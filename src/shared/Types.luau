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
-- the player's own doing or a silent state resync on join/respawn.
export type AgeUpCause = "Manual" | "Auto" | "Sync"

-- Server's verdict on the Age Up button, so the HUD never invents its own
-- gating rule: Hidden (dead, or still a child), Cooldown (too soon), Ready.
export type ManualAgeUpState = "Hidden" | "Cooldown" | "Ready"

export type ProfileData = {
	ageMonths: number,
	stage: LifeStageId,
	alive: boolean,
	stats: Stats,
	livesLived: number,
	-- Active in-server seconds banked since the last age-up. Persisted so a
	-- player who leaves mid-year resumes their progress instead of restarting it.
	secondsSinceAgeUp: number,
}

return Types
