--!strict
--[[
	The panel. This is the game.

	The player walks to a board, clicks it, and this opens over the world: the AdVenture
	Capitalist screen, a row per business. The 3D plot is the shell around it, which is why the
	economy has exactly one interaction surface.

	Division of labour with the server is unchanged by how this looks:

	* Every number shown here arrives in a snapshot. The client prices nothing, credits nothing.
	* Progress bars are interpolated locally between snapshots. A bar is cosmetic -- the payout
	  is decided by the server's clock -- so a snapshot every few hundred milliseconds still
	  renders smoothly on a phone.

	Styling is Steal An Egg's: stroked type, sticker buttons, icon chips, fat corners. All of it
	comes from Theme through Bubbly; this file contains no colours and no magic numbers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNumber = require(Shared.Economy.BigNumber)
local Businesses = require(Shared.Config.Businesses)
local Format = require(Shared.Economy.Format)
local Remotes = require(Shared.Net.Remotes)
local Types = require(Shared.Types)

local Bubbly = require(script.Parent.Bubbly)
local Device = require(script.Parent.Parent.Device)
local Theme = require(script.Parent.Theme)

local Panel = {}
Panel.__index = Panel

local BUY_MODES: { Types.BuyMode } = { "x1", "x10", "x100", "max" }

--[[
	A glyph per business.

	Text rather than images so Phase 7 can swap in real icons without touching a call site, and
	so nothing here depends on an uploaded asset.
]]
local GLYPHS: { [Types.BusinessId]: string } = {
	LemonadeStand = "🍋",
	NewspaperDelivery = "📰",
	CarWash = "🚗",
	PizzaDelivery = "🍕",
	DonutShop = "🍩",
	ShrimpBoat = "🦐",
	HockeyTeam = "🏒",
	MovieStudio = "🎬",
	Bank = "🏦",
	OilCompany = "🛢",
}

type Row = {
	container: Frame,
	units: TextLabel,
	payout: TextLabel,
	milestone: TextLabel,
	progressTrack: Frame,
	progressFill: Frame,
	tapHint: TextLabel,
	fillTween: Tween?,
	cycleToken: number,
	buyButton: TextButton,
	buyLabel: TextLabel,
	buyPrice: TextLabel,
	cycleSeconds: number,
	cycleElapsed: number,
	receivedAt: number,
	isCycling: boolean,
}

export type Panel = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		surface: Frame,
		cashLabel: TextLabel,
		lifetimeLabel: TextLabel,
		angelLabel: TextLabel,
		rowHolder: ScrollingFrame,
		overlay: Frame,
		modeButtons: { [Types.BuyMode]: TextButton },
		rows: { [Types.BusinessId]: Row },
		buyMode: Types.BuyMode,
		isOpen: boolean,
		connections: { RBXScriptConnection },
	},
	Panel
))

--[[ Paint the selected buy mode. UI only -- it tells the server nothing. ]]
local function highlightBuyMode(self: Panel, mode: Types.BuyMode): ()
	self.buyMode = mode

	for candidate, button in self.modeButtons do
		local selected = candidate == mode
		-- Fill carries the selection. Dark text on gold looked right in theory, but at this
		-- weight with a dark stroke around it the glyph closed up into a blob.
		button.BackgroundColor3 = if selected then Theme.colour.money else Theme.colour.panelDeep
	end
end

