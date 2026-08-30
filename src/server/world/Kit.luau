--!strict
-- The building kit: the pieces every laid-in-code structure is made of.
--
-- Lab, Studio, Corridor and ReadingRoom each grew their own `buildBlock` and their own
-- `buildLabel`, byte-identical apart from which folder they parented into. That was fine at
-- four rooms and stops being fine at a three-storey building with an aquatic centre on the
-- side: the fifth copy is the one where somebody fixes a surface property in four places and
-- misses the fifth, and the symptom is one room in the school lit differently to the rest.
--
-- So this is the shared vocabulary. It knows nothing about schools -- it knows about slabs,
-- glass, columns, light panels, signs and stairs, and anything laid in Luau can speak it.
--
-- **Nothing here is anchored to the world.** Every function takes the position it is given
-- and the folder it is to live in. There is not an absolute world coordinate anywhere in
-- this file, and there must never be one: the map still moves, and a kit that knew where
-- anything was would move the wrong things when it did.
--
-- Everything is `Anchored` and almost everything is `CanCollide = false`. Collision is opt
-- in, per piece, because the cost of a stray collidable prop in a corridor is a player stuck
-- on a bench, and the cost of a non-collidable wall is a player walking through it -- the
-- second is a bug you see immediately and the first is one you get a report about.

local Kit = {}

-- How often a glazed wall is divided, and how heavy the divisions are.
--
-- Eight studs is a bay a little wider than a doorway, which is what makes it work: the eye
-- has a human-sized unit to measure the elevation against, and a wall that was one huge sheet
-- becomes a legible count of bays. Wider than about twelve and the effect is lost; tighter
-- than about six and a long elevation turns into a fence.
-- Safe range: 6-12, 0.3-0.8, 8-16.
local MULLION_SPACING_STUDS = 8
local MULLION_WIDTH_STUDS = 0.5
local MULLION_TRANSOM_MIN_HEIGHT = 11

-- The material every painted surface uses unless told otherwise. SmoothPlastic rather than
-- Plastic because Plastic carries a subtle noise texture that reads as dirt at the scale a
-- school is built at, and it is the difference between "clean modern building" and "old".
local DEFAULT_MATERIAL = Enum.Material.SmoothPlastic

export type BlockOptions = {
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
	collide: boolean?,
	-- Rotation about the vertical axis, in degrees. Everything in a building is either
	-- square to the grid or turned about Y, so this is the only rotation the kit offers --
	-- an arbitrary CFrame parameter would be an invitation to lay something at an angle no
	-- other piece can line up with.
	yawDegrees: number?,
	reflectance: number?,
}

-- One rectangular piece, positioned by its **centre**.
--
-- Centre rather than by a corner or by its base, because every other thing in this file
-- composes out of it and two conventions would mean converting between them at every call
-- site -- which is exactly where an off-by-half-a-height error lives.
function Kit.Block(parent: Instance, name: string, center: Vector3, size: Vector3, options: BlockOptions): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(center) * CFrame.Angles(0, math.rad(options.yawDegrees or 0), 0)
	part.Anchored = true
	part.CanCollide = options.collide == true
	part.Color = options.color
	part.Material = options.material or DEFAULT_MATERIAL
	part.Transparency = options.transparency or 0
	part.Reflectance = options.reflectance or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A floor or ceiling slab, positioned by the height of its **top surface**, which is the
-- number anybody laying a storey actually has: a floor at y = 18 means you stand at 18.
function Kit.Slab(
	parent: Instance,
	name: string,
	center: Vector3,
	width: number,
	depth: number,
	thickness: number,
	options: BlockOptions
): BasePart
	local at = Vector3.new(center.X, center.Y - thickness / 2, center.Z)
	local block = Kit.Block(parent, name, at, Vector3.new(width, thickness, depth), options)
	-- Floors collide unless the caller says otherwise, which is the opposite of the default
	-- and is the one place the inversion is right: a floor you fall through is not a floor.
	block.CanCollide = if options.collide == nil then true else options.collide
	return block
end

