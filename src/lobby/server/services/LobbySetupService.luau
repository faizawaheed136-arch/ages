--!strict
-- Where a life is made. The lobby's half of character creation: hand the client the rules,
-- check what comes back against them, and write a person into an empty slot.
--
-- **This used to live in the game place, and moving it is the point of part 3.** A card
-- drawn over a running world is a card the world has to be stopped for -- every clock in the
-- game checked `setup == nil` before it moved, so the menu was not a screen over the world,
-- it was the world refusing to start. That works, and it means the first thing a new player
-- ever sees is a form floating in a town they cannot touch. Here there is no world behind it
-- to hold still: the lobby is a stage and a backdrop, the cards are the only thing on it, and
-- pressing Create fills a card rather than unfreezing a place.
--
-- The rules themselves are in `shared.LifeSetup`, required by both places. This file is the
-- part that needs a player and a profile: the filter call, the slot bounds, and the write.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local DataService = require(script.Parent.Parent.shared.DataService)
local LifeSetup = require(script.Parent.Parent.shared.LifeSetup)
local Perks = require(script.Parent.Parent.content.Perks)

type LifeData = Types.LifeData
type Gender = Types.Gender

local SetupOptionsRemote = Remotes.Get("LobbySetupOptions")
local RequestCreateLifeRemote = Remotes.Get("RequestCreateLife")
local SlotActionRefusedRemote = Remotes.Get("SlotActionRefused")

local LobbySetupService = {}

-- Handed over rather than required, because LobbyService already requires nothing from this
-- file and requiring it back would close a cycle. The same device the game place uses for
-- LifeService's begin handler. What it does: redraw the cards, which is the only visible
-- result of a life being created.
type PushHandler = (player: Player) -> ()
local pushHandler: PushHandler? = nil

function LobbySetupService.SetPushHandler(handler: PushHandler)
	pushHandler = handler
end

local function refuse(player: Player, reason: string)
	SlotActionRefusedRemote:FireClient(player, reason)
end

