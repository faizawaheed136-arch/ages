--!strict
-- What a life remembers about itself.
--
-- A stat says how you are. A flag says what you did. The difference matters because
-- stats are continuous and forgetful -- happiness decays, and by twenty nothing about
-- the number says the dog was the reason -- while the interesting parts of a life are
-- discrete and permanent: you either shouted at it or you knelt down, and either way
-- that is still true forty years later.
--
-- This is the whole mechanism behind two things that were previously impossible to
-- write: an event that only exists because of an earlier one, and a person who is in
-- your life because you went and got them. Both are the same sentence -- "because of
-- what you did" -- so both are the same field.
--
-- Every flag is declared here and nowhere else. Content refers to them by id and the
-- loader refuses an id that is not in this table, which is the only defence against the
-- failure this system would otherwise have by design: a mistyped `requires` is an event
-- that is never selected, and an event that is never selected looks exactly like an
-- event that was simply unlucky. There is no runtime symptom to notice, so the mistake
-- has to be impossible to make rather than possible to find.
--
-- Flags are per life, cleared with the seen list on a new one. A friendship you earned
-- as a child belongs to that child.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type FlagDef = Types.FlagDef
type FlagSet = Types.FlagSet

-- Ids are lowercase words joined by underscores, checked below. Not style for its own
-- sake: these are written by hand in six content files and compared as strings, so
-- "DogLover" and "dog_lover" being two different flags that mean the same thing is a
-- bug nobody would ever see, because both halves would work perfectly on their own.
local ID_PATTERN = "^[a-z][a-z0-9_]*$"

local SOURCE: { FlagDef } = {
	-- Childhood. These are the first decisions a life makes and they are made before
	-- the player understands they are deciding anything, which is exactly right: the
	-- things that turn out to have shaped you were not presented as forks at the time.
	{
		id = "dog_loved",
		meaning = "Knelt down to the dog rather than backing away from it",
	},
	{
		id = "dog_feared",
		meaning = "Was frightened by the dog and has not forgotten it",
	},
	{
		id = "climbed_stairs",
		meaning = "Went up the stairs alone before anybody said it was allowed",
	},
	{
		id = "stayed_put",
		meaning = "Looked at the stairs and did not go up them",
	},
	{
		id = "broke_it_owned_up",
		meaning = "Broke something and said so",
	},
	{
		id = "broke_it_hid_it",
		meaning = "Broke something and put the pieces back together facing the wall",
	},
	{
		id = "wandered_off",
		meaning = "Went through the gap in the hedge to see what was past it",
	},

	-- People. Set by an offer rather than by an event, which is the same sentence said
	-- from the other end: an answer the player gave, to somebody, at a bond they had to
	-- earn first. This one exists because the favour is the sort of thing a life carries
	-- around afterwards -- somebody else's name is on it, and the person who would want
	-- to hear about it is not the person who did it.
	{
		id = "had_a_word_put_in",
		meaning = "Had somebody put a word in for them about work",
	},

	-- The body. Not a memory like the others but a state: this one is set by the
	-- health loop and cleared at the next birthday rather than kept for life, and it
	-- is declared here for the same reason the memories are -- content refers to it
	-- by id and the loader refuses an id that is not in this table, so an illness
	-- event with a mistyped flag is impossible rather than merely unlikely.
	{
		id = "sick",
		meaning = "Is unwell, and will stay that way until the next birthday",
	},

	-- The gym. Set by a choice that amounts to actually starting to go, so later
	-- events that presuppose a membership ("the direct debit keeps going out")
	-- only fire for a life that has one. A memory, like the others: once you have
	-- joined, you have joined.
	{
		id = "gym_joined",
		meaning = "Started going to the gym, whether the habit lasted",
	},

	-- Debt. The one number in the game that compounds against the player. Flags
	-- here let content react to a life being in the red rather than letting the
	-- number sit invisible and only punishing.
	{
		id = "in_debt",
		meaning = "Owes money on monthly bills, and the interest is still running",
	},
	{
		id = "loan_shark_deal",
		meaning = "Took a loan shark up on an offer when bills became too much",
	},
	{
		id = "debt_relief",
		meaning = "Had debt cleared or reduced by something other than working it off",
	},

	-- Careers. Set the first time a life steps into a job category, so later
	-- events can branch off what the life has already done rather than only
	-- what the life is doing right now. Cleared on death with the rest of the
	-- flag set, because a new life has not earned any of these.
	{
		id = "career_shop",
		meaning = "Worked the shop floor at some point, which is where most careers start",
	},
	{
		id = "career_office",
		meaning = "Worked upstairs in the office, past the stairs that separate the two worlds",
	},
	{
		id = "career_bakery",
		meaning = "Worked the bakery, early mornings and flour in the hair",
	},
	{
		id = "career_trades",
		meaning = "Worked with your hands outside a shop or office — garage, site, warehouse",
	},
	{
		id = "career_retired",
		meaning = "Left the workforce deliberately, not because something pushed you out",
	},

	-- The park. Set by choices that make the park a regular part of a life, so
	-- later events can treat it as a place the life already knows rather than
	-- somewhere they are visiting for the first time.
	{
		id = "park_regular",
		meaning = "Visits the park often enough that it is a real place in their life",
	},
	{
		id = "park_first_swings",
		meaning = "Went on the swings as a small child and liked it",
	},
	{
		id = "park_confession",
		meaning = "Had an important conversation at the park that changed something",
	},
	{
		id = "park_gang_untouched",
		meaning = "Was near the west gang at the park and walked away clean",
	},
}

