--!strict
-- Fighting: the contest for footing, and the only thing in AGES two people do to each
-- other with their hands.
--
-- The loop:
--
--   Somebody is stood in the street with dots over their head. You take the square-up,
--   and from then until one of you is on the floor there are three buttons. Hold Strike
--   to wind up and let go to commit; hold Guard to turn their strike into a stamina
--   problem instead of a footing one; tap Sidestep to make it miss entirely. Footing
--   runs out, somebody goes down, and a few seconds later they get up again.
--
-- **Nobody is hurt here and there is nothing in this file that could hurt them.** There
-- is no health on a fighter, no damage number, no injury and no death. What runs out is
-- footing, and going down is a pose with a timer on it. That is not a rating decision
-- applied on top of a combat system -- it is the combat system, which is why there is
-- no switch anywhere to make it bloodier.
--
-- ## What makes it a fight and not a race
--
-- Three rules do all the work, and each exists to close a degenerate line:
--
--   **A strike never interrupts a wind-up.** Hit somebody who is mid-swing and you both
--   land -- you trade. Without this the whole game is "press Strike whenever they start
--   winding", and the brawler's enormous tell becomes the easiest thing in the file
--   instead of the hardest. With it, trading is a real option that is good against a
--   scrapper hitting for eight and terrible against a brawler hitting for twenty.
--
--   **Only a sidestep negates a strike outright**, and it puts the attacker into the
--   longest recovery in the game. That is what makes the expensive button worth its
--   stamina, and it is the answer the brawler is built to teach.
--
--   **Only a charge held past GuardBreakShare breaks a guard**, which is deep enough
--   into the meter to be inside overcharge -- so breaking a boxer's guard and eating a
--   near-second of recovery are the same decision. There is no safe answer to a guard,
--   only a bet.
--
-- Take any one of those away and the other two stop mattering within an afternoon.
--
-- ## What this file owns and what it does not
--
-- It owns the bout: one per player, at most. It does not own heat, ties, records or
-- what a witness thinks -- a fight in this part is a fight and nothing follows it into
-- the rest of the world. That is deliberate sequencing rather than an oversight: the
-- consequences are the next part, and wiring them in before the contest itself is worth
-- playing would mean tuning the punishment for a mechanic nobody had tried.
--
-- The one exception is the pair of stat outcomes at the bottom, and they are here
-- because an activity whose outcomes do not differ is the anti-pattern this project has
-- already shipped once. Losing costs health, health sets your footing pool, and a
-- shorter bar is what a losing streak feels like from inside the mechanic.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Interact = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Interact"))

local DataService = require(script.Parent.DataService)
local NPCService = require(script.Parent.NPCService)
local StatService = require(script.Parent.StatService)

local Fighters = require(script.Parent.Parent.content.Fighters)
local Ground = require(script.Parent.Parent.world.Ground)

type FighterDef = Types.FighterDef
type FightState = Types.FightState
type Visitor = NPCService.Visitor

local FightService = {}

local FightUpdatedRemote = Remotes.Get("FightUpdated")
local RequestFightActionRemote = Remotes.Get("RequestFightAction")
local RequestFightSquareRemote = Remotes.Get("RequestFightSquare")
local NoticeRemote = Remotes.Get("Notice")

local FIGHT = Config.Fight

-- The one relationship between two Config numbers that the whole triangle rests on, checked
-- loudly at require time because it fails silently in play.
--
-- If a guard can be broken below the overcharge mark, then there is a charge that beats a
-- guard *and* keeps the short recovery -- and the moment that exists it is the correct
-- answer to every opponent in the game, every time, with no read involved. The fight would
-- still run, nothing would error, and the symptom would be a combat system that felt
-- shallow for reasons nobody could point at. That is exactly the kind of defect worth an
-- error() rather than a comment.
if FIGHT.GuardBreakShare <= FIGHT.OverchargeShare then
	error(
		`[AGES config] Fight.GuardBreakShare is {FIGHT.GuardBreakShare} and Fight.OverchargeShare is {FIGHT.OverchargeShare}.`
			.. ` The guard break must sit above the overcharge, or breaking a guard costs nothing and there is one`
			.. ` correct charge for every fight. Raise GuardBreakShare above OverchargeShare in shared/Config.luau.`
	)
end

-- What the opponent is doing. Held as a string rather than recomputed because the wind
-- share the client draws its tell from is a fraction of the *current* intent's clock,
-- and a reader that recomputed the intent would have to recompute the clock with it.
type FoeIntent = "wait" | "close" | "wind" | "guard" | "recover" | "down"

-- The joints the tell is drawn on, and the rest pose to compose onto. Captured once
-- when the body is built rather than read per tick: `C0` is written every frame the
-- opponent is winding up, so a reader that took "rest" from the live joint would be
-- reading its own last frame and the arm would walk away from the shoulder.
type Pose = {
	rightShoulder: Motor6D,
	leftShoulder: Motor6D,
	waist: Motor6D?,
	restRight: CFrame,
	restLeft: CFrame,
	restWaist: CFrame,
}

