--!strict
-- The police, as bodies.
--
-- Deliberately not in Cast.luau, and this is the whole reason the file exists rather
-- than five more rows over there. Cast is merged into one list that visitor events draw
-- from -- the neighbor who knocks, the friend who calls round -- and an officer in that
-- pool would eventually turn up at the door to offer somebody a lift to the park. They
-- are also not Townsfolk: a townsperson is somebody you can build a bond with over forty
-- years, and the entire point of a police officer in this game is that there is no
-- relationship on the other end of them.
--
-- So they are a third kind of person, and the difference is worth naming: the cast are
-- people you know, the town are people you could know, and these are a *function the
-- world performs on you*. Nobody here has a history, nobody remembers the last time, and
-- nothing you do to one of them is remembered by the next.
--
-- Which is why they all display the same name. Five bodies so that a manhunt is not four
-- copies of one man walking in step, one word over every head so that no player ever
-- starts thinking of a particular officer as a character. The variation is in the
-- shoulders and nowhere else, because a uniform is the thing you actually see when
-- somebody in one is coming toward you.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Types"))

type CastMember = Types.CastMember

-- What is written over every one of them. A rank rather than a name, because a name is
-- the first half of a relationship and there is not going to be one.
local DISPLAY_NAME = "Officer"

-- The uniform. One shirt and one pair of trousers across every body here, so that what
-- reads at fifty studs is the uniform rather than the person in it -- which is both the
-- honest thing and the useful one, since recognising the uniform at distance is the
-- skill this system is actually asking for.
--
-- Zero until the assets exist, matching every other body in the game today. When they
-- are made, these two numbers are the only edit: the bodies below do not change.
local UNIFORM_SHIRT = 0
local UNIFORM_PANTS = 0

-- Five, and the number matters slightly. The top tier puts six officers in the world at
-- once, so at five bodies a full citywide response has exactly one repeat in it -- enough
-- variety that the street does not look cloned, not so much that anybody starts telling
-- them apart. Adding a sixth would be fine. Adding twenty would be writing characters.
local Bodies: { CastMember } = {
	{
		id = "officer_a",
		name = DISPLAY_NAME,
		gender = "male",
		skinColor = Color3.fromRGB(224, 178, 145),
		heightScale = 1.04,
		widthScale = 1.06,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.75,
		shirtAssetId = UNIFORM_SHIRT,
		pantsAssetId = UNIFORM_PANTS,
		hairAssetId = 0,
	},
	{
		id = "officer_b",
		name = DISPLAY_NAME,
		gender = "female",
		skinColor = Color3.fromRGB(168, 122, 92),
		heightScale = 0.99,
		widthScale = 0.97,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.8,
		shirtAssetId = UNIFORM_SHIRT,
		pantsAssetId = UNIFORM_PANTS,
		hairAssetId = 0,
	},
	{
		id = "officer_c",
		name = DISPLAY_NAME,
		gender = "male",
		skinColor = Color3.fromRGB(122, 86, 62),
		heightScale = 1.08,
		widthScale = 1.02,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.7,
		shirtAssetId = UNIFORM_SHIRT,
		pantsAssetId = UNIFORM_PANTS,
		hairAssetId = 0,
	},
	{
		id = "officer_d",
		name = DISPLAY_NAME,
		gender = "female",
		skinColor = Color3.fromRGB(238, 205, 178),
		heightScale = 1.01,
		widthScale = 1.04,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.85,
		shirtAssetId = UNIFORM_SHIRT,
		pantsAssetId = UNIFORM_PANTS,
		hairAssetId = 0,
	},
	{
		id = "officer_e",
		name = DISPLAY_NAME,
		gender = "male",
		skinColor = Color3.fromRGB(196, 150, 116),
		heightScale = 0.97,
		widthScale = 1.09,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.72,
		shirtAssetId = UNIFORM_SHIRT,
		pantsAssetId = UNIFORM_PANTS,
		hairAssetId = 0,
	},
}

if #Bodies == 0 then
	error("[AGES content] there are no police bodies, so no bounty could ever be answered. Add one in content/Police.")
end

local byId: { [string]: CastMember } = {}
for _, member in Bodies do
	if byId[member.id] ~= nil then
		error(`[AGES content] duplicate police body id "{member.id}"`)
	end
	-- Every one of these has to be an adult. `ageOffset` is what re-sizes a peer to the
	-- player's own age, so an officer that carried one would be a six-year-old policeman
	-- attending a six-year-old's burglary -- which is funny exactly once and is also the
	-- kind of thing that ships.
	if member.ageOffset ~= nil then
		error(
			`[AGES content] police body "{member.id}" has an ageOffset, which would size it against`
				.. ` the player's own age. Officers are adults regardless of who they are arresting.`
		)
	end
	byId[member.id] = member
end

local Police = {}

Police.Bodies = Bodies

-- One body, by index, wrapping round the list. Index rather than a random draw because
-- the caller is filling numbered posts in a response and wants them to differ from each
-- other -- and a random pick of five, taken six times, collides about as often as not.
function Police.Body(index: number): CastMember
	return Bodies[(index - 1) % #Bodies + 1]
end

-- Nil for an id nothing authors any more, the same contract Curriculum.Get and
-- Studies.Get offer, and for the same reason.
function Police.Get(id: string): CastMember?
	return byId[id]
end

return Police
