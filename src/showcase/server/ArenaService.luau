--!strict
-- Rings, spectator seats and the target wall.
--
-- Three interactions, one service, because they share a subject: the arena. Each is found by
-- tag, so a modular kit adds another ring or another bench without a line of code.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Records = require(ReplicatedStorage:WaitForChild("Showcase"):WaitForChild("Records"))

local RING_TAG = "SparringRing"
local SEAT_TAG = "SpectatorSeat"
local TARGET_TAG = "TargetNode"
local VANTAGE_TAG = "ArenaCamera"

-- How far a strike is felt. The clicker always gets the full shake; anybody else inside this
-- gets it scaled down by distance, which is what makes a hit land in the *room* rather than
-- only on the person who threw it.
local FELT_RADIUS = 90

local IMPACT_SOUND = "rbxassetid://0" -- replace: a heavy bag or body impact, not a punch whoosh

local ArenaService = {}

local wired: { [Instance]: true } = {}

-- ---------------------------------------------------------------------------------------
-- Remotes
-- ---------------------------------------------------------------------------------------

local function folderUnder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		return existing :: Folder
	end
	local made = Instance.new("Folder")
	made.Name = name
	made.Parent = parent
	return made
end

local function remote(name: string): RemoteEvent
	local folder = folderUnder(folderUnder(ReplicatedStorage, "Showcase"), "Remotes")
	local existing = folder:FindFirstChild(name)
	if existing ~= nil then
		return existing :: RemoteEvent
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = folder
	return event
end

local ShowScoreboard = remote("ShowScoreboard")
local SeatCamera = remote("SeatCamera")
local Impact = remote("Impact")

-- ---------------------------------------------------------------------------------------
-- 1. Sparring rings
-- ---------------------------------------------------------------------------------------

local function wireRing(part: Instance)
	if wired[part] or not part:IsA("BasePart") then
		return
	end
	wired[part] = true

	local detector = Instance.new("ClickDetector")
	detector.Name = "RingDetector"
	detector.MaxActivationDistance = 26
	detector.CursorIcon = ""
	detector.Parent = part

	detector.MouseClick:Connect(function(player: Player)
		-- The ring id lives on the part or on any ancestor, so a whole ring model can carry it
		-- once rather than every rope section carrying its own copy.
		local id = part:GetAttribute("RingId")
		local search: Instance? = part
		while id == nil and search ~= nil do
			id = search:GetAttribute("RingId")
			search = search.Parent
		end
		if typeof(id) ~= "string" or Records.ByRing[id] == nil then
			id = Records.DefaultRing
		end
		ShowScoreboard:FireClient(player, id)
	end)
end

-- ---------------------------------------------------------------------------------------
-- 2. Spectator seats
-- ---------------------------------------------------------------------------------------

-- Where the camera goes when you sit. A seat can name its own vantage with a child ObjectValue
-- called CameraTarget; otherwise every seat shares the one part tagged ArenaCamera, which is
-- what you want for a single arena and saves tagging forty benches individually.
local function vantageFor(seat: Instance): BasePart?
	local named = seat:FindFirstChild("CameraTarget")
	if named ~= nil and named:IsA("ObjectValue") then
		local value = named.Value
		if value ~= nil and value:IsA("BasePart") then
			return value
		end
	end
	for _, candidate in CollectionService:GetTagged(VANTAGE_TAG) do
		if candidate:IsA("BasePart") then
			return candidate
		end
	end
	return nil
end

local function wireSeat(instance: Instance)
	if wired[instance] or not instance:IsA("Seat") then
		return
	end
	wired[instance] = true
	local seat = instance :: Seat

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		if occupant == nil then
			return
		end
		local player = Players:GetPlayerFromCharacter(occupant.Parent)
		if player == nil then
			return
		end

		local vantage = vantageFor(seat)
		if vantage == nil then
			warn(`[Arena] {seat:GetFullName()} has no CameraTarget and nothing is tagged {VANTAGE_TAG}`)
			return
		end

		SeatCamera:FireClient(player, true, vantage.CFrame)

		-- **Release on standing, on dying, and on leaving.**
		--
		-- Occupant going nil covers standing up. It does *not* reliably cover a character being
		-- removed underneath the seat -- a respawn while seated leaves the camera scriptable and
		-- the player looking at an empty ring with no way back. The client also guards this, but
		-- a camera that can get stuck deserves belt and braces.
		local released = false
		local function release()
			if released then
				return
			end
			released = true
			if player.Parent ~= nil then
				SeatCamera:FireClient(player, false)
			end
		end

		local connection: RBXScriptConnection
		connection = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			if seat.Occupant ~= occupant then
				connection:Disconnect()
				release()
			end
		end)
		occupant.Died:Once(release)
		occupant.AncestryChanged:Once(function(_, parent)
			if parent == nil then
				release()
			end
		end)
	end)
