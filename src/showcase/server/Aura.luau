--!strict
-- The glow you get for finishing a session.
--
-- Server-side, so everybody sees it -- an effect the earner cannot show anybody is not a reward.
-- Built onto the character and torn down on a timer, on death, and on respawn, because a
-- cosmetic that outlives its welcome is worse than one that never fires.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Workout = require(ReplicatedStorage:WaitForChild("Showcase"):WaitForChild("Workout"))

local FOLDER_NAME = "WorkoutAura"

local Aura = {}

local function sequence(a: number, b: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, a),
		NumberSequenceKeypoint.new(1, b),
	})
end

-- Two attachments a stud apart on the torso. A Trail needs exactly two, and their separation is
-- the ribbon's width -- putting them further apart does not make a longer trail, only a fatter
-- one, which is the usual reason a first Trail looks like a flag.
local function buildTrail(root: BasePart, parent: Folder)
	local top = Instance.new("Attachment")
	top.Name = "AuraTop"
	top.Position = Vector3.new(0, 1.1, 0)
	top.Parent = root

	local bottom = Instance.new("Attachment")
	bottom.Name = "AuraBottom"
	bottom.Position = Vector3.new(0, -1.1, 0)
	bottom.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = "AuraTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.5
	trail.MinLength = 0.2
	-- Warm, and matched to the sun accent from section 03 rather than being a new colour.
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 206, 140), Color3.fromRGB(196, 120, 60))
	trail.Transparency = sequence(0.25, 1)
	trail.WidthScale = sequence(1, 0)
	trail.LightEmission = 0.85
	trail.FaceCamera = true
	-- The Trail lives in the folder; its two attachments have to live on the part they follow.
	-- Both are handed to Debris below so neither outlasts the aura.
	trail.Parent = parent
	return { top, bottom }
end

-- The trail only shows while moving. A player who earns the aura and then stands still should
-- still be visibly glowing, so a slow upward drift of embers does the standing-still case.
local function buildEmbers(root: BasePart, parent: Folder)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AuraEmbers"
	emitter.Rate = 14
	emitter.Speed = NumberRange.new(1, 3)
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = sequence(0.28, 0)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 214, 150), Color3.fromRGB(180, 104, 52))
	emitter.LightEmission = 0.9
	emitter.Acceleration = Vector3.new(0, 4, 0)
	emitter.Parent = root

	-- Deliberately not a PointLight. A light following a player through the dark interiors of
	-- section 01 lifts the exposure everywhere they walk and quietly undoes the whole lighting
	-- design; LightEmission on the particles gives the glow without touching the scene.
	return { emitter }
end

function Aura.Clear(character: Model)
	local existing = character:FindFirstChild(FOLDER_NAME)
	if existing ~= nil then
		existing:Destroy()
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return
	end
	for _, name in { "AuraTop", "AuraBottom", "AuraEmbers" } do
		local part = root:FindFirstChild(name)
		if part ~= nil then
			part:Destroy()
		end
	end
end

function Aura.Grant(player: Player)
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if character == nil or root == nil then
		return
	end

	-- Re-earning refreshes rather than stacking. Two trails on one torso is not twice as bright,
	-- it is a rendering artefact.
	Aura.Clear(character)

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = character

	local strays = {}
	for _, instance in buildTrail(root :: BasePart, folder) do
		table.insert(strays, instance)
	end
	for _, instance in buildEmbers(root :: BasePart, folder) do
		table.insert(strays, instance)
	end

	-- Debris rather than a task.delay closure: it survives the character being destroyed under
	-- it, which a delayed :Destroy() on a freed instance does not.
	Debris:AddItem(folder, Workout.AuraSeconds)
	for _, instance in strays do
		Debris:AddItem(instance, Workout.AuraSeconds)
	end
end

return Aura
