--!strict
-- The interior walls of all three floors, built from Layout.
--
-- Every coordinate comes out of `Layout`; there are no dimensions written down here. See the
-- header of that file for why that rule is absolute rather than tidy.

local Engine = require(script.Parent.SchoolBuilderEngine)
local Layout = require(script.Parent.Layout)
local Tree = require(script.Parent.Tree)

local Interior = {}

local T = Layout.WallThicknessStuds
local FH = Layout.FloorHeightStuds
local DOOR_W = Layout.DoorWidthStuds
local DOOR_H = Layout.DoorHeightStuds

local PARTITION = Color3.fromRGB(228, 230, 235)
local CORRIDOR_WALL = Color3.fromRGB(206, 211, 219)
local TRIM = Color3.fromRGB(58, 64, 76)
local GLASS_TINT = Color3.fromRGB(198, 220, 236)
local COUNTER_TOP = Color3.fromRGB(52, 58, 68)
local COUNTER_BODY = Color3.fromRGB(226, 228, 232)

-- The two locker colours, alternating down the corridor.
local ROYAL_BLUE = Color3.fromRGB(36, 78, 176)
local CRIMSON = Color3.fromRGB(158, 34, 52)

local ORIGIN = Vector3.new(0, 0, 0)

local function place(x: number, y: number, z: number): Vector3
	return Vector3.new(x + ORIGIN.X, y + ORIGIN.Y, z + ORIGIN.Z)
end

-- ---------------------------------------------------------------------------------------
-- Wall helpers
-- ---------------------------------------------------------------------------------------

-- A straight partition. `axis` is which way it runs.
local function partition(parent: Instance, axis: string, fixed: number, from: number, to: number, y: number, colour: Color3, height: number?)
	local span = to - from
	if span <= 0.05 then
		return
	end
	local h = height or FH
	local mid = (from + to) / 2
	local position = if axis == "x" then place(mid, y + h / 2, fixed) else place(fixed, y + h / 2, mid)
	local size = if axis == "x" then Vector3.new(span, h, T) else Vector3.new(T, h, span)
	Engine.CreateWall(position, size, Vector3.new(0, 0, 0), Enum.Material.SmoothPlastic, colour, parent).Name = "Partition"
end

-- A partition with a doorway in it.
--
-- **Framed, not cut** -- the same constraint `CreateWindowCutout` works around, and the same
-- answer: a pier each side and a header over the top. A doorway differs from a window only in
-- having no sill, because the opening reaches the floor.
local function doorway(parent: Instance, axis: string, fixed: number, from: number, to: number, y: number, at: number, colour: Color3)
	local half = DOOR_W / 2
	partition(parent, axis, fixed, from, at - half, y, colour)
	partition(parent, axis, fixed, at + half, to, y, colour)

	local headerH = FH - DOOR_H
	if headerH > 0.05 then
		local position = if axis == "x"
			then place(at, y + DOOR_H + headerH / 2, fixed)
			else place(fixed, y + DOOR_H + headerH / 2, at)
		local size = if axis == "x" then Vector3.new(DOOR_W, headerH, T) else Vector3.new(T, headerH, DOOR_W)
		Engine.CreateWall(position, size, Vector3.new(0, 0, 0), Enum.Material.SmoothPlastic, colour, parent).Name = "DoorHeader"
	end

	-- A frame round the opening, which is what stops a doorway reading as a missing panel.
	for side = -1, 1, 2 do
		local jambAt = at + side * (half + T / 2)
		local position = if axis == "x" then place(jambAt, y + DOOR_H / 2, fixed) else place(fixed, y + DOOR_H / 2, jambAt)
		local size = if axis == "x" then Vector3.new(T, DOOR_H, T * 1.6) else Vector3.new(T * 1.6, DOOR_H, T)
		Engine.CreateWall(position, size, Vector3.new(0, 0, 0), Enum.Material.SmoothPlastic, TRIM, parent).Name = "DoorJamb"
	end
