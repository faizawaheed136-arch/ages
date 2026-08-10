--!strict
-- Builds one stage per player and stands their avatar on it.
--
-- The screen is a composed shot of *your* character, so every player gets their own copy of
-- the set, `Config.Lobby.Stage.Spacing` studs along X from the last one. See that Config
-- entry for why this beats the two obvious alternatives.
--
-- Stage indices are recycled, not incremented. A lobby server that ran for an hour would
-- otherwise build its twentieth stage eight thousand studs out, and Roblox's floating-point
-- precision starts visibly shaking a character somewhere past ten thousand -- so an
-- unbounded counter is a bug that only appears on a busy server that has been up a while,
-- which is the worst kind.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Stage = require(script.Parent.Parent.content.Stage)

type Piece = Stage.Piece

-- The names the client looks for. Written out here and in `StageCamera` and nowhere else;
-- they are the whole interface between the two halves of the lobby.
--
-- Deliberately *not* CollectionService tags. A tag is a set, and the client needs to find
-- the one mark belonging to *this* player -- so the lookup has to be by name under a folder
-- named after them, which a tag cannot express without a second attribute doing the real
-- work anyway.
local STAGE_FOLDER = "AgesLobbyStages"
local MARK_NAME = "Mark"
local CAMERA_NAME = "CameraSpot"

local StageService = {}

-- index -> player, so a departing player's index can be found and freed. Keyed the way it
-- is asked about: `release` knows the player, and `claim` needs the lowest free index.
local occupants: { [number]: Player } = {}
local stages: { [Player]: Folder } = {}

-- The parts that turn, gathered as they are built.
--
-- Kept as a list rather than found each frame by walking the stage and asking every part for
-- an attribute. Six spinners out of twenty-five parts per player means five-sixths of that
-- walk is wasted, every frame, for every player in the lobby -- and the cost grows with the
-- scenery rather than with the animation, which is the wrong thing for it to grow with.
local spinners: { [Player]: { { part: BasePart, rate: number } } } = {}

local function indexOf(player: Player): number?
	for index, occupant in occupants do
		if occupant == player then
			return index
		end
	end
	return nil
end

local function claim(player: Player): number
	local index = 1
	while occupants[index] ~= nil do
		index += 1
	end
	occupants[index] = player
	return index
end

local function release(player: Player)
	for index, occupant in occupants do
		if occupant == player then
			occupants[index] = nil
		end
	end
end

-- Where the nth stage stands in the world.
local function originFor(index: number): Vector3
	return Stage.Origin() + Vector3.new((index - 1) * Config.Lobby.Stage.Spacing, 0, 0)
end

local function build(piece: Piece, origin: Vector3, parent: Folder): BasePart
	local part = Instance.new("Part")
	part.Name = piece.name
	part.Size = piece.size
	part.Anchored = true
	part.Locked = true
	-- Nothing on the stage is walked into, so only the disc is solid -- see `Piece.solid`.
	-- A collidable pillar is something a character can get wedged against in the moment
	-- before it is anchored, and buys nothing at all in return.
	--
	-- `CanQuery` follows `CanCollide` rather than being off everywhere, because the Humanoid's
	-- ground check is a raycast: a disc that collides but cannot be queried is a floor the
	-- character rests on and the state machine cannot see.
	part.CanCollide = piece.solid == true
	part.CanQuery = piece.solid == true
	part.CanTouch = false
	-- Lights and glow do not cast. The light check was always here; the transparency check
	-- arrived with the halo, which is a twenty-six stud disc four studs behind somebody's head
	-- -- exactly the shape that, left casting, drops the character into its own shadow.
	part.CastShadow = piece.light == nil and (piece.transparency or 0) < 0.5
	part.Shape = piece.shape or Enum.PartType.Block
	part.Color = piece.color
	part.Material = piece.material
	part.Transparency = piece.transparency or 0
	part.Reflectance = piece.reflectance or 0

	local rotation = piece.rotation or Vector3.zero
	part.CFrame = CFrame.new(origin + piece.offset)
		* CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))

	if piece.light ~= nil then
		local light = Instance.new("PointLight")
		light.Color = piece.light.color
		light.Range = piece.light.range
		light.Brightness = piece.light.brightness
		-- Off, because a dozen shadow-casting point lights on one stage is the single most
		-- expensive thing this place could do, and none of them is the key light shaping the
		-- character -- that one is a PointLight too, and the sun does the shadow work.
		light.Shadows = false
		light.Parent = part
	end

	part.Parent = parent
	return part
end

-- An invisible, non-colliding anchor used as a position and nothing else.
local function marker(name: string, at: CFrame, parent: Folder): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.one
	part.Anchored = true
	part.Locked = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.CFrame = at
	part.Parent = parent
	return part
