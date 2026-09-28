--!strict
-- Builds a car and makes it drivable. The car itself -- paint, glass, lights, wheels, seats -- is
-- drawn by shared/CarBody, the same drawing the shop and the showroom floor use; how it drives is
-- shared/CarPhysics, stepped here while the car is parked (the server owns it) and by
-- client/world/CarDriver while somebody drives it (their machine owns it). This file gives it a
-- seat, springs, a way in and out, and its lamps.
--
-- Raycast suspension rather than a physical wheel collider, on purpose: a HingeConstraint wheel is
-- a cylinder that can catch on a kerb, and this city is built out of kerbs -- MAP_PLAN.md's whole
-- record of the street grid is nothing but edges a wheel could snag on. A raycast wheel never
-- touches the road at all. It measures the distance to it, once per corner every tick -- see
-- Config.Vehicles.TickSeconds -- and pushes back with a spring. There is nothing for a pavement lip
-- to catch, because there is no wheel there to catch it. The hull rides clear of the kerbs too:
-- everything below it -- sills, bumpers -- is paint that does not collide (CarBody's HULL_BOTTOM).
--
-- The suspension is the textbook damped spring, one per wheel:
--
--   F = k*x - c*v
--
-- k is Config.Vehicles.SuspensionStiffness, x is how far the spring is compressed from its rest
-- length, c is SuspensionDamping, and v is how fast that wheel's mount is already moving along the
-- spring's own axis -- without the second term every landing bounces forever. Applied through a
-- VectorForce at an Attachment at each axle, which is the one force primitive that does not care
-- what the part underneath it is built from.
--
-- The wheels you see are the springs made visible: client/world/CarWheels puts each wheel where its
-- ray meets the road, turns the front pair with the steering and spins them with the road, on every
-- client, every frame. They ride on Welds whose C0 moves, part of the car's own assembly, weighing
-- nothing.
--
-- Steering is not a turned wheel. It is a yaw rate written straight onto the chassis's own
-- AssemblyAngularVelocity, scaled by how fast the car is already going -- a stationary car does not
-- spin on the spot, because a stationary real car cannot either. That is a simplification and it is
-- a deliberate one: a wheel whose raycast direction turned with the steering would need its own
-- friction model to feel like anything, and the arcade version -- Jailbreak's version, and every
-- casual Roblox driving game's version -- reads as correct to a player at street speed and is a
-- fraction of the code.
--
-- **Network ownership is Roblox's own, handed off explicitly.** The moment a player sits in the
-- VehicleSeat, this file gives them SetNetworkOwner on the chassis, so the physics they are watching
-- are the physics their own machine is resolving -- zero-latency, the same as their own character.
-- The moment they get out, ownership comes back to the server, which steps a car nobody is in.
-- Not SetNetworkOwnershipAuto(): that hands an empty car to whichever client is nearest -- often the
-- one who just climbed out -- where nothing steps it, and it rolled away on the last forces their
-- machine had set. There is no passenger seat for the same reason: one seat, one owner.
--
-- The step runs where the physics runs. It used to run on the server for every car, driven or
-- not: the forces it wrote reached the driver's machine late, and late springs bucked a car onto
-- its roof. See shared/CarPhysics.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarBody = require(ReplicatedStorage:WaitForChild("CarBody"))
local CarPhysics = require(ReplicatedStorage:WaitForChild("CarPhysics"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type VehicleKind = Types.VehicleKind
type Layout = CarBody.Layout

local VEHICLES = Config.Vehicles

local VehicleChassis = {}

-- Below this many studs a second a car counts as stopped, for the brake and reversing lamps.
local CREEP_STUDS = 1

-- The driver sits inside the car's colliders, the way a driver sits inside a car -- so while seated,
-- and on the way in and out, their character is in a collision group that passes through car
-- bodies. Without it, sitting down put the character inside the hull and the physics threw the two
-- apart.
local DRIVER_GROUP = "VehicleDrivers"
local BODY_GROUP = "VehicleBodies"
-- How far from the driver's door a player is set down on getting out.
local EXIT_STUDS = 2.5
-- How close a player must be to get in.
local ENTER_STUDS = 12

-- The headlamps' beam.
local HEADLIGHT_BRIGHTNESS = 2.2
local HEADLIGHT_RANGE = 52
local HEADLIGHT_ANGLE = 64

export type Chassis = {
	model: Model,
	seat: VehicleSeat,
	kind: VehicleKind,
	-- Puts a humanoid at the wheel, the right way: out of the car body's collisions first.
	seatDriver: (humanoid: Humanoid) -> (),
	-- Stops the parked-car loop and disconnects everything. Safe to call once; a second call is a
	-- no-op, which matters because both a despawn and the model being destroyed out from under the
	-- loop reach here.
	destroy: () -> (),
}

local groupsReady = false
local function ensureGroups()
	if groupsReady then
		return
	end
	groupsReady = true
	local ok, err = pcall(function()
		PhysicsService:RegisterCollisionGroup(DRIVER_GROUP)
		PhysicsService:RegisterCollisionGroup(BODY_GROUP)
		PhysicsService:CollisionGroupSetCollidable(DRIVER_GROUP, BODY_GROUP, false)
	end)
	if not ok then
		warn(`[AGES vehicles] collision groups: {err}`)
	end
end

local function setGroup(character: Instance, group: string)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

local function buildSeat(layout: Layout, hull: BasePart): VehicleSeat
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(1.6, 1, 2)
	-- On the driver's side, over the drawn seat. The seat has no mass, so where it sits is about
	-- what the player sees -- sat behind the wheel, not in the middle of the car.
	seat.CFrame = hull.CFrame * CFrame.new(layout.seat)
	seat.Anchored = false
	seat.CanCollide = false
	seat.Massless = true
	seat.Transparency = 1
	-- Roblox's own drive numbers are not read: CarPhysics reads .Throttle/.Steer itself instead of
	-- trusting the seat's built-in HingeConstraint motoring, which assumes physical wheels.
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.Parent = hull.Parent

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hull
	weld.Part1 = seat
	weld.Parent = seat
	return seat
end

-- A spring mount at each wheel, and the force it pushes with; and on each wheel's roots what
-- client/world/CarWheels needs to put the wheel where its spring says.
local function rig(built: CarBody.Built, welds: { Weld })
	local layout = built.layout
	local hull = built.hull
	for index, wheel in built.wheels do
		local attachment = Instance.new("Attachment")
		attachment.Name = "SuspensionMount"
		attachment.Position = Vector3.new(wheel.rest.X, layout.mountY, wheel.rest.Z)
		attachment.Parent = hull

		local force = Instance.new("VectorForce")
		force.Name = "SuspensionForce"
		force.Attachment0 = attachment
		force.RelativeTo = Enum.ActuatorRelativeTo.World
		force.Force = Vector3.zero
		force.Parent = attachment

		local centre = CFrame.new(wheel.rest) * (if wheel.side < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new())
		for slot, root in { wheel.spin, wheel.knuckle } do
			local weld = welds[index * 2 - 2 + slot]
			root:SetAttribute("WheelRest", wheel.rest)
			root:SetAttribute("WheelSide", wheel.side)
			root:SetAttribute("WheelFront", wheel.front)
			root:SetAttribute("WheelSpins", slot == 1)
			root:SetAttribute("WheelOffset", centre:Inverse() * weld.C0)
		end
	end
end

-- Builds a car standing with its hull's centre at `cframe`, painted `paint` if given, wearing
-- `look`'s rims and underglow. It settles on its springs once the caller parents the model.
function VehicleChassis.Build(kind: VehicleKind, cframe: CFrame, paint: Color3?, look: CarBody.Look?): Chassis
	ensureGroups()
	local built = CarBody.Build(kind, cframe, paint, look)
	local model = built.model
	local layout = built.layout
	local chassis = built.hull
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.CanCollide then
			part.CollisionGroup = BODY_GROUP
		end
	end
	local welds = CarBody.Weld(built)
	local seat = buildSeat(layout, chassis)
	rig(built, welds)
	model:SetAttribute("TopSpeed", kind.topSpeedStuds)
	model:SetAttribute("Acceleration", kind.acceleration)
	model:SetAttribute("SteerDegrees", kind.steerDegrees)
	model:SetAttribute("Wheelbase", math.max(layout.axleRear - layout.axleFront, 1))
	model:SetAttribute("MountY", layout.mountY)
	CollectionService:AddTag(model, CarPhysics.Tag)

	local beams: { SpotLight } = {}
	for _, aim in built.headlights do
		local beam = Instance.new("SpotLight")
		beam.Face = Enum.NormalId.Front
		beam.Brightness = HEADLIGHT_BRIGHTNESS
		beam.Range = HEADLIGHT_RANGE
		beam.Angle = HEADLIGHT_ANGLE
		beam.Color = Color3.fromRGB(255, 246, 228)
		beam.Shadows = true
		beam.Enabled = false
		beam.Parent = aim
		table.insert(beams, beam)
	end

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

	local physics = CarPhysics.Rig(model)
	local braking, reversing = false, false

	-- Deferred, not spawned: `model` has no parent until the caller gives it one, and a loop that
	-- started first would find none and exit on the spot.
	task.defer(function()
		-- The server's from the start: left to Auto, a new car belongs to whoever stands nearest, and
		-- nothing steps it there until somebody sits in it.
		if model:IsDescendantOf(workspace) and seat.Occupant == nil then
			chassis:SetNetworkOwner(nil)
		end
		while running and model.Parent ~= nil do
			local elapsed = task.wait(VEHICLES.TickSeconds)
			if not running or model.Parent == nil or chassis.Parent == nil then
				break
			end
			-- Parked, the server owns the car and steps it; driven, the driver's machine does.
			if seat.Occupant == nil and physics then
				CarPhysics.Step(physics, elapsed, 0, 0)
			end

			-- The lamps, from what the driver's seat and the car's motion replicate here: brake lights
			-- while the throttle fights the way the car is going, reversing lights while it goes
			-- backwards on purpose. Only written when they change.
			local throttle = seat.Throttle
			local speed = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
			local nowBraking = throttle ~= 0 and math.abs(speed) > CREEP_STUDS and (throttle > 0) ~= (speed > 0)
			local nowReversing = throttle < 0 and speed < -CREEP_STUDS
			if nowBraking ~= braking then
				braking = nowBraking
				for _, lamp in built.brakeLights do
					lamp.Color = if braking then CarBody.BrakeColor else CarBody.TailColor
				end
			end
			if nowReversing ~= reversing then
				reversing = nowReversing
				for _, lamp in built.reverseLights do
					lamp.Material = if reversing then Enum.Material.Neon else Enum.Material.SmoothPlastic
				end
			end
		end
	end)

	local function seatDriver(humanoid: Humanoid)
		local character = humanoid.Parent
		if character == nil or seat.Occupant ~= nil or humanoid.Health <= 0 then
			return
		end
		setGroup(character, DRIVER_GROUP)
		seat:Sit(humanoid)
	end

	-- Getting in: the seat is inside the car, out of reach of a touch, so a prompt on the car.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Drive"
	prompt.ActionText = "Drive"
	prompt.ObjectText = kind.name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = ENTER_STUDS
	prompt.RequiresLineOfSight = false
	prompt.Parent = chassis
	prompt.Triggered:Connect(function(player: Player)
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			seatDriver(humanoid)
		end
	end)

	local driver: Humanoid? = nil
	occupantConnection = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		local player = if occupant ~= nil then Players:GetPlayerFromCharacter(occupant.Parent) else nil
		if player ~= nil then
			-- The driver's machine resolves the physics they are watching, zero-latency, and steps it:
			-- the explicit handoff the header argues for.
			chassis:SetNetworkOwner(player)
		else
			chassis:SetNetworkOwner(nil)
		end
		for _, beam in beams do
			beam.Enabled = occupant ~= nil
		end
		prompt.Enabled = occupant == nil
		if occupant ~= nil then
			-- Seated by a touch or anything else: still out of the body's collisions.
			driver = occupant
			local character = occupant.Parent
			if character then
				setGroup(character, DRIVER_GROUP)
			end
		else
			-- Getting out: set down beside the driver's door, then solid again.
			local leaving = driver
			driver = nil
			local character = if leaving then leaving.Parent else nil
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if character and root and root:IsA("BasePart") and chassis.Parent ~= nil then
				root.CFrame = chassis.CFrame * CFrame.new(-(layout.width / 2 + EXIT_STUDS), 1.5, layout.seat.Z)
			end
			if character then
				task.delay(0.5, function()
					local now = seat.Occupant
					if now == nil or now.Parent ~= character then
						setGroup(character, "Default")
					end
				end)
			end
		end
	end)

	return {
		model = model,
		seat = seat,
		kind = kind,
		seatDriver = seatDriver,
		destroy = function()
			stop()
			if model.Parent ~= nil then
				model:Destroy()
			end
		end,
	}
end

--[[
	A car that is only looked at: the same body Build lays, on its wheels at rest, everything
	anchored -- no seat, no suspension, no drive loop. For a dealership floor, where a car that looks
	different from the one you drive away would be the showroom lying.

	`ground` is a CFrame on the floor the car stands on, turned the way its nose should point.
]]
function VehicleChassis.BuildDisplay(kind: VehicleKind, ground: CFrame, paint: Color3?): Model
	local built = CarBody.Build(kind, CarBody.RestOn(kind, ground), paint)
	CarBody.Anchor(built)
	return built.model
end

-- Studs per second, read off the seat's own chassis. For a speedometer HUD -- see
-- client/ui/VehicleUI.luau -- so the number on screen and the number the drive force is actually
-- seeking can never disagree.
function VehicleChassis.SpeedOf(chassisInstance: BasePart): number
	return chassisInstance.AssemblyLinearVelocity.Magnitude
end

return VehicleChassis
