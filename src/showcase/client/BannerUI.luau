--!strict
-- The period announcement: one bar across the top, gone in six seconds.
--
-- Built in code for the same reason WardrobeUI is -- the palette lives in one table, and the
-- whole panel is version-controlled as text rather than as a binary ScreenGui.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local showcase = ReplicatedStorage:WaitForChild("Showcase")
local Schedule = require(showcase:WaitForChild("Schedule"))
local PeriodChanged = showcase:WaitForChild("Remotes"):WaitForChild("PeriodChanged") :: RemoteEvent

local GROUND = Color3.fromRGB(17, 18, 22)
local EDGE = Color3.fromRGB(43, 47, 55)
local INK = Color3.fromRGB(226, 222, 213)
local INK_DIM = Color3.fromRGB(124, 122, 116)
local SUN = Color3.fromRGB(240, 178, 104)
local ALERT = Color3.fromRGB(196, 85, 63)

local SLIDE_IN = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local HOLD_SECONDS = 5

local HIDDEN = UDim2.new(0.5, 0, 0, -96)
local SHOWN = UDim2.new(0.5, 0, 0, 44)

local BannerUI = {}

local banner: Frame? = nil
local rule: Frame? = nil
local title: TextLabel? = nil
local subtitle: TextLabel? = nil
local status: TextLabel? = nil

local showToken = 0
local currentKey: string? = nil
local endsAt = 0

-- ---------------------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------------------

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "BannerUI"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 30
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local bar = Instance.new("Frame")
	bar.Name = "Banner"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = HIDDEN
	bar.Size = UDim2.new(0, 620, 0, 76)
	bar.BackgroundColor3 = GROUND
	bar.BackgroundTransparency = 0.08
	bar.BorderSizePixel = 0
	bar.Parent = screen

	local edge = Instance.new("UIStroke")
	edge.Color = EDGE
	edge.Thickness = 1
	edge.Parent = bar

	local fit = Instance.new("UISizeConstraint")
	fit.MaxSize = Vector2.new(620, 76)
	fit.Parent = bar

	-- The accent rule down the left edge. It is the only thing that changes colour between a
	-- routine period and lockdown -- which is enough, and cheaper to read at a glance than
	-- recolouring the text.
	local accent = Instance.new("Frame")
	accent.Name = "Rule"
	accent.Size = UDim2.new(0, 3, 1, 0)
	accent.BackgroundColor3 = SUN
	accent.BorderSizePixel = 0
	accent.Parent = bar

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 26)
	pad.PaddingRight = UDim.new(0, 22)
	pad.PaddingTop = UDim.new(0, 15)
	pad.Parent = bar

	local head = Instance.new("TextLabel")
	head.Name = "Title"
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, -110, 0, 22)
	head.Font = Enum.Font.GothamBold
	head.TextSize = 17
	head.TextColor3 = INK
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.TextTruncate = Enum.TextTruncate.AtEnd
	head.Text = ""
	head.Parent = bar

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.new(0, 0, 0, 26)
	sub.Size = UDim2.new(1, -110, 0, 18)
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 13
	sub.TextColor3 = INK_DIM
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = ""
	sub.Parent = bar

	-- Countdown, top right. Computed locally from the shared Schedule rather than pushed from
	-- the server -- a per-second remote to every client, forever, to render a number the client
	-- can work out for itself.
	local clock = Instance.new("TextLabel")
	clock.Name = "Status"
	clock.BackgroundTransparency = 1
	clock.AnchorPoint = Vector2.new(1, 0)
	clock.Position = UDim2.new(1, 0, 0, 2)
	clock.Size = UDim2.new(0, 100, 0, 40)
	clock.Font = Enum.Font.RobotoMono
	clock.TextSize = 15
	clock.TextColor3 = SUN
	clock.TextXAlignment = Enum.TextXAlignment.Right
	clock.Text = ""
	clock.Parent = bar

	banner, rule, title, subtitle, status = bar, accent, head, sub, clock
end

-- ---------------------------------------------------------------------------------------
-- Show / hide
-- ---------------------------------------------------------------------------------------

local function hide()
	local bar = banner
	if bar == nil then
		return
	end
	TweenService:Create(bar, SLIDE_OUT, { Position = HIDDEN }):Play()
end

local function show(period: Schedule.Period)
	local bar, accent, head, sub = banner, rule, title, subtitle
	if bar == nil or accent == nil or head == nil or sub == nil then
		return
	end

	head.Text = period.Banner
	sub.Text = `Next: {Schedule.After(period.Key).Name}`
	accent.BackgroundColor3 = if period.Tone == "alert" then ALERT else SUN

	-- **Token, not a timer handle.** Two periods can in principle land close together, and the
	-- naive version -- start a 5-second task.delay(hide) each time -- has the first banner's
	-- timer hiding the second banner mid-display. Bumping a counter and checking it on wake
	-- means only the most recent show can retract.
	showToken += 1
	local token = showToken

	TweenService:Create(bar, SLIDE_IN, { Position = SHOWN }):Play()
	task.delay(HOLD_SECONDS, function()
		if token == showToken then
			hide()
		end
	end)
end

-- ---------------------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------------------

function BannerUI.Start()
	build()

	PeriodChanged.OnClientEvent:Connect(function(key: string, remaining: number, transition: boolean)
		local period = Schedule.ByKey[key]
		if period == nil then
			return
		end
		currentKey = key
		endsAt = workspace:GetServerTimeNow() + remaining
		-- No banner on join. A player who has just loaded in did not miss anything, and an
		-- announcement they had no part in reads as a bug.
		if transition then
			show(period)
		end
	end)

	RunService.Heartbeat:Connect(function()
		local clock = status
		if clock == nil or currentKey == nil then
			return
		end
		local left = math.max(endsAt - workspace:GetServerTimeNow(), 0)
		clock.Text = string.format("%d:%02d", left // 60, left % 60)
	end)
end

return BannerUI
