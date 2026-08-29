--!strict
-- PE: the graded sports drill, and the join between school and sports.
--
-- Every other subject on the timetable pays smarts into academics. This one pays **health
-- into athletics**, and that is the whole reason it is a subject rather than an activity.
-- `docs/school_and_sports.md`: *"PE -- a graded sports drill. Do not build a separate PE
-- minigame; this is the join between the two systems and it is what makes school carry the
-- childhood years."*
--
-- **The verb is the golf three-click meter**, ranked first of twelve input primitives in that
-- document: *"Zero RNG, every input owns one variable. The most reusable meter in all of
-- gaming, and the overswing zone is free risk/reward."*
--
--   click 1   starts the power marker sweeping
--   click 2   locks power. Past the overswing line you get more power *and* a faster
--             accuracy sweep -- you buy the risk, you do not roll for it
--   click 3   locks accuracy against a centre window
--
-- Deliberately a different problem from the gym's single timing window, which is the rule
-- the gym's own four machines follow: what separates two minigames is the shape of the
-- question, not its difficulty. The gym asks whether you can hit a moving target. This asks
-- how much harder you are willing to make that for yourself.
--
-- **Two rules taken from the spec on purpose, both named there:**
--
-- 1. *"Missing it falls back to your ratings rather than failing outright. The kindest
--    failure design in sports games. Steal this rule specifically."* A missed accuracy click
--    scores a floor that scales with health, so one bad click is never a zero.
-- 2. *"Difficulty is a rising threshold on the same minigame."* Level 5 is not a new drill --
--    it is this drill wanting more of it. The pass mark rises; the meter does not change.
--
-- The click carries a value rather than a moment, for the reason MusicService's hit carries
-- an offset: the marker is drawn on the client, and a server that recomputed position from
-- arrival time would grade a bar the player never saw and punish ping instead of timing.
-- Unlike music, though, the claim is *bounded* -- the server keeps its own marker and refuses
-- a value that could not have come from the bar in front of the player. See onClickRequested.

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
local School = require(script.Parent.Parent.world.School)

type LifeData = Types.LifeData
type PEState = Types.PEState

local PEService = {}

local PEUpdatedRemote = Remotes.Get("PEUpdated")
local RequestPEClickRemote = Remotes.Get("RequestPEClick")

local PE = Config.School.PE
local SUBJECT_ID = "pe"
local PLACE_ID = "school"

type Drill = {
	id: string,
	label: string,
	line: string,
	powerScale: number,
	accuracyScale: number,
	windowScale: number,
}

type Session = {
	drill: Drill,
	attempt: number,
	phase: string,
	sweepStartedAt: number,
	sweepSeconds: number,
	power: number,
	overswung: boolean,
	scored: number,
	bestAttempt: number,
	goodFraction: number,
	perfectFraction: number,
	passShare: number,
	endsAt: number,
	levelAtStart: number,
	atField: boolean,
	line: string,
	lastLine: string,
}

local sessions: { [Player]: Session } = {}
local notices: { [Player]: { text: string, until_: number } } = {}
local pushed: { [Player]: string } = {}
local enabled = true
local roomBuilt = false

-- Which drill comes round next. Advanced per lesson rather than rolled, so a year of PE is
-- all three rather than the same one three times by chance.
local drillCursor = 0

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

local function notice(player: Player, text: string)
	notices[player] = { text = text, until_ = os.clock() + Config.UI.NoticeSeconds }
end

-- PE happens on the school track, and falls back to the gymnasium indoors.
--
-- No ground of its own is built. The school already lays a track with an infield, which is
-- where penalties and free kicks belong; the gym is the wet-weather answer behind it. A pitch
-- drawn on top of either would be two places occupying one lesson -- the same reasoning the
-- art and music rooms use when they decline to draw a classroom over a room that exists.
--
-- Falls all the way back to the school door rather than refusing, because a drill at the
-- gates is still a drill, and a PE class that could not run because one anchor was missing
-- would be the subject silently absent from the timetable.
local function ensureRoom(): Vector3?
	local place = PlaceService.Find(PLACE_ID)
	if place == nil then
		return nil
	end
	if not roomBuilt then
		roomBuilt = true
		School.Build(place.part.Position)
	end
	return School.RoomAt("track") or School.RoomAt("gym") or place.part.Position
end

