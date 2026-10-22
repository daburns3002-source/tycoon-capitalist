--!strict
--[[
	The always-on overlay: cash, and a nudge toward the board.

	Small on purpose. The panel is where the game happens, so the HUD's job is to keep the one
	number visible while walking and to make sure a new player finds the board without being
	told. Everything else belongs behind the board.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Economy.Format)
local Types = require(Shared.Types)

local Device = require(script.Parent.Parent.Device)
local Theme = require(script.Parent.Theme)

local Hud = {}
Hud.__index = Hud

export type Hud = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		cashLabel: TextLabel,
		hint: TextLabel,
		hintShown: boolean,
	},
	Hud
))

function Hud.new(): Hud
	local player = Device.localPlayer()

	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local plate = Instance.new("Frame")
	plate.Name = "CashPlate"
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.Position = UDim2.new(0.5, 0, 0, 12)
	plate.Size = UDim2.fromOffset(220, 52)
	plate.BackgroundColor3 = Theme.colour.panelBackdrop
	plate.BackgroundTransparency = 0.15
	plate.BorderSizePixel = 0
	plate.Parent = gui

	local plateCorner = Instance.new("UICorner")
	plateCorner.CornerRadius = UDim.new(0, Theme.metric.corner)
	plateCorner.Parent = plate

	local cashLabel = Instance.new("TextLabel")
	cashLabel.Name = "Cash"
	cashLabel.BackgroundTransparency = 1
	cashLabel.Size = UDim2.fromScale(1, 1)
	cashLabel.Font = Theme.font.number
	cashLabel.TextSize = 28
	cashLabel.TextColor3 = Theme.colour.accent
	cashLabel.Text = "$0"
	cashLabel.Parent = plate

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -24)
	hint.Size = UDim2.fromOffset(320, 28)
	hint.BackgroundTransparency = 1
	hint.Font = Theme.font.body
	hint.TextSize = 18
	hint.TextColor3 = Theme.colour.text
	hint.TextStrokeTransparency = 0.6
	hint.Text = if Device.isTouch()
		then "Tap the board to open your business"
		else "Walk to the board and press E"
	hint.Parent = gui

	return setmetatable({
		gui = gui,
		cashLabel = cashLabel,
		hint = hint,
		hintShown = true,
	}, Hud)
end

function Hud.setSnapshot(self: Hud, snapshot: Types.PlotSnapshot): ()
	self.cashLabel.Text = Format.money(snapshot.cash)
end

--[[
	Hide the hint once the player has opened the panel.

	A permanent instruction reads as clutter the moment it is no longer needed.
]]
function Hud.setHintVisible(self: Hud, visible: boolean): ()
	if self.hintShown == visible then
		return
	end
	self.hintShown = visible
	self.hint.Visible = visible
end

function Hud.setVisible(self: Hud, visible: boolean): ()
	self.gui.Enabled = visible
end

function Hud.destroy(self: Hud): ()
	self.gui:Destroy()
end

return Hud
