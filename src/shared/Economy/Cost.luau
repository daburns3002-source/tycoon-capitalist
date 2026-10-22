--!strict
--[[
	Cost -- what the next units of a business are worth.

	Each unit costs the previous one times a fixed coefficient between 1.07 and 1.15. That
	makes the price of unit n a geometric term and the price of a batch a geometric series.

	Buying ten or a hundred at once gives **no discount** in the source game; the bulk price is
	exactly what ten or a hundred single purchases would total. Implementing it as a closed-form
	series rather than a loop is purely about not iterating 400 times per UI frame -- the answer
	is identical.

	Pure module: no services, no clock, no RNG.
]]

local BigNumber = require(script.Parent.BigNumber)
local Types = require(script.Parent.Parent.Types)

type BigNumber = Types.BigNumber
type BusinessConfig = Types.BusinessConfig

local Cost = {}

--[[
	Price of unit number `n`, where n counts from 1.

	`unitCost(config, 1)` is the initial cost; `unitCost(config, 2)` is the initial cost times
	the coefficient. The exponent is `n - 1`, and an off-by-one here is silent -- every price in
	the game drifts by one coefficient step and nothing crashes.
]]
function Cost.unitCost(config: BusinessConfig, n: number): BigNumber
	if n < 1 then
		error("Cost.unitCost: n must be at least 1", 2)
	end

	local growth = BigNumber.powNumber(config.coefficient, n - 1)
	return BigNumber.mul(config.initialCost, growth)
end

--[[
	Total price of buying `quantity` more units when `owned` are already held.

	The next unit is number `owned + 1`, so the batch runs from `c^owned` to `c^(owned+quantity-1)`
	and sums to:

	    initialCost * c^owned * (c^quantity - 1) / (c - 1)

	A finite geometric series. With c > 1 this is exact to the double's precision at every scale
	because BigNumber keeps the mantissa normalised.
]]
function Cost.bulkCost(config: BusinessConfig, owned: number, quantity: number): BigNumber
	if quantity <= 0 then
		return BigNumber.zero
	end
	if owned < 0 then
		error("Cost.bulkCost: owned cannot be negative", 2)
	end

	--[[
		A batch of one is the single most common call -- every x1 purchase and every
		affordability check -- and the series is not exact for it.

		`(c^1 - 1) / (c - 1)` should be 1, but with c = 1.09 the float arithmetic yields
		0.99999999999999989, so a single Movie Studio priced through the series came out at
		179159039.99999997 against a unit cost of 179159040. A player holding exactly the unit
		price was then told they could not afford it, because `maxAffordable` compared the two
		figures and the series one was larger. Returning the unit cost directly is exact, is one
		multiply instead of four operations, and removes the inconsistency at its source.
	]]
	if quantity == 1 then
		return Cost.unitCost(config, owned + 1)
	end

	local coefficient = config.coefficient
	local base = BigNumber.mul(config.initialCost, BigNumber.powNumber(coefficient, owned))
	local seriesNumerator = BigNumber.sub(BigNumber.powNumber(coefficient, quantity), BigNumber.one)
	local series = BigNumber.divNumber(seriesNumerator, coefficient - 1)

	return BigNumber.mul(base, series)
end

--[[
	How many units `available` money can buy, on top of `owned`.

	Inverts the series rather than stepping one unit at a time, so a "max buy" button stays
	cheap even when the answer is in the thousands:

	    quantity = floor( log(1 + available * (c-1) / (initialCost * c^owned)) / log(c) )

	Done in log space throughout, because `available / base` can be astronomically large.
	Returns 0 when the next single unit is unaffordable.
]]
function Cost.maxAffordable(
	config: BusinessConfig,
	owned: number,
	available: BigNumber,
	unitCap: number
): number
	if BigNumber.isZero(available) or available.mantissa < 0 then
		return 0
	end

	local coefficient = config.coefficient
	local base = BigNumber.mul(config.initialCost, BigNumber.powNumber(coefficient, owned))

	-- Gate on the price actually charged for one unit, not on `base`. The two differ by a
	-- rounding step, and when they did, a player holding exactly the price of one unit was
	-- refused it. Anything that decides affordability has to ask the same function that will
	-- take the money.
	if BigNumber.lt(available, Cost.bulkCost(config, owned, 1)) then
		return 0
	end

	local ratio = BigNumber.div(available, base)
	local scaled = BigNumber.mulNumber(ratio, coefficient - 1)
	-- `scaled + 1` only matters while scaled is small; past that the 1 is below precision and
	-- BigNumber.add drops it, which is correct rather than approximate.
	local inner = BigNumber.add(scaled, BigNumber.one)

	local quantity = math.floor(BigNumber.log10(inner) / math.log10(coefficient))
	quantity = math.max(quantity, 0)

	local headroom = math.max(unitCap - owned, 0)
	if quantity > headroom then
		quantity = headroom
	end

	-- The logarithm is inexact near a batch boundary, and it can err in either direction, so
	-- settle the answer against the exact series rather than trusting it.
	--
	-- Correcting only downward is a real bug: when `available` is exactly the price of ten
	-- units, `log10` can land a hair under 10, floor to 9, and a decrement-only loop has no way
	-- back up. The player is then refused a unit they can exactly afford -- which is precisely
	-- the moment a max-buy button gets pressed, because it is how the UI shows "you can afford
	-- ten". Both loops together are what make the result exact.
	--
	-- A couple of iterations at most: the log is wrong by rounding, not by magnitude.
	while quantity > 0 and BigNumber.gt(Cost.bulkCost(config, owned, quantity), available) do
		quantity -= 1
	end
	while
		quantity < headroom
		and BigNumber.lte(Cost.bulkCost(config, owned, quantity + 1), available)
	do
		quantity += 1
	end

	return quantity
end

--[[
	Apply the unit-cost discounts the source game grants.

	Accountants cost angels and take 10% off; the late-game discount managers take 99.999% off.
	They stack multiplicatively, and both are lost on an angel reset.
]]
function Cost.applyDiscount(price: BigNumber, discountMultiplier: number): BigNumber
	if discountMultiplier == 1 then
		return price
	end
	return BigNumber.mulNumber(price, discountMultiplier)
end

return table.freeze(Cost)
