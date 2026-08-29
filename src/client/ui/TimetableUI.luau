--!strict
-- The year's timetable, on J.
--
-- The rotation has existed since school was written and there was no way to see it. A player
-- could find out what they were doing this year by turning up to it, one afternoon at a time,
-- and could not find out what was coming at all -- which makes a timetable that was carefully
-- designed to be *predictable* indistinguishable from three random draws.
--
-- That is the whole argument for this panel. `subjectForSlot` rotates rather than rolls
-- specifically so every subject comes round evenly and the same year lived twice gives the
-- same subjects; none of that reaches the player unless they can look at it.
--
-- Pushed, not computed. The rotation lives in one function on the server and a client that
-- recomputed it would be a second copy of the timetable, free to disagree with the one that
-- decides what lesson you actually sit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type Timetable = Types.Timetable

local TimetableUI = {}
TimetableUI.__index = TimetableUI

-- The school's own colours, so the panel reads as part of the same building.
local PANEL_COLOR = Color3.fromRGB(20, 22, 30)
local HEADER_COLOR = Color3.fromRGB(64, 116, 200)
local TEXT_COLOR = Color3.fromRGB(232, 234, 240)
local DIM_TEXT = Color3.fromRGB(150, 156, 170)
local STROKE_COLOR = Color3.fromRGB(12, 13, 18)

-- Done is spent, now is the one the bell rings for next, later is still to come. The three
-- get three different weights rather than three different hues: a timetable read at a glance
-- is answering "which one is next", and one bright row against two quiet ones answers it
-- faster than a colour key does.
local STATE_STYLE = {
	done = { accent = Color3.fromRGB(96, 104, 120), label = "done", text = DIM_TEXT },
	now = { accent = Color3.fromRGB(246, 196, 96), label = "next", text = Color3.fromRGB(255, 244, 214) },
	later = { accent = Color3.fromRGB(64, 116, 200), label = "later", text = TEXT_COLOR },
}

local PANEL_WIDTH = 320
local ROW_HEIGHT = 56

export type TimetableUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		list: Frame,
		title: TextLabel,
		open: boolean,
		latest: Timetable?,
	},
	TimetableUI
))

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance)
	local s = Instance.new("UIStroke")
	s.Color = STROKE_COLOR
	s.Thickness = 2
	s.Transparency = 0.35
	s.Parent = parent
end

function TimetableUI.new(): TimetableUIHandle
	local player = Players.LocalPlayer

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TimetableUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 6
	screenGui.Enabled = false
	screenGui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, 120)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BorderSizePixel = 0
	panel.Parent = screenGui
	corner(panel, 12)
	stroke(panel)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 44)
	header.BackgroundColor3 = HEADER_COLOR
	header.BorderSizePixel = 0
	header.Parent = panel
	corner(header, 12)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -24, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 17
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Timetable"
	title.Parent = header

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.Size = UDim2.new(1, -24, 1, 0)
	hint.Position = UDim2.new(0, 12, 0, 0)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 13
	hint.TextColor3 = Color3.fromRGB(226, 236, 255)
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.Text = "J to close"
	hint.Parent = header

	local list = Instance.new("Frame")
	list.Name = "List"
	list.Position = UDim2.new(0, 0, 0, 52)
	list.Size = UDim2.new(1, 0, 1, -60)
	list.BackgroundTransparency = 1
	list.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = list

	local self = setmetatable({
		screenGui = screenGui,
		panel = panel,
		list = list,
		title = title,
		open = false,
		latest = nil,
	}, TimetableUI)

	Remotes.Get("TimetableUpdated").OnClientEvent:Connect(function(payload: unknown)
		self.latest = payload :: Timetable?
		if self.open then
			self:Render()
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.J then
			self:Toggle()
		end
	end)

	return self
end

function TimetableUI.Render(self: TimetableUIHandle)
	for _, child in self.list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local data = self.latest
	if data == nil then
		self.title.Text = "Timetable"
		local empty = Instance.new("Frame")
		empty.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		empty.BackgroundTransparency = 1
		empty.LayoutOrder = 1
		empty.Parent = self.list

		local text = Instance.new("TextLabel")
		text.Size = UDim2.new(1, 0, 1, 0)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.Gotham
		text.TextSize = 14
		text.TextColor3 = DIM_TEXT
		text.TextWrapped = true
		-- Says why rather than showing a blank. A player who is four has no timetable and that
		-- is the system working, not a panel that failed to load.
		text.Text = "No school year running.\nCome back when you are old enough for lessons."
		text.Parent = empty

		self.panel.Size = UDim2.new(0, PANEL_WIDTH, 0, 60 + ROW_HEIGHT)
		return
	end

	self.title.Text = `Timetable  ·  age {data.ageYears}`

	for index, entry in data.entries do
		local style = STATE_STYLE[entry.state] or STATE_STYLE.later

		local row = Instance.new("Frame")
		row.Name = `Slot{entry.slot}`
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.BackgroundColor3 = Color3.fromRGB(30, 33, 44)
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Parent = self.list
		corner(row, 8)

		-- The accent bar down the left edge, which is what carries the state at a glance.
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(0, 4, 1, -12)
		bar.Position = UDim2.new(0, 8, 0, 6)
		bar.BackgroundColor3 = style.accent
		bar.BorderSizePixel = 0
		bar.Parent = row
		corner(bar, 2)

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, -70, 0, 20)
		name.Position = UDim2.new(0, 20, 0, 8)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextSize = 15
		name.TextColor3 = style.text
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = `{entry.slot}.  {entry.name}`
		name.Parent = row

		local blurb = Instance.new("TextLabel")
		blurb.Size = UDim2.new(1, -30, 0, 18)
		blurb.Position = UDim2.new(0, 20, 0, 28)
		blurb.BackgroundTransparency = 1
		blurb.Font = Enum.Font.Gotham
		blurb.TextSize = 12
		blurb.TextColor3 = DIM_TEXT
		blurb.TextXAlignment = Enum.TextXAlignment.Left
		blurb.TextTruncate = Enum.TextTruncate.AtEnd
		blurb.Text = entry.blurb
		blurb.Parent = row

		local tag = Instance.new("TextLabel")
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Size = UDim2.new(0, 52, 0, 18)
		tag.Position = UDim2.new(1, -10, 0, 8)
		tag.BackgroundTransparency = 1
		tag.Font = Enum.Font.GothamBold
		tag.TextSize = 11
		tag.TextColor3 = style.accent
		tag.TextXAlignment = Enum.TextXAlignment.Right
		tag.Text = string.upper(style.label)
		tag.Parent = row
	end

	self.panel.Size = UDim2.new(0, PANEL_WIDTH, 0, 60 + #data.entries * (ROW_HEIGHT + 6))
end

function TimetableUI.Toggle(self: TimetableUIHandle)
	self.open = not self.open
	self.screenGui.Enabled = self.open
	if self.open then
		self:Render()
	end
end

return TimetableUI
