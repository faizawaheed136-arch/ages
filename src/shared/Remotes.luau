--!strict
-- Single source of truth for remotes. Both server and client require this
-- module; it lazily creates (server) or waits for (client) the RemoteEvent
-- instances so there is never a second place that spells out remote names.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- The `Request` remotes are the only client -> server ones; everything else is a
-- one-way state push. In the game place they carry no payload at all (RequestAgeUp)
-- or only ids, which the server checks against what it actually offered this player
-- — so there is nothing useful to forge. Clicking the dots over somebody's head is
-- not itself sent anywhere: it opens a menu the client was already holding, and only
-- what the player picks off that menu ever leaves this machine.
--
-- The one exception is `RequestCreateLife`, which carries a typed name, and it lives
-- in the *lobby*. That is not a coincidence: free text is the one input that needs a
-- filter and a refusal path, and putting the only screen that takes it in a place with
-- no world running behind it means a name being rejected costs the player nothing.
export type RemoteName =
	"StatsUpdated"
	| "MoneyUpdated"
	| "AgeUpdated"
	| "AgeUpProgress"
	| "LifeStageChanged"
	| "PlayerDied"
	| "RequestAgeUp"
	| "RequestReturnToLobby"
	| "ReturnRefused"
	| "EventOffered"
	| "EventResolved"
	| "RequestEventChoice"
	| "ShiftUpdated"
	| "Notice"
	| "GuideUpdated"
	| "JobPostsUpdated"
	| "TaskUpdated"
	| "LessonUpdated"
	| "PersonUpdated"
	| "RequestPersonOffer"
	| "RequestLessonAnswer"
	-- The two roster remotes. Their prose lives down in `REMOTE_NAMES` rather than being
	-- repeated here, the same as most of the names above them; what matters at this end is
	-- only that they are here at all. They were not, for a while, and the gap is worth a
	-- word because nothing caught it: `REMOTE_NAMES` is annotated `{ RemoteName }`, so a
	-- name in that list and missing from this union is a type error in two places at once
	-- -- the list literal and every `Remotes.Get` that spells it -- and yet the file
	-- compiles, both places build, and the remotes work perfectly at runtime. Only the
	-- analyzer ever objects, which means only Studio ever objects.
	| "PeopleRosterUpdated"
	| "RequestPersonContact"
	| "LobbySlotsUpdated"
	| "LobbySetupOptions"
	| "RequestPlay"
	| "PlayRefused"
	| "RequestSelectSlot"
	| "RequestDeleteSlot"
	| "RequestCreateLife"
	| "SlotActionRefused"
	-- The spins remotes. Live in this list for the same reason the rest of the lobby's do --
	-- one place that spells out remote names -- and the game place pays the same small cost
	-- as it already does for the slot remotes: a handful of RemoteEvents it never fires.
	--
	-- What this player owns and can still buy, pushed whole whenever either changes. Whole
	-- rather than split, on the same reasoning as `LobbySlotsUpdated`: spins and perks are
	-- read off the same page at the same moment, and a spin landing while a perk count is
	-- mid-flight is exactly the kind of out-of-order redraw a single push avoids.
	| "SpinsUpdated"
	-- "Open the purchase prompt for this product." Carries a product id from
	-- `Config.Spins.Products`; the server still bounds-checks it and still refuses a
	-- `productId` of 0, the same as if it had been typed. The grant itself never happens on
	-- this remote -- it happens in `ProcessReceipt`, which Roblox calls back on its own, so a
	-- client cannot claim spins by firing this a second time.
	| "RequestBuySpins"
	-- "Pull." No payload -- what it lands on is decided entirely server-side and pushed back
	-- as part of the next `SpinsUpdated`, so there is nothing on this wire a client could
	-- have forged the result of.
	| "RequestSpin"
	-- Why a spins purchase or a pull did not happen, in a sentence meant for the player.
	--
	-- Its own remote rather than a reuse of `SlotActionRefused`, on the precedent that already
	-- split `PlayRefused` from it: spins are read on a different page, at a different moment,
	-- from a different set of buttons, and a single shared channel would leave the client
	-- guessing which screen a refusal was even about.
	| "SpinActionRefused"
	-- The workout in progress, pushed as a whole snapshot. Its own remote rather than
	-- a field on StatsUpdated, because a workout changes four times a second during
	-- the sweep and the stat bars it moves change once or twice a minute.
	| "WorkoutUpdated"
	-- "Start a workout on this machine." Carries a machine kind string from the
	-- attribute on the part the player is standing next to; the server bounds-
	-- checks it against Config.Gym.Kinds and still refuses a kind it does not
	-- know. The session itself runs entirely server-side after this point.
	| "RequestStartWorkout"
	-- "I pushed." The player clicked the button at the right moment (or the wrong
	-- one). No payload beyond the fact of the click; the server decides quality
	-- from the sweep position it is already tracking, so a client that fires this
	-- twice gains nothing.
	| "RequestRep"

