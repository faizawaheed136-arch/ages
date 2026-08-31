--!strict
-- The block-out. Grey boxes at true scale, and nothing else.
--
-- This is step 1 of the build order in section 02, deliberately: every part is Concrete in one
-- colour, there is no trim, no material variation and no furniture. The only question a
-- block-out answers is whether the building is the right *size*, and detail added before that
-- is answered is detail you throw away.
--
-- It reads Plan.luau and lays what the plan says. Nothing here decides a dimension.

local Plan = require(script.Parent.Plan)
local Kit = require(script.Parent.Kit)

local Shell = {}

-- Re-exported so the starter can centre the building without requiring Plan as well.
Shell.Width = Plan.WidthStuds
Shell.Depth = Plan.DepthStuds

local GREY = Color3.fromRGB(108, 108, 102)
local DARK = Color3.fromRGB(78, 78, 73)
local FLOOR = Color3.fromRGB(88, 86, 82)

-- Openings, from section 05. A block-out with solid walls tells you nothing about circulation,
-- so the gaps go in from the start.
local DOOR_W = 12
local DOOR_H = 14
local ARCH_W = 20

local built = false

-- ---------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------

-- A wall run with holes in it. `gaps` is a list of {from, to} along the run's own axis; the run
-- is emitted as the segments between them.
--
-- Doing it this way rather than laying a solid wall and then "cutting" holes matters, because
-- Roblox has no CSG at this level -- a hole is a wall you did not build.
local function wallRun(
	parent: Instance,
	name: string,
	axis: string,
	fixed: number,
	from: number,
	to: number,
	y: number,
	height: number,
	thickness: number,
	gaps: { { number } },
	toWorld: (number, number, number) -> Vector3
)
	table.sort(gaps, function(a, b)
		return a[1] < b[1]
	end)

	local cursor = from
	local index = 0
	local function segment(a: number, b: number, h: number, base: number)
		if b - a < 0.05 then
			return
		end
		index += 1
		local centre = (a + b) / 2
		local size = if axis == "x" then Vector3.new(b - a, h, thickness) else Vector3.new(thickness, h, b - a)
		local position = if axis == "x" then toWorld(centre, base + h / 2, fixed) else toWorld(fixed, base + h / 2, centre)
		Kit.Block(parent, `{name}{index}`, position, size, GREY)
	end

	for _, gap in gaps do
		segment(cursor, gap[1], height, y)
		-- The lintel over the opening. Without it the doorway runs to the ceiling and every
		-- room reads as an alcove rather than a room you enter.
		local head = math.min(gap[3] or DOOR_H, height)
		if height - head > 0.05 then
			index += 1
			local centre = (gap[1] + gap[2]) / 2
			local span = gap[2] - gap[1]
			local size = if axis == "x"
				then Vector3.new(span, height - head, thickness)
				else Vector3.new(thickness, height - head, span)
			local position = if axis == "x"
				then toWorld(centre, y + head + (height - head) / 2, fixed)
				else toWorld(fixed, y + head + (height - head) / 2, centre)
			Kit.Block(parent, `{name}Head{index}`, position, size, GREY)
		end
		cursor = gap[2]
	end
	segment(cursor, to, height, y)
end

local function slab(parent: Instance, name: string, x1: number, z1: number, x2: number, z2: number, y: number, toWorld: (number, number, number) -> Vector3)
	if x2 - x1 < 0.05 or z2 - z1 < 0.05 then
		return
	end
	Kit.Block(
		parent,
		name,
		toWorld((x1 + x2) / 2, y + Plan.SlabStuds / 2, (z1 + z2) / 2),
		Vector3.new(x2 - x1, Plan.SlabStuds, z2 - z1),
		FLOOR
	)
end

-- ---------------------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------------------

