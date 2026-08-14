--!strict
-- Ordinary people recognising a face the police have described.
--
-- This is the chase's second opponent, and it exists because without it the whole of being
-- wanted is standing behind a wall for two and a half minutes while DecayPerSecond finishes.
-- That is the unskilled-dead-time anti-pattern sitting in the middle of the best part of the
-- system: the player has heat, officers, a search ring drifting across the street, and
-- nothing to do about any of it but wait. A town that recognises you turns hiding from a
-- wait into a route -- the empty back street is now genuinely better than the busy one, and
-- that is a decision made continuously rather than once.
--
-- Split from PoliceService for the reason every split in this tree is made: an officer and a
-- passer-by are asking different questions. An officer is looking *for* you and closes; a
-- pedestrian is walking somewhere and happens to look up. Folding the second into the first
-- would mean the day somebody tunes a search radius is the day the crowd changes too.
--
-- Three rules, and each of them is what stops this being a punishment:
--
--   They only ever recognise a *described* face. The disguise is the answer to this
--   system, and a witness who reported somebody the police could not identify would make
--   the one verb the chase has worthless.
--
--   They react before they cost anything. The person stops and turns to face you the
--   moment they begin to notice, and the report only lands once that notice fills. That is
--   not decoration -- it is the entire warning this system gives, in the world rather than
--   on the HUD, the same way the shop camera is. It matters more now than it did: how long
--   the gap lasts depends on how conspicuous the player is, so the warning is short exactly
--   when the player is most exposed, and the turn is the only thing telling them so.
--
--   One person reports once every CooldownSeconds. Without it, standing in front of a
--   single pedestrian is a heat firehose, and the tier climbs on its own with nothing
--   interesting having happened.
--
-- What a report actually does is drag the sighting back onto you. The heat is small on
-- purpose: a witness is not a disaster, it is a reason to keep moving.
--
-- How fast anybody places you is not decided here. It is world/Spotting, shared with the
-- police, because "how much do you stand out" is one question and the day the crowd and the
-- officers answer it differently is the day neither can be reasoned about.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local BountyService = require(script.Parent.BountyService)
local PeopleService = require(script.Parent.PeopleService)

local Ground = require(script.Parent.Parent.world.Ground)
local Spotting = require(script.Parent.Parent.world.Spotting)

local WitnessService = {}

local CRIME = Config.Crime
local WITNESS = CRIME.Witness

-- One person's opinion of one player, this chase.
type Look = {
	-- How close this person is to placing the face, from 0 to 1. Reset the moment the line
	-- is lost, so ducking behind a van genuinely restarts their count rather than pausing it
	-- -- which is what makes breaking sight a move rather than a delay.
	--
	-- This used to be `heldFor`, a count of seconds against a flat 2.2. It fills at a rate
	-- now, and the rate is how conspicuous the player is -- so a citywide manhunt sprinting
	-- past in gang colors is placed in a fraction of the time a clean stranger walking is.
	-- That is the whole of what changed here, and it is the reason the bounty finally means
	-- something to the people in the street rather than only to the police.
	notice: number,
	-- Seconds until they will report again. Counts down whether or not they can see anybody,
	-- because it is about them having already made the call, not about the player.
	cooldown: number,
	-- Whether they are currently stopped and turned toward the player, so the release is
	-- sent once rather than every tick at a person already walking.
	alarmed: boolean,
}

local looks: { [Player]: { [string]: Look } } = {}
local enabled = true

local function looksFor(player: Player): { [string]: Look }
	local existing = looks[player]
	if existing ~= nil then
		return existing
	end
	local made: { [string]: Look } = {}
	looks[player] = made
	return made
end

local function lookFor(here: { [string]: Look }, personId: string): Look
	local existing = here[personId]
	if existing ~= nil then
		return existing
	end
	local made: Look = { notice = 0, cooldown = 0, alarmed = false }
	here[personId] = made
	return made
