--!strict
-- Music: the only lesson scored on when you act rather than on what you choose.
--
-- Four lanes, a chart falling down them, one thing to be good at. Every other subject in
-- this school asks a question -- which step, which colour, which letter, which word -- and
-- this one asks none, which is what keeps it from being one of the other five wearing
-- different furniture.
--
-- **The chart goes out complete, at the downbeat, and never again.** A player who can see
-- the next four bars is reading music; a player sent one note at a time is being startled,
-- and the difference is whether the thing being trained is anticipation or reflex. It is
-- also what makes the second queue possible: a held note occupies a hand while the other
-- three lanes keep arriving, so the piece is planned a bar ahead rather than reacted to.
--
-- **Timing is judged on the client and there is no honest alternative.** The window being
-- measured is 25 to 124 milliseconds and a Roblox round trip is longer than that, so a
-- server-timed rhythm game is not a strict rhythm game, it is an unplayable one. The client
-- therefore sends its own offset and the server treats it as a *claim*: the note must exist,
-- must not already be hit, the offset must be inside the widest window this life has earned,
-- and the note must have been due about now. That does not make cheating impossible. It
-- makes it cost more than playing, which is the honest bar for a 13+ school minigame where
-- the prize is smarts.
--
-- **What mastery buys is the windows, and this is the cleanest instance of that rule in the
-- game.** Level one is judged at 25/45/80ms and level five at 48/76/124. Nothing else
-- changes -- same chart, same tempo, same lanes -- and the player feels their own margin
-- widen. That is requirement six of the activity law done the way Stardew does it.
--
-- Failure is soft throughout: a miss scores nothing and costs nothing else. There is no
-- combo to break that takes points away, because a scoring rule that punishes is a scoring
-- rule that makes the last thirty seconds of a good run frightening.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Mastery = require(ReplicatedStorage:WaitForChild("school"):WaitForChild("Mastery"))
local Report = require(ReplicatedStorage:WaitForChild("school"):WaitForChild("Report"))

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local PlaceService = require(script.Parent.PlaceService)
local SkillService = require(script.Parent.SkillService)
local StatService = require(script.Parent.StatService)
local MusicRoom = require(script.Parent.Parent.world.MusicRoom)
local School = require(script.Parent.Parent.world.School)

type LifeData = Types.LifeData
type MusicState = Types.MusicState
type MusicNote = Types.MusicNote

local MusicService = {}

local MusicUpdatedRemote = Remotes.Get("MusicUpdated")
local RequestMusicHitRemote = Remotes.Get("RequestMusicHit")

local MUSIC = Config.School.Music
local CHART = MUSIC.Chart

local SUBJECT_ID = "music"
local PLACE_ID = "school"

-- Every rung has to buy something, and here every rung buys three things. Checked at require
-- time, the same guard Art keeps on its palette and Reading on its takebacks.
for _, pair in { { "PerfectMsByLevel", MUSIC.PerfectMsByLevel }, { "GreatMsByLevel", MUSIC.GreatMsByLevel }, { "GoodMsByLevel", MUSIC.GoodMsByLevel } } do
	local name = pair[1] :: string
	local list = pair[2] :: { number }
	if #list ~= Mastery.Levels then
		error(
			`[AGES config] Config.School.Music.{name} has {#list} entries but the mastery ladder has`
				.. ` {Mastery.Levels} rungs. Every rung has to widen the window, or a level-up is a`
				.. ` message with nothing behind it.`
		)
	end
end

-- The three windows must stay ordered at every level, or a hit lands in a band the judge
-- never reaches and the tighter grade becomes unreachable without anything erroring.
for level = 1, Mastery.Levels do
	if not (MUSIC.PerfectMsByLevel[level] < MUSIC.GreatMsByLevel[level] and MUSIC.GreatMsByLevel[level] < MUSIC.GoodMsByLevel[level]) then
		error(
			`[AGES config] Config.School.Music windows at level {level} are`
				.. ` {MUSIC.PerfectMsByLevel[level]}/{MUSIC.GreatMsByLevel[level]}/{MUSIC.GoodMsByLevel[level]}`
				.. ` -- they must widen in that order or the tighter grade is unreachable.`
		)
	end
end

type Session = {
	notes: { MusicNote },
	-- Which notes have been judged already, by index. A note is scored exactly once: without
	-- this a client could send the same perfect hit forty times.
	hit: { [number]: boolean },
	perfectMs: number,
	greatMs: number,
	goodMs: number,
	score: number,
	perfect: number,
	great: number,
	good: number,
	missed: number,
	streak: number,
	bestStreak: number,
	-- os.clock() at the downbeat.
	startedAt: number,
	endsAt: number,
	levelAtStart: number,
	atStand: boolean,
	line: string,
}

