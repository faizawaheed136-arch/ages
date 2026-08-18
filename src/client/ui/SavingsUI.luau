--!strict
-- The savings panel. Deposit, withdraw, and a running balance that grows on its
-- own. Bottom left, the corner every activity surface takes. It sits below
-- CarDealerUI and beside HouseUI because they are all things you do at a counter,
-- not readings you glance at from across the street.
--
-- The panel is simple by design: three buttons (deposit all, deposit half,
-- withdraw all) and a balance readout. The server validates every transaction
-- and pushes a full snapshot back, so the client never guesses at the number.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Types"))

type SavingsState = Types.SavingsState

local PANEL_WIDTH = 300

local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local BALANCE_COLOR = Color3.fromRGB(225, 205, 130)
local CAPTION_COLOR = Color3.fromRGB(146, 150, 162)
local TRACK_COLOR = Color3.fromRGB(38, 39, 46)
local ACTION_COLOR = Color3.fromRGB(80, 140, 220)
local ACTION_TEXT = Color3.fromRGB(255, 255, 255)
local WITHDRAW_COLOR = Color3.fromRGB(226, 140, 78)
local WITHDRAW_TEXT = Color3.fromRGB(255, 240, 238)

local SavingsUI = {}
SavingsUI.__index = SavingsUI

export type SavingsUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		titleLabel: TextLabel,
		balanceLabel: TextLabel,
		balanceTrack: Frame,
		balanceFill: Frame,
		balanceCaption: TextLabel,
		depositAllBtn: TextButton,
		depositHalfBtn: TextButton,
		withdrawAllBtn: TextButton,
		noticeLabel: TextLabel,
		onDepositAll: (() -> ())?,
		onDepositHalf: (() -> ())?,
		onWithdrawAll: (() -> ())?,
	},
	SavingsUI
))

