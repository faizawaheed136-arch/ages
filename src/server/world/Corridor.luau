--!strict
-- The corridor, as a place that exists.
--
-- School had a pad outside it and three rooms hanging off one point, and nothing in
-- between: you arrived at the building and a lesson happened to you. The walk from the
-- door to the desk was zero studs long, so there was nowhere for anything to *be* between
-- lessons -- which is why the school read as a menu with a roof on rather than as a
-- building somebody spends twelve years in.
--
-- This is that walk, given a length. It is one straight run with lockers down both sides,
-- a handful of places along it where somebody can stand, and a library desk at the far
-- end. Nothing here knows what a bully is; it lays the floor and hands back the points.
--
-- Split from BullyService for the reason Lab is split from ScienceService and Studio from
-- ArtService: where a thing stands and what happens when you reach it are different
-- questions, and re-laying the corridor must never be able to touch the scoring.
--
-- Built in Luau at runtime around the school place point, exactly as the lab and the art
-- room are, and that is the whole reason the school can grow at all from here. The
-- building itself is generated into assets/ by tools/, which is eleven megabytes of XML
-- that cannot be hand-merged and belongs to somebody else; a room laid in code around a
-- point that is looked up by id costs nobody a regeneration and moves with the map when
-- the map moves. Every position below is derived from the centre it is handed. There is
-- not an absolute world coordinate anywhere in this file, and there must never be one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Corridor = {}

local BUILD = Config.School.Bully.Build

-- What a built corridor hands back. Points only: the parts are the room's own business
-- and nothing outside here has a reason to hold one.
export type CorridorRoom = {
	-- The school point it was laid around, kept so a caller can tell whether the corridor
	-- it is holding belongs to the building it is standing in.
	center: Vector3,
	-- The mouth and the far end, on the floor.
	start: Vector3,
	finish: Vector3,
	-- Unit vector along the run, start to finish. Handed back rather than recomputed by
	-- every caller that wants to face somebody down it -- two derivations of the same
	-- direction is two chances to disagree about which way the corridor points.
	axis: Vector3,
	-- Where somebody can stand, in order, mouth first. Exactly Build.StationCount of them.
	-- The tiers in Config index into this, which is why the count is checked below rather
	-- than trusted: a tier asking for station three of two is a spawn that fails silently
	-- at the moment the corridor is supposed to get harder.
	stations: { Vector3 },
	-- The desk you redo taken homework at, at the far end on purpose -- it is the forced
	-- traversal the whole consumable exists to create, and a desk beside the lockers would
	-- be a refill with a walk animation on it.
	library: Vector3,
}

local room: CorridorRoom? = nil
local folder: Folder? = nil

-- Everything the corridor puts in the world lives in one folder, the same arrangement the
-- lab and the art room make and separate from both because the three get cleared for
-- different reasons.
local function corridorFolder(): Folder
	local existing = folder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "SchoolCorridor"
	made.Parent = workspace
	folder = made
	return made
end

-- One piece of placeholder furniture, sat on the floor rather than centred in it.
-- Non-collidable for the reason the lab's and the studio's are: what is supposed to cost
-- the player something here is the length of the run, not the job of walking round a
-- bench, and a corridor you have to thread is a corridor that charges twice.
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
	part.Parent = corridorFolder()
	return part
end

-- The name over a piece of furniture, built in the world rather than pushed, because what
-- a thing *is* is true for everybody standing in the room. Borrows the studio's distance
-- rather than inventing a third number that would drift away from it.
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

