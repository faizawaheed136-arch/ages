--!strict
-- Soccer: the one sport built to full depth. Six bodies and a ball, 3v3, always
-- running -- see Config.Sports.Soccer's header and docs/school_sports_plan.md's
-- phase 6 for the research this comes out of, and the lock-in this file answers to:
-- "drills that can improve skills, speed and stuff, can be seen under soccer skills
-- in menu, 3v3 mode always available."
--
-- Two things share this one pitch and this one roster:
--
--   The match itself. Bot-filled the moment the server has the goals to stand it
--   up, and never empty: anybody who walks up and presses join takes over the
--   nearest bot's slot, and anybody who walks away or dies hands it back. This is
--   the "3v3 mode always available" half of the lock-in.
--
--   PE. Curriculum's "pe" entry has verb "match" -- SchoolService hands the whole
--   afternoon to SoccerService.Begin the same way it already hands Science to a
--   procedure. Begin puts the student on the roster and opens a grading window;
--   nothing about the match itself changes because one player in it happens to be
--   being graded. The four SportsDrillService stations, including the shared
--   Penalty Spot, are untouched -- that is the "drills that improve skills, speed
--   and stuff" half, and it keeps raising athletics whether or not this file is
--   running a match at all.
--
-- What this file is not: a physics simulation. The ball and every bot are simple
-- kinematic bodies -- Anchored, CanCollide false, moved by setting .Position or
-- :PivotTo() every tick -- exactly the tradeoff StadiumCrowdService already makes
-- for many simple bodies on screen at once, and it sidesteps every
-- network-ownership question a real physics ball would raise. A human player is
-- never puppeted: this file only ever reads where their HumanoidRootPart already
-- is and writes their WalkSpeed once at kickoff.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Report = require(ReplicatedStorage:WaitForChild("school"):WaitForChild("Report"))

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local StatService = require(script.Parent.StatService)
local SkillService = require(script.Parent.SkillService)
local Ground = require(script.Parent.Parent.world.Ground)

type LifeData = Types.LifeData
type SoccerCareer = Types.SoccerCareer
type SoccerMatchState = Types.SoccerMatchState
type SoccerRosterEntry = Types.SoccerRosterEntry
type Team = "home" | "away"

local SoccerService = {}

local SoccerUpdatedRemote = Remotes.Get("SoccerUpdated")
local RequestSoccerJoinRemote = Remotes.Get("RequestSoccerJoin")
local RequestSoccerShootRemote = Remotes.Get("RequestSoccerShoot")
local RequestSoccerPassRemote = Remotes.Get("RequestSoccerPass")
local NoticeRemote = Remotes.Get("Notice")

local WORLD = Config.World
local SOCCER = Config.Sports.Soccer
local SKILL_AWARDS = Config.Skills.Awards

-- The subject id and school verb this file answers PE for.
local SUBJECT_ID = "pe"

-- Sanity checks at require time, the same guard MusicService runs on its own
-- Perfect/Sweet pair -- Perfect has to be the narrower band inside Good, or
-- nothing can ever grade Good.
if SOCCER.ShotPerfectBandHalf > SOCCER.ShotBandHalf then
	error(
		`[AGES config] Config.Sports.Soccer.ShotPerfectBandHalf ({SOCCER.ShotPerfectBandHalf}) is wider than`
			.. ` ShotBandHalf ({SOCCER.ShotBandHalf}). Perfect has to be the narrower band inside Good, or`
			.. ` nothing can ever grade a Good shot. Narrow ShotPerfectBandHalf or widen ShotBandHalf.`
	)
end
if #SOCCER.BotLaneOffsetShare ~= SOCCER.TeamSize or #SOCCER.BotLaneDepthShare ~= SOCCER.TeamSize then
	error(
		`[AGES config] Config.Sports.Soccer.BotLaneOffsetShare/BotLaneDepthShare must have exactly TeamSize`
			.. ` ({SOCCER.TeamSize}) entries, one rest lane per roster slot on a side. Add or remove one.`
	)
end

-- Flavour, not a tunable -- the same call MusicService.SONG_TITLES makes. Which
-- name a bot gets never changes what it does.
local BOT_NAMES = {
	"Alto", "Breeze", "Cinder", "Dune", "Echo", "Faro",
	"Gale", "Harbor", "Ives", "Jett", "Koa", "Lark",
}

local HOME_COLOR = Color3.fromRGB(210, 60, 60)
local AWAY_COLOR = Color3.fromRGB(60, 100, 210)
local BOT_HEAD_COLOR = Color3.fromRGB(245, 224, 196)
local BALL_COLOR = Color3.fromRGB(250, 250, 250)

-- -------------------------------------------------------------------
-- Pitch discovery: the two goals, found by tag and grouped by their own Model
-- parent -- see tools/gen_city.py's soccer_field(), which builds each goal as a
-- Model containing Post, Post2 and Bar, every part tagged SportTag with a
-- FacilityKind of "soccer". Whichever goal's own bounding box has the smaller
-- max-Z is "home"'s, the larger is "away"'s -- a goal's own Z-max is always its
-- own line regardless of which end of the pitch it stands at, so sorting by that
-- one number is the whole of "which way is outward" with no pitch-centre math
-- needed to get there.
-- -------------------------------------------------------------------

type Goal = {
	defendedBy: Team,
	lineZ: number,
	outward: number,
	minX: number,
	maxX: number,
	centerX: number,
	minY: number,
	maxY: number,
}

type Pitch = {
	goals: { home: Goal, away: Goal },
	centerX: number,
	centerZ: number,
	groundY: number,
	halfWidth: number,
	halfLength: number,
}

local pitch: Pitch? = nil

