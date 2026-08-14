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
local ArtService = require(services.ArtService)
local BountyService = require(services.BountyService)
local PoliceService = require(services.PoliceService)
local TheftService = require(services.TheftService)
local BankService = require(services.BankService)
local GangService = require(services.GangService)
local WitnessService = require(services.WitnessService)
local DisguiseService = require(services.DisguiseService)
local GymService = require(services.GymService)
local FightService = require(services.FightService)
local PeopleService = require(services.PeopleService)
local ChildhoodService = require(services.ChildhoodService)
local SetupService = require(services.SetupService)
local ReturnService = require(services.ReturnService)
local DebugService = require(services.DebugService)
local HouseService = require(services.HouseService)
local CarDealerService = require(services.CarDealerService)
local BillService = require(services.BillService)
local MilestoneService = require(services.MilestoneService)
local GossipService = require(services.GossipService)

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
TheftService:Init()
BankService:Init()
GangService:Init()
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
-- ReturnService must start before BodyService: its onPlayerAdded hook calls
-- SetupService.Skip to create a fresh child life, and that has to happen
-- before BodyService's watch applies the (then-adult) size to the character.
ReturnService:Start()
BodyService:Start()
LifeService:Start()
WorldEventService:Start()
PlaceService:Start()
NPCService:Start()
CompanionService:Start()
DeliveryService:Start()
WorkService:Start()
HouseService:Init()
CarDealerService:Init()
BillService:Init()
MilestoneService:Init()
GossipService:Init()
HouseService:Start()
CarDealerService:Start()
BillService:Start()
MilestoneService:Start()
GossipService:Start()
-- Before SchoolService, which hands a Science, a Geography or an Art lesson straight to
-- whichever of these owns the verb. Cosmetic like every other line in this list -- all four
-- are running before the first player finishes loading -- but reading it in this order is
-- the truth about which owns which.
ScienceService:Start()
GeographyService:Start()
ArtService:Start()
SchoolService:Start()
-- Heat before the officers, because the officers are a function of it: PoliceService's
-- first tick asks BountyService how many bodies the street should have, and a police force
-- that started answering before there was a number to answer from would spend its opening
-- pass reading zero. Cosmetic in practice -- both are running long before anybody commits
-- a crime -- but the dependency runs this way and only this way, and the list should say so.
BountyService:Start()
PoliceService:Start()
-- After both, and it has to be: standing up a till reads the place index, and the first
-- thing a robbery does is hand heat to BountyService and a sighting with it. It also has
-- an Init, unlike the two above -- the drawer is held with a button and the button is a
-- remote, so there is a handler to register before anybody can be standing at a counter.
TheftService:Start()
-- The bank, next to the till because they are the same half of the same system read from
-- opposite ends, and after it for the same two reasons: standing up a vault reads the place
-- index, and the first thing a trip does is hand heat to BountyService. It also spawns a
-- guard, which is an NPCService rig -- and NPCService is already up, several lines above.
BankService:Start()
-- The gang, after every system that pays it. Standing a boss up reads the place index and
-- spawns an NPCService rig, so both of those have to be up -- but the ordering that actually
-- matters is against BountyService: a gang tick reads the player's live bounty to decide
-- whether an escape happened, and a tick that ran before the manhunt existed would read a
-- zero and quietly award nothing for the best thing the player did all life.
GangService:Start()
-- The escape, after the heat it undoes. Standing up a mark reads the place index, and the
-- first thing a completed change does is delete a belief BountyService owns.
DisguiseService:Start()
GymService:Start()
-- The fight, after NPCService because squaring somebody up spawns a rig, and after
-- StatService because the pool a player has to spend is read off their health the moment a
-- bout opens. Both are up well above this. Nothing else in the game reads a fight, so it
-- goes late and nothing waits on it.
FightService:Start()
PeopleService:Start()
-- Dead last of the crime services, and after PeopleService rather than before it. The crowd
-- is the only part of this that reads bodies somebody else put in the street: a witness pass
-- that ran before there was anybody standing in the town would spend its first ticks
-- reporting an empty street, and the whole system would look broken for exactly as long as
-- it took the first person to spawn.
WitnessService:Start()
ChildhoodService:Start()
-- ReturnService already started above, before BodyService, so the child life is in place
-- before the body is sized. DebugService still runs last because it drives the other
-- services and no-ops outside Studio.
DebugService:Start()

print("[AGES] Server started")
