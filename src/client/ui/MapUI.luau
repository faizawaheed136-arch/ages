--!strict
-- The full map: a sheet you can zoom into and drag around, with the four gang sides
-- available behind a button.
--
-- Opened from the minimap or with M, and it is a sheet rather than a fullscreen takeover
-- -- the game keeps running behind it, dimmed. A life simulator where opening the map
-- pauses the world would be teaching the player that the map is a menu, and it is not: it
-- is a thing you look at while deciding where to walk.
--
-- **The sheet shows landmarks, and hands the rest back as you zoom in.** This world has
-- several hundred place points. Drawing all of them was the first version and it produced
-- a square of confetti -- technically complete and completely unreadable, and the failure
-- mode of a map is not "it left something out", it is "I could not find the bank". So a
-- place carries a tier in `Config.Map.Icons.Rules` and appears at the zoom its tier names.
-- Nothing is dropped; it is filed. Zooming in is how you ask for the next layer, which is
-- also what gives the zoom something to do besides magnify.
--
-- **The region overlay is off until it is asked for, and it draws lines rather than
-- stains.** Territory is one question among several the map answers, and it was previously
-- the loudest thing on the sheet whether or not anybody had asked. It now sits behind a
-- toggle in the top bar. What it draws changed too, and that is the more important half:
-- see `buildRegions`.
--
-- **Everything geographic lives inside one Frame and that Frame is what moves.** Zoom is
-- its size, pan is its position, and every dot inside it is placed in scale and sized in
-- offset -- so a dot lands in the right place at every zoom and stays the same number of
-- pixels across. The alternative is recomputing several hundred positions on every wheel
-- click, which is the version that makes a map feel heavy.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local WorldMap = require(ReplicatedStorage:WaitForChild("WorldMap"))
local MapIcons = require(script.Parent.MapIcons)
local MapTerrain = require(script.Parent.MapTerrain)

type MapData = Types.MapData
type TerritoryState = Types.TerritoryState

local MAP = Config.Map
local MOTION = Config.UI.Menu.Motion
-- The menu's palette, deliberately. The map and the menu are two halves of the same
-- screen furniture and a player crosses between them in a keystroke; two palettes would
-- read as two games.
local PALETTE = Config.UI.Palette

local FONT_BOLD = Font.fromEnum(Enum.Font.GothamBold)
local FONT_MEDIUM = Font.fromEnum(Enum.Font.GothamMedium)
local FONT_BODY = Font.fromEnum(Enum.Font.Gotham)

