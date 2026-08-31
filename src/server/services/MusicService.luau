--!strict
-- Music: a rhythm held rather than a question answered.
--
-- The loop:
--
--   A count-in runs, then a needle sweeps a bar. Press the button while the needle is
--   over the beat -- centre for Perfect, near it for Good, anywhere else for Miss.
--   Eight notes make a song, then it is graded like every other lesson: a band, a smarts
--   payout, and a mastery pass banked toward the ladder.
--
-- This is the sweep every gym machine and every sports station already runs (see
-- shared/Sweep.luau), pointed at a beat instead of a rep -- exactly the reuse
-- content/Curriculum.luau names in its header comment on Music. What makes it a lesson
-- rather than a fifth drill station is the count-in: mastery here does not narrow the
-- window or slow the needle, it buys warning before the needle starts moving, which is
-- the same shape Geography's ladder gives a town becoming legible rather than an errand
-- becoming easier. See Config.School.Music for the numbers and the reasoning behind
-- each one.
--
-- No room of its own. The mechanic is a needle and a press and it reads the same
-- anywhere; this file runs it from the school's own front door (PlaceService.Find, the
-- same point SchoolService's quiz path attends at) and holds the player to it with
-- School.RoomRadiusStuds, exactly the radius the quiz path already enforces there. That
-- is a saving over Science and Art, which each needed a hand-built room because their
-- verbs are about a bench or a wall standing somewhere -- rhythm has no furniture to
-- stand in front of.
--
-- No teacher either, on the same reasoning Geography gives: a classroom drawn around a
-- player who is about to be looking at a sweep bar and nothing else is a room built for
-- nobody to look at.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Sweep = require(ReplicatedStorage:WaitForChild("Sweep"))
local Mastery = require(ReplicatedStorage:WaitForChild("school"):WaitForChild("Mastery"))
local Report = require(ReplicatedStorage:WaitForChild("school"):WaitForChild("Report"))

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local PlaceService = require(script.Parent.PlaceService)
local StatService = require(script.Parent.StatService)
local SkillService = require(script.Parent.SkillService)
local Ground = require(script.Parent.Parent.world.Ground)

type LifeData = Types.LifeData
type MusicState = Types.MusicState

local MusicService = {}

local MusicUpdatedRemote = Remotes.Get("MusicUpdated")
local RequestMusicNoteRemote = Remotes.Get("RequestMusicNote")

local SCHOOL = Config.School
local MUSIC = SCHOOL.Music
local SKILL_AWARDS = Config.Skills.Awards

-- The subject id this service answers to. A constant rather than a parameter because
-- there is exactly one rhythm subject; the day there is a second, this becomes an
-- argument and nothing else here changes. Mirrors GeographyService's SUBJECT_ID.
local SUBJECT_ID = "music"

-- The school's own place point. Music never builds a room -- see the header -- so it
-- reads the same anchor SchoolService's own quiz path attends at rather than owning a
-- second one that could drift from it.
local PLACE_ID = "school"

-- The two ladders have to be the same length, and this is the only place that can
-- notice. School.Mastery.Levels says how many rungs there are; CountInSecondsByLevel
-- says what each rung buys. A sixth rung added to one and not the other is a promotion
-- the verb has no answer for. The same check, and the same reasoning, as
-- GeographyService's on Hunt.RevealedByLevel and ArtService's on Art.PaletteByLevel.
if #MUSIC.CountInSecondsByLevel ~= Mastery.Levels then
	error(
		`[AGES config] School.Music.CountInSecondsByLevel has {#MUSIC.CountInSecondsByLevel} entries but`
			.. ` School.Mastery.Levels is {Mastery.Levels}. Every mastery rung has to say how much warning it`
			.. ` buys, so the list must have exactly one entry per level. Add or remove one.`
	)
end

