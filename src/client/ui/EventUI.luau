--!strict
-- The delivery layer. The server decides which event fires; this decides how it
-- reaches the player, keyed off the event's `delivery` field.
--
-- DELIVERY_STYLES is deliberately a closed record rather than a loose map: add
-- a variant to Types.EventDelivery and this file stops type-checking until it
-- has been given a presentation. When step 3 brings a world, NPCApproach /
-- Letter / PhoneCall / Location are added here, and nothing on the server or in
-- the content modules has to move.
--
-- `resolution` is the second axis and it cuts across all of those. A Panel event
-- is the card this file has always drawn. An Enacted one is answered by walking
-- onto a marker in the room, so the card becomes a banner: same words, same
-- style, but nothing dimmed, nothing to click, and nothing standing between the
-- player and the room they are about to answer the question in. The styles
-- below are shared by both, which is what keeps a letter reading as paper
-- whichever way it is answered.

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
	-- The panel itself. A field rather than a constant because Letter is paper:
	-- dark ink on a pale page, where every other delivery is light text on dark.
	-- Without this the letter's prompt color would be unreadable on its own card.
	panelColor: Color3,
	-- Where the panel's center sits vertically, 0 top to 1 bottom. Only the
	-- visitor moves off center, and only because the person who walked in to say
	-- this is standing where a centered panel would cover them.
	anchorY: number,
	promptFont: Enum.Font,
	promptSize: number,
	promptColor: Color3,
	choiceFont: Enum.Font,
	choiceColor: Color3,
	accent: Color3,
}

-- What every delivery that isn't paper uses.
local PANEL_DARK = Color3.fromRGB(18, 18, 22)
local PANEL_CENTER = 0.5

-- How far the outcome line is pulled back toward the panel behind it. Derived
-- from the prompt color rather than authored per style, so it stays readable on
-- the pale letter page and the dark cards alike without six more colors to keep
-- in step with each other. Safe range: 0.2-0.5.
local OUTCOME_MUTE = 0.35

local DELIVERY_STYLES: {
	Memory: DeliveryStyle,
	Direct: DeliveryStyle,
	Interact: DeliveryStyle,
	Letter: DeliveryStyle,
	PhoneCall: DeliveryStyle,
	NPCApproach: DeliveryStyle,
} = {
	-- Early childhood. Dimmer, wider, quieter — a recollection surfacing rather
	-- than a decision being demanded. Held until the toddler house exists and
	-- these entries can be reached by walking to the thing instead.
	Memory = {
		width = 520,
		backdropTransparency = 0.25,
		panelTransparency = 1,
		panelColor = PANEL_DARK,
		anchorY = PANEL_CENTER,
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
		panelColor = PANEL_DARK,
		anchorY = PANEL_CENTER,
		promptFont = Enum.Font.GothamMedium,
		promptSize = 17,
		promptColor = Color3.fromRGB(240, 240, 245),
		choiceFont = Enum.Font.GothamMedium,
		choiceColor = Color3.fromRGB(225, 225, 235),
		accent = Color3.fromRGB(110, 160, 220),
	},
	-- The player walked to this. Narrow, bright and barely dimmed, because the
	-- room they crossed to get here is the point and should stay visible behind
	-- it — the opposite of Memory, which wants the world to fall away.
	Interact = {
		width = 400,
		backdropTransparency = 0.8,
		panelTransparency = 0.02,
		panelColor = PANEL_DARK,
		anchorY = PANEL_CENTER,
		promptFont = Enum.Font.GothamMedium,
		promptSize = 18,
		promptColor = Color3.fromRGB(255, 252, 245),
		choiceFont = Enum.Font.GothamMedium,
		choiceColor = Color3.fromRGB(238, 234, 226),
		accent = Color3.fromRGB(245, 205, 120),
	},
	-- Something the player picked up and is now reading, so the panel is the
	-- page: opaque, warm, serif, and the widest of the world deliveries because
	-- the fiction is a sheet of paper rather than a card floating over a room.
	Letter = {
		width = 470,
		backdropTransparency = 0.6,
		panelTransparency = 0,
		panelColor = Color3.fromRGB(240, 233, 216),
		anchorY = PANEL_CENTER,
		promptFont = Enum.Font.Merriweather,
		promptSize = 17,
		promptColor = Color3.fromRGB(48, 42, 34),
		choiceFont = Enum.Font.GothamMedium,
		choiceColor = Color3.fromRGB(228, 224, 214),
		accent = Color3.fromRGB(196, 158, 92),
	},
	-- A voice, not a document. Narrow and tall-feeling, barely dimmed so the room
	-- the player is standing in stays behind it, because they are still standing
	-- in it holding a phone.
	PhoneCall = {
		width = 360,
		backdropTransparency = 0.75,
		panelTransparency = 0.04,
		panelColor = PANEL_DARK,
		anchorY = PANEL_CENTER,
		promptFont = Enum.Font.GothamMedium,
		promptSize = 17,
		promptColor = Color3.fromRGB(236, 244, 250),
		choiceFont = Enum.Font.GothamMedium,
		choiceColor = Color3.fromRGB(214, 226, 236),
		accent = Color3.fromRGB(120, 190, 235),
	},
	-- Someone is standing in front of the player saying this. The least dimming
	-- of any style on purpose: the visitor took the trouble to walk in, and a
	-- backdrop that hides them would throw away the entire delivery.
	NPCApproach = {
		width = 420,
		backdropTransparency = 0.88,
		panelTransparency = 0.06,
		panelColor = PANEL_DARK,
		-- Low enough that a visitor's head and shoulders clear the panel.
		anchorY = 0.68,
		promptFont = Enum.Font.GothamMedium,
		promptSize = 18,
		promptColor = Color3.fromRGB(252, 250, 246),
		choiceFont = Enum.Font.GothamMedium,
		choiceColor = Color3.fromRGB(234, 230, 224),
		accent = Color3.fromRGB(232, 168, 140),
	},
}

