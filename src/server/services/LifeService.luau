--!strict
-- Aging is player-driven. There is no wall clock advancing the world: a year
-- ends when the player presses Age Up, or when they have banked enough active
-- session time that the safety net advances them anyway. Both routes run the
-- same code path so decay, stage transitions and the death roll can never
-- drift apart between them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local DataService = require(script.Parent.DataService)
local StatService = require(script.Parent.StatService)

type LifeStageId = Types.LifeStageId
type AgeUpCause = Types.AgeUpCause
type ManualAgeUpState = Types.ManualAgeUpState
type ProfileData = Types.ProfileData

local AgeUpdatedRemote = Remotes.Get("AgeUpdated")
local AgeUpProgressRemote = Remotes.Get("AgeUpProgress")
local RequestAgeUpRemote = Remotes.Get("RequestAgeUp")
local PlayerDiedRemote = Remotes.Get("PlayerDied")
local PlayerRespawnedRemote = Remotes.Get("PlayerRespawned")
local LifeStageChangedRemote = Remotes.Get("LifeStageChanged")

local LifeService = {}

local function stageForAge(ageYears: number): LifeStageId
	for _, stage in Config.LifeStages do
		if ageYears >= stage.minAge and ageYears <= stage.maxAge then
			return stage.id :: LifeStageId
		end
	end
	return "Elder"
end

-- ChancePerYear = min(MaxChancePerYear, BaseChancePerYear * (age - RampStartAge) ^ Exponent)
local function rollNaturalDeath(ageYears: number): boolean
	local deathConfig = Config.Death
	if ageYears < deathConfig.RampStartAge then
		return false
	end
	local yearsPast = ageYears - deathConfig.RampStartAge
	local chance = math.min(deathConfig.MaxChancePerYear, deathConfig.BaseChancePerYear * (yearsPast ^ deathConfig.Exponent))
	return math.random() < chance
end

local function ageYearsOf(data: ProfileData): number
	return data.ageMonths // Config.Time.MonthsPerYear
end

-- Gated on age rather than life stage: the player takes the wheel partway
-- through Childhood, at the point they could plausibly be choosing things for
-- themselves, not at the stage boundary years later.
local function isSelfDirected(data: ProfileData): boolean
	return ageYearsOf(data) >= Config.ManualAgeUpMinAge
end

-- The earliest years run on a shorter timer because there is nothing for the
-- player to decide while they pass. Thresholds are authored in game hours and
-- converted here, so the day length is the only dial that moves them.
local function autoThresholdSeconds(data: ProfileData): number
	local gameHours = if isSelfDirected(data) then Config.AutoAgeUpGameHours else Config.ChildAutoAgeUpGameHours
	return gameHours * Config.Time.RealSecondsPerGameHour
end

-- Single source of truth for the manual gate. The HUD renders whatever this
-- returns rather than re-deriving the rule, so the button can never offer an
-- action the server would refuse.
local function manualState(data: ProfileData): ManualAgeUpState
	if not data.alive or not isSelfDirected(data) then
		return "Hidden"
	end
	if data.secondsSinceAgeUp < Config.ManualAgeUpCooldownSeconds then
		return "Cooldown"
	end
	return "Ready"
end

local function pushProgress(player: Player, data: ProfileData)
	AgeUpProgressRemote:FireClient(player, data.secondsSinceAgeUp, autoThresholdSeconds(data), manualState(data))
end

function LifeService.GetAgeYears(player: Player): number?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return ageYearsOf(profile.Data)
end

