--!strict
-- Aging is player-driven. There is no wall clock advancing the world: a year
-- ends when the player presses Age Up, or when they have banked enough active
-- session time that the safety net advances them anyway. Both routes run the
-- same code path so decay, stage transitions and the death roll can never
-- drift apart between them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)
local StatService = require(script.Parent.StatService)
local PocketMoneyService = require(script.Parent.PocketMoneyService)
local EventService = require(script.Parent.EventService)
local BodyService = require(script.Parent.BodyService)
local DeliveryService = require(script.Parent.DeliveryService)
local WorkService = require(script.Parent.WorkService)
local SchoolService = require(script.Parent.SchoolService)
local GymService = require(script.Parent.GymService)
local SportsDrillService = require(script.Parent.SportsDrillService)
local FightService = require(script.Parent.FightService)
local PeopleService = require(script.Parent.PeopleService)
local VehicleService = require(script.Parent.VehicleService)
local BillService = require(script.Parent.BillService)
local SavingsService = require(script.Parent.SavingsService)
local MilestoneService = require(script.Parent.MilestoneService)
local ChildhoodService = require(script.Parent.ChildhoodService)
local SetupService = require(script.Parent.SetupService)
local ReturnService = require(script.Parent.ReturnService)
-- Used by Init (SetMoments) and by the verdict at the end of a life. This require was
-- missing, so `VerdictService` was a global read -- nil -- and `LifeService:Init()` threw
-- on the nil index. init.server.luau calls the Inits unguarded, so nothing after line 92
-- ever initialised and no service was ever Started: the place came up with nothing in it.
--
-- The comment at the SetMoments call says requiring it here would close a cycle. It does
-- not: VerdictService reaches only DataService and Ribbons, and neither reaches back here.
-- SetMoments is still needed -- it threads the moments *query* in -- but that is a
-- different problem from the require, and conflating the two is what lost the require.
local VerdictService = require(script.Parent.VerdictService)

type LifeStageId = Types.LifeStageId
type AgeUpCause = Types.AgeUpCause
type ManualAgeUpState = Types.ManualAgeUpState
type LifeData = Types.LifeData
type Moment = Types.Moment

local AgeUpdatedRemote = Remotes.Get("AgeUpdated")
local AgeUpProgressRemote = Remotes.Get("AgeUpProgress")
local RequestAgeUpRemote = Remotes.Get("RequestAgeUp")
local PlayerDiedRemote = Remotes.Get("PlayerDied")
local LifeStageChangedRemote = Remotes.Get("LifeStageChanged")
local NoticeRemote = Remotes.Get("Notice")
local ChapterBreakRemote = Remotes.Get("ChapterBreak")

local LifeService = {}

local function stageForAge(ageYears: number): LifeStageId
	for _, stage in Config.LifeStages do
		if ageYears >= stage.minAge and ageYears <= stage.maxAge then
			return stage.id :: LifeStageId
		end
	end
	return "Elder"
end

-- ChancePerYear = min(MaxChancePerYear, BaseChancePerYear * (age - RampStartAge) ^ Exponent)
local function rollNaturalDeath(ageYears: number): boolean
	local deathConfig = Config.Death
	if ageYears < deathConfig.RampStartAge then
		return false
	end
	local yearsPast = ageYears - deathConfig.RampStartAge
	local chance = math.min(deathConfig.MaxChancePerYear, deathConfig.BaseChancePerYear * (yearsPast ^ deathConfig.Exponent))
	return math.random() < chance
end

-- The birthday chance of falling ill, given the health the new year begins on.
-- Zero at and above the line -- illness is the tax on being run down, not a lottery
-- everyone is in -- and rising in a straight line to the ceiling at zero health, so
-- every point of health below the line is a little more of the body failing to hold.
local function illnessChanceAt(health: number): number
	local healthConfig = Config.Health
	if health >= healthConfig.RiskHealth then
		return 0
	end
	local fall = (healthConfig.RiskHealth - health) / healthConfig.RiskHealth
	return healthConfig.BaseIllnessChance + fall * (healthConfig.MaxIllnessChance - healthConfig.BaseIllnessChance)
end