local function computePitch(): Pitch?
	local groups: { [Instance]: { BasePart } } = {}
	for _, instance in CollectionService:GetTagged(WORLD.SportTag) do
		if not instance:IsA("BasePart") then
			continue
		end
		local part = instance :: BasePart
		if part:GetAttribute(WORLD.SportKindAttribute) ~= SOCCER.GoalKind then
			continue
		end
		local parent = part.Parent
		if parent == nil then
			continue
		end
		local list = groups[parent]
		if list == nil then
			list = {}
			groups[parent] = list
		end
		table.insert(list, part)
	end

	local rawGoals: { Goal } = {}
	for _, parts in groups do
		local minX, maxX = math.huge, -math.huge
		local minY, maxY = math.huge, -math.huge
		local minZ, maxZ = math.huge, -math.huge
		for _, part in parts do
			local half = part.Size / 2
			minX = math.min(minX, part.Position.X - half.X)
			maxX = math.max(maxX, part.Position.X + half.X)
			minY = math.min(minY, part.Position.Y - half.Y)
			maxY = math.max(maxY, part.Position.Y + half.Y)
			minZ = math.min(minZ, part.Position.Z - half.Z)
			maxZ = math.max(maxZ, part.Position.Z + half.Z)
		end
		table.insert(rawGoals, {
			defendedBy = "home", -- placeholder, assigned below once sorted
			lineZ = maxZ,
			outward = 0,
			minX = minX,
			maxX = maxX,
			centerX = (minX + maxX) / 2,
			minY = minY,
			maxY = maxY,
		})
	end

	if #rawGoals ~= 2 then
		return nil
	end

	table.sort(rawGoals, function(a: Goal, b: Goal): boolean
		return a.lineZ < b.lineZ
	end)

	local home = rawGoals[1]
	home.defendedBy = "home"
	home.outward = -1
	local away = rawGoals[2]
	away.defendedBy = "away"
	away.outward = 1

	-- Ground level, off the goal parts themselves rather than a copy of GROUND --
	-- the same reasoning Config.Sports.Soccer's header gives for reading the goals
	-- at runtime instead of keeping a coordinate.
	local groundY = math.min(home.minY, away.minY)

	return {
		goals = { home = home, away = away },
		centerX = (home.centerX + away.centerX) / 2,
		centerZ = (home.lineZ + away.lineZ) / 2,
		groundY = groundY,
		halfWidth = SOCCER.PitchWidthStuds / 2,
		halfLength = math.abs(away.lineZ - home.lineZ) / 2,
	}
end

-- -------------------------------------------------------------------
-- Roster and ball state.
-- -------------------------------------------------------------------

type Slot = {
	team: Team,
	laneIndex: number,
	isBot: boolean,
	player: Player?,
	name: string,
	position: Vector3,
	facing: Vector3,
	model: Model?,
	torso: BasePart?,
	savedWalkSpeed: number?,
	claimCooldownLeft: number,
	charging: boolean,
	chargeShare: number,
	moveTarget: Vector3,
	decisionLeft: number,
}

type Ball = {
	position: Vector3,
	velocity: Vector3,
	carrierSlot: number?,
	lastShooterSlot: number?,
	assistCandidateSlot: number?,
	part: BasePart?,
}

type Match = {
	running: boolean,
	homeScore: number,
	awayScore: number,
	secondsLeft: number,
	pauseLeft: number,
	verdict: string?,
	verdictLeft: number,
	roster: { Slot },
	ball: Ball,
}

type PeWindow = {
	secondsLeft: number,
	contribution: number,
	goals: number,
	assists: number,
	tackles: number,
	shotsTaken: number,
	shotsOnTarget: number,
}

local match: Match? = nil
local rig: Folder? = nil

local playerSlot: { [Player]: number } = {}
local peWindows: { [Player]: PeWindow } = {}
local pushed: { [Player]: string } = {}

local enabled = true

-- -------------------------------------------------------------------
-- Small helpers.
-- -------------------------------------------------------------------

