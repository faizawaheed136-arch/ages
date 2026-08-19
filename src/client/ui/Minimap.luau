--!strict
-- The corner map: where you are, what is near you, and whose side you are standing on.
--
-- Bottom right, which is the last free corner -- StatsUI holds the top right, HeatUI the
-- top centre, and a choice takes the middle. Bottom right is also the corner a player's
-- eye goes to least often, which is correct for a surface that answers "where am I" only
-- when asked.
--
-- **North is up and stays up.** The alternative -- rotating the map under a fixed
-- player arrow -- is more common in shooters and is wrong here. This game already has a
-- compass: GeographyService describes destinations in eight named sectors ("the
-- north-east side of town") and every errand hint the player has ever read is phrased
-- that way. A map that spins cannot be read against a sentence that does not, so the
-- map holds still and the player turns.
--
-- **The wash under the icons is whose turf it is, not what the ground is.** There is no
-- terrain art here and deliberately none planned: a painted map is a second copy of the
-- world that goes stale the first time gen_city.py runs, and this tree's most expensive
-- recurring defect is exactly that -- one measurement written down twice. Everything
-- drawn is computed from the place points that exist. See Shared/WorldMap.
--
-- Nothing here decides anything. It reads two pushes and a position, and clicking it
-- opens the full sheet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local WorldMap = require(ReplicatedStorage:WaitForChild("WorldMap"))
local MapIcons = require(script.Parent.Parent.ui.MapIcons)

type MapData = Types.MapData
type TerritoryState = Types.TerritoryState

local MAP = Config.Map

local SIZE_PIXELS = 168
local MARGIN_PIXELS = 16

local DIAL_COLOR = Color3.fromRGB(16, 17, 22)
local RING_COLOR = Color3.fromRGB(96, 102, 118)
local CAPTION_COLOR = Color3.fromRGB(206, 210, 222)
local SUBCAPTION_COLOR = Color3.fromRGB(150, 155, 170)

-- The four letters around the rim, and where each sits as a fraction of the dial.
-- Roblox's +Z runs south, so "north" is -Z and therefore the top of the dial -- the one
-- axis flip in this file, written once, here.
local CARDINALS = {
	{ text = "N", x = 0.5, y = 0.06 },
	{ text = "E", x = 0.94, y = 0.5 },
	{ text = "S", x = 0.5, y = 0.94 },
	{ text = "W", x = 0.06, y = 0.5 },
}

local Minimap = {}
Minimap.__index = Minimap

export type MinimapHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		dial: Frame,
		field: Frame,
		wash: Frame,
		youDot: Frame,
		regionLabel: TextLabel,
		depthLabel: TextLabel,
		button: TextButton,
		data: MapData?,
		territory: TerritoryState?,
		markers: { Frame },
		onOpen: (() -> ())?,
		-- Turned off in Settings. A separate flag from `dial.Visible`, which Redraw owns and
		-- rewrites every heartbeat from whether the character exists -- a preference written
		-- straight onto that property would be erased sixty times a second.
		hidden: boolean,
	},
	Minimap
))

local function makeDot(parent: Instance, size: number, color: Color3, order: number): Frame
	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(0, size, 0, size)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	dot.ZIndex = order
	dot.Visible = false
	dot.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot

	return dot
end