end

local function root(): Folder
	local existing = Workspace:FindFirstChild(STAGE_FOLDER)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = STAGE_FOLDER
	folder.Parent = Workspace
	return folder
end

-- The framing, derived once and used by both the camera marker and the direction the
-- character is turned to face.
--
-- The avatar faces the camera rather than the camera facing a fixed direction, which is the
-- only way round that survives moving `CameraOffset`: turn the camera and the character
-- turns with it, instead of ending up in profile.
local function framing(origin: Vector3): (CFrame, CFrame)
	local settings = Config.Lobby.Stage
	local eye = origin + settings.CameraOffset
	local target = origin + settings.CameraLookAt
	local camera = CFrame.lookAt(eye, target)

	-- Flattened to the horizontal before the character is turned to it. A character told to
	-- look at a camera four studs above its head tips over backwards.
	local toCamera = Vector3.new(eye.X - origin.X, 0, eye.Z - origin.Z)
	local facing = CFrame.lookAt(origin, origin + toCamera.Unit)
	return camera, facing
end

-- Where this player's character should stand, as a full CFrame including the turn.
local function markCFrame(player: Player): CFrame?
	local folder = stages[player]
	if folder == nil then
		return nil
	end
	local mark = folder:FindFirstChild(MARK_NAME)
	if mark == nil or not mark:IsA("BasePart") then
		return nil
	end
	return mark.CFrame
end

-- Build (or rebuild) this player's stage. Safe to call twice: the old folder is destroyed
-- first, so a Rojo sync mid-session leaves one stage rather than two overlapping ones.
function StageService.Ensure(player: Player): Folder
	local existing = stages[player]
	if existing ~= nil then
		existing:Destroy()
		stages[player] = nil
	end
	-- Reused if they already had one, so a rebuild cannot leak an index -- and so a player
	-- whose stage is rebuilt does not slide sideways into a different one while the camera
	-- is still pointed at the old spot.
	local index = indexOf(player) or claim(player)

	local origin = originFor(index)
	local folder = Instance.new("Folder")
	folder.Name = `Stage_{player.UserId}`

	local turning: { { part: BasePart, rate: number } } = {}
	for _, piece in Stage.Pieces() do
		local part = build(piece, origin, folder)
		if piece.spin ~= nil then
			table.insert(turning, { part = part, rate = piece.spin })
		end
	end
	spinners[player] = turning

	local camera, facing = framing(origin)
	marker(MARK_NAME, facing, folder)
	marker(CAMERA_NAME, camera, folder)

	folder.Parent = root()
	stages[player] = folder
	return folder
end

-- Put the character on the mark and keep it there.
--
-- Anchoring the root is what actually holds it; the speed and jump zeroing is so the
-- Humanoid does not spend the whole lobby trying to walk and playing the walk animation
-- against an anchored root. Both are needed and neither is sufficient.
function StageService.Place(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or rootPart == nil or not rootPart:IsA("BasePart") then
		warn(`[AGES] lobby: {player.Name}'s character has no Humanoid or HumanoidRootPart, so it cannot be stood on the mark.`)
		return
	end

	local mark = markCFrame(player)
	if mark == nil then
		warn(`[AGES] lobby: no stage for {player.Name} yet -- StageService.Ensure must run before Place.`)
		return
	end

	humanoid.WalkSpeed = 0
	humanoid.JumpHeight = 0
	humanoid.JumpPower = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)

	-- Raised by half the root's height so the feet meet the disc rather than sinking into
	-- it. Read off the part rather than hardcoded, because a scaled avatar has a taller root
	-- and R6 has a shorter one.
	rootPart.CFrame = mark + Vector3.new(0, rootPart.Size.Y / 2 + humanoid.HipHeight, 0)
	rootPart.Anchored = true

	-- Told explicitly rather than left to the state machine to work out. The character was
	-- put here rather than walking here, and an anchored root generates no physics step for
	-- the Humanoid to notice, so without this it can stay in whatever state it arrived in --
	-- which on a fresh spawn is Freefall, and Freefall means the falling pose and no idle
	-- animation. The first thing the player sees of themselves should not be a fall.
	humanoid:ChangeState(Enum.HumanoidStateType.Landed)
end

local function onCharacterAdded(player: Player, character: Model)
	-- The character model arrives before its parts do on a fresh join. Placing it before the
	-- root exists silently does nothing, which would leave the player falling through the
	-- void off-camera with no error anywhere.
	if character:FindFirstChild("HumanoidRootPart") == nil then
		character:WaitForChild("HumanoidRootPart", 10)
	end
	if character.Parent == nil or player.Parent ~= Players then
		return
	end
	StageService.Place(player, character)
