--!strict
-- The words Reading asks you to finish.
--
-- Content, and a flat table rather than code for the reason Lessons gives about its own
-- bank: a lesson is six words and a childhood is thirty-six lessons, so the thing that has
-- to stay cheap is writing another one. A word is one line here and never touches the loop
-- that puts it on the board.
--
-- Which letters are missing is **not** authored. Only how many are, and the service picks
-- the positions when it deals the board. That split is deliberate and it is what stops this
-- file being three times the size: authoring the gaps would mean deciding, for every word,
-- which letters a child can infer -- which is a judgement the age band already makes, and
-- making it twice would let the two disagree.
--
-- What is deliberately *not* here:
--
--   No definitions and no clues. The subject is finishing a word you can already half see,
--   not knowing what it means -- a clue would turn this into a quiz with tiles, which is
--   precisely the shape Curriculum spent a paragraph explaining the way out of.
--
--   No proper nouns, no names, nothing regional. A word whose spelling you either happen to
--   have met or have not is a coin toss, and it is the same objection Lessons raises to
--   trivia. Every word below is one a reader of that age has seen in print.
--
--   Nothing an eight-year-old at a keyboard would need an adult for. School is the part of
--   this game most likely to be read over a shoulder.
--
-- US English, like everything else in the tree -- NEIGHBOR and PRACTICE are spelled the way
-- the rest of the game spells them.
--
-- The age bands overlap heavily and on purpose. Eleven is a perfectly good age to still be
-- handed WINTER, and a hard boundary would make a birthday feel like a different subject.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Words = {}

-- One word as content declares it. Local rather than exported to Types because nothing
-- outside this file and its service ever holds one -- what leaves here is a dealt board,
-- and that shape is in Types where the client can see it.
export type Word = {
	id: string,
	word: string,
	-- How many letters are taken out. The positions are chosen when the board is dealt.
	gaps: number,
	minAge: number,
	maxAge: number,
}

local SCHOOL_START = Config.School.StartAge
local SCHOOL_END = Config.School.EndAge
local READING = Config.School.Reading