type Bout = {
	def: FighterDef,
	visitor: Visitor,
	dots: Interact.InteractHandle?,
	pose: Pose?,

	phase: "square" | "fight" | "down" | "over",

	-- The contest.
	footing: number,
	maxFooting: number,
	foeFooting: number,
	foeMaxFooting: number,
	stamina: number,

	-- The player's hands. `charge` only advances while `charging`, and it is the server
	-- that advances it: the client draws a meter from this value and never reports one,
	-- so the strongest thing a forged packet can say is that a button went down.
	charging: boolean,
	charge: number,
	guarding: boolean,
	sidestepLeft: number,
	recoverLeft: number,

	-- The opponent's. `windTotal` is kept beside `timer` so the 0-1 share the tell is
	-- drawn from divides by the length this particular wind-up was started with,
	-- rather than by the archetype's -- which matters the moment anything ever
	-- shortens one.
	intent: FoeIntent,
	timer: number,
	windTotal: number,

	-- The last exchange, and how long it stays on screen.
	beat: string?,
	beatGood: boolean,
	beatLeft: number,

	-- Set once, when it is decided.
	result: string?,
	won: boolean,
	overLeft: number,
	downLeft: number,

	-- Guard against a finish arriving twice, from the tick and from PlayerRemoving.
	ending: boolean,
}

local bouts: { [Player]: Bout } = {}

-- The client only redraws when the digest changes, the same as the gym. Named for
-- every field the client actually draws.
local pushed: { [Player]: string } = {}

-- -------------------------------------------------------------------
-- Harness switch.
--
-- Declared above every reader on purpose: a `local` declared *below* a function that
-- names it is a plain global read inside that function, which is exactly how the gym's
-- Describe came to report DISABLED forever while it was running fine.
-- -------------------------------------------------------------------

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

local function humanoidOf(model: Model?): Humanoid?
	if model == nil then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid
end

-- How much footing somebody with this health starts with.
--
-- Read live rather than cached at the start of the bout, and that is the same call the
-- gym makes about its sweet zone: health lost *during* a fight should shorten the bar
-- you are looking at, because the alternative is a player watching a number change with
-- no effect until the next time they square up.
local function footingFor(health: number): number
	local fitness = math.clamp(health / Config.Stats.Max, 0, 1)
	return FIGHT.BaseFooting * (1 + FIGHT.HealthFootingBonus * fitness)
end

local function healthOf(player: Player): number
	local stats = StatService.GetStats(player)
	return if stats ~= nil then stats.health else 0
end

-- Distance from the player to the opponent, flat. Returns nil when either body is gone,
-- which every caller treats as "the fight cannot continue" rather than as zero.
local function gapTo(player: Player, bout: Bout): number?
	local root = characterRoot(player)
	if root == nil or bout.visitor.gone() then
		return nil
	end
	return Ground.FlatDistance(root.Position, bout.visitor.at())
end

local function say(bout: Bout, line: string, good: boolean)
	bout.beat = line
	bout.beatGood = good
	bout.beatLeft = FIGHT.BeatSeconds
end

-- -------------------------------------------------------------------
-- State push.
-- -------------------------------------------------------------------

local function stateFor(player: Player): FightState?
	local bout = bouts[player]
	if bout == nil then
		return nil
	end

	local gap = gapTo(player, bout)
	return {
		phase = bout.phase,
		foeName = bout.def.body.name,
		foeStyle = bout.def.name,
		foeBlurb = bout.def.blurb,
		footing = bout.footing,
		maxFooting = bout.maxFooting,
		foeFooting = bout.foeFooting,
		foeMaxFooting = bout.foeMaxFooting,
		stamina = bout.stamina,
		maxStamina = FIGHT.MaxStamina,
		charge = bout.charge,
		guarding = bout.guarding,
		sidestepping = bout.sidestepLeft > 0,
		recover = if bout.recoverLeft > 0 then bout.recoverLeft else 0,
		foeIntent = bout.intent,
		foeWind = if bout.intent == "wind" and bout.windTotal > 0
			then math.clamp(1 - bout.timer / bout.windTotal, 0, 1)
			else 0,
		engaged = gap ~= nil and gap <= FIGHT.RangeStuds,
		beat = if bout.beatLeft > 0 then bout.beat else nil,
		beatGood = bout.beatGood,
		jabShare = FIGHT.JabShare,
		guardBreakShare = FIGHT.GuardBreakShare,
		overchargeShare = FIGHT.OverchargeShare,
		result = bout.result,
		won = bout.won,
	}
end

local function push(player: Player)
	local state = stateFor(player)
	-- The charge and the opponent's wind share are both in the digest at a coarse
	-- resolution: they move every tick while anything is happening, and they are the two
	-- things the player is actually reading, so a redraw they miss is a tell they miss.
	local digest = if state == nil
		then "none"
		else `{state.phase}|{math.floor(state.footing)}/{math.floor(state.maxFooting)}`
			.. `|{math.floor(state.foeFooting)}/{math.floor(state.foeMaxFooting)}`
			.. `|{math.floor(state.stamina)}|{math.floor(state.charge * 50)}`
			.. `|{tostring(state.guarding)}|{tostring(state.sidestepping)}`
			.. `|{math.floor(state.recover * 20)}|{state.foeIntent}`
			.. `|{math.floor(state.foeWind * 50)}|{tostring(state.engaged)}`
			.. `|{tostring(state.beat)}|{tostring(state.result)}`
	if pushed[player] == digest then
		return
	end
	pushed[player] = digest
	FightUpdatedRemote:FireClient(player, state)
