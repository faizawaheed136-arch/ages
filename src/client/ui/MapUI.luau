--!strict
-- The full map: the whole world on one sheet, with the four gang sides washed over it.
--
-- Opened from the minimap or with M, and it is a sheet rather than a fullscreen takeover
-- -- the game keeps running behind it, dimmed. A life simulator where opening the map
-- pauses the world would be teaching the player that the map is a menu, and it is not:
-- it is a thing you look at while deciding where to walk.
--
-- **The region wash is sampled, not traced.** A side is "the ground nearer this boss
-- than any other", which is a Voronoi cell -- it has no outline to draw without solving
-- for one. Sampling a grid and colouring each cell by its owner gets the same picture
-- for a fraction of the work, and it stays correct if a fifth gang is ever added, which
-- a hand-traced polygon would not.
--
-- **Sampling happens in world coordinates, never in the normalized 0..1 the icons use.**
-- The world is about 1200 studs by 1650 and the sheet is square, so the two axes are
-- scaled by different factors -- "nearest boss" measured on the squashed sheet would
-- put the boundaries in visibly the wrong place. Every cell centre is therefore mapped
-- back out to studs before WorldMap is asked who owns it. This is the one thing in this
-- file that would be silently, plausibly wrong if done the easy way.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local WorldMap = require(ReplicatedStorage:WaitForChild("WorldMap"))
local MapIcons = require(script.Parent.MapIcons)

type MapData = Types.MapData
type TerritoryState = Types.TerritoryState

local MAP = Config.Map

local BACKDROP_COLOR = Color3.fromRGB(6, 7, 10)
local SHEET_COLOR = Color3.fromRGB(14, 16, 21)
local PANEL_COLOR = Color3.fromRGB(20, 22, 28)
local TEXT_COLOR = Color3.fromRGB(228, 232, 242)
local MUTED_COLOR = Color3.fromRGB(150, 156, 172)
local RING_COLOR = Color3.fromRGB(72, 78, 94)

-- Only the places worth naming get a name printed beside them. Everything else is a
-- dot with a colour, because this world has hundreds of place points and a sheet with
-- hundreds of labels on it is a sheet nobody can read. The threshold is a priority
-- rather than a kind list so Config stays the only place that decides what matters.
local LABEL_PRIORITY_FLOOR = 30

local MapUI = {}
MapUI.__index = MapUI

export type MapUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		backdrop: TextButton,
		sheet: Frame,
		washFolder: Frame,
		iconFolder: Frame,
		youDot: Frame,
		titleLabel: TextLabel,
		legendList: Frame,
		toggleButton: TextButton,
		data: MapData?,
		territory: TerritoryState?,
		showRegions: boolean,
		washBuilt: boolean,
		open: boolean,
	},
	MapUI
))

local function corner(instance: Instance, radius: number)
	local rounded = Instance.new("UICorner")
	rounded.CornerRadius = UDim.new(0, radius)
	rounded.Parent = instance
end