--[[ Header: cash in gold, lifetime and angels beneath, and a red close sticker. ]]
local function buildHeader(self: Panel, parent: Frame): ()
	local header = Bubbly.panel("Header", parent, Theme.colour.panelDeep)
	header.Size = UDim2.new(1, 0, 0, 92)
	header.LayoutOrder = 1

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Theme.metric.panelPadding)
	padding.PaddingRight = UDim.new(0, Theme.metric.panelPadding)
	padding.Parent = header

	local chip = Bubbly.iconChip(header, "💰", Theme.colour.money)
	chip.Position = UDim2.fromOffset(4, 14)

	self.cashLabel = Bubbly.label("Cash", header, {
		text = "$0",
		size = 40,
		gradient = Theme.gradient.money,
	})
	self.cashLabel.Size = UDim2.new(1, -200, 0, 48)
	self.cashLabel.Position = UDim2.fromOffset(Theme.metric.iconChip + 16, 8)

	self.lifetimeLabel = Bubbly.label("Lifetime", header, {
		size = 17,
		colour = Theme.colour.textDim,
		strokeThickness = Theme.metric.textStrokeSmall,
	})
	self.lifetimeLabel.Size = UDim2.new(1, -200, 0, 22)
	self.lifetimeLabel.Position = UDim2.fromOffset(Theme.metric.iconChip + 16, 56)

	self.angelLabel = Bubbly.label("Angels", header, {
		size = 17,
		colour = Theme.colour.textDim,
		alignment = Enum.TextXAlignment.Right,
		strokeThickness = Theme.metric.textStrokeSmall,
	})
	self.angelLabel.Size = UDim2.fromOffset(140, 26)
	self.angelLabel.Position = UDim2.new(1, -212, 0, 14)

	local close = Bubbly.button("Close", header, {
		fill = Theme.colour.red,
		outline = Theme.colour.text,
		corner = Theme.metric.chipCorner,
		text = "X",
		textSize = 26,
	})
	close.Size = UDim2.fromOffset(52, 52)
	close.Position = UDim2.new(1, -52, 0, 12)

	table.insert(
		self.connections,
		close.Activated:Connect(function()
			self:close()
		end)
	)
end

--[[ The x1 / x10 / x100 / MAX selector. ]]
local function buildModeBar(self: Panel, parent: Frame): ()
	local bar = Instance.new("Frame")
	bar.Name = "BuyModes"
	bar.BackgroundTransparency = 1
	bar.Size = UDim2.new(1, 0, 0, 52)
	bar.LayoutOrder = 2
	bar.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, Theme.metric.rowGap)
	-- Without this a UIListLayout orders by Name, which put the modes in alphabetical order:
	-- MAX, x1, x10, x100. The sequence has to read smallest to largest.
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar

	for index, mode: Types.BuyMode in BUY_MODES do
		local button = Bubbly.button(mode, bar, {
			fill = Theme.colour.panelDeep,
			outline = Theme.colour.text,
			text = if mode == "max" then "MAX" else mode:upper(),
			textSize = 22,
		})
		button.Size = UDim2.new(0.25, -Theme.metric.rowGap, 1, 0)
		button.LayoutOrder = index

		self.modeButtons[mode] = button

		table.insert(
			self.connections,
			button.Activated:Connect(function()
				self:setBuyMode(mode)
			end)
		)
	end
end

