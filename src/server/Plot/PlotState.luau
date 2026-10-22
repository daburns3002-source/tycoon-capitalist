--!strict
--[[
	Plot records -- the authoritative state of one player's game.

	Keyed per player and passed explicitly. There is no module-level "current plot" here even
	though the game is solo, because retrofitting shared plots or cross-server ranked onto
	singleton state is how this kind of project dies in Phase 8. CLAUDE.md, non-negotiable 5.

	This module constructs and mutates records. It does not decide economics -- every number
	comes from the pure modules in Shared.Economy -- and it does not touch the network or the
	world.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Angels = require(Shared.Economy.Angels)
local BigNumber = require(Shared.Economy.BigNumber)
local Businesses = require(Shared.Config.Businesses)
local Cost = require(Shared.Economy.Cost)
local Cycle = require(Shared.Economy.Cycle)
local Revenue = require(Shared.Economy.Revenue)
local Types = require(Shared.Types)
local Upgrades = require(Shared.Config.Upgrades)

type BigNumber = Types.BigNumber
type PlotState = Types.PlotState
type BusinessState = Types.BusinessState

local PlotState = {}

--[[
	Every business the panel shows, in cost order.

	All ten, as the source game does: the ones you cannot afford yet are still listed, greyed,
	with their price on the buy button. Seeing the Oil Company sitting there at twenty-five
	billion from the first minute is a large part of why the early game pulls -- hiding it until
	it is affordable would remove the thing being aimed at.

	A business with zero units earns nothing and runs no cycle; `Production.advance` and
	`Revenue.perCycle` both already treat zero as zero, so "locked" needs no separate state.
]]
local LISTED: { Types.BusinessId } = {}
for _, config in Businesses.list do
	table.insert(LISTED, config.id)
end

PlotState.unlocked = LISTED

local function newBusinessState(): BusinessState
	return {
		unitsOwned = 0,
		hasManager = false,
		hasAccountant = false,
		cycleStartedAt = nil,
		profitMultiplier = 1,
	}
end

--[[
	A fresh plot.

	The player starts owning one free Lemonade Stand, exactly as the source game does, which is
	why the first purchase is unit 2 at $4 rather than unit 1 at $3.74.
]]
function PlotState.new(userId: number): PlotState
	local businesses: { [Types.BusinessId]: BusinessState } = {}
	for _, id in LISTED do
		businesses[id] = newBusinessState()
	end

	businesses.LemonadeStand.unitsOwned = 1

	return {
		userId = userId,
		cash = BigNumber.zero,
		lifetimeEarnings = BigNumber.zero,
		earningsBeforeThisRun = BigNumber.zero,
		angels = 0,
		angelsSacrificed = 0,
		allProfitMultiplier = 1,
		angelEffectiveness = 1,
		businesses = businesses,
		upgradesOwned = {},
	}
end

--[[
	Recompute every multiplier from the set of owned upgrades.

	Derived rather than incremented on purchase. Incrementing works right up until something
	needs to remove an upgrade -- an angel reset, a refund, a migration that drops one -- and
	then the multipliers are silently wrong with no way to notice. Recomputing from the owned
	set cannot drift, and it is 35 multiplications on a purchase, which is free.
]]
function PlotState.recomputeMultipliers(plot: PlotState): ()
	local allMultiplier = 1
	local effectiveness = 1
	local perBusiness: { [Types.BusinessId]: number } = {}

	for _, config in Upgrades.list do
		if not plot.upgradesOwned[config.id] then
			continue
		end

		if config.kind == "angelEffectiveness" then
			effectiveness += config.multiplier
		elseif config.target == "all" then
			allMultiplier *= config.multiplier
		else
			local current = perBusiness[config.target] or 1
			perBusiness[config.target] = current * config.multiplier
		end
	end

	plot.allProfitMultiplier = allMultiplier
	plot.angelEffectiveness = effectiveness
	for id, state in plot.businesses do
		state.profitMultiplier = perBusiness[id] or 1
	end
end

--[[ Unit counts by business id, for the all-business milestone calculation. ]]
function PlotState.unitsById(plot: PlotState): { [Types.BusinessId]: number }
	local units: { [Types.BusinessId]: number } = {}
	for id, state in plot.businesses do
		units[id] = state.unitsOwned
	end
	return units
end

function PlotState.globalMilestones(plot: PlotState): number
	return Cycle.globalMilestonesReached(PlotState.unitsById(plot))
end

--[[ A business's current cycle length, with every milestone halving applied. ]]
function PlotState.cycleSeconds(plot: PlotState, id: Types.BusinessId): number
	local config = Businesses.byId[id]
	local state = plot.businesses[id]
	if config == nil or state == nil then
		error(`PlotState.cycleSeconds: unknown business {id}`, 2)
	end

	return Cycle.duration(config, state.unitsOwned, PlotState.globalMilestones(plot))
end

--[[ What one completed cycle of this business pays right now. ]]
function PlotState.payout(plot: PlotState, id: Types.BusinessId): BigNumber
	local config = Businesses.byId[id]
	local state = plot.businesses[id]
	if config == nil or state == nil then
		error(`PlotState.payout: unknown business {id}`, 2)
	end

	return Revenue.perCycle(
		config,
		state.unitsOwned,
		state.profitMultiplier,
		plot.allProfitMultiplier,
		plot.angels,
		plot.angelEffectiveness
	)
end

--[[
	Credit money.

	Both the spendable balance and the lifetime total move together, and lifetime earnings only
	ever go up -- it is the basis of the angel formula, so a spend must never touch it.
]]
function PlotState.credit(plot: PlotState, amount: BigNumber): ()
	if BigNumber.isZero(amount) or amount.mantissa < 0 then
		return
	end

	plot.cash = BigNumber.add(plot.cash, amount)
	plot.lifetimeEarnings = BigNumber.add(plot.lifetimeEarnings, amount)
end

--[[
	Spend money, if there is enough.

	Returns false and changes nothing when the player cannot afford it, so a caller can treat a
	failed purchase as a no-op rather than having to check first and risk a race.
]]
function PlotState.trySpend(plot: PlotState, amount: BigNumber): boolean
	if amount.mantissa < 0 then
		return false
	end
	if BigNumber.lt(plot.cash, amount) then
		return false
	end

	plot.cash = BigNumber.sub(plot.cash, amount)
	return true
end

--[[ How many units a buy mode resolves to, given what the player can actually afford. ]]
function PlotState.quantityForMode(
	plot: PlotState,
	id: Types.BusinessId,
	mode: Types.BuyMode
): number
	local config = Businesses.byId[id]
	local state = plot.businesses[id]
	if config == nil or state == nil then
		return 0
	end

	if mode == "max" then
		return Cost.maxAffordable(config, state.unitsOwned, plot.cash, Businesses.maxUnits)
	end

	local requested = if mode == "x1" then 1 elseif mode == "x10" then 10 else 100
	local headroom = Businesses.maxUnits - state.unitsOwned
	return math.min(requested, math.max(headroom, 0))
end

--[[
	Angels this plot would gain by resetting now. Phase 6 consumes this; the panel shows it
	from Phase 2 so the number is visible long before the button exists.
]]
function PlotState.pendingAngels(plot: PlotState): number
	return Angels.gainOnReset(
		plot.lifetimeEarnings,
		plot.earningsBeforeThisRun,
		plot.angelsSacrificed
	)
end

return table.freeze(PlotState)
