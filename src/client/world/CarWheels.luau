--!strict
--[[
	Animates every car on this client: each wheel stood where its spring's ray meets the road, the
	front pair turned by the steering and all four spun by how fast they are really turning; the
	steering wheel turned with them; and the effects -- smoke and black lines off a tyre that
	slides, flames on nitro and the crackle of a gearshift at high revs. Local and every frame, so it
	is smooth whoever owns the car and nothing about it crosses the network.

	WHAT IT KNOWS. The car this machine drives has its telemetry in CarPhysics.Live: the steering
	angle the physics is holding, how fast each wheel is turning, which are slipping. That is what is
	drawn, so a locked wheel looks locked and a wheel spinning up on the line looks it. A car somebody
	else drives has only its motion and its seat's Steer, which replicate: its wheels roll at the speed
	it moves, steer to what the input and the speed would let them, and it is sliding if it moves
	sideways faster than SLIDE_STUDS.

	The body is not animated at all. A car's pitch under braking, its squat, its roll in a corner are
	the physics' own (shared/CarPhysics acts through the tyres, below the centre of mass), and this
	shows the wheels following the road beneath it.

	world/VehicleChassis leaves on each wheel's roots (the tyre, which spins, and the brake disc, which
	only steers) where the wheel rests and how the root sits on it; this reads those and moves the Weld
	each root hangs from. Cars further than ANIMATE_STUDS from the camera are left as they are: a
	wheel nobody can see turning is not worth a raycast.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarPhysics = require(ReplicatedStorage:WaitForChild("CarPhysics"))
local CarSpec = require(ReplicatedStorage:WaitForChild("CarSpec"))

local ANIMATE_STUDS = 260
-- How fast another player's front wheels follow their steering, per second.
local STEER_RATE = 14
-- Studs a second a tyre slides across the road before it smokes and leaves a line.
local SLIDE_STUDS = 9
-- How far the steering wheel turns each way at full lock of the road wheels: a turn and a quarter.
local WHEEL_TURN = math.rad(450)
-- Roblox's own particle textures, shipped with the engine: nothing uploaded.
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

type Corner = {
	index: number,
	rest: Vector3,
	side: number,
	front: boolean,
	-- Per frame: how far the wheel hangs below its mount, where it touches the road.
	y: number,
	hit: boolean,
	point: Vector3,
	spin: number,
	patch: Attachment,
	smoke: ParticleEmitter,
	skid: Trail,
	sliding: number,
}

type Root = {
	weld: Weld,
	corner: Corner,
	spins: boolean,
	offset: CFrame,
}

type Car = {
	model: Model,
	hull: BasePart,
	seat: VehicleSeat?,
	spec: CarSpec.Spec,
	corners: { Corner },
	roots: { Root },
	params: RaycastParams,
	mountY: number,
	ride: number,
	bump: number,
	droop: number,
	radius: number,
	topSpeed: number,
	steer: number,
	wheel: { weld: Weld, base: CFrame, axis: Vector3 }?,
	flames: { ParticleEmitter },
	boosting: boolean,
	shifts: number,
}

local CarWheels = {}

local function number(model: Model, name: string, fallback: number): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

local function fireEmitter(): ParticleEmitter
	local fire = Instance.new("ParticleEmitter")
	fire.Name = "Nitro"
	fire.Texture = FIRE_TEXTURE
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
	return fire
end

-- Flames at each exhaust tip, pointing back out of the pipe.
local function flamesFor(model: Model): { ParticleEmitter }
	local flames: { ParticleEmitter } = {}
	for _, part in model:GetChildren() do
		if part.Name ~= "Exhaust" or not part:IsA("BasePart") then
			continue
		end
		if part:IsA("MeshPart") then
			-- A modelled car's exhaust is one piece with its tips across the back of it: flames at four
			-- evenly spaced points along it, pointing out of its back face.
			for _, share in { -0.36, -0.14, 0.14, 0.36 } do
				local tip = Instance.new("Attachment")
				tip.Name = "ExhaustTip"
				tip.Position = Vector3.new(part.Size.X * share, 0, part.Size.Z / 2)
				tip.Parent = part
				local fire = fireEmitter()
				fire.EmissionDirection = Enum.NormalId.Back
				fire.Parent = tip
				table.insert(flames, fire)
			end
		else
			-- The tip is the pipe's -X end, which CarBody turns to face the back of the car.
			local tip = Instance.new("Attachment")
			tip.Name = "ExhaustTip"
			tip.Position = Vector3.new(-part.Size.X / 2, 0, 0)
			tip.Parent = part
			local fire = fireEmitter()
			fire.EmissionDirection = Enum.NormalId.Left
			fire.Parent = tip
			table.insert(flames, fire)
		end
	end
	return flames
end

-- Smoke and a skid line at a wheel's contact patch.
local function tyreEffects(hull: BasePart, rest: Vector3, wheelWidth: number): (Attachment, ParticleEmitter, Trail)
	local patch = Instance.new("Attachment")
	patch.Name = "SmokePatch"
	patch.Position = rest
	patch.Parent = hull
	local puff = Instance.new("ParticleEmitter")
	puff.Name = "TyreSmoke"
	puff.Texture = SMOKE_TEXTURE
	puff.Color = ColorSequence.new(Color3.fromRGB(226, 228, 232))
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.0), NumberSequenceKeypoint.new(1, 5.5) })
	puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	puff.Lifetime = NumberRange.new(0.9, 1.7)
	puff.Speed = NumberRange.new(1, 4)
	puff.SpreadAngle = Vector2.new(50, 50)
	puff.Acceleration = Vector3.new(0, 3, 0)
	puff.Drag = 2
	puff.Rate = 0
	puff.Parent = patch
	-- Two points across the tread, a tyre's width apart: the trail between them is the mark.
	local a = Instance.new("Attachment")
	a.Name = "SkidA"
	a.Position = rest + Vector3.new(-wheelWidth / 2, 0, 0)
	a.Parent = hull
	local b = Instance.new("Attachment")
	b.Name = "SkidB"
	b.Position = rest + Vector3.new(wheelWidth / 2, 0, 0)
	b.Parent = hull
	local trail = Instance.new("Trail")
	trail.Name = "Skid"
	trail.Attachment0 = a
	trail.Attachment1 = b
	trail.Color = ColorSequence.new(Color3.fromRGB(14, 14, 16))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 3
	trail.MinLength = 0.1
	trail.LightInfluence = 1
	trail.FaceCamera = false
	trail.Enabled = false
	trail.Parent = hull
	return patch, puff, trail
