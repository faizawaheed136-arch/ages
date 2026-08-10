--!strict
-- Somewhere in this workplace you could actually stand.
--
-- Every task in a shift needs a patch of floor to put a mark on, and the only thing
-- that makes that hard is that nobody has told this code what the building looks
-- like. There is no list of shelves and no tagged part for the stockroom -- there is
-- a station the player clocked on at and a room around it that was built in Studio by
-- hand and may have been rearranged since.
--
-- So the spot is found rather than authored: fan out around the station, and take the
-- first bearing whose floor exists, has room for a body, and can be walked to in a
-- straight line. Exactly the three questions EnactService asks before it puts a
-- choice pad down, asked with the same Ground probes for the same reason -- they err
-- toward rejecting a tight spot, and a rejected spot costs a fallback while an
-- accepted bad one costs a player standing inside a wall being asked to sweep it.
--
-- What this buys is that a job gets tasks the moment the job exists. No parts to tag,
-- no offsets to measure, and a workplace that gets refurnished next month does not
-- silently start sending people into the new shelving.
--
-- Split from WorkService for the reason JobPosts was: where a mark can go and what
-- happens when you reach it are different questions, and re-tuning the search should
-- never be able to touch the wage loop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Ground = require(script.Parent.Ground)

local WorkSpots = {}

-- How far apart two marks in the same task must be, in multiples of the radius that
-- counts as reaching one.
--
-- Three rather than two, and the extra one is not slack. At two, the marks are only
-- as far apart as their own diameters, so a player standing on the near edge of the
-- first is exactly on the far edge of the second -- and a two-mark task would
-- complete itself on the following tick without anybody taking a step. Which is
-- precisely the thing "fetch it and bring it back" exists to make impossible.
local SEPARATION_REACHES = 3

-- How far out the search reaches, resolved once from the two numbers that describe
-- it. Kept well inside StationRadiusStuds because a mark painted beyond it would end
-- the player's own shift for walking out on it -- see the Config comment.
local function spreadStuds(): number
	return math.max(
		Config.Work.Tasks.MinSpreadStuds,
		Config.Work.StationRadiusStuds * Config.Work.Tasks.SpreadShareOfStation
	)
end

-- A patch of floor near `station` that a body could stand on and walk to, avoiding
-- anywhere in `avoid`.
--
-- `avoid` is the marks already placed for this task, so a two-mark task does not
-- paint both of them on the same tile and turn "fetch it and bring it back" into
-- standing still. Measured against the reach radius rather than any smaller figure,
-- because two marks a body's width apart are one mark as far as the player's feet are
-- concerned.
--
-- Nil means the room defeated the search: a stockroom too small to fan out in, or a
-- station somebody built facing a wall. The caller's job is to carry on without a
-- task rather than to place one badly, which is why this returns nil instead of
-- falling back to the station itself -- a mark under your feet teaches the player
-- that the marks can be ignored, and that lesson is much more expensive than a
-- missing task.
function WorkSpots.Find(character: Model, station: Vector3, avoid: { Vector3 }): Vector3?
	local tasks = Config.Work.Tasks
	local radius = Ground.BodyRadius(character)
	local height = Ground.BodyHeight(character)
	local ignore = Ground.IgnoreList()
	local spread = spreadStuds()

	-- Scattered rather than walked in order, so the same task at the same counter does
	-- not put its mark in the same corner every single time. The search is otherwise
	-- completely deterministic, and a shift where every task happens in one spot is a
	-- shift that stops being a room after about ninety seconds.
	local bearings = Ground.ScatteredBearings(tasks.SearchArcDegrees, tasks.SearchBearings)

	for _, bearing in bearings do
		local direction = CFrame.Angles(0, math.rad(bearing), 0) * Vector3.new(0, 0, -1)

		for _, step in tasks.SearchSteps do
			local distance = math.max(tasks.MinSpreadStuds, spread * step)

			-- Reachability measured from the station rather than from the player. The
			-- station is the fixed point of the shift and the player is wherever they
			-- happen to be standing; measuring from the player would let a spot be legal
			-- when they asked for it and unreachable two seconds later.
			local floor = Ground.SpotAt(station + direction * distance, radius, height, ignore, station)
			if floor == nil then
				continue
			end
			if not Ground.Apart(floor, avoid, tasks.ReachStuds * SEPARATION_REACHES) then
				continue
			end

			return floor
		end
	end

	return nil
end

