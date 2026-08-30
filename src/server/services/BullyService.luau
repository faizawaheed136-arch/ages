--!strict
-- The corridor between lessons, and holding your nerve in it.
--
-- The walk from the school door to the desk used to be zero studs long. You stepped on a
-- pad and a lesson happened, so there was nowhere for anything to be *between* lessons,
-- and twelve years of school were twelve years of arriving. This is what is in the way.
--
-- The loop:
--
--   Somebody steps across you in the corridor and says what they want. Two bars appear:
--   yours, rising while you hold the key, and theirs, falling on its own. Let go while
--   yours is in the band just above theirs and you have faced them down. Let go below it
--   and you backed off, and they take the toll. Hold past the band and you overcommitted,
--   which is worse than backing off, because now everybody is watching.
--
-- One key, and the release *value* is what scores it -- so the whole verb survives a
-- phone and survives 200ms of ping. Nothing here is a reflex test: the bars move slowly
-- enough to read, and what a player learns over thirty corridors is not faster fingers
-- but which of these three people is lying to them.
--
-- What makes it a decision rather than a button is that there are two clocks at the tiers
-- where the corridor sends people in pairs. The first bar says when the window opens; the
-- backup walking toward you says when it shrinks. Two queues at half load each, which is
-- the shape the activity law asks for -- and it is why the top tier is a second person
-- rather than a bigger number on the first.
--
-- Everything the player can lose here is upside. Backing down costs the toll and a point
-- of happiness; it never costs the lesson, never costs a rung of anything already earned,
-- and there is no state you can be put into that you have to wait your way out of. The
-- one thing that is *taken* is your homework, and that is a walk to the library rather
-- than a penalty -- burst, forced traversal, burst, which is the corridor generating its
-- own pacing out of the one consumable it has.
--
-- 13+ throughout, and by construction rather than by moderation. Nothing here is said
-- about the player: every line in content/Bullies.luau is about the toll or about who
-- moves first. There is no gore and no injury. The only door into contact at all is
-- overholding against somebody you have already faced down -- see Config.TipsIntoFight --
-- and what is on the other side of that door is FightService, which is already a contest
-- with a winner that ends with everybody back on their feet.
--
-- Split three ways for the reason the other school subjects are: Corridor lays the floor,
-- content/Bullies.luau says who stands on it, and this file is the only thing that knows
-- how a stare-down is scored. Re-laying the corridor must never be able to touch the
-- scoring, and writing a fourth bully must never require reading this file.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local DataService = require(script.Parent.DataService)
local FightService = require(script.Parent.FightService)
local MoneyService = require(script.Parent.MoneyService)
local NPCService = require(script.Parent.NPCService)
local PlaceService = require(script.Parent.PlaceService)
local SkillService = require(script.Parent.SkillService)
local StatService = require(script.Parent.StatService)
local Corridor = require(script.Parent.Parent.world.Corridor)
local School = require(script.Parent.Parent.world.School)
local Bullies = require(script.Parent.Parent.content.Bullies)

type LifeData = Types.LifeData
type NerveState = Types.NerveState
type BullyArchetype = Types.BullyArchetype
type Visitor = NPCService.Visitor

local BullyService = {}

local NerveUpdatedRemote = Remotes.Get("NerveUpdated")
local RequestNerveHoldRemote = Remotes.Get("RequestNerveHold")

local BULLY = Config.School.Bully
local NERVE = BULLY.Nerve
local DRAIN = BULLY.Drain
local TOLL = BULLY.Toll
local HOMEWORK = BULLY.Homework

-- The place id the corridor answers to. The same one SchoolService uses, because the
-- corridor is a room in that building and not a second location -- if these ever
-- disagreed the corridor would be laid around a school nobody attends.
local PLACE_ID = "school"

-- The ceiling nerve is measured against, borrowed from the stat scale rather than given a
-- number of its own. bullyNerve is not a stat, but it is written and read on the same
-- 0..100 scale as one, and a second ceiling here would be a second thing to keep in step.
local NERVE_MAX = Config.Stats.Max

