--!strict
--[[
	Clicking into the board.

	The board carries a ProximityPrompt, built server-side by PlotBuilder. Using the prompt
	rather than a ClickDetector is the whole reason this file is short: the prompt already
	handles touch, keyboard and gamepad, shows the right affordance on each, and handles
	distance -- three input paths that would otherwise be written and maintained here.

	This module only has to notice that *the local player's own* board was triggered. Plots are
	laid out in a row, so without that check a player standing near a neighbour's plot could
	open a panel from their board.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local Device = require(script.Parent.Parent.Device)

local BoardInteraction = {}

local PROMPT_NAME = "OpenPrompt"
local OWNER_ATTRIBUTE = "OwnerUserId"

--[[
	Walk up from the prompt to the plot model and read its owner.

	Returns nil when the prompt is not a board prompt, so an unrelated prompt added later does
	not accidentally open the panel.
]]
local function ownerOf(prompt: ProximityPrompt): number?
	if prompt.Name ~= PROMPT_NAME then
		return nil
	end

	local plots = Workspace:FindFirstChild("Plots")
	if plots == nil then
		return nil
	end

	local node: Instance? = prompt
	while node ~= nil and node.Parent ~= plots do
		node = node.Parent
	end
	if node == nil then
		return nil
	end

	local owner = node:GetAttribute(OWNER_ATTRIBUTE)
	if typeof(owner) ~= "number" then
		return nil
	end
	return owner
end

--[[
	Connect the prompt to `onOpen`, which fires only for the local player's own board.

	Returns the connection so the caller owns its lifetime -- every `:Connect` in this project
	has a disconnect path.
]]
function BoardInteraction.connect(onOpen: () -> ()): RBXScriptConnection
	local localUserId = Device.localPlayer().UserId

	return ProximityPromptService.PromptTriggered:Connect(
		function(prompt: ProximityPrompt, player: Player)
			if player.UserId ~= localUserId then
				return
			end
			if ownerOf(prompt) ~= localUserId then
				return
			end
			onOpen()
		end
	)
end

return table.freeze(BoardInteraction)
