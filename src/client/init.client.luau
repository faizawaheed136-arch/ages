--!strict
-- Client bootstrap. The client only ever displays state pushed by the
-- server over Remotes — it never computes stats, age, or death itself.
-- Pressing Age Up sends a bare request; the server decides the outcome.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local StatsUI = require(script.ui.StatsUI)

type Stats = Types.Stats
type AgeUpCause = Types.AgeUpCause
type ManualAgeUpState = Types.ManualAgeUpState

local ui = StatsUI.new()

local RequestAgeUpRemote = Remotes.Get("RequestAgeUp")

ui:OnAgeUpActivated(function()
	RequestAgeUpRemote:FireServer()
end)

Remotes.Get("StatsUpdated").OnClientEvent:Connect(function(stats: Stats)
	ui:SetStats(stats)
end)

Remotes.Get("AgeUpdated").OnClientEvent:Connect(function(years: number, cause: AgeUpCause)
	ui:SetAge(years)
	if cause == "Auto" then
		ui:ShowNotice("A year has passed while you were living your life...")
	end
end)

Remotes.Get("AgeUpProgress").OnClientEvent:Connect(function(seconds: number, thresholdSeconds: number, state: ManualAgeUpState)
	ui:SetAgeUpProgress(seconds, thresholdSeconds, state)
end)

Remotes.Get("LifeStageChanged").OnClientEvent:Connect(function(stage: string)
	ui:SetStage(stage)
end)

Remotes.Get("PlayerDied").OnClientEvent:Connect(function(ageYears: number)
	ui:ShowDeath(ageYears)
end)

Remotes.Get("PlayerRespawned").OnClientEvent:Connect(function()
	ui:HideDeath()
end)
