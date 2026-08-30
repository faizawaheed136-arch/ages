--!strict
-- The interactive layer for the editable copy of v1: doors, lockers, light switches, seats.
--
-- **Scoped to `Workspace.SchoolV1Copy` and nothing else.** v1 has its own interactivity through
-- FixtureService, which scans `Workspace.School`; the two never touch the same model, which is
-- the whole point of the copy existing. If this file ever starts scanning `School`, it has
-- become an edit to v1.
--
-- **Everything is derived from the parts already in the model.** No coordinates are written
-- down here and no plan is imported: a door tells you where its room is, a locker bank tells
-- you how wide it is and which way it faces. That matters because the copy is a fork whose
-- dimensions are meant to change -- anything hardcoded here would be wrong the first time
-- somebody widens a corridor in SchoolCopy.luau.
--
-- Runs at play time, because every instance it makes -- ProximityPrompt, Seat, PointLight --
-- is one the asset bake cannot carry.

local TweenService = game:GetService("TweenService")

local Interactive = {}

local MODEL_NAME = "SchoolV1Copy"

local BLUE = Color3.fromRGB(58, 122, 206)
local METAL = Color3.fromRGB(126, 132, 142)
local WHITE = Color3.fromRGB(242, 243, 246)
local SMOOTH = Enum.Material.SmoothPlastic

local DOOR_SWING = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LOCKER_SWING = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local AUTO_CLOSE_SECONDS = 4
local DOOR_DEGREES = 90
local LOCKER_DEGREES = 45

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

-- One place makes every prompt, so the key, the hold and the wording cannot drift apart across
-- four different kinds of interaction.
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

-- A panel that swings about one vertical edge.
--
-- **The hinge is an edge, not the centre.** Rotating about the middle spins the panel like a
-- turnstile and sweeps half of it backwards through the wall it is set in.
local function hinged(panel: BasePart, degrees: number, info: TweenInfo, autoCloseSeconds: number?)
	local shut = panel.CFrame
	local half = panel.Size.X / 2
	local pivot = shut * CFrame.new(-half, 0, 0)
	local open = pivot * CFrame.Angles(0, math.rad(degrees), 0) * CFrame.new(half, 0, 0)

	local isOpen = false
	local token = 0

	local function set(target: boolean)
		isOpen = target
		TweenService:Create(panel, info, { CFrame = if target then open else shut }):Play()
	end

	return function()
		set(not isOpen)
		if isOpen and autoCloseSeconds ~= nil then
			-- The token is what stops a door that was opened, shut by hand and opened again from
			-- being slammed by the first timer four seconds after the first press.
			token += 1
			local mine = token
			task.delay(autoCloseSeconds, function()
				if mine == token and isOpen then
					set(false)
				end
			end)
		end
	end
end

-- ---------------------------------------------------------------------------------------
-- Doors
-- ---------------------------------------------------------------------------------------

local function wireDoors(root: Instance): number
	local made = 0
	for _, leaf in root:GetDescendants() do
		if leaf:IsA("BasePart") and leaf.Name:match("DoorLeaf") then
			-- The leaves are already built and in the right place; they were simply never
			-- movable. Making them collidable is what turns a decorative panel into a door --
			-- a leaf you can walk through is a picture of a door.
			leaf.CanCollide = true
			promptOn(leaf, "Interact", "Door", Enum.KeyCode.E).Triggered:Connect(
				hinged(leaf, DOOR_DEGREES, DOOR_SWING, AUTO_CLOSE_SECONDS)
			)
			made += 1
		end
	end
	return made
end

-- ---------------------------------------------------------------------------------------
-- Lockers
-- ---------------------------------------------------------------------------------------

