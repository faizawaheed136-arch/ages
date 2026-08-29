--!strict
-- The reading room, as a room that exists.
--
-- Two things in it: the desk you build words at, and the shelf you draw a fresh tray of
-- tiles from when the one you have is spent.
--
-- The distance between them is deliberately *short*, and that is the one decision in this
-- file worth defending, because the art room next door makes the opposite one. There the
-- walk is the mechanic -- fetching paint costs you sight of the picture, so the cupboard is
-- put behind the player on purpose. Here the mechanic is the allocation at the desk, and a
-- long walk would not deepen it, it would only interrupt it. The shelf exists so a tray has
-- a refill cost, not so the room is big.
--
-- Split from ReadingService for the reason Lab is split from ScienceService and Studio from
-- ArtService: where a thing stands and what happens when you reach it are different
-- questions, and re-laying the room must never be able to touch the scoring.
--
-- Laid in Luau at runtime around the school place point, like the lab, the studio and the
-- corridor. Every position is derived from the centre it is handed -- there is not an
-- absolute world coordinate in this file, and there must never be one, because the map
-- still moves and place-point ids are the only thing that is stable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local ReadingRoom = {}

local READING = Config.School.Reading
local BUILD = READING.Build

-- What a built room hands back. Two points, and nothing else: unlike the art room there is
-- no piece of furniture here whose *appearance* is state. The board is per player and
-- pushed, because two children at the same desk are finishing different words.
export type Room = {
	center: Vector3,
	desk: Vector3,
	shelf: Vector3,
}

local room: Room? = nil
local folder: Folder? = nil

-- Everything the reading room puts in the world lives in one folder, the same arrangement
-- the other three make and separate from them because the four get cleared for different
-- reasons.
local function roomFolder(): Folder
	local existing = folder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "ReadingRoom"
	made.Parent = workspace
	folder = made
	return made
end

-- A point on the room\'s circle, in the same terms Lab.onCircle and Studio.onCircle use, so
-- a layout number here and a layout number there mean the same thing.
local function onCircle(center: Vector3, bearing: number, share: number): Vector3
	local direction = CFrame.Angles(0, math.rad(bearing), 0) * Vector3.new(0, 0, -1)
	return center + direction * (BUILD.RoomRadiusStuds * share)
end

-- One piece of placeholder furniture, sat on the floor rather than centred in it.
-- Non-collidable for the reason the lab\'s and the studio\'s are: what costs the player
-- something here is deciding where a letter goes, not walking around a desk.
local function buildBlock(name: string, at: Vector3, size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(at + Vector3.new(0, size.Y / 2, 0))
	part.Anchored = true
	part.CanCollide = false
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = roomFolder()
	return part
end

-- The name over a piece of furniture, built in the world rather than pushed, because what a
-- thing *is* is true for everybody standing in the room.
local function buildLabel(part: BasePart, text: string, width: number)
	local sign = Instance.new("BillboardGui")
	sign.Name = "Label"
	sign.Adornee = part
	sign.Size = UDim2.new(width, 0, 1.1, 0)
	sign.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 1.2, 0)
	sign.MaxDistance = BUILD.LabelMaxDistanceStuds
	sign.AlwaysOnTop = true
	sign.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(248, 246, 240)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = sign
end

-- Builds the room around a centre point, once. Nil means it could not be laid, which the
-- caller turns into Reading refusing at the door with a reason rather than into a lesson
-- that opens onto nothing.
function ReadingRoom.Build(center: Vector3): Room?
	local existing = room
	if existing ~= nil then
		return existing
	end

	local deskAt = onCircle(center, BUILD.DeskBearing, BUILD.DeskDistanceShare)
	local shelfAt = onCircle(center, BUILD.ShelfBearing, BUILD.ShelfDistanceShare)

	local desk = buildBlock("ReadingDesk", deskAt, BUILD.DeskSize, Color3.fromRGB(138, 106, 72))
	buildLabel(desk, "Desk", 6)

	local shelf = buildBlock("LetterShelf", shelfAt, BUILD.ShelfSize, Color3.fromRGB(112, 124, 132))
	-- Says what it hands out rather than what it is called, because a shelf is only
	-- interesting to somebody whose tray has run dry and that is the moment they will be
	-- reading it from across the room.
	buildLabel(shelf, "Letters", 6)

	local built: Room = {
		center = center,
		desk = deskAt,
		shelf = shelfAt,
	}
	room = built
	return built
end

-- The room as it stands, or nil if it has not been laid yet. Read rather than built by
-- callers that must not cause one to appear.
function ReadingRoom.Room(): Room?
	return room
end

-- Takes the room down, for the new-life path -- the same reason Corridor.Clear exists: the
-- folder is rebuilt around whichever school point the next life walks into.
function ReadingRoom.Clear()
	local existing = folder
	if existing ~= nil then
		existing:Destroy()
	end
	folder = nil
	room = nil
end

return ReadingRoom
