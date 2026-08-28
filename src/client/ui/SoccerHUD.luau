--!strict
-- The 3v3 pitch, drawn.
--
-- Top centre, and alone in taking that spot for the same reason a scoreboard always sits
-- above the pitch it belongs to rather than beside the player reading it: this state is
-- pushed to everyone standing near enough to watch (see SoccerUpdated's own header), not
-- only the six on the roster, so the panel has to read as "the match" before it reads as
-- "your controls." Score and clock are the only two lines a spectator gets; everything
-- below the divider only appears once the roster carries your name.
--
-- The charge meter reuses FightUI's whole shape on purpose -- track, bands, an overcharge
-- mark, a held button whose release is the one thing that can commit it -- because it is
-- the same primitive wearing a different Config table (Config.Sports.Soccer's shooting
-- section instead of Fight's). The bands are not sent on the state the way Fight's are:
-- a shot is graded once, at release, and nothing about a shot in flight needs to disagree
-- with Config, so the marks are read from it directly rather than round-tripped for no
-- reason a per-frame server push would answer.
--
-- Pass is a tap, never a hold. See Config.Sports.Soccer's own passing-section comment for
-- why: a second charge meter here would be a shot wearing a different name, and this game
-- already has one verb for "commit to a release."

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))

type SoccerMatchState = Types.SoccerMatchState

local SOCCER = Config.Sports.Soccer

local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local CAPTION_COLOR = Color3.fromRGB(146, 150, 162)
local TRACK_COLOR = Color3.fromRGB(38, 39, 46)

local HOME_COLOR = Color3.fromRGB(120, 178, 224)
local AWAY_COLOR = Color3.fromRGB(224, 108, 96)
local CARRIER_COLOR = Color3.fromRGB(235, 190, 90)

local CHARGE_COLOR = Color3.fromRGB(150, 196, 214)
local CHARGE_OVER_COLOR = Color3.fromRGB(214, 196, 130)
local MARK_COLOR = Color3.fromRGB(96, 100, 112)

local GOAL_VERDICT_COLOR = Color3.fromRGB(120, 208, 140)
local OTHER_VERDICT_COLOR = Color3.fromRGB(228, 148, 84)

local BUTTON_COLOR = Color3.fromRGB(44, 46, 56)
local BUTTON_HELD_COLOR = Color3.fromRGB(78, 82, 98)
local BUTTON_TEXT_COLOR = Color3.fromRGB(228, 231, 240)

local JOIN_COLOR = Color3.fromRGB(120, 208, 140)

local PE_TAG_COLOR = Color3.fromRGB(150, 196, 214)

local PANEL_WIDTH = 340
local BUTTON_HEIGHT = 48

-- Same tween shape as FightUI's footing bars, for the same reason: the server ticks at
-- Config.Sports.Soccer.TickSeconds, and a fill still travelling when the next state
-- arrives lies about the meter at the exact moment a release reads it.
local BAR_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local SoccerHUD = {}
SoccerHUD.__index = SoccerHUD

export type SoccerHUDHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		scoreLabel: TextLabel,
		clockLabel: TextLabel,
		peTag: TextLabel,
		rosterLabel: TextLabel,
		verdictLabel: TextLabel,
		controls: Frame,
		chargeTrack: Frame,
		chargeFill: Frame,
		perfectMark: Frame,
		overMark: Frame,
		shootButton: TextButton,
		passButton: TextButton,
		joinButton: TextButton,
		holdingShoot: boolean,
		onJoin: (() -> ())?,
		onShoot: ((held: boolean) -> ())?,
		onPass: (() -> ())?,
	},
	SoccerHUD
))

-- The one path that can change the shoot hold, on the same rule FightUI's setHeld
-- follows: every way a hold can end -- releasing on the button, releasing off it,
-- alt-tabbing, or the match taking the panel down -- runs through here, so the server is
-- never left believing a button is still down that the client has forgotten about.
local function setHeldShoot(self: SoccerHUDHandle, held: boolean)
	if self.holdingShoot == held then
		return
	end
	self.holdingShoot = held
	local callback = self.onShoot
	if callback ~= nil then
		callback(held)
	end
	self.shootButton.BackgroundColor3 = if held then BUTTON_HELD_COLOR else BUTTON_COLOR
end

