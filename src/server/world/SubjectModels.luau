--!strict
-- What a subject looks like when it is standing in the room, and which of its
-- parts can be moved. SceneService decides where the subject goes and when it
-- leaves, SubjectMotion decides how it carries itself while it is there, and this
-- decides what turns up and what there is to animate.
--
-- Same split, and for the same reason, as EnactService/Interact and
-- DeliveryService/DeliveryPresenters: retuning how close the animal comes never
-- touches its geometry, retuning its gait never touches its proportions, and
-- replacing all of it with a bought model never touches the placement math.
--
-- Two sources, in the order they are tried:
--
--   A real Model, named after the subject id, inside the ServerStorage folder
--   Config.World.SubjectFolder names. This is the seam for a Toolbox dog: drop
--   it in, name it "dog", and nothing in code moves.
--
--   Otherwise a placeholder built from parts out of the subject's own
--   dimensions. Not a cube with a label on it -- a legible four-legged animal of
--   the right size, for the reason NPCService builds visitors from body scales
--   rather than waiting on asset ids. A subject that is the correct height and
--   arrives at the correct moment is already most of the event; the fur is the
--   part that can wait.
--
-- What comes back is a rig rather than a Model, which is the whole difference
-- between this version and the one before it. A Model can only be slid around; a
-- rig names the pieces -- four legs by corner, a head, a tail -- so the thing can
-- walk. The two sources answer that question differently and deliberately: the
-- placeholder hands over its own parts to be posed, and an adopted model hands
-- over its Animator and whatever clips it shipped with, because somebody else's
-- geometry is not ours to take apart and guess at.
--
-- Anchoring is load-bearing and is the one rule that differs between the two.
-- Nothing here may be knocked over, shoved through a wall or dropped through a
-- floor, and nothing here is ever pushed, so a static model is anchored outright.
-- A model that brought animations cannot be: an animation drives limbs through
-- Motor6Ds, and an anchored limb ignores its motor. Those get their root anchored
-- and their limbs left to the motors, which pins the animal in place just as hard
-- while leaving it able to move.
--
-- Non-collidable throughout, and invisible to raycasts and region queries. Both
-- matter: an enacted event fans its choices across the floor and the subject must
-- never be the thing standing between the player and one of them, and a subject
-- that answered probes would be reported as furniture by Ground -- including by
-- the probes that run for the *next* event while this one is still standing there.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type SceneSubject = Types.SceneSubject

local SubjectModels = {}

-- One group of parts that moves as a piece about a single point: a leg about its
-- hip, the head about the neck, the tail about its base.
--
-- Rest poses are stored relative to that pivot, captured once at build time.
-- Nothing ever reads a part's live CFrame afterwards, which is what stops a pose
-- from accumulating error -- every frame is computed from the rest pose rather
-- than from the frame before it, so a hundred thousand frames of tail wag leave
-- the tail exactly where it started.
export type Segment = {
	parts: { BasePart },
	-- Parallel to `parts`: rest[i] is where parts[i] sits relative to `pivot`.
	rest: { CFrame },
	-- In the model's own frame, which has the feet at y = 0 and faces -Z.
	pivot: CFrame,
}

-- Named rather than indexed, because a gait is written in terms of which leg --
-- a trot moves the diagonal pairs together -- and `legs[2]` in that sentence
-- would be a comment waiting to go stale. Left and right are the animal's own:
-- it faces -Z, so its left is +X.
export type Legs = {
	frontLeft: Segment,
	frontRight: Segment,
	rearLeft: Segment,
	rearRight: Segment,
}

export type Limbs = {
	-- The torso. Carries the head and the tail, so a bob applied here moves all
	-- three and only the legs stay on the ground.
	body: Segment,
	-- Head, snout, nose, ears and eyes together: they are one rigid thing and
	-- there is nothing to be gained from being able to waggle an ear on its own.
	head: Segment,
	tail: Segment,
	legs: Legs,
	-- A biped's arms, hanging from the shoulders. Nil for a quadruped, which
	-- has no equivalent part to pose. The gait reads this to decide whether
	-- to swing arms opposite the legs.
	arms: { left: Segment, right: Segment }?,
}

