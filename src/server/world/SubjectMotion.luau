--!strict
-- How a subject carries itself. SubjectModels decides what turns up and names its
-- pieces; this moves them.
--
-- It exists because a dog that slides is worse than no dog. An animal translating
-- across a floor with its legs locked does not read as an animal at all -- it
-- reads as furniture being pushed, and every other thing the scene gets right
-- (the size, the timing, the fact that it looks at you) is spent arguing with
-- that one wrong signal. The gait below is not decoration; it is the difference
-- between something arriving and something being moved.
--
-- Two implementations behind one interface, chosen by what the rig turned out to
-- be:
--
--   A placeholder hands over its own parts, so the gait is computed here. Keyed
--   to *distance travelled* rather than to time, which is the one decision that
--   makes or breaks it: legs driven by a clock skate whenever the speed changes,
--   and legs driven by distance plant wherever the animal actually is.
--
--   An adopted model hands over an Animator and whatever clips it shipped with,
--   so the gait is whatever its author made and this only decides which clip is
--   playing. Somebody else's rig is not ours to take apart and guess at.
--
-- Nothing here reads a part's live CFrame. Every frame is computed from the rest
-- pose the rig captured at build time, so a pose can never accumulate error --
-- an hour of tail wag leaves the tail exactly where it started.

local SubjectModels = require(script.Parent.SubjectModels)

type SubjectRig = SubjectModels.SubjectRig
type Segment = SubjectModels.Segment
type Limbs = SubjectModels.Limbs

local SubjectMotion = {}

local TAU = math.pi * 2

-- What the scene knows about this instant. Everything below is derived from it,
-- so a scene never has to think about legs and this never has to think about
-- rooms.
export type Pose = {
	-- Where the feet are and which way the animal faces. Ground level, not hip
	-- level: the rig's own groundOffset is added here, not by the caller.
	root: CFrame,
	-- Total ground distance covered since the scene began. Drives the gait, which
	-- is why the feet cannot skate: they are a function of distance, not of time.
	traveled: number,
	-- Seconds since the scene began. Drives everything that happens while the
	-- animal is standing still, where there is no distance to key off.
	elapsed: number,
	moving: boolean,
	-- How much turn is still to make, signed radians, and only meaningful while
	-- standing. The head leads the body through a turn, which is what an animal
	-- does and what makes a turn read as a decision rather than as a rotation.
	turning: number,
	-- Whether the animal is lying down. A flag rather than a duration because the
	-- easing belongs here: the scene knows it wants a settled animal and this knows
	-- how long an animal takes to get down, which is the same division of labour the
	-- gait already uses.
	settled: boolean,
}

export type Motion = {
	apply: (Pose) -> (),
	-- Called before the model is destroyed. The model itself is the caller's.
	stop: () -> (),
}

-- Which clip plays when. The whole contract with a dropped-in model: name an
-- Animation "Walk" and it plays while walking. Two required names, no folder, no
-- Config entry -- because the thing most likely to go wrong with a bought model is
-- that whoever dropped it in did not read far enough.
local WALK_CLIP = "Walk"
local IDLE_CLIP = "Idle"
-- Optional third. A model without one settles by playing its idle, which looks
-- like an animal that decided not to lie down rather than like a broken scene --
-- so this stays a bonus rather than joining the two names above in the contract.
local REST_CLIP = "Rest"
local CLIP_FADE = 0.2

-- Gait shape. Cosmetic, and therefore local rather than Config, on exactly the
-- rule SubjectModels and ChoiceMarkers follow: nobody balances this game by
-- adjusting how far a tail swings, and putting it in Config would make it compete
-- for attention with the numbers people genuinely tune.
--
-- Everything that scales is a fraction of the animal's own dimensions, so a cat
-- trots like a cat rather than like a dog played at speed.

