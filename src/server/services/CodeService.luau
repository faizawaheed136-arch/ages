--!strict
-- The redeem box. One string in, one sentence back, and a reward that is decided entirely
-- from `content/Codes.luau` and never from anything the client sent.
--
-- **This is the only free-text input the game place has**, and everything unusual about
-- this file follows from that. The lobby's name field is the other one, and it was put in
-- the lobby precisely so that the place with a world running in it would have none. This
-- one has to be here -- a code is something you redeem while playing -- so it is handled
-- the way a free-text field from a client has to be: length-capped before it is looked at,
-- rate-limited per player, matched against a fixed table, and answered with the same
-- sentence whether the code was wrong or never existed.
--
-- **Order of operations, and it is the whole correctness argument.** Decide the outcome,
-- record the redemption, *then* pay. Paying first and recording after leaves a window in
-- which a second attempt lands between the two and pays twice; there is no lock here and
-- there does not need to be, because the record is written before anything is granted and
-- the second attempt reads it and refuses.
--
-- **A code is account-level.** It is written to `ProfileData.redeemedCodes`, not to the
-- life, so a player cannot bank a code, delete the slot and cash it again -- three times
-- over, with three slots, on every code the game ever ships.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local Codes = require(script.Parent.Parent.content.Codes)
local DataService = require(script.Parent.DataService)
local MoneyService = require(script.Parent.MoneyService)

type Player = Players.Player
type CodeEntry = Codes.CodeEntry
type RedeemedCode = Types.RedeemedCode

local CodeService = {}

local CODES = Config.Codes
local CODES_UPDATED = Remotes.Get("CodesUpdated")
local CODE_RESULT = Remotes.Get("CodeResult")
local REQUEST_REDEEM = Remotes.Get("RequestRedeemCode")

-- When each player last tried. Cleared on leave rather than left to grow, because this is
-- keyed by Player instance and a stale key would pin the object.
local lastAttempt: { [Player]: number } = {}

-- The same sentence for "that is not a code" and "that code is retired", on purpose. Two
-- different refusals would turn the box into an oracle that answers "does this code exist"
-- for free, which is exactly what somebody enumerating strings wants from it.
local UNKNOWN = "That code isn't one we recognise. Check the spelling and try again."

local function reply(player: Player, ok: boolean, message: string)
	CODE_RESULT:FireClient(player, { ok = ok, message = message } :: Types.CodeResult)
end

-- Everything this account has used, newest content order, each with what it paid.
--
-- Built by walking the content list rather than the save, so the pane lists redemptions in
-- a stable order and an id in the save with no entry behind it is skipped rather than
-- drawn as a blank row. That gap should not happen -- `Codes.luau` says never to delete a
-- row -- but a receipt is the wrong place to find out that somebody did.
local function stateFor(player: Player): { RedeemedCode }
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return {}
	end

	local redeemed: { RedeemedCode } = {}
	for _, entry in Codes.Entries do
		if profile.Data.redeemedCodes[entry.id] then
			table.insert(redeemed, {
				id = entry.id,
				code = entry.code,
				label = entry.label,
				reward = Codes.Describe(entry),
			})
		end
	end
	return redeemed
end

function CodeService.Push(player: Player)
	if DataService.GetProfile(player) == nil then
		return
	end
	CODES_UPDATED:FireClient(player, { redeemed = stateFor(player) } :: Types.CodesState)
end

-- Hand over what one entry pays. Called only after the redemption is already recorded, so
-- a failure to pay costs the player a reward and never lets them have it twice -- which is
-- the right way round for a mistake to go wrong.
local function grant(player: Player, entry: CodeEntry): string
	local paid: { string } = {}

	local money = entry.money or 0
	if money > 0 then
		MoneyService.Add(player, money, `code {entry.id}`)
		table.insert(paid, "it's in your pocket")
	end

	local spins = entry.spins or 0
	if spins > 0 then
		local profile = DataService.GetProfile(player)
		if profile ~= nil then
			profile.Data.spinsAvailable += spins
			-- Said out loud because a spin is spent in the lobby and this is the game place.
			-- A player who redeems a spin code here and sees nothing change on screen has
			-- been given something they have no way of knowing about.
			table.insert(paid, "your spins are waiting in the menu")
		end
	end

	return table.concat(paid, ", and ")
