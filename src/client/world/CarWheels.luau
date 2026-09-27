--!strict
--[[
	Turns every car's wheels on this client and gives every car its effects: each wheel stood where
	its spring's ray meets the road, the front pair turned by the steering, all four spun by how far
	the car rolled; nitro flames from the exhausts; smoke off the rear tyres and black lines on the
	road while it drifts. Local and every frame, so it is smooth whoever owns the car and nothing
	about it crosses the network.

	HOW IT KNOWS. The driver's own machine sets Boosting and Drifting on their car (client/world/
	CarDriver) -- locally, so their flames and smoke start the frame they press the key. Everyone
	else reads the car's motion, which replicates anyway: sliding sideways faster than MIN_SLIP is a
	drift, and going faster than the car's rated top speed can only be nitro.

	world/VehicleChassis leaves on each wheel's roots (the tyre, which spins, and the brake disc,
	which only steers) where the wheel rests and how the root sits on it; this reads those and moves
	the Weld each root hangs from. Cars further than ANIMATE_STUDS from the camera are left as they
	are: a wheel nobody can see turning is not worth a raycast.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarPhysics = require(ReplicatedStorage:WaitForChild("CarPhysics"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local VEHICLES = Config.Vehicles

local ANIMATE_STUDS = 220
-- How fast the front wheels follow the steering, per second: the look of a wheel being turned.
local STEER_RATE = 8
-- Studs a second of sideways slide that reads as a drift, for a car somebody else is driving.
local MIN_SLIP = 9
-- Roblox's own particle textures, shipped with the engine: nothing uploaded.
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

type Wheel = {
	weld: Weld,
	rest: Vector3,
	side: number,
	front: boolean,
	spins: boolean,
	offset: CFrame,
}

type Car = {
	model: Model,
	hull: BasePart,
	seat: VehicleSeat?,
	wheels: { Wheel },
	params: RaycastParams,
	mountY: number,
	steerDegrees: number,
	topSpeed: number,
	spin: number,
	steer: number,
	flames: { ParticleEmitter },
	smoke: { ParticleEmitter },
	skids: { Trail },
	boosting: boolean,
	drifting: boolean,
}

local CarWheels = {}

local function number(model: Model, name: string, fallback: number): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

-- Flames at each exhaust tip, pointing back out of the pipe.
local function flamesFor(model: Model): { ParticleEmitter }
	local flames: { ParticleEmitter } = {}
	for _, part in model:GetChildren() do
		if part.Name == "Exhaust" and part:IsA("BasePart") then
			-- The tip is the pipe's -X end, which CarBody turns to face the back of the car.
			local tip = Instance.new("Attachment")
			tip.Name = "ExhaustTip"
			tip.Position = Vector3.new(-part.Size.X / 2, 0, 0)
			tip.Parent = part
			local fire = Instance.new("ParticleEmitter")
			fire.Name = "Nitro"
			fire.Texture = FIRE_TEXTURE
			fire.EmissionDirection = Enum.NormalId.Left
			fire.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 250, 255)),
				ColorSequenceKeypoint.new(0.35, Color3.fromRGB(60, 170, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 60, 255)),
			})
			fire.LightEmission = 1
			fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.1) })
			fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
			fire.Lifetime = NumberRange.new(0.08, 0.16)
			fire.Speed = NumberRange.new(16, 24)
			fire.SpreadAngle = Vector2.new(8, 8)
			fire.Rate = 140
			fire.LockedToPart = true
			fire.Enabled = false
			fire.Parent = tip
			table.insert(flames, fire)
		end
	end
	return flames
end

-- Smoke and skid lines at each rear tyre's contact patch.
local function tyresFor(hull: BasePart, wheels: { Wheel }): ({ ParticleEmitter }, { Trail })
	local smoke: { ParticleEmitter } = {}
	local skids: { Trail } = {}
	for _, wheel in wheels do
		if wheel.front or not wheel.spins then
			continue
		end
		local ground = Vector3.new(wheel.rest.X, wheel.rest.Y - VEHICLES.WheelRadius + 0.15, wheel.rest.Z)
		local patch = Instance.new("Attachment")
		patch.Name = "TyrePatch"
		patch.Position = ground
		patch.Parent = hull
		local puff = Instance.new("ParticleEmitter")
		puff.Name = "TyreSmoke"
		puff.Texture = SMOKE_TEXTURE
		puff.Color = ColorSequence.new(Color3.fromRGB(230, 232, 236))
		puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 6) })
		puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
		puff.Lifetime = NumberRange.new(1, 1.8)
		puff.Speed = NumberRange.new(2, 5)
		puff.SpreadAngle = Vector2.new(50, 50)
		puff.Acceleration = Vector3.new(0, 3, 0)
		puff.Drag = 2
		puff.Rate = 45
		puff.Enabled = false
		puff.Parent = patch
		table.insert(smoke, puff)
		-- Two points across the tread, a tyre's width apart: the trail between them is the mark.
		local a = Instance.new("Attachment")
		a.Name = "SkidA"
		a.Position = ground + Vector3.new(-0.45, -0.1, 0)
		a.Parent = hull
		local b = Instance.new("Attachment")
		b.Name = "SkidB"
		b.Position = ground + Vector3.new(0.45, -0.1, 0)
		b.Parent = hull
		local trail = Instance.new("Trail")
		trail.Name = "Skid"
		trail.Attachment0 = a
		trail.Attachment1 = b
		trail.Color = ColorSequence.new(Color3.fromRGB(16, 16, 18))
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
		trail.Lifetime = 3
		trail.MinLength = 0.1
		trail.LightInfluence = 1
		trail.FaceCamera = false
		trail.Enabled = false
		trail.Parent = hull
		table.insert(skids, trail)
	end
	return smoke, skids