local sessions: { [Player]: Session } = {}
local pushed: { [Player]: string } = {}
local notices: { [Player]: { text: string, until_: number } } = {}
local enabled = true
local roomBuilt = false

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

local function levelOf(data: LifeData): number
	return Mastery.LevelOf(data, SUBJECT_ID)
end

local function ensureRoom(): boolean
	if roomBuilt then
		return MusicRoom.Room() ~= nil
	end
	local place = PlaceService.Find(PLACE_ID)
	if place == nil then
		return false
	end
	roomBuilt = true
	School.Build(place.part.Position)
	return MusicRoom.Build(School.RoomAt("music") or place.part.Position) ~= nil
end

local function notice(player: Player, text: string)
	notices[player] = { text = text, until_ = os.clock() + Config.UI.NoticeSeconds }
end

-- Writes a chart.
--
-- Generated rather than authored, unlike every other content bank in this tree, and the
-- reason is the one thing that makes rhythm different: a hand-written chart is a piece of
-- *music*, and thirty-six of them is a job for somebody who writes music. What a lesson
-- needs is a piece with shape -- rests, chords, holds, a ramp -- and that is a handful of
-- rules rather than a bank of files.
--
-- Held to the same standards a bank would be: it never opens on its hardest figure, it
-- always breathes, and a chord never lands twice in one lane.
local function writeChart(): { MusicNote }
	local notes: { MusicNote } = {}
	for beat = 1, CHART.Beats do
		if math.random() > CHART.NoteChance then
			continue
		end
		local atMs = (CHART.CountInBeats + beat) * CHART.BeatMs
		local ramped = beat > CHART.RampBeats
		local lane = math.random(1, MUSIC.Lanes)
		local holdMs = 0
		if ramped and math.random() < CHART.HoldChance then
			holdMs = CHART.HoldBeats * CHART.BeatMs
		end
		table.insert(notes, { atMs = atMs, lane = lane, holdMs = holdMs })

		-- The chord: a second note on the same beat in a different lane. Chosen by walking
		-- from a random offset rather than by rerolling until it differs, because a reroll
		-- loop with one lane free is a loop that can run a long time.
		if ramped and math.random() < CHART.ChordChance then
			local other = ((lane + math.random(1, MUSIC.Lanes - 1) - 1) % MUSIC.Lanes) + 1
			table.insert(notes, { atMs = atMs, lane = other, holdMs = 0 })
		end
	end
	return notes
end

local function stateFor(player: Player): MusicState
	local session = sessions[player]
	if session == nil then
		local held = notices[player]
		local line = ""
		if held ~= nil and os.clock() < held.until_ then
			line = held.text
		else
			notices[player] = nil
		end
		return {
			active = false,
			line = line,
			notes = {},
			startedAt = 0,
			perfectMs = 0,
			greatMs = 0,
			goodMs = 0,
			perfect = 0,
			great = 0,
			good = 0,
			missed = 0,
			streak = 0,
			bestStreak = 0,
			notesTotal = 0,
			secondsLeft = 0,
			atStand = false,
			masteryLevel = 1,
		}
	end

	local profile = DataService.GetProfile(player)
	local level = if profile ~= nil then levelOf(Lives.Active(profile.Data)) else 1

	return {
		active = true,
		line = session.line,
		notes = session.notes,
		startedAt = session.startedAt,
		perfectMs = session.perfectMs,
		greatMs = session.greatMs,
		goodMs = session.goodMs,
		perfect = session.perfect,
		great = session.great,
		good = session.good,
		missed = session.missed,
		streak = session.streak,
		bestStreak = session.bestStreak,
		notesTotal = #session.notes,
		secondsLeft = math.max(session.endsAt - os.clock(), 0),
		atStand = session.atStand,
		masteryLevel = level,
	}
end

local function push(player: Player)
	local state = stateFor(player)
	-- The chart is not in the signature. It is fixed for the whole lesson, it is the largest
	-- thing on the channel, and hashing it every tick to discover it has not changed would
	-- cost more than the throttle saves.
	local signature = `{state.active}|{state.line}|{state.perfect}|{state.great}|{state.good}`
		.. `|{state.missed}|{state.streak}|{state.atStand}|{math.floor(state.secondsLeft)}`
	if pushed[player] == signature then
		return
	end
	pushed[player] = signature
	MusicUpdatedRemote:FireClient(player, state)