-- Builds the corridor around a centre point, once. Nil means it could not be laid at all,
-- which the caller turns into the corridor simply not running today rather than into a
-- stare-down against somebody standing in mid-air.
--
-- `layProps` is false when the school building is standing, and that is the whole of how
-- these two modules avoid building the same hallway twice. School.luau lays the corridor
-- floor, the lockers, the benches and the lighting as part of the architecture; this module
-- then wants nothing from the world except *where people stand*, which is arithmetic along
-- an axis. When there is no building -- the place point exists but the building is off or
-- failed to lay -- it falls back to laying its own hallway, so the bully system is never
-- dependent on the architecture having worked.
--
-- `library` is where taken homework is redone. Handed in rather than assumed, because with
-- the building up that is the actual library on the far side of the ground floor, and
-- without it there is nowhere better than the far end of this corridor.
--
-- The one thing that can genuinely fail here is the station count, and it is checked
-- rather than clamped: a tier that asks for a station the corridor does not have is a
-- content error that would otherwise present as the corridor mysteriously not getting
-- harder, months later, with nothing in any log about it.
function Corridor.Build(center: Vector3, layProps: boolean, library: Vector3?): CorridorRoom?
	local existing = room
	if existing ~= nil then
		return existing
	end

	if BUILD.StationCount < 1 then
		error(
			`[AGES config] Config.School.Bully.Build.StationCount is {BUILD.StationCount}, so the`
				.. ` corridor has nowhere for anybody to stand. Set it to at least 1.`
		)
	end
	for index, tier in Config.School.Bully.Tiers do
		if tier.stations > BUILD.StationCount then
			error(
				`[AGES config] Config.School.Bully.Tiers[{index}] wants {tier.stations} stations but the`
					.. ` corridor only lays {BUILD.StationCount}. Raise Build.StationCount or lower that tier.`
			)
		end
	end

	local axis = CFrame.Angles(0, math.rad(BUILD.BearingDegrees), 0) * Vector3.new(0, 0, -1)
	local start = center + axis * BUILD.StartOffsetStuds
	local finish = start + axis * BUILD.LengthStuds
	-- Across the run, for the two locker walls. Cross with up rather than turning the
	-- bearing by ninety degrees, so the two directions can never disagree about handedness
	-- when somebody edits the bearing.
	local across = axis:Cross(Vector3.new(0, 1, 0)).Unit
	local halfWidth = BUILD.WidthStuds / 2

	-- Where somebody can stand, spread down the middle of the run. Mouth first, so tier one
	-- puts a bully in the open where they can be seen from the door and the later tiers push
	-- them further in -- the escalation is which of these are occupied, and that is a change
	-- to the space rather than to any number.
	local stations: { Vector3 } = {}
	for i = 1, BUILD.StationCount do
		local share = i / (BUILD.StationCount + 1)
		table.insert(stations, start + axis * (BUILD.LengthStuds * share))
	end

	if layProps then
		Corridor.layProps(start, finish, axis, across, halfWidth)
	end

	local libraryAt = library or finish
	if layProps then
		local desk = buildBlock("LibraryDesk", libraryAt, Vector3.new(7, 3, 2.5), Color3.fromRGB(120, 92, 64))
		buildLabel(desk, "Library desk", 7)
	end

	local built: CorridorRoom = {
		center = center,
		start = start,
		finish = finish,
		axis = axis,
		stations = stations,
		library = libraryAt,
	}
	room = built
	return built
end

-- The hallway itself, laid only when there is no school building to have laid it already.
-- Kept as a function rather than deleted because the fallback is real: a place point with
-- the building switched off still has to give the corridor system somewhere to happen.
function Corridor.layProps(start: Vector3, finish: Vector3, axis: Vector3, across: Vector3, halfWidth: number)
	local floor = Instance.new("Part")
	floor.Name = "CorridorFloor"
	floor.Size = Vector3.new(BUILD.WidthStuds, 0.4, BUILD.LengthStuds)
	floor.CFrame = CFrame.lookAt(start + axis * (BUILD.LengthStuds / 2) - Vector3.new(0, 0.2, 0), start + axis * (BUILD.LengthStuds / 2) + axis)
	floor.Anchored = true
	floor.CanCollide = false
	floor.Color = Color3.fromRGB(198, 194, 186)
	floor.Material = Enum.Material.SmoothPlastic
	floor.TopSurface = Enum.SurfaceType.Smooth
	floor.BottomSurface = Enum.SurfaceType.Smooth
	floor.Parent = corridorFolder()

	-- Lockers down both sides. Cosmetic and the only cosmetic thing here, for the reason
	-- Config says: the corridor has to read as a school rather than as a box with people
	-- standing in it, and a bare strip of floor would read as neither.
	for side = -1, 1, 2 do
		for i = 1, BUILD.LockersPerWall do
			-- Spread across the run rather than from the mouth, so the two walls stay level
			-- with each other however many lockers are asked for.
			local share = (i - 0.5) / BUILD.LockersPerWall
			local at = start + axis * (BUILD.LengthStuds * share) + across * (halfWidth * side)
			buildBlock(`Locker{side}_{i}`, at, BUILD.LockerSize, Color3.fromRGB(118, 132, 124))
		end
	end

	-- A bench between each pair of stations, off to one side. Placed off-centre on purpose:
	-- a bench in the middle of the run would be the one thing in here the player has to
	-- walk around, and this room charges in length only.
	for i = 1, math.max(BUILD.StationCount - 1, 0) do
		local share = (i + 0.5) / (BUILD.StationCount + 1)
		local at = start + axis * (BUILD.LengthStuds * share) + across * (halfWidth * 0.55)
		buildBlock(`Bench{i}`, at, BUILD.BenchSize, Color3.fromRGB(146, 118, 86))
	end

end

-- The corridor as it stands, or nil if it has not been laid yet. Read rather than built
-- by callers that must not cause one to appear -- a debug command describing the corridor
-- should not be the thing that creates it.
function Corridor.Room(): CorridorRoom?
	return room
end

-- Takes the corridor down. The new-life path: a corridor is a room in a building and the
-- building outlives a life, but the folder is rebuilt around whichever school point the
-- next life walks into, and holding the old one would leave a hallway hanging off a
-- school that is no longer there.
function Corridor.Clear()
	local existing = folder
	if existing ~= nil then
		existing:Destroy()
	end
	folder = nil
	room = nil
end

return Corridor
