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
-- The suspension is a damped spring per wheel, set the way a real car's is -- by the ride frequency
-- it is meant to have and how hard it is damped, from shared/CarSpec -- with an anti-roll bar per
-- axle and a bump stop. Each wheel pushes through a VectorForce at an Attachment at its mount, which
-- is the one force primitive that does not care what the part underneath it is built from, and each
-- tyre pushes on the road through a second one at the contact patch: drive, brakes and cornering
-- force all act there, below the centre of mass, so a car squats, dives and rolls because the forces
-- that do it are there, not because anything animates it. See shared/CarPhysics.
--
-- The wheels you see are the springs made visible: client/world/CarWheels puts each wheel where its
-- ray meets the road, turns the front pair with the steering and spins them with the road, on every
-- client, every frame. They ride on Welds whose C0 moves, part of the car's own assembly, weighing
-- nothing.
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
local CarSpec = require(ReplicatedStorage:WaitForChild("CarSpec"))
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

local function force(parent: Attachment, name: string): VectorForce
	local f = Instance.new("VectorForce")
	f.Name = name
	f.Attachment0 = parent
	f.RelativeTo = Enum.ActuatorRelativeTo.World
	f.Force = Vector3.zero
	f.ApplyAtCenterOfMass = false
	f.Parent = parent
	return f
end

-- Each wheel's spring mount and the force it pushes the body up with; the tyre's contact patch and
-- the force it drives, brakes and corners with; one more force at the centre of mass for the air and
-- the hill; and on each wheel's roots what client/world/CarWheels needs to put the wheel where its
-- spring says.
local function rig(built: CarBody.Built, welds: { Weld })
	local layout = built.layout
	local hull = built.hull
	for index, wheel in built.wheels do
		local mount = Instance.new("Attachment")
		mount.Name = "SuspensionMount"
		mount.Position = Vector3.new(wheel.rest.X, layout.mountY, wheel.rest.Z)
		mount:SetAttribute("WheelIndex", index)
		mount:SetAttribute("Front", wheel.front)
		mount:SetAttribute("Side", wheel.side)
		mount.Parent = hull
		force(mount, "SuspensionForce")

		local patch = Instance.new("Attachment")
		patch.Name = `TyrePatch{index}`
		patch.Position = Vector3.new(wheel.rest.X, wheel.rest.Y - layout.wheelRadius, wheel.rest.Z)
		patch.Parent = hull
		force(patch, "TyreForce")

		local centre = CFrame.new(wheel.rest) * (if wheel.side < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new())
		for slot, root in { wheel.spin, wheel.knuckle } do
			local weld = welds[index * 2 - 2 + slot]
			root:SetAttribute("WheelIndex", index)
			root:SetAttribute("WheelRest", wheel.rest)
			root:SetAttribute("WheelSide", wheel.side)
			root:SetAttribute("WheelFront", wheel.front)
			root:SetAttribute("WheelSpins", slot == 1)
			root:SetAttribute("WheelOffset", centre:Inverse() * weld.C0)
		end
	end
	local body = Instance.new("Attachment")
	body.Name = "BodyMount"
	-- Where the weight is, which for a car with its corner weights set to the spec is not the middle.
	body.Position = Vector3.new(0, 0, (layout :: any).comZ or 0)
	body.Parent = hull
	force(body, "BodyForce")
end

-- The lamps of a car drawn from a model cannot be recoloured -- a texture ignores its colour -- so a
-- brake lamp is one that glows, and throws a little red on the road behind it.
local function lampLight(lamp: BasePart, color: Color3, brightness: number, range: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Enabled = false
	light.Parent = lamp
	return light
end

--[[
	WHAT THE DRIVER CONTROLS BESIDES THE CAR'S MOTION -- the headlights, the turn signals, the horn --
	belongs to the server, because everybody in the world sees and hears it. The driver's client
	(client/world/CarDriver) says what it wants over one RemoteEvent, CarControl, made here if nothing
	has yet. It is not one of Remotes.luau's: this file is used in places that have no such module (the
	dealership sandbox), and a remote the car makes for itself cannot go missing in a place that
	replaces that list. The server takes it only from the player in a car's driver's seat, for that car.
]]
local CONTROL_REMOTE = "CarControl"
local SIGNALS = { [""] = true, left = true, right = true, hazard = true }
local controlReady = false

local function carOf(player: Player): Model?
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local seat = if humanoid then humanoid.SeatPart else nil
	if seat == nil or seat.Name ~= "DriverSeat" then
		return nil
	end
	local model = seat.Parent
	if model and model:IsA("Model") and CollectionService:HasTag(model, CarPhysics.Tag) then
		return model
	end
	return nil
end

