--!strict
--[[
	The panel. This is the game.

	The player walks to a board, clicks it, and this opens over the world: the AdVenture
	Capitalist screen, with a row per business. The 3D plot is the shell around it -- which is
	why the economy has exactly one interaction surface instead of mechanics scattered across
	ten buildings.

	Division of labour with the server:

	* Every number shown here arrives in a snapshot. The client prices nothing and credits
	  nothing.
	* Progress bars are interpolated locally between snapshots. A bar is cosmetic -- the payout
	  is decided by the server's clock -- so interpolating it costs nothing and means a snapshot
	  every few hundred milliseconds still looks smooth on a phone.

	Layout is scale-based rather than pixel-based, so a phone and a desktop get the same panel
	at different sizes. Styling is Phase 4; every colour and metric comes from Theme so that
	pass is one diff.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNumber = require(Shared.Economy.BigNumber)
local Businesses = require(Shared.Config.Businesses)
local Format = require(Shared.Economy.Format)
local Remotes = require(Shared.Net.Remotes)
local Types = require(Shared.Types)

local Device = require(script.Parent.Parent.Device)
local Theme = require(script.Parent.Theme)

local Panel = {}
Panel.__index = Panel

local BUY_MODES: { Types.BuyMode } = { "x1", "x10", "x100", "max" }

type Row = {
	container: Frame,
	title: TextLabel,
	units: TextLabel,
	payout: TextLabel,
	milestone: TextLabel,
	progressFill: Frame,
	buyButton: TextButton,
	buyLabel: TextLabel,
	buyPrice: TextLabel,
	-- Interpolation state, refreshed on every snapshot.
	cycleSeconds: number,
	cycleElapsed: number,
	receivedAt: number,
	isCycling: boolean,
}

export type Panel = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		backdrop: Frame,
		surface: Frame,
		cashLabel: TextLabel,
		perSecondLabel: TextLabel,
		angelLabel: TextLabel,
		rowHolder: ScrollingFrame,
		modeButtons: { [Types.BuyMode]: TextButton },
		rows: { [Types.BusinessId]: Row },
		buyMode: Types.BuyMode,
		isOpen: boolean,
		connections: { RBXScriptConnection },
	},
	Panel
))

local function corner(parent: Instance, radius: number): ()
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
end

local function label(name: string, parent: Instance, font: Enum.Font, size: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Font = font
	text.TextSize = size
	text.TextColor3 = Theme.colour.text
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Text = ""
	text.Parent = parent
	return text
end

--[[ Header: the two numbers that matter, plus a way out. ]]
local function buildHeader(self: Panel, parent: Frame): ()
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = Theme.colour.panelSurface
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, 76)
	header.Parent = parent
	corner(header, Theme.metric.corner)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, Theme.metric.panelPadding)
	padding.PaddingRight = UDim.new(0, Theme.metric.panelPadding)
	padding.Parent = header

	self.cashLabel = label("Cash", header, Theme.font.number, 34)
	self.cashLabel.Size = UDim2.new(1, -120, 0, 42)
	self.cashLabel.Position = UDim2.fromOffset(0, 6)
	self.cashLabel.TextColor3 = Theme.colour.accent

	self.perSecondLabel = label("Lifetime", header, Theme.font.body, 16)
	self.perSecondLabel.Size = UDim2.new(1, -120, 0, 20)
	self.perSecondLabel.Position = UDim2.fromOffset(0, 48)
	self.perSecondLabel.TextColor3 = Theme.colour.textDim

	self.angelLabel = label("Angels", header, Theme.font.body, 16)
	self.angelLabel.Size = UDim2.fromOffset(110, 20)
	self.angelLabel.Position = UDim2.new(1, -110, 0, 48)
	self.angelLabel.TextXAlignment = Enum.TextXAlignment.Right
	self.angelLabel.TextColor3 = Theme.colour.textDim

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(44, 44)
	close.Position = UDim2.new(1, -44, 0, 6)
	close.BackgroundColor3 = Theme.colour.rowSurface
	close.BorderSizePixel = 0
	close.Font = Theme.font.display
	close.TextSize = 24
	close.TextColor3 = Theme.colour.text
	close.Text = "X"
	close.Parent = header
	corner(close, Theme.metric.rowCorner)

	table.insert(
		self.connections,
		close.Activated:Connect(function()
			self:close()
		end)
	)
end

