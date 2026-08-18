--!strict
-- The property panel. Owned houses, available suburbs, and the jobs linked to them.
--
-- Bottom left, the corner every activity surface takes. It sits below TillUI and
-- beside BankUI because they are all things you are doing in a room, not readings
-- you glance at from across the street. The panel cannot collide with any of them
-- because a player is never buying a house and robbing a till at once.
--
-- The list is the whole of it. There is no button to "refresh" or "open shop" --
-- the server pushes the full table whenever anything changes, and the client just
-- redraws. A house that appears on the list is one you can interact with; one that
-- vanishes is one you no longer have. The only action that reaches the server is
-- a fire, and each fire carries an id the server bounds-checks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Types"))

type HouseState = Types.HouseState

local PANEL_WIDTH = 300

local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local SECTION_COLOR = Color3.fromRGB(146, 150, 162)
local CAPTION_COLOR = Color3.fromRGB(120, 124, 134)
local BUY_COLOR = Color3.fromRGB(90, 200, 120)
local BUY_TEXT = Color3.fromRGB(20, 40, 20)
local SELL_COLOR = Color3.fromRGB(226, 78, 74)
local SELL_TEXT = Color3.fromRGB(255, 240, 238)

local HouseUI = {}
HouseUI.__index = HouseUI

export type HouseUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		titleLabel: TextLabel,
		ownedSection: TextLabel,
		ownedList: Frame,
		availableSection: TextLabel,
		availableList: Frame,
		noticeLabel: TextLabel,
		onBuyHouse: ((houseId: string) -> ())?,
		onSellHouse: ((houseId: string) -> ())?,
		onSetHomeJob: ((houseId: string) -> ())?,
	},
	HouseUI
))

function HouseUI.new(): HouseUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesHouse"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 2
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "HousePanel"
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 16, 1, -16)
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

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = panel

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 16
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = TITLE_COLOR
	titleLabel.Text = "PROPERTIES"
	titleLabel.LayoutOrder = 0
	titleLabel.Parent = panel

	local ownedSection = Instance.new("TextLabel")
	ownedSection.Name = "OwnedSection"
	ownedSection.Size = UDim2.new(1, 0, 0, 14)
	ownedSection.BackgroundTransparency = 1
	ownedSection.Font = Enum.Font.GothamBold
	ownedSection.TextSize = 11
	ownedSection.TextXAlignment = Enum.TextXAlignment.Left
	ownedSection.TextColor3 = SECTION_COLOR
	ownedSection.Text = "OWNED"
	ownedSection.LayoutOrder = 1
	ownedSection.Parent = panel

	local ownedList = Instance.new("Frame")
	ownedList.Name = "OwnedList"
	ownedList.Size = UDim2.new(1, 0, 0, 0)
	ownedList.BackgroundTransparency = 1
	ownedList.LayoutOrder = 2
	ownedList.Parent = panel

	local ownedLayout = Instance.new("UIListLayout")
	ownedLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ownedLayout.Padding = UDim.new(0, 4)
	ownedLayout.Parent = ownedList

	local availableSection = Instance.new("TextLabel")
	availableSection.Name = "AvailableSection"
	availableSection.Size = UDim2.new(1, 0, 0, 14)
	availableSection.BackgroundTransparency = 1
	availableSection.Font = Enum.Font.GothamBold
	availableSection.TextSize = 11
	availableSection.TextXAlignment = Enum.TextXAlignment.Left
	availableSection.TextColor3 = SECTION_COLOR
	availableSection.Text = "AVAILABLE"
	availableSection.LayoutOrder = 3
	availableSection.Parent = panel

	local availableList = Instance.new("Frame")
	availableList.Name = "AvailableList"
	availableList.Size = UDim2.new(1, 0, 0, 0)
	availableList.BackgroundTransparency = 1
	availableList.LayoutOrder = 4
	availableList.Parent = panel

	local availableLayout = Instance.new("UIListLayout")
	availableLayout.SortOrder = Enum.SortOrder.LayoutOrder
	availableLayout.Padding = UDim.new(0, 4)
	availableLayout.Parent = availableList

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
	noticeLabel.LayoutOrder = 5
	noticeLabel.Parent = panel

	local self = setmetatable({
		screenGui = screenGui,
		panel = panel,
		titleLabel = titleLabel,
		ownedSection = ownedSection,
		ownedList = ownedList,
		availableSection = availableSection,
		availableList = availableList,
		noticeLabel = noticeLabel,
		onBuyHouse = nil,
		onSellHouse = nil,
	}, HouseUI) :: HouseUIHandle

	return self
end

function HouseUI.OnBuyHouse(self: HouseUIHandle, handler: (houseId: string) -> ())
	self.onBuyHouse = handler
end

function HouseUI.OnSellHouse(self: HouseUIHandle, handler: (houseId: string) -> ())
	self.onSellHouse = handler
end

function HouseUI.OnSetHomeJob(self: HouseUIHandle, handler: (houseId: string) -> ())
	self.onSetHomeJob = handler
end

