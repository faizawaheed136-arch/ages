--!strict
-- The four primary stats: clamping, decay, and pushing updates to clients.
-- This is the only place stat values are ever written.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

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
	local stats = Lives.Active(profile.Data).stats
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
	local stats = Lives.Active(profile.Data).stats
	stats[statName] = clamp(stats[statName] + delta)
	pushStats(player, stats)
end

function StatService.SetStat(player: Player, statName: StatName, value: number)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local stats = Lives.Active(profile.Data).stats
	stats[statName] = clamp(value)
	pushStats(player, stats)
end

-- Called once per in-game year by LifeService.
function StatService.ApplyYearlyDecay(player: Player, ageYears: number)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)
	local stats = data.stats
	local multiplier = if ageYears >= Config.Stats.ElderDecayStartAge then Config.Stats.ElderDecayMultiplier else 1

	for _, statName in STAT_NAMES do
		local decay = Config.Stats.DecayPerYear[statName]
		if decay ~= 0 then
			stats[statName] = clamp(stats[statName] - decay * multiplier)
		end
	end

	-- Being unwell costs more than an ordinary year does, and it is the kind of
	-- drain that can end a life rather than merely dim one. Read straight off the
	-- flag rather than through a service so this stays a leaf in the require graph:
	-- the flag is the contract, and nothing here needs to know how it got set.
	if data.flags.sick ~= nil then
		stats.health = clamp(stats.health - Config.Health.SickHealthPerYear)
		stats.happiness = clamp(stats.happiness - Config.Health.SickHappinessPerYear)
	end

	-- Debt is the one thing in the game that compounds against the player. The
	-- flag was set by BillService the moment the balance went negative, and it
	-- stays until the next birthday clears it — so a life that skips years
	-- pays the drain for each skipped year the same way it pays each skipped
	-- bill. Read the flag directly; StatService owns the drain and nothing
	-- else writes it.
	if data.flags["in_debt"] ~= nil then
		local debt = data.bills.debt
		if debt > 0 then
			-- Happiness drops proportionally to how deep in the red the life is,
			-- capped so a maxed-out debt does not tank the bar in a single year.
			-- Health drops a smaller flat amount: the body does not care about
			-- status, only about the stress that keeps it up at night.
			local stress = math.min(debt / Config.Bills.MaxDebt, 1)
			stats.happiness = clamp(stats.happiness - math.floor(4 * stress))
			stats.health = clamp(stats.health - 2)
		end
	end

	pushStats(player, stats)
end

function StatService.PushStats(player: Player)
	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		pushStats(player, Lives.Active(profile.Data).stats)
	end
end

-- `ResetToStarting` used to live here, and it is gone rather than kept. It wound a life's
-- four bars back to `Config.Stats.Starting` for the rebirth that ran in place; a new life is
-- now a fresh `Lives.New()` that starts there already, with whatever the create card spent on
-- top -- see `LifeSetup.StartingStats`, which applies this same clamp.

function StatService:Init() end

function StatService:Start()
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			local profile = DataService.WaitForProfile(player)
			if profile ~= nil then
				pushStats(player, Lives.Active(profile.Data).stats)
			end
		end)
	end)
end

return StatService
