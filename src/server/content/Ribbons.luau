--!strict
-- The ribbons: named endings for a life. Each entry is scored against a life's
-- data and the best match wins. Failure ribbons are not punishments — they are
-- honest names for lives that did not go well, written with the same care as
-- the success ones. "A life that ends badly must still end named."
--
-- Scoring is content, not code. Add a ribbon, adjust a weight, or change a
-- moment — all of it is a table edit. The service that reads this file does
-- not know or care which ribbon won.
--
-- Each ribbon has:
--   id              machine key, e.g. "steadfast"
--   title           shown on screen, e.g. "Steadfast"
--   description     one line of prose
--   score           function(data) -> score, moments
--   momentsTemplate a table of moment slots the selector fills from actual data
--
-- The selector picks three moments from the template, falling back through
-- flag → bond milestone → school grade → standing band → age milestone when a
-- slot's preferred signal is absent. A life that is too young gets fewer.

local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Types"))

type RibbonEntry = {
	id: string,
	title: string,
	description: string,
	score: (data: Types.LifeData) -> number,
	momentsTemplate: { { age: number, kind: string, id: string } },
	nearMissKind: string,
}

local function sumJobStanding(data: Types.LifeData): number
	local total = 0
	for _, v in data.jobStanding do
		total += v
	end
	return total
end

local function countStrongBonds(data: Types.LifeData, threshold: number): number
	local count = 0
	for _, bond in data.bonds do
		if bond >= threshold then
			count += 1
		end
	end
	return count
end

local function bestSchoolGrade(data: Types.LifeData): string
	local best = "F"
	for _, year in data.schoolGrades do
		local g = year.grade
		if g == "A" then return "A" end
		if g == "B" and best ~= "A" then best = "B" end
		if g == "C" and best ~= "A" and best ~= "B" then best = "C" end
		if g == "D" and best == "F" then best = "D" end
	end
	return best
end

local function countFlagAge(data: Types.LifeData, flagId: string): number?
	return data.flags[flagId]
end

local function maxJobStanding(data: Types.LifeData): number
	local best = 0
	for _, v in data.jobStanding do
		if v > best then best = v end
	end
	return best
end

local function totalYearsWorked(data: Types.LifeData): number
	return #data.jobStanding
end

