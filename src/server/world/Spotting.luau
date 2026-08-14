--!strict
-- Being noticed. One definition, for everybody in town who might look up.
--
-- Before this there were two, and they did not agree about anything. An officer saw you the
-- instant you crossed a distance line -- a boolean, no build-up, no warning. A passer-by
-- needed a flat 2.2 seconds and did not care who you were or what you were doing. Neither
-- asked the question the whole chase is built on, which is *how much do you stand out right
-- now*, and the consequence was that the single most important number in the crime system --
-- the bounty on your head -- had no effect whatsoever on how easily you were found. It
-- bought more officers and longer sight lines, and that was all.
--
-- So there was nothing to *do* about being wanted except be somewhere else. Every other
-- system in this game gives the player a dial; this one gave them a wall.
--
-- What this module is: two halves that were always going to be needed together.
--
--   **Can they see you at all** -- distance, then a ray. Unchanged in behaviour from the
--   check PoliceService already had, and lifted here so that the crowd, the police and
--   (next) the gangs cannot drift apart on what "in view" means. The day somebody tunes
--   one of those must not be the day the other two quietly change.
--
--   **How fast that turns into being spotted** -- which is new, and is the system. An
--   observer fills a `notice` from 0 to 1 while they have you, at a rate set by how
--   conspicuous you are. At 1 they have made you. Below 1 nothing has happened yet, and
--   that gap is the entire point: it is room to walk out of.
--
-- Notice is not held here. It belongs to the observer -- one officer's opinion, one
-- pedestrian's -- and every caller already has a per-observer table to keep it in. A module
-- that owned it would need to know who all the observers are, which is the one thing it has
-- no business knowing.
--
-- **Notice resets when line of sight breaks. It does not decay.** That is deliberate and it
-- is load-bearing: it is what makes ducking behind a van a *move* rather than a pause, and
-- it is the rule WitnessService was already written around. A decay would turn every piece
-- of cover in the town into a slightly slower version of standing in the open.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Ground = require(script.Parent.Ground)

local Spotting = {}

local SPOT = Config.Crime.Spotting

-- What makes a person worth noticing. Every field is something the player can change,
-- which is the test a term has to pass to be in here at all: a conspicuousness made of
-- things outside the player's control would be a difficulty number wearing a system's
-- clothes.
export type Factors = {
	-- How wanted you are, as a share of the cap. The headline term.
	heatShare: number,
	-- How fast you are actually moving, in studs per second. Not what your WalkSpeed is
	-- set to -- what your body is doing -- because standing still inside a shop with a
	-- run speed configured is standing still.
	speedStuds: number,
	-- Whether you are wearing gang colors, which exist to be read across a street.
	wearingColors: boolean,
}

-- How loud this person is, roughly 0.35 (still, clean, plain) to about 1.7 (sprinting,
-- citywide, banded up).
--
-- Additive rather than multiplied. Multiplying would mean a clean player is unnoticeable
-- no matter what else is true -- heat times zero is zero -- and "invisible while clean"
-- is not the same claim as "harder to notice while clean". Every term stacks onto a floor,
-- so there is no combination that switches the town's eyes off.
function Spotting.Conspicuousness(factors: Factors): number
	local loud = SPOT.Base
	loud += SPOT.HeatShare * math.clamp(factors.heatShare, 0, 1)
	-- Clamped rather than allowed to run, so that a body launched by physics -- knocked
	-- down the stairs, thrown by a moving part -- does not briefly read as forty times
	-- more conspicuous than a person can be.
	loud += SPOT.MovementShare * math.clamp(factors.speedStuds / SPOT.RunSpeedStuds, 0, 1)
	if factors.wearingColors then
		loud += SPOT.ColorsBonus
	end
	return loud
end

-- How much of an observer's attention this distance is worth: 1 in their face, EdgeShare
-- at the very limit of their range, 0 beyond it.
--
-- Linear on purpose. A curve here would be a nicer number and a worse instruction: the
-- player cannot see this value, only feel it, and "further away is proportionally safer"
-- is a thing a person can learn by playing. Anything fancier is indistinguishable from
-- randomness from the far side of the screen.
function Spotting.Closeness(distanceStuds: number, sightStuds: number): number
	if sightStuds <= 0 or distanceStuds > sightStuds then
		return 0
	end
	local share = 1 - math.clamp(distanceStuds / sightStuds, 0, 1)
	return SPOT.EdgeShare + (1 - SPOT.EdgeShare) * share
end

-- Whether this observer can see that point at all.
--
-- Distance first because it is arithmetic and the raycast is not. At the top tier the
-- police half of this runs six times per player per tick and the crowd half runs once per
-- person on the street, and the overwhelming majority of both are answered by the cheap
-- half before a ray is ever cast.
--
-- `height` is how far off the floor the look happens: an officer looks from head height
-- because they are a body, and the crowd check passes 0 because it was written that way
-- and a pedestrian's eyeline is not worth a second raycast profile. `ignore` is the
-- caller's, because who is allowed to block a view genuinely differs -- an officer must
-- not be blinded by the officer standing in front of them.
function Spotting.CanSee(
	from: Vector3,
	to: Vector3,
	sightStuds: number,
	height: number,
	ignore: { Instance }
): boolean
	if sightStuds <= 0 then
		return false
	end
	if Ground.FlatDistance(from, to) > sightStuds then
		return false
	end
	return Ground.Reachable(from, to, height, ignore)
end

-- How much notice this observer gains per second, given that they can already see you.
--
-- `secondsAtFull` is how long this kind of observer takes to make somebody of exactly
-- conspicuousness 1 at point-blank range, and it is the one number that differs between a
-- trained officer and somebody on their way to work. Passing it in rather than branching
-- on an observer type keeps this arithmetic and keeps the difference between the two in
-- Config where it can be read.
function Spotting.NoticeRate(
	distanceStuds: number,
	sightStuds: number,
	conspicuousness: number,
	secondsAtFull: number
): number
	if secondsAtFull <= 0 then
		-- Not a tunable value, a broken one. Treated as instant rather than as a divide
		-- by zero, because the alternative is an observer who can never notice anybody
		-- and a system that fails by doing nothing at all.
		return math.huge
	end
	local closeness = Spotting.Closeness(distanceStuds, sightStuds)
	if closeness <= 0 then
		return 0
	end
	return conspicuousness * closeness / secondsAtFull
end

-- How fast a character is actually travelling, flat, in studs per second.
--
-- Read off the body rather than off Humanoid.WalkSpeed, which is a setting and not a fact:
-- a player standing still in a shop has whatever run speed the game gave them and is not
-- moving at all. Flattened because falling is not conspicuous in the way running is, and
-- without it a player who steps off a kerb reads as briefly sprinting.
function Spotting.SpeedOf(character: Model?): number
	if character == nil then
		return 0
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return 0
	end
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

return Spotting