local function ensureControls()
	if controlReady then
		return
	end
	controlReady = true
	local remote = ReplicatedStorage:FindFirstChild(CONTROL_REMOTE)
	if remote == nil then
		remote = Instance.new("RemoteEvent")
		remote.Name = CONTROL_REMOTE
		remote.Parent = ReplicatedStorage
	end
	(remote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, action: any, value: any)
		local model = carOf(player)
		if model == nil then
			return
		end
		if action == "lights" and typeof(value) == "boolean" then
			model:SetAttribute("Lights", value)
		elseif action == "signal" and typeof(value) == "string" and SIGNALS[value] then
			model:SetAttribute("Signal", value)
		elseif action == "horn" and typeof(value) == "boolean" then
			model:SetAttribute("Horn", value)
		end
	end)
end

-- The driver's hands on the wheel: each arm raised toward it, the elbow a little bent. An avatar's
-- arms otherwise hang at its sides, which in a car is through the door. The joints are Motor6Ds, or
-- AnimationConstraints in a place that rigs characters that way; either way it is the joint's own
-- frame on the torso side that is turned, which an animation (it moves the joint, not its frame)
-- leaves alone.
local DRIVER_POSE = {
	{ "LeftShoulder", CFrame.Angles(math.rad(78), 0, -math.rad(10)) },
	{ "RightShoulder", CFrame.Angles(math.rad(78), 0, math.rad(10)) },
	{ "LeftElbow", CFrame.Angles(math.rad(-22), 0, 0) },
	{ "RightElbow", CFrame.Angles(math.rad(-22), 0, 0) },
}