-- Health as a share of its maximum, which is what widens the windows and lifts the miss
-- floor. Read from the life rather than the character: this is fitness, not current damage.
local function fitnessOf(data: LifeData): number
	local max = Config.Stats.Max
	if max <= 0 then
		return 0
	end
	return math.clamp(data.stats.health / max, 0, 1)
end

-- The marker, as a share of the bar, at a given point in a sweep.
--
-- A triangle wave rather than a saw: the marker runs to the end and comes back, so missing a
-- click costs you the return trip rather than silently restarting the bar under your hand.
-- Both the server and the client compute this, from the same start time, which is what makes
-- the bound in onClickRequested meaningful.
local function markerAt(elapsed: number, sweepSeconds: number): number
	if sweepSeconds <= 0 then
		return 0
	end
	local phase = (elapsed / sweepSeconds) % 2
	return if phase <= 1 then phase else 2 - phase
end

-- The accuracy bands for a session, as (goodFrom, goodTo, perfectFrom, perfectTo). Centred
-- on the bar, and widened by fitness.
local function bandsOf(session: Session): (number, number, number, number)
	local good = session.goodFraction
	local perfect = session.perfectFraction
	return 0.5 - good / 2, 0.5 + good / 2, 0.5 - perfect / 2, 0.5 + perfect / 2
end

local function stateFor(player: Player): PEState
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
			drill = "",
			attempt = 0,
			attempts = PE.Attempts,
			phase = "power",
			sweepStartedAt = 0,
			sweepSeconds = 0,
			overswingFrom = PE.OverswingFrom,
			perfectFrom = 0,
			perfectTo = 0,
			goodFrom = 0,
			goodTo = 0,
			power = 0,
			scored = 0,
			bestAttempt = 0,
			lastLine = "",
			passShare = 0,
			secondsLeft = 0,
			masteryLevel = 1,
			atField = false,
		}
	end

	local goodFrom, goodTo, perfectFrom, perfectTo = bandsOf(session)

	return {
		active = true,
		line = session.line,
		drill = session.drill.label,
		attempt = session.attempt,
		attempts = PE.Attempts,
		phase = session.phase,
		sweepStartedAt = session.sweepStartedAt,
		sweepSeconds = session.sweepSeconds,
		overswingFrom = PE.OverswingFrom,
		perfectFrom = perfectFrom,
		perfectTo = perfectTo,
		goodFrom = goodFrom,
		goodTo = goodTo,
		power = session.power,
		scored = session.scored,
		bestAttempt = session.bestAttempt,
		lastLine = session.lastLine,
		passShare = session.passShare,
		secondsLeft = math.max(session.endsAt - os.clock(), 0),
		masteryLevel = session.levelAtStart,
		atField = session.atField,
	}
end

local function push(player: Player)
	local state = stateFor(player)
	-- The sweep start is in the signature deliberately: it changes on every click and it is
	-- the one number the client cannot infer, so a push that dropped it would leave the
	-- marker running from the previous phase's clock.
	local signature = `{state.active}|{state.line}|{state.lastLine}|{state.phase}|{state.attempt}`
		.. `|{state.sweepStartedAt}|{state.power}|{state.scored}|{state.atField}`
		.. `|{math.floor(state.secondsLeft)}`
	if pushed[player] == signature then
		return
	end
	pushed[player] = signature
	PEUpdatedRemote:FireClient(player, state)
end

-- Opens the next attempt, or nil if the drill is done.
local function startAttempt(session: Session)
	session.attempt += 1
	session.phase = "power"
	session.power = 0
	session.overswung = false
	session.sweepSeconds = PE.PowerSweepSeconds * session.drill.powerScale
	session.sweepStartedAt = os.clock()
end

