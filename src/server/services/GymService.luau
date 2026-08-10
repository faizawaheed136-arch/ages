--!strict
-- Gym: the room where effort becomes something you can read.
--
-- The loop:
--
--   You walk to a machine and the server notices you are there. A panel offers
--   a workout; you press Start. A sweep bar travels left to right; you press
--   PUSH while it is in the sweet zone. Quality is graded by how close to
--   centre the hit lands. Ten reps or an empty stamina bar ends the session.
--
-- The gym is a room of machines that exist in the world as tagged parts. Nothing
-- here builds the room -- the world is built by hand and this finds it, so
-- replacing a machine means swapping a part in Studio and keeping the tag.
-- A machine is a thing you stand at, not a question you sit for, which is
-- why there are four of them in the same room and the school has one door.
--
-- Stats gained: health and looks. The only two a gym can move honestly --
-- effort makes you fitter and it makes you look it, and nothing in a weight
-- room makes you smarter. Both are capped by the per-machine yearly limit
-- so a session is a meaningful investment rather than a button you can hammer.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Sweep = require(ReplicatedStorage:WaitForChild("Sweep"))

local DataService = require(script.Parent.DataService)
local StatService = require(script.Parent.StatService)
local Ground = require(script.Parent.Parent.world.Ground)

type LifeData = Types.LifeData
type WorkoutState = Types.WorkoutState

local GymService = {}

local WorkoutUpdatedRemote = Remotes.Get("WorkoutUpdated")
local RequestStartWorkoutRemote = Remotes.Get("RequestStartWorkout")
local RequestRepRemote = Remotes.Get("RequestRep")
local NoticeRemote = Remotes.Get("Notice")

local GYM = Config.Gym
local KINDS = GYM.Kinds

-- The sweet zone for a machine, widened by how fit the character is.
--
-- Returns half-widths, because every caller wants distance-from-centre. Health is
-- read live rather than cached on the session so that the health earned during a
-- workout widens the window for the reps still to come -- the player watches their
-- own margin grow inside the activity that is growing it, which is the one thing
-- the old fixed-width bar could never show.
local function windowFor(machine: string, health: number): (number, number)
	local kind = KINDS[machine]
	local fitness = math.clamp(health / Config.Stats.Max, 0, 1)
	local widen = 1 + GYM.HealthWindowBonus * fitness
	return (kind.sweetFraction * widen) / 2, (kind.perfectFraction * widen) / 2
end

-- Health, or zero if the profile is not loaded yet. Zero rather than a default,
-- because a missing profile should hand out the narrowest window rather than a free
-- one -- and in practice the panel that would use it is not on screen yet either.
local function healthOf(player: Player): number
	local stats = StatService.GetStats(player)
	return if stats ~= nil then stats.health else 0
end

-- -------------------------------------------------------------------
-- Machine index: tagged parts grouped by their kind attribute.
-- -------------------------------------------------------------------

type MachineEntry = {
	part: BasePart,
	kind: string,
}

local allMachines: { MachineEntry } = {}
local machinesByKind: { [string]: { MachineEntry } } = {}

local function registerMachine(part: BasePart)
	if not part:IsA("BasePart") then
		return
	end
	local raw = part:GetAttribute(GYM.GymKindAttribute)
	if raw == nil or type(raw) ~= "string" or raw == "" then
		warn(`[AGES] gym equipment "{part:GetFullName()}" has no "{GYM.GymKindAttribute}" attribute`)
		return
	end
	if KINDS[raw] == nil then
		warn(`[AGES] gym equipment "{part:GetFullName()}" has unknown kind "{raw}"`)
		return
	end
	local entry = { part = part, kind = raw }
	table.insert(allMachines, entry)
	local list = machinesByKind[raw]
	if list == nil then
		list = {}
		machinesByKind[raw] = list
	end
	table.insert(list, entry)
end

local function unregisterMachine(part: BasePart)
	for i = #allMachines, 1, -1 do
		if allMachines[i].part == part then
			table.remove(allMachines, i)
			break
		end
	end
	for _, list in machinesByKind do
		for i = #list, 1, -1 do
			if list[i].part == part then
				table.remove(list, i)
				break
			end
		end
	end
