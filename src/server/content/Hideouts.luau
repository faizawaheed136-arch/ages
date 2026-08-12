--!strict
-- Where in town you can change your clothes.
--
-- Content, and a short list for the same reason Tills is a short list -- but the argument
-- here is the stronger one. A disguise deletes the police's belief about where you are, and
-- a verb that powerful has to cost a walk. If you could change anywhere the answer to being
-- wanted would be "duck behind the nearest van", which is one decision made once and is the
-- thing this system exists to avoid. Four marks across the map means the answer is instead
-- "which of these can I reach from here, through a town that is looking for me" -- and that
-- question has a different answer every time, because the search ring is somewhere new.
--
-- Every id has to be a place point in the built world, the same ones PlaceService indexes,
-- because the mark is stood up relative to one. DisguiseService checks the whole list at
-- startup and names anything that does not resolve, rather than leaving a hideout that
-- quietly is not there -- which the player would experience as running to a corner of the
-- map during the worst thirty seconds of their afternoon and finding nothing.
--
-- The clothing store is on this list *and* on Tills, and that is the best accident in the
-- whole system: the place you most want to be able to run to is a place you may already
-- have robbed. Nothing enforces the tension -- the shop does not lock you out -- but a
-- player who has just emptied its drawer and is now standing in it changing their shirt
-- while the clerk watches is playing a better game than one who never noticed.

local Hideouts = {}

-- One place you can change.
export type Spot = {
	-- The place id, which is what the mark is built against.
	place: string,
	-- What the mark says on it, in the world. Short, because it is read at a run.
	label: string,
}

local Spots: { Spot } = {
	-- Home. Free of any tension and deliberately so: the first time a player is wanted they
	-- should have one obvious answer, even if it is the longest walk on the list. Learning
	-- that the other three exist is the progression.
	{ place = "home", label = "Change" },

	-- The one you already know, because you may have robbed it.
	{ place = "clothing_store", label = "Change" },

	-- Mid-map, off the main street, and the one that makes a spree survivable: without it
	-- the middle of town has no answer at all and every chase resolves as a run for the
	-- edges, which is the same route every time.
	{ place = "gym", label = "Change" },

	-- The civic end, which is to say the wrong end -- a mark within sight of the police
	-- station. It is on the list because the best escape in the game should sometimes be
	-- the one nobody sane would take, and a player who makes it work has done something.
	{ place = "library", label = "Change" },
}

-- Loud at require time rather than at the moment somebody sprints into a room, which is the
-- standing rule for content in this tree and matters more here than anywhere: this list is
-- read under pressure and a mistake in it surfaces at the least recoverable moment.
local seen: { [string]: boolean } = {}
for index, spot in Spots do
	if spot.place == "" then
		error(`[AGES content] Hideouts[{index}] has no place id. Every hideout must name a place point.`)
	end
	if seen[spot.place] then
		error(
			`[AGES content] two hideouts claim the place "{spot.place}". `
				.. `A place point can only hold one mark -- remove one of them from Hideouts.luau.`
		)
	end
	seen[spot.place] = true
	if spot.label == "" then
		error(
			`[AGES content] hideout "{spot.place}" has no label. `
				.. `A mark with nothing written on it is a mark nobody runs to.`
		)
	end
end

Hideouts.Spots = Spots

-- Nil for a place with no mark in it, which is almost every place in town.
function Hideouts.Get(place: string): Spot?
	for _, spot in Spots do
		if spot.place == place then
			return spot
		end
	end
	return nil
end

return Hideouts
