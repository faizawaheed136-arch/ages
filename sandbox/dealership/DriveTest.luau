--!strict
--[[
	Scripted drive tests for shared/CarPhysics, run on the server in a Play session of the sandbox
	place: builds a car from content/Vehicles on a slab of asphalt a long way from the dealership,
	drives it with scripted pedals, and measures it -- 0-100 km/h, 100-0 and 200-0 stopping, the
	steady cornering force on a skidpad, stability at rest and on a slope, a kerb taken at speed.

	Not shipped: a tool for tuning, installed beside the car modules by drive.project.json. The
	results go back as a table (and as JSON on workspace's DriveTestResult attribute, for reading
	while a run is under way).
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local CarBody = require(ReplicatedStorage:WaitForChild("CarBody"))
local CarPhysics = require(ReplicatedStorage:WaitForChild("CarPhysics"))
local CarSpec = require(ReplicatedStorage:WaitForChild("CarSpec"))
local Vehicles = require(ServerStorage:WaitForChild("Vehicles"))
local VehicleChassis = require(ServerStorage:WaitForChild("VehicleChassis"))

local S = CarSpec.StudsPerMetre
-- How many times larger than life the car under test is drawn, set by Spawn: every stud below is
-- 0.28 / K metres.
local K = 1
local ORIGIN = Vector3.new(20000, 0, 0)

local DriveTest = {}

-- Step the car on every Nth frame instead of every frame, to test how it drives on a slow machine.
DriveTest.Skip = 1

type Controls = CarPhysics.Controls

local function ground()
	local old = workspace:FindFirstChild("DriveTestGround")
	if old then
		return old
	end
	local folder = Instance.new("Folder")
	folder.Name = "DriveTestGround"
	folder.Parent = workspace
	-- A part is at most 2048 studs long: five of them end to end, from 1000 studs behind the start to
	-- 9000 ahead of it.
	for k = 0, 4 do
		local slab = Instance.new("Part")
		slab.Name = "Road"
		slab.Anchored = true
		slab.Material = Enum.Material.Asphalt
		slab.Color = Color3.fromRGB(60, 60, 64)
		slab.Size = Vector3.new(2000, 4, 2048)
		slab.Position = ORIGIN + Vector3.new(0, -2, -2048 * k)
		slab.Parent = folder
	end
	-- A circle of the same for a skidpad is just the slab: the test steers on it.
	return folder
end

local function clear()
	for _, m in workspace:GetChildren() do
		if m.Name:find("^Vehicle_") and m:GetAttribute("DriveTest") then
			m:Destroy()
		end
	end
end

type Rig = CarPhysics.Rig

-- A car standing on the test ground at `at` (studs from its origin), nose to -Z unless `yaw`.
function DriveTest.Spawn(id: string, at: Vector3?, yaw: number?): (Model, Rig)
	ground()
	clear()
	local kind = Vehicles.Get(id)
	assert(kind, "no such car " .. id)
	local layout = CarBody.Layout(kind)
	local pos = ORIGIN + (at or Vector3.zero) + Vector3.new(0, layout.hullY + 0.05, 0)
	local chassis = VehicleChassis.Build(kind, CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0), nil, nil)
	chassis.model:SetAttribute("DriveTest", true)
	-- Something else steps this car: the tests, not the parked-car loop.
	chassis.model:SetAttribute("Driven", true)
	chassis.model.Parent = workspace
	for _ = 1, 3 do
		RunService.Heartbeat:Wait()
	end
	local rig = CarPhysics.Rig(chassis.model)
	assert(rig, "no rig")
	K = rig.spec.scale
	-- Settle on the springs, parked, as a car standing in the world is.
	for _ = 1, 90 do
		local dt = RunService.PreSimulation:Wait()
		CarPhysics.Park(rig, dt)
	end
	return chassis.model, rig
end

local function speedOf(rig: Rig): number
	return rig.hull.AssemblyLinearVelocity:Dot(rig.hull.CFrame.LookVector) / (S * K)
end

-- Runs `control` every step for `seconds`, sampling every `every` seconds. `control` gets
-- (time, rig, speed m/s) and returns the pedals; return nil to stop early.
local function drive(rig: Rig, seconds: number, every: number, control: (number, Rig, number) -> Controls?, record: ((number, Rig) -> { [string]: any })?): { { [string]: any } }
	local samples = {}
	local t = 0
	local nextSample = 0
	local pending, frames = 0, 0
	local tele = rig.tele
	while t < seconds do
		local frame = RunService.PreSimulation:Wait()
		t += frame
		pending += frame
		frames += 1
		-- A slower machine steps the car less often: every DriveTest.Skip-th frame, over the time of all.
		if frames % DriveTest.Skip ~= 0 then
			continue
		end
		local v = speedOf(rig)
		local controls = control(t, rig, v)
		if controls == nil then
			break
		end
		tele = CarPhysics.Step(rig, pending, controls)
		pending = 0
		if t >= nextSample then
			nextSample += every
			local row: { [string]: any } = {
				t = math.round(t * 100) / 100,
				kph = math.round(tele.kph * 10) / 10,
				rpm = math.round(tele.rpm),
				gear = tele.gear,
				thr = math.round(tele.throttle * 100) / 100,
				brk = math.round(tele.brake * 100) / 100,
				abs = tele.abs,
				tc = tele.tc,
				slide = tele.sliding,
				g = math.round(tele.longG * 100) / 100,
				lat = math.round(tele.latG * 100) / 100,
				pitch = math.round(math.deg(math.asin(math.clamp(-rig.hull.CFrame.LookVector.Y, -1, 1))) * 10) / 10,
				roll = math.round(math.deg(math.asin(math.clamp(rig.hull.CFrame.RightVector.Y, -1, 1))) * 10) / 10,
			}
			if record then
				for k, v2 in record(t, rig) do
					row[k] = v2
				end
			end
			table.insert(samples, row)
		end
	end
	return samples
end

local NEUTRAL: Controls = { throttle = 0, steer = 0, handbrake = 0, boost = false }

-- Holds `target` m/s with the pedals, by a proportional controller.
local function hold(target: number, v: number): Controls
	local err = target - v
	return { throttle = math.clamp(err * 0.6, -1, 1), steer = 0, handbrake = 0, boost = false }
end

local function flipped(rig: Rig): boolean
	return rig.hull.CFrame.UpVector.Y < 0.3
end

-- 0 to `top` km/h flat out: times to 100, 200, 300 km/h, and the top speed reached.
function DriveTest.Accel(id: string, seconds: number?, every: number?): { [string]: any }
	local model, rig = DriveTest.Spawn(id)
	local marks: { [string]: number } = {}
	local top = 0
	local dist = 0
	local start = rig.hull.Position
	local samples = drive(rig, seconds or 30, every or 2, function(t, _, v)
		for _, kph in { 60, 100, 160, 200, 250, 300 } do
			if v * 3.6 >= kph and marks[tostring(kph)] == nil then
				marks[tostring(kph)] = math.round(t * 100) / 100
			end
		end
		top = math.max(top, v * 3.6)
		return { throttle = 1, steer = 0, handbrake = 0, boost = false }
	end, function(_, r)
		local tele = r.tele
		return {
			dist = math.round((r.hull.Position - start).Magnitude * 0.28 / K),
			tcCut = math.round(r.tcCut * 100) / 100,
			slipF = math.round(tele.slip[1] * 100) / 100,
			slipR = math.round(tele.slip[3] * 100) / 100,
			boost = math.round(tele.boost * 100) / 100,
			loadF = math.round(tele.load[1]),
			loadR = math.round(tele.load[3]),
		}
	end)
	dist = (rig.hull.Position - start).Magnitude * 0.28 / K
	model:Destroy()
	return { test = "accel", id = id, reach_kph = marks, topKph = math.round(top), metres = math.round(dist), samples = samples }
end

-- Flat out up to `from` km/h, then straight onto the brakes to a stop. Timed from the moment the
-- brake pedal is down (the speed then, and where), which is how a stopping distance is measured, and
-- also from the command, to show what the pedal's travel costs.
function DriveTest.Brake(id: string, from: number, steerWhileBraking: number?): { [string]: any }
	local model, rig = DriveTest.Spawn(id)
	local target = from / 3.6
	local phase = "run"
	local tCmd, pCmd = 0, Vector3.zero
	local tDown, vDown, pDown = 0, 0, Vector3.zero
	local down = false
	local stopT, stopD, stopDCmd = 0, 0, 0
	local absSeen = false
	local peakG = 0
	local samples = drive(rig, 70, 0.5, function(t, r, v)
		if phase == "run" then
			if v >= target then
				phase = "brake"
				tCmd = t
				pCmd = r.hull.Position
			else
				return { throttle = 1, steer = 0, handbrake = 0, boost = false }
			end
		end
		if not down and r.tele.brake >= 0.95 then
			down = true
			tDown, vDown, pDown = t, v, r.hull.Position
		end
		if r.tele.abs then
			absSeen = true
		end
		peakG = math.max(peakG, -r.tele.longG)
		if v < 0.3 then
			stopT = t - tDown
			stopD = (r.hull.Position - pDown).Magnitude * 0.28 / K
			stopDCmd = (r.hull.Position - pCmd).Magnitude * 0.28 / K
			return nil
		end
		return { throttle = -1, steer = steerWhileBraking or 0, handbrake = 0, boost = false }
	end)
	model:Destroy()
	return {
		test = "brake",
		id = id,
		fromKph = from,
		kphAtBrake = math.round(vDown * 3.6 * 10) / 10,
		pedalLag = math.round((tDown - tCmd) * 100) / 100,
		seconds = math.round(stopT * 100) / 100,
		metres = math.round(stopD * 10) / 10,
		metresFromCommand = math.round(stopDCmd * 10) / 10,
		avgG = if stopD > 0 then math.round(vDown * vDown / (2 * stopD) / 9.81 * 100) / 100 else 0,
		peakG = math.round(peakG * 100) / 100,
		abs = absSeen,
		flipped = flipped(rig),
		samples = samples,
	}
end

-- A steady turn at `kph` with the wheel held over: the lateral g it settles at.
function DriveTest.Skidpad(id: string, kph: number, steer: number): { [string]: any }
	local model, rig = DriveTest.Spawn(id)
	local target = kph / 3.6
	local peak, settled = 0, 0
	local count = 0
	local samples = drive(rig, 14, 0.5, function(t, r, v)
		local c = hold(target, v)
		if t > 3 then
			c.steer = steer
			c.throttle = math.clamp((target - v) * 0.6, -0.3, 1)
		end
		if t > 8 then
			peak = math.max(peak, math.abs(r.tele.latG))
			settled += math.abs(r.tele.latG)
			count += 1
		end
		return c
	end, function(_, r)
		local tele = r.tele
		return {
			yawRate = math.round(math.deg(r.hull.AssemblyAngularVelocity.Y) * 10) / 10,
			kphNow = math.round(speedOf(r) * 3.6),
			steerDeg = math.round(math.deg(tele.steer) * 10) / 10,
			loads = string.format("%d %d %d %d", tele.load[1], tele.load[2], tele.load[3], tele.load[4]),
			comp = string.format("%.2f %.2f %.2f %.2f", tele.compression[1], tele.compression[2], tele.compression[3], tele.compression[4]),
		}
	end)
	local out = {
		test = "skidpad",
		id = id,
		kph = kph,
		steer = steer,
		peakLatG = math.round(peak * 100) / 100,
		meanLatG = math.round(settled / math.max(count, 1) * 100) / 100,
		flipped = flipped(rig),
		samples = samples,
	}
	model:Destroy()
	return out
end

-- A key's worth of steering at `kph`: the wheel put over at once and held. How soon the car turns (the
-- time its yaw rate takes to reach half and nine tenths of where it settles), where it settles, whether
-- it overshoots, and the turning circle that makes.
function DriveTest.SteerStep(id: string, kph: number, input: number): { [string]: any }
	local model, rig = DriveTest.Spawn(id)
	local target = kph / 3.6
	local samples = drive(rig, 10.5, 0.04, function(t, _, v)
		local c = hold(target, v)
		if t > 6 then
			c.steer = input
			c.throttle = math.clamp((target - v) * 0.6, -0.3, 1)
		end
		return c
	end, function(_, r)
		return {
			yaw = math.round(math.deg(r.hull.AssemblyAngularVelocity:Dot(r.hull.CFrame.UpVector)) * 10) / 10,
			steerDeg = math.round(math.deg(r.tele.steer) * 10) / 10,
		}
	end)
	local sum, n, peak = 0, 0, 0
	for _, row in samples do
		if row.t >= 9.5 then
			sum += math.abs(row.yaw)
			n += 1
		end
		if row.t >= 6 then
			peak = math.max(peak, math.abs(row.yaw))
		end
	end
	local final = sum / math.max(n, 1)
	local t50, t90 = -1, -1
	for _, row in samples do
		if row.t >= 6 then
			if t50 < 0 and math.abs(row.yaw) >= final * 0.5 then
				t50 = row.t - 6
			end
			if t90 < 0 and math.abs(row.yaw) >= final * 0.9 then
				t90 = row.t - 6
			end
		end
	end
	local out = {
		test = "steerstep",
		id = id,
		kph = kph,
		input = input,
		yawFinal = math.round(final),
		t50 = math.round(t50 * 100) / 100,
		t90 = math.round(t90 * 100) / 100,
		overshootPct = math.round((peak / math.max(final, 0.1) - 1) * 100),
		radiusMetres = math.round(target / math.max(math.rad(final), 0.01) * 10) / 10,
		flipped = flipped(rig),
		samples = samples,
	}
	model:Destroy()
	return out
