--!strict
-- The exterior shell of the new school: three storeys, flat roof, glazed entrance bay.
--
-- **Everything here is derived from PLAN.** Not one coordinate below is written down twice, and
-- none is a literal that means something. That is not tidiness for its own sake -- the last
-- school was rebuilt six times because a number like "the corridor is at z 53" was true in one
-- function and false in another after a change, and every one of those bugs was invisible until
-- somebody walked into it. If a dimension moves here, everything that depends on it moves.

local Engine = require(script.Parent.SchoolBuilderEngine)
local Tree = require(script.Parent.Tree)

local Exterior = {}

-- ---------------------------------------------------------------------------------------
-- The plan
-- ---------------------------------------------------------------------------------------

local PLAN = {
	WidthStuds = 200, -- along X, the frontage
	DepthStuds = 120, -- along Z, front wall to back wall
	FloorHeightStuds = 20,
	Floors = 3,
	WallThicknessStuds = 2,

	-- The entrance bay: the whole centre of the front elevation, two storeys of it.
	EntranceBayStuds = 40,
	EntranceRecessStuds = 6, -- how far the doors sit back from the facade
	CurtainWidthStuds = 30,
	CurtainHeightStuds = 20,
	DoorWidthStuds = 16, -- the pair together
	DoorHeightStuds = 13,

	-- Classroom glazing. One window per bay, and the bay count is what makes the rhythm read
	-- as regular from outside -- see the note on windowedRun.
	WindowWidthStuds = 12,
	WindowHeightStuds = 10,
	BaysLongWall = 8, -- across the 200-stud back
	BaysShortWall = 5, -- along each 120-stud flank

	ParapetHeightStuds = 2,
	ParapetThicknessStuds = 1.5,
	PlinthHeightStuds = 3,
}

-- Dual tone. The pale field is the building; the dark is everything that marks an edge -- base
-- course, the band at each floor line, the parapet, the entrance reveals. Doing it that way
-- rather than as stripes means the darker colour is always describing a piece of structure,
-- which is what stops a two-colour building looking like a painted one.
local COOL_GRAY = Color3.fromRGB(196, 202, 210)
local DARK_SLATE = Color3.fromRGB(58, 64, 76)
local GLASS_TINT = Color3.fromRGB(198, 220, 236)
local DOOR_TIMBER = Color3.fromRGB(112, 78, 52)

local WALL_MATERIAL = Enum.Material.Concrete
local TRIM_MATERIAL = Enum.Material.SmoothPlastic

-- ---------------------------------------------------------------------------------------
-- Derived
-- ---------------------------------------------------------------------------------------

local W = PLAN.WidthStuds
local D = PLAN.DepthStuds
local FH = PLAN.FloorHeightStuds
local T = PLAN.WallThicknessStuds
local TOTAL_H = FH * PLAN.Floors

local HALF_W = W / 2
local HALF_D = D / 2

-- The height of a storey's floor level. Floor 1 stands on the ground the origin sits on.
local function floorY(floor: number): number
	return (floor - 1) * FH
end

-- Where the building's centre sits in the world.
--
-- Module-level rather than threaded through every helper, and set once at the top of Build.
-- The alternative was to lay the whole shell at the world origin and translate it afterwards,
-- which needs a staging folder and a second pass over every part -- and, more to the point,
-- needs `Instance.new("Folder")` and `FindFirstChild` to work, which is exactly what is not
-- available when this module is run headless to bake an asset.
local ORIGIN = Vector3.new(0, 0, 0)

-- Every coordinate below is written as a dimension of the building; this is the one place it
-- becomes a position in the map.
local function place(x: number, y: number, z: number): Vector3
	return Vector3.new(x + ORIGIN.X, y + ORIGIN.Y, z + ORIGIN.Z)
end

-- ---------------------------------------------------------------------------------------
-- Wall runs
-- ---------------------------------------------------------------------------------------