-- One birthday's worth of sickness, run in the right order: whatever the year had
-- is over first, then the new year gets its own chance to begin one. Recovery
-- restoring less than a sick year took is the whole shape of the loop -- a life that
-- falls ill pays a little each time until it either gets well or runs out of the
-- middle of the bar, and a life that keeps dropping faces a worse chance every year.
--
-- The flag is read and written here and nowhere else. StatService and WorkService
-- read it straight off the record to tax the year and the shifts -- they stay leaves
-- in the require graph -- while this is the only place it is ever set or cleared.
local function progressSickness(player: Player, data: LifeData)
	local healthConfig = Config.Health

	if data.flags.sick ~= nil then
		data.flags.sick = nil
		StatService.AddStat(player, "health", healthConfig.RecoverHealth)
		NoticeRemote:FireClient(player, "You got over it. Whatever it was, it's behind you now.")
	end

	if math.random() < illnessChanceAt(data.stats.health) then
		data.flags.sick = data.ageMonths // Config.Time.MonthsPerYear
		NoticeRemote:FireClient(player, "You're coming down with something. You feel hollow and feverish, and it isn't going anywhere fast.")
	end
end

local function ageYearsOf(data: LifeData): number
	return data.ageMonths // Config.Time.MonthsPerYear
end

-- Whether the given age falls inside one of the configured chapter bands.
local function bandIndexOf(ageYears: number): number
	for i, band in Config.Life.ChapterBands do
		if ageYears >= band[1] and ageYears <= band[2] then
			return i
		end
	end
	return #Config.Life.ChapterBands
end

-- Turn a moment into readable prose, anchored to the life's data.
--
-- Called by both the verdict (which wants up to three) and the chapter reel
-- (which wants all of them). Same function, same output — the spec calls it
-- the "single source" precisely because the two consumers must never diverge.
function LifeService.FormatMoment(moment: Moment, data: LifeData): string
	local ageYears = moment.ageMonths // Config.Time.MonthsPerYear
	if moment.kind == "flag" then
		return `At age {ageYears}, you {moment.id}`
	elseif moment.kind == "bond" then
		return `At age {ageYears}, you and {moment.id} grew close`
	elseif moment.kind == "grade" then
		return `At age {ageYears}, you did well in school`
	elseif moment.kind == "standing" then
		return `At age {ageYears}, you earned respect at {moment.id}`
	elseif moment.kind == "mastery" then
		return `At age {ageYears}, you mastered {moment.id}`
	elseif moment.kind == "job" then
		return `At age {ageYears}, you worked as a {moment.id}`
	elseif moment.kind == "house" then
		return `At age {ageYears}, you bought a home`
	elseif moment.kind == "gangRank" then
		return `At age {ageYears}, you rose in a gang`
	elseif moment.kind == "visit" then
		return `At age {ageYears}, you visited {moment.id}`
	elseif moment.kind == "confrontation" then
		return `At age {ageYears}, {moment.id}`
	elseif moment.kind == "age" then
		return `At age {ageYears}, you reached age {ageYears}`
	else
		return `At age {ageYears}, {moment.id}`
	end
end

