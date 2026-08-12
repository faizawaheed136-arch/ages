--!strict
-- Which places in town have a drawer worth opening.
--
-- Content, and deliberately a short list rather than "every shop". Three reasons, and
-- the third is the one that matters:
--
--   A shop you can rob is a shop the game has to have furnished with a clerk and a
--   camera, and furnishing forty of them is forty times the cost for no extra idea.
--
--   A spree should be a *route*. If every storefront on the street were a till, the
--   optimal play would be to walk in a straight line with the heat climbing behind
--   you, which is one decision made once. Spacing them out means the walk between two
--   scores is a real choice about which way to go while a search ring drifts.
--
--   And a town where some doors are worth something and others are not is a town with
--   knowledge in it. Learning which is which is the only progression this activity
--   has, and it is the honest kind: it lives in the player rather than in a number.
--
-- Every id here has to be a place point in the built world -- the same ids PlaceService
-- indexes -- because the till is stood up relative to one. An id that does not resolve
-- is a shop that quietly cannot be robbed and nothing in the game would say so, which
-- is why TheftService checks the whole list once at startup and names the offender.
--
-- The bank is not here. It has a vault rather than a till, its own layout and its own
-- answer to "what happens when you are seen", and folding it into this list would mean
-- the first thing built for it was a compromise with a corner store.

local Tills = {}

-- One robbable place.
export type Shop = {
	-- The place id, which is also what the panel names.
	place: string,
	-- What the player calls it. Read off the place point's own label would be more
	-- honest, but the label is a sentence about where to stand -- "the pages & press, by
	-- the counter" -- and a heat notice needs a name.
	name: string,
	-- What the till is worth, as a share of Config.Crime.Theft.TillFloat.
	--
	-- The one difficulty dial in this file, and it is set against how exposed the shop
	-- is rather than against what it sells. A market off the main street with two ways
	-- out is worth less than a pharmacy with one door onto a street the police walk
	-- down, because the thing being priced is the walk away from it.
	-- Safe range: 0.5-1.5.
	richness: number,
}

local Shops: { Shop } = {
	-- The teaching one. Middle of the row, two exits either side, and the smallest float
	-- in town: somewhere to learn what a clerk's shoulders look like when they turn,
	-- without an afternoon riding on it.
	{ place = "pharmacy", name = "First Pharmacy", richness = 0.7 },

	-- A long way up the street from the pharmacy on purpose. The second robbery of a
	-- spree should cost a walk, and this is the walk.
	{ place = "electronics", name = "Volt Electronics", richness = 1.15 },

	{ place = "clothing_store", name = "Thread & Co", richness = 0.9 },

	-- The far end, and the richest of the four. It is also the closest to the civic row,
	-- which is to say the closest to the police station -- so the best drawer in town is
	-- the one where being seen costs the most. That is the trade this list exists to
	-- make, and it is made with geography rather than with a number.
	{ place = "gas_station", name = "Tank & Go", richness = 1.4 },
}

-- Loud at require time rather than at the moment somebody walks into a shop, which is
-- the standing rule for content in this tree.
local seen: { [string]: boolean } = {}
for index, shop in Shops do
	if shop.place == "" then
		error(`[AGES content] Tills[{index}] has no place id. Every shop must name a place point.`)
	end
	if seen[shop.place] then
		error(
			`[AGES content] two tills claim the place "{shop.place}". `
				.. `A place point can only hold one drawer -- remove one of them from Tills.luau.`
		)
	end
	seen[shop.place] = true
	if shop.richness <= 0 then
		error(
			`[AGES content] shop "{shop.place}" has richness {shop.richness}. `
				.. `A till worth nothing is a shop the player robs once and never returns to; `
				.. `remove it from Tills.luau instead.`
		)
	end
end

Tills.Shops = Shops

-- Nil for a place with no drawer in it, which is almost every place in town. Every
-- caller handles that rather than being handed a default: "this shop cannot be robbed"
-- is the answer for most of the map and it is not an error anywhere.
function Tills.Get(place: string): Shop?
	for _, shop in Shops do
		if shop.place == place then
			return shop
		end
	end
	return nil
end

return Tills
