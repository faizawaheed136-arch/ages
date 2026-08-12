--!strict
-- The drawer you are standing at, drawn.
--
-- Bottom left, the corner every activity surface takes, and the same reason as always:
-- this is a place you are in, not a readout you glance at. It cannot collide with the lab,
-- the hunt or the easel, because all four are things you are doing and you are only ever
-- doing one.
--
-- **The two lamps are the panel, and what they are not is a warning.** They say where the
-- clerk and the camera are pointed right now -- nothing more. There is no countdown to the
-- next glance, no amber "about to turn", no pip that fills. That omission is the activity:
-- the clerk's shoulders and the camera's housing are both in the room, moving, and a
-- player who wants to know when the window closes has to watch them rather than watch
-- this. A panel that predicted the turn would reduce a thing you read to a thing you
-- react to, and there is already a reaction test in the gym.
--
-- What the lamps *are* for is the moment after. When a hold goes wrong the player needs to
-- know which of the two caught them, because the two are learned separately -- the clerk is
-- a short beat you can nearly count and the camera is a long sweep you have to look up at
-- -- and a robbery that just said "seen" would teach neither.
--
-- The TAKE button is held, not pressed, and it is the only held control in the game. That
-- is worth one line of justification: every other verb here is a commitment you make and
-- live with, and this one is a commitment you are making continuously and can withdraw
-- from in half a second. Holding is the only input that means that.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage:WaitForChild("Types"))

type TheftState = Types.TheftState

local PANEL_WIDTH = 300

local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local CAPTION_COLOR = Color3.fromRGB(146, 150, 162)
local TRACK_COLOR = Color3.fromRGB(38, 39, 46)

-- The drawer, which drains. Green rather than gold: gold in this game means "go here",
-- and a bar the same colour as every destination marker would be the one place the palette
-- lied.
local CASH_COLOR = Color3.fromRGB(120, 186, 132)

-- The lamps. Dark when the attention is elsewhere, red when it is on the till -- the same
-- red as the camera's own lens across the room, the heat bar's border and the search ring,
-- because all four mean the identical thing and a player should learn that colour once.
local LAMP_IDLE = Color3.fromRGB(46, 48, 56)
local LAMP_LIVE = Color3.fromRGB(226, 78, 74)
local LAMP_IDLE_TEXT = Color3.fromRGB(120, 124, 134)
local LAMP_LIVE_TEXT = Color3.fromRGB(255, 240, 238)

local BUTTON_IDLE = Color3.fromRGB(58, 62, 72)
local BUTTON_HELD = Color3.fromRGB(196, 88, 74)
local BUTTON_TEXT = Color3.fromRGB(245, 246, 250)

local SPOTTED_COLOR = Color3.fromRGB(226, 78, 74)

local TillUI = {}
TillUI.__index = TillUI

export type TillUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		titleLabel: TextLabel,
		track: Frame,
		fill: Frame,
		takenLabel: TextLabel,
		clerkLamp: TextLabel,
		cameraLamp: TextLabel,
		button: TextButton,
		noticeLabel: TextLabel,
		-- What the client last told the server. Held so that a release is only ever sent
		-- once -- the button raises both a mouse-up and an input-ended on a desktop, and
		-- two "hands out" messages for one release is one message the server has to be
		-- built to ignore.
		holding: boolean,
		onHold: ((holding: boolean) -> ())?,
	},
	TillUI
))

local function makeLamp(parent: Instance, order: number, text: string): TextLabel
	local lamp = Instance.new("TextLabel")
	lamp.Name = text
	lamp.Size = UDim2.new(0.5, -3, 1, 0)
	lamp.Position = UDim2.new(if order == 0 then 0 else 0.5, if order == 0 then 0 else 3, 0, 0)
	lamp.BackgroundColor3 = LAMP_IDLE
	lamp.BorderSizePixel = 0
	lamp.Font = Enum.Font.GothamBold
	lamp.TextSize = 12
	lamp.TextColor3 = LAMP_IDLE_TEXT
	lamp.Text = text
	lamp.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = lamp

	return lamp
end

local function setLamp(lamp: TextLabel, live: boolean)
	lamp.BackgroundColor3 = if live then LAMP_LIVE else LAMP_IDLE
	lamp.TextColor3 = if live then LAMP_LIVE_TEXT else LAMP_IDLE_TEXT
end