--[[ The x1 / x10 / x100 / max selector. One of the source game's best quality-of-life touches. ]]
local function buildModeBar(self: Panel, parent: Frame): ()
	local bar = Instance.new("Frame")
	bar.Name = "BuyModes"
	bar.BackgroundTransparency = 1
	bar.Size = UDim2.new(1, 0, 0, 40)
	bar.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, Theme.metric.rowGap)
	layout.Parent = bar

	for _, mode: Types.BuyMode in BUY_MODES do
		local button = Instance.new("TextButton")
		button.Name = mode
		button.Size = UDim2.new(0.25, -Theme.metric.rowGap, 1, 0)
		button.BackgroundColor3 = Theme.colour.rowSurface
		button.BorderSizePixel = 0
		button.Font = Theme.font.display
		button.TextSize = 18
		button.TextColor3 = Theme.colour.text
		button.Text = if mode == "max" then "MAX" else mode:upper()
		button.Parent = bar
		corner(button, Theme.metric.rowCorner)

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

	The whole row is the collect button, as in the source game: clicking the business starts its
	cycle. The buy button is a separate control on the right so the two actions never fight for
	the same tap, which matters a lot more on a phone than on a desktop.
]]
local function buildRow(self: Panel, id: Types.BusinessId): Row
	local config = Businesses.byId[id]

	local container = Instance.new("Frame")
	container.Name = id
	container.BackgroundColor3 = Theme.colour.rowSurface
	container.BorderSizePixel = 0
	container.Size = UDim2.new(1, 0, 0, Theme.metric.rowHeight)
	container.LayoutOrder = config.order
	container.Parent = self.rowHolder
	corner(container, Theme.metric.rowCorner)

	local collect = Instance.new("TextButton")
	collect.Name = "Collect"
	collect.BackgroundTransparency = 1
	collect.Size = UDim2.new(1, -150, 1, 0)
	collect.Text = ""
	collect.Parent = container

	local title = label("Title", collect, Theme.font.display, 22)
	title.Size = UDim2.new(1, -16, 0, 26)
	title.Position = UDim2.fromOffset(12, 8)
	title.Text = config.displayName

	local units = label("Units", collect, Theme.font.number, 18)
	units.Size = UDim2.fromOffset(70, 22)
	units.Position = UDim2.fromOffset(12, 34)
	units.TextColor3 = Theme.colour.accent

	local payout = label("Payout", collect, Theme.font.body, 15)
	payout.Size = UDim2.new(1, -90, 0, 20)
	payout.Position = UDim2.fromOffset(86, 36)
	payout.TextColor3 = Theme.colour.textDim

	local milestone = label("Milestone", collect, Theme.font.body, 13)
	milestone.Size = UDim2.new(1, -24, 0, 16)
	milestone.Position = UDim2.new(0, 12, 1, -24)
	milestone.TextColor3 = Theme.colour.textDim

	local track = Instance.new("Frame")
	track.Name = "ProgressTrack"
	track.BackgroundColor3 = Theme.colour.progressTrack
	track.BorderSizePixel = 0
	track.Size = UDim2.new(1, -24, 0, 6)
	track.Position = UDim2.new(0, 12, 1, -8)
	track.AnchorPoint = Vector2.new(0, 1)
	track.Parent = collect
	corner(track, 3)

	local fill = Instance.new("Frame")
	fill.Name = "ProgressFill"
	fill.BackgroundColor3 = Theme.colour.progressFill
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	corner(fill, 3)

	local buyButton = Instance.new("TextButton")
	buyButton.Name = "Buy"
	buyButton.Size = UDim2.new(0, 134, 1, -16)
	buyButton.Position = UDim2.new(1, -142, 0, 8)
	buyButton.BackgroundColor3 = Theme.colour.accentDark
	buyButton.BorderSizePixel = 0
	buyButton.Text = ""
	buyButton.Parent = container
	corner(buyButton, Theme.metric.rowCorner)

	local buyLabel = label("BuyMode", buyButton, Theme.font.display, 18)
	buyLabel.Size = UDim2.new(1, 0, 0, 22)
	buyLabel.Position = UDim2.fromOffset(0, 10)
	buyLabel.TextXAlignment = Enum.TextXAlignment.Center

	local buyPrice = label("BuyPrice", buyButton, Theme.font.number, 17)
	buyPrice.Size = UDim2.new(1, 0, 0, 24)
	buyPrice.Position = UDim2.fromOffset(0, 32)
	buyPrice.TextXAlignment = Enum.TextXAlignment.Center

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
		title = title,
		units = units,
		payout = payout,
		milestone = milestone,
		progressFill = fill,
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
	backdrop.BackgroundColor3 = Theme.colour.panelBackdrop
	backdrop.BackgroundTransparency = Theme.transparency.backdrop
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = gui

	local surface = Instance.new("Frame")
	surface.Name = "Surface"
	surface.AnchorPoint = Vector2.new(0.5, 0.5)
	surface.Position = UDim2.fromScale(0.5, 0.5)
	surface.Size = UDim2.fromScale(Theme.metric.panelWidthScale, Theme.metric.panelHeightScale)
	surface.BackgroundColor3 = Theme.colour.panelBackdrop
	surface.BorderSizePixel = 0
	surface.Parent = backdrop
	corner(surface, Theme.metric.corner)

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
		backdrop = backdrop,
		surface = surface,
		cashLabel = nil :: any,
		perSecondLabel = nil :: any,
		angelLabel = nil :: any,
		rowHolder = nil :: any,
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
	holder.Size = UDim2.new(1, 0, 1, -130)
	holder.CanvasSize = UDim2.new()
	holder.AutomaticCanvasSize = Enum.AutomaticSize.Y
	holder.ScrollBarThickness = 4
	holder.ScrollBarImageColor3 = Theme.colour.textDim
	holder.LayoutOrder = 3
	holder.Parent = surface
	self.rowHolder = holder

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.Padding = UDim.new(0, Theme.metric.rowGap)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = holder

	self:setBuyMode("x1")
	return self
