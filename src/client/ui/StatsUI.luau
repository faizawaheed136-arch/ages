--!strict
-- Minimal always-visible HUD: age, life stage, progress toward the automatic
-- age-up, the Age Up button, and the four primary stats. Step 1 goal is
-- "working numbers", not final art — polish comes later in the build order.
--
-- This module renders server state and reports button presses. It never
-- decides whether aging up is allowed; that verdict arrives from the server.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Types"))

type Stats = Types.Stats
type StatName = Types.StatName
type ManualAgeUpState = Types.ManualAgeUpState

local STAT_ORDER: { { name: StatName, label: string } } = {
	{ name = "health", label = "Health" },
	{ name = "happiness", label = "Happiness" },
	{ name = "smarts", label = "Smarts" },
	{ name = "looks", label = "Looks" },
}

local READY_COLOR = Color3.fromRGB(235, 190, 90)
local SKIP_COLOR = Color3.fromRGB(70, 70, 82)
local COOLDOWN_COLOR = Color3.fromRGB(52, 52, 60)
local PROGRESS_COLOR = Color3.fromRGB(110, 160, 220)
local GOOD_STAT_COLOR = Color3.fromRGB(90, 200, 120)
local WARN_STAT_COLOR = Color3.fromRGB(210, 60, 60)

local StatsUI = {}
StatsUI.__index = StatsUI

export type StatsUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		ageLabel: TextLabel,
		stageLabel: TextLabel,
		progressFill: Frame,
		progressCaption: TextLabel,
		ageUpButton: TextButton,
		noticeFrame: Frame,
		noticeLabel: TextLabel,
		noticeToken: number,
		deathFrame: Frame,
		deathLabel: TextLabel,
		statBars: { [StatName]: { fill: Frame, label: TextLabel } },
	},
	StatsUI
))

local function formatDuration(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function makeStatRow(parent: Instance, order: number, label: string): { fill: Frame, label: TextLabel }
	local row = Instance.new("Frame")
	row.Name = label .. "Row"
	row.Size = UDim2.new(1, 0, 0, 28)
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Parent = parent

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 10)
	track.Position = UDim2.new(0, 0, 1, -10)
	track.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	track.BorderSizePixel = 0
	track.Parent = row

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = GOOD_STAT_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Label"
	textLabel.Size = UDim2.new(1, 0, 0, 18)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.GothamMedium
	textLabel.TextSize = 14
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
	textLabel.Text = label .. ": --"
	textLabel.Parent = row

	return { fill = fill, label = textLabel }
end

