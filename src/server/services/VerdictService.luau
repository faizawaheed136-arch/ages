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
type MomentsFn = (LifeData, {
	sinceMonths: number?,
	untilMonths: number?,
	maxCount: number?,
	kinds: { string }?,
}) -> { Types.Moment }

local VerdictService = {}

local momentsFn: MomentsFn? = nil

function VerdictService.SetMoments(fn: MomentsFn)
	momentsFn = fn
end

-- How close another ribbon's score must be to the winner to count as a near-miss.
-- 15% is generous enough that a life that almost became something shows it, but
-- tight enough that the game does not suggest every ribbon was within reach.
local NEAR_MISS_THRESHOLD = 0.15

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

	-- Fill the three moments from the winner's template by delegating to the
	-- shared query. The template only names kinds — the query walks the life's
	-- data and FormatMoment turns each result into prose.
	local templateKinds: { string } = {}
	for _, slot in (Ribbons :: any)[bestRibbon.id].momentsTemplate do
		local kind = slot.kind :: string
		if not table.find(templateKinds, kind) then
			table.insert(templateKinds, kind)
		end
	end
	local moments = (momentsFn :: any)(data, {
		sinceMonths = 0,
		maxCount = 3,
		kinds = templateKinds,
	})
	bestRibbon.moments = {}
	for _, m in moments do
		table.insert(bestRibbon.moments, {
			age = m.ageMonths // Config.Time.MonthsPerYear,
			line = m.line,
		})
	end

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