local function makeMark(track: Frame, share: number): Frame
	local mark = Instance.new("Frame")
	mark.Size = UDim2.new(0, 2, 1, 0)
	mark.Position = UDim2.new(share, -1, 0, 0)
	mark.BackgroundColor3 = MARK_COLOR
	mark.BorderSizePixel = 0
	mark.ZIndex = 3
	mark.Parent = track
	return mark
end

local function makeButton(parent: Instance, order: number, text: string, width: number): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, width, 0, BUTTON_HEIGHT)
	button.BackgroundColor3 = BUTTON_COLOR
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextColor3 = BUTTON_TEXT_COLOR
	button.Text = text
	button.LayoutOrder = order
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	return button
end

function SoccerHUD.new(): SoccerHUDHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesSoccer"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 2

	local panel = Instance.new("Frame")
	panel.Name = "SoccerPanel"
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 16)
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
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = panel

	local scoreRow = Instance.new("Frame")
	scoreRow.Name = "ScoreRow"
	scoreRow.Size = UDim2.new(1, 0, 0, 0)
	scoreRow.AutomaticSize = Enum.AutomaticSize.Y
	scoreRow.BackgroundTransparency = 1
	scoreRow.LayoutOrder = 0
	scoreRow.Parent = panel

	local scoreLayout = Instance.new("UIListLayout")
	scoreLayout.FillDirection = Enum.FillDirection.Horizontal
	scoreLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scoreLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	scoreLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	scoreLayout.Padding = UDim.new(0, 10)
	scoreLayout.Parent = scoreRow

	local scoreLabel = Instance.new("TextLabel")
	scoreLabel.Name = "Score"
	scoreLabel.Size = UDim2.new(0, 0, 0, 22)
	scoreLabel.AutomaticSize = Enum.AutomaticSize.X
	scoreLabel.BackgroundTransparency = 1
	scoreLabel.Font = Enum.Font.GothamBold
	scoreLabel.TextSize = 20
	scoreLabel.TextColor3 = TITLE_COLOR
	scoreLabel.Text = ""
	scoreLabel.LayoutOrder = 0
	scoreLabel.Parent = scoreRow

	local clockLabel = Instance.new("TextLabel")
	clockLabel.Name = "Clock"
	clockLabel.Size = UDim2.new(0, 0, 0, 22)
	clockLabel.AutomaticSize = Enum.AutomaticSize.X
	clockLabel.BackgroundTransparency = 1
	clockLabel.Font = Enum.Font.GothamMedium
	clockLabel.TextSize = 16
	clockLabel.TextColor3 = CAPTION_COLOR
	clockLabel.Text = ""
	clockLabel.LayoutOrder = 1
	clockLabel.Parent = scoreRow

	local peTag = Instance.new("TextLabel")
	peTag.Name = "PeTag"
	peTag.Size = UDim2.new(0, 0, 0, 18)
	peTag.AutomaticSize = Enum.AutomaticSize.X
	peTag.BackgroundTransparency = 1
	peTag.Font = Enum.Font.GothamBold
	peTag.TextSize = 12
	peTag.TextColor3 = PE_TAG_COLOR
	peTag.Text = "PE"
	peTag.Visible = false
	peTag.LayoutOrder = 2
	peTag.Parent = scoreRow

	local rosterLabel = Instance.new("TextLabel")
	rosterLabel.Name = "Roster"
	rosterLabel.Size = UDim2.new(1, 0, 0, 0)
	rosterLabel.AutomaticSize = Enum.AutomaticSize.Y
	rosterLabel.BackgroundTransparency = 1
	rosterLabel.Font = Enum.Font.Gotham
	rosterLabel.TextSize = 12
	rosterLabel.TextWrapped = true
	rosterLabel.RichText = true
	rosterLabel.TextColor3 = CAPTION_COLOR
	rosterLabel.Text = ""
	rosterLabel.LayoutOrder = 1
	rosterLabel.Parent = panel

	local verdictLabel = Instance.new("TextLabel")
	verdictLabel.Name = "Verdict"
	verdictLabel.Size = UDim2.new(1, 0, 0, 20)
	verdictLabel.BackgroundTransparency = 1
	verdictLabel.Font = Enum.Font.GothamBold
	verdictLabel.TextSize = 16
	verdictLabel.TextColor3 = GOAL_VERDICT_COLOR
	verdictLabel.Text = ""
	verdictLabel.Visible = false
	verdictLabel.LayoutOrder = 2
	verdictLabel.Parent = panel

	local joinButton = makeButton(panel, 3, "Join the match", PANEL_WIDTH - 24)
	joinButton.BackgroundColor3 = JOIN_COLOR
	joinButton.TextColor3 = Color3.fromRGB(20, 40, 26)
	joinButton.Visible = false

	-- Everything below here only shows once the roster carries your name.
	local controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.Size = UDim2.new(1, 0, 0, 0)
	controls.AutomaticSize = Enum.AutomaticSize.Y
	controls.BackgroundTransparency = 1
	controls.Visible = false
	controls.LayoutOrder = 4
	controls.Parent = panel

	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	controlsLayout.Padding = UDim.new(0, 6)
	controlsLayout.Parent = controls

	local chargeTrack = Instance.new("Frame")
	chargeTrack.Name = "ChargeTrack"
	chargeTrack.Size = UDim2.new(1, 0, 0, 10)
	chargeTrack.BackgroundColor3 = TRACK_COLOR
	chargeTrack.BorderSizePixel = 0
	chargeTrack.ClipsDescendants = true
	chargeTrack.LayoutOrder = 0
	chargeTrack.Parent = controls

	local chargeCorner = Instance.new("UICorner")
	chargeCorner.CornerRadius = UDim.new(0, 3)
	chargeCorner.Parent = chargeTrack

	local chargeFill = Instance.new("Frame")
	chargeFill.Name = "Fill"
	chargeFill.Size = UDim2.new(0, 0, 1, 0)
	chargeFill.BackgroundColor3 = CHARGE_COLOR
	chargeFill.BorderSizePixel = 0
	chargeFill.ZIndex = 2
	chargeFill.Parent = chargeTrack

	local chargeFillCorner = Instance.new("UICorner")
	chargeFillCorner.CornerRadius = UDim.new(0, 3)
	chargeFillCorner.Parent = chargeFill

	-- Two lines rather than a filled band the way Music's sweet/perfect bands are drawn:
	-- Fight's charge meter marks single points to aim at rather than zones to land inside,
	-- and this reuses that reading. `perfectMark` sits at ShotBandCenter -- release close
	-- to it for Perfect, release near it for Good -- and `overMark` sits at the point past
	-- which a shot is overcharged and goes wide no matter how well-aimed.
	local perfectMark = makeMark(chargeTrack, 0)
	local overMark = makeMark(chargeTrack, 0)

	local buttonRow = Instance.new("Frame")
	buttonRow.Name = "Buttons"
	buttonRow.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
	buttonRow.BackgroundTransparency = 1
	buttonRow.LayoutOrder = 1
	buttonRow.Parent = controls

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonLayout.Padding = UDim.new(0, 8)
	buttonLayout.Parent = buttonRow

	local passButton = makeButton(buttonRow, 0, "Pass", (PANEL_WIDTH - 32) / 2)
	local shootButton = makeButton(buttonRow, 1, "Hold to shoot", (PANEL_WIDTH - 32) / 2)

	screenGui.Parent = playerGui

	local self = setmetatable({
		screenGui = screenGui,
		panel = panel,
		scoreLabel = scoreLabel,
		clockLabel = clockLabel,
		peTag = peTag,
		rosterLabel = rosterLabel,
		verdictLabel = verdictLabel,
		controls = controls,
		chargeTrack = chargeTrack,
		chargeFill = chargeFill,
		perfectMark = perfectMark,
		overMark = overMark,
		shootButton = shootButton,
		passButton = passButton,
		joinButton = joinButton,
		holdingShoot = false,
		onJoin = nil,
		onShoot = nil,
		onPass = nil,
	}, SoccerHUD) :: SoccerHUDHandle

	-- Shoot is held, on the same input shape as FightUI's strike -- see that file's header
	-- for why every way a hold can end has to run through one path.
	shootButton.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			setHeldShoot(self, true)
		end
	end)
	shootButton.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			setHeldShoot(self, false)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			setHeldShoot(self, false)
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		setHeldShoot(self, false)
	end)

	passButton.Activated:Connect(function()
		local callback = self.onPass
		if callback ~= nil then
			callback()
		end
	end)

	joinButton.Activated:Connect(function()
		local callback = self.onJoin
		if callback ~= nil then
			callback()
		end
	end)

	return self
