--!strict
-- The bank you are standing in, drawn.
--
-- Bottom left, the corner every activity surface takes, and it cannot collide with the
-- till's because a player is never in a shop and a bank at once.
--
-- **One button, and what it says depends on where you are standing.** That is the whole
-- design of this panel and it is not a saving of space -- it is the activity restated in
-- the interface. The room has two controls forty-eight studs apart and the player can only
-- ever have their hands on one of them, so a panel with two buttons on it would be a panel
-- offering a choice the floor has already made. Between the two it says so and goes dead,
-- because those thirty studs of carpet are a real part of this activity and a live button
-- during them would be the panel pretending otherwise.
--
-- **The alarm's clock is on screen, and the till's deliberately is not.** That looks like
-- an inconsistency between two sibling panels and it is the difference between the two
-- rooms. A shop asks you to read a clerk's shoulders and a camera housing moving in the
-- world; putting a countdown on the HUD there would play the activity for you. A bank has
-- already told you everything -- there is a bell going and a lamp flashing forty-eight
-- studs away -- and the only question left is how much of the clock you will spend. Hiding
-- a number the room is screaming would be coy rather than skilful.
--
-- Everything on it is shared. The vault bar, the alarm and the guard are one set of facts
-- about a room, so two players robbing one bank are reading the same panel -- which is what
-- makes a partner a partner rather than a duplicate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage:WaitForChild("Types"))

type BankState = Types.BankState

local PANEL_WIDTH = 300

local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local CAPTION_COLOR = Color3.fromRGB(146, 150, 162)
local TRACK_COLOR = Color3.fromRGB(38, 39, 46)

-- The vault, which drains. The same green the till's drawer takes, because it is the same
-- fact about the same kind of thing and a second colour would be a second thing to learn.
local CASH_COLOR = Color3.fromRGB(120, 186, 132)

-- The three states of the room, in the palette this game has been using since the heat bar.
-- Red is "you are being seen" and it is the same red as the camera lens, the search ring and
-- the alarm lamp across the room. Amber is "in progress and not yet true" -- the hideout
-- mark's counting colour -- which is exactly what a silenced alarm is.
local IDLE_COLOR = Color3.fromRGB(46, 48, 56)
local IDLE_TEXT = Color3.fromRGB(120, 124, 134)
local LIVE_COLOR = Color3.fromRGB(226, 78, 74)
local LIVE_TEXT = Color3.fromRGB(255, 240, 238)
local WAITING_COLOR = Color3.fromRGB(238, 176, 74)
local WAITING_TEXT = Color3.fromRGB(38, 30, 12)

local BUTTON_IDLE = Color3.fromRGB(58, 62, 72)
local BUTTON_HELD = Color3.fromRGB(196, 88, 74)
local BUTTON_DEAD = Color3.fromRGB(32, 34, 40)
local BUTTON_TEXT = Color3.fromRGB(245, 246, 250)
local BUTTON_DEAD_TEXT = Color3.fromRGB(104, 108, 118)

local BankUI = {}
BankUI.__index = BankUI

export type BankUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		titleLabel: TextLabel,
		fill: Frame,
		takenLabel: TextLabel,
		alarmLamp: TextLabel,
		guardLamp: TextLabel,
		silenceTrack: Frame,
		silenceFill: Frame,
		button: TextButton,
		noticeLabel: TextLabel,
		-- What the client last told the server. Held so a release is only ever sent once --
		-- the button raises both a mouse-up and an input-ended on a desktop, and two "hands
		-- off" messages for one release is one the server has to be built to ignore.
		holding: boolean,
		-- Whether there is anything within reach to put hands on. Checked before a press is
		-- sent rather than left to the server to refuse, so that the dead stretch between the
		-- vault and the panel is dead on screen too.
		canHold: boolean,
		-- What the button would do if pressed right now, so a release drawn after the player
		-- has walked away still repaints the right words.
		verb: string,
		onHold: ((holding: boolean) -> ())?,
	},
	BankUI
))