-- A wall, given the two ends of its base line and a height. Works out its own length and
-- yaw, so a caller lays walls by naming corners rather than by doing trigonometry -- which
-- is what makes a room a loop over four points instead of four hand-written blocks.
function Kit.Wall(
	parent: Instance,
	name: string,
	from: Vector3,
	to: Vector3,
	height: number,
	thickness: number,
	options: BlockOptions
): BasePart?
	local delta = to - from
	local length = delta.Magnitude
	if length < 0.05 then
		-- Two corners in the same place. Refused rather than built as a zero-length sliver,
		-- because a degenerate part is invisible in Studio and impossible to select.
		return nil
	end
	local mid = from + delta * 0.5
	local yaw = math.deg(math.atan2(-delta.X, -delta.Z))
	local opts: BlockOptions = {
		color = options.color,
		material = options.material,
		transparency = options.transparency,
		collide = if options.collide == nil then true else options.collide,
		yawDegrees = yaw,
		reflectance = options.reflectance,
	}
	return Kit.Block(
		parent,
		name,
		Vector3.new(mid.X, mid.Y + height / 2, mid.Z),
		Vector3.new(thickness, height, length),
		opts
	)
end

-- A glazed wall: a sill, a head, and glass between them.
--
-- Three pieces rather than one transparent block, and that is the whole reason this
-- function exists. A window wall in a real building has a solid band at the floor and
-- another at the ceiling; without them glass reads as a *missing* wall rather than as a
-- window, and the building looks unfinished in exactly the way a first pass always does.
function Kit.GlassWall(
	parent: Instance,
	name: string,
	from: Vector3,
	to: Vector3,
	height: number,
	thickness: number,
	glassShare: number,
	frameColor: Color3,
	glassColor: Color3
)
	local glassHeight = height * glassShare
	local bandHeight = (height - glassHeight) / 2

	Kit.Wall(parent, `{name}Sill`, from, to, bandHeight, thickness, { color = frameColor })

	local glassBase = Vector3.new(from.X, from.Y + bandHeight, from.Z)
	local glassTo = Vector3.new(to.X, to.Y + bandHeight, to.Z)
	local pane = Kit.Wall(parent, `{name}Glass`, glassBase, glassTo, glassHeight, thickness * 0.5, {
		color = glassColor,
		material = Enum.Material.Glass,
		transparency = 0.55,
		-- Deliberately not collidable. A glazed elevation is mostly glass, and a player who
		-- clips a pane while walking the corridor behind it would be stopped by something they
		-- can see straight through -- which reads as the building being broken.
		collide = false,
		reflectance = 0.15,
	})
	if pane ~= nil then
		pane.CastShadow = false
	end

	local headBase = Vector3.new(from.X, from.Y + bandHeight + glassHeight, from.Z)
	local headTo = Vector3.new(to.X, to.Y + bandHeight + glassHeight, to.Z)
	Kit.Wall(parent, `{name}Head`, headBase, headTo, bandHeight, thickness, { color = frameColor })

	-- Mullions: the uprights that divide a glazed elevation into bays.
	--
	-- This is the single highest-value detail in the whole kit per part spent, and the reason
	-- is scale rather than decoration. A ninety-stud pane of flat glass has nothing in it to
	-- measure the building against, so the eye reads it as one enormous window and the whole
	-- elevation loses its size -- which is exactly why the school looked toy-like next to a
	-- town of small houses. Divide the same glass every eight studs and each bay is suddenly
	-- door-sized, the building is legibly three storeys, and not one dimension has changed.
	--
	-- Every glazed wall in the school goes through this function -- the frontage, both wings,
	-- the gym, the pool hall and every classroom elevation -- so the spacing here is the
	-- glazing rhythm of the entire building.
	local span = (to - from).Magnitude
	if span > MULLION_SPACING_STUDS then
		local bays = math.max(1, math.floor(span / MULLION_SPACING_STUDS + 0.5))
		local direction = (to - from).Unit
		for index = 1, bays - 1 do
			local along = from + direction * (span * (index / bays))
			local base = Vector3.new(along.X, from.Y + bandHeight, along.Z)
			local bar = Kit.Block(
				parent,
				`{name}Mullion{index}`,
				base + Vector3.new(0, glassHeight / 2, 0),
				Vector3.new(MULLION_WIDTH_STUDS, glassHeight, thickness * 0.9),
				{
					color = frameColor,
					-- Turned to stand square in the wall, the same way Kit.Wall turns its own
					-- panels: a mullion at the wall's angle rather than the world's.
					yawDegrees = -math.deg(math.atan2(direction.Z, direction.X)),
				}
			)
			bar.CastShadow = false
		end

		-- A transom across the middle, which is what stops tall bays reading as slots. Only on
		-- glazing tall enough to want one -- a low clerestory divided horizontally looks like
		-- a mistake rather than a window.
		if glassHeight > MULLION_TRANSOM_MIN_HEIGHT then
			local transom = Kit.Wall(
				parent,
				`{name}Transom`,
				Vector3.new(from.X, from.Y + bandHeight + glassHeight / 2, from.Z),
				Vector3.new(to.X, to.Y + bandHeight + glassHeight / 2, to.Z),
				MULLION_WIDTH_STUDS,
				thickness * 0.9,
				{ color = frameColor, collide = false }
			)
			if transom ~= nil then
				transom.CastShadow = false
			end
		end
	end
