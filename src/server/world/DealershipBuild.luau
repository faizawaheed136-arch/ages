--!strict
--[[
	Meridian Motors: the car dealership, laid as parts.

	It replaces AUTOPIA MOTORS, which was one desk, one chair and one box of a car in the ground
	floor of a tower on avenue 1 -- boxed in by the gas station and the tattoo parlour, with no
	room for anything but a counter. The owner asked for it to go and for a proper one to be
	built: a luxury showroom and an everyday lot in one, where every car can be bought or taken
	for a test drive.

	WHAT THIS FILE IS. Geometry only. It lays the building, the lot and the markers the
	dealership's systems look for, under one Model, relative to one origin -- so moving the
	whole dealership is one CFrame. It requires nothing from the game, which is what lets it be
	run from Studio's command bar in edit mode: the dealership is baked into the place and can
	be seen and adjusted without pressing Play.

	WHAT IT LEAVES FOR RUNTIME. The cars. Each display spot is a `CarSlot` part carrying a
	`VehicleId`; `DealershipService` builds the car on it from `content/Vehicles` when the
	server starts, so what stands on the floor is always what the lot actually sells, at the
	price it actually charges. A slot is a translucent footprint in edit mode so the layout
	reads without Play.

	THE MARKERS the services read, all found by name under the model:
	  * `CounterMark` -- where the `auto_dealer` place point belongs: in front of the sales
	    counter, level with the side door, so a bought car parks in the pickup lane 36 studs
	    west of it (Config.Vehicles.ParkStuds) with a clear line of sight through the door.
	  * `TestDriveBay` x2 -- where a test-drive car is put, nose to the road.
	  * `TestDriveReturn` -- where a driver is set down when a test drive ends.
	  * `Turntable` models -- their `Rotor` is spun on each client by DealershipTurntables.

	SCALE. An avatar is five studs. Doors are ten, the showroom ceiling twenty (a hall, not a
	room), a parking bay 11 by 20, a desk top three studs up. The lot's rows are laid off the
	cars' own sizes in content/Vehicles, the widest of which is 7.2 by 18.5.

	Every glass pane is CanQuery false. Ground.SpotAt only accepts a parking spot it can see from
	the place point with a chest-height ray, and a pane that answered raycasts would hide the
	pickup lane from the counter and leave every bought car with "nowhere to park".
]]

local CollectionService = game:GetService("CollectionService")

local DealershipBuild = {}

DealershipBuild.ModelName = "Dealership"
DealershipBuild.SlotTag = "DealershipSlot"
DealershipBuild.TurntableTag = "DealershipTurntable"

-- Heights above the plot's grass, which the origin sits on.
local FLOOR = 0.65 -- showroom floor top: one small step up off the plaza
local CEIL = FLOOR + 20
local ROOF = CEIL + 1.2
local PARAPET = ROOF + 3.3
local LOT = 0.15 -- asphalt top
local WALK = 0.25 -- sidewalk and walkway top
local PLAZA = 0.3

local C = {
	White = Color3.fromRGB(240, 240, 238),
	OffWhite = Color3.fromRGB(226, 224, 218),
	Charcoal = Color3.fromRGB(38, 40, 46),
	Navy = Color3.fromRGB(20, 30, 54),
	Gold = Color3.fromRGB(222, 178, 86),
	Glass = Color3.fromRGB(168, 204, 224),
	Asphalt = Color3.fromRGB(52, 54, 58),
	Line = Color3.fromRGB(236, 236, 230),
	Yellow = Color3.fromRGB(244, 196, 48),
	Paving = Color3.fromRGB(190, 188, 182),
	Kerb = Color3.fromRGB(150, 150, 148),
	Marble = Color3.fromRGB(234, 234, 230),
	DarkFloor = Color3.fromRGB(44, 46, 52),
	Wood = Color3.fromRGB(128, 92, 62),
	Leather = Color3.fromRGB(30, 30, 34),
	Fabric = Color3.fromRGB(96, 104, 116),
	Rug = Color3.fromRGB(150, 140, 128),
	Leaf = Color3.fromRGB(64, 112, 58),
	LeafDark = Color3.fromRGB(46, 88, 46),
	Planter = Color3.fromRGB(58, 58, 62),
	Screen = Color3.fromRGB(14, 16, 22),
	Warm = Color3.fromRGB(255, 226, 180),
	Red = Color3.fromRGB(214, 44, 52),
	Blue = Color3.fromRGB(40, 96, 214),
}

local FLAG_COLOURS = { C.Red, C.Blue, C.Yellow, C.White }
local BALLOON_COLOURS = { C.Red, C.Yellow, C.Blue, C.White, C.Gold }

type Opts = {
	collide: boolean?,
	transparency: number?,
	reflectance: number?,
	shadow: boolean?,
	query: boolean?,
	shape: Enum.PartType?,
}

-- Set once per Build: every position below is local to it.
local origin = CFrame.new()

local function at(x: number, y: number, z: number): CFrame
	return origin * CFrame.new(x, y, z)
end

local function style(part: BasePart, color: Color3, material: Enum.Material, opts: Opts?)
	part.Anchored = true
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if opts then
		if opts.collide ~= nil then
			part.CanCollide = opts.collide
		end
		if opts.transparency then
			part.Transparency = opts.transparency
		end
		if opts.reflectance then
			part.Reflectance = opts.reflectance
		end
		if opts.shadow ~= nil then
			part.CastShadow = opts.shadow
		end
		if opts.query ~= nil then
			part.CanQuery = opts.query
		end
	end
end

