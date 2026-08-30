--!strict
-- Furniture for the rooms Interior walls off.
--
-- Two rules learned the hard way on this building, both worth stating before the code:
--
--   * **Anything sitting on a face clears that face by at least a grid unit.** Engine snaps
--     every position to a quarter stud, so a detail offset by less than that can be rounded
--     back through the surface it was meant to sit on. That bug has now been found three times
--     -- locker vents, locker handles, stair nosings -- and it never throws, it just quietly
--     buries the thing.
--   * **A room's front is its -Z face**, and `facing` flips that for rooms on the other side of
--     the corridor. A classroom whose board is behind the students is not obviously wrong from
--     any single screenshot, which is exactly why it needs to be a parameter rather than an
--     assumption.

local Engine = require(script.Parent.SchoolBuilderEngine)
local Layout = require(script.Parent.Layout)
local Tree = require(script.Parent.Tree)

local Furniture = {}

local WOOD = Color3.fromRGB(148, 104, 66)
local DARK_WOOD = Color3.fromRGB(96, 66, 44)
local METAL = Color3.fromRGB(126, 132, 142)
local CHAIR = Color3.fromRGB(58, 92, 158)
local SLATE = Color3.fromRGB(44, 50, 60)

local BOOK = {
	Color3.fromRGB(158, 52, 52),
	Color3.fromRGB(44, 78, 148),
	Color3.fromRGB(72, 116, 72),
	Color3.fromRGB(186, 148, 68),
	Color3.fromRGB(104, 72, 132),
}

local SMOOTH = Enum.Material.SmoothPlastic
local PLANKS = Enum.Material.WoodPlanks
local METALLIC = Enum.Material.Metal

-- Anything on a surface clears it by this much. One grid unit -- see the header.
local CLEAR = 0.25

local function block(parent: Instance, name: string, position: Vector3, size: Vector3, material: Enum.Material, colour: Color3, orientation: Vector3?): Part
	local part = Engine.CreateWall(position, size, orientation or Vector3.new(0, 0, 0), material, colour, parent)
	part.Name = name
	return part
end

-- A disc lying flat. Roblox's cylinder runs along its own X, so a table top is a quarter turn
-- about Z -- not about Y, which is the mistake that produces a wheel standing on its edge.
local function disc(parent: Instance, name: string, position: Vector3, radius: number, thickness: number, material: Enum.Material, colour: Color3): Part
	local part = block(parent, name, position, Vector3.new(thickness, radius * 2, radius * 2), material, colour, Vector3.new(0, 0, 90))
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- A desk: a top on two leg panels. Three parts rather than five, because at this size a pair of
-- panels reads better than four thin legs and costs two parts less across two hundred desks.
local function desk(parent: Instance, tag: string, cx: number, cz: number, y: number, width: number, depth: number, height: number, topColour: Color3, topMaterial: Enum.Material)
	block(parent, `{tag}Top`, Vector3.new(cx, y + height, cz), Vector3.new(width, 0.4, depth), topMaterial, topColour)
	for side = -1, 1, 2 do
		block(
			parent,
			`{tag}Leg{side}`,
			Vector3.new(cx + side * (width / 2 - 0.8), y + height / 2, cz),
			Vector3.new(0.6, height, depth - 0.8),
			SMOOTH,
			METAL
		)
	end
end

local function chair(parent: Instance, tag: string, cx: number, cz: number, y: number, facing: number)
	block(parent, `{tag}Seat`, Vector3.new(cx, y + 1.9, cz), Vector3.new(2.6, 0.4, 2.6), SMOOTH, CHAIR)
	block(parent, `{tag}Back`, Vector3.new(cx, y + 3.3, cz - facing * 1.3), Vector3.new(2.6, 3, 0.4), SMOOTH, CHAIR)
	block(parent, `{tag}Leg`, Vector3.new(cx, y + 0.95, cz), Vector3.new(2, 1.9, 2), SMOOTH, METAL)
end

-- ---------------------------------------------------------------------------------------
-- Rooms
-- ---------------------------------------------------------------------------------------

