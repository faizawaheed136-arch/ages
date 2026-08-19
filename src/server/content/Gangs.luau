--!strict
-- The four gangs. Content only -- no behavior lives here.
--
-- One to a side of the city, which is a promise this file makes and cannot yet keep:
-- territory is deferred until the map expansion, so `side` is written down and read by
-- nothing. That is deliberate rather than sloppy. Deciding four gangs' identities is a
-- one-way door -- their colors and their names are what players will call them for the
-- life of the game -- and doing it later, against streets that already exist, would mean
-- re-deciding it under pressure from geometry. The seam is here; the districts hang off
-- it when there are districts.
--
-- **On the colors.** These four do the most work of anything in this file. They are the
-- band on every member's head and the only thing that tells a mixed room of players and
-- NPCs apart at distance, so they are chosen against each other and against the world:
-- roughly ninety degrees apart on the wheel, all saturated, none of them a color the town
-- already uses in bulk (asphalt grey, grass green, brick red, the warm gold of a choice
-- marker). A fifth gang would have to fit in the gaps, which is one of two reasons there
-- are four.
--
-- The other reason is the boss. Each of these needs a person standing somewhere with dots
-- over their head, and four is the point where a player can plausibly go and meet all of
-- them before choosing rather than picking the first one they tripped over.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local Cast = require(script.Parent.Cast)

type GangDef = Types.GangDef

local ID_PATTERN = "^[a-z][a-z0-9_]*$"

-- How far apart two gang colors have to be before they count as different colors.
--
-- This was plain RGB distance with a floor of 180, and the comment above it said it had
-- been "tuned so the four below pass with room". They did not pass. Two pairs were under
-- the floor, this file threw at require time, and because `init.server.luau` requires it
-- on the boot path with no pcall around it, the symptom was not a color warning -- it was
-- a game that loaded with no services in it at all.
--
-- The reflex fix is to move a color until the number goes green. That would have been
-- wrong, because the number was measuring the wrong thing. Raw RGB distance does not
-- order these four the way an eye does, and the proof is in the pairs it was ranking:
--
--   east/south   RGB 155.9 -- REJECTED -- but 96.2 apart perceptually
--   north/west   RGB 208.0 -- accepted -- and only 95.0 apart perceptually
--
-- It rejected a pair that is *further* apart to look at than a pair it let through. A
-- threshold laid over a metric that misorders its own inputs cannot mean what it claims,
-- so no value of it would have been correct and moving a color to satisfy it would have
-- been moving a color to satisfy a broken ruler.
--
-- So the ruler is replaced, not the colors. CIE76 in L*a*b* below, which is a real
-- perceptual space, and the floor is measured off both ends rather than picked:
--
--   * The failure being guarded against is a fifth gang added in a shade of an existing
--     one. Shading each of the four (15% darker, 12% lighter, 11 degrees of hue, 12% less
--     saturated) tops out at 23.1. A floor has to sit above that or it catches nothing.
--   * The four real colors' closest pair is 87.8. A floor has to sit below that or it
--     rejects a palette that is already fine.
--
-- 50 is between them with room on both sides: 2.2x the worst near-shade, and 1.8x below
-- the tightest real pair. For scale, 2.3 in this space is "just noticeable".
--
-- Note that shared/world/Pigments deliberately keeps raw RGB for its own color guard, and
-- that is not an inconsistency to tidy up. There the distance feeds a *score* the player
-- is paid on, so it has to be near in the plainest sense of near. Here nobody is scored;
-- the only question is whether two bandanas read as two gangs across a street.
local MIN_COLOR_DIFFERENCE = 50

-- sRGB -> CIE L*a*b*, D65. Color3 channels are already 0-1, so there is no /255 here.
local function toLab(color: Color3): (number, number, number)
	local function linear(channel: number): number
		if channel <= 0.04045 then
			return channel / 12.92
		end
		return ((channel + 0.055) / 1.055) ^ 2.4
	end

	local r, g, b = linear(color.R), linear(color.G), linear(color.B)

	-- Divided through by the D65 white point, which is what makes the result relative to
	-- "white under daylight" rather than to an absolute the numbers below would not match.
	local x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
	local y = (0.2126 * r + 0.7152 * g + 0.0722 * b)
	local z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883

	-- The cube root is what bends the linear numbers into even perceptual steps. The
	-- straight-line piece below the knee keeps it from going vertical near black.
	local function bend(t: number): number
		if t > 0.008856 then
			return t ^ (1 / 3)
		end
		return 7.787 * t + 16 / 116
	end

	x, y, z = bend(x), bend(y), bend(z)
	return 116 * y - 16, 500 * (x - y), 200 * (y - z)
end

local function colorDifference(a: Color3, b: Color3): number
	local aL, aA, aB = toLab(a)
	local bL, bA, bB = toLab(b)
	return math.sqrt((aL - bL) ^ 2 + (aA - bA) ^ 2 + (aB - bB) ^ 2)
end

