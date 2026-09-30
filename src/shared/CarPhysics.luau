--!strict
--[[
	How a car drives: one physics step of a raycast-wheel vehicle, simulated from its real numbers
	(shared/CarSpec). Shared, because the step has to run on whichever machine owns the car's
	physics: the server for a parked car, the driver's own machine while somebody is at the wheel
	(client/world/CarDriver). A step written from the wrong end arrives late, and late forces buck a
	car onto its roof -- which is how this file came to be separate in the first place.

	WHAT A STEP DOES, in order:

	  1. Each wheel casts a ray down from its mount. Where it lands is the contact patch; how far the
	     wheel is from the body is the spring's length.
	  2. The suspension: a spring and damper per corner, an anti-roll bar per axle, a bump stop. Its
	     rate is set the way a real car's is, by the ride frequency it is meant to have (1.75 Hz is a
	     firm sports car's) -- k = m (2 pi f)^2 -- and so is how hard it is damped.
	  3. The driver's pedals, smoothed: a key is either down or up, a foot is not.
	  4. The engine and the gearbox: rpm from how fast the driven wheels turn, a torque curve, a
	     turbo that takes a moment to spool, an automatic that shifts on rpm and throttle and cuts the
	     torque while it does, and a slipping clutch that holds the engine up off the line.
	  5. The tyres. Each patch carries a share of the weight, and from that, as much grip as a tyre
	     has. Drive and braking want a longitudinal force, the car's sideways slide wants a lateral
	     one (a slip angle, through a magic-formula curve), and both draw on the same grip: past it,
	     both fall back and the tyre slides. ABS holds the brakes just under that edge; traction
	     control holds the drive there.
	  6. The air: drag, and downforce if the car makes any.
	  7. Every force is written onto a VectorForce in the world's frame, at the point it acts.

	Nothing is written onto the car's velocity. Pitch under braking, squat on the throttle, roll in a
	corner and the car's whole yaw come out of those forces acting at the patches, below the centre
	of mass, because that is where they come from in a real car.

	UNITS. Real ones, converted at the edge. A stud is 0.28 m; forces are worked in newtons against
	the spec's real mass and scaled to the assembly's Roblox mass at the end, so every acceleration
	is a real acceleration. The one place the world shows through is gravity: Roblox's is 5.6 times
	real at this scale, so the springs carry the weight against it (preload) while grip and weight
	transfer are worked out against 9.81 m/s^2 -- see the GRIP LOAD comment below.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = workspace

local CarSpec = require(ReplicatedStorage:WaitForChild("CarSpec"))

type Spec = CarSpec.Spec

local S = CarSpec.StudsPerMetre
local G_REAL = CarSpec.Gravity
local AIR_DENSITY = 1.2
-- Reverse power fades out from REVERSE_FADE to nothing at REVERSE_LIMIT: 32 to 43 km/h.
local REVERSE_FADE, REVERSE_LIMIT = 9, 12
-- How much of a front wheel's share of the braking a rear wheel is asked for, at the same load.
local REAR_BRAKE = 0.9

local CarPhysics = {}

-- The tag every drivable car carries, so a client can find the cars it animates and drives.
CarPhysics.Tag = "AgesCar"

-- The rig of the car this machine is driving, by model, for the wheels, the sound and the camera to
-- read the telemetry of. Empty for every car somebody else has the wheel of.
CarPhysics.Live = setmetatable({}, { __mode = "k" }) :: { [Model]: any }

export type Controls = {
	-- -1 to 1: W is 1, S is -1. Forward, it is the throttle; against the way the car is going it is
	-- the brake; once stopped, pushed back, it is reverse.
	throttle: number,
	-- -1 (left) to 1 (right).
	steer: number,
	-- 0 to 1: the rear wheels locked.
	handbrake: number,
	-- Nitro: extra torque while held.
	boost: boolean,
}

export type Telemetry = {
	speed: number, -- studs/s along the nose, signed
	kph: number,
	rpm: number,
	redline: number,
	gear: number, -- -1 reverse, 1..n
	throttle: number,
	brake: number,
	steer: number, -- radians at the front wheels
	abs: boolean,
	tc: boolean,
	sliding: boolean,
	grounded: number,
	shifted: boolean, -- true for the one step a shift starts in
	shifts: number, -- how many shifts there have been: a count, for a reader that can miss one step
	boost: number, -- turbo boost, 0 to 1
	nitro: boolean,
	longG: number,
	latG: number,
	-- Per wheel, in wheel order: how hard it is slipping (1 = all of it), how fast it turns, how
	-- compressed its spring is, and how loaded.
	slip: { number },
	omega: { number },
	compression: { number },
	load: { number },
}

type Wheel = {
	mount: Vector3, -- hull-local: where its ray starts
	front: boolean,
	side: number,
	driven: boolean,
	radius: number, -- studs
	share: number, -- of the car's mass this corner carries
	susp: VectorForce?,
	patch: Attachment?,
	tyre: VectorForce?,
	-- Per step.
	hit: boolean,
	point: Vector3,
	normal: Vector3,
	surface: number,
	spring: number,
	rate: number,
	load: number, -- the suspension's push, in Roblox force
	grip: number, -- the weight the tyre's grip is worked from, in newtons
	compress: number,
	-- Kept between steps.
	omega: number,
	slip: number,
	sideForce: number,
}

export type Rig = {
	model: Model,
	hull: BasePart,
	seat: VehicleSeat,
	spec: Spec,
	wheels: { Wheel },
	body: VectorForce?,
	params: RaycastParams,
	ride: number, -- the spring's length at rest, studs
	bumpMin: number,
	rayLength: number,
	-- Kept between steps.
	throttle: number,
	brake: number,
	handbrake: number,
	steerAngle: number,
	reverse: boolean,
	gear: number,
	nextGear: number,
	shiftTimer: number,
	shiftHold: number,
	rpm: number,
	boost: number,
	tcCut: number,
	lastVel: Vector3,
	longG: number,
	latG: number,
	tele: Telemetry,
}

-- What a tyre has to hold on, by what it is on: a multiple of its grip on asphalt.
local SURFACE: { [Enum.Material]: number } = {
	[Enum.Material.Asphalt] = 1,
	[Enum.Material.Concrete] = 0.98,
	[Enum.Material.Pavement] = 0.96,
	[Enum.Material.Slate] = 0.9,
	[Enum.Material.Brick] = 0.85,
	[Enum.Material.Cobblestone] = 0.8,
	[Enum.Material.Granite] = 0.85,
	[Enum.Material.Marble] = 0.7,
	[Enum.Material.WoodPlanks] = 0.75,
	[Enum.Material.Wood] = 0.75,
	[Enum.Material.Metal] = 0.65,
	[Enum.Material.DiamondPlate] = 0.65,
	[Enum.Material.Plastic] = 0.85,
	[Enum.Material.SmoothPlastic] = 0.82,
	[Enum.Material.Grass] = 0.5,
	[Enum.Material.LeafyGrass] = 0.5,
	[Enum.Material.Ground] = 0.58,
	[Enum.Material.Mud] = 0.42,
	[Enum.Material.Sand] = 0.45,
	[Enum.Material.Sandstone] = 0.7,
	[Enum.Material.Rock] = 0.8,
	[Enum.Material.Snow] = 0.3,
	[Enum.Material.Ice] = 0.12,
	[Enum.Material.Glacier] = 0.12,
}
local DEFAULT_SURFACE = 0.9

local function number(model: Model, name: string, fallback: number): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

local function approach(current: number, target: number, rise: number, fall: number, dt: number): number
	local rate = if target > current then rise else fall
	local step = rate * dt
	if math.abs(target - current) <= step then
		return target
	end
	return current + math.sign(target - current) * step
end

local function unit(v: Vector3, fallback: Vector3): Vector3
	if v.Magnitude < 1e-4 then
		return fallback
	end
	return v.Unit
end

--[[
	The spec a model carries: its own SpecId if CarSpec has one by that name, otherwise one made from
	the numbers world/VehicleChassis stamped on it.
]]
function CarPhysics.SpecOf(model: Model): Spec
	local id = model:GetAttribute("SpecId")
	if typeof(id) == "string" and CarSpec.Specs[id] then
		return CarSpec.Specs[id]
	end
	local name = if typeof(id) == "string" then id else "car"
	return CarSpec.Derive(
		name,
		number(model, "TopSpeed", 80),
		number(model, "Acceleration", 12),
		number(model, "SteerDegrees", 30),
		Vector3.new(number(model, "SizeX", 7), number(model, "SizeY", 5), number(model, "SizeZ", 16)),
		(model:GetAttribute("Drive") :: any) or "RWD",
		number(model, "WheelRadius", 1.4)
	)
end

--[[
	What a step needs, found on a car world/VehicleChassis built. `rider`, if given, is left out of
	the wheels' rays as well as the car itself -- the driver sits inside the car, and a ray must
	never find their legs.
]]
function CarPhysics.Rig(model: Model, rider: Instance?): Rig?
	local hull = model.PrimaryPart
	local seat = model:FindFirstChild("DriverSeat")
	if hull == nil or seat == nil or not seat:IsA("VehicleSeat") then
		return nil
	end
	local spec = CarPhysics.SpecOf(model)
	local radius = number(model, "WheelRadius", spec.tyreRadius * S)
	local ride = number(model, "SpringRide", 1.2)

	-- Where the centre of mass is along the car decides how the weight is shared between the axles.
	local comLocal = hull.CFrame:PointToObjectSpace(hull.AssemblyCenterOfMass)
	local mounts: { Attachment } = {}
	for _, child in hull:GetChildren() do
		if child:IsA("Attachment") and child.Name == "SuspensionMount" then
			table.insert(mounts, child)
		end
	end
	table.sort(mounts, function(a, b)
		return (a:GetAttribute("WheelIndex") :: number) < (b:GetAttribute("WheelIndex") :: number)
	end)
	if #mounts < 4 then
		return nil
	end
	local frontZ, rearZ = math.huge, -math.huge
	for _, mount in mounts do
		frontZ = math.min(frontZ, mount.Position.Z)
		rearZ = math.max(rearZ, mount.Position.Z)
	end
	local frontShare = math.clamp((rearZ - comLocal.Z) / math.max(rearZ - frontZ, 0.1), 0.2, 0.8)

	local wheels: { Wheel } = {}
	for index, mount in mounts do
		local front = mount:GetAttribute("Front") == true
		local side = (mount:GetAttribute("Side") :: number?) or 1
		local patch = hull:FindFirstChild("TyrePatch" .. index)
		local driven = spec.drive == "AWD" or (spec.drive == "FWD" and front) or (spec.drive == "RWD" and not front)
		table.insert(wheels, {
			mount = mount.Position,
			front = front,
			side = side,
			driven = driven,
			radius = radius,
			share = (if front then frontShare else 1 - frontShare) / 2,
			susp = mount:FindFirstChildOfClass("VectorForce"),
			patch = if patch and patch:IsA("Attachment") then patch else nil,
			tyre = if patch then patch:FindFirstChildOfClass("VectorForce") else nil,
			hit = false,
			point = Vector3.zero,
			normal = Vector3.yAxis,
			surface = 1,
			spring = ride,
			rate = 0,
			load = 0,
			grip = 0,
			compress = 0,
			omega = 0,
			slip = 0,
			sideForce = 0,
		})
	end
	local bodyMount = hull:FindFirstChild("BodyMount")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if rider then { model, rider } else { model }
	params.IgnoreWater = true
	local bump = number(model, "SpringBump", spec.travelBump * S)
	local droop = number(model, "SpringDroop", spec.travelDroop * S)
	local count = #wheels
	return {
		model = model,
		hull = hull,
		seat = seat,
		spec = spec,
		wheels = wheels,
		body = if bodyMount then bodyMount:FindFirstChildOfClass("VectorForce") else nil,
		params = params,
		ride = ride,
		bumpMin = ride - bump,
		rayLength = ride + droop + radius,
		throttle = 0,
		brake = 0,
		handbrake = 0,
		steerAngle = 0,
		reverse = false,
		gear = 1,
		nextGear = 1,
		shiftTimer = 0,
		shiftHold = 0,
		rpm = spec.idleRpm,
		boost = 0,
		tcCut = 1,
		lastVel = Vector3.zero,
		longG = 0,
		latG = 0,
		tele = {
			speed = 0,
			kph = 0,
			rpm = spec.idleRpm,
			redline = spec.redlineRpm,
			gear = 1,
			throttle = 0,
			brake = 0,
			steer = 0,
			abs = false,
			tc = false,
			sliding = false,
			grounded = 0,
			shifted = false,
			shifts = 0,
			boost = 0,
			nitro = false,
			longG = 0,
			latG = 0,
			slip = table.create(count, 0),
			omega = table.create(count, 0),
			compression = table.create(count, 0),
			load = table.create(count, 0),
		},
	}
end

--[[
	The most the front wheels turn, in radians, at `speed` (studs/s): all of the lock parked, and
	less and less as the car goes faster -- to the angle that would, all by itself, pull the most
	lateral g the tyres have, plus a few degrees for the slip angles a tyre works at. A driver with
	a keyboard has full lock or none, and a car that could turn sharper than its tyres can grip would
	spend every corner sliding straight on.
]]
function CarPhysics.MaxSteer(spec: Spec, speed: number): number
	local v = math.max(math.abs(speed) / S, 2)
	local limit = spec.mu * G_REAL * 0.9
	local grip = math.atan(limit * spec.wheelbase / (v * v)) + math.rad(6)
	return math.clamp(grip, math.rad(4), math.rad(spec.steerLock))
end

-- The steering a car somebody else is driving shows: the same angle, read off their input.
function CarPhysics.SteerAngle(spec: Spec, speed: number, input: number): number
	return input * CarPhysics.MaxSteer(spec, speed)
end

-- Engine rpm and gear for a car whose physics this machine does not run: what the gearbox would
-- choose at `speed` and `throttle`.
function CarPhysics.EstimateRpm(spec: Spec, speed: number, throttle: number): (number, number)
	local wheel = math.abs(speed) / S / spec.tyreRadius
	local upRpm = spec.redlineRpm * 0.55 + (spec.redlineRpm - 300 - spec.redlineRpm * 0.55) * math.clamp(throttle, 0, 1)
	local gear = 1
	for g = 1, #spec.gears do
		gear = g
		if wheel * spec.gears[g] * spec.finalDrive * 60 / (2 * math.pi) < upRpm then
			break
		end
	end
	local rpm = wheel * spec.gears[gear] * spec.finalDrive * 60 / (2 * math.pi)
	return math.clamp(rpm, spec.idleRpm + 100 * throttle, spec.limiterRpm), gear
end

--[[
	One step: `dt` seconds, and what the driver is doing (all zeros, and the handbrake on, for a car
	nobody is in). Returns the telemetry the HUD, the sound and the wheels read.
]]
function CarPhysics.Step(rig: Rig, dt: number, controls: Controls): Telemetry
	local hull = rig.hull
	local tele = rig.tele
	if hull.Parent == nil then
		return tele
	end
	-- `dt` is the time the physics covers between this step and the next: RunService.PreSimulation's.
	dt = math.clamp(dt, 1 / 240, 1 / 12)
	local spec = rig.spec
	local wheels = rig.wheels
	local count = #wheels
	local G = Workspace.Gravity
	local frame = hull.CFrame
	local up = frame.UpVector
	local fwdHull = frame.LookVector
	local vel = hull.AssemblyLinearVelocity
	local angVel = hull.AssemblyAngularVelocity
	local com = hull.AssemblyCenterOfMass
	local mass = hull.AssemblyMass
	-- Roblox force per real newton: every tyre force below is worked in newtons on the spec's real
	-- mass, so its acceleration is a real one, and is scaled to this assembly's mass at the end.
	local fs = mass * S / spec.massKg
	local vLong = vel:Dot(fwdHull) / S
	local speedMs = vel.Magnitude / S

	-- 3. The pedals. -------------------------------------------------------------------------
	local pedal = math.clamp(controls.throttle, -1, 1)
	local throttleIn, brakeIn = 0, 0
	if pedal > 0.02 then
		if vLong < -1 then
			brakeIn = pedal
		else
			rig.reverse = false
			throttleIn = pedal
		end
	elseif pedal < -0.02 then
		if vLong > 1 and not rig.reverse then
			brakeIn = -pedal
		else
			rig.reverse = true
			throttleIn = -pedal
		end
	end
	rig.throttle = approach(rig.throttle, throttleIn, 6, 10, dt)
	rig.brake = approach(rig.brake, brakeIn, 8, 14, dt)
	rig.handbrake = approach(rig.handbrake, math.clamp(controls.handbrake, 0, 1), 12, 8, dt)

	-- The front wheels' angle: limited by speed, and only so fast to move.
	local maxSteer = CarPhysics.MaxSteer(spec, vLong * S)
	local wanted = math.clamp(controls.steer, -1, 1) * maxSteer
	-- Turning further from straight ahead is slower than coming back to it.
	local awayFromCentre = math.abs(wanted) > math.abs(rig.steerAngle) and (rig.steerAngle == 0 or math.sign(wanted) == math.sign(rig.steerAngle))
	local steerRate = (if awayFromCentre then 2.8 else 4.5) * maxSteer + 0.3
	local steerStep = steerRate * dt
	if math.abs(wanted - rig.steerAngle) <= steerStep then
		rig.steerAngle = wanted
	else
		rig.steerAngle += math.sign(wanted - rig.steerAngle) * steerStep
	end

	-- 1 and 2. The wheels, the road and the springs. ----------------------------------------
	local grounded = 0
	local normalSum = Vector3.zero
	for _, w in wheels do
		local origin = frame:PointToWorldSpace(w.mount)
		local result = Workspace:Raycast(origin, -up * rig.rayLength, rig.params)
		if result then
			w.hit = true
			w.point = result.Position
			w.normal = result.Normal
			w.surface = SURFACE[result.Material] or DEFAULT_SURFACE
			w.spring = (result.Position - origin).Magnitude - w.radius
			grounded += 1
			normalSum += result.Normal
		else
			w.hit = false
			w.spring = rig.rayLength - w.radius
		end
		local velocityAtMount = vel + angVel:Cross(origin - com)
		w.rate = -velocityAtMount:Dot(up)
		w.compress = rig.ride - w.spring
	end

	-- The anti-roll bar pushes the lower side up and the higher down, in proportion to how unevenly
	-- the axle is loaded.
	local bar: { number } = table.create(count, 0)
	for i = 1, count, 2 do
		local left, right = wheels[i], wheels[i + 1]
		if left.hit and right.hit then
			local mc = mass * left.share
			local hz = if left.front then spec.rideFront else spec.rideRear
			local k = mc * (2 * math.pi * hz) ^ 2
			local stiffness = k * (if left.front then spec.antiRollFront else spec.antiRollRear)
			local diff = left.compress - right.compress
			bar[i] = stiffness * diff
			bar[i + 1] = -stiffness * diff
		end
	end

	for i, w in wheels do
		local mc = mass * w.share
		local preload = mc * G
		local load = 0
		if w.hit then
			local hz = if w.front then spec.rideFront else spec.rideRear
			local omega = 2 * math.pi * hz
			local k = mc * omega * omega
			local zeta = if w.rate > 0 then spec.zetaBump else spec.zetaRebound
			-- The force is set once a step and held for the whole of it, so a damper cannot be asked for
			-- more than takes all of a wheel's speed off in one step, or it overshoots and buzzes: on a
			-- slow machine, where steps are long, the ride would shake itself apart.
			local c = math.min(2 * zeta * mc * omega, 0.9 * mc / dt)
			local push = k * w.compress + c * w.rate + bar[i]
			-- The bump stop: past the end of the travel the spring stiffens fast -- as fast as a step this
			-- long can follow without ringing.
			if w.spring < rig.bumpMin then
				local stiffen = math.min(18, 1 / math.max(omega * omega * dt * dt, 1e-4))
				push += k * stiffen * (rig.bumpMin - w.spring)
			end
			load = math.clamp(preload + push, 0, preload * 5)
		end
		w.load = load
		-- GRIP LOAD. The springs hold the car up against the world's gravity, so the force in them is
		-- five and a half times the weight a real car's would be; grip worked from that would be five
		-- and a half g. What matters for grip is the real weight on the tyre and how it shifts, and
		-- the shift is exactly the springs' force above their preload (the rest is just gravity), in
		-- real newtons -- so grip is the real static share, plus the dynamic part.
		local dynamic = (load - preload) / fs
		w.grip = if w.hit then math.max(0, spec.massKg * G_REAL * w.share + dynamic) else 0
		if w.susp then
			-- Along the road's normal, not the body's up: a wheel is pushed by the road, at right angles to
			-- it. Along the body's axis a car that squats would push itself backward with its own springs,
			-- and one that dives would push itself forward.
			w.susp.Force = (if w.hit then w.normal else up) * load
		end
	end

	-- 4. The engine and the gearbox. ---------------------------------------------------------
	local omegaSum, omegaN = 0, 0
	local drivenCount = 0
	for _, w in wheels do
		if w.driven then
			drivenCount += 1
			omegaSum += w.omega
			omegaN += 1
		end
	end
	local omegaDrive = if omegaN > 0 then omegaSum / omegaN else 0
	local gears = spec.gears
	local n = #gears
	local ratio = (if rig.reverse then spec.reverse else gears[rig.gear]) * spec.finalDrive
	local rpmWheel = math.abs(omegaDrive) * ratio * 60 / (2 * math.pi)

	local shifted = false
	if rig.reverse then
		rig.gear = 1
		rig.shiftTimer = 0
	elseif rig.shiftTimer > 0 then
		rig.shiftTimer -= dt
		if rig.shiftTimer <= 0 then
			rig.gear = rig.nextGear
			rig.shiftHold = 0.4
		end
	else
		rig.shiftHold = math.max(0, rig.shiftHold - dt)
		if rig.shiftHold <= 0 and grounded > 0 then
			local red = spec.redlineRpm
			local upRpm = red * 0.55 + (red - 300 - red * 0.55) * rig.throttle
			local downRpm = spec.idleRpm + 600 + (red * 0.42 - spec.idleRpm - 600) * rig.throttle
			if rig.gear < n and rpmWheel > upRpm then
				rig.nextGear = rig.gear + 1
				rig.shiftTimer = spec.shiftTime
				shifted = true
			elseif rig.gear > 1 and rpmWheel < downRpm then
				local after = rpmWheel * gears[rig.gear - 1] / gears[rig.gear]
				if after < red - 500 then
					rig.nextGear = rig.gear - 1
					rig.shiftTimer = spec.shiftTime
					shifted = true
				end
			end
		end
	end
	local engaged = rig.shiftTimer <= 0
	-- Off the line the clutch slips and holds the engine at launch rpm; in a shift it is open.
	local slipRpm = spec.idleRpm + (spec.launchRpm - spec.idleRpm) * math.min(1, rig.throttle * 1.25)
	local target = if engaged then math.max(rpmWheel, slipRpm) else math.max(rpmWheel, spec.idleRpm)
	rig.rpm += (target - rig.rpm) * math.min(1, dt * (if target > rig.rpm then 18 else 9))

	local boostMult = 1
	if spec.turbo then
		local want = rig.throttle * math.clamp(rig.rpm / spec.boostRpm, 0, 1) ^ 1.5
		rig.boost += (want - rig.boost) * math.min(1, dt / spec.boostLag)
		boostMult = spec.boostBase + (1 - spec.boostBase) * rig.boost
	end
	local nitro = controls.boost
	if nitro then
		boostMult *= 1.4
	end
	local torque = CarSpec.Torque(spec, rig.rpm) * rig.throttle * boostMult
	if rig.rpm > spec.limiterRpm and rig.throttle > 0 then
		torque = 0
	end
	-- Closing the throttle drags the engine against the road: engine braking.
	torque -= spec.engineBrake * (0.3 + 0.7 * rig.rpm / spec.redlineRpm) * (1 - rig.throttle)
	if not engaged then
		torque = 0
	end
	-- The gearbox limits reverse: the power fades out between these two speeds, in metres a second.
	if rig.reverse then
		torque *= math.clamp((REVERSE_LIMIT - (-vLong)) / (REVERSE_LIMIT - REVERSE_FADE), 0, 1)
	end
	local wheelTorque = torque * ratio * spec.driveEff * (if rig.reverse then -1 else 1)

	-- Traction control: if a driven wheel spins well past the road, take some drive away.
	local maxSpin = 0
	for _, w in wheels do
		if w.driven and w.hit then
			local roll = math.abs(vLong)
			local spin = (math.abs(w.omega) * w.radius / S - roll) / math.max(roll, 3)
			maxSpin = math.max(maxSpin, spin)
		end
	end
	local tcWanted = 1
	if spec.tc and maxSpin > 0.16 then
		tcWanted = math.clamp(1 - (maxSpin - 0.16) / 0.22, 0.15, 1)
	end
	rig.tcCut += (tcWanted - rig.tcCut) * math.min(1, dt * 30)
	local tcActive = rig.tcCut < 0.95
	if wheelTorque > 0 or rig.reverse then
		wheelTorque *= rig.tcCut
	end

	-- The rotating parts the engine also has to spin up: more in a low gear, which is why a car
	-- pulls harder than its torque alone says in a high one.
	local rotating = spec.engineInertia * ratio * ratio * spec.driveEff + spec.wheelInertia * 4
	local inertiaFactor = 1 / (1 + rotating / (spec.massKg * spec.tyreRadius * spec.tyreRadius))

	-- 5. The tyres. ---------------------------------------------------------------------------
	local brakeCap = rig.brake * spec.brakeG * G_REAL * spec.massKg
	-- Electronic brake-force distribution: each wheel is asked for braking in proportion to the weight
	-- on it (the rears a little less, for stability), so under hard braking, when the weight is all on
	-- the front, the fronts do the work and the rears are not locked up by a fixed split.
	local ebdSum = 0
	for _, w in wheels do
		ebdSum += w.grip * (if w.front then 1 else REAR_BRAKE)
	end
	local handbrakeCap = rig.handbrake * 2.5 * G_REAL * spec.massKg / 4
	local mw = spec.massKg / 4
	local anyAbs = false
	local anySliding = false
	local latSum, longSum = 0, 0
	local forceScale = fs
	for i, w in wheels do
		local tyre = w.tyre
		local patch = w.patch
		if not w.hit or tyre == nil or patch == nil then
			-- Airborne: the wheel coasts.
			w.omega *= 1 - math.min(1, dt * 0.4)
			w.slip = 0
			w.sideForce = 0
			if tyre then
				tyre.Force = Vector3.zero
			end
			tele.slip[i] = 0
			tele.omega[i] = w.omega
			tele.compression[i] = w.compress
			tele.load[i] = 0
			continue
		end
		-- The wheel's own frame on the road: forward, and to the right.
		local normal = w.normal
		local f0 = unit(fwdHull - normal * fwdHull:Dot(normal), fwdHull)
		local r0 = f0:Cross(normal)
		local steer = if w.front then rig.steerAngle else 0
		local fw = f0 * math.cos(steer) + r0 * math.sin(steer)
		local rw = fw:Cross(normal)

		local vp = vel + angVel:Cross(w.point - com)
		local vx = vp:Dot(fw) / S
		local vy = vp:Dot(rw) / S
		local muBase = spec.mu * w.surface * (if w.front then spec.muFront else spec.muRear)
		local limX = muBase * (spec.muLong / spec.mu) * w.grip
		local limY = muBase * w.grip

		-- Longitudinal: the drive, the brakes and the rolling resistance.
		local driveForce = 0
		if w.driven then
			local share = if spec.drive == "AWD" then (if w.front then spec.frontBias else 1 - spec.frontBias) / 2 else 1 / drivenCount
			driveForce = wheelTorque * share / (w.radius / S) * inertiaFactor
		end
		local share = if ebdSum > 0 then w.grip * (if w.front then 1 else REAR_BRAKE) / ebdSum else 0.25
		local brakeForce = 0
		local slowing = math.clamp(vx / 0.4, -1, 1)
		if brakeCap > 0 then
			brakeForce -= math.clamp(mw * vx * 0.9 / dt, -brakeCap * share, brakeCap * share)
		end
		local handbrakeForce = 0
		if not w.front and handbrakeCap > 0 then
			handbrakeForce = -math.clamp(mw * vx * 0.9 / dt, -handbrakeCap, handbrakeCap)
		end
		local rolling = -slowing * spec.rollingResistance * w.grip

		-- Lateral: a slip angle, through the magic formula, as a share of the grip there is.
		local alpha = math.atan2(vy, math.abs(vx) + 1)
		local curve = math.sin(spec.cornerC * math.atan(spec.cornerB * math.abs(alpha)))
		local lateral = -math.sign(alpha) * limY * curve
		-- Held at a standstill: no slip angle to read, so stop the sliding directly.
		local creep = 1 - math.clamp(speedMs / 2.5, 0, 1)
		if creep > 0 then
			local stick = -math.clamp(mw * vy * 0.9 / dt, -limY, limY)
			lateral = lateral * (1 - creep) + stick * creep
		end
		-- Never more than it takes to stop the slide this step: anything more overshoots.
		local budget = mw * math.abs(vy) * 0.85 / dt
		lateral = math.clamp(lateral, -budget - 1, budget + 1)
		-- A little of what was there: a tyre takes a moment to build its side force.
		lateral = w.sideForce + (lateral - w.sideForce) * math.min(1, dt * (8 + math.abs(vx) * 1.5))

		-- ABS: the brakes may take the grip the corner is not using, and no more.
		local wantLong = driveForce + brakeForce + handbrakeForce + rolling
		local usesLateral = math.clamp(math.abs(lateral) / math.max(limY, 1), 0, 0.99)
		local availLong = limX * math.sqrt(1 - usesLateral * usesLateral)
		local absOn = false
		if spec.abs and brakeForce < 0 and vx > 1 and wantLong < -availLong * 0.96 and handbrakeForce == 0 then
			wantLong = -availLong * 0.96
			absOn = true
			anyAbs = true
		end

		-- Both forces draw on one grip: past it, both fall back, and the tyre slides.
		local usage = math.sqrt((wantLong / math.max(limX, 1)) ^ 2 + (lateral / math.max(limY, 1)) ^ 2)
		local Fx, Fy = wantLong, lateral
		local sliding = usage > 1.0 and not absOn
		if usage > 1 then
			local slide = if absOn then 1 else 1 - (1 - spec.muSlide) * math.clamp((usage - 1) * 2.5, 0, 1)
			Fx = wantLong / usage * slide
			Fy = lateral / usage * slide
		end
		w.sideForce = Fy
		if sliding then
			anySliding = true
		end

		-- The wheel itself: it rolls with the road unless the tyre is sliding, and then the drive
		-- spins it up or the brakes hold it.
		local roll = vx / (w.radius / S)
		if sliding or (handbrakeForce ~= 0 and math.abs(handbrakeForce) > limX) then
			local inertia = spec.wheelInertia + (if w.driven and engaged then spec.engineInertia * ratio * ratio / math.max(drivenCount, 1) else 0)
			local driveTorque = driveForce * (w.radius / S)
			local next = w.omega + (driveTorque - Fx * (w.radius / S)) / inertia * dt
			local brakeTorque = (math.abs(brakeForce) + math.abs(handbrakeForce)) * (w.radius / S)
			local drop = brakeTorque / inertia * dt
			if next > 0 then
				next = math.max(0, next - drop)
			else
				next = math.min(0, next + drop)
			end
			w.omega = next
		else
			w.omega += (roll - w.omega) * math.min(1, dt * 40)
		end
		w.slip = if math.abs(vx) > 0.5 or math.abs(w.omega) > 0.5 then (w.omega * (w.radius / S) - vx) / math.max(math.abs(vx), 2) else 0
		longSum += Fx
		latSum += Fy

		patch.WorldPosition = w.point
		tyre.Force = (fw * Fx + rw * Fy) * forceScale
		tele.slip[i] = w.slip
		tele.omega[i] = w.omega
		tele.compression[i] = w.compress
		tele.load[i] = w.grip
	end

	-- 6. The air and the road's slope. -------------------------------------------------------
	local body = rig.body
	if body then
		local velDir = unit(vel, fwdHull)
		local drag = -velDir * (0.5 * AIR_DENSITY * spec.cdA * speedMs * speedMs * fs)
		local lift = up * (0.5 * AIR_DENSITY * spec.liftA * speedMs * speedMs * fs)
		local extra = Vector3.zero
		if grounded >= 2 then
			-- Roblox's gravity is 5.6 times real, so a hill pulls a car 5.6 times as hard as it would pull
			-- a real one. On the ground the part of gravity along the road is cut to a real g's share; the
			-- part into the road is left to the springs.
			local n1 = unit(normalSum / grounded, up)
			local gravity = Vector3.new(0, -G, 0)
			local along = gravity - n1 * gravity:Dot(n1)
			extra = -along * mass * (1 - S * G_REAL / G)
		end
		body.Force = drag + lift + extra
	end

	-- Telemetry. -------------------------------------------------------------------------------
	local accel = (vel - rig.lastVel) / dt
	rig.lastVel = vel
	rig.longG += ((accel:Dot(fwdHull) / S / G_REAL) - rig.longG) * math.min(1, dt * 8)
	rig.latG += ((accel:Dot(frame.RightVector) / S / G_REAL) - rig.latG) * math.min(1, dt * 8)
	tele.speed = vel:Dot(fwdHull)
	tele.kph = vLong * 3.6
	tele.rpm = rig.rpm
	tele.gear = if rig.reverse then -1 else rig.gear
	tele.throttle = rig.throttle
	tele.brake = rig.brake
	tele.steer = rig.steerAngle
	tele.abs = anyAbs
	tele.tc = tcActive
	tele.sliding = anySliding
	tele.grounded = grounded
	tele.shifted = shifted
	if shifted then
		tele.shifts += 1
	end
	tele.boost = rig.boost
	tele.nitro = nitro
	tele.longG = rig.longG
	tele.latG = rig.latG
	return tele
end

-- Parked: the brakes on, nobody steering.
function CarPhysics.Park(rig: Rig, dt: number): Telemetry
	local tele = CarPhysics.Step(rig, dt, { throttle = 0, steer = 0, handbrake = 1, boost = false })
	-- A car at rest on the road is at rest: the tyres' forces hold it to within a hair's breadth, and
	-- that hair would be a parked car creeping a stud every ten seconds.
	local hull = rig.hull
	local v = hull.AssemblyLinearVelocity
	if tele.grounded >= 3 and Vector3.new(v.X, 0, v.Z).Magnitude < 0.35 and hull.AssemblyAngularVelocity.Magnitude < 0.05 then
		hull.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
	end
	return tele
end

return CarPhysics
