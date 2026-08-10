--!strict
-- The line on the floor that says "go there".
--
-- Drawn on the client, and that is the whole reason this file exists rather than a
-- Beam built by WorkService alongside the hiring signs. Everything else this game
-- puts in the world is public -- a choice pad, a sign, a dog -- and being seen by
-- whoever walks past is either harmless or the point. Directions are not: they are
-- addressed to one person, and three players in one shop would otherwise stand in a
-- cat's cradle of each other's arrows. Built here, the line exists only for the
-- player it belongs to, and the server's whole side of it is a position and a name.
--
-- Two beams, doing two different jobs:
--
--   The core beam is slim and sharp — it says "this way" and gives the line its
--   directionality. It disappears on arrival because it would point at the floor.
--
--   The halo beam is wide and soft — it gives the line warmth and presence so it
--   reads as part of the world rather than a debug visualization. A gentle width
--   pulse makes it breathe.
--
--   The waypoint answers "what is over there?" and is *most* useful once you can
--   see the building, so it stays. It also carries the distance, which is what
--   turns a direction into a decision: "Shop assistant, 140 studs" is something a
--   player can weigh against whatever else they were doing.
--
-- The server decides where to point and when to stop. Nothing here asks why.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type GuideState = Types.GuideState

local Guide = {}
Guide.__index = Guide

-- Cosmetic, and out of Config for the reason ChoiceMarkers gives: the size of the
-- word on a waypoint is not a number anybody balances the game with. What is in
-- Config is everything that decides where the line goes and when it stops.
local WAYPOINT_WIDTH_STUDS = 8
local WAYPOINT_HEIGHT_STUDS = 2
local LABEL_TEXT_SIZE = 16
local DISTANCE_TEXT_SIZE = 13
local LABEL_COLOR = Color3.fromRGB(255, 250, 240)
local DISTANCE_COLOR = Color3.fromRGB(214, 208, 196)
local STROKE_COLOR = Color3.fromRGB(20, 18, 14)
local STROKE_THICKNESS = 2
local LABEL_HEIGHT = 0.55

-- Waypoint background chip — a dark rounded rect behind the text so the labels
-- are legible against any skybox or neon-lit storefront. The chip is the reason
-- the waypoint reads at a glance rather than getting lost in visual noise.
local CHIP_COLOR = Color3.fromRGB(18, 16, 14)
local CHIP_TRANSPARENCY = 0.35
local CHIP_CORNER = 8

-- How high the waypoint floats above the point it marks. Above head height so it
-- clears whoever is standing at the counter it is naming.
local WAYPOINT_LIFT_STUDS = 6.5

-- Core beam: bright in the middle, fading at both ends so it does not appear to be
-- welded to the player's waist or stabbed into the floor. The fade at the near end
-- matters most: a solid line starting at your own body reads as a tether.
local CORE_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.1, 0.15),
	NumberSequenceKeypoint.new(0.5, 0.06),
	NumberSequenceKeypoint.new(0.9, 0.15),
	NumberSequenceKeypoint.new(1, 1),
})

-- The halo's transparency is not a constant up here beside the core's, and the asymmetry
-- is deliberate: the core's curve is fixed, the halo's is built inline at construction from
-- `guide.HaloTransparency` so the glow can be tuned in Config without editing a sequence
-- shape by hand. A constant here would be a second, frozen answer to a question Config
-- already owns -- which is exactly what it was until now.

export type GuideHandle = typeof(setmetatable(
	{} :: {
		-- The part the far end of the line is pinned to, and what the waypoint is
		-- adorned to. Anchored, invisible, and moved rather than rebuilt each time the
		-- target changes.
		anchor: Part,
		anchorAttachment: Attachment,
		core: Beam,
		halo: Beam,
		waypoint: BillboardGui,
		chipFrame: Frame,
		labelText: TextLabel,
		distanceText: TextLabel,
		-- Rebuilt on respawn, because it lives on a body that gets replaced.
		playerAttachment: Attachment?,
		target: Vector3?,
		connection: RBXScriptConnection?,
	},
	Guide
))

local function outline(into: Instance)
	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE_COLOR
	stroke.Thickness = STROKE_THICKNESS
	stroke.Parent = into
end

-- Studs, rounded, with no unit. The player has no idea how long a stud is and does
-- not need one: the number's whole job is to get smaller as you walk, which is how
-- you know you are going the right way.
local function formatDistance(studs: number): string
	return string.format("%d away", math.floor(studs + 0.5))
end

