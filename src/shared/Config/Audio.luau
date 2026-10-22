--!strict
--[[
	Sound cues.

	Every id here is an `rbxasset://` path, which means the audio ships with the Roblox client
	rather than living on the catalogue. Three consequences, all of them useful right now:

	* it works in an unpublished place, which is where this game currently is
	* there is no upload step and no asset that can 404 or be moderated away
	* every one of these was checked in Studio and confirmed to load -- several plausible-looking
	  built-ins (`pop.wav`, `swoosh.wav`, `button-09.mp3`) silently do not, and a cue pointed at
	  one of those is a cue that never plays

	They are **placeholders with the right shape**, not the final audio. Phase 7 replaces the ids
	and nothing else: volume, pitch variation and rate limits are already tuned per cue here.

	`rateLimit` is the minimum gap between two plays of the same cue. It is not politeness -- a
	managed Lemonade Stand past fifty units pays every 0.15 seconds, and without a limit the
	collect cue becomes a continuous tone.

	Pure data. No logic, no functions, frozen.
]]

--[[ One cue. Declared so consumers can iterate this table without losing the field types. ]]
export type Cue = {
	id: string,
	volume: number,
	pitch: number,
	pitchJitter: number,
	rateLimit: number,
}

return table.freeze({
	--[[ A business paid out. The one cue that fires constantly, so it is short and quiet. ]]
	collect = table.freeze({
		id = "rbxasset://sounds/electronicpingshort.wav",
		volume = 0.18,
		pitch = 1.3,
		-- Varies slightly each play, so a run of payouts does not sound like a machine.
		pitchJitter = 0.08,
		rateLimit = 0.12,
	}),

	--[[ Units bought. Should feel like something landing. ]]
	buy = table.freeze({
		id = "rbxasset://sounds/snap.wav",
		volume = 0.35,
		pitch = 1.1,
		pitchJitter = 0.05,
		rateLimit = 0.05,
	}),

	--[[ A manager hired: heavier, because it changes how the game plays. ]]
	manager = table.freeze({
		id = "rbxasset://sounds/metal.ogg",
		volume = 0.4,
		pitch = 0.9,
		pitchJitter = 0,
		rateLimit = 0.2,
	}),

	--[[ An unlock earned. The reward sound, so it gets the low end. ]]
	unlock = table.freeze({
		id = "rbxasset://sounds/bass.wav",
		volume = 0.45,
		pitch = 1,
		pitchJitter = 0,
		rateLimit = 0.4,
	}),

	--[[ A reset. Long and distinct -- it should not sound like anything else in the game. ]]
	reset = table.freeze({
		id = "rbxasset://sounds/impact_water.mp3",
		volume = 0.5,
		pitch = 0.8,
		pitchJitter = 0,
		rateLimit = 1,
	}),

	--[[ Tab changes and the board opening. Quiet; it fires on every navigation. ]]
	tap = table.freeze({
		id = "rbxasset://sounds/clickfast.wav",
		volume = 0.22,
		pitch = 1,
		pitchJitter = 0.04,
		rateLimit = 0.06,
	}),

	--[[ An intent the server refused, so the player is not left wondering. ]]
	denied = table.freeze({
		id = "rbxasset://sounds/switch3.wav",
		volume = 0.25,
		pitch = 0.7,
		pitchJitter = 0,
		rateLimit = 0.3,
	}),
})