function MapUI.new(): MapUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesMap"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	-- Above the HUD and the minimap, below a choice panel. A choice is a decision the
	-- game is waiting on; the map is never that, so it must never cover one.
	screenGui.DisplayOrder = 5
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	-- The backdrop is a button so that clicking anywhere off the sheet closes it, which
	-- is the gesture every player already has. It is also what stops a click meant for
	-- the map reaching a dot in the world behind it.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = BACKDROP_COLOR
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = screenGui

	local sheet = Instance.new("Frame")
	sheet.Name = "Sheet"
	-- Square, sized off the shorter screen axis so it fits in portrait and landscape
	-- without two layouts. The world is not square and the sheet does not pretend it is
	-- -- the wash and the icons are both placed in normalized space, so the picture is
	-- simply stretched to fill, and every distance on it is stretched identically.
	sheet.Size = UDim2.new(MAP.SheetScreenFraction, 0, MAP.SheetScreenFraction, 0)
	sheet.SizeConstraint = Enum.SizeConstraint.RelativeYY
	sheet.AnchorPoint = Vector2.new(0.5, 0.5)
	sheet.Position = UDim2.new(0.5, 0, 0.5, 0)
	sheet.BackgroundColor3 = SHEET_COLOR
	sheet.BorderSizePixel = 0
	sheet.ClipsDescendants = true
	sheet.Parent = screenGui
	corner(sheet, 10)

	local sheetRing = Instance.new("UIStroke")
	sheetRing.Color = RING_COLOR
	sheetRing.Thickness = 1
	sheetRing.Parent = sheet

	local washFolder = Instance.new("Frame")
	washFolder.Name = "Regions"
	washFolder.Size = UDim2.new(1, 0, 1, 0)
	washFolder.BackgroundTransparency = 1
	washFolder.ZIndex = 1
	washFolder.Parent = sheet

	local iconFolder = Instance.new("Frame")
	iconFolder.Name = "Icons"
	iconFolder.Size = UDim2.new(1, 0, 1, 0)
	iconFolder.BackgroundTransparency = 1
	iconFolder.ZIndex = 10
	iconFolder.Parent = sheet

	local youDot = Instance.new("Frame")
	youDot.Name = "You"
	youDot.Size = UDim2.new(0, MAP.YouSizePixels + 2, 0, MAP.YouSizePixels + 2)
	youDot.AnchorPoint = Vector2.new(0.5, 0.5)
	youDot.BackgroundColor3 = MAP.YouColor
	youDot.BorderSizePixel = 0
	youDot.ZIndex = 60
	youDot.Visible = false
	youDot.Parent = sheet
	local youCorner = Instance.new("UICorner")
	youCorner.CornerRadius = UDim.new(1, 0)
	youCorner.Parent = youDot
	local youRing = Instance.new("UIStroke")
	youRing.Color = Color3.fromRGB(10, 34, 18)
	youRing.Thickness = 2
	youRing.Parent = youDot

	-- Title sits above the sheet rather than on it, so it never covers the north edge of
	-- the world.
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 22)
	titleLabel.AnchorPoint = Vector2.new(0.5, 1)
	titleLabel.Position = UDim2.new(0.5, 0, 0, -8)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 15
	titleLabel.TextColor3 = TEXT_COLOR
	titleLabel.Text = ""
	titleLabel.Parent = sheet

	-- The side panel: legend, and the one control on this screen.
	local side = Instance.new("Frame")
	side.Name = "Side"
	side.Size = UDim2.new(0, 168, 0, 0)
	side.AutomaticSize = Enum.AutomaticSize.Y
	side.AnchorPoint = Vector2.new(0, 0.5)
	side.Position = UDim2.new(1, 14, 0.5, 0)
	side.BackgroundColor3 = PANEL_COLOR
	side.BackgroundTransparency = 0.08
	side.BorderSizePixel = 0
	side.Parent = sheet
	corner(side, 8)

	local sidePad = Instance.new("UIPadding")
	sidePad.PaddingTop = UDim.new(0, 10)
	sidePad.PaddingBottom = UDim.new(0, 10)
	sidePad.PaddingLeft = UDim.new(0, 10)
	sidePad.PaddingRight = UDim.new(0, 10)
	sidePad.Parent = side

	local sideLayout = Instance.new("UIListLayout")
	sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sideLayout.Padding = UDim.new(0, 6)
	sideLayout.Parent = side

	local legendTitle = Instance.new("TextLabel")
	legendTitle.Name = "LegendTitle"
	legendTitle.Size = UDim2.new(1, 0, 0, 16)
	legendTitle.BackgroundTransparency = 1
	legendTitle.Font = Enum.Font.GothamBold
	legendTitle.TextSize = 12
	legendTitle.TextXAlignment = Enum.TextXAlignment.Left
	legendTitle.TextColor3 = TEXT_COLOR
	legendTitle.Text = "Legend"
	legendTitle.LayoutOrder = 1
	legendTitle.Parent = side

	local legendList = Instance.new("Frame")
	legendList.Name = "Legend"
	legendList.Size = UDim2.new(1, 0, 0, 0)
	legendList.AutomaticSize = Enum.AutomaticSize.Y
	legendList.BackgroundTransparency = 1
	legendList.LayoutOrder = 2
	legendList.Parent = side

	local legendLayout = Instance.new("UIListLayout")
	legendLayout.SortOrder = Enum.SortOrder.LayoutOrder
	legendLayout.Padding = UDim.new(0, 4)
	legendLayout.Parent = legendList

	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "ToggleRegions"
	toggleButton.Size = UDim2.new(1, 0, 0, 30)
	toggleButton.BackgroundColor3 = Color3.fromRGB(34, 37, 46)
	toggleButton.BorderSizePixel = 0
	toggleButton.Font = Enum.Font.GothamMedium
	toggleButton.TextSize = 12
	toggleButton.TextColor3 = TEXT_COLOR
	toggleButton.Text = "Gang Regions"
	toggleButton.LayoutOrder = 3
	toggleButton.Parent = side
	corner(toggleButton, 6)

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.Size = UDim2.new(1, 0, 0, 26)
	closeButton.BackgroundColor3 = Color3.fromRGB(28, 30, 38)
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.Gotham
	closeButton.TextSize = 11
	closeButton.TextColor3 = MUTED_COLOR
	closeButton.Text = "Close  (M)"
	closeButton.LayoutOrder = 4
	closeButton.Parent = side
	corner(closeButton, 6)

	local self: MapUIHandle = setmetatable({
		screenGui = screenGui,
		backdrop = backdrop,
		sheet = sheet,
		washFolder = washFolder,
		iconFolder = iconFolder,
		youDot = youDot,
		titleLabel = titleLabel,
		legendList = legendList,
		toggleButton = toggleButton,
		data = nil,
		territory = nil,
		showRegions = true,
		washBuilt = false,
		open = false,
	}, MapUI)

	backdrop.Activated:Connect(function()
		MapUI.Close(self)
	end)
	closeButton.Activated:Connect(function()
		MapUI.Close(self)
	end)
	toggleButton.Activated:Connect(function()
		self.showRegions = not self.showRegions
		self.washFolder.Visible = self.showRegions
		toggleButton.BackgroundColor3 = if self.showRegions
			then Color3.fromRGB(34, 37, 46)
			else Color3.fromRGB(24, 26, 32)
		toggleButton.TextColor3 = if self.showRegions then TEXT_COLOR else MUTED_COLOR
	end)

	RunService.Heartbeat:Connect(function()
		if self.open then
			MapUI.RedrawYou(self)
		end
	end)

	return self
