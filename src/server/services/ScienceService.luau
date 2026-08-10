--!strict
-- Science: the first school subject that is a thing you do rather than a thing you are
-- asked.
--
-- The loop:
--
--   You walk to the board and read the next few steps of a procedure -- go to the
--   balance, then the beaker, then the notebook. You walk to a bench and pick it up.
--   Then you cross the room clicking those stations in that order, each click stacking
--   a step. Nothing is scored until you walk back and commit, so the whole stack can be
--   taken apart and rebuilt until then. A second bench opens partway through with a
--   second procedure on it, and the two of them compete for the same stations and the
--   same reagents.
--
-- What makes it a mechanic rather than a fetch quest, in the order it matters:
--
--   The board goes blank when you walk away from it. That is the single most important
--   line in this file. The steps live in the player's head between the board and the
--   station, and how many they can hold is what a mastery level *is* -- see BenchState
--   .revealed. A version of this that kept the list on screen would be a checklist with
--   a walk attached, and the whole progression would evaporate.
--
--   Committing is the only irreversible act. Everything before it is a draft, which is
--   what makes an eight-step procedure something you can attempt at all rather than
--   something you have to get right blind.
--
--   Failure is a share, never a flag. A stack is scored on how much of the procedure it
--   contains in the right order, so a step in the wrong place costs that step -- not the
--   run. Getting one thing wrong out of eight should feel like getting seven right.
--
--   You run out of reagents about once a procedure and the cupboard is on the far side
--   of the room from the board. The two errands are deliberately opposite, so they
--   cannot be batched into one trip.
--
-- What this file is deliberately not:
--
--   It is not a second school. The door, the yearly cap, the smarts payout and the
--   verdict shares are all School's, read from Config.School, and a lesson that happens
--   to be Science still spends one of the three lessons in the year. Two sets of numbers
--   describing how good an afternoon of school was is exactly the drift this codebase
--   keeps getting bitten by.
--
--   It does not build the room. Lab.luau does, for the reason WorkSpots is not inside
--   WorkService: where a thing can stand and what happens when you reach it are separate
--   questions, and re-laying the lab must never be able to touch the scoring.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Stations = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Stations"))

local DataService = require(script.Parent.DataService)
local StatService = require(script.Parent.StatService)
local Ground = require(script.Parent.Parent.world.Ground)
local Lab = require(script.Parent.Parent.world.Lab)
local Procedures = require(script.Parent.Parent.content.Procedures)

type LifeData = Types.LifeData
type LabState = Types.LabState
type BenchState = Types.BenchState
type Procedure = Types.Procedure
type ProcedureStep = Types.ProcedureStep

local ScienceService = {}

local LabUpdatedRemote = Remotes.Get("LabUpdated")
local RequestLabStepRemote = Remotes.Get("RequestLabStep")
local RequestLabUndoRemote = Remotes.Get("RequestLabUndo")
local RequestLabCommitRemote = Remotes.Get("RequestLabCommit")

local SCHOOL = Config.School
local SCIENCE = SCHOOL.Science

-- The subject id this service answers to. A constant rather than a parameter because
-- there is exactly one procedure subject; the day there is a second, this becomes an
-- argument and nothing else here changes.
local SUBJECT_ID = "science"

-- One bench, mid-draft.
type Bench = {
	index: number,
	procedure: Procedure,
	-- Station ids in click order. The draft.
	taken: { string },
	secondsLeft: number,
	committed: boolean,
	score: number?,
	verdict: string?,
}

-- One player's session in the lab. Only ever one -- you cannot be in two labs.
type Session = {
	-- Where the room was when the session started. Walking beyond RoomRadiusStuds of it
	-- ends the session, the same way walking out of a classroom ends a lesson.
	center: Vector3,
	benches: { Bench },
	-- Which bench has been picked up, or nil before the player has been to one. Steps
	-- land here and nowhere else.
	active: number?,
	charges: number,
	level: number,
	passes: number,
	-- Seconds of standing at the cupboard banked toward a refill. Reset the moment the
	-- player steps away, on purpose: a refill you can start and come back to is two half
	-- trips, and the trip is the mechanic.
	refillHeld: number,
	-- The procedures still to be handed out, so the second bench opens with something
	-- different on it rather than a copy of the first.
	pool: { Procedure },
	-- How many benches this session will ever have. Starts at Config's figure and is
	-- lowered to the benches actually open if the pool runs out of runnable procedures.
	--
	-- A field rather than the constant, because otherwise a lab that cannot fill its
	-- second bench never satisfies the "every bench committed" test and the session hangs
	-- until the room's clock runs it out -- a silent stall, which is the worst way for
	-- this to fail. Lowering it turns that into a one-bench lab, which is a smaller lab
	-- and not a broken one.
	benchesMax: number,
	-- Seconds until the session's closing line comes down. Non-zero only after every
	-- bench is committed.
	verdictLeft: number,
	summary: string?,
	-- The last refusal, held for a beat. See LabState.notice.
	notice: string?,
	noticeLeft: number,
	-- Where the player was standing on the last tick, cached so the click handlers can
	-- answer without re-probing. Written only by the tick.
	atBoard: boolean,
	atBench: number?,
	atCupboard: boolean,
}