end

function SoccerHUD.OnJoin(self: SoccerHUDHandle, callback: () -> ())
	self.onJoin = callback
end

function SoccerHUD.OnShoot(self: SoccerHUDHandle, callback: (held: boolean) -> ())
	self.onShoot = callback
end

function SoccerHUD.OnPass(self: SoccerHUDHandle, callback: () -> ())
	self.onPass = callback
end

local function formatClock(secondsLeft: number): string
	local whole = math.max(0, math.floor(secondsLeft))
	local minutes = whole // 60
	local seconds = whole % 60
	return string.format("%d:%02d", minutes, seconds)
end

local function colorToHex(color: Color3): string
	return string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
end

local HOME_HEX = colorToHex(HOME_COLOR)
local AWAY_HEX = colorToHex(AWAY_COLOR)
local CARRIER_HEX = colorToHex(CARRIER_COLOR)

-- Rich text rather than a plain string, so the two teams read apart by colour the same
-- way FightUI's footing bars do -- a name is worth telling apart from the ball it is
-- currently attached to, and RichText is the cheap way to say both in one label instead
-- of building six separate ones for a line this small.
local function rosterLine(state: SoccerMatchState): string
	local home: { string } = {}
	local away: { string } = {}
	for _, entry in state.roster do
		local word = if entry.isYou then `<b>{entry.name}</b>` else entry.name
		if entry.isCarrier then
			word ..= ` <font color="{CARRIER_HEX}">(ball)</font>`
		end
		if entry.team == "home" then
			table.insert(home, word)
		else
			table.insert(away, word)
		end
	end
	local homeLine = `<font color="{HOME_HEX}">Home:</font> {table.concat(home, ", ")}`
	local awayLine = `<font color="{AWAY_HEX}">Away:</font> {table.concat(away, ", ")}`
	return `{homeLine}  --  {awayLine}`
