--!strict
-- Floating money numbers that drift up and fade. Spawned on every money change
-- so the player sees exactly how much they gained or lost, and in which direction.
--
-- Green for earnings, red for spending. Stacked vertically so rapid changes
-- don't overwrite each other -- each pop gets its own lane.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Money = require(ReplicatedStorage:WaitForChild("Money"))

local MoneyPop = {}

type Pop = {
	label: TextLabel,
	lane: number,
}

local pops: { Pop } = {}

-- Show a floating number at a world position. `amount` is positive for gains,
-- negative for losses. `worldPos` is optional: if omitted the pop appears at
-- the centre of the screen instead.
function MoneyPop.Show(worldPos: Vector3?, amount: number)
	local player = Players.LocalPlayer
	local character = player.Character
	if character == nil then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp == nil then
		return
	end

	local screenGui = player:FindFirstChild("PlayerGui"):WaitForChild("AgesHUD", 5)
	if screenGui == nil then
		return
	end

	local delta = amount
	local text = (if delta >= 0 then "+" else "") .. Money.Format(delta)
	local color = if delta >= 0
		then Color3.fromRGB(90, 220, 130)
		else Color3.fromRGB(230, 90, 90)

	local label = Instance.new("TextLabel")
	label.Name = "MoneyPop"
	label.Text = text
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = screenGui

	-- Position: project world position to screen, or centre.
	local absPos: Vector2
	if worldPos ~= nil then
		local vp = workspace.CurrentCamera
		if vp ~= nil then
			local screenPos = vp:WorldToScreenPoint(worldPos)
			absPos = Vector2.new(screenPos.X, screenPos.Y)
		else
			absPos = Vector2.new(0, 0)
		end
	else
		local vp = workspace.CurrentCamera
		if vp ~= nil then
			absPos = Vector2.new(vp.ViewportSize.X / 2, vp.ViewportSize.Y / 2 - 60)
		else
			absPos = Vector2.new(0, 0)
		end
	end

	label.Position = UDim2.new(0, absPos.X - label.TextBounds.X / 2, 0, absPos.Y)

	-- Stagger lanes so pops do not overlap.
	local laneOffset = #pops * 24
	label.Position = UDim2.new(
		0,
		label.Position.X.Offset,
		0,
		label.Position.Y.Offset - laneOffset
	)

	local tweenService = game:GetService("TweenService")
	local tweenInfo = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0)
	local goal = {
		Position = UDim2.new(
			0,
			label.Position.X.Offset,
			0,
			label.Position.Y.Offset - 80
		),
		TextTransparency = 1,
	}
	tweenService:Create(label, tweenInfo, goal):Play()

	task.delay(1.5, function()
		label:Destroy()
	end)

	-- Keep the pops array bounded.
	if #pops > 5 then
		table.remove(pops, 1)
	end
	table.insert(pops, { label = label, lane = laneOffset })
end

return MoneyPop