local function finish(player: Player, data: LifeData, session: Session, reason: string)
	-- Worked out before anything is written, then recorded -- the order every other subject
	-- uses, and the reason a walk-out grades what was actually done rather than zero.
	local share = math.clamp(session.scored / PE.Attempts, 0, 1)
	local band = Report.BandFor(share)
	local gained = Report.SmartsFor(band)

	sessions[player] = nil

	-- **Health, not smarts.** This is the line that makes PE the join rather than a lesson in
	-- a tracksuit, and it is the only place in the school tree that awards it.
	if gained ~= 0 then
		StatService.AddStat(player, "health", gained)
	end

	Mastery.Record(data, SUBJECT_ID, share)

	local earned = math.floor(Config.Skills.Awards.DrillCleared * share)
	if earned > 0 then
		SkillService.Award(player, "athletics", earned, "drilled")
	end

	data.lessonsThisYear += 1
	EventService.AwardAutonomy(player, 1)

	local level = levelOf(data)
	Report.RecordLesson(data, SUBJECT_ID, band, gained, if level > session.levelAtStart then level else nil)

	local percent = math.floor(share * 100 + 0.5)
	local passed = share >= session.passShare
	local opening = if reason == "drilled"
		then (if passed then "That will do." else "Not enough of them found the net.")
		elseif reason == "left" then "You walked off the pitch."
		else "Whistle."
	local reward = if gained > 0 then `. +{gained} health.` else "."
	notice(player, `{opening} {percent}%, best strike {math.floor(session.bestAttempt * 100 + 0.5)}%{reward}`)
	push(player)
end

-- One click of the meter. Everything about it is checked, because the value came from the
-- client -- see the note at the top of the file about why it has to.
local function onClickRequested(player: Player, value: unknown)
	local session = sessions[player]
	if session == nil then
		return
	end
	if typeof(value) ~= "number" or value ~= value then
		return
	end
	local claimed = value :: number
	if claimed < 0 or claimed > 1 then
		return
	end

	-- The bound on a client-sent value. The server keeps its own marker from the same start
	-- time, and a claim that could not have come from the bar in front of the player is
	-- **dropped rather than scored as a miss** -- punishing a lag spike with a failed attempt
	-- is how a fair rule becomes the one players hate.
	local mine = markerAt(os.clock() - session.sweepStartedAt, session.sweepSeconds)
	if math.abs(claimed - mine) > PE.ClickTolerance then
		return
	end

	if session.phase == "power" then
		session.power = claimed
		session.overswung = claimed >= PE.OverswingFrom
		session.phase = "accuracy"
		session.sweepSeconds = PE.AccuracySweepSeconds * session.drill.accuracyScale
		if session.overswung then
			session.sweepSeconds /= PE.OverswingSpeedup
		end
		session.sweepStartedAt = os.clock()
		session.line = if session.overswung
			then "Big swing. Now place it, and quickly."
			else "Now place it."
		push(player)
		return
	end

	-- Accuracy: the third click, which is where the attempt is scored.
	local goodFrom, goodTo, perfectFrom, perfectTo = bandsOf(session)
	local scoredThis: number
	local said: string

	if claimed >= perfectFrom and claimed <= perfectTo then
		scoredThis = session.power * PE.PerfectMultiplier
		said = "Top corner."
	elseif claimed >= goodFrom and claimed <= goodTo then
		scoredThis = session.power * PE.GoodMultiplier
		said = "On target."
	else
		-- The kind failure. Falls back to the character's own fitness rather than to nothing.
		local profile = DataService.GetProfile(player)
		local fitness = if profile ~= nil then fitnessOf(Lives.Active(profile.Data)) else 0
		local floor = PE.MissFloor + (PE.MissFloorFit - PE.MissFloor) * fitness
		scoredThis = session.power * floor
		said = if fitness >= 0.6 then "Wide, but you got something on it." else "Wide."
	end

	session.scored += scoredThis
	if scoredThis > session.bestAttempt then
		session.bestAttempt = scoredThis
	end
	session.lastLine = `{said} {math.floor(scoredThis * 100 + 0.5)}%`

	local profile = DataService.GetProfile(player)
	if session.attempt >= PE.Attempts then
		if profile ~= nil then
			finish(player, Lives.Active(profile.Data), session, "drilled")
		else
			sessions[player] = nil
			push(player)
		end
		return
	end

	startAttempt(session)
	session.line = session.drill.line
	push(player)
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
	local data = Lives.Active(profile.Data)

	-- Walking off ends the class and grades what was done, which is the rule every subject
	-- shares. The radius is generous because the field is a running track: a drill you could
	-- fail by stepping backwards is a drill nobody would stand still for.
	local field = ensureRoom()
	local here = characterPosition(player)
	if field ~= nil and here ~= nil then
		local near = (here - field).Magnitude <= PE.ReachStuds
		if near ~= session.atField then
			session.atField = near
		end
		if not near then
			finish(player, data, session, "left")
			return
		end
	end

	if os.clock() >= session.endsAt then
		finish(player, data, session, "time")
		return
	end

	push(player)
end

