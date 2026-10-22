--!strict
--[[
	Builds a plot out of parts, from World config.

	Nothing here is authored by hand in Studio. CLAUDE.md, non-negotiable 8: Studio is a
	renderer and a test harness, not a source of truth, so the world is code that produces
	geometry rather than a model someone dragged into place and nobody can diff.

	Grey boxes on purpose. Phase 7 replaces the geometry with Blender meshes; what matters now
	is that the layout is readable and the board is obviously the thing to walk up to.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Businesses = require(Shared.Config.Businesses)
local Types = require(Shared.Types)
local World = require(Shared.Config.World)

local PlotBuilder = {}

export type Plot = {
	model: Model,
	origin: Vector3,
	spawnPosition: Vector3,
	board: BasePart,
	buildings: { [Types.BusinessId]: BasePart },
}

local function part(name: string, size: Vector3, colour: Color3, parent: Instance): Part
	local created = Instance.new("Part")
	created.Name = name
	created.Size = size
	created.Color = colour
	created.Anchored = true
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Material = Enum.Material.SmoothPlastic
	created.Parent = parent
	return created
end

--[[
	A low wall around the plot.

	Four parts rather than a mesh, because at Phase 2 the point is a readable boundary and
	anything more detailed would be thrown away in Phase 7.
]]
local function buildBorder(model: Model, origin: Vector3): ()
	local size = World.plot.size
	local height = World.plot.borderHeight
	local thickness = World.plot.borderThickness
	local halfX = size.X / 2
	local halfZ = size.Z / 2

	local edges = {
		{ Vector3.new(size.X, height, thickness), Vector3.new(0, height / 2, -halfZ) },
		{ Vector3.new(size.X, height, thickness), Vector3.new(0, height / 2, halfZ) },
		{ Vector3.new(thickness, height, size.Z), Vector3.new(-halfX, height / 2, 0) },
		{ Vector3.new(thickness, height, size.Z), Vector3.new(halfX, height / 2, 0) },
	}

	for index, edge in edges do
		local wall = part(`Border{index}`, edge[1], World.plot.borderColour, model)
		wall.Position = origin + edge[2]
	end
end

--[[
	The board: the one interactive object on the plot, and the way into the game.

	Built as an angled face on two legs so it reads as something to use. The ProximityPrompt is
	the interaction on every device -- it handles touch, keyboard and gamepad without three
	separate input paths, which is most of why it is used here rather than a ClickDetector.
]]
local function buildBoard(model: Model, origin: Vector3): BasePart
	local config = World.board
	local centre = origin + config.offset + Vector3.new(0, config.height, 0)

	local face = part("BoardFace", config.size, config.faceColour, model)
	face.CFrame = CFrame.new(centre) * CFrame.Angles(math.rad(config.tilt), 0, 0)

	local frame =
		part("BoardFrame", config.size + Vector3.new(0.8, 0.8, -0.4), config.frameColour, model)
	frame.CFrame = face.CFrame
	frame.CanCollide = false

	for index, side in { -1, 1 } do
		local leg = part(`BoardLeg{index}`, config.legSize, config.frameColour, model)
		leg.Position = Vector3.new(
			centre.X + side * (config.size.X / 2 - 1.5),
			origin.Y + config.legSize.Y / 2,
			centre.Z
		)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenPrompt"
	prompt.ActionText = config.promptText
	prompt.ObjectText = config.promptObjectText
	prompt.MaxActivationDistance = config.promptDistance
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = face

	return face
end

--[[
	The building row behind the board.

	Display only. No prompt, no click detector, no mechanics -- the panel owns the economy and
	these exist so a player can see their empire rather than only read it. Phase 3 fills the
	row out; Phase 7 replaces the boxes.
]]
local function buildBuildings(
	model: Model,
	origin: Vector3,
	unlocked: { Types.BusinessId }
): { [Types.BusinessId]: BasePart }
	local built: { [Types.BusinessId]: BasePart } = {}
	local config = World.buildings

	for _, id in unlocked do
		local businessConfig = Businesses.byId[id]
		if businessConfig == nil then
			continue
		end

		local offset = Vector3.new((businessConfig.order - 1) * config.spacing, 0, 0)
		local position = origin + config.rowStart + offset
		local box = part(id, config.baseSize, Color3.fromRGB(200, 196, 108), model)
		box.Position = position + Vector3.new(0, config.baseSize.Y / 2, 0)

		local label = Instance.new("StringValue")
		label.Name = "BusinessId"
		label.Value = id
		label.Parent = box

		built[id] = box
	end

	return built
end

--[[
	Build one plot at `index` along the row.

	Index rather than a position so that adding plots for more players later is arithmetic and
	not a layout redesign.
]]
function PlotBuilder.build(index: number, unlocked: { Types.BusinessId }, parent: Instance): Plot
	local origin = Vector3.new(index * World.plot.spacing, 0, 0)

	local model = Instance.new("Model")
	model.Name = `Plot{index}`

	local ground = part("Ground", World.plot.size, World.plot.groundColour, model)
	ground.Position = origin
	model.PrimaryPart = ground

	buildBorder(model, origin)
	local board = buildBoard(model, origin)
	local buildings = buildBuildings(model, origin, unlocked)

	model.Parent = parent

	return {
		model = model,
		origin = origin,
		spawnPosition = origin + World.spawn.offset,
		board = board,
		buildings = buildings,
	}
end

--[[
	Scale a building to reflect its unit count.

	A readout, not a mechanic. Steps at the thresholds in World config rather than growing
	continuously, so the change is a visible event the player can connect to the milestone that
	caused it.
]]
function PlotBuilder.updateBuilding(plot: Plot, id: Types.BusinessId, unitsOwned: number): ()
	local box: BasePart? = plot.buildings[id]
	if box == nil then
		return
	end

	--[[
		A business you do not own yet has nothing standing on the plot.

		The panel still lists it with its price -- that is where the aiming happens -- but an
		empty plot that fills in as the empire grows is the whole point of putting the row out
		here, and ten identical boxes from the first second would throw that away.
	]]
	local config = World.buildings
	local steps = 0
	for _, threshold in config.growthThresholds do
		if unitsOwned >= threshold then
			steps += 1
		end
	end

	if steps == 0 then
		box.Transparency = 1
		box.CanCollide = false
		return
	end

	box.Transparency = 0
	box.CanCollide = true

	local scale = config.growthStep ^ (steps - 1)
	local size = config.baseSize * scale
	local base = box.Position.Y - box.Size.Y / 2

	box.Size = size
	box.Position = Vector3.new(box.Position.X, base + size.Y / 2, box.Position.Z)
end

return table.freeze(PlotBuilder)
