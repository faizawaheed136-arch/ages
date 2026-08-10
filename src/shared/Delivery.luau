--!strict
-- What each delivery mode *is*, structurally. Config owns the tunable numbers;
-- this owns the fixed facts that three separate systems would otherwise each
-- keep a copy of and eventually disagree about.
--
-- Route is the important one. An event reaches the player exactly one way, and
-- the routes are disjoint by construction:
--
--   Immediate  handed over the moment it is picked, by a birthday. No world
--              presence at all -- the panel is the whole delivery.
--   Ambient    staged into the world by the scheduler and collected by going to
--              it. The object is spawned per event and belongs to one player.
--   Wandered   put on whatever floor the player can reach and pointed at, then
--              collected by going to it. Ambient's sibling, and the difference is
--              the whole point: Ambient needs a tagged point to arrive at, so an
--              untagged room is a room where nothing happens. Wandered finds its
--              own spot, which is what lets a childhood be playable in a house
--              nobody has dressed yet. Never scheduled -- it is a loop rather than
--              a timer, and there is one out there whenever there could be.
--   Anchored   reached by walking to hand-placed geometry that is always there.
--              Never scheduled; the player finds it or they don't.
--   Shift      fired by being at work while working. Not scheduled and not
--              staged: the condition is an activity rather than a place or a
--              date, which is why it is its own route rather than a filter over
--              one of the others. Its own route is also what guarantees a
--              birthday can never hand you "a customer is shouting at you" in
--              your own kitchen -- the birthday pool asks for Immediate and
--              these are not in it.
--
-- Keeping this here is what stops a birthday from handing out a letter (which
-- would announce mail the player never picked up) or the scheduler from staging
-- a Memory (which has nowhere to be staged). ROUTES is a closed record rather
-- than a loose map on purpose: add a variant to Types.EventDelivery and this
-- file stops type-checking until the new mode has been told which route it
-- takes. The alternative is a mode that silently never fires and is never
-- missed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type EventDelivery = Types.EventDelivery

local Delivery = {}

export type Route = "Immediate" | "Ambient" | "Wandered" | "Anchored" | "Shift"

local ROUTES: {
	Memory: Route,
	Direct: Route,
	Wander: Route,
	Interact: Route,
	Letter: Route,
	PhoneCall: Route,
	NPCApproach: Route,
	Shift: Route,
} = {
	Memory = "Immediate",
	Direct = "Immediate",
	Wander = "Wandered",
	Interact = "Anchored",
	Letter = "Ambient",
	PhoneCall = "Ambient",
	NPCApproach = "Ambient",
	Shift = "Shift",
}

function Delivery.RouteOf(delivery: EventDelivery): Route
	return ROUTES[delivery]
end

return Delivery
