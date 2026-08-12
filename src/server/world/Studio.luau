--!strict
-- The art room, as a room that exists.
--
-- Three things in it, and the whole subject is the distance between them: a wall with
-- the study on it, an easel a little way in front of the wall, and the paint cupboard
-- directly behind you when you are standing at the easel.
--
-- That last word is the layout. In the lab the board and the cupboard face each other so
-- the two errands cannot be batched into one trip; here there is only one errand, and it
-- is put behind the player so that fetching paint costs them *sight of the picture*
-- rather than costing them seconds. A cupboard beside the wall would be a free refill
-- with a walk animation on it. See Config.School.Art.RoomRadiusStuds for why the room is
-- half again the size of the lab: the mechanic is distance from the picture, and there is
-- nothing else to buy it with.
--
-- Split from ArtService for the reason Lab is split from ScienceService: where a thing
-- stands and what happens when you reach it are different questions, and re-laying the
-- room must never be able to touch the scoring.
--
-- Built once, shared, and never taken down -- and unlike the lab, what is *written* on
-- the furniture is shared too. The study on the wall is one picture that everybody in the
-- room is copying, because a wall can only hold one thing and pretending otherwise would
-- mean two players standing side by side seeing different paintings on the same parts.
-- The canvases are per player and pushed; the wall is the room's.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Pigments = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Pigments"))

local Studio = {}

local ART = Config.School.Art
local BUILD = ART.Build

local COLUMNS = ART.Columns
local ROWS = ART.Rows

-- What a built room hands back. Positions for the things the loop measures against, and
-- the wall's own parts, because the wall is the one piece of furniture whose *appearance*
-- is state -- a study shifting is a part changing colour, and something has to hold them.
export type ArtRoom = {
	center: Vector3,
	easel: Vector3,
	cupboard: Vector3,
	-- One part per cell, indexed the way a study's cells are: left to right, then top to
	-- bottom. The same index means the same square on the wall, in the session and on the
	-- player's canvas, with nothing mapping between them.
	wall: { BasePart },
}

local room: ArtRoom? = nil
local folder: Folder? = nil
local titleLabel: TextLabel? = nil

-- Everything the art room puts in the world lives in one folder, the same arrangement the
-- lab makes and separate from it because the two get cleared for different reasons.
local function studioFolder(): Folder
	local existing = folder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "ArtRoom"
	made.Parent = workspace
	folder = made
	return made
end

-- A point on the room's circle, in the same terms Lab.onCircle uses, so a layout number
-- here and a layout number there mean the same thing.
local function onCircle(center: Vector3, bearing: number, share: number): Vector3
	local direction = CFrame.Angles(0, math.rad(bearing), 0) * Vector3.new(0, 0, -1)
	return center + direction * (ART.RoomRadiusStuds * share)
end

-- One piece of placeholder furniture, sat on the floor rather than centred in it.
-- Non-collidable for the reason the lab's is: a player who has to walk around the easel
-- to reach the cupboard is being charged for the room twice, and it is the distances that
-- are supposed to cost something rather than the geometry.
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
	part.Parent = studioFolder()
	return part
end

-- The name over a piece of furniture, built in the world rather than pushed, because what
-- a thing *is* is true for everybody standing in the room. Handed back so the wall's own
-- label can be rewritten when the study changes -- the only one of these that ever moves.
local function buildLabel(part: BasePart, text: string, width: number): TextLabel
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
	return label
end