-- A classroom: board on the front wall, teacher's desk in front of it, and a grid of student
-- desks facing both.
--
-- `facing` is which way the room's front is: -1 puts the board on the -Z wall, +1 on the +Z.
-- Everything else -- which way the students face, which side of the desk a chair goes -- falls
-- out of it, so the room cannot end up half-reversed.
function Furniture.PopulateClassroom(roomCenter: Vector3, roomSize: Vector3, parent: Instance?, facing: number?)
	local into = parent or Tree.Build().Furniture
	local face = facing or -1
	local y = roomCenter.Y
	local halfD = roomSize.Z / 2
	local frontZ = roomCenter.Z + face * (halfD - 1)
	local tag = `Class{math.round(roomCenter.X)}_{math.round(roomCenter.Z)}`

	-- The whiteboard: one large dark slate panel, framed, standing off the wall by more than
	-- the grid so it cannot snap into it.
	block(into, `{tag}BoardFrame`, Vector3.new(roomCenter.X, y + 9, frontZ - face * CLEAR), Vector3.new(26, 12, 0.5), SMOOTH, Color3.fromRGB(198, 202, 210))
	block(into, `{tag}Board`, Vector3.new(roomCenter.X, y + 9, frontZ - face * (CLEAR + 0.5)), Vector3.new(24, 10.4, 0.4), SMOOTH, SLATE)
	block(into, `{tag}BoardTray`, Vector3.new(roomCenter.X, y + 3.4, frontZ - face * (CLEAR + 0.9)), Vector3.new(24, 0.4, 1.2), SMOOTH, METAL)

	-- The teacher's desk, set to one side of the board so it does not stand in front of it.
	local teacherZ = roomCenter.Z + face * (halfD - 8)
	desk(into, `{tag}Teacher`, roomCenter.X - 8, teacherZ, y, 11, 4.5, 3.2, DARK_WOOD, PLANKS)
	chair(into, `{tag}TeacherChair`, roomCenter.X - 8, teacherZ + face * 3.4, y, -face)

	-- **A 4 by 5 grid, sized to the room rather than pitched at a fixed spacing.**
	-- The rows divide the space that is actually free -- back wall to the teacher's zone -- so
	-- the grid stays a grid whatever the room's proportions are. Fixed pitch is what put desk
	-- row five on top of the teacher's desk in the last school.
	local cols, rows = 4, 5
	local fieldFront = roomCenter.Z + face * (halfD - 16)
	local fieldBack = roomCenter.Z - face * (halfD - 5)
	local rowPitch = (fieldBack - fieldFront) / rows
	local colPitch = (roomSize.X - 12) / cols

	for row = 1, rows do
		for col = 1, cols do
			local dx = roomCenter.X - (roomSize.X - 12) / 2 + colPitch * (col - 0.5)
			local dz = fieldFront + rowPitch * (row - 0.5)
			local id = `{tag}D{row}_{col}`
			desk(into, id, dx, dz, y, 6, 3, 2.8, WOOD, PLANKS)
			-- The chair sits behind the desk, on the side away from the board.
			chair(into, `{id}Chair`, dx, dz - face * 3, y, face)
		end
	end
end

