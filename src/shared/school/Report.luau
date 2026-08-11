--!strict
-- What a school year was, kept so it can be said back.
--
-- Until now a year of school left behind exactly one artifact: a `smarts` number that
-- had moved. That is enough for the office job to read and not nearly enough for the
-- player -- they cannot tell you which subject they were good at, which year they threw
-- away, or how close they are to finishing something. Thirty-six lessons over a
-- childhood, and no record that any of them happened.
--
-- This is the record. Every lesson appends a line; every birthday closes the year, names
-- it, and stages a card to be handed over at the school. Nothing here draws anything --
-- see SchoolService for what the card actually says -- and nothing here pays anything,
-- for the same reason Mastery does not: a lesson and a procedure pay differently and
-- this file should never learn the difference.
--
-- Shared rather than server-side for the reason Mastery is: it has two callers already.
-- SchoolService records a quiz and ScienceService records a lab, and the day those two
-- disagreed about what a "good" lesson was would be the day a report card and a lesson's
-- own closing line said different things about the same afternoon. It requires only
-- Config and Types, so it is safe in the lobby tree as well.
--
-- The grades this writes are read on the card today and are also the substrate the
-- end-of-life verdict will need. That is not speculative scaffolding: a year's grade is
-- reconstructible from nothing once the year is over, so a build that does not record it
-- as it happens can never go back and work it out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LifeData = Types.LifeData
type SchoolLessonRecord = Types.SchoolLessonRecord

local Report = {}

local SCHOOL = Config.School

-- The band a lesson fell in, as stored. Deliberately the same three words Config names
-- its payouts after -- SmartsPerGoodLesson, PerOk, PerPoor -- so a stored record and the
-- number it was paid cannot drift apart in anybody's head.
--
-- "skipped" is the fourth and it is not a share at all: it is what mastery bought, and it
-- has to be distinguishable from an ordinary pass on the card. A year of skips reads very
-- differently from a year of lessons, and both are worth the same smarts.
Report.Good = "good"
Report.Ok = "ok"
Report.Poor = "poor"
Report.Skipped = "skipped"

-- What each band is called out loud. A table rather than the strings inline, because the
-- stored word and the printed word are deliberately not the same -- "ok" is the name of a
-- Config threshold and "fair" is what a child reads on a report card -- and one table is
-- the only way to have both without two vocabularies drifting.
local BAND_WORDS: { [string]: string } = {
	[Report.Good] = "good",
	[Report.Ok] = "fair",
	[Report.Poor] = "poor",
	[Report.Skipped] = "skipped",
}

-- A slot on the card with no lesson against it. Not a stored band: nothing writes this,
-- the card draws it for the lessons that never happened, and that absence is most of what
-- a bad year's card is trying to say.
Report.AbsentWord = "absent"

-- What a whole year is called. Four, and one of them is a failure -- a year nobody turned
-- up to still ends named, because a life that goes badly has to be a life that was lived
-- rather than a blank.
Report.Top = "top of the class"
Report.Passing = "passing"
Report.Behind = "falling behind"
Report.Absent = "never turned up"

-- What each band is worth toward the year, out of one slot.
--
-- A skip counts as a pass rather than as a full lesson, which is the same call takeSkip
-- makes when it pays SmartsPerOkLesson: the player earned the afternoon back and they did
-- not spend it learning anything. A year of skips is a passing year and never a top one.
local BAND_VALUE: { [string]: number } = {
	[Report.Good] = 1,
	[Report.Ok] = 0.5,
	[Report.Poor] = 0,
	[Report.Skipped] = 0.5,
}

-- The band a share of right answers falls in. The one place this decision is made, and
-- both verbs call it -- a quiz measures the share of questions and a lab the share of
-- procedure steps, but what counts as a good afternoon is a school-wide judgment and not
-- a per-subject one.
function Report.BandFor(share: number): string
	if share >= SCHOOL.GoodShare then
		return Report.Good
	elseif share >= SCHOOL.OkShare then
		return Report.Ok
	end
	return Report.Poor
end

-- What a band pays. Paired with BandFor so a caller that has already asked which band it
-- is never has to run the same if-chain again against a different set of constants.
function Report.SmartsFor(band: string): number
	if band == Report.Good then
		return SCHOOL.SmartsPerGoodLesson
	elseif band == Report.Ok or band == Report.Skipped then
		return SCHOOL.SmartsPerOkLesson
	end
	return SCHOOL.SmartsPerPoorLesson
end

-- The word for a band, for a card. Falls back to the stored word rather than erroring: a
-- saved life can hold a band written by a build that had a fifth one, and a row reading
-- "excellent" is better than a card that refuses to draw.
function Report.WordFor(band: string): string
	return BAND_WORDS[band] or band
end

