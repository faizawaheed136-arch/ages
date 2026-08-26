--!strict
-- Builds a car and drives it. Raycast suspension rather than a physical wheel
-- collider, on purpose: a HingeConstraint wheel is a cylinder that can catch on a
-- kerb, and this city is built out of kerbs -- MAP_PLAN.md's whole record of the
-- street grid is nothing but edges a wheel could snag on. A raycast wheel never
-- touches the road at all. It measures the distance to it, once per corner every
-- tick -- see Config.Vehicles.TickSeconds -- and pushes back with a spring. There
-- is nothing for a pavement lip to catch, because there is no wheel there to
-- catch it.
--
-- The suspension is the textbook damped spring, one per corner:
--
--   F = k*x - c*v
--
-- k is Config.Vehicles.SuspensionStiffness, x is how far the spring is compressed
-- from its rest length, c is SuspensionDamping, and v is how fast that corner is
-- already moving along the spring's own axis -- without the second term every
-- landing bounces forever. Applied through a VectorForce at an Attachment, which
-- is the one force primitive that does not care what the part underneath it is
-- built from: swap the placeholder body for a real mesh later and every force in
-- this file still lands in the same four places.
--
-- Steering is not a turned wheel. It is a yaw rate written straight onto the
-- chassis's own AssemblyAngularVelocity, scaled by how fast the car is already
-- going -- a stationary car does not spin on the spot, because a stationary real
-- car cannot either. That is a simplification and it is a deliberate one: a wheel
-- whose raycast direction turned with the steering would need its own friction
-- model to feel like anything, and the arcade version -- Jailbreak's version, and
-- every casual Roblox driving game's version -- reads as correct to a player at
-- street speed and is a fraction of the code.
--
-- **Network ownership is Roblox's own, handed off explicitly.** The moment a
-- player sits in the VehicleSeat, this file gives them SetNetworkOwner on the
-- chassis, so the physics they are watching are the physics their own machine is
-- resolving -- zero-latency, the same as their own character. The moment they get
-- out, ownership goes back to SetNetworkOwnershipAuto(). Left to Roblox's default
-- assignment this breaks the moment a passenger seat exists and somebody sits in
-- it before the driver does -- the passenger keeps ownership and the driver's
-- input visibly lags -- which is why the explicit handoff is not optional. There
-- is no passenger seat in this file for exactly that reason: one seat, one owner,
-- nothing to get backwards.
--
-- What still drives every tick is a server Script, not the client. The client
-- owns the *physics resolution* once they are seated; the *decision* of how much
-- force that resolves into is read off VehicleSeat.Throttle/.Steer on the server
-- every tick, which Roblox already replicates driver-to-server as part of what a
-- VehicleSeat is. That is the whole of why this needs no Server Authority place
-- migration: a car, unlike a shared ball, only ever has one owner, and Roblox's
-- ordinary distributed physics already resolves that correctly once told who it
-- is.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type VehicleKind = Types.VehicleKind

local VEHICLES = Config.Vehicles

local VehicleChassis = {}

-- Cosmetic geometry, kept out of Config for the reason every other placeholder
-- model in this tree gives: the height of a wheel arch is not a number anyone
-- balances a life simulator with.
local WHEEL_THICKNESS = 0.9
local CAB_HEIGHT_SHARE = 0.55
local CAB_LENGTH_SHARE = 0.55
local CAB_INSET_STUDS = 0.5
local BODY_MATERIAL = Enum.Material.SmoothPlastic
local WHEEL_COLOR = Color3.fromRGB(24, 24, 26)
local WHEEL_MATERIAL = Enum.Material.Plastic
local GLASS_COLOR = Color3.fromRGB(150, 190, 210)
local GLASS_MATERIAL = Enum.Material.Glass

-- How far in from the chassis's own edges the suspension attachments sit. Not
-- flush with the corners -- a wheel is not a knife-edge, it has its own width --
-- and not so far in that a wide, low car loses the roll stability that comes from
-- spreading its four springs as wide as the body actually is.
local WHEEL_INSET_X = 0.35
local WHEEL_INSET_Z = 0.9

-- How hard the chassis resists sliding sideways. Not a suspension number and not
-- per-car: every car on the lot should feel like it is on the same road, and
-- differences in cornering come from steerDegrees and speed, not from one car
-- mysteriously gripping better in a straight line.
-- Safe range: 900-1800.
local LATERAL_GRIP = 1300

