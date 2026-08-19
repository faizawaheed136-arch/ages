--!strict
-- The dealership queue panel. Customers waiting at the counter, a serve button,
-- and the greeting from the front customer.
--
-- Bottom left, the corner every activity surface takes. It sits below HouseUI and
-- beside TillUI because they are all things you are doing at a counter, not readings
-- you glance at from across the street. The panel cannot collide with any of them
-- because a player is never serving at a dealership and standing at a till at once.
--
-- The queue bar is the whole of the read. It fills as customers arrive and empties
-- as they are served. A player who wants to know when the next customer is at the
-- front has to watch the bar rather than a number, because the bar is the one thing
-- that tells them whether they should walk over or keep walking.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Types"))

type CarDealerState = Types.CarDealerState

local PANEL_WIDTH = 300

local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local CAPTION_COLOR = Color3.fromRGB(146, 150, 162)
local TRACK_COLOR = Color3.fromRGB(38, 39, 46)

-- The queue bar. Blue rather than green: green is health and smarts, and a queue
-- that shares a colour with a stat bar would be a number the player reads as a score
-- rather than as a count of people.
local QUEUE_COLOR = Color3.fromRGB(110, 160, 220)

local BUTTON_ACTIVE = Color3.fromRGB(225, 190, 90)
local BUTTON_TEXT = Color3.fromRGB(20, 20, 24)
local BUTTON_DEAD = Color3.fromRGB(32, 34, 40)
local BUTTON_DEAD_TEXT = Color3.fromRGB(104, 108, 118)

local CarDealerUI = {}
CarDealerUI.__index = CarDealerUI

export type CarDealerUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		titleLabel: TextLabel,
		queueTrack: Frame,
		queueFill: Frame,
		greetingLabel: TextLabel,
		button: TextButton,
		noticeLabel: TextLabel,
		onServe: (() -> ())?,
	},
	CarDealerUI
))

function CarDealerUI.new(): CarDealerUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesCarDealer"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 2
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "CarDealerPanel"
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
	titleLabel.Text = "AUTOPIA"
	titleLabel.LayoutOrder = 0
	titleLabel.Parent = panel

	local queueTrack = Instance.new("Frame")
	queueTrack.Name = "QueueTrack"
	queueTrack.Size = UDim2.new(1, 0, 0, 8)
	queueTrack.BackgroundColor3 = TRACK_COLOR
	queueTrack.BorderSizePixel = 0
	queueTrack.LayoutOrder = 1
	queueTrack.Parent = panel

	local queueFill = Instance.new("Frame")
	queueFill.Name = "QueueFill"
	queueFill.Size = UDim2.new(0, 0, 1, 0)
	queueFill.BackgroundColor3 = QUEUE_COLOR
	queueFill.BorderSizePixel = 0
	queueFill.Parent = queueTrack

	local queueLabel = Instance.new("TextLabel")
	queueLabel.Name = "QueueLabel"
	queueLabel.Size = UDim2.new(1, 0, 0, 14)
	queueLabel.BackgroundTransparency = 1
	queueLabel.Font = Enum.Font.Gotham
	queueLabel.TextSize = 11
	queueLabel.TextXAlignment = Enum.TextXAlignment.Left
	queueLabel.TextColor3 = CAPTION_COLOR
	queueLabel.Text = "0 customers waiting"
	queueLabel.LayoutOrder = 2
	queueLabel.Parent = panel

	local greetingLabel = Instance.new("TextLabel")
	greetingLabel.Name = "Greeting"
	greetingLabel.Size = UDim2.new(1, 0, 0, 0)
	greetingLabel.AutomaticSize = Enum.AutomaticSize.Y
	greetingLabel.BackgroundTransparency = 1
	-- Enum.Font has no italic Gotham -- same note as StatsUI's near-miss label. The
	-- quieter reading this wanted is already carried by the size and the dimmed colour.
	greetingLabel.Font = Enum.Font.Gotham
	greetingLabel.TextSize = 12
	greetingLabel.TextWrapped = true
	greetingLabel.TextXAlignment = Enum.TextXAlignment.Left
	greetingLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
	greetingLabel.Text = ""
	greetingLabel.Visible = false
	greetingLabel.LayoutOrder = 3
	greetingLabel.Parent = panel

	local button = Instance.new("TextButton")
	button.Name = "Serve"
	button.Size = UDim2.new(1, 0, 0, 36)
	button.BackgroundColor3 = BUTTON_DEAD
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.TextColor3 = BUTTON_DEAD_TEXT
	button.Text = "SERVE"
	button.LayoutOrder = 4
	button.Parent = panel

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = button

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
		queueTrack = queueTrack,
		queueFill = queueFill,
		greetingLabel = greetingLabel,
		button = button,
		noticeLabel = noticeLabel,
		onServe = nil,
	}, CarDealerUI) :: CarDealerUIHandle

	button.MouseButton1Click:Connect(function()
		local handler = self.onServe
		if handler ~= nil then
			handler()
		end
	end)

	return self
end

function CarDealerUI.OnServe(self: CarDealerUIHandle, handler: () -> ())
	self.onServe = handler
end

function CarDealerUI.Set(self: CarDealerUIHandle, state: CarDealerState?)
	if state == nil then
		self.panel.Visible = false
		return
	end

	self.panel.Visible = true

	local maxQueue = 3
	local share = math.clamp(state.waiting / maxQueue, 0, 1)
	self.queueFill.Size = UDim2.new(share, 0, 1, 0)
	self.queueLabel.Text = tostring(state.waiting) .. " customer" .. (state.waiting ~= 1 and "s" or "") .. " waiting"

	local greeting = state.greeting
	if greeting ~= nil and greeting ~= "" then
		self.greetingLabel.Text = '"' .. greeting .. '"'
		self.greetingLabel.Visible = true
	else
		self.greetingLabel.Visible = false
	end

	if state.waiting > 0 and not state.served then
		self.button.BackgroundColor3 = BUTTON_ACTIVE
		self.button.TextColor3 = BUTTON_TEXT
		self.button.Text = "SERVE"
		self.button.Enabled = true
	else
		self.button.BackgroundColor3 = BUTTON_DEAD
		self.button.TextColor3 = BUTTON_DEAD_TEXT
		self.button.Text = "SERVE"
		self.button.Enabled = false
	end

	self.noticeLabel.Visible = false
end

function CarDealerUI.Open(self: CarDealerUIHandle)
	self.panel.Visible = true
end

return CarDealerUI
