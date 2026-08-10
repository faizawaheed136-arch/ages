--!strict
-- Everybody else. The people who are in a room because rooms have people in them.
--
-- Separate from Cast for a reason Cast itself states in its first paragraph: those
-- four recur, and the neighbor who knocks when you are nine has to be the neighbor
-- who knocks when you are forty or none of it means anything. Serving Mom at a till
-- eleven times in a four-minute shift would spend that on nothing.
--
-- So these are strangers, and being strangers is their entire job. Nothing may ever
-- reference one of them by id, no event may cast one, and no relationship should ever
-- be recorded against one -- the moment any of that is wanted, the person wanted is a
-- cast member and belongs in the other file. The ids exist only so a debug line can
-- say which body it built.
--
-- Same CastMember shape, so they cost nothing extra: NPCService builds one exactly
-- the way it builds a parent, head tracking and all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type CastMember = Types.CastMember

-- Eight, which is enough that a whole shift rarely repeats a face and few enough to
-- read them as regulars rather than as a crowd. Spread across height, build and skin
-- tone on purpose: a queue of people who are all the same size is the thing that
-- makes a generated crowd look generated.
local Public: { CastMember } = {
	{
		id = "public_1",
		gender = "male",
		name = "Customer",
		skinColor = Color3.fromRGB(238, 200, 172),
		heightScale = 1.04,
		widthScale = 1,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.7,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	{
		id = "public_2",
		gender = "female",
		name = "Customer",
		skinColor = Color3.fromRGB(150, 108, 78),
		heightScale = 0.94,
		widthScale = 0.9,
		headScale = 1.02,
		proportionScale = 1,
		bodyTypeScale = 0.85,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	{
		id = "public_3",
		gender = "male",
		name = "Customer",
		skinColor = Color3.fromRGB(206, 160, 126),
		heightScale = 1.1,
		widthScale = 1.12,
		headScale = 0.98,
		proportionScale = 1,
		bodyTypeScale = 0.6,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	{
		id = "public_4",
		gender = "female",
		name = "Customer",
		skinColor = Color3.fromRGB(120, 84, 60),
		heightScale = 0.99,
		widthScale = 0.96,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.9,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	{
		id = "public_5",
		gender = "male",
		name = "Customer",
		skinColor = Color3.fromRGB(246, 214, 190),
		heightScale = 0.9,
		widthScale = 0.88,
		headScale = 1.04,
		proportionScale = 1,
		bodyTypeScale = 0.75,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	{
		id = "public_6",
		gender = "female",
		name = "Customer",
		skinColor = Color3.fromRGB(178, 132, 100),
		heightScale = 1.07,
		widthScale = 1.04,
		headScale = 1,
		proportionScale = 1,
		bodyTypeScale = 0.65,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	{
		id = "public_7",
		gender = "male",
		name = "Customer",
		skinColor = Color3.fromRGB(96, 66, 48),
		heightScale = 1.01,
		widthScale = 1.08,
		headScale = 0.99,
		proportionScale = 1,
		bodyTypeScale = 0.8,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
	{
		id = "public_8",
		gender = "female",
		name = "Customer",
		skinColor = Color3.fromRGB(222, 178, 142),
		heightScale = 0.96,
		widthScale = 0.94,
		headScale = 1.01,
		proportionScale = 1,
		bodyTypeScale = 0.72,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
}

local seen: { [string]: true } = {}
for _, member in Public do
	if seen[member.id] then
		error(`[AGES content] duplicate public id "{member.id}"`)
	end
	seen[member.id] = true
end

if #Public == 0 then
	error("[AGES content] the public is empty, so no task could ever have anybody waiting on it")
end

return {
	All = Public,
	-- Whoever turns up next. Random rather than in rotation: a shop where the same
	-- eight people arrive in the same order is a shop with eight people in it.
	Someone = function(): CastMember
		return Public[math.random(#Public)]
	end,
}
