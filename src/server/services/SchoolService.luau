--!strict
-- School: the twelve years of a life that had nothing in them to do.
--
-- Everything between being born and being hired was a stat readout and a text prompt
-- on a birthday. A player could not spend an afternoon being nine, because there was
-- no afternoon -- childhood was a progress bar in front of the job. This is the thing
-- that fills it.
--
-- The loop:
--
--   You walk to the school and step on the pad outside it. A question comes up with
--   three or four answers under it and a clock. You have twenty seconds to pick one.
--   Whatever you pick, the teacher's line explains the answer for a beat, and then the
--   next question comes up. Five of those is a lesson.
--
-- The question opens itself, and that is the one place in this game where nothing has
-- three dots over its head. Dots are for things you walk up to -- a person, an animal
-- -- and they mean "there is something here". A lesson is not something in the room;
-- it is something you are already inside, like a shift. You did the walking when you
-- came to the school. Making a nine-year-old click a building between every question
-- would be charging them for the same journey five times.
--
-- The walk is still what a lesson costs. It is spent at the door rather than at every
-- question, and the clock is what stops the twenty seconds after that being idle.
--
-- What it is for, past being something to do. `smarts` was a number nothing in the
-- game read -- no job asked for it, no event moved it, and it decayed at zero a year.
-- School moves it and the office job now wants it, so the afternoons a nine-year-old
-- spends here are the reason a sixteen-year-old can be something other than a shop
-- assistant. That is the point of the whole system: it makes the first half of a life
-- pay into the second, which is the one thing a life simulator has to do.
--
-- Two things are deliberately *not* here.
--
-- There is no guide line to the school. Config.Guide exists to point at "something
-- that just opened up", and school does not open up -- it is there for the whole of
-- your childhood, in a building on a street, with a sign over the door. The sign and
-- the pad are shared and server-built, on the rule Remotes.luau states: a thing meant
-- for whoever walks past is built in the world, and a thing addressed to one person is
-- pushed to them. A school is a building. A job offer is addressed to you.
--
-- And there is no way to fail into a hole. Missing every question in a lesson costs
-- you the lesson, never smarts; only never turning up at all costs anything, once a
-- year, on the birthday that ends it. A childhood spent elsewhere ends around thirty
-- smarts rather than at zero -- behind, not ruined -- because "failure worth playing"
-- means a bad run you can still play out of.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local ChoiceMarkers = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("ChoiceMarkers"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Mastery = require(ReplicatedStorage:WaitForChild("school"):WaitForChild("Mastery"))
local Report = require(ReplicatedStorage:WaitForChild("school"):WaitForChild("Report"))

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local PlaceService = require(script.Parent.PlaceService)
local StatService = require(script.Parent.StatService)
local SkillService = require(script.Parent.SkillService)
local ScienceService = require(script.Parent.ScienceService)
local GeographyService = require(script.Parent.GeographyService)
local ArtService = require(script.Parent.ArtService)
local MusicService = require(script.Parent.MusicService)
local SoccerService = require(script.Parent.SoccerService)
local Ground = require(script.Parent.Parent.world.Ground)
local Lab = require(script.Parent.Parent.world.Lab)
local Studio = require(script.Parent.Parent.world.Studio)
local Classroom = require(script.Parent.Parent.world.Classroom)
local SubjectModels = require(script.Parent.Parent.world.SubjectModels)
local SubjectMotion = require(script.Parent.Parent.world.SubjectMotion)
local Curriculum = require(script.Parent.Parent.content.Curriculum)
local Lessons = require(script.Parent.Parent.content.Lessons)
local Subjects = require(script.Parent.Parent.content.Subjects)

type LifeData = Types.LifeData
type LessonQuestion = Types.LessonQuestion
type LessonState = Types.LessonState
type OfferedChoice = Types.OfferedChoice
type ReportCard = Types.ReportCard
type SchoolYearRecord = Types.SchoolYearRecord
type SchoolSubject = Types.SchoolSubject
type SubjectRig = SubjectModels.SubjectRig
type Motion = SubjectMotion.Motion

-- One answer disc on the classroom floor. The marker is the drawn pad and the at is
-- the point the player has to reach, kept together because the two belong to the
-- same answer and a disc that moved would otherwise leave its proximity test behind.
type Disc = {
	at: Vector3,
	marker: ChoiceMarkers.ChoiceMarker,
}

local SchoolService = {}

local LessonUpdatedRemote = Remotes.Get("LessonUpdated")
local RequestLessonAnswerRemote = Remotes.Get("RequestLessonAnswer")
local ReportCardUpdatedRemote = Remotes.Get("ReportCardUpdated")
local RequestReportCardReadRemote = Remotes.Get("RequestReportCardRead")
local RequestSitRemote = Remotes.Get("RequestSit")

-- The place id the classroom answers to. A part in Studio carries this on its place
-- attribute, exactly like the shop and the office. Nothing here builds a school: the
-- world is built by hand and this finds it, so moving the building is a drag in Studio
-- and not an edit here.
local PLACE_ID = "school"

-- Where the lab actually goes. "school" is the front door -- the pad the player walks
-- onto and the point the sign hangs from -- and it stands in the forecourt outside the
-- building, not in the room the lab needs to fit inside. tools/world_plan.py lays a
-- second point, "science_lab", in the middle of SCHOOL_SCIENCE's own benches for exactly
-- this call: see its comment on SCIENCE_Z0/Z1 for the room Lab.Build (and
-- Config.School.Science.RoomRadiusStuds) are actually sized against.
local LAB_PLACE_ID = "science_lab"

local SCHOOL = Config.School

-- One lesson in progress. Only ever one per player -- you cannot be in two classrooms.
type Lesson = {
	-- Where the classroom is, taken once at the start rather than looked up per tick.
	-- The lesson is anchored to the room it began in, so a place point that streams out
	-- mid-lesson does not silently move the walls in around the player.
	room: Vector3,

	-- Which subject is being taught. Held on the lesson rather than recomputed at the end
	-- from `subjectFor(data)`, because that function reads `lessonsThisYear` -- which the
	-- lesson itself increments -- so asking it twice can honestly return two different
	-- subjects, and the pass would be banked against whatever is on next.
	subjectId: string,

	questions: { LessonQuestion },
	-- Which question is in front of the player, from 1. Runs one past #questions for
	-- the instant between the last answer and the lesson closing.
	index: number,
	right: number,

	-- Which authored answer each row on the panel is: `order[n]` is the index into
	-- `questions[index].answers` that row number n is showing. The rows are shuffled
	-- and the question is not, which is why this is a second list rather than a
	-- rearrangement of the first -- `correct` keeps meaning what the content file said
	-- it meant.
	--
	-- Shuffled per question and not per lesson, so the right answer is never learnable
	-- as a position. A child who works out that the correct answer is always the top
	-- row has stopped answering questions and started reading the game.
	--
	-- It is also the whole of what the client is told. The rows go out numbered by
	-- their position on the panel, so an answer coming back names a row and this is the
	-- only thing that knows which answer that row was.
	order: { number },

	-- The answer discs on the classroom floor, in row order so disc n answers the same
	-- row the panel row n would have. Nil means this question's answers are rows to
	-- click: either the lesson is not physical, or the floor refused a disc and the
	-- question fell back. Cleared with the question and never kept past the lesson.
	discs: { Disc }?,

	secondsLeft: number,
	-- Counts down while the teacher's line is being held, and is the flag for "an
	-- answer has been given and the next question has not started". Zero means the
	-- question is live.
	verdictLeft: number,
	verdictText: string?,
	verdictRight: boolean,

	-- Whether the player has actually sat down at a Classroom desk yet. False from the
	-- moment a quiz lesson is created until Classroom.TrySit succeeds for them -- see
	-- the note on Config.School.Classroom for why this exists at all. No question is
	-- asked, no clock runs and nothing is pushed but the room itself while this is
	-- false; the lesson is otherwise fully formed (questions drawn, order not yet
	-- shuffled) so sitting down has nothing left to wait on.
	seated: boolean,
}

local lessons: { [Player]: Lesson } = {}

-- The last thing pushed to each player, so an unchanged state is not re-sent four
-- times a second. Same reason WorkService keeps one: the HUD row is redrawn on
-- receipt, and a row that redraws every tick cannot be read.
local pushed: { [Player]: string } = {}

-- A notice with no lesson behind it -- a refusal at the door, or the summary of a
-- lesson that has just ended -- and how long is left of it. Held separately from
-- `lessons` precisely because it outlives the lesson: the closing line has to stay up
-- for a beat after everything else about the lesson is gone.
type Notice = { text: string, good: boolean, secondsLeft: number }
local notices: { [Player]: Notice } = {}

-- A player standing at the school with a subject they have already finished with, being
-- asked whether they want to sit it anyway.
--
-- This is the whole of what mastery buys, and it is deliberately a *question* rather
-- than an automatic pass. A subject that silently stopped happening once you were good
-- at it would read as the game running out of content; being asked, every time, is what
-- makes it a thing you achieved. It also leaves the door open to sitting it anyway,
-- which a player chasing the last few points of smarts has a real reason to do.
--
-- Held per player rather than on the lesson because there is no lesson yet -- that is
-- the point of it. Cleared the moment the player answers or walks away, so the panel is
-- never up for a building they are not standing in.
type Door = { subjectId: string }
local doors: { [Player]: Door } = {}

-- Whether this player is currently being shown their report card.
--
-- The card itself is on the profile -- see LifeData.pendingReport -- and this is only
-- whether it is in their hands right now. Two separate things on purpose: the card
-- survives a birthday, a logout and a rejoin, and being at the school does not.
--
-- Held per player for the reason the door is, and read the same way: set when they arrive
-- at the pad, cleared when they walk off or press the button. Keeping the geometry out
-- here rather than in the composer means the card can be built from a profile alone,
-- which is what makes the harness command able to print one.
local cards: { [Player]: boolean } = {}


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
	return data.ageMonths // Config.Time.MonthsPerYear
end

-- A subject's name for a sentence, falling back to its id. The fallback is the case
-- that matters: a saved life can hold mastery in a subject that has since been taken off
-- the timetable, and a report card reading "you finished with woodwork" is better than
-- one that errors or silently drops the row.
local function subjectNameOf(subjectId: string): string
	local subject = Curriculum.Get(subjectId)
	return if subject ~= nil then subject.name else subjectId
end

-- What is on in a given slot of a given year, from 1. The timetable itself, and the one
-- place the rotation is worked out.
--
-- Rotated rather than rolled, and the difference matters over a childhood: three random
-- draws a year from six subjects will hand a player the same one twice in a term and skip
-- another for four years, and a timetable that behaves like that is not a timetable. Keyed
-- on the age and the slot, so it walks the list evenly and every subject comes round -- and
-- so the same year lived twice in a test gives the same subjects, which is worth a great
-- deal when the thing being tested is one of them.
--
-- Asked about a slot rather than about "now" because the report card has to name the
-- subject in a slot the player never turned up for. A year with an empty second period is
-- reported as "Music, absent" rather than as a blank, and that is only possible because
-- the timetable is a function of the year rather than a record of what happened.
--
-- Nil only if a whole school year has no subject in it, which content/Curriculum.luau
-- refuses to load with. Handled anyway rather than assumed, because the check that makes
-- it impossible lives in another file and could be relaxed there.
local function subjectForSlot(ageYears: number, slot: number): SchoolSubject?
	local list = Curriculum.ForAge(ageYears)
	if #list == 0 then
		return nil
	end
	local turn = ageYears * SCHOOL.LessonsPerYear + (slot - 1)
	return list[turn % #list + 1]
end

-- The teacher in the classroom. One per player with a lesson, built from the
-- `teacher` subject so it reuses the same rig path as every animal in the game.
-- It is a smaller SceneService: walk in, stand facing the player, do whatever the
-- last answer said it did, and hold that pose -- but it belongs to the lesson
-- rather than to an event, so it lives here next to the loop that grades answers.
-- The gesture the teacher performs is set by answer() and read by the run loop,
-- which is the one channel of communication the two halves of this file need.
type Teacher = {
	rig: SubjectRig,
	motion: Motion,
	-- The point it is standing on this frame, which moves when a wrong answer
	-- makes it step back and comes home when it re-centres.
	at: Vector3,
	-- The front-of-room spot it belongs on between answers, which is also where a
	-- re-centre is heading.
	front: Vector3,
	-- Where it walks in from, so the walk-out can retrace it if there were one.
	-- (There is not: the teacher is despawned rather than walked away, because
	-- nobody watches a classroom empty out.)
	spawn: Vector3,
	heading: number,
	-- Ground covered and time since spawn, keyed the same way the animal gait is
	-- keyed -- traveled for the walk, elapsed for everything done standing still.
	travelled: number,
	startedAt: number,
	-- What the last answer called for, read once and cleared by the run loop.
	-- "right" is a bow, "wrong" is a step back, "settle" is a calm nod, and
	-- "approach" is a step toward the player before bowing. Nil when the loop
	-- is idling.
	gesture: "right" | "wrong" | "settle" | "approach"?,
	-- Set by despawnTeacher(); every wait below checks it before touching the rig,
	-- because the model may be gone by the time the loop next wakes.
	cancelled: boolean,
}
local teachers: { [Player]: Teacher } = {}

-- Everything school puts in the world lives in one folder, so a Studio session can see
-- at a glance what is standing and clear the lot if a test left something behind.
--
-- Declared up here rather than down beside `buildRoom`, which is the only place it reads
-- like it belongs, because `spawnTeacher` calls it and `spawnTeacher` is defined above
-- that point. Lua resolves names at compile time: a call written above the `local function`
-- that defines it does not see the local at all, it compiles to a *global* lookup and
-- returns nil. Nothing catches that -- it is legal Luau, so `luau-compile` passes, and
-- `rojo build` never parses the file -- and the symptom is not a load error but every
-- lesson in the game dying on "attempt to call a nil value" the first time a teacher spawns.
local function schoolFolder(): Folder
	local existing = workspace:FindFirstChild("SchoolPads")
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "SchoolPads"
	folder.Parent = workspace
	return folder
end

-- Facing and floor helpers, kept local to this file because the teacher only ever
-- walks straight lines and turns toward a player. Three are the same three
-- SceneService uses, copied small because the teacher never needs the scene's
-- arc-search -- its spot is computed once, opposite the player from the room.
local MIN_DIRECTION = 1e-3

local function flatten(direction: Vector3): Vector3?
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < MIN_DIRECTION then
		return nil
	end
	return flat.Unit
end

local function headingTo(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

local function poseAt(at: Vector3, heading: number): CFrame
	return CFrame.new(at) * CFrame.Angles(0, heading, 0)
end

-- Hands one frame to the teacher's motion. Present so every call site passes the
-- same four things, and so a new field on the pose is added in one place.
local function presentTeacher(teacher: Teacher, root: CFrame, moving: boolean, turning: number, settled: boolean)
	teacher.motion.apply({
		root = root,
		traveled = teacher.travelled,
		elapsed = os.clock() - teacher.startedAt,
		moving = moving,
		turning = turning,
		settled = settled,
	})
end

-- Walks the teacher between two floor points at its own pace, facing the way it is
-- going. Returns false if the loop was cancelled part-way, which means the model is
-- already gone and the caller must not touch it again.
local function travelTeacher(teacher: Teacher, from: Vector3, to: Vector3): boolean
	local direction = flatten(to - from)
	local distance = (to - from).Magnitude
	if direction == nil or distance < MIN_DIRECTION then
		return true
	end

	local heading = headingTo(direction)
	local covered = 0
	while covered < distance do
		local delta = RunService.Heartbeat:Wait()
		if teacher.cancelled then
			return false
		end
		local step = math.min(distance - covered, teacher.rig.subject.walkSpeed * delta)
		covered += step
		teacher.travelled += step
		presentTeacher(teacher, poseAt(from:Lerp(to, covered / distance), heading), true, 0, false)
	end
	teacher.at = to
	return true
end

-- One frame of standing still: eases the facing round toward the player and hands
-- the frame over, the same tracking SceneService does for a subject -- a teacher
-- that follows you perfectly is a turret, and one that never turns is a statue.
local function standTeacher(player: Player, teacher: Teacher, settled: boolean): number
	local heading = teacher.heading
	local remaining = 0
	local character = player.Character
	if character ~= nil then
		local target = flatten(character:GetPivot().Position - teacher.at)
		if target ~= nil then
			local desired = headingTo(target)
			remaining = (desired - heading + math.pi) % (2 * math.pi) - math.pi
			heading += remaining * Config.Scene.TurnResponsiveness
		end
	end
	presentTeacher(teacher, poseAt(teacher.at, heading), false, remaining, settled)
	return heading
end

-- Stands facing the player for a while, easing the turn on every frame.
local function holdTeacher(player: Player, teacher: Teacher, seconds: number, settled: boolean)
	local waited = 0
	while waited < seconds do
		local delta = RunService.Heartbeat:Wait()
		if teacher.cancelled then
			return
		end
		waited += delta
		teacher.heading = standTeacher(player, teacher, settled)
	end
end

-- The teacher's whole classroom life: walk in, then idle facing the player, doing
-- whatever each answer asks of it. Deliberately a much smaller loop than a
-- SceneService scene -- the teacher has no arc to place in and no walk-out to
-- retrace, because it is despawned rather than sent away.
local function runTeacher(player: Player, teacher: Teacher)
	if not travelTeacher(teacher, teacher.spawn, teacher.front) then
		return
	end

	while true do
		local delta = RunService.Heartbeat:Wait()
		if teacher.cancelled then
			return
		end

		local gesture = teacher.gesture
		if gesture ~= nil then
			teacher.gesture = nil
			if gesture == "right" then
				-- A bow, held a beat, then eased back up. The motion owns how long
				-- getting up takes, so the motion is asked -- the same rule as an
				-- animal getting back to its feet after lying down.
				holdTeacher(player, teacher, SCHOOL.TeacherNodSeconds, true)
				if teacher.cancelled then
					return
				end
				holdTeacher(player, teacher, SubjectMotion.SettleSeconds, false)
			elseif gesture == "settle" then
				-- A calm nod: shorter than a full bow, for questions that were
				-- merely correct rather than genuinely earned.
				holdTeacher(player, teacher, SCHOOL.TeacherNodSeconds * 0.5, true)
				if teacher.cancelled then
					return
				end
				holdTeacher(player, teacher, SubjectMotion.SettleSeconds, false)
			elseif gesture == "approach" then
				-- A step toward the player, a bow, then back to the front. The
				-- mirror of "wrong" but in the other direction: the teacher
				-- closes distance for the ones that were genuinely earned.
				local playerPos = characterPosition(player)
				local toward = if playerPos ~= nil then flatten(playerPos - teacher.at) else nil
				if toward ~= nil then
					local closer = teacher.at + toward * SCHOOL.TeacherBackStuds
					if not travelTeacher(teacher, teacher.at, closer) then
						return
					end
					holdTeacher(player, teacher, SCHOOL.TeacherNodSeconds, true)
					if teacher.cancelled then
						return
					end
					if not travelTeacher(teacher, teacher.at, teacher.front) then
						return
					end
					holdTeacher(player, teacher, SubjectMotion.SettleSeconds, false)
				end
			elseif gesture == "wrong" then
				-- A step back: away from the player, a beat standing there, then
				-- back to the front. The step is what makes a wrong answer land in
				-- the room rather than as a sentence on a panel.
				local playerPos = characterPosition(player)
				local toward = if playerPos ~= nil then flatten(playerPos - teacher.at) else nil
				if toward ~= nil then
					local back = teacher.at - toward * SCHOOL.TeacherBackStuds
					if not travelTeacher(teacher, teacher.at, back) then
						return
					end
					holdTeacher(player, teacher, SCHOOL.TeacherBackHoldSeconds, false)
					if teacher.cancelled then
						return
					end
					travelTeacher(teacher, teacher.at, teacher.front)
				end
			end
			if teacher.cancelled then
				return
			end
		end

		teacher.heading = standTeacher(player, teacher, false)
	end
end

-- Finds the teacher a spot ahead of the player where they are facing, walks the rig
-- up to the front, and starts its loop. Best-effort in exactly the sense the scene
-- placement is: a room with nowhere for the teacher is an ordinary outcome, and the
-- lesson plays exactly as it did before teachers existed.
--
-- Anchored to the player's facing rather than to the room centre, because the player
-- steps onto the room centre to start the lesson -- the direction from room to player
-- is the one direction that tells you nothing about where a teacher should stand.
local function spawnTeacher(player: Player): boolean
	if not SCHOOL.TeacherEnabled then
		return false
	end
	local subject = Subjects.ById["teacher"]
	local character = player.Character
	local position = characterPosition(player)
	if subject == nil or character == nil or position == nil then
		return false
	end

	local direction = flatten(character:GetPivot().LookVector)
	if direction == nil then
		return false
	end

	local ignore = Ground.IgnoreList()
	local teacherRadius = math.max(subject.bodyLength, subject.bodyWidth) / 2
	local teacherHeight = subject.shoulderHeight
	local playerHeight = Ground.BodyHeight(character)

	local front = position + direction * SCHOOL.TeacherFrontStuds
	local spawn = front + direction * SCHOOL.TeacherWalkInStuds

	-- Where the teacher ends up and where they walk in from, both probed at the
	-- teacher's own size rather than the player's -- an adult standing in a classroom is
	-- a different footprint from a child sitting in one.
	--
	-- Neither is checked for a line to the other, and that is the behavior this has
	-- always had rather than an oversight in passing: the walk in is pathfound, so a
	-- teacher who has to come round a doorway is a teacher coming round a doorway, and a
	-- straight-line test would refuse the room for a corner the walk handles fine.
	local frontFloor = Ground.SpotAt(front, teacherRadius, teacherHeight, ignore)
	local spawnFloor = Ground.SpotAt(spawn, teacherRadius, teacherHeight, ignore)
	if frontFloor == nil or spawnFloor == nil then
		return false
	end
	-- The *player* has to be able to see it, measured at the player's height. Separate
	-- from the two above because it is a different question about a different body, and
	-- it is the one that decides whether the lesson happens in the room or on a panel.
	if not Ground.Reachable(position, frontFloor, playerHeight, ignore) then
		return false
	end

	local rig = SubjectModels.Build(subject)
	rig.model.Parent = schoolFolder()
	local motion = SubjectMotion.Attach(rig)

	local heading = headingTo(front - spawn)
	rig.model:PivotTo(poseAt(spawnFloor, heading))

	local teacher: Teacher = {
		rig = rig,
		motion = motion,
		at = spawnFloor,
		front = frontFloor,
		spawn = spawnFloor,
		heading = heading,
		travelled = 0,
		startedAt = os.clock(),
		gesture = nil,
		cancelled = false,
	}
	teachers[player] = teacher
	task.spawn(runTeacher, player, teacher)
	return true
end

-- Ends the teacher's presence immediately. Everything that despawns it goes through
-- here, because the model must never be destroyed from inside its own loop -- the
-- cancelled flag is set first and the loop checks it at every wait, which is the one
-- thing that keeps a destroyed model from being posed again.
local function despawnTeacher(player: Player)
	local teacher = teachers[player]
	if teacher == nil then
		return
	end
	teachers[player] = nil
	teacher.cancelled = true
	teacher.motion.stop()
	teacher.rig.model:Destroy()
end

-- The classmates standing near the door. Pure world dressing: nothing here is keyed by
-- player, nothing here is ever despawned, and nothing here tracks the player the way the
-- teacher does -- it is a small huddle that stands at the school for the life of the
-- server, the same permanence as the sign and the pad. Kept as its own list rather than
-- folded into `teachers` because the two have almost nothing in common once you take the
-- rig away: one is per-player lesson state, the other is scenery.
type Classmate = {
	rig: SubjectRig,
	motion: Motion,
	at: Vector3,
	heading: number,
	startedAt: number,
}
local classmates: { Classmate } = {}

-- Stands a small group of classmate rigs on a ring around the door point, facing in
-- toward it so they read as gathered at the school rather than facing out at nothing.
-- Best-effort exactly like spawnTeacher: a door with nowhere for the group to stand
-- plays exactly as it did before they existed, one at a time per bearing rather than
-- refusing the whole group over one blocked angle.
local function spawnClassmates(at: Vector3)
	local CLASSMATES = SCHOOL.Classmates
	local ids = { "classmate1", "classmate2", "classmate3" }
	local ignore = Ground.IgnoreList()
	local radius = Config.NPC.BodyRadius
	local height = Config.NPC.BodyHeight
	local taken: { Vector3 } = {}

	local placed = 0
	for _, bearing in Ground.Bearings(360, CLASSMATES.Bearings) do
		if placed >= CLASSMATES.Count then
			break
		end

		local direction = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(-bearing)) * Vector3.new(0, 0, -1)
		local candidate = at + direction * CLASSMATES.RingStuds

		-- No reachability test, on the same reasoning PeopleService.spotFor gives for a
		-- townsperson's own ring: this group is not walking to the door, it is already
		-- standing there when the world loads.
		local floor = Ground.SpotAt(candidate, radius, height, ignore)
		if floor == nil then
			continue
		end
		if not Ground.Apart(floor, taken, radius * 2) then
			continue
		end
		table.insert(taken, floor)
		placed += 1

		local subject = Subjects.ById[ids[placed]]
		if subject == nil then
			continue
		end

		local rig = SubjectModels.Build(subject)
		rig.model.Parent = schoolFolder()
		local motion = SubjectMotion.Attach(rig)

		local heading = headingTo(at - floor)
		rig.model:PivotTo(poseAt(floor, heading))

		local classmate: Classmate = {
			rig = rig,
			motion = motion,
			at = floor,
			heading = heading,
			startedAt = os.clock(),
		}
		table.insert(classmates, classmate)

		-- Idling forever rather than for a lesson's length. `SubjectMotion`'s posed idle
		-- already supplies the breathing and head drift that make a stationary biped read
		-- as alive rather than propped up -- see SubjectMotion.luau -- so there is nothing
		-- else this loop needs to do.
		task.spawn(function()
			while true do
				RunService.Heartbeat:Wait()
				classmate.motion.apply({
					root = poseAt(classmate.at, classmate.heading),
					traveled = 0,
					elapsed = os.clock() - classmate.startedAt,
					moving = false,
					turning = 0,
					settled = false,
				})
			end
		end)
	end
end

-- Whether the room has been furnished yet. Built lazily rather than at Start, because
-- the place point may stream in after the server does -- and a school that only exists
-- if the building happened to be loaded at boot is a school that is missing on exactly
-- the runs where it matters.
local roomBuilt = false
local attendAt: Vector3? = nil

-- Studio harness switch. Off means no lesson can start and any in progress is ended,
-- which is what makes it possible to test the shift loop in a world that also has a
-- school in it without walking past the door and being pulled into a lesson.
local enabled = true

-- The sign over the door and the pad under it. Shared, built once, and never taken
-- down -- the two things in this system that belong to the building rather than to a
-- player.
--
-- The pad is deliberately still gold and still there for somebody who has used up
-- their lessons for the year. A hiring post has to disappear once you take the job,
-- because an offer that has been accepted is no longer an offer; a school door is not
-- an offer, and a door that vanishes when you are done for the year would read as the
-- building having gone. Stepping on it out of hours gets you a reason instead.
local function buildRoom(): boolean
	if roomBuilt then
		return attendAt ~= nil
	end

	local place = PlaceService.Find(PLACE_ID)
	if place == nil then
		-- Already warned once by PlaceService, and warning again per tick would bury
		-- the rest of the log. Retried on the next tick rather than given up on, in
		-- case the building is still streaming in.
		return false
	end

	roomBuilt = true
	local folder = schoolFolder()
	local at = place.part.Position

	local sign = Instance.new("BillboardGui")
	sign.Name = "SchoolSign"
	sign.Adornee = place.part
	sign.Size = UDim2.new(12, 0, 2.4, 0)
	sign.StudsOffsetWorldSpace = Vector3.new(0, Config.Work.Hiring.SignLiftStuds, 0)
	-- Read from down the street to decide whether to walk over, not once you have
	-- arrived -- the same job the hiring signs do, so it borrows their distance rather
	-- than inventing a second number that would drift away from it.
	sign.MaxDistance = Config.Work.Hiring.SignMaxDistanceStuds
	sign.AlwaysOnTop = true
	sign.Parent = place.part

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.62, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 250, 240)
	title.Text = "SCHOOL"
	title.Parent = sign

	local terms = Instance.new("TextLabel")
	terms.Name = "Terms"
	terms.Size = UDim2.new(1, 0, 0.38, 0)
	terms.Position = UDim2.new(0, 0, 0.62, 0)
	terms.BackgroundTransparency = 1
	terms.Font = Enum.Font.GothamMedium
	terms.TextScaled = true
	terms.TextColor3 = Color3.fromRGB(245, 205, 120)
	-- States its terms and lets you work out whether you meet them, exactly as the
	-- hiring signs do. A sign that told a five-year-old they were too young would be
	-- the building talking about the reader rather than about itself.
	terms.Text = `Lessons for ages {SCHOOL.StartAge} to {SCHOOL.EndAge}`
	terms.Parent = sign

	-- The handle is deliberately dropped. Everything a ChoiceMarker hands back is for a
	-- marker that comes down again -- somewhere to read its position from, a pulse to
	-- cancel, a pad to destroy -- and this one never does. Holding a reference would
	-- only imply there is a case where the school closes.
	ChoiceMarkers.Build(folder, at, Config.Work.Hiring.PadRadiusStuds, {
		label = "Go to class",
		locked = false,
	})
	attendAt = at

	-- A few other kids at the door. See spawnClassmates for why this is scenery rather
	-- than lesson state, and Config.School.Classmates for the numbers.
	spawnClassmates(at)

	-- The lab goes up with the school, but around its own point (LAB_PLACE_ID above) and
	-- not the front door -- the school grew past a building small enough for one centre
	-- to serve both, and a lab built around the forecourt now lands outside the room
	-- SCHOOL_SCIENCE was measured for. Built here rather than lazily on the first
	-- Science lesson so that a Studio session can see the benches standing the moment
	-- the world loads -- a room that only appears once somebody is nine is a room nobody
	-- can check.
	--
	-- Best effort, and a failure is not a failure of school: Lab.Build refusing means
	-- Science refuses at the door with a reason, and every other subject carries on. A
	-- missing science_lab point is the same kind of best-effort failure as a floor
	-- Lab.Build itself refuses, so it is logged and swallowed the same way rather than
	-- taking buildRoom's own success down with it -- the classroom, cafeteria and pad
	-- above have already gone up by this point and should stay up.
	local labPlace = PlaceService.Find(LAB_PLACE_ID)
	if labPlace ~= nil then
		Lab.Build(labPlace.part.Position)
	else
		warn(`SchoolService: no part tagged "{LAB_PLACE_ID}" -- the science lab has no room to build in`)
	end

	-- And the art room, for the same reasons in the same order -- a room in the same
	-- building, standing before anybody is old enough to be sent to it, and free to fail
	-- on its own without taking the rest of the timetable down with it. Laid around the
	-- same point as the lab and much wider than it, which is deliberate: see
	-- Config.School.Art.RoomRadiusStuds for why the walk from the easel to the paint
	-- cupboard has to cost real seconds.
	Studio.Build(at)

	-- And the classroom, same point, same best-effort rule. A quiz refuses at the door
	-- if this comes back nil -- see beginLesson's fallthrough -- exactly the way Science
	-- already refuses when the lab has nowhere to stand a station.
	Classroom.Build(at)

	return true
end

local function destroyDiscs(lesson: Lesson)
	local discs = lesson.discs
	if discs == nil then
		return
	end
	for _, disc in discs do
		disc.marker.destroy()
	end
	lesson.discs = nil
end

-- One floor disc per answer, fanned around the player so the question is answered
-- by walking. Reuses the same Ground probes EnactService and the workplace run
-- before they put anything on a floor: the disc has to have floor under it, a
-- body-sized gap to stand in, and a straight walk from where the player is.
-- Err on rejecting -- the cost of rejecting is a panel question, and the cost
-- of accepting is a disc half in a wall.
local function placeDiscs(lesson: Lesson, player: Player): boolean
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	local center = root.Position

	local ignore = Ground.IgnoreList()
	local radius = Ground.BodyRadius(character)
	local height = Ground.BodyHeight(character)

	local count = #lesson.order
	if count < 2 then
		return false
	end

	-- Scattered like WorkSpots so the same question at the same spot does not fan
	-- its discs into the same corners every time.
	local bearings = Ground.ScatteredBearings(SCHOOL.DiscArcDegrees, count)

	local placed: { Disc } = {}
	-- The points of `placed`, kept alongside it because `Apart` takes positions and a
	-- disc is more than one. Appended to at the same moment as `placed` below, and the
	-- pair only stays honest because there is exactly one place either is added to.
	local takenSpots: { Vector3 } = {}
	for row, bearing in bearings do
		local direction = CFrame.Angles(0, math.rad(bearing), 0) * Vector3.new(0, 0, -1)
		local spot: Vector3? = nil
		for _, step in { 1, 1.5, 2 } do
			local candidate = center + direction * (SCHOOL.DiscDistanceStuds * step)

			local floor = Ground.SpotAt(candidate, radius, height, ignore, center)
			if floor == nil then
				continue
			end
			if not Ground.Apart(floor, takenSpots, SCHOOL.DiscReachStuds * 2 + 1) then
				continue
			end

			spot = floor
			break
		end
		if spot == nil then
			-- The floor refused a disc, so the whole question falls back to the
			-- panel. Any discs already placed come down with it: a question is asked
			-- one way or the other, never half over a fan and half over a row.
			for _, disc in placed do
				disc.marker.destroy()
			end
			lesson.discs = nil
			return false
		end

		table.insert(takenSpots, spot)
		table.insert(placed, {
			at = spot,
			marker = ChoiceMarkers.Build(schoolFolder(), spot, SCHOOL.DiscReachStuds, {
				label = lesson.questions[lesson.index].answers[lesson.order[row]],
				locked = false,
			}),
		})
	end

	lesson.discs = placed
	return true
end

-- The rows to put in front of the player, in the shuffled order, or empty while there
-- is nothing to answer -- the beat the teacher's line is up, and the moment a lesson
-- has ended. Empty is what closes the panel, so this being right is what stops a
-- question standing open over the explanation of the last one.
local function rowsFor(lesson: Lesson): { OfferedChoice }
	local rows: { OfferedChoice } = {}
	if lesson.verdictLeft > 0 or lesson.index > #lesson.questions then
		return rows
	end
	local question = lesson.questions[lesson.index]
	for row, answerIndex in lesson.order do
		-- Numbered by position on the panel rather than by which answer it is. The
		-- client is never told which of the authored answers it is looking at, so a
		-- client reading its own traffic learns the order it was already shown and
		-- nothing else.
		table.insert(rows, { id = tostring(row), label = question.answers[answerIndex], cost = nil, locked = lesson.discs ~= nil })
	end
	return rows
end

local function stateFor(player: Player): LessonState?
	local lesson = lessons[player]
	-- Seated is checked here, not just at creation: an unseated lesson has no shuffled
	-- order and a stale secondsLeft, neither of which askCurrent has touched yet, so
	-- returning question-state for it would draw a question nobody chose an order for
	-- and a clock that was never started. Falls through to the notice below instead.
	if lesson ~= nil and lesson.seated and lesson.index <= #lesson.questions then
		local question = lesson.questions[lesson.index]
		return {
			ask = question.ask,
			answers = rowsFor(lesson),
			index = lesson.index,
			count = #lesson.questions,
			right = lesson.right,
			secondsLeft = math.max(0, lesson.secondsLeft),
			secondsTotal = SCHOOL.SecondsPerQuestion,
			verdict = lesson.verdictText,
			wasRight = lesson.verdictRight,
			physical = lesson.discs ~= nil,
		}
	end

	-- The skip offer. Rendered as a lesson state with two answers and no clock, because
	-- it is the same panel asking the same shape of question and inventing a second
	-- remote for it would be a second surface to keep in step. Index zero is what marks
	-- it out from a real question: a lesson counts from one, so an answer coming back
	-- against zero can only be this.
	local door = doors[player]
	if door ~= nil then
		local name = subjectNameOf(door.subjectId)
		return {
			ask = `{name} today, and you have finished with it.`,
			answers = {
				-- The costs are in the notes rather than the labels, so the two payouts sit
				-- in one column and can be read against each other at a glance. That
				-- comparison is the entire decision.
				{
					id = "sit",
					label = "Sit the lesson anyway",
					cost = nil,
					note = `up to +{SCHOOL.SmartsPerGoodLesson} smarts`,
					locked = false,
				},
				{
					id = "skip",
					label = "Skip it",
					cost = nil,
					note = `+{Report.SmartsFor(Report.Skipped)} smarts, no lesson`,
					locked = false,
				},
			},
			index = 0,
			count = 0,
			right = 0,
			secondsLeft = 0,
			secondsTotal = 0,
			verdict = nil,
			wasRight = false,
			physical = false,
		}
	end

	local notice = notices[player]
	if notice ~= nil then
		return {
			ask = "School",
			-- Nothing to answer, which is also what tells the client to close whatever
			-- panel it has open: this is a message, not a question.
			answers = {},
			-- Zeroes throughout: this is a message, not a position in a lesson, and the
			-- client reads a zero total as "draw no clock". See the type.
			index = 0,
			count = 0,
			right = 0,
			secondsLeft = 0,
			secondsTotal = 0,
			verdict = notice.text,
			wasRight = notice.good,
		}
	end

	return nil
end

local function push(player: Player)
	local state = stateFor(player)
	-- A digest rather than a deep compare, and it has to name every field that is
	-- drawn: a state whose only change is the second on the clock must still be sent,
	-- and one whose only change is nothing at all must not.
	local digest = if state == nil
		then "none"
		else `{state.ask}|{state.index}/{state.count}|{state.right}|{math.floor(state.secondsLeft * 4)}|`
			.. `{tostring(state.verdict)}|{tostring(state.wasRight)}|{#state.answers}|{tostring(state.physical)}`
	if pushed[player] == digest then
		return
	end
	pushed[player] = digest
	LessonUpdatedRemote:FireClient(player, state)
end

-- A line with no lesson behind it. Replaces whatever was showing, because the newest
-- thing the school has to say is always the one worth reading.
local function notice(player: Player, text: string, good: boolean)
	notices[player] = { text = text, good = good, secondsLeft = SCHOOL.VerdictSeconds }
	push(player)
end

-- The line that says what this life is closest to finishing, or nil when nothing is
-- close. Only ever about the subjects on the current timetable: a rung in a subject that
-- will not be taught for another three years is not a near miss, it is trivia.
--
-- One line and only when it is true, which is the whole discipline of it. A card that
-- printed "keep going!" every year would be a card nobody read the bottom of by twelve.
local function nearMissFor(data: LifeData): string?
	-- A ladder that promotes on a single pass has no "one away" to be -- everybody not
	-- topped out is always one away -- and the line would be on every card forever.
	if Mastery.PassesPerLevel <= 1 then
		return nil
	end

	for _, subject in Curriculum.ForAge(ageYearsOf(data)) do
		if not Mastery.IsTopped(data, subject.id) and Mastery.PassesOf(data, subject.id) == Mastery.PassesPerLevel - 1 then
			-- Not named `next`: that is a Lua global, and shadowing it here is legal,
			-- silent, and exactly the sort of thing that surprises somebody later.
			local rung = Mastery.LevelOf(data, subject.id) + 1
			if rung >= Mastery.Levels then
				-- The only near miss that changes what the player can *do*, so it says so
				-- rather than naming the rung. A number is a smaller thing to be told than
				-- an afternoon back.
				return `One more good {subject.name} lesson finishes it for good.`
			end
			return `One more good {subject.name} lesson makes it level {rung}.`
		end
	end
	return nil
end

-- Everything this life's school years came to, counted. Counted rather than listed
-- year by year: by seventeen a list is twelve entries of muted text nobody reads to the
-- end, and what a record actually says is "three good years and two thrown away".
local function recordLineFor(data: LifeData): string?
	local parts: { string } = {}
	for _, entry in Report.Tally(data) do
		local years = if entry.years == 1 then "1 year" else `{entry.years} years`
		table.insert(parts, `{years} {entry.grade}`)
	end
	if #parts == 0 then
		return nil
	end
	return `School so far: {table.concat(parts, ", ")}.`
end

-- Composes a staged card into the thing the player reads.
--
-- Takes the report rather than reading it off the profile, so the harness can print a
-- card for a year without one having to be staged -- and so this function has no way to
-- accidentally hand over a card that is not the one being asked about.
local function buildCard(data: LifeData, report: SchoolYearRecord): ReportCard
	local rows: { OfferedChoice } = {}

	-- Every slot of the year, not every lesson sat. The empty ones are most of what a bad
	-- year's card has to say, and naming the subject that was on -- which the timetable can
	-- still answer for a year that is over -- is the difference between "you missed a
	-- lesson" and "you missed Music".
	local slots = math.max(SCHOOL.LessonsPerYear, #report.lessons)
	for slot = 1, slots do
		local lesson = report.lessons[slot]
		if lesson == nil then
			local subject = subjectForSlot(report.ageYears, slot)
			local name = if subject ~= nil then subject.name else "Nothing"
			table.insert(rows, {
				id = `slot{slot}`,
				label = `{name} — {Report.AbsentWord}`,
				cost = nil,
				-- An em dash rather than "0 smarts". Nothing happened, and a zero in the
				-- column where every other row has a payout reads as a lesson that paid
				-- badly rather than as one that never took place.
				note = "—",
				locked = true,
			})
		else
			-- The stored subject wins over the timetable's for a slot that was actually
			-- sat. They agree today; they would not for a life saved before a subject was
			-- moved, and what happened beats what was scheduled.
			local label = `{subjectNameOf(lesson.subjectId)} — {Report.WordFor(lesson.band)}`
			if lesson.level ~= nil then
				label ..= `, level {lesson.level} of {Mastery.Levels}`
			end
			table.insert(rows, {
				id = `slot{slot}`,
				label = label,
				cost = nil,
				note = if lesson.smarts > 0 then `+{lesson.smarts} smarts` else "no smarts",
				locked = true,
			})
		end
	end

	-- The one row that is not locked, and the only thing on the card that can be pressed.
	-- The client does not read this id -- there is nothing else to press, so it fires the
	-- acknowledgement whatever comes back -- but it is named rather than blank because a
	-- row with no id is a row nothing can be said about in a log.
	table.insert(rows, { id = "read", label = "Continue", cost = nil, note = nil, locked = false })

	local footnotes: { string } = {}
	local near = nearMissFor(data)
	if near ~= nil then
		table.insert(footnotes, near)
	end
	local record = recordLineFor(data)
	if record ~= nil then
		table.insert(footnotes, record)
	end

	return {
		ageYears = report.ageYears,
		title = `Age {report.ageYears} report card: {report.grade}`,
		rows = rows,
		footnote = table.concat(footnotes, "\n"),
	}
end

-- The card in this player's hands right now, or nil. Both halves have to be true: one
-- staged on the profile, and the player standing where it is handed over.
local function cardFor(player: Player): ReportCard?
	if not cards[player] then
		return nil
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	local data = Lives.Active(profile.Data)
	local report = data.pendingReport
	if report == nil then
		return nil
	end
	return buildCard(data, report)
end

-- The last card pushed to each player, so the panel is not rebuilt four times a second
-- under somebody standing still reading it. Only the age is digested because a card is
-- immutable once staged: the year it reports is over, and nothing that could change a row
-- can happen without a birthday replacing the whole card anyway.
local pushedCards: { [Player]: string } = {}

local function pushCard(player: Player)
	local card = cardFor(player)
	local digest = if card == nil then "none" else `card:{card.ageYears}`
	if pushedCards[player] == digest then
		return
	end
	pushedCards[player] = digest
	ReportCardUpdatedRemote:FireClient(player, card)
end

-- Why this player cannot sit a lesson right now, or nil if they can. Written as the
-- sentence the player reads, because there is exactly one caller and a reason code
-- would only ever be turned back into this string.
local function refusalFor(data: LifeData): string?
	if not enabled then
		return "School is closed."
	end
	if not data.alive then
		return "School is closed."
	end

	local age = ageYearsOf(data)
	if age < SCHOOL.StartAge then
		return `You start school at {SCHOOL.StartAge}.`
	end
	if age > SCHOOL.EndAge then
		return "You are done with school."
	end
	if data.lessonsThisYear >= SCHOOL.LessonsPerYear then
		return `You have had your {SCHOOL.LessonsPerYear} lessons this year. Come back next year.`
	end

	return nil
end

-- Puts whichever question is now current in front of the player. When physical
-- lessons are enabled the answers go down as discs on the classroom floor and the
-- panel rows arrive locked; when the floor refuses discs or the switch is off the
-- panel rows are the answer, as before.
local function askCurrent(lesson: Lesson, player: Player)
	destroyDiscs(lesson)

	local question = lesson.questions[lesson.index]

	-- Shuffled per question, and the shuffle is on the *order* rather than on the
	-- answers themselves, so `correct` keeps meaning what the content file said it
	-- meant. Shuffling a copy of the answers and re-finding the right one by string
	-- match would break the moment two questions shared an answer.
	local order: { number } = {}
	for index = 1, #question.answers do
		table.insert(order, index)
	end
	for index = #order, 2, -1 do
		local swap = math.random(index)
		order[index], order[swap] = order[swap], order[index]
	end

	lesson.order = order
	lesson.secondsLeft = SCHOOL.SecondsPerQuestion
	lesson.verdictLeft = 0
	lesson.verdictText = nil
	lesson.verdictRight = false

	if SCHOOL.PhysicalLessons then
		placeDiscs(lesson, player)
	end
end

-- Ends the lesson and grades it. `reason` is why it stopped, and it changes the
-- sentence but never the arithmetic: a lesson walked out of halfway through is graded
-- on all of its questions, not on the ones that were reached. Leaving early is a way
-- of getting them wrong.
local function finish(player: Player, data: LifeData, lesson: Lesson, reason: string)
	destroyDiscs(lesson)
	despawnTeacher(player)
	-- Frees the desk. Harmless to call when the player was never seated at all --
	-- StandUp only ever acts on a humanoid that is actually sitting -- so this does not
	-- need its own guard for the door-refusal paths that route through here unseated.
	Classroom.StandUp(player)
	lessons[player] = nil

	local count = #lesson.questions
	local share = if count > 0 then lesson.right / count else 0

	-- Which band and what it pays both come from school/Report rather than from an
	-- if-chain here. ScienceService had a byte-identical copy of that chain, and two
	-- copies of "what counts as a good afternoon" is how a report card ends up disagreeing
	-- with the closing line the player just read.
	local band = Report.BandFor(share)
	local gained = Report.SmartsFor(band)

	if gained ~= 0 then
		StatService.AddStat(player, "smarts", gained)
	end

	-- Counted however it ended, including walked out of. Turning up is what the year's
	-- cap is counting, and a player who could start a lesson, leave, and start another
	-- would be able to re-roll the questions until they got an easy five.
	data.lessonsThisYear += 1
	-- Showing up for school earns the right to be interrupted by the world. The
	-- counter is per-year, but the autonomy gate is per-chapter, so the points
	-- bank across the whole band and do not reset at the year line.
	EventService.AwardAutonomy(player, 1)

	-- Banks toward this subject's mastery on the same ladder Science climbs. Quiz
	-- subjects had no ladder at all until now, which meant five of the six could never be
	-- finished with -- you sat Music at seventeen exactly as you sat it at six.
	--
	-- What a rung buys inside a quiz is, honestly, nothing yet. That is a debt and not a
	-- design: giving a level "one fewer question" or "five more seconds" would be a bigger
	-- number for the same decision, which is the numbers-only progression this rebuild
	-- exists to remove. The in-lesson reward arrives with each subject's real verb. What
	-- the rung buys *today* is the right to stop sitting the lesson, and that is worth
	-- having on its own -- see the skip at the door below.
	local before = Mastery.LevelOf(data, lesson.subjectId)
	local level, rose = Mastery.Record(data, lesson.subjectId, share)

	-- And onto the year's record, which is what the card handed over next birthday is
	-- drawn from. Written here rather than derived later because none of it survives the
	-- year otherwise: `smarts` is a running total that says nothing about which afternoon
	-- moved it, and mastery says where the player ended up rather than how they got there.
	--
	-- The promotion is passed only when there was one. A row reading "level 3" against a
	-- lesson that did not earn it would credit the wrong afternoon.
	Report.RecordLesson(data, lesson.subjectId, band, gained, if rose then level else nil)

	local scored = `{lesson.right} of {count} right`
	local reward = if gained > 0 then `. +{gained} smarts.` else "."
	local line = if reason == "left"
		then `You walked out. {scored}{reward}`
		else `Lesson over. {scored}{reward}`

	-- The promotion is said out loud and it replaces the score line rather than following
	-- it, because it is the more important of the two and two notices in a row means the
	-- first is never read. Topping out gets its own sentence: it is the only one that
	-- changes what the player can do tomorrow, and a player who is not told they may now
	-- skip will never find out -- the panel at the door only appears if they walk back.
	if rose then
		local name = subjectNameOf(lesson.subjectId)
		line = if level >= Mastery.Levels
			then `{scored}{reward} You have finished with {name} -- you can skip it from now on.`
			else `{scored}{reward} {name} level {level} of {Mastery.Levels}.`
	elseif before >= Mastery.Levels and reason ~= "left" then
		-- Sat a subject they had already beaten. Worth a word: they chose to, the smarts
		-- were real, and silence here reads as the skip having failed to work.
		line = `{scored}{reward} You did not have to sit that one.`
	end

	notice(player, line, gained > 0 or rose)
end

-- One question answered, by picking row `row` off the panel -- or not answered at all,
-- when `row` is nil and the clock ran out. Both go through here, because running out of
-- time is a wrong answer with the same consequences and should read as one.
local function answer(player: Player, lesson: Lesson, row: number?)
	local question = lesson.questions[lesson.index]

	local chose = if row ~= nil then lesson.order[row] else nil
	local correct = chose == question.correct
	if correct then
		lesson.right += 1
		-- Academics, per right answer. Time running out arrives here as `row == nil` and
		-- is a wrong answer to this branch exactly as it is to the lesson's own grade,
		-- which is the whole reason both paths were routed through this one function.
		SkillService.Award(player, "academics", Config.Skills.Awards.LessonCorrect, "right answer")
	end

	-- The teacher reads the verdict in the room while it is read on the panel. The
	-- gesture is a request the run loop picks up on its next frame; if the teacher
	-- is mid-walk-in it performs it once it arrives, which is late but never lost.
	-- A correct answer with a per-question reaction uses that instead of the
	-- default bow, so the teacher's body language varies across the lesson.
	local teacher = teachers[player]
	if teacher ~= nil then
		if correct and question.reaction ~= nil then
			teacher.gesture = question.reaction
		else
			teacher.gesture = if correct then "right" else "wrong"
		end
	end

	-- The teacher's line either way, which is the one thing that makes this school
	-- rather than a quiz: getting it wrong should still leave you knowing the answer.
	-- Prefixed with the verdict so the row reads as a reply to what you just did rather
	-- than as a fact appearing on screen.
	local opening = if correct then "Right." elseif chose ~= nil then "Not quite." else "Time."
	lesson.verdictText = `{opening} {question.because}`
	lesson.verdictRight = correct
	lesson.verdictLeft = SCHOOL.VerdictSeconds
	lesson.secondsLeft = 0

	-- The index deliberately does not move here. It advances when the explanation
	-- expires, so for the whole beat the line is up the row still says "3 of 5" about
	-- the question the line is explaining -- rather than about the one that has not
	-- been asked yet.
	push(player)
end

-- What is on today: the next slot of this year's timetable, which is the one after the
-- lessons already sat.
local function subjectFor(data: LifeData): SchoolSubject?
	return subjectForSlot(ageYearsOf(data), data.lessonsThisYear + 1)
end

-- Starts a lesson. Only fails for a reason worth saying out loud -- the caller has
-- already checked everything about the player, and there is no longer a room to fail
-- against.
--
-- Three shapes come out of here, and which one depends entirely on the subject's verb.
-- A "quiz" subject runs the loop in the rest of this file. A "procedure" subject hands
-- the whole afternoon to ScienceService and a "hunt" subject hands it to
-- GeographyService, and this file does nothing further with either -- including the
-- smarts and the yearly count, which each verb pays and spends itself. That split is
-- deliberate: the alternative is a School that knows how every verb is scored, which is
-- the file that would have to be edited six times over.
local function beginLesson(player: Player, data: LifeData, room: Vector3): boolean
	local subject = subjectFor(data)
	if subject == nil then
		notice(player, "There is nothing on today.", false)
		return false
	end

	if subject.verb == "procedure" then
		local ok, refusal = ScienceService.Begin(player, data)
		if not ok then
			notice(player, refusal or "The lab is closed today.", false)
			return false
		end
		-- Cleared so the science HUD is not opening underneath a school line about a
		-- lesson that is not the one running.
		notices[player] = nil
		push(player)
		return true
	end

	if subject.verb == "hunt" then
		local ok, refusal = GeographyService.Begin(player, data)
		if not ok then
			notice(player, refusal or "There is no geography today.", false)
			return false
		end
		-- Cleared for the same reason as above: the hunt takes the screen from here, and
		-- a school line left underneath it is a line about a lesson that is not running.
		--
		-- No teacher is spawned and no scene is drawn, unlike a quiz. That is the verb:
		-- the errand happens in the town, and a classroom built around a player who is
		-- about to walk out of it is furniture nobody will be in the room to see.
		notices[player] = nil
		push(player)
		return true
	end

	if subject.verb == "copy" then
		local ok, refusal = ArtService.Begin(player, data)
		if not ok then
			notice(player, refusal or "The art room is closed today.", false)
			return false
		end
		-- Cleared for the same reason as the two above.
		--
		-- No teacher and no scene here either, but for the opposite reason to Geography's:
		-- the art room is already built and already standing a few studs away, so a
		-- classroom drawn on top of it would be two rooms occupying one lesson. The player
		-- walks to the easel; that walk is the opening of the verb.
		notices[player] = nil
		push(player)
		return true
	end

	if subject.verb == "rhythm" then
		local ok, refusal = MusicService.Begin(player, data)
		if not ok then
			notice(player, refusal or "There is no music today.", false)
			return false
		end
		-- Cleared for the same reason as the three above.
		--
		-- No teacher and no scene here either, and for the same reason as Geography's: the
		-- verb is a needle and a press, and a classroom drawn around a player about to be
		-- looking at nothing but a sweep bar is a room built for nobody to look at.
		notices[player] = nil
		push(player)
		return true
	end

	if subject.verb == "match" then
		local ok, refusal = SoccerService.Begin(player, data)
		if not ok then
			notice(player, refusal or "There is no PE today.", false)
			return false
		end
		-- Cleared for the same reason as the four above -- the pitch takes the screen
		-- from here. No teacher and no scene for the same reason PE was never a fourth
		-- SportsDrill station either: the match is already running, bot-filled, a walk
		-- away, whether or not this call ever happens.
		notices[player] = nil
		push(player)
		return true
	end

	local questions = Lessons.For(ageYearsOf(data), SCHOOL.QuestionsPerLesson)
	if #questions == 0 then
		-- Impossible if the content file loaded, which checks every age has enough
		-- written for it. Reachable only if the bank is emptied without the check being
		-- updated, and the honest thing to do is say so rather than start a lesson with
		-- nothing in it.
		notice(player, "There is nothing on today.", false)
		return false
	end

	-- A quiz needs somewhere to sit. Refused here rather than left to open onto a room
	-- with no desks in it -- the same rule Science already lives by when the lab has
	-- nowhere to stand a station.
	if Classroom.Room() == nil then
		notice(player, "The classroom is not in the world right now.", false)
		return false
	end

	local lesson: Lesson = {
		room = room,
		subjectId = subject.id,
		questions = questions,
		index = 1,
		right = 0,
		order = {},
		secondsLeft = SCHOOL.SecondsPerQuestion,
		verdictLeft = 0,
		verdictText = nil,
		verdictRight = false,
		-- Not seated yet -- see the field's own note on Lesson. Nothing below this asks
		-- a question or spawns the teacher; both wait for RequestSit to succeed.
		seated = false,
	}

	-- Cleared here rather than left up, so a stale refusal is not still on screen once
	-- the player is standing in a room with somewhere to sit.
	notices[player] = nil
	lessons[player] = lesson
	notice(player, "Take a seat at a desk to begin.", true)
	push(player)
	return true
end

-- Taking the skip. Spends the lesson off the year and pays what an ordinary pass pays.
--
-- The payout is deliberately the middle band rather than the top one. A player who has
-- topped a subject out can reliably score above GoodShare in it -- that is what topping
-- it out means -- so paying SmartsPerGoodLesson here would make skipping strictly better
-- than attending, and the lesson would be dead content rather than a choice. Paying the
-- pass rate makes the trade honest: the skip costs you a point and buys you the
-- afternoon, and which of those is worth more is a real question that changes with how
-- much of the map you have left to see.
--
-- It counts as attendance, which is the other half of the deal. Turning up and proving
-- you know it already is turning up, so the missed-year penalty must not fire on a
-- player who skipped -- being punished for the thing you earned would be the single
-- worst sentence this system could say.
local function takeSkip(player: Player, data: LifeData, subjectId: string)
	data.lessonsThisYear += 1
	EventService.AwardAutonomy(player, 1)

	local gained = Report.SmartsFor(Report.Skipped)
	if gained ~= 0 then
		StatService.AddStat(player, "smarts", gained)
	end

	-- Recorded as its own band rather than as an ordinary pass. They are worth the same
	-- smarts and they are not the same afternoon, and a card that could not tell them
	-- apart would report a year spent elsewhere as a year of lessons.
	Report.RecordLesson(data, subjectId, Report.Skipped, gained, nil)

	local reward = if gained > 0 then ` +{gained} smarts.` else ""
	notice(player, `You skipped {subjectNameOf(subjectId)}.{reward} That is one lesson off the year.`, gained > 0)
end

-- A row picked off the panel. Checked against the question that is actually live
-- rather than against whatever the client thinks it is answering: the twenty seconds
-- are real, and an answer clicked as the clock ran out has to lose to the clock.
local function onAnswerRequested(player: Player, index: unknown, answerId: unknown)
	if type(index) ~= "number" or type(answerId) ~= "string" then
		return
	end

	-- The skip offer, which is not a question in a lesson and is answered before one is
	-- looked for. Index zero is the marker -- see stateFor -- and a lesson's questions
	-- count from one, so the two can never be confused for each other.
	local door = doors[player]
	if door ~= nil and index == 0 then
		doors[player] = nil

		local profile = DataService.GetProfile(player)
		if profile == nil then
			push(player)
			return
		end
		local data = Lives.Active(profile.Data)

		-- Re-checked here rather than trusted from when the panel was drawn. The offer may
		-- have been on screen for a while, and a birthday or a `/school year` in between
		-- can have closed the door behind it. Everything the client sends is a request.
		local refusal = refusalFor(data)
		if refusal ~= nil then
			notice(player, refusal, false)
			return
		end

		if answerId == "skip" then
			if not Mastery.IsTopped(data, door.subjectId) then
				-- Only reachable from a client that made the row up, since the offer is only
				-- ever drawn for a topped subject. Refused by name anyway: a silent drop here
				-- would look exactly like the button not working.
				notice(player, `You have not finished with {subjectNameOf(door.subjectId)} yet.`, false)
				return
			end
			takeSkip(player, data, door.subjectId)
			return
		end

		if answerId ~= "sit" then
			-- A row id the panel never drew. Nothing to say to a real player, and nothing
			-- to do but put the offer back up, which the next tick does.
			push(player)
			return
		end

		-- Sitting it. Falls through to the ordinary start, so a lesson chosen from the door
		-- is in every respect the lesson that would have started on its own -- the offer
		-- decides whether there is a lesson, never what one is. That is also why this needs
		-- no branch for Science: a topped-out procedure subject goes through here and comes
		-- out in the lab, exactly as it would have without the offer in front of it.
		local at = attendAt
		if at == nil then
			notice(player, "The school is not in the world right now.", false)
			return
		end
		-- Standing at the school is the one condition the offer itself does not carry. The
		-- panel comes down within a tick of walking away, but a click already in flight
		-- when it does would otherwise start a lesson from wherever the player had got to.
		local position = characterPosition(player)
		if position == nil or Ground.FlatDistance(position, at) > SCHOOL.AttendRadiusStuds then
			notice(player, "You walked off before you answered.", false)
			return
		end

		beginLesson(player, data, at)
		return
	end

	local lesson = lessons[player]
	if lesson == nil then
		return
	end
	-- Both halves of "this question, still open". The index catches an answer to the
	-- question before this one; the verdict catches one clicked during the beat the
	-- teacher's line is up, which is the same click arriving a fraction later.
	if lesson.index ~= index or lesson.verdictLeft > 0 or lesson.index > #lesson.questions then
		return
	end

	local row = tonumber(answerId)
	if row == nil or lesson.order[row] == nil then
		return
	end
	answer(player, lesson, row)
end

-- The L key, or a click on a desk -- see Classroom.TrySit for why the two are the same
-- request. The one thing this does that Classroom itself cannot: a desk found empty is
-- not yet a lesson started, and starting one -- drawing the first question, standing the
-- teacher up, taking down the seat-hint notice -- is SchoolService's business, not the
-- room's.
local function onSitRequested(player: Player)
	local lesson = lessons[player]
	if lesson == nil or lesson.seated then
		-- Nothing pending, or already sat -- a second press while seated has nothing
		-- left to do, and a press with no lesson at all is a key mashed outside school.
		return
	end

	if not Classroom.TrySit(player) then
		notice(player, "Find an open desk first.", false)
		return
	end

	lesson.seated = true
	-- Cleared before the question is drawn, not after -- push below carries whichever
	-- of the two is now true, and a client should never see both a question and the
	-- hint that led to it on the same frame.
	notices[player] = nil
	askCurrent(lesson, player)
	spawnTeacher(player)
	push(player)
end

local function tickPlayer(player: Player, elapsed: number)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)
	local position = characterPosition(player)

	local lesson = lessons[player]

	if lesson == nil then
		-- Whether the player has left the pad, for the two things that may already be up in
		-- front of them. Read once because both ask the identical question and a second
		-- probe a few lines apart could honestly answer it differently.
		--
		-- Only sound for a panel that is *already* open, which is the only thing it is used
		-- for. `attendAt` is filled in by buildRoom further down, so on the first tick of a
		-- session this reads nil -- harmless, because nothing can be open yet, and the
		-- lower half of this branch re-reads it after the room has been built.
		local standingAt = attendAt
		local walkedOff = position == nil
			or standingAt == nil
			or Ground.FlatDistance(position, standingAt) > SCHOOL.AttendRadiusStuds

		-- The card in the player's hands, and it outranks everything else the school could
		-- be doing. It is last year's business being finished before this year's is
		-- started, which is the order it happens in a real school and, more to the point,
		-- the order that stops a lesson beginning underneath something being read.
		--
		-- Comes down the moment they walk off, and goes back up when they come back: the
		-- card is still staged on the profile, and the only thing that puts it away is the
		-- player pressing the button on it.
		if cards[player] then
			if walkedOff then
				cards[player] = nil
				pushCard(player)
			end
			return
		end

		-- The skip offer comes down the moment the player walks off the pad, and before
		-- anything else is considered. A panel asking whether to sit today's lesson,
		-- still up while its owner is halfway across town, is the game talking about a
		-- building that is no longer in front of them.
		local door = doors[player]
		if door ~= nil then
			if walkedOff then
				doors[player] = nil
				push(player)
			end
			-- Returns either way. An open offer is a question the player has been asked and
			-- has not answered, and starting the lesson out from under it -- which is what
			-- falling through to the pad check below would do -- would answer it for them.
			return
		end

		local held = notices[player]
		if held ~= nil then
			held.secondsLeft -= elapsed
			if held.secondsLeft <= 0 then
				notices[player] = nil
			end
			push(player)
			-- Deliberately returns: the attend pad is not read while a line is being
			-- held, so somebody standing on it after a refusal reads the refusal instead
			-- of being refused again on every tick for as long as they stand there.
			return
		end

		if position == nil or not buildRoom() then
			return
		end

		-- A Science lesson is a lesson, and it is not one of these. Without this the pad
		-- is read on every tick of a lab session -- and the lab centre is the pad, so the
		-- player is standing on it the whole time -- and school would try to start a
		-- second lesson four times a second for the length of the procedure.
		if ScienceService.IsRunning(player) then
			return
		end

		-- And so is a Geography errand. The failure here is the same one but arrives
		-- later: a hunt begins on the school pad and ends wherever the last destination
		-- was, so the first tick after the player walks back into school would start a
		-- second lesson on top of the one they are still on.
		if GeographyService.IsRunning(player) then
			return
		end

		-- And so is a painting. Same failure as Science's, arriving in the same place: the
		-- art room is laid around the school pad, so an Art lesson begins with the player
		-- standing on the pad and stays that way for the seconds it takes them to walk out
		-- to the easel -- during which, without this, school would start a fresh lesson on
		-- top of it four times a second.
		if ArtService.IsRunning(player) then
			return
		end

		-- And so is a song. Same failure, same place: the moment a rhythm lesson opens, the
		-- player is still standing on the school pad that started it, and without this the
		-- tick loop would start a second lesson on top of the one already sweeping.
		if MusicService.IsRunning(player) then
			return
		end

		-- And so is a PE lesson being graded. Same failure, same place: the pitch is a
		-- walk from the school pad, but the grading window opens the instant Begin runs,
		-- while the player may still be standing on the pad that started it.
		if SoccerService.IsRunning(player) then
			return
		end

		local at = attendAt
		if at == nil or Ground.FlatDistance(position, at) > SCHOOL.AttendRadiusStuds then
			return
		end

		-- Handing the card over, and deliberately *above* the refusal below rather than
		-- after it. The two most likely refusals at this moment are "you have had your
		-- lessons this year" and "you are done with school" -- which are exactly the states
		-- the owner of an uncollected card is most likely to be in. A card collectable only
		-- on a day you may also sit a lesson is a card the last year of school never
		-- delivers, and the final year is the one whose card matters most.
		if data.pendingReport ~= nil then
			cards[player] = true
			pushCard(player)
			return
		end

		local refusal = refusalFor(data)
		if refusal ~= nil then
			notice(player, refusal, false)
			return
		end

		-- A subject already finished with is asked about rather than started. This is the
		-- only thing mastery buys today and it is the whole of part two: the lesson still
		-- exists, it is just no longer compulsory.
		--
		-- Asked at the door rather than offered from the HUD because arriving is what
		-- raises the question. A player who has topped out three subjects should not be
		-- carrying three standing offers around town -- the decision belongs to the moment
		-- they are standing outside the school with an afternoon in front of them.
		local subject = subjectFor(data)
		if subject ~= nil and Mastery.IsTopped(data, subject.id) then
			doors[player] = { subjectId = subject.id }
			push(player)
			return
		end

		beginLesson(player, data, at)
		return
	end

	-- From here on there is a lesson, and every way it can end is asked before
	-- anything is asked of the player.
	if not data.alive or not enabled then
		finish(player, data, lesson, "left")
		return
	end
	if position == nil or Ground.FlatDistance(position, lesson.room) > SCHOOL.RoomRadiusStuds then
		finish(player, data, lesson, "left")
		return
	end

	-- Not seated yet: waiting on RequestSit, which is the only thing that starts the
	-- clock -- see the field's note on Lesson. Nothing to tick, but still pushed, which
	-- is what keeps "Take a seat at a desk to begin." on screen for as long as this is
	-- true rather than ticking down and vanishing the way a refusal notice does; there
	-- is nothing wrong to explain here, just a thing not yet done, so it holds.
	if not lesson.seated then
		push(player)
		return
	end

	-- Sat down, then not sitting any more -- stood up, jumped, or knocked off. The desk's
	-- own occupant state governs this, not a timer, so the lesson ends the same tick
	-- rather than leaving a question up in front of a player no longer at a desk for it.
	if not Classroom.IsSitting(player) then
		finish(player, data, lesson, "left")
		return
	end

	if lesson.verdictLeft > 0 then
		lesson.verdictLeft -= elapsed
		if lesson.verdictLeft > 0 then
			push(player)
			return
		end

		lesson.verdictLeft = 0
		lesson.verdictText = nil
		lesson.index += 1
		if lesson.index > #lesson.questions then
			finish(player, data, lesson, "over")
			return
		end
		askCurrent(lesson, player)
		push(player)
		return
	end

	lesson.secondsLeft -= elapsed

	-- When the answers are discs on the floor, the tick is what reads the player's
	-- feet: standing on a disc is picking it, and the first disc under the player
	-- answers the question. When the answers are rows on the panel, a click arrives
	-- on its own remote and the tick only counts down.
	if lesson.discs ~= nil then
		for row, disc in lesson.discs do
			if Ground.FlatDistance(position, disc.at) <= SCHOOL.DiscReachStuds then
				answer(player, lesson, row)
				return
			end
		end
	end

	if lesson.secondsLeft <= 0 then
		answer(player, lesson, nil)
		return
	end

	push(player)
end

-- Ends whatever is running and forgets this player entirely. The one place a lesson
-- ends without being graded, because in every case that calls it there is nobody left
-- to grade -- a player who left, or a life that is being started over.
local function forget(player: Player)
	local lesson = lessons[player]
	if lesson ~= nil then
		destroyDiscs(lesson)
	end
	despawnTeacher(player)
	-- Frees the desk on every path that forgets a player, including a disconnect --
	-- otherwise a desk stays claimed by a Seat whose Occupant humanoid no longer exists
	-- to stand up any other way.
	Classroom.StandUp(player)
	lessons[player] = nil
	notices[player] = nil
	doors[player] = nil
	pushed[player] = nil
	-- Only the *held* card, never the staged one. `data.pendingReport` is the player's
	-- record and survives a logout on purpose -- what is dropped here is the fact that they
	-- happened to be standing at the school reading it. The new-life path clears the record
	-- itself, separately, through Report.Clear.
	cards[player] = nil
	pushedCards[player] = nil
end

-- The player pressed Continue. The one thing that puts a card away for good.
--
-- Carries the year it was pressed on, which is the only thing a client has to say about a
-- card -- there is exactly one pressable row, so *which row* is not a question. The year
-- is here for the race a lesson answer's question index is here for: a birthday landing
-- while a card is on screen stages a new one and swaps the panel underneath the player, and
-- a press already in flight from the old card would otherwise clear the new one unread.
-- One year of school, silently thrown away, in the one window where the game was talking
-- over itself.
local function onCardRead(player: Player, ageYears: unknown)
	if not cards[player] then
		-- No card in front of them. A stale press from a panel that came down while the
		-- click was in flight, and there is nothing to say about it: the thing the player
		-- wanted -- the card gone -- has already happened.
		return
	end

	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)
	local report = data.pendingReport
	if report == nil then
		cards[player] = nil
		pushCard(player)
		return
	end
	if ageYears ~= report.ageYears then
		-- Answering a card that is no longer the one staged. Left standing rather than
		-- refused out loud: the new card is already on screen in front of them, and a
		-- notice explaining a race would be the game apologizing for something the player
		-- never saw.
		return
	end

	cards[player] = nil
	data.pendingReport = nil
	pushCard(player)
