--!strict
-- Sports drills: the gym's verb, aimed at the sports campus.
--
-- The loop is byte-identical to GymService's, on purpose -- see the header comment on
-- Config.SportsDrill for why reusing "push the sweep at the right moment" here is the
-- right call rather than a shortcut: the rule that matters is one distinct verb per
-- *subject*, not one per *building*, and effort becoming something you can read is the
-- same idea whether the room is a weight room or a boxing gym.
--
--   You walk to a station -- a heavy bag, a free-throw rim, the volleyball net, a
--   penalty crossbar -- and the server notices you are there. A panel offers a drill;
--   you press Start. A sweep bar travels; you press PUSH in the sweet zone. Quality is
--   graded by how close to centre the hit lands. A fixed rep count or empty stamina
--   ends the session.
--
-- The campus is a set of tagged parts built by hand in tools/gen_city.py -- three bags,
-- two hoops, one net, two crossbars -- found by tag rather than built here, exactly as
-- GymService finds its four machines.
--
-- Stats gained: health and happiness. Health because a drill is exercise same as a
-- workout is; happiness rather than looks, because playing a sport you enjoy is the
-- honest thing sport moves that a bench press does not. Skill gained: athletics, into
-- the same discipline the gym already pays -- one bar for "effort read off a timing
-- sweep," fed from two rooms.

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
local SkillService = require(script.Parent.SkillService)
local Ground = require(script.Parent.Parent.world.Ground)

type LifeData = Types.LifeData
type SportsDrillState = Types.SportsDrillState

local SportsDrillService = {}

local SportsDrillUpdatedRemote = Remotes.Get("SportsDrillUpdated")
local RequestStartDrillRemote = Remotes.Get("RequestStartDrill")
local RequestDrillRepRemote = Remotes.Get("RequestDrillRep")
local NoticeRemote = Remotes.Get("Notice")

local DRILL = Config.SportsDrill
local SKILL_AWARDS = Config.Skills.Awards
local KINDS = DRILL.Kinds

-- The sweet zone for a station, widened by how fit the character is. Same shape as
-- GymService.windowFor -- see that comment for why health is read live rather than
-- cached on the session.
local function windowFor(station: string, health: number): (number, number)
	local kind = KINDS[station]
	local fitness = math.clamp(health / Config.Stats.Max, 0, 1)
	local widen = 1 + DRILL.HealthWindowBonus * fitness
	return (kind.sweetFraction * widen) / 2, (kind.perfectFraction * widen) / 2
end

local function healthOf(player: Player): number
	local stats = StatService.GetStats(player)
	return if stats ~= nil then stats.health else 0
end

-- -------------------------------------------------------------------
-- Station index: tagged parts grouped by their kind attribute.
-- -------------------------------------------------------------------

type StationEntry = {
	part: BasePart,
	kind: string,
}

local allStations: { StationEntry } = {}
local stationsByKind: { [string]: { StationEntry } } = {}

local function registerStation(part: BasePart)
	if not part:IsA("BasePart") then
		return
	end
	local raw = part:GetAttribute(DRILL.DrillKindAttribute)
	if raw == nil or type(raw) ~= "string" or raw == "" then
		warn(`[AGES] sports drill station "{part:GetFullName()}" has no "{DRILL.DrillKindAttribute}" attribute`)
		return
	end
	if KINDS[raw] == nil then
		warn(`[AGES] sports drill station "{part:GetFullName()}" has unknown kind "{raw}"`)
		return
	end
	local entry = { part = part, kind = raw }
	table.insert(allStations, entry)
	local list = stationsByKind[raw]
	if list == nil then
		list = {}
		stationsByKind[raw] = list
	end
	table.insert(list, entry)
end

local function unregisterStation(part: BasePart)
	for i = #allStations, 1, -1 do
		if allStations[i].part == part then
			table.remove(allStations, i)
			break
		end
	end
	for _, list in stationsByKind do
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