end

-- A structural column, by the centre of its base.
function Kit.Column(parent: Instance, name: string, base: Vector3, height: number, thickness: number, color: Color3): BasePart
	return Kit.Block(
		parent,
		name,
		Vector3.new(base.X, base.Y + height / 2, base.Z),
		Vector3.new(thickness, height, thickness),
		{ color = color, material = Enum.Material.Concrete, collide = true }
	)
end

-- A recessed ceiling light panel. Neon rather than a PointLight, and that is a performance
-- decision rather than a look one: a school interior wants sixty of these and sixty real
-- lights would cost more than the rest of the building put together. Neon is free and, at
-- this scale, indistinguishable.
function Kit.LightPanel(parent: Instance, name: string, center: Vector3, width: number, depth: number): BasePart
	local panel = Kit.Block(parent, name, center, Vector3.new(width, 0.2, depth), {
		color = Color3.fromRGB(255, 253, 244),
		material = Enum.Material.Neon,
	})
	panel.CastShadow = false
	return panel
end

-- A flat circular rug. The cheapest thing in the kit and, at a white tiled floor, close to
-- the most effective: an unbroken tile plane reads as a warehouse, and two or three of these
-- read as a room somebody furnished.
function Kit.Rug(parent: Instance, name: string, center: Vector3, radius: number, color: Color3): BasePart
	local rug = Instance.new("Part")
	rug.Name = name
	rug.Shape = Enum.PartType.Cylinder
	rug.Size = Vector3.new(0.12, radius * 2, radius * 2)
	-- Turned on its side: a Roblox cylinder\'s length runs along X, so a flat disc is a
	-- quarter turn about Z rather than a short cylinder.
	rug.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	rug.Anchored = true
	rug.CanCollide = false
	rug.Color = color
	rug.Material = Enum.Material.Fabric
	rug.CastShadow = false
	rug.Parent = parent
	return rug
end

-- A planter with a hedge in it. Two blocks, and the reason it is worth a function is that
-- the proportion between them is what makes it read as planting rather than as a green box
-- on a white box.
function Kit.Planter(parent: Instance, name: string, base: Vector3, width: number, height: number)
	local potHeight = height * 0.32
	Kit.Block(parent, `{name}Pot`, Vector3.new(base.X, base.Y + potHeight / 2, base.Z), Vector3.new(width, potHeight, width), {
		color = Color3.fromRGB(238, 238, 240),
	})
	Kit.Block(
		parent,
		`{name}Hedge`,
		Vector3.new(base.X, base.Y + potHeight + (height - potHeight) / 2, base.Z),
		Vector3.new(width * 0.86, height - potHeight, width * 0.86),
		{ color = Color3.fromRGB(104, 152, 84), material = Enum.Material.Grass }
	)
end

-- A tree: trunk and two canopy blobs. Not a mesh, because the kit must not depend on an
-- asset id -- a building that needs the catalog to be reachable is a building that does not
-- lay on a fresh machine.
-- A clipped conical topiary: the tall dark-green cone that lines the reference's forecourt.
--
-- It is a different plant from Kit.Tree and it is worth having both. A round canopy on a
-- visible trunk reads as a park tree; these read as *landscaping* -- something a groundsman
-- shapes -- and a row of them down an approach is most of why that frontage looks like a
-- school somebody maintains rather than a building dropped on grass.
--
-- Built as a stack of tapering balls rather than one cone, because there is no cone primitive
-- and a stack reads softer than the wedge that would otherwise be reached for -- these are
-- clipped shrubs, not spikes.
function Kit.Topiary(parent: Instance, name: string, base: Vector3, height: number, tiers: number)
	local trunkHeight = height * 0.12
	Kit.Block(parent, `{name}Trunk`, Vector3.new(base.X, base.Y + trunkHeight / 2, base.Z), Vector3.new(1.2, trunkHeight, 1.2), {
		color = Color3.fromRGB(104, 78, 58),
		material = Enum.Material.Wood,
	})

	local green = Color3.fromRGB(78, 128, 70)
	for tier = 1, tiers do
		local share = (tier - 1) / tiers
		-- Width falls away faster than height climbs, which is what makes a cone rather than a
		-- column. The top tier is deliberately small enough to read as a point.
		local width = height * 0.36 * (1 - share * 0.82)
		local tall = height * 0.9 / tiers * 1.25
		local y = base.Y + trunkHeight + (height * 0.9) * (share + 0.5 / tiers)
		local blob = Instance.new("Part")
		blob.Name = `{name}Tier{tier}`
		blob.Shape = Enum.PartType.Ball
		blob.Size = Vector3.new(width, tall, width)
		blob.CFrame = CFrame.new(base.X, y, base.Z)
		blob.Anchored = true
		blob.CanCollide = false
		blob.Color = green
		blob.Material = Enum.Material.Grass
		blob.CastShadow = tier == 1
		blob.Parent = parent
	end