end

local function finish(player: Player, data: LifeData, session: Session, reason: string)
	-- Decided before anything is written: work the outcome out, then record it.
	local total = #session.notes
	local share = if total > 0 then math.clamp(session.score / total, 0, 1) else 0
	local band = Report.BandFor(share)
	local gained = Report.SmartsFor(band)

	sessions[player] = nil

	if gained ~= 0 then
		StatService.AddStat(player, "smarts", gained)
	end

	Mastery.Record(data, SUBJECT_ID, share)

	local earned = math.floor(Config.Skills.Awards.MusicPiece * share)
	if earned > 0 then
		SkillService.Award(player, "academics", earned, "kept time")
	end

	data.lessonsThisYear += 1
	EventService.AwardAutonomy(player, 1)

	local level = levelOf(data)
	Report.RecordLesson(data, SUBJECT_ID, band, gained, if level > session.levelAtStart then level else nil)

	local percent = math.floor(share * 100 + 0.5)
	local opening = if reason == "played" then "That is the piece." elseif reason == "left" then "You walked off mid-bar." else "Time."
	local reward = if gained > 0 then `. +{gained} smarts.` else "."
	notice(player, `{opening} {percent}%, best run of {session.bestStreak}{reward}`)
	push(player)
end

-- One claimed hit. Everything about it is checked, because everything about it came from the
-- client -- see the note at the top of the file about why it has to.
local function onHitRequested(player: Player, index: unknown, offsetMs: unknown)
	local session = sessions[player]
	if session == nil then
		return
	end
	if typeof(index) ~= "number" or typeof(offsetMs) ~= "number" then
		return
	end
	if index ~= math.floor(index) or index < 1 or index > #session.notes then
		return
	end
	if session.hit[index] then
		return
	end
	if offsetMs ~= offsetMs then
		-- NaN. Compares false against every bound below, so it would slip through as a
		-- perfect. It arrives from a client that computed a hit against a zero clock.
		return
	end

	local note = session.notes[index]
	local magnitude = math.abs(offsetMs)
	if magnitude > session.goodMs then
		return
	end

	-- And the note has to have been due about now. This is the bound the offset cannot fake:
	-- a client can claim any offset it likes, but it cannot claim one for a note that is four
	-- bars away without the server noticing the wall clock disagrees.
	local dueAt = session.startedAt + note.atMs / 1000
	if math.abs(os.clock() - dueAt) * 1000 > MUSIC.AcceptMs then
		return
	end

	session.hit[index] = true
	if magnitude <= session.perfectMs then
		session.perfect += 1
		session.score += MUSIC.PerfectScore
	elseif magnitude <= session.greatMs then
		session.great += 1
		session.score += MUSIC.GreatScore
	else
		session.good += 1
		session.score += MUSIC.GoodScore
	end

	session.streak += 1
	if session.streak > session.bestStreak then
		session.bestStreak = session.streak
	end
	push(player)
end

-- Sweeps notes whose window has closed without a hit. Done on the server tick rather than
-- trusting the client to report its own misses, for the obvious reason: a client that never
-- reports a miss has a perfect run.
local function sweepMisses(session: Session)
	local now = os.clock()
	for index, note in session.notes do
		if not session.hit[index] then
			local dueAt = session.startedAt + note.atMs / 1000
			if now > dueAt + session.goodMs / 1000 then
				session.hit[index] = true
				session.missed += 1
				session.streak = 0
			end
		end
	end
end

local function tickPlayer(player: Player, _dt: number)
	local session = sessions[player]
	if session == nil then
		push(player)
		return
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end

	local position = characterPosition(player)
	local room = MusicRoom.Room()
	if position ~= nil and room ~= nil then
		session.atStand = (position - room.stand).Magnitude <= MUSIC.Build.ReachStuds
	end

	sweepMisses(session)

	-- Every note judged, or the clock ran out. The first is the normal end and arrives well
	-- before the second, which is a backstop for a player who walked off.
	local remaining = 0
	for index = 1, #session.notes do
		if not session.hit[index] then
			remaining += 1
		end
	end
	if remaining == 0 then
		finish(player, Lives.Active(profile.Data), session, "played")
		return
	end
	if os.clock() >= session.endsAt then
		finish(player, Lives.Active(profile.Data), session, "time")
		return
	end
	push(player)
end

