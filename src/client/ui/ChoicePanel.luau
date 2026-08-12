--!strict
-- The one panel. Everything the player is ever asked opens here: an event, the
-- offers in front of a person, the answers to a question in a lesson.
--
-- It was EventUI, and it was one of two ways to answer something -- the card you
-- were shown when the room could not be used, with pads on the floor being the
-- real interface. There is only one interface now. You click the three dots over
-- something's head and this is what comes up, every time, for everything. A player
-- learns to talk to this world once.
--
-- DELIVERY_STYLES is still keyed by the event's `delivery` field and is still
-- deliberately a closed record: add a variant to Types.EventDelivery and this file
-- stops type-checking until it has been given a presentation. What changed is that
-- the styles are no longer only for events. Anything the player walked across a
-- room and clicked on borrows `Interact`, which was already written for exactly
-- that -- bright, narrow, and barely dimming the world behind it, because the room
-- is the thing the player went to and taking it away would throw the journey out.
--
-- An enacted event still gets a banner first: the words arrive when the event
-- does, and the choices arrive when the player reaches whatever is carrying them.
-- That gap is the mechanic. Everything else opens complete.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local Money = require(game:GetService("ReplicatedStorage"):WaitForChild("Money"))
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
	-- than a decision being demanded.
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
	-- A birthday arriving rather than a thing in the room: nothing was walked to,
	-- so there is no room to preserve behind it.
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
	-- The player walked to this and clicked it. Narrow, bright and barely dimmed,
	-- because the room they crossed to get here is the point and should stay
	-- visible behind it — the opposite of Memory, which wants the world to fall
	-- away. Borrowed by people and lessons too: they are all the same sentence,
	-- which is "you went over to something and it had something to say".
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
-- Flatter and darker than idle. A locked choice has to read as part of the list --
-- it is still one of the things you could have done -- while being obviously not
-- pressable, so it recedes rather than being colored like a warning.
local CHOICE_LOCKED = Color3.fromRGB(28, 28, 33)
-- How far a locked choice's words are pulled toward invisible. Enough to read as
-- unavailable at a glance, not so far that the player cannot read what they are
-- missing. Safe range: 0.3-0.7.
local CHOICE_LOCKED_MUTE = 0.55

-- The price sits in its own right-aligned column rather than being appended to the
-- label, so that a list of priced choices lines its figures up and can be compared
-- down the column instead of hunted for at the end of each sentence.
local PRICE_WIDTH = 72
local PRICE_GAP = 10
local PRICE_COLOR = Color3.fromRGB(225, 205, 130)
-- Muted red only when the player cannot pay. The price itself is never red just for
-- existing -- spending money is a normal thing to do, and coloring every cost like a
-- penalty would tell the player the game disapproves of half its own content.
local PRICE_LOCKED_COLOR = Color3.fromRGB(196, 108, 104)

-- A note shares the price's column but not its color. Cooler and dimmer than a
-- figure, because a price is a fact about the choice and a note is a hedge about it
-- -- "they might say no" should read as the game being honest rather than as a
-- second number to add up. Wider too: it is words, and a clipped word is worse than
-- no word at all.
local NOTE_WIDTH = 118
local NOTE_COLOR = Color3.fromRGB(186, 178, 162)
local NOTE_TEXT_SIZE = 13

-- An enacted event's banner sits high and out of the way of whatever is carrying
-- the answer. Narrower than any panel: it is one or two sentences to glance at,
-- not something to sit and read.
local BANNER_ANCHOR_Y = 0.13
local BANNER_WIDTH = 440
-- Barely there. The banner must not become the thing the player is looking at --
-- the room is, and the room is where the thing they have to go and click is.
local BANNER_BACKDROP_TRANSPARENCY = 1
local BANNER_PANEL_TRANSPARENCY = 0.25