end

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return nil
	end
	return (root :: BasePart).Position
end

-- Everybody this player has stopped and turned, put back to walking.
--
-- Called whenever the reason to be looking goes away -- the heat drops, the description is
-- lost, the switch is thrown, the player dies -- and it has to be, because `holdFor` turned
-- their AutoRotate off and paused their wander. A crowd left alarmed is a street of people
-- standing perfectly still facing a spot where somebody used to be, forever.
local function calmAll(player: Player)
	local here = looks[player]
	if here == nil then
		return
	end
	for personId, look in here do
		if look.alarmed then
			look.alarmed = false
			PeopleService.Alarm(player, personId, nil)
		end
	end
end

local function forget(player: Player)
	calmAll(player)
	looks[player] = nil
end

-- One player's crowd, for one tick.
local function tickPlayer(player: Player, elapsed: number)
	local here = looksFor(player)

	-- The cooldowns run regardless of everything below, so a chase the player wins does not
	-- leave a street of people who will each report instantly the next time they see anybody.
	for _, look in here do
		if look.cooldown > 0 then
			look.cooldown = math.max(0, look.cooldown - elapsed)
		end
	end

	-- No description, no crowd. This is the disguise doing its work, and it is checked before
	-- anything expensive: a player who has just changed their clothes should cost this
	-- service one function call a tick, not a sweep of the street.
	if not BountyService.Described(player) then
		calmAll(player)
		return
	end

	local tier = BountyService.TierOf(player)
	if tier.officers <= 0 then
		-- Nobody is looking for you, so nobody in the street has been told to. Read off the
		-- tier rather than off the raw number so there is exactly one definition in the game
		-- of "the police are interested", and it is the one on the ladder in Config.
		calmAll(player)
		return
	end

	local at = characterPosition(player)
	if at == nil then
		calmAll(player)
		return
	end

	-- Every player's body, out of the way. Both ends of the ray are inside a character --
	-- the townsperson's own rig at one end, the player's at the other -- and a cast that
	-- stopped on the thing it was aimed at would report that nobody can ever see anybody.
	-- The player's end is covered by this list; the townsperson's by the engine, which does
	-- not register a hit on a part the ray starts inside.
	local ignore = Ground.IgnoreList()

	-- Read once for the whole street rather than per person: it is a property of the player
	-- being looked at, not of whoever is looking, and recomputing it inside the loop would
	-- price a busy pavement at one velocity read per pedestrian for an identical answer.
	local loud = BountyService.Conspicuousness(player)

	for _, bystander in PeopleService.Bystanders(player) do
		local look = lookFor(here, bystander.personId)
		local distance = Ground.FlatDistance(at, bystander.position)
		-- Line of sight is only asked for once the distance passes, because it is a raycast
		-- per person per tick and the distance is arithmetic. On a busy street that is the
		-- difference between a handful of casts and one for everybody in town.
		--
		-- Cast from them to you rather than the other way around, which is not symmetric
		-- here: the origin is what the engine forgives for being inside a body, and the
		-- destination is what the ignore list has to cover. The 0 eyeline is what this
		-- check has always used and is kept deliberately -- a pedestrian is not worth a
		-- second raycast profile.
		local sees = Spotting.CanSee(bystander.position, at, WITNESS.SeeStuds, 0, ignore)

		if not sees then
			look.notice = 0
			if look.alarmed then
				look.alarmed = false
				PeopleService.Alarm(player, bystander.personId, nil)
			end
			continue
		end

		-- Stopped and turned the instant they have you, not when the count finishes. The
		-- gesture *is* the warning, and a warning that arrived with the consequence would be
		-- a report with an animation on it.
		--
		-- Re-sent every tick rather than only on the change, so the turn follows a player who
		-- runs past them -- the same reason PeopleService re-holds somebody you are talking
		-- to. The flag is only there so the *release* is sent once, at a person who is
		-- already walking again.
		look.alarmed = true
		PeopleService.Alarm(player, bystander.personId, at)

		if look.cooldown > 0 then
			-- Already made their call. They still stop and stare -- somebody who recognised
			-- you a moment ago does not stop recognising you -- they just have nobody new to
			-- tell, which is the honest reading of a cooldown and costs the player nothing.
			continue
		end

		-- SeeSeconds is now what it takes to place a face of conspicuousness exactly 1 at
		-- point-blank, rather than a flat wait every observer served. A player who is
		-- barely wanted and walking is under 1 and takes longer than the old number; one
		-- at the top of the ladder, running, in colors is well over it and is placed in
		-- well under a second. The warning -- them stopping and turning -- still lands at
		-- the start of the fill either way, so the fast case is fast, not silent.
		look.notice += Spotting.NoticeRate(distance, WITNESS.SeeStuds, loud, WITNESS.SeeSeconds) * elapsed
		if look.notice >= 1 then
			look.notice = 0
			look.cooldown = WITNESS.CooldownSeconds
			-- Their position, not the player's, and this is the point of the whole system.
			-- A witness reports the corner they saw somebody on; by the time an officer gets
			-- there the player is a street away. Handing the player's own position over would
			-- make the crowd a perfect tracking network and delete the search entirely -- the
			-- same mistake BountyService's header warns about from the other side.
			BountyService.Seen(player, WITNESS.Heat, "Someone recognised you", bystander.position)
		end
	end
