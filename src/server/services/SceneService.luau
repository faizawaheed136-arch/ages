--!strict
-- The thing the event is about, actually there. When an event names a subject,
-- this finds it somewhere to stand, walks it in as the prompt opens, keeps it
-- facing the player while the question is open, plays out its answer to whatever
-- the player chose, and takes it away afterwards.
--
-- It exists because of a specific hole. "There is a dog. It is at least as tall
-- as you are, and it has noticed you" was a sentence about an animal that did not
-- exist, and enactment made that worse rather than better: a card at least keeps
-- the fiction in one place, whereas a marker on the floor reading "Put your hand
-- out" points at nothing at all. The subject is what the marker is for.
--
-- The same argument runs one step further and is why reactions are here too. "It
-- shoved its whole head under your palm" and "you held still until it lost
-- interest" are two different things happening in a room, and an animal that
-- stands there identically under both of them is telling the player that their
-- answer did not matter -- in the one medium, the room itself, where the game had
-- just finished insisting that it did.
--
-- Deliberately independent of both other axes. Delivery decides how the event
-- reached you and resolution decides how you answer it; a subject is what it is
-- *about*, and the dog turns up whether the event arrived on a birthday or off a
-- doormat, and whether you answer it on a panel or by walking. Nothing here reads
-- either field.
--
-- Best-effort in exactly the sense EnactService is. A room with nowhere to put
-- the animal is an ordinary outcome, not an error: the event plays as it did
-- before subjects existed. And unlike a choice marker, a subject is never
-- interactive -- it cannot be walked onto, cannot be collided with and answers no
-- probes -- so it can never be the reason a prompt cannot be answered.
--
-- Travel is a route rather than a Humanoid walk, which is the one place this is
-- knowingly simpler than NPCService. A visitor is a real R15 avatar and MoveTo is
-- the right tool for one; a subject may be any shape at all, and a hand-built
-- Humanoid rig would be fragile in exactly the ways that do not matter here --
-- nothing ever pushes the dog, and nothing ever needs it to fall over. The route
-- is checked against the same probes a walk would have had to satisfy.
--
-- What the animal *does* along that route is SubjectMotion's, and the split is
-- the point: this file decides where the feet are each frame and how far they
-- have come, and knows nothing about legs. That is also what makes a bought model
-- a drop-in -- its own walk clip plays along the same route through the same
-- interface, and nothing here can tell the difference.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local Ground = require(script.Parent.Parent.world.Ground)
local SubjectModels = require(script.Parent.Parent.world.SubjectModels)
local SubjectMotion = require(script.Parent.Parent.world.SubjectMotion)
local Subjects = require(script.Parent.Parent.content.Subjects)

type LifeEvent = Types.LifeEvent
type EventChoice = Types.EventChoice
type ChoiceReaction = Types.ChoiceReaction
type SceneSubject = Types.SceneSubject
type SubjectRig = SubjectModels.SubjectRig
type Motion = SubjectMotion.Motion

local SceneService = {}

-- One folder for every subject in play, so a leak shows up as a fat folder in the
-- explorer rather than as animals scattered through the house.
local SCENE_FOLDER = "AgesScene"

-- Below this a direction is noise rather than a heading -- a player looking
-- straight down, or a travel vector between two points on top of each other.
local MIN_DIRECTION = 1e-3

-- How close a turn on the spot has to get before it counts as finished, and the
-- longest it is allowed to spend getting there. Cosmetic, and therefore local
-- rather than Config on the rule the rest of this feature follows: nobody balances
-- this game by adjusting how sharply a dog comes round.
--
-- Both are needed and neither is arbitrary. The easing is exponential and so never
-- actually arrives, and the walk that follows a turn has to start exactly aligned
-- or the animal crabs sideways forever; the cap bounds the loop whatever
-- TurnResponsiveness has been tuned to, including zero.
local TURN_DONE_DEGREES = 3
local MAX_TURN_SECONDS = 2

