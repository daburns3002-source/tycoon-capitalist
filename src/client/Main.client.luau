--!strict
--[[
	Client entry point.

	Renders and predicts; never decides a number. Deleting this whole folder and rewriting it
	must not change a single value in the game -- that is what makes the server authoritative in
	practice rather than only on paper.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Types = require(Shared.Types)

local BoardInteraction = require(script.Parent.World.BoardInteraction)
local Device = require(script.Parent.Device)
local Hud = require(script.Parent.UI.Hud)
local Panel = require(script.Parent.UI.Panel)

local CLOSE_ACTION = "ClosePanel"

local function main(): ()
	local hud = Hud.new()
	local panel = Panel.new()

	local connections: { RBXScriptConnection } = {}

	table.insert(
		connections,
		Remotes.get(Remotes.toClient.PlotSnapshot).OnClientEvent
			:Connect(function(snapshot: Types.PlotSnapshot)
				hud:setSnapshot(snapshot)
				panel:setSnapshot(snapshot)
			end)
	)

	table.insert(
		connections,
		Remotes.get(Remotes.toClient.CyclePaid).OnClientEvent
			:Connect(function(payments: { Types.CyclePayment })
				for _, payment in payments do
					panel:notifyPaid(payment.id, payment.amount)
				end
			end)
	)

	table.insert(
		connections,
		Remotes.get(Remotes.toClient.IntentRejected).OnClientEvent
			:Connect(function(intent: string, reason: string)
				-- Phase 4 turns this into a toast. Logging it now means a rejected action is
				-- never silent, which is the thing that makes an economy bug hard to find.
				warn(`[panel] {intent} rejected: {reason}`)
			end)
	)

	table.insert(
		connections,
		BoardInteraction.connect(function()
			panel:open()
			hud:setHintVisible(false)
		end)
	)

	-- Escape and the gamepad's B button close the panel. Touch devices have the X button in the
	-- header, which is why that is not conditional on anything.
	ContextActionService:BindAction(CLOSE_ACTION, function(_, state: Enum.UserInputState)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if not panel.isOpen then
			return Enum.ContextActionResult.Pass
		end
		panel:close()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)

	--[[
		Drive the progress bars, every frame.

		This used to be throttled to the device tier's HUD rate -- 30/sec on desktop, 10 on a
		phone -- which was premature optimisation and visibly steppy. The work is one UDim2
		assignment per visible business row, at most ten of them, and only while the panel is
		open. That is nothing next to rendering the frame it rides on, and a progress bar is the
		one thing in this UI whose entire job is to look smooth.

		Device tiering still governs what actually costs frames: shadows, particles, draw
		distance and building detail.
	]]
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function()
			if panel.isOpen then
				panel:step(os.clock())
			end
		end)
	)

	table.insert(
		connections,
		Device.localPlayer().AncestryChanged:Connect(function(_, parent: Instance?)
			if parent ~= nil then
				return
			end
			-- Leaving: drop everything this script created.
			for _, connection in connections do
				connection:Disconnect()
			end
			ContextActionService:UnbindAction(CLOSE_ACTION)
			panel:destroy()
			hud:destroy()
		end)
	)

	print(`[Tycoon Capitalist] client ready, tier {Device.tier()}`)
end

main()

return nil
