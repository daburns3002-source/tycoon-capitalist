--!strict
--[[
	Plot ownership: one plot per player, built on join and torn down on leave.

	Holds the per-player records in a table keyed by user id rather than a single "current plot"
	global, so the step to shared plots in Phase 8 is a change to who may act on a record, not a
	rewrite of where it lives.

	Phase 2 has no persistence: a plot is fresh every join. Phase 5 adds DataStore profiles, and
	the seam is deliberately narrow -- `PlotService.load` is where a saved profile will be
	deserialised instead of a new record being created.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Offline = require(script.Parent.Parent.Tick.Offline)
local PlotBuilder = require(script.Parent.Parent.World.PlotBuilder)
local PlotState = require(script.Parent.PlotState)
local Profiles = require(script.Parent.Parent.Data.Profiles)
local Serialise = require(script.Parent.Parent.Data.Serialise)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)

type PlotState = Types.PlotState

export type Entry = {
	state: PlotState,
	world: PlotBuilder.Plot,
	index: number,
	panelOpen: boolean,
	lastBuyMode: Types.BuyMode,
	--[[
		False when the profile could not be read or locked. The player still plays; nothing is
		written for them. A failed read must never be allowed to overwrite a good profile.
	]]
	canSave: boolean,
	--[[ What the managers earned while away, for the welcome-back panel. Cleared once shown. ]]
	offline: Offline.Result?,
}

local PlotService = {}

local entries: { [number]: Entry } = {}
local usedIndices: { [number]: boolean } = {}
local container: Folder? = nil

local function ensureContainer(): Folder
	local existing = container
	if existing then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "Plots"
	folder.Parent = Workspace
	container = folder
	return folder
end

--[[ Lowest free plot index, so a leaver's slot is reused rather than the row growing forever. ]]
local function nextIndex(): number
	local index = 0
	while usedIndices[index] do
		index += 1
	end
	return index
end

--[[
	Create a plot for a player.

	Phase 5 replaces the `PlotState.new` call with a profile load; everything downstream of
	here already treats the record as opaque state, so nothing else changes.
]]
function PlotService.load(player: Player): Entry
	local existing = entries[player.UserId]
	if existing then
		return existing
	end

	local index = nextIndex()
	usedIndices[index] = true

	--[[
		Reads the profile, takes the session lock, and settles the absence before the player can
		touch anything. Yields -- the caller runs this off the PlayerAdded thread.
	]]
	local userId = player.UserId
	local result = Profiles.load(userId)
	local plot, savedAt = Serialise.load(result.stored, function()
		return PlotState.new(userId)
	end)

	-- Derived from what was loaded, never stored: unit counts and owned upgrades are the truth,
	-- and a stored multiplier could come back out of step with them.
	PlotState.recomputeMultipliers(plot)

	local offline: Offline.Result? = nil
	if savedAt ~= nil then
		local settled = Offline.settle(plot, savedAt, os.time())
		if settled.businesses > 0 then
			offline = settled
		end
	end

	local entry: Entry = {
		state = plot,
		world = PlotBuilder.build(index, PlotState.unlocked, ensureContainer()),
		index = index,
		panelOpen = false,
		lastBuyMode = "x1",
		canSave = result.canSave,
		offline = offline,
	}

	if not result.canSave then
		warn(`[plots] {player.Name} is playing unsaved: {result.reason or "unknown"}`)
	end

	entry.world.model:SetAttribute("OwnerUserId", player.UserId)

	for id, state in entry.state.businesses do
		PlotBuilder.updateBuilding(entry.world, id, state.unitsOwned)
	end

	entries[player.UserId] = entry
	return entry
end

function PlotService.get(player: Player): Entry?
	return entries[player.UserId]
end

--[[
	Tear a plot down.

	The model is destroyed and the index freed. Every instance created for a plot hangs off its
	model, so one Destroy is the whole cleanup path -- CLAUDE.md's rule that anything created
	has a destroy path.
]]
--[[
	Write a plot to its profile.

	`releaseLock` is true when the player is leaving. Refuses when this session never held the
	lock, so a server that could not read a profile can never write over it.
]]
function PlotService.save(userId: number, entry: Entry, releaseLock: boolean): boolean
	if not entry.canSave then
		return false
	end
	return Profiles.save(userId, Serialise.save(entry.state), releaseLock)
end

function PlotService.unload(player: Player): ()
	local entry = entries[player.UserId]
	if entry == nil then
		return
	end

	PlotService.save(player.UserId, entry, true)

	entry.world.model:Destroy()
	usedIndices[entry.index] = nil
	entries[player.UserId] = nil
end

--[[ Iterate live plots. Used by the production tick. ]]
function PlotService.all(): { [number]: Entry }
	return entries
end

--[[
	Put a player's character on their own plot.

	Called on spawn rather than relying on a SpawnLocation, because the plot is built at a
	position derived from its index and a static spawn would put everyone in the same place.
]]
function PlotService.teleportToPlot(player: Player, entry: Entry): ()
	local character = player.Character
	if character == nil then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end

	character:PivotTo(CFrame.new(entry.world.spawnPosition))
end

--[[
	Whether this player may act on this plot.

	Trivial while plots are solo, and deliberately a function anyway: every remote handler asks
	this rather than assuming, so Phase 8's shared plots change one predicate instead of every
	call site. An idle game is pure currency, and ownership is the check that stops one player
	spending another's.
]]
function PlotService.mayAct(player: Player, entry: Entry): boolean
	return entry.state.userId == player.UserId
end

function PlotService.playerFor(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

return table.freeze(PlotService)
