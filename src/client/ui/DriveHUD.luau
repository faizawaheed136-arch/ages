--!strict
--[[
	What a driver sees on screen: a speedometer dial in the corner -- the speed large, a ring of lamps
	round it lighting toward red as the car nears flat out -- the nitro left under it, a drift score
	that climbs while the car is sideways and banks when it straightens, and the keys. On a phone,
	buttons for nitro, drift and getting out, since there is no Shift or Space to hold.

	A view only: client/world/CarDriver feeds it every frame and wires its buttons.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local DriveHUD = {}
DriveHUD.__index = DriveHUD

local PANEL = Color3.fromRGB(18, 22, 32)
local STROKE = Color3.fromRGB(58, 70, 96)
local WHITE = Color3.fromRGB(244, 246, 250)
local GREY = Color3.fromRGB(140, 150, 170)
local UNLIT = Color3.fromRGB(46, 52, 68)
local LOW = Color3.fromRGB(60, 150, 255)
local HIGH = Color3.fromRGB(255, 60, 80)
local NITRO = Color3.fromRGB(70, 200, 255)
local DRIFT = Color3.fromRGB(255, 176, 40)

local DIAL = 190
local SEGMENTS = 32
-- The gauge's sweep: from lower left, over the top, to lower right.
local SWEEP_FROM, SWEEP_TO = 225, -45

export type HUD = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		ring: { Frame },
		speed: TextLabel,
		nitroFill: Frame,
		nitroLabel: TextLabel,
		driftBadge: TextLabel,
		driftShown: boolean,
		buttons: Frame,
		onBoost: ((boolean) -> ())?,
		onDrift: ((boolean) -> ())?,
		onExit: (() -> ())?,
	},
	DriveHUD
))

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Parent = parent
end

local function label(parent: Instance, name: string, position: UDim2, size: UDim2, text: string, color: Color3, textSize: number, font: Enum.Font): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = position
	t.Size = size
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = color
	t.TextSize = textSize
	t.Font = font
	t.Parent = parent
	return t
end

