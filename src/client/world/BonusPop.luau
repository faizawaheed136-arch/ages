--!strict
-- Distinct money pop for tips, bonuses, and special earnings. Gold color so the
-- player can tell at a glance that this money came from somewhere other than a
-- regular wage or pocket money change.
--
-- Triggered by MoneyService.Add when the reason string matches a known bonus
-- category. Falls back to the green/red pop for everything else.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Money = require(game:GetService("ReplicatedStorage"):WaitForChild("Money"))

local BonusPop = {}

type Pop = {
	label: TextLabel,
}

local pops: { Pop } = {}
local GOLD = Color3.fromRGB(255, 210, 80)
local TEAL = Color3.fromRGB(80, 210, 220)
local LAVENDER = Color3.fromRGB(200, 160, 255)

local BONUS_COLORS: { [string]: Color3 } = {
	["tip"] = GOLD,
	["bonus"] = GOLD,
	["interest"] = TEAL,
	["milestone"] = LAVENDER,
	["gift"] = GOLD,
}

local function pickColor(reason: string?): Color3
	if reason == nil then
		return GOLD
	end
	local lower = reason:lower()
	for keyword, color in BONUS_COLORS do
		if lower:find(keyword, 1, true) ~= nil then
			return color
		end
	end
	return GOLD
end

-- Show a floating bonus number. `amount` is always positive (the caller has
-- already signed it), `worldPos` is optional, and `reason` is human-readable
-- text the player may never see but the color logic uses to pick the tint.
function BonusPop.Show(worldPos: Vector3?, amount: number, reason: string?)
	local player = Players.LocalPlayer
	local screenGui = player:FindFirstChild("PlayerGui"):FindFirstChild("AgesHUD")
	if screenGui == nil then
		return
	 end

	local text = "+" .. Money.Format(amount)
	local color = pickColor(reason)

	local label = Instance.new("TextLabel")
	label.Name = "BonusPop"
	label.Text = text
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = 16
	label.Parent = screenGui

	local absPos: Vector2
	if worldPos ~= nil then
		local vp = workspace.CurrentCamera
		if vp ~= nil then
			local sp = vp:WorldToScreenPoint(worldPos)
			absPos = Vector2.new(sp.X, sp.Y)
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

	local laneOffset = #pops * 24
	label.Position = UDim2.new(
		0,
		label.Position.X.Offset,
		0,
		label.Position.Y.Offset - laneOffset
	)

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
	TweenService:Create(label, tweenInfo, goal):Play()

	task.delay(1.5, function()
		label:Destroy()
	end)

	if #pops > 5 then
		table.remove(pops, 1)
	end
	table.insert(pops, { label = label })
end

return BonusPop
