--!strict
-- "Could a body be here, and could you get to it from there?" — the three probes
-- every system that puts something on the floor has to run before it does.
--
-- Extracted from EnactService, which asked these questions first and still asks
-- them the most. SceneService asks the identical questions about a different kind
-- of body, and two copies of a raycast whose *filter flags* carry the reasoning
-- would drift the moment one of them was tuned. The comments below are the real
-- payload of this file: each flag on each query is a decision that took a bug to
-- find, and they belong in one place.
--
-- Everything here is a bounding-box or single-ray approximation, which errs
-- toward rejecting a tight spot. That is the right way to be wrong for every
-- caller so far: the cost of rejecting a good spot is a fallback, and the cost of
-- accepting a bad one is something standing in a wall.

local Players = game:GetService("Players")

local Ground = {}

-- Distance ignoring height, which is the only distance this game ever actually means.
--
-- Every "am I near it" in the codebase is a question about the floor: the player standing
-- on a stair one step above a task mark is *at* the task mark as far as anyone playing is
-- concerned, and true 3D distance would say otherwise and refuse them the thing they are
-- standing on. Reaches are tuned in studs across a room, never up it.
--
-- Which does mean this is knowingly wrong about one case, and callers should know it: the
-- office sits directly above the shop floor, so a player upstairs measures as fifteen
-- studs from a station downstairs, and by this function they are standing next to it.
-- Left wrong rather than fixed with a height test, because the honest question there is
-- not "how far" but "could you walk it" -- and `Reachable` already answers that, at the
-- one moment it matters, without every reach check in the game paying for a raycast.
--
-- Here because it was written out by hand in nine files and open-coded inside the
-- separation loops of two more, and one of the nine had already drifted to a different
-- implementation of the same three lines. Nothing was broken by that yet -- which is
-- exactly the problem, because the first thing that breaks would have been a reach that
-- behaves differently in the gym than in the shop for no reason anybody wrote down.
function Ground.FlatDistance(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- A character mid-spawn can report an extents size of nearly zero, and a
-- zero-sized clearance box finds nothing and therefore passes everything. These
-- are the floor under that reading rather than tunables: roughly a crawling
-- toddler, which is the smallest body the game actually has.
local MIN_BODY_HEIGHT = 1.2
local MIN_BODY_WIDTH = 1.0

-- How far above a candidate the floor probe starts and how far below it gives
-- up. Generous downward so a spot can land on a step or a slightly lower floor,
-- bounded so it cannot find the storey below through a gap.
local PROBE_UP = 6
local PROBE_DOWN = 12

-- Lifted off the floor before the box is swept, so the floor the body stands on
-- is not itself counted as the thing blocking it.
local CLEARANCE_LIFT = 0.2

function Ground.BodyHeight(character: Model): number
	return math.max(character:GetExtentsSize().Y, MIN_BODY_HEIGHT)
end

-- What has to fit, as opposed to what is drawn. A marker's disc may overhang a
-- table leg -- the player stands in the middle of it, not on its edge -- so
-- testing the whole disc for clearance would reject most of a furnished room for
-- no reason. Taken from the character rather than fixed, so a crawling toddler
-- can be offered spots an adult could not stand in, which is correct: they are a
-- different size and the house is the same house.
function Ground.BodyRadius(character: Model): number
	local extents = character:GetExtentsSize()
	return math.max(extents.X, extents.Z, MIN_BODY_WIDTH) / 2
end

-- Everything a probe must look straight through: every player's character, plus
-- whatever the caller is in the middle of placing. Rebuilt per placement because
-- the set of characters changes.
--
-- Characters are always excluded rather than optionally so. A probe that stopped
-- on a body would report "occupied" for the one spot the asker is standing in,
-- and every system here measures spots *around* a player.
function Ground.IgnoreList(extra: { Instance }?): { Instance }
	local ignore: { Instance } = {}
	if extra ~= nil then
		table.move(extra, 1, #extra, 1, ignore)
	end
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if character ~= nil then
			table.insert(ignore, character)
		end
	end
	return ignore
end

-- The floor under a candidate, or nil if there isn't one. Returned rather than
-- assumed because candidates are generated on a flat plane and the house is not
-- flat: one can hang over a stairwell or off the edge of an upstairs floor, and
-- something floating in the air is not where it was meant to be.
function Ground.FloorUnder(candidate: Vector3, ignore: { Instance }): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	-- Rugs, mats and delivery markers are non-colliding, and a probe that stopped
	-- on one would place whatever it is siting on the rug's *surface* rather than
	-- on the floor it is lying on. Half a stud, but it is the difference between a
	-- pad painted on the floor and one hovering over it.
	params.RespectCanCollide = true

	local from = candidate + Vector3.new(0, PROBE_UP, 0)
	local result = workspace:Raycast(from, Vector3.new(0, -(PROBE_UP + PROBE_DOWN), 0), params)
	if result == nil then
		return nil
	end
	return result.Position
end

-- Whether a body of this size could actually stand at this spot, `at` being the
-- point on the floor it would stand on.
function Ground.Standable(at: Vector3, radius: number, height: number, ignore: { Instance }): boolean
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

-- The bearings to try, in the order to try them: straight ahead first, then
-- alternating outward. So whatever is being placed turns up where the player is
-- already looking whenever the room allows it, and only slides around the arc when
-- it cannot.
--
-- Here rather than in either caller because both are the same question asked about
-- different bodies -- where can the dog walk in from, where can a parent come from
-- -- and a fan that tried its bearings in a different order in one of them would be
-- a different feature wearing the same name. The arc is the caller's, because those
-- genuinely differ: an animal arrives in front of you and a person may come from
-- behind.
function Ground.Bearings(arcDegrees: number, count: number): { number }
	if count <= 1 then
		return { 0 }
	end

	local step = arcDegrees / (count - 1)
	local angles: { number } = {}
	for index = 1, count do
		table.insert(angles, -arcDegrees / 2 + (index - 1) * step)
	end
	table.sort(angles, function(a: number, b: number): boolean
		-- Ties are the symmetric pair either side of straight ahead. Which of the two
		-- is tried first does not matter, but the comparator has to be a strict order
		-- or table.sort is entitled to throw, so the sign breaks the tie.
		if math.abs(a) == math.abs(b) then
			return a < b
		end
		return math.abs(a) < math.abs(b)
	end)
	return angles
end

-- Whether one floor point can be reached from another in a straight line. Not a
-- path test -- a single ray at chest height, which is enough to catch the failure
-- that actually matters: a spot on the far side of a wall, plainly visible and
-- completely unreachable.
--
-- `height` is the body's, and the ray is cast at half of it, so the same call
-- answers "can the player walk there" and "can the dog walk here" without either
-- caller having to know how the other measures itself.
function Ground.Reachable(from: Vector3, to: Vector3, height: number, ignore: { Instance }): boolean
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

-- The three probes above, in the one order they are ever run, as a single question:
-- "is there a spot here a body this size could stand in and get to?" Returns the floor
-- point, or nil for any of the three ways a candidate can fail.
--
-- The order is load-bearing rather than incidental, which is the whole argument for this
-- existing. `FloorUnder` has to be first because the other two take a point *on the
-- floor* and a candidate is a point in the air; `Standable` before `Reachable` because a
-- box query beats a raycast when most rejections are furniture rather than walls.
-- Eighteen places wrote that sequence out by hand across nine files, and checking that
-- any two of them agreed meant reading both.
--
-- `reachableFrom` is nil for the callers that genuinely do not ask -- a townsperson
-- standing on a ring around their own doorstep is not walking there, they are simply
-- there -- rather than a shortcut for the ones that forgot. There is no way to express
-- "I skipped the reachability test by accident" in one optional argument, which is the
-- point of it being one.
--
-- The ray always runs from `reachableFrom` out to the candidate, never inward, and the
-- direction is fixed here so no caller has to decide it. It very nearly does not matter
-- and not quite: a ray that starts inside a part registers no hit, so whichever end it
-- starts from is the end whose own geometry is forgiven. Outward is right because the
-- asker is the one standing somewhere known to be clear -- they are standing there --
-- while the candidate is a guess that has not been stood in yet. Two callers used to
-- cast inward; they now cast outward with everything else.
function Ground.SpotAt(
	candidate: Vector3,
	radius: number,
	height: number,
	ignore: { Instance },
	reachableFrom: Vector3?
): Vector3?
	local floor = Ground.FloorUnder(candidate, ignore)
	if floor == nil then
		return nil
	end
	if not Ground.Standable(floor, radius, height, ignore) then
		return nil
	end
	if reachableFrom ~= nil and not Ground.Reachable(reachableFrom, floor, height, ignore) then
		return nil
	end
	return floor
end

-- Whether a spot is at least `minStuds` from everything already placed.
--
-- The counterpart to `SpotAt` and the other half of every placement loop in the game:
-- the floor will happily accept two marks a stud apart, and two marks a stud apart is a
-- player clearing both without moving. Five copies of this loop, and two of them were
-- open-coded flat-distance arithmetic inside the `if` rather than even a named call.
--
-- Strictly closer than, so `minStuds` is the closest two things may legally be rather
-- than the closest they may not. One of the five copies read the comparison the other
-- way; at exactly the boundary distance they disagreed, which is a difference no float
-- ever actually lands on and nobody would have found on purpose.
function Ground.Apart(at: Vector3, others: { Vector3 }, minStuds: number): boolean
	for _, other in others do
		if Ground.FlatDistance(at, other) < minStuds then
			return false
		end
	end
	return true
end

-- `Bearings`, then shuffled, for the searches that must not put their marks in the same
-- corner of the same room every time.
--
-- The opposite of what `Bearings` is for, and both are right: a prop set or an animal
-- should arrive where the player is already looking, and a shift's eighth task should
-- not be in the spot the first seven were. Separate functions rather than a flag, so the
-- call site says which of those two things it wants.
--
-- Fisher-Yates written once. It was written twice, identically, in two files that each
-- said "shuffled like the other one" in a comment -- and a hand-rolled shuffle is a
-- classic place to leave an off-by-one that biases the first element and is invisible
-- for a year.
function Ground.ScatteredBearings(arcDegrees: number, count: number): { number }
	local bearings = Ground.Bearings(arcDegrees, count)
	for index = #bearings, 2, -1 do
		local swap = math.random(index)
		bearings[index], bearings[swap] = bearings[swap], bearings[index]
	end
	return bearings
end

-- Deliberately not here: the search itself.
--
-- Seven systems run an arc search over these probes and it is tempting to read that as
-- seven copies of one function. It is not. The dog needs two spots that can see each
-- other, the toddler wants the *furthest* ring rather than the first hit and picks at
-- random inside it, the prop set places a whole arrangement per bearing and fails as a
-- unit, the shop walks out in steps and shuffles, the parent tries two distances and
-- checks reachability in the opposite direction. The bearings, the ordering, the number
-- of probes and what counts as success are all different, and all of them are that
-- activity's design rather than plumbing.
--
-- A function taking all of that as arguments would need eight of them, most optional,
-- and would turn five legible loops into five opaque option tables while still leaving
-- two callers open-coded because they would not fit. The duplication worth removing is
-- the part with no decisions in it, which is everything above this comment.

return Ground
