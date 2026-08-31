--!strict
-- Gym tuning: what counts as a session, and which animation plays for what.
--
-- Shared so a client-side rep counter can read the same targets the server enforces. The server
-- is still the one counting -- this table is numbers, not authority.

export type Station = "bag" | "bench"

local Workout = {}

-- **Replace these.** Until they are real ids the equipment works, the bag swings and the reps
-- count -- the avatar simply does not move. That is the failure mode to expect, and it looks
-- exactly like the animation system being broken.
Workout.Animations = {
	-- One strike. Priority must be Action or higher or the walk cycle wins.
	Strike = "rbxassetid://0",
	-- Looped. Holds the character flat on the bench; this is what overrides the seat's own pose.
	BenchIdle = "rbxassetid://0",
	-- One press. Its length is what the barbell travel is synced to.
	BenchPress = "rbxassetid://0",
}

-- How much work is a session. Reached on either station, counted per player, reset on
-- completion -- so a session is a thing you finish rather than a total you accumulate forever.
Workout.StrikesPerSession = 12
Workout.RepsPerSession = 8

-- Per-player, per-station cooldown. 0.45 is a little under the strike animation, so a player
-- hammering the prompt gets a continuous sequence rather than a stutter of restarts.
Workout.StrikeCooldown = 0.45
Workout.RepCooldown = 1.2

-- How long the aura lasts once earned.
Workout.AuraSeconds = 18

-- The bag. Impulse is in stud-mass-per-second; this is tuned against a bag of roughly 900 mass
-- and wants retuning if you change the bag's size or density.
Workout.StrikeImpulse = 2400
Workout.BarbellTravel = 1.6

return Workout