-- A straight run of wall divided into equal bays, each with a window in it.
--
-- **The bays are equal and the windows are centred in them.** That is the whole trick to an
-- elevation reading as a real building: eyes are extremely good at spotting an irregular
-- rhythm and very bad at measuring one, so evenly divided bays look deliberate at any spacing
-- while a single odd gap looks like a mistake from across the map.
--
-- `axis` is "x" for a run along the frontage or "z" for one along a flank; the two differ only
-- in which component the bays step along and whether the wall is turned a quarter turn.
local function windowedRun(
	parent: Instance,
	axis: string,
	fixed: number, -- the coordinate the wall sits at, on the other horizontal axis
	from: number,
	to: number,
	bays: number,
	y: number
)
	local span = to - from
	local bayWidth = span / bays
	local orientation = if axis == "x" then Vector3.new(0, 0, 0) else Vector3.new(0, 90, 0)

	for bay = 1, bays do
		local along = from + bayWidth * (bay - 0.5)
		local position = if axis == "x"
			then place(along, y + FH / 2, fixed)
			else place(fixed, y + FH / 2, along)

		Engine.CreateWindowCutout(
			position,
			Vector3.new(bayWidth, FH, T),
			Vector3.new(PLAN.WindowWidthStuds, PLAN.WindowHeightStuds, T),
			parent,
			orientation,
			WALL_MATERIAL,
			COOL_GRAY
		)
	end
end

-- ---------------------------------------------------------------------------------------
-- The entrance
-- ---------------------------------------------------------------------------------------

-- The grand front door: a two-storey bay cut out of the middle of the facade, with the doors
-- set back inside it and a glazed wall over them.
--
-- The recess is the part that makes it grand rather than merely large. A door flush with the
-- facade is a hole in a wall; a door six studs back has a soffit over it, a reveal down each
-- side, and a pool of shadow around it -- and those are what the eye reads as *entrance* from
-- the far side of a car park.
local function buildEntrance(parent: Instance)
	local bay = PLAN.EntranceBayStuds
	local recess = PLAN.EntranceRecessStuds
	local faceZ = -HALF_D
	local backZ = faceZ + recess

	-- The two reveals, running back from the facade to the door wall.
	for side = -1, 1, 2 do
		Engine.CreateWall(
			place(side * bay / 2, FH, faceZ + recess / 2),
			Vector3.new(T, FH * 2, recess),
			Vector3.new(0, 0, 0),
			TRIM_MATERIAL,
			DARK_SLATE,
			parent
		)
	end

	-- The soffit over the recess, at the head of storey two.
	Engine.CreateFloor(
		place(0, FH * 2, faceZ + recess / 2),
		Vector3.new(bay, T, recess),
		TRIM_MATERIAL,
		DARK_SLATE,
		parent
	)

	-- The door wall at the back of the recess, framed around the opening rather than cut --
	-- the same reason CreateWindowCutout frames rather than cuts.
	local doorW = PLAN.DoorWidthStuds
	local doorH = PLAN.DoorHeightStuds
	local pier = (bay - doorW) / 2
	for side = -1, 1, 2 do
		Engine.CreateWall(
			place(side * (doorW + pier) / 2, FH / 2, backZ),
			Vector3.new(pier, FH, T),
			Vector3.new(0, 0, 0),
			WALL_MATERIAL,
			COOL_GRAY,
			parent
		)
	end
	Engine.CreateWall(
		place(0, doorH + (FH - doorH) / 2, backZ),
		Vector3.new(doorW, FH - doorH, T),
		Vector3.new(0, 0, 0),
		WALL_MATERIAL,
		COOL_GRAY,
		parent
	)

	-- The doors themselves. Timber, and that is a deliberate break from the palette: in an
	-- elevation this pale, the one warm object is the way in, and it can be found from the road
	-- without a sign.
	for side = -1, 1, 2 do
		local leaf = Engine.CreateWall(
			place(side * doorW / 4, doorH / 2, backZ - 0.3),
			Vector3.new(doorW / 2 - 0.3, doorH, 0.8),
			Vector3.new(0, 0, 0),
			Enum.Material.WoodPlanks,
			DOOR_TIMBER,
			parent
		)
		leaf.Name = `EntranceDoorLeaf{side}`

		local bar = Engine.CreateWall(
			place(side * doorW / 4, doorH * 0.45, backZ - 0.85),
			Vector3.new(doorW / 2 - 4, 0.5, 0.5),
			Vector3.new(0, 0, 0),
			TRIM_MATERIAL,
			Color3.fromRGB(214, 218, 226),
			parent
		)
		bar.Name = `EntranceDoorBar{side}`
	end

	-- The curtain wall over the entrance, filling storey two of the bay.
	local curtainW = PLAN.CurtainWidthStuds
	local curtainH = PLAN.CurtainHeightStuds
	local curtain = Engine.CreateWall(
		place(0, floorY(2) + curtainH / 2, faceZ),
		Vector3.new(curtainW, curtainH, T * 0.5),
		Vector3.new(0, 0, 0),
		Enum.Material.Glass,
		GLASS_TINT,
		parent
	)
	curtain.Name = "EntranceCurtainWall"
	curtain.Transparency = 0.5
	curtain.Reflectance = 0.1

	-- Mullions. A 30-stud sheet of glass has nothing in it to measure the building against, so
	-- the eye reads it as one enormous window and the whole facade loses its size. Divided into
	-- door-width bays it is legibly two storeys tall, and not one dimension has changed.
	for index = 1, 4 do
		local mullion = Engine.CreateWall(
			place(-curtainW / 2 + curtainW * (index / 5), floorY(2) + curtainH / 2, faceZ - 0.3),
			Vector3.new(0.6, curtainH, 0.6),
			Vector3.new(0, 0, 0),
			TRIM_MATERIAL,
			DARK_SLATE,
			parent
		)
		mullion.Name = `EntranceMullion{index}`
	end
	Engine.CreateWall(
		place(0, floorY(2), faceZ - 0.3),
		Vector3.new(curtainW, 0.8, 0.8),
		Vector3.new(0, 0, 0),
		TRIM_MATERIAL,
		DARK_SLATE,
		parent
	).Name = "EntranceTransom"

	-- The bay is flanked full height by dark piers, so the composition has edges.
	for side = -1, 1, 2 do
		Engine.CreateWall(
			place(side * (bay / 2 + 1.5), TOTAL_H / 2, faceZ - 0.6),
			Vector3.new(3, TOTAL_H, 1.6),
			Vector3.new(0, 0, 0),
			TRIM_MATERIAL,
			DARK_SLATE,
			parent
		).Name = `EntrancePier{side}`
	end
