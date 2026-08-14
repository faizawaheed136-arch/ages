--!strict
-- Bond milestone celebration: a banner that slides in from the right and fades.
-- Shows the relationship milestone reached with a specific person.

local Players = game:GetService("Players")

local BondCelebration = {}

-- Show a bond milestone banner. `person` is the NPC name, `label` is the milestone
-- title (e.g. "Close Friend").
function BondCelebration.Show(person: string, label: string)
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChild("PlayerGui")
	if playerGui == nil then
		return
	end

	local screenGui = playerGui:WaitForChild("AgesHUD", 5)
	if screenGui == nil then
		return
	end

	local banner = Instance.new("Frame")
	banner.Name = "BondCelebration"
	banner.Size = UDim2.new(0, 320, 0, 50)
	banner.Position = UDim2.new(1, -340, 0.5, -25)
	banner.AnchorPoint = Vector2.new(0, 0.5)
	banner.BackgroundColor3 = Color3.fromRGB(40, 30, 50)
	banner.BackgroundTransparency = 0.2
	banner.BorderSizePixel = 0
	banner.ZIndex = 15
	banner.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = banner

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = banner

	local label1 = Instance.new("TextLabel")
	label1.Name = "Label1"
	label1.Size = UDim2.new(1, 0, 0.5, 0)
	label1.BackgroundTransparency = 1
	label1.Text = `Bond milestone with {person}!`
	label1.TextColor3 = Color3.fromRGB(220, 180, 255)
	label1.Font = Enum.Font.GothamMedium
	label1.TextSize = 14
	label1.TextXAlignment = Enum.TextXAlignment.Left
	label1.ZIndex = 16
	label1.Parent = banner

	local label2 = Instance.new("TextLabel")
	label2.Name = "Label2"
	label2.Size = UDim2.new(1, 0, 0.5, 0)
	label2.Position = UDim2.new(0, 0, 0.5, 0)
	label2.BackgroundTransparency = 1
	label2.Text = label
	label2.TextColor3 = Color3.fromRGB(255, 220, 100)
	label2.Font = Enum.Font.GothamBold
	label2.TextSize = 16
	label2.TextXAlignment = Enum.TextXAlignment.Left
	label2.ZIndex = 16
	label2.Parent = banner

	local tweenService = game:GetService("TweenService")
	local slideIn = tweenService:Create(
		banner,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(1, -20, 0.5, -25) }
	)
	slideIn:Play()

	task.delay(3.5, function()
		local slideOut = tweenService:Create(
			banner,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(1, -340, 0.5, -25), BackgroundTransparency = 1 }
		)
		slideOut:Play()
		task.wait(0.5)
		banner:Destroy()
	end)
end

return BondCelebration
