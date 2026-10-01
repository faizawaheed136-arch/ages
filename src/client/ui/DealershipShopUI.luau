--!strict
--[[
	The dealership shop: what opens when a player steps into the BUY CARS! circle.

	Two views, the way the big driving games lay a car shop out:
	  * THE LIST -- a Cars / Brands tab pair across the top; down the left the shop's name, the
	    filters (New, All, Owned, Favourites) and a sort; across the top of the grid a search box,
	    the player's money and Exit; then a grid of cards, each a portrait of the car in the look it
	    wears, its year and name, its price (or OWNED), a heart, and NEW on what just arrived.
	  * THE CAR -- the camera sweeps onto the stage (world/ShopStage), the car on a turntable and two
	    more on plinths behind. Its name across the top with the heart; BUY and TEST DRIVE under it,
	    or DRIVE and CUSTOMIZE once it is yours; Back to Vehicles in the corner; the stats down the
	    right; and along the bottom the look -- Paint, Rims, Underglow -- every pick shown on the
	    turntable at once. A car is bought in the look on the turntable; an owned one's new look is
	    kept with SAVE LOOK.
	The layout is the genre's; the names, colours and letters are this dealership's own.

	A view and nothing else: it holds no money and moves no car. Everything it asks for goes out
	through the callbacks (world/DealershipShop wires them to the server), and everything it shows
	comes in through Set*: the catalog, what is owned and how it looks, the balance, a notice.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CarBody = require(ReplicatedStorage:WaitForChild("CarBody"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type VehicleKind = Types.VehicleKind
type Paint = CarBody.Paint

-- A car's look as keys: into CarBody.Paints, CarBody.Rims and CarBody.Glows. Nil for as it came.
export type LookKeys = { paint: string?, rims: string?, glow: string? }
-- Every owned car's look, as the server keeps them.
export type Looks = { paint: { [string]: string }?, rims: { [string]: string }?, glow: { [string]: string }? }

-- The palette. Dark glass panels, one blue for everything selectable, green to buy, red to leave.
local PANEL = Color3.fromRGB(24, 28, 38)
local CARD = Color3.fromRGB(34, 39, 52)
local CARD_HOVER = Color3.fromRGB(44, 51, 68)
local STROKE = Color3.fromRGB(58, 66, 86)
local BLUE = Color3.fromRGB(46, 128, 238)
local BLUE_DARK = Color3.fromRGB(30, 88, 170)
local GREEN = Color3.fromRGB(44, 182, 94)
local RED = Color3.fromRGB(222, 56, 70)
local GOLD = Color3.fromRGB(255, 202, 58)
local WHITE = Color3.fromRGB(244, 246, 250)
local GREY = Color3.fromRGB(150, 158, 176)
local DIM = Color3.fromRGB(96, 104, 122)
local HEART = Color3.fromRGB(240, 70, 92)
local PURPLE = Color3.fromRGB(150, 80, 240)

-- Drawn at this size and scaled to the screen, so a phone and a monitor see the same layout.
local REFERENCE_HEIGHT = 720
local CARD_W, CARD_H = 180, 152

-- Brand wordmark colours: each maker's letters in its own colour, as a badge would be.
local BRAND_COLORS: { [string]: Color3 } = {
	Fairline = Color3.fromRGB(120, 180, 255),
	Elmhurst = Color3.fromRGB(140, 214, 150),
	Castellan = Color3.fromRGB(255, 196, 90),
	Solari = Color3.fromRGB(255, 96, 96),
}

local SORTS = {
	{ key = "priceUp", label = "Price - Low to High" },
	{ key = "priceDown", label = "Price - High to Low" },
	{ key = "speed", label = "Top Speed" },
	{ key = "accel", label = "Acceleration" },
	{ key = "year", label = "Newest" },
	{ key = "name", label = "Name A-Z" },
}

local FILTERS = {
	{ key = "new", label = "New Vehicles", icon = "🆕" },
	{ key = "all", label = "All Vehicles", icon = "🚘" },
	{ key = "owned", label = "Owned Vehicles", icon = "🔑" },
	{ key = "favorites", label = "Favorite Vehicles", icon = "♥" },
}

-- The look bar's three tabs, and the swatches under each.
local PARTS = {
	{ key = "paint", label = "Paint", list = CarBody.Paints, none = "Factory colour" },
	{ key = "rims", label = "Rims", list = CarBody.Rims, none = "Factory rims" },
	{ key = "glow", label = "Underglow", list = CarBody.Glows, none = "No underglow" },
}

local DealershipShopUI = {}
DealershipShopUI.__index = DealershipShopUI

type Card = { frame: Frame, heart: TextButton, price: TextLabel, kind: VehicleKind, grow: UIScale }

export type Handle = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		scale: UIScale,
		refit: RBXScriptConnection?,
		stage: any,
		title: string,
		-- The list.
		list: CanvasGroup,
		tabs: { [string]: TextButton },
		filterButtons: { [string]: TextButton },
		brandBanner: TextLabel,
		brandClear: TextButton,
		sortButton: TextButton,
		sortMenu: Frame,
		search: TextBox,
		count: TextLabel,
		grid: ScrollingFrame,
		brandGrid: ScrollingFrame,
		empty: TextLabel,
		cards: { Card },
		-- The car.
		detail: CanvasGroup,
		nameLabel: TextLabel,
		detailHeart: TextButton,
		buyButton: TextButton,
		testButton: TextButton,
		driveButton: TextButton,
		styleButton: TextButton,
		statRows: { [string]: { bar: Frame, value: TextLabel } },
		statNotes: TextLabel,
		priceLabel: TextLabel,
		ownedLabel: TextLabel,
		partTabs: { [string]: TextButton },
		partRows: { [string]: Frame },
		swatches: { [string]: { [string]: TextButton } },
		lookName: TextLabel,
		banner: TextLabel,
		-- Shared.
		moneyLabels: { TextLabel },
		notice: TextLabel,
		-- State.
		open: boolean,
		catalog: { VehicleKind },
		owned: { [string]: boolean },
		looks: Looks,
		active: string?,
		money: number,
		favorites: { [string]: boolean },
		tab: string,
		filter: string,
		brand: string?,
		sort: string,
		query: string,
		viewing: VehicleKind?,
		part: string,
		chosen: LookKeys,
		noticeToken: number,
		onBuy: ((string, LookKeys) -> ())?,
		onTestDrive: ((string, string?) -> ())?,
		onDrive: ((string) -> ())?,
		onCustomize: ((string, LookKeys) -> ())?,
		onClose: (() -> ())?,
	},
	DealershipShopUI
))

-- ---------------------------------------------------------------------------------------------
-- Little builders.
-- ---------------------------------------------------------------------------------------------

local function money(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return "$" .. out
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function frame(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3, transparency: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

-- A whole view, fadeable as one.
local function group(parent: Instance, name: string): CanvasGroup
	local g = Instance.new("CanvasGroup")
	g.Name = name
	g.Size = UDim2.fromScale(1, 1)
	g.BackgroundTransparency = 1
	g.BorderSizePixel = 0
	g.Parent = parent
	return g
end

local function text(parent: Instance, name: string, position: UDim2, size: UDim2, value: string, color: Color3, textSize: number, font: Enum.Font, align: Enum.TextXAlignment?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Position = position
	t.Size = size
	t.BackgroundTransparency = 1
	t.Text = value
	t.TextColor3 = color
	t.TextSize = textSize
	t.Font = font
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = parent
	return t
end

local function button(parent: Instance, name: string, position: UDim2, size: UDim2, label: string, color: Color3, textSize: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Position = position
	b.Size = size
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Text = label
	b.TextColor3 = WHITE
	b.TextSize = textSize
	b.Font = Enum.Font.GothamBold
	b.Parent = parent
	corner(b, 8)
	return b
end

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal):Play()
end

local function displayName(kind: VehicleKind): string
	if kind.year then
		return `{kind.year} {kind.name}`
	end
	return kind.name
end

-- A 1-10 rating across a stat's safe range: what a bar shows.
local function rating(value: number, low: number, high: number): number
	return math.clamp(1 + 9 * (value - low) / (high - low), 1, 10)
end

local function sameLook(a: LookKeys, b: LookKeys): boolean
	return a.paint == b.paint and a.rims == b.rims and a.glow == b.glow
end

-- The car in a card: its own portrait, drawn by the same CarBody the stage and the road use.
local function portrait(parent: Instance, kind: VehicleKind, look: CarBody.Look): ViewportFrame
	local view = Instance.new("ViewportFrame")
	view.Name = "Portrait"
	view.BackgroundTransparency = 1
	view.Ambient = Color3.fromRGB(170, 176, 190)
	view.LightColor = Color3.fromRGB(255, 255, 255)
	view.LightDirection = Vector3.new(-0.6, -1, -0.4)
	view.Size = UDim2.fromScale(1, 1)
	view.Parent = parent
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = view
	view.CurrentCamera = camera
	local built = CarBody.Build(kind, CFrame.new(), nil, look)
	CarBody.Anchor(built)
	built.model.Parent = view
	-- Front three-quarters, a little above: the angle every dealer photographs a car from.
	local centre = Vector3.new(0, kind.size.Y / 2 - built.layout.hullY, 0)
	local reach = kind.size.Z * 1.25 + 2
	camera.CFrame = CFrame.lookAt(centre + Vector3.new(-reach * 0.62, reach * 0.3, -reach * 0.78), centre)
	return view
end

-- ---------------------------------------------------------------------------------------------
-- Construction.
-- ---------------------------------------------------------------------------------------------

function DealershipShopUI.new(stage: any, title: string): Handle
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "DealershipShop"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Everything is laid out on a 1280x720 canvas in the middle of the screen and scaled to fit.
	local canvas = frame(gui, "Canvas", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(1280, REFERENCE_HEIGHT), PANEL, 1)
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	local scale = Instance.new("UIScale")
	scale.Parent = canvas

	local self = setmetatable({}, DealershipShopUI) :: Handle
	self.gui = gui
	self.scale = scale
	self.stage = stage
	self.title = title
	self.open = false
	self.catalog = {}
	self.owned = {}
	self.looks = {}
	self.active = nil
	self.money = 0
	self.favorites = {}
	self.tab = "cars"
	self.filter = "all"
	self.brand = nil
	self.sort = "priceUp"
	self.query = ""
	self.viewing = nil
	self.part = "paint"
	self.chosen = {}
	self.noticeToken = 0
	self.cards = {}
	self.moneyLabels = {}
	self.statRows = {}
	self.swatches = {}
	self.partTabs = {}
	self.partRows = {}
	self.tabs = {}
	self.filterButtons = {}

	-- ============================== THE LIST ==============================
	local list = group(canvas, "List")
	self.list = list

	-- Tabs across the top.
	for i, tab in { { key = "cars", label = "🚗  Cars" }, { key = "brands", label = "◆  Brands" } } do
		local b = button(list, "Tab", UDim2.fromOffset(640 - 160 + (i - 1) * 164, 16), UDim2.fromOffset(156, 40), tab.label, PANEL, 18)
		stroke(b, STROKE, 1.5)
		b.MouseButton1Click:Connect(function()
			self:SetTab(tab.key)
		end)
		self.tabs[tab.key] = b
		if tab.key == "brands" then
			local badge = text(b, "New", UDim2.fromOffset(110, -8), UDim2.fromOffset(44, 18), "NEW!", WHITE, 11, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
			badge.BackgroundColor3 = RED
			badge.BackgroundTransparency = 0
			corner(badge, 6)
		end
	end

	-- The side panel.
	local side = frame(list, "Side", UDim2.fromOffset(24, 70), UDim2.fromOffset(250, 552), PANEL, 0.06)
	corner(side, 12)
	stroke(side, STROKE, 1.5)
	text(side, "Title", UDim2.fromOffset(16, 12), UDim2.fromOffset(220, 26), title, WHITE, 21, Enum.Font.GothamBlack)
	text(side, "Subtitle", UDim2.fromOffset(16, 38), UDim2.fromOffset(220, 16), "Purchase and preview vehicles", GREY, 12, Enum.Font.Gotham)
	local bannerBox = frame(side, "Banner", UDim2.fromOffset(12, 64), UDim2.fromOffset(226, 70), CARD, 0)
	corner(bannerBox, 10)
	self.brandBanner = text(bannerBox, "Brand", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), "ALL MAKERS", WHITE, 24, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
	self.brandClear = button(bannerBox, "Clear", UDim2.fromOffset(198, 6), UDim2.fromOffset(22, 22), "X", RED, 12)
	self.brandClear.Visible = false
	self.brandClear.MouseButton1Click:Connect(function()
		self.brand = nil
		self:Refresh()
	end)
	for i, f in FILTERS do
		local b = button(side, "Filter", UDim2.fromOffset(12, 146 + (i - 1) * 42), UDim2.fromOffset(226, 36), `  {f.icon}   {f.label}`, CARD, 15)
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.MouseButton1Click:Connect(function()
			self.filter = f.key
			self:Refresh()
		end)
		self.filterButtons[f.key] = b
	end
	text(side, "SortLabel", UDim2.fromOffset(16, 322), UDim2.fromOffset(200, 18), "SORT", GREY, 13, Enum.Font.GothamBlack)
	self.sortButton = button(side, "Sort", UDim2.fromOffset(12, 344), UDim2.fromOffset(226, 36), "", CARD, 14)
	stroke(self.sortButton, STROKE, 1)
	self.sortMenu = frame(side, "SortMenu", UDim2.fromOffset(12, 384), UDim2.fromOffset(226, #SORTS * 30 + 8), PANEL, 0)
	self.sortMenu.ZIndex = 5
	corner(self.sortMenu, 8)
	stroke(self.sortMenu, STROKE, 1.5)
	self.sortMenu.Visible = false
	for i, option in SORTS do
		local o = button(self.sortMenu, "Option", UDim2.fromOffset(4, 4 + (i - 1) * 30), UDim2.fromOffset(218, 28), option.label, PANEL, 13)
		o.ZIndex = 6
		o.MouseButton1Click:Connect(function()
			self.sort = option.key
			self.sortMenu.Visible = false
			self:Refresh()
		end)
	end
	self.sortButton.MouseButton1Click:Connect(function()
		self.sortMenu.Visible = not self.sortMenu.Visible
	end)
	self.count = text(side, "Count", UDim2.fromOffset(16, 520), UDim2.fromOffset(220, 20), "", DIM, 13, Enum.Font.GothamBold)

	-- Your money, bottom left, as the shop's own panel.
	local purse = frame(list, "Purse", UDim2.fromOffset(24, 634), UDim2.fromOffset(250, 62), PANEL, 0.06)
	corner(purse, 12)
	stroke(purse, STROKE, 1.5)
	text(purse, "YouHave", UDim2.fromOffset(16, 8), UDim2.fromOffset(200, 16), "You have", GREY, 13, Enum.Font.GothamBold)
	table.insert(self.moneyLabels, text(purse, "Money", UDim2.fromOffset(16, 26), UDim2.fromOffset(220, 28), "$0", GOLD, 24, Enum.Font.GothamBlack))

	-- The bar over the grid: search, money, exit.
	local searchBox = frame(list, "SearchBox", UDim2.fromOffset(290, 70), UDim2.fromOffset(640, 42), PANEL, 0.06)
	corner(searchBox, 10)
	stroke(searchBox, STROKE, 1.5)
	text(searchBox, "Glass", UDim2.fromOffset(12, 0), UDim2.fromOffset(24, 42), "⌕", GREY, 18, Enum.Font.GothamBold)
	local search = Instance.new("TextBox")
	search.Name = "Search"
	search.Position = UDim2.fromOffset(40, 0)
	search.Size = UDim2.fromOffset(590, 42)
	search.BackgroundTransparency = 1
	search.PlaceholderText = "Search vehicles..."
	search.PlaceholderColor3 = DIM
	search.Text = ""
	search.TextColor3 = WHITE
	search.TextSize = 16
	search.Font = Enum.Font.Gotham
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.ClearTextOnFocus = false
	search.Parent = searchBox
	search:GetPropertyChangedSignal("Text"):Connect(function()
		self.query = string.lower(search.Text)
		self:Refresh()
	end)
	self.search = search
	local wallet = frame(list, "Wallet", UDim2.fromOffset(940, 70), UDim2.fromOffset(200, 42), PANEL, 0.06)
	corner(wallet, 10)
	stroke(wallet, STROKE, 1.5)
	table.insert(self.moneyLabels, text(wallet, "Money", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), "$0", GOLD, 19, Enum.Font.GothamBlack, Enum.TextXAlignment.Center))
	local exit = button(list, "Exit", UDim2.fromOffset(1150, 70), UDim2.fromOffset(106, 42), "Exit", RED, 18)
	exit.MouseButton1Click:Connect(function()
		self:Close()
	end)

	-- The grid of cars, and the grid of makers behind the other tab.
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(290, 124)
	grid.Size = UDim2.fromOffset(966, 572)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = BLUE
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = list
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.Parent = grid
	self.grid = grid
	self.empty = text(list, "Empty", UDim2.fromOffset(290, 300), UDim2.fromOffset(966, 30), "No vehicles match.", GREY, 18, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	self.empty.Visible = false

	local brandGrid = grid:Clone()
	brandGrid.Name = "Brands"
	brandGrid.Parent = list
	local brandLayout = brandGrid:FindFirstChildOfClass("UIGridLayout") :: UIGridLayout
	brandLayout.CellSize = UDim2.fromOffset(228, 132)
	brandGrid.Visible = false
	self.brandGrid = brandGrid

	-- ============================== THE CAR ==============================
	local detail = group(canvas, "Detail")
	detail.Visible = false
	self.detail = detail

	local plate = frame(detail, "NamePlate", UDim2.fromOffset(640 - 230, 16), UDim2.fromOffset(460, 48), PANEL, 0.08)
	corner(plate, 12)
	stroke(plate, STROKE, 1.5)
	self.nameLabel = text(plate, "Name", UDim2.fromOffset(16, 0), UDim2.fromOffset(390, 48), "", WHITE, 22, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
	self.detailHeart = button(detail, "Heart", UDim2.fromOffset(640 + 240, 20), UDim2.fromOffset(40, 40), "♡", PANEL, 24)
	self.detailHeart.MouseButton1Click:Connect(function()
		local kind = self.viewing
		if kind then
			self.favorites[kind.id] = not self.favorites[kind.id] or nil
			self:RefreshDetail()
			self:Refresh()
		end
	end)
	self.buyButton = button(detail, "Buy", UDim2.fromOffset(640 - 206, 74), UDim2.fromOffset(200, 42), "BUY", GREEN, 18)
	self.testButton = button(detail, "TestDrive", UDim2.fromOffset(640 + 6, 74), UDim2.fromOffset(200, 42), "🚦  TEST DRIVE", BLUE, 17)
	self.driveButton = button(detail, "Drive", UDim2.fromOffset(640 - 206, 74), UDim2.fromOffset(200, 42), "🚗  DRIVE", BLUE, 18)
	self.styleButton = button(detail, "Customize", UDim2.fromOffset(640 + 6, 74), UDim2.fromOffset(200, 42), "🎨  CUSTOMIZE", PURPLE, 17)
	self.buyButton.MouseButton1Click:Connect(function()
		local kind = self.viewing
		local callback = self.onBuy
		if kind and callback and self.money >= kind.price and not self.owned[kind.id] then
			callback(kind.id, table.clone(self.chosen))
		end
	end)
	self.testButton.MouseButton1Click:Connect(function()
		local kind = self.viewing
		local callback = self.onTestDrive
		if kind and callback then
			callback(kind.id, self.chosen.paint)
		end
	end)
	self.driveButton.MouseButton1Click:Connect(function()
		local kind = self.viewing
		local callback = self.onDrive
		if kind and callback then
			callback(kind.id)
		end
	end)
	self.styleButton.MouseButton1Click:Connect(function()
		local kind = self.viewing
		if kind == nil then
			return
		end
		local callback = self.onCustomize
		if not sameLook(self.chosen, self:SavedLook(kind.id)) and callback then
			callback(kind.id, table.clone(self.chosen))
		else
			-- Nothing changed yet: point at the look bar, starting from the rims.
			self:SetPart(if self.part == "paint" then "rims" else self.part)
		end
	end)
	local back = button(detail, "Back", UDim2.fromOffset(1280 - 24 - 190, 18), UDim2.fromOffset(190, 40), "Back to Vehicles", RED, 16)
	back.MouseButton1Click:Connect(function()
		self:ShowList()
	end)

	-- Two small view buttons over the stats, and the stats.
	local spin = button(detail, "Spin", UDim2.fromOffset(1280 - 24 - 130, 346), UDim2.fromOffset(130, 30), "🔄  Turntable", BLUE_DARK, 13)
	local spinning = true
	spin.MouseButton1Click:Connect(function()
		spinning = not spinning
		spin.BackgroundColor3 = if spinning then BLUE_DARK else CARD
		self.stage:SetAutoSpin(spinning)
	end)
	local reset = button(detail, "Reset", UDim2.fromOffset(1280 - 24 - 270, 346), UDim2.fromOffset(130, 30), "⌂  Reset View", BLUE_DARK, 13)
	reset.MouseButton1Click:Connect(function()
		self.stage:ResetView()
	end)
	local stats = frame(detail, "Stats", UDim2.fromOffset(1280 - 24 - 270, 384), UDim2.fromOffset(270, 250), PANEL, 0.06)
	corner(stats, 12)
	stroke(stats, STROKE, 1.5)
	text(stats, "Title", UDim2.fromOffset(14, 8), UDim2.fromOffset(240, 26), "Vehicle Stats", WHITE, 19, Enum.Font.GothamBlack)
	for i, row in { { key = "speed", label = "Top Speed" }, { key = "accel", label = "Acceleration" }, { key = "handling", label = "Handling" } } do
		local y = 40 + (i - 1) * 30
		text(stats, "Label", UDim2.fromOffset(14, y), UDim2.fromOffset(100, 20), row.label, GREY, 13, Enum.Font.GothamBold)
		local track = frame(stats, "Track", UDim2.fromOffset(112, y + 5), UDim2.fromOffset(92, 10), CARD, 0)
		corner(track, 5)
		local bar = frame(track, "Bar", UDim2.new(), UDim2.fromScale(0.5, 1), BLUE, 0)
		corner(bar, 5)
		local value = text(stats, "Value", UDim2.fromOffset(208, y), UDim2.fromOffset(56, 20), "", WHITE, 13, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
		self.statRows[row.key] = { bar = bar, value = value }
	end
	self.statNotes = text(stats, "Notes", UDim2.fromOffset(14, 132), UDim2.fromOffset(242, 18), "", GREY, 13, Enum.Font.Gotham)
	self.priceLabel = text(stats, "Price", UDim2.fromOffset(14, 158), UDim2.fromOffset(242, 34), "", GOLD, 28, Enum.Font.GothamBlack)
	self.ownedLabel = text(stats, "Owned", UDim2.fromOffset(14, 198), UDim2.fromOffset(242, 36), "", WHITE, 15, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	self.ownedLabel.BackgroundColor3 = BLUE
	self.ownedLabel.BackgroundTransparency = 0
	corner(self.ownedLabel, 8)

	-- The look along the bottom: three tabs, a row of swatches under each.
	local most = 0
	for _, part in PARTS do
		most = math.max(most, #part.list + (if part.key == "glow" then 1 else 0))
	end
	local barWidth = most * 42 + 132
	local lookBar = frame(detail, "Look", UDim2.fromOffset(640 - barWidth / 2, 630), UDim2.fromOffset(barWidth, 74), PANEL, 0.06)
	corner(lookBar, 12)
	stroke(lookBar, STROKE, 1.5)
	for i, part in PARTS do
		local t = button(lookBar, "PartTab", UDim2.fromOffset(10, 6 + (i - 1) * 21), UDim2.fromOffset(112, 19), part.label, CARD, 12)
		t.MouseButton1Click:Connect(function()
			self:SetPart(part.key)
		end)
		self.partTabs[part.key] = t
		local row = frame(lookBar, "Row", UDim2.fromOffset(128, 0), UDim2.new(1, -128, 1, 0), PANEL, 1)
		row.Visible = false
		self.partRows[part.key] = row
		local swatches: { [string]: TextButton } = {}
		local entries: { Paint } = table.clone(part.list)
		if part.key == "glow" then
			-- Underglow can be switched off: a first swatch for none.
			table.insert(entries, 1, { key = "", name = part.none, color = CARD })
		end
		for j, entry in entries do
			local swatch = button(row, "Swatch", UDim2.fromOffset(4 + (j - 1) * 42, 20), UDim2.fromOffset(34, 34), if entry.key == "" then "X" else "", entry.color, 14)
			swatch.TextColor3 = GREY
			stroke(swatch, STROKE, 2)
			swatch.MouseButton1Click:Connect(function()
				local key = if entry.key == "" then nil else entry.key
				if part.key == "paint" then
					self.chosen.paint = key
				elseif part.key == "rims" then
					self.chosen.rims = key
				else
					self.chosen.glow = key
				end
				local kind = self.viewing
				if kind then
					self.stage:Show(kind, CarBody.LookOf(self.chosen.paint, self.chosen.rims, self.chosen.glow))
				end
				self:RefreshDetail()
			end)
			swatches[entry.key] = swatch
		end
		self.swatches[part.key] = swatches
	end
	self.lookName = text(detail, "LookName", UDim2.fromOffset(640 - 200, 604), UDim2.fromOffset(400, 22), "", WHITE, 15, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	self.lookName.TextStrokeTransparency = 0.5

	local purse2 = purse:Clone()
	purse2.Parent = detail
	table.insert(self.moneyLabels, purse2:FindFirstChild("Money") :: TextLabel)

	-- The moment a car is yours.
	local banner = text(canvas, "Purchased", UDim2.fromOffset(640, 300), UDim2.fromOffset(600, 90), "🎉  PURCHASED!", GOLD, 56, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.TextStrokeColor3 = Color3.fromRGB(60, 40, 0)
	banner.TextStrokeTransparency = 0.2
	banner.ZIndex = 20
	banner.Visible = false
	self.banner = banner

	-- A notice, dropping in under the top of whichever view is showing.
	local notice = text(canvas, "Notice", UDim2.fromOffset(640 - 260, 128), UDim2.fromOffset(520, 40), "", WHITE, 17, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	notice.BackgroundColor3 = PANEL
	notice.BackgroundTransparency = 0.05
	notice.ZIndex = 10
	notice.Visible = false
	corner(notice, 10)
	stroke(notice, BLUE, 1.5)
	self.notice = notice

	self:SetPart("paint")
	self:Refresh()
	return self
end

-- ---------------------------------------------------------------------------------------------
-- What goes on the grid.
-- ---------------------------------------------------------------------------------------------

local function sorted(self: Handle, cars: { VehicleKind }): { VehicleKind }
	local list = table.clone(cars)
	local key = self.sort
	table.sort(list, function(a: VehicleKind, b: VehicleKind): boolean
		if key == "priceDown" then
			return a.price > b.price
		elseif key == "speed" then
			return a.topSpeedStuds > b.topSpeedStuds
		elseif key == "accel" then
			return a.acceleration > b.acceleration
		elseif key == "year" then
			return (a.year or 0) > (b.year or 0)
		elseif key == "name" then
			return a.name < b.name
		end
		return a.price < b.price
	end)
	return list
end

local function visible(self: Handle, kind: VehicleKind): boolean
	if self.brand and kind.brand ~= self.brand then
		return false
	end
	if self.filter == "new" and not kind.isNew then
		return false
	elseif self.filter == "owned" and not self.owned[kind.id] then
		return false
	elseif self.filter == "favorites" and not self.favorites[kind.id] then
		return false
	end
	if self.query ~= "" then
		local haystack = string.lower(`{kind.year or ""} {kind.name} {kind.brand or ""}`)
		if not string.find(haystack, self.query, 1, true) then
			return false
		end
	end
	return true
end

local function buildCard(self: Handle, kind: VehicleKind, order: number): Card
	local card = frame(self.grid, "Card", UDim2.new(), UDim2.new(), CARD, 0)
	card.LayoutOrder = order
	corner(card, 10)
	stroke(card, STROKE, 1.5)
	local grow = Instance.new("UIScale")
	grow.Parent = card
	local shot = frame(card, "Shot", UDim2.fromOffset(4, 24), UDim2.fromOffset(CARD_W - 8, 96), CARD, 1)
	local saved = self:SavedLook(kind.id)
	portrait(shot, kind, CarBody.LookOf(saved.paint, saved.rims, saved.glow))
	local name = text(card, "Name", UDim2.fromOffset(10, 6), UDim2.fromOffset(CARD_W - 20, 18), displayName(kind), WHITE, 13, Enum.Font.GothamBold)
	name.ZIndex = 2
	local price = text(card, "Price", UDim2.fromOffset(10, 122), UDim2.fromOffset(120, 24), "", GOLD, 17, Enum.Font.GothamBlack)
	local heart = button(card, "Heart", UDim2.fromOffset(CARD_W - 36, 120), UDim2.fromOffset(28, 26), "♡", CARD, 18)
	heart.TextColor3 = GREY
	heart.ZIndex = 3
	heart.MouseButton1Click:Connect(function()
		self.favorites[kind.id] = not self.favorites[kind.id] or nil
		self:Refresh()
	end)
	if kind.isNew then
		local badge = text(card, "New", UDim2.fromOffset(CARD_W - 50, 6), UDim2.fromOffset(42, 16), "NEW!", WHITE, 10, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
		badge.BackgroundColor3 = RED
		badge.BackgroundTransparency = 0
		badge.ZIndex = 3
		corner(badge, 5)
		name.Size = UDim2.fromOffset(CARD_W - 64, 18)
	end
	local hit = Instance.new("TextButton")
	hit.Name = "Open"
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Size = UDim2.new(1, 0, 1, -30)
	hit.ZIndex = 2
	hit.Parent = card
	hit.MouseButton1Click:Connect(function()
		self:ShowCar(kind)
	end)
	local outline = card:FindFirstChildOfClass("UIStroke")
	hit.MouseEnter:Connect(function()
		card.BackgroundColor3 = CARD_HOVER
		if outline then
			outline.Color = BLUE
		end
		tween(grow, 0.15, { Scale = 1.05 })
	end)
	hit.MouseLeave:Connect(function()
		card.BackgroundColor3 = CARD
		if outline then
			outline.Color = STROKE
		end
		tween(grow, 0.2, { Scale = 1 })
	end)
	return { frame = card, heart = heart, price = price, kind = kind, grow = grow }
end

local function rebuildBrands(self: Handle)
	for _, child in self.brandGrid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local counts: { [string]: number } = {}
	local order: { string } = {}
	for _, kind in self.catalog do
		local brand = kind.brand or "Other"
		if counts[brand] == nil then
			counts[brand] = 0
			table.insert(order, brand)
		end
		counts[brand] += 1
	end
	table.sort(order)
	for i, brand in order do
		local tile = frame(self.brandGrid, "Brand", UDim2.new(), UDim2.new(), CARD, 0)
		tile.LayoutOrder = i
		corner(tile, 12)
		stroke(tile, STROKE, 1.5)
		text(tile, "Wordmark", UDim2.fromOffset(0, 26), UDim2.new(1, 0, 0, 44), string.upper(brand), BRAND_COLORS[brand] or WHITE, 30, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
		text(tile, "Count", UDim2.fromOffset(0, 80), UDim2.new(1, 0, 0, 20), `{counts[brand]} vehicle{if counts[brand] == 1 then "" else "s"}`, GREY, 14, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.Parent = tile
		hit.MouseButton1Click:Connect(function()
			self.brand = brand
			self:SetTab("cars")
		end)
	end
end

-- Fades a view in, rising a little as it comes.
local function reveal(view: CanvasGroup)
	view.Visible = true
	view.GroupTransparency = 1
	view.Position = UDim2.fromOffset(0, 24)
	tween(view, 0.35, { GroupTransparency = 0, Position = UDim2.new() })
end

-- ---------------------------------------------------------------------------------------------
-- Public.
-- ---------------------------------------------------------------------------------------------

-- The look an owned car wears, as keys; empty for a car not owned.
function DealershipShopUI.SavedLook(self: Handle, id: string): LookKeys
	local looks = self.looks
	return {
		paint = (looks.paint or {})[id],
		rims = (looks.rims or {})[id],
		glow = (looks.glow or {})[id],
	}
end

function DealershipShopUI.SetCatalog(self: Handle, catalog: { VehicleKind })
	self.catalog = catalog
	for _, card in self.cards do
		card.frame:Destroy()
	end
	table.clear(self.cards)
	for i, kind in catalog do
		table.insert(self.cards, buildCard(self, kind, i))
	end
	rebuildBrands(self)
	self:Refresh()
end

function DealershipShopUI.SetOwned(self: Handle, owned: { [string]: boolean }, looks: Looks, active: string?)
	-- A car bought or restyled: its card is redrawn in the look it now wears.
	local changed = false
	for _, kind in self.catalog do
		local before = self:SavedLook(kind.id)
		local after: LookKeys = { paint = (looks.paint or {})[kind.id], rims = (looks.rims or {})[kind.id], glow = (looks.glow or {})[kind.id] }
		if not sameLook(before, after) then
			changed = true
		end
	end
	local viewing = self.viewing
	local justBought = viewing ~= nil and not self.owned[viewing.id] and owned[viewing.id] == true
	self.owned = owned
	self.looks = looks
	self.active = active
	if changed and #self.catalog > 0 then
		self:SetCatalog(self.catalog)
	end
	if justBought then
		self:Celebrate()
	end
	self:Refresh()
	self:RefreshDetail()
end

function DealershipShopUI.SetMoney(self: Handle, balance: number)
	self.money = balance
	for _, label in self.moneyLabels do
		label.Text = money(balance)
	end
	self:Refresh()
	self:RefreshDetail()
end

function DealershipShopUI.Notice(self: Handle, message: string)
	self.noticeToken += 1
	local token = self.noticeToken
	self.notice.Text = message
	self.notice.Visible = true
	task.delay(3, function()
		if self.noticeToken == token then
			self.notice.Visible = false
		end
	end)
end

-- The PURCHASED! banner: in with a bounce, held, and gone.
function DealershipShopUI.Celebrate(self: Handle)
	local banner = self.banner
	local grow = banner:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	grow.Parent = banner
	grow.Scale = 0.3
	banner.TextTransparency = 0
	banner.TextStrokeTransparency = 0.2
	banner.Visible = true
	TweenService:Create(grow, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.6, function()
		tween(banner, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quad)
		task.delay(0.6, function()
			banner.Visible = false
		end)
	end)
end

function DealershipShopUI.OnBuy(self: Handle, callback: (string, LookKeys) -> ())
	self.onBuy = callback
end

function DealershipShopUI.OnTestDrive(self: Handle, callback: (string, string?) -> ())
	self.onTestDrive = callback
end

function DealershipShopUI.OnDrive(self: Handle, callback: (string) -> ())
	self.onDrive = callback
end

function DealershipShopUI.OnCustomize(self: Handle, callback: (string, LookKeys) -> ())
	self.onCustomize = callback
end

function DealershipShopUI.OnClose(self: Handle, callback: () -> ())
	self.onClose = callback
end

function DealershipShopUI.IsOpen(self: Handle): boolean
	return self.open
end

-- Fits the 1280x720 canvas to the screen: what makes a phone and a monitor see one layout. Fitted
-- below Roblox's own top bar: the gui ignores the inset so the backdrop reaches the top of the
-- screen, but the shop's buttons must not sit under the menu and chat buttons -- on a screen as
-- short as a phone's the top row, Exit with it, was there and could not be pressed.
local function fit(self: Handle)
	local camera = Workspace.CurrentCamera
	if camera then
		local size = camera.ViewportSize
		local top = GuiService:GetGuiInset().Y
		self.scale.Scale = math.clamp(math.min((size.Y - top) / REFERENCE_HEIGHT, size.X / 1280), 0.3, 1.6)
		local canvas = self.scale.Parent
		if canvas and canvas:IsA("GuiObject") then
			canvas.Position = UDim2.new(0.5, 0, 0.5, top / 2)
		end
	end
end

function DealershipShopUI.Open(self: Handle)
	if self.open then
		return
	end
	self.open = true
	fit(self)
	-- And again if the window changes while the shop is up: a phone turned, a window resized.
	local camera = Workspace.CurrentCamera
	if self.refit == nil and camera then
		self.refit = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if self.open then
				fit(self)
			end
		end)
	end
	self.gui.Enabled = true
	self:ShowList()
end

function DealershipShopUI.Close(self: Handle)
	if not self.open then
		return
	end
	self.open = false
	self.gui.Enabled = false
	self.viewing = nil
	self.stage:Leave()
	local callback = self.onClose
	if callback then
		callback()
	end
end

function DealershipShopUI.SetTab(self: Handle, tab: string)
	self.tab = tab
	self.sortMenu.Visible = false
	self:Refresh()
end

function DealershipShopUI.SetPart(self: Handle, part: string)
	self.part = part
	for key, t in self.partTabs do
		t.BackgroundColor3 = if key == part then BLUE else CARD
	end
	for key, row in self.partRows do
		row.Visible = key == part
	end
	self:RefreshDetail()
end

function DealershipShopUI.ShowList(self: Handle)
	self.viewing = nil
	self.detail.Visible = false
	self.stage:Leave()
	reveal(self.list)
	self:Refresh()
end

function DealershipShopUI.ShowCar(self: Handle, kind: VehicleKind)
	self.viewing = kind
	self.chosen = self:SavedLook(kind.id)
	self.list.Visible = false
	self.sortMenu.Visible = false
	reveal(self.detail)
	-- The two cars behind it: the next two in the list, as they came.
	local others: { VehicleKind } = {}
	for _, other in sorted(self, self.catalog) do
		if other.id ~= kind.id and #others < 2 then
			table.insert(others, other)
		end
	end
	self.stage:Enter()
	self.stage:Dress(others)
	self.stage:Show(kind, CarBody.LookOf(self.chosen.paint, self.chosen.rims, self.chosen.glow))
	self.stage:Sweep()
	self:SetPart("paint")
end

function DealershipShopUI.IsViewing(self: Handle): boolean
	return self.viewing ~= nil
end

function DealershipShopUI.Refresh(self: Handle)
	for key, b in self.tabs do
		b.BackgroundColor3 = if self.tab == key then BLUE else PANEL
	end
	for key, b in self.filterButtons do
		b.BackgroundColor3 = if self.filter == key then BLUE else CARD
	end
	local brand = self.brand
	self.brandBanner.Text = if brand then string.upper(brand) else "ALL MAKERS"
	self.brandBanner.TextColor3 = if brand then (BRAND_COLORS[brand] or WHITE) else WHITE
	self.brandClear.Visible = brand ~= nil
	for _, option in SORTS do
		if option.key == self.sort then
			self.sortButton.Text = `{option.label}   ▼`
		end
	end

	local onCars = self.tab == "cars"
	self.grid.Visible = onCars
	self.brandGrid.Visible = not onCars
	local order: { [string]: number } = {}
	for i, kind in sorted(self, self.catalog) do
		order[kind.id] = i
	end
	local shown, ownedCount = 0, 0
	for _, card in self.cards do
		local kind = card.kind
		local show = visible(self, kind)
		card.frame.Visible = show
		card.frame.LayoutOrder = order[kind.id] or 0
		if show then
			shown += 1
		end
		if self.owned[kind.id] then
			ownedCount += 1
			card.price.Text = "OWNED"
			card.price.TextColor3 = GREEN
		else
			card.price.Text = money(kind.price)
			card.price.TextColor3 = if self.money >= kind.price then GOLD else DIM
		end
		local fav = self.favorites[kind.id] == true
		card.heart.Text = if fav then "♥" else "♡"
		card.heart.TextColor3 = if fav then HEART else GREY
	end
	self.empty.Visible = onCars and shown == 0
	self.count.Text = `{shown} shown  •  {ownedCount} of {#self.catalog} owned`
end

function DealershipShopUI.RefreshDetail(self: Handle)
	local kind = self.viewing
	if kind == nil then
		return
	end
	self.nameLabel.Text = displayName(kind)
	local fav = self.favorites[kind.id] == true
	self.detailHeart.Text = if fav then "♥" else "♡"
	self.detailHeart.TextColor3 = if fav then HEART else WHITE

	local owned = self.owned[kind.id] == true
	self.buyButton.Visible = not owned
	self.testButton.Visible = not owned
	self.driveButton.Visible = owned
	self.styleButton.Visible = owned
	local affordable = self.money >= kind.price
	self.buyButton.Text = if affordable then `BUY  {money(kind.price)}` else `NEED  {money(kind.price - self.money)}  MORE`
	self.buyButton.BackgroundColor3 = if affordable then GREEN else CARD
	self.buyButton.AutoButtonColor = affordable
	self.driveButton.Text = if self.active == kind.id then "🚗  DRIVING" else "🚗  DRIVE"
	local unsaved = owned and not sameLook(self.chosen, self:SavedLook(kind.id))
	self.styleButton.Text = if unsaved then "💾  SAVE LOOK" else "🎨  CUSTOMIZE"
	self.styleButton.BackgroundColor3 = if unsaved then GREEN else PURPLE

	local speed = self.statRows.speed
	speed.value.Text = `{CarBody.Mph(kind.topSpeedStuds, kind.scale)} MPH`
	speed.bar.Size = UDim2.fromScale(rating(kind.topSpeedStuds, 60, 140) / 10, 1)
	local accel = self.statRows.accel
	local a = rating(kind.acceleration, 8, 20)
	accel.value.Text = string.format("%.1f", a)
	accel.bar.Size = UDim2.fromScale(a / 10, 1)
	local handling = self.statRows.handling
	local h = rating(kind.steerDegrees, 20, 40)
	handling.value.Text = string.format("%.1f", h)
	handling.bar.Size = UDim2.fromScale(h / 10, 1)
	local notes: { string } = {}
	if kind.drivetrain then
		table.insert(notes, kind.drivetrain)
	end
	if kind.seats then
		table.insert(notes, `{kind.seats} seats`)
	end
	if kind.brand then
		table.insert(notes, kind.brand)
	end
	self.statNotes.Text = table.concat(notes, "  •  ")
	self.priceLabel.Text = money(kind.price)
	self.ownedLabel.Text = if owned then "Owned" elseif affordable then "Available" else "Can't afford yet"
	self.ownedLabel.BackgroundColor3 = if owned then BLUE elseif affordable then GREEN else CARD

	-- The swatches: the one chosen in each part ringed in white.
	local chosenKeys = { paint = self.chosen.paint, rims = self.chosen.rims, glow = self.chosen.glow }
	local names: { string } = {}
	for _, part in PARTS do
		local chosenKey = chosenKeys[part.key] or ""
		for key, swatch in self.swatches[part.key] do
			local s = swatch:FindFirstChildOfClass("UIStroke")
			if s then
				s.Color = if key == chosenKey then WHITE else STROKE
				s.Thickness = if key == chosenKey then 3 else 2
			end
		end
		local entry: Paint? = nil
		for _, candidate in part.list do
			if candidate.key == chosenKey then
				entry = candidate
			end
		end
		table.insert(names, if entry then (entry :: Paint).name else part.none)
	end
	self.lookName.Text = table.concat(names, "   •   ")
end

return DealershipShopUI
