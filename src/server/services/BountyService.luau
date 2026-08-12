--!strict
-- Heat: the number the police are working from, and what it costs when they win.
--
-- Split from PoliceService for the reason Lab is split from ScienceService and Studio
-- from ArtService: how much trouble you are in and who is currently walking toward you
-- are different questions, and re-tuning a pursuit must never be able to touch what a
-- conviction does to a life. The dependency runs one way and only one way -- PoliceService
-- reads this file, this file has never heard of it. That is what lets an arrest be
-- implemented here as "set the number to zero" and lets the officers notice on their own
-- tick that there is no longer anybody to chase.
--
-- The two ideas worth reading before changing anything:
--
-- **The police do not know where you are.** They know where you were last *seen*, and
-- everything else is inference. This file owns that sighting -- when it happened, where,
-- and how stale it has got -- and it is the only thing in the system that does. An
-- officer asking "where do I go" is asking this file, and the honest answer is usually
-- wrong, which is the entire game.
--
-- **Heat is spent, not suffered.** A crime buys trouble at a price it sets itself. That
-- makes taking more a decision rather than a preference, and it is why the number is
-- public and continuous rather than a wanted flag: three quarters of a manhunt has to
-- feel different from all of one, or there is nothing to weigh.
--
-- Nothing here spawns a body, draws anything, or knows what a crime is. This is the
-- number.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)
local LifeService = require(script.Parent.LifeService)
local MoneyService = require(script.Parent.MoneyService)

type LifeData = Types.LifeData
type BountyState = Types.BountyState

local BountyService = {}

local CRIME = Config.Crime

local BountyUpdatedRemote = Remotes.Get("BountyUpdated")

-- One tier, as authored in Config.Crime.Tiers.
type Tier = {
	atLeast: number,
	name: string,
	officers: number,
	sightStuds: number,
	searchRadiusStuds: number,
}

-- What the police currently believe, per player. Session state rather than saved state,
-- and the split is exact: the *number* survives a disconnect because otherwise leaving is
-- a free escape, and everything in here does not, because a belief about where somebody
-- was standing four minutes ago in a session that has ended is not a belief worth keeping.
type Watch = {
	-- Where the police think you are. Nil means genuinely no idea, which is the state a
	-- player with heat on them is playing to reach.
	lastKnown: Vector3?,
	-- Seconds since that sighting. What turns a converge into a spread -- see
	-- Config.Crime.SightingHoldSeconds -- because officers who walk to a spot and stand on
	-- it read as broken rather than as searching.
	sightingAge: number,
	-- Seconds since anybody last had eyes on the player, and the thing the decay waits on.
	-- Starts at a number large enough to mean "not recently" rather than at zero, because
	-- zero would mean *just now* and would freeze the heat of somebody nobody has ever
	-- seen.
	unseenFor: number,
	-- Whether anybody had eyes on the player on the most recent tick. Held rather than
	-- recomputed because two different readers want it in the same tick and the answer is
	-- expensive enough to be worth asking once.
	seen: boolean,
	-- Whether anybody could say what you look like. Set by every sighting and destroyed
	-- by a change of clothes, and it is what ordinary people on the street read: a town
	-- can only recognise a face it has been given.
	--
	-- Separate from the heat on purpose. Heat is what you did; a description is what they
	-- know about who did it, and the whole of the disguise verb lives in the gap between
	-- those two. A player who has been reported but never actually seen -- which is not
	-- currently reachable, but will be the moment an alarm or a tip-off exists -- is
	-- wanted by a police force with nothing to go on, and that should mean something.
	described: boolean,
	notice: string?,
	noticeLeft: number,
}

local watches: { [Player]: Watch } = {}
local pushed: { [Player]: string } = {}
local enabled = true

-- Long enough to read as "nobody has seen you in a while" on the first tick of a life.
-- Any value past CoolStartSeconds does the same job; this one is obviously past it.
local NEVER_SEEN = 3600

