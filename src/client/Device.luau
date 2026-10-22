--!strict
--[[
	Resolves the device tier once, at join.

	"Easily accessible from multiple devices" is in the brief, so everything that costs frames
	reads a budget from here rather than hard-coding a number that happens to work on the
	machine it was written on. CLAUDE.md, non-negotiable 6.

	Tiering is a judgement call -- Roblox gives no device model or GPU -- so this reads the
	signals it does give: touch versus keyboard, whether it is a console, and the viewport's
	size. A phone is touch-only with a small viewport; a tablet is touch with a large one and
	gets the middle tier rather than the phone's budget.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DeviceTiers = require(Shared.Config.DeviceTiers)
local Types = require(Shared.Types)

local Device = {}

-- Below this diagonal, in pixels, a touch device is treated as a phone rather than a tablet.
local PHONE_DIAGONAL = 1100

-- Named rather than returned as bare literals: a literal in a return position widens to
-- `string`, which then fails against the DeviceTier union at every call site.
local LOW: Types.DeviceTier = "Low"
local MEDIUM: Types.DeviceTier = "Medium"
local HIGH: Types.DeviceTier = "High"

--[[
	Cached tier, held as a definite value plus a flag rather than as an optional.

	This looks like it wants to be `local resolved: Types.DeviceTier? = nil`, and it did. Do not
	change it back: narrowing an *optional* string-literal union widens it to plain `string` in
	the pinned luau-lsp, so `if cached then return cached end` fails to type-check against
	DeviceTier. Verified both the `== nil` and the truthiness form; neither narrows correctly,
	and this form does.
]]
local resolvedTier: Types.DeviceTier = "High"
local hasResolved = false

local function viewportDiagonal(): number
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return PHONE_DIAGONAL
	end

	local size = camera.ViewportSize
	return math.sqrt(size.X * size.X + size.Y * size.Y)
end

local function resolve(): Types.DeviceTier
	if GuiService:IsTenFootInterface() then
		-- Console: plenty of GPU, but a TV at distance wants larger UI, which the panel's
		-- scale-based layout already gives it.
		return HIGH
	end

	local touch = UserInputService.TouchEnabled
	local keyboard = UserInputService.KeyboardEnabled

	if touch and not keyboard then
		return if viewportDiagonal() < PHONE_DIAGONAL then LOW else MEDIUM
	end

	return HIGH
end

--[[ The tier, resolved on first call and cached. ]]
function Device.tier(): Types.DeviceTier
	if not hasResolved then
		resolvedTier = resolve()
		hasResolved = true
	end
	return resolvedTier
end

--[[ The budget table for this device. ]]
function Device.budget(): typeof(DeviceTiers.High)
	return DeviceTiers[Device.tier()]
end

--[[
	Whether this device drives the game by touch.

	Separate from the tier: a tablet is Medium but still touch, and interaction differs from
	rendering budget. Used to decide whether the panel shows a close button or relies on a key.
]]
function Device.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Device.localPlayer(): Player
	local player = Players.LocalPlayer
	if player == nil then
		error("Device.localPlayer: no LocalPlayer -- client only", 2)
	end
	return player
end

return table.freeze(Device)
