--!strict
-- Lobby bootstrap. Five services, and the order matters for exactly one reason: the stage
-- has to exist before a character can be stood on it, and DataService has to be listening
-- before the lobby can wait on a profile.
--
-- Deliberately not the game place's bootstrap with things removed. The game place runs
-- twenty services in a documented dependency order; the lobby runs a data layer, a set, a
-- menu and a harness. Sharing one bootstrap between them would mean every service in the
-- game place growing a "does this place want me" test, which is the same mistake as a
-- `paused` flag in thirteen tick loops -- it works until the fourteenth is written.
--
-- `shared` holds the modules that are genuinely the same file in both places, mapped in by
-- `lobby.project.json` rather than copied: DataService (one definition of how a profile
-- loads, migrates and locks), Countries (one list of countries, so a card in the lobby and a
-- name in the game cannot disagree), and LifeSetup (one definition of what a valid life is,
-- checked in the lobby where one is made and in the game place where `/setup skip` makes
-- one). LifeSetup requires Countries as a sibling, which is why the two are mapped next to
-- each other and must stay that way.

local services = script.services

local DataService = require(script.shared.DataService)
local StageService = require(services.StageService)
local LobbySetupService = require(services.LobbySetupService)
local LobbyService = require(services.LobbyService)
local SpinsService = require(services.SpinsService)
local LobbyDebugService = require(services.LobbyDebugService)

DataService:Init()
StageService:Init()
-- Before LobbySetupService, and that is the one ordering here that is not about the stage.
-- LobbyService's Init hands the setup service the callback that redraws the cards, and the
-- setup service's Init is where it starts accepting create requests. Reversed, there is a
-- window -- vanishingly small, but a real one -- in which a life could be written and the
-- menu never told.
LobbyService:Init()
LobbySetupService:Init()
-- After LobbySetupService, but nothing here actually depends on the order between the two --
-- SpinsService only reads and writes `profile.Data.perks`, and LobbySetupService only reads
-- it back at Create time, well after both are up. Placed here anyway so the file reads in the
-- order a life is actually made: get spins, spend a spin, spend the perk it bought.
SpinsService:Init()
LobbyDebugService:Init()

DataService:Start()
StageService:Start()
LobbyService:Start()
LobbySetupService:Start()
SpinsService:Start()
LobbyDebugService:Start()
