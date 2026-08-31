--!strict
-- The timetable. Which subjects exist, what each one asks of you, and -- the only line
-- here that is load-bearing -- which *verb* each one runs.
--
-- Content data, not system code. Adding a subject is an entry in the list below; giving
-- an existing subject a real verb is one word changed on its row plus the service that
-- implements the verb. That split is the whole point of the file: the timetable should
-- not have to be rewritten every time a subject stops being a quiz.
--
-- The model is Bully's. A subject is not a topic with questions attached, it is a
-- different thing you do with your hands, and two subjects that share a verb are the
-- same activity wearing two names. That is a design failure, not a content gap, so
-- every row still reading `verb = "quiz"` below is a debt with a date on it rather than
-- a finished subject -- see the note on SchoolVerb in Types.
--
-- Not to be confused with content/Subjects.luau, which is animals and people an event
-- can be about. Nothing here meets a dog.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type SchoolSubject = Types.SchoolSubject

local Curriculum = {}

-- The school years, from Config rather than restated, so a subject can never be taught
-- in a year school does not run. A subject whose band falls outside these is a subject
-- that silently never appears, which is the kind of content bug that looks like an
-- engine bug.
local SCHOOL_START = Config.School.StartAge
local SCHOOL_END = Config.School.EndAge

local SOURCE: { SchoolSubject } = {
	-- Science. The first subject with a verb of its own, and the reference for the rest:
	-- a board names an ordered procedure, you walk the room clicking stations to stack
	-- steps on a bench, and nothing is scored until you commit.
	--
	-- Starts at nine rather than six because the verb has a floor a six-year-old cannot
	-- clear -- reading an ordered list off a board and holding three entries of it across
	-- a room is the mechanic, and a player who cannot do that is not being challenged,
	-- they are being excluded. The early years stay on the quiz path, which is the one
	-- thing the quiz path is genuinely good at.
	{
		id = "science",
		name = "Science",
		verb = "procedure",
		blurb = "Read the procedure off the board, then walk it in order. Nothing counts until you commit the bench.",
		minAge = 9,
		maxAge = SCHOOL_END,
	},

	-- Math. Kept on the quiz path deliberately and possibly forever: arithmetic under a
	-- clock with one right answer is the one thing multiple choice models honestly, and
	-- inventing a walking verb for it would be variety-as-fix -- a different room around
	-- an identical decision. If it ever gets a verb it should be one where the *answer*
	-- is a thing you build rather than pick.
	{
		id = "math",
		name = "Math",
		verb = "quiz",
		blurb = "Numbers, on a clock. Get them wrong early enough to still fix the lesson.",
		minAge = SCHOOL_START,
		maxAge = SCHOOL_END,
	},

	-- Reading. The debt above is paid: the verb is *building* the word rather than knowing
	-- it. Two words stand on the board with letters missing and there is one tray of tiles
	-- between them, so a letter spent on one is a letter the other does not get -- which is
	-- the whole subject. It is the only lesson here where the answer is assembled rather
	-- than chosen, found or copied, and that is what keeps it from being one of the others
	-- wearing a different name.
	--
	-- The note that used to stand here called this an unsolved problem, on the grounds that
	-- "a passage on the board and the answer somewhere in it" is a quiz with more words. That
	-- was correct about *that* shape and is left recorded because it is the trap: the way out
	-- was not a better question, it was to stop asking one.
	{
		id = "reading",
		name = "Reading",
		verb = "build",
		blurb = "Two words, one tray of letters, and not enough of them to be careless.",
		minAge = SCHOOL_START,
		maxAge = SCHOOL_END,
	},

	-- Art. Copy the study on the wall onto your canvas, one square of paint at a time,
	-- while the study quietly changes behind your back. The only subject here that can be
	-- soft-failed by degree without a right answer ever existing: a cell painted in the
	-- nearest colour you were handed is worth most of a cell painted correctly, so the
	-- score is a distance rather than a tally of rights and wrongs.
	--
	-- The only subject that starts at six, and the one place the mastery ladder is doing
	-- the age-banding instead of the content. A six-year-old and a fourteen-year-old copy
	-- the same harbour; what differs is how many tubes of paint they have been handed --
	-- see Config.School.Art.PaletteByLevel -- so there is nothing here a small child cannot
	-- attempt and nothing an older one has run out of.
	{
		id = "art",
		name = "Art",
		verb = "copy",
		blurb = "Copy the wall. It will not hold still, and you were not given every colour.",
		minAge = SCHOOL_START,
		maxAge = 14,
	},
	-- Music. A rhythm held rather than a question answered -- the sweep primitive the
	-- gym and the sports campus already use (shared/Sweep.luau), pointed at a beat
	-- instead of a rep: a count-in, then the needle, then a press timed against the
	-- window rather than a multiple-choice guess about a note's name.
	--
	-- Starts at eight for the same reason Geography does: holding a count-in and
	-- reacting to a moving needle is the mechanic, and a six-year-old is not the
	-- player that challenges.
	{
		id = "music",
		name = "Music",
		verb = "rhythm",
		blurb = "Count in, then hold the beat. Nothing here is asked -- only kept.",
		minAge = 8,
		maxAge = SCHOOL_END,
	},

	-- PE. The join between school and sports, and the only subject on this list that does not
	-- pay smarts.
	--
	-- `docs/school_and_sports.md` names it exactly: *"PE -- a graded sports drill. Do not build
	-- a separate PE minigame; this is the join between the two systems and it is what makes
	-- school carry the childhood years."* So it awards **health into athletics**, and a good
	-- report in PE is what a player takes with them into sport rather than into a career at a
	-- desk. It was the one subject missing from the timetable entirely.
	--
	-- The verb is the golf three-click meter -- power, then placement, with an overswing zone
	-- that buys power with time. See Config.School.PE, which holds it deliberately as a *sports*
	-- primitive rather than a school one, because the soccer build takes the same numbers.
	--
	-- Runs the whole of school. Unlike Science and Music there is no floor here that a small
	-- child cannot clear: the meter is three clicks, and being bad at it is legible at six in a
	-- way that holding a beat across four lanes is not. It is the one subject that gets easier
	-- to be *good* at as the character grows, because the window widens with health.
	{
		-- **Gym, not PE.** Both agents wrote a PE subject: this drill meter and A's live 3v3
		-- match below. They are different lessons with different verbs, so the timetable keeps
		-- both -- but two entries cannot share an id, and Curriculum refuses the duplicate at
		-- load. The drill takes the name the debug command and StatsUI's sweep sources have
		-- always used for it.
		id = "gym",
		name = "Gym",
		verb = "drill",
		blurb = "Power, then placement. The greedy swing is the one that costs you.",
		minAge = SCHOOL_START,
		maxAge = SCHOOL_END,
	},

	-- Geography. The errand, and the one lesson where the game stops telling you where
	-- things are: you are given a place's *name* and nothing else, and you walk. Every
	-- other destination in AGES arrives as a lit disc with a beam over it and a distance
	-- counting down, so taking that away is not a missing feature -- it is the entire
	-- verb, and it is a verb no other subject can borrow because no other subject owns
	-- the town.
	--
	-- Starts at eight rather than six for the same reason Science starts at nine: holding
	-- a name in your head across a two-hundred-stud walk is the mechanic, and a player who
	-- cannot yet read the name is not being challenged.
	{
		id = "geography",
		name = "Geography",
		verb = "hunt",
		blurb = "You get the name. You do not get the marker. Go and find it.",
		minAge = 8,
		maxAge = SCHOOL_END,
	},

	-- PE. The one subject that was never a quiz to begin with -- see
	-- docs/school_sports_plan.md and docs/school_and_sports.md's SPORTS section. The
	-- verb is a live 3v3 soccer match at the stadium pitch, the same match anybody can
	-- walk up and join outside of school hours (SoccerService's roster is always
	-- running, bot-filled, and this lesson takes over one bot's slot for the window
	-- Config.Sports.Soccer.PeLessonSeconds covers). No teacher and no scene, on the
	-- same reasoning Music and Geography give: the pitch is already standing a walk
	-- away, and drawing a classroom around a player about to be sprinting at a ball
	-- would be furniture nobody stays in the room to see.
	--
	-- Starts at eight for the same reason Music and Geography do: reading the ball,
	-- holding a charge, and finding a teammate are the mechanic, and a six-year-old is
	-- not the player it is aimed at. The four SportsDrill stations (Config.SportsDrill)
	-- stay open at every age below this as the solo, un-graded way to touch the same
	-- ball, rim, net and bag.
	{
		id = "pe",
		name = "PE",
		verb = "match",
		blurb = "Three a side, live, on the pitch. Win the ball, beat a marker, put one in the net.",
		minAge = 8,
		maxAge = SCHOOL_END,
	},
}