-- The library: ranks of shelving down both flanks, reading tables through the middle.
--
-- Shelves are ranked rather than scattered for the same reason the window bays are even -- a
-- regular rhythm reads as a designed room, and an irregular one reads as a mistake from the
-- door. The middle is left clear because a library that is all stacks has nowhere to read.
function Furniture.PopulateLibrary(roomCenter: Vector3, roomSize: Vector3, parent: Instance?)
	local into = parent or Tree.Build().Furniture
	local y = roomCenter.Y
	local tag = "Library"
	local spacing = 6
	local shelfDepth = 3
	local shelfHeight = 11
	local halfW = roomSize.X / 2
	local halfD = roomSize.Z / 2

	-- The stacks: two blocks of ranks, one at each end, running across the room's depth.
	local rankLength = roomSize.Z - 14
	local blockWidth = halfW * 0.45
	local index = 0
	for side = -1, 1, 2 do
		local blockStart = roomCenter.X + side * (halfW - 4)
		local ranks = math.floor(blockWidth / spacing)
		for rank = 1, ranks do
			index += 1
			local sx = blockStart - side * spacing * (rank - 0.5)
			block(into, `{tag}Shelf{index}`, Vector3.new(sx, y + shelfHeight / 2, roomCenter.Z), Vector3.new(shelfDepth, shelfHeight, rankLength), PLANKS, DARK_WOOD)
			-- Books on three tiers, and on **both faces** of the rank.
			--
			-- A single band drawn the full width of the carcass is 86% inside it: what shows is
			-- a quarter-stud sliver down each edge, which from any distance is nothing. A shelf
			-- is double-sided, so the books belong on the two faces, standing clear of the wood
			-- by the usual grid unit. Six parts a rank instead of three, and the difference is
			-- between a bookshelf and a brown box.
			for tier = 1, 3 do
				for face = -1, 1, 2 do
					block(
						into,
						`{tag}Books{index}_{tier}_{face}`,
						Vector3.new(sx + face * (shelfDepth / 2 + 0.6), y + tier * 3 - 0.6, roomCenter.Z),
						Vector3.new(1.2, 2, rankLength - 1),
						SMOOTH,
						BOOK[(index + tier + face) % #BOOK + 1]
					)
				end
			end
		end
	end

	-- Round study tables down the centre, four chairs apiece.
	local tables = 4
	for t = 1, tables do
		local tx = roomCenter.X - (roomSize.X * 0.4) / 2 + (roomSize.X * 0.4) * ((t - 0.5) / tables)
		local tz = roomCenter.Z
		disc(into, `{tag}Table{t}`, Vector3.new(tx, y + 3.2, tz), 5, 0.5, PLANKS, WOOD)
		block(into, `{tag}TablePost{t}`, Vector3.new(tx, y + 1.6, tz), Vector3.new(1.2, 3.2, 1.2), SMOOTH, METAL)
		disc(into, `{tag}TableFoot{t}`, Vector3.new(tx, y + 0.3, tz), 2.2, 0.5, SMOOTH, METAL)
		for seat = 0, 3 do
			local angle = math.rad(90 * seat)
			chair(into, `{tag}T{t}C{seat}`, tx + math.cos(angle) * 7, tz + math.sin(angle) * 7, y, if math.sin(angle) >= 0 then -1 else 1)
		end
	end
end

-- The cafeteria: long refectory tables in rows, benches either side.
--
-- Bench tables rather than separate chairs, because that is what a school hall has and because
-- a hundred loose chairs is a hundred parts that will all end up at odd angles.
function Furniture.PopulateCafeteria(roomCenter: Vector3, roomSize: Vector3, parent: Instance?)
	local into = parent or Tree.Build().Furniture
	local y = roomCenter.Y
	local tag = "Cafe"
	local rows = 5
	local tableLength = roomSize.Z - 16
	local usable = roomSize.X - 20
	local pitch = usable / rows

	for row = 1, rows do
		local tx = roomCenter.X - usable / 2 + pitch * (row - 0.5)
		block(into, `{tag}Table{row}`, Vector3.new(tx, y + 3, roomCenter.Z), Vector3.new(7, 0.5, tableLength), PLANKS, WOOD)
		for side = -1, 1, 2 do
			block(into, `{tag}Leg{row}_{side}`, Vector3.new(tx, y + 1.5, roomCenter.Z + side * (tableLength / 2 - 3)), Vector3.new(6, 3, 0.8), SMOOTH, METAL)
			block(into, `{tag}Bench{row}_{side}`, Vector3.new(tx + side * 6, y + 1.9, roomCenter.Z), Vector3.new(3.2, 0.4, tableLength - 2), PLANKS, DARK_WOOD)
			block(into, `{tag}BenchLeg{row}_{side}`, Vector3.new(tx + side * 6, y + 0.95, roomCenter.Z), Vector3.new(2.6, 1.9, tableLength - 6), SMOOTH, METAL)
		end
	end
end

-- ---------------------------------------------------------------------------------------
-- Administration
-- ---------------------------------------------------------------------------------------
--
-- **These are baked, which is why they live here rather than in Interactive.**
--
-- Anything built in Interactive exists only once the server is running, so it is invisible in
-- the editor. Geometry belongs in the bake and behaviour belongs at runtime, and the seam
-- between them is the part name: Interactive finds `ReceptionChair`, `ExecChair`, `GuestChair*`
-- and `Couch*` below and hangs a Seat and an L prompt on each. Rename one here and it stops
-- being sittable, silently -- which is the cost of the split and worth knowing about.

-- The reception desk, curved as a fan of straight segments. Roblox has no curved primitive, and
-- seven chords across 110 degrees reads as a curve from anywhere a player stands.
function Furniture.PopulateLobby(roomCenter: Vector3, roomSize: Vector3, parent: Instance?)
	local into = parent or Tree.Build().Furniture
	local y = roomCenter.Y
	local cx = roomCenter.X
	local cz = roomCenter.Z - roomSize.Z / 2 + 22
	local radius = 13
	local segments = 7
	local sweep = math.rad(110)
	local chord = radius * sweep / segments

	for i = 1, segments do
		local a = -sweep / 2 + sweep * ((i - 0.5) / segments)
		local px = cx + math.sin(a) * radius
		local pz = cz + math.cos(a) * radius
		local turn = Vector3.new(0, -math.deg(a), 0)
		block(into, `DeskBody{i}`, Vector3.new(px, y + 2, pz), Vector3.new(chord + 1, 4, 3), PLANKS, DARK_WOOD, turn)
		block(into, `DeskTop{i}`, Vector3.new(px, y + 4.2, pz), Vector3.new(chord + 1.4, 0.5, 4), SMOOTH, Color3.fromRGB(226, 228, 232), turn)
		-- The privacy screen is glass and stops at counter height plus three, so the desk
		-- screens the paperwork without hiding the person behind it.
		block(into, `DeskScreen{i}`, Vector3.new(px, y + 6, pz), Vector3.new(chord + 1, 3, 0.3), Enum.Material.Glass, Color3.fromRGB(196, 220, 240), turn)
	end

	block(into, "Monitor", Vector3.new(cx, y + 6, cz + radius - 1.5), Vector3.new(6, 3.6, 0.3), SMOOTH, SLATE)
	block(into, "MonitorScreen", Vector3.new(cx, y + 6, cz + radius - 1.8), Vector3.new(5.4, 3, 0.1), Enum.Material.Neon, Color3.fromRGB(120, 180, 230))
	block(into, "MonitorStand", Vector3.new(cx, y + 3.6, cz + radius - 1.5), Vector3.new(1, 1.6, 1), SMOOTH, METAL)
	block(into, "ReceptionChair", Vector3.new(cx, y + 2, cz + radius + 3), Vector3.new(3, 0.4, 3), SMOOTH, SLATE)
	block(into, "ReceptionChairBack", Vector3.new(cx, y + 4.2, cz + radius + 4.4), Vector3.new(3, 4, 0.4), SMOOTH, SLATE)
end

function Furniture.PopulateOffice(roomCenter: Vector3, roomSize: Vector3, parent: Instance?)
	local into = parent or Tree.Build().Furniture
	local y = roomCenter.Y
	local cx, cz = roomCenter.X, roomCenter.Z

	block(into, "ExecDeskBody", Vector3.new(cx, y + 2, cz), Vector3.new(16, 4, 7), PLANKS, Color3.fromRGB(58, 40, 28))
	block(into, "ExecDeskTop", Vector3.new(cx, y + 4.3, cz), Vector3.new(17, 0.6, 8), PLANKS, Color3.fromRGB(74, 50, 34))
	block(into, "ExecChair", Vector3.new(cx, y + 2.2, cz - 6), Vector3.new(4, 0.5, 4), SMOOTH, SLATE)
	block(into, "ExecChairBack", Vector3.new(cx, y + 6, cz - 8), Vector3.new(4, 7, 0.6), SMOOTH, SLATE)

	for side = -1, 1, 2 do
		block(into, `GuestChair{side}`, Vector3.new(cx + side * 5, y + 2, cz + 7), Vector3.new(3, 0.4, 3), SMOOTH, CHAIR)
		block(into, `GuestChairBack{side}`, Vector3.new(cx + side * 5, y + 4, cz + 8.4), Vector3.new(3, 4, 0.4), SMOOTH, CHAIR)
	end

	local cabX = roomCenter.X - roomSize.X / 2 + 6
	block(into, "FilingCabinet", Vector3.new(cabX, y + 5, cz - 14), Vector3.new(5, 10, 4), METALLIC, METAL)
	for drawer = 1, 3 do
		block(into, `FilingDrawer{drawer}`, Vector3.new(cabX, y + 1.6 + drawer * 3, cz - 11.7), Vector3.new(4.4, 2.4, 0.4), METALLIC, Color3.fromRGB(158, 164, 174))
	end
end

function Furniture.PopulateStaffRoom(roomCenter: Vector3, roomSize: Vector3, parent: Instance?)
	local into = parent or Tree.Build().Furniture
	local y = roomCenter.Y
	local cx, cz = roomCenter.X, roomCenter.Z

	block(into, "BreakTableTop", Vector3.new(cx, y + 3.2, cz + 6), Vector3.new(22, 0.6, 7), PLANKS, WOOD)
	for side = -1, 1, 2 do
		block(into, `BreakTableLeg{side}`, Vector3.new(cx + side * 9, y + 1.6, cz + 6), Vector3.new(1, 3.2, 6), SMOOTH, METAL)
	end

	local counterZ = roomCenter.Z - roomSize.Z / 2 + 4
	block(into, "KitchenBody", Vector3.new(cx, y + 1.5, counterZ), Vector3.new(24, 3, 4.4), SMOOTH, Color3.fromRGB(242, 243, 246))
	block(into, "KitchenCounter", Vector3.new(cx, y + 3.2, counterZ), Vector3.new(24, 0.6, 5), SMOOTH, Color3.fromRGB(216, 220, 228))
	block(into, "Sink", Vector3.new(cx - 6, y + 3.1, counterZ), Vector3.new(5, 0.8, 3.4), METALLIC, Color3.fromRGB(198, 204, 214))
	block(into, "Tap", Vector3.new(cx - 6, y + 4.8, counterZ - 1.6), Vector3.new(0.4, 2.4, 0.4), METALLIC, METAL)

	-- The pair is spaced off the room's width, not a fixed eleven studs.
	--
	-- Two 12-stud couches with 6.2-stud arms need 35.6 studs between their outer edges, and the
	-- staff room is 40 wide -- so a hard-coded offset put both outer arms through the side walls.
	-- Derived, they sit clear whatever the room turns out to be.
	local couchOffset = roomSize.X * 0.22
	for index = -1, 1, 2 do
		local sx = cx + index * couchOffset
		local sz = cz + 16
		block(into, `Couch{index}`, Vector3.new(sx, y + 2, sz), Vector3.new(12, 2.6, 5), Enum.Material.Fabric, Color3.fromRGB(96, 118, 168))
		block(into, `CouchBack{index}`, Vector3.new(sx, y + 4.4, sz + 2.2), Vector3.new(12, 5, 1.2), Enum.Material.Fabric, Color3.fromRGB(84, 104, 152))
		for arm = -1, 1, 2 do
			block(into, `CouchArm{index}_{arm}`, Vector3.new(sx + arm * 6.2, y + 3.4, sz), Vector3.new(1.2, 3.4, 5), Enum.Material.Fabric, Color3.fromRGB(84, 104, 152))
		end
	end
end

-- ---------------------------------------------------------------------------------------
-- Driver
-- ---------------------------------------------------------------------------------------

-- Walks every room on every floor and fills the ones there is furniture for.
--
-- The bounds come out of Layout, the same table the walls were built from, so a room's contents
-- and the room itself cannot end up in different places. Nothing here writes a coordinate.
function Furniture.Build(origin: Vector3?, parent: Instance?): ()
	local into = parent or Tree.Build().Furniture
	local at = origin or Vector3.new(0, 0, 0)

	for floor = 1, Layout.Floors do
		local y = Layout.FloorY(floor)
		for _, room in Layout.RoomsOn(floor) do
			local z1, z2 = Layout.BandZ(room.band)
			local centre = Vector3.new((room.x1 + room.x2) / 2 + at.X, y + at.Y, (z1 + z2) / 2 + at.Z)
			local size = Vector3.new(room.x2 - room.x1, Layout.FloorHeightStuds, z2 - z1)

			-- A front-band room has the corridor on its +Z side, so its front -- the wall the
			-- board goes on -- is -Z. A back-band room is the mirror of that.
			local facing = if room.band == "front" then -1 else 1

			if room.kind == "classroom" then
				Furniture.PopulateClassroom(centre, size, into, facing)
			elseif room.kind == "library" then
				Furniture.PopulateLibrary(centre, size, into)
			elseif room.kind == "cafeteria" then
				Furniture.PopulateCafeteria(centre, size, into)
			elseif room.kind == "lobby" then
				Furniture.PopulateLobby(centre, size, into)
			elseif room.kind == "office" then
				Furniture.PopulateOffice(centre, size, into)
			elseif room.kind == "staff" then
				Furniture.PopulateStaffRoom(centre, size, into)
			end
		end
	end
end

return Furniture