-- The copy's lockers are baked as long solid banks with seams painted on. The brief wants a
-- panel per locker, so each bank is divided at its own seam pitch and a real door hung in front
-- of every division.
--
-- Width and facing are read off the bank rather than assumed: the corridor-side run and the
-- room-side segments face opposite ways, and the room-side ones vary in length because they sit
-- between classroom doors.
local function wireLockers(root: Instance, into: Instance, corridorZ: number): number
	local made = 0
	for _, bank in root:GetDescendants() do
		if not bank:IsA("BasePart") then
			continue
		end
		if not (bank.Name:match("^LockerBank%d+$") or bank.Name:match("^RoomSideLocker%d+_%d+$")) then
			continue
		end

		-- Which face is the open one: whichever side of the bank points at the middle of the
		-- corridor. Both runs are flush to a wall, so the corridor is always the way out.
		local facing = if bank.Position.Z < corridorZ then 1 else -1
		local doors = math.max(2, math.floor(bank.Size.X / 5))
		local doorW = bank.Size.X / doors
		local faceZ = bank.Position.Z + facing * (bank.Size.Z / 2)

		for index = 1, doors do
			local dx = bank.Position.X - bank.Size.X / 2 + doorW * (index - 0.5)
			local leaf = part(
				into,
				`{bank.Name}Door{index}`,
				CFrame.new(dx, bank.Position.Y, faceZ + facing * 0.3),
				Vector3.new(doorW - 0.3, bank.Size.Y - 0.4, 0.4),
				Enum.Material.Metal,
				bank.Color
			)
			leaf.CanCollide = false
			-- A dark slot behind it, so an open locker shows a hollow rather than the painted
			-- back of the bank.
			part(
				into,
				`{bank.Name}Slot{index}`,
				CFrame.new(dx, bank.Position.Y, faceZ - facing * 0.9),
				Vector3.new(doorW - 0.8, bank.Size.Y - 1.4, 1.4),
				SMOOTH,
				Color3.fromRGB(28, 32, 40)
			).CanCollide = false

			-- A handle, offset well clear of the panel face. Anything sitting on a surface has
			-- to stand off it by more than the build grid, or it gets rounded back inside the
			-- thing it is meant to sit on -- a bug this project has now found four separate times.
			part(
				into,
				`{bank.Name}Handle{index}`,
				CFrame.new(dx + doorW * 0.28, bank.Position.Y, faceZ + facing * 0.9),
				Vector3.new(0.4, 1.6, 0.3),
				Enum.Material.Metal,
				METAL
			).CanCollide = false

			promptOn(leaf, "Interact", "Locker", Enum.KeyCode.E).Triggered:Connect(
				hinged(leaf, LOCKER_DEGREES, LOCKER_SWING, nil)
			)
			made += 1
		end
	end
	return made
end

-- ---------------------------------------------------------------------------------------
-- Lights and switches
-- ---------------------------------------------------------------------------------------

-- A switch beside every door, owning the fittings in the room behind it.
--
-- The room's extent is not looked up anywhere: the fittings are stepped back from the door
-- along the direction the room lies in, which the door itself gives. That keeps this correct
-- when the copy's room sizes change, which they are expected to.
local function wireLights(root: Instance, lighting: Instance, architecture: Instance, corridorZ: number): (number, number)
	local fixtures, switches = 0, 0

	for _, leaf in root:GetDescendants() do
		if not (leaf:IsA("BasePart") and leaf.Name:match("DoorLeaf")) then
			continue
		end
		-- Into the room, away from the corridor.
		local inward = if leaf.Position.Z < corridorZ then -1 else 1
		local ceilingY = leaf.Position.Y + leaf.Size.Y / 2 + 8

		local group = Instance.new("Folder")
		group.Name = `Lights_{leaf.Name}`
		group.Parent = lighting

		local owned: { PointLight } = {}
		for step = 1, 3 do
			local panel = part(
				group,
				`Fixture{step}`,
				CFrame.new(leaf.Position.X, ceilingY, leaf.Position.Z + inward * (10 + step * 16)),
				Vector3.new(10, 0.4, 3),
				Enum.Material.Neon,
				Color3.fromRGB(250, 250, 244)
			)
			panel.CanCollide = false
			local bulb = Instance.new("PointLight")
			bulb.Brightness = 1.6
			bulb.Range = 44
			bulb.Color = Color3.fromRGB(255, 250, 238)
			bulb.Parent = panel
			table.insert(owned, bulb)
			fixtures += 1
		end

		local plate = part(
			architecture,
			`LightSwitch_{leaf.Name}`,
			CFrame.new(leaf.Position.X + leaf.Size.X / 2 + 3, leaf.Position.Y, leaf.Position.Z),
			Vector3.new(1.6, 2.4, 0.4),
			SMOOTH,
			WHITE
		)
		plate.CanCollide = false
		local toggle = part(architecture, `LightSwitchToggle_{leaf.Name}`, plate.CFrame * CFrame.new(0, 0.3, -0.3), Vector3.new(0.7, 1, 0.3), SMOOTH, BLUE)
		toggle.CanCollide = false

		local on = true
		promptOn(plate, "Interact", "Lights", Enum.KeyCode.E).Triggered:Connect(function()
			on = not on
			for _, bulb in owned do
				bulb.Enabled = on
			end
			-- The panel drops off Neon too. A dark room whose ceiling still glows reads as
			-- broken rather than as off.
			for _, fixture in group:GetChildren() do
				if fixture:IsA("BasePart") then
					fixture.Material = if on then Enum.Material.Neon else SMOOTH
				end
			end
			toggle.CFrame = plate.CFrame * CFrame.new(0, if on then 0.3 else -0.3, -0.3)
		end)
		switches += 1
	end

	return fixtures, switches
