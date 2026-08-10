--!strict
-- The lobby's only job that is not scenery: tell the client what lives the player owns, and
-- send them into one.
--
-- **The handoff is the whole difficulty, and it is a consequence of session locking.** One
-- ProfileStore key can be open in exactly one server at a time. The lobby holds it while the
-- player is standing on the stage, so the game place cannot open it until the lobby lets go
-- — and the lobby only lets go when the player has actually left, in `PlayerRemoving`.
-- The sequence is therefore fixed and there is no room to be clever in it:
--
--   1. Write `activeSlot` on the profile. Which life to run travels *in the save*, not in
--      TeleportData -- see the comment on `ProfileData.activeSlot` for why.
--   2. Teleport. The player leaves; ProfileStore's session ends and does its final save,
--      which is what makes step 1 durable.
--   3. The game place calls StartSessionAsync, finds the key released, and loads it.
--
-- The cost is that Play is not instant -- it is a teleport plus a datastore handoff. That
-- is paid once per life, at the one moment the player has just chosen to wait.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local DataService = require(script.Parent.Parent.shared.DataService)
local Countries = require(script.Parent.Parent.shared.Countries)
local LobbySetupService = require(script.Parent.LobbySetupService)

type LobbyState = Types.LobbyState
type SlotSummary = Types.SlotSummary

local SlotsUpdatedRemote = Remotes.Get("LobbySlotsUpdated")
local RequestPlayRemote = Remotes.Get("RequestPlay")
local PlayRefusedRemote = Remotes.Get("PlayRefused")
local RequestSelectSlotRemote = Remotes.Get("RequestSelectSlot")
local RequestDeleteSlotRemote = Remotes.Get("RequestDeleteSlot")
local SlotActionRefusedRemote = Remotes.Get("SlotActionRefused")

local LobbyService = {}

-- Who has a teleport in the air, and since when.
--
-- A timestamp rather than a boolean, because a boolean that is only ever cleared on success
-- or on a caught failure is a boolean that stays true forever the one time neither happens
-- -- and the player is then holding a Play button that will never work again with no way to
-- find out why. The stamp expires, so the worst case is a wait rather than a dead session.
local inFlight: { [Player]: number } = {}

local function refuse(player: Player, reason: string)
	PlayRefusedRemote:FireClient(player, reason)
end

-- Kept apart from `refuse` above, which is Play's channel. See the comments on the two
-- remotes: a card action is answered in the same instant on a line under the cards, and Play
-- is a slow call to another server whose refusal arrives after the screen has gone busy.
local function refuseSlotAction(player: Player, reason: string)
	SlotActionRefusedRemote:FireClient(player, reason)
end

-- Whether there is a life in this slot to press Play on, select, or delete.
--
-- Takes an already-bounds-checked slot; every caller has been through `blockedBecause` or
-- `slotBlockedBecause` first, both of which answer a bad number before this is reached.
local function hasLife(player: Player, slot: number): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	local life = profile.Data.slots[slot]
	return life ~= nil and Lives.HasBegun(life)
end

-- One slot as a card. Ages are reported in whole years because that is how the card reads
-- them; months are the game place's business.
local function summarize(index: number, life: Types.LifeData): SlotSummary
	if not Lives.HasBegun(life) then
		return { index = index, begun = false }
	end
	-- Narrowed by HasBegun, but Luau cannot see through a function call, so the field is
	-- re-tested here rather than asserted. An assert would be a crash in the lobby -- the one
	-- place in this game with nothing behind it to fall back to.
	local setup = life.setup
	if setup == nil then
		return { index = index, begun = false }
	end
	local country = Countries.ById[setup.countryId]
	return {
		index = index,
		begun = true,
		name = `{setup.firstName} {setup.lastName}`,
		-- Falls back to the stored id rather than to "Unknown" if the country has been
		-- renamed out of content. The id is at least true, and a card reading `gb_north`
		-- says exactly which content entry went missing.
		country = if country ~= nil then country.name else setup.countryId,
		gender = life.gender,
		ageYears = math.floor(life.ageMonths / 12),
		alive = life.alive,
	}