end

-- -------------------------------------------------------------------
-- Going down, and getting back up.
--
-- Both sides use the humanoid's own sit state. It costs no asset, no animation and no
-- new rig, it reads exactly as "on the floor", and -- the part that matters -- it is
-- trivially reversible, which is the whole requirement: whatever puts somebody down has
-- to be able to put them back up a few seconds later without leaving a trace.
-- -------------------------------------------------------------------

local function setFloored(humanoid: Humanoid?, floored: boolean)
	if humanoid == nil then
		return
	end
	humanoid.Sit = floored
end

-- -------------------------------------------------------------------
-- The tell, on the body.
--
-- Everything above this line was already replicated to the client and drawn as a bar in
-- the bottom-centre panel. That bar is a good bar and it stays. The problem it cannot
-- solve is that **the opponent was visually inert**: the whole skill of a fight is
-- reading *when*, and until now the only place "when" existed was a rectangle at the
-- bottom of the screen. A player who looked at the person hitting them learned nothing,
-- which makes this a UI game with a 3D backdrop rather than a fight.
--
-- It also quietly cancelled the archetypes. Fighters.luau says the brawler's build
-- should tell you "across a street which question is about to be asked" -- but a brawler,
-- a scrapper and a boxer all stood in the identical rest pose and differed only in how
-- fast a bar filled. Requirement 7 of the activity law, same input different opponent,
-- was true in the numbers and invisible in the world.
--
-- **Server-side, because the opponent is in workspace.Visitors and everybody can see
-- them.** A client-side pose would leave a bystander watching two people mime a fight at
-- a statue.
--
-- **Driven from `intent` and `timer`, which are the same fields the bar is drawn from**,
-- so the body and the panel cannot drift apart. Not a second clock -- there is no new
-- state here at all, only a reading of state that already existed.
-- -------------------------------------------------------------------

-- The hardest hit anybody in the roster throws, so a wind-up's size can be a share of it
-- rather than a number typed per archetype. This is the whole per-fighter difference in
-- the pose: the brawler already hits for 20 and the scrapper for 8, and drawing the
-- rear-back at that ratio means the tell is enormous or a flick *for the reason it
-- should be* -- because of what is about to land -- instead of because a second table
-- said so. Add a fighter and their tell sizes itself.
local HARDEST_STRIKE = 0
for _, def in Fighters.All do
	HARDEST_STRIKE = math.max(HARDEST_STRIKE, def.strikeFooting)
end
if HARDEST_STRIKE <= 0 then
	error("[AGES] no fighter throws a strike worth more than zero footing, so no wind-up could be drawn")
end

-- How far the smallest hitter still leans. Without a floor the scrapper's 8-of-20 would
-- read as barely moving at all, and "too fast to react to" is the lesson she is meant to
-- teach -- not "invisible".
local TELL_FLOOR = 0.45

-- Where a limb points, in the upper torso's own space: -Z is forward, +Y is up, +X is the
-- fighter's right. Written as directions rather than as Euler angles on purpose -- the
-- rotation is then built by `aimLimb` from the arm's rest axis, so none of this depends
-- on knowing which way R15 happens to orient a shoulder's C0. Guessing that sign is how
-- you ship a fighter who winds up by putting his arm through his own chest.
local ARM_REST = Vector3.new(0, -1, 0)
local ARM_WOUND = Vector3.new(0.45, 0.30, 0.85) -- back, out and up: the cocked arm
local ARM_THROWN = Vector3.new(0.15, -0.25, -0.95) -- through the target, still extended
local ARM_GUARD_R = Vector3.new(0.25, 0.55, -0.80) -- hands up in front of the face
local ARM_GUARD_L = Vector3.new(-0.25, 0.55, -0.80)
local ARM_COVER_L = Vector3.new(-0.25, 0.45, -0.85) -- the off hand, up while the other winds

-- The shoulders turn with the punch. Yaw only, so this one *is* a plain angle: rotation
-- about Y is unambiguous in any rig.
local WAIST_WOUND_DEGREES = 22
local WAIST_THROWN_DEGREES = -14

-- The rotation that takes a limb's rest axis onto `dir`, both in the joint's own space.
-- Axis-and-angle rather than composed Euler terms because the question being asked is
-- "point the arm there", and that is one rotation with one answer.
local function aimLimb(dir: Vector3): CFrame
	local target = dir.Unit
	local dot = math.clamp(ARM_REST:Dot(target), -1, 1)
	if dot > 0.9999 then
		return CFrame.identity
	end
	if dot < -0.9999 then
		-- Straight up. The cross product is degenerate here, so pick an axis rather than
		-- normalising a zero vector -- which returns NaN and silently deletes the arm.
		return CFrame.fromAxisAngle(Vector3.new(1, 0, 0), math.pi)
	end
	return CFrame.fromAxisAngle(ARM_REST:Cross(target).Unit, math.acos(dot))
end