local function poseDriver(character: Model?, on: boolean)
	if character == nil then
		return
	end
	for _, entry in DRIVER_POSE do
		local name, turn = entry[1] :: string, entry[2] :: CFrame
		for _, joint in character:GetDescendants() do
			if joint.Name ~= name then
				continue
			end
			local target: Instance? = nil
			local property = "C0"
			if joint:IsA("Motor6D") then
				target = joint
			elseif joint:IsA("AnimationConstraint") and joint.Attachment0 then
				target = joint.Attachment0
				property = "CFrame"
			end
			if target then
				local home = target:GetAttribute("CarPoseHome")
				if on then
					if typeof(home) ~= "CFrame" then
						home = (target :: any)[property]
						target:SetAttribute("CarPoseHome", home)
					end
					(target :: any)[property] = (home :: CFrame) * turn
				elseif typeof(home) == "CFrame" then
					(target :: any)[property] = home
					target:SetAttribute("CarPoseHome", nil)
				end
			end
			break
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
	-- What shared/CarPhysics builds this car's spec from, and what the client reads to draw and hear it.
	model:SetAttribute("SpecId", kind.id)
	model:SetAttribute("TopSpeed", kind.topSpeedStuds)
	model:SetAttribute("Acceleration", kind.acceleration)
	model:SetAttribute("SteerDegrees", kind.steerDegrees)
	model:SetAttribute("Wheelbase", math.max(layout.axleRear - layout.axleFront, 1))
	model:SetAttribute("MountY", layout.mountY)
	model:SetAttribute("SizeX", kind.size.X)
	model:SetAttribute("SizeY", kind.size.Y)
	model:SetAttribute("SizeZ", kind.size.Z)
	model:SetAttribute("Drive", if kind.drivetrain == "FWD" or kind.drivetrain == "RWD" then kind.drivetrain else "AWD")
	model:SetAttribute("WheelRadius", layout.wheelRadius)
	model:SetAttribute("SpringRide", layout.springRide)
	model:SetAttribute("SpringBump", layout.springBump)
	model:SetAttribute("SpringDroop", layout.springDroop)
	local spec = CarSpec.Specs[kind.id]
	model:SetAttribute("Voice", if spec then spec.voice else "road")
	model:SetAttribute("Scale", if spec then spec.scale else 1)
	-- Where a bonnet camera and a cockpit camera sit, hull-local.
	model:SetAttribute("CamCockpit", (layout :: any).camCockpit or (layout.seat + Vector3.new(0, 2.6, -0.4)))
	model:SetAttribute("CamHood", (layout :: any).camHood or Vector3.new(0, layout.hullY * 0.4, -layout.length * 0.3))
	-- The driver's switches: the headlights, the turn signal ("", "left", "right", "hazard"), the horn.
	model:SetAttribute("Lights", false)
	model:SetAttribute("Signal", "")
	model:SetAttribute("Horn", false)
	CollectionService:AddTag(model, CarPhysics.Tag)
	ensureControls()

	local beams: { SpotLight } = {}
	for _, aim in built.headlights do
		local beam = Instance.new("SpotLight")
		beam.Face = Enum.NormalId.Front
		beam.Brightness = HEADLIGHT_BRIGHTNESS
		beam.Range = HEADLIGHT_RANGE
		beam.Angle = HEADLIGHT_ANGLE
		beam.Color = Color3.fromRGB(255, 246, 228)
		-- A modelled car's lamps sit inside the shell of its wings; a shadow-casting beam is stopped by it.
		beam.Shadows = not built.mesh
		beam.Enabled = false
		beam.Parent = aim
		table.insert(beams, beam)
	end

	-- What each headlamp lens is made of off, to go back to it.
	local lenses: { [BasePart]: Enum.Material } = {}
	for _, lens in built.lenses or {} do
		lenses[lens] = lens.Material
	end
	-- The headlights are lit when the driver has switched them on, and somebody is driving.
	local function applyLights()
		local lit = seat.Occupant ~= nil and model:GetAttribute("Lights") == true
		for _, beam in beams do
			beam.Enabled = lit
		end
		for _, lens in built.lenses or {} do
			lens.Material = if lit then Enum.Material.Neon else lenses[lens]
		end
	end
	model:GetAttributeChangedSignal("Lights"):Connect(applyLights)

	-- The turn signals flash on and off together, a third of a second each, for as long as one is set.
	local signals = (built :: any).signals
	if signals and (#signals.left > 0 or #signals.right > 0) then
		task.spawn(function()
			local shown = false
			while task.wait(0.34) do
				if model.Parent == nil then
					break
				end
				local mode = model:GetAttribute("Signal")
				local wantLeft = mode == "left" or mode == "hazard"
				local wantRight = mode == "right" or mode == "hazard"
				shown = not shown
				for _, lamp in signals.left do
					lamp.Transparency = if wantLeft and shown then 0 else 1
				end
				for _, lamp in signals.right do
					lamp.Transparency = if wantRight and shown then 0 else 1
				end
			end
		end)
	end

	-- Lamps that light up rather than change colour: a modelled car's.
	local lamps: { [BasePart]: { material: Enum.Material, light: PointLight? } } = {}
	if built.mesh then
		for _, lamp in built.brakeLights do
			lamps[lamp] = { material = lamp.Material, light = lampLight(lamp, Color3.fromRGB(255, 30, 30), 0.8, 6) }
		end
		for _, lamp in built.reverseLights do
			lamps[lamp] = { material = lamp.Material, light = lampLight(lamp, Color3.fromRGB(240, 246, 255), 1.6, 12) }
		end
	end

	-- Tells a client the car has been sent whole: set a moment after it is in the world, so it reaches
	-- a client after the parts, welds and attributes it describes. See CarPhysics.WhenReady.
	task.delay(0.3, function()
		if model.Parent ~= nil then
			model:SetAttribute("Ready", true)
		end
	end)

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

	-- Made on the first tick the car is in the world: a rig reads where the weight is, which a part that
	-- has not been given a parent yet cannot say.
	local physics: CarPhysics.Rig? = nil
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
			-- Driven: something else is stepping this car -- a script's test of it, an AI driver.
			if seat.Occupant == nil and model:GetAttribute("Driven") ~= true then
				if physics == nil then
					physics = CarPhysics.Rig(model)
				end
				if physics then
					CarPhysics.Park(physics, elapsed)
				end
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
					local glow = lamps[lamp]
					if glow then
						lamp.Material = if braking then Enum.Material.Neon else glow.material
						if glow.light then
							glow.light.Enabled = braking
						end
					else
						lamp.Color = if braking then CarBody.BrakeColor else CarBody.TailColor
					end
				end
			end
			if nowReversing ~= reversing then
				reversing = nowReversing
				for _, lamp in built.reverseLights do
					local glow = lamps[lamp]
					lamp.Material = if reversing then Enum.Material.Neon elseif glow then glow.material else Enum.Material.SmoothPlastic
					if glow and glow.light then
						glow.light.Enabled = reversing
					end
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
		-- Not from a seat already: E is a gear key in a car, and must not climb into the next one.
		if humanoid and humanoid.SeatPart == nil then
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
		prompt.Enabled = occupant == nil
		if occupant ~= nil then
			-- Seated by a touch or anything else: still out of the body's collisions.
			driver = occupant
			local character = occupant.Parent
			if character then
				setGroup(character, DRIVER_GROUP)
				poseDriver(character :: Model, true)
			end
			-- At night the lights come on with the driver.
			local hour = game:GetService("Lighting").ClockTime
			model:SetAttribute("Lights", hour < 6.5 or hour >= 17.5)
		else
			model:SetAttribute("Lights", false)
			model:SetAttribute("Signal", "")
			model:SetAttribute("Horn", false)
			poseDriver(if driver then (driver.Parent :: Model?) else nil, false)
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
