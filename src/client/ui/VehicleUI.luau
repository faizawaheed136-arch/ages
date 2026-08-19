--!strict
-- The showroom and the garage: what the lot sells, what this life already owns,
-- and which one -- if any -- is standing outside right now. Separate from
-- CarDealerUI on purpose, even though they are the same building: that panel is
-- the counter job, always at the bottom-left corner every activity panel takes,
-- and this is a life's own property, on the same footing as HouseUI. The two can
-- be open at once -- a player working a shift while also thinking about trading
-- their car in is not a contradiction -- so this sits top-left, the one corner
-- StatsUI, CarDealerUI/HouseUI/TillUI and GangUI leave alone.
--
-- Also carries the speedometer: a single line that appears only while the local
-- character is seated in a VehicleSeat, because that is the one number driving
-- actually gives the player to read and everything else about the car is felt
-- through the controls rather than a HUD.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Money = require(ReplicatedStorage:WaitForChild("Money"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type VehicleState = Types.VehicleState
type VehicleKind = Types.VehicleKind

local PANEL_WIDTH = 300

local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local CAPTION_COLOR = Color3.fromRGB(146, 150, 162)
local ROW_COLOR = Color3.fromRGB(28, 29, 36)
local ROW_ACTIVE_COLOR = Color3.fromRGB(40, 52, 46)
local NAME_COLOR = Color3.fromRGB(226, 228, 236)
local PRICE_COLOR = Color3.fromRGB(180, 190, 210)

-- Same teal the dealership's own floor marker and panel already use -- see
-- DealerMark.luau -- so a car row and the showroom disc outside read as the
-- same brand.
local ACCENT_COLOR = Color3.fromRGB(50, 170, 200)
local BUTTON_TEXT = Color3.fromRGB(14, 16, 20)
local BUTTON_DEAD = Color3.fromRGB(36, 38, 46)
local BUTTON_DEAD_TEXT = Color3.fromRGB(104, 108, 118)
local SELL_COLOR = Color3.fromRGB(150, 90, 90)

local SPEED_COLOR = Color3.fromRGB(240, 238, 230)
local SPEED_STROKE = Color3.fromRGB(20, 18, 14)

local VehicleUI = {}
VehicleUI.__index = VehicleUI

type Row = {
	frame: Frame,
	nameLabel: TextLabel,
	statusLabel: TextLabel,
	button: TextButton,
}

export type VehicleUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		list: Frame,
		rows: { [string]: Row },
		storeButton: TextButton,
		speedGui: ScreenGui,
		speedLabel: TextLabel,
		onBuy: ((string) -> ())?,
		onSell: ((string) -> ())?,
		onSpawn: ((string) -> ())?,
		onStore: (() -> ())?,
		seatConnection: RBXScriptConnection?,
		renderConnection: RBXScriptConnection?,
	},
	VehicleUI
))

local function buildRow(parent: Instance, order: number): Row
	local frame = Instance.new("Frame")
	frame.Name = "Row"
	frame.Size = UDim2.new(1, 0, 0, 40)
	frame.BackgroundColor3 = ROW_COLOR
	frame.BorderSizePixel = 0
	frame.LayoutOrder = order
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = frame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, -96, 0, 18)
	nameLabel.Position = UDim2.new(0, 0, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 13
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = NAME_COLOR
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = frame

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -96, 0, 14)
	statusLabel.Position = UDim2.new(0, 0, 0, 21)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 11
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextColor3 = PRICE_COLOR
	statusLabel.Parent = frame

	local button = Instance.new("TextButton")
	button.Name = "Action"
	button.Size = UDim2.new(0, 84, 0, 28)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, 0, 0.5, 0)
	button.BackgroundColor3 = ACCENT_COLOR
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 12
	button.TextColor3 = BUTTON_TEXT
	button.Text = "BUY"
	button.Parent = frame

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = button

	return { frame = frame, nameLabel = nameLabel, statusLabel = statusLabel, button = button }
end