-- Which station kind, if any, the player is standing next to. Closest wins, same
-- rule as GymService.machineNear.
local function stationNear(player: Player): (string?, Vector3?)
	local position = characterPosition(player)
	if position == nil then
		return nil, nil
	end
	local bestKind: string? = nil
	local bestAt: Vector3? = nil
	local bestDist = math.huge
	for _, entry in allStations do
		local dist = Ground.FlatDistance(position, entry.part.Position)
		if dist <= DRILL.ReachStuds and dist < bestDist then
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
	station: string,
	at: Vector3,
	rep: number,
	reps: number,
	stamina: number,
	healthGained: number,
	happinessGained: number,
	sweptSeconds: number,
	progress: number,
	verdictLeft: number,
	grade: string?,
	ending: boolean,
}

local sessions: { [Player]: Session } = {}
local pushed: { [Player]: string } = {}
local toldRefused: { [Player]: string? } = {}

-- See GymService's identical comment: declared here, above every reader, so a
-- harness toggle can never silently become a global read.
local enabled = true

-- -------------------------------------------------------------------
-- State construction and push.
-- -------------------------------------------------------------------

local function stateFor(player: Player): SportsDrillState?
	local health = healthOf(player)

	local session = sessions[player]
	if session ~= nil then
		local kind = KINDS[session.station]
		local sweetHalf, perfectHalf = windowFor(session.station, health)
		return {
			phase = if session.verdictLeft > 0 then "verdict" else "rep",
			station = session.station,
			stationLabel = kind.label,
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
			maxStamina = DRILL.MaxStamina,
			grade = if session.verdictLeft > 0 then session.grade else nil,
			healthGained = session.healthGained,
			happinessGained = session.happinessGained,
		}
	end

	local station = stationNear(player)
	if station ~= nil then
		local kind = KINDS[station]
		local sweetHalf, perfectHalf = windowFor(station, health)
		return {
			phase = "offer",
			station = station,
			stationLabel = kind.label,
			rep = 0,
			reps = kind.reps,
			progress = 0,
			sweetCenter = kind.sweetCenter,
			sweetHalf = sweetHalf,
			perfectHalf = perfectHalf,
			sweepSeconds = kind.sweepSeconds,
			curve = kind.curve,
			elapsedShare = 0,
			stamina = DRILL.MaxStamina,
			maxStamina = DRILL.MaxStamina,
			grade = nil,
			healthGained = 0,
			happinessGained = 0,
		}
	end

	return nil
end

local function push(player: Player)
	local state = stateFor(player)
	local digest = if state == nil
		then "none"
		else `{state.phase}|{state.station}|{state.rep}/{state.reps}|{state.stamina}`
			.. `|{math.floor(state.progress * 50)}|{tostring(state.grade)}`
			.. `|{state.healthGained}|{state.happinessGained}`
			.. `|{math.floor(state.sweetHalf * 1000)}|{state.sweetCenter}`
	if pushed[player] == digest then
		return
	end
	pushed[player] = digest
	SportsDrillUpdatedRemote:FireClient(player, state)
end

-- -------------------------------------------------------------------
-- Refusal check.
-- -------------------------------------------------------------------

local function refusalFor(data: LifeData, station: string): string?
	if not data.alive then
		return "The sports campus is closed."
	end

	local used = data.drillsThisYear[station]
	if used ~= nil and used >= DRILL.DrillsPerYear then
		local label = KINDS[station].label
		return `You have run the {label} {DRILL.DrillsPerYear} time(s) this year. Come back next year.`
	end

	return nil
end

-- -------------------------------------------------------------------
-- Grade scoring.
-- -------------------------------------------------------------------

