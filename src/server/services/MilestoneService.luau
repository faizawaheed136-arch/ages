--!strict
-- Milestone tracking. A life crosses named thresholds -- first job, first house,
-- ten shifts, age thirty, and so on -- and the game fires a one-time celebration
-- with a money bonus. Each milestone is tracked in LifeData.milestones so it
-- fires exactly once per life, resetting on death.
--
-- The client sees a brief flash and a banner; the server owns the trigger and
-- the bonus. No remote is fired for the trigger itself: milestones are checked
-- at natural decision points (age-up, shift end, house purchase) rather than
-- on a polling loop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local DataService = require(script.Parent.DataService)
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local MoneyService = require(script.Parent.MoneyService)
local NoticeRemote = Remotes.Get("Notice")

type LifeData = Types.LifeData
type Player = Players.Player

local MilestoneService = {}

local MILESTONES = Config.Milestones
local MILESTONE_ACHIEVED = Remotes.Get("MilestoneAchieved")

-- Get the life data for a player, nil if no profile or no active life.
local function lifeDataFor(player: Player): LifeData?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return Lives.Active(profile.Data)
end

-- Check and fire a milestone if it has not been achieved this life.
-- Returns true if the milestone was newly achieved.
local function checkAndFire(player: Player, milestoneId: string, label: string, bonus: number): boolean
	local life = lifeDataFor(player)
	if life == nil then
		return false
	end
	if life.milestones[milestoneId] == true then
		return false
	end
	life.milestones[milestoneId] = true
	MoneyService.Add(player, bonus, milestoneId .. " milestone")
	NoticeRemote:FireClient(player, label .. "! +" .. tostring(bonus) .. " credits")
	MILESTONE_ACHIEVED:FireClient(player, {
		milestone = milestoneId,
		label = label,
		bonus = bonus,
	})
	return true
end

-- Check age milestones on birthday.
function MilestoneService.OnAgeUp(player: Player, ageYears: number)
	if ageYears == 30 then
		checkAndFire(player, "Age30", "Thirty", MILESTONES.Age30.bonus)
	end
	if ageYears == 50 then
		checkAndFire(player, "Age50", "Fifty", MILESTONES.Age50.bonus)
	end
	if ageYears == 80 then
		checkAndFire(player, "Age80", "Long Life", MILESTONES.Age80.bonus)
	end
end

-- Check first-job milestone.
function MilestoneService.OnFirstJob(player: Player, jobId: string)
	checkAndFire(player, "FirstJob", "First Job", MILESTONES.FirstJob.bonus)
end

-- Check house purchase milestone.
function MilestoneService.OnFirstHouse(player: Player)
	checkAndFire(player, "FirstHouse", "Homeowner", MILESTONES.FirstHouse.bonus)
end

-- Check shift count milestones. Called from WorkService after a shift completes.
function MilestoneService.OnShiftComplete(player: Player, totalShifts: number)
	local life = lifeDataFor(player)
	if life == nil then
		return
	end
	life.bills.shiftsCompleted = totalShifts
	if totalShifts >= 10 then
		checkAndFire(player, "TenShifts", "Steady Worker", MILESTONES.TenShifts.bonus)
	end
	if totalShifts >= 50 then
		checkAndFire(player, "FiftyShifts", "Dedicated", MILESTONES.FiftyShifts.bonus)
	end
end

-- Check standing milestone. Called when standing reaches the max band.
function MilestoneService.OnMaxStanding(player: Player, jobId: string)
	checkAndFire(player, "MaxStanding", "Top Performer", MILESTONES.MaxStanding.bonus)
end

function MilestoneService:Init()
	Players.PlayerAdded:Connect(function(player: Player)
		-- No state to push on join; milestones are silent achievements.
	end)
end

function MilestoneService:Start()
	-- No background tick needed.
end

return MilestoneService
