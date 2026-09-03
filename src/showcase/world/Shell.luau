--!strict
-- The building, from Plan.
--
-- Not a grey block-out this time. The plan's whole argument is light and openness, and a
-- block-out in one colour cannot be judged against that -- you would be looking at exactly the
-- concrete box the plan exists to replace. So the glass, the timber and the planting go in with
-- the structure, and only they do: no furniture, no trim, no props.
--
-- It reads Plan.luau and lays what the plan says. Nothing here decides a dimension.

local Plan = require(script.Parent.Plan)
local Kit = require(script.Parent.Kit)
local Props = require(script.Parent.Props)

local Shell = {}

Shell.Width = Plan.WidthStuds
Shell.Depth = Plan.DepthStuds

-- Section 03's palette. The building is four materials and no more.
local CONCRETE = Color3.fromRGB(196, 194, 188) -- pale, not grey: this is a light building
local SHADED = Color3.fromRGB(150, 148, 142)
local TIMBER = Color3.fromRGB(122, 86, 58)
local TIMBER_DARK = Color3.fromRGB(88, 62, 42)
local MAPLE = Color3.fromRGB(196, 148, 92)
local IRON = Color3.fromRGB(48, 50, 56)
local GLASS = Color3.fromRGB(150, 176, 196)
local LAWN = Color3.fromRGB(74, 102, 62)
local LEAF = Color3.fromRGB(88, 122, 70)

local built = false

-- ---------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------

local function slab(parent: Instance, name: string, x1: number, z1: number, x2: number, z2: number, y: number, colour: Color3, toWorld: (number, number, number) -> Vector3)
	if x2 - x1 < 0.05 or z2 - z1 < 0.05 then
		return
	end
	Kit.Block(parent, name, toWorld((x1 + x2) / 2, y + Plan.SlabStuds / 2, (z1 + z2) / 2), Vector3.new(x2 - x1, Plan.SlabStuds, z2 - z1), colour)
end

-- **A curtain wall is panels and vertical mullions, and nothing else.**
--
-- No horizontal transom at every storey: that is the single thing that makes Roblox glass read
-- as graph paper instead of as a facade. The bay is 8 studs -- wider looks like a shopfront,
-- narrower and the mullions eat the view.
--
-- Panels are CanCollide so you cannot walk out of the building, and CastShadow false because a
-- transparent pane casting a hard shadow is the giveaway that it is not really glass.
local function curtain(parent: Instance, name: string, axis: string, fixed: number, from: number, to: number, y: number, height: number, toWorld: (number, number, number) -> Vector3)
	local span = to - from
	local bays = math.max(1, math.round(span / Plan.GlassBayStuds))
	local bay = span / bays
	for index = 0, bays - 1 do
		local centre = from + bay * (index + 0.5)
		local size = if axis == "x" then Vector3.new(bay - Plan.MullionStuds, height, 0.4) else Vector3.new(0.4, height, bay - Plan.MullionStuds)
		local at = if axis == "x" then toWorld(centre, y + height / 2, fixed) else toWorld(fixed, y + height / 2, centre)
		Kit.Block(parent, `{name}Pane{index}`, at, size, GLASS, {
			material = Enum.Material.Glass,
			transparency = Plan.GlassTransparency,
			reflectance = Plan.GlassReflectance,
			shadow = false,
		})
	end
	for index = 1, bays - 1 do
		local at = from + bay * index
		local size = if axis == "x" then Vector3.new(Plan.MullionStuds, height, 1.2) else Vector3.new(1.2, height, Plan.MullionStuds)
		local pos = if axis == "x" then toWorld(at, y + height / 2, fixed) else toWorld(fixed, y + height / 2, at)
		Kit.Block(parent, `{name}Mullion{index}`, pos, size, IRON, {
			material = Enum.Material.Metal,
			shadow = false,
			collide = false,
		})
	end
end

-- ---------------------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------------------