function Guide.new(): GuideHandle
	local guide = Config.Guide

	local anchor = Instance.new("Part")
	anchor.Name = "AgesGuideAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	-- Parented to the workspace on the *client*, which never reaches the server or
	-- any other player. That is the entire privacy mechanism and it is worth being
	-- explicit about: nothing here is replicated because nothing here was made by
	-- anyone but this player's own machine.
	anchor.Parent = workspace

	local anchorAttachment = Instance.new("Attachment")
	anchorAttachment.Name = "GuideEnd"
	anchorAttachment.Parent = anchor

	-- The halo beam sits behind the core and gives the line its warmth. Wider,
	-- softer, with a gentle width pulse that makes it feel alive.
	local halo = Instance.new("Beam")
	halo.Name = "AgesGuideHalo"
	halo.Attachment1 = anchorAttachment
	halo.Color = ColorSequence.new(guide.Color)
	halo.Width0 = guide.HaloWidthNearStuds
	halo.Width1 = guide.HaloWidthFarStuds
	halo.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.08, math.clamp(0.3 + guide.HaloTransparency * 0.7, 0, 1)),
		NumberSequenceKeypoint.new(0.5, guide.HaloTransparency),
		NumberSequenceKeypoint.new(0.92, math.clamp(0.3 + guide.HaloTransparency * 0.7, 0, 1)),
		NumberSequenceKeypoint.new(1, 1),
	})
	halo.LightEmission = 1
	halo.FaceCamera = true
	halo.ZOffset = -0.1
	halo.CurveSize0 = guide.CurveStuds
	halo.CurveSize1 = -guide.CurveStuds
	halo.Texture = guide.ArrowTexture
	halo.TextureSpeed = guide.ArrowSpeed
	halo.TextureLength = math.max(1, 10 / guide.ArrowsPerTenStuds)
	halo.Enabled = false
	halo.Parent = anchor

	-- The core beam: slim, sharp, and bright. This is what gives the line its
	-- directionality; the halo is what gives it soul.
	local core = Instance.new("Beam")
	core.Name = "AgesGuide"
	core.Attachment1 = anchorAttachment
	core.Color = ColorSequence.new(guide.Color)
	core.Width0 = guide.WidthNearStuds
	core.Width1 = guide.WidthFarStuds
	core.Transparency = CORE_TRANSPARENCY
	core.LightEmission = 1
	core.FaceCamera = true
	core.ZOffset = 0.1
	core.CurveSize0 = guide.CurveStuds
	core.CurveSize1 = -guide.CurveStuds
	core.Texture = guide.ArrowTexture
	core.TextureSpeed = guide.ArrowSpeed
	core.TextureLength = math.max(1, 10 / guide.ArrowsPerTenStuds)
	core.Enabled = false
	core.Parent = anchor

	-- Waypoint: a billboard that floats above the destination with a dark chip
	-- behind the text for legibility against any background.
	local waypoint = Instance.new("BillboardGui")
	waypoint.Name = "AgesGuideWaypoint"
	waypoint.Adornee = anchor
	waypoint.Size = UDim2.new(WAYPOINT_WIDTH_STUDS, 0, WAYPOINT_HEIGHT_STUDS, 0)
	waypoint.StudsOffsetWorldSpace = Vector3.new(0, WAYPOINT_LIFT_STUDS, 0)
	waypoint.AlwaysOnTop = true
	waypoint.MaxDistance = math.huge
	waypoint.Enabled = false
	waypoint.Parent = anchor

	-- Dark chip behind the text. Rounded corners via UICorner so the waypoint
	-- reads as a polished UI element rather than floating raw text.
	local chipFrame = Instance.new("Frame")
	chipFrame.Name = "Chip"
	chipFrame.Size = UDim2.new(1, 8, 1, 4)
	chipFrame.Position = UDim2.new(0, -4, 0, -2)
	chipFrame.BackgroundColor3 = CHIP_COLOR
	chipFrame.BackgroundTransparency = CHIP_TRANSPARENCY
	chipFrame.BorderSizePixel = 0
	chipFrame.Parent = waypoint

	local chipCorner = Instance.new("UICorner")
	chipCorner.CornerRadius = UDim.new(0, CHIP_CORNER)
	chipCorner.Parent = chipFrame

	local labelText = Instance.new("TextLabel")
	labelText.Name = "Label"
	labelText.Size = UDim2.new(1, 0, LABEL_HEIGHT, 0)
	labelText.BackgroundTransparency = 1
	labelText.Font = Enum.Font.GothamBold
	labelText.TextSize = LABEL_TEXT_SIZE
	labelText.TextColor3 = LABEL_COLOR
	labelText.Text = ""
	labelText.Parent = waypoint
	outline(labelText)

	local distance = Instance.new("TextLabel")
	distance.Name = "Distance"
	distance.Size = UDim2.new(1, 0, 1 - LABEL_HEIGHT, 0)
	distance.Position = UDim2.new(0, 0, LABEL_HEIGHT, 0)
	distance.BackgroundTransparency = 1
	distance.Font = Enum.Font.GothamMedium
	distance.TextSize = DISTANCE_TEXT_SIZE
	distance.TextColor3 = DISTANCE_COLOR
	distance.Text = ""
	distance.Parent = waypoint
	outline(distance)

	return setmetatable({
		anchor = anchor,
		anchorAttachment = anchorAttachment,
		core = core,
		halo = halo,
		waypoint = waypoint,
		chipFrame = chipFrame,
		labelText = labelText,
		distanceText = distance,
		playerAttachment = nil,
		target = nil,
		connection = nil,
	}, Guide)
