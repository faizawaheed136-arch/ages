--!strict
-- The courtyard vending machine, and the can it hands you.
--
-- The can is built from parts rather than imported as a mesh, which keeps the whole catalogue
-- free to extend and means there is no asset id to go missing. See Detail.luau in world/ for the
-- same argument applied to the fencing.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Drinks = require(ReplicatedStorage:WaitForChild("Showcase"):WaitForChild("Drinks"))

local TAG = "VendingMachine"

-- **Replace these.** Until they are real ids the machine works and the can drains silently,
-- which looks exactly like the sound system being broken.
local POP_SOUND = "rbxassetid://0" -- a ring-pull cracking, short and bright
local SIP_SOUND = "rbxassetid://0" -- one swallow, quieter than the pop
local VEND_SOUND = "rbxassetid://0" -- the machine's motor and the thud of the can dropping

local VendingService = {}

local wired: { [Instance]: true } = {}
local lastSip: { [Player]: number } = {}

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

local OpenVending = remote("OpenVending")
local RequestDrink = remote("RequestDrink")

-- ---------------------------------------------------------------------------------------
-- The can
-- ---------------------------------------------------------------------------------------

local CAN_HEIGHT = 1.6
local CAN_WIDTH = 0.7

local function buildCan(drink: Drinks.Drink): Tool
	local tool = Instance.new("Tool")
	tool.Name = drink.Name
	tool.ToolTip = drink.Blurb
	tool.RequiresHandle = true
	-- Dropped cans on the courtyard floor within a minute of anyone finding backspace.
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(CAN_WIDTH, CAN_HEIGHT, CAN_WIDTH)
	handle.Shape = Enum.PartType.Cylinder
	handle.Color = drink.Body
	handle.Material = Enum.Material.Metal
	handle.Reflectance = 0.12
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.Parent = tool

	-- **A cylinder's axis runs along local X in Roblox, not Y.** A can built as a
	-- Shape = Cylinder part with a Y-major size lies on its side; the mesh below is what stands
	-- it up, and the Grip compensates. This catches everyone once.
	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "Body"
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = handle

	tool.Grip = CFrame.new(0, -0.1, 0) * CFrame.Angles(0, 0, math.rad(90))

	if POP_SOUND ~= "rbxassetid://0" then
		local pop = Instance.new("Sound")
		pop.Name = "Pop"
		pop.SoundId = POP_SOUND
		pop.Volume = 0.85
		pop.RollOffMaxDistance = 45
		pop.Parent = handle
	end
	if SIP_SOUND ~= "rbxassetid://0" then
		local sip = Instance.new("Sound")
		sip.Name = "Sip"
		sip.SoundId = SIP_SOUND
		sip.Volume = 0.6
		sip.RollOffMaxDistance = 30
		sip.Parent = handle
	end

	tool:SetAttribute("SipsLeft", drink.Sips)
	tool:SetAttribute("SipsTotal", drink.Sips)
	return tool
end

-- **Shrink the mesh, not the Handle.**
--
-- `Tool.Grip` is a CFrame relative to the Handle's *centre*, so shrinking Handle.Size moves that
-- centre and the can slides through the hand as it empties. Scaling the SpecialMesh leaves the
-- Handle -- and therefore the grip -- exactly where it was.
--
-- The offset is what makes it drain rather than merely get smaller: scale down the long axis and
-- push the mesh back by half of what was removed, so the base of the can stays against the palm
-- and the top comes down.
local function setLevel(handle: BasePart, share: number)
	local mesh = handle:FindFirstChild("Body") :: SpecialMesh?
	if mesh == nil then
		return
	end
	local goal = math.clamp(share, 0.08, 1)
	TweenService:Create(mesh, TweenInfo.new(0.35, Enum.EasingStyle.Quad), {
		-- X is the cylinder's long axis, per the note in buildCan.
		Scale = Vector3.new(goal, 1, 1),
		Offset = Vector3.new(-(1 - goal) * CAN_HEIGHT / 2, 0, 0),
	}):Play()
end

