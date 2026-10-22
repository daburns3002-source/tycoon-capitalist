--!strict
--[[
	The welcome-back card: what the managers earned while the player was away.

	This is the payoff for hiring managers and the single strongest reason to open the game
	tomorrow, so it gets its own screen-centred card rather than a line in the HUD. It says how
	long, how many businesses, and how much -- "your 3 businesses earned $4.2M in 7 hours" is a
	sentence; a bare number is not.

	Dismissed by tapping anywhere on it. Nothing is gated behind it; the money is already
	credited by the time this appears, so a player who never reads it loses nothing.
]]

local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Economy.Format)
local Types = require(Shared.Types)

local Bubbly = require(script.Parent.Bubbly)
local Device = require(script.Parent.Parent.Device)
local Theme = require(script.Parent.Theme)

local WelcomeBack = {}
WelcomeBack.__index = WelcomeBack

export type WelcomeBack = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		card: Frame,
		amount: TextLabel,
		detail: TextLabel,
		connections: { RBXScriptConnection },
	},
	WelcomeBack
))

--[[ "7 hours", "12 minutes" -- rounded, because precision here is noise. ]]
local function describeAbsence(seconds: number): string
	if seconds < 90 then
		return `{math.max(math.floor(seconds), 1)} seconds`
	end

	local minutes = math.floor(seconds / 60)
	if minutes < 90 then
		return `{minutes} minute{if minutes == 1 then "" else "s"}`
	end

	local hours = math.floor(seconds / 3600)
	return `{hours} hour{if hours == 1 then "" else "s"}`
end

function WelcomeBack.new(): WelcomeBack
	local player = Device.localPlayer()

	local gui = Instance.new("ScreenGui")
	gui.Name = "WelcomeBack"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.BackgroundColor3 = Theme.colour.backdrop
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = gui

	local card = Bubbly.panel("Card", backdrop, Theme.colour.panel)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(420, 260)

	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(420, 260)
	constraint.Parent = card

	local chip = Bubbly.iconChip(card, "💤", Theme.colour.blue)
	chip.AnchorPoint = Vector2.new(0.5, 0)
	chip.Position = UDim2.new(0.5, 0, 0, 20)

	local title = Bubbly.label("Title", card, {
		text = "While you were away",
		size = 24,
		alignment = Enum.TextXAlignment.Center,
	})
	title.Size = UDim2.new(1, -32, 0, 30)
	title.Position = UDim2.fromOffset(16, 86)

	local amount = Bubbly.label("Amount", card, {
		size = 40,
		alignment = Enum.TextXAlignment.Center,
		gradient = Theme.gradient.money,
	})
	amount.Size = UDim2.new(1, -32, 0, 50)
	amount.Position = UDim2.fromOffset(16, 120)

	local detail = Bubbly.label("Detail", card, {
		size = 16,
		alignment = Enum.TextXAlignment.Center,
		colour = Theme.colour.textDim,
		strokeThickness = Theme.metric.textStrokeSmall,
	})
	detail.Size = UDim2.new(1, -32, 0, 24)
	detail.Position = UDim2.fromOffset(16, 172)

	local dismiss = Bubbly.label("Dismiss", card, {
		text = "tap to continue",
		size = 14,
		alignment = Enum.TextXAlignment.Center,
		colour = Theme.colour.textDim,
		strokeThickness = Theme.metric.textStrokeSmall,
	})
	dismiss.Size = UDim2.new(1, -32, 0, 20)
	dismiss.Position = UDim2.fromOffset(16, 214)

	local self: WelcomeBack = setmetatable({
		gui = gui,
		card = card,
		amount = amount,
		detail = detail,
		connections = {},
	}, WelcomeBack)

	table.insert(
		self.connections,
		backdrop.Activated:Connect(function()
			self:hide()
		end)
	)

	return self
end

--[[ Show the card. The money is already credited; this only reports it. ]]
function WelcomeBack.show(
	self: WelcomeBack,
	seconds: number,
	earned: Types.BigNumber,
	businesses: number
): ()
	self.amount.Text = Format.money(earned)
	self.detail.Text =
		`{businesses} business{if businesses == 1 then "" else "es"} earned this in {describeAbsence(
			seconds
		)}`

	self.gui.Enabled = true

	-- A small scale-in, so it reads as arriving rather than as having always been there.
	local scale = self.card:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = self.card
	TweenService
		:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		})
		:Play()
end

function WelcomeBack.hide(self: WelcomeBack): ()
	self.gui.Enabled = false
end

function WelcomeBack.destroy(self: WelcomeBack): ()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.gui:Destroy()
end

return WelcomeBack