end

-- A glazed partition: a low solid upstand with glass above it, divided by mullions. Used where
-- a room should be visible from the corridor rather than shut off from it.
local function glazedPartition(parent: Instance, axis: string, fixed: number, from: number, to: number, y: number, at: number)
	local span = to - from
	if span <= 0.05 then
		return
	end
	local half = DOOR_W / 2

	for _, piece in { { from, at - half }, { at + half, to } } do
		local a, b = piece[1], piece[2]
		local width = b - a
		if width > 0.05 then
			local mid = (a + b) / 2
			-- The upstand, so the glass does not start at ankle height.
			local upPos = if axis == "x" then place(mid, y + 1.5, fixed) else place(fixed, y + 1.5, mid)
			local upSize = if axis == "x" then Vector3.new(width, 3, T) else Vector3.new(T, 3, width)
			Engine.CreateWall(upPos, upSize, Vector3.new(0, 0, 0), Enum.Material.SmoothPlastic, PARTITION, parent).Name = "GlazedUpstand"

			local glassH = DOOR_H - 3
			local gPos = if axis == "x" then place(mid, y + 3 + glassH / 2, fixed) else place(fixed, y + 3 + glassH / 2, mid)
			local gSize = if axis == "x" then Vector3.new(width, glassH, T * 0.4) else Vector3.new(T * 0.4, glassH, width)
			local pane = Engine.CreateWall(gPos, gSize, Vector3.new(0, 0, 0), Enum.Material.Glass, GLASS_TINT, parent)
			pane.Name = "GlazedPane"
			pane.Transparency = 0.45
			pane.Reflectance = 0.08

			-- Mullions every six studs or so, for the same reason the entrance curtain wall has
			-- them: undivided glass has no scale.
			local bars = math.max(1, math.floor(width / 8))
			for bar = 1, bars - 1 do
				local bx = a + width * (bar / bars)
				local mPos = if axis == "x" then place(bx, y + 3 + glassH / 2, fixed) else place(fixed, y + 3 + glassH / 2, bx)
				local mSize = if axis == "x" then Vector3.new(0.5, glassH, T * 0.8) else Vector3.new(T * 0.8, glassH, 0.5)
				Engine.CreateWall(mPos, mSize, Vector3.new(0, 0, 0), Enum.Material.SmoothPlastic, TRIM, parent).Name = "GlazedMullion"
			end

			-- The head, above the glass.
			local headH = FH - DOOR_H
			if headH > 0.05 then
				local hPos = if axis == "x" then place(mid, y + DOOR_H + headH / 2, fixed) else place(fixed, y + DOOR_H + headH / 2, mid)
				local hSize = if axis == "x" then Vector3.new(width, headH, T) else Vector3.new(T, headH, width)
				Engine.CreateWall(hPos, hSize, Vector3.new(0, 0, 0), Enum.Material.SmoothPlastic, PARTITION, parent).Name = "GlazedHead"
			end
		end
	end

	local headerH = FH - DOOR_H
	if headerH > 0.05 then
		local position = if axis == "x"
			then place(at, y + DOOR_H + headerH / 2, fixed)
			else place(fixed, y + DOOR_H + headerH / 2, at)
		local size = if axis == "x" then Vector3.new(DOOR_W, headerH, T) else Vector3.new(T, headerH, DOOR_W)
		Engine.CreateWall(position, size, Vector3.new(0, 0, 0), Enum.Material.SmoothPlastic, PARTITION, parent).Name = "DoorHeader"
	end
end

-- ---------------------------------------------------------------------------------------
-- Fittings
-- ---------------------------------------------------------------------------------------

