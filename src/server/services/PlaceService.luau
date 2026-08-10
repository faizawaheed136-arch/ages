--!strict
-- The world's index of itself. Every named spot outside the player's own feet --
-- the front path, the crossing, a classroom, the shop floor -- is a tagged part
-- in the built world, and this is the one place that knows how to find them.
--
-- The alternative, and the reason this exists, is a table of coordinates in
-- Luau. That table is correct exactly until somebody nudges a wall in Studio,
-- and then it is a list of spots inside walls that nothing in the game is in a
-- position to notice. A tagged part moves when the building moves because it is
-- part of the building.
--
-- What this is not: a teleport network. Send() exists for the harness and for
-- the recovery cases a system will genuinely need later (clocking off should put
-- you outside the door, not wherever you were standing when your shift ended).
-- Ordinary travel is walking, and Part 1 of this slice is only done when the
-- walk itself works.
--
-- Attributes are read at use rather than cached at tag time, matching
-- DeliveryService and WorldEventService: an id corrected in Studio mid-session
-- takes effect without a restart.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type Place = Types.Place

local PlaceService = {}

-- Below this, a flattened look vector is noise rather than a heading. Not a
-- tunable: it is the floating-point floor of "this vector points straight up",
-- so it lives with the arithmetic it guards rather than in Config.
local FLAT_FACING_EPSILON = 1e-3

-- Everything currently tagged. A set rather than a map by id, because two parts
-- can carry the same id at once while somebody is mid-edit in Studio, and the
-- lookup wants to be able to say so rather than silently keep one of them.
local points: { [BasePart]: boolean } = {}

local warnedPoints: { [Instance]: boolean } = {}
local warnedIds: { [string]: boolean } = {}

local function warnPointOnce(instance: Instance, message: string)
	if warnedPoints[instance] then
		return
	end
	warnedPoints[instance] = true
	warn(`[AGES] place point "{instance:GetFullName()}" {message}`)
end

-- The id a point answers to, or nil if it is misconfigured. An untagged-but-
-- present point looks exactly like a working one nothing has asked for yet, so
-- the bad cases are said out loud once rather than skipped.
local function pointId(point: BasePart): string?
	local raw = point:GetAttribute(Config.World.PlacePointAttribute)
	if raw == nil then
		warnPointOnce(point, `has no "{Config.World.PlacePointAttribute}" attribute, so nothing can ask for it`)
		return nil
	end
	if typeof(raw) ~= "string" then
		warnPointOnce(point, `has a non-string "{Config.World.PlacePointAttribute}" attribute`)
		return nil
	end
	if raw == "" then
		warnPointOnce(point, `has an empty "{Config.World.PlacePointAttribute}" attribute`)
		return nil
	end
	return raw
end

-- The human sentence for a point. Falls back to the id rather than to nothing:
-- a listing with a missing label should still be a listing, because the label is
-- flavour and the id is the thing you actually need to see.
local function pointLabel(point: BasePart, id: string): string
	local raw = point:GetAttribute(Config.World.PlacePointLabelAttribute)
	if typeof(raw) == "string" and raw ~= "" then
		return raw
	end
	return id
end

-- Nil when no point carries that id. Warned once per id, not per call, because
-- the thing asking is likely to be asking on a loop.
function PlaceService.Find(id: string): Place?
	local found: BasePart? = nil
	for point in points do
		if point.Parent == nil then
			continue
		end
		if pointId(point) ~= id then
			continue
		end
		if found ~= nil then
			-- Two points answering to one name is a build mistake, and picking one
			-- quietly would mean the game sometimes puts you in the wrong room and
			-- nothing ever explains why.
			warnPointOnce(point, `duplicates the id "{id}", which "{found:GetFullName()}" already answers to`)
			continue
		end
		found = point
	end

	if found == nil then
		if not warnedIds[id] then
			warnedIds[id] = true
			warn(`[AGES] nothing tagged "{Config.World.PlacePointTag}" answers to the place id "{id}"`)
		end
		return nil
	end

	-- Copied into a fresh non-optional local, because a refinement on a variable
	-- the loop above assigns to is not one the type checker will carry this far.
	local part = found :: BasePart
	return { id = id, label = pointLabel(part, id), part = part }
end

-- Every place, sorted by id so a listing reads the same way twice running.
function PlaceService.All(): { Place }
	local places: { Place } = {}
	for point in points do
		if point.Parent == nil then
			continue
		end
		local id = pointId(point)
		if id == nil then
			continue
		end
		table.insert(places, { id = id, label = pointLabel(point, id), part = point })
	end
	table.sort(places, function(a: Place, b: Place): boolean
		return a.id < b.id
	end)
	return places
end

-- Puts a character down at a place. False when the id is unknown or there is no
-- body to move, so the caller can say which rather than reporting a move that
-- never happened.
--
-- The lift is not decoration. A place point marks the floor, and a body pivoted
-- onto the floor is a body half inside it -- either wedged or ejected upward by
-- the physics solver, both of which look like a bug. Dropping from just above
-- lets the fall do the seating.
function PlaceService.Send(player: Player, id: string): boolean
	local place = PlaceService.Find(id)
	if place == nil then
		return false
	end

	local character = player.Character
	if character == nil then
		return false
	end

	-- The player keeps whichever way they were already looking, flattened. A place
	-- point is a marker, not a pose: taking its rotation would tip the player over
	-- if the part were ever turned, and taking no rotation at all would spin them
	-- to face due north for no reason they could work out. Flattening is what
	-- stands up a character who was mid-fall when this was called.
	local look = character:GetPivot().LookVector
	local facing = Vector3.new(look.X, 0, look.Z)
	if facing.Magnitude < FLAT_FACING_EPSILON then
		-- Looking straight up or straight down, so there is no heading to keep.
		facing = -Vector3.zAxis
	end

	local origin = place.part.Position + Vector3.new(0, Config.World.PlaceDropStuds, 0)
	character:PivotTo(CFrame.lookAt(origin, origin + facing.Unit))
	return true
end

function PlaceService:Init() end

function PlaceService:Start()
	local tag = Config.World.PlacePointTag

	local function add(instance: Instance)
		if instance:IsA("BasePart") then
			points[instance :: BasePart] = true
		else
			warnPointOnce(instance, `is a {instance.ClassName}, which has no position; nothing can be sent to it`)
		end
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
		add(instance)
		-- A point arriving may be the one an earlier lookup complained about --
		-- someone tagging a part in Studio to fix exactly that. Clearing the whole
		-- memo rather than reasoning about which id it was keeps the fix quiet.
		table.clear(warnedIds)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			points[instance :: BasePart] = nil
		end
		warnedPoints[instance] = nil
	end)
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
end

return PlaceService
