--!strict
-- The three-click meter, drawn.
--
-- Centre-bottom rather than the corner the other school panels use, for MusicUI's reason:
-- the whole lesson is a marker crossing a bar, and a bar read out of the side of your eye is
-- a bar you cannot time. It is the same placement rule -- a panel goes where the eye has to
-- be, and only a panel the eye has to *live* on earns the middle of the screen.
--
-- **This module does not judge.** That is the difference from MusicUI, and it is worth being
-- explicit about because the two files look alike. Music judges on the client because its
-- windows are 25-124ms and a round trip is longer than the widest of them. This meter's
-- windows are hundreds of milliseconds wide, so there is no such excuse: the click sends the
-- marker position it was taken at and **the server scores it**, having first checked that
-- value against its own marker. See PEService.onClickRequested.
--
-- The marker is drawn from a clock this file starts when a new sweep arrives, not from the
-- server's. Same reasoning as the music count-in: the player is judged against the bar they
-- watched, and a mid-sweep correction would move the target under their hand. What keeps the
-- two honest is the tolerance the server applies, not a shared clock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage:WaitForChild("Types"))

type PEState = Types.PEState

local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local CAPTION_COLOR = Color3.fromRGB(146, 150, 162)
local BAR_COLOR = Color3.fromRGB(32, 34, 42)

local POWER_COLOR = Color3.fromRGB(238, 172, 84)
local OVERSWING_COLOR = Color3.fromRGB(206, 78, 70)
local GOOD_COLOR = Color3.fromRGB(72, 132, 96)
local PERFECT_COLOR = Color3.fromRGB(112, 214, 150)
local MARKER_COLOR = Color3.fromRGB(244, 246, 250)

export type DrillUIHandle = {
	gui: ScreenGui,
	panel: Frame,
	title: TextLabel,
	caption: TextLabel,
	bar: Frame,
	good: Frame,
	perfect: Frame,
	overswing: Frame,
	marker: Frame,
	held: Frame,
	tally: TextLabel,
	state: PEState?,
	-- The client clock at the moment the running sweep was learned about, and the sweep it
	-- belongs to. Two fields rather than one because a push that does not change the sweep
	-- must not restart the marker.
	sweepKey: number,
	sweepAt: number,
	onClick: ((value: number) -> ())?,
	conns: { RBXScriptConnection },
}

local DrillUI = {}
DrillUI.__index = DrillUI

-- The marker position, as a share of the bar. A triangle wave, and it must stay byte-for-byte
-- the same shape as PEService.markerAt -- the server's tolerance check compares the two, so a
-- divergence here would not look like a drawing bug, it would look like the server rejecting
-- honest clicks.
local function markerAt(elapsed: number, sweepSeconds: number): number
	if sweepSeconds <= 0 then
		return 0
	end
	local phase = (elapsed / sweepSeconds) % 2
	return if phase <= 1 then phase else 2 - phase
end

function DrillUI.new(): DrillUIHandle
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "DrillUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -24)
	panel.Size = UDim2.fromOffset(460, 132)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -32, 0, 20)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = TITLE_COLOR
	title.Text = ""
	title.Parent = panel

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.BackgroundTransparency = 1
	caption.Position = UDim2.fromOffset(16, 30)
	caption.Size = UDim2.new(1, -32, 0, 18)
	caption.Font = Enum.Font.Gotham
	caption.TextSize = 13
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextColor3 = CAPTION_COLOR
	caption.Text = ""
	caption.Parent = panel

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromOffset(16, 58)
	bar.Size = UDim2.new(1, -32, 0, 34)
	bar.BackgroundColor3 = BAR_COLOR
	bar.BorderSizePixel = 0
	bar.ClipsDescendants = true
	bar.Parent = panel
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = bar

	-- Drawn back to front: the zones, then the held power, then the marker over everything.
	local function zone(name: string, color: Color3, transparency: number): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundColor3 = color
		f.BackgroundTransparency = transparency
		f.BorderSizePixel = 0
		f.Size = UDim2.new(0, 0, 1, 0)
		f.Visible = false
		f.Parent = bar
		return f
	end

	local overswing = zone("Overswing", OVERSWING_COLOR, 0.55)
	local good = zone("Good", GOOD_COLOR, 0.45)
	local perfect = zone("Perfect", PERFECT_COLOR, 0.3)

	local held = Instance.new("Frame")
	held.Name = "Held"
	held.BackgroundColor3 = POWER_COLOR
	held.BorderSizePixel = 0
	held.Size = UDim2.new(0, 3, 1, 0)
	held.Visible = false
	held.Parent = bar

	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.BackgroundColor3 = MARKER_COLOR
	marker.BorderSizePixel = 0
	marker.Size = UDim2.new(0, 3, 1, 0)
	marker.Parent = bar

	local tally = Instance.new("TextLabel")
	tally.Name = "Tally"
	tally.BackgroundTransparency = 1
	tally.Position = UDim2.fromOffset(16, 98)
	tally.Size = UDim2.new(1, -32, 0, 20)
	tally.Font = Enum.Font.Gotham
	tally.TextSize = 13
	tally.TextXAlignment = Enum.TextXAlignment.Left
	tally.TextColor3 = CAPTION_COLOR
	tally.Text = ""
	tally.Parent = panel

	local self: DrillUIHandle = setmetatable({
		gui = gui,
		panel = panel,
		title = title,
		caption = caption,
		bar = bar,
		good = good,
		perfect = perfect,
		overswing = overswing,
		marker = marker,
		held = held,
		tally = tally,
		state = nil,
		sweepKey = 0,
		sweepAt = 0,
		onClick = nil,
		conns = {},
	}, DrillUI) :: any

	table.insert(
		self.conns,
		RunService.RenderStepped:Connect(function()
			DrillUI._frame(self)
		end)
	)

	table.insert(
		self.conns,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed then
				return
			end
			-- Mouse, touch or space. One verb, three ways in: the meter is the whole lesson
			-- and a player who cannot find its button is a player who cannot sit the class.
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
				or input.KeyCode == Enum.KeyCode.Space
			then
				DrillUI._click(self)
			end
		end)
	)

	return self
