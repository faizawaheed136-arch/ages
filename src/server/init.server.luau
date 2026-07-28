--!strict
-- Server bootstrap. Requires every service and drives the Init() / Start()
-- lifecycle in dependency order: data must be loadable before stats can be
-- read, stats must exist before aging can decay or kill them, events must be
-- listening before a birthday can offer one, and the body must be watching for
-- spawns before a birthday resizes it. DebugService is last because it drives
-- the others, and no-ops outside Studio.

local services = script.services

local DataService = require(services.DataService)
local StatService = require(services.StatService)
local EventService = require(services.EventService)
local BodyService = require(services.BodyService)
local LifeService = require(services.LifeService)
local DebugService = require(services.DebugService)

DataService:Init()
StatService:Init()
EventService:Init()
BodyService:Init()
LifeService:Init()
DebugService:Init()

DataService:Start()
StatService:Start()
EventService:Start()
BodyService:Start()
LifeService:Start()
DebugService:Start()

print("[AGES] Server started")