function VehicleUI.new(): VehicleUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesVehicles"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 2
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "VehiclePanel"
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UDim2.new(0, 16, 0, 16)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = panel

	local outer = Instance.new("UIListLayout")
	outer.SortOrder = Enum.SortOrder.LayoutOrder
	outer.Padding = UDim.new(0, 8)
	outer.Parent = panel

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 16
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = TITLE_COLOR
	titleLabel.Text = "AUTOPIA SHOWROOM"
	titleLabel.LayoutOrder = 0
	titleLabel.Parent = panel

	local noticeLabel = Instance.new("TextLabel")
	noticeLabel.Name = "Notice"
	noticeLabel.Size = UDim2.new(1, 0, 0, 0)
	noticeLabel.AutomaticSize = Enum.AutomaticSize.Y
	noticeLabel.BackgroundTransparency = 1
	noticeLabel.Font = Enum.Font.GothamMedium
	noticeLabel.TextSize = 12
	noticeLabel.TextWrapped = true
	noticeLabel.TextXAlignment = Enum.TextXAlignment.Left
	noticeLabel.TextColor3 = CAPTION_COLOR
	noticeLabel.Text = ""
	noticeLabel.Visible = false
	noticeLabel.LayoutOrder = 1
	noticeLabel.Parent = panel

	local list = Instance.new("Frame")
	list.Name = "List"
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.LayoutOrder = 2
	list.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = list

	local storeButton = Instance.new("TextButton")
	storeButton.Name = "Store"
	storeButton.Size = UDim2.new(1, 0, 0, 30)
	storeButton.BackgroundColor3 = SELL_COLOR
	storeButton.BorderSizePixel = 0
	storeButton.AutoButtonColor = false
	storeButton.Font = Enum.Font.GothamBold
	storeButton.TextSize = 13
	storeButton.TextColor3 = Color3.fromRGB(20, 20, 20)
	storeButton.Text = "PARK THE ACTIVE CAR"
	storeButton.Visible = false
	storeButton.LayoutOrder = 3
	storeButton.Parent = panel

	local storeCorner = Instance.new("UICorner")
	storeCorner.CornerRadius = UDim.new(0, 8)
	storeCorner.Parent = storeButton

	-- The speedometer, its own ScreenGui so it can sit low-centre while the
	-- showroom stays top-left -- the two are read at completely different
	-- moments and have no reason to share a container.
	local speedGui = Instance.new("ScreenGui")
	speedGui.Name = "AgesSpeedometer"
	speedGui.ResetOnSpawn = false
	speedGui.IgnoreGuiInset = true
	speedGui.DisplayOrder = 2
	speedGui.Parent = playerGui

	local speedLabel = Instance.new("TextLabel")
	speedLabel.Name = "Speed"
	speedLabel.AnchorPoint = Vector2.new(0.5, 1)
	speedLabel.Position = UDim2.new(0.5, 0, 1, -28)
	speedLabel.Size = UDim2.new(0, 160, 0, 40)
	speedLabel.BackgroundTransparency = 1
	speedLabel.Font = Enum.Font.GothamBold
	speedLabel.TextSize = 28
	speedLabel.TextColor3 = SPEED_COLOR
	speedLabel.Text = ""
	speedLabel.Visible = false
	speedLabel.Parent = speedGui

	local speedStroke = Instance.new("UIStroke")
	speedStroke.Color = SPEED_STROKE
	speedStroke.Thickness = 2
	speedStroke.Parent = speedLabel

	local self = setmetatable({
		screenGui = screenGui,
		panel = panel,
		list = list,
		rows = {} :: { [string]: Row },
		storeButton = storeButton,
		speedGui = speedGui,
		speedLabel = speedLabel,
		onBuy = nil,
		onSell = nil,
		onSpawn = nil,
		onStore = nil,
		seatConnection = nil,
		renderConnection = nil,
	}, VehicleUI) :: VehicleUIHandle

	storeButton.MouseButton1Click:Connect(function()
		local handler = self.onStore
		if handler ~= nil then
			handler()
		end
	end)

	-- The speedometer watches the local character's own seat, independently of
	-- anything the server pushes -- it is a fact about which part the humanoid
	-- is sitting in, not about who owns what, so there is nothing to wait on a
	-- remote for.
	local function watchCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid == nil or not humanoid:IsA("Humanoid") then
			return
		end
		local existing = self.seatConnection
		if existing ~= nil then
			existing:Disconnect()
		end
		self.seatConnection = humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			local seatPart = humanoid.SeatPart
			local renderExisting = self.renderConnection
			if renderExisting ~= nil then
				renderExisting:Disconnect()
				self.renderConnection = nil
			end
			if seatPart == nil or not seatPart:IsA("VehicleSeat") then
				speedLabel.Visible = false
				return
			end
			speedLabel.Visible = true
			self.renderConnection = RunService.RenderStepped:Connect(function()
				if seatPart.Parent == nil then
					speedLabel.Text = ""
					return
				end
				local studsPerSecond = seatPart.AssemblyLinearVelocity.Magnitude
				-- Studs read as roughly a yard, so this is shown as "mph" the
				-- way every other Roblox driving game does -- a raw stud figure
				-- would mean nothing to a player and a truly converted unit
				-- would mean claiming a precision this chassis was never tuned
				-- to deliver.
				speedLabel.Text = string.format("%d mph", math.floor(studsPerSecond * 0.68))
			end)
		end)
	end

	if player.Character ~= nil then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	return self
