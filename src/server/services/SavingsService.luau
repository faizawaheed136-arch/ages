--!strict
-- Savings account. A life can deposit money, withdraw it, and earn monthly
-- interest while it sits there. The account is separate from pocket money so a
-- life that saves feels the gap between what it carries and what it has grown.
--
-- Interest compounds on age-up, alongside bills, so a saver and a defaulter
-- diverge every birthday. Deposits and withdrawals are remote-triggered and
-- pushed back to the client as a full snapshot — there is no incremental update.

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

local SavingsService = {}

local SAVINGS = Config.Savings
local SAVINGS_UPDATED = Remotes.Get("SavingsUpdated")
local REQUEST_DEPOSIT = Remotes.Get("RequestDeposit")
local REQUEST_WITHDRAW = Remotes.Get("RequestWithdraw")

-- Get the life data for a player, nil if no profile or no active life.
local function lifeDataFor(player: Player): LifeData?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return Lives.Active(profile.Data)
end

-- Push the full savings state to a player's client.
local function pushSavingsState(player: Player, life: LifeData)
	SAVINGS_UPDATED:FireClient(player, {
		balance = life.savings.balance,
		maxBalance = SAVINGS.MaxBalance,
		interestRate = SAVINGS.InterestRate,
	})
end

-- Credit one month of compound interest on the savings balance.
-- Called from LifeService.OnAgeUp so it runs once per birthday.
function SavingsService.CreditInterest(player: Player)
	local life = lifeDataFor(player)
	if life == nil then
		return
	end

	local balance = life.savings.balance
	if balance <= 0 then
		return
	end

	local interest = math.floor(balance * SAVINGS.InterestRate)
	if interest <= 0 then
		return
	end

	life.savings.balance += interest
	MoneyService.Add(player, interest, "savings interest")
	pushSavingsState(player, life)
end

-- Deposit money into the savings account.
-- Returns ("ok", newBalance) on success, ("error", reason) on failure.
function SavingsService.Deposit(player: Player, amount: number): (boolean, number?, string?)
	if typeof(amount) ~= "number" or amount <= 0 then
		return false, nil, "Invalid amount"
	end

	local life = lifeDataFor(player)
	if life == nil then
		return false, nil, "No active life"
	end

	-- Move from pocket money into savings.
	local moved = MoneyService.Spend(player, amount, "deposited to savings")
	if not moved then
		return false, nil, "Not enough money"
	end

	local newBalance = life.savings.balance + amount
	if newBalance > SAVINGS.MaxBalance then
		-- Overflow goes back to pocket money; the cap is on savings only.
		local overflow = newBalance - SAVINGS.MaxBalance
		life.savings.balance = SAVINGS.MaxBalance
		MoneyService.Add(player, overflow, "savings cap overflow")
		newBalance = SAVINGS.MaxBalance
	else
		life.savings.balance = newBalance
	end

	pushSavingsState(player, life)
	return true, newBalance, nil
end

-- Withdraw money from the savings account.
-- Returns ("ok", newBalance) on success, ("error", reason) on failure.
function SavingsService.Withdraw(player: Player, amount: number): (boolean, number?, string?)
	if typeof(amount) ~= "number" or amount <= 0 then
		return false, nil, "Invalid amount"
	end

	local life = lifeDataFor(player)
	if life == nil then
		return false, nil, "No active life"
	end

	if life.savings.balance < amount then
		return false, nil, "Insufficient savings"
	end

	life.savings.balance -= amount
	MoneyService.Add(player, amount, "withdrew from savings")
	pushSavingsState(player, life)
	return true, life.savings.balance, nil
end

function SavingsService:Init()
	REQUEST_DEPOSIT.OnServerEvent:Connect(function(player: Player, amount: any)
		if typeof(amount) ~= "number" then
			return
		end
		local ok, _, err = SavingsService.Deposit(player, amount)
		if not ok then
			warn(`[AGES] Deposit failed for {player.Name}: {err}`)
		end
	end)

	REQUEST_WITHDRAW.OnServerEvent:Connect(function(player: Player, amount: any)
		if typeof(amount) ~= "number" then
			return
		end
		local ok, _, err = SavingsService.Withdraw(player, amount)
		if not ok then
			warn(`[AGES] Withdraw failed for {player.Name}: {err}`)
		end
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		local life = lifeDataFor(player)
		if life ~= nil then
			pushSavingsState(player, life)
		end
	end)
end

function SavingsService:Start()
	-- No background tick needed. Savings change only on action or age-up.
end

return SavingsService
