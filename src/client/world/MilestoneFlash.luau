--!strict
-- Milestone celebration: a full-screen flash with the milestone name and bonus.
-- Shows for 1.5 seconds, gold gradient overlay with large text.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Money = require(ReplicatedStorage:WaitForChild("Money"))

local MilestoneFlash = {}

-- Show a milestone celebration. `label` is the milestone name (e.g. "First House"),
-- `bonus` is the credit amount awarded.
function MilestoneFlash.Show(label: string, bonus: number)
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChild("PlayerGui")
	if playerGui == nil then
		return
	end

	local overlay = Instance.new("Frame")
	overlay.Name = "MilestoneFlash"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundTransparency = 1
	overlay.ZIndex = 20
	overlay.Parent = playerGui

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 215, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 180, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 215, 0)),
	})
	gradient.Parent = overlay

	local bg = Instance.new("Frame")
	bg.Name = "Bg"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(20, 15, 5)
	bg.BackgroundTransparency = 0.6
	bg.ZIndex = 21
	bg.Parent = overlay

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 0)
	corner.Parent = bg

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(0.8, 0, 0, 60)
	titleLabel.Position = UDim2.new(0.1, 0, 0.2, 0)
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = label .. "!"
	titleLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 36
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.ZIndex = 22
	titleLabel.Parent = overlay

	local bonusLabel = Instance.new("TextLabel")
	bonusLabel.Name = "Bonus"
	bonusLabel.Size = UDim2.new(0.6, 0, 0, 40)
	bonusLabel.Position = UDim2.new(0.2, 0, 0.35, 0)
	bonusLabel.AnchorPoint = Vector2.new(0.5, 0)
	bonusLabel.BackgroundTransparency = 1
	bonusLabel.Text = "+" .. Money.Format(bonus) .. " credits"
	bonusLabel.TextColor3 = Color3.fromRGB(200, 255, 150)
	bonusLabel.Font = Enum.Font.GothamBold
	bonusLabel.TextSize = 28
	bonusLabel.TextXAlignment = Enum.TextXAlignment.Center
	bonusLabel.ZIndex = 22
	bonusLabel.Parent = overlay

	task.delay(1.5, function()
		overlay:Destroy()
	end)
end

return MilestoneFlash
