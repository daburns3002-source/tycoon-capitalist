--!strict
--[[
	Remote definitions.

	One place where every client/server boundary is named, so the set of things a hostile client
	can reach is a list you can read rather than something to grep for. An idle game is pure
	currency, which makes it pure exploit surface -- CLAUDE.md, non-negotiable 3.

	Shape of the protocol:

	* The client sends *intents* -- "I clicked this business", "buy some of this" -- and never
	  values. No cash totals, no elapsed time, no payouts. The server reads its own clock and
	  its own state and decides.
	* The server pushes *snapshots*. The client renders what it is told and interpolates the
	  progress bar locally for smoothness, but never computes a number that matters.

	Deliberately RemoteEvents in both directions rather than RemoteFunctions: a RemoteFunction
	lets a client stall a server thread by never returning, and nothing here needs a blocking
	call.
]]

local RunService = game:GetService("RunService")

local Remotes = {}

--[[
	Client to server. Every one of these is an intent with no trusted payload.
]]
local TO_SERVER: { [string]: string } = {
	-- "I clicked a business row." Payload: businessId (string).
	StartCycle = "StartCycle",
	-- "Buy units." Payload: businessId (string), mode ("x1" | "x10" | "x100" | "max").
	BuyUnits = "BuyUnits",
	--[[
		"Hire this business's manager." Payload: businessId (string).

		The manager is what turns a clicker into an idle game: from here the business restarts
		its own cycle forever, including while the player is away.
	]]
	HireManager = "HireManager",
	-- "Buy this cash upgrade." Payload: upgradeId (string). Permanent for the run, lost on an
	-- angel reset like everything else bought with cash.
	BuyUpgrade = "BuyUpgrade",
	--[[
		"Reset for Angel Investors." No payload.

		Destructive and irreversible: it wipes cash, units, managers and upgrades. The client
		confirms before sending, but the server does not rely on that -- it refuses a reset that
		would pay nothing, which is the case a confirmation dialog exists to prevent.
	]]
	PerformReset = "PerformReset",
	-- "Sacrifice angels for this upgrade." Payload: upgradeId (string). The angels are gone
	-- permanently; the upgrade is not.
	BuyAngelUpgrade = "BuyAngelUpgrade",
	-- "I selected a buy mode." Payload: mode ("x1" | "x10" | "x100" | "max").
	--
	-- The mode has to be server state, not client state, because the server prices the selected
	-- batch for every row in the snapshot. Without this intent the server never learns the
	-- selection, keeps pricing x1, and the next snapshot overwrites the player's choice.
	SetBuyMode = "SetBuyMode",
	-- "I opened or closed the board." Payload: isOpen (boolean). Lets the server stop pushing
	-- panel detail to a client that is not looking at it.
	SetPanelOpen = "SetPanelOpen",
}

--[[
	Server to client.
]]
local TO_CLIENT: { [string]: string } = {
	-- Full plot snapshot. Sent on join and whenever something the panel shows changes.
	PlotSnapshot = "PlotSnapshot",
	-- A cycle paid out. Drives the number pop and the collect sound; the authoritative totals
	-- still arrive in the snapshot.
	CyclePaid = "CyclePaid",
	--[[
		"Your managers earned this while you were away."

		Payload: seconds (number), amount (BigNumber), businesses (number). Sent once on join,
		and only when something was actually earned -- a welcome-back panel showing zero is
		worse than no panel.
	]]
	WelcomeBack = "WelcomeBack",
	-- A rejected intent, with a reason, so the UI can say why rather than silently doing
	-- nothing. Payload: intent (string), reason (string).
	IntentRejected = "IntentRejected",
}

Remotes.toServer = table.freeze(TO_SERVER)
Remotes.toClient = table.freeze(TO_CLIENT)

local FOLDER_NAME = "Remotes"

--[[
	Fetch (server) or wait for (client) the RemoteEvent for `name`.

	The server creates the folder and the events on first use; the client waits. Both go through
	this function so a typo is a nil index at startup rather than a remote that silently never
	fires.
]]
local function container(): Instance
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing
		end

		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end

	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local cache: { [string]: RemoteEvent } = {}

function Remotes.get(name: string): RemoteEvent
	local cached = cache[name]
	if cached then
		return cached
	end

	local parent = container()
	local remote: RemoteEvent

	if RunService:IsServer() then
		local existing = parent:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			remote = existing
		else
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = parent
		end
	else
		remote = parent:WaitForChild(name) :: RemoteEvent
	end

	cache[name] = remote
	return remote
end

--[[
	Create every remote up front, on the server, so the client's WaitForChild calls resolve
	immediately rather than racing the first use.
]]
function Remotes.createAll(): ()
	if not RunService:IsServer() then
		error("Remotes.createAll: server only", 2)
	end

	for _, name in TO_SERVER do
		Remotes.get(name)
	end
	for _, name in TO_CLIENT do
		Remotes.get(name)
	end
end

return table.freeze(Remotes)
