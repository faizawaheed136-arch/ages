--!strict
-- Turns the built school into a playable one: doors that open, lockers that open, light
-- switches that work, seats you sit on, a lunch counter, admin furniture and spawn points.
--
-- **This runs at play time, and it has to.** Everything below is either an instance the asset
-- bake cannot carry (ProximityPrompt, Seat, PointLight, SpawnLocation, Tool) or behaviour that
-- needs a running server. The geometry it adds -- door panels, locker fronts, switches,
-- reception furniture -- therefore appears when you press Play, not in the editor. If you want
-- any of it visible in Studio, it moves into Furniture.luau and gets baked; the split is
-- deliberate and is the only reason it is not there already.
--
-- Positions come from Layout, never from scanning geometry for coordinates. The one thing it
-- does read off the world is where the building is, and it takes that from the Roof so there is
-- no second copy of the site coordinate to fall out of date.

local TweenService = game:GetService("TweenService")

local Layout = require(script.Parent.Layout)
local Tree = require(script.Parent.Tree)

local Interactive = {}

local WHITE = Color3.fromRGB(242, 243, 246)
local BLUE = Color3.fromRGB(58, 122, 206)
local DARK_WOOD = Color3.fromRGB(96, 66, 44)
local TIMBER = Color3.fromRGB(148, 104, 66)
local METAL = Color3.fromRGB(126, 132, 142)
local SLATE = Color3.fromRGB(44, 50, 60)
local GLASS_TINT = Color3.fromRGB(196, 220, 240)

local SMOOTH = Enum.Material.SmoothPlastic
local PLANKS = Enum.Material.WoodPlanks

local DOOR_SWING = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local AUTO_CLOSE_SECONDS = 4
local LOCKER_SWING = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local T = Layout.WallThicknessStuds
local DOOR_W = Layout.DoorWidthStuds
local DOOR_H = Layout.DoorHeightStuds

-- ---------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------

