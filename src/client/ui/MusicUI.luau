--!strict
-- The rhythm lesson, drawn.
--
-- Bottom left, the same corner LabUI and HuntUI take, and for the same reason: this is
-- the surface of the activity the player is currently doing, and the timetable runs one
-- subject at a time, so none of the three are ever on screen together.
--
-- This is not routed through StatsUI.applySweep even though the mechanic is the same
-- needle-and-window sweep the gym and the sports drill draw. That shared row is typed
-- `"gym" | "drill"` on purpose (see StatsUI.SweepSource) -- a third source would widen a
-- type meant to stay closed at two rooms that are always mutually exclusive by
-- construction (one gym, one sports campus). School is a third room a life can be
-- standing in at the same time as neither of those, so this panel owns its own track,
-- its own needle and its own PUSH button rather than reaching into a row built for two
-- other rooms to share.
--
-- The count-in is the one phase none of the gym's or the drill's sweep states have: a
-- number counting down before the needle moves at all. That is the ladder for this
-- subject (see Config.School.Music.CountInSecondsByLevel and MusicService's header) --
-- mastery buys warning, not an easier window -- so it gets its own line rather than
-- being folded into the bar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Sweep = require(ReplicatedStorage:WaitForChild("Sweep"))

type MusicState = Types.MusicState

-- The panel's own palette, matching LabUI's and HuntUI's rather than StatsUI's, for the
-- same reason they give: this is a place the player is in, not a readout they glance at.
local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local CAPTION_COLOR = Color3.fromRGB(146, 150, 162)
local TRACK_COLOR = Color3.fromRGB(34, 34, 40)
local SWEET_COLOR = Color3.fromRGB(180, 150, 50)
local PERFECT_COLOR = Color3.fromRGB(230, 195, 60)
local NEEDLE_COLOR = Color3.fromRGB(245, 240, 230)

local COUNT_IN_COLOR = Color3.fromRGB(150, 196, 214)

local PERFECT_GRADE_COLOR = Color3.fromRGB(230, 195, 60)
local GOOD_GRADE_COLOR = Color3.fromRGB(150, 196, 214)
local MISS_GRADE_COLOR = Color3.fromRGB(228, 140, 80)

local PUSH_ACTIVE_COLOR = Color3.fromRGB(235, 190, 90)
local PUSH_INACTIVE_COLOR = Color3.fromRGB(70, 70, 82)

local PANEL_WIDTH = 300

local MusicUI = {}
MusicUI.__index = MusicUI

export type MusicUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		titleLabel: TextLabel,
		songLabel: TextLabel,
		noteLabel: TextLabel,
		countInLabel: TextLabel,
		track: Frame,
		sweetBand: Frame,
		perfectBand: Frame,
		needle: Frame,
		gradeLabel: TextLabel,
		masteryLabel: TextLabel,
		summaryLabel: TextLabel,
		pushButton: TextButton,
		-- Live between server pushes, the same interpolation StatsUI's sweep row does and
		-- for the same reason: the server ticks a handful of times a second, and a needle
		-- that only moved on a tick would stutter instead of sweep.
		sweepConnection: RBXScriptConnection?,
		sweepBaseProgress: number,
		sweepElapsed: number,
		-- Nil unless a song is actually sweeping. Read by init.client.luau so the one PUSH
		-- key this panel owns never fires into a session that has already ended.
		running: boolean,
	},
	MusicUI
))

local function formatSeconds(seconds: number): string
	return string.format("%.1f", math.max(0, seconds))
end

