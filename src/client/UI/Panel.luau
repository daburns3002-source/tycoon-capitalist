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
local AngelMath = require(Shared.Economy.Angels)
local BigNumber = require(Shared.Economy.BigNumber)
local Businesses = require(Shared.Config.Businesses)
local Format = require(Shared.Economy.Format)
local Remotes = require(Shared.Net.Remotes)
local Types = require(Shared.Types)
local Upgrades = require(Shared.Config.Upgrades)

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
	title: TextLabel,
	milestone: TextLabel,
	progressTrack: Frame,
	progressFill: Frame,
	tapHint: TextLabel,
	countBadge: TextLabel,
	timer: TextLabel,
	chip: Frame,
	fillTween: Tween?,
	cycleToken: number,
	buyButton: TextButton,
	buyLabel: TextLabel,
	buyPrice: TextLabel,
	managerButton: TextButton,
	managerLabel: TextLabel,
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
		upgradeHolder: ScrollingFrame,
		angelView: Frame,
		angelHeadline: TextLabel,
		angelBonus: TextLabel,
		angelPending: TextLabel,
		angelNext: TextLabel,
		resetButton: TextButton,
		resetLabel: TextLabel,
		resetArmed: boolean,
		upgradeRows: { [string]: { button: TextButton, price: TextLabel, container: Frame } },
		tabButtons: { [string]: TextButton },
		activeTab: string,
		overlay: Frame,
		modeButtons: { [Types.BuyMode]: TextButton },
		rows: { [Types.BusinessId]: Row },
		buyMode: Types.BuyMode,
		isOpen: boolean,
		lastRowPopAt: number,
		lastCashPopAt: number,
		pendingCashGain: Types.BigNumber,
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

--[[
	The tab bar: businesses, or upgrades.

	The source game puts upgrades behind a side-menu button that opens a separate modal. One
	panel with two tabs keeps the promise that the board is the single surface for the economy,
	and on a phone a second full-screen modal on top of a full-screen modal is a bad place to be.
]]
local function buildTabs(self: Panel, parent: Frame): ()
	local bar = Instance.new("Frame")
	bar.Name = "Tabs"
	bar.BackgroundTransparency = 1
	bar.Size = UDim2.new(1, 0, 0, 44)
	bar.LayoutOrder = 2
	bar.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, Theme.metric.rowGap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar

	local names = { businesses = "BUSINESSES", upgrades = "UPGRADES", angels = "ANGELS" }
	local order = { "businesses", "upgrades", "angels" }

	for index, key in order do
		local button = Bubbly.button(key, bar, {
			fill = Theme.colour.panelDeep,
			outline = Theme.colour.text,
			text = names[key],
			textSize = 18,
		})
		button.Size = UDim2.new(1 / 3, -Theme.metric.rowGap, 1, 0)
		button.LayoutOrder = index
		self.tabButtons[key] = button

		table.insert(
			self.connections,
			button.Activated:Connect(function()
				self:setTab(key)
			end)
		)
	end
end