local REMOTE_NAMES: { RemoteName } = {
	"StatsUpdated",
	-- Its own remote rather than a fifth field on StatsUpdated. Money is not a stat
	-- -- it is unbounded, it does not decay, and it moves on different occasions --
	-- and folding it in would mean every stat push carried a balance and every
	-- balance change redrew four bars.
	"MoneyUpdated",
	"AgeUpdated",
	"AgeUpProgress",
	"LifeStageChanged",
	-- A life ending, carrying the age it ended at. There is no `PlayerRespawned` to pair
	-- with it any more, and its absence is the whole of part 3 in one line: a life does not
	-- restart in place. It stays dead in the slot it was lived in, and the player goes back
	-- to the lobby to pick another card. The death screen is therefore the last thing this
	-- place ever says to that life -- nothing takes it down, the place going away does.
	"PlayerDied",
	"RequestAgeUp",
	-- "Take me back to the menu." Pressed off the death screen, and available from the HUD
	-- for a player who simply wants to change life mid-run.
	--
	-- A request rather than the client teleporting itself, because a teleport out is also a
	-- profile handoff: the session in this place has to end cleanly for the lobby to be able
	-- to open the same key, and only the server knows when it has.
	"RequestReturnToLobby",
	-- Why the trip back did not happen. Almost always one of exactly two things -- running
	-- in Studio, where teleports do not work at all, or an unpublished lobby place id -- and
	-- both are sentences a developer needs to read rather than errors a player caused.
	--
	-- Load-bearing for the same reason PlayRefused is: the death screen's only button
	-- silently doing nothing is indistinguishable from the game having hung.
	"ReturnRefused",
	"EventOffered",
	"EventResolved",
	"RequestEventChoice",
	-- The shift in progress, pushed as a whole snapshot. Its own remote rather than
	-- a field on MoneyUpdated for the same reason money is not a fifth stat: a wage
	-- arriving is a balance change, but being three hours into a shift is not, and
	-- folding them together would redraw the shift row every time a letter paid out.
	"ShiftUpdated",
	-- A single sentence for the player, spoken by the server and shown as the same
	-- transient banner the client already raises on an auto age-up. A general channel
	-- rather than a firing-specific remote, because the thing being said -- "you've
	-- been let go" -- is one the server composes and the client only displays: the
	-- client cannot know it was coming, so it cannot draw it off any state it holds.
	-- Carries only the finished string; nothing on this wire is acted on, only read.
	"Notice",
	-- Where the player is being pointed, if anywhere. Sent rather than drawn on the
	-- server because guidance is addressed to exactly one person: most of what this
	-- game puts in the workspace -- a choice pad, a dog, a delivery van -- is meant
	-- to be seen by whoever walks past, and a line to your first job is not.
	"GuideUpdated",
	-- The "NOW HIRING" posts this player should be looking at, as a whole list.
	--
	-- The same argument as GuideUpdated, arrived at the hard way. These were once
	-- built by the server and shared by everyone in the room, which was fine right up
	-- until somebody took the job: the sign and the mark stayed standing over the head
	-- of the one person they were no longer for. An offer has to stop being made once
	-- it is accepted, and only a per-player post can do that.
	"JobPostsUpdated",
	-- What the player is doing this minute, inside the shift they are already on.
	--
	-- Its own remote rather than a field on ShiftUpdated, on the rule that keeps money
	-- and shifts apart: a shift is eight game hours and a wage, and it changes when an
	-- hour completes. A task is a sentence and a countdown, and it changes four times
	-- a second. Folding them together would redraw the whole shift row every tick for
	-- the sake of one number.
	"TaskUpdated",
	-- The question in front of the player, inside the lesson they are already in.
	--
	-- Exactly the same argument as TaskUpdated, which is the point: school and work are
	-- the two things this game asks you to actually do, and they push at the same rate
	-- for the same reason. The answers themselves are not in here -- those are pads on
	-- the floor, built by the server, because an answer you give by walking has to be
	-- somewhere you can walk.
	"LessonUpdated",
	-- Who the player is standing next to, and what they just said back.
	--
	-- The third of the three rows that are pushed rather than drawn, alongside a task and
	-- a lesson, and it is here for the same reason as both: the pads in front of a person
	-- are built by the server, because an offer you take by walking has to be somewhere you
	-- can walk, but what is written on them was decided by reading one profile.
	--
	-- Further than a lesson, in fact. The person themselves is spawned per player rather
	-- than shared: who is around depends on the player's age and what they say depends on
	-- the player's bond, so two players standing in the same kitchen are looking at two
	-- rigs offering two different things. Family is not scenery.
	"PersonUpdated",
	-- What the player picked off the panel in front of somebody, and off the panel in a
	-- lesson. Their own remotes rather than a shared one carrying a kind and an id,
	-- because a person and a lesson are checked against completely different things --
	-- who you are standing next to and their bond, versus which question you are on --
	-- and one handler doing both would be one handler that could confuse them.
	"RequestPersonOffer",
	"RequestLessonAnswer",
	-- The people the player has met, as a whole list for the HUD's people section.
	--
	-- Distinct from PersonUpdated in the way a whole list is always distinct from a
	-- single row: PersonUpdated names who is standing next to you and what they will
	-- say; this names everyone whose name you know, whether or not they are near. The
	-- HUD's avatars are built from it, and the list is why tapping an avatar is a
	-- conversation rather than a guess — the server sent the person's name and face,
	-- and the tap only carries their id.
	"PeopleRosterUpdated",
	-- "I tapped this avatar, open the conversation." Carries a person id, checked
	-- against the roster the server sent, and the conversation itself is answered by
	-- the same PersonUpdated push a proximity approach already raises.
	"RequestPersonContact",
	-- The lobby remotes. They live in this list rather than a `LobbyRemotes` module of
	-- their own for the reason at the top of the file -- one place that spells out remote
	-- names -- and the cost is that each place creates a handful of RemoteEvents it never
	-- fires. A few unused instances is a smaller price than two files that can disagree
	-- about a string.
	--
	-- Every slot the player owns, as a whole list, whenever any of it changes. A whole
	-- list rather than a per-slot push because the menu is three cards read side by side:
	-- there is no moment where one card is meaningfully newer than the others, and a
	-- per-slot remote would let a delete and a rebuild land out of order and leave a card
	-- showing a life that no longer exists.
	"LobbySlotsUpdated",
	-- "Choose who you are about to be", carrying everything the create page needs to draw
	-- itself. Sent rather than the client reading Config, because these are the exact
	-- numbers the server is about to validate the answer against -- so a page physically
	-- cannot offer a spend that will then be refused.
	--
	-- Its own remote rather than a field on LobbySlotsUpdated, even though both are pushed
	-- on load. Slots change every time a card is touched; the options change only when a
	-- life *ends*, which happens in the other place entirely. Folding them together would
	-- resend the full country list on every delete.
	--
	-- The client holds the Create button disabled until this arrives, rather than opening a
	-- page with empty steppers on it. There is no honest thing to draw before it lands.
	"LobbySetupOptions",
	-- "Start this slot." Carries the slot number, which the server bounds-checks against
	-- Config.Slots.Count exactly as if it had been typed -- the client picked it off a
	-- list the server sent, but the client is still the client.
	"RequestPlay",
	-- Why Play did not happen, in a sentence meant for the player. The accepted path
	-- already announces itself by teleporting you, so the only outcome needing words is
	-- the one that did not.
	--
	-- Kept apart from SlotActionRefused below, which is the one distinction between these
	-- two refusal channels that is worth a remote: everything on the cards is instant and
	-- local, and Play is a slow call to another server that can fail *after* the screen has
	-- already gone busy. They are read in different places on screen and at different
	-- moments, so a single remote would have the client guessing which one it just got.
	--
	-- Load-bearing, because the most likely refusal here is not the player's fault at all
	-- -- an unpublished place id, a teleport rate limit, a profile that has not loaded yet.
	-- A Play button that silently does nothing is indistinguishable from a frozen game.
	"PlayRefused",
	-- "Make this card the one Play uses." Carries a slot number and nothing else.
	--
	-- A remote at all, rather than the client remembering which card is highlighted and
	-- telling the server only at Play time, because the choice is *persisted* -- it is
	-- written to `activeSlot` on the profile, which is how the game place learns which life
	-- to run. See ProfileData.activeSlot: that field is deliberately not something a
	-- teleport payload can assert.
	"RequestSelectSlot",
	-- "Delete the life in this slot." The only irreversible thing in this game that is not
	-- dying, so the card asks twice before it fires -- but the second press is a fact about
	-- the *screen*, not about the wire, and the server does not attempt to verify that it
	-- happened. It cannot: any check it could make is a value the client would be sending
	-- itself. What the server does enforce is that the slot is real, that something is in
	-- it, and that it is not the slot currently mid-teleport.
	"RequestDeleteSlot",
	-- The answer to the create page: a slot number and the life to put in it.
	--
	-- The only remote in the game that carries free text -- a name the player typed, which
	-- goes through TextService before it is stored and is refused outright if the filter
	-- cannot be reached.
	"RequestCreateLife",
	-- Why a card action was not accepted, in a sentence meant to be read by the player
	-- rather than by a log. Shared by select, delete and create because all three are
	-- answered in the same instant and read on the same line under the cards.
	--
	-- A sentence rather than a code, and a refusal rather than an acceptance flag: the
	-- accepted path already has a message -- the cards redrawing -- and a boolean that is
	-- false only on failure is a sentence with nowhere to put the reason.
	"SlotActionRefused",
	"SpinsUpdated",
	"RequestBuySpins",
	"RequestSpin",
	"SpinActionRefused",
	"WorkoutUpdated",
	"RequestStartWorkout",
	"RequestRep",
}

local FOLDER_NAME = "RemoteEvents"

local Remotes = {}

local function getFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		return existing :: Folder
	end

	if RunService:IsServer() then
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		for _, name in REMOTE_NAMES do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		folder.Parent = ReplicatedStorage
		return folder
	end

	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Remotes.Get(name: RemoteName): RemoteEvent
	local folder = getFolder()
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