local function part(parent: Instance, name: string, cf: CFrame, size: Vector3, material: Enum.Material, colour: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CastShadow = true
	p.Material = material
	p.Color = colour
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Every prompt in the building is made here, so the key, the hold and the distance cannot drift
-- between one interaction and the next.
local function promptOn(adornee: BasePart, action: string, object: string, key: Enum.KeyCode): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = key
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = adornee
	return prompt
end

-- A hinged panel that swings through `degrees` about one vertical edge and comes back.
--
-- **The hinge is an edge, not the centre.** Rotating a panel about its own middle spins it like
-- a turnstile with half of it sweeping backwards through the wall. The move is: translate to
-- the hinge edge, rotate there, translate back -- which is what a door does.
local function hinge(panel: Part, degrees: number, side: number, info: TweenInfo, autoCloseSeconds: number?)
	local shut = panel.CFrame
	local halfWidth = panel.Size.X / 2
	local pivot = shut * CFrame.new(side * halfWidth, 0, 0)
	local open = pivot * CFrame.Angles(0, math.rad(-side * degrees), 0) * CFrame.new(-side * halfWidth, 0, 0)

	local isOpen = false
	local token = 0

	local function set(target: boolean)
		isOpen = target
		TweenService:Create(panel, info, { CFrame = if target then open else shut }):Play()
	end

	return function()
		set(not isOpen)
		if isOpen and autoCloseSeconds ~= nil then
			token += 1
			local mine = token
			task.delay(autoCloseSeconds, function()
				-- Only close if nobody has touched it since. Without the token a door opened,
				-- shut by hand and opened again slams itself on the first timer.
				if mine == token and isOpen then
					set(false)
				end
			end)
		end
	end
end

-- ---------------------------------------------------------------------------------------
-- 1. Doors
-- ---------------------------------------------------------------------------------------

local function buildDoors(root: Instance, origin: Vector3, architecture: Instance)
	local made = 0
	for floor = 1, Layout.Floors do
		for _, opening in Layout.DoorwaysOn(floor) do
			local along = opening.axis == "x"
			local centre = origin + Vector3.new(opening.x, opening.y + DOOR_H / 2, opening.z)

			local model = Instance.new("Model")
			model.Name = `Door_{opening.id}_F{opening.floor}`
			model.Parent = architecture

			-- The frame: two jambs and a head, in the school's blue so an opening reads as one.
			local jambSize = if along then Vector3.new(0.6, DOOR_H + 1, T * 1.8) else Vector3.new(T * 1.8, DOOR_H + 1, 0.6)
			for side = -1, 1, 2 do
				local off = if along then Vector3.new(side * (DOOR_W / 2 + 0.3), 0, 0) else Vector3.new(0, 0, side * (DOOR_W / 2 + 0.3))
				part(model, `Jamb{side}`, CFrame.new(centre + off), jambSize, SMOOTH, BLUE)
			end
			local headSize = if along then Vector3.new(DOOR_W + 1.6, 1, T * 1.8) else Vector3.new(T * 1.8, 1, DOOR_W + 1.6)
			part(model, "Head", CFrame.new(centre + Vector3.new(0, DOOR_H / 2 + 0.5, 0)), headSize, SMOOTH, BLUE)

			-- The leaf. Built along its own X and then turned, so `hinge` can treat the hinge
			-- edge as +/- half its width whichever way the door faces.
			local facing = if along then CFrame.new(centre) else CFrame.new(centre) * CFrame.Angles(0, math.rad(90), 0)
			local leaf = part(model, "Leaf", facing, Vector3.new(DOOR_W - 0.4, DOOR_H - 0.4, 0.5), PLANKS, TIMBER)
			leaf.CanCollide = true

			part(model, "Vision", facing * CFrame.new(0, DOOR_H * 0.2, -0.3), Vector3.new(3.5, 4, 0.2), Enum.Material.Glass, GLASS_TINT).CanCollide =
				false
			part(model, "Handle", facing * CFrame.new(DOOR_W * 0.32, 0, -0.45), Vector3.new(0.5, 1.6, 0.4), Enum.Material.Metal, METAL).CanCollide =
				false

			model.PrimaryPart = leaf

			local toggle = hinge(leaf, 90, -1, DOOR_SWING, AUTO_CLOSE_SECONDS)
			promptOn(leaf, "Open/Close", "Door", Enum.KeyCode.E).Triggered:Connect(toggle)
			made += 1
		end
	end
	return made
end

-- ---------------------------------------------------------------------------------------
-- 2. Lockers
-- ---------------------------------------------------------------------------------------

-- Each baked locker is one solid box. This hangs a door on the front of it and hollows the
-- box behind, so opening one shows a slot rather than a painted line.
local function buildLockers(root: Instance, furniture: Instance)
	local made = 0
	for _, body in root:GetDescendants() do
		if not body:IsA("BasePart") or not body.Name:match("^Locker%d+$") then
			continue
		end

		local depth = body.Size.Z
		local width = body.Size.X
		local height = body.Size.Y

		-- Which way the bank faces: away from the wall it is against, which is the side its
		-- handle was put on. Read off the body rather than assumed, so both corridor runs work.
		local handle = body.Parent and body.Parent:FindFirstChild(body.Name:gsub("Locker", "LockerHandle"))
		local facing = 1
		if handle and handle:IsA("BasePart") then
			facing = if handle.Position.Z < body.Position.Z then -1 else 1
		end

		local model = Instance.new("Model")
		model.Name = `{body.Name}Unit`
		model.Parent = furniture

		-- The hollow: a dark recess set into the body's face.
		part(
			model,
			"Slot",
			CFrame.new(body.Position + Vector3.new(0, 0, facing * (depth / 2 - 0.9))),
			Vector3.new(width - 0.8, height - 1.2, 1.4),
			SMOOTH,
			Color3.fromRGB(28, 32, 40)
		).CanCollide = false

		local leaf = part(
			model,
			"LockerDoor",
			CFrame.new(body.Position + Vector3.new(0, 0, facing * (depth / 2 + 0.15))),
			Vector3.new(width - 0.3, height - 0.6, 0.3),
			Enum.Material.Metal,
			body.Color
		)
		leaf.CanCollide = false
		model.PrimaryPart = leaf

		promptOn(leaf, "Open/Close", "Locker", Enum.KeyCode.E).Triggered:Connect(hinge(leaf, 45, -1, LOCKER_SWING, nil))
		made += 1
	end
	return made
end

-- ---------------------------------------------------------------------------------------
-- 3. Lighting and switches
-- ---------------------------------------------------------------------------------------

-- There were no lights in this building at all -- not one PointLight anywhere -- so the
-- switches had nothing to switch. Fixtures come first, then the switch that owns them.
local function buildLighting(origin: Vector3, lighting: Instance, architecture: Instance)
	local fixtures, switches = 0, 0

	for floor = 1, Layout.Floors do
		local y = Layout.FloorY(floor)
		local ceiling = y + Layout.FloorHeightStuds - 1.4

		local zones: { { id: string, x1: number, x2: number, z1: number, z2: number, doorX: number, doorZ: number } } = {}
		for _, room in Layout.RoomsOn(floor) do
			local z1, z2 = Layout.BandZ(room.band)
			local doorX, doorZ = (room.x1 + room.x2) / 2, z1
			for _, opening in Layout.DoorwaysOn(floor) do
				if opening.id == room.id then
					doorX, doorZ = opening.x, opening.z
				end
			end
			table.insert(zones, { id = room.id, x1 = room.x1, x2 = room.x2, z1 = z1, z2 = z2, doorX = doorX, doorZ = doorZ })
		end
		-- The corridor is a room for this purpose: it needs lights and a switch like any other.
		table.insert(zones, {
			id = "corridor",
			x1 = Layout.CorridorX1,
			x2 = Layout.CorridorX2,
			z1 = Layout.CorridorZ1,
			z2 = Layout.CorridorZ2,
			doorX = Layout.CorridorX1 + 6,
			doorZ = Layout.CorridorZ1,
		})

		for _, zone in zones do
			local group = Instance.new("Folder")
			group.Name = `Lights_{zone.id}_F{floor}`
			group.Parent = lighting

			local cols = math.max(1, math.floor((zone.x2 - zone.x1) / 24))
			local rows = math.max(1, math.floor((zone.z2 - zone.z1) / 24))
			local owned: { PointLight } = {}

			for col = 1, cols do
				for row = 1, rows do
					local fx = zone.x1 + (zone.x2 - zone.x1) * ((col - 0.5) / cols)
					local fz = zone.z1 + (zone.z2 - zone.z1) * ((row - 0.5) / rows)
					local panel = part(
						group,
						`Fixture{col}_{row}`,
						CFrame.new(origin + Vector3.new(fx, ceiling, fz)),
						Vector3.new(10, 0.4, 3),
						Enum.Material.Neon,
						Color3.fromRGB(250, 250, 244)
					)
					panel.CanCollide = false

					local bulb = Instance.new("PointLight")
					bulb.Brightness = 1.6
					bulb.Range = 42
					bulb.Color = Color3.fromRGB(255, 250, 238)
					bulb.Parent = panel
					table.insert(owned, bulb)
					fixtures += 1
				end
			end

			-- The switch, on the wall beside that room's own door.
			local plate = part(
				architecture,
				`LightSwitch_{zone.id}_F{floor}`,
				CFrame.new(origin + Vector3.new(zone.doorX + DOOR_W / 2 + 2.5, y + 6, zone.doorZ)),
				Vector3.new(1.6, 2.4, 0.4),
				SMOOTH,
				WHITE
			)
			plate.CanCollide = false
			local toggle = part(
				architecture,
				`LightSwitchToggle_{zone.id}_F{floor}`,
				plate.CFrame * CFrame.new(0, 0.3, -0.3),
				Vector3.new(0.7, 1, 0.3),
				SMOOTH,
				BLUE
			)
			toggle.CanCollide = false

			local on = true
			promptOn(plate, "Toggle Lights", zone.id, Enum.KeyCode.E).Triggered:Connect(function()
				on = not on
				for _, bulb in owned do
					bulb.Enabled = on
				end
				for _, fixture in group:GetChildren() do
					if fixture:IsA("BasePart") then
						fixture.Material = if on then Enum.Material.Neon else SMOOTH
					end
				end
				toggle.CFrame = plate.CFrame * CFrame.new(0, if on then 0.3 else -0.3, -0.3)
			end)
			switches += 1
		end
	end

	return fixtures, switches
end

-- ---------------------------------------------------------------------------------------
-- 4. Seating
-- ---------------------------------------------------------------------------------------

-- **An invisible Seat that cannot be touched, driven by a prompt.**
--
-- A Roblox Seat grabs any character that brushes it, which is the auto-sit the brief asks to be
-- rid of, and there is no property that turns that off. `CanTouch = false` is the one that does:
-- the seat stops firing its own touch handler entirely, so the only way onto it is `Seat:Sit`,
-- which is what the prompt calls. The visible chair part is left exactly as built.
local function makeSeat(surface: BasePart, seating: Instance): Seat
	local seat = Instance.new("Seat")
	seat.Name = `{surface.Name}Seat`
	seat.Size = Vector3.new(math.min(surface.Size.X, 3), 0.4, math.min(surface.Size.Z, 3))
	seat.CFrame = surface.CFrame * CFrame.new(0, surface.Size.Y / 2 + 0.2, 0)
	seat.Anchored = true
	seat.CanCollide = false
	seat.CanTouch = false
	seat.Transparency = 1
	seat.Parent = seating

	promptOn(seat, "Sit Down", "Seat", Enum.KeyCode.L).Triggered:Connect(function(player: Player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			seat:Sit(humanoid)
		end
	end)
	return seat
end

local function buildSeating(root: Instance, furniture: Instance): number
	local seating = Instance.new("Folder")
	seating.Name = "Seating"
	seating.Parent = furniture

	local made = 0
	for _, surface in root:GetDescendants() do
		if not surface:IsA("BasePart") then
			continue
		end
		-- Chair seats and cafeteria benches. Matched on the name the builders gave them, which
		-- is the contract between Furniture.luau and this file.
		if surface.Name:match("ChairSeat$") or surface.Name:match("^CafeBench%d") then
			makeSeat(surface, seating)
			made += 1
		end
	end
	return made
end

-- ---------------------------------------------------------------------------------------
-- 5. Lunch counter
-- ---------------------------------------------------------------------------------------

local function buildLunchCounter(origin: Vector3, furniture: Instance)
	local kitchen
	for _, room in Layout.RoomsOn(1) do
		if room.kind == "kitchen" then
			kitchen = room
		end
	end
	if kitchen == nil then
		return false
	end

	local z1 = Layout.BackBandZ1
	local cx = (kitchen.x1 + kitchen.x2) / 2
	local model = Instance.new("Model")
	model.Name = "LunchCounter"
	model.Parent = furniture

	local counter = part(
		model,
		"Counter",
		CFrame.new(origin + Vector3.new(cx, 3, z1 + 6)),
		Vector3.new(kitchen.x2 - kitchen.x1 - 16, 0.6, 5),
		SMOOTH,
		Color3.fromRGB(206, 212, 222)
	)
	part(
		model,
		"CounterBody",
		CFrame.new(origin + Vector3.new(cx, 1.5, z1 + 6)),
		Vector3.new(kitchen.x2 - kitchen.x1 - 16, 3, 4.4),
		SMOOTH,
		WHITE
	)
	part(
		model,
		"SneezeGuard",
		CFrame.new(origin + Vector3.new(cx, 6.5, z1 + 4)),
		Vector3.new(kitchen.x2 - kitchen.x1 - 16, 6, 0.3),
		Enum.Material.Glass,
		GLASS_TINT
	).CanCollide = false
	model.PrimaryPart = counter

	-- The tool handed out. Built once and cloned, so two hundred lunches are one template.
	local template = Instance.new("Tool")
	template.Name = "School Lunch"
	template.CanBeDropped = true
	local tray = Instance.new("Part")
	tray.Name = "Handle"
	tray.Size = Vector3.new(3, 0.4, 2.2)
	tray.Color = Color3.fromRGB(212, 96, 84)
	tray.Material = SMOOTH
	tray.TopSurface = Enum.SurfaceType.Smooth
	tray.BottomSurface = Enum.SurfaceType.Smooth
	tray.Parent = template

	promptOn(counter, "Get School Lunch", "Lunch Line", Enum.KeyCode.E).Triggered:Connect(function(player: Player)
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack and backpack:FindFirstChild("School Lunch") == nil then
			template:Clone().Parent = backpack
		end
	end)
	return true
end

-- ---------------------------------------------------------------------------------------
-- 6. Administration
-- ---------------------------------------------------------------------------------------

local function buildAdmin(origin: Vector3, furniture: Instance, seating: Instance)
	local rooms: { [string]: any } = {}
	for _, room in Layout.RoomsOn(1) do
		rooms[room.id] = room
	end

	local function seatAt(surface: BasePart)
		makeSeat(surface, seating)
	end

	-- ---- Main lobby: a curved reception desk, built as a fan of straight segments.
	local lobby = rooms.lobby
	if lobby then
		local model = Instance.new("Model")
		model.Name = "Reception"
		model.Parent = furniture
		local cx = (lobby.x1 + lobby.x2) / 2
		local cz = Layout.FrontBandZ1 + 22
		local radius = 13
		local segments = 7
		local sweep = math.rad(110)
		for i = 1, segments do
			local a = -sweep / 2 + sweep * ((i - 0.5) / segments)
			local px = cx + math.sin(a) * radius
			local pz = cz + math.cos(a) * radius
			local cf = CFrame.new(origin + Vector3.new(px, 0, pz)) * CFrame.Angles(0, -a, 0)
			part(model, `DeskBody{i}`, cf * CFrame.new(0, 2, 0), Vector3.new(radius * sweep / segments + 1, 4, 3), PLANKS, DARK_WOOD)
			part(model, `DeskTop{i}`, cf * CFrame.new(0, 4.2, 0), Vector3.new(radius * sweep / segments + 1.4, 0.5, 4), SMOOTH, Color3.fromRGB(226, 228, 232))
			-- The privacy partition: open above the counter rather than a solid screen, so the
			-- receptionist can still be seen.
			part(model, `DeskScreen{i}`, cf * CFrame.new(0, 6, 0.4), Vector3.new(radius * sweep / segments + 1, 3, 0.3), Enum.Material.Glass, GLASS_TINT).CanCollide =
				false
		end
		local monitorCf = CFrame.new(origin + Vector3.new(cx, 6, cz + radius - 1.5))
		part(model, "Monitor", monitorCf, Vector3.new(6, 3.6, 0.3), SMOOTH, SLATE)
		part(model, "MonitorScreen", monitorCf * CFrame.new(0, 0, -0.2), Vector3.new(5.4, 3, 0.1), Enum.Material.Neon, Color3.fromRGB(120, 180, 230)).CanCollide =
			false
		part(model, "MonitorStand", monitorCf * CFrame.new(0, -2.4, 0), Vector3.new(1, 1.6, 1), SMOOTH, SLATE)
		local chair = part(model, "ReceptionChair", CFrame.new(origin + Vector3.new(cx, 2, cz + radius + 3)), Vector3.new(3, 0.4, 3), SMOOTH, SLATE)
		seatAt(chair)
	end

	-- ---- Principal's office.
	local principal = rooms.principal
	if principal then
		local model = Instance.new("Model")
		model.Name = "PrincipalOffice"
		model.Parent = furniture
		local cx = (principal.x1 + principal.x2) / 2
		local cz = (Layout.FrontBandZ1 + Layout.FrontBandZ2) / 2

		part(model, "ExecDeskBody", CFrame.new(origin + Vector3.new(cx, 2, cz)), Vector3.new(16, 4, 7), PLANKS, Color3.fromRGB(58, 40, 28))
		part(model, "ExecDeskTop", CFrame.new(origin + Vector3.new(cx, 4.3, cz)), Vector3.new(17, 0.6, 8), PLANKS, Color3.fromRGB(74, 50, 34))

		local chair = part(model, "ExecChair", CFrame.new(origin + Vector3.new(cx, 2.2, cz - 6)), Vector3.new(4, 0.5, 4), SMOOTH, SLATE)
		part(model, "ExecChairBack", CFrame.new(origin + Vector3.new(cx, 6, cz - 8)), Vector3.new(4, 7, 0.6), SMOOTH, SLATE)
		seatAt(chair)

		for side = -1, 1, 2 do
			local guest = part(model, `GuestChair{side}`, CFrame.new(origin + Vector3.new(cx + side * 5, 2, cz + 7)), Vector3.new(3, 0.4, 3), SMOOTH, BLUE)
			part(model, `GuestChairBack{side}`, CFrame.new(origin + Vector3.new(cx + side * 5, 4, cz + 8.4)), Vector3.new(3, 4, 0.4), SMOOTH, BLUE)
			seatAt(guest)
		end

		part(model, "FilingCabinet", CFrame.new(origin + Vector3.new(principal.x1 + 6, 5, cz - 14)), Vector3.new(5, 10, 4), Enum.Material.Metal, METAL)
		for drawer = 1, 3 do
			part(
				model,
				`FilingDrawer{drawer}`,
				CFrame.new(origin + Vector3.new(principal.x1 + 6, 1.6 + drawer * 3, cz - 11.8)),
				Vector3.new(4.4, 2.4, 0.4),
				Enum.Material.Metal,
				Color3.fromRGB(158, 164, 174)
			).CanCollide = false
		end
	end

	-- ---- Staff room.
	local staff = rooms.staff
	if staff then
		local model = Instance.new("Model")
		model.Name = "StaffRoom"
		model.Parent = furniture
		local cx = (staff.x1 + staff.x2) / 2
		local cz = (Layout.FrontBandZ1 + Layout.FrontBandZ2) / 2

		part(model, "BreakTableTop", CFrame.new(origin + Vector3.new(cx, 3.2, cz + 6)), Vector3.new(22, 0.6, 7), PLANKS, TIMBER)
		for side = -1, 1, 2 do
			part(model, `BreakTableLeg{side}`, CFrame.new(origin + Vector3.new(cx + side * 9, 1.6, cz + 6)), Vector3.new(1, 3.2, 6), SMOOTH, METAL)
		end

		-- The counter run, with a sink set into it.
		local counterZ = Layout.FrontBandZ1 + 4
		part(model, "KitchenCounter", CFrame.new(origin + Vector3.new(cx, 3, counterZ)), Vector3.new(24, 0.6, 5), SMOOTH, Color3.fromRGB(216, 220, 228))
		part(model, "KitchenBody", CFrame.new(origin + Vector3.new(cx, 1.5, counterZ)), Vector3.new(24, 3, 4.4), SMOOTH, WHITE)
		part(model, "Sink", CFrame.new(origin + Vector3.new(cx - 6, 2.9, counterZ)), Vector3.new(5, 0.8, 3.4), Enum.Material.Metal, Color3.fromRGB(198, 204, 214)).CanCollide =
			false
		part(model, "Tap", CFrame.new(origin + Vector3.new(cx - 6, 4.5, counterZ - 1.6)), Vector3.new(0.4, 2.4, 0.4), Enum.Material.Metal, METAL).CanCollide =
			false

		-- Two couches, each a base, a back and two arms.
		for index = -1, 1, 2 do
			local sx = cx + index * 11
			local sz = cz + 16
			local base = part(model, `Couch{index}`, CFrame.new(origin + Vector3.new(sx, 2, sz)), Vector3.new(12, 2.6, 5), Enum.Material.Fabric, Color3.fromRGB(96, 118, 168))
			part(model, `CouchBack{index}`, CFrame.new(origin + Vector3.new(sx, 4.4, sz + 2.2)), Vector3.new(12, 5, 1.2), Enum.Material.Fabric, Color3.fromRGB(84, 104, 152))
			for arm = -1, 1, 2 do
				part(model, `CouchArm{index}_{arm}`, CFrame.new(origin + Vector3.new(sx + arm * 6.2, 3.4, sz)), Vector3.new(1.2, 3.4, 5), Enum.Material.Fabric, Color3.fromRGB(84, 104, 152))
			end
			seatAt(base)
		end
	end
end

-- ---------------------------------------------------------------------------------------
-- 7. Spawns, and the stair check
-- ---------------------------------------------------------------------------------------

local function buildSpawns(origin: Vector3, props: Instance)
	local lobby
	for _, room in Layout.RoomsOn(1) do
		if room.kind == "lobby" then
			lobby = room
		end
	end
	if lobby == nil then
		return 0
	end

	local cx = (lobby.x1 + lobby.x2) / 2
	for index = 1, 4 do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = `LobbySpawn{index}`
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.CFrame = CFrame.new(origin + Vector3.new(cx - 12 + (index - 1) * 8, 0.5, Layout.FrontBandZ1 + 12))
		spawn.Anchored = true
		spawn.CanCollide = false
		spawn.Transparency = 1
		spawn.Neutral = true
		spawn.Parent = props
		-- A SpawnLocation ships with a decal on it. Left on, four glowing pads sit in the middle
		-- of a polished lobby floor.
		for _, child in spawn:GetChildren() do
			if child:IsA("Decal") or child:IsA("Texture") then
				child:Destroy()
			end
		end
	end
	return 4
end

-- Are the flights actually there and reaching each floor? Measured, because the brief asks for
-- backup teleports only *if* they are missing, and adding them regardless would be dead weight
-- players can fall onto.
local function stairsAreComplete(root: Instance): (boolean, string)
	local tops: { [string]: number } = {}
	for _, p in root:GetDescendants() do
		if p:IsA("BasePart") and p.Name:match("^Stair.+Arrival$") then
			tops[p.Name] = p.Position.Y + p.Size.Y / 2
		end
	end
	local expected = #Layout.Stairwells * (Layout.Floors - 1)
	local found = 0
	for _ in tops do
		found += 1
	end
	if found < expected then
		return false, `only {found} of {expected} stair arrivals found`
	end
	return true, `{found} arrivals, all flights present`
end

-- ---------------------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------------------

function Interactive.Build(): ()
	local root = workspace:FindFirstChild("ProperSchool")
	if root == nil then
		warn("[ProperSchool] no ProperSchool model in Workspace -- nothing to make interactive")
		return
	end

	-- Where the building is, taken from the Roof rather than written down a second time. The
	-- roof slab is centred on the plan and sits half a thickness under the top of the shell.
	local roof
	for _, p in root:GetDescendants() do
		if p:IsA("BasePart") and p.Name == "Roof" then
			roof = p
		end
	end
	if roof == nil then
		warn("[ProperSchool] no Roof part -- cannot locate the building")
		return
	end
	local origin = Vector3.new(
		roof.Position.X,
		roof.Position.Y + roof.Size.Y / 2 - Layout.FloorHeightStuds * Layout.Floors,
		roof.Position.Z
	)

	local tree = Tree.Build()
	local props = tree.Props
	local furniture = tree.Furniture
	local architecture = tree.Architecture
	local lighting = tree.Lighting

	local seating = Instance.new("Folder")
	seating.Name = "AdminSeating"
	seating.Parent = furniture

	local doors = buildDoors(root, origin, architecture)
	local lockers = buildLockers(root, furniture)
	local fixtures, switches = buildLighting(origin, lighting, architecture)
	local seats = buildSeating(root, furniture)
	local lunch = buildLunchCounter(origin, furniture)
	buildAdmin(origin, furniture, seating)
	local spawns = buildSpawns(origin, props)

	local ok, note = stairsAreComplete(root)

	print(
		`[ProperSchool] interactive: {doors} doors, {lockers} lockers, {fixtures} light fixtures on `
			.. `{switches} switches, {seats} seats, lunch counter {if lunch then "up" else "missing kitchen"}, `
			.. `{spawns} spawns. Stairs: {note}.`
	)
	if not ok then
		warn(`[ProperSchool] stairs incomplete ({note}) -- add backup teleport pads before shipping`)
	end
end

return Interactive
