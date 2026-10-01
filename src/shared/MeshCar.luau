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
	-- Studs to the metre for this car, which is drawn spec.scale times life size.
	S: number,
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
		S = CarSpec.StudsPerMetreOf(spec.scale),
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
	return (p - m.hullCentre) * m.S
end

-- CarBody.Layout's shape, for a modelled car. `kind` supplies the spec through its id.
function MeshCar.Layout(kind: any, spec: CarSpec.Spec): any
	local m = measure(kind.model, spec)
	-- Studs to the metre for this car, and the factor every length below is drawn larger by.
	local S, k = m.S, spec.scale
	local sizeZ = kind.size.Z
	local width = kind.size.X
	local hullTop = spec.cgHeight * S + 0.4 * k
	local hullSize = Vector3.new(m.halfTrack * 2 * S - m.width * S - 0.5 * k, hullTop - HULL_BOTTOM * k, sizeZ - 1.2 * k)
	local mass = HULL_MASS_PER_STUD2 * hullSize.X * hullSize.Z
	local hullY = spec.cgHeight * S
	local axleFront = (m.frontZ - m.hullCentre.Z) * S
	local axleRear = (m.rearZ - m.hullCentre.Z) * S
	-- The corner weights are set so the centre of mass falls where the spec says the weight is: a
	-- front-heavy car has more of it at the front.
	local comZ = axleFront + (1 - spec.weightFront) * (axleRear - axleFront)
	local reach = sizeZ / 2 - 1.5 * k
	local frontShare = math.clamp((1 - comZ / (BALLAST_SHARE * reach)) / 2, 0.2, 0.8)
	local ballastMass = mass * BALLAST_SHARE / 4
	local radiusStuds = m.radius * S
	local ride = spec.travelBump * S + SPRING_MARGIN * k
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
			Vector3.new(-(width / 2 - 0.6 * k), 0, -reach),
			Vector3.new(width / 2 - 0.6 * k, 0, -reach),
			Vector3.new(-(width / 2 - 0.6 * k), 0, reach),
			Vector3.new(width / 2 - 0.6 * k, 0, reach),
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
		seat = Vector3.new(m.wheelX * S * 0.6, SEAT_TOP * k - 0.5 - hullY, (m.wheelZ + 0.6 - m.hullCentre.Z) * S),
		-- Where a bonnet camera sits, over the middle of the bonnet, and a cockpit camera, at the driver's
		-- eyes: an avatar's eyes are about three studs over the seat it sits on, whatever the car.
		camHood = Vector3.new(0, 1.12 * S - hullY, (-1.05 - m.hullCentre.Z) * S),
		camCockpit = Vector3.new(m.wheelX * S * 0.6, SEAT_TOP * k + 3.0 - hullY, (m.wheelZ + 0.6 - m.hullCentre.Z) * S - 0.2 * k),
		springRide = ride,
		springBump = spec.travelBump * S,
		springDroop = spec.travelDroop * S,
		comZ = comZ,
		mesh = true,
	}
end