local Ribbons: { RibbonEntry } = {
	-- Success ribbons

	{
		id = "steadfast",
		title = "Steadfast",
		description = "You held a job for thirty years and never once looked for an easier one.",
		score = function(data)
			local s = 0
			s += sumJobStanding(data) / 10
			if data.convictions == 0 then s += 15 end
			s += countStrongBonds(data, 40) * 3
			local grade = bestSchoolGrade(data)
			if grade == "A" then s += 6 end
			if grade == "B" then s += 3 end
			return s
		end,
		momentsTemplate = {
			{ age = 16, kind = "flag", id = "firstJob" },
			{ age = 25, kind = "flag", id = "promotion" },
			{ age = 0, kind = "bond", id = "closest" },
		},
		nearMissKind = "master",
	},
	{
		id = "master",
		title = "Master",
		description = "You rose high enough that people still mention your name.",
		score = function(data)
			local s = 0
			s += maxJobStanding(data) * 2
			s += totalYearsWorked(data) * 3
			if data.convictions == 0 then s += 10 end
			s += countStrongBonds(data, 50) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "standing", threshold = 10 },
			{ age = 0, kind = "flag", id = "promotion" },
			{ age = 0, kind = "bond", id = "closest" },
		},
		nearMissKind = "steadfast",
	},
	{
		id = "creator",
		title = "Creator",
		description = "You made something that outlasted you.",
		score = function(data)
			local s = 0
			if data.flags.artPiece ~= nil then s += 8 end
			if data.flags.patent ~= nil then s += 12 end
			s += (data.subjectMastery.art or 0) * 2
			s += (data.subjectMastery.science or 0) * 1
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "artPiece" },
			{ age = 0, kind = "flag", id = "patent" },
			{ age = 0, kind = "mastery", subject = "art", level = 5 },
		},
		nearMissKind = "craftsman",
	},
	{
		id = "leader",
		title = "Leader",
		description = "You stood at the front and people followed.",
		score = function(data)
			local s = 0
			if data.gangRankId ~= nil then s += 12 end
			s += maxJobStanding(data) * 1.5
			s += countStrongBonds(data, 60) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "gangRank" },
			{ age = 0, kind = "flag", id = "promotion" },
			{ age = 0, kind = "bond", id = "closest" },
		},
		nearMissKind = "diplomat",
	},
	{
		id = "healer",
		title = "Healer",
		description = "You spent your life mending what was broken in others.",
		score = function(data)
			local s = 0
			if data.jobStanding["doctor"] ~= nil then s += 15 end
			if data.jobStanding["nurse"] ~= nil then s += 10 end
			s += countStrongBonds(data, 30) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "job", id = "doctor" },
			{ age = 0, kind = "job", id = "nurse" },
			{ age = 0, kind = "bond", id = "closest" },
		},
		nearMissKind = "teacher",
	},
	{
		id = "athlete",
		title = "Athlete",
		description = "You ran faster and jumped higher than most people ever will.",
		score = function(data)
			local s = 0
			if data.flags.allState ~= nil then s += 15 end
			if data.flags.scholarAthlete ~= nil then s += 10 end
			s += (data.stats.looks or 0) / 10
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "allState" },
			{ age = 0, kind = "flag", id = "scholarAthlete" },
			{ age = 0, kind = "grade", best = true },
		},
		nearMissKind = "adrenaline-seeker",
	},
	{
		id = "scholar",
		title = "Scholar",
		description = "You spent your life learning, and never stopped.",
		score = function(data)
			local s = 0
			for _, v in data.subjectMastery do
				s += v * 2
			end
			local grade = bestSchoolGrade(data)
			if grade == "A" then s += 10 end
			if data.flags.phd ~= nil then s += 15 end
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "mastery", subject = "science", level = 5 },
			{ age = 0, kind = "mastery", subject = "math", level = 5 },
			{ age = 0, kind = "flag", id = "phd" },
		},
		nearMissKind = "teacher",
	},
	{
		id = "philanthropist",
		title = "Philanthropist",
		description = "You had enough and gave some of it away.",
		score = function(data)
			local s = 0
			if data.flags.donated ~= nil then s += 12 end
			if data.flags.legacy ~= nil then s += 15 end
			s += (data.money or 0) / 500
			return math.min(s, 30)
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "donated" },
			{ age = 0, kind = "flag", id = "legacy" },
			{ age = 0, kind = "bond", id = "closest" },
		},
		nearMissKind = "steady",
	},
	{
		id = "family",
		title = "Family",
		description = "Your home was full and the door was always open.",
		score = function(data)
			local s = 0
			if data.flags.parent ~= nil then s += 10 end
			if data.flags.largeFamily ~= nil then s += 8 end
			s += countStrongBonds(data, 50) * 2
			if #data.houses.owned > 0 then s += 5 end
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "parent" },
			{ age = 0, kind = "bond", id = "mother" },
			{ age = 0, kind = "bond", id = "friend" },
		},
		nearMissKind = "lonely",
	},
	{
		id = "explorer",
		title = "Explorer",
		description = "You went places most people only read about.",
		score = function(data)
			local s = 0
			if data.flags.traveled ~= nil then s += 10 end
			if data.flags.immigrant ~= nil then s += 8 end
			s += (data.subjectMastery.geography or 0) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "traveled" },
			{ age = 0, kind = "flag", id = "immigrant" },
			{ age = 0, kind = "grade", best = true },
		},
		nearMissKind = "settled",
	},
	{
		id = "artisan",
		title = "Artisan",
		description = "You made things with your hands and they were good.",
		score = function(data)
			local s = 0
			if data.flags.crafted ~= nil then s += 10 end
			s += (data.subjectMastery.art or 0) * 2
			s += (data.subjectMastery.science or 0)
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "crafted" },
			{ age = 0, kind = "mastery", subject = "art", level = 3 },
			{ age = 0, kind = "job", id = "mechanic" },
		},
		nearMissKind = "creator",
	},
	{
		id = "architect",
		title = "Architect",
		description = "You shaped the world other people live in.",
		score = function(data)
			local s = 0
			if data.jobStanding["architect"] ~= nil then s += 15 end
			s += (data.subjectMastery.science or 0) * 2
			s += (data.subjectMastery.math or 0)
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "job", id = "architect" },
			{ age = 0, kind = "mastery", subject = "science", level = 3 },
			{ age = 0, kind = "mastery", subject = "math", level = 3 },
		},
		nearMissKind = "engineer",
	},
	{
		id = "musician",
		title = "Musician",
		description = "You played for people and they listened.",
		score = function(data)
			local s = 0
			if data.flags.performed ~= nil then s += 10 end
			if data.flags.talentShow ~= nil then s += 8 end
			s += (data.subjectMastery.music or 0) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "performed" },
			{ age = 0, kind = "flag", id = "talentShow" },
			{ age = 0, kind = "mastery", subject = "music", level = 3 },
		},
		nearMissKind = "artist",
	},
	{
		id = "writer",
		title = "Writer",
		description = "You put words on the page and called it a life's work.",
		score = function(data)
			local s = 0
			if data.flags.published ~= nil then s += 12 end
			if data.flags.stories ~= nil then s += 8 end
			s += (data.subjectMastery.reading or 0) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "published" },
			{ age = 0, kind = "flag", id = "stories" },
			{ age = 0, kind = "mastery", subject = "reading", level = 3 },
		},
		nearMissKind = "scholar",
	},
	{
		id = "diplomat",
		title = "Diplomat",
		description = "You settled arguments instead of starting them.",
		score = function(data)
			local s = 0
			if data.flags.peacemaker ~= nil then s += 10 end
			s += countStrongBonds(data, 40) * 2
			s += maxJobStanding(data)
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "peacemaker" },
			{ age = 0, kind = "bond", id = "closest" },
			{ age = 0, kind = "standing", threshold = 5 },
		},
		nearMissKind = "leader",
	},
	{
		id = "guardian",
		title = "Guardian",
		description = "You stood between danger and the people you loved.",
		score = function(data)
			local s = 0
			if data.flags.protected ~= nil then s += 12 end
			if data.flags.helicopter ~= nil then s += 8 end
			s += countStrongBonds(data, 60) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "protected" },
			{ age = 0, kind = "bond", id = "parent" },
			{ age = 0, kind = "bond", id = "child" },
		},
		nearMissKind = "hero",
	},
	{
		id = "teacher",
		title = "Teacher",
		description = "You spent your life helping other people learn.",
		score = function(data)
			local s = 0
			if data.jobStanding["teacher"] ~= nil then s += 15 end
			if data.jobStanding["tutor"] ~= nil then s += 10 end
			s += (data.subjectMastery.reading or 0) * 2
			s += (data.subjectMastery.math or 0)
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "job", id = "teacher" },
			{ age = 0, kind = "job", id = "tutor" },
			{ age = 0, kind = "mastery", subject = "reading", level = 3 },
		},
		nearMissKind = "scholar",
	},
	{
		id = "engineer",
		title = "Engineer",
		description = "You figured out how things work and made them work better.",
		score = function(data)
			local s = 0
			if data.jobStanding["engineer"] ~= nil then s += 15 end
			if data.jobStanding["mechanic"] ~= nil then s += 10 end
			s += (data.subjectMastery.science or 0) * 3
			s += (data.subjectMastery.math or 0) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "job", id = "engineer" },
			{ age = 0, kind = "mastery", subject = "science", level = 5 },
			{ age = 0, kind = "mastery", subject = "math", level = 3 },
		},
		nearMissKind = "architect",
	},
	{
		id = "volunteer",
		title = "Volunteer",
		description = "You gave your time when nobody was paying you to.",
		score = function(data)
			local s = 0
			if data.flags.volunteered ~= nil then s += 12 end
			s += countStrongBonds(data, 30) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "volunteered" },
			{ age = 0, kind = "bond", id = "closest" },
			{ age = 0, kind = "age", value = 30 },
		},
		nearMissKind = "philanthropist",
	},
	{
		id = "retiree",
		title = "Retiree",
		description = "You worked hard, saved what you could, and rested.",
		score = function(data)
			local s = 0
			local age = data.ageMonths // 12
			if age >= 60 then s += 10 end
			s += totalYearsWorked(data) * 2
			if #data.houses.owned > 0 then s += 5 end
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "age", value = 60 },
			{ age = 0, kind = "flag", id = "firstJob" },
			{ age = 0, kind = "bond", id = "closest" },
		},
		nearMissKind = "steadfast",
	},

	-- Failure ribbons

	{
		id = "dropout",
		title = "Dropout",
		description = "You never finished what you started.",
		score = function(data)
			local s = 0
			if data.flags.droppedOut ~= nil then s += 20 end
			s += (10 - math.min(data.subjectMastery.science or 1, 5)) * 2
			s += (10 - math.min(data.subjectMastery.reading or 1, 5)) * 2
			if data.jobId == nil then s += 15 end
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "droppedOut" },
			{ age = 0, kind = "grade", worst = true },
			{ age = 0, kind = "bond", id = "none" },
		},
		nearMissKind = "steady",
	},
	{
		id = "benchwarmer",
		title = "Benchwarmer",
		description = "You were good enough to try, and never good enough to stay.",
		score = function(data)
			local s = 0
			if data.flags.triedOut ~= nil and data.flags.madeTeam == nil then s += 15 end
			s += (data.subjectMastery.science or 0)
			if data.jobId ~= nil and maxJobStanding(data) < 3 then s += 10 end
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "triedOut" },
			{ age = 0, kind = "flag", id = "madeTeam" },
			{ age = 0, kind = "job", id = "athlete" },
		},
		nearMissKind = "athlete",
	},
	{
		id = "estranged",
		title = "Estranged",
		description = "The people who should have been there were not.",
		score = function(data)
			local s = 0
			local strong = countStrongBonds(data, 50)
			s += (5 - strong) * 4
			if data.flags.fallenOut ~= nil then s += 10 end
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "bond", id = "mother" },
			{ age = 0, kind = "bond", id = "friend" },
			{ age = 0, kind = "flag", id = "fallenOut" },
		},
		nearMissKind = "family",
	},
	{
		id = "broke",
		title = "Broke",
		description = "You ran out before you had enough.",
		score = function(data)
			local s = 0
			if data.bills.debt > 0 then s += 12 end
			if data.money < 100 then s += 8 end
			if data.flags.bankrupt ~= nil then s += 15 end
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "bankrupt" },
			{ age = 0, kind = "debt" },
			{ age = 0, kind = "flag", id = "lostJob" },
		},
		nearMissKind = "steady",
	},
	{
		id = "convict",
		title = "Convict",
		description = "The system took you and did not give you back.",
		score = function(data)
			local s = 0
			s += data.convictions * 15
			if data.flags.incarcerated ~= nil then s += 10 end
			if data.gangId ~= nil then s += 8 end
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "firstCrime" },
			{ age = 0, kind = "flag", id = "convicted" },
			{ age = 0, kind = "flag", id = "incarcerated" },
		},
		nearMissKind = "drifter",
	},
	{
		id = "lonely",
		title = "Lonely",
		description = "You were surrounded by people and still had nobody.",
		score = function(data)
			local s = 0
			local strong = countStrongBonds(data, 40)
			s += (4 - strong) * 5
			if #data.bonds < 2 then s += 10 end
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "bond", id = "none" },
			{ age = 0, kind = "flag", id = "noFriends" },
			{ age = 0, kind = "age", value = 40 },
		},
		nearMissKind = "family",
	},
	{
		id = "washed-up",
		title = "Washed-up",
		description = "You had your moment, and then it was over.",
		score = function(data)
			local s = 0
			if data.flags.onceFamous ~= nil then s += 15 end
			if data.flags.hadItAll ~= nil then s += 10 end
			if maxJobStanding(data) < 3 and totalYearsWorked(data) > 5 then s += 8 end
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "onceFamous" },
			{ age = 0, kind = "flag", id = "lostJob" },
			{ age = 0, kind = "standing", threshold = 1 },
		},
		nearMissKind = "master",
	},
	{
		id = "addict",
		title = "Addict",
		description = "Something held you tighter than you held anything else.",
		score = function(data)
			local s = 0
			if data.flags.addiction ~= nil then s += 15 end
			if data.flags.rehab ~= nil then s += 8 end
			s += (10 - (data.stats.health or 50) / 5)
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "addiction" },
			{ age = 0, kind = "flag", id = "rehab" },
			{ age = 0, kind = "flag", id = "relapse" },
		},
		nearMissKind = "survivor",
	},
	{
		id = "drifter",
		title = "Drifter",
		description = "You never stayed anywhere long enough to put down roots.",
		score = function(data)
			local s = 0
			s += totalYearsWorked(data) == 0 and 15 or (10 - totalYearsWorked(data)) * 2
			if #data.houses.owned == 0 and data.flags.livedWith ~= nil then s += 5 end
			s += (5 - countStrongBonds(data, 20)) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "moved" },
			{ age = 0, kind = "job", id = "none" },
			{ age = 0, kind = "bond", id = "none" },
		},
		nearMissKind = "convict",
	},
	{
		id = "nobody",
		title = "Nobody",
		description = "You lived and died and nothing remember you at all.",
		score = function(data)
			local s = 0
			s += (10 - countStrongBonds(data, 20)) * 3
			if totalYearsWorked(data) == 0 then s += 10 end
			if data.flags.noLegacy ~= nil then s += 8 end
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "bond", id = "none" },
			{ age = 0, kind = "flag", id = "noLegacy" },
			{ age = 0, kind = "age", value = 50 },
		},
		nearMissKind = "lonely",
	},
	{
		id = "burnt-out",
		title = "Burnt-out",
		description = "You gave everything and had nothing left to give.",
		score = function(data)
			local s = 0
			s += totalYearsWorked(data) * 2
			if data.flags.overworked ~= nil then s += 12 end
			s += (100 - (data.stats.happiness or 50)) / 5
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "overworked" },
			{ age = 0, kind = "job", id = "office" },
			{ age = 0, kind = "age", value = 40 },
		},
		nearMissKind = "steadfast",
	},
	{
		id = "failed",
		title = "Failed",
		description = "You tried, and it did not work out.",
		score = function(data)
			local s = 0
			if data.flags.tried ~= nil and data.flags.succeeded == nil then s += 12 end
			s += (data.convictions or 0) * 3
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "tried" },
			{ age = 0, kind = "flag", id = "succeeded" },
			{ age = 0, kind = "age", value = 30 },
		},
		nearMissKind = "persistent",
	},
	{
		id = "forgotten",
		title = "Forgotten",
		description = "The world moved on and took your name with it.",
		score = function(data)
			local s = 0
			if countStrongBonds(data, 30) == 0 then s += 15 end
			if totalYearsWorked(data) == 0 then s += 8 end
			s += (100 - (data.stats.happiness or 50)) / 8
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "bond", id = "none" },
			{ age = 0, kind = "flag", id = "isolated" },
			{ age = 0, kind = "age", value = 60 },
		},
		nearMissKind = "lonely",
	},
	{
		id = "unemployed",
		title = "Unemployed",
		description = "You could not find work, or could not keep it.",
		score = function(data)
			local s = 0
			if totalYearsWorked(data) == 0 then s += 20 end
			if data.flags.fired ~= nil then s += 8 end
			s += (10 - totalYearsWorked(data)) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "firstJob" },
			{ age = 0, kind = "flag", id = "fired" },
			{ age = 0, kind = "age", value = 25 },
		},
		nearMissKind = "drifter",
	},
	{
		id = "inmate",
		title = "Inmate",
		description = "You spent more time in a cell than anywhere else.",
		score = function(data)
			local s = 0
			s += data.convictions * 12
			if data.flags.servedTime ~= nil then s += 10 end
			if data.gangId ~= nil then s += 6 end
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "firstCrime" },
			{ age = 0, kind = "flag", id = "servedTime" },
			{ age = 0, kind = "flag", id = "paroled" },
		},
		nearMissKind = "convict",
	},
	{
		id = "vagrant",
		title = "Vagrant",
		description = "You had no home and no one to call your own.",
		score = function(data)
			local s = 0
			if #data.houses.owned == 0 then s += 10 end
			if data.flags.homeless ~= nil then s += 15 end
			s += (5 - countStrongBonds(data, 10)) * 3
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "homeless" },
			{ age = 0, kind = "bond", id = "none" },
			{ age = 0, kind = "age", value = 35 },
		},
		nearMissKind = "drifter",
	},

	-- Neutral / specific ribbons

	{
		id = "parent",
		title = "Parent",
		description = "You raised somebody else's future.",
		score = function(data)
			local s = 0
			if data.flags.parent ~= nil then s += 15 end
			s += countStrongBonds(data, 40) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "parent" },
			{ age = 0, kind = "bond", id = "child" },
			{ age = 0, kind = "age", value = 25 },
		},
		nearMissKind = "family",
	},
	{
		id = "immigrant",
		title = "Immigrant",
		description = "You left everything behind and started over.",
		score = function(data)
			local s = 0
			if data.flags.immigrant ~= nil then s += 15 end
			if data.flags.traveled ~= nil then s += 8 end
			s += totalYearsWorked(data) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "immigrant" },
			{ age = 0, kind = "flag", id = "firstJob" },
			{ age = 0, kind = "bond", id = "closest" },
		},
		nearMissKind = "explorer",
	},
	{
		id = "inventor",
		title = "Inventor",
		description = "You made something that had not existed before.",
		score = function(data)
			local s = 0
			if data.flags.patent ~= nil then s += 20 end
			s += (data.subjectMastery.science or 0) * 3
			s += (data.subjectMastery.math or 0) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "patent" },
			{ age = 0, kind = "mastery", subject = "science", level = 5 },
			{ age = 0, kind = "mastery", subject = "math", level = 5 },
		},
		nearMissKind = "creator",
	},
	{
		id = "survivor",
		title = "Survivor",
		description = "You lived through things that should have broken you.",
		score = function(data)
			local s = 0
			if data.flags.survived ~= nil then s += 15 end
			if data.flags.addiction ~= nil and data.flags.rehab ~= nil then s += 10 end
			s += (data.stats.health or 50) / 5
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "survived" },
			{ age = 0, kind = "flag", id = "addiction" },
			{ age = 0, kind = "flag", id = "rehab" },
		},
		nearMissKind = "addict",
	},
	{
		id = "widow",
		title = "Widow",
		description = "You loved somebody and then you did not have them anymore.",
		score = function(data)
			local s = 0
			if data.flags.widowed ~= nil then s += 15 end
			s += countStrongBonds(data, 60) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "widowed" },
			{ age = 0, kind = "bond", id = "spouse" },
			{ age = 0, kind = "age", value = 50 },
		},
		nearMissKind = "family",
	},
	{
		id = "volunteer",
		title = "Volunteer",
		description = "You showed up when nobody was watching.",
		score = function(data)
			local s = 0
			if data.flags.volunteered ~= nil then s += 15 end
			s += countStrongBonds(data, 30) * 2
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "volunteered" },
			{ age = 0, kind = "bond", id = "closest" },
			{ age = 0, kind = "age", value = 30 },
		},
		nearMissKind = "philanthropist",
	},
	{
		id = "migrant",
		title = "Migrant",
		description = "You moved for work and never found a place to stay.",
		score = function(data)
			local s = 0
			if data.flags.migrant ~= nil then s += 12 end
			s += totalYearsWorked(data) * 2
			if #data.houses.owned == 0 then s += 5 end
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "migrant" },
			{ age = 0, kind = "job", id = "none" },
			{ age = 0, kind = "flag", id = "moved" },
		},
		nearMissKind = "drifter",
	},
	{
		id = "craftsman",
		title = "Craftsman",
		description = "You made things with your hands and they lasted.",
		score = function(data)
			local s = 0
			if data.flags.crafted ~= nil then s += 12 end
			s += (data.subjectMastery.art or 0) * 2
			s += (data.subjectMastery.science or 0)
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "crafted" },
			{ age = 0, kind = "mastery", subject = "art", level = 3 },
			{ age = 0, kind = "job", id = "mechanic" },
		},
		nearMissKind = "creator",
	},
	{
		id = "hero",
		title = "Hero",
		description = "You did something brave when it mattered.",
		score = function(data)
			local s = 0
			if data.flags.heroic ~= nil then s += 20 end
			if data.flags.protected ~= nil then s += 10 end
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "flag", id = "heroic" },
			{ age = 0, kind = "flag", id = "protected" },
			{ age = 0, kind = "bond", id = "closest" },
		},
		nearMissKind = "guardian",
	},
	{
		id = "settled",
		title = "Settled",
		description = "You found a place and stayed in it.",
		score = function(data)
			local s = 0
			if #data.houses.owned > 0 then s += 10 end
			s += totalYearsWorked(data) * 2
			s += countStrongBonds(data, 30)
			return s
		end,
		momentsTemplate = {
			{ age = 0, kind = "house" },
			{ age = 0, kind = "flag", id = "firstJob" },
			{ age = 0, kind = "bond", id = "closest" },
		},
		nearMissKind = "explorer",
	},
}

-- Public API: return the full table for the service to iterate.
return Ribbons
