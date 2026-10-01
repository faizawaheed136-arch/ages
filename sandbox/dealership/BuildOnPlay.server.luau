--!strict
--[[
	Lays the sandbox site and Meridian Motors when the sandbox place is played, if they are not
	already baked into it. Sandbox only: in AGES the dealership is baked into the place, at its plot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

-- The props, as in AGES: DealershipService does this there, and there is no DealershipService here.
local DealershipDressing = require(ServerStorage:WaitForChild("DealershipDressing"))
local DealershipProps = require(ServerStorage:WaitForChild("DealershipProps"))
local swapped, kept = DealershipDressing.Dress(Workspace:WaitForChild(DealershipBuild.ModelName) :: Model, DealershipProps)
print(`[dealership sandbox] {swapped} props placed, {kept} still block stand-ins`)

-- Cars drawn from a model (the GT-R) cannot be baked into the place offline, where there is no model
-- to draw them from; stand them on their slots now, as DealershipService does in AGES.
local MeshCar = require(ReplicatedStorage:WaitForChild("MeshCar"))
local Vehicles = require(ServerStorage:WaitForChild("Vehicles"))
local VehicleChassis = require(ServerStorage:WaitForChild("VehicleChassis"))
local standing: { [string]: number } = {}
for _, slot in Workspace:GetDescendants() do
	if slot.Name ~= "CarSlot" or not slot:IsA("BasePart") then
		continue
	end
	local id = slot:GetAttribute("VehicleId")
	local kind = if typeof(id) == "string" then Vehicles.Get(id) else nil
	if kind and kind.model and MeshCar.Available(kind.model) and slot.Parent then
		local car = VehicleChassis.BuildDisplay(kind, slot.CFrame * CFrame.new(0, -slot.Size.Y / 2, 0))
		-- The lot stands one kind in several bays: the first is Display_<id>, the rest numbered.
		local seen = standing[kind.id] or 0
		standing[kind.id] = seen + 1
		car.Name = if seen == 0 then `Display_{kind.id}` else `Display_{kind.id}_{seen + 1}`
		car.Parent = slot.Parent
	end
end