local function gradeFor(station: string, progress: number, health: number): (string, number, number)
	local kind = KINDS[station]
	local sweetHalf, perfectHalf = windowFor(station, health)
	local dist = math.abs(progress - kind.sweetCenter)
	if dist <= perfectHalf then
		return "Perfect", kind.healthPerPerfect, kind.happinessPerPerfect
	elseif dist <= sweetHalf then
		return "Good", kind.healthPerGood, kind.happinessPerGood
	else
		return "Miss", 0, 0
	end
end

-- -------------------------------------------------------------------
-- Session lifecycle.
-- -------------------------------------------------------------------

local function answer(player: Player, session: Session, pushedRep: boolean)
	local grade: string
	local health, happiness: number
	if pushedRep then
		grade, health, happiness = gradeFor(session.station, session.progress, healthOf(player))
	else
		grade, health, happiness = "Miss", 0, 0
	end

	session.grade = grade
	session.healthGained += health
	session.happinessGained += happiness

	local cost = KINDS[session.station].repStamina
	if grade == "Miss" then
		cost += DRILL.MissStamina
	end
	session.stamina = math.max(0, session.stamina - cost)

	if health > 0 then
		StatService.AddStat(player, "health", health)
	end
	if happiness > 0 then
		StatService.AddStat(player, "happiness", happiness)
	end

	-- Athletics, on the grade and nothing else -- the same rule GymService.answer
	-- applies, into the same discipline.
	if grade == "Perfect" then
		SkillService.Award(player, "athletics", SKILL_AWARDS.DrillPerfect, "perfect drill rep")
	elseif grade == "Good" then
		SkillService.Award(player, "athletics", SKILL_AWARDS.DrillGood, "good drill rep")
	end

	session.verdictLeft = DRILL.VerdictSeconds
	push(player)
end

local function finish(player: Player, session: Session, reason: string)
	if session.ending then
		return
	end
	session.ending = true
	sessions[player] = nil

	local label = KINDS[session.station].label
	local reps = math.max(0, session.rep - 1)
	local gains = `+{session.healthGained} health, +{session.happinessGained} happiness`
	local line = if reason == "left"
		then `You left the {label}. {reps} reps, {gains}.`
		else `Drill over at the {label}. {reps} reps, {gains}.`

	NoticeRemote:FireClient(player, line)
	push(player)
end

