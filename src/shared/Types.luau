--!strict
-- Shared Luau type definitions. Pure types, no runtime content.

local Types = {}

export type StatName = "health" | "happiness" | "smarts" | "looks"

export type Stats = {
	health: number,
	happiness: number,
	smarts: number,
	looks: number,
}

export type LifeStageId = "Childhood" | "Adolescence" | "Adulthood" | "Elder" | "Death"

-- Why a year ended. The client only announces "Auto" — the others are either
-- the player's own doing or a silent state resync on join/respawn. "Skip" marks
-- the years crossed by Skip Childhood, which pass without offering an event.
-- "Event" is a childhood year ended by answering its event: silent, because the
-- outcome the player is already reading is the announcement.
export type AgeUpCause = "Manual" | "Auto" | "Sync" | "Skip" | "Event"

-- Server's verdict on the Age Up button, so the HUD never invents its own
-- gating rule: Hidden (dead, or a first life still in childhood), Cooldown
-- (too soon), Ready, SkipChildhood (offered instead of Ready before the manual
-- age, once the player has already lived childhood at least once).
export type ManualAgeUpState = "Hidden" | "Cooldown" | "Ready" | "SkipChildhood"

-- A partial map: a choice names only the stats it moves.
export type StatDelta = { [StatName]: number }

-- One rung of the childhood body ladder. Matched by the first band whose maxAge
-- the player's age falls under, so Config.Childhood.Bands must stay sorted.
export type ChildhoodBand = {
	id: string,
	maxAge: number,
	walkSpeed: number,
	jumpPower: number,
	bodyScale: number,
	headScale: number,
	cameraOffsetY: number,
}

-- How an event reaches the player. The engine decides *which* event fires;
-- delivery decides *how*, and the two are kept separate so a mode can be added
-- here without touching content or selection logic.
--
-- Memory is how childhood reads until the toddler world exists. Once it does,
-- those entries move to Interact and only this field changes on them. Interact
-- means the player reached the event by walking to a tagged object rather than
-- having it handed to them.
--
-- Letter, PhoneCall and NPCApproach are the world coming to *you*: something is
-- staged in the house and the prompt only opens once you go to it. Which route
-- each mode takes -- and therefore which system is allowed to pick it -- lives
-- in Delivery.luau, so no system has to hardcode the list.
export type EventDelivery = "Memory" | "Direct" | "Interact" | "Letter" | "PhoneCall" | "NPCApproach"

-- How an event is *answered*, which is a separate question from how it reached
-- the player. A Panel event is read and clicked. An Enacted one puts its choices
-- in the room as places to stand, and you answer it by walking to one -- the
-- prompt stays on screen as a banner and the world stays live behind it.
--
-- The two axes are independent on purpose: a letter can be read off a panel or
-- walked away from, and which it is should be a content decision rather than a
-- consequence of how the letter arrived.
--
-- Enacted is always a *request*. If the room cannot hold the markers -- no floor,
-- a wall in the way, furniture where a choice would have to stand -- the event
-- falls back to a panel rather than becoming unanswerable. That means the field
-- is never a guarantee and no caller may treat it as one.
export type EventResolution = "Panel" | "Enacted"

-- One person the world can send to your door. Built from body scales and colors
-- rather than from a catalog bundle on purpose: those need no asset ids at all,
-- so the cast exists and reads as a person before a single id has been picked in
-- Studio. The id fields are polish layered on top, and 0 means "not chosen yet"
-- because that is what HumanoidDescription itself uses for an empty slot.
--
-- The cast is fixed rather than randomized so that the neighbor who turns up at
-- nine is the same neighbor at forty. That continuity is the whole reason these
-- are authored people instead of generated ones.
export type CastMember = {
	id: string,
	-- Shown over their head. Kept out of the event text so a line can be reused
	-- by a different visitor without being rewritten.
	name: string,
	skinColor: Color3,
	heightScale: number,
	widthScale: number,
	headScale: number,
	proportionScale: number,
	bodyTypeScale: number,
	shirtAssetId: number,
	pantsAssetId: number,
	hairAssetId: number,
}

-- What a staged delivery actually put in the world. `anchor` is the thing the
-- player has to reach, and it may move -- a visitor's is their own root part, so
-- reaching them means reaching where they now are rather than where they came
-- in. `dismiss` owns *all* teardown including the anchor, which is what lets a
-- presentation end gracefully instead of blinking out of existence.
export type DeliveryPresentation = {
	anchor: BasePart,
	-- `collected` distinguishes the player arriving from the delivery giving up,
	-- because those two endings should not look the same.
	dismiss: (collected: boolean) -> (),
}

export type EventChoice = {
	id: string,
	label: string,
	-- Shown after the choice is made. Second person, past tense.
	outcome: string,
	effects: StatDelta,
}

export type LifeEvent = {
	id: string,
	minAge: number,
	maxAge: number,
	delivery: EventDelivery,
	prompt: string,
	choices: { EventChoice },
	-- How the player answers. Nil means "Panel", so an event written before
	-- enactment existed keeps behaving exactly as it did.
	resolution: EventResolution?,
	-- Relative selection weight among eligible events. Defaults to 1.
	weight: number?,
	-- For NPCApproach events, which member of the cast turns up. Ignored by every
	-- other delivery. Nil is allowed and falls back to the first cast member, so
	-- writing a visitor event is never blocked on casting it -- but an id that
	-- doesn't exist is a content error and throws at start.
	cast: string?,
}

-- What the client is told about an offered event. Effects and outcome lines are
-- withheld until a choice is made, so the answer can't be read off the payload.
export type OfferedEvent = {
	id: string,
	delivery: EventDelivery,
	prompt: string,
	choices: { { id: string, label: string } },
	-- What the *server actually did*, not what the content asked for. An event
	-- authored Enacted arrives here as "Panel" whenever the markers could not be
	-- placed, so the client renders what exists rather than what was intended and
	-- a fallback needs no second message to announce itself.
	resolution: EventResolution,
}

export type ProfileData = {
	ageMonths: number,
	stage: LifeStageId,
	alive: boolean,
	stats: Stats,
	livesLived: number,
	-- Active in-server seconds banked since the last age-up. Persisted so a
	-- player who leaves mid-year resumes their progress instead of restarting it.
	secondsSinceAgeUp: number,
	-- Events already answered in the *current* life, so a year can't repeat one.
	-- Cleared on respawn: living the same moment again in a new life is fine.
	seenEventIds: { [string]: boolean },
	-- The event offered but not yet answered. Persisted so it survives a rejoin,
	-- and so re-joining can't be used to reroll an unwanted prompt.
	pendingEventId: string?,
	-- The event picked and physically placed in the world but not yet reached:
	-- a letter on the mat, a phone ringing in the hall. Deliberately a separate
	-- field from pendingEventId rather than a flag on it, because the two mean
	-- different things to every check that reads them -- "there is something to
	-- find" versus "there is a question open". Persisted, so the letter is still
	-- on the mat after a rejoin instead of vanishing with the session that
	-- staged it.
	deliveringEventId: string?,
	-- Real seconds until the ambient scheduler next tries to stage something.
	-- Counts down only while the player is in a server, so logging out neither
	-- banks quiet time nor resets it. Reset to a fresh random gap after each
	-- staging, which is what keeps ambient events from arriving on a metronome.
	deliveryCountdown: number,
	-- Ambient deliveries staged in the current year, against Ambient.MaxPerYear.
	-- Without this a player who lingers in one year would be buried in mail.
	deliveriesThisYear: number,
}

return Types