end

-- ---------------------------------------------------------------------------------------
-- 3. The target wall
-- ---------------------------------------------------------------------------------------

local function sequence(a: number, b: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, a),
		NumberSequenceKeypoint.new(1, b),
	})
end

local function buildEmitters(node: BasePart)
	if node:FindFirstChild("ImpactSpark") ~= nil then
		return
	end

	-- **Rate 0 on both.** These never run continuously; they exist to be told to Emit. A target
	-- wall with sixty nodes quietly emitting is a frame-rate problem you will blame on lighting.
	local spark = Instance.new("ParticleEmitter")
	spark.Name = "ImpactSpark"
	spark.Rate = 0
	spark.Speed = NumberRange.new(22, 44)
	spark.Lifetime = NumberRange.new(0.12, 0.3)
	spark.SpreadAngle = Vector2.new(38, 38)
	spark.Size = sequence(0.5, 0)
	spark.Transparency = sequence(0.1, 1)
	spark.Color = ColorSequence.new(Color3.fromRGB(255, 214, 150), Color3.fromRGB(196, 120, 60))
	spark.LightEmission = 0.6
	spark.Acceleration = Vector3.new(0, -60, 0)
	spark.Parent = node

	-- The dust is what sells weight. Sparks alone read as a spark effect; a slow grey puff
	-- hanging in the air afterwards reads as something heavy hitting a solid wall.
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "ImpactDust"
	dust.Rate = 0
	dust.Speed = NumberRange.new(2, 7)
	dust.Lifetime = NumberRange.new(0.7, 1.4)
	dust.SpreadAngle = Vector2.new(60, 60)
	dust.Size = sequence(1.2, 5)
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.3, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Color = ColorSequence.new(Color3.fromRGB(150, 146, 138))
	dust.Acceleration = Vector3.new(0, 3, 0)
	dust.Parent = node

	if IMPACT_SOUND ~= "rbxassetid://0" then
		local sound = Instance.new("Sound")
		sound.Name = "ImpactSound"
		sound.SoundId = IMPACT_SOUND
		sound.Volume = 0.85
		sound.PlaybackSpeed = 0.9
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMaxDistance = 120
		sound.Parent = node
	end
end

local function wireTarget(instance: Instance)
	if wired[instance] or not instance:IsA("BasePart") then
		return
	end
	wired[instance] = true
	local node = instance :: BasePart
	buildEmitters(node)

	local detector = Instance.new("ClickDetector")
	detector.Name = "TargetDetector"
	detector.MaxActivationDistance = 22
	detector.Parent = node

	detector.MouseClick:Connect(function(player: Player)
		-- **Emit on the server.** ParticleEmitter:Emit replicates, so one call puts the burst in
		-- everybody's world. Firing a remote and emitting per client would produce the same
		-- picture at more cost and let a modified client emit nothing.
		local spark = node:FindFirstChild("ImpactSpark") :: ParticleEmitter?
		local dust = node:FindFirstChild("ImpactDust") :: ParticleEmitter?
		if spark ~= nil then
			spark:Emit(26)
		end
		if dust ~= nil then
			dust:Emit(9)
		end
		local sound = node:FindFirstChild("ImpactSound") :: Sound?
		if sound ~= nil then
			sound:Play()
		end

		-- Shake is per-camera and therefore per-client. Full for whoever struck it, falling off
		-- with distance for everyone else in the hall.
		local origin = node.Position
		for _, other in Players:GetPlayers() do
			if other == player then
				Impact:FireClient(other, 1)
				continue
			end
			local character = other.Character
			local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
			if root ~= nil then
				local distance = ((root :: BasePart).Position - origin).Magnitude
				if distance < FELT_RADIUS then
					Impact:FireClient(other, 1 - distance / FELT_RADIUS)
				end
			end
		end
	end)
end

-- ---------------------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------------------

local function bind(tag: string, wire: (Instance) -> ())
	for _, instance in CollectionService:GetTagged(tag) do
		wire(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(wire)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		wired[instance] = nil
	end)
end

function ArenaService.Start()
	bind(RING_TAG, wireRing)
	bind(SEAT_TAG, wireSeat)
	bind(TARGET_TAG, wireTarget)
end

return ArenaService
