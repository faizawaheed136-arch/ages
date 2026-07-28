--!strict
-- The delivery layer. The server decides which event fires; this decides how it
-- reaches the player, keyed off the event's `delivery` field.
--
-- DELIVERY_STYLES is deliberately a closed record rather than a loose map: add
-- a variant to Types.EventDelivery and this file stops type-checking until it
-- has been given a presentation. When step 3 brings a world, NPCApproach /
-- Letter / PhoneCall / Location are added here, and nothing on the server or in
-- the content modules has to move.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Types"))

type OfferedEvent = Types.OfferedEvent
type EventDelivery = Types.EventDelivery

type DeliveryStyle = {
	width: number,
	backdropTransparency: number,
	panelTransparency: number,
	promptFont: Enum.Font,
	promptSize: number,
	promptColor: Color3,
	choiceFont: Enum.Font,
	choiceColor: Color3,
	accent: Color3,
}

local DELIVERY_STYLES: { Memory: DeliveryStyle, Direct: DeliveryStyle } = {
	-- Early childhood. Dimmer, wider, quieter — a recollection surfacing rather
	-- than a decision being demanded. There is no world for a toddler to walk
	-- around, so this presentation is permanent, not a stand-in.
	Memory = {
		width = 520,
		backdropTransparency = 0.25,
		panelTransparency = 1,
		promptFont = Enum.Font.Gotham,
		promptSize = 20,
		promptColor = Color3.fromRGB(240, 236, 228),
		choiceFont = Enum.Font.Gotham,
		choiceColor = Color3.fromRGB(210, 205, 195),
		accent = Color3.fromRGB(225, 200, 150),
	},
	-- Everything from school age on: a plain card, pending the world.
	Direct = {
		width = 460,
		backdropTransparency = 0.55,
		panelTransparency = 0.05,
		promptFont = Enum.Font.GothamMedium,
		promptSize = 17,
		promptColor = Color3.fromRGB(240, 240, 245),
		choiceFont = Enum.Font.GothamMedium,
		choiceColor = Color3.fromRGB(225, 225, 235),
		accent = Color3.fromRGB(110, 160, 220),
	},
}

local CHOICE_HEIGHT = 38
local CHOICE_IDLE = Color3.fromRGB(38, 38, 44)
local CHOICE_HOVER = Color3.fromRGB(54, 54, 62)

local EventUI = {}
EventUI.__index = EventUI

export type EventUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		backdrop: Frame,
		panel: Frame,
		promptLabel: TextLabel,
		choicesFrame: Frame,
		outcomeLabel: TextLabel,
		choiceButtons: { TextButton },
		activeEventId: string?,
		onChoice: ((eventId: string, choiceId: string) -> ())?,
		hideToken: number,
	},
	EventUI
))

function EventUI.new(): EventUIHandle
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesEvents"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	-- Above the HUD, below the death screen.
	screenGui.DisplayOrder = 5

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(0, 460, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	panel.BorderSizePixel = 0
	panel.Parent = backdrop

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 22)
	padding.PaddingBottom = UDim.new(0, 22)
	padding.PaddingLeft = UDim.new(0, 24)
	padding.PaddingRight = UDim.new(0, 24)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 14)
	layout.Parent = panel

	local promptLabel = Instance.new("TextLabel")
	promptLabel.Name = "Prompt"
	promptLabel.Size = UDim2.new(1, 0, 0, 0)
	promptLabel.AutomaticSize = Enum.AutomaticSize.Y
	promptLabel.BackgroundTransparency = 1
	promptLabel.TextWrapped = true
	promptLabel.TextXAlignment = Enum.TextXAlignment.Left
	promptLabel.LayoutOrder = 0
	promptLabel.Text = ""
	promptLabel.Parent = panel

	local choicesFrame = Instance.new("Frame")
	choicesFrame.Name = "Choices"
	choicesFrame.Size = UDim2.new(1, 0, 0, 0)
	choicesFrame.AutomaticSize = Enum.AutomaticSize.Y
	choicesFrame.BackgroundTransparency = 1
	choicesFrame.LayoutOrder = 1
	choicesFrame.Parent = panel

	local choicesLayout = Instance.new("UIListLayout")
	choicesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	choicesLayout.Padding = UDim.new(0, 8)
	choicesLayout.Parent = choicesFrame

	local outcomeLabel = Instance.new("TextLabel")
	outcomeLabel.Name = "Outcome"
	outcomeLabel.Size = UDim2.new(1, 0, 0, 0)
	outcomeLabel.AutomaticSize = Enum.AutomaticSize.Y
	outcomeLabel.BackgroundTransparency = 1
	outcomeLabel.TextWrapped = true
	outcomeLabel.TextXAlignment = Enum.TextXAlignment.Left
	outcomeLabel.Font = Enum.Font.Gotham
	outcomeLabel.TextSize = 16
	outcomeLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	outcomeLabel.LayoutOrder = 2
	outcomeLabel.Visible = false
	outcomeLabel.Text = ""
	outcomeLabel.Parent = panel

	screenGui.Parent = playerGui

	return setmetatable({
		screenGui = screenGui,
		backdrop = backdrop,
		panel = panel,
		promptLabel = promptLabel,
		choicesFrame = choicesFrame,
		outcomeLabel = outcomeLabel,
		choiceButtons = {},
		activeEventId = nil,
		onChoice = nil,
		hideToken = 0,
	}, EventUI)
