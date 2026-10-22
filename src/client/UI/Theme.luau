--!strict
--[[
	Every colour, font, metric and stroke the UI uses, in one place.

	Styled after Steal An Egg, studied from its store art and from gameplay footage. Worth
	recording what the "bubbly" look actually consists of, because it is a recipe rather than a
	vibe, and nearly all of it is things the first pass was missing:

	1. **A heavy black stroke on every piece of text.** This is the single biggest contributor
	   and it was the main thing absent before. Nothing in that game's UI is plain text on a
	   background; every label is outlined, which is what makes it read as a sticker rather
	   than as a document.
	2. **A thick light outline on every panel and button**, usually white or a brighter tint of
	   the fill, 3-4px. Buttons look like cut-out stickers laid on the world.
	3. **Corners so round they are nearly pills.** The first pass used 10-12px on 92px rows,
	   which reads as a web dashboard. Theirs is closer to a third of the height.
	4. **Saturated primary fills** -- postbox red, cyan blue, grass green, gold -- not the muted
	   slate-greys of a productivity app.
	5. **An icon chip**: a contrasting circle or rounded square on the left of a button holding
	   an icon, rather than an icon floating on the fill.
	6. **Gradients on the big numbers**, gold for money, cyan-white for counts.
	7. **Drop shadows** under panels and buttons, offset down, no blur.
	8. **A squash-and-pop on press**, which costs nothing and does more for feel than any
	   static treatment.

	The font is Fredoka One: a rounded heavy display sans and the nearest of Roblox's built-in
	fonts to theirs. Roblox renders only built-in font enums unless a font asset is uploaded, so
	if we ever want an exact match that is the route -- but with a black stroke at this weight
	the difference is small, and this costs nothing.
]]

return table.freeze({
	font = table.freeze({
		-- Everything the player reads at a glance. Deliberately the same face throughout:
		-- that game uses one voice and lets weight and colour do the work.
		display = Enum.Font.FredokaOne,
		-- Only for dense secondary text where Fredoka gets hard to read small.
		body = Enum.Font.GothamMedium,
		number = Enum.Font.FredokaOne,
	}),

	colour = table.freeze({
		-- Backdrop behind an open panel: deep navy, not black, so the world still reads.
		backdrop = Color3.fromRGB(16, 22, 42),
		-- Panel body.
		panel = Color3.fromRGB(46, 58, 96),
		panelDeep = Color3.fromRGB(32, 42, 74),
		-- A business row at rest and while its cycle is running.
		row = Color3.fromRGB(64, 80, 128),
		rowActive = Color3.fromRGB(86, 118, 180),

		-- Saturated primaries, used for buttons that mean something.
		money = Color3.fromRGB(255, 196, 54),
		moneyDeep = Color3.fromRGB(226, 146, 20),
		green = Color3.fromRGB(86, 212, 96),
		greenDeep = Color3.fromRGB(48, 160, 64),
		blue = Color3.fromRGB(64, 170, 255),
		blueDeep = Color3.fromRGB(28, 112, 204),
		red = Color3.fromRGB(240, 76, 76),
		redDeep = Color3.fromRGB(186, 40, 40),

		text = Color3.fromRGB(255, 255, 255),
		textDim = Color3.fromRGB(188, 202, 236),
		-- The outline colour on text and the shadow under panels. Near-black rather than pure,
		-- which keeps it from looking like a border and makes it read as depth.
		outline = Color3.fromRGB(12, 14, 28),

		track = Color3.fromRGB(28, 36, 64),
	}),

	--[[
		Gradients for the big numbers. Two stops, light at the top, saturated at the bottom --
		the standard treatment in this genre and the reason their numbers look embossed.
	]]
	gradient = table.freeze({
		money = table.freeze({ Color3.fromRGB(255, 236, 150), Color3.fromRGB(255, 176, 32) }),
		count = table.freeze({ Color3.fromRGB(226, 248, 255), Color3.fromRGB(96, 194, 255) }),
		green = table.freeze({ Color3.fromRGB(190, 255, 190), Color3.fromRGB(64, 194, 86) }),
	}),

	metric = table.freeze({
		panelPadding = 16,
		rowHeight = 118,
		rowGap = 12,
		-- Nearly a pill. This single number does more for "bubbly" than any colour change.
		corner = 24,
		rowCorner = 28,
		chipCorner = 18,
		-- Outline around panels and buttons.
		stroke = 4,
		rowStroke = 3,
		-- Outline around text.
		textStroke = 3,
		textStrokeSmall = 2,
		shadowOffset = 6,

		panelWidthScale = 0.94,
		panelHeightScale = 0.88,
		panelMaxWidth = 760,
		iconChip = 54,
	}),

	motion = table.freeze({
		-- Press feedback. Short enough that it never gets in the way of a fast tapper, which
		-- matters in a game whose core verb is tapping.
		pressDuration = 0.08,
		pressScale = 0.92,
		releaseDuration = 0.12,
		popDuration = 0.5,
	}),

	transparency = table.freeze({
		backdrop = 0.25,
	}),
})