-- The button, repainted from the three facts that decide it: whether there is anything in
-- reach, what it would do, and whether it is being held.
--
-- Module level rather than a closure inside `new`, because both the input handlers and the
-- server snapshot repaint it and the two have to agree exactly. When this was written twice
-- -- once in each -- the copies drifted on the dead state within an hour of being written.
local function paintButton(self: BankUIHandle)
	if not self.canHold then
		self.button.BackgroundColor3 = BUTTON_DEAD
		self.button.TextColor3 = BUTTON_DEAD_TEXT
		self.button.Text = self.verb
		return
	end
	self.button.TextColor3 = BUTTON_TEXT
	self.button.BackgroundColor3 = if self.holding then BUTTON_HELD else BUTTON_IDLE
	self.button.Text = if self.holding then "LET GO" else self.verb
end

local function makeLamp(parent: Instance, name: string, order: number): TextLabel
	local lamp = Instance.new("TextLabel")
	lamp.Name = name
	lamp.Size = UDim2.new(1, 0, 0, 22)
	lamp.BackgroundColor3 = IDLE_COLOR
	lamp.BorderSizePixel = 0
	lamp.Font = Enum.Font.GothamBold
	lamp.TextSize = 12
	lamp.TextColor3 = IDLE_TEXT
	lamp.Text = ""
	lamp.LayoutOrder = order
	lamp.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = lamp

	return lamp
end

local function setLamp(lamp: TextLabel, text: string, state: string)
	lamp.Text = text
	if state == "live" then
		lamp.BackgroundColor3 = LIVE_COLOR
		lamp.TextColor3 = LIVE_TEXT
	elseif state == "waiting" then
		lamp.BackgroundColor3 = WAITING_COLOR
		lamp.TextColor3 = WAITING_TEXT
	else
		lamp.BackgroundColor3 = IDLE_COLOR
		lamp.TextColor3 = IDLE_TEXT
	end
end

function BankUI.new(): BankUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesBank"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 2
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "BankPanel"
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
	track.Name = "Vault"
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

	local alarmLamp = makeLamp(panel, "Alarm", 3)
	local guardLamp = makeLamp(panel, "Guard", 4)

	-- Only up while a silence is being held. A permanently visible empty bar would read as
	-- a second thing draining alongside the vault, which is the one misreading that would
	-- make a player let go at the wrong moment.
	local silenceTrack = Instance.new("Frame")
	silenceTrack.Name = "Silence"
	silenceTrack.Size = UDim2.new(1, 0, 0, 6)
	silenceTrack.BackgroundColor3 = TRACK_COLOR
	silenceTrack.BorderSizePixel = 0
	silenceTrack.Visible = false
	silenceTrack.LayoutOrder = 5
	silenceTrack.Parent = panel

	local silenceFill = Instance.new("Frame")
	silenceFill.Name = "Fill"
	silenceFill.Size = UDim2.fromScale(0, 1)
	silenceFill.BackgroundColor3 = WAITING_COLOR
	silenceFill.BorderSizePixel = 0
	silenceFill.Parent = silenceTrack

	local button = Instance.new("TextButton")
	button.Name = "Hold"
	button.Size = UDim2.new(1, 0, 0, 40)
	button.BackgroundColor3 = BUTTON_DEAD
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextColor3 = BUTTON_DEAD_TEXT
	button.Text = "WALK TO THE VAULT"
	button.LayoutOrder = 6
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
	noticeLabel.TextColor3 = LIVE_COLOR
	noticeLabel.Text = ""
	noticeLabel.Visible = false
	noticeLabel.LayoutOrder = 7
	noticeLabel.Parent = panel

	local self = setmetatable({
		screenGui = screenGui,
		panel = panel,
		titleLabel = titleLabel,
		fill = fill,
		takenLabel = takenLabel,
		alarmLamp = alarmLamp,
		guardLamp = guardLamp,
		silenceTrack = silenceTrack,
		silenceFill = silenceFill,
		button = button,
		noticeLabel = noticeLabel,
		holding = false,
		canHold = false,
		verb = "WALK TO THE VAULT",
		onHold = nil,
	}, BankUI) :: BankUIHandle

	local function setHolding(holding: boolean)
		-- A press with nothing in reach is dropped here rather than sent and refused. The
		-- server would say no either way; doing it on this side is what lets the button be
		-- visibly dead, and a dead button that still fired would be the panel lying about
		-- what it is.
		if holding and not self.canHold then
			return
		end
		if self.holding == holding then
			return
		end
		self.holding = holding
		paintButton(self)
		local handler = self.onHold
		if handler ~= nil then
			handler(holding)
		end
	end

	-- Both input paths, because the two devices raise different events and a bank that only
	-- worked with a mouse would be a bank most of this game's players cannot rob.
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
	-- before letting go, or the window lost focus mid-hold. Without this the hands stay on
	-- the vault with nothing on screen saying so, which during a ringing alarm is the worst
	-- possible way to lose an afternoon.
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

