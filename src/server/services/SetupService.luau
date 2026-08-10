--!strict
-- What this place does about a life having been chosen somewhere else.
--
-- **This file used to be the character menu, and part 3 moved it out.** It built the options
-- payload, validated an answer, filtered a typed name and wrote the life -- drawn as a card
-- over a town that was standing still, because `LifeData.setup` being absent is what every
-- clock in this game checks before it moves. The menu was not a screen over the world; it
-- was the world refusing to start.
--
-- All of that now lives in the lobby, where there is no world behind it to hold still. See
-- `lobby/server/services/LobbySetupService.luau` for the half that needs a player, and
-- `content/LifeSetup.luau` for the rules themselves, which are one file required by both
-- places so that a card in the lobby and a name in the game cannot disagree.
--
-- What is left here is the three things that only make sense on this side:
--
--   * `SetBeginHandler` / the begin path -- what runs the instant a life starts.
--   * `Skip` -- the debug harness answering the card that is not here, so a test of school
--     or a job does not have to be started by teleporting through a menu.
--   * `NameOf` / `CountryOf` -- reading a life that has already been chosen, which half the
--     services in this place do when they put somebody's name in a sentence.
--
-- Note what is *not* here any more: `Ask`. There is nothing to ask. A player who arrives
-- with no life in their slot is not shown a menu, they are sent back to the one that exists
-- -- see ReturnService, which is the other half of this change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)
local StatService = require(script.Parent.StatService)
local LifeSetup = require(script.Parent.Parent.content.LifeSetup)

type LifeData = Types.LifeData
type Gender = Types.Gender
type Country = Types.Country
type LifeSetupData = Types.LifeSetup

local SetupService = {}

-- Handed over rather than required, because LifeService requires this module and requiring
-- it back would close a cycle. The same device LifeService already uses for EventService's
-- age-up handler.
type BeginHandler = (player: Player) -> ()
local beginHandler: BeginHandler? = nil

-- What to run once a life is under way: push the opening state and offer the first event of
-- age zero. Owned by LifeService because it is the same work a rebirth used to do inline.
function SetupService.SetBeginHandler(handler: BeginHandler)
	beginHandler = handler
end

-- Write the life down and start it.
--
-- Reduced to one caller -- `Skip` -- and kept as its own function anyway, because the two
-- things it does are in an order that matters and the order is not obvious: the setup is
-- written before the stats are applied, because StatService pushes to the client and the
-- client is about to raise a HUD.
local function commit(player: Player, data: LifeData, gender: Gender, setup: LifeSetupData, deltas: { [string]: number }?)
	data.gender = gender
	data.setup = setup

	if deltas ~= nil then
		for _, statName in LifeSetup.StatOrder do
			local delta = deltas[statName] or 0
			if delta ~= 0 then
				StatService.AddStat(player, statName, delta)
			end
		end
	end

	local handler = beginHandler
	if handler == nil then
		-- Unreachable once LifeService has run its Init, and a warn rather than a silent
		-- return because the symptom -- a life that exists on the profile but in which nothing
		-- ever happens -- is one nobody would think to trace back to a missing handler.
		warn(`[AGES] {player.Name} began a life with no begin handler registered; the life will not start`)
		return
	end
	handler(player)
end

-- What the game calls this life, for anywhere a life needs naming. Falls back to the
-- player's Roblox name rather than to an empty string, because every caller of this is
-- putting it in a sentence.
--
-- A pass-through to `LifeSetup` rather than a second implementation. It stays on this module
-- because a dozen services in this place already call `SetupService.NameOf` and none of them
-- has any business knowing which of two places defined the rule.
function SetupService.NameOf(data: LifeData, fallback: string): string
	return LifeSetup.NameOf(data, fallback)
end

-- The country this life began in, or nil if it has not begun.
function SetupService.CountryOf(data: LifeData): Country?
	return LifeSetup.CountryOf(data)
end

-- Start a rolled life in the slot the player arrived on, without the lobby.
--
-- The debug path for everything that lives *after* setup: a test of school or a job should
-- not have to be reached by teleporting out to the menu and filling in a card, and in Studio
-- -- where teleports do not work at all -- there is no menu to reach. This is the command
-- that makes the game place testable on its own.
--
-- Goes through `commit` rather than writing the profile itself, so the one thing a harness
-- must never do -- start a life by a route a player could not take -- stays structurally
-- impossible. Returns what it rolled, or nil if there was nothing to answer, which is what
-- the command prints.
--
-- `force` discards whatever is in the active slot first, begun or not, alive or dead. It
-- exists because a life left in the active slot is otherwise a dead end in *this* place:
-- plain skip refuses an occupied slot, `/slots delete` refuses the active one, and rebirth
-- in place is gone -- so a test session that ran a life to death, or that carried one over
-- from an earlier Studio run (API-backed saves persist across runs), had no way back to a
-- fresh body without teleporting out to the lobby. This is that way back, and it is debug
-- only. A brand new life goes through `Lives.New`, so it starts at age zero -- which is what
-- puts a body back to a crawler and the HUD back to a childhood.
function SetupService.Skip(player: Player, force: boolean?): LifeSetupData?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	local data = Lives.Active(profile.Data)
	if Lives.HasBegun(data) then
		if not force then
			return nil
		end
		-- Overwrite the slot rather than mutate the life in place: a fresh `Lives.New` is the
		-- one definition of a clean slot, and reaching into the old life to reset field by
		-- field would be a second, drifting copy of it.
		local fresh = Lives.New()
		profile.Data.slots[profile.Data.activeSlot] = fresh
		data = fresh
	end
	-- Already filled in by DataService on load; read rather than rolled, so a skipped setup
	-- keeps whoever the profile already said this life was. A forced restart rolls a new one,
	-- because `fresh.gender` is nil and EnsureGender fills it -- a restarted life is not
	-- obliged to be the same person the discarded one was.
	local gender = DataService.EnsureGender(data)
	local setup = LifeSetup.Roll(gender)
	commit(player, data, gender, setup)
	return setup
end

function SetupService:Init()
	-- Checked once at boot rather than discovered when `/setup skip` rolls a life into an era
	-- that is not playable. The lobby runs the same assertion for the same reason; both places
	-- read the same list, and a list with nothing pickable in it is a build nobody can play.
	LifeSetup.AssertPlayable()
end

return SetupService