end

-- The near end of the line, on the body that currently exists.
--
-- Re-resolved rather than remembered, because a life ends and a new body arrives
-- without this module being told: the guide is about where you are going, and dying
-- on the way there is not information it is given. Cheap enough to ask every refresh.
local function playerEnd(self: GuideHandle): Attachment?
	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return nil
	end

	local existing = self.playerAttachment
	if existing ~= nil and existing.Parent == root then
		return existing
	end

	if existing ~= nil then
		existing:Destroy()
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "GuideStart"
	attachment.Position = Vector3.new(0, Config.Guide.LiftAtPlayerStuds, 0)
	attachment.Parent = root
	self.playerAttachment = attachment
	return attachment
end

local function refresh(self: GuideHandle)
	local target = self.target
	if target == nil then
		self.core.Enabled = false
		self.halo.Enabled = false
		self.waypoint.Enabled = false
		return
	end

	local from = playerEnd(self)
	if from == nil then
		-- Mid-respawn. The waypoint keeps standing where it stands — it is a fact
		-- about the world, not about the body — and the line comes back with the
		-- character it has to start from.
		self.core.Enabled = false
		self.halo.Enabled = false
		return
	end

	self.core.Attachment0 = from
	self.halo.Attachment0 = from

	local distance = (from.WorldPosition - target).Magnitude
	self.distanceText.Text = formatDistance(distance)

	-- Arrived. The waypoint stays, because knowing what you are standing in front of
	-- is still worth something; the line goes, because it would now be pointing at
	-- the floor beneath you.
	local visible = distance > Config.Guide.ArrivedRadiusStuds
	self.core.Enabled = visible
	self.halo.Enabled = visible
	self.waypoint.Enabled = true
end

-- Point somewhere, or nowhere. The only thing the server ever calls.
function Guide.Set(self: GuideHandle, state: GuideState)
	local target = state.target
	self.target = target

	if target == nil then
		self.core.Enabled = false
		self.halo.Enabled = false
		self.waypoint.Enabled = false
		-- The connection is dropped rather than left spinning on a hidden beam. A
		-- player spends nearly their whole life with nowhere in particular to be, so
		-- this is the state that has to cost nothing.
		local running = self.connection
		if running ~= nil then
			running:Disconnect()
			self.connection = nil
		end
		return
	end

	self.anchor.Position = target + Vector3.new(0, Config.Guide.LiftAtTargetStuds, 0)
	self.labelText.Text = state.label or ""

	-- Drawn straight away rather than on the next tick, so a guide that appears the
	-- instant you turn sixteen appears the instant you turn sixteen.
	refresh(self)

	if self.connection == nil then
		local since = 0
		self.connection = RunService.Heartbeat:Connect(function(delta: number)
			since += delta
			if since < Config.Guide.RefreshSeconds then
				return
			end
			since = 0

			-- The halo breathes: a gentle width oscillation that makes the glow
			-- feel alive without being distracting. The core stays steady.
			local guide = Config.Guide
			if guide.PulseStrengthStuds > 0 then
				local pulse = math.sin(tick() * guide.PulseSpeed * math.pi * 2)
					* guide.PulseStrengthStuds
				self.halo.Width0 = guide.HaloWidthNearStuds + pulse
				self.halo.Width1 = guide.HaloWidthFarStuds + pulse
			end

			refresh(self)
		end)
	end
end

return Guide
