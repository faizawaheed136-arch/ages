--!strict
--[[
	CarBody: what every car in the game looks like, built from parts -- the paint, the glass, the
	lights, the wheels, the seats you see through the windows.

	WHY PARTS AND WHY SHARED. A car of wedges, blocks and cylinders needs nothing bought or
	uploaded, and one builder serves all three places a car is seen: the car a player drives
	(world/VehicleChassis on the server), the car standing on the showroom floor (the same, anchored)
	and the car turning on the shop's stage (the client, from the catalog it is sent). A car that
	looked one way in the shop and another at the kerb would be the showroom lying.

	HOW A BODY IS DRAWN. Each body style is a side view, drawn in studs above the ground at rest and
	in shares of the car's length from its nose:
	  * `top` -- the lower body's upper edge: bumper, bonnet, belt line, boot, tail;
	  * `bottom` -- its lower edge: the sill, turning up into each bumper;
	  * `cabin` -- the greenhouse's roof line, from the windscreen's foot to the rear screen's.
	The lower body is cut into slabs at every point of either line. Each slab is a block with a wedge
	on top where the line climbs or falls and one under it where the sill turns up, so the silhouette
	is the line itself, not a staircase of it. The greenhouse is two glass sides cut the same way,
	a screen and a roof laid along the roof line between them, and the car's seats inside.

	WHERE IT SITS. A model is built round its hull: the one part with mass, the box the chassis's
	springs push, centred between the axles with the nose to local -Z. The hull rides clear of kerbs
	(HULL_BOTTOM); the paint below it -- sills, bumpers -- is scenery that does not collide, which is
	what lets a car look like a car and still drive over the city's kerbs on raycast wheels. Where
	the hull sits at rest is worked out from the springs (Layout), so a car on the floor and the same
	car settled on its suspension stand at the same height.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarSpec = require(ReplicatedStorage:WaitForChild("CarSpec"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local MeshCar = require(ReplicatedStorage:WaitForChild("MeshCar"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type VehicleKind = Types.VehicleKind

local VEHICLES = Config.Vehicles

local CarBody = {}

-- ---------------------------------------------------------------------------------------------
-- Paint: the colours a car can be bought in. The shop's swatches, and what a save names.
-- ---------------------------------------------------------------------------------------------
export type Paint = { key: string, name: string, color: Color3 }

CarBody.Paints = {
	{ key = "white", name = "Glacier White", color = Color3.fromRGB(236, 236, 232) },
	{ key = "silver", name = "Silver Mist", color = Color3.fromRGB(174, 178, 184) },
	{ key = "graphite", name = "Graphite", color = Color3.fromRGB(68, 70, 76) },
	{ key = "black", name = "Obsidian", color = Color3.fromRGB(20, 20, 23) },
	{ key = "red", name = "Rosso", color = Color3.fromRGB(196, 22, 34) },
	{ key = "orange", name = "Sunset", color = Color3.fromRGB(230, 104, 22) },
	{ key = "yellow", name = "Racing Yellow", color = Color3.fromRGB(240, 190, 28) },
	{ key = "lime", name = "Lime", color = Color3.fromRGB(122, 190, 38) },
	{ key = "green", name = "Heritage Green", color = Color3.fromRGB(24, 82, 50) },
	{ key = "teal", name = "Lagoon", color = Color3.fromRGB(16, 130, 146) },
	{ key = "blue", name = "Royal Blue", color = Color3.fromRGB(28, 76, 188) },
	{ key = "purple", name = "Violet", color = Color3.fromRGB(94, 44, 148) },
} :: { Paint }

local function find(list: { Paint }, key: string?): Paint?
	if key == nil then
		return nil
	end
	for _, entry in list do
		if entry.key == key then
			return entry
		end
	end
	return nil
end

function CarBody.Paint(key: string?): Paint?
	return find(CarBody.Paints, key)
end

-- Rim finishes, for the shop's CUSTOMIZE: each car's own finish unless one is chosen.
CarBody.Rims = {
	{ key = "silver", name = "Silver", color = Color3.fromRGB(196, 200, 206) },
	{ key = "gunmetal", name = "Gunmetal", color = Color3.fromRGB(78, 80, 86) },
	{ key = "black", name = "Gloss Black", color = Color3.fromRGB(26, 26, 28) },
	{ key = "gold", name = "Gold", color = Color3.fromRGB(214, 170, 72) },
	{ key = "bronze", name = "Bronze", color = Color3.fromRGB(150, 104, 62) },
	{ key = "white", name = "White", color = Color3.fromRGB(236, 236, 234) },
	{ key = "red", name = "Red", color = Color3.fromRGB(200, 30, 40) },
	{ key = "blue", name = "Blue", color = Color3.fromRGB(40, 100, 220) },
} :: { Paint }

function CarBody.Rim(key: string?): Paint?
	return find(CarBody.Rims, key)
end

-- Underglow: a line of light under the car and the pool it throws on the road. None by default.
CarBody.Glows = {
	{ key = "red", name = "Red", color = Color3.fromRGB(255, 40, 60) },
	{ key = "orange", name = "Orange", color = Color3.fromRGB(255, 130, 30) },
	{ key = "yellow", name = "Yellow", color = Color3.fromRGB(255, 220, 40) },
	{ key = "green", name = "Green", color = Color3.fromRGB(40, 255, 110) },
	{ key = "cyan", name = "Cyan", color = Color3.fromRGB(40, 230, 255) },
	{ key = "blue", name = "Blue", color = Color3.fromRGB(50, 110, 255) },
	{ key = "purple", name = "Purple", color = Color3.fromRGB(170, 70, 255) },
	{ key = "pink", name = "Pink", color = Color3.fromRGB(255, 80, 200) },
	{ key = "white", name = "White", color = Color3.fromRGB(240, 244, 255) },
} :: { Paint }

function CarBody.Glow(key: string?): Paint?
	return find(CarBody.Glows, key)
end

-- A car's chosen look, as colours: nil for anything left as it came.
export type Look = { paint: Color3?, rims: Color3?, glow: Color3? }

-- The look named by a set of keys, as the shop and a save hold it.
function CarBody.LookOf(paintKey: string?, rimKey: string?, glowKey: string?): Look
	local paint, rims, glow = CarBody.Paint(paintKey), CarBody.Rim(rimKey), CarBody.Glow(glowKey)
	return {
		paint = if paint then paint.color else nil,
		rims = if rims then rims.color else nil,
		glow = if glow then glow.color else nil,
	}
end

-- ---------------------------------------------------------------------------------------------
-- The fixed colours: glass, trim, chrome, rubber, lamps.
-- ---------------------------------------------------------------------------------------------
local GLASS = Color3.fromRGB(26, 32, 42)
local GLASS_TRANSPARENCY = 0.32
local TRIM = Color3.fromRGB(20, 20, 23)
local CHROME = Color3.fromRGB(206, 210, 216)
local RUBBER = Color3.fromRGB(26, 26, 28)
local INTERIOR = Color3.fromRGB(30, 30, 34)
local LAMP_GLASS = Color3.fromRGB(214, 222, 230)
local DRL = Color3.fromRGB(236, 244, 255)
local TAIL_GLASS = Color3.fromRGB(110, 8, 14)
-- What a brake light shows at rest, and pressed. Neon's glow scales with its colour, so the same
-- part reads as a tail lamp and then, brighter, as a brake lamp.
CarBody.TailColor = Color3.fromRGB(150, 14, 22)
CarBody.BrakeColor = Color3.fromRGB(255, 36, 44)
local CALIPER = Color3.fromRGB(196, 28, 36)
local DISC = Color3.fromRGB(120, 122, 126)
local PLATE = Color3.fromRGB(240, 240, 236)

-- The physics hull's underside, in studs above the ground at rest. Everything below it is paint that
-- does not collide: a hull any lower catches the kerbs the raycast wheels exist to ride over.
local HULL_BOTTOM = 1.7
-- The hull's mass per stud of its footprint: a hull 2.8 studs deep of density 0.7, which is what
-- the car was when Config.Vehicles' springs, dampers and drive were tuned. A car half that heavy --
-- the first cut of these bodies -- had the same springs throw it off the ground and onto its roof.
local HULL_MASS_PER_STUD2 = 0.7 * 2.8
-- The share of a car's mass carried by four hidden weights near its corners rather than by the
-- hull. Same weight, spread out the way a real car's is: two to three times the resistance to
-- rolling and pitching. The hull alone was light across its width against the springs, and a
-- turn set it rocking from wheel to wheel.
local BALLAST_SHARE = 0.8
-- A tyre's width, and how far its outer face stands proud of the body side.
local TYRE_WIDTH = 1.0
local TYRE_PROUD = 0.08
-- The arch round each wheel: this much bigger than the tyre.
local ARCH_MARGIN = 0.25
local EPS = 1e-4

-- ---------------------------------------------------------------------------------------------
-- Body styles.
-- ---------------------------------------------------------------------------------------------
type Point = { number } -- { share of the length from the nose, height above the ground }
-- A lamp laid along the top line between two shares, `inset` in from the side and `width` wide;
-- or, with `face`, stood on the nose or tail face between two heights.
type Lamp = { from: number, to: number, inset: number, width: number, face: boolean? }

type Style = {
	axles: { number },
	top: { Point },
	bottom: { Point },
	cabin: { Point }?,
	tumble: number,
	pillars: { number },
	rearPillar: number?,
	head: Lamp,
	tail: Lamp,
	tailBar: boolean?,
	grille: string, -- "bars" | "frame" | "mesh" | "intake"
	rims: string, -- "five" | "ten" | "twin" | "steel"
	rimColor: Color3,
	seats: { number },
	seatY: number,
	doors: { number },
	bed: { number }?, -- { from, to, floor, top }: an open box let into the body
	screen: { number }?, -- open cars: { foot share, top share, top height }
	hoops: boolean?,
	rails: boolean?,
	wing: { number }?, -- { from, to, height }
	lip: boolean?,
	intakes: { number }?, -- { from, to }
	exhausts: number,
	diffuser: boolean?,
}

local SILVER = Color3.fromRGB(196, 200, 206)
local GUNMETAL = Color3.fromRGB(78, 80, 86)
local BLACK_RIM = Color3.fromRGB(28, 28, 30)

local STYLES: { [string]: Style } = {
	-- A three-box saloon: bonnet, cabin, boot.
	sedan = {
		axles = { 0.19, 0.79 },
		top = {
			{ 0, 2.1 },
			{ 0.02, 2.7 },
			{ 0.07, 3.0 },
			{ 0.19, 3.2 },
			{ 0.35, 3.45 },
			{ 0.38, 3.5 },
			{ 0.76, 3.55 },
			{ 0.81, 3.62 },
			{ 0.95, 3.62 },
			{ 0.985, 3.05 },
			{ 1, 2.4 },
		},
		bottom = { { 0, 0.95 }, { 0.05, 0.6 }, { 0.95, 0.6 }, { 1, 1.05 } },
		cabin = { { 0.38, 0 }, { 0.51, 5.25 }, { 0.71, 5.3 }, { 0.81, 0 } },
		tumble = 0.55,
		pillars = { 0.605 },
		rearPillar = 0.745,
		head = { from = 0, to = 0.02, inset = 0.25, width = 1.6 },
		tail = { from = 0.95, to = 0.985, inset = 0.2, width = 1.7 },
		grille = "bars",
		rims = "five",
		rimColor = SILVER,
		seats = { 0.535, 0.69 },
		seatY = 1.9,
		doors = { 0.39, 0.6, 0.745 },
		exhausts = 1,
	},
	-- The sedan's nose on a long roof and a near-upright tailgate.
	wagon = {
		axles = { 0.18, 0.77 },
		top = {
			{ 0, 2.1 },
			{ 0.02, 2.7 },
			{ 0.07, 3.0 },
			{ 0.18, 3.2 },
			{ 0.33, 3.45 },
			{ 0.36, 3.5 },
			{ 0.955, 3.62 },
			{ 0.985, 3.35 },
			{ 1, 2.5 },
		},
		bottom = { { 0, 0.95 }, { 0.05, 0.6 }, { 0.95, 0.6 }, { 1, 1.05 } },
		cabin = { { 0.36, 0 }, { 0.48, 5.4 }, { 0.92, 5.45 }, { 0.965, 0 } },
		tumble = 0.55,
		pillars = { 0.58, 0.765 },
		rearPillar = 0.9,
		head = { from = 0, to = 0.02, inset = 0.25, width = 1.6 },
		-- On the steep last stretch of the tail: upright lamps at the corners, the way an estate's are.
		tail = { from = 0.985, to = 1, inset = 0.15, width = 1.3 },
		grille = "frame",
		rims = "twin",
		rimColor = SILVER,
		seats = { 0.515, 0.66 },
		seatY = 1.9,
		doors = { 0.37, 0.575, 0.76 },
		rails = true,
		exhausts = 1,
	},
	-- A pickup: a tall bonnet, a short cab, an open bed.
	pickup = {
		axles = { 0.17, 0.77 },
		top = {
			{ 0, 3.0 },
			{ 0.02, 3.75 },
			{ 0.06, 4.0 },
			{ 0.17, 4.15 },
			{ 0.28, 4.25 },
			{ 0.595, 4.3 },
			{ 0.595, 2.9 },
			{ 1, 2.9 },
		},
		bottom = { { 0, 1.4 }, { 0.05, 1.0 }, { 0.95, 1.0 }, { 1, 1.3 } },
		cabin = { { 0.28, 0 }, { 0.37, 6.05 }, { 0.575, 6.1 }, { 0.59, 0 } },
		tumble = 0.45,
		pillars = { 0.46 },
		rearPillar = 0.56,
		head = { from = 0, to = 0.02, inset = 0.3, width = 1.7 },
		tail = { from = 3.0, to = 4.1, inset = 0.05, width = 0.55, face = true },
		grille = "frame",
		rims = "steel",
		rimColor = GUNMETAL,
		seats = { 0.43, 0.53 },
		seatY = 2.5,
		doors = { 0.29, 0.455, 0.57 },
		bed = { 0.6, 1, 2.9, 4.3 },
		exhausts = 1,
	},
	-- A tall estate on a raised ride: the family car for a family with a boat.
	suv = {
		axles = { 0.18, 0.79 },
		top = {
			{ 0, 3.0 },
			{ 0.02, 3.75 },
			{ 0.06, 4.0 },
			{ 0.18, 4.15 },
			{ 0.3, 4.35 },
			{ 0.33, 4.4 },
			{ 0.95, 4.5 },
			{ 0.985, 4.25 },
			{ 1, 3.5 },
		},
		bottom = { { 0, 1.4 }, { 0.05, 1.0 }, { 0.95, 1.0 }, { 1, 1.4 } },
		cabin = { { 0.33, 0 }, { 0.44, 6.2 }, { 0.93, 6.25 }, { 0.97, 0 } },
		tumble = 0.5,
		pillars = { 0.58, 0.77 },
		rearPillar = 0.88,
		head = { from = 0, to = 0.02, inset = 0.3, width = 1.8 },
		tail = { from = 0.95, to = 0.985, inset = 0.2, width = 1.6 },
		tailBar = true,
		grille = "frame",
		rims = "twin",
		rimColor = SILVER,
		seats = { 0.5, 0.66 },
		seatY = 2.5,
		doors = { 0.34, 0.575, 0.765 },
		rails = true,
		exhausts = 2,
	},
	-- A two-door with a fastback roof.
	coupe = {
		axles = { 0.19, 0.79 },
		top = {
			{ 0, 1.9 },
			{ 0.02, 2.5 },
			{ 0.07, 2.85 },
			{ 0.19, 3.1 },
			{ 0.38, 3.25 },
			{ 0.41, 3.3 },
			{ 0.78, 3.35 },
			{ 0.93, 3.42 },
			{ 0.965, 3.38 },
			{ 0.99, 2.9 },
			{ 1, 2.3 },
		},
		bottom = { { 0, 0.8 }, { 0.05, 0.5 }, { 0.95, 0.5 }, { 1, 0.9 } },
		cabin = { { 0.41, 0 }, { 0.55, 4.65 }, { 0.66, 4.7 }, { 0.9, 0 } },
		tumble = 0.6,
		pillars = {},
		rearPillar = 0.76,
		head = { from = 0.02, to = 0.07, inset = 0.3, width = 1.7 },
		tail = { from = 0.965, to = 0.99, inset = 0.2, width = 1.8 },
		grille = "mesh",
		rims = "ten",
		rimColor = GUNMETAL,
		seats = { 0.56, 0.69 },
		seatY = 1.45,
		doors = { 0.42, 0.69 },
		exhausts = 2,
		diffuser = true,
	},
	-- A grand tourer: a long bonnet, the cabin pushed back, a lip on the tail.
	gt = {
		axles = { 0.2, 0.8 },
		top = {
			{ 0, 1.9 },
			{ 0.02, 2.5 },
			{ 0.07, 2.85 },
			{ 0.2, 3.1 },
			{ 0.43, 3.2 },
			{ 0.46, 3.25 },
			{ 0.8, 3.3 },
			{ 0.94, 3.4 },
			{ 0.97, 3.45 },
			{ 0.99, 2.9 },
			{ 1, 2.3 },
		},
		bottom = { { 0, 0.8 }, { 0.05, 0.5 }, { 0.95, 0.5 }, { 1, 0.9 } },
		cabin = { { 0.46, 0 }, { 0.59, 4.55 }, { 0.69, 4.6 }, { 0.93, 0 } },
		tumble = 0.65,
		pillars = {},
		rearPillar = 0.78,
		head = { from = 0.02, to = 0.07, inset = 0.3, width = 1.8 },
		tail = { from = 0.97, to = 0.99, inset = 0.2, width = 1.8 },
		tailBar = true,
		grille = "mesh",
		rims = "five",
		rimColor = GUNMETAL,
		seats = { 0.6, 0.72 },
		seatY = 1.35,
		doors = { 0.47, 0.73 },
		lip = true,
		exhausts = 2,
		diffuser = true,
	},
	-- An open two-seater: a windscreen, a cockpit let into the body, fairings behind the seats.
	roadster = {
		axles = { 0.19, 0.8 },
		top = {
			{ 0, 1.8 },
			{ 0.02, 2.4 },
			{ 0.07, 2.75 },
			{ 0.19, 3.0 },
			{ 0.42, 3.1 },
			{ 0.45, 3.15 },
			{ 0.45, 1.3 },
			{ 0.68, 1.3 },
			{ 0.68, 3.15 },
			{ 0.95, 3.2 },
			{ 0.98, 2.95 },
			{ 1, 2.3 },
		},
		bottom = { { 0, 0.75 }, { 0.05, 0.5 }, { 0.95, 0.5 }, { 1, 0.85 } },
		tumble = 0.7,
		pillars = {},
		head = { from = 0.02, to = 0.07, inset = 0.3, width = 1.6 },
		tail = { from = 0.95, to = 0.98, inset = 0.25, width = 1.4 },
		grille = "intake",
		rims = "ten",
		rimColor = SILVER,
		seats = { 0.575 },
		seatY = 1.7,
		doors = { 0.46, 0.67 },
		bed = { 0.45, 0.68, 1.3, 3.15 },
		screen = { 0.45, 0.53, 4.2 },
		hoops = true,
		exhausts = 2,
	},
	-- Mid-engined: a low nose, the cabin forward, the engine under glass behind it, a wing.
	supercar = {
		axles = { 0.21, 0.79 },
		top = {
			{ 0, 1.4 },
			{ 0.02, 1.9 },
			{ 0.07, 2.3 },
			{ 0.21, 3.05 },
			{ 0.3, 2.95 },
			{ 0.33, 2.98 },
			{ 0.84, 3.15 },
			{ 0.96, 3.25 },
			{ 0.985, 2.9 },
			{ 1, 2.2 },
		},
		bottom = { { 0, 0.75 }, { 0.04, 0.45 }, { 0.96, 0.45 }, { 1, 0.9 } },
		cabin = { { 0.33, 0 }, { 0.46, 4.45 }, { 0.56, 4.5 }, { 0.84, 0 } },
		tumble = 0.8,
		pillars = {},
		rearPillar = 0.62,
		head = { from = 0.02, to = 0.07, inset = 0.35, width = 1.7 },
		tail = { from = 0.96, to = 0.985, inset = 0.25, width = 2 },
		tailBar = true,
		grille = "intake",
		rims = "ten",
		rimColor = BLACK_RIM,
		seats = { 0.54 },
		seatY = 1.2,
		doors = { 0.34, 0.6 },
		wing = { 0.9, 0.985, 3.85 },
		intakes = { 0.6, 0.71 },
		exhausts = 2,
		diffuser = true,
	},
}

function CarBody.Style(kind: VehicleKind): Style
	return STYLES[kind.style or "sedan"] or STYLES.sedan
end

-- ---------------------------------------------------------------------------------------------
-- Lines.
-- ---------------------------------------------------------------------------------------------

-- The height of a line at `s`. At a step -- two points at the same share -- the value just right of
-- it is taken when `s` is nudged right, and just left when nudged left, which is how a slab either
-- side of a pickup's cab-back reads the right height.
local function lineAt(points: { Point }, s: number): number
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		if b[1] > a[1] and s >= a[1] and s <= b[1] then
			return a[2] + (b[2] - a[2]) * (s - a[1]) / (b[1] - a[1])
		end
	end
	if s <= points[1][1] then
		return points[1][2]
	end
	return points[#points][2]
end

local function shade(color: Color3, k: number): Color3
	return Color3.new(math.clamp(color.R * k, 0, 1), math.clamp(color.G * k, 0, 1), math.clamp(color.B * k, 0, 1))
end

-- ---------------------------------------------------------------------------------------------
-- Layout: where the hull, the wheels, the springs and the seat go.
-- ---------------------------------------------------------------------------------------------
export type Layout = {
	style: Style,
	length: number,
	width: number,
	-- The share of the length the hull's centre stands at: midway between the axles.
	midShare: number,
	hullSize: Vector3,
	hullDensity: number,
	-- Each corner weight's mass, and where the four stand, hull-local.
	ballastMass: number,
	ballast: { Vector3 },
	-- The hull centre's height above the ground at rest.
	hullY: number,
	-- The spring mounts' height, hull-local: where each raycast starts.
	mountY: number,
	axleFront: number,
	axleRear: number,
	track: number,
	wheelRadius: number,
	wheelWidth: number,
	-- The driver's seat part's centre, hull-local.
	seat: Vector3,
	-- The springs, in studs: how long each is at rest, how far it compresses, how far it drops.
	springRide: number,
	springBump: number,
	springDroop: number,
	-- Set on a car drawn from a model (shared/MeshCar), which brings its own corner weights.
	mesh: boolean?,
	ballastWeights: { number }?,
}

function CarBody.Layout(kind: VehicleKind): Layout
	local spec = CarSpec.Specs[kind.id]
	if kind.model ~= nil and spec ~= nil and MeshCar.Available(kind.model) then
		local layout = MeshCar.Layout(kind, spec)
		-- A modelled car is never drawn from a style; this only keeps the field honest.
		layout.style = STYLES.gt
		return layout
	end
	local style = CarBody.Style(kind)
	local length, width = kind.size.Z, kind.size.X
	local midShare = (style.axles[1] + style.axles[2]) / 2

	-- The hull's top is the lowest the body's top line comes between the axles, so it never shows
	-- through the paint; it is never shallower than a stud.
	local low = math.huge
	for _, point in style.top do
		if point[1] >= style.axles[1] and point[1] <= style.axles[2] then
			low = math.min(low, point[2])
		end
	end
	local hullTop = math.max(low, HULL_BOTTOM + 1)
	-- Nearly the car's whole length, not just the wheelbase: the hull's length is its resistance to
	-- pitching, and a short one bucked on its springs.
	local hullSize = Vector3.new(width - 0.8, hullTop - HULL_BOTTOM, length - 1.2)
	local mass = HULL_MASS_PER_STUD2 * hullSize.X * hullSize.Z
	local hullY = (HULL_BOTTOM + hullTop) / 2

	-- Settled on four springs, each takes a quarter of the weight: compression = m g / 4k. The
	-- mount stands the spring's rest length less that above the ground.
	local compression = mass * workspace.Gravity / (4 * VEHICLES.SuspensionStiffness)
	local restLength = VEHICLES.SuspensionLength + VEHICLES.WheelRadius
	local mountY = (restLength - compression) - hullY

	local track = width / 2 + TYRE_PROUD - TYRE_WIDTH / 2
	local seatZ = (style.seats[1] - midShare) * length
	local driverX = -(width / 2 - style.tumble) / 2
	return {
		style = style,
		length = length,
		width = width,
		midShare = midShare,
		hullSize = hullSize,
		hullDensity = mass * (1 - BALLAST_SHARE) / (hullSize.X * hullSize.Y * hullSize.Z),
		ballastMass = mass * BALLAST_SHARE / 4,
		ballast = {
			Vector3.new(-(width / 2 - 0.6), 0, -(length / 2 - 1.5)),
			Vector3.new(width / 2 - 0.6, 0, -(length / 2 - 1.5)),
			Vector3.new(-(width / 2 - 0.6), 0, length / 2 - 1.5),
			Vector3.new(width / 2 - 0.6, 0, length / 2 - 1.5),
		},
		hullY = hullY,
		mountY = mountY,
		axleFront = (style.axles[1] - midShare) * length,
		axleRear = (style.axles[2] - midShare) * length,
		track = track,
		wheelRadius = VEHICLES.WheelRadius,
		wheelWidth = TYRE_WIDTH,
		seat = Vector3.new(driverX, style.seatY - 0.5 - hullY, seatZ),
		springRide = VEHICLES.SuspensionLength - compression,
		springBump = 0.6,
		springDroop = 0.5,
	}
end

-- ---------------------------------------------------------------------------------------------
-- The builder.
-- ---------------------------------------------------------------------------------------------
export type Wheel = {
	spin: BasePart, -- the tyre: everything that turns with the road is welded to it
	knuckle: BasePart, -- the brake disc: the calliper is welded to it; steers, never spins
	front: boolean,
	side: number, -- -1 left, 1 right
	rest: Vector3, -- the wheel centre at rest, hull-local
}

export type Built = {
	model: Model,
	hull: Part,
	layout: Layout,
	wheels: { Wheel },
	-- Every part and the part it rides on, for Weld: the hull for the body, a wheel's root for
	-- the rest of that wheel.
	riders: { { BasePart } },
	headlights: { BasePart },
	brakeLights: { BasePart },
	reverseLights: { BasePart },
	-- A modelled car's own steering wheel, for the wheels to turn with the driver's hands.
	steeringWheel: BasePart?,
	-- A modelled car's headlamp lenses, which glow when its beams are on.
	lenses: { BasePart }?,
	mesh: boolean?,
}

type Ctx = {
	model: Model,
	base: CFrame,
	layout: Layout,
	paint: Color3,
	rims: Color3?,
	accent: Color3,
	riders: { { BasePart } },
	hull: Part,
}

local function style_(part: BasePart, color: Color3, material: Enum.Material)
	part.Color = color
	part.Material = material
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

-- A part at `localCF` (hull-local), riding on `on` (the hull unless given).
local function add(ctx: Ctx, className: string, name: string, size: Vector3, localCF: CFrame, color: Color3, material: Enum.Material, on: BasePart?): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	part.Size = size
	part.CFrame = ctx.base * localCF
	style_(part, color, material)
	if material == Enum.Material.Glass then
		part.Transparency = GLASS_TRANSPARENCY
		part.Reflectance = 0.2
		part.CastShadow = false
	elseif material == Enum.Material.Metal then
		part.Reflectance = 0.25
	end
	part.Parent = ctx.model
	table.insert(ctx.riders, { part, on or ctx.hull })
	return part
end

-- Paint gets a lacquer: SmoothPlastic with a little reflectance reads as a finish, not a toy.
local function paint(part: BasePart): BasePart
	part.Reflectance = 0.08
	return part
end

-- Hull-local position of a point drawn at `x` across, `y` above the ground, `s` along.
local function at(ctx: Ctx, x: number, y: number, s: number): Vector3
	local layout = ctx.layout
	return Vector3.new(x, y - layout.hullY, (s - layout.midShare) * layout.length)
end

local function zOf(ctx: Ctx, s: number): number
	return (s - ctx.layout.midShare) * ctx.layout.length
end

-- A box between two corners, hull-local, drawn in ground heights and shares.
local function block(ctx: Ctx, name: string, x0: number, x1: number, y0: number, y1: number, s0: number, s1: number, color: Color3, material: Enum.Material, on: BasePart?): BasePart?
	local z0, z1 = zOf(ctx, s0), zOf(ctx, s1)
	if math.abs(x1 - x0) < 0.01 or math.abs(y1 - y0) < 0.01 or math.abs(z1 - z0) < 0.01 then
		return nil
	end
	local centre = Vector3.new((x0 + x1) / 2, (y0 + y1) / 2 - ctx.layout.hullY, (z0 + z1) / 2)
	return add(ctx, "Part", name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)), CFrame.new(centre), color, material, on)
end

-- A vertical slab from `s0` to `s1`, `x0..x1` across, whose top runs from `t0` to `t1` and whose
-- underside runs from `b0` to `b1`: a block, a wedge over it where the top slopes, and an upturned
-- wedge under it where the underside does.
local function slab(ctx: Ctx, name: string, x0: number, x1: number, s0: number, s1: number, t0: number, t1: number, b0: number, b1: number, color: Color3, material: Enum.Material): { BasePart }
	local parts: { BasePart } = {}
	local z0, z1 = zOf(ctx, s0), zOf(ctx, s1)
	local length = z1 - z0
	if length < 0.01 then
		return parts
	end
	local width = x1 - x0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local hullY = ctx.layout.hullY
	local lowTop, highTop = math.min(t0, t1), math.max(t0, t1)
	local lowBottom, highBottom = math.min(b0, b1), math.max(b0, b1)
	if lowTop - highBottom > 0.01 then
		local part = block(ctx, name, x0, x1, highBottom, lowTop, s0, s1, color, material)
		if part then
			table.insert(parts, part)
		end
	end
	if highTop - lowTop > 0.01 then
		-- A wedge's slope climbs toward its local +Z; turned half round when the line falls.
		local turn = if t1 >= t0 then CFrame.new() else CFrame.Angles(0, math.pi, 0)
		local cf = CFrame.new(cx, (lowTop + highTop) / 2 - hullY, cz) * turn
		table.insert(parts, add(ctx, "WedgePart", name, Vector3.new(width, highTop - lowTop, length), cf, color, material))
	end
	if highBottom - lowBottom > 0.01 then
		-- Upside down, the wedge's point is at +Z: the underside falls toward +Z. Turned half round
		-- as well when it falls toward -Z instead.
		local flip = CFrame.Angles(0, 0, math.pi)
		local turn = if b1 <= b0 then flip else CFrame.Angles(0, math.pi, 0) * flip
		local cf = CFrame.new(cx, (lowBottom + highBottom) / 2 - hullY, cz) * turn
		table.insert(parts, add(ctx, "WedgePart", name, Vector3.new(width, highBottom - lowBottom, length), cf, color, material))
	end
	return parts
end

-- A thin panel laid along the straight line from (s0, y0) to (s1, y1) -- on a bonnet, a screen, a
-- roof -- `x0..x1` across, `lift` off the line, `thickness` thick.
local function along(ctx: Ctx, name: string, x0: number, x1: number, s0: number, y0: number, s1: number, y1: number, lift: number, thickness: number, color: Color3, material: Enum.Material, on: BasePart?): BasePart?
	local p0 = at(ctx, 0, y0, s0)
	local p1 = at(ctx, 0, y1, s1)
	local span = p1 - p0
	if span.Magnitude < 0.02 then
		return nil
	end
	local mid = (p0 + p1) / 2
	local frame = CFrame.lookAt(mid, p1)
	local centre = mid + Vector3.new((x0 + x1) / 2, 0, 0) + frame.UpVector * (lift + thickness / 2)
	return add(ctx, "Part", name, Vector3.new(math.abs(x1 - x0), thickness, span.Magnitude), CFrame.lookAt(centre, centre + span), color, material, on)
end

-- A cylinder whose axis runs across the car, centred at (x, y, s): wheels, arches.
local function acrossDisc(ctx: Ctx, name: string, x: number, y: number, s: number, thickness: number, diameter: number, color: Color3, material: Enum.Material, on: BasePart?): BasePart
	local part = add(ctx, "Part", name, Vector3.new(thickness, diameter, diameter), CFrame.new(at(ctx, x, y, s)), color, material, on)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- A cylinder whose axis runs along the car: exhaust tips, the roadster's fairings.
local function lengthwise(ctx: Ctx, name: string, x: number, y: number, s0: number, s1: number, diameter: number, color: Color3, material: Enum.Material): BasePart
	local z0, z1 = zOf(ctx, s0), zOf(ctx, s1)
	local part = add(
		ctx,
		"Part",
		name,
		Vector3.new(math.abs(z1 - z0), diameter, diameter),
		CFrame.new(x, y - ctx.layout.hullY, (z0 + z1) / 2) * CFrame.Angles(0, math.rad(90), 0),
		color,
		material
	)
	part.Shape = Enum.PartType.Cylinder
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

-- ---------------------------------------------------------------------------------------------
-- The pieces of a car.
-- ---------------------------------------------------------------------------------------------

local function breakpoints(style: Style): { number }
	local seen: { [number]: boolean } = {}
	local list: { number } = {}
	for _, line in { style.top, style.bottom } do
		for _, point in line do
			if not seen[point[1]] then
				seen[point[1]] = true
				table.insert(list, point[1])
			end
		end
	end
	table.sort(list)
	return list
end

local function lowerBody(ctx: Ctx)
	local style = ctx.layout.style
	local half = ctx.layout.width / 2
	local marks = breakpoints(style)
	for i = 1, #marks - 1 do
		local s0, s1 = marks[i], marks[i + 1]
		local t0, t1 = lineAt(style.top, s0 + EPS), lineAt(style.top, s1 - EPS)
		local b0, b1 = lineAt(style.bottom, s0 + EPS), lineAt(style.bottom, s1 - EPS)
		-- The nose and tail slabs a little narrower than the flanks: a bumper tucks in at its corners.
		local inset = if i == 1 or i == #marks - 1 then 0.18 else 0
		for _, part in slab(ctx, "Body", -half + inset, half - inset, s0, s1, t0, t1, b0, b1, ctx.paint, Enum.Material.SmoothPlastic) do
			paint(part)
		end
	end
end

local function openBox(ctx: Ctx)
	local style = ctx.layout.style
	local bed = style.bed
	if bed == nil then
		return
	end
	local half = ctx.layout.width / 2
	local s0, s1, floor, top = bed[1], bed[2], bed[3], bed[4]
	local wall = 0.28
	for _, side in { -1, 1 } do
		local x0, x1 = side * (half - wall), side * half
		paint(block(ctx, "BedSide", math.min(x0, x1), math.max(x0, x1), floor, top, s0, s1, ctx.paint, Enum.Material.SmoothPlastic) :: BasePart)
		-- A dark cap along the top of the wall.
		block(ctx, "BedRail", math.min(x0, x1), math.max(x0, x1), top, top + 0.08, s0, s1, TRIM, Enum.Material.SmoothPlastic)
	end
	if s1 >= 0.999 then
		-- A pickup's tailgate across the back.
		local gate = wall / ctx.layout.length
		paint(block(ctx, "Tailgate", -half + wall, half - wall, floor, top, s1 - gate, s1, ctx.paint, Enum.Material.SmoothPlastic) :: BasePart)
		block(ctx, "BedLiner", -half + wall, half - wall, floor, floor + 0.06, s0, s1 - gate, TRIM, Enum.Material.SmoothPlastic)
	else
		-- A cockpit: carpet on its floor.
		block(ctx, "Carpet", -half + wall, half - wall, floor, floor + 0.06, s0, s1, INTERIOR, Enum.Material.Fabric)
	end
end

local function arches(ctx: Ctx)
	local layout = ctx.layout
	local half = layout.width / 2
	local diameter = (layout.wheelRadius + ARCH_MARGIN) * 2
	for _, s in layout.style.axles do
		for _, side in { -1, 1 } do
			-- A thin dark disc on the body side, bigger than the tyre: the ring of it the tyre does
			-- not cover reads as the opening in the wing the wheel sits in.
			acrossDisc(ctx, "Arch", side * (half + 0.01), layout.wheelRadius, s, 0.04, diameter, TRIM, Enum.Material.SmoothPlastic)
		end
	end
end

local function greenhouse(ctx: Ctx)
	local layout = ctx.layout
	local style = layout.style
	local cabin = style.cabin
	if cabin == nil then
		return
	end
	-- The roof line, with its feet stood on the body's top line.
	local line: { Point } = {}
	for i, point in cabin do
		local y = point[2]
		if i == 1 then
			y = lineAt(style.top, point[1] + EPS)
		elseif i == #cabin then
			y = lineAt(style.top, point[1] - EPS)
		end
		table.insert(line, { point[1], y })
	end
	local halfCab = layout.width / 2 - style.tumble
	local glassT = 0.12

	-- The sides: glass cut to the roof line over the belt, paint aft of the last window.
	for i = 1, #line - 1 do
		local s0, s1 = line[i][1], line[i + 1][1]
		local cuts = { s0, s1 }
		local rear = style.rearPillar
		if rear and rear > s0 and rear < s1 then
			cuts = { s0, rear, s1 }
		end
		for j = 1, #cuts - 1 do
			local a, b = cuts[j], cuts[j + 1]
			local topA = lineAt(line, a + EPS)
			local topB = lineAt(line, b - EPS)
			local beltA, beltB = lineAt(style.top, a + EPS), lineAt(style.top, b - EPS)
			local isGlass = rear == nil or a < rear
			for _, side in { -1, 1 } do
				local x0, x1 = side * (halfCab - glassT), side * halfCab
				local parts = slab(
					ctx,
					if isGlass then "SideGlass" else "Pillar",
					math.min(x0, x1),
					math.max(x0, x1),
					a,
					b,
					topA,
					topB,
					beltA,
					beltB,
					if isGlass then GLASS else ctx.paint,
					if isGlass then Enum.Material.Glass else Enum.Material.SmoothPlastic
				)
				if not isGlass then
					for _, part in parts do
						paint(part)
					end
				end
			end
		end
	end

	-- The windscreen, the roof, the rear screen, laid along the roof line.
	for i = 1, #line - 1 do
		local a, b = line[i], line[i + 1]
		local first, last = i == 1, i == #line - 1
		if first or last then
			-- The rear screen sits between broad C-pillars, the windscreen between slim A-pillars.
			local pillarWidth = if last then 0.45 else 0.26
			local inner = halfCab - pillarWidth + 0.02
			along(ctx, if first then "Windscreen" else "RearScreen", -inner, inner, a[1], a[2], b[1], b[2], -0.05, 0.1, GLASS, Enum.Material.Glass)
			-- Pillars along the screen's edges, in the paint.
			for _, side in { -1, 1 } do
				local x0 = side * (halfCab - pillarWidth)
				local x1 = side * (halfCab + 0.02)
				local pillar = along(ctx, "ScreenPillar", math.min(x0, x1), math.max(x0, x1), a[1], a[2], b[1], b[2], -0.04, 0.14, ctx.paint, Enum.Material.SmoothPlastic)
				if pillar then
					paint(pillar)
				end
			end
		else
			local roof = along(ctx, "Roof", -halfCab - 0.06, halfCab + 0.06, a[1], a[2], b[1], b[2], -0.1, 0.22, ctx.paint, Enum.Material.SmoothPlastic)
			if roof then
				paint(roof)
			end
			if style.rails then
				for _, side in { -1, 1 } do
					local x = side * (halfCab - 0.35)
					along(ctx, "RoofRail", x - 0.09, x + 0.09, a[1] + 0.02, a[2], b[1] - 0.02, b[2], 0.3, 0.12, CHROME, Enum.Material.Metal)
					for _, s in { a[1] + 0.03, b[1] - 0.03 } do
						block(ctx, "RailFoot", x - 0.09, x + 0.09, lineAt(line, s) + 0.1, lineAt(line, s) + 0.32, s - 0.006, s + 0.006, TRIM, Enum.Material.SmoothPlastic)
					end
				end
			end
		end
	end

	-- Pillars between windows, and a black frame along the top of the glass.
	for _, s in style.pillars do
		local top = lineAt(line, s)
		for _, side in { -1, 1 } do
			local x0, x1 = side * (halfCab - glassT - 0.03), side * (halfCab + 0.03)
			block(ctx, "BPillar", math.min(x0, x1), math.max(x0, x1), lineAt(style.top, s), top, s - 0.012, s + 0.012, TRIM, Enum.Material.SmoothPlastic)
		end
	end
end

-- Seats and the dash, where the glass shows them; whole, in an open car.
local function interior(ctx: Ctx)
	local layout = ctx.layout
	local style = layout.style
	local halfCab = layout.width / 2 - style.tumble
	local open = style.cabin == nil
	local seatW = math.min(1.6, halfCab - 0.3)
	for row, s in style.seats do
		local xs = if row == 1 then { -halfCab / 2, halfCab / 2 } else { 0 }
		for _, x in xs do
			local w = if row == 1 then seatW else halfCab * 2 - 0.9
			local backFrom = if open then style.seatY - 0.1 else lineAt(style.top, s) - 0.05
			local backS = s + 0.5 / layout.length
			block(ctx, "SeatBack", x - w / 2, x + w / 2, backFrom, style.seatY + 2.3, backS, backS + 0.4 / layout.length, INTERIOR, Enum.Material.Leather)
			if row == 1 then
				block(ctx, "Headrest", x - 0.45, x + 0.45, style.seatY + 2.3, style.seatY + 2.85, backS + 0.05 / layout.length, backS + 0.35 / layout.length, INTERIOR, Enum.Material.Leather)
			end
			if open then
				block(ctx, "SeatBase", x - w / 2, x + w / 2, style.seatY - 0.45, style.seatY, s - 1.1 / layout.length, backS, INTERIOR, Enum.Material.Leather)
			end
		end
	end
	-- The dash across the foot of the windscreen, and a wheel in front of the driver.
	local foot = if style.cabin then (style.cabin :: { Point })[1][1] else (style.screen :: { number })[1]
	local dashY = lineAt(style.top, foot - EPS)
	-- Set a tenth of a stud behind the foot of the screen, off the plane the body's slabs meet on.
	block(ctx, "Dash", -halfCab + 0.12, halfCab - 0.12, dashY - 0.4, dashY + 0.35, foot + 0.1 / layout.length, foot + 1.2 / layout.length, INTERIOR, Enum.Material.SmoothPlastic)
	local driverX = -halfCab / 2
	local wheelS = style.seats[1] - 1.45 / layout.length
	local centre = at(ctx, driverX, math.max(style.seatY + 1.35, lineAt(style.top, wheelS) + 0.4), wheelS)
	local column = Vector3.new(0, -0.45, -1).Unit
	local wheel = add(ctx, "Part", "SteeringWheel", Vector3.new(0.14, 1.15, 1.15), CFrame.lookAt(centre, centre + column) * CFrame.Angles(0, math.rad(90), 0), INTERIOR, Enum.Material.SmoothPlastic)
	wheel.Shape = Enum.PartType.Cylinder
end

local function frontEnd(ctx: Ctx, kind: VehicleKind, built: Built)
	local layout = ctx.layout
	local style = layout.style
	local half = layout.width / 2
	local noseTop, noseBottom = lineAt(style.top, EPS), lineAt(style.bottom, EPS)
	local faceZ = zOf(ctx, 0)
	local faceHeight = noseTop - noseBottom
	local function onFace(name: string, x0: number, x1: number, y0: number, y1: number, depth: number, color: Color3, material: Enum.Material): BasePart
		local size = Vector3.new(x1 - x0, y1 - y0, depth)
		return add(ctx, "Part", name, size, CFrame.new((x0 + x1) / 2, (y0 + y1) / 2 - layout.hullY, faceZ - depth / 2 + 0.02), color, material)
	end

	-- Lower intake, across the bottom of the bumper.
	local intakeW = layout.width * 0.62
	onFace("Intake", -intakeW / 2, intakeW / 2, noseBottom + 0.15, noseBottom + math.min(0.55, faceHeight * 0.35), 0.1, TRIM, Enum.Material.SmoothPlastic)
	local grilleTop = noseTop - 0.1
	local grilleBottom = noseBottom + math.min(0.7, faceHeight * 0.45)
	if style.grille == "intake" then
		-- A mid-engined car or an open one has no radiator up front, only a splitter and a mouth.
		onFace("Splitter", -half + 0.3, half - 0.3, noseBottom - 0.05, noseBottom + 0.08, 0.35, TRIM, Enum.Material.SmoothPlastic)
		onFace("Mouth", -layout.width * 0.2, layout.width * 0.2, noseBottom + 0.2, noseTop - 0.08, 0.08, TRIM, Enum.Material.SmoothPlastic)
	elseif grilleTop - grilleBottom > 0.2 then
		local gw = if style.grille == "frame" then layout.width * 0.5 else layout.width * 0.36
		onFace("Grille", -gw / 2, gw / 2, grilleBottom, grilleTop, 0.1, TRIM, Enum.Material.SmoothPlastic)
		if style.grille == "bars" or style.grille == "frame" then
			local bars = 3
			for i = 1, bars do
				local y = grilleBottom + (grilleTop - grilleBottom) * i / (bars + 1)
				onFace("GrilleBar", -gw / 2 + 0.1, gw / 2 - 0.1, y - 0.05, y + 0.05, 0.14, CHROME, Enum.Material.Metal)
			end
		end
		if style.grille == "frame" then
			onFace("GrilleFrame", -gw / 2 - 0.1, gw / 2 + 0.1, grilleTop, grilleTop + 0.1, 0.16, CHROME, Enum.Material.Metal)
			onFace("GrilleFrame", -gw / 2 - 0.1, gw / 2 + 0.1, grilleBottom - 0.1, grilleBottom, 0.16, CHROME, Enum.Material.Metal)
			onFace("GrilleFrame", -gw / 2 - 0.1, -gw / 2, grilleBottom, grilleTop, 0.16, CHROME, Enum.Material.Metal)
			onFace("GrilleFrame", gw / 2, gw / 2 + 0.1, grilleBottom, grilleTop, 0.16, CHROME, Enum.Material.Metal)
		elseif style.grille == "mesh" then
			onFace("GrilleSurround", -gw / 2 - 0.08, gw / 2 + 0.08, grilleBottom - 0.08, grilleBottom, 0.14, CHROME, Enum.Material.Metal)
		end
		-- The maker's name on the grille, in the brand's own letters -- nobody else's badge.
		if kind.brand then
			local badge = onFace("Badge", -0.7, 0.7, (grilleBottom + grilleTop) / 2 - 0.16, (grilleBottom + grilleTop) / 2 + 0.16, 0.18, TRIM, Enum.Material.SmoothPlastic)
			badge.Transparency = 1
			label(badge, Enum.NormalId.Front, string.upper(kind.brand), CHROME, 60)
		end
	end
	-- A plate under the grille.
	if faceHeight > 0.9 then
		local py = noseBottom + faceHeight * 0.3
		local plate = onFace("Plate", -0.8, 0.8, py - 0.2, py + 0.2, 0.14, PLATE, Enum.Material.SmoothPlastic)
		label(plate, Enum.NormalId.Front, "MERIDIAN", TRIM, 50)
	end
	-- Headlamps.
	local head = style.head
	local y0, y1 = lineAt(style.top, head.from + EPS), lineAt(style.top, head.to - EPS)
	for _, side in { -1, 1 } do
		local outer = side * (half - head.inset)
		local inner = side * (half - head.inset - head.width)
		local x0, x1 = math.min(outer, inner), math.max(outer, inner)
		local lamp = along(ctx, "Headlight", x0, x1, head.from, y0, head.to, y1, -0.02, 0.1, LAMP_GLASS, Enum.Material.Glass)
		if lamp then
			lamp.Transparency = 0
			lamp.Reflectance = 0.35
		end
		-- The running light: a line of light across the lamp's lower edge.
		local share = 0.28
		along(ctx, "DRL", x0 + 0.1, x1 - 0.1, head.from, y0, head.from + (head.to - head.from) * share, y0 + (y1 - y0) * share, 0.08, 0.04, DRL, Enum.Material.Neon)
		-- Where the beam comes from, square to the road whatever the lamp's slope: an invisible
		-- mount facing forward, which the chassis hangs a SpotLight on while the car is driven.
		local s = (head.from + head.to) / 2
		local aim = add(ctx, "Part", "HeadlightAim", Vector3.new(0.2, 0.2, 0.2), CFrame.new(at(ctx, (x0 + x1) / 2, lineAt(style.top, s) - 0.1, s)), DRL, Enum.Material.SmoothPlastic)
		aim.Transparency = 1
		table.insert(built.headlights, aim)
	end
end

local function rearEnd(ctx: Ctx, kind: VehicleKind, built: Built)
	local layout = ctx.layout
	local style = layout.style
	local half = layout.width / 2
	local tailTop, tailBottom = lineAt(style.top, 1 - EPS), lineAt(style.bottom, 1 - EPS)
	local faceZ = zOf(ctx, 1)
	-- `out` stands a part further off the face, for one laid over another.
	local function onFace(name: string, x0: number, x1: number, y0: number, y1: number, depth: number, color: Color3, material: Enum.Material, out: number?): BasePart
		local z = faceZ + (out or 0) + depth / 2 - 0.02
		return add(ctx, "Part", name, Vector3.new(x1 - x0, y1 - y0, depth), CFrame.new((x0 + x1) / 2, (y0 + y1) / 2 - layout.hullY, z), color, material)
	end
	local faceHeight = tailTop - tailBottom

	-- Tail lamps: a red lens, and in it the lamp that brightens under braking.
	local tail = style.tail
	local function lamp(x0: number, x1: number)
		if tail.face then
			onFace("TailLight", x0, x1, tail.from, tail.to, 0.08, TAIL_GLASS, Enum.Material.Glass).Transparency = 0
			local brake = onFace("BrakeLight", x0 + 0.08, x1 - 0.08, tail.from + 0.15, tail.to - 0.15, 0.06, CarBody.TailColor, Enum.Material.Neon, 0.06)
			table.insert(built.brakeLights, brake)
		else
			local y0, y1 = lineAt(style.top, tail.from + EPS), lineAt(style.top, tail.to - EPS)
			local lens = along(ctx, "TailLight", x0, x1, tail.from, y0, tail.to, y1, -0.02, 0.1, TAIL_GLASS, Enum.Material.Glass)
			if lens then
				lens.Transparency = 0
			end
			local brake = along(ctx, "BrakeLight", x0 + 0.1, x1 - 0.1, tail.from, y0, tail.to, y1, 0.06, 0.05, CarBody.TailColor, Enum.Material.Neon)
			if brake then
				table.insert(built.brakeLights, brake)
			end
		end
	end
	if style.tailBar and not tail.face then
		lamp(-half + tail.inset, half - tail.inset)
	else
		for _, side in { -1, 1 } do
			local outer = side * (half - tail.inset)
			local inner = side * (half - tail.inset - tail.width)
			lamp(math.min(outer, inner), math.max(outer, inner))
		end
	end

	-- The rear face: a plate, reversing lamps, the badge, a diffuser, the exhausts.
	local py = tailBottom + faceHeight * 0.55
	if faceHeight > 0.9 then
		local plate = onFace("Plate", -0.8, 0.8, py - 0.2, py + 0.2, 0.08, PLATE, Enum.Material.SmoothPlastic)
		label(plate, Enum.NormalId.Back, "MERIDIAN", TRIM, 50)
	end
	for _, side in { -1, 1 } do
		local x = side * (half - 0.9)
		local reverse = onFace("ReverseLight", x - 0.25, x + 0.25, tailBottom + 0.3, tailBottom + 0.48, 0.06, LAMP_GLASS, Enum.Material.SmoothPlastic)
		table.insert(built.reverseLights, reverse)
	end
	if kind.brand and faceHeight > 0.9 and py + 0.62 < tailTop then
		local badge = onFace("Badge", -1.2, 1.2, py + 0.3, py + 0.62, 0.1, TRIM, Enum.Material.SmoothPlastic)
		badge.Transparency = 1
		label(badge, Enum.NormalId.Back, string.upper(kind.brand), CHROME, 60)
	end
	if style.diffuser then
		onFace("Diffuser", -half + 0.6, half - 0.6, tailBottom - 0.05, tailBottom + 0.3, 0.3, TRIM, Enum.Material.SmoothPlastic)
		for i = -2, 2 do
			onFace("DiffuserFin", i * 0.6 - 0.04, i * 0.6 + 0.04, tailBottom - 0.05, tailBottom + 0.3, 0.55, TRIM, Enum.Material.SmoothPlastic)
		end
	end
	local tips = style.exhausts
	for i = 1, tips do
		local x = if tips == 1 then half - 1.4 else (if i == 1 then -1 else 1) * (half - 1.4)
		lengthwise(ctx, "Exhaust", x, tailBottom + 0.25, 1 - 0.2 / layout.length, 1 + 0.12 / layout.length, 0.4, CHROME, Enum.Material.Metal)
	end
	-- A lip on the tail of a GT; a wing on struts on a supercar.
	if style.lip then
		local s0, s1 = 0.95, 0.975
		local lip = along(ctx, "Lip", -half + 0.5, half - 0.5, s0, lineAt(style.top, s0), s1, lineAt(style.top, s1) + 0.25, 0.02, 0.1, ctx.paint, Enum.Material.SmoothPlastic)
		if lip then
			paint(lip)
		end
	end
	local wing = style.wing
	if wing then
		block(ctx, "Wing", -half + 0.4, half - 0.4, wing[3], wing[3] + 0.12, wing[1], wing[2], TRIM, Enum.Material.SmoothPlastic)
		for _, side in { -1, 1 } do
			local x = side * (half - 1.4)
			local foot = lineAt(style.top, (wing[1] + wing[2]) / 2)
			block(ctx, "WingStrut", x - 0.06, x + 0.06, foot, wing[3], (wing[1] + wing[2]) / 2 - 0.01, (wing[1] + wing[2]) / 2 + 0.02, TRIM, Enum.Material.SmoothPlastic)
			block(ctx, "WingPlate", side * (half - 0.4) - 0.04, side * (half - 0.4) + 0.04, wing[3] - 0.25, wing[3] + 0.3, wing[1], wing[2], TRIM, Enum.Material.SmoothPlastic)
		end
	end
end

local function flanks(ctx: Ctx)
	local layout = ctx.layout
	local style = layout.style
	local half = layout.width / 2
	local sill = lineAt(style.bottom, 0.5)
	local axF, axR = style.axles[1], style.axles[2]
	local archShare = (layout.wheelRadius + ARCH_MARGIN + 0.1) / layout.length
	for _, side in { -1, 1 } do
		local function skin(name: string, y0: number, y1: number, s0: number, s1: number, proud: number, color: Color3, material: Enum.Material): BasePart?
			local x0, x1 = side * half, side * (half + proud)
			return block(ctx, name, math.min(x0, x1), math.max(x0, x1), y0, y1, s0, s1, color, material)
		end
		-- The sill, between the arches.
		skin("SideSkirt", sill, sill + 0.28, axF + archShare, axR - archShare, 0.04, TRIM, Enum.Material.SmoothPlastic)
		-- A crease down the flank, a shade darker than the paint: what makes a slab read as pressed metal.
		local creaseY = sill + (lineAt(style.top, 0.5) - sill) * 0.62
		local crease = skin("Crease", creaseY - 0.035, creaseY + 0.035, axF + archShare, axR - archShare * 0.6, 0.02, shade(ctx.paint, 0.78), Enum.Material.SmoothPlastic)
		if crease then
			paint(crease)
		end
		-- Door shuts, and a handle ahead of each rear edge.
		for i, s in style.doors do
			local top = lineAt(style.top, s) - 0.06
			skin("DoorLine", sill + 0.3, top, s - 0.0015, s + 0.0015, 0.015, TRIM, Enum.Material.SmoothPlastic)
			if i > 1 then
				local hy = top - 0.45
				skin("Handle", hy - 0.08, hy + 0.08, s - 0.05, s - 0.022, 0.05, CHROME, Enum.Material.Metal)
			end
		end
		-- Side intakes on a mid-engined car.
		local intake = style.intakes
		if intake then
			local belt = lineAt(style.top, intake[1])
			skin("SideIntake", sill + 0.6, belt - 0.25, intake[1], intake[2], 0.03, TRIM, Enum.Material.SmoothPlastic)
		end
		-- The mirror, on the door at the foot of the screen.
		local foot = if style.cabin then (style.cabin :: { Point })[1][1] else (style.screen :: { number })[1]
		local my = lineAt(style.top, foot + 0.03) + 0.45
		local ms = foot + 0.035
		local mx0, mx1 = side * (half - style.tumble + 0.05), side * (half + 0.3)
		paint(block(ctx, "Mirror", math.min(mx0, mx1), math.max(mx0, mx1), my - 0.18, my + 0.2, ms, ms + 0.4 / layout.length, ctx.paint, Enum.Material.SmoothPlastic) :: BasePart)
		local gx0, gx1 = side * (half + 0.05), side * (half + 0.28)
		block(ctx, "MirrorGlass", math.min(gx0, gx1), math.max(gx0, gx1), my - 0.12, my + 0.14, ms + 0.4 / layout.length, ms + 0.43 / layout.length, TRIM, Enum.Material.SmoothPlastic)
	end
end

local function openCar(ctx: Ctx)
	local layout = ctx.layout
	local style = layout.style
	local screen = style.screen
	if screen == nil then
		return
	end
	local half = layout.width / 2 - style.tumble
	local s0, s1, topY = screen[1], screen[2], screen[3]
	local footY = lineAt(style.top, s0 - EPS)
	along(ctx, "Windscreen", -half + 0.12, half - 0.12, s0, footY, s1, topY, -0.05, 0.1, GLASS, Enum.Material.Glass)
	for _, side in { -1, 1 } do
		local x0, x1 = side * (half - 0.14), side * half
		along(ctx, "ScreenFrame", math.min(x0, x1), math.max(x0, x1), s0, footY, s1, topY, -0.05, 0.14, TRIM, Enum.Material.SmoothPlastic)
	end
	along(ctx, "ScreenFrame", -half, half, s1 - 0.004, topY - 0.08, s1, topY, -0.02, 0.12, TRIM, Enum.Material.SmoothPlastic)
	if style.hoops then
		-- A fairing behind each seat, faired into the deck.
		local bed = style.bed :: { number }
		local deck = lineAt(style.top, bed[2] + 0.02)
		for _, x in { -half / 2, half / 2 } do
			paint(lengthwise(ctx, "Fairing", x, deck, bed[2], bed[2] + 2.4 / layout.length, 1.1, ctx.paint, Enum.Material.SmoothPlastic))
		end
	end
end

-- One wheel: tyre, rim lip, dark barrel, spokes, centre cap -- all turning with the tyre -- and a
-- brake disc with its calliper, which steer but do not spin.
local function wheel(ctx: Ctx, front: boolean, side: number): Wheel
	local layout = ctx.layout
	local style = layout.style
	local r = layout.wheelRadius
	local w = layout.wheelWidth
	local z = if front then layout.axleFront else layout.axleRear
	local rest = Vector3.new(side * layout.track, r - layout.hullY, z)
	-- Built facing out along +X, then turned for the left-hand side.
	local face = CFrame.new(rest) * (if side < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new())
	local function disc(name: string, x0: number, x1: number, diameter: number, color: Color3, material: Enum.Material, on: BasePart?): BasePart
		local part = add(ctx, "Part", name, Vector3.new(x1 - x0, diameter, diameter), face * CFrame.new((x0 + x1) / 2, 0, 0), color, material, on)
		part.Shape = Enum.PartType.Cylinder
		return part
	end
	local tyre = disc("Tyre", -w / 2, w / 2, r * 2, RUBBER, Enum.Material.Rubber)
	local outer = w / 2
	local knuckle = disc("BrakeDisc", outer - 0.02, outer + 0.03, r * 1.02, DISC, Enum.Material.Metal)
	knuckle.Transparency = 1
	local rimColor = ctx.rims or style.rimColor
	disc("RimLip", outer, outer + 0.04, r * 1.44, rimColor, Enum.Material.Metal, tyre)
	disc("Barrel", outer + 0.04, outer + 0.06, r * 1.32, TRIM, Enum.Material.SmoothPlastic, tyre)
	disc("Rotor", outer + 0.06, outer + 0.08, r * 0.98, DISC, Enum.Material.Metal, knuckle)
	-- The calliper, clasping the disc's trailing top edge.
	local caliper = add(ctx, "Part", "Caliper", Vector3.new(0.12, 0.34, 0.62), face * CFrame.new(outer + 0.12, r * 0.36, 0.22), CALIPER, Enum.Material.SmoothPlastic, knuckle)
	caliper.Reflectance = 0.1
	local spokes = if style.rims == "ten" then 10 elseif style.rims == "steel" then 6 else 5
	local spokeW = if style.rims == "ten" then 0.12 elseif style.rims == "steel" then 0.22 else 0.22
	for i = 0, spokes - 1 do
		local angle = i / spokes * math.pi * 2
		local reach = r * 0.64
		local twin = style.rims == "twin"
		for _, offset in (if twin then { -0.07, 0.07 } else { 0 }) do
			local cf = face * CFrame.Angles(angle + offset, 0, 0) * CFrame.new(outer + 0.16, reach / 2 + 0.12, 0)
			add(ctx, "Part", "Spoke", Vector3.new(0.08, reach, if twin then 0.1 else spokeW), cf, rimColor, Enum.Material.Metal, tyre)
		end
	end
	disc("Cap", outer + 0.12, outer + 0.24, r * 0.34, rimColor, Enum.Material.Metal, tyre)
	return { spin = tyre, knuckle = knuckle, front = front, side = side, rest = rest }
end

-- ---------------------------------------------------------------------------------------------
-- Build.
-- ---------------------------------------------------------------------------------------------

--[[
	Builds `kind` with its hull's centre at `cframe`, painted `paintColor` (its own colour unless
	given). Nothing is anchored and nothing is welded: the caller does one or the other -- Anchor
	for a car that is only looked at, Weld for one that drives.
]]
function CarBody.Build(kind: VehicleKind, cframe: CFrame, paintColor: Color3?, extras: Look?): Built
	local spec = CarSpec.Specs[kind.id]
	if kind.model ~= nil and spec ~= nil and MeshCar.Available(kind.model) then
		local built = MeshCar.Build(kind, spec, cframe, paintColor or (if extras then extras.paint else nil), if extras then extras.rims else nil, if extras then extras.glow else nil)
		built.layout.style = STYLES.gt
		return built :: any
	end
	local layout = CarBody.Layout(kind)
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

	local built: Built = {
		model = model,
		hull = hull,
		layout = layout,
		wheels = {},
		riders = {},
		headlights = {},
		brakeLights = {},
		reverseLights = {},
	}
	local ctx: Ctx = {
		model = model,
		base = cframe,
		layout = layout,
		paint = paintColor or (if extras then extras.paint else nil) or kind.color,
		rims = if extras then extras.rims else nil,
		accent = kind.accentColor,
		riders = built.riders,
		hull = hull,
	}

	lowerBody(ctx)
	openBox(ctx)
	arches(ctx)
	greenhouse(ctx)
	openCar(ctx)
	interior(ctx)
	flanks(ctx)
	frontEnd(ctx, kind, built)
	rearEnd(ctx, kind, built)
	for _, spec in { { true, -1 }, { true, 1 }, { false, -1 }, { false, 1 } } do
		table.insert(built.wheels, wheel(ctx, spec[1], spec[2]))
	end
	local glow = if extras then extras.glow else nil
	if glow then
		-- A bar of light under the sills between the axles, and a light throwing its colour on the
		-- road beneath: the pool is the effect; the bar is where it comes from.
		local style = layout.style
		local sill = lineAt(style.bottom, 0.5)
		local half = layout.width / 2 - 0.9
		local bar = block(ctx, "Underglow", -half, half, sill - 0.14, sill - 0.04, style.axles[1] + 0.03, style.axles[2] - 0.03, glow, Enum.Material.Neon)
		if bar then
			bar.CastShadow = false
			local pool = Instance.new("SurfaceLight")
			pool.Face = Enum.NormalId.Bottom
			pool.Color = glow
			pool.Brightness = 4
			pool.Range = 9
			pool.Angle = 120
			pool.Parent = bar
		end
	end

	-- The corner weights: a cubic stud each, as dense as its share of the mass makes it, invisible
	-- and touching nothing.
	for _, offset in layout.ballast do
		local weight = Instance.new("Part")
		weight.Name = "Ballast"
		weight.Size = Vector3.new(1, 1, 1)
		weight.CFrame = cframe * CFrame.new(offset)
		weight.Transparency = 1
		weight.Anchored = false
		weight.CanCollide = false
		weight.CanQuery = false
		weight.CanTouch = false
		weight.CustomPhysicalProperties = PhysicalProperties.new(layout.ballastMass, 0.3, 0.5)
		weight.Parent = model
		table.insert(built.riders, { weight, hull })
	end

	-- A collider over the greenhouse, so the roof can be stood on and walked into. Massless: the
	-- hull alone carries the car's weight.
	local style = layout.style
	local cabin = style.cabin
	if cabin then
		local s0, s1 = cabin[2][1], cabin[#cabin - 1][1]
		local roof = math.min(cabin[2][2], cabin[#cabin - 1][2])
		local belt = lineAt(style.top, (s0 + s1) / 2)
		local collider = Instance.new("Part")
		collider.Name = "CabinHull"
		collider.Size = Vector3.new(layout.width - style.tumble * 2, roof - belt, (s1 - s0) * layout.length)
		collider.CFrame = cframe * CFrame.new(at(ctx, 0, (roof + belt) / 2, (s0 + s1) / 2))
		collider.Transparency = 1
		collider.Anchored = false
		collider.CanCollide = true
		collider.CanTouch = false
		collider.Massless = true
		collider.Parent = model
		table.insert(built.riders, { collider, hull })
	end
	return built
end

-- Anchors every part where it stands: a car for looking at.
function CarBody.Anchor(built: Built)
	for _, part in built.model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
end

--[[
	Welds a car for driving: every body part to the hull, every piece of a wheel to that wheel's tyre
	or brake disc. The tyre and the disc themselves are held by a Weld each, returned in wheel order,
	tyre then disc, whose C0 the chassis moves every tick -- suspension travel, steering, spin.
]]
function CarBody.Weld(built: Built): { Weld }
	local roots: { [BasePart]: boolean } = {}
	for _, w in built.wheels do
		roots[w.spin] = true
		roots[w.knuckle] = true
	end
	for _, pair in built.riders do
		local part, on = pair[1], pair[2]
		if roots[part] then
			continue
		end
		if part == built.steeringWheel then
			-- Held by a Weld whose C0 client/world/CarWheels turns with the driver's hands.
			local steer = Instance.new("Weld")
			steer.Name = "SteerWeld"
			steer.Part0 = on
			steer.Part1 = part
			steer.C0 = on.CFrame:ToObjectSpace(part.CFrame)
			steer.C1 = CFrame.new()
			steer.Parent = part
			continue
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = on
		weld.Part1 = part
		weld.Parent = part
	end
	local welds: { Weld } = {}
	for _, w in built.wheels do
		for _, root in { w.spin, w.knuckle } do
			local weld = Instance.new("Weld")
			weld.Name = "WheelWeld"
			weld.Part0 = built.hull
			weld.Part1 = root
			weld.C0 = built.hull.CFrame:ToObjectSpace(root.CFrame)
			weld.C1 = CFrame.new()
			weld.Parent = root
			table.insert(welds, weld)
		end
	end
	return welds
end

-- Where a car's hull centre stands over `ground` (a CFrame on the floor, nose to its -Z) at rest.
function CarBody.RestOn(kind: VehicleKind, ground: CFrame): CFrame
	return ground * CFrame.new(0, CarBody.Layout(kind).hullY, 0)
end

-- The headline numbers a showroom prints: from the same fields the chassis drives on.
function CarBody.Mph(studsPerSecond: number): number
	-- A stud is 0.28 m (shared/CarSpec), and a metre a second is 2.237 miles an hour.
	return math.floor(studsPerSecond / CarSpec.StudsPerMetre * 2.23694 + 0.5)
end

return CarBody
