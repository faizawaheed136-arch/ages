--!strict
-- The list of keys that do something right now, right side of the screen, shown for
-- exactly as long as a shift is.
--
-- Everything else on the HUD lives top-left, so this is the one panel with the right
-- side to itself -- there is nothing else there to crowd and nothing here worth
-- crowding the task rows the player is actually timing against. It only ever shows
-- while `onShift` is true: a key advertised while it does nothing is worse than a key
-- not advertised at all, which is the same rule the pickup prompt itself follows by
-- only existing on a mark that is actually live.
--
-- One row today -- P, the universal pickup key from Config.Interact.PickupKeyboardKey
-- -- built off a list rather than a single hardcoded row, because the day a second
-- shift verb earns its own key, it is a second entry in `COMMANDS` and nothing else in
-- this file has to change.

local Players = game:GetService("Players")

local CommandsLegend = {}
CommandsLegend.__index = CommandsLegend

-- The warm gold family every other interactable in the game already answers to --
-- the choice marker's disc, the hiring sign, the pickup prompt's own accent -- so a
-- key on this list reads as the same kind of thing as the mark it belongs to.
local KEY_COLOR = Color3.fromRGB(245, 205, 120)
local KEY_TEXT_COLOR = Color3.fromRGB(20, 18, 14)
local LABEL_COLOR = Color3.fromRGB(230, 226, 216)
local STROKE_COLOR = Color3.fromRGB(20, 18, 14)
local PANEL_COLOR = Color3.fromRGB(20, 20, 24)

local PANEL_WIDTH = 190
local KEY_SIZE = 30

-- Every command this legend can ever show, in the order it shows them.
local COMMANDS: { { key: string, label: string } } = {
	{ key = "P", label = "Pick up" },
}

export type CommandsLegendHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
	},
	CommandsLegend
))

function CommandsLegend.new(): CommandsLegendHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesCommandsLegend"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 2
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -14, 0.5, 0)
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = KEY_COLOR
	stroke.Transparency = 0.6
	stroke.Thickness = 1
	stroke.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = panel

	for index, command in COMMANDS do
		local row = Instance.new("Frame")
		row.Name = command.key
		row.Size = UDim2.new(1, 0, 0, KEY_SIZE)
		row.BackgroundTransparency = 1
		row.LayoutOrder = index
		row.Parent = panel

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.Padding = UDim.new(0, 10)
		rowLayout.Parent = row

		local key = Instance.new("Frame")
		key.Name = "Key"
		key.Size = UDim2.new(0, KEY_SIZE, 0, KEY_SIZE)
		key.BackgroundColor3 = KEY_COLOR
		key.BorderSizePixel = 0
		key.LayoutOrder = 1
		key.Parent = row

		local keyCorner = Instance.new("UICorner")
		keyCorner.CornerRadius = UDim.new(0, 6)
		keyCorner.Parent = key

		local keyStroke = Instance.new("UIStroke")
		keyStroke.Color = STROKE_COLOR
		keyStroke.Thickness = 1.5
		keyStroke.Parent = key

		local keyText = Instance.new("TextLabel")
		keyText.Name = "Text"
		keyText.Size = UDim2.new(1, 0, 1, 0)
		keyText.BackgroundTransparency = 1
		keyText.Font = Enum.Font.GothamBold
		keyText.TextSize = 16
		keyText.TextColor3 = KEY_TEXT_COLOR
		keyText.Text = command.key
		keyText.LayoutOrder = 1
		keyText.Parent = key

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, -(KEY_SIZE + 10), 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 14
		label.TextColor3 = LABEL_COLOR
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = command.label
		label.LayoutOrder = 2
		label.Parent = row
	end

	return setmetatable({
		screenGui = screenGui,
		panel = panel,
	}, CommandsLegend) :: CommandsLegendHandle
end

-- Shown for exactly as long as a shift is, and for nothing else.
function CommandsLegend.Set(self: CommandsLegendHandle, onShift: boolean)
	self.panel.Visible = onShift
end

return CommandsLegend
