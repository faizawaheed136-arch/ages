--!strict
-- Computes a named ribbon for a life that has ended. Reads LifeData and scores
-- every ribbon in content/Ribbons.luau against it, then picks the highest.
--
-- A life under Config.Verdict.MinAge gets no ribbon — childhood deaths are
-- honest rather than forced into a category they did not earn.
--
-- The service has one public function. Everything else is private so the
-- content file is the only place a new ribbon touches the system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local DataService = require(script.Parent.DataService)

local Ribbons = require(script.Parent.Ribbons)

type Ribbon = Types.Ribbon
type RibbonMoment = Types.RibbonMoment
type LifeData = Types.LifeData

local VerdictService = {}

-- How close another ribbon's score must be to the winner to count as a near-miss.
-- 15% is generous enough that a life that almost became something shows it, but
-- tight enough that the game does not suggest every ribbon was within reach.
local NEAR_MISS_THRESHOLD = 0.15

-- Select the best matching moments from a template, reading the life's actual
-- data. A template may reference a flag, a bond level, a school grade, a standing
-- band, a subject mastery level, or a specific age. Each slot falls back to the
-- next available signal when its primary choice is absent, so the output always
-- has up to three moments even for sparse lives.
local function fillMoments(data: LifeData, template: { { age: number, kind: string, id: string } }): { RibbonMoment }
	local moments: { RibbonMoment } = {}
	local ageYears = data.ageMonths // 12

	for _, slot in template do
		if #moments >= 3 then break end

		local moment: RibbonMoment? = nil

		if slot.kind == "flag" then
			local flagAge = data.flags[slot.id]
			if flagAge ~= nil then
				moment = { age = flagAge, line = slot.id }
			end

		elseif slot.kind == "bond" then
			if slot.id == "none" then
				-- A slot asking for an absence is filled by the oldest age the life
				-- reached without a strong bond, or the current age if the life is
				-- still young.
				moment = { age = ageYears, line = "Nobody close enough to visit" }
			elseif slot.id == "closest" then
				local bestBond = 0
				local bestAge = ageYears
				for personId, bond in data.bonds do
					if bond >= 60 then
						-- Look up the age from visits or flags; fall back to current.
						local visited = data.visits[personId]
						local bondAge = visited ~= nil and (visited.lastYear or ageYears)
						if bond > bestBond then
							bestBond = bond
							bestAge = bondAge
						end
					end
				end
				if bestBond >= 60 then
					moment = { age = bestAge, line = "You and somebody became close" }
				end

			elseif slot.id == "mother" or slot.id == "parent" or slot.id == "child" or slot.id == "spouse" or slot.id == "friend" then
				for personId, bond in data.bonds do
					local tie = data.ties[personId]
					if tie ~= nil and string.find(string.lower(tie), string.lower(slot.id), 1, false) ~= nil and bond >= 50 then
						local visited = data.visits[personId]
						local bondAge = visited ~= nil and (visited.lastYear or ageYears)
						moment = { age = bondAge, line = "You and " .. personId .. " grew close" }
						break
					end
				end
			end

		elseif slot.kind == "grade" then
			if slot.worst == true then
				local worstGrade = "A"
				local worstAge = ageYears
				for _, year in data.schoolGrades do
					if year.grade == "F" or year.grade == "D" then
						worstGrade = year.grade
						worstAge = year.ageYears
						break
					end
					if worstGrade == "A" and (year.grade == "F" or year.grade == "D") then
						worstGrade = year.grade
						worstAge = year.ageYears
					end
				end
				if worstGrade ~= "A" then
					moment = { age = worstAge, line = "School was hard that year" }
				end
			else
				local bestGrade: { ageYears: number, grade: string }? = nil
				for _, year in data.schoolGrades do
					if year.grade == "A" then
						bestGrade = year
						break
					end
					if bestGrade == nil or (year.grade == "B" and bestGrade.grade ~= "A") then
						bestGrade = year
					end
				end
				if bestGrade ~= nil then
					moment = { age = bestGrade.ageYears, line = "You did well in school" }
				end
			end

		elseif slot.kind == "standing" then
			local threshold = slot.threshold :: number
			for jobId, standing in data.jobStanding do
				if standing >= threshold then
					moment = { age = ageYears, line = "You earned respect at " .. jobId }
					break
				end
			end

		elseif slot.kind == "mastery" then
			local subject = slot.id :: string
			local level = slot.level :: number
			local mastery = data.subjectMastery[subject]
			if mastery ~= nil and mastery >= level then
				moment = { age = ageYears, line = "You mastered " .. subject }
			end

		elseif slot.kind == "job" then
			local jobId = slot.id :: string
			if jobId == "none" and data.jobId == nil then
				moment = { age = ageYears, line = "You never held a job" }
			elseif data.jobStanding[jobId] ~= nil then
				moment = { age = ageYears, line = "You worked as a " .. jobId }
			end

		elseif slot.kind == "age" then
			local value = slot.value :: number
			if ageYears >= value then
				moment = { age = value, line = "You reached age " .. tostring(value) }
			end

		elseif slot.kind == "debt" then
			if data.bills.debt > 0 then
				moment = { age = ageYears, line = "You fell into debt" }
			end

		elseif slot.kind == "house" then
			if #data.houses.owned > 0 then
				moment = { age = ageYears, line = "You bought a home" }
			end

		elseif slot.kind == "gangRank" then
			if data.gangRankId ~= nil then
				moment = { age = ageYears, line = "You rose in a gang" }
			end
		end

		if moment ~= nil then
			-- Convert the mechanical line into readable prose.
			if string.find(moment.line, "^[a-z]") and not string.find(moment.line, "^You ") then
				moment.line = "You " .. moment.line
			end
			table.insert(moments, moment)
		end
	end

	return moments
