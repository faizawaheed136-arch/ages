--!strict
-- The science lab, as a room that exists.
--
-- Everything about the Science verb is a journey between things, so the things have to
-- be somewhere. This puts them there: a board on one side, a supply cupboard directly
-- opposite it, the benches on the cross axis between the two, and the stations ringing
-- the outside further out than any of them. That arrangement is the mechanic in
-- physical form -- see the note on Config.School.Science.Build for why each fraction is
-- what it is -- and it is the reason the room is laid out here rather than being tagged
-- part by part in Studio: the distances between these five kinds of thing are load
-- bearing, and a builder nudging a bench should not be able to quietly delete the walk
-- that makes committing early a decision.
--
-- Split from ScienceService for the reason WorkSpots was split from WorkService: where
-- a thing can stand and what happens when you reach it are different questions, and
-- re-laying the room should never be able to touch the scoring.
--
-- Built once, shared, and never taken down. Two players in the lab stand in one room --
-- the same way two players sit in one classroom -- because the furniture is a thing
-- anybody walking past can see, and it is only what is *written* on it that is
-- addressed to one person. The stack on a bench and the list on the board are pushed
-- per player and drawn by their own client; nothing about a procedure is in the world.
-- That is the rule Remotes.luau states, applied to a room instead of a sign.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Interact = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Interact"))
local Stations = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Stations"))

local Ground = require(script.Parent.Ground)

type Procedure = Types.Procedure

local Lab = {}

local SCIENCE = Config.School.Science
local BUILD = SCIENCE.Build

-- What a built lab hands back. Positions rather than parts, because everything the
-- service does with the room is a distance test -- the parts themselves are the
-- client's business and the builder's, not the loop's.
export type LabRoom = {
	center: Vector3,
	board: Vector3,
	cupboard: Vector3,
	-- Indexed the way BenchState.index is, so bench 2 here and bench 2 on screen are the
	-- same piece of furniture without anything having to map between them.
	benches: { Vector3 },
	-- Where each station ended up. A station that the floor refused is simply absent,
	-- and callers must treat absence as "this procedure cannot be run" and say so by
	-- name rather than offering a procedure with an unreachable step in it.
	stations: { [string]: Vector3 },
}

-- The room, once it exists. Nil until Build succeeds; the whole module is a
-- build-once, because a lab that re-laid itself would move a station out from under a
-- player who was walking to it.
local room: LabRoom? = nil
local folder: Folder? = nil

-- Stations the floor refused, kept so the refusal can name them. A warning at build
-- time scrolls past; a player told "the lab is missing its balance" can go and look.
local missing: { string } = {}

-- Everything the lab puts in the world lives in one folder, so a Studio session can see
-- at a glance what is standing and clear the lot if a test left something behind. The
-- same arrangement school makes for its pads, and separate from it because these two
-- get cleared for different reasons.
local function labFolder(): Folder
	local existing = folder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "ScienceLab"
	made.Parent = workspace
	folder = made
	return made
end

-- A point on the room's circle. Bearing is degrees clockwise from world forward, which
-- is the same convention Ground.Bearings uses, so a layout number here and a scatter
-- there mean the same thing.
local function onCircle(center: Vector3, bearing: number, share: number): Vector3
	local direction = CFrame.Angles(0, math.rad(bearing), 0) * Vector3.new(0, 0, -1)
	return center + direction * (SCIENCE.RoomRadiusStuds * share)
end