end

local function onPlayerAdded(player: Player)
	StageService.Ensure(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	-- Loaded by hand, which is the whole reason `CharacterAutoLoads` is turned off in `Init`.
	--
	-- Automatic loading races this function, and losing that race is fatal rather than
	-- untidy: a character that appears before its stage does has no mark to be moved to and
	-- no floor under it, so it falls out of the world and is destroyed, respawns into the
	-- same nothing, and loops. Ordering it explicitly -- stage first, then a body to stand on
	-- it -- means the race cannot be lost because it is no longer run.
	--
	-- Wrapped because `LoadCharacter` throws if the player leaves between the join and here,
	-- which is a normal thing for a player to do and not worth a stack trace.
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		warn(`[AGES] lobby: could not load a character for {player.Name} -- {err}`)
	end
end

local function onPlayerRemoving(player: Player)
	local folder = stages[player]
	if folder ~= nil then
		folder:Destroy()
		stages[player] = nil
	end
	spinners[player] = nil
	release(player)
end

-- The one SpawnLocation in the lobby, sitting on the first stage's mark.
--
-- Built here rather than declared in `lobby.project.json`, where static geometry normally
-- belongs, for the same reason the stage is: a spawn point written into JSON is a copy of
-- `Config.Lobby.Stage.Origin` with nothing keeping the two equal, and the day the origin
-- moved every player would spend their first second somewhere else.
--
-- Sitting on stage 1's mark means every player lands on a solid disc, whichever stage is
-- theirs: they spawn here, `Place` moves them to their own mark a moment later, and neither
-- end of that is ever mid-air.
--
-- **Collidable, unlike every other part this file builds.** It is the one thing here that has
-- to hold a character up rather than merely be seen, and a SpawnLocation you fall through is
-- worse than no SpawnLocation at all -- it looks like it worked.
local function ensureSpawn()
	local existing = Workspace:FindFirstChild("LobbySpawn")
	if existing ~= nil then
		existing:Destroy()
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Locked = true
	spawn.CanCollide = true
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Size = Vector3.new(8, 0.2, 8)
	-- Just clear of the disc's top face rather than flush with it, so the two are never
	-- coplanar -- z-fighting on an invisible part is invisible, but a character spawning
	-- exactly on a seam is not.
	spawn.CFrame = CFrame.new(originFor(1) + Vector3.new(0, 0.1, 0))
	spawn.Parent = Workspace
end

function StageService:Init()
	-- **Off, and this is load-bearing.** With automatic loading on, a character appears the
	-- instant a player joins -- which races `onPlayerAdded` and, on a fresh server, wins. A
	-- character that exists before its stage does has no mark to be moved to and no floor
	-- under it: it falls out of the world, is destroyed, respawns into the same nothing, and
	-- loops. `onPlayerAdded` calls `LoadCharacter` itself once the stage is up, so the order
	-- is stated rather than hoped for.
	Players.CharacterAutoLoads = false

	-- Before the first join rather than in `Start`, because `PlayerAdded` is connected on the
	-- next line and a player arriving between the two would spawn into a place with no
	-- SpawnLocation in it.
	ensureSpawn()

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

function StageService:Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- One loop for every spinning part on every stage, rather than one per part.
	--
	-- Server-side rather than client-side because the parts are anchored and replicated, so
	-- a client-side spin would only turn on the machine running it -- and every player is
	-- looking at a different stage anyway, so there is nothing to gain by moving it and a
	-- desync to lose.
	RunService.Heartbeat:Connect(function(delta)
		for _, turning in spinners do
			for _, entry in turning do
				-- Checked rather than trusted, because `Ensure` destroys a folder and the
				-- entries for it are only replaced on the line after -- and a Rojo sync can
				-- land a Heartbeat in between. Writing a CFrame to a destroyed part is a
				-- silent no-op today and an error the version Roblox tightens it.
				if entry.part.Parent ~= nil then
					entry.part.CFrame = entry.part.CFrame * CFrame.Angles(0, math.rad(entry.rate * delta), 0)
				end
			end
		end
	end)
end

-- For the debug harness: what exists, and where.
function StageService.Describe(): { string }
	local out: { string } = {}
	for index, occupant in occupants do
		local origin = originFor(index)
		local built = if stages[occupant] ~= nil then "built" else "MISSING"
		table.insert(out, `stage {index}: {occupant.Name} at ({math.floor(origin.X)}, {math.floor(origin.Y)}, {math.floor(origin.Z)}) -- {built}`)
	end
	if #out == 0 then
		table.insert(out, "no stages -- nobody is in the lobby")
	end
	return out
end


return StageService
