--!strict
--[[
	Lays the sandbox site and Meridian Motors when the sandbox place is played, if they are not
	already baked into it. Sandbox only: in AGES the dealership is baked into the place, at its plot.
]]

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local DealershipBuild = require(ServerStorage:WaitForChild("DealershipBuild"))
local SandboxSite = require(ServerStorage:WaitForChild("SandboxSite"))

-- The sandbox builds at the world origin, so a position in the builder is a position in the world.
local CORNER = CFrame.new()

if Workspace:FindFirstChild(SandboxSite.ModelName) == nil then
	SandboxSite.Build(CORNER, Workspace)
end
if Workspace:FindFirstChild(DealershipBuild.ModelName) == nil then
	DealershipBuild.Build(CORNER, Workspace)
end
