--!strict
--[[
	Production -- advancing cycles and paying them out.

	The server owns time. A cycle is stored as the timestamp it started at, and completion is
	derived by comparing that against the server's own clock. Nothing here reads a value the
	client sent, which is the whole point: elapsed time is the single most attractive thing to
	lie about in an idle game.

	Only whole completed cycles pay. A cycle three-quarters through has earned nothing yet,
	which is how the source game behaves and why collecting just before a long cycle completes
	is a real strategy.

	Unmanaged businesses stop after one cycle and wait for another click. Managed ones restart
	immediately, which is what makes this an idle game rather than a clicker -- and because
	completion is derived from a timestamp rather than ticked, a managed business that ran for
	an hour while nobody looked settles correctly in one step. That is the same code path
	offline accrual will use in Phase 5.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNumber = require(Shared.Economy.BigNumber)
local Types = require(Shared.Types)

local PlotState = require(script.Parent.Parent.Plot.PlotState)

type PlotState = Types.PlotState

local Production = {}

--[[
	How many cycles a business may settle in one advance.

	A guard rather than a balance decision. If a server hitch or a clock jump produced an
	absurd elapsed time, this bounds the work done in one frame instead of locking the thread
	while it multiplies out a million cycles. Phase 5's offline accrual will clamp elapsed time
	before it ever reaches here, so this should never bind in normal play.
]]
local MAX_CYCLES_PER_ADVANCE = 10000

-- Defined in Shared.Types so the client can name the same shape when it receives one.
export type Payment = Types.CyclePayment

--[[
	Settle every active cycle on a plot against `now`.

	Returns the payments made, so the caller can push a number pop per business rather than
	re-deriving what changed. An empty list means nothing completed and no snapshot is needed.

	`now` is passed in rather than read here so that one tick settles every plot against a
	single consistent timestamp, and so Phase 5 can replay an offline interval through the same
	function.
]]
function Production.advance(plot: PlotState, now: number): { Payment }
	local payments: { Payment } = {}

	for id, state in plot.businesses do
		--[[
			A managed business never sits idle.

			This is the whole mechanic: the tick starts a cycle for any business that has a
			manager and is not already running one. It covers hiring, rejoining, and the moment
			after a payout, without any of those paths needing to remember to kick it off.
		]]
		if state.hasManager and state.cycleStartedAt == nil and state.unitsOwned > 0 then
			state.cycleStartedAt = now
		end

		local startedAt = state.cycleStartedAt
		if startedAt == nil then
			continue
		end
		if state.unitsOwned <= 0 then
			-- Cannot happen in normal play, but a business with no units must not pay out.
			state.cycleStartedAt = nil
			continue
		end

		local duration = PlotState.cycleSeconds(plot, id)
		if duration <= 0 then
			state.cycleStartedAt = nil
			continue
		end

		local elapsed = now - startedAt
		if elapsed < duration then
			continue
		end

		local completed = math.floor(elapsed / duration)
		if completed > MAX_CYCLES_PER_ADVANCE then
			completed = MAX_CYCLES_PER_ADVANCE
		end

		-- An unmanaged business pays once and stops; it does not bank cycles it was never
		-- clicked for.
		if not state.hasManager then
			completed = 1
		end

		local payout = PlotState.payout(plot, id)
		local amount = if completed == 1 then payout else BigNumber.mulNumber(payout, completed)

		PlotState.credit(plot, amount)

		if state.hasManager then
			-- Carry the remainder so a managed business never loses partial progress to the
			-- tick rate.
			state.cycleStartedAt = startedAt + completed * duration
		else
			state.cycleStartedAt = nil
		end

		table.insert(payments, {
			id = id,
			cycles = completed,
			amount = amount,
		})
	end

	return payments
end

--[[
	Begin a cycle, if one is not already running.

	Returns false when the business is already cycling or owns nothing, so a client spamming
	clicks cannot restart a cycle early and collect faster than the cycle time allows. That is
	the exploit this function exists to close.
]]
function Production.startCycle(plot: PlotState, id: Types.BusinessId, now: number): boolean
	local state = plot.businesses[id]
	if state == nil then
		return false
	end
	if state.unitsOwned <= 0 then
		return false
	end
	if state.cycleStartedAt ~= nil then
		return false
	end

	state.cycleStartedAt = now
	return true
end

--[[
	How far through its cycle a business is, in seconds. Zero when idle.

	The client interpolates the bar from this rather than being sent a fill fraction every
	frame, so a snapshot every few hundred milliseconds still renders smoothly.
]]
function Production.cycleElapsed(plot: PlotState, id: Types.BusinessId, now: number): number
	local state = plot.businesses[id]
	if state == nil or state.cycleStartedAt == nil then
		return 0
	end

	local elapsed = now - state.cycleStartedAt
	return math.max(elapsed, 0)
end

return table.freeze(Production)