end

-- -------------------------------------------------------------------
-- Distance and position helpers.
-- -------------------------------------------------------------------


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

-- Which machine kind, if any, the player is standing next to. Returns nil
-- if the player is near no machine or has no character. When multiple machines
-- are within reach the closest one wins, so a player between a treadmill and
-- a bench gets whichever is nearer rather than whichever was indexed first.
local function machineNear(player: Player): (string?, Vector3?)
	local position = characterPosition(player)
	if position == nil then
		return nil, nil
	end
	local bestKind: string? = nil
	local bestAt: Vector3? = nil
	local bestDist = math.huge
	for _, entry in allMachines do
		local dist = Ground.FlatDistance(position, entry.part.Position)
		if dist <= GYM.ReachStuds and dist < bestDist then
			bestDist = dist
			bestKind = entry.kind
			bestAt = entry.part.Position
		end
	end
	return bestKind, bestAt
end

-- -------------------------------------------------------------------
-- Session state: one per player, at most one at a time.
-- -------------------------------------------------------------------

type Session = {
	-- The machine kind this session uses. Immutable once the session starts.
	machine: string,
	-- The machine part's world position at the start of the session. Locked
	-- because the player's radius is checked against this rather than against
	-- the live part position -- the session belongs to the spot it started at,
	-- not to wherever the part might have been dragged in Studio.
	at: Vector3,
	-- Rep counter. Starts at 1, increments after each verdict beat.
	rep: number,
	-- Total reps attempted so far (set at start from Config).
	reps: number,
	-- Session-local stamina. Starts at MaxStamina, drains per rep.
	stamina: number,
	-- Running totals of gains, for the client to display and for the final
	-- notice to report.
	healthGained: number,
	looksGained: number,
	-- Seconds of live sweep elapsed in the current rep. The needle position is
	-- derived from this through the machine's curve every tick rather than being
	-- advanced in place, so the clock and the needle cannot drift apart.
	sweptSeconds: number,
	-- Current needle position 0-1, authoritative. Derived from sweptSeconds; held
	-- here because the push digest and the grade both need the value the player
	-- actually saw, not one recomputed a tick later.
	progress: number,
	-- Countdown for the verdict beat. While > 0 the sweep is frozen and the
	-- client shows the grade.
	verdictLeft: number,
	-- The grade the last hit earned: "Perfect", "Good", or "Miss". Set by
	-- answer() and cleared when the verdict beat ends.
	grade: string?,
	-- Guard against double-finish from tickPlayer + PlayerRemoving racing.
	ending: boolean,
}

local sessions: { [Player]: Session } = {}

-- Dedup push: the state is pushed on every tick, but the client only redraws
-- when the digest changes. Named for every field the client reads.
local pushed: { [Player]: string } = {}

-- -------------------------------------------------------------------
-- Refusal guards. The player standing at a machine they cannot use sees a
-- one-time notice per machine; walking away and coming back re-tells.
-- -------------------------------------------------------------------

local toldRefused: { [Player]: string? } = {}

-- -------------------------------------------------------------------
-- Harness switch.
--
-- Declared here, above every reader, and that placement is the whole point:
-- a `local` declared *below* a function that names it is a plain global read
-- inside that function, not an upvalue. That is exactly how `Describe` came
-- to report "DISABLED" forever while the gym was running fine.
--
-- The gym does not build anything into the world -- the room is authored in
-- Studio and found by tag -- so there is no room-construction gate here.
-- -------------------------------------------------------------------

local enabled = true

-- -------------------------------------------------------------------
-- State construction and push.
-- -------------------------------------------------------------------