-- How firmly steering input is allowed to change yaw rate per second. A hard
-- `AssemblyAngularVelocity` write is instant and correct for the common case;
-- this is what keeps a steering *reversal* from reading as the car teleporting
-- its spin the other way in one frame.
local YAW_RESPONSIVENESS = 6

-- What one wheel corner needs to do its job: where it sits, and what it last
-- measured, so the model can be turned to match what the physics decided.
type Corner = {
	attachment: Attachment,
	-- Held directly rather than found again each tick with
	-- FindFirstChildOfClass -- there is exactly one per attachment and it never
	-- changes, so the lookup would only ever be paying to confirm the same
	-- answer sixty times a second.
	force: VectorForce,
	wheelModel: BasePart,
	localOffset: Vector3,
}

export type Chassis = {
	model: Model,
	seat: VehicleSeat,
	kind: VehicleKind,
	-- Stops the drive loop and disconnects everything. Safe to call once; a
	-- second call is a no-op, which matters because both a despawn and the
	-- model being destroyed out from under the loop reach here.
	destroy: () -> (),
}

-- One wheel, as a squat cylinder. A cylinder's own length runs along local X, so
-- it is rotated ninety degrees to stand it on its side facing outward -- the same
-- correction ChoiceMarkers makes for the discs it paints on the floor.
local function buildWheel(parent: Instance, radius: number): BasePart
	local wheel = Instance.new("Part")
	wheel.Name = "Wheel"
	wheel.Shape = Enum.PartType.Cylinder
	wheel.Size = Vector3.new(WHEEL_THICKNESS, radius * 2, radius * 2)
	wheel.Color = WHEEL_COLOR
	wheel.Material = WHEEL_MATERIAL
	wheel.Anchored = false
	wheel.CanCollide = false
	wheel.CanQuery = false
	wheel.CanTouch = false
	wheel.Massless = true
	wheel.Parent = parent
	return wheel
end

-- The body: a block for the chassis, a smaller block set back and up for the
-- cab, and a glass band between them. Three primitives is the greeble floor
-- Props.luau and PropModels already hold everywhere else in this game -- a car
-- that was a single coloured box would read as a crate with wheels.
local function buildBody(kind: VehicleKind, cframe: CFrame): Model
	local model = Instance.new("Model")
	model.Name = `Vehicle_{kind.id}`

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = kind.size
	chassis.Color = kind.color
	chassis.Material = BODY_MATERIAL
	chassis.CFrame = cframe
	chassis.Anchored = false
	chassis.CanCollide = true
	chassis.CustomPhysicalProperties = PhysicalProperties.new(
		-- Density chosen so the body sits at a mass the suspension constants in
		-- Config.Vehicles were tuned against -- roughly 1.4 tonnes for a
		-- mid-sized car's worth of studs. A real mesh dropped in later inherits
		-- whatever density it ships with; this only has to be right for the
		-- placeholder.
		0.7,
		0.3,
		0.5
	)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local cabSize = Vector3.new(
		kind.size.X - CAB_INSET_STUDS * 2,
		kind.size.Y * CAB_HEIGHT_SHARE,
		kind.size.Z * CAB_LENGTH_SHARE
	)
	local cab = Instance.new("Part")
	cab.Name = "Cab"
	cab.Size = cabSize
	cab.Color = kind.color
	cab.Material = BODY_MATERIAL
	-- Set back from centre toward the rear third, which is what makes a boxy
	-- placeholder read as "car" rather than "van" from a passing glance -- the
	-- cab is not centred over the wheelbase. Positive local Z is toward the
	-- rear: CFrame.LookVector -- the direction the chassis is built facing,
	-- see driveForce in this same file -- points along local -Z, so "back" is
	-- the other way.
	cab.CFrame = cframe * CFrame.new(0, kind.size.Y / 2 + cabSize.Y / 2 - 0.1, kind.size.Z * 0.08)
	cab.Anchored = false
	cab.CanCollide = true
	cab.Massless = true
	cab.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = chassis
	weld.Part1 = cab
	weld.Parent = cab

	local glass = Instance.new("Part")
	glass.Name = "Windshield"
	glass.Size = Vector3.new(cabSize.X - 0.4, cabSize.Y * 0.7, 0.2)
	glass.Color = GLASS_COLOR
	glass.Material = GLASS_MATERIAL
	glass.Transparency = 0.35
	-- The cab's front edge, which is its local -Z face -- same direction as the
	-- chassis's own front, since the cab carries no rotation of its own.
	glass.CFrame = cab.CFrame * CFrame.new(0, cabSize.Y * 0.12, -cabSize.Z / 2 + 0.05)
	glass.Anchored = false
	glass.CanCollide = false
	glass.CanQuery = false
	glass.Massless = true
	glass.Parent = model

	local glassWeld = Instance.new("WeldConstraint")
	glassWeld.Part0 = chassis
	glassWeld.Part1 = glass
	glassWeld.Parent = glass

	-- Accent stripe along the flank, which is the one place the second colour
	-- earns its keep -- see the note on Props.luau's accentColor for why a
	-- placeholder gets two colours and not one.
	local stripe = Instance.new("Part")
	stripe.Name = "Stripe"
	stripe.Size = Vector3.new(kind.size.X + 0.05, 0.18, kind.size.Z * 0.85)
	stripe.Color = kind.accentColor
	stripe.Material = BODY_MATERIAL
	stripe.CFrame = cframe * CFrame.new(0, -kind.size.Y * 0.05, 0)
	stripe.Anchored = false
	stripe.CanCollide = false
	stripe.CanQuery = false
	stripe.Massless = true
	stripe.Parent = model

	local stripeWeld = Instance.new("WeldConstraint")
	stripeWeld.Part0 = chassis
	stripeWeld.Part1 = stripe
	stripeWeld.Parent = stripe

	return model
