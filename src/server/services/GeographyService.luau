--!strict
-- Geography: the errand, and the one lesson where the game stops telling you where
-- things are.
--
-- The loop:
--
--   You are given a place's name -- "the pages & press, by the counter", "number 5, on
--   avenue 2" -- and nothing else. No lit disc, no beam, no line on the floor, no
--   distance counting down. You walk. When you get there the lesson says so and gives
--   you the next name. Three of them, then it is over.
--
-- What makes it a mechanic rather than a fetch quest:
--
--   The absence *is* the verb. Every other destination in AGES arrives as a gold disc
--   with a beam over it -- job pads, shift marks, event anchors, the toddler's lure --
--   and that is right, because in every one of those systems finding the place is
--   overhead in front of the activity. Here finding the place is the activity, and the
--   moment a marker appears the subject has nothing left in it. This file therefore
--   never touches GuideUpdated, and that is a design constraint rather than an omission.
--
--   Mastery buys back help, one rung at a time, and buys nothing else. Level one is the
--   name alone. Level two adds roughly which end of town. Level three puts an arrow on
--   the screen. Level four adds how far. Level five tops the subject out and buys the
--   right to skip it, like every other subject's top rung. That is Bully's map markers:
--   a level is felt as the town becoming legible, not as a number going up, which is the
--   whole of what this rebuild is for.
--
--   Failure is soft and measured in the verb's own units. A stop the clock ran out on
--   still pays for how much of the gap the player closed -- see Hunt.MissedCreditCap --
--   so being lost near the bookstore is worth more than never leaving the school, and a
--   missed stop moves the lesson on rather than ending it.
--
-- What this file is deliberately not:
--
--   It is not a second school. The door, the yearly cap, the smarts payout and the
--   verdict shares are School's, read from Config.School, and a hunt still spends one of
--   the three lessons in the year.
--
--   It does not own a list of places. Every destination is drawn from the live place
--   graph at the moment the lesson starts, so there is no content file here to fall out
--   of step with the world -- and a town that grows gets a richer subject for free,
--   which is exactly what happened to be needed while the city was being rebuilt
--   underneath it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Mastery = require(ReplicatedStorage:WaitForChild("school"):WaitForChild("Mastery"))
local Report = require(ReplicatedStorage:WaitForChild("school"):WaitForChild("Report"))

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local PlaceService = require(script.Parent.PlaceService)
local StatService = require(script.Parent.StatService)
local Ground = require(script.Parent.Parent.world.Ground)

type LifeData = Types.LifeData
type HuntState = Types.HuntState
type Place = Types.Place

local GeographyService = {}

local HuntUpdatedRemote = Remotes.Get("HuntUpdated")

local SCHOOL = Config.School
local HUNT = SCHOOL.Hunt

-- The subject id this service answers to. A constant rather than a parameter because
-- there is exactly one hunt subject; the day there is a second, this becomes an argument
-- and nothing else here changes.
local SUBJECT_ID = "geography"

-- The eight points of the compass, in clockwise order from north. Not a tunable and not
-- Config's: it is the compass. Eight rather than four because four cannot tell "the north
-- end of town" from "the far corner", and rather than sixteen because "north-north-east"
-- is precision a sector does not have and nobody says out loud anyway.
local COMPASS = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }

-- Degrees per compass sector, derived rather than written down so the two can never
-- disagree about how many there are.
local DEGREES_PER_SECTOR = 360 / #COMPASS

-- The ladder of help, as ranks. Every rung shows everything the rungs below it showed, so
-- a level is one number and the four questions below are all answered by comparing
-- against it.
local REVEAL_RANK: { [string]: number } = {
	name = 1,
	area = 2,
	bearing = 3,
	range = 4,
}