-- Public so the Studio debug harness can force a death without waiting on a
-- mortality roll. Safe to call on an already-dead player: the alive check
-- makes it a no-op, so a retried call cannot queue a second respawn.
function LifeService.Die(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil or not profile.Data.alive then
		return
	end

	profile.Data.alive = false
	profile.Data.stage = "Death"
	pushProgress(player, profile.Data)
	PlayerDiedRemote:FireClient(player, ageYearsOf(profile.Data))

	task.delay(Config.Death.RespawnDelaySeconds, function()
		-- Bail out if the player's profile changed identity (e.g. rejoined).
		if DataService.GetProfile(player) ~= profile then
			return
		end

		profile.Data.ageMonths = 0
		profile.Data.stage = "Childhood"
		profile.Data.alive = true
		profile.Data.livesLived += 1
		profile.Data.secondsSinceAgeUp = 0

		StatService.ResetToStarting(player)
		PlayerRespawnedRemote:FireClient(player)
		LifeStageChangedRemote:FireClient(player, "Childhood")
		AgeUpdatedRemote:FireClient(player, 0, "Sync" :: AgeUpCause)
		pushProgress(player, profile.Data)
	end)
end

-- Health reaching zero is lethal the moment it happens rather than at the next
-- birthday, otherwise a fatal injury could sit harmless for half an hour.
local function killIfOutOfHealth(player: Player): boolean
	local stats = StatService.GetStats(player)
	if stats ~= nil and stats.health <= 0 then
		LifeService.Die(player)
		return true
	end
	return false
end

-- The one and only way age advances. Public so the debug harness drives the
-- real path instead of a shortcut that could diverge from it.
function LifeService.AgeUp(player: Player, cause: AgeUpCause)
	local profile = DataService.GetProfile(player)
	if profile == nil or not profile.Data.alive then
		return
	end

	local data = profile.Data

	-- Banked time is spent before anything else can yield: a duplicate request
	-- arriving behind this one fails its cooldown check, so a retry (or a
	-- client firing the remote twice) cannot buy two years for one year's wait.
	data.secondsSinceAgeUp = 0
	data.ageMonths += Config.Time.MonthsPerYear

	local ageYears = ageYearsOf(data)

	StatService.ApplyYearlyDecay(player, ageYears)

	local newStage: LifeStageId = stageForAge(ageYears)
	if newStage ~= data.stage then
		data.stage = newStage
		LifeStageChangedRemote:FireClient(player, newStage)
	end

	AgeUpdatedRemote:FireClient(player, ageYears, cause)
	pushProgress(player, data)

	if killIfOutOfHealth(player) then
		return
	end
	if rollNaturalDeath(ageYears) then
		LifeService.Die(player)
	end
end

-- Only time spent in the server counts toward the safety net, and the counter
-- lives in the profile, so leaving mid-year banks progress rather than losing
-- or farming it.
local function bankPlaytime(elapsedSeconds: number)
	for _, player in Players:GetPlayers() do
		local profile = DataService.GetProfile(player)
		if profile == nil or not profile.Data.alive then
			continue
		end

		local data = profile.Data
		data.secondsSinceAgeUp += elapsedSeconds

		if killIfOutOfHealth(player) then
			continue
		end

		if data.secondsSinceAgeUp >= autoThresholdSeconds(data) then
			LifeService.AgeUp(player, "Auto")
		else
			pushProgress(player, data)
		end
	end
end

local function onAgeUpRequested(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		-- Fired before the profile finished loading, or after it was released.
		-- There is nothing to validate against, so refuse rather than guess.
		return
	end

	local data = profile.Data
	if manualState(data) ~= "Ready" then
		-- Refused: dead, too young for the button, or inside the cooldown.
		-- Re-push the
		-- authoritative state so a desynced or hostile client's button
		-- immediately snaps back to what the server actually allows.
		pushProgress(player, data)
		return
	end

	LifeService.AgeUp(player, "Manual")
end

local function pushInitialState(player: Player)
	local profile = DataService.WaitForProfile(player)
	if profile == nil then
		return
	end
	local data = profile.Data
	AgeUpdatedRemote:FireClient(player, ageYearsOf(data), "Sync" :: AgeUpCause)
	LifeStageChangedRemote:FireClient(player, data.stage)
	pushProgress(player, data)
end

function LifeService:Init()
	RequestAgeUpRemote.OnServerEvent:Connect(onAgeUpRequested)
end

function LifeService:Start()
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(pushInitialState, player)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(pushInitialState, player)
	end

	task.spawn(function()
		while true do
			-- task.wait returns the time that actually elapsed, so a hitching
			-- server banks real seconds instead of drifting behind.
			local elapsed = task.wait(Config.AgeUpProgressTickSeconds)
			bankPlaytime(elapsed)
		end
	end)
end

return LifeService
