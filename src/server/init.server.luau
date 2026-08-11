--!strict
-- Server bootstrap. Requires every service and drives the Init() / Start()
-- lifecycle in dependency order: data must be loadable before stats can be
-- read, money must be pushable before an event can charge for a choice, pocket
-- money must have caught up a loaded profile's ledger before that profile can have
-- a birthday and be paid off it, stats
-- must exist before aging can decay or kill them, events must be
-- listening before a birthday can offer one, enactment must have registered its
-- handler before the first event is offered or that one silently arrives as a
-- panel, scenes must likewise have registered before the first event or the dog
-- the prompt is about never turns up, the body must be watching for spawns before
-- a birthday resizes it, and the world can only offer events once there is an
-- engine to ask. Places must be indexed before anything can be sent to one --
-- it depends on nothing itself, being only an index of what is already built,
-- so it sits as early as the first thing that will want to name a room.
-- Visitors must
-- be sweepable before anything can send one, and deliveries come last of the real
-- services because they register a handler on the world and restore whatever
-- players left standing in it. Work comes after both, because clocking on needs
-- somewhere to clock on at and a shift can raise an event on the same terms as
-- anything else. School sits beside work and after it, needing the same three
-- things -- a place to be, a profile to read and stats to move -- and wiring up to
-- nothing, which is why it is the one service here with no Init to call.
-- People sit after both and last of the real services, because putting somebody in
-- the world needs everything the two before it needed plus a visitor to build --
-- a place to stand at, a profile to read an age and a bond off, stats and money to
-- pay an offer out into, and NPCService swept clean so a Rojo sync mid-session does
-- not leave a second mother behind. It wires up to nothing, so like school it has no
-- Init to call. CompanionService has no order of its own -- it is a mechanic, and
-- PeopleService is the only thing that calls into it -- but it wires its PlayerRemoving
-- hook with an Init like the others, and its Start is a no-op kept for symmetry.
-- DebugService is last of all because it drives the others, and no-ops outside
-- Studio.

local services = script.services

local DataService = require(services.DataService)
local StatService = require(services.StatService)
local MoneyService = require(services.MoneyService)
local PocketMoneyService = require(services.PocketMoneyService)
local EventService = require(services.EventService)
local EnactService = require(services.EnactService)
local PropService = require(services.PropService)
local SceneService = require(services.SceneService)
local BodyService = require(services.BodyService)
local LifeService = require(services.LifeService)
local WorldEventService = require(services.WorldEventService)
local PlaceService = require(services.PlaceService)
local NPCService = require(services.NPCService)
local CompanionService = require(services.CompanionService)
local DeliveryService = require(services.DeliveryService)
local WorkService = require(services.WorkService)
local SchoolService = require(services.SchoolService)
local ScienceService = require(services.ScienceService)
local GeographyService = require(services.GeographyService)
local GymService = require(services.GymService)
local PeopleService = require(services.PeopleService)
local ChildhoodService = require(services.ChildhoodService)
local SetupService = require(services.SetupService)
local ReturnService = require(services.ReturnService)
local DebugService = require(services.DebugService)

DataService:Init()
StatService:Init()
MoneyService:Init()
PocketMoneyService:Init()
EventService:Init()
EnactService:Init()
PropService:Init()
SceneService:Init()
BodyService:Init()
-- Before LifeService, which hands it the function that starts a life. Only the Init
-- order is cosmetic here -- every Init runs before every Start -- but reading it in the
-- other order invites somebody to "fix" the Start order below, which is not cosmetic.
SetupService:Init()
LifeService:Init()
WorldEventService:Init()
PlaceService:Init()
NPCService:Init()
CompanionService:Init()
DeliveryService:Init()
WorkService:Init()
ReturnService:Init()
DebugService:Init()

DataService:Start()
StatService:Start()
MoneyService:Start()
PocketMoneyService:Start()
EventService:Start()
EnactService:Start()
PropService:Start()
SceneService:Start()
BodyService:Start()
LifeService:Start()
WorldEventService:Start()
PlaceService:Start()
NPCService:Start()
CompanionService:Start()
DeliveryService:Start()
WorkService:Start()
-- Before SchoolService, which hands a Science or a Geography lesson straight to whichever
-- of these owns the verb. Cosmetic like every other line in this list -- all three are
-- running before the first player finishes loading -- but reading it in this order is the
-- truth about which owns which.
ScienceService:Start()
GeographyService:Start()
SchoolService:Start()
GymService:Start()
PeopleService:Start()
ChildhoodService:Start()
-- Last of the real services, and it has to be. It checks arriving players for a life worth
-- running and sends the ones without one back to the lobby -- but the check has to be made
-- against a fully booted server, because "no life here" is a claim about state every service
-- above has had its chance to load. SetupService has no Start any more: it used to raise the
-- character menu from here, and the menu is in the other place now.
ReturnService:Start()
DebugService:Start()

print("[AGES] Server started")
