--!strict
-- The officers: bodies in the street, and what they do about a bounty.
--
-- Reads BountyService and is never read by it. That one-way dependency is the whole
-- architecture of this feature and it is worth saying why it is worth protecting: an
-- arrest, in this file, is a call into BountyService and then nothing. Nobody here tears
-- an officer down at the moment of the arrest. The number goes to zero, and on the next
-- pass the ordinary "how many officers should exist" line reads zero and takes them off
-- the street the same way it would if the player had simply cooled off. There is exactly
-- one piece of code that removes an officer, and it does not know why it is doing it.
--
-- The other thing to read before changing anything is what an officer actually knows.
-- It is not where the player is. Every tick, one at a time, each officer asks whether it
-- can *see* the player -- near enough, and with nothing solid in between -- and only a
-- yes produces a sighting. A no means it carries on walking toward a spot that may be
-- half a minute out of date. That is not an approximation of better AI. It is the game:
-- the whole of hiding is the gap between where they are going and where you are, and any
-- change here that lets an officer read the player's live position without seeing them
-- deletes the feature while leaving every test passing.
--
-- What is deliberately absent: any way for an officer to affect the player except by
-- standing next to them. No weapons, no damage, no shoving. An arrest is proximity held
-- for a few seconds. If the police could do anything else, the answer to a pursuit would
-- be to turn around and deal with them, and last known position, hiding and every other
-- decision in this system would stop being decisions on the same afternoon.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local BountyService = require(script.Parent.BountyService)
local NPCService = require(script.Parent.NPCService)
local Ground = require(script.Parent.Parent.world.Ground)
local Police = require(script.Parent.Parent.content.Police)

type Visitor = NPCService.Visitor

local PoliceService = {}

local CRIME = Config.Crime

-- One officer in the world, and what it currently believes it is doing.
type Officer = {
	visitor: Visitor,
	-- Which numbered post in the response this is. Fixes which body it wears and which
	-- bearing it searches on, so a manhunt fans out instead of four people walking in a
	-- line -- and so those two things stay stable across ticks rather than being re-rolled
	-- into a twitch.
	post: number,
	-- "pursue" once it can see the player, "search" the rest of the time. Held rather than
	-- recomputed by every reader because the walk legs below key off the transition.
	mode: string,
	-- Where a search leg is currently walking to, and whether one is in flight. A leg is a
	-- yielding pathfind on its own thread, so this is the handshake that stops the tick
	-- from starting a second one on top of it four times a second.
	legTarget: Vector3?,
	legRunning: boolean,
	-- Seconds this officer has been within arresting distance, continuously. Reset the
	-- moment it is not, which is what makes a near miss a near miss.
	contactFor: number,
}

local officers: { [Player]: { Officer } } = {}
-- Set while a spawn is in flight for a player. Spawning is a yielding web call, so
-- without this the tick would ask for a second body a fifth of a second after asking for
-- the first and end up with twice the response the tier called for.
local spawning: { [Player]: boolean } = {}
local enabled = true

-- How far out an officer arrives, as a share of the tier's search radius. Not in Config
-- because it is not a difficulty dial: it exists so that police *arrive* rather than
-- appear, and any value that does that is as good as any other. At 1.0 they turn up at
-- the edge of where they are willing to look, which is the honest place for them to
-- start.
local ARRIVE_AT_EDGE_SHARE = 1

-- How near a search leg has to get before it counts as walked and the officer picks
-- somewhere else to look. Loose, because a humanoid stopping exactly on a point is not a
-- thing that happens and a tighter number here reads as officers refusing to move on.
local LEG_ARRIVED_STUDS = 8

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

-- Everything a sight test should shoot through rather than stop on. Players are already
-- in Ground.IgnoreList; the visitors folder is added because an officer must not be
-- blinded by another officer standing in front of it, which at the top tier is most of
-- the time.
local function sightIgnore(): { Instance }
	local extra: { Instance } = {}
	local folder = workspace:FindFirstChild("AgesVisitors")
	if folder ~= nil then
		table.insert(extra, folder)
	end
	return Ground.IgnoreList(extra)
end

-- Whether this officer can see that point. Distance first because it is arithmetic and
-- the raycast is not -- at the top tier this runs six times per player per tick, and the
-- overwhelming majority of those are answered by the cheap half.
local function canSee(from: Vector3, to: Vector3, sightStuds: number): boolean
	if sightStuds <= 0 then
		return false
	end
	if Ground.FlatDistance(from, to) > sightStuds then
		return false
	end
	return Ground.Reachable(from, to, Config.NPC.BodyHeight, sightIgnore())
end