end

local function buildSeat(kind: VehicleKind, chassis: BasePart): VehicleSeat
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(math.min(kind.size.X - 1, 3.2), 1, 2.2)
	-- Centred on X, which the research this file is built from names as the
	-- single most common reason a Roblox car spins out the instant it turns --
	-- an off-centre seat is an off-centre CFrame the whole steering model is
	-- read from, and this chassis reads its own yaw off the seat's own CFrame
	-- nowhere, so the centring here is about the model looking honest rather
	-- than about the physics, but it is cheap to get right and worth doing.
	seat.CFrame = chassis.CFrame * CFrame.new(0, kind.size.Y / 2 + 0.5, kind.size.Z * 0.05)
	seat.Anchored = false
	seat.CanCollide = false
	seat.Massless = true
	seat.Transparency = 1
	-- Roblox's own drive numbers are not read here -- see the header on why the
	-- chassis below reads .Throttle/.Steer directly instead of trusting the
	-- seat's built-in HingeConstraint motoring, which assumes physical wheels
	-- this chassis does not have.
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.Parent = chassis.Parent

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = chassis
	weld.Part1 = seat
	weld.Parent = seat

	return seat
end

local function buildCorners(kind: VehicleKind, chassis: BasePart): { Corner }
	local halfX = kind.size.X / 2 - WHEEL_INSET_X
	local halfZ = kind.size.Z / 2 - WHEEL_INSET_Z
	local bottom = -kind.size.Y / 2

	-- Labelled front/rear for readability only -- every corner runs the identical
	-- tickCorner below, so nothing here actually branches on which is which.
	-- Negative local Z is the front, matching CFrame.LookVector; see driveForce.
	local offsets = {
		Vector3.new(-halfX, bottom, -halfZ), -- front left
		Vector3.new(halfX, bottom, -halfZ), -- front right
		Vector3.new(-halfX, bottom, halfZ), -- rear left
		Vector3.new(halfX, bottom, halfZ), -- rear right
	}

	local corners: { Corner } = {}
	for _, offset in offsets do
		local attachment = Instance.new("Attachment")
		attachment.Name = "SuspensionMount"
		attachment.Position = offset
		attachment.Parent = chassis

		local force = Instance.new("VectorForce")
		force.Name = "SuspensionForce"
		force.Attachment0 = attachment
		force.RelativeTo = Enum.ActuatorRelativeTo.World
		force.Force = Vector3.zero
		force.Parent = attachment

		local wheel = buildWheel(chassis.Parent :: Instance, VEHICLES.WheelRadius)
		wheel.CFrame = chassis.CFrame * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90))

		table.insert(corners, { attachment = attachment, force = force, wheelModel = wheel, localOffset = offset })
	end

	return corners
end

-- The velocity of a point fixed to the chassis, in world space -- linear plus
-- however fast that point is being carried around by the body's own spin.
-- Needed for the damping term: a spring that only read the chassis's linear
-- velocity would under-damp every corner during a turn, because the outside
-- corners are moving faster than the centre of mass is.
local function velocityAt(chassis: BasePart, worldPoint: Vector3): Vector3
	local toPoint = worldPoint - chassis.Position
	return chassis.AssemblyLinearVelocity + chassis.AssemblyAngularVelocity:Cross(toPoint)