local function poseOf(model: Model?): Pose?
	if model == nil then
		return nil
	end
	local rightArm = model:FindFirstChild("RightUpperArm")
	local leftArm = model:FindFirstChild("LeftUpperArm")
	local torso = model:FindFirstChild("UpperTorso")
	if rightArm == nil or leftArm == nil then
		return nil
	end
	local right = rightArm:FindFirstChild("RightShoulder") :: Motor6D?
	local left = leftArm:FindFirstChild("LeftShoulder") :: Motor6D?
	local waist = if torso ~= nil then torso:FindFirstChild("Waist") :: Motor6D? else nil
	if right == nil or left == nil then
		return nil
	end
	return {
		rightShoulder = right,
		leftShoulder = left,
		waist = waist,
		restRight = right.C0,
		restLeft = left.C0,
		restWaist = if waist ~= nil then waist.C0 else CFrame.identity,
	}
end

-- Back to standing. Called from teardown and from going down, so a bout that ends
-- mid-wind-up does not leave a body frozen with its arm cocked.
local function poseRest(pose: Pose?)
	if pose == nil then
		return
	end
	pose.rightShoulder.C0 = pose.restRight
	pose.leftShoulder.C0 = pose.restLeft
	local waist = pose.waist
	if waist ~= nil then
		waist.C0 = pose.restWaist
	end
end

local function posedTo(pose: Pose, right: Vector3, left: Vector3, waistDegrees: number)
	pose.rightShoulder.C0 = pose.restRight * aimLimb(right)
	pose.leftShoulder.C0 = pose.restLeft * aimLimb(left)
	local waist = pose.waist
	if waist ~= nil then
		waist.C0 = pose.restWaist * CFrame.Angles(0, math.rad(waistDegrees), 0)
	end
end

-- The one reader. `share` runs 0 at the start of whatever the opponent is doing to 1 at
-- the end of it, and the arm's position *is* the clock -- linear, deliberately, because
-- an eased tell is a tell that lies about how much time is left.
local function poseFoe(bout: Bout)
	local pose = bout.pose
	if pose == nil then
		return
	end
	if bout.phase ~= "fight" then
		poseRest(pose)
		return
	end

	local reach = math.max(TELL_FLOOR, bout.def.strikeFooting / HARDEST_STRIKE)

	if bout.intent == "wind" then
		local total = math.max(bout.windTotal, 1e-3)
		local share = math.clamp(1 - bout.timer / total, 0, 1)
		posedTo(
			pose,
			ARM_REST:Lerp(ARM_WOUND, share * reach),
			ARM_REST:Lerp(ARM_COVER_L, share),
			WAIST_WOUND_DEGREES * share * reach
		)
	elseif bout.intent == "recover" then
		-- The punish window, and the reason it is drawn at all: an opponent who has just
		-- swung and missed should *look* open. The arm returns from thrown to rest over
		-- the recovery, so how far it has come back is how much of the window is left.
		local total = math.max(bout.def.recoverSeconds, 1e-3)
		local left = math.clamp(bout.timer / total, 0, 1)
		posedTo(
			pose,
			ARM_THROWN:Lerp(ARM_REST, 1 - left),
			ARM_REST,
			WAIST_THROWN_DEGREES * left * reach
		)
	elseif bout.intent == "guard" then
		posedTo(pose, ARM_GUARD_R, ARM_GUARD_L, 0)
	else
		-- wait and close. Hands down; the fight is not happening this instant and the
		-- body should say so, because "nothing is coming" is a read too.
		poseRest(pose)
	end
end

-- -------------------------------------------------------------------
-- Teardown. One exit, and it does not know why it is being called -- the same shape
-- PoliceService uses for officers, and for the same reason: every way a fight can end
-- has to leave the world in the identical state, or the one path nobody tested is the
-- one that leaves an NPC standing in the street forever.
-- -------------------------------------------------------------------

local function teardown(player: Player, bout: Bout)
	-- Before the body goes, in case it is not going: ForceEnd and a new life both
	-- come through here, and an opponent left standing with a cocked arm is worse
	-- than one left standing.
	poseRest(bout.pose)
	local dots = bout.dots
	if dots ~= nil then
		dots.Destroy()
		bout.dots = nil
	end
	setFloored(humanoidOf(player.Character), false)
	if not bout.visitor.gone() then
		bout.visitor.destroy()
	end
	bouts[player] = nil
end

local function finish(player: Player, bout: Bout, line: string?)
	if bout.ending then
		return
	end
	bout.ending = true
	teardown(player, bout)
	if line ~= nil then
		NoticeRemote:FireClient(player, line)
	end
	push(player)
end

-- Somebody hit zero. Decides the outcome, pays it out, and hands over to the down beat.
--
-- The payout happens here rather than when the down beat expires, because the beat is
-- three seconds during which the player can disconnect, die of old age or be arrested,
-- and a result that is only banked at the end of it is a result a player can lose by
-- walking away from their keyboard.
local function decide(player: Player, bout: Bout, playerWon: boolean)
	bout.phase = "down"
	poseRest(bout.pose)
	bout.downLeft = FIGHT.DownSeconds
	bout.won = playerWon
	bout.charging = false
	bout.charge = 0
	bout.guarding = false
	bout.sidestepLeft = 0
	bout.recoverLeft = 0
	bout.intent = if playerWon then "down" else "wait"
	bout.visitor.halt()

	if playerWon then
		bout.result = `{bout.def.body.name} went down.`
		setFloored(humanoidOf(bout.visitor.model), true)
		StatService.AddStat(player, "happiness", FIGHT.WinHappiness)
	else
		bout.result = "You went down."
		setFloored(humanoidOf(player.Character), true)
		StatService.AddStat(player, "health", -FIGHT.LossHealth)
	end
	push(player)
