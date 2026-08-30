--!strict
-- The exterior shell of the new school: three storeys, flat roof, glazed entrance bay.
--
-- **Everything here is derived from PLAN.** Not one coordinate below is written down twice, and
-- none is a literal that means something. That is not tidiness for its own sake -- the last
-- school was rebuilt six times because a number like "the corridor is at z 53" was true in one
-- function and false in another after a change, and every one of those bugs was invisible until
-- somebody walked into it. If a dimension moves here, everything that depends on it moves.

local Engine = require(script.Parent.SchoolBuilderEngine)
local Layout = require(script.Parent.Layout)
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
	-- Two, not three. The base course wraps the wall rather than standing in front of it, so it
	-- and the ground-floor sill band share the same studs -- at three it swallowed two thirds of
	-- that sill. A base course is meant to be read as the bottom edge of the wall, not as the
	-- bottom storey of it.
	PlinthHeightStuds = 2,
}

-- **School v1's palette, because v1's exterior worked and this one did not.**
--
-- Cool gray and dark slate is a perfectly good scheme and it made a dull building, for a
-- reason worth writing down: grey on grey has no figure. The eye needs one colour doing the
-- describing, and the pale field has to be near-white for the accent to read as an accent
-- rather than as the other half of a two-tone stripe.
--
-- So: white walls, and the school's blue on everything that marks a piece of structure -- base
-- course, the band at every floor line, the parapet, the entrance frame. The blue is never
-- decoration; it is always showing you where a floor is.
local WHITE = Color3.fromRGB(242, 243, 246)
local OFF_WHITE = Color3.fromRGB(228, 230, 235)
local BLUE = Color3.fromRGB(58, 122, 206)
local DEEP_BLUE = Color3.fromRGB(36, 84, 158)
local GLASS_TINT = Color3.fromRGB(196, 220, 240)
local DOOR_TIMBER = Color3.fromRGB(112, 78, 52)

-- Kept under their old names so the rest of the file did not need rewriting to change colour.
local COOL_GRAY = WHITE
local DARK_SLATE = BLUE

local WALL_MATERIAL = Enum.Material.SmoothPlastic
local TRIM_MATERIAL = Enum.Material.SmoothPlastic

-- How much of a storey is glass, and how far apart the uprights that divide it go. Both lifted
-- from v1: 18 studs is about a door and a half, which is the spacing at which a glazed wall
-- stops reading as one enormous window and starts reading as a building with floors in it.
local GLASS_SHARE = 0.55
local MULLION_SPACING = 18

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