function BankUI.OnHold(self: BankUIHandle, handler: (holding: boolean) -> ())
	self.onHold = handler
end

-- The whole panel from one snapshot. Nil takes it down and, importantly, lets go: a panel
-- that vanished while the server still believed the hands were on the vault would be a
-- robbery continuing off screen.
function BankUI.Set(self: BankUIHandle, state: BankState?)
	if state == nil then
		self.panel.Visible = false
		self.holding = false
		self.canHold = false
		self.verb = "WALK TO THE VAULT"
		paintButton(self)
		return
	end

	self.panel.Visible = true
	self.titleLabel.Text = state.place

	local share = if state.vaultFull > 0 then state.vaultLeft / state.vaultFull else 0
	self.fill.Size = UDim2.new(math.clamp(share, 0, 1), 0, 1, 0)

	-- Rounded down to the whole unit. The vault drains continuously and a figure ticking
	-- through cents is a number the player watches instead of watching the room -- and in
	-- here the room contains a man walking toward them.
	self.takenLabel.Text = `${math.floor(state.taken)} taken -- ${math.floor(state.vaultLeft)} left in the vault`

	if state.alarm == "ringing" then
		setLamp(self.alarmLamp, `ALARM -- {string.format("%.0f", state.ringingFor)}s AND THEY KNOW WHERE YOU ARE`, "live")
	elseif state.alarm == "silenced" then
		setLamp(self.alarmLamp, `QUIET -- ARMS ITSELF IN {string.format("%.1f", state.rearmIn)}s`, "waiting")
	else
		setLamp(self.alarmLamp, "ALARM ARMED", "idle")
	end

	local guard = state.guard
	self.guardLamp.Visible = guard ~= nil
	if guard == "onYou" then
		setLamp(self.guardLamp, "THE GUARD HAS SEEN YOU", "live")
	elseif guard == "near" then
		setLamp(self.guardLamp, "GUARD IN THE ROOM", "waiting")
	elseif guard == "away" then
		setLamp(self.guardLamp, "GUARD AT THE OTHER END", "idle")
	end

	-- What the floor has decided the button means. Read off where the player is standing
	-- rather than off anything they chose, which is the whole grammar of this room.
	if state.at == "vault" then
		self.canHold = true
		self.verb = "HOLD TO TAKE"
	elseif state.at == "alarm" then
		self.canHold = true
		self.verb = "HOLD TO SILENCE"
	else
		self.canHold = false
		self.verb = if state.alarm == "ringing" then "RUN TO THE PANEL" else "WALK TO THE VAULT"
	end

	self.silenceTrack.Visible = state.at == "alarm" and state.silencing > 0
	self.silenceFill.Size = UDim2.fromScale(math.clamp(state.silencing, 0, 1), 1)

	-- The server's word on whether the hands are actually on it, which can differ from the
	-- button: walking out of reach, an empty vault, a completed silence or a death all take
	-- them off without anybody letting go. Following the server rather than the button is
	-- what stops the panel insisting on a hold that has already ended.
	if not state.holding then
		self.holding = false
	end
	paintButton(self)

	local notice = state.notice
	self.noticeLabel.Visible = notice ~= nil
	self.noticeLabel.Text = notice or ""
	self.noticeLabel.TextColor3 = if state.alarm == "ringing" then LIVE_COLOR else CAPTION_COLOR
end

return BankUI
