--!strict
-- What being good at a subject means, in one place.
--
-- Every subject climbs the same ladder: lessons at or above School.GoodShare bank
-- passes, passes buy rungs, and the top rung buys the right to stop attending. What a
-- rung is *worth inside the lesson* is the verb's own business and deliberately not here
-- -- Science spends a level on showing more of the board, and a verb that has not been
-- written yet will spend one on something else -- but how a level is earned has to be
-- the same everywhere, or a procedure and a quiz end up disagreeing about what
-- "mastered" is and the skip means two different things depending on the day.
--
-- Split out of ScienceService, which held the only copy and would have had it copied
-- five more times as the other verbs landed. That is the failure this file exists to
-- stop: five ladders is five places to fix a rounding rule.
--
-- Shared rather than server-side because the report card and the door both have to read
-- a level, and because it is pure arithmetic over a LifeData with no world in it. It
-- requires only Config and Types, so it is safe in the lobby tree as well.
--
-- Nothing here writes to a profile of its own accord and nothing here pays anything.
-- Record mutates the two tables it is handed and says what happened; paying for it is
-- the caller's job, because a lesson and a procedure pay differently and this file
-- should never learn the difference.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LifeData = Types.LifeData

local Mastery = {}

local SCHOOL = Config.School
local LADDER = SCHOOL.Mastery

-- The top rung, named rather than read off Config at every call site. Exported because
-- a level is drawn as "3/5" in three places and none of them should be reaching into
-- Config to find out what the 5 is.
Mastery.Levels = LADDER.Levels
Mastery.PassesPerLevel = LADDER.PassesPerLevel

-- Where a life stands in a subject. One-based, and one is the floor rather than zero:
-- a child who has never sat a lesson is at the bottom of the ladder, not off it, and a
-- level of zero would have to be special-cased by everything that draws it.
--
-- Clamped on the way out rather than trusted. A stored level comes off a saved profile
-- that may have been written by a build with a longer ladder, and the honest reading of
-- "level 7 on a five-rung ladder" is the top rung -- not an error, and certainly not an
-- index off the end of a list.
function Mastery.LevelOf(data: LifeData, subjectId: string): number
	local stored = data.subjectMastery[subjectId]
	if stored == nil then
		return 1
	end
	return math.clamp(math.floor(stored), 1, LADDER.Levels)
end

-- Passes banked toward the next rung. Always below PassesPerLevel except at the
-- ceiling, where it is deliberately pinned to it -- see Record.
function Mastery.PassesOf(data: LifeData, subjectId: string): number
	local stored = data.subjectPasses[subjectId]
	if stored == nil then
		return 0
	end
	return math.clamp(math.floor(stored), 0, LADDER.PassesPerLevel)
end

-- Whether this subject is finished with -- the top rung, which is the whole point of
-- there being rungs.
function Mastery.IsTopped(data: LifeData, subjectId: string): boolean
	return Mastery.LevelOf(data, subjectId) >= LADDER.Levels
end

-- Records how a lesson went and returns the level afterwards plus whether it just rose.
--
-- Takes the share rather than a boolean so that the bar for a pass lives on
-- School.GoodShare with every other verdict in the system. A caller that had to decide
-- "was that good enough" itself is a caller that can decide differently from the one
-- next to it.
--
-- A poor lesson costs nothing. Deliberate, and the same principle the whole activity
-- runs on: soft failure means a bad run is worth less, never that it takes something
-- away. A ladder you can slide down turns the last lesson before the top rung into a
-- thing to be afraid of, and school is not supposed to be frightening.
function Mastery.Record(data: LifeData, subjectId: string, share: number): (number, boolean)
	local level = Mastery.LevelOf(data, subjectId)
	local passes = Mastery.PassesOf(data, subjectId)

	if share < SCHOOL.GoodShare then
		-- Written back anyway, so the first lesson in a subject leaves a record of having
		-- happened. Without this a life that has sat nine bad Music lessons is
		-- indistinguishable from one that has never seen Music, and the report card would
		-- have nothing to say about the difference.
		data.subjectMastery[subjectId] = level
		data.subjectPasses[subjectId] = passes
		return level, false
	end

	local rose = false
	if level < LADDER.Levels then
		passes += 1
		if passes >= LADDER.PassesPerLevel then
			level += 1
			passes = 0
			rose = true
		end
	else
		-- Held at the top rather than reset to zero. A topped-out player watching their
		-- progress bar cycle forever against a level that will never arrive is the game
		-- lying about there being more, and there is not.
		passes = LADDER.PassesPerLevel
	end

	data.subjectMastery[subjectId] = level
	data.subjectPasses[subjectId] = passes
	return level, rose
end

-- Sets a level outright and clears the passes under it. The harness path, and the one
-- new-life path: forgetting a subject is setting it back to the bottom.
--
-- Clamped rather than refused, so asking for level nine gets the top of the ladder --
-- a debug command that errors on an out-of-range number is a debug command you have to
-- debug.
function Mastery.Set(data: LifeData, subjectId: string, level: number)
	local clamped = math.clamp(math.floor(level), 1, LADDER.Levels)
	data.subjectMastery[subjectId] = clamped
	data.subjectPasses[subjectId] = if clamped >= LADDER.Levels then LADDER.PassesPerLevel else 0
end

-- Wipes a subject entirely, back to never having been taught. Distinct from Set(1):
-- Set leaves a record saying "sat lessons, learned nothing", and this leaves none at
-- all, which is the truth for a life that has not started yet.
function Mastery.Clear(data: LifeData, subjectId: string)
	data.subjectMastery[subjectId] = nil
	data.subjectPasses[subjectId] = nil
end

-- Whether this life has ever been taught this subject. Read by the report card, which
-- must not print a row for a subject the player has never seen -- a card listing five
-- subjects at level one, four of which were never on the timetable, tells the player
-- nothing and looks like a bug.
function Mastery.HasSat(data: LifeData, subjectId: string): boolean
	return data.subjectMastery[subjectId] ~= nil
end

return Mastery