end

-- Format a near-miss as prose. The scoreDelta tells us how far off the life was;
-- the ribbonId tells us what it almost was.
local function formatNearMiss(nearRibbon: Ribbon, scoreDelta: number, data: LifeData): string
	local ageYears = data.ageMonths // 12
	-- The template for near-miss prose is simple: name the ribbon and anchor it
	-- to a concrete fact the life actually has.
	local lead = nearRibbon.title
	if nearRibbon.id == "steadfast" then
		return `One more year at the office and you would have been {lead}.`
	elseif nearRibbon.id == "dropout" then
		return `You were one class away from finishing.`
	elseif nearRibbon.id == "broke" then
		return `One good year and you would not have been {lead}.`
	elseif nearRibbon.id == "lonely" then
		return `One close friend and you would not have been {lead}.`
	elseif nearRibbon.id == "convict" then
		return `One clean year and you would not have been {lead}.`
	elseif nearRibbon.id == "master" then
		return `A little further and you would have been {lead}.`
	elseif nearRibbon.id == "family" then
		return `One more bond and you would have been {lead}.`
	elseif nearRibbon.id == "athlete" then
		return `One more season and you would have been {lead}.`
	else
		return `You were close to being a {lead}.`
	end
end

function VerdictService.Compute(player: Player): Ribbon?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	local data = Lives.Active(profile.Data)
	if not data.alive then
		return nil
	end

	local ageYears = data.ageMonths // 12
	if ageYears < Config.Verdict.MinAge then
		return nil
	end

	-- Score every ribbon and track the winner.
	local bestScore = -1
	local bestRibbon: Ribbon? = nil
	local allScores: { [string]: number } = {}

	for _, entry in Ribbons do
		local score = entry.score(data)
		allScores[entry.id] = score
		if score > bestScore then
			bestScore = score
			bestRibbon = {
				id = entry.id,
				title = entry.title,
				description = entry.description,
				moments = {},
				nearMisses = nil,
			} :: Ribbon
		end
	end

	if bestRibbon == nil then
		return nil
	end

	-- Fill the three moments from the winner's template.
	local template: { { age: number, kind: string, id: string } } =
		(Ribbons :: any)[bestRibbon.id].momentsTemplate :: any
	bestRibbon.moments = fillMoments(data, template)

	-- Compute near-misses: ribbons within 15% of the winning score, up to two.
	local nearMisses: { string } = {}
	for ribbonId, score in allScores do
		if ribbonId ~= bestRibbon.id then
			local threshold = bestScore * (1 - NEAR_MISS_THRESHOLD)
			if score >= threshold then
				local nearEntry = (Ribbons :: any)[ribbonId]
				if nearEntry ~= nil then
					local nearRibbon = {
						id = ribbonId,
						title = nearEntry.title,
						description = nearEntry.description,
						moments = {},
						nearMisses = nil,
					} :: Ribbon
					table.insert(nearMisses, formatNearMiss(nearRibbon, bestScore - score, data))
				end
			end
		end
	end
	if #nearMisses > 0 then
		table.sort(nearMisses)
		-- Keep at most two.
		while #nearMisses > 2 do
			table.remove(nearMisses)
		end
		bestRibbon.nearMisses = nearMisses
	end

	return bestRibbon
end

return VerdictService
