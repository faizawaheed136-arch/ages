--!strict
-- Single source of truth for remotes. Both server and client require this
-- module; it lazily creates (server) or waits for (client) the RemoteEvent
-- instances so there is never a second place that spells out remote names.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- RequestAgeUp is the only client -> server remote; everything else is a
-- one-way state push. It carries no payload precisely so there is nothing for
-- a hostile client to forge — the server decides whether the request is legal.
export type RemoteName =
	"StatsUpdated" | "AgeUpdated" | "AgeUpProgress" | "LifeStageChanged" | "PlayerDied" | "PlayerRespawned" | "RequestAgeUp"

local REMOTE_NAMES: { RemoteName } = {
	"StatsUpdated",
	"AgeUpdated",
	"AgeUpProgress",
	"LifeStageChanged",
	"PlayerDied",
	"PlayerRespawned",
	"RequestAgeUp",
}

local FOLDER_NAME = "RemoteEvents"

local Remotes = {}

local function getFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		return existing :: Folder
	end

	if RunService:IsServer() then
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		for _, name in REMOTE_NAMES do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		folder.Parent = ReplicatedStorage
		return folder
	end

	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Remotes.Get(name: RemoteName): RemoteEvent
	local folder = getFolder()
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
