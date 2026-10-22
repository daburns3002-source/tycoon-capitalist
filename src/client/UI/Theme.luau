--!strict
--[[
	Every colour, font and metric the UI uses, in one place.

	Phase 4 is the Steal an Egg styling pass. The point of this file is that Phase 4 edits these
	values and nothing else -- if a colour appears inline in a widget, the restyle becomes a
	hunt through every file instead of one diff.

	On the font: `FredokaOne` is a placeholder, not a match. Roblox renders only its built-in
	font enums unless a font asset is uploaded, and the reference's typeface has not been
	identified yet -- so this is the closest chunky rounded built-in and Phase 4 either confirms
	it against screenshots or uploads the real one.
]]

return table.freeze({
	font = table.freeze({
		display = Enum.Font.FredokaOne,
		body = Enum.Font.GothamMedium,
		number = Enum.Font.GothamBold,
	}),

	colour = table.freeze({
		panelBackdrop = Color3.fromRGB(18, 20, 28),
		panelSurface = Color3.fromRGB(32, 36, 48),
		rowSurface = Color3.fromRGB(44, 49, 64),
		rowSurfaceReady = Color3.fromRGB(56, 72, 92),
		accent = Color3.fromRGB(255, 196, 64),
		accentDark = Color3.fromRGB(196, 140, 24),
		positive = Color3.fromRGB(104, 212, 124),
		negative = Color3.fromRGB(226, 96, 96),
		text = Color3.fromRGB(244, 246, 252),
		textDim = Color3.fromRGB(158, 166, 186),
		progressTrack = Color3.fromRGB(26, 29, 38),
		progressFill = Color3.fromRGB(255, 196, 64),
	}),

	metric = table.freeze({
		panelPadding = 14,
		rowHeight = 92,
		rowGap = 8,
		corner = 12,
		rowCorner = 10,
		stroke = 2,
		-- The panel is a fixed fraction of the viewport rather than a pixel size, so a phone
		-- and a desktop get the same layout at different scales.
		panelWidthScale = 0.92,
		panelHeightScale = 0.86,
		panelMaxWidth = 720,
	}),

	transparency = table.freeze({
		backdrop = 0.35,
	}),
})