function StatsUI.new(): StatsUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local panel = Instance.new("Frame")
	panel.Name = "StatsPanel"
	-- Height follows its contents so hiding the Age Up button in the earliest
	-- years doesn't leave a hole in the panel.
	panel.Size = UDim2.new(0, 220, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 16)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
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
	layout.Padding = UDim.new(0, 4)
	layout.Parent = panel

	local ageLabel = Instance.new("TextLabel")
	ageLabel.Name = "AgeLabel"
	ageLabel.Size = UDim2.new(1, 0, 0, 20)
	ageLabel.BackgroundTransparency = 1
	ageLabel.Font = Enum.Font.GothamBold
	ageLabel.TextSize = 16
	ageLabel.TextXAlignment = Enum.TextXAlignment.Left
	ageLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	ageLabel.Text = "Age: --"
	ageLabel.LayoutOrder = 0
	ageLabel.Parent = panel

	local stageLabel = Instance.new("TextLabel")
	stageLabel.Name = "StageLabel"
	stageLabel.Size = UDim2.new(1, 0, 0, 16)
	stageLabel.BackgroundTransparency = 1
	stageLabel.Font = Enum.Font.Gotham
	stageLabel.TextSize = 13
	stageLabel.TextXAlignment = Enum.TextXAlignment.Left
	stageLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
	stageLabel.Text = "Childhood"
	stageLabel.LayoutOrder = 1
	stageLabel.Parent = panel

	local progressRow = Instance.new("Frame")
	progressRow.Name = "AutoAgeUpRow"
	progressRow.Size = UDim2.new(1, 0, 0, 24)
	progressRow.LayoutOrder = 2
	progressRow.BackgroundTransparency = 1
	progressRow.Parent = panel

	local progressCaption = Instance.new("TextLabel")
	progressCaption.Name = "Caption"
	progressCaption.Size = UDim2.new(1, 0, 0, 14)
	progressCaption.BackgroundTransparency = 1
	progressCaption.Font = Enum.Font.Gotham
	progressCaption.TextSize = 11
	progressCaption.TextXAlignment = Enum.TextXAlignment.Left
	progressCaption.TextColor3 = Color3.fromRGB(140, 140, 155)
	progressCaption.Text = "Growing up"
	progressCaption.Parent = progressRow

	local progressTrack = Instance.new("Frame")
	progressTrack.Name = "Track"
	progressTrack.Size = UDim2.new(1, 0, 0, 4)
	progressTrack.Position = UDim2.new(0, 0, 1, -4)
	progressTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	progressTrack.BorderSizePixel = 0
	progressTrack.Parent = progressRow

	local progressFill = Instance.new("Frame")
	progressFill.Name = "Fill"
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.BackgroundColor3 = PROGRESS_COLOR
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressTrack

	local statBars: { [StatName]: { fill: Frame, label: TextLabel } } = {}
	for i, entry in STAT_ORDER do
		statBars[entry.name] = makeStatRow(panel, i + 2, entry.label)
	end

	local ageUpButton = Instance.new("TextButton")
	ageUpButton.Name = "AgeUpButton"
	ageUpButton.Size = UDim2.new(1, 0, 0, 32)
	ageUpButton.LayoutOrder = #STAT_ORDER + 3
	ageUpButton.BackgroundColor3 = COOLDOWN_COLOR
	ageUpButton.BorderSizePixel = 0
	ageUpButton.AutoButtonColor = false
	ageUpButton.Font = Enum.Font.GothamBold
	ageUpButton.TextSize = 15
	ageUpButton.TextColor3 = Color3.fromRGB(120, 120, 130)
	ageUpButton.Text = "Age Up"
	ageUpButton.Visible = false
	ageUpButton.Parent = panel

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = ageUpButton

	local noticeFrame = Instance.new("Frame")
	noticeFrame.Name = "Notice"
	noticeFrame.AnchorPoint = Vector2.new(0.5, 1)
	noticeFrame.Position = UDim2.new(0.5, 0, 1, -48)
	noticeFrame.Size = UDim2.new(0, 420, 0, 40)
	noticeFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	noticeFrame.BackgroundTransparency = 1
	noticeFrame.BorderSizePixel = 0
	noticeFrame.Visible = false
	noticeFrame.Parent = screenGui

	local noticeCorner = Instance.new("UICorner")
	noticeCorner.CornerRadius = UDim.new(0, 8)
	noticeCorner.Parent = noticeFrame

	local noticeLabel = Instance.new("TextLabel")
	noticeLabel.Name = "Label"
	noticeLabel.Size = UDim2.new(1, -24, 1, 0)
	noticeLabel.Position = UDim2.new(0, 12, 0, 0)
	noticeLabel.BackgroundTransparency = 1
	noticeLabel.Font = Enum.Font.Gotham
	noticeLabel.TextSize = 14
	noticeLabel.TextColor3 = Color3.fromRGB(225, 225, 235)
	noticeLabel.TextTransparency = 1
	noticeLabel.Text = ""
	noticeLabel.Parent = noticeFrame

	local deathFrame = Instance.new("Frame")
	deathFrame.Name = "DeathScreen"
	deathFrame.Size = UDim2.new(1, 0, 1, 0)
	deathFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	deathFrame.BackgroundTransparency = 0.35
	deathFrame.Visible = false
	deathFrame.ZIndex = 10
	deathFrame.Parent = screenGui

	local deathLabel = Instance.new("TextLabel")
	deathLabel.Name = "DeathLabel"
	deathLabel.Size = UDim2.new(0, 500, 0, 80)
	deathLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	deathLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	deathLabel.BackgroundTransparency = 1
	deathLabel.Font = Enum.Font.GothamBold
	deathLabel.TextSize = 28
	deathLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	deathLabel.Text = ""
	deathLabel.ZIndex = 11
	deathLabel.Parent = deathFrame

	screenGui.Parent = playerGui

	return setmetatable({
		screenGui = screenGui,
		ageLabel = ageLabel,
		stageLabel = stageLabel,
		progressFill = progressFill,
		progressCaption = progressCaption,
		ageUpButton = ageUpButton,
		noticeFrame = noticeFrame,
		noticeLabel = noticeLabel,
		noticeToken = 0,
		deathFrame = deathFrame,
		deathLabel = deathLabel,
		statBars = statBars,
	}, StatsUI)
end

function StatsUI.SetAge(self: StatsUIHandle, years: number)
	self.ageLabel.Text = `Age: {years}`
end