end

function Kit.Tree(parent: Instance, name: string, base: Vector3, height: number)
	local trunkHeight = height * 0.45
	Kit.Block(parent, `{name}Trunk`, Vector3.new(base.X, base.Y + trunkHeight / 2, base.Z), Vector3.new(1.6, trunkHeight, 1.6), {
		color = Color3.fromRGB(112, 84, 62),
		material = Enum.Material.Wood,
	})
	local canopy = Instance.new("Part")
	canopy.Name = `{name}Canopy`
	canopy.Shape = Enum.PartType.Ball
	canopy.Size = Vector3.new(height * 0.5, height * 0.62, height * 0.5)
	canopy.CFrame = CFrame.new(base + Vector3.new(0, trunkHeight + height * 0.28, 0))
	canopy.Anchored = true
	canopy.CanCollide = false
	canopy.Color = Color3.fromRGB(96, 148, 82)
	canopy.Material = Enum.Material.Grass
	canopy.Parent = parent
end

-- A flight of stairs as a run of steps, from one landing to the next.
--
-- Real steps rather than a ramp with a texture, because a ramp is the thing that makes a
-- three-storey building feel like a diagram: you glide up it. Roblox humanoids climb a step
-- of up to 2 studs without help, so the rise per step is worked out from the count and
-- checked against that -- a flight that is too steep is refused rather than laid, since the
-- failure is a player who cannot reach the first floor and no error anywhere.
function Kit.Stairs(
	parent: Instance,
	name: string,
	base: Vector3,
	top: Vector3,
	width: number,
	steps: number,
	color: Color3
): boolean
	local rise = top.Y - base.Y
	local perStep = rise / steps
	if perStep > 2 then
		return false
	end

	local run = Vector3.new(top.X - base.X, 0, top.Z - base.Z)
	local runLength = run.Magnitude
	if runLength < 0.05 then
		return false
	end
	local direction = run.Unit
	local yaw = math.deg(math.atan2(-direction.X, -direction.Z))
	local depthPerStep = runLength / steps

	for index = 1, steps do
		-- Each tread is a block whose top is at that step\'s height and which reaches all the
		-- way down to the base. Solid rather than floating treads: a player who walks off the
		-- side of a floating flight falls through the middle of the building.
		local topY = base.Y + perStep * index
		local centre = base + direction * (depthPerStep * (index - 0.5))
		local height = topY - base.Y
		Kit.Block(
			parent,
			`{name}Step{index}`,
			Vector3.new(centre.X, base.Y + height / 2, centre.Z),
			Vector3.new(width, height, depthPerStep),
			{ color = color, collide = true, yawDegrees = yaw }
		)
	end
	return true
end

-- A guard rail along a line. Two posts and a top rail; the balusters are left out on
-- purpose, because at the density a building needs them they cost hundreds of parts to say
-- something the top rail has already said.
function Kit.Railing(parent: Instance, name: string, from: Vector3, to: Vector3, height: number, color: Color3)
	Kit.Wall(parent, `{name}Rail`, Vector3.new(from.X, from.Y + height, from.Z), Vector3.new(to.X, to.Y + height, to.Z), 0.35, 0.35, {
		color = color,
		material = Enum.Material.Metal,
		collide = false,
	})
	Kit.Wall(parent, `{name}Panel`, from, to, height, 0.25, {
		color = color,
		material = Enum.Material.Glass,
		transparency = 0.6,
		collide = true,
	})
end

