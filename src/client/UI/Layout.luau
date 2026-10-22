--!strict
--[[
	Viewport size to UI metrics.

	A pure function, deliberately: "does this fit on a phone" is the kind of question that should
	be answerable in a test rather than by squinting at a device emulator. Nothing here touches
	an instance or a service -- it takes two numbers and returns a table.

	The brief asks for a game that works across devices, and the panel is where almost all the
	screen time happens, so this is the file that decides whether a phone gets a real layout or a
	desktop one with everything shrunk.

	Three bands rather than a continuous scale. A continuous one sounds tidier and produces
	in-between sizes nobody designed for; bands mean each layout was actually chosen.
]]

local Layout = {}

export type Metrics = {
	--[[ Phone-sized: the band where things have to be dropped rather than shrunk. ]]
	compact: boolean,
	panelWidthScale: number,
	panelHeightScale: number,
	panelMaxWidth: number,
	rowHeight: number,
	rowGap: number,
	buyWidth: number,
	iconChip: number,
	titleSize: number,
	bodySize: number,
	tabSize: number,
	cashSize: number,
	--[[
		Whether a row has room for its third line.

		On a phone the milestone hint is the first thing to go: the name, the count and the price
		are what a purchase decision needs, and the hint repeats what the GOALS tab says anyway.
	]]
	showRowHint: boolean,
	--[[ Top inset, so a panel does not sit under a notch or the Roblox topbar. ]]
	topInset: number,
}

local DESKTOP: Metrics = {
	compact = false,
	panelWidthScale = 0.94,
	panelHeightScale = 0.88,
	panelMaxWidth = 760,
	rowHeight = 118,
	rowGap = 12,
	buyWidth = 150,
	iconChip = 54,
	titleSize = 24,
	bodySize = 18,
	tabSize = 15,
	cashSize = 40,
	showRowHint = true,
	topInset = 0,
}

--[[ Phone landscape, and small tablets. Everything is tighter but nothing is dropped. ]]
local MEDIUM: Metrics = {
	compact = false,
	panelWidthScale = 0.96,
	panelHeightScale = 0.92,
	panelMaxWidth = 640,
	rowHeight = 106,
	rowGap = 10,
	buyWidth = 132,
	iconChip = 48,
	titleSize = 21,
	bodySize = 16,
	tabSize = 14,
	cashSize = 34,
	showRowHint = true,
	topInset = 0,
}

--[[ Phone portrait. ]]
local COMPACT: Metrics = {
	compact = true,
	panelWidthScale = 0.98,
	panelHeightScale = 0.94,
	panelMaxWidth = 520,
	rowHeight = 94,
	rowGap = 8,
	buyWidth = 112,
	iconChip = 42,
	titleSize = 18,
	bodySize = 14,
	tabSize = 12,
	cashSize = 28,
	showRowHint = false,
	topInset = 36,
}

--[[ Below this width a layout has to drop things, not just shrink them. ]]
local COMPACT_WIDTH = 560
local MEDIUM_WIDTH = 900

--[[ Below this height even a wide viewport is short enough to need the tighter row. ]]
local SHORT_HEIGHT = 520

--[[
	Pick a layout for a viewport.

	`height` matters as well as width: a phone held sideways is wide and very short, and giving
	it the desktop row leaves two businesses visible with no room to scroll comfortably.
]]
function Layout.forViewport(width: number, height: number): Metrics
	if width < COMPACT_WIDTH then
		return COMPACT
	end
	if width < MEDIUM_WIDTH or height < SHORT_HEIGHT then
		return MEDIUM
	end
	return DESKTOP
end

Layout.desktop = DESKTOP
Layout.medium = MEDIUM
Layout.compact = COMPACT

return table.freeze(Layout)
