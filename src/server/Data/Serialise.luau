--!strict
--[[
	Turning a plot into something a DataStore will hold, and back.

	In an idle game the save file *is* the player's entire investment -- weeks of it, eventually.
	So this module is deliberately conservative: an explicit schema version, a migration seam
	that exists before it is needed, and a load that tolerates a malformed or partial profile
	rather than erroring and handing the player a fresh plot.

	What is stored and what is not:

	* Money is stored as BigNumber's two-element array, which is exact and compact.
	* `cycleStartedAt` is **not** stored. It is an `os.clock()` reading, which is meaningful only
	  inside the process that produced it -- saving one and comparing it to a different server's
	  clock would produce an arbitrary elapsed time. Offline earnings are derived from `savedAt`,
	  which is wall-clock, and managed cycles restart on the next tick anyway.
	* Multipliers are not stored. They are derived from owned upgrades and unit counts, so
	  storing them would create a second source of truth that could load out of step with the
	  thing it was derived from.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNumber = require(Shared.Economy.BigNumber)
local Businesses = require(Shared.Config.Businesses)
local Types = require(Shared.Types)

local Serialise = {}

--[[
	Bump this whenever the stored shape changes, and add a migration below.

	A schema change without a version bump is the one mistake here that silently corrupts live
	profiles, which is why `AGENTS.md` makes it a blocking review finding.
]]
local SCHEMA_VERSION = 1

Serialise.schemaVersion = SCHEMA_VERSION

export type SavedBusiness = {
	units: number,
	manager: boolean,
	accountant: boolean,
}

export type SavedProfile = {
	version: number,
	savedAt: number,
	cash: { number },
	lifetimeEarnings: { number },
	earningsBeforeThisRun: { number },
	angels: number,
	angelsSacrificed: number,
	businesses: { [string]: SavedBusiness },
	upgrades: { string },
}

--[[ Plot to stored table. `savedAt` is wall-clock, since offline accrual depends on it. ]]
function Serialise.save(plot: Types.PlotState): SavedProfile
	local businesses: { [string]: SavedBusiness } = {}
	for id, state in plot.businesses do
		businesses[id] = {
			units = state.unitsOwned,
			manager = state.hasManager,
			accountant = state.hasAccountant,
		}
	end

	-- Stored as a list rather than a map: a map of ids to `true` doubles the payload for no
	-- information, and the owned set is small.
	local upgrades: { string } = {}
	for id, owned in plot.upgradesOwned do
		if owned then
			table.insert(upgrades, id)
		end
	end
	table.sort(upgrades)

	return {
		version = SCHEMA_VERSION,
		savedAt = os.time(),
		cash = BigNumber.serialise(plot.cash),
		lifetimeEarnings = BigNumber.serialise(plot.lifetimeEarnings),
		earningsBeforeThisRun = BigNumber.serialise(plot.earningsBeforeThisRun),
		angels = plot.angels,
		angelsSacrificed = plot.angelsSacrificed,
		businesses = businesses,
		upgrades = upgrades,
	}
end

--[[
	Migrate a stored profile forward to the current schema.

	Empty today because there is only one version. It exists now so that the first migration is
	a case in a function that already runs, rather than a new concept introduced under pressure
	when live profiles are at stake.
]]
local function migrate(stored: SavedProfile): SavedProfile
	-- if stored.version < 2 then ... stored.version = 2 end
	return stored
end

local function readNumber(value: unknown, fallback: number): number
	if typeof(value) == "number" and value == value and value ~= math.huge then
		return value
	end
	return fallback
end

local function readBig(value: unknown): Types.BigNumber
	if typeof(value) ~= "table" then
		return BigNumber.zero
	end
	return BigNumber.deserialise(value :: { number })
end

--[[
	Stored table into a plot, defaulting anything missing or malformed.

	`makeEmpty` supplies a fresh plot to fill in, so this module does not need to know how a new
	plot is constructed. Every field is read defensively: a profile that fails to parse cleanly
	should cost the player the corrupt fields, not the whole save.
]]
function Serialise.load(
	stored: unknown,
	makeEmpty: () -> Types.PlotState
): (Types.PlotState, number?)
	local plot = makeEmpty()
	if typeof(stored) ~= "table" then
		return plot, nil
	end

	local profile = migrate(stored :: SavedProfile)

	plot.cash = readBig(profile.cash)
	plot.lifetimeEarnings = readBig(profile.lifetimeEarnings)
	plot.earningsBeforeThisRun = readBig(profile.earningsBeforeThisRun)
	plot.angels = math.max(math.floor(readNumber(profile.angels, 0)), 0)
	plot.angelsSacrificed = math.max(math.floor(readNumber(profile.angelsSacrificed, 0)), 0)

	if typeof(profile.businesses) == "table" then
		for id, saved in profile.businesses do
			local state = plot.businesses[id]
			-- A business id that is no longer in the config is dropped rather than resurrected.
			if state == nil or Businesses.byId[id] == nil or typeof(saved) ~= "table" then
				continue
			end

			local units = math.floor(readNumber(saved.units, 0))
			state.unitsOwned = math.clamp(units, 0, Businesses.maxUnits)
			state.hasManager = saved.manager == true
			state.hasAccountant = saved.accountant == true
			-- Never restored: see the note at the top of this file.
			state.cycleStartedAt = nil
		end
	end

	if typeof(profile.upgrades) == "table" then
		for _, id in profile.upgrades do
			if typeof(id) == "string" then
				plot.upgradesOwned[id] = true
			end
		end
	end

	local savedAt = readNumber(profile.savedAt, 0)
	return plot, if savedAt > 0 then savedAt else nil
end

return table.freeze(Serialise)