-- Lockers down a corridor wall, alternating colours.
--
-- Alternating rather than random: a repeating two-colour pattern reads as a decision from the
-- end of a corridor, where a random one reads as a mistake. The run stops short of every
-- doorway, which is what `skip` is for -- a locker across a classroom door is the same error as
-- a column across an entrance.
local function lockerRun(parent: Instance, z: number, facing: number, y: number, skips: { { number } })
	local doorW = 4
	local bankH = 11
	local x = Layout.CorridorX1 + 2

	local index = 0
	while x + doorW <= Layout.CorridorX2 - 2 do
		local blocked = false
		for _, gap in skips do
			if x + doorW > gap[1] and x < gap[2] then
				blocked = true
				x = gap[2] + 1
				break
			end
		end
		if not blocked then
			index += 1
			local colour = if index % 2 == 1 then ROYAL_BLUE else CRIMSON
			local cx = x + doorW / 2
			-- The outer face of the bank, computed rather than guessed at.
			--
			-- The handle and the vent were placed at a fixed 2.6 off the wall, which happens to
			-- be the face itself -- so each one straddled it and sat 88% inside the locker. A
			-- detail on a surface has to be offset by its own half-depth from that surface, and
			-- the only way to get that right every time is to work it out from the body.
			local faceZ = z + facing * (1.4 + 2.2 / 2)

			Engine.CreateWall(
				place(cx, y + 1 + bankH / 2, z + facing * 1.4),
				Vector3.new(doorW, bankH, 2.2),
				Vector3.new(0, 0, 0),
				Enum.Material.Metal,
				colour,
				parent
			).Name = `Locker{index}`
			Engine.CreateWall(
				place(cx, y + 0.5, z + facing * 1.4),
				Vector3.new(doorW, 1, 2.6),
				Vector3.new(0, 0, 0),
				Enum.Material.Metal,
				TRIM,
				parent
			).Name = `LockerPlinth{index}`
			-- The two details that make a coloured box read as a locker: a handle at hand
			-- height and a vent at the top.
			Engine.CreateWall(
				place(cx + doorW * 0.3, y + 1 + bankH * 0.5, faceZ + facing * 0.5),
				Vector3.new(0.4, 1.6, 0.25),
				Vector3.new(0, 0, 0),
				Enum.Material.Metal,
				Color3.fromRGB(232, 236, 244),
				parent
			).Name = `LockerHandle{index}`
			Engine.CreateWall(
				place(cx, y + 1 + bankH * 0.86, faceZ + facing * 0.5),
				Vector3.new(doorW * 0.45, 0.8, 0.2),
				Vector3.new(0, 0, 0),
				Enum.Material.Metal,
				TRIM,
				parent
			).Name = `LockerVent{index}`
			x += doorW
		end
	end
end

-- A counter round the perimeter of a room, for the laboratories.
local function perimeterCounter(parent: Instance, x1: number, x2: number, z1: number, z2: number, y: number, id: string)
	local inset = 2.5
	local runs = {
		{ axis = "x", fixed = z1 + inset, from = x1 + inset, to = x2 - inset },
		{ axis = "x", fixed = z2 - inset, from = x1 + inset, to = x2 - inset },
		{ axis = "z", fixed = x1 + inset, from = z1 + inset, to = z2 - inset },
		{ axis = "z", fixed = x2 - inset, from = z1 + inset, to = z2 - inset },
	}
	for index, run in runs do
		local span = run.to - run.from
		local mid = (run.from + run.to) / 2
		local topPos = if run.axis == "x" then place(mid, y + 2.7, run.fixed) else place(run.fixed, y + 2.7, mid)
		local topSize = if run.axis == "x" then Vector3.new(span, 0.5, 4) else Vector3.new(4, 0.5, span)
		Engine.CreateWall(topPos, topSize, Vector3.new(0, 0, 0), Enum.Material.SmoothPlastic, COUNTER_TOP, parent).Name =
			`{id}CounterTop{index}`

		local bodyPos = if run.axis == "x" then place(mid, y + 1.3, run.fixed) else place(run.fixed, y + 1.3, mid)
		local bodySize = if run.axis == "x" then Vector3.new(span, 2.6, 3.6) else Vector3.new(3.6, 2.6, span)
		Engine.CreateWall(bodyPos, bodySize, Vector3.new(0, 0, 0), Enum.Material.SmoothPlastic, COUNTER_BODY, parent).Name =
			`{id}CounterBody{index}`
	end
