--!strict
-- What Science actually asks you to do.
--
-- The procedures that send you round the lab. The stations themselves are furniture
-- rather than content and live in `shared/world/Stations.luau`, because the client has
-- to be able to name and colour one; this file is the list of *errands*, and it is
-- content in the same sense Lessons.luau is.
--
-- A table rather than code for the reason Lessons.luau gives -- the thing that has to
-- stay cheap is writing another one. A procedure is six lines here and never touches
-- the loop that runs it.
--
-- A procedure is an *ordered* list of stations, and the order is the entire test. That
-- is what makes this a different activity from a quiz rather than a quiz you walk: a
-- question has one right answer and you either have it or you do not, where a procedure
-- has a right answer you can be half-way to. Wash before you weigh and you have made a
-- specific, nameable mistake with a specific cost, and the score says which one.
--
-- Rules the content follows, all of them for mechanical reasons rather than scientific
-- ones:
--
--   No station twice in a row. Two identical clicks in a row is a step the player takes
--   without moving, and a step you can take without moving is not a step -- it is the
--   idle-payout-pad anti-pattern hiding inside a good mechanic. The same station may
--   appear twice in a procedure, just never adjacently: coming *back* to the balance is
--   a real trip and a real thing to forget.
--
--   Every procedure is doable in any order without being *right* in any order. There
--   are no steps that physically cannot be done out of sequence, because a step the
--   game refuses to let you take wrong is a step with no decision in it. Getting it
--   wrong has to be possible and has to cost something short of a fail.
--
--   The science is real enough to be worth knowing and never the difficulty. A player
--   who has never held a pipette should be able to read the board and do it; the
--   challenge is the room, the clock and the other bench, not domain knowledge. School
--   here teaches by having you do a correct thing, not by testing whether you already
--   knew it -- same principle as a question's `because` line.
--
--   Nothing here involves fire, blades, anything a child should not copy, or a result
--   that goes bang. Thirteen-plus is a hard ceiling and a chemistry set is exactly the
--   place a game drifts through it without noticing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Stations = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Stations"))

type Procedure = Types.Procedure

local Procedures = {}

-- Authoring limits, from Config rather than restated so the limit the author writes
-- against and the limit the lab enforces can never drift.
local MAX_STEPS = Config.School.Science.MaxSteps
local MIN_STEPS = Config.School.Science.StepsMin
local MAX_LABEL = Config.School.Science.MaxStepLabelLength

-- Written as an instruction to somebody standing in the room, because that is what it
-- is: one line, present tense, and short enough to read off a board without stopping.
local SOURCE: { Procedure } = {
	-- The first one a nine-year-old sees. Four steps, no station repeated, and an order
	-- with an obvious reason behind it -- you cannot record a mass you have not measured
	-- -- so the first procedure teaches that order is the point without having to say so.
	{
		id = "measure_salt",
		name = "Measure out a spoon of salt",
		steps = {
			{ station = "scale_paper", label = "Take a square of paper" },
			{ station = "balance", label = "Zero the balance" },
			{ station = "beaker", label = "Spoon salt from the jar" },
			{ station = "notebook", label = "Write the mass down" },
		},
		minAge = 9,
		maxAge = 12,
	},
	-- Five steps and the first repeats: the sink at both ends and the notebook either
	-- side of the microscope. A player who reads three steps at a time meets the second
	-- wash without remembering the first, which is the exact moment mastery starts being
	-- worth something.
	--
	-- Looking down the microscope is deliberately *one* step rather than a set-it-down
	-- and a focus-it. Two microscope steps back to back read as two things to do and are
	-- one place to stand, which is the no-station-twice-in-a-row rule in the header: the
	-- second click would be a step taken without moving.
	{
		id = "clean_slide",
		name = "Prepare a clean slide",
		steps = {
			{ station = "sink", label = "Rinse the slide" },
			{ station = "notebook", label = "Label it with the date" },
			{ station = "microscope", label = "Set it on the stage" },
			{ station = "notebook", label = "Sketch what you can see" },
			{ station = "sink", label = "Rinse your hands after" },
		},
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "dissolve_sugar",
		name = "Find out how fast sugar dissolves",
		steps = {
			{ station = "beaker", label = "Half fill the beaker" },
			{ station = "balance", label = "Weigh out the sugar" },
			{ station = "beaker", label = "Tip the sugar in" },
			{ station = "stirrer", label = "Stir at a steady count" },
			{ station = "notebook", label = "Record how long it took" },
		},
		minAge = 10,
		maxAge = 14,
	},
	-- Six steps, and the first where an out-of-order run is a *nameable* mistake rather
	-- than just a wrong one: heat before you have measured and the number you write down
	-- is not the number you meant to take. The verdict line says so.
	{
		id = "warm_water",
		name = "Warm water and watch the thermometer",
		steps = {
			{ station = "beaker", label = "Fill the beaker halfway" },
			{ station = "notebook", label = "Note the temperature" },
			{ station = "burner", label = "Set it on the hot plate" },
			{ station = "stirrer", label = "Stir it while it warms" },
			{ station = "notebook", label = "Note the temperature again" },
			{ station = "sink", label = "Cool it under the tap" },
		},
		minAge = 11,
		maxAge = 15,
	},
	{
		id = "grow_crystal",
		name = "Start a salt crystal growing",
		steps = {
			{ station = "scale_paper", label = "Take a square of paper" },
			{ station = "balance", label = "Weigh out the salt" },
			{ station = "beaker", label = "Add warm water" },
			{ station = "stirrer", label = "Stir until it clears" },
			{ station = "notebook", label = "Date the jar" },
			{ station = "microscope", label = "Look at a seed grain" },
		},
		minAge = 12,
		maxAge = 17,
	},
	-- Seven and eight steps. These only appear late, and by design they are unreadable
	-- three-at-a-time: at mastery one this procedure is four trips to the board, and at
	-- mastery five it is one. That gap is the whole progression, and it is why the long
	-- procedures exist at all.
	{
		id = "filter_mixture",
		name = "Separate sand from salty water",
		steps = {
			{ station = "beaker", label = "Stir the mixture up" },
			{ station = "stirrer", label = "Let the sand settle" },
			{ station = "sink", label = "Pour the water off" },
			{ station = "balance", label = "Weigh what is left" },
			{ station = "burner", label = "Dry the sand off gently" },
			{ station = "balance", label = "Weigh it dry" },
			{ station = "notebook", label = "Write both masses down" },
		},
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "compare_samples",
		name = "Compare two soil samples",
		steps = {
			{ station = "scale_paper", label = "Two squares of paper" },
			{ station = "balance", label = "Weigh the first sample" },
			{ station = "microscope", label = "Look at the first" },
			{ station = "notebook", label = "Write what you saw" },
			{ station = "balance", label = "Weigh the second" },
			{ station = "microscope", label = "Look at the second" },
			{ station = "notebook", label = "Write the difference" },
			{ station = "sink", label = "Wash the trays" },
		},
		minAge = 14,
		maxAge = 17,
	},
}

