--!strict
-- The stare-down, drawn.
--
-- Bottom centre rather than bottom left, and that is the one placement decision in this
-- file worth arguing about. Every other activity surface in school lives in the corner
-- because the player is looking at a room -- the bench, the wall, the canvas -- and the
-- panel is a readout beside it. Here the player is looking at a *person*, who is directly
-- in front of them, and the bar has to be in the same glance as the face. A corner panel
-- would make the corridor a thing you play by watching the corner.
--
-- **One bar, not two.** Nerve and patience are drawn on the same track, which is the whole
-- reason the encounter is readable: the question is never "what are these two numbers",
-- it is "is my fill past their line yet", and two stacked bars would turn a comparison
-- into arithmetic. The green band is where the player is trying to stop.
--
-- **This module draws off `active` and off nothing else.** Same contract EaselUI and
-- LabUI hold: the server decides whether there is somebody in front of you, and the hold
-- button exists exactly when the server would honour a hold. There is no version of this
-- where the button is live and the release is refused.
--
-- The window is drawn from `windowLow`/`windowHigh` as sent and is never recomputed here.
-- It is what the life\'s nerve buys and the server scores against it; a client that worked
-- it out again could disagree, and the player would watch themselves release inside the
-- green and be told they backed down. Of every number on this channel that is the one that
-- must not be derived twice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type NerveState = Types.NerveState

local BULLY = Config.School.Bully

-- The full width of the track, in the same share units the server sends. Everything on the
-- bar is divided by this, so the overhold zone past the window has somewhere to be drawn
-- rather than running off the end.
local SCALE = BULLY.Nerve.OverholdCeilingShare

-- The panel\'s own palette, copied from EaselUI rather than shared with it, for the reason
-- that file gives: two surfaces that look alike should look alike because somebody decided
-- so, and a shared constants file means re-colouring one silently re-colours the other.
local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local CAPTION_COLOR = Color3.fromRGB(146, 150, 162)
local TRACK_COLOR = Color3.fromRGB(38, 39, 46)

-- Your nerve. Warm, and the only thing on the bar that is *yours*.
local NERVE_COLOR = Color3.fromRGB(238, 186, 92)
-- The band to release in. Green, and it is the only green in the panel -- nothing else may
-- borrow it, or the one thing the player is aiming at stops being the one thing that is
-- green.
local WINDOW_COLOR = Color3.fromRGB(96, 196, 122)
-- Past the band. Not red: overholding is a bad outcome, not a forbidden one, and a red
-- zone would read as a wall the bar must not enter rather than as a cost.
local OVER_COLOR = Color3.fromRGB(122, 96, 132)
-- Their patience, drawn as a line rather than a fill. A fill would be a second bar and the
-- note at the top of this file is about why there is only one.
local PATIENCE_COLOR = Color3.fromRGB(228, 228, 236)

export type NerveUIHandle = {
	gui: ScreenGui,
	frame: Frame,
	title: TextLabel,
	line: TextLabel,
	track: Frame,
	window: Frame,
	over: Frame,
	fill: Frame,
	patience: Frame,
	button: TextButton,
	backup: TextLabel,
	holding: boolean,
	onHold: ((holding: boolean) -> ())?,
}

local NerveUI = {}
NerveUI.__index = NerveUI