-- Steps per second for an animal whose legs are one stud long. Everything else
-- scales off it by the square root of leg length, because a leg is a pendulum and
-- a pendulum's frequency goes as one over the root of its length -- which is why
-- a terrier's legs blur and a wolfhound's do not, and why this is a law rather
-- than a taste.
--
-- Cadence rather than stride length is the number chosen here, and that ordering
-- matters. Sizing a stride off the geometry and letting the cadence fall out gives
-- the dog five steps a second at its authored walkSpeed and the cat eight, which
-- is not a trot, it is a blur. Sizing the cadence and letting the stride fall out
-- gives 2.8 and 4.5, which is a dog and a cat.
--
-- The cost is honest and is paid in the other direction: legs this short cannot
-- sweep as much ground as the animal covers, so a planted foot drifts forward by
-- roughly a fifth of the distance the body travels over it. Reducible only by
-- swinging the legs further, which is why LEG_SWING_DEGREES is at the top of the
-- plausible range rather than the middle. A model that arrives with its own walk
-- clip has whatever its author decided and none of this applies to it.
local CADENCE_AT_UNIT_LEG = 3.2
-- Floor under the derived stride, so a subject authored at walkSpeed zero cannot
-- divide the phase by nothing.
local MIN_STRIDE = 0.4
-- Floor under the leg length the cadence is derived from, for the same reason in
-- the other direction: a subject authored with no legs would take the root of zero
-- and step infinitely fast.
local MIN_LEG_LENGTH = 0.1

local LEG_SWING_DEGREES = 36
-- How far a leg picks up while it is swinging forward, as a fraction of its own
-- length. A rigid leg pivoting about the hip drags its foot along the floor for
-- the whole cycle, which is the thing that makes cheap quadrupeds look like
-- windscreen wipers. Lifting only on the forward half is a knee's worth of
-- correctness for one addition: the foot clears the ground going forward and is
-- planted going back, which is what a stride *is*.
local LEG_LIFT_FRACTION = 0.1
-- Seconds to fade the gait in and out. Without it a dog that stops walking snaps
-- its legs to attention mid-stride, which is the single most obvious tell that
-- something is being animated by a formula.
local GAIT_EASE_SECONDS = 0.22

-- Vertical bob of the body over a stride, as a fraction of shoulder height. Runs
-- at twice the leg frequency: a trot lifts the body as each diagonal pair passes
-- under it. Small on purpose -- the legs are doing the work and a body that
-- bounces reads as a cartoon.
local BODY_BOB_FRACTION = 0.022
-- Nod of the head over the same stride.
local HEAD_NOD_DEGREES = 4
-- Sway of the tail across a stride. Larger than the nod because a tail is the one
-- part of an animal that is allowed to be theatrical.
local TAIL_WALK_SWAY_DEGREES = 16

-- Breathing while standing: rise and fall of the body, as a fraction of shoulder
-- height, over this many seconds. Below the threshold of being noticed and well
-- above the threshold of being missed.
local BREATH_FRACTION = 0.012
local BREATH_SECONDS = 3.1

-- A slow drift of the head while standing, so a waiting animal is not a statue.
-- Deliberately not in time with the breathing: two idle motions on the same
-- period read as one mechanism.
local IDLE_HEAD_DEGREES = 3
local IDLE_HEAD_SECONDS = 5.3

-- An occasional flick of the tail while standing. The gap is randomized between
-- these bounds, which is the entire point -- anything on a metronome reads as a
-- machine, and this is the cheapest possible signal that the thing is alive.
local FLICK_DEGREES = 24
local FLICK_SECONDS = 0.75
local FLICK_GAP_MIN = 2.2
local FLICK_GAP_MAX = 6.5

-- How much of the body's remaining turn the head takes first, and the most it may
-- lead by. Capped because an unbounded lead lets the head swing right around when
-- the animal is asked to turn and face behind it.
local HEAD_LEAD = 0.5
local HEAD_LEAD_MAX_DEGREES = 32

