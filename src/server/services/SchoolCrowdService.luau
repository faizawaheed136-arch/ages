--!strict
-- The other students.
--
-- The school had nobody in it. Teachers appear for a lesson and bullies stand in the
-- corridor, and that was the whole population of a fourteen-room building -- so every
-- reference photograph of this genre is crowded and ours was an empty set with the lights
-- on. A school is *other children*; that is what the word means, and it is the single
-- largest gap between this building and the games it is measured against.
--
-- **This file spawns nobody the school has not already built a room for.** It never calls
-- School.Build. If the building is not up, there is no crowd, and that is correct: a
-- cohort of rigs standing on an empty lot is worse than an empty lot.
--
-- Modelled on StadiumCrowdService, which solved the hard half already. Its two lessons are
-- the two that matter here:
--
-- 1. **A rig is a web call.** NPCService.Spawn goes through
--    Players:CreateHumanoidModelFromDescription. The cap and the per-tick budget are not
--    tuning; they are what stops the first player through the gate from stalling the server.
-- 2. **Top the pool up on a tick, never spawn it once.** Streaming and failed builds lose
--    rigs silently, and a missing student is not something a player reports -- it is
--    something they never learn was supposed to be there.
--
-- Everyone is spawned **at the player's own age**, the way BullyService does it. That single
-- argument is the difference between schoolmates and adults loitering in a corridor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)
local NPCService = require(script.Parent.NPCService)
local Townsfolk = require(script.Parent.Parent.content.Townsfolk)
local School = require(script.Parent.Parent.world.School)

type Visitor = NPCService.Visitor

local SchoolCrowdService = {}

local CROWD = Config.School.Crowd

-- Where students stand and walk, as room ids in School's own plan.
--
-- Read from the plan rather than written as coordinates, which is the rule the whole world
-- tree follows: the school is laid around a place point and the place point moves. A list of
-- room ids survives that; a list of positions does not.
--
-- The corridor is weighted by appearing twice. That is not a trick -- between periods a
-- school corridor holds more people than any room in the building, and a crowd spread evenly
-- across fourteen rooms reads as a museum.
local STANDING_ROOMS = {
	"corridor",
	"corridor",
	"lounge",
	"lounge",
	"cafeteria",
	"cafeteria",
	"library",
	"gym",
}

-- What a roamer walks between. Deliberately the big shared spaces rather than the
-- classrooms: a student pacing in and out of the chemistry lab all afternoon is a student
-- with nowhere to be.
local ROAMING_ROOMS = {
	"corridor",
	"cafeteria",
	"lounge",
	"library",
}

type Slot = {
	kind: string,
	visitor: Visitor?,
	spawning: boolean,
	walking: boolean,
	-- Where a stander was told to stand, so the tick can tell a student who wandered from a
	-- student whose rig has gone.
	post: Vector3?,
}

local slots: { Slot } = {}
local enabled = true