function NerveUI.new(): NerveUIHandle
	local gui = Instance.new("ScreenGui")
	gui.Name = "NerveUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	-- Wide and short, and anchored to the bottom centre. The height is deliberately small:
	-- this sits under a person\'s feet and anything taller would cover the face the player
	-- is supposed to be reading.
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -18)
	frame.Size = UDim2.new(0, 460, 0, 150)
	frame.BackgroundColor3 = PANEL_COLOR
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 20)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 17
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = TITLE_COLOR
	title.Text = ""
	title.Parent = frame

	local line = Instance.new("TextLabel")
	line.Name = "Line"
	line.Position = UDim2.new(0, 0, 0, 22)
	line.Size = UDim2.new(1, 0, 0, 30)
	line.BackgroundTransparency = 1
	line.Font = Enum.Font.GothamMedium
	line.TextSize = 13
	line.TextWrapped = true
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextYAlignment = Enum.TextYAlignment.Top
	line.TextColor3 = CAPTION_COLOR
	line.Text = ""
	line.Parent = frame

	-- The track, and everything on it is a child of this so that every position below is a
	-- share of the same width and none of them can drift apart.
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.new(0, 0, 0, 60)
	track.Size = UDim2.new(1, 0, 0, 22)
	track.BackgroundColor3 = TRACK_COLOR
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = frame

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 5)
	trackCorner.Parent = track

	-- Drawn in this order on purpose: the zones are the backdrop, the fill runs over them,
	-- and their patience line sits on top of everything so it is never hidden by the bar
	-- that is chasing it.
	local over = Instance.new("Frame")
	over.Name = "Over"
	over.BackgroundColor3 = OVER_COLOR
	over.BorderSizePixel = 0
	over.Parent = track

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.BackgroundColor3 = WINDOW_COLOR
	window.BorderSizePixel = 0
	window.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = NERVE_COLOR
	fill.BackgroundTransparency = 0.25
	fill.BorderSizePixel = 0
	fill.Parent = track

	local patience = Instance.new("Frame")
	patience.Name = "Patience"
	patience.Size = UDim2.new(0, 2, 1, 0)
	patience.BackgroundColor3 = PATIENCE_COLOR
	patience.BorderSizePixel = 0
	patience.Parent = track

	local backup = Instance.new("TextLabel")
	backup.Name = "Backup"
	backup.Position = UDim2.new(0, 0, 0, 84)
	backup.Size = UDim2.new(1, 0, 0, 14)
	backup.BackgroundTransparency = 1
	backup.Font = Enum.Font.GothamMedium
	backup.TextSize = 12
	backup.TextXAlignment = Enum.TextXAlignment.Left
	backup.TextColor3 = CAPTION_COLOR
	backup.Text = ""
	backup.Parent = frame

	local button = Instance.new("TextButton")
	button.Name = "Hold"
	button.Position = UDim2.new(0, 0, 1, -34)
	-- Full width and 34 tall, which clears the 44-50px minimum tap target once the panel
	-- padding either side of it is counted. This is the only control in the corridor and on
	-- a phone it is the only thing a thumb has to find.
	button.Size = UDim2.new(1, 0, 0, 34)
	button.BackgroundColor3 = TRACK_COLOR
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.TextColor3 = TITLE_COLOR
	button.Text = "HOLD YOUR NERVE"
	button.Parent = frame

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = button

	local self: NerveUIHandle = setmetatable({
		gui = gui,
		frame = frame,
		title = title,
		line = line,
		track = track,
		window = window,
		over = over,
		fill = fill,
		patience = patience,
		button = button,
		backup = backup,
		holding = false,
		onHold = nil,
	}, NerveUI) :: any

	local function setHolding(holding: boolean)
		if self.holding == holding then
			return
		end
		self.holding = holding
		self.button.BackgroundColor3 = if holding then NERVE_COLOR else TRACK_COLOR
		self.button.TextColor3 = if holding then PANEL_COLOR else TITLE_COLOR
		self.button.Text = if holding then "LET GO TO COMMIT" else "HOLD YOUR NERVE"
		local handler = self.onHold
		if handler ~= nil then
			handler(holding)
		end
	end

	-- Both input paths, for the reason BankUI states about its own: the two devices raise
	-- different events, and a corridor that only worked with a mouse would be a corridor
	-- most of this game\'s players cannot walk down.
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

	-- A release that happened somewhere else entirely: dragged off the button before letting
	-- go, or the window lost focus mid-hold. Without this the player is left holding a bar
	-- that keeps climbing with nothing on screen saying so, and the encounter resolves as an
	-- overhold they never chose -- which is the one outcome in the corridor that is worse
	-- than backing down.
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

function NerveUI.OnHold(self: NerveUIHandle, handler: (holding: boolean) -> ())
	self.onHold = handler
end

-- Draws a state, or clears the panel when handed nil or an inactive one.
--
-- The closing line is the one thing that survives `active` going false: what somebody said
-- on the way out has to stay readable for a beat after they have gone, or the outcome of
-- the encounter is a panel disappearing.
function NerveUI.Set(self: NerveUIHandle, state: NerveState?)
	if state == nil then
		self.frame.Visible = false
		return
	end

	if not state.active then
		if state.line == "" then
			self.frame.Visible = false
			return
		end
		-- The closing beat. Bar and button gone, the line left standing.
		self.frame.Visible = true
		self.title.Text = ""
		self.line.Text = state.line
		self.track.Visible = false
		self.button.Visible = false
		self.backup.Text = ""
		return
	end

	self.frame.Visible = true
	self.track.Visible = true
	self.button.Visible = true
	self.title.Text = state.bullyName
	self.line.Text = state.line

	-- Every position on the track is a share of SCALE, so the overhold zone past the window
	-- has somewhere to be drawn instead of running off the end of the bar.
	local low = math.clamp(state.windowLow / SCALE, 0, 1)
	local high = math.clamp(state.windowHigh / SCALE, 0, 1)
	self.window.Position = UDim2.new(low, 0, 0, 0)
	self.window.Size = UDim2.new(math.max(high - low, 0), 0, 1, 0)
	self.over.Position = UDim2.new(high, 0, 0, 0)
	self.over.Size = UDim2.new(math.max(1 - high, 0), 0, 1, 0)

	self.fill.Size = UDim2.new(math.clamp(state.nerve / SCALE, 0, 1), 0, 1, 0)
	self.patience.Position = UDim2.new(math.clamp(state.patience / SCALE, 0, 1), -1, 0, 0)

	local seconds = state.secondsToBackup
	if seconds == nil then
		self.backup.Text = ""
	else
		-- Named rather than counted down in bare numbers. "2.4" on its own is a number the
		-- player has to be told the meaning of once and remember; this says what it is every
		-- time, at the cost of nothing.
		self.backup.Text = string.format("someone else is coming -- %.1fs", math.max(seconds, 0))
	end
end

function NerveUI.Destroy(self: NerveUIHandle)
	self.gui:Destroy()
end

return NerveUI