-- The numbers the create page draws itself from, which are the numbers this file is about to
-- validate against. Sent once the profile is up, because `lifeNumber` is read off it.
function LobbySetupService.PushOptions(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	SetupOptionsRemote:FireClient(player, LifeSetup.Options(profile.Data.livesLived))
end

-- Whether a slot is a real, empty one to build in, or a sentence saying why not.
--
-- Separate from the write below and called twice -- once before the filter call and once
-- after it -- because the filter yields, and everything it checks can change across a yield.
-- Two lives created from two fast clicks would otherwise both find the slot empty on the way
-- in and both write to it on the way out.
local function slotBlockedBecause(player: Player, slot: number): string?
	if typeof(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > Config.Slots.Count then
		return `Slot {slot} is not one of your {Config.Slots.Count} slots.`
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "Your save has not finished loading yet. Try again in a moment."
	end
	local life = profile.Data.slots[slot]
	if life == nil then
		-- Unreachable while `Lives.Reconcile` fills every slot on load, and a refusal rather
		-- than a crash because the lobby is the one place in this game with nothing behind it
		-- to fall back to.
		return `Slot {slot} is missing from your save. Rejoin and try again.`
	end
	if Lives.HasBegun(life) then
		-- The only route to a slot that is already full is a client that skipped the card's own
		-- check, or a second click landing after the first one wrote. Either way the answer is
		-- the same, and it is not "overwrite the life that is there".
		return `Slot {slot} already has a life in it. Delete it before starting a new one.`
	end
	return nil
end

-- Whether this player may spend this perk right now, or a sentence saying why not.
--
-- `nil` perkId -- no perk chosen, the ordinary path -- is always allowed. Checked twice for
-- the same reason `slotBlockedBecause` is: the filter call yields, and a second create request
-- landing during that yield could spend the last copy of a perk out from under the first.
local function perkBlockedBecause(player: Player, perkId: string?): string?
	if perkId == nil then
		return nil
	end
	if Perks.ById[perkId] == nil then
		return "That perk doesn't exist."
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "Your save has not finished loading yet. Try again in a moment."
	end
	local owned = profile.Data.perks[perkId] or 0
	if owned <= 0 then
		return "You don't have that perk to spend."
	end
	return nil
end

-- Write the person down.
--
-- Everything is decided before anything is written, on the codebase's idempotency rule: a
-- refusal at any point above leaves an empty slot rather than one holding half an identity.
-- The whole life is replaced rather than patched, so a slot that was deleted and rebuilt
-- cannot carry a single field over from whoever was in it before.
local function commit(
	player: Player,
	slot: number,
	gender: Gender,
	setup: Types.LifeSetup,
	deltas: { [string]: number },
	perkId: string?
)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end

	local life = Lives.New()
	life.gender = gender
	life.setup = setup
	-- Written straight onto the life rather than through a StatService, because there is no
	-- StatService here and there should not be: this is not a stat *changing*, it is the value
	-- a stat starts at. `LifeSetup.StartingStats` applies the same clamp StatService would.
	life.stats = LifeSetup.StartingStats(deltas)

	-- Applied after the base stats and money exist to be added to, and spent -- the count
	-- decremented -- only once `Perks.Apply` has actually returned true. A perk that failed to
	-- apply for a reason `perkBlockedBecause` could not see (content pulled between the check
	-- and here) is a perk the player keeps rather than one silently burned for nothing.
	if perkId ~= nil then
		local owned = profile.Data.perks[perkId] or 0
		if owned > 0 and Perks.Apply(life, perkId) then
			profile.Data.perks[perkId] = owned - 1
		end
	end

	profile.Data.slots[slot] = life

	-- Creating a life selects it. The alternative -- create it and leave the selection where it
	-- was -- means the most likely next press, Play, opens somebody else. There is no reading
	-- of "I just made this person" under which that is what the player meant.
	DataService.SetActiveSlot(player, slot)

	local handler = pushHandler
	if handler == nil then
		-- Unreachable once LobbyService has run its Init, and a warn rather than a silent return
		-- because the symptom -- a Create button that appears to do nothing while the life it
		-- made sits in the save -- is one nobody would think to trace back to a missing handler.
		warn(`[AGES] lobby: created a life for {player.Name} with no push handler registered; the cards will not redraw`)
		return
	end
	handler(player)
end

-- The whole create path, from an untrusted payload to a life on the profile.
--
-- Public rather than a local wired straight to the remote, so the debug harness can drive the
-- real thing with a rolled payload instead of a second, shorter version of it that would be
-- free to disagree about what a valid life is. It takes `any` for both arguments precisely
-- because that is what the wire gives it: a caller that already has a well-typed request is
-- still checked by the same code the wire is.
function LobbySetupService.Create(player: Player, slot: any, payload: any)
	-- Typed off the wire before anything touches it. The client picked this number off a list
	-- the server sent, which is true right up until somebody sends a string.
	if typeof(slot) ~= "number" then
		refuse(player, "That is not a slot.")
		return
	end

	local blocked = slotBlockedBecause(player, slot)
	if blocked ~= nil then
		refuse(player, blocked)
		return
	end

	local request, reason = LifeSetup.Parse(payload)
	if request == nil then
		refuse(player, reason or "That didn't work. Try again.")
		return
	end

	-- Optional, and read off the raw payload rather than folded into `LifeSetup.Parse` /
	-- `SetupRequest`. `LifeSetup` is mapped into the game place too -- see CLAUDE.md -- and a
	-- perk is lobby-only content that file has no business knowing about; "which perk, if any"
	-- is a question this service answers on its own, the same way it answers "which slot".
	local perkId: string? = nil
	if typeof(payload) == "table" then
		local rawPerkId = (payload :: { perkId: any }).perkId
		if rawPerkId ~= nil then
			if typeof(rawPerkId) ~= "string" then
				refuse(player, "That perk couldn't be read.")
				return
			end
			perkId = rawPerkId
		end
	end
	local perkBlocked = perkBlockedBecause(player, perkId)
	if perkBlocked ~= nil then
		refuse(player, perkBlocked)
		return
	end

	-- Yields. Everything above this point is cheap and synchronous on purpose: the filter is
	-- the only slow step, so it runs once, last, on input that is already known to be shaped
	-- like a name.
	local firstName = LifeSetup.FilterName(player, request.firstName)
	local lastName = LifeSetup.FilterName(player, request.lastName)
	if firstName == nil or lastName == nil then
		refuse(player, "That name couldn't be checked. Try a different one, or press Shuffle.")
		return
	end

	-- Re-checked after the yield. The player can have left, rejoined, or -- with two fast
	-- requests in flight -- already filled this slot, or already spent this perk, while the
	-- filter was in the air, and the second request through must not overwrite the first or
	-- spend the same copy twice. Silence rather than a refusal in the double-click case would
	-- be kinder, but this path cannot tell a double-click from a genuine collision, and a
	-- sentence naming what blocked it is honest about both.
	if player.Parent ~= Players then
		return
	end
	local stillBlocked = slotBlockedBecause(player, slot)
	if stillBlocked ~= nil then
		refuse(player, stillBlocked)
		return
	end
	local perkStillBlocked = perkBlockedBecause(player, perkId)
	if perkStillBlocked ~= nil then
		refuse(player, perkStillBlocked)
		return
	end

	commit(player, slot, request.gender, {
		firstName = firstName,
		lastName = lastName,
		countryId = request.countryId,
		eraId = request.eraId,
	}, request.statDeltas, perkId)
end

local function onPlayerAdded(player: Player)
	-- Its own wait rather than a call from LobbyService's, so that each service owns the push
	-- it is responsible for. The two waits resolve off the same already-loading profile; the
	-- second one costs a table lookup.
	task.spawn(function()
		local profile = DataService.WaitForProfile(player, Config.Lobby.ProfileWaitSeconds)
		if profile == nil or player.Parent ~= Players then
			return
		end
		LobbySetupService.PushOptions(player)
	end)
end

function LobbySetupService:Init()
	-- Checked once at boot rather than discovered when the first player presses Create on a
	-- card with no pickable era on it.
	LifeSetup.AssertPlayable()

	RequestCreateLifeRemote.OnServerEvent:Connect(function(player: Player, slot: any, payload: any)
		LobbySetupService.Create(player, slot, payload)
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
end

function LobbySetupService:Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return LobbySetupService