-- Lying down. How far the hips drop, as a fraction of leg length -- and that
-- fraction is the only number chosen here, because the splay below is not a
-- choice: a rigid leg pivoting at the hip keeps its foot at a fixed radius, so
-- once the hip has dropped there is exactly one angle that leaves the foot on the
-- floor, and it is the arccosine of what is left. Picking the angle by eye instead
-- is how a lying animal ends up with its feet through the floorboards, which is
-- the same class of mistake as legs that skate.
--
-- Half. Enough to read as lying rather than crouching, and it is also the value
-- that brings the derived splay out at exactly sixty degrees -- worth having,
-- because a round splay is the quickest way to check by eye that the derivation is
-- still doing what it claims. Not further: a rigid leg has no knee, so past about
-- two thirds the splay gets wide enough that the animal looks like it has been
-- dropped rather than settled.
local SETTLE_DROP_FRACTION = 0.5
-- Seconds to get down and to get back up. Longer than the gait ease because
-- lying down is a decision and standing up is an effort, and neither is something
-- an animal does in a quarter of a second.
local SETTLE_SECONDS = 0.9
-- Biped-only: how far the arms swing, as a fraction of the leg swing. Gentler
-- than the legs -- arms that swing as far as the legs read as a march.
local ARM_SWING_FRACTION = 0.5
-- How far the head pitches forward for a right-answer nod. The settle flag drives
-- this the same way it drives the quadruped's lie-down: ease in, hold, ease out.
local BIPED_NOD_DEGREES = 22
-- How far the head comes down with the rest of it. Less than the body, so the
-- animal is still looking at you from the floor rather than asleep face-first.
local SETTLE_HEAD_DROP_DEGREES = 12
-- How much of the tail's motion is left once it is down. Not zero: a still tail
-- reads as an animal that has been switched off, and the whole reason the flick
-- exists is that this is the cheapest signal of being alive.
local SETTLE_TAIL_MOTION = 0.4
-- How much deeper it breathes lying down. The only motion left at that point, so
-- it is the one carrying the whole signal and is worth making visible.
local SETTLE_BREATH_SCALE = 1.8

-- Published because SceneService has to wait it out. An animal that is asked to
-- get up and starts walking in the same frame slides across the floor on its
-- side, which is precisely the failure this whole file exists to prevent -- so
-- the number lives here, next to what it describes, and the scene reads it.
SubjectMotion.SettleSeconds = SETTLE_SECONDS

-- The one primitive: put a segment where its pivot says, transformed about that
-- pivot, with every part back at its rest pose relative to it.
local function poseSegment(segment: Segment, base: CFrame, transform: CFrame)
	local at = base * segment.pivot * transform
	for index, part in segment.parts do
		part.CFrame = at * segment.rest[index]
	end
end

-- One leg at one point in the cycle. `phase` is where this leg is in its own
-- stride, so the two diagonal pairs are the same call half a cycle apart.
--
-- The angle is a plain sine: furthest forward at a quarter turn, furthest back at
-- three quarters. The lift is the derivative's sign -- cosine is positive exactly
-- while the leg is travelling forward -- so the foot is up through the swing and
-- down through the stance, and the two need no state to stay in agreement.
--
-- `bias` is a standing offset the stride swings around, which is how a settled
-- animal folds its front legs forward and its rear legs back without any of the
-- above needing to know it is lying down. Positive is forward: the model faces -Z,
-- and a positive rotation about X carries a leg hanging on -Y round toward -Z.
local function poseLeg(segment: Segment, base: CFrame, phase: number, swing: number, lift: number, bias: number)
	local angle = bias + swing * math.sin(phase)
	local raise = lift * math.max(0, math.cos(phase))
	poseSegment(segment, base, CFrame.new(0, raise, 0) * CFrame.Angles(angle, 0, 0))
end