-- The two ladders have to be the same length, and this is the only place that can notice.
-- School.Mastery.Levels says how many rungs there are; Hunt.RevealedByLevel says what each
-- rung tells you. A sixth rung added to one and not the other is a promotion the verb has
-- no answer for -- the player is told they levelled up and the town does not get any more
-- legible -- which is the numbers-only progression this rebuild exists to remove,
-- arriving by accident.
--
-- Loud at require time rather than clamped quietly, because clamping is what hides it: the
-- level would work, the help would not, and nothing would ever say so. The same reasoning,
-- and the same shape, as ScienceService's check on RevealedStepsByLevel.
if #HUNT.RevealedByLevel ~= Mastery.Levels then
	error(
		`[AGES config] School.Hunt.RevealedByLevel has {#HUNT.RevealedByLevel} entries but School.Mastery.Levels`
			.. ` is {Mastery.Levels}. Every mastery rung has to say what it tells you about a destination, so the`
			.. ` list must have exactly one word per level. Add or remove one.`
	)
end

-- Each rung must name a kind of help this file knows how to give, and must never tell you
-- less than the rung below it. A ladder that goes back down is a promotion that takes the
-- arrow away, which would read as a bug in the arrow rather than as a typo in Config.
do
	local previous = 0
	for level, word in HUNT.RevealedByLevel do
		local rank = REVEAL_RANK[word]
		if rank == nil then
			error(
				`[AGES config] School.Hunt.RevealedByLevel[{level}] is "{word}", which Geography has no answer for.`
					.. ` It must be one of: name, area, bearing, range.`
			)
		end
		if rank < previous then
			error(
				`[AGES config] School.Hunt.RevealedByLevel[{level}] is "{word}", which tells the player less than`
					.. ` the rung below it. Levelling up must never take help away. Reorder the list.`
			)
		end
		previous = rank
	end
end

-- A leg has to have a band to land in.
if HUNT.MinLegStuds >= HUNT.MaxLegStuds then
	error(
		`[AGES config] School.Hunt.MinLegStuds ({HUNT.MinLegStuds}) is not below MaxLegStuds ({HUNT.MaxLegStuds}),`
			.. ` so no destination can ever be drawn in the band. Swap them.`
	)
end

-- One destination, live or closed.
type Stop = {
	index: number,
	id: string,
	label: string,
	at: Vector3,
	-- How far it was when it was given, and the nearest the player has been since. The
	-- pair is what a missed stop is scored on: the share of the original gap closed.
	startGap: number,
	nearest: number,
	secondsLeft: number,
}

-- One player's hunt. Only ever one -- you cannot be on two errands.
type Session = {
	-- Where the lesson began, which is the school. The compass sector sits here rather
	-- than on the player, because "it is over in the east" is a thing you are told once
	-- with the name and not a needle that swings as you walk. The arrow is the live one.
	origin: Vector3,
	-- Every place this lesson may send the player to, worked out once at Begin.
	--
	-- Cached, unlike PlaceService's own reads: a place moved in Studio mid-lesson would
	-- otherwise move the destination the player is currently walking to, which is a worse
	-- failure than a ninety-second delay before an edit takes effect.
	pool: { Place },
	used: { [string]: boolean },
	stops: number,
	current: Stop?,
	-- How many have been reached, which is what the player is shown, and the credit
	-- earned, which includes part-marks for the ones that were not. The two are different
	-- numbers on purpose -- "1 of 3" is a fact and 0.62 is a grade.
	found: number,
	credit: number,
	closed: number,
	-- The ladder, mirrored for the panel to draw. The profile is the single writer -- both
	-- are re-read off it whenever they can have moved -- so these two can never drift from
	-- what Mastery thinks.
	level: number,
	passes: number,
	-- The rung this life was on when the lesson opened, kept so the report card line can
	-- say whether this afternoon moved it.
	levelAtStart: number,
	-- The line about the stop just reached, held for a beat before the next name is given.
	arrived: string?,
	arrivedLeft: number,
	summary: string?,
	verdictLeft: number,
}

local sessions: { [Player]: Session } = {}

-- The last thing pushed to each player, so an unchanged state is not re-sent four times a
-- second. Same reason SchoolService and ScienceService keep one.
local pushed: { [Player]: string } = {}

-- Switched off by the harness. Same shape as School's, and checked in the same two places:
-- at the door, and on every tick of a hunt already running.
local enabled = true

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

local function ageYearsOf(data: LifeData): number
	return math.floor(data.ageMonths / 12)
end

local function levelOf(data: LifeData): number
	return Mastery.LevelOf(data, SUBJECT_ID)
end