-- The shared "what happened" query. One function feeds the chapter reel and the
-- end-of-life verdict; the two consumers pass different opts but the walk is the
-- same.
--
-- `sinceMonths` defaults to 0 (whole life) rather than nil, because a stored life
-- that predates the field gets reconciled to 0 and 0 means "start from birth" here.
-- `maxCount` and `kinds` gate the output; nil means "unlimited" / "all kinds".
function LifeService.Moments(data: LifeData, opts: {
	sinceMonths: number?,
	untilMonths: number?,
	maxCount: number?,
	kinds: { string }?,
}): { Moment }
	local sinceMonths = opts.sinceMonths or 0
	local untilMonths = opts.untilMonths or data.ageMonths
	local maxCount = opts.maxCount
	local allowedKinds = opts.kinds

	local results: { Moment } = {}

	local function emit(ageMonths: number, kind: string, id: string)
		if allowedKinds ~= nil and not table.find(allowedKinds, kind) then
			return
		end
		if ageMonths < sinceMonths then
			return
		end
		if ageMonths > untilMonths then
			return
		end
		local moment: Moment = {
			ageMonths = ageMonths,
			kind = kind,
			id = id,
			line = "",
		}
		moment.line = LifeService.FormatMoment(moment, data)
		table.insert(results, moment)
		if maxCount ~= nil and #results >= maxCount then
			return
		end
	end

	-- Flags: age is the value stored in the flag set.
	if not table.find(allowedKinds or {}, "flag") or allowedKinds == nil then
		for flagId, flagAgeMonths in data.flags do
			emit(flagAgeMonths, "flag", flagId)
		end
	end

	-- Bonds: age is the last-visited year for bonds >= 50.
	if allowedKinds == nil or table.find(allowedKinds, "bond") then
		for personId, bond in data.bonds do
			if bond >= 50 then
				local visit = data.visits[personId]
				local bondAgeMonths = visit ~= nil and ((visit.lastYear or 0) * Config.Time.MonthsPerYear) or data.ageMonths
				emit(bondAgeMonths, "bond", personId)
			end
		end
	end

	-- School grades: best and worst per year.
	if allowedKinds == nil or table.find(allowedKinds, "grade") then
		for _, year in data.schoolGrades do
			local ageMonths = (year.ageYears or 0) * Config.Time.MonthsPerYear
			if year.grade == "A" or year.grade == "B" then
				emit(ageMonths, "grade", "school")
			end
		end
	end

	-- Job standing: any standing at or above the band threshold.
	if allowedKinds == nil or table.find(allowedKinds, "standing") then
		for jobId, standing in data.jobStanding do
			emit(data.ageMonths, "standing", jobId)
		end
	end

	-- Subject mastery: level 5 mastery.
	if allowedKinds == nil or table.find(allowedKinds, "mastery") then
		for subject, level in data.subjectMastery do
			if level >= 5 then
				emit(data.ageMonths, "mastery", subject)
			end
		end
	end

	-- Current job.
	if allowedKinds == nil or table.find(allowedKinds, "job") then
		if data.jobId ~= nil then
			emit(data.ageMonths, "job", data.jobId)
		end
	end

	-- Houses owned.
	if allowedKinds == nil or table.find(allowedKinds, "house") then
		for houseId in data.houses.owned do
			emit(data.ageMonths, "house", houseId)
		end
	end

	-- Gang rank.
	if allowedKinds == nil or table.find(allowedKinds, "gangRank") then
		if data.gangRankId ~= nil then
			emit(data.ageMonths, "gangRank", data.gangRankId)
		end
	end

	-- Visits: proximity-driven NPC news, one per person.
	if allowedKinds == nil or table.find(allowedKinds, "visit") then
		for personId, visit in data.visits do
			local visitAgeMonths = (visit.lastYear or 0) * Config.Time.MonthsPerYear
			emit(visitAgeMonths, "visit", personId)
		end
	end

	-- Age milestones: every integer age.
	if allowedKinds == nil or table.find(allowedKinds, "age") then
		local startAge = sinceMonths // Config.Time.MonthsPerYear
		local endAge = untilMonths // Config.Time.MonthsPerYear
		for age = startAge, endAge do
			emit(age * Config.Time.MonthsPerYear, "age", tostring(age))
		end
	end

	-- Sort by age ascending.
	table.sort(results, function(a, b)
		return a.ageMonths < b.ageMonths
	end)

	return results
end

-- Whether there is a life here to run at all.
--
-- Gated on age rather than life stage: the player takes the wheel partway
-- through Childhood, at the point they could plausibly be choosing things for
-- themselves, not at the stage boundary years later.
local function isSelfDirected(data: LifeData): boolean
	return ageYearsOf(data) >= Config.ManualAgeUpMinAge
end

-- The earliest years run on a shorter timer because there is nothing for the
-- player to decide while they pass. Thresholds are authored in game hours and
-- converted here, so the day length is the only dial that moves them.
local function autoThresholdSeconds(data: LifeData): number
	local gameHours = if isSelfDirected(data) then Config.AutoAgeUpGameHours else Config.ChildAutoAgeUpGameHours
	return gameHours * Config.Time.RealSecondsPerGameHour
end