end

-- One frame per sampled cell, coloured by whoever owns that patch of ground. Built once
-- and never rebuilt: the bosses do not move while the server is up, so this picture is
-- constant, and rebuilding it on every open would be two thousand instances a keypress.
local function buildWash(self: MapUIHandle, data: MapData)
	if self.washBuilt then
		return
	end

	local sites: { WorldMap.Site } = {}
	for _, region in data.regions do
		local x, z = WorldMap.Denormalize(
			{ minX = data.minX, maxX = data.maxX, minZ = data.minZ, maxZ = data.maxZ },
			region.u,
			region.v
		)
		table.insert(sites, { id = region.id, x = x, z = z })
	end
	if #sites == 0 then
		return
	end

	local cells = MAP.RegionSampleCells
	local step = 1 / cells

	for row = 0, cells - 1 do
		for column = 0, cells - 1 do
			-- The cell's centre, in normalized space, then back out to studs. Going back
			-- out is the whole point: the sheet is square and the world is not, so
			-- "nearest boss" is only the right answer when asked in studs.
			local u = (column + 0.5) * step
			local v = (row + 0.5) * step
			local worldX, worldZ = WorldMap.Denormalize(
				{ minX = data.minX, maxX = data.maxX, minZ = data.minZ, maxZ = data.maxZ },
				u,
				v
			)
			local owner = WorldMap.StandingAt(sites, worldX, worldZ).id
			if owner == nil then
				continue
			end
			local color = MapIcons.RegionColor(data, owner)
			if color == nil then
				continue
			end

			local cell = Instance.new("Frame")
			cell.Name = owner
			-- Half a percent of overlap. Adjacent cells sized exactly 1/cells leave a
			-- hairline of backdrop between them at some resolutions, which reads as a
			-- grid drawn on the map rather than as a solid wash.
			cell.Size = UDim2.new(step * 1.02, 0, step * 1.02, 0)
			cell.Position = UDim2.new(column * step, 0, row * step, 0)
			cell.BackgroundColor3 = color
			cell.BackgroundTransparency = MAP.RegionTransparency
			cell.BorderSizePixel = 0
			cell.ZIndex = 1
			cell.Parent = self.washFolder
		end
	end

	self.washBuilt = true
end