function Shell.Build(origin: Vector3, options: { Ground: boolean? }?): Instance?
	local existing = workspace:FindFirstChild("Showcase")
	if existing ~= nil then
		return existing
	end
	if built then
		return nil
	end
	built = true

	local o = options or {}
	local folder = Instance.new("Folder")
	folder.Name = "Showcase"
	folder.Parent = workspace

	local function at(x: number, y: number, z: number): Vector3
		return origin + Vector3.new(x, y, z)
	end

	local X, Z, E, ZE = Plan.X, Plan.Z, Plan.Edge, Plan.ZEdge
	local W, D = Plan.WidthStuds, Plan.DepthStuds
	local atrium, garden, gym, cafe = Plan.Atrium(), Plan.Garden(), Plan.Gym(), Plan.Cafeteria()

	-- ---- ground
	if o.Ground ~= false then
		Kit.Block(folder, "Ground", at(W / 2, -1, D / 2), Vector3.new(W + 200, 2, D + 200), SHADED)
	end

	-- ---- the garden: lawn, paving down the axis, and low-poly planting
	slab(folder, "GardenLawn", garden.X1, garden.Z1, garden.X2, garden.Z2, -Plan.SlabStuds, LAWN, at)
	local axisX = (garden.X1 + garden.X2) / 2
	slab(folder, "GardenWalk", axisX - 14, garden.Z1, axisX + 14, garden.Z2, -Plan.SlabStuds + 0.1, CONCRETE, at)
	for index = 1, 10 do
		local side = if index % 2 == 0 then 1 else -1
		local tx = axisX + side * (26 + (index % 3) * 16)
		local tz = garden.Z1 + 16 + (index - 1) * 12
		Kit.Block(folder, `TreeTrunk{index}`, at(tx, 6, tz), Vector3.new(2, 12, 2), TIMBER_DARK, { material = Enum.Material.Wood })
		-- Two stacked boxes rather than a sphere: low-poly on purpose, and it reads better in
		-- silhouette against glass than a smooth ball does.
		Kit.Block(folder, `TreeCrown{index}a`, at(tx, 15, tz), Vector3.new(13, 7, 13), LEAF, { material = Enum.Material.Grass, shadow = false })
		Kit.Block(folder, `TreeCrown{index}b`, at(tx, 20, tz), Vector3.new(8, 5, 8), LEAF, { material = Enum.Material.Grass, shadow = false })
	end

	-- ---- the patio deck, west of the cafeteria, three 2-stud steps down
	local patio = Plan.Patio()
	slab(folder, "PatioDeck", patio.X1, patio.Z1, patio.X2, patio.Z2, -Plan.PatioDropStuds, TIMBER, at)
	for step = 1, 3 do
		slab(folder, `PatioStep{step}`, 0, patio.Z1, 6, patio.Z2, -step * 2, TIMBER_DARK, at)
	end

	-- ---- slabs, per level. The atrium and garden are void; everything else is floor.
	for floor = 1, 2 do
		local base = if floor == 1 then 0 else Plan.GroundStoreyStuds
		local level = Instance.new("Folder")
		level.Name = `Level{floor}`
		level.Parent = folder

		-- West wing, east wing, and the band behind the atrium.
		--
		-- Level 2 has no slab over the gymnasium -- it is one 44-stud volume through both storeys
		-- -- so the east slab starts behind the hall rather than being laid and then cut out.
		local eastFrom = if floor == 1 then 0 else gym.Z2
		slab(level, "SlabWest", 0, 0, X[E.VoidNear], D, base, CONCRETE, at)
		slab(level, "SlabEast", X[E.VoidFar], eastFrom, W, D, base, CONCRETE, at)
		slab(level, "SlabBack", X[E.VoidNear], Z[ZE.AtriumBack], X[E.VoidFar], D, base, CONCRETE, at)
	end

	-- ---- the aerial bridges
	for _, bridge in Plan.Bridges() do
		slab(folder, `Bridge_{bridge.Id}`, bridge.X1, bridge.Z1, bridge.X2, bridge.Z2, Plan.GroundStoreyStuds, CONCRETE, at)
		for _, edge in { bridge.Z1, bridge.Z2 } do
			Kit.Block(folder, `BridgeRail_{bridge.Id}_{edge}`, at((bridge.X1 + bridge.X2) / 2, Plan.GroundStoreyStuds + 6, edge), Vector3.new(bridge.X2 - bridge.X1, 0.4, 0.4), IRON, {
				material = Enum.Material.Metal,
				shadow = false,
			})
			curtain(folder, `BridgeGlass_{bridge.Id}_{edge}`, "x", edge, bridge.X1, bridge.X2, Plan.GroundStoreyStuds + Plan.SlabStuds, 5.5, at)
		end
	end

	-- ---- curtain walling
	--
	-- Four faces get glass, and they are the four that matter: both wings looking into the
	-- garden, both wings looking out, and the atrium's south face onto the approach.
	for floor = 1, 2 do
		local base = if floor == 1 then Plan.SlabStuds else Plan.GroundStoreyStuds + Plan.SlabStuds
		local height = if floor == 1 then Plan.GroundClearStuds else Plan.UpperClearStuds
		curtain(folder, `GlassWestIn{floor}`, "z", X[E.VoidNear], 0, D, base, height, at)
		curtain(folder, `GlassEastIn{floor}`, "z", X[E.VoidFar], 0, D, base, height, at)
		curtain(folder, `GlassWestOut{floor}`, "z", Plan.MullionStuds, 0, D, base, height, at)
		curtain(folder, `GlassEastOut{floor}`, "z", W - Plan.MullionStuds, 0, D, base, height, at)
		curtain(folder, `GlassWestFront{floor}`, "x", 0, 0, X[E.VoidNear], base, height, at)
		curtain(folder, `GlassEastFront{floor}`, "x", 0, X[E.VoidFar], W, base, height, at)
		curtain(folder, `GlassBack{floor}`, "x", D, 0, W, base, height, at)
	end
	-- The atrium's own south wall, full height in one sweep -- this is the face you see from the
	-- garden and the reason the whole plan is called glass.
	curtain(folder, "GlassAtriumFront", "x", atrium.Z1, atrium.X1, atrium.X2, Plan.SlabStuds, Plan.RoofStuds - Plan.SlabStuds, at)

	-- ---- roofs
	slab(folder, "RoofWest", 0, 0, X[E.VoidNear], D, Plan.RoofStuds, CONCRETE, at)
	slab(folder, "RoofEast", X[E.VoidFar], 0, W, D, Plan.RoofStuds, CONCRETE, at)
	slab(folder, "RoofBack", X[E.VoidNear], Z[ZE.AtriumBack], X[E.VoidFar], D, Plan.RoofStuds, CONCRETE, at)

	-- The lantern: glazed, and raised above the parapet so light enters over the roofline.
	local lanternY = Plan.RoofStuds + Plan.LanternStuds
	for _, side in { atrium.X1, atrium.X2 } do
		curtain(folder, `LanternSide{side}`, "z", side, atrium.Z1, atrium.Z2, Plan.RoofStuds, Plan.LanternStuds, at)
	end
	Kit.Block(folder, "LanternGlass", at((atrium.X1 + atrium.X2) / 2, lanternY, (atrium.Z1 + atrium.Z2) / 2), Vector3.new(atrium.X2 - atrium.X1, 0.6, atrium.Z2 - atrium.Z1), GLASS, {
		material = Enum.Material.Glass,
		transparency = 0.62,
		shadow = false,
		collide = false,
	})
	-- Beams across it, so the roof has structure rather than being a sheet of tint.
	for index = 0, 10 do
		local z = atrium.Z1 + (atrium.Z2 - atrium.Z1) * (index / 10)
		Kit.Block(folder, `LanternBeam{index}`, at((atrium.X1 + atrium.X2) / 2, lanternY - 0.8, z), Vector3.new(atrium.X2 - atrium.X1, 1.2, 1.6), TIMBER, {
			material = Enum.Material.Wood,
			shadow = false,
		})
	end

	-- ---- the gymnasium: one volume, a timber vault, a maple court
	slab(folder, "GymFloor", gym.X1, gym.Z1, gym.X2, gym.Z2, 0, MAPLE, at)
	local courtX, courtZ = (gym.X1 + gym.X2) / 2, (gym.Z1 + gym.Z2) / 2
	Kit.Block(folder, "CourtLine", at(courtX, Plan.SlabStuds + 0.05, courtZ), Vector3.new(84, 0.1, 46), MAPLE, {
		material = Enum.Material.WoodPlanks,
		shadow = false,
		collide = false,
	})
	-- The vault, as stepped timber ribs. Roblox has no curved beam, and a stepped arch reads as
	-- a vault the moment there are enough ribs -- eleven is enough.
	for index = 0, 10 do
		local t = index / 10
		local z = gym.Z1 + (gym.Z2 - gym.Z1) * t
		for step = 0, 4 do
			local inset = step * 9
			local y = Plan.SlabStuds + Plan.GymClearStuds - step * 3
			Kit.Block(folder, `GymRib{index}_{step}`, at(courtX, y, z), Vector3.new(gym.X2 - gym.X1 - inset, 1.4, 2), TIMBER, {
				material = Enum.Material.Wood,
				shadow = false,
			})
		end
	end

	-- ---- the learning stair
	--
	-- Rising floor to floor -- 26, not the 22 of clear height. A stair climbs the slab as well as
	-- the room, and getting that wrong lands it four studs under its own landing.
	local stairX = (atrium.X1 + atrium.X2) / 2
	local cursor = atrium.Z2 - 12
	for tread = 1, Plan.StairTreads do
		local going = if tread % Plan.StairTierEvery == 0 then Plan.StairTierGoingStuds else Plan.StairGoingStuds
		local rise = tread * Plan.StairRiserStuds
		cursor -= going
		Kit.Block(folder, `LearnStair{tread}`, at(stairX, Plan.SlabStuds + rise - Plan.StairRiserStuds / 2, cursor + going / 2), Vector3.new(Plan.StairWidthStuds, Plan.StairRiserStuds, going), TIMBER, {
			material = Enum.Material.WoodPlanks,
		})
	end

	-- ---- reception: a floating desk and a polished accent wall behind it
	local desk = Plan.Reception()
	Kit.Block(folder, "ReceptionWall", at((desk.X1 + desk.X2) / 2, Plan.SlabStuds + 11, desk.Z1 - 3), Vector3.new(desk.X2 - desk.X1 + 24, 22, 1.5), TIMBER_DARK, {
		material = Enum.Material.Wood,
		reflectance = 0.08,
	})
	-- Floating: the top is a slab with no legs under it, held off the wall on a recessed base.
	Kit.Block(folder, "ReceptionDesk", at((desk.X1 + desk.X2) / 2, Plan.SlabStuds + 4.2, (desk.Z1 + desk.Z2) / 2), Vector3.new(desk.X2 - desk.X1, 1.2, desk.Z2 - desk.Z1), CONCRETE, {
		reflectance = 0.06,
	})
	Kit.Block(folder, "ReceptionBase", at((desk.X1 + desk.X2) / 2, Plan.SlabStuds + 2, (desk.Z1 + desk.Z2) / 2 + 2), Vector3.new(desk.X2 - desk.X1 - 16, 4.4, desk.Z2 - desk.Z1 - 8), TIMBER_DARK, {
		material = Enum.Material.Wood,
	})

	-- ---- room partitions, so the wings read as rooms rather than as one long shed
	for _, room in Plan.Rooms() do
		local base = if room.Floor == 1 then Plan.SlabStuds else Plan.GroundStoreyStuds + Plan.SlabStuds
		local height = if room.Floor == 1 then Plan.GroundClearStuds else Plan.UpperClearStuds
		Kit.Block(folder, `Partition_{room.Id}`, at((room.X1 + room.X2) / 2, base + height / 2, room.Z2), Vector3.new(room.X2 - room.X1, height, 1.5), CONCRETE, {
			material = Enum.Material.SmoothPlastic,
		})
	end

	Props.Static(folder, at)
	return folder
end

return Shell
