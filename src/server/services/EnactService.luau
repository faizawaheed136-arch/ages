--!strict
-- Answering an event by doing it. When an event is authored Enacted, this puts
-- its choices on the floor around the player as places to stand, watches for one
-- of them being reached, and applies it.
--
-- The division of labour is the one the rest of the event chain already uses.
-- EventService alone decides which event fires and alone validates an answer;
-- this decides only *where the choices are* and *that the player got there*.
-- Every answer it produces goes through EventService.ResolveChoice, the same
-- function the panel's remote lands in, so there is exactly one place that can
-- pay out a choice and enactment cannot become a second way to cheat one.
--
-- Server-side proximity, matching WorldEventService: the client is never asked
-- where it is standing. That matters more here than anywhere else, because here
-- standing somewhere *is* the choice.
--
-- The whole system is best-effort by design. A room that cannot hold the markers
-- is common -- a corner, a stairwell, a player standing in a doorway -- so
-- failing to place them is an ordinary outcome, not an error, and the event falls
-- back to the panel it would have been. Enactment may never be the reason an
-- event cannot be answered.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local ChoiceMarkers = require(script.Parent.Parent.world.ChoiceMarkers)

type LifeEvent = Types.LifeEvent
type ChoiceMarker = ChoiceMarkers.ChoiceMarker

local EnactService = {}

-- One folder for every marker in play, so a leak shows up as a fat folder in the
-- explorer rather than as parts scattered through the house.
local MARKERS_FOLDER = "AgesChoices"

-- A character mid-spawn can report an extents size of nearly zero, and a
-- zero-sized clearance box finds nothing and therefore passes everything. These
-- are the floor under that reading rather than tunables: roughly a crawling
-- toddler, which is the smallest body the game actually has.
local MIN_BODY_HEIGHT = 1.2
local MIN_BODY_WIDTH = 1.0

-- How far above a candidate the floor probe starts and how far below it gives
-- up. Generous downward so a marker can land on a step or a slightly lower floor,
-- bounded so it cannot find the storey below through a gap.
local PROBE_UP = 6
local PROBE_DOWN = 12

-- Lifted off the floor before the box is swept, so the floor the marker stands on
-- is not itself counted as the thing blocking it.
local CLEARANCE_LIFT = 0.2

type Active = {
	eventId: string,
	event: LifeEvent,
	markers: { [string]: ChoiceMarker },
	-- What the markers were actually drawn at, which is not Config.Enact.MarkerRadius
	-- when the spread had to be drawn in. Stored so that standing on a marker is
	-- tested against the disc the player can see rather than against the size one
	-- would have been at full spread.
	radius: number,
	-- os.clock() deadline, or nil when the fallback is switched off. In memory
	-- rather than in the profile: an enactment does not survive a rejoin, so a
	-- deadline that did would be counting down against nothing.
	expiresAt: number?,
}

local active: { [Player]: Active } = {}

-- Debug switch for the Studio harness, never touched in a live server. Off means
-- every event resolves on a panel, which is also the state to put the game in
-- while testing something that has nothing to do with enactment.
local enabled = true

local function markersFolder(): Folder
	local existing = workspace:FindFirstChild(MARKERS_FOLDER)
	if existing ~= nil then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = MARKERS_FOLDER
	folder.Parent = workspace
	return folder
end

local function clearMarkers(current: Active)
	for _, marker in current.markers do
		marker.destroy()
	end
	table.clear(current.markers)
end

-- Ends an enactment without answering it. Callers that also need the prompt dealt
-- with do that themselves -- this only takes the choices out of the room.
local function stop(player: Player)
	local current = active[player]
	if current == nil then
		return
	end
	active[player] = nil
	clearMarkers(current)
end

local function bodyHeight(character: Model): number
	return math.max(character:GetExtentsSize().Y, MIN_BODY_HEIGHT)
end