export type SubjectRig = {
	model: Model,
	subject: SceneSubject,
	-- How far the model's pivot sits above the floor it is standing on. Zero for
	-- anything with a root put in deliberately; nonzero only for an animated model
	-- whose own root part we had to keep, which is usually somewhere around the
	-- hips. Callers add it when placing, so a rigged dog's feet land on the floor
	-- in the same call that lands the placeholder's.
	groundOffset: number,
	-- Length of a leg, which is the one geometric fact a gait needs and cannot
	-- work out for itself. Reported rather than recomputed so the stride matches
	-- the animal that was actually built.
	legHeight: number,
	-- The placeholder's own parts, posable frame by frame. Nil for a model
	-- somebody else built: we know where its feet are and nothing else.
	limbs: Limbs?,
	-- An adopted model's animation driver and whatever clips it shipped with,
	-- keyed by Animation name. Nil and empty for the placeholder.
	animator: Animator?,
	clips: { [string]: Animation },
}

-- Cosmetic proportions, kept out of Config for the reason ChoiceMarkers gives:
-- the fraction of a dog that is leg is not a number anyone balances the game
-- with, and putting it in Config makes it compete for attention with the numbers
-- that are. The numbers that *are* authored -- how tall, how long, how fast --
-- live on the subject in content and arrive as arguments.
--
-- All of these are fractions of the subject's own dimensions, so a cat is a cat
-- and not a shrunken dog.
local LEG_FRACTION = 0.5 -- of shoulder height; the rest is torso, so the back lands exactly on it
local TORSO_LENGTH_FRACTION = 0.62 -- of body length; the remainder is head at one end and tail at the other
local LEG_THICKNESS_FRACTION = 0.28 -- of body width
local LEG_INSET_FRACTION = 0.18 -- of body width, in from each side and end
local PAW_LENGTH_FRACTION = 1.4 -- of leg thickness; a foot is longer than the leg above it
local PAW_HEIGHT_FRACTION = 0.45 -- of leg thickness
local HEAD_FRACTION = 0.95 -- of body width, cubed
local HEAD_DROP_FRACTION = 0.08 -- of shoulder height, below the line of the back
local SNOUT_FRACTION = 0.5 -- of head size
local NOSE_FRACTION = 0.34 -- of snout size
local EAR_FRACTION = 0.32 -- of head size
local EYE_FRACTION = 0.17 -- of head size
local TAIL_FRACTION = 0.3 -- of body length
local TAIL_THICKNESS_FRACTION = 0.2 -- of body width
local TAIL_TIP_FRACTION = 0.28 -- of tail length

-- Biped proportions. A human is not a dog stood on end: two legs, two arms and a
-- head that sits upright on top of a torso rather than poking out of its front.
local BIPED_LEG_SPREAD_FRACTION = 0.25 -- of body width, half the shoulder span
local ARM_FRACTION = 0.42 -- of shoulder height; wrist to shoulder
local ARM_THICKNESS_FRACTION = 0.16 -- of body width
-- The nod angle is deliberately *not* here. It sat here as a second `BIPED_NOD_DEGREES = 22`,
-- identical to the live one in `SubjectMotion` and read by nobody -- this module builds the
-- rig, that one moves it, and an angle is motion. Two copies of one number in two modules is
-- the shape a silent drift starts in: nobody edits both, and the copy nobody edits is the one
-- that looks authoritative to whoever reads this file next.

-- How far the tail is carried above the line of the back at rest. A tail held
-- level reads as a plank and one held down reads as a cowed animal; a little up
-- is the neutral, interested carriage the prompt describes.
local TAIL_LIFT_DEGREES = 18
-- Ears tipped out and back rather than standing straight up, which reads alert
-- without reading startled.
local EAR_OUT_DEGREES = 16
local EAR_BACK_DEGREES = 10

-- The root is a marker, not a body part: it exists so that the model's pivot sits
-- between the animal's feet, which is what lets a caller place it with a single
-- PivotTo onto a point the floor probe returned.
local ROOT_SIZE = Vector3.new(0.2, 0.2, 0.2)