function Shell.Build(origin: Vector3): Folder?
	if built then
		return workspace:FindFirstChild("Showcase") :: Folder?
	end
	built = true

	local folder = Instance.new("Folder")
	folder.Name = "Showcase"
	folder.Parent = workspace

	-- Local coordinates run 0..Width and 0..Depth, so the plan reads as a plan. `at` is the only
	-- place the world position is added, which is what lets the whole building be moved by
	-- changing one argument.
	local function at(x: number, y: number, z: number): Vector3
		return origin + Vector3.new(x, y, z)
	end

	local X, Z, E = Plan.X, Plan.Z, Plan.Edge
	local W, D = Plan.WidthStuds, Plan.DepthStuds
	local courtX1, courtX2 = X[E.CourtNear], X[E.CourtFar]
	local courtZ1, courtZ2 = Z[E.CourtNear], Z[E.CourtFar]
	local gym = Plan.Gym()

	-- ---- ground, with an apron so the building is not standing on a cliff edge
	Kit.Block(folder, "Ground", at(W / 2, -1, D / 2), Vector3.new(W + 160, 2, D + 160), DARK)

	-- ---- courtyard floor, one storey of it and open to the sky above
	slab(folder, "CourtyardGround", courtX1, courtZ1, courtX2, courtZ2, -Plan.SlabStuds, at)

	for floor = 1, Plan.Floors do
		local base = (floor - 1) * Plan.StoreyStuds
		local level = Instance.new("Folder")
		level.Name = `Level{floor}`
		level.Parent = folder

		-- ---- slab, as a frame around the courtyard void
		slab(level, "SlabSouth", 0, 0, W, courtZ1, base, at)
		slab(level, "SlabWest", 0, courtZ1, courtX1, courtZ2, base, at)
		slab(level, "SlabEast", courtX2, courtZ1, W, courtZ2, base, at)
		if floor == 2 then
			-- The sparring hall is one 40-stud volume over floors 1 and 2, so level 2's slab
			-- stops at the hall and picks up again either side of it. This gap is the gallery's
			-- reason to exist.
			slab(level, "SlabNorthInner", 0, courtZ2, W, gym.Z1, base, at)
			slab(level, "SlabNorthWest", 0, gym.Z1, gym.X1, D, base, at)
			slab(level, "SlabNorthEast", gym.X2, gym.Z1, W, D, base, at)
		else
			slab(level, "SlabNorth", 0, courtZ2, W, D, base, at)
		end

		-- ---- outer walls
		local h = Plan.ClearStuds
		local y = base + Plan.SlabStuds
		-- The entrance: one 20-wide opening on the south face, on the courtyard's axis, ground
		-- floor only. Section 04's whole approach depends on it lining up with the corridor.
		local southGaps = if floor == 1 then { { W / 2 - ARCH_W / 2, W / 2 + ARCH_W / 2, DOOR_H + 4 } } else {}
		-- The two x-runs take the full width and the two z-runs stop short of them, so the
		-- corners butt instead of overlapping. Four coincident corner blocks is the same defect
		-- the coplanar check caught in ProperSchool's plinth -- solid geometry sharing a face is
		-- z-fighting waiting for a camera angle.
		--
		-- The `fixed` argument is a coordinate on the *other* axis: a z for an x-run. This read
		-- X[E.Outer] for the south wall, which is 0 and therefore right by accident -- it would
		-- have gone wrong the first time the plan grew an offset.
		local nearFace = Plan.WallStuds / 2
		wallRun(level, `WallSouth{floor}_`, "x", Z[E.Outer] + nearFace, 0, W, y, h, Plan.WallStuds, southGaps, at)
		wallRun(level, `WallNorth{floor}_`, "x", Z[E.OuterFar] - nearFace, 0, W, y, h, Plan.WallStuds, {}, at)
		wallRun(level, `WallWest{floor}_`, "z", X[E.Outer] + nearFace, Plan.WallStuds, D - Plan.WallStuds, y, h, Plan.WallStuds, {}, at)
		wallRun(level, `WallEast{floor}_`, "z", X[E.OuterFar] - nearFace, Plan.WallStuds, D - Plan.WallStuds, y, h, Plan.WallStuds, {}, at)

		-- ---- the wall between the room bands and the corridor, with a door per bay
		local rooms = Plan.Rooms()
		local southDoors, westDoors, eastDoors = {}, {}, {}
		for _, room in rooms do
			if room.Floor ~= floor then
				continue
			end
			if room.Z2 == Z[E.BandInner] then
				local centre = (room.X1 + room.X2) / 2
				table.insert(southDoors, { centre - DOOR_W / 2, centre + DOOR_W / 2, DOOR_H })
			elseif room.X2 == X[E.BandInner] then
				local centre = (room.Z1 + room.Z2) / 2
				table.insert(westDoors, { centre - DOOR_W / 2, centre + DOOR_W / 2, DOOR_H })
			elseif room.X1 == X[E.CorridorFar] then
				local centre = (room.Z1 + room.Z2) / 2
				table.insert(eastDoors, { centre - DOOR_W / 2, centre + DOOR_W / 2, DOOR_H })
			end
		end
		wallRun(level, `BandSouth{floor}_`, "x", Z[E.BandInner], 0, W, y, h, 2, southDoors, at)
		wallRun(level, `BandWest{floor}_`, "z", X[E.BandInner], Z[E.BandInner], Z[E.CorridorFar], y, h, 2, westDoors, at)
		wallRun(level, `BandEast{floor}_`, "z", X[E.CorridorFar], Z[E.BandInner], Z[E.CorridorFar], y, h, 2, eastDoors, at)

		-- ---- room dividers between bays
		for _, room in rooms do
			if room.Floor == floor and room.Z2 == Z[E.BandInner] then
				Kit.Block(level, `Divider{room.Id}`, at(room.X2, y + h / 2, (room.Z1 + room.Z2) / 2), Vector3.new(2, h, room.Z2 - room.Z1), GREY)
			end
		end

		-- ---- the arcade: columns, not a wall, so the courtyard reads as one space
		for step = 0, 6 do
			local t = step / 6
			for _, spot in {
				{ courtX1 + (courtX2 - courtX1) * t, courtZ1 - Plan.ArcadeStuds / 2 },
				{ courtX1 + (courtX2 - courtX1) * t, courtZ2 + Plan.ArcadeStuds / 2 },
				{ courtX1 - Plan.ArcadeStuds / 2, courtZ1 + (courtZ2 - courtZ1) * t },
				{ courtX2 + Plan.ArcadeStuds / 2, courtZ1 + (courtZ2 - courtZ1) * t },
			} do
				Kit.Block(level, `Column{floor}_{step}`, at(spot[1], y + h / 2, spot[2]), Vector3.new(4, h, 4), DARK)
			end
		end
	end

	-- ---- the sparring hall: no intermediate slab, so it is one 40-stud volume
	Kit.Block(
		folder,
		"GymFloor",
		at((gym.X1 + gym.X2) / 2, Plan.SlabStuds / 2, (gym.Z1 + gym.Z2) / 2),
		Vector3.new(gym.X2 - gym.X1, Plan.SlabStuds, gym.Z2 - gym.Z1),
		DARK
	)

	-- ---- stairs
	for _, core in Plan.Stairs() do
		for floor = 1, Plan.Floors - 1 do
			local base = (floor - 1) * Plan.StoreyStuds + Plan.SlabStuds
			local x = (core.X1 + core.X2) / 2
			for tread = 1, Plan.StairTreads do
				local rise = tread * Plan.StairRiserStuds
				local z = core.Z1 + 6 + (tread - 0.5) * Plan.StairGoingStuds
				Kit.Block(
					folder,
					`{core.Id}F{floor}Step{tread}`,
					at(x, base + rise - Plan.StairRiserStuds / 2, z),
					Vector3.new(Plan.StairWidthStuds, Plan.StairRiserStuds, Plan.StairGoingStuds),
					GREY
				)
			end
		end
	end

	return folder
end

return Shell
