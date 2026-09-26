--!strict
--[[
	Turns every car's wheels on this client: each wheel stood where its spring's ray meets the road,
	the front pair turned by the steering, all four spun by how far the car rolled. Local and every
	frame, so wheels move smoothly whoever owns the car and nothing about them crosses the network.

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
	spin: number,
	steer: number,
}

local CarWheels = {}

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
	local mountY = model:GetAttribute("MountY")
	local steerDegrees = model:GetAttribute("SteerDegrees")
	return {
		model = model,
		hull = hull,
		seat = if seat and seat:IsA("VehicleSeat") then seat else nil,
		wheels = wheels,
		params = params,
		mountY = if typeof(mountY) == "number" then mountY else 0,
		steerDegrees = if typeof(steerDegrees) == "number" then steerDegrees else 30,
		spin = 0,
		steer = 0,
	}
end

local function animate(car: Car, dt: number)
	local hull = car.hull
	local frame = hull.CFrame
	local up = frame.UpVector
	local speed = hull.AssemblyLinearVelocity:Dot(frame.LookVector)
	local radius = VEHICLES.WheelRadius
	local reach = VEHICLES.SuspensionLength + radius
	car.spin = (car.spin - speed * dt / radius) % (math.pi * 2)
	local wanted = 0
	local seat = car.seat
	if seat and seat.Occupant then
		wanted = math.rad(seat.Steer * car.steerDegrees) * CarPhysics.SteerScale(speed)
	end
	car.steer += (wanted - car.steer) * math.clamp(STEER_RATE * dt, 0, 1)
	for _, wheel in car.wheels do
		local mount = frame * Vector3.new(wheel.rest.X, car.mountY, wheel.rest.Z)
		local hit = Workspace:Raycast(mount, -up * reach, car.params)
		local distance = if hit then (hit.Position - mount).Magnitude else reach
		local y = car.mountY - (distance - radius)
		-- Steering right turns the wheel's nose toward +X: a negative turn about Y.
		local yaw = if wheel.front then -car.steer else 0
		local turn = if wheel.side < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new()
		local roll = if wheel.spins then CFrame.Angles(car.spin * wheel.side, 0, 0) else CFrame.new()
		wheel.weld.C0 = CFrame.new(wheel.rest.X, y, wheel.rest.Z) * CFrame.Angles(0, yaw, 0) * turn * roll * wheel.offset
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