local byId: { [string]: FlagDef } = {}
for _, def in SOURCE do
	if not string.match(def.id, ID_PATTERN) then
		error(`[AGES content] flag id "{def.id}" must be lowercase words joined by underscores`)
	end
	if byId[def.id] ~= nil then
		error(`[AGES content] duplicate flag id "{def.id}"`)
	end
	if def.meaning == "" then
		error(`[AGES content] flag "{def.id}" has no meaning written against it`)
	end
	byId[def.id] = def
end

local Flags = {
	All = SOURCE,
	ById = byId,
}

-- Refuses a list of flag ids that content has referred to. `where` is said back in the
-- error because by the time this throws the author is looking at six content files and
-- the useful half of the message is which line to open.
function Flags.AssertKnown(ids: { string }?, where: string)
	if ids == nil then
		return
	end
	if #ids == 0 then
		error(`[AGES content] {where} has an empty flag list; leave it out rather than writing none`)
	end
	local seen: { [string]: boolean } = {}
	for _, id in ids do
		if byId[id] == nil then
			error(`[AGES content] {where} refers to flag "{id}", which is not declared in Flags.luau`)
		end
		if seen[id] then
			error(`[AGES content] {where} lists flag "{id}" twice`)
		end
		seen[id] = true
	end
end

-- The one flag id two lists must never share, said in whichever words fit the pair.
-- Taking the sentence as an argument rather than hardcoding it is not decoration: the two
-- callers below are different mistakes -- one is content that can never be reached, the
-- other is two intentions written in one place -- and an error that described the wrong
-- one would send the author looking in the wrong file.
local function assertDisjoint(a: { string }?, b: { string }?, where: string, complaint: string)
	if a == nil or b == nil then
		return
	end
	local inB: { [string]: boolean } = {}
	for _, id in b do
		inB[id] = true
	end
	for _, id in a do
		if inB[id] then
			error(`[AGES content] {where} {complaint} flag "{id}"`)
		end
	end
end

-- Refuses a requires/forbids pair that can never be satisfied. Written as its own check
-- because the two lists are authored separately and a flag in both is not a strict rule,
-- it is a piece of content that has been switched off in a way that leaves no trace.
function Flags.AssertSatisfiable(requires: { string }?, forbids: { string }?, where: string)
	assertDisjoint(requires, forbids, where, "both requires and forbids")
end

-- Refuses an answer that sets and clears the same flag. Not resolved by documenting a
-- winner, because a documented winner is a rule somebody has to already know to read the
-- content correctly.
function Flags.AssertNotBoth(sets: { string }?, clears: { string }?, where: string)
	assertDisjoint(sets, clears, where, "both sets and clears")
end

-- The single gate, used by events, by people and by what people offer. One function
-- rather than three, so a rule can never mean one thing for an event and another for the
-- person the event is about.
--
-- Requires is all of them, not any: two flags named together read as one condition with
-- two halves, and "any" is spelled by writing two pieces of content.
function Flags.Meets(held: FlagSet, requires: { string }?, forbids: { string }?): boolean
	if requires ~= nil then
		for _, id in requires do
			if held[id] == nil then
				return false
			end
		end
	end
	if forbids ~= nil then
		for _, id in forbids do
			if held[id] ~= nil then
				return false
			end
		end
	end
	return true
end

return Flags
