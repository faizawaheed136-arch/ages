--!strict
--[[
	How a car drives, one physics step at a time: raycast springs, the drive, the grip and the
	steering. Shared, because the step must run on whichever machine is simulating the car.

	WHO RUNS IT. Roblox simulates an assembly on its network owner. A parked car belongs to the
	server, so world/VehicleChassis steps it there. The moment a player sits at the wheel, the
	chassis hands them ownership -- their own machine resolves the physics they are watching, with no
	lag -- and client/world/CarDriver steps it on that machine from then on. The first cut stepped
	every car on the server whoever owned it: the spring forces it wrote reached the driver's machine
	late, and late springs bucked a car onto its roof with nobody touching the controls.

	None of this is an authority the server gives away: whoever owns an assembly's physics can already
	move it anywhere. The server keeps what matters -- who may sit where, what a car costs, whose it
	is, where it is spawned.

	WHAT A STEP DOES:
	  * a spring per wheel: F = k*x - c*v along the car's own up, from a ray cast down from its
	    mount, capped at MAX_SPRING_SHARE times its share of the weight -- a bump stop;
	  * the drive: a push toward throttle times top speed, eased near the top;
	  * the grip: a damper against sliding sideways;
	  * the steering: a yaw rate from the bicycle model, calmer at speed;
	  * the settle: a grounded car's pitch and roll eased out, the dampers' work between reads.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local VEHICLES = Config.Vehicles

local CarPhysics = {}

-- The tag every drivable car carries, so a client can find the cars it animates and drives.
CarPhysics.Tag = "AgesCar"

-- How hard a car resists sliding sideways. Not per-car: every car should feel like it is on the
-- same road, and differences in cornering come from steerDegrees and speed.
-- Safe range: 900-1800.
local LATERAL_GRIP = 1300
-- How firmly steering may change the yaw rate per second: keeps a steering reversal from reading
-- as the car teleporting its spin the other way in one frame.
local YAW_RESPONSIVENESS = 6
-- A spring never pushes harder than this many times its share of the car's weight: a bump stop,
-- so a slow step that finds a spring crushed cannot throw the car in the air.
local MAX_SPRING_SHARE = 3
-- How fast a grounded car's pitch and roll settle, per second.
local TILT_SETTLE = 3
-- Nitro: how much further past its rated top speed a car goes, and how much harder it pushes.
CarPhysics.BoostTop = 1.35
local BOOST_PUSH = 1.8
-- Drifting (the handbrake held): the share of grip the tyres keep, how much more the car yaws
-- for the same steering, how quickly it swings into the slide, and the drag of locked rear wheels.
local DRIFT_GRIP = 0.3
local DRIFT_YAW = 1.5
local DRIFT_RESPONSIVENESS = 9
local DRIFT_DRAG = 0.3
-- The drift assist: past DRIFT_ANGLE sideways the tyres bite back, fully by DRIFT_ANGLE plus
-- DRIFT_CATCH, so a drift holds its angle instead of becoming a spin. Tried without it at full
-- lock and flat out: the car went round and backwards off the road.
local DRIFT_ANGLE = math.rad(35)
local DRIFT_CATCH = math.rad(20)

export type Mount = { attachment: Attachment, force: VectorForce }

export type Rig = {
	model: Model,
	hull: BasePart,
	seat: VehicleSeat,
	mounts: { Mount },
	params: RaycastParams,
	topSpeed: number,
	acceleration: number,
	steerDegrees: number,
	wheelbase: number,
}

local function number(model: Model, name: string, fallback: number): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

--[[
	What a step needs, found on a car world/VehicleChassis built: its hull, seat, spring mounts and
	the numbers it was built with. `rider`, if given, is left out of the springs' rays as well as the
	car itself -- the driver sits inside the car, and a ray must never find their legs.
]]
function CarPhysics.Rig(model: Model, rider: Instance?): Rig?
	local hull = model.PrimaryPart
	local seat = model:FindFirstChild("DriverSeat")
	if hull == nil or seat == nil or not seat:IsA("VehicleSeat") then
		return nil
	end
	local mounts: { Mount } = {}
	for _, child in hull:GetChildren() do
		if child:IsA("Attachment") and child.Name == "SuspensionMount" then
			local force = child:FindFirstChildOfClass("VectorForce")
			if force then
				table.insert(mounts, { attachment = child, force = force })
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if rider then { model, rider } else { model }
	params.IgnoreWater = true
	return {
		model = model,
		hull = hull,
		seat = seat,
		mounts = mounts,
		params = params,
		topSpeed = number(model, "TopSpeed", 80),
		acceleration = number(model, "Acceleration", 10),
		steerDegrees = number(model, "SteerDegrees", 30),
		wheelbase = number(model, "Wheelbase", 10),
	}
end

-- The share of full steering a car gets at `speed`: all of it in a car park, HighSpeedSteerShare of
-- it flat out.
function CarPhysics.SteerScale(speed: number): number
	local share = math.clamp(math.abs(speed) / VEHICLES.SteerTaperStuds, 0, 1)
	return 1 - share * (1 - VEHICLES.HighSpeedSteerShare)
end

-- The velocity of a point fixed to the hull: linear, plus how fast the hull's spin carries it.
local function velocityAt(hull: BasePart, point: Vector3): Vector3
	return hull.AssemblyLinearVelocity + hull.AssemblyAngularVelocity:Cross(point - hull.Position)
end

--[[
	One step: `dt` seconds, the driver's throttle and steer (-1..1 each; zero for a parked car),
	whether nitro is burning, and how far into a drift the car is (0 gripping, 1 handbrake fully
	on -- the driver eases it, so the tyres bite back gradually rather than snapping the car straight).
]]
function CarPhysics.Step(rig: Rig, dt: number, throttle: number, steer: number, boost: boolean?, drift: number?)
	local hull = rig.hull
	if hull.Parent == nil then
		return
	end
	local up = hull.CFrame.UpVector
	local restLength = VEHICLES.SuspensionLength + VEHICLES.WheelRadius
	local limit = MAX_SPRING_SHARE * hull.AssemblyMass * workspace.Gravity / 4
	local grounded = false
	for _, mount in rig.mounts do
		local origin = mount.attachment.WorldPosition
		local result = workspace:Raycast(origin, -up * restLength, rig.params)
		if result then
			grounded = true
			local compression = math.clamp(restLength - (result.Position - origin).Magnitude, 0, restLength)
			local speed = velocityAt(hull, origin):Dot(up)
			-- The damper, capped at what stops this corner's quarter of the car in one step: past
			-- that it overshoots, and a slow frame turns damping into a wobble.
			local reach = hull.AssemblyMass / 4 * math.abs(speed) / math.max(dt, 1 / 240)
			local damping = math.clamp(VEHICLES.SuspensionDamping * speed, -reach, reach)
			local push = math.max(0, VEHICLES.SuspensionStiffness * compression - damping)
			mount.force.Force = up * math.min(push, limit)
		else
			mount.force.Force = Vector3.zero
		end
	end
	if not grounded then
		return
	end

	-- The drive seeks a target speed rather than pushing flat out, so nothing clamps top speed:
	-- the car stops being pushed once it goes as fast as the throttle asks. TopSpeedTaper eases the
	-- push near the top.
	local forward = hull.CFrame.LookVector
	local right = hull.CFrame.RightVector
	local velocity = hull.AssemblyLinearVelocity
	local speed = velocity:Dot(forward)
	local slipAngle = math.atan2(math.abs(velocity:Dot(right)), math.max(math.abs(velocity:Dot(forward)), 1))
	local catch = math.clamp((slipAngle - DRIFT_ANGLE) / DRIFT_CATCH, 0, 1)
	local sliding = math.clamp(drift or 0, 0, 1) * (1 - catch)
	local top = rig.topSpeed * (if boost then CarPhysics.BoostTop else 1)
	local accel = rig.acceleration * (if boost then BOOST_PUSH else 1)
	if boost then
		throttle = 1
	end
	local total = Vector3.zero
	if throttle ~= 0 then
		local share = math.clamp(math.abs(speed) / top, 0, 1)
		local headroom = 1 - share * (1 - VEHICLES.TopSpeedTaper)
		local push = math.clamp((throttle * top - speed) * accel * 40, -accel * 4000, accel * 4000) * headroom
		total += forward * push
	end
	local grip = LATERAL_GRIP * (1 - sliding * (1 - DRIFT_GRIP))
	total += -right * velocity:Dot(right) * grip
	total += -forward * speed * DRIFT_DRAG * sliding * hull.AssemblyMass
	hull:ApplyImpulse(total * dt)

	-- The bicycle model: a steered front wheel traces a circle of radius wheelbase / tan(angle), so
	-- the yaw rate is speed / radius -- which is zero standing still, as a real car's is. Positive
	-- yaw turns the nose toward -X; steering right (+1) must turn it toward +X.
	local angle = math.rad(steer * rig.steerDegrees)
	local swing = 1 + sliding * (DRIFT_YAW - 1)
	local target = -(speed / rig.wheelbase) * math.tan(angle) * CarPhysics.SteerScale(speed) * swing
	local cap = math.rad(rig.steerDegrees) * 1.6 * swing
	target = math.clamp(target, -cap, cap)
	local current = hull.AssemblyAngularVelocity
	local responsiveness = YAW_RESPONSIVENESS + sliding * (DRIFT_RESPONSIVENESS - YAW_RESPONSIVENESS)
	local yaw = current.Y + (target - current.Y) * math.clamp(responsiveness * dt, 0, 1)
	local settle = math.exp(-TILT_SETTLE * dt)
	hull.AssemblyAngularVelocity = Vector3.new(current.X * settle, yaw, current.Z * settle)
end

return CarPhysics
