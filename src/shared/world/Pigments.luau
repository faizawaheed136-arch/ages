--!strict
-- The paint an Art lesson can be made of.
--
-- Shared for the same reason Stations is, and more so. The studies that get copied are
-- content and stay content -- `src/server/content/Studies.luau` -- but a pigment is not
-- content in that sense, it is a physical thing on a shelf: the server builds the study
-- wall out of these colours, and the client draws the palette swatches and every painted
-- cell of the canvas out of the same ones.
--
-- The colour is the whole payload here. A canvas is sixteen colours and a wall is
-- sixteen colours and the entire mechanic is comparing one to the other, so the two ends
-- have to be reading the identical Color3 -- not two hand-copied triples that drifted by
-- four in the blue and turned "notice the difference" into a bug report. Sending them
-- down the wire instead would be the same eight colours on every push forever, and would
-- still leave the wall and the panel free to disagree.
--
-- Deliberately just the paint. Nothing here knows what a study is, so this module
-- requires nothing at all and both places can hold it.

local Pigments = {}

-- One tube of paint.
export type Pigment = {
	id: string,
	-- Shown under the swatch. Short enough to sit in a palette row without wrapping,
	-- because a palette that has to be read word by word is a palette you look at
	-- instead of looking at the study.
	name: string,
	-- The single character a study's grid uses for this pigment. Studies are authored as
	-- rows of letters rather than as arrays of ids, because a composition written as four
	-- four-letter strings can be *seen* in the source file, and one written as sixteen
	-- quoted ids cannot -- and a picture you cannot see while authoring is a picture
	-- nobody will ever fix.
	letter: string,
	color: Color3,
}

-- The full set, in the order a topped-out palette hands them over.
--
-- Chosen to be told apart at distance rather than to be pretty, exactly as the lab's
-- stations are, and then one step further: no two of these may be close enough that
-- painting one for the other is invisible, because the scorer gives part credit by
-- colour distance and a pair nobody can distinguish would be a pair of free points.
-- The spread is checked below rather than trusted.
local ALL: { Pigment } = {
	{ id = "white", name = "White", letter = "w", color = Color3.fromRGB(238, 235, 226) },
	{ id = "charcoal", name = "Charcoal", letter = "k", color = Color3.fromRGB(40, 42, 48) },
	{ id = "slate", name = "Slate", letter = "l", color = Color3.fromRGB(112, 124, 138) },
	{ id = "sky", name = "Sky", letter = "s", color = Color3.fromRGB(132, 180, 214) },
	{ id = "deep", name = "Deep", letter = "d", color = Color3.fromRGB(36, 68, 122) },
	{ id = "ochre", name = "Ochre", letter = "o", color = Color3.fromRGB(212, 162, 68) },
	{ id = "rust", name = "Rust", letter = "r", color = Color3.fromRGB(168, 78, 50) },
	{ id = "moss", name = "Moss", letter = "m", color = Color3.fromRGB(94, 130, 76) },
}

-- How far apart two pigments have to be to count as different paint, on the same 0-1
-- scale the scorer works in. A lesson in noticing differences cannot contain two colours
-- the player has no way of telling apart -- that is not a hard cell, it is an unfair one,
-- and the player would never find out which of the two they were supposed to have used.
--
-- Not in Config, unlike almost every other number in this codebase, and this is the
-- exception that proves that rule: it is not a tunable. It is a property of the eight
-- colours on the list above, checked against them at require time, and the only thing
-- anybody would ever do with it is discover they had added a ninth pigment too close to
-- one of these. Moving it to Config would invite somebody to lower it instead of moving
-- the colour, which is precisely the wrong fix.
local MIN_SEPARATION = 0.12