end

-- A tap of a steering key at `kph`: `tap` seconds of full lock, then straight. How far the car's heading
-- has turned a second and a half after (a key is pressed for a moment, and a car should answer a moment).
function DriveTest.SteerTap(id: string, kph: number, tap: number): { [string]: any }
	local model, rig = DriveTest.Spawn(id)
	local target = kph / 3.6
	local heading0 = 0
	local function heading(r: Rig): number
		return math.deg(math.atan2(-r.hull.CFrame.LookVector.X, -r.hull.CFrame.LookVector.Z))
	end
	local peakYaw = 0
	local samples = drive(rig, 7.5 + tap, 0.1, function(t, r, v)
		local c = hold(target, v)
		if t > 6 and heading0 == 0 then
			heading0 = heading(r)
		end
		if t > 6 and t < 6 + tap then
			c.steer = 1
		end
		if t > 6 then
			peakYaw = math.max(peakYaw, math.abs(math.deg(r.hull.AssemblyAngularVelocity:Dot(r.hull.CFrame.UpVector))))
		end
		return c
	end, function(_, r)
		return { heading = math.round(heading(r) * 10) / 10 }
	end)
	local out = {
		test = "steertap",
		id = id,
		kph = kph,
		tap = tap,
		-- heading change 1.5 s after the key came up, and the car's peak yaw rate in it.
		turnedDeg = math.round(math.abs(samples[#samples].heading - heading0) * 10) / 10,
		peakYaw = math.round(peakYaw),
		flipped = flipped(rig),
		samples = samples,
	}
	model:Destroy()
	return out
end

-- Flat out into a solid wall, head on or at `angle` degrees, at `kph`: does it stop, spin, flip, bounce
-- back or stick to the wall? Reports speed in and out, how far it was turned, and what is left running
-- at the end (a car pinned to a wall with the throttle held should not shake itself apart).
function DriveTest.Wall(id: string, kph: number, angle: number): { [string]: any }
	local g = ground()
	local wall = Instance.new("Part")
	wall.Name = "Wall"
	wall.Anchored = true
	wall.Size = Vector3.new(900, 30, 8)
	wall.Position = ORIGIN + Vector3.new(0, 15, -420)
	wall.Parent = g
	local model, rig = DriveTest.Spawn(id, nil, math.rad(angle))
	local target = kph / 3.6
	local vIn, tHit, hit = 0, 0, false
	local peakUp, airborne, maxSpin = 1, 0, 0
	local startHeading = math.atan2(-rig.hull.CFrame.LookVector.X, -rig.hull.CFrame.LookVector.Z)
	local lastV = 0
	local samples = drive(rig, 25, 0.5, function(t, r, v)
		if not hit then
			vIn = math.max(vIn, v)
			if v < lastV - 3 and vIn > 5 then
				hit = true
				tHit = t
			end
		end
		lastV = v
		if hit then
			peakUp = math.min(peakUp, r.hull.CFrame.UpVector.Y)
			maxSpin = math.max(maxSpin, math.abs(math.deg(r.hull.AssemblyAngularVelocity.Magnitude)))
			if r.tele.grounded == 0 then
				airborne += 1
			end
		end
		return hold(target, v)
	end, function(_, r)
		return { z = math.round((r.hull.Position.Z - ORIGIN.Z) * 0.28 / K * 10) / 10, up = math.round(r.hull.CFrame.UpVector.Y * 100) / 100 }
	end)
	local last = samples[#samples]
	local heading = math.atan2(-rig.hull.CFrame.LookVector.X, -rig.hull.CFrame.LookVector.Z)
	local out = {
		test = "wall",
		id = id,
		kph = kph,
		angle = angle,
		speedInKph = math.round(vIn * 3.6),
		hitAt = math.round(tHit * 100) / 100,
		turnedDeg = math.round(math.deg(heading - startHeading) * 10) / 10,
		minUp = math.round(peakUp * 100) / 100,
		maxSpinDegS = math.round(maxSpin),
		airborneSteps = airborne,
		finalKph = last.kph,
		finalZ = last.z,
		wallZ = math.round(-420 * 0.28 / K * 10) / 10,
		flipped = flipped(rig),
		samples = samples,
	}
	wall:Destroy()
	model:Destroy()
	return out
end

-- A ramp of `degrees`, 30 studs long, taken at `kph`: how long it flies, how it lands, whether it flips or
-- bounces more than once.
function DriveTest.Ramp(id: string, kph: number, degrees: number): { [string]: any }
	local g = ground()
	local ramp = Instance.new("Part")
	ramp.Name = "Jump"
	ramp.Anchored = true
	ramp.Material = Enum.Material.Asphalt
	ramp.Size = Vector3.new(40, 2, 30)
	local rad = math.rad(degrees)
	-- the top face's low edge sits on the road at z = -300 and rises toward -Z
	ramp.CFrame = CFrame.new(ORIGIN + Vector3.new(0, 0, -300 - 15 * math.cos(rad))) * CFrame.Angles(rad, 0, 0) * CFrame.new(0, -1, 0)
	ramp.Parent = g
	local model, rig = DriveTest.Spawn(id)
	local target = kph / 3.6
	local airSteps, flights, inAir = 0, 0, false
	local maxHeight, landUp, landPitch, landRoll = 0, 1, 0, 0
	local y0 = rig.hull.Position.Y
	local samples = drive(rig, 14, 0.25, function(t, r, v)
		if r.hull.Position.Z < ORIGIN.Z - 290 then
			local a = r.tele.grounded == 0
			if a then
				airSteps += 1
			end
			if a and not inAir then
				flights += 1
			end
			if not a and inAir then
				landUp = math.min(landUp, r.hull.CFrame.UpVector.Y)
				landPitch = math.max(landPitch, math.abs(math.deg(math.asin(math.clamp(r.hull.CFrame.LookVector.Y, -1, 1)))))
				landRoll = math.max(landRoll, math.abs(math.deg(math.asin(math.clamp(r.hull.CFrame.RightVector.Y, -1, 1)))))
			end
			inAir = a
			maxHeight = math.max(maxHeight, (r.hull.Position.Y - y0) * 0.28 / K)
		end
		if r.hull.Position.Z < ORIGIN.Z - 520 then
			return { throttle = 0, steer = 0, handbrake = 0, boost = false }
		end
		return hold(target, v)
	end)
	local out = {
		test = "ramp",
		id = id,
		kph = kph,
		degrees = degrees,
		airSteps = airSteps,
		flights = flights,
		peakHeightM = math.round(maxHeight * 10) / 10,
		landMinUp = math.round(landUp * 100) / 100,
		landPitchDeg = math.round(landPitch),
		landRollDeg = math.round(landRoll),
		flipped = flipped(rig),
		samples = samples,
	}
	ramp:Destroy()
	model:Destroy()
	return out
end

-- Parked for `seconds`: does it stay where it is, and level.
function DriveTest.Rest(id: string, seconds: number?): { [string]: any }
	local model, rig = DriveTest.Spawn(id)
	local start = rig.hull.Position
	local startCf = rig.hull.CFrame
	local lo, hi = math.huge, -math.huge
	local samples = drive(rig, seconds or 8, 1, function()
		lo = math.min(lo, rig.hull.Position.Y)
		hi = math.max(hi, rig.hull.Position.Y)
		return { throttle = 0, steer = 0, handbrake = 1, boost = false }
	end, function(_, r)
		local tele = r.tele
		return {
			y = math.round(r.hull.Position.Y * 1000) / 1000,
			comp = string.format("%.3f %.3f %.3f %.3f", tele.compression[1], tele.compression[2], tele.compression[3], tele.compression[4]),
			vel = math.round(r.hull.AssemblyLinearVelocity.Magnitude * 1000) / 1000,
		}
	end)
	local out = {
		test = "rest",
		id = id,
		moved = math.round((rig.hull.Position - start).Magnitude * 1000) / 1000,
		yawDeg = math.round(math.deg(select(2, startCf:ToObjectSpace(rig.hull.CFrame):ToEulerAnglesYXZ())) * 100) / 100,
		yRange = math.round((hi - lo) * 1000) / 1000,
		samples = samples,
	}
	model:Destroy()
	return out
end

-- Parked on a slope of `degrees`, handbrake on; and again with nothing on: does it hold, and does it
-- roll the way a real car would.
function DriveTest.Slope(id: string, degrees: number, handbrake: boolean): { [string]: any }
	ground()
	local ramp = Instance.new("Part")
	ramp.Name = "Ramp"
	ramp.Anchored = true
	ramp.Material = Enum.Material.Asphalt
	ramp.Size = Vector3.new(60, 2, 400)
	ramp.CFrame = CFrame.new(ORIGIN + Vector3.new(300, 0, -400)) * CFrame.Angles(math.rad(degrees), 0, 0)
	ramp.Parent = workspace.DriveTestGround
	clear()
	local kind = Vehicles.Get(id)
	assert(kind)
	local layout = CarBody.Layout(kind)
	-- On the ramp's upper face, at its middle, facing up the slope.
	local base = ramp.CFrame * CFrame.new(0, 1 + layout.hullY + 0.1, 0)
	local chassis = VehicleChassis.Build(kind, base, nil, nil)
	chassis.model:SetAttribute("DriveTest", true)
	chassis.model:SetAttribute("Driven", true)
	chassis.model.Parent = workspace
	for _ = 1, 30 do
		RunService.Heartbeat:Wait()
	end
	local rig = CarPhysics.Rig(chassis.model)
	assert(rig)
	K = rig.spec.scale
	local p0 = rig.hull.Position
	local samples = drive(rig, 10, 2, function()
		return { throttle = 0, steer = 0, handbrake = if handbrake then 1 else 0, boost = false }
	end, function(_, r)
		return { slid = math.round((r.hull.Position - p0).Magnitude * 0.28 / K * 100) / 100 }
	end)
	local moved = (rig.hull.Position - p0).Magnitude * 0.28 / K
	ramp:Destroy()
	chassis.model:Destroy()
	return { test = "slope", id = id, degrees = degrees, handbrake = handbrake, movedMetres = math.round(moved * 100) / 100, samples = samples }
end

-- A kerb, `height` studs tall, across the road, taken at `kph`.
function DriveTest.Kerb(id: string, kph: number, height: number): { [string]: any }
	local g = ground()
	local kerb = Instance.new("Part")
	kerb.Name = "Kerb"
	kerb.Anchored = true
	kerb.Size = Vector3.new(40, height, 3)
	kerb.Position = ORIGIN + Vector3.new(0, height / 2, -500)
	kerb.Parent = g
	local model, rig = DriveTest.Spawn(id)
	local target = kph / 3.6
	local maxPitch, maxRoll, airborne = 0, 0, 0
	local samples = drive(rig, 40, 2, function(_, r, v)
		if r.hull.Position.Z < ORIGIN.Z - 560 then
			return nil
		end
		maxPitch = math.max(maxPitch, math.abs(r.hull.CFrame.LookVector.Y))
		maxRoll = math.max(maxRoll, math.abs(r.hull.CFrame.RightVector.Y))
		if r.tele.grounded == 0 then
			airborne += 1
		end
		return hold(target, v)
	end)
	local out = {
		test = "kerb",
		id = id,
		kph = kph,
		height = height,
		pitchDeg = math.round(math.deg(math.asin(maxPitch)) * 10) / 10,
		rollDeg = math.round(math.deg(math.asin(maxRoll)) * 10) / 10,
		airborneSteps = airborne,
		flipped = flipped(rig),
		samples = samples,
	}
	kerb:Destroy()
	model:Destroy()
	return out
end

-- A lane change at `kph`: steer `input` one way for 0.8 s, straight for 0.4 s, back the other way for
-- 0.8 s, then straight. Reports how hard it was taken and whether the car came out straight.
function DriveTest.LaneChange(id: string, kph: number, input: number): { [string]: any }
	local model, rig = DriveTest.Spawn(id)
	local target = kph / 3.6
	local peakLat, peakRoll, peakYaw = 0, 0, 0
	local startX = rig.hull.Position.X
	local samples = drive(rig, 14, 0.5, function(t, r, v)
		local c = hold(target, v)
		local u = t - 7
		if u > 0 and u < 0.8 then
			c.steer = input
		elseif u > 1.2 and u < 2.0 then
			c.steer = -input
		end
		if u > 0 and u < 4 then
			peakLat = math.max(peakLat, math.abs(r.tele.latG))
			peakRoll = math.max(peakRoll, math.abs(math.deg(math.asin(r.hull.CFrame.RightVector.Y))))
			peakYaw = math.max(peakYaw, math.abs(math.deg(r.hull.AssemblyAngularVelocity.Y)))
		end
		return c
	end, function(_, r)
		return {
			x = math.round((r.hull.Position.X - startX) * 0.28 / K * 10) / 10,
			heading = math.round(math.deg(math.atan2(-r.hull.CFrame.LookVector.X, -r.hull.CFrame.LookVector.Z)) * 10) / 10,
		}
	end)
	local last = samples[#samples]
	local out = {
		test = "lane",
		id = id,
		kph = kph,
		input = input,
		peakLatG = math.round(peakLat * 100) / 100,
		peakRollDeg = math.round(peakRoll * 10) / 10,
		peakYawRate = math.round(peakYaw),
		offsetMetres = last.x,
		endHeadingDeg = last.heading,
		flipped = flipped(rig),
		samples = samples,
	}
	model:Destroy()
	return out
end

-- Handbrake turn at `kph`: wheel over and the handbrake for 1.5 s, then both released.
function DriveTest.Handbrake(id: string, kph: number): { [string]: any }
	local model, rig = DriveTest.Spawn(id)
	local target = kph / 3.6
	local peakSlide = 0
	local function slipAngle(r: Rig): number
		local vel = r.hull.AssemblyLinearVelocity
		return math.deg(math.atan2(vel:Dot(r.hull.CFrame.RightVector), math.max(math.abs(vel:Dot(r.hull.CFrame.LookVector)), 1)))
	end
	local samples = drive(rig, 12, 0.5, function(t, r, v)
		local c = hold(target, v)
		local u = t - 6
		if u > 0 and u < 1.5 then
			c = { throttle = 0, steer = 1, handbrake = 1, boost = false }
		elseif u >= 1.5 then
			c = { throttle = 0.3, steer = 0, handbrake = 0, boost = false }
		end
		if u > 0 then
			peakSlide = math.max(peakSlide, math.abs(slipAngle(r)))
		end
		return c
	end, function(_, r)
		return { slipAngle = math.round(slipAngle(r) * 10) / 10, yaw = math.round(math.deg(r.hull.AssemblyAngularVelocity.Y)) }
	end)
	local out = { test = "handbrake", id = id, kph = kph, peakSlideAngle = math.round(peakSlide), flipped = flipped(rig), samples = samples }
	model:Destroy()
	return out
end

-- A drift as a player does it: up to `kph`, then into the turn with the wheel held over, a tap of the
-- handbrake (`tap` seconds), and the throttle down; the wheel stays where it is. Logs the slide angle
-- and speed so one can see whether it settles into a slide or spins out.
function DriveTest.Drift(id: string, kph: number, tap: number, steer: number): { [string]: any }
	local model, rig = DriveTest.Spawn(id)
	local target = kph / 3.6
	local peak, spun = 0, false
	local function slipAngle(r: Rig): number
		local vel = r.hull.AssemblyLinearVelocity
		return math.deg(math.atan2(vel:Dot(r.hull.CFrame.RightVector), math.max(math.abs(vel:Dot(r.hull.CFrame.LookVector)), 1)))
	end
	local samples = drive(rig, 14, 0.5, function(t, r, v)
		local u = t - 6
		if u < 0 then
			return hold(target, v)
		end
		local c: Controls = { throttle = if u < tap then 0.4 else 1, steer = steer, handbrake = if u < tap then 1 else 0, boost = false }
		peak = math.max(peak, math.abs(slipAngle(r)))
		if math.abs(slipAngle(r)) > 120 then
			spun = true
		end
		return c
	end, function(_, r)
		return { slip = math.round(slipAngle(r)), yaw = math.round(math.deg(r.hull.AssemblyAngularVelocity.Y)) }
	end)
	local out = { test = "drift", id = id, kph = kph, tap = tap, peakSlide = math.round(peak), spunOut = spun, flipped = flipped(rig), samples = samples }
	model:Destroy()
	return out
end

-- From rest: reverse for 8 s, then full throttle forward: how fast it goes back, and the swing.
function DriveTest.Reverse(id: string): { [string]: any }
	local model, rig = DriveTest.Spawn(id)
	local topBack = 0
	local samples = drive(rig, 14, 1, function(t, _, v)
		if t < 8 then
			topBack = math.max(topBack, -v)
			return { throttle = -1, steer = 0, handbrake = 0, boost = false }
		end
		return { throttle = 1, steer = 0, handbrake = 0, boost = false }
	end)
	local out = { test = "reverse", id = id, topReverseKph = math.round(topBack * 3.6), samples = samples }
	model:Destroy()
	return out
end

-- Every step's suspension numbers for the first wheel, after the car is dropped `drop` studs.
function DriveTest.Bounce(id: string, drop: number, steps: number): { [string]: any }
	local model, rig = DriveTest.Spawn(id, Vector3.new(0, drop, 0))
	local rows = {}
	local t = 0
	for i = 1, steps do
		local frame = RunService.PreSimulation:Wait()
		local dt = math.min(frame, 1 / 30)
		local tele = CarPhysics.Step(rig, dt, { throttle = 0, steer = 0, handbrake = 1, boost = false })
		t += dt
		local w = rig.wheels[1]
		if i % 3 == 1 then
			table.insert(rows, string.format("t=%.2f dt=%.4f y=%.3f vy=%.2f comp=%.3f rate=%.2f load/pre=%.2f hit=%s", t, dt, rig.hull.Position.Y, rig.hull.AssemblyLinearVelocity.Y, w.compress, w.rate, w.load / (rig.hull.AssemblyMass * w.share * workspace.Gravity), tostring(w.hit)))
		end
	end
	model:Destroy()
	return { test = "bounce", rows = rows }
end

-- Flat out from rest for `seconds`, logging each 0.25 s what the tyres were told to push with against
-- what the car actually did: the force written onto the tyres, its forward share, and the
-- acceleration that would make and the one measured.
function DriveTest.Probe(id: string, seconds: number): { [string]: any }
	local model, rig = DriveTest.Spawn(id)
	local rows = {}
	local t, nextLog = 0, 0
	local lastV, lastT = 0, 0
	local startClock = os.clock()
	while t < seconds do
		local frame = RunService.PreSimulation:Wait()
		local tele = CarPhysics.Step(rig, math.min(frame, 1 / 30), { throttle = 1, steer = 0, handbrake = 0, boost = false })
		t = os.clock() - startClock
		if t >= nextLog then
			nextLog += 0.25
			local fwd = rig.hull.CFrame.LookVector
			local sum, sumF = Vector3.zero, 0
			local parts = {}
			for i, w in rig.wheels do
				local f = if w.tyre then w.tyre.Force else Vector3.zero
				sum += f
				sumF += f:Dot(fwd)
				table.insert(parts, string.format("%.0f", f:Dot(fwd)))
			end
			local v = rig.hull.AssemblyLinearVelocity:Dot(fwd)
			local measured = (v - lastV) / math.max(t - lastT, 1e-3)
			lastV, lastT = v, t
			table.insert(rows, string.format("t=%.2f v=%.1f st/s thrust=%.0f mass=%.1f expect=%.1f measured=%.1f st/s2 | per wheel %s | vy=%.2f yaw=%.3f", t, v, sumF, rig.hull.AssemblyMass, sumF / rig.hull.AssemblyMass, measured, table.concat(parts, " "), rig.hull.AssemblyLinearVelocity.Y, rig.hull.AssemblyAngularVelocity.Y))
		end
	end
	model:Destroy()
	return { test = "probe", rows = rows }
end

-- A car standing on the test road for looking at and driving by hand: the real parked-car loop steps
-- it, and `player`, if given, is put behind the wheel.
function DriveTest.Show(id: string, paintKey: string?, player: Player?): Model
	ground()
	clear()
	local kind = Vehicles.Get(id)
	assert(kind, "no such car " .. id)
	local layout = CarBody.Layout(kind)
	local look = CarBody.LookOf(paintKey, nil, nil)
	local chassis = VehicleChassis.Build(kind, CFrame.new(ORIGIN + Vector3.new(0, layout.hullY + 0.3, -60)), nil, look)
	chassis.model.Name = "Vehicle_show"
	chassis.model:SetAttribute("DriveTest", true)
	chassis.model.Parent = workspace
	for _ = 1, 90 do
		RunService.Heartbeat:Wait()
	end
	if player then
		player:LoadCharacter()
		task.wait(1.5)
		local character = player.Character :: Model
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				part.CollisionGroup = "VehicleDrivers"
			end
		end
		character:PivotTo(chassis.seat.CFrame * CFrame.new(0, 2.5, 0))
		task.wait(0.05)
		chassis.seatDriver(humanoid)
	end
	return chassis.model
end

-- Every car in `ids` (all of them if nil), built at rest and anchored on the test road in rows of `cols`,
-- nose to -Z, 26 studs apart: for looking at. Returns where the first one stands and the spacing.
function DriveTest.Gallery(ids: { string }?, cols: number?): (Vector3, number)
	ground()
	for _, m in workspace:GetChildren() do
		if m.Name == "DriveTestGallery" then
			m:Destroy()
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "DriveTestGallery"
	folder.Parent = workspace
	local list: { string } = {}
	if ids then
		list = ids
	else
		for _, kind in Vehicles.All do
			table.insert(list, kind.id)
		end
	end
	local perRow = cols or 6
	local spacing = 26
	for index, id in list do
		local kind = Vehicles.Get(id)
		if kind == nil then
			continue
		end
		local layout = CarBody.Layout(kind)
		local col, row = (index - 1) % perRow, (index - 1) // perRow
		local pos = ORIGIN + Vector3.new(col * spacing, layout.hullY + 0.05, row * spacing)
		local built = CarBody.Build(kind, CFrame.new(pos), if kind.model ~= nil then Color3.fromRGB(215, 218, 224) else nil, nil)
		CarBody.Anchor(built)
		built.model.Name = "Gallery_" .. id
		built.model.Parent = folder
	end
	return ORIGIN, spacing
end

-- Runs each of `list` ({ name, args, skip }) in turn, in the background, and appends a line for each to
-- workspace's DriveTestLog (a StringValue): the result without its samples. Read it while it runs.
function DriveTest.Suite(list: { { any } })
	local log = workspace:FindFirstChild("DriveTestLog") :: StringValue?
	if log == nil then
		local made = Instance.new("StringValue")
		made.Name = "DriveTestLog"
		made.Parent = workspace
		log = made
	end
	assert(log)
	log.Value = ""
	task.spawn(function()
		for _, item in list do
			DriveTest.Skip = item.skip or 1
			local ok, result = pcall(function()
				return (DriveTest :: any)[item[1]](table.unpack(item[2]))
			end)
			local line
			if ok then
				result.samples = nil
				result.rows = nil
				line = HttpService:JSONEncode(result)
			else
				line = "ERROR " .. tostring(result)
			end
			log.Value ..= string.format("[%s %s skip=%d] %s\n", item[1], HttpService:JSONEncode(item[2]), item.skip or 1, line)
		end
		DriveTest.Skip = 1
		log.Value ..= "DONE\n"
	end)
end

-- Runs a test in the background and leaves its result in workspace's DriveTestResult.
function DriveTest.Start(name: string, ...: any)
	local args = { ... }
	local out = workspace:FindFirstChild("DriveTestResult") :: StringValue?
	if out == nil then
		local made = Instance.new("StringValue")
		made.Name = "DriveTestResult"
		made.Parent = workspace
		out = made
	end
	assert(out)
	out.Value = "running " .. name
	task.spawn(function()
		local ok, result = pcall(function()
			return (DriveTest :: any)[name](table.unpack(args))
		end)
		out.Value = if ok then HttpService:JSONEncode(result) else "ERROR " .. tostring(result)
	end)
end

return DriveTest