local SOURCE: { GangDef } = {
	{
		id = "north",
		name = "The Ridge",
		-- Cyan. Reads coldest of the four and holds up best at dusk, which matters because
		-- this is the color a player sees first: the north boss is the one nearest the
		-- civic end of the city where a young life already has reasons to be.
		color = Color3.fromRGB(64, 220, 232),
		side = "north",
		bossPlaceId = "cinema",
		bossCastId = "gang_boss_north",
		pitch = "We were here before the towers. Keep your head, and the north keeps you.",
	},
	{
		id = "east",
		name = "Kestrel",
		-- Orange. The warmest of the four, and about as far from the game's gold accent as a
		-- warm color can get: measured against Config.Guide.Color, this sits 42.5 away and
		-- the best any warm color manages is 46.6. Warmth is boxed in on both sides -- the
		-- gold marker sits at hue 41 and the heat meter's red at hue 2 -- so this is close
		-- to the ceiling rather than a free choice, and it is why a Kestrel band is told
		-- from a choice marker by being fabric on a body rather than by hue alone.
		color = Color3.fromRGB(255, 138, 40),
		side = "east",
		bossPlaceId = "gas_station",
		bossCastId = "gang_boss_east",
		pitch = "Everything on this side moves through us. Move with it or move.",
	},
	{
		id = "south",
		name = "Sable Row",
		-- Magenta. There is nothing in the generated world this color, which is exactly
		-- why it is here -- the south gang is the one whose members are visible against the
		-- park and the greenfield blocks, where every other palette is green.
		color = Color3.fromRGB(236, 72, 180),
		side = "south",
		bossPlaceId = "garage",
		bossCastId = "gang_boss_south",
		pitch = "Nobody down here is asking permission. Neither should you.",
	},
	{
		id = "west",
		name = "The Old Line",
		-- Lime. The only one of the four that sits near a natural color, and it is pushed
		-- far enough toward yellow that it separates from grass at fifty studs. Checked on
		-- purpose: the west runs back toward the suburb, which is the greenest ground on
		-- the map.
		color = Color3.fromRGB(178, 246, 60),
		side = "west",
		bossPlaceId = "park",
		bossCastId = "gang_boss_west",
		pitch = "The town was ours when it was a town. It is still ours.",
	},
}

local byId: { [string]: GangDef } = {}
local seenSide: { [string]: string } = {}
local seenPlace: { [string]: string } = {}

for _, def in SOURCE do
	if not string.match(def.id, ID_PATTERN) then
		error(`[AGES content] gang id "{def.id}" must be lowercase words joined by underscores`)
	end
	if byId[def.id] ~= nil then
		error(`[AGES content] duplicate gang id "{def.id}"`)
	end
	if def.name == "" then
		error(`[AGES content] gang "{def.id}" has no name, so it would show as a blank line on the panel`)
	end
	if def.pitch == "" then
		error(`[AGES content] gang "{def.id}" has no pitch; the panel that offers to let you in would be a blank box`)
	end

	-- Two gangs on one side is not a content error the day it is written -- it is a
	-- territory map with a hole in it, months later, when the districts land.
	local sideTaken = seenSide[def.side]
	if sideTaken ~= nil then
		error(`[AGES content] gangs "{sideTaken}" and "{def.id}" both hold the {def.side} side; one gang to a side`)
	end
	seenSide[def.side] = def.id

	-- Two bosses at one place point would stand inside each other, and whichever spawned
	-- second would be the only one a player could ever talk to.
	local placeTaken = seenPlace[def.bossPlaceId]
	if placeTaken ~= nil then
		error(
			`[AGES content] gangs "{placeTaken}" and "{def.id}" both post their boss at "{def.bossPlaceId}"; `
				.. `they would spawn on the same spot`
		)
	end
	seenPlace[def.bossPlaceId] = def.id

	-- A boss with no body is a gang that can be joined by nobody, and the symptom is a
	-- place point with nothing standing at it rather than an error anybody would connect
	-- back to this file.
	if Cast.ById[def.bossCastId] == nil then
		error(
			`[AGES content] gang "{def.id}" is run by cast member "{def.bossCastId}", `
				.. `which is not declared in Cast.luau`
		)
	end

	byId[def.id] = def
end

-- Every pair, checked against every other pair. Six comparisons for four gangs, once, at
-- require time -- and the alternative is discovering in a playtest that two gangs are
-- indistinguishable from across a street, which is the one thing the colors exist to
-- prevent.
for i = 1, #SOURCE do
	for j = i + 1, #SOURCE do
		local difference = colorDifference(SOURCE[i].color, SOURCE[j].color)
		if difference < MIN_COLOR_DIFFERENCE then
			error(
				`[AGES content] gangs "{SOURCE[i].id}" and "{SOURCE[j].id}" wear colors only `
					.. `{string.format("%.1f", difference)} apart perceptually; at least {MIN_COLOR_DIFFERENCE} `
					.. `is needed to tell two bands apart across a street. Move one of the two colors in `
					.. `server/content/Gangs rather than lowering the floor -- the floor is set from measurement `
					.. `(a near-shade of an existing gang scores about 23, the four real colors' closest pair `
					.. `scores 88) and lowering it is how a fifth gang ends up wearing a fourth gang's color.`
			)
		end
	end
end

if #SOURCE == 0 then
	error("[AGES content] there are no gangs, so nothing could ever be joined")
end

local Gangs = {}

Gangs.All = SOURCE
Gangs.ById = byId

-- The gang whose boss stands at this place point, or nil for the overwhelming majority of
-- places, which have no boss at all. The reverse of the content table, so GangService can
-- answer "whose dots are these" without walking four entries on every prompt.
function Gangs.AtPlace(placeId: string): GangDef?
	local id = seenPlace[placeId]
	return if id ~= nil then byId[id] else nil
end

return Gangs
