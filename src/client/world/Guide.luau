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
-- The path itself used to be one straight segment from the player to the target,
-- which cut through buildings and off the edge of roads the moment either end sat
-- around a corner. It now asks `PathfindingService` for a route -- the same navmesh
-- `NPCService` already walks its townsfolk on, with the same agent size, so a guide
-- never promises a line an NPC's own body could not fit through. Full recomputes are
-- throttled to `RouteRefreshSeconds`, because asking the navmesh is not free and the
-- corners it finds do not move just because the player took another step; the leg
-- from the player to the first of those corners is re-anchored to their live
-- position on every refresh regardless, so the path never lags a step behind their
-- feet even between recomputes.
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

local PathfindingService = game:GetService("PathfindingService")
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
		-- Fixed-size pool of arrows, each a pair of wing bars forming a "V", plus a
		-- dark outline part behind each wing for contrast against any ground.
		-- Built once; rebuildPath only ever repositions or hides them.
		arrowsFolder: Folder,
		arrows: { { left: Part, right: Part, leftOutline: Part, rightOutline: Part } },
		-- Parallel arrays, valid for the first `activeCount` slots only -- how far
		-- along the path that arrow sits, and how faded its edge-of-path alpha is.
		-- Read every frame by the flow animation, written only when the path is
		-- re-walked.
		arrowAlong: { number },
		arrowEdgeAlpha: { number },
		activeCount: number,
		rayParams: RaycastParams,
		target: Vector3?,
		-- The current road-following polyline, corner to corner, from the last full
		-- PathfindingService compute -- point 1 is re-anchored to the player's live
		-- position on every refresh, the rest only changes when the route itself is
		-- recomputed. At least 2 points whenever `target` is set.
		routePoints: { Vector3 },
		-- What `target` was the last time the route was actually recomputed, so a new
		-- target forces a fresh route immediately rather than waiting out the timer
		-- below on a corner structure that pointed somewhere else.
		routeTarget: Vector3?,
		-- os.clock() of the last full recompute, throttled against by RouteRefreshSeconds.
		routeComputedAt: number,
		connection: RBXScriptConnection?,
	},
	Guide
))

-- The agent a route is asked for. Same body size `NPCService` already computes routes
-- for, so a guide never draws a line through a gap only a player's own thinner
-- hitbox could pass -- the arrows point somewhere an NPC could actually be walking.
local ROUTE_AGENT_PARAMS = {
	AgentRadius = Config.NPC.BodyRadius,
	AgentHeight = Config.NPC.BodyHeight,
	AgentCanJump = true,
}

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

-- The dark rim behind a wing: same shape, a margin larger on every side, not
-- neon. Positioned each refresh at the same CFrame as its wing but dropped
-- slightly along the ground normal, so the bright top face still shows through
-- and the rim reads as an outline rather than a second, bigger arrow.
local function newOutline(name: string, guide: typeof(Config.Guide)): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(
		guide.ArrowWingThicknessStuds + guide.ArrowOutlineMarginStuds * 2,
		guide.ArrowWingHeightStuds,
		guide.ArrowWingLengthStuds + guide.ArrowOutlineMarginStuds * 2
	)
	part.Color = guide.OutlineColor
	part.Material = Enum.Material.SmoothPlastic
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
		local leftOutline = newOutline(`Wing{i}LOutline`, guide)
		local rightOutline = newOutline(`Wing{i}ROutline`, guide)
		leftOutline.Parent = arrowsFolder
		rightOutline.Parent = arrowsFolder
		left.Parent = arrowsFolder
		right.Parent = arrowsFolder
		arrows[i] = { left = left, right = right, leftOutline = leftOutline, rightOutline = rightOutline }
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
		routePoints = {},
		routeTarget = nil,
		routeComputedAt = 0,
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
		pair.leftOutline.Transparency = 1
		pair.rightOutline.Transparency = 1
	end
end

