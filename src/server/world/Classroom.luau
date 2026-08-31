--!strict
-- The classroom, as a room that exists.
--
-- Until this file, a quiz subject -- Math, Reading -- had no room of its own. It opened
-- on the school's own forecourt the instant a player crossed AttendRadiusStuds, which is
-- the same ground the sign and the pad stand on: no walls, no desks, nothing to walk to.
-- That is what "the baseplate" meant. Science got a lab (Lab.luau) and Art got a studio
-- (Studio.luau) because each of those verbs needed a *thing* to walk to; a quiz's answers
-- travel with the player on a panel (Config.School.PhysicalLessons is false, and stays
-- false -- see the note on Config.School.Classroom for why this file does not reopen
-- that), so nothing about the quiz itself ever demanded a room. The entry gesture does.
-- Sitting down is the one-verb-one-commit every other subject already has, and a commit
-- needs somewhere to make it.
--
-- Built the same way Lab and Studio are: laid out in code around the school's own point
-- rather than authored as an asset, because the distances and the grid are the mechanic
-- (SchoolService gates a lesson's first question on the player actually being seated),
-- and a builder nudging a desk should not be able to quietly change what "seated" means.
--
-- Built once, shared, never taken down -- the same reason the lab and the studio never
-- come down. Any number of players can be in the room; a desk's seat can hold exactly
-- one, which the Roblox Seat instance already enforces on its own.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Ground = require(script.Parent.Ground)

local Classroom = {}

local CLASSROOM = Config.School.Classroom
local BUILD = CLASSROOM.Build

-- One desk, as the room hands it back. Position rather than parts, because everything
-- the service does with a desk is "is anybody in this seat" -- the parts themselves are
-- the client's business, not the loop's.
export type Desk = {
	id: number,
	seat: Seat,
}

export type ClassroomRoom = {
	center: Vector3,
	desks: { Desk },
}

-- The room, once it exists. Nil until Build succeeds; the whole module is a build-once,
-- because a classroom that re-laid itself would move a desk out from under whoever was
-- walking to it.
local room: ClassroomRoom? = nil
local folder: Folder? = nil

-- Desk ids the floor refused, kept so a refusal can name what is missing rather than the
-- room silently opening two desks short. Empty on a good build.
local missing: number = 0

local function classroomFolder(): Folder
	local existing = folder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "Classroom"
	made.Parent = workspace
	folder = made
	return made
end

-- A point on the room's grid, `share` studs out along `bearing` and `across` studs to
-- the right of it, both measured in world space rather than degrees -- a desk grid is
-- rows and columns, not a fan, and forcing it through onCircle the way Lab's stations do
-- would curve a row that is supposed to be straight.
local function onGrid(center: Vector3, bearing: number, distance: number, across: number): Vector3
	local direction = CFrame.Angles(0, math.rad(bearing), 0) * Vector3.new(0, 0, -1)
	local right = direction:Cross(Vector3.yAxis)
	return center + direction * distance + right * across
end

local function buildLabel(part: BasePart, text: string)
	local sign = Instance.new("BillboardGui")
	sign.Name = "Label"
	sign.Adornee = part
	sign.Size = UDim2.new(6, 0, 1.1, 0)
	sign.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 1.4, 0)
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