-- An axis-aligned block between two corners, in local studs.
local function box(
	parent: Instance,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	color: Color3,
	material: Enum.Material,
	opts: Opts?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
	part.CFrame = at((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	style(part, color, material, opts)
	part.Parent = parent
	return part
end

-- A flat disc standing on its face, centred at (x, z), from y0 up to y1.
local function disc(
	parent: Instance,
	name: string,
	x: number,
	z: number,
	y0: number,
	y1: number,
	diameter: number,
	color: Color3,
	material: Enum.Material,
	opts: Opts?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	-- A cylinder's length runs along its own X, so it is turned onto its side to lie flat.
	part.Size = Vector3.new(y1 - y0, diameter, diameter)
	part.CFrame = at(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.rad(90))
	style(part, color, material, opts)
	part.Parent = parent
	return part
end

-- A vertical round post, centred at (x, z).
local function post(
	parent: Instance,
	name: string,
	x: number,
	z: number,
	y0: number,
	y1: number,
	diameter: number,
	color: Color3,
	material: Enum.Material
): Part
	return disc(parent, name, x, z, y0, y1, diameter, color, material)
end

local function ball(parent: Instance, name: string, position: Vector3, diameter: number, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.CFrame = origin * CFrame.new(position)
	style(part, color, material, { collide = false, shadow = false })
	part.Parent = parent
	return part
end

-- The studs a face spans, (across, up) as a SurfaceGui lays it out.
local function faceSize(part: BasePart, face: Enum.NormalId): (number, number)
	local size = part.Size
	if face == Enum.NormalId.Front or face == Enum.NormalId.Back then
		return size.X, size.Y
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return size.Z, size.Y
	end
	return size.X, size.Z
end

--[[
	Text on one face of a part. `glow` makes it ignore the scene's lighting, for signs that are lit.

	The pixel density is worked out from the face rather than fixed. TextScaled never draws text
	larger than 100 pixels, so at a fixed 40 pixels a stud the fascia sign -- four studs tall --
	capped its lettering at two and a half studs and read as small print on a big board. A
	hundred pixels across the face's short side lets the text fill it.
]]
local function sign(part: BasePart, face: Enum.NormalId, text: string, color: Color3, glow: boolean?, font: Enum.Font?)
	local across, up = faceSize(part, face)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = math.clamp(100 / math.min(across, up), 4, 50)
	gui.LightInfluence = if glow then 0 else 1
	gui.Brightness = if glow then 2.5 else 1
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = font or Enum.Font.GothamBlack
	label.Parent = gui
end

local function light(part: BasePart, kind: "Point" | "Spot", brightness: number, range: number, color: Color3?, angle: number?)
	if kind == "Point" then
		local l = Instance.new("PointLight")
		l.Brightness = brightness
		l.Range = range
		l.Color = color or C.Warm
		l.Shadows = false
		l.Parent = part
	else
		local l = Instance.new("SpotLight")
		l.Brightness = brightness
		l.Range = range
		l.Angle = angle or 60
		l.Face = Enum.NormalId.Bottom
		l.Color = color or C.Warm
		l.Shadows = false
		l.Parent = part
	end
end

local function folder(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

-- An invisible marker the services find by name. Anchored and out of every physics query.
local function mark(parent: Instance, name: string, x: number, y: number, z: number, facingDegrees: number): Part
	local part = box(parent, name, x - 1, x + 1, y, y + 0.2, z - 1, z + 1, C.Yellow, Enum.Material.Neon, {
		collide = false,
		transparency = 1,
		query = false,
		shadow = false,
	})
	part.CFrame = at(x, y + 0.1, z) * CFrame.Angles(0, math.rad(facingDegrees), 0)
	part.CanTouch = false
	return part
end

--[[
	Where a car will stand. Facing 0 puts the car's nose to local -Z, south, toward the road --
	the same "front is -Z" the chassis is built on. The footprint is translucent in edit mode so
	the layout can be read, and hidden by DealershipService once the car is on it.
]]
local function slot(parent: Instance, vehicleId: string, display: string, x: number, y: number, z: number, facingDegrees: number): Part
	local part = Instance.new("Part")
	part.Name = "CarSlot"
	part.Size = Vector3.new(7, 0.2, 16)
	part.CFrame = at(x, y + 0.1, z) * CFrame.Angles(0, math.rad(facingDegrees), 0)
	style(part, C.Gold, Enum.Material.SmoothPlastic, {
		collide = false,
		transparency = 0.55,
		query = false,
		shadow = false,
	})
	part.CanTouch = false
	part:SetAttribute("VehicleId", vehicleId)
	part:SetAttribute("Display", display)
	CollectionService:AddTag(part, DealershipBuild.SlotTag)
	part.Parent = parent
	return part
end

-- A chair facing `facingDegrees` (0 = the sitter looks south, -Z).
local function chair(parent: Instance, x: number, z: number, y: number, facingDegrees: number, color: Color3)
	local model = folder(parent, "Chair")
	local seat = box(model, "Seat", -1.3, 1.3, 1.8, 2.3, -1.3, 1.3, color, Enum.Material.Fabric)
	local back = box(model, "Back", -1.3, 1.3, 2.3, 5.0, 1.0, 1.4, color, Enum.Material.Fabric)
	local stem = box(model, "Stem", -0.2, 0.2, 0, 1.8, -0.2, 0.2, C.Charcoal, Enum.Material.Metal)
	local foot = disc(model, "Foot", 0, 0, 0, 0.2, 2.2, C.Charcoal, Enum.Material.Metal)
	local frame = at(x, y, z) * CFrame.Angles(0, math.rad(facingDegrees), 0)
	for _, part in { seat, back, stem, foot } do
		part.CFrame = frame * origin:ToObjectSpace(part.CFrame)
	end
end

local function plant(parent: Instance, x: number, z: number, y: number, size: number)
	local model = folder(parent, "Plant")
	box(model, "Pot", x - size * 0.45, x + size * 0.45, y, y + size * 0.7, z - size * 0.45, z + size * 0.45, C.Planter, Enum.Material.SmoothPlastic)
	ball(model, "Foliage", Vector3.new(x, y + size * 1.2, z), size * 1.3, C.Leaf, Enum.Material.LeafyGrass)
	ball(model, "Foliage2", Vector3.new(x + size * 0.3, y + size * 1.6, z - size * 0.2), size * 0.9, C.LeafDark, Enum.Material.LeafyGrass)
end

local function monitor(parent: Instance, x: number, z: number, y: number, facingDegrees: number)
	local model = folder(parent, "Monitor")
	local screen = box(model, "Screen", -1.3, 1.3, 1.0, 2.6, -0.08, 0.08, C.Screen, Enum.Material.SmoothPlastic)
	local stand = box(model, "Stand", -0.12, 0.12, 0, 1.0, -0.1, 0.1, C.Charcoal, Enum.Material.Metal)
	local base = box(model, "Base", -0.5, 0.5, 0, 0.08, -0.35, 0.35, C.Charcoal, Enum.Material.Metal)
	local frame = at(x, y, z) * CFrame.Angles(0, math.rad(facingDegrees), 0)
	for _, part in { screen, stand, base } do
		part.CFrame = frame * origin:ToObjectSpace(part.CFrame)
	end
	sign(screen, Enum.NormalId.Front, "MERIDIAN", C.Gold, true)
end

-- ---------------------------------------------------------------------------------------------
-- Ground: sidewalk, lot, pickup lane, plaza, walkway, hedges.
-- ---------------------------------------------------------------------------------------------
local function buildGround(model: Model)
	local g = folder(model, "Ground")
	-- The sidewalk along the road, cut where the lot's driveway crosses it.
	box(g, "Sidewalk", 0, 104, 0, WALK, 0, 6, C.Paving, Enum.Material.Concrete)
	box(g, "Sidewalk", 140, 310, 0, WALK, 0, 6, C.Paving, Enum.Material.Concrete)
	box(g, "Driveway", 104, 140, 0, 0.2, 0, 8, C.Asphalt, Enum.Material.Asphalt)
	box(g, "Kerb", 6, 104, 0, 0.45, 7.2, 8, C.Kerb, Enum.Material.Concrete)
	box(g, "Lot", 6, 140, 0, LOT, 8, 114, C.Asphalt, Enum.Material.Asphalt)
	box(g, "Plaza", 140, 270, 0, PLAZA, 6, 22, C.Paving, Enum.Material.Slate)
	box(g, "Walkway", 140, 150, 0, WALK, 22, 114, C.Paving, Enum.Material.Slate)
	box(g, "HedgeNorth", 6, 140, 0, 2.6, 114.5, 117, C.Leaf, Enum.Material.LeafyGrass)
	box(g, "HedgeWest", 2.5, 5, 0, 2.6, 8, 117, C.Leaf, Enum.Material.LeafyGrass)
	box(g, "HedgeEast", 264.5, 267, 0, 2.6, 22, 98, C.Leaf, Enum.Material.LeafyGrass)
end

-- ---------------------------------------------------------------------------------------------
-- The everyday lot: painted bays, test-drive bays, pickup lane, lights, bunting, sales cabin.
-- ---------------------------------------------------------------------------------------------
local BAY_WIDTH = 11
local BAY_FIRST_X = 10
local BAY_COUNT = 8
local ROW_A = { z0 = 14, z1 = 34 }
local ROW_B = { z0 = 58, z1 = 78 }
local LOT_KINDS = { "sedan", "wagon" }

local function paint(parent: Instance, name: string, x0: number, x1: number, z0: number, z1: number, color: Color3)
	return box(parent, name, x0, x1, LOT, LOT + 0.03, z0, z1, color, Enum.Material.SmoothPlastic, {
		collide = false,
		query = false,
		shadow = false,
	})
end

-- Lettering laid flat on the asphalt, reading from the road.
local function groundText(parent: Instance, name: string, text: string, x0: number, x1: number, z0: number, z1: number, color: Color3)
	local part = paint(parent, name, x0, x1, z0, z1, C.Asphalt)
	part.Transparency = 1
	sign(part, Enum.NormalId.Top, text, color, false, Enum.Font.GothamBold)
end

local function buildLot(model: Model)
	local lot = folder(model, "Lot")
	local marks = folder(lot, "Markings")
	for _, row in { ROW_A, ROW_B } do
		for i = 0, BAY_COUNT do
			local x = BAY_FIRST_X + BAY_WIDTH * i
			paint(marks, "BayLine", x - 0.18, x + 0.18, row.z0, row.z1, C.Line)
		end
	end

	-- Two test-drive bays by the driveway, outlined in yellow.
	for _, bay in { { 106, 122 }, { 124, 140 } } do
		paint(marks, "TestLine", bay[1], bay[1] + 0.3, 12, 32, C.Yellow)
		paint(marks, "TestLine", bay[2] - 0.3, bay[2], 12, 32, C.Yellow)
		paint(marks, "TestLine", bay[1], bay[2], 31.7, 32, C.Yellow)
	end
	groundText(marks, "TestDriveText", "TEST DRIVE", 106, 140, 33, 38, C.Yellow)
	groundText(marks, "PickupText", "NEW OWNER PICKUP", 106, 140, 78, 83, C.Line)
	paint(marks, "PickupEdge", 103.7, 104, 34, 112, C.Line)

	-- Lights at the aisle ends, clear of every bay.
	local poles = folder(lot, "LightPoles")
	local polePoints = { { 7, 46 }, { 101, 46 }, { 7, 102 }, { 101, 102 } }
	for _, p in polePoints do
		post(poles, "Pole", p[1], p[2], LOT, 16, 0.7, C.Charcoal, Enum.Material.Metal)
		local head = box(poles, "Lamp", p[1] - 1.4, p[1] + 1.4, 15.4, 16.1, p[2] - 0.7, p[2] + 0.7, C.Charcoal, Enum.Material.Metal)
		box(poles, "LampGlow", p[1] - 1.2, p[1] + 1.2, 15.3, 15.4, p[2] - 0.5, p[2] + 0.5, C.Warm, Enum.Material.Neon, {
			collide = false,
			shadow = false,
		})
		light(head, "Spot", 2.2, 44, C.Warm, 110)
	end

	-- Bunting: strings of pennants between the pole tops, sagging.
	local bunting = folder(lot, "Bunting")
	local lines = { { 1, 2 }, { 3, 4 }, { 1, 3 }, { 2, 4 } }
	local colourIndex = 0
	for _, pair in lines do
		local a, b = polePoints[pair[1]], polePoints[pair[2]]
		local from, to = Vector3.new(a[1], 15, a[2]), Vector3.new(b[1], 15, b[2])
		local span = (to - from).Magnitude
		local count = math.floor(span / 3)
		local sag = math.min(3, span / 30)
		local function pointAt(t: number): Vector3
			return from:Lerp(to, t) - Vector3.new(0, sag * (1 - (2 * t - 1) ^ 2), 0)
		end
		local along = (to - from).Unit
		for i = 0, count - 1 do
			local p0, p1 = pointAt(i / count), pointAt((i + 1) / count)
			local mid = (p0 + p1) / 2
			local rope = Instance.new("Part")
			rope.Name = "String"
			rope.Size = Vector3.new(0.1, 0.1, (p1 - p0).Magnitude)
			rope.CFrame = origin * CFrame.lookAt(mid, p1)
			style(rope, C.Charcoal, Enum.Material.SmoothPlastic, { collide = false, shadow = false, query = false })
			rope.Parent = bunting

			colourIndex += 1
			local flag = Instance.new("WedgePart")
			flag.Name = "Pennant"
			flag.Size = Vector3.new(0.08, 1.4, 1.2)
			-- A wedge's slope runs from its top-back edge down to its front: turned upside down, it
			-- hangs from the string as a point-down pennant.
			local hang = mid - Vector3.new(0, 0.75, 0)
			flag.CFrame = origin * CFrame.lookAt(hang, hang + along) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(180))
			style(flag, FLAG_COLOURS[(colourIndex - 1) % #FLAG_COLOURS + 1], Enum.Material.Fabric, {
				collide = false,
				shadow = false,
				query = false,
			})
			flag.Parent = bunting
		end
	end

	-- Balloon clusters either side of the driveway.
	local balloons = folder(lot, "Balloons")
	for _, base in { Vector3.new(102.5, 0, 4), Vector3.new(141.5, 0, 4) } do
		post(balloons, "Weight", base.X, base.Z, WALK, WALK + 0.8, 1, C.Charcoal, Enum.Material.Metal)
		for i = 1, 5 do
			local angle = i * 72
			local top = base + Vector3.new(math.cos(math.rad(angle)) * 1.3, 11 + (i % 3) * 1.2, math.sin(math.rad(angle)) * 1.3)
			ball(balloons, "Balloon", top, 2.4, BALLOON_COLOURS[i], Enum.Material.SmoothPlastic)
			local from = base + Vector3.new(0, WALK + 0.8, 0)
			local tie = top - Vector3.new(0, 1.2, 0)
			local cord = Instance.new("Part")
			cord.Name = "Cord"
			cord.Size = Vector3.new(0.05, 0.05, (tie - from).Magnitude)
			cord.CFrame = origin * CFrame.lookAt((from + tie) / 2, tie)
			style(cord, C.White, Enum.Material.SmoothPlastic, { collide = false, shadow = false, query = false })
			cord.Parent = balloons
		end
	end

	-- A waving tube man by the driveway: the cheapest signal there is that this is a car lot.
	local tube = folder(lot, "TubeMan")
	post(tube, "Fan", 97, 10, LOT, LOT + 1.4, 2.4, C.Charcoal, Enum.Material.Metal)
	post(tube, "Body", 97, 10, LOT + 1.4, LOT + 11, 1.5, C.Red, Enum.Material.Fabric)
	ball(tube, "Head", Vector3.new(97, LOT + 11.8, 10), 1.8, C.Red, Enum.Material.Fabric)
	box(tube, "ArmL", 94.2, 96.4, LOT + 8.2, LOT + 8.8, 9.7, 10.3, C.Yellow, Enum.Material.Fabric, { collide = false })
	box(tube, "ArmR", 97.6, 99.8, LOT + 9.4, LOT + 10, 9.7, 10.3, C.Yellow, Enum.Material.Fabric, { collide = false })

	-- "EVERYDAY CARS" over the front of the lot.
	local banner = folder(lot, "Banner")
	post(banner, "PostL", 30, 10, LOT, 11, 0.6, C.Charcoal, Enum.Material.Metal)
	post(banner, "PostR", 80, 10, LOT, 11, 0.6, C.Charcoal, Enum.Material.Metal)
	local board = box(banner, "Board", 29, 81, 7.4, 11, 9.8, 10.2, C.Navy, Enum.Material.SmoothPlastic)
	sign(board, Enum.NormalId.Front, "EVERYDAY CARS  •  DRIVE AWAY TODAY", C.Gold, true)
	sign(board, Enum.NormalId.Back, "EVERYDAY CARS  •  DRIVE AWAY TODAY", C.Gold, true)

	-- The lot's sales cabin, in the back strip behind row B.
	local cabin = folder(lot, "SalesCabin")
	box(cabin, "Floor", 10, 34, LOT, 0.55, 90, 110, C.Wood, Enum.Material.WoodPlanks)
	box(cabin, "WallN", 10, 34, 0.55, 9, 109.5, 110, C.White, Enum.Material.SmoothPlastic)
	box(cabin, "WallW", 10, 10.5, 0.55, 9, 90, 110, C.White, Enum.Material.SmoothPlastic)
	box(cabin, "WallE", 33.5, 34, 0.55, 9, 90, 110, C.White, Enum.Material.SmoothPlastic)
	box(cabin, "WallS1", 10, 14, 0.55, 9, 90, 90.5, C.White, Enum.Material.SmoothPlastic)
	box(cabin, "WallS2", 24, 26, 0.55, 9, 90, 90.5, C.White, Enum.Material.SmoothPlastic)
	box(cabin, "WallS3", 30, 34, 0.55, 9, 90, 90.5, C.White, Enum.Material.SmoothPlastic)
	box(cabin, "Sill", 14, 24, 0.55, 3, 90, 90.5, C.White, Enum.Material.SmoothPlastic)
	box(cabin, "Window", 14, 24, 3, 7.5, 90.15, 90.35, C.Glass, Enum.Material.Glass, { transparency = 0.5, query = false, shadow = false })
	box(cabin, "Lintel", 14, 30, 7.5, 9, 90, 90.5, C.White, Enum.Material.SmoothPlastic)
	box(cabin, "Roof", 9, 35, 9, 9.6, 88.6, 111, C.Navy, Enum.Material.SmoothPlastic)
	local cabinSign = box(cabin, "Sign", 12, 32, 9.6, 11.4, 88.9, 89.3, C.Navy, Enum.Material.SmoothPlastic)
	sign(cabinSign, Enum.NormalId.Front, "SALES OFFICE", C.Gold, true)
	box(cabin, "Desk", 14, 22, 0.55, 3.4, 102, 106, C.Wood, Enum.Material.Wood)
	chair(cabin, 18, 107.5, 0.55, 0, C.Leather)
	chair(cabin, 18, 99.5, 0.55, 180, C.Fabric)
	local lamp = box(cabin, "CeilingLamp", 20, 24, 8.6, 9, 98, 102, C.Warm, Enum.Material.Neon, { collide = false, shadow = false })
	light(lamp, "Point", 1.2, 16)
end

-- ---------------------------------------------------------------------------------------------
-- The showroom: glass on the road and the lot, solid on the other two sides.
-- ---------------------------------------------------------------------------------------------
local SHOW = { x0 = 150, x1 = 264, z0 = 22, z1 = 98 }

local function glazing(
	parent: Instance,
	horizontal: boolean,
	from: number,
	to: number,
	fixed: number,
	bays: number,
	door: number?,
	doorBays: number
)
	-- `horizontal` runs along local X (the south face); otherwise along local Z (the west face).
	-- The door takes `doorBays` bays from bay `door`, with no mullion between them.
	local pitch = (to - from) / bays
	local glassProps: Opts = { transparency = 0.55, reflectance = 0.15, query = false, shadow = false }
	for i = 0, bays do
		local s = from + pitch * i
		local isDoorEdge = door ~= nil and i > door and i < door + doorBays
		if not isDoorEdge then
			if horizontal then
				box(parent, "Mullion", s - 0.3, s + 0.3, FLOOR, CEIL, fixed, fixed + 1, C.Charcoal, Enum.Material.Metal)
			else
				box(parent, "Mullion", fixed, fixed + 1, FLOOR, CEIL, s - 0.3, s + 0.3, C.Charcoal, Enum.Material.Metal)
			end
		end
	end
	for i = 0, bays - 1 do
		local a, b = from + pitch * i + 0.3, from + pitch * (i + 1) - 0.3
		local inDoor = door ~= nil and i >= door and i < door + doorBays
		local bottom = if inDoor then FLOOR + 10.5 else FLOOR
		if horizontal then
			box(parent, "Pane", a, b, bottom, CEIL - 2.5, fixed + 0.3, fixed + 0.7, C.Glass, Enum.Material.Glass, glassProps)
		else
			box(parent, "Pane", fixed + 0.3, fixed + 0.7, bottom, CEIL - 2.5, a, b, C.Glass, Enum.Material.Glass, glassProps)
		end
		if inDoor then
			if horizontal then
				box(parent, "DoorHead", a - 0.3, b + 0.3, FLOOR + 10, FLOOR + 10.5, fixed, fixed + 1, C.Charcoal, Enum.Material.Metal)
			else
				box(parent, "DoorHead", fixed, fixed + 1, FLOOR + 10, FLOOR + 10.5, a - 0.3, b + 0.3, C.Charcoal, Enum.Material.Metal)
			end
		end
	end
	if horizontal then
		box(parent, "Transom", from, to, CEIL - 2.5, CEIL, fixed, fixed + 1, C.Charcoal, Enum.Material.Metal)
	else
		box(parent, "Transom", fixed, fixed + 1, CEIL - 2.5, CEIL, from, to, C.Charcoal, Enum.Material.Metal)
	end
end

local function buildShell(model: Model)
	local shell = folder(model, "Shell")
	box(shell, "Floor", SHOW.x0, SHOW.x1, 0, FLOOR, SHOW.z0, SHOW.z1, C.Marble, Enum.Material.Marble, { reflectance = 0.12 })
	-- A dark border and a runway from the doors to the hero car: the floor says where to walk.
	for _, b in {
		{ SHOW.x0 + 1, SHOW.x1 - 1, SHOW.z0 + 1, SHOW.z0 + 2.2 },
		{ SHOW.x0 + 1, SHOW.x1 - 1, SHOW.z1 - 2.2, SHOW.z1 - 1 },
		{ SHOW.x0 + 1, SHOW.x0 + 2.2, SHOW.z0 + 1, SHOW.z1 - 1 },
		{ SHOW.x1 - 2.2, SHOW.x1 - 1, SHOW.z0 + 1, SHOW.z1 - 1 },
	} do
		box(shell, "Inlay", b[1], b[2], FLOOR, FLOOR + 0.02, b[3], b[4], C.DarkFloor, Enum.Material.Marble, { collide = false, query = false })
	end
	box(shell, "Runway", 201, 213, FLOOR, FLOOR + 0.02, 23, 60, C.DarkFloor, Enum.Material.Marble, { collide = false, query = false, reflectance = 0.2 })
	for _, x in { 200.8, 213.2 } do
		box(shell, "RunwayEdge", x - 0.12, x + 0.12, FLOOR, FLOOR + 0.03, 23, 60, C.Gold, Enum.Material.Neon, { collide = false, query = false, shadow = false })
	end

	-- South face: 14 bays, the doors in bays 6 and 7. West face: 8 bays, a side door in bay 4,
	-- opposite the counter and the pickup lane.
	glazing(shell, true, SHOW.x0, SHOW.x1, SHOW.z0, 14, 6, 2)
	glazing(shell, false, SHOW.z0, SHOW.z1, SHOW.x0, 8, 4, 1)

	box(shell, "WallNorth", SHOW.x0, SHOW.x1, FLOOR, CEIL, SHOW.z1 - 1, SHOW.z1, C.OffWhite, Enum.Material.SmoothPlastic)
	box(shell, "WallEast", SHOW.x1 - 1, SHOW.x1, FLOOR, CEIL, SHOW.z0, SHOW.z1, C.OffWhite, Enum.Material.SmoothPlastic)
	box(shell, "Roof", SHOW.x0 - 1, SHOW.x1 + 1, CEIL, ROOF, SHOW.z0 - 1, SHOW.z1 + 1, C.White, Enum.Material.SmoothPlastic)

	-- Fascia and parapet: a dark band all the way round, which is what makes a glass box read as a
	-- building from the road rather than a greenhouse.
	box(shell, "FasciaSouth", SHOW.x0 - 1.4, SHOW.x1 + 1.4, CEIL - 0.6, PARAPET, SHOW.z0 - 1.4, SHOW.z0 - 0.8, C.Charcoal, Enum.Material.SmoothPlastic)
	box(shell, "FasciaWest", SHOW.x0 - 1.4, SHOW.x0 - 0.8, CEIL - 0.6, PARAPET, SHOW.z0 - 1.4, SHOW.z1 + 1.4, C.Charcoal, Enum.Material.SmoothPlastic)
	box(shell, "ParapetNorth", SHOW.x0 - 1.4, SHOW.x1 + 1.4, ROOF, PARAPET, SHOW.z1 + 0.8, SHOW.z1 + 1.4, C.Charcoal, Enum.Material.SmoothPlastic)
	box(shell, "ParapetEast", SHOW.x1 + 0.8, SHOW.x1 + 1.4, ROOF, PARAPET, SHOW.z0 - 1.4, SHOW.z1 + 1.4, C.Charcoal, Enum.Material.SmoothPlastic)

	local brand = box(shell, "BrandSign", 168, 246, CEIL + 0.2, PARAPET - 0.3, SHOW.z0 - 1.8, SHOW.z0 - 1.4, C.Navy, Enum.Material.SmoothPlastic)
	sign(brand, Enum.NormalId.Front, "MERIDIAN MOTORS", C.Gold, true)
	box(shell, "BrandUnderline", 168, 246, CEIL - 0.1, CEIL + 0.15, SHOW.z0 - 1.9, SHOW.z0 - 1.5, C.Gold, Enum.Material.Neon, { collide = false, shadow = false })
	local side = box(shell, "SideSign", SHOW.x0 - 1.8, SHOW.x0 - 1.4, CEIL + 0.2, PARAPET - 0.3, 34, 86, C.Navy, Enum.Material.SmoothPlastic)
	sign(side, Enum.NormalId.Left, "MERIDIAN MOTORS", C.Gold, true)

	-- The entrance canopy.
	local canopy = box(shell, "Canopy", 196, 218, FLOOR + 11, FLOOR + 11.8, 11, SHOW.z0 - 1.4, C.Charcoal, Enum.Material.SmoothPlastic)
	box(shell, "CanopyGlow", 196.2, 217.8, FLOOR + 10.9, FLOOR + 11, 11.2, 12, C.Gold, Enum.Material.Neon, { collide = false, shadow = false })
	light(canopy, "Spot", 2, 18, C.Warm, 100)
	post(shell, "CanopyPost", 197.5, 12.5, PLAZA, FLOOR + 11, 0.8, C.Charcoal, Enum.Material.Metal)
	post(shell, "CanopyPost", 216.5, 12.5, PLAZA, FLOOR + 11, 0.8, C.Charcoal, Enum.Material.Metal)
end

-- ---------------------------------------------------------------------------------------------
-- Showroom interior.
-- ---------------------------------------------------------------------------------------------
local function spot(parent: Instance, x: number, z: number, brightness: number)
	local can = post(parent, "SpotCan", x, z, CEIL - 1.2, CEIL, 1.2, C.Charcoal, Enum.Material.Metal)
	box(parent, "SpotLens", x - 0.4, x + 0.4, CEIL - 1.25, CEIL - 1.2, z - 0.4, z + 0.4, C.Warm, Enum.Material.Neon, { collide = false, shadow = false })
	light(can, "Spot", brightness, 26, C.Warm, 45)
end

local function turntable(parent: Instance, name: string, vehicleId: string, x: number, z: number)
	local table_ = folder(parent, name)
	CollectionService:AddTag(table_, DealershipBuild.TurntableTag)
	table_:SetAttribute("Centre", (origin * CFrame.new(x, FLOOR + 0.7, z)).Position)
	-- One revolution in this many seconds: slow enough to read the car, fast enough to see it turn.
	table_:SetAttribute("SpinSeconds", 28)

	disc(table_, "Glow", x, z, FLOOR + 0.05, FLOOR + 0.3, 24.6, C.Gold, Enum.Material.Neon, { shadow = false })
	disc(table_, "Base", x, z, FLOOR, FLOOR + 0.4, 24, C.Charcoal, Enum.Material.SmoothPlastic, { reflectance = 0.25 })
	local rotor = folder(table_, "Rotor")
	disc(rotor, "Disc", x, z, FLOOR + 0.4, FLOOR + 0.7, 22, C.Marble, Enum.Material.Marble, { reflectance = 0.15 })
	for _, offset in { { -7, -5 }, { 7, -5 }, { 0, 7 } } do
		spot(parent, x + offset[1], z + offset[2], 3)
	end
	slot(rotor, vehicleId, "Turntable", x, FLOOR + 0.7, z, 0)
end

local function desk(parent: Instance, x: number, z: number, facingDegrees: number)
	-- Staff sit on the far side from `facingDegrees`' customers.
	local model = folder(parent, "SalesDesk")
	local frame = at(x, FLOOR, z) * CFrame.Angles(0, math.rad(facingDegrees), 0)
	local parts = {
		box(model, "Top", -4, 4, 2.9, 3.2, -2, 2, C.White, Enum.Material.Marble),
		box(model, "Panel", -4, -3.6, 0, 2.9, -2, 2, C.Navy, Enum.Material.SmoothPlastic),
		box(model, "Panel", 3.6, 4, 0, 2.9, -2, 2, C.Navy, Enum.Material.SmoothPlastic),
		box(model, "Modesty", -3.6, 3.6, 0.8, 2.9, -1.9, -1.7, C.Navy, Enum.Material.SmoothPlastic),
	}
	for _, part in parts do
		part.CFrame = frame * origin:ToObjectSpace(part.CFrame)
	end
	local function world(lx: number, lz: number): Vector3
		return origin:PointToObjectSpace((frame * CFrame.new(lx, 0, lz)).Position)
	end
	local m = world(0, 1)
	monitor(model, m.X, m.Z, FLOOR + 3.2, facingDegrees + 180)
	local staff = world(0, 4)
	chair(model, staff.X, staff.Z, FLOOR, facingDegrees, C.Leather)
	for _, dx in { -1.8, 1.8 } do
		local guest = world(dx, -4)
		chair(model, guest.X, guest.Z, FLOOR, facingDegrees + 180, C.Fabric)
	end
end

local function buildInterior(model: Model)
	local inside = folder(model, "Interior")

	-- The two turntables in the window, and the hero car on its podium at the end of the runway.
	turntable(inside, "TurntableWest", "roadster", 178, 44)
	turntable(inside, "TurntableEast", "coupe", 228, 44)

	local hero = folder(inside, "Hero")
	box(hero, "Podium", 197, 217, FLOOR, FLOOR + 1, 60, 86, C.Charcoal, Enum.Material.SmoothPlastic, { reflectance = 0.25 })
	for _, x in { 197, 217 } do
		box(hero, "PodiumEdge", x - 0.1, x + 0.1, FLOOR + 0.2, FLOOR + 0.9, 60, 86, C.Gold, Enum.Material.Neon, { collide = false, shadow = false })
	end
	box(hero, "PodiumEdge", 197, 217, FLOOR + 0.2, FLOOR + 0.9, 59.9, 60.1, C.Gold, Enum.Material.Neon, { collide = false, shadow = false })
	slot(hero, "roadster", "Hero", 207, FLOOR + 1, 73, 0)
	local backdrop = box(hero, "Backdrop", 193, 221, FLOOR, FLOOR + 15, 90, 92, C.Navy, Enum.Material.SmoothPlastic)
	sign(backdrop, Enum.NormalId.Front, "MERIDIAN", C.Gold, true)
	box(hero, "BackdropGlow", 192.6, 221.4, FLOOR + 15, FLOOR + 15.3, 89.6, 92.4, C.Gold, Enum.Material.Neon, { collide = false, shadow = false })
	spot(hero, 201, 70, 3.5)
	spot(hero, 213, 70, 3.5)

	-- The sales counter, level with the side door. The auto_dealer place point stands in front of it.
	local counter = folder(inside, "Counter")
	box(counter, "Body", 154, 172, FLOOR, FLOOR + 3.6, 70, 73.5, C.Navy, Enum.Material.SmoothPlastic)
	box(counter, "Top", 153.6, 172.4, FLOOR + 3.6, FLOOR + 3.9, 69.6, 73.9, C.White, Enum.Material.Marble)
	box(counter, "Kick", 154, 172, FLOOR + 0.2, FLOOR + 0.35, 69.85, 70, C.Gold, Enum.Material.Neon, { collide = false, shadow = false })
	monitor(counter, 158, 72.5, FLOOR + 3.9, 180)
	monitor(counter, 167, 72.5, FLOOR + 3.9, 180)
	chair(counter, 158, 76, FLOOR, 0, C.Leather)
	chair(counter, 167, 76, FLOOR, 0, C.Leather)
	local hanging = box(counter, "SalesSign", 156, 170, 13, 15.5, 71.6, 72, C.Navy, Enum.Material.SmoothPlastic)
	sign(hanging, Enum.NormalId.Front, "SALES  &  FINANCE", C.Gold, true)
	sign(hanging, Enum.NormalId.Back, "SALES  &  FINANCE", C.Gold, true)
	for _, x in { 158, 168 } do
		box(counter, "Cord", x - 0.05, x + 0.05, 15.5, CEIL, 71.75, 71.85, C.Charcoal, Enum.Material.Metal, { collide = false, shadow = false, query = false })
	end
	mark(model, "CounterMark", 162, FLOOR, 66, 0)

	-- Sales desks along the east wall, customers facing the window.
	local desks = folder(inside, "SalesDesks")
	for _, z in { 34, 50, 66 } do
		desk(desks, 250, z, 90)
	end
	plant(desks, 259, 42, FLOOR, 2.4)
	plant(desks, 259, 58, FLOOR, 2.4)

	-- Two glass offices in the north-east corner.
	local offices = folder(inside, "Offices")
	local officeGlass: Opts = { transparency = 0.6, reflectance = 0.1, query = false, shadow = false }
	for i, span in { { 224, 243, "FINANCE" }, { 243, 262, "MANAGER" } } do
		local x0, x1 = span[1] :: number, span[2] :: number
		local mid = (x0 + x1) / 2
		box(offices, "Glass", x0, mid - 2, FLOOR, CEIL - 6, 80, 80.3, C.Glass, Enum.Material.Glass, officeGlass)
		box(offices, "Glass", mid + 2, x1, FLOOR, CEIL - 6, 80, 80.3, C.Glass, Enum.Material.Glass, officeGlass)
		box(offices, "Head", x0, x1, CEIL - 6, CEIL, 80, 80.3, C.OffWhite, Enum.Material.SmoothPlastic)
		box(offices, "Head", mid - 2, mid + 2, FLOOR + 10, CEIL - 6, 80, 80.3, C.OffWhite, Enum.Material.SmoothPlastic)
		if i == 1 then
			box(offices, "Glass", 224, 224.3, FLOOR, CEIL - 6, 80, 97, C.Glass, Enum.Material.Glass, officeGlass)
		end
		box(offices, "Glass", x1 - 0.15, x1 + 0.15, FLOOR, CEIL - 6, 80, 97, C.Glass, Enum.Material.Glass, officeGlass)
		local plate = box(offices, "DoorPlate", mid - 2, mid + 2, FLOOR + 10.6, FLOOR + 11.6, 79.8, 80, C.Navy, Enum.Material.SmoothPlastic)
		sign(plate, Enum.NormalId.Front, span[3] :: string, C.Gold, true)
		box(offices, "Desk", mid - 4, mid + 4, FLOOR + 2.9, FLOOR + 3.2, 88, 92, C.Wood, Enum.Material.Wood)
		box(offices, "DeskBody", mid - 3.8, mid + 3.8, FLOOR, FLOOR + 2.9, 90.5, 91.8, C.Wood, Enum.Material.Wood)
		monitor(offices, mid, 91, FLOOR + 3.2, 180)
		chair(offices, mid, 94, FLOOR, 0, C.Leather)
		chair(offices, mid - 1.8, 85.5, FLOOR, 180, C.Fabric)
		chair(offices, mid + 1.8, 85.5, FLOOR, 180, C.Fabric)
		plant(offices, x1 - 2.5, 95, FLOOR, 2)
		local screen = box(offices, "WallScreen", mid - 4, mid + 4, FLOOR + 7, FLOOR + 11.5, 96.6, 97, C.Screen, Enum.Material.SmoothPlastic)
		sign(screen, Enum.NormalId.Front, "Q3 SALES ↑", C.Gold, true)
	end

	-- The customer lounge, north-west: somewhere to sit while the paperwork is done.
	local lounge = folder(inside, "Lounge")
	box(lounge, "Rug", 157, 183, FLOOR, FLOOR + 0.05, 82, 95, C.Rug, Enum.Material.Fabric, { collide = false })
	box(lounge, "SofaBase", 160, 178, FLOOR, FLOOR + 2, 92, 95.5, C.Fabric, Enum.Material.Fabric)
	box(lounge, "SofaBack", 160, 178, FLOOR + 2, FLOOR + 4.6, 95, 96.5, C.Fabric, Enum.Material.Fabric)
	box(lounge, "SofaArm", 159, 160, FLOOR, FLOOR + 3.2, 92, 96.5, C.Fabric, Enum.Material.Fabric)
	box(lounge, "SofaArm", 178, 179, FLOOR, FLOOR + 3.2, 92, 96.5, C.Fabric, Enum.Material.Fabric)
	box(lounge, "CoffeeTable", 164, 174, FLOOR + 1.3, FLOOR + 1.6, 85, 89, C.Wood, Enum.Material.Wood)
	box(lounge, "TableLegs", 165, 173, FLOOR, FLOOR + 1.3, 86, 88, C.Charcoal, Enum.Material.Metal)
	chair(lounge, 159, 85, FLOOR, 270, C.Leather)
	chair(lounge, 181, 85, FLOOR, 90, C.Leather)
	local tv = box(lounge, "TV", 160, 176, FLOOR + 7, FLOOR + 14, 96.6, 97, C.Screen, Enum.Material.SmoothPlastic)
	sign(tv, Enum.NormalId.Front, "DRIVE THE DREAM", C.Gold, true)
	box(lounge, "CoffeeBar", 151, 154.5, FLOOR, FLOOR + 3.4, 81, 96, C.Navy, Enum.Material.SmoothPlastic)
	box(lounge, "CoffeeBarTop", 151, 155, FLOOR + 3.4, FLOOR + 3.7, 80.6, 96.4, C.White, Enum.Material.Marble)
	box(lounge, "CoffeeMachine", 151.4, 154, FLOOR + 3.7, FLOOR + 6.2, 84, 86.5, C.Charcoal, Enum.Material.Metal)
	box(lounge, "CoffeeLight", 154, 154.1, FLOOR + 5.2, FLOOR + 5.6, 84.6, 85.9, C.Gold, Enum.Material.Neon, { collide = false })
	for _, z in { 89, 90, 91 } do
		post(lounge, "Cup", 153, z, FLOOR + 3.7, FLOOR + 4.3, 0.5, C.White, Enum.Material.SmoothPlastic)
	end
	plant(lounge, 183.5, 95, FLOOR, 2.2)
	-- Many small pendants rather than one big light: the cheap signal that a space is lived in.
	for _, p in { { 163, 84 }, { 169, 84 }, { 175, 84 }, { 163, 90 }, { 169, 90 }, { 175, 90 } } do
		box(lounge, "PendantCord", p[1] - 0.04, p[1] + 0.04, 11, CEIL, p[2] - 0.04, p[2] + 0.04, C.Charcoal, Enum.Material.Metal, {
			collide = false,
			shadow = false,
			query = false,
		})
		local lamp = ball(lounge, "Pendant", Vector3.new(p[1], 10.6, p[2]), 1.2, C.Warm, Enum.Material.Neon)
		light(lamp, "Point", 0.6, 10)
	end

	-- Planters in the corners and either side of the doors.
	local plants = folder(inside, "Planters")
	for _, p in { { 153.5, 25.5 }, { 260.5, 25.5 }, { 196, 26 }, { 218, 26 } } do
		plant(plants, p[1], p[2], FLOOR, 3)
	end

	-- Ceiling light panels, and a banner along the east wall.
	local ceiling = folder(inside, "Ceiling")
	local lit = 0
	for _, z in { 32, 56 } do
		for _, x in { 164, 190, 238 } do
			lit += 1
			local panel = box(ceiling, "LightPanel", x - 5, x + 5, CEIL - 0.2, CEIL, z - 0.7, z + 0.7, C.White, Enum.Material.Neon, {
				collide = false,
				shadow = false,
			})
			if lit % 2 == 1 then
				light(panel, "Point", 1.1, 40, C.White)
			end
		end
	end
	local banner = box(ceiling, "WallBanner", SHOW.x1 - 1.4, SHOW.x1 - 1, FLOOR + 12, FLOOR + 16.5, 28, 76, C.Navy, Enum.Material.SmoothPlastic)
	sign(banner, Enum.NormalId.Left, "PERFORMANCE  •  LUXURY  •  EVERYDAY", C.Gold, true)
end

-- ---------------------------------------------------------------------------------------------
-- The plaza and the road-side sign.
-- ---------------------------------------------------------------------------------------------
local function buildPlaza(model: Model)
	local plaza = folder(model, "Plaza")
	for _, x in { 172, 244, 262 } do
		box(plaza, "Planter", x - 3, x + 3, PLAZA, PLAZA + 1.6, 7.5, 10, C.Planter, Enum.Material.SmoothPlastic)
		box(plaza, "Hedge", x - 2.7, x + 2.7, PLAZA + 1.6, PLAZA + 3, 7.8, 9.7, C.Leaf, Enum.Material.LeafyGrass)
	end
	for _, x in { 184, 230 } do
		box(plaza, "BenchSeat", x - 3, x + 3, PLAZA + 1.5, PLAZA + 1.9, 14, 15.6, C.Wood, Enum.Material.Wood)
		box(plaza, "BenchLeg", x - 2.8, x - 2.3, PLAZA, PLAZA + 1.5, 14.1, 15.5, C.Charcoal, Enum.Material.Metal)
		box(plaza, "BenchLeg", x + 2.3, x + 2.8, PLAZA, PLAZA + 1.5, 14.1, 15.5, C.Charcoal, Enum.Material.Metal)
	end

	-- Flags on three poles by the corner, where the road can see them.
	for i, x in { 152, 157, 162 } do
		post(plaza, "Flagpole", x, 9, PLAZA, 24, 0.35, C.White, Enum.Material.Metal)
		ball(plaza, "Finial", Vector3.new(x, 24.2, 9), 0.6, C.Gold, Enum.Material.Metal)
		local flag = box(plaza, "Flag", x + 0.2, x + 4.6, 20.4, 23.4, 8.95, 9.05, ({ C.Navy, C.Gold, C.Navy })[i], Enum.Material.Fabric, {
			collide = false,
			shadow = false,
			query = false,
		})
		if i ~= 2 then
			sign(flag, Enum.NormalId.Front, "M", C.Gold, false)
			sign(flag, Enum.NormalId.Back, "M", C.Gold, false)
		end
	end

	-- The pylon at the corner of the lot and the plaza: the one thing a driver on the road reads.
	local pylon = folder(model, "Pylon")
	box(pylon, "Base", 140.6, 147.4, WALK, 2.2, 8, 11, C.Kerb, Enum.Material.Concrete)
	local body = box(pylon, "Body", 141.2, 146.8, 2.2, 26, 8.6, 10.4, C.Navy, Enum.Material.SmoothPlastic)
	body.Name = "Body"
	local upper = box(pylon, "Upper", 141.3, 146.7, 15, 25.5, 8.55, 10.45, C.Navy, Enum.Material.SmoothPlastic, { collide = false })
	sign(upper, Enum.NormalId.Front, "MERIDIAN\nMOTORS", C.Gold, true)
	sign(upper, Enum.NormalId.Back, "MERIDIAN\nMOTORS", C.Gold, true)
	local lower = box(pylon, "Lower", 141.3, 146.7, 4, 13.5, 8.55, 10.45, C.Navy, Enum.Material.SmoothPlastic, { collide = false })
	sign(lower, Enum.NormalId.Front, "LUXURY\n•\nEVERYDAY\n•\nTEST\nDRIVES", C.White, true, Enum.Font.GothamBold)
	sign(lower, Enum.NormalId.Back, "LUXURY\n•\nEVERYDAY\n•\nTEST\nDRIVES", C.White, true, Enum.Font.GothamBold)
	box(pylon, "Cap", 141, 147, 26, 26.6, 8.4, 10.6, C.Gold, Enum.Material.Neon, { shadow = false })
end

-- ---------------------------------------------------------------------------------------------
-- Every car spot, and the markers the services read.
-- ---------------------------------------------------------------------------------------------
local function buildSlots(model: Model)
	local stock = folder(model, "LotStock")
	for rowIndex, row in { ROW_A, ROW_B } do
		local z = (row.z0 + row.z1) / 2
		for i = 0, BAY_COUNT - 1 do
			local x = BAY_FIRST_X + BAY_WIDTH * i + BAY_WIDTH / 2
			local kind = LOT_KINDS[(i + rowIndex) % #LOT_KINDS + 1]
			slot(stock, kind, "Lot", x, LOT, z, 0)
		end
	end
	mark(model, "TestDriveBay", 114, LOT, 22, 0)
	mark(model, "TestDriveBay", 132, LOT, 22, 0)
	mark(model, "TestDriveReturn", 122, LOT, 46, 0)
end

--[[
	Lay the dealership with its south-west corner at `corner`, on the grass: +X runs east along
	the road, +Z north away from it. Replaces any dealership already under `parent`.
]]
function DealershipBuild.Build(corner: CFrame, parent: Instance): Model
	local existing = parent:FindFirstChild(DealershipBuild.ModelName)
	if existing then
		existing:Destroy()
	end
	origin = corner
	local model = Instance.new("Model")
	model.Name = DealershipBuild.ModelName
	model:SetAttribute("Origin", corner)
	-- Built while unparented, so the engine does not reflow streaming and physics after every part.
	buildGround(model)
	buildLot(model)
	buildShell(model)
	buildInterior(model)
	buildPlaza(model)
	buildSlots(model)
	model.WorldPivot = corner
	model.Parent = parent
	return model
end

return DealershipBuild