-- Said once, in the banner, because three dots over a dog's head do not explain
-- themselves the very first time a player sees them. Muted against the prompt so
-- it reads as an instruction rather than as part of the fiction.
local BANNER_HINT = "Click the dots to answer."
-- A Handled event has no dots and never opens a list, so the enacted hint would be
-- an instruction to click something that does not exist. What it says instead is
-- deliberately vague about *how*: each thing in the room is already wearing its own
-- instruction, and repeating one of them up here would quietly nominate it as the
-- real answer.
local HANDLED_HINT = "Answer by doing it."
local BANNER_HINT_SIZE = 14
local BANNER_HINT_MUTE = 0.45

-- What the panel needs to put a list of things in front of the player, for the
-- callers that are not events. An options table rather than five arguments because
-- the person and lesson call sites are in two different files and neither should
-- have to remember an order.
export type PanelOption = {
	id: string,
	label: string,
	cost: number?,
	-- Words in the same right-hand column a price uses, for a row whose caveat is not
	-- a figure. Ignored when `cost` is set: one column, one thing in it.
	note: string?,
	locked: boolean,
}

export type PanelContent = {
	-- What is currently open, used to ignore an outcome for something that has
	-- since been closed. An event id, a person id, a lesson question -- this file
	-- never interprets it, it only compares it.
	key: string,
	prompt: string,
	options: { PanelOption },
	-- The muted line under the choices. Two jobs, and they are the same shape so they
	-- share a slot rather than a second label:
	--
	--   * an instruction, for the rare list whose rows are not the interface -- a physical
	--     lesson's answers are discs on the floor, so its rows arrive locked and this is
	--     what says so.
	--   * a footnote, for a list that is a *statement* rather than a question -- a report
	--     card's rows are all locked and the line under them is what the year came to.
	--
	-- Multi-line prose is fine: the label wraps and grows. Read the way a banner's hint is,
	-- muted against the fiction, which suits both -- neither is the thing being said, both
	-- are said quietly underneath it.
	hint: string?,
	-- Overrides the style's prompt color for this one show, and nothing else on the panel.
	--
	-- Added for the gang bosses, who are the first speakers in the game whose words the
	-- player has to place: four of them say four different things in four different rooms,
	-- and which gang is talking is the single most useful fact on the panel. Passing their
	-- color is how a boss sounds like themselves without a second panel style per gang.
	--
	-- Optional and nil everywhere else on purpose. A person, a lesson and a report card are
	-- all one voice each, and a colored line on any of them would be decoration.
	accent: Color3?,
	-- Open in the PhoneCall voice rather than Interact: narrow, barely dimmed, blue
	-- accents -- the room stays visible because the player is still standing in it
	-- holding a phone.
	phone: boolean?,
	-- Where the answer goes. Held rather than routed through a remote here, so
	-- that a new kind of interactable needs no changes in this file at all.
	choose: (optionId: string) -> (),
}

local ChoicePanel = {}
ChoicePanel.__index = ChoicePanel

export type ChoicePanelHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		backdrop: Frame,
		panel: Frame,
		promptLabel: TextLabel,
		choicesFrame: Frame,
		hintLabel: TextLabel,
		outcomeLabel: TextLabel,
		-- The locked flag is carried alongside each button rather than read back off
		-- the instance, because SetChoicesEnabled re-enables the list after a timeout
		-- and needs to know which buttons were never enabled in the first place. A
		-- button that is inactive for both reasons cannot say which.
		choiceButtons: { { button: TextButton, locked: boolean } },
		activeKey: string?,
		onChoice: ((eventId: string, choiceId: string) -> ())?,
		hideToken: number,
		-- Held while an outcome is still on screen. In childhood a resolved event
		-- ends the year, and the birthday immediately offers the next one, so
		-- without this the answer to what just happened is wiped mid-sentence.
		queuedOffer: OfferedEvent?,
		-- The enacted event whose words are on screen as a banner, waiting for the
		-- player to go and click the thing that carries its choices. Held because
		-- the click arrives from somewhere else entirely -- the dots on a dog -- and
		-- carries nothing but an id.
		pendingEnacted: OfferedEvent?,
		-- Called when the panel hides for any reason -- including being overwritten by a
		-- different panel. The key is the one being closed, so a caller tracking multiple
		-- panels (lesson, phone) can clear the right one without watching every caller.
		onHidden: ((key: string) -> ())?,
	},
	ChoicePanel
))