end

function LobbyService.StateFor(player: Player): LobbyState?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	local data = profile.Data
	local slots: { SlotSummary } = {}
	for index = 1, Config.Slots.Count do
		local life = data.slots[index]
		if life ~= nil then
			table.insert(slots, summarize(index, life))
		end
	end
	return {
		slots = slots,
		activeSlot = data.activeSlot,
		slotCount = Config.Slots.Count,
		livesLived = data.livesLived,
	}
end

-- Push the whole state. Called on join and after anything that could change a card.
--
-- Silent when there is no profile, which is the one case where saying nothing is right: the
-- client opens with its cards blank and waits, and a "your data has not loaded" message
-- that resolves itself a second later is noise the player has to learn to ignore.
function LobbyService.Push(player: Player)
	local state = LobbyService.StateFor(player)
	if state == nil then
		return
	end
	SlotsUpdatedRemote:FireClient(player, state)
end

-- Why Play cannot happen right now, or nil if it can.
--
-- Every one of these is checked before anything is written or any web call is made. The
-- alternative -- teleport and see -- leaves `activeSlot` moved for a journey that did not
-- happen, so the player's next Play would open a different life than the card they pressed.
-- Ordered so that anything wrong with the *request* is answered before anything wrong with
-- the *environment*. A slot number out of range is a bad ask and should be told so whether
-- it was made in Studio or in production; reversing these would have a nonsense slot come
-- back with a cheerful "teleports do not work in Studio", and the caller in `Play` would
-- then claim to have selected it.
local function blockedBecause(player: Player, slot: number): string?
	if slot ~= math.floor(slot) or slot < 1 or slot > Config.Slots.Count then
		return `Slot {slot} is not one of your {Config.Slots.Count} slots.`
	end
	if DataService.GetProfile(player) == nil then
		return "Your save has not finished loading yet. Try again in a moment."
	end
	-- The reason Play and Create are two buttons rather than one that guesses. An empty slot
	-- has no `setup`, and `setup == nil` is what every clock in the game place checks before it
	-- moves -- so teleporting into one would land the player in a world that never starts, with
	-- nothing on screen explaining it. Refusing here is the same rule, enforced one place
	-- earlier and in a sentence.
	if not hasLife(player, slot) then
		return `Slot {slot} is empty. Create a life in it first.`
	end
	local since = inFlight[player]
	if since ~= nil and os.clock() - since < Config.Lobby.TeleportTimeoutSeconds then
		return "Already starting a life -- hold on."
	end
	if RunService:IsStudio() then
		-- Not a failure and not something to hide. Teleports genuinely do not work in Studio,
		-- so a Play button that looks broken here is the expected result and saying so is the
		-- difference between a five-minute check and an afternoon.
		return "Teleporting does not work in Studio. Publish both places and test in-game -- "
			.. "the slot was still selected, so joining the game place directly will open it."
	end
	if Config.Lobby.GamePlaceId == 0 then
		return "This build has no game place id yet. Publish the game place and set "
			.. "Config.Lobby.GamePlaceId to its id."
	end
	return nil
end

-- Retried rather than reported on the first failure, because the common failures here pass
-- on their own. Only the last one is ever shown, and it is always shown.
local function teleport(player: Player): (boolean, string?)
	local lastError: string? = nil
	for attempt = 1, Config.Lobby.TeleportRetries + 1 do
		if player.Parent ~= Players then
			-- They left while we were retrying. Not an error, and firing a refusal at a player
			-- who has gone is a warning in the log for nothing.
			return false, nil
		end
		-- No TeleportOptions. The only two this would carry are a reserved server, which the
		-- game place must not have -- it is a persistent world and a private server per life
		-- would silently empty the town -- and a teleport data payload, which this design
		-- deliberately does not use: which life to open travels in the save.
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(Config.Lobby.GamePlaceId, { player })
		end)
		if ok then
			return true, nil
		end
		lastError = tostring(err)
		if attempt <= Config.Lobby.TeleportRetries then
			task.wait(Config.Lobby.TeleportRetrySeconds)
		end
	end
	return false, lastError