-- A name over a thing, readable from across a room and no further.
function Kit.Sign(part: BasePart, text: string, width: number, maxDistance: number, color: Color3): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Adornee = part
	gui.Size = UDim2.new(width, 0, width * 0.22, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 1.6, 0)
	gui.MaxDistance = maxDistance
	gui.AlwaysOnTop = false
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.55
	label.Text = text
	label.Parent = gui
	return label
end

-- A line of bunting between two points. Purely decorative and deliberately kept: it is the
-- cheapest signal in the kit that a building is *used* rather than merely built, and the
-- reference photographs are full of it.
function Kit.Bunting(parent: Instance, name: string, from: Vector3, to: Vector3, flags: number, colors: { Color3 })
	if #colors == 0 then
		return
	end
	local delta = to - from
	for index = 1, flags do
		local share = (index - 0.5) / flags
		-- A shallow sag, so the line hangs rather than being pulled taut between two nails.
		local sag = math.sin(share * math.pi) * 1.4
		local at = from + delta * share - Vector3.new(0, sag, 0)
		local flag = Kit.Block(parent, `{name}{index}`, at, Vector3.new(1.4, 1.1, 0.08), {
			color = colors[((index - 1) % #colors) + 1],
			material = Enum.Material.Fabric,
		})
		flag.CastShadow = false
	end
end

-- A balloon on a string. Two parts, and the string is the half that matters: a ball
-- hanging in mid-air reads as a bug, and a ball with a line down to the floor reads as a
-- party. It is the cheapest signal in the whole kit.
function Kit.Balloon(parent: Instance, name: string, base: Vector3, height: number, color: Color3)
	local ball = Instance.new("Part")
	ball.Name = `{name}Ball`
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(3.2, 3.8, 3.2)
	ball.CFrame = CFrame.new(base + Vector3.new(0, height, 0))
	ball.Anchored = true
	ball.CanCollide = false
	ball.Color = color
	ball.Material = Enum.Material.SmoothPlastic
	ball.CastShadow = false
	ball.Parent = parent

	Kit.Block(parent, `{name}String`, base + Vector3.new(0, height / 2, 0), Vector3.new(0.1, height, 0.1), {
		color = Color3.fromRGB(238, 238, 242),
	}).CastShadow = false
end

-- A bunch of them, fanned so no two are at the same height. Even heights read as a rack of
-- balls; uneven ones read as balloons.
function Kit.BalloonCluster(parent: Instance, name: string, base: Vector3, count: number, colors: { Color3 })
	if #colors == 0 or count < 1 then
		return
	end
	for index = 1, count do
		local angle = (index / count) * math.pi * 2
		local spread = 2.4
		local at = base + Vector3.new(math.cos(angle) * spread, 0, math.sin(angle) * spread)
		Kit.Balloon(parent, `{name}_{index}`, at, 9 + (index % 3) * 2.2, colors[((index - 1) % #colors) + 1])
	end
end

-- An arch of them over a doorway. Odd counts put one balloon at the crown, which is what
-- makes it read as an arch rather than as two columns.
function Kit.BalloonArch(parent: Instance, name: string, center: Vector3, span: number, rise: number, count: number, colors: { Color3 })
	if #colors == 0 or count < 3 then
		return
	end
	for index = 1, count do
		local share = (index - 1) / (count - 1)
		local angle = math.pi * share
		local at = center + Vector3.new(-math.cos(angle) * (span / 2), math.sin(angle) * rise, 0)
		local ball = Instance.new("Part")
		ball.Name = `{name}{index}`
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(3.6, 4, 3.6)
		ball.CFrame = CFrame.new(at)
		ball.Anchored = true
		ball.CanCollide = false
		ball.Color = colors[((index - 1) % #colors) + 1]
		ball.Material = Enum.Material.SmoothPlastic
		ball.CastShadow = false
		ball.Parent = parent
	end
end

-- A streamer strung between two points, sagging in the middle. Same idea as Bunting but a
-- continuous ribbon rather than flags, which is what a ceiling wants -- flags read as an
-- outdoor fete and ribbons read as a hall somebody decorated.
function Kit.Streamer(parent: Instance, name: string, from: Vector3, to: Vector3, segments: number, color: Color3)
	local delta = to - from
	for index = 1, segments do
		local a = (index - 1) / segments
		local b = index / segments
		local pa = from + delta * a - Vector3.new(0, math.sin(a * math.pi) * 3.5, 0)
		local pb = from + delta * b - Vector3.new(0, math.sin(b * math.pi) * 3.5, 0)
		local seg = Kit.Wall(parent, `{name}{index}`, pa, pb, 0.45, 0.12, {
			color = color,
			material = Enum.Material.Fabric,
			collide = false,
		})
		if seg ~= nil then
			seg.CastShadow = false
		end
	end
end

-- A hanging pendant lamp: cord, shade, and a neon disc for the bulb.
--
-- Dozens of these rather than a few ceiling panels is most of the difference between a room
-- that reads as a warehouse gym and one that reads as a school corridor, and it costs three
-- parts each because the light itself is neon rather than a real PointLight -- sixty real
-- lights in one room would cost more than the building.
function Kit.Pendant(parent: Instance, name: string, ceiling: Vector3, drop: number, shadeColor: Color3)
	Kit.Block(parent, `{name}Cord`, ceiling - Vector3.new(0, drop / 2, 0), Vector3.new(0.12, drop, 0.12), {
		color = Color3.fromRGB(40, 42, 48),
	}).CastShadow = false

	Kit.Block(parent, `{name}Shade`, ceiling - Vector3.new(0, drop, 0), Vector3.new(2.6, 1.6, 2.6), {
		color = shadeColor,
		material = Enum.Material.Metal,
	}).CastShadow = false

	local bulb = Kit.Block(parent, `{name}Bulb`, ceiling - Vector3.new(0, drop + 0.9, 0), Vector3.new(2, 0.25, 2), {
		color = Color3.fromRGB(255, 244, 214),
		material = Enum.Material.Neon,
	})
	bulb.CastShadow = false
end

-- A coloured wash on the floor, for a room that is being lit for something. Flat, bright and
-- non-collidable: it is a pool of light rather than an object, and anything the player can
-- stand on would make the dance floor a step.
function Kit.Spotlight(parent: Instance, name: string, at: Vector3, radius: number, color: Color3)
	local pool = Kit.Rug(parent, name, at, radius, color)
	pool.Material = Enum.Material.Neon
	pool.Transparency = 0.55
	return pool
end

-- A mirrored wall. High reflectance and a hair of transparency, which at Roblox's shading is
-- what reads as glass with something behind it rather than as a grey panel.
function Kit.Mirror(parent: Instance, name: string, from: Vector3, to: Vector3, height: number)
	local pane = Kit.Wall(parent, name, from, to, height, 0.4, {
		color = Color3.fromRGB(206, 216, 226),
		material = Enum.Material.Glass,
		transparency = 0.25,
		reflectance = 0.75,
		collide = true,
	})
	if pane ~= nil then
		pane.CastShadow = false
	end
	return pane
end

-- A loaded barbell: the bar, and a stack of coloured plates at each end.
--
-- The plates are the whole point. A grey bar on a rack is a stick; competition plates are
-- colour-coded by weight -- red, blue, yellow, green -- and a rack of them is instantly a
-- gym. This is the single highest-value prop in the kit per part spent.
function Kit.Barbell(parent: Instance, name: string, center: Vector3, length: number, plates: number)
	Kit.Block(parent, `{name}Bar`, center, Vector3.new(length, 0.45, 0.45), {
		color = Color3.fromRGB(196, 200, 206),
		material = Enum.Material.Metal,
	}).CastShadow = false

	local plateColors = {
		Color3.fromRGB(206, 66, 62),
		Color3.fromRGB(56, 110, 196),
		Color3.fromRGB(226, 194, 74),
		Color3.fromRGB(86, 176, 108),
	}
	for side = -1, 1, 2 do
		for index = 1, plates do
			local offset = side * (length / 2 - 1.4 - (index - 1) * 0.9)
			local plate = Instance.new("Part")
			plate.Name = `{name}Plate{side}_{index}`
			plate.Shape = Enum.PartType.Cylinder
			-- A Roblox cylinder runs along X, which is already the bar's axis, so a plate needs
			-- no rotation at all -- unlike Rug, which has to be turned on its side.
			plate.Size = Vector3.new(0.5, 3.6 - (index - 1) * 0.5, 3.6 - (index - 1) * 0.5)
			plate.CFrame = CFrame.new(center + Vector3.new(offset, 0, 0))
			plate.Anchored = true
			plate.CanCollide = false
			plate.Color = plateColors[((index - 1) % #plateColors) + 1]
			plate.Material = Enum.Material.SmoothPlastic
			plate.CastShadow = false
			plate.Parent = parent
		end
	end
end

return Kit
