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
	-- The source game names every manager after a pun or a pop-culture reference. Flavour, but
	-- it is the flavour that makes hiring one feel like hiring someone.
	managerName: string,
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
	--[[
		Cash upgrades bought this run, by id.

		Lost on an angel reset, like everything else bought with cash. The multipliers on
		`businesses` and `allProfitMultiplier` are derived from this set rather than stored
		independently, so there is one source of truth and no way for them to drift apart.
	]]
	upgradesOwned: { [string]: boolean },
}

--[[
	One cash upgrade.

	`target` is a business id, "all" for every business, or "angel" for the Angel Investor
	effectiveness line. For a profit upgrade `multiplier` is the factor (always 3 in the source
	game); for an angel upgrade it is the amount added to effectiveness, so 0.01 is +1%.
]]
export type UpgradeConfig = {
	id: string,
	displayName: string,
	target: string,
	kind: "profit" | "angelEffectiveness",
	multiplier: number,
	cost: BigNumber,
}

--[[
	One unlock: a named milestone earned by owning units, never bought.

	`owner` is the business whose unit count gates it, or "Capitalist" for the ladder gated on
	every business at once. `kind` is "speed" for the cycle-time halvings -- which `Economy.Cycle`
	already applies, so those are display-only here -- or "profit" for a multiplier that is
	genuinely applied. `target` is the business the multiplier lands on, which is not always the
	owner: Newspaper Delivery's unlocks multiply other businesses.
]]
export type UnlockConfig = {
	id: string,
	owner: string,
	goal: number,
	displayName: string,
	kind: "speed" | "profit",
	target: string,
	multiplier: number,
}

--[[ What the client is told about one unlock: earned, and how close the next one is. ]]
export type UnlockSnapshot = {
	id: string,
	earned: boolean,
	progress: number,
}

--[[ What the client is told about one upgrade. ]]
export type UpgradeSnapshot = {
	id: string,
	owned: boolean,
	affordable: boolean,
}

export type DeviceTier = "Low" | "Medium" | "High"

--[[
	One business's payout, as sent to the client when a cycle completes.

	Drives the number pop and the collect sound. The authoritative totals still arrive in the
	snapshot -- this is presentation, and a client that ignored it would still see the right
	cash.
]]
export type CyclePayment = {
	id: BusinessId,
	cycles: number,
	amount: BigNumber,
}

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
	--[[
		Identifies *which* cycle is running, so the client can tell a continuing cycle from a
		new one and avoid restarting its fill animation on every snapshot.

		It is the server's own start timestamp and is only ever compared for equality -- never
		subtracted, never shown. The server's clock means nothing on the client.

		Zero when idle. This matters from Phase 3: a managed business keeps `isCycling` true
		across back-to-back cycles, so a false-to-true transition is not enough to spot a new
		one.
	]]
	cycleToken: number,
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
	--[[
		Angels gained by resetting right now, and the lifetime earnings the next whole angel
		needs. Both computed server-side -- the client must never be the thing that decides how
		much a reset is worth.
	]]
	pendingAngels: number,
	nextAngelAt: BigNumber,
	globalMilestones: number,
	businesses: { BusinessSnapshot },
	upgrades: { UpgradeSnapshot },
	unlocks: { UnlockSnapshot },
}

return nil