-- One stare-down in progress. Only ever one per player: you cannot be stood in front of
-- by two people in two places, and the paired tiers are one encounter with a second body
-- walking into it rather than two encounters at once.
type Encounter = {
	archetype: BullyArchetype,
	visitor: Visitor,
	-- Both shares of the same bar, which is why neither carries a unit. Nerve starts where
	-- this life's nerve puts it and climbs while held; patience starts full and falls on
	-- its own, in the shape the archetype's drain names.
	nerve: number,
	patience: number,
	-- How wide the band above patience is. Fixed at engage rather than recomputed per tick,
	-- because it is what this life's nerve *buys* and a window that moved under the player
	-- mid-hold would make the same release score differently twice.
	windowWidth: number,
	holding: boolean,
	-- The bluffer lies exactly once. Recorded here rather than derived from the bar, since
	-- the bar passes through the trigger point twice once the jump has happened.
	bluffed: boolean,
	-- Seconds until a second bully arrives and the window closes to its narrowest, or nil
	-- at the tiers that do not send one.
	backupIn: number?,
	backup: Visitor?,
	-- Set the moment an outcome is decided, so a tick that lands during the closing beat
	-- cannot score the same encounter twice. Every write here is decided before it is
	-- recorded, which is the atomicity rule stated about one small thing.
	resolved: boolean,
}

local encounters: { [Player]: Encounter } = {}

-- When each bully last stepped across each player, so the same person does not work the
-- same corridor twice in a lesson. Keyed by player and then by archetype id.
local cooldowns: { [Player]: { [string]: number } } = {}

-- The closing line, and how long is left of it. Held apart from the encounter precisely
-- because it outlives one: what they say on the way out has to stay up for a beat after
-- everything else about the stare-down is gone.
local notices: { [Player]: { text: string, until_: number } } = {}

-- The last state pushed to each player, so an unchanged corridor is not re-sent ten times
-- a second. Same reason SchoolService keeps one: the bars are redrawn on receipt.
local pushed: { [Player]: string } = {}

-- Seconds a player has been stood at the library desk with taken homework. Cleared the
-- moment they walk off it, because a redo you can do in ten separate seconds spread over
-- an afternoon is not a walk, it is a formality.
local redoing: { [Player]: number } = {}

local enabled = BULLY.Enabled
local corridorBuilt = false

-- Where this player is, or nil if they have no body this instant. Every yield in this
-- file is a place a character can be torn down under it.
local function characterPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root == nil then
		return nil
	end
	return root.Position
end

local function ageYearsOf(data: LifeData): number
	return math.floor(data.ageMonths / Config.Time.MonthsPerYear)
end

-- Lays the corridor once the school building has streamed in. Retried rather than given
-- up on, for the reason SchoolService retries its own room: the building may still be
-- arriving, and a corridor that gave up on the first tick would never appear at all.
local function ensureCorridor(): boolean
	if corridorBuilt then
		return Corridor.Room() ~= nil
	end
	local place = PlaceService.Find(PLACE_ID)
	if place == nil then
		return false
	end
	corridorBuilt = true
	School.Build(place.part.Position)

	-- With the building up the hallway already exists, so the corridor lays no props of its
	-- own -- it only works out where people stand along it. Homework is redone in the actual
	-- library rather than at a desk invented at the end of the run, which is the whole reason
	-- that walk is worth making.
	local line = School.RoomAt("corridor")
	if line ~= nil then
		return Corridor.Build(line, false, School.RoomAt("library")) ~= nil
	end
	return Corridor.Build(place.part.Position, true, nil) ~= nil
end

-- Which tier this life is at, by how many corridors it has won. Walks the list rather
-- than indexing it so the tiers can be re-ordered in Config without this going wrong, and
-- returns the last one whose threshold is met.
local function tierFor(data: LifeData)
	local current = BULLY.Tiers[1]
	for _, tier in BULLY.Tiers do
		if data.bullyStandUps >= tier.standUps then
			current = tier
		end
	end
	return current
end