local function wireDrinking(tool: Tool)
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	if handle == nil then
		return
	end

	-- The tab, once, the first time it is taken out. Popping it on every equip turns a nice
	-- detail into a tic.
	local popped = false
	tool.Equipped:Connect(function()
		if popped then
			return
		end
		popped = true
		local pop = handle:FindFirstChild("Pop") :: Sound?
		if pop ~= nil then
			pop:Play()
		end
	end)

	-- Tool.Activated fires on the server as well as the client, and the level has to change on
	-- the server or nobody else sees the can empty.
	tool.Activated:Connect(function()
		local player = Players:GetPlayerFromCharacter(tool.Parent)
		if player == nil then
			return
		end
		local last = lastSip[player]
		if last ~= nil and os.clock() - last < Drinks.SipCooldown then
			return
		end
		lastSip[player] = os.clock()

		local left = (tool:GetAttribute("SipsLeft") :: number?) or 0
		local total = (tool:GetAttribute("SipsTotal") :: number?) or 1
		left -= 1
		tool:SetAttribute("SipsLeft", left)

		local sip = handle:FindFirstChild("Sip") :: Sound?
		if sip ~= nil then
			sip:Play()
		end
		setLevel(handle, left / total)

		if left <= 0 then
			-- Let the last shrink finish before the can goes, or it vanishes mid-swallow.
			task.delay(0.45, function()
				if tool.Parent ~= nil then
					tool:Destroy()
				end
			end)
		end
	end)
end

-- ---------------------------------------------------------------------------------------
-- Vending
-- ---------------------------------------------------------------------------------------

local function give(player: Player, key: string): boolean
	local drink = Drinks.ByKey[key]
	if drink == nil then
		return false
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack == nil then
		return false
	end

	-- One can at a time. Buying six and holding them all is not a thing a vending machine should
	-- allow, and a backpack full of cans is a UI problem nobody asked for.
	for _, existing in { backpack, player.Character } do
		if existing == nil then
			continue
		end
		for _, item in (existing :: Instance):GetChildren() do
			if item:IsA("Tool") and Drinks.ByKey[(item:GetAttribute("DrinkKey") :: string?) or ""] ~= nil then
				return false
			end
		end
	end

	local tool = buildCan(drink)
	tool:SetAttribute("DrinkKey", key)
	wireDrinking(tool)
	tool.Parent = backpack
	return true
end

local function anchorOf(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function wire(instance: Instance)
	if wired[instance] then
		return
	end
	local anchor = anchorOf(instance)
	if anchor == nil then
		warn(`[Vending] {instance:GetFullName()} is tagged {TAG} but has no BasePart to prompt from`)
		return
	end
	wired[instance] = true

	if VEND_SOUND ~= "rbxassetid://0" and anchor:FindFirstChild("Vend") == nil then
		local vend = Instance.new("Sound")
		vend.Name = "Vend"
		vend.SoundId = VEND_SOUND
		vend.Volume = 0.8
		vend.RollOffMaxDistance = 55
		vend.Parent = anchor
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VendingPrompt"
	prompt.ActionText = "Buy"
	prompt.ObjectText = "Vending Machine"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	prompt.Triggered:Connect(function(player: Player)
		OpenVending:FireClient(player)
	end)
end

function VendingService.Start()
	for _, instance in CollectionService:GetTagged(TAG) do
		wire(instance)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(wire)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance)
		wired[instance] = nil
	end)

	RequestDrink.OnServerEvent:Connect(function(player: Player, key: unknown)
		if typeof(key) ~= "string" then
			return
		end
		if give(player, key :: string) then
			-- The machine nearest the buyer makes the noise, so the sound comes from the thing
			-- they are standing at rather than from nowhere.
			local character = player.Character
			local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
			if root ~= nil then
				local best, bestDistance = nil, math.huge
				for machine in wired do
					local anchor = anchorOf(machine)
					if anchor ~= nil then
						local d = (anchor.Position - (root :: BasePart).Position).Magnitude
						if d < bestDistance then
							best, bestDistance = anchor, d
						end
					end
				end
				local vend = if best ~= nil then best:FindFirstChild("Vend") :: Sound? else nil
				if vend ~= nil then
					vend:Play()
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSip[player] = nil
	end)
end

return VendingService