local function randomBody()
	local bodies = Townsfolk.Bodies
	if #bodies == 0 then
		return nil
	end
	return bodies[math.random(1, #bodies)]
end

-- A point inside a named room, scattered a little so a row of students does not read as a
-- shelf of dolls. Nil when the school has no such room, which is the normal answer before
-- the building is up.
local function spotIn(rooms: { string }): Vector3?
	local plan = School.Plan()
	if plan == nil then
		return nil
	end
	-- Tried a few times rather than once: a room id in the list above may simply not exist in
	-- a given build, and giving up on the first miss would empty the whole crowd because of
	-- one name.
	for _ = 1, 4 do
		local id = rooms[math.random(1, #rooms)]
		local at = plan.rooms[id]
		if at ~= nil then
			local spread = CROWD.ScatterStuds
			return at + Vector3.new(math.random(-spread, spread), 0, math.random(-spread, spread))
		end
	end
	return nil
end

-- The player the crowd is being built for, and only if they are near the school.
--
-- One player rather than all of them: NPCService.Spawn takes a player because a rig is built
-- against somebody's age, and a school full of students who are all seventeen because one
-- seventeen-year-old is on the server is a smaller wrong than a school full of adults.
local function nearestStudent(): (Player?, number)
	local plan = School.Plan()
	if plan == nil then
		return nil, 0
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root ~= nil and (root.Position - plan.center).Magnitude <= CROWD.NearStuds then
				local profile = DataService.GetProfile(player)
				if profile ~= nil then
					local data = Lives.Active(profile.Data)
					return player, math.floor(data.ageMonths / 12)
				end
			end
		end
	end
	return nil, 0
end

local function despawn(slot: Slot)
	if slot.visitor ~= nil then
		slot.visitor.destroy()
		slot.visitor = nil
	end
	slot.walking = false
	slot.post = nil
end

-- Walks a roamer between the shared rooms forever, pausing at each. The same walk/rest shape
-- the stadium's concourse loop uses, and `visitor.gone()` is the only exit -- a walk can be
-- yielding for seconds while the rig underneath it is torn down by a life ending or the last
-- player leaving.
local function walkRoamer(slot: Slot, visitor: Visitor)
	slot.walking = true
	task.spawn(function()
		while not visitor.gone() and slot.visitor == visitor do
			local target = spotIn(ROAMING_ROOMS)
			if target == nil then
				break
			end
			local shouldStop = function()
				return visitor.gone() or slot.visitor ~= visitor
			end
			visitor.pathTo(target, shouldStop)
			if visitor.gone() or slot.visitor ~= visitor then
				break
			end
			task.wait(math.random(CROWD.PauseMinSeconds, CROWD.PauseMaxSeconds))
		end
		slot.walking = false
	end)
end

local function spawnInto(slot: Slot, player: Player, age: number)
	if slot.visitor ~= nil or slot.spawning then
		return
	end
	local member = randomBody()
	if member == nil then
		return
	end
	local rooms = if slot.kind == "roam" then ROAMING_ROOMS else STANDING_ROOMS
	local at = spotIn(rooms)
	if at == nil then
		return
	end

	slot.spawning = true
	task.spawn(function()
		-- The age is the whole point -- see the header. A schoolmate is somebody your own
		-- size, and passing this is what makes the corridor read as a school.
		local visitor = NPCService.Spawn(player, member, CFrame.new(at), age)
		slot.spawning = false
		if visitor == nil then
			return
		end
		-- The pool may have been torn down while the web call was in flight.
		if slot.visitor ~= nil or not enabled then
			visitor.destroy()
			return
		end
		slot.visitor = visitor
		if slot.kind == "roam" then
			visitor.setSpeed(CROWD.WalkSpeed)
			walkRoamer(slot, visitor)
		else
			slot.post = at
		end
	end)
end

local function tickCrowd()
	if not enabled then
		for _, slot in slots do
			despawn(slot)
		end
		return
	end

	local player, age = nearestStudent()
	if player == nil then
		-- Nobody near the school, or no school. Tear the cohort down rather than leaving it
		-- standing in an empty building on the far side of the map.
		for _, slot in slots do
			despawn(slot)
		end
		return
	end

	local budget = CROWD.SpawnPerTick
	for _, slot in slots do
		if budget <= 0 then
			break
		end
		if slot.visitor ~= nil and slot.visitor.gone() then
			-- Lost to streaming or a sweep. Cleared here so the slot can be refilled, which is
			-- the whole reason this runs on a tick instead of once.
			slot.visitor = nil
			slot.walking = false
		end
		if slot.visitor == nil and not slot.spawning then
			spawnInto(slot, player, age)
			budget -= 1
		end
	end
end

function SchoolCrowdService.SetEnabled(value: boolean)
	enabled = value
	if not enabled then
		for _, slot in slots do
			despawn(slot)
		end
	end
end

function SchoolCrowdService.IsEnabled(): boolean
	return enabled
end

-- Clears the cohort. The new-life path: the school is rebuilt around whichever place point
-- the next life walks into, and a crowd standing at the old one would be a class of ghosts.
function SchoolCrowdService.Clear()
	for _, slot in slots do
		despawn(slot)
	end
end

function SchoolCrowdService.Describe(): string
	local standing, roaming, pending = 0, 0, 0
	for _, slot in slots do
		if slot.spawning then
			pending += 1
		elseif slot.visitor ~= nil then
			if slot.kind == "roam" then
				roaming += 1
			else
				standing += 1
			end
		end
	end
	local plan = School.Plan()
	local player = nearestStudent()
	return table.concat({
		`students: {if enabled then "on" else "off"}`,
		`school: {if plan ~= nil then "built" else "not built yet"}`,
		`someone near: {if player ~= nil then player.Name else "nobody"}`,
		`standing {standing}, roaming {roaming}, arriving {pending}, of {CROWD.Max}`,
	}, "\n")
end

function SchoolCrowdService:Init()
	-- The slots are made once and refilled forever, which is what makes the cap a cap: a
	-- pool that grew on demand would have no ceiling on the web calls it could ask for.
	for index = 1, CROWD.Max do
		table.insert(slots, {
			kind = if index <= CROWD.Roaming then "roam" else "stand",
			visitor = nil,
			spawning = false,
			walking = false,
			post = nil,
		})
	end
end

function SchoolCrowdService:Start()
	Players.PlayerRemoving:Connect(function()
		-- The last player out takes the school with them on the next tick; this only makes
		-- that immediate rather than waiting on the timer.
		if #Players:GetPlayers() <= 1 then
			SchoolCrowdService.Clear()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(CROWD.TickSeconds)
			local ok, err = pcall(tickCrowd)
			if not ok then
				warn(`[AGES] school crowd tick failed: {err}`)
			end
		end
	end)
end

return SchoolCrowdService
