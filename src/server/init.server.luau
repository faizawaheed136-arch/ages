--!strict
-- Server bootstrap. Requires every service and drives the Init() / Start()
-- lifecycle in dependency order: data must be loadable before stats can be
-- read, stats must exist before aging can decay or kill them, events must be
-- listening before a birthday can offer one, the body must be watching for
-- spawns before a birthday resizes it, and the world can only offer events once
-- there is an engine to ask. Visitors must be sweepable before anything can send
-- one, and deliveries come last of the real services because they register a
-- handler on the world and restore whatever players left standing in it.
-- DebugService is last of all because it drives the others, and no-ops outside
-- Studio.

local services = script.services

local DataService = require(services.DataService)
local StatService = require(services.StatService)
local EventService = require(services.EventService)
local BodyService = require(services.BodyService)
local LifeService = require(services.LifeService)
local WorldEventService = require(services.WorldEventService)
local NPCService = require(services.NPCService)
local DeliveryService = require(services.DeliveryService)
local DebugService = require(services.DebugService)

DataService:Init()
StatService:Init()
EventService:Init()
BodyService:Init()
LifeService:Init()
WorldEventService:Init()
NPCService:Init()
DeliveryService:Init()
DebugService:Init()

DataService:Start()
StatService:Start()
EventService:Start()
BodyService:Start()
LifeService:Start()
WorldEventService:Start()
NPCService:Start()
DeliveryService:Start()
DebugService:Start()

print("[AGES] Server started")
