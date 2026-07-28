--!strict
-- What each delivery mode *is*, structurally. Config owns the tunable numbers;
-- this owns the fixed facts that three separate systems would otherwise each
-- keep a copy of and eventually disagree about.
--
-- Route is the important one. An event reaches the player exactly one way, and
-- the three routes are disjoint by construction:
--
--   Immediate  handed over the moment it is picked, by a birthday. No world
--              presence at all -- the panel is the whole delivery.
--   Ambient    staged into the world by the scheduler and collected by going to
--              it. The object is spawned per event and belongs to one player.
--   Anchored   reached by walking to hand-placed geometry that is always there.
--              Never scheduled; the player finds it or they don't.
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

export type Route = "Immediate" | "Ambient" | "Anchored"

local ROUTES: {
	Memory: Route,
	Direct: Route,
	Interact: Route,
	Letter: Route,
	PhoneCall: Route,
	NPCApproach: Route,
} = {
	Memory = "Immediate",
	Direct = "Immediate",
	Interact = "Anchored",
	Letter = "Ambient",
	PhoneCall = "Ambient",
	NPCApproach = "Ambient",
}

function Delivery.RouteOf(delivery: EventDelivery): Route
	return ROUTES[delivery]
end

-- Whether this mode puts something in the world that has to be reached before
-- the prompt opens. True for both world routes, which is exactly the set that
-- needs a delivery point, an owner and a way to be cleaned up.
function Delivery.IsStaged(delivery: EventDelivery): boolean
	return ROUTES[delivery] ~= "Immediate"
end

return Delivery
