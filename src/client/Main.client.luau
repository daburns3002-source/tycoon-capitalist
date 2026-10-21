--!strict
--[[
	Client entry point.

	Phase 0: bootstrap only. The client renders and predicts; it never decides a number.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local function main(): ()
	assert(Shared, "Shared folder failed to replicate")
	print("[Tycoon Capitalist] client bootstrapped")
end

main()

return nil
