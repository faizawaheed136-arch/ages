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
-- Compared as plain RGB distance, which is not how eyes work -- but the failure this
-- guards against is somebody adding a fifth gang in a shade of an existing one, and for
-- that a crude measure is enough. Tuned so the four below pass with room and so any pair
-- a player would have to squint at does not.
local MIN_COLOR_DISTANCE = 180

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
		-- Orange. The warmest of the four and the one furthest from the game's gold accent
		-- while still being warm, so a Kestrel band is never mistaken at range for a choice
		-- marker hanging over somebody's head.
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

-- Every pair, checked against every other pair. Sixteen comparisons for four gangs, once,
-- at require time -- and the alternative is discovering in a playtest that two gangs are
-- indistinguishable from across a street, which is the one thing the colors exist to
-- prevent.
for i = 1, #SOURCE do
	for j = i + 1, #SOURCE do
		local a, b = SOURCE[i].color, SOURCE[j].color
		local distance = math.sqrt(
			((a.R - b.R) * 255) ^ 2 + ((a.G - b.G) * 255) ^ 2 + ((a.B - b.B) * 255) ^ 2
		)
		if distance < MIN_COLOR_DISTANCE then
			error(
				`[AGES content] gangs "{SOURCE[i].id}" and "{SOURCE[j].id}" wear colors only `
					.. `{math.floor(distance)} apart; at least {MIN_COLOR_DISTANCE} is needed to tell two bands `
					.. `apart across a street`
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