local CHOICE_HEIGHT = 38
local CHOICE_IDLE = Color3.fromRGB(38, 38, 44)
local CHOICE_HOVER = Color3.fromRGB(54, 54, 62)

-- An enacted event's banner sits high, out of the way of both the character and
-- the markers fanned in front of them. Narrower than any panel: it is one or two
-- sentences to glance at, not something to sit and read.
local BANNER_ANCHOR_Y = 0.13
local BANNER_WIDTH = 440
-- Barely there. The banner must not become the thing the player is looking at --
-- the room is, and the room is where the answer is.
local BANNER_BACKDROP_TRANSPARENCY = 1
local BANNER_PANEL_TRANSPARENCY = 0.25

-- Said once, in the banner, because "walk onto one" is not discoverable from
-- three glowing discs alone the first time a player sees them. Muted against the
-- prompt so it reads as an instruction rather than as part of the fiction.
local BANNER_HINT = "Walk to your answer."
local BANNER_HINT_SIZE = 14
local BANNER_HINT_MUTE = 0.45

local EventUI = {}
EventUI.__index = EventUI

export type EventUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		backdrop: Frame,
		panel: Frame,
		promptLabel: TextLabel,
		choicesFrame: Frame,
		hintLabel: TextLabel,
		outcomeLabel: TextLabel,
		choiceButtons: { TextButton },
		activeEventId: string?,
		onChoice: ((eventId: string, choiceId: string) -> ())?,
		hideToken: number,
		-- Held while an outcome is still on screen. In childhood a resolved event
		-- ends the year, and the birthday immediately offers the next one, so
		-- without this the answer to what just happened is wiped mid-sentence.
		queuedOffer: OfferedEvent?,
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
	-- Load-bearing for enacted events, and set explicitly rather than left to the
	-- default: an inactive frame passes mouse input through to the world, so a
	-- fully transparent backdrop covering the screen costs the player nothing.
	-- Active would silently make the room unclickable behind an invisible sheet.
	backdrop.Active = false
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

	local hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "Hint"
	hintLabel.Size = UDim2.new(1, 0, 0, 0)
	hintLabel.AutomaticSize = Enum.AutomaticSize.Y
	hintLabel.BackgroundTransparency = 1
	hintLabel.TextWrapped = true
	hintLabel.TextXAlignment = Enum.TextXAlignment.Left
	hintLabel.Font = Enum.Font.Gotham
	hintLabel.TextSize = BANNER_HINT_SIZE
	-- Between the choices and the outcome, so the banner reads prompt-then-hint
	-- and the outcome still lands at the bottom when the choice is made.
	hintLabel.LayoutOrder = 2
	hintLabel.Visible = false
	hintLabel.Text = BANNER_HINT
	hintLabel.Parent = panel

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
	outcomeLabel.LayoutOrder = 3
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
		hintLabel = hintLabel,
		outcomeLabel = outcomeLabel,
		choiceButtons = {},
		activeEventId = nil,
		queuedOffer = nil,
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
	-- Hide is only called on death or after an outcome has run its course, and
	-- both of those outrank anything still waiting behind them.
	self.queuedOffer = nil
	self.backdrop.Visible = false
	self.outcomeLabel.Visible = false
	self.hintLabel.Visible = false
	clearChoices(self)
