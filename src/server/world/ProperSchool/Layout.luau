--!strict
-- The floor plan, as data. Nothing in here builds anything.
--
-- **This file exists because of a specific bug that cost days on the last school.** There, the
-- corridor's position was computed in one function and the hole in the upper floor was computed
-- in another. Both were correct in isolation; they disagreed by three studs; and the result was
-- a corridor with no floor under it on the first storey and a bank of lockers embedded in a
-- feature wall. Nothing errored, and it was only found by someone walking into it.
--
-- So the plan is written once, here, and every module that needs a coordinate reads it from
-- this table. `Exterior` cuts its stairwell openings from `Layout.Stairwells`; `Interior` builds
-- its shaft walls from the same rects. They cannot drift apart because there is only one of
-- them.

local Layout = {}

Layout.WidthStuds = 200 -- along X
Layout.DepthStuds = 120 -- along Z
Layout.FloorHeightStuds = 20
Layout.Floors = 3
Layout.WallThicknessStuds = 1.5

Layout.HalfW = Layout.WidthStuds / 2
Layout.HalfD = Layout.DepthStuds / 2

-- The corridor runs the length of the building, down the middle of its depth. Rooms sit in the
-- two bands either side of it -- the front band toward the entrance, the back band behind.
Layout.CorridorWidthStuds = 20
Layout.CorridorZ1 = -Layout.CorridorWidthStuds / 2
Layout.CorridorZ2 = Layout.CorridorWidthStuds / 2

Layout.FrontBandZ1 = -Layout.HalfD
Layout.FrontBandZ2 = Layout.CorridorZ1
Layout.BackBandZ1 = Layout.CorridorZ2
Layout.BackBandZ2 = Layout.HalfD

-- Openings between a room and the corridor.
Layout.DoorWidthStuds = 10
Layout.DoorHeightStuds = 12

-- **The two stairwells, at the ends of the corridor.**
--
-- At the ends rather than in the middle for the reason every school does it: a stair in the
-- middle of a corridor splits the corridor, and a stair at the end closes it. They sit inside
-- the corridor band so they are reached from the corridor and interrupt no room.
--
-- The same rects are what Exterior cuts out of every floor plate above the ground, which is
-- what "open ceilings for stairs" means -- a shaft is a hole through the building, and a hole
-- the walls know about but the floors do not is the bug this file exists to prevent.
Layout.StairwellWidthStuds = 24
Layout.Stairwells = {
	{
		id = "West",
		x1 = -Layout.HalfW,
		x2 = -Layout.HalfW + Layout.StairwellWidthStuds,
		z1 = Layout.CorridorZ1,
		z2 = Layout.CorridorZ2,
	},
	{
		id = "East",
		x1 = Layout.HalfW - Layout.StairwellWidthStuds,
		x2 = Layout.HalfW,
		z1 = Layout.CorridorZ1,
		z2 = Layout.CorridorZ2,
	},
}

-- The stretch of corridor that is actually corridor, between the two shafts.
Layout.CorridorX1 = -Layout.HalfW + Layout.StairwellWidthStuds
Layout.CorridorX2 = Layout.HalfW - Layout.StairwellWidthStuds

export type Room = {
	id: string,
	label: string,
	band: string, -- "front" or "back"
	x1: number,
	x2: number,
	kind: string,
}

-- Divides a band into n rooms of equal width. Equal by construction rather than by hand-written
-- corners, so a change to the count cannot leave a gap or an overlap behind.
local function split(band: string, entries: { { id: string, label: string, kind: string, share: number? } }): { Room }
	local total = 0
	for _, entry in entries do
		total += entry.share or 1
	end

	local rooms: { Room } = {}
	local cursor = -Layout.HalfW
	for _, entry in entries do
		local width = Layout.WidthStuds * ((entry.share or 1) / total)
		table.insert(rooms, {
			id = entry.id,
			label = entry.label,
			band = band,
			x1 = cursor,
			x2 = cursor + width,
			kind = entry.kind,
		})
		cursor += width
	end
	return rooms
end

local function concat(a: { Room }, b: { Room }): { Room }
	local out: { Room } = {}
	for _, r in a do
		table.insert(out, r)
	end
	for _, r in b do
		table.insert(out, r)
	end
	return out
end

-- **Floor 1 -- public and admin.** Everything a visitor needs is on the ground and reachable
-- without a stair: you come through the front door into the lobby, the office is beside it, and
-- the cafeteria takes the whole back band because it is the one room the entire school is in at
-- the same time.
--
-- Shares rather than coordinates: the lobby gets twice the frontage of an office because it is
-- the room the building is entered through, and the numbers say that rather than a comment.
Layout.Floor1 = concat(
	split("front", {
		{ id = "principal", label = "Principal's Office", kind = "office", share = 1 },
		{ id = "staff", label = "Staff Room", kind = "staff", share = 1 },
		{ id = "lobby", label = "Main Lobby", kind = "lobby", share = 2 },
		{ id = "restroomM", label = "Restrooms", kind = "restroom", share = 1 },
		{ id = "restroomF", label = "Restrooms", kind = "restroom", share = 1 },
	}),
	split("back", {
		{ id = "cafeteria", label = "Cafeteria", kind = "cafeteria", share = 7 },
		{ id = "kitchen", label = "Kitchen", kind = "kitchen", share = 3 },
	})
)

-- **Floor 2 -- six identical classrooms, three a side.** Identical on purpose: a teaching floor
-- is the one place repetition is correct, and a corridor of matching doors is what tells a
-- player at a glance which floor they are on.
Layout.Floor2 = concat(
	split("front", {
		{ id = "class1", label = "Classroom 1", kind = "classroom" },
		{ id = "class2", label = "Classroom 2", kind = "classroom" },
		{ id = "class3", label = "Classroom 3", kind = "classroom" },
	}),
	split("back", {
		{ id = "class4", label = "Classroom 4", kind = "classroom" },
		{ id = "class5", label = "Classroom 5", kind = "classroom" },
		{ id = "class6", label = "Classroom 6", kind = "classroom" },
	})
)

-- **Floor 3 -- the specialised rooms.** The library takes the whole front band as one volume,
-- glazed to the corridor: a library you can see into is one people go into.
Layout.Floor3 = concat(
	split("front", {
		{ id = "library", label = "Library & Media Centre", kind = "library" },
	}),
	split("back", {
		{ id = "lab1", label = "Science Laboratory 1", kind = "lab" },
		{ id = "lab2", label = "Science Laboratory 2", kind = "lab" },
		{ id = "computers", label = "Computer Lab", kind = "computers" },
	})
)

Layout.Floors_ = { Layout.Floor1, Layout.Floor2, Layout.Floor3 }

function Layout.RoomsOn(floor: number): { Room }
	return Layout.Floors_[floor] or {}
end

function Layout.FloorY(floor: number): number
	return (floor - 1) * Layout.FloorHeightStuds
end

-- The z extent of a band, so callers never write -60 or 10 by hand.
function Layout.BandZ(band: string): (number, number)
	if band == "front" then
		return Layout.FrontBandZ1, Layout.FrontBandZ2
	end
	return Layout.BackBandZ1, Layout.BackBandZ2
end

-- True where a stairwell shaft crosses this x on the corridor line -- the corridor's walls stop
-- at the shafts rather than running through them.
function Layout.InStairwell(x: number): boolean
	for _, shaft in Layout.Stairwells do
		if x >= shaft.x1 and x <= shaft.x2 then
			return true
		end
	end
	return false
end

return Layout
