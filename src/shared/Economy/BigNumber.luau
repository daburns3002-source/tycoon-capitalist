--!strict
--[[
	BigNumber -- the money type.

	Why this exists: AdVenture Capitalist prices follow a geometric series and the real game
	treats anything past ~2^1024 as infinite. A Luau `number` is an IEEE-754 double: it
	overflows to `inf` at ~1.8e308 and loses meaningful precision on sums long before that.
	A tycoon built on plain numbers breaks somewhere around the Movie Studio and takes every
	system that touched money down with it.

	So money is a normalised mantissa/exponent pair: `mantissa * 10^exponent` with the mantissa
	held in [1, 10) (or exactly 0). The exponent is a plain integer, so the representable range
	is bounded by the exponent's size rather than by the double's, and precision stays at the
	double's full ~15 significant digits no matter how large the value gets.

	This module is pure: no services, no instances, no clock, no RNG. It is the one module
	allowed to do raw arithmetic on the components, which is why scripts/guard.py exempts it
	from the money-arith guard.

	Operations return new values; nothing here mutates its arguments.
]]

local Types = require(script.Parent.Parent.Types)

type BigNumber = Types.BigNumber

local BigNumber = {}

-- The mantissa is kept in [1, 10). log10 of the double's own limit, with headroom, is the
-- point past which we refuse to go -- matching the source game's "infinity" rather than
-- silently producing one.
local MAX_EXPONENT = 1e6

local ZERO: BigNumber = table.freeze({ mantissa = 0, exponent = 0 })
local ONE: BigNumber = table.freeze({ mantissa = 1, exponent = 0 })

BigNumber.zero = ZERO
BigNumber.one = ONE

--[[
	Pull a mantissa back into [1, 10) and fold the shift into the exponent.

	Every constructor and operation ends here, so an un-normalised BigNumber never escapes this
	module. Comparison and formatting both depend on that invariant.
]]
local function normalise(mantissa: number, exponent: number): BigNumber
	if mantissa == 0 or mantissa ~= mantissa then
		return ZERO
	end

	local sign = if mantissa < 0 then -1 else 1
	local magnitude = math.abs(mantissa)

	if magnitude == math.huge then
		return table.freeze({ mantissa = sign, exponent = MAX_EXPONENT })
	end

	local shift = math.floor(math.log10(magnitude))
	magnitude = magnitude / 10 ^ shift
	exponent += shift

	-- log10 and the division are both inexact at the boundaries, so settle the invariant by
	-- hand rather than trusting the float.
	while magnitude >= 10 do
		magnitude /= 10
		exponent += 1
	end
	while magnitude < 1 do
		magnitude *= 10
		exponent -= 1
	end

	if exponent > MAX_EXPONENT then
		return table.freeze({ mantissa = sign, exponent = MAX_EXPONENT })
	end

	return table.freeze({ mantissa = sign * magnitude, exponent = exponent })
end

BigNumber.normalise = normalise

--[[ Build a BigNumber from a plain Luau number. ]]
function BigNumber.fromNumber(value: number): BigNumber
	return normalise(value, 0)
end

--[[
	Build a BigNumber from an explicit mantissa and exponent.

	Config tables use this so a value like the Oil Company's base revenue can be written as
	`fromParts(2.9668737024, 10)` and survive the round trip exactly, rather than being parsed
	out of a 29-digit literal.
]]
function BigNumber.fromParts(mantissa: number, exponent: number): BigNumber
	return normalise(mantissa, exponent)
end

--[[
	Collapse to a plain number.

	Only for values known to be small -- a cycle count, a UI percentage. Returns `math.huge`
	past the double's range rather than a wrong finite number, so a misuse is loud.
]]
function BigNumber.toNumber(value: BigNumber): number
	if value.exponent > 308 then
		return if value.mantissa < 0 then -math.huge else math.huge
	end
	return value.mantissa * 10 ^ value.exponent
end

--[[ Base-10 logarithm. Exact for our purposes and the basis of the angel formula. ]]
function BigNumber.log10(value: BigNumber): number
	if value.mantissa <= 0 then
		return -math.huge
	end
	return value.exponent + math.log10(value.mantissa)
end

function BigNumber.isZero(value: BigNumber): boolean
	return value.mantissa == 0
end

--[[ -1 if a < b, 0 if equal, 1 if a > b. ]]
function BigNumber.compare(a: BigNumber, b: BigNumber): number
	if a.mantissa == 0 and b.mantissa == 0 then
		return 0
	end

	local aSign = if a.mantissa < 0 then -1 elseif a.mantissa > 0 then 1 else 0
	local bSign = if b.mantissa < 0 then -1 elseif b.mantissa > 0 then 1 else 0
	if aSign ~= bSign then
		return if aSign < bSign then -1 else 1
	end

	-- Same sign: the larger exponent wins, flipped when both are negative.
	if a.exponent ~= b.exponent then
		local larger = if a.exponent > b.exponent then 1 else -1
		return larger * aSign
	end
	if a.mantissa == b.mantissa then
		return 0
	end
	return if a.mantissa < b.mantissa then -1 else 1
end

function BigNumber.lt(a: BigNumber, b: BigNumber): boolean
	return BigNumber.compare(a, b) < 0
end

function BigNumber.lte(a: BigNumber, b: BigNumber): boolean
	return BigNumber.compare(a, b) <= 0