-- The client only redraws when the digest changes. A state whose only change
-- is the sweep advancing by one tick must still be sent; one whose only change
-- is nothing at all must not. The digest names every field drawn by the client.
local function stateFor(player: Player): WorkoutState?
	local health = healthOf(player)

	local session = sessions[player]
	if session ~= nil then
		local kind = KINDS[session.machine]
		local sweetHalf, perfectHalf = windowFor(session.machine, health)
		return {
			phase = if session.verdictLeft > 0 then "verdict" else "rep",
			machine = session.machine,
			machineLabel = kind.label,
			rep = session.rep,
			reps = session.reps,
			progress = session.progress,
			sweetCenter = kind.sweetCenter,
			sweetHalf = sweetHalf,
			perfectHalf = perfectHalf,
			sweepSeconds = kind.sweepSeconds,
			curve = kind.curve,
			elapsedShare = math.min(1, session.sweptSeconds / kind.sweepSeconds),
			stamina = session.stamina,
			maxStamina = GYM.MaxStamina,
			grade = if session.verdictLeft > 0 then session.grade else nil,
			healthGained = session.healthGained,
			looksGained = session.looksGained,
		}
	end

	-- No session: check whether the player is standing near a machine. This
	-- drives the offer panel on the client.
	--
	-- The offer carries the machine's real centre, width and rep count, so the panel
	-- shows what this machine is going to ask of you before you commit to it. Walking
	-- between the four and reading their bars is how a player learns the room without
	-- being told, and it is the only tutorial the gym needs.
	local machine = machineNear(player)
	if machine ~= nil then
		local kind = KINDS[machine]
		local sweetHalf, perfectHalf = windowFor(machine, health)
		return {
			phase = "offer",
			machine = machine,
			machineLabel = kind.label,
			rep = 0,
			reps = kind.reps,
			progress = 0,
			sweetCenter = kind.sweetCenter,
			sweetHalf = sweetHalf,
			perfectHalf = perfectHalf,
			sweepSeconds = kind.sweepSeconds,
			curve = kind.curve,
			elapsedShare = 0,
			stamina = GYM.MaxStamina,
			maxStamina = GYM.MaxStamina,
			grade = nil,
			healthGained = 0,
			looksGained = 0,
		}
	end

	return nil
end

local function push(player: Player)
	local state = stateFor(player)
	-- sweetHalf is in the digest because it is no longer a constant: it widens as
	-- health climbs, including mid-session, and a widening the client never redraws
	-- is a widening the player never sees -- which would defeat the entire point of
	-- making it move.
	local digest = if state == nil
		then "none"
		else `{state.phase}|{state.machine}|{state.rep}/{state.reps}|{state.stamina}`
			.. `|{math.floor(state.progress * 50)}|{tostring(state.grade)}`
			.. `|{state.healthGained}|{state.looksGained}`
			.. `|{math.floor(state.sweetHalf * 1000)}|{state.sweetCenter}`
	if pushed[player] == digest then
		return
	end
	pushed[player] = digest
	WorkoutUpdatedRemote:FireClient(player, state)
end

-- -------------------------------------------------------------------
-- Refusal check.
-- -------------------------------------------------------------------

local function refusalFor(data: LifeData, machine: string): string?
	if not data.alive then
		return "The gym is closed."
	end

	local used = data.workoutsThisYear[machine]
	if used ~= nil and used >= GYM.WorkoutsPerYear then
		local label = KINDS[machine].label
		return `You have worked the {label} {GYM.WorkoutsPerYear} time(s) this year. Come back next year.`
	end

	return nil
end

-- -------------------------------------------------------------------
-- Grade scoring. The sweep bar is 0-1; the sweet zone is centred at 0.5.
-- A hit lands wherever the needle was when the player pressed. Perfect is
-- the inner band, good is the outer band, miss is outside both.
-- -------------------------------------------------------------------

local function gradeFor(machine: string, progress: number, health: number): (string, number, number)
	local kind = KINDS[machine]
	local sweetHalf, perfectHalf = windowFor(machine, health)
	-- Distance from the machine's own centre, which is not 0.5 on three of the four.
	local dist = math.abs(progress - kind.sweetCenter)
	if dist <= perfectHalf then
		return "Perfect", kind.healthPerPerfect, kind.looksPerPerfect
	elseif dist <= sweetHalf then
		return "Good", kind.healthPerGood, kind.looksPerGood
	else
		return "Miss", 0, 0
	end
end

-- -------------------------------------------------------------------
-- Session lifecycle.
-- -------------------------------------------------------------------