local ENTER = TweenInfo.new(MOTION.EnterSeconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local EXIT = TweenInfo.new(MOTION.ExitSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOVER = TweenInfo.new(MOTION.HoverSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ZOOM = TweenInfo.new(MAP.ZoomSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- The bar along the bottom that says how far a hundred-odd pixels is. One of these
-- lengths is picked per zoom -- the one that comes closest to `SCALE_TARGET_PIXELS`
-- without going over -- so the number on it is always round.
local SCALE_STUDS = { 25, 50, 100, 200, 500, 1000, 2000 }
local SCALE_TARGET_PIXELS = 110

-- Layers inside the sheet, so that "which of these draws on top" is one list rather than
-- a number invented at each site.
local Z_LAND = 1
-- The drawn world sits between the ground rectangle and the territory overlay, in two
-- layers of its own so a roof always covers the road it fronts onto.
local Z_SHAPE_GROUND = 2
local Z_SHAPE_BUILDING = 3
local Z_REGION_FILL = 4
local Z_REGION_EDGE = 5
local Z_GRID = 6
local Z_ICON = 10
local Z_YOU = 40
-- The invisible sheet-sized button that catches the wheel and the drag. Above everything
-- geographic so no dot can steal a click, below every control so no control is smothered.
local Z_GRAB = 50
local Z_CHROME = 60

local MapUI = {}
MapUI.__index = MapUI

-- One drawn place, with the two things the zoom needs to know about it.
type IconEntry = {
	dot: Frame,
	labelText: TextLabel?,
	tier: string,
}

export type MapUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		backdrop: TextButton,
		sheet: Frame,
		-- The moving Frame. Its size is the zoom and its position is the pan; nothing
		-- inside it is ever repositioned by either.
		world: Frame,
		gridFolder: Frame,
		regionFolder: Frame,
		plateFolder: Frame,
		shapeFolder: Frame,
		iconFolder: Frame,
		youDot: Frame,
		titleLabel: TextLabel,
		placeLabel: TextLabel,
		gangRow: Frame,
		territoryButton: TextButton,
		scaleBar: Frame,
		scaleLabel: TextLabel,
		data: MapData?,
		territory: TerritoryState?,
		icons: { IconEntry },
		showRegions: boolean,
		regionsBuilt: boolean,
		-- The view. `zoom` is how many sheets wide the world is drawn at, and the focus is
		-- the point of the world sitting under the middle of the sheet. Held as numbers
		-- rather than read back off the Frame so that a view being tweened into place is
		-- still the view the next wheel click is measured from.
		zoom: number,
		focusU: number,
		focusV: number,
		viewTween: Tween?,
		-- Where the last drag sample was, in pixels, or nil when nobody is dragging.
		dragFrom: Vector2?,
		open: boolean,
	},
	MapUI
))

-- -------------------------------------------------------------------
-- The same four helpers the menu is built out of, with the same names. These two files
-- are one piece of furniture as far as a player is concerned.
-- -------------------------------------------------------------------

-- A colour off the world, dressed for this panel.
--
-- Pulled toward its own grey first and toward the panel second -- see
-- `Config.Map.Shapes` for what each of the two is doing and why the picture is not
-- allowed to shout. Done here rather than baked into `MapShapes` so that both knobs stay
-- live: a value baked into a generated file is a value nobody will ever try changing.
local function corner(instance: GuiObject, radius: number)
	local rounded = Instance.new("UICorner")
	rounded.CornerRadius = UDim.new(0, radius)
	rounded.Parent = instance
end

local function stroke(instance: GuiObject, color: Color3, thickness: number, transparency: number): UIStroke
	local line = Instance.new("UIStroke")
	line.Color = color
	line.Thickness = thickness
	line.Transparency = transparency
	line.Parent = instance
	return line
end

local function label(parent: Instance, font: Font, size: number, color: Color3, align: Enum.TextXAlignment): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.FontFace = font
	text.TextSize = size
	text.TextColor3 = color
	text.TextXAlignment = align
	text.TextYAlignment = Enum.TextYAlignment.Center
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.Text = ""
	text.ZIndex = Z_CHROME + 1
	text.Parent = parent
	return text
end

-- A floating strip of chrome over the sheet: the top bar, the legend, the zoom cluster.
-- Translucent rather than solid so the map is still visible under it -- these sit on the
-- picture, and a control that hides the thing it is controlling is a control in the way.
local function panel(parent: Instance, name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = PALETTE.Panel
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel = 0
	frame.ZIndex = Z_CHROME
	frame.Parent = parent

	corner(frame, 10)
	stroke(frame, PALETTE.Edge, 1, 0.5)
	return frame
end

-- A small square button with a shape drawn in it, for the zoom cluster. Text would do the
-- job for "+" and "-" and nothing else in that cluster, and a row of two glyphs and a
-- drawing is the tell that somebody stopped halfway.
local function iconButton(parent: Instance, name: string, order: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(30, 30)
	button.LayoutOrder = order
	button.BackgroundColor3 = PALETTE.Row
	button.BackgroundTransparency = 0.05
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = Z_CHROME + 1
	button.Parent = parent

	corner(button, 8)
	stroke(button, PALETTE.Edge, 1, 0.55)

	button.MouseEnter:Connect(function()
		TweenService:Create(button, HOVER, { BackgroundColor3 = PALETTE.RowHover }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, HOVER, { BackgroundColor3 = PALETTE.Row }):Play()
	end)
	return button
end

-- A bar of ink inside a button, used to draw the plus, the minus and the crosshair.
local function bar(parent: Instance, w: number, h: number, color: Color3): Frame
	local mark = Instance.new("Frame")
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.Size = UDim2.fromOffset(w, h)
	mark.BackgroundColor3 = color
	mark.BorderSizePixel = 0
	mark.ZIndex = Z_CHROME + 2
	mark.Parent = parent
	corner(mark, 1)
	return mark
end

-- -------------------------------------------------------------------
-- The view: zoom, pan, and the two things that follow from them.
-- -------------------------------------------------------------------

-- The world Frame moved and resized to match `self.zoom` and the focus, with the focus
-- clamped so that the sheet is never showing anything off the edge of the world.
--
-- The clamp is what makes the pan feel like a map rather than like a draggable picture:
-- at any zoom the visible window is `1/zoom` of the world across, so the centre of that
-- window can never be closer to an edge than half of it.
local function applyView(self: MapUIHandle, animate: boolean)
	local zoom = self.zoom
	local half = 0.5 / zoom
	-- At zoom 1 this collapses to a single legal focus, which is exactly right: fully
	-- zoomed out there is nowhere to pan to.
	self.focusU = math.clamp(self.focusU, half, 1 - half)
	self.focusV = math.clamp(self.focusV, half, 1 - half)

	local size = UDim2.fromScale(zoom, zoom)
	local position = UDim2.fromScale(0.5 - self.focusU * zoom, 0.5 - self.focusV * zoom)

	local running = self.viewTween
	if running ~= nil then
		running:Cancel()
		self.viewTween = nil
	end

	if animate then
		local tween = TweenService:Create(self.world, ZOOM, { Size = size, Position = position })
		self.viewTween = tween
		tween:Play()
	else
		self.world.Size = size
		self.world.Position = position
	end
end

-- Which places are drawn, and which of those are named, for the zoom the sheet is at.
--
-- Called on every zoom change and nowhere else. It is a walk over every icon rather than
-- a set of pre-bucketed lists because the buckets would have to be rebuilt on every push
-- of map data and the walk is a few hundred boolean writes on a keypress.
local function applyDetail(self: MapUIHandle)
	local zoom = self.zoom
	for _, entry in self.icons do
		local dotAt = MAP.DetailZoom[entry.tier]
		local labelAt = MAP.LabelZoom[entry.tier]
		entry.dot.Visible = dotAt ~= nil and zoom >= dotAt
		local text = entry.labelText
		if text ~= nil then
			text.Visible = entry.dot.Visible and labelAt ~= nil and zoom >= labelAt
		end
	end
end

-- The bar at the bottom-left redrawn for the current zoom.
--
-- A map without one is a picture: it can say where things are relative to each other and
-- nothing at all about whether the walk is thirty seconds or five minutes, which on a
-- world this size is the question the player is actually asking.
local function applyScale(self: MapUIHandle)
	local data = self.data
	if data == nil then
		return
	end

	local sheetPixels = self.sheet.AbsoluteSize.X
	if sheetPixels <= 0 then
		return
	end
	local studsAcross = data.maxX - data.minX
	if studsAcross <= 0 then
		return
	end
	local pixelsPerStud = (sheetPixels * self.zoom) / studsAcross

	-- Largest round distance that still fits the bar. Falls back to the smallest entry
	-- when even that overshoots, so the bar is never zero-width on a tiny window.
	local chosen = SCALE_STUDS[1]
	for _, studs in SCALE_STUDS do
		if studs * pixelsPerStud <= SCALE_TARGET_PIXELS then
			chosen = studs
		end
	end

	local barPixels = math.max(math.floor(chosen * pixelsPerStud), 6)
	self.scaleBar.Size = UDim2.fromOffset(barPixels, 3)
	-- The label follows the bar rather than sitting at a fixed inset. The bar is as wide
	-- as the round distance it stands for and that width changes with every zoom, so a
	-- fixed inset is a collision waiting for the one zoom where the bar is longest.
	self.scaleLabel.Position = UDim2.new(0, barPixels + 8, 0.5, 0)
	self.scaleLabel.Text = `{chosen} studs`
end

local function refreshView(self: MapUIHandle, animate: boolean)
	applyView(self, animate)
	applyDetail(self)
	applyScale(self)
end

-- Zoom by one step, about a point of the sheet given in 0..1.
--
-- Zooming about the cursor rather than about the middle is the difference between a map
-- and a slideshow: the thing under the pointer is the thing the player is interested in,
-- and a zoom that walks it off the screen means every zoom costs a pan to undo it.
--
-- The identity is that the world point under the cursor must not move. A sheet point `s`
-- shows world point `focus + (s - 0.5) / zoom`, so holding that fixed across a change of
-- zoom gives the new focus directly.
local function zoomAbout(self: MapUIHandle, steps: number, sheetU: number, sheetV: number)
	local before = self.zoom
	local after = math.clamp(before * MAP.ZoomStep ^ steps, 1, MAP.MaxZoom)
	if after == before then
		return
	end

	local worldU = self.focusU + (sheetU - 0.5) / before
	local worldV = self.focusV + (sheetV - 0.5) / before
	self.zoom = after
	self.focusU = worldU - (sheetU - 0.5) / after
	self.focusV = worldV - (sheetV - 0.5) / after
	refreshView(self, true)
end

-- Put the player back under the middle of the sheet, at the zoom they are already at.
-- The one control on this screen that is about *them* rather than about the picture, and
-- the way back from having dragged somewhere and lost yourself.
local function recentre(self: MapUIHandle, animate: boolean)
	local data = self.data
	if data == nil then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil then
		return
	end

	local here = (root :: BasePart).Position
	local u, v = WorldMap.Normalize(
		{ minX = data.minX, maxX = data.maxX, minZ = data.minZ, maxZ = data.maxZ },
		here.X,
		here.Z
	)
	self.focusU, self.focusV = u, v
	refreshView(self, animate)
end

-- -------------------------------------------------------------------
-- The layers inside the world Frame.
-- -------------------------------------------------------------------

-- The world itself, as rectangles, under everything else on the sheet.
--
-- The drawing is `MapTerrain`, shared with the corner dial so that the two surfaces cannot
-- disagree about what the town looks like. All this decides is how big the sheet is, which
-- is the one thing the painter cannot know: it needs a pixel width to cull sub-pixel
-- rectangles by, and `AbsoluteSize` is zero until Roblox has laid the sheet out -- which it
-- has not, the first time the server pushes map data.
local function buildShapes(self: MapUIHandle, data: MapData)
	local sheetPixels = self.sheet.AbsoluteSize.X
	if sheetPixels <= 0 then
		sheetPixels = MAP.SheetAssumedPixels
	end

	MapTerrain.Paint(
		self.shapeFolder,
		{ minX = data.minX, maxX = data.maxX, minZ = data.minZ, maxZ = data.maxZ },
		sheetPixels,
		Z_SHAPE_GROUND,
		Z_SHAPE_BUILDING
	)
end

-- A line every `Config.Map.GridStuds`, in both axes.
--
-- Without it the sheet is dots on a void, and a player who zooms into a quiet corner has
-- no way to tell that anything happened -- the dots simply spread. A grid that scales
-- with the zoom answers that for the price of a dozen Frames, and it is the cheapest
-- thing on this screen that makes it read as a map rather than as a diagram.
local function buildGrid(self: MapUIHandle, data: MapData)
	for _, child in self.gridFolder:GetChildren() do
		child:Destroy()
	end

	local width = data.maxX - data.minX
	local depth = data.maxZ - data.minZ
	if width <= 0 or depth <= 0 then
		return
	end

	local function line(u: number, v: number, horizontal: boolean)
		local rule = Instance.new("Frame")
		rule.BackgroundColor3 = PALETTE.Edge
		rule.BackgroundTransparency = 0.72
		rule.BorderSizePixel = 0
		rule.ZIndex = Z_GRID
		rule.Parent = self.gridFolder
		-- One pixel thick in offset and full length in scale: the grid keeps its weight
		-- as the world Frame grows, which is what a graticule does and what a hairline
		-- scaled by five would not.
		if horizontal then
			rule.AnchorPoint = Vector2.new(0, 0.5)
			rule.Position = UDim2.fromScale(0, v)
			rule.Size = UDim2.new(1, 0, 0, 1)
		else
			rule.AnchorPoint = Vector2.new(0.5, 0)
			rule.Position = UDim2.fromScale(u, 0)
			rule.Size = UDim2.new(0, 1, 1, 0)
		end
	end

	local step = MAP.GridStuds
	local x = math.ceil(data.minX / step) * step
	while x < data.maxX do
		line((x - data.minX) / width, 0, false)
		x += step
	end
	local z = math.ceil(data.minZ / step) * step
	while z < data.maxZ do
		line(0, (z - data.minZ) / depth, true)
		z += step
	end
end

-- The four sides, as fills with real borders on them.
--
-- **A flat mosaic is not a territory map, and that is what this was.** Colouring every
-- sampled cell at one transparency gives four blurry stains with a grid visible inside
-- them, and the thing a player wants off a territory map is the *line*: where does one
-- side stop and the next begin. So this draws two things.
--
-- The fill is sampled, as it always was -- a side is "the ground nearer this boss than
-- any other", which is a Voronoi cell and has no outline to draw without solving for one
-- -- but the cells of a row are now merged into runs before they are drawn. Four sides
-- means at most a handful of runs per row, so the fill costs a couple of hundred Frames
-- instead of a couple of thousand, and it has no seams in it because a run is one Frame.
--
-- The borders are not sampled at all, and this is the part that makes it look like a map.
-- The boundary between two sides is their perpendicular bisector, which is a *straight
-- line* -- so it is drawn as one, rotated, exact at every zoom, with no staircase. Which
-- pairs of sides actually touch is the only thing that has to be discovered, and that is
-- done by walking each candidate line and keeping the stretch where those two are in fact
-- the nearest pair.
--
-- Sampling happens in world coordinates, never in the normalized 0..1 the icons use. The
-- world is about 1200 studs by 1650 and the sheet is square, so the two axes are scaled
-- by different factors -- "nearest boss" measured on the squashed sheet would put the
-- boundaries visibly in the wrong place. This is the one thing in this file that would be
-- silently, plausibly wrong if done the easy way.
local function buildRegions(self: MapUIHandle, data: MapData)
	if self.regionsBuilt then
		return
	end
	for _, child in self.regionFolder:GetChildren() do
		child:Destroy()
	end
	for _, child in self.plateFolder:GetChildren() do
		child:Destroy()
	end

	local bounds = { minX = data.minX, maxX = data.maxX, minZ = data.minZ, maxZ = data.maxZ }

	local sites: { WorldMap.Site } = {}
	for _, region in data.regions do
		local x, z = WorldMap.Denormalize(bounds, region.u, region.v)
		table.insert(sites, { id = region.id, x = x, z = z })
	end
	if #sites == 0 then
		return
	end

	-- ---- the fill, one Frame per run of one side along a strip ----

	-- Who owns the ground at this point on the sheet. Denormalized first, because a
	-- squashed sheet would put the answer in the wrong place -- see the header.
	local function ownerAt(u: number, v: number): string
		local worldX, worldZ = WorldMap.Denormalize(bounds, u, v)
		return WorldMap.StandingAt(sites, worldX, worldZ).id
	end

	-- The exact u where the side changes, given two u's known to be on opposite sides of
	-- a boundary.
	--
	-- **This is what stops the fill having a staircase along its edges.** Probing a fixed
	-- grid and painting whole cells was the old way and it drew the boundary as a flight
	-- of steps whose tread grew with the zoom -- so the closer a player looked at a
	-- border, the less like a border it got. Twenty halvings puts the edge inside a
	-- millionth of the sheet, which is under a pixel at any zoom this map allows.
	-- Returns the crossing, and who is on the far side of it. The second half matters
	-- where three sides meet: the far side is not necessarily whoever owned the end of the
	-- probe interval, because there can be another side wedged in between.
	--
	-- The number handed back is `hi` and not the midpoint of the final bracket. `hi` is a
	-- point this function actually sampled and found on the far side, so using it as the
	-- left end of the next search makes that search's invariant true by construction. The
	-- midpoint is never sampled and can land a hair on the near side -- which starts the
	-- next bisection with a false premise, and a bisection given a false premise converges
	-- on its own left end and returns a zero-width run forever.
	local function crossing(lo: number, hi: number, loOwner: string, v: number): (number, string)
		local hiOwner = ownerAt(hi, v)
		for _ = 1, 24 do
			local mid = (lo + hi) / 2
			local midOwner = ownerAt(mid, v)
			if midOwner == loOwner then
				lo = mid
			else
				hi = mid
				hiOwner = midOwner
			end
		end
		return hi, hiOwner
	end

	local rows = MAP.RegionRows
	local rowHeight = 1 / rows
	local probes = MAP.RegionSampleCells

	for row = 0, rows - 1 do
		local top = row * rowHeight
		local v = top + rowHeight / 2

		local runOwner = ownerAt(0, v)
		local runStart = 0
		local previousU = 0

		-- Walk the strip, and every time the side changes between two probes, solve for
		-- where it actually changed and end the run exactly there.
		local function closeRun(endU: number)
			local color = MapIcons.RegionColor(data, runOwner)
			if color == nil or endU <= runStart then
				return
			end
			local fill = Instance.new("Frame")
			fill.Name = runOwner
			fill.Position = UDim2.fromScale(runStart, top)
			fill.Size = UDim2.fromScale(endU - runStart, rowHeight)
			fill.BackgroundColor3 = color
			fill.BackgroundTransparency = MAP.RegionFillTransparency
			fill.BorderSizePixel = 0
			fill.ZIndex = Z_REGION_FILL
			fill.Parent = self.regionFolder
		end

		for probe = 1, probes do
			local u = probe / probes
			local endOwner = ownerAt(u, v)
			local lo = previousU

			-- **A loop rather than an `if`, because more than one boundary can fall inside
			-- one probe interval.** Near the point where three sides meet, a strip can
			-- cross a sliver of a third side that is thinner than the probe spacing --
			-- and splitting off only the first crossing there leaves that sliver painted
			-- as nobody's, which shows as a notch of bare ground at the exact place the
			-- overlay is meant to be explaining. Each pass peels off the leftmost
			-- remaining crossing, so this ends when the run reaches the far probe.
			-- Bounded, because this is a drawing pass and there is no picture worth
			-- hanging a client for. A side cannot be crossed twice along a straight line
			-- -- the cells are convex -- so one pass per side is already generous, and
			-- falling out of it early costs a few mis-coloured pixels next to a vertex.
			local passes = 0
			while endOwner ~= runOwner and passes < #sites do
				passes += 1
				local edge, nextOwner = crossing(lo, u, runOwner, v)
				closeRun(edge)
				runOwner = nextOwner
				runStart = edge
				lo = edge
			end
			runOwner = endOwner
			previousU = u
		end
		closeRun(1)
	end

	-- ---- the borders, one rotated Frame per pair that actually touches ----

	-- Whether these two are the two nearest sites to this point, which is what it means
	-- for the ground here to be on the line between them.
	local function isSharedEdge(a: WorldMap.Site, b: WorldMap.Site, x: number, z: number): boolean
		local owner = WorldMap.StandingAt(sites, x, z).id
		if owner ~= a.id and owner ~= b.id then
			return false
		end
		-- The nearest of everybody else. If any third site is closer than these two are,
		-- this stretch of the bisector is buried inside somebody else's ground and there
		-- is no line here to draw.
		local mine = math.min((x - a.x) ^ 2 + (z - a.z) ^ 2, (x - b.x) ^ 2 + (z - b.z) ^ 2)
		for _, other in sites do
			if other.id ~= a.id and other.id ~= b.id then
				if (x - other.x) ^ 2 + (z - other.z) ^ 2 < mine then
					return false
				end
			end
		end
		return true
	end

	-- How finely each candidate bisector is walked looking for the stretch that is really
	-- a border. The walk spans the world diagonal in both directions from the midpoint, so
	-- this is the *only* thing standing between a short border and no border at all: an
	-- edge shorter than one step falls between two samples and is never found. Two sides
	-- can share a very short edge -- it happens wherever a third side nearly reaches the
	-- line between them -- and a boundary the fill draws with no line along it reads as a
	-- hole in the overlay rather than as a border.
	local SAMPLES = 600
	for i = 1, #sites do
		for j = i + 1, #sites do
			local a, b = sites[i], sites[j]
			local midX, midZ = (a.x + b.x) / 2, (a.z + b.z) / 2
			-- The bisector's direction is perpendicular to the line joining the two.
			local dx, dz = b.x - a.x, b.z - a.z
			local length = math.sqrt(dx * dx + dz * dz)
			if length <= 0 then
				continue
			end
			local px, pz = -dz / length, dx / length

			-- Long enough to cross the world from the midpoint in either direction, so the
			-- walk below cannot stop short of the map edge and leave a border hanging.
			local reach = math.sqrt((data.maxX - data.minX) ^ 2 + (data.maxZ - data.minZ) ^ 2)

			-- Whether the point this far along the bisector is on the map and is really
			-- on the border between these two.
			local function onEdge(t: number): boolean
				local x, z = midX + px * t, midZ + pz * t
				return x >= data.minX
					and x <= data.maxX
					and z >= data.minZ
					and z <= data.maxZ
					and isSharedEdge(a, b, x, z)
			end

			local step = (2 * reach) / SAMPLES
			local firstT: number? = nil
			local lastT: number? = nil
			for sample = 0, SAMPLES do
				local t = -reach + step * sample
				if onEdge(t) then
					if firstT == nil then
						firstT = t
					end
					lastT = t
				end
			end

			if firstT == nil or lastT == nil then
				continue
			end

			-- The walk can only place an end within one step of the truth, and a step is
			-- several studs. On a long border that is invisible; on a short one it is most
			-- of the border, and two borders that meet at a vertex would each stop short
			-- of it and leave a gap at the exact place a player is looking to see who
			-- borders whom. So each end is walked back out to where it stops being an edge.
			local function refine(inside: number, outside: number): number
				for _ = 1, 20 do
					local mid = (inside + outside) / 2
					if onEdge(mid) then
						inside = mid
					else
						outside = mid
					end
				end
				return inside
			end

			firstT = refine(firstT, firstT - step)
			lastT = refine(lastT, lastT + step)

			local x1, z1 = midX + px * firstT, midZ + pz * firstT
			local x2, z2 = midX + px * lastT, midZ + pz * lastT
			local u1, v1 = WorldMap.Normalize(bounds, x1, z1)
			local u2, v2 = WorldMap.Normalize(bounds, x2, z2)

			-- The angle is taken in normalized space, not in studs. The sheet is square
			-- and the world is not, so a line that runs at 30 degrees through the town
			-- does not run at 30 degrees across the paper -- and drawing it at the world
			-- angle would put both ends in the right place with a visible kink between.
			local du, dv = u2 - u1, v2 - v1
			local span = math.sqrt(du * du + dv * dv)
			if span <= 0 then
				continue
			end

			local edge = Instance.new("Frame")
			edge.Name = `{a.id}|{b.id}`
			edge.AnchorPoint = Vector2.new(0.5, 0.5)
			edge.Position = UDim2.fromScale((u1 + u2) / 2, (v1 + v2) / 2)
			-- Length in scale so it grows with the zoom, thickness in offset so it does
			-- not. A border that thickened as you zoomed in would swallow the ground it
			-- was outlining.
			edge.Size = UDim2.new(span, 0, 0, MAP.RegionBorderPixels)
			edge.Rotation = math.deg(math.atan2(dv, du))
			edge.BackgroundColor3 = PALETTE.Text
			edge.BackgroundTransparency = MAP.RegionBorderTransparency
			edge.BorderSizePixel = 0
			edge.ZIndex = Z_REGION_EDGE
			edge.Parent = self.regionFolder

			corner(edge, 1)
		end
	end

	-- ---- the name plates, one per side, at its boss ----

	for _, region in data.regions do
		local plate = Instance.new("Frame")
		plate.Name = region.id
		plate.AnchorPoint = Vector2.new(0.5, 0.5)
		plate.Position = UDim2.fromScale(region.u, region.v)
		plate.AutomaticSize = Enum.AutomaticSize.XY
		plate.Size = UDim2.fromOffset(0, 0)
		plate.BackgroundColor3 = PALETTE.Panel
		plate.BackgroundTransparency = 0.1
		plate.BorderSizePixel = 0
		plate.ZIndex = Z_ICON + 45
		plate.Parent = self.plateFolder

		corner(plate, 6)
		stroke(plate, region.color, 1, 0.25)

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingBottom = UDim.new(0, 4)
		pad.Parent = plate

		local name = label(plate, FONT_BOLD, 11, region.color, Enum.TextXAlignment.Left)
		name.AutomaticSize = Enum.AutomaticSize.XY
		name.Size = UDim2.fromOffset(0, 0)
		name.TextTruncate = Enum.TextTruncate.None
		name.Text = region.name
		name.ZIndex = Z_ICON + 46
	end

	self.regionsBuilt = true
end

local function buildIcons(self: MapUIHandle, data: MapData)
	for _, child in self.iconFolder:GetChildren() do
		child:Destroy()
	end
	table.clear(self.icons)

	for _, icon in data.icons do
		local style = MapIcons.StyleFor(icon.id)

		local dot = Instance.new("Frame")
		dot.Name = icon.id
		-- Sized in offset inside a Frame that grows with the zoom, so a place is a dot of
		-- the same weight whether the sheet is showing the whole world or one street.
		dot.Size = UDim2.fromOffset(style.size * 2, style.size * 2)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		-- No flip, and that is not an oversight. Roblox -Z is north, so bounds.minZ is the
		-- world's north edge; Normalize divides from minZ, so v=0 is north and screen v=0
		-- is the top. North-up falls out of the two conventions agreeing, and negating
		-- here would silently draw the town upside down.
		dot.Position = UDim2.fromScale(icon.u, icon.v)
		dot.BackgroundColor3 = style.color
		dot.BorderSizePixel = 0
		dot.ZIndex = Z_ICON + style.priority
		dot.Parent = self.iconFolder

		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = dot

		-- A dark ring, so a dot landing on its own gang's wash or on another dot still
		-- reads as one round thing rather than as a smear.
		stroke(dot, PALETTE.PanelDeep, 1.5, 0.25)

		local text: TextLabel? = nil
		if MAP.LabelZoom[style.tier] ~= nil then
			local name = label(self.iconFolder, FONT_MEDIUM, 11, style.color, Enum.TextXAlignment.Left)
			-- Parented to the folder rather than to the dot, because a label inside a dot
			-- would be clipped to a twelve-pixel circle the moment anything set
			-- ClipsDescendants on it, and because the label wants its own ZIndex: names
			-- belong above every dot, not above only the one they name.
			name.AnchorPoint = Vector2.new(0, 0.5)
			name.Position = UDim2.fromScale(icon.u, icon.v)
			name.Size = UDim2.fromOffset(130, 14)
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Text = icon.label
			name.ZIndex = Z_ICON + 30 + style.priority

			-- Pushed clear of the dot in offset, which keeps the gap constant at every
			-- zoom. In scale it would drift away from its own dot as the player zoomed in.
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, style.size + 6)
			pad.Parent = name

			local textStroke = Instance.new("UIStroke")
			-- A name printed straight onto the map is unreadable wherever it crosses a
			-- gang wash or a grid line, which on a sheet this busy is most of them.
			textStroke.Color = PALETTE.PanelDeep
			textStroke.Thickness = 2
			textStroke.Transparency = 0.25
			textStroke.Parent = name

			text = name
		end

		table.insert(self.icons, { dot = dot, labelText = text, tier = style.tier })
	end

	applyDetail(self)
end

-- -------------------------------------------------------------------
-- The chrome. Built once, over the sheet.
-- -------------------------------------------------------------------

-- One swatch and a word, for the legend and for the gang row.
local function chip(parent: Instance, color: Color3, text: string, order: number)
	local row = Instance.new("Frame")
	row.Name = text
	row.AutomaticSize = Enum.AutomaticSize.X
	row.Size = UDim2.fromOffset(0, 16)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.ZIndex = Z_CHROME + 1
	row.Parent = parent

	local swatch = Instance.new("Frame")
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.Position = UDim2.new(0, 0, 0.5, 0)
	swatch.Size = UDim2.fromOffset(8, 8)
	swatch.BackgroundColor3 = color
	swatch.BorderSizePixel = 0
	swatch.ZIndex = Z_CHROME + 2
	swatch.Parent = row

	local swatchCorner = Instance.new("UICorner")
	swatchCorner.CornerRadius = UDim.new(1, 0)
	swatchCorner.Parent = swatch

	local name = label(row, FONT_BODY, 11, PALETTE.Muted, Enum.TextXAlignment.Left)
	name.AutomaticSize = Enum.AutomaticSize.X
	name.Position = UDim2.fromOffset(13, 0)
	name.Size = UDim2.new(0, 0, 1, 0)
	name.TextTruncate = Enum.TextTruncate.None
	name.Text = text
	name.ZIndex = Z_CHROME + 2
end

function MapUI.new(): MapUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesMap"
	screenGui.ResetOnSpawn = false
	-- Not `IgnoreGuiInset`. Setting that while the default `CoreUISafeInsets` is in force
	-- silently flips the whole GUI to device insets anyway, so the honest version is to
	-- ask for what is wanted: the sheet is centred and must not sit under a notch.
	screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	-- Above the HUD and the minimap, below a choice panel. A choice is a decision the game
	-- is waiting on; the map is never that, so it must never cover one.
	screenGui.DisplayOrder = 5
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	-- The backdrop is a button so that clicking anywhere off the sheet closes it, which is
	-- the gesture every player already has. It is also what stops a click meant for the
	-- map reaching a dot in the world behind it.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = PALETTE.Backdrop
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.ZIndex = 0
	backdrop.Parent = screenGui

	local sheet = Instance.new("Frame")
	sheet.Name = "Sheet"
	-- Square, sized off the shorter screen axis so it fits in portrait and landscape
	-- without two layouts. The world is not square and the sheet does not pretend it is:
	-- everything inside is placed in normalized space, so the picture is stretched to fill
	-- and every distance on it is stretched identically.
	sheet.Size = UDim2.new(MAP.SheetScreenFraction, 0, MAP.SheetScreenFraction, 0)
	sheet.SizeConstraint = Enum.SizeConstraint.RelativeYY
	sheet.AnchorPoint = Vector2.new(0.5, 0.5)
	sheet.Position = UDim2.new(0.5, 0, 0.5, 0)
	sheet.BackgroundColor3 = PALETTE.PanelDeep
	sheet.BorderSizePixel = 0
	-- The whole reason the pan works: the world Frame inside is larger than this and hangs
	-- off every edge, and this is what stops it painting over the rest of the screen.
	sheet.ClipsDescendants = true
	sheet.Parent = screenGui

	corner(sheet, 14)
	stroke(sheet, PALETTE.Edge, 1, 0.3)

	local world = Instance.new("Frame")
	world.Name = "World"
	world.AnchorPoint = Vector2.new(0, 0)
	world.Position = UDim2.fromScale(0, 0)
	world.Size = UDim2.fromScale(1, 1)
	world.BackgroundTransparency = 1
	world.ZIndex = Z_LAND
	world.Parent = sheet

	-- The ground itself: one rectangle covering exactly the mapped bounds, a shade up from
	-- the sheet behind it. It is what gives the world an edge -- zoomed out, the border of
	-- this is the coastline of everything there is.
	local land = Instance.new("Frame")
	land.Name = "Land"
	land.Size = UDim2.fromScale(1, 1)
	land.BackgroundColor3 = PALETTE.Panel
	land.BorderSizePixel = 0
	land.ZIndex = Z_LAND
	land.Parent = world

	stroke(land, PALETTE.Edge, 1, 0.55)

	-- The drawn world. Its own folder rather than parts parented to `land`, so that the
	-- nine hundred-odd Frames in it can be thrown away and rebuilt in one line when the
	-- bounds change, without taking the ground rectangle with them.
	local shapeFolder = Instance.new("Frame")
	shapeFolder.Name = "Shapes"
	shapeFolder.Size = UDim2.fromScale(1, 1)
	shapeFolder.BackgroundTransparency = 1
	shapeFolder.ZIndex = Z_SHAPE_GROUND
	shapeFolder.Parent = world

	local gridFolder = Instance.new("Frame")
	gridFolder.Name = "Grid"
	gridFolder.Size = UDim2.fromScale(1, 1)
	gridFolder.BackgroundTransparency = 1
	gridFolder.ZIndex = Z_GRID
	gridFolder.Parent = world

	local regionFolder = Instance.new("Frame")
	regionFolder.Name = "Regions"
	regionFolder.Size = UDim2.fromScale(1, 1)
	regionFolder.BackgroundTransparency = 1
	regionFolder.Visible = false
	regionFolder.ZIndex = Z_REGION_FILL
	regionFolder.Parent = world

	local plateFolder = Instance.new("Frame")
	plateFolder.Name = "Plates"
	plateFolder.Size = UDim2.fromScale(1, 1)
	plateFolder.BackgroundTransparency = 1
	plateFolder.Visible = false
	plateFolder.ZIndex = Z_ICON + 45
	plateFolder.Parent = world

	local iconFolder = Instance.new("Frame")
	iconFolder.Name = "Icons"
	iconFolder.Size = UDim2.fromScale(1, 1)
	iconFolder.BackgroundTransparency = 1
	iconFolder.ZIndex = Z_ICON
	iconFolder.Parent = world

	local youDot = Instance.new("Frame")
	youDot.Name = "You"
	youDot.Size = UDim2.fromOffset(MAP.YouSizePixels + 2, MAP.YouSizePixels + 2)
	youDot.AnchorPoint = Vector2.new(0.5, 0.5)
	youDot.BackgroundColor3 = MAP.YouColor
	youDot.BorderSizePixel = 0
	youDot.ZIndex = Z_YOU
	youDot.Visible = false
	youDot.Parent = world

	local youCorner = Instance.new("UICorner")
	youCorner.CornerRadius = UDim.new(1, 0)
	youCorner.Parent = youDot
	stroke(youDot, PALETTE.PanelDeep, 2, 0)

	-- ---------------------------------------------------------------
	-- The catcher. One invisible button over the whole sheet, above every dot and below
	-- every control, so that the wheel and the drag land in exactly one place. Without it
	-- the topmost Frame under the pointer -- which on a sheet this dense is usually some
	-- dot -- takes the input and the sheet never hears about it.
	-- ---------------------------------------------------------------

	local grab = Instance.new("TextButton")
	grab.Name = "Grab"
	grab.Size = UDim2.new(1, 0, 1, 0)
	grab.BackgroundTransparency = 1
	grab.AutoButtonColor = false
	grab.Text = ""
	grab.ZIndex = Z_GRAB
	grab.Parent = sheet

	-- ---------------------------------------------------------------
	-- The top bar: where you are, and the two controls.
	-- ---------------------------------------------------------------

	local topBar = panel(sheet, "TopBar")
	topBar.Position = UDim2.fromOffset(10, 10)
	topBar.Size = UDim2.new(1, -20, 0, 46)

	local titleLabel = label(topBar, FONT_BOLD, 15, PALETTE.Text, Enum.TextXAlignment.Left)
	titleLabel.Position = UDim2.fromOffset(14, 6)
	titleLabel.Size = UDim2.new(0.5, -14, 0, 18)

	local placeLabel = label(topBar, FONT_BODY, 11, PALETTE.Muted, Enum.TextXAlignment.Left)
	placeLabel.Position = UDim2.fromOffset(14, 24)
	placeLabel.Size = UDim2.new(0.5, -14, 0, 15)

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.Position = UDim2.new(1, -10, 0.5, 0)
	closeButton.Size = UDim2.fromOffset(30, 30)
	closeButton.BackgroundColor3 = PALETTE.Row
	closeButton.BorderSizePixel = 0
	closeButton.AutoButtonColor = false
	closeButton.Text = ""
	closeButton.ZIndex = Z_CHROME + 1
	closeButton.Parent = topBar

	corner(closeButton, 8)

	-- Two rotated bars rather than the letter X, for the same reason the menu rail draws
	-- its icons: a glyph borrowed to stand in for a shape is the tell that nobody drew one.
	for _, angle in { 45, -45 } do
		local mark = bar(closeButton, 13, 2, PALETTE.Muted)
		mark.Rotation = angle
	end

	-- **The one control the brief asked for by name.** Territory used to be painted over
	-- the map whether or not anybody had asked, which made every other thing on the sheet
	-- harder to read in exchange for an answer most opens do not want.
	local territoryButton = Instance.new("TextButton")
	territoryButton.Name = "Territory"
	territoryButton.AnchorPoint = Vector2.new(1, 0.5)
	territoryButton.Position = UDim2.new(1, -48, 0.5, 0)
	territoryButton.Size = UDim2.fromOffset(126, 30)
	territoryButton.BackgroundColor3 = PALETTE.Row
	territoryButton.BorderSizePixel = 0
	territoryButton.AutoButtonColor = false
	territoryButton.FontFace = FONT_MEDIUM
	territoryButton.TextSize = 12
	territoryButton.TextColor3 = PALETTE.Muted
	territoryButton.Text = "Gang territory"
	territoryButton.ZIndex = Z_CHROME + 1
	territoryButton.Parent = topBar

	corner(territoryButton, 8)
	local territoryEdge = stroke(territoryButton, PALETTE.Accent, 1, 1)

	-- ---------------------------------------------------------------
	-- Bottom-left: the legend, the gang row it grows when territory is on, and the scale.
	-- ---------------------------------------------------------------

	local legend = panel(sheet, "Legend")
	legend.AnchorPoint = Vector2.new(0, 1)
	legend.Position = UDim2.new(0, 10, 1, -10)
	legend.AutomaticSize = Enum.AutomaticSize.XY
	legend.Size = UDim2.fromOffset(0, 0)

	local legendPad = Instance.new("UIPadding")
	legendPad.PaddingLeft = UDim.new(0, 12)
	legendPad.PaddingRight = UDim.new(0, 12)
	legendPad.PaddingTop = UDim.new(0, 9)
	legendPad.PaddingBottom = UDim.new(0, 9)
	legendPad.Parent = legend

	local legendLayout = Instance.new("UIListLayout")
	legendLayout.FillDirection = Enum.FillDirection.Vertical
	legendLayout.SortOrder = Enum.SortOrder.LayoutOrder
	legendLayout.Padding = UDim.new(0, 5)
	legendLayout.Parent = legend

	-- The place kinds, laid across rather than down. Five words in a column is a list to
	-- read; five words in a line is a key to glance at.
	local kindRow = Instance.new("Frame")
	kindRow.Name = "Kinds"
	kindRow.AutomaticSize = Enum.AutomaticSize.XY
	kindRow.Size = UDim2.fromOffset(0, 0)
	kindRow.BackgroundTransparency = 1
	kindRow.LayoutOrder = 1
	kindRow.ZIndex = Z_CHROME + 1
	kindRow.Parent = legend

	local kindLayout = Instance.new("UIListLayout")
	kindLayout.FillDirection = Enum.FillDirection.Horizontal
	kindLayout.SortOrder = Enum.SortOrder.LayoutOrder
	kindLayout.Padding = UDim.new(0, 12)
	kindLayout.Parent = kindRow

	chip(kindRow, MAP.YouColor, "You", 1)
	chip(kindRow, MAP.Icons.Kinds.home.color, "Home", 2)
	chip(kindRow, MAP.Icons.Kinds.civic.color, "Civic", 3)
	chip(kindRow, MAP.Icons.Kinds.work.color, "Work", 4)
	chip(kindRow, MAP.Icons.Kinds.leisure.color, "Leisure", 5)

	-- The four sides, named. Hidden with the overlay, because a key to something that is
	-- not on the picture is furniture.
	local gangRow = Instance.new("Frame")
	gangRow.Name = "Gangs"
	gangRow.AutomaticSize = Enum.AutomaticSize.XY
	gangRow.Size = UDim2.fromOffset(0, 0)
	gangRow.BackgroundTransparency = 1
	gangRow.LayoutOrder = 2
	gangRow.Visible = false
	gangRow.ZIndex = Z_CHROME + 1
	gangRow.Parent = legend

	local gangLayout = Instance.new("UIListLayout")
	gangLayout.FillDirection = Enum.FillDirection.Horizontal
	gangLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gangLayout.Padding = UDim.new(0, 12)
	gangLayout.Parent = gangRow

	local scaleHolder = Instance.new("Frame")
	scaleHolder.Name = "Scale"
	scaleHolder.AutomaticSize = Enum.AutomaticSize.X
	scaleHolder.Size = UDim2.fromOffset(0, 20)
	scaleHolder.BackgroundTransparency = 1
	scaleHolder.LayoutOrder = 3
	scaleHolder.ZIndex = Z_CHROME + 1
	scaleHolder.Parent = legend

	local scaleBar = Instance.new("Frame")
	scaleBar.Name = "Bar"
	scaleBar.AnchorPoint = Vector2.new(0, 0.5)
	scaleBar.Position = UDim2.new(0, 0, 0.5, 0)
	scaleBar.Size = UDim2.fromOffset(80, 3)
	scaleBar.BackgroundColor3 = PALETTE.Muted
	scaleBar.BorderSizePixel = 0
	scaleBar.ZIndex = Z_CHROME + 2
	scaleBar.Parent = scaleHolder

	corner(scaleBar, 2)

	local scaleLabel = label(scaleHolder, FONT_BODY, 10, PALETTE.Muted, Enum.TextXAlignment.Left)
	scaleLabel.AnchorPoint = Vector2.new(0, 0.5)
	scaleLabel.Position = UDim2.new(0, 0, 0.5, 0)
	scaleLabel.Size = UDim2.new(0, 0, 1, 0)
	scaleLabel.AutomaticSize = Enum.AutomaticSize.X
	scaleLabel.TextTruncate = Enum.TextTruncate.None
	scaleLabel.ZIndex = Z_CHROME + 2


	-- ---------------------------------------------------------------
	-- Bottom-right: the zoom cluster.
	-- ---------------------------------------------------------------

	local zoomCluster = Instance.new("Frame")
	zoomCluster.Name = "Zoom"
	zoomCluster.AnchorPoint = Vector2.new(1, 1)
	zoomCluster.Position = UDim2.new(1, -10, 1, -10)
	zoomCluster.AutomaticSize = Enum.AutomaticSize.Y
	zoomCluster.Size = UDim2.fromOffset(30, 0)
	zoomCluster.BackgroundTransparency = 1
	zoomCluster.ZIndex = Z_CHROME
	zoomCluster.Parent = sheet

	local zoomLayout = Instance.new("UIListLayout")
	zoomLayout.FillDirection = Enum.FillDirection.Vertical
	zoomLayout.SortOrder = Enum.SortOrder.LayoutOrder
	zoomLayout.Padding = UDim.new(0, 6)
	zoomLayout.Parent = zoomCluster

	local zoomIn = iconButton(zoomCluster, "In", 1)
	bar(zoomIn, 12, 2, PALETTE.Text)
	bar(zoomIn, 2, 12, PALETTE.Text)

	local zoomOut = iconButton(zoomCluster, "Out", 2)
	bar(zoomOut, 12, 2, PALETTE.Text)

	-- The crosshair: back to me, at whatever zoom I am at. The way out of having dragged
	-- across the world and lost track of where you were standing.
	local homeButton = iconButton(zoomCluster, "Recentre", 3)
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(12, 12)
	ring.BackgroundTransparency = 1
	ring.ZIndex = Z_CHROME + 2
	ring.Parent = homeButton
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	stroke(ring, MAP.YouColor, 2, 0)
	bar(homeButton, 4, 4, MAP.YouColor)

	-- ---------------------------------------------------------------

	local self: MapUIHandle = setmetatable({
		screenGui = screenGui,
		backdrop = backdrop,
		sheet = sheet,
		world = world,
		gridFolder = gridFolder,
		regionFolder = regionFolder,
		plateFolder = plateFolder,
		shapeFolder = shapeFolder,
		iconFolder = iconFolder,
		youDot = youDot,
		titleLabel = titleLabel,
		placeLabel = placeLabel,
		gangRow = gangRow,
		territoryButton = territoryButton,
		scaleBar = scaleBar,
		scaleLabel = scaleLabel,
		data = nil,
		territory = nil,
		icons = {},
		showRegions = false,
		regionsBuilt = false,
		zoom = 1,
		focusU = 0.5,
		focusV = 0.5,
		viewTween = nil,
		dragFrom = nil,
		open = false,
	}, MapUI)

	-- ---- the controls ----

	backdrop.Activated:Connect(function()
		MapUI.Close(self)
	end)
	closeButton.Activated:Connect(function()
		MapUI.Close(self)
	end)

	local function paintTerritory()
		self.regionFolder.Visible = self.showRegions
		self.plateFolder.Visible = self.showRegions
		self.gangRow.Visible = self.showRegions
		TweenService
			:Create(territoryButton, HOVER, {
				BackgroundColor3 = if self.showRegions then PALETTE.Accent else PALETTE.Row,
				TextColor3 = if self.showRegions then PALETTE.Ink else PALETTE.Muted,
			})
			:Play()
		TweenService:Create(territoryEdge, HOVER, { Transparency = if self.showRegions then 0 else 1 }):Play()
	end

	territoryButton.Activated:Connect(function()
		self.showRegions = not self.showRegions
		paintTerritory()
	end)
	territoryButton.MouseEnter:Connect(function()
		if not self.showRegions then
			TweenService:Create(territoryButton, HOVER, { BackgroundColor3 = PALETTE.RowHover }):Play()
		end
	end)
	territoryButton.MouseLeave:Connect(paintTerritory)

	zoomIn.Activated:Connect(function()
		zoomAbout(self, 1, 0.5, 0.5)
	end)
	zoomOut.Activated:Connect(function()
		zoomAbout(self, -1, 0.5, 0.5)
	end)
	homeButton.Activated:Connect(function()
		recentre(self, true)
	end)

	-- ---- the wheel and the drag ----

	-- Both hang off `grab` rather than off the sheet, and both convert the pointer into
	-- sheet-relative 0..1 from the sheet's own absolute rectangle rather than from
	-- `GetMouseLocation`. The two disagree by the height of the topbar inset on some
	-- setups, and a zoom anchored a few dozen pixels from the cursor is the kind of wrong
	-- that reads as jitter rather than as a bug.
	local function sheetPointOf(position: Vector3): (number, number)
		local origin = sheet.AbsolutePosition
		local size = sheet.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return 0.5, 0.5
		end
		return (position.X - origin.X) / size.X, (position.Y - origin.Y) / size.Y
	end

	grab.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		local u, v = sheetPointOf(input.Position)
		zoomAbout(self, input.Position.Z, u, v)
	end)

	grab.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			self.dragFrom = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)

	-- Movement and release are watched globally rather than on `grab`, so that a drag which
	-- runs off the edge of the sheet keeps panning instead of stopping dead at the border
	-- -- which is exactly the drag a player does when they want to see what is over there.
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local from = self.dragFrom
		if from == nil or not self.open then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		local now = Vector2.new(input.Position.X, input.Position.Y)
		local moved = now - from
		self.dragFrom = now

		local size = self.sheet.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		-- Divided by the zoom as well as by the sheet, because a drag moves the *picture*
		-- by a number of pixels and the focus is measured in worlds. Zoomed in five times,
		-- the same hand movement should cover a fifth of the ground.
		self.focusU -= (moved.X / size.X) / self.zoom
		self.focusV -= (moved.Y / size.Y) / self.zoom
		refreshView(self, false)
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			self.dragFrom = nil
		end
	end)

	RunService.Heartbeat:Connect(function()
		if self.open then
			MapUI.RedrawYou(self)
		end
	end)

	paintTerritory()
	return self