end

-- One tick of suspension for one corner. Returns whether this wheel is touching,
-- which the drive step needs -- force should not be pretending an airborne car
-- still has grip.
local function tickCorner(chassis: BasePart, corner: Corner, ignore: { Instance }): boolean
	local attachment = corner.attachment
	local force = corner.force
	local worldPos = attachment.WorldPosition
	-- Springs push along the chassis's own up, not world up -- see the header on
	-- why this is deliberate: it is what lets a car lean into a bank on a hill
	-- rather than the suspension fighting the slope on every corner at once.
	local springAxis = chassis.CFrame.UpVector
	local restLength = VEHICLES.SuspensionLength + VEHICLES.WheelRadius

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true

	local result = workspace:Raycast(worldPos, -springAxis * restLength, params)
	if result == nil then
		force.Force = Vector3.zero
		corner.wheelModel.CFrame = CFrame.lookAt(worldPos - springAxis * restLength, worldPos - springAxis * restLength + chassis.CFrame.LookVector)
			* CFrame.Angles(0, 0, math.rad(90))
		return false
	end

	local distance = (result.Position - worldPos).Magnitude
	local compression = math.clamp(restLength - distance, 0, restLength)
	local velocity = velocityAt(chassis, worldPos):Dot(springAxis)

	local magnitude = math.max(0, VEHICLES.SuspensionStiffness * compression - VEHICLES.SuspensionDamping * velocity)
	force.Force = springAxis * magnitude

	local wheelCenter = result.Position + springAxis * VEHICLES.WheelRadius
	corner.wheelModel.CFrame = CFrame.lookAt(wheelCenter, wheelCenter + chassis.CFrame.LookVector) * CFrame.Angles(0, 0, math.rad(90))
	return true
end

-- Longitudinal drive: seeks a target speed rather than applying a flat force, so
-- there is no explicit top-speed clamp anywhere in this file -- the car simply
-- stops being pushed once it is already going as fast as the throttle asks for.
-- TopSpeedTaper narrows how hard that push is allowed to be as the car nears its
-- rated top speed, which is what stops a light tap of throttle at speed reading
-- as a full-force shove.
local function driveForce(chassis: BasePart, kind: VehicleKind, throttle: number): Vector3
	if throttle == 0 then
		return Vector3.zero
	end
	-- CFrame.LookVector is Roblox's own convention for "the way this part faces" --
	-- the local -Z direction -- and the chassis is built facing that way on purpose
	-- (VehicleService spawns it with CFrame.lookAt pointed at the dealership), so
	-- this is forward with no correction needed. Taking the negative here once read
	-- as "obviously forward is the other way" and was wrong -- the car drove
	-- backward relative to its own windshield the first time this ran.
	local forward = chassis.CFrame.LookVector
	local currentSpeed = chassis.AssemblyLinearVelocity:Dot(forward)
	local targetSpeed = throttle * kind.topSpeedStuds
	local speedShare = math.clamp(math.abs(currentSpeed) / kind.topSpeedStuds, 0, 1)
	local headroom = 1 - speedShare * (1 - VEHICLES.TopSpeedTaper)
	local error_ = targetSpeed - currentSpeed
	local magnitude = math.clamp(error_ * kind.acceleration * 40, -kind.acceleration * 4000, kind.acceleration * 4000) * headroom
	return forward * magnitude
end

-- Lateral grip: a plain damper against sideways velocity, so the car corners
-- rather than slides. Cheap and it is the one liberty this file takes with the
-- otherwise-honest suspension model -- a raycast wheel has no physical contact
-- patch to generate real cornering friction from, so this stands in for one.
local function gripForce(chassis: BasePart): Vector3
	local right = chassis.CFrame.RightVector
	local lateralSpeed = chassis.AssemblyLinearVelocity:Dot(right)
	return -right * lateralSpeed * LATERAL_GRIP
end