--[[
	One business row.

	The whole left side is the collect button, as in the source game: clicking the business
	starts its cycle. The buy button is a separate sticker on the right so the two actions never
	compete for the same tap, which matters far more on a phone than on a desktop.
]]
local function buildRow(self: Panel, id: Types.BusinessId): Row
	local config = Businesses.byId[id]

	local container = Bubbly.panel(id, self.rowHolder, Theme.colour.row)
	container.Size = UDim2.new(1, -8, 0, Theme.metric.rowHeight)
	container.LayoutOrder = config.order

	local collect = Instance.new("TextButton")
	collect.Name = "Collect"
	collect.BackgroundTransparency = 1
	collect.Size = UDim2.new(1, -170, 1, 0)
	collect.Text = ""
	collect.ZIndex = 3
	collect.Parent = container
	Bubbly.addPress(collect)

	local chip = Bubbly.iconChip(collect, GLYPHS[id] or "⬤", Theme.colour.blue)
	chip.Position = UDim2.fromOffset(14, 16)

	local title = Bubbly.label("Title", collect, {
		text = config.displayName,
		size = 24,
	})
	title.Size = UDim2.new(1, -90, 0, 28)
	title.Position = UDim2.fromOffset(Theme.metric.iconChip + 26, 10)

	local units = Bubbly.label("Units", collect, {
		size = 22,
		gradient = Theme.gradient.count,
	})
	units.Size = UDim2.fromOffset(80, 26)
	units.Position = UDim2.fromOffset(Theme.metric.iconChip + 26, 38)

	local payout = Bubbly.label("Payout", collect, {
		size = 18,
		colour = Theme.colour.textDim,
		strokeThickness = Theme.metric.textStrokeSmall,
	})
	payout.Size = UDim2.new(1, -260, 0, 24)
	payout.Position = UDim2.fromOffset(Theme.metric.iconChip + 118, 38)

	local milestone = Bubbly.label("Milestone", collect, {
		size = 15,
		colour = Theme.colour.textDim,
		strokeThickness = Theme.metric.textStrokeSmall,
	})
	milestone.Size = UDim2.new(1, -220, 0, 18)
	milestone.Position = UDim2.fromOffset(Theme.metric.iconChip + 26, 66)

	local track = Instance.new("Frame")
	track.Name = "ProgressTrack"
	track.BackgroundColor3 = Theme.colour.track
	track.BorderSizePixel = 0
	-- Stops short of the buy button: it belongs to the collect half of the row, and running it
	-- the full width made it look like the button was sitting on top of the bar.
	track.Size = UDim2.new(1, -184, 0, 14)
	track.Position = UDim2.new(0, 14, 1, -12)
	track.AnchorPoint = Vector2.new(0, 1)
	track.ZIndex = 3
	track.Parent = container
	Bubbly.corner(track, 6)
	Bubbly.stroke(track, Theme.colour.outline, 2)

	local fill = Instance.new("Frame")
	fill.Name = "ProgressFill"
	fill.BackgroundColor3 = Theme.colour.green
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 4
	fill.Parent = track
	Bubbly.corner(fill, 6)

	--[[
		The idle prompt.

		The bar crosses in 0.6 seconds at one Lemonade Stand and then sits empty, so a player
		who has not clicked sees a permanently empty bar and reasonably concludes it is broken.
		This says what to do instead of leaving a blank trough, and hides itself the moment a
		cycle is running.
	]]
	local tapHint = Bubbly.label("TapHint", track, {
		text = "TAP TO COLLECT",
		size = 13,
		alignment = Enum.TextXAlignment.Center,
		strokeThickness = Theme.metric.textStrokeSmall,
	})
	tapHint.Size = UDim2.fromScale(1, 1)
	tapHint.ZIndex = 5

	local buyButton, buyLabel = Bubbly.button("Buy", container, {
		fill = Theme.colour.green,
		outline = Theme.colour.text,
		textSize = 20,
	})
	buyButton.Size = UDim2.fromOffset(150, Theme.metric.rowHeight - 28)
	buyButton.Position = UDim2.new(1, -162, 0, 14)
	buyButton.ZIndex = 3
	buyLabel.Size = UDim2.new(1, 0, 0, 26)
	buyLabel.Position = UDim2.fromOffset(0, 12)

	local buyPrice = Bubbly.label("BuyPrice", buyButton, {
		size = 20,
		alignment = Enum.TextXAlignment.Center,
		gradient = Theme.gradient.money,
	})
	buyPrice.Size = UDim2.new(1, 0, 0, 28)
	buyPrice.Position = UDim2.fromOffset(0, 38)

	table.insert(
		self.connections,
		collect.Activated:Connect(function()
			Remotes.get(Remotes.toServer.StartCycle):FireServer(id)
		end)
	)
	table.insert(
		self.connections,
		buyButton.Activated:Connect(function()
			Remotes.get(Remotes.toServer.BuyUnits):FireServer(id, self.buyMode)
		end)
	)

	return {
		container = container,
		units = units,
		payout = payout,
		milestone = milestone,
		progressTrack = track,
		progressFill = fill,
		tapHint = tapHint,
		fillTween = nil,
		cycleToken = 0,
		buyButton = buyButton,
		buyLabel = buyLabel,
		buyPrice = buyPrice,
		cycleSeconds = config.cycleSeconds,
		cycleElapsed = 0,
		receivedAt = os.clock(),
		isCycling = false,
	}
end