function ChoicePanel.new(): ChoicePanelHandle
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesChoices"
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
	-- Load-bearing, and set explicitly rather than left to the default: an inactive
	-- frame passes input through to the world, so a transparent backdrop covering
	-- the screen costs the player nothing. Active would silently make everything
	-- behind it unclickable -- including the three dots this whole system runs on.
	backdrop.Active = false
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(0, 460, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = PANEL_DARK
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
		activeKey = nil,
		queuedOffer = nil,
		pendingEnacted = nil,
		onChoice = nil,
		hideToken = 0,
	}, ChoicePanel)
end

function ChoicePanel.OnChoice(self: ChoicePanelHandle, callback: (eventId: string, choiceId: string) -> ())
	self.onChoice = callback
end

function ChoicePanel.OnHidden(self: ChoicePanelHandle, callback: (key: string) -> ())
	self.onHidden = callback
end

local function clearChoices(self: ChoicePanelHandle)
	for _, entry in self.choiceButtons do
		entry.button:Destroy()
	end
	table.clear(self.choiceButtons)
end

function ChoicePanel.Hide(self: ChoicePanelHandle)
	self.hideToken += 1
	local previousKey = self.activeKey
	self.activeKey = nil
	-- Hide is only called on death or after an outcome has run its course, and
	-- both of those outrank anything still waiting behind them.
	self.queuedOffer = nil
	self.pendingEnacted = nil
	self.backdrop.Visible = false
	self.outcomeLabel.Visible = false
	self.hintLabel.Visible = false
	clearChoices(self)
	-- Anyone tracking which panel is open hears about the close. The callback fires
	-- after the state is torn down, so a listener clearing its own key (lesson,
	-- phone) does not race with a new panel being opened in the same frame.
	local onHidden = self.onHidden
	if onHidden ~= nil and previousKey ~= nil then
		onHidden(previousKey)
	end
end

