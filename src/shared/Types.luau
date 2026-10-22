--!strict
--[[
	Shared type definitions.

	Money is never a plain `number`. A Luau number is an IEEE-754 double and this economy's
	prices reach ~1e306, so everything monetary is a BigNumber: a normalised mantissa/exponent
	pair. See CLAUDE.md, non-negotiable 1, and src/shared/Economy/BigNumber.luau.
]]

--[[
	`mantissa * 10^exponent`, with the mantissa held in [1, 10) or exactly 0.

	The invariant is maintained by BigNumber.normalise and relied on by comparison and
	formatting, so never build one of these by hand -- use BigNumber.fromNumber or fromParts.
]]
export type BigNumber = {
	mantissa: number,
	exponent: number,
}

export type BusinessId = string

--[[
	One business, exactly as the source game defines it.

	`coefficient` stays a plain number: it is a small multiplier in [1.07, 1.15] that is never
	itself a money value, and BigNumber.powNumber consumes it directly.
]]
export type BusinessConfig = {
	id: BusinessId,
	displayName: string,
	order: number,
	initialCost: BigNumber,
	coefficient: number,
	cycleSeconds: number,
	revenuePerCycle: BigNumber,
	managerCost: BigNumber,
}

--[[
	A player's state for one business. Owned by the server; the client gets a copy to render.

	`unitsOwned` is a plain number because the source game caps it at the 32-bit integer limit
	and nothing in the economy multiplies two unit counts together.
]]
export type BusinessState = {
	unitsOwned: number,
	hasManager: boolean,
	hasAccountant: boolean,
	cycleStartedAt: number?,
	profitMultiplier: number,
}

--[[
	Everything one player's run owns.

	Keyed per player and passed explicitly rather than held in a module-level global, so a
	shared-plot or ranked layer later is an addition and not a rewrite. CLAUDE.md,
	non-negotiable 5.
]]
export type PlotState = {
	userId: number,
	cash: BigNumber,
	lifetimeEarnings: BigNumber,
	earningsBeforeThisRun: BigNumber,
	angels: number,
	angelsSacrificed: number,
	allProfitMultiplier: number,
	angelEffectiveness: number,
	businesses: { [BusinessId]: BusinessState },
}

export type DeviceTier = "Low" | "Medium" | "High"

export type BuyMode = "x1" | "x10" | "x100" | "max"

--[[
	What the client is told about one business.

	BigNumbers cross the wire as their mantissa/exponent table, which replicates as a plain
	table -- no custom serialisation needed and no precision lost. `nextCostFor` is the price of
	the currently selected buy mode, computed server-side so the client never prices anything
	itself.
]]
export type BusinessSnapshot = {
	id: BusinessId,
	unitsOwned: number,
	hasManager: boolean,
	cycleSeconds: number,
	cycleElapsed: number,
	isCycling: boolean,
	payoutPerCycle: BigNumber,
	nextCostFor: BigNumber,
	affordableAtMode: number,
	nextMilestone: number?,
}

--[[
	The whole panel's state, pushed by the server whenever something it shows changes.

	The client renders this and interpolates progress bars locally for smoothness. It never
	derives a value that matters from it.
]]
export type PlotSnapshot = {
	cash: BigNumber,
	lifetimeEarnings: BigNumber,
	angels: number,
	buyMode: BuyMode,
	globalMilestones: number,
	businesses: { BusinessSnapshot },
}

return nil
