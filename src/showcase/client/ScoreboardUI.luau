--!strict
-- The ring record board. Opens on a click, closes on anything.
--
-- Same palette and the same build-it-in-code approach as the other two panels, and the same
-- reason: the colours live in one table and the whole thing is version-controlled as text.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local showcase = ReplicatedStorage:WaitForChild("Showcase")
local Records = require(showcase:WaitForChild("Records"))
local ShowScoreboard = showcase:WaitForChild("Remotes"):WaitForChild("ShowScoreboard") :: RemoteEvent

local GROUND = Color3.fromRGB(17, 18, 22)
local PANEL = Color3.fromRGB(25, 27, 32)
local EDGE = Color3.fromRGB(43, 47, 55)
local INK = Color3.fromRGB(226, 222, 213)
local INK_DIM = Color3.fromRGB(124, 122, 116)
local SUN = Color3.fromRGB(240, 178, 104)

local FADE = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ROW_HEIGHT = 34

local ScoreboardUI = {}

local gui: ScreenGui? = nil
local shade: Frame? = nil
local titleLabel: TextLabel? = nil
local subtitleLabel: TextLabel? = nil
local rows: Frame? = nil
local closeConnection: RBXScriptConnection? = nil

-- ---------------------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------------------

local function text(parent: Instance, size: number, colour: Color3, font: Enum.Font): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.TextSize = size
	t.TextColor3 = colour
	t.Font = font
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Text = ""
	t.Parent = parent
	return t
end

local function playerGui(): Instance
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "ScoreboardUI"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 25
	screen.Enabled = false
	screen.Parent = playerGui()

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = GROUND
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Parent = screen

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0, 520, 0, 108 + ROW_HEIGHT * 6)
	panel.BackgroundColor3 = PANEL
	panel.BorderSizePixel = 0
	panel.Parent = dim

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = EDGE
	stroke.Thickness = 1
	stroke.Parent = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 26)
	pad.PaddingLeft = UDim.new(0, 28)
	pad.PaddingRight = UDim.new(0, 28)
	pad.Parent = panel

	local title = text(panel, 20, SUN, Enum.Font.GothamBold)
	title.Size = UDim2.new(1, 0, 0, 24)

	local subtitle = text(panel, 13, INK_DIM, Enum.Font.Gotham)
	subtitle.Position = UDim2.new(0, 0, 0, 26)
	subtitle.Size = UDim2.new(1, 0, 0, 18)

	-- Column heads. Wins and losses are right-aligned and monospaced so the digits line up --
	-- a scoreboard whose numbers do not form a column is the one thing that makes a records
	-- board look improvised.
	local heads = { { "#", 0, 30 }, { "NAME", 34, 200 }, { "HOUSE", 240, 110 }, { "W", 372, 50 }, { "L", 430, 50 } }
	for _, head in heads do
		local h = text(panel, 11, INK_DIM, Enum.Font.GothamMedium)
		h.Position = UDim2.new(0, head[2] :: number, 0, 56)
		h.Size = UDim2.new(0, head[3] :: number, 0, 14)
		h.Text = head[1] :: string
		if head[1] == "W" or head[1] == "L" then
			h.TextXAlignment = Enum.TextXAlignment.Right
		end
	end

	local rule = Instance.new("Frame")
	rule.Position = UDim2.new(0, 0, 0, 74)
	rule.Size = UDim2.new(1, 0, 0, 1)
	rule.BackgroundColor3 = EDGE
	rule.BorderSizePixel = 0
	rule.Parent = panel

	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Position = UDim2.new(0, 0, 0, 82)
	list.Size = UDim2.new(1, 0, 0, ROW_HEIGHT * 6)
	list.Parent = panel

	gui, shade, titleLabel, subtitleLabel, rows = screen, dim, title, subtitle, list
end

local function paint(ring: Records.Ring)
	local list, title, subtitle = rows, titleLabel, subtitleLabel
	if list == nil or title == nil or subtitle == nil then
		return
	end
	title.Text = ring.Title
	subtitle.Text = ring.Subtitle

	list:ClearAllChildren()
	for index, entry in ring.Entries do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Position = UDim2.new(0, 0, 0, (index - 1) * ROW_HEIGHT)
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.Parent = list

		-- The leader is the only row that gets the accent. Highlighting three of six is not a
		-- ranking, it is a gradient.
		local colour = if index == 1 then SUN else INK

		local columns = {
			{ tostring(entry.Rank), 0, 30, Enum.TextXAlignment.Left, Enum.Font.RobotoMono },
			{ entry.Name, 34, 200, Enum.TextXAlignment.Left, Enum.Font.Gotham },
			{ entry.House, 240, 110, Enum.TextXAlignment.Left, Enum.Font.Gotham },
			{ tostring(entry.Wins), 372, 50, Enum.TextXAlignment.Right, Enum.Font.RobotoMono },
			{ tostring(entry.Losses), 430, 50, Enum.TextXAlignment.Right, Enum.Font.RobotoMono },
		}
		for _, column in columns do
			local cell = text(row, 14, colour, column[5] :: Enum.Font)
			cell.Position = UDim2.new(0, column[2] :: number, 0, 8)
			cell.Size = UDim2.new(0, column[3] :: number, 0, 18)
			cell.Text = column[1] :: string
			cell.TextXAlignment = column[4] :: Enum.TextXAlignment
		end
	end
end

-- ---------------------------------------------------------------------------------------
-- Open / close
-- ---------------------------------------------------------------------------------------

function ScoreboardUI.Close()
	local screen, dim = gui, shade
	if screen == nil or dim == nil or not screen.Enabled then
		return
	end
	if closeConnection ~= nil then
		closeConnection:Disconnect()
		closeConnection = nil
	end
	local tween = TweenService:Create(dim, FADE, { BackgroundTransparency = 1 })
	tween.Completed:Once(function()
		screen.Enabled = false
	end)
	tween:Play()
end

function ScoreboardUI.Open(ringId: string)
	local screen, dim = gui, shade
	if screen == nil or dim == nil then
		return
	end
	local ring = Records.ByRing[ringId] or Records.ByRing[Records.DefaultRing]
	if ring == nil then
		return
	end
	paint(ring)

	screen.Enabled = true
	dim.BackgroundTransparency = 1
	TweenService:Create(dim, FADE, { BackgroundTransparency = 0.4 }):Play()

	closeConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape
			or input.KeyCode == Enum.KeyCode.E
			or input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			ScoreboardUI.Close()
		end
	end)
end

function ScoreboardUI.Start()
	build()
	ShowScoreboard.OnClientEvent:Connect(function(ringId: string)
		ScoreboardUI.Open(ringId)
	end)
end

return ScoreboardUI