-- Single source of truth for the manual gate. The HUD renders whatever this
-- returns rather than re-deriving the rule, so the button can never offer an
-- action the server would refuse.
-- `livesLived` is passed in rather than read off the life, because it is the one thing this
-- rule needs that is a fact about the *player* rather than the person: how many lives have
-- been finished across every save slot. Threading it as an argument keeps this function
-- pure and testable, and keeps the account/life split visible at the call site instead of
-- buried behind a lookup.
local function manualState(data: LifeData, livesLived: number): ManualAgeUpState
	-- Unborn reads as Hidden exactly like dead does. The client hides the whole HUD behind
	-- the setup menu anyway, so this is the belt to that braces: a client that failed to
	-- hide it is holding a button the server will refuse rather than one that works.
	if not data.alive or not Lives.HasBegun(data) then
		return "Hidden"
	end

	if not isSelfDirected(data) then
		-- Once childhood has been lived at least once, skipping the rest of it
		-- in one action becomes the player's call. No cooldown applies: the
		-- counter is at zero on a fresh life, which is exactly when a
		-- returning player wants this button, and it takes priority over the
		-- per-year one below -- somebody who has already chosen "skip" is not
		-- also asking to click through five separate years to get there.
		if livesLived >= Config.SkipChildhoodMinLives then
			return "SkipChildhood"
		end
		-- Below the manual age is still played, not skipped -- see
		-- ChildManualAgeUpCooldownSeconds -- but there is no shift or lesson to
		-- sit through in these years, so a player who is done with a toddler
		-- year is not made to wait out the same clock a working adult does.
		if data.secondsSinceAgeUp < Config.ChildManualAgeUpCooldownSeconds then
			return "ChildCooldown"
		end
		return "ChildReady"
	end

	if data.secondsSinceAgeUp < Config.ManualAgeUpCooldownSeconds then
		return "Cooldown"
	end
	return "Ready"
end

local function pushProgress(player: Player, data: LifeData)
	-- Looked up here rather than added to this function's signature, so that all eight call
	-- sites stay as they were: every one of them already had the player, and none of them
	-- had any business knowing that the skip-childhood rule reads an account-level counter.
	--
	-- Falls back to zero if the profile has gone, which is the safe direction -- zero lives
	-- lived hides the skip button, and a player whose profile has unloaded mid-push should
	-- not be handed a control that acts on a life the server can no longer see.
	local profile = DataService.GetProfile(player)
	local livesLived = if profile ~= nil then profile.Data.livesLived else 0
	AgeUpProgressRemote:FireClient(
		player,
		data.secondsSinceAgeUp,
		autoThresholdSeconds(data),
		manualState(data, livesLived)
	)
end

function LifeService.GetAgeYears(player: Player): number?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return ageYearsOf(Lives.Active(profile.Data))
end