end

local function read(model: Model): Car?
	local hull = model.PrimaryPart
	if hull == nil then
		return nil
	end
	local wheels: { Wheel } = {}
	for _, part in model:GetChildren() do
		local rest = part:GetAttribute("WheelRest")
		local weld = part:FindFirstChild("WheelWeld")
		local offset = part:GetAttribute("WheelOffset")
		if typeof(rest) == "Vector3" and typeof(offset) == "CFrame" and weld and weld:IsA("Weld") then
			local side = part:GetAttribute("WheelSide")
			table.insert(wheels, {
				weld = weld,
				rest = rest,
				side = if typeof(side) == "number" then side else 1,
				front = part:GetAttribute("WheelFront") == true,
				spins = part:GetAttribute("WheelSpins") == true,
				offset = offset,
			})
		end
	end
	if #wheels == 0 then
		return nil
	end
	local seat = model:FindFirstChild("DriverSeat")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	params.IgnoreWater = true
	local smoke, skids = tyresFor(hull, wheels)
	return {
		model = model,
		hull = hull,
		seat = if seat and seat:IsA("VehicleSeat") then seat else nil,
		wheels = wheels,
		params = params,
		mountY = number(model, "MountY", 0),
		steerDegrees = number(model, "SteerDegrees", 30),
		topSpeed = number(model, "TopSpeed", 80),
		spin = 0,
		steer = 0,
		flames = flamesFor(model),
		smoke = smoke,
		skids = skids,
		boosting = false,
		drifting = false,
	}
end

local function animate(car: Car, dt: number)
	local hull = car.hull
	local frame = hull.CFrame
	local up = frame.UpVector
	local velocity = hull.AssemblyLinearVelocity
	local speed = velocity:Dot(frame.LookVector)
	local radius = VEHICLES.WheelRadius
	local reach = VEHICLES.SuspensionLength + radius
	car.spin = (car.spin - speed * dt / radius) % (math.pi * 2)
	local wanted = 0
	local seat = car.seat
	if seat and seat.Occupant then
		wanted = math.rad(seat.Steer * car.steerDegrees) * CarPhysics.SteerScale(speed)
	end
	car.steer += (wanted - car.steer) * math.clamp(STEER_RATE * dt, 0, 1)
	local grounded = false
	for _, wheel in car.wheels do
		local mount = frame * Vector3.new(wheel.rest.X, car.mountY, wheel.rest.Z)
		local hit = Workspace:Raycast(mount, -up * reach, car.params)
		if hit then
			grounded = true
		end
		local distance = if hit then (hit.Position - mount).Magnitude else reach
		local y = car.mountY - (distance - radius)
		-- Steering right turns the wheel's nose toward +X: a negative turn about Y.
		local yaw = if wheel.front then -car.steer else 0
		local turn = if wheel.side < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new()
		local roll = if wheel.spins then CFrame.Angles(car.spin * wheel.side, 0, 0) else CFrame.new()
		wheel.weld.C0 = CFrame.new(wheel.rest.X, y, wheel.rest.Z) * CFrame.Angles(0, yaw, 0) * turn * roll * wheel.offset
	end

	-- The effects: this machine's driver says; anyone else's car shows it in how it moves.
	local model = car.model
	local localBoost = model:GetAttribute("Boosting")
	local localDrift = model:GetAttribute("Drifting")
	local boosting = if typeof(localBoost) == "boolean" then localBoost else speed > car.topSpeed * 1.03
	local slip = math.abs(velocity:Dot(frame.RightVector))
	local drifting = grounded and (if typeof(localDrift) == "boolean" then localDrift else slip > MIN_SLIP and math.abs(speed) > 12)
	if boosting ~= car.boosting then
		car.boosting = boosting
		for _, fire in car.flames do
			fire.Enabled = boosting
		end
	end
	if drifting ~= car.drifting then
		car.drifting = drifting
		for _, puff in car.smoke do
			puff.Enabled = drifting
		end
		for _, trail in car.skids do
			trail.Enabled = drifting
		end
	end
end

function CarWheels.Start()
	local cars: { [Model]: Car } = {}
	local function add(model: Instance)
		if model:IsA("Model") then
			-- Built on the server with its wheels already welded; read once it has arrived whole.
			task.defer(function()
				local car = read(model)
				if car then
					cars[model] = car
				end
			end)
		end
	end
	for _, model in CollectionService:GetTagged(CarPhysics.Tag) do
		add(model)
	end
	CollectionService:GetInstanceAddedSignal(CarPhysics.Tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(CarPhysics.Tag):Connect(function(model: Instance)
		if model:IsA("Model") then
			cars[model] = nil
		end
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local eye = camera.CFrame.Position
		for model, car in cars do
			if model.Parent == nil or car.hull.Parent == nil then
				cars[model] = nil
			elseif (car.hull.Position - eye).Magnitude <= ANIMATE_STUDS then
				animate(car, dt)
			end
		end
	end)
end

return CarWheels