end

-- -------------------------------------------------------------------
-- Resolving a strike.
--
-- Two functions, one per direction, and they are deliberately not shared. They look
-- similar and they are not the same rules: only the player has a charge meter, and only
-- the opponent can be caught in a guard the player chose to break. A single "resolve"
-- taking a side flag would have to branch on it four times, which is the same code with
-- the reader's job made harder.
-- -------------------------------------------------------------------

-- The opponent's wind-up has completed and lands on the player.
local function foeStrikeLands(player: Player, bout: Bout)
	local gap = gapTo(player, bout)
	if gap == nil or gap > FIGHT.RangeStuds then
		-- They swung at where you were. Out of range is its own answer and it costs
		-- them the same long recovery a sidestep does, which is what makes backing off
		-- mid-wind a real option rather than only a stamina decision.
		bout.intent = "recover"
		bout.timer = FIGHT.WhiffRecoverSeconds
		say(bout, "They missed", true)
		return
	end

	if bout.sidestepLeft > 0 then
		bout.intent = "recover"
		bout.timer = FIGHT.WhiffRecoverSeconds
		say(bout, "Dodged", true)
		return
	end

	local power = bout.def.strikeFooting
	if bout.guarding then
		bout.footing -= power * FIGHT.GuardedFootingShare
		bout.stamina = math.max(0, bout.stamina - power * FIGHT.GuardedStaminaShare)
		say(bout, "Blocked", true)
	else
		bout.footing -= power
		say(bout, "Hit", false)
	end

	bout.intent = "recover"
	bout.timer = bout.def.recoverSeconds
end

-- The player let go of Strike. `share` is how far the meter had filled.
local function playerStrikeLands(player: Player, bout: Bout, share: number)
	local gap = gapTo(player, bout)
	local engaged = gap ~= nil and gap <= FIGHT.RangeStuds

	-- A release below the jab mark is still a strike. There is no dead zone, because an
	-- input that silently does nothing is the one thing a player cannot learn from.
	local effective = math.max(share, FIGHT.JabShare)
	local power = FIGHT.StrikeFootingMin
		+ (FIGHT.StrikeFootingMax - FIGHT.StrikeFootingMin) * effective
	local overcharged = share >= FIGHT.OverchargeShare
	if overcharged then
		power *= FIGHT.OverchargeFootingScale
	end

	if not engaged then
		bout.recoverLeft = FIGHT.WhiffRecoverSeconds
		say(bout, "Whiffed", false)
		return
	end

	if bout.intent == "guard" then
		if share >= FIGHT.GuardBreakShare then
			bout.foeFooting -= power * FIGHT.GuardBreakFootingScale
			bout.intent = "recover"
			bout.timer = FIGHT.GuardBreakRecoverSeconds
			say(bout, "Broke guard", true)
		else
			bout.foeFooting -= power * FIGHT.GuardedFootingShare
			say(bout, "They blocked", false)
		end
	else
		-- Lands, and does *not* interrupt. If they were mid-wind that swing is still
		-- coming: this is the trade, and it is the rule the whole triangle rests on.
		bout.foeFooting -= power
		say(bout, if overcharged then "Big hit" else "Clean hit", true)
	end

	bout.recoverLeft = if overcharged
		then FIGHT.OverchargeRecoverSeconds
		else FIGHT.StrikeRecoverSeconds
end

-- -------------------------------------------------------------------
-- The opponent's turn. One state machine, four states, no lookahead: it does not know
-- what the player is holding and it must not, because an opponent that read the guard
-- before choosing would never be punishable and the whole read would run backwards.
-- -------------------------------------------------------------------

local function tickFoe(player: Player, bout: Bout, elapsed: number)
	local gap = gapTo(player, bout)
	if gap == nil then
		return
	end

	bout.timer -= elapsed

	if bout.intent == "close" then
		if gap <= FIGHT.RangeStuds then
			bout.visitor.halt()
			bout.intent = "wait"
			bout.timer = bout.def.restSeconds
		else
			local root = characterRoot(player)
			if root ~= nil then
				bout.visitor.moveTo(root.Position)
			end
		end
		return
	end

	-- Out of reach in any other state: go and close the distance. Checked before the
	-- timer so that a wind-up started at range is abandoned rather than swung at nobody,
	-- which otherwise reads as an opponent attacking thin air.
	if gap > FIGHT.RangeStuds then
		bout.intent = "close"
		bout.timer = 0
		return
	end

	local root = characterRoot(player)
	if root ~= nil then
		bout.visitor.face(root.Position)
	end

	if bout.timer > 0 then
		return
	end

	if bout.intent == "wind" then
		foeStrikeLands(player, bout)
		return
	end

	-- Recovering ends into a pause, not straight into the next wind-up, and this is the
	-- line that makes restSeconds load-bearing rather than decorative. Without it every
	-- archetype runs wind-strike-recover-wind with no gap in it, which collapses the
	-- brawler and the scrapper onto the same relentless rhythm and deletes the one
	-- difference the player is supposed to feel between them -- the brawler's 0.7s gap is
	-- the room you get for having read him, and the scrapper's 0.2s is why she is
	-- answered with a guard instead of a punish.
	if bout.intent == "recover" then
		bout.intent = "wait"
		bout.timer = bout.def.restSeconds
		return
	end

	-- "wait" and "guard" both end the same way: pick the next thing.
	if math.random() < bout.def.guardChance then
		bout.intent = "guard"
		bout.timer = bout.def.guardSeconds
	else
		bout.intent = "wind"
		bout.timer = bout.def.windSeconds
		bout.windTotal = bout.def.windSeconds
	end