function Minimap.new(): MinimapHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesMinimap"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	-- Below the heat bar and below a choice. The map is the least urgent thing on
	-- screen by construction: it answers a question the player chose to ask.
	screenGui.DisplayOrder = 2
	screenGui.Parent = playerGui

	local dial = Instance.new("Frame")
	dial.Name = "Dial"
	dial.Size = UDim2.new(0, SIZE_PIXELS, 0, SIZE_PIXELS)
	dial.AnchorPoint = Vector2.new(1, 1)
	dial.Position = UDim2.new(1, -MARGIN_PIXELS, 1, -MARGIN_PIXELS)
	dial.BackgroundColor3 = DIAL_COLOR
	dial.BackgroundTransparency = 0.08
	dial.BorderSizePixel = 0
	dial.Visible = false
	dial.Parent = screenGui

	local dialCorner = Instance.new("UICorner")
	dialCorner.CornerRadius = UDim.new(1, 0)
	dialCorner.Parent = dial

	local ring = Instance.new("UIStroke")
	ring.Color = RING_COLOR
	ring.Thickness = 2
	ring.Transparency = 0.35
	ring.Parent = dial

	-- Everything that moves lives inside this, and it clips. Without the clip an icon
	-- three hundred studs away is still drawn, just outside the circle, and the corner
	-- of the screen fills up with the whole city.
	local field = Instance.new("Frame")
	field.Name = "Field"
	field.Size = UDim2.new(1, 0, 1, 0)
	field.BackgroundTransparency = 1
	field.ClipsDescendants = true
	field.Parent = dial

	local fieldCorner = Instance.new("UICorner")
	fieldCorner.CornerRadius = UDim.new(1, 0)
	fieldCorner.Parent = field

	-- A flat tint of whichever side the player is standing on. The full sheet samples
	-- the boundaries properly; at this size a boundary would be two pixels of noise, so
	-- the minimap answers the simpler question -- whose side is this -- with one colour.
	local wash = Instance.new("Frame")
	wash.Name = "Wash"
	wash.Size = UDim2.new(1, 0, 1, 0)
	wash.BackgroundColor3 = DIAL_COLOR
	wash.BackgroundTransparency = 1
	wash.BorderSizePixel = 0
	wash.ZIndex = 1
	wash.Parent = field

	for _, cardinal in CARDINALS do
		local letter = Instance.new("TextLabel")
		letter.Name = cardinal.text
		letter.Size = UDim2.new(0, 14, 0, 14)
		letter.AnchorPoint = Vector2.new(0.5, 0.5)
		letter.Position = UDim2.new(cardinal.x, 0, cardinal.y, 0)
		letter.BackgroundTransparency = 1
		letter.Font = Enum.Font.GothamBold
		letter.TextSize = 11
		letter.TextColor3 = RING_COLOR
		letter.Text = cardinal.text
		letter.ZIndex = 40
		letter.Parent = dial
	end

	local youDot = makeDot(field, MAP.YouSizePixels, MAP.YouColor, 50)
	youDot.Position = UDim2.new(0.5, 0, 0.5, 0)
	youDot.Visible = true

	local youRing = Instance.new("UIStroke")
	youRing.Color = Color3.fromRGB(12, 40, 20)
	youRing.Thickness = 2
	youRing.Parent = youDot

	local caption = Instance.new("Frame")
	caption.Name = "Caption"
	caption.Size = UDim2.new(1, 40, 0, 30)
	caption.AnchorPoint = Vector2.new(0.5, 1)
	caption.Position = UDim2.new(0.5, 0, 0, -4)
	caption.BackgroundTransparency = 1
	caption.Parent = dial

	local regionLabel = Instance.new("TextLabel")
	regionLabel.Name = "Region"
	regionLabel.Size = UDim2.new(1, 0, 0, 15)
	regionLabel.BackgroundTransparency = 1
	regionLabel.Font = Enum.Font.GothamBold
	regionLabel.TextSize = 12
	regionLabel.TextColor3 = CAPTION_COLOR
	regionLabel.Text = ""
	regionLabel.Parent = caption

	local depthLabel = Instance.new("TextLabel")
	depthLabel.Name = "Depth"
	depthLabel.Size = UDim2.new(1, 0, 0, 13)
	depthLabel.Position = UDim2.new(0, 0, 0, 15)
	depthLabel.BackgroundTransparency = 1
	depthLabel.Font = Enum.Font.Gotham
	depthLabel.TextSize = 10
	depthLabel.TextColor3 = SUBCAPTION_COLOR
	depthLabel.Text = ""
	depthLabel.Parent = caption

	-- The whole dial is the button. A small "expand" affordance in a corner of a circle
	-- would be a two-pixel target on a phone, and there is nothing else the player could
	-- possibly want from clicking a map.
	local button = Instance.new("TextButton")
	button.Name = "Open"
	button.Size = UDim2.new(1, 0, 1, 0)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.ZIndex = 60
	button.Parent = dial

	local self: MinimapHandle = setmetatable({
		screenGui = screenGui,
		dial = dial,
		field = field,
		wash = wash,
		youDot = youDot,
		regionLabel = regionLabel,
		depthLabel = depthLabel,
		button = button,
		data = nil,
		territory = nil,
		markers = {},
		onOpen = nil,
		hidden = false,
	}, Minimap)

	button.Activated:Connect(function()
		local open = self.onOpen
		if open ~= nil then
			open()
		end
	end)

	RunService.Heartbeat:Connect(function()
		Minimap.Redraw(self)
	end)

	return self