-- What has to fit, as opposed to what is drawn. A marker's disc may overhang a
-- table leg -- the player stands in the middle of it, not on its edge -- so
-- testing the whole disc for clearance would reject most of a furnished room for
-- no reason. Taken from the character rather than fixed, so a crawling toddler
-- can be offered spots an adult could not stand in, which is correct: they are a
-- different size and the house is the same house.
local function bodyRadius(character: Model): number
	local extents = character:GetExtentsSize()
	return math.max(extents.X, extents.Z, MIN_BODY_WIDTH) / 2
end

-- Everything a probe must look straight through: the player themselves, the
-- markers already placed, and anything else a player is standing in. Rebuilt per
-- placement because the set of characters changes.
local function ignoreList(): { Instance }
	local ignore: { Instance } = { markersFolder() }
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if character ~= nil then
			table.insert(ignore, character)
		end
	end
	return ignore
end

-- The floor under a candidate, or nil if there isn't one. Returned rather than
-- assumed because the fan is drawn on a flat plane through the player and the
-- house is not flat: a candidate can hang over a stairwell or off the edge of an
-- upstairs floor, and a marker floating in the air is a choice nobody can take.
local function floorUnder(candidate: Vector3, ignore: { Instance }): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	-- Rugs, mats and delivery markers are non-colliding, and a probe that stopped
	-- on one would place the marker on the rug's *surface* rather than on the
	-- floor it is lying on. Half a stud, but it is the difference between a pad
	-- painted on the floor and one hovering over it.
	params.RespectCanCollide = true

	local from = candidate + Vector3.new(0, PROBE_UP, 0)
	local result = workspace:Raycast(from, Vector3.new(0, -(PROBE_UP + PROBE_DOWN), 0), params)
	if result == nil then
		return nil
	end
	return result.Position
end

-- Whether a body could actually stand at this spot. Bounding boxes rather than
-- exact geometry, which errs toward rejecting a tight spot -- the right way to be
-- wrong, since the cost of rejecting one is a panel and the cost of accepting one
-- is a choice the player can see and cannot take.
local function standable(at: Vector3, radius: number, height: number, ignore: { Instance }): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	-- Non-colliding parts are rugs, mats, delivery markers and the like: things a
	-- body passes through, which is exactly what standing on them means. Skipped
	-- by the query rather than filtered out of its results, so a room full of soft
	-- furnishings costs nothing to sweep.
	params.RespectCanCollide = true
	-- One is all the answer needed: any collidable part in the box means no.
	params.MaxParts = 1

	local center = at + Vector3.new(0, CLEARANCE_LIFT + height / 2, 0)
	local box = Vector3.new(radius * 2, height, radius * 2)
	return #workspace:GetPartBoundsInBox(CFrame.new(center), box, params) == 0
end