-- Everything below runs at require time and errors by name. A procedure that names a
-- missing station, or repeats one adjacently, is not a thing to discover in a playtest:
-- the first is a step the player can never take and the second is a step they take
-- without moving, and both look like the lab is broken rather than the content is.
local byId: { [string]: Procedure } = {}
for _, procedure in SOURCE do
	if byId[procedure.id] ~= nil then
		error(`[AGES content] duplicate procedure id "{procedure.id}"`)
	end
	local count = #procedure.steps
	if count < MIN_STEPS or count > MAX_STEPS then
		error(
			`[AGES content] procedure "{procedure.id}" has {count} steps, outside {MIN_STEPS}-{MAX_STEPS}.`
				.. ` Change the steps or Config.School.Science.StepsMin/MaxSteps.`
		)
	end
	if procedure.minAge > procedure.maxAge then
		error(
			`[AGES content] procedure "{procedure.id}" has minAge {procedure.minAge} above maxAge`
				.. ` {procedure.maxAge} -- it would never be offered. Swap them.`
		)
	end
	local previous: string? = nil
	for index, step in procedure.steps do
		if Stations.Get(step.station) == nil then
			error(
				`[AGES content] procedure "{procedure.id}" step {index} names station "{step.station}",`
					.. ` which is not in shared/world/Stations.luau. Add the station or fix the name.`
			)
		end
		if step.station == previous then
			error(
				`[AGES content] procedure "{procedure.id}" uses station "{step.station}" twice in a row at`
					.. ` step {index}. That is a step the player takes without moving. Put another station`
					.. ` between them or merge the two labels.`
			)
		end
		if #step.label > MAX_LABEL then
			error(
				`[AGES content] procedure "{procedure.id}" step {index} label is {#step.label} characters,`
					.. ` over Config.School.Science.MaxStepLabelLength ({MAX_LABEL}). It is one row of a list`
					.. ` read across a room -- shorten it.`
			)
		end
		previous = step.station
	end
	byId[procedure.id] = procedure
end

-- Every procedure must be reachable in some school year, or it is content nobody will
-- ever see -- which is the same defect as a question written outside the age bands, and
-- just as invisible.
for _, procedure in SOURCE do
	if procedure.maxAge < Config.School.StartAge or procedure.minAge > Config.School.EndAge then
		error(
			`[AGES content] procedure "{procedure.id}" is offered between {procedure.minAge} and`
				.. ` {procedure.maxAge}, entirely outside the school years. It would never be run.`
		)
	end
end

-- The procedures a life of this age can be given. Never empty inside the ages Science
-- is taught over -- Curriculum's band for science is 9 to EndAge, and the entries above
-- cover it -- but the caller still handles empty, because content edits are exactly how
-- that stops being true.
function Procedures.ForAge(age: number): { Procedure }
	local out: { Procedure } = {}
	for _, procedure in SOURCE do
		if age >= procedure.minAge and age <= procedure.maxAge then
			table.insert(out, procedure)
		end
	end
	return out
end

-- Nil for an id that is no longer authored. Callers holding an id from a saved profile
-- must handle that -- a procedure deleted from content is one a live life may be
-- part-way through, and erroring here would lock that life out of the lab.
function Procedures.Get(id: string): Procedure?
	return byId[id]
end

Procedures.All = SOURCE

return Procedures