local sessions: { [Player]: Session } = {}

-- The last thing pushed to each player, so an unchanged state is not re-sent four times
-- a second. Same reason SchoolService keeps one.
local pushed: { [Player]: string } = {}

-- Switched off by the harness. Same shape as School's, and checked in the same two
-- places: at the door, and on every tick of a session already running.
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

-- How many steps of the board this level shows at once. Clamped rather than indexed
-- blind: a stored level from a build with a longer ladder must not index off the end of
-- a shorter one, and the honest reading of "level 9 on a five-rung ladder" is the top
-- rung.
local function revealCountFor(level: number): number
	local ladder = SCIENCE.RevealedStepsByLevel
	local rung = math.clamp(math.floor(level), 1, #ladder)
	return ladder[rung]
end

local function levelOf(data: LifeData): number
	local stored = data.subjectMastery[SUBJECT_ID]
	if stored == nil then
		return 1
	end
	return math.clamp(math.floor(stored), 1, #SCIENCE.RevealedStepsByLevel)
end

local function passesOf(data: LifeData): number
	local stored = data.subjectPasses[SUBJECT_ID]
	if stored == nil then
		return 0
	end
	return math.max(0, math.floor(stored))
end

-- How much of the procedure this stack actually contains, in order, as a 0-1 share.
--
-- The longest common subsequence rather than a position-by-position match, and the
-- difference is the whole of "soft failure". Position matching means one forgotten step
-- shifts everything after it and scores zero from there on -- a single slip reading as a
-- total failure, which is the binary outcome this activity is built to avoid. A
-- subsequence charges a missed step for exactly itself and lets the rest of a good run
-- stand, so eight steps with one wrong is seven eighths and reads like it.
--
-- An extra step the procedure never asked for costs nothing directly, which is
-- deliberate: it costs a reagent and it costs the walk, and those are real enough. The
-- clock is what stops padding the stack from being free.
local function orderedMatch(taken: { string }, procedure: Procedure): number
	local steps = procedure.steps
	local wanted = #steps
	if wanted == 0 then
		return 0
	end

	-- Two rolling rows of the LCS table rather than the whole thing. Both lists are a
	-- handful of entries, so this is a few dozen cells either way -- but it runs on every
	-- commit and there is no reason to allocate a rectangle for it.
	--
	-- Offset by one throughout: `row[j + 1]` is the score against the first j steps, so
	-- `row[1]` is the empty prefix and stays zero. Every cell of `current` is written
	-- before it is read on the next pass, so neither row ever needs clearing.
	local previous: { number } = table.create(wanted + 1, 0)
	local current: { number } = table.create(wanted + 1, 0)

	for _, station in taken do
		current[1] = 0
		for index = 1, wanted do
			if station == steps[index].station then
				current[index + 1] = previous[index] + 1
			else
				current[index + 1] = math.max(current[index], previous[index + 1])
			end
		end
		previous, current = current, previous
	end

	return previous[wanted + 1] / wanted
end

-- How much of the clock is worth. Never zero: a correct procedure handed in on the
-- buzzer is still most of a correct procedure, because the player who took the long way
-- round is usually the one still learning the room and punishing them for it is
-- punishing them for playing.
local function speedFactorFor(secondsLeft: number): number
	local share = math.clamp(secondsLeft / SCIENCE.SecondsPerProcedure, 0, 1)
	local reached = math.clamp(share / SCIENCE.SpeedFullShare, 0, 1)
	return SCIENCE.SpeedFloorFactor + (1 - SCIENCE.SpeedFloorFactor) * reached
end

-- The sentence said about a committed bench. Names the first place the stack and the
-- procedure part company, because "0.6" tells a player nothing they can do differently
-- and "you went to the sink before you had weighed it" tells them everything.
local function verdictFor(bench: Bench, score: number): string
	local steps = bench.procedure.steps
	local taken = bench.taken

	if score >= 0.999 then
		return "Perfect. Every step in order."
	end

	-- The first disagreement, which is where the run went wrong even if it recovered.
	for index = 1, math.max(#steps, #taken) do
		local want = steps[index]
		local got = taken[index]
		if want == nil then
			return `You kept going past the last step. It ended at {#steps}.`
		end
		if got == nil then
			return `You left it at step {index} of {#steps} -- the {Stations.NameOf(want.station)} was next.`
		end
		if got ~= want.station then
			return `Step {index} was the {Stations.NameOf(want.station)}, not the {Stations.NameOf(got)}.`
		end
	end

	-- Reached only when the stack matches step for step and the score is still short,
	-- which means the clock took it. Worth its own sentence rather than falling through
	-- to a generic one: "you were right but slow" is a completely different lesson.
	return "Right the whole way, but slowly."
end

-- The window of the board this bench is currently showing. Starts where the stack
-- stands, so the board answers "what now" rather than repeating what the bench already
-- records.
--
-- `from` is deliberately allowed past the end of the procedure, and the window is then
-- empty. Clamping it to the last step instead -- which is what this did first -- makes
-- the board hand back a step the player has already taken the moment their stack is
-- complete, and a board that says "now the notebook" to somebody who has just done the
-- notebook is a board actively telling them to score themselves down. Empty is the
-- truth: there is nothing left to read, go and commit it.
local function revealFor(bench: Bench, level: number): ({ ProcedureStep }, number)
	local steps = bench.procedure.steps
	local from = #bench.taken + 1
	local out: { ProcedureStep } = {}
	for index = from, math.min(from + revealCountFor(level) - 1, #steps) do
		table.insert(out, steps[index])
	end
	return out, from
end

local function benchStateFor(session: Session, bench: Bench): BenchState
	-- Empty away from the board. This is the mechanic -- see the type -- and it is done
	-- here rather than on the client so that a modified client cannot simply keep the
	-- list: the tail is never sent, so there is nothing to hold on to.
	local revealed: { ProcedureStep } = {}
	local from = #bench.taken + 1
	if session.atBoard and not bench.committed then
		revealed, from = revealFor(bench, session.level)
	end

	return {
		index = bench.index,
		name = bench.procedure.name,
		-- Copied rather than handed over, because this table crosses a remote and the
		-- session keeps writing to its own.
		taken = table.clone(bench.taken),
		revealed = revealed,
		revealedFrom = from,
		total = #bench.procedure.steps,
		secondsLeft = math.max(0, bench.secondsLeft),
		secondsTotal = SCIENCE.SecondsPerProcedure,
		active = session.active == bench.index,
		score = bench.score,
		verdict = bench.verdict,
		committed = bench.committed,
	}
end

local function stateFor(player: Player): LabState?
	local session = sessions[player]
	if session == nil then
		return nil
	end

	local benches: { BenchState } = {}
	for _, bench in session.benches do
		table.insert(benches, benchStateFor(session, bench))
	end

	return {
		benches = benches,
		charges = session.charges,
		chargesMax = SCIENCE.SupplyCharges,
		level = session.level,
		levelMax = #SCIENCE.RevealedStepsByLevel,
		passes = session.passes,
		passesPerLevel = SCIENCE.PassesPerLevel,
		atBoard = session.atBoard,
		atBench = session.atBench,
		atCupboard = session.atCupboard,
		refillProgress = math.clamp(session.refillHeld / SCIENCE.CupboardRefillSeconds, 0, 1),
		summary = session.summary,
		notice = session.notice,
	}
end

local function push(player: Player)
	local state = stateFor(player)
	-- A digest rather than a deep compare, and it has to name every field that is drawn.
	-- The stacks are folded in by length and last entry: a stack only ever changes at its
	-- end, so those two move whenever it does.
	local digest: string
	if state == nil then
		digest = "none"
	else
		local parts: { string } = {}
		for _, bench in state.benches do
			table.insert(
				parts,
				`{bench.index}:{#bench.taken}:{bench.taken[#bench.taken] or "-"}:{#bench.revealed}:`
					.. `{bench.revealedFrom}:{math.floor(bench.secondsLeft * 4)}:{tostring(bench.active)}:`
					.. `{tostring(bench.committed)}:{tostring(bench.verdict)}`
			)
		end
		digest = `{table.concat(parts, "|")}#{state.charges}/{state.level}/{state.passes}/`
			.. `{tostring(state.atBoard)}/{tostring(state.atBench)}/{tostring(state.atCupboard)}/`
			.. `{math.floor(state.refillProgress * 20)}/{tostring(state.summary)}/{tostring(state.notice)}`
	end

	if pushed[player] == digest then
		return
	end
	pushed[player] = digest
	LabUpdatedRemote:FireClient(player, state)
end

-- A refusal, held for a beat so it can be read. Replaces whatever was showing, because
-- the newest thing the lab has to say is always the one worth reading.
local function refuse(player: Player, session: Session, text: string)
	session.notice = text
	session.noticeLeft = SCIENCE.VerdictSeconds
	push(player)
end

-- Hands a bench a procedure off the session's pool, without repeating one already
-- running. Nil when the pool is empty, which means the second bench simply does not
-- open -- a lab with one procedure in it is still a lab, and inventing a duplicate
-- would make the second bench a copy of the first, which is the undifferentiated-
-- outcome trap wearing a lab coat.
local function drawProcedure(session: Session): Procedure?
	while #session.pool > 0 do
		local index = math.random(#session.pool)
		local procedure = table.remove(session.pool, index)
		if procedure == nil then
			continue
		end
		local ok = Lab.CanRun(procedure)
		if ok then
			return procedure
		end
		-- A procedure whose station the floor refused is skipped rather than handed out
		-- and failed. Not silent: Lab.Missing names the stations, and the harness prints
		-- them -- but a player must never be given a run they physically cannot finish.
	end
	return nil
end

-- Scores a bench and closes it. The one irreversible act in the whole verb.
local function commitBench(session: Session, bench: Bench, spoiled: boolean)
	if bench.committed then
		return
	end

	-- Decided before anything is written, which is the idempotency rule this codebase
	-- runs on: work out the outcome, then record it, rather than recording as you go and
	-- unpicking if something goes wrong halfway.
	local matched = orderedMatch(bench.taken, bench.procedure)
	local score = matched * speedFactorFor(if spoiled then 0 else bench.secondsLeft)

	bench.committed = true
	bench.score = score
	bench.secondsLeft = 0
	bench.verdict = if spoiled and #bench.taken == 0
		then "You never started this one."
		elseif spoiled then `Time. {verdictFor(bench, matched)}`
		else verdictFor(bench, matched)

	-- A pass banks toward the next mastery level. Measured on the ordered match rather
	-- than the speed-adjusted score, because mastery is about knowing the procedure and
	-- charging for the walk twice would make the ladder a test of running.
	if matched >= SCHOOL.GoodShare then
		session.passes += 1
		if session.passes >= SCIENCE.PassesPerLevel then
			local ceiling = #SCIENCE.RevealedStepsByLevel
			if session.level < ceiling then
				session.level += 1
				session.passes = 0
			else
				-- Held at the ceiling rather than reset, so a topped-out player does not
				-- see their progress bar cycle forever against a level that will never
				-- arrive. See the note on the report card in part 2.
				session.passes = SCIENCE.PassesPerLevel
			end
		end
	end

	if session.active == bench.index then
		session.active = nil
	end
end

-- Ends the session and pays for it. `reason` changes the sentence but never the
-- arithmetic: a lab walked out of halfway through is graded on both benches, because
-- leaving early is a way of getting them wrong -- the same rule a lesson runs on.
local function finish(player: Player, data: LifeData, session: Session, reason: string)
	for _, bench in session.benches do
		if not bench.committed then
			commitBench(session, bench, true)
		end
	end

	local total = 0
	for _, bench in session.benches do
		total += bench.score or 0
	end
	local share = if #session.benches > 0 then total / #session.benches else 0

	local gained: number
	if share >= SCHOOL.GoodShare then
		gained = SCHOOL.SmartsPerGoodLesson
	elseif share >= SCHOOL.OkShare then
		gained = SCHOOL.SmartsPerOkLesson
	else
		gained = SCHOOL.SmartsPerPoorLesson
	end

	if gained ~= 0 then
		StatService.AddStat(player, "smarts", gained)
	end

	-- Written back once, at the end, rather than on every level-up. The session holds the
	-- working copy and the profile takes it whole, which means a server that dies
	-- mid-procedure costs the player the run and nothing else -- there is no half-applied
	-- mastery to reconcile.
	data.subjectMastery[SUBJECT_ID] = session.level
	data.subjectPasses[SUBJECT_ID] = session.passes

	-- Counted however it ended, including walked out of, for the reason a lesson is:
	-- otherwise a player could start, leave, and start again until they drew a procedure
	-- they liked.
	data.lessonsThisYear += 1

	local percent = math.floor(share * 100 + 0.5)
	local reward = if gained > 0 then `. +{gained} smarts.` else "."
	local opening = if reason == "left" then "You walked out of the lab." else "Lab over."
	session.summary = `{opening} {percent}% of the procedures right{reward}`
	session.verdictLeft = SCHOOL.VerdictSeconds
	session.notice = nil
	session.noticeLeft = 0
	push(player)
end

-- Why this player cannot run a procedure right now, or nil if they can. Only the things
-- Science itself refuses -- the age, the yearly cap and the door are School's, checked
-- before this is ever called.
local function refusalFor(): string?
	if not enabled then
		return "The lab is closed."
	end
	local room = Lab.Room()
	if room == nil then
		return "The lab has not been built."
	end
	local missing = Lab.Missing()
	if #missing > 0 then
		-- Named rather than a shrug. A station the floor refused is a build problem, and a
		-- player who is told which one can at least report it.
		return `The lab is missing its {table.concat(missing, ", ")}.`
	end
	return nil
end

-- Starts a lab session. Returns false with a reason worth saying out loud.
--
-- Deliberately takes no position. A lesson can be sat wherever the player is standing --
-- the classroom is drawn around them -- but a lab cannot, because the benches and the
-- stations are real furniture in one place and a session centred anywhere else would
-- start with every station already outside the room. So the lab is always the lab, and a
-- harness that skips the walk to school still runs it in the room that exists.
function ScienceService.Begin(player: Player, data: LifeData): (boolean, string?)
	if sessions[player] ~= nil then
		return false, "You are already in the lab."
	end
	local refusal = refusalFor()
	if refusal ~= nil then
		return false, refusal
	end
	-- Non-nil by refusalFor, which returns a reason when the room is missing. Re-read
	-- rather than carried out of it so the type is not an optional the rest of this
	-- function has to keep unwrapping.
	local room = Lab.Room()
	if room == nil then
		return false, "The lab has not been built."
	end

	local pool = Procedures.ForAge(ageYearsOf(data))
	if #pool == 0 then
		-- Impossible if the content file loaded, which checks every procedure lands inside
		-- the school years. Reachable only by emptying the list without updating the check,
		-- and the honest thing is to say so rather than open a lab with nothing in it.
		return false, "There is nothing running in the lab today."
	end

	local session: Session = {
		center = room.center,
		benches = {},
		active = nil,
		charges = SCIENCE.SupplyCharges,
		level = levelOf(data),
		passes = passesOf(data),
		refillHeld = 0,
		pool = pool,
		benchesMax = SCIENCE.Benches,
		verdictLeft = 0,
		summary = nil,
		notice = nil,
		noticeLeft = 0,
		atBoard = false,
		atBench = nil,
		atCupboard = false,
	}

	local first = drawProcedure(session)
	if first == nil then
		return false, "Nothing in the lab can be run with the stations that are standing."
	end
	table.insert(session.benches, {
		index = 1,
		procedure = first,
		taken = {},
		secondsLeft = SCIENCE.SecondsPerProcedure,
		committed = false,
		score = nil,
		verdict = nil,
	})

	sessions[player] = session
	push(player)
	return true, nil
end

-- A station clicked. Checked against the bench that is actually in hand rather than
-- against whatever the client believes: the reagent pool and the clock are real, and a
-- click that arrives after the bench committed has to lose to the commit.
local function onStepRequested(player: Player, stationId: unknown)
	if type(stationId) ~= "string" then
		return
	end
	local session = sessions[player]
	if session == nil then
		return
	end
	if session.summary ~= nil then
		return
	end

	local room = Lab.Room()
	if room == nil or room.stations[stationId] == nil then
		-- A station id the lab never built. Silently dropped rather than refused out
		-- loud: the only way to produce one is a modified client, and a real player has
		-- no sentence this could usefully say to them.
		return
	end

	local index = session.active
	if index == nil then
		refuse(player, session, "Pick up a bench first -- walk to one.")
		return
	end
	local bench = session.benches[index]
	if bench == nil or bench.committed then
		session.active = nil
		refuse(player, session, "That bench is finished. Walk to the other one.")
		return
	end

	if #bench.taken >= SCIENCE.MaxSteps then
		refuse(player, session, "There is no room left on that bench. Commit it or take a step back.")
		return
	end

	-- Checked against where the player actually is, not where the prompt was when it
	-- fired. A prompt is a click on a thing across the room the instant you walk out of
	-- range, and the walk is the entire cost of a step.
	local position = characterPosition(player)
	if position == nil then
		return
	end
	local at = room.stations[stationId]
	if Ground.FlatDistance(position, at) > SCIENCE.StationRadiusStuds then
		return
	end

	if session.charges < SCIENCE.ChargesPerStep then
		refuse(player, session, "Out of reagents. The cupboard is across the room.")
		return
	end

	session.charges -= SCIENCE.ChargesPerStep
	table.insert(bench.taken, stationId)
	session.notice = nil
	session.noticeLeft = 0
	push(player)
end

-- The last step off a bench. Free, uncapped and instant, which is the half of
-- commit-and-undo that makes the other half mean something: a draft you are charged to
-- edit is not a draft.
--
-- The reagent is deliberately *not* refunded. Undo costs nothing in time or in score
-- and it should not -- but a free undo that also refunded the pool would make an
-- exhausted cupboard trip reversible, and the traversal is the point.
local function onUndoRequested(player: Player, benchIndex: unknown)
	if type(benchIndex) ~= "number" then
		return
	end
	local session = sessions[player]
	if session == nil or session.summary ~= nil then
		return
	end
	local bench = session.benches[benchIndex]
	if bench == nil or bench.committed then
		return
	end
	if #bench.taken == 0 then
		return
	end
	-- Only the bench in hand, so undo cannot be used to reach across the room and edit
	-- the other procedure without walking to it.
	if session.active ~= benchIndex then
		refuse(player, session, "That is not the bench you are holding.")
		return
	end

	table.remove(bench.taken)
	session.notice = nil
	session.noticeLeft = 0
	push(player)
end

local function onCommitRequested(player: Player, benchIndex: unknown)
	if type(benchIndex) ~= "number" then
		return
	end
	local session = sessions[player]
	if session == nil or session.summary ~= nil then
		return
	end
	local bench = session.benches[benchIndex]
	if bench == nil or bench.committed then
		return
	end

	-- Committing happens at the bench, not from across the room. Enforced rather than
	-- assumed, because the client only draws the button in range and a client is not
	-- something to take the word of.
	if session.atBench ~= benchIndex then
		refuse(player, session, "Walk to the bench to commit it.")
		return
	end
	if #bench.taken == 0 then
		refuse(player, session, "There is nothing on that bench yet.")
		return
	end

	commitBench(session, bench, false)
	push(player)
end

-- Reads where the player is standing and writes it onto the session. Everything the
-- click handlers allow or refuse is decided from these three, so they are worked out
-- once a tick in one place rather than re-probed per click.
local function readPosition(session: Session, position: Vector3)
	local room = Lab.Room()
	if room == nil then
		session.atBoard = false
		session.atBench = nil
		session.atCupboard = false
		return
	end

	session.atBoard = Ground.FlatDistance(position, room.board) <= SCIENCE.BoardRadiusStuds
	session.atCupboard = Ground.FlatDistance(position, room.cupboard) <= SCIENCE.CupboardRadiusStuds

	session.atBench = nil
	for index, at in room.benches do
		if Ground.FlatDistance(position, at) <= SCIENCE.BenchRadiusStuds then
			session.atBench = index
			break
		end
	end

	-- Standing at a bench picks it up. There is no separate "take" click, because
	-- arriving somewhere and then pressing a button to confirm you arrived is the kind of
	-- ceremony that makes a room feel like a form. A committed bench is not picked up --
	-- walking past a finished one must not put down the one you are carrying.
	local at = session.atBench
	if at ~= nil then
		local bench = session.benches[at]
		if bench ~= nil and not bench.committed then
			session.active = at
		end
	end
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

	-- The closing line, held for a beat and then the session is gone. Checked first so
	-- nothing below runs against a lab that has already been scored.
	if session.summary ~= nil then
		session.verdictLeft -= elapsed
		if session.verdictLeft <= 0 then
			sessions[player] = nil
			pushed[player] = nil
			LabUpdatedRemote:FireClient(player, nil)
			return
		end
		push(player)
		return
	end

	local position = characterPosition(player)

	if not data.alive or not enabled then
		finish(player, data, session, "left")
		return
	end
	if position == nil or Ground.FlatDistance(position, session.center) > SCIENCE.RoomRadiusStuds then
		finish(player, data, session, "left")
		return
	end

	readPosition(session, position)

	if session.noticeLeft > 0 then
		session.noticeLeft -= elapsed
		if session.noticeLeft <= 0 then
			session.noticeLeft = 0
			session.notice = nil
		end
	end

	-- The cupboard. Held rather than instant so that a refill is a place you stand for a
	-- moment, which is what makes running dry during a two-bench stretch cost something
	-- beyond the walk.
	if session.atCupboard and session.charges < SCIENCE.SupplyCharges then
		session.refillHeld += elapsed
		if session.refillHeld >= SCIENCE.CupboardRefillSeconds then
			session.refillHeld = 0
			session.charges = SCIENCE.SupplyCharges
		end
	else
		session.refillHeld = 0
	end

	-- Clocks. Only benches that are open and uncommitted run down, so the second bench
	-- is not quietly spending its time before the player has ever seen it.
	local running = 0
	for _, bench in session.benches do
		if bench.committed then
			continue
		end
		running += 1
		bench.secondsLeft -= elapsed
		if bench.secondsLeft <= 0 then
			-- Spoiled: scored where it stands, with no speed credit. Not a failure state
			-- -- a stack that was five steps of six right is still five steps right.
			commitBench(session, bench, true)
			running -= 1
		end
	end

	-- The second bench opens part way through the first, so the opening stretch teaches
	-- the verb before it tests it. Opened once and never re-opened: a bench that closed
	-- and came back would give a player a second attempt at a procedure they had already
	-- been scored on.
	local first = session.benches[1]
	if first ~= nil and #session.benches < session.benchesMax then
		local elapsedShare = 1 - math.max(0, first.secondsLeft) / SCIENCE.SecondsPerProcedure
		if elapsedShare >= SCIENCE.SecondBenchAtShare then
			local drawn = drawProcedure(session)
			if drawn ~= nil then
				table.insert(session.benches, {
					index = #session.benches + 1,
					procedure = drawn,
					taken = {},
					secondsLeft = SCIENCE.SecondsPerProcedure,
					committed = false,
					score = nil,
					verdict = nil,
				})
				running += 1
			else
				-- Nothing left in the pool that can be run. The lab carries on as a
				-- one-bench lab rather than waiting forever for a bench that will never
				-- open -- see the note on `benchesMax`. Not retried, because the pool only
				-- ever shrinks.
				session.benchesMax = #session.benches
			end
		end
	end

	-- Every bench committed, and no more to open. The session is over on its own terms
	-- rather than on the clock, which is the whole reward for working quickly.
	if running == 0 and #session.benches >= session.benchesMax then
		finish(player, data, session, "over")
		return
	end

	push(player)
end

-- Ends whatever is running and forgets this player entirely, without grading. The one
-- place a session ends ungraded, because in every case that calls it there is nobody
-- left to grade -- a player who left, or a life being started over.
local function forget(player: Player)
	sessions[player] = nil
	pushed[player] = nil
end

-- Whether this player is mid-procedure. Read by SchoolService, which has to know that a
-- birthday landing in the middle of a lab is a year the player turned up for.
function ScienceService.IsRunning(player: Player): boolean
	return sessions[player] ~= nil
end

-- A new life. Nobody inherits an education, and the mastery ladder is per life for
-- exactly the reason bonds and money are.
function ScienceService.ResetForNewLife(player: Player)
	forget(player)
	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		local data = Lives.Active(profile.Data)
		data.subjectMastery[SUBJECT_ID] = nil
		data.subjectPasses[SUBJECT_ID] = nil
	end
	LabUpdatedRemote:FireClient(player, nil)
end

-- Studio harness: opens the lab wherever the player is standing, skipping the walk to
-- the school but nothing else. The room itself is still the built one, so the stations
-- are wherever they actually are -- a harness that also moved the furniture would be
-- testing a lab that does not exist.
function ScienceService.ForceStart(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	return ScienceService.Begin(player, Lives.Active(profile.Data))
end

-- Ends a session and grades it, exactly as running out of room would.
--
-- Refuses a session that has already been graded rather than grading it twice. Only
-- reachable from the harness -- `/lab end` twice inside the verdict beat, which is three
-- seconds long and easy to hit -- but grading is the one act in this verb that pays
-- smarts and spends a lesson off the year's allowance, and a command that can be held
-- down for free smarts is not a harness, it is a cheat.
function ScienceService.ForceEnd(player: Player): boolean
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
-- The single most useful command in this system, because the thing mastery buys is how
-- much of the board you can see -- and the only other way to reach level five is to run
-- eight good procedures. Clamped rather than refused, so asking for level nine gets the
-- top of the ladder and a player can see what the ceiling looks like.
function ScienceService.SetLevel(player: Player, level: number): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	local clamped = math.clamp(math.floor(level), 1, #SCIENCE.RevealedStepsByLevel)
	local data = Lives.Active(profile.Data)
	data.subjectMastery[SUBJECT_ID] = clamped
	data.subjectPasses[SUBJECT_ID] = 0

	-- Applied to a session in progress too, so the command can be run while standing at
	-- the board and the effect read off it immediately. That is the whole point of being
	-- able to set it.
	local session = sessions[player]
	if session ~= nil then
		session.level = clamped
		session.passes = 0
		push(player)
	end
	return true
end

-- Studio harness: refills the reagent pool without the walk. The cupboard trip is the
-- thing most likely to be in the way of testing something else.
function ScienceService.Refill(player: Player): boolean
	local session = sessions[player]
	if session == nil then
		return false
	end
	session.charges = SCIENCE.SupplyCharges
	session.refillHeld = 0
	push(player)
	return true
end

function ScienceService.SetEnabled(value: boolean)
	enabled = value
end

function ScienceService.IsEnabled(): boolean
	return enabled
end

-- What the harness prints: whether the room exists, then who this player is to it, then
-- what is actually running -- the same order SchoolService.Describe uses, because
-- somebody debugging one is usually about to debug the other.
function ScienceService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "science: no profile loaded"
	end
	local data = Lives.Active(profile.Data)

	local room = Lab.Room()
	local where = if room == nil
		then "lab not built"
		else `lab at {math.floor(room.center.X)}, {math.floor(room.center.Z)}`
	local missing = Lab.Missing()
	if #missing > 0 then
		where ..= ` (missing: {table.concat(missing, ", ")})`
	end

	local level = levelOf(data)
	local mastery = `level {level}/{#SCIENCE.RevealedStepsByLevel}, {revealCountFor(level)} steps shown,`
		.. ` {passesOf(data)}/{SCIENCE.PassesPerLevel} passes`

	local running = "no session"
	local session = sessions[player]
	if session ~= nil then
		local parts: { string } = {}
		for _, bench in session.benches do
			local state = if bench.committed
				then `committed {math.floor((bench.score or 0) * 100)}%`
				else `{#bench.taken}/{#bench.procedure.steps} steps, {string.format("%.1f", bench.secondsLeft)}s`
			local hand = if session.active == bench.index then " [in hand]" else ""
			table.insert(parts, `bench {bench.index} "{bench.procedure.id}" {state}{hand}`)
		end
		local standing = if session.atBoard
			then "at the board"
			elseif session.atCupboard then "at the cupboard"
			elseif session.atBench ~= nil then `at bench {session.atBench}`
			else "crossing the room"
		running = `{table.concat(parts, "; ")} | {session.charges}/{SCIENCE.SupplyCharges} charges | {standing}`
	end

	return string.format(
		"science: %s | %s | age %d | %s | %d procedures written for this age | %s",
		if enabled then "enabled" else "DISABLED",
		where,
		ageYearsOf(data),
		mastery,
		#Procedures.ForAge(ageYearsOf(data)),
		running
	)
end

function ScienceService:Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		forget(player)
	end)

	RequestLabStepRemote.OnServerEvent:Connect(function(player: Player, stationId: unknown)
		local ok, err = pcall(onStepRequested, player, stationId)
		if not ok then
			warn(`[AGES] lab step failed for {player.Name}: {err}`)
		end
	end)

	RequestLabUndoRemote.OnServerEvent:Connect(function(player: Player, benchIndex: unknown)
		local ok, err = pcall(onUndoRequested, player, benchIndex)
		if not ok then
			warn(`[AGES] lab undo failed for {player.Name}: {err}`)
		end
	end)

	RequestLabCommitRemote.OnServerEvent:Connect(function(player: Player, benchIndex: unknown)
		local ok, err = pcall(onCommitRequested, player, benchIndex)
		if not ok then
			warn(`[AGES] lab commit failed for {player.Name}: {err}`)
		end
	end)

	task.spawn(function()
		while true do
			local elapsed = task.wait(SCIENCE.TickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player, elapsed)
				if not ok then
					warn(`[AGES] science tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

return ScienceService
