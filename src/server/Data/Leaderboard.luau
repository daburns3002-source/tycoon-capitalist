--!strict
--[[
	The global lifetime-earnings leaderboard.

	The interesting problem here is that an OrderedDataStore sorts by a plain integer, and
	lifetime earnings in this game reach ~1e306. There is no integer that holds that.

	The fix is to rank by the **logarithm** rather than the value. log10 is strictly increasing,
	so ordering by `floor(log10(earnings) * PRECISION)` produces exactly the same ranking as
	ordering by the earnings themselves -- no approximation in the result, only in the stored
	key. At a precision of a million, two players tie only if their earnings are within a factor
	of 1.0000023 of each other, which is far finer than anyone will ever notice.

	It also means the stored score can be turned back into a displayable figure -- 10^(score /
	PRECISION) -- so the board shows real money without a second store holding the mantissa.

	Like `Profiles`, the store is injectable so the encoding can be tested without a published
	place.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNumber = require(Shared.Economy.BigNumber)
local Types = require(Shared.Types)

local Leaderboard = {}

local STORE_NAME = "LifetimeEarnings"
local STORE_SCOPE = "v1"

--[[ Log-space resolution. A million gives ties only within a factor of 1.0000023. ]]
local PRECISION = 1000000

--[[
	Shifts the log so every positive amount lands above zero.

	Without it, log10($1) is 0 and a player with a dollar scores the same as a player with
	nothing. Ten decades of headroom means anything down to a ten-billionth of a dollar still
	outranks an empty account, and the top of the range -- (306 + 10) million -- is nowhere near
	an integer's limit.
]]
local LOG_OFFSET = 10

Leaderboard.precision = PRECISION

export type OrderedStore = {
	SetAsync: (self: any, key: string, value: number) -> (),
	GetSortedAsync: (self: any, ascending: boolean, pageSize: number) -> any,
}

export type Entry = {
	userId: number,
	displayName: string,
	earnings: Types.BigNumber,
}

local store: OrderedStore? = nil
local available = true
local injected: OrderedStore? = nil

function Leaderboard.configure(fake: OrderedStore?): ()
	injected = fake
	if fake ~= nil then
		available = true
	end
end

local function getStore(): OrderedStore?
	if injected then
		return injected
	end
	if not available then
		return nil
	end
	if store then
		return store
	end

	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(STORE_NAME, STORE_SCOPE)
	end)

	if not ok or result == nil then
		available = false
		warn("[leaderboard] OrderedDataStore unavailable; rankings will not update")
		return nil
	end

	store = result :: any
	return store
end

--[[
	Earnings to a sortable integer.

	Zero and anything below it score zero rather than negative infinity, so a new player sorts
	at the bottom instead of breaking the store.
]]
function Leaderboard.encode(earnings: Types.BigNumber): number
	if BigNumber.isZero(earnings) or earnings.mantissa < 0 then
		return 0
	end

	local logValue = BigNumber.log10(earnings)
	-- At least 1, so any positive balance is distinguishable from no balance at all.
	return math.max(math.floor((logValue + LOG_OFFSET) * PRECISION), 1)
end

--[[ And back, for display. Exact to the stored resolution. ]]
function Leaderboard.decode(score: number): Types.BigNumber
	if score <= 0 then
		return BigNumber.zero
	end

	local logValue = score / PRECISION - LOG_OFFSET
	local whole = math.floor(logValue)
	return BigNumber.fromParts(10 ^ (logValue - whole), whole)
end

--[[
	Publish a player's lifetime earnings.

	Called on save rather than on every payout: the ranking only has to be roughly current, and
	an OrderedDataStore write per cycle would blow the request budget instantly.
]]
function Leaderboard.publish(userId: number, lifetimeEarnings: Types.BigNumber): boolean
	local ordered = getStore()
	if ordered == nil then
		return false
	end

	local score = Leaderboard.encode(lifetimeEarnings)
	local ok = pcall(function()
		ordered:SetAsync(`player_{userId}`, score)
	end)
	return ok
end

local nameCache: { [number]: string } = {}

local function displayNameFor(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end

	-- A player who is here already has a name; otherwise ask Roblox once and remember it.
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end

	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)

	local name = if ok and typeof(result) == "string" then result else "Someone"
	nameCache[userId] = name
	return name
end

--[[
	The top `count` players, best first.

	Returns an empty list rather than erroring when the store is unavailable, so a caller can
	render "no rankings yet" without special-casing the failure.
]]
function Leaderboard.top(count: number): { Entry }
	local ordered = getStore()
	if ordered == nil then
		return {}
	end

	local ok, pages = pcall(function()
		return ordered:GetSortedAsync(false, count)
	end)
	if not ok or pages == nil then
		return {}
	end

	local okPage, rows = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not okPage or typeof(rows) ~= "table" then
		return {}
	end

	local entries: { Entry } = {}
	for _, row in rows do
		local key = tostring(row.key)
		local userId = tonumber(key:match("player_(%d+)") or "")
		if userId == nil then
			continue
		end

		table.insert(entries, {
			userId = userId,
			displayName = displayNameFor(userId),
			earnings = Leaderboard.decode(tonumber(row.value) or 0),
		})
	end

	return entries
end

return table.freeze(Leaderboard)