end

function Panel.setBuyMode(self: Panel, mode: Types.BuyMode): ()
	self.buyMode = mode

	for candidate, button in self.modeButtons do
		local selected = candidate == mode
		button.BackgroundColor3 = if selected then Theme.colour.accent else Theme.colour.rowSurface
		button.TextColor3 = if selected then Theme.colour.panelBackdrop else Theme.colour.text
	end

	-- The server prices the selected mode, so ask it to re-send rather than pricing locally.
	Remotes.get(Remotes.toServer.SetPanelOpen):FireServer(self.isOpen)
end

--[[ Apply a server snapshot. The only place panel numbers are set. ]]
function Panel.setSnapshot(self: Panel, snapshot: Types.PlotSnapshot): ()
	self.cashLabel.Text = Format.money(snapshot.cash)
	self.perSecondLabel.Text = `lifetime {Format.money(snapshot.lifetimeEarnings)}`
	self.angelLabel.Text = `{Format.integer(snapshot.angels)} angels`

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

		row.units.Text = Format.integer(business.unitsOwned)
		row.payout.Text =
			`{Format.money(business.payoutPerCycle)} / {Format.duration(business.cycleSeconds)}`

		local milestone = business.nextMilestone
		row.milestone.Text = if milestone
			then `next speed-up at {Format.integer(milestone)}`
			else "fully upgraded"

		local count = business.affordableAtMode
		row.buyLabel.Text = if snapshot.buyMode == "max"
			then `BUY {Format.integer(math.max(count, 1))}`
			else `BUY {snapshot.buyMode:upper()}`
		row.buyPrice.Text = Format.money(business.nextCostFor)

		local affordable = count > 0 and not BigNumber.lt(snapshot.cash, business.nextCostFor)
		row.buyButton.BackgroundColor3 = if affordable
			then Theme.colour.accentDark
			else Theme.colour.rowSurface
		row.buyPrice.TextColor3 = if affordable then Theme.colour.text else Theme.colour.textDim

		row.container.BackgroundColor3 = if business.isCycling
			then Theme.colour.rowSurfaceReady
			else Theme.colour.rowSurface
	end

	if self.buyMode ~= snapshot.buyMode then
		self.buyMode = snapshot.buyMode
		for candidate, button in self.modeButtons do
			local selected = candidate == snapshot.buyMode
			button.BackgroundColor3 = if selected
				then Theme.colour.accent
				else Theme.colour.rowSurface
			button.TextColor3 = if selected then Theme.colour.panelBackdrop else Theme.colour.text
		end
	end
end

--[[
	Advance the progress bars between snapshots.

	Cosmetic only: the server decides when a cycle pays. Interpolating here is what lets the
	server push a snapshot ten times a second instead of every frame.
]]
function Panel.step(self: Panel, now: number): ()
	for _, row in self.rows do
		if not row.isCycling or row.cycleSeconds <= 0 then
			row.progressFill.Size = UDim2.fromScale(0, 1)
			continue
		end

		local elapsed = row.cycleElapsed + (now - row.receivedAt)
		local fraction = math.clamp(elapsed / row.cycleSeconds, 0, 1)
		row.progressFill.Size = UDim2.fromScale(fraction, 1)
	end
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

--[[ Every connection made here is disconnected here. CLAUDE.md's rule, and the leak otherwise. ]]
function Panel.destroy(self: Panel): ()
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.rows)
	table.clear(self.modeButtons)
	self.gui:Destroy()
end

return Panel