end

-- ---------------------------------------------------------------------------------------
-- Seating
-- ---------------------------------------------------------------------------------------

-- **An invisible Seat with CanTouch off, driven by the prompt.**
--
-- A Roblox Seat grabs anyone who brushes it and there is no property that disables that.
-- `CanTouch = false` is the one that does: the seat stops firing its own touch handler, so
-- `Seat:Sit` becomes the only way onto it -- which is exactly the manual seating the brief
-- asks for. The visible chair the builder made is left untouched.
local SEATABLE = { "^Chair", "Stool%d*$", "^LoungeSofa%d+$", "^CafeBench", "Bench%d*$" }

local function wireSeats(root: Instance, into: Instance): number
	local made = 0
	for _, surface in root:GetDescendants() do
		if not surface:IsA("BasePart") then
			continue
		end
		local match = false
		for _, pattern in SEATABLE do
			if surface.Name:match(pattern) then
				match = true
				break
			end
		end
		-- Legs and backs are not seats. Without this every chair gets three prompts stacked on
		-- top of each other and the player picks one at random.
		if not match or surface.Name:match("Leg") or surface.Name:match("Back") then
			continue
		end

		local seat = Instance.new("Seat")
		seat.Name = `{surface.Name}Seat`
		seat.Size = Vector3.new(math.min(surface.Size.X, 3), 0.4, math.min(surface.Size.Z, 3))
		seat.CFrame = surface.CFrame * CFrame.new(0, surface.Size.Y / 2 + 0.2, 0)
		seat.Anchored = true
		seat.CanCollide = false
		seat.CanTouch = false
		seat.Transparency = 1
		seat.Parent = into

		promptOn(seat, "Sit Down", "Seat", Enum.KeyCode.L).Triggered:Connect(function(player: Player)
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				seat:Sit(humanoid)
			end
		end)
		made += 1
	end
	return made
end

-- ---------------------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------------------

function Interactive.Build(): ()
	local root = workspace:FindFirstChild(MODEL_NAME)
	if root == nil then
		warn(`[{MODEL_NAME}] not in Workspace -- nothing to make interactive`)
		return
	end

	-- Where the corridor runs, measured rather than assumed: the locker banks are flush to its
	-- two walls, so the midpoint between them is the corridor's centreline. That is what tells
	-- every other loop which way is "out of the wall" and which way is "into the room".
	local wallZ: { number } = {}
	for _, p in root:GetDescendants() do
		if p:IsA("BasePart") and p.Name:match("^LockerBank%d+$") then
			table.insert(wallZ, p.Position.Z)
		end
		if p:IsA("BasePart") and p.Name:match("^RoomSideLocker%d+_%d+$") then
			table.insert(wallZ, p.Position.Z)
		end
	end
	if #wallZ == 0 then
		warn(`[{MODEL_NAME}] no locker banks found -- cannot locate the corridor`)
		return
	end
	local lo, hi = wallZ[1], wallZ[1]
	for _, z in wallZ do
		lo = math.min(lo, z)
		hi = math.max(hi, z)
	end
	local corridorZ = (lo + hi) / 2

	local folders = {}
	for _, name in { "Furniture", "Architecture", "Lighting", "Seating" } do
		local existing = root:FindFirstChild(name)
		if existing == nil then
			local made = Instance.new("Folder")
			made.Name = name
			made.Parent = root
			existing = made
		end
		folders[name] = existing
	end

	local doors = wireDoors(root)
	local lockers = wireLockers(root, folders.Furniture, corridorZ)
	local fixtures, switches = wireLights(root, folders.Lighting, folders.Architecture, corridorZ)
	local seats = wireSeats(root, folders.Seating)

	print(
		`[{MODEL_NAME}] interactive: {doors} doors (E, 90 deg, {AUTO_CLOSE_SECONDS}s auto-close), `
			.. `{lockers} locker panels (E, {LOCKER_DEGREES} deg), {fixtures} fittings on {switches} switches (E), `
			.. `{seats} seats (L). Corridor centreline z={string.format("%.1f", corridorZ)}.`
	)
end

return Interactive
