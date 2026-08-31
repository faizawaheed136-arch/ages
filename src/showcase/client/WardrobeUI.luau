--!strict
-- The locker panel. Two cards, a title, and nothing else.
--
-- Built in code rather than in Studio on purpose: the palette lives in one table here, so a
-- change to the showcase's colours does not mean hunting through a ScreenGui by hand. It also
-- means the whole thing is in version control as text.
--
-- The panel decides nothing. It sends a catalogue key and waits to be told whether it worked --
-- see WardrobeService for why the client is not trusted with an asset id.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Uniforms = require(ReplicatedStorage:WaitForChild("Showcase"):WaitForChild("Uniforms"))

local remotes = ReplicatedStorage:WaitForChild("Showcase"):WaitForChild("Remotes")
local OpenWardrobe = remotes:WaitForChild("OpenWardrobe") :: RemoteEvent
local RequestUniform = remotes:WaitForChild("RequestUniform") :: RemoteEvent
local UniformApplied = remotes:WaitForChild("UniformApplied") :: RemoteEvent

-- Straight out of the palette in section 03. Nothing here is a one-off colour.
local GROUND = Color3.fromRGB(17, 18, 22)
local PANEL = Color3.fromRGB(25, 27, 32)
local PANEL_HI = Color3.fromRGB(31, 34, 41)
local EDGE = Color3.fromRGB(43, 47, 55)
local INK = Color3.fromRGB(226, 222, 213)
local INK_DIM = Color3.fromRGB(124, 122, 116)
local SUN = Color3.fromRGB(240, 178, 104)

local FADE = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local WardrobeUI = {}

local gui: ScreenGui? = nil
local shade: Frame? = nil
local selected: string = Uniforms.Default
local cards: { [string]: { frame: Frame, stroke: UIStroke, name: TextLabel } } = {}
local escapeConnection: RBXScriptConnection? = nil

-- ---------------------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------------------

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Parent = parent
	return s
end

local function label(parent: Instance, text: string, size: number, color: Color3, font: Enum.Font): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextSize = size
	t.TextColor3 = color
	t.Font = font
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextWrapped = true
	t.Parent = parent
	return t
end

local function buildCard(parent: Instance, uniform: Uniforms.Uniform, index: number): Frame
	local card = Instance.new("Frame")
	card.Name = uniform.Key
	card.Size = UDim2.new(0.5, -8, 1, 0)
	card.Position = UDim2.new(0.5 * (index - 1), if index == 1 then 0 else 8, 0, 0)
	card.BackgroundColor3 = PANEL
	card.BorderSizePixel = 0
	card.Parent = parent
	corner(card, 4)
	local edge = stroke(card, EDGE, 1)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 22)
	pad.PaddingBottom = UDim.new(0, 22)
	pad.PaddingLeft = UDim.new(0, 22)
	pad.PaddingRight = UDim.new(0, 22)
	pad.Parent = card

	local name = label(card, uniform.Name, 20, INK, Enum.Font.GothamMedium)
	name.Size = UDim2.new(1, 0, 0, 26)
	name.Position = UDim2.new(0, 0, 0, 0)

	local blurb = label(card, uniform.Blurb, 14, INK_DIM, Enum.Font.Gotham)
	blurb.Size = UDim2.new(1, 0, 0, 44)
	blurb.Position = UDim2.new(0, 0, 0, 32)
	blurb.TextYAlignment = Enum.TextYAlignment.Top

	-- The whole card is the button. A separate "select" button inside a clickable card is two
	-- targets for one action, and players find the wrong one.
	local hit = Instance.new("TextButton")
	hit.Size = UDim2.new(1, 44, 1, 44)
	hit.Position = UDim2.new(0, -22, 0, -22)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.Parent = card

	hit.MouseEnter:Connect(function()
		if selected ~= uniform.Key then
			TweenService:Create(card, FADE, { BackgroundColor3 = PANEL_HI }):Play()
		end
	end)
	hit.MouseLeave:Connect(function()
		if selected ~= uniform.Key then
			TweenService:Create(card, FADE, { BackgroundColor3 = PANEL }):Play()
		end
	end)
	hit.Activated:Connect(function()
		WardrobeUI.Choose(uniform.Key)
	end)

	cards[uniform.Key] = { frame = card, stroke = edge, name = name }
	return card
end

