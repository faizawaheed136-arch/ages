--!strict
-- Who is standing in the corridor, and what each of them is like to be stood in front of.
--
-- Content data, not system code. Adding somebody to the corridor is an entry in the list
-- below; how the stare-down is scored is BullyService's business and deliberately not
-- here, which is the same split Curriculum makes against the verbs it names.
--
-- The only load-bearing field is `drain`. Every one of these has the same one-key verb --
-- hold, then let go -- so what makes one different to play against is the shape their
-- patience falls in, and nothing else. That is the seventh requirement in the activity
-- law taken literally: same input, different opponent, knowledge compounding across
-- repetitions without a single button being added. A fourth bully with the same drain as
-- one of these would be a reskin, and reskins are how a corridor stops teaching.
--
-- What is deliberately *not* here:
--
--   No slurs, no targeting, and nothing said about who anybody is. Every line below is
--   about the toll or about the standing -- "give it here", "you were not going to use
--   it" -- and never about the player. This game is 13+ and the corridor is the part of
--   it most likely to be read over a shoulder; a bully who is frightening because of what
--   they *want* needs nothing said about anybody to work, and a bully who is frightening
--   because of what they call you is a different game that this one is not going to be.
--
--   No winning by being bigger. None of these can be beaten by having more of a stat --
--   bullyNerve widens the window you are aiming at and never moves the bar for you, so a
--   maxed life that releases badly still backs down. A corridor you outgrow rather than
--   out-play is a corridor that stops being played.
--
-- The bodies are whole CastMembers rather than cast ids for the reason the type says: the
-- cast is the handful of faces a life keeps meeting, and four interchangeable corridor
-- kids in that list would dilute the one thing it is for. They carry ageOffset so they
-- grow alongside the player -- a bully who was a head taller at eleven and exactly the
-- same height at seventeen would be a prop rather than a person.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type BullyArchetype = Types.BullyArchetype

local Bullies = {}

local BULLY = Config.School.Bully

-- The corridor years, from Config rather than restated, so nobody can be written into a
-- band the corridor does not run in. Someone whose band falls outside these never turns
-- up, and a bully who silently never appears is the kind of content bug that reads as an
-- engine bug.
local MIN_AGE = BULLY.MinAge
local MAX_AGE = BULLY.MaxAge

local SOURCE: { BullyArchetype } = {
	-- Steady, and the one the verb is learned on. Patience falls at one rate and the bar
	-- never lies, so a player meeting the corridor for the first time can watch the two
	-- numbers cross and understand what the release is for without being punished for
	-- looking. Every other entry here is a departure from this one.
	{
		id = "steady_toll",
		body = {
			id = "bully_steady",
			name = "Griff",
			gender = "male",
			skinColor = Color3.fromRGB(214, 168, 134),
			-- A year older than you, and it stays a year for the whole of school. See the
			-- note at the top about why nobody here is written as an absolute height.
			ageOffset = 1,
			heightScale = 1.06,
			widthScale = 1.08,
			headScale = 1,
			proportionScale = 1,
			bodyTypeScale = 0.7,
			shirtAssetId = 0,
			pantsAssetId = 0,
			hairAssetId = 0,
			shirtColor = Color3.fromRGB(92, 84, 78),
			pantsColor = Color3.fromRGB(58, 58, 64),
		},
		patienceSeconds = 4.2,
		drain = "steady",
		demand = "money",
		openingLine = "Lunch money. Come on, you know how this goes.",
		standUpLine = "Fine. Keep it.",
		backDownLine = "Good. See you tomorrow.",
		minAge = MIN_AGE,
		maxAge = MAX_AGE,
	},

	-- The bluffer, and the one with a technique in it. Patience falls fast enough that the
	-- window looks like it is arriving early, then jumps back up once -- so releasing on
	-- first sight loses, and waiting exactly one beat past the first opening wins.
	--
	-- This is the "trivial verb with a discovered optimal technique" the law asks for. The
	-- input is identical to Griff's; what a player knows on the thirtieth corridor that
	-- they did not on the first is that this one lies once, and only once.
	{
		id = "bluffer_homework",
		body = {
			id = "bully_bluffer",
			name = "Wren",
			gender = "female",
			skinColor = Color3.fromRGB(176, 132, 104),
			ageOffset = 1,
			heightScale = 1.01,
			widthScale = 0.96,
			headScale = 1,
			proportionScale = 1,
			bodyTypeScale = 0.62,
			shirtAssetId = 0,
			pantsAssetId = 0,
			hairAssetId = 0,
			shirtColor = Color3.fromRGB(126, 76, 92),
			pantsColor = Color3.fromRGB(48, 52, 62),
		},
		patienceSeconds = 3.6,
		drain = "bluffer",
		demand = "homework",
		openingLine = "That is due next period, is it not? Hand it over.",
		standUpLine = "Whatever. It was not worth reading.",
		backDownLine = "You were not going to use it anyway.",
		minAge = MIN_AGE,
		maxAge = MAX_AGE,
	},

	-- The mirror, and the one that makes holding the wrong answer. Their patience falls in
	-- proportion to how fast your nerve is rising, so the harder you lean the sooner they
	-- are gone -- and the window has to be taken early, on a bar that has barely moved.
	--
	-- Every other opponent here rewards holding on. This one is why the verb is a release
	-- rather than a race: a player who has only ever met Griff will hold through the window
	-- out of habit and overcommit, which is the moment the corridor stops being one fight
	-- repeated and starts being a thing you read.
	{
		id = "mirror_seat",
		body = {
			id = "bully_mirror",
			name = "Marlow",
			gender = "male",
			skinColor = Color3.fromRGB(150, 110, 88),
			ageOffset = 2,
			heightScale = 1.09,
			widthScale = 1.02,
			headScale = 1,
			proportionScale = 1,
			bodyTypeScale = 0.68,
			shirtAssetId = 0,
			pantsAssetId = 0,
			hairAssetId = 0,
			shirtColor = Color3.fromRGB(64, 88, 96),
			pantsColor = Color3.fromRGB(44, 46, 52),
		},
		patienceSeconds = 5.0,
		drain = "mirror",
		-- Wants nothing, which is the point of having one who does. A corridor where every
		-- encounter has a price is a tax with faces on it; this one is only ever about who
		-- moves first, so standing your ground here buys nothing but the standing.
		demand = "seat",
		openingLine = "You are in my way.",
		standUpLine = "...Go on, then.",
		backDownLine = "Thought so.",
		minAge = MIN_AGE,
		maxAge = MAX_AGE,
	},

	-- The long one, and the only one banded to the last years of school. Patience falls
	-- slowly and steadily, so the encounter runs nearly twice as long as Griff's -- which
	-- against the bell is the whole of the difference. Standing up to this one is a real
	-- decision about being late, and it is the reason the second clock exists.
	{
		id = "steady_long",
		body = {
			id = "bully_long",
			name = "Bex",
			gender = "female",
			skinColor = Color3.fromRGB(232, 196, 168),
			ageOffset = 2,
			heightScale = 1.04,
			widthScale = 1.05,
			headScale = 1,
			proportionScale = 1,
			bodyTypeScale = 0.72,
			shirtAssetId = 0,
			pantsAssetId = 0,
			hairAssetId = 0,
			shirtColor = Color3.fromRGB(104, 96, 60),
			pantsColor = Color3.fromRGB(52, 50, 46),
		},
		patienceSeconds = 7.4,
		drain = "steady",
		demand = "money",
		openingLine = "I can do this all afternoon. Can you?",
		standUpLine = "Huh. All right.",
		backDownLine = "Told you.",
		-- The last three years only. A fourteen-year-old has not yet got anywhere to be that
		-- costs them something to be late to, so the long stare would just be a long wait --
		-- and a long wait with no decision in it is the dead time the law names first.
		minAge = math.max(MIN_AGE, 15),
		maxAge = MAX_AGE,
	},
}