local function buildIcons(self: MapUIHandle, data: MapData)
	for _, child in self.iconFolder:GetChildren() do
		child:Destroy()
	end

	for _, icon in data.icons do
		local style = MapIcons.StyleFor(icon.id)

		local dot = Instance.new("Frame")
		dot.Name = icon.id
		dot.Size = UDim2.new(0, style.size, 0, style.size)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		-- No flip, and that is not an oversight. Roblox -Z is north, so bounds.minZ is the
		-- world's north edge; Normalize divides from minZ, so v=0 is north and screen v=0
		-- is the top. North-up falls out of the two conventions agreeing, and negating
		-- here would silently draw the town upside down.
		dot.Position = UDim2.new(icon.u, 0, icon.v, 0)
		dot.BackgroundColor3 = style.color
		dot.BorderSizePixel = 0
		dot.ZIndex = 10 + style.priority
		dot.Parent = self.iconFolder

		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = dot

		if style.priority >= LABEL_PRIORITY_FLOOR then
			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.Size = UDim2.new(0, 120, 0, 12)
			label.AnchorPoint = Vector2.new(0, 0.5)
			label.Position = UDim2.new(0, style.size, 0.5, 0)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamMedium
			label.TextSize = 10
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = style.color
			label.Text = icon.label
			label.ZIndex = 10 + style.priority
			label.Parent = dot
		end
	end
end

local function buildLegend(self: MapUIHandle, data: MapData)
	for _, child in self.legendList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local order = 0
	local function row(color: Color3, text: string)
		order += 1
		local line = Instance.new("Frame")
		line.Name = text
		line.Size = UDim2.new(1, 0, 0, 14)
		line.BackgroundTransparency = 1
		line.LayoutOrder = order
		line.Parent = self.legendList

		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.new(0, 8, 0, 8)
		swatch.AnchorPoint = Vector2.new(0, 0.5)
		swatch.Position = UDim2.new(0, 0, 0.5, 0)
		swatch.BackgroundColor3 = color
		swatch.BorderSizePixel = 0
		swatch.Parent = line
		local swatchCorner = Instance.new("UICorner")
		swatchCorner.CornerRadius = UDim.new(1, 0)
		swatchCorner.Parent = swatch

		local text_ = Instance.new("TextLabel")
		text_.Size = UDim2.new(1, -16, 1, 0)
		text_.Position = UDim2.new(0, 16, 0, 0)
		text_.BackgroundTransparency = 1
		text_.Font = Enum.Font.Gotham
		text_.TextSize = 10
		text_.TextXAlignment = Enum.TextXAlignment.Left
		text_.TextColor3 = MUTED_COLOR
		text_.Text = text
		text_.Parent = line
	end

	row(Config.Map.YouColor, "You")
	row(Config.Map.Icons.Kinds.home.color, "Home")
	row(Config.Map.Icons.Kinds.civic.color, "Civic")
	row(Config.Map.Icons.Kinds.work.color, "Work")
	row(Config.Map.Icons.Kinds.leisure.color, "Leisure")

	-- The four sides, named. This is the half of the legend that changes with content --
	-- read off the pushed data so a renamed gang renames itself here.
	for _, region in data.regions do
		row(region.color, region.name)
	end
end

function MapUI.SetMapData(self: MapUIHandle, data: MapData)
	self.data = data
	buildWash(self, data)
	buildIcons(self, data)
	buildLegend(self, data)
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
	self.youDot.Position = UDim2.new(math.clamp(u, 0, 1), 0, math.clamp(v, 0, 1), 0)

	local territory = self.territory
	if territory ~= nil and territory.regionId ~= nil then
		local name = MapIcons.RegionName(data, territory.regionId :: string)
		if territory.onIncursion then
			self.titleLabel.Text = `{name}'s side  —  {territory.deepestStuds} studs in`
			self.titleLabel.TextColor3 = MAP.YouColor
		else
			self.titleLabel.Text = `{name}'s side`
			self.titleLabel.TextColor3 = TEXT_COLOR
		end
	else
		self.titleLabel.Text = "The city"
		self.titleLabel.TextColor3 = TEXT_COLOR
	end
end

function MapUI.Open(self: MapUIHandle)
	if self.data == nil then
		return
	end
	self.open = true
	self.screenGui.Enabled = true
	MapUI.RedrawYou(self)
end

function MapUI.Close(self: MapUIHandle)
	self.open = false
	self.screenGui.Enabled = false
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
