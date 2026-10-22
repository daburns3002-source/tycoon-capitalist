--!strict
--[[
	The always-on overlay: a cash pill, and a nudge toward the board.

	Laid out like the reference's HUD -- stat pills stacked at the bottom left with an icon chip
	and a gradient number, rather than a centred plate. That corner is where a player's eye
	already lives in this genre, and it keeps the middle of the screen clear for the world.

	Small on purpose. The panel is where the game happens; the HUD's job is to keep the one
	number visible while walking and to make sure a new player finds the board.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Economy.Format)
local Types = require(Shared.Types)

local Bubbly = require(script.Parent.Bubbly)
local Device = require(script.Parent.Parent.Device)
local Theme = require(script.Parent.Theme)

local Hud = {}
Hud.__index = Hud

export type Hud = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		overlay: Frame,
		cashValue: TextLabel,
		lifetimeValue: TextLabel,
		hint: Frame,
		hintShown: boolean,
	},
	Hud
))

function Hud.new(): Hud
	local player = Device.localPlayer()

	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Instance.new gives a ScreenGui `Global` ZIndex behaviour, where a child can render behind
	-- its own parent. Sibling is what every layout here assumes.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.BackgroundTransparency = 1
	stats.AnchorPoint = Vector2.new(0, 1)
	stats.Position = UDim2.new(0, 18, 1, -18)
	stats.Size = UDim2.fromOffset(260, 120)
	stats.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = stats

	local _, cashValue =
		Bubbly.statPill("Cash", stats, "💰", Theme.colour.money, Theme.gradient.money)
	cashValue.Text = "$0"

	local lifetimePill, lifetimeValue =
		Bubbly.statPill("Lifetime", stats, "📈", Theme.colour.blue, Theme.gradient.count)
	lifetimePill.LayoutOrder = 2
	lifetimeValue.TextSize = 24
	lifetimeValue.Text = "$0"

	--[[
		Pops go here, never into `stats`.

		`stats` has a UIListLayout, and a UIListLayout counts every GuiObject child as an item --
		so a rising "+$1" parented there would shove the cash and lifetime pills around for the
		half-second it exists. Exactly the bug that was just fixed in the panel; the overlay is
		how it stays fixed.
	]]
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 50
	overlay.Parent = gui

	-- The hint is a sticker rather than bare text, so it reads as part of the same UI.
	local hint = Bubbly.panel("Hint", gui, Theme.colour.panelDeep)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -24)
	hint.Size = UDim2.fromOffset(380, 52)

	local hintLabel = Bubbly.label("Text", hint, {
		text = if Device.isTouch()
			then "Tap the board to open your business"
			else "Walk to the board and press E",
		size = 20,
		alignment = Enum.TextXAlignment.Center,
	})
	hintLabel.Size = UDim2.fromScale(1, 1)

	return setmetatable({
		gui = gui,
		overlay = overlay,
		cashValue = cashValue,
		lifetimeValue = lifetimeValue,
		hint = hint,
		hintShown = true,
	}, Hud)
end

function Hud.setSnapshot(self: Hud, snapshot: Types.PlotSnapshot): ()
	self.cashValue.Text = Format.money(snapshot.cash)
	self.lifetimeValue.Text = Format.money(snapshot.lifetimeEarnings)
end

--[[
	Pop a rising "+$" off the cash pill.

	Matters most from Phase 3, when managers earn while the player is walking around with the
	panel closed and this is the only thing telling them it is working.
]]
function Hud.popGain(self: Hud, amount: Types.BigNumber): ()
	if not self.gui.Enabled then
		return
	end

	-- Near the start of the figure, for the same reason as the panel's: the pill's value label
	-- is left-aligned and much wider than its text.
	local origin = self.cashValue.AbsolutePosition - self.overlay.AbsolutePosition
	Bubbly.popNumber(
		self.overlay,
		`+{Format.money(amount)}`,
		UDim2.fromOffset(origin.X + 40, origin.Y)
	)
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
