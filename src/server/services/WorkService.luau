--!strict
-- Having a job, and doing it. The first money in a life that is earned rather
-- than given, and the reason the workplace was built at the far end of the
-- street: a wage costs a walk.
--
-- The shape of a shift:
--
--   1. Stand near a job's place point, old enough, with hours left in the year.
--      That clocks you on -- and the first time, it also hires you.
--   2. Wages are credited as each game hour completes. Not accrued and paid at
--      the end: an hour you worked is money you have, and there is no state
--      anywhere that owes you for work already done.
--   3. Somewhere in the middle, one thing happens. That is the whole reason this
--      is a game rather than a timer -- see content/LifeEvents/Work.luau.
--   4. Walk out of the station radius, or work the shift out, and you are done.
--
-- Crediting per completed hour is what makes every retry question here answer
-- itself. There is no pending balance to double-pay, nothing to reconcile after
-- a crash, and leaving the server mid-shift needs no special case at all: you
-- keep what you worked for because you were already paid it. The one piece of
-- persisted state is the year's hour count, and it only ever goes up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Money = require(ReplicatedStorage:WaitForChild("Money"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local MoneyService = require(script.Parent.MoneyService)
local PlaceService = require(script.Parent.PlaceService)
local Jobs = require(script.Parent.Parent.content.Jobs)
local Cast = require(script.Parent.Parent.content.Cast)
local People = require(script.Parent.Parent.content.People)
local JobTasks = require(script.Parent.Parent.content.JobTasks)
local Ground = require(script.Parent.Parent.world.Ground)
local WorkSpots = require(script.Parent.Parent.world.WorkSpots)
local MoneyPop = require(script.Parent.Parent.world.MoneyPop)
local Customers = require(script.Parent.Parent.world.Customers)

type Job = Types.Job
type JobTask = Types.JobTask
type TaskState = Types.TaskState
type LifeData = Types.LifeData
type ShiftState = Types.ShiftState
type LifeEvent = Types.LifeEvent
type EventChoice = Types.EventChoice
type JobPostState = Types.JobPostState
type Customer = Customers.Customer

local ShiftUpdatedRemote = Remotes.Get("ShiftUpdated")
local GuideUpdatedRemote = Remotes.Get("GuideUpdated")
local JobPostsUpdatedRemote = Remotes.Get("JobPostsUpdated")
local TaskUpdatedRemote = Remotes.Get("TaskUpdated")
local NoticeRemote = Remotes.Get("Notice")

local WorkService = {}

type Shift = {
	jobId: string,
	-- Where the player clocked on, resolved once at clock-in. Held as a position
	-- rather than re-read from PlaceService every tick, because the station is
	-- where you started working and should not move if a build edit moves the
	-- marker halfway through a shift.
	station: Vector3,
	-- Real seconds of work banked. Compared against RealSecondsPerGameHour to
	-- decide when another game hour is owed.
	realSeconds: number,
	-- Game hours already paid for in this shift. Only ever goes up, and only in
	-- whole steps, which is what makes each hour paid exactly once.
	hoursCredited: number,
	-- Paid so far this shift, for the HUD. A receipt, not a promise.
	earned: number,
	-- Of `earned`, how much arrived as tips. Tracked separately because tips are the
	-- one part of the shift's pay with no clock behind it -- they scale with tasks
	-- touched, which a player controls completely -- so they are the part that needs
	-- a ceiling. Wages need no such counter; the hour loop already bounds them.
	tipsPaid: number,
	-- Which game hour this shift's one moment is due at, rolled at clock-in so it
	-- is not the same minute every time.
	eventAtHour: number,
	eventFired: boolean,
	-- What the player is being asked for this minute, and how they have done so far.
	--
	-- A list rather than one, and that is the whole of what makes a shift a shift. With
	-- a single field the loop could only ever ask one thing at a time, so the only
	-- question it put to the player was how fast they could walk -- and a question with
	-- one right answer at every instant is not a decision, it is a chore with a timer
	-- on it. Two live tasks means the shop wants two things at once and the player
	-- chooses the order, which is the first point in this job where being good at it
	-- means something other than being quick.
	--
	-- Ordered by when they were issued, and never sorted: the HUD reads top-down, and a
	-- list that reorders itself under the player's eyes while they are deciding is the
	-- one thing that would make the decision harder to make rather than more
	-- interesting to make.
	--
	-- Holds missed tasks too, for MissLingerSeconds, so the row that says "Missed" has
	-- something to be drawn from. Those do not occupy a slot -- see liveTasks.
	--
	-- Held on the shift rather than in a table beside it, because a task has no life
	-- outside the shift it belongs to: clocking off, walking out and dying all end the
	-- shift, and every one of them has to end every task too. One field cannot be
	-- forgotten in one of those three paths.
	tasks: { ActiveTask },
	-- Seconds until the next task is *considered*. One clock for the whole shift rather
	-- than one per slot: what it describes is how often the shop asks for something,
	-- which is a fact about the shop and not about any particular task. Whether the ask
	-- lands depends on there being a slot free when it comes round.
	nextTaskIn: number,
	-- The shift's report card, settled at the end. Counted rather than scored as it
	-- goes, so the verdict is one calculation in one place instead of a running total
	-- that has to be right after every possible way a task can end.
	tasksIssued: number,
	tasksDone: number,
	-- Which tasks this shift has already asked for, so it works through the job's list
	-- before repeating any. Being asked to sweep the same aisle twice running is the
	-- shift equivalent of the same customer being rude to you two shifts in a row.
	tasksUsed: { [string]: true },
}

-- One task in progress. The marks are resolved up front rather than one at a time,
-- which is what makes a two-mark task honest: if the room only has room for one, the
-- task is never issued at all, instead of stranding somebody halfway through a fetch
-- with nowhere to bring it back to.
type ActiveTask = {
	id: string,
	label: string,
	-- What the near mark and the far mark say. Odd steps get the first, even steps the
	-- second, which on a two-mark task is "fetch it" and then "bring it here" and on a
	-- rush is those two over and over.
	mark: string,
	handMark: string,
	spots: { Vector3 },
	-- Which mark they are walking to now, from 1.
	at: number,
	-- A queue, rather than one person or nobody. The spot list has already been
	-- alternated into fetch/hand/fetch/hand by the time it gets here, so this changes
	-- exactly two things: reaching an even mark short of the last one serves whoever is
	-- at the front, and the HUD counts people instead of marks.
	rush: boolean,
	secondsLeft: number,
	secondsTotal: number,
	-- Ran out of time. The task is kept rather than thrown away, for the length of the
	-- gap before the next one, purely so that there is something left to say it with:
	-- a mark that vanishes off the floor and a row that vanishes off the HUD is a
	-- player who does not know whether they failed something or whether the shift
	-- simply stopped asking. Missing is a thing they did, and the shift is going to
	-- charge them for it at the end, so it has to be a thing they saw.
	expired: boolean,
	-- How long it has been sitting there saying so. Its own clock rather than the
	-- shift's refill gap, because a miss must not hold a slot it has stopped using:
	-- with two slots, a shared clock meant every miss cost the player a second task as
	-- well, which is a penalty nothing in the game ever told them about.
	expiredFor: number,
	-- Whoever is waiting on it, if anybody is. Held here rather than looked up because
	-- there is exactly one way to get rid of a person and it is to have kept hold of
	-- them: every path out of a task has to send them off, including the ones that are
	-- not about the task at all -- a shift ending, a life ending, a player leaving.
	customer: Customer?,
}

local shifts: { [Player]: Shift } = {}

-- The station a player must step away from before they can clock on again, for
-- anyone who has just finished a shift. Without this, working a shift out while
-- standing on the spot would immediately start the next one, and "walk out" would
-- not be a way to stop working.
--
-- The position rather than a flag, because there is more than one station: a
-- player who finishes downstairs and walks up to the office has stepped away from
-- the one that matters, and should be able to clock straight on up there.
local mustStepAway: { [Player]: Vector3 } = {}

-- Why the player cannot start work where they are standing, when they are standing
-- somewhere they might reasonably expect to. Nil for almost everybody almost all
-- of the time -- it is only ever set for someone actually at a station.
local blocked: { [Player]: string } = {}

-- The last shift moment this player was offered, so the next one can prefer a
-- different one. Only matters once the fresh pool is empty and moments start
-- coming round again: the same customer being rude to you two shifts running
-- reads as a bug rather than as a life. Deliberately not saved to the profile --
-- it only has to survive between two shifts, and a rejoin is a fine place for
-- the sequence to forget itself.
local lastMoment: { [Player]: string } = {}

-- The hiring posts each player was last sent, as one string, so the list is only
-- pushed when something on it changed. Same job as `guided` below and for the same
-- reason -- the tick runs four times a second and a post changes perhaps three times
-- in a life -- but it has to be a digest rather than an id, because what can change
-- is a whole list of signs and any word on any of them.
--
-- Deliberately not a copy of the list itself. Comparing two lists of tables field by
-- field is the sort of code that stops noticing a field the day somebody adds one;
-- a string built from every field is wrong loudly or not at all.
local postedSignature: { [Player]: string } = {}

-- The job each player is currently being pointed at, by id, so the guide is only
-- pushed when the answer changes. The tick runs four times a second and the answer
-- changes perhaps twice in a life; without this every player would be sent their own
-- directions two hundred and forty times a minute.
local guided: { [Player]: string } = {}

-- Debug switch for the Studio harness. Never touched in a live server.
local enabled = true

-- The window the shift's moment is rolled in, clamped to the shift itself rather
-- than trusted as authored. The two Config numbers are written independently of
-- ShiftGameHours, so shortening a shift below EventLatestGameHour would otherwise
-- roll moments due at an hour the shift never reaches -- and the symptom would be
-- shifts that silently never have anything happen in them, which is
-- indistinguishable from bad luck and would take a very long time to notice.
--
-- Held one below the shift's last hour, because a moment due on the hour the shift
-- ends is a question the player answers after they have already clocked off.
local MOMENT_LATEST_HOUR = math.max(1, math.min(Config.Work.EventLatestGameHour, Config.Work.ShiftGameHours - 1))
local MOMENT_EARLIEST_HOUR = math.max(1, math.min(Config.Work.EventEarliestGameHour, MOMENT_LATEST_HOUR))

local STANDING = Config.Work.Standing
local BANDS = STANDING.Bands