-- How wide the band above their patience is, for this life. The whole of what nerve buys,
-- and it is deliberately the *visible* thing rather than a hidden multiplier: the player
-- watches the green band grow as they get harder to push around, which is requirement six
-- of the activity law done the way Stardew does it rather than the way a wage does.
local function windowFor(data: LifeData): number
	local share = math.clamp(data.bullyNerve / NERVE_MAX, 0, 1)
	return NERVE.WindowMinShare + (NERVE.WindowMaxShare - NERVE.WindowMinShare) * share
end

-- Where nerve starts. Never zero -- a child who has never stood up to anybody still has
-- some, and a floor start would make the first corridor unwinnable rather than hard.
local function startingNerve(data: LifeData): number
	local share = math.clamp(data.bullyNerve / NERVE_MAX, 0, 1)
	return NERVE.BaseShare + NERVE.StatShare * share
end

local function notice(player: Player, text: string)
	notices[player] = { text = text, until_ = os.clock() + Config.UI.NoticeSeconds }
end

-- What the client is shown. Built fresh each tick and compared as a string before being
-- sent, which is cheaper than diffing the table and is the same trick SchoolService uses.
local function stateFor(player: Player): NerveState
	local encounter = encounters[player]
	if encounter == nil then
		local held = notices[player]
		local line = ""
		if held ~= nil and os.clock() < held.until_ then
			line = held.text
		else
			notices[player] = nil
		end
		return {
			active = false,
			bullyName = "",
			line = line,
			nerve = 0,
			patience = 0,
			windowLow = 0,
			windowHigh = 0,
			holding = false,
			secondsToBackup = nil,
		}
	end

	return {
		active = true,
		bullyName = encounter.archetype.body.name,
		line = encounter.archetype.openingLine,
		nerve = encounter.nerve,
		patience = encounter.patience,
		windowLow = encounter.patience,
		windowHigh = encounter.patience + encounter.windowWidth,
		holding = encounter.holding,
		secondsToBackup = encounter.backupIn,
	}
end

local function push(player: Player)
	local state = stateFor(player)
	-- Rounded before it is compared, or a bar drifting in the sixth decimal counts as a
	-- change every tick and the throttle does nothing at all.
	local signature = `{state.active}|{state.bullyName}|{state.line}|{math.floor(state.nerve * 100)}`
		.. `|{math.floor(state.patience * 100)}|{math.floor(state.windowHigh * 100)}|{state.holding}`
		.. `|{if state.secondsToBackup ~= nil then math.floor(state.secondsToBackup * 10) else -1}`
	if pushed[player] == signature then
		return
	end
	pushed[player] = signature
	NerveUpdatedRemote:FireClient(player, state)
end

-- Takes the bully out of the world and forgets the encounter. Safe to call twice: every
-- path out of a stare-down comes through here, including the ones that arrive from a
-- player leaving mid-hold.
local function clearEncounter(player: Player)
	local encounter = encounters[player]
	if encounter == nil then
		return
	end
	encounters[player] = nil
	if not encounter.visitor.gone() then
		encounter.visitor.destroy()
	end
	local backup = encounter.backup
	if backup ~= nil and not backup.gone() then
		backup.destroy()
	end
end