end

-- -------------------------------------------------------------------
-- The pushes.
-- -------------------------------------------------------------------

function MapUI.SetMapData(self: MapUIHandle, data: MapData)
	self.data = data
	buildShapes(self, data)
	buildGrid(self, data)
	buildRegions(self, data)
	buildIcons(self, data)

	-- The gang key, rebuilt with the data so a renamed gang renames itself here.
	for _, child in self.gangRow:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for order, region in data.regions do
		chip(self.gangRow, region.color, region.name, order)
	end

	applyScale(self)
end

function MapUI.SetTerritory(self: MapUIHandle, state: TerritoryState?)
	self.territory = state
end

function MapUI.RedrawYou(self: MapUIHandle)
	local data = self.data
	if data == nil then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil then
		self.youDot.Visible = false
		return
	end

	local here = (root :: BasePart).Position
	local u, v = WorldMap.Normalize(
		{ minX = data.minX, maxX = data.maxX, minZ = data.minZ, maxZ = data.maxZ },
		here.X,
		here.Z
	)
	self.youDot.Visible = true
	self.youDot.Position = UDim2.fromScale(math.clamp(u, 0, 1), math.clamp(v, 0, 1))

	local territory = self.territory
	if territory ~= nil and territory.regionId ~= nil then
		local name = MapIcons.RegionName(data, territory.regionId :: string)
		self.titleLabel.Text = `{name}'s side`
		if territory.onIncursion then
			self.placeLabel.Text = `{territory.deepestStuds} studs in — you are a long way from your own`
			self.placeLabel.TextColor3 = MAP.YouColor
		else
			self.placeLabel.Text = "Drag to look around · scroll to zoom"
			self.placeLabel.TextColor3 = PALETTE.Muted
		end
	else
		self.titleLabel.Text = "The city"
		self.placeLabel.Text = "Drag to look around · scroll to zoom"
		self.placeLabel.TextColor3 = PALETTE.Muted
	end