type Active = {
	eventId: string,
	subject: SceneSubject,
	rig: SubjectRig,
	motion: Motion,
	-- What the answer turned out to be, filled in by onAnswered at the moment the
	-- player chooses. Nil until then, and nil forever for an event whose choices
	-- carry no reactions -- which is most of them, and which is the behaviour this
	-- had before reactions existed: hold while the outcome is read, then leave.
	reaction: ChoiceReaction?,
	-- Whether an answer has landed at all, which nil above cannot say by itself.
	-- Nothing in play reads this; it is for the Studio harness, where "the event has
	-- not been answered yet" and "it was answered by a choice the content gives no
	-- reaction to" are the same animal standing in the same room and completely
	-- different things to go and fix.
	answered: boolean,
	-- Where it came in from, which is also where it leaves by, so an exit is the
	-- entrance run backwards rather than a second piece of routing.
	spawnAt: Vector3,
	stopAt: Vector3,
	-- Ground covered since the scene began, which is what the gait is keyed to.
	-- Accumulated rather than recomputed from the endpoints, because it has to
	-- carry across the walk in, the wait and the walk out as one continuous number
	-- -- a stride that restarted at each leg of the journey would plant the feet
	-- differently every time.
	traveled: number,
	-- os.clock() when the scene began. Everything that happens while the animal is
	-- standing still is keyed to this, since there is no distance to key off.
	startedAt: number,
	-- Set by stop(); every loop below checks it. A scene owns a running coroutine
	-- and a model, and this is the one thing that ends both.
	cancelled: boolean,
}

local active: { [Player]: Active } = {}

-- Why the last event that opened did or didn't put something in the room, for the
-- Studio harness alone. Nothing here is an error and nothing is logged, but "no
-- subject" has half a dozen causes that look identical from inside the game --
-- the event named none, the room was too tight, scenes are switched off -- and a
-- harness that cannot tell them apart is a harness that gets ignored.
local lastReason: { [Player]: string } = {}

-- Debug switch for the Studio harness, never touched in a live server. Off means
-- events play as text again, which is also the state to put the game in while
-- testing something that has nothing to do with subjects.
local enabled = true

local function sceneFolder(): Folder
	local existing = workspace:FindFirstChild(SCENE_FOLDER)
	if existing ~= nil then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = SCENE_FOLDER
	folder.Parent = workspace
	return folder
end

-- Ends a scene immediately and without ceremony. Everything that has a graceful
-- ending goes through the tail of run() instead; this is what the abrupt endings
-- share -- a death, a new event, a player leaving.
local function stop(player: Player)
	local current = active[player]
	if current == nil then
		return
	end
	active[player] = nil
	current.cancelled = true
	-- Before the model goes, because an adopted model's motion holds animation
	-- tracks loaded off it and stopping them afterwards would be stopping tracks on
	-- an Animator that no longer has a parent.
	current.motion.stop()
	current.rig.model:Destroy()
end

-- Ends a scene from inside its own coroutine, and only if it is still the one in
-- play. run() reaches its tail across yields, and by then a second event may have
-- superseded it and started a scene of its own -- clearing by player alone would
-- take that newer one down instead of this finished one.
local function finish(player: Player, current: Active)
	if active[player] ~= current then
		return
	end
	stop(player)
end

-- Collected first rather than cleared during the traversal: stop() removes the
-- key it would be standing on, and adding or removing keys mid-pairs is undefined.
local function stopAll()
	local players: { Player } = {}
	for player in active do
		table.insert(players, player)
	end
	for _, player in players do
		stop(player)
	end
end

-- Flattened onto the floor plane. Everything here is arranged on the ground, and
-- a player looking at their feet or up the stairs must not tip the arrangement
-- over -- the same reasoning, and the same guard, as EnactService's fan.
local function flatten(direction: Vector3): Vector3?
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < MIN_DIRECTION then
		return nil
	end
	return flat.Unit
end

type Placement = { spawnAt: Vector3, stopAt: Vector3 }

