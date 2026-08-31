--!strict
-- The academy plan, as data.
--
-- Nothing here draws anything. Shell.luau reads this and lays parts; tools/check_showcase.py
-- reads the same numbers and proves they add up. Keeping the plan separate from the builder is
-- what makes it checkable at all -- a plan expressed only as calls to Kit.Block can be verified
-- by walking around in it and no other way.
--
-- **Every dimension is derived from the band widths, not written down twice.** WidthStuds is
-- the sum of the bands across, DepthStuds the sum along. Change CorridorStuds and the footprint
-- follows. The alternative -- a footprint constant *and* band constants -- is two sources of
-- truth that agree until the day somebody edits one of them.

local Plan = {}

-- ---------------------------------------------------------------------------------------
-- The bands
-- ---------------------------------------------------------------------------------------

Plan.WallStuds = 4
-- 76 deep. A classroom 48 wide by 76 deep is 13 by 21 metres, which is a large room; the depth
-- is set by the gym on the far side needing 124, and a ring wants matching bands.
Plan.BandStuds = 76
-- 24, from section 05: camera clearance on a turn plus a sparring pair abreast.
Plan.CorridorStuds = 24
-- The colonnade between corridor and courtyard. Structure, not circulation.
Plan.ArcadeStuds = 6
Plan.CourtyardStuds = 180
-- The gym breaks the ring on the north: 76 will not hold a sparring hall.
Plan.GymBandStuds = 124

-- 4 + 76 + 24 + 6 + 180 + 6 + 24 + 76 + 4 = 400
Plan.WidthStuds = Plan.WallStuds * 2
	+ Plan.BandStuds * 2
	+ Plan.CorridorStuds * 2
	+ Plan.ArcadeStuds * 2
	+ Plan.CourtyardStuds

-- The same, with the gym band replacing one room band: 448
Plan.DepthStuds = Plan.WallStuds * 2
	+ Plan.BandStuds
	+ Plan.GymBandStuds
	+ Plan.CorridorStuds * 2
	+ Plan.ArcadeStuds * 2
	+ Plan.CourtyardStuds

-- ---------------------------------------------------------------------------------------
-- Heights
-- ---------------------------------------------------------------------------------------

-- 16 clear, from section 05: a jumping avatar's head crown reaches 12.2, so 12 means clipping
-- on every jump and in a combat showcase they will jump constantly.
Plan.ClearStuds = 16
Plan.SlabStuds = 4
Plan.StoreyStuds = Plan.ClearStuds + Plan.SlabStuds
Plan.Floors = 3
Plan.RoofStuds = Plan.StoreyStuds * Plan.Floors -- 60

-- ---------------------------------------------------------------------------------------
-- Edges, west to east and south to north
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

-- X: wall, room band, corridor, arcade, courtyard, arcade, corridor, room band, wall
Plan.X = run(0, Plan.WallStuds, Plan.BandStuds, Plan.CorridorStuds, Plan.ArcadeStuds,
	Plan.CourtyardStuds, Plan.ArcadeStuds, Plan.CorridorStuds, Plan.BandStuds, Plan.WallStuds)

-- Z: wall, room band, corridor, arcade, courtyard, arcade, corridor, GYM band, wall
Plan.Z = run(0, Plan.WallStuds, Plan.BandStuds, Plan.CorridorStuds, Plan.ArcadeStuds,
	Plan.CourtyardStuds, Plan.ArcadeStuds, Plan.CorridorStuds, Plan.GymBandStuds, Plan.WallStuds)

-- Named indices into the edge lists, so Shell reads as a plan rather than as arithmetic.
--
-- `run` emits the *starting* edge plus one per band, so index 1 is the outside face and index
-- n+1 is the far side of band n. Naming these after the band they follow rather than the band
-- they precede is an off-by-one that put the south rooms at z -72 and overlapped twelve of them;
-- the plan checks caught it before a single part was laid, which is the entire reason the plan
-- is data in its own file.
Plan.Edge = {
	Outer = 1, -- 0     outside face of the wall
	WallInner = 2, -- 4     inside face of the wall / start of the room band
	BandInner = 3, -- 80    end of the room band / start of the corridor
	CorridorInner = 4, -- 104   end of the corridor / start of the arcade
	CourtNear = 5, -- 110   start of the courtyard
	CourtFar = 6, -- 290   end of the courtyard
	ArcadeFar = 7, -- 296   end of the far arcade
	CorridorFar = 8, -- 320   end of the far corridor / start of the far band
	BandFar = 9, -- 396 x, 444 z   end of the far band
	OuterFar = 10, -- 400 x, 448 z
}

