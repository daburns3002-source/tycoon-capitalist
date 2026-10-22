--!strict
--[[
	Client entry point.

	Renders and predicts; never decides a number. Deleting this whole folder and rewriting it
	must not change a single value in the game -- that is what makes the server authoritative in
	practice rather than only on paper.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNumber = require(Shared.Economy.BigNumber)
local Remotes = require(Shared.Net.Remotes)
local Types = require(Shared.Types)

local BoardInteraction = require(script.Parent.World.BoardInteraction)
local Device = require(script.Parent.Device)
local Hud = require(script.Parent.UI.Hud)
local Panel = require(script.Parent.UI.Panel)
local WelcomeBack = require(script.Parent.UI.WelcomeBack)

local CLOSE_ACTION = "ClosePanel"

local function main(): ()
	local hud = Hud.new()
	local panel = Panel.new()
	local welcome = WelcomeBack.new()

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
				-- One pop per business says which one paid; the summed pop on the balance says
				-- how much the player is now up. Summed rather than popped per payment so a
				-- Phase 3 tick with ten businesses does not stack ten numbers on the total.
				local total = BigNumber.zero
				for _, payment in payments do
					panel:notifyPaid(payment.id, payment.amount)
					total = BigNumber.add(total, payment.amount)
				end

				if not BigNumber.isZero(total) then
					panel:notifyCashGain(total)
					hud:popGain(total)
				end
			end)
	)

	table.insert(
		connections,
		Remotes.get(Remotes.toClient.WelcomeBack).OnClientEvent
			:Connect(function(seconds: number, earned: Types.BigNumber, businesses: number)
				welcome:show(seconds, earned, businesses)
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
			welcome:destroy()
			panel:destroy()
			hud:destroy()
		end)
	)

	print(`[Tycoon Capitalist] client ready, tier {Device.tier()}`)
end

main()

return nil