-- Asks the navmesh for a route rather than assuming a straight line, and falls back
-- to one on any failure -- an unreachable spot, a navmesh gap, a target the player
-- teleported next to that nothing has walked before. A guide that vanished when
-- pathfinding had a bad day would be worse than one that goes straight for a few
-- studs; the raycast ground-hugging below still keeps that fallback flush with the
-- floor even though it no longer bends around anything.
local function computeRoute(from: Vector3, target: Vector3): { Vector3 }
	local ok, path = pcall(PathfindingService.CreatePath, PathfindingService, ROUTE_AGENT_PARAMS)
	if not ok then
		return { from, target }
	end
	local computed = pcall(function()
		path:ComputeAsync(from, target)
	end)
	if not computed or path.Status ~= Enum.PathStatus.Success then
		path:Destroy()
		return { from, target }
	end
	local waypoints = path:GetWaypoints()
	path:Destroy()
	if #waypoints < 2 then
		return { from, target }
	end
	local points = table.create(#waypoints)
	for _, waypoint in waypoints do
		table.insert(points, waypoint.Position)
	end
	return points
end

-- The full length of a polyline, corner to corner.
local function routeLength(points: { Vector3 }): number
	local total = 0
	for i = 1, #points - 1 do
		total += (points[i + 1] - points[i]).Magnitude
	end
	return total
end

-- Where `along` studs into the route lands, and which way that leg of it runs.
-- Clamps into the final leg past the end rather than erroring, since edge-fade
-- rounding can ask for a hair past the route's own measured length.
local function pointAlong(points: { Vector3 }, along: number): (Vector3, Vector3)
	local remaining = along
	local lastLegCount = #points - 1
	for i = 1, lastLegCount do
		local segStart = points[i]
		local segEnd = points[i + 1]
		local segVector = segEnd - segStart
		local segLength = segVector.Magnitude
		if remaining <= segLength or i == lastLegCount then
			local fraction = if segLength > 1e-4 then math.clamp(remaining / segLength, 0, 1) else 0
			local position = segStart + segVector * fraction
			local horizontal = Vector3.new(segVector.X, 0, segVector.Z)
			local direction = if horizontal.Magnitude > 1e-4 then horizontal.Unit else Vector3.new(0, 0, 1)
			return position, direction
		end
		remaining -= segLength
	end
	local last = points[#points]
	return last, Vector3.new(0, 0, 1)
end

-- Re-walks the path from the player's feet to the target, ground first: one
-- downward raycast per arrow slot, so the chain follows a slope or a flight of
-- steps instead of assuming the ground is flat between the two ends. The shape it
-- walks is the road-following route above, not a straight line -- only how bright
-- each arrow is this instant is `animateFlow`'s job, every frame, not this one's.
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

	self.waypoint.Enabled = true

	-- The route's corner structure is only worth asking the navmesh for again once
	-- in a while, or the moment the target itself changed underneath it -- either
	-- way the near leg still gets re-anchored to `from` below regardless, so this
	-- never shows a route starting somewhere the player already left.
	local now = os.clock()
	local routeTarget = self.routeTarget
	if #self.routePoints < 2 or routeTarget == nil or (routeTarget - target).Magnitude > 0.5 or now - self.routeComputedAt >= guide.RouteRefreshSeconds then
		self.routePoints = computeRoute(from, target)
		self.routeComputedAt = now
		self.routeTarget = target
	else
		self.routePoints[1] = from
		self.routePoints[#self.routePoints] = target
	end

	local totalDistance = routeLength(self.routePoints)
	self.distanceText.Text = formatDistance(totalDistance)

	-- Arrived, judged by the walk still left on the route rather than the
	-- straight-line distance to the target. A target around a corner can sit
	-- well inside ArrivedRadiusStuds as the crow flies while most of a block is
	-- still ahead on foot -- that used to clear the arrows with the player still
	-- mid-route and nothing left pointing the rest of the way. The route's own
	-- length already folds in every corner it bends around, so it is the honest
	-- measure of "arrived", and it doubles as the degenerate-route guard the old
	-- `totalDistance < 1` check existed for, since ArrivedRadiusStuds is well
	-- above 1. The waypoint stays regardless -- knowing what you are standing in
	-- front of is still worth something -- only the path goes.
	if totalDistance <= guide.ArrivedRadiusStuds then
		hideArrowsFrom(self, 1)
		self.activeCount = 0
		return
	end

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
		local samplePoint, direction = pointAlong(self.routePoints, along)

		local origin = samplePoint + Vector3.new(0, RAY_UP_STUDS, 0)
		local result = workspace:Raycast(origin, Vector3.new(0, -(RAY_UP_STUDS + RAY_DOWN_STUDS), 0), self.rayParams)

		local groundPosition: Vector3
		local normal: Vector3
		if result ~= nil then
			groundPosition = result.Position
			normal = result.Normal
		else
			-- No ground found under this sample (a gap, a void, a raycast filter
			-- miss) -- the route point itself already carries a real height, since
			-- it came off the navmesh or off the player's and target's own feet, so
			-- that is the fallback rather than a straight interpolation between the
			-- two far ends of the whole path.
			groundPosition = samplePoint
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
		for _, wing in
			{
				{ part = pair.left, outline = pair.leftOutline, side = -1 },
				{ part = pair.right, outline = pair.rightOutline, side = 1 },
			}
		do
			local wingDirection = (-direction * math.cos(angle) + rightAxis * wing.side * math.sin(angle)).Unit
			local wingCenter = tip + wingDirection * (guide.ArrowWingLengthStuds * 0.5)
			local wingCFrame = CFrame.lookAt(wingCenter, wingCenter + wingDirection, normal)
			wing.part.CFrame = wingCFrame
			wing.outline.CFrame = wingCFrame - normal * guide.ArrowOutlineDropStuds
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
	local restColor = guide.Color
	local peakColor = guide.FlowPeakColor
	local outlineRestT = guide.OutlineTransparency

	for i = 1, self.activeCount do
		local along = self.arrowAlong[i]
		local phase = (along - now * guide.FlowSpeedStuds) % wavelength
		local waveAlpha = 0.5 + 0.5 * math.cos((phase / wavelength) * math.pi * 2)
		local transparency = restT - (restT - peakT) * waveAlpha

		local edgeAlpha = self.arrowEdgeAlpha[i]
		local final = 1 - (1 - transparency) * edgeAlpha
		local finalOutline = 1 - (1 - outlineRestT) * edgeAlpha
		local color = restColor:Lerp(peakColor, waveAlpha)

		local pair = self.arrows[i]
		pair.left.Transparency = final
		pair.right.Transparency = final
		pair.left.Color = color
		pair.right.Color = color
		pair.leftOutline.Transparency = finalOutline
		pair.rightOutline.Transparency = finalOutline
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
		self.routePoints = {}
		self.routeTarget = nil
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
