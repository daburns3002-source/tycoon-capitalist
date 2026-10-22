--!strict
--[[
	Server entry point.

	Wires the pieces together and owns the production tick. Deliberately thin: anything with
	logic in it belongs in a module that can be reasoned about on its own.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)

local Handlers = require(script.Parent.Net.Handlers)
local Leaderboard = require(script.Parent.Data.Leaderboard)
local PlotBuilder = require(script.Parent.World.PlotBuilder)
local PlotService = require(script.Parent.Plot.PlotService)
local Production = require(script.Parent.Tick.Production)
local Profiles = require(script.Parent.Data.Profiles)

--[[
	Tick rate for settling cycles.

	The Lemonade Stand's base cycle is 0.6 seconds and halves up to twelve times, so completion
	can land far inside one frame. That is fine: completion is derived from a timestamp, not
	counted in ticks, so a slower tick delays *notification* of a payout but never loses one or
	changes its size. Ten per second keeps the cash counter feeling live without doing per-frame
	work for a game whose fastest event is a tenth of a second.
]]
local TICK_INTERVAL = 0.1

--[[
	How often an idle client still gets a snapshot.

	Even with nothing completing, the panel wants the progress bar re-anchored occasionally so a
	long cycle cannot drift from the server's view. The client interpolates between these.
]]
local IDLE_SNAPSHOT_INTERVAL = 1

--[[
	How often a live session is written back.

	A crash, a server shutdown Roblox does not give us time to handle, or a player whose client
	dies without a clean leave all lose everything since the last write. Sixty seconds bounds
	that at a minute of progress, well inside the DataStore request budget for any plausible
	server population.
]]
local AUTOSAVE_INTERVAL = 60

--[[
	How often the ranking boards are refreshed.

	A sorted read is expensive and the standings barely move, so this is deliberately slow. Two
	minutes is often enough that a player who overtakes someone sees it within a session.
]]
local RANKING_INTERVAL = 120

local function onPlayerAdded(player: Player): ()
	-- Yields: reads the profile, takes the lock, settles the absence.
	local entry = PlotService.load(player)
	if player.Parent == nil then
		-- Left while the profile was loading. Release the lock we just took.
		PlotService.unload(player)
		return
	end

	local function onCharacterAdded(): ()
		PlotService.teleportToPlot(player, entry)
		Handlers.pushSnapshot(player, entry)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded()
	end

	Handlers.pushSnapshot(player, entry)
	Handlers.pushWelcomeBack(player, entry)
end

local function main(): ()
	Remotes.createAll()
	Handlers.bind()

	if not Profiles.isAvailable() then
		warn("[Tycoon Capitalist] DataStores unavailable -- nothing will be saved this session.")
		warn(
			"[Tycoon Capitalist] In Studio: Game Settings > Security > Enable Studio Access to API Services."
		)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		-- Spawned because PlotService.load yields on the DataStore, and blocking PlayerAdded
		-- would stall every other player joining behind this one.
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		PlotService.unload(player)
	end)

	-- Players who joined before this script ran.
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	--[[
		Autosave.

		Separate from the production tick so a slow DataStore call can never delay a payout, and
		spread across players rather than written in one burst.
	]]
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for userId, entry in PlotService.all() do
				PlotService.save(userId, entry, false)
			end
		end
	end)

	--[[
		Ranking boards.

		Fetched once for the whole server and written to every plot's board, rather than fetched
		per player -- the standings are global, so one read serves everybody.
	]]
	task.spawn(function()
		local Format = require(Shared.Economy.Format)
		while true do
			local top = Leaderboard.top(8)

			local lines: { string } = {}
			for index, row in top do
				table.insert(lines, `{index}.  {row.displayName}  --  {Format.money(row.earnings)}`)
			end

			for _, entry in PlotService.all() do
				PlotBuilder.setRanking(entry.world, lines)
			end

			task.wait(RANKING_INTERVAL)
		end
	end)

	--[[
		Last write before the server goes down.

		Roblox gives a short window here and nothing after it, so this is the difference between
		a graceful shutdown costing nothing and costing everyone their last minute.
	]]
	game:BindToClose(function()
		for userId, entry in PlotService.all() do
			PlotService.save(userId, entry, true)
		end
	end)

	local sinceTick = 0
	local sinceIdleSnapshot = 0

	RunService.Heartbeat:Connect(function(delta: number)
		sinceTick += delta
		if sinceTick < TICK_INTERVAL then
			return
		end
		sinceTick = 0
		sinceIdleSnapshot += TICK_INTERVAL

		-- One timestamp for every plot, so two players' cycles cannot settle against clocks
		-- that differ by a few microseconds.
		local now = os.clock()
		local pushIdle = sinceIdleSnapshot >= IDLE_SNAPSHOT_INTERVAL
		if pushIdle then
			sinceIdleSnapshot = 0
		end

		for userId, entry in PlotService.all() do
			local payments = Production.advance(entry.state, now)
			local player = PlotService.playerFor(userId)
			if player == nil then
				continue
			end

			if #payments > 0 then
				Handlers.notifyPaid(player, payments)
				Handlers.pushSnapshot(player, entry)
			elseif pushIdle and entry.panelOpen then
				Handlers.pushSnapshot(player, entry)
			end
		end
	end)

	print("[Tycoon Capitalist] server ready")
end

main()

return nil