end

local function read(model: Model): Car?
	local hull = model.PrimaryPart
	if hull == nil then
		return nil
	end
	local radius = number(model, "WheelRadius", 1.4)
	local corners: { [number]: Corner } = {}
	local roots: { Root } = {}
	for _, part in model:GetChildren() do
		local rest = part:GetAttribute("WheelRest")
		local weld = part:FindFirstChild("WheelWeld")
		local offset = part:GetAttribute("WheelOffset")
		local index = part:GetAttribute("WheelIndex")
		if typeof(rest) == "Vector3" and typeof(offset) == "CFrame" and typeof(index) == "number" and weld and weld:IsA("Weld") then
			local side = part:GetAttribute("WheelSide")
			local corner = corners[index]
			if corner == nil then
				local width = if part:IsA("BasePart") then part.Size.X else 1
				local patch, smoke, skid = tyreEffects(hull, rest, math.max(width, 0.8))
				corner = {
					index = index,
					rest = rest,
					side = if typeof(side) == "number" then side else 1,
					front = part:GetAttribute("WheelFront") == true,
					y = rest.Y,
					hit = true,
					point = Vector3.zero,
					spin = 0,
					patch = patch,
					smoke = smoke,
					skid = skid,
					sliding = 0,
				}
				corners[index] = corner
			end
			table.insert(roots, {
				weld = weld,
				corner = corner :: Corner,
				spins = part:GetAttribute("WheelSpins") == true,
				offset = offset,
			})
		end
	end
	local list: { Corner } = {}
	for _, corner in corners do
		table.insert(list, corner)
	end
	table.sort(list, function(a, b)
		return a.index < b.index
	end)
	if #list == 0 then
		return nil
	end
	local seat = model:FindFirstChild("DriverSeat")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	params.IgnoreWater = true

	-- The steering wheel of a car that has one to turn, about the line square to its rim.
	local wheel = nil
	local column = model:FindFirstChild("SteeringWheel")
	local steerWeld = if column then column:FindFirstChild("SteerWeld") else nil
	if steerWeld and steerWeld:IsA("Weld") then
		wheel = { weld = steerWeld, base = steerWeld.C0, axis = Vector3.new(0, 0.39, 0.92).Unit }
	end
	return {
		model = model,
		hull = hull,
		seat = if seat and seat:IsA("VehicleSeat") then seat else nil,
		spec = CarPhysics.SpecOf(model),
		corners = list,
		roots = roots,
		params = params,
		mountY = number(model, "MountY", 0),
		ride = number(model, "SpringRide", 1.2),
		bump = number(model, "SpringBump", 0.6),
		droop = number(model, "SpringDroop", 0.5),
		radius = radius,
		topSpeed = number(model, "TopSpeed", 80),
		steer = 0,
		wheel = wheel,
		flames = flamesFor(model),
		boosting = false,
		shifts = 0,
	}
end

