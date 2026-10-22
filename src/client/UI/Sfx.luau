--!strict
--[[
	Plays the sound cues.

	Three things this does that a bare `Sound:Play()` does not:

	1. **Rate limits per cue.** A managed Lemonade Stand past fifty units pays every 0.15
	   seconds. Without a limit the collect cue stops being a sound and becomes a tone.
	2. **Varies the pitch.** A cue that fires in runs sounds mechanical at a fixed pitch; a few
	   percent of jitter is the difference between a game and a smoke alarm.
	3. **Reuses a small pool.** Creating a Sound per payout and trusting the garbage collector
	   is how a long session ends up with thousands of instances in SoundService.

	Every cue is preloaded once at startup. A sound that is still loading when first played is
	simply silent, which reads as a bug in the thing that triggered it rather than in the audio.
]]

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared.Config.Audio)

local Sfx = {}

--[[
	How many Sound instances a cue keeps.

	Four is enough for the cues that overlap -- collect, mostly -- and the rate limit stops
	anything needing more. A single instance would cut each play off at the next one.
]]
local POOL_SIZE = 4

type Voice = {
	sounds: { Sound },
	next: number,
	lastPlayedAt: number,
}

local voices: { [string]: Voice } = {}
local container: Folder? = nil
local muted = false

local function ensureContainer(): Folder
	local existing = container
	if existing then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "Sfx"
	folder.Parent = SoundService
	container = folder
	return folder
end

--[[ Build the pools and preload every cue. Safe to call more than once. ]]
function Sfx.start(): ()
	if next(voices) ~= nil then
		return
	end

	local parent = ensureContainer()
	local toPreload: { Instance } = {}

	for name: string, cue: Audio.Cue in Audio :: any do
		local pool: { Sound } = {}
		for index = 1, POOL_SIZE do
			local sound = Instance.new("Sound")
			sound.Name = `{name}{index}`
			sound.SoundId = cue.id
			sound.Volume = cue.volume
			sound.PlaybackSpeed = cue.pitch
			sound.Parent = parent
			table.insert(pool, sound)
		end

		voices[name] = { sounds = pool, next = 1, lastPlayedAt = 0 }
		table.insert(toPreload, pool[1])
	end

	-- Preloading blocks, so it runs off the caller's thread.
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(toPreload)
		end)
	end)
end

--[[
	Play a cue by name.

	Silently does nothing for an unknown name rather than erroring: a missing sound should never
	be the thing that breaks a purchase.
]]
function Sfx.play(name: string): ()
	if muted then
		return
	end

	local cue: Audio.Cue? = (Audio :: any)[name]
	local voice = voices[name]
	if cue == nil or voice == nil then
		return
	end

	local rateLimit = cue.rateLimit
	local now = os.clock()
	if now - voice.lastPlayedAt < rateLimit then
		return
	end
	voice.lastPlayedAt = now

	local sound = voice.sounds[voice.next]
	voice.next = (voice.next % #voice.sounds) + 1

	if cue.pitchJitter > 0 then
		sound.PlaybackSpeed = cue.pitch + (math.random() * 2 - 1) * cue.pitchJitter
	end

	sound.TimePosition = 0
	sound:Play()
end

--[[ For a settings toggle later, and so a test can silence the lot. ]]
function Sfx.setMuted(value: boolean): ()
	muted = value
end

function Sfx.isMuted(): boolean
	return muted
end

function Sfx.destroy(): ()
	for _, voice in voices do
		for _, sound in voice.sounds do
			sound:Destroy()
		end
	end
	table.clear(voices)

	if container then
		container:Destroy()
		container = nil
	end
end

return table.freeze(Sfx)