-- The placeholder path: a trot computed from distance, and a set of small idle
-- motions for when there is no distance to compute from.
local function posedMotion(rig: SubjectRig, limbs: Limbs): Motion
	local model = rig.model
	-- Cadence first, stride second. The animal's pace is already fixed by its
	-- authored walkSpeed, so once we have decided how often it puts a foot down the
	-- stride is not a choice -- it is whatever length of step covers that pace at
	-- that rate. Deriving it in this order is what keeps the feet under the body.
	local cadence = CADENCE_AT_UNIT_LEG / math.sqrt(math.max(rig.legHeight, MIN_LEG_LENGTH))
	local stride = math.max(rig.subject.walkSpeed / cadence, MIN_STRIDE)
	local bobHeight = rig.subject.shoulderHeight * BODY_BOB_FRACTION
	local breathHeight = rig.subject.shoulderHeight * BREATH_FRACTION

	local swingLimit = math.rad(LEG_SWING_DEGREES)
	local legLift = rig.legHeight * LEG_LIFT_FRACTION
	local settleDrop = rig.legHeight * SETTLE_DROP_FRACTION
	-- Derived, not chosen: the foot sits one leg-length from the hip whatever the
	-- hip does, so this is the only angle that keeps it on the floor once the hip
	-- has dropped by settleDrop. Clamped because the fraction is authored above and
	-- a value past 1 would hand acos an argument it has no answer for.
	local settleSplay = math.acos(math.clamp(1 - SETTLE_DROP_FRACTION, -1, 1))
	local settleHeadDrop = math.rad(SETTLE_HEAD_DROP_DEGREES)
	local nodLimit = math.rad(HEAD_NOD_DEGREES)
	local swayLimit = math.rad(TAIL_WALK_SWAY_DEGREES)
	local idleHeadLimit = math.rad(IDLE_HEAD_DEGREES)
	local flickLimit = math.rad(FLICK_DEGREES)
	local leadLimit = math.rad(HEAD_LEAD_MAX_DEGREES)

	local biped = rig.subject.biped == true

	local random = Random.new()
	-- How much of the walk cycle is currently showing, 0 to 1. Eased rather than
	-- switched, which is what stops the legs snapping when the animal arrives.
	local gait = 0
	-- How far down it is, 0 to 1, eased on exactly the same terms and for exactly
	-- the same reason: an animal that snaps to the floor has not lain down, it has
	-- been teleported into a different shape.
	local settle = 0
	-- A flag rather than an optional last-time, because the last time is written
	-- from inside apply() and a nil-check on a value a closure assigns to is not
	-- something the typechecker is willing to narrow.
	local started = false
	local lastElapsed = 0
	local nextFlickAt = random:NextNumber(FLICK_GAP_MIN, FLICK_GAP_MAX)
	local flickStartedAt = -math.huge

	local function apply(pose: Pose)
		-- Derived rather than passed, so a caller cannot get the two out of step. A
		-- first frame has no previous one and therefore no elapsed time, which is
		-- correct: nothing should have eased anywhere yet.
		local delta = if started then math.max(0, pose.elapsed - lastElapsed) else 0
		started = true
		lastElapsed = pose.elapsed

		local wanted = if pose.moving then 1 else 0
		local step = if GAIT_EASE_SECONDS > 0 then delta / GAIT_EASE_SECONDS else 1
		gait += math.clamp(wanted - gait, -step, step)

		local wantedSettle = if pose.settled then 1 else 0
		local settleStep = if SETTLE_SECONDS > 0 then delta / SETTLE_SECONDS else 1
		settle += math.clamp(wantedSettle - settle, -settleStep, settleStep)

		local phase = pose.traveled / stride * TAU

		-- Moves everything that is not posed below -- which is only the invisible
		-- root, but that root is what GetPivot reads, so the model would otherwise
		-- report that it had never left the spot it spawned on.
		model:PivotTo(pose.root)

		-- Two beats per stride while walking, easing into a slow breath as it stops,
		-- and into a deeper one as it goes down. Breathing is the only motion left on
		-- a settled animal, so it is carrying the whole "this is alive" signal by
		-- itself and is worth a little more amplitude to do it with. Biped never
		-- settles down -- the settle flag means "nod" for a teacher, not "lie down".
		local drop = if biped then 0 else settleDrop * settle
		local walkBob = bobHeight * (0.5 - 0.5 * math.cos(phase * 2))
		local breathScale = 1 + (SETTLE_BREATH_SCALE - 1) * settle
		local breath = breathHeight * breathScale * (0.5 - 0.5 * math.cos(pose.elapsed / BREATH_SECONDS * TAU))
		local body = pose.root * CFrame.new(0, walkBob * gait + breath * (1 - gait) - drop, 0)
		poseSegment(limbs.body, body, CFrame.identity)

		-- A trot: the diagonal pairs swing together and the two pairs oppose. Legs
		-- ride the ground rather than the body, so the bob above never lifts a foot
		-- off the floor -- only the swing does, and only on the half of the cycle
		-- where a foot is meant to be off it.
		--
		-- The settle is the one exception, and has to be: the hips really do come
		-- down, so the legs are hung off a base that drops with them and splayed by
		-- exactly enough to leave the feet where they were. Front legs fold forward
		-- and rear legs back, which is the shape of a dog on a floor.
		local hips = if drop > 0 then pose.root * CFrame.new(0, -drop, 0) else pose.root
		local splay = if biped then 0 else settleSplay * settle
		local swing = swingLimit * gait
		local lift = legLift * gait
		poseLeg(limbs.legs.frontLeft, hips, phase, swing, lift, splay)
		poseLeg(limbs.legs.frontRight, hips, phase + math.pi, swing, lift, splay)
		if not biped then
			poseLeg(limbs.legs.rearRight, hips, phase, swing, lift, -splay)
			poseLeg(limbs.legs.rearLeft, hips, phase + math.pi, swing, lift, -splay)
		end

		-- Biped arms swing opposite their ipsilateral leg. Gentler than the legs:
		-- arms that match the leg amplitude read as a march.
		if biped and limbs.arms ~= nil then
			local armSwing = swing * ARM_SWING_FRACTION
			poseSegment(limbs.arms.left, body, CFrame.Angles(armSwing * math.sin(phase + math.pi), 0, 0))
			poseSegment(limbs.arms.right, body, CFrame.Angles(armSwing * math.sin(phase), 0, 0))
		end

		local nod = nodLimit * gait * math.sin(phase * 2 + math.pi)
		local drift = idleHeadLimit * (1 - gait) * math.sin(pose.elapsed / IDLE_HEAD_SECONDS * TAU)
		local lead = math.clamp(pose.turning * HEAD_LEAD, -leadLimit, leadLimit) * (1 - gait)
		-- Subtracted, because the head reaches along -Z from the neck and a positive
		-- rotation about X lifts the snout. For a biped the settle is a nod (pitch
		-- forward), not a lie-down, so the angle is larger and keeps the face toward
		-- the player rather than toward the floor.
		local headSettle = if biped
			then math.rad(BIPED_NOD_DEGREES) * settle
			else settleHeadDrop * settle
		poseSegment(limbs.head, body, CFrame.Angles(nod - headSettle, drift + lead, 0))

		-- Tail: invisible on bipeds, fully posed on quadrupeds. Flicks are only
		-- scheduled while standing, so an animal that walks in without stopping
		-- never banks a flick to spend the moment it arrives.
		if not biped then
			if not pose.moving then
				if pose.elapsed >= nextFlickAt then
					flickStartedAt = pose.elapsed
					nextFlickAt = pose.elapsed + random:NextNumber(FLICK_GAP_MIN, FLICK_GAP_MAX)
				end
			else
				nextFlickAt = pose.elapsed + random:NextNumber(FLICK_GAP_MIN, FLICK_GAP_MAX)
			end

			local flick = 0
			local sinceFlick = pose.elapsed - flickStartedAt
			if sinceFlick >= 0 and sinceFlick < FLICK_SECONDS then
				-- A couple of beats, dying away. A flick that ends abruptly looks like a
				-- dropped frame rather than like a tail coming to rest.
				local progress = sinceFlick / FLICK_SECONDS
				flick = flickLimit * math.sin(progress * TAU * 2) * (1 - progress)
			end

			-- Damped rather than stopped as it goes down. A tail that stops dead reads as
			-- an animal that has been switched off, which is the opposite of what lying
			-- down is meant to say.
			local stillness = 1 - (1 - SETTLE_TAIL_MOTION) * settle
			local sway = (swayLimit * gait * math.sin(phase) + flick * (1 - gait)) * stillness
			poseSegment(limbs.tail, body, CFrame.Angles(0, sway, 0))
		end
	end

	return {
		apply = apply,
		-- Nothing is playing and nothing is connected: every frame is written by
		-- the caller's own loop, so there is nothing here to unwind. Present because
		-- the caller must not have to know which of the two motions it got.
		stop = function() end,
	}
