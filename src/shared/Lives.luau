--!strict
-- What a life *is*, independent of who is playing it: how to make a fresh one, how to
-- repair a stored one, and how to find the one currently being played.
--
-- Replaces the old one-function `Life.luau`, which existed only to hold `HasBegun` where
-- `EventService` could reach it without closing a require cycle. That constraint still
-- applies -- this module requires Config and Types and nothing else, deliberately, so that
-- every service and both places can require it freely -- but there is now enough here to
-- justify the file on its own.
--
-- Shared rather than server-side because the lobby place needs all of it too: the lobby is
-- where lives are created, deleted and chosen, and it must build a slot the game place will
-- accept without a second definition of what a slot looks like.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LifeData = Types.LifeData
type ProfileData = Types.ProfileData

local Lives = {}

-- A brand new, unlived life.
--
-- A function rather than a constant table, and that is not a style preference. Three slots
-- built from one shared constant would share the *same* `stats`, `bonds` and `flags`
-- tables by reference, so a stat moved in slot 1 would move in slots 2 and 3 as well --
-- silently, and only for players who had more than one life going. Every call builds fresh
-- tables all the way down.
function Lives.New(): LifeData
	return {
		ageMonths = 0,
		stage = "Childhood",
		alive = true,
		stats = {
			health = Config.Stats.Starting.health,
			happiness = Config.Stats.Starting.happiness,
			smarts = Config.Stats.Starting.smarts,
			looks = Config.Stats.Starting.looks,
		},
		-- Read straight from Config rather than through MoneyService.StartingBalance,
		-- which everything else uses. This is also the template a *stored* life is repaired
		-- against, not only the start of one: it exists so that a save written before money
		-- did gets the field added, and there is no player to ask about at the moment it is
		-- filled in. Every actual life start goes through the service.
		money = Config.Money.StartingBalance,
		-- Both right for the newborn this describes, and both also right as the value a
		-- *stored* life is repaired to: a save that predates pocket money gains an empty
		-- ledger and a paid-through age of zero. Zero would back-pay a whole childhood at
		-- that life's next birthday, so PocketMoneyService moves it up to the age the life
		-- has actually reached before anything can read it.
		pocketMoneyOwed = 0,
		pocketMoneyPaidThroughAge = 0,
		secondsSinceAgeUp = 0,
		-- pendingEventId, deliveringEventId, jobId, gender and setup are all intentionally
		-- absent, and the absence is the meaning in every case: nothing outstanding, nothing
		-- staged in the world, holds no job, nobody decided yet, no life running. Because
		-- `Lives.Reconcile` fills a stored life from exactly this table, a field that is not
		-- here is a field it can never wrongly invent -- which is the entire reason the
		-- absent-means-something idiom is safe to rely on.
		seenEventIds = {},
		-- Empty is the correct state for a save written before flags existed too: an old
		-- life has done nothing the game can prove, which is exactly what filling this in
		-- says.
		flags = {},
		-- Starts at the top of the window rather than 0, so the first ambient delivery of a
		-- life is a wait and not an ambush the moment the player is old enough for one. The
		-- countdown only runs while they are that old, so this is not silently spent during
		-- childhood.
		deliveryCountdown = Config.Ambient.MaxSecondsBetween,
		deliveriesThisYear = 0,
		workGameHoursThisYear = 0,
		-- Empty, which reads the same as "no job has an opinion of you yet" -- true of the
		-- newborn this describes, and the right thing to hand a save written before records
		-- existed: that life's career starts being judged from now.
		jobStanding = {},
		-- Empty, which reads the same as "no job has let you go this year" -- true of the
		-- newborn, and the right thing to hand an old save: nobody arrives already sacked.
		firedFrom = {},
		-- Empty, which reads the same as "no machine has been worked out on this year" --
		-- true of the newborn, and the right thing to hand a save written before the gym
		-- existed: that life has not worked out this year, which is exactly true.
		workoutsThisYear = {},
		-- Right for the newborn this describes, and right for a save written before school
		-- existed: that life has sat no lessons this year, which is exactly true -- there was
		-- nothing to sit.
		lessonsThisYear = 0,
		-- Empty, which reads as level one in every subject with no passes banked -- true of
		-- the newborn, and true of a save written before subjects had verbs. An old life
		-- arrives at the lab as a beginner, which is what it is: it has never run a
		-- procedure, because until now there were none to run.
		subjectMastery = {},
		subjectPasses = {},
		-- Empty, which reads as "no lessons yet this year" and "no year finished yet" --
		-- true of the newborn, and the right thing to hand a save written before the record
		-- existed. That life's school years genuinely have no verdict: they were lived by a
		-- build that was not keeping one, and inventing grades for them here would be the
		-- game making up a childhood it did not watch.
		--
		-- `pendingReport` is intentionally absent, and the absence is the meaning: nothing
		-- staged, nothing to collect at the school.
		schoolYear = {},
		schoolGrades = {},
		-- Empty for a newborn, who has met nobody yet, and empty is also the honest thing to
		-- hand a save written before people existed. An absent key is "not met", and the
		-- authored starting bond is written the first time anything moves -- so a stored life's
		-- mother starts where every mother starts rather than at nothing, which would have the
		-- game open by telling them their family are strangers.
		bonds = {},
		-- Likewise empty: nobody has been visited, which for a save that predates visiting is
		-- true.
		visits = {},
		-- Empty for a newborn, who is nobody to anybody yet. Unlike the two fields above this
		-- costs a stored life nothing -- a tie is only ever conferred by an offer, so there is
		-- no year of anything to make up and nothing to be charged for having missed.
		ties = {},
		-- No heat and no record, which is true of a newborn and is the only safe thing to
		-- hand a save written before crime existed: an old life cannot be charged for a
		-- bounty that was never running, and inventing a conviction for a life the game was
		-- not watching would be the worst possible direction for this field to be wrong in.
		--
		-- Heat is persisted rather than held per session, and that is deliberate: it is the
		-- one number in the game a player would otherwise clear by pressing Leave. Logging
		-- out is the cheapest hiding place in any open world and it has to cost the same as
		-- every other one, which is to say it has to cost time.
		bounty = 0,
		convictions = 0,
		-- `gangId`, `gangRankId` and `leftGangAt` are all intentionally absent, and the
		-- absence is the meaning in each case: runs with nobody, holds no rung, has never
		-- walked away from one. Because Reconcile fills a stored life from exactly this
		-- table, a field that is not here is one it can never wrongly invent -- so a save
		-- written before gangs existed cannot arrive already in one, which is the only
		-- direction these three would be dangerous to be wrong in.
		--
		-- Empty, which reads as "no gang has an opinion of you yet" -- true of the newborn,
		-- and the right thing to hand an old save: that life's standing starts being kept
		-- from now rather than being back-paid for crimes nobody was counting.
		gangStanding = {},
		-- False rather than absent, because unlike the three above this one is read on
		-- every tick and an absent boolean would be a nil compared against `true` -- legal,
		-- silent, and wrong only for the lives that predate the field. False is also
		-- correct: a life not in a gang is not wearing anybody's colors.
		wearingColors = false,
		-- No houses owned, no home job linked. True of a newborn, and the right
		-- thing to hand a save written before house ownership existed.
		houses = {
			owned = {},
			homeJob = {},
		},
		-- No cars owned, none spawned. True of a newborn, and the right thing to
		-- hand a save written before vehicles existed: that life's garage starts
		-- empty rather than the game inventing a car it never bought.
		vehicles = {
			owned = {},
			active = nil,
		},
		-- Bills start at zero debt, first bill charged at month 0, zero shifts completed.
		bills = {
			debt = 0,
			lastBillMonth = 0,
			shiftsCompleted = 0,
		},
		-- No XP earned yet this life. Reset on death like money.
		workXp = 0,
		-- No milestones achieved, no bond milestones fired.
		milestones = {},
		bondMilestones = {},
	}
