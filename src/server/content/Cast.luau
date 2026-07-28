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

type CastMember = Types.CastMember

-- Scales are HumanoidDescription multipliers around 1. Height is the one that
-- carries most of the read: an adult at 1.0 next to a toddler scaled to 0.3 is
-- already a towering figure without any other work.
local Cast: { CastMember } = {
	{
		id = "mom",
		name = "Mom",
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
		-- Scaled down because they grow up alongside the player and first show up
		-- in the school years. One rig, so they are recognisable later.
		id = "friend",
		name = "Rae",
		skinColor = Color3.fromRGB(168, 124, 96),
		heightScale = 0.9,
		widthScale = 0.9,
		headScale = 1.05,
		proportionScale = 1,
		bodyTypeScale = 0.6,
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	},
}

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
