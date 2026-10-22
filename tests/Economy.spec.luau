--!strict
--[[
	The economy suite.

	Every assertion here is a value with a known-correct answer, either read out of the Steam
	build or derived from the formulas in docs/RESEARCH-advcap.md at 50-digit precision. This
	is the file that makes "identical to AdVenture Capitalist" a checkable claim.

	Run it from Studio (see tests/README.md). CI type-checks it and separately re-derives the
	same anchors in scripts/verify_economy.py, which needs no Luau runtime.

	A note on one anchor: the wiki says the second Car Wash costs $829.92. It does not. That is
	728 x 1.14, and the initial cost is 720, so the answer is $820.80. The wiki's other figures
	reproduce exactly, which is a decent reminder that a secondary source is worth checking
	rather than trusting.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = Shared:WaitForChild("Economy")

local Angels = require(Economy.Angels)
local BigNumber = require(Economy.BigNumber)
local Businesses = require(Shared.Config.Businesses)
local Cost = require(Economy.Cost)
local Cycle = require(Economy.Cycle)
local Format = require(Economy.Format)
local Revenue = require(Economy.Revenue)
local ServerScriptService = game:GetService("ServerScriptService")
local AngelUpgradeConfig = require(Shared.Config.AngelUpgrades)
local FakeStore = require(ServerStorage.Tests.FakeStore)
local Leaderboard = require(ServerScriptService.Server.Data.Leaderboard)
local Offline = require(ServerScriptService.Server.Tick.Offline)
local PlotState = require(ServerScriptService.Server.Plot.PlotState)
local Profiles = require(ServerScriptService.Server.Data.Profiles)
local Serialise = require(ServerScriptService.Server.Data.Serialise)
local TestRunner = require(ServerStorage.Tests.TestRunner)
local UnlockConfig = require(Shared.Config.Unlocks)
local UpgradeConfig = require(Shared.Config.Upgrades)

local Spec = {}

local function allUnits(count: number): { [string]: number }
	local map = {}
	for _, config in Businesses.list do
		map[config.id] = count
	end
	return map
end

local function testBigNumber(): (number, number)
	local t = TestRunner.new("BigNumber")

	t:bigEquals("fromNumber normalises 1500", BigNumber.fromNumber(1500), 1.5, 3)
	t:bigEquals("fromNumber handles 1", BigNumber.fromNumber(1), 1, 0)
	t:bigEquals("fromParts round-trips", BigNumber.fromParts(2.9668737024, 10), 2.9668737024, 10)
	t:isTrue("zero is zero", BigNumber.isZero(BigNumber.zero))

	-- Addition across a small gap keeps both terms.
	t:bigEquals(
		"1e3 + 5e2",
		BigNumber.add(BigNumber.fromNumber(1000), BigNumber.fromNumber(500)),
		1.5,
		3
	)
	-- Across a gap wider than the double's precision the smaller term cannot register, which
	-- is correct rather than approximate.
	t:bigEquals(
		"1e30 + 1e3 drops the small term",
		BigNumber.add(BigNumber.fromParts(1, 30), BigNumber.fromNumber(1000)),
		1,
		30
	)

	t:bigEquals(
		"mul adds exponents",
		BigNumber.mul(BigNumber.fromParts(2, 50), BigNumber.fromParts(3, 60)),
		6,
		110
	)
	t:bigEquals(
		"sub to zero",
		BigNumber.sub(BigNumber.fromNumber(5), BigNumber.fromNumber(5)),
		0,
		0
	)

	-- Past the double's own ceiling, which is the entire reason this type exists.
	local huge = BigNumber.powNumber(10, 400)
	t:bigEquals("10^400 survives", huge, 1, 400)
	t:bigEquals("10^400 squared", BigNumber.mul(huge, huge), 1, 800)

	t:bigEquals("sqrt of 1e100", BigNumber.sqrt(BigNumber.fromParts(1, 100)), 1, 50)
	-- An odd exponent cannot be halved directly; the mantissa has to absorb a power of ten.
	t:bigEquals("sqrt of 1e101", BigNumber.sqrt(BigNumber.fromParts(1, 101)), 3.16227766017, 50)

	t:equalsApprox("log10 of 1.5e7", BigNumber.log10(BigNumber.fromParts(1.5, 7)), 7.17609125906)
	t:equals(
		"compare 1e10 > 1e9",
		BigNumber.gt(BigNumber.fromParts(1, 10), BigNumber.fromParts(1, 9)),
		true
	)
	t:equals(
		"compare equal",
		BigNumber.eq(BigNumber.fromNumber(42), BigNumber.fromNumber(42)),
		true
	)

	local stored = BigNumber.serialise(BigNumber.fromParts(1.07495424, 9))
	t:bigEquals("serialise round-trip", BigNumber.deserialise(stored), 1.07495424, 9)

	return t:finish()
end

local function testCost(): (number, number)
	local t = TestRunner.new("Cost")

	local carWash = Businesses.byId.CarWash
	local lemonade = Businesses.byId.LemonadeStand
	local oil = Businesses.byId.OilCompany

	-- The first unit is the initial cost: no coefficient applied.
	t:equalsApprox("1st Car Wash", BigNumber.toNumber(Cost.unitCost(carWash, 1)), 720, 1e-12)
	-- 720 * 1.14. NOT the wiki's 829.92.
	t:equalsApprox("2nd Car Wash", BigNumber.toNumber(Cost.unitCost(carWash, 2)), 820.80, 1e-12)
	t:equalsApprox("3rd Car Wash", BigNumber.toNumber(Cost.unitCost(carWash, 3)), 935.712, 1e-12)

	-- The player owns one free stand, so the first purchase is unit 2 at exactly $4.
	t:equalsApprox(
		"2nd Lemonade Stand is $4",
		BigNumber.toNumber(Cost.unitCost(lemonade, 2)),
		4,
		1e-12
	)

	-- Ten at once is exactly ten singles: no bulk discount in the source game.
	local singles = BigNumber.zero
	for n = 1, 10 do
		singles = BigNumber.add(singles, Cost.unitCost(carWash, n))
	end
	t:equalsApprox(
		"bulk of 10 equals 10 singles",
		BigNumber.toNumber(Cost.bulkCost(carWash, 0, 10)),
		BigNumber.toNumber(singles),
		1e-9
	)

	-- The headline series check: 319,433,276,243,943 to the dollar.
	t:equalsApprox(
		"first 100 Oil Companies",
		BigNumber.toNumber(Cost.bulkCost(oil, 0, 100)),
		319433276243943,
		1e-12
	)

	t:equals("bulk of 0 is zero", BigNumber.isZero(Cost.bulkCost(carWash, 5, 0)), true)

	-- maxAffordable has to invert the series exactly, including at the boundary.
	local exactlyTen = Cost.bulkCost(carWash, 0, 10)
	t:equals(
		"maxAffordable with exactly 10 units of money",
		Cost.maxAffordable(carWash, 0, exactlyTen, Businesses.maxUnits),
		10
	)
	local oneShort = BigNumber.sub(exactlyTen, BigNumber.fromNumber(1))
	t:equals(
		"maxAffordable one dollar short buys 9",
		Cost.maxAffordable(carWash, 0, oneShort, Businesses.maxUnits),
		9
	)
	t:equals(
		"maxAffordable with no money",
		Cost.maxAffordable(carWash, 0, BigNumber.zero, Businesses.maxUnits),
		0
	)
	t:equals(
		"maxAffordable respects the unit cap",
		Cost.maxAffordable(carWash, 0, BigNumber.powNumber(10, 300), 50),
		50
	)

	-- The property that matters: given exactly the price of k units, max-buy must return k, for
	-- every business and at every scale. Codex caught this failing at exact boundaries -- the
	-- log can land a hair under the integer, and a decrement-only correction has no way back up,
	-- so the player is refused a unit they can exactly afford.
	--
	-- Swept rather than spot-checked, because the failure depends on where the floating-point
	-- logarithm happens to land and a single case proves nothing about the next coefficient.
	local boundaryFailures = 0
	local firstFailure: string? = nil
	for _, config in Businesses.list do
		for _, owned in { 0, 1, 24, 25, 99, 400 } do
			for _, quantity in { 1, 2, 9, 10, 25, 100 } do
				local exact = Cost.bulkCost(config, owned, quantity)
				local answer = Cost.maxAffordable(config, owned, exact, Businesses.maxUnits)
				if answer ~= quantity then
					boundaryFailures += 1
					if firstFailure == nil then
						firstFailure = string.format(
							"%s owned=%d wanted=%d got=%d",
							config.id,
							owned,
							quantity,
							answer
						)
					end
				end
			end
		end
	end
	t:record(
		"maxAffordable is exact at every batch boundary (360 cases)",
		boundaryFailures == 0,
		if firstFailure
			then string.format("%d failures, first: %s", boundaryFailures, firstFailure)
			else nil
	)

	-- One short of a boundary must still round down, so the upward correction cannot overshoot.
	local justUnder = BigNumber.sub(Cost.bulkCost(carWash, 7, 10), BigNumber.fromNumber(0.01))
	t:equals(
		"a penny short of ten still buys nine",
		Cost.maxAffordable(carWash, 7, justUnder, Businesses.maxUnits),
		9
	)

	-- The accountant's 10% discount.
	t:equalsApprox(
		"10% accountant discount",
		BigNumber.toNumber(Cost.applyDiscount(Cost.unitCost(carWash, 2), 0.9)),
		738.72,
		1e-12
	)

	return t:finish()
end

local function testCycle(): (number, number)
	local t = TestRunner.new("Cycle")

	local oil = Businesses.byId.OilCompany
	local lemonade = Businesses.byId.LemonadeStand

	t:equals("0 units, no milestones", Cycle.milestonesReached(0), 0)
	t:equals("24 units, no milestones", Cycle.milestonesReached(24), 0)
	t:equals("25 units, one milestone", Cycle.milestonesReached(25), 1)
	t:equals("400 units, all six", Cycle.milestonesReached(400), 6)
	t:equals("1000 units, still six", Cycle.milestonesReached(1000), 6)

	-- No milestones: the base cycle.
	t:equalsApprox("Oil at 1 unit", Cycle.duration(oil, 1, 0), 36864, 1e-12)
	-- Its own 25 mark halves it once.
	t:equalsApprox("Oil at 25 units", Cycle.duration(oil, 25, 0), 18432, 1e-12)

	-- The all-business tier stacks on top of the per-business one. This is the half of the
	-- system that is easy to miss and that carries the mid-game.
	local at25 = allUnits(25)
	t:equals("all businesses at 25", Cycle.globalMilestonesReached(at25), 1)
	t:equalsApprox("Oil at 25 with all at 25", Cycle.duration(oil, 25, 1), 9216, 1e-12)

	-- One business short holds the whole global tier back.
	local almost = allUnits(25)
	almost.Bank = 24
	t:equals("one business short blocks the global tier", Cycle.globalMilestonesReached(almost), 0)

	-- The headline: 400 of everything is six own plus six global, capped at twelve, and the
	-- Oil Company's ten-hour cycle becomes exactly nine seconds.
	local at400 = allUnits(400)
	t:equals("all businesses at 400", Cycle.globalMilestonesReached(at400), 6)
	t:equals("halvings cap at 12", Cycle.halvings(400, 6), 12)
	t:equalsApprox("Oil cycle at 400 of everything", Cycle.duration(oil, 400, 6), 9, 1e-12)
	t:equalsApprox(
		"Lemonade cycle at 400 of everything",
		Cycle.duration(lemonade, 400, 6),
		0.6 / 4096,
		1e-12
	)

	t:equals("next milestone from 0", Cycle.nextMilestone(0), 25)
	t:equals("next milestone from 25", Cycle.nextMilestone(25), 50)
	t:equals("no milestone past 400", Cycle.nextMilestone(400), nil)

	local target, laggard = Cycle.nextGlobalMilestone(almost)
	t:equals("next global milestone target", target, 25)
	t:equals("next global milestone laggard", laggard, "Bank")

	return t:finish()
end

local function testRevenue(): (number, number)
	local t = TestRunner.new("Revenue")

	local bank = Businesses.byId.Bank

	-- Linear in units: the 145th Bank adds what the first did.
	local one = Revenue.perCycle(bank, 1, 1, 1, 0)
	local oneForty5 = Revenue.perCycle(bank, 145, 1, 1, 0)
	t:equalsApprox("1 Bank per cycle", BigNumber.toNumber(one), 1074954240, 1e-12)
	t:equalsApprox(
		"145 Banks is exactly 145x",
		BigNumber.toNumber(oneForty5),
		1074954240 * 145,
		1e-12
	)

	-- Angels are additive among themselves. Fifty is x2, not 1.02^50.
	t:equalsApprox("50 angels is x2", Revenue.angelMultiplier(50), 2, 1e-12)
	t:equalsApprox("1000 angels is x21", Revenue.angelMultiplier(1000), 21, 1e-12)
	t:equalsApprox("0 angels is x1", Revenue.angelMultiplier(0), 1, 1e-12)

	-- Upgrade stacks are multiplicative against each other and against the angel bonus.
	local boosted = Revenue.perCycle(bank, 1, 3, 2, 50)
	t:equalsApprox(
		"x3 business, x2 all, 50 angels",
		BigNumber.toNumber(boosted),
		1074954240 * 3 * 2 * 2,
		1e-12
	)

	t:equals("zero units earns nothing", BigNumber.isZero(Revenue.perCycle(bank, 0, 1, 1, 0)), true)

	t:equalsApprox(
		"per second at base cycle",
		BigNumber.toNumber(Revenue.perSecond(one, bank.cycleSeconds)),
		1074954240 / 6144,
		1e-12
	)

	-- Only whole cycles pay out, and the remainder carries forward.
	local payout, remainder = Revenue.overElapsed(BigNumber.fromNumber(100), 10, 35)
	t:equalsApprox("3 whole cycles in 35s", BigNumber.toNumber(payout), 300, 1e-12)
	t:equalsApprox("5s carries over", remainder, 5, 1e-12)

	local nothing, held = Revenue.overElapsed(BigNumber.fromNumber(100), 10, 7)
	t:equals("a partial cycle pays nothing", BigNumber.isZero(nothing), true)
	t:equalsApprox("the partial cycle is held", held, 7, 1e-12)

	return t:finish()
end

local function testAngels(): (number, number)
	local t = TestRunner.new("Angels")

	local zero = BigNumber.zero

	-- The first angel lands just past $44.44 billion lifetime.
	t:equals(
		"no angel below the threshold",
		Angels.gainOnReset(BigNumber.fromNumber(44e9), zero, 0),
		0
	)
	t:equals(
		"first angel at 44,444,444,445",
		Angels.gainOnReset(BigNumber.fromNumber(44444444445), zero, 0),
		1
	)

	-- The reference points from the source game, all exact.
	t:equals("1e12 lifetime", Angels.gainOnReset(BigNumber.fromParts(1, 12), zero, 0), 4)
	t:equals("1e15 lifetime", Angels.gainOnReset(BigNumber.fromParts(1, 15), zero, 0), 150)
	t:equals("1e18 lifetime", Angels.gainOnReset(BigNumber.fromParts(1, 18), zero, 0), 4743)
	t:equals("1e21 lifetime", Angels.gainOnReset(BigNumber.fromParts(1, 21), zero, 0), 150000)
	t:equals("1e24 lifetime", Angels.gainOnReset(BigNumber.fromParts(1, 24), zero, 0), 4743416)

	-- A second run only pays for what it added, not for the whole lifetime again.
	t:equals(
		"second run pays the difference",
		Angels.gainOnReset(BigNumber.fromParts(1, 18), BigNumber.fromParts(1, 15), 0),
		4743 - 150
	)

	-- Spending angels does not make the next one cheaper: the requirement tracks lifetime
	-- earnings, so a sacrifice beyond the previous run's credit comes off the payout.
	t:equals(
		"sacrificed angels come off the payout",
		Angels.gainOnReset(BigNumber.fromParts(1, 18), BigNumber.fromParts(1, 15), 1000),
		4743 - 1000
	)
	t:equals(
		"a small sacrifice is absorbed by prior credit",
		Angels.gainOnReset(BigNumber.fromParts(1, 18), BigNumber.fromParts(1, 15), 100),
		4743 - 150
	)
	t:equals(
		"the payout never goes negative",
		Angels.gainOnReset(BigNumber.fromParts(1, 15), zero, 999999),
		0
	)

	-- Inverting the formula for the "next angel at $X" readout.
	local nextAt = Angels.earningsForNextAngel(0)
	t:equalsApprox("next angel from 0", BigNumber.toNumber(nextAt), 400e9 / 9, 1e-9)
	t:equalsApprox(
		"next angel from 149",
		BigNumber.toNumber(Angels.earningsForNextAngel(149)),
		150 * 150 * (400e9 / 9),
		1e-9
	)

	-- Mars divides by 100e9 instead of 400e9, so the same earnings yield twice the angels.
	t:equals(
		"Mars divisor doubles the yield",
		Angels.gainOnReset(BigNumber.fromParts(1, 15), zero, 0, Angels.marsDivisor),
		300
	)

	return t:finish()
end

local function testFormat(): (number, number)
	local t = TestRunner.new("Format")

	t:equals("zero", Format.short(BigNumber.zero), "0")
	t:equals("under a thousand prints whole", Format.short(BigNumber.fromNumber(847)), "847")
	t:equals("trailing zeros trimmed", Format.short(BigNumber.fromNumber(1000)), "1K")
	t:equals("one decimal kept", Format.short(BigNumber.fromNumber(1500)), "1.5K")
	t:equals("two decimals kept", Format.short(BigNumber.fromNumber(1234)), "1.23K")
	t:equals("millions", Format.short(BigNumber.fromNumber(45600000)), "45.6M")
	t:equals("billions", Format.short(BigNumber.fromParts(7.89, 9)), "7.89B")
	t:equals("trillions", Format.short(BigNumber.fromParts(1, 12)), "1T")

	-- Mid-group exponents have to redistribute into the digits, not the suffix.
	t:equals("1e7 is 10M", Format.short(BigNumber.fromParts(1, 7)), "10M")
	t:equals("1e8 is 100M", Format.short(BigNumber.fromParts(1, 8)), "100M")

	t:equals(
		"named magnitudes run out into letters",
		Format.short(BigNumber.fromParts(1, 66)),
		"1aa"
	)
	t:equals("vigintillion is still named", Format.short(BigNumber.fromParts(1, 63)), "1Vg")

	t:equals("long form millions", Format.long(BigNumber.fromNumber(1230000)), "1.23 million")
	t:equals("long form quadrillion", Format.long(BigNumber.fromParts(1, 15)), "1 quadrillion")
	t:equals("long form defers past vigintillion", Format.long(BigNumber.fromParts(1, 66)), "1aa")

	t:equals("money prefixes a dollar sign", Format.money(BigNumber.fromNumber(1500)), "$1.5K")

	t:equals("sub-second cycle", Format.duration(0.6), "0.6s")
	t:equals("seconds", Format.duration(24), "24s")
	t:equals("minutes and seconds", Format.duration(96), "1:36")
	t:equals("hours", Format.duration(36864), "10:14:24")

	t:equals("integer grouping", Format.integer(1074954240), "1,074,954,240")
	t:equals("small integer ungrouped", Format.integer(25), "25")

	return t:finish()
end

local function testConfigIntegrity(): (number, number)
	local t = TestRunner.new("Config")

	t:equals("ten Earth businesses", #Businesses.list, 10)
	t:equals("six cycle milestones", #Businesses.cycleMilestones, 6)
	t:equals("twelve halvings maximum", Businesses.maxCycleHalvings, 12)

	-- Ordered cheapest to most expensive, and every coefficient in the source game's range.
	local previousCost = BigNumber.zero
	local ordered = true
	local coefficientsSane = true
	for index, config in Businesses.list do
		if BigNumber.lte(config.initialCost, previousCost) then
			ordered = false
		end
		previousCost = config.initialCost

		if config.coefficient < 1.07 or config.coefficient > 1.15 then
			coefficientsSane = false
		end
		if config.order ~= index then
			ordered = false
		end
	end
	t:isTrue("businesses ordered by ascending cost", ordered)
	t:isTrue("coefficients within 1.07..1.15", coefficientsSane)

	-- Frozen: a config module that can be mutated at runtime is not a config module.
	local froze = true
	local ok = pcall(function()
		(Businesses.byId :: any).CarWash = nil
	end)
	if ok then
		froze = false
	end
	t:isTrue("config table is frozen", froze)

	return t:finish()
end

local function testUpgradesAndManagers(): (number, number)
	local t = TestRunner.new("Upgrades")

	local plot = PlotState.new(1)

	-- A fresh plot owns nothing and manages nothing. The second half of that matters: a
	-- manager must be a deliberate purchase, never granted.
	t:equals("no upgrades at start", next(plot.upgradesOwned), nil)
	t:equals("all-business multiplier starts at 1", plot.allProfitMultiplier, 1)
	t:equals("angel effectiveness starts at 1", plot.angelEffectiveness, 1)

	local unmanaged = 0
	for _, state in plot.businesses do
		if not state.hasManager then
			unmanaged += 1
		end
	end
	t:equals("no business starts with a manager", unmanaged, 10)

	-- A per-business upgrade multiplies only its own business.
	plot.upgradesOwned.LittleUmbrellas = true
	PlotState.recomputeMultipliers(plot)
	t:equals("lemonade x3", plot.businesses.LemonadeStand.profitMultiplier, 3)
	t:equals("newspaper untouched", plot.businesses.NewspaperDelivery.profitMultiplier, 1)
	t:equals("all-business untouched", plot.allProfitMultiplier, 1)

	-- Tiers stack multiplicatively on the same business, as in the source game.
	plot.upgradesOwned.NoveltyStraws = true
	plot.upgradesOwned.ImportedIceCubes = true
	PlotState.recomputeMultipliers(plot)
	t:equals("three lemonade tiers is x27", plot.businesses.LemonadeStand.profitMultiplier, 27)

	-- An all-business upgrade is separate from the per-business stack, not folded into it.
	plot.upgradesOwned.Monopoly = true
	PlotState.recomputeMultipliers(plot)
	t:equals("all-business x3", plot.allProfitMultiplier, 3)
	t:equals("lemonade still x27", plot.businesses.LemonadeStand.profitMultiplier, 27)

	-- Angel upgrades add a percentage point each, they do not multiply.
	plot.upgradesOwned.HolyMoola = true
	plot.upgradesOwned.ImmaculateConsumption = true
	PlotState.recomputeMultipliers(plot)
	t:equalsApprox("two angel upgrades is +2%", plot.angelEffectiveness, 1.02, 1e-12)

	-- Recomputing is derived, not incremental: dropping an upgrade must drop its multiplier.
	-- This is what makes an angel reset safe to implement in Phase 6.
	plot.upgradesOwned.NoveltyStraws = false
	plot.upgradesOwned.ImportedIceCubes = false
	PlotState.recomputeMultipliers(plot)
	t:equals("removing two tiers returns to x3", plot.businesses.LemonadeStand.profitMultiplier, 3)

	-- Every configured upgrade must point at something real.
	local danglingTarget = nil
	for _, config in UpgradeConfig.list do
		local valid = config.target == "all"
			or config.target == "angel"
			or Businesses.byId[config.target] ~= nil
		if not valid and danglingTarget == nil then
			danglingTarget = `{config.id} -> {config.target}`
		end
	end
	t:record("every upgrade targets a real business", danglingTarget == nil, danglingTarget)

	return t:finish()
end

local function testUnlocks(): (number, number)
	local t = TestRunner.new("Unlocks")

	local plot = PlotState.new(1)

	-- Nothing earned from one free stand.
	t:equals("lowest count starts at 0", PlotState.lowestUnitCount(plot), 0)
	t:equals("lemonade x1 earns nothing", plot.businesses.LemonadeStand.profitMultiplier, 1)

	-- The speed marks are Economy.Cycle's job. Crossing 400 must NOT grant a profit
	-- multiplier here, or every cycle would effectively be doubled twice over.
	plot.businesses.LemonadeStand.unitsOwned = 400
	PlotState.recomputeMultipliers(plot)
	t:equals(
		"400 units grants no profit multiplier",
		plot.businesses.LemonadeStand.profitMultiplier,
		1
	)

	-- 500 is where profit multipliers start. Lemonade is the generous one at x4.
	plot.businesses.LemonadeStand.unitsOwned = 500
	PlotState.recomputeMultipliers(plot)
	t:equals("500 lemonade is x4", plot.businesses.LemonadeStand.profitMultiplier, 4)

	-- They stack: 500 through 900 are x4 each, 1000 is x5.
	plot.businesses.LemonadeStand.unitsOwned = 1000
	PlotState.recomputeMultipliers(plot)
	t:equals("1000 lemonade is 4^5 * 5", plot.businesses.LemonadeStand.profitMultiplier, 4 ^ 5 * 5)

	-- Newspaper Delivery multiplies *other* businesses. 125 units is the first ad deal.
	local fresh = PlotState.new(2)
	fresh.businesses.NewspaperDelivery.unitsOwned = 125
	PlotState.recomputeMultipliers(fresh)
	t:equals("newspaper 125 gives lemonade x2", fresh.businesses.LemonadeStand.profitMultiplier, 2)
	t:equals(
		"newspaper does not boost itself there",
		fresh.businesses.NewspaperDelivery.profitMultiplier,
		1
	)

	-- The Capitalist ladder is gated on the weakest business, not a total.
	local everywhere = PlotState.new(3)
	for _, state in everywhere.businesses do
		state.unitsOwned = 500
	end
	PlotState.recomputeMultipliers(everywhere)
	t:equals("all at 500 gives the capitalist x2", everywhere.allProfitMultiplier, 2)

	everywhere.businesses.OilCompany.unitsOwned = 499
	PlotState.recomputeMultipliers(everywhere)
	t:equals("one business short loses it", everywhere.allProfitMultiplier, 1)
	t:equals("lowest count reflects the laggard", PlotState.lowestUnitCount(everywhere), 499)

	-- Every unlock must point at a real business, and no speed unlock may sit past 400.
	local badTarget, lateSpeed = nil, nil
	for _, config in UnlockConfig.list do
		local validTarget = config.target == "all" or Businesses.byId[config.target] ~= nil
		if not validTarget and badTarget == nil then
			badTarget = `{config.id} -> {config.target}`
		end
		if config.kind == "speed" and config.goal > 400 and lateSpeed == nil then
			lateSpeed = `{config.id} at {config.goal}`
		end
	end
	t:record("every unlock targets a real business", badTarget == nil, badTarget)
	t:record("no speed unlock past 400", lateSpeed == nil, lateSpeed)

	return t:finish()
end

local function testPersistence(): (number, number)
	local t = TestRunner.new("Persistence")

	-- A plot with everything on it: cash, units, a manager, an upgrade, angels.
	local plot = PlotState.new(7)
	plot.cash = BigNumber.fromParts(1.5, 30)
	plot.lifetimeEarnings = BigNumber.fromParts(9.87, 42)
	plot.earningsBeforeThisRun = BigNumber.fromParts(1, 20)
	plot.angels = 4321
	plot.angelsSacrificed = 17
	plot.businesses.LemonadeStand.unitsOwned = 537
	plot.businesses.Bank.unitsOwned = 12
	plot.businesses.Bank.hasManager = true
	plot.businesses.OilCompany.hasAccountant = true
	plot.upgradesOwned.LittleUmbrellas = true
	plot.upgradesOwned.Monopoly = true
	PlotState.recomputeMultipliers(plot)

	local stored = Serialise.save(plot)
	local loaded, savedAt = Serialise.load(stored, function()
		return PlotState.new(7)
	end)
	PlotState.recomputeMultipliers(loaded)

	-- Money has to survive exactly. A save that rounds is a save that steals.
	t:bigEquals("cash round-trips", loaded.cash, 1.5, 30)
	t:bigEquals("lifetime round-trips", loaded.lifetimeEarnings, 9.87, 42)
	t:bigEquals("previous-run earnings round-trip", loaded.earningsBeforeThisRun, 1, 20)
	t:equals("angels round-trip", loaded.angels, 4321)
	t:equals("sacrificed angels round-trip", loaded.angelsSacrificed, 17)
	t:equals("units round-trip", loaded.businesses.LemonadeStand.unitsOwned, 537)
	t:equals("managers round-trip", loaded.businesses.Bank.hasManager, true)
	t:equals("accountants round-trip", loaded.businesses.OilCompany.hasAccountant, true)
	t:equals("upgrades round-trip", loaded.upgradesOwned.Monopoly, true)
	t:isTrue("savedAt is written", savedAt ~= nil and savedAt > 0)

	-- Multipliers are derived, never stored, so they must come back identical from the inputs.
	t:equals(
		"derived multipliers match",
		loaded.businesses.LemonadeStand.profitMultiplier,
		plot.businesses.LemonadeStand.profitMultiplier
	)
	t:equals("derived all-multiplier matches", loaded.allProfitMultiplier, plot.allProfitMultiplier)

	-- Cycle timestamps are an os.clock() reading and meaningless in another process.
	t:equals("cycles are not restored", loaded.businesses.Bank.cycleStartedAt, nil)

	-- A missing or junk profile yields a playable plot rather than an error.
	local fresh = Serialise.load(nil, function()
		return PlotState.new(8)
	end)
	t:equals("nil profile gives a fresh plot", fresh.businesses.LemonadeStand.unitsOwned, 1)
	local junk = Serialise.load({ version = 1, businesses = "nonsense" }, function()
		return PlotState.new(9)
	end)
	t:isTrue("malformed profile still loads", BigNumber.isZero(junk.cash))

	return t:finish()
end

local function testOfflineEarnings(): (number, number)
	local t = TestRunner.new("Offline")

	local plot = PlotState.new(11)
	plot.businesses.LemonadeStand.unitsOwned = 10
	plot.businesses.LemonadeStand.hasManager = true

	-- One Lemonade Stand cycle is 0.6s and ten units pay $10, so an hour is 6000 cycles.
	local hour = Offline.settle(plot, 0, 3600)
	t:equals("one business contributed", hour.businesses, 1)
	t:equalsApprox("an hour pays 6000 cycles", BigNumber.toNumber(hour.earned), 6000 * 10, 1e-9)
	t:equalsApprox("cash credited", BigNumber.toNumber(plot.cash), 6000 * 10, 1e-9)
	-- Offline money is real money: it has to count toward angels like any other.
	t:equalsApprox(
		"lifetime credited too",
		BigNumber.toNumber(plot.lifetimeEarnings),
		6000 * 10,
		1e-9
	)

	-- An unmanaged business earns nothing while away. That is the point of managers.
	local unmanaged = PlotState.new(12)
	unmanaged.businesses.LemonadeStand.unitsOwned = 100
	local idle = Offline.settle(unmanaged, 0, 3600)
	t:equals("unmanaged earns nothing", idle.businesses, 0)
	t:isTrue("and credits nothing", BigNumber.isZero(unmanaged.cash))

	-- Clamped at both ends.
	local backwards = PlotState.new(13)
	backwards.businesses.LemonadeStand.unitsOwned = 10
	backwards.businesses.LemonadeStand.hasManager = true
	local negative = Offline.settle(backwards, 5000, 1000)
	t:equals("a backwards clock pays nothing", negative.seconds, 0)
	t:isTrue("and credits nothing", BigNumber.isZero(backwards.cash))

	local long = PlotState.new(14)
	long.businesses.LemonadeStand.unitsOwned = 10
	long.businesses.LemonadeStand.hasManager = true
	local capped = Offline.settle(long, 0, 60 * 24 * 60 * 60)
	t:equals("a 60-day absence is capped", capped.seconds, Offline.maxSeconds)

	return t:finish()
end

local function testSessionLock(): (number, number)
	local t = TestRunner.new("SessionLock")

	local fake = FakeStore.new()
	local clock = FakeStore.clock(10000)
	local userId = 4242

	local function asServer(jobId: string): ()
		Profiles.configure({ store = fake.store, jobId = jobId, now = clock.now })
	end

	local function profileOf(): Serialise.SavedProfile
		local plot = PlotState.new(userId)
		plot.cash = BigNumber.fromParts(5, 12)
		return Serialise.save(plot)
	end

	-- A new player on server A: nothing stored, lock taken, writing allowed.
	asServer("A")
	local first = Profiles.load(userId)
	t:equals("new profile has no data", first.stored, nil)
	t:equals("and may save", first.canSave, true)

	t:equals("server A saves", Profiles.save(userId, profileOf(), false), true)
	t:isTrue("data is stored", fake.data[`plot_{userId}`].data ~= nil)

	-- Server B tries to take it while A's lock is fresh. It must be refused, and crucially it
	-- must not get the data either -- a reader that is refused the lock but handed the profile
	-- would be one bad branch away from writing it back.
	asServer("B")
	local blocked = Profiles.load(userId)
	t:equals("server B is refused", blocked.canSave, false)
	t:equals("and gets no data", blocked.stored, nil)
	t:isTrue("the refusal says why", blocked.reason ~= nil)

	-- B must not be able to write either, even if it tried anyway.
	local writesBefore = fake.writes
	t:equals("server B's save reports failure", Profiles.save(userId, profileOf(), false), false)
	t:equals("and wrote nothing", fake.writes, writesBefore)
	t:isTrue("its write was aborted", fake.aborts > 0)
	t:equals("the lock is still A's", fake.data[`plot_{userId}`].lock.jobId, "A")

	-- Age the lock past the timeout. A crashed server never releases one, so an abandoned lock
	-- has to become takeable or the player is locked out forever.
	clock.advance(Profiles.lockTimeout + 1)
	local stolen = Profiles.load(userId)
	t:equals("a stale lock can be taken", stolen.canSave, true)
	t:isTrue("and the data comes with it", stolen.stored ~= nil)
	t:equals("the lock is now B's", fake.data[`plot_{userId}`].lock.jobId, "B")

	-- Now A has lost the lock. Its next autosave must abandon rather than win.
	asServer("A")
	local beforeStaleWrite = fake.writes
	t:equals(
		"the server that lost the lock reports failure",
		Profiles.save(userId, profileOf(), false),
		false
	)
	t:equals("and writes nothing", fake.writes, beforeStaleWrite)

	-- B leaves cleanly: the lock is released so the next server need not wait it out.
	asServer("B")
	t:equals("leaving saves", Profiles.save(userId, profileOf(), true), true)
	t:equals("and releases the lock", fake.data[`plot_{userId}`].lock, nil)

	asServer("C")
	local afterRelease = Profiles.load(userId)
	t:equals("the next server loads immediately", afterRelease.canSave, true)
	t:isTrue("with the data intact", afterRelease.stored ~= nil)

	-- A round trip through the store, to prove the lock work did not cost the payload.
	local restored = Serialise.load(afterRelease.stored, function()
		return PlotState.new(userId)
	end)
	t:bigEquals("cash survived the store", restored.cash, 5, 12)

	Profiles.configure(nil)
	return t:finish()
end

local function testAngelUpgrades(): (number, number)
	local t = TestRunner.new("AngelUpgrades")

	local plot = PlotState.new(21)
	plot.angels = 150000

	-- Spending costs the angels *and* their bonus. That is the trade the whole layer rests on.
	local before = Revenue.angelMultiplier(plot.angels, plot.angelEffectiveness)
	t:equals("sacrifice succeeds when affordable", PlotState.trySacrifice(plot, 10000), true)
	t:equals("angels are spent", plot.angels, 140000)
	t:equals("and recorded as sacrificed", plot.angelsSacrificed, 10000)
	t:isTrue("the profit bonus drops", Revenue.angelMultiplier(plot.angels, 1) < before)

	t:equals("cannot overspend", PlotState.trySacrifice(plot, 999999999), false)
	t:equals("and nothing changed", plot.angels, 140000)

	-- All-profit angel upgrades stack with cash ones rather than replacing them.
	plot.angelUpgradesOwned.AngelSacrifice = true
	PlotState.recomputeMultipliers(plot)
	t:equals("angel all-profit applies", plot.allProfitMultiplier, 3)

	plot.upgradesOwned.Monopoly = true
	PlotState.recomputeMultipliers(plot)
	t:equals("and stacks with the cash one", plot.allProfitMultiplier, 9)

	-- Effectiveness is additive: +2% takes each angel from 2% to 4%.
	plot.angelUpgradesOwned.AngelicMutiny = true
	PlotState.recomputeMultipliers(plot)
	t:equalsApprox("effectiveness rises", plot.angelEffectiveness, 1.02, 1e-12)
	t:equalsApprox(
		"50 angels now give more than x2",
		Revenue.angelMultiplier(50, plot.angelEffectiveness),
		1 + 50 * 0.02 * 1.02,
		1e-12
	)

	-- Starting-units upgrades change what a run begins with.
	local head = PlotState.new(22)
	t:equals("a plain run starts with one stand", PlotState.startingUnits(head, "LemonadeStand"), 1)
	t:equals("and nothing else", PlotState.startingUnits(head, "CarWash"), 0)

	head.angelUpgradesOwned.CarWashSwap = true
	head.angelUpgradesOwned.CarWashSurge = true
	t:equals("swap and surge stack", PlotState.startingUnits(head, "CarWash"), 60)

	-- A reset keeps the angel upgrades and starts the run from what they grant.
	head.lifetimeEarnings = BigNumber.fromParts(1, 15)
	head.businesses.LemonadeStand.unitsOwned = 400
	head.businesses.CarWash.unitsOwned = 7
	head.businesses.Bank.hasManager = true
	head.upgradesOwned.LittleUmbrellas = true
	PlotState.reset(head)

	t:equals("angel upgrades survive the reset", head.angelUpgradesOwned.CarWashSwap, true)
	t:equals("cash upgrades do not", next(head.upgradesOwned), nil)
	t:equals("managers do not", head.businesses.Bank.hasManager, false)
	t:equals("the run starts from the head start", head.businesses.CarWash.unitsOwned, 60)
	t:equals("and the free stand is still there", head.businesses.LemonadeStand.unitsOwned, 1)

	-- Every angel upgrade must point at something real.
	local bad = nil
	for _, config in AngelUpgradeConfig.list do
		local valid = config.target == "all"
			or config.target == "angel"
			or Businesses.byId[config.target] ~= nil
		if not valid and bad == nil then
			bad = `{config.id} -> {config.target}`
		end
	end
	t:record("every angel upgrade targets something real", bad == nil, bad)

	return t:finish()
end

local function testLeaderboard(): (number, number)
	local t = TestRunner.new("Leaderboard")

	--[[
		The whole trick is ranking by the logarithm. An OrderedDataStore sorts a plain integer
		and this game's earnings reach 1e306, so the stored key is log10 scaled up. log10 is
		strictly increasing, so the ranking is exactly the ranking by earnings -- the test that
		matters is that ordering is preserved across the entire range.
	]]
	local samples = {
		BigNumber.zero,
		BigNumber.fromNumber(1),
		BigNumber.fromNumber(4),
		BigNumber.fromNumber(1000),
		BigNumber.fromParts(4.4, 10),
		BigNumber.fromParts(1, 15),
		BigNumber.fromParts(9.99, 15),
		BigNumber.fromParts(1, 100),
		BigNumber.fromParts(1, 306),
	}

	local brokenAt = nil
	for index = 2, #samples do
		local lower = Leaderboard.encode(samples[index - 1])
		local higher = Leaderboard.encode(samples[index])
		if higher <= lower and brokenAt == nil then
			brokenAt = `sample {index}: {lower} then {higher}`
		end
	end
	t:record("encoding preserves order across 1 to 1e306", brokenAt == nil, brokenAt)

	t:equals("zero scores zero", Leaderboard.encode(BigNumber.zero), 0)
	t:isTrue("one dollar outranks nothing", Leaderboard.encode(BigNumber.fromNumber(1)) > 0)
	t:isTrue("1e306 fits in an integer", Leaderboard.encode(BigNumber.fromParts(1, 306)) < 2 ^ 53)

	-- A negative balance cannot happen, but it must not poison the store if it ever did.
	t:equals(
		"a negative value scores zero",
		Leaderboard.encode(BigNumber.negate(BigNumber.fromNumber(500))),
		0
	)

	-- Decoding is exact enough to display: within the stored resolution.
	local original = BigNumber.fromParts(3.7, 42)
	local roundTrip = Leaderboard.decode(Leaderboard.encode(original))
	t:equals("decode keeps the exponent", roundTrip.exponent, 42)
	t:equalsApprox("and the mantissa", roundTrip.mantissa, 3.7, 1e-5)

	-- Two players a factor of two apart must never tie.
	local a = Leaderboard.encode(BigNumber.fromParts(1, 20))
	local b = Leaderboard.encode(BigNumber.fromParts(2, 20))
	t:isTrue("a factor of two is clearly separated", b > a)

	-- Publishing against a fake ordered store.
	local written: { [string]: number } = {}
	Leaderboard.configure({
		SetAsync = function(_self: any, key: string, value: number)
			written[key] = value
		end,
		GetSortedAsync = function()
			return nil
		end,
	})

	t:equals("publish succeeds", Leaderboard.publish(99, BigNumber.fromParts(5, 25)), true)
	t:equals(
		"and writes the encoded score",
		written.player_99,
		Leaderboard.encode(BigNumber.fromParts(5, 25))
	)

	Leaderboard.configure(nil)
	return t:finish()
end

function Spec.run(): boolean
	print("[economy] running suite")

	local suites = {
		testBigNumber,
		testCost,
		testCycle,
		testRevenue,
		testAngels,
		testFormat,
		testConfigIntegrity,
		testUpgradesAndManagers,
		testUnlocks,
		testPersistence,
		testOfflineEarnings,
		testSessionLock,
		testAngelUpgrades,
		testLeaderboard,
	}

	local passed, failed = 0, 0
	for _, suite in suites do
		local suitePassed, suiteFailed = suite()
		passed += suitePassed
		failed += suiteFailed
	end

	if failed == 0 then
		print(string.format("[economy] %d assertions, all passed", passed))
	else
		warn(string.format("[economy] %d of %d assertions FAILED", failed, passed + failed))
	end

	return failed == 0
end

return Spec
