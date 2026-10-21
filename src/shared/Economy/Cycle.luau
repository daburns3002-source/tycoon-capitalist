--!strict
--[[
	Cycle -- how long a business takes to pay out.

	This is the best mechanic in the source game and the one most worth getting exactly right.
	A business's cycle time halves when its own unit count reaches 25, 50, 100, 200, 300 or
	400 -- and halves again, for *every* business, each time all ten have crossed one of those
	marks. Twelve halvings is the cap, so the floor is 1/4096 of the initial cycle: the Oil
	Company's ten hours and fourteen minutes become exactly nine seconds.

	The all-business tier is what makes the mid-game feel like it opens up. A player who pushes
	one business to 400 gets one business six times faster; a player who brings all ten to 25
	gets all ten twice as fast on top of whatever they had. Reproducing only the per-business
	half of this would quietly flatten the whole curve.

	Pure module: no services, no clock, no RNG.
]]

local Businesses = require(script.Parent.Parent.Config.Businesses)
local Types = require(script.Parent.Parent.Types)

type BusinessConfig = Types.BusinessConfig

local Cycle = {}

--[[ How many milestones `units` has reached. ]]
local function milestonesReached(units: number): number
	local count = 0
	for _, threshold in Businesses.cycleMilestones do
		if units >= threshold then
			count += 1
		end
	end
	return count
end

Cycle.milestonesReached = milestonesReached

--[[
	The lowest milestone count across all ten businesses.

	The all-business bonus is granted per mark that *every* business has crossed, so it is
	governed by the weakest one. `unitsById` must cover every configured business; a missing
	entry counts as zero, which is the correct reading of "not yet bought".
]]
function Cycle.globalMilestonesReached(unitsById: { [Types.BusinessId]: number }): number
	local lowest = math.huge

	for _, config in Businesses.list do
		local units = unitsById[config.id] or 0
		local reached = milestonesReached(units)
		if reached < lowest then
			lowest = reached
		end
		if lowest == 0 then
			-- Nothing can bring it below zero, so stop early.
			return 0
		end
	end

	return if lowest == math.huge then 0 else lowest
end

--[[
	Total halvings applying to one business: its own milestones plus the all-business ones,
	capped at twelve.
]]
function Cycle.halvings(ownUnits: number, globalMilestones: number): number
	local total = milestonesReached(ownUnits) + globalMilestones
	return math.min(total, Businesses.maxCycleHalvings)
end

--[[
	A business's current cycle length in seconds.

	`speedMultiplier` is for effects outside the milestone system -- an event boost, a
	Phase 9 product. It defaults to 1 and divides the result, so 2 means twice as fast.
]]
function Cycle.duration(
	config: BusinessConfig,
	ownUnits: number,
	globalMilestones: number,
	speedMultiplier: number?
): number
	local halvings = Cycle.halvings(ownUnits, globalMilestones)
	local seconds = config.cycleSeconds / 2 ^ halvings

	local multiplier = speedMultiplier or 1
	if multiplier ~= 1 then
		if multiplier <= 0 then
			error("Cycle.duration: speedMultiplier must be positive", 2)
		end
		seconds /= multiplier
	end

	return seconds
end

--[[
	The next unit count at which this business's own cycle halves, or nil if it has crossed
	every milestone.

	The UI uses this for the "next milestone" readout, which is most of why a player keeps
	buying one more unit.
]]
function Cycle.nextMilestone(ownUnits: number): number?
	for _, threshold in Businesses.cycleMilestones do
		if ownUnits < threshold then
			return threshold
		end
	end
	return nil
end

--[[
	The next all-business milestone and how many units the weakest business still needs.

	Returns nil when every business has crossed every mark.
]]
function Cycle.nextGlobalMilestone(
	unitsById: { [Types.BusinessId]: number }
): (number?, Types.BusinessId?)
	local reached = Cycle.globalMilestonesReached(unitsById)
	local target = Businesses.cycleMilestones[reached + 1]
	if target == nil then
		return nil, nil
	end

	local laggard: Types.BusinessId? = nil
	local lowestUnits = math.huge
	for _, config in Businesses.list do
		local units = unitsById[config.id] or 0
		if units < target and units < lowestUnits then
			lowestUnits = units
			laggard = config.id
		end
	end

	return target, laggard
end

return table.freeze(Cycle)
