--!strict
-- Studio-only chat commands for the lobby, on the same terms as the game place's
-- DebugService: it bails out unless `RunService:IsStudio()`, so a live server never has one
-- of these connected.
--
-- Its own file rather than a second copy of the game place's DebugService, and deliberately
-- much smaller. The two harnesses share a dispatcher shape and nothing else -- there is no
-- life running in here to age, kill or pay -- and the honest way to say that is a short file
-- with four commands in it rather than a long one with thirty that error.
--
-- The commands are chosen around the one thing that is genuinely hard to see from inside the
-- lobby: **the teleport does not work in Studio at all**, so every path that ends in one has
-- to be testable up to the point it would fire. `/play` reports exactly what Play would have
-- refused or done, without doing it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local DataService = require(script.Parent.Parent.shared.DataService)
local LifeSetup = require(script.Parent.Parent.shared.LifeSetup)
local Perks = require(script.Parent.Parent.content.Perks)
local LobbyService = require(script.Parent.LobbyService)
local LobbySetupService = require(script.Parent.LobbySetupService)
local SpinsService = require(script.Parent.SpinsService)
local StageService = require(script.Parent.StageService)

local PREFIXES = { "/", "!" }

local Commands: { [string]: (Player, { string }) -> string } = {}

local HELP_TEXT = "lobby commands: /slots [list|use <n>|delete <n>], /create [n], /play [n], "
	.. "/stage [list|rebuild], /spins [list|grant <n>|roll|perk <id>], /joincode [gen|revoke|list], /ids"

