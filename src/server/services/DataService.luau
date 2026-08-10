--!strict
-- Profile load/save + session locking. Every other service reaches game state through
-- DataService.GetProfile(player) — never directly through DataStoreService.
--
-- Since save slots arrived there are two levels to that, and the distinction matters at
-- every call site. `profile.Data` is the **account**: the slot list, which one is active,
-- how many lives have been lived. `Lives.Active(profile.Data)` is the **life** being played
-- right now, and it is what almost everything actually wants — money, stats, bonds, the
-- job. A service reading a per-life field straight off `profile.Data` is a bug that will
-- type-check, because both are tables and only one of them has the field.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local ProfileStoreModule = require(ServerStorage:WaitForChild("ProfileStore"))

type ProfileData = Types.ProfileData
type LifeData = Types.LifeData
type Gender = Types.Gender

-- The save shape this build writes. Bumped only when a load has to *do* something about
-- the difference, which is rarer than it sounds -- adding a per-life field needs no bump,
-- because `Lives.Reconcile` already fills it.
--
-- 1: one life stored flat on the profile, from before save slots existed.
-- 2: `slots` + `activeSlot`, with the per-life fields moved into slot 1.
local SCHEMA_VERSION = 2

-- A minimal structural view of ProfileStore's generic Profile<T> — only the
-- members this codebase actually touches. Avoids depending on the vendor
-- library's exact generic export shape everywhere Profile is referenced.
type Profile = {
	Data: ProfileData,
	UserIds: { number },
	OnSessionEnd: { Connect: (self: any, listener: () -> ()) -> { Disconnect: (self: any) -> () } },
	IsActive: (self: any) -> boolean,
	Reconcile: (self: any) -> (),
	EndSession: (self: any) -> (),
	AddUserId: (self: any, userId: number) -> (),
}

-- The *account* template. Everything a life is made of moved to `Lives.New()` when save
-- slots arrived; what is left here is the handful of facts that outlive a person.
--
-- `schema` starts at 1 rather than at SCHEMA_VERSION, and that is load-bearing. ProfileStore
-- uses one template for both jobs -- filling a brand new profile and reconciling a stored
-- one -- so there is no value that could mean "new" to one and "old" to the other. Starting
-- at 1 makes every profile, new or stored, take the migration path once; `migrate` is
-- written to be a no-op on a profile with nothing to move, so a first-time player passes
-- through it untouched and comes out stamped at the current version.
--
-- `slots` starts empty rather than holding three fresh lives. A template is deep-copied by
-- ProfileStore, but writing lives here would still put a second definition of "what a new
-- slot looks like" in the codebase beside `Lives.New` -- and the load path has to be able
-- to top up a short list anyway, the day Config.Slots.Count goes up. One code path builds
-- slots, and it is `ensureSlots` below.
local PROFILE_TEMPLATE: ProfileData = {
	schema = 1,
	slots = {},
	activeSlot = 1,
	livesLived = 0,
	-- Spins, perks and receipts all need no `SCHEMA_VERSION` bump and no line in `migrate`
	-- to arrive on a save written before they existed. They are top-level keys, and
	-- ProfileStore's own `Reconcile` -- not `Lives.Reconcile`, the ordinary one this file
	-- calls after every load -- fills in any key missing from a stored profile straight
	-- from this template. Only per-life fields inside `slots` need the explicit pass,
	-- because Reconcile "cannot descend into a list".
	spinsAvailable = 0,
	perks = {},
	processedReceipts = {},
}

local playerStore = ProfileStoreModule.New("PlayerData", PROFILE_TEMPLATE)

local profiles: { [Player]: Profile } = {}

local DataService = {}