end

-- -------------------------------------------------------------------
-- The tick.
-- -------------------------------------------------------------------

local function tickPlayer(player: Player, elapsed: number)
	local bout = bouts[player]
	if bout == nil then
		return
	end

	-- Honoured here rather than around the loop so a fight already running when the
	-- system is switched off is closed out and reported, instead of being abandoned with
	-- an NPC left standing in the road.
	if not enabled then
		finish(player, bout, "The fight broke up.")
		return
	end

	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	if not Lives.Active(profile.Data).alive then
		finish(player, bout, nil)
		return
	end

	if bout.beatLeft > 0 then
		bout.beatLeft -= elapsed
	end

	if bout.phase == "over" then
		bout.overLeft -= elapsed
		if bout.overLeft <= 0 then
			finish(player, bout, nil)
			return
		end
		push(player)
		return
	end

	if bout.phase == "down" then
		bout.downLeft -= elapsed
		if bout.downLeft <= 0 then
			-- Back up. The result stays on screen for the over beat, which is the part
			-- the player reads; the getting up is what makes it a fight rather than an
			-- injury, and it happens whether they won or lost.
			setFloored(humanoidOf(player.Character), false)
			setFloored(humanoidOf(bout.visitor.model), false)
			bout.phase = "over"
			bout.overLeft = FIGHT.OverSeconds
		end
		push(player)
		return
	end

	local gap = gapTo(player, bout)
	if gap == nil then
		finish(player, bout, nil)
		return
	end

	if bout.phase == "square" then
		-- Waiting to be taken up on it. They stand and watch; walk far enough away and
		-- the offer goes with them.
		if gap > FIGHT.BreakStuds then
			finish(player, bout, nil)
			return
		end
		local root = characterRoot(player)
		if root ~= nil then
			bout.visitor.face(root.Position)
		end
		push(player)
		return
	end

	-- From here the fight is live.
	if gap > FIGHT.BreakStuds then
		finish(player, bout, "You walked away from it.")
		return
	end

	local engaged = gap <= FIGHT.RangeStuds

	-- Stamina. The gap between these two rates is the entire pacing mechanism: it is
	-- what turns a fight into exchange, break, exchange without a timer telling it to.
	local recovery = if engaged then FIGHT.StaminaPerSecondEngaged else FIGHT.StaminaPerSecondClear
	bout.stamina = math.min(FIGHT.MaxStamina, bout.stamina + recovery * elapsed)

	if bout.recoverLeft > 0 then
		bout.recoverLeft -= elapsed
		-- A lockout drops everything. Holding guard through your own recovery would make
		-- the punish window free, which is the one thing it must never be.
		if bout.recoverLeft > 0 then
			bout.charging = false
			bout.charge = 0
			bout.guarding = false
		end
	end

	if bout.sidestepLeft > 0 then
		bout.sidestepLeft -= elapsed
	end

	if bout.guarding then
		bout.stamina = math.max(0, bout.stamina - FIGHT.GuardStaminaPerSecond * elapsed)
		if bout.stamina <= 0 then
			-- Guard collapses rather than being held for free at zero. Said out loud,
			-- because a block that quietly stopped blocking is indistinguishable from a
			-- bug from the other side of the screen.
			bout.guarding = false
			say(bout, "Guard gave out", false)
		end
	end

	if bout.charging then
		bout.charge = math.min(1, bout.charge + elapsed / FIGHT.ChargeSeconds)
	end

	tickFoe(player, bout, elapsed)

	-- Checked after both sides have acted so a trade that puts both fighters down
	-- resolves the same way every time: the player's own footing is read first, so
	-- trading your last footing for theirs is a loss. Going out on your feet is not a
	-- thing this game lets you do by accident.
	if bout.footing <= 0 then
		decide(player, bout, false)
		return
	end
	if bout.foeFooting <= 0 then
		decide(player, bout, true)
		return
	end

	push(player)
end

-- -------------------------------------------------------------------
-- Remote handlers.
-- -------------------------------------------------------------------

local function onSquareRequested(player: Player, id: unknown)
	local bout = bouts[player]
	if bout == nil or bout.phase ~= "square" then
		return
	end
	if type(id) ~= "string" or id ~= bout.def.id then
		-- The id is checked against the one actually stood in front of this player
		-- rather than looked up in the content table, so a forged packet cannot pick
		-- which opponent it is fighting.
		return
	end
	bout.phase = "fight"
	local dots = bout.dots
	if dots ~= nil then
		-- The dots go the moment it starts. Leaving them up would put a "square up"
		-- prompt on somebody already swinging at you.
		dots.Destroy()
		bout.dots = nil
	end
	bout.intent = "close"
	bout.timer = 0
	bout.visitor.setSpeed(FIGHT.FoeWalkSpeed)
	push(player)