-- Records the outcome and pays for it. The one place any of this is written down, and it
-- decides everything before it writes anything -- so a retry cannot half-apply a result.
local function resolve(player: Player, data: LifeData, outcome: string)
	local encounter = encounters[player]
	if encounter == nil or encounter.resolved then
		return
	end
	encounter.resolved = true

	local archetype = encounter.archetype
	cooldowns[player] = cooldowns[player] or {}
	cooldowns[player][archetype.id] = os.clock() + BULLY.CooldownSeconds

	if outcome == "stood" then
		data.bullyStandUps += 1
		data.bullyNerve = math.clamp(data.bullyNerve + TOLL.NerveOnStandUp, 0, NERVE_MAX)
		StatService.AddStat(player, "happiness", TOLL.HappinessOnStandUp)
		-- The same nerve discipline getting away from the police pays into, deliberately
		-- rather than a school ladder of its own -- see Config.Skills.Awards.StoodUp. It is
		-- also the only progression here the player can see in a panel: bullyNerve widens the
		-- window and is felt rather than read, and this is the half that is read.
		SkillService.Award(player, "nerve", Config.Skills.Awards.StoodUp, "stood your ground")
		notice(player, archetype.standUpLine)
	elseif outcome == "backed" then
		data.bullyNerve = math.clamp(data.bullyNerve + TOLL.NerveOnBackDown, 0, NERVE_MAX)
		StatService.AddStat(player, "happiness", TOLL.HappinessOnBackDown)
		if archetype.demand == "money" then
			-- Spend rather than Add with a negative, so a life with nothing on them simply
			-- has nothing taken instead of being driven below zero. Somebody who cannot pay
			-- the toll has already lost the thing this was about.
			MoneyService.Spend(player, TOLL.Money, "bully toll")
		elseif archetype.demand == "homework" then
			data.homeworkTaken = true
		end
		notice(player, archetype.backDownLine)
	else
		-- Overheld. Worse than backing off, and the only outcome with a door out of the
		-- corridor in it: against somebody already faced down at least once, a scene turns
		-- into a contest. Everything else about it costs exactly what backing off costs.
		StatService.AddStat(player, "happiness", TOLL.HappinessOnBackDown)
		if archetype.demand == "money" then
			MoneyService.Spend(player, TOLL.Money, "bully toll")
		elseif archetype.demand == "homework" then
			data.homeworkTaken = true
		end

		local tipped = false
		if BULLY.TipsIntoFight and data.bullyStandUps > 0 then
			-- Nil rather than a fighter id: a bully is not in content/Fighters.luau, and
			-- FightService picking its own opponent is the honest reading of "this turned
			-- into a fight" without inventing a fighter that has no other reason to exist.
			local started = FightService.Challenge(player, nil)
			tipped = started
		end
		if tipped then
			notice(player, "You went too far, and now it is a fight.")
		else
			notice(player, "You held it too long. Everybody saw.")
		end
	end

	clearEncounter(player)
	push(player)
end

-- Steps a running stare-down forward. Everything that can end one is decided here rather
-- than in the release handler, so an encounter cannot outlive the corridor it is in.
local function tickEncounter(player: Player, data: LifeData, encounter: Encounter, dt: number)
	if encounter.resolved then
		return
	end

	local archetype = encounter.archetype
	local fall = dt / archetype.patienceSeconds

	if archetype.drain == "steady" then
		encounter.patience -= fall
	elseif archetype.drain == "bluffer" then
		encounter.patience -= fall * DRAIN.BlufferRate
		if not encounter.bluffed and encounter.patience <= DRAIN.BlufferJumpAt then
			encounter.patience += DRAIN.BlufferJumpBy
			encounter.bluffed = true
		end
	else
		-- Mirror. Falls only against your own rise, so a player who does not hold is stood
		-- in front of by somebody who will wait all afternoon -- and one who leans hard
		-- brings the window forward faster than they are climbing toward it.
		if encounter.holding then
			encounter.patience -= NERVE.RisePerSecond * dt * DRAIN.MirrorFactor
		end
	end
	encounter.patience = math.max(encounter.patience, 0)

	if encounter.holding then
		encounter.nerve += NERVE.RisePerSecond * dt
	end

	local backupIn = encounter.backupIn
	if backupIn ~= nil then
		backupIn -= dt
		if backupIn <= 0 then
			-- They have arrived. The window closes to its narrowest whatever this life's
			-- nerve is, which is the second clock landing -- and the countdown is cleared so
			-- the client stops drawing a number that has stopped meaning anything.
			encounter.windowWidth = NERVE.WindowMinShare
			encounter.backupIn = nil
		else
			encounter.backupIn = backupIn
		end
	end

	-- Held all the way to the ceiling without ever letting go. Resolved as an overhold
	-- rather than left running, because a bar with nowhere left to go and no decision in it
	-- is exactly the dead time this system exists to remove.
	if encounter.nerve >= NERVE.OverholdCeilingShare then
		resolve(player, data, "overheld")
	end
end