-- The same listing the game place's `/slots` prints, and deliberately the same wording.
--
-- Two harnesses describing one save in two vocabularies is how a session ends with somebody
-- convinced the lobby and the game disagree about which life is active. They do not; the
-- text does.
Commands.slots = function(player: Player, args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end
	local data = profile.Data
	local action = string.lower(args[1] or "list")

	-- Both of these go through the same functions the cards call rather than writing the
	-- profile here, so the harness cannot do anything a click could not. The one visible cost
	-- is that a refusal appears on screen instead of in this return value -- which is the
	-- right place for it, because that is where a player would read it.
	if action == "use" then
		local index = tonumber(args[2])
		if index == nil then
			return "usage: /slots use <n>"
		end
		LobbyService.Select(player, index)
		return `select requested on slot {index} -- the cards redrawing is the answer`
	end

	if action == "delete" then
		local index = tonumber(args[2])
		if index == nil then
			return `usage: /slots delete <1-{Config.Slots.Count}>`
		end
		-- No second press asked for here, unlike the card, and no refusal for deleting the
		-- *active* slot, unlike the game place's harness. Both differences are the point: in
		-- the game place that slot is running, and in the lobby nothing is -- which is exactly
		-- why deleting a life is the lobby's job.
		LobbyService.Delete(player, index)
		return `delete requested on slot {index} -- the cards redrawing is the answer`
	end

	local lines = { "" }
	for index = 1, Config.Slots.Count do
		local life = data.slots[index]
		local marker = if index == data.activeSlot then ">" else " "
		if life == nil then
			table.insert(lines, `{marker} {index}: MISSING -- ensureSlots did not run`)
		elseif not Lives.HasBegun(life) then
			table.insert(lines, `{marker} {index}: empty`)
		else
			local setup = life.setup
			local name = if setup ~= nil then `{setup.firstName} {setup.lastName}` else "?"
			local state = if life.alive then "alive" else "dead"
			table.insert(lines, `{marker} {index}: {name}, age {math.floor(life.ageMonths / 12)}, {state}`)
		end
	end
	table.insert(lines, `slot {data.activeSlot} of {Config.Slots.Count} active (schema {data.schema}, {data.livesLived} lives lived)`)
	return table.concat(lines, "\n  ")
end

-- Fill a slot without typing a card.
--
-- The harness's answer to the create page, and the lobby's counterpart to the game place's
-- `/setup skip`: a test of the Play handoff, of a delete confirmation, or of how three full
-- cards look side by side should not begin with three names being typed in.
--
-- Goes through the real `LobbySetupService.Create` with a payload shaped exactly like the
-- wire's, so it is checked by the same parser, filtered by the same filter and refused by the
-- same rules -- including the empty-slot check, which is why a full slot answers on screen
-- rather than here. The one thing a harness must never do is start a life by a route a player
-- could not take.
Commands.create = function(player: Player, args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end
	local slot = tonumber(args[1]) or profile.Data.activeSlot
	local gender: Types.Gender = if math.random() < 0.5 then "female" else "male"
	local setup = LifeSetup.Roll(gender)
	-- Deliberately spends nothing. The points are the one part of the card worth checking by
	-- hand, and a harness that always spent them would make "did my spend land" untestable.
	LobbySetupService.Create(player, slot, {
		gender = gender,
		firstName = setup.firstName,
		lastName = setup.lastName,
		countryId = setup.countryId,
		eraId = setup.eraId,
		statDeltas = {},
	})
	return `create requested on slot {slot}: {setup.firstName} {setup.lastName}, {setup.countryId}, `
		.. `era {setup.eraId} -- the cards redrawing (or a refusal on screen) is the answer`
end

-- Robux, without Robux.
--
-- `grant` credits spins the same way a real receipt would, straight onto the profile -- there
-- is no honest way to fake a purchase prompt in Studio, so this is the harness's stand-in for
-- one. `roll` spends a spin through the real `SpinsService.RequestSpin`, so a pull in a test
-- session is checked by the exact code a paying player's is, not a second copy of it. `perk`
-- grants a named perk directly, which is what testing the picker on `SetupCard` needs and
-- what a fair roll cannot promise on demand.
Commands.spins = function(player: Player, args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end
	local action = string.lower(args[1] or "list")

	if action == "grant" then
		local amount = tonumber(args[2]) or 1
		profile.Data.spinsAvailable += amount
		SpinsService.Push(player)
		return `granted {amount} spin(s) -- {profile.Data.spinsAvailable} available`
	end

	if action == "roll" then
		SpinsService.RequestSpin(player)
		return "spin requested -- the result (or a refusal) is on screen"
	end

	if action == "perk" then
		local perkId = args[2]
		if perkId == nil or Perks.ById[perkId] == nil then
			local ids = {}
			for _, perk in Perks.All do
				table.insert(ids, perk.id)
			end
			return `usage: /spins perk <id> -- one of: {table.concat(ids, ", ")}`
		end
		profile.Data.perks[perkId] = (profile.Data.perks[perkId] or 0) + 1
		SpinsService.Push(player)
		return `granted perk {perkId} -- {profile.Data.perks[perkId]} owned`
	end

	local lines = { "", `{profile.Data.spinsAvailable} spin(s) available` }
	local anyPerks = false
	for _, perk in Perks.All do
		local count = profile.Data.perks[perk.id]
		if count ~= nil and count > 0 then
			anyPerks = true
			table.insert(lines, `{perk.id} ({perk.rarity}) x{count}`)
		end
	end
	if not anyPerks then
		table.insert(lines, "no perks owned")
	end
	return table.concat(lines, "\n  ")
end

-- What Play would do, without doing it.
--
-- Runs the real refusal checks by calling the real function, which in Studio always stops at
-- the "teleports do not work here" gate -- so this is a genuine dry run rather than a second
-- implementation of the rules that could drift from them.
Commands.play = function(player: Player, args: { string }): string
	local profile = DataService.GetProfile(player)
	local slot = tonumber(args[1]) or (if profile ~= nil then profile.Data.activeSlot else 1)
	LobbyService.Play(player, slot)
	return `play requested on slot {slot} -- the refusal (or the teleport) is on your screen`
end

Commands.stage = function(player: Player, args: { string }): string
	local action = string.lower(args[1] or "list")
	if action == "rebuild" then
		StageService.Ensure(player)
		local character = player.Character
		if character ~= nil then
			-- `Place` writes the root's CFrame directly, which works on an already-anchored
			-- part, so a second call needs no unanchoring first. It has to be called at all
			-- because the old stage was just destroyed and the character is still standing
			-- where it used to be.
			StageService.Place(player, character)
		end
		return "stage rebuilt and character replaced on the mark"
	end
	return "\n  " .. table.concat(StageService.Describe(), "\n  ")
end

-- The two numbers that have to be filled in by hand, and the one failure mode nothing else
-- can see: a place id that is set but *wrong* teleports you somewhere real and confusing.
Commands.ids = function(_player: Player, _args: { string }): string
	local game_ = if Config.Lobby.GamePlaceId == 0 then "NOT SET" else tostring(Config.Lobby.GamePlaceId)
	local lobby = if Config.Lobby.LobbyPlaceId == 0 then "NOT SET" else tostring(Config.Lobby.LobbyPlaceId)
	return `this place: {game.PlaceId} -- Config.Lobby.GamePlaceId: {game_} -- LobbyPlaceId: {lobby}`
end

Commands.joincode = function(player: Player, args: { string }): string
	local action = string.lower(args[1] or "list")

	if action == "gen" or action == "generate" then
		local code = LobbyService.GenerateJoinCode(player)
		if code == nil then
			return "could not generate a code -- the active slot has no life"
		end
		local p = DataService.GetProfile(player)
		local slot = p and p.Data.activeSlot or 1
		return `generated {code} for slot {slot}`
	end

	if action == "revoke" then
		local revoked = LobbyService.RevokeJoinCode(player, args[2])
		if revoked then
			return "code revoked"
		end
		return "no code to revoke"
	end

	-- Default: list.
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end
	local slot = profile.Data.activeSlot
	local life = profile.Data.slots[slot]
	return `active slot {slot}: {if life ~= nil and Lives.HasBegun(life) then life.setup.firstName .. " " .. life.setup.lastName else "no life"} -- generate with /joincode gen`
end

Commands.help = function(_player: Player, _args: { string }): string
	return HELP_TEXT
end

local function stripPrefix(message: string): string?
	for _, prefix in PREFIXES do
		if string.sub(message, 1, #prefix) == prefix then
			return string.sub(message, #prefix + 1)
		end
	end
	return nil
end

local function onChatted(player: Player, message: string)
	local body = stripPrefix(message)
	if body == nil then
		return
	end
	local parts = string.split(body, " ")
	local name = string.lower(table.remove(parts, 1) or "")
	local handler = Commands[name]
	if handler == nil then
		return
	end
	local ok, result = pcall(handler, player, parts)
	if ok then
		print(`[AGES lobby debug] {player.Name}: {result}`)
	else
		warn(`[AGES lobby debug] /{name} failed: {result}`)
	end
end

local LobbyDebugService = {}

function LobbyDebugService:Init() end

function LobbyDebugService:Start()
	if not RunService:IsStudio() then
		return
	end

	local function watch(player: Player)
		player.Chatted:Connect(function(message: string)
			onChatted(player, message)
		end)
	end

	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	print(`[AGES lobby debug] Studio commands active — {HELP_TEXT}`)
end

return LobbyDebugService
