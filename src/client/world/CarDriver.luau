--!strict
--[[
	Drives the car the local player is sitting at the wheel of, on this machine.

	The server hands a seated driver network ownership of their car (world/VehicleChassis), so the
	car's physics resolves here, with no lag between a key and the road. The physics step
	(shared/CarPhysics) has to run where the physics does, or the springs it writes arrive late and
	buck the car -- so from the moment the local character sits in a car's DriverSeat until it gets
	up, this steps that car every frame from the seat's own Throttle and Steer.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CarPhysics = require(ReplicatedStorage:WaitForChild("CarPhysics"))

local CarDriver = {}

function CarDriver.Start()
	local player = Players.LocalPlayer
	local stepping: RBXScriptConnection? = nil

	local function stop()
		if stepping then
			stepping:Disconnect()
			stepping = nil
		end
	end

	local function watch(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			stop()
			local seat = humanoid.SeatPart
			if seat == nil or not seat:IsA("VehicleSeat") or seat.Name ~= "DriverSeat" then
				return
			end
			local model = seat.Parent
			if model == nil or not model:IsA("Model") or not CollectionService:HasTag(model, CarPhysics.Tag) then
				return
			end
			local rig = CarPhysics.Rig(model, character)
			if rig == nil then
				return
			end
			local driverSeat = seat :: VehicleSeat
			stepping = RunService.Stepped:Connect(function(_, dt: number)
				if humanoid.SeatPart ~= driverSeat or rig.hull.Parent == nil then
					stop()
					return
				end
				CarPhysics.Step(rig, dt, driverSeat.Throttle, driverSeat.Steer)
			end)
		end)
	end

	player.CharacterAdded:Connect(function(character: Model)
		stop()
		watch(character)
	end)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

return CarDriver
