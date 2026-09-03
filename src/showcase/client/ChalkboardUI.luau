--!strict
-- The chalkboard panel: one question, four options, a score.
--
-- It knows the prompts and the options, because Chalkboard.luau is replicated. It does **not**
-- know which option is right -- the key never leaves the server. So this panel cannot tell you
-- whether you were correct until the server's next push says the score went up, and that is the
-- design rather than a limitation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local showcase = ReplicatedStorage:WaitForChild("Showcase")
local Chalkboard = require(showcase:WaitForChild("Chalkboard"))
local remotes = showcase:WaitForChild("Remotes")
local ShowLesson = remotes:WaitForChild("ShowLesson") :: RemoteEvent
local AnswerLesson = remotes:WaitForChild("AnswerLesson") :: RemoteEvent

local GROUND = Color3.fromRGB(17, 18, 22)
local SLATE = Color3.fromRGB(32, 42, 38)
local EDGE = Color3.fromRGB(58, 74, 66)
local CHALK = Color3.fromRGB(232, 236, 226)
local SUN = Color3.fromRGB(240, 178, 104)

local FADE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local ChalkboardUI = {}

local gui: ScreenGui? = nil
local panel: Frame? = nil
local promptLabel: TextLabel? = nil
local scoreLabel: TextLabel? = nil
local buttons: { TextButton } = {}
local locked = false

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "ChalkboardUI"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 24
	screen.Enabled = false
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Anchored low, not centred. The desk camera is already looking at the board; a panel over
	-- the middle of the screen would cover the thing the camera was moved to show.
	local board = Instance.new("Frame")
	board.Name = "Board"
	board.AnchorPoint = Vector2.new(0.5, 1)
	board.Position = UDim2.new(0.5, 0, 1, -46)
	board.Size = UDim2.new(0, 620, 0, 210)
	board.BackgroundColor3 = SLATE
	board.BorderSizePixel = 0
	board.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = board
	local stroke = Instance.new("UIStroke")
	stroke.Color = EDGE
	stroke.Thickness = 2
	stroke.Parent = board

	local fit = Instance.new("UISizeConstraint")
	fit.MaxSize = Vector2.new(620, 210)
	fit.Parent = board

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 20)
	pad.PaddingLeft = UDim.new(0, 26)
	pad.PaddingRight = UDim.new(0, 26)
	pad.PaddingBottom = UDim.new(0, 20)
	pad.Parent = board

	local prompt = Instance.new("TextLabel")
	prompt.BackgroundTransparency = 1
	prompt.Size = UDim2.new(1, -110, 0, 46)
	prompt.Font = Enum.Font.GothamBold
	prompt.TextSize = 34
	prompt.TextColor3 = CHALK
	prompt.TextXAlignment = Enum.TextXAlignment.Left
	prompt.Text = ""
	prompt.Parent = board

	local score = Instance.new("TextLabel")
	score.BackgroundTransparency = 1
	score.AnchorPoint = Vector2.new(1, 0)
	score.Position = UDim2.new(1, 0, 0, 6)
	score.Size = UDim2.new(0, 110, 0, 30)
	score.Font = Enum.Font.RobotoMono
	score.TextSize = 15
	score.TextColor3 = SUN
	score.TextXAlignment = Enum.TextXAlignment.Right
	score.Text = ""
	score.Parent = board

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.new(0, 0, 0, 62)
	row.Size = UDim2.new(1, 0, 0, 108)
	row.Parent = board

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -8, 0.5, -8)
	grid.CellPadding = UDim2.fromOffset(16, 12)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = row

	for index = 1, 4 do
		local button = Instance.new("TextButton")
		button.Name = `Option{index}`
		button.LayoutOrder = index
		button.BackgroundColor3 = GROUND
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Font = Enum.Font.Gotham
		button.TextSize = 18
		button.TextColor3 = CHALK
		button.Text = ""
		button.Parent = row

		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 3)
		c.Parent = button
		local s = Instance.new("UIStroke")
		s.Color = EDGE
		s.Parent = button

		button.MouseEnter:Connect(function()
			if not locked then
				TweenService:Create(s, FADE, { Color = SUN }):Play()
			end
		end)
		button.MouseLeave:Connect(function()
			TweenService:Create(s, FADE, { Color = EDGE }):Play()
		end)
		button.Activated:Connect(function()
			if locked then
				return
			end
			-- **Locked until the server answers.** Without this a fast player sends three
			-- answers for one question, and the extras land against whatever question happens to
			-- be current by the time they arrive.
			locked = true
			AnswerLesson:FireServer(index)
		end)

		table.insert(buttons, button)
	end

	gui, panel, promptLabel, scoreLabel = screen, board, prompt, score
end

local function showQuestion(questionId: string?, score: number?, total: number?)
	local screen, prompt, scoreText = gui, promptLabel, scoreLabel
	if screen == nil or prompt == nil or scoreText == nil then
		return
	end

	if questionId == nil then
		if score ~= nil and total ~= nil then
			-- Finished: hold the result up for a moment rather than snapping the panel away,
			-- which reads as the UI crashing.
			prompt.Text = `Lesson complete — {score} of {total}`
			scoreText.Text = ""
			for _, button in buttons do
				button.Text = ""
				button.Visible = false
			end
			task.delay(2.4, function()
				if screen ~= nil then
					screen.Enabled = false
				end
			end)
		else
			screen.Enabled = false
		end
		return
	end

	local index = Chalkboard.ByIdIndex[questionId]
	local question = if index ~= nil then Chalkboard.Questions[index] else nil
	if question == nil then
		return
	end

	prompt.Text = question.Prompt
	scoreText.Text = if score ~= nil and total ~= nil then string.format("%d / %d", score, total) else ""
	for slot, button in buttons do
		local option = question.Options[slot]
		button.Visible = option ~= nil
		button.Text = option or ""
	end
	locked = false
	screen.Enabled = true
end

function ChalkboardUI.Start()
	build()
	ShowLesson.OnClientEvent:Connect(showQuestion)
end

return ChalkboardUI