end

function MapUI.Open(self: MapUIHandle)
	if self.data == nil then
		return
	end
	self.open = true
	self.screenGui.Enabled = true

	-- Opened on the player, at the zoom they left it at. Which zoom is worth remembering
	-- and which position is not: a player who was studying one street will want that
	-- magnification again, but almost never that exact patch of ground -- they have walked
	-- since, and the reason to open a map is nearly always to ask where you are now.
	recentre(self, false)
	MapUI.RedrawYou(self)

	self.sheet.Size = UDim2.new(MAP.SheetScreenFraction * 0.97, 0, MAP.SheetScreenFraction * 0.97, 0)
	self.backdrop.BackgroundTransparency = 1
	TweenService
		:Create(self.sheet, ENTER, {
			Size = UDim2.new(MAP.SheetScreenFraction, 0, MAP.SheetScreenFraction, 0),
		})
		:Play()
	TweenService:Create(self.backdrop, ENTER, { BackgroundTransparency = PALETTE.BackdropTransparency }):Play()
end

function MapUI.Close(self: MapUIHandle)
	if not self.open then
		return
	end
	self.open = false
	-- A drag that was in progress when the sheet closed would otherwise still be live the
	-- next time it opened, and the first mouse movement would jerk the map sideways.
	self.dragFrom = nil

	TweenService:Create(self.backdrop, EXIT, { BackgroundTransparency = 1 }):Play()

	-- Hidden after the fade rather than with it, and re-checked when the timer comes back,
	-- so that closing and immediately reopening does not blank the sheet mid-entrance.
	task.delay(MOTION.ExitSeconds, function()
		if self.open then
			return
		end
		self.screenGui.Enabled = false
	end)
end

function MapUI.Toggle(self: MapUIHandle)
	if self.open then
		MapUI.Close(self)
	else
		MapUI.Open(self)
	end
end

function MapUI.IsOpen(self: MapUIHandle): boolean
	return self.open
end

return MapUI