function PEService.Begin(player: Player, data: LifeData): (boolean, string?)
	if sessions[player] ~= nil then
		return false, "You are already out on the field."
	end
	if not enabled then
		return false, "There is no PE today."
	end
	if ensureRoom() == nil then
		return false, "The gym is closed today."
	end

	local drills = PE.Drills :: { Drill }
	if #drills == 0 then
		return false, "There is nothing set out today."
	end
	drillCursor = (drillCursor % #drills) + 1
	local drill = drills[drillCursor]

	local level = levelOf(data)
	local fitness = fitnessOf(data)
	-- Fitness widens the window; the drill scales it; mastery does not touch it. That split
	-- is the point: what you *earn* is a wider target, what the drill sets is how hard the
	-- shot is, and what mastery sets is how many of them you need. Three different levers,
	-- none of them the same number.
	local widen = 1 + PE.HealthWindowBonus * fitness

	local session: Session = {
		drill = drill,
		attempt = 0,
		phase = "power",
		sweepStartedAt = os.clock(),
		sweepSeconds = PE.PowerSweepSeconds * drill.powerScale,
		power = 0,
		overswung = false,
		scored = 0,
		bestAttempt = 0,
		goodFraction = PE.GoodFraction * drill.windowScale * widen,
		perfectFraction = PE.PerfectFraction * drill.windowScale * widen,
		passShare = math.clamp(PE.PassShare + PE.PassSharePerLevel * (level - 1), 0, 1),
		endsAt = os.clock() + PE.TimeoutSeconds,
		levelAtStart = level,
		atField = true,
		line = drill.line,
		lastLine = "",
	}
	startAttempt(session)

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

function PEService.ResetForNewLife(player: Player)
	forget(player)
	push(player)
end

function PEService.ForceStart(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded yet"
	end
	return PEService.Begin(player, Lives.Active(profile.Data))
end

function PEService.ForceEnd(player: Player): boolean
	local session = sessions[player]
	if session == nil then
		return false
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		sessions[player] = nil
		push(player)
		return true
	end
	finish(player, Lives.Active(profile.Data), session, "time")
	return true
end

-- Plays a drill out to a given grade, for testing the report path without six clean clicks.
function PEService.Autoplay(player: Player, grade: string): (boolean, string?)
	local session = sessions[player]
	if session == nil then
		return false, "no drill running"
	end
	local share = if grade == "perfect" then 1 elseif grade == "good" then 0.72 elseif grade == "poor" then 0.2 else -1
	if share < 0 then
		return false, "grade must be perfect, good or poor"
	end
	session.scored = PE.Attempts * share
	session.bestAttempt = share
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded yet"
	end
	finish(player, Lives.Active(profile.Data), session, "drilled")
	return true
end

function PEService.SetEnabled(value: boolean)
	enabled = value
end

function PEService.IsEnabled(): boolean
	return enabled
end

function PEService.Describe(player: Player): string
	local lines = {}
	table.insert(lines, `PE: {if enabled then "on" else "off"}`)

	local field = ensureRoom()
	table.insert(lines, `field: {if field ~= nil then "found" else "no school place point"}`)

	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		local data = Lives.Active(profile.Data)
		local level = levelOf(data)
		table.insert(lines, `mastery level {level}, fitness {math.floor(fitnessOf(data) * 100 + 0.5)}%`)
		table.insert(lines, `pass mark {math.floor((PE.PassShare + PE.PassSharePerLevel * (level - 1)) * 100 + 0.5)}%`)
	end

	local session = sessions[player]
	if session == nil then
		table.insert(lines, "no drill running")
	else
		local share = session.scored / PE.Attempts
		table.insert(
			lines,
			`{session.drill.label}: attempt {session.attempt}/{PE.Attempts}, `
				.. `{session.phase}, scored {math.floor(share * 100 + 0.5)}%`
		)
	end

	return table.concat(lines, "\n")
end

function PEService:Start()
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			if DataService.WaitForProfile(player) ~= nil then
				push(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		forget(player)
	end)

	RequestPEClickRemote.OnServerEvent:Connect(function(player: Player, value: unknown)
		local ok, err = pcall(onClickRequested, player, value)
		if not ok then
			warn(`[AGES] PE click failed for {player.Name}: {err}`)
		end
	end)

	task.spawn(function()
		while true do
			local elapsed = task.wait(PE.TickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player, elapsed)
				if not ok then
					warn(`[AGES] PE tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

return PEService
