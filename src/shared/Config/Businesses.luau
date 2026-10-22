--!strict
--[[
	The Earth business table, copied from AdVenture Capitalist.

	Every value here is the source game's, verified against the Steam build and the wiki table
	reproduced in docs/RESEARCH-advcap.md. This file is data: no logic, no functions, frozen.
	Tuning the game means editing these numbers and nothing else.

	Two things worth knowing before changing anything:

	* The Lemonade Stand's initial cost is 4/1.07, not 4. The player starts owning one free
	  stand and the *second* costs exactly $4, so the formula needs that base for unit 2 to
	  price correctly. The wiki rounds it to 3.738, which prices unit 2 at $3.99966; we keep
	  the exact quotient instead. Never show either figure to a player.
	* The wiki's worked example claims the second Car Wash costs $829.92. It does not: that is
	  728 x 1.14, and the initial cost is 720. The correct price is $820.80. Checked against
	  the Steam build.
	* Costs grow geometrically and revenue grows linearly. That divergence is the entire
	  difficulty curve, and it is why the Angel Investor reset layer has to exist.

	Manager costs are the source game's Earth normal managers -- the ones bought with cash that
	auto-restart a cycle. Accountants and discount managers cost angels and live in the angel
	upgrade tables, not here.
]]

local BigNumber = require(script.Parent.Parent.Economy.BigNumber)
local Types = require(script.Parent.Parent.Types)

type BusinessConfig = Types.BusinessConfig

local p = BigNumber.fromParts

--[[
	Ordered cheapest to most expensive. `order` is also the vertical order in the UI and the
	left-to-right order of the buildings on the plot.
]]
local LIST: { BusinessConfig } = {
	{
		id = "LemonadeStand",
		displayName = "Lemonade Stand",
		order = 1,
		initialCost = p(4 / 1.07, 0),
		coefficient = 1.07,
		cycleSeconds = 0.6,
		revenuePerCycle = p(1, 0),
		managerCost = p(1, 3),
		managerName = "Cabe Johnson",
	},
	{
		id = "NewspaperDelivery",
		displayName = "Newspaper Delivery",
		order = 2,
		initialCost = p(6, 1),
		coefficient = 1.15,
		cycleSeconds = 3,
		revenuePerCycle = p(6, 1),
		managerCost = p(1.5, 4),
		managerName = "Perry Black",
	},
	{
		id = "CarWash",
		displayName = "Car Wash",
		order = 3,
		initialCost = p(7.2, 2),
		coefficient = 1.14,
		cycleSeconds = 6,
		revenuePerCycle = p(5.4, 2),
		managerCost = p(1, 5),
		managerName = "W.W. Heisenbird",
	},
	{
		id = "PizzaDelivery",
		displayName = "Pizza Delivery",
		order = 4,
		initialCost = p(8.64, 3),
		coefficient = 1.13,
		cycleSeconds = 12,
		revenuePerCycle = p(4.32, 3),
		managerCost = p(5, 5),
		managerName = "Mama Sean",
	},
	{
		id = "DonutShop",
		displayName = "Donut Shop",
		order = 5,
		initialCost = p(1.0368, 5),
		coefficient = 1.12,
		cycleSeconds = 24,
		revenuePerCycle = p(5.184, 4),
		managerCost = p(1.2, 6),
		managerName = "Jim Thorton",
	},
	{
		id = "ShrimpBoat",
		displayName = "Shrimp Boat",
		order = 6,
		initialCost = p(1.24416, 6),
		coefficient = 1.11,
		cycleSeconds = 96,
		revenuePerCycle = p(6.2208, 5),
		managerCost = p(1, 7),
		managerName = "Forest Trump",
	},
	{
		id = "HockeyTeam",
		displayName = "Hockey Team",
		order = 7,
		initialCost = p(1.492992, 7),
		coefficient = 1.10,
		cycleSeconds = 384,
		revenuePerCycle = p(7.46496, 6),
		managerCost = p(1.11111111, 8),
		managerName = "Dawn Cheri",
	},
	{
		id = "MovieStudio",
		displayName = "Movie Studio",
		order = 8,
		initialCost = p(1.7915904, 8),
		coefficient = 1.09,
		cycleSeconds = 1536,
		revenuePerCycle = p(8.957952, 7),
		managerCost = p(5.55555555, 8),
		managerName = "Stefani Speilburger",
	},
	{
		id = "Bank",
		displayName = "Bank",
		order = 9,
		initialCost = p(2.14990848, 9),
		coefficient = 1.08,
		cycleSeconds = 6144,
		revenuePerCycle = p(1.07495424, 9),
		managerCost = p(1, 10),
		managerName = "The Dark Lord",
	},
	{
		id = "OilCompany",
		displayName = "Oil Company",
		order = 10,
		initialCost = p(2.579890176, 10),
		coefficient = 1.07,
		cycleSeconds = 36864,
		revenuePerCycle = p(2.9668737024, 10),
		managerCost = p(1, 11),
		managerName = "Derrick Plainview",
	},
}

local BY_ID: { [Types.BusinessId]: BusinessConfig } = {}
for _, entry in LIST do
	BY_ID[entry.id] = table.freeze(entry)
end

--[[
	Unit counts at which a business's production cycle halves.

	Each business halves on its own count, and every business halves again each time *all ten*
	cross one of these marks. Twelve halvings maximum, so the floor is 1/4096 of the initial
	cycle -- which is what turns the Oil Company's ten-hour cycle into about nine seconds.
]]
local CYCLE_MILESTONES: { number } = { 25, 50, 100, 200, 300, 400 }

--[[ The source game stops at twelve halvings; past that the cycle does not shorten further. ]]
local MAX_CYCLE_HALVINGS = 12

--[[
	Highest unit count the source game allows: the 32-bit signed integer limit. Buying past it
	wraps and subtracts the player's money, so it is a hard cap rather than a soft one.
]]
local MAX_UNITS = 2147483647

return table.freeze({
	list = table.freeze(LIST),
	byId = table.freeze(BY_ID),
	cycleMilestones = table.freeze(CYCLE_MILESTONES),
	maxCycleHalvings = MAX_CYCLE_HALVINGS,
	maxUnits = MAX_UNITS,
})
