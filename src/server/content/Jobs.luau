--!strict
-- The jobs that exist. Two, and they are the two ends of the building we already
-- put on the street: the shop floor is on the ground and the office is up the
-- stairs, so the career ladder is a literal staircase the player has to be old
-- enough to climb.
--
-- Salaries are authored yearly and only yearly. What a shift pays and what an
-- hour pays are divided out of this at the point of use, against
-- Config.Work.YearGameHours, so there is exactly one number here to argue about
-- and no second one to fall out of step with it.
--
-- The scale to judge them against is the note above Config.PocketMoney: a whole
-- childhood of allowance comes to somewhere near seven thousand, and that same
-- note puts a teenager doing nothing at about 2,400 a year before their allowance
-- would start out-earning a first job. So a first job pays 2,400 -- worth having,
-- not life-changing -- and adult work pays 8,000, which is the first income in a
-- life that is actually a living.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

-- Content asking content a question. The only thing this wants from People is whether
-- the person a job names as a reference actually exists, and that has to be answered at
-- load: a vouch pointing at nobody is a second route into a job that quietly never opens.
local People = require(script.Parent.People)

type Job = Types.Job

local SOURCE: { Job } = {
	{
		id = "shop_assistant",
		title = "Shop assistant",
		-- The shop floor, downstairs, where the tills and the aisles are.
		placeId = "store",
		-- Sixteen, which is the age this whole system was specified around: the
		-- first year you can trade your time for money instead of being given it.
		minAge = 16,
		yearlySalary = 2400,
	},
	{
		id = "office_clerk",
		title = "Office clerk",
		-- Upstairs, through the stairwell we measured headroom on.
		placeId = "office",
		minAge = 18,
		yearlySalary = 8000,
		-- The staircase is the career, and this is the handrail. Turning eighteen is
		-- not enough on its own: the office wants to know what the shop floor made of
		-- you, which is the difference between a career and a birthday.
		--
		-- Six is the bottom of "well thought of" -- three or four shifts answered like
		-- someone who cared, or a full year of simply turning up and doing it. Priced
		-- so that a player who worked at sixteen walks up the stairs at eighteen and
		-- finds the door open, and a player who spent two years walking out early
		-- finds it shut and knows exactly why.
		requires = { jobId = "shop_assistant", standing = 6 },
		-- What school was for, and the only place in the game that reads smarts.
		--
		-- Priced off what a childhood actually does to the number. Everyone starts at
		-- 50. Twelve years of sitting lessons and answering most of them puts a child
		-- somewhere near the ceiling; twelve years of never turning up costs two a year
		-- and leaves them in the twenties. Sixty is set just above the line a player
		-- who did nothing could reach by standing still, and well below what anybody who
		-- went at all will have -- five good lessons out of a possible thirty-six clears
		-- it. It is not a wall for the diligent. It is a door that is shut, at eighteen,
		-- for the player who spent their childhood elsewhere, and the game will have
		-- told them the number on the office window for years by then.
		minSmarts = 60,
		-- And the way in that is not a classroom.
		--
		-- Mr. Alderman stands outside the shop the ladder starts at, and this is what
		-- twenty years of being decent to him is worth: he knows the office, and if he
		-- thinks well enough of you he says so. Forty-five is "close" -- roughly a decade
		-- of turning up -- and fifteen brings the bar down to forty-five smarts, which is
		-- a childhood with some school in it rather than none.
		--
		-- Priced so it is a second route and never a shortcut. A player who skipped every
		-- lesson lands in the twenties and is still short even with him vouching, so the
		-- door does not open on friendship alone; a player who went occasionally and knew
		-- their neighbor gets in where either on its own would not have been enough. That
		-- is the whole reason both systems exist in the same childhood.
		vouch = { personId = "neighbor", minBond = 45, worthSmarts = 15 },
	},
	{
		id = "manager",
		title = "Manager",
		-- Same building, different floor. The manager's office is upstairs from
		-- the clerk's, with a door that does not open until the office has had
		-- enough of you to trust you with the rest.
		placeId = "office",
		-- Two years of proving the clerk was not a fluke. Standing 14 is "relied
		-- on" -- four good shifts a year for three years, or two years of simply
		-- turning up and doing it properly.
		minAge = 20,
		-- Double the clerk. The first salary in the game that changes what a life
		-- looks like rather than what a week feels like.
		yearlySalary = 16000,
		-- The standing gate is the real door. Fourteen is the band where the office
		-- knows your name and what you can do. No vouch here: the office has had
		-- two years to make up its mind, and a word from someone outside it does
		-- not carry further than that.
		requires = { jobId = "office_clerk", standing = 14 },
		-- The top of what a childhood with some school in it reaches, and well
		-- below what a childhood full of it produces. The manager has to read a
		-- budget and talk to a client, which is not the same as being clever but
		-- is close enough that the number sits here rather than lower.
		minSmarts = 75,
	},
	{
		id = "bakery",
		title = "Baker",
		-- The bread shop down the far street, and the second door a sixteen-year-old
		-- can walk through. Same rung as the shop assistant on purpose: the first
		-- job in a life should be a choice between two rooms, not a single sentence.
		placeId = "bakery",
		minAge = 16,
		-- The same wage as the shop floor, for the same reason: what the first job
		-- teaches is that you are worth something, not what you are worth.
		yearlySalary = 2400,
	},
	{
		id = "librarian",
		title = "Librarian",
		-- The reading room up the far road. The smarts route out of the bakery: it
		-- pays more than the shop's office door for less standing, because the thing
		-- it is really asking for is that school happened.
		placeId = "library",
		minAge = 18,
		yearlySalary = 6000,
		-- Five is "well thought of" -- a single year of turning up at the bakery and
		-- doing the job. The ladder is two years long here rather than the office's
		-- three, because a baker's trade is smaller than a shop floor's and this is
		-- the quiet rung, not the top.
		requires = { jobId = "bakery", standing = 5 },
		-- The line school was always drawing. Fifty-five is a childhood with most
		-- of its lessons in it -- well clear of the twenty-somethings who never went,
		-- and below what a diligent child clears before they are fifteen. A librarian
		-- is not a genius. They are somebody who reads, which is close enough.
		minSmarts = 55,
	},
	{
		id = "mechanic",
		title = "Mechanic",
		-- The garage on the far side of the bakery, and the practical route out of
		-- it: the same standing door the librarian walks through, opened instead by
		-- working hands. This is the route that keeps a life whose smarts never
		-- reached the library's bar from ending at sixteen.
		placeId = "garage",
		minAge = 18,
		yearlySalary = 6400,
		requires = { jobId = "bakery", standing = 5 },
		-- Where the practical route lives. Forty-five is a childhood with a bit of
		-- school in it rather than none -- nobody who skipped every lesson for a
		-- decade clears it -- but it is well below the library's bar, because the
		-- garage will take the hands it is offered and train the rest.
		minSmarts = 45,
		-- The ladder man vouches, in a way that rhymes with his own story. Mr.
		-- Alderman's gutter comes away in summer and he holds no ladder steady, but
		-- he knows who keeps this town's cars and its rooflines working, and if he
		-- thinks well enough of you he says so. Worth less than his word to the
		-- office -- fifteen years of seeing you about the street is not the same as
		-- recommending you for the room where the money is -- but it will pull a
		-- player who half-went to school over the garage's lower line.
		vouch = { personId = "neighbor", minBond = 40, worthSmarts = 12 },
	},
	{
		id = "gym_instructor",
		title = "Gym instructor",
		-- The gym at the north end, and the only job in the game that is earned as
		-- much in the body as on the record. It sits off the mechanic's rung because
		-- the garage is where this town's physical work already happened; this is
		-- where it starts being paid to happen to other people.
		placeId = "gym",
		minAge = 20,
		yearlySalary = 8000,
		-- Ten is "relied on" -- roughly two good years at the garage. Being asked to
		-- run a room full of people who are hurting on purpose requires having done
		-- that yourself for a while.
		requires = { jobId = "mechanic", standing = 10 },
		-- Below the library's and clinic's bars, because the gym does not need to
		-- read a budget. It needs somebody who knows a movement from a mistake, and
		-- the way this game checks for that is that school happened at all.
		minSmarts = 50,
	},
	{
		id = "clinic_assistant",
		title = "Clinic assistant",
		-- The clinic on the south road. The top of the services row and the care
		-- route: the best-paid job in the game that does not sit upstairs in the
		-- office, and the one that asks the most of a childhood.
		placeId = "clinic",
		minAge = 20,
		yearlySalary = 12000,
		-- Twelve is "relied on" at the library -- two years of being the quiet rung
		-- this ladder is built on. There is no vouch and no shortcut: the clinic
		-- takes the people the library proved it could trust with other people's
		-- information, which is most of what a waiting room is.
		requires = { jobId = "librarian", standing = 12 },
		-- The top of what a childhood produces outside the office. Sixty-five is a
		-- childhood with most of its lessons in it and a library career on top, and
		-- it is the one bar on this row that a player who skipped school simply
		-- cannot reach from the bakery -- which is the point of the row.
		minSmarts = 65,
	},
}

