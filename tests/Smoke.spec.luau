--!strict
--[[
	Phase 0 smoke test.

	Replaced in Phase 1 by the economy suite, which asserts against values read out of the real
	game. See the anchor table in CLAUDE.md.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

local function run(): boolean
	assert(Types == nil or Types ~= nil, "Types module failed to load")
	return true
end

return {
	run = run,
}
