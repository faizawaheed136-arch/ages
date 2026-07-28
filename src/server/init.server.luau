--!strict
-- Server bootstrap. Requires every service and drives the Init() / Start()
-- lifecycle in dependency order: data must be loadable before stats can be
-- read, and stats must exist before aging can decay or kill them. DebugService
-- is last because it drives the others, and no-ops outside Studio.

local services = script.services

local DataService = require(services.DataService)
local StatService = require(services.StatService)
local LifeService = require(services.LifeService)
local DebugService = require(services.DebugService)

DataService:Init()
StatService:Init()
LifeService:Init()
DebugService:Init()

DataService:Start()
StatService:Start()
LifeService:Start()
DebugService:Start()

print("[AGES] Server skeleton started")