end

-- Called once, when the server sends the map. Builds one marker per place and then
-- never creates another: Redraw runs many times a second and allocating there would
-- make the corner of the screen the most expensive thing in the game.
function Minimap.SetMapData(self: MinimapHandle, data: MapData)
	self.data = data

	for _, marker in self.markers do
		marker:Destroy()
	end
	table.clear(self.markers)

	for _, icon in data.icons do
		local style = MapIcons.StyleFor(icon.id)
		local dot = makeDot(self.field, math.max(math.floor(style.size * MAP.Icons.MinimapIconScale), 3), style.color, 10 + style.priority)
		self.markers[#self.markers + 1] = dot
	end

	self.dial.Visible = not self.hidden
end

-- Hide the dial without tearing it down. The markers, the wash and the heartbeat all stay
-- exactly as they were, because a setting somebody flips twice in a life is not worth a
-- rebuild -- and a minimap that had to be reconstructed on the way back would spend its
-- first frames wrong.
function Minimap.SetHidden(self: MinimapHandle, hidden: boolean)
	self.hidden = hidden
	if hidden then
		self.dial.Visible = false
	end
end

function Minimap.SetTerritory(self: MinimapHandle, state: TerritoryState?)
	self.territory = state
end

function Minimap.SetOnOpen(self: MinimapHandle, callback: () -> ())
	self.onOpen = callback
end

function Minimap.Redraw(self: MinimapHandle)
	local data = self.data
	if data == nil then
		return
	end

	-- Checked before the character lookup, not after: this runs every heartbeat, and a
	-- player who has turned the dial off should not be paying for a character walk to
	-- decide something that is already decided.
	if self.hidden then
		self.dial.Visible = false
		return
	end

	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil then
		self.dial.Visible = false
		return
	end
	self.dial.Visible = true

	local here = (root :: BasePart).Position
	local bounds: WorldMap.Bounds = {
		minX = data.minX,
		maxX = data.maxX,
		minZ = data.minZ,
		maxZ = data.maxZ,
	}

	-- Studs to pixels. The dial's radius shows MinimapRadiusStuds of world, so a place
	-- exactly that far away lands exactly on the rim and is clipped the instant it is
	-- further -- which is the behaviour the radius is named for.
	local scale = (SIZE_PIXELS / 2) / MAP.MinimapRadiusStuds

	for index, icon in data.icons do
		local marker = self.markers[index]
		if marker == nil then
			continue
		end
		local worldX, worldZ = WorldMap.Denormalize(bounds, icon.u, icon.v)
		local offsetX = (worldX - here.X) * scale
		-- No negation: north is -Z and screen Y grows downward, so a place north of the
		-- player already produces a negative offset and therefore draws above them.
		local offsetY = (worldZ - here.Z) * scale

		if offsetX * offsetX + offsetY * offsetY > (SIZE_PIXELS / 2) ^ 2 then
			marker.Visible = false
			continue
		end

		marker.Visible = true
		marker.Position = UDim2.new(0.5, math.floor(offsetX), 0.5, math.floor(offsetY))
	end

	local territory = self.territory
	local region = if territory ~= nil then territory.regionId else nil
	if region == nil then
		self.wash.BackgroundTransparency = 1
		self.regionLabel.Text = ""
		self.depthLabel.Text = ""
		return
	end

	local tint = MapIcons.RegionColor(data, region)
	if tint ~= nil then
		self.wash.BackgroundColor3 = tint
		self.wash.BackgroundTransparency = MAP.RegionTransparency
	else
		self.wash.BackgroundTransparency = 1
	end

	self.regionLabel.Text = MapIcons.RegionName(data, region)

	-- The one number worth showing, and only while it is being earned. Depth is what the
	-- incursion award is computed from, so a player watching it climb is watching the
	-- only quantity that pays -- and a player standing still watches it not move, which
	-- is the lesson.
	if territory ~= nil and territory.onIncursion then
		self.depthLabel.Text = `deep as {territory.deepestStuds} studs`
		self.depthLabel.TextColor3 = MAP.YouColor
	else
		self.depthLabel.Text = "your side"
		self.depthLabel.TextColor3 = SUBCAPTION_COLOR
	end
end

return Minimap