function HouseUI.Set(self: HouseUIHandle, state: HouseState?)
	if state == nil then
		self.panel.Visible = false
		return
	end

	self.panel.Visible = true

	-- Clear old rows.
	for _, child in self.ownedList:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for _, child in self.availableList:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextButton") then
			child:Destroy()
		end
	end

	-- Owned houses.
	local ownedCount = 0
	for houseId, _ in state.owned do
		ownedCount = ownedCount + 1
	end

	if ownedCount > 0 then
		self.ownedSection.Text = "OWNED (" .. tostring(ownedCount) .. ")"
		self.ownedSection.Visible = true
		self.ownedList.Visible = true
		for houseId, _ in state.owned do
			local jobId = state.homeJob[houseId]
			local row = Instance.new("Frame")
			row.Name = "HouseRow"
			row.Size = UDim2.new(1, 0, 0, 28)
			row.BackgroundTransparency = 1
			row.Parent = self.ownedList

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "Name"
			nameLabel.Size = UDim2.new(1, -90, 1, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Enum.Font.GothamMedium
			nameLabel.TextSize = 13
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
			nameLabel.Text = houseId
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Parent = row

			local jobLabel = Instance.new("TextLabel")
			jobLabel.Name = "Job"
			jobLabel.Size = UDim2.new(1, -90, 0, 12)
			jobLabel.Position = UDim2.new(0, 0, 1, 2)
			jobLabel.BackgroundTransparency = 1
			jobLabel.Font = Enum.Font.Gotham
			jobLabel.TextSize = 10
			jobLabel.TextXAlignment = Enum.TextXAlignment.Left
			jobLabel.TextColor3 = CAPTION_COLOR
			jobLabel.Text = if jobId ~= nil and jobId ~= "" then "· " .. jobId else ""
			jobLabel.Parent = row

			local sellBtn = Instance.new("TextButton")
			sellBtn.Name = "Sell"
			sellBtn.Size = UDim2.new(0, 80, 1, 0)
			sellBtn.Position = UDim2.new(1, -80, 0, 0)
			sellBtn.BackgroundColor3 = SELL_COLOR
			sellBtn.BorderSizePixel = 0
			sellBtn.AutoButtonColor = false
			sellBtn.Font = Enum.Font.GothamBold
			sellBtn.TextSize = 11
			sellBtn.TextColor3 = SELL_TEXT
			sellBtn.Text = "SELL"
			sellBtn.Parent = row

			local sellCorner = Instance.new("UICorner")
			sellCorner.CornerRadius = UDim.new(0, 5)
			sellCorner.Parent = sellBtn

			sellBtn.MouseButton1Click:Connect(function()
				local handler = self.onSellHouse
				if handler ~= nil then
					handler(houseId)
				end
			end)

			-- LINK button: appears when no job is attached, lets the player
			-- bind a work-from-home job to this house. The server validates
			-- that the job's placeId actually points at this house.
			if jobId == nil or jobId == "" then
				local linkBtn = Instance.new("TextButton")
				linkBtn.Name = "Link"
				linkBtn.Size = UDim2.new(0, 80, 1, 0)
				linkBtn.Position = UDim2.new(1, -80, 0, 0)
				linkBtn.BackgroundColor3 = Color3.fromRGB(80, 140, 220)
				linkBtn.BorderSizePixel = 0
				linkBtn.AutoButtonColor = false
				linkBtn.Font = Enum.Font.GothamBold
				linkBtn.TextSize = 11
				linkBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
				linkBtn.Text = "LINK"
				linkBtn.Parent = row

				local linkCorner = Instance.new("UICorner")
				linkCorner.CornerRadius = UDim.new(0, 5)
				linkCorner.Parent = linkBtn

				linkBtn.MouseButton1Click:Connect(function()
					local handler = self.onSetHomeJob
					if handler ~= nil then
						handler(houseId)
					end
				end)
			end
		end
	else
		self.ownedSection.Text = "OWNED"
		self.ownedSection.Visible = false
		self.ownedList.Visible = false
	end

	-- Available houses.
	local availCount = 0
	for _ in state.available do
		availCount = availCount + 1
	end

	if availCount > 0 then
		self.availableSection.Text = "AVAILABLE (" .. tostring(availCount) .. ")"
		self.availableSection.Visible = true
		self.availableList.Visible = true
		for houseId, price in state.available do
			local row = Instance.new("Frame")
			row.Name = "HouseRow"
			row.Size = UDim2.new(1, 0, 0, 28)
			row.BackgroundTransparency = 1
			row.Parent = self.availableList

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "Name"
			nameLabel.Size = UDim2.new(1, -90, 1, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Enum.Font.GothamMedium
			nameLabel.TextSize = 13
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
			nameLabel.Text = houseId
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Parent = row

			local priceLabel = Instance.new("TextLabel")
			priceLabel.Name = "Price"
			priceLabel.Size = UDim2.new(0, 70, 1, 0)
			priceLabel.Position = UDim2.new(1, -70, 0, 0)
			priceLabel.BackgroundTransparency = 1
			priceLabel.Font = Enum.Font.GothamBold
			priceLabel.TextSize = 12
			priceLabel.TextXAlignment = Enum.TextXAlignment.Right
			priceLabel.TextColor3 = Color3.fromRGB(225, 205, 130)
			priceLabel.Text = "$" .. tostring(price)
			priceLabel.Parent = row

			local buyBtn = Instance.new("TextButton")
			buyBtn.Name = "Buy"
			buyBtn.Size = UDim2.new(0, 80, 1, 0)
			buyBtn.Position = UDim2.new(1, -80, 0, 0)
			buyBtn.BackgroundColor3 = BUY_COLOR
			buyBtn.BorderSizePixel = 0
			buyBtn.AutoButtonColor = false
			buyBtn.Font = Enum.Font.GothamBold
			buyBtn.TextSize = 11
			buyBtn.TextColor3 = BUY_TEXT
			buyBtn.Text = "BUY"
			buyBtn.Parent = row

			local buyCorner = Instance.new("UICorner")
			buyCorner.CornerRadius = UDim.new(0, 5)
			buyCorner.Parent = buyBtn

			buyBtn.MouseButton1Click:Connect(function()
				local handler = self.onBuyHouse
				if handler ~= nil then
					handler(houseId)
				end
			end)
		end
	else
		self.availableSection.Text = "AVAILABLE"
		self.availableSection.Visible = false
		self.availableList.Visible = false
	end

	self.noticeLabel.Visible = false
end

return HouseUI
