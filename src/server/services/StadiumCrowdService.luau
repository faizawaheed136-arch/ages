--!strict
-- The stadium's ambient crowd, made real.
--
-- tools/gen_city.py tags every seat in every tier as a seat anchor (AgesStadiumCrowdSeat)
-- and six roam anchors per stand's concourse (AgesStadiumCrowdRoam), each carrying a
-- `Stand` attribute saying which of the four stands it belongs to. There is no separate
-- static-mannequin fill any more: an occupied seat is a real NPC and an empty one is just
-- an empty seat, the same trade GangService makes for its four bosses and NPCService
-- makes for a delivery -- a capped pool of real, driven rigs standing in for a crowd that
-- cannot all be real without asking NPCService.Spawn -- a web call per rig -- to answer
-- for every seat in the bowl at once.
--
-- Two capped pools, mirroring GangService's post pattern:
--   Seated   Sit at a seat anchor, facing the pitch (Config.Stadium.StandFacing), and
--            occasionally stand up, step back into the row and sit back down again
--            (`standUpSeated`) -- the difference between a crowd and a photograph of one.
--   Roaming  Walk a loop of their stand's six concourse waypoints, pausing at each.
-- Both pools are topped up on a tick rather than spawned once, for the same reason
-- GangService re-checks its four bosses: streaming and a failed rig build can lose one
-- silently, and a gap in a stand this size is not something a player will report, it is
-- something they will just not notice was ever supposed to be there. `SpawnPerTick`
-- caps how many empty slots a single tick is allowed to start filling -- the caps below
-- can be asking for well over a hundred rigs the moment a server's first player loads in,
-- and firing all of them at once is the same web-call burst Config.Town's bodied-NPC cap
-- exists to avoid elsewhere; a low per-tick budget fills the bowl within a couple of
-- minutes without ever asking for more than a handful of rigs at once.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local NPCService = require(script.Parent.NPCService)
local Townsfolk = require(script.Parent.Parent.content.Townsfolk)

type Visitor = NPCService.Visitor
type CastMember = Types.CastMember

local STADIUM = Config.Stadium

local StadiumCrowdService = {}

-- One seated Visitor per occupied seat anchor.
type SeatedSlot = {
	anchor: BasePart,
	visitor: Visitor?,
	spawning: boolean,
	standingUp: boolean,
}

-- One roaming Visitor per occupied roam slot, plus the loop it is walking.
type RoamingSlot = {
	stand: string,
	waypoints: { Vector3 },
	visitor: Visitor?,
	spawning: boolean,
	walking: boolean,
}

local seatSlots: { SeatedSlot } = {}
local roamSlots: { RoamingSlot } = {}

local enabled = true

-- ---------------------------------------------------------------------------
-- Indexing: read the tagged anchors gen_city.py salted through the bowl.
-- ---------------------------------------------------------------------------

-- Roam anchors are grouped by stand (their `Stand` attribute) into one waypoint loop
-- per stand, matching the RoamAnchor{stand}{0..5} anchors stadium_crowd_roam_arc emits
-- in tools/gen_city.py. Read once at Init: the bowl is static geometry built at map-gen
-- time, not something that grows at runtime the way PlaceService's posts can.
local function indexAnchors()
	seatSlots = {}
	for _, instance in CollectionService:GetTagged(STADIUM.SeatTag) do
		local anchor = instance :: BasePart
		table.insert(seatSlots, { anchor = anchor, visitor = nil, spawning = false, standingUp = false })
	end

	local waypointsByStand: { [string]: { Vector3 } } = {}
	for _, instance in CollectionService:GetTagged(STADIUM.RoamTag) do
		local anchor = instance :: BasePart
		local stand = anchor:GetAttribute(STADIUM.StandAttribute)
		if type(stand) ~= "string" then
			continue
		end
		local list = waypointsByStand[stand]
		if list == nil then
			list = {}
			waypointsByStand[stand] = list
		end
		table.insert(list, anchor.Position)
	end

	roamSlots = {}
	for stand, waypoints in waypointsByStand do
		if #waypoints < 2 then
			-- A loop needs at least two stops to be a loop. Never expected in practice --
			-- stadium_crowd_roam_loop always emits four -- but a stand short a wall would
			-- otherwise spawn a roamer that "walks" between one point and itself forever.
			continue
		end
		local perStand = math.max(1, math.floor(STADIUM.MaxRoamingCrowd / 4))
		for _ = 1, perStand do
			table.insert(roamSlots, { stand = stand, waypoints = waypoints, visitor = nil, spawning = false, walking = false })
		end
	end
end

-- ---------------------------------------------------------------------------
-- Bodies: any Townsfolk member does, the same generic pool NPCService draws
-- background crew from -- a spectator is not one of the four-and-tie-gated
-- named cast, just somebody who happened to be at the match.
-- ---------------------------------------------------------------------------