function TillUI.new(): TillUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesTill"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 2
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "TillPanel"
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
	titleLabel.Text = ""
	titleLabel.LayoutOrder = 0
	titleLabel.Parent = panel

	local track = Instance.new("Frame")
	track.Name = "Drawer"
	track.Size = UDim2.new(1, 0, 0, 6)
	track.BackgroundColor3 = TRACK_COLOR
	track.BorderSizePixel = 0
	track.LayoutOrder = 1
	track.Parent = panel

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = CASH_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track

	local takenLabel = Instance.new("TextLabel")
	takenLabel.Name = "Taken"
	takenLabel.Size = UDim2.new(1, 0, 0, 16)
	takenLabel.BackgroundTransparency = 1
	takenLabel.Font = Enum.Font.Gotham
	takenLabel.TextSize = 12
	takenLabel.TextXAlignment = Enum.TextXAlignment.Left
	takenLabel.TextColor3 = CAPTION_COLOR
	takenLabel.Text = ""
	takenLabel.LayoutOrder = 2
	takenLabel.Parent = panel

	local lamps = Instance.new("Frame")
	lamps.Name = "Lamps"
	lamps.Size = UDim2.new(1, 0, 0, 24)
	lamps.BackgroundTransparency = 1
	lamps.LayoutOrder = 3
	lamps.Parent = panel

	local clerkLamp = makeLamp(lamps, 0, "CLERK")
	local cameraLamp = makeLamp(lamps, 1, "CAMERA")

	local button = Instance.new("TextButton")
	button.Name = "Take"
	button.Size = UDim2.new(1, 0, 0, 40)
	button.BackgroundColor3 = BUTTON_IDLE
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextColor3 = BUTTON_TEXT
	button.Text = "HOLD TO TAKE"
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
	noticeLabel.TextSize = 13
	noticeLabel.TextWrapped = true
	noticeLabel.TextXAlignment = Enum.TextXAlignment.Left
	noticeLabel.TextColor3 = SPOTTED_COLOR
	noticeLabel.Text = ""
	noticeLabel.Visible = false
	noticeLabel.LayoutOrder = 5
	noticeLabel.Parent = panel

	local self = setmetatable({
		screenGui = screenGui,
		panel = panel,
		titleLabel = titleLabel,
		track = track,
		fill = fill,
		takenLabel = takenLabel,
		clerkLamp = clerkLamp,
		cameraLamp = cameraLamp,
		button = button,
		noticeLabel = noticeLabel,
		holding = false,
		onHold = nil,
	}, TillUI) :: TillUIHandle

	local function setHolding(holding: boolean)
		if self.holding == holding then
			return
		end
		self.holding = holding
		self.button.BackgroundColor3 = if holding then BUTTON_HELD else BUTTON_IDLE
		self.button.Text = if holding then "TAKING -- LET GO" else "HOLD TO TAKE"
		local handler = self.onHold
		if handler ~= nil then
			handler(holding)
		end
	end

	-- Both input paths, because the two devices raise different events and a robbery that
	-- only worked with a mouse would be a robbery most of this game's players cannot do.
	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			setHolding(true)
		end
	end)

	button.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			setHolding(false)
		end
	end)

	-- A release that happened somewhere else entirely: the player dragged off the button
	-- before letting go, or the window lost focus mid-hold. Without this the hands stay in
	-- the drawer with nothing on screen saying so, which is the worst possible way to lose
	-- a life's savings.
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			setHolding(false)
		end
	end)

	UserInputService.WindowFocusReleased:Connect(function()
		setHolding(false)
	end)

	return self
end

function TillUI.OnHold(self: TillUIHandle, handler: (holding: boolean) -> ())
	self.onHold = handler
end

-- The whole panel from one snapshot. Nil takes it down and, importantly, lets go: a panel
-- that vanished while the server still believed the hands were in the drawer would be a
-- robbery continuing off screen.
function TillUI.Set(self: TillUIHandle, state: TheftState?)
	if state == nil then
		self.panel.Visible = false
		if self.holding then
			self.holding = false
			self.button.BackgroundColor3 = BUTTON_IDLE
			self.button.Text = "HOLD TO TAKE"
		end
		return
	end

	self.panel.Visible = true
	self.titleLabel.Text = state.place

	local share = if state.tillFull > 0 then state.tillLeft / state.tillFull else 0
	self.fill.Size = UDim2.new(math.clamp(share, 0, 1), 0, 1, 0)

	-- Rounded down to the whole unit. The drawer drains continuously and a figure ticking
	-- through cents is a number the player watches instead of watching the room, which is
	-- the one thing this activity cannot afford.
	self.takenLabel.Text = `${math.floor(state.taken)} taken -- ${math.floor(state.tillLeft)} left in the drawer`

	setLamp(self.clerkLamp, state.clerkWatching)
	setLamp(self.cameraLamp, state.cameraWatching)

	-- The server's word on whether the hands are actually in it, which can differ from the
	-- button: walking out of reach, an empty drawer or a death all take them out without
	-- anybody letting go. Following the server rather than the button is what stops the
	-- panel insisting on a robbery that has already stopped.
	if not state.holding and self.holding then
		self.holding = false
		self.button.BackgroundColor3 = BUTTON_IDLE
		self.button.Text = "HOLD TO TAKE"
	end

	local notice = state.notice
	self.noticeLabel.Visible = notice ~= nil
	self.noticeLabel.Text = notice or ""
	self.noticeLabel.TextColor3 = if state.spotted then SPOTTED_COLOR else CAPTION_COLOR
end

return TillUI