-- One row per option. Shared by every caller rather than written once for events
-- and again for people, because the one thing that must never drift is what a
-- choice looks like when you read it: the player takes in three answers at a
-- glance and cannot be asked to learn two vocabularies to do it.
local function buildOptions(
	self: ChoicePanelHandle,
	style: DeliveryStyle,
	options: { PanelOption },
	choose: (optionId: string) -> ()
)
	for index, option in options do
		local locked = option.locked
		local cost = option.cost
		-- A figure wins the column outright. Nothing today sets both, and if something
		-- ever does, what it costs is the harder fact and the one worth the space.
		local note = if cost == nil then option.note else nil
		local columnWidth = if cost ~= nil then PRICE_WIDTH elseif note ~= nil then NOTE_WIDTH else 0

		local button = Instance.new("TextButton")
		button.Name = `Choice_{option.id}`
		button.Size = UDim2.new(1, 0, 0, CHOICE_HEIGHT)
		button.AutomaticSize = Enum.AutomaticSize.Y
		button.LayoutOrder = index
		button.BackgroundColor3 = if locked then CHOICE_LOCKED else CHOICE_IDLE
		button.BackgroundTransparency = 0.1
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		-- Activated does not fire on an inactive GuiButton, so this is the lock and
		-- not a hint about one. The server checks again regardless.
		button.Active = not locked
		button.Font = style.choiceFont
		button.TextSize = 15
		button.TextColor3 = style.choiceColor
		button.TextTransparency = if locked then CHOICE_LOCKED_MUTE else 0
		button.TextWrapped = true
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.Text = option.label
		button.Parent = self.choicesFrame

		local buttonPadding = Instance.new("UIPadding")
		buttonPadding.PaddingTop = UDim.new(0, 10)
		buttonPadding.PaddingBottom = UDim.new(0, 10)
		buttonPadding.PaddingLeft = UDim.new(0, 14)
		-- Widened only when the column has something in it, so that the overwhelming
		-- majority of choices -- the plain ones -- keep the full width for their words.
		buttonPadding.PaddingRight = UDim.new(0, if columnWidth > 0 then 14 + columnWidth + PRICE_GAP else 14)
		buttonPadding.Parent = button

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 8)
		buttonCorner.Parent = button

		if cost ~= nil then
			local priceLabel = Instance.new("TextLabel")
			priceLabel.Name = "Price"
			priceLabel.Size = UDim2.new(0, PRICE_WIDTH, 1, 0)
			-- Positioned against the button's right edge rather than inside the
			-- padded area: UIPadding insets children, so the reserved gap above is
			-- exactly what this label sits in.
			priceLabel.AnchorPoint = Vector2.new(0, 0.5)
			priceLabel.Position = UDim2.new(1, PRICE_GAP, 0.5, 0)
			priceLabel.BackgroundTransparency = 1
			priceLabel.Font = Enum.Font.GothamMedium
			priceLabel.TextSize = 15
			priceLabel.TextXAlignment = Enum.TextXAlignment.Right
			priceLabel.TextColor3 = if locked then PRICE_LOCKED_COLOR else PRICE_COLOR
			priceLabel.Text = Money.Format(cost)
			priceLabel.Parent = button
		elseif note ~= nil then
			local noteLabel = Instance.new("TextLabel")
			noteLabel.Name = "Note"
			noteLabel.Size = UDim2.new(0, NOTE_WIDTH, 1, 0)
			noteLabel.AnchorPoint = Vector2.new(0, 0.5)
			noteLabel.Position = UDim2.new(1, PRICE_GAP, 0.5, 0)
			noteLabel.BackgroundTransparency = 1
			noteLabel.Font = Enum.Font.Gotham
			noteLabel.TextSize = NOTE_TEXT_SIZE
			noteLabel.TextXAlignment = Enum.TextXAlignment.Right
			noteLabel.TextColor3 = NOTE_COLOR
			noteLabel.TextTransparency = if locked then CHOICE_LOCKED_MUTE else 0
			noteLabel.Text = note
			noteLabel.Parent = button
		end

		-- No hover response on a locked choice. A row that lights up under the cursor
		-- and then does nothing when pressed is worse than one that never reacted.
		if not locked then
			button.MouseEnter:Connect(function()
				button.BackgroundColor3 = CHOICE_HOVER
				button.TextColor3 = style.accent
			end)
			button.MouseLeave:Connect(function()
				button.BackgroundColor3 = CHOICE_IDLE
				button.TextColor3 = style.choiceColor
			end)
		end

		button.Activated:Connect(function()
			local key = self.activeKey
			if key == nil then
				return
			end

			-- Locked immediately so a double-click can't send two answers. The
			-- server would refuse the second anyway; this stops the UI implying
			-- otherwise. ShowOutcome or the timeout below reopens things.
			self:SetChoicesEnabled(false)
			choose(option.id)
			self:StartResponseTimeout(key)
		end)

		table.insert(self.choiceButtons, { button = button, locked = locked })
	end
end

local function applyStyle(self: ChoicePanelHandle, style: DeliveryStyle, prompt: string)
	self.backdrop.BackgroundTransparency = style.backdropTransparency
	self.panel.Size = UDim2.new(0, style.width, 0, 0)
	self.panel.BackgroundTransparency = style.panelTransparency
	self.panel.BackgroundColor3 = style.panelColor
	self.panel.Position = UDim2.new(0.5, 0, style.anchorY, 0)

	self.outcomeLabel.TextColor3 = style.promptColor:Lerp(style.panelColor, OUTCOME_MUTE)

	self.promptLabel.Font = style.promptFont
	self.promptLabel.TextSize = style.promptSize
	self.promptLabel.TextColor3 = style.promptColor
	self.promptLabel.Text = prompt

	self.outcomeLabel.Visible = false
	self.outcomeLabel.Text = ""
end