end

-- Fill in anything a stored life is missing, in place.
--
-- **This function is the entire reason the slot refactor is safe, and it exists because
-- ProfileStore's `Reconcile` cannot reach inside an array.** Reconcile walks the profile
-- template and fills absent keys, which covers every account-level field -- but `slots` is
-- a list, and a list in a template has no per-element shape to reconcile against. So the
-- day a new per-life field is added, every already-saved slot loads back missing it: no
-- error, no warning, just `nil` where a number should be, surfacing weeks later as
-- arithmetic on a nil value in whichever service happened to read it first.
--
-- Called for every slot on every load, so a save written by any older build is brought up
-- to the current shape before a single service sees it.
--
-- Deliberately additive only. It never overwrites a value that is present, including a
-- present-but-zero one, and it never *removes* a field this build no longer knows about --
-- a downgrade should cost the player nothing, and a stale field costs a few bytes.
function Lives.Reconcile(life: LifeData)
	-- Recursive rather than a flat key loop, because `stats` is a record with four keys of
	-- its own and a save written before a fifth stat existed needs that one key filled, not
	-- the whole table replaced. Safe on the map-shaped fields beside it -- `bonds`, `flags`,
	-- `visits`, `ties`, `jobStanding` are all empty in the template, so there is nothing to
	-- recurse into and a player's actual data is never walked.
	local function fill(target: { [string]: any }, template: { [string]: any })
		for key, value in template do
			local existing = target[key]
			if existing == nil then
				-- Copied rather than assigned when it is a table, for the same reason `New`
				-- is a function: handing the template's own table to a slot would let two
				-- slots repaired in the same load share it.
				if type(value) == "table" then
					local copy = {}
					fill(copy, value)
					target[key] = copy
				else
					target[key] = value
				end
			elseif type(existing) == "table" and type(value) == "table" then
				fill(existing, value)
			end
		end
	end

	fill(life :: any, Lives.New() :: any)
