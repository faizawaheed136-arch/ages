--!strict
-- Visitors. Builds a real R15 avatar for a member of the cast, walks them in
-- from the doorstep, has them look at the player while they wait, and walks them
-- back out afterwards.
--
-- Three layers, in order of how much they cost to have:
--
--   Body       HumanoidDescription scales and colors. Needs no asset ids at all,
--              so a visitor is a properly proportioned person from the very
--              first run rather than a placeholder waiting on a shopping trip.
--   Motion     Two of them, and the caller picks. `walkTo` is a straight line via
--              Humanoid:MoveTo, which is right for a visitor crossing an empty
--              hallway to a spot chosen to be reachable. `pathTo` asks
--              PathfindingService for a route and walks it waypoint by waypoint,
--              which is what a townsperson crossing a built world needs -- a
--              straight line there walks into the first wall it meets and gives up.
--   Expression Looped idle/walk plus one-shot greet and talk clips, driven from
--              Config.Assets.Animations, procedural head tracking, and turning on
--              the spot to face somebody.
--
-- Head tracking is the part worth understanding. It is the single largest
-- difference between a mannequin and a person, and it costs nothing: no asset,
-- no upload, just the neck joint re-aimed a few times a second. So it runs even
-- while every animation id above is still empty, and it is what carries the
-- scene until they are filled in.
--
-- `face` is the same argument one level down the body. The neck says somebody has
-- noticed you; turning to square up says they have stopped what they were doing.
-- It exists because the town walks now, and being spoken to by a person facing
-- away down the street is worse than being spoken to by a statue.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local Cast = require(script.Parent.Parent.content.Cast)
local DataService = require(script.Parent.DataService)

type LifeEvent = Types.LifeEvent
type CastMember = Types.CastMember
type DeliveryPresentation = Types.DeliveryPresentation

local NPCService = {}

local VISITORS_FOLDER = "AgesVisitors"

-- Below this the humanoid is standing still for animation purposes. Not a design
-- tunable: it is the noise floor of Humanoid.Running, which reports small
-- non-zero speeds while settling.
local MOVING_SPEED_THRESHOLD = 0.5

-- How often a walk is checked for having finished. Only bounds how quickly the
-- *next* beat starts, so it can be coarse.
local WALK_POLL_SECONDS = 0.1

-- Cross-fade between idle and walk. Long enough not to pop, short enough that a
-- visitor who stops does not keep striding for half a step.
local ANIMATION_FADE_SECONDS = 0.2

-- Below this, the vector from a rig to whoever it is turning toward is straight up
-- or straight down and carries no heading. Not a tunable: it is the floating-point
-- floor of the arithmetic it guards, the same one PlaceService keeps for the same
-- reason.
local FLAT_FACING_EPSILON = 1e-3

-- Visitors are solid to the world and to the player, and pass through each other.
--
-- The world half is not a choice: a humanoid with nothing to collide with falls
-- through the floor. The each-other half is what makes a queue possible at all --
-- four rigs standing a couple of studs apart shove one another sideways within
-- seconds, and a line that drifts apart under its own weight is not a line.
--
-- The player is deliberately left out of it. Somebody standing at a till is a person
-- in your way, and walking through them would undo the only thing that makes them
-- feel present.
local VISITOR_COLLISION_GROUP = "AgesVisitors"

-- Every rig currently alive, so a hot reload or a server restart can sweep up
-- visitors whose delivery no longer exists.
local active: { [Model]: boolean } = {}

-- Positions of every active visitor, keyed by the rig model so the world event
-- system can answer "who is near the player" without walking the whole cast.
-- Each entry carries the cast id (used as the context tag) and the root position.
local visitorPositions: { [Model]: { id: string, position: Vector3 } } = {}

-- Registered once, on demand, and reported if it fails rather than left to be
-- discovered as a queue that will not hold its shape.
local collisionGroupReady = false