-- Anything that is not an event: the offers in front of a person, the answers to a
-- question. Always complete, always immediate -- the player has already walked over
-- and clicked, and there is nothing left to wait for.
--
-- False means it did not open. Worth returning rather than swallowing because the
-- lesson calls this off a push that repeats four times a second, and a refusal it
-- can see is a refusal it will simply try again on the next one.
function ChoicePanel.ShowOptions(self: ChoicePanelHandle, content: PanelContent): boolean
	-- An outcome still on screen is still being read, and unlike an event nothing
	-- here is racing a birthday: the person will still be standing there in a
	-- second. Refused rather than queued, so a reply never gets cut off by the
	-- player clicking the same dots again.
	if self.outcomeLabel.Visible then
		return false
	end

	self.hideToken += 1
	clearChoices(self)

	self.activeKey = content.key
	self.pendingEnacted = nil

	local style = if content.phone then DELIVERY_STYLES.PhoneCall else DELIVERY_STYLES.Interact
	applyStyle(self, style, content.prompt)
	-- After applyStyle rather than instead of it, which is what makes this safe to leave
	-- unset: every show reapplies the style's own color first, so a colored gang panel
	-- cannot leak its accent into the next person who talks.
	local accent = content.accent
	if accent ~= nil then
		self.promptLabel.TextColor3 = accent
	end
	buildOptions(self, style, content.options, content.choose)

	-- Muted the way a banner's hint is, so it reads as an instruction rather than as
	-- part of the fiction. Absent for the ordinary list, where the rows explain
	-- themselves -- a hint only earns its line when the rows are not the interface.
	local hint = content.hint
	self.hintLabel.Visible = hint ~= nil
	if hint ~= nil then
		self.hintLabel.Text = hint
		self.hintLabel.TextColor3 = style.promptColor:Lerp(style.panelColor, BANNER_HINT_MUTE)
	end

	self.backdrop.Visible = true
	return true
end

-- Takes down a list this file opened, and only that exact one. The lesson is the
-- reason this exists: its questions expire on a clock the server owns, so the panel
-- has to be closable by something other than the click that opened it -- otherwise
-- the answers to question three sit there while the teacher explains it.
--
-- Keyed for the same reason ShowOutcome is. Between the question expiring and this
-- being called, a birthday can have put an event on screen; closing then would take
-- down somebody else's panel on the strength of a lesson ending.
-- Whether the panel is currently holding a particular key. The one honest way for a
-- caller that remembers its own open key -- the phone panel does -- to tell whether
-- something else took the panel over, since the overwriting shows do not announce it.
function ChoicePanel.IsOpen(self: ChoicePanelHandle, key: string): boolean
	return self.activeKey == key
end

function ChoicePanel.CloseOptions(self: ChoicePanelHandle, key: string): boolean
	if self.activeKey ~= key or self.outcomeLabel.Visible then
		return false
	end
	self:Hide()
	return true
end

function ChoicePanel.Show(self: ChoicePanelHandle, offered: OfferedEvent)
	-- An outcome on screen is still being read. Hold the new prompt rather than
	-- overwriting it; ShowOutcome hands over once it has finished.
	--
	-- Except when the new prompt is enacted, which cannot wait: the thing carrying
	-- its answers is already standing in the room with dots over its head, so
	-- holding the banner back would leave a window in which the player can open a
	-- question they have not been shown. Cutting an outcome short is the lesser of
	-- those two.
	if self.outcomeLabel.Visible and offered.resolution == "Panel" then
		self.queuedOffer = offered
		return
	end

	self.hideToken += 1
	clearChoices(self)

	local style = DELIVERY_STYLES[offered.delivery]
	-- Two questions, deliberately not one. A banner is what both of the in-world
	-- resolutions look like: a line of framing that stays out of the room. Whether
	-- this panel is still holding a list behind it is a different question, and only
	-- an enacted event is -- a Handled one has no list anywhere, so there is nothing
	-- for arriving to open.
	local banner = offered.resolution ~= "Panel"
	local enacted = offered.resolution == "Enacted"

	self.activeKey = offered.id
	applyStyle(self, style, offered.prompt)

	-- An enacted event overrides the style's framing but keeps its voice. The
	-- colors, fonts and sizes are the delivery's; only the things that would come
	-- between the player and the room -- the dimming, the width, the position --
	-- are replaced.
	if banner then
		self.backdrop.BackgroundTransparency = BANNER_BACKDROP_TRANSPARENCY
		self.panel.Size = UDim2.new(0, BANNER_WIDTH, 0, 0)
		self.panel.BackgroundTransparency = BANNER_PANEL_TRANSPARENCY
		self.panel.Position = UDim2.new(0.5, 0, BANNER_ANCHOR_Y, 0)
	end

	self.hintLabel.Visible = banner
	self.hintLabel.Text = if enacted then BANNER_HINT else HANDLED_HINT
	self.hintLabel.TextColor3 = style.promptColor:Lerp(style.panelColor, BANNER_HINT_MUTE)

	-- No buttons at all while the answers are still out there in the room. Not
	-- disabled buttons -- absent ones, so there is exactly one way to answer and no
	-- chance of a greyed-out row implying the panel is the real interface and the
	-- thing standing in front of you is decoration.
	if banner then
		-- Only an enacted event is held for reopening. A Handled one is shown and then
		-- let go of: nothing the player can click will ever ask for its list, and
		-- keeping it here would leave a panel that could be opened by a stray dot click
		-- from some other scene.
		self.pendingEnacted = if enacted then offered else nil
		self.backdrop.Visible = true
		return
	end

	self.pendingEnacted = nil
	buildOptions(self, style, offered.choices, function(choiceId: string)
		local callback = self.onChoice
		if callback ~= nil then
			callback(offered.id, choiceId)
		end
	end)

	self.backdrop.Visible = true