function Panel.new(): Panel
	local player = Device.localPlayer()

	local gui = Instance.new("ScreenGui")
	gui.Name = "BusinessPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.BackgroundColor3 = Theme.colour.backdrop
	backdrop.BackgroundTransparency = Theme.transparency.backdrop
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = gui

	local surface = Bubbly.panel("Surface", backdrop, Theme.colour.panel)
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(Theme.metric.panelWidthScale, Theme.metric.panelHeightScale)

	-- Caps the panel on a wide desktop so rows do not stretch to absurd widths.
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(Theme.metric.panelMaxWidth, math.huge)
	constraint.Parent = surface

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Theme.metric.panelPadding)
	padding.PaddingBottom = UDim.new(0, Theme.metric.panelPadding)
	padding.PaddingLeft = UDim.new(0, Theme.metric.panelPadding)
	padding.PaddingRight = UDim.new(0, Theme.metric.panelPadding)
	padding.Parent = surface

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, Theme.metric.rowGap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = surface

	local self: Panel = setmetatable({
		gui = gui,
		surface = surface,
		cashLabel = nil :: any,
		lifetimeLabel = nil :: any,
		angelLabel = nil :: any,
		rowHolder = nil :: any,
		overlay = nil :: any,
		modeButtons = {},
		rows = {},
		buyMode = "x1" :: Types.BuyMode,
		isOpen = false,
		connections = {},
	}, Panel)

	buildHeader(self, surface)
	buildModeBar(self, surface)

	local holder = Instance.new("ScrollingFrame")
	holder.Name = "Businesses"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.new(1, 0, 1, -164)
	holder.CanvasSize = UDim2.new()
	holder.AutomaticCanvasSize = Enum.AutomaticSize.Y
	holder.ScrollBarThickness = 6
	holder.ScrollBarImageColor3 = Theme.colour.textDim
	holder.LayoutOrder = 3
	holder.Parent = surface
	self.rowHolder = holder

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.Padding = UDim.new(0, Theme.metric.rowGap)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = holder

	--[[
		Pops live here, not in the surface.

		The surface has a UIListLayout, and a UIListLayout treats every GuiObject child as an
		item -- so a "+$1" parented there became a row of its own and shoved the header, the
		mode bar and every business down for the half-second it existed. The overlay sits over
		the surface with no layout on it and nothing but pops inside.
	]]
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 50
	overlay.Parent = backdrop
	self.overlay = overlay

	-- Paint only. The server already starts every plot on x1, so there is nothing to tell it.
	highlightBuyMode(self, "x1")
	return self
end

--[[
	The player tapped a buy mode.

	Highlights immediately so the tap feels instant, then tells the server, which holds the
	selection because it prices the selected batch for every row. Its snapshot comes straight
	back with the new prices and confirms the highlight.
]]
function Panel.setBuyMode(self: Panel, mode: Types.BuyMode): ()
	highlightBuyMode(self, mode)
	Remotes.get(Remotes.toServer.SetBuyMode):FireServer(mode)
end

--[[
	Point the progress fill at the end of its cycle and let the engine carry it there.

	Driving the width from Luau every frame looked steppy, and no amount of frame rate fixed
	it: the track is ~536px and the first Lemonade Stand's cycle is 0.6 seconds, so the edge
	travels about 900px per second. At a perfect 60fps that is still a 15px jump per frame, and
	a fast-moving hard edge sampled that coarsely reads as chop. The world looked fine next to
	it because nothing in the world moves that fast across the screen.

	A tween hands the interpolation to the engine, which advances it on the render thread with
	whatever precision the frame rate allows, and costs no Luau at all per frame.

	Restarts only when the cycle identity changes, so the ten snapshots a second that arrive
	during normal play do not keep resetting the animation. Rejoining mid-cycle tweens from
	wherever the bar should already be, over the time that is actually left.
]]
local function syncFill(row: Row, business: Types.BusinessSnapshot): ()
	if not business.isCycling or business.cycleSeconds <= 0 then
		if row.fillTween then
			row.fillTween:Cancel()
			row.fillTween = nil
		end
		row.cycleToken = 0
		row.progressFill.Size = UDim2.fromScale(0, 1)
		row.tapHint.Visible = true
		return
	end

	row.tapHint.Visible = false

	-- Same cycle still running: leave the tween alone.
	if row.cycleToken == business.cycleToken and row.fillTween ~= nil then
		return
	end

	if row.fillTween then
		row.fillTween:Cancel()
	end
	row.cycleToken = business.cycleToken

	local progress = math.clamp(business.cycleElapsed / business.cycleSeconds, 0, 1)
	local remaining = math.max(business.cycleSeconds - business.cycleElapsed, 0.01)

	row.progressFill.Size = UDim2.fromScale(progress, 1)

	local tween = TweenService:Create(
		row.progressFill,
		TweenInfo.new(remaining, Enum.EasingStyle.Linear),
		{ Size = UDim2.fromScale(1, 1) }
	)
	row.fillTween = tween
	tween:Play()
