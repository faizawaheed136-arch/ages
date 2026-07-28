--!strict
-- Client bootstrap. The client only ever displays state pushed by the
-- server over Remotes — it never computes stats, age, or death itself.
-- Pressing Age Up sends a bare request; the server decides the outcome.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local StatsUI = require(script.ui.StatsUI)
local EventUI = require(script.ui.EventUI)

type Stats = Types.Stats
type AgeUpCause = Types.AgeUpCause
type ManualAgeUpState = Types.ManualAgeUpState
type OfferedEvent = Types.OfferedEvent

-- SetCoreGuiEnabled throws while the core scripts are still loading, so this
-- retries for a few frames instead of giving up on the first attempt.
local CORE_GUI_RETRY_ATTEMPTS = 10

-- The HUD occupies the top-right corner, which is where the player list would
-- otherwise render on top of it.
local function hidePlayerList()
	for _ = 1, CORE_GUI_RETRY_ATTEMPTS do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		if ok then
			return
		end
		task.wait()
	end
	warn("AGES: could not hide the player list; it may overlap the HUD")
end

-- Spawned rather than awaited: retrying here on the main thread would delay the
-- remote connections below past the server's initial state push.
task.spawn(hidePlayerList)

local ui = StatsUI.new()
local events = EventUI.new()

local RequestAgeUpRemote = Remotes.Get("RequestAgeUp")
local RequestEventChoiceRemote = Remotes.Get("RequestEventChoice")

ui:OnAgeUpActivated(function()
	RequestAgeUpRemote:FireServer()
end)

events:OnChoice(function(eventId: string, choiceId: string)
	RequestEventChoiceRemote:FireServer(eventId, choiceId)
end)

Remotes.Get("EventOffered").OnClientEvent:Connect(function(offered: OfferedEvent)
	events:Show(offered)
end)

Remotes.Get("EventResolved").OnClientEvent:Connect(function(eventId: string, outcome: string)
	events:ShowOutcome(eventId, outcome)
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
	-- A life ending outranks whatever was being decided.
	events:Hide()
	ui:ShowDeath(ageYears)
end)

Remotes.Get("PlayerRespawned").OnClientEvent:Connect(function()
	ui:HideDeath()
end)