-- Move a pre-slots save into slot 1, and stamp the version.
--
-- Runs on every profile exactly once, including brand new ones -- see the note on
-- `schema = 1` in the template. A profile with nothing to move falls straight through the
-- `ageMonths == nil` check and comes out stamped, which is what makes it safe to run
-- unconditionally rather than guarded by a "has this player played before" test that would
-- itself need to be right.
--
-- The legacy read goes through `any` deliberately. Those fields are genuinely not on
-- `ProfileData` any more, so a cast is the honest way to say "this is the old shape" --
-- and keeping a `LegacyProfileData` type around forever to describe a layout nothing writes
-- would be worse: it would look like a thing this build still supports.
local function migrate(data: ProfileData)
	if data.schema >= SCHEMA_VERSION then
		return
	end

	-- Both sides go through an explicit string-keyed map type rather than bare `any`, so the
	-- loops below are iterating something Luau knows the shape of. Casting to `any` and then
	-- iterating it is the kind of thing that type-checks locally and fails at the one moment
	-- it runs, which for a migration is a player's whole save.
	--
	-- The parentheses are load-bearing: Luau allows at most one `::` per expression, so the
	-- chained `a :: any :: T` that reads so naturally is a *syntax* error -- and a syntax error
	-- in this file is not a bug in migration, it is the whole server failing to boot, because
	-- DataService is the first thing both bootstraps require.
	local legacy = (data :: any) :: { [string]: any }

	-- `ageMonths` is the sentinel because every life has one from its first frame, including
	-- a life that never got past the setup menu -- unlike `setup`, `jobId` or `gender`, all
	-- of which are legitimately absent on a save that was never played. Picking one of those
	-- would silently drop the childhood of anyone who quit before choosing a name.
	if legacy.ageMonths ~= nil then
		local moved = Lives.New()
		local target = (moved :: any) :: { [string]: any }
		for key in target do
			local stored = legacy[key]
			if stored ~= nil then
				target[key] = stored
			end
		end
		-- The five `Lives.New` deliberately omits, which the loop above therefore cannot
		-- reach. Absence is their meaning, so they are copied only when actually present.
		for _, key in { "pendingEventId", "deliveringEventId", "jobId", "gender", "setup" } do
			local stored = legacy[key]
			if stored ~= nil then
				target[key] = stored
			end
		end
		data.slots[1] = moved
		data.activeSlot = 1
	end

	-- Cleared whether or not anything moved. A profile carrying both shapes at once is the
	-- one state no reader in this codebase is written to survive, and leaving the originals
	-- behind would mean the next build's migration could run against stale copies.
	for _, key in
		{
			"ageMonths",
			"stage",
			"alive",
			"stats",
			"money",
			"pocketMoneyOwed",
			"pocketMoneyPaidThroughAge",
			"secondsSinceAgeUp",
			"seenEventIds",
			"flags",
			"pendingEventId",
			"deliveringEventId",
			"deliveryCountdown",
			"deliveriesThisYear",
			"jobId",
			"workGameHoursThisYear",
			"jobStanding",
			"lessonsThisYear",
			"bonds",
			"visits",
			"ties",
			"gender",
			"setup",
		}
	do
		legacy[key] = nil
	end

	data.schema = SCHEMA_VERSION
end

-- Bring the slot list up to `Config.Slots.Count` and repair every life in it.
--
-- Both halves matter and neither is optional. The append handles Count going up, so a save
-- written when there were three slots simply gains a fourth. The `Lives.Reconcile` pass is
-- the one that would otherwise bite weeks later: ProfileStore's own Reconcile fills absent
-- keys on the profile but cannot descend into a list, so without this every stored slot
-- would come back missing any per-life field added since it was written.
local function ensureSlots(data: ProfileData)
	for index = 1, Config.Slots.Count do
		local life = data.slots[index]
		if life == nil then
			data.slots[index] = Lives.New()
		else
			Lives.Reconcile(life)
		end
	end

	-- Clamped rather than trusted. The only way this is out of range on a healthy save is a
	-- build where Count came down, and pointing at a slot that is no longer there would fail
	-- inside `Lives.Active` on the first read -- during a join, where it is hardest to
	-- diagnose. Reset to 1 is the one choice that is always a real life.
	if data.activeSlot < 1 or data.activeSlot > Config.Slots.Count then
		data.activeSlot = 1
	end
end