local byId: { [string]: Pigment } = {}
local byLetter: { [string]: Pigment } = {}
for _, pigment in ALL do
	if byId[pigment.id] ~= nil then
		error(`[AGES content] duplicate pigment id "{pigment.id}"`)
	end
	if #pigment.letter ~= 1 then
		error(
			`[AGES content] pigment "{pigment.id}" has letter "{pigment.letter}", which is not one character.`
				.. ` Study grids are rows of single letters, so every pigment needs exactly one.`
		)
	end
	if byLetter[pigment.letter] ~= nil then
		error(
			`[AGES content] pigments "{byLetter[pigment.letter].id}" and "{pigment.id}" both use the letter`
				.. ` "{pigment.letter}". Every study grid in the game would silently mean one of them.`
				.. ` Give one of the two a different letter.`
		)
	end
	byId[pigment.id] = pigment
	byLetter[pigment.letter] = pigment
end

-- The furthest apart two of these colours get, which is what turns a raw RGB gap into
-- the 0-1 share the scorer needs. Measured off the list rather than assumed to be
-- black-to-white, because the list contains neither: the darkest is charcoal and the
-- lightest is off-white, and dividing by a distance no pair of these can actually reach
-- would quietly compress every score in the subject toward the top.
local widest = 0

-- Raw distance between two colours, in the same 0-255-per-channel space Color3.fromRGB
-- reads. Unweighted on purpose. A perceptual metric would be more correct about how
-- different two colours *look*, and would also mean the player's score depended on a
-- formula they cannot see -- and the honest version of this mechanic is that a cell is
-- worth more the nearer the paint is to the right paint, in the plainest sense of near.
local function rawDistance(a: Color3, b: Color3): number
	local dr = (a.R - b.R) * 255
	local dg = (a.G - b.G) * 255
	local db = (a.B - b.B) * 255
	return math.sqrt(dr * dr + dg * dg + db * db)
end

for i = 1, #ALL do
	for j = i + 1, #ALL do
		local gap = rawDistance(ALL[i].color, ALL[j].color)
		if gap > widest then
			widest = gap
		end
	end
end

if widest <= 0 then
	-- Only reachable by cutting the list down to one pigment or eight identical ones,
	-- either of which would make every cell score the same and the subject unplayable.
	error("[AGES content] every pigment is the same colour -- Art cannot be scored. See shared/world/Pigments.")
end

for i = 1, #ALL do
	for j = i + 1, #ALL do
		local share = rawDistance(ALL[i].color, ALL[j].color) / widest
		if share < MIN_SEPARATION then
			error(
				`[AGES content] pigments "{ALL[i].id}" and "{ALL[j].id}" are only {string.format("%.3f", share)}`
					.. ` apart, under the {MIN_SEPARATION} a player can tell apart across a room. Move one of the`
					.. ` two colours in shared/world/Pigments rather than lowering the floor -- a cell nobody`
					.. ` can see the answer to is not a hard cell, it is an unfair one.`
			)
		end
	end
end

-- How close two pigments are, as 1 for the same paint down to 0 for the furthest apart
-- two on the list get. This is the entire scorer for a painted cell, and it lives here
-- rather than in ArtService because the client needs the identical number to draw a cell
-- as nearly-right rather than wrong -- and two implementations of "how close is this"
-- is exactly the drift that makes a player argue with their own score.
function Pigments.Closeness(a: Pigment, b: Pigment): number
	if a.id == b.id then
		return 1
	end
	return math.clamp(1 - rawDistance(a.color, b.color) / widest, 0, 1)
end

-- Nil for a letter no pigment uses. The caller handles it rather than being handed a
-- default: the only thing that asks is the study parser, and a study containing a letter
-- the game has no paint for has to name the study and the letter, not quietly paint it
-- white and ship a picture nobody authored.
function Pigments.FromLetter(letter: string): Pigment?
	return byLetter[letter]
end

-- Nil for an id nothing stocks any more, for the same reason Stations.Get is nil-able:
-- an id can arrive from a client, and inventing a pigment to satisfy it would be
-- letting the client add paint to the shelf.
function Pigments.Get(id: string): Pigment?
	return byId[id]
end

Pigments.All = ALL

return Pigments