-- Adds a lesson to the year in progress. Called by whichever verb just ended, with what
-- it decided -- this file never re-derives the band, because the verb has already paid
-- against it and a second opinion here would let the card contradict the smarts.
--
-- `level` is the rung this lesson promoted the subject to, or nil if it promoted nothing.
-- Only the promotion is recorded and not the standing level: a card is a report on a
-- year, and "Math, level 3" against a lesson that did not move it would read as though
-- the lesson had earned it.
function Report.RecordLesson(data: LifeData, subjectId: string, band: string, smarts: number, level: number?)
	-- Bounded by the year's own cap, which is enforced at the school door -- so this only
	-- ever bites when something has bypassed that check, and the honest failure is a card
	-- that reports the first three lessons rather than one that claims the year had five
	-- afternoons in it. The count that charges the missed-year penalty is
	-- `lessonsThisYear`, not this, so nothing is let off by the drop.
	if #data.schoolYear >= SCHOOL.LessonsPerYear then
		return
	end
	table.insert(data.schoolYear, {
		subjectId = subjectId,
		band = band,
		smarts = smarts,
		level = level,
	})
end

-- What a year of these lessons is called. Measured over the year's slots rather than over
-- the lessons actually sat, which is the whole difference between "you did well" and "you
-- turned up once and did well": two good lessons and an empty slot is not a top year.
--
-- Graded against the same two shares a single lesson is, deliberately. A year and a
-- lesson are the same question asked over a different span, and a second pair of
-- thresholds would be two sets of numbers to keep in step for no gain.
function Report.GradeFor(lessons: { SchoolLessonRecord }): string
	if #lessons == 0 then
		return Report.Absent
	end

	local slots = math.max(SCHOOL.LessonsPerYear, #lessons)
	local earned = 0
	for _, lesson in lessons do
		earned += BAND_VALUE[lesson.band] or 0
	end

	local share = earned / slots
	if share >= SCHOOL.GoodShare then
		return Report.Top
	elseif share >= SCHOOL.OkShare then
		return Report.Passing
	end
	return Report.Behind
end

-- Closes the school year that has just ended and stages its card. Returns whether there
-- is one to hand over.
--
-- `missed` is passed in rather than worked out here because the caller already had to
-- decide it to charge for it, and two answers to "did they go to school this year" is
-- exactly the kind of disagreement that ends with a card calling a player absent from a
-- year they were not charged for.
--
-- Three outcomes, and the third is the one worth reading twice:
--
--   * lessons on the record -- graded on them.
--   * no lessons and missed -- the year is named as the failure it was.
--   * no lessons and *not* missed -- no card and no grade at all. This is a birthday that
--     landed mid-lesson, where the lesson counts against the year now starting: grading
--     the old year as absent would accuse a child sitting in a classroom of never having
--     come, and grading it on a lesson the next year is also counting would count it
--     twice. A year with no honest verdict gets none, and the history simply has no entry
--     for that age.
function Report.CloseYear(data: LifeData, yearJustEnded: number, missed: boolean): boolean
	local lessons = data.schoolYear
	data.schoolYear = {}

	if yearJustEnded < SCHOOL.StartAge or yearJustEnded > SCHOOL.EndAge then
		return false
	end
	if #lessons == 0 and not missed then
		return false
	end

	local grade = Report.GradeFor(lessons)
	table.insert(data.schoolGrades, { ageYears = yearJustEnded, grade = grade })

	-- Overwrites any card still waiting to be collected, and that is the rule rather than
	-- an accident: a player who has not been to school for three years is handed the most
	-- recent card, not three of them in a row. The years underneath it are not lost --
	-- they are in `schoolGrades`, which is what the card's own record line is drawn from.
	data.pendingReport = { ageYears = yearJustEnded, grade = grade, lessons = lessons }
	return true
end

-- How many years of each grade this life has behind it, as a list in the order the grades
-- are declared above rather than a map -- the card reads them worst-last and a map has no
-- order to read.
function Report.Tally(data: LifeData): { { grade: string, years: number } }
	local counts: { [string]: number } = {}
	for _, year in data.schoolGrades do
		counts[year.grade] = (counts[year.grade] or 0) + 1
	end

	local tally: { { grade: string, years: number } } = {}
	for _, grade in { Report.Top, Report.Passing, Report.Behind, Report.Absent } do
		local years = counts[grade]
		if years ~= nil and years > 0 then
			table.insert(tally, { grade = grade, years = years })
		end
	end
	return tally
end

-- Wipes the whole record, back to a life that has never been to school. The new-life
-- path, and the harness one. Distinct from letting the fields age out on their own:
-- nobody inherits an education, and a newborn holding somebody else's report card is the
-- kind of bug that looks like the save system is broken.
function Report.Clear(data: LifeData)
	data.schoolYear = {}
	data.schoolGrades = {}
	data.pendingReport = nil
end

return Report
