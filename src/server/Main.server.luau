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
local PlotService = require(script.Parent.Plot.PlotService)
local Production = require(script.Parent.Tick.Production)

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

local function onPlayerAdded(player: Player): ()
	local entry = PlotService.load(player)

	local function onCharacterAdded(): ()
		PlotService.teleportToPlot(player, entry)
		Handlers.pushSnapshot(player, entry)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded()
	end

	Handlers.pushSnapshot(player, entry)
end

local function main(): ()
	Remotes.createAll()
	Handlers.bind()

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		PlotService.unload(player)
	end)

	-- Players who joined before this script ran.
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

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
