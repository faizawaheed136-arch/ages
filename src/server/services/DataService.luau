--!strict
-- Profile load/save + session locking. Every other service reads and writes
-- game state through DataService.GetProfile(player).Data — never directly
-- through DataStoreService.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local ProfileStoreModule = require(ServerStorage:WaitForChild("ProfileStore"))

type ProfileData = Types.ProfileData

-- A minimal structural view of ProfileStore's generic Profile<T> — only the
-- members this codebase actually touches. Avoids depending on the vendor
-- library's exact generic export shape everywhere Profile is referenced.
type Profile = {
	Data: ProfileData,
	UserIds: { number },
	OnSessionEnd: { Connect: (self: any, listener: () -> ()) -> { Disconnect: (self: any) -> () } },
	IsActive: (self: any) -> boolean,
	Reconcile: (self: any) -> (),
	EndSession: (self: any) -> (),
	AddUserId: (self: any, userId: number) -> (),
}

local PROFILE_TEMPLATE: ProfileData = {
	ageMonths = 0,
	stage = "Childhood",
	alive = true,
	stats = {
		health = Config.Stats.Starting.health,
		happiness = Config.Stats.Starting.happiness,
		smarts = Config.Stats.Starting.smarts,
		looks = Config.Stats.Starting.looks,
	},
	livesLived = 0,
	secondsSinceAgeUp = 0,
}

local playerStore = ProfileStoreModule.New("PlayerData", PROFILE_TEMPLATE)

local profiles: { [Player]: Profile } = {}

local DataService = {}

local function onPlayerAdded(player: Player)
	local profile = playerStore:StartSessionAsync(`Player_{player.UserId}`, {})

	if profile == nil then
		player:Kick("Could not load your data (session lock timeout). Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Your data session ended (opened on another server). Please rejoin.")
	end)

	if player.Parent ~= Players then
		-- Player left the game while the session was still starting.
		profile:EndSession()
		return
	end

	profiles[player] = profile
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile ~= nil then
		profile:EndSession()
	end
end

function DataService.GetProfile(player: Player): Profile?
	return profiles[player]
end

-- Yields until the profile finishes loading, or returns nil if the player
-- leaves first. Callers must handle the nil case.
function DataService.WaitForProfile(player: Player): Profile?
	local attempts = 0
	while profiles[player] == nil and player.Parent == Players and attempts < 100 do
		task.wait(0.1)
		attempts += 1
	end
	return profiles[player]
end

function DataService:Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

function DataService:Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService
