--!strict
-- House ownership. A life can buy a suburb home, sell it, and link a work-from-home
-- job to it. The property data sits on LifeData, resetting on death so a new life
-- starts with nothing -- just like money and bonds.
--
-- No special integration with WorkService is needed: stationAtHand() already
-- resolves any placeId through PlaceService.Find(), so a job whose placeId points
-- to a suburb house works the same way any other job does. HouseService only
-- manages ownership and the home-job link.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local DataService = require(script.Parent.DataService)
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local MoneyService = require(script.Parent.MoneyService)
local MilestoneService = require(script.Parent.MilestoneService)
local GossipService = require(script.Parent.GossipService)

type LifeData = Types.LifeData
type Player = Players.Player

local HouseService = {}

local HOUSE = Config.House
local HOUSE_UPDATED = Remotes.Get("HouseUpdated")
local REQUEST_BUY = Remotes.Get("RequestBuyHouse")
local REQUEST_SELL = Remotes.Get("RequestSellHouse")
local REQUEST_SET_JOB = Remotes.Get("RequestSetHomeJob")

-- Check whether a house id is a known suburb place in the walkable list.
local function isValidHouseId(houseId: string): boolean
	return table.find(Config.Places.Walkable, houseId) ~= nil
		and string.find(houseId, "^suburb_") == 1
end

-- Get the life data for a player, nil if no profile or no active life.
local function lifeDataFor(player: Player): LifeData?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return Lives.Active(profile.Data)
end

-- Build the list of unowned suburb houses a player can buy.
local function buildAvailable(): { [string]: number }
	local available: { [string]: number } = {}
	for _, houseId in Config.Places.Walkable do
		if string.find(houseId, "^suburb_") == 1 then
			available[houseId] = HOUSE.BuyPrice
		end
	end
	return available
end

-- Push the full house state to a player's client.
local function pushHouseStatus(player: Player, life: LifeData)
	local houses = life.houses :: { owned: { [string]: boolean }, homeJob: { [string]: string } }
	HOUSE_UPDATED:FireClient(player, {
		owned = houses.owned,
		homeJob = houses.homeJob,
		available = buildAvailable(),
	})
end