-- One piece of placeholder furniture. Anchored and non-collidable: a player who has to
-- walk round a bench to reach a station is being charged for the room twice, and the
-- whole point of the layout is that the *distances* cost something rather than the
-- geometry.
local function buildBlock(name: string, at: Vector3, size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	-- Sat on the floor rather than centred on it, so a six-stud cupboard is six studs
	-- tall standing up instead of three studs of it being underground.
	part.CFrame = CFrame.new(at + Vector3.new(0, size.Y / 2, 0))
	part.Anchored = true
	part.CanCollide = false
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = labFolder()
	return part
end

-- The name over a piece of furniture. Built in the world rather than pushed, because
-- what a station *is* is true for everybody in the room -- it is only what the
-- procedure wants from it that is addressed to one player.
local function buildLabel(part: BasePart, text: string)
	local sign = Instance.new("BillboardGui")
	sign.Name = "Label"
	sign.Adornee = part
	sign.Size = UDim2.new(5, 0, 1.1, 0)
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

-- Somewhere a station can stand: on the ring first, then nudged outward a ring at a
-- time. Nil means the floor refused it everywhere tried, which the caller records by
-- name rather than swallowing -- a station that is not in the room is a step that
-- cannot be taken, and a procedure with one of those in it is unfinishable.
local function stationSpot(center: Vector3, bearing: number, ignore: { Instance }, taken: { Vector3 }): Vector3?
	local size = BUILD.StationSize
	-- Probed as a body would be, because a station the player cannot get to the side of
	-- is a station they cannot click. The gap wanted is its own width plus room to stand.
	local radius = math.max(size.X, size.Z) / 2 + SCIENCE.StationRadiusStuds
	for retry = 0, BUILD.StationRetries do
		local share = BUILD.StationDistanceShare + BUILD.StationRetryShare * retry
		local candidate = onCircle(center, bearing, share)
		local floor = Ground.SpotAt(candidate, radius, size.Y, ignore, center)
		if floor == nil then
			continue
		end
		-- Two stations within reach of each other is one station as far as the player's
		-- clicking is concerned, and it would make the wrong one answer for the right one.
		if not Ground.Apart(floor, taken, SCIENCE.StationRadiusStuds * 2 + 1) then
			continue
		end
		return floor
	end
	return nil
end

-- Builds the room around a centre point, once. Returns nil if the lab could not be
-- laid at all, which is a different failure from a station or two going missing and is
-- reported differently: no room means no Science anywhere, and the caller refuses at
-- the door.
function Lab.Build(center: Vector3): LabRoom?
	local existing = room
	if existing ~= nil then
		return existing
	end

	local ignore = Ground.IgnoreList()

	local board = onCircle(center, BUILD.BoardBearing, BUILD.BoardDistanceShare)
	local cupboard = onCircle(center, BUILD.CupboardBearing, BUILD.CupboardDistanceShare)

	local boardPart = buildBlock("Board", board, BUILD.BoardSize, Color3.fromRGB(48, 58, 52))
	buildLabel(boardPart, "Procedure")

	local cupboardPart = buildBlock("Cupboard", cupboard, BUILD.CupboardSize, Color3.fromRGB(150, 128, 96))
	buildLabel(cupboardPart, "Supplies")

	local benches: { Vector3 } = {}
	for index = 1, SCIENCE.Benches do
		local bearing = BUILD.FirstBenchBearing + BUILD.BenchBearingStep * (index - 1)
		local at = onCircle(center, bearing, BUILD.BenchDistanceShare)
		local part = buildBlock(`Bench{index}`, at, BUILD.BenchSize, Color3.fromRGB(96, 104, 118))
		buildLabel(part, `Bench {index}`)
		table.insert(benches, at)
	end

	-- Every station that any procedure names, laid in one even ring. All of them rather
	-- than only the ones this player's mastery has unlocked: the room is shared, built
	-- once, and cannot be re-laid per player -- so escalation is which stations a
	-- *procedure* uses, not which ones are standing. A player at mastery one walks past
	-- five stations they will not touch today, which is the correct thing for a school
	-- lab to look like anyway.
	local all = Stations.All
	local bearings = Ground.Bearings(360, #all)
	local stations: { [string]: Vector3 } = {}
	local taken: { Vector3 } = {}
	table.clear(missing)

	for index, station in all do
		local spot = stationSpot(center, bearings[index], ignore, taken)
		if spot == nil then
			table.insert(missing, station.id)
			continue
		end
		table.insert(taken, spot)
		stations[station.id] = spot

		local part = buildBlock(`Station_{station.id}`, spot, BUILD.StationSize, station.color)
		buildLabel(part, station.name)

		-- The three dots. A station is a thing in the room you go to, which is exactly
		-- what dots mean -- and it carries no price and opens no menu, because clicking
		-- it *is* the answer. What it does to your procedure is written on the board
		-- across the room, which is the whole verb.
		--
		-- Attached lit, and then turned down per player by the client -- see
		-- client/world/LabDots.luau. It has to be done at that end: the lab is one room
		-- shared by everybody in the school, so the server cannot dim a beaker for the
		-- player with no lesson on without dimming it for the one who has.
		--
		-- Which leaves the *name* doing the work in between, and that is the reason this
		-- reads as a room rather than as furniture appearing around you. The label built
		-- on the line above is part of the fixture and never goes anywhere, so a lab out
		-- of hours is still a legible room full of named equipment. It simply stops
		-- promising that any of it can be used -- which is what three dots mean, and the
		-- only thing they mean.
		Interact.Attach(part, {
			kind = "Station",
			id = station.id,
			actionText = "Use",
			objectText = station.name,
		})
	end

	local built: LabRoom = {
		center = center,
		board = board,
		cupboard = cupboard,
		benches = benches,
		stations = stations,
	}
	room = built
	return built
end

-- The room, or nil if nothing has built it yet. Never builds as a side effect: the
-- caller that owns the place point is the one that decides the lab exists.
function Lab.Room(): LabRoom?
	return room
end

-- Station ids the floor refused, so a refusal can name them. Empty on a good build,
-- which is the case worth optimising the sentence for.
function Lab.Missing(): { string }
	return missing
end

-- Whether every station a procedure needs is actually standing. Asked before a
-- procedure is handed out rather than discovered part way through it: a player four
-- steps into a procedure whose fifth station does not exist has lost the run to a build
-- error, and no amount of soft failure makes that fair.
function Lab.CanRun(procedure: Procedure): (boolean, string?)
	local built = room
	if built == nil then
		return false, "the lab has not been built yet"
	end
	for _, step in procedure.steps do
		if built.stations[step.station] == nil then
			return false, `the lab has no {Stations.NameOf(step.station)} standing in it`
		end
	end
	return true, nil
end

return Lab