local all: { Job } = {}
local byId: { [string]: Job } = {}

-- Content mistakes are authoring bugs, not runtime conditions, so these throw at
-- start rather than producing a job that quietly pays nothing and is never missed.
local function validate(job: Job)
	if byId[job.id] ~= nil then
		error(`[AGES content] duplicate job id "{job.id}"`)
	end
	if job.title == "" then
		error(`[AGES content] job "{job.id}" has no title; it is what the player is told they do`)
	end
	if job.placeId == "" then
		error(`[AGES content] job "{job.id}" names no place, so there is nowhere to clock on`)
	end
	if job.minAge < 0 then
		error(`[AGES content] job "{job.id}" has a negative minimum age`)
	end

	-- Whole units above zero. A salary of zero is a job that pays nothing, which
	-- is a content mistake rather than a design; a fractional one would be rounded
	-- somewhere downstream and silently stop adding up to the figure authored here.
	if job.yearlySalary <= 0 or job.yearlySalary ~= math.floor(job.yearlySalary) then
		error(`[AGES content] job "{job.id}" pays {job.yearlySalary} a year; a salary must be a whole number above zero`)
	end

	-- A smarts gate has to sit inside the range smarts can actually take, or it is a
	-- door with no key: above the ceiling nobody clears it however hard they worked,
	-- and at or below the floor everybody does and the gate is decoration.
	local minSmarts = job.minSmarts
	if minSmarts ~= nil then
		local stats = Config.Stats
		if minSmarts <= stats.Min or minSmarts > stats.Max then
			error(
				`[AGES content] job "{job.id}" asks for {minSmarts} smarts; it must be above the floor of `
					.. `{stats.Min} and no more than the ceiling of {stats.Max}`
			)
		end
	end

	local vouch = job.vouch
	if vouch ~= nil then
		if People.ById[vouch.personId] == nil then
			error(`[AGES content] job "{job.id}" is vouched for by "{vouch.personId}", who is not a person`)
		end
		-- A vouch with no bar to lower is a field that does nothing, which is worse than
		-- a missing feature: it reads as a route into the job that silently is not one.
		if minSmarts == nil then
			error(`[AGES content] job "{job.id}" has a vouch but asks for no smarts, so there is nothing to lower`)
		end
		local people = Config.People
		if vouch.minBond <= people.MinBond or vouch.minBond > people.MaxBond then
			error(
				`[AGES content] job "{job.id}" wants a bond of {vouch.minBond}, which is either below the `
					.. `floor of {people.MinBond} -- so everybody is vouched for -- or above the ceiling of `
					.. `{people.MaxBond}, so nobody ever is`
			)
		end
		-- Has to move the bar and must not move it to the floor. The first would be a
		-- reference nobody notices; the second a job that could be had on a friendship
		-- and no education at all, which is exactly what the bar is there to prevent.
		if vouch.worthSmarts <= 0 or minSmarts - vouch.worthSmarts <= Config.Stats.Min then
			error(
				`[AGES content] job "{job.id}" values a word from "{vouch.personId}" at {vouch.worthSmarts} `
					.. `smarts against a bar of {minSmarts}; it must be worth something and must leave a bar behind`
			)
		end
	end

	-- The one check that earns its keep. An hour's pay is the salary divided by the
	-- year's game hours, and that division has to come out whole or every hour
	-- worked pays a rounded figure and a full year of work quietly fails to add up
	-- to the salary printed above -- by a few dollars, invisibly, forever.
	if job.yearlySalary % Config.Work.YearGameHours ~= 0 then
		error(
			`[AGES content] job "{job.id}" pays {job.yearlySalary} a year, which does not divide evenly `
				.. `by the {Config.Work.YearGameHours} game hours in a working year; `
				.. `a year of work would not add up to the salary`
		)
	end