-- The contract SchoolService dispatches against.
function MusicService.Begin(player: Player, data: LifeData): (boolean, string?)
	if sessions[player] ~= nil then
		return false, "You are already at the stand."
	end
	if not enabled then
		return false, "There is no music today."
	end
	if not ensureRoom() then
		return false, "The music room is closed today."
	end

	local notes = writeChart()
	if #notes == 0 then
		-- Possible only if NoteChance is set to zero, which is a config mistake rather than a
		-- content one. Said out loud rather than starting a silent lesson.
		return false, "There is nothing written on the stand today."
	end

	local level = levelOf(data)
	local lastMs = notes[#notes].atMs
	local session: Session = {
		notes = notes,
		hit = {},
		perfectMs = MUSIC.PerfectMsByLevel[level],
		greatMs = MUSIC.GreatMsByLevel[level],
		goodMs = MUSIC.GoodMsByLevel[level],
		score = 0,
		perfect = 0,
		great = 0,
		good = 0,
		missed = 0,
		streak = 0,
		bestStreak = 0,
		startedAt = os.clock(),
		-- The longer of the lesson cap and the piece itself plus a bar. A chart that outran
		-- the cap would be graded on the half of it that fitted.
		endsAt = os.clock() + math.max(MUSIC.SecondsPerLesson, lastMs / 1000 + 4),
		levelAtStart = level,
		atStand = false,
		line = "Four lanes. Count yourself in.",
	}

	sessions[player] = session
	notices[player] = nil
	push(player)
	return true
end

local function forget(player: Player)
	sessions[player] = nil
	notices[player] = nil
	pushed[player] = nil
end

function MusicService.ResetForNewLife(player: Player)
	forget(player)
	push(player)
end

function MusicService.ForceStart(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	return MusicService.Begin(player, Lives.Active(profile.Data))
end

function MusicService.ForceEnd(player: Player): boolean
	local session = sessions[player]
	if session == nil then
		return false
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	finish(player, Lives.Active(profile.Data), session, "left")
	return true
end

-- Debug: judge every remaining note at the given grade, so the scoring, the report line and
-- the mastery rung can be reached without playing a hundred-beat piece by hand.
function MusicService.Autoplay(player: Player, grade: string): (boolean, string?)
	local session = sessions[player]
	if session == nil then
		return false, "no piece running"
	end
	local value = if grade == "perfect" then MUSIC.PerfectScore elseif grade == "great" then MUSIC.GreatScore elseif grade == "good" then MUSIC.GoodScore else nil
	if value == nil then
		return false, `grade must be perfect, great or good -- got "{grade}"`
	end
	for index = 1, #session.notes do
		if not session.hit[index] then
			session.hit[index] = true
			session.score += value
			session.streak += 1
			if grade == "perfect" then
				session.perfect += 1
			elseif grade == "great" then
				session.great += 1
			else
				session.good += 1
			end
		end
	end
	if session.streak > session.bestStreak then
		session.bestStreak = session.streak
	end
	push(player)
	return true
end

function MusicService.SetEnabled(value: boolean)
	enabled = value
end

function MusicService.IsEnabled(): boolean
	return enabled
end

function MusicService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded"
	end
	local data = Lives.Active(profile.Data)
	local level = levelOf(data)
	local room = MusicRoom.Room()
	local lines = {
		`enabled: {enabled}`,
		`mastery: {level}/{Mastery.Levels}`
			.. `  windows {MUSIC.PerfectMsByLevel[level]}/{MUSIC.GreatMsByLevel[level]}/{MUSIC.GoodMsByLevel[level]}ms`,
		`room: {if room ~= nil then "laid" else "not laid yet"}`,
	}
	local session = sessions[player]
	if session == nil then
		table.insert(lines, "no piece running")
	else
		local judged = session.perfect + session.great + session.good + session.missed
		table.insert(
			lines,
			`{judged}/{#session.notes} judged`
				.. `  perfect {session.perfect}  great {session.great}  good {session.good}  missed {session.missed}`
				.. `  streak {session.streak} (best {session.bestStreak})`
				.. `  score {string.format("%.1f", session.score)}`
				.. `  {math.floor(math.max(session.endsAt - os.clock(), 0))}s left  stand={session.atStand}`
		)
	end
	return table.concat(lines, "\n")
end

function MusicService:Start()
	Players.PlayerRemoving:Connect(forget)

	RequestMusicHitRemote.OnServerEvent:Connect(function(player: Player, index: unknown, offsetMs: unknown)
		local ok, err = pcall(onHitRequested, player, index, offsetMs)
		if not ok then
			warn(`[AGES] music hit failed for {player.Name}: {err}`)
		end
	end)

	task.spawn(function()
		while true do
			local elapsed = task.wait(MUSIC.TickSeconds)
			ensureRoom()
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
