--!strict
--[[
	What the managers earned while nobody was watching.

	This is the mechanic that makes an idle game worth coming back to, and it is also the one
	with the most attractive exploit surface in the whole project: anything that scales a payout
	by an elapsed time is worth lying about.

	So the elapsed time comes from `os.time()` on the server, compared against the `savedAt`
	written into the profile by the server. The client never supplies, confirms or influences it.
	It is also clamped at both ends -- a negative interval (a clock that moved backwards, a
	profile written by a server whose clock was ahead) pays nothing rather than something
	strange.

	Only managed businesses earn. An unmanaged business needs a tap to start each cycle, so it
	earned nothing while the player was away, which is exactly how the source game behaves and is
	most of the reason to hire a manager at all.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNumber = require(Shared.Economy.BigNumber)
local Types = require(Shared.Types)

local PlotState = require(script.Parent.Parent.Plot.PlotState)

local Offline = {}

--[[
	The longest absence that pays.

	AdVenture Capitalist pays for an unbounded absence. A cap is a deliberate departure, for two
	reasons that have nothing to do with balance: a server whose clock is wrong, or a profile
	restored from a backup, can otherwise produce an interval of years and a payout that ruins
	the save it lands in. Twenty-four hours is long enough that a normal player never meets it.

	Raise it here if the design wants longer; it is a single constant on purpose.
]]
local MAX_OFFLINE_SECONDS = 24 * 60 * 60

Offline.maxSeconds = MAX_OFFLINE_SECONDS

export type Result = {
	seconds: number,
	earned: Types.BigNumber,
	businesses: number,
}

--[[
	Settle an absence and credit the plot.

	Returns how long was counted, what it paid, and how many businesses contributed, so the
	welcome-back panel can say something specific rather than just showing a number.

	`now` is passed in so one join settles against a single timestamp and so this is testable
	without waiting a day.
]]
function Offline.settle(plot: Types.PlotState, savedAt: number, now: number): Result
	local elapsed = now - savedAt
	if elapsed <= 0 then
		return { seconds = 0, earned = BigNumber.zero, businesses = 0 }
	end

	elapsed = math.min(elapsed, MAX_OFFLINE_SECONDS)

	local total = BigNumber.zero
	local contributing = 0

	for id, state in plot.businesses do
		if not state.hasManager or state.unitsOwned <= 0 then
			continue
		end

		local duration = PlotState.cycleSeconds(plot, id)
		if duration <= 0 then
			continue
		end

		local cycles = math.floor(elapsed / duration)
		if cycles <= 0 then
			continue
		end

		local payout = PlotState.payout(plot, id)
		if BigNumber.isZero(payout) then
			continue
		end

		total = BigNumber.add(total, BigNumber.mulNumber(payout, cycles))
		contributing += 1
	end

	if not BigNumber.isZero(total) then
		-- Through `credit`, so lifetime earnings move with it. Offline money counts toward
		-- angels exactly as earned money does; crediting cash directly would quietly make
		-- idling worth less than playing.
		PlotState.credit(plot, total)
	end

	return { seconds = elapsed, earned = total, businesses = contributing }
end

return table.freeze(Offline)
