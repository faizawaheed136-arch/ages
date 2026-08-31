--!strict
-- Lockers, and the only code in the game allowed to change what a player is wearing.
--
-- Three jobs: hang a ProximityPrompt on anything tagged Wardrobe, answer the client's request
-- to change, and put the outfit back on after a respawn. Everything that touches a
-- HumanoidDescription lives here on the server -- see `dress` for why.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Uniforms = require(ReplicatedStorage:WaitForChild("Showcase"):WaitForChild("Uniforms"))

local TAG = "Wardrobe"

-- 12 studs. The corridor is 24 wide, so this reaches a player walking down the middle of it
-- without reaching one on the far side -- two banks of lockers facing each other across a
-- corridor would otherwise both prompt at once, and the player gets whichever won the race.
local PROMPT_DISTANCE = 12

-- One change per second per player. ApplyDescription is throttled by the engine anyway, but it
-- *queues* rather than rejecting -- so a client spamming the remote builds a backlog that keeps
-- rebuilding the character long after they stopped clicking.
local COOLDOWN_SECONDS = 1

local WardrobeService = {}

local chosen: { [Player]: string } = {}
local lastChange: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}

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

local OpenWardrobe = remote("OpenWardrobe") -- server -> client, "the locker is open"
local RequestUniform = remote("RequestUniform") -- client -> server, "I picked this key"
local UniformApplied = remote("UniformApplied") -- server -> client, "it worked / it did not"

-- ---------------------------------------------------------------------------------------
-- Dressing
-- ---------------------------------------------------------------------------------------

-- **Why this is on the server.**
--
-- A client can set its own character's Shirt locally and it will look right *to that client and
-- nobody else*. Appearance has to be applied server-side to replicate. And since the server is
-- doing it anyway, the request carries a catalogue key rather than an asset id -- so the worst
-- a modified client can send is a key that does not exist.
local function dress(player: Player, key: string): (boolean, string?)
	local uniform = Uniforms.ByKey[key]
	if uniform == nil then
		return false, "unknown uniform"
	end

	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid == nil then
		return false, "no character"
	end

	if busy[player] then
		return false, "already changing"
	end
	busy[player] = true

	local ok, err = pcall(function()
		local description = humanoid:GetAppliedDescription()

		-- **The strip and the overlay are one operation, not two.**
		--
		-- There is no "clear what they are wearing" step above this. Zeroing GraphicTShirt and
		-- overwriting Shirt/Pants removes whatever the player walked in wearing, and
		-- ApplyDescription swaps the whole appearance at once -- so there is no frame in which
		-- the character stands there half-dressed. Destroying the Shirt instance first and
		-- adding a new one second is the version that flickers.
		description.Shirt = uniform.Shirt
		description.Pants = uniform.Pants
		description.GraphicTShirt = 0

		-- `false` = "this list contains no rigid accessories", which leaves hats, hair and faces
		-- alone and replaces only layered clothing. Passing `true` here is how you accidentally
		-- shave everybody who uses a locker.
		description:SetAccessories(uniform.Layers, false)

		humanoid:ApplyDescription(description)
	end)

	busy[player] = nil

	if not ok then
		return false, tostring(err)
	end

	chosen[player] = key
	lastChange[player] = os.clock()
	return true, nil
end

-- ---------------------------------------------------------------------------------------
-- Prompts
-- ---------------------------------------------------------------------------------------

local function anchorOf(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function attachPrompt(instance: Instance)
	local anchor = anchorOf(instance)
	if anchor == nil then
		-- Loud, because the failure is otherwise invisible: the locker stands there looking
		-- correct and simply never prompts, and the usual cause is a Model with no PrimaryPart.
		warn(`[Wardrobe] {instance:GetFullName()} is tagged "{TAG}" but has no BasePart to hang a prompt on`)
		return
	end
	if anchor:FindFirstChild("WardrobePrompt") ~= nil then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WardrobePrompt"
	prompt.ActionText = "Change"
	prompt.ObjectText = "Locker"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.UIOffset = Vector2.new(0, -12)

	-- False on purpose. A locker door, a bench, or another player standing in front of the bank
	-- all break line of sight, and a prompt that flickers as somebody walks past reads as broken.
	-- The cost is that it can occasionally be seen through a thin door, which nobody notices.
	prompt.RequiresLineOfSight = false

	prompt.Parent = anchor

	prompt.Triggered:Connect(function(player: Player)
		OpenWardrobe:FireClient(player, chosen[player] or Uniforms.Default)
	end)
end

-- ---------------------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------------------

local function onPlayer(player: Player)
	player.CharacterAppearanceLoaded:Connect(function()
		-- **Respawn.** A HumanoidDescription is applied to a character, not to a player, so a
		-- new character arrives wearing whatever the player's own Roblox avatar wears. Without
		-- this the uniform silently comes off every time they die -- which in a combat showcase
		-- is constantly.
		local key = chosen[player]
		if key ~= nil then
			task.defer(dress, player, key)
		end
	end)
end

function WardrobeService.Start()
	for _, instance in CollectionService:GetTagged(TAG) do
		attachPrompt(instance)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(attachPrompt)

	RequestUniform.OnServerEvent:Connect(function(player: Player, key: unknown)
		-- Everything crossing this boundary is untrusted, including its type.
		if typeof(key) ~= "string" then
			return
		end
		local last = lastChange[player]
		if last ~= nil and os.clock() - last < COOLDOWN_SECONDS then
			UniformApplied:FireClient(player, false, "Too fast.")
			return
		end
		local ok, err = dress(player, key :: string)
		UniformApplied:FireClient(player, ok, err)
	end)

	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)

	Players.PlayerRemoving:Connect(function(player)
		chosen[player] = nil
		lastChange[player] = nil
		busy[player] = nil
	end)
end

-- Exposed so a debug command or a cutscene can dress somebody without a locker.
WardrobeService.Dress = dress

return WardrobeService