function MusicUI.new(): MusicUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesMusic"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 2

	local panel = Instance.new("Frame")
	panel.Name = "MusicPanel"
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
	titleLabel.Text = "Music"
	titleLabel.LayoutOrder = 0
	titleLabel.Parent = panel

	local songLabel = Instance.new("TextLabel")
	songLabel.Name = "Song"
	songLabel.Size = UDim2.new(1, 0, 0, 0)
	songLabel.AutomaticSize = Enum.AutomaticSize.Y
	songLabel.BackgroundTransparency = 1
	songLabel.Font = Enum.Font.GothamBold
	songLabel.TextSize = 18
	songLabel.TextXAlignment = Enum.TextXAlignment.Left
	songLabel.TextWrapped = true
	songLabel.TextColor3 = TITLE_COLOR
	songLabel.Text = ""
	songLabel.LayoutOrder = 1
	songLabel.Parent = panel

	local noteLabel = Instance.new("TextLabel")
	noteLabel.Name = "Note"
	noteLabel.Size = UDim2.new(1, 0, 0, 0)
	noteLabel.AutomaticSize = Enum.AutomaticSize.Y
	noteLabel.BackgroundTransparency = 1
	noteLabel.Font = Enum.Font.Gotham
	noteLabel.TextSize = 13
	noteLabel.TextXAlignment = Enum.TextXAlignment.Left
	noteLabel.TextColor3 = CAPTION_COLOR
	noteLabel.Text = ""
	noteLabel.LayoutOrder = 2
	noteLabel.Parent = panel

	-- The count-in. Its own line, front and centre while it runs, because the ladder in
	-- this subject is entirely warning -- see the header -- and a reward that shares a
	-- line with something else reads as half the reward.
	local countInLabel = Instance.new("TextLabel")
	countInLabel.Name = "CountIn"
	countInLabel.Size = UDim2.new(1, 0, 0, 22)
	countInLabel.BackgroundTransparency = 1
	countInLabel.Font = Enum.Font.GothamBold
	countInLabel.TextSize = 18
	countInLabel.TextXAlignment = Enum.TextXAlignment.Left
	countInLabel.TextColor3 = COUNT_IN_COLOR
	countInLabel.Text = ""
	countInLabel.Visible = false
	countInLabel.LayoutOrder = 3
	countInLabel.Parent = panel

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 14)
	track.BackgroundColor3 = TRACK_COLOR
	track.BorderSizePixel = 0
	track.Visible = false
	track.LayoutOrder = 4
	track.Parent = panel

	local sweetBand = Instance.new("Frame")
	sweetBand.Name = "SweetBand"
	sweetBand.Size = UDim2.new(0, 0, 1, 0)
	sweetBand.BackgroundColor3 = SWEET_COLOR
	sweetBand.BorderSizePixel = 0
	sweetBand.Parent = track

	local perfectBand = Instance.new("Frame")
	perfectBand.Name = "PerfectBand"
	perfectBand.Size = UDim2.new(0, 0, 1, 0)
	perfectBand.BackgroundColor3 = PERFECT_COLOR
	perfectBand.BorderSizePixel = 0
	perfectBand.Parent = track

	local needle = Instance.new("Frame")
	needle.Name = "Needle"
	needle.Size = UDim2.new(0, 2, 1, 0)
	needle.AnchorPoint = Vector2.new(0.5, 0)
	needle.Position = UDim2.new(0, 0, 0, 0)
	needle.BackgroundColor3 = NEEDLE_COLOR
	needle.BorderSizePixel = 0
	needle.Parent = track

	local gradeLabel = Instance.new("TextLabel")
	gradeLabel.Name = "Grade"
	gradeLabel.Size = UDim2.new(1, 0, 0, 18)
	gradeLabel.BackgroundTransparency = 1
	gradeLabel.Font = Enum.Font.GothamBold
	gradeLabel.TextSize = 15
	gradeLabel.TextXAlignment = Enum.TextXAlignment.Left
	gradeLabel.TextColor3 = TITLE_COLOR
	gradeLabel.Text = ""
	gradeLabel.Visible = false
	gradeLabel.LayoutOrder = 5
	gradeLabel.Parent = panel

	local masteryLabel = Instance.new("TextLabel")
	masteryLabel.Name = "Mastery"
	masteryLabel.Size = UDim2.new(1, 0, 0, 0)
	masteryLabel.AutomaticSize = Enum.AutomaticSize.Y
	masteryLabel.BackgroundTransparency = 1
	masteryLabel.Font = Enum.Font.Gotham
	masteryLabel.TextSize = 12
	masteryLabel.TextXAlignment = Enum.TextXAlignment.Left
	masteryLabel.TextWrapped = true
	masteryLabel.TextColor3 = CAPTION_COLOR
	masteryLabel.Text = ""
	masteryLabel.LayoutOrder = 6
	masteryLabel.Parent = panel

	local summaryLabel = Instance.new("TextLabel")
	summaryLabel.Name = "Summary"
	summaryLabel.Size = UDim2.new(1, 0, 0, 0)
	summaryLabel.AutomaticSize = Enum.AutomaticSize.Y
	summaryLabel.BackgroundTransparency = 1
	summaryLabel.Font = Enum.Font.GothamMedium
	summaryLabel.TextSize = 14
	summaryLabel.TextXAlignment = Enum.TextXAlignment.Left
	summaryLabel.TextWrapped = true
	summaryLabel.TextColor3 = TITLE_COLOR
	summaryLabel.Text = ""
	summaryLabel.Visible = false
	summaryLabel.LayoutOrder = 7
	summaryLabel.Parent = panel

	-- Its own PUSH button rather than StatsUI's shared one -- see the header. Same look
	-- as the shared one so the press reads as the same verb everywhere it appears.
	local pushButton = Instance.new("TextButton")
	pushButton.Name = "PushButton"
	pushButton.Size = UDim2.new(0, 220, 0, 56)
	pushButton.AnchorPoint = Vector2.new(0.5, 1)
	pushButton.Position = UDim2.new(0.5, 0, 1, -24)
	pushButton.BackgroundColor3 = PUSH_INACTIVE_COLOR
	pushButton.AutoButtonColor = false
	pushButton.Font = Enum.Font.GothamBold
	pushButton.TextSize = 20
	pushButton.TextColor3 = Color3.fromRGB(120, 120, 130)
	pushButton.Text = "PUSH"
	pushButton.Visible = false
	pushButton.Parent = screenGui

	local pushCorner = Instance.new("UICorner")
	pushCorner.CornerRadius = UDim.new(0, 10)
	pushCorner.Parent = pushButton

	screenGui.Parent = playerGui

	return setmetatable({
		screenGui = screenGui,
		panel = panel,
		titleLabel = titleLabel,
		songLabel = songLabel,
		noteLabel = noteLabel,
		countInLabel = countInLabel,
		track = track,
		sweetBand = sweetBand,
		perfectBand = perfectBand,
		needle = needle,
		gradeLabel = gradeLabel,
		masteryLabel = masteryLabel,
		summaryLabel = summaryLabel,
		pushButton = pushButton,
		sweepConnection = nil,
		sweepBaseProgress = 0,
		sweepElapsed = 0,
		running = false,
	}, MusicUI) :: MusicUIHandle