-- ---------------------------------------------------------------------------------------
-- Rooms
-- ---------------------------------------------------------------------------------------

export type Room = {
	Id: string,
	Label: string,
	Floor: number,
	X1: number,
	Z1: number,
	X2: number,
	Z2: number,
}

-- Six bays along the south band, four down each side. The disciplinary room is the middle two
-- bays of the south band on level 3 -- see section 04 for why it sits at the head of the long
-- corridor rather than anywhere more convenient.
local function bays(from: number, to: number, count: number): { { number } }
	local out = {}
	local span = (to - from) / count
	for index = 1, count do
		table.insert(out, { from + span * (index - 1), from + span * index })
	end
	return out
end

function Plan.Rooms(): { Room }
	local rooms: { Room } = {}
	local X, Z, E = Plan.X, Plan.Z, Plan.Edge

	local southBays = bays(X[E.WallInner], X[E.BandFar], 6)
	local sideBays = bays(Z[E.BandInner], Z[E.CorridorFar], 4)

	local programme = {
		-- Bays 1 and 6 are the stair cores on every floor. They have to be the same bay all the
		-- way up -- a stair that moves between storeys is two stairs and a hole in the slab.
		{ floor = 1, labels = { "Stair", "Reception", "Entrance Hall", "Entrance Hall", "Locker Hall", "Stair" } },
		{ floor = 2, labels = { "Stair", "Classroom", "Classroom", "Classroom", "Classroom", "Stair" } },
		{ floor = 3, labels = { "Stair", "Archive", "Disciplinary", "Disciplinary", "Records", "Stair" } },
	}

	for _, level in programme do
		for index, label in level.labels do
			local bay = southBays[index]
			table.insert(rooms, {
				Id = `s{level.floor}_{index}`,
				Label = label,
				Floor = level.floor,
				X1 = bay[1],
				Z1 = Z[E.WallInner],
				X2 = bay[2],
				Z2 = Z[E.BandInner],
			})
		end
	end

	for floor = 1, 3 do
		for index, bay in sideBays do
			table.insert(rooms, {
				Id = `w{floor}_{index}`,
				Label = if floor == 1 then "Refectory" else "Classroom",
				Floor = floor,
				X1 = X[E.WallInner],
				Z1 = bay[1],
				X2 = X[E.BandInner],
				Z2 = bay[2],
			})
			table.insert(rooms, {
				Id = `e{floor}_{index}`,
				Label = if floor == 1 then "Workshop" else "Classroom",
				Floor = floor,
				X1 = X[E.CorridorFar],
				Z1 = bay[1],
				X2 = X[E.BandFar],
				Z2 = bay[2],
			})
		end
	end

	return rooms
end

-- The two stair cores: the outer bays of the south band, same bay on every floor.
--
-- They sit in the band rather than in the corners of the corridor ring, and the reason is the
-- arithmetic: a 20-stud storey at a 1.43 riser is 14 treads, and 14 treads at a 3-stud going is
-- a 42-stud run. The ring's corners are 24 square. The band is 76 deep, which holds a straight
-- flight with room to arrive into.
function Plan.Stairs(): { Room }
	local X, Z, E = Plan.X, Plan.Z, Plan.Edge
	local bay = (X[E.BandFar] - X[E.WallInner]) / 6
	local out: { Room } = {}
	for index, first in { X[E.WallInner], X[E.WallInner] + bay * 5 } do
		table.insert(out, {
			Id = `stair{index}`,
			Label = "Stair",
			Floor = 1,
			X1 = first,
			Z1 = Z[E.WallInner],
			X2 = first + bay,
			Z2 = Z[E.BandInner],
		})
	end
	return out
end

Plan.StairRiserStuds = 20 / 14
Plan.StairGoingStuds = 3
Plan.StairTreads = 14
Plan.StairWidthStuds = 16

-- The sparring hall: the middle of the north band, double height over floors 1 and 2.
function Plan.Gym(): Room
	local X, Z, E = Plan.X, Plan.Z, Plan.Edge
	local centre = Plan.WidthStuds / 2
	return {
		Id = "gym",
		Label = "Sparring Hall",
		Floor = 1,
		X1 = centre - 100,
		Z1 = Z[E.CorridorFar],
		X2 = centre + 100,
		Z2 = Z[E.BandFar],
	}
end

return Plan
