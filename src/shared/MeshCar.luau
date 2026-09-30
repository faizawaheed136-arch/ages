--!strict
--[[
	A car drawn from a modelled mesh instead of parts: the GT-R the owner imported. Builds the same
	thing shared/CarBody.Build builds -- a hull that carries the mass, a model welded to it, four
	wheels that can spin and steer, lamps -- so the shop, the showroom floor and world/VehicleChassis
	treat it as any other car; they never ask how it was drawn.

	THE MODEL. ReplicatedStorage.CarModels.<kind.model>, made by tools/gen_gtr_model.py: a flat model of
	MeshParts, in metres, nose to -Z, every part at its place in the car. Names say what a part is:
	`Paint_*` is body panel, `WheelFL_Tyre` (and _Rim, _Disc, _CalliperA, _CalliperB) is a wheel,
	`Lamp_*` and `Lens_*` are lamps, `Glass_*` windows. This scales it up to the world (a stud is 0.28
	m) and sets its parts on a hull at the car's real centre-of-mass height, so its wheels touch the
	ground exactly when its suspension is at rest.

	PAINT. A textured MeshPart ignores its Color, so the paint panels carry a SurfaceAppearance (named
	Tint, authored into the model by tools/gen_gtr_model.py: a script cannot write its ColorMap) whose
	ColorMap is the panel's own texture and whose Color this sets: white panels take the paint whole,
	the dark shut-lines and badges stay dark.

	LAMPS are textured too, so they cannot be recoloured -- a lamp glows by its Material going Neon,
	and by a light it carries. world/VehicleChassis does both, off `built.lamps`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarSpec = require(ReplicatedStorage:WaitForChild("CarSpec"))

local MeshCar = {}

local S = CarSpec.StudsPerMetre
MeshCar.Scale = S

-- Same hull recipe as CarBody: a box that carries a fifth of the mass, four corner weights the rest,
-- so the car resists pitching and rolling like a real one.
local HULL_MASS_PER_STUD2 = 0.7 * 2.8
local BALLAST_SHARE = 0.8
-- The hull is what the world bumps into. Its underside rides this high over the road, which is what
-- lets a car cross a kerb.
local HULL_BOTTOM = 1.5
-- The spring's length at rest, beyond its travel in bump: what is left of it when fully compressed.
local SPRING_MARGIN = 0.3
-- How high the driver's seat is over the road, and how high the roof collider reaches, in studs.
local SEAT_TOP = 0.75
local ROOF_TOP = 4.7

local function templateOf(name: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("CarModels")
	local model = if folder then folder:FindFirstChild(name) else nil
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

-- Whether the model `name` is in this place.
function MeshCar.Available(name: string?): boolean
	return name ~= nil and templateOf(name) ~= nil
end

local function part(template: Model, name: string): BasePart
	local found = template:FindFirstChild(name)
	assert(found and found:IsA("BasePart"), `[CarModels] {template.Name} has no part {name}`)
	return found
end

type Measured = {
	template: Model,
	spec: CarSpec.Spec,
	-- Model space, metres.
	hullCentre: Vector3,
	groundY: number,
	frontZ: number,
	rearZ: number,
	radius: number, -- tyre radius, metres
	width: number, -- tyre width, metres
	halfTrack: number,
	-- The steering wheel's place, model space, metres: where the driver sits comes from it.
	wheelX: number,
	wheelZ: number,
}

local function measure(name: string, spec: CarSpec.Spec): Measured
	local template = templateOf(name) :: Model
	local fl, fr = part(template, "WheelFL_Tyre"), part(template, "WheelFR_Tyre")
	local rl = part(template, "WheelRL_Tyre")
	local steering = part(template, "SteeringWheel")
	local radius = fl.Size.Y / 2
	local groundY = fl.Position.Y - radius
	local frontZ, rearZ = fl.Position.Z, rl.Position.Z
	-- The hull is centred between the axles, at the height the car's weight acts.
	local centre = Vector3.new(0, groundY + spec.cgHeight, (frontZ + rearZ) / 2)
	return {
		template = template,
		spec = spec,
		hullCentre = centre,
		groundY = groundY,
		frontZ = frontZ,
		rearZ = rearZ,
		radius = radius,
		width = fl.Size.X,
		halfTrack = (math.abs(fl.Position.X) + math.abs(fr.Position.X)) / 2,
		wheelX = steering.Position.X,
		wheelZ = steering.Position.Z,
	}
end

-- Hull-local studs, from a point in the model's space.
local function toHull(m: Measured, p: Vector3): Vector3
	return (p - m.hullCentre) * S
end

-- CarBody.Layout's shape, for a modelled car. `kind` supplies the spec through its id.
function MeshCar.Layout(kind: any, spec: CarSpec.Spec): any
	local m = measure(kind.model, spec)
	local sizeZ = kind.size.Z
	local width = kind.size.X
	local hullTop = spec.cgHeight * S + 0.4
	local hullSize = Vector3.new(m.halfTrack * 2 * S - m.width * S - 0.5, hullTop - HULL_BOTTOM, sizeZ - 1.2)
	local mass = HULL_MASS_PER_STUD2 * hullSize.X * hullSize.Z
	local hullY = spec.cgHeight * S
	local axleFront = (m.frontZ - m.hullCentre.Z) * S
	local axleRear = (m.rearZ - m.hullCentre.Z) * S
	-- The corner weights are set so the centre of mass falls where the spec says the weight is: a
	-- front-heavy car has more of it at the front.
	local comZ = axleFront + (1 - spec.weightFront) * (axleRear - axleFront)
	local reach = sizeZ / 2 - 1.5
	local frontShare = math.clamp((1 - comZ / (BALLAST_SHARE * reach)) / 2, 0.2, 0.8)
	local ballastMass = mass * BALLAST_SHARE / 4
	local radiusStuds = m.radius * S
	local ride = spec.travelBump * S + SPRING_MARGIN
	return {
		style = nil,
		length = sizeZ,
		width = width,
		midShare = 0.5,
		hullSize = hullSize,
		hullDensity = mass * (1 - BALLAST_SHARE) / (hullSize.X * hullSize.Y * hullSize.Z),
		ballastMass = ballastMass,
		ballastWeights = {
			ballastMass * 4 * frontShare / 2,
			ballastMass * 4 * frontShare / 2,
			ballastMass * 4 * (1 - frontShare) / 2,
			ballastMass * 4 * (1 - frontShare) / 2,
		},
		ballast = {
			Vector3.new(-(width / 2 - 0.6), 0, -reach),
			Vector3.new(width / 2 - 0.6, 0, -reach),
			Vector3.new(-(width / 2 - 0.6), 0, reach),
			Vector3.new(width / 2 - 0.6, 0, reach),
		},
		hullY = hullY,
		mountY = radiusStuds + ride - hullY,
		axleFront = axleFront,
		axleRear = axleRear,
		track = m.halfTrack * S,
		wheelRadius = radiusStuds,
		wheelWidth = m.width * S,
		-- The driver sits behind the steering wheel, on its side of the car: the seat's top a thigh's
		-- height off the road, a little nearer the middle than the wheel so an avatar's shoulders, which
		-- are wider than a driver's, stay inside the door, and back from the wheel by an arm's reach.
		seat = Vector3.new(m.wheelX * S * 0.5, SEAT_TOP - 0.5 - hullY, (m.wheelZ + 0.6 - m.hullCentre.Z) * S),
		springRide = ride,
		springBump = spec.travelBump * S,
		springDroop = spec.travelDroop * S,
		comZ = comZ,
		mesh = true,
	}
end

local PAINT_PREFIX = "Paint_"
local LAMP_PREFIX = "Lamp_"

--[[
	The car built with its hull's centre at `cframe`, painted `paintColor` (and wearing `rims`' colour
	on its rims if given). Nothing is anchored and nothing is welded; riders lists every part and what it
	rides on, for CarBody.Weld.
]]
function MeshCar.Build(kind: any, spec: CarSpec.Spec, cframe: CFrame, paintColor: Color3?, rimColor: Color3?, glow: Color3?): any
	local m = measure(kind.model, spec)
	local layout = MeshCar.Layout(kind, spec)
	local model = Instance.new("Model")
	model.Name = `Vehicle_{kind.id}`

	local hull = Instance.new("Part")
	hull.Name = "Chassis"
	hull.Size = layout.hullSize
	hull.CFrame = cframe
	hull.Transparency = 1
	hull.Anchored = false
	hull.CanCollide = true
	hull.TopSurface = Enum.SurfaceType.Smooth
	hull.BottomSurface = Enum.SurfaceType.Smooth
	hull.CustomPhysicalProperties = PhysicalProperties.new(layout.hullDensity, 0.3, 0.5)
	hull.Parent = model
	model.PrimaryPart = hull

	local paint = paintColor or kind.color
	local built = {
		model = model,
		hull = hull,
		layout = layout,
		wheels = {},
		riders = {},
		headlights = {},
		brakeLights = {},
		reverseLights = {},
		lamps = {},
		lenses = {},
		mesh = true,
	}
	local roots: { [string]: BasePart } = {}
	local wheelRider: { [string]: { BasePart } } = { FL = {}, FR = {}, RL = {}, RR = {} }

	for _, source in m.template:GetChildren() do
		if not source:IsA("MeshPart") then
			continue
		end
		local piece = source:Clone()
		piece.Size = source.Size * S
		piece.CFrame = cframe * CFrame.new(toHull(m, source.Position))
		piece.Anchored = false
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.Massless = true
		piece.Parent = model
		local name = source.Name
		local tint = piece:FindFirstChild("Tint")
		if string.sub(name, 1, #PAINT_PREFIX) == PAINT_PREFIX and tint and tint:IsA("SurfaceAppearance") then
			tint.Color = paint
		end
		local corner = string.match(name, "^Wheel(%u%u)_")
		if corner then
			local role = string.sub(name, 9)
			if role == "Tyre" or role == "Disc" then
				roots[corner .. role] = piece
			else
				table.insert(wheelRider[corner], piece)
			end
			if role == "Rim" and rimColor and tint and tint:IsA("SurfaceAppearance") then
				tint.Color = rimColor
			end
			if role ~= "Tyre" and role ~= "Disc" then
				-- Rims turn with the tyre, callipers stay with the disc.
				table.insert(built.riders, { piece, if role == "Rim" then roots[corner .. "Tyre"] else roots[corner .. "Disc"] })
			end
		else
			table.insert(built.riders, { piece, hull })
			if name == "Lens_HeadL" or name == "Lens_HeadR" then
				table.insert(built.lenses, piece)
				-- The beam starts a little ahead of the lens, which sits inside the shell of the wing.
				local aim = Instance.new("Part")
				aim.Name = "HeadlightAim"
				aim.Size = Vector3.new(0.2, 0.2, 0.2)
				aim.CFrame = piece.CFrame * CFrame.new(0, 0, -(piece.Size.Z / 2 + 0.2))
				aim.Transparency = 1
				aim.Anchored = false
				aim.CanCollide = false
				aim.CanQuery = false
				aim.CanTouch = false
				aim.Massless = true
				aim.Parent = model
				table.insert(built.riders, { aim, hull })
				table.insert(built.headlights, aim)
			elseif string.sub(name, 1, #LAMP_PREFIX) == LAMP_PREFIX then
				table.insert(built.lamps, piece)
				if name == "Lamp_RearBumper" then
					table.insert(built.reverseLights, piece)
				elseif string.find(name, "Brake") or string.find(name, "Tail") then
					table.insert(built.brakeLights, piece)
				end
			end
			if name == "SteeringWheel" then
				built.steeringWheel = piece
			end
		end
	end
	-- The rims and callipers were queued against roots that might not have been cloned yet; fix the
	-- pairings now that every root exists.
	for _, pair in built.riders do
		local piece = pair[1]
		local corner = string.match(piece.Name, "^Wheel(%u%u)_")
		if corner then
			local role = string.sub(piece.Name, 9)
			pair[2] = if role == "Rim" then roots[corner .. "Tyre"] else roots[corner .. "Disc"]
		end
	end

	for index, corner in { "FL", "FR", "RL", "RR" } do
		local tyre, disc = roots[corner .. "Tyre"], roots[corner .. "Disc"]
		local rest = cframe:PointToObjectSpace(tyre.Position)
		table.insert(built.wheels, {
			spin = tyre,
			knuckle = disc,
			front = index <= 2,
			side = if index % 2 == 1 then -1 else 1,
			rest = rest,
		})
	end

	-- The corner weights, each as heavy as its share of the car.
	for index, offset in layout.ballast do
		local weight = Instance.new("Part")
		weight.Name = "Ballast"
		weight.Size = Vector3.new(1, 1, 1)
		weight.CFrame = cframe * CFrame.new(offset)
		weight.Transparency = 1
		weight.Anchored = false
		weight.CanCollide = false
		weight.CanQuery = false
		weight.CanTouch = false
		weight.CustomPhysicalProperties = PhysicalProperties.new(layout.ballastWeights[index], 0.3, 0.5)
		weight.Parent = model
		table.insert(built.riders, { weight, hull })
	end

	-- Colliders over the cabin and the two ends, weightless: the roof can be stood on and the nose
	-- and tail are solid, while the hull alone carries the mass.
	local function collider(name: string, size: Vector3, offset: Vector3)
		local box = Instance.new("Part")
		box.Name = name
		box.Size = size
		box.CFrame = cframe * CFrame.new(offset)
		box.Transparency = 1
		box.Anchored = false
		box.CanCollide = true
		box.CanTouch = false
		box.Massless = true
		box.Parent = model
		table.insert(built.riders, { box, hull })
	end
	local hullTopY = layout.hullY + layout.hullSize.Y / 2
	collider("CabinHull", Vector3.new(layout.hullSize.X + 0.6, ROOF_TOP - hullTopY, 6.6), Vector3.new(0, (ROOF_TOP + hullTopY) / 2 - layout.hullY, 0.6))
	collider("NoseHull", Vector3.new(layout.width - 0.8, 1.6, 2.0), Vector3.new(0, 1.8 - layout.hullY, -(layout.length / 2 - 1.0)))
	collider("TailHull", Vector3.new(layout.width - 0.8, 1.6, 2.0), Vector3.new(0, 1.8 - layout.hullY, layout.length / 2 - 1.0))

	-- Underglow: a bar between the axles under the sills, throwing its colour on the road.
	if glow then
		local bar = Instance.new("Part")
		bar.Name = "Underglow"
		bar.Size = Vector3.new(layout.width - 2.4, 0.12, (layout.axleRear - layout.axleFront) - 2.5)
		bar.CFrame = cframe * CFrame.new(0, 0.55 - layout.hullY, (layout.axleFront + layout.axleRear) / 2)
		bar.Color = glow
		bar.Material = Enum.Material.Neon
		bar.CanCollide = false
		bar.CanQuery = false
		bar.CanTouch = false
		bar.Massless = true
		bar.CastShadow = false
		bar.Anchored = false
		bar.Parent = model
		local pool = Instance.new("SurfaceLight")
		pool.Face = Enum.NormalId.Bottom
		pool.Color = glow
		pool.Brightness = 4
		pool.Range = 9
		pool.Angle = 120
		pool.Parent = bar
		table.insert(built.riders, { bar, hull })
	end
	return built
end

return MeshCar