local function characterRoot(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function opposingTeam(team: Team): Team
	return if team == "home" then "away" else "home"
end

-- Takes team/lane directly rather than a whole Slot: called once per roster slot
-- before any Slot record exists yet (roster construction), and a throwaway Slot
-- built just to read two fields off it would be worse than the two arguments.
local function restPosition(pitchNow: Pitch, team: Team, laneIndex: number): Vector3
	local offsetShare = SOCCER.BotLaneOffsetShare[laneIndex]
	local depthShare = SOCCER.BotLaneDepthShare[laneIndex]
	local x = pitchNow.centerX + offsetShare * pitchNow.halfWidth
	-- Depth is a share of the distance from this slot's own goal line toward the
	-- far one, so "deep" always means "near your own goal" regardless of which
	-- end home/away defends. `outward` points from the goal line into the net --
	-- the conceded direction -- so the pitch interior from this goal is the
	-- opposite sign of it. Depth 0 lands exactly on the own goal line, depth 1
	-- exactly on the far one.
	local ownGoal = pitchNow.goals[team]
	local z = ownGoal.lineZ - ownGoal.outward * depthShare * (pitchNow.halfLength * 2)
	return Vector3.new(x, pitchNow.groundY, z)
end

local function ensureMatch(): Match?
	if match ~= nil then
		return match
	end
	local built = computePitch()
	if built == nil then
		return nil
	end
	pitch = built

	local roster: { Slot } = {}
	local nameOrder = {}
	for i, name in BOT_NAMES do
		nameOrder[i] = name
	end
	local nameIndex = 1
	local function nextBotName(): string
		local n = nameOrder[((nameIndex - 1) % #nameOrder) + 1]
		nameIndex += 1
		return n
	end

	for _, team in { "home", "away" } do
		for lane = 1, SOCCER.TeamSize do
			local slot: Slot = {
				team = team :: Team,
				laneIndex = lane,
				isBot = true,
				player = nil,
				name = nextBotName(),
				position = restPosition(built, team :: Team, lane),
				facing = if team == "home" then Vector3.new(0, 0, 1) else Vector3.new(0, 0, -1),
				model = nil,
				torso = nil,
				savedWalkSpeed = nil,
				claimCooldownLeft = 0,
				charging = false,
				chargeShare = 0,
				moveTarget = Vector3.zero,
				decisionLeft = math.random() * SOCCER.BotDecisionSeconds,
			}
			slot.moveTarget = slot.position
			table.insert(roster, slot)
		end
	end

	match = {
		running = false,
		homeScore = 0,
		awayScore = 0,
		secondsLeft = SOCCER.MatchSeconds,
		pauseLeft = 0,
		verdict = nil,
		verdictLeft = 0,
		roster = roster,
		ball = {
			position = Vector3.new(built.centerX, built.groundY + SOCCER.BallRadius, built.centerZ),
			velocity = Vector3.zero,
			carrierSlot = nil,
			lastShooterSlot = nil,
			assistCandidateSlot = nil,
			part = nil,
		},
	}
	return match
end

-- -------------------------------------------------------------------
-- Rig: the kinematic bodies drawn for the ball and every bot. Built once the
-- pitch is found, alongside the match table.
-- -------------------------------------------------------------------

local function buildRig(m: Match, p: Pitch)
	local folder = Instance.new("Folder")
	folder.Name = "SoccerRig"
	folder.Parent = Workspace

	local ball = Instance.new("Part")
	ball.Name = "SoccerBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(SOCCER.BallRadius * 2, SOCCER.BallRadius * 2, SOCCER.BallRadius * 2)
	ball.Color = BALL_COLOR
	ball.Material = Enum.Material.SmoothPlastic
	ball.Anchored = true
	ball.CanCollide = false
	ball.CastShadow = true
	ball.Position = m.ball.position
	ball.Parent = folder
	m.ball.part = ball

	for _, slot in m.roster do
		local model = Instance.new("Model")
		model.Name = `SoccerBot_{slot.team}_{slot.laneIndex}`

		local torso = Instance.new("Part")
		torso.Name = "Torso"
		torso.Size = Vector3.new(2, 3, 1)
		torso.Color = if slot.team == "home" then HOME_COLOR else AWAY_COLOR
		torso.Material = Enum.Material.Fabric
		torso.Anchored = true
		torso.CanCollide = false
		torso.CastShadow = true
		torso.Parent = model

		local head = Instance.new("Part")
		head.Name = "Head"
		head.Shape = Enum.PartType.Ball
		head.Size = Vector3.new(1.4, 1.4, 1.4)
		head.Color = BOT_HEAD_COLOR
		head.Material = Enum.Material.SmoothPlastic
		head.Anchored = true
		head.CanCollide = false
		head.CastShadow = true
		head.Parent = model

		model.PrimaryPart = torso
		model:PivotTo(CFrame.new(slot.position + Vector3.new(0, 2.0, 0)))
		head.CFrame = torso.CFrame + Vector3.new(0, 2.4, 0)
		model.Parent = folder

		slot.model = model
		slot.torso = torso
	end

	rig = folder
end

-- -------------------------------------------------------------------
-- Career + PE bookkeeping.
-- -------------------------------------------------------------------

local function lifeDataFor(player: Player): LifeData?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return Lives.Active(profile.Data)
end

local function careerOf(slot: Slot): SoccerCareer?
	if slot.player == nil then
		return nil
	end
	local data = lifeDataFor(slot.player :: Player)
	if data == nil then
		return nil
	end
	return data.soccerCareer
end

local function addPeContribution(slot: Slot, weight: number, field: "goals" | "assists" | "tackles" | "shotsTaken" | "shotsOnTarget")
	if slot.player == nil then
		return
	end
	local window = peWindows[slot.player :: Player]
	if window == nil then
		return
	end
	window.contribution += weight
	if field == "goals" then
		window.goals += 1
	elseif field == "assists" then
		window.assists += 1
	elseif field == "tackles" then
		window.tackles += 1
	elseif field == "shotsTaken" then
		window.shotsTaken += 1
	elseif field == "shotsOnTarget" then
		window.shotsOnTarget += 1
	end
end

local function recordCareer(slot: Slot, field: "matchesPlayed" | "goals" | "assists" | "tackles" | "shotsTaken" | "shotsOnTarget", amount: number)
	local career = careerOf(slot)
	if career == nil then
		return
	end
	(career :: any)[field] = (career :: any)[field] + amount
	-- The menu's Soccer Skills section reads this off SkillsUpdated rather than
	-- SoccerUpdated -- see that push's own header -- because it has to be legible from
	-- anywhere in the town, not only within SOCCER.WatchRadiusStuds of the pitch. This is
	-- the one place the field changes, so it is the one place that asks for a re-push.
	if slot.player ~= nil then
		SkillService.Push(slot.player :: Player)
	end
end

local function awardSkillIfHuman(slot: Slot, xp: number, reason: string)
	if slot.player == nil or xp == 0 then
		return
	end
	SkillService.Award(slot.player :: Player, "athletics", xp, reason)
end

-- -------------------------------------------------------------------
-- Roster join / leave.
-- -------------------------------------------------------------------

local function applyWalkSpeed(slot: Slot)
	if slot.player == nil then
		return
	end
	local character = (slot.player :: Player).Character
	if character == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	slot.savedWalkSpeed = humanoid.WalkSpeed
	local level = SkillService.LevelOf(slot.player :: Player, "athletics")
	local levelCount = #Config.Skills.Levels
	local share = if levelCount > 1 then (level - 1) / (levelCount - 1) else 0
	humanoid.WalkSpeed = SOCCER.BaseWalkSpeed + SOCCER.MaxAthleticsWalkSpeedBonus * share
end

local function restoreWalkSpeed(slot: Slot)
	if slot.player == nil or slot.savedWalkSpeed == nil then
		return
	end
	local character = (slot.player :: Player).Character
	if character == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.WalkSpeed = slot.savedWalkSpeed :: number
	end
	slot.savedWalkSpeed = nil
end

local function revertSlotToBot(m: Match, slotIndex: number)
	local slot = m.roster[slotIndex]
	if slot.isBot then
		return
	end
	restoreWalkSpeed(slot)
	local player = slot.player :: Player
	playerSlot[player] = nil
	slot.isBot = true
	slot.player = nil
	slot.name = BOT_NAMES[((slotIndex - 1) % #BOT_NAMES) + 1]
	slot.charging = false
	slot.chargeShare = 0
	if slot.model ~= nil then
		slot.model.Parent = rig
	end
	if m.ball.carrierSlot == slotIndex then
		-- The ball cannot be left carried by a body that just vanished. Dropped in
		-- place as a loose ball, which the loose-ball chase picks straight back up.
		m.ball.carrierSlot = nil
		m.ball.velocity = Vector3.zero
	end
end

local function assignPlayerToSlot(m: Match, p: Pitch, player: Player, slotIndex: number)
	local slot = m.roster[slotIndex]
	slot.isBot = false
	slot.player = player
	slot.name = player.DisplayName
	slot.charging = false
	slot.chargeShare = 0
	if slot.model ~= nil then
		slot.model.Parent = nil
	end
	playerSlot[player] = slotIndex

	local rest = restPosition(p, slot.team, slot.laneIndex)
	local dropAt = rest + Vector3.new(0, WORLD.PlaceDropStuds, 0)
	local character = player.Character
	if character ~= nil then
		local facing = if slot.team == "home" then Vector3.new(0, 0, 1) else Vector3.new(0, 0, -1)
		character:PivotTo(CFrame.lookAt(dropAt, dropAt + facing))
	end
	slot.position = rest
	applyWalkSpeed(slot)
end

-- Nearest bot slot to a point, on either team, preferring the team with fewer
-- humans already on it so a third joiner does not stack one side three deep
-- while the other still has an open bot slot.
local function bestJoinSlot(m: Match): number?
	local homeHumans, awayHumans = 0, 0
	for _, slot in m.roster do
		if not slot.isBot then
			if slot.team == "home" then
				homeHumans += 1
			else
				awayHumans += 1
			end
		end
	end
	local preferredTeam: Team = if homeHumans <= awayHumans then "home" else "away"

	for _, wantTeam in { preferredTeam, opposingTeam(preferredTeam) } do
		for i, slot in m.roster do
			if slot.isBot and slot.team == wantTeam then
				return i
			end
		end
	end
	return nil
end

-- -------------------------------------------------------------------
-- Ball physics.
-- -------------------------------------------------------------------

local function facingVector(slot: Slot): Vector3
	if not slot.isBot and slot.player ~= nil then
		local root = characterRoot(slot.player :: Player)
		if root ~= nil then
			local look = root.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude > 1e-3 then
				return flat.Unit
			end
		end
	end
	return slot.facing
end

local function carryPositionFor(slot: Slot): Vector3
	local facing = facingVector(slot)
	return slot.position + facing * SOCCER.CarryAheadStuds + Vector3.new(0, SOCCER.CarryHeightStuds, 0)
end

local function resetBallToCenter(m: Match, p: Pitch)
	m.ball.position = Vector3.new(p.centerX, p.groundY + SOCCER.BallRadius, p.centerZ)
	m.ball.velocity = Vector3.zero
	m.ball.carrierSlot = nil
	m.ball.lastShooterSlot = nil
	m.ball.assistCandidateSlot = nil
end

local function goalTargetX(goal: Goal, aimShare: number, missStuds: number): number
	return goal.centerX + missStuds
end

-- Whether a defender of `goal.defendedBy`'s team is close enough to the crossing
-- point to turn a goal into a save -- the sole stand-in for a goalkeeper, reusing
-- the same claim-radius primitive tackling already uses.
local function defenderNearCrossing(m: Match, goal: Goal, crossX: number): boolean
	for _, slot in m.roster do
		if slot.team == goal.defendedBy then
			local dx = slot.position.X - crossX
			local dz = slot.position.Z - goal.lineZ
			if math.sqrt(dx * dx + dz * dz) <= SOCCER.ClaimRadiusStuds then
				return true
			end
		end
	end
	return false
end

local function setVerdict(m: Match, text: string, holdSeconds: number)
	m.verdict = text
	m.verdictLeft = holdSeconds
end

local function handleGoal(m: Match, p: Pitch, goal: Goal)
	local scoringTeam = opposingTeam(goal.defendedBy)
	if scoringTeam == "home" then
		m.homeScore += 1
	else
		m.awayScore += 1
	end

	local shooterIndex = m.ball.lastShooterSlot
	if shooterIndex ~= nil then
		local shooter = m.roster[shooterIndex]
		if shooter.team == scoringTeam then
			recordCareer(shooter, "goals", 1)
			awardSkillIfHuman(shooter, SKILL_AWARDS.SoccerGoal, "soccer goal")
			addPeContribution(shooter, SOCCER.PeGoalWeight, "goals")
		end
	end
	local assistIndex = m.ball.assistCandidateSlot
	if assistIndex ~= nil and assistIndex ~= shooterIndex then
		local assister = m.roster[assistIndex]
		if assister.team == scoringTeam then
			recordCareer(assister, "assists", 1)
			addPeContribution(assister, SOCCER.PeAssistWeight, "assists")
		end
	end

	setVerdict(m, "GOAL!", SOCCER.KickoffPauseSeconds)
	m.pauseLeft = SOCCER.KickoffPauseSeconds
	resetBallToCenter(m, p)
	for _, slot in m.roster do
		slot.position = restPosition(p, slot.team, slot.laneIndex)
		slot.moveTarget = slot.position
		slot.charging = false
		slot.chargeShare = 0
	end
end

-- Linear-interpolated goal-line crossing, checked against both goals every tick.
-- Point-in-box-per-tick would miss a fast shot tunnelling through the shallow
-- goal box between two ticks; interpolating the exact crossing point does not.
local function checkGoalCrossing(m: Match, p: Pitch, prevPos: Vector3, newPos: Vector3): boolean
	for _, goal in { p.goals.home, p.goals.away } do
		local prevOutward = (prevPos.Z - goal.lineZ) * goal.outward
		local newOutward = (newPos.Z - goal.lineZ) * goal.outward
		if prevOutward < 0 and newOutward >= 0 then
			local denom = newPos.Z - prevPos.Z
			local t = if math.abs(denom) > 1e-4 then math.clamp((goal.lineZ - prevPos.Z) / denom, 0, 1) else 0
			local crossX = prevPos.X + (newPos.X - prevPos.X) * t
			local crossY = prevPos.Y + (newPos.Y - prevPos.Y) * t
			if crossX >= goal.minX and crossX <= goal.maxX and crossY >= goal.minY and crossY <= goal.maxY then
				if defenderNearCrossing(m, goal, crossX) then
					setVerdict(m, "Saved!", SOCCER.VerdictHoldSeconds)
					m.ball.position = Vector3.new(crossX, crossY, goal.lineZ - goal.outward * 2)
					m.ball.velocity = Vector3.new(-m.ball.velocity.X, math.abs(m.ball.velocity.Y) * 0.3, -m.ball.velocity.Z * SOCCER.BounceDamping)
					m.ball.carrierSlot = nil
				else
					handleGoal(m, p, goal)
				end
				return true
			end
		end
	end
	return false
end

local function tickBall(m: Match, p: Pitch, elapsed: number)
	local ball = m.ball

	if ball.carrierSlot ~= nil then
		local carrier = m.roster[ball.carrierSlot :: number]
		ball.position = carryPositionFor(carrier)
		ball.velocity = Vector3.zero
		return
	end

	local prevPos = ball.position
	local velocity = ball.velocity
	local aboveGround = prevPos.Y > p.groundY + SOCCER.BallRadius + 0.05

	if aboveGround then
		velocity = velocity - Vector3.new(0, SOCCER.Gravity * elapsed, 0)
	end

	local newPos = prevPos + velocity * elapsed

	if newPos.Y <= p.groundY + SOCCER.BallRadius then
		newPos = Vector3.new(newPos.X, p.groundY + SOCCER.BallRadius, newPos.Z)
		if velocity.Y < 0 then
			velocity = Vector3.new(velocity.X, -velocity.Y * SOCCER.BounceDamping, velocity.Z)
		end
	end

	-- Rolling friction, applied to the horizontal component only.
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = horizontal.Magnitude
	if speed > 0 then
		local drop = SOCCER.RollFriction * elapsed
		local newSpeed = math.max(0, speed - drop)
		if newSpeed < SOCCER.RestSpeed and newPos.Y <= p.groundY + SOCCER.BallRadius + 0.05 then
			newSpeed = 0
		end
		horizontal = if speed > 0 then horizontal.Unit * newSpeed else Vector3.zero
		velocity = Vector3.new(horizontal.X, velocity.Y, horizontal.Z)
	end

	-- Touchline containment: the far/side boundary is a wall the ball bounces off
	-- of rather than a place a goal check ever needs to run, since only the two
	-- goal lines carry a goal.
	if math.abs(newPos.X - p.centerX) > p.halfWidth then
		local clampedX = p.centerX + math.sign(newPos.X - p.centerX) * p.halfWidth
		newPos = Vector3.new(clampedX, newPos.Y, newPos.Z)
		velocity = Vector3.new(-velocity.X * SOCCER.BounceDamping, velocity.Y, velocity.Z)
	end

	local scored = checkGoalCrossing(m, p, prevPos, newPos)
	if not scored then
		-- A shot that misses the frame entirely bounces back off the goal line
		-- plane rather than sailing on forever behind it.
		for _, goal in { p.goals.home, p.goals.away } do
			local prevOutward = (prevPos.Z - goal.lineZ) * goal.outward
			local newOutward = (newPos.Z - goal.lineZ) * goal.outward
			if prevOutward < 0 and newOutward >= 0 then
				newPos = Vector3.new(newPos.X, newPos.Y, goal.lineZ - goal.outward * 0.5)
				velocity = Vector3.new(velocity.X, velocity.Y, -velocity.Z * SOCCER.BounceDamping)
				setVerdict(m, "Wide!", SOCCER.VerdictHoldSeconds)
			end
		end
		ball.position = newPos
		ball.velocity = velocity
	end
end

-- -------------------------------------------------------------------
-- Shooting and passing.
-- -------------------------------------------------------------------

local function resolveShot(m: Match, p: Pitch, slotIndex: number, share: number)
	if m.ball.carrierSlot ~= slotIndex then
		return
	end
	local slot = m.roster[slotIndex]
	local opposing = p.goals[opposingTeam(slot.team)]

	local overcharged = share >= SOCCER.OverchargeShare
	local effective = math.max(share, SOCCER.ShotMinShare)
	local power = SOCCER.ShotMinPower + (SOCCER.ShotMaxPower - SOCCER.ShotMinPower) * effective

	local bandDist = math.abs(share - SOCCER.ShotBandCenter)
	local grade: string
	if not overcharged and bandDist <= SOCCER.ShotPerfectBandHalf then
		grade = "Perfect"
	elseif not overcharged and bandDist <= SOCCER.ShotBandHalf then
		grade = "Good"
	else
		grade = "Wide"
	end

	local missStuds = 0
	if grade == "Wide" then
		local missShare = math.clamp((bandDist - SOCCER.ShotBandHalf) / math.max(1e-3, 1 - SOCCER.ShotBandHalf), 0, 1)
		local sign = if overcharged then 1 elseif share < SOCCER.ShotBandCenter then -1 else 1
		missStuds = sign * missShare * SOCCER.ShotAccuracyMissStuds
	end

	local targetX = goalTargetX(opposing, share, missStuds)
	local onTarget = targetX >= opposing.minX and targetX <= opposing.maxX

	local flat = Vector3.new(targetX - m.ball.position.X, 0, opposing.lineZ - m.ball.position.Z)
	local dir = if flat.Magnitude > 1e-3 then flat.Unit else facingVector(slot)
	m.ball.velocity = Vector3.new(dir.X * power, power * SOCCER.ShotLiftRatio, dir.Z * power)
	m.ball.carrierSlot = nil
	m.ball.lastShooterSlot = slotIndex

	slot.claimCooldownLeft = SOCCER.ClaimCooldownSeconds
	slot.charging = false
	slot.chargeShare = 0

	recordCareer(slot, "shotsTaken", 1)
	if onTarget then
		recordCareer(slot, "shotsOnTarget", 1)
	end
	addPeContribution(slot, if onTarget then SOCCER.PeShotOnTargetWeight else 0, "shotsTaken")
	if onTarget then
		addPeContribution(slot, 0, "shotsOnTarget")
	end

	if grade == "Perfect" then
		awardSkillIfHuman(slot, SKILL_AWARDS.SoccerShotPerfect, "perfect soccer shot")
	elseif grade == "Good" then
		awardSkillIfHuman(slot, SKILL_AWARDS.SoccerShotGood, "good soccer shot")
	end

	setVerdict(m, if grade == "Perfect" then "Perfect strike!" elseif grade == "Good" then "Shot!" else "Wide!", SOCCER.VerdictHoldSeconds)
end

local function findPassTarget(m: Match, slotIndex: number): number?
	local slot = m.roster[slotIndex]
	local facing = facingVector(slot)
	local coneHalf = math.rad(SOCCER.PassConeDegrees / 2)

	local best: number? = nil
	local bestDot = -math.huge
	for i, other in m.roster do
		if i == slotIndex or other.team ~= slot.team then
			continue
		end
		local to = Vector3.new(other.position.X - slot.position.X, 0, other.position.Z - slot.position.Z)
		local dist = to.Magnitude
		if dist < 1 or dist > SOCCER.PassMaxRangeStuds then
			continue
		end
		local dot = facing:Dot(to.Unit)
		if dot >= math.cos(coneHalf) and dot > bestDot then
			bestDot = dot
			best = i
		end
	end
	return best
end

local function resolvePass(m: Match, slotIndex: number)
	if m.ball.carrierSlot ~= slotIndex then
		return
	end
	local slot = m.roster[slotIndex]
	local targetIndex = findPassTarget(m, slotIndex)
	if targetIndex == nil then
		return
	end
	local target = m.roster[targetIndex]
	local dir = Vector3.new(target.position.X - slot.position.X, 0, target.position.Z - slot.position.Z)
	if dir.Magnitude < 1e-3 then
		return
	end
	m.ball.velocity = dir.Unit * SOCCER.PassSpeedStudsPerSecond
	m.ball.carrierSlot = nil
	m.ball.assistCandidateSlot = slotIndex
	slot.claimCooldownLeft = SOCCER.ClaimCooldownSeconds
end

-- -------------------------------------------------------------------
-- Possession contest.
-- -------------------------------------------------------------------

local function claimBall(m: Match, slotIndex: number, wasTackle: boolean)
	local slot = m.roster[slotIndex]
	local previousAssist = m.ball.assistCandidateSlot
	m.ball.lastShooterSlot = nil
	if previousAssist ~= nil and m.roster[previousAssist].team == slot.team then
		-- Same-team continuity: a teammate collecting a loose or rebounded ball
		-- keeps the assist chain alive.
	else
		m.ball.assistCandidateSlot = nil
	end
	m.ball.carrierSlot = slotIndex
	m.ball.velocity = Vector3.zero

	if wasTackle then
		recordCareer(slot, "tackles", 1)
		awardSkillIfHuman(slot, SKILL_AWARDS.SoccerTackle, "soccer tackle")
		addPeContribution(slot, SOCCER.PeTackleWeight, "tackles")
		setVerdict(m, "Tackled!", SOCCER.VerdictHoldSeconds)
	end
end

local function tickPossession(m: Match, elapsed: number)
	for _, slot in m.roster do
		if slot.claimCooldownLeft > 0 then
			slot.claimCooldownLeft = math.max(0, slot.claimCooldownLeft - elapsed)
		end
	end

	if m.ball.carrierSlot ~= nil then
		local carrierIndex = m.ball.carrierSlot :: number
		local carrier = m.roster[carrierIndex]
		local bestIndex: number? = nil
		local bestDist = SOCCER.ClaimRadiusStuds
		for i, slot in m.roster do
			if i == carrierIndex or slot.team == carrier.team or slot.claimCooldownLeft > 0 then
				continue
			end
			local dist = Ground.FlatDistance(slot.position, carrier.position)
			if dist <= bestDist then
				bestDist = dist
				bestIndex = i
			end
		end
		if bestIndex ~= nil then
			m.roster[carrierIndex].claimCooldownLeft = SOCCER.ClaimCooldownSeconds
			claimBall(m, bestIndex :: number, true)
		end
		return
	end

	-- Loose ball: any slot off cooldown close enough claims it, regardless of team.
	local bestIndex: number? = nil
	local bestDist = SOCCER.ClaimRadiusStuds
	for i, slot in m.roster do
		if slot.claimCooldownLeft > 0 then
			continue
		end
		local dist = Ground.FlatDistance(slot.position, m.ball.position)
		if dist <= bestDist then
			bestDist = dist
			bestIndex = i
		end
	end
	if bestIndex ~= nil then
		claimBall(m, bestIndex :: number, false)
	end
end

-- -------------------------------------------------------------------
-- Bot AI: an elastic-band formation, pulled toward the ball by how much
-- possession its own team holds, plus a decision layer for whoever is carrying
-- or chasing.
-- -------------------------------------------------------------------

local function formationTarget(m: Match, p: Pitch, slot: Slot): Vector3
	local rest = restPosition(p, slot.team, slot.laneIndex)
	if m.ball.carrierSlot == nil then
		return rest
	end
	local carrier = m.roster[m.ball.carrierSlot :: number]
	local attacking = carrier.team == slot.team
	local pull = if attacking then SOCCER.BotAdvanceShare else SOCCER.BotRetreatShare

	local ownGoal = p.goals[slot.team]
	local restDepthZ = rest.Z
	local targetDepthZ: number
	if attacking then
		targetDepthZ = restDepthZ + (m.ball.position.Z - restDepthZ) * pull
	else
		targetDepthZ = restDepthZ + (ownGoal.lineZ - restDepthZ) * pull
	end

	local targetX = rest.X + (m.ball.position.X - rest.X) * SOCCER.BotLateralPull
	return Vector3.new(targetX, p.groundY, targetDepthZ)
end

local function nearestTeammateToBall(m: Match, team: Team): number?
	local bestIndex: number? = nil
	local bestDist = math.huge
	for i, slot in m.roster do
		if slot.team ~= team then
			continue
		end
		local dist = Ground.FlatDistance(slot.position, m.ball.position)
		if dist < bestDist then
			bestDist = dist
			bestIndex = i
		end
	end
	return bestIndex
end

local function decideBot(m: Match, p: Pitch, slotIndex: number)
	local slot = m.roster[slotIndex]

	if m.ball.carrierSlot == slotIndex then
		local opposing = p.goals[opposingTeam(slot.team)]
		local rangeToGoal = math.abs(slot.position.Z - opposing.lineZ)
		if rangeToGoal <= SOCCER.BotShootRangeStuds then
			local jitter = (1 - SOCCER.BotSkill) * SOCCER.ShotBandHalf * 2
			local share = math.clamp(SOCCER.ShotBandCenter + (math.random() - 0.5) * jitter, 0, 1)
			resolveShot(m, p, slotIndex, share)
			return
		end
		if math.random() < SOCCER.BotSkill * 0.5 then
			resolvePass(m, slotIndex)
			if m.ball.carrierSlot ~= slotIndex then
				return
			end
		end
		local dir = Vector3.new(0, 0, opposing.lineZ - slot.position.Z)
		if dir.Magnitude > 1e-3 then
			slot.facing = dir.Unit
		end
		slot.moveTarget = slot.position + slot.facing * SOCCER.BaseWalkSpeed * SOCCER.BotDecisionSeconds
		return
	end

	if m.ball.carrierSlot == nil then
		local chaser = nearestTeammateToBall(m, slot.team)
		if chaser == slotIndex then
			slot.moveTarget = m.ball.position
			return
		end
	end

	slot.moveTarget = formationTarget(m, p, slot)
end

local function tickBots(m: Match, p: Pitch, elapsed: number)
	for i, slot in m.roster do
		if not slot.isBot then
			continue
		end
		slot.decisionLeft -= elapsed
		if slot.decisionLeft <= 0 then
			slot.decisionLeft = SOCCER.BotDecisionSeconds
			decideBot(m, p, i)
		end

		-- Whether carrying, chasing, or holding formation, every bot has a
		-- moveTarget by now -- decideBot set it above, or an earlier tick did.
		-- Carrying a ball needs no special case here: the ball itself follows the
		-- carrier via carryPositionFor next tick, once this slot's position moves.
		local toTarget = slot.moveTarget - slot.position
		local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
		if flat.Magnitude > 0.1 then
			slot.facing = flat.Unit
			local step = math.min(flat.Magnitude, SOCCER.BaseWalkSpeed * elapsed)
			slot.position = slot.position + flat.Unit * step
		end
	end
end

-- -------------------------------------------------------------------
-- Charge advance for human shooters.
-- -------------------------------------------------------------------

local function tickCharging(m: Match, elapsed: number)
	for i, slot in m.roster do
		if slot.isBot or not slot.charging then
			continue
		end
		if m.ball.carrierSlot ~= i then
			slot.charging = false
			slot.chargeShare = 0
			continue
		end
		slot.chargeShare = math.min(1, slot.chargeShare + elapsed / SOCCER.ShotChargeSeconds)
	end
end

-- -------------------------------------------------------------------
-- Human positions, rig sync, roster attrition (players who wandered off).
-- -------------------------------------------------------------------

local function syncHumanPositions(m: Match, p: Pitch)
	for i, slot in m.roster do
		if slot.isBot then
			continue
		end
		local player = slot.player :: Player
		local root = characterRoot(player)
		if root == nil then
			revertSlotToBot(m, i)
			continue
		end
		slot.position = root.Position
		slot.facing = facingVector(slot)
		if Ground.FlatDistance(root.Position, Vector3.new(p.centerX, 0, p.centerZ)) > SOCCER.WatchRadiusStuds then
			revertSlotToBot(m, i)
		end
	end
end

local function syncRig(m: Match)
	if m.ball.part ~= nil then
		m.ball.part.Position = m.ball.position
	end
	for _, slot in m.roster do
		if slot.model ~= nil and slot.isBot then
			local cf = CFrame.lookAt(slot.position + Vector3.new(0, 2.0, 0), slot.position + Vector3.new(0, 2.0, 0) + slot.facing)
			slot.model:PivotTo(cf)
		end
	end
end

-- -------------------------------------------------------------------
-- PE grading.
-- -------------------------------------------------------------------

local function finishPe(player: Player, reason: string)
	local window = peWindows[player]
	if window == nil then
		return
	end
	peWindows[player] = nil

	local data = lifeDataFor(player)
	if data == nil then
		return
	end

	local share = math.clamp(window.contribution / math.max(1e-3, SOCCER.PeContributionTarget), 0, 1)
	local band = Report.BandFor(share)
	local gained = Report.SmartsFor(band)

	if gained ~= 0 then
		StatService.AddStat(player, "smarts", gained)
	end

	data.lessonsThisYear += 1
	EventService.AwardAutonomy(player, 1)

	Report.RecordLesson(data, SUBJECT_ID, band, gained, nil)

	local slotIndex = playerSlot[player]
	if slotIndex ~= nil then
		recordCareer((match :: Match).roster[slotIndex], "matchesPlayed", 1)
	end

	local percent = math.floor(share * 100 + 0.5)
	local reward = if gained > 0 then `. +{gained} smarts.` else "."
	local opening = if reason == "left" then "You left the pitch." else "PE lesson over."
	local line = `{opening} {window.goals} goals, {window.assists} assists, {window.tackles} tackles, {percent}%{reward}`
	NoticeRemote:FireClient(player, line)
end

-- -------------------------------------------------------------------
-- State push.
-- -------------------------------------------------------------------

local function rosterEntryFor(slot: Slot, viewer: Player): SoccerRosterEntry
	local isYou = slot.player == viewer
	return {
		name = slot.name,
		team = slot.team,
		isBot = slot.isBot,
		isYou = isYou,
		isCarrier = false, -- filled by caller, which knows the carrier index
	}
end

local function stateFor(player: Player): SoccerMatchState?
	local m = match
	local p = pitch
	if m == nil or p == nil then
		return nil
	end

	local root = characterRoot(player)
	local nearPitch = if root ~= nil then Ground.FlatDistance(root.Position, Vector3.new(p.centerX, 0, p.centerZ)) <= SOCCER.WatchRadiusStuds else false
	local slotIndex = playerSlot[player]
	if not nearPitch and slotIndex == nil then
		return nil
	end

	local roster: { SoccerRosterEntry } = {}
	for i, slot in m.roster do
		local entry = rosterEntryFor(slot, player)
		entry.isCarrier = m.ball.carrierSlot == i
		table.insert(roster, entry)
	end

	local yourTeam: Team? = nil
	local onRoster = slotIndex ~= nil
	local isCarrier = false
	local charging = false
	local chargeShare = 0
	if slotIndex ~= nil then
		local slot = m.roster[slotIndex]
		yourTeam = slot.team
		isCarrier = m.ball.carrierSlot == slotIndex
		charging = slot.charging
		chargeShare = slot.chargeShare
	end

	local canJoin = false
	if not onRoster and root ~= nil then
		canJoin = enabled and Ground.FlatDistance(root.Position, Vector3.new(p.centerX, 0, p.centerZ)) <= SOCCER.JoinRadiusStuds
	end

	local data = lifeDataFor(player)
	local career: SoccerCareer = if data ~= nil
		then data.soccerCareer
		else { matchesPlayed = 0, goals = 0, assists = 0, tackles = 0, shotsTaken = 0, shotsOnTarget = 0 }

	return {
		running = m.running,
		homeScore = m.homeScore,
		awayScore = m.awayScore,
		secondsLeft = math.max(0, math.floor(m.secondsLeft)),
		roster = roster,
		yourTeam = yourTeam,
		onRoster = onRoster,
		isCarrier = isCarrier,
		charging = charging,
		chargeShare = chargeShare,
		verdict = if m.verdictLeft > 0 then m.verdict else nil,
		canJoin = canJoin,
		gradingPe = peWindows[player] ~= nil,
		career = career,
	}
end

local function push(player: Player)
	local state = stateFor(player)
	local digest: string
	if state == nil then
		digest = "none"
	else
		digest = `{state.running}|{state.homeScore}-{state.awayScore}|{state.secondsLeft}|{tostring(state.yourTeam)}`
			.. `|{state.onRoster}|{state.isCarrier}|{state.charging}|{math.floor(state.chargeShare * 20)}`
			.. `|{tostring(state.verdict)}|{state.canJoin}|{state.gradingPe}`
		for _, entry in state.roster do
			digest ..= `|{entry.name}:{entry.team}:{entry.isCarrier}`
		end
	end
	if pushed[player] == digest then
		return
	end
	pushed[player] = digest
	SoccerUpdatedRemote:FireClient(player, state)
end

local function pushAll()
	for _, player in Players:GetPlayers() do
		local ok, err = pcall(push, player)
		if not ok then
			warn(`[AGES] soccer push failed for {player.Name}: {err}`)
		end
	end
end

-- -------------------------------------------------------------------
-- Match tick.
-- -------------------------------------------------------------------

local function tickMatch(elapsed: number)
	if not enabled then
		return
	end
	local m = ensureMatch()
	if m == nil then
		return
	end
	local p = pitch :: Pitch
	if rig == nil then
		buildRig(m, p)
	end

	m.running = true

	if m.verdictLeft > 0 then
		m.verdictLeft = math.max(0, m.verdictLeft - elapsed)
	end

	if m.pauseLeft > 0 then
		m.pauseLeft = math.max(0, m.pauseLeft - elapsed)
		syncRig(m)
		pushAll()
		return
	end

	m.secondsLeft -= elapsed
	if m.secondsLeft <= 0 then
		m.secondsLeft = SOCCER.MatchSeconds
		m.homeScore = 0
		m.awayScore = 0
		setVerdict(m, "Full time!", SOCCER.KickoffPauseSeconds)
		m.pauseLeft = SOCCER.KickoffPauseSeconds
		resetBallToCenter(m, p)
		for _, slot in m.roster do
			slot.position = restPosition(p, slot.team, slot.laneIndex)
			slot.moveTarget = slot.position
		end
		syncRig(m)
		pushAll()
		return
	end

	syncHumanPositions(m, p)
	tickCharging(m, elapsed)
	tickBots(m, p, elapsed)
	tickPossession(m, elapsed)
	tickBall(m, p, elapsed)
	syncRig(m)

	for player in peWindows do
		local window = peWindows[player]
		window.secondsLeft -= elapsed
		local slotIndex = playerSlot[player]
		local stillOnPitch = slotIndex ~= nil
		if window.secondsLeft <= 0 then
			finishPe(player, "over")
		elseif not stillOnPitch then
			finishPe(player, "left")
		end
	end

	pushAll()
end

-- -------------------------------------------------------------------
-- Remote handlers.
-- -------------------------------------------------------------------

local function onJoinRequested(player: Player)
	if not enabled then
		return
	end
	local m = ensureMatch()
	local p = pitch
	if m == nil or p == nil then
		NoticeRemote:FireClient(player, "The soccer pitch has not been built.")
		return
	end
	if playerSlot[player] ~= nil then
		return
	end
	local root = characterRoot(player)
	if root == nil or Ground.FlatDistance(root.Position, Vector3.new(p.centerX, 0, p.centerZ)) > SOCCER.JoinRadiusStuds then
		NoticeRemote:FireClient(player, "Walk onto the pitch to join.")
		return
	end
	local slotIndex = bestJoinSlot(m)
	if slotIndex == nil then
		NoticeRemote:FireClient(player, "The match is full of players already.")
		return
	end
	assignPlayerToSlot(m, p, player, slotIndex)
	push(player)
end

local function onShootRequested(player: Player, held: unknown)
	local m = match
	if m == nil or type(held) ~= "boolean" then
		return
	end
	local slotIndex = playerSlot[player]
	if slotIndex == nil then
		return
	end
	local slot = m.roster[slotIndex]
	if held then
		if m.ball.carrierSlot == slotIndex then
			slot.charging = true
		end
	else
		if slot.charging then
			local share = slot.chargeShare
			slot.charging = false
			resolveShot(m, pitch :: Pitch, slotIndex, share)
		end
	end
end

local function onPassRequested(player: Player)
	local m = match
	if m == nil then
		return
	end
	local slotIndex = playerSlot[player]
	if slotIndex == nil then
		return
	end
	resolvePass(m, slotIndex)
end

-- -------------------------------------------------------------------
-- Public API.
-- -------------------------------------------------------------------

-- Hands a PE afternoon over to the match. Puts the student on the roster (over a
-- bot's slot, same as walking up and pressing join) and opens a grading window --
-- the match itself is unaffected either way, see the header.
function SoccerService.Begin(player: Player, data: LifeData): (boolean, string?)
	if not enabled then
		return false, "PE is not running today."
	end
	local m = ensureMatch()
	local p = pitch
	if m == nil or p == nil then
		return false, "The soccer pitch has not been built."
	end
	if peWindows[player] ~= nil then
		return false, "You are already being graded on the pitch."
	end

	local slotIndex = playerSlot[player]
	if slotIndex == nil then
		slotIndex = bestJoinSlot(m)
		if slotIndex == nil then
			return false, "The match is full of players already."
		end
		assignPlayerToSlot(m, p, player, slotIndex)
	end

	peWindows[player] = {
		secondsLeft = SOCCER.PeLessonSeconds,
		contribution = 0,
		goals = 0,
		assists = 0,
		tackles = 0,
		shotsTaken = 0,
		shotsOnTarget = 0,
	}
	push(player)
	return true, nil
end

function SoccerService.IsRunning(player: Player): boolean
	return peWindows[player] ~= nil
end

function SoccerService.ResetForNewLife(player: Player)
	peWindows[player] = nil
	local m = match
	if m ~= nil then
		local slotIndex = playerSlot[player]
		if slotIndex ~= nil then
			revertSlotToBot(m, slotIndex)
		end
	end
	pushed[player] = nil
	SoccerUpdatedRemote:FireClient(player, nil)
end

-- Studio harness.
--
-- ForceJoin is Begin's first half on its own: onto the roster, teleported to a rest
-- spot, and nothing else -- no PE window opens. It exists because "the match is always
-- available" is a claim about the pitch, not about school, and a harness for it has to
-- be able to prove the roster takes a player without touching PE at all. Bypasses
-- JoinRadiusStuds the same way ForceStart bypasses the walk to school: see that
-- function's own one-line reason.
function SoccerService.ForceJoin(player: Player): (boolean, string?)
	if not enabled then
		return false, "soccer is not running today."
	end
	local m = ensureMatch()
	local p = pitch
	if m == nil or p == nil then
		return false, "The soccer pitch has not been built."
	end
	if playerSlot[player] ~= nil then
		return false, "already on the roster."
	end
	local slotIndex = bestJoinSlot(m)
	if slotIndex == nil then
		return false, "The match is full of players already."
	end
	assignPlayerToSlot(m, p, player, slotIndex)
	push(player)
	return true, nil
end

function SoccerService.ForceStart(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	return SoccerService.Begin(player, Lives.Active(profile.Data))
end

function SoccerService.ForceGoal(player: Player): boolean
	local m = match
	local p = pitch
	if m == nil or p == nil then
		return false
	end
	local slotIndex = playerSlot[player]
	if slotIndex == nil then
		return false
	end
	m.ball.carrierSlot = slotIndex
	m.ball.lastShooterSlot = slotIndex
	handleGoal(m, p, p.goals[opposingTeam(m.roster[slotIndex].team)])
	return true
end

function SoccerService.ForceEnd(player: Player): boolean
	if peWindows[player] == nil then
		return false
	end
	finishPe(player, "over")
	return true
end

function SoccerService.SetEnabled(value: boolean)
	enabled = value
end

function SoccerService.IsEnabled(): boolean
	return enabled
end

function SoccerService.Describe(player: Player): string
	local m = match
	local p = pitch
	if m == nil or p == nil then
		return "soccer: pitch not found"
	end
	local slotIndex = playerSlot[player]
	local roleLine = if slotIndex == nil then "not on roster" else `on roster: {m.roster[slotIndex].team} lane {m.roster[slotIndex].laneIndex}`
	local peLine = "not grading PE"
	local window = peWindows[player]
	if window ~= nil then
		peLine = `PE grading: {string.format("%.1f", window.secondsLeft)}s left, contribution {string.format("%.2f", window.contribution)}`
	end
	return string.format(
		"soccer: %s | %d-%d, %ds left | %s | %s | %s",
		if enabled then "enabled" else "DISABLED",
		m.homeScore,
		m.awayScore,
		math.floor(m.secondsLeft),
		roleLine,
		peLine,
		if m.ball.carrierSlot ~= nil then `carried by {m.roster[m.ball.carrierSlot :: number].name}` else "loose ball"
	)
end

function SoccerService:Start()
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			if DataService.WaitForProfile(player) ~= nil then
				push(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		peWindows[player] = nil
		pushed[player] = nil
		local m = match
		if m ~= nil then
			local slotIndex = playerSlot[player]
			if slotIndex ~= nil then
				revertSlotToBot(m, slotIndex)
			end
		end
	end)

	RequestSoccerJoinRemote.OnServerEvent:Connect(function(player: Player)
		local ok, err = pcall(onJoinRequested, player)
		if not ok then
			warn(`[AGES] soccer join failed for {player.Name}: {err}`)
		end
	end)

	RequestSoccerShootRemote.OnServerEvent:Connect(function(player: Player, held: unknown)
		local ok, err = pcall(onShootRequested, player, held)
		if not ok then
			warn(`[AGES] soccer shoot failed for {player.Name}: {err}`)
		end
	end)

	RequestSoccerPassRemote.OnServerEvent:Connect(function(player: Player)
		local ok, err = pcall(onPassRequested, player)
		if not ok then
			warn(`[AGES] soccer pass failed for {player.Name}: {err}`)
		end
	end)

	task.spawn(function()
		while true do
			local elapsed = task.wait(SOCCER.TickSeconds)
			local ok, err = pcall(tickMatch, elapsed)
			if not ok then
				warn(`[AGES] soccer tick failed: {err}`)
			end
		end
	end)
end

return SoccerService