--[[
	One upgrade row: what it does, what it costs, and a button.

	The description is generated from the config rather than written out per upgrade, because
	every one of the 478 in the source game says the same thing -- "<business> Profit x3" -- and
	a hand-written string per row would be 478 chances to get one wrong.
]]
local function buildUpgradeRow(self: Panel, config: Types.UpgradeConfig): ()
	local container = Bubbly.panel(config.id, self.upgradeHolder, Theme.colour.row)
	container.Size = UDim2.new(1, -8, 0, 76)
	container.LayoutOrder = #self.upgradeHolder:GetChildren()

	local title = Bubbly.label("Title", container, {
		text = config.displayName,
		size = 20,
	})
	title.Size = UDim2.new(1, -180, 0, 24)
	title.Position = UDim2.fromOffset(16, 10)

	local effect = if config.kind == "angelEffectiveness"
		then `Angel effectiveness +{math.floor(config.multiplier * 100)}%`
		elseif config.target == "all" then `All businesses profit x{config.multiplier}`
		else `{Businesses.byId[config.target].displayName} profit x{config.multiplier}`

	local description = Bubbly.label("Effect", container, {
		text = effect,
		size = 15,
		colour = Theme.colour.textDim,
		strokeThickness = Theme.metric.textStrokeSmall,
	})
	description.Size = UDim2.new(1, -180, 0, 20)
	description.Position = UDim2.fromOffset(16, 38)

	local button, label = Bubbly.button("Buy", container, {
		fill = Theme.colour.green,
		outline = Theme.colour.text,
		corner = Theme.metric.chipCorner,
		textSize = 15,
	})
	button.Size = UDim2.fromOffset(150, 52)
	button.Position = UDim2.new(1, -162, 0, 12)
	label.Size = UDim2.new(1, 0, 0, 20)
	label.Position = UDim2.fromOffset(0, 6)

	local price = Bubbly.label("Price", button, {
		size = 17,
		alignment = Enum.TextXAlignment.Center,
		gradient = Theme.gradient.money,
	})
	price.Size = UDim2.new(1, 0, 0, 24)
	price.Position = UDim2.fromOffset(0, 26)

	self.upgradeRows[config.id] = { button = button, price = price, container = container }

	table.insert(
		self.connections,
		button.Activated:Connect(function()
			Remotes.get(Remotes.toServer.BuyUpgrade):FireServer(config.id)
		end)
	)
end

--[[
	The Angels view: what you have, what a reset would pay, and the button that does it.

	Deliberately wordy where the rest of the UI is terse. A reset destroys everything the player
	has built this run, and the only thing that makes it a good idea rather than a catastrophe is
	understanding that angels are permanent and the next run is faster. A number with no
	explanation would just look like a punishment.
]]
local function buildAngelView(self: Panel, parent: Frame): ()
	local view = Bubbly.panel("AngelView", parent, Theme.colour.panelDeep)
	view.Size = UDim2.new(1, 0, 1, -212)
	view.LayoutOrder = 4
	view.Visible = false
	self.angelView = view

	local chip = Bubbly.iconChip(view, "😇", Theme.colour.money)
	chip.Position = UDim2.fromOffset(20, 20)

	self.angelHeadline = Bubbly.label("Headline", view, {
		text = "0 Angel Investors",
		size = 30,
		gradient = Theme.gradient.money,
	})
	self.angelHeadline.Size = UDim2.new(1, -110, 0, 38)
	self.angelHeadline.Position = UDim2.fromOffset(90, 18)

	self.angelBonus = Bubbly.label("Bonus", view, {
		size = 17,
		colour = Theme.colour.textDim,
		strokeThickness = Theme.metric.textStrokeSmall,
	})
	self.angelBonus.Size = UDim2.new(1, -110, 0, 22)
	self.angelBonus.Position = UDim2.fromOffset(90, 56)

	self.angelPending = Bubbly.label("Pending", view, {
		size = 24,
		alignment = Enum.TextXAlignment.Center,
		gradient = Theme.gradient.green,
	})
	self.angelPending.Size = UDim2.new(1, -40, 0, 32)
	self.angelPending.Position = UDim2.fromOffset(20, 108)

	self.angelNext = Bubbly.label("NextAngel", view, {
		size = 16,
		alignment = Enum.TextXAlignment.Center,
		colour = Theme.colour.textDim,
		strokeThickness = Theme.metric.textStrokeSmall,
	})
	self.angelNext.Size = UDim2.new(1, -40, 0, 22)
	self.angelNext.Position = UDim2.fromOffset(20, 144)

	local explain = Bubbly.label("Explain", view, {
		text = "Resetting clears your cash, businesses, managers and upgrades. "
			.. "Angels are kept forever and make every future run faster.",
		size = 15,
		alignment = Enum.TextXAlignment.Center,
		colour = Theme.colour.textDim,
		strokeThickness = Theme.metric.textStrokeSmall,
	})
	explain.Size = UDim2.new(1, -40, 0, 48)
	explain.Position = UDim2.fromOffset(20, 182)
	explain.TextWrapped = true

	local button, label = Bubbly.button("Reset", view, {
		fill = Theme.colour.red,
		outline = Theme.colour.text,
		text = "RESET FOR ANGELS",
		textSize = 20,
	})
	button.Size = UDim2.new(1, -80, 0, 62)
	button.Position = UDim2.fromOffset(40, 244)
	self.resetButton = button
	self.resetLabel = label

	--[[
		Two taps, not one.

		The first arms it and changes the wording; the second commits. An irreversible action
		one tap away from a scrolling list is a mis-tap waiting to wipe somebody's run, and this
		costs nothing. The server refuses a reset worth no angels regardless -- the confirmation
		is for the case where it *is* worth something and the player still did not mean it.
	]]
	table.insert(
		self.connections,
		button.Activated:Connect(function()
			if not self.resetArmed then
				self.resetArmed = true
				self.resetLabel.Text = "TAP AGAIN TO CONFIRM"
				button.BackgroundColor3 = Theme.colour.redDeep
				return
			end

			self.resetArmed = false
			Remotes.get(Remotes.toServer.PerformReset):FireServer()
		end)
	)