local SOURCE: { Word } = {
	{ id = "bread", word = "BREAD", minAge = 6, maxAge = 9, gaps = 1 },
	{ id = "chair", word = "CHAIR", minAge = 6, maxAge = 9, gaps = 1 },
	{ id = "river", word = "RIVER", minAge = 6, maxAge = 10, gaps = 1 },
	{ id = "green", word = "GREEN", minAge = 6, maxAge = 9, gaps = 1 },
	{ id = "stone", word = "STONE", minAge = 6, maxAge = 10, gaps = 1 },
	{ id = "cloud", word = "CLOUD", minAge = 6, maxAge = 10, gaps = 1 },
	{ id = "horse", word = "HORSE", minAge = 6, maxAge = 10, gaps = 1 },
	{ id = "light", word = "LIGHT", minAge = 6, maxAge = 11, gaps = 1 },
	{ id = "water", word = "WATER", minAge = 6, maxAge = 10, gaps = 1 },
	{ id = "apple", word = "APPLE", minAge = 6, maxAge = 9, gaps = 1 },
	{ id = "night", word = "NIGHT", minAge = 6, maxAge = 11, gaps = 1 },
	{ id = "field", word = "FIELD", minAge = 6, maxAge = 11, gaps = 1 },
	{ id = "garden", word = "GARDEN", minAge = 8, maxAge = 13, gaps = 2 },
	{ id = "winter", word = "WINTER", minAge = 8, maxAge = 13, gaps = 2 },
	{ id = "market", word = "MARKET", minAge = 8, maxAge = 13, gaps = 2 },
	{ id = "silver", word = "SILVER", minAge = 8, maxAge = 13, gaps = 2 },
	{ id = "bridge", word = "BRIDGE", minAge = 8, maxAge = 13, gaps = 2 },
	{ id = "pocket", word = "POCKET", minAge = 8, maxAge = 12, gaps = 2 },
	{ id = "kitchen", word = "KITCHEN", minAge = 9, maxAge = 14, gaps = 2 },
	{ id = "morning", word = "MORNING", minAge = 9, maxAge = 14, gaps = 2 },
	{ id = "harbour", word = "HARBOUR", minAge = 9, maxAge = 14, gaps = 2 },
	{ id = "teacher", word = "TEACHER", minAge = 9, maxAge = 14, gaps = 2 },
	{ id = "weather", word = "WEATHER", minAge = 9, maxAge = 14, gaps = 2 },
	{ id = "station", word = "STATION", minAge = 9, maxAge = 15, gaps = 2 },
	{ id = "blanket", word = "BLANKET", minAge = 9, maxAge = 14, gaps = 2 },
	{ id = "machine", word = "MACHINE", minAge = 10, maxAge = 15, gaps = 2 },
	{ id = "journey", word = "JOURNEY", minAge = 10, maxAge = 15, gaps = 2 },
	{ id = "cabinet", word = "CABINET", minAge = 10, maxAge = 15, gaps = 2 },
	{ id = "distance", word = "DISTANCE", minAge = 11, maxAge = 17, gaps = 3 },
	{ id = "evidence", word = "EVIDENCE", minAge = 12, maxAge = 17, gaps = 3 },
	{ id = "argument", word = "ARGUMENT", minAge = 12, maxAge = 17, gaps = 3 },
	{ id = "pressure", word = "PRESSURE", minAge = 12, maxAge = 17, gaps = 3 },
	{ id = "interest", word = "INTEREST", minAge = 12, maxAge = 17, gaps = 3 },
	{ id = "practice", word = "PRACTICE", minAge = 11, maxAge = 17, gaps = 3 },
	{ id = "neighbor", word = "NEIGHBOR", minAge = 11, maxAge = 17, gaps = 3 },
	{ id = "stubborn", word = "STUBBORN", minAge = 12, maxAge = 17, gaps = 3 },
	{ id = "hospital", word = "HOSPITAL", minAge = 11, maxAge = 17, gaps = 3 },
	{ id = "remember", word = "REMEMBER", minAge = 11, maxAge = 17, gaps = 3 },
	{ id = "sentence", word = "SENTENCE", minAge = 11, maxAge = 17, gaps = 3 },
	{ id = "question", word = "QUESTION", minAge = 11, maxAge = 17, gaps = 3 },
	{ id = "daughter", word = "DAUGHTER", minAge = 11, maxAge = 17, gaps = 3 },
	{ id = "engineer", word = "ENGINEER", minAge = 13, maxAge = 17, gaps = 3 },
	{ id = "laughter", word = "LAUGHTER", minAge = 11, maxAge = 17, gaps = 3 },
	{ id = "thousand", word = "THOUSAND", minAge = 11, maxAge = 17, gaps = 3 },
	{ id = "attention", word = "ATTENTION", minAge = 13, maxAge = 17, gaps = 3 },
	{ id = "difficult", word = "DIFFICULT", minAge = 13, maxAge = 17, gaps = 3 },
	{ id = "furniture", word = "FURNITURE", minAge = 13, maxAge = 17, gaps = 3 },
	{ id = "important", word = "IMPORTANT", minAge = 13, maxAge = 17, gaps = 3 },
	{ id = "carpenter", word = "CARPENTER", minAge = 13, maxAge = 17, gaps = 3 },
	{ id = "orchestra", word = "ORCHESTRA", minAge = 13, maxAge = 17, gaps = 3 },
}