-- Public so the Studio debug harness can force a death without waiting on a
-- mortality roll. Safe to call on an already-dead player: the alive check
-- makes it a no-op, so a retried call cannot queue a second trip to the lobby
-- or count the same life twice in `livesLived`.
function LifeService.Die(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local dying = Lives.Active(profile.Data)
	if not dying.alive then
		return
	end

	dying.alive = false
	dying.stage = "Death"
	-- On the profile, not the life: it counts what the *player* has been through, and a life
	-- that reset its own counter would put every player permanently on their first.
	--
	-- Incremented here rather than at the start of the next life, which is where it used to
	-- sit, because there is no "next life" in this place any more. The lobby reads this number
	-- to say which life a card is about to be, and the lobby is where the player is going.
	profile.Data.livesLived += 1
	-- Whatever the world was holding out for this person goes with them, rather
	-- than sitting in the house through the death screen waiting for a collector
	-- who is never coming.
	DeliveryService.ResetForNewLife(player)
	-- And they stop working, for the plainest reason available. Before the death
	-- screen rather than with the rest of the reset below, because a shift left
	-- running would go on paying a corpse for the length of the respawn delay.
	WorkService.ResetForNewLife(player)
	-- Likewise, and for the sharper version of the same reason: a lesson left running
	-- would leave three answer pads breathing on a classroom floor through the death
	-- screen, waiting on somebody who is not coming back to them.
	SchoolService.ResetForNewLife(player)
	-- Likewise: a workout in progress would leave a sweep bar frozen on
	-- a dead body and a PUSH button that did nothing, so end it and clear
	-- the yearly caps.
	GymService.ResetForNewLife(player)
	-- Same reason, same shape: a drill session left running on a dead body is a
	-- sweep bar and a PUSH button belonging to nobody.
	SportsDrillService.ResetForNewLife(player)
	-- And the fight, which is the sharpest case of the lot. A bout left running would keep
	-- ticking against a dead player -- an opponent still winding up, still landing strikes,
	-- still taking footing off somebody who has no footing to lose -- and the death screen
	-- would come up with three live buttons under it. The opponent leaves with everything
	-- else; nothing is paid out, because the fight was not finished, it was interrupted.
	FightService.ResetForNewLife(player)
	-- And the room empties. Not for a mechanical reason -- nothing is left running --
	-- but because the death screen is read over the world behind it, and a mother
	-- standing in the doorway through her child's death would be the single worst frame
	-- this game could draw.
	PeopleService.ResetForNewLife(player)
	-- And whatever was parked outside waiting for them. A dead life driving itself
	-- around is the same frame as the room emptying above, one system further out:
	-- the car goes back to the lot rather than sitting in the street with nobody
	-- ever coming back to it.
	VehicleService.ResetForNewLife(player)
	-- And whatever was lying across the room waiting to be crawled to. Same reasoning
	-- as the room emptying: a lit pad still inviting a dead child somewhere is a worse
	-- frame than an empty floor.
	ChildhoodService.ResetForNewLife(player)
	-- And whoever was walking pocket money across the room to this person, who is no longer
	-- there to take it. This call used to sit in the rebirth below, clearing the ledger for a
	-- newborn; the ledger no longer needs clearing -- a new life is a new `Lives.New()` with an
	-- empty one -- but the delivery in flight still does, and a parent finishing a walk to a
	-- corpse is exactly the frame the rest of this teardown exists to prevent.
	PocketMoneyService.ResetForNewLife(player)
	pushProgress(player, dying)
	local ribbon = VerdictService.Compute(player)
	dying.verdict = ribbon
	PlayerDiedRemote:FireClient(player, ageYearsOf(dying), ribbon)

	-- And then they go back to the menu.
	--
	-- **The rebirth that used to live here is gone, and this is the change part 3 is for.**
	-- It wound this same life back to age zero, re-rolled its gender, reset six services and
	-- cleared `setup` so the character menu would draw itself over the town -- which meant a
	-- player had one life at a time, ever, and the moment it ended it was overwritten by the
	-- next one. There was no way to look back at who you had been, because nothing was kept.
	--
	-- Nothing is reset now. The dead life stays exactly as it died, in the slot it was lived
	-- in, and the lobby draws it on a card as a person with a name and an age they got to --
	-- the player deletes it when they are ready to use the slot for somebody else. All the
	-- resets that used to run here have moved to where a life actually begins, which is the
	-- lobby writing a new one into an empty slot: `Lives.New()` is the whole of it, because
	-- a brand-new life has nothing to clear.
	--
	-- The delay is the same one it always was: long enough to read the summary. What comes
	-- after it is a teleport instead of a newborn.
	task.delay(Config.Death.RespawnDelaySeconds, function()
		-- Bail out if the player's profile changed identity (e.g. rejoined), or if they have
		-- already pressed the button on the death screen themselves. Both leave the trip to
		-- somebody else; ReturnService's own in-flight stamp makes the second harmless anyway,
		-- but a refusal fired at a player mid-teleport is a message onto a screen that is
		-- already going away.
		if DataService.GetProfile(player) ~= profile or player.Parent ~= Players then
			return
		end
		ReturnService.Send(player)
	end)
end

-- Health reaching zero is lethal the moment it happens rather than at the next
-- birthday, otherwise a fatal injury could sit harmless for half an hour.
local function killIfOutOfHealth(player: Player): boolean
	local stats = StatService.GetStats(player)
	if stats ~= nil and stats.health <= 0 then
		LifeService.Die(player)
		return true
	end
	return false
end

-- The one and only way age advances. Public so the debug harness drives the
-- real path instead of a shortcut that could diverge from it.
function LifeService.AgeUp(player: Player, cause: AgeUpCause)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end

	local data = Lives.Active(profile.Data)
	if not data.alive then
		return
	end

	-- Banked time is spent before anything else can yield: a duplicate request
	-- arriving behind this one fails its cooldown check, so a retry (or a
	-- client firing the remote twice) cannot buy two years for one year's wait.
	data.secondsSinceAgeUp = 0
	data.ageMonths += Config.Time.MonthsPerYear

	local ageYears = ageYearsOf(data)

	-- Chapter break: the band changed. Compute moments since the last break and
	-- push them to the client so the reel can roll. A zero-moment break is still
	-- fired — the client suppresses the screen when the list is empty.
	local newBand = bandIndexOf(ageYears)
	local lastBreakYears = data.lastChapterBreakMonths // Config.Time.MonthsPerYear
	local lastBreakBand = bandIndexOf(lastBreakYears)
	if newBand ~= lastBreakBand then
		local moments = LifeService.Moments(data, {
			sinceMonths = data.lastChapterBreakMonths,
			maxCount = nil,
		})
		ChapterBreakRemote:FireClient(player, {
			ageMonths = data.ageMonths,
			moments = moments,
		})
		data.lastChapterBreakMonths = data.ageMonths
		data.pendingEventCountInChapter = 0
		-- Reset the world/modal ratio trackers for the new chapter, so the
		-- 70/30 budget is enforced per chapter rather than over the whole life.
		data.worldEventsThisChapter = 0
		data.modalEventsThisChapter = 0
		-- Reset autonomy points so the new chapter starts fresh: the player has
		-- to earn every ambient event again, which is the whole point of the gate.
		data.autonomyPoints = 0
	end

	StatService.ApplyYearlyDecay(player, ageYears)

	local newStage: LifeStageId = stageForAge(ageYears)
	if newStage ~= data.stage then
		data.stage = newStage
		LifeStageChangedRemote:FireClient(player, newStage)
	end

	-- A birthday is a change of body as much as a change of number: through
	-- childhood each year buys speed, height and eventually the ability to jump.
	BodyService.Apply(player)

	-- Anything the world was still holding out belonged to the year that just
	-- ended, so it goes with it -- and this is also what refills the year's
	-- allowance of ambient deliveries.
	DeliveryService.OnAgeUp(player)

	-- A new year of work to be had. Deliberately does not interrupt a shift in
	-- progress: a birthday at work is still a day at work.
	WorkService.OnAgeUp(player)

	-- And a new year of school, on the same terms -- except that this one also looks
	-- back. A school year nobody turned up to is charged for here, because not going
	-- is not something that happens at a place: it is something that turns out to have
	-- happened once the year is over, and a birthday is when a year is over.
	--
	-- After WorkService rather than before it for no reason beyond reading order: the
	-- two touch nothing in common, and a player cannot be at both.
	SchoolService.OnAgeUp(player)

	-- A new year of machines: the per-machine yearly caps reset, and any
	-- workout in progress is graded on the year it started in.
	GymService.OnAgeUp(player)

	-- A new year of stations: same reset, same reason, for the sports campus.
	SportsDrillService.OnAgeUp(player)

	-- And a year of everybody you did not go and see. Last of the three because it is
	-- the only one that looks purely backwards: work and school each hand out a fresh
	-- year's allowance as well, and this hands out nothing -- it just settles up.
	PeopleService.OnAgeUp(player)

	AgeUpdatedRemote:FireClient(player, ageYears, cause)
	pushProgress(player, data)

	-- A birthday is payday too, for as long as somebody else is doing the paying.
	--
	-- After the age has gone out, so the balance moves against a HUD already showing
	-- the new year -- being handed a ten-year-old's allowance while the screen still
	-- says nine is a small lie about why the number went up. Before the death rolls,
	-- because the birthday happened: a year that turns out to be your last still had
	-- a birthday in it, and if it does kill you the money is cleared with everything
	-- else a moment later anyway.
	--
	-- Runs on skipped years as well, and deliberately. A skipped year passes unlived
	-- and so offers no event, but it is still a birthday, and pocket money is not a
	-- prompt -- a childhood skipped for the second time should not also be a
	-- childhood unpaid.
	PocketMoneyService.OnAgeUp(player)

	-- Bills are due every birthday. They run after pocket money so a life that
	-- cannot afford them falls into debt rather than being patched over by
	-- childhood allowance.
	-- rather than being patched over by childhood allowance.
	BillService.Charge(player)
	SavingsService.CreditInterest(player)

	-- Milestone age checks run after the age has moved and bills are settled, so a
	-- life that died from debt cannot also score the longevity bonus.
	MilestoneService.OnAgeUp(player, ageYears)

	if killIfOutOfHealth(player) then
		return
	end
	if rollNaturalDeath(ageYears) then
		LifeService.Die(player)
		return
	end

	-- One birthday's worth of sickness: recovery, then a roll for the new year. Runs
	-- on skipped years too, and for the same reason decay does -- a skipped year is
	-- still a year the body lives, and skipping should not let a life dodge the
	-- recovery that is its only way off the tax.
	progressSickness(player, data)

	-- Last, so a year that killed the player never also hands them a prompt.
	-- Skipped years pass unlived by definition, so they don't offer one either.
	if cause == "Skip" then
		return
	end

	if cause == "Event" then
		-- This birthday was caused by answering an event, so offering the next
		-- one immediately would chain prompt straight into prompt. Wait, and let
		-- the player be a child for a moment. OfferForAge re-reads the profile,
		-- so dying, leaving or rejoining inside the gap all resolve correctly.
		task.delay(Config.Childhood.NextEventDelaySeconds, function()
			-- Re-read rather than closing over ageYears: a death and respawn, or
			-- the auto safety net, can move the age inside the gap, and the offer
			-- has to match the age the player actually is when it lands.
			local current = DataService.GetProfile(player)
			if current == nil then
				return
			end
			EventService.OfferForAge(player, ageYearsOf(Lives.Active(current.Data)))
		end)
	else
		EventService.OfferForAge(player, ageYears)
	end
end

-- Crosses the yearless early years in one action, for players who have already
-- lived them at least once. It runs the ordinary per-year path rather than
-- writing ageMonths directly, so the skipped years still decay stats and cross
-- stage boundaries exactly as if they had been played. Bounded by construction:
-- at most one iteration per year being skipped.
local function skipChildhood(player: Player, data: LifeData)
	for _ = 1, Config.ManualAgeUpMinAge do
		if not data.alive or isSelfDirected(data) then
			break
		end
		LifeService.AgeUp(player, "Skip")
	end

	-- Anything offered at the start of this life belonged to the years just
	-- skipped, so it goes with them.
	EventService.ClearPending(player)
	pushProgress(player, data)

	if data.alive then
		EventService.OfferForAge(player, ageYearsOf(data))
	end
end

-- Only time spent in the server counts toward the safety net, and the counter
-- lives in the profile, so leaving mid-year banks progress rather than losing
-- or farming it.
local function bankPlaytime(elapsedSeconds: number)
	for _, player in Players:GetPlayers() do
		local profile = DataService.GetProfile(player)
		-- The gate. A player still choosing their name banks nothing -- not a partial
		-- second, not a health check -- so the menu can be read at whatever speed the
		-- player reads at. This is the line that makes setup a decision rather than a
		-- timed one.
		if profile == nil then
			continue
		end

		local data = Lives.Active(profile.Data)
		if not data.alive or not Lives.HasBegun(data) then
			continue
		end
		data.secondsSinceAgeUp += elapsedSeconds

		if killIfOutOfHealth(player) then
			continue
		end

		if data.secondsSinceAgeUp >= autoThresholdSeconds(data) then
			LifeService.AgeUp(player, "Auto")
		else
			pushProgress(player, data)
		end
	end
end

local function onAgeUpRequested(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		-- Fired before the profile finished loading, or after it was released.
		-- There is nothing to validate against, so refuse rather than guess.
		return
	end

	local data = Lives.Active(profile.Data)
	-- livesLived threaded from the profile exactly as pushProgress does it: manualState
	-- takes it as an argument, and the account-level counter lives on the profile we
	-- already hold here. Passing it (rather than leaving it nil) is the whole fix -- the
	-- skip-childhood branch compares livesLived against a number, so a nil argument threw
	-- and every age-up request died silently, stranding a freshly skipped life at age 0.
	local state = manualState(data, profile.Data.livesLived)

	if state == "SkipChildhood" then
		skipChildhood(player, data)
		return
	end

	if state ~= "Ready" and state ~= "ChildReady" then
		-- Refused: dead, or inside whichever cooldown applies to this age.
		-- Re-push the authoritative state so a desynced or hostile client's
		-- button immediately snaps back to what the server actually allows.
		pushProgress(player, data)
		return
	end

	LifeService.AgeUp(player, "Manual")
end

-- The moment a life actually starts: the setup is written, so everything that was waiting
-- on it goes.
--
-- Lives here rather than in SetupService because it is the tail of what a rebirth used to
-- do inline, and splitting a life's first moment across two files by *where the trigger*
-- came from would mean a life begun on join and a life begun after a death screen opened
-- differently. SetupService calls it through a handler for the same reason EventService
-- gets its age-up handler that way: requiring back the other direction closes a cycle.
local function beginLife(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)
	local ageYears = ageYearsOf(data)

	-- Re-applied even though the rebirth already did it, because the *other* way into this
	-- function is a fresh join, where nothing has applied a body at all.
	BodyService.Apply(player)
	AgeUpdatedRemote:FireClient(player, ageYears, "Sync" :: AgeUpCause)
	LifeStageChangedRemote:FireClient(player, data.stage)
	pushProgress(player, data)

	-- A new life opens on its first moment rather than on an empty year. This is the line
	-- that moved out of the rebirth block: the first decision of a life now arrives after
	-- the player has decided whose life it is.
	EventService.OfferForAge(player, ageYears)
end

local function pushInitialState(player: Player)
	local profile = DataService.WaitForProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)
	-- Nothing to describe. A slot with no setup in it is not a life yet, and ReturnService is
	-- already sending this player back to the lobby to fill one -- pushing an age and a stage
	-- at them on the way out would raise a HUD over a world they are leaving.
	if not Lives.HasBegun(data) then
		return
	end
	local ageYears = ageYearsOf(data)
	AgeUpdatedRemote:FireClient(player, ageYears, "Sync" :: AgeUpCause)
	LifeStageChangedRemote:FireClient(player, data.stage)
	pushProgress(player, data)

	-- **The first moment of a life created in the lobby, and the one thing arriving here does
	-- that a rejoin must not.** Before part 3 this line was not needed: every life was born in
	-- this place, so `beginLife` always ran and always offered age zero. A life is now written
	-- on the other side of a teleport, so the player walks in already begun and the opening
	-- event has nobody to offer it.
	--
	-- Gated on having seen nothing and having nothing pending, which is what makes it safe to
	-- run on *every* arrival: a player rejoining at forty has a seen list behind them, so this
	-- does nothing, and one who disconnected mid-decision has that decision still pending and
	-- gets it back rather than a second one. Only a life that has genuinely not started yet
	-- passes both tests, and it can only pass them once.
	if data.pendingEventId == nil and next(data.seenEventIds) == nil then
		EventService.OfferForAge(player, ageYears)
	end
end

function LifeService:Init()
	RequestAgeUpRemote.OnServerEvent:Connect(onAgeUpRequested)
	-- Handed over rather than required the other way around: EventService cannot
	-- require this module without closing a dependency cycle.
	EventService.SetAgeUpHandler(LifeService.AgeUp)
	-- Same device, same reason. SetupService writes the setup and this runs the moment
	-- after, which is the moment a life starts.
	SetupService.SetBeginHandler(beginLife)
	-- VerdictService needs the shared moments query but requiring it here would
	-- close a cycle. The setter below threads it in after both modules are loaded.
	VerdictService.SetMoments(LifeService.Moments)
end

function LifeService:Start()
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(pushInitialState, player)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(pushInitialState, player)
	end

	task.spawn(function()
		while true do
			-- task.wait returns the time that actually elapsed, so a hitching
			-- server banks real seconds instead of drifting behind.
			local elapsed = task.wait(Config.AgeUpProgressTickSeconds)
			bankPlaytime(elapsed)
		end
	end)
end

return LifeService