end

-- A birthday. The year's lessons refill, and a year nobody turned up to is charged
-- for. Charged here rather than at the school, because not going is not a thing that
-- happens at a place -- it is a thing that turns out to have happened when the year
-- ends, which is exactly what a birthday is.
--
-- LifeService calls this after the age has already moved, so the year being judged is
-- the one just left: the age the player has now reached, less one. Getting that off by
-- one would charge a five-year-old for missing a year of school that had not started
-- and let a seventeen-year-old off the last one.
function SchoolService.OnAgeUp(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)

	local yearJustEnded = ageYearsOf(data) - 1
	-- A lesson in progress counts as having turned up, even though nothing has been
	-- graded yet. `lessonsThisYear` only moves when a lesson ends, so a birthday landing
	-- mid-question would otherwise charge a child for missing a year of school while
	-- they were sitting in it -- which is the one accusation this penalty must never
	-- make. The lesson goes on and counts against the new year when it finishes, which
	-- is the generous reading and the right one: they are still in the room.
	local missed = data.lessonsThisYear == 0
		and lessons[player] == nil
		and not ScienceService.IsRunning(player)
		and not GeographyService.IsRunning(player)
		and not ArtService.IsRunning(player)
		and not MusicService.IsRunning(player)
		and not SoccerService.IsRunning(player)
		and yearJustEnded >= SCHOOL.StartAge
		and yearJustEnded <= SCHOOL.EndAge

	data.lessonsThisYear = 0

	-- Closes the year and stages its card, before the penalty below is charged and told.
	-- Order matters in one direction only: `missed` has to be read before `lessonsThisYear`
	-- is reset, which it is. The card itself is not handed over here -- it waits on the
	-- profile until the player next stands at the school, which is the whole delivery
	-- decision for this feature. See the block in tickPlayer.
	--
	-- Fires on every birthday, including the ones outside school age, because CloseYear is
	-- what decides that: it wipes the year's lessons either way and only writes a grade for
	-- a year that was a school year. Skipping the call for a five-year-old would leave a
	-- half-year of nursery lessons on the record to be folded into the first real card.
	Report.CloseYear(data, yearJustEnded, missed)

	-- Any skip offer standing at the door is now about last year's timetable. The subject
	-- on today is keyed on the age and the lessons already sat, and a birthday moves both
	-- -- so an offer left up would name one subject and start another.
	doors[player] = nil

	if missed and SCHOOL.SmartsPerYearMissed ~= 0 then
		StatService.AddStat(player, "smarts", SCHOOL.SmartsPerYearMissed)
		-- Told rather than left to be noticed on the stats bar. A number quietly going
		-- down is the game punishing you without saying so, and this is the one penalty
		-- in the system -- it has to be legible or it is just an unexplained drift.
		notice(player, `You missed a year of school. {SCHOOL.SmartsPerYearMissed} smarts.`, false)
	end