-- Must never fall as level rises. A ladder that hands back less warning at a higher rung
-- is a promotion that takes help away, which would read as a bug in the count-in rather
-- than as a typo in Config.
do
	local previous = -math.huge
	for level, seconds in MUSIC.CountInSecondsByLevel do
		if seconds < previous then
			error(
				`[AGES config] School.Music.CountInSecondsByLevel[{level}] is {seconds}, less than the rung below`
					.. ` it. Levelling up must never take warning away. Reorder the list.`
			)
		end
		previous = seconds
	end
end

if MUSIC.PerfectFraction > MUSIC.SweetFraction then
	error(
		`[AGES config] School.Music.PerfectFraction ({MUSIC.PerfectFraction}) is wider than SweetFraction`
			.. ` ({MUSIC.SweetFraction}). Perfect has to be the narrower band inside Good, or nothing can ever`
			.. ` grade Good.`
	)
end

local SWEET_HALF = MUSIC.SweetFraction / 2
local PERFECT_HALF = MUSIC.PerfectFraction / 2

-- Song titles. Not a tunable and not Config's, the same call GeographyService's own
-- COMPASS list makes: flavour rather than a number, and which title comes up never
-- changes what the lesson asks of the player.
local SONG_TITLES = {
	"Two-Beat Waltz",
	"Corner Shuffle",
	"Back Porch Blues",
	"Schoolyard March",
	"Quiet Hallway",
	"Afternoon Swing",
	"Rooftop Echo",
	"Morning Bell",
}

-- One player's song. Only ever one -- you cannot sit two lessons at once.
type Session = {
	-- Where the lesson began, which is the school's own door. Held to this rather than
	-- re-read every tick, exactly as GeographyService pins a hunt's origin.
	at: Vector3,
	songLabel: string,
	-- Which note of how many, both 1-based -- the same shape Hunt's stop/stops gives.
	note: number,
	notes: number,
	-- Seconds still to count in before this note's sweep starts moving.
	countInLeft: number,
	sweptSeconds: number,
	progress: number,
	-- The running score, in the verb's own units: 1 per Perfect, GoodCreditShare per
	-- Good, 0 per Miss. Graded through Report exactly as Hunt's `credit` is.
	credit: number,
	-- Notes hit well enough to count -- Perfect or Good -- shown as "x of y" on the panel.
	hits: number,
	level: number,
	passes: number,
	-- The rung this life was on when the lesson opened, so the report card line can say
	-- whether this afternoon moved it.
	levelAtStart: number,
	-- The most recent note's grade, held for the beat after it lands. Cleared the moment
	-- the next note's count-in starts.
	grade: string?,
	noteVerdictLeft: number,
	-- The closing line, held for a beat and then the lesson is gone. Same slot and same
	-- read every other verb's summary gets.
	summary: string?,
	verdictLeft: number,
}

local sessions: { [Player]: Session } = {}

-- The last thing pushed to each player, so an unchanged state is not re-sent four times
-- a second. Same reason GeographyService and SportsDrillService each keep one.
local pushed: { [Player]: string } = {}

-- Switched off by the harness. Same shape as School's own, checked at the door and on
-- every tick of a song already running.
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

local function levelOf(data: LifeData): number
	return Mastery.LevelOf(data, SUBJECT_ID)
end

