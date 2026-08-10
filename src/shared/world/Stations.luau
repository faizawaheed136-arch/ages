--!strict
-- The things that can stand in the Science lab.
--
-- Shared rather than server-side, which is the one thing about this list worth
-- explaining. The procedures that send you round these stations are content and stay
-- content -- `src/server/content/Procedures.luau`, alongside the questions -- but a
-- station is not content in the same sense. It is a piece of furniture: the server
-- builds a model for it, and the client has to be able to write its name on a bench
-- stack and tint a step chip to match the thing across the room the player is being
-- sent to.
--
-- The alternative was sending station names down the wire on every push, which is the
-- same eight strings four times a second forever, and it would also cost the client the
-- colour -- and the colour is not decoration here. A step chip drawn in the same shade
-- as the station it names is how a player carries "beaker, balance, notebook" across a
-- room without re-reading it, which is precisely the thing mastery is a measure of.
-- Making the player match words to words instead would be making the mechanic harder in
-- the one way that teaches nothing.
--
-- Deliberately just the furniture. Nothing here knows what a procedure is, so this
-- module requires nothing at all and both places can hold it.

local Stations = {}

-- One thing that can stand in the lab. The id is what a procedure step names and what
-- the world builder tags the model with, so the two can never be out of step: a
-- procedure naming a station that does not exist is caught at require time in
-- Procedures.luau rather than by a player walking a room with a missing bench in it.
export type Station = {
	id: string,
	-- Written on the station itself and on the board. A noun, because the board reads as
	-- a list of places and the verb is on the step's own label.
	name: string,
	-- The colour the placeholder model is built in, and the only way the player tells
	-- two stations apart across a room until real models exist. Chosen to be
	-- distinguishable at distance rather than to be pretty -- six stations of six
	-- similar blues is a lab you have to walk up to in order to read, which turns every
	-- step into two trips.
	color: Color3,
}

local ALL: { Station } = {
	{ id = "balance", name = "Balance", color = Color3.fromRGB(206, 178, 96) },
	{ id = "beaker", name = "Beaker", color = Color3.fromRGB(96, 158, 206) },
	{ id = "burner", name = "Hot Plate", color = Color3.fromRGB(200, 104, 84) },
	{ id = "sink", name = "Sink", color = Color3.fromRGB(112, 196, 184) },
	{ id = "microscope", name = "Microscope", color = Color3.fromRGB(140, 122, 190) },
	{ id = "notebook", name = "Notebook", color = Color3.fromRGB(224, 214, 190) },
	{ id = "scale_paper", name = "Weighing Paper", color = Color3.fromRGB(196, 196, 202) },
	{ id = "stirrer", name = "Stirrer", color = Color3.fromRGB(120, 176, 118) },
}

local byId: { [string]: Station } = {}
for _, station in ALL do
	if byId[station.id] ~= nil then
		error(`[AGES content] duplicate lab station id "{station.id}"`)
	end
	byId[station.id] = station
end

-- Nil for an id nothing authors any more. Every caller handles that rather than being
-- handed a default, because the two places this is asked from -- a verdict line and a
-- step chip -- both have a sensible fallback of their own (say the id out loud), and a
-- made-up station would be a lie the player cannot see through.
function Stations.Get(id: string): Station?
	return byId[id]
end

-- The station's name, or the raw id when nothing knows it. Here rather than written out
-- at each of the five call sites, all of which wanted exactly this and one of which
-- would eventually have got the fallback wrong.
function Stations.NameOf(id: string): string
	local station = byId[id]
	return if station ~= nil then station.name else id
end

Stations.All = ALL

return Stations