function DriveHUD.new(): HUD
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "DriveHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 15
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The dial.
	local dial = Instance.new("Frame")
	dial.Name = "Dial"
	dial.AnchorPoint = Vector2.new(1, 1)
	dial.Position = UDim2.new(1, -28, 1, -64)
	dial.Size = UDim2.fromOffset(DIAL, DIAL)
	dial.BackgroundColor3 = PANEL
	dial.BackgroundTransparency = 0.12
	dial.Parent = gui
	corner(dial, UDim.new(0.5, 0))
	stroke(dial, STROKE, 2)
	local ring: { Frame } = {}
	for i = 0, SEGMENTS - 1 do
		local degrees = SWEEP_FROM + (SWEEP_TO - SWEEP_FROM) * i / (SEGMENTS - 1)
		local a = math.rad(degrees)
		local seg = Instance.new("Frame")
		seg.Name = "Lamp"
		seg.AnchorPoint = Vector2.new(0.5, 0.5)
		seg.Position = UDim2.new(0.5, math.cos(a) * (DIAL / 2 - 16), 0.5, -math.sin(a) * (DIAL / 2 - 16))
		seg.Size = UDim2.fromOffset(5, 14)
		seg.Rotation = 90 - degrees
		seg.BackgroundColor3 = UNLIT
		seg.BorderSizePixel = 0
		seg.Parent = dial
		corner(seg, UDim.new(0, 2))
		table.insert(ring, seg)
	end
	local speed = label(dial, "Speed", UDim2.fromScale(0.5, 0.45), UDim2.fromOffset(150, 64), "0", WHITE, 58, Enum.Font.GothamBlack)
	label(dial, "Unit", UDim2.fromScale(0.5, 0.68), UDim2.fromOffset(100, 20), "MPH", GREY, 16, Enum.Font.GothamBold)

	-- Nitro, under the dial.
	local nitro = Instance.new("Frame")
	nitro.Name = "Nitro"
	nitro.AnchorPoint = Vector2.new(1, 1)
	nitro.Position = UDim2.new(1, -28, 1, -40)
	nitro.Size = UDim2.fromOffset(DIAL, 14)
	nitro.BackgroundColor3 = PANEL
	nitro.BackgroundTransparency = 0.12
	nitro.Parent = gui
	corner(nitro, UDim.new(0, 7))
	stroke(nitro, STROKE, 1.5)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = NITRO
	fill.BorderSizePixel = 0
	fill.Parent = nitro
	corner(fill, UDim.new(0, 7))
	local nitroLabel = label(nitro, "Label", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1), "NITRO", WHITE, 11, Enum.Font.GothamBlack)

	-- The keys.
	local hint = label(gui, "Keys", UDim2.new(1, -28 - DIAL / 2, 1, -18), UDim2.fromOffset(320, 18), "SHIFT  Nitro     SPACE  Drift     F  Exit", GREY, 13, Enum.Font.GothamBold)
	hint.TextStrokeTransparency = 0.6

	-- The drift score, over the dial.
	local drift = label(gui, "Drift", UDim2.new(1, -28 - DIAL / 2, 1, -64 - DIAL - 26), UDim2.fromOffset(260, 40), "", DRIFT, 30, Enum.Font.GothamBlack)
	drift.TextStrokeTransparency = 0.3
	drift.TextTransparency = 1
	drift.TextStrokeColor3 = Color3.fromRGB(40, 20, 0)

	-- Buttons for a touch screen.
	local buttons = Instance.new("Frame")
	buttons.Name = "Touch"
	buttons.AnchorPoint = Vector2.new(1, 1)
	buttons.Position = UDim2.new(1, -28 - DIAL - 16, 1, -64)
	buttons.Size = UDim2.fromOffset(96, DIAL)
	buttons.BackgroundTransparency = 1
	buttons.Visible = UserInputService.TouchEnabled
	buttons.Parent = gui

	local self = setmetatable({
		gui = gui,
		ring = ring,
		speed = speed,
		nitroFill = fill,
		nitroLabel = nitroLabel,
		driftBadge = drift,
		driftShown = false,
		buttons = buttons,
		onBoost = nil,
		onDrift = nil,
		onExit = nil,
	}, DriveHUD) :: HUD

	local function round(name: string, y: number, text: string, color: Color3): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.AnchorPoint = Vector2.new(0.5, 0)
		b.Position = UDim2.new(0.5, 0, 0, y)
		b.Size = UDim2.fromOffset(84, 56)
		b.BackgroundColor3 = color
		b.BackgroundTransparency = 0.1
		b.Text = text
		b.TextColor3 = WHITE
		b.TextSize = 14
		b.Font = Enum.Font.GothamBlack
		b.Parent = buttons
		corner(b, UDim.new(0, 14))
		return b
	end
	local boost = round("Nitro", 0, "NITRO", Color3.fromRGB(30, 110, 200))
	local slide = round("Drift", 66, "DRIFT", Color3.fromRGB(200, 120, 20))
	local exit = round("Exit", 132, "EXIT", Color3.fromRGB(190, 50, 60))
	boost.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch and self.onBoost then
			(self.onBoost :: (boolean) -> ())(true)
		end
	end)
	boost.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch and self.onBoost then
			(self.onBoost :: (boolean) -> ())(false)
		end
	end)
	slide.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch and self.onDrift then
			(self.onDrift :: (boolean) -> ())(true)
		end
	end)
	slide.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch and self.onDrift then
			(self.onDrift :: (boolean) -> ())(false)
		end
	end)
	exit.Activated:Connect(function()
		local callback = self.onExit
		if callback then
			callback()
		end
	end)
	return self
end

function DriveHUD.Show(self: HUD, visible: boolean)
	self.gui.Enabled = visible
	self.buttons.Visible = UserInputService.TouchEnabled
end

function DriveHUD.OnButtons(self: HUD, onBoost: (boolean) -> (), onDrift: (boolean) -> (), onExit: () -> ())
	self.onBoost = onBoost
	self.onDrift = onDrift
	self.onExit = onExit
end

local function comma(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

-- One frame: the speed in mph, how far toward flat out (0-1, past 1 on nitro), the nitro left
-- (0-1) and whether it is burning, and the drift score so far (nil when not drifting).
function DriveHUD.Set(self: HUD, mph: number, share: number, fuel: number, boosting: boolean, driftScore: number?)
	self.speed.Text = tostring(math.floor(mph))
	local lit = math.floor(math.clamp(share, 0, 1) * #self.ring + 0.5)
	for i, seg in self.ring do
		if i <= lit then
			local t = (i - 1) / (#self.ring - 1)
			seg.BackgroundColor3 = if boosting then NITRO else LOW:Lerp(HIGH, t * t)
		else
			seg.BackgroundColor3 = UNLIT
		end
	end
	self.nitroFill.Size = UDim2.fromScale(math.clamp(fuel, 0, 1), 1)
	self.nitroFill.BackgroundColor3 = if boosting then Color3.fromRGB(150, 240, 255) else NITRO
	self.nitroLabel.Text = if boosting then "NITRO!" else "NITRO"

	local badge = self.driftBadge
	if driftScore and driftScore >= 1 then
		badge.Text = `DRIFT  +{comma(driftScore)}`
		if not self.driftShown then
			self.driftShown = true
			badge.TextTransparency = 0
			badge.TextStrokeTransparency = 0.3
		end
	elseif self.driftShown then
		self.driftShown = false
		badge.Text = badge.Text .. "  BANKED"
		TweenService:Create(badge, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end
end

return DriveHUD