end

local function onActionRequested(player: Player, action: unknown, held: unknown)
	local bout = bouts[player]
	if bout == nil or bout.phase ~= "fight" then
		return
	end
	if type(action) ~= "string" then
		return
	end

	-- Locked out. Refused rather than queued: an input that fires when the lockout ends
	-- would let a player buffer through their own punish window, which is the window the
	-- opponent just earned.
	if bout.recoverLeft > 0 then
		return
	end

	if action == "strike" then
		if held == true then
			if bout.stamina < FIGHT.StrikeStamina then
				say(bout, "Winded", false)
				push(player)
				return
			end
			bout.guarding = false
			bout.charging = true
			bout.charge = 0
		elseif bout.charging then
			local share = bout.charge
			bout.charging = false
			bout.charge = 0
			bout.stamina = math.max(0, bout.stamina - FIGHT.StrikeStamina)
			playerStrikeLands(player, bout, share)
		end
	elseif action == "guard" then
		if held == true then
			if bout.stamina <= 0 then
				say(bout, "Winded", false)
				push(player)
				return
			end
			-- Guarding cancels a wind-up rather than stacking with it. The two are
			-- opposite answers and holding both would be holding neither.
			bout.charging = false
			bout.charge = 0
			bout.guarding = true
		else
			bout.guarding = false
		end
	elseif action == "sidestep" then
		if bout.stamina < FIGHT.SidestepStamina then
			say(bout, "Winded", false)
			push(player)
			return
		end
		bout.stamina -= FIGHT.SidestepStamina
		bout.charging = false
		bout.charge = 0
		bout.guarding = false
		bout.sidestepLeft = FIGHT.SidestepSeconds
		bout.recoverLeft = FIGHT.SidestepRecoverSeconds
	else
		return
	end

	push(player)
end

-- -------------------------------------------------------------------
-- Cleanup.
-- -------------------------------------------------------------------

local function forget(player: Player)
	local bout = bouts[player]
	if bout ~= nil then
		teardown(player, bout)
	end
	pushed[player] = nil
end

-- -------------------------------------------------------------------
-- Public API.
-- -------------------------------------------------------------------

-- Stands somebody in front of the player, waiting to be squared up to.
--
-- Yields on a web call inside NPCService.Spawn, so everything after it is re-checked --
-- the player can have walked off, died or picked up a different fight in the meantime.
function FightService.Challenge(player: Player, fighterId: string?): (boolean, string?)
	if not enabled then
		return false, "fighting is switched off"
	end
	if bouts[player] ~= nil then
		return false, "already in a fight"
	end

	local def = if fighterId ~= nil then Fighters.ById[fighterId] else Fighters.Default
	if def == nil then
		return false, `no fighter with id "{fighterId}"`
	end

	local root = characterRoot(player)
	if root == nil then
		return false, "no character"
	end

	-- In front of them, far enough back to be squared up to rather than stood on. Put
	-- through the same ground probe every other spawned body uses, so a challenger
	-- cannot appear inside a wall or off the edge of a pavement.
	local ahead = root.Position + root.CFrame.LookVector * FIGHT.SquareUpStuds
	local spot = Ground.SpotAt(ahead, Ground.BodyRadius(player.Character :: Model), Ground.BodyHeight(player.Character :: Model), Ground.IgnoreList(), root.Position)
	if spot == nil then
		return false, "nowhere to stand them"
	end

	local visitor = NPCService.Spawn(player, def.body, CFrame.lookAt(spot, root.Position), def.ageYears)
	if visitor == nil then
		return false, "could not build the body"
	end
	if bouts[player] ~= nil then
		visitor.destroy()
		return false, "already in a fight"
	end

	local maxFooting = footingFor(healthOf(player))
	local bout: Bout = {
		def = def,
		visitor = visitor,
		dots = nil,
		-- Nil is a supported answer, not a failure: a rig that arrives without the
		-- joints still fights, it just fights without the body tell. Warned about
		-- rather than errored on, because losing the tell should not lose the bout.
		pose = poseOf(visitor.model),
		phase = "square",
		footing = maxFooting,
		maxFooting = maxFooting,
		foeFooting = FIGHT.BaseFooting * def.footingScale,
		foeMaxFooting = FIGHT.BaseFooting * def.footingScale,
		stamina = FIGHT.MaxStamina,
		charging = false,
		charge = 0,
		guarding = false,
		sidestepLeft = 0,
		recoverLeft = 0,
		intent = "wait",
		timer = 0,
		windTotal = def.windSeconds,
		beat = nil,
		beatGood = true,
		beatLeft = 0,
		result = nil,
		won = false,
		overLeft = 0,
		downLeft = 0,
		ending = false,
	}
	bouts[player] = bout

	local dots = Interact.Attach(visitor.model, {
		kind = "Fight",
		id = def.id,
		actionText = "Square up",
		objectText = def.body.name,
		nameplate = { name = def.body.name, age = def.ageYears },
	})
	if dots == nil then
		-- Worth saying out loud because the symptom is silent and reads as content: a
		-- stranger stood in the road who can be circled forever and never answered.
		warn(`[AGES] could not put dots over the {def.name} -- they cannot be squared up to`)
	end
	bout.dots = dots
	push(player)
	return true, nil
