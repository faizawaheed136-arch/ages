--!strict
-- The academy plan, as data. **Open-arms scheme.**
--
-- This replaced a closed ring of rooms around an enclosed void. That was the plan of a barracks:
-- it turns its back on the world and looks inward at nothing, and no amount of glass would have
-- fixed it, because the fault was in the diagram rather than the cladding.
--
-- What is here instead: two wings reaching forward, a garden held between them and **open to the
-- approach**, and a glass atrium at the head of it. The garden's fourth side is missing on
-- purpose -- that one absence is the whole difference between a courtyard and a forecourt.
--
-- Nothing here draws anything. Shell.luau reads it and lays parts; tools/check_showcase.py reads
-- the same numbers and proves they add up. Keeping the plan separate from the builder is what
-- makes it checkable at all, and it has already earned that twice.

local Plan = {}

-- ---------------------------------------------------------------------------------------
-- The bands, west to east
-- ---------------------------------------------------------------------------------------

Plan.WallStuds = 4
-- A teaching room 76 deep. Same as the old scheme -- it was the one dimension that was right.
Plan.BandStuds = 76
-- 28, up from 24. Camera clearance on a turn (see section 05) plus a glazed wall you are meant
-- to stop and look out of, which 24 does not leave room for.
Plan.GalleryStuds = 28
-- The structural zone between the gallery and the void: mullions, columns, the slab edge.
Plan.EdgeStuds = 12
-- Square in plan, and nearly a third as tall. Below about 120 across, a full-height void stops
-- reading as a room and starts reading as a shaft.
Plan.AtriumStuds = 160

-- 4 + 76 + 28 + 12 + 160 + 12 + 28 + 76 + 4 = 400
Plan.WidthStuds = Plan.WallStuds * 2
	+ Plan.BandStuds * 2
	+ Plan.GalleryStuds * 2
	+ Plan.EdgeStuds * 2
	+ Plan.AtriumStuds

-- ---------------------------------------------------------------------------------------
-- The bands, south to north
-- ---------------------------------------------------------------------------------------

-- The garden, held between the wings and open on the south. The wings run past it on both
-- sides, which is what makes it a forecourt rather than a yard.
Plan.GardenStuds = 140
-- Back of house behind the atrium: plant, deliveries, the things a showcase does not show.
Plan.BackStuds = 40

-- 140 + 160 + 40 = 340
Plan.DepthStuds = Plan.GardenStuds + Plan.AtriumStuds + Plan.BackStuds

-- ---------------------------------------------------------------------------------------
-- Heights
-- ---------------------------------------------------------------------------------------

-- 22 on the ground, because this is the grand floor -- lobby, cafeteria, gym -- and 22 is about
-- where a room stops feeling domestic. 18 above, lower on purpose so the hierarchy reads.
--
-- Both are far above the number that actually matters: a jumping avatar's head crown reaches
-- 12.2 studs, and anything under about 14 means clipping your head on every jump.
Plan.GroundClearStuds = 22
Plan.UpperClearStuds = 18
Plan.SlabStuds = 4

Plan.GroundStoreyStuds = Plan.GroundClearStuds + Plan.SlabStuds -- 26
Plan.UpperStoreyStuds = Plan.UpperClearStuds + Plan.SlabStuds -- 22
Plan.RoofStuds = Plan.GroundStoreyStuds + Plan.UpperStoreyStuds -- 48
-- The glazed lantern sits above the parapet, so daylight enters *over* the roofline rather than
-- through it. That is what puts sun on the atrium floor at section 01's 7.4 clock instead of
-- only on the top of the stair.
Plan.LanternStuds = 4

-- The gym is one volume through both storeys.
Plan.GymClearStuds = Plan.RoofStuds - Plan.SlabStuds -- 44

-- ---------------------------------------------------------------------------------------
-- Edges
-- ---------------------------------------------------------------------------------------

local function run(start: number, ...: number): { number }
	local edges = { start }
	local at = start
	for _, width in { ... } do
		at += width
		table.insert(edges, at)
	end
	return edges
end

-- wall, rooms, gallery, edge, ATRIUM, edge, gallery, rooms, wall
Plan.X = run(0, Plan.WallStuds, Plan.BandStuds, Plan.GalleryStuds, Plan.EdgeStuds,
	Plan.AtriumStuds, Plan.EdgeStuds, Plan.GalleryStuds, Plan.BandStuds, Plan.WallStuds)