local function animate(car: Car, dt: number)
	local hull = car.hull
	local frame = hull.CFrame
	local up = frame.UpVector
	local right = frame.RightVector
	local velocity = hull.AssemblyLinearVelocity
	local angular = hull.AssemblyAngularVelocity
	local com = hull.AssemblyCenterOfMass
	local speed = velocity:Dot(frame.LookVector)
	local rig = CarPhysics.Live[car.model]
	local tele = if rig then rig.tele else nil

	-- The front wheels' angle: the physics' own on the car this machine drives, what the seat's input
	-- and the speed would give on anyone else's.
	if tele then
		car.steer = tele.steer
	else
		local seat = car.seat
		local input = if seat and seat.Occupant then seat.SteerFloat else 0
		local wanted = CarPhysics.SteerAngle(car.spec, speed, input)
		car.steer += (wanted - car.steer) * math.clamp(STEER_RATE * dt, 0, 1)
	end

	local reach = car.ride + car.droop + car.radius
	local grounded = 0
	for i, corner in car.corners do
		local mount = frame:PointToWorldSpace(Vector3.new(corner.rest.X, car.mountY, corner.rest.Z))
		local hit = Workspace:Raycast(mount, -up * reach, car.params)
		local distance = if hit then (hit.Position - mount).Magnitude else reach
		-- The spring's length, and never shorter than the bump stop lets it be.
		local spring = math.clamp(distance - car.radius, car.ride - car.bump, car.ride + car.droop)
		corner.y = car.mountY - spring
		corner.hit = hit ~= nil
		if hit then
			corner.point = hit.Position
			grounded += 1
		end
		local omega = if tele then tele.omega[i] else speed / (car.radius)
		corner.spin = (corner.spin - omega * dt) % (math.pi * 2)

		-- Is this tyre sliding? Sideways over the road beyond SLIDE_STUDS, or (for the car this machine
		-- drives) turning against the road: locked under the brakes, or spinning on the throttle.
		local sliding = 0
		if corner.hit then
			local point = corner.point
			local vp = velocity + angular:Cross(point - com)
			local side = math.abs(vp:Dot(right))
			if side > SLIDE_STUDS and math.abs(speed) > 6 then
				sliding = math.clamp((side - SLIDE_STUDS) / 12, 0.15, 1)
			end
			if tele then
				local slip = math.abs(tele.slip[i] or 0)
				if slip > 0.25 and (tele.load[i] or 0) > 0 then
					sliding = math.max(sliding, math.clamp((slip - 0.25) / 0.5, 0.15, 1))
				end
			end
		end
		corner.sliding = sliding
		corner.patch.Position = Vector3.new(corner.rest.X, corner.y - car.radius + 0.12, corner.rest.Z)
		corner.smoke.Rate = sliding * 90
		local marking = sliding > 0.12
		if corner.skid.Enabled ~= marking then
			corner.skid.Enabled = marking
		end
	end

	for _, root in car.roots do
		local corner = root.corner
		-- Steering right turns the wheel's nose toward +X: a negative turn about Y.
		local yaw = if corner.front then -car.steer else 0
		local turn = if corner.side < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new()
		local roll = if root.spins then CFrame.Angles(corner.spin * corner.side, 0, 0) else CFrame.new()
		root.weld.C0 = CFrame.new(corner.rest.X, corner.y, corner.rest.Z) * CFrame.Angles(0, yaw, 0) * turn * roll * root.offset
	end

	-- The steering wheel follows the road wheels' angle in proportion to their lock.
	local column = car.wheel
	if column then
		local lock = math.rad(car.spec.steerLock)
		local angle = -math.clamp(car.steer / lock, -1.2, 1.2) * WHEEL_TURN
		column.weld.C0 = column.base * CFrame.fromAxisAngle(column.axis, angle)
	end

	-- Nitro: the driver's machine says; anyone else's car shows it in how fast it goes. On a modelled car
	-- a shift at high revs also crackles out of the pipes.
	local localBoost = car.model:GetAttribute("Boosting")
	local boosting = if typeof(localBoost) == "boolean" then localBoost else speed > car.topSpeed * 1.03
	if boosting ~= car.boosting then
		car.boosting = boosting
		for _, fire in car.flames do
			fire.Enabled = boosting
		end
	end
	if tele then
		if tele.shifts ~= car.shifts then
			car.shifts = tele.shifts
			if tele.rpm > tele.redline * 0.7 and tele.throttle > 0.4 then
				for _, fire in car.flames do
					fire:Emit(5)
				end
			end
		end
	else
		car.shifts = 0
	end
end

function CarWheels.Start()
	local cars: { [Model]: Car } = {}
	local function add(model: Instance)
		if model:IsA("Model") then
			-- Built on the server with its wheels already welded; read once it has arrived whole.
			CarPhysics.WhenReady(model, function()
				if cars[model] == nil then
					local car = read(model)
					if car then
						cars[model] = car
					end
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