-- A storey's worth of ribbon glazing along one elevation.
--
-- **This replaces punched windows, and that single change is most of what made the old facade
-- dull.** Separate 12x10 holes in a wall read as a warehouse: the wall is the subject and the
-- windows are absences in it. A continuous band -- sill, glass, head, repeated at every floor
-- -- makes the *glazing* the subject and the solid parts into structure between it. It is the
-- difference between a shed with windows and a building.
--
-- Four parts plus a mullion every 18 studs, against five parts per window before, so it is
-- cheaper as well.
--
-- `axis` is "x" for a run along the frontage or "z" for one along a flank.
local function ribbonRun(parent: Instance, axis: string, fixed: number, from: number, to: number, y: number)
	local span = to - from
	if span <= 0.05 then
		return
	end
	local mid = (from + to) / 2
	local glassH = FH * GLASS_SHARE
	local bandH = (FH - glassH) / 2

	local function slab(name: string, cy: number, h: number, thickness: number, colour: Color3, material: Enum.Material): Part
		local position = if axis == "x" then place(mid, cy, fixed) else place(fixed, cy, mid)
		local size = if axis == "x" then Vector3.new(span, h, thickness) else Vector3.new(thickness, h, span)
		return Engine.CreateWall(position, size, Vector3.new(0, 0, 0), material, colour, parent)
	end

	slab("RibbonSill", y + bandH / 2, bandH, T, WHITE, WALL_MATERIAL).Name = "RibbonSill"
	local pane = slab("RibbonGlass", y + bandH + glassH / 2, glassH, T * 0.5, GLASS_TINT, Enum.Material.Glass)
	pane.Name = "RibbonGlass"
	pane.Transparency = 0.5
	pane.Reflectance = 0.12
	slab("RibbonHead", y + bandH + glassH + bandH / 2, bandH, T, OFF_WHITE, WALL_MATERIAL).Name = "RibbonHead"

	-- The uprights. Without them a fifty-stud pane has nothing in it to measure the building
	-- against, and the whole elevation loses its scale -- which is exactly why the old school
	-- looked like a toy next to a town of small houses.
	if span > MULLION_SPACING then
		local bays = math.max(1, math.floor(span / MULLION_SPACING + 0.5))
		for bay = 1, bays - 1 do
			local along = from + span * (bay / bays)
			local position = if axis == "x"
				then place(along, y + bandH + glassH / 2, fixed - 0.4)
				else place(fixed - 0.4, y + bandH + glassH / 2, along)
			local size = if axis == "x" then Vector3.new(0.8, glassH, T) else Vector3.new(T, glassH, 0.8)
			Engine.CreateWall(position, size, Vector3.new(0, 0, 0), TRIM_MATERIAL, WHITE, parent).Name = "Mullion"
		end
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
		place(0, FH * 2 - 2, faceZ + recess / 2),
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
			place(-curtainW / 2 + curtainW * (index / 5), floorY(2) + curtainH / 2, faceZ - 1.1),
			Vector3.new(0.6, curtainH, 0.6),
			Vector3.new(0, 0, 0),
			TRIM_MATERIAL,
			DARK_SLATE,
			parent
		)
		mullion.Name = `EntranceMullion{index}`
	end
	Engine.CreateWall(
		place(0, floorY(2), faceZ - 1.1),
		Vector3.new(curtainW, 0.8, 0.8),
		Vector3.new(0, 0, 0),
		TRIM_MATERIAL,
		DARK_SLATE,
		parent
	).Name = "EntranceTransom"

	-- **A canopy over the way in.**
	--
	-- The thing v1's frontage had that this one did not. A recess alone gives you shadow; a
	-- canopy gives you a horizontal line crossing the glazing at one storey, which is what
	-- makes an entrance the biggest thing on an elevation rather than a gap in it. Set well
	-- clear of the door head -- the mistake on v1 was a canopy at 14 over a 17-stud door, which
	-- hid the thing it was sheltering.
	local canopyY = PLAN.DoorHeightStuds + 6
	local canopyOut = 12
	Engine.CreateFloor(
		place(0, canopyY, faceZ - canopyOut / 2),
		Vector3.new(bay + 22, 1.4, canopyOut),
		TRIM_MATERIAL,
		WHITE,
		parent
	).Name = "EntranceCanopy"
	Engine.CreateWall(
		place(0, canopyY - 1.2, faceZ - canopyOut / 2),
		Vector3.new(bay + 22, 1, canopyOut - 1),
		Vector3.new(0, 0, 0),
		TRIM_MATERIAL,
		BLUE,
		parent
	).Name = "EntranceCanopyBand"
	-- Two columns carrying its outer edge, clear of the doorway between them.
	for side = -1, 1, 2 do
		Engine.CreateWall(
			place(side * (bay / 2 + 6), canopyY / 2, faceZ - canopyOut + 1.5),
			Vector3.new(2.4, canopyY, 2.4),
			Vector3.new(0, 0, 0),
			TRIM_MATERIAL,
			WHITE,
			parent
		).Name = `EntranceColumn{side}`
	end

	-- The bay is flanked full height by piers, so the composition has edges.
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

		-- ---- floor plate, with the stairwells cut out of every level above the ground
		--
		-- **The openings come from Layout, the same table Interior builds the shaft walls
		-- from.** That is the whole reason Layout exists: on the last school the corridor and
		-- the hole in the floor above it were computed independently, disagreed by three studs,
		-- and produced a corridor with no floor under it that nothing detected.
		--
		-- Ground floor is solid -- there is nothing under it to fall into.
		-- **The plate hangs below its level, so `floorY(n)` is the surface you stand on.**
		--
		-- Centred *on* the level instead, its top surface sits half a thickness higher than the
		-- number every other module works from -- so every interior wall is built a stud low and
		-- anything short, like a locker plinth, ends up buried in the slab. Found exactly that
		-- way: 44 plinths inside FloorPlate2Corridor.
		if floor == 1 then
			Engine.CreateFloor(place(0, y - T / 2, 0), Vector3.new(W, T, D), TRIM_MATERIAL, COOL_GRAY, staging).Name =
				`FloorPlate{floor}`
		else
			-- Laid as strips around the shafts. Roblox cannot put a hole in a Part, so a floor
			-- with a void in it is a ring of slabs -- the same constraint the window frames work
			-- around, one storey up.
			local westX = Layout.Stairwells[1].x2
			local eastX = Layout.Stairwells[2].x1
			local wellZ1, wellZ2 = Layout.CorridorZ1, Layout.CorridorZ2

			-- In front of and behind the shafts, full width.
			Engine.CreateFloor(
				place(0, y - T / 2, (-HALF_D + wellZ1) / 2),
				Vector3.new(W, T, wellZ1 + HALF_D),
				TRIM_MATERIAL,
				COOL_GRAY,
				staging
			).Name = `FloorPlate{floor}Front`
			Engine.CreateFloor(
				place(0, y - T / 2, (wellZ2 + HALF_D) / 2),
				Vector3.new(W, T, HALF_D - wellZ2),
				TRIM_MATERIAL,
				COOL_GRAY,
				staging
			).Name = `FloorPlate{floor}Back`
			-- And the corridor band between them, which is where the two holes are.
			Engine.CreateFloor(
				place((westX + eastX) / 2, y - T / 2, 0),
				Vector3.new(eastX - westX, T, wellZ2 - wellZ1),
				TRIM_MATERIAL,
				COOL_GRAY,
				staging
			).Name = `FloorPlate{floor}Corridor`
		end

		-- ---- the three windowed elevations
		ribbonRun(staging, "z", -HALF_W, -HALF_D, HALF_D, y)
		ribbonRun(staging, "z", HALF_W, -HALF_D, HALF_D, y)
		ribbonRun(staging, "x", HALF_D, -HALF_W, HALF_W, y)

		-- ---- the front, which has the entrance bay in the middle of it
		local bayHalf = PLAN.EntranceBayStuds / 2
		if floor == 3 then
			-- Above the entrance the frontage is continuous, so it takes the full rhythm.
			ribbonRun(staging, "x", -HALF_D, -HALF_W, HALF_W, y)
		else
			-- Either side of the entrance bay. A ribbon needs no bay arithmetic -- it simply runs
			-- the length it is given and puts a mullion every 18 studs, so the rhythm matches
			-- the rest of the building without being told to.
			ribbonRun(staging, "x", -HALF_D, -HALF_W, -bayHalf, y)
			ribbonRun(staging, "x", -HALF_D, bayHalf, HALF_W, y)
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
		place(0, TOTAL_H - T / 2, 0),
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
		Engine.CreateWall(wall.position, wall.size, Vector3.new(0, 0, 0), TRIM_MATERIAL, DEEP_BLUE, staging).Name = "Parapet"
	end

	return staging
end

Exterior.Plan = PLAN

return Exterior