function SavingsUI.new(): SavingsUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesSavings"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 2
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "SavingsPanel"
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
	titleLabel.Text = "SAVINGS"
	titleLabel.LayoutOrder = 0
	titleLabel.Parent = panel

	local balanceLabel = Instance.new("TextLabel")
	balanceLabel.Name = "Balance"
	balanceLabel.Size = UDim2.new(1, 0, 0, 22)
	balanceLabel.BackgroundTransparency = 1
	balanceLabel.Font = Enum.Font.GothamBold
	balanceLabel.TextSize = 18
	balanceLabel.TextXAlignment = Enum.TextXAlignment.Left
	balanceLabel.TextColor3 = BALANCE_COLOR
	balanceLabel.Text = "$0"
	balanceLabel.LayoutOrder = 1
	balanceLabel.Parent = panel

	local balanceTrack = Instance.new("Frame")
	balanceTrack.Name = "BalanceTrack"
	balanceTrack.Size = UDim2.new(1, 0, 0, 6)
	balanceTrack.BackgroundColor3 = TRACK_COLOR
	balanceTrack.BorderSizePixel = 0
	balanceTrack.LayoutOrder = 2
	balanceTrack.Parent = panel

	local balanceFill = Instance.new("Frame")
	balanceFill.Name = "BalanceFill"
	balanceFill.Size = UDim2.new(0, 0, 1, 0)
	balanceFill.BackgroundColor3 = BALANCE_COLOR
	balanceFill.BorderSizePixel = 0
	balanceFill.Parent = balanceTrack

	local balanceCaption = Instance.new("TextLabel")
	balanceCaption.Name = "Caption"
	balanceCaption.Size = UDim2.new(1, 0, 0, 12)
	balanceCaption.BackgroundTransparency = 1
	balanceCaption.Font = Enum.Font.Gotham
	balanceCaption.TextSize = 10
	balanceCaption.TextXAlignment = Enum.TextXAlignment.Left
	balanceCaption.TextColor3 = CAPTION_COLOR
	balanceCaption.Text = "0 / 10000"
	balanceCaption.LayoutOrder = 3
	balanceCaption.Parent = panel

	local depositAllBtn = Instance.new("TextButton")
	depositAllBtn.Name = "DepositAll"
	depositAllBtn.Size = UDim2.new(1, 0, 0, 30)
	depositAllBtn.BackgroundColor3 = ACTION_COLOR
	depositAllBtn.BorderSizePixel = 0
	depositAllBtn.AutoButtonColor = false
	depositAllBtn.Font = Enum.Font.GothamBold
	depositAllBtn.TextSize = 12
	depositAllBtn.TextColor3 = ACTION_TEXT
	depositAllBtn.Text = "DEPOSIT ALL"
	depositAllBtn.LayoutOrder = 4
	depositAllBtn.Parent = panel

	local depositAllCorner = Instance.new("UICorner")
	depositAllCorner.CornerRadius = UDim.new(0, 5)
	depositAllCorner.Parent = depositAllBtn

	local depositHalfBtn = Instance.new("TextButton")
	depositHalfBtn.Name = "DepositHalf"
	depositHalfBtn.Size = UDim2.new(1, 0, 0, 30)
	depositHalfBtn.BackgroundColor3 = Color3.fromRGB(60, 110, 180)
	depositHalfBtn.BorderSizePixel = 0
	depositHalfBtn.AutoButtonColor = false
	depositHalfBtn.Font = Enum.Font.GothamBold
	depositHalfBtn.TextSize = 12
	depositHalfBtn.TextColor3 = Color3.fromRGB(220, 230, 255)
	depositHalfBtn.Text = "DEPOSIT HALF"
	depositHalfBtn.LayoutOrder = 5
	depositHalfBtn.Parent = panel

	local depositHalfCorner = Instance.new("UICorner")
	depositHalfCorner.CornerRadius = UDim.new(0, 5)
	depositHalfCorner.Parent = depositHalfBtn

	local withdrawAllBtn = Instance.new("TextButton")
	withdrawAllBtn.Name = "WithdrawAll"
	withdrawAllBtn.Size = UDim2.new(1, 0, 0, 30)
	withdrawAllBtn.BackgroundColor3 = WITHDRAW_COLOR
	withdrawAllBtn.BorderSizePixel = 0
	withdrawAllBtn.AutoButtonColor = false
	withdrawAllBtn.Font = Enum.Font.GothamBold
	withdrawAllBtn.TextSize = 12
	withdrawAllBtn.TextColor3 = WITHDRAW_TEXT
	withdrawAllBtn.Text = "WITHDRAW ALL"
	withdrawAllBtn.LayoutOrder = 6
	withdrawAllBtn.Parent = panel

	local withdrawAllCorner = Instance.new("UICorner")
	withdrawAllCorner.CornerRadius = UDim.new(0, 5)
	withdrawAllCorner.Parent = withdrawAllBtn

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
	noticeLabel.LayoutOrder = 7
	noticeLabel.Parent = panel

	local self = setmetatable({
		screenGui = screenGui,
		panel = panel,
		titleLabel = titleLabel,
		balanceLabel = balanceLabel,
		balanceTrack = balanceTrack,
		balanceFill = balanceFill,
		balanceCaption = balanceCaption,
		depositAllBtn = depositAllBtn,
		depositHalfBtn = depositHalfBtn,
		withdrawAllBtn = withdrawAllBtn,
		noticeLabel = noticeLabel,
		onDepositAll = nil,
		onDepositHalf = nil,
		onWithdrawAll = nil,
	}, SavingsUI) :: SavingsUIHandle

	depositAllBtn.MouseButton1Click:Connect(function()
		local handler = self.onDepositAll
		if handler ~= nil then
			handler()
		end
	end)

	depositHalfBtn.MouseButton1Click:Connect(function()
		local handler = self.onDepositHalf
		if handler ~= nil then
			handler()
		end
	end)

	withdrawAllBtn.MouseButton1Click:Connect(function()
		local handler = self.onWithdrawAll
		if handler ~= nil then
			handler()
		end
	end)

	return self
end

function SavingsUI.OnDepositAll(self: SavingsUIHandle, handler: () -> ())
	self.onDepositAll = handler
end

function SavingsUI.OnDepositHalf(self: SavingsUIHandle, handler: () -> ())
	self.onDepositHalf = handler
end

function SavingsUI.OnWithdrawAll(self: SavingsUIHandle, handler: () -> ())
	self.onWithdrawAll = handler
end

function SavingsUI.Set(self: SavingsUIHandle, state: SavingsState?)
	if state == nil then
		self.panel.Visible = false
		return
	end

	self.panel.Visible = true

	local balance = state.balance
	local maxBalance = state.maxBalance
	self.balanceLabel.Text = "$" .. tostring(balance)
	self.balanceCaption.Text = tostring(balance) .. " / " .. tostring(maxBalance)

	local share = math.clamp(balance / maxBalance, 0, 1)
	self.balanceFill.Size = UDim2.new(share, 0, 1, 0)

	self.noticeLabel.Visible = false
end

return SavingsUI
