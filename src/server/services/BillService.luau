--!strict
-- Monthly bills. A life pays every game month it has been alive, and the cost
-- scales with what it owns. Houses add a fixed amount; accumulated wealth
-- pushes the base up. Unpaid bills become debt that grows interest, and debt
-- is the one thing in the game that compounds against the player rather than
-- for them -- the inverse of a bank account, and deliberately so.
--
-- Nothing here is a remote. The client is told what it owes and when it is due;
-- it does not ask to be billed. Billing is driven by the age-up path so a life
-- that skips years pays for each one it skips.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local DataService = require(script.Parent.DataService)
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local MoneyService = require(script.Parent.MoneyService)

type LifeData = Types.LifeData
type Player = Players.Player

local BillService = {}

local BILLS = Config.Bills
local BILL_DUE = Remotes.Get("BillDue")

-- Get the life data for a player, nil if no profile or no active life.
local function lifeDataFor(player: Player): LifeData?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return Lives.Active(profile.Data)
end

-- Count how many suburb houses a life owns.
local function houseCount(life: LifeData): number
	local count = 0
	for _ in life.houses.owned do
		count = count + 1
	end
	return count
end

-- Compute this life's monthly bill total.
local function computeBill(life: LifeData): number
	local base = BILLS.BaseMonthly
	local houses = houseCount(life) * BILLS.HouseMonthly

	if life.money >= BILLS.LuxuryThreshold then
		base = math.floor(base * BILLS.LuxuryMultiplier)
	end

	return base + houses
end

-- Charge a bill for a life. Called from LifeService on age-up.
-- Returns the amount deducted (may be less than the bill if money was insufficient).
function BillService.Charge(player: Player): number
	local life = lifeDataFor(player)
	if life == nil then
		return 0
	end

	local bill = computeBill(life)
	local ageYears = life.ageMonths // Config.Time.MonthsPerYear
	local billMonth = (ageYears * Config.Time.MonthsPerYear) :: number

	-- Skip if this billing cycle has already been processed.
	if life.bills.lastBillMonth >= billMonth then
		return 0
	end

	life.bills.lastBillMonth = billMonth

	-- Apply interest to existing debt first.
	if life.bills.debt > 0 then
		local interest = math.floor(life.bills.debt * BILLS.DebtInterestRate)
		life.bills.debt += interest
		if life.bills.debt > BILLS.MaxDebt then
			life.bills.debt = BILLS.MaxDebt
		end
	end

	local totalOwed = bill + life.bills.debt
	local paid = MoneyService.Spend(player, totalOwed, "monthly bill")

	if paid then
		BILL_DUE:FireClient(player, {
			totalThisMonth = bill,
			debt = 0,
			paid = true,
			notice = "Bill paid: " .. tostring(bill) .. " this month.",
		})
		return totalOwed
	else
		-- Could not pay in full. Whatever was there goes to the bill, the rest becomes debt.
		local remaining = totalOwed - life.money
		if remaining < 0 then
			remaining = 0
		end
		life.bills.debt = math.min(remaining, BILLS.MaxDebt)
		BILL_DUE:FireClient(player, {
			totalThisMonth = bill,
			debt = life.bills.debt,
			paid = false,
			notice = "Could not pay the full bill. " .. tostring(life.bills.debt) .. " added to debt.",
		})
		return life.money
	end
end

-- Get the current bill state for a player's client.
function BillService.GetState(player: Player): Types.BillState?
	local life = lifeDataFor(player)
	if life == nil then
		return nil
	end
	return {
		totalThisMonth = computeBill(life),
		debt = life.bills.debt,
		paid = life.bills.lastBillMonth >= (life.ageMonths // Config.Time.MonthsPerYear) * Config.Time.MonthsPerYear,
		notice = nil,
	}
end

function BillService:Init()
	-- No remotes to register. Billing is driven by LifeService on age-up.
	Players.PlayerAdded:Connect(function(player: Player)
		-- Push current state on join.
		local state = BillService.GetState(player)
		if state ~= nil then
			BILL_DUE:FireClient(player, state)
		end
	end)
end

function BillService:Start()
	-- No background tick needed. Bills are charged on age-up.
end

return BillService