-- How long the count-in runs at a given level. Clamped rather than indexed blind, for
-- the same reason GeographyService.revealRankFor is: a stored level from a build with a
-- longer ladder must not index off the end of a shorter one.
local function countInFor(level: number): number
	local ladder = MUSIC.CountInSecondsByLevel
	local rung = math.clamp(math.floor(level), 1, #ladder)
	return ladder[rung]
end

-- Perfect, Good or Miss, from how far the needle was from centre when the button was
-- pressed. No dynamic widening by a stat, unlike the gym and the sports drill -- their
-- window grows with health because health is what they are paying for; this pays smarts
-- and academics, and the window is the whole of what mastery is not already spending on
-- the count-in.
local function gradeFor(progress: number): string
	local dist = math.abs(progress - MUSIC.SweetCenter)
	if dist <= PERFECT_HALF then
		return "Perfect"
	elseif dist <= SWEET_HALF then
		return "Good"
	end
	return "Miss"
end

local function stateFor(player: Player): MusicState?
	local session = sessions[player]
	if session == nil then
		return nil
	end

	local phase: string
	if session.summary ~= nil or session.noteVerdictLeft > 0 then
		phase = "verdict"
	elseif session.countInLeft > 0 then
		phase = "leadIn"
	else
		phase = "note"
	end

	return {
		phase = phase,
		songLabel = session.songLabel,
		note = session.note,
		notes = session.notes,
		countInSecondsLeft = math.max(0, session.countInLeft),
		progress = session.progress,
		sweetCenter = MUSIC.SweetCenter,
		sweetHalf = SWEET_HALF,
		perfectHalf = PERFECT_HALF,
		sweepSeconds = MUSIC.SweepSeconds,
		curve = MUSIC.Curve,
		elapsedShare = math.min(1, session.sweptSeconds / MUSIC.SweepSeconds),
		hits = session.hits,
		level = session.level,
		levelMax = Mastery.Levels,
		passes = session.passes,
		passesPerLevel = Mastery.PassesPerLevel,
		grade = session.grade,
		summary = session.summary,
	}
end

local function push(player: Player)
	local state = stateFor(player)
	local digest: string
	if state == nil then
		digest = "none"
	else
		digest = `{state.phase}|{state.note}/{state.notes}|{math.floor(state.countInSecondsLeft * 10)}`
			.. `|{math.floor(state.progress * 50)}|{state.hits}|{state.level}|{state.passes}`
			.. `|{tostring(state.grade)}|{tostring(state.summary)}`
	end
	if pushed[player] == digest then
		return
	end
	pushed[player] = digest
	MusicUpdatedRemote:FireClient(player, state)
end

-- Ends the song and pays for it. `reason` changes the sentence but never the arithmetic.
-- Guarded against running twice: the only callers are the tick loop and the harness, and
-- both can arrive here on a session that has already been graded.
local function finish(player: Player, data: LifeData, session: Session, reason: string)
	if session.summary ~= nil then
		return
	end

	local share = if session.notes > 0 then math.clamp(session.credit / session.notes, 0, 1) else 0
	local band = Report.BandFor(share)
	local gained = Report.SmartsFor(band)

	if gained ~= 0 then
		StatService.AddStat(player, "smarts", gained)
	end

	-- Banked once, on the whole song, rather than per note -- exactly as Hunt banks once
	-- per errand rather than per stop. Eight notes are one lesson, not eight.
	local level = Mastery.Record(data, SUBJECT_ID, share)

	data.lessonsThisYear += 1
	EventService.AwardAutonomy(player, 1)

	Report.RecordLesson(data, SUBJECT_ID, band, gained, if level > session.levelAtStart then level else nil)

	session.level = level
	session.passes = Mastery.PassesOf(data, SUBJECT_ID)

	local percent = math.floor(share * 100 + 0.5)
	local reward = if gained > 0 then `. +{gained} smarts.` else "."
	local opening = if reason == "left" then "You walked out of the lesson." else "Song over."
	session.summary = `{opening} {session.hits} of {session.notes} on the beat, {percent}%{reward}`
	session.grade = nil
	session.noteVerdictLeft = 0
	session.verdictLeft = SCHOOL.VerdictSeconds
	push(player)
end

-- Grades the note in hand. `pressed` is false when the sweep ran out with no press at
-- all -- a timeout is a Miss, exactly as an unanswered quiz question is wrong rather
-- than skipped.
local function answer(player: Player, session: Session, pressed: boolean)
	local grade = if pressed then gradeFor(session.progress) else "Miss"
	session.grade = grade

	if grade == "Perfect" then
		session.credit += 1
		session.hits += 1
		SkillService.Award(player, "academics", SKILL_AWARDS.RhythmPerfect, "perfect rhythm note")
	elseif grade == "Good" then
		session.credit += MUSIC.GoodCreditShare
		session.hits += 1
		SkillService.Award(player, "academics", SKILL_AWARDS.RhythmGood, "good rhythm note")
	end

	session.noteVerdictLeft = MUSIC.VerdictSeconds
	push(player)
end

-- Starts a song from wherever the school's door is. Returns false with a reason worth
-- saying out loud. Takes no position, exactly as ArtService.Begin does not: there is
-- exactly one door this verb ever starts from.
function MusicService.Begin(player: Player, data: LifeData): (boolean, string?)
	if sessions[player] ~= nil then
		return false, "You are already in a music lesson."
	end
	if not enabled then
		return false, "There is no music today."
	end
	local place = PlaceService.Find(PLACE_ID)
	if place == nil then
		return false, "The school has not been built."
	end

	local level = levelOf(data)
	local session: Session = {
		at = place.part.Position,
		songLabel = SONG_TITLES[math.random(#SONG_TITLES)],
		note = 1,
		notes = MUSIC.NotesPerSong,
		countInLeft = countInFor(level),
		sweptSeconds = 0,
		progress = 0,
		credit = 0,
		hits = 0,
		level = level,
		passes = Mastery.PassesOf(data, SUBJECT_ID),
		levelAtStart = level,
		grade = nil,
		noteVerdictLeft = 0,
		summary = nil,
		verdictLeft = 0,
	}

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

	-- The closing line, held for a beat and then the lesson is gone. Checked first so
	-- nothing below runs against a song that has already been scored.
	if session.summary ~= nil then
		session.verdictLeft -= elapsed
		if session.verdictLeft <= 0 then
			sessions[player] = nil
			pushed[player] = nil
			MusicUpdatedRemote:FireClient(player, nil)
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
		-- Mid-respawn: no body to be anywhere. The clock is held rather than run down,
		-- exactly as GeographyService.tickPlayer holds it, so nobody is charged for
		-- seconds the engine cost them.
		return
	end
	if Ground.FlatDistance(position, session.at) > SCHOOL.RoomRadiusStuds then
		finish(player, data, session, "left")
		return
	end

	-- Holding a note's grade on screen before the next count-in starts.
	if session.noteVerdictLeft > 0 then
		session.noteVerdictLeft -= elapsed
		if session.noteVerdictLeft > 0 then
			push(player)
			return
		end

		session.noteVerdictLeft = 0
		session.grade = nil
		session.note += 1

		if session.note > session.notes then
			finish(player, data, session, "over")
			return
		end

		session.countInLeft = countInFor(session.level)
		session.sweptSeconds = 0
		session.progress = 0
		push(player)
		return
	end

	-- The count-in, before the needle starts moving.
	if session.countInLeft > 0 then
		session.countInLeft = math.max(0, session.countInLeft - elapsed)
		push(player)
		return
	end

	-- The sweep itself.
	session.sweptSeconds += elapsed
	local elapsedShare = math.min(1, session.sweptSeconds / MUSIC.SweepSeconds)
	session.progress = Sweep.At(MUSIC.Curve, elapsedShare)

	if elapsedShare >= 1 then
		session.progress = 1
		answer(player, session, false)
		return
	end

	push(player)
end

-- Ends whatever is running and forgets this player entirely, without grading. The one
-- place a song ends ungraded, because in every case that calls it there is nobody left
-- to grade -- a player who disconnected, or a life being started over.
local function forget(player: Player)
	sessions[player] = nil
	pushed[player] = nil
end

local function onNoteRequested(player: Player)
	local session = sessions[player]
	if session == nil or session.summary ~= nil or session.countInLeft > 0 or session.noteVerdictLeft > 0 then
		return
	end
	answer(player, session, true)
end

-- Whether this player is mid-song. Read by SchoolService, which has to know both that a
-- player standing back on the school pad is not starting a second lesson and that a
-- birthday landing mid-song is a year they turned up for.
function MusicService.IsRunning(player: Player): boolean
	return sessions[player] ~= nil
end

-- A new life. Nobody inherits an education, and the mastery ladder is per life for
-- exactly the reason Geography's is.
function MusicService.ResetForNewLife(player: Player)
	forget(player)
	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		Mastery.Clear(Lives.Active(profile.Data), SUBJECT_ID)
	end
	MusicUpdatedRemote:FireClient(player, nil)
end

-- Studio harness: starts a song from wherever the player is standing, skipping the walk
-- to school but nothing else.
function MusicService.ForceStart(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	return MusicService.Begin(player, Lives.Active(profile.Data))
end

-- Studio harness: counts the note in hand as a Perfect, without waiting for the sweep or
-- the press. The most useful command in this system by the same margin
-- GeographyService.ForceFind is its own file's: the sweep is a couple of seconds and it
-- is in front of everything else worth testing -- the count-in, the note advancing, the
-- closing line, the report card row.
function MusicService.ForceHit(player: Player): boolean
	local session = sessions[player]
	if session == nil or session.summary ~= nil or session.countInLeft > 0 or session.noteVerdictLeft > 0 then
		return false
	end
	session.progress = MUSIC.SweetCenter
	answer(player, session, true)
	return true
end

-- Ends a song and grades it, exactly as running out of notes would. Refuses a song that
-- has already been graded rather than grading it twice, for the reason
-- GeographyService.ForceEnd refuses the same thing.
function MusicService.ForceEnd(player: Player): boolean
	local session = sessions[player]
	local profile = DataService.GetProfile(player)
	if session == nil or profile == nil or session.summary ~= nil then
		return false
	end
	finish(player, Lives.Active(profile.Data), session, "over")
	return true
end

-- Studio harness: sets the mastery level directly. Clamped rather than refused, so
-- asking for level nine gets the top rung.
function MusicService.SetLevel(player: Player, level: number): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	local data = Lives.Active(profile.Data)
	Mastery.Set(data, SUBJECT_ID, level)

	local session = sessions[player]
	if session ~= nil then
		session.level = levelOf(data)
		session.passes = Mastery.PassesOf(data, SUBJECT_ID)
		if session.countInLeft > 0 then
			session.countInLeft = countInFor(session.level)
		end
		push(player)
	end
	return true
end

function MusicService.SetEnabled(value: boolean)
	enabled = value
end

function MusicService.IsEnabled(): boolean
	return enabled
end

-- What the harness prints: whether the subject can run at all, then who this player is
-- to it, then what is actually running -- the same order GeographyService.Describe and
-- ArtService.Describe use.
function MusicService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "music: no profile loaded"
	end
	local data = Lives.Active(profile.Data)

	local place = PlaceService.Find(PLACE_ID)
	local doorLine = if place == nil then "school not built" else "school found"

	local level = levelOf(data)
	local mastery = `level {level}/{Mastery.Levels}, count-in {string.format("%.1f", countInFor(level))}s,`
		.. ` {Mastery.PassesOf(data, SUBJECT_ID)}/{Mastery.PassesPerLevel} passes`
		.. if Mastery.IsTopped(data, SUBJECT_ID) then " (topped out -- can skip)" else ""

	local running = "no song"
	local session = sessions[player]
	if session ~= nil then
		local where: string
		if session.summary ~= nil then
			where = "graded"
		elseif session.countInLeft > 0 then
			where = `count-in {string.format("%.1f", session.countInLeft)}s`
		elseif session.noteVerdictLeft > 0 then
			where = `verdict {tostring(session.grade)}`
		else
			where = `sweeping {string.format("%.2f", session.progress)}`
		end
		running = `"{session.songLabel}" note {session.note}/{session.notes}, {session.hits} hits, {string.format("%.2f", session.credit)} credit | {where}`
	end

	return string.format(
		"music: %s | %s | age %d | %s | %s",
		if enabled then "enabled" else "DISABLED",
		doorLine,
		math.floor(data.ageMonths / 12),
		mastery,
		running
	)
end

function MusicService:Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		forget(player)
	end)

	RequestMusicNoteRemote.OnServerEvent:Connect(function(player: Player)
		local ok, err = pcall(onNoteRequested, player)
		if not ok then
			warn(`[AGES] music note failed for {player.Name}: {err}`)
		end
	end)

	task.spawn(function()
		while true do
			local elapsed = task.wait(MUSIC.TickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player, elapsed)
				if not ok then
					warn(`[AGES] music tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

return MusicService