end

-- Whether this is a life being lived, or an empty slot.
--
-- The one fact about a life that anything is allowed to ask and that depends on nothing.
-- It is `setup` and not `alive` that answers it, because a dead life is still a life that
-- was lived -- it has a name, a country and a history, and the slot should say so. An
-- empty slot has never had a person in it at all.
function Lives.HasBegun(life: LifeData): boolean
	return life.setup ~= nil
end

-- Whether this life has ever been convicted, and what that costs.
--
-- Here rather than in BountyService, which is where the rest of crime lives and where these
-- three started, because a criminal record is not a fact about a chase -- it is a fact
-- about a life, and the two things that read it sit on opposite sides of the game. The
-- pursuit asks "does this face get recognised faster"; hiring asks "how high is this desk's
-- bar for this person", and hiring must never have to know that a police service exists.
--
-- The move was forced as well as right: WorkService -> BountyService -> LifeService ->
-- WorkService is a require cycle, and this file is the one place in the tree with a
-- standing promise to require nothing but Config and Types so that anybody can ask it
-- anything. `HasBegun` is here for exactly the same reason -- see its own note. Config
-- holds the numbers, this holds the one sentence in the codebase that says what they mean,
-- and BountyService keeps thin Player-flavoured wrappers for callers holding a Player.
function Lives.HasRecord(life: LifeData): boolean
	return life.convictions > 0
end

-- How much faster a known face turns into heat. One for a clean life, so every caller can
-- multiply unconditionally rather than branching on whether the player has a record -- a
-- branch that would eventually be written in one place and forgotten in another.
function Lives.SuspicionMultiplier(life: LifeData): number
	if not Lives.HasRecord(life) then
		return 1
	end
	return Config.Crime.Record.SuspicionMultiplier
end

-- Whether this life is currently wearing a gang's colors.
--
-- Both halves matter and neither implies the other: a member who has taken the band off is
-- in a gang and not wearing it, and `wearingColors` is only ever true alongside a gang
-- because taking a band off does not resign. Written as one question because every caller
-- wants the same one -- is there a bright band on this head right now.
function Lives.WearingColors(life: LifeData): boolean
	return life.gangId ~= nil and life.wearingColors
end

-- How much easier the colors make a life to describe, stacked on top of the record.
--
-- Here rather than in GangService for the reason the two above are here: BountyService is
-- what multiplies heat, and BountyService cannot require GangService without a cycle --
-- GangService needs the bounty to decide whether somebody got away. This file requires
-- nothing but Config and Types, so it is the one place both ends can reach.
--
-- Multiplied by the caller against the record multiplier rather than folded in here, so
-- that a life with a record wearing colors is charged for both -- which is correct, and is
-- the worst possible combination to be walking past a witness in.
function Lives.ColorsMultiplier(life: LifeData): number
	if not Lives.WearingColors(life) then
		return 1
	end
	return Config.Gangs.ColorsSuspicion
end

-- How much higher every job's stat bar sits for this life. Also one for a clean record, for
-- the same reason.
function Lives.HiringBarMultiplier(life: LifeData): number
	if not Lives.HasRecord(life) then
		return 1
	end
	return 1 + Config.Crime.Record.HiringBarIncrease
end

-- The life this profile is currently playing.
--
-- Errors rather than clamping if the slot is out of range. `activeSlot` is guaranteed valid
-- by DataService at load and is only ever written by code that has already bounds-checked
-- it, so an out-of-range value here is a bug in this codebase rather than bad data -- and
-- clamping would hand back somebody else's life while looking like it worked, which is the
-- worst possible failure for a save system to have.
function Lives.Active(data: ProfileData): LifeData
	local life = data.slots[data.activeSlot]
	if life == nil then
		error(
			`[AGES] active slot {data.activeSlot} does not exist -- the profile has {#data.slots} `
				.. `slot(s). Something wrote activeSlot without bounds-checking it against Config.Slots.Count.`
		)
	end
	return life
end

return Lives
