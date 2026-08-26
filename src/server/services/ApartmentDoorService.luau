--!strict
-- Apartment entrance doors. Each door is a tagged part in the generated world;
-- this service attaches an interaction prompt so the player can open/close it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Interact = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Interact"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local ApartmentDoorService = {}

-- Remote to toggle the door state (open/closed)
local REQUEST_TOGGLE_DOOR = Remotes.Get("RequestToggleApartmentDoor")

-- Track door state: doorPart -> {hinge, isOpen}
local doorStates: { [BasePart]: { hinge: CFrame, isOpen: boolean } } = {}

-- Initialize by finding all tagged apartment doors
function ApartmentDoorService:Init()
	local tag = "ApartmentDoor"
	local instances = CollectionService:GetTagged(tag)

	for _, instance in instances do
		if instance:IsA("BasePart") then
			self:setupDoor(instance :: BasePart)
		else
			warn(`[AGES] ApartmentDoor tagged instance "{instance:GetFullName()}" is not a BasePart`)
		end
	end

	-- Listen for new doors being tagged (e.g., during Studio editing)
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			self:setupDoor(instance :: BasePart)
		end
	end)

	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			doorStates[instance :: BasePart] = nil
		end
	end)
end

function ApartmentDoorService:Start()
	-- Handle toggle requests from clients
	REQUEST_TOGGLE_DOOR.OnServerEvent:Connect(function(player: Player, blockName: string)
		local doorPart = self:findDoorByBlockName(blockName)
		if doorPart then
			self:toggleDoor(player, doorPart)
		end
	end)
end

function ApartmentDoorService:findDoorByBlockName(blockName: string): BasePart?
	for doorPart, _ in doorStates do
		local attr = doorPart:GetAttribute("ApartmentBlock")
		if attr == blockName then
			return doorPart
		end
	end
	return nil
end

-- Set up a single door part with interaction and initial state
function ApartmentDoorService:setupDoor(doorPart: BasePart)
	-- Calculate hinge position (left edge of door)
	local size = doorPart.Size
	local hinge = doorPart.CFrame * CFrame.new(-size.X / 2, 0, 0)

	doorStates[doorPart] = {
		hinge = hinge,
		isOpen = false,
	}

	-- Get the apartment block name from the attribute
	local blockName = doorPart:GetAttribute("ApartmentBlock") or "Apartment"

	-- Attach interaction prompt
	Interact.Attach(doorPart, {
		kind = "Apartment",
		id = blockName,
		actionText = "Open",
		objectText = "Apartment Door",
	})

	-- Ensure door starts closed
	doorPart.CFrame = hinge * CFrame.new(size.X / 2, 0, 0)
end

-- Toggle door open/closed
function ApartmentDoorService:toggleDoor(player: Player, doorPart: BasePart)
	local state = doorStates[doorPart]
	if not state then
		return
	end

	-- Check distance
	local character = player.Character
	if not character then
		return
	end
	local pivot = character:GetPivot()
	if (pivot.Position - doorPart.Position).Magnitude > Config.Interact.ReachStuds * 2 then
		return
	end

	state.isOpen = not state.isOpen
	local size = doorPart.Size
	local swing = Config.ApartmentDoor.SwingDegrees
	local targetCFrame = state.hinge * CFrame.Angles(0, math.rad(state.isOpen and -swing or 0), 0) * CFrame.new(size.X / 2, 0, 0)

	-- Animate the door
	local tweenInfo = TweenInfo.new(Config.ApartmentDoor.AnimationSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = game:GetService("TweenService"):Create(doorPart, tweenInfo, { CFrame = targetCFrame })
	tween:Play()

	-- Update interaction text
	local prompt = doorPart:FindFirstChild("AgesInteract")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.ActionText = state.isOpen and "Close" or "Open"
	end
end

return ApartmentDoorService