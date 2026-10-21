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

return nil