local function answer(player: Player, session: Session, pushedRep: boolean)
	local grade: string
	local health, looks: number
	if pushedRep then
		grade, health, looks = gradeFor(session.machine, session.progress, healthOf(player))
	else
		grade, health, looks = "Miss", 0, 0
	end

	session.grade = grade
	session.healthGained += health
	session.looksGained += looks

	-- Stamina cost. A miss costs extra: the whole rep plus the penalty,
	-- so pushing at the wrong moment is actively worse than waiting. The rep cost is
	-- the machine's own, which is what makes the bench a seven-rep workout and the
	-- treadmill a twelve-rep one out of the same hundred-point bar.
	local cost = KINDS[session.machine].repStamina
	if grade == "Miss" then
		cost += GYM.MissStamina
	end
	session.stamina = math.max(0, session.stamina - cost)

	-- Stat gains are granted immediately rather than batched at the end,
	-- so the player's bars move on each hit and the reward feedback is
	-- instantaneous -- the same pace school uses for right answers.
	if health > 0 then
		StatService.AddStat(player, "health", health)
	end
	if looks > 0 then
		StatService.AddStat(player, "looks", looks)
	end

	session.verdictLeft = GYM.VerdictSeconds
	push(player)
end

-- Takes no LifeData: everything a finish reports lives on the session itself.
-- Keeping the profile out of the signature is what lets the harness switch and
-- the birthday hook close a session without first proving a profile is loaded.
local function finish(player: Player, session: Session, reason: string)
	if session.ending then
		return
	end
	session.ending = true
	sessions[player] = nil

	local label = KINDS[session.machine].label
	local reps = math.max(0, session.rep - 1)
	local gains = `+{session.healthGained} health, +{session.looksGained} looks`
	local line = if reason == "left"
		then `You left the {label}. {reps} reps, {gains}.`
		else `Workout over on the {label}. {reps} reps, {gains}.`

	NoticeRemote:FireClient(player, line)
	push(player)
end

local function begin(player: Player, data: LifeData, machine: string, at: Vector3)
	-- Counted at start on the school's precedent: turning up is what the
	-- cap counts, and a player who starts, walks away, restarts should not
	-- be able to re-roll the sweep.
	local used = data.workoutsThisYear[machine] or 0
	data.workoutsThisYear[machine] = used + 1

	local session: Session = {
		machine = machine,
		at = at,
		rep = 1,
		reps = KINDS[machine].reps,
		stamina = GYM.MaxStamina,
		healthGained = 0,
		looksGained = 0,
		sweptSeconds = 0,
		progress = 0,
		verdictLeft = 0,
		grade = nil,
		ending = false,
	}
	sessions[player] = session
	push(player)
end

-- -------------------------------------------------------------------
-- Remote handlers.
-- -------------------------------------------------------------------

local function onStartRequested(player: Player, kind: unknown)
	if not enabled then
		NoticeRemote:FireClient(player, "The gym is closed.")
		return
	end
	if type(kind) ~= "string" then
		return
	end

	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)

	-- Already in a session? Refuse silently rather than interrupting a
	-- workout the player is mid-way through.
	if sessions[player] ~= nil then
		return
	end

	if KINDS[kind] == nil then
		NoticeRemote:FireClient(player, "That machine is not set up yet.")
		return
	end

	-- Must still be standing next to the machine. A panel can be opened
	-- by walking to a machine, then answered after walking away.
	local nearKind, at = machineNear(player)
	if nearKind ~= kind or at == nil then
		NoticeRemote:FireClient(player, "Step up to the machine to start.")
		return
	end

	local refusal = refusalFor(data, kind)
	if refusal ~= nil then
		NoticeRemote:FireClient(player, refusal)
		return
	end

	begin(player, data, kind, at)
end

local function onRepRequested(player: Player)
	local session = sessions[player]
	if session == nil or session.verdictLeft > 0 then
		return
	end
	-- Only the live sweep can be pushed. A push that arrives during the
	-- verdict beat or after the session has ended gains nothing.
	answer(player, session, true)
end

-- -------------------------------------------------------------------
-- Tick: drives the sweep and enforces session boundaries.
-- -------------------------------------------------------------------

