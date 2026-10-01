--!strict
--[[
	Drives the car the local player is sitting at the wheel of, on this machine.

	The server hands a seated driver network ownership of their car (world/VehicleChassis), so the
	car's physics resolves here, with no lag between a key and the road. The physics step
	(shared/CarPhysics) has to run where the physics does, or the forces it writes arrive late and
	buck the car -- so from the moment the local character sits in a car's DriverSeat until it gets
	up, this steps that car every frame, and lists it in CarPhysics.Live for the wheels and the
	sound to read the telemetry of.

	THE CONTROLS are a driving game's:
	  * W / S (or the arrows) -- throttle; brake, and reverse once stopped. The seat's own WASD.
	  * A / D -- steer;
	  * Shift -- nitro, while there is any left (NITRO_SECONDS of it, refilling when not in use);
	  * Space -- the handbrake: the rear lets go and the car drifts. Space would otherwise stand the
	    driver up, so it is taken for as long as they drive;
	  * E / Q -- the next gear up and down, which puts the gearbox in manual; G gives it back to the
	    automatic;
	  * L -- headlights; Z, C and X -- left, right and hazard signals; H -- the horn, while held;
	  * V -- the camera: chase, bonnet, cockpit, and the free camera of the rest of the game;
	  * F -- get out.
	On a phone the same are buttons on the HUD (client/ui/DriveHUD). The camera widens with speed and
	further on nitro; a drift scores for as long as the car stays sideways.

	What the lights, signals and horn are is told to the server, which owns them for everybody to see
	(world/VehicleChassis). Whether the driver is on nitro is set as an attribute on their car --
	Boosting -- locally, for client/world/CarWheels' flames to show without waiting on anything.
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
local DRIFT_IN, DRIFT_OUT = 8, 3
-- The camera: how much wider it opens at top speed, and again on nitro; how quickly it follows.
local FOV_SPEED, FOV_BOOST, FOV_RATE = 14, 10, 5
-- A drift scores this many points per stud of sideways slide; below MIN_SLIP studs a second
-- sideways the car is not drifting, just turning.
local DRIFT_POINTS = 1.6
local MIN_SLIP = 8

local RENDER_STEP = "AgesCarCamera"
local CAMERAS = { "Chase", "Bonnet", "Cockpit", "Free" }

local ACTIONS = {
	"AgesCarBoost",
	"AgesCarHandbrake",
	"AgesCarExit",
	"AgesCarLights",
	"AgesCarSignal",
	"AgesCarHorn",
	"AgesCarCamera",
	"AgesCarGear",
	"AgesCarManual",
}

local SIGNALS = { [Enum.KeyCode.Z] = "left", [Enum.KeyCode.C] = "right", [Enum.KeyCode.X] = "hazard" }

function CarDriver.Start(hudModule: any)
	local player = Players.LocalPlayer
	local hud = hudModule.new()
	local stepping: RBXScriptConnection? = nil
	local boostHeld, driftHeld = false, false
	local exitWanted = false
	local shiftWanted = 0
	local manual = false
	local lights = false
	local signal = ""
	local camMode = 1
	local control: RemoteEvent? = nil

	local function tell(action: string, value: any)
		if control == nil then
			local found = ReplicatedStorage:FindFirstChild("CarControl")
			control = if found and found:IsA("RemoteEvent") then found else nil
		end
		if control then
			control:FireServer(action, value)
		end
	end

	local function setLights(on: boolean)
		lights = on
		tell("lights", on)
	end

	local function setSignal(name: string)
		-- The same key again puts it out.
		signal = if signal == name then "" else name
		tell("signal", signal)
	end

	local function cycleCamera()
		camMode = camMode % #CAMERAS + 1
	end

	hud:OnButtons(function(down: boolean)
		boostHeld = down
	end, function(down: boolean)
		driftHeld = down
	end, function()
		exitWanted = true
	end)
	hud:OnAction(function(name: string, down: boolean)
		if name == "camera" and down then
			cycleCamera()
		elseif name == "lights" and down then
			setLights(not lights)
		elseif name == "horn" then
			tell("horn", down)
		elseif name == "signal" and down then
			setSignal("hazard")
		end
	end)

	local function unbind()
		for _, name in ACTIONS do
			ContextActionService:UnbindAction(name)
		end
		tell("horn", false)
	end

	local function bind()
		local priority = Enum.ContextActionPriority.High.Value + 50
		local function on(name: string, handler: (Enum.UserInputState, InputObject) -> (), ...: Enum.KeyCode)
			ContextActionService:BindActionAtPriority(name, function(_, state: Enum.UserInputState, input: InputObject)
				handler(state, input)
				return Enum.ContextActionResult.Sink
			end, false, priority, ...)
		end
		on("AgesCarBoost", function(state)
			boostHeld = state == Enum.UserInputState.Begin
		end, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonR1)
		on("AgesCarHandbrake", function(state)
			driftHeld = state == Enum.UserInputState.Begin
		end, Enum.KeyCode.Space, Enum.KeyCode.ButtonB)
		on("AgesCarExit", function(state)
			if state == Enum.UserInputState.Begin then
				exitWanted = true
			end
		end, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
		on("AgesCarLights", function(state)
			if state == Enum.UserInputState.Begin then
				setLights(not lights)
			end
		end, Enum.KeyCode.L, Enum.KeyCode.DPadUp)
		on("AgesCarSignal", function(state, input)
			local name = SIGNALS[input.KeyCode]
			if state == Enum.UserInputState.Begin and name then
				setSignal(name)
			end
		end, Enum.KeyCode.Z, Enum.KeyCode.C, Enum.KeyCode.X)
		on("AgesCarHorn", function(state)
			tell("horn", state == Enum.UserInputState.Begin)
		end, Enum.KeyCode.H, Enum.KeyCode.ButtonL3)
		on("AgesCarCamera", function(state)
			if state == Enum.UserInputState.Begin then
				cycleCamera()
			end
		end, Enum.KeyCode.V, Enum.KeyCode.ButtonR3)
		on("AgesCarGear", function(state, input)
			if state == Enum.UserInputState.Begin then
				manual = true
				shiftWanted = if input.KeyCode == Enum.KeyCode.E then 1 else -1
			end
		end, Enum.KeyCode.E, Enum.KeyCode.Q)
		on("AgesCarManual", function(state)
			if state == Enum.UserInputState.Begin then
				manual = not manual
			end
		end, Enum.KeyCode.G)
	end

	local baseFov: number? = nil
	local driving: Model? = nil
	local character: Model? = nil

	-- Every part of the character drawn or not, for a camera that sits where their head is.
	local function showCharacter(visible: boolean)
		if character == nil then
			return
		end
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = if visible then 0 else 1
			end
		end
	end

	local function stop()
		if stepping then
			stepping:Disconnect()
			stepping = nil
		end
		pcall(function()
			RunService:UnbindFromRenderStep(RENDER_STEP)
		end)
		if driving then
			CarPhysics.Live[driving] = nil
			driving:SetAttribute("Boosting", nil)
			driving = nil
		end
		unbind()
		showCharacter(true)
		hud:Show(false)
		boostHeld, driftHeld, exitWanted = false, false, false
		shiftWanted, manual, lights, signal = 0, false, false, ""
		local camera = Workspace.CurrentCamera
		if camera then
			if camera.CameraType == Enum.CameraType.Scriptable then
				camera.CameraType = Enum.CameraType.Custom
			end
			if baseFov then
				camera.FieldOfView = baseFov
			end
		end
		baseFov = nil
	end

	local function watch(char: Model)
		local humanoid = char:WaitForChild("Humanoid") :: Humanoid
		local function seated()
			stop()
			local seat = humanoid.SeatPart
			if seat == nil or not seat:IsA("VehicleSeat") or seat.Name ~= "DriverSeat" then
				return
			end
			local model = seat.Parent
			if model == nil or not model:IsA("Model") or not CollectionService:HasTag(model, CarPhysics.Tag) then
				return
			end
			local rig = CarPhysics.Rig(model, char)
			if rig == nil then
				return
			end
			local driverSeat = seat :: VehicleSeat
			local car = model :: Model
			local topSpeed = (car:GetAttribute("TopSpeed") :: number?) or 100
			local sizeZ = (car:GetAttribute("SizeZ") :: number?) or 16
			local sizeY = (car:GetAttribute("SizeY") :: number?) or 5
			local scale = (car:GetAttribute("Scale") :: number?) or 1
			driving = car
			character = char
			CarPhysics.Live[car] = rig
			local fuel = 1
			local drift = 0
			local score = 0
			local camera = Workspace.CurrentCamera
			baseFov = if camera then camera.FieldOfView else 70
			-- The chase camera's own heading, which follows the car's with some delay.
			local chase = Vector3.new(rig.hull.CFrame.LookVector.X, 0, rig.hull.CFrame.LookVector.Z)
			chase = if chase.Magnitude > 0.01 then chase.Unit else Vector3.new(0, 0, -1)
			local shown = true
			bind()
			hud:Show(true)

			local function place(dt: number, share: number, boosting: boolean)
				local cam = Workspace.CurrentCamera
				if cam == nil or baseFov == nil then
					return
				end
				local mode = CAMERAS[camMode]
				local want = (baseFov :: number) + FOV_SPEED * math.clamp(share, 0, 1) + (if boosting then FOV_BOOST else 0)
				local hull = rig.hull
				local cf = hull.CFrame
				if mode == "Free" then
					if cam.CameraType == Enum.CameraType.Scriptable then
						cam.CameraType = Enum.CameraType.Custom
					end
					if not shown then
						shown = true
						showCharacter(true)
					end
					cam.FieldOfView += (want - cam.FieldOfView) * math.clamp(FOV_RATE * dt, 0, 1)
					return
				end
				cam.CameraType = Enum.CameraType.Scriptable
				local inside = mode ~= "Chase"
				if inside == shown then
					shown = not inside
					showCharacter(shown)
				end
				if mode == "Chase" then
					-- Behind the car, on where it is heading as much as where it points, so a slide is seen
					-- from behind the slide.
					local vel = hull.AssemblyLinearVelocity
					local flat = Vector3.new(vel.X, 0, vel.Z)
					local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
					local target = if look.Magnitude > 0.01 then look.Unit else chase
					if flat.Magnitude > 10 * scale and vel:Dot(cf.LookVector) > 0 then
						target = (target * 0.65 + flat.Unit * 0.35).Unit
					end
					chase = (chase:Lerp(target, 1 - math.exp(-5 * dt))).Unit
					local pos = cf.Position - chase * (sizeZ * 1.0 + 7 + 4 * share) + Vector3.new(0, sizeY * 0.7 + 3, 0)
					local aim = cf.Position + Vector3.new(0, sizeY * 0.35, 0) + chase * (sizeZ * 0.35)
					cam.CFrame = CFrame.lookAt(pos, aim)
				else
					local offset = car:GetAttribute(if mode == "Bonnet" then "CamHood" else "CamCockpit")
					local at = cf:PointToWorldSpace(if typeof(offset) == "Vector3" then offset else Vector3.new(0, sizeY * 0.6, 0))
					cam.CFrame = CFrame.new(at) * cf.Rotation
				end
				cam.FieldOfView += (want - cam.FieldOfView) * math.clamp(FOV_RATE * dt, 0, 1)
			end

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
				local shift = shiftWanted
				shiftWanted = 0
				local tele = CarPhysics.Step(rig, dt, {
					-- The floats, so a thumbstick or a phone's slider is not rounded to a key.
					throttle = driverSeat.ThrottleFloat,
					steer = driverSeat.SteerFloat,
					handbrake = drift,
					boost = boosting,
					manual = manual,
					shift = shift,
				})

				local hull = rig.hull
				local velocity = hull.AssemblyLinearVelocity
				local speed = velocity:Dot(hull.CFrame.LookVector)
				local slip = math.abs(velocity:Dot(hull.CFrame.RightVector))
				local drifting = slip > MIN_SLIP * scale and math.abs(speed) > 12 * scale
				if drifting then
					score += slip / scale * dt * DRIFT_POINTS * (1 + drift)
				else
					score = 0
				end
				car:SetAttribute("Boosting", boosting)

				hud:Set(tele, fuel, boosting, if drifting then score else nil)
				hud:SetState({ lights = lights, signal = signal, camera = CAMERAS[camMode], manual = manual })
			end)
			-- After the step: the camera sits where the car has just been put.
			RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
				if rig.hull.Parent == nil then
					return
				end
				local speed = rig.hull.AssemblyLinearVelocity:Dot(rig.hull.CFrame.LookVector)
				place(dt, math.abs(speed) / topSpeed, car:GetAttribute("Boosting") == true)
			end)
		end
		humanoid:GetPropertyChangedSignal("SeatPart"):Connect(seated)
		-- Already in a car when this starts: the script ran late, or a respawn put them straight back.
		if humanoid.SeatPart ~= nil then
			seated()
		end
	end

	player.CharacterAdded:Connect(function(char: Model)
		stop()
		watch(char)
	end)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

return CarDriver