end

-- ---------------------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------------------

-- Lays the shell. `origin` is where the building's centre sits in the world; everything above
-- is written relative to it, so moving the school is one argument rather than a search.
function Exterior.Build(origin: Vector3?, into: Instance?): Instance
	ORIGIN = origin or Vector3.new(0, 0, 0)

	-- `into` is taken as given when supplied, so the module can be run headless against a plain
	-- folder to bake an asset. Left out, it builds the folder tree and uses the Exterior branch.
	local staging: Instance
	if into ~= nil then
		staging = into
	else
		staging = Tree.Build().Exterior
	end

	-- ---- base course
	for _, run in {
		{ axis = "x", fixed = -HALF_D, from = -HALF_W, to = HALF_W },
		{ axis = "x", fixed = HALF_D, from = -HALF_W, to = HALF_W },
		{ axis = "z", fixed = -HALF_W, from = -HALF_D, to = HALF_D },
		{ axis = "z", fixed = HALF_W, from = -HALF_D, to = HALF_D },
	} do
		local span = run.to - run.from
		local mid = (run.from + run.to) / 2
		local position = if run.axis == "x"
			then place(mid, PLAN.PlinthHeightStuds / 2, run.fixed)
			else place(run.fixed, PLAN.PlinthHeightStuds / 2, mid)
		local size = if run.axis == "x"
			then Vector3.new(span + T, PLAN.PlinthHeightStuds, T + 1)
			else Vector3.new(T + 1, PLAN.PlinthHeightStuds, span + T)
		Engine.CreateWall(position, size, Vector3.new(0, 0, 0), TRIM_MATERIAL, DARK_SLATE, staging).Name = "Plinth"
	end

	for floor = 1, PLAN.Floors do
		local y = floorY(floor)

		-- ---- floor plate
		Engine.CreateFloor(
			place(0, y, 0),
			Vector3.new(W, T, D),
			TRIM_MATERIAL,
			COOL_GRAY,
			staging
		).Name = `FloorPlate{floor}`

		-- ---- the three windowed elevations
		windowedRun(staging, "z", -HALF_W, -HALF_D, HALF_D, PLAN.BaysShortWall, y)
		windowedRun(staging, "z", HALF_W, -HALF_D, HALF_D, PLAN.BaysShortWall, y)
		windowedRun(staging, "x", HALF_D, -HALF_W, HALF_W, PLAN.BaysLongWall, y)

		-- ---- the front, which has the entrance bay in the middle of it
		local bayHalf = PLAN.EntranceBayStuds / 2
		if floor == 3 then
			-- Above the entrance the frontage is continuous, so it takes the full rhythm.
			windowedRun(staging, "x", -HALF_D, -HALF_W, HALF_W, PLAN.BaysLongWall, y)
		else
			-- Either side of the bay, in proportion, so the windows stay the same size as
			-- everywhere else rather than being squeezed to fit what is left.
			local sideSpan = HALF_W - bayHalf
			local sideBays = math.max(1, math.round(PLAN.BaysLongWall * sideSpan / W))
			windowedRun(staging, "x", -HALF_D, -HALF_W, -bayHalf, sideBays, y)
			windowedRun(staging, "x", -HALF_D, bayHalf, HALF_W, sideBays, y)
			if floor == 1 then
				-- storey one of the bay is the recess, built below
			else
				-- storey two of the bay is the curtain wall, also below; nothing solid here
			end
		end

		-- ---- the floor band, in the dark tone, wrapped round all four sides
		if floor > 1 then
			for _, band in {
				{ position = place(0, y, -HALF_D - 0.4), size = Vector3.new(W + 2, 1.6, 1.2) },
				{ position = place(0, y, HALF_D + 0.4), size = Vector3.new(W + 2, 1.6, 1.2) },
				{ position = place(-HALF_W - 0.4, y, 0), size = Vector3.new(1.2, 1.6, D + 2) },
				{ position = place(HALF_W + 0.4, y, 0), size = Vector3.new(1.2, 1.6, D + 2) },
			} do
				Engine.CreateWall(band.position, band.size, Vector3.new(0, 0, 0), TRIM_MATERIAL, DARK_SLATE, staging).Name =
					`FloorBand{floor}`
			end
		end
	end

	buildEntrance(staging)

	-- ---- flat roof and its parapet
	Engine.CreateFloor(
		place(0, TOTAL_H, 0),
		Vector3.new(W, T, D),
		TRIM_MATERIAL,
		Color3.fromRGB(122, 128, 138),
		staging
	).Name = "Roof"

	local pt = PLAN.ParapetThicknessStuds
	local ph = PLAN.ParapetHeightStuds
	for _, wall in {
		{ position = place(0, TOTAL_H + ph / 2, -HALF_D + pt / 2), size = Vector3.new(W, ph, pt) },
		{ position = place(0, TOTAL_H + ph / 2, HALF_D - pt / 2), size = Vector3.new(W, ph, pt) },
		{ position = place(-HALF_W + pt / 2, TOTAL_H + ph / 2, 0), size = Vector3.new(pt, ph, D - pt * 2) },
		{ position = place(HALF_W - pt / 2, TOTAL_H + ph / 2, 0), size = Vector3.new(pt, ph, D - pt * 2) },
	} do
		Engine.CreateWall(wall.position, wall.size, Vector3.new(0, 0, 0), TRIM_MATERIAL, DARK_SLATE, staging).Name = "Parapet"
	end

	return staging
end

Exterior.Plan = PLAN

return Exterior