-- Validated at require time rather than found in play, and loudly: a subject with a
-- broken band does not error, it silently never gets taught, and a whole school year
-- quietly missing a subject is close to invisible from inside the game.
local byId: { [string]: SchoolSubject } = {}
for _, subject in SOURCE do
	if byId[subject.id] ~= nil then
		error(`[AGES content] duplicate school subject id "{subject.id}"`)
	end
	if subject.minAge > subject.maxAge then
		error(
			`[AGES content] school subject "{subject.id}" has minAge {subject.minAge} above maxAge {subject.maxAge}`
				.. ` -- it would never be taught. Swap them.`
		)
	end
	if subject.maxAge < SCHOOL_START or subject.minAge > SCHOOL_END then
		error(
			`[AGES content] school subject "{subject.id}" is taught between {subject.minAge} and {subject.maxAge},`
				.. ` entirely outside the school years {SCHOOL_START}-{SCHOOL_END} -- it would never be taught.`
				.. ` Widen the band or widen Config.School.StartAge/EndAge.`
		)
	end
	byId[subject.id] = subject
end

-- Every school year must have something in it. Without this check a band edit can empty
-- a year, and an empty year is a lesson that refuses at the door with no reason a player
-- could act on.
for age = SCHOOL_START, SCHOOL_END do
	local any = false
	for _, subject in SOURCE do
		if age >= subject.minAge and age <= subject.maxAge then
			any = true
			break
		end
	end
	if not any then
		error(
			`[AGES content] no school subject is taught at age {age}, so that whole year has no lesson in it.`
				.. ` Widen a subject's band in content/Curriculum.luau.`
		)
	end
end

-- The subjects a life of this age can be taught, in timetable order. Empty is
-- impossible inside the school years by the check above, and correct outside them.
function Curriculum.ForAge(age: number): { SchoolSubject }
	local out: { SchoolSubject } = {}
	for _, subject in SOURCE do
		if age >= subject.minAge and age <= subject.maxAge then
			table.insert(out, subject)
		end
	end
	return out
end

-- Nil for an id that is not on the timetable. Callers that hold an id from a saved
-- profile must handle that: a subject removed from content is a subject a live profile
-- may still be part-way through, and erroring here would lock that life out of school.
function Curriculum.Get(id: string): SchoolSubject?
	return byId[id]
end

Curriculum.All = SOURCE

return Curriculum
