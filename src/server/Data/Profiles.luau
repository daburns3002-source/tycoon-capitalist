--!strict
--[[
	DataStore profiles: load, save, and a session lock so two servers cannot fight over one.

	The lock is the part worth reading carefully. Without it, a player who rejoins quickly --
	teleporting, a disconnect and reconnect, two devices -- can end up live on two servers at
	once, and the loser's last write silently discards whatever the winner did. In an idle game
	that is weeks of progress, and the player has no way to tell it happened.

	So every load takes a lock stamped with this server's job id and the time. Another server
	seeing a *fresh* lock refuses to load. A lock older than `LOCK_TIMEOUT` is treated as
	abandoned -- a crashed server never releases its locks, and refusing those forever would
	lock players out permanently.

	`UpdateAsync` is used rather than Get-then-Set throughout, because it is the only operation
	the DataStore API makes atomic, and a lock implemented on top of a non-atomic read/write is
	not a lock.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Serialise = require(script.Parent.Serialise)

local Profiles = {}

local STORE_NAME = "Plots"
local STORE_SCOPE = "v1"

--[[ How long before another server may take a lock it did not place. ]]
local LOCK_TIMEOUT = 120

--[[ How long to keep retrying a load before giving up and letting the player in unsaved. ]]
local LOAD_ATTEMPTS = 4
local RETRY_DELAY = 2

export type LoadResult = {
	stored: unknown,
	--[[
		False when the profile could not be read or locked.

		A player in this state still gets to play -- being bounced out because a DataStore was
		briefly unavailable is worse than a session that does not save -- but nothing is written
		for them, so a failed read can never overwrite a good profile with a blank one. That is
		the single most destructive thing a save system can do.
	]]
	canSave: boolean,
	reason: string?,
}

local store: DataStore? = nil
local available = true

local function getStore(): DataStore?
	if not available then
		return nil
	end
	if store then
		return store
	end

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME, STORE_SCOPE)
	end)

	if not ok or result == nil then
		-- Studio without API access enabled, or a service outage. Play continues unsaved.
		available = false
		warn("[profiles] DataStore unavailable; this session will not save")
		return nil
	end

	store = result
	return store
end

local function keyFor(userId: number): string
	return `plot_{userId}`
end

local function lockIsStale(lock: unknown): boolean
	if typeof(lock) ~= "table" then
		return true
	end

	local placedAt = (lock :: { placedAt: unknown }).placedAt
	if typeof(placedAt) ~= "number" then
		return true
	end
	return os.time() - placedAt > LOCK_TIMEOUT
end

--[[
	Read a profile and take its lock, retrying a few times before giving up.

	Returns the stored table (nil for a new player) and whether this server may write.
]]
function Profiles.load(userId: number): LoadResult
	local dataStore = getStore()
	if dataStore == nil then
		return { stored = nil, canSave = false, reason = "datastore unavailable" }
	end

	local jobId = if RunService:IsStudio() then "studio" else game.JobId

	for attempt = 1, LOAD_ATTEMPTS do
		local blocked = false

		local ok, result = pcall(function()
			return dataStore:UpdateAsync(keyFor(userId), function(current: any)
				if typeof(current) == "table" and current.lock ~= nil then
					if current.lock.jobId ~= jobId and not lockIsStale(current.lock) then
						blocked = true
						-- Returning nil aborts the update, leaving the other server's lock be.
						return nil
					end
				end

				local profile = if typeof(current) == "table" then current else {}
				profile.lock = { jobId = jobId, placedAt = os.time() }
				return profile
			end)
		end)

		if ok and not blocked then
			local data = if typeof(result) == "table" then (result :: any).data else nil
			return { stored = data, canSave = true }
		end

		if attempt < LOAD_ATTEMPTS then
			task.wait(RETRY_DELAY)
		end
	end

	return {
		stored = nil,
		canSave = false,
		reason = "profile is locked by another server",
	}
end

--[[
	Write a profile.

	`releaseLock` is true when the player is leaving, false for an autosave of a live session.
	Writing through UpdateAsync rather than SetAsync keeps the lock check and the write atomic,
	so a server that lost its lock while running cannot clobber whoever holds it now.
]]
function Profiles.save(
	userId: number,
	profile: Serialise.SavedProfile,
	releaseLock: boolean
): boolean
	local dataStore = getStore()
	if dataStore == nil then
		return false
	end

	local jobId = if RunService:IsStudio() then "studio" else game.JobId

	local ok = pcall(function()
		dataStore:UpdateAsync(keyFor(userId), function(current: any)
			if typeof(current) == "table" and current.lock ~= nil then
				if current.lock.jobId ~= jobId and not lockIsStale(current.lock) then
					-- Someone else owns this profile now. Abandon the write rather than win it.
					return nil
				end
			end

			local next = if typeof(current) == "table" then current else {}
			next.data = profile
			next.lock = if releaseLock then nil else { jobId = jobId, placedAt = os.time() }
			return next
		end)
	end)

	if not ok then
		warn(`[profiles] save failed for {userId}`)
	end
	return ok
end

--[[ Whether saving is possible at all in this session. Surfaced so the server can say so once. ]]
function Profiles.isAvailable(): boolean
	getStore()
	return available
end

function Profiles.playerName(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	return if player then player.Name else tostring(userId)
end

return table.freeze(Profiles)