end

-- The whole panel, from one snapshot. Nil is the usual state -- out of watch range, or the
-- pitch has not built its first match yet -- and takes it down.
function SoccerHUD.Set(self: SoccerHUDHandle, state: SoccerMatchState?)
	if state == nil then
		-- Dropped through the one path, same as FightUI.Set's own nil branch: a shoot
		-- left held across a panel taking down would freeze the button on the next match.
		setHeldShoot(self, false)
		self.panel.Visible = false
		return
	end

	self.panel.Visible = true

	self.scoreLabel.Text = `Home {state.homeScore} -- {state.awayScore} Away`
	self.scoreLabel.TextColor3 = if state.onRoster then CARRIER_COLOR else TITLE_COLOR
	self.clockLabel.Text = formatClock(state.secondsLeft)
	self.peTag.Visible = state.gradingPe
	self.rosterLabel.Text = rosterLine(state)

	local verdict = state.verdict
	self.verdictLabel.Visible = verdict ~= nil
	if verdict ~= nil then
		self.verdictLabel.Text = verdict
		self.verdictLabel.TextColor3 = if string.find(verdict, "Goal") ~= nil
			then GOAL_VERDICT_COLOR
			else OTHER_VERDICT_COLOR
	end

	self.joinButton.Visible = state.canJoin and not state.onRoster

	self.controls.Visible = state.onRoster
	if not state.onRoster then
		setHeldShoot(self, false)
		return
	end

	self.perfectMark.Position = UDim2.new(math.clamp(SOCCER.ShotBandCenter, 0, 1), -1, 0, 0)
	self.overMark.Position = UDim2.new(SOCCER.OverchargeShare, -1, 0, 0)
	TweenService
		:Create(self.chargeFill, BAR_TWEEN, { Size = UDim2.new(math.clamp(state.chargeShare, 0, 1), 0, 1, 0) })
		:Play()
	self.chargeFill.BackgroundColor3 = if state.chargeShare >= SOCCER.OverchargeShare
		then CHARGE_OVER_COLOR
		else CHARGE_COLOR

	if not state.isCarrier and self.holdingShoot then
		-- Lost the ball mid-charge -- a tackle, a pass out, a goal reset. Released through
		-- the one path for the same reason every other forced release in this game is.
		setHeldShoot(self, false)
	end
	self.shootButton.BackgroundColor3 = if self.holdingShoot then BUTTON_HELD_COLOR else BUTTON_COLOR
end

return SoccerHUD
