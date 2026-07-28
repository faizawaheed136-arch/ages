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
--   Motion     A straight walk via Humanoid:MoveTo. Deliberately the simplest
--              honest version -- no pathfinding graph -- and flagged as such in
--              Config.NPC, because the moment a visitor has to cross a cluttered
--              room this needs PathfindingService instead.
--   Expression Looped idle/walk plus one-shot greet and talk clips, driven from
--              Config.Assets.Animations, and procedural head tracking.
--
-- Head tracking is the part worth understanding. It is the single largest
-- difference between a mannequin and a person, and it costs nothing: no asset,
-- no upload, just the neck joint re-aimed a few times a second. So it runs even
-- while every animation id above is still empty, and it is what carries the
-- scene until they are filled in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local Cast = require(script.Parent.Parent.content.Cast)

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

-- Every rig currently alive, so a hot reload or a server restart can sweep up
-- visitors whose delivery no longer exists.
local active: { [Model]: boolean } = {}

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

local function buildDescription(member: CastMember): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	description.HeightScale = member.heightScale
	description.WidthScale = member.widthScale
	description.HeadScale = member.headScale
	description.ProportionScale = member.proportionScale
	description.BodyTypeScale = member.bodyTypeScale

	description.HeadColor = member.skinColor
	description.LeftArmColor = member.skinColor
	description.RightArmColor = member.skinColor
	description.LeftLegColor = member.skinColor
	description.RightLegColor = member.skinColor
	description.TorsoColor = member.skinColor

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
local function walkTo(humanoid: Humanoid, position: Vector3): boolean
	local finished = false
	local reached = false

	local connection = humanoid.MoveToFinished:Connect(function(ok: boolean)
		reached = ok
		finished = true
	end)

	humanoid:MoveTo(position)

	local elapsed = 0
	while not finished and elapsed < Config.NPC.WalkTimeoutSeconds do
		if humanoid.Parent == nil then
			break
		end
		elapsed += task.wait(WALK_POLL_SECONDS)
	end

	connection:Disconnect()
	return reached
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

-- Builds the visitor and starts the scene. Yields: creating an avatar from a
-- description is a web-backed call. Returns nil if the rig could not be made,
-- which the caller must treat as "this delivery did not happen".
function NPCService.Arrive(player: Player, point: BasePart, event: LifeEvent): DeliveryPresentation?
	local member = resolveMember(event)

	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(buildDescription(member), Enum.HumanoidRigType.R15)
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
	humanoid.DisplayName = member.name
	humanoid.WalkSpeed = Config.NPC.WalkSpeed
	-- Nobody is fighting anybody in this game, so a health bar over a visitor's
	-- head would be answering a question the player never asked.
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	-- Placed before parenting so the visitor is never briefly at the origin.
	visitor:PivotTo(point.CFrame)
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

	local arrivalPosition = point.Position
	-- The waiting spot is straight in from the door along the point's own facing,
	-- so where a visitor ends up is set in Studio by turning the marker rather
	-- than by a number in here.
	local waitPosition = (point.CFrame * CFrame.new(0, 0, -Config.NPC.ApproachStuds)).Position

	local dismissed = false

	local function teardown()
		looking = false
		runningConnection:Disconnect()
		active[visitor] = nil
		visitor:Destroy()
	end

	task.spawn(function()
		walkTo(humanoid, waitPosition)
		if dismissed then
			return
		end
		if greetTrack ~= nil then
			greetTrack:Play(ANIMATION_FADE_SECONDS)
		end
	end)

	return {
		anchor = root,
		dismiss = function(collected: boolean)
			if dismissed then
				return
			end
			dismissed = true

			task.spawn(function()
				if visitor.Parent ~= nil and collected then
					-- Talk over the prompt the player is now reading, then leave.
					-- Vanishing the instant they are reached would undo the whole
					-- reason they walked in.
					if talkTrack ~= nil then
						talkTrack:Play(ANIMATION_FADE_SECONDS)
					end
					task.wait(Config.NPC.TalkBeatSeconds)
				end

				if visitor.Parent ~= nil and humanoid.Parent ~= nil then
					walkTo(humanoid, arrivalPosition)
				end
				teardown()
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
		visitor:Destroy()
	end

	local folder = workspace:FindFirstChild(VISITORS_FOLDER)
	if folder ~= nil then
		folder:ClearAllChildren()
	end
end

function NPCService:Init() end

function NPCService:Start()
	NPCService.DespawnAll()
end

return NPCService