-- A standable spot on a bearing out from a centre point, or nil if the town has nothing
-- there. Used both for arrivals and for search legs, because they are the same question
-- asked at different radii.
local function spotOut(center: Vector3, bearing: number, distance: number): Vector3?
	local direction = CFrame.Angles(0, math.rad(bearing), 0) * Vector3.new(0, 0, -1)
	local candidate = center + direction * distance
	return Ground.SpotAt(candidate, Config.NPC.BodyRadius, Config.NPC.BodyHeight, sightIgnore())
end

-- Where officer number `post` should look, given what the police believe.
--
-- The whole behaviour of a search is in this function, and it is one branch. A *fresh*
-- sighting sends everybody to the same place, because that is what a real report does:
-- somebody just saw you there and everybody goes there. A *stale* one fans them out on
-- their own bearings, because standing on a spot nobody has confirmed in ten seconds is
-- not searching, it is waiting -- and an officer who does that reads as broken rather
-- than as looking for someone.
--
-- The player never sees this rule, only its consequence: hiding near where you were seen
-- works for about ten seconds and then stops working, so the correct play is to keep
-- moving away rather than to find one good bush. That is the behaviour worth having, and
-- it falls out of one `if`.
local function searchSpot(lastKnown: Vector3, sightingAge: number, post: number, radiusStuds: number): Vector3?
	if sightingAge < CRIME.SightingHoldSeconds then
		return Ground.SpotAt(lastKnown, Config.NPC.BodyRadius, Config.NPC.BodyHeight, sightIgnore()) or lastKnown
	end

	-- Spread. Each post keeps its own slice of the circle so that officers do not all
	-- wander to the same side, and the slice is offset by how long the search has run so a
	-- long one sweeps rather than re-walking the same four spokes.
	local slice = 360 / math.max(1, #Police.Bodies)
	local bearing = (post - 1) * slice + sightingAge * 6
	-- Two thirds out rather than the full radius, so a spread search still covers the
	-- middle. At the full radius every officer stands on the rim of a circle with the
	-- player comfortably inside it.
	local out = radiusStuds * (2 / 3)
	return spotOut(lastKnown, bearing, out) or spotOut(lastKnown, bearing + slice / 2, out * 0.6)
end

-- Stops any walk this officer is on and forgets the leg. Called whenever the mode changes,
-- because a search leg that is still yielding when a pursuit starts would keep steering
-- the body toward a corner the player has already left.
local function dropLeg(officer: Officer)
	officer.legTarget = nil
end

local function removeOfficer(officer: Officer)
	dropLeg(officer)
	officer.visitor.destroy()
end

-- Takes every officer off a player. The single place a body is removed, and deliberately
-- ignorant of why -- arrest, cooling off, death, leaving, the harness turning the system
-- off and a new life all arrive here identically.
local function clearOfficers(player: Player)
	local list = officers[player]
	if list == nil then
		return
	end
	officers[player] = nil
	for _, officer in list do
		removeOfficer(officer)
	end
end

-- Puts one more body in the world, on its own thread because building a rig is a yielding
-- web call and the pursuit tick must not stop for it.
local function spawnOfficer(player: Player, post: number, near: Vector3, radiusStuds: number)
	if spawning[player] then
		return
	end
	spawning[player] = true

	task.spawn(function()
		local bearing = (post - 1) * (360 / math.max(1, #Police.Bodies)) + math.random() * 40
		local at = spotOut(near, bearing, math.max(radiusStuds, 1) * ARRIVE_AT_EDGE_SHARE)
			or spotOut(near, bearing + 90, math.max(radiusStuds, 1) * 0.5)
		if at == nil then
			-- The town has nowhere to put them. Not an error and not worth a warning every
			-- fifth of a second: the next tick asks again, and by then the player has moved
			-- and the geometry around their last known position is different.
			spawning[player] = false
			return
		end

		local body = Police.Body(post)
		local visitor = NPCService.Spawn(player, body, CFrame.new(at, near))
		spawning[player] = false

		if visitor == nil then
			return
		end

		-- Checked *after* the spawn rather than before, because the spawn yields and
		-- everything can have changed underneath it: the player may have cooled off, died,
		-- left, or been arrested by an officer that got there first. A body arriving into
		-- any of those is a policeman standing in an empty street forever.
		local list = officers[player]
		if list == nil or not enabled or BountyService.Get(player) <= 0 then
			visitor.destroy()
			return
		end

		visitor.setSpeed(CRIME.OfficerWalkSpeed)
		table.insert(list, {
			visitor = visitor,
			post = post,
			mode = "search",
			legTarget = nil,
			legRunning = false,
			contactFor = 0,
		})
	end)
end

-- Sends an officer walking to a fixed point, by route rather than in a straight line.
--
-- Pathfinding rather than a plain aim, and only here: a search leg is a walk across a
-- built town to somewhere the officer cannot see, which is exactly the case a straight
-- line fails at -- it ends with a body pressed into the side of a building. A pursuit
-- does the opposite and re-aims every tick, because the destination is a person who is
-- moving and a route computed to where they were is worse than useless.
local function walkLeg(player: Player, officer: Officer, to: Vector3)
	officer.legTarget = to
	officer.legRunning = true

	task.spawn(function()
		local visitor = officer.visitor
		-- Called on every waypoint. Everything that could have made this walk pointless is
		-- asked about here rather than trusted for the length of a crossing.
		local function shouldStop(): boolean
			return not enabled
				or visitor.gone()
				or officer.mode ~= "search"
				or officer.legTarget ~= to
				or BountyService.Get(player) <= 0
		end
		visitor.pathTo(to, shouldStop)
		officer.legRunning = false
	end)
end

-- One officer, for one tick. Returns true if this officer can see the player, which the
-- caller folds into the single sighting the whole response is allowed to produce.
local function tickOfficer(player: Player, officer: Officer, playerAt: Vector3?, elapsed: number): boolean
	local visitor = officer.visitor
	if visitor.gone() then
		return false
	end

	local tier = BountyService.TierOf(player)
	local at = visitor.at()

	local sees = playerAt ~= nil and canSee(at, playerAt, tier.sightStuds)

	if sees and playerAt ~= nil then
		if officer.mode ~= "pursue" then
			officer.mode = "pursue"
			dropLeg(officer)
		end
		-- Re-aimed every tick rather than pathed, because a humanoid holds the last
		-- destination it was given and the destination is a person who is running.
		visitor.moveTo(playerAt)

		-- Contact. Measured flat, because an officer at the bottom of a staircase is not
		-- holding onto anybody at the top of it -- but neither is a chase up a ramp meant
		-- to be an escape, and flat distance is what every other proximity check in this
		-- game means by near.
		if Ground.FlatDistance(at, playerAt) <= CRIME.ArrestStuds then
			officer.contactFor += elapsed
		else
			officer.contactFor = 0
		end
		return true
	end

	-- Lost them, or never had them.
	if officer.mode ~= "search" then
		officer.mode = "search"
		officer.contactFor = 0
	end
	officer.contactFor = 0

	local lastKnown, sightingAge = BountyService.LastKnown(player)
	if lastKnown == nil then
		-- Nobody has any idea. The officer stops rather than wandering: a police force
		-- with no information walking the streets at random would be indistinguishable
		-- from one that knows exactly where you are, and the player could not tell that
		-- their hiding had worked.
		if officer.legTarget ~= nil then
			dropLeg(officer)
			visitor.halt()
		end
		return false
	end

	-- A leg is already in flight and still going somewhere useful.
	if officer.legRunning then
		local target = officer.legTarget
		if target ~= nil and Ground.FlatDistance(target, lastKnown) <= tier.searchRadiusStuds then
			return false
		end
		-- The belief has moved further than this walk was ever going to cover. Dropping the
		-- target is what makes the in-flight leg's shouldStop go true and hand the body back.
		dropLeg(officer)
		return false
	end

	local target = officer.legTarget
	if target ~= nil and Ground.FlatDistance(at, target) > LEG_ARRIVED_STUDS then
		-- Walked it, did not arrive, and no leg is running -- the pathfind failed or was
		-- called off. Ask again next tick rather than hammering it this one.
		officer.legTarget = nil
		return false
	end

	local spot = searchSpot(lastKnown, sightingAge, officer.post, tier.searchRadiusStuds)
	if spot ~= nil then
		walkLeg(player, officer, spot)
	end
	return false
end

-- One player's whole response, for one tick.
local function tickPlayer(player: Player, elapsed: number)
	local bounty = BountyService.Get(player)
	local tier = BountyService.TierOf(player)
	local wanted = if enabled then tier.officers else 0

	if bounty <= 0 or wanted <= 0 then
		clearOfficers(player)
		return
	end

	local list = officers[player]
	if list == nil then
		list = {}
		officers[player] = list
	end

	-- Sweep bodies that have left the world under us -- a server clean-up, a rig that
	-- failed to build. Done before counting, so the count below is of officers that
	-- actually exist rather than of table entries.
	for index = #list, 1, -1 do
		if list[index].visitor.gone() then
			table.remove(list, index)
		end
	end

	-- Too many, because the player cooled down a tier. Removed from the end so the
	-- officers who keep their posts keep their bearings too, and a de-escalation looks
	-- like people being stood down rather than like the whole search restarting.
	while #list > wanted do
		local last = list[#list]
		table.remove(list, #list)
		removeOfficer(last)
	end

	local playerAt = characterPosition(player)

	local anySighting = false
	for _, officer in list do
		local fine, problem = pcall(function()
			if tickOfficer(player, officer, playerAt, elapsed) then
				anySighting = true
			end
		end)
		if not fine then
			warn(`[AGES] officer tick failed for {player.Name}: {problem}`)
		end
	end

	-- One sighting for the whole response rather than one per officer. Six officers all
	-- reporting the same player in the same frame is one fact, and pushing it six times
	-- would be six writes of an identical position -- harmless today, and exactly the kind
	-- of thing that stops being harmless the moment a sighting starts adding heat.
	if anySighting and playerAt ~= nil then
		BountyService.Sighted(player, playerAt)
	end

	-- The arrest, checked after every officer has moved, so that the officer who has been
	-- holding contact longest is the one that closes it regardless of table order.
	for _, officer in list do
		if officer.contactFor >= CRIME.ContactSeconds then
			if BountyService.Arrest(player) then
				-- Nothing is torn down here. The bounty is zero now, and the top of this
				-- function will read that on the next pass and take the whole response off
				-- the street -- which is the same line that handles cooling off, dying and
				-- the harness being switched off. One exit, not four.
				return
			end
		end
	end

	-- Too few. Asked for one at a time rather than all at once, because each is a yielding
	-- rig build and a manhunt arriving as six simultaneous web calls is a hitch on the
	-- server and a row of policemen materialising in step on the screen.
	if #list < wanted and not spawning[player] then
		local lastKnown = select(1, BountyService.LastKnown(player))
		local from = lastKnown or playerAt
		if from ~= nil then
			spawnOfficer(player, #list + 1, from, tier.searchRadiusStuds)
		end
	end
end

-- How many bodies are actually on a player right now. For the harness, and for the day
-- something else wants to know whether the street is busy.
function PoliceService.OfficerCount(player: Player): number
	local list = officers[player]
	if list == nil then
		return 0
	end
	local count = 0
	for _, officer in list do
		if not officer.visitor.gone() then
			count += 1
		end
	end
	return count
end

-- Everything off the street for one player, without touching their heat. For the harness
-- only.
--
-- There is deliberately no ResetForNewLife here, and no death hook, which makes this the
-- one system in the game LifeService does not have to remember to tear down. It cannot
-- have one -- this file reads BountyService, which spends years through LifeService, so a
-- call back the other way would close a require cycle -- and it turns out not to need one.
-- A dead player's heat reads as zero (see BountyService.Get) and a new life is a new
-- Lives.New() with the number already at zero, so both arrive at the same line at the top
-- of tickPlayer that handles cooling off, and the street empties on the next pass.
--
-- Worth stating rather than leaving to be rediscovered: if anything here ever starts
-- holding state that outlives a life, this stops being true and the hook has to be found
-- a home that does not cycle.
function PoliceService.Clear(player: Player)
	clearOfficers(player)
end

function PoliceService.SetEnabled(value: boolean)
	enabled = value
	if not value then
		for player in officers do
			clearOfficers(player)
		end
	end
end

function PoliceService.IsEnabled(): boolean
	return enabled
end

-- What the harness prints: every officer, where it is, what it thinks it is doing and how
-- close it is to making an arrest. The mode and the contact clock are the two things that
-- cannot be seen by standing in the street -- an officer walking toward you looks the same
-- whether it has seen you or is going to where you were.
function PoliceService.Describe(player: Player): string
	local list = officers[player]
	if list == nil or #list == 0 then
		return `no officers out — {if enabled then "on" else "off"}`
	end
	local parts: { string } = {}
	for _, officer in list do
		if officer.visitor.gone() then
			table.insert(parts, `post {officer.post}: gone`)
		else
			local at = officer.visitor.at()
			table.insert(
				parts,
				string.format(
					"post %d: %s at %d,%d contact %.1f/%.1f",
					officer.post,
					officer.mode,
					at.X,
					at.Z,
					officer.contactFor,
					CRIME.ContactSeconds
				)
			)
		end
	end
	return `{#list} out — {table.concat(parts, " · ")} — {if enabled then "on" else "off"}`
end

function PoliceService:Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		clearOfficers(player)
		spawning[player] = nil
	end)

	task.spawn(function()
		while true do
			local elapsed = task.wait(CRIME.TickSeconds)
			for _, player in Players:GetPlayers() do
				local fine, problem = pcall(tickPlayer, player, elapsed)
				if not fine then
					warn(`[AGES] police tick failed for {player.Name}: {problem}`)
				end
			end
		end
	end)
end

return PoliceService
