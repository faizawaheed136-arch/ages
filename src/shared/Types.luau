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
-- delivery decides *how*, and the two are kept separate so the world-based
-- modes arriving with step 3 (NPCApproach / Letter / PhoneCall / Location) can
-- be added here without touching content or selection logic.
--
-- Memory is deliberately permanent rather than a placeholder: a toddler has no
-- world to walk around, so early childhood is presented as a first-person
-- recollection no matter what the rest of the game grows into.
export type EventDelivery = "Memory" | "Direct"

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
	-- Relative selection weight among eligible events. Defaults to 1.
	weight: number?,
}

-- What the client is told about an offered event. Effects and outcome lines are
-- withheld until a choice is made, so the answer can't be read off the payload.
export type OfferedEvent = {
	id: string,
	delivery: EventDelivery,
	prompt: string,
	choices: { { id: string, label: string } },
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
}

return Types