-- garden, atrium, back
Plan.Z = run(0, Plan.GardenStuds, Plan.AtriumStuds, Plan.BackStuds)

-- Index 1 is the outside face; index n+1 is the far side of band n.
Plan.Edge = {
	Outer = 1, -- 0
	WallInner = 2, -- 4    inside face of the wall / start of the rooms
	RoomInner = 3, -- 80   end of the rooms / start of the gallery
	GalleryInner = 4, -- 108  end of the gallery / start of the structural edge
	VoidNear = 5, -- 120  the atrium and garden begin
	VoidFar = 6, -- 280  they end
	EdgeFar = 7, -- 292
	GalleryFar = 8, -- 320
	RoomFar = 9, -- 396
	OuterFar = 10, -- 400
}

Plan.ZEdge = {
	Front = 1, -- 0    the open south approach
	GardenBack = 2, -- 140  the garden ends, the atrium begins
	AtriumBack = 3, -- 300  the atrium ends
	Back = 4, -- 340
}

-- ---------------------------------------------------------------------------------------
-- Named volumes
-- ---------------------------------------------------------------------------------------

export type Rect = {
	Id: string,
	Label: string,
	Floor: number,
	X1: number,
	Z1: number,
	X2: number,
	Z2: number,
}

local function rect(id: string, label: string, floor: number, x1: number, z1: number, x2: number, z2: number): Rect
	return { Id = id, Label = label, Floor = floor, X1 = x1, Z1 = z1, X2 = x2, Z2 = z2 }
end

-- The garden: open to the south, wings either side, atrium at its head.
function Plan.Garden(): Rect
	local X, Z, E, ZE = Plan.X, Plan.Z, Plan.Edge, Plan.ZEdge
	return rect("garden", "Garden Courtyard", 0, X[E.VoidNear], Z[ZE.Front], X[E.VoidFar], Z[ZE.GardenBack])
end

function Plan.Atrium(): Rect
	local X, Z, E, ZE = Plan.X, Plan.Z, Plan.Edge, Plan.ZEdge
	return rect("atrium", "Glass Atrium", 1, X[E.VoidNear], Z[ZE.GardenBack], X[E.VoidFar], Z[ZE.AtriumBack])
end

-- East wing, front half. One volume through both storeys.
function Plan.Gym(): Rect
	local X, Z, E, ZE = Plan.X, Plan.Z, Plan.Edge, Plan.ZEdge
	return rect("gym", "Gymnasium", 1, X[E.GalleryFar], Z[ZE.Front] + 8, X[E.RoomFar], Z[ZE.GardenBack])
end

-- West wing, front half, mirrored.
function Plan.Cafeteria(): Rect
	local X, Z, E, ZE = Plan.X, Plan.Z, Plan.Edge, Plan.ZEdge
	return rect("cafeteria", "Cafeteria", 1, X[E.WallInner], Z[ZE.Front] + 8, X[E.GalleryInner], Z[ZE.GardenBack])
end

-- The timber patio the cafeteria spills onto, outside the west wall. Three 2-stud steps down,
-- which is exactly what a humanoid walks without jumping.
function Plan.Patio(): Rect
	local Z, ZE = Plan.Z, Plan.ZEdge
	return rect("patio", "Patio Deck", 1, -70, Z[ZE.Front] + 20, 0, Z[ZE.Front] + 120)
end

Plan.PatioDropStuds = 6

-- **The learning stair.** Forty wide, rising the full floor-to-floor height out of the atrium
-- floor, with every fourth tread run deep enough to sit on.
--
-- Note the rise is *floor to floor*, 26, not the 22 of clear height -- a stair climbs the slab
-- as well as the room. Getting that wrong is a stair that arrives 4 studs under its landing.
Plan.StairWidthStuds = 40
Plan.StairTreads = 20
Plan.StairRiserStuds = Plan.GroundStoreyStuds / Plan.StairTreads -- 1.3
Plan.StairGoingStuds = 3.5
-- A seat needs depth for thighs. 3.5 is a ledge; 7 is a bench.
Plan.StairTierGoingStuds = 7
Plan.StairTierEvery = 4

function Plan.StairRunStuds(): number
	local run = 0
	for tread = 1, Plan.StairTreads do
		run += if tread % Plan.StairTierEvery == 0 then Plan.StairTierGoingStuds else Plan.StairGoingStuds
	end
	return run