-- Where somebody waiting on a task would stand, and where they walk in from.
--
-- Both measured out along the line from the station through the mark, so the player
-- steps onto the mark and finds the other person across it facing them. That line is
-- the only thing here that makes it read as a counter rather than as two people
-- standing near each other, and it needs no knowledge of the building at all: the
-- station is behind you because it is what you clocked on at, so anything beyond the
-- mark is the customer's side by definition.
--
-- Three answers, and the caller has to handle all three, because a task must never
-- fail for want of somewhere to put a person:
--
--   nil, nil        no room for them. Run the task alone, exactly as it ran before
--                   anybody was ever waiting on it.
--   stand, nil      room to stand, nowhere to come from. They appear where they
--                   stand -- worse than walking in, and much better than nothing.
--   stand, from     the whole thing.
--
-- Measured against Config.NPC's nominal body rather than a real one, for the reason
-- that config states: building an avatar is a web-backed call, and spawning a person
-- to discover there was nowhere for them to go is the wrong order to do it in.
function WorkSpots.Attend(station: Vector3, spot: Vector3): (Vector3?, Vector3?)
	local customers = Config.Work.Customers
	local ignore = Ground.IgnoreList()
	local radius = Config.NPC.BodyRadius
	local height = Config.NPC.BodyHeight

	local away = Vector3.new(spot.X - station.X, 0, spot.Z - station.Z)
	if away.Magnitude < 0.1 then
		-- The mark landed on top of the station, which the search is built to prevent.
		-- There is no "across the mark" from a point with no direction to it, and
		-- guessing one would put somebody behind the counter.
		return nil, nil
	end
	local outward = away.Unit

	-- Reachable from the mark rather than from the station: what matters is that the
	-- player and the person they are serving can see each other across it. A pillar
	-- between the counter and the customer is the one arrangement that would look broken.
	local standFloor = Ground.SpotAt(spot + outward * customers.StandOffStuds, radius, height, ignore, spot)
	if standFloor == nil then
		return nil, nil
	end

	-- Nil here is not a failure of the whole thing: somebody can stand across the mark
	-- with nowhere authored to walk in from, and the caller pops them into place. Which
	-- is why this is a second call rather than another way for the first to fail.
	local fromFloor =
		Ground.SpotAt(standFloor + outward * customers.ArriveFromStuds, radius, height, ignore, standFloor)
	return standFloor, fromFloor
end

-- Where a queue of `count` would stand, front first, and where they walk in from.
--
-- The same line as Attend, continued: the front stands across the mark, and everybody
-- else is a QueueSpacingStuds further back along it. So a queue points away from the
-- counter, which is the one arrangement that reads as a queue from any angle -- a
-- cluster of four people near a till reads as a crowd, and a crowd does not have a
-- front to serve.
--
-- Returns as many as fit and stops at the first slot that does not, rather than
-- skipping it and carrying on. A gap in the middle of a line is worse than a short
-- line: it looks like two queues, and the player has to guess which end is the front.
--
-- The list may be shorter than asked for and may be empty, and the caller has to cope
-- with both. Empty is not a failure -- it is the same answer Attend gives for a room
-- with no space beyond the mark, and it means the task runs with nobody in it.
function WorkSpots.Line(station: Vector3, spot: Vector3, count: number): ({ Vector3 }, Vector3?)
	local slots: { Vector3 } = {}
	if count < 1 then
		return slots, nil
	end

	local front, from = WorkSpots.Attend(station, spot)
	if front == nil then
		return slots, nil
	end
	table.insert(slots, front)
	if count == 1 then
		return slots, from
	end

	local customers = Config.Work.Customers
	local ignore = Ground.IgnoreList()
	local radius = Config.NPC.BodyRadius
	local height = Config.NPC.BodyHeight

	local away = Vector3.new(spot.X - station.X, 0, spot.Z - station.Z)
	if away.Magnitude < 0.1 then
		return slots, from
	end
	local outward = away.Unit

	for index = 2, count do
		local behind = front + outward * (customers.QueueSpacingStuds * (index - 1))

		-- Reachability checked back to the slot in front rather than to the counter. What
		-- matters for somebody third in line is that they can step up when the queue
		-- moves; whether they can see the till from where they are standing is exactly
		-- the thing about queueing that nobody enjoys, and is not a placement error.
		local floor = Ground.SpotAt(behind, radius, height, ignore, slots[index - 1])
		if floor == nil then
			break
		end

		table.insert(slots, floor)
	end

	-- Re-measured from the back of the line that actually formed, not from the front.
	-- Walking in to the point the first person came from would mean everybody after
	-- them appearing inside the queue and walking backwards out of it.
	local last = slots[#slots]
	local arriveFloor = Ground.SpotAt(last + outward * customers.ArriveFromStuds, radius, height, ignore, last)
	if arriveFloor == nil then
		return slots, from
	end

	return slots, arriveFloor
end

return WorkSpots