end

function LobbyService.Play(player: Player, slot: number)
	local blocked = blockedBecause(player, slot)
	if blocked ~= nil then
		-- The slot is still selected in Studio, deliberately: the refusal message says so, and
		-- it makes "pick a slot in the lobby, then join the game place by hand" a usable test
		-- path without a second command to run. Gated on the slot being a real, occupied one
		-- rather than on which refusal it was, so neither a nonsense slot number nor an empty
		-- card can be quietly written by the branch that exists to be helpful about a
		-- *different* problem -- pointing `activeSlot` at an empty life is precisely the thing
		-- the check above exists to prevent, and it would be a strange way to prevent it.
		if RunService:IsStudio() and hasLife(player, slot) and DataService.SetActiveSlot(player, slot) then
			LobbyService.Push(player)
		end
		refuse(player, blocked)
		return
	end

	-- Written before the teleport, and this order is the whole handshake. A profile whose
	-- session ends between here and the teleport still saves the new slot, so the worst case
	-- is a player who arrives at the game place on the life they picked without having
	-- travelled -- which is a rejoin away from being right, rather than being wrong.
	if not DataService.SetActiveSlot(player, slot) then
		refuse(player, `Slot {slot} could not be selected. Rejoin and try again.`)
		return
	end
	LobbyService.Push(player)

	inFlight[player] = os.clock()
	local ok, err = teleport(player)
	if ok then
		return
	end
	inFlight[player] = nil
	if err ~= nil then
		warn(`[AGES] lobby: teleport failed for {player.Name} after {Config.Lobby.TeleportRetries + 1} tries -- {err}`)
		refuse(player, "Could not start the game -- Roblox refused the teleport. Try again in a moment.")
	end
end

-- Everything select and delete both have to be true of a slot, or a sentence saying which
-- one is not. Bounds, a loaded save, and no teleport already in the air.
--
-- The in-flight check is the one that is easy to miss and the one that matters most: between
-- `TeleportAsync` returning and the player actually leaving, this server still holds the
-- profile and would happily accept a request to move `activeSlot` somewhere else or empty the
-- slot being travelled to. The player would land in the game place on a life they did not
-- press, or on one that no longer exists.
local function slotActionBlockedBecause(player: Player, slot: number): string?
	if slot ~= math.floor(slot) or slot < 1 or slot > Config.Slots.Count then
		return `Slot {slot} is not one of your {Config.Slots.Count} slots.`
	end
	if DataService.GetProfile(player) == nil then
		return "Your save has not finished loading yet. Try again in a moment."
	end
	local since = inFlight[player]
	if since ~= nil and os.clock() - since < Config.Lobby.TeleportTimeoutSeconds then
		return "A life is already starting -- hold on."
	end
	return nil
end

-- Point the profile at a different card.
--
-- A server-side write rather than a highlight the client remembers, because the selection is
-- what the *game place* reads on arrival -- see `ProfileData.activeSlot`. An empty slot may
-- be selected: selecting is how the player says which card they are looking at, and the card
-- they are looking at is very often the one they are about to fill in.
function LobbyService.Select(player: Player, slot: number)
	local blocked = slotActionBlockedBecause(player, slot)
	if blocked ~= nil then
		refuseSlotAction(player, blocked)
		return
	end
	if not DataService.SetActiveSlot(player, slot) then
		refuseSlotAction(player, `Slot {slot} could not be selected. Rejoin and try again.`)
		return
	end
	LobbyService.Push(player)
end

