--!strict
-- The recurring people. Content data only -- no behavior lives here.
--
-- Deliberately a small fixed cast rather than generated strangers. A life is
-- made of the same few faces turning up again and again, and the moment they are
-- random that stops being true: the neighbor who knocks when you are nine has to
-- be the neighbor who knocks when you are forty, or none of it means anything.
-- It is also what makes relationship state possible later without a retrofit,
-- since these ids are already stable and already referenced by events.
--
-- Every member is described by body scales and colors, which need no Roblox
-- asset ids at all, so the cast reads as people from the first run. The asset id
-- slots are polish: fill them from the Studio catalog and the same person gains
-- clothes and hair without a line of logic moving. 0 means "not chosen yet",
-- matching what HumanoidDescription itself uses for an empty slot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local Townsfolk = require(script.Parent.Townsfolk)

type CastMember = Types.CastMember

-- Scales are *build*, not size: multipliers around 1 saying how far off average this
-- person is. Age is applied on top by Config.Growth at the moment the rig is built, so
-- an adult here at 1.0 towers over a two-year-old player without anybody having to
-- write down that they tower -- and a peer stays a peer as the player grows.
local Cast: { CastMember } = {
	{
		id = "mom",
		name = "Mom",
		gender = "female",
		skinColor = Color3.fromRGB(232, 190, 160),
		heightScale = 0.98,
		widthScale = 0.92,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.8,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	{
		id = "dad",
		name = "Dad",
		gender = "male",
		skinColor = Color3.fromRGB(226, 181, 150),
		heightScale = 1.06,
		widthScale = 1.05,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.7,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	{
		id = "neighbor",
		name = "Mr. Alderman",
		gender = "male",
		skinColor = Color3.fromRGB(198, 152, 120),
		heightScale = 1.02,
		widthScale = 1.08,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.75,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	{
		-- The one peer in the authored cast, and so the one member with an ageOffset.
		-- Rae used to be written at 0.9 height and 1.05 head, which was a way of saying
		-- "a child" by hand -- and it was wrong twice: a shrunk adult with a normal head
		-- is a short adult rather than a child, and a number written once meant Rae was
		-- exactly as tall at seventeen as at six. The offset hands both jobs to
		-- Config.Growth, so these three are back to being build: very slightly slight.
		id = "friend",
		name = "Rae",
		gender = "female",
		skinColor = Color3.fromRGB(168, 124, 96),
		ageOffset = 0,
		heightScale = 0.96,
		widthScale = 0.95,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.6,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	-- Tie-gated relationship archetypes.
	--
	-- These are the specific people who hold a mentor, rival, or sibling tie with the
	-- player. The event system uses their cast id ("mentor", "rival", "sibling") to
	-- stage the right person when a tie-gated event fires -- the person who is *your*
	-- mentor shows up, not a random stranger. They are authored bodies so the face is
	-- stable across a life: your mentor at sixteen is your mentor at sixty.
	--
	-- They are placed here, before the gang bosses, because tie events can fire earlier
	-- in a life than gang content.
	{
		id = "mentor",
		name = "Mentor",
		gender = "male",
		skinColor = Color3.fromRGB(180, 135, 100),
		heightScale = 1.05,
		widthScale = 1.0,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.7,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	{
		id = "rival",
		name = "Rival",
		gender = "female",
		skinColor = Color3.fromRGB(150, 110, 85),
		heightScale = 1.02,
		widthScale = 0.98,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.75,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	{
		id = "sibling",
		name = "Sibling",
		gender = "male",
		skinColor = Color3.fromRGB(200, 155, 120),
		heightScale = 1.0,
		widthScale = 1.0,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.65,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	-- An enemy. The person who holds the enemy tie. The event system uses
	-- this cast id ("enemy") to stage the right person when an enemy-gated
	-- event fires -- the person who is *your* enemy shows up.
	{
		id = "enemy",
		name = "Enemy",
		gender = "female",
		skinColor = Color3.fromRGB(120, 90, 70),
		heightScale = 1.05,
		widthScale = 1.0,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.7,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	-- The four people who run the four gangs.
	--
	-- Here rather than in Public.luau, and that placement is forced by Public's own first
	-- rule: nothing may reference one of those by id, and a gang boss is referenced by id
	-- from content/Gangs.luau, holds a rung of yours, and has to be the same face the next
	-- time you walk in. That is the definition of a cast member.
	--
	-- Built as adults with visibly different frames, because these four are the only
	-- authored bodies a player will ever compare side by side -- the game points them at
	-- all four during one decision -- and four strangers of identical build would make the
	-- choice read as a menu of colors rather than of people.
	{
		id = "gang_boss_north",
		name = "Odile",
		gender = "female",
		skinColor = Color3.fromRGB(142, 100, 74),
		heightScale = 1.03,
		widthScale = 0.94,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.75,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	{
		id = "gang_boss_east",
		name = "Bram",
		gender = "male",
		skinColor = Color3.fromRGB(214, 172, 140),
		heightScale = 1.11,
		widthScale = 1.14,
		headScale = 0.98,
		proportionScale = 1,
		bodyTypeScale = 0.55,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	{
		id = "gang_boss_south",
		name = "Marisol",
		gender = "female",
		skinColor = Color3.fromRGB(188, 140, 106),
		heightScale = 0.93,
		widthScale = 1.02,
		headScale = 1.02,
		proportionScale = 1,
		bodyTypeScale = 0.9,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	{
		id = "gang_boss_west",
		name = "Teodor",
		gender = "male",
		skinColor = Color3.fromRGB(240, 205, 178),
		heightScale = 1,
		widthScale = 0.88,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.65,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
}

-- The town's bodies, folded in behind the four. Everything downstream of this file looks
-- a member up by id and does not care where it came from -- NPCService builds an avatar
-- from a description either way -- so this is the whole of what it costs to have a
-- generated population wearing real bodies.
--
-- Appended rather than merged in place, so `Default` stays the first authored member: the
-- person the world sends when an event forgot to say who, and that should never be a
-- stranger the game picked out of a hat.
for _, member in Townsfolk.Bodies do
	table.insert(Cast, member)
end

local byId: { [string]: CastMember } = {}
for _, member in Cast do
	if byId[member.id] ~= nil then
		error(`[AGES content] duplicate cast id "{member.id}"`)
	end
	byId[member.id] = member
end

if #Cast == 0 then
	error("[AGES content] the cast is empty, so no visitor event could ever be staged")
end

return {
	All = Cast,
	ById = byId,
	-- Who turns up when an event didn't say. Never nil: the check above
	-- guarantees there is someone.
	Default = Cast[1],
}