-- Buy a suburb house.
-- Returns ("ok", houseId) on success, ("error", reason) on failure.
function HouseService.BuyHouse(player: Player, houseId: string): (boolean, string?)
	if typeof(houseId) ~= "string" then
		return false, "Invalid house id"
	end
	if not isValidHouseId(houseId) then
		return false, "Unknown house"
	end

	local life = lifeDataFor(player)
	if life == nil then
		return false, "No active life"
	end

	local houses = life.houses :: { owned: { [string]: boolean }, homeJob: { [string]: string } }

	if houses.owned[houseId] == true then
		return false, "Already own this house"
	end

	local ownedCount = 0
	for _ in houses.owned do
		ownedCount = ownedCount + 1
	end
	if ownedCount >= HOUSE.MaxPerPlayer then
		return false, "Already own the maximum number of houses"
	end

	local spent = MoneyService.Spend(player, HOUSE.BuyPrice, "bought " .. houseId)
	if not spent then
		return false, "Not enough money"
	end

	houses.owned[houseId] = true
	-- Clear any stale home job for this house (shouldn't happen, but be safe).
	houses.homeJob[houseId] = nil
	pushHouseStatus(player, life)

	-- Track milestones and gossip around home ownership.
	if ownedCount == 0 then
		MilestoneService.OnFirstHouse(player)
	end
	GossipService.OnHousePurchase(player, houseId)

	return true, houseId
end

-- Sell a suburb house.
-- Returns ("ok", amount) on success, ("error", reason) on failure.
function HouseService.SellHouse(player: Player, houseId: string): (boolean, string?)
	if typeof(houseId) ~= "string" then
		return false, "Invalid house id"
	end
	if not isValidHouseId(houseId) then
		return false, "Unknown house"
	end

	local life = lifeDataFor(player)
	if life == nil then
		return false, "No active life"
	end

	local houses = life.houses :: { owned: { [string]: boolean }, homeJob: { [string]: string } }

	if houses.owned[houseId] ~= true then
		return false, "Do not own this house"
	end

	-- Clear any linked home job first.
	houses.homeJob[houseId] = nil

	local refund = math.floor(HOUSE.BuyPrice * HOUSE.ResaleFraction)
	MoneyService.Add(player, refund, "sold " .. houseId)

	houses.owned[houseId] = nil
	pushHouseStatus(player, life)

	GossipService.OnHouseSale(player, houseId)

	return true, tostring(refund)
end

-- Link a home job to an owned house.
-- Returns ("ok", jobId) on success, ("error", reason) on failure.
function HouseService.SetHomeJob(player: Player, houseId: string, jobId: string): (boolean, string?)
	if typeof(houseId) ~= "string" or typeof(jobId) ~= "string" then
		return false, "Invalid arguments"
	end

	local life = lifeDataFor(player)
	if life == nil then
		return false, "No active life"
	end

	local houses = life.houses :: { owned: { [string]: boolean }, homeJob: { [string]: string } }

	if houses.owned[houseId] ~= true then
		return false, "Do not own this house"
	end

	-- Look up the job and verify it exists and its placeId matches.
	local Jobs = require(script.Parent.Parent.content.Jobs)
	local job = Jobs.ById[jobId]
	if job == nil then
		return false, "Unknown job"
	end
	if job.placeId ~= houseId then
		return false, "Job does not match this house"
	end

	if not Config.Work.HomeJobAllowed then
		return false, "Work-from-home jobs are disabled"
	end

	houses.homeJob[houseId] = jobId
	pushHouseStatus(player, life)

	return true, jobId
end

-- Get the home job id for an owned house, or nil if none is linked.
function HouseService.GetHomeJob(player: Player, houseId: string): string?
	if typeof(houseId) ~= "string" then
		return nil
	end
	local life = lifeDataFor(player)
	if life == nil then
		return nil
	end
	local houses = life.houses
	if houses == nil then
		return nil
	end
	if houses.owned[houseId] ~= true then
		return nil
	end
	return houses.homeJob[houseId]
end

-- Check whether a job can be done from home (placeId is an owned suburb house
-- with a linked home job). Returns the job with its place verified, or nil.
function HouseService.ResolveJob(player: Player, job: Types.Job): Types.Job?
	if not Config.Work.HomeJobAllowed then
		return nil
	end
	if not string.find(job.placeId, "^suburb_") == 1 then
		return nil
	end

	local life = lifeDataFor(player)
	if life == nil then
		return nil
	end

	local houses = life.houses :: { owned: { [string]: boolean }, homeJob: { [string]: string } }
	if houses.owned[job.placeId] ~= true then
		return nil
	end

	-- The job is valid and the player owns the house. Return it as-is.
	-- WorkService.stationAtHand() will handle the rest.
	return job
end

function HouseService:Init()
	REQUEST_BUY.OnServerEvent:Connect(function(player: Player, houseId: any)
		if typeof(houseId) ~= "string" then
			return
		end
		local ok, err = HouseService.BuyHouse(player, houseId)
		if not ok then
			warn(`[AGES] BuyHouse failed for {player.Name}: {err}`)
		end
	end)

	REQUEST_SELL.OnServerEvent:Connect(function(player: Player, houseId: any)
		if typeof(houseId) ~= "string" then
			return
		end
		local ok, err = HouseService.SellHouse(player, houseId)
		if not ok then
			warn(`[AGES] SellHouse failed for {player.Name}: {err}`)
		end
	end)

	REQUEST_SET_JOB.OnServerEvent:Connect(function(player: Player, houseId: any, jobId: any)
		if typeof(houseId) ~= "string" or typeof(jobId) ~= "string" then
			return
		end
		local ok, err = HouseService.SetHomeJob(player, houseId, jobId)
		if not ok then
			warn(`[AGES] SetHomeJob failed for {player.Name}: {err}`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		-- No persistent state to clean up beyond the life data, which is
		-- managed by DataService.
	end)
end

function HouseService:Start()
	-- No background tick needed. House state only changes on player action.
end

return HouseService