local function begin(player: Player, data: LifeData, station: string, at: Vector3)
	local used = data.drillsThisYear[station] or 0
	data.drillsThisYear[station] = used + 1

	local session: Session = {
		station = station,
		at = at,
		rep = 1,
		reps = KINDS[station].reps,
		stamina = DRILL.MaxStamina,
		healthGained = 0,
		happinessGained = 0,
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
		NoticeRemote:FireClient(player, "The sports campus is closed.")
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

	if sessions[player] ~= nil then
		return
	end

	if KINDS[kind] == nil then
		NoticeRemote:FireClient(player, "That station is not set up yet.")
		return
	end

	local nearKind, at = stationNear(player)
	if nearKind ~= kind or at == nil then
		NoticeRemote:FireClient(player, "Step up to the station to start.")
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
	answer(player, session, true)
end

-- -------------------------------------------------------------------
-- Tick: drives the sweep and enforces session boundaries.
-- -------------------------------------------------------------------

local function tickPlayer(player: Player, elapsed: number)
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
		local station = stationNear(player)
		if station == nil then
			if toldRefused[player] ~= nil then
				toldRefused[player] = nil
			end
			push(player)
			return
		end

		local refusal = refusalFor(data, station)
		if refusal ~= nil then
			if toldRefused[player] ~= station then
				toldRefused[player] = station
				NoticeRemote:FireClient(player, refusal)
			end
			return
		end

		push(player)
		return
	end

	if not data.alive then
		finish(player, session, "left")
		return
	end
	if position == nil or Ground.FlatDistance(position, session.at) > DRILL.RoomRadiusStuds then
		finish(player, session, "left")
		return
	end

	if session.verdictLeft > 0 then
		session.verdictLeft -= elapsed
		if session.verdictLeft > 0 then
			push(player)
			return
		end

		session.verdictLeft = 0
		session.grade = nil
		session.rep += 1

		if session.rep > session.reps or session.stamina < KINDS[session.station].repStamina then
			finish(player, session, "over")
			return
		end

		session.sweptSeconds = 0
		session.progress = 0
		push(player)
		return
	end

	local kind = KINDS[session.station]
	session.sweptSeconds += elapsed
	local elapsedShare = math.min(1, session.sweptSeconds / kind.sweepSeconds)
	session.progress = Sweep.At(kind.curve, elapsedShare)

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

function SportsDrillService.OnAgeUp(player: Player)
	local session = sessions[player]
	if session ~= nil then
		finish(player, session, "over")
	end

	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		local data = Lives.Active(profile.Data)
		table.clear(data.drillsThisYear)
	end
	push(player)
end

function SportsDrillService.ResetForNewLife(player: Player)
	forget(player)
	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		table.clear(Lives.Active(profile.Data).drillsThisYear)
	end
	push(player)
end

function SportsDrillService.ForceStart(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "no profile loaded"
	end
	if sessions[player] ~= nil then
		return false, "already in a drill"
	end

	local station, at = stationNear(player)
	if station == nil or at == nil then
		return false, "not near any station"
	end

	local data = Lives.Active(profile.Data)
	local refusal = refusalFor(data, station)
	if refusal ~= nil then
		return false, refusal
	end

	begin(player, data, station, at)
	return true, nil
end

function SportsDrillService.ForceEnd(player: Player): boolean
	local session = sessions[player]
	if session == nil then
		return false
	end
	finish(player, session, "over")
	return true
end

function SportsDrillService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "sports drill: no profile loaded"
	end
	local data = Lives.Active(profile.Data)

	local stationCount = #allStations
	local health = healthOf(player)

	local nearKind = stationNear(player)
	local nearLine = "not near any station"
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

	local running = "no drill"
	local session = sessions[player]
	if session ~= nil then
		running = `{session.station} rep {session.rep}/{session.reps}, stamina {session.stamina}, progress {string.format("%.2f", session.progress)}`
	end

	local caps: { string } = {}
	for kind, def in KINDS do
		local used = data.drillsThisYear[kind] or 0
		table.insert(caps, `{def.label} {used}/{DRILL.DrillsPerYear}`)
	end
	table.sort(caps)

	return string.format(
		"sports drill: %d stations | %s | %s | %s | %s",
		stationCount,
		nearLine,
		running,
		table.concat(caps, ", "),
		if enabled then "enabled" else "DISABLED"
	)
end

function SportsDrillService.SetEnabled(value: boolean)
	enabled = value
end

function SportsDrillService.IsEnabled(): boolean
	return enabled
end

-- -------------------------------------------------------------------
-- Start: wire up signals and the tick loop.
-- -------------------------------------------------------------------

function SportsDrillService:Start()
	local tag = DRILL.DrillTag

	CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
		registerStation(instance :: BasePart)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		unregisterStation(instance :: BasePart)
	end)
	for _, instance in CollectionService:GetTagged(tag) do
		registerStation(instance :: BasePart)
	end

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

	RequestStartDrillRemote.OnServerEvent:Connect(function(player: Player, kind: unknown)
		local ok, err = pcall(onStartRequested, player, kind)
		if not ok then
			warn(`[AGES] sports drill start failed for {player.Name}: {err}`)
		end
	end)

	RequestDrillRepRemote.OnServerEvent:Connect(function(player: Player)
		local ok, err = pcall(onRepRequested, player)
		if not ok then
			warn(`[AGES] sports drill rep failed for {player.Name}: {err}`)
		end
	end)

	task.spawn(function()
		while true do
			local elapsed = task.wait(DRILL.TickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player, elapsed)
				if not ok then
					warn(`[AGES] sports drill tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

return SportsDrillService