function StatsUI.SetStage(self: StatsUIHandle, stage: string)
	self.stageLabel.Text = stage
end

function StatsUI.OnAgeUpActivated(self: StatsUIHandle, callback: () -> ())
	self.ageUpButton.Activated:Connect(callback)
end

function StatsUI.SetAgeUpProgress(self: StatsUIHandle, seconds: number, thresholdSeconds: number, state: ManualAgeUpState)
	local fraction = if thresholdSeconds > 0 then math.clamp(seconds / thresholdSeconds, 0, 1) else 0
	self.progressFill.Size = UDim2.new(fraction, 0, 1, 0)

	-- Through the early years the year is something happening to the player
	-- rather than something they end — true whether or not a skip is on offer.
	local childhood = state == "Hidden" or state == "SkipChildhood"
	-- The bar names what it fills toward but never how long that takes. The
	-- threshold is a real-world duration, so showing it both broke the fiction
	-- and told the player the game would advance itself if they sat still.
	self.progressCaption.Text = if childhood then "Growing up" else "Next year"

	self.ageUpButton.Visible = state ~= "Hidden"
	if state == "SkipChildhood" then
		-- Offered only on a life after the first. Muted rather than gold: it is
		-- an escape hatch for someone who has been here before, not the thing
		-- the screen is inviting a new player to press.
		self.ageUpButton.Text = "Skip Childhood"
		self.ageUpButton.BackgroundColor3 = SKIP_COLOR
		self.ageUpButton.TextColor3 = Color3.fromRGB(215, 215, 225)
	elseif state == "Ready" then
		self.ageUpButton.Text = "Age Up"
		self.ageUpButton.BackgroundColor3 = READY_COLOR
		self.ageUpButton.TextColor3 = Color3.fromRGB(30, 25, 10)
	else
		-- Count the wait down rather than just greying out: at a minute-long
		-- cooldown an unexplained dead button reads as a bug, not a rule.
		local remaining = math.max(0, Config.ManualAgeUpCooldownSeconds - seconds)
		self.ageUpButton.Text = `Age Up ({formatDuration(remaining)})`
		self.ageUpButton.BackgroundColor3 = COOLDOWN_COLOR
		self.ageUpButton.TextColor3 = Color3.fromRGB(120, 120, 130)
	end
end

-- A passive, expected event — it fades in at the bottom of the screen and
-- leaves on its own. Deliberately not styled like an error.
function StatsUI.ShowNotice(self: StatsUIHandle, text: string)
	self.noticeToken += 1
	local token = self.noticeToken

	self.noticeLabel.Text = text
	self.noticeFrame.Visible = true

	local fadeIn = TweenInfo.new(Config.UI.NoticeFadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(self.noticeFrame, fadeIn, { BackgroundTransparency = 0.2 }):Play()
	TweenService:Create(self.noticeLabel, fadeIn, { TextTransparency = 0 }):Play()

	task.delay(Config.UI.NoticeSeconds, function()
		-- A newer notice has taken over this frame; leave it alone.
		if self.noticeToken ~= token then
			return
		end
		local fadeOut = TweenInfo.new(Config.UI.NoticeFadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(self.noticeFrame, fadeOut, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(self.noticeLabel, fadeOut, { TextTransparency = 1 }):Play()

		task.delay(Config.UI.NoticeFadeSeconds, function()
			if self.noticeToken == token then
				self.noticeFrame.Visible = false
			end
		end)
	end)
end

function StatsUI.SetStats(self: StatsUIHandle, stats: Stats)
	for _, entry in STAT_ORDER do
		local bar = self.statBars[entry.name]
		local value = (stats :: any)[entry.name] :: number
		bar.fill.Size = UDim2.new(value / Config.Stats.Max, 0, 1, 0)
		bar.label.Text = `{entry.label}: {value}`

		if value <= Config.Stats.WarningThreshold then
			bar.fill.BackgroundColor3 = WARN_STAT_COLOR
			bar.label.TextColor3 = Color3.fromRGB(255, 140, 140)
		else
			bar.fill.BackgroundColor3 = GOOD_STAT_COLOR
			bar.label.TextColor3 = Color3.fromRGB(235, 235, 235)
		end
	end
end

function StatsUI.ShowDeath(self: StatsUIHandle, ageYears: number)
	self.deathLabel.Text = `You died at age {ageYears}.\nRestarting...`
	self.deathFrame.Visible = true
end

function StatsUI.HideDeath(self: StatsUIHandle)
	self.deathFrame.Visible = false
end

return StatsUI