-- Whether the player could walk there in a straight line. Not a path test -- a
-- single ray at chest height, which is enough to catch the failure that actually
-- matters: a marker placed on the far side of a wall, visible through the label's
-- AlwaysOnTop and completely unreachable.
local function reachable(from: Vector3, to: Vector3, height: number, ignore: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	params.RespectCanCollide = true

	local lift = Vector3.new(0, height / 2, 0)
	local start = from + lift
	local finish = to + lift
	return workspace:Raycast(start, finish - start, params) == nil
end

-- How wide a marker may be at this spread without touching its neighbour. The
-- fan gets tighter as the spread comes in, so a fixed radius would have the
-- markers overlapping on the retry -- and two overlapping answers is worse than
-- no answer at all, because the player cannot tell which one they are standing
-- on. Shrinking them instead keeps what is drawn identical to what is measured.
local function reachRadius(count: number, spread: number): number
	local step = math.rad(Config.Enact.FanDegrees / (count - 1))
	local gap = 2 * spread * math.sin(step / 2)
	return math.min(Config.Enact.MarkerRadius, gap / 2)
end

type Placement = {
	positions: { [string]: Vector3 },
	radius: number,
}

-- Where the choices would stand, or nil if this spread cannot hold all of them.
-- All or nothing on purpose: two markers out of three is not a reduced choice, it
-- is a broken one, and the player would have no way to tell which it was.
local function fan(character: Model, event: LifeEvent, spread: number): Placement?
	local pivot = character:GetPivot()
	local origin = pivot.Position

	-- Flattened, because the fan lies on the floor and a player looking at their
	-- feet or up the stairs must not tip the whole arrangement over.
	local forward = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
	if forward.Magnitude < 1e-3 then
		return nil
	end
	forward = forward.Unit

	local count = #event.choices
	local height = bodyHeight(character)
	local radius = bodyRadius(character)
	local ignore = ignoreList()
	local positions: { [string]: Vector3 } = {}

	for index, choice in event.choices do
		-- Evenly across the fan, centered on the way the player is facing. A single
		-- choice would sit dead ahead; content validation guarantees at least two,
		-- so the divisor is never zero.
		local step = Config.Enact.FanDegrees / (count - 1)
		local angle = -Config.Enact.FanDegrees / 2 + (index - 1) * step
		local direction = CFrame.Angles(0, math.rad(angle), 0) * forward
		local candidate = origin + direction * spread

		local ground = floorUnder(candidate, ignore)
		if ground == nil then
			return nil
		end
		if not standable(ground, radius, height, ignore) then
			return nil
		end
		if not reachable(origin, ground, height, ignore) then
			return nil
		end

		positions[choice.id] = ground
	end

	return { positions = positions, radius = reachRadius(count, spread) }
end

-- Called by EventService at the moment a prompt opens, and the answer decides
-- what the client is told. Returns false for every ordinary reason a room cannot
-- hold the choices, so callers must not treat false as a fault: it means "this
-- one is a panel", which is always a valid answer.
local function begin(player: Player, event: LifeEvent): boolean
	if not enabled then
		return false
	end

	local character = player.Character
	if character == nil then
		return false
	end

	stop(player)

	-- Full spread first, then drawn in once. Two attempts rather than a search:
	-- the difference between them is the difference between a room and a corner,
	-- and anywhere that fails both is somewhere the player should be handed a
	-- panel rather than made to shuffle around looking for space.
	local placed = fan(character, event, Config.Enact.MarkerSpread)
	if placed == nil then
		placed = fan(character, event, Config.Enact.MarkerSpread * Config.Enact.RetrySpreadScale)
	end
	if placed == nil then
		return false
	end

	local folder = markersFolder()
	local markers: { [string]: ChoiceMarker } = {}
	for _, choice in event.choices do
		local at = placed.positions[choice.id]
		markers[choice.id] = ChoiceMarkers.Build(folder, at, choice.label, placed.radius)
	end

	active[player] = {
		eventId = event.id,
		event = event,
		markers = markers,
		radius = placed.radius,
		-- 0 means the fallback is off, which is a testing state only -- see the
		-- safe range on SecondsToChoose.
		expiresAt = if Config.Enact.SecondsToChoose > 0
			then os.clock() + Config.Enact.SecondsToChoose
			else nil,
	}
	return true
end

-- Which marker the player is standing on, if any. Height is part of the test
-- because the storeys of this house sit above each other: without it, walking
-- over the spot upstairs would answer a question asked in the hall.
local function markerUnder(player: Player, current: Active): string?
	local character = player.Character
	if character == nil then
		return nil
	end

	local here = character:GetPivot().Position
	for choiceId, marker in current.markers do
		local to = marker.position
		if math.abs(here.Y - to.Y) > Config.Enact.ReachHeightStuds then
			continue
		end
		local flat = Vector2.new(here.X - to.X, here.Z - to.Z)
		if flat.Magnitude <= current.radius then
			return choiceId
		end
	end
	return nil
end

-- Answering a childhood event ends the year, and the birthday that follows may
-- offer -- and enact -- the next one immediately. Adding a key to `active` while
-- it is being traversed is undefined in Lua, so the traversal decides and this
-- list acts, strictly afterwards. `answer` nil means "fall back to the panel".
type Verdict = { player: Player, eventId: string, answer: string? }

local function tick()
	if next(active) == nil then
		return
	end

	local verdicts: { Verdict } = {}

	for player, current in active do
		-- The prompt is the authority, not this table. An event answered on a
		-- panel, a player who died, a life that ended, a profile that went away --
		-- all of them show up here as "the pending id is no longer mine", so there
		-- is one condition to get right instead of a subscription to every service
		-- that could have ended it. Clearing keys mid-traversal is safe; adding is
		-- what the list above exists to avoid.
		local profile = DataService.GetProfile(player)
		if profile == nil or not profile.Data.alive or profile.Data.pendingEventId ~= current.eventId then
			stop(player)
			continue
		end

		local choiceId = markerUnder(player, current)
		if choiceId ~= nil then
			-- Taken down before the answer is applied. Resolving fires the outcome
			-- to the client, and markers still standing under an outcome would
			-- invite a second walk onto a question that has already been answered.
			stop(player)
			table.insert(verdicts, { player = player, eventId = current.eventId, answer = choiceId })
		elseif current.expiresAt ~= nil and os.clock() >= current.expiresAt then
			-- The prompt stays open; only the way of answering it changes. The
			-- player has not lost anything and is not told off for taking too long
			-- -- the panel simply appears and the choices are still all there.
			stop(player)
			table.insert(verdicts, { player = player, eventId = current.eventId, answer = nil })
		end
	end

	for _, verdict in verdicts do
		if verdict.answer ~= nil then
			EventService.ResolveChoice(verdict.player, verdict.eventId, verdict.answer)
		else
			EventService.FallBackToPanel(verdict.player, verdict.eventId)
		end
	end
end

-- Studio harness: what is standing in the room right now.
function EnactService.Describe(player: Player): string
	local current = active[player]
	if current == nil then
		return `nothing enacted | enactment {if enabled then "on" else "off"}`
	end

	local ids: { string } = {}
	for choiceId in current.markers do
		table.insert(ids, choiceId)
	end
	table.sort(ids)

	local remaining = if current.expiresAt ~= nil
		then string.format("%.0fs left", math.max(0, current.expiresAt - os.clock()))
		else "no timeout"
	-- The radius is reported because it is the visible sign of a tight room: below
	-- Config.Enact.MarkerRadius means the fan had to be drawn in, which is worth
	-- knowing when a spot feels fiddly to stand on.
	local size = string.format("r%.1f", current.radius)
	return `"{current.eventId}" | markers: {table.concat(ids, ", ")} ({size}) | {remaining}`
end

function EnactService.SetEnabled(value: boolean)
	enabled = value
	if value then
		return
	end
	-- Switching off mid-enactment leaves a prompt that can only be answered by
	-- walking onto markers that are about to stop being watched. Hand each one
	-- back to its panel rather than stranding it. Collected first for the reason
	-- tick() collects: falling back must not run inside the traversal.
	local stranded: { { player: Player, eventId: string } } = {}
	for player, current in active do
		table.insert(stranded, { player = player, eventId = current.eventId })
	end
	for _, entry in stranded do
		stop(entry.player)
		EventService.FallBackToPanel(entry.player, entry.eventId)
	end
end

function EnactService:Init()
	-- Injected rather than required the other way around: EventService is what
	-- this calls to resolve a choice, so it must not know about this file.
	EventService.SetEnactHandler(begin)
end

function EnactService:Start()
	Players.PlayerRemoving:Connect(stop)

	task.spawn(function()
		while true do
			task.wait(Config.Enact.TickSeconds)
			tick()
		end
	end)
end

return EnactService