-- Whether this player could be stepped across right now. Every reason not to is checked
-- here rather than spread across the tick, so adding one is a line in one place.
local function eligible(player: Player, data: LifeData): boolean
	if not enabled or not BULLY.Enabled then
		return false
	end
	if not Lives.HasBegun(data) then
		return false
	end
	local age = ageYearsOf(data)
	if age < BULLY.MinAge or age > BULLY.MaxAge then
		return false
	end
	return true
end

-- Picks somebody to step across this player, or nil if nobody is free. Walks the age band
-- and skips anyone still on cooldown; returns nil rather than erroring when everyone is,
-- because "the corridor is quiet right now" is a normal state and not a content fault.
local function pickArchetype(player: Player, age: number): BullyArchetype?
	local now = os.clock()
	local held = cooldowns[player]
	local available: { BullyArchetype } = {}
	for _, archetype in Bullies.ForAge(age) do
		local until_ = if held ~= nil then held[archetype.id] else nil
		if until_ == nil or now >= until_ then
			table.insert(available, archetype)
		end
	end
	if #available == 0 then
		return nil
	end
	return available[math.random(1, #available)]
end

-- Starts a stare-down. Returns whether one began, so the debug path can say why not.
-- `standing` is the loiterer already at this station, when there is one. Passing it rather
-- than spawning is what removes the pop-in: the person you walk up to is the same body that
-- turns to face you, so the encounter starts by somebody *reacting* rather than by somebody
-- appearing. Nil falls back to spawning, which is what /bully forces and what happens if the
-- loiterer was lost to a stream-out between ticks.
local function engage(player: Player, data: LifeData, archetype: BullyArchetype, station: Vector3, standing: Visitor?): boolean
	if encounters[player] ~= nil then
		return false
	end
	local age = ageYearsOf(data)
	local visitor = standing
	if visitor == nil or visitor.gone() then
		visitor = NPCService.Spawn(player, archetype.body, CFrame.new(station), age + (archetype.body.ageOffset or 0))
	end
	if visitor == nil then
		-- The rig could not be built, which every caller of Spawn has to treat as "this did
		-- not happen". Silent on purpose: NPCService has already warned, and a second
		-- warning per tick would bury it.
		return false
	end

	local tier = tierFor(data)
	local room = Corridor.Room()
	local backup: Visitor? = nil
	local backupIn: number? = nil
	if tier.paired and room ~= nil then
		-- The second body starts at the far end and walks. Spawned as a real person rather
		-- than faked with a timer because the countdown has to be something the player can
		-- look at down the corridor and read without the HUD -- the world is the menu.
		local second = pickArchetype(player, age)
		if second ~= nil and second.id ~= archetype.id then
			backup = NPCService.Spawn(player, second.body, CFrame.new(room.finish), age + (second.body.ageOffset or 0))
			if backup ~= nil then
				backup.moveTo(station)
				backupIn = BULLY.BackupSeconds
			end
		end
	end

	visitor.face(characterPosition(player))
	visitor.talk()

	encounters[player] = {
		archetype = archetype,
		visitor = visitor,
		nerve = startingNerve(data),
		patience = 1,
		windowWidth = windowFor(data),
		holding = false,
		bluffed = false,
		backupIn = backupIn,
		backup = backup,
		resolved = false,
	}
	push(player)
	return true
end

-- The release, and the only commit in the system. Everything before it is free: a player
-- who has not let go can still walk away, which is the undo window the activity law asks
-- for -- mistakes are decisions here rather than gotchas.
local function onHoldRequested(player: Player, holding: unknown)
	if typeof(holding) ~= "boolean" then
		return
	end
	local encounter = encounters[player]
	if encounter == nil or encounter.resolved then
		return
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)

	if holding then
		encounter.holding = true
		push(player)
		return
	end
	if not encounter.holding then
		-- A release with no hold behind it. Ignored rather than scored: a client that fires
		-- the up edge on its own would otherwise be scoring an encounter the player never
		-- took part in.
		return
	end

	encounter.holding = false
	if encounter.nerve < encounter.patience then
		resolve(player, data, "backed")
	elseif encounter.nerve <= encounter.patience + encounter.windowWidth then
		resolve(player, data, "stood")
	else
		resolve(player, data, "overheld")
	end
end

-- The library desk, which is the whole of what a taken homework costs. Standing still for
-- a few seconds rather than a panel, because the walk down the corridor is the mechanic
-- and a button at the end of it would be a walk with a formality attached.
local function tickRedo(player: Player, data: LifeData, position: Vector3, dt: number)
	if not data.homeworkTaken then
		redoing[player] = nil
		return
	end
	local room = Corridor.Room()
	if room == nil then
		return
	end
	if (position - room.library).Magnitude > BULLY.EngageRadiusStuds then
		redoing[player] = nil
		return
	end

	local held = (redoing[player] or 0) + dt
	if held < HOMEWORK.RedoSeconds then
		redoing[player] = held
		return
	end
	redoing[player] = nil
	data.homeworkTaken = false
	notice(player, "You redid it. Nobody has to know.")
	push(player)
end

-- ---------------------------------------------------------------------------------------
-- Loiterers: the people standing in the corridor before anything has happened.
-- ---------------------------------------------------------------------------------------

-- One body per live station, standing there for as long as the player is in the building.
--
-- Keyed by player and then by station index, because a station is only live for the tier the
-- player has reached -- two players at different tiers are looking at different corridors, and
-- a shared pool would have to pick one of them to be wrong.
type Loiter = { visitor: Visitor, archetype: BullyArchetype }
local loiterers: { [Player]: { [number]: Loiter } } = {}
local loiterSpawning: { [Player]: { [number]: boolean } } = {}

local function clearLoiterers(player: Player)
	local mine = loiterers[player]
	if mine ~= nil then
		for _, entry in mine do
			if not entry.visitor.gone() then
				entry.visitor.destroy()
			end
		end
	end
	loiterers[player] = nil
	loiterSpawning[player] = nil
end

-- Takes the loiterer off the pool without destroying it, because it is about to become the
-- encounter. The encounter owns the body from here and clearEncounter is what ends it.
local function takeLoiterer(player: Player, index: number): Loiter?
	local mine = loiterers[player]
	if mine == nil then
		return nil
	end
	local entry = mine[index]
	mine[index] = nil
	return entry
end

local function tickLoiterers(player: Player, data: LifeData, position: Vector3)
	-- Nobody loiters for a player who cannot be bullied -- too young, too old, already in an
	-- encounter, or with the system off. The corridor being empty is then true rather than a
	-- rendering decision.
	if encounters[player] ~= nil or not eligible(player, data) then
		clearLoiterers(player)
		return
	end

	local room = Corridor.Room()
	if room == nil then
		clearLoiterers(player)
		return
	end

	-- Out of range: torn down, for the reason the school crowd is. A cohort of rigs standing in
	-- a corridor on the other side of the map is pure cost.
	if (position - room.start).Magnitude > BULLY.LoiterNearStuds then
		clearLoiterers(player)
		return
	end

	local tier = tierFor(data)
	local live = math.min(tier.stations, #room.stations)

	local mine = loiterers[player]
	if mine == nil then
		mine = {}
		loiterers[player] = mine
	end
	local spawning = loiterSpawning[player]
	if spawning == nil then
		spawning = {}
		loiterSpawning[player] = spawning
	end

	-- Stations that have stopped being live -- the tier dropped on a new life -- give their
	-- bodies back.
	for index, entry in mine do
		if index > live or entry.visitor.gone() then
			if not entry.visitor.gone() then
				entry.visitor.destroy()
			end
			mine[index] = nil
		end
	end

	local age = ageYearsOf(data)
	for index = 1, live do
		if mine[index] == nil and not spawning[index] then
			local archetype = pickArchetype(player, age)
			if archetype ~= nil then
				local station = room.stations[index]
				spawning[index] = true
				task.spawn(function()
					local visitor = NPCService.Spawn(player, archetype.body, CFrame.new(station), age + (archetype.body.ageOffset or 0))
					spawning[index] = false
					if visitor == nil then
						return
					end
					-- The pool may have been torn down while the web call was in flight -- the
					-- player walked out, died, or an encounter started with somebody else.
					local current = loiterers[player]
					if current == nil or current[index] ~= nil or encounters[player] ~= nil then
						visitor.destroy()
						return
					end
					current[index] = { visitor = visitor, archetype = archetype }
				end)
			end
		end
	end
end

local function tickPlayer(player: Player, dt: number)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)
	local position = characterPosition(player)
	if position == nil then
		return
	end

	tickRedo(player, data, position, dt)
	tickLoiterers(player, data, position)

	local encounter = encounters[player]
	if encounter ~= nil then
		-- Walking away. The undo window, and it costs nothing at all: nobody took anything
		-- and nobody learned anything, which is the honest outcome of a stare-down that did
		-- not happen. Deliberately a wider radius than the one that started it, so leaving
		-- is not a coin balanced on the edge of the distance you arrived through.
		if (position - encounter.visitor.at()).Magnitude > BULLY.ReleaseRadiusStuds then
			clearEncounter(player)
			push(player)
			return
		end
		encounter.visitor.face(position)
		tickEncounter(player, data, encounter, dt)
		push(player)
		return
	end

	if not eligible(player, data) then
		push(player)
		return
	end

	local room = Corridor.Room()
	if room == nil then
		push(player)
		return
	end

	-- Which stations are occupied is the whole of the escalation: at the bottom tier only
	-- the first is live and it is in the open where it can be seen from the door; higher up
	-- the later ones are too, and those are further in. The space changes, not the numbers.
	local tier = tierFor(data)
	local live = math.min(tier.stations, #room.stations)
	for index = 1, live do
		local station = room.stations[index]
		if (position - station).Magnitude <= BULLY.EngageRadiusStuds then
			-- The person already standing here, if there is one. Their archetype comes with them:
			-- the player has been looking at this body from down the corridor, and re-rolling who
			-- it is at the moment they arrive would make that look a lie.
			local standing = takeLoiterer(player, index)
			local archetype = if standing ~= nil then standing.archetype else pickArchetype(player, ageYearsOf(data))
			if archetype ~= nil then
				local body = if standing ~= nil then standing.visitor else nil
				if not engage(player, data, archetype, station, body) and body ~= nil then
					-- Refused -- already in an encounter. The body would otherwise be orphaned,
					-- since it is off the pool and was never handed to one.
					body.destroy()
				end
				break
			end
		end
	end
	push(player)
end

local function forget(player: Player)
	clearLoiterers(player)
	clearEncounter(player)
	cooldowns[player] = nil
	notices[player] = nil
	pushed[player] = nil
	redoing[player] = nil
end

-- Wipes the corridor for a life that has just ended. The bodies go with it: a bully is a
-- person this life met, and the next one has not met them.
function BullyService.ResetForNewLife(player: Player)
	forget(player)
	push(player)
end

-- Debug: put somebody in front of this player now, ignoring cooldowns and distance.
function BullyService.ForceEngage(player: Player, bullyId: string?): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	local data = Lives.Active(profile.Data)
	if encounters[player] ~= nil then
		return false, "already in a stare-down -- /nerve end first"
	end
	if not ensureCorridor() then
		return false, `no place point tagged "{PLACE_ID}" yet, so there is no corridor to stand in`
	end
	local room = Corridor.Room()
	if room == nil then
		return false, "the corridor could not be laid"
	end

	local archetype: BullyArchetype? = nil
	if bullyId ~= nil then
		archetype = Bullies.Get(bullyId)
		if archetype == nil then
			return false, `no bully "{bullyId}" -- see /nerve list`
		end
	else
		archetype = pickArchetype(player, ageYearsOf(data))
		if archetype == nil then
			return false, "everybody is on cooldown"
		end
	end

	local position = characterPosition(player)
	if position == nil then
		return false, "no character to stand in front of"
	end
	-- In front of the player rather than at a station, because the point of forcing one is
	-- to see it without walking to the corridor first.
	local at = position + (room.axis * BULLY.EngageRadiusStuds * 0.4)
	if not engage(player, data, archetype :: BullyArchetype, at) then
		return false, "the rig could not be built"
	end
	return true
end

-- Debug: end a running stare-down with a named outcome, so every branch can be seen
-- without having to land the release by hand.
function BullyService.ForceResolve(player: Player, outcome: string): (boolean, string?)
	if outcome ~= "stood" and outcome ~= "backed" and outcome ~= "overheld" then
		return false, `outcome must be stood, backed or overheld -- got "{outcome}"`
	end
	if encounters[player] == nil then
		return false, "not in a stare-down"
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	resolve(player, Lives.Active(profile.Data), outcome)
	return true
end

-- Debug: end a stare-down with no outcome at all, the way walking away does.
function BullyService.ForceEnd(player: Player): boolean
	if encounters[player] == nil then
		return false
	end
	clearEncounter(player)
	push(player)
	return true
end

-- Debug: set this life's nerve outright, which is the only way to see the window widen
-- without playing thirty corridors first.
function BullyService.SetNerve(player: Player, value: number): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	local data = Lives.Active(profile.Data)
	data.bullyNerve = math.clamp(math.floor(value), 0, NERVE_MAX)
	return true
end

-- Debug: hand the player their homework back, or take it.
function BullyService.SetHomeworkTaken(player: Player, taken: boolean): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	Lives.Active(profile.Data).homeworkTaken = taken
	push(player)
	return true
end

function BullyService.SetEnabled(value: boolean)
	enabled = value
	if not value then
		for player in encounters do
			clearEncounter(player)
			push(player)
		end
		-- And the people standing about waiting to start one. Without this, turning the system
		-- off left the corridor full of bullies who could no longer do anything -- which reads
		-- as broken rather than as disabled.
		for player in loiterers do
			clearLoiterers(player)
		end
	end
end

function BullyService.IsEnabled(): boolean
	return enabled and BULLY.Enabled
end

-- What the corridor looks like right now, for the debug path. Reads state and never
-- builds any, so describing the corridor cannot be the thing that creates it.
function BullyService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded"
	end
	local data = Lives.Active(profile.Data)
	local tier = tierFor(data)
	local room = Corridor.Room()
	local lines = {
		`enabled: {BullyService.IsEnabled()}`,
		`age: {ageYearsOf(data)} (corridor runs {BULLY.MinAge}-{BULLY.MaxAge})`,
		`nerve: {data.bullyNerve}/{NERVE_MAX}  window: {string.format("%.3f", windowFor(data))}`,
		`stood up: {data.bullyStandUps}  tier: {tier.label} ({tier.stations} station(s), paired={tier.paired})`,
		`homework taken: {data.homeworkTaken}`,
		`corridor: {if room ~= nil then `laid, {#room.stations} station(s)` else "not laid yet"}`,
	}
	local encounter = encounters[player]
	if encounter == nil then
		table.insert(lines, "no stare-down running")
	else
		table.insert(
			lines,
			`vs {encounter.archetype.body.name} ({encounter.archetype.drain}/{encounter.archetype.demand})`
				.. `  nerve {string.format("%.2f", encounter.nerve)}`
				.. `  patience {string.format("%.2f", encounter.patience)}`
				.. `  window {string.format("%.2f", encounter.patience)}..{string.format("%.2f", encounter.patience + encounter.windowWidth)}`
				.. `  holding={encounter.holding}`
		)
	end
	return table.concat(lines, "\n")
end

function BullyService:Start()
	Players.PlayerRemoving:Connect(forget)

	RequestNerveHoldRemote.OnServerEvent:Connect(function(player: Player, holding: unknown)
		local ok, err = pcall(onHoldRequested, player, holding)
		if not ok then
			warn(`[AGES] nerve hold failed for {player.Name}: {err}`)
		end
	end)

	task.spawn(function()
		while true do
			local elapsed = task.wait(BULLY.TickSeconds)
			-- The corridor first, then the people in it. A station that has not been laid yet
			-- is a station nobody can be stood at, and checking it per player would ask the
			-- same question once for everybody in the server.
			ensureCorridor()
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player, elapsed)
				if not ok then
					warn(`[AGES] corridor tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

return BullyService