end

function EventUI.Show(self: EventUIHandle, offered: OfferedEvent)
	-- An outcome on screen is still being read. Hold the new prompt rather than
	-- overwriting it; ShowOutcome hands over once it has finished.
	--
	-- Except when the new prompt is enacted, which cannot wait: its markers are
	-- already standing in the room and already answerable, so holding the banner
	-- back would leave a window in which the player can walk onto a question they
	-- have not been shown. Cutting an outcome short is the lesser of those two.
	if self.outcomeLabel.Visible and offered.resolution ~= "Enacted" then
		self.queuedOffer = offered
		return
	end

	self.hideToken += 1
	clearChoices(self)

	local style = DELIVERY_STYLES[offered.delivery]
	local enacted = offered.resolution == "Enacted"

	self.activeEventId = offered.id
	-- An enacted event overrides the style's framing but keeps its voice. The
	-- colors, fonts and sizes are the delivery's; only the things that would come
	-- between the player and the room -- the dimming, the width, the position --
	-- are replaced.
	self.backdrop.BackgroundTransparency = if enacted
		then BANNER_BACKDROP_TRANSPARENCY
		else style.backdropTransparency
	self.panel.Size = UDim2.new(0, if enacted then BANNER_WIDTH else style.width, 0, 0)
	self.panel.BackgroundTransparency = if enacted then BANNER_PANEL_TRANSPARENCY else style.panelTransparency
	self.panel.BackgroundColor3 = style.panelColor
	self.panel.Position = UDim2.new(0.5, 0, if enacted then BANNER_ANCHOR_Y else style.anchorY, 0)

	self.outcomeLabel.TextColor3 = style.promptColor:Lerp(style.panelColor, OUTCOME_MUTE)

	self.promptLabel.Font = style.promptFont
	self.promptLabel.TextSize = style.promptSize
	self.promptLabel.TextColor3 = style.promptColor
	self.promptLabel.Text = offered.prompt

	self.hintLabel.Visible = enacted
	self.hintLabel.TextColor3 = style.promptColor:Lerp(style.panelColor, BANNER_HINT_MUTE)

	self.outcomeLabel.Visible = false
	self.outcomeLabel.Text = ""

	-- No buttons at all when the choices are standing in the room. Not disabled
	-- buttons -- absent ones, so there is exactly one way to answer and no chance
	-- of a greyed-out row implying the panel is the real interface and the markers
	-- are decoration.
	if enacted then
		self.backdrop.Visible = true
		return
	end

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
	-- The question has been answered, so "walk to your answer" stops being true.
	self.hintLabel.Visible = false
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

			local queued = self.queuedOffer
			self.queuedOffer = nil
			if queued ~= nil then
				self.outcomeLabel.Visible = false
				self:Show(queued)
			else
				self:Hide()
			end
		end)
	end)
end

return EventUI