local function paintSelection()
	for key, card in cards do
		local on = key == selected
		TweenService:Create(card.stroke, FADE, {
			Color = if on then SUN else EDGE,
			Thickness = if on then 2 else 1,
		}):Play()
		TweenService:Create(card.frame, FADE, {
			BackgroundColor3 = if on then PANEL_HI else PANEL,
		}):Play()
		card.name.TextColor3 = if on then SUN else INK
	end
end

local function build()
	local player = Players.LocalPlayer
	local screen = Instance.new("ScreenGui")
	screen.Name = "WardrobeUI"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 20
	screen.Enabled = false
	screen.Parent = player:WaitForChild("PlayerGui")

	local dim = Instance.new("Frame")
	dim.Name = "Shade"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = GROUND
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Parent = screen

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0, 720, 0, 300)
	panel.BackgroundColor3 = GROUND
	panel.BorderSizePixel = 0
	panel.Parent = dim
	corner(panel, 5)
	stroke(panel, EDGE, 1)

	local panelPad = Instance.new("UIPadding")
	panelPad.PaddingTop = UDim.new(0, 28)
	panelPad.PaddingBottom = UDim.new(0, 28)
	panelPad.PaddingLeft = UDim.new(0, 28)
	panelPad.PaddingRight = UDim.new(0, 28)
	panelPad.Parent = panel

	-- Keeps the panel usable on a phone without a second layout.
	local fit = Instance.new("UISizeConstraint")
	fit.MaxSize = Vector2.new(720, 300)
	fit.Parent = panel

	local heading = label(panel, "UNIFORM", 12, SUN, Enum.Font.GothamMedium)
	heading.Size = UDim2.new(1, 0, 0, 16)

	local hint = label(panel, "E to close", 12, INK_DIM, Enum.Font.Gotham)
	hint.Size = UDim2.new(0, 120, 0, 16)
	hint.Position = UDim2.new(1, -120, 0, 0)
	hint.TextXAlignment = Enum.TextXAlignment.Right

	local row = Instance.new("Frame")
	row.Name = "Cards"
	row.BackgroundTransparency = 1
	row.Position = UDim2.new(0, 0, 0, 40)
	row.Size = UDim2.new(1, 0, 1, -40)
	row.Parent = panel

	for index, uniform in Uniforms.Catalogue do
		buildCard(row, uniform, index)
	end

	gui = screen
	shade = dim
	return screen
end

-- ---------------------------------------------------------------------------------------
-- Open / close
-- ---------------------------------------------------------------------------------------

function WardrobeUI.Close()
	local screen, dim = gui, shade
	if screen == nil or dim == nil or not screen.Enabled then
		return
	end
	if escapeConnection ~= nil then
		escapeConnection:Disconnect()
		escapeConnection = nil
	end
	local tween = TweenService:Create(dim, FADE, { BackgroundTransparency = 1 })
	tween.Completed:Once(function()
		screen.Enabled = false
	end)
	tween:Play()
end

function WardrobeUI.Open(current: string?)
	local screen, dim = gui, shade
	if screen == nil or dim == nil then
		return
	end
	selected = current or selected
	paintSelection()
	screen.Enabled = true
	dim.BackgroundTransparency = 1
	TweenService:Create(dim, FADE, { BackgroundTransparency = 0.35 }):Play()

	-- E opened it, so E closes it -- the same key, because a player who just pressed E to open a
	-- locker will press E again to leave it. Escape works too, for anyone who expects that.
	escapeConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Escape then
			WardrobeUI.Close()
		end
	end)
end

function WardrobeUI.Choose(key: string)
	if key == selected then
		WardrobeUI.Close()
		return
	end
	selected = key
	-- Painted immediately rather than on the server's reply. The round trip is short but not
	-- free, and a card that highlights 80ms after the click feels broken; the server's answer
	-- only matters if it is a refusal, and then it repaints.
	paintSelection()
	RequestUniform:FireServer(key)
end

function WardrobeUI.Start()
	build()
	OpenWardrobe.OnClientEvent:Connect(function(current: string?)
		WardrobeUI.Open(current)
	end)
	UniformApplied.OnClientEvent:Connect(function(ok: boolean, err: string?)
		if ok then
			WardrobeUI.Close()
		else
			-- The optimistic paint above was wrong. Put the highlight back where it was rather
			-- than leaving the player looking at a selected card they are not wearing.
			warn(`[Wardrobe] refused: {err}`)
			paintSelection()
		end
	end)
end

return WardrobeUI