-- A classroom is an indoor room, for the same reason the lab and the studio are: laid on
-- the forecourt it would put its desks on the road. Raycast upward from the centre; no
-- ceiling within a storey means outdoors, and the room refuses rather than cluttering
-- the street.
local function ceilingAbove(center: Vector3, ignore: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local result = workspace:Raycast(center + Vector3.new(0, 2, 0), Vector3.new(0, 14, 0), params)
	return result ~= nil
end

local function buildDesk(id: number, at: Vector3, faceCenter: Vector3, ignore: { Instance }): (Desk?, ClickDetector?)
	local radius = math.max(CLASSROOM.DeskSize.X, CLASSROOM.DeskSize.Z) / 2 + 1
	local floor = Ground.SpotAt(at, radius, CLASSROOM.DeskSize.Y, ignore)
	if floor == nil then
		return nil, nil
	end

	local desk = Instance.new("Part")
	desk.Name = `Desk_{id}`
	desk.Size = CLASSROOM.DeskSize
	desk.CFrame = CFrame.lookAt(floor + Vector3.new(0, CLASSROOM.DeskSize.Y / 2, 0), floor + faceCenter + Vector3.new(0, CLASSROOM.DeskSize.Y / 2, 0))
	desk.Anchored = true
	desk.CanCollide = true
	desk.Color = Color3.fromRGB(150, 128, 96)
	desk.Material = Enum.Material.SmoothPlastic
	desk.TopSurface = Enum.SurfaceType.Smooth
	desk.BottomSurface = Enum.SurfaceType.Smooth
	desk.Parent = classroomFolder()
	buildLabel(desk, "Press L to sit")

	-- A little in front of the desk, on the side the player approaches from, rather than
	-- inside it. A Seat overlapping the desk it belongs to is a Seat a walking player
	-- clips through on their way past, and CanCollide is already off below for the other
	-- reason -- see the note there -- so overlap buys nothing and costs a visual glitch.
	local seatAt = floor - faceCenter * (CLASSROOM.DeskSize.Z / 2 + CLASSROOM.SeatSize.Z / 2)

	local seat = Instance.new("Seat")
	seat.Name = `DeskSeat_{id}`
	seat.Size = CLASSROOM.SeatSize
	seat.CFrame = CFrame.lookAt(
		seatAt + Vector3.new(0, CLASSROOM.SeatHeightStuds, 0),
		seatAt + faceCenter + Vector3.new(0, CLASSROOM.SeatHeightStuds, 0)
	)
	seat.Anchored = true
	-- Off deliberately. A Seat's own engine behaviour is to sit anybody who touches it,
	-- and this room's whole point is that sitting is a decision made with a key press --
	-- see SchoolService's `seated` gate -- not a thing that happens to a player who
	-- walked through the room on their way to a desk further back.
	seat.CanCollide = false
	seat.Color = Color3.fromRGB(96, 104, 118)
	seat.Material = Enum.Material.SmoothPlastic
	seat.Parent = classroomFolder()
	seat:SetAttribute("AgesDeskId", id)

	-- The click/tap half of "L, or a click on the desk" -- see the header on
	-- Interact.luau for why a phone needs this and a keyboard prompt alone does not. A
	-- ClickDetector's MouseClick already replicates server-side on its own, unlike a
	-- GuiButton, so this needs no client script to answer it, and it is wired straight
	-- to TrySit below rather than handed back to the caller -- a click on a desk and a
	-- press of L are the same request and must go through the same one door.
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = CLASSROOM.SitReachStuds
	click.Parent = desk

	return { id = id, seat = seat }, click
end

-- Builds the room around a centre point, once. Nil means it could not be laid at all,
-- which SchoolService turns into the quiz path falling back to no room rather than a
-- lesson that opens onto a grid with nowhere to sit.
function Classroom.Build(center: Vector3): ClassroomRoom?
	local existing = room
	if existing ~= nil then
		return existing
	end

	local ignore = Ground.IgnoreList()
	if not ceilingAbove(center, ignore) then
		return nil
	end

	local direction = CFrame.Angles(0, math.rad(BUILD.RowBearing), 0) * Vector3.new(0, 0, -1)
	local faceCenter = -direction

	local desks: { Desk } = {}
	local id = 0
	missing = 0
	for rowIndex = 1, CLASSROOM.Rows do
		local distance = CLASSROOM.RoomRadiusStuds * (BUILD.FirstRowDistanceShare + BUILD.RowDistanceStep * (rowIndex - 1))
		for columnIndex = 1, CLASSROOM.PerRow do
			id += 1
			local step = CLASSROOM.DeskSize.X + BUILD.DeskGapStuds
			local across = (columnIndex - (CLASSROOM.PerRow + 1) / 2) * step
			local at = onGrid(center, BUILD.RowBearing, distance, across)

			local desk, click = buildDesk(id, at, faceCenter, ignore)
			if desk == nil then
				missing += 1
				continue
			end
			if click ~= nil then
				-- Wired to TrySit directly rather than reaching back into SchoolService: a
				-- click on a desk and a press of L are the same request, and SchoolService's
				-- own tick already reads Classroom.IsSitting on its own clock, so nothing
				-- here needs to *tell* it a seating just happened.
				click.MouseClick:Connect(function(player: Player)
					Classroom.TrySit(player)
				end)
			end
			table.insert(desks, desk)
		end
	end

	local built: ClassroomRoom = { center = center, desks = desks }
	room = built
	return built
end

function Classroom.Room(): ClassroomRoom?
	return room
end

-- Desks the floor refused to build, as a count -- there is nothing to name them by that
-- a player would recognise, unlike Lab's stations, so a refusal here just says the room
-- came up short rather than listing which of eight identical desks is missing.
function Classroom.Missing(): number
	return missing
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil
	end
	return humanoid
end

-- The nearest open desk within reach of the player's own position, or nil if every desk
-- in reach already has somebody in it -- or nobody is in reach of one at all. Server-
-- resolved rather than client-named, on the same precedent as RequestRep: the player
-- presses one key, and which desk that means is this room's business, not theirs.
local function nearestOpenSeat(position: Vector3): Seat?
	local built = room
	if built == nil then
		return nil
	end
	local best: Seat? = nil
	local bestDistance = CLASSROOM.SitReachStuds
	for _, desk in built.desks do
		if desk.seat.Occupant ~= nil then
			continue
		end
		local distance = Ground.FlatDistance(position, desk.seat.Position)
		if distance <= bestDistance then
			best = desk.seat
			bestDistance = distance
		end
	end
	return best
end

-- Sits the player in the nearest open desk within reach, or refuses. The one entry point
-- for "the player wants to sit down", reached from the L key and from a desk's own
-- ClickDetector alike, so the two can never disagree about how close is close enough.
function Classroom.TrySit(player: Player): boolean
	local humanoid = humanoidOf(player)
	if humanoid == nil then
		return false
	end
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return false
	end

	local seat = nearestOpenSeat(root.Position)
	if seat == nil then
		return false
	end

	seat:Sit(humanoid)
	return true
end

-- Whether this player is, right now, sitting in one of this room's desks. Read from the
-- Seat's own Occupant rather than tracked separately, so a player who stood up by
-- jumping -- the ordinary way a Roblox Seat is left -- is caught the next tick without
-- this room needing to be told.
function Classroom.IsSitting(player: Player): boolean
	local built = room
	if built == nil then
		return false
	end
	local humanoid = humanoidOf(player)
	if humanoid == nil then
		return false
	end
	for _, desk in built.desks do
		if desk.seat.Occupant == humanoid then
			return true
		end
	end
	return false
end

-- Stands the player up. Called once a lesson is over so a desk frees itself rather than
-- staying claimed by a player reading their verdict, and safe to call on a player who is
-- not sitting at all -- Humanoid.Sit is a no-op false-to-false.
function Classroom.StandUp(player: Player)
	local humanoid = humanoidOf(player)
	if humanoid == nil then
		return
	end
	humanoid.Sit = false
end

return Classroom
