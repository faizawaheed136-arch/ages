--!strict
-- What a prop looks like when it is standing in the room.
--
-- The same split, for the same reason, as SubjectModels/SceneService: this decides
-- what turns up and PropService decides where it goes and what doing something to
-- it means. Replacing every one of these with a bought model must not touch a line
-- of the placement math, and retuning how far a rug slides must not touch its
-- geometry.
--
-- Two sources, in the order they are tried, and the order matches SubjectModels
-- exactly so there is one rule to remember:
--
--   A real Model named after the prop id, inside the ServerStorage folder
--   Config.World.PropFolder names. Drop in a Model called "rug" and nothing in
--   code moves.
--
--   Otherwise a shape built from the prop's own dimensions.
--
-- Unlike a subject, a prop has no rig and nothing to animate. It is one solid thing
-- that gets slid around, so what comes back is a Model with a PrimaryPart and no
-- limbs -- and a rug being pushed is that Model being moved, not a gait.
--
-- Anchored throughout and never collidable, which is the rule that took the longest
-- to arrive at. The temptation with a pushable rug is to let the physics engine do
-- it: make it unanchored, walk into it, watch it slide. That produces a rug that can
-- be shoved through a wall, tipped on its side, launched by a player who jumps on
-- it, and left in a place the next event then tries to stage a cookie inside. A prop
-- that moves only when this game says it moves is not a limitation, it is the
-- feature -- and it costs one lerp.
--
-- CanQuery off for the same reason SubjectModels turns it off: a prop that answered
-- floor and clearance probes would be reported as furniture by Ground, including by
-- the probes that run while it is still standing there deciding where its own
-- neighbours go.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type PropKind = Types.PropKind

local PropModels = {}

-- The root is a marker rather than a body, exactly as it is on a subject: it exists
-- so the model's pivot sits at the centre of the prop's footprint on the floor,
-- which is what lets a caller place it with one PivotTo onto a point the floor probe
-- returned.
local ROOT_SIZE = Vector3.new(0.2, 0.2, 0.2)

-- A figure is a body and a head and that is all. Proportions rather than sizes, so
-- the same two numbers make a toddler and a ten-year-old out of one authored height.
-- Kept here rather than in Config for the reason SubjectModels gives: what fraction
-- of a child is head is not a number anybody balances a life simulator with.
local FIGURE_HEAD_FRACTION = 0.3 -- of total height; children are top-heavy and should look it
local FIGURE_BODY_TAPER = 0.82 -- body width as a fraction of the declared width

local function newPart(model: Model, name: string, size: Vector3, at: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = at
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = model
	return part
end

-- Everything is built with its footprint centred on the origin and its underside at
-- y = 0, so a caller places it by pivoting the model onto the floor point and adding
-- the prop's own lift. Nothing here knows where in the house it is going.
local function buildShape(model: Model, prop: PropKind)
	local size = prop.size

	if prop.shape == "Ball" then
		local ball = newPart(model, "Prop", size, CFrame.new(0, size.Y / 2, 0), prop.color)
		ball.Shape = Enum.PartType.Ball
		return
	end

	if prop.shape == "Cylinder" then
		-- A Roblox cylinder's circular face is in its local YZ plane and its axis is
		-- local X, so a disc lying flat on the floor is one rotated a quarter turn
		-- about Z. That rotation maps local X to world Y, so the part is built with
		-- its authored height in X and its authored width in Y and comes out the
		-- right way up with the right footprint. Easy to get backwards, and when it
		-- is backwards the plate stands on its edge like a wheel.
		local disc = newPart(
			model,
			"Prop",
			Vector3.new(size.Y, size.X, size.Z),
			CFrame.new(0, size.Y / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			prop.color
		)
		disc.Shape = Enum.PartType.Cylinder
		return
	end

	if prop.shape == "Figure" then
		local headSize = size.Y * FIGURE_HEAD_FRACTION
		local bodyHeight = size.Y - headSize
		newPart(
			model,
			"Body",
			Vector3.new(size.X * FIGURE_BODY_TAPER, bodyHeight, size.Z),
			CFrame.new(0, bodyHeight / 2, 0),
			prop.color
		)
		-- The head takes the accent color, which on a figure is a skin tone rather
		-- than a trim. That is the whole difference between a person and a bollard.
		local head = newPart(
			model,
			"Head",
			Vector3.new(headSize, headSize, headSize),
			CFrame.new(0, bodyHeight + headSize / 2, 0),
			prop.accentColor
		)
		head.Shape = Enum.PartType.Ball
		return
	end

	-- Block. Two parts rather than one: a slab in the main color with a thin border
	-- of the accent standing just proud of its edges. One extra part, and it is the
	-- difference between a rug and a brown rectangle on the carpet -- at this
	-- fidelity an edge is what tells the eye an object is an object.
	newPart(model, "Prop", size, CFrame.new(0, size.Y / 2, 0), prop.color)
	local trimInset = math.min(size.X, size.Z) * 0.12
	newPart(
		model,
		"Trim",
		Vector3.new(size.X - trimInset, size.Y * 0.6, size.Z - trimInset),
		CFrame.new(0, size.Y * 0.8, 0),
		prop.accentColor
	)
end

local function authoredModel(propId: string): Model?
	local folder = ServerStorage:FindFirstChild(Config.World.PropFolder)
	if folder == nil then
		return nil
	end
	local found = folder:FindFirstChild(propId)
	if found == nil then
		return nil
	end
	if not found:IsA("Model") then
		warn(`[AGES] "{propId}" in {Config.World.PropFolder} is a {found.ClassName}, not a Model; using the placeholder`)
		return nil
	end
	return found
end

-- A hand-made model has its own idea of where its origin is, and it is rarely the
-- middle of its own footprint. Rather than asking whoever drops one in to get that
-- right, a root is added at the centre of the bottom of its bounding box -- so an
-- adopted rug places identically to a built one and PropService never learns which
-- it got.
local function adoptModel(source: Model, propId: string): Model?
	local model = source:Clone()

	local ok, boxCFrame, boxSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or boxCFrame == nil or boxSize == nil then
		warn(`[AGES] prop model "{propId}" has no parts to measure; using the placeholder instead`)
		model:Destroy()
		return nil
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end

	local root = Instance.new("Part")
	root.Name = "PropRoot"
	root.Size = ROOT_SIZE
	root.CFrame =
		CFrame.new(Vector3.new(boxCFrame.Position.X, boxCFrame.Position.Y - boxSize.Y / 2, boxCFrame.Position.Z))
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	return model
end

-- Builds the prop, unparented and unplaced, with its pivot at the centre of its
-- underside. The caller pivots it onto a floor point and lifts it by the prop's own
-- liftStuds.
function PropModels.Build(prop: PropKind): Model
	local authored = authoredModel(prop.id)
	if authored ~= nil then
		local adopted = adoptModel(authored, prop.id)
		if adopted ~= nil then
			adopted.Name = `Prop_{prop.id}`
			return adopted
		end
	end

	local model = Instance.new("Model")
	buildShape(model, prop)

	local root = newPart(model, "PropRoot", ROOT_SIZE, CFrame.new(0, 0, 0), prop.color)
	root.Transparency = 1
	root.CastShadow = false
	model.PrimaryPart = root

	model.Name = `Prop_{prop.id}`
	return model
end

return PropModels
