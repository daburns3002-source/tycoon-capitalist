--!strict
--[[
	Angels -- the prestige layer.

	Resetting the plot converts lifetime earnings into Angel Investors, each worth +2% to all
	profits forever. Angels are the only thing that survives a reset, so they are the reason a
	second run reaches the old wall in a fraction of the time.

	The formula:

	    angels = floor( sqrt(lifetimeEarnings / divisor) - sqrt(earningsBeforeThisRun / divisor) )
	    divisor = 400e9 / 9  (Earth and Moon; Mars uses 100e9 / 9)

	Two consequences worth keeping in mind, because both are counter-intuitive and both are
	load-bearing:

	* The requirement is tied to *lifetime* earnings, not to how many angels you hold. Spending
	  angels never makes the next one cheaper.
	* Because it is a square root, every thousand-fold increase in lifetime earnings multiplies
	  angels by about 31.6. The reference points alternate: 1e15 gives exactly 150, 1e18 gives
	  4,743, 1e21 gives 150,000, 1e24 gives 4,743,416.

	The first angel lands at about $44.44 billion lifetime earnings.

	Pure module: no services, no clock, no RNG.
]]

local BigNumber = require(script.Parent.BigNumber)
local Types = require(script.Parent.Parent.Types)

type BigNumber = Types.BigNumber

local Angels = {}

--[[ 400e9/9 for Earth and the Moon. Mars divides 100e9 by 9 instead. ]]
local EARTH_DIVISOR = BigNumber.fromNumber(400e9 / 9)
local MARS_DIVISOR = BigNumber.fromNumber(100e9 / 9)

Angels.earthDivisor = EARTH_DIVISOR
Angels.marsDivisor = MARS_DIVISOR

--[[ Each angel is worth two percent, before any angel-upgrade effectiveness bonus. ]]
Angels.profitPerAngel = 0.02

--[[
	Angels the player holds in total for a given lifetime-earnings figure, ignoring resets.

	This is the raw `sqrt(lifetime / divisor)` term. Mostly useful for a "what would I get"
	projection; the actual payout on reset is `gainOnReset`.
]]
function Angels.totalForEarnings(lifetimeEarnings: BigNumber, divisor: BigNumber?): number
	if BigNumber.isZero(lifetimeEarnings) or lifetimeEarnings.mantissa < 0 then
		return 0
	end

	local ratio = BigNumber.div(lifetimeEarnings, divisor or EARTH_DIVISOR)
	local root = BigNumber.sqrt(ratio)
	return BigNumber.toNumber(root)
end

--[[
	Angels gained by resetting now.

	`earningsBeforeThisRun` is the lifetime total as it stood at the previous reset, so the
	difference of the two roots is what this run earned. Floored, because a run that gets 1.9
	angels' worth of the way yields one angel.

	There is a second branch in the source game: if the player has sacrificed more angels than
	`sqrt(earningsBeforeThisRun / divisor)` -- that is, spent into the credit built up by
	earlier runs -- the payout becomes `sqrt(lifetime / divisor) - lifetimeAngelsSacrificed`
	instead. Without it, heavy spending on angel upgrades would silently refund itself on the
	next reset.
]]
function Angels.gainOnReset(
	lifetimeEarnings: BigNumber,
	earningsBeforeThisRun: BigNumber,
	angelsSacrificed: number,
	divisor: BigNumber?
): number
	local effectiveDivisor = divisor or EARTH_DIVISOR

	local totalRoot = Angels.totalForEarnings(lifetimeEarnings, effectiveDivisor)
	local previousRoot = Angels.totalForEarnings(earningsBeforeThisRun, effectiveDivisor)

	local gain: number
	if angelsSacrificed > previousRoot then
		gain = totalRoot - angelsSacrificed
	else
		gain = totalRoot - previousRoot
	end

	return math.max(math.floor(gain), 0)
end

--[[
	Lifetime earnings needed for the next whole angel beyond `currentTotal`.

	Inverts the formula: `(n + 1)^2 * divisor`. Drives the "next angel at $X" readout, which is
	what makes a player decide to push one more business rather than reset now.
]]
function Angels.earningsForNextAngel(currentTotal: number, divisor: BigNumber?): BigNumber
	local target = math.floor(currentTotal) + 1
	local squared = BigNumber.fromNumber(target * target)
	return BigNumber.mul(squared, divisor or EARTH_DIVISOR)
end

--[[
	Whether resetting is worth it yet.

	Not a rule from the source game -- it is the community's rule of thumb, surfaced so the
	reset button can discourage a player from throwing away a run for two angels. The reset
	flow still lets them.
]]
function Angels.isResetWorthwhile(gain: number, currentAngels: number): boolean
	if currentAngels <= 0 then
		return gain >= 1
	end
	return gain >= currentAngels * 0.1
end

return table.freeze(Angels)
