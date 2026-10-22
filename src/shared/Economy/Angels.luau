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

--[[
	The divisor, kept as a fraction rather than as one number.

	The formula divides by 400e9/9 on Earth and the Moon, and by 100e9/9 on Mars. Precomputing
	that quotient loses the answer: 400e9/9 is not representable in binary, so it lands on a
	mantissa of 4.4444444444444446, and dividing 1e15 by it gives 22499.999999999996 instead of
	22500. The square root is then 149.99999999999997, which floors to **149 angels instead of
	150** -- an off-by-one the player would see on every reset at a round number.

	Dividing by the numerator and the denominator separately keeps it exact: 1e15 x 9 is 9e15
	exactly, 9e15 / 400e9 is 22500 exactly, and sqrt(22500) is 150 exactly. Both operands are
	powers of ten times a small integer, so every step is representable.

	Found by running the suite in Studio. The Python verifier could never have caught it -- it
	works in Decimal, where the precomputed quotient is exact.
]]
export type Divisor = {
	scale: number,
	base: BigNumber,
}

local EARTH_DIVISOR: Divisor = table.freeze({
	scale = 9,
	base = BigNumber.fromNumber(400e9),
})

local MARS_DIVISOR: Divisor = table.freeze({
	scale = 9,
	base = BigNumber.fromNumber(100e9),
})

Angels.earthDivisor = EARTH_DIVISOR
Angels.marsDivisor = MARS_DIVISOR

--[[ Each angel is worth two percent, before any angel-upgrade effectiveness bonus. ]]
Angels.profitPerAngel = 0.02

--[[
	Angels the player holds in total for a given lifetime-earnings figure, ignoring resets.

	This is the raw `sqrt(lifetime / divisor)` term. Mostly useful for a "what would I get"
	projection; the actual payout on reset is `gainOnReset`.
]]
function Angels.totalForEarnings(lifetimeEarnings: BigNumber, divisor: Divisor?): number
	if BigNumber.isZero(lifetimeEarnings) or lifetimeEarnings.mantissa < 0 then
		return 0
	end

	local effective = divisor or EARTH_DIVISOR
	-- Numerator first, then denominator. See the note on Divisor: collapsing these into one
	-- division costs an angel at every round number.
	local scaled = BigNumber.mulNumber(lifetimeEarnings, effective.scale)
	local ratio = BigNumber.div(scaled, effective.base)
	return BigNumber.toNumber(BigNumber.sqrt(ratio))
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
	divisor: Divisor?
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
function Angels.earningsForNextAngel(currentTotal: number, divisor: Divisor?): BigNumber
	local effective = divisor or EARTH_DIVISOR
	local target = math.floor(currentTotal) + 1
	local squared = BigNumber.fromNumber(target * target)
	-- Inverts totalForEarnings, so it has to undo the fraction the same way round.
	return BigNumber.divNumber(BigNumber.mul(squared, effective.base), effective.scale)
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
