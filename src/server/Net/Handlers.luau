--!strict
--[[
	Remote handlers. The only place a client can influence anything.

	Every handler follows the same shape, and the order matters:

	  1. validate the argument's *type* -- a client can send anything, including nil, a table,
	     or a 400-character string
	  2. validate it against the allowed set -- an unknown business id is a rejection, not a nil
	     index that errors out mid-handler
	  3. check the player owns the plot they are acting on
	  4. do the thing, using only server state and the server's clock
	  5. push a snapshot

	Assume every client is hostile. An idle game is pure currency, so it is pure exploit
	surface: the attacks worth closing are claiming a cycle finished early, buying at a price
	the client chose, and spending money the server never credited. None of those values are
	accepted from the client at all -- that is the design, not a check.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Businesses = require(Shared.Config.Businesses)
local Cost = require(Shared.Economy.Cost)
local Remotes = require(Shared.Net.Remotes)
local Types = require(Shared.Types)
local Upgrades = require(Shared.Config.Upgrades)

local PlotBuilder = require(script.Parent.Parent.World.PlotBuilder)
local PlotService = require(script.Parent.Parent.Plot.PlotService)
local PlotState = require(script.Parent.Parent.Plot.PlotState)
local Production = require(script.Parent.Parent.Tick.Production)
local Snapshot = require(script.Parent.Snapshot)

local Handlers = {}

--[[
	Allowed buy modes, as a lookup that both validates and types.

	A client sends a string; this maps it to the typed value or to nil. One table does the
	whitelist and the conversion together, so there is no path where a validated string is
	cast and trusted separately -- which is exactly where a validation bug would hide.
]]
--[[
	A note on how buy modes are validated below.

	The whitelist is an inline if-chain assigning literals to an explicitly annotated local,
	rather than the obvious lookup table or a small parse helper. That is deliberate and it is
	a workaround, so it is worth writing down before someone tidies it into a bug.

	In the pinned luau-lsp, a string-literal union loses its literalness in two places:
	narrowing an optional one widens it to plain `string` (so `local m = TABLE[raw]; if m == nil
	then return end` discards the type), and a declared multi-return annotation is not applied
	to the inferred branches (so a `(BuyMode, boolean)` helper returns a union of four widened
	strings). Either way every downstream call stops type-checking.

	Assigning a literal to a field or a local with an explicit annotation involves no inference
	and no narrowing, so it types correctly. It also happens to be the most legible spelling of
	a whitelist, which is the one thing in this file that has to be obviously right on sight.
]]
local function applyBuyMode(entry: PlotService.Entry, raw: unknown): boolean
	if raw == "x1" then
		entry.lastBuyMode = "x1"
	elseif raw == "x10" then
		entry.lastBuyMode = "x10"
	elseif raw == "x100" then
		entry.lastBuyMode = "x100"
	elseif raw == "max" then
		entry.lastBuyMode = "max"
	else
		return false
	end

	return true
end

local function reject(player: Player, intent: string, reason: string): ()
	Remotes.get(Remotes.toClient.IntentRejected):FireClient(player, intent, reason)
end

--[[
	Tell a joining player what their managers earned while away.

	Cleared after sending so a respawn does not replay it -- the money was credited once, and
	showing the banner again would read as earning it twice.
]]
function Handlers.pushWelcomeBack(player: Player, entry: PlotService.Entry): ()
	local offline = entry.offline
	if offline == nil then
		return
	end
	entry.offline = nil

	Remotes.get(Remotes.toClient.WelcomeBack)
		:FireClient(player, offline.seconds, offline.earned, offline.businesses)
end

function Handlers.pushSnapshot(player: Player, entry: PlotService.Entry): ()
	Remotes.get(Remotes.toClient.PlotSnapshot):FireClient(player, Snapshot.build(entry, os.clock()))
end

--[[
	Resolve a player's plot and a business id in one place.

	Returns nil on anything unexpected rather than erroring, because an error in a remote
	handler is a free way for a client to fill the server's log.
]]
local function resolve(
	player: Player,
	intent: string,
	businessId: unknown
): (PlotService.Entry?, Types.BusinessId?)
	local entry = PlotService.get(player)
	if entry == nil then
		reject(player, intent, "no plot")
		return nil, nil
	end
	if not PlotService.mayAct(player, entry) then
		reject(player, intent, "not your plot")
		return nil, nil
	end

	if typeof(businessId) ~= "string" then
		reject(player, intent, "bad business id")
		return nil, nil
	end

	local id = businessId :: Types.BusinessId
	if Businesses.byId[id] == nil then
		reject(player, intent, "unknown business")
		return nil, nil
	end
	if entry.state.businesses[id] == nil then
		reject(player, intent, "business not unlocked")
		return nil, nil
	end

	return entry, id
end

--[[
	"I clicked a business row."

	The client does not say when the cycle started or when it ends; it only says which business
	was clicked. `Production.startCycle` refuses if one is already running, so clicking faster
	cannot produce money faster -- which is the obvious first thing anyone would try.
]]
local function onStartCycle(player: Player, businessId: unknown): ()
	local intent = Remotes.toServer.StartCycle
	local entry, id = resolve(player, intent, businessId)
	if entry == nil or id == nil then
		return
	end

	if not Production.startCycle(entry.state, id, os.clock()) then
		reject(player, intent, "already running")
		return
	end

	Handlers.pushSnapshot(player, entry)
end

--[[
	"Buy units of this business."

	The client sends a mode, never a quantity and never a price. The server resolves the mode
	to a quantity against its own cash figure, prices it from the config, and spends -- so a
	client that asks for "max" with no money buys nothing rather than buying at a price it
	invented.
]]
local function onBuyUnits(player: Player, businessId: unknown, mode: unknown): ()
	local intent = Remotes.toServer.BuyUnits
	local entry, id = resolve(player, intent, businessId)
	if entry == nil or id == nil then
		return
	end

	if not applyBuyMode(entry, mode) then
		reject(player, intent, "bad buy mode")
		return
	end

	local plot = entry.state
	local state = plot.businesses[id]
	local config = Businesses.byId[id]

	local quantity = PlotState.quantityForMode(plot, id, entry.lastBuyMode)
	if quantity <= 0 then
		reject(player, intent, "cannot afford any")
		return
	end

	local price = Cost.bulkCost(config, state.unitsOwned, quantity)
	if not PlotState.trySpend(plot, price) then
		-- Only reachable for a fixed mode (x10 with enough for three, say). "max" is derived
		-- from the balance and so is always affordable by construction.
		reject(player, intent, "cannot afford that many")
		return
	end

	state.unitsOwned += quantity
	if state.unitsOwned > Businesses.maxUnits then
		state.unitsOwned = Businesses.maxUnits
	end

	--[[
		Unit counts gate the unlock ladder, so buying units can earn a profit multiplier. The
		multipliers are derived, so they have to be recomputed here as well as on an upgrade
		purchase -- miss this and crossing 500 units would light up the unlock in the UI while
		paying nothing.
	]]
	PlotState.recomputeMultipliers(plot)

	PlotBuilder.updateBuilding(entry.world, id, state.unitsOwned)
	Handlers.pushSnapshot(player, entry)
end

--[[
	"Hire this business's manager."

	Costs cash, is permanent for the run, and from then on the business restarts its own cycle
	forever -- the tick does that, so nothing here has to. Refuses when the business is not
	owned yet (there is nothing to manage), when a manager is already hired (so a client cannot
	be charged twice), and when the money is not there.
]]
local function onHireManager(player: Player, businessId: unknown): ()
	local intent = Remotes.toServer.HireManager
	local entry, id = resolve(player, intent, businessId)
	if entry == nil or id == nil then
		return
	end

	local plot = entry.state
	local state = plot.businesses[id]
	local config = Businesses.byId[id]

	if state.unitsOwned <= 0 then
		reject(player, intent, "buy one first")
		return
	end
	if state.hasManager then
		reject(player, intent, "already hired")
		return
	end
	if not PlotState.trySpend(plot, config.managerCost) then
		reject(player, intent, "cannot afford")
		return
	end

	state.hasManager = true
	-- The tick picks it up from here and keeps it running.
	Handlers.pushSnapshot(player, entry)
end

--[[
	"Buy this cash upgrade."

	Permanent for the run and bought once. The multipliers are recomputed from the owned set
	rather than nudged, so there is no path where a double purchase doubles a multiplier.
]]
local function onBuyUpgrade(player: Player, upgradeId: unknown): ()
	local intent = Remotes.toServer.BuyUpgrade
	local entry = PlotService.get(player)
	if entry == nil then
		reject(player, intent, "no plot")
		return
	end
	if not PlotService.mayAct(player, entry) then
		reject(player, intent, "not your plot")
		return
	end
	if typeof(upgradeId) ~= "string" then
		reject(player, intent, "bad upgrade id")
		return
	end

	local config = Upgrades.byId[upgradeId]
	if config == nil then
		reject(player, intent, "unknown upgrade")
		return
	end

	local plot = entry.state
	if plot.upgradesOwned[config.id] then
		reject(player, intent, "already owned")
		return
	end
	if not PlotState.trySpend(plot, config.cost) then
		reject(player, intent, "cannot afford")
		return
	end

	plot.upgradesOwned[config.id] = true
	PlotState.recomputeMultipliers(plot)
	Handlers.pushSnapshot(player, entry)
end

--[[
	"Reset for Angel Investors."

	Refuses when the run would pay no angels. A confirmation dialog on the client is a courtesy;
	this is the rule. Wiping a player's entire run for nothing is the single most damaging thing
	this game could do to someone, so it is refused at the authoritative end rather than trusted
	to a prompt that a modified client simply would not show.
]]
local function onPerformReset(player: Player): ()
	local intent = Remotes.toServer.PerformReset
	local entry = PlotService.get(player)
	if entry == nil then
		reject(player, intent, "no plot")
		return
	end
	if not PlotService.mayAct(player, entry) then
		reject(player, intent, "not your plot")
		return
	end

	local plot = entry.state
	if PlotState.pendingAngels(plot) <= 0 then
		reject(player, intent, "no angels yet")
		return
	end

	PlotState.reset(plot)

	-- The plot is bare again, so every building goes back to hidden.
	for id, state in plot.businesses do
		PlotBuilder.updateBuilding(entry.world, id, state.unitsOwned)
	end

	Handlers.pushSnapshot(player, entry)
end

--[[
	"I selected a buy mode."

	The server holds the selection because it prices the selected batch for every row. Pushing a
	snapshot straight back is the whole point: the new prices and affordable counts arrive in one
	round trip, so the buttons update without the client ever pricing anything itself.
]]
local function onSetBuyMode(player: Player, mode: unknown): ()
	local intent = Remotes.toServer.SetBuyMode
	local entry = PlotService.get(player)
	if entry == nil then
		reject(player, intent, "no plot")
		return
	end
	if not PlotService.mayAct(player, entry) then
		reject(player, intent, "not your plot")
		return
	end

	if not applyBuyMode(entry, mode) then
		reject(player, intent, "bad buy mode")
		return
	end

	Handlers.pushSnapshot(player, entry)
end

--[[
	"I opened or closed the board."

	Lets the tick skip pushing panel detail to a client that is not looking at the panel. Purely
	an optimisation -- the server does not trust it for anything, and a client that lies about
	it only affects how often it hears from us.
]]
local function onSetPanelOpen(player: Player, isOpen: unknown): ()
	local entry = PlotService.get(player)
	if entry == nil then
		return
	end
	if typeof(isOpen) ~= "boolean" then
		reject(player, Remotes.toServer.SetPanelOpen, "bad flag")
		return
	end

	entry.panelOpen = isOpen
	if isOpen then
		Handlers.pushSnapshot(player, entry)
	end
end

function Handlers.bind(): ()
	Remotes.get(Remotes.toServer.StartCycle).OnServerEvent:Connect(onStartCycle)
	Remotes.get(Remotes.toServer.BuyUnits).OnServerEvent:Connect(onBuyUnits)
	Remotes.get(Remotes.toServer.SetBuyMode).OnServerEvent:Connect(onSetBuyMode)
	Remotes.get(Remotes.toServer.HireManager).OnServerEvent:Connect(onHireManager)
	Remotes.get(Remotes.toServer.BuyUpgrade).OnServerEvent:Connect(onBuyUpgrade)
	Remotes.get(Remotes.toServer.PerformReset).OnServerEvent:Connect(onPerformReset)
	Remotes.get(Remotes.toServer.SetPanelOpen).OnServerEvent:Connect(onSetPanelOpen)
end

--[[ Tell a client a cycle paid out, so it can pop the number and play the sound. ]]
function Handlers.notifyPaid(player: Player, payments: { Production.Payment }): ()
	if #payments == 0 then
		return
	end
	Remotes.get(Remotes.toClient.CyclePaid):FireClient(player, payments)
end

function Handlers.pushTo(userId: number, entry: PlotService.Entry): ()
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return
	end
	Handlers.pushSnapshot(player, entry)
end

return table.freeze(Handlers)
