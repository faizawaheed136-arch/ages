--!strict
-- What somebody can be to you.
--
-- A bond is a number that says how a person feels about you. A tie is a word that says
-- what the two of you are. They are not the same thing and the difference is the reason
-- this file exists: a bond rises because you turned up and falls because you did not,
-- with nobody deciding anything, whereas a tie is only ever conferred by an offer the
-- player picked off a panel while standing in front of the person it is about.
--
-- Put the other way round: if friendship were a bond threshold, then everybody you were
-- reliably nice to would become your friend on some birthday you were not paying
-- attention on, and the game would be telling you about your own life after the fact.
-- Making it an offer means there is a moment. The bond is what unlocks the moment; the
-- moment is what makes it true.
--
-- **Why this is not a flag.** Flags in content/Flags.luau are facts about the *life* and
-- every one of them is declared by hand. A tie is a fact about a *pair*, and one side of
-- that pair is usually generated -- the town is Config.Town.Count ids that nobody typed
-- and that change the day that number changes. So this file declares the handful of
-- words, and the person they attach to is a key at runtime.
--
-- **Why the list is short.** Three rungs across a whole life, and all of them are
-- friendship. A game with eleven grades of closeness has quietly replaced a relationship
-- with a progress bar, which is the exact thing bonds are hidden from the player to
-- avoid. If a fourth is ever wanted, the question to answer first is what sentence a
-- player would say about it that they could not already say about one of these -- and,
-- for AGES specifically, whether a 13+ life can hold it, which is why there is no partner.
--
-- Phase 5 adds three structural slots that replace romance: mentor, rival, sibling.
-- Each is capped at one and sits above the friendship ladder. They are parallel tracks --
-- you can have one of each -- because a life holds multiple kinds of significance.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type TieDef = Types.TieDef

-- Same shape as flag ids and checked the same way, because they are written by hand in
-- the same content files and compared as strings in the same places.
local ID_PATTERN = "^[a-z][a-z0-9_]*$"

local SOURCE: { TieDef } = {
	-- Somebody you know by name and who knows you. The cheapest rung, and it is here
	-- because without it there is no difference between the shopkeeper you have spoken
	-- to forty times and the one you walked past -- and there should be, because the
	-- player did something to make it so.
	{
		id = "known",
		label = "knows you",
		rank = 1,
	},
	-- An actual friend. No limit: a life with six friends in it is a good life, and
	-- capping this would make the game an argument about who to drop.
	{
		id = "friend",
		label = "friend",
		rank = 2,
	},
	-- The one. Capped at one on purpose, and this cap is the whole point of the ladder:
	-- it is the first and only thing in AGES that a player can have with just one person,
	-- so it is the first relationship decision that costs something to make. It is the top
	-- rung deliberately -- a life is built around a closest friend, and there is nothing
	-- closer for the ladder to reach toward.
	--
	-- Note what the cap does *not* do: it never takes a tie away. The rung is simply not
	-- offered by anybody else while it is spoken for, which is refusing to write a
	-- friendship the player did not end rather than quietly demoting one they earned.
	-- Ending one properly would need a surface to end it on, which does not exist yet; until
	-- it does, the cap holds by silence rather than by taking anything back.
	{
		id = "closest",
		label = "closest friend",
		rank = 3,
		limit = 1,
	},
	-- A mentor. Capped at one. Offered by an older person when the bond is deep and the
	-- player has something to learn. The mentor tie unlocks guidance offers and marks the
	-- person as a teacher in your life. Not a parent -- a chosen guide.
	{
		id = "mentor",
		label = "mentor",
		rank = 4,
		limit = 1,
	},
	-- A rival. Capped at one. Offered by someone whose bond with you has gone negative --
	-- a person you wronged, outshone, or crossed. The rival tie unlocks competitive offers
	-- and marks the person as an adversary who respects you enough to chase you. Negative
	-- ties are content: a rival is a relationship, not the absence of one.
	{
		id = "rival",
		label = "rival",
		rank = 5,
		limit = 1,
	},
	-- A chosen sibling. Capped at one. Offered by a peer when the bond is at its peak and
	-- the offer is to make it permanent -- not by blood, but by choice. The sibling tie
	-- unlocks lifelong loyalty offers and marks the person as family you chose.
	{
		id = "sibling",
		label = "sibling",
		rank = 6,
		limit = 1,
	},
}

local byId: { [string]: TieDef } = {}
local seenRank: { [number]: string } = {}

for _, def in SOURCE do
	if not string.match(def.id, ID_PATTERN) then
		error(`[AGES content] tie id "{def.id}" must be lowercase words joined by underscores`)
	end
	if byId[def.id] ~= nil then
		error(`[AGES content] duplicate tie id "{def.id}"`)
	end
	if def.label == "" then
		error(`[AGES content] tie "{def.id}" has no label, so it would show as a blank line on a nameplate`)
	end
	if def.rank ~= math.floor(def.rank) or def.rank < 1 then
		error(`[AGES content] tie "{def.id}" has rank {def.rank}; ranks are whole numbers from 1 up`)
	end
	-- Two ties at one rank would make "closer than" ambiguous, and every comparison in
	-- this file and in People.OffersFor is a rank comparison. It would not error at
	-- runtime; it would just make one of the two impossible to require.
	local taken = seenRank[def.rank]
	if taken ~= nil then
		error(`[AGES content] ties "{taken}" and "{def.id}" are both rank {def.rank}; ranks order the ladder`)
	end
	seenRank[def.rank] = def.id

	local limit = def.limit
	if limit ~= nil and (limit ~= math.floor(limit) or limit < 1) then
		error(`[AGES content] tie "{def.id}" is limited to {limit} people; a limit is a whole number from 1 up`)
	end

	byId[def.id] = def
end

local Ties = {}

Ties.All = SOURCE
Ties.ById = byId

-- How close a tie is, and zero for nobody in particular. The one comparison the rest of
-- the game does with these, wrapped so that "no tie" is a number rather than a case
-- every caller has to remember to write.
function Ties.RankOf(tieId: string?): number
	if tieId == nil then
		return 0
	end
	local def = byId[tieId]
	return if def ~= nil then def.rank else 0
end

-- Whether `held` is that tie or a closer one. What needsTie means, and what stops an
-- offer written for a friend from disappearing the moment somebody becomes more than one.
function Ties.Meets(held: string?, needed: string?): boolean
	if needed == nil then
		return true
	end
	return Ties.RankOf(held) >= Ties.RankOf(needed)
end

-- Refuses a tie id nothing declares. The same defence Flags.AssertKnown is: a mistyped
-- tie on an offer is an offer that can never be reached or a rung that never lands, and
-- neither has a runtime symptom anybody would notice.
function Ties.AssertKnown(tieId: string?, where: string)
	if tieId == nil then
		return
	end
	if byId[tieId] == nil then
		error(`[AGES content] {where} refers to tie "{tieId}", which is not declared in Ties.luau`)
	end
end

-- What to show under somebody's name, or nil for the people who are nobody in particular
-- -- which is most of a town, and a nameplate that said so on every head would be noise.
function Ties.LabelOf(tieId: string?): string?
	if tieId == nil then
		return nil
	end
	local def = byId[tieId]
	return if def ~= nil then def.label else nil
end

return Ties
