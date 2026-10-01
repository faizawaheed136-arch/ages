--!strict
--[[
	What a car IS, in real units: its mass, its engine's torque curve, its gearbox, its tyres, its
	springs. shared/CarPhysics reads this and simulates it; nothing here moves anything.

	WHY REAL UNITS. The world is in studs, and a stud is taken here as 0.28 m (the five-stud avatar
	is 1.4 m tall, so a 4.7 m car is 16.8 studs -- about what the dealership's cars are). Writing a
	car as kilograms, newton-metres, hertz and g means its numbers can be checked against the real
	thing -- a GT-R does 0-100 km/h in under three seconds, stops from 100 in about 31 m, and pulls
	1 g round a corner -- instead of being tuned by feel and forgotten. The physics converts at the
	edge, once, in one place.

	WHY NOT JUST USE ROBLOX'S GRAVITY. workspace.Gravity is 196.2 studs/s^2: 55 m/s^2 at this
	scale, five and a half times real gravity. A tyre's grip is a fraction of the weight on it, so
	done naively cars would brake and corner at five g, and a ten-degree hill would pull like a
	wall. CarPhysics holds the car up against the world's gravity with its springs, and works out
	grip and weight transfer against a real 9.81 m/s^2 -- the same numbers a real car has.

	Two kinds of spec: a hand-written one for a car that is modelled on a real one (the GT-R), and a
	derived one, made from the few numbers content/Vehicles gives every car (top speed,
	acceleration, steering, size), so that every car in the dealership drives on the same physics.
]]

local CarSpec = {}

-- A stud is 0.28 m.
CarSpec.StudsPerMetre = 1 / 0.28
CarSpec.Gravity = 9.81

-- Studs to the metre for a car drawn `scale` times larger than life: a car that is 1.25 times bigger
-- has a metre of it 1.25 times as many studs long, and everything the physics works out in real units
-- -- speeds, forces, radii -- is converted with this, not with StudsPerMetre.
function CarSpec.StudsPerMetreOf(scale: number): number
	return CarSpec.StudsPerMetre * scale
end

export type Spec = {
	id: string,
	-- How many times larger than life the car is drawn. The numbers below stay the real car's.
	scale: number,
	-- Mass and layout.
	massKg: number,
	drive: string, -- "FWD", "RWD" or "AWD"
	frontBias: number, -- the share of drive torque sent to the front axle, AWD only
	wheelbase: number, -- m
	trackFront: number, -- m
	trackRear: number, -- m
	tyreRadius: number, -- m
	cgHeight: number, -- m, the centre of mass above the road
	weightFront: number, -- the share of the weight on the front axle
	-- The engine: {rpm, Nm} pairs, lowest rpm first.
	torque: { { number } },
	idleRpm: number,
	redlineRpm: number,
	limiterRpm: number,
	launchRpm: number, -- where the clutch holds the engine off the line
	engineInertia: number, -- kg m^2
	engineBrake: number, -- Nm of drag at redline with the throttle shut
	turbo: boolean,
	boostRpm: number, -- the rpm the turbo is fully on song by
	boostBase: number, -- the share of torque available with no boost at all
	boostLag: number, -- seconds for the boost to build
	-- The gearbox.
	gears: { number },
	reverse: number,
	finalDrive: number,
	driveEff: number,
	shiftTime: number,
	-- Resistance.
	cdA: number, -- drag area, m^2
	liftA: number, -- lift area, m^2: negative is downforce
	rollingResistance: number,
	-- Tyres.
	mu: number, -- peak sideways grip, as a multiple of the load on the tyre
	muLong: number, -- peak grip along the tyre: higher, braking and launching, than sideways
	muSlide: number, -- what is left of it once the tyre lets go
	muBrake: number, -- peak grip under the brakes: a driving game's brakes, not a road car's
	muFront: number, -- multipliers on mu, to set the balance of the car
	muRear: number,
	-- What the handling adds to the tyres, for a car that is driven with a keyboard.
	gripGain: number, -- more sideways grip with speed, up to this much more (a share of mu) by 30 m/s
	driftGrip: number, -- the share of its sideways grip a rear tyre keeps with the handbrake held
	steerSpeed: number, -- the speed, m/s, at which the front wheels have half their lock left
	steerAssist: number, -- how far past its peak a front tyre is let to slip when the wheel is turned
	yawAssist: number, -- 0 to 1: how much of the turn the wheel asks for is simply given to the car
	yawGain: number, -- per second: how quickly the car's yaw is taken to what the wheel asks for
	yawGrip: number, -- the sideways g, as a multiple of the tyres', the assist will ask for
	nitroG: number, -- the push the nitro adds, in g
	cornerB: number, -- how quickly grip builds with slip angle
	cornerC: number,
	wheelInertia: number, -- kg m^2, each
	-- Brakes.
	brakeG: number, -- the most the brakes could ever slow the car, in g
	abs: boolean,
	tc: boolean,
	-- Suspension.
	rideFront: number, -- Hz
	rideRear: number,
	zetaBump: number,
	zetaRebound: number,
	antiRollFront: number, -- as a share of the springs' own roll stiffness
	antiRollRear: number,
	travelBump: number, -- m
	travelDroop: number, -- m
	-- Steering.
	steerLock: number, -- degrees at the road wheels, parked
	-- What it sounds like: read by client/world/CarSound.
	voice: string,
}

-- A torque curve, at `rpm`.
local function curveAt(curve: { { number } }, rpm: number): number
	if rpm <= curve[1][1] then
		return curve[1][2]
	end
	for i = 2, #curve do
		local a, b = curve[i - 1], curve[i]
		if rpm <= b[1] then
			return a[2] + (b[2] - a[2]) * (rpm - a[1]) / (b[1] - a[1])
		end
	end
	return curve[#curve][2]
end

-- The torque curve of a spec, at `rpm`.
function CarSpec.Torque(spec: Spec, rpm: number): number
	return curveAt(spec.torque, rpm)
end

-- ---------------------------------------------------------------------------------------------
-- The GT-R. Nismo, 2020: a 3.8 litre twin-turbo V6, a six-speed twin-clutch gearbox, all-wheel
-- drive. Figures are the manufacturer's and the road tests' -- 441 kW and 652 Nm, 1,720 kg, 0-100
-- km/h in 2.9 s, 100-0 in 31 m, 315 km/h -- and the model's own measurements (wheelbase, track and
-- tyre size are off the imported mesh).
-- ---------------------------------------------------------------------------------------------
local GTR: Spec = {
	id = "gtr",
	-- Drawn a quarter larger than life, so the avatar at its wheel fits inside it and the car reads as
	-- big next to the people and the road.
	scale = 1.25,
	massKg = 1750,
	drive = "AWD",
	frontBias = 0.30,
	wheelbase = 2.78,
	trackFront = 1.59,
	trackRear = 1.60,
	tyreRadius = 0.364,
	-- Lower than the real car's 0.52 m: with the grip a driving game gives its tyres, a real centre of
	-- mass would roll the car over at the first corner.
	cgHeight = 0.38,
	weightFront = 0.54,
	torque = {
		-- The makers' curve (652 Nm from 3,600 to 5,600 rpm), a little over: a dynamometer reads a
		-- turbo car a few per cent above its brochure.
		{ 800, 250 },
		{ 1500, 340 },
		{ 2000, 455 },
		{ 2500, 572 },
		{ 3200, 660 },
		{ 3600, 672 },
		{ 5600, 672 },
		{ 6000, 665 },
		{ 6400, 651 },
		{ 6800, 638 },
		{ 7000, 608 },
		{ 7250, 546 },
	},
	idleRpm = 800,
	redlineRpm = 7100,
	limiterRpm = 7250,
	launchRpm = 3600,
	engineInertia = 0.2,
	engineBrake = 70,
	turbo = true,
	boostRpm = 3200,
	boostBase = 0.85,
	boostLag = 0.2,
	gears = { 4.056, 2.301, 1.595, 1.248, 1.001, 0.796 },
	reverse = 3.522,
	-- 3.7 on the real car's 0.35 m rolling radius; this model's tyre is 0.364, so the same gearing is
	-- 3.85: the same road speed at the same revs.
	finalDrive = 3.85,
	driveEff = 0.92,
	shiftTime = 0.13,
	cdA = 0.6,
	liftA = -0.12,
	rollingResistance = 0.013,
	mu = 1.6,
	muLong = 1.5,
	muBrake = 2.3,
	muSlide = 0.9,
	muFront = 0.98,
	muRear = 1.03,
	gripGain = 0.5,
	driftGrip = 0.3,
	steerSpeed = 38,
	steerAssist = 1.15,
	yawAssist = 1,
	yawGain = 14,
	yawGrip = 0.8,
	nitroG = 0.55,
	cornerB = 14,
	cornerC = 1.4,
	wheelInertia = 1.1,
	brakeG = 3.2,
	abs = true,
	tc = true,
	rideFront = 1.5,
	rideRear = 1.65,
	zetaBump = 0.55,
	zetaRebound = 0.85,
	antiRollFront = 0.65,
	antiRollRear = 0.45,
	travelBump = 0.16,
	travelDroop = 0.14,
	steerLock = 38,
	voice = "twinturbo",
}

CarSpec.Specs = {
	gtr = GTR,
} :: { [string]: Spec }

-- ---------------------------------------------------------------------------------------------
-- A spec from the numbers every car in content/Vehicles has.
-- ---------------------------------------------------------------------------------------------

-- A generic torque curve shaped like a road engine's: it climbs to a plateau a third of the way up
-- the rev range and falls away toward the redline, scaled so its peak power is `powerW`.
local SHAPE = { { 0.12, 0.55 }, { 0.25, 0.80 }, { 0.40, 0.97 }, { 0.55, 1.0 }, { 0.70, 0.97 }, { 0.85, 0.90 }, { 1.0, 0.80 }, { 1.04, 0.6 } }

local function genericCurve(redline: number, idle: number, powerW: number): { { number } }
	local best = 0
	for _, p in SHAPE do
		local omega = p[1] * redline * 2 * math.pi / 60
		best = math.max(best, p[2] * omega)
	end
	local scale = powerW / best
	local curve: { { number } } = { { idle, SHAPE[1][2] * scale * 0.7 } }
	for _, p in SHAPE do
		table.insert(curve, { p[1] * redline, p[2] * scale })
	end
	return curve
end

--[[
	`top` and `accel` are content/Vehicles' topSpeedStuds and acceleration; `size` is the car's
	outline in studs. A car is given the mass a box that size has at a car's density, the power to
	reach `top` against the drag a car its shape has, and gears spread so its top gear tops out at
	`top` -- and the initial pull (`accel`, in studs/s^2) is what the tyres can put down.
]]
function CarSpec.Derive(id: string, top: number, accel: number, steerDegrees: number, size: Vector3, drive: string, radiusStuds: number, scale: number?): Spec
	-- A car drawn larger than life has more studs to the metre; its size, top speed and the rest are in
	-- those studs.
	local drawn = scale or 1
	local S = CarSpec.StudsPerMetreOf(drawn)
	local volume = size.X * size.Y * size.Z / (S * S * S)
	local mass = math.clamp(105 * volume, 850, 2600)
	local vTop = top / S
	local a0 = accel / S
	local rolling = 0.015
	-- Power: what it takes to pull a0 at the speed it hits top gear -- so the car keeps the pull its
	-- catalog entry promises up to about a third of the way to top speed, not just at a standstill.
	local power = mass * a0 * vTop
	local driveEff = 0.9
	local radius = radiusStuds / S
	local redline, idle = 6400, 800
	local peakPowerRpm = 0.78 * redline
	local curve = genericCurve(redline, idle, power)
	-- Drag area: the drag that stops it at `top`, with what the engine really makes at the revs `top` is
	-- reached at -- a little under its peak -- on the wheels.
	local powerAtTop = curveAt(curve, peakPowerRpm) * peakPowerRpm * 2 * math.pi / 60
	local cdA = math.max(0.35, (driveEff * powerAtTop - rolling * mass * CarSpec.Gravity * vTop) / (0.5 * 1.2 * vTop ^ 3))
	local topRatio = (peakPowerRpm * 2 * math.pi / 60) * radius / vTop
	local finalDrive = 3.4
	local topGear = topRatio / finalDrive
	-- First gear only as much lower than top as a car of this power needs to pull its first g: 2.2
	-- times, not the five a road car with six forward gears has. The gearing of a car that tops out
	-- at 80 km/h is already that of a car's first and second, and five times that would be 48:1, which
	-- a driven wheel can only spin up on, never roll with.
	local firstGear = topGear * 2.2
	local gears: { number } = {}
	for i = 0, 4 do
		table.insert(gears, firstGear * (topGear / firstGear) ^ (i / 4))
	end
	local lock = math.clamp(steerDegrees, 22, 38)
	return {
		id = id,
		scale = drawn,
		massKg = mass,
		drive = drive,
		frontBias = 0.4,
		wheelbase = math.max(2.3, size.Z / S * 0.6),
		trackFront = size.X / S * 0.8,
		trackRear = size.X / S * 0.8,
		tyreRadius = radius,
		cgHeight = math.clamp(size.Y / S * 0.28, 0.36, 0.6),
		weightFront = if drive == "FWD" then 0.6 elseif drive == "RWD" then 0.5 else 0.54,
		torque = curve,
		idleRpm = idle,
		redlineRpm = redline,
		limiterRpm = redline + 200,
		launchRpm = 2400,
		engineInertia = 0.18,
		engineBrake = 55,
		turbo = false,
		boostRpm = 3000,
		boostBase = 1,
		boostLag = 0.3,
		gears = gears,
		reverse = firstGear * 0.9,
		finalDrive = finalDrive,
		driveEff = driveEff,
		shiftTime = 0.3,
		cdA = cdA,
		liftA = 0,
		rollingResistance = rolling,
		mu = 1.45,
		muLong = 1.3,
		muBrake = 2.3,
		muSlide = 0.88,
		muFront = 0.98,
		muRear = 1.03,
		gripGain = 0.4,
		driftGrip = 0.32,
		steerSpeed = 30,
		steerAssist = 1.15,
		yawAssist = 1,
		yawGain = 14,
		yawGrip = 0.8,
		nitroG = 0.45,
		cornerB = 12,
		cornerC = 1.4,
		wheelInertia = 1.5,
		brakeG = 2.8,
		abs = true,
		tc = true,
		rideFront = 1.35,
		rideRear = 1.45,
		zetaBump = 0.5,
		zetaRebound = 0.75,
		antiRollFront = 0.8,
		antiRollRear = 0.6,
		travelBump = 0.16,
		travelDroop = 0.14,
		steerLock = math.clamp(lock + 4, 26, 40),
		voice = "road",
	}
end

local derived: { [string]: Spec } = {}

--[[
	The spec of a car in content/Vehicles: the hand-written one if it has one (the GT-R), or one made
	from its numbers. A modelled car that is not hand-written -- the pack of imported cars -- is
	derived at the scale it is drawn at, on the tyre radius its entry gives.
]]
function CarSpec.Of(kind: {
	id: string,
	topSpeedStuds: number,
	acceleration: number,
	steerDegrees: number,
	size: Vector3,
	drivetrain: string?,
	scale: number?,
	tyreRadius: number?,
}): Spec
	local written = CarSpec.Specs[kind.id]
	if written then
		return written
	end
	local cached = derived[kind.id]
	if cached then
		return cached
	end
	local drive = if kind.drivetrain == "FWD" or kind.drivetrain == "RWD" then kind.drivetrain :: string else "AWD"
	local scale = kind.scale or 1
	local radiusStuds = (kind.tyreRadius or 0.32) * CarSpec.StudsPerMetreOf(scale)
	local spec = CarSpec.Derive(kind.id, kind.topSpeedStuds, kind.acceleration, kind.steerDegrees, kind.size, drive, radiusStuds, scale)
	derived[kind.id] = spec
	return spec
end

return CarSpec