local function tickPlayer(player: Player, elapsed: number)
	-- The harness switch is honoured here rather than around the loop so that a
	-- session already running when the gym is switched off is closed out and
	-- reported, instead of being abandoned mid-rep with its yearly slot already
	-- spent and the client left holding a rep counter that never advances.
	if not enabled then
		local running = sessions[player]
		if running ~= nil then
			finish(player, running, "over")
		end
		return
	end

	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)
	local position = characterPosition(player)

	local session = sessions[player]

	if session == nil then
		-- No session running. If the player is near a machine with no
		-- session, stateFor returns an offer. If refused, the refusal
		-- fires once and the offer is suppressed until they leave.
		local machine = machineNear(player)
		if machine == nil then
			-- Cleared away from any machine: re-offer next time.
			if toldRefused[player] ~= nil then
				toldRefused[player] = nil
			end
			push(player)
			return
		end

		local refusal = refusalFor(data, machine)
		if refusal ~= nil then
			if toldRefused[player] ~= machine then
				toldRefused[player] = machine
				NoticeRemote:FireClient(player, refusal)
			end
			return
		end

		-- Offer state is returned by stateFor; push it.
		push(player)
		return
	end

	-- From here a session exists. Every way it can end is checked before
	-- anything is asked of the player.
	if not data.alive then
		finish(player, session, "left")
		return
	end
	if position == nil or Ground.FlatDistance(position, session.at) > GYM.RoomRadiusStuds then
		finish(player, session, "left")
		return
	end

	-- Verdict beat: the sweep is frozen, the grade is shown, and we wait
	-- for the beat to expire before advancing to the next rep.
	if session.verdictLeft > 0 then
		session.verdictLeft -= elapsed
		if session.verdictLeft > 0 then
			push(player)
			return
		end

		-- Verdict over. Advance to the next rep, or finish.
		session.verdictLeft = 0
		session.grade = nil
		session.rep += 1

		if session.rep > session.reps or session.stamina < KINDS[session.machine].repStamina then
			finish(player, session, "over")
			return
		end

		-- New rep: reset the sweep.
		session.sweptSeconds = 0
		session.progress = 0
		push(player)
		return
	end

	-- Live sweep. The clock advances evenly; the needle does not. Where it actually
	-- sits is the machine's curve applied to how much of the sweep has run, which is
	-- what makes the bench creep-then-rush and the dumbbells rush-then-crawl out of
	-- one shared tick.
	local kind = KINDS[session.machine]
	session.sweptSeconds += elapsed
	local elapsedShare = math.min(1, session.sweptSeconds / kind.sweepSeconds)
	session.progress = Sweep.At(kind.curve, elapsedShare)

	-- The sweep ran out without a push. The player did not press in time,
	-- which counts as a miss with the same consequences as a deliberate
	-- miss -- the game does not distinguish laziness from failure, because
	-- from the character's perspective both look the same.
	-- Tested on the clock rather than on the needle: every curve lands on 1 at the
	-- same moment, but only the clock does it without floating-point slack, and a
	-- sweep that expires a tick late is a free rep on the quickening machines.
	if elapsedShare >= 1 then
		session.progress = 1
		answer(player, session, false)
		return
	end

	push(player)
end

-- -------------------------------------------------------------------
-- Cleanup.
-- -------------------------------------------------------------------

local function forget(player: Player)
	local session = sessions[player]
	if session ~= nil then
		sessions[player] = nil
	end
	pushed[player] = nil
	toldRefused[player] = nil
end

-- -------------------------------------------------------------------
-- Public API: birthday hooks, studio harness, diagnostics.
-- -------------------------------------------------------------------

-- A birthday. The per-machine yearly caps reset. A session in progress is
-- ended first so it is graded on the year it started in, exactly as a
-- lesson is.
function GymService.OnAgeUp(player: Player)
	-- Closed unconditionally. The old shape dropped the session outright when
	-- no profile was loaded, which skipped the notice and the push and left the
	-- client showing a rep counter for a workout that no longer existed.
	local session = sessions[player]
	if session ~= nil then
		finish(player, session, "over")
	end

	-- Clear the yearly counters. The old year's count is already spent; a
	-- player who turned up to every machine gets a clean slate.
	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		local data = Lives.Active(profile.Data)
		table.clear(data.workoutsThisYear)
	end
	push(player)
end