-- Steering, written straight onto the yaw rate rather than built from a torque.
-- See the header for why direct yaw is used at all; the *shape* of it here is a
-- bicycle model, the standard arcade-racing approximation: a car turning on a
-- steered front wheel traces a circle of radius `wheelbase / tan(steerAngle)`,
-- so its yaw rate is `speed / radius`. That formula is what actually gives "a
-- stationary car does not spin on the spot" for free -- it falls out of speed
-- being the numerator, not a special case bolted on -- and it cannot blow up
-- near zero speed the way dividing *by* speed would.
--
-- HighSpeedSteerShare/SteerTaperStuds is then a second, independent scale on
-- top of the honest bicycle number: a real bicycle model gets twitchier at
-- speed, not calmer, and letting that through untouched is exactly the spin-out
-- this project's own numbers are named to prevent.
local function tickSteer(chassis: BasePart, kind: VehicleKind, steer: number, elapsed: number)
	-- See driveForce above for why this is the plain LookVector, un-negated.
	local forward = chassis.CFrame.LookVector
	local speed = chassis.AssemblyLinearVelocity:Dot(forward)
	local wheelbase = math.max(kind.size.Z * 0.6, 1)

	local speedShare = math.clamp(math.abs(speed) / VEHICLES.SteerTaperStuds, 0, 1)
	local highSpeedScale = 1 - speedShare * (1 - VEHICLES.HighSpeedSteerShare)

	local steerAngle = math.rad(steer * kind.steerDegrees)
	local targetYaw = (speed / wheelbase) * math.tan(steerAngle) * highSpeedScale
	targetYaw = math.clamp(targetYaw, -math.rad(kind.steerDegrees) * 1.6, math.rad(kind.steerDegrees) * 1.6)

	local current = chassis.AssemblyAngularVelocity
	local nextYaw = current.Y + (targetYaw - current.Y) * math.clamp(YAW_RESPONSIVENESS * elapsed, 0, 1)
	chassis.AssemblyAngularVelocity = Vector3.new(current.X, nextYaw, current.Z)
end

-- Builds a car standing at `cframe`, with nothing driving it yet -- call `Start`
-- to bring the chassis to life. Split from Start so a caller can pose the model,
-- read its PrimaryPart, or decide not to start it at all (a showroom car parked
-- for looks, one day) without paying for a running loop.
function VehicleChassis.Build(kind: VehicleKind, cframe: CFrame): Chassis
	local model = buildBody(kind, cframe)
	local chassis = model.PrimaryPart :: BasePart
	local seat = buildSeat(kind, chassis)
	local corners = buildCorners(kind, chassis)

	local running = true
	local occupantConnection: RBXScriptConnection? = nil

	local function stop()
		if not running then
			return
		end
		running = false
		if occupantConnection ~= nil then
			occupantConnection:Disconnect()
			occupantConnection = nil
		end
	end

	-- Computed once rather than rebuilt every tick -- the one thing a suspension
	-- raycast must never hit is the car's own body, and which model that is
	-- never changes for the life of this chassis.
	local ignore: { Instance } = { model }

	task.spawn(function()
		while running and model.Parent ~= nil do
			local elapsed = task.wait(VEHICLES.TickSeconds)
			if not running or model.Parent == nil or chassis.Parent == nil then
				break
			end

			local anyGrounded = false
			for _, corner in corners do
				if tickCorner(chassis, corner, ignore) then
					anyGrounded = true
				end
			end

			local throttle = seat.Throttle
			local steer = seat.Steer

			local total = Vector3.zero
			if anyGrounded then
				total += driveForce(chassis, kind, throttle)
				total += gripForce(chassis)
				tickSteer(chassis, kind, steer, elapsed)
			end

			if total.Magnitude > 0 then
				chassis:ApplyImpulse(total * elapsed)
			end
		end
	end)

	occupantConnection = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		local player = if occupant ~= nil then Players:GetPlayerFromCharacter(occupant.Parent) else nil
		if player ~= nil then
			-- The explicit handoff the header argues for. A car has exactly one
			-- seat, so there is no passenger who could have claimed ownership
			-- first -- but setting it explicitly rather than trusting Roblox's
			-- default assignment costs one line and removes the question.
			chassis:SetNetworkOwner(player)
		else
			chassis:SetNetworkOwnershipAuto()
		end
	end)

	return {
		model = model,
		seat = seat,
		kind = kind,
		destroy = function()
			stop()
			if model.Parent ~= nil then
				model:Destroy()
			end
		end,
	}
end

-- Studs per second, read off the seat's own chassis. For a speedometer HUD --
-- see client/ui/VehicleUI.luau -- so the number on screen and the number the
-- drive force is actually seeking can never disagree.
function VehicleChassis.SpeedOf(chassisInstance: BasePart): number
	return chassisInstance.AssemblyLinearVelocity.Magnitude
end

return VehicleChassis
