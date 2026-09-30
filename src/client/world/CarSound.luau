--!strict
--[[
	What every car sounds like, on this client: the engine, the turbo, the gearbox, the tyres and the
	wind. Each car within HEAR_STUDS of the camera with somebody in it gets a set of Sounds on its hull,
	so Roblox's own 3D sound does the distance and the panning, and they are updated every frame from
	what the car is doing.

	WHAT IT READS. The car this machine drives has its telemetry in CarPhysics.Live: real engine
	revs, the turbo's boost, how many shifts there have been, how hard each tyre is sliding. A car
	somebody else drives has only what replicates -- its speed, its seat's throttle -- and its revs are
	what its gearbox would have it at (CarPhysics.EstimateRpm). Nobody in a car, no engine: a parked car
	is silent.

	THE ENGINE is three looped recordings crossfaded across the rev range, each played faster as the
	revs rise: an idle loop that carries the bottom, a mid-range loop, and a bright one for the top. A
	recording played faster goes up in pitch the way revs do, and where two overlap one is fading out as
	the other fades in, so the join is not heard. Throttle sets how loud and how bright; lifting off
	quietens it, which is what engine braking sounds like.

	THE OTHER LAYERS. Boost is an airy rush that rises in pitch and level with the turbo; lifting off
	the throttle under boost vents it, with the blow-off valve's hiss. A shift thumps, and at high revs
	on the throttle the exhaust cracks. A tyre that slides screams, louder the harder it slides. Wind
	comes up with the square of the speed.

	WHERE THE SOUNDS COME FROM. Every id below was found by marketplace search, and loads. The voice a
	car is given (CarSpec's `voice`) picks how much of the turbo there is: "twinturbo" has all of it.
	Swapping a recording is a one-line change in SOUNDS; the pitch ranges are in ENGINE.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarPhysics = require(ReplicatedStorage:WaitForChild("CarPhysics"))
local CarSpec = require(ReplicatedStorage:WaitForChild("CarSpec"))

local HEAR_STUDS = 260

local SOUNDS = {
	-- Engine, low to high.
	idle = "rbxassetid://126560668123605", -- New Gen Car Idle Engine
	mid = "rbxassetid://5830439961", -- car engine loop
	high = "rbxassetid://106461618159911", -- V6 engine 3
	-- An airy rush: the turbo's breath, and under it the wind.
	rush = "rbxassetid://9120610374", -- Water Wake Constant 2 (Pro Sound Effects)
	skid = "rbxassetid://73429750798250", -- Tire skid/screech sound
	bov = "rbxassetid://119410156059995", -- Blow Off Valve - HKS
	shiftUp = "rbxassetid://89099133276738", -- shiftup
	shiftDown = "rbxassetid://127881754247004", -- downshift
	start = "rbxassetid://5830481291", -- car engine start
}

-- How each engine layer is played: its pitch from `speed0` at idle to `speed1` at the redline, and
-- where along the rev range (0 idle, 1 redline) it is at full volume and how far either side it is
-- heard.
local ENGINE = {
	idle = { speed0 = 0.85, speed1 = 1.7, centre = 0.0, reach = 0.5, level = 0.85 },
	mid = { speed0 = 0.6, speed1 = 1.9, centre = 0.45, reach = 0.45, level = 0.7 },
	high = { speed0 = 0.75, speed1 = 1.55, centre = 1.0, reach = 0.6, level = 0.75 },
}

type Car = {
	model: Model,
	hull: BasePart,
	seat: VehicleSeat?,
	spec: CarSpec.Spec,
	turbo: boolean,
	loops: { [string]: Sound },
	-- 0 to 1: how much the engine is running, for the start and the shut-down.
	running: number,
	started: boolean,
	rpm: number,
	boost: number,
	throttle: number,
	lastThrottle: number,
	shifts: number,
	lastGear: number,
	vented: number,
	paused: boolean,
}

local CarSound = {}

local function loop(parent: Instance, name: string, id: string): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = 0
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 14
	sound.RollOffMaxDistance = 240
	sound.Parent = parent
	sound:Play()
	return sound
end

local function shot(car: Car, id: string, volume: number, speed: number)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 14
	sound.RollOffMaxDistance = 240
	sound.Parent = car.hull
	sound:Play()
	Debris:AddItem(sound, 6)
end

local function smooth(edge0: number, edge1: number, x: number): number
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- How loud an engine layer is at `share` along the rev range: full at its centre, fading to nothing
-- `reach` either side of it.
local function window(layer: { centre: number, reach: number }, share: number): number
	local d = math.abs(share - layer.centre) / layer.reach
	return 1 - smooth(0, 1, d)
end

local function build(model: Model): Car?
	local hull = model.PrimaryPart
	if hull == nil then
		return nil
	end
	local seat = model:FindFirstChild("DriverSeat")
	local spec = CarPhysics.SpecOf(model)
	local car: Car = {
		model = model,
		hull = hull,
		seat = if seat and seat:IsA("VehicleSeat") then seat else nil,
		spec = spec,
		turbo = spec.turbo,
		loops = {},
		running = 0,
		started = false,
		rpm = spec.idleRpm,
		boost = 0,
		throttle = 0,
		lastThrottle = 0,
		shifts = 0,
		lastGear = 1,
		vented = 0,
		paused = false,
	}
	for _, name in { "idle", "mid", "high" } do
		car.loops[name] = loop(hull, "Engine_" .. name, SOUNDS[name])
	end
	car.loops.rush = loop(hull, "Rush", SOUNDS.rush)
	car.loops.wind = loop(hull, "Wind", SOUNDS.rush)
	car.loops.skid = loop(hull, "Skid", SOUNDS.skid)
	return car
end

-- A car nobody is in, or that is out of earshot, has its loops stopped, not just turned down: sixty
-- looping sounds with their volume at nothing still cost something every frame.
local function silence(car: Car)
	if car.paused then
		return
	end
	car.paused = true
	for _, sound in car.loops do
		sound.Volume = 0
		sound:Pause()
	end
end

local function wake(car: Car)
	if not car.paused then
		return
	end
	car.paused = false
	for _, sound in car.loops do
		sound:Resume()
	end
end

local function update(car: Car, dt: number)
	local hull = car.hull
	local spec = car.spec
	local seat = car.seat
	local occupied = seat ~= nil and seat.Occupant ~= nil
	local rig = CarPhysics.Live[car.model]
	local tele = if rig then rig.tele else nil

	-- Ignition: the engine catches when somebody sits, and dies when they leave.
	if occupied and not car.started then
		car.started = true
		shot(car, SOUNDS.start, 0.6, 1)
		car.running = 0
	elseif not occupied and car.started then
		car.started = false
	end
	car.running = math.clamp(car.running + (if occupied then dt / 0.7 else -dt / 0.45), 0, 1)
	if car.running <= 0 then
		silence(car)
		return
	end
	wake(car)

	local frame = hull.CFrame
	local velocity = hull.AssemblyLinearVelocity
	local speed = velocity:Dot(frame.LookVector)
	local lateral = math.abs(velocity:Dot(frame.RightVector))

	-- The revs, throttle and boost: the physics' own, or what they would be.
	local rpm, throttle, boost, gear, sliding
	if tele then
		rpm, throttle, boost, gear = tele.rpm, tele.throttle, tele.boost, tele.gear
		sliding = 0
		for i = 1, #tele.slip do
			if (tele.load[i] or 0) > 0 then
				sliding = math.max(sliding, (math.abs(tele.slip[i]) - 0.25) / 0.5)
			end
		end
		if tele.shifts ~= car.shifts then
			local up = tele.gear > car.lastGear
			car.shifts = tele.shifts
			car.lastGear = tele.gear
			shot(car, if up then SOUNDS.shiftUp else SOUNDS.shiftDown, 0.35, 0.95 + math.random() * 0.1)
			if tele.rpm > spec.redlineRpm * 0.7 and tele.throttle > 0.4 then
				shot(car, SOUNDS.shiftDown, 0.5, 1.3 + math.random() * 0.3)
			end
		end
	else
		local input = if seat then math.max(seat.Throttle, 0) else 0
		local est
		est, gear = CarPhysics.EstimateRpm(spec, speed, input)
		rpm = est
		throttle = input
		boost = if car.turbo then input * math.clamp(rpm / spec.boostRpm, 0, 1) ^ 1.5 else 0
		sliding = 0
	end
	car.rpm += (rpm - car.rpm) * math.min(1, dt * 14)
	car.boost += (boost - car.boost) * math.min(1, dt * 6)
	car.throttle += (throttle - car.throttle) * math.min(1, dt * 12)

	-- Lifting off under boost vents it.
	if car.turbo and car.lastThrottle > 0.6 and car.throttle < 0.25 and car.boost > 0.45 then
		shot(car, SOUNDS.bov, 0.5 * math.clamp(car.boost, 0, 1), 0.95 + math.random() * 0.1)
		car.boost *= 0.3
		car.vented = 0.6
	end
	car.lastThrottle = car.throttle
	car.vented = math.max(0, car.vented - dt)

	local share = math.clamp((car.rpm - spec.idleRpm) / (spec.redlineRpm - spec.idleRpm), 0, 1)
	-- Loud on the throttle, hushed off it, and quieter in the last of a shut-down.
	local load = 0.42 + 0.58 * car.throttle
	local fade = car.running
	for name, layer in ENGINE do
		local sound = car.loops[name]
		sound.PlaybackSpeed = layer.speed0 + (layer.speed1 - layer.speed0) * share
		local bright = if name == "high" then 0.35 + 0.65 * car.throttle else 1
		sound.Volume = layer.level * window(layer, share) * load * bright * fade
	end

	-- The turbo's breath: it rises with the boost, and is the loudest part of a lift off.
	local rush = car.loops.rush
	if car.turbo then
		rush.PlaybackSpeed = 1.25 + 0.9 * car.boost
		rush.Volume = (0.05 + 0.3 * car.boost * car.boost + 0.12 * car.vented) * fade
	else
		rush.Volume = 0
	end

	-- Wind and the road: the square of the speed.
	local wind = car.loops.wind
	local fast = math.clamp(math.abs(speed) / 80, 0, 1.4)
	wind.PlaybackSpeed = 0.75 + 0.35 * fast
	wind.Volume = 0.55 * fast * fast * fade

	-- A tyre that slides: from the physics where it is ours, from the motion where it is not.
	local slide = math.clamp(lateral - 9, 0, 12) / 12
	if math.abs(speed) < 6 then
		slide = 0
	end
	sliding = math.clamp(math.max(sliding :: number, slide), 0, 1)
	local skid = car.loops.skid
	skid.PlaybackSpeed = 0.9 + 0.3 * math.clamp(math.abs(speed) / 40, 0, 1) + 0.15 * sliding
	skid.Volume = 0.85 * sliding * (0.4 + 0.6 * math.clamp(math.abs(speed) / 25, 0, 1)) * fade
end

function CarSound.Start()
	local cars: { [Model]: Car } = {}
	local function add(model: Instance)
		if model:IsA("Model") then
			task.defer(function()
				if cars[model] == nil and model.Parent ~= nil then
					local car = build(model)
					if car then
						cars[model] = car
					end
				end
			end)
		end
	end
	local function remove(model: Instance)
		if model:IsA("Model") then
			local car = cars[model]
			if car then
				for _, sound in car.loops do
					sound:Destroy()
				end
				cars[model] = nil
			end
		end
	end
	for _, model in CollectionService:GetTagged(CarPhysics.Tag) do
		add(model)
	end
	CollectionService:GetInstanceAddedSignal(CarPhysics.Tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(CarPhysics.Tag):Connect(remove)
	RunService.RenderStepped:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local eye = camera.CFrame.Position
		for model, car in cars do
			if model.Parent == nil or car.hull.Parent == nil then
				remove(model)
			elseif (car.hull.Position - eye).Magnitude <= HEAR_STUDS then
				update(car, dt)
			else
				silence(car)
			end
		end
	end)
end

return CarSound