-- Validated at require time rather than found in play, and loudly, for the reason
-- Curriculum states: a bully with a broken band does not error, they silently never turn
-- up, and a corridor quietly missing somebody is close to invisible from inside the game.
local byId: { [string]: BullyArchetype } = {}
for _, bully in SOURCE do
	if byId[bully.id] ~= nil then
		error(`[AGES content] duplicate bully id "{bully.id}"`)
	end
	if bully.minAge > bully.maxAge then
		error(
			`[AGES content] bully "{bully.id}" has minAge {bully.minAge} above maxAge {bully.maxAge}`
				.. ` -- they would never turn up. Swap them.`
		)
	end
	if bully.maxAge < MIN_AGE or bully.minAge > MAX_AGE then
		error(
			`[AGES content] bully "{bully.id}" stands between {bully.minAge} and {bully.maxAge},`
				.. ` entirely outside the corridor years {MIN_AGE}-{MAX_AGE} -- they would never turn up.`
				.. ` Widen their band or widen Config.School.Bully.MinAge/MaxAge.`
		)
	end
	if bully.patienceSeconds <= 0 then
		error(
			`[AGES content] bully "{bully.id}" has patienceSeconds {bully.patienceSeconds}, which is not`
				.. ` a length of time -- their patience would be gone before the bar was drawn.`
		)
	end
	byId[bully.id] = bully
end

-- Every corridor year must have somebody in it. Without this a band edit can empty a
-- year, and an empty year is a corridor that is simply a hallway -- which is not an error
-- anybody would notice until they wondered where the system went.
for age = MIN_AGE, MAX_AGE do
	local any = false
	for _, bully in SOURCE do
		if age >= bully.minAge and age <= bully.maxAge then
			any = true
			break
		end
	end
	if not any then
		error(
			`[AGES content] no bully stands in the corridor at age {age}, so that whole year has`
				.. ` nobody in it. Widen a band in content/Bullies.luau.`
		)
	end
end

-- Each drain has to be represented, or the corridor is one opponent wearing several
-- names. This is the one check here that is about the *design* rather than about the
-- data being well formed, and it is here because the failure it catches -- a corridor
-- that stops teaching after the first encounter -- is invisible to every other check in
-- the tree and reads as "the system got boring" rather than as a bug.
for _, drain in { "steady", "bluffer", "mirror" } do
	local found = false
	for _, bully in SOURCE do
		if bully.drain == drain then
			found = true
			break
		end
	end
	if not found then
		error(
			`[AGES content] no bully uses the "{drain}" drain, so the corridor has one fewer way`
				.. ` of being played than it has archetypes. Give one of them that drain, or remove`
				.. ` it from Types.BullyDrain.`
		)
	end
end

-- Who can turn up at this age, in declaration order. Empty is impossible inside the
-- corridor years by the check above, and correct outside them.
function Bullies.ForAge(age: number): { BullyArchetype }
	local out: { BullyArchetype } = {}
	for _, bully in SOURCE do
		if age >= bully.minAge and age <= bully.maxAge then
			table.insert(out, bully)
		end
	end
	return out
end

-- Nil for an id that is not in the corridor. Callers holding an id from a live encounter
-- must handle that: a bully removed from content is a bully a running stare-down may
-- still be against, and erroring here would strand that player mid-hold.
function Bullies.Get(id: string): BullyArchetype?
	return byId[id]
end

Bullies.All = SOURCE

return Bullies
