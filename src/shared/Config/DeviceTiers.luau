--!strict
--[[
	Device tiers.

	"Easily accessible from multiple devices" is in the brief, so a phone and a desktop run the
	same code with different numbers rather than a desktop game with a phone apology. The tier
	is resolved once at join and everything that costs frames reads from it.

	Phase 2 only has a plot, a board and one building, so the budgets here are mostly forward
	declaration -- but they are declared now so Phase 7's art pass has a contract to hit instead
	of a conversation to have.

	Pure data. No logic, no functions, frozen.
]]

return table.freeze({
	Low = table.freeze({
		-- Phones and low-end tablets.
		streamingTargetRadius = 128,
		shadows = false,
		buildingDetail = 0,
		maxParticles = 24,
		numberPopsPerSecond = 4,
		panelBlur = false,
		-- Lower UI refresh: the progress bar is interpolated locally, so a slower push is
		-- invisible and saves a surprising amount on a mid-range Android.
		hudUpdatesPerSecond = 10,
	}),

	Medium = table.freeze({
		streamingTargetRadius = 256,
		shadows = true,
		buildingDetail = 1,
		maxParticles = 64,
		numberPopsPerSecond = 8,
		panelBlur = true,
		hudUpdatesPerSecond = 20,
	}),

	High = table.freeze({
		streamingTargetRadius = 512,
		shadows = true,
		buildingDetail = 2,
		maxParticles = 160,
		numberPopsPerSecond = 16,
		panelBlur = true,
		hudUpdatesPerSecond = 30,
	}),
})