-- The tiers, checked once at require time rather than trusted.
--
-- Every number in this system is read off this ladder, so a ladder that is out of order
-- or does not start at zero produces a game that is subtly wrong everywhere at once and
-- obviously wrong nowhere -- an officer count that goes down as heat goes up, or a player
-- at three points with nothing to look up. Both are one typo away and neither would throw.
local TIERS: { Tier } = CRIME.Tiers

do
	if #TIERS == 0 then
		error("[AGES config] Config.Crime.Tiers is empty, so no bounty could ever mean anything.")
	end
	if TIERS[1].atLeast ~= 0 then
		error(
			`[AGES config] Config.Crime.Tiers starts at {TIERS[1].atLeast} rather than 0, so a player`
				.. ` with no heat on them has no tier to be in. The first rung must be the clean one.`
		)
	end
	for index = 2, #TIERS do
		local under = TIERS[index - 1]
		local over = TIERS[index]
		if over.atLeast <= under.atLeast then
			error(
				`[AGES config] Config.Crime.Tiers is out of order: "{over.name}" starts at {over.atLeast},`
					.. ` which is not above "{under.name}" at {under.atLeast}. Tiers must climb.`
			)
		end
		if over.officers < under.officers then
			error(
				`[AGES config] Config.Crime.Tiers has "{over.name}" sending {over.officers} officers`
					.. ` where "{under.name}" below it sends {under.officers}. More heat must never mean`
					.. ` fewer police -- that is a difficulty curve that goes backwards.`
			)
		end
	end
	if TIERS[#TIERS].atLeast >= CRIME.MaxBounty then
		error(
			`[AGES config] the top tier "{TIERS[#TIERS].name}" starts at {TIERS[#TIERS].atLeast}, at or`
				.. ` above Config.Crime.MaxBounty of {CRIME.MaxBounty}, so it can never be reached.`
		)
	end
end

-- Deliberately no character-position helper in this file, unlike every other service that
-- ticks. Nothing here ever asks where the player actually is -- it could not do its job
-- honestly if it did. A sighting arrives with the position it was made from, because a
-- camera sees you where the camera is pointed and a witness reports the corner they saw
-- you on rather than wherever you got to afterwards.
local function watchFor(player: Player): Watch
	local existing = watches[player]
	if existing ~= nil then
		return existing
	end
	local made: Watch = {
		lastKnown = nil,
		sightingAge = 0,
		unseenFor = NEVER_SEEN,
		seen = false,
		described = false,
		notice = nil,
		noticeLeft = 0,
	}
	watches[player] = made
	return made
end

-- Everything the police believe about you, dropped: where you were, that they can see you,
-- and what you look like.
--
-- Not the heat. That is a number about what you *did* and it survives every one of the four
-- things that call this -- a change of clothes, an arrest, a debug wipe, and the moment the
-- number itself reaches zero. Keeping the two apart is what makes a disguise an escape
-- rather than an undo.
local function loseTrack(watch: Watch)
	watch.lastKnown = nil
	watch.seen = false
	watch.unseenFor = NEVER_SEEN
	watch.described = false
end

local function dataFor(player: Player): LifeData?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return Lives.Active(profile.Data)
end

-- Which rung a number sits on. Walks down rather than up so the *highest* matching tier
-- wins, which is the one the player is actually in.
local function tierFor(bounty: number): Tier
	for index = #TIERS, 1, -1 do
		local tier = TIERS[index]
		if bounty >= tier.atLeast then
			return tier
		end
	end
	return TIERS[1]
end

-- Which rung index, for the custody table, which is written against the same ladder.
local function tierIndexFor(bounty: number): number
	for index = #TIERS, 1, -1 do
		if bounty >= TIERS[index].atLeast then
			return index
		end
	end
	return 1
end

local function noticeFor(player: Player, text: string)
	local watch = watchFor(player)
	watch.notice = text
	watch.noticeLeft = 4
end

local function stateFor(player: Player): BountyState?
	local data = dataFor(player)
	if data == nil or not data.alive then
		return nil
	end
	local bounty = data.bounty
	local watch = watches[player]
	-- No heat and nothing being said about it is not a state worth a panel. Returning nil
	-- rather than a zeroed snapshot is what takes the HUD off screen entirely, which is
	-- right: a heat bar sitting at zero for the forty years somebody spends not committing
	-- crimes is furniture.
	if bounty <= 0 and (watch == nil or watch.notice == nil) then
		return nil
	end

	local tier = tierFor(bounty)
	local seen = watch ~= nil and watch.seen
	return {
		share = math.clamp(bounty / CRIME.MaxBounty, 0, 1),
		tier = tier.name,
		officers = tier.officers,
		seen = seen,
		cooling = not seen and watch ~= nil and watch.unseenFor >= CRIME.CoolStartSeconds and bounty > 0,
		lastKnown = if watch ~= nil then watch.lastKnown else nil,
		searchRadiusStuds = tier.searchRadiusStuds,
		hasRecord = data.convictions > 0,
		notice = if watch ~= nil then watch.notice else nil,
	}
end

local function push(player: Player)
	local state = stateFor(player)
	-- A digest rather than a deep compare, and it has to name every field that is drawn.
	--
	-- The last known position is quantised to whole studs on purpose. It is a Vector3 that
	-- moves every time an officer blinks at a walking player, and at full precision this
	-- would push a packet on every tick of every pursuit for a marker the player cannot
	-- see move by a tenth of a stud.
	local digest: string
	if state == nil then
		digest = "none"
	else
		local known = state.lastKnown
		digest = `{math.floor(state.share * 200)}/{state.tier}/{state.officers}/`
			.. `{tostring(state.seen)}/{tostring(state.cooling)}/`
			.. `{if known ~= nil then `{math.floor(known.X)},{math.floor(known.Z)}` else "-"}/`
			.. `{math.floor(state.searchRadiusStuds)}/{tostring(state.hasRecord)}/{tostring(state.notice)}`
	end

	if pushed[player] == digest then
		return
	end
	pushed[player] = digest
	BountyUpdatedRemote:FireClient(player, state)
end

local function forget(player: Player)
	watches[player] = nil
	pushed[player] = nil
end

-- One player's heat, for one tick. Everything in here is about the *number*; where the
-- officers are standing is PoliceService's tick and runs separately.
local function tickPlayer(player: Player, elapsed: number)
	local watch = watches[player]
	if watch == nil then
		return
	end

	if watch.noticeLeft > 0 then
		watch.noticeLeft -= elapsed
		if watch.noticeLeft <= 0 then
			watch.notice = nil
			watch.noticeLeft = 0
		end
	end

	local data = dataFor(player)
	if data == nil or not data.alive then
		push(player)
		return
	end

	watch.unseenFor += elapsed
	watch.sightingAge += elapsed
	-- Cleared here rather than by whoever set it, because "seen" is a claim about the tick
	-- that just happened and the only thing that knows a tick ended is this loop. An
	-- officer that still has eyes on the player will set it again before the next pass.
	watch.seen = false

	if data.bounty <= 0 then
		-- Heat gone means the belief goes with it. Without this an officer sent out by the
		-- next crime would start from a sighting that belonged to the last one, which reads
		-- as the police having remembered something they were never told. The description
		-- goes with it for the same reason: a town that kept recognising somebody nobody
		-- is looking for would be a spree's first crime following it for the rest of a life.
		loseTrack(watch)
		push(player)
		return
	end

	if not enabled then
		push(player)
		return
	end

	-- The freeze. Heat does not fall at all while somebody has eyes on you, and does not
	-- start falling the instant they lose them -- an officer who has just turned a corner
	-- has not given up looking, and a number that resumed cooling in the same frame would
	-- be telling the player that they had.
	if watch.unseenFor >= CRIME.CoolStartSeconds then
		data.bounty = math.max(0, data.bounty - CRIME.DecayPerSecond * elapsed)
		if data.bounty <= 0 then
			data.bounty = 0
			watch.lastKnown = nil
			noticeFor(player, "You are not being looked for any more.")
		end
	end

	push(player)
end

-- Raises the heat. The only way it ever goes up, and every caller has to say why -- the
-- reason is not decoration, it is what the notice on screen says, and a player who cannot
-- tell which of the things they just did was the expensive one cannot learn to do it
-- differently.
function BountyService.Add(player: Player, points: number, reason: string): number
	local data = dataFor(player)
	if data == nil or not data.alive or points <= 0 then
		return if data ~= nil then data.bounty else 0
	end

	local before = data.bounty
	data.bounty = math.clamp(before + points, 0, CRIME.MaxBounty)

	-- Only worth saying when it moves you between rungs. A running commentary on every
	-- point would be noise over the top of a chase, and the tier is what actually changed
	-- about the player's afternoon.
	local wasTier = tierFor(before)
	local nowTier = tierFor(data.bounty)
	if nowTier.name ~= wasTier.name then
		noticeFor(player, `{reason}. You are {nowTier.name}.`)
	end

	push(player)
	return data.bounty
end

-- Somebody has eyes on the player, right now, and this is where they are. Called by
-- PoliceService for an officer with line of sight, and later by a camera or a witness --
-- which is exactly why it takes a position rather than reading one: a camera sees you
-- where the camera is pointed, and a witness reports the corner they saw you on rather
-- than wherever you got to afterwards.
function BountyService.Sighted(player: Player, at: Vector3)
	local watch = watchFor(player)
	watch.lastKnown = at
	watch.sightingAge = 0
	watch.unseenFor = 0
	watch.seen = true
	-- Every sighting is also a description. Set here rather than at each call site so a
	-- disguise can never be defeated by one and not another: whatever saw you -- officer,
	-- camera, clerk, passer-by -- got a look at what you are wearing, and the one that
	-- forgot to say so would be a hole the player could find and nobody could explain.
	watch.described = true
end

-- Nobody can say what you look like any more.
--
-- The one thing in this system that moves a number *down* other than time, and it is
-- deliberately not the heat: what you did still stands, and there are still the same
-- officers out. What goes is where they think you are and who they are looking for --
-- so a converge becomes a search of somewhere you are not, and the street stops turning
-- to look at you. `seen` and `unseenFor` are reset with it because leaving them would
-- have the decay still frozen for a player nobody can identify.
--
-- Idempotent, and the caller is told whether it actually did anything: changing clothes
-- while already unrecognised should not be sold to the player as an escape.
function BountyService.LoseDescription(player: Player): boolean
	local watch = watches[player]
	if watch == nil or not watch.described then
		return false
	end
	loseTrack(watch)
	noticeFor(player, "Different clothes. They have lost you.")
	push(player)
	return true
end

-- Whether the police have anything to go on. Read by the crowd, which will not recognise
-- a face nobody has described to it.
function BountyService.Described(player: Player): boolean
	local watch = watches[player]
	return watch ~= nil and watch.described
end

-- Whether anybody had eyes on the player as of the last tick.
--
-- Already on the wire for the HUD; exported for the disguise, which needs the same fact on
-- the server and must not be given the pushed state to read it out of. It is a claim about
-- one tick and nothing longer -- see the note where the tick clears it -- which is exactly
-- what "not while they can see you" means.
function BountyService.IsSeen(player: Player): boolean
	local watch = watches[player]
	return watch ~= nil and watch.seen
end

-- Somebody saw the player do something, and it cost them. The sighting and the heat in one
-- call, because they are one event.
--
-- This is where a record has its teeth, and it is one function rather than a multiplier
-- sprinkled through every activity for the reason the comment on SuspicionMultiplier
-- already gives: a branch written in one place and forgotten in another is how a
-- consequence quietly stops applying to three of the four things that can trigger it. A
-- till, a camera, a witness and a bank guard all end up here, so all four recognise a known
-- face faster without any of them knowing that records exist.
--
-- Kept separate from Add rather than folded into it because Add is the ledger and has to
-- mean what it says: `/bounty 20` awarding 32 to a player with a conviction would be a
-- debug command that lies, and a flat penalty that has nothing to do with being observed
-- would pick up a multiplier that is explicitly about being observed.
function BountyService.Seen(player: Player, points: number, reason: string, at: Vector3): number
	local total = BountyService.Add(player, points * BountyService.SuspicionMultiplier(player), reason)
	BountyService.Sighted(player, at)
	return total
end

-- Where the police should be looking, and how wide. Nil means nobody has any idea, which
-- is a real answer and the caller has to have a plan for it.
--
-- The second return is how stale the belief is, and it is the thing that turns a converge
-- into a spread: officers all walking to one exact spot is what a fresh sighting looks
-- like, and officers fanning out from a spot nobody has confirmed in ten seconds is what
-- a search looks like. Same data, and the age is the whole difference.
function BountyService.LastKnown(player: Player): (Vector3?, number)
	local watch = watches[player]
	if watch == nil then
		return nil, 0
	end
	return watch.lastKnown, watch.sightingAge
end

-- The heat, and zero for a life that is over.
--
-- Death reading as zero here rather than as the stored number is what takes the officers
-- off the street when a player dies, and it is deliberately done in this one function
-- rather than as a death check inside the pursuit. PoliceService already has exactly one
-- line that removes a body -- "the tier says nobody should be out" -- and routing death
-- through it means dying, cooling off, being arrested and switching the system off all
-- leave by the same door. A second exit is a second thing to forget.
--
-- The stored number is left alone, not cleared. A life that ended wanted stays wanted in
-- the save; it is simply not being pursued any more, because there is nobody to pursue.
function BountyService.Get(player: Player): number
	local data = dataFor(player)
	if data == nil or not data.alive then
		return 0
	end
	return data.bounty
end

-- The tier a player is currently in. PoliceService reads this every tick to decide how
-- many bodies should be in the world and how far they can see.
function BountyService.TierOf(player: Player): Tier
	return tierFor(BountyService.Get(player))
end

-- The record, for callers holding a Player rather than a life.
--
-- Thin on purpose. What a conviction *means* is three functions in Lives, which requires
-- nothing but Config and Types precisely so that hiring -- on the far side of a require
-- cycle from here -- can ask the same question and get the same answer. These three are a
-- profile lookup and a forward, and the day they grow a rule of their own is the day the
-- record has two definitions again.
--
-- A player with no profile loaded reads as clean rather than as an error, because every
-- caller is in the middle of doing something else -- aiming a camera, refusing a job -- and
-- none of them has a sensible branch for "we do not know yet".
function BountyService.HasRecord(player: Player): boolean
	local data = dataFor(player)
	return data ~= nil and Lives.HasRecord(data)
end

function BountyService.SuspicionMultiplier(player: Player): number
	local data = dataFor(player)
	if data == nil then
		return 1
	end
	return Lives.SuspicionMultiplier(data)
end

function BountyService.HiringBarMultiplier(player: Player): number
	local data = dataFor(player)
	if data == nil then
		return 1
	end
	return Lives.HiringBarMultiplier(data)
end

-- Caught.
--
-- Deliberately not a death and deliberately not a wait. The player loses years, not
-- minutes: the sentence runs through the ordinary per-year path so those years decay
-- stats and cross stage boundaries exactly as if they had been lived -- because they
-- were -- and the player is never asked to sit in a room while it happens. A jail you
-- wait out is the purest form of the idle-time bug this project keeps designing away.
--
-- What is actually being charged here is the record. The years are the headline and the
-- record is the sentence: from now on this life is recognised faster and hired harder,
-- on every job and every crime, until it ends.
function BountyService.Arrest(player: Player): boolean
	local data = dataFor(player)
	if data == nil or not data.alive or data.bounty <= 0 then
		return false
	end

	-- Decided before anything is written, so a second arrest arriving behind this one --
	-- two officers making contact on the same tick -- finds the bounty already at zero and
	-- refuses at the door above rather than sentencing the player twice for one bust.
	local tierIndex = tierIndexFor(data.bounty)
	local years = CRIME.CustodyYearsByTier[tierIndex] or 0
	local carried = data.money

	data.bounty = 0
	data.convictions += 1

	loseTrack(watchFor(player))

	-- The haul, such as it is. Everything on you rather than a fixed fine, because a fine
	-- is a number and confiscation is the job not having happened -- which is the thing
	-- being said. Nothing to take is a perfectly good outcome and is not an error.
	if carried > 0 then
		MoneyService.Spend(player, carried, "confiscated on arrest")
	end

	-- Bounded by construction: one pass per year of the sentence, and the table it is read
	-- from is capped in Config. AgeUp refuses on its own once a life is over, so a sentence
	-- that outlives its owner stops rather than ageing a corpse.
	for _ = 1, years do
		if not data.alive then
			break
		end
		LifeService.AgeUp(player, "Custody")
	end

	local sentence = if years == 1 then "a year" else `{years} years`
	if years <= 0 then
		noticeFor(player, "Picked up and let go with a caution. It is on your record.")
	else
		noticeFor(player, `Convicted. {sentence} gone, and a record that does not go.`)
	end
	push(player)
	return true
end

-- Drops the heat without a conviction. For the debug harness and for the day something
-- legitimate forgives a bounty; not reachable by playing.
function BountyService.Clear(player: Player)
	local data = dataFor(player)
	if data ~= nil then
		data.bounty = 0
	end
	loseTrack(watchFor(player))
	push(player)
end

-- No ResetForNewLife, deliberately, and this is the one service LifeService does not have
-- to remember on a rebirth.
--
-- It could not have one anyway: this file spends years through LifeService, so a call the
-- other way would close a require cycle. But it also does not need one. Both fields this
-- system owns live on LifeData, and a new life is a new Lives.New() with `bounty` and
-- `convictions` already at zero -- so a newborn is clean by construction rather than by
-- being cleaned. The session state above is keyed by player rather than by life, and the
-- tick clears the stale belief within one pass of the number reading zero.
--
-- The record going is the only clean slate this game offers, and it costs exactly what
-- starting again costs, which is the right price for it.

function BountyService.SetEnabled(value: boolean)
	enabled = value
end

function BountyService.IsEnabled(): boolean
	return enabled
end

-- What the harness prints. Every number the pursuit is running on, in one line, because
-- the whole system is invisible by construction: heat, a belief and a search radius all
-- look identical from inside the game, which is a player standing in a street.
function BountyService.Describe(player: Player): string
	local data = dataFor(player)
	if data == nil then
		return "no profile loaded yet"
	end
	local watch = watches[player]
	local tier = tierFor(data.bounty)
	local known = if watch ~= nil then watch.lastKnown else nil
	return string.format(
		"bounty %.1f/%d (%s, %d officers, sight %d, search %d) · convictions %d (suspicion x%.2f, hiring bar x%.2f) · %s · last known %s (%.1fs old) · %s",
		data.bounty,
		CRIME.MaxBounty,
		tier.name,
		tier.officers,
		tier.sightStuds,
		tier.searchRadiusStuds,
		data.convictions,
		-- The record's two teeth, spelled out rather than left to be inferred from the
		-- conviction count. They are applied a long way from here -- one in a shop, one at
		-- a hiring desk -- and a tester who has to multiply in their head to check whether
		-- a record is working is a tester who will not check.
		Lives.SuspicionMultiplier(data),
		Lives.HiringBarMultiplier(data),
		if watch ~= nil and watch.seen then "IN SIGHT" else string.format("unseen %.1fs", if watch ~= nil then watch.unseenFor else 0),
		if known ~= nil then string.format("%d,%d", known.X, known.Z) else "nowhere",
		if watch ~= nil then watch.sightingAge else 0,
		if enabled then "on" else "off"
	)
end

function BountyService:Start()
	Players.PlayerRemoving:Connect(forget)

	task.spawn(function()
		while true do
			local elapsed = task.wait(CRIME.TickSeconds)
			for _, player in Players:GetPlayers() do
				local fine, problem = pcall(tickPlayer, player, elapsed)
				if not fine then
					warn(`[AGES] bounty tick failed for {player.Name}: {problem}`)
				end
			end
		end
	end)
end

return BountyService