end

-- ---------------------------------------------------------------------------------------
-- Stairs
-- ---------------------------------------------------------------------------------------

local STAIR_TREAD = Color3.fromRGB(96, 102, 114)
local STAIR_NOSING = Color3.fromRGB(214, 218, 226)
local STAIR_RAIL = Color3.fromRGB(52, 58, 68)

-- One storey of stair inside a shaft: two flights and a half-landing between them.
--
-- **A dog-leg, because a straight run does not fit.** A storey here is 20 studs, and a flight
-- climbing 20 studs at a walkable pitch needs roughly 26 studs of floor to do it in. The shaft
-- is 24 across. So the climb is split: half a storey out to a landing at the far wall, a turn,
-- and half a storey back. Two flights of ten studs each need thirteen studs of run apiece,
-- which fits twice over in the same shaft -- and it is what a real school stairwell is, for
-- exactly this reason.
--
-- The two flights sit side by side across the shaft's depth, so the second passes back over
-- open air rather than over the first.
local function buildStairs(parent: Instance, shaft, floor: number)
	local y0 = Layout.FloorY(floor)
	local halfRise = FH / 2
	local steps = 12
	local stepRise = halfRise / steps

	-- Which wall carries the door, and which way the first flight climbs away from it.
	local fromDoor = shaft.x1 <= -Layout.HalfW
	local doorX = if fromDoor then shaft.x2 else shaft.x1
	local farX = if fromDoor then shaft.x1 else shaft.x2
	local dir = if fromDoor then -1 else 1

	local landingDepth = 5
	local landingFar = farX + dir * -(T + landingDepth / 2)
	local flightStartX = doorX + dir * 1
	local flightEndX = farX + dir * -(T + landingDepth)
	local runLen = math.abs(flightEndX - flightStartX)
	local going = runLen / steps

	-- The shaft's depth, split between the two flights with the balustrade on the join.
	local zMid = (shaft.z1 + shaft.z2) / 2
	local flightW = (shaft.z2 - shaft.z1 - T * 2) / 2 - 0.5
	local zUp = zMid - flightW / 2 - 0.5
	local zDown = zMid + flightW / 2 + 0.5

	-- Each tread is solid from the flight's own base to its top surface. On a straight flight
	-- the boxes hide behind one another and the result reads as a cast concrete stair, which is
	-- what a school has. (The curved stairs on the old school could not do this -- their boxes
	-- fanned out and every one showed its full height to the room.)
	local function flight(baseY: number, z: number, startX: number, direction: number, tag: string)
		for index = 1, steps do
			local topY = baseY + stepRise * index
			local cx = startX + direction * going * (index - 0.5)
			Engine.CreateWall(
				place(cx, (baseY + topY) / 2, z),
				Vector3.new(going, topY - baseY, flightW),
				Vector3.new(0, 0, 0),
				Enum.Material.Concrete,
				STAIR_TREAD,
				parent
			).Name = `Stair{tag}Step{index}`
			-- **The nosing lies on top of the tread, not in its front face.**
			--
			-- A real nosing overhangs the riser, and there is no riser to overhang here: each
			-- tread is solid from the flight's base, so the face below one tread is the *next*
			-- tread's box. Set flush it is two-thirds inside its own step; pushed forward to fix
			-- that it goes inside the step in front, which is worse. Laid on the surface it is a
			-- contrast line along the edge of each tread -- which is all it was ever for -- and
			-- it is inside nothing.
			Engine.CreateWall(
				place(cx + direction * going * 0.3, topY + 0.1, z),
				Vector3.new(0.6, 0.2, flightW + 0.4),
				Vector3.new(0, 0, 0),
				Enum.Material.SmoothPlastic,
				STAIR_NOSING,
				parent
			).Name = `Stair{tag}Nosing{index}`
		end
	end

	local tag = `{shaft.id}F{floor}`
	flight(y0, zUp, flightStartX, dir, `{tag}Up`)
	flight(y0 + halfRise, zDown, flightEndX, -dir, `{tag}Down`)

	-- The half-landing the first flight arrives on and the second leaves from.
	Engine.CreateFloor(
		place(landingFar, y0 + halfRise - 0.5, zMid),
		Vector3.new(landingDepth, 1, shaft.z2 - shaft.z1 - T * 2),
		Enum.Material.Concrete,
		STAIR_TREAD,
		parent
	).Name = `Stair{tag}HalfLanding`

	-- The arrival landing at the top, level with the floor it delivers you to. It reaches to
	-- the shaft's inner wall so you step off it straight through the doorway; without this the
	-- last tread hands you to the edge of the hole in the floor plate.
	Engine.CreateFloor(
		place(doorX + dir * 3.5, y0 + FH - 0.5, zDown),
		Vector3.new(7, 1, flightW),
		Enum.Material.Concrete,
		STAIR_TREAD,
		parent
	).Name = `Stair{tag}Arrival`

	-- A balustrade down the open side of each flight, on the line between them.
	for _, run in {
		{ z = zUp + flightW / 2, y = y0, tag = "Up" },
		{ z = zDown - flightW / 2, y = y0 + halfRise, tag = "Down" },
	} do
		-- The run is inset at both ends rather than spanning 0..1. At the extremes a post lands
		-- in the exterior wall at the top and in the doorway at the bottom -- a balustrade
		-- should stop where the flight does, not carry on into the building.
		local posts = 6
		for index = 0, posts do
			local share = 0.08 + (index / posts) * 0.84
			local px = flightStartX + dir * runLen * (if run.tag == "Up" then share else 1 - share)
			local py = run.y + halfRise * share + 2.2
			Engine.CreateWall(
				place(px, py, run.z),
				Vector3.new(0.4, 4.4, 0.4),
				Vector3.new(0, 0, 0),
				Enum.Material.Metal,
				STAIR_RAIL,
				parent
			).Name = `Stair{tag}{run.tag}Post{index}`
		end
	end