local function newPart(model: Model, name: string, size: Vector3, at: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = at
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	-- Invisible to raycasts and region queries, which is what keeps a subject from
	-- being reported as furniture by the floor and clearance probes in Ground --
	-- including the ones that would run for the *next* event while this one is
	-- still standing there.
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = model
	return part
end

-- Everything is built at the origin in the model's own frame, so a part's CFrame
-- at this moment *is* its rest pose and there is nothing to measure.
local function segmentOf(pivot: CFrame, parts: { BasePart }): Segment
	local inverse = pivot:Inverse()
	local rest: { CFrame } = {}
	for index, part in parts do
		rest[index] = inverse * part.CFrame
	end
	return { parts = parts, rest = rest, pivot = pivot }
end

-- A leg and the foot on the end of it, pivoting about the hip. Not about the
-- middle, which scissors the foot through the floor, and not about the foot,
-- which lifts the whole animal off it.
local function buildLeg(
	model: Model,
	name: string,
	hipX: number,
	hipZ: number,
	legHeight: number,
	thickness: number,
	subject: SceneSubject
): Segment
	local leg = newPart(
		model,
		name,
		Vector3.new(thickness, legHeight, thickness),
		CFrame.new(hipX, legHeight / 2, hipZ),
		subject.color
	)

	local pawHeight = thickness * PAW_HEIGHT_FRACTION
	local pawLength = thickness * PAW_LENGTH_FRACTION
	local paw = newPart(
		model,
		`{name}Paw`,
		Vector3.new(thickness * 1.1, pawHeight, pawLength),
		-- Set forward of the leg it hangs off, because a foot sticks out in front
		-- of the ankle and one centered under the leg reads as a stilt.
		CFrame.new(hipX, pawHeight / 2, hipZ - (pawLength - thickness) / 2),
		subject.accentColor
	)

	return segmentOf(CFrame.new(hipX, legHeight, hipZ), { leg, paw })
end

-- A single invisible part satisfying the Segment type, used for the parts a
-- biped does not need but the gait still references.
local function invisibleSegment(model: Model, name: string, at: CFrame): Segment
	local part = newPart(model, name, Vector3.new(0.01, 0.01, 0.01), at, Color3.new(1, 1, 1))
	part.Transparency = 1
	part.CastShadow = false
	return segmentOf(at, { part })
end

-- A four-legged animal, facing -Z, with its feet at y = 0 and the top of its back
-- at exactly shoulderHeight. Built at the origin and moved afterwards, so the
-- arithmetic below is all in the subject's own frame.
local function buildPlaceholder(subject: SceneSubject): (Model, Limbs, number)
	local model = Instance.new("Model")

	local height = subject.shoulderHeight
	local length = subject.bodyLength
	local width = subject.bodyWidth

	local legHeight = height * LEG_FRACTION
	local torsoHeight = height - legHeight
	local torsoLength = length * TORSO_LENGTH_FRACTION
	local torsoCenterY = legHeight + torsoHeight / 2

	local torso = newPart(
		model,
		"Torso",
		Vector3.new(width, torsoHeight, torsoLength),
		CFrame.new(0, torsoCenterY, 0),
		subject.color
	)
	local body = segmentOf(CFrame.new(0, torsoCenterY, 0), { torso })

	local legThickness = width * LEG_THICKNESS_FRACTION
	local legInset = width * LEG_INSET_FRACTION
	local legX = width / 2 - legInset
	local legZ = torsoLength / 2 - legInset
	-- Facing -Z with +Y up makes the animal's own left +X, so front-left is
	-- (+X, -Z). Getting this backwards would put the trot on the wrong diagonal,
	-- which looks subtly wrong in a way that is very hard to find later.
	local legs: Legs = {
		frontLeft = buildLeg(model, "LegFrontLeft", legX, -legZ, legHeight, legThickness, subject),
		frontRight = buildLeg(model, "LegFrontRight", -legX, -legZ, legHeight, legThickness, subject),
		rearLeft = buildLeg(model, "LegRearLeft", legX, legZ, legHeight, legThickness, subject),
		rearRight = buildLeg(model, "LegRearRight", -legX, legZ, legHeight, legThickness, subject),
	}

	-- Held at the front and a little below the line of the back, which is where a
	-- dog carries its head when it has noticed you and has not decided about you
	-- yet. Level would read as a statue and raised would read as a howl.
	--
	-- The head's back face lands exactly on the torso's front face, so there is no
	-- neck to build and no gap to hide.
	local headSize = width * HEAD_FRACTION
	local headY = height - height * HEAD_DROP_FRACTION
	local headZ = -(torsoLength / 2 + headSize / 2)
	local neck = CFrame.new(0, headY, -torsoLength / 2)

	local headParts: { BasePart } = {}
	table.insert(
		headParts,
		newPart(model, "Head", Vector3.new(headSize, headSize, headSize), CFrame.new(0, headY, headZ), subject.color)
	)

	local snoutSize = headSize * SNOUT_FRACTION
	local snoutY = headY - headSize * 0.2
	local snoutZ = headZ - headSize / 2 - snoutSize / 2
	table.insert(
		headParts,
		newPart(
			model,
			"Snout",
			Vector3.new(snoutSize, snoutSize, snoutSize),
			CFrame.new(0, snoutY, snoutZ),
			subject.accentColor
		)
	)

	-- A ball rather than a box, and worth the one extra part: the nose is the only
	-- round thing on the animal and it is what stops the face reading as a crate.
	local noseSize = snoutSize * NOSE_FRACTION
	local nose = newPart(
		model,
		"Nose",
		Vector3.new(noseSize, noseSize, noseSize),
		CFrame.new(0, snoutY + snoutSize * 0.1, snoutZ - snoutSize / 2),
		subject.accentColor
	)
	nose.Shape = Enum.PartType.Ball
	table.insert(headParts, nose)

	local earSize = headSize * EAR_FRACTION
	for _, side in { -1, 1 } do
		table.insert(
			headParts,
			newPart(
				model,
				"Ear",
				Vector3.new(earSize * 0.35, earSize, earSize * 0.7),
				-- Both signs are easy to get backwards and both are checkable. About X,
				-- the top of an upright part moves to z = +sin(theta), so a positive
				-- angle tips it back. About Z it moves to x = -sin(theta), so the angle
				-- that tips it *out* is the negation of the side it is on.
				CFrame.new(side * headSize * 0.32, headY + headSize / 2 + earSize * 0.4, headZ + headSize * 0.1)
					* CFrame.Angles(math.rad(EAR_BACK_DEGREES), 0, math.rad(-side * EAR_OUT_DEGREES)),
				subject.accentColor
			)
		)
	end

	-- Two dark spheres. Out of all proportion to their cost: they are the
	-- difference between a shape facing you and something looking at you, which is
	-- the entire claim the prompt makes.
	local eyeSize = headSize * EYE_FRACTION
	for _, side in { -1, 1 } do
		local eye = newPart(
			model,
			"Eye",
			Vector3.new(eyeSize, eyeSize, eyeSize),
			-- Set into the face rather than onto it, so the sphere reads as an eye
			-- in a socket instead of a bead glued to a box.
			CFrame.new(side * headSize * 0.3, headY + headSize * 0.14, headZ - headSize / 2 + eyeSize * 0.25),
			subject.accentColor
		)
		eye.Shape = Enum.PartType.Ball
		table.insert(headParts, eye)
	end

	local head = segmentOf(neck, headParts)

	local tailLength = length * TAIL_FRACTION
	local tailThickness = width * TAIL_THICKNESS_FRACTION
	local tailBase = CFrame.new(0, height - tailThickness, torsoLength / 2)
	-- Negative pitch about X lifts the far end: rotating (0, 0, +L) about X by
	-- theta gives y = -sin(theta) * L, so the tail rises only when theta is below
	-- zero. Easy to get backwards and immediately obvious when it is.
	local tailPose = tailBase * CFrame.Angles(math.rad(-TAIL_LIFT_DEGREES), 0, 0)
	local tailParts: { BasePart } = {
		newPart(
			model,
			"Tail",
			Vector3.new(tailThickness, tailThickness, tailLength),
			tailPose * CFrame.new(0, 0, tailLength / 2),
			subject.color
		),
	}
	local tipLength = tailLength * TAIL_TIP_FRACTION
	table.insert(
		tailParts,
		newPart(
			model,
			"TailTip",
			Vector3.new(tailThickness * 1.05, tailThickness * 1.05, tipLength),
			tailPose * CFrame.new(0, 0, tailLength - tipLength / 2),
			subject.accentColor
		)
	)
	local tail = segmentOf(tailBase, tailParts)

	local root = newPart(model, "SubjectRoot", ROOT_SIZE, CFrame.new(0, 0, 0), subject.color)
	root.Transparency = 1
	root.CastShadow = false
	model.PrimaryPart = root

	local limbs: Limbs = { body = body, head = head, tail = tail, legs = legs }
	return model, limbs, legHeight
end

-- A two-legged human figure, facing -Z, feet at y = 0 and the top of the
-- shoulders at shoulderHeight. Built for the teacher: two legs, a torso, a head
-- with eyes and two arms. The rear legs and tail are built invisible so the
-- four-corner rig shape holds and the gait can skip them cleanly.
local function buildBipedPlaceholder(subject: SceneSubject): (Model, Limbs, number)
	local model = Instance.new("Model")

	local height = subject.shoulderHeight
	local length = subject.bodyLength
	local width = subject.bodyWidth

	local legHeight = height * LEG_FRACTION
	local torsoHeight = height - legHeight
	local torsoCenterY = legHeight + torsoHeight / 2

	local torso = newPart(
		model,
		"Torso",
		Vector3.new(width, torsoHeight, length),
		CFrame.new(0, torsoCenterY, 0),
		subject.color
	)
	local body = segmentOf(CFrame.new(0, torsoCenterY, 0), { torso })

	local legThickness = width * LEG_THICKNESS_FRACTION
	local legX = width / 2 - width * BIPED_LEG_SPREAD_FRACTION
	local legZ = 0
	local legs: Legs = {
		frontLeft = buildLeg(model, "LegFrontLeft", legX, legZ, legHeight, legThickness, subject),
		frontRight = buildLeg(model, "LegFrontRight", -legX, legZ, legHeight, legThickness, subject),
		rearLeft = invisibleSegment(model, "LegRearLeft", CFrame.new(legX, legHeight / 2, legZ)),
		rearRight = invisibleSegment(model, "LegRearRight", CFrame.new(-legX, legHeight / 2, legZ)),
	}

	-- Head sits on top of the shoulders, facing -Z. Box and eyes only: a
	-- teacher's face is the last place to be wrong, so the shape is kept to
	-- the parts that read unambiguously as human.
	local headSize = width * HEAD_FRACTION
	local headY = height + headSize / 2 - headSize * 0.18
	local headZ = -length / 2 + headSize * 0.1
	local neck = CFrame.new(0, height - headSize * 0.05, headZ)
	local headParts: { BasePart } = {
		newPart(model, "Head", Vector3.new(headSize, headSize, headSize), CFrame.new(0, headY, headZ), subject.color),
	}
	local eyeSize = headSize * EYE_FRACTION
	for _, side in { -1, 1 } do
		local eye = newPart(
			model,
			"Eye",
			Vector3.new(eyeSize, eyeSize, eyeSize),
			CFrame.new(side * headSize * 0.28, headY + headSize * 0.05, headZ - headSize / 2 + eyeSize * 0.3),
			subject.accentColor
		)
		eye.Shape = Enum.PartType.Ball
		table.insert(headParts, eye)
	end
	local head = segmentOf(neck, headParts)

	-- Arms hang from the shoulders, pivoting at the shoulder joint. They swing
	-- opposite the legs during a walk, which is what sells the gait as a person
	-- rather than a puppet whose limbs forgot they were attached.
	local armThickness = width * ARM_THICKNESS_FRACTION
	local armLength = height * ARM_FRACTION
	local armX = width / 2 + armThickness * 0.4
	local armY = height - armLength / 2
	local function buildArm(name: string, side: number): Segment
		local at = CFrame.new(side * armX, armY, 0)
		return segmentOf(at, {
			newPart(model, name, Vector3.new(armThickness, armLength, armThickness), at, subject.accentColor),
		})
	end
	local arms: { left: Segment, right: Segment } = {
		left = buildArm("ArmLeft", 1),
		right = buildArm("ArmRight", -1),
	}

	-- Tail: absent for a person. Built invisible so the rig shape holds.
	local tail = invisibleSegment(model, "Tail", CFrame.new(0, height - 0.2, length / 2))

	local root = newPart(model, "SubjectRoot", ROOT_SIZE, CFrame.new(0, 0, 0), subject.color)
	root.Transparency = 1
	root.CastShadow = false
	model.PrimaryPart = root

	local limbs: Limbs = { body = body, head = head, tail = tail, legs = legs, arms = arms }
	return model, limbs, legHeight
end

-- Whatever will actually play an AnimationTrack on this model, creating the
-- Animator if the model brought a Humanoid or an AnimationController without one
-- -- which is common, because an Animator is normally added at runtime by the
-- engine and a model sitting in ServerStorage has never run.
local function findAnimator(model: Model): Animator?
	local host: Instance? = model:FindFirstChildWhichIsA("Humanoid", true)
	if host == nil then
		host = model:FindFirstChildWhichIsA("AnimationController", true)
	end
	if host == nil then
		return nil
	end

	local existing = host:FindFirstChildWhichIsA("Animator")
	if existing ~= nil then
		return existing :: Animator
	end
	local animator = Instance.new("Animator")
	animator.Parent = host
	return animator
end

-- Every Animation anywhere in the model, keyed by its name. Deliberately not
-- looked for in a folder with a fixed name: the contract is "call an Animation
-- Walk and it plays while walking", which is one thing to remember rather than
-- two, and it survives whatever folder structure the model arrived with.
local function collectClips(model: Model): { [string]: Animation }
	local clips: { [string]: Animation } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Animation") then
			clips[descendant.Name] = descendant
		end
	end
	return clips
end

-- The part an animated model is driven from. Its own PrimaryPart if it set one,
-- otherwise the conventional name, otherwise the largest part -- which is a guess
-- but a good one, since the piece a rig hangs off is rarely the smallest.
local function driverPart(model: Model): BasePart?
	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end
	local named = model:FindFirstChild("HumanoidRootPart")
	if named ~= nil and named:IsA("BasePart") then
		return named
	end

	local best: BasePart? = nil
	local bestVolume = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local size = descendant.Size
			local volume = size.X * size.Y * size.Z
			if volume > bestVolume then
				best = descendant
				bestVolume = volume
			end
		end
	end
	return best
end

-- A hand-made model has its own idea of where its origin is, and it is usually
-- not between the animal's feet. Rather than asking whoever drops one in to get
-- that right, the bottom of its bounding box is measured and the difference is
-- reported as groundOffset -- so a Toolbox dog places identically to the
-- placeholder and the caller never learns which one it got.
local function adoptModel(source: Model, subject: SceneSubject): SubjectRig?
	local model = source:Clone()

	local ok, boxCFrame, boxSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or boxCFrame == nil or boxSize == nil then
		warn(`[AGES] subject model "{source.Name}" has no parts to measure; using the placeholder instead`)
		model:Destroy()
		return nil
	end

	local animator = findAnimator(model)
	local clips = collectClips(model)
	-- Animated only if it can *both* drive a clip and has one to drive. Either one
	-- alone is a model that will stand still, and standing still is exactly what
	-- the anchored path does better.
	local animated = animator ~= nil and next(clips) ~= nil
	local driver = if animated then driverPart(model) else nil
	if animated and driver == nil then
		warn(`[AGES] subject model "{source.Name}" has animations but no part to drive them from; anchoring it instead`)
		animated = false
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			-- An animated limb must stay unanchored or its motor cannot move it. It
			-- does not fall: a Motor6D chain hanging off an anchored root is one rigid
			-- assembly as far as the physics engine is concerned.
			descendant.Anchored = not animated or descendant == driver
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end

	local bottom = boxCFrame.Position.Y - boxSize.Y / 2

	if animated and driver ~= nil then
		model.PrimaryPart = driver
		return {
			model = model,
			subject = subject,
			groundOffset = driver.Position.Y - bottom,
			-- Only used to size a stride, which an animated model does not need
			-- because its clip already has one. Reported honestly all the same.
			legHeight = subject.shoulderHeight * LEG_FRACTION,
			limbs = nil,
			animator = animator,
			clips = clips,
		}
	end

	local root = Instance.new("Part")
	root.Name = "SubjectRoot"
	root.Size = ROOT_SIZE
	root.CFrame = CFrame.new(Vector3.new(boxCFrame.Position.X, bottom, boxCFrame.Position.Z))
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	return {
		model = model,
		subject = subject,
		groundOffset = 0,
		legHeight = subject.shoulderHeight * LEG_FRACTION,
		limbs = nil,
		animator = nil,
		clips = {},
	}
end

local function authoredModel(subjectId: string): Model?
	local folder = ServerStorage:FindFirstChild(Config.World.SubjectFolder)
	if folder == nil then
		return nil
	end
	local found = folder:FindFirstChild(subjectId)
	if found == nil then
		return nil
	end
	if not found:IsA("Model") then
		warn(`[AGES] "{subjectId}" in {Config.World.SubjectFolder} is a {found.ClassName}, not a Model; using the placeholder`)
		return nil
	end
	return found
end

-- Builds the subject, unparented and unplaced. Its pivot sits between its feet
-- once groundOffset is added and it faces -Z, so the caller places it with one
-- PivotTo onto a point the floor probe returned.
function SubjectModels.Build(subject: SceneSubject): SubjectRig
	local authored = authoredModel(subject.id)
	if authored ~= nil then
		local adopted = adoptModel(authored, subject)
		if adopted ~= nil then
			adopted.model.Name = `Subject_{subject.id}`
			return adopted
		end
	end

	local model, limbs, legHeight = if subject.biped then buildBipedPlaceholder(subject) else buildPlaceholder(subject)
	model.Name = `Subject_{subject.id}`
	return {
		model = model,
		subject = subject,
		groundOffset = 0,
		legHeight = legHeight,
		limbs = limbs,
		animator = nil,
		clips = {},
	}
end

return SubjectModels