local function randomBody(): CastMember?
	local bodies = Townsfolk.Bodies
	if #bodies == 0 then
		return nil
	end
	return bodies[math.random(1, #bodies)]
end

-- A seated fan in the home or away colour banding the tier itself is painted
-- in, rather than whatever colour Townsfolk happened to roll. `anchor.Name`
-- is `Seat{index}` -- the same `index` tools/gen_city.py's `stadium_seat`
-- coloured the seat itself with via `STAD_SEATS[index % 2]` -- so reading
-- the trailing digits back and picking the matching Config colour is what
-- makes a live fan continue the exact banding pattern the seat they are
-- sitting in is already painted, instead of a fan that randomly breaks kit
-- two rows deep into a block of red.
local function seatedBody(anchorName: string): CastMember?
	local base = randomBody()
	if base == nil then
		return nil
	end
	local digits = string.match(anchorName, "%d+$")
	local index = if digits ~= nil then tonumber(digits) else nil
	if index == nil then
		return base
	end
	local shirt = if index % 2 == 0 then STADIUM.HomeShirtColor else STADIUM.AwayShirtColor
	-- A shallow copy with one field overridden, not a mutation of the shared
	-- Townsfolk record -- the same body is drawn for roamers and for other
	-- seats, and none of them should end up wearing this one's kit by accident.
	local fan: CastMember = table.clone(base)
	fan.shirtColor = shirt
	return fan
end

local function facingVector(stand: string): Vector3
	local facing = STADIUM.StandFacing[stand]
	if facing == nil then
		return Vector3.new(0, 0, 1)
	end
	return Vector3.new(facing.x, 0, facing.z)
end

-- ---------------------------------------------------------------------------
-- Seated pool.
-- ---------------------------------------------------------------------------

local function despawnSeated(slot: SeatedSlot)
	if slot.visitor ~= nil then
		slot.visitor.destroy()
		slot.visitor = nil
	end
	slot.standingUp = false
end

-- Yields on the web call inside NPCService.Spawn, so everything after it is re-checked
-- against the slot -- see GangService.spawnPost, the same shape for the same reason.
local function spawnSeated(player: Player, slot: SeatedSlot)
	if slot.visitor ~= nil or slot.spawning then
		return
	end
	local member = seatedBody(slot.anchor.Name)
	if member == nil then
		return
	end
	local stand = slot.anchor:GetAttribute(STADIUM.StandAttribute)
	local facing = if type(stand) == "string" then facingVector(stand) else Vector3.new(0, 0, 1)
	local seatPos = slot.anchor.Position
	local at = CFrame.lookAt(seatPos, seatPos + facing)

	slot.spawning = true
	task.spawn(function()
		local visitor = NPCService.Spawn(player, member, at)
		slot.spawning = false
		if visitor == nil then
			return
		end
		if slot.visitor ~= nil then
			-- Somebody else was seated here while this one was still building.
			visitor.destroy()
			return
		end
		slot.visitor = visitor
	end)
end

-- Stands a seated fan up, steps them straight back along their stand's own
-- StandFacing direction -- away from the pitch, into the gap behind the row
-- their seat is in, not a pathfind through the packed seats either side --
-- waits a few seconds, then walks them back and sits them down again.
-- `slot.standingUp` is the guard: `tickCrowd` rolls the chance for every
-- occupied seat on every tick, and without it a seat that missed the coin
-- flip once would just get asked again a moment later while still mid-walk.
-- Checked before and after every yield the same way `walkRoamer` checks
-- `visitor.gone()`, since a stand-up can be yielding for seconds while the
-- rig underneath it is torn down by a server sweep or the seat is despawned.
local function standUpSeated(slot: SeatedSlot)
	local visitor = slot.visitor
	if visitor == nil or slot.standingUp then
		return
	end
	local stand = slot.anchor:GetAttribute(STADIUM.StandAttribute)
	local facing = if type(stand) == "string" then facingVector(stand) else Vector3.new(0, 0, 1)
	local seatPos = slot.anchor.Position
	local stepPos = seatPos - facing * STADIUM.StandUpStepStuds
	local shouldStop = function()
		return visitor.gone() or slot.visitor ~= visitor
	end

	slot.standingUp = true
	task.spawn(function()
		if not shouldStop() then
			visitor.walkTo(stepPos)
		end
		if not shouldStop() then
			task.wait(math.random(STADIUM.StandUpMinSeconds, STADIUM.StandUpMaxSeconds))
		end
		if not shouldStop() then
			visitor.walkTo(seatPos)
		end
		slot.standingUp = false
	end)
end

-- ---------------------------------------------------------------------------
-- Roaming pool.
-- ---------------------------------------------------------------------------

local function despawnRoaming(slot: RoamingSlot)
	if slot.visitor ~= nil then
		slot.visitor.destroy()
		slot.visitor = nil
	end
	slot.walking = false
end

-- Cycles a roamer between its stand's concourse waypoints forever, pausing at each --
-- the same walk/rest/walk shape as Roam.Start, simplified from the town's route graph
-- down to one stand's fixed six-point loop. Runs for as long as the Visitor is alive;
-- `visitor.gone()` is the only exit, checked before and after every yield the same way
-- Roam.Start checks it, since a walk can be yielding for seconds while the rig underneath
-- it is torn down by a server sweep or the last player leaving.
local function walkRoamer(slot: RoamingSlot, visitor: Visitor)
	slot.walking = true
	task.spawn(function()
		local index = math.random(1, #slot.waypoints)
		while not visitor.gone() and slot.visitor == visitor do
			index = (index % #slot.waypoints) + 1
			local shouldStop = function()
				return visitor.gone() or slot.visitor ~= visitor
			end
			visitor.pathTo(slot.waypoints[index], shouldStop)
			if visitor.gone() or slot.visitor ~= visitor then
				break
			end
			task.wait(math.random(STADIUM.RoamPauseMinSeconds, STADIUM.RoamPauseMaxSeconds))
		end
		slot.walking = false
	end)
end

local function spawnRoaming(player: Player, slot: RoamingSlot)
	if slot.visitor ~= nil or slot.spawning then
		return
	end
	local member = randomBody()
	if member == nil then
		return
	end
	local startPos = slot.waypoints[math.random(1, #slot.waypoints)]
	local at = CFrame.new(startPos)

	slot.spawning = true
	task.spawn(function()
		local visitor = NPCService.Spawn(player, member, at)
		slot.spawning = false
		if visitor == nil then
			return
		end
		if slot.visitor ~= nil then
			visitor.destroy()
			return
		end
		slot.visitor = visitor
		visitor.setSpeed(STADIUM.RoamWalkSpeed)
		walkRoamer(slot, visitor)
	end)
end

-- ---------------------------------------------------------------------------
-- Tick: top both pools back up to their caps, or tear them down in an empty
-- server. Mirrors GangService.tickPosts exactly, for the same reason: an NPC
-- rig does not persist through streaming, so "was it lost" has to be asked
-- again and again rather than answered once at Start.
-- ---------------------------------------------------------------------------

local function tickCrowd()
	if not enabled then
		return
	end
	local anybody = Players:GetPlayers()[1]
	if anybody == nil then
		for _, slot in seatSlots do
			despawnSeated(slot)
		end
		for _, slot in roamSlots do
			despawnRoaming(slot)
		end
		return
	end

	-- Shared across both pools: only this many empty slots may start
	-- spawning on this one tick, however many the caps below would
	-- otherwise ask for at once. See the header comment and
	-- Config.Stadium.SpawnPerTick.
	local budget = STADIUM.SpawnPerTick

	local seated = 0
	for _, slot in seatSlots do
		if slot.visitor ~= nil then
			if slot.visitor.gone() then
				despawnSeated(slot)
			else
				seated += 1
				-- Stand-up is a walk, not a spawn -- it never touches `budget`.
				if not slot.standingUp and math.random() < STADIUM.StandUpChancePerTick then
					standUpSeated(slot)
				end
			end
		end
	end
	if seated < STADIUM.MaxSeatedCrowd then
		for _, slot in seatSlots do
			if seated >= STADIUM.MaxSeatedCrowd or budget <= 0 then
				break
			end
			if slot.visitor == nil and not slot.spawning then
				spawnSeated(anybody, slot)
				seated += 1
				budget -= 1
			end
		end
	end

	local roaming = 0
	for _, slot in roamSlots do
		if slot.visitor ~= nil then
			if slot.visitor.gone() then
				despawnRoaming(slot)
			else
				roaming += 1
			end
		end
	end
	if roaming < STADIUM.MaxRoamingCrowd then
		for _, slot in roamSlots do
			if roaming >= STADIUM.MaxRoamingCrowd or budget <= 0 then
				break
			end
			if slot.visitor == nil and not slot.spawning then
				spawnRoaming(anybody, slot)
				roaming += 1
				budget -= 1
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Debug surface.
-- ---------------------------------------------------------------------------

function StadiumCrowdService.SetEnabled(value: boolean)
	enabled = value
	if not enabled then
		for _, slot in seatSlots do
			despawnSeated(slot)
		end
		for _, slot in roamSlots do
			despawnRoaming(slot)
		end
	end
end

function StadiumCrowdService.IsEnabled(): boolean
	return enabled
end

function StadiumCrowdService.Describe(): string
	local seated = 0
	for _, slot in seatSlots do
		if slot.visitor ~= nil then
			seated += 1
		end
	end
	local roaming = 0
	for _, slot in roamSlots do
		if slot.visitor ~= nil then
			roaming += 1
		end
	end
	return `stadium crowd: {seated}/{STADIUM.MaxSeatedCrowd} seated, {roaming}/{STADIUM.MaxRoamingCrowd} roaming, {#seatSlots} seat anchors, {#roamSlots} roam slots ({if enabled then "on" else "DISABLED"})`
end

function StadiumCrowdService:Init()
	indexAnchors()
end

function StadiumCrowdService:Start()
	task.spawn(function()
		while true do
			task.wait(STADIUM.TickSeconds)
			local ok, err = pcall(tickCrowd)
			if not ok then
				warn(`[AGES] stadium crowd tick failed: {err}`)
			end
		end
	end)
end

return StadiumCrowdService