-- How much this level tells you, as a rank. Clamped rather than indexed blind: a stored
-- level from a build with a longer ladder must not index off the end of a shorter one, and
-- the honest reading of "level 9 on a five-rung ladder" is the top rung. The require-time
-- check above makes that unreachable from Config; this covers the profile.
local function revealRankFor(level: number): number
	local ladder = HUNT.RevealedByLevel
	local rung = math.clamp(math.floor(level), 1, #ladder)
	return REVEAL_RANK[ladder[rung]] or 1
end

-- Degrees clockwise from north, where north is -Z -- the direction a Roblox character
-- faces at rest, and the one the world generators lay their avenues along.
local function bearingBetween(from: Vector3, to: Vector3): number
	local delta = to - from
	local degrees = math.deg(math.atan2(delta.X, -delta.Z))
	return (degrees + 360) % 360
end

local function sectorFor(degrees: number): string
	local index = math.floor(degrees / DEGREES_PER_SECTOR + 0.5) % #COMPASS
	return COMPASS[index + 1]
end

-- Somewhere a child could actually be sent. Two rules, both read off the world rather
-- than off a list of ids here:
--
--   A route node is not a destination. Roughly 174 of the city's 382 place points are
--   crossings and avenue midpoints -- see World.PlaceWaypointPrefix -- and "go to cross
--   street 4" names a road marking.
--
--   Upstairs is somebody's home. A verb that gives you a name and no marker can only be
--   played by a player who can see the destination from the street; a first-floor
--   apartment behind an unmarked door is not findable, it is already-known. See
--   Hunt.MaxRiseStuds.
local function eligiblePlaces(origin: Vector3): { Place }
	local prefix = Config.World.PlaceWaypointPrefix
	local out: { Place } = {}
	for _, place in PlaceService.All() do
		if string.sub(place.id, 1, #prefix) == prefix then
			continue
		end
		if math.abs(place.part.Position.Y - origin.Y) > HUNT.MaxRiseStuds then
			continue
		end
		table.insert(out, place)
	end
	return out
end

-- The next destination, drawn from `from` -- which is the school for the first stop and
-- the last place reached for the rest, so a hunt walks a loop around a district rather
-- than crossing the map and coming back.
--
-- Inside the band by preference, and the nearest thing to the band when the band is empty.
-- Falling back rather than failing matters: a lesson that cannot draw its third stop would
-- have to end early, and a lesson that ends early because of where the player happens to
-- be standing is a lesson that scores them for the town's layout.
local function drawStop(session: Session, from: Vector3): Place?
	local inBand: { Place } = {}
	local nearest: Place? = nil
	local nearestMiss = math.huge

	for _, place in session.pool do
		if session.used[place.id] then
			continue
		end
		local gap = Ground.FlatDistance(from, place.part.Position)
		if gap >= HUNT.MinLegStuds and gap <= HUNT.MaxLegStuds then
			table.insert(inBand, place)
			continue
		end
		-- How far out of the band it is, so the fallback picks the least wrong leg rather
		-- than simply the closest -- which on a crowded street would be the shop next door
		-- every time.
		local miss = if gap < HUNT.MinLegStuds then HUNT.MinLegStuds - gap else gap - HUNT.MaxLegStuds
		if miss < nearestMiss then
			nearestMiss = miss
			nearest = place
		end
	end

	if #inBand > 0 then
		return inBand[math.random(#inBand)]
	end
	return nearest
end

local function stateFor(player: Player): HuntState?
	local session = sessions[player]
	if session == nil then
		return nil
	end

	local stop = session.current
	if stop == nil then
		-- Between stops, or after the last one. The label of record is whatever the
		-- closing line or the arrival line is talking about, so the panel does not blank
		-- out mid-sentence.
		return {
			stop = math.min(session.closed + 1, session.stops),
			stops = session.stops,
			label = "",
			area = nil,
			bearing = nil,
			rangeStuds = nil,
			secondsLeft = 0,
			found = session.found,
			level = session.level,
			levelMax = Mastery.Levels,
			passes = session.passes,
			passesPerLevel = Mastery.PassesPerLevel,
			arrived = session.arrived,
			summary = session.summary,
		}
	end

	local rank = revealRankFor(session.level)

	-- Measured live from where the player is standing, not from the origin: the arrow and
	-- the range are the two pieces of help that are only worth having because they update
	-- as you walk. The sector is not -- it is a fact about the town, given once with the
	-- name, and it is measured from the school.
	local position = characterPosition(player) or session.origin

	return {
		stop = stop.index,
		stops = session.stops,
		label = stop.label,
		area = if rank >= REVEAL_RANK.area then sectorFor(bearingBetween(session.origin, stop.at)) else nil,
		bearing = if rank >= REVEAL_RANK.bearing then bearingBetween(position, stop.at) else nil,
		rangeStuds = if rank >= REVEAL_RANK.range then Ground.FlatDistance(position, stop.at) else nil,
		secondsLeft = math.max(0, stop.secondsLeft),
		found = session.found,
		level = session.level,
		levelMax = Mastery.Levels,
		passes = session.passes,
		passesPerLevel = Mastery.PassesPerLevel,
		arrived = session.arrived,
		summary = session.summary,
	}
end

local function push(player: Player)
	local state = stateFor(player)
	-- A digest rather than a deep compare, and it has to name every field that is drawn.
	-- The bearing and the range are quantised rather than compared exactly, because both
	-- move on every floating-point wobble of a walking character.
	--
	-- It does not save anything while a stop is live -- the clock is in here and the tick
	-- is a quarter second, so that term changes on every pass by construction. What it
	-- saves is the two beats where nothing is moving: the arrival pause and the closing
	-- line, both of which would otherwise re-send an identical snapshot four times a
	-- second for as long as they hold.
	local digest: string
	if state == nil then
		digest = "none"
	else
		digest = `{state.stop}/{state.stops}/{state.label}/{tostring(state.area)}/`
			.. `{if state.bearing ~= nil then math.floor(state.bearing) else "-"}/`
			.. `{if state.rangeStuds ~= nil then math.floor(state.rangeStuds) else "-"}/`
			.. `{math.floor(state.secondsLeft * 4)}/{state.found}/{state.level}/{state.passes}/`
			.. `{tostring(state.arrived)}/{tostring(state.summary)}`
	end

	if pushed[player] == digest then
		return
	end
	pushed[player] = digest
	HuntUpdatedRemote:FireClient(player, state)
end

-- Opens the next destination, or returns false when there is nothing left to open --
-- either because the lesson has had its three, or because the town ran out of places that
-- have not already been used.
local function openStop(session: Session, from: Vector3): boolean
	if session.closed >= session.stops then
		return false
	end
	local place = drawStop(session, from)
	if place == nil then
		return false
	end
	session.used[place.id] = true
	local at = place.part.Position
	local gap = Ground.FlatDistance(from, at)
	session.current = {
		index = session.closed + 1,
		id = place.id,
		label = place.label,
		at = at,
		startGap = gap,
		nearest = gap,
		secondsLeft = HUNT.SecondsPerStop,
	}
	return true
end

-- Scores the destination in hand and puts it away. `found` decides which of the two ways
-- it closes; both are worth something and neither ends the lesson.
local function closeStop(session: Session, stop: Stop, found: boolean)
	session.closed += 1
	session.current = nil

	if found then
		session.found += 1
		session.credit += 1
		session.arrived = `Found it -- {stop.label}.`
	else
		-- The share of the original gap the player actually closed, capped well below what
		-- arriving pays. Zero when they never got any nearer than they started, which is
		-- the honest score for not having looked.
		local closedShare = if stop.startGap > 0
			then math.clamp(1 - stop.nearest / stop.startGap, 0, 1)
			else 0
		session.credit += closedShare * HUNT.MissedCreditCap
		session.arrived = if closedShare >= 0.5
			then `Time -- you were close. It was {stop.label}.`
			else `Time. It was {stop.label}.`
	end

	session.arrivedLeft = HUNT.ArrivedSeconds
end

-- Ends the lesson and pays for it. `reason` changes the sentence but never the arithmetic.
--
-- The divisor is always the full three, never the number of stops that got as far as being
-- handed out, and that is what makes walking away cost something: an errand abandoned after
-- one find is a third of a lesson, not a whole lesson with one stop in it. The same rule a
-- quiz and a lab run on -- leaving early is a way of getting the rest wrong.
local function finish(player: Player, data: LifeData, session: Session, reason: string)
	local stop = session.current
	if stop ~= nil then
		closeStop(session, stop, false)
	end

	local share = if session.stops > 0 then math.clamp(session.credit / session.stops, 0, 1) else 0

	-- Graded through Report rather than against SCHOOL's thresholds directly, for the
	-- reason Report is shared at all: a hunt, a lab and a quiz are three ways of spending
	-- the same afternoon, and the day two of them disagreed about what a good one was would
	-- be the day the report card and the closing line said different things about it.
	local band = Report.BandFor(share)
	local gained = Report.SmartsFor(band)

	if gained ~= 0 then
		StatService.AddStat(player, "smarts", gained)
	end

	-- Banked once, on the whole lesson, rather than per stop the way a lab banks per bench.
	-- A bench is a self-contained procedure and a stop is not: three destinations are one
	-- errand, and paying the ladder three times for it would make Geography climb at three
	-- times the rate of every other subject.
	local level = Mastery.Record(data, SUBJECT_ID, share)

	-- Counted however it ended, including walked away from, for the reason a lesson is:
	-- otherwise a player could start, leave, and start again until they drew a set of
	-- destinations they liked the look of.
	data.lessonsThisYear += 1
	EventService.AwardAutonomy(player, 1)

	-- The promotion is reported only when this lesson moved it -- a card line reading
	-- "Geography, level 3" against an afternoon that began on that rung would read as
	-- though the afternoon had earned it.
	Report.RecordLesson(data, SUBJECT_ID, band, gained, if level > session.levelAtStart then level else nil)

	session.level = level
	session.passes = Mastery.PassesOf(data, SUBJECT_ID)

	local percent = math.floor(share * 100 + 0.5)
	local reward = if gained > 0 then `. +{gained} smarts.` else "."
	local opening = if reason == "left" then "You gave up on the errand." else "Errand over."
	session.summary = `{opening} {session.found} of {session.stops} found, {percent}%{reward}`
	session.arrived = nil
	session.arrivedLeft = 0
	session.verdictLeft = SCHOOL.VerdictSeconds
	push(player)
end

-- Why this player cannot be sent on an errand right now, or nil if they can. Only the
-- things Geography itself refuses -- the age, the yearly cap and the door are School's,
-- checked before this is ever called.
--
-- Takes the pool rather than working it out, so Begin walks the place graph exactly once.
-- Three hundred and eighty-two parts is cheap but it is not free, and the version of this
-- that scanned it twice was scanning it a second time only to count the same list.
local function refusalFor(pool: { Place }): string?
	if not enabled then
		return "There is no geography today."
	end
	if #pool < HUNT.Stops then
		-- Named rather than a shrug. Too few places is a build problem -- an unbuilt town,
		-- or a world whose place points are all route nodes -- and a developer who is told
		-- the count can go and look at the right thing.
		return `There is nowhere to send you: the town has {#pool} places in it and the errand needs {HUNT.Stops}.`
	end
	return nil
end

-- Starts a hunt from wherever the player is standing, which is the school. Returns false
-- with a reason worth saying out loud.
--
-- Unlike a lab, this is genuinely started from the player's own feet, and it has to be:
-- the first leg is measured from where they are, and the compass sector every later hint
-- is phrased against is anchored there too. A harness that skips the walk to school
-- therefore runs a real errand from wherever it was typed, which is the right thing for it
-- to do.
function GeographyService.Begin(player: Player, data: LifeData): (boolean, string?)
	if sessions[player] ~= nil then
		return false, "You are already on an errand."
	end
	local origin = characterPosition(player)
	if origin == nil then
		return false, "You are not standing anywhere yet."
	end
	local pool = eligiblePlaces(origin)
	local refusal = refusalFor(pool)
	if refusal ~= nil then
		return false, refusal
	end

	local level = levelOf(data)
	local session: Session = {
		origin = origin,
		pool = pool,
		used = {},
		stops = HUNT.Stops,
		current = nil,
		found = 0,
		credit = 0,
		closed = 0,
		level = level,
		passes = Mastery.PassesOf(data, SUBJECT_ID),
		levelAtStart = level,
		arrived = nil,
		arrivedLeft = 0,
		summary = nil,
		verdictLeft = 0,
	}

	if not openStop(session, origin) then
		-- Unreachable given the pool check above, which counts the same list this draws
		-- from. Kept because "the errand silently did not start" is the one outcome that
		-- would look like the school itself being broken.
		return false, "There is nowhere to send you from here."
	end

	sessions[player] = session
	push(player)
	return true, nil
end

local function tickPlayer(player: Player, elapsed: number)
	local session = sessions[player]
	if session == nil then
		return
	end

	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)

	-- The closing line, held for a beat and then the hunt is gone. Checked first so nothing
	-- below runs against a lesson that has already been scored.
	if session.summary ~= nil then
		session.verdictLeft -= elapsed
		if session.verdictLeft <= 0 then
			sessions[player] = nil
			pushed[player] = nil
			HuntUpdatedRemote:FireClient(player, nil)
			return
		end
		push(player)
		return
	end

	if not data.alive or not enabled then
		finish(player, data, session, "left")
		return
	end

	local position = characterPosition(player)
	if position == nil then
		-- Mid-respawn, so there is no body to be anywhere. The clock is deliberately held
		-- rather than run down: a player with no character cannot walk, and charging them
		-- for seconds they could not have used is charging them for the engine. Death is
		-- caught above, so this cannot be used to park the lesson.
		return
	end

	-- The beat after arriving, before the next name is given. Nothing else runs during it,
	-- which is what makes reaching somewhere land as a moment rather than as a line
	-- replaced mid-read.
	if session.arrivedLeft > 0 then
		session.arrivedLeft -= elapsed
		if session.arrivedLeft <= 0 then
			session.arrivedLeft = 0
			session.arrived = nil
			-- The next leg is measured from where the player is now rather than from the
			-- place they were sent to, which are the same spot when they arrived and are
			-- not when the clock ran out. Measuring from the missed destination would send
			-- a lost player somewhere near a place they never found.
			if not openStop(session, position) then
				finish(player, data, session, "over")
				return
			end
		end
		push(player)
		return
	end

	local stop = session.current
	if stop == nil then
		-- Nothing in hand and no beat running, which the two branches above should have
		-- made impossible. Ending it cleanly rather than spinning: a hunt with no
		-- destination is a lesson with nothing to do, and that is the stall this codebase
		-- treats as the worst failure shape.
		finish(player, data, session, "over")
		return
	end

	local gap = Ground.FlatDistance(position, stop.at)
	if gap < stop.nearest then
		stop.nearest = gap
	end

	if gap <= HUNT.ArriveRadiusStuds then
		closeStop(session, stop, true)
		push(player)
		return
	end

	stop.secondsLeft -= elapsed
	if stop.secondsLeft <= 0 then
		closeStop(session, stop, false)
		push(player)
		return
	end

	push(player)
end

-- Ends whatever is running and forgets this player entirely, without grading. The one
-- place a hunt ends ungraded, because in every case that calls it there is nobody left to
-- grade -- a player who left, or a life being started over.
local function forget(player: Player)
	sessions[player] = nil
	pushed[player] = nil
end

-- Whether this player is mid-errand. Read by SchoolService, which has to know both that a
-- player standing back on the school pad is not starting a second lesson and that a
-- birthday landing mid-errand is a year they turned up for.
function GeographyService.IsRunning(player: Player): boolean
	return sessions[player] ~= nil
end

-- A new life. Nobody inherits an education, and the mastery ladder is per life for exactly
-- the reason bonds and money are.
function GeographyService.ResetForNewLife(player: Player)
	forget(player)
	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		Mastery.Clear(Lives.Active(profile.Data), SUBJECT_ID)
	end
	HuntUpdatedRemote:FireClient(player, nil)
end

-- Studio harness: starts an errand from wherever the player is standing, skipping the walk
-- to school but nothing else. The destinations are drawn from the real place graph around
-- wherever that is, so this tests the errand that exists rather than one laid out for it.
function GeographyService.ForceStart(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	return GeographyService.Begin(player, Lives.Active(profile.Data))
end

-- Studio harness: counts the destination in hand as reached, without the walk.
--
-- The most useful command in this system by some distance, because the walk is thirty
-- seconds and it is in front of everything else worth testing -- the arrival beat, the
-- second leg being drawn from the right spot, the closing line, the report card row.
function GeographyService.ForceFind(player: Player): boolean
	local session = sessions[player]
	if session == nil or session.summary ~= nil then
		return false
	end
	local stop = session.current
	if stop == nil then
		return false
	end
	closeStop(session, stop, true)
	push(player)
	return true
end

-- Ends a hunt and grades it, exactly as running out of destinations would.
--
-- Refuses a lesson that has already been graded rather than grading it twice. Only
-- reachable from the harness -- `/geo end` twice inside the verdict beat, which is easy to
-- hit -- but grading is the one act in this verb that pays smarts and spends a lesson off
-- the year's allowance, and a command that can be held down for free smarts is not a
-- harness, it is a cheat.
function GeographyService.ForceEnd(player: Player): boolean
	local session = sessions[player]
	local profile = DataService.GetProfile(player)
	if session == nil or profile == nil or session.summary ~= nil then
		return false
	end
	finish(player, Lives.Active(profile.Data), session, "over")
	return true
end

-- Studio harness: sets the mastery level directly.
--
-- The other command worth having, because the thing mastery buys here is *the interface* --
-- a sector, then an arrow, then a distance -- and the only other way to see the top of that
-- ladder is to run eight good errands. Clamped rather than refused, so asking for level
-- nine gets the top rung.
function GeographyService.SetLevel(player: Player, level: number): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	local data = Lives.Active(profile.Data)
	Mastery.Set(data, SUBJECT_ID, level)

	-- Applied to a hunt in progress too, so the command can be run mid-walk and the arrow
	-- appear on the next tick. That is the whole point of being able to set it.
	local session = sessions[player]
	if session ~= nil then
		session.level = levelOf(data)
		session.passes = Mastery.PassesOf(data, SUBJECT_ID)
		push(player)
	end
	return true
end

function GeographyService.SetEnabled(value: boolean)
	enabled = value
end

function GeographyService.IsEnabled(): boolean
	return enabled
end

-- What the harness prints: whether the town can carry an errand at all, then who this
-- player is to it, then what is actually running -- the same order SchoolService.Describe
-- and ScienceService.Describe use, because somebody debugging one is usually about to debug
-- another.
function GeographyService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "geography: no profile loaded"
	end
	local data = Lives.Active(profile.Data)

	local origin = characterPosition(player)
	local town: string
	if origin == nil then
		town = "no character, so nothing can be measured"
	else
		local all = #PlaceService.All()
		town = `{#eligiblePlaces(origin)} places sendable of {all} tagged`
	end

	local level = levelOf(data)
	local ladder = HUNT.RevealedByLevel
	local shows = ladder[math.clamp(level, 1, #ladder)]
	local mastery = `level {level}/{Mastery.Levels}, shows {shows}, {Mastery.PassesOf(data, SUBJECT_ID)}`
		.. `/{Mastery.PassesPerLevel} passes`
		.. if Mastery.IsTopped(data, SUBJECT_ID) then " (topped out -- can skip)" else ""

	local running = "no errand"
	local session = sessions[player]
	if session ~= nil then
		local stop = session.current
		local where: string
		if session.summary ~= nil then
			where = "graded"
		elseif stop == nil then
			where = `between stops ({string.format("%.1f", session.arrivedLeft)}s beat)`
		else
			local gap = if origin ~= nil then Ground.FlatDistance(origin, stop.at) else -1
			where = `stop {stop.index} "{stop.id}" {math.floor(gap)} studs off,`
				.. ` {string.format("%.1f", stop.secondsLeft)}s left`
		end
		running = `{session.found}/{session.stops} found, {string.format("%.2f", session.credit)} credit | {where}`
	end

	return string.format(
		"geography: %s | %s | age %d | %s | %s",
		if enabled then "enabled" else "DISABLED",
		town,
		ageYearsOf(data),
		mastery,
		running
	)
end

function GeographyService:Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		forget(player)
	end)

	task.spawn(function()
		while true do
			local elapsed = task.wait(HUNT.TickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player, elapsed)
				if not ok then
					warn(`[AGES] geography tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

return GeographyService