-- A new life. Nobody inherits a workout session or a machine record.
function GymService.ResetForNewLife(player: Player)
	forget(player)
	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		table.clear(Lives.Active(profile.Data).workoutsThisYear)
	end
	push(player)
end

-- Studio harness: starts a workout wherever the player is standing, on the
-- nearest machine kind.
function GymService.ForceStart(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	if sessions[player] ~= nil then
		return false, "already in a workout"
	end

	local machine, at = machineNear(player)
	if machine == nil or at == nil then
		return false, "not near any machine"
	end

	local data = Lives.Active(profile.Data)
	local refusal = refusalFor(data, machine)
	if refusal ~= nil then
		return false, refusal
	end

	begin(player, data, machine, at)
	return true, nil
end

function GymService.ForceEnd(player: Player): boolean
	local session = sessions[player]
	if session == nil then
		return false
	end
	finish(player, session, "over")
	return true
end

function GymService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "gym: no profile loaded"
	end
	local data = Lives.Active(profile.Data)

	local machineCount = #allMachines
	local health = healthOf(player)

	-- The window is the thing worth printing: it is per-machine AND scales with health,
	-- so "the bar felt wrong" is only diagnosable if the numbers the grader used are
	-- visible next to the machine they came from.
	local nearKind = machineNear(player)
	local nearLine = "not near any machine"
	if nearKind ~= nil then
		local sweetHalf, perfectHalf = windowFor(nearKind, health)
		nearLine = string.format(
			"near %s (%s, %.1fs, centre %.2f, sweet ±%.3f, perfect ±%.3f at health %d)",
			KINDS[nearKind].label,
			KINDS[nearKind].curve,
			KINDS[nearKind].sweepSeconds,
			KINDS[nearKind].sweetCenter,
			sweetHalf,
			perfectHalf,
			health
		)
	end

	local running = "no workout"
	local session = sessions[player]
	if session ~= nil then
		running = `{session.machine} rep {session.rep}/{session.reps}, stamina {session.stamina}, progress {string.format("%.2f", session.progress)}`
	end

	local caps: { string } = {}
	for kind, def in KINDS do
		local used = data.workoutsThisYear[kind] or 0
		table.insert(caps, `{def.label} {used}/{GYM.WorkoutsPerYear}`)
	end
	-- `for ... in` over a hash table has no defined order, and a debug line that
	-- reshuffles between two calls is a debug line you have to read twice.
	table.sort(caps)

	return string.format(
		"gym: %d machines | %s | %s | %s | %s",
		machineCount,
		nearLine,
		running,
		table.concat(caps, ", "),
		if enabled then "enabled" else "DISABLED"
	)
end

function GymService.SetEnabled(value: boolean)
	enabled = value
end

function GymService.IsEnabled(): boolean
	return enabled
end

-- -------------------------------------------------------------------
-- Start: wire up signals and the tick loop.
-- -------------------------------------------------------------------

function GymService:Start()
	-- Index tagged equipment. Uses the same CollectionService pattern as
	-- PlaceService: listen for additions and removals so Studio edits take
	-- effect without a restart.
	local tag = GYM.EquipmentTag

	CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
		registerMachine(instance :: BasePart)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		unregisterMachine(instance :: BasePart)
	end)
	for _, instance in CollectionService:GetTagged(tag) do
		registerMachine(instance :: BasePart)
	end

	-- Push once the profile exists on join.
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			if DataService.WaitForProfile(player) ~= nil then
				push(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		forget(player)
	end)

	RequestStartWorkoutRemote.OnServerEvent:Connect(function(player: Player, kind: unknown)
		local ok, err = pcall(onStartRequested, player, kind)
		if not ok then
			warn(`[AGES] gym start failed for {player.Name}: {err}`)
		end
	end)

	RequestRepRemote.OnServerEvent:Connect(function(player: Player)
		local ok, err = pcall(onRepRequested, player)
		if not ok then
			warn(`[AGES] gym rep failed for {player.Name}: {err}`)
		end
	end)

	task.spawn(function()
		while true do
			local elapsed = task.wait(GYM.TickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player, elapsed)
				if not ok then
					warn(`[AGES] gym tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

return GymService