end

-- The banner becoming the panel, when the player reaches whatever was carrying the
-- answers and clicks it. Takes the event id so that clicking the dots on a dog from
-- a scene that has already been resolved cannot reopen it.
function ChoicePanel.OpenEnacted(self: ChoicePanelHandle, eventId: string): boolean
	local offered = self.pendingEnacted
	if offered == nil or offered.id ~= eventId then
		return false
	end

	self.pendingEnacted = nil
	self.hideToken += 1
	clearChoices(self)

	-- Deliberately not the enacted framing. The player has arrived; the room has
	-- done its job and the question is now the thing being answered, so it gets the
	-- panel its delivery would always have had.
	local style = DELIVERY_STYLES[offered.delivery]
	self.activeKey = offered.id
	applyStyle(self, style, offered.prompt)
	self.hintLabel.Visible = false

	buildOptions(self, style, offered.choices, function(choiceId: string)
		local callback = self.onChoice
		if callback ~= nil then
			callback(offered.id, choiceId)
		end
	end)

	self.backdrop.Visible = true
	return true
end

-- Closes the whole list while an answer is in flight, and reopens it if none comes
-- back. A choice the player cannot afford stays shut through both: enabling is
-- "let go of the list", not "make everything available".
function ChoicePanel.SetChoicesEnabled(self: ChoicePanelHandle, enabled: boolean)
	for _, entry in self.choiceButtons do
		-- Activated does not fire on an inactive GuiButton, so this is the lock
		-- itself and not just a visual state.
		entry.button.Active = enabled and not entry.locked
		if entry.locked then
			continue
		end
		entry.button.TextTransparency = if enabled then 0 else 0.45
	end
end

-- The server answers every accepted choice, so silence means the answer was
-- refused or dropped. Rather than leaving a dead panel on screen, the choices
-- come back so the player can try again.
function ChoicePanel.StartResponseTimeout(self: ChoicePanelHandle, key: string)
	task.delay(Config.UI.EventResponseTimeoutSeconds, function()
		if self.activeKey ~= key or self.outcomeLabel.Visible then
			return
		end
		warn("AGES: no response to that choice; re-enabling it")
		self:SetChoicesEnabled(true)
	end)
end

-- Replaces the choices with what happened, holds it long enough to read, then
-- clears. Ignores an outcome for something that is no longer on screen.
function ChoicePanel.ShowOutcome(self: ChoicePanelHandle, key: string, outcome: string)
	if self.activeKey ~= key then
		return
	end

	self.hideToken += 1
	local token = self.hideToken

	clearChoices(self)
	-- The question has been answered, so the instruction stops being true.
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

return ChoicePanel