end

-- A new life. Nobody inherits an education, and a lesson in progress belonged to
-- somebody who no longer exists.
function SchoolService.ResetForNewLife(player: Player)
	forget(player)
	-- Every verb goes with it. Called from here rather than added to the caller's list
	-- because these are subjects of this school rather than systems beside it: a caller
	-- that had to remember all of them would eventually forget one, and the failure -- a
	-- new child arriving at the lab, or in a town they have already learned, already good
	-- at it -- is invisible. This list grows by one line per verb, which is the price of
	-- that, and it is cheaper than the bug.
	ScienceService.ResetForNewLife(player)
	GeographyService.ResetForNewLife(player)
	ArtService.ResetForNewLife(player)
	MusicService.ResetForNewLife(player)
	SoccerService.ResetForNewLife(player)
	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		local data = Lives.Active(profile.Data)
		data.lessonsThisYear = 0

		-- The whole record, not just the year in progress. A new child holding somebody
		-- else's report card, or a record line claiming three years they never lived, is the
		-- kind of bug that reads as the save system being broken rather than as school
		-- being wrong.
		Report.Clear(data)

		-- Every subject, not just the ones on today's timetable. Cleared by walking the
		-- stored tables rather than the curriculum, because a life may hold mastery in a
		-- subject that has since been taken off it -- and a subject that is not cleared is
		-- one a new child arrives already finished with, which reads as the school
		-- refusing to teach them and is close to impossible to trace back to here.
		-- Collected before anything is removed. Clearing a subject writes to both tables,
		-- so deleting straight out of the one being walked is the kind of thing that works
		-- until the day it does not.
		local held: { string } = {}
		for subjectId in data.subjectMastery do
			table.insert(held, subjectId)
		end
		for subjectId in data.subjectPasses do
			if data.subjectMastery[subjectId] == nil then
				table.insert(held, subjectId)
			end
		end
		for _, subjectId in held do
			Mastery.Clear(data, subjectId)
		end
	end
	push(player)
	-- Takes down a card that was on screen when the life ended. `forget` has already
	-- dropped the digest, so this pushes nil rather than being deduplicated away.
	pushCard(player)
