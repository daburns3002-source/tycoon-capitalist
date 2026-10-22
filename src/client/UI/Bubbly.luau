--!strict
--[[
	The bubbly primitives: stroked text, sticker buttons, icon chips, gradient numbers, pops.

	Everything in `Theme`'s recipe, as functions. The point is that no widget file ever builds a
	UIStroke or a UICorner by hand -- if the look needs adjusting it is adjusted here and in
	Theme, and every screen follows.

	Nothing in this module knows what the game is about. It takes text and colours and returns
	instances.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Bubbly = {}

local PRESS_IN =
	TweenInfo.new(Theme.motion.pressDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_OUT =
	TweenInfo.new(Theme.motion.releaseDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--[[
	Put a child one layer above its parent.

	Under `ZIndexBehavior.Sibling` a child always draws above its parent and this is harmless.
	Under `Global` -- which is what a plain `Instance.new("ScreenGui")` gives you -- ZIndex is
	absolute, so a label left at the default 1 inside a panel at 2 renders *behind* the panel
	and the text simply vanishes. That is a genuinely confusing bug to look at, because the
	label is present, visible and fully opaque.

	Doing it here means no caller has to know which mode its ScreenGui is in.
]]
local function layerAbove(child: GuiObject, parent: Instance): ()
	if parent:IsA("GuiObject") then
		child.ZIndex = parent.ZIndex + 1
	end
end

--[[ Rounded corners. ]]
function Bubbly.corner(parent: Instance, radius: number): UICorner
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
	return instance
end

--[[
	An outline.

	On a TextLabel this draws the black keyline around the glyphs that makes the type read as a
	sticker; on a Frame it draws the light border around the panel. Same instance, different
	effect, which is why both go through one function.
]]
function Bubbly.stroke(parent: Instance, colour: Color3, thickness: number): UIStroke
	local instance = Instance.new("UIStroke")
	instance.Color = colour
	instance.Thickness = thickness
	instance.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	instance.LineJoinMode = Enum.LineJoinMode.Round
	instance.Parent = parent
	return instance
end

--[[ A two-stop vertical gradient, light at the top. What makes the big numbers look embossed. ]]
function Bubbly.gradient(parent: Instance, stops: { Color3 }): UIGradient
	local instance = Instance.new("UIGradient")
	instance.Color = ColorSequence.new(stops[1], stops[2])
	instance.Rotation = 90
	instance.Parent = parent
	return instance
end

--[[
	A drop shadow.

	A second rounded frame behind the real one, offset down and not blurred -- the flat offset
	shadow this art style uses. Done with a sibling rather than an image so it needs no uploaded
	asset and tints with the theme.
]]
function Bubbly.shadow(target: GuiObject, parent: Instance, radius: number): Frame
	local shade = Instance.new("Frame")
	shade.Name = target.Name .. "Shadow"
	shade.BackgroundColor3 = Theme.colour.outline
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.AnchorPoint = target.AnchorPoint
	shade.Size = target.Size
	shade.Position = target.Position + UDim2.fromOffset(0, Theme.metric.shadowOffset)
	shade.ZIndex = target.ZIndex - 1
	shade.Parent = parent
	Bubbly.corner(shade, radius)
	return shade
end

export type LabelOptions = {
	text: string?,
	size: number,
	colour: Color3?,
	gradient: { Color3 }?,
	alignment: Enum.TextXAlignment?,
	strokeThickness: number?,
	font: Enum.Font?,
}

--[[
	A stroked label.

	Every piece of player-facing text goes through here. The stroke is the whole point: plain
	text on a coloured panel is what made the first pass read as a dashboard.
]]
function Bubbly.label(name: string, parent: Instance, options: LabelOptions): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Font = options.font or Theme.font.display
	text.TextSize = options.size
	text.TextColor3 = options.colour or Theme.colour.text
	text.TextXAlignment = options.alignment or Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Center
	text.Text = options.text or ""
	text.Parent = parent
	layerAbove(text, parent)

	Bubbly.stroke(text, Theme.colour.outline, options.strokeThickness or Theme.metric.textStroke)

	if options.gradient then
		Bubbly.gradient(text, options.gradient)
	end

	return text
end

--[[
	Make a button squash on press and spring back on release.

	Driven through a UIScale so it never fights whatever layout the button sits in. The spring
	back uses Back easing, which overshoots slightly -- that overshoot is most of why a tap
	feels good, and it costs one tween.
]]
function Bubbly.addPress(button: GuiButton): ()
	local scale = Instance.new("UIScale")
	scale.Parent = button

	local function down(): ()
		TweenService:Create(scale, PRESS_IN, { Scale = Theme.motion.pressScale }):Play()
	end
	local function up(): ()
		TweenService:Create(scale, PRESS_OUT, { Scale = 1 }):Play()
	end

	button.MouseButton1Down:Connect(down)
	button.MouseButton1Up:Connect(up)
	button.MouseLeave:Connect(up)
	button.TouchLongPress:Connect(up)
end

export type ButtonOptions = {
	fill: Color3,
	outline: Color3?,
	corner: number?,
	textSize: number?,
	text: string?,
	gradient: { Color3 }?,
}

--[[
	A sticker button: saturated fill, thick light outline, round corners, stroked label, pop on
	press. Returns the button and its label so a caller can retitle it without digging.
]]
function Bubbly.button(
	name: string,
	parent: Instance,
	options: ButtonOptions
): (TextButton, TextLabel)
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundColor3 = options.fill
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = parent
	layerAbove(button, parent)

	Bubbly.corner(button, options.corner or Theme.metric.corner)
	Bubbly.stroke(button, options.outline or Theme.colour.text, Theme.metric.stroke)
	Bubbly.addPress(button)

	local label = Bubbly.label("Label", button, {
		text = options.text,
		size = options.textSize or 20,
		alignment = Enum.TextXAlignment.Center,
		gradient = options.gradient,
	})
	label.Size = UDim2.fromScale(1, 1)

	return button, label
end

--[[
	The icon chip: a contrasting rounded square on the left of a button or stat, holding a
	glyph. In the reference every actionable control has one, and it is most of what stops a
	row of buttons reading as a list of links.

	Takes a text glyph rather than an image so Phase 7 can swap in real icons without changing
	any call site.
]]
function Bubbly.iconChip(parent: Instance, glyph: string, fill: Color3): Frame
	local chip = Instance.new("Frame")
	chip.Name = "IconChip"
	chip.BackgroundColor3 = fill
	chip.BorderSizePixel = 0
	chip.Size = UDim2.fromOffset(Theme.metric.iconChip, Theme.metric.iconChip)
	chip.Parent = parent
	layerAbove(chip, parent)

	Bubbly.corner(chip, Theme.metric.chipCorner)
	Bubbly.stroke(chip, Theme.colour.outline, Theme.metric.rowStroke)

	local label = Bubbly.label("Glyph", chip, {
		text = glyph,
		size = 26,
		alignment = Enum.TextXAlignment.Center,
		strokeThickness = Theme.metric.textStrokeSmall,
	})
	label.Size = UDim2.fromScale(1, 1)

	return chip
end

--[[
	A stat pill: icon chip plus a gradient number, as along the bottom-left of the reference's
	HUD. Returns the pill and its value label.
]]
function Bubbly.statPill(
	name: string,
	parent: Instance,
	glyph: string,
	chipFill: Color3,
	numberGradient: { Color3 }
): (Frame, TextLabel)
	local pill = Instance.new("Frame")
	pill.Name = name
	pill.BackgroundTransparency = 1
	pill.Size = UDim2.fromOffset(240, 52)
	pill.Parent = parent

	local chip = Bubbly.iconChip(pill, glyph, chipFill)
	chip.Position = UDim2.fromOffset(0, -1)

	local value = Bubbly.label("Value", pill, {
		text = "0",
		size = 34,
		gradient = numberGradient,
	})
	value.Size = UDim2.new(1, -(Theme.metric.iconChip + 12), 1, 0)
	value.Position = UDim2.fromOffset(Theme.metric.iconChip + 12, 0)

	return pill, value
end

--[[
	A panel: deep fill, thick outline, big corners, drop shadow. The shadow is parented
	alongside, so pass the frame the panel itself lives in.
]]
function Bubbly.panel(name: string, parent: Instance, fill: Color3?): Frame
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.BackgroundColor3 = fill or Theme.colour.panel
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Parent = parent

	Bubbly.corner(panel, Theme.metric.corner)
	Bubbly.stroke(panel, Theme.colour.text, Theme.metric.stroke)

	return panel
end

--[[
	A number that flies up and fades, for a collected payout.

	Destroys itself when it finishes, so the caller has no cleanup to forget -- the leak this
	avoids is the classic one in a game that pops a number on every cycle.
]]
function Bubbly.popNumber(parent: Instance, text: string, origin: UDim2): ()
	local label = Bubbly.label("Pop", parent, {
		text = text,
		size = 32,
		gradient = Theme.gradient.green,
		alignment = Enum.TextXAlignment.Center,
	})
	label.Size = UDim2.fromOffset(200, 40)
	label.Position = origin
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.ZIndex = 20

	local info =
		TweenInfo.new(Theme.motion.popDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local rise = TweenService:Create(label, info, {
		Position = origin - UDim2.fromOffset(0, 56),
		TextTransparency = 1,
	})

	local stroke = label:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	end

	rise.Completed:Connect(function()
		label:Destroy()
	end)
	rise:Play()
end

return table.freeze(Bubbly)
