--!strict
-- The only place a balance is ever written. Everything that moves money goes
-- through Add or Spend here, which is what makes "where did that come from" a
-- question with one place to look rather than a search.
--
-- Server-authoritative with no client path at all: there is no remote into this
-- service, only one out of it. The client is told what it has and never asked.
--
-- Every write below is a read-modify-write with no yield in the middle. Luau on
-- the server runs one thing at a time, so an uninterrupted stretch like that is
-- atomic by construction -- but only while it stays uninterrupted, which is why
-- nothing here waits on anything. A task.wait() inside one of these functions
-- would silently turn a balance into something two callers could interleave on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Money = require(ReplicatedStorage:WaitForChild("Money"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)

local MoneyUpdatedRemote = Remotes.Get("MoneyUpdated")

local MoneyService = {}

-- Printed for every movement, in Studio only. The single most likely complaint
-- about an economy is "my money changed and I don't know why", and the answer has
-- to exist before the question is asked -- reconstructing it afterwards from a
-- balance and a guess is not possible. Off in a live server because a busy one
-- would fill the log with it and because a player cannot read the output anyway.
local LEDGER = RunService:IsStudio()

local function ledger(player: Player, delta: number, balance: number, reason: string)
	if not LEDGER then
		return
	end
	local sign = if delta >= 0 then "+" else "-"
	print(`[AGES money] {player.Name} {sign}{Money.Format(math.abs(delta))} -> {Money.Format(balance)} ({reason})`)
end

-- Pushed on every change and on join, so the HUD never has to ask. One number, so
-- there is nothing to diff and nothing to get out of order.
local function push(player: Player, balance: number)
	MoneyUpdatedRemote:FireClient(player, balance)
end

-- Whole units only. Content validation rejects a fractional price at load, so in
-- practice this only ever bites the Studio command -- and truncating there is the
-- right answer, because "/money 12.7" means twelve and asking the player to be
-- precise about it would be a worse harness.
local function whole(amount: number): number
	return math.floor(amount)
end

-- What a life starts with.
--
-- A function rather than a direct read of Config, and this is the seam the whole
-- money system is built to leave open. Being born into a family with something
-- behind it -- the difference between an ordinary house and a palace -- changes
-- exactly this answer and nothing else: the profile field, the HUD, the prices and
-- every guard downstream are all indifferent to where the first figure came from.
--
-- One number today, and deliberately not a speculative table of family types with
-- one entry in it. When backgrounds exist they will be content, chosen at the
-- moment a life begins, and read here.
function MoneyService.StartingBalance(_player: Player): number
	return whole(Config.Money.StartingBalance)
end

function MoneyService.Get(player: Player): number?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return Lives.Active(profile.Data).money
end

-- Whether the player could pay this right now. Used both to decide what a choice
-- looks like before it is taken and to refuse it when it is, so the two can never
-- disagree about what is affordable.
--
-- A missing profile answers false rather than nil. Every caller would treat nil as
-- "no" anyway, and an optional here would put a narrowing step in front of what is
-- meant to read as a plain question.
function MoneyService.CanAfford(player: Player, amount: number): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	return Lives.Active(profile.Data).money >= whole(amount)
end

-- Money in. `reason` is for the ledger and is never stored -- it says why this
-- happened, which matters while the server is running and not afterwards.
--
-- Idempotency is the caller's problem and deliberately so. Every payout in the
-- game comes from resolving a choice, and ResolveChoice consumes the pending event
-- before it pays, so a retried answer is refused before it reaches here. A token
-- scheme in this service would be a second guard against the same thing, which is
-- how two guards drift apart.
function MoneyService.Add(player: Player, amount: number, reason: string): number
	local profile = DataService.GetProfile(player)
	if profile == nil then
		-- Loud, because this is money the player earned and did not get. Nothing in
		-- the current call paths can reach here -- they all hold a profile already --
		-- so if it ever fires, something new is paying out a player who has left.
		warn(`[AGES] cannot pay {player.Name} {Money.Format(amount)} ({reason}): no profile`)
		return 0
	end

	local gain = whole(amount)
	if gain < 0 then
		-- Add is for money in and Spend is for money out, and keeping them one-way
		-- is what makes the ledger readable. A negative here is a caller bug, not a
		-- refund.
		warn(`[AGES] Add called with a negative amount ({gain}) for {reason}; use Spend`)
		return Lives.Active(profile.Data).money
	end

	local data = Lives.Active(profile.Data)
	data.money = math.min(data.money + gain, Config.Money.MaxBalance)
	ledger(player, gain, data.money, reason)
	push(player, data.money)
	return data.money
end

-- Money out. Returns whether it happened, and refuses rather than overdrawing --
-- so a caller that forgets to check affordability first cannot produce a negative
-- balance, only a false it ignores.
function MoneyService.Spend(player: Player, amount: number, reason: string): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end

	local price = whole(amount)
	if price < 0 then
		warn(`[AGES] Spend called with a negative amount ({price}) for {reason}; use Add`)
		return false
	end

	local data = Lives.Active(profile.Data)
	if data.money < price then
		-- Loud, because every caller is supposed to have asked CanAfford first and
		-- the client is supposed to have been told the choice was locked. Reaching
		-- here means one of those two is wrong, and it is not the kind of wrong that
		-- shows up as anything else.
		warn(
			`[AGES] {player.Name} cannot afford {Money.Format(price)} for {reason} `
				.. `(has {Money.Format(data.money)}); refused`
		)
		return false
	end

	data.money -= price
	ledger(player, -price, data.money, reason)
	push(player, data.money)
	return true
end

-- Studio harness only, and the one function here that sets rather than moves. Kept
-- separate from Add and Spend precisely so the ledger can say which it was: an
-- amount that appeared because a tester asked for it should never be mistaken for
-- one the game paid out.
function MoneyService.Set(player: Player, amount: number): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end

	local data = Lives.Active(profile.Data)
	local target = math.clamp(whole(amount), 0, Config.Money.MaxBalance)
	ledger(player, target - data.money, target, "debug /money")
	data.money = target
	push(player, data.money)
	return true
end

-- `ResetForNewLife` used to live here, and it is gone rather than kept for later. It set a
-- life's balance back to `StartingBalance` for the rebirth that ran in place; there is no
-- rebirth any more -- a new life is a fresh `Lives.New()`, which reads the same number out of
-- Config on the way in -- so the reset had nothing left to reset. See `Lives.New`.

function MoneyService.Push(player: Player)
	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		push(player, Lives.Active(profile.Data).money)
	end
end

function MoneyService:Init() end

function MoneyService:Start()
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			local profile = DataService.WaitForProfile(player)
			if profile ~= nil then
				push(player, Lives.Active(profile.Data).money)
			end
		end)
	end)
end

return MoneyService