end

function EventUI.OnChoice(self: EventUIHandle, callback: (eventId: string, choiceId: string) -> ())
	self.onChoice = callback
end

local function clearChoices(self: EventUIHandle)
	for _, button in self.choiceButtons do
		button:Destroy()
	end
	table.clear(self.choiceButtons)
end

function EventUI.Hide(self: EventUIHandle)
	self.hideToken += 1
	self.activeEventId = nil
	self.backdrop.Visible = false
	self.outcomeLabel.Visible = false
	clearChoices(self)
end

function EventUI.Show(self: EventUIHandle, offered: OfferedEvent)
	self.hideToken += 1
	clearChoices(self)

	local style = DELIVERY_STYLES[offered.delivery]

	self.activeEventId = offered.id
	self.backdrop.BackgroundTransparency = style.backdropTransparency
	self.panel.Size = UDim2.new(0, style.width, 0, 0)
	self.panel.BackgroundTransparency = style.panelTransparency

	self.promptLabel.Font = style.promptFont
	self.promptLabel.TextSize = style.promptSize
	self.promptLabel.TextColor3 = style.promptColor
	self.promptLabel.Text = offered.prompt

	self.outcomeLabel.Visible = false
	self.outcomeLabel.Text = ""

	for index, choice in offered.choices do
		local button = Instance.new("TextButton")
		button.Name = `Choice_{choice.id}`
		button.Size = UDim2.new(1, 0, 0, CHOICE_HEIGHT)
		button.AutomaticSize = Enum.AutomaticSize.Y
		button.LayoutOrder = index
		button.BackgroundColor3 = CHOICE_IDLE
		button.BackgroundTransparency = 0.1
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Font = style.choiceFont
		button.TextSize = 15
		button.TextColor3 = style.choiceColor
		button.TextWrapped = true
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.Text = choice.label
		button.Parent = self.choicesFrame

		local buttonPadding = Instance.new("UIPadding")
		buttonPadding.PaddingTop = UDim.new(0, 10)
		buttonPadding.PaddingBottom = UDim.new(0, 10)
		buttonPadding.PaddingLeft = UDim.new(0, 14)
		buttonPadding.PaddingRight = UDim.new(0, 14)
		buttonPadding.Parent = button

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 8)
		buttonCorner.Parent = button

		button.MouseEnter:Connect(function()
			button.BackgroundColor3 = CHOICE_HOVER
			button.TextColor3 = style.accent
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundColor3 = CHOICE_IDLE
			button.TextColor3 = style.choiceColor
		end)

		button.Activated:Connect(function()
			local eventId = self.activeEventId
			local callback = self.onChoice
			if eventId == nil or callback == nil then
				return
			end

			-- Locked immediately so a double-click can't send two answers. The
			-- server would refuse the second anyway; this stops the UI implying
			-- otherwise. ShowOutcome or the timeout below reopens things.
			self:SetChoicesEnabled(false)
			callback(eventId, choice.id)
			self:StartResponseTimeout(eventId)
		end)

		table.insert(self.choiceButtons, button)
	end

	self.backdrop.Visible = true
end

function EventUI.SetChoicesEnabled(self: EventUIHandle, enabled: boolean)
	for _, button in self.choiceButtons do
		-- Activated does not fire on an inactive GuiButton, so this is the lock
		-- itself and not just a visual state.
		button.Active = enabled
		button.TextTransparency = if enabled then 0 else 0.45
	end
end

-- The server answers every accepted choice, so silence means the answer was
-- refused or dropped. Rather than leaving a dead panel on screen, the choices
-- come back so the player can try again.
function EventUI.StartResponseTimeout(self: EventUIHandle, eventId: string)
	task.delay(Config.UI.EventResponseTimeoutSeconds, function()
		if self.activeEventId ~= eventId or self.outcomeLabel.Visible then
			return
		end
		warn("AGES: no response to that choice; re-enabling it")
		self:SetChoicesEnabled(true)
	end)
end

-- Replaces the choices with what happened, holds it long enough to read, then
-- clears. Ignores an outcome for an event that is no longer on screen.
function EventUI.ShowOutcome(self: EventUIHandle, eventId: string, outcome: string)
	if self.activeEventId ~= eventId then
		return
	end

	self.hideToken += 1
	local token = self.hideToken

	clearChoices(self)
	self.outcomeLabel.Text = outcome
	self.outcomeLabel.Visible = true

	task.delay(Config.UI.EventOutcomeSeconds, function()
		if self.hideToken ~= token then
			return
		end
		local fade = TweenInfo.new(Config.UI.NoticeFadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(self.outcomeLabel, fade, { TextTransparency = 1 }):Play()

		task.delay(Config.UI.NoticeFadeSeconds, function()
			if self.hideToken ~= token then
				return
			end
			self.outcomeLabel.TextTransparency = 0
			self:Hide()
		end)
	end)
end

return EventUI