-- Where the subject comes to rest and where it comes in from, or nil if this
-- walk-in length cannot be fitted anywhere in the arc.
--
-- Four questions per bearing, and each one is a failure that has been seen: the
-- resting place needs a floor under it and room for the animal on it, the player
-- has to be able to see it -- an animal behind a wall is not in the room -- and
-- the way in has to be clear, or the dog arrives through the couch.
local function place(character: Model, subject: SceneSubject, walkIn: number): Placement?
	local pivot = character:GetPivot()
	local origin = pivot.Position
	local forward = flatten(pivot.LookVector)
	if forward == nil then
		return nil
	end

	local playerHeight = Ground.BodyHeight(character)
	-- The animal's footprint is its own, not the player's: a dog is longer than it
	-- is tall and a cat fits places a dog does not.
	local subjectRadius = math.max(subject.bodyLength, subject.bodyWidth) / 2
	local subjectHeight = subject.shoulderHeight
	local ignore = Ground.IgnoreList()

	-- ApproachStuds is clearance past arm's reach, and clearance is measured to the
	-- animal's near edge rather than to its middle -- otherwise half a dog is already
	-- inside clicking range while a cat leaves a gap, which is backwards. Adding its
	-- own half-length here is what makes one Config number correct for both.
	local restAt = Config.Scene.ApproachStuds + subject.bodyLength / 2

	for _, angle in Ground.Bearings(Config.Scene.ArcDegrees, Config.Scene.Bearings) do
		local direction = CFrame.Angles(0, math.rad(angle), 0) * forward

		-- Two spots per bearing rather than one, which is why this stays a loop of its
		-- own: the animal has to be able to walk from where it appears to where it
		-- stops, so the pair either works together or neither of them counts.
		--
		-- The stop first and with no reachability of its own, because the line that
		-- matters to it is the player's, and that is measured separately below at the
		-- player's height rather than the animal's.
		local stopGround = Ground.SpotAt(origin + direction * restAt, subjectRadius, subjectHeight, ignore)
		if stopGround == nil then
			continue
		end
		-- The walk-in, checked against the stop it has to reach.
		local spawnGround =
			Ground.SpotAt(origin + direction * (restAt + walkIn), subjectRadius, subjectHeight, ignore, stopGround)
		if spawnGround == nil then
			continue
		end
		-- Measured at the player's height rather than the animal's, because the
		-- question this one asks is whether the *player* has a clear line to it.
		if not Ground.Reachable(origin, stopGround, playerHeight, ignore) then
			continue
		end

		return { spawnAt = spawnGround, stopAt = stopGround }
	end

	return nil
end