end

-- The whole redemption, from a typed string to a sentence. Returns the sentence so that
-- the remote handler and the debug command are the same code path rather than two.
local function redeem(player: Player, typed: string): (boolean, string)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false, "Your save isn't loaded yet. Give it a moment."
	end

	if #typed > CODES.MaxLength then
		-- Checked on the raw string, before normalizing, because normalizing allocates and
		-- a length check is what stops a client sending a megabyte to be uppercased.
		return false, UNKNOWN
	end

	local entry = Codes.Find(typed)
	if entry == nil or not entry.active then
		return false, UNKNOWN
	end

	if profile.Data.redeemedCodes[entry.id] then
		-- The one refusal that names the code rather than hiding behind `UNKNOWN`, and it is
		-- safe to: the player has already proved they know this one, so there is nothing left
		-- to leak. It is also the refusal most likely to be a real player double-clicking.
		return false, `You've already redeemed {entry.code}.`
	end

	local count = 0
	for _ in profile.Data.redeemedCodes do
		count += 1
	end
	if count >= CODES.MaxRedeemed then
		-- Unreachable while the content list is shorter than the cap, which it is by a wide
		-- margin. It is here because `redeemedCodes` is an unbounded dictionary written to a
		-- save, and every unbounded thing in this tree has a ceiling with a sentence on it.
		return false, "You've redeemed as many codes as an account can hold."
	end

	-- Recorded before anything is paid. See the header: this is what makes a double-fire
	-- cost the player a duplicate refusal rather than paying them twice.
	profile.Data.redeemedCodes[entry.id] = true

	local where = grant(player, entry)
	CodeService.Push(player)

	local reward = Codes.Describe(entry)
	if where == "" then
		return true, `{entry.code} redeemed: {reward}.`
	end
	return true, `{entry.code} redeemed: {reward} — {where}.`
end

function CodeService:Init()
	REQUEST_REDEEM.OnServerEvent:Connect(function(player: Player, typed: unknown)
		if type(typed) ~= "string" then
			return
		end

		local now = os.clock()
		local previous = lastAttempt[player]
		if previous ~= nil and now - previous < CODES.AttemptCooldownSeconds then
			-- Answered rather than dropped. A silently ignored attempt looks to a player
			-- exactly like a box that does not work, and the one thing this field must never
			-- do is leave somebody unsure whether it heard them.
			reply(player, false, "Slow down a moment, then try again.")
			return
		end
		lastAttempt[player] = now

		local ok, message = redeem(player, typed)
		reply(player, ok, message)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		CodeService.Push(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		lastAttempt[player] = nil
	end)
end

function CodeService:Start()
	-- Nothing to run. A code is redeemed when somebody types one, and never otherwise.
end

-- What this account has used, on one line, for `/code`.
function CodeService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile"
	end

	local used: { string } = {}
	for _, entry in stateFor(player) do
		table.insert(used, `{entry.code} ({entry.reward})`)
	end
	if #used == 0 then
		return `none redeemed of {#Codes.Entries} in the list`
	end
	return `{#used} of {#Codes.Entries}: {table.concat(used, ", ")}`
end

-- Redeem from a debug command, through the same path a typed one takes -- including the
-- already-redeemed refusal, which is the case `/code` exists to test.
function CodeService.Force(player: Player, typed: string): string
	local _, message = redeem(player, typed)
	return message
end

-- Un-redeem everything, so the same code can be tested twice without a fresh account.
-- Deliberately the only way back: nothing in the game removes a redemption, because a code
-- that can be given back is a code that can be redeemed twice.
function CodeService.Clear(player: Player): number
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return 0
	end

	local cleared = 0
	for id in profile.Data.redeemedCodes do
		profile.Data.redeemedCodes[id] = nil
		cleared += 1
	end
	CodeService.Push(player)
	return cleared
end

return CodeService