end

-- A new life. Nobody inherits a fight.
function FightService.ResetForNewLife(player: Player)
	forget(player)
	push(player)
end

function FightService.ForceEnd(player: Player): boolean
	local bout = bouts[player]
	if bout == nil then
		return false
	end
	finish(player, bout, nil)
	return true
end

-- Puts the fight straight to a result, for testing what follows one without having to
-- win it first. Takes the same path a real decision does rather than a shortcut, which
-- is the point: a debug command that skips the payout tests nothing.
function FightService.ForceDecide(player: Player, playerWon: boolean): boolean
	local bout = bouts[player]
	if bout == nil or bout.phase ~= "fight" then
		return false
	end
	decide(player, bout, playerWon)
	return true
end

function FightService.Describe(player: Player): string
	local bout = bouts[player]
	local styles: { string } = {}
	for _, def in Fighters.All do
		table.insert(styles, `{def.id} (wind {def.windSeconds}s, hits {def.strikeFooting}, guards {math.floor(def.guardChance * 100)}%)`)
	end

	if bout == nil then
		return string.format(
			"fight: no fight | footing at this health would be %.0f | %s | %s",
			footingFor(healthOf(player)),
			table.concat(styles, ", "),
			if enabled then "enabled" else "DISABLED"
		)
	end

	local gap = gapTo(player, bout)
	return string.format(
		"fight: %s vs %s | phase %s | you %.0f/%.0f footing, %.0f stamina, charge %.2f%s%s | them %.0f/%.0f, %s %.2fs | gap %s | %s",
		bout.def.id,
		bout.def.body.name,
		bout.phase,
		bout.footing,
		bout.maxFooting,
		bout.stamina,
		bout.charge,
		if bout.guarding then ", guarding" else "",
		if bout.recoverLeft > 0 then string.format(", locked %.2fs", bout.recoverLeft) else "",
		bout.foeFooting,
		bout.foeMaxFooting,
		bout.intent,
		bout.timer,
		if gap ~= nil then string.format("%.1f", gap) else "gone",
		if enabled then "enabled" else "DISABLED"
	)
end

function FightService.SetEnabled(value: boolean)
	enabled = value
	if value then
		return
	end
	-- Switching off closes what is running. Left alone, a disabled system would keep a
	-- half-finished fight on screen with an NPC frozen in the road and no tick coming to
	-- clear either.
	for player, bout in bouts do
		finish(player, bout, "The fight broke up.")
	end
end

function FightService.IsEnabled(): boolean
	return enabled
end

function FightService.Styles(): { string }
	local ids: { string } = {}
	for _, def in Fighters.All do
		table.insert(ids, def.id)
	end
	return ids
end

-- -------------------------------------------------------------------
-- Start.
-- -------------------------------------------------------------------

-- No Init. There is nothing this needs to stand up before the other services exist -- the
-- remotes are fetched at require time and the first opponent is spawned on demand -- and an
-- empty Init registered in the boot sequence is a line that looks load-bearing and is not.
function FightService:Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		forget(player)
	end)

	RequestFightSquareRemote.OnServerEvent:Connect(function(player: Player, id: unknown)
		local ok, err = pcall(onSquareRequested, player, id)
		if not ok then
			warn(`[AGES] fight square failed for {player.Name}: {err}`)
		end
	end)

	RequestFightActionRemote.OnServerEvent:Connect(function(player: Player, action: unknown, held: unknown)
		local ok, err = pcall(onActionRequested, player, action, held)
		if not ok then
			warn(`[AGES] fight action failed for {player.Name}: {err}`)
		end
	end)

	task.spawn(function()
		while true do
			local elapsed = task.wait(FIGHT.TickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player, elapsed)
				if not ok then
					warn(`[AGES] fight tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)

	-- The body tell runs on its own clock, faster than the bout does, and that split is
	-- the whole reason it is a second loop rather than a line in the first one.
	--
	-- The bout ticks at Fight.TickSeconds = 0.1. A scrapper's wind-up is 0.55s, so a
	-- pose driven off the bout tick would draw her entire tell in five steps -- and this
	-- file already knows what that looks like, because NPCService measured it for the
	-- head-turn and wrote the answer down: "above ~0.2 the head visibly steps."
	--
	-- So the rate is NPC.LookTickSeconds, borrowed rather than added to Config. It is the
	-- same measurement -- how often a joint on a visitor rig has to move to stop reading
	-- as stepping -- and this project has been bitten enough times by two constants
	-- describing one fact. If that number is ever retuned, this follows it, which is
	-- correct: they would be retuning the thing this depends on.
	--
	-- Nothing here advances state. It only reads the bout the loop above owns and writes
	-- C0, so the two cannot race in any way that matters: the worst case is one frame
	-- posed from a timer 0.1s stale, which is a pose 6% along a wind-up it already knew
	-- about.
	task.spawn(function()
		while true do
			task.wait(Config.NPC.LookTickSeconds)
			for _, bout in bouts do
				local ok, err = pcall(poseFoe, bout)
				if not ok then
					warn(`[AGES] fight pose failed: {err}`)
				end
			end
		end
	end)
end

return FightService
