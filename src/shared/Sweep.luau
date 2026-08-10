--!strict
-- How a timing needle crosses its bar.
--
-- Shared because both ends need the same answer and neither may be the authority
-- alone: the server grades the hit and must decide where the needle really was, and
-- the client draws the needle every frame between the server's ticks. Two copies of
-- these curves would be two curves the moment one was edited, and the symptom would
-- be a bar that visibly disagrees with the grade it produces -- the single worst bug
-- a timing minigame can have, because it teaches the player the game is lying.
--
-- Each shape maps elapsed share of the sweep (0-1) to needle position (0-1). Every
-- shape is pinned at both ends: f(0) = 0 and f(1) = 1. A sweep therefore always
-- starts at the left edge and always expires at the right, whatever it does between
-- them, so "the sweep ran out" means one thing everywhere.
--
-- The gym uses these to make four machines out of one button. Anything else that
-- wants a timing verb -- a sports charge meter, a school rhythm lesson -- should
-- take its curve from here rather than growing a private one.

local Sweep = {}

export type Curve = "steady" | "quickening" | "easing"

-- Constant speed. What you see is what it is doing, and the only machine a new
-- player can read on sight.
local function steady(t: number): number
	return t
end

-- Creeps, then rushes. By the time the needle looks close, the zone is already
-- behind it -- so the bar has to be played by anticipation rather than reaction.
local function quickening(t: number): number
	return t * t
end

-- Rushes, then crawls. Easy to reach and hard to leave: the needle spends most of
-- the sweep near the far end, which makes holding out for a better moment feel free
-- right up to the instant the sweep expires.
local function easing(t: number): number
	return 1 - (1 - t) * (1 - t)
end

-- Named so content and saved data can refer to a curve by string rather than holding a
-- function. Deliberately private: a caller that reaches in for a raw shape would be
-- skipping the clamps in `At`, which is the one place the overshoot from a tick or a
-- frame is absorbed.
local shapes: { [string]: (number) -> number } = {
	steady = steady,
	quickening = quickening,
	easing = easing,
}

-- Needle position for a named curve at an elapsed share.
--
-- Clamps both ways rather than trusting the caller: the share arrives from a tick
-- accumulator on the server and from a RenderStepped accumulator on the client, and
-- either can overshoot by a frame. An unknown curve name is a content error and says
-- so, rather than quietly drawing a straight line that grades differently to the bar
-- the player was looking at.
function Sweep.At(curve: string, elapsedShare: number): number
	local shape = shapes[curve]
	if shape == nil then
		error(`[AGES] unknown sweep curve "{curve}" -- add it to the shapes table in Sweep.luau, or fix the machine that names it`)
	end
	return math.clamp(shape(math.clamp(elapsedShare, 0, 1)), 0, 1)
end

return Sweep