end

--[[ The x1 / x10 / x100 / MAX selector. ]]
local function buildModeBar(self: Panel, parent: Frame): ()
	local bar = Instance.new("Frame")
	bar.Name = "BuyModes"
	bar.BackgroundTransparency = 1
	bar.Size = UDim2.new(1, 0, 0, 52)
	bar.LayoutOrder = 3
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

	--[[
		The owned count, as a badge on the icon.

		Straight from the source game, where every business icon carries its count in the corner
		rather than in the body text. It is the number a player checks most often -- it is what
		the next cycle-time milestone is measured against -- so it belongs on the thing their
		eye already goes to.
	]]
	local countBadge = Bubbly.label("Count", chip, {
		size = 15,
		alignment = Enum.TextXAlignment.Center,
		strokeThickness = Theme.metric.textStrokeSmall,
	})
	countBadge.Size = UDim2.fromOffset(Theme.metric.iconChip, 18)
	countBadge.Position = UDim2.fromOffset(0, Theme.metric.iconChip - 17)
	countBadge.ZIndex = 8

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

	--[[
		Time left on the cycle, right-aligned, as the source game shows it.

		Refreshed from snapshots rather than per frame. That is one a second while idle, which
		is exact for the Oil Company's ten hours and meaningless for the Lemonade Stand's
		0.6s -- and at 0.6s the bar is the readout anyway.
	]]
	local timer = Bubbly.label("Timer", collect, {
		size = 16,
		colour = Theme.colour.textDim,
		alignment = Enum.TextXAlignment.Right,
		strokeThickness = Theme.metric.textStrokeSmall,
	})
	timer.Size = UDim2.fromOffset(96, 22)
	timer.Position = UDim2.new(1, -104, 0, 12)

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
	buyButton.Size = UDim2.fromOffset(150, 64)
	buyButton.Position = UDim2.new(1, -162, 0, 10)
	buyButton.ZIndex = 3
	buyLabel.Size = UDim2.new(1, 0, 0, 22)
	buyLabel.Position = UDim2.fromOffset(0, 8)

	local buyPrice = Bubbly.label("BuyPrice", buyButton, {
		size = 19,
		alignment = Enum.TextXAlignment.Center,
		gradient = Theme.gradient.money,
	})
	buyPrice.Size = UDim2.new(1, 0, 0, 26)
	buyPrice.Position = UDim2.fromOffset(0, 30)

	--[[
		The manager button, under BUY.

		Deliberately its own control rather than a tab elsewhere. Hiring a manager is the single
		most important decision on a business -- it is what makes the game idle at all -- and the
		source game puts it behind a side menu where a new player can miss that entirely. Here it
		sits next to the thing it automates.
	]]
	local managerButton, managerLabel = Bubbly.button("Manager", container, {
		fill = Theme.colour.blue,
		outline = Theme.colour.text,
		corner = Theme.metric.chipCorner,
		textSize = 15,
	})
	managerButton.Size = UDim2.fromOffset(150, 32)
	managerButton.Position = UDim2.new(1, -162, 0, 78)
	managerButton.ZIndex = 3
	managerLabel.Size = UDim2.fromScale(1, 1)

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
	table.insert(
		self.connections,
		managerButton.Activated:Connect(function()
			Remotes.get(Remotes.toServer.HireManager):FireServer(id)
		end)
	)

	return {
		container = container,
		title = title,
		units = units,
		payout = payout,
		milestone = milestone,
		progressTrack = track,
		progressFill = fill,
		tapHint = tapHint,
		countBadge = countBadge,
		timer = timer,
		chip = chip,
		fillTween = nil,
		cycleToken = 0,
		buyButton = buyButton,
		buyLabel = buyLabel,
		buyPrice = buyPrice,
		managerButton = managerButton,
		managerLabel = managerLabel,
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
		upgradeHolder = nil :: any,
		angelView = nil :: any,
		angelHeadline = nil :: any,
		angelBonus = nil :: any,
		angelPending = nil :: any,
		angelNext = nil :: any,
		resetButton = nil :: any,
		resetLabel = nil :: any,
		resetArmed = false,
		upgradeRows = {},
		tabButtons = {},
		activeTab = "businesses",
		overlay = nil :: any,
		modeButtons = {},
		rows = {},
		buyMode = "x1" :: Types.BuyMode,
		isOpen = false,
		lastRowPopAt = 0,
		lastCashPopAt = 0,
		pendingCashGain = BigNumber.zero,
		connections = {},
	}, Panel)

	buildHeader(self, surface)
	buildTabs(self, surface)
	buildModeBar(self, surface)

	local holder = Instance.new("ScrollingFrame")
	holder.Name = "Businesses"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.new(1, 0, 1, -212)
	holder.CanvasSize = UDim2.new()
	holder.AutomaticCanvasSize = Enum.AutomaticSize.Y
	holder.ScrollBarThickness = 6
	holder.ScrollBarImageColor3 = Theme.colour.textDim
	holder.LayoutOrder = 4
	holder.Parent = surface
	self.rowHolder = holder

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.Padding = UDim.new(0, Theme.metric.rowGap)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = holder

	--[[
		The upgrades scroller shares the same slot as the businesses one.

		Both sit at LayoutOrder 4 and only one is ever visible, so the UIListLayout gives
		whichever is showing the same space without the panel resizing as the tab changes.
	]]
	local upgradeHolder = Instance.new("ScrollingFrame")
	upgradeHolder.Name = "UpgradeList"
	upgradeHolder.BackgroundTransparency = 1
	upgradeHolder.BorderSizePixel = 0
	upgradeHolder.Size = UDim2.new(1, 0, 1, -212)
	upgradeHolder.CanvasSize = UDim2.new()
	upgradeHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
	upgradeHolder.ScrollBarThickness = 6
	upgradeHolder.ScrollBarImageColor3 = Theme.colour.textDim
	upgradeHolder.LayoutOrder = 4
	upgradeHolder.Visible = false
	upgradeHolder.Parent = surface
	self.upgradeHolder = upgradeHolder

	local upgradeLayout = Instance.new("UIListLayout")
	upgradeLayout.Padding = UDim.new(0, Theme.metric.rowGap)
	upgradeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	upgradeLayout.Parent = upgradeHolder

	for _, config in Upgrades.list do
		buildUpgradeRow(self, config)
	end

	buildAngelView(self, surface)

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
	self:setTab("businesses")
	return self