-- Validated at require time rather than found in play, and loudly, for the reason
-- Curriculum and Bullies both state: a word with a broken band does not error, it silently
-- never appears, and a bank that quietly stopped covering the early years would present as
-- a lesson that refuses at the door for no reason.
local byId: { [string]: Word } = {}
for _, entry in SOURCE do
	if byId[entry.id] ~= nil then
		error(`[AGES content] duplicate word id "{entry.id}"`)
	end
	if entry.word ~= string.upper(entry.word) then
		error(
			`[AGES content] word "{entry.id}" is written "{entry.word}" -- the board draws these as`
				.. ` given, and a lower-case tile beside upper-case ones reads as a different alphabet.`
				.. ` Write it in capitals.`
		)
	end
	if string.match(entry.word, "^%u+$") == nil then
		error(
			`[AGES content] word "{entry.id}" is "{entry.word}", which has something in it that is not`
				.. ` a letter. A tile can only carry a letter.`
		)
	end
	if entry.gaps < 1 then
		error(`[AGES content] word "{entry.id}" has {entry.gaps} gaps, so there is nothing to build.`)
	end
	if entry.gaps >= #entry.word then
		error(
			`[AGES content] word "{entry.id}" is {#entry.word} letters with {entry.gaps} gaps, which`
				.. ` leaves nothing standing. A word with every letter missing is not a word, it is a`
				.. ` row of empty squares -- leave at least one.`
		)
	end
	if entry.minAge > entry.maxAge then
		error(
			`[AGES content] word "{entry.id}" has minAge {entry.minAge} above maxAge {entry.maxAge}`
				.. ` -- it would never be dealt. Swap them.`
		)
	end
	if entry.maxAge < SCHOOL_START or entry.minAge > SCHOOL_END then
		error(
			`[AGES content] word "{entry.id}" is taught between {entry.minAge} and {entry.maxAge},`
				.. ` entirely outside the school years {SCHOOL_START}-{SCHOOL_END} -- it would never be`
				.. ` dealt. Widen the band.`
		)
	end
	byId[entry.id] = entry
end

-- Every school year needs enough words to fill a whole lesson without repeating one.
-- Checked here rather than discovered at the desk, because the failure mode is the same
-- word arriving twice in one lesson, which reads as a bug in the dealer rather than as a
-- thin bank.
local NEEDED = READING.WordsPerLesson + READING.TargetsAtOnce
for age = SCHOOL_START, SCHOOL_END do
	local count = 0
	for _, entry in SOURCE do
		if age >= entry.minAge and age <= entry.maxAge then
			count += 1
		end
	end
	if count < NEEDED then
		error(
			`[AGES content] age {age} has only {count} words but a lesson needs {NEEDED}`
				.. ` (WordsPerLesson plus the {READING.TargetsAtOnce} standing on the board at the end).`
				.. ` Write more words for that age in content/Words.luau or widen a band.`
		)
	end
end

-- The longest gap count anywhere in the bank, against the tray. A tray that cannot cover
-- two full boards is a lesson that can deadlock with tiles in hand and nowhere to put them,
-- and that is a content fault rather than a player mistake -- so it is refused here.
local widest = 0
for _, entry in SOURCE do
	if entry.gaps > widest then
		widest = entry.gaps
	end
end
if READING.Tray.Size - READING.Tray.Decoys < widest * READING.TargetsAtOnce then
	error(
		`[AGES config] the tray deals {READING.Tray.Size} tiles of which {READING.Tray.Decoys} are`
			.. ` decoys, leaving {READING.Tray.Size - READING.Tray.Decoys} useful ones -- but`
			.. ` {READING.TargetsAtOnce} words of up to {widest} gaps each can need`
			.. ` {widest * READING.TargetsAtOnce}. Raise Tray.Size, lower Tray.Decoys, or lower the`
			.. ` gap count on the widest word.`
	)
end

-- The words this age can be dealt, in declaration order. Never empty inside the school
-- years by the check above.
function Words.ForAge(age: number): { Word }
	local out: { Word } = {}
	for _, entry in SOURCE do
		if age >= entry.minAge and age <= entry.maxAge then
			table.insert(out, entry)
		end
	end
	return out
end

-- Nil for an id that is not in the bank. Callers holding one from a live board must handle
-- that: a word removed from content is a word a running lesson may still have on the board.
function Words.Get(id: string): Word?
	return byId[id]
end

Words.All = SOURCE

return Words