local PAINT_PREFIX = "Paint_"
local LAMP_PREFIX = "Lamp_"
-- The parts of the model that carry a real maker's name and logo, left out of the drawing.
local HIDDEN_BADGES = { Badge_Boot = true, Badge_Rear = true, Badge_Front = true }
local CHROME = Color3.fromRGB(206, 210, 216)
local BADGE_DARK = Color3.fromRGB(18, 18, 22)
local BADGE_NAME = "NISAN"

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
		signals = { left = {}, right = {} },
		mesh = true,
	}
	local roots: { [string]: BasePart } = {}
	local wheelRider: { [string]: { BasePart } } = { FL = {}, FR = {}, RL = {}, RR = {} }

	for _, source in m.template:GetChildren() do
		if not source:IsA("MeshPart") then
			continue
		end
		local piece = source:Clone()
		piece.Size = source.Size * m.S
		piece.CFrame = cframe * CFrame.new(toHull(m, source.Position))
		piece.Anchored = false
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.Massless = true
		piece.Parent = model
		local name = source.Name
		-- The maker's own badges are not drawn: MeshCar.Badges draws this game's, slightly altered.
		if HIDDEN_BADGES[source.Name] then
			piece.Transparency = 1
		end
		-- Glass is seen through: from the cockpit camera the road has to show past the windscreen.
		if string.sub(source.Name, 1, 6) == "Glass_" then
			piece.Transparency = 0.55
			piece.CastShadow = false
		end
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
				aim.CFrame = piece.CFrame * CFrame.new(0, 0, -(piece.Size.Z / 2 + 0.2 * spec.scale))
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

	-- This game's badges, where the maker's were: a ring with a bar across it, close to the one a
	-- grille or a boot lid wears but not the same -- a thicker ring, a bar that breaks it, another spelling.
	local function plate(name: string, x: number, y: number, z: number, w: number, h: number, facing: Enum.NormalId, on: BasePart?)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = Vector3.new(w, h, 0.01 * m.S) * 1
		part.CFrame = cframe * CFrame.new(toHull(m, Vector3.new(x, y, z)))
		part.Transparency = 1
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		part.Parent = model
		table.insert(built.riders, { part, on or hull })
		return part
	end
	local function label(part: BasePart, face: Enum.NormalId, text: string, color: Color3, pixels: number)
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = pixels
		gui.LightInfluence = 1
		gui.Parent = part
		local text_ = Instance.new("TextLabel")
		text_.Size = UDim2.fromScale(1, 1)
		text_.BackgroundTransparency = 1
		text_.Text = text
		text_.TextColor3 = color
		text_.TextScaled = true
		text_.Font = Enum.Font.GothamBold
		text_.Parent = gui
	end
	-- The roundel: a chrome ring, a dark field, a bar across it with the name on it. `axis` turns a
	-- disc (which a Roblox cylinder lies along X) to face `toward`: 1 for a lid facing back, -1 forward,
	-- and for a wheel's cap an angle about Z from the wheel's own frame.
	local function roundel(parent: Model, at: CFrame, diameter: number, on: BasePart)
		local function disc(name: string, d: number, t: number, color: Color3, material: Enum.Material, depth: number)
			local part = Instance.new("Part")
			part.Name = name
			part.Shape = Enum.PartType.Cylinder
			part.Size = Vector3.new(t, d, d)
			part.CFrame = at * CFrame.new(0, 0, depth) * CFrame.Angles(0, math.rad(90), 0)
			part.Color = color
			part.Material = material
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.CastShadow = false
			part.Parent = parent
			table.insert(built.riders, { part, on })
			return part
		end
		disc("BadgeRing", diameter, 0.012 * m.S, CHROME, Enum.Material.Metal, 0)
		disc("BadgeField", diameter * 0.74, 0.016 * m.S, BADGE_DARK, Enum.Material.SmoothPlastic, 0.003 * m.S)
		-- The bar, which the ring does not close over: it runs past it on both sides.
		local bar = Instance.new("Part")
		bar.Name = "BadgeBar"
		bar.Size = Vector3.new(diameter * 1.18, diameter * 0.26, 0.012 * m.S)
		bar.CFrame = at * CFrame.new(0, 0, 0.006 * m.S)
		bar.Color = CHROME
		bar.Material = Enum.Material.Metal
		bar.Anchored = false
		bar.CanCollide = false
		bar.CanQuery = false
		bar.CanTouch = false
		bar.Massless = true
		bar.CastShadow = false
		bar.Parent = parent
		table.insert(built.riders, { bar, on })
		label(bar, Enum.NormalId.Back, BADGE_NAME, BADGE_DARK, 400)
	end
	-- On the boot lid, facing back.
	roundel(model, cframe * CFrame.new(toHull(m, Vector3.new(0, 0.2486, 2.243))), 0.11 * m.S, hull)
	-- And in the middle of each wheel, over the cap that had the maker's.
	for _, corner in { "FL", "FR", "RL", "RR" } do
		local rim = part(m.template, "Wheel" .. corner .. "_Rim")
		local side = if string.sub(corner, 2, 2) == "L" then -1 else 1
		local at = cframe
			* CFrame.new(toHull(m, Vector3.new(rim.Position.X + side * (rim.Size.X / 2 + 0.004), rim.Position.Y, rim.Position.Z)))
			* CFrame.Angles(0, side * math.rad(90), 0)
		roundel(model, at, 0.13 * m.S, roots[corner .. "Tyre"])
	end
	-- Across the boot, the trim's name and the model's, where the lettering was.
	do
		-- Set well back of the lid: the surface is further out than the lettering the model had drawn on it.
		local strip = plate("BadgeText", 0, 0.1346, 2.36, 0.76 * m.S, 0.06 * m.S, Enum.NormalId.Back, nil)
		strip.Transparency = 0.99
		label(strip, Enum.NormalId.Back, "NISMA     GT-R", Color3.fromRGB(226, 228, 232), 150)
	end

	-- The turn signals: a bar of amber at each corner, dark (and so unseen) until one flashes.
	local function signal(side: string, x: number, y: number, z: number, w: number, h: number, d: number)
		local lamp = Instance.new("Part")
		lamp.Name = "Signal"
		lamp.Size = Vector3.new(w, h, d) * m.S
		lamp.CFrame = cframe * CFrame.new(toHull(m, Vector3.new(x, y, z)))
		lamp.Color = Color3.fromRGB(255, 160, 24)
		lamp.Material = Enum.Material.Neon
		lamp.Transparency = 1
		lamp.Anchored = false
		lamp.CanCollide = false
		lamp.CanQuery = false
		lamp.CanTouch = false
		lamp.Massless = true
		lamp.CastShadow = false
		lamp.Parent = model
		table.insert(built.riders, { lamp, hull })
		table.insert(built.signals[side], lamp)
		local glow = Instance.new("PointLight")
		glow.Color = lamp.Color
		glow.Brightness = 0.6
		glow.Range = 5
		glow.Shadows = false
		glow.Parent = lamp
	end
	for _, side in { -1, 1 } do
		local name = if side < 0 then "left" else "right"
		-- Across the foot of each headlamp lens and each tail lamp, where the real car's indicators are.
		signal(name, side * 0.705, -0.035, -2.14, 0.16, 0.018, 0.02)
		signal(name, side * 0.59, 0.118, 2.228, 0.17, 0.018, 0.02)
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
	local k = spec.scale
	local hullTopY = layout.hullY + layout.hullSize.Y / 2
	local roofTop = ROOF_TOP * k
	collider("CabinHull", Vector3.new(layout.hullSize.X + 0.6 * k, roofTop - hullTopY, 6.6 * k), Vector3.new(0, (roofTop + hullTopY) / 2 - layout.hullY, 0.6 * k))
	collider("NoseHull", Vector3.new(layout.width - 0.8 * k, 1.6 * k, 2.0 * k), Vector3.new(0, 1.8 * k - layout.hullY, -(layout.length / 2 - 1.0 * k)))
	collider("TailHull", Vector3.new(layout.width - 0.8 * k, 1.6 * k, 2.0 * k), Vector3.new(0, 1.8 * k - layout.hullY, layout.length / 2 - 1.0 * k))

	-- Underglow: a bar between the axles under the sills, throwing its colour on the road.
	if glow then
		local bar = Instance.new("Part")
		bar.Name = "Underglow"
		bar.Size = Vector3.new(layout.width - 2.4 * k, 0.12 * k, (layout.axleRear - layout.axleFront) - 2.5 * k)
		bar.CFrame = cframe * CFrame.new(0, 0.55 * k - layout.hullY, (layout.axleFront + layout.axleRear) / 2)
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
