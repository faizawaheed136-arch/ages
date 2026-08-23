--!strict
-- The chevron path on the ground that says "go there".
--
-- Drawn on the client, and that is the whole reason this file exists rather than
-- something WorkService builds alongside the hiring signs. Everything else this
-- game puts in the world is public -- a choice pad, a sign, a dog -- and being seen
-- by whoever walks past is either harmless or the point. Directions are not: they
-- are addressed to one person, and three players in one shop would otherwise stand
-- in a cat's cradle of each other's arrows. Built here, the path exists only for
-- the player it belongs to, and the server's whole side of it is a position and a
-- name.
--
-- Was a pair of floating Beams welded to attachments at fixed heights with an
-- artificial sag between them, textured with a chevron image that never shipped --
-- there is still no Roblox group to upload one to. This version needs no asset:
-- each arrow is two thin neon bars meeting in a "V", built from vectors, and the
-- whole chain is walked down onto the real ground with a downward raycast per
-- arrow rather than guessed at with a fixed curve. It follows a slope, a kerb or a
-- flight of steps the old beam had no way to know was there.
--
-- Fixed-size pool, not create-and-destroy. `Config.Guide.MaxArrows` bars are built
-- once in `Guide.new()` and only ever repositioned or hidden; a guide to the far
-- side of the map costs exactly the same as one to the next room over, just spaced
-- further apart. Two update rates run on the same Heartbeat connection: the path's
-- shape (every arrow's ground height, orientation and count) only needs to be
-- re-walked at `RefreshSeconds`, the same as before, but the travelling brightness
-- wave that makes the path feel like it flows toward the destination needs every
-- frame or it reads as a slideshow.
--
-- The waypoint is unchanged: it answers "what is over there?" and is *most* useful
-- once you can see the building, so it stays even after the arrows disappear on
-- arrival. It also carries the distance, which is what turns a direction into a
-- decision: "Shop assistant, 140 studs" is something a player can weigh against
-- whatever else they were doing.
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
-- Config is everything that decides where the path goes, how it is shaped and
-- when it stops.
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

-- How far above and below a sample point the ground is searched for. Generous on
-- purpose: a raycast that comes up empty falls back to a straight interpolation
-- between the two ends rather than leaving a gap in the path, but the fallback
-- looks worse than a real hit, so the search window is wide enough to find a roof,
-- a bridge deck or a basement floor rather than only the ground directly below.
local RAY_UP_STUDS = 15
local RAY_DOWN_STUDS = 60

export type GuideHandle = typeof(setmetatable(
	{} :: {
		-- The part the waypoint is adorned to. Anchored, invisible, and moved
		-- rather than rebuilt each time the target changes.
		anchor: Part,
		waypoint: BillboardGui,
		chipFrame: Frame,
		labelText: TextLabel,
		distanceText: TextLabel,
		-- Fixed-size pool of arrows, each a pair of wing bars forming a "V". Built
		-- once; rebuildPath only ever repositions or hides them.
		arrowsFolder: Folder,
		arrows: { { left: Part, right: Part } },
		-- Parallel arrays, valid for the first `activeCount` slots only -- how far
		-- along the path that arrow sits, and how faded its edge-of-path alpha is.
		-- Read every frame by the flow animation, written only when the path is
		-- re-walked.
		arrowAlong: { number },
		arrowEdgeAlpha: { number },
		activeCount: number,
		rayParams: RaycastParams,
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

-- One wing bar: a thin, self-lit box. Symmetric along its own length, which is
-- what makes `CFrame.lookAt` safe to orient it with below without caring which of
-- Roblox's two sign conventions for LookVector is the true one -- a bar looks
-- identical pointed either way down its own long axis.
local function newWing(name: string, guide: typeof(Config.Guide)): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(guide.ArrowWingThicknessStuds, guide.ArrowWingHeightStuds, guide.ArrowWingLengthStuds)
	part.Color = guide.Color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	return part
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

	local arrowsFolder = Instance.new("Folder")
	arrowsFolder.Name = "AgesGuideArrows"
	arrowsFolder.Parent = workspace

	local arrows = {}
	for i = 1, guide.MaxArrows do
		local left = newWing(`Wing{i}L`, guide)
		local right = newWing(`Wing{i}R`, guide)
		left.Parent = arrowsFolder
		right.Parent = arrowsFolder
		arrows[i] = { left = left, right = right }
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true

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
		waypoint = waypoint,
		chipFrame = chipFrame,
		labelText = labelText,
		distanceText = distance,
		arrowsFolder = arrowsFolder,
		arrows = arrows,
		arrowAlong = table.create(guide.MaxArrows, 0),
		arrowEdgeAlpha = table.create(guide.MaxArrows, 0),
		activeCount = 0,
		rayParams = rayParams,
		target = nil,
		connection = nil,
	}, Guide)
end

-- Where the player is standing right now, or nil mid-respawn. Re-resolved every
-- call rather than cached: a life ends and a new body arrives without this module
-- being told, and the guide is about where you are going, not about the body
-- currently carrying you there. Cheap enough to ask every refresh.
local function playerPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

-- Hide every pooled arrow from `from` (inclusive) onward. Used both to clear a
-- path entirely and to retract the tail end of the pool when the path just got
-- shorter than it was last refresh.
local function hideArrowsFrom(self: GuideHandle, from: number)
	local arrows = self.arrows
	for i = from, #arrows do
		local pair = arrows[i]
		pair.left.Transparency = 1
		pair.right.Transparency = 1
	end
end

-- Re-walks the path from the player's feet to the target, ground first: one
-- downward raycast per arrow slot, so the chain follows a slope or a flight of
-- steps instead of assuming the ground is flat between the two ends. Only the
-- shape of the path is decided here -- how bright each arrow is this instant is
-- `animateFlow`'s job, every frame, not this one's.
local function rebuildPath(self: GuideHandle)
	local guide = Config.Guide
	local target = self.target
	if target == nil then
		self.waypoint.Enabled = false
		hideArrowsFrom(self, 1)
		self.activeCount = 0
		return
	end

	local from = playerPosition()
	if from == nil then
		-- Mid-respawn. The waypoint keeps standing where it stands — it is a fact
		-- about the world, not about the body — and the path comes back with the
		-- character it has to start from.
		hideArrowsFrom(self, 1)
		self.activeCount = 0
		return
	end

	local distance = (from - target).Magnitude
	self.distanceText.Text = formatDistance(distance)
	self.waypoint.Enabled = true

	-- Arrived. The waypoint stays, because knowing what you are standing in front
	-- of is still worth something; the path goes, because it would now be pointing
	-- at the ground under your own feet.
	if distance <= guide.ArrivedRadiusStuds then
		hideArrowsFrom(self, 1)
		self.activeCount = 0
		return
	end

	local delta = target - from
	local horizontal = Vector3.new(delta.X, 0, delta.Z)
	local totalDistance = horizontal.Magnitude
	if totalDistance < 1 then
		-- Directly above or below the player somehow (a vault, a rooftop). No
		-- horizontal direction to lay arrows along; the waypoint alone still says
		-- what is there.
		hideArrowsFrom(self, 1)
		self.activeCount = 0
		return
	end
	local direction = horizontal.Unit

	-- A path longer than MaxArrows * ArrowSpacingStuds spaces its arrows further
	-- apart rather than growing the pool, so a cross-map guide never costs more
	-- than a next-door one.
	local spacing = math.max(guide.ArrowSpacingStuds, totalDistance / guide.MaxArrows)
	local count = math.clamp(math.floor(totalDistance / spacing), 1, guide.MaxArrows)

	self.rayParams.FilterDescendantsInstances = {
		Players.LocalPlayer.Character,
		self.arrowsFolder,
		self.anchor,
	}

	for i = 1, count do
		local along = (i - 0.5) * spacing
		local samplePoint = from + direction * along

		local origin = samplePoint + Vector3.new(0, RAY_UP_STUDS, 0)
		local result = workspace:Raycast(origin, Vector3.new(0, -(RAY_UP_STUDS + RAY_DOWN_STUDS), 0), self.rayParams)

		local groundPosition: Vector3
		local normal: Vector3
		if result ~= nil then
			groundPosition = result.Position
			normal = result.Normal
		else
			-- No ground found (a gap, a void, a raycast filter miss) — fall back to
			-- a straight interpolation between the two known endpoints rather than
			-- leaving a hole in the path.
			local alpha = along / totalDistance
			groundPosition = Vector3.new(samplePoint.X, from.Y + (target.Y - from.Y) * alpha, samplePoint.Z)
			normal = Vector3.new(0, 1, 0)
		end

		local center = groundPosition + normal * guide.ArrowLiftStuds
		local nearFade = math.clamp(along / guide.ArrowEdgeFadeStuds, 0, 1)
		local farFade = math.clamp((totalDistance - along) / guide.ArrowEdgeFadeStuds, 0, 1)
		self.arrowAlong[i] = along
		self.arrowEdgeAlpha[i] = math.min(nearFade, farFade)

		local tip = center + direction * (guide.ArrowWingLengthStuds * 0.5)
		local angle = math.rad(guide.ArrowWingAngleDegrees)
		local rightAxis = direction:Cross(normal)
		if rightAxis.Magnitude < 1e-4 then
			rightAxis = direction:Cross(Vector3.new(0, 1, 0))
		end
		rightAxis = rightAxis.Unit

		local pair = self.arrows[i]
		for _, wing in { { part = pair.left, side = -1 }, { part = pair.right, side = 1 } } do
			local wingDirection = (-direction * math.cos(angle) + rightAxis * wing.side * math.sin(angle)).Unit
			local wingCenter = tip + wingDirection * (guide.ArrowWingLengthStuds * 0.5)
			wing.part.CFrame = CFrame.lookAt(wingCenter, wingCenter + wingDirection, normal)
		end
	end

	if count < #self.arrows then
		hideArrowsFrom(self, count + 1)
	end
	self.activeCount = count
end

-- The travelling brightness wave that makes the path read as flowing toward the
-- destination rather than just sitting there. Runs every Heartbeat frame,
-- unthrottled — it only ever touches Transparency on the arrows rebuildPath has
-- already placed this refresh, never their position, so it stays cheap at any
-- frame rate.
local function animateFlow(self: GuideHandle, now: number)
	local guide = Config.Guide
	local wavelength = guide.FlowWaveLengthStuds
	local restT = guide.FlowRestTransparency
	local peakT = guide.FlowPeakTransparency

	for i = 1, self.activeCount do
		local along = self.arrowAlong[i]
		local phase = (along - now * guide.FlowSpeedStuds) % wavelength
		local waveAlpha = 0.5 + 0.5 * math.cos((phase / wavelength) * math.pi * 2)
		local transparency = restT - (restT - peakT) * waveAlpha

		local edgeAlpha = self.arrowEdgeAlpha[i]
		local final = 1 - (1 - transparency) * edgeAlpha

		local pair = self.arrows[i]
		pair.left.Transparency = final
		pair.right.Transparency = final
	end
end

-- Point somewhere, or nowhere. The only thing the server ever calls.
function Guide.Set(self: GuideHandle, state: GuideState)
	local target = state.target
	self.target = target
	self.labelText.Text = state.label or ""

	if target == nil then
		self.waypoint.Enabled = false
		hideArrowsFrom(self, 1)
		self.activeCount = 0
		-- The connection is dropped rather than left spinning on a hidden path. A
		-- player spends nearly their whole life with nowhere in particular to be,
		-- so this is the state that has to cost nothing.
		local running = self.connection
		if running ~= nil then
			running:Disconnect()
			self.connection = nil
		end
		return
	end

	self.anchor.Position = target + Vector3.new(0, Config.Guide.LiftAtTargetStuds, 0)

	-- Drawn straight away rather than on the next tick, so a guide that appears the
	-- instant you turn sixteen appears the instant you turn sixteen.
	rebuildPath(self)
	animateFlow(self, os.clock())

	if self.connection == nil then
		local since = 0
		self.connection = RunService.Heartbeat:Connect(function(delta: number)
			animateFlow(self, os.clock())

			since += delta
			if since < Config.Guide.RefreshSeconds then
				return
			end
			since = 0
			rebuildPath(self)
		end)
	end
end

return Guide