local function ensureCollisionGroup(): boolean
	if collisionGroupReady then
		return true
	end

	local ok, err = pcall(function()
		-- Checked rather than assumed: registering a name twice is an error, and this
		-- runs again after every hot reload in Studio.
		if not PhysicsService:IsCollisionGroupRegistered(VISITOR_COLLISION_GROUP) then
			PhysicsService:RegisterCollisionGroup(VISITOR_COLLISION_GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(VISITOR_COLLISION_GROUP, VISITOR_COLLISION_GROUP, false)
	end)
	if not ok then
		warn(`[AGES] visitors will push each other around: {err}`)
		return false
	end

	collisionGroupReady = true
	return true
end

local function visitorsFolder(): Folder
	local existing = workspace:FindFirstChild(VISITORS_FOLDER)
	if existing ~= nil then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = VISITORS_FOLDER
	folder.Parent = workspace
	return folder
end

-- How big this person is, right now, as the four numbers a rig is scaled by.
--
-- A CastMember carries a *build* -- how far off average for their age they are --
-- and the age supplies the rest, from the one curve everybody in the world grows
-- along. Nil age means grown, which is the honest default for every caller that
-- spawns an adult and has no reason to say so: a shopkeeper, a delivery driver,
-- somebody a scene needed. It reproduces exactly what this file did before there
-- was a curve at all.
--
-- Depth is scaled with the rest, and it did not used to be. On an adult that is
-- invisible, which is why it went unnoticed; on a body scaled to a third of its
-- height it is the difference between a small child and a flattened one.
local function scaleOf(member: CastMember, ageYears: number?): (number, number, number)
	if ageYears == nil then
		return member.heightScale, member.widthScale, member.headScale
	end
	local body, head = Config.Growth.At(ageYears)
	return member.heightScale * body, member.widthScale * body, member.headScale * head
end

-- How old a peer is right now, for callers who never had a reason to work it out.
-- PeopleService knows a townsperson's age already and passes it; everybody else --
-- an event sending Rae round, a scene that just wants somebody there -- does not,
-- and asking each of them to would be asking every caller to care about growth in
-- order to spawn a person. So the question is answered here, once, off the member's
-- own ageOffset.
--
-- nil for anybody without an offset, which is everybody but the peers, and nil again
-- if the profile has not loaded: an adult-sized rig is a far smaller wrong than a
-- newborn-sized one, which is what treating a missing profile as age nought would give.
local function peerAge(player: Player, member: CastMember): number?
	local offset = member.ageOffset
	if offset == nil then
		return nil
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return math.max(Lives.Active(profile.Data).ageMonths // Config.Time.MonthsPerYear + offset, 0)
end

local function buildDescription(member: CastMember, ageYears: number?): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	local height, width, headSize = scaleOf(member, ageYears)
	description.HeightScale = height
	description.WidthScale = width
	description.DepthScale = width
	description.HeadScale = headSize
	description.ProportionScale = member.proportionScale
	description.BodyTypeScale = member.bodyTypeScale

	description.HeadColor = member.skinColor

	-- Arms and torso take the shirt colour when there is one, legs the pants
	-- colour -- both fall back to skinColor, which is exactly the old
	-- all-one-shade body for any CastMember that has not been given either.
	-- This is what makes a crowd of these read as clothed people from across
	-- a pitch rather than as a few hundred identical skin-toned dummies: no
	-- asset upload, no shopping trip, just two more colours read off the body.
	local shirt = member.shirtColor or member.skinColor
	local pants = member.pantsColor or member.skinColor
	description.LeftArmColor = shirt
	description.RightArmColor = shirt
	description.TorsoColor = shirt
	description.LeftLegColor = pants
	description.RightLegColor = pants

	-- 0 is HumanoidDescription's own "empty slot", so an unchosen id is left
	-- alone rather than written as a zero that would fail to load.
	if member.shirtAssetId ~= 0 then
		description.Shirt = member.shirtAssetId
	end
	if member.pantsAssetId ~= 0 then
		description.Pants = member.pantsAssetId
	end
	if member.hairAssetId ~= 0 then
		description.HairAccessory = tostring(member.hairAssetId)
	end

	return description
end

-- Written once when the rig is built and again on every birthday.
--
-- Belt and braces over the description, and both halves earn their place. The
-- description is what gets the *proportions* right at build time; these
-- NumberValues are what the engine actually renders from, they can be written
-- to a body that already exists, and they are not subject to whatever the
-- place's avatar rules would clamp a description to. Without the second half a
-- classmate stays the size they were the day you met them until something else
-- happens to tear their rig down -- which is a birthday you can watch not
-- happening.
local warnedAboutScales = false
local function applyScale(humanoid: Humanoid, member: CastMember, ageYears: number?)
	local height, width, headSize = scaleOf(member, ageYears)
	local scales: { [string]: number } = {
		BodyHeightScale = height,
		BodyWidthScale = width,
		BodyDepthScale = width,
		HeadScale = headSize,
	}

	local scaled = true
	for valueName, target in scales do
		local value = humanoid:FindFirstChild(valueName)
		if value ~= nil and value:IsA("NumberValue") then
			value.Value = target
		else
			scaled = false
		end
	end

	-- Once per server, exactly as BodyService does for the player's own rig, and
	-- for the same reason: silently not growing looks like a content mistake and
	-- sends whoever is chasing it to the wrong file entirely.
	if not scaled and not warnedAboutScales then
		warnedAboutScales = true
		warn("[AGES] a visitor rig has no R15 scale values; nobody in the world will be sized to their age")
	end
end

-- An empty id means one has not been chosen in Studio yet. Returning nil rather
-- than loading an empty AnimationId keeps that at "this clip is missing" instead
-- of an error on every play, and every caller already handles a nil track.
local function loadTrack(animator: Animator, assetId: string, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack?
	if assetId == "" then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = assetId

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or track == nil then
		warn(`[AGES] visitor animation "{assetId}" could not be loaded: {track}`)
		return nil
	end

	track.Looped = looped
	track.Priority = priority
	return track
end

-- Re-aims the neck at a point in the world and returns the angles it settled on,
-- so the caller can carry them into the next tick. Angles are eased rather than
-- snapped: a head that reaches its target in one frame reads as a turret.
--
-- Yaw is measured in the upper torso's space, where -Z is forward and +Y is up,
-- which is the same frame the neck's rest C0 sits in -- so the rotation composes
-- onto that rest pose directly instead of needing to be converted first.
local function aimNeck(
	neck: Motor6D,
	restC0: CFrame,
	upperTorso: BasePart,
	head: BasePart,
	target: Vector3?,
	yaw: number,
	pitch: number
): (number, number)
	local desiredYaw, desiredPitch = 0, 0

	if target ~= nil then
		local toTarget = target - head.Position
		local distance = toTarget.Magnitude
		-- Beyond LookMaxDistance they face front. Someone across the street is
		-- not staring at you, and tracking that far reads as uncanny.
		if distance > 0 and distance <= Config.NPC.LookMaxDistance then
			local relative = upperTorso.CFrame:VectorToObjectSpace(toTarget.Unit)
			desiredYaw = math.atan2(-relative.X, -relative.Z)
			desiredPitch = math.asin(math.clamp(relative.Y, -1, 1))
		end
	end

	-- Clamped rather than abandoned: past the limit a person turns as far as
	-- their neck goes and holds it there, which is what this looks like.
	local maxYaw = math.rad(Config.NPC.LookMaxYawDegrees)
	local maxPitch = math.rad(Config.NPC.LookMaxPitchDegrees)
	desiredYaw = math.clamp(desiredYaw, -maxYaw, maxYaw)
	desiredPitch = math.clamp(desiredPitch, -maxPitch, maxPitch)

	local responsiveness = Config.NPC.LookResponsiveness
	local nextYaw = yaw + (desiredYaw - yaw) * responsiveness
	local nextPitch = pitch + (desiredPitch - pitch) * responsiveness

	neck.C0 = restC0 * CFrame.Angles(nextPitch, nextYaw, 0)
	return nextYaw, nextPitch
end

-- Walks to a point and reports whether it arrived. Bounded by its own timeout
-- rather than trusting MoveToFinished, because a humanoid wedged on geometry
-- never fires it and a visitor frozen in the hallway forever is worse than one
-- who quietly gives up.
--
-- `shouldStop` is how a walk is called off from outside while it is happening --
-- somebody has walked up to talk, the roster is being torn down, the whole thing
-- has been switched off in the harness. Asked on the poll rather than handed a
-- cancel token, because the caller is the only thing that knows what "call it off"
-- means and this way it never has to be told twice.
local function walkTo(humanoid: Humanoid, position: Vector3, timeout: number, shouldStop: (() -> boolean)?): boolean
	local finished = false
	local reached = false

	local connection = humanoid.MoveToFinished:Connect(function(ok: boolean)
		reached = ok
		finished = true
	end)

	humanoid:MoveTo(position)

	local elapsed = 0
	while not finished and elapsed < timeout do
		if humanoid.Parent == nil then
			break
		end
		if shouldStop ~= nil and shouldStop() then
			-- Abandoned, not arrived. Aimed at where they already stand, which is the
			-- only way to stop a humanoid without freezing it in mid-stride.
			local root = humanoid.RootPart
			if root ~= nil then
				humanoid:MoveTo(root.Position)
			end
			reached = false
			break
		end
		elapsed += task.wait(WALK_POLL_SECONDS)
	end

	connection:Disconnect()
	return reached
end

-- The agent a route is computed for. Nominal, like everything else measured off
-- Config.NPC.BodyRadius: a path has to be asked for before there is a body to
-- measure, and asking for one slightly wider than anybody actually is means the
-- error is a route refused rather than a route through a doorway they do not fit.
local function agentParams(): { [string]: any }
	return {
		AgentRadius = Config.NPC.BodyRadius,
		AgentHeight = Config.NPC.BodyHeight,
		AgentCanJump = true,
	}
end

-- Walks a computed route and reports whether the whole thing was walked.
--
-- Every failure here -- no route, a wedged waypoint, geometry that moved -- comes
-- back as false rather than as a retry, because the caller is a wander loop that
-- already has somewhere else to be. Grinding against an obstacle is the one
-- behaviour that reads as broken from across the street; giving up and strolling
-- somewhere else does not.
local function pathTo(humanoid: Humanoid, root: BasePart, position: Vector3, shouldStop: (() -> boolean)?): boolean
	if shouldStop ~= nil and shouldStop() then
		return false
	end

	local path = PathfindingService:CreatePath(agentParams())

	local ok = pcall(function()
		path:ComputeAsync(root.Position, position)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		-- No route. Not warned: an unreachable spot is an ordinary answer when the
		-- thing asking is picking spots at random, and a warning per attempt would
		-- bury the log in a town of thirty.
		path:Destroy()
		return false
	end

	local waypoints = path:GetWaypoints()
	path:Destroy()

	-- The first waypoint is where the walker already is, so walking to it is a
	-- MoveTo that finishes instantly and costs a poll interval each leg.
	for index = 2, #waypoints do
		if humanoid.Parent == nil then
			return false
		end
		local waypoint = waypoints[index]
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		if not walkTo(humanoid, waypoint.Position, Config.NPC.WaypointTimeoutSeconds, shouldStop) then
			return false
		end
	end

	return true
end

local function resolveMember(event: LifeEvent): CastMember
	local castId = event.cast
	if castId == nil then
		return Cast.Default
	end
	-- Validated at content load, so reaching here with an unknown id would mean
	-- the validator was bypassed. Fall back rather than fail the whole delivery.
	local member = Cast.ById[castId]
	if member == nil then
		warn(`[AGES] event "{event.id}" casts "{castId}", who is not in the cast; sending {Cast.Default.name}`)
		return Cast.Default
	end
	return member
end

-- A person standing in the world, and everything anyone can ask one to do.
--
-- Handed back by Spawn rather than driven through the service, because a visitor is
-- not a singleton and the caller is the only thing that knows the shape of the
-- errand: a delivery walks to a fixed spot and waits, while a parent chases a
-- moving toddler across a room. Both are the same person underneath, which is the
-- whole point of the split.
export type Visitor = {
	model: Model,
	-- The part to hang things off -- the anchor a delivery's interact prompt sits on
	-- and the point money floats up from.
	root: BasePart,
	-- Where they are now.
	at: () -> Vector3,
	-- Whether the rig has left the world. Every yield below is a place a visitor can
	-- be torn down under the caller -- a server sweep, a life ending -- so anything
	-- that comes back from a wait and touches them has to ask this first.
	gone: () -> boolean,
	-- Aims the walk at a point and returns immediately. For a target that moves, call
	-- it again: a humanoid holds the last destination it was given, so a chase is a
	-- re-aim on a tick rather than anything cleverer.
	moveTo: (position: Vector3) -> (),
	-- Stops where they stand. Needed because moveTo has no "and stop here" -- a
	-- chaser that simply stopped re-aiming would keep walking into the player.
	halt: () -> (),
	-- Walks to a point and reports whether it arrived, yielding until it does or
	-- until Config.NPC.WalkTimeoutSeconds gives up. The right call for a fixed
	-- destination; useless for a moving one.
	walkTo: (position: Vector3) -> boolean,
	-- The same, by a route rather than in a straight line, and false the moment any
	-- part of it fails. What to use when the destination is somewhere in a built
	-- world rather than a spot picked to be reachable -- see the note above pathTo.
	-- Yields for as long as the walk takes, so it takes a way to be called off: pass
	-- a predicate that goes true when this walk has stopped being wanted.
	pathTo: (position: Vector3, shouldStop: (() -> boolean)?) -> boolean,
	-- Turns them on the spot to look at a point, easing rather than snapping, and
	-- holds there. nil lets go, and is what has to be called before they walk again:
	-- a body being held at an angle cannot also be steering itself.
	--
	-- Not a MoveTo. A humanoid turns by walking, so aiming one at a point a step
	-- away to make it face somebody produces a shuffle, and a person who takes a
	-- step toward you every time you speak to them is unnerving rather than warm.
	face: (target: Vector3?) -> (),
	-- How fast they walk from now on. Here rather than at spawn because the same
	-- body does different things at different speeds -- crossing town is a stroll,
	-- arriving at a door is not -- and both are properties of the errand.
	setSpeed: (studsPerSecond: number) -> (),
	-- How old they are from now on, which is the only thing that decides how big
	-- they are. Here rather than only at spawn because a birthday must not cost a
	-- rebuild: tearing a rig down and building a new one is a yielding web call and
	-- a visible pop, so the whole street would flicker every time the player aged
	-- up. nil is grown, matching Spawn.
	setAge: (ageYears: number?) -> (),
	greet: () -> (),
	talk: () -> (),
	destroy: () -> (),
}

-- Builds a person and puts them in the world facing the way `at` faces. Yields:
-- creating an avatar from a description is a web-backed call. Returns nil if the rig
-- could not be made, which every caller must treat as "this did not happen".
--
-- Knows nothing about why they are here. It takes a cast member and a place to
-- appear, and everything above the neck -- head tracking, locomotion clips -- runs
-- from the moment they exist, because those are properties of being a person rather
-- than of any particular errand.
function NPCService.Spawn(player: Player, member: CastMember, at: CFrame, ageYears: number?): Visitor?
	local age = ageYears or peerAge(player, member)

	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(buildDescription(member, age), Enum.HumanoidRigType.R15)
	end)
	if not ok or rig == nil then
		warn(`[AGES] could not build visitor "{member.id}": {rig}`)
		return nil
	end

	local visitor = rig :: Model
	local humanoid = visitor:FindFirstChildOfClass("Humanoid")
	local root = visitor:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid == nil or root == nil then
		warn(`[AGES] visitor "{member.id}" came back without a humanoid or root part`)
		visitor:Destroy()
		return nil
	end

	visitor.Name = `Visitor_{member.id}`
	-- Again, over the description that already asked for it. See applyScale.
	applyScale(humanoid, member, age)
	humanoid.DisplayName = member.name
	humanoid.WalkSpeed = Config.NPC.WalkSpeed
	-- Nobody is fighting anybody in this game, so a health bar over a visitor's
	-- head would be answering a question the player never asked.
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	visitorPositions[visitor] = { id = member.id, position = root.Position }

	-- Set before parenting, so no rig is ever briefly able to shove the one it is
	-- queueing behind. One frame of that is enough to break a line.
	if ensureCollisionGroup() then
		for _, part in visitor:GetDescendants() do
			if part:IsA("BasePart") then
				part.CollisionGroup = VISITOR_COLLISION_GROUP
			end
		end
	end

	-- Placed before parenting so the visitor is never briefly at the origin.
	visitor:PivotTo(at)
	visitor.Parent = visitorsFolder()
	active[visitor] = true

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local animationIds = Config.Assets.Animations
	local idleTrack = loadTrack(animator :: Animator, animationIds.NPCIdle, true, Enum.AnimationPriority.Idle)
	local walkTrack = loadTrack(animator :: Animator, animationIds.NPCWalk, true, Enum.AnimationPriority.Movement)
	local greetTrack = loadTrack(animator :: Animator, animationIds.NPCGreet, false, Enum.AnimationPriority.Action)
	local talkTrack = loadTrack(animator :: Animator, animationIds.NPCTalk, false, Enum.AnimationPriority.Action)

	if idleTrack ~= nil then
		idleTrack:Play(ANIMATION_FADE_SECONDS)
	end

	-- Locomotion is driven off the humanoid's own reported speed rather than off
	-- our walk calls, so the clips stay right even when movement ends in a way
	-- this service did not ask for -- a timeout, a shove, a stall on geometry.
	local runningConnection = humanoid.Running:Connect(function(speed: number)
		local moving = speed > MOVING_SPEED_THRESHOLD
		if walkTrack ~= nil then
			if moving and not walkTrack.IsPlaying then
				walkTrack:Play(ANIMATION_FADE_SECONDS)
			elseif not moving and walkTrack.IsPlaying then
				walkTrack:Stop(ANIMATION_FADE_SECONDS)
			end
		end
		if idleTrack ~= nil then
			if not moving and not idleTrack.IsPlaying then
				idleTrack:Play(ANIMATION_FADE_SECONDS)
			end
		end
	end)

	local head = visitor:FindFirstChild("Head") :: BasePart?
	local upperTorso = visitor:FindFirstChild("UpperTorso") :: BasePart?
	local neck = if head ~= nil then head:FindFirstChild("Neck") :: Motor6D? else nil

	local looking = true
	if neck ~= nil and head ~= nil and upperTorso ~= nil then
		local restC0 = neck.C0
		task.spawn(function()
			local yaw, pitch = 0, 0
			while looking and visitor.Parent ~= nil do
				local character = player.Character
				local targetHead = if character ~= nil then character:FindFirstChild("Head") :: BasePart? else nil
				yaw, pitch = aimNeck(
					neck :: Motor6D,
					restC0,
					upperTorso :: BasePart,
					head :: BasePart,
					if targetHead ~= nil then targetHead.Position else nil,
					yaw,
					pitch
				)
				task.wait(Config.NPC.LookTickSeconds)
			end
		end)
	end

	-- Copied out of the optionals above so the closures below close over plain
	-- values. A refinement made here does not survive into a function body that runs
	-- later, and every one of these is read from inside one.
	local body = root :: BasePart
	local walker = humanoid :: Humanoid

	local function gone(): boolean
		return visitor.Parent == nil or walker.Parent == nil
	end

	local function play(track: AnimationTrack?)
		if track == nil or gone() then
			return
		end
		track:Play(ANIMATION_FADE_SECONDS)
	end

	-- Where they are being held looking, and whether the loop doing the holding is
	-- already running. One loop per rig at most: `face` is called again on every tick
	-- of an open conversation so the turn tracks a player who walks around them, and
	-- spawning a fresh loop each time would stack a dozen of them fighting over the
	-- same root part within a few seconds.
	local facing: Vector3? = nil
	local turning = false

	local function stepFacing()
		while facing ~= nil and not gone() do
			local target = facing :: Vector3
			local flat = Vector3.new(target.X - body.Position.X, 0, target.Z - body.Position.Z)
			if flat.Magnitude > FLAT_FACING_EPSILON then
				local want = CFrame.lookAt(body.Position, body.Position + flat.Unit)
				-- Slerped through CFrame:Lerp rather than by stepping a yaw angle,
				-- because a yaw has a seam at +/-pi and a person turning the long way
				-- round to greet somebody standing just behind them is a spin.
				local stepped = body.CFrame:Lerp(want, Config.NPC.TurnResponsiveness)
				body.CFrame = CFrame.lookAt(body.Position, body.Position + stepped.LookVector)

				local left = math.deg(math.acos(math.clamp(body.CFrame.LookVector:Dot(want.LookVector), -1, 1)))
				if left <= Config.NPC.TurnDoneDegrees then
					-- Squared up. The hold stays -- AutoRotate is still off and the
					-- target is still set -- so this only stops the arithmetic, which
					-- would otherwise nudge forever without ever quite arriving.
					body.CFrame = want
					break
				end
			end
			task.wait(Config.NPC.TurnTickSeconds)
		end
		turning = false
	end

	local function face(target: Vector3?)
		if gone() then
			return
		end
		facing = target
		if target == nil then
			-- Steering handed back. Without this a walker keeps whatever angle it was
			-- held at and moons sideways down the street.
			walker.AutoRotate = true
			return
		end
		-- Off while held, because AutoRotate is the humanoid writing this same CFrame
		-- from its own velocity, and the two take turns rather than settling.
		walker.AutoRotate = false
		if not turning then
			turning = true
			task.spawn(stepFacing)
		end
	end

	return {
		model = visitor,
		root = body,
		at = function()
			return body.Position
		end,
		gone = gone,
		moveTo = function(position: Vector3)
			if gone() then
				return
			end
			-- Any walk lets go of a held angle first. A body cannot be steering itself
			-- and being held square to somebody at the same time, and the failure when
			-- both are true is a rig sliding down the street sideways.
			face(nil)
			walker:MoveTo(position)
		end,
		halt = function()
			if gone() then
				return
			end
			-- Told to walk to where they already are, which is how a humanoid is
			-- stopped without freezing it: it settles on the spot and the locomotion
			-- clips follow its own reported speed back down to idle.
			walker:MoveTo(body.Position)
		end,
		walkTo = function(position: Vector3): boolean
			if gone() then
				return false
			end
			face(nil)
			return walkTo(walker, position, Config.NPC.WalkTimeoutSeconds)
		end,
		pathTo = function(position: Vector3, shouldStop: (() -> boolean)?): boolean
			if gone() then
				return false
			end
			face(nil)
			return pathTo(walker, body, position, shouldStop)
		end,
		face = face,
		setSpeed = function(studsPerSecond: number)
			if gone() then
				return
			end
			walker.WalkSpeed = studsPerSecond
		end,
		setAge = function(years: number?)
			if gone() then
				return
			end
			applyScale(walker, member, years)
		end,
		greet = function()
			play(greetTrack)
		end,
		talk = function()
			play(talkTrack)
		end,
		destroy = function()
			looking = false
			facing = nil
			runningConnection:Disconnect()
			active[visitor] = nil
			visitorPositions[visitor] = nil
			visitor:Destroy()
		end,
	}
end

-- A visitor for an event: in from the doorstep, waiting to be reached, and away
-- again once they have been.
--
-- Thin on purpose. Everything about being a person is Spawn's, and everything here
-- is about this particular errand -- which door, how far in, and what "dismissed"
-- means to a delivery. The whole file used to be this function, and splitting it is
-- what lets a parent bring pocket money without a LifeEvent or a delivery point
-- existing to justify her.
function NPCService.Arrive(player: Player, point: BasePart, event: LifeEvent): DeliveryPresentation?
	local visitor = NPCService.Spawn(player, resolveMember(event), point.CFrame)
	if visitor == nil then
		return nil
	end
	local arriving = visitor :: Visitor

	local arrivalPosition = point.Position
	-- The waiting spot is straight in from the door along the point's own facing,
	-- so where a visitor ends up is set in Studio by turning the marker rather
	-- than by a number in here.
	local waitPosition = (point.CFrame * CFrame.new(0, 0, -Config.NPC.ApproachStuds)).Position

	local dismissed = false

	task.spawn(function()
		arriving.walkTo(waitPosition)
		if dismissed then
			return
		end
		arriving.greet()
	end)

	return {
		anchor = arriving.root,
		dismiss = function(collected: boolean)
			if dismissed then
				return
			end
			dismissed = true

			task.spawn(function()
				if collected then
					-- Talk over the prompt the player is now reading, then leave.
					-- Vanishing the instant they are reached would undo the whole
					-- reason they walked in.
					arriving.talk()
					task.wait(Config.NPC.TalkBeatSeconds)
				end

				arriving.walkTo(arrivalPosition)
				arriving.destroy()
			end)
		end,
	}
end

-- Removes every visitor currently standing around. Used at server start, where
-- a Rojo sync mid-session can otherwise leave rigs behind with nothing left
-- holding a reference to them.
function NPCService.DespawnAll()
	for visitor in active do
		active[visitor] = nil
		visitorPositions[visitor] = nil
		visitor:Destroy()
	end

	local folder = workspace:FindFirstChild(VISITORS_FOLDER)
	if folder ~= nil then
		folder:ClearAllChildren()
	end
end

-- Asked for at start rather than at the first spawn, so a server that cannot have it
-- says so in the log while somebody is still reading the log, instead of half an hour
-- later in the shape of a queue that will not stand still.
function NPCService:Init()
	ensureCollisionGroup()
end

function NPCService:Start()
	NPCService.DespawnAll()
end

-- Returns the cast id and current position of every active visitor, so
-- EventService can build context tags from who is standing near the player.
-- The list is rebuilt on every call from the live table, so it is always current.
function NPCService.GetPositions(): { { id: string, position: Vector3 } }
	local result: { { id: string, position: Vector3 } } = {}
	for model, info in visitorPositions do
		if info ~= nil then
			table.insert(result, { id = info.id, position = info.position })
		end
	end
	return result
end

return NPCService