-- The band table is read top-down and the first match wins, which is only correct
-- if it descends and its last entry reaches the floor. Both are the kind of thing
-- that is obviously true when the table is written and quietly stops being true
-- when someone adds a rung in the middle -- and the symptom would be a standing
-- that silently resolves to the wrong name and the wrong raise, or to none at all.
-- Checked once at load, where it is an error nobody can ship past.
do
	if #BANDS == 0 then
		error("[AGES config] Work.Standing.Bands is empty; there is no way to describe a record")
	end
	local previous = math.huge
	for _, band in BANDS do
		if band.atLeast >= previous then
			error(
				`[AGES config] Work.Standing.Bands is not in descending order at "{band.name}"; `
					.. `the first band you meet is the one that wins, so order is the rule`
			)
		end
		previous = band.atLeast
	end
	if BANDS[#BANDS].atLeast > STANDING.Min then
		error(
			`[AGES config] Work.Standing.Bands bottoms out at {BANDS[#BANDS].atLeast}, above the floor `
				.. `of {STANDING.Min}; a record between the two would have no name`
		)
	end
	-- Firing has to be reachable and it has to be a sacking, not a policy. Above the
	-- floor and a player could never fall far enough to trigger it; at or above zero
	-- and turning up for your first shift would let you go on the spot. Min <= FireAt
	-- < 0 is the only range where "sink to rock bottom" means what it says.
	if STANDING.FireAt < STANDING.Min or STANDING.FireAt >= 0 then
		error(
			`[AGES config] Work.Standing.FireAt is {STANDING.FireAt}, outside Min ({STANDING.Min}) .. -1; `
				.. `a firing point above the floor can never be reached and one at or above zero fires on hire`
		)
	end
	-- The final warning has to land before the sack but after thin ice starts, or it
	-- is either noise (equal to FireAt, warning at the moment of firing) or dead
	-- (at or above zero, unreachable from inside the danger band). FireAt < FinalWarnAt
	-- < 0 is the only range where "one more bad shift" can be literally true.
	if STANDING.FinalWarnAt <= STANDING.FireAt or STANDING.FinalWarnAt >= 0 then
		error(
			`[AGES config] Work.Standing.FinalWarnAt is {STANDING.FinalWarnAt}, outside FireAt ({STANDING.FireAt}) .. -1; `
				.. `the last warning must land strictly between the fire line and zero`
		)
	end
end

-- The hire pad has to sit strictly inside the clock-in radius, and this is not a
-- taste check: a player is only ever considered for a station they are already
-- within ClockInRadiusStuds of, so a pad as wide as that radius is a pad they are
-- standing on the instant they are noticed. Being hired and clocking on would fuse
-- back into one silent motion the moment somebody walks past the counter -- which is
-- exactly the behavior the pad exists to undo, restored by a config edit, with no
-- error and nothing on screen to say so.
if Config.Work.Hiring.PadRadiusStuds >= Config.Work.ClockInRadiusStuds then
	error(
		`[AGES config] Work.Hiring.PadRadiusStuds ({Config.Work.Hiring.PadRadiusStuds}) must be below `
			.. `Work.ClockInRadiusStuds ({Config.Work.ClockInRadiusStuds}), or taking a job happens by `
			.. `walking near it instead of by stepping onto the mark`
	)
end

-- Task marks have to land strictly inside the radius a player is allowed to wander
-- before they count as having walked out on the shift.
--
-- Get this wrong and the game asks somebody to go and do something, and then ends
-- their shift and docks their record for going and doing it. It is the funniest bug
-- this system can have and it would be close to undiagnosable from the symptom --
-- "sometimes my shift just ends" -- so it is an error at load rather than a comment
-- hoping to be read.
--
-- The reach is counted in because a mark is reached from its edge, not its center:
-- the furthest a player can be standing at the moment a task completes is the spread
-- plus the reach.
do
	local tasks = Config.Work.Tasks
	local furthest = math.max(tasks.MinSpreadStuds, Config.Work.StationRadiusStuds * tasks.SpreadShareOfStation)
		+ tasks.ReachStuds
	if furthest >= Config.Work.StationRadiusStuds then
		error(
			`[AGES config] a task mark can land {furthest} studs from the station, at or beyond `
				.. `Work.StationRadiusStuds ({Config.Work.StationRadiusStuds}) — a player who walked to it `
				.. `would be clocked out for abandoning the shift that sent them. Lower `
				.. `Work.Tasks.SpreadShareOfStation or Work.Tasks.MinSpreadStuds.`
		)
	end
end

-- A customer has to stand outside the radius that counts as reaching their mark.
--
-- Inside it, they are standing on the spot the player is being sent to, and the
-- player walks into the person they are meant to be serving. There is no error to
-- catch afterwards -- it looks like a bug in the spot search, or like the rig failing
-- to stop -- so the only place it can be caught is here, where the two numbers are
-- one line apart.
if Config.Work.Customers.StandOffStuds <= Config.Work.Tasks.ReachStuds then
	error(
		`[AGES config] Work.Customers.StandOffStuds ({Config.Work.Customers.StandOffStuds}) must be `
			.. `above Work.Tasks.ReachStuds ({Config.Work.Tasks.ReachStuds}), or the customer is standing `
			.. `on the mark the player is being sent to and gets walked into rather than served`
	)
end

-- Who a job's reference is, by the name they are known by rather than by their id.
-- Falls back to the id, which is a poor name and a much better one than a blank space
-- in the middle of the sentence explaining why you were turned away.
local function personName(personId: string): string
	local person = People.ById[personId]
	if person == nil then
		return personId
	end
	local member = Cast.ById[person.castId]
	return if member ~= nil then member.name else personId
end

-- What the job thinks of you, as the band you fall in. Total, because the table is
-- checked above to cover everything from the floor upward and standing is clamped
-- to that range everywhere it is written.
local function bandFor(standing: number)
	for _, band in BANDS do
		if standing >= band.atLeast then
			return band
		end
	end
	return BANDS[#BANDS]
end

local function standingAt(data: LifeData, jobId: string): number
	return data.jobStanding[jobId] or 0
end

-- The name of a job as a person would say it, for a notice. Falls back to the raw
-- id only if the job table vanished under a running server, which the load-time
-- validation makes all but impossible -- but a notice reading "as a nil" is worse,
-- and string interpolation errors on nil, so the fallback is never nil.
local function jobTitleOf(jobId: string): string
	local job = Jobs.ById[jobId]
	return if job ~= nil then job.title else jobId
end

-- The two warnings between a good record and the sack, spoken as the record sinks.
--
-- Fired on the way down and only once per crossing: entering the thin-ice band is
-- the event for the first, and crossing the final line is the event for the second.
-- A long fall warns twice, no more; recovering above either line re-arms it for the
-- next time it is crossed, which is the "you pulled it back" beat the mechanic owes.
--
-- The final warning is written to be literally true: from FinalWarnAt a single worst
-- answer (a -3 performance) reaches the floor, so "one more bad shift" means what it
-- says. Only the job the player currently holds is worth warning about -- the shift
-- paths can only touch that record anyway, so the only way to arrive with a
-- different jobId is the harness setting a stranger's record at random.
local function warnStanding(player: Player, jobId: string, before: number, after: number)
	if after >= before then
		return
	end

	local title = jobTitleOf(jobId)

	local lastBand = BANDS[#BANDS]
	if bandFor(before) ~= lastBand and bandFor(after) == lastBand then
		NoticeRemote:FireClient(
			player,
			`You're on thin ice as a {title}. Your record there is on the line.`
		)
	end

	if before > STANDING.FinalWarnAt and after <= STANDING.FinalWarnAt then
		NoticeRemote:FireClient(
			player,
			`One more bad shift as a {title} and they'll let you go.`
		)
	end
end

-- Moves a record and says so. Clamped rather than allowed to run away, because a
-- player who worked one job for forty years should not be so far above a
-- prerequisite that nothing they do afterward can ever cost them it.
local function adjustStanding(player: Player, data: LifeData, jobId: string, delta: number)
	if delta == 0 then
		return
	end
	local before = standingAt(data, jobId)
	local after = math.clamp(before + delta, STANDING.Min, STANDING.Max)
	if after == before then
		return
	end
	data.jobStanding[jobId] = after
	if data.jobId == jobId then
		warnStanding(player, jobId, before, after)
	end
	print(`[AGES] {player.Name} standing at "{jobId}" {before} -> {after} ({bandFor(after).name})`)
end

-- What an hour of this job pays *this player*, which is the base rate plus
-- whatever their record has earned them. The only place a wage is worked out.
--
-- Floored, so the rate stays a whole number of dollars. That is why Jobs.luau
-- checks the base divides evenly by the working year and this does not have to:
-- the salary is the promise a baseline year keeps, and a raise is on top of it.
local function rateFor(data: LifeData, job: Job): number
	local base = Jobs.HourlyRate(job)
	return base + math.floor(base * bandFor(standingAt(data, job.id)).raise)
end

local function hoursAllowedThisYear(): number
	return Config.Work.YearGameHours
end

local function ageYearsOf(data: LifeData): number
	return data.ageMonths // Config.Time.MonthsPerYear
end

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

-- The job the player holds, or nil. Reads through the content table rather than
-- trusting the profile, so a saved job id whose entry was deleted resolves to
-- "no job" rather than to a crash.
local function heldJob(data: LifeData): Job?
	local jobId = data.jobId
	if jobId == nil then
		return nil
	end
	return Jobs.ById[jobId]
end

-- Why this player could not be *hired* here, in a sentence written to be shown to
-- them, or nil if they could.
--
-- A sentence rather than a code, because this is the only thing standing between the
-- player and a locked door, and the door does not otherwise speak: the sign in the
-- window states the job's terms and has no idea who is reading it, so this is where
-- the game gets to be personal about it.
--
-- Ordered by what is most useful to hear. Age first because it is the flattest fact,
-- the prerequisite second because it is the one the player can go and do something
-- about.
--
-- Everything here is a *qualification*: a fact about whether this player is somebody
-- this job would take on. Nothing about the calendar, and nothing that would be
-- untrue of somebody who already holds the job -- see refusalFor -- with the single
-- exception below.
--
-- That exception is being sacked. It is the one employer-side timing fact that lives
-- here rather than in refusalFor, and it belongs here because it is a refusal to
-- *hire*, not a bar on clocking a shift you already hold: a player who has been let go
-- no longer holds the job, so the only door it can shut is this one. It reads first
-- because it is the flattest fact of all -- this employer is not talking to you right
-- now -- and there is nothing to check about age or smarts for a job that will not have
-- you back until the year turns.
local function hireRefusalFor(data: LifeData, job: Job): string?
	if data.firedFrom[job.id] then
		return "They let you go here. Come back next year."
	end

	local ageYears = ageYearsOf(data)
	if ageYears < job.minAge then
		return `You have to be {job.minAge} to work here.`
	end

	local requirement = job.requires
	if requirement ~= nil then
		local prerequisite = Jobs.ById[requirement.jobId]
		if prerequisite == nil then
			-- Validated at content load, so reaching this means the table changed under
			-- a running server. Refuse rather than wave them through: a ladder with a
			-- missing rung should not silently become a job with no requirements.
			warn(`[AGES] job "{job.id}" requires "{requirement.jobId}", which is not a job`)
			return "This job is not taking anyone at the moment."
		end
		if standingAt(data, requirement.jobId) < requirement.standing then
			-- Named by the band the requirement sits in rather than by its number, so
			-- the sentence asks for something the player has seen written about
			-- themselves on the HUD instead of a figure that appears nowhere else.
			return `You need to be {bandFor(requirement.standing).name} as a {prerequisite.title} first.`
		end
	end

	-- Last of the three because it is the one nothing can be done about now. Age comes
	-- with waiting and standing comes with working, but the smarts a desk job asks for
	-- were earned or not earned in a classroom years before anybody stood here -- so it
	-- is said last, and it names the place they came from rather than only the number.
	-- An eighteen-year-old reading "you need 60" and nothing else has been given a
	-- score and no explanation of it.
	local minSmarts = job.minSmarts
	if minSmarts ~= nil then
		local asks = minSmarts
		local vouched = false
		local voucherName = ""

		-- A word from somebody who thinks well of you, read live off the bond rather than
		-- spent out of a store of favours. There is no reference to hand in: the office
		-- asks the neighbor what he makes of you on the day, so the answer is whatever
		-- twenty years of walking past his shop has made it -- and it can go back down if
		-- those years stop happening.
		local vouch = job.vouch
		if vouch ~= nil then
			local bond = People.BondIn(data.bonds, vouch.personId)
			if bond ~= nil and bond >= vouch.minBond then
				asks = minSmarts - vouch.worthSmarts
				vouched = true
				voucherName = personName(vouch.personId)
			end
		end

		if data.stats.smarts < asks then
			local held = math.floor(data.stats.smarts)
			if vouched then
				-- The refusal says the word was put in, which matters more than it looks.
				-- A bar that quietly moved is indistinguishable from a bar the player had
				-- misread, and the thing being rewarded here -- having gone and seen
				-- somebody, for years -- is worth being told about even while being
				-- turned away.
				return `Even with {voucherName} putting in a word this desk needs {asks} smarts `
					.. `and you have {held}. School was where the rest came from.`
			end
			return `This desk needs {minSmarts} smarts and you have {held}. School was where that came from.`
		end
	end

	return nil
end

-- Why this player cannot *work a shift* here right now. Everything that would stop
-- them being hired, plus the one thing that would not.
--
-- The split matters because these two questions have different answers and used to
-- share one. Having used up the year's hours does not mean the shop would not employ
-- you -- it means you are done for this year, at a job that is still yours. Asking
-- one function both things made the hiring sign, which only cares about the first,
-- unable to use it: it would have advertised a job as closed to a player who already
-- had it and had simply worked it out.
local function refusalFor(data: LifeData, job: Job): string?
	local refusal = hireRefusalFor(data, job)
	if refusal ~= nil then
		return refusal
	end

	-- Last because it is temporary and applies everywhere, rather than saying
	-- anything about this job in particular.
	if data.workGameHoursThisYear >= hoursAllowedThisYear() then
		return "You have worked all your hours for this year."
	end

	return nil
end

-- The job worth walking across town for, or nil if there is nothing to point at.
--
-- The best-paying one they would be hired for and do not already hold. Hired for
-- rather than able to work today, because the year's hours running out is not a
-- reason to stop telling somebody a career exists.
--
-- "Do not already hold" is what stops this nagging. Take the job it is pointing at
-- and the line goes out; the only thing that lights it again is qualifying for
-- something better, which is exactly the news worth interrupting somebody with. The
-- office is up a staircase that a player with no reason to climb it will never climb,
-- and the day they become welcome up there should not be a day they find out by
-- accident eleven years later.
local function guideTargetFor(data: LifeData): Job?
	if not data.alive then
		return nil
	end

	local best: Job? = nil
	for _, job in Jobs.All do
		if data.jobId == job.id then
			continue
		end
		if hireRefusalFor(data, job) == nil and (best == nil or job.yearlySalary > best.yearlySalary) then
			best = job
		end
	end
	return best
end

-- Points the player at a job, or at nothing. Only ever sends when the answer has
-- changed -- see `guided`.
local function setGuide(player: Player, job: Job?)
	local jobId = if job ~= nil then job.id else nil
	if guided[player] == jobId then
		return
	end
	guided[player] = jobId

	if job == nil then
		GuideUpdatedRemote:FireClient(player, { target = nil, label = nil })
		return
	end

	local place = PlaceService.Find(job.placeId)
	if place == nil then
		-- Already warned by PlaceService. Pointing at nothing is the honest answer:
		-- the job exists in content but nowhere in the world, and a line into the
		-- middle of a field would be worse than no line.
		GuideUpdatedRemote:FireClient(player, { target = nil, label = nil })
		return
	end

	GuideUpdatedRemote:FireClient(player, { target = place.part.Position, label = job.title })
end

-- What the sign in the window says, under the job title. The job's terms, in the
-- order somebody deciding whether to walk over would want them: what it pays, then
-- who it is open to.
--
-- Facts about the job, never about the reader, even though the sign is now personal
-- enough to say either. A shop window states its terms and lets you work out whether
-- you meet them; that is a nicer thing to read than a game telling you what you are
-- not. The verdict has its own place -- the mark on the floor below, which goes grey
-- and says why -- and keeping the two apart means the sign reads the same to a
-- twelve-year-old as to the person about to be hired.
local function signTermsFor(job: Job): { string }
	local terms = { `{Money.Format(job.yearlySalary)} a year`, `from {job.minAge}` }

	local requirement = job.requires
	if requirement ~= nil then
		local prerequisite = Jobs.ById[requirement.jobId]
		if prerequisite ~= nil then
			-- The same phrase the refusal at the door uses, deliberately word for word.
			-- A player who reads "well thought of as a Shop assistant" on the office
			-- sign and later hears it again standing at the office counter should not
			-- have to work out that they are the same requirement.
			table.insert(terms, `{bandFor(requirement.standing).name} as a {prerequisite.title}`)
		end
	end

	-- The reason this sign is worth walking past as a child. A ten-year-old cannot be
	-- hired here and cannot read a refusal, but they can read a window that says the
	-- office wants sixty smarts, and they have seven school years left to do something
	-- about it. This is the only place in the game that tells a player what lessons are
	-- for before the bill for skipping them comes due.
	local minSmarts = job.minSmarts
	if minSmarts ~= nil then
		local vouch = job.vouch
		if vouch ~= nil then
			-- Both routes on the window, because a route nobody is told about is not a
			-- route. This is where a nine-year-old finds out that the man outside the shop
			-- is worth knowing -- years before there is any way to act on it, which is
			-- exactly when a childhood decision has to be made.
			table.insert(terms, `{minSmarts} smarts, or {minSmarts - vouch.worthSmarts} with a word from {personName(vouch.personId)}`)
		else
			table.insert(terms, `{minSmarts} smarts`)
		end
	end

	return terms
end

-- Every hiring post this player should be looking at.
--
-- The one rule that matters is the omission: a job you already hold does not get a
-- post. It is not an offer any more, and leaving a NOW HIRING sign and a gold "take
-- the job" mark standing over somebody's own counter for the rest of their life is
-- the game failing to notice they did the thing it asked.
--
-- Everything else still gets one, including jobs the player would be turned away
-- from. That is deliberate and it is the signposting doing its work: a twelve-year-
-- old should be able to walk past the shop and learn that it hires at sixteen. Those
-- come back locked -- grey, still, and carrying the reason -- rather than absent,
-- because a job that is invisible until the year you qualify is a job nobody plans
-- for.
local function postsFor(data: LifeData): { JobPostState }
	local states: { JobPostState } = {}
	if not data.alive then
		-- Dead. Signs over a corpse are not signposting, and the next life's push
		-- arrives the moment the new one starts.
		return states
	end

	for _, job in Jobs.All do
		if data.jobId == job.id then
			continue
		end

		local place = PlaceService.Find(job.placeId)
		if place == nil then
			-- Warned once by PlaceService. Nothing to advertise: the job exists in
			-- content but nowhere anybody could walk to.
			continue
		end

		-- Asked with hireRefusalFor rather than refusalFor, which is the same
		-- distinction the guide draws: having worked all your hours this year is a
		-- reason you cannot start a shift today, not a reason the job is closed to
		-- you, and greying out the sign over it would say the wrong thing.
		local refusal = hireRefusalFor(data, job)
		table.insert(states, {
			jobId = job.id,
			position = place.part.Position,
			headline = "NOW HIRING",
			title = job.title,
			terms = signTermsFor(job),
			-- The refusal is reused as the label rather than reworded, so the mark on
			-- the floor and the line on the HUD when you walk up to it are the same
			-- sentence. Two phrasings of one rule reads as two rules.
			padLabel = refusal or (if data.jobId == nil then "Take the job" else "Move to this job"),
			padLocked = refusal ~= nil,
		})
	end

	return states
end

-- Sends the posts, if they have changed. See postedSignature: this is called from
-- the tick, which runs four times a second for the whole life of the server.
local function setPosts(player: Player, data: LifeData)
	local states = postsFor(data)

	local parts: { string } = {}
	for _, state in states do
		table.insert(
			parts,
			`{state.jobId}\30{state.position}\30{state.headline}\30{state.title}\30`
				.. `{table.concat(state.terms, "|")}\30{state.padLabel}\30{tostring(state.padLocked)}`
		)
	end
	local signature = table.concat(parts, "\31")

	if postedSignature[player] == signature then
		return
	end
	postedSignature[player] = signature
	JobPostsUpdatedRemote:FireClient(player, states)
end

-- The best-paying job the player could actually take right now, wherever it is.
-- Only used by the harness and by the "you could be working" line in Describe --
-- never to decide what somebody is doing, because that is decided by where they
-- are standing.
local function bestEligibleJob(data: LifeData): Job?
	local best: Job? = nil
	for _, job in Jobs.All do
		if refusalFor(data, job) == nil and (best == nil or job.yearlySalary > best.yearlySalary) then
			best = job
		end
	end
	return best
end

-- The job whose station the player is standing at, whether or not they may work
-- it. The nearest wins, which only matters if two jobs are ever built within a
-- clock-in radius of each other.
--
-- Deliberately not "the job they hold". Where you are standing is what decides
-- what you are doing, and that is what makes the staircase in the workplace mean
-- something: at eighteen, with the shop floor behind you, you walk up it and clock
-- on in the office, and that is the promotion -- no menu, no application, just a
-- job you have finally earned the right to stand in. Clocking on downstairs again
-- the next day is equally allowed, and would be a demotion you chose by walking.
--
-- Deliberately not filtered by whether they qualify, either -- that was the shape
-- of this before the ladder existed, and it made an unqualified player and an
-- empty room the same answer. They are not: one of them is owed an explanation.
-- Qualification is refusalFor's job, and it is asked separately.
--
-- Returns the station's position alongside the job, because the caller needs it
-- and finding it twice invites the two answers differing.
local function stationAtHand(position: Vector3): (Job?, Vector3?)
	local nearest: Job? = nil
	local nearestStation: Vector3? = nil
	local nearestDistance = math.huge

	for _, job in Jobs.All do
		local place = PlaceService.Find(job.placeId)
		if place == nil then
			-- Warned once inside PlaceService, which is the right place for it: this
			-- is a world that has not been built rather than a player who cannot work.
			continue
		end
		local station = place.part.Position
		local distance = Ground.FlatDistance(position, station)
		if distance <= Config.Work.ClockInRadiusStuds and distance < nearestDistance then
			nearest = job
			nearestStation = station
			nearestDistance = distance
		end
	end
	return nearest, nearestStation
end

local function stateFor(player: Player): ShiftState
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return {
			jobTitle = nil,
			onShift = false,
			gameHoursWorked = 0,
			shiftGameHours = Config.Work.ShiftGameHours,
			earned = 0,
			shiftsThisYear = 0,
			shiftsPerYear = Config.Work.ShiftsPerYear,
			standing = nil,
			blockedReason = nil,
		}
	end

	local data = Lives.Active(profile.Data)
	local job = heldJob(data)
	local shift = shifts[player]

	-- Reported in shifts rather than hours, rounded down, because "3 of 5" is a
	-- thing a player can hold in their head and "24 of 40 game hours" is not.
	local shiftsThisYear = data.workGameHoursThisYear // Config.Work.ShiftGameHours

	return {
		jobTitle = if job ~= nil then job.title else nil,
		onShift = shift ~= nil,
		-- The fractional part is deliberate: it is what makes the HUD bar move
		-- rather than jump once every thirty seconds.
		gameHoursWorked = if shift ~= nil then shift.realSeconds / Config.Time.RealSecondsPerGameHour else 0,
		shiftGameHours = Config.Work.ShiftGameHours,
		earned = if shift ~= nil then shift.earned else 0,
		shiftsThisYear = shiftsThisYear,
		shiftsPerYear = Config.Work.ShiftsPerYear,
		standing = if job ~= nil then bandFor(standingAt(data, job.id)).name else nil,
		blockedReason = blocked[player],
	}
end

local function push(player: Player)
	ShiftUpdatedRemote:FireClient(player, stateFor(player))
end

-- Records why the player cannot clock on where they are standing, and tells them
-- only when the answer changes.
--
-- The change check is the whole point. This is read on every tick of a loop that
-- runs four times a second, and a player standing in front of a door they cannot
-- open yet is exactly the case where it stays the same for minutes at a time --
-- so pushing unconditionally would be a remote firing 240 times a minute to say
-- nothing new.
local function setBlocked(player: Player, reason: string?)
	if blocked[player] == reason then
		return
	end
	blocked[player] = reason
	push(player)
end

-- Ends the shift and says why. `reason` is for the harness and the log, never for
-- the player: they know why, they just walked out.
--
-- `standingDelta` is what the ending itself does to their record, before any
-- moment is counted: finishing is worth something and leaving early costs
-- something. Passed in at every call site rather than worked out from the reason
-- string, so that what an ending is worth is a decision each site makes on purpose
-- and never something inferred from prose that was written for a log.
-- What the HUD is told about one task. The list it goes into may be empty, which
-- covers both the gap between tasks and the whole of the rest of a life -- the HUD
-- does not need to tell those apart, because in neither case is there anything to be
-- doing.
local function taskStateFor(task: ActiveTask, paused: boolean): TaskState
	return {
		id = task.id,
		label = task.label,
		spot = task.spots[task.at],
		-- The far mark on every even step. A two-mark task whose second mark still reads
		-- "Fetch the box" is the one word in the whole task pointing back the way you
		-- came.
		mark = if task.at % 2 == 0 then task.handMark else task.mark,
		spotIndex = task.at,
		spotCount = #task.spots,
		-- Counted off the queue rather than off the marks, because on a rush the marks
		-- are the same two over and over and "3 of 6" tells the player nothing they can
		-- act on. How many people are still standing there is the same information in
		-- the units they are actually thinking in.
		waiting = if task.rush and task.customer ~= nil then task.customer.waiting() else nil,
		-- Clamped, because the clock is checked once a tick and therefore always ends
		-- up a fraction of a second past zero. "-0.2s left" printed under a missed task
		-- is the game admitting it was still counting after it stopped caring.
		secondsLeft = math.max(task.secondsLeft, 0),
		secondsTotal = task.secondsTotal,
		paused = paused,
		missed = task.expired,
	}
end

-- Pushed on a change rather than on a tick, which for a countdown means "when the
-- displayed second changes". The HUD shows whole seconds, so sending the same number
-- four times over is four remotes asking for an identical row to be redrawn.
local pushedTask: { [Player]: string } = {}

-- The whole list, every push, never a diff. A dropped message is corrected by the next
-- one instead of leaving the player with a mark on the floor for a task that finished
-- ten seconds ago -- and with two of them live, a diff would need the client to hold a
-- model of which task is which, which is exactly the sort of state that ends up one
-- message behind and impossible to reproduce.
local function pushTasks(player: Player, shift: Shift?, paused: boolean)
	local states: { TaskState } = {}
	if shift ~= nil then
		for _, task in shift.tasks do
			table.insert(states, taskStateFor(task, paused))
		end
	end

	local parts: { string } = {}
	for _, state in states do
		table.insert(
			parts,
			`{state.id}\30{state.label}\30{state.spotIndex}\30{tostring(state.spot)}\30`
				.. `{math.ceil(state.secondsLeft)}\30{tostring(state.paused)}\30{tostring(state.missed)}\30`
				-- In the digest because the queue shortens without the mark or the clock
				-- doing anything a signature would notice: serve somebody at the same instant
				-- the displayed second changes and the row would otherwise keep the old count
				-- until the next tick.
				.. `{tostring(state.waiting)}`
		)
	end
	-- The count is in the digest in its own right, so that going from two tasks to none
	-- is a change even in the impossible case where the remaining parts concatenate to
	-- the same string. Cheap insurance against a HUD that keeps a row for a task the
	-- shift has forgotten.
	local signature = `{#states}\31` .. table.concat(parts, "\31")
	if pushedTask[player] == signature then
		return
	end
	pushedTask[player] = signature

	TaskUpdatedRemote:FireClient(player, states)
end

-- Letting the player go. The mirror of takeJob: the one place, outside a life ending,
-- that clears data.jobId -- here because their record sank to the floor.
--
-- Deliberately does not touch `shifts`. Firing lands at clock-off, when the shift has
-- already been torn down by the caller, so a fire that ended shifts would be ending one
-- that is already gone -- and wiring it to do so would knot this function and endShift
-- into each other's definitions. The caller owns the shift; fire owns the job.
--
-- Sets firedFrom before clearing jobId so that the moment the job is gone the door is
-- already shut: a hire refusal read in the same frame sees the cooldown, not an opening.
local function fire(player: Player, data: LifeData, jobId: string)
	data.firedFrom[jobId] = true
	data.jobId = nil

	-- Named off the job table rather than the id, and falls back to a bare "here" only
	-- if the job vanished under a running server -- which the load-time validation makes
	-- all but impossible, but a notice that reads "let go as a nil" is worse than vague.
	local job = Jobs.ById[jobId]
	local title = if job ~= nil then job.title else nil
	local text = if title ~= nil
		then `You've been let go as a {string.lower(title)}.`
		else "You've been let go."
	NoticeRemote:FireClient(player, text)

	print(`[AGES] {player.Name} was let go from "{jobId}" at age {ageYearsOf(data)}`)
	push(player)
end

local function endShift(player: Player, reason: string, standingDelta: number)
	local shift = shifts[player]
	if shift == nil then
		return
	end
	shifts[player] = nil

	-- Sent before anything else the ending does. Clocking off, walking out and dying
	-- all arrive here, and every one of them has to take every mark off the floor -- so
	-- it is done once, on the one path all three go through, rather than three times.
	pushTasks(player, nil, false)

	-- And anybody who was waiting on any of them goes with it. Every task, not the one:
	-- two live tasks can each have brought a queue, and the second one is the one a
	-- loop written for a single field would leave standing in an empty shop forever.
	--
	-- Destroyed rather than sent off politely, because this is the path a player
	-- quitting the game and a life ending both take: there is no shop left for them to
	-- walk out of, and a rig left standing at a counter nobody works at is the kind of
	-- thing that is still there an hour later.
	for _, abandoned in shift.tasks do
		if abandoned.customer ~= nil then
			abandoned.customer.destroy()
		end
	end

	print(`[AGES] {player.Name} clocked off after {shift.hoursCredited}h, {Money.Format(shift.earned)} earned ({reason})`)

	local profile = DataService.GetProfile(player)
	if profile == nil then
		push(player)
		return
	end
	local data = Lives.Active(profile.Data)

	-- A shift put in while ill is a bad shift before it has even been one, so the
	-- verdict carries an extra line. Applied only when the shift actually did some
	-- work -- clocking on and walking straight off is not a performance to judge.
	local delta = standingDelta
	if data.flags.sick ~= nil and shift.hoursCredited > 0 then
		delta += Config.Health.SickShiftStanding
		NoticeRemote:FireClient(player, "Working while you're ill showed. It didn't do your record any favors.")
	end
	adjustStanding(player, data, shift.jobId, delta)

	-- The sacking lands here and nowhere else -- at clock-off, once the shift's own worth
	-- has been counted, so a bad shift always finishes before it can cost you the job.
	-- Checked directly off the record rather than off the delta just applied, because a
	-- player re-hired at the floor and sinking no further would never re-trigger a
	-- delta-based check: reaching the line is what matters, not moving to it. Guarded on
	-- jobId still matching the shift so a shift that ended *because* they quit or changed
	-- jobs cannot fire them from a job they already walked away from.
	if data.jobId == shift.jobId and standingAt(data, shift.jobId) <= STANDING.FireAt then
		fire(player, data, shift.jobId)
		-- fire already pushed the cleared state; a second push here would redraw it.
		return
	end

	push(player)
end

-- Being hired. The one place data.jobId is ever set to a job.
--
-- Small, and deliberately so -- everything that decides *whether* this should happen
-- is asked before it is called, and what is left is the fact of it. It is the moment
-- a life gains a job, though, so it says so out loud: a career starting is worth a
-- line in the log next to births and deaths, and until Part B gives it a sound and a
-- handshake this print is the only record that the game noticed.
local function takeJob(player: Player, data: LifeData, job: Job)
	local previous = data.jobId
	data.jobId = job.id

	if previous == nil then
		print(`[AGES] {player.Name} took the job "{job.id}" at age {ageYearsOf(data)}`)
	else
		print(`[AGES] {player.Name} left "{previous}" for "{job.id}" at age {ageYearsOf(data)}`)
	end

	push(player)
end

-- Starts one. Returns false for every ordinary reason you cannot work right now,
-- so a caller must not treat false as a fault -- the common case by far is simply
-- being too young.
local function startShift(player: Player, job: Job, station: Vector3): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil or not Lives.Active(profile.Data).alive or shifts[player] ~= nil then
		return false
	end

	local data = Lives.Active(profile.Data)
	if data.workGameHoursThisYear >= hoursAllowedThisYear() then
		return false
	end

	-- You cannot clock on somewhere you do not work. This used to be the line that
	-- hired you -- walking near the counter did both at once, silently -- and pulling
	-- the two apart is the whole point of the hire pad: being given a job and turning
	-- up for a shift are different days in a life and should be different acts in the
	-- game. Taking the job happens once, on a mark you chose to step on; this happens
	-- every time you come back.
	if data.jobId ~= job.id then
		return false
	end

	shifts[player] = {
		jobId = job.id,
		station = station,
		realSeconds = 0,
		hoursCredited = 0,
		earned = 0,
		tipsPaid = 0,
		-- Rolled per shift so the moment does not land on the same minute every
		-- time, which would make it read as part of the clock rather than as
		-- something that happened.
		eventAtHour = math.random(MOMENT_EARLIEST_HOUR, MOMENT_LATEST_HOUR),
		eventFired = false,
		tasks = {},
		-- The first task waits out a gap like every other one, so clocking on is not
		-- immediately an instruction. A second or two of standing behind your own
		-- counter before the shop asks you for anything is the whole of the game's
		-- pacing on this: arriving somewhere and being shouted at is not arriving.
		nextTaskIn = Config.Work.Tasks.GapSeconds,
		tasksIssued = 0,
		tasksDone = 0,
		tasksUsed = {},
	}
	push(player)
	return true
end

-- Pays for one game hour of work. The only place a wage is ever credited, and the
-- only place the year's counter moves -- both in the same step, so an hour paid is
-- an hour spent and there is no ordering in which one happens without the other.
--
-- The rate is resolved per hour rather than once at clock-in, so a raise earned by
-- a moment halfway through a shift is paid from the next hour on. That is the
-- clearest possible demonstration that the record is real: you answer well, and
-- the very next hour pays more.
-- How the shift is going, as the share of issued tasks that were finished, or nil
-- when nothing has been asked yet.
--
-- One definition, read by both the wage and the end-of-shift verdict. They used to
-- disagree by construction -- the verdict counted tasks and the wage counted seconds
-- -- and two answers to "was this a good shift?" is one answer too many.
local function taskShareOf(shift: Shift): number?
	if shift.tasksIssued == 0 then
		return nil
	end
	return shift.tasksDone / shift.tasksIssued
end

-- What this hour is worth, as a multiple of the job's rate.
--
-- Resolved at the moment the hour lands rather than once at clock-in, for the same
-- reason the rate itself is: a shift that turns around halfway through should start
-- paying properly from the next hour, and one that falls apart should stop. The
-- player feels the wage respond inside the shift instead of being told about it in a
-- summary once the shift is already over.
local function wageShareFor(shift: Shift): number
	local tasks = Config.Work.Tasks
	local share = taskShareOf(shift)

	-- Nothing asked yet, so nothing missed. Pays in full.
	if share == nil then
		return tasks.WageShareGood
	end
	if share >= tasks.GoodShare then
		return tasks.WageShareGood
	end
	if share >= tasks.OkShare then
		return tasks.WageShareOk
	end
	-- Above zero but below Ok: they are working, badly. Still worth something.
	if share > 0 then
		return tasks.WageSharePoor
	end
	-- Tasks were issued and not one was touched. This is the standing-in-the-radius
	-- case, and it is the whole reason this function exists.
	return tasks.WageShareNone
end

local function creditHour(player: Player, data: LifeData, shift: Shift, job: Job)
	-- The hour is always spent, whatever it paid. Coasting costs the year's hours at
	-- the same rate as working, so a poor shift is not a cheap way to keep the good
	-- hours in reserve -- it is a wasted afternoon, which is what it should be.
	data.workGameHoursThisYear += 1
	shift.hoursCredited += 1

	local rate = math.floor(rateFor(data, job) * wageShareFor(shift))
	if rate <= 0 then
		return
	end

	shift.earned += rate
	MoneyService.Add(player, rate, `wages: {job.id}`)
end

-- Picks the next task and finds the floor for it, or gives up quietly.
--
-- Both halves can fail for ordinary reasons -- a job with no tasks authored, a
-- stockroom too cramped to fan out in -- and neither is a fault. The shift carries on
-- being a shift; it simply has nothing in it, which is exactly what every shift in
-- this game was before this existed. So the failure path is silent and the caller
-- tries again after the gap, rather than warning four times a second about a room.
--
-- Silent, but only after every task on the list has been tried. Giving up on the first
-- one that would not fit is how a small room turns into a shift spent standing still.
--
-- `only` names one task and asks for that one or nothing. The Studio harness alone
-- passes it: four of the ten tasks have somebody waiting on them, and testing a
-- customer by asking for random tasks until one turns up is how a five-second check
-- becomes a two-minute one.
-- Jobs already reported as having nowhere to put a task, so the warning is said once
-- per job per server rather than every GapSeconds for the length of every shift.
local warnedNoRoom: { [string]: true } = {}

-- How many tasks are still being asked for, as opposed to sitting on the HUD saying
-- they were missed. A miss is over: it holds a row and it holds no slot, because
-- charging a player a second task for having missed the first is a penalty the game
-- never told them about and could not have -- there is nothing on screen that would
-- say it.
local function liveTasks(shift: Shift): number
	local count = 0
	for _, task in shift.tasks do
		if not task.expired then
			count += 1
		end
	end
	return count
end

-- How many may be live at once, right now.
--
-- Grows once, partway through the shift, and that is the shift's whole difficulty
-- curve. Nothing gets faster and nothing gets tighter -- the clocks and the marks are
-- the ones JobTasks authored -- the room simply starts asking for two things instead
-- of one. Escalating by changing the space rather than the numbers is the difference
-- between a job that gets harder and a job that gets meaner.
local function slotsFor(shift: Shift): number
	local tasks = Config.Work.Tasks
	-- hoursCredited is hours *finished*, so the hour being worked is one past it.
	if shift.hoursCredited + 1 < tasks.SecondSlotFromHour then
		return 1
	end
	return tasks.MaxConcurrent
end

-- Whether a rush is running, which stops anything else being issued alongside it.
--
-- A rush is already several round trips with a queue of people standing at the counter
-- for the duration, so it is using the whole floor and the whole of the player's
-- attention by design. A second task painted on top of it would put a mark in among a
-- line of customers, split a HUD that is already counting people rather than marks,
-- and turn the one task in the shift with a shape of its own into noise. It gets the
-- room to itself, both ways round: nothing is issued while it runs, and it is not
-- picked while anything else is.
local function rushRunning(shift: Shift): boolean
	for _, task in shift.tasks do
		if task.rush and not task.expired then
			return true
		end
	end
	return false
end

-- Every mark currently lit, so a new task is never painted on top of one the player is
-- already walking to.
--
-- The single most load-bearing consequence of running two tasks at once. WorkSpots
-- already keeps a task's own marks apart -- that is what stops a fetch completing
-- itself -- but it has no idea another task exists, so without this two tasks
-- regularly land within a stride of each other and the player clears both by standing
-- still. Which is the AFK shift again, arrived at from a completely different
-- direction.
local function markedSpots(shift: Shift): { Vector3 }
	local spots: { Vector3 } = {}
	for _, task in shift.tasks do
		if task.expired then
			continue
		end
		for _, spot in task.spots do
			table.insert(spots, spot)
		end
	end
	return spots
end

-- How long until the shop asks for the next thing.
--
-- Longer when something is already in hand, and the two slots must fill staggered for
-- the reason Config gives: two tasks arriving together are one task with two halves,
-- and the player simply does them in order. One landing while the other is half walked
-- is an interruption, and handling interruptions is the entire point of the second
-- slot.
local function gapFor(shift: Shift): number
	local tasks = Config.Work.Tasks
	if liveTasks(shift) > 0 then
		return tasks.GapSeconds * tasks.SecondTaskGapMultiplier
	end
	return tasks.GapSeconds
end

local function issueTask(player: Player, shift: Shift, only: string?)
	local pool = JobTasks.For(shift.jobId)
	if #pool == 0 then
		if not warnedNoRoom[shift.jobId] then
			warnedNoRoom[shift.jobId] = true
			warn(`[AGES] job "{shift.jobId}" has no tasks authored -- every shift at it pays a full wage for nothing. Add tasks to JobTasks.luau or remove the job.`)
		end
		return
	end

	-- Fresh ones first, and only then round again. Same rule as shift moments and for
	-- the same reason: being asked to sweep the same aisle twice running reads as the
	-- game having lost its place rather than as a job.
	-- A rush needs the floor to itself, so it is only a candidate when the floor is
	-- clear. Skipped rather than deferred: the pool is reshuffled every time, so a rush
	-- passed over now is picked the moment the player finishes what they are holding,
	-- which is exactly when it should arrive.
	local alone = liveTasks(shift) == 0

	local candidates: { JobTask } = {}
	for _, task in pool do
		if task.rush ~= nil and not alone then
			continue
		end
		if only ~= nil then
			if task.id == only then
				table.insert(candidates, task)
			end
		elseif not shift.tasksUsed[task.id] then
			table.insert(candidates, task)
		end
	end
	if only ~= nil then
		-- An unknown id asks for nothing rather than for something else. The harness
		-- reports the miss, and a silent substitution would have the tester watching
		-- the wrong task and drawing conclusions about it.
		if #candidates == 0 then
			return
		end
	elseif #candidates == 0 then
		-- Round again. Rebuilt from the pool rather than assigned it, because the rush
		-- rule has to survive the wrap: handing back the raw pool here is how the one
		-- task that must never run alongside another ends up doing exactly that, on the
		-- second lap of every shift, for the rest of the game.
		shift.tasksUsed = {}
		candidates = {}
		for _, task in pool do
			if task.rush ~= nil and not alone then
				continue
			end
			table.insert(candidates, task)
		end
		-- A job whose entire list is rushes, asked for a task while one is in hand. Not
		-- an error and not worth a warning: the slot stays empty and the next gap asks
		-- again, by which time the rush has almost certainly finished.
		if #candidates == 0 then
			return
		end
	end

	local character = player.Character
	if character == nil then
		return
	end

	-- Shuffled and then worked through, rather than one pick and give up. In a room
	-- with space for one mark and not two -- a corner shop, a stockroom the size of a
	-- cupboard -- a single random pick lands on a two-mark task about half the time and
	-- issues nothing, and the player stands there through another gap having done
	-- nothing wrong. Trying the rest of the list costs a few raycasts once every fifteen
	-- seconds and buys a shift that keeps asking as long as anything at all fits.
	for index = #candidates, 2, -1 do
		local swap = math.random(index)
		candidates[index], candidates[swap] = candidates[swap], candidates[index]
	end

	-- Where the other task's marks already are. Resolved once, outside the loop, because
	-- it does not change as candidates are tried and rejected -- and because forgetting
	-- it is the one mistake here that would not look like a bug: the marks would simply
	-- land close together sometimes, and the shift would quietly go back to paying for
	-- standing still.
	local taken = markedSpots(shift)

	for _, chosen in candidates do
		-- Every mark resolved before the task is issued, never one at a time. That is
		-- what makes a two-mark task honest: if the room has room for one and not two,
		-- this one is passed over entirely, instead of stranding somebody halfway
		-- through a fetch with nowhere to bring it back to and a clock still running.
		--
		-- `avoid` starts from the marks the other task is using and grows as this one
		-- places its own, so the separation rule that always kept a fetch honest now also
		-- keeps two tasks from being one.
		local avoid = table.clone(taken)
		local spots: { Vector3 } = {}
		local placed = true
		for _ = 1, chosen.spots do
			local spot = WorkSpots.Find(character, shift.station, avoid)
			if spot == nil then
				placed = false
				break
			end
			table.insert(spots, spot)
			table.insert(avoid, spot)
		end
		if not placed then
			continue
		end

		-- Somebody to wait on it, if the task has one authored and the room has space
		-- for them beyond the last mark. Never a reason to reject the task: a shop too
		-- tight to fit a customer runs the till task with nobody at the till, which is
		-- exactly how every shift in this game ran until now.
		local customer: Customer? = nil
		local line = chosen.customer
		local seconds = chosen.seconds
		local rush = false

		if line ~= nil then
			local wanted = math.min(chosen.rush or 1, Config.Work.Customers.MaxQueue)
			local last = spots[#spots]
			local slots, from = WorkSpots.Line(shift.station, last, wanted)

			if #slots > 0 then
				customer = Customers.Queue(player, slots, from, last, line)
			end

			-- A rush is the authored task repeated once per person who actually fits.
			-- Both halves of that matter: a queue of three in a room with space for two
			-- is one person permanently unreachable behind a wall, and three round trips
			-- for a queue of two is a clock the player cannot make sense of.
			if chosen.rush ~= nil then
				local people = math.max(#slots, 1)
				rush = people > 1
				if rush then
					-- The counter is fixed -- it is where the queue is standing, and a queue
					-- that moved would not be one -- and the other end is looked up fresh for
					-- each person.
					--
					-- That second half is the difference between a rush and a treadmill. Six
					-- lengths of the same lane is one walk done six times and the player stops
					-- looking up after the second; a different shelf each time is a shop they
					-- have to know their way around under a clock, which is the only thing
					-- being asked of them here that gets easier with practice.
					local counter = spots[2]
					local rounds: { Vector3 } = { spots[1] }
					for _ = 2, people do
						-- Kept clear of the counter and of nothing else. Landing on the shelf
						-- from two customers ago is fine and reads fine -- shops repeat -- but
						-- landing next to the till would turn a round trip into a pivot.
						local another = WorkSpots.Find(character, shift.station, { counter })
						-- A room with nowhere left to put one sends them back to the first
						-- shelf rather than dropping a leg. Repetitive beats a rush that is
						-- suddenly one person shorter than the queue standing in front of it.
						table.insert(rounds, another or rounds[1])
					end

					spots = {}
					for _, shelf in rounds do
						table.insert(spots, shelf)
						table.insert(spots, counter)
					end

					-- Scaled off the authored count, so shortening the queue shortens the
					-- clock in step and a cramped shop is an easier shift to look at and
					-- exactly as hard a one to work.
					seconds = chosen.seconds * (people / (chosen.rush :: number))
				end
			end
		end

		shift.tasksUsed[chosen.id] = true
		shift.tasksIssued += 1
		-- Appended, never inserted at the front. The HUD reads the list top-down, so the
		-- order it arrives in is the order the player sees, and a new task pushing the
		-- one they are already walking to down a row is a HUD that moves while it is
		-- being read.
		table.insert(shift.tasks, {
			id = chosen.id,
			label = chosen.label,
			mark = chosen.mark,
			handMark = chosen.handMark or chosen.mark,
			spots = spots,
			at = 1,
			rush = rush,
			secondsLeft = seconds,
			secondsTotal = seconds,
			expired = false,
			expiredFor = 0,
			customer = customer,
		})
		return
	end

	-- Every candidate was rejected, which in practice means the room is too tight to
	-- fan marks out in. Said out loud because the symptom is invisible from inside the
	-- game and pleasant to the player: a shift with no tasks issues no tasks, misses
	-- none, and therefore reads as a shift where nothing was asked -- which pays in
	-- full and climbs the ladder at base rate. A station nobody can work is a station
	-- that pays for standing, and that is the exact bug this whole file is fighting.
	if not warnedNoRoom[shift.jobId] then
		warnedNoRoom[shift.jobId] = true
		warn(`[AGES] job "{shift.jobId}" could not place a single task mark at its station -- the room is too cramped to fan out in, so shifts there pay in full for no work. Widen the room or move the place point.`)
	end
end

-- Finishing one. The tip is paid on the spot and in cash, which is the entire point:
-- a wage arrives once an hour whether you moved or not, and this arrives because you
-- just did something. It is the only money in a shift with a cause the player can
-- point at.
-- Takes the index rather than the task, because the caller is walking the list and the
-- one thing this must do exactly once is take it out of that list.
--
-- Deliberately does not touch nextTaskIn. The refill clock belongs to the shop, not to
-- any one task: with two slots, resetting the gap every time something finished would
-- mean a fast player kept pushing the next arrival away and ended up with less work
-- than a slow one, which is precisely backwards.
local function completeTask(player: Player, data: LifeData, shift: Shift, job: Job, index: number)
	local task = shift.tasks[index]
	if task == nil then
		return
	end
	table.remove(shift.tasks, index)
	shift.tasksDone += 1

	-- Served before the money, so the person you did it for reacts to it rather than
	-- to the tip landing. They see themselves out from here.
	if task.customer ~= nil then
		task.customer.serve()
	end

	-- A share of the hour rather than a figure per task, so the tip climbs with the
	-- ladder and with the player's record without a second table to keep in step:
	-- rateFor already carries the raise their standing earned them.
	local tasks = Config.Work.Tasks
	local tip = math.floor(rateFor(data, job) * tasks.TipShareOfHour)

	-- Held under a ceiling for the shift, because nothing else bounds them: a task
	-- ends on contact, so tips scale with how fast a player can walk between marks
	-- and not with how long they worked. Past the cap the task still counts toward
	-- the verdict and still moves the record -- it just stops paying, so working on
	-- is worth doing for the standing rather than for the money.
	local ceiling = math.floor(rateFor(data, job) * Config.Work.ShiftGameHours * tasks.TipCapShareOfShift)
	local headroom = math.max(0, ceiling - shift.tipsPaid)
	tip = math.min(tip, headroom)

	if tip > 0 then
		shift.tipsPaid += tip
		shift.earned += tip
		MoneyService.Add(player, tip, `tip: {job.id}/{task.id}`)
		-- Where they are standing, not where the counter is. The number comes out of
		-- the thing they just did.
		MoneyPop.Show(task.spots[#task.spots], tip)
	end

	push(player)
end

-- Running out of time. Costs nothing directly and that is deliberate: what a missed
-- task costs is settled once, at the end of the shift, against how many were missed.
-- Docking a point here would put eight or nine standing swings inside four minutes
-- and flatten a ladder whose bands sit at 6, 14 and 24.
--
-- But it is said out loud. The task is marked rather than dropped, so it holds the HUD
-- row for the length of the gap saying it was missed, and the mark comes off the floor
-- because there is no longer anywhere to go. Silently deleting both would leave the
-- player to work out from a number at the end of the shift that the game had been
-- keeping score of something it never mentioned.
-- Deliberately does not touch nextTaskIn, and does not remove the task. It stays in the
-- list, marked, aging on its own MissLingerSeconds clock -- so it holds a row and
-- nothing else. Holding a slot as well is what the single shared gap used to do, and it
-- meant every miss silently cost the player a second task on top of the first.
local function failTask(task: ActiveTask)
	if task.expired then
		return
	end
	task.expired = true
	task.secondsLeft = 0
	task.expiredFor = 0

	-- They go now, while the HUD row stays for a few seconds to say what happened.
	-- Deliberately opposite ways round: the row is the game telling you, and the empty
	-- space where somebody was standing is the shop telling you.
	if task.customer ~= nil then
		task.customer.giveUp()
	end
end

-- One tick of the task loop, while a shift is running.
--
-- Returns nothing and decides nothing about the shift itself. Reaching a mark is the
-- only thing here the player does; everything else is a clock.
--
-- Runs in four passes over the list rather than doing everything to one task before
-- looking at the next, and the ordering is the correctness of the whole function. Task
-- by task, the task that happened to be first would get its clock, its reach and its
-- refill resolved while the second one was still holding last tick's state -- so a
-- player standing squarely on a mark could watch it expire because the other task was
-- earlier in the list. Every task gets each question asked of it before any task is
-- asked the next one.
--
-- Every pass walks backwards, because two of them remove entries.
local function tickTasks(player: Player, data: LifeData, shift: Shift, job: Job, elapsed: number, position: Vector3?)
	-- Held while a prompt is open, and this is the single most load-bearing line in
	-- the shift loop. A shift moment is several sentences and a choice that changes
	-- your record; if its clock kept running, the correct way to play would be to
	-- dismiss the writing unread and get back to the mark. The game would have taught
	-- players to skip the part of it that is actually about a life. With two tasks live
	-- it holds both, which is the only defensible reading of "paused".
	if data.pendingEventId ~= nil then
		pushTasks(player, shift, true)
		return
	end

	local tasks = Config.Work.Tasks

	-- 1. Retire the misses whose few seconds on the HUD are up.
	for index = #shift.tasks, 1, -1 do
		local task = shift.tasks[index]
		if task.expired then
			task.expiredFor += elapsed
			if task.expiredFor >= tasks.MissLingerSeconds then
				table.remove(shift.tasks, index)
			end
		end
	end

	-- 2. Clocks. Nothing is removed here -- a task that runs out becomes a miss and
	-- stays in the list to say so.
	for _, task in shift.tasks do
		if task.expired then
			continue
		end
		task.secondsLeft -= elapsed
		if task.secondsLeft <= 0 then
			failTask(task)
		end
	end

	-- 3. Feet. A player can only be standing on one mark, and issueTask keeps every
	-- live mark a stride apart from every other, so at most one of these can fire on a
	-- tick -- but the loop does not rely on that, because relying on it would make a
	-- placement bug in another function come out as a scoring bug in this one.
	if position ~= nil then
		for index = #shift.tasks, 1, -1 do
			local task = shift.tasks[index]
			if task.expired then
				continue
			end
			if Ground.FlatDistance(position, task.spots[task.at]) > tasks.ReachStuds then
				continue
			end

			if task.at < #task.spots then
				-- Reaching the counter on a rush, with more of it still to come. One person
				-- served, the line steps up, and the clock keeps running -- the only place in
				-- this game where finishing something is not the end of the task.
				--
				-- The last one is deliberately not handled here: it is the same event, but it
				-- also ends the task and pays the tip, and completeTask already serves the
				-- front for exactly that reason.
				if task.rush and task.at % 2 == 0 and task.customer ~= nil then
					task.customer.serve()
				end
				-- Reached the first of two. The second mark was found when the task was
				-- issued, so it is already somewhere real -- it simply had nothing to say
				-- until now.
				task.at += 1
			else
				completeTask(player, data, shift, job, index)
			end
		end
	end

	-- 4. The shop asks for the next thing, if it is time and there is room for it.
	shift.nextTaskIn -= elapsed
	if shift.nextTaskIn <= 0 then
		if liveTasks(shift) < slotsFor(shift) and not rushRunning(shift) then
			issueTask(player, shift)
		end
		-- Reset unconditionally and after the attempt: unconditionally so a room with
		-- nowhere to put a mark waits out another gap rather than retrying four times a
		-- second, and after so the length of the wait reflects what the player is
		-- actually holding now rather than what they were holding a line ago.
		shift.nextTaskIn = gapFor(shift)
	end

	pushTasks(player, shift, false)
end

-- What the shift's tasks were worth, added to what finishing it was worth.
--
-- Deliberately a verdict on the whole shift rather than a running score. Standing
-- bands sit at 6, 14 and 24 and a finished shift is worth 1, so anything paid per
-- task would climb the entire ladder in an afternoon. This way the tasks decide what
-- the shift counted for: work it properly and it counts double, coast and it counts
-- for nothing -- which is the difference between reaching the office in three shifts
-- and reaching it in six.
--
-- A shift that was never given a task -- a job with none authored, or a room with
-- nowhere to stand -- scores as ordinary rather than as poor. The player did
-- everything that was asked of them; nothing was.
local function shiftTaskStanding(shift: Shift): number
	local tasks = Config.Work.Tasks
	local base = Config.Work.Standing.PerShiftWorked

	local share = taskShareOf(shift)
	if share == nil then
		return base
	end

	if share >= tasks.GoodShare then
		return base + tasks.PerGoodShift
	end
	if share >= tasks.OkShare then
		return base
	end
	return tasks.PoorShiftStanding
end

-- The shift's one moment. Picks from the Shift route -- which nothing else can
-- draw from, so a work event can only ever reach the player at work -- and offers
-- it through the ordinary eligibility path.
--
-- A quiet no is the normal answer: every work event may already have been lived
-- this life, or a prompt may be open, or a letter may be sitting on the mat at
-- home. Marked fired either way, because a shift gets one attempt at a moment and
-- retrying every tick would turn "nothing happened today" into a poll.
-- Whether a moment may be offered on this shift at all. Shared by both picks
-- below because the fallback exists to allow a repeat, not to open a gate: an
-- event that needs the office and a certain standing there is *wrong* to offer
-- anywhere else, and that stays true on the second try.
local function momentFits(shift: Shift, standing: number, candidate: LifeEvent): boolean
	if candidate.jobs ~= nil then
		local allowed = false
		for _, jobId in candidate.jobs do
			if jobId == shift.jobId then
				allowed = true
				break
			end
		end
		if not allowed then
			return false
		end
	end
	if candidate.minStanding ~= nil and standing < candidate.minStanding then
		return false
	end
	return true
end

local function tryShiftEvent(player: Player, shift: Shift)
	shift.eventFired = true

	-- The gate is checked against the standing the player actually has at the job
	-- being worked, which is the number the ladder moves -- so the unlock is
	-- earned here, at the counter, and not somewhere the life was not standing.
	local profile = DataService.GetProfile(player)
	local standing = 0
	if profile ~= nil then
		standing = standingAt(Lives.Active(profile.Data), shift.jobId)
	end

	-- Asked for anything but the last thing that happened to them first. Once the
	-- unlived work events run out every shift draws from the repeatable pool, and
	-- without this the same customer would occasionally be rude to you twice in a
	-- row -- which is the single most obvious way a repeat can read as a bug rather
	-- than as a life.
	local previous = lastMoment[player]
	local event = EventService.PickStageable(player, "Shift", function(candidate: LifeEvent): boolean
		return candidate.id ~= previous and momentFits(shift, standing, candidate)
	end)
	-- Nothing but the last one was available, so the last one it is. A repeat beats
	-- a silent shift, and this is only reachable when the pool is down to one.
	if event == nil then
		event = EventService.PickStageable(player, "Shift", function(candidate: LifeEvent): boolean
			return momentFits(shift, standing, candidate)
		end)
	end
	if event == nil then
		return
	end

	if EventService.OfferIfEligible(player, event.id) then
		lastMoment[player] = event.id
	end
end

-- How an answer landed with your employer. Called for every event answered
-- anywhere in the game, so the guards are the feature: only while on shift, and
-- only for a choice that was authored with an opinion attached.
--
-- Scored against the job being worked rather than the job held. They are the same
-- thing today, and will stop being on the day someone can be moonlighting.
local function onAnswered(player: Player, _event: LifeEvent, choice: EventChoice)
	local shift = shifts[player]
	if shift == nil then
		return
	end

	local performance = choice.performance
	if performance == nil then
		return
	end

	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end

	adjustStanding(player, Lives.Active(profile.Data), shift.jobId, performance)
	-- Pushed here rather than left to the next tick, so the HUD names the new
	-- standing on the same frame the outcome line appears.
	push(player)
end

-- One player, one tick. Split out because the loop below has to keep going for
-- everyone else no matter what this does.
local function tickPlayer(player: Player, elapsed: number)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)
	local shift = shifts[player]
	local position = characterPosition(player)

	-- Nobody is pointed anywhere while they are working. Partly because they are
	-- already where the game wanted them, and partly because the office is up a
	-- staircase from the shop floor: without this, a shop assistant who has just
	-- earned the right to work upstairs would spend every remaining shift of their
	-- life with a line running out of the room they are being paid to stand in.
	setGuide(player, if shift == nil and enabled then guideTargetFor(data) else nil)

	-- The signs, on the other hand, stay up while you work. They are part of how the
	-- street reads, not an instruction: the office sign should still be legible from
	-- behind the shop counter, because seeing where you are going next is the whole
	-- reason to keep turning up. The one it never shows is the job you are standing in.
	setPosts(player, data)

	if shift == nil then
		-- Not working. The only question is whether they have just walked up to
		-- somewhere they could be -- and if they have and cannot, why not.
		if not enabled or not data.alive or position == nil then
			setBlocked(player, nil)
			return
		end

		-- Checked before anything about where they are standing, and that order is
		-- load-bearing: the guard clears on distance from the *old* station, so asking
		-- it only when near a station would mean it could never clear at all.
		local awayFrom = mustStepAway[player]
		if awayFrom ~= nil then
			-- Has to leave before they can come back. Measured against the station
			-- radius rather than the clock-in radius, so stepping one pace off the
			-- marker is not enough -- you have to actually stop working.
			if Ground.FlatDistance(position, awayFrom) > Config.Work.StationRadiusStuds then
				mustStepAway[player] = nil
			else
				setBlocked(player, "You have just finished here. Step away before you start another shift.")
				return
			end
		end

		local job, station = stationAtHand(position)
		if job == nil or station == nil then
			-- Standing nowhere in particular, which is where a player spends nearly all
			-- of their life. Nothing to explain.
			setBlocked(player, nil)
			return
		end

		-- Standing at a counter they do not work behind. Being here is not enough any
		-- more; there is a mark on the floor and taking the job means stepping onto it.
		if data.jobId ~= job.id then
			local refusal = hireRefusalFor(data, job)
			if refusal ~= nil then
				-- Asked before the pad rather than after, so the answer is the same
				-- whether they are hovering at the edge of the counter or standing
				-- squarely on the mark. A door that only explains itself once you are
				-- close enough to touch it is a door that mostly stays silent.
				setBlocked(player, refusal)
				return
			end

			-- Measured against the station and the pad radius rather than against the
			-- built pad, because the pad is now drawn on the player's own machine and
			-- the server does not have one to measure. That is not a compromise: the
			-- pad was only ever painted at the station with this radius, so this is the
			-- same number arrived at from the definition instead of from the drawing --
			-- and it means a client that drew nothing at all still cannot be hired from
			-- across the room.
			if Ground.FlatDistance(position, station) > Config.Work.Hiring.PadRadiusStuds then
				-- Welcome to it, and not yet on the mark. The one case in this whole
				-- function where nothing is wrong and there is still something to say.
				setBlocked(
					player,
					if data.jobId == nil
						then "Step onto the mark to take this job."
						else "Step onto the mark to move to this job."
				)
				return
			end

			takeJob(player, data, job)
			-- Falls through rather than returning: they took the job while standing at
			-- the counter, and making them step off the mark and back on again to
			-- actually start would be a rule with nothing behind it.
		end

		local refusal = refusalFor(data, job)
		if refusal ~= nil then
			setBlocked(player, refusal)
			return
		end

		setBlocked(player, nil)
		startShift(player, job, station)
		return
	end

	-- Working, so there is nothing they are being kept out of.
	setBlocked(player, nil)

	-- On shift from here down.
	local job = Jobs.ById[shift.jobId]
	if job == nil then
		-- The job was deleted from content while someone was working it. Not a
		-- silent stop: there is no rate to pay them at, so the shift cannot continue.
		warn(`[AGES] {player.Name} was working "{shift.jobId}", which is no longer a job`)
		-- Nothing to their record either way. The job going missing is our fault, not
		-- theirs, and marking them down for it would be the wrong half of a bug.
		endShift(player, "the job no longer exists", 0)
		return
	end

	if not data.alive then
		-- Also nothing. There is no version of this where what your employer thought
		-- of you at the end matters, and the record dies with the life regardless.
		endShift(player, "died", 0)
		return
	end

	if position == nil then
		-- Mid-respawn. Not an ending -- the character comes back in a moment and
		-- the clock is not running while there is nobody to be at the station.
		return
	end

	-- A prompt this shift raised is answered by walking, sometimes to a marker a
	-- few studs off. Clocking someone out for answering a question their job asked
	-- them would be the one interaction in this system that punishes playing it.
	local answering = data.pendingEventId ~= nil
	if not answering and Ground.FlatDistance(position, shift.station) > Config.Work.StationRadiusStuds then
		-- No step-away guard on this one, unlike the two endings below: they leave the
		-- player standing on the spot, whereas this player has already gone. Walking
		-- back in should clock them straight on, because the walk was the cost.
		--
		-- The only ending that costs you. It costs more than finishing a shift pays,
		-- which is what stops a walk-out from being a cheap way to end a shift you
		-- were bored of and start a fresh one -- and it is why an event open at your
		-- station suppresses this check a few lines up. Being marked down for
		-- answering a question your job asked you would be indefensible.
		endShift(player, "walked out", Config.Work.Standing.PerWalkOut)
		return
	end

	shift.realSeconds += elapsed

	-- A while rather than an if: a server that hitched for a minute owes every
	-- hour that passed in it, not one.
	local secondsPerHour = Config.Time.RealSecondsPerGameHour
	while
		shift.realSeconds >= (shift.hoursCredited + 1) * secondsPerHour
		and shift.hoursCredited < Config.Work.ShiftGameHours
		and data.workGameHoursThisYear < hoursAllowedThisYear()
	do
		creditHour(player, data, shift, job)
	end

	if shift.hoursCredited >= Config.Work.ShiftGameHours then
		mustStepAway[player] = shift.station
		-- Turning up and staying to the end is worth something on its own, and what it
		-- is worth now depends on what you did while you were there. This is still the
		-- floor of the whole system -- a player who never sees a single moment, and
		-- simply does the job, climbs -- but "does the job" finally means something
		-- other than standing still for four minutes.
		endShift(player, "shift worked out", shiftTaskStanding(shift))
		return
	end

	if data.workGameHoursThisYear >= hoursAllowedThisYear() then
		mustStepAway[player] = shift.station
		-- Credited as a finished shift, because from where the player is standing it
		-- is one: they worked until the work ran out. The year's cap already stops
		-- this from being repeatable, so there is nothing here to farm.
		endShift(player, "no hours left this year", shiftTaskStanding(shift))
		return
	end

	if not shift.eventFired and shift.hoursCredited >= shift.eventAtHour then
		tryShiftEvent(player, shift)
	end

	-- Last, and after every way this tick could have ended the shift has been asked.
	-- A task issued on the same tick the shift finished would paint a mark on the
	-- floor a fraction of a second before endShift takes it away again.
	tickTasks(player, data, shift, job, elapsed, position)

	push(player)
end

-- A year ended: the allowance refills. Deliberately does not end a shift in
-- progress -- a birthday at work is still a day at work, and the hours already
-- worked belonged to the year that just closed.
function WorkService.OnAgeUp(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)
	data.workGameHoursThisYear = 0
	-- The year turning is exactly what a sacking's cooldown waits for. Cleared here so a
	-- player let go last year can walk back up to the counter on their birthday and be
	-- considered again -- the door the firing shut opens once, on its own, with time.
	data.firedFrom = {}
	push(player)
end

-- A new life. The job goes with the person who had it, and so does everything
-- anyone thought of them.
function WorkService.ResetForNewLife(player: Player)
	-- Nothing to the record: it is about to be thrown away entirely, and adjusting
	-- it first would be writing to a table one line before it is emptied.
	endShift(player, "new life", 0)
	mustStepAway[player] = nil
	blocked[player] = nil
	lastMoment[player] = nil

	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		Lives.Active(profile.Data).jobId = nil
		Lives.Active(profile.Data).workGameHoursThisYear = 0
		-- Cleared wholesale rather than key by key. A career is not inherited: the
		-- next life walks into the same shop as a stranger, which is the point.
		Lives.Active(profile.Data).jobStanding = {}
		-- And a stranger has never been let go from anywhere. Same reason as the standing
		-- beside it: the record the cooldown reads belonged to the last person's career.
		Lives.Active(profile.Data).firedFrom = {}
	end
	push(player)
end

-- Studio harness: clocks on wherever the player is standing, skipping the walk to
-- the station but nothing else. The station becomes their current position, so
-- walking away still clocks them out and the radius is still the radius.
--
-- Deliberately does *not* skip the qualification check, and returns the refusal so
-- the harness can print it. A test tool that could open a door the game keeps shut
-- would be a tool that cannot test the door -- and the ladder is the one thing in
-- here most worth being able to stand in front of and read the reason off.
-- `/job standing` is how you get past it, which is honest about what it is doing.
function WorkService.ForceStart(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end

	local position = characterPosition(player)
	if position == nil then
		return false, "no character to clock on"
	end

	-- Whatever they are standing at, or failing that the best they could take. The
	-- second case is the usual one for this command: it exists precisely so a shift
	-- can be tested without the walk to the far end of the street.
	local job = stationAtHand(position) or heldJob(Lives.Active(profile.Data)) or bestEligibleJob(Lives.Active(profile.Data))
	if job == nil then
		return false, "no job you could take anywhere"
	end

	local refusal = refusalFor(Lives.Active(profile.Data), job)
	if refusal ~= nil then
		return false, refusal
	end

	-- Hires as well as clocks on, because the alternative is a harness that cannot
	-- test a shift without first walking to the pad -- which is the walk this command
	-- exists to skip. The refusal above is the same one the pad would have given, so
	-- nothing is being waved through: this takes the job on the player's behalf only
	-- in cases where stepping on the mark would have worked.
	if Lives.Active(profile.Data).jobId ~= job.id then
		takeJob(player, Lives.Active(profile.Data), job)
	end

	mustStepAway[player] = nil
	return startShift(player, job, position), nil
end

-- Studio harness: gives the job up without ending the life.
--
-- There is no way to quit from inside the game, and deliberately not -- walking away
-- from a career is a real decision that deserves a real design, and it is not this
-- one. But taking a job is now a thing you walk onto a mark to do, and a test you can
-- only run once per life is not a test: without this, checking the hiring pad a
-- second time means dying and living another sixteen years first.
--
-- The record stays. Standing is per job and survives being unemployed, which is both
-- right -- the shop remembers you -- and the more useful thing to be able to test.
function WorkService.Quit(player: Player): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil or Lives.Active(profile.Data).jobId == nil then
		return false
	end

	-- Nothing to the record, matching ForceEnd: the harness ended this, not the
	-- player, and a test tool should not mark somebody down for being a test tool.
	endShift(player, "quit (harness)", 0)
	Lives.Active(profile.Data).jobId = nil

	-- So the pad is stepped back onto rather than walked through: they are almost
	-- certainly standing on it right now, having just used it to get hired.
	mustStepAway[player] = nil
	push(player)
	return true
end

-- Studio harness: the sacking, on demand, without the run of bad shifts it normally
-- takes to earn. The one way to stand in front of the fired state and read it -- the
-- re-hire refusal, the cleared shift row, the cooldown that lifts on a birthday --
-- without grinding standing down to the floor a walk-out at a time.
--
-- Goes through endShift first so the shift is torn down exactly as a real firing's is,
-- then fires only if that did not already do it: endShift auto-fires when standing is
-- at the floor, so a player who was genuinely on thin ice is let go by the real path
-- and this only steps in for the harness's usual case, a player nowhere near it yet.
-- Nothing to the record -- the harness ended this, not a bad year.
function WorkService.ForceFire(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	local data = Lives.Active(profile.Data)
	local jobId = data.jobId
	if jobId == nil then
		return false, "no job to be let go from"
	end

	endShift(player, "let go (harness)", 0)
	-- Still holding it means the real path did not fire them -- their standing was above
	-- the floor -- so the harness does the sacking itself, on the job they held going in.
	if data.jobId ~= nil then
		fire(player, data, jobId)
	end
	mustStepAway[player] = nil
	return true, nil
end

-- Studio harness: the next task now, instead of after the gap.
--
-- The one thing that makes the task loop testable at all. A task lasts fifteen
-- seconds and arrives every eighteen, so checking a change to the search or to the
-- HUD row otherwise means clocking on and waiting through a shift for a mark to land
-- somewhere interesting. Returns false for the ordinary reasons -- not on shift, or a
-- room with nowhere to put one -- and the caller reports which.
--
-- `taskId` asks for one by name, which is the only way to test a specific task in
-- reasonable time: the one with a customer, the one with two marks, the one with the
-- longest clock.
function WorkService.ForceTask(player: Player, taskId: string?): boolean
	local shift = shifts[player]
	if shift == nil then
		return false
	end

	-- Whatever they were doing is abandoned rather than completed or failed, and it is
	-- taken back off the shift's report card on the way out. A harness that quietly
	-- docked the player for every task it skipped past would make the end-of-shift
	-- verdict untestable by the only tool that can reach it quickly.
	--
	-- One already missed is left counted, though. `/job fail` then `/job task` is how a
	-- tester builds a bad shift on purpose, and un-counting the miss would erase the
	-- very thing they were assembling.
	--
	-- All of them, so that `/job task` puts the shift into a known state with exactly
	-- one thing in it. A harness that left the other slot running would have the tester
	-- watching two tasks and drawing conclusions about the wrong one.
	for index = #shift.tasks, 1, -1 do
		local previous = shift.tasks[index]
		if not previous.expired then
			shift.tasksIssued -= 1
		end
		if previous.customer ~= nil then
			previous.customer.destroy()
		end
		table.remove(shift.tasks, index)
	end

	issueTask(player, shift, taskId)
	pushTasks(player, shift, false)
	return #shift.tasks > 0
end

-- Studio harness: run the clock out on the task in hand, without waiting for it.
--
-- Exists because the failure path is the half of this loop that is hard to reach on
-- purpose and easy to get wrong: it has to take the mark off the floor, clear the HUD
-- row, start the gap, and leave the shift's report card one worse. Standing still for
-- fifteen seconds proves that once; this proves it eight times in a shift.
function WorkService.ForceFailTask(player: Player): boolean
	local shift = shifts[player]
	if shift == nil then
		return false
	end
	-- The oldest one still running, which with two slots is the one whose clock was
	-- always going to run out first. Deliberately one per call rather than all of them:
	-- `/job fail` twice in a row is how a tester fails both, and a single call that
	-- wiped the board would make failing exactly one impossible to arrange.
	--
	-- Nothing to run the clock out on, and one that already ran out is not a second
	-- one: false here is what tells the caller to say "no task in hand" rather than
	-- reporting a miss that never happened.
	for _, task in shift.tasks do
		if not task.expired then
			failTask(task)
			pushTasks(player, shift, false)
			return true
		end
	end
	return false
end

-- Studio harness: wind the shift's clock forward to the end of a given game hour.
--
-- Exists for the second task slot. It does not open until
-- `Config.Work.Tasks.SecondSlotFromHour`, and two live tasks is the single most
-- important thing about a shift to actually look at -- so the alternative to this is a
-- minute and a half of standing in a shop before the test can begin, once per shift,
-- every time.
--
-- Moves `realSeconds` rather than `hoursCredited`, so the ordinary catch-up loop in the
-- tick does the crediting: the hours are paid, the wage share earned by the tasks so far
-- is applied, and the shift moment fires if it was due on the way past. Writing the
-- counter directly would hand the tester a shift claiming four hours that paid for none,
-- which is a worse thing to reason from than the slow wait it replaces.
function WorkService.ForceShiftHour(player: Player, hour: number): boolean
	local shift = shifts[player]
	if shift == nil then
		return false
	end
	-- Forward only, and that is a correctness rule rather than a convenience. The
	-- catch-up loop pays every hour standing between the clock and `hoursCredited`;
	-- winding the clock back behind hours already credited would leave that stretch to be
	-- walked -- and paid -- a second time as the shift caught back up to where it was.
	local target = math.clamp(math.floor(hour), 0, Config.Work.ShiftGameHours)
	local seconds = target * Config.Time.RealSecondsPerGameHour
	if seconds <= shift.realSeconds then
		return false
	end
	shift.realSeconds = seconds
	return true
end

function WorkService.ForceEnd(player: Player): boolean
	if shifts[player] == nil then
		return false
	end
	-- Not marked as needing to step away: the harness ended this, not the player,
	-- so "/job end" then "/job start" should work from the same spot. Nothing to the
	-- record either, for the same reason -- this ending was not something they did.
	endShift(player, "debug /job end", 0)
	return true
end

-- Studio harness: sets what a named job thinks of the player, which is the only
-- practical way to stand in front of the office door and watch it open. Reaching
-- the requirement honestly is several shifts of shop work.
function WorkService.SetStanding(player: Player, jobId: string, value: number): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil or Jobs.ById[jobId] == nil then
		return false
	end
	Lives.Active(profile.Data).jobStanding[jobId] = math.clamp(math.floor(value), STANDING.Min, STANDING.Max)
	push(player)
	return true
end

-- Forces the shift's moment now rather than at the hour it was rolled for.
-- Returns false when there was no shift to have a moment in.
function WorkService.ForceEvent(player: Player): boolean
	local shift = shifts[player]
	if shift == nil then
		return false
	end
	tryShiftEvent(player, shift)
	return true
end

-- Sets the year's hour count, which is the only practical way to test the cap:
-- reaching it honestly is forty game hours of standing in a shop.
function WorkService.SetHoursWorked(player: Player, hours: number): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	Lives.Active(profile.Data).workGameHoursThisYear = math.clamp(math.floor(hours), 0, hoursAllowedThisYear())
	push(player)
	return true
end

function WorkService.SetEnabled(value: boolean)
	enabled = value
end

function WorkService.IsEnabled(): boolean
	return enabled
end

-- What the harness prints for /job.
function WorkService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded"
	end

	local data = Lives.Active(profile.Data)
	local ageYears = ageYearsOf(data)
	local job = heldJob(data)
	local shift = shifts[player]

	local held: string
	if job ~= nil then
		-- Base and actual both, because the whole question this line has to answer is
		-- "is my record paying me anything yet", and one number cannot answer it.
		local base = Jobs.HourlyRate(job)
		local rate = rateFor(data, job)
		local standing = standingAt(data, job.id)
		held = string.format(
			'%s (%s/yr, %s/game hr base, %s now) | record %d "%s"',
			job.title,
			Money.Format(job.yearlySalary),
			Money.Format(base),
			Money.Format(rate),
			standing,
			bandFor(standing).name
		)
	else
		local available = bestEligibleJob(data)
		if available == nil then
			-- Deliberately does not guess *why*. Since the ladder exists there are
			-- several reasons nothing is open -- too young, not thought well enough of
			-- anywhere, or simply out of hours for the year -- and the line below spells
			-- out the real one per job rather than this one asserting the likeliest.
			held = `no job, and nothing open to you at {ageYears}`
		else
			held = `no job yet — could take "{available.id}" at the "{available.placeId}" point`
		end
	end

	-- Every job and what currently stands between the player and it. The one line
	-- that makes the ladder legible from a chat command rather than by walking the
	-- building, which matters most for the rung you *cannot* reach yet.
	local ladder: { string } = {}
	for _, entry in Jobs.All do
		local refusal = refusalFor(data, entry)
		table.insert(ladder, `{entry.id}: ` .. (if refusal == nil then "open" else refusal))
	end

	local doing: string
	if shift == nil then
		doing = if mustStepAway[player] ~= nil
			then "off shift (step away from the station before clocking on again)"
			else "off shift"
	else
		-- What they are doing this minute, and how the shift is going. The second half
		-- is the useful one: the tasks decide what the whole shift is worth to the
		-- record, and "5/7" printed here is the only way to see that verdict coming
		-- before it lands.
		-- Every live task, and the slot count they are being drawn from, because with two
		-- of them the interesting failure is no longer "is there a task" but "why is
		-- there only one". Slots opening partway through the shift, a rush holding the
		-- floor, and a room too cramped for a second mark all look identical from inside
		-- the game and have to be told apart from here.
		local gap = string.format("next in %.1fs", math.max(shift.nextTaskIn, 0))
		local rows: { string } = {}
		for _, task in shift.tasks do
			if task.expired then
				table.insert(rows, string.format('missed "%s" (%.1fs ago)', task.label, task.expiredFor))
			else
				table.insert(
					rows,
					string.format(
						'"%s" mark %d/%d, %.1fs left%s',
						task.label,
						task.at,
						#task.spots,
						task.secondsLeft,
						-- Whether anybody was brought for it, which is the only part of a
						-- customer a log can see: the rig is built on a coroutine and may still
						-- be on its way, and "somebody waiting" is true either way.
						if task.customer ~= nil then ", somebody waiting" else ""
					)
				)
			end
		end

		local onTask = string.format(
			"%s [%d/%d slots%s], %s",
			if #rows == 0 then "between tasks" else table.concat(rows, " + "),
			liveTasks(shift),
			slotsFor(shift),
			if rushRunning(shift) then ", rush holds the floor" else "",
			gap
		)

		doing = string.format(
			"on shift %.1f/%d game hrs, %s earned, moment %s | %s (%d/%d done, shift worth %+d)",
			shift.realSeconds / Config.Time.RealSecondsPerGameHour,
			Config.Work.ShiftGameHours,
			Money.Format(shift.earned),
			if shift.eventFired then "fired" else `due at hour {shift.eventAtHour}`,
			onTask,
			shift.tasksDone,
			shift.tasksIssued,
			shiftTaskStanding(shift)
		)
	end

	-- Where they are being pointed, because the guide is drawn on the client and is
	-- therefore the one part of this system a server-side log cannot otherwise see.
	-- "nowhere" is the correct and usual answer, and worth being able to tell apart
	-- from a guide that is broken.
	local pointedAt = guided[player]
	local pointing = if pointedAt ~= nil and Jobs.ById[pointedAt] ~= nil
		then `pointed at {Jobs.ById[pointedAt].title}`
		else "pointed nowhere"

	-- Which signs this player is currently being shown, for the same reason as the
	-- line above: the posts are drawn on their machine, so this is the only place the
	-- server can be asked what it thinks is standing there. The useful case is the
	-- absence -- after taking a job, that job should have dropped off this list, and
	-- if it has not then the sign still over their head is the server's fault rather
	-- than the client's.
	local showing: { string } = {}
	for _, state in postsFor(data) do
		table.insert(showing, state.jobId .. (if state.padLocked then " (locked)" else ""))
	end

	return string.format(
		"age %d | %s | %s | %d/%d hrs this year (%d/%d shifts) | %s | posts %s | work %s\n  ladder — %s",
		ageYears,
		held,
		doing,
		data.workGameHoursThisYear,
		hoursAllowedThisYear(),
		data.workGameHoursThisYear // Config.Work.ShiftGameHours,
		Config.Work.ShiftsPerYear,
		pointing,
		if #showing == 0 then "none" else table.concat(showing, ", "),
		if enabled then "on" else "off",
		table.concat(ladder, " | ")
	)
end

function WorkService:Init()
	-- Registered here rather than in Start, matching every other injected handler:
	-- Init is where services wire up to each other and Start is where they begin
	-- doing things. Bootstrap runs every Init before any Start, so an event
	-- answered on the very first frame already lands on a listening job.
	EventService.OnAnswered(onAnswered)
end

function WorkService:Start()
	Players.PlayerAdded:Connect(function(player: Player)
		-- Pushed once the profile exists, so a rejoining player's HUD says what job
		-- they hold rather than starting blank and correcting itself on the first
		-- tick they happen to be near a station.
		task.spawn(function()
			if DataService.WaitForProfile(player) ~= nil then
				push(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		-- No banking to do: every hour worked was paid when it completed, so
		-- dropping the shift loses nothing that was owed.
		--
		-- The one thing that does have to be undone by hand is anybody standing at the
		-- counter waiting on them. Dropping the shift table drops the only reference to
		-- that person, and nothing else in the game would ever go looking: the rig
		-- would stand there for the life of the server, in a shop with nobody working
		-- in it, still turning to look at a player who has left.
		local shift = shifts[player]
		if shift ~= nil then
			for _, task in shift.tasks do
				if task.customer ~= nil then
					task.customer.destroy()
				end
			end
		end
		shifts[player] = nil
		mustStepAway[player] = nil
		blocked[player] = nil
		lastMoment[player] = nil
		guided[player] = nil
		postedSignature[player] = nil
		pushedTask[player] = nil
	end)

	task.spawn(function()
		while true do
			-- task.wait returns what actually elapsed, so a hitching server pays for
			-- the time that really passed instead of drifting behind it.
			local elapsed = task.wait(Config.Work.TickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player, elapsed)
				if not ok then
					warn(`[AGES] work tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

return WorkService