end

-- Off leaves the street walking and nobody reporting. On puts the crowd back. For telling a
-- witness bug apart from a pursuit one, which from the player's side look identical: in both
-- of them officers keep arriving at where you are.
function WitnessService.SetEnabled(value: boolean)
	enabled = value
	if not value then
		for _, player in Players:GetPlayers() do
			calmAll(player)
		end
	end
end

function WitnessService.IsEnabled(): boolean
	return enabled
end

-- For the harness, and phrased as the three questions a broken crowd raises: do they have a
-- description to work from, how many people are close enough to matter, and what is each of
-- them doing about it.
function WitnessService.Describe(player: Player): string
	local at = characterPosition(player)
	if at == nil then
		return "no body in the world"
	end

	local here = looks[player] or {}
	local watching = 0
	local cooling = 0
	local inRange = 0
	for _, bystander in PeopleService.Bystanders(player) do
		if Ground.FlatDistance(at, bystander.position) > WITNESS.SeeStuds then
			continue
		end
		inRange += 1
		local look = here[bystander.personId]
		if look == nil then
			continue
		end
		if look.alarmed then
			watching += 1
		end
		if look.cooldown > 0 then
			cooling += 1
		end
	end

	-- Conspicuousness is on here because it is the number that changed the behaviour and
	-- the one the player cannot see. A crowd that reports instantly and a crowd that never
	-- reports look like the same bug from outside, and this is what tells them apart.
	local loud = BountyService.Conspicuousness(player)
	return string.format(
		"witnesses %s · described %s · %d within %d studs (%d staring, %d already called it in)"
			.. " · conspicuousness %.2f · places a face in %.1fs at point blank",
		if enabled then "on" else "off",
		if BountyService.Described(player) then "yes" else "no -- nobody recognises you",
		inRange,
		WITNESS.SeeStuds,
		watching,
		cooling,
		loud,
		if loud > 0 then WITNESS.SeeSeconds / loud else math.huge
	)
end

function WitnessService:Start()
	Players.PlayerRemoving:Connect(forget)

	task.spawn(function()
		while true do
			local elapsed = task.wait(CRIME.TickSeconds)
			if enabled then
				for _, player in Players:GetPlayers() do
					local fine, problem = pcall(tickPlayer, player, elapsed)
					if not fine then
						warn(`[AGES] witness tick failed for {player.Name}: {problem}`)
					end
				end
			end
		end
	end)
end

return WitnessService