end

-- The adopted-model path: place it, and pick the clip.
local function clipMotion(rig: SubjectRig): Motion
	local model = rig.model
	local animator = rig.animator
	-- The rig's own root is somewhere around the hips rather than between the
	-- feet, so a pose that puts feet on the floor has to be lifted to reach it.
	local lift = CFrame.new(0, rig.groundOffset, 0)

	local function load(name: string): AnimationTrack?
		local clip = rig.clips[name]
		if animator == nil or clip == nil then
			return nil
		end
		-- Rebound as non-optional before the pcall rather than relied on through the
		-- check above: the pcall body is a closure, and a nil-check refinement does
		-- not survive being captured by one.
		local host: Animator = animator
		local wanted: Animation = clip
		local ok, track = pcall(function()
			return host:LoadAnimation(wanted)
		end)
		if not ok or track == nil then
			warn(`[AGES] subject model "{model.Name}" could not load its "{name}" animation`)
			return nil
		end
		track.Looped = true
		return track
	end

	local walk = load(WALK_CLIP)
	local idle = load(IDLE_CLIP)
	local rest = load(REST_CLIP)
	local playing: AnimationTrack? = nil

	local function play(track: AnimationTrack?)
		if track == playing then
			return
		end
		if playing ~= nil then
			playing:Stop(CLIP_FADE)
		end
		playing = track
		if track ~= nil then
			track:Play(CLIP_FADE)
		end
	end

	return {
		apply = function(pose: Pose)
			model:PivotTo(pose.root * lift)
			-- Falls back to whichever clip exists. A model that shipped one animation
			-- should play it rather than stand frozen because the other name is
			-- missing -- the alternative is a silent nothing that looks like a bug in
			-- this file.
			--
			-- Moving wins over settled, which only matters for the frames either side
			-- of getting up: a walk that started while the rest clip was still fading
			-- would have the animal travelling on its side.
			if pose.moving then
				play(walk or idle)
			elseif pose.settled then
				play(rest or idle or walk)
			else
				play(idle or walk)
			end
		end,
		stop = function()
			play(nil)
		end,
	}
end

-- Binds a motion to a rig. Which of the two implementations comes back is not
-- something any caller may ask, and nothing in the interface differs between
-- them: a scene walks an animal in the same way whether the legs are being posed
-- here or by a clip somebody uploaded.
function SubjectMotion.Attach(rig: SubjectRig): Motion
	local limbs = rig.limbs
	if limbs ~= nil then
		return posedMotion(rig, limbs)
	end
	return clipMotion(rig)
end

return SubjectMotion