end

local function stopSweep(self: MusicUIHandle)
	if self.sweepConnection ~= nil then
		self.sweepConnection:Disconnect()
		self.sweepConnection = nil
	end
end

-- The mastery line: what the next rung buys, in the player's words rather than a level
-- number -- the same call HuntUI's masterySentence makes and for the same reason.
local function masterySentence(state: MusicState): string
	if state.level >= state.levelMax then
		return "You can keep this beat. Music can be skipped."
	end
	local left = state.passesPerLevel - state.passes
	local word = if left == 1 then "song" else "songs"
	return `{left} good {word} until the count-in runs a little longer.`
end

local function gradeColor(grade: string): Color3
	if grade == "Perfect" then
		return PERFECT_GRADE_COLOR
	elseif grade == "Good" then
		return GOOD_GRADE_COLOR
	end
	return MISS_GRADE_COLOR
end

-- The whole panel, from one snapshot. Nil is the usual state and takes it down.
function MusicUI.Set(self: MusicUIHandle, state: MusicState?)
	if state == nil then
		self.panel.Visible = false
		self.pushButton.Visible = false
		self.running = false
		stopSweep(self)
		return
	end

	self.panel.Visible = true
	self.running = true

	-- The closing line replaces the working panel for a beat, exactly as HuntUI's
	-- summary does: everything else about a song already over is a thing arguing with
	-- the sentence that just landed.
	local summary = state.summary
	if summary ~= nil then
		stopSweep(self)
		self.pushButton.Visible = false
		self.summaryLabel.Visible = true
		self.summaryLabel.Text = summary
		self.songLabel.Visible = false
		self.noteLabel.Visible = false
		self.countInLabel.Visible = false
		self.track.Visible = false
		self.gradeLabel.Visible = false
		self.masteryLabel.Visible = false
		return
	end

	self.summaryLabel.Visible = false
	self.songLabel.Visible = true
	self.noteLabel.Visible = true
	self.masteryLabel.Visible = true
	self.songLabel.Text = state.songLabel
	self.noteLabel.Text = `Note {state.note} of {state.notes} -- {state.hits} on the beat`
	self.masteryLabel.Text = masterySentence(state)

	self.sweetBand.Size = UDim2.new(state.sweetHalf * 2, 0, 1, 0)
	self.sweetBand.Position = UDim2.new(state.sweetCenter - state.sweetHalf, 0, 0, 0)
	self.perfectBand.Size = UDim2.new(state.perfectHalf * 2, 0, 1, 0)
	self.perfectBand.Position = UDim2.new(state.sweetCenter - state.perfectHalf, 0, 0, 0)

	if state.phase == "leadIn" then
		stopSweep(self)
		self.countInLabel.Visible = true
		self.countInLabel.Text = `Count-in -- {formatSeconds(state.countInSecondsLeft)}s`
		self.track.Visible = false
		self.gradeLabel.Visible = false
		self.pushButton.Visible = false
		return
	end

	self.countInLabel.Visible = false
	self.track.Visible = true

	if state.phase == "verdict" then
		stopSweep(self)
		self.needle.Position = UDim2.new(state.progress, 0, 0, 0)
		local grade = state.grade
		self.gradeLabel.Visible = grade ~= nil
		if grade ~= nil then
			self.gradeLabel.Text = grade
			self.gradeLabel.TextColor3 = gradeColor(grade)
		end
		self.pushButton.Visible = true
		self.pushButton.BackgroundColor3 = PUSH_INACTIVE_COLOR
		self.pushButton.TextColor3 = Color3.fromRGB(120, 120, 130)
		return
	end

	-- Sweeping. Interpolated client-side between pushes for the same reason StatsUI's
	-- gym and drill rows are: the server ticks a handful of times a second, and a needle
	-- that only moved on a tick would stagger instead of sweep.
	self.gradeLabel.Visible = false
	self.pushButton.Visible = true
	self.pushButton.BackgroundColor3 = PUSH_ACTIVE_COLOR
	self.pushButton.TextColor3 = Color3.fromRGB(30, 25, 10)

	stopSweep(self)
	self.sweepBaseProgress = state.elapsedShare
	self.sweepElapsed = 0
	local sweepSeconds = state.sweepSeconds
	local curve = state.curve
	self.sweepConnection = RunService.RenderStepped:Connect(function(dt: number)
		self.sweepElapsed += dt
		local share = math.min(1, self.sweepBaseProgress + self.sweepElapsed / sweepSeconds)
		self.needle.Position = UDim2.new(Sweep.At(curve, share), 0, 0, 0)
	end)
end

function MusicUI.IsRunning(self: MusicUIHandle): boolean
	return self.running
end

function MusicUI.OnPushActivated(self: MusicUIHandle, callback: () -> ())
	self.pushButton.Activated:Connect(callback)
end

return MusicUI
