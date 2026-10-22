--!strict
--[[
	Plot and world layout.

	Grey-box numbers for Phase 2. The plot is deliberately small: the board is the game, and a
	plot the player has to cross a field to reach just puts distance between them and it. Big
	enough to feel like a place, small enough that the board is always a few seconds away.

	Pure data. No logic, no functions, frozen.
]]

local PLOT_SIZE = Vector3.new(96, 1, 96)

return table.freeze({
	plot = table.freeze({
		size = PLOT_SIZE,
		-- Plots are laid out along X with a gap, so adding players later is arithmetic rather
		-- than a redesign.
		spacing = PLOT_SIZE.X + 48,
		groundColour = Color3.fromRGB(104, 142, 96),
		borderColour = Color3.fromRGB(78, 108, 72),
		borderHeight = 2,
		borderThickness = 2,
	}),

	spawn = table.freeze({
		-- Offset toward the near edge so the board is in view on arrival rather than behind.
		offset = Vector3.new(0, 4, 28),
	}),

	board = table.freeze({
		-- The one interactive object in Phase 2. Waist-high and angled back like a lectern, so
		-- it reads as something to use rather than scenery to walk past.
		offset = Vector3.new(0, 0, -8),
		size = Vector3.new(14, 9, 1),
		legSize = Vector3.new(1.5, 5, 1.5),
		tilt = -18,
		height = 7,
		faceColour = Color3.fromRGB(44, 48, 58),
		frameColour = Color3.fromRGB(216, 184, 96),
		promptText = "Open",
		promptObjectText = "Your Business Empire",
		promptDistance = 14,
	}),

	--[[
		Buildings are placed in a row behind the board. In Phase 2 only the Lemonade Stand
		exists; the rest of the row fills in during Phase 3. These are display only -- no
		mechanics hang off them, the panel owns the economy.
	]]
	buildings = table.freeze({
		rowStart = Vector3.new(-40, 0, -34),
		spacing = 9,
		baseSize = Vector3.new(6, 4, 6),
		-- Unit counts at which a building visibly grows. Matches the cycle milestones so the
		-- world reflects the moment the economy jumps.
		growthThresholds = table.freeze({ 1, 25, 50, 100, 200, 400 }),
		growthStep = 1.35,
	}),
})
