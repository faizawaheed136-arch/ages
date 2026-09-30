--!strict
--[[
	Drives the car the local player is sitting at the wheel of, on this machine.

	The server hands a seated driver network ownership of their car (world/VehicleChassis), so the
	car's physics resolves here, with no lag between a key and the road. The physics step
	(shared/CarPhysics) has to run where the physics does, or the forces it writes arrive late and
	buck the car -- so from the moment the local character sits in a car's DriverSeat until it gets
	up, this steps that car every frame, and lists it in CarPhysics.Live for the wheels and the
	sound to read the telemetry of.

	THE CONTROLS, beyond the seat's own WASD:
	  * Shift -- nitro, while there is any left (NITRO_SECONDS of it, refilling when not in use);
	  * Space -- the handbrake: the rear lets go and the car drifts. Space would otherwise stand the
	    driver up, so it is taken for as long as they drive;
	  * F -- get out.
	On a phone the same three are buttons on the HUD (client/ui/DriveHUD). The camera widens with
	speed and further on nitro; a drift scores for as long as the car stays sideways.

	Whether the driver is on nitro is set as an attribute on their car -- Boosting -- locally, for
	client/world/CarWheels' flames to show without waiting on anything.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarPhysics = require(ReplicatedStorage:WaitForChild("CarPhysics"))

local CarDriver = {}

-- Seconds of nitro in a full tank, and seconds to refill it from empty.
local NITRO_SECONDS = 3.5
local REFILL_SECONDS = 9
-- How fast the handbrake takes the grip away and gives it back, per second.
local DRIFT_IN, DRIFT_OUT = 6, 2.5
-- The camera: how much wider it opens at top speed, and again on nitro; how quickly it follows.
local FOV_SPEED, FOV_BOOST, FOV_RATE = 14, 10, 5
-- A drift scores this many points per stud of sideways slide; below MIN_SLIP studs a second
-- sideways the car is not drifting, just turning.
local DRIFT_POINTS = 1.6
local MIN_SLIP = 8

local ACTIONS = { "AgesCarBoost", "AgesCarDrift", "AgesCarExit" }

function CarDriver.Start(hudModule: any)
	local player = Players.LocalPlayer
	local hud = hudModule.new()
	local stepping: RBXScriptConnection? = nil
	local boostHeld, driftHeld = false, false
	local exitWanted = false

	hud:OnButtons(function(down: boolean)
		boostHeld = down
	end, function(down: boolean)
		driftHeld = down
	end, function()
		exitWanted = true
	end)

	local function unbind()
		for _, name in ACTIONS do
			ContextActionService:UnbindAction(name)
		end
	end

	local function bind()
		local priority = Enum.ContextActionPriority.High.Value + 50
		ContextActionService:BindActionAtPriority("AgesCarBoost", function(_, state: Enum.UserInputState)
			boostHeld = state == Enum.UserInputState.Begin
			return Enum.ContextActionResult.Sink
		end, false, priority, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonR1)
		ContextActionService:BindActionAtPriority("AgesCarDrift", function(_, state: Enum.UserInputState)
			driftHeld = state == Enum.UserInputState.Begin
			return Enum.ContextActionResult.Sink
		end, false, priority, Enum.KeyCode.Space, Enum.KeyCode.ButtonL1)
		ContextActionService:BindActionAtPriority("AgesCarExit", function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				exitWanted = true
			end
			return Enum.ContextActionResult.Sink
		end, false, priority, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
	end

	local baseFov: number? = nil
	local driving: Model? = nil
	local function stop()
		if stepping then
			stepping:Disconnect()
			stepping = nil
		end
		if driving then
			CarPhysics.Live[driving] = nil
			driving:SetAttribute("Boosting", nil)
			driving = nil
		end
		unbind()
		hud:Show(false)
		boostHeld, driftHeld, exitWanted = false, false, false
		local camera = Workspace.CurrentCamera
		if camera and baseFov then
			camera.FieldOfView = baseFov
		end
		baseFov = nil
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
			local car = model :: Model
			local topSpeed = (car:GetAttribute("TopSpeed") :: number?) or 100
			driving = car
			CarPhysics.Live[car] = rig
			local fuel = 1
			local drift = 0
			local score = 0
			local camera = Workspace.CurrentCamera
			baseFov = if camera then camera.FieldOfView else 70
			bind()
			hud:Show(true)
			stepping = RunService.PreSimulation:Connect(function(dt: number)
				if humanoid.SeatPart ~= driverSeat or rig.hull.Parent == nil then
					stop()
					return
				end
				if exitWanted then
					exitWanted = false
					humanoid.Jump = true
					return
				end
				local boosting = boostHeld and fuel > 0.02
				if boosting then
					fuel = math.max(0, fuel - dt / NITRO_SECONDS)
				else
					fuel = math.min(1, fuel + dt / REFILL_SECONDS)
				end
				drift = if driftHeld then math.min(1, drift + dt * DRIFT_IN) else math.max(0, drift - dt * DRIFT_OUT)
				local tele = CarPhysics.Step(rig, dt, {
					throttle = driverSeat.Throttle,
					steer = driverSeat.Steer,
					handbrake = drift,
					boost = boosting,
				})

				local hull = rig.hull
				local velocity = hull.AssemblyLinearVelocity
				local speed = velocity:Dot(hull.CFrame.LookVector)
				local slip = math.abs(velocity:Dot(hull.CFrame.RightVector))
				local drifting = slip > MIN_SLIP and math.abs(speed) > 12
				if drifting then
					score += slip * dt * DRIFT_POINTS * (1 + drift)
				else
					score = 0
				end
				car:SetAttribute("Boosting", boosting)

				local share = math.abs(speed) / topSpeed
				if camera and baseFov then
					local want = (baseFov :: number) + FOV_SPEED * math.clamp(share, 0, 1) + (if boosting then FOV_BOOST else 0)
					camera.FieldOfView += (want - camera.FieldOfView) * math.clamp(FOV_RATE * dt, 0, 1)
				end
				hud:Set(tele, fuel, boosting, if drifting then score else nil)
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