end

--[[ Apply a server snapshot. The only place panel numbers are set. ]]
function Panel.setSnapshot(self: Panel, snapshot: Types.PlotSnapshot): ()
	self.cashLabel.Text = Format.money(snapshot.cash)
	self.lifetimeLabel.Text = `lifetime {Format.money(snapshot.lifetimeEarnings)}`
	self.angelLabel.Text = `😇 {Format.integer(snapshot.angels)}`

	local received = os.clock()

	for _, business in snapshot.businesses do
		local row = self.rows[business.id]
		if row == nil then
			row = buildRow(self, business.id)
			self.rows[business.id] = row
		end

		row.cycleSeconds = business.cycleSeconds
		row.cycleElapsed = business.cycleElapsed
		row.receivedAt = received
		row.isCycling = business.isCycling
		syncFill(row, business)

		row.units.Text = `x{Format.integer(business.unitsOwned)}`
		row.payout.Text =
			`{Format.money(business.payoutPerCycle)} / {Format.duration(business.cycleSeconds)}`

		local milestone = business.nextMilestone
		row.milestone.Text = if milestone
			then `⚡ speed-up at {Format.integer(milestone)}`
			else "⚡ fully upgraded"

		local count = business.affordableAtMode
		row.buyLabel.Text = if snapshot.buyMode == "max"
			then `BUY {Format.integer(math.max(count, 1))}`
			else `BUY {snapshot.buyMode:upper()}`
		row.buyPrice.Text = Format.money(business.nextCostFor)

		local affordable = count > 0 and not BigNumber.lt(snapshot.cash, business.nextCostFor)
		row.buyButton.BackgroundColor3 = if affordable
			then Theme.colour.green
			else Theme.colour.panelDeep

		row.container.BackgroundColor3 = if business.isCycling
			then Theme.colour.rowActive
			else Theme.colour.row
	end

	-- The server is the authority on the selected mode, so reconcile rather than assume the
	-- local highlight was right.
	if self.buyMode ~= snapshot.buyMode then
		highlightBuyMode(self, snapshot.buyMode)
	end
end

--[[
	A cycle paid out. Pops the amount above the row that earned it.

	Cosmetic and self-cleaning: the pop destroys itself when the tween finishes.
]]
function Panel.notifyPaid(self: Panel, id: Types.BusinessId, amount: Types.BigNumber): ()
	if not self.isOpen then
		return
	end
	local row = self.rows[id]
	if row == nil then
		return
	end

	-- The bar itself is too quick to read at a 0.6s cycle; the flash is what makes a completed
	-- cycle register.
	Bubbly.flash(row.progressTrack, Theme.colour.track, Theme.colour.green)

	-- Positioned against the overlay, which no layout manages, so this cannot move anything.
	local anchorY = row.container.AbsolutePosition.Y - self.overlay.AbsolutePosition.Y
	Bubbly.popNumber(
		self.overlay,
		`+{Format.money(amount)}`,
		UDim2.new(0.5, 0, 0, anchorY + row.container.AbsoluteSize.Y / 2)
	)
end

function Panel.open(self: Panel): ()
	if self.isOpen then
		return
	end
	self.isOpen = true
	self.gui.Enabled = true
	Remotes.get(Remotes.toServer.SetPanelOpen):FireServer(true)
end

function Panel.close(self: Panel): ()
	if not self.isOpen then
		return
	end
	self.isOpen = false
	self.gui.Enabled = false
	Remotes.get(Remotes.toServer.SetPanelOpen):FireServer(false)
end

function Panel.toggle(self: Panel): ()
	if self.isOpen then
		self:close()
	else
		self:open()
	end
end

--[[ Every connection made here is disconnected here. ]]
function Panel.destroy(self: Panel): ()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	for _, row in self.rows do
		if row.fillTween then
			row.fillTween:Cancel()
		end
	end
	table.clear(self.connections)
	table.clear(self.rows)
	table.clear(self.modeButtons)
	self.gui:Destroy()
end

return Panel
