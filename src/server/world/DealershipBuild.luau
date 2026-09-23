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
	price it actually charges. A slot is invisible: it is a marker, and an outline on an empty bay
	is clutter.

	WHERE IT IS DESIGNED. Offline, in sandbox/dealership: export.py runs this file under a stand-in
	for Roblox's API and writes it as a drop-in .rbxmx for AGES and as an open-field sandbox place
	(stocked with the game's own display cars); preview.py draws it by day and night, signs and
	all; audit.py lists faces that would z-fight. Run the three after any change here, then
	tools/check.py.

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
-- A double-height hall: thirty studs to the ceiling, with a mezzanine round the back. It was
-- twenty, one tall storey, and from the road the building read as a shed with a glass front.
local CEIL = FLOOR + 30
local ROOF = CEIL + 1.2
local PARAPET = ROOF + 3.3
local MEZZ = FLOOR + 12 -- the underside of the mezzanine slab
local UPPER = MEZZ + 0.8 -- the mezzanine's floor
local LOT = 0.15 -- asphalt top
local WALK = 0.25 -- sidewalk and walkway top
local PLAZA = 0.3

local C = {
	White = Color3.fromRGB(240, 240, 238),
	OffWhite = Color3.fromRGB(226, 224, 218),
	Charcoal = Color3.fromRGB(38, 40, 46),
	-- Aluminium composite panel: the fascia and cladding. Light, so the navy-and-gold sign on it
	-- reads from the road -- on the dark fascia it started on, the sign disappeared into it.
	Panel = Color3.fromRGB(212, 216, 220),
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
	Bark = Color3.fromRGB(92, 66, 46),
	Green = Color3.fromRGB(58, 168, 92),
	Ceiling = Color3.fromRGB(46, 48, 54),
	Joint = Color3.fromRGB(196, 194, 188),
	ScreenGlow = Color3.fromRGB(226, 232, 240),
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

	The pixel density is worked out from the text, not fixed. TextScaled never draws text larger
	than 100 pixels, so the density decides both how big the lettering can get and how sharp it
	is: at a fixed 40 pixels a stud the four-stud fascia sign capped its lettering at two and a
	half studs, and a density taken from the face's short side alone left a long word on a narrow
	face -- CUSTOMERS on the car park, the pylon's name -- fitted at 15 pixels and stretched over
	a stud and a half, small and soft. So: estimate the font size, in studs, the text can have on
	this face -- the height shared between its lines, or the width its longest line needs at
	about 0.72 of the font size a character, whichever is less -- and set the density so that size
	is exactly 100 pixels.
]]
local function sign(part: BasePart, face: Enum.NormalId, text: string, color: Color3, glow: boolean?, font: Enum.Font?)
	local across, up = faceSize(part, face)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	local lines = string.split(text, "\n")
	local longest = 1
	for _, line in lines do
		longest = math.max(longest, utf8.len(line) or #line)
	end
	local fontStuds = math.min(up / #lines, across / (0.72 * longest))
	-- Up to 100 a stud: a small face (a screen, a spec card) keeps its size but gets sharper.
	gui.PixelsPerStud = math.clamp(100 / fontStuds, 4, 100)
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

local function light(part: BasePart, kind: "Point" | "Spot", brightness: number, range: number, color: Color3?, angle: number?): Light
	if kind == "Point" then
		local l = Instance.new("PointLight")
		l.Brightness = brightness
		l.Range = range
		l.Color = color or C.Warm
		l.Shadows = false
		l.Parent = part
		return l
	end
	local l = Instance.new("SpotLight")
	l.Brightness = brightness
	l.Range = range
	l.Angle = angle or 60
	l.Face = Enum.NormalId.Bottom
	l.Color = color or C.Warm
	l.Shadows = false
	l.Parent = part
	return l
end

local function folder(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

--[[
	Marks a model as the block stand-in for a real prop. world/DealershipDressing swaps it at
	server start for the model content/DealershipProps names under `prop`, fitted to this one's
	space; until that prop is uploaded, or if it fails to load, the stand-in is what stays.
	`facing` is where its front points (0 = local -Z, as for chairs); `variant` picks one of a
	pack's objects. The attribute names are DealershipDressing's, written out here because this
	file requires nothing from the game.
]]
local function standIn(model: Model, prop: string, facing: number?, variant: number?): Model
	model:SetAttribute("Prop", prop)
	if facing then
		model:SetAttribute("Facing", facing)
	end
	if variant then
		model:SetAttribute("Variant", variant)
	end
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
	the same "front is -Z" the chassis is built on. Invisible: it is a marker for the car that
	DealershipService stands on it, and a gold outline on an empty bay or turntable is clutter.
]]
local function slot(parent: Instance, vehicleId: string, display: string, x: number, y: number, z: number, facingDegrees: number): Part
	local part = Instance.new("Part")
	part.Name = "CarSlot"
	part.Size = Vector3.new(7, 0.2, 16)
	part.CFrame = at(x, y + 0.1, z) * CFrame.Angles(0, math.rad(facingDegrees), 0)
	style(part, C.Gold, Enum.Material.SmoothPlastic, {
		collide = false,
		transparency = 1,
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
	local model = standIn(folder(parent, "Chair"), "chair", facingDegrees)
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
	local model = standIn(folder(parent, "Plant"), "plant")
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
	box(g, "Sidewalk", 140, 272, 0, WALK, 0, 6, C.Paving, Enum.Material.Concrete)
	box(g, "Sidewalk", 286, 310, 0, WALK, 0, 6, C.Paving, Enum.Material.Concrete)
	box(g, "Driveway", 104, 140, 0, 0.2, 0, 8, C.Asphalt, Enum.Material.Asphalt)
	box(g, "Kerb", 6, 104, 0, 0.45, 7.2, 8, C.Kerb, Enum.Material.Concrete)
	box(g, "Lot", 6, 140, 0, LOT, 8, 114, C.Asphalt, Enum.Material.Asphalt)
	box(g, "Plaza", 140, 270, 0, PLAZA, 6, 22, C.Paving, Enum.Material.Slate)
	-- Bands across the paving every eight studs: large-format stone, not one grey sheet.
	for x = 148, 264, 8 do
		box(g, "PavingBand", x - 0.2, x + 0.2, PLAZA, PLAZA + 0.02, 6, 22, C.Kerb, Enum.Material.Slate, { collide = false, query = false, shadow = false })
	end
	box(g, "Walkway", 140, 150, 0, WALK, 22, 98, C.Paving, Enum.Material.Slate)
	box(g, "HedgeNorth", 6, 130, 0, 2.6, 114.5, 117, C.Leaf, Enum.Material.LeafyGrass)
	box(g, "HedgeWest", 2.5, 5, 0, 2.6, 8, 117, C.Leaf, Enum.Material.LeafyGrass)
	box(g, "HedgeEast", 266, 268.5, 0, 2.6, 22, 98, C.Leaf, Enum.Material.LeafyGrass)
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

	-- Balloon clusters at the two ends of the lot's frontage: by the driveway, and at the far
	-- corner. Not beside the pylon, where they hung across its lower panels from the road.
	local balloons = folder(lot, "Balloons")
	for _, base in { Vector3.new(102.5, 0, 4), Vector3.new(8, 0, 4) } do
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

	-- Feather flags along the kerb, between the road and the front row.
	local feathers = folder(lot, "FeatherFlags")
	for _, f in { { 9, C.Red, "SALE" }, { 19, C.Blue, "DEALS" }, { 87, C.Red, "SALE" } } do
		local x, colour, text = f[1] :: number, f[2] :: Color3, f[3] :: string
		local z = 11.5
		box(feathers, "Foot", x - 0.8, x + 0.8, LOT, LOT + 0.3, z - 0.8, z + 0.8, C.Charcoal, Enum.Material.Metal)
		post(feathers, "Pole", x, z, LOT, LOT + 13.4, 0.25, C.Kerb, Enum.Material.Metal)
		local flag = box(feathers, "Feather", x + 0.15, x + 2.5, LOT + 3.6, LOT + 12.2, z - 0.04, z + 0.04, colour, Enum.Material.Fabric, {
			collide = false,
			shadow = false,
			query = false,
		})
		-- Stepped in at the top, the way a feather flag curves off its pole.
		box(feathers, "Tip", x + 0.15, x + 1.9, LOT + 12.2, LOT + 12.9, z - 0.04, z + 0.04, colour, Enum.Material.Fabric, {
			collide = false,
			shadow = false,
			query = false,
		})
		local letters = table.concat(string.split(text, ""), "\n")
		sign(flag, Enum.NormalId.Front, letters, C.White, false, Enum.Font.GothamBlack)
		sign(flag, Enum.NormalId.Back, letters, C.White, false, Enum.Font.GothamBlack)
	end

	-- "EVERYDAY CARS" over the front of the lot, high: at 7 studs it hung at a player's eye
	-- line and walled the front row off from the road it is meant to be sold to.
	local banner = folder(lot, "Banner")
	post(banner, "PostL", 34, 10, LOT, 15.2, 0.6, C.Charcoal, Enum.Material.Metal)
	post(banner, "PostR", 76, 10, LOT, 15.2, 0.6, C.Charcoal, Enum.Material.Metal)
	local board = box(banner, "Board", 33, 77, 11.8, 15.2, 9.8, 10.2, C.Navy, Enum.Material.SmoothPlastic)
	box(banner, "Trim", 33, 77, 11.5, 11.8, 9.75, 10.25, C.Gold, Enum.Material.Neon, { collide = false, shadow = false })
	box(banner, "Cap", 32.6, 77.4, 15.2, 15.5, 9.6, 10.4, C.Panel, Enum.Material.Metal)
	for _, x in { 44, 66 } do
		box(banner, "FloodArm", x - 0.15, x + 0.15, 15.5, 15.8, 10.4, 12.2, C.Charcoal, Enum.Material.Metal, { collide = false })
		local flood = box(banner, "Flood", x - 1, x + 1, 15.3, 16, 12.2, 13.4, C.Charcoal, Enum.Material.Metal, { collide = false })
		light(flood, "Spot", 1.8, 32, C.Warm, 120)
		box(banner, "FloodLens", x - 0.9, x + 0.9, 15.25, 15.3, 12.3, 13.3, C.Warm, Enum.Material.Neon, { collide = false, shadow = false, query = false })
	end
	sign(board, Enum.NormalId.Front, "EVERYDAY CARS  •  DRIVE AWAY TODAY", C.Gold, true)
	sign(board, Enum.NormalId.Back, "EVERYDAY CARS  •  DRIVE AWAY TODAY", C.Gold, true)

	-- The lot's sales cabin, in the back strip behind row B.
	local cabin = folder(lot, "SalesCabin")
	box(cabin, "Floor", 10, 34, LOT, 0.55, 90, 110, C.Wood, Enum.Material.WoodPlanks)
	box(cabin, "WallN", 10, 34, 0.55, 9, 109.5, 110, C.White, Enum.Material.SmoothPlastic)
	box(cabin, "WallW", 10, 10.5, 0.55, 9, 90.5, 109.5, C.White, Enum.Material.SmoothPlastic)
	box(cabin, "WallE", 33.5, 34, 0.55, 9, 90.5, 109.5, C.White, Enum.Material.SmoothPlastic)
	box(cabin, "WallS1", 10, 14, 0.55, 9, 90, 90.5, C.White, Enum.Material.SmoothPlastic)
	box(cabin, "WallS2", 24, 26, 0.55, 7.5, 90, 90.5, C.White, Enum.Material.SmoothPlastic)
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
	-- The porch: a deck out from the door, a bench under the eaves, planters either side.
	box(cabin, "Deck", 12, 34, LOT, 0.5, 86, 90, C.Wood, Enum.Material.WoodPlanks)
	box(cabin, "Step", 26, 30, LOT, 0.3, 85, 86, C.Wood, Enum.Material.WoodPlanks)
	for _, x in { 13.5, 32.5 } do
		post(cabin, "PorchPost", x, 88.9, 0.5, 9, 0.5, C.White, Enum.Material.SmoothPlastic)
	end
	local porchBench = standIn(folder(cabin, "Bench"), "bench", 0)
	box(porchBench, "BenchSeat", 15, 22, 1.9, 2.2, 88, 89.4, C.Wood, Enum.Material.Wood)
	for _, x in { 15.5, 21.5 } do
		box(porchBench, "BenchLeg", x - 0.2, x + 0.2, 0.5, 1.9, 88.2, 89.2, C.Charcoal, Enum.Material.Metal)
	end
	plant(cabin, 24.8, 87.5, 0.5, 1.4)
	plant(cabin, 31.2, 87.5, 0.5, 1.4)
	local porchLamp = box(cabin, "PorchLamp", 27.3, 28.7, 8.4, 9, 88.8, 89.4, C.Warm, Enum.Material.Neon, { collide = false, shadow = false })
	light(porchLamp, "Spot", 1.2, 12, C.Warm, 100)
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
				box(parent, "Mullion", s - 0.3, s + 0.3, FLOOR, CEIL - 2.5, fixed, fixed + 1, C.Charcoal, Enum.Material.Metal)
			else
				box(parent, "Mullion", fixed, fixed + 1, FLOOR, CEIL - 2.5, s - 0.3, s + 0.3, C.Charcoal, Enum.Material.Metal)
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
		{ SHOW.x0 + 1, SHOW.x0 + 2.2, SHOW.z0 + 2.2, SHOW.z1 - 2.2 },
		{ SHOW.x1 - 2.2, SHOW.x1 - 1, SHOW.z0 + 2.2, SHOW.z1 - 2.2 },
	} do
		box(shell, "Inlay", b[1], b[2], FLOOR, FLOOR + 0.02, b[3], b[4], C.DarkFloor, Enum.Material.Marble, { collide = false, query = false })
	end
	box(shell, "Runway", 201, 213, FLOOR, FLOOR + 0.02, SHOW.z0 + 2.2, 60, C.DarkFloor, Enum.Material.Marble, { collide = false, query = false, reflectance = 0.2 })
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
	box(shell, "FasciaSouth", SHOW.x0 - 1.4, SHOW.x1 + 1.4, CEIL - 0.6, PARAPET, SHOW.z0 - 1.4, SHOW.z0 - 0.8, C.Panel, Enum.Material.SmoothPlastic, { reflectance = 0.08 })
	box(shell, "FasciaWest", SHOW.x0 - 1.4, SHOW.x0 - 0.8, CEIL - 0.6, PARAPET, SHOW.z0 - 0.8, SHOW.z1 + 1.4, C.Panel, Enum.Material.SmoothPlastic, { reflectance = 0.08 })
	box(shell, "ParapetNorth", SHOW.x0 - 0.8, SHOW.x1 + 0.8, ROOF, PARAPET, SHOW.z1 + 0.8, SHOW.z1 + 1.4, C.Panel, Enum.Material.SmoothPlastic)
	box(shell, "ParapetEast", SHOW.x1 + 0.8, SHOW.x1 + 1.4, ROOF, PARAPET, SHOW.z0 - 0.8, SHOW.z1 + 1.4, C.Panel, Enum.Material.SmoothPlastic)
	-- A dark reveal under the fascia: the shadow line that makes the panel read as hung on the frame.
	box(shell, "Reveal", SHOW.x0 - 1.5, SHOW.x1 + 1.5, CEIL - 0.9, CEIL - 0.6, SHOW.z0 - 1.5, SHOW.z0 - 0.7, C.Charcoal, Enum.Material.Metal, { shadow = false })
	box(shell, "Reveal", SHOW.x0 - 1.5, SHOW.x0 - 0.7, CEIL - 0.9, CEIL - 0.6, SHOW.z0 - 0.7, SHOW.z1 + 1.5, C.Charcoal, Enum.Material.Metal, { shadow = false })

	-- The lettering stands on the fascia itself, and a white LED line runs out either side of it:
	-- a navy box on a silver band read as a sign bolted on, not as the building's name.
	local brand = box(shell, "BrandSign", 168, 246, CEIL + 0.2, PARAPET - 0.3, SHOW.z0 - 1.8, SHOW.z0 - 1.4, C.Panel, Enum.Material.SmoothPlastic)
	sign(brand, Enum.NormalId.Front, "MERIDIAN MOTORS", C.Gold, true)
	local ledY = (CEIL - 0.6 + PARAPET) / 2
	for _, run in { { SHOW.x0 - 1, 166 }, { 248, SHOW.x1 + 1 } } do
		box(shell, "FasciaLED", run[1], run[2], ledY - 0.1, ledY + 0.1, SHOW.z0 - 1.5, SHOW.z0 - 1.4, C.White, Enum.Material.Neon, { collide = false, shadow = false, query = false })
	end
	for _, run in { { SHOW.z0 - 0.7, 32 }, { 88, SHOW.z1 + 1 } } do
		box(shell, "FasciaLED", SHOW.x0 - 1.5, SHOW.x0 - 1.4, ledY - 0.1, ledY + 0.1, run[1], run[2], C.White, Enum.Material.Neon, { collide = false, shadow = false, query = false })
	end
	-- Joints between the aluminium panels, one over every mullion: a plain band reads as paint.
	for i = 1, 13 do
		local x = SHOW.x0 + (SHOW.x1 - SHOW.x0) / 14 * i
		box(shell, "PanelJoint", x - 0.06, x + 0.06, CEIL - 0.6, PARAPET, SHOW.z0 - 1.45, SHOW.z0 - 1.35, C.Joint, Enum.Material.Metal, { collide = false, shadow = false, query = false })
	end
	for i = 1, 7 do
		local z = SHOW.z0 + (SHOW.z1 - SHOW.z0) / 8 * i
		box(shell, "PanelJoint", SHOW.x0 - 1.45, SHOW.x0 - 1.35, CEIL - 0.6, PARAPET, z - 0.06, z + 0.06, C.Joint, Enum.Material.Metal, { collide = false, shadow = false, query = false })
	end
	local side = box(shell, "SideSign", SHOW.x0 - 1.8, SHOW.x0 - 1.4, CEIL + 0.2, PARAPET - 0.3, 34, 86, C.Panel, Enum.Material.SmoothPlastic)
	sign(side, Enum.NormalId.Left, "MERIDIAN MOTORS", C.Gold, true)

	-- A low hedge along the foot of the glass, broken for the doors and the tree pits: planting at
	-- the base is what stops a glass wall reading as a shop window onto a car park.
	for _, run in { { 152, 164 }, { 173, 192 }, { 222, 244 }, { 253, 262 } } do
		box(shell, "HedgeBed", run[1], run[2], PLAZA, PLAZA + 0.7, SHOW.z0 - 2.7, SHOW.z0 - 0.5, C.Planter, Enum.Material.SmoothPlastic)
		box(shell, "Hedge", run[1] + 0.2, run[2] - 0.2, PLAZA + 0.7, PLAZA + 2.3, SHOW.z0 - 2.5, SHOW.z0 - 0.7, C.Leaf, Enum.Material.LeafyGrass)
	end

	-- The entrance portal: silver fins either side of the doors, up the full height of the glass
	-- to a lintel under the fascia, lit gold on their inner faces. On a double-height front, a
	-- single-storey canopy on its own read as a side door; the portal says where the way in is.
	local portal = folder(shell, "Portal")
	local top = CEIL - 0.9
	for _, fin in { { 195.4, 196.8, 196.8, 196.9 }, { 217.2, 218.6, 217.1, 217.2 } } do
		box(portal, "Fin", fin[1], fin[2], PLAZA, top - 2.5, 16.5, 21.6, C.Panel, Enum.Material.SmoothPlastic, { reflectance = 0.08 })
		box(portal, "FinGlow", fin[3], fin[4], PLAZA + 0.6, top - 2.9, 20.2, 21.2, C.Gold, Enum.Material.Neon, { collide = false, shadow = false, query = false })
		local up = box(portal, "FinUplight", fin[1] + 0.2, fin[2] - 0.2, PLAZA, PLAZA + 0.25, 15.6, 16.4, C.Warm, Enum.Material.Neon, { collide = false, shadow = false, query = false })
		local beam = light(up, "Spot", 1.8, 30, C.Warm, 40) :: SpotLight
		beam.Face = Enum.NormalId.Top
	end
	box(portal, "Lintel", 195.4, 218.6, top - 2.5, top, 16.5, 21.6, C.Panel, Enum.Material.SmoothPlastic, { reflectance = 0.08 })
	box(portal, "LintelGlow", 196.9, 217.1, top - 2.6, top - 2.5, 20.2, 21.2, C.Gold, Enum.Material.Neon, { collide = false, shadow = false, query = false })

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
	light(can, "Spot", brightness, 36, C.Warm, 45)
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
	-- The screen on the timber wall behind the car. It replaced a navy block that stood in front of
	-- the wall and hid it: the timber is the warm thing in the room, and it should be what frames
	-- the flagship.
	box(hero, "ScreenBezel", 197.4, 216.6, FLOOR + 3.6, FLOOR + 10.4, SHOW.z1 - 2.65, SHOW.z1 - 2.5, C.Charcoal, Enum.Material.Metal)
	local screen = box(hero, "Screen", 198, 216, FLOOR + 4, FLOOR + 10, SHOW.z1 - 2.8, SHOW.z1 - 2.65, C.ScreenGlow, Enum.Material.Neon, { shadow = false })
	sign(screen, Enum.NormalId.Front, "MERIDIAN", C.Navy, true)
	spot(hero, 201, 70, 3.5)
	spot(hero, 213, 70, 3.5)

	-- A ring of light hung over the flagship: the showroom's one piece of theatre, and the
	-- thing a player sees first through the doors, at the far end of the runway.
	local halo = folder(hero, "Halo")
	for ringIndex, ring in { { y = FLOOR + 20.5, r = 9, n = 32 }, { y = FLOOR + 21.7, r = 6.4, n = 24 } } do
		for i = 0, ring.n - 1 do
			local a = i / ring.n * math.pi * 2
			local seg = Instance.new("Part")
			seg.Name = "Ring"
			seg.Size = Vector3.new(0.45, 0.35, ring.r * 2 * math.pi / ring.n * 1.04)
			seg.CFrame = at(207 + ring.r * math.cos(a), ring.y, 73 + ring.r * math.sin(a)) * CFrame.Angles(0, -a, 0)
			style(seg, C.Warm, Enum.Material.Neon, { collide = false, shadow = false, query = false })
			seg.Parent = halo
			-- The neon is the look; two lights on the outer ring are the light. Every lamp in a room
			-- costs on a phone, and seven here lit nothing the other two did not.
			if ringIndex == 1 and i % 16 == 0 then
				light(seg, "Point", 1, 20)
			end
		end
		for i = 0, 2 do
			local a = i / 3 * math.pi * 2 + math.pi / 2 + ringIndex * 0.5
			local x, z = 207 + ring.r * math.cos(a), 73 + ring.r * math.sin(a)
			box(halo, "Cable", x - 0.04, x + 0.04, ring.y + 0.2, CEIL - 0.15, z - 0.04, z + 0.04, C.Charcoal, Enum.Material.Metal, {
				collide = false,
				shadow = false,
				query = false,
			})
		end
	end

	-- The sales counter, level with the side door. The auto_dealer place point stands in front of it.
	local counter = folder(inside, "Counter")
	box(counter, "Body", 154, 172, FLOOR, FLOOR + 3.6, 70, 73.5, C.Navy, Enum.Material.SmoothPlastic)
	box(counter, "Top", 153.6, 172.4, FLOOR + 3.6, FLOOR + 3.9, 69.6, 73.9, C.White, Enum.Material.Marble)
	box(counter, "Kick", 154, 172, FLOOR + 0.2, FLOOR + 0.35, 69.85, 70, C.Gold, Enum.Material.Neon, { collide = false, shadow = false })
	monitor(counter, 158, 72.5, FLOOR + 3.9, 180)
	monitor(counter, 167, 72.5, FLOOR + 3.9, 180)
	chair(counter, 158, 75.4, FLOOR, 0, C.Leather)
	chair(counter, 167, 75.4, FLOOR, 0, C.Leather)
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
	plant(desks, 255.5, 58, FLOOR, 2.4)

	-- Two glass offices in the north-east corner.
	local offices = folder(inside, "Offices")
	local officeGlass: Opts = { transparency = 0.6, reflectance = 0.1, query = false, shadow = false }
	for i, span in { { 224, 243, "FINANCE" }, { 243, 262, "MANAGER" } } do
		local x0, x1 = span[1] :: number, span[2] :: number
		local mid = (x0 + x1) / 2
		-- The mezzanine above is their ceiling: glass to a head, the head to the slab.
		local top = MEZZ - 1.5
		box(offices, "Glass", x0, mid - 2, FLOOR, top, 80, 80.3, C.Glass, Enum.Material.Glass, officeGlass)
		box(offices, "Glass", mid + 2, x1, FLOOR, top, 80, 80.3, C.Glass, Enum.Material.Glass, officeGlass)
		box(offices, "Head", x0, x1, top, MEZZ, 80, 80.3, C.OffWhite, Enum.Material.SmoothPlastic)
		box(offices, "Head", mid - 2, mid + 2, FLOOR + 10, top, 80, 80.3, C.OffWhite, Enum.Material.SmoothPlastic)
		if i == 1 then
			box(offices, "Glass", 224, 224.3, FLOOR, top, 80.3, 97, C.Glass, Enum.Material.Glass, officeGlass)
		end
		box(offices, "Glass", x1 - 0.15, x1 + 0.15, FLOOR, top, 80.3, 97, C.Glass, Enum.Material.Glass, officeGlass)
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
	local sofa = standIn(folder(lounge, "Sofa"), "couch", 0)
	box(sofa, "SofaBase", 160, 178, FLOOR, FLOOR + 2, 92, 95.5, C.Fabric, Enum.Material.Fabric)
	box(sofa, "SofaBack", 160, 178, FLOOR + 2, FLOOR + 4.6, 95, 96.5, C.Fabric, Enum.Material.Fabric)
	box(sofa, "SofaArm", 159, 160, FLOOR, FLOOR + 3.2, 92, 96.5, C.Fabric, Enum.Material.Fabric)
	box(sofa, "SofaArm", 178, 179, FLOOR, FLOOR + 3.2, 92, 96.5, C.Fabric, Enum.Material.Fabric)
	box(lounge, "CoffeeTable", 164, 174, FLOOR + 1.3, FLOOR + 1.6, 85, 89, C.Wood, Enum.Material.Wood)
	box(lounge, "TableLegs", 165, 173, FLOOR, FLOOR + 1.3, 86, 88, C.Charcoal, Enum.Material.Metal)
	chair(lounge, 159, 85, FLOOR, 270, C.Leather)
	chair(lounge, 181, 85, FLOOR, 90, C.Leather)
	local tv = box(lounge, "TV", 160, 176, FLOOR + 4, FLOOR + 10.5, 96.6, 97, C.Screen, Enum.Material.SmoothPlastic)
	sign(tv, Enum.NormalId.Front, "DRIVE THE DREAM", C.Gold, true)
	box(lounge, "CoffeeBar", 151, 154.5, FLOOR, FLOOR + 3.4, 81, 96, C.Navy, Enum.Material.SmoothPlastic)
	box(lounge, "CoffeeBarTop", 151, 155, FLOOR + 3.4, FLOOR + 3.7, 80.6, 96.4, C.White, Enum.Material.Marble)
	-- Faces +X, into the lounge.
	local machine = standIn(folder(lounge, "CoffeeMachine"), "coffee", 270)
	box(machine, "Body", 151.4, 154, FLOOR + 3.7, FLOOR + 6.2, 84, 86.5, C.Charcoal, Enum.Material.Metal)
	box(machine, "CoffeeLight", 154, 154.1, FLOOR + 5.2, FLOOR + 5.6, 84.6, 85.9, C.Gold, Enum.Material.Neon, { collide = false })
	for _, z in { 89, 90, 91 } do
		post(lounge, "Cup", 153, z, FLOOR + 3.7, FLOOR + 4.3, 0.5, C.White, Enum.Material.SmoothPlastic)
	end
	plant(lounge, 183.5, 95, FLOOR, 2.2)
	-- Many small pendants rather than one big light: the cheap signal that a space is lived in.
	for index, p in { { 163, 84 }, { 169, 84 }, { 175, 84 }, { 163, 90 }, { 169, 90 }, { 175, 90 } } do
		box(lounge, "PendantCord", p[1] - 0.04, p[1] + 0.04, 11, MEZZ, p[2] - 0.04, p[2] + 0.04, C.Charcoal, Enum.Material.Metal, {
			collide = false,
			shadow = false,
			query = false,
		})
		local lamp = ball(lounge, "Pendant", Vector3.new(p[1], 10.6, p[2]), 1.2, C.Warm, Enum.Material.Neon)
		-- All six glow; the middle two cast, for the lounge.
		if index == 2 or index == 5 then
			light(lamp, "Point", 0.9, 13)
		end
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
	local banner = box(ceiling, "WallBanner", SHOW.x1 - 1.4, SHOW.x1 - 1, FLOOR + 17, FLOOR + 21.5, 28, 76, C.Navy, Enum.Material.SmoothPlastic)
	sign(banner, Enum.NormalId.Left, "PERFORMANCE  •  LUXURY  •  EVERYDAY", C.Gold, true)
end

-- ---------------------------------------------------------------------------------------------
-- The mezzanine: an upper floor round the back of the double-height hall. A west wing over the
-- lounge (the owners' lounge), an east wing over the offices (the heritage gallery), and a
-- bridge between them across the timber wall, reached by a floating stair up the east wall.
-- The middle stays open to the ceiling: the flagship keeps its full height, and from upstairs
-- the whole floor is on show over the glass.
-- ---------------------------------------------------------------------------------------------
local WEST_WING = { x0 = SHOW.x0 + 1, x1 = 186, z0 = 78, z1 = SHOW.z1 - 1 }
local EAST_WING = { x0 = 224, x1 = SHOW.x1 - 1, z0 = 78, z1 = SHOW.z1 - 1 }
local BRIDGE = { x0 = 186, x1 = 224, z0 = 91, z1 = SHOW.z1 - 2.6 }
local STAIR = { x0 = SHOW.x1 - 5.6, x1 = SHOW.x1 - 1.4, z0 = 50, steps = 16, run = 1.75 }

-- A glass rail along one open edge of the mezzanine: a pane, a steel handrail, and posts.
local function balustrade(parent: Instance, x0: number, x1: number, z0: number, z1: number)
	box(parent, "RailGlass", x0, x1, UPPER, UPPER + 3.3, z0, z1, C.Glass, Enum.Material.Glass, {
		transparency = 0.55,
		reflectance = 0.15,
		query = false,
		shadow = false,
	})
	local along = x1 - x0 > z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	if along then
		box(parent, "Handrail", x0, x1, UPPER + 3.3, UPPER + 3.6, cz - 0.15, cz + 0.15, C.Panel, Enum.Material.Metal)
		local count = math.max(1, math.floor((x1 - x0) / 6))
		for i = 0, count do
			local x = x0 + 0.3 + (x1 - x0 - 0.6) * i / count
			box(parent, "RailPost", x - 0.1, x + 0.1, UPPER, UPPER + 3.3, cz - 0.12, cz + 0.12, C.Charcoal, Enum.Material.Metal)
		end
	else
		box(parent, "Handrail", cx - 0.15, cx + 0.15, UPPER + 3.3, UPPER + 3.6, z0, z1, C.Panel, Enum.Material.Metal)
		local count = math.max(1, math.floor((z1 - z0) / 6))
		for i = 0, count do
			local z = z0 + 0.3 + (z1 - z0 - 0.6) * i / count
			box(parent, "RailPost", cx - 0.12, cx + 0.12, UPPER, UPPER + 3.3, z - 0.1, z + 0.1, C.Charcoal, Enum.Material.Metal)
		end
	end
end

-- A sloped part from `a` to `b` (local points), `width` across and `depth` thick: stair stringers
-- and the stair's rail.
local function slope(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, depth: number, color: Color3, material: Enum.Material, opts: Opts?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(width, depth, (b - a).Magnitude)
	part.CFrame = origin * CFrame.lookAt((a + b) / 2, b)
	style(part, color, material, opts)
	part.Parent = parent
	return part
end

-- A sofa facing `facing` degrees, built at (x0..x1, z) with its back to +Z before turning: here
-- only ever 0 (facing the rail) or 180.
local function sofa(parent: Instance, x0: number, x1: number, z: number, y: number, color: Color3): Model
	local model = standIn(folder(parent, "Sofa"), "couch", 0)
	box(model, "SofaBase", x0 + 1, x1 - 1, y, y + 2, z, z + 3.5, color, Enum.Material.Fabric)
	box(model, "SofaBack", x0 + 1, x1 - 1, y + 2, y + 4.6, z + 3, z + 4.5, color, Enum.Material.Fabric)
	box(model, "SofaArm", x0, x0 + 1, y, y + 3.2, z, z + 4.5, color, Enum.Material.Fabric)
	box(model, "SofaArm", x1 - 1, x1, y, y + 3.2, z, z + 4.5, color, Enum.Material.Fabric)
	return model
end

local function buildMezzanine(model: Model)
	local mezz = folder(model, "Mezzanine")
	for _, part in { WEST_WING, EAST_WING, BRIDGE } do
		box(mezz, "Slab", part.x0, part.x1, MEZZ, UPPER, part.z0, part.z1, C.OffWhite, Enum.Material.SmoothPlastic)
	end
	-- A panel edge on every open side, with a warm line of light under it: the slab reads as a
	-- floor floating in the hall, not a shelf.
	local edges = {
		{ WEST_WING.x0, WEST_WING.x1, WEST_WING.z0 - 0.25, WEST_WING.z0 },
		{ WEST_WING.x1, WEST_WING.x1 + 0.25, WEST_WING.z0 - 0.25, BRIDGE.z0 },
		{ BRIDGE.x0 + 0.25, BRIDGE.x1 - 0.25, BRIDGE.z0 - 0.25, BRIDGE.z0 },
		{ EAST_WING.x0 - 0.25, EAST_WING.x0, EAST_WING.z0 - 0.25, BRIDGE.z0 },
		{ EAST_WING.x0, STAIR.x0, EAST_WING.z0 - 0.25, EAST_WING.z0 },
	}
	for _, e in edges do
		box(mezz, "Edge", e[1], e[2], MEZZ - 0.5, UPPER, e[3], e[4], C.Panel, Enum.Material.SmoothPlastic)
		box(mezz, "EdgeGlow", e[1], e[2], MEZZ - 0.6, MEZZ - 0.5, e[3], e[4], C.Warm, Enum.Material.Neon, { collide = false, shadow = false, query = false })
	end

	-- Glass rails on the open edges, each stopping short of the next so no two panes overlap.
	local rails = folder(mezz, "Rails")
	balustrade(rails, WEST_WING.x0, WEST_WING.x1 - 0.5, WEST_WING.z0 + 0.2, WEST_WING.z0 + 0.35)
	balustrade(rails, WEST_WING.x1 - 0.35, WEST_WING.x1 - 0.2, WEST_WING.z0 + 0.5, BRIDGE.z0 + 0.2)
	balustrade(rails, BRIDGE.x0, BRIDGE.x1, BRIDGE.z0 + 0.2, BRIDGE.z0 + 0.35)
	balustrade(rails, EAST_WING.x0 + 0.2, EAST_WING.x0 + 0.35, EAST_WING.z0 + 0.5, BRIDGE.z0 + 0.2)
	balustrade(rails, EAST_WING.x0 + 0.5, STAIR.x0 - 0.3, EAST_WING.z0 + 0.2, EAST_WING.z0 + 0.35)

	-- The stair: floating timber treads up the east wall on one steel stringer, a glass rail on
	-- the open side. Sixteen rises of 0.8 from the floor to the mezzanine.
	local stair = folder(mezz, "Stair")
	local rise = (UPPER - FLOOR) / STAIR.steps
	for i = 0, STAIR.steps - 1 do
		local za = STAIR.z0 + i * STAIR.run
		local top = FLOOR + rise * (i + 1)
		box(stair, "Tread", STAIR.x0, STAIR.x1, top - 0.35, top, za, za + STAIR.run, C.Wood, Enum.Material.Wood)
	end
	local zTop = STAIR.z0 + STAIR.steps * STAIR.run
	local mid = (STAIR.x0 + STAIR.x1) / 2
	slope(stair, "Stringer", Vector3.new(mid, FLOOR, STAIR.z0), Vector3.new(mid, UPPER - 0.4, zTop), 1.4, 0.7, C.Charcoal, Enum.Material.Metal)
	local railLow, railHigh = Vector3.new(STAIR.x0 - 0.2, FLOOR + 1.8, STAIR.z0 + 0.8), Vector3.new(STAIR.x0 - 0.2, UPPER + 1.8, zTop)
	slope(stair, "RailGlass", railLow, railHigh, 0.15, 3.2, C.Glass, Enum.Material.Glass, { transparency = 0.55, reflectance = 0.15, query = false, shadow = false })
	slope(stair, "Handrail", railLow + Vector3.new(0, 1.75, 0), railHigh + Vector3.new(0, 1.75, 0), 0.3, 0.3, C.Panel, Enum.Material.Metal)

	-- West wing: the owners' lounge. Two sofas to the rail, a bar, planters, pendants, its name.
	local lounge = folder(mezz, "OwnersLounge")
	box(lounge, "Rug", 157, 185, UPPER, UPPER + 0.05, 80.5, 94, C.Rug, Enum.Material.Fabric, { collide = false })
	sofa(lounge, 158, 170, 88, UPPER, C.Leather)
	sofa(lounge, 173, 185, 88, UPPER, C.Leather)
	for _, x in { 160, 175 } do
		box(lounge, "LowTable", x, x + 8, UPPER + 1.2, UPPER + 1.5, 82.5, 85.5, C.Wood, Enum.Material.Wood)
		box(lounge, "LowTableBase", x + 1, x + 7, UPPER, UPPER + 1.2, 83.2, 84.8, C.Charcoal, Enum.Material.Metal)
	end
	box(lounge, "Bar", 151.5, 155, UPPER, UPPER + 3.4, 81, 95, C.Navy, Enum.Material.SmoothPlastic)
	box(lounge, "BarTop", 151.5, 155.4, UPPER + 3.4, UPPER + 3.7, 80.6, 95.4, C.White, Enum.Material.Marble)
	box(lounge, "BarGlow", 155, 155.05, UPPER + 0.3, UPPER + 0.5, 81.2, 94.8, C.Gold, Enum.Material.Neon, { collide = false, shadow = false })
	for _, z in { 84, 88, 92 } do
		post(lounge, "StoolLeg", 156.6, z, UPPER, UPPER + 2.6, 0.5, C.Charcoal, Enum.Material.Metal)
		disc(lounge, "StoolSeat", 156.6, z, UPPER + 2.6, UPPER + 3, 2.2, C.Leather, Enum.Material.Fabric)
	end
	plant(lounge, 153.5, 80, UPPER, 2)
	plant(lounge, 171.5, 95.5, UPPER, 2)
	local lname = box(lounge, "Name", 158, 184, UPPER + 8, UPPER + 10.5, SHOW.z1 - 1.4, SHOW.z1 - 1, C.Navy, Enum.Material.SmoothPlastic)
	sign(lname, Enum.NormalId.Front, "OWNERS' LOUNGE", C.Gold, true)
	for _, x in { 164, 171.5, 179 } do
		box(lounge, "PendantCord", x - 0.04, x + 0.04, UPPER + 9, CEIL - 0.15, 84 - 0.04, 84 + 0.04, C.Charcoal, Enum.Material.Metal, {
			collide = false,
			shadow = false,
			query = false,
		})
		local lamp = ball(lounge, "Pendant", Vector3.new(x, UPPER + 8.6, 84), 1.4, C.Warm, Enum.Material.Neon)
		if x == 171.5 then
			light(lamp, "Point", 1.1, 20)
		end
	end

	-- East wing: the heritage gallery. Three framed panels lit from above, a plinth for a car of
	-- the marque's past (empty until cars come), benches to sit and look.
	local gallery = folder(mezz, "Gallery")
	for index, panelText in { "EST. 1968", "MOTORSPORT", "HANDCRAFTED" } do
		local x0 = 227 + (index - 1) * 10
		local x1 = x0 + 8
		local face = box(gallery, "Panel", x0, x1, UPPER + 3, UPPER + 9, SHOW.z1 - 1.3, SHOW.z1 - 1, C.Navy, Enum.Material.SmoothPlastic)
		sign(face, Enum.NormalId.Front, panelText, C.Gold, true)
		box(gallery, "Frame", x0 - 0.3, x1 + 0.3, UPPER + 9, UPPER + 9.3, SHOW.z1 - 1.45, SHOW.z1 - 1, C.Gold, Enum.Material.Metal)
		box(gallery, "Frame", x0 - 0.3, x1 + 0.3, UPPER + 2.7, UPPER + 3, SHOW.z1 - 1.45, SHOW.z1 - 1, C.Gold, Enum.Material.Metal)
		box(gallery, "Frame", x0 - 0.3, x0, UPPER + 3, UPPER + 9, SHOW.z1 - 1.45, SHOW.z1 - 1, C.Gold, Enum.Material.Metal)
		box(gallery, "Frame", x1, x1 + 0.3, UPPER + 3, UPPER + 9, SHOW.z1 - 1.45, SHOW.z1 - 1, C.Gold, Enum.Material.Metal)
		local lamp = box(gallery, "PictureLight", (x0 + x1) / 2 - 1.5, (x0 + x1) / 2 + 1.5, UPPER + 10, UPPER + 10.4, SHOW.z1 - 2.2, SHOW.z1 - 1, C.Charcoal, Enum.Material.Metal)
		light(lamp, "Spot", 1.4, 12, C.Warm, 80)
		box(gallery, "PictureLens", (x0 + x1) / 2 - 1.4, (x0 + x1) / 2 + 1.4, UPPER + 9.95, UPPER + 10, SHOW.z1 - 2.1, SHOW.z1 - 1.1, C.Warm, Enum.Material.Neon, { collide = false, shadow = false, query = false })
	end
	local gname = box(gallery, "Name", 230, 254, UPPER + 11, UPPER + 13, SHOW.z1 - 1.4, SHOW.z1 - 1, C.Navy, Enum.Material.SmoothPlastic)
	sign(gname, Enum.NormalId.Front, "HERITAGE GALLERY", C.Gold, true)
	box(gallery, "Plinth", 234, 252, UPPER, UPPER + 0.8, 81, 89, C.Charcoal, Enum.Material.SmoothPlastic, { reflectance = 0.25 })
	for _, z in { 81, 89 } do
		box(gallery, "PlinthEdge", 234, 252, UPPER + 0.2, UPPER + 0.6, z - 0.1, z + 0.1, C.Gold, Enum.Material.Neon, { collide = false, shadow = false })
	end
	for _, x in { 229, 257 } do
		local bench = standIn(folder(gallery, "Bench"), "bench", 90)
		box(bench, "BenchSeat", x - 0.8, x + 0.8, UPPER + 1.5, UPPER + 1.9, 82, 88, C.Wood, Enum.Material.Wood)
		box(bench, "BenchLeg", x - 0.7, x + 0.7, UPPER, UPPER + 1.5, 82.2, 82.7, C.Charcoal, Enum.Material.Metal)
		box(bench, "BenchLeg", x - 0.7, x + 0.7, UPPER, UPPER + 1.5, 87.3, 87.8, C.Charcoal, Enum.Material.Metal)
	end
	plant(gallery, 226.5, 95.5, UPPER, 2)
	local glow = box(gallery, "Glow", 242, 244, CEIL - 0.4, CEIL - 0.15, 86, 88, C.White, Enum.Material.Neon, { collide = false, shadow = false, query = false })
	light(glow, "Point", 1, 22, C.White)
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
		local bench = standIn(folder(plaza, "Bench"), "bench", 0)
		box(bench, "BenchSeat", x - 3, x + 3, PLAZA + 1.5, PLAZA + 1.9, 14, 15.6, C.Wood, Enum.Material.Wood)
		box(bench, "BenchLeg", x - 2.8, x - 2.3, PLAZA, PLAZA + 1.5, 14.1, 15.5, C.Charcoal, Enum.Material.Metal)
		box(bench, "BenchLeg", x + 2.3, x + 2.8, PLAZA, PLAZA + 1.5, 14.1, 15.5, C.Charcoal, Enum.Material.Metal)
	end

	-- A reflecting pool either side of the entrance: dark stone, still water, a row of low jets and
	-- a light under them. The water is what makes a forecourt read as a place and not a car park.
	for _, span in { { 176, 191 }, { 223, 238 } } do
		local x0, x1, z0, z1 = span[1], span[2], 9.5, 13
		box(plaza, "PoolFloor", x0 + 0.5, x1 - 0.5, PLAZA, PLAZA + 0.3, z0 + 0.5, z1 - 0.5, C.Charcoal, Enum.Material.Slate)
		box(plaza, "PoolRim", x0, x1, PLAZA, PLAZA + 1, z0, z0 + 0.5, C.Kerb, Enum.Material.Concrete)
		box(plaza, "PoolRim", x0, x1, PLAZA, PLAZA + 1, z1 - 0.5, z1, C.Kerb, Enum.Material.Concrete)
		box(plaza, "PoolRim", x0, x0 + 0.5, PLAZA, PLAZA + 1, z0 + 0.5, z1 - 0.5, C.Kerb, Enum.Material.Concrete)
		box(plaza, "PoolRim", x1 - 0.5, x1, PLAZA, PLAZA + 1, z0 + 0.5, z1 - 0.5, C.Kerb, Enum.Material.Concrete)
		box(plaza, "Water", x0 + 0.5, x1 - 0.5, PLAZA + 0.3, PLAZA + 0.75, z0 + 0.5, z1 - 0.5, Color3.fromRGB(40, 86, 118), Enum.Material.Glass, {
			transparency = 0.15,
			reflectance = 0.45,
			collide = false,
			query = false,
			shadow = false,
		})
		local count = 5
		for i = 1, count do
			local x = x0 + (x1 - x0) * i / (count + 1)
			post(plaza, "Jet", x, (z0 + z1) / 2, PLAZA + 0.75, PLAZA + 2.2, 0.25, C.White, Enum.Material.SmoothPlastic)
			ball(plaza, "Spray", Vector3.new(x, PLAZA + 2.3, (z0 + z1) / 2), 0.6, C.White, Enum.Material.SmoothPlastic)
		end
		local lamp = box(plaza, "PoolLight", (x0 + x1) / 2 - 1, (x0 + x1) / 2 + 1, PLAZA + 0.3, PLAZA + 0.4, (z0 + z1) / 2 - 0.4, (z0 + z1) / 2 + 0.4, C.Warm, Enum.Material.Neon, { collide = false, shadow = false, query = false })
		local up = light(lamp, "Spot", 1.2, 10, C.Warm, 90) :: SpotLight
		up.Face = Enum.NormalId.Top
	end

	-- Flags on three poles by the corner, where the road can see them.
	for i, x in { 152, 157, 162 } do
		post(plaza, "Flagpole", x, 9, PLAZA, 32, 0.4, C.White, Enum.Material.Metal)
		ball(plaza, "Finial", Vector3.new(x, 32.2, 9), 0.7, C.Gold, Enum.Material.Metal)
		local flag = box(plaza, "Flag", x + 0.2, x + 4.6, 27.8, 31.4, 8.95, 9.05, ({ C.Navy, C.Gold, C.Navy })[i], Enum.Material.Fabric, {
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
	-- Built the way dealership pylons are: the brand's mark big at the top, the name under it,
	-- then what the site does. It was a 5.6-stud column with the name across it, and a column that
	-- narrow fits MERIDIAN at two thirds of a stud -- the size of the spec cards indoors.
	local pylon = folder(model, "Pylon")
	box(pylon, "Base", 139.9, 149.1, WALK, 2.6, 8.2, 10.8, C.Kerb, Enum.Material.Concrete)
	box(pylon, "Body", 140.2, 148.8, 2.6, 36, 8.6, 10.4, C.Navy, Enum.Material.SmoothPlastic)
	local function panel(name: string, y0: number, y1: number, text: string, colour: Color3, font: Enum.Font)
		local face = box(pylon, name, 140.4, 148.6, y0, y1, 8.55, 10.45, C.Navy, Enum.Material.SmoothPlastic, { collide = false })
		sign(face, Enum.NormalId.Front, text, colour, true, font)
		sign(face, Enum.NormalId.Back, text, colour, true, font)
	end
	panel("Mark", 27.4, 35.4, "M", C.Gold, Enum.Font.GothamBlack)
	panel("Name", 24.8, 26.8, "MERIDIAN", C.Gold, Enum.Font.GothamBlack)
	panel("Motors", 22.8, 24.6, "MOTORS", C.Gold, Enum.Font.GothamBlack)
	box(pylon, "Rule", 140.4, 148.6, 22.1, 22.3, 8.5, 10.5, C.Gold, Enum.Material.Neon, { collide = false, shadow = false })
	panel("Sales", 19.6, 21.2, "SALES", C.White, Enum.Font.GothamBold)
	panel("Service", 17.6, 19.2, "SERVICE", C.White, Enum.Font.GothamBold)
	panel("Wash", 15.6, 17.2, "CAR WASH", C.White, Enum.Font.GothamBold)
	-- A lit line down the plain lower column, so it reads as part of the sign and not a post.
	box(pylon, "Stripe", 144.2, 144.6, 4.6, 15, 8.5, 10.5, C.Gold, Enum.Material.Neon, { collide = false, shadow = false })
	box(pylon, "Cap", 140, 149, 36, 36.6, 8.4, 10.6, C.Gold, Enum.Material.Neon, { shadow = false })
end

-- ---------------------------------------------------------------------------------------------
-- Every car spot, and the markers the services read.
-- ---------------------------------------------------------------------------------------------
-- ---------------------------------------------------------------------------------------------
-- The detail pass.
--
-- The shell, the lot and the furniture put the dealership there; this is what makes it read as
-- built rather than blocked out. Roblox's own environment-art order is floors, architecture,
-- props, overhead, effects, lighting -- and everything below is the last three passes over the
-- first two: a base course and corner columns so a glass box has a frame, doors you can see are
-- doors, plant on the roof, bollards and bins at the kerb, rope stanchions and spec boards
-- around the display spots, a ceiling with beams in it.
--
-- Detail density follows use: heaviest where a customer stands (the entrance, the turntables,
-- the counter), lighter across the lot, sparse at the edges. Even density everywhere is what
-- makes a build read as wallpaper.
-- ---------------------------------------------------------------------------------------------

-- A short post with a coloured band near its top: bollard, stanchion, sign post.
local function bollard(parent: Instance, x: number, z: number, y0: number, height: number, diameter: number, body: Color3, band: Color3): Part
	post(parent, "Bollard", x, z, y0, y0 + height, diameter, body, Enum.Material.Metal)
	return disc(parent, "Band", x, z, y0 + height * 0.78, y0 + height * 0.86, diameter * 1.15, band, Enum.Material.Neon, {
		collide = false,
		shadow = false,
	})
end

-- A rope slung between two stanchion tops, in two segments so it sags in the middle.
local function rope(parent: Instance, from: Vector3, to: Vector3, colour: Color3)
	local sag = 0.5
	local mid = (from + to) / 2 - Vector3.new(0, sag, 0)
	for _, pair in { { from, mid }, { mid, to } } do
		local a, b = pair[1], pair[2]
		local part = Instance.new("Part")
		part.Name = "Rope"
		part.Size = Vector3.new(0.14, 0.14, (b - a).Magnitude)
		part.CFrame = origin * CFrame.lookAt((a + b) / 2, b)
		style(part, colour, Enum.Material.Fabric, { collide = false, shadow = false, query = false })
		part.Parent = parent
	end
end

-- Six posts and six ropes around a display spot: the barrier every showroom puts round the car
-- it does not want fingerprints on, and the thing that tells a player where to stand.
local function stanchions(parent: Instance, x: number, z: number, radius: number, y: number)
	local model = folder(parent, "Stanchions")
	local points: { Vector3 } = {}
	for i = 0, 5 do
		local angle = math.rad(i * 60 + 30)
		local px, pz = x + math.cos(angle) * radius, z + math.sin(angle) * radius
		bollard(model, px, pz, y, 2.4, 0.3, C.Gold, C.Navy)
		table.insert(points, Vector3.new(px, y + 2.2, pz))
	end
	for i = 1, #points do
		rope(model, points[i], points[i % #points + 1], C.Navy)
	end
end

-- The angled card beside a display spot that a dealership prints the specification on.
local function specBoard(parent: Instance, x: number, z: number, y: number, facingDegrees: number, text: string)
	local model = folder(parent, "SpecBoard")
	local stem = post(model, "Stem", x, z, y, y + 2.6, 0.22, C.Charcoal, Enum.Material.Metal)
	local plate = box(model, "Plate", -1.7, 1.7, 2.4, 3.6, -0.12, 0.12, C.Navy, Enum.Material.SmoothPlastic)
	sign(plate, Enum.NormalId.Front, text, C.Gold, true, Enum.Font.GothamBold)
	-- Tipped back, the way a lectern card is, so it reads from standing height.
	local frame = at(x, y, z) * CFrame.Angles(0, math.rad(facingDegrees), 0) * CFrame.Angles(math.rad(20), 0, 0)
	plate.CFrame = frame * origin:ToObjectSpace(plate.CFrame)
	stem.CFrame = at(x, y + 1.3, z) * CFrame.Angles(0, 0, math.rad(90))
end

local function buildDetail(model: Model)
	-- --- The building's frame: a base course, corner columns and a spandrel band -------------
	local frame = folder(model, "Frame")
	-- Glass that runs into the floor looks like a greenhouse. A stone course under it is what
	-- makes the same wall read as a building.
	for _, span in { { SHOW.x0, 198.8 }, { 215.2, SHOW.x1 } } do
		box(frame, "BaseCourse", span[1], span[2], FLOOR, FLOOR + 1.1, SHOW.z0 - 0.35, SHOW.z0 + 1.1, C.Charcoal, Enum.Material.Slate)
	end
	for _, span in { { SHOW.z0, 59.8 }, { 69.7, SHOW.z1 } } do
		box(frame, "BaseCourse", SHOW.x0 - 0.35, SHOW.x0 + 1.1, FLOOR, FLOOR + 1.1, span[1], span[2], C.Charcoal, Enum.Material.Slate)
	end
	-- A shadow line across the glazing at head height: one band, and the wall stops reading as
	-- a single sheet of nothing.
	for _, span in { { SHOW.x0, 198.8 }, { 215.2, SHOW.x1 } } do
		box(frame, "Spandrel", span[1], span[2], MEZZ, UPPER, SHOW.z0 - 0.2, SHOW.z0 + 1.05, C.Charcoal, Enum.Material.Metal, { shadow = false })
	end
	box(frame, "Spandrel", SHOW.x0 - 0.2, SHOW.x0 + 1.05, MEZZ, UPPER, SHOW.z0, SHOW.z1, C.Charcoal, Enum.Material.Metal, { shadow = false })
	for _, corner in { { SHOW.x0, SHOW.z0 }, { SHOW.x1, SHOW.z0 }, { SHOW.x0, SHOW.z1 }, { SHOW.x1, SHOW.z1 } } do
		-- Stops inside the fascia, which wraps over its head: flush with the fascia's top, the two
		-- would fight for the same face under the coping.
		box(frame, "Column", corner[1] - 1.2, corner[1] + 1.2, 0, PARAPET - 0.2, corner[2] - 1.2, corner[2] + 1.2, C.Charcoal, Enum.Material.Slate)
	end
	-- Coping along the top of the parapet: the light line that finishes a flat roof.
	box(frame, "Coping", SHOW.x0 - 1.8, SHOW.x1 + 1.8, PARAPET, PARAPET + 0.4, SHOW.z0 - 1.8, SHOW.z0 - 0.6, C.Kerb, Enum.Material.Concrete)
	box(frame, "Coping", SHOW.x0 - 1.8, SHOW.x1 + 1.8, PARAPET, PARAPET + 0.4, SHOW.z1 + 0.6, SHOW.z1 + 1.8, C.Kerb, Enum.Material.Concrete)
	box(frame, "Coping", SHOW.x0 - 1.8, SHOW.x0 - 0.6, PARAPET, PARAPET + 0.4, SHOW.z0 - 0.6, SHOW.z1 + 0.6, C.Kerb, Enum.Material.Concrete)
	box(frame, "Coping", SHOW.x1 + 0.6, SHOW.x1 + 1.8, PARAPET, PARAPET + 0.4, SHOW.z0 - 0.6, SHOW.z1 + 0.6, C.Kerb, Enum.Material.Concrete)

	-- --- The doors, which were a hole in the glass ------------------------------------------
	local doors = folder(model, "Entrance")
	for _, x in { 198.8, 215.2 } do
		box(doors, "DoorPost", x - 0.35, x + 0.35, FLOOR, FLOOR + 10.5, SHOW.z0 - 0.05, SHOW.z0 + 1.2, C.Charcoal, Enum.Material.Metal)
	end
	-- Both leaves stand open, parked inside the glass line: a dealership's door is never shut
	-- during the day, and an open one invites a player in without a prompt to explain it.
	for _, leaf in { { 191.6, 198.6 }, { 215.4, 222.4 } } do
		box(doors, "DoorLeaf", leaf[1], leaf[2], FLOOR + 0.2, FLOOR + 9.9, SHOW.z0 + 1.15, SHOW.z0 + 1.35, C.Glass, Enum.Material.Glass, {
			transparency = 0.45,
			reflectance = 0.15,
			query = false,
		})
		box(doors, "DoorRail", leaf[1] - 0.05, leaf[2] + 0.05, FLOOR + 0.1, FLOOR + 0.45, SHOW.z0 + 1.1, SHOW.z0 + 1.4, C.Charcoal, Enum.Material.Metal)
		box(doors, "DoorRail", leaf[1] - 0.05, leaf[2] + 0.05, FLOOR + 9.7, FLOOR + 10, SHOW.z0 + 1.1, SHOW.z0 + 1.4, C.Charcoal, Enum.Material.Metal)
		local handleX = if leaf[1] < 200 then leaf[2] - 0.8 else leaf[1] + 0.8
		post(doors, "Handle", handleX, SHOW.z0 + 1.6, FLOOR + 3.4, FLOOR + 6.4, 0.22, C.Gold, Enum.Material.Metal)
	end
	box(doors, "Mat", 199, 215, FLOOR, FLOOR + 0.04, SHOW.z0 + 1.4, SHOW.z0 + 7, C.Charcoal, Enum.Material.Fabric, { collide = false, query = false })
	box(doors, "Threshold", 198.8, 215.2, FLOOR - 0.05, FLOOR + 0.06, SHOW.z0 - 0.4, SHOW.z0 + 1.2, C.Kerb, Enum.Material.Concrete, { query = false })
	-- Under the canopy: a slatted soffit and two downlights, so the way in is the brightest
	-- thing on the frontage after dark.
	for i = 0, 6 do
		local x = 197 + i * 3
		box(doors, "Soffit", x, x + 2.2, FLOOR + 10.85, FLOOR + 11, 11.4, SHOW.z0 - 1.6, C.Charcoal, Enum.Material.Metal, { collide = false, shadow = false })
	end
	for _, x in { 202, 212 } do
		local lamp = box(doors, "Downlight", x - 0.9, x + 0.9, FLOOR + 10.8, FLOOR + 10.9, 15, 17, C.Warm, Enum.Material.Neon, { collide = false, shadow = false })
		light(lamp, "Spot", 2.4, 20, C.Warm, 90)
	end
	local canopyPlate = box(doors, "CanopyPlate", 196, 218, FLOOR + 11.8, FLOOR + 13.2, 11, 11.4, C.Navy, Enum.Material.SmoothPlastic)
	sign(canopyPlate, Enum.NormalId.Front, "SHOWROOM", C.Gold, true, Enum.Font.GothamBold)

	-- --- Roof plant: the thing every real building has and no Roblox one does ----------------
	local roof = folder(model, "RoofPlant")
	for _, unit in { { 168, 86 }, { 196, 86 }, { 224, 86 } } do
		local x, z = unit[1], unit[2]
		box(roof, "Plinth", x - 4.5, x + 4.5, ROOF, ROOF + 0.4, z - 3.5, z + 3.5, C.Charcoal, Enum.Material.Concrete)
		box(roof, "Unit", x - 4, x + 4, ROOF + 0.4, ROOF + 3.4, z - 3, z + 3, C.Kerb, Enum.Material.Metal)
		disc(roof, "Fan", x - 2, z, ROOF + 3.4, ROOF + 3.6, 3.2, C.Charcoal, Enum.Material.DiamondPlate)
		disc(roof, "Fan", x + 2, z, ROOF + 3.4, ROOF + 3.6, 3.2, C.Charcoal, Enum.Material.DiamondPlate)
		for i = 0, 2 do
			box(roof, "Grille", x - 4.05, x - 3.95, ROOF + 0.8 + i * 0.8, ROOF + 1.3 + i * 0.8, z - 2.6, z + 2.6, C.Charcoal, Enum.Material.Metal, {
				collide = false,
				shadow = false,
			})
		end
	end
	-- A ladder up the back wall, because a roof with plant on it is a roof somebody services.
	for _, x in { 256.4, 258.6 } do
		box(roof, "LadderRail", x - 0.12, x + 0.12, FLOOR + 3, ROOF + 2.5, SHOW.z1 + 0.05, SHOW.z1 + 0.35, C.Charcoal, Enum.Material.Metal, { collide = false })
	end
	for i = 0, math.floor((ROOF - FLOOR - 3.6) / 2) do
		box(roof, "Rung", 256.4, 258.6, FLOOR + 3.6 + i * 2, FLOOR + 3.8 + i * 2, SHOW.z1 + 0.1, SHOW.z1 + 0.3, C.Charcoal, Enum.Material.Metal, {
			collide = false,
			shadow = false,
		})
	end

	-- --- The kerb line: bollards, a bin, a bike rack ----------------------------------------
	local street = folder(model, "Street")
	for i = 0, 8 do
		local band = bollard(street, 154 + i * 13, 7.2, PLAZA, 3.4, 0.8, C.Charcoal, C.Gold)
		if i % 4 == 0 then
			light(band, "Point", 1, 13)
		end
	end
	-- Either side of the doors, where a kerb is what stops a car on the plaza.
	bollard(street, 194, 13, PLAZA, 3.4, 0.8, C.Charcoal, C.Gold)
	bollard(street, 220, 13, PLAZA, 3.4, 0.8, C.Charcoal, C.Gold)
	for _, x in { 232, 236 } do
		box(street, "BikeHoop", x - 0.15, x + 0.15, PLAZA, PLAZA + 3.2, 14.4, 14.7, C.Kerb, Enum.Material.Metal, { collide = false })
		box(street, "BikeHoop", x - 0.15, x + 0.15, PLAZA, PLAZA + 3.2, 16.9, 17.2, C.Kerb, Enum.Material.Metal, { collide = false })
		box(street, "BikeHoop", x - 0.15, x + 0.15, PLAZA + 3, PLAZA + 3.2, 14.4, 17.2, C.Kerb, Enum.Material.Metal, { collide = false })
	end
	local plazaBin = standIn(folder(street, "Bin"), "trash", 0)
	post(plazaBin, "Bin", 227, 15.5, PLAZA, PLAZA + 3.6, 2.2, C.Charcoal, Enum.Material.Metal)
	disc(plazaBin, "BinLid", 227, 15.5, PLAZA + 3.6, PLAZA + 3.9, 2.5, C.Kerb, Enum.Material.Metal)
	for _, x in { 152, 157, 162 } do
		disc(street, "PolePad", x, 9, PLAZA, PLAZA + 0.25, 2.4, C.Kerb, Enum.Material.Concrete)
	end
	-- The pylon gets a planted base and a lit OPEN panel: the two things that say the place is
	-- trading, read from a car on the road.
	box(street, "PylonPlanter", 139.6, 149.6, WALK, WALK + 1.4, 7, 12, C.Planter, Enum.Material.SmoothPlastic)
	box(street, "PylonHedge", 140, 149.2, WALK + 1.4, WALK + 2.6, 7.4, 11.6, C.Leaf, Enum.Material.LeafyGrass)
	local openPanel = box(street, "OpenPanel", 141.4, 146.6, 2.6, 3.9, 8.5, 10.5, C.Gold, Enum.Material.Neon)
	sign(openPanel, Enum.NormalId.Front, "OPEN", C.Navy, false, Enum.Font.GothamBlack)
	sign(openPanel, Enum.NormalId.Back, "OPEN", C.Navy, false, Enum.Font.GothamBlack)

	-- --- The lot: wheel stops, lane arrows, a sign at the test-drive bays --------------------
	local lot = folder(model, "LotDetail")
	for _, row in { ROW_A, ROW_B } do
		for i = 0, BAY_COUNT - 1 do
			local x = BAY_FIRST_X + BAY_WIDTH * i + BAY_WIDTH / 2
			box(lot, "WheelStop", x - 3, x + 3, LOT, LOT + 0.55, row.z0 + 1.6, row.z0 + 2.4, C.Kerb, Enum.Material.Concrete, { shadow = false })
		end
	end
	-- Chevrons up the pickup lane: which way the traffic runs, said in paint rather than a sign.
	for i = 0, 3 do
		local z = 44 + i * 14
		for _, side in { -1, 1 } do
			local part = paint(lot, "Chevron", 121 + side * 0.1, 121 + side * 4.4, z, z + 0.7, C.Line)
			part.CFrame = at(121 + side * 2.2, LOT + 0.03, z + 2) * CFrame.Angles(0, math.rad(side * 35), 0)
		end
	end
	groundText(lot, "EnterText", "ENTER", 106, 121, 2, 6, C.Line)
	groundText(lot, "ExitText", "EXIT", 123, 138, 2, 6, C.Line)
	local testPost = folder(lot, "TestDriveSign")
	post(testPost, "Post", 104.5, 26, LOT, 9, 0.5, C.Charcoal, Enum.Material.Metal)
	local testPlate = box(testPost, "Plate", 100, 109, 6.4, 9, 25.85, 26.15, C.Navy, Enum.Material.SmoothPlastic)
	sign(testPlate, Enum.NormalId.Front, "TEST DRIVES", C.Gold, true, Enum.Font.GothamBold)
	sign(testPlate, Enum.NormalId.Back, "TEST DRIVES", C.Gold, true, Enum.Font.GothamBold)
	for _, p in { { 7, 46 }, { 101, 46 }, { 7, 102 }, { 101, 102 } } do
		disc(lot, "PolePad", p[1], p[2], LOT, LOT + 0.3, 2.6, C.Kerb, Enum.Material.Concrete)
	end

	-- --- Inside: ceiling beams, barriers, spec boards, a back wall to the counter ------------
	local inside = folder(model, "InteriorDetail")
	-- A dark ceiling, the way galleries and the better showrooms do it: the eye goes to what is lit,
	-- and the linear lights read as lines of light rather than as fittings on a white board.
	box(inside, "CeilingLiner", SHOW.x0 + 1, SHOW.x1 - 1, CEIL - 0.15, CEIL, SHOW.z0 + 1, SHOW.z1 - 1, C.Ceiling, Enum.Material.SmoothPlastic, {
		collide = false,
		query = false,
	})
	-- Large-format panels on the east wall, one joint every eight studs.
	for z = SHOW.z0 + 8, SHOW.z1 - 3, 8 do
		box(inside, "WallJoint", SHOW.x1 - 1.08, SHOW.x1 - 0.96, FLOOR, CEIL - 0.15, z - 0.07, z + 0.07, C.Joint, Enum.Material.SmoothPlastic, {
			collide = false,
			shadow = false,
			query = false,
		})
	end
	-- Joints across the runway, so it reads as laid stone.
	box(inside, "RunwayJoint", 206.92, 207.08, FLOOR, FLOOR + 0.04, 29.2, 51, C.Joint, Enum.Material.Slate, { collide = false, query = false, shadow = false })
	for z = 32, 48, 4 do
		box(inside, "RunwayJoint", 201.1, 212.9, FLOOR, FLOOR + 0.04, z - 0.07, z + 0.07, C.Joint, Enum.Material.Slate, { collide = false, query = false, shadow = false })
	end
	-- Beams across the ceiling.
	for _, z in { 30, 46, 62, 78, 94 } do
		box(inside, "Beam", SHOW.x0 + 1, SHOW.x1 - 1, CEIL - 0.9, CEIL, z - 0.5, z + 0.5, C.Charcoal, Enum.Material.Metal, { collide = false })
	end
	for _, z in { 38, 54, 70, 86 } do
		local strip = box(inside, "LightStrip", SHOW.x0 + 4, SHOW.x1 - 4, CEIL - 0.25, CEIL - 0.1, z - 0.35, z + 0.35, C.White, Enum.Material.Neon, {
			collide = false,
			shadow = false,
		})
		if z == 38 or z == 70 then
			light(strip, "Point", 0.9, 44, C.White)
		end
	end

	-- Configurator kiosks either side of the runway, facing the doors: a screen on a stand, tipped
	-- back to be read standing.
	for _, x in { 198.5, 215.5 } do
		local kiosk = folder(inside, "Kiosk")
		box(kiosk, "Foot", x - 1.1, x + 1.1, FLOOR, FLOOR + 0.2, 30.2, 31.8, C.Charcoal, Enum.Material.Metal)
		box(kiosk, "Stem", x - 0.35, x + 0.35, FLOOR + 0.2, FLOOR + 3.6, 30.7, 31.3, C.Charcoal, Enum.Material.Metal)
		local screen = Instance.new("Part")
		screen.Name = "Screen"
		screen.Size = Vector3.new(2.8, 1.9, 0.2)
		screen.CFrame = at(x, FLOOR + 4.3, 31) * CFrame.Angles(math.rad(30), 0, 0)
		style(screen, C.Screen, Enum.Material.SmoothPlastic, { collide = false })
		screen.Parent = kiosk
		sign(screen, Enum.NormalId.Front, "BUILD\nYOURS", C.Gold, true, Enum.Font.GothamBold)
	end

	stanchions(inside, 178, 44, 14, FLOOR)
	stanchions(inside, 228, 44, 14, FLOOR)
	specBoard(inside, 163, 40, FLOOR, 0, "SPECIFICATION")
	specBoard(inside, 243, 40, FLOOR, 0, "SPECIFICATION")
	specBoard(inside, 221, 66, FLOOR + 1, 270, "THE FLAGSHIP")
	-- A stone disc ringed in gold under the hero podium, so the middle of the room has a centre.
	-- Light, not dark: runway, podium and backdrop are dark already, and a dark disc as well
	-- turned the whole back of the hall into one black mass.
	disc(inside, "HeroRing", 207, 73, FLOOR, FLOOR + 0.05, 44, C.Gold, Enum.Material.Metal, { collide = false, query = false, shadow = false })
	disc(inside, "HeroInlay", 207, 73, FLOOR, FLOOR + 0.07, 43, C.Paving, Enum.Material.Marble, { collide = false, query = false, reflectance = 0.1 })

	-- Timber slats on the back wall behind the hero: the one warm surface in a hall of white
	-- stone and dark metal, where every photo of the flagship car is taken.
	local slats = folder(inside, "FeatureWall")
	local slatCount = 26
	local sx0, sx1 = 186, 223
	local slatPitch = (sx1 - sx0) / slatCount
	for i = 0, slatCount - 1 do
		local x = sx0 + i * slatPitch
		box(slats, "Slat", x, x + slatPitch * 0.55, FLOOR, CEIL - 1, SHOW.z1 - 1.5, SHOW.z1 - 1, C.Wood, Enum.Material.Wood, { shadow = false })
	end
	box(slats, "Backing", sx0, sx1, FLOOR, CEIL - 1, SHOW.z1 - 1.05, SHOW.z1 - 1, C.Charcoal, Enum.Material.SmoothPlastic)
	box(slats, "Uplight", sx0, sx1, FLOOR, FLOOR + 0.15, SHOW.z1 - 2, SHOW.z1 - 1.5, C.Warm, Enum.Material.Neon, { collide = false, shadow = false })
	for index, x in { sx0 + 3, sx0 + 11, sx0 + 19, sx0 + 27, sx0 + 35 } do
		local washer = box(slats, "WallWasher", x - 0.5, x + 0.5, CEIL - 1.5, CEIL - 0.15, SHOW.z1 - 3.3, SHOW.z1 - 2.7, C.Charcoal, Enum.Material.Metal, { collide = false })
		if index % 2 == 1 then
			light(washer, "Spot", 1.6, 22, C.Warm, 80)
		end
		box(slats, "WasherLens", x - 0.4, x + 0.4, CEIL - 1.55, CEIL - 1.5, SHOW.z1 - 3.2, SHOW.z1 - 2.8, C.Warm, Enum.Material.Neon, { collide = false, shadow = false, query = false })
	end

	-- The counter gets a back wall: somewhere for the brand to sit, and a line between the
	-- desk and the lounge behind it.
	local back = folder(inside, "CounterBack")
	box(back, "Wall", 152, 176, FLOOR, FLOOR + 9, 77, 77.9, C.Navy, Enum.Material.SmoothPlastic)
	for i = 0, 11 do
		box(back, "Slat", 152.6 + i * 2, 153.6 + i * 2, FLOOR, FLOOR + 9, 76.85, 77.05, C.Gold, Enum.Material.Metal, {
			collide = false,
			shadow = false,
		})
	end
	local logo = box(back, "Logo", 159, 169, FLOOR + 3.4, FLOOR + 7.4, 76.6, 76.9, C.Navy, Enum.Material.SmoothPlastic)
	sign(logo, Enum.NormalId.Front, "M", C.Gold, true)
	-- Stools on the customer side of the counter.
	for _, x in { 158, 167 } do
		post(inside, "StoolLeg", x, 67.5, FLOOR, FLOOR + 2.6, 0.5, C.Charcoal, Enum.Material.Metal)
		disc(inside, "StoolSeat", x, 67.5, FLOOR + 2.6, FLOOR + 3, 2.4, C.Leather, Enum.Material.Fabric)
	end

	-- An accessory cabinet by the desks: alloys and paint, which is what a showroom sells that
	-- is not a car.
	local cabinet = folder(inside, "Cabinet")
	box(cabinet, "Base", 257, 262, FLOOR, FLOOR + 1.2, 26, 34, C.Charcoal, Enum.Material.SmoothPlastic)
	box(cabinet, "Glass", 257, 262, FLOOR + 1.2, FLOOR + 8, 26, 34, C.Glass, Enum.Material.Glass, {
		transparency = 0.6,
		reflectance = 0.2,
		query = false,
	})
	for i = 0, 1 do
		box(cabinet, "Shelf", 257.2, 261.8, FLOOR + 3.4 + i * 2.2, FLOOR + 3.6 + i * 2.2, 26.2, 33.8, C.White, Enum.Material.SmoothPlastic, { collide = false })
	end
	disc(cabinet, "Alloy", 259.5, 28.5, FLOOR + 3.6, FLOOR + 4.1, 2.6, C.Kerb, Enum.Material.Metal)
	disc(cabinet, "Alloy", 259.5, 31.5, FLOOR + 5.8, FLOOR + 6.3, 2.6, C.Charcoal, Enum.Material.Metal)
	for i = 0, 3 do
		box(cabinet, "Swatch", 257.6 + i * 1.1, 258.4 + i * 1.1, FLOOR + 1.3, FLOOR + 1.5, 29, 31, ({ C.Red, C.Blue, C.Gold, C.White })[i + 1], Enum.Material.SmoothPlastic, {
			collide = false,
		})
	end

	-- Lounge extras: a brochure rack and a water cooler, the two props that say "waiting room".
	local lounge = folder(inside, "LoungeDetail")
	box(lounge, "RackBack", 185.6, 186, FLOOR, FLOOR + 6, 84, 90, C.Charcoal, Enum.Material.Metal)
	for i = 0, 2 do
		box(lounge, "RackShelf", 184.4, 185.6, FLOOR + 1.6 + i * 1.8, FLOOR + 1.8 + i * 1.8, 84.2, 89.8, C.Charcoal, Enum.Material.Metal, { collide = false })
		box(lounge, "Brochure", 184.6, 185.6, FLOOR + 1.8 + i * 1.8, FLOOR + 2.4 + i * 1.8, 85, 89, C.Navy, Enum.Material.SmoothPlastic, { collide = false })
	end
	post(lounge, "CoolerStand", 156, 92, FLOOR, FLOOR + 3.2, 1.6, C.White, Enum.Material.SmoothPlastic)
	post(lounge, "CoolerBottle", 156, 92, FLOOR + 3.2, FLOOR + 5.4, 1.9, C.Glass, Enum.Material.Glass)
	plant(inside, 190, 30, FLOOR, 2.6)
	plant(inside, 190, 94.5, FLOOR, 2.6)
end

-- ---------------------------------------------------------------------------------------------
-- The rest of the site: a service centre, a customer car park, a dressed east side, trees.
--
-- A showroom and a lot are a car shop; a service department and somewhere for customers to
-- park is what makes the same plot read as a dealership. They also fill the grass behind and
-- beside the showroom, which was the one part of the plot with nothing on it.
-- ---------------------------------------------------------------------------------------------

-- A tree from primitives: a trunk and three overlapping crowns, the same way the city's own
-- trees are made.
local function tree(parent: Instance, x: number, z: number, y: number, height: number)
	-- One of the pack's three trees, picked from where it stands so neighbours differ.
	local model = standIn(folder(parent, "Tree"), "trees", 0, math.floor(x * 7 + z * 13) % 3 + 1)
	post(model, "Trunk", x, z, y, y + height * 0.55, height * 0.09, C.Bark, Enum.Material.Wood)
	ball(model, "Crown", Vector3.new(x, y + height * 0.7, z), height * 0.55, C.Leaf, Enum.Material.LeafyGrass)
	ball(model, "Crown", Vector3.new(x + height * 0.14, y + height * 0.86, z - height * 0.1), height * 0.42, C.LeafDark, Enum.Material.LeafyGrass)
	ball(model, "Crown", Vector3.new(x - height * 0.15, y + height * 0.8, z + height * 0.12), height * 0.38, C.Leaf, Enum.Material.LeafyGrass)
end

-- A stack of four tyres, where a workshop keeps them.
local function tyreStack(parent: Instance, x: number, z: number, y: number)
	local stack = standIn(folder(parent, "Tyres"), "tires")
	for i = 0, 3 do
		disc(stack, "Tyre", x, z, y + i * 0.9, y + i * 0.9 + 0.85, 2.8, C.Leather, Enum.Material.Rubber)
	end
end

-- A low bush.
local function bush(parent: Instance, x: number, z: number, y: number, size: number)
	local model = standIn(folder(parent, "Bush"), "bush")
	ball(model, "Leaves", Vector3.new(x, y + size * 0.4, z), size, C.LeafDark, Enum.Material.LeafyGrass)
end

-- A lamp post like the lot's: a pole, a head, a warm glow and a spot throwing down wide. `reach`
-- carries the head out along X on an arm, for a pole that has to stand off the surface it lights.
local function lampPost(parent: Instance, x: number, z: number, y0: number, reach: number?)
	local lamp = folder(parent, "LampPost")
	local hx = x + (reach or 0)
	disc(lamp, "Pad", x, z, y0, y0 + 0.3, 2.6, C.Kerb, Enum.Material.Concrete)
	post(lamp, "Pole", x, z, y0 + 0.3, 16.6, 0.7, C.Charcoal, Enum.Material.Metal)
	if reach then
		box(lamp, "Arm", math.min(x, hx), math.max(x, hx), 16.1, 16.5, z - 0.2, z + 0.2, C.Charcoal, Enum.Material.Metal)
	end
	local head = box(lamp, "Lamp", hx - 1.4, hx + 1.4, 15.4, 16.1, z - 0.7, z + 0.7, C.Charcoal, Enum.Material.Metal)
	box(lamp, "LampGlow", hx - 1.2, hx + 1.2, 15.3, 15.4, z - 0.5, z + 0.5, C.Warm, Enum.Material.Neon, { collide = false, shadow = false })
	light(head, "Spot", 2.2, 44, C.Warm, 110)
end

local SERVICE = { x0 = 150, x1 = 264, z0 = 112, z1 = 152, height = 18 }

local function buildService(model: Model)
	local service = folder(model, "ServiceCentre")
	local x0, x1, z0, z1, h = SERVICE.x0, SERVICE.x1, SERVICE.z0, SERVICE.z1, SERVICE.height

	-- The service lane between the showroom's back wall and the service doors, off the lot.
	box(service, "Lane", 140, SERVICE.x1, 0, LOT, 98, 112, C.Asphalt, Enum.Material.Asphalt)
	paint(service, "LaneEdge", 150, SERVICE.x1, 98.3, 98.6, C.Yellow)
	groundText(service, "LaneText", "SERVICE", 108, 138, 100, 110, C.Line)

	box(service, "Slab", x0, x1, 0, FLOOR, z0, z1, C.Kerb, Enum.Material.Concrete)
	box(service, "WallNorth", x0, x1, FLOOR, h, z1 - 1, z1, C.Panel, Enum.Material.SmoothPlastic)
	box(service, "WallWest", x0, x0 + 1, FLOOR, h, z0, z1 - 1, C.Panel, Enum.Material.SmoothPlastic)
	box(service, "WallEast", x1 - 1, x1, FLOOR, h, z0, z1 - 1, C.Panel, Enum.Material.SmoothPlastic)
	box(service, "Roof", x0 - 0.8, x1 + 0.8, h, h + 1, z0 - 0.8, z1 + 0.8, C.OffWhite, Enum.Material.SmoothPlastic)
	box(service, "Fascia", x0 - 1, x1 + 1, h - 1.6, h + 1.4, z0 - 1.2, z0 - 0.6, C.Navy, Enum.Material.SmoothPlastic)
	local serviceSign = box(service, "Sign", 176, 238, h - 1.4, h + 1.2, z0 - 1.5, z0 - 1.2, C.Navy, Enum.Material.SmoothPlastic)
	sign(serviceSign, Enum.NormalId.Front, "MERIDIAN SERVICE CENTRE", C.Gold, true)

	-- Four bays on the lane, every one fitted with a lift, a tool chest and a lamp. The last door is
	-- up; the other three are glazed sectional doors, the "window into the kitchen" the better
	-- dealerships build so a customer can watch their car being worked on.
	local bayWidth = 20
	local gap = ((x1 - x0) - bayWidth * 4) / 5
	for i = 0, 3 do
		local bx0 = x0 + gap + i * (bayWidth + gap)
		local bx1 = bx0 + bayWidth
		box(service, "Pier", if i == 0 then x0 - 0.2 else bx0 - gap, bx0, FLOOR, h - 1.6, z0 - 0.2, z0 + 1, C.Charcoal, Enum.Material.Slate)
		box(service, "Head", bx0, bx1, 12.5, h - 1.6, z0, z0 + 1, C.Panel, Enum.Material.SmoothPlastic)
		local open = i == 3
		box(service, "BayFloor", bx0, bx1, FLOOR, FLOOR + 0.02, z0 + 1, z1 - 1, C.DarkFloor, Enum.Material.Concrete, { collide = false })
		local cx, cz = (bx0 + bx1) / 2, (z0 + z1) / 2
		for _, side in { -1, 1 } do
			box(service, "LiftPost", cx + side * 6 - 0.6, cx + side * 6 + 0.6, FLOOR, 11, cz - 0.6, cz + 0.6, C.Red, Enum.Material.Metal)
			box(service, "LiftArm", cx + side * 6 - (if side < 0 then 0 else 3), cx + side * 6 + (if side < 0 then 3 else 0), FLOOR + 2.2, FLOOR + 2.6, cz - 4, cz - 3.4, C.Charcoal, Enum.Material.Metal)
			box(service, "LiftArm", cx + side * 6 - (if side < 0 then 0 else 3), cx + side * 6 + (if side < 0 then 3 else 0), FLOOR + 2.2, FLOOR + 2.6, cz + 3.4, cz + 4, C.Charcoal, Enum.Material.Metal)
		end
		box(service, "LiftBeam", cx - 6, cx + 6, 10.4, 10.9, cz - 0.4, cz + 0.4, C.Red, Enum.Material.Metal)
		local chest = standIn(folder(service, "ToolChest"), "toolcart", 90)
		box(chest, "Body", bx1 - 4, bx1 - 1.2, FLOOR, FLOOR + 4.4, z1 - 5, z1 - 2, if i % 2 == 0 then C.Red else C.Blue, Enum.Material.Metal)
		for d = 0, 3 do
			box(chest, "Drawer", bx1 - 4.05, bx1 - 3.95, FLOOR + 0.8 + d, FLOOR + 1.5 + d, z1 - 4.8, z1 - 2.2, C.Charcoal, Enum.Material.Metal, { collide = false })
		end
		if i ~= 1 then
			tyreStack(service, bx0 + 2.2, z1 - 3.5, FLOOR)
		end
		local bayLamp = box(service, "BayLamp", cx - 4, cx + 4, h - 0.3, h, cz - 0.5, cz + 0.5, C.White, Enum.Material.Neon, { collide = false })
		light(bayLamp, "Point", 1, 26, C.White)
		if open then
			box(service, "RollerUp", bx0, bx1, 11, 12.5, z0 + 0.1, z0 + 0.9, C.Kerb, Enum.Material.Metal)
		else
			-- Aluminium rails and stiles over one sheet of glass. The stiles sit inside the rails'
			-- depth, so no two faces of the frame share a plane.
			box(service, "DoorGlass", bx0 + 0.2, bx1 - 0.2, FLOOR + 0.1, 12.3, z0 + 0.44, z0 + 0.56, C.Glass, Enum.Material.Glass, {
				transparency = 0.45,
				reflectance = 0.2,
				query = false,
				shadow = false,
			})
			for k = 0, 5 do
				local y = FLOOR + (12.5 - FLOOR) / 5 * k
				box(service, "DoorRail", bx0, bx1, math.max(y - 0.15, FLOOR), math.min(y + 0.15, 12.5), z0 + 0.3, z0 + 0.7, C.Panel, Enum.Material.Metal)
			end
			for k = 0, 4 do
				local x = bx0 + bayWidth / 4 * k
				box(service, "DoorStile", x - 0.12, x + 0.12, FLOOR, 12.5, z0 + 0.34, z0 + 0.66, C.Panel, Enum.Material.Metal)
			end
		end
		local pack = box(service, "WallPack", bx0 + 1.2, bx0 + 2.8, 13.4, 14.4, z0 - 0.7, z0, C.Charcoal, Enum.Material.Metal)
		light(pack, "Spot", 1.5, 24, C.White, 110)
		box(service, "WallPackLens", bx0 + 1.3, bx0 + 2.7, 13.35, 13.4, z0 - 0.6, z0 - 0.1, C.White, Enum.Material.Neon, { collide = false, shadow = false, query = false })
		local number = box(service, "BayNumber", bx0 + 7, bx1 - 7, 13.2, 15.4, z0 - 0.15, z0, C.Navy, Enum.Material.SmoothPlastic)
		sign(number, Enum.NormalId.Front, `BAY {i + 1}`, C.Gold, true, Enum.Font.GothamBold)
	end
	box(service, "Pier", x1 - gap, x1 + 0.2, FLOOR, h - 1.6, z0 - 0.2, z0 + 1, C.Charcoal, Enum.Material.Slate)
	-- A window band along the back, high up, and a customer door with a canopy at the west end.
	for i = 0, 7 do
		local wx = x0 + 8 + i * 13.4
		box(service, "HighWindow", wx, wx + 9, 13, 16, z1 - 0.1, z1 + 0.05, C.Glass, Enum.Material.Glass, { transparency = 0.4, query = false })
	end
	box(service, "DropOffCanopy", 132, x0, 12, 12.8, 104, 118, C.Panel, Enum.Material.SmoothPlastic)
	box(service, "CanopyEdge", 131.8, x0, 11.7, 12, 103.8, 118.2, C.Charcoal, Enum.Material.Metal, { shadow = false })
	local canopyLamp = box(service, "CanopyLamp", 138, 146, 11.6, 11.7, 110, 112, C.White, Enum.Material.Neon, { collide = false, shadow = false })
	light(canopyLamp, "Spot", 1.5, 16, C.White, 110)
	post(service, "CanopyPost", 133.5, 105.5, LOT, 12, 0.7, C.Charcoal, Enum.Material.Metal)
	post(service, "CanopyPost", 133.5, 116.5, LOT, 12, 0.7, C.Charcoal, Enum.Material.Metal)
	local dropSign = box(service, "DropOffSign", 132, 132.3, 12.8, 14.2, 104, 118, C.Navy, Enum.Material.SmoothPlastic)
	sign(dropSign, Enum.NormalId.Left, "SERVICE DROP-OFF", C.Gold, true, Enum.Font.GothamBold)
	box(service, "DropOffPad", 132, x0, 0, LOT + 0.04, 104, 118, C.DarkFloor, Enum.Material.Asphalt)
	-- The door the canopy is for: without it, a driver dropping off pulls up to a blank wall.
	box(service, "ReceptionFrame", x0 - 0.3, x0, FLOOR, FLOOR + 8.6, 113.2, 117.6, C.Charcoal, Enum.Material.Metal)
	box(service, "ReceptionDoor", x0 - 0.45, x0 - 0.3, FLOOR + 0.2, FLOOR + 8.2, 113.5, 117.3, C.Screen, Enum.Material.Glass, { reflectance = 0.3 })
	post(service, "ReceptionHandle", x0 - 0.6, 116.6, FLOOR + 3, FLOOR + 5.4, 0.2, C.Gold, Enum.Material.Metal)
	local reception = box(service, "ReceptionSign", x0 - 0.3, x0, FLOOR + 9, FLOOR + 10.6, 113.2, 117.6, C.Navy, Enum.Material.SmoothPlastic)
	sign(reception, Enum.NormalId.Left, "SERVICE\nRECEPTION", C.Gold, true, Enum.Font.GothamBold)
	box(service, "ReceptionStep", x0 - 1.6, x0 - 0.3, 0, 0.45, 113.2, 117.6, C.Kerb, Enum.Material.Concrete)

	-- A dark base course and a shadow line under the roof: a plain box of panel reads as a
	-- building once its foot and its head are drawn.
	box(service, "Plinth", x0 - 0.15, x1 + 0.15, 0, 2.2, z1 - 0.2, z1 + 0.15, C.Charcoal, Enum.Material.Slate)
	box(service, "Plinth", x0 - 0.15, x0 + 0.2, 0, 2.2, z0 + 1, z1 - 0.2, C.Charcoal, Enum.Material.Slate)
	box(service, "Plinth", x1 - 0.2, x1 + 0.15, 0, 2.2, z0 + 1, z1 - 0.2, C.Charcoal, Enum.Material.Slate)
	box(service, "Reveal", x0 - 0.9, x1 + 0.9, h - 0.3, h, z1 + 0.05, z1 + 0.9, C.Charcoal, Enum.Material.Metal, { shadow = false })
	box(service, "Reveal", x0 - 0.9, x0 - 0.05, h - 0.3, h, z0 - 0.6, z1 + 0.05, C.Charcoal, Enum.Material.Metal, { shadow = false })
	box(service, "Reveal", x1 + 0.05, x1 + 0.9, h - 0.3, h, z0 - 0.6, z1 + 0.05, C.Charcoal, Enum.Material.Metal, { shadow = false })
	for _, x in { x0 + 6, 196, 232, x1 - 6 } do
		post(service, "Downpipe", x, z1 + 0.45, 0, h, 0.6, C.Charcoal, Enum.Material.Metal)
	end

	-- Plant on the roof, which the showroom's own roof looks straight across at.
	for _, u in { { 172, 128 }, { 200, 138 }, { 228, 126 } } do
		box(service, "RoofUnit", u[1] - 4, u[1] + 4, h + 1, h + 3.8, u[2] - 3, u[2] + 3, C.Kerb, Enum.Material.Metal)
		disc(service, "RoofFan", u[1] + 1.5, u[2], h + 3.8, h + 4, 3.6, C.Charcoal, Enum.Material.Metal)
	end
	post(service, "Vent", 250, 140, h + 1, h + 3.5, 1, C.Charcoal, Enum.Material.Metal)
	post(service, "Vent", 254, 132, h + 1, h + 2.8, 0.8, C.Charcoal, Enum.Material.Metal)

	-- The yard behind: parts come in at a roller door, bins sit in an enclosure, staff smoke by the
	-- back door. None of it is visited, all of it says the building works.
	local yard = folder(service, "Yard")
	box(yard, "Apron", 196, x1, 0, LOT, z1, z1 + 20, C.Kerb, Enum.Material.Concrete)
	box(yard, "PartsDoor", 236, 252, FLOOR, 13, z1, z1 + 0.35, C.Kerb, Enum.Material.Metal)
	for rib = 1, 10 do
		local y = FLOOR + rib * 1.15
		box(yard, "Rib", 236, 252, y, y + 0.12, z1 + 0.35, z1 + 0.5, C.Charcoal, Enum.Material.Metal, { collide = false, shadow = false })
	end
	box(yard, "PartsHead", 235, 253, 13, 14, z1, z1 + 0.6, C.Charcoal, Enum.Material.Metal)
	local parts = box(yard, "PartsSign", 239, 249, 14.6, 16.2, z1, z1 + 0.25, C.Navy, Enum.Material.SmoothPlastic)
	sign(parts, Enum.NormalId.Back, "PARTS", C.Gold, true, Enum.Font.GothamBold)
	local partsPack = box(yard, "WallPack", 243.2, 244.8, 16.5, 17.4, z1, z1 + 0.7, C.Charcoal, Enum.Material.Metal)
	light(partsPack, "Spot", 1.5, 24, C.White, 110)
	box(yard, "WallPackLens", 243.3, 244.7, 16.45, 16.5, z1 + 0.1, z1 + 0.6, C.White, Enum.Material.Neon, { collide = false, shadow = false, query = false })
	for _, x in { 234.5, 253.5 } do
		bollard(yard, x, z1 + 1.5, LOT, 3.5, 0.9, C.Yellow, C.Charcoal)
	end
	paint(yard, "Hatch", 236, 252, z1 + 1, z1 + 1.4, C.Yellow)

	box(yard, "StaffDoor", 208, 212, FLOOR, FLOOR + 8, z1, z1 + 0.3, C.Charcoal, Enum.Material.Metal)
	box(yard, "DoorCanopy", 206.5, 213.5, FLOOR + 9, FLOOR + 9.4, z1, z1 + 3, C.Panel, Enum.Material.SmoothPlastic)
	local wallPack = box(yard, "WallPack", 209.3, 210.7, FLOOR + 10, FLOOR + 11, z1, z1 + 0.6, C.Charcoal, Enum.Material.Metal)
	light(wallPack, "Spot", 1.2, 18, C.White, 90)
	box(yard, "WallPackLens", 209.4, 210.6, FLOOR + 9.95, FLOOR + 10, z1 + 0.05, z1 + 0.55, C.White, Enum.Material.Neon, { collide = false, shadow = false })

	-- The bin enclosure: three walls and a gap to wheel them out.
	local ex0, ex1, ez0, ez1 = 214, 228, z1 + 8, z1 + 18
	box(yard, "BinWall", ex0, ex0 + 0.6, 0, 6, ez0, ez1 - 0.6, C.Panel, Enum.Material.SmoothPlastic)
	box(yard, "BinWall", ex1 - 0.6, ex1, 0, 6, ez0, ez1 - 0.6, C.Panel, Enum.Material.SmoothPlastic)
	box(yard, "BinWall", ex0, ex1, 0, 6, ez1 - 0.6, ez1, C.Panel, Enum.Material.SmoothPlastic)
	box(yard, "BinCap", ex0 - 0.1, ex1 + 0.1, 6, 6.3, ez1 - 0.7, ez1 + 0.1, C.Charcoal, Enum.Material.Metal)
	for i, colour in { C.LeafDark, C.Navy } do
		local bx = ex0 + 1.2 + (i - 1) * 6.2
		box(yard, "Bin", bx, bx + 5.4, LOT + 0.6, LOT + 4.2, ez0 + 3.5, ez1 - 1.2, colour, Enum.Material.SmoothPlastic)
		box(yard, "BinLid", bx - 0.1, bx + 5.5, LOT + 4.2, LOT + 4.5, ez0 + 3.3, ez1 - 1, C.Charcoal, Enum.Material.SmoothPlastic)
		for _, wx in { bx + 0.8, bx + 4.6 } do
			disc(yard, "Wheel", wx, ez0 + 4.2, LOT, LOT + 0.6, 0.6, C.Charcoal, Enum.Material.Rubber)
		end
	end
	-- Facing away from the wall, into the yard.
	local yardBench = standIn(folder(yard, "Bench"), "bench", 180)
	box(yardBench, "BenchSeat", 200, 205, FLOOR + 1.3, FLOOR + 1.6, z1 + 2, z1 + 3.4, C.Wood, Enum.Material.Wood)
	for _, x in { 200.5, 204.5 } do
		box(yardBench, "BenchLeg", x - 0.2, x + 0.2, LOT, FLOOR + 1.3, z1 + 2.2, z1 + 3.2, C.Charcoal, Enum.Material.Metal)
	end
	-- Tyres by the parts door, waiting to go in.
	tyreStack(yard, 256.5, z1 + 3.5, LOT)
	tyreStack(yard, 259.5, z1 + 3.5, LOT)
end

-- The customer car park on the east flank, with its own driveway off the road.
local function buildCustomerParking(model: Model)
	local park = folder(model, "CustomerParking")
	box(park, "Driveway", 272, 286, 0, 0.2, 0, 8, C.Asphalt, Enum.Material.Asphalt)
	box(park, "Asphalt", 270, 308, 0, LOT, 8, 98, C.Asphalt, Enum.Material.Asphalt)
	box(park, "KerbEast", 308, 309, 0, 0.45, 8, 112, C.Kerb, Enum.Material.Concrete)
	for i = 0, 7 do
		local z = 12 + i * 10.5
		paint(park, "BayLine", 288, 308, z - 0.18, z + 0.18, C.Line)
		if i < 7 then
			box(park, "WheelStop", 305, 306, LOT, LOT + 0.55, z + 2, z + 8.5, C.Kerb, Enum.Material.Concrete, { shadow = false })
		end
	end
	groundText(park, "Customers", "CUSTOMERS", 272, 286, 44, 60, C.Line)
	-- Lit like the lot: two poles behind the kerb over the bays, one across the aisle.
	lampPost(park, 310, 34, 0, -6)
	lampPost(park, 310, 70, 0, -6)
	lampPost(park, 269.2, 52, 0, 5)
	local parkSign = folder(park, "Sign")
	post(parkSign, "Post", 271, 7.5, WALK, 8, 0.4, C.Charcoal, Enum.Material.Metal)
	local plate = box(parkSign, "Plate", 268.5, 273.5, 5.5, 8, 7.35, 7.65, C.Navy, Enum.Material.SmoothPlastic)
	sign(plate, Enum.NormalId.Front, "CUSTOMER\nPARKING", C.Gold, true, Enum.Font.GothamBold)
	-- Planted ends at the head and foot of the bays -- not across the aisle, where the south one
	-- first stood and closed the way in off the driveway.
	for _, span in { { 8.4, 11.6 }, { 86, 97.6 } } do
		box(park, "Island", 288, 307.6, 0, 0.5, span[1], span[2], C.Kerb, Enum.Material.Concrete)
		box(park, "IslandGrass", 288.4, 307.2, 0.5, 0.6, span[1] + 0.4, span[2] - 0.4, C.Leaf, Enum.Material.Grass)
	end
	tree(park, 298, 92, 0.6, 16)
	for _, x in { 292, 298, 304 } do
		bush(park, x, 10, 0.6, 2.4)
	end
	for _, x in { 291, 305 } do
		bush(park, x, 92, 0.6, 2.6)
	end

	-- A zebra across the aisle from the bays to the plaza: the way a customer walks in.
	for k = 0, 8 do
		local x = 271 + k * 2
		paint(park, "Zebra", x, x + 1, 17, 21, C.Line)
	end

	-- Two EV bays nearest the showroom door, painted, each with its charger at the kerb.
	local ev = folder(park, "EVCharging")
	for i = 5, 6 do
		local z0, z1 = 12 + i * 10.5, 12 + (i + 1) * 10.5
		local mid = (z0 + z1) / 2
		paint(ev, "EVBay", 288.6, 304.6, z0 + 0.4, z1 - 0.4, C.Green)
		groundText(ev, "EVText", "EV", 290, 300, z0 + 2.5, z1 - 2.5, C.White)
		box(ev, "Pedestal", 306.4, 307.6, LOT, LOT + 5, mid - 0.6, mid + 0.6, C.White, Enum.Material.SmoothPlastic)
		box(ev, "Cap", 306.25, 307.75, LOT + 5, LOT + 5.25, mid - 0.75, mid + 0.75, C.Green, Enum.Material.SmoothPlastic)
		local screen = box(ev, "Screen", 306.25, 306.4, LOT + 3.3, LOT + 4.5, mid - 0.45, mid + 0.45, C.Screen, Enum.Material.SmoothPlastic)
		sign(screen, Enum.NormalId.Left, "EV", C.Green, true)
		box(ev, "Glow", 306.3, 306.4, LOT + 1.2, LOT + 2.9, mid - 0.1, mid + 0.1, C.Green, Enum.Material.Neon, { collide = false, shadow = false })
		box(ev, "Holster", 306.1, 306.4, LOT + 2.3, LOT + 3, mid + 0.2, mid + 0.5, C.Charcoal, Enum.Material.SmoothPlastic)
	end
	local evSign = folder(ev, "Sign")
	post(evSign, "Post", 308.5, 75, 0.45, 8, 0.35, C.Charcoal, Enum.Material.Metal)
	local evPlate = box(evSign, "Plate", 308.35, 308.65, 5.6, 8, 72.5, 77.5, C.Green, Enum.Material.SmoothPlastic)
	sign(evPlate, Enum.NormalId.Left, "EV\nCHARGING", C.White, true, Enum.Font.GothamBold)
end

--[[
	A drive-through car wash east of the service centre, fed by the service lane: pay at the
	kiosk, roll north through the tunnel, dry off and vacuum out on the apron behind. The lane is
	carried east to the customer car park's aisle, so the car park, the lane and the service
	bays are one loop rather than three dead ends.
]]
local WASH = { x0 = 280, x1 = 300, z0 = 116, z1 = 146, height = 13 }

local function buildCarWash(model: Model)
	local wash = folder(model, "CarWash")
	local x0, x1, z0, z1, h = WASH.x0, WASH.x1, WASH.z0, WASH.z1, WASH.height
	local deck = 0.25 -- the tunnel floor, a lip above the asphalt

	box(wash, "Lane", SERVICE.x1, 308, 0, LOT, 98, 112, C.Asphalt, Enum.Material.Asphalt)
	box(wash, "Approach", x0, x1, 0, LOT, 112, z0, C.Asphalt, Enum.Material.Asphalt)
	groundText(wash, "LaneText", "WASH", 268, 290, 100, 110, C.Line)
	box(wash, "Slab", x0, x1, 0, deck, z0, z1, C.DarkFloor, Enum.Material.Concrete)
	for _, x in { 286, 293.6 } do
		box(wash, "GuideRail", x, x + 0.4, deck, deck + 0.45, z0, z1, C.Yellow, Enum.Material.Metal)
	end

	-- Side walls: solid at the foot and head, a glass band between so the brushes show.
	for _, side in { { x0, x0 + 1 }, { x1 - 1, x1 } } do
		local a, b = side[1], side[2]
		box(wash, "WallLow", a, b, deck, 4, z0, z1, C.Panel, Enum.Material.SmoothPlastic)
		box(wash, "WallHigh", a, b, 9, h, z0, z1, C.Panel, Enum.Material.SmoothPlastic)
		box(wash, "Band", a + 0.3, b - 0.3, 4, 9, z0, z1, C.Glass, Enum.Material.Glass, { transparency = 0.45, reflectance = 0.2, query = false, shadow = false })
		for z = z0 + 5, z1 - 5, 5 do
			box(wash, "Mullion", a, b, 4, 9, z - 0.25, z + 0.25, C.Charcoal, Enum.Material.Metal)
		end
		box(wash, "Plinth", a - 0.15, b + 0.15, 0, 1.2, z0 + 0.3, z1 - 0.3, C.Charcoal, Enum.Material.Slate)
	end
	box(wash, "Roof", x0 - 0.6, x1 + 0.6, h, h + 0.8, z0 - 0.6, z1 + 0.6, C.OffWhite, Enum.Material.SmoothPlastic)
	local front = box(wash, "Fascia", x0 - 1, x1 + 1, h - 2.2, h + 1.4, z0 - 1.2, z0 - 0.6, C.Navy, Enum.Material.SmoothPlastic)
	sign(front, Enum.NormalId.Front, "MERIDIAN CAR WASH", C.Gold, true)
	box(wash, "FasciaGlow", x0 - 1, x1 + 1, h - 2.5, h - 2.2, z0 - 1.25, z0 - 0.55, C.Gold, Enum.Material.Neon, { collide = false, shadow = false })
	local back = box(wash, "Fascia", x0 - 1, x1 + 1, h - 2.2, h + 1.4, z1 + 0.6, z1 + 1.2, C.Navy, Enum.Material.SmoothPlastic)
	sign(back, Enum.NormalId.Back, "THANK YOU", C.Gold, true)
	for _, z in { z0 - 0.6, z1 } do
		box(wash, "Header", x0 + 1, x1 - 1, h - 2.2, h, z, z + 0.6, C.Panel, Enum.Material.SmoothPlastic)
	end

	-- A stop-go light on the entrance pier.
	box(wash, "Signal", x0 - 0.9, x0 - 0.1, 6, 9, z0 - 0.5, z0 + 0.3, C.Charcoal, Enum.Material.Metal)
	box(wash, "Stop", x0 - 0.95, x0 - 0.9, 7.8, 8.7, z0 - 0.35, z0 + 0.15, C.Red, Enum.Material.Neon, { collide = false, shadow = false })
	box(wash, "Go", x0 - 0.95, x0 - 0.9, 6.3, 7.2, z0 - 0.35, z0 + 0.15, C.Green, Enum.Material.Neon, { collide = false, shadow = false })

	-- Inside, in the order a car meets them: a curtain of cloth strips, the two side brushes,
	-- the top brush on its gantry, and the dryer arch at the exit.
	for i = 0, 15 do
		local x = x0 + 1.4 + i * 1.1
		box(wash, "Strip", x, x + 0.8, 5, h - 0.4, 122, 122.15, if i % 2 == 0 then C.Blue else C.White, Enum.Material.Fabric, {
			collide = false,
			shadow = false,
			query = false,
		})
	end
	box(wash, "StripRail", x0 + 1, x1 - 1, h - 0.4, h, 121.8, 122.35, C.Charcoal, Enum.Material.Metal)
	for _, x in { 283.2, 296.8 } do
		post(wash, "BrushCore", x, 130, deck, h - 0.4, 0.5, C.Charcoal, Enum.Material.Metal)
		post(wash, "Brush", x, 130, 1.2, 9.5, 3.8, C.Blue, Enum.Material.Fabric)
		box(wash, "BrushArm", if x < 290 then x0 + 1 else x, if x < 290 then x else x1 - 1, h - 1.2, h - 0.6, 129.7, 130.3, C.Charcoal, Enum.Material.Metal)
	end
	for _, x in { x0 + 1.2, x1 - 2 } do
		box(wash, "GantryPost", x, x + 0.8, deck, h - 1.4, 135.6, 136.4, C.Charcoal, Enum.Material.Metal)
	end
	box(wash, "GantryBeam", x0 + 1.2, x1 - 1.2, h - 1.4, h - 0.4, 135.6, 136.4, C.Charcoal, Enum.Material.Metal)
	-- A cylinder's length runs along its own X, which is already across the tunnel.
	local topBrush = Instance.new("Part")
	topBrush.Name = "TopBrush"
	topBrush.Shape = Enum.PartType.Cylinder
	topBrush.Size = Vector3.new(13, 3, 3)
	topBrush.CFrame = at(290, 7.6, 136)
	style(topBrush, C.Blue, Enum.Material.Fabric, { collide = false })
	topBrush.Parent = wash
	for _, x in { 284.6, 295.4 } do
		box(wash, "Hanger", x - 0.15, x + 0.15, 7.6, h - 1.4, 135.85, 136.15, C.Charcoal, Enum.Material.Metal, { collide = false })
	end
	box(wash, "DryerArch", x0 + 1, x1 - 1, h - 3.4, h - 0.4, 141, 143, C.Panel, Enum.Material.SmoothPlastic)
	for i = 0, 5 do
		local x = x0 + 3 + i * 2.6
		box(wash, "Nozzle", x, x + 1.4, h - 3.8, h - 3.4, 141.4, 142.6, C.Charcoal, Enum.Material.Metal, { collide = false })
	end
	for _, z in { 126, 138 } do
		local lamp = box(wash, "Lamp", 288, 292, h - 0.15, h, z - 2, z + 2, C.White, Enum.Material.Neon, { collide = false, shadow = false })
		light(lamp, "Point", 1.1, 20, C.White)
	end

	-- The pay kiosk on its island by the way in.
	box(wash, "PayIsland", 274, 279, 0, 0.5, 112.5, 118, C.Kerb, Enum.Material.Concrete)
	box(wash, "PayPost", 276.6, 278, 0.5, 5.2, 114.5, 116, C.White, Enum.Material.SmoothPlastic)
	local pay = box(wash, "PayScreen", 278, 278.15, 3.2, 4.6, 114.7, 115.8, C.Screen, Enum.Material.SmoothPlastic)
	sign(pay, Enum.NormalId.Right, "PAY\nHERE", C.Gold, true, Enum.Font.GothamBold)
	local payCanopy = box(wash, "PayCanopy", 275.4, 279.2, 5.2, 5.5, 113.9, 116.6, C.Navy, Enum.Material.SmoothPlastic)
	light(payCanopy, "Spot", 1.4, 12, C.White, 100)
	box(wash, "PayLamp", 277.4, 279, 5.15, 5.2, 114.6, 115.9, C.White, Enum.Material.Neon, { collide = false, shadow = false, query = false })
	lampPost(wash, 303.5, 110, LOT)
	for _, z in { 113.2, 117.3 } do
		bollard(wash, 276, z, 0.5, 3.2, 0.7, C.Yellow, C.Charcoal)
	end

	-- Dry-off and vacuum bays behind, running on into the service yard.
	local yard = folder(wash, "VacuumBays")
	lampPost(yard, 304, 158, LOT, -5)
	box(yard, "Apron", SERVICE.x1, 306, 0, LOT, z1, 172, C.Asphalt, Enum.Material.Asphalt)
	box(yard, "KerbNorth", SERVICE.x1, 306.6, 0, 0.45, 172, 172.6, C.Kerb, Enum.Material.Concrete)
	box(yard, "KerbEast", 306, 306.6, 0, 0.45, z1, 172, C.Kerb, Enum.Material.Concrete)
	for i = 0, 3 do
		local x = 268 + i * 11
		paint(yard, "BayLine", x - 0.18, x + 0.18, 152, 170, C.Line)
	end
	for i = 0, 2 do
		local x = 273.5 + i * 11
		local pole = folder(yard, "Vacuum")
		box(pole, "Body", x - 0.8, x + 0.8, LOT, LOT + 4.2, 170, 171.4, C.Blue, Enum.Material.SmoothPlastic)
		box(pole, "Top", x - 0.9, x + 0.9, LOT + 4.2, LOT + 4.5, 169.9, 171.5, C.White, Enum.Material.SmoothPlastic)
		post(pole, "Mast", x, 170.7, LOT + 4.5, LOT + 10, 0.35, C.Kerb, Enum.Material.Metal)
		box(pole, "Boom", x - 0.15, x + 0.15, LOT + 9.7, LOT + 10, 164, 170.7, C.Kerb, Enum.Material.Metal, { collide = false })
		box(pole, "Hose", x - 0.2, x + 0.2, LOT + 3.4, LOT + 9.7, 164.1, 164.5, C.Charcoal, Enum.Material.Rubber, { collide = false })
		local label = box(pole, "Label", x - 0.6, x + 0.6, LOT + 2.2, LOT + 3.6, 169.95, 170, C.White, Enum.Material.SmoothPlastic, { collide = false })
		sign(label, Enum.NormalId.Front, "VAC", C.Blue, false, Enum.Font.GothamBlack)
	end
end

--[[
	The handover bay: a canopy off the showroom's side door, over the pickup lane, where a bought
	car is parked for its new owner (Config.Vehicles.ParkStuds west of the counter). It turns the
	moment of buying from a notice on the screen into a place -- walk out of the side door and
	the car is waiting under the lights.

	Cantilevered from two posts at the lane's edge, not four across it: posts in the lane would
	stand where the car is parked, and in the chest-height ray Ground.SpotAt looks along from
	the counter to find the spot.
]]
local HANDOVER = { x0 = 121, x1 = SHOW.x0 - 0.2, z0 = 58, z1 = 74, y = 11.6 }

local function buildHandover(model: Model)
	local bay = folder(model, "HandoverBay")
	local x0, x1, z0, z1, y = HANDOVER.x0, HANDOVER.x1, HANDOVER.z0, HANDOVER.z1, HANDOVER.y
	box(bay, "Canopy", x0, x1, y, y + 0.8, z0, z1, C.Panel, Enum.Material.SmoothPlastic)
	box(bay, "FasciaWest", x0 - 0.3, x0, y - 0.4, y + 1.1, z0 - 0.3, z1 + 0.3, C.Navy, Enum.Material.SmoothPlastic)
	local south = box(bay, "FasciaSouth", x0, x1, y - 0.4, y + 1.1, z0 - 0.3, z0, C.Navy, Enum.Material.SmoothPlastic)
	sign(south, Enum.NormalId.Front, "HANDOVER BAY", C.Gold, true, Enum.Font.GothamBold)
	box(bay, "FasciaNorth", x0, x1, y - 0.4, y + 1.1, z1, z1 + 0.3, C.Navy, Enum.Material.SmoothPlastic)
	local board = box(bay, "Board", x0 - 0.2, x0 + 0.2, y + 1.3, y + 3.6, z0 + 3, z1 - 3, C.Navy, Enum.Material.SmoothPlastic)
	sign(board, Enum.NormalId.Left, "YOUR NEW CAR", C.Gold, true)
	box(bay, "BoardGlow", x0 - 0.25, x0 + 0.25, y + 1.1, y + 1.3, z0 + 2.8, z1 - 2.8, C.Gold, Enum.Material.Neon, { collide = false, shadow = false })
	-- A gold line round the underside, and three downlights over where the car stands.
	for _, run in { { x0 + 0.4, x1, z0 + 0.4, z0 + 0.7 }, { x0 + 0.4, x1, z1 - 0.7, z1 - 0.4 }, { x0 + 0.4, x0 + 0.7, z0 + 0.7, z1 - 0.7 } } do
		box(bay, "Glow", run[1], run[2], y - 0.1, y, run[3], run[4], C.Gold, Enum.Material.Neon, { collide = false, shadow = false, query = false })
	end
	for _, x in { 126, 134, 142 } do
		local lamp = box(bay, "Downlight", x - 1, x + 1, y - 0.1, y, 65, 67, C.Warm, Enum.Material.Neon, { collide = false, shadow = false, query = false })
		light(lamp, "Spot", 2, 16, C.Warm, 90)
	end
	for _, z in { z0 + 0.8, z1 - 0.8 } do
		post(bay, "Post", 139.4, z, LOT, y, 0.9, C.Charcoal, Enum.Material.Metal)
		disc(bay, "PostFoot", 139.4, z, LOT, LOT + 0.3, 1.6, C.Kerb, Enum.Material.Concrete)
	end
	-- The walkway under it gets a runner to the side door, like the one indoors.
	box(bay, "Runner", 140, SHOW.x0, WALK, WALK + 0.02, 62, 68, C.DarkFloor, Enum.Material.Slate, { collide = false, query = false })
end

local function buildEastSide(model: Model)
	local east = folder(model, "EastSide")
	-- Vertical fins across the blank east wall: the cheapest way to give a solid wall a rhythm.
	for i = 0, 17 do
		local z = SHOW.z0 + 3 + i * 4.1
		box(east, "Fin", SHOW.x1, SHOW.x1 + 0.8, FLOOR + 1.1, CEIL - 1, z, z + 0.7, if i % 2 == 0 then C.Charcoal else C.Panel, Enum.Material.Metal, { shadow = false })
	end
	-- A clerestory band high on the wall, and the brand where the car park sees it.
	box(east, "Clerestory", SHOW.x1 + 0.05, SHOW.x1 + 0.3, CEIL - 5.5, CEIL - 2, SHOW.z0 + 6, SHOW.z1 - 6, C.Glass, Enum.Material.Glass, {
		transparency = 0.35,
		reflectance = 0.2,
		query = false,
	})
	local logo = box(east, "Logo", SHOW.x1 + 0.9, SHOW.x1 + 1.3, 8, 24, 48, 72, C.Navy, Enum.Material.SmoothPlastic)
	sign(logo, Enum.NormalId.Right, "M", C.Gold, true)
	box(east, "LogoGlow", SHOW.x1 + 0.85, SHOW.x1 + 1.35, 7.7, 8, 47.7, 72.3, C.Gold, Enum.Material.Neon, { collide = false, shadow = false })

	-- Skylights down the middle of the showroom roof.
	for _, x in { 178, 207, 236 } do
		box(east, "SkylightCurb", x - 7, x + 7, ROOF, ROOF + 0.8, 50, 66, C.Charcoal, Enum.Material.Metal)
		box(east, "Skylight", x - 6.5, x + 6.5, ROOF + 0.8, ROOF + 1.4, 50.5, 65.5, C.Glass, Enum.Material.Glass, {
			transparency = 0.3,
			reflectance = 0.3,
			query = false,
		})
	end

	-- Trees: along the frontage in the plaza, down the west hedge, at the back of the lot.
	local trees = folder(model, "Trees")
	for _, x in { 168, 248 } do
		box(trees, "TreePit", x - 2.5, x + 2.5, PLAZA, PLAZA + 0.1, 16, 21, C.Bark, Enum.Material.Ground, { collide = false })
		-- An uplight in the pit: a lit tree is the cheapest thing that makes a frontage read at night.
		local uplight = box(trees, "Uplight", x + 0.9, x + 1.7, PLAZA + 0.1, PLAZA + 0.35, 17.2, 18, C.Warm, Enum.Material.Neon, { collide = false, shadow = false })
		local beam = light(uplight, "Spot", 1.6, 18, C.Warm, 70) :: SpotLight
		beam.Face = Enum.NormalId.Top
		tree(trees, x, 18.5, PLAZA, 14)
	end
	for _, z in { 20, 56, 92 } do
		tree(trees, -2, z, 0, 18)
	end
	for _, x in { 40, 70 } do
		tree(trees, x, 122, 0, 18)
	end
	for _, x in { 164, 184 } do
		tree(trees, x, 162, 0, 20)
	end
	for _, z in { 120, 140 } do
		tree(trees, 272, z, 0, 18)
	end
end

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
	buildMezzanine(model)
	buildPlaza(model)
	buildDetail(model)
	buildService(model)
	buildCarWash(model)
	buildHandover(model)
	buildCustomerParking(model)
	buildEastSide(model)
	buildSlots(model)
	model.WorldPivot = corner
	model.Parent = parent
	return model
end

return DealershipBuild
