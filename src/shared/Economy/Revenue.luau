--!strict
--[[
	Revenue -- what a completed production cycle pays out.

	Revenue scales strictly **linearly** with units owned. The 145th Bank adds exactly what the
	first one did. Cost grows geometrically and revenue grows linearly, and that divergence is
	the entire difficulty curve of the source game -- if revenue ever compounds here, the
	pacing is wrong no matter how right every constant is.

	On top of the linear base sit three multipliers, all multiplicative with each other:

	* per-business multipliers from cash upgrades (mostly x3)
	* an all-business multiplier from the more expensive cash upgrades and from unlocks
	* the angel bonus, which is +2% per angel and therefore *additive among angels* but
	  multiplicative against everything else

	Pure module: no services, no clock, no RNG.
]]

local BigNumber = require(script.Parent.BigNumber)
local Types = require(script.Parent.Parent.Types)

type BigNumber = Types.BigNumber
type BusinessConfig = Types.BusinessConfig

local Revenue = {}

--[[
	Each angel adds two percent to all profits.

	Additive among themselves: fifty angels is +100%, a x2 overall, and a thousand angels is
	+2000%, a x21. Treating them as multiplicative would make 1000 angels about 4e8 instead,
	which is not a subtle difference.

	`effectiveness` is the angel-upgrade line that raises the per-angel rate above 2%.
]]
function Revenue.angelMultiplier(angels: number, effectiveness: number?): number
	local perAngel = 0.02 * (effectiveness or 1)
	return 1 + angels * perAngel
end

--[[
	Payout for one completed cycle of one business.

	`businessMultiplier` is that business's own upgrade stack; `allMultiplier` covers the
	upgrades and unlocks that hit everything; `angels` and `angelEffectiveness` produce the
	reset bonus.
]]
function Revenue.perCycle(
	config: BusinessConfig,
	unitsOwned: number,
	businessMultiplier: number,
	allMultiplier: number,
	angels: number,
	angelEffectiveness: number?
): BigNumber
	if unitsOwned <= 0 then
		return BigNumber.zero
	end

	local base = BigNumber.mulNumber(config.revenuePerCycle, unitsOwned)
	local combined = businessMultiplier
		* allMultiplier
		* Revenue.angelMultiplier(angels, angelEffectiveness)

	return BigNumber.mulNumber(base, combined)
end

--[[
	Income per second for one business.

	The source game shows this in place of the per-cycle figure once an accountant is hired.
	`cycleSeconds` comes from Economy.Cycle, so the milestone halvings are already in it.
]]
function Revenue.perSecond(payout: BigNumber, cycleSeconds: number): BigNumber
	if cycleSeconds <= 0 then
		error("Revenue.perSecond: cycleSeconds must be positive", 2)
	end
	return BigNumber.divNumber(payout, cycleSeconds)
end

--[[
	What a managed business earns over `elapsed` seconds.

	Only whole completed cycles pay out -- a cycle three-quarters through has earned nothing
	yet, which is exactly how the source game behaves and why collecting manually just before
	a long cycle completes is a real strategy. The remainder is returned so the caller can
	carry it into the next tick rather than discarding progress.

	Used both by the server tick and by offline accrual. The elapsed time must come from a
	server-trusted clock; this module never reads one itself.
]]
function Revenue.overElapsed(
	payout: BigNumber,
	cycleSeconds: number,
	elapsed: number
): (BigNumber, number)
	if cycleSeconds <= 0 then
		error("Revenue.overElapsed: cycleSeconds must be positive", 2)
	end
	if elapsed <= 0 then
		return BigNumber.zero, 0
	end

	local completed = math.floor(elapsed / cycleSeconds)
	local remainder = elapsed - completed * cycleSeconds

	if completed <= 0 then
		return BigNumber.zero, remainder
	end

	return BigNumber.mulNumber(payout, completed), remainder
end

return table.freeze(Revenue)
