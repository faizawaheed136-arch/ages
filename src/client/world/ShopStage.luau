--!strict
--[[
	The dealership shop's stage: a white round hall, built on this client alone far out of the map,
	where a car chosen in the shop turns on a lit turntable and the camera orbits it. The shop's list
	is a menu; this is the showroom it opens onto -- the part of buying a car that is looking at it.

	Everything here is local: the hall, the car, the lights. Nobody else sees a player's stage, and
	nothing on it collides with anything. The car is drawn by shared/CarBody, so it is the car the
	player will drive away, down to the paint they pick.

	Drag to turn the view; the wheel (or a pinch) to come closer or stand back. Left alone, the
	turntable turns.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CarBody = require(ReplicatedStorage:WaitForChild("CarBody"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type VehicleKind = Types.VehicleKind

-- Where the hall stands: straight up, well above anything any map here builds, and out of the way
-- of a player's own streaming radius.
local ORIGIN = CFrame.new(0, 1600, 0)
local HALL_RADIUS = 58
local HALL_HEIGHT = 30
local TURNTABLE_DIAMETER = 26
local TURNTABLE_HEIGHT = 0.8
-- Seconds for the turntable to go round once.
local TURN_SECONDS = 26
-- The view: how far out, how high, and how far it may be zoomed either way.
local VIEW_PITCH = math.rad(11)
local VIEW_MIN, VIEW_MAX = 12, 40
local DRAG_RATE = 0.008
local ZOOM_STEP = 2.5

-- A shade off white throughout: pure white under the showroom's lamps and bloom reads as a glare
-- with a car lost in it.
local WHITE = Color3.fromRGB(222, 225, 231)
local FLOOR = Color3.fromRGB(204, 208, 215)
local LANE = Color3.fromRGB(176, 181, 190)
local LED = Color3.fromRGB(196, 204, 222)
local ACCENT = Color3.fromRGB(34, 96, 210)

local ShopStage = {}
ShopStage.__index = ShopStage

export type Stage = typeof(setmetatable(
	{} :: {
		folder: Model,
		turntable: BasePart,
		car: Model?,
		carCentre: CFrame,
		spin: number,
		yaw: number,
		distance: number,
		autoSpin: boolean,
		active: boolean,
		dragging: boolean,
		connections: { RBXScriptConnection },
		savedCameraType: Enum.CameraType?,
		savedSubject: Instance?,
		-- The city's atmosphere, held while the stage is up: its haze is weather, and the hall is a
		-- room -- through it the car was a pastel of itself.
		savedAtmosphere: { density: number, haze: number, glare: number }?,
	},
	ShopStage
))

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function disc(parent: Instance, name: string, diameter: number, height: number, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = part(parent, name, Vector3.new(height, diameter, diameter), cframe * CFrame.Angles(0, 0, math.rad(90)), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- The hall: a gloss floor with lanes curving across it, a wall of white panels studded with light
-- in diamonds, a ceiling ringed with light, and the turntable in the middle.
local function buildHall(folder: Model): BasePart
	local floor = disc(folder, "Floor", HALL_RADIUS * 2, 1, ORIGIN * CFrame.new(0, -0.5, 0), FLOOR, Enum.Material.SmoothPlastic)
	floor.Reflectance = 0.1
	-- Two lanes, like a road drawn across the floor, curving round the turntable.
	for _, side in { -1, 1 } do
		for i = 0, 17 do
			local a = math.rad(-80 + i * 9.5)
			local r = 24
			local cf = ORIGIN * CFrame.new(side * r * math.cos(a) * 1.2, 0.01, r * math.sin(a)) * CFrame.Angles(0, -a * side, 0)
			part(folder, "Lane", Vector3.new(3.2, 0.04, 4.6), cf, LANE, Enum.Material.SmoothPlastic)
		end
	end
	local panels = 36
	for i = 0, panels - 1 do
		local a = i / panels * math.pi * 2
		local cf = ORIGIN * CFrame.Angles(0, a, 0) * CFrame.new(0, HALL_HEIGHT / 2, -HALL_RADIUS)
		local width = HALL_RADIUS * 2 * math.pi / panels + 0.2
		part(folder, "Wall", Vector3.new(width, HALL_HEIGHT, 1), cf, WHITE, Enum.Material.SmoothPlastic)
		-- Light in diamonds on every other panel, the way a showroom wall is lit.
		if i % 2 == 0 then
			for row = 0, 5 do
				for col = -2, 2 do
					if (row + col) % 2 == 0 then
						local led = part(folder, "Led", Vector3.new(0.7, 0.7, 0.1), cf * CFrame.new(col * 1.4, 4 + row * 1.6 - HALL_HEIGHT / 2 + 8, 0.55) * CFrame.Angles(0, 0, math.rad(45)), LED, Enum.Material.Neon)
						led.CastShadow = false
					end
				end
			end
		end
	end
	disc(folder, "Ceiling", HALL_RADIUS * 2, 1, ORIGIN * CFrame.new(0, HALL_HEIGHT + 0.5, 0), WHITE, Enum.Material.SmoothPlastic)
	for _, r in { 14, 30, 46 } do
		local segments = math.floor(r * 1.6)
		for i = 0, segments - 1 do
			local a = i / segments * math.pi * 2
			local ring = part(folder, "CeilingRing", Vector3.new(0.5, 0.2, r * 2 * math.pi / segments * 1.05), ORIGIN * CFrame.new(r * math.cos(a), HALL_HEIGHT - 0.1, r * math.sin(a)) * CFrame.Angles(0, -a, 0), LED, Enum.Material.Neon)
			ring.CastShadow = false
		end
	end
	-- One soft lamp overhead, and the walls of light do the rest. Tried with a stronger wash and a
	-- ring of fill lamps round the car, in Studio: the floor went white-hot and a red car read pink.
	local sun = part(folder, "Lamp", Vector3.new(1, 1, 1), ORIGIN * CFrame.new(0, HALL_HEIGHT - 1, 0), LED, Enum.Material.SmoothPlastic)
	sun.Transparency = 1
	local wash = Instance.new("PointLight")
	wash.Brightness = 0.35
	wash.Range = 40
	wash.Shadows = true
	wash.Parent = sun
	disc(folder, "TurntableRing", TURNTABLE_DIAMETER + 1, TURNTABLE_HEIGHT - 0.3, ORIGIN * CFrame.new(0, (TURNTABLE_HEIGHT - 0.3) / 2, 0), ACCENT, Enum.Material.Neon)
	local turntable = disc(folder, "Turntable", TURNTABLE_DIAMETER, TURNTABLE_HEIGHT, ORIGIN * CFrame.new(0, TURNTABLE_HEIGHT / 2, 0), WHITE, Enum.Material.SmoothPlastic)
	turntable.Reflectance = 0.12
	return turntable
end

function ShopStage.new(): Stage
	local folder = Instance.new("Model")
	folder.Name = "DealershipShopStage"
	local turntable = buildHall(folder)
	local self = setmetatable({
		folder = folder,
		turntable = turntable,
		car = nil,
		carCentre = ORIGIN * CFrame.new(0, TURNTABLE_HEIGHT, 0),
		spin = 0,
		yaw = math.rad(-35),
		distance = 24,
		autoSpin = true,
		active = false,
		dragging = false,
		connections = {},
		savedCameraType = nil,
		savedSubject = nil,
		savedAtmosphere = nil,
	}, ShopStage)
	return self
end

-- Puts `kind` on the turntable in `paint`, replacing whatever was there.
function ShopStage.Show(self: Stage, kind: VehicleKind, paint: Color3?)
	if self.car then
		self.car:Destroy()
		self.car = nil
	end
	local ground = self.carCentre * CFrame.Angles(0, self.spin, 0)
	local built = CarBody.Build(kind, CarBody.RestOn(kind, ground), paint)
	CarBody.Anchor(built)
	for _, d in built.model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	built.model.Parent = self.folder
	self.car = built.model
	-- Stand back far enough for the car's length.
	self.distance = math.clamp(kind.size.Z * 0.85 + 5, VIEW_MIN, VIEW_MAX)
end

function ShopStage.SetAutoSpin(self: Stage, on: boolean)
	self.autoSpin = on
end

function ShopStage.ResetView(self: Stage)
	self.yaw = math.rad(-35)
	self.spin = 0
end

local function place(self: Stage)
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local target = self.carCentre.Position + Vector3.new(0, 2.2, 0)
	local offset = CFrame.Angles(0, self.yaw, 0) * CFrame.Angles(-VIEW_PITCH, 0, 0) * Vector3.new(0, 0, self.distance)
	camera.CFrame = CFrame.lookAt(target + offset, target)
end

-- Takes the camera to the stage and starts the turntable.
function ShopStage.Enter(self: Stage)
	if self.active then
		return
	end
	self.active = true
	self.folder.Parent = workspace
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		self.savedAtmosphere = { density = atmosphere.Density, haze = atmosphere.Haze, glare = atmosphere.Glare }
		atmosphere.Density = 0
		atmosphere.Haze = 0
		atmosphere.Glare = 0
	end
	local camera = workspace.CurrentCamera
	if camera then
		self.savedCameraType = camera.CameraType
		self.savedSubject = camera.CameraSubject
		camera.CameraType = Enum.CameraType.Scriptable
	end
	table.insert(
		self.connections,
		RunService.RenderStepped:Connect(function(dt: number)
			if self.autoSpin and not self.dragging and self.car then
				self.spin = (self.spin + dt * math.pi * 2 / TURN_SECONDS) % (math.pi * 2)
				local car = self.car :: Model
				local kindCentre = car.PrimaryPart
				if kindCentre then
					local height = kindCentre.CFrame.Position.Y - self.carCentre.Position.Y
					car:PivotTo(self.carCentre * CFrame.Angles(0, self.spin, 0) * CFrame.new(0, height, 0))
				end
				self.turntable.CFrame = self.carCentre * CFrame.new(0, -TURNTABLE_HEIGHT / 2, 0) * CFrame.Angles(0, self.spin, 0) * CFrame.Angles(0, 0, math.rad(90))
			end
			place(self)
		end)
	)
	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				self.dragging = true
			end
		end)
	)
	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				self.dragging = false
			end
		end)
	)
	table.insert(
		self.connections,
		UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
			if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
				self.distance = math.clamp(self.distance - input.Position.Z * ZOOM_STEP, VIEW_MIN, VIEW_MAX)
			elseif self.dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				self.yaw -= input.Delta.X * DRAG_RATE
			end
		end)
	)
	table.insert(
		self.connections,
		UserInputService.TouchPinch:Connect(function(_, scale: number, _velocity: number, state: Enum.UserInputState)
			if state == Enum.UserInputState.Change then
				self.distance = math.clamp(self.distance / math.max(scale, 0.1), VIEW_MIN, VIEW_MAX)
			end
		end)
	)
end

-- Gives the camera back and takes the hall away.
function ShopStage.Leave(self: Stage)
	if not self.active then
		return
	end
	self.active = false
	self.dragging = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.folder.Parent = nil
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local saved = self.savedAtmosphere
	if atmosphere and saved then
		atmosphere.Density = saved.density
		atmosphere.Haze = saved.haze
		atmosphere.Glare = saved.glare
	end
	self.savedAtmosphere = nil
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = self.savedCameraType or Enum.CameraType.Custom
		if self.savedSubject then
			camera.CameraSubject = self.savedSubject
		end
	end
end

return ShopStage