end

--[[
	Switch between the businesses list and the upgrades list.

	The buy-mode selector only means anything for businesses, so it hides on the upgrades tab
	rather than sitting there inert.
]]
function Panel.setTab(self: Panel, tab: string): ()
	self.activeTab = tab

	for key, button in self.tabButtons do
		local selected = key == tab
		button.BackgroundColor3 = if selected then Theme.colour.money else Theme.colour.panelDeep
	end

	self.rowHolder.Visible = tab == "businesses"
	self.upgradeHolder.Visible = tab == "upgrades"
	self.angelView.Visible = tab == "angels"

	-- Leaving the tab disarms the reset, so a confirmation cannot be left primed behind a tab
	-- and tripped much later by someone who has forgotten it is armed.
	if tab ~= "angels" and self.resetArmed then
		self.resetArmed = false
		self.resetLabel.Text = "RESET FOR ANGELS"
		self.resetButton.BackgroundColor3 = Theme.colour.red
	end

	local modeBar = self.surface:FindFirstChild("BuyModes")
	if modeBar and modeBar:IsA("GuiObject") then
		modeBar.Visible = tab == "businesses"
	end
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
	if business.unitsOwned <= 0 or not business.isCycling or business.cycleSeconds <= 0 then
		if row.fillTween then
			row.fillTween:Cancel()
			row.fillTween = nil
		end
		row.cycleToken = 0
		row.progressFill.Size = UDim2.fromScale(0, 1)
		-- A managed business is never waiting for a tap, so never prompt for one.
		row.tapHint.Visible = business.unitsOwned > 0 and not business.hasManager
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

		--[[
			A business with no units is "locked": listed with its price, greyed, inert.

			The source game does the same -- every business is visible from the first minute
			with its cost on the button, which is most of why the early game pulls. It is not a
			separate state on the server; zero units already earns nothing and runs no cycle.
		]]
		local owned = business.unitsOwned > 0

		row.countBadge.Text = if owned then Format.integer(business.unitsOwned) else ""
		row.units.Text = if owned then `x{Format.integer(business.unitsOwned)}` else "LOCKED"
		row.units.TextTransparency = if owned then 0 else 0.25

		-- A locked row quotes what *one* unit earns, read from the shared config. The snapshot's
		-- payout is computed from units owned, which is zero here, so using it would advertise
		-- every business as earning nothing -- the opposite of the point of listing them.
		local config = Businesses.byId[business.id]
		row.payout.Text = if owned
			then `{Format.money(business.payoutPerCycle)} / {Format.duration(business.cycleSeconds)}`
			else `{Format.money(config.revenuePerCycle)} per {Format.duration(
				config.cycleSeconds
			)}`

		local milestone = business.nextMilestone
		row.milestone.Text = if not owned
			then "tap BUY to start earning"
			elseif milestone then `⚡ speed-up at {Format.integer(milestone)}`
			else "⚡ fully upgraded"

		-- Time left this cycle, or the cycle length when idle.
		local remaining = math.max(business.cycleSeconds - business.cycleElapsed, 0)
		row.timer.Text = if not owned
			then ""
			elseif business.isCycling then Format.duration(remaining)
			else Format.duration(business.cycleSeconds)

		--[[
			The manager control has three states: unavailable until you own one unit, a priced
			hire offer, and then the manager's name once hired. Showing the name rather than a
			tick is the source game's touch and it is the right one -- "Cabe Johnson" reads as
			someone running the stand, which is the fiction the whole mechanic rests on.
		]]
		if not owned then
			row.managerButton.Visible = false
		elseif business.hasManager then
			row.managerButton.Visible = true
			row.managerButton.BackgroundColor3 = Theme.colour.greenDeep
			row.managerLabel.Text = config.managerName
		else
			row.managerButton.Visible = true
			local affordableManager = not BigNumber.lt(snapshot.cash, config.managerCost)
			row.managerButton.BackgroundColor3 = if affordableManager
				then Theme.colour.blue
				else Theme.colour.panelDeep
			row.managerLabel.Text = `MANAGER {Format.money(config.managerCost)}`
		end

		row.chip.BackgroundTransparency = if owned then 0 else 0.55
		row.title.TextTransparency = if owned then 0 else 0.25
		row.progressTrack.Visible = owned

		local count = business.affordableAtMode
		row.buyLabel.Text = if snapshot.buyMode == "max"
			then `BUY {Format.integer(math.max(count, 1))}`
			else `BUY {snapshot.buyMode:upper()}`
		row.buyPrice.Text = Format.money(business.nextCostFor)

		local affordable = count > 0 and not BigNumber.lt(snapshot.cash, business.nextCostFor)
		row.buyButton.BackgroundColor3 = if affordable
			then Theme.colour.green
			else Theme.colour.panelDeep

		row.container.BackgroundColor3 = if not owned
			then Theme.colour.panelDeep
			elseif business.isCycling then Theme.colour.rowActive
			else Theme.colour.row
	end

	-- A rate, not a money value, so this arithmetic is plain-number work by design.
	local perAngel = AngelMath.profitPerAngel
	local bonusPercent = math.floor(perAngel * snapshot.angels * 100 + 0.5)
	self.angelHeadline.Text = `{Format.integer(snapshot.angels)} Angel Investors`
	self.angelBonus.Text = `+{Format.integer(bonusPercent)}% to all profits, permanently`

	if snapshot.pendingAngels > 0 then
		self.angelPending.Text = `Reset now for {Format.integer(snapshot.pendingAngels)} more`
		self.resetButton.BackgroundColor3 = if self.resetArmed
			then Theme.colour.redDeep
			else Theme.colour.red
	else
		self.angelPending.Text = "No angels earned yet this run"
		self.resetButton.BackgroundColor3 = Theme.colour.panelDeep
	end
	self.angelNext.Text = `next angel at {Format.money(snapshot.nextAngelAt)} lifetime earnings`

	for _, upgrade in snapshot.upgrades do
		local widget = self.upgradeRows[upgrade.id]
		if widget == nil then
			continue
		end

		local config = Upgrades.byId[upgrade.id]
		local label = widget.button:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.Text = if upgrade.owned then "OWNED" else "BUY"
		end
		widget.price.Text = if upgrade.owned then "" else Format.money(config.cost)
		widget.button.BackgroundColor3 = if upgrade.owned
			then Theme.colour.greenDeep
			elseif upgrade.affordable then Theme.colour.green
			else Theme.colour.panelDeep
		widget.container.BackgroundTransparency = if upgrade.owned then 0.35 else 0
	end

	-- The server is the authority on the selected mode, so reconcile rather than assume the
	-- local highlight was right.
	if self.buyMode ~= snapshot.buyMode then
		highlightBuyMode(self, snapshot.buyMode)
	end