-- Turns CFrame.Angles' Y rotation into "facing this way", so every placement
-- below is written in headings rather than in axes. For a Y rotation of theta the
-- look direction is (-sin, 0, -cos), so the heading that points along `direction`
-- is atan2 of its negation.
local function headingTo(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

-- A floor point and a facing, which is the only kind of frame anything here deals
-- in. Ground level rather than hip level: whatever the rig needs adding to reach
-- its own root is the rig's business and is added inside the motion.
local function poseAt(at: Vector3, heading: number): CFrame
	return CFrame.new(at) * CFrame.Angles(0, heading, 0)
end

-- Hands one frame to the motion. Every caller goes through this rather than
-- building a Pose inline, so "which fields does a frame need" is answered once and
-- a new one can be added without hunting down every call site.
local function present(current: Active, root: CFrame, moving: boolean, turning: number, settled: boolean)
	current.motion.apply({
		root = root,
		traveled = current.traveled,
		elapsed = os.clock() - current.startedAt,
		moving = moving,
		turning = turning,
		settled = settled,
	})
end

-- Moves the subject between two floor points at its own pace, facing the way it is
-- going. Returns false if the scene was cancelled part-way, which every caller must
-- treat as "stop, the model is already gone".
--
-- Distance covered is banked into the scene rather than kept locally, because the
-- gait is keyed to it and the walk in, the wait and the walk out have to read as
-- one continuous journey: a stride that restarted at each leg would replant the
-- feet at every stop.
local function travel(current: Active, from: Vector3, to: Vector3): boolean
	local direction = flatten(to - from)
	local distance = (to - from).Magnitude
	if direction == nil or distance < MIN_DIRECTION then
		return true
	end

	local heading = headingTo(direction)
	local covered = 0
	while covered < distance do
		local delta = RunService.Heartbeat:Wait()
		if current.cancelled then
			return false
		end
		local step = math.min(distance - covered, current.subject.walkSpeed * delta)
		covered += step
		current.traveled += step
		present(current, poseAt(from:Lerp(to, covered / distance), heading), true, 0, false)
	end

	return true
end

-- Whether the scene is still wanted, which is a question about the prompt and not
-- about this table. An event answered, a player who died, a life that ended, a
-- profile that went away, a second event offered on top -- all of them show up
-- here as "the pending id is no longer mine", so there is one condition to get
-- right instead of a subscription to every service that could have ended it. The
-- same trick EnactService uses, for the same reason.
local function stillWanted(player: Player, current: Active): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil or not Lives.Active(profile.Data).alive then
		return false
	end
	return Lives.Active(profile.Data).pendingEventId == current.eventId
end

-- Whether the prompt ended by being *answered*, as opposed to by a death or by
-- being superseded. Read off the seen list rather than passed in, because nothing
-- calls this service when a choice resolves -- and adding a call would mean
-- EventService had to know a subject existed.
local function wasAnswered(player: Player, current: Active): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil or not Lives.Active(profile.Data).alive then
		return false
	end
	return Lives.Active(profile.Data).seenEventIds[current.eventId] == true
end

-- Which way the player is from a point on the floor, or nil if there is nobody to
-- look at -- a character still loading, or one that has just been removed. Nil is
-- an ordinary answer and every caller keeps whichever heading it already had,
-- because an animal that snaps to a default when a character reloads is worse
-- than one that goes on looking where it was looking.
local function towardPlayer(player: Player, from: Vector3): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	return flatten(character:GetPivot().Position - from)
end

-- One frame of standing still: eases the facing round toward the player, hands the
-- frame over, and reports where the facing ended up. The turn still to make goes
-- with it so the head can lead the body through it.
--
-- A function rather than a block inside the waiting loop because the waiting is no
-- longer the only time the animal stands there. An animal that breathes while the
-- question is open and then freezes solid the instant it is answered is worse than
-- one that never breathed -- the freeze is the moment the player is looking
-- straight at it.
local function stand(player: Player, current: Active, at: Vector3, heading: number, settled: boolean): number
	local remaining = 0
	local target = towardPlayer(player, at)
	if target ~= nil then
		local desired = headingTo(target)
		remaining = (desired - heading + math.pi) % (2 * math.pi) - math.pi
		-- Eased rather than snapped: an animal that tracks you perfectly is a turret.
		heading += remaining * Config.Scene.TurnResponsiveness
	end
	present(current, poseAt(at, heading), false, remaining, settled)
	return heading
end

-- Stands facing the player for a while. Returns false if the scene was cancelled
-- part-way, which every caller must treat as "stop, the model is already gone" --
-- the same contract travel() has, because the two are interchangeable steps in the
-- sequence at the end of run().
local function hold(
	player: Player,
	current: Active,
	at: Vector3,
	heading: number,
	seconds: number,
	settled: boolean
): (boolean, number)
	local waited = 0
	while waited < seconds do
		local delta = RunService.Heartbeat:Wait()
		if current.cancelled then
			return false, heading
		end
		waited += delta
		heading = stand(player, current, at, heading, settled)
	end
	return true, heading
end

-- Turns on the spot to face a fixed heading. Distinct from stand()'s easing in two
-- ways that matter: the target is a direction of travel rather than the player, and
-- this one has to actually finish.
--
-- It exists because every walk used to begin with the animal snapping instantly to
-- face wherever it was going. On the way in that was invisible -- it spawns already
-- pointing the right way -- but every leg after the first is a turn the player is
-- watching, and a dog that leaves by rotating 180 degrees in one frame and then
-- walking has not turned away from you, it has been rewound.
local function turn(current: Active, at: Vector3, heading: number, desired: number): (boolean, number)
	local waited = 0
	while true do
		local remaining = (desired - heading + math.pi) % (2 * math.pi) - math.pi
		-- The last fraction of a degree is taken in one step. Invisible, and it is
		-- what lets the walk that follows start exactly aligned rather than crabbing
		-- by however much the easing had left to do.
		if math.abs(remaining) <= math.rad(TURN_DONE_DEGREES) or waited >= MAX_TURN_SECONDS then
			return true, desired
		end

		local delta = RunService.Heartbeat:Wait()
		if current.cancelled then
			return false, heading
		end
		waited += delta
		heading += remaining * Config.Scene.TurnResponsiveness
		present(current, poseAt(at, heading), false, remaining, false)
	end
end

-- Where the subject stops when it comes to the player, or nil if there is nowhere
-- worth coming to. Nil covers "already close enough" as well as "cannot get
-- there", and both mean the same thing to the caller: stay put. An approach that
-- cannot be made is an ordinary outcome on the same terms as everything else here
-- -- the animal holds where it is, the outcome still reads, and nothing is broken.
--
-- Measured against where the player is *now*, not where they were when the prompt
-- opened. An enacted answer is given by walking, so by the time this is called they
-- are standing on a marker somewhere else in the room -- and for "Put your hand
-- out" that marker is between them and the dog, which is exactly the case this has
-- to get right.
local function approachSpot(player: Player, current: Active): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end

	local from = current.stopAt
	local to = character:GetPivot().Position
	local direction = flatten(to - from)
	if direction == nil then
		return nil
	end

	local subject = current.subject
	-- Edge to edge: the player's own width, the gap, and the animal's half-length.
	-- One Config number is then right for a toddler meeting a dog and an adult
	-- meeting a cat, which is the same trick ApproachStuds uses.
	local gap = Ground.BodyRadius(character) + Config.Scene.ReactionCloseStuds + subject.bodyLength / 2
	local away = Vector2.new(to.X - from.X, to.Z - from.Z).Magnitude
	if away - gap < MIN_DIRECTION then
		return nil
	end

	local ignore = Ground.IgnoreList()
	local subjectRadius = math.max(subject.bodyLength, subject.bodyWidth) / 2
	return Ground.SpotAt(from + direction * (away - gap), subjectRadius, subject.shoulderHeight, ignore, from)
end

-- The whole life of a scene: walk in, hold while the question is open, do whatever
-- the answer says it did, and then either leave the way it came or vanish,
-- depending on how the question ended.
local function run(player: Player, current: Active)
	if not travel(current, current.spawnAt, current.stopAt) then
		return
	end

	-- Seeded facing the player if there is one, and otherwise along the way it came
	-- in -- which is the direction it is already pointing, so a missing character at
	-- this instant costs a turn rather than a snap.
	local toPlayer = towardPlayer(player, current.stopAt)
	local heading = if toPlayer ~= nil then headingTo(toPlayer) else headingTo(current.stopAt - current.spawnAt)
	local sinceCheck = math.huge

	while true do
		local delta = RunService.Heartbeat:Wait()
		if current.cancelled then
			return
		end

		-- Coarse on purpose: this only bounds how quickly a subject clears after
		-- the prompt it belongs to has gone, and the profile lookup is the one
		-- thing in the loop that is not arithmetic.
		sinceCheck += delta
		if sinceCheck >= Config.Scene.TickSeconds then
			sinceCheck = 0
			if not stillWanted(player, current) then
				break
			end
		end

		-- Standing and watching. The turn still to make is handed to the motion as
		-- well as applied here, because the head leads the body through a turn -- a
		-- body that rotates with its head bolted straight ahead reads as a gun
		-- turret, which is the same failure NPCService's head tracking exists to
		-- avoid, one joint further out.
		heading = stand(player, current, current.stopAt, heading, false)
	end

	-- Past here the prompt is over. An abrupt ending gets an abrupt exit: nobody
	-- is watching a dog walk out of a room they have just died in.
	if not wasAnswered(player, current) then
		finish(player, current)
		return
	end

	-- Everything below is the ending, and it is the one stretch of this file that
	-- can be interrupted at half a dozen points -- the player may die, leave, or be
	-- handed a new event at any of them. Every step returns false when the scene was
	-- cancelled under it, and every one of those means the model is already gone and
	-- there is nothing left to tidy.
	local reaction = current.reaction
	local at = current.stopAt
	local ok = true

	if reaction == "approach" then
		local closeAt = approachSpot(player, current)
		if closeAt ~= nil then
			local direction = flatten(closeAt - at)
			if direction ~= nil then
				ok, heading = turn(current, at, heading, headingTo(direction))
				if not ok then
					return
				end
				if not travel(current, at, closeAt) then
					return
				end
				at = closeAt
			end
		end
	end

	-- The outcome is on screen now, and the animal it is about is still there while
	-- it is read -- vanishing on the click would undo the entire reason it walked
	-- in. Withdrawing is the one answer that skips this, and has to: turning away
	-- *is* what "it lost interest" looks like, and an animal that turns away and
	-- then waits four seconds has not lost interest in you at all.
	if reaction ~= "withdraw" then
		ok, heading = hold(player, current, at, heading, Config.Scene.LingerSeconds, reaction == "settle")
		if not ok then
			return
		end
		if reaction == "settle" then
			-- On its feet before anything moves. An animal asked to walk while it is
			-- still on the floor slides across the room on its side, which is exactly
			-- the failure the whole gait exists to prevent, one pose further out. The
			-- motion owns how long getting up takes, so the motion is asked.
			ok, heading = hold(player, current, at, heading, SubjectMotion.SettleSeconds, false)
			if not ok then
				return
			end
		end
	end

	-- Out the way it came, retracing an approach first if it made one. Every leg of
	-- the exit is then a route that was already checked in the other direction,
	-- which is why leaving needs no probing of its own.
	if at ~= current.stopAt then
		local back = flatten(current.stopAt - at)
		if back ~= nil then
			ok, heading = turn(current, at, heading, headingTo(back))
			if not ok then
				return
			end
		end
		if not travel(current, at, current.stopAt) then
			return
		end
	end

	local out = flatten(current.spawnAt - current.stopAt)
	if out ~= nil then
		-- The heading it ends on is the one travel() is about to use anyway, so only
		-- the "was this cancelled" half of the answer is wanted here.
		local turned = turn(current, current.stopAt, heading, headingTo(out))
		if not turned then
			return
		end
	end
	travel(current, current.stopAt, current.spawnAt)
	finish(player, current)
end

-- Called by EventService at the moment a prompt opens. Returns the model that is
-- doing the walking, which is everything anything else in the room needs to know
-- about it.
--
-- The model rather than a position, and that is the whole of why the choice hangs
-- where it does. A point would be true once, at this instant, and the animal is
-- still walking in -- anything pinned to it would be pinned to where the dog used
-- to be going. The dots ride the model instead and ask it where it is, so the dog
-- can walk in, turn to face you, and come over when you answer without the choice
-- ever losing track of it.
--
-- Handing out the model is a real widening of what this service exposes, and the
-- bound is worth stating: it is read, never driven. run() owns every pose the
-- animal takes, and a second writer moving it would be two things driving one
-- model -- the same rule onAnswered below already keeps.
--
-- Nil is the answer to every reason there is no animal, and every one of them is
-- ordinary: an event about nothing, a room that cannot hold one, a harness switch
-- turned off. Callers treat nil as "there is nothing to be toward" and fall back
-- to what they did before subjects existed.
local function begin(player: Player, event: LifeEvent): Types.StagedSubject?
	stop(player)

	if not enabled then
		lastReason[player] = "scenes are switched off"
		return nil
	end

	local subjectId = event.subject
	if subjectId == nil then
		lastReason[player] = `"{event.id}" is not about anything`
		return nil
	end

	-- Validated at content load, so reaching here with an unknown id would mean the
	-- validator was bypassed. Warn rather than throw: a missing prop must not take
	-- the event down with it.
	local subject = Subjects.ById[subjectId]
	if subject == nil then
		warn(`[AGES] event "{event.id}" is about "{subjectId}", which is not a subject; nothing will appear`)
		lastReason[player] = `"{subjectId}" is not a subject`
		return nil
	end

	local character = player.Character
	if character == nil then
		lastReason[player] = `no character to put a {subject.name} in front of`
		return nil
	end

	-- Full walk-in first, then drawn in once. Two attempts rather than a search,
	-- for the reason EnactService gives: the difference between them is the
	-- difference between a room and a corner.
	local retryWalkIn = Config.Scene.WalkInStuds * Config.Scene.RetryWalkInScale
	local placed = place(character, subject, Config.Scene.WalkInStuds)
	if placed == nil then
		placed = place(character, subject, retryWalkIn)
	end
	if placed == nil then
		lastReason[player] = string.format(
			"nowhere here for a %s: %d bearings across %d degrees, walking in %.0f then %.0f studs",
			subject.name,
			Config.Scene.Bearings,
			Config.Scene.ArcDegrees,
			Config.Scene.WalkInStuds,
			retryWalkIn
		)
		return nil
	end
	lastReason[player] = ""

	local rig = SubjectModels.Build(subject)
	local current: Active = {
		eventId = event.id,
		subject = subject,
		rig = rig,
		motion = SubjectMotion.Attach(rig),
		-- Nothing has been answered yet, and for most events nothing ever will be:
		-- written here rather than left out so that the one field whose value is a
		-- moment in the future is visible in the shape of a scene at the moment it
		-- starts.
		reaction = nil,
		answered = false,
		spawnAt = placed.spawnAt,
		stopAt = placed.stopAt,
		traveled = 0,
		startedAt = os.clock(),
		cancelled = false,
	}

	-- Posed before parenting, so the subject is never seen for a frame standing at
	-- the world origin in whatever shape it was built in, and is already facing the
	-- way it is about to walk.
	local direction = flatten(placed.stopAt - placed.spawnAt)
	present(current, poseAt(placed.spawnAt, if direction ~= nil then headingTo(direction) else 0), false, 0, false)
	rig.model.Parent = sceneFolder()

	active[player] = current
	task.spawn(run, player, current)

	return rig.model
end

-- Told by EventService which way the question went, which is the one thing about
-- an event this service cannot work out for itself: the choice is never written to
-- the profile, and should not be -- it matters for the few seconds an animal is
-- still in the room and never again.
--
-- Guarded on the id rather than on the player alone. By the time an answer lands,
-- a newer event may already have superseded this one and started a scene of its
-- own, and the reaction to the old question must not be played by the new animal.
local function onAnswered(player: Player, event: LifeEvent, choice: EventChoice)
	local current = active[player]
	if current == nil or current.eventId ~= event.id then
		return
	end
	-- Stored rather than acted on. run() is mid-frame somewhere in its waiting loop
	-- and owns every pose the animal takes; a second writer moving it from in here
	-- would be two things driving one model.
	current.reaction = choice.reaction
	current.answered = true
end

-- Studio harness: what is standing in the room right now.
function SceneService.Describe(player: Player): string
	local current = active[player]
	if current == nil then
		local reason = lastReason[player]
		if reason == nil or reason == "" then
			return `no subject | scenes {if enabled then "on" else "off"}`
		end
		return `no subject: {reason}`
	end

	local at = current.rig.model:GetPivot().Position
	local fromRest = (at - current.stopAt).Magnitude
	return string.format(
		'"%s" | %s (%s) at (%.1f, %.1f) | %s | %s | %s, %.1f studs walked',
		current.eventId,
		current.subject.name,
		current.subject.id,
		at.X,
		at.Z,
		-- Half a stud is well under one frame of travel at any authored walkSpeed,
		-- so "in place" means arrived rather than nearly arrived.
		if fromRest < 0.5 then "in place" else "on the move",
		-- Three states, not two, and the third is the one worth printing: an event
		-- that was answered and has no reaction to play looks exactly like one that
		-- has not been answered yet, and the fix for the two is completely different.
		if not current.answered then "unanswered" else current.reaction or "no reaction",
		-- Which of the two motions it got, which is the first thing worth knowing
		-- when a dropped-in model stands frozen: "posed" means the placeholder is
		-- being animated here, "clips" means the model brought its own and this is
		-- only choosing between them.
		if current.rig.limbs ~= nil then "posed" else "clips",
		current.traveled
	)
end

function SceneService.SetEnabled(value: boolean)
	enabled = value
	if value then
		return
	end
	-- Switching off mid-scene leaves an animal standing in a room nothing is
	-- watching any more.
	stopAll()
end

-- Removes every subject currently standing around. Used at server start, where a
-- Rojo sync mid-session can otherwise leave models behind with nothing left
-- holding a reference to them.
function SceneService.DespawnAll()
	stopAll()

	local folder = workspace:FindFirstChild(SCENE_FOLDER)
	if folder ~= nil then
		folder:ClearAllChildren()
	end
end

function SceneService:Init()
	-- Injected rather than required the other way around, matching EnactService:
	-- a subject is something an event *has*, so the event engine must not have to
	-- know that this file exists.
	EventService.SetSceneHandler(begin)
	-- Added to the answered listeners rather than owning the slot: WorkService
	-- listens for the same news to score the shift, and the two have nothing to say
	-- to each other.
	EventService.OnAnswered(onAnswered)
end

function SceneService:Start()
	SceneService.DespawnAll()
	Players.PlayerRemoving:Connect(function(player: Player)
		stop(player)
		-- Keyed by Player, so leaving this behind would hold a reference to someone
		-- who has gone. Small, and exactly the kind of small that accumulates over a
		-- server's lifetime.
		lastReason[player] = nil
	end)
end

return SceneService