end

-- Studio harness: sits a lesson wherever the player is standing, skipping the walk to
-- the school but nothing else.
--
-- Deliberately does not skip the refusal check, for the reason WorkService.ForceStart
-- gives: a test tool that could open a door the game keeps shut is a tool that cannot
-- test the door. Age and the yearly cap are the two things most worth being able to
-- stand in front of and read the reason off.
function SchoolService.ForceStart(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	if lessons[player] ~= nil then
		return false, "already in a lesson"
	end

	local refusal = refusalFor(Lives.Active(profile.Data))
	if refusal ~= nil then
		return false, refusal
	end

	local position = characterPosition(player)
	if position == nil then
		return false, "no character in the world"
	end

	-- The room becomes wherever they are standing, so walking away still ends the
	-- lesson and the radius is still the radius. The same trick, and the same honesty
	-- about it, as clocking on where you stand.
	if not beginLesson(player, Lives.Active(profile.Data), position) then
		return false, "could not place the answers here"
	end
	return true, nil
end

-- Ends a lesson in progress and grades it, exactly as walking out would.
function SchoolService.ForceEnd(player: Player): boolean
	local lesson = lessons[player]
	local profile = DataService.GetProfile(player)
	if lesson == nil or profile == nil then
		return false
	end
	finish(player, Lives.Active(profile.Data), lesson, "over")
	return true
end

-- Studio harness: sets how many lessons this year is already down as having had.
--
-- The yearly cap and the missed-year charge are the two rules school actually turns on,
-- and both are otherwise only reachable by sitting three lessons or letting a whole year
-- go by. Clamped rather than refused above the cap, because the interesting test is the
-- refusal at the door and asking for four when three is the limit is asking for that.
function SchoolService.SetLessonsThisYear(player: Player, count: number): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil or count < 0 then
		return false
	end
	Lives.Active(profile.Data).lessonsThisYear = math.min(math.floor(count), SCHOOL.LessonsPerYear)
	push(player)
	return true
end

-- Studio harness: closes the school year on the spot and stages its card.
--
-- The card is otherwise only reachable by sitting lessons and then waiting out a birthday,
-- which at the real year length is minutes per card and a whole childhood to see a full
-- record line. This runs the same CloseYear the birthday runs, on the year the player is
-- actually in, so what it stages is a real card and not a mock one -- a harness that built
-- its own card would be testing itself.
--
-- Not delivered here. It goes onto the profile exactly as a birthday's would, and the
-- player still has to walk to the school for it, because *that walk is the feature* and a
-- command that skipped it could not test it.
function SchoolService.StageReportCard(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	local data = Lives.Active(profile.Data)
	local ageYears = ageYearsOf(data)

	if ageYears < SCHOOL.StartAge or ageYears > SCHOOL.EndAge then
		-- Refused by name rather than staging nothing and reporting success. CloseYear
		-- would drop it silently, and a command that prints "ok" and produces no card is
		-- the harness lying about the system it exists to explain.
		return false, `age {ageYears} is outside school (ages {SCHOOL.StartAge} to {SCHOOL.EndAge})`
	end

	-- Same reading of "missed" the birthday uses, minus the in-progress-lesson clause: this
	-- is being run deliberately, and refusing it because a lesson happens to be open would
	-- make the command depend on where the player is standing.
	local missed = data.lessonsThisYear == 0
	if not Report.CloseYear(data, ageYears, missed) then
		return false, "no year to close -- no lessons sat and the year is not counted as missed"
	end

	data.lessonsThisYear = 0
	-- The offer at the door is keyed on lessons already sat, which has just moved.
	doors[player] = nil
	push(player)
	return true, nil
end

-- Studio harness: sets mastery in any subject directly.
--
-- The command that makes the skip testable at all. Reaching the top rung honestly is
-- eight good lessons in one subject, which at three lessons a year and six subjects on
-- the timetable is most of a childhood -- so without this the only way to see the door
-- panel is to play to about fifteen.
--
-- Refuses an unknown subject rather than creating one. A typo that silently wrote
-- mastery in "sceince" would look exactly like the command not working, and the player
-- would go on typing it.
function SchoolService.SetMastery(player: Player, subjectId: string, level: number): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	if Curriculum.Get(subjectId) == nil then
		local names: { string } = {}
		for _, subject in Curriculum.All do
			table.insert(names, subject.id)
		end
		return false, `no subject "{subjectId}" -- try one of: {table.concat(names, ", ")}`
	end

	Mastery.Set(Lives.Active(profile.Data), subjectId, level)

	-- Any offer standing at the door is now about a stale level, so it comes down and is
	-- re-asked on the next tick. Without this, setting mastery while standing on the pad
	-- leaves the old panel up and the command looks like it did nothing.
	doors[player] = nil
	push(player)
	return true, nil
end

function SchoolService.SetEnabled(value: boolean)
	enabled = value
end

function SchoolService.IsEnabled(): boolean
	return enabled
end

-- What the harness prints. Every number a `/school` command could be asked about, in
-- the order somebody debugging would want them: whether the building was found, then
-- who this player is to it, then what is actually running.
function SchoolService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "school: no profile loaded"
	end
	local data = Lives.Active(profile.Data)

	local place = PlaceService.Find(PLACE_ID)
	local where = if place == nil
		then `no part tagged "{PLACE_ID}" -- the school is not in the world`
		else `at {math.floor(place.part.Position.X)}, {math.floor(place.part.Position.Z)}`

	local refusal = refusalFor(data) or "can sit a lesson now"

	local running = "no lesson"
	local lesson = lessons[player]
	if lesson ~= nil then
		local question = if lesson.index <= #lesson.questions
			then lesson.questions[lesson.index].id
			else "(finished)"
		local held = if lesson.verdictLeft > 0
			then `holding the teacher's line for {string.format("%.1f", lesson.verdictLeft)}s`
			else `{#lesson.order} answers on the panel, {string.format("%.1f", lesson.secondsLeft)}s left`
		running = `question {lesson.index}/{#lesson.questions} "{question}", {lesson.right} right, {held}`
	end

	-- Teacher presence: where the teacher stands, and what the last answer called for.
	-- The two "why is there nobody in the room" answers -- switched off, and no floor
	-- for it -- look identical from inside the game, so the harness says which.
	local teacherLine = "no teacher"
	local teacher = teachers[player]
	if teacher ~= nil then
		local gesture = if teacher.gesture == nil then "idle" else `about to {teacher.gesture}`
		local spot = math.floor((teacher.at - teacher.front).Magnitude * 10) / 10
		teacherLine = `teacher at the front, {gesture}, {string.format("%.1f", spot)} studs off-spot`
	elseif SCHOOL.TeacherEnabled then
		teacherLine = "teacher skipped (no floor for it)"
	end

	local pool = #Lessons.For(ageYearsOf(data), math.huge)

	-- The ladder, subject by subject, and only for the ones actually on this age's
	-- timetable -- a row for a subject that will not be taught for another three years is
	-- noise in a line that is already long. Today's subject is marked, because "which one
	-- is next" is the question every other part of this line is in service of.
	local today = subjectFor(data)
	local ladder: { string } = {}
	for _, subject in Curriculum.ForAge(ageYearsOf(data)) do
		local level = Mastery.LevelOf(data, subject.id)
		local mark = if today ~= nil and today.id == subject.id then "*" else ""
		local topped = if Mastery.IsTopped(data, subject.id) then " SKIPPABLE" else ""
		table.insert(
			ladder,
			`{mark}{subject.id} {level}/{Mastery.Levels}`
				.. `+{Mastery.PassesOf(data, subject.id)}/{Mastery.PassesPerLevel}{topped}`
		)
	end

	local door = doors[player]
	local offer = if door ~= nil then `offering the skip on {door.subjectId}` else "no offer up"

	-- The staged card and the held one said separately, because the two states they tell
	-- apart are the ones worth being able to tell apart: a card waiting on the profile that
	-- the player has not walked to the school for, versus one on screen in front of them.
	-- "Nothing is happening" looks the same from inside the game in both cases.
	local report = data.pendingReport
	local cardLine = if report == nil
		then `no card staged, {#data.schoolGrades} year(s) on the record`
		else `card staged for age {report.ageYears} "{report.grade}" ({#report.lessons} lesson(s)), `
			.. `{if cards[player] then "in hand" else "not collected"}, `
			.. `{#data.schoolGrades} year(s) on the record`

	return string.format(
		"school: %s | %s | age %d, %d/%d lessons this year, %d questions written for this age | %s | %s | %s | %s | %s | %s",
		if enabled then "enabled" else "DISABLED",
		where,
		ageYearsOf(data),
		data.lessonsThisYear,
		SCHOOL.LessonsPerYear,
		pool,
		refusal,
		running,
		teacherLine,
		table.concat(ladder, ", "),
		offer,
		cardLine
	)
end

function SchoolService:Start()
	Players.PlayerAdded:Connect(function(player: Player)
		-- Pushed once the profile exists, so a rejoining player's row starts blank
		-- rather than holding whatever the last occupant of the slot was looking at.
		task.spawn(function()
			if DataService.WaitForProfile(player) ~= nil then
				push(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		forget(player)
	end)

	RequestLessonAnswerRemote.OnServerEvent:Connect(function(player: Player, index: unknown, answerId: unknown)
		local ok, err = pcall(onAnswerRequested, player, index, answerId)
		if not ok then
			warn(`[AGES] lesson answer failed for {player.Name}: {err}`)
		end
	end)

	RequestReportCardReadRemote.OnServerEvent:Connect(function(player: Player, ageYears: unknown)
		local ok, err = pcall(onCardRead, player, ageYears)
		if not ok then
			warn(`[AGES] report card read failed for {player.Name}: {err}`)
		end
	end)

	RequestSitRemote.OnServerEvent:Connect(function(player: Player)
		local ok, err = pcall(onSitRequested, player)
		if not ok then
			warn(`[AGES] school sit failed for {player.Name}: {err}`)
		end
	end)

	task.spawn(function()
		while true do
			local elapsed = task.wait(SCHOOL.TickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player, elapsed)
				if not ok then
					warn(`[AGES] school tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

return SchoolService