-- Builds the room around a centre point, once. Nil means it could not be laid at all,
-- which the caller turns into Art refusing at the door with a reason rather than into a
-- lesson that opens onto nothing.
function Studio.Build(center: Vector3): ArtRoom?
	local existing = room
	if existing ~= nil then
		return existing
	end

	local wallAt = onCircle(center, BUILD.WallBearing, BUILD.WallDistanceShare)
	local easelAt = onCircle(center, BUILD.EaselBearing, BUILD.EaselDistanceShare)
	local cupboardAt = onCircle(center, BUILD.CupboardBearing, BUILD.CupboardDistanceShare)

	-- Which way the wall faces, and which way is right along it from the player's side.
	-- Flattened first: a room laid on a slope would otherwise tilt the whole picture, and
	-- a study read at an angle is a study read wrong.
	local flat = Vector3.new(center.X - wallAt.X, 0, center.Z - wallAt.Z)
	if flat.Magnitude < 1 then
		-- Only reachable by putting the wall on top of the room's own centre, which means
		-- the layout shares in Config have been edited into nonsense. Said out loud rather
		-- than divided by zero.
		return nil
	end
	local faceCenter = flat.Unit
	-- The direction a player at the easel is looking, and their right hand from there.
	local look = -faceCenter
	local right = look:Cross(Vector3.yAxis)

	local step = BUILD.WallCellStuds + BUILD.WallCellGapStuds
	local width = COLUMNS * step
	local height = ROWS * step

	-- A dark panel behind the grid, sized a little past it. Not decoration: without it the
	-- study is a set of squares floating in whatever happens to be behind the room, and
	-- the first thing the player has to do is work out where the picture ends.
	local backing = Instance.new("Part")
	backing.Name = "StudyBacking"
	backing.Size = Vector3.new(width + step * 0.5, height + step * 0.5, BUILD.WallDepthStuds)
	backing.CFrame = CFrame.lookAt(
		wallAt + Vector3.new(0, BUILD.WallLiftStuds + height / 2, 0) - faceCenter * BUILD.WallDepthStuds,
		wallAt + Vector3.new(0, BUILD.WallLiftStuds + height / 2, 0) + faceCenter
	)
	backing.Anchored = true
	backing.CanCollide = false
	backing.Color = Color3.fromRGB(28, 28, 32)
	backing.Material = Enum.Material.SmoothPlastic
	backing.Parent = studioFolder()

	titleLabel = buildLabel(backing, "Study", 8)

	local wall: { BasePart } = {}
	for rowIndex = 1, ROWS do
		for columnIndex = 1, COLUMNS do
			-- Centred on the wall point: the middle of the grid sits on the bearing, so a
			-- study of any width is laid symmetrically about the same spot and widening the
			-- picture does not slide it off to one side.
			local across = (columnIndex - (COLUMNS + 1) / 2) * step
			local up = ((ROWS + 1) / 2 - rowIndex) * step
			local at = wallAt + right * across + Vector3.new(0, BUILD.WallLiftStuds + height / 2 + up, 0)

			local cell = Instance.new("Part")
			cell.Name = `Cell_{(rowIndex - 1) * COLUMNS + columnIndex}`
			cell.Size = Vector3.new(BUILD.WallCellStuds, BUILD.WallCellStuds, BUILD.WallDepthStuds)
			cell.CFrame = CFrame.lookAt(at, at + faceCenter)
			cell.Anchored = true
			cell.CanCollide = false
			-- Flat and unlit rather than plastic, because the one thing the player is doing
			-- all lesson is judging a colour, and a study that shades differently on its
			-- left than its right would be asking them to judge the room's lighting instead.
			cell.Material = Enum.Material.Neon
			cell.Color = Color3.fromRGB(28, 28, 32)
			cell.Parent = studioFolder()

			wall[(rowIndex - 1) * COLUMNS + columnIndex] = cell
		end
	end

	local easelPart = buildBlock("Easel", easelAt, BUILD.EaselSize, Color3.fromRGB(140, 112, 78))
	buildLabel(easelPart, "Easel", 5)

	local cupboardPart = buildBlock("PaintCupboard", cupboardAt, BUILD.CupboardSize, Color3.fromRGB(150, 128, 96))
	buildLabel(cupboardPart, "Paint", 5)

	local built: ArtRoom = {
		center = center,
		easel = easelAt,
		cupboard = cupboardAt,
		wall = wall,
	}
	room = built
	return built
end

-- The room, or nil if nothing has built it yet. Never builds as a side effect: the caller
-- that owns the place point is the one that decides the art room exists.
function Studio.Room(): ArtRoom?
	return room
end

-- Puts a whole study up. Called when the wall is free and somebody starts a lesson.
function Studio.Show(title: string, cells: { Pigments.Pigment })
	local built = room
	if built == nil then
		return
	end
	local label = titleLabel
	if label ~= nil then
		label.Text = title
	end
	for index, part in built.wall do
		local pigment = cells[index]
		if pigment ~= nil then
			part.Color = pigment.color
		end
	end
end

-- Changes one square. This is a study shifting, and it is deliberately the whole of what
-- that looks like from the world's side: a part changes colour and nothing announces it.
-- A sound or a flash here would tell every player in the room exactly which cell to go and
-- look at, which is the one thing this subject is about finding out for yourself.
function Studio.SetCell(index: number, pigment: Pigments.Pigment)
	local built = room
	if built == nil then
		return
	end
	local part = built.wall[index]
	if part == nil then
		return
	end
	part.Color = pigment.color
end

-- Blanks the wall back to its unlit state, for when the last painter leaves. A study left
-- hanging would be the next lesson's picture already half-solved for anybody who walked
-- past the room -- and, more simply, an empty art room should look like one.
function Studio.Clear()
	local built = room
	if built == nil then
		return
	end
	local label = titleLabel
	if label ~= nil then
		label.Text = "Study"
	end
	for _, part in built.wall do
		part.Color = Color3.fromRGB(28, 28, 32)
	end
end

return Studio