end

-- Two aerial bridges across the atrium at level 2, wing to wing.
Plan.BridgeWidthStuds = 14
function Plan.Bridges(): { Rect }
	local X, Z, E, ZE = Plan.X, Plan.Z, Plan.Edge, Plan.ZEdge
	local out = {}
	local atriumZ1, atriumZ2 = Z[ZE.GardenBack], Z[ZE.AtriumBack]
	for index, share in { 0.34, 0.68 } do
		local centre = atriumZ1 + (atriumZ2 - atriumZ1) * share
		table.insert(out, rect(
			`bridge{index}`, "Bridge", 2,
			X[E.GalleryInner], centre - Plan.BridgeWidthStuds / 2,
			X[E.EdgeFar], centre + Plan.BridgeWidthStuds / 2
		))
	end
	return out
end

-- ---------------------------------------------------------------------------------------
-- Rooms
-- ---------------------------------------------------------------------------------------

local function bays(from: number, to: number, count: number): { { number } }
	local out = {}
	local span = (to - from) / count
	for index = 1, count do
		table.insert(out, { from + span * (index - 1), from + span * index })
	end
	return out
end

function Plan.Rooms(): { Rect }
	local X, Z, E, ZE = Plan.X, Plan.Z, Plan.Edge, Plan.ZEdge
	local rooms: { Rect } = {}

	-- Back halves of both wings, ground floor: the service rooms behind the big volumes.
	local backBays = bays(Z[ZE.GardenBack] + 10, Z[ZE.AtriumBack], 3)
	local westBack = { "Kitchen", "Store", "Washrooms" }
	local eastBack = { "Changing", "Equipment", "Washrooms" }
	for index, bay in backBays do
		table.insert(rooms, rect(`w1_{index}`, westBack[index], 1, X[E.WallInner], bay[1], X[E.RoomInner], bay[2]))
		table.insert(rooms, rect(`e1_{index}`, eastBack[index], 1, X[E.GalleryFar], bay[1], X[E.RoomFar], bay[2]))
	end

	-- Level 2, west wing: the art studio takes the front, where the roof can be opened up.
	local westUpper = bays(Z[ZE.Front] + 8, Z[ZE.AtriumBack], 4)
	for index, label in { "Art Studio", "Math", "Classroom", "Classroom" } do
		local bay = westUpper[index]
		table.insert(rooms, rect(`w2_{index}`, label, 2, X[E.WallInner], bay[1], X[E.RoomInner], bay[2]))
	end

	-- Level 2, east wing: the gym void takes the front half, so rooms start behind it.
	local eastUpper = bays(Z[ZE.GardenBack] + 10, Z[ZE.AtriumBack], 2)
	for index, label in { "Science Lab", "Classroom" } do
		local bay = eastUpper[index]
		table.insert(rooms, rect(`e2_{index}`, label, 2, X[E.GalleryFar], bay[1], X[E.RoomFar], bay[2]))
	end

	-- Behind the atrium, both levels.
	for floor = 1, 2 do
		table.insert(rooms, rect(`c{floor}_1`, if floor == 1 then "Admin" else "Staff Room", floor,
			X[E.VoidNear], Z[ZE.AtriumBack], X[E.VoidFar], Z[ZE.Back]))
	end

	return rooms
end

-- The reception, in the atrium's south edge, facing whoever comes up the garden.
function Plan.Reception(): Rect
	local X, Z, E, ZE = Plan.X, Plan.Z, Plan.Edge, Plan.ZEdge
	local centre = (X[E.VoidNear] + X[E.VoidFar]) / 2
	return rect("reception", "Reception", 1, centre - 50, Z[ZE.GardenBack] + 6, centre + 50, Z[ZE.GardenBack] + 24)
end

-- ---------------------------------------------------------------------------------------
-- Curtain walling
-- ---------------------------------------------------------------------------------------

-- 8-stud bays. Fifteen across a 120-stud wing: wider reads as a shopfront, narrower and the
-- mullions eat the view. Vertical mullions only -- horizontal transoms at every storey are what
-- make Roblox glass look like graph paper.
Plan.GlassBayStuds = 8
Plan.MullionStuds = 0.5
Plan.GlassTransparency = 0.55
Plan.GlassReflectance = 0.1

return Plan
