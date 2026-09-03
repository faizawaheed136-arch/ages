--!strict
-- The vending machine's front panel. Two products, nothing else.
--
-- Same palette and the same build-in-code approach as the other three panels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local showcase = ReplicatedStorage:WaitForChild("Showcase")
local Drinks = require(showcase:WaitForChild("Drinks"))
local remotes = showcase:WaitForChild("Remotes")
local OpenVending = remotes:WaitForChild("OpenVending") :: RemoteEvent
local RequestDrink = remotes:WaitForChild("RequestDrink") :: RemoteEvent

local GROUND = Color3.fromRGB(17, 18, 22)
local PANEL = Color3.fromRGB(25, 27, 32)
local PANEL_HI = Color3.fromRGB(31, 34, 41)
local EDGE = Color3.fromRGB(43, 47, 55)
local INK = Color3.fromRGB(226, 222, 213)
local INK_DIM = Color3.fromRGB(124, 122, 116)
local SUN = Color3.fromRGB(240, 178, 104)

local FADE = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local VendingUI = {}

local gui: ScreenGui? = nil
local shade: Frame? = nil
local closeConnection: RBXScriptConnection? = nil

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "VendingUI"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 22
	screen.Enabled = false
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = GROUND
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Parent = screen

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0, 560, 0, 250)
	panel.BackgroundColor3 = GROUND
	panel.BorderSizePixel = 0
	panel.Parent = dim

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = EDGE
	stroke.Parent = panel

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 24)
	pad.PaddingLeft = UDim.new(0, 24)
	pad.PaddingRight = UDim.new(0, 24)
	pad.PaddingBottom = UDim.new(0, 24)
	pad.Parent = panel

	local heading = Instance.new("TextLabel")
	heading.BackgroundTransparency = 1
	heading.Size = UDim2.new(1, 0, 0, 16)
	heading.Font = Enum.Font.GothamMedium
	heading.TextSize = 12
	heading.TextColor3 = SUN
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Text = "VENDING"
	heading.Parent = panel

	local hint = heading:Clone()
	hint.TextColor3 = INK_DIM
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.Text = "E to close"
	hint.Parent = panel

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.new(0, 0, 0, 36)
	row.Size = UDim2.new(1, 0, 1, -36)
	row.Parent = panel

	for index, drink in Drinks.Catalogue do
		local card = Instance.new("Frame")
		card.Name = drink.Key
		card.Size = UDim2.new(0.5, -8, 1, 0)
		card.Position = UDim2.new(0.5 * (index - 1), if index == 1 then 0 else 8, 0, 0)
		card.BackgroundColor3 = PANEL
		card.BorderSizePixel = 0
		card.Parent = row
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 3)
		c.Parent = card
		local s = Instance.new("UIStroke")
		s.Color = EDGE
		s.Parent = card

		-- A swatch in the drink's own colour rather than an icon: the can is built from parts in
		-- these exact colours, so the panel and the thing it hands you match without an asset.
		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.new(0, 34, 0, 74)
		swatch.Position = UDim2.new(0, 22, 0, 26)
		swatch.BackgroundColor3 = drink.Body
		swatch.BorderSizePixel = 0
		swatch.Parent = card
		local sc = Instance.new("UICorner")
		sc.CornerRadius = UDim.new(0, 5)
		sc.Parent = swatch
		local lid = Instance.new("Frame")
		lid.Size = UDim2.new(1, 0, 0, 7)
		lid.BackgroundColor3 = drink.Lid
		lid.BorderSizePixel = 0
		lid.Parent = swatch

		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.new(0, 72, 0, 26)
		name.Size = UDim2.new(1, -92, 0, 24)
		name.Font = Enum.Font.GothamBold
		name.TextSize = 18
		name.TextColor3 = INK
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = drink.Name
		name.Parent = card

		local blurb = Instance.new("TextLabel")
		blurb.BackgroundTransparency = 1
		blurb.Position = UDim2.new(0, 72, 0, 52)
		blurb.Size = UDim2.new(1, -92, 0, 48)
		blurb.Font = Enum.Font.Gotham
		blurb.TextSize = 13
		blurb.TextColor3 = INK_DIM
		blurb.TextXAlignment = Enum.TextXAlignment.Left
		blurb.TextYAlignment = Enum.TextYAlignment.Top
		blurb.TextWrapped = true
		blurb.Text = drink.Blurb
		blurb.Parent = card

		local hit = Instance.new("TextButton")
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.Parent = card
		hit.MouseEnter:Connect(function()
			TweenService:Create(card, FADE, { BackgroundColor3 = PANEL_HI }):Play()
			TweenService:Create(s, FADE, { Color = SUN }):Play()
		end)
		hit.MouseLeave:Connect(function()
			TweenService:Create(card, FADE, { BackgroundColor3 = PANEL }):Play()
			TweenService:Create(s, FADE, { Color = EDGE }):Play()
		end)
		hit.Activated:Connect(function()
			RequestDrink:FireServer(drink.Key)
			VendingUI.Close()
		end)
	end

	gui, shade = screen, dim
end

function VendingUI.Close()
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

function VendingUI.Open()
	local screen, dim = gui, shade
	if screen == nil or dim == nil then
		return
	end
	screen.Enabled = true
	dim.BackgroundTransparency = 1
	TweenService:Create(dim, FADE, { BackgroundTransparency = 0.4 }):Play()

	closeConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Escape then
			VendingUI.Close()
		end
	end)
end

function VendingUI.Start()
	build()
	OpenVending.OnClientEvent:Connect(function()
		VendingUI.Open()
	end)
end

return VendingUI
