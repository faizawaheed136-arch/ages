--!strict
-- The chapter reel: a plain text list of what happened since the last band
-- boundary, followed by a single Continue button. The screen is a read, not
-- a choice — there is nothing to click on the moments, and the only input is
-- "I have read enough, keep going."
--
-- Suppressed when the moment list is empty. A slide deck of filler teaches
-- the player to skip it permanently; a zero-moment break is honest and goes
-- straight through. The client checks the list length before opening.
--
-- While the reel is up the world is frozen: the server does not fire ambient
-- events, NPCs do not move, and the age-up progress bar does not fill. The
-- seam is the only time the game is allowed to be still.
--
-- Centered on screen, DisplayOrder above the HUD so it covers everything
-- without touching the HUD's own layout. The parent ScreenGui is hidden
-- alongside the HUD on death.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Types"))

type Moment = Types.Moment

local ChapterReel = {}
ChapterReel.__index = ChapterReel

export type ChapterReelHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		frame: Frame,
		backdrop: Frame,
		titleLabel: TextLabel,
		momentsList: Frame,
		continueButton: TextButton,
		onContinueActivated: (() -> ())?,
	},
	ChapterReel
))

function ChapterReel.new(): ChapterReelHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesChapterReel"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 10
	screenGui.Parent = playerGui

	-- Backdrop dims the world behind the reel. Opaque enough to read, dark
	-- enough that the player cannot see what is still happening on the other
	-- side of the seam.
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	backdrop.BackgroundTransparency = 0.55
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.new(0, 560, 0, 420)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 24)
	padding.PaddingBottom = UDim.new(0, 20)
	padding.PaddingLeft = UDim.new(0, 28)
	padding.PaddingRight = UDim.new(0, 28)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Parent = panel

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 28)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 20
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.TextColor3 = Color3.fromRGB(236, 238, 245)
	titleLabel.Text = "CHAPTER COMPLETE"
	titleLabel.LayoutOrder = 0
	titleLabel.Parent = panel

	local momentsList = Instance.new("Frame")
	momentsList.Name = "MomentsList"
	momentsList.Size = UDim2.new(1, 0, 0, 0)
	momentsList.BackgroundTransparency = 1
	momentsList.LayoutOrder = 1
	momentsList.Parent = panel

	local momentsLayout = Instance.new("UIListLayout")
	momentsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	momentsLayout.Padding = UDim.new(0, 6)
	momentsLayout.FillDirection = Enum.FillDirection.Vertical
	momentsLayout.Parent = momentsList

	local continueButton = Instance.new("TextButton")
	continueButton.Name = "Continue"
	continueButton.Size = UDim2.new(1, 0, 0, 44)
	continueButton.BackgroundTransparency = 1
	continueButton.Font = Enum.Font.GothamBold
	continueButton.TextSize = 18
	continueButton.Text = "Continue"
	continueButton.TextColor3 = Color3.fromRGB(236, 238, 245)
	continueButton.TextWrapped = false
	continueButton.AutoButtonColor = false
	continueButton.LayoutOrder = 2
	continueButton.Parent = panel

	local self = setmetatable({
		screenGui = screenGui,
		frame = panel,
		backdrop = backdrop,
		titleLabel = titleLabel,
		momentsList = momentsList,
		continueButton = continueButton,
		onContinueActivated = nil,
	}, ChapterReel) :: ChapterReelHandle

	continueButton.MouseButton1Click:Connect(function()
		local handler = self.onContinueActivated
		if handler ~= nil then
			handler()
		end
	end)

	return self
end

function ChapterReel.OnContinueActivated(self: ChapterReelHandle, handler: () -> ())
	self.onContinueActivated = handler
end

-- Push a new reel state. `nil` hides the panel; a non-nil state opens it with
-- the given moments. An empty moments list suppresses the screen — the client
-- stays at the title with nothing to read and the player presses Continue
-- immediately.
function ChapterReel.Set(self: ChapterReelHandle, ageMonths: number, moments: { Moment }?)
	if moments == nil or #moments == 0 then
		self.backdrop.Visible = false
		self.frame.Visible = false
		return
	end

	self.backdrop.Visible = true
	self.frame.Visible = true

	-- Age label: "You turned N" or similar, centered above the list.
	local ageYears = ageMonths // 12
	self.titleLabel.Text = `Chapter break — age {ageYears}`

	-- Clear old moment rows.
	for _, child in self.momentsList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	-- Build the list. Each row is a single line: "At age N, ..."
	for _, moment in moments do
		local row = Instance.new("TextLabel")
		row.Name = "Moment"
		row.Size = UDim2.new(1, 0, 0, 22)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.Gotham
		row.TextSize = 14
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = Color3.fromRGB(200, 202, 210)
		row.TextWrapped = true
		row.Text = moment.line
		row.LayoutOrder = moment.ageMonths
		row.Parent = self.momentsList
	end
end

function ChapterReel.Hide(self: ChapterReelHandle)
	self.backdrop.Visible = false
	self.frame.Visible = false
end

return ChapterReel
