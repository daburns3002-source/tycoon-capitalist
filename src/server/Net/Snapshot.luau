--!strict
--[[
	Builds the state the client is allowed to see.

	Every number the panel displays is computed here, on the server, including the price of the
	currently selected buy mode and how many units the player can afford. The client never
	prices anything -- if it did, a modified client could show itself a cheaper number, click
	buy, and the mismatch would have to be caught downstream anyway. Computing it once in the
	one authoritative place is both safer and less code.

	BigNumbers cross the wire as their mantissa/exponent table, which replicates as a plain
	table with no precision lost and no custom serialisation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Angels = require(Shared.Economy.Angels)
local BigNumber = require(Shared.Economy.BigNumber)
local Businesses = require(Shared.Config.Businesses)
local Cost = require(Shared.Economy.Cost)
local Cycle = require(Shared.Economy.Cycle)
local Types = require(Shared.Types)
local Upgrades = require(Shared.Config.Upgrades)

local PlotService = require(script.Parent.Parent.Plot.PlotService)
local PlotState = require(script.Parent.Parent.Plot.PlotState)
local Production = require(script.Parent.Parent.Tick.Production)

local Snapshot = {}

--[[
	One business row.

	`cycleElapsed` is seconds into the cycle rather than a fill fraction, so the client can
	interpolate the bar locally and a snapshot every few hundred milliseconds still renders
	smoothly on a phone.
]]
local function businessSnapshot(
	entry: PlotService.Entry,
	id: Types.BusinessId,
	now: number
): Types.BusinessSnapshot
	local plot = entry.state
	local state = plot.businesses[id]
	local config = Businesses.byId[id]

	local quantity = PlotState.quantityForMode(plot, id, entry.lastBuyMode)
	-- "max" with no money resolves to zero units, which would price at nothing. Show the price
	-- of one instead, so the button reads as a goal rather than as free.
	local pricedQuantity = math.max(quantity, 1)

	return {
		id = id,
		unitsOwned = state.unitsOwned,
		hasManager = state.hasManager,
		cycleSeconds = PlotState.cycleSeconds(plot, id),
		cycleElapsed = Production.cycleElapsed(plot, id, now),
		isCycling = state.cycleStartedAt ~= nil,
		-- Compared for equality only, so the client can tell a continuing cycle from a new one.
		-- The server's clock is meaningless over there; its *changes* are not.
		cycleToken = state.cycleStartedAt or 0,
		payoutPerCycle = PlotState.payout(plot, id),
		nextCostFor = Cost.bulkCost(config, state.unitsOwned, pricedQuantity),
		affordableAtMode = quantity,
		nextMilestone = Cycle.nextMilestone(state.unitsOwned),
	}
end

--[[ The whole panel's state. ]]
function Snapshot.build(entry: PlotService.Entry, now: number): Types.PlotSnapshot
	local plot = entry.state

	local businesses: { Types.BusinessSnapshot } = {}
	for _, id in PlotState.unlocked do
		if plot.businesses[id] ~= nil then
			table.insert(businesses, businessSnapshot(entry, id, now))
		end
	end

	table.sort(businesses, function(a, b)
		return Businesses.byId[a.id].order < Businesses.byId[b.id].order
	end)

	--[[
		Upgrades the player has not bought yet, plus the ones they have.

		Affordability is decided here rather than on the client for the same reason prices are:
		one authoritative answer, and no way for a modified client to show itself a cheaper
		number and then be surprised when the purchase is refused.
	]]
	local upgrades: { Types.UpgradeSnapshot } = {}
	for _, config in Upgrades.list do
		table.insert(upgrades, {
			id = config.id,
			owned = plot.upgradesOwned[config.id] == true,
			affordable = not BigNumber.lt(plot.cash, config.cost),
		})
	end

	return {
		cash = plot.cash,
		lifetimeEarnings = plot.lifetimeEarnings,
		angels = plot.angels,
		buyMode = entry.lastBuyMode,
		pendingAngels = PlotState.pendingAngels(plot),
		nextAngelAt = Angels.earningsForNextAngel(Angels.totalForEarnings(plot.lifetimeEarnings)),
		globalMilestones = PlotState.globalMilestones(plot),
		businesses = businesses,
		upgrades = upgrades,
	}
end

return table.freeze(Snapshot)