end

function BigNumber.gt(a: BigNumber, b: BigNumber): boolean
	return BigNumber.compare(a, b) > 0
end

function BigNumber.gte(a: BigNumber, b: BigNumber): boolean
	return BigNumber.compare(a, b) >= 0
end

function BigNumber.eq(a: BigNumber, b: BigNumber): boolean
	return BigNumber.compare(a, b) == 0
end

--[[
	Addition.

	Shifts the smaller operand onto the larger one's exponent. Once the gap exceeds the
	double's ~15 significant digits the smaller term cannot affect the result, so it is
	dropped rather than rounded into noise -- which is also what the source game does when a
	quadrillion is added to an octillion.
]]
function BigNumber.add(a: BigNumber, b: BigNumber): BigNumber
	if a.mantissa == 0 then
		return b
	end
	if b.mantissa == 0 then
		return a
	end

	local high, low = a, b
	if a.exponent < b.exponent then
		high, low = b, a
	end

	local gap = high.exponent - low.exponent
	if gap > 17 then
		return high
	end

	return normalise(high.mantissa + low.mantissa / 10 ^ gap, high.exponent)
end

function BigNumber.sub(a: BigNumber, b: BigNumber): BigNumber
	return BigNumber.add(a, BigNumber.negate(b))
end

function BigNumber.negate(value: BigNumber): BigNumber
	if value.mantissa == 0 then
		return ZERO
	end
	return table.freeze({ mantissa = -value.mantissa, exponent = value.exponent })
end

function BigNumber.abs(value: BigNumber): BigNumber
	if value.mantissa >= 0 then
		return value
	end
	return BigNumber.negate(value)
end

--[[ Multiplication -- mantissas multiply, exponents add. No precision loss at any scale. ]]
function BigNumber.mul(a: BigNumber, b: BigNumber): BigNumber
	if a.mantissa == 0 or b.mantissa == 0 then
		return ZERO
	end
	return normalise(a.mantissa * b.mantissa, a.exponent + b.exponent)
end

--[[ Multiply by a plain number. The common case: applying a coefficient or a multiplier. ]]
function BigNumber.mulNumber(value: BigNumber, scalar: number): BigNumber
	if value.mantissa == 0 or scalar == 0 then
		return ZERO
	end
	return normalise(value.mantissa * scalar, value.exponent)
end

function BigNumber.div(a: BigNumber, b: BigNumber): BigNumber
	if b.mantissa == 0 then
		error("BigNumber.div: division by zero", 2)
	end
	if a.mantissa == 0 then
		return ZERO
	end
	return normalise(a.mantissa / b.mantissa, a.exponent - b.exponent)
end

function BigNumber.divNumber(value: BigNumber, scalar: number): BigNumber
	if scalar == 0 then
		error("BigNumber.divNumber: division by zero", 2)
	end
	if value.mantissa == 0 then
		return ZERO
	end
	return normalise(value.mantissa / scalar, value.exponent)
end

--[[
	Raise a plain base to a plain power, as a BigNumber.

	This is the cost curve's engine: `coefficient^n` where n can reach five figures. Done in
	log space so it never overflows on the way to the answer -- `1.15^5000` is about 1e302 as a
	double but intermediate steps of a naive loop would not survive.
]]
function BigNumber.powNumber(base: number, exponent: number): BigNumber
	if base <= 0 then
		error("BigNumber.powNumber: base must be positive", 2)
	end
	if exponent == 0 then
		return ONE
	end

	local logTotal = exponent * math.log10(base)
	local wholePart = math.floor(logTotal)
	return normalise(10 ^ (logTotal - wholePart), wholePart)
end

--[[ Square root. Used by the angel formula, which is sqrt of a ratio of huge numbers. ]]
function BigNumber.sqrt(value: BigNumber): BigNumber
	if value.mantissa < 0 then
		error("BigNumber.sqrt: negative value", 2)
	end
	if value.mantissa == 0 then
		return ZERO
	end

	local exponent = value.exponent
	local mantissa = value.mantissa
	-- An odd exponent cannot be halved cleanly, so move one power of ten into the mantissa.
	if exponent % 2 ~= 0 then
		mantissa *= 10
		exponent -= 1
	end
	return normalise(math.sqrt(mantissa), exponent // 2)
end

function BigNumber.min(a: BigNumber, b: BigNumber): BigNumber
	return if BigNumber.lt(a, b) then a else b
end

function BigNumber.max(a: BigNumber, b: BigNumber): BigNumber
	return if BigNumber.gt(a, b) then a else b
end

--[[
	Serialise for DataStores.

	Stored as a two-element array rather than a table with keys: a saved profile holds one of
	these per business per player, so the key names would be most of the payload.
]]
function BigNumber.serialise(value: BigNumber): { number }
	return { value.mantissa, value.exponent }
end

function BigNumber.deserialise(stored: { number }): BigNumber
	local mantissa = stored[1]
	local exponent = stored[2]
	if typeof(mantissa) ~= "number" or typeof(exponent) ~= "number" then
		return ZERO
	end
	return normalise(mantissa, exponent)
end

--[[ Debug representation. Player-facing text comes from Economy.Format, not from here. ]]
function BigNumber.toDebugString(value: BigNumber): string
	return string.format("%.6fe%d", value.mantissa, value.exponent)
end

return table.freeze(BigNumber)