local function onPlayerAdded(player: Player)
	local profile = playerStore:StartSessionAsync(`Player_{player.UserId}`, {})

	if profile == nil then
		player:Kick("Could not load your data (session lock timeout). Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	-- Order is load-bearing: migrate lifts an old flat save into slot 1, then ensureSlots
	-- fills the rest of the list and repairs what migrate just moved. Reversed, the migration
	-- would overwrite a slot that had only just been created and repaired.
	migrate(profile.Data)
	ensureSlots(profile.Data)

	-- Before anything can read it, and before the player is in `profiles` where anything
	-- could. A life that has already started is left exactly as it was -- this only ever
	-- fills the hole Reconcile is unable to, which is a life that has never been lived.
	DataService.EnsureGender(Lives.Active(profile.Data))

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Your data session ended (opened on another server). Please rejoin.")
	end)

	if player.Parent ~= Players then
		-- Player left the game while the session was still starting.
		profile:EndSession()
		return
	end

	profiles[player] = profile
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile ~= nil then
		profile:EndSession()
	end
end

-- Who this life is. Rolls one if the profile does not have one yet, and returns whatever
-- is there if it does.
--
-- Idempotent on purpose and called from two places that both have to be safe to repeat:
-- once when a profile loads, so a brand new player has a gender before anything asks, and
-- once when a life restarts, so the next one is not obliged to be the same person. Neither
-- caller has to know whether the other already ran.
--
-- Unseeded, unlike the town. The town is a fact about the world and has to be identical
-- for everybody; this is a fact about one life and should not be.
--
-- Returns the value rather than nothing so that callers reading it right after do not
-- have to re-narrow an optional field the function just guaranteed.
function DataService.EnsureGender(data: LifeData): Gender
	local existing = data.gender
	if existing ~= nil then
		return existing
	end
	local rolled: Gender = if math.random() < 0.5 then "female" else "male"
	data.gender = rolled
	return rolled
end

-- `RollGenderForNewLife` used to sit here, next to the function above and deliberately apart
-- from it: one is "make sure this is filled in", the other threw away who the player was. It
-- is gone because the only caller was the rebirth in `LifeService.Die`, which wound one life
-- back into another and had to re-roll so that every life after the first was not a
-- continuation of it. Lives do not turn into other lives now -- a new one is a new slot, and
-- the card that fills it is asked which gender it is.

function DataService.GetProfile(player: Player): Profile?
	return profiles[player]
end

-- Point the profile at a different slot.
--
-- Bounds-checked here rather than at the call sites, because `Lives.Active` errors on an
-- out-of-range slot by design and this is the only function that writes the field -- so one
-- check here is the whole guarantee. Returns whether it moved, so a caller can tell "you
-- are now on slot 2" from "2 is not a slot".
--
-- Deliberately does *not* touch the world, the HUD or the running life. It is the lobby
-- that switches slots, and the lobby has no running life to disturb; the game place reads
-- the field on arrival and never changes it. Making this function also tear down a life
-- would be building the game place a capability it must not have.
function DataService.SetActiveSlot(player: Player, slot: number): boolean
	local profile = profiles[player]
	if profile == nil or slot ~= math.floor(slot) or slot < 1 or slot > Config.Slots.Count then
		return false
	end
	profile.Data.activeSlot = slot
	return true
end

-- Yields until the profile finishes loading, or returns nil if the player
-- leaves first. Callers must handle the nil case.
--
-- The timeout is an argument rather than a constant because the two places that call this
-- are waiting on genuinely different things. In the game place a profile is either already
-- loading or the join has gone wrong, and ten seconds is a long time to hold a service up.
-- In the lobby this is the *first* thing that happens to a player and there is nothing
-- behind it to fall back on, so it waits `Config.Lobby.ProfileWaitSeconds`.
function DataService.WaitForProfile(player: Player, timeoutSeconds: number?): Profile?
	local deadline = os.clock() + (timeoutSeconds or 10)
	while profiles[player] == nil and player.Parent == Players and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService:Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

function DataService:Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService
