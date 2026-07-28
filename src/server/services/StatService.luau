--!strict
-- The four primary stats: clamping, decay, and pushing updates to clients.
-- This is the only place stat values are ever written.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local DataService = require(script.Parent.DataService)

type Stats = Types.Stats
type StatName = Types.StatName

local STAT_NAMES: { StatName } = { "health", "happiness", "smarts", "looks" }

local StatService = {}

local function clamp(value: number): number
	return math.clamp(value, Config.Stats.Min, Config.Stats.Max)
end

local function pushStats(player: Player, stats: Stats)
	Remotes.Get("StatsUpdated"):FireClient(player, stats)
end

function StatService.GetStats(player: Player): Stats?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	local stats = profile.Data.stats
	return {
		health = stats.health,
		happiness = stats.happiness,
		smarts = stats.smarts,
		looks = stats.looks,
	}
end

-- Every interaction in the game should call this at least once — if a
-- choice doesn't move a stat, per the spec it should be cut.
function StatService.AddStat(player: Player, statName: StatName, delta: number)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local stats = profile.Data.stats
	stats[statName] = clamp(stats[statName] + delta)
	pushStats(player, stats)
end

function StatService.SetStat(player: Player, statName: StatName, value: number)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local stats = profile.Data.stats
	stats[statName] = clamp(value)
	pushStats(player, stats)
end

-- Called once per in-game year by LifeService.
function StatService.ApplyYearlyDecay(player: Player, ageYears: number)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local stats = profile.Data.stats
	local multiplier = if ageYears >= Config.Stats.ElderDecayStartAge then Config.Stats.ElderDecayMultiplier else 1

	for _, statName in STAT_NAMES do
		local decay = Config.Stats.DecayPerYear[statName]
		if decay ~= 0 then
			stats[statName] = clamp(stats[statName] - decay * multiplier)
		end
	end

	pushStats(player, stats)
end

function StatService.PushStats(player: Player)
	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		pushStats(player, profile.Data.stats)
	end
end

function StatService.ResetToStarting(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local stats = profile.Data.stats
	stats.health = Config.Stats.Starting.health
	stats.happiness = Config.Stats.Starting.happiness
	stats.smarts = Config.Stats.Starting.smarts
	stats.looks = Config.Stats.Starting.looks
	pushStats(player, stats)
end

function StatService:Init() end

function StatService:Start()
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			local profile = DataService.WaitForProfile(player)
			if profile ~= nil then
				pushStats(player, profile.Data.stats)
			end
		end)
	end)
end

return StatService