end

function DrillUI.OnClick(self: DrillUIHandle, handler: (value: number) -> ())
	self.onClick = handler
end

function DrillUI._click(self: DrillUIHandle)
	local state = self.state
	if state == nil or not state.active then
		return
	end
	local handler = self.onClick
	if handler == nil then
		return
	end
	handler(markerAt(os.clock() - self.sweepAt, state.sweepSeconds))
end

function DrillUI._frame(self: DrillUIHandle)
	local state = self.state
	if state == nil or not state.active then
		return
	end
	local value = markerAt(os.clock() - self.sweepAt, state.sweepSeconds)
	self.marker.Position = UDim2.new(value, -1, 0, 0)
end

function DrillUI.Set(self: DrillUIHandle, state: PEState?)
	if state == nil or not state.active then
		self.state = nil
		self.gui.Enabled = false
		return
	end

	-- A new sweep restarts the local clock; a push that only changed the tally must not, or
	-- the marker would jump every quarter second.
	if state.sweepStartedAt ~= self.sweepKey then
		self.sweepKey = state.sweepStartedAt
		self.sweepAt = os.clock()
	end

	self.state = state
	self.gui.Enabled = true

	self.title.Text = `{state.drill}  —  {state.attempt}/{state.attempts}`
	self.caption.Text = state.line

	local isPower = state.phase == "power"

	-- Power phase shows what the greedy end of the bar costs; accuracy phase shows the target.
	self.overswing.Visible = isPower
	if isPower then
		self.overswing.Position = UDim2.fromScale(state.overswingFrom, 0)
		self.overswing.Size = UDim2.new(1 - state.overswingFrom, 0, 1, 0)
	end

	self.good.Visible = not isPower
	self.perfect.Visible = not isPower
	if not isPower then
		self.good.Position = UDim2.fromScale(state.goodFrom, 0)
		self.good.Size = UDim2.new(state.goodTo - state.goodFrom, 0, 1, 0)
		self.perfect.Position = UDim2.fromScale(state.perfectFrom, 0)
		self.perfect.Size = UDim2.new(state.perfectTo - state.perfectFrom, 0, 1, 0)
	end

	-- The power you locked stays on the bar through the accuracy sweep, so the thing you are
	-- about to spend is visible while you spend it.
	self.held.Visible = not isPower and state.power > 0
	if self.held.Visible then
		self.held.Position = UDim2.new(state.power, -1, 0, 0)
	end

	local scoredPercent = math.floor((state.scored / math.max(state.attempts, 1)) * 100 + 0.5)
	local passPercent = math.floor(state.passShare * 100 + 0.5)
	local tally = `{scoredPercent}%  ·  pass {passPercent}%`
	if state.lastLine ~= "" then
		tally ..= `  ·  {state.lastLine}`
	end
	self.tally.Text = tally
end

function DrillUI.Destroy(self: DrillUIHandle)
	for _, conn in self.conns do
		conn:Disconnect()
	end
	table.clear(self.conns)
	self.gui:Destroy()
end

return DrillUI
