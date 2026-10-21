--!strict
--[[
	Server entry point.

	Phase 0: bootstrap only. The plot, tick and persistence systems arrive in Phases 2 and 5.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local function main(): ()
	assert(Shared, "Shared folder failed to replicate")
	print("[Tycoon Capitalist] server bootstrapped")
end

main()

return nil