end

function VehicleUI.OnBuy(self: VehicleUIHandle, handler: (string) -> ())
	self.onBuy = handler
end

function VehicleUI.OnSell(self: VehicleUIHandle, handler: (string) -> ())
	self.onSell = handler
end

function VehicleUI.OnSpawn(self: VehicleUIHandle, handler: (string) -> ())
	self.onSpawn = handler
end

function VehicleUI.OnStore(self: VehicleUIHandle, handler: () -> ())
	self.onStore = handler
end

function VehicleUI.Set(self: VehicleUIHandle, state: VehicleState?)
	if state == nil then
		self.panel.Visible = false
		return
	end
	self.panel.Visible = true

	local noticeLabel = self.panel:FindFirstChild("Notice") :: TextLabel
	if state.notice ~= nil and state.notice ~= "" then
		noticeLabel.Text = state.notice
		noticeLabel.Visible = true
	else
		noticeLabel.Visible = false
	end

	local seen: { [string]: boolean } = {}
	for order, kind in state.catalog do
		seen[kind.id] = true
		local row = self.rows[kind.id]
		if row == nil then
			row = buildRow(self.list, order)
			self.rows[kind.id] = row
		end
		row.frame.LayoutOrder = order
		row.nameLabel.Text = kind.name

		local owned = state.owned[kind.id] == true
		local active = state.active == kind.id

		if active then
			row.frame.BackgroundColor3 = ROW_ACTIVE_COLOR
			row.statusLabel.Text = "Out front, driving now"
			row.button.Text = if state.busy then "..." else "SELL"
			row.button.BackgroundColor3 = if state.busy then BUTTON_DEAD else SELL_COLOR
			row.button.TextColor3 = if state.busy then BUTTON_DEAD_TEXT else BUTTON_TEXT
			row.button.Enabled = not state.busy
		elseif owned then
			row.frame.BackgroundColor3 = ROW_COLOR
			row.statusLabel.Text = "In the garage"
			row.button.Text = if state.busy then "..." else "DRIVE"
			row.button.BackgroundColor3 = if state.busy then BUTTON_DEAD else ACCENT_COLOR
			row.button.TextColor3 = if state.busy then BUTTON_DEAD_TEXT else BUTTON_TEXT
			row.button.Enabled = not state.busy
		else
			row.frame.BackgroundColor3 = ROW_COLOR
			row.statusLabel.Text = Money.Format(kind.price)
			row.button.Text = "BUY"
			row.button.BackgroundColor3 = ACCENT_COLOR
			row.button.TextColor3 = BUTTON_TEXT
			row.button.Enabled = true
		end

		-- One connection per row, replaced rather than stacked: `Set` is
		-- called on every push, and a row that lived across several pushes
		-- would otherwise fire its buy handler once per push it has survived.
		local existing = (row :: any).clickConnection
		if existing ~= nil then
			(existing :: RBXScriptConnection):Disconnect()
		end
		local vehicleId = kind.id
		local wasActive = active
		local wasOwned = owned
		;(row :: any).clickConnection = row.button.MouseButton1Click:Connect(function()
			if wasActive then
				local handler = self.onSell
				if handler ~= nil then
					handler(vehicleId)
				end
			elseif wasOwned then
				local handler = self.onSpawn
				if handler ~= nil then
					handler(vehicleId)
				end
			else
				local handler = self.onBuy
				if handler ~= nil then
					handler(vehicleId)
				end
			end
		end)
	end

	for id, row in self.rows do
		if not seen[id] then
			row.frame:Destroy()
			self.rows[id] = nil
		end
	end

	self.storeButton.Visible = state.active ~= nil
end

return VehicleUI
