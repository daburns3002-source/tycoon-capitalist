--!strict
--[[
	Angel upgrades: what angels are actually for.

	Bought by sacrificing Angel Investors rather than cash. The sacrifice is permanent -- those
	angels are gone, and with them their +2% each -- so every purchase is a real trade rather
	than a shopping trip. That tension is the whole point of a prestige currency: without a sink
	the reset is a button, with one it is a decision.

	Copied from the source game's Earth table, carried to a trillion angels. The full table runs
	to quadrillions; that is far past anything reachable and the pattern is plain.

	**One deliberate departure, flagged.** The wiki says angel upgrades are lost on each reset.
	Taken literally that makes them strictly bad -- you would lose the angels *and* the upgrade,
	so nobody would ever buy one, and a sink nobody uses is not a sink. Read alongside entries
	like "+10 Newspaper Delivery", which only mean anything as a permanent head start, the more
	likely reading is that the sentence is about accountants and these are permanent. They are
	implemented as permanent here. Worth checking against the Steam build before launch.

	Accountants -- the per-business managers bought with angels for a 10% cost discount -- are
	deliberately **not** carried yet, precisely because their reset semantics are the part the
	wiki is ambiguous about and shipping a mechanic nobody understands is worse than shipping
	without it.

	Pure data. No logic, no functions, frozen.
]]

local Types = require(script.Parent.Parent.Types)

type AngelUpgradeConfig = Types.AngelUpgradeConfig

--[[
	Ordered by cost.

	`kind` is one of:
	* `allProfit` -- multiplies every business's profit by `amount`
	* `effectiveness` -- adds `amount` to angel effectiveness, so 0.02 raises each angel from
	  +2% to +4%
	* `startingUnits` -- grants `amount` free units of `target` at the start of every run,
	  including after a reset. The source game's "Swap", "Surge" and "Merger" line.
]]
local LIST: { AngelUpgradeConfig } = {
	{
		id = "AngelSacrifice",
		displayName = "Angel Sacrifice",
		cost = 10000,
		kind = "allProfit",
		target = "all",
		amount = 3,
	},
	{
		id = "AngelicMutiny",
		displayName = "Angelic Mutiny",
		cost = 100000,
		kind = "effectiveness",
		target = "angel",
		amount = 0.02,
	},
	{
		id = "NewspaperSwap",
		displayName = "Newspaper Swap",
		cost = 25000000,
		kind = "startingUnits",
		target = "NewspaperDelivery",
		amount = 10,
	},
	{
		id = "CarWashSwap",
		displayName = "Car Wash Swap",
		cost = 25000000,
		kind = "startingUnits",
		target = "CarWash",
		amount = 10,
	},
	{
		id = "PizzaSwap",
		displayName = "Pizza Swap",
		cost = 25000000,
		kind = "startingUnits",
		target = "PizzaDelivery",
		amount = 10,
	},
	{
		id = "DonutSwap",
		displayName = "Donut Swap",
		cost = 25000000,
		kind = "startingUnits",
		target = "DonutShop",
		amount = 10,
	},
	{
		id = "AngelicRebellion",
		displayName = "Angelic Rebellion",
		cost = 100000000,
		kind = "effectiveness",
		target = "angel",
		amount = 0.02,
	},
	{
		id = "NewspaperSurge",
		displayName = "Newspaper Surge",
		cost = 250000000,
		kind = "startingUnits",
		target = "NewspaperDelivery",
		amount = 50,
	},
	{
		id = "CarWashSurge",
		displayName = "Car Wash Surge",
		cost = 250000000,
		kind = "startingUnits",
		target = "CarWash",
		amount = 50,
	},
	{
		id = "PizzaSurge",
		displayName = "Pizza Surge",
		cost = 250000000,
		kind = "startingUnits",
		target = "PizzaDelivery",
		amount = 50,
	},
	{
		id = "DonutSurge",
		displayName = "Donut Surge",
		cost = 250000000,
		kind = "startingUnits",
		target = "DonutShop",
		amount = 50,
	},
	{
		id = "AngelicSelection",
		displayName = "Angelic Selection",
		cost = 1000000000,
		kind = "allProfit",
		target = "all",
		amount = 5,
	},
	{
		id = "NewspaperMerger",
		displayName = "Newspaper Merger",
		cost = 25000000000,
		kind = "startingUnits",
		target = "NewspaperDelivery",
		amount = 50,
	},
	{
		id = "CarWashMerger",
		displayName = "Car Wash Merger",
		cost = 25000000000,
		kind = "startingUnits",
		target = "CarWash",
		amount = 50,
	},
	{
		id = "PizzaMerger",
		displayName = "Pizza Merger",
		cost = 25000000000,
		kind = "startingUnits",
		target = "PizzaDelivery",
		amount = 50,
	},
	{
		id = "DonutMerger",
		displayName = "Donut Merger",
		cost = 25000000000,
		kind = "startingUnits",
		target = "DonutShop",
		amount = 50,
	},
	{
		id = "DivineIntervention",
		displayName = "Divine Intervention",
		cost = 100000000000,
		kind = "allProfit",
		target = "all",
		amount = 9,
	},
	{
		id = "RaptureContingent",
		displayName = "Rapture Contingent",
		cost = 1000000000000,
		kind = "allProfit",
		target = "all",
		amount = 11,
	},
}

local BY_ID: { [string]: AngelUpgradeConfig } = {}
for index, entry in LIST do
	local frozen = table.freeze(entry)
	LIST[index] = frozen
	BY_ID[frozen.id] = frozen
end

return table.freeze({
	list = table.freeze(LIST),
	byId = table.freeze(BY_ID),
})