end

for _, job in SOURCE do
	validate(job)
	byId[job.id] = job
	table.insert(all, job)
end

-- Prerequisites are checked in a second pass, because a job is allowed to require
-- one declared below it and the first pass has only seen what came before.
local function validateRequirement(job: Job)
	local requirement = job.requires
	if requirement == nil then
		return
	end

	if requirement.jobId == job.id then
		error(`[AGES content] job "{job.id}" requires standing at itself, which cannot be earned without it`)
	end

	local prerequisite = byId[requirement.jobId]
	if prerequisite == nil then
		error(`[AGES content] job "{job.id}" requires "{requirement.jobId}", which is not a job`)
	end

	-- Above the floor, or the requirement is met by everyone who has never worked a
	-- day and the gate is decoration. At or below the ceiling, or it can never be
	-- met by anyone and the job is unreachable -- which at runtime looks exactly
	-- like a door that is simply broken.
	local standing = Config.Work.Standing
	if requirement.standing <= 0 or requirement.standing > standing.Max then
		error(
			`[AGES content] job "{job.id}" requires standing {requirement.standing} at `
				.. `"{requirement.jobId}"; it must be above 0 and no more than the ceiling of {standing.Max}`
		)
	end

	-- A job you can only qualify for by already holding something further up the
	-- ladder is a job nobody can ever reach. Walked rather than checked one deep,
	-- because a three-job loop is just as unreachable and far harder to spot by eye.
	local seen: { [string]: boolean } = { [job.id] = true }
	local step: Job? = prerequisite
	while step ~= nil do
		if seen[step.id] then
			error(`[AGES content] job "{job.id}" sits in a loop of requirements, so nothing in it can ever be taken`)
		end
		seen[step.id] = true
		local nextRequirement = step.requires
		step = if nextRequirement ~= nil then byId[nextRequirement.jobId] else nil
	end
end

local hasEntryPoint = false
for _, job in all do
	validateRequirement(job)
	if job.requires == nil then
		hasEntryPoint = true
	end
end

-- Somewhere there has to be a job that asks nothing of you but your age, or the
-- ladder has no bottom rung and no player can ever start working at all. The one
-- content mistake here that would leave a completely silent game: no errors, no
-- warnings, just a world where clocking on never happens anywhere.
if not hasEntryPoint then
	error("[AGES content] every job requires standing at another one; there is no job anybody could take first")
end

local Jobs = {
	All = all,
	ById = byId,
}

-- What one game hour of this job pays, in whole units. The only place a salary is
-- ever divided, so the arithmetic exists once.
function Jobs.HourlyRate(job: Job): number
	return job.yearlySalary // Config.Work.YearGameHours
end

-- The lowest age at which any job at all can be held. Read off the content rather
-- than written down a second time in Config, so adding a job for a younger worker
-- moves it automatically.
function Jobs.MinimumWorkingAge(): number
	local lowest = math.huge
	for _, job in all do
		lowest = math.min(lowest, job.minAge)
	end
	return lowest
end

return Jobs