-- Empty a slot, permanently.
--
-- **The only irreversible thing in this game that is not dying.** The card asks twice before
-- it gets here -- see `Config.Slots.DeleteConfirmSeconds` -- but that second press is a fact
-- about the screen and this function does not attempt to verify it happened. It cannot: any
-- token it could demand is a value the client would be sending itself, so the check would
-- prove nothing while looking like it proved something. What is enforced instead is that the
-- slot is real, that there is something in it, and that no teleport is in the air.
--
-- Replaced with a fresh empty life rather than set to nil, because a nil hole in a Luau array
-- breaks `#` and `ipairs` silently and intermittently. An empty slot is a real LifeData with
-- no `setup`, which is what "no life here" already means everywhere else in this codebase.
function LobbyService.Delete(player: Player, slot: number)
	local blocked = slotActionBlockedBecause(player, slot)
	if blocked ~= nil then
		refuseSlotAction(player, blocked)
		return
	end
	if not hasLife(player, slot) then
		-- Reachable by a second click landing after the first has already emptied the slot, and
		-- the honest answer to "delete this" when there is nothing there is to say so rather
		-- than to report a success that did not happen.
		refuseSlotAction(player, `Slot {slot} is already empty.`)
		return
	end

	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	profile.Data.slots[slot] = Lives.New()

	-- `activeSlot` is deliberately left pointing here if it was. The card stays selected and
	-- becomes an empty one, which is what the player is looking at and what they most likely
	-- want to fill next. Silently jumping the selection to a different life would be the menu
	-- choosing somebody for them at the exact moment they said they wanted nobody.
	LobbyService.Push(player)
end

local function onPlayerAdded(player: Player)
	-- Yields, so the join connection is not held open by it. A profile that never arrives
	-- leaves the cards blank and the Play button refusing with a reason, which is the
	-- correct visible state -- there is nothing else the lobby could honestly do.
	task.spawn(function()
		local profile = DataService.WaitForProfile(player, Config.Lobby.ProfileWaitSeconds)
		if profile == nil or player.Parent ~= Players then
			return
		end
		LobbyService.Push(player)
	end)
end

local function onPlayerRemoving(player: Player)
	inFlight[player] = nil
end

function LobbyService:Init()
	-- Redraw the cards once a life has been created. Handed over rather than required back,
	-- because this file requires LobbySetupService and requiring it the other way would close
	-- a cycle. Registered in Init so it is in place before the first remote can fire.
	LobbySetupService.SetPushHandler(function(player)
		LobbyService.Push(player)
	end)

	RequestPlayRemote.OnServerEvent:Connect(function(player, slot)
		-- Typed off the wire before anything touches it. Every slot number that arrives here was
		-- picked off a list the server sent -- which is exactly the kind of thing that is true
		-- right up until somebody sends a string.
		if typeof(slot) ~= "number" then
			refuse(player, "That is not a slot.")
			return
		end
		LobbyService.Play(player, slot)
	end)

	RequestSelectSlotRemote.OnServerEvent:Connect(function(player, slot)
		if typeof(slot) ~= "number" then
			refuseSlotAction(player, "That is not a slot.")
			return
		end
		LobbyService.Select(player, slot)
	end)

	RequestDeleteSlotRemote.OnServerEvent:Connect(function(player, slot)
		if typeof(slot) ~= "number" then
			refuseSlotAction(player, "That is not a slot.")
			return
		end
		LobbyService.Delete(player, slot)
	end)

	-- A teleport can fail *after* TeleportAsync returned successfully, and this is the only
	-- place that hears about it. Without this the player stands on the stage with a Play
	-- button that has already been pressed, refusing to work for TeleportTimeoutSeconds, with
	-- nothing on screen saying why.
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		inFlight[player] = nil
		warn(`[AGES] lobby: teleport init failed for {player.Name} -- {result.Name}: {message}`)
		refuse(player, "Could not start the game -- the teleport was rejected. Try again in a moment.")
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

function LobbyService:Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return LobbyService