end

-- ---------------------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------------------

local function buildFloor(parent: Instance, floor: number)
	local y = Layout.FloorY(floor)
	local rooms = Layout.RoomsOn(floor)

	-- ---- the shaft walls, on every floor, so a stairwell is a shaft rather than a hole
	for _, shaft in Layout.Stairwells do
		local inner = if shaft.x1 <= -Layout.HalfW then shaft.x2 else shaft.x1
		-- **A doorway, not a wall.** This was solid on every floor, which made each shaft a
		-- sealed box with a staircase in it and no way to reach the staircase. Worth stating
		-- plainly because it is the kind of thing that looks completely finished from outside.
		--
		-- Stopped a wall-thickness short at each end too: run to the full corridor width and it
		-- meets the corridor's own wall face-on and the two interpenetrate at the junction.
		doorway(parent, "z", inner, shaft.z1 + T, shaft.z2 - T, y, 0, CORRIDOR_WALL)
		partition(parent, "x", shaft.z1, shaft.x1, shaft.x2, y, CORRIDOR_WALL)
		partition(parent, "x", shaft.z2, shaft.x1, shaft.x2, y, CORRIDOR_WALL)
	end

	-- ---- corridor walls and the rooms behind them
	for _, room in rooms do
		local bz1, bz2 = Layout.BandZ(room.band)
		local corridorLine = if room.band == "front" then Layout.CorridorZ1 else Layout.CorridorZ2
		local doorAt = (room.x1 + room.x2) / 2

		-- The wall onto the corridor -- but only along the stretch that *is* corridor.
		--
		-- Where a room backs onto a stairwell the wall is plain, because there is nothing to
		-- open onto or see into from inside a shaft. Skipping this put glazing bars from the
		-- library's window wall inside the shaft partitions: the room band runs the full 200
		-- studs, the corridor only the 152 between the two stairs, and a wall that ignores the
		-- difference is a wall built through something.
		local wx1 = math.max(room.x1, Layout.CorridorX1)
		local wx2 = math.min(room.x2, Layout.CorridorX2)
		partition(parent, "x", corridorLine, room.x1, wx1, y, CORRIDOR_WALL)
		partition(parent, "x", corridorLine, wx2, room.x2, y, CORRIDOR_WALL)

		if wx2 - wx1 > DOOR_W + 2 then
			-- The door position comes from Layout.DoorwaysOn, which is also what hangs the door
			-- panel and its prompt. Computed here as well they would agree today and drift the
			-- first time a room moves.
			local at = doorAt
			for _, opening in Layout.DoorwaysOn(floor) do
				if opening.id == room.id then
					at = opening.x
				end
			end
			if room.kind == "library" then
				glazedPartition(parent, "x", corridorLine, wx1, wx2, y, at)
			else
				doorway(parent, "x", corridorLine, wx1, wx2, y, at, CORRIDOR_WALL)
			end
		else
			partition(parent, "x", corridorLine, wx1, wx2, y, CORRIDOR_WALL)
		end

		-- The cross wall to the next room along. Only on the right-hand edge, so neighbours
		-- share one wall rather than each building their own in the same place.
		if room.x2 < Layout.HalfW - 0.05 then
			partition(parent, "z", room.x2, bz1, bz2, y, PARTITION)
		end

		-- Fittings that belong to the room itself.
		if room.kind == "lab" then
			perimeterCounter(parent, room.x1, room.x2, bz1, bz2, y, room.id)
		elseif room.kind == "computers" then
			-- Benches in rows rather than round the walls: a computer lab is looked at from the
			-- front, so the furniture faces one way.
			for row = 1, 3 do
				local rz = bz1 + (bz2 - bz1) * (row / 4)
				Engine.CreateWall(
					place((room.x1 + room.x2) / 2, y + 2.7, rz),
					Vector3.new(room.x2 - room.x1 - 10, 0.5, 4),
					Vector3.new(0, 0, 0),
					Enum.Material.SmoothPlastic,
					COUNTER_TOP,
					parent
				).Name = `ComputerBench{row}`
			end
		end
	end

	-- ---- the flights. Floors 1 and 2 each carry a storey of stair up to the floor above;
	-- the top floor has nothing above it to climb to.
	if floor < Layout.Floors then
		for _, shaft in Layout.Stairwells do
			buildStairs(parent, shaft, floor)
		end
	end

	-- ---- lockers, on the teaching floor only
	if floor == 2 then
		local skips: { { number } } = {}
		for _, room in rooms do
			local doorAt = (room.x1 + room.x2) / 2
			table.insert(skips, { doorAt - DOOR_W, doorAt + DOOR_W })
		end
		lockerRun(parent, Layout.CorridorZ1, 1, y, skips)
		lockerRun(parent, Layout.CorridorZ2, -1, y, skips)
	end
end

-- Lays every interior wall. `origin` is the building centre, the same one Exterior is given.
function Interior.Build(origin: Vector3?, floors: { [number]: Instance }?): ()
	ORIGIN = origin or Vector3.new(0, 0, 0)

	local targets = floors
	if targets == nil then
		local tree = Tree.Build()
		targets = { tree.Floor1, tree.Floor2, tree.Floor3 }
	end

	for floor = 1, Layout.Floors do
		local parent = (targets :: { [number]: Instance })[floor]
		if parent ~= nil then
			buildFloor(parent, floor)
		end
	end
end

return Interior
