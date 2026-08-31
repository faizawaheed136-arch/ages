--!strict
-- Wires every tagged door and locker to a ProximityPrompt, once, at startup.
--
-- Two tags, one mechanism. A locker door and a classroom door differ only in numbers -- how far
-- they swing, how fast, how long before they shut, and what they sound like -- so they share
-- Hinge and differ in a config table. Writing them as two systems is how they drift apart.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Hinge = require(script.Parent.Hinge)
local HandWraps = require(script.Parent.HandWraps)

local DOOR_TAG = "Door"
local LOCKER_TAG = "LockerDoor"

-- 16 studs, comfortably inside the 24-wide corridor so a door does not open at somebody
-- walking past on the far side of it.
local AUTO_OPEN_RADIUS = 16

-- **Replace these.** Until they are real ids the doors swing correctly and silently.
local SOUND = {
	Creak = "rbxassetid://0",
	Latch = "rbxassetid://0",
	Thud = "rbxassetid://0",
}

local CLASSROOM: Hinge.Config = {
	Side = "Left",
	SwingDegrees = 100,
	OpenSeconds = 0.85,
	CloseSeconds = 1.1,
	SlamSeconds = 0.16,
	AutoCloseSeconds = 5,
	OpenSound = SOUND.Creak,
	LatchSound = SOUND.Latch,
	ThudSound = SOUND.Thud,
}

local LOCKER: Hinge.Config = {
	Side = "Left",
	-- Wider than a room door: a locker door that only opens to 100 still hides its own interior
	-- from anyone standing in front of it.
	SwingDegrees = 118,
	OpenSeconds = 0.4,
	CloseSeconds = 0.55,
	SlamSeconds = 0.12,
	AutoCloseSeconds = 5,
	OpenSound = SOUND.Creak,
	LatchSound = SOUND.Latch,
	ThudSound = SOUND.Thud,
}

local DoorService = {}

local doors: { [Instance]: Hinge.Door } = {}
-- Only doors that asked for it. Empty in the normal case, and the loop below does not start
-- unless something is in here.
local autoOpen: { [Instance]: Hinge.Door } = {}
local autoOpenCount = 0

-- ---------------------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------------------

-- Attributes let a modular kit override any of this per instance without a script per door:
-- set Hinge, SwingDegrees or AutoCloseSeconds in Studio and the kit picks them up.
local function configure(instance: Instance, base: Hinge.Config): Hinge.Config
	local config = table.clone(base)
	local side = instance:GetAttribute("Hinge")
	if side == "Left" or side == "Right" then
		config.Side = side :: any
	end
	local swing = instance:GetAttribute("SwingDegrees")
	if typeof(swing) == "number" then
		config.SwingDegrees = swing
	end
	local auto = instance:GetAttribute("AutoCloseSeconds")
	if typeof(auto) == "number" then
		config.AutoCloseSeconds = auto
	end
	return config
end

local function promptAnchor(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart
	end
	return nil
end

local function attach(instance: Instance, base: Hinge.Config, isLocker: boolean)
	if doors[instance] ~= nil then
		return
	end

	local door = Hinge.new(instance :: PVInstance, configure(instance, base))
	if door == nil then
		return
	end
	doors[instance] = door

	local anchor = promptAnchor(instance)
	if anchor == nil then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DoorPrompt"
	prompt.ActionText = if isLocker then "Open" else "Door"
	prompt.ObjectText = if isLocker then "Locker" else ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = if isLocker then 10 else 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	prompt.Triggered:Connect(function(player: Player)
		door:Toggle()
		-- Wraps come out of a locker, not a classroom door. Idempotent, so opening every locker
		-- in the corridor still leaves you with one pair.
		if isLocker and door.isOpen then
			HandWraps.Give(player)
		end
	end)

	if instance:GetAttribute("AutoOpen") == true then
		autoOpen[instance] = door
		autoOpenCount += 1
	end
end

-- ---------------------------------------------------------------------------------------
-- Auto-open, for doors that should swing as you walk up
-- ---------------------------------------------------------------------------------------

-- **One loop for all of them, at 5 Hz, and only if any exist.**
--
-- The obvious version is a Heartbeat connection per door checking distance every frame -- sixty
-- checks a second times every door in a corridor, forever, almost all of them against an empty
-- corridor. This runs five times a second over only the doors that opted in, and never starts
-- at all if none did.
local function startAutoOpen()
	if autoOpenCount == 0 then
		return
	end
	task.spawn(function()
		while true do
			task.wait(0.2)
			for instance, door in autoOpen do
				if instance.Parent == nil then
					autoOpen[instance] = nil
					continue
				end
				local near = false
				local origin = door.leaf.Position
				for _, player in Players:GetPlayers() do
					local character = player.Character
					local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
					if root ~= nil and ((root :: BasePart).Position - origin).Magnitude < AUTO_OPEN_RADIUS then
						near = true
						break
					end
				end
				if near and not door.isOpen then
					door:Open()
				end
			end
		end
	end)
end

-- ---------------------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------------------

function DoorService.Start()
	for _, instance in CollectionService:GetTagged(DOOR_TAG) do
		attach(instance, CLASSROOM, false)
	end
	for _, instance in CollectionService:GetTagged(LOCKER_TAG) do
		attach(instance, LOCKER, true)
	end

	CollectionService:GetInstanceAddedSignal(DOOR_TAG):Connect(function(instance)
		attach(instance, CLASSROOM, false)
	end)
	CollectionService:GetInstanceAddedSignal(LOCKER_TAG):Connect(function(instance)
		attach(instance, LOCKER, true)
	end)

	CollectionService:GetInstanceRemovedSignal(DOOR_TAG):Connect(function(instance)
		doors[instance] = nil
		autoOpen[instance] = nil
	end)
	CollectionService:GetInstanceRemovedSignal(LOCKER_TAG):Connect(function(instance)
		doors[instance] = nil
		autoOpen[instance] = nil
	end)

	startAutoOpen()
end

DoorService.Doors = doors

return DoorService
