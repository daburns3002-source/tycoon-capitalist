--!strict
--[[
	Cash upgrades, copied from AdVenture Capitalist.

	The shape of the real table is a repeating tier: ten per-business "profit x3" upgrades in
	ascending price, then one "all businesses x3", then (from the second tier onward) one that
	raises Angel Investor effectiveness by a percentage point.

	The source has 478 of these, running out past a googol. Three tiers are carried here -- 35
	upgrades, the last costing a sextillion -- which is far beyond anything a session will
	reach and leaves the pattern obvious for whoever extends it.

	x3 is not a tuning choice. Every per-business upgrade in the source game is exactly triple,
	and they stack multiplicatively, so owning all three tiers for one business is x27 on top of
	whatever the all-business upgrades contribute.

	Pure data. No logic, no functions, frozen.
]]

local BigNumber = require(script.Parent.Parent.Economy.BigNumber)
local Types = require(script.Parent.Parent.Types)

type UpgradeConfig = Types.UpgradeConfig

local p = BigNumber.fromParts

--[[
	Ordered by price, which is also the order they become relevant.

	`target` is a business id, or "all" for every business, or "angel" for the Angel Investor
	effectiveness line. `multiplier` is the profit factor; for angel upgrades it is the amount
	added to effectiveness instead (0.01 = +1%).
]]
local LIST: { UpgradeConfig } = {
	-- Tier 1
	{
		id = "LittleUmbrellas",
		displayName = "Little Umbrellas",
		target = "LemonadeStand",
		kind = "profit",
		multiplier = 3,
		cost = p(2.5, 5),
	},
	{
		id = "FunnyPages",
		displayName = "Funny Pages",
		target = "NewspaperDelivery",
		kind = "profit",
		multiplier = 3,
		cost = p(5, 5),
	},
	{
		id = "DriveThroughWash",
		displayName = "Drive Through Wash",
		target = "CarWash",
		kind = "profit",
		multiplier = 3,
		cost = p(1, 6),
	},
	{
		id = "RobotCars",
		displayName = "Robot Cars",
		target = "PizzaDelivery",
		kind = "profit",
		multiplier = 3,
		cost = p(5, 6),
	},
	{
		id = "PrePackagedPastries",
		displayName = "Pre-packaged Pastries",
		target = "DonutShop",
		kind = "profit",
		multiplier = 3,
		cost = p(1, 7),
	},
	{
		id = "ShrimpSatellite",
		displayName = "Shrimp Satellite",
		target = "ShrimpBoat",
		kind = "profit",
		multiplier = 3,
		cost = p(2.5, 7),
	},
	{
		id = "TeamJet",
		displayName = "Team Jet",
		target = "HockeyTeam",
		kind = "profit",
		multiplier = 3,
		cost = p(5, 8),
	},
	{
		id = "ThreeDCameras",
		displayName = "3D Cameras",
		target = "MovieStudio",
		kind = "profit",
		multiplier = 3,
		cost = p(1, 10),
	},
	{
		id = "GoldPlatedVaults",
		displayName = "Gold Plated Vaults",
		target = "Bank",
		kind = "profit",
		multiplier = 3,
		cost = p(5, 10),
	},
	{
		id = "SpillProofTankers",
		displayName = "Spill Proof Tankers",
		target = "OilCompany",
		kind = "profit",
		multiplier = 3,
		cost = p(2.5, 11),
	},
	{
		id = "Monopoly",
		displayName = "Monopoly",
		target = "all",
		kind = "profit",
		multiplier = 3,
		cost = p(1, 12),
	},

	-- Tier 2
	{
		id = "NoveltyStraws",
		displayName = "Novelty Straws",
		target = "LemonadeStand",
		kind = "profit",
		multiplier = 3,
		cost = p(2, 13),
	},
	{
		id = "SportsPages",
		displayName = "Sports Pages",
		target = "NewspaperDelivery",
		kind = "profit",
		multiplier = 3,
		cost = p(5, 13),
	},
	{
		id = "AutomaticVacuums",
		displayName = "Automatic Vacuums",
		target = "CarWash",
		kind = "profit",
		multiplier = 3,
		cost = p(1, 14),
	},
	{
		id = "OnlineOrdering",
		displayName = "Online Ordering",
		target = "PizzaDelivery",
		kind = "profit",
		multiplier = 3,
		cost = p(5, 14),
	},
	{
		id = "DonutHoles",
		displayName = "Donut Holes",
		target = "DonutShop",
		kind = "profit",
		multiplier = 3,
		cost = p(1, 15),
	},
	{
		id = "ShrimpMagnets",
		displayName = "Shrimp Magnets",
		target = "ShrimpBoat",
		kind = "profit",
		multiplier = 3,
		cost = p(2, 15),
	},
	{
		id = "EnergyDrinkSponsors",
		displayName = "Energy Drink Sponsors",
		target = "HockeyTeam",
		kind = "profit",
		multiplier = 3,
		cost = p(5, 15),
	},
	{
		id = "GreenScreens",
		displayName = "Green Screens",
		target = "MovieStudio",
		kind = "profit",
		multiplier = 3,
		cost = p(7, 15),
	},
	{
		id = "FreeFancyPens",
		displayName = "Free Fancy Pens",
		target = "Bank",
		kind = "profit",
		multiplier = 3,
		cost = p(1, 16),
	},
	{
		id = "EcoSafePipeline",
		displayName = "Eco-safe Pipeline",
		target = "OilCompany",
		kind = "profit",
		multiplier = 3,
		cost = p(2, 16),
	},
	{
		id = "Monopsony",
		displayName = "Monopsony",
		target = "all",
		kind = "profit",
		multiplier = 3,
		cost = p(5, 16),
	},
	{
		id = "HolyMoola",
		displayName = "Holy Moola",
		target = "angel",
		kind = "angelEffectiveness",
		multiplier = 0.01,
		cost = p(1, 17),
	},

	-- Tier 3
	{
		id = "ImportedIceCubes",
		displayName = "Imported Ice Cubes",
		target = "LemonadeStand",
		kind = "profit",
		multiplier = 3,
		cost = p(2, 18),
	},
	{
		id = "BusinessPages",
		displayName = "Business Pages",
		target = "NewspaperDelivery",
		kind = "profit",
		multiplier = 3,
		cost = p(5, 18),
	},
	{
		id = "MicrofiberSponges",
		displayName = "Microfiber Sponges",
		target = "CarWash",
		kind = "profit",
		multiplier = 3,
		cost = p(7, 18),
	},
	{
		id = "DroneDelivery",
		displayName = "Drone Delivery",
		target = "PizzaDelivery",
		kind = "profit",
		multiplier = 3,
		cost = p(1, 19),
	},
	{
		id = "BaconSprinkles",
		displayName = "Bacon Sprinkles",
		target = "DonutShop",
		kind = "profit",
		multiplier = 3,
		cost = p(2, 19),
	},
	{
		id = "CarbonNanotubeNets",
		displayName = "Carbon Nanotube Nets",
		target = "ShrimpBoat",
		kind = "profit",
		multiplier = 3,
		cost = p(3.5, 19),
	},
	{
		id = "GpsPuckTracker",
		displayName = "GPS Puck Tracker",
		target = "HockeyTeam",
		kind = "profit",
		multiplier = 3,
		cost = p(5, 19),
	},
	{
		id = "SmellOVision",
		displayName = "Smell-O-Vision",
		target = "MovieStudio",
		kind = "profit",
		multiplier = 3,
		cost = p(7.5, 19),
	},
	{
		id = "CreditCardImplants",
		displayName = "Credit Card Implants",
		target = "Bank",
		kind = "profit",
		multiplier = 3,
		cost = p(1, 20),
	},
	{
		id = "HyperloopPumps",
		displayName = "Hyperloop Pumps",
		target = "OilCompany",
		kind = "profit",
		multiplier = 3,
		cost = p(2, 20),
	},
	{
		id = "Illuminati",
		displayName = "Illuminati",
		target = "all",
		kind = "profit",
		multiplier = 3,
		cost = p(5, 20),
	},
	{
		id = "ImmaculateConsumption",
		displayName = "Immaculate Consumption",
		target = "angel",
		kind = "angelEffectiveness",
		multiplier = 0.01,
		cost = p(1, 21),
	},
}

local BY_ID: { [string]: UpgradeConfig } = {}
for index, entry in LIST do
	BY_ID[entry.id] = table.freeze(entry)
	LIST[index] = BY_ID[entry.id]
end

return table.freeze({
	list = table.freeze(LIST),
	byId = table.freeze(BY_ID),
})
