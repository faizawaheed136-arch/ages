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
--
-- Debt consequences live in StatService: the flag is the contract there, and
-- BillService only sets and clears it. This file never touches stats.

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

-- Whether this life is old enough to be billed at all. A child is somebody else's
-- dependent, and the game says so by not sending them a bill rather than by sending
-- them one for nothing -- see Config.Bills.MinAge for why the boundary is Adulthood.
--
-- Asked in all three places a bill can reach the player: the charge, the state the
-- HUD reads, and the push on join. Gating only the charge would have left a child
-- looking at a bill they were never actually charged, which is the same bug wearing
-- a different face.
local function oldEnoughToBill(life: LifeData): boolean
	return life.ageMonths // Config.Time.MonthsPerYear >= BILLS.MinAge
end

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

	-- Before adulthood there is nothing to charge and nothing to record. Deliberately
	-- leaves lastBillMonth alone rather than advancing it through childhood: the first
	-- adult birthday then charges exactly one bill, which is the right answer. Advancing
	-- it would work too, but it would mean eighteen writes to say nothing happened.
	--
	-- Still pushes, with nil, rather than returning in silence. The HUD's bill row is
	-- only ever changed by this remote, so a path that swaps the active life without
	-- rebuilding the client -- /slots switch does exactly that -- would otherwise leave
	-- an adult's debt sitting over a child's head until their eighteenth birthday. One
	-- cleared row per birthday is a cheaper contract than reasoning about which paths
	-- can reach a stale one.
	if not oldEnoughToBill(life) then
		BILL_DUE:FireClient(player, nil)
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

	-- Debt state changes are flags, not stats. They open content doors — loan sharks,
	-- counselling, family help — so the number in bills.debt is not the only thing that
	-- matters when a life is in the red. The flag is set the moment debt appears and
	-- cleared the moment it vanishes; a life that dips into debt and pays it back in the
	-- same billing cycle still gets the events that flag carries.
	local wasInDebt = life.bills.debt > 0

	local totalOwed = bill + life.bills.debt
	local paid = MoneyService.Spend(player, totalOwed, "monthly bill")

	if paid then
		life.bills.debt = 0
		if wasInDebt then
			life.flags["in_debt"] = nil
		end
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
		if life.bills.debt > 0 then
			life.flags["in_debt"] = ageYears
		elseif wasInDebt then
			life.flags["in_debt"] = nil
		end
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
	-- Same nil a player with no life gets. The HUD already knows how to show nothing
	-- for that, so a child gets no bill panel rather than an empty one -- the absence
	-- is the message.
	if not oldEnoughToBill(life) then
		return nil
	end
	return {
		totalThisMonth = computeBill(life),
		debt = life.bills.debt,
		paid = life.bills.lastBillMonth >= (life.ageMonths // Config.Time.MonthsPerYear) * Config.Time.MonthsPerYear,
		notice = nil,
		inDebt = life.bills.debt > 0,
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