end

--[[
	A tick's total earnings, popped off the cash figure.

	The per-row pop says which business paid; this one says the balance moved. Called once per
	server tick with the sum, rather than once per business, so ten businesses paying together
	in Phase 3 produce one legible number instead of ten overlapping ones.
]]
function Panel.notifyCashGain(self: Panel, amount: Types.BigNumber): ()
	if not self.isOpen then
		return
	end

	--[[
		Rate-limited, with the skipped earnings rolled into the next pop.

		A managed Lemonade Stand past the 50-unit milestone pays every 0.15 seconds, so an
		unlimited pop rate turns the top of the panel into a smear of overlapping numbers. The
		budget comes from the device tier -- 16/sec on desktop, 4 on a phone -- which is what
		`numberPopsPerSecond` was always for.

		Carrying the remainder forward matters: dropping the skipped payouts would show the
		player less than they earned, which is worse than showing it less often.
	]]
	self.pendingCashGain = BigNumber.add(self.pendingCashGain, amount)

	local now = os.clock()
	if now - self.lastCashPopAt < 1 / Device.budget().numberPopsPerSecond then
		return
	end
	self.lastCashPopAt = now

	local total = self.pendingCashGain
	self.pendingCashGain = BigNumber.zero

	--[[
		Sits flush against the end of the cash figure.

		`TextBounds` is the width of the rendered text, not of its container, so this tracks the
		number as it grows: $9 and $9.99M put the pop in different places, each time just past
		the last digit. Anchoring to the label's box instead would leave the pop stranded far to
		the right of a short number, and overlapping a long one.
	]]
	local label = self.cashLabel
	local origin = label.AbsolutePosition - self.overlay.AbsolutePosition
	Bubbly.popNumber(
		self.overlay,
		`+{Format.money(total)}`,
		UDim2.fromOffset(origin.X + label.TextBounds.X + 14, origin.Y + label.AbsoluteSize.Y / 2),
		Vector2.new(0, 0.5)
	)
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

	-- Same budget as the cash pop. The row's own bar already conveys the rate, so a skipped
	-- pop here loses nothing.
	local now = os.clock()
	if now - self.lastRowPopAt < 1 / Device.budget().numberPopsPerSecond then
		return
	end
	self.lastRowPopAt = now

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
