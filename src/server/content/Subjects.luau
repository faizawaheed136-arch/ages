--!strict
-- The things events are about, when the thing is something you can look at.
-- Content data, not system code: the numbers here are authored descriptions of
-- animals, the way Cast.luau holds authored descriptions of people, and adding
-- one needs no code.
--
-- Sizes are chosen against the childhood body ladder rather than against an
-- adult, because that is who meets them. At Config.Childhood.Bands a two-year-old
-- stands roughly 2.3 studs and a five-year-old roughly 3.4, so a dog with a 2.6
-- stud back really is "at least as tall as you are" for most of the ages
-- childhood_big_dog can fire at -- which is the sentence the prompt already makes
-- and, until now, could not keep.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type SceneSubject = Types.SceneSubject

local list: { SceneSubject } = {
	{
		id = "dog",
		name = "big dog",
		-- Deliberately at the top of the range the prompt claims. A dog that has
		-- to be looked *up* at is a different event from one you look down at, and
		-- the choices -- put your hand out, stand still, get behind an adult --
		-- only make sense at the first size.
		shoulderHeight = 2.6,
		bodyLength = 3.2,
		bodyWidth = 1.3,
		-- Faster than a visitor's 9. Someone at your door is being polite; a dog
		-- that has noticed you is not.
		walkSpeed = 11,
		color = Color3.fromRGB(122, 92, 62),
		accentColor = Color3.fromRGB(64, 48, 34),
	},
	{
		id = "cat",
		-- Nothing casts this yet. It is here because one entry is not a content
		-- module, it is a special case wearing one: a second subject at a
		-- genuinely different size is what proves the builder reads these numbers
		-- rather than having a dog baked into it.
		name = "cat",
		shoulderHeight = 1.0,
		bodyLength = 1.6,
		bodyWidth = 0.6,
		walkSpeed = 7,
		color = Color3.fromRGB(70, 70, 74),
		accentColor = Color3.fromRGB(236, 232, 224),
	},
	{
		id = "teacher",
		name = "teacher",
		-- Adult proportions against the childhood body ladder: at school age the
		-- player stands 3.6-4.8 studs tall, so a shoulderHeight of 4.5 plus a
		-- head puts the teacher clearly above them. Sized for the placeholder's
		-- biped path; a real R15 model dropped in overrides the dimensions.
		shoulderHeight = 4.5,
		bodyLength = 1.1,
		bodyWidth = 1.05,
		walkSpeed = 9,
		color = Color3.fromRGB(110, 98, 150),
		accentColor = Color3.fromRGB(60, 58, 68),
		biped = true,
	},
	-- The three people who can be in the room during a shift. Work moments are
	-- Enacted events, and until these existed the shift was the one place a subject
	-- could never stand: a rude customer has to be somebody you walk to. Same
	-- proportions as the teacher because the player is grown by then; the colors are
	-- the whole way the player tells who is who at a glance, so they are chosen to
	-- read as three different people rather than three shades of the same one.
	{
		id = "customer",
		name = "customer",
		shoulderHeight = 4.5,
		bodyLength = 1.1,
		bodyWidth = 1.05,
		walkSpeed = 9,
		color = Color3.fromRGB(92, 128, 134),
		accentColor = Color3.fromRGB(224, 216, 196),
		biped = true,
	},
	{
		id = "coworker",
		name = "coworker",
		shoulderHeight = 4.5,
		bodyLength = 1.1,
		bodyWidth = 1.05,
		walkSpeed = 9,
		color = Color3.fromRGB(112, 126, 92),
		accentColor = Color3.fromRGB(222, 210, 186),
		biped = true,
	},
	{
		id = "manager",
		name = "manager",
		-- A touch taller than the other two, which is the one proportional liberty
		-- the placeholder allows itself: a manager asked to carry an event about
		-- whether you can say no reads as the person with the power of review, and
		-- a bare half-stud of height is the cheapest version of that on offer.
		shoulderHeight = 4.7,
		bodyLength = 1.1,
		bodyWidth = 1.05,
		walkSpeed = 9,
		color = Color3.fromRGB(74, 84, 122),
		accentColor = Color3.fromRGB(170, 82, 78),
		biped = true,
	},
}

local byId: { [string]: SceneSubject } = {}
for _, subject in list do
	if byId[subject.id] ~= nil then
		error(`[AGES content] duplicate subject id "{subject.id}"`)
	end
	byId[subject.id] = subject
end

return {
	All = list,
	ById = byId,
}
