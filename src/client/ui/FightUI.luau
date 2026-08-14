--!strict
-- The fight, drawn.
--
-- Bottom centre, and alone in taking that spot -- every other activity surface in the game
-- sits in a bottom corner because the player is reading it *while* doing something else.
-- This one is the something else. A fight is the only thing in AGES where a misread costs
-- you the round in under a second, so the panel is where the eyes already are.
--
-- Three buttons, and the panel's entire job is to make the fourth thing -- *when* -- legible:
--
--   The opponent's tell is the largest moving thing on screen. It fills, and their strike
--   lands the instant it is full. That bar is the whole read; if a player can only look at
--   one element, this is the one worth looking at, so it is drawn wider and brighter than
--   the player's own bars.
--
--   The power meter is the only place the overcharge decision is visible. It carries three
--   marks -- jab, guard-break, overcharge -- because "hold it past the second line" is a
--   thing a player can aim at, and "hold it for about 0.7 seconds" is not. The marks are
--   drawn from the *server's* numbers, sent on the state, so the line the player aims at
--   and the line the server judges cannot drift apart.
--
--   The lockout greys the buttons out. Not because the player needs telling that input is
--   refused -- they will feel that -- but because a punish window the opponent earned
--   should be visibly theirs, rather than reading as the game having dropped an input.
--
-- Footing, not health. Nothing here draws a health bar, a damage number or a hit spark,
-- and nothing here ever should: the contest is over balance, both fighters get up
-- afterwards, and the surface has to say that as plainly as the mechanic does.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage:WaitForChild("Types"))

type FightState = Types.FightState

local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local CAPTION_COLOR = Color3.fromRGB(146, 150, 162)
local TRACK_COLOR = Color3.fromRGB(38, 39, 46)

-- The two fighters, told apart by colour and never by position alone. The opponent is warm
-- and the player is cool, held consistently across the footing bars so a glance at the
-- shape of the panel answers "who is winning" without reading a single word.
local FOE_COLOR = Color3.fromRGB(224, 108, 96)
local SELF_COLOR = Color3.fromRGB(120, 178, 224)

-- The tell. Its own colour, hotter than anything else drawn, because it is the one element
-- the player is punished for missing.
local WIND_COLOR = Color3.fromRGB(244, 172, 72)

-- Stamina. Deliberately quiet: it is a budget, not a threat, and a stamina bar that shouts
-- pulls attention off the tell at exactly the wrong moment.
local STAMINA_COLOR = Color3.fromRGB(120, 196, 150)
local STAMINA_LOW_COLOR = Color3.fromRGB(212, 176, 92)

-- Below this share of the pool there is not enough left for a sidestep, and the bar says so
-- by changing colour. Not read from Config: the exact costs vary per action, and what this
-- is marking is "you are nearly out of answers", which is a feeling rather than a threshold.
local STAMINA_LOW_SHARE = 0.3

-- The power meter. It climbs through three colours as it passes the three marks, which is
-- the cheapest possible way to say "this is now a different strike than it was".
--
-- Cool, then warm, then hot, in that order and matching what each zone costs: the guard
-- break is the hottest because it is the furthest out and the most expensive, sitting above
-- the overcharge rather than below it.
local CHARGE_COLOR = Color3.fromRGB(150, 196, 214)
local CHARGE_OVER_COLOR = Color3.fromRGB(214, 196, 130)
local CHARGE_BREAK_COLOR = Color3.fromRGB(236, 136, 96)
local MARK_COLOR = Color3.fromRGB(96, 100, 112)

local GOOD_COLOR = Color3.fromRGB(120, 208, 140)
local BAD_COLOR = Color3.fromRGB(228, 148, 84)

local BUTTON_COLOR = Color3.fromRGB(44, 46, 56)
local BUTTON_HELD_COLOR = Color3.fromRGB(78, 82, 98)
local BUTTON_TEXT_COLOR = Color3.fromRGB(228, 231, 240)
local BUTTON_LOCKED_COLOR = Color3.fromRGB(28, 29, 35)
local BUTTON_LOCKED_TEXT_COLOR = Color3.fromRGB(92, 95, 104)

local PANEL_WIDTH = 460
local BAR_HEIGHT = 12
local TELL_HEIGHT = 18
local BUTTON_HEIGHT = 52

-- How fast a bar chases the number behind it. Long enough to read as a thing moving rather
-- than a number jumping, short enough that it has always caught up before the next tick --
-- the server pushes at Config.Fight.TickSeconds, and a bar still travelling when the next
-- state arrives lies about the current footing at the exact moment it matters.
local BAR_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- The tell and the power meter are not tweened at all. Both are read as *positions in
-- time*, and smoothing either one puts the drawn edge behind the truth by a frame or two,
-- which on a 0.55-second scrapper wind-up is the difference between blocking and not.

-- What the opponent is doing, in the player's words. Keyed by Types.FightState.foeIntent.
--
-- Not verified at require time, unlike HuntUI's reveal sentences: those are checked against
-- a Config table that can grow without this file noticing, whereas these keys come from a
-- type union, so a check here would only be this file confirming its own spelling. An
-- intent with no word falls back to the raw key in Set, which is ugly on screen and
-- therefore reports itself the first time it happens.
local INTENT_WORD: { [string]: string } = {
	wait = "Sizing you up",
	close = "Closing in",
	wind = "Winding up",
	guard = "Guarding",
	recover = "Off balance",
	down = "Down",
}

local FightUI = {}
FightUI.__index = FightUI

export type FightUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		-- The squaring-up card, which is a different shape of thing to the fight and so
		-- gets its own frame rather than a mode of the same one: it is prose, and the
		-- fight is instruments.
		card: Frame,
		cardNameLabel: TextLabel,
		cardStyleLabel: TextLabel,
		cardBlurbLabel: TextLabel,
		-- The fight proper.
		bout: Frame,
		foeNameLabel: TextLabel,
		foeFooting: Frame,
		intentLabel: TextLabel,
		tellTrack: Frame,
		tellFill: Frame,
		selfFooting: Frame,
		staminaFill: Frame,
		chargeTrack: Frame,
		chargeFill: Frame,
		jabMark: Frame,
		breakMark: Frame,
		overMark: Frame,
		beatLabel: TextLabel,
		strikeButton: TextButton,
		guardButton: TextButton,
		stepButton: TextButton,
		resultLabel: TextLabel,
		-- Which buttons are currently held, so a lockout that arrives mid-hold can drop
		-- them without the client and the server disagreeing about what is held.
		holding: { [string]: boolean },
		-- Whether input is refused right now, recomputed on every push. Held on the
		-- handle because the input connections fire outside Set and have to know.
		locked: boolean,
		onStrike: ((held: boolean) -> ())?,
		onGuard: ((held: boolean) -> ())?,
		onSidestep: (() -> ())?,
	},
	FightUI
))

-- The one path that changes a held button.
--
-- There is exactly one of these, at module scope rather than inside `new`, because both the
-- input connections and Set have to be able to release a hold -- and a release the server is
-- never told about is the worst bug this panel can have. Two copies of this would be two
-- places for that to go missing from.
local function setHeld(self: FightUIHandle, action: string, held: boolean)
	if self.holding[action] == held then
		return
	end
	-- A press while locked out is dropped, but a *release* while locked out is not: the
	-- lockout may have arrived mid-hold, and the server has to be told the button is no
	-- longer down or it will read the next press as a continuation of this one.
	if held and self.locked then
		return
	end
	self.holding[action] = held

	local strike = self.onStrike
	local guard = self.onGuard
	if action == "strike" and strike ~= nil then
		strike(held)
	elseif action == "guard" and guard ~= nil then
		guard(held)
	end

	local button = if action == "strike" then self.strikeButton else self.guardButton
	button.BackgroundColor3 = if held
		then BUTTON_HELD_COLOR
		elseif self.locked then BUTTON_LOCKED_COLOR
		else BUTTON_COLOR
end

local function makeLabel(
	parent: Instance,
	order: number,
	size: number,
	color: Color3,
	font: Enum.Font
): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.TextColor3 = color
	label.Text = ""
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

-- A track with a fill in it. Returns the fill, because the track never changes once built
-- and holding a reference to something nothing writes to is exactly the orphaned state the
-- house rules are against.
local function makeBar(parent: Instance, order: number, height: number, color: Color3): Frame
	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, height)
	track.BackgroundColor3 = TRACK_COLOR
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.LayoutOrder = order
	track.Parent = parent

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 3)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fill

	return fill
end

-- One of the three lines across the power meter. Drawn inside the track so it is behind
-- the fill's leading edge as the fill passes it, which is what makes crossing a mark read
-- as crossing something.
local function makeMark(track: Frame, share: number): Frame
	local mark = Instance.new("Frame")
	mark.Size = UDim2.new(0, 2, 1, 0)
	mark.Position = UDim2.new(share, -1, 0, 0)
	mark.BackgroundColor3 = MARK_COLOR
	mark.BorderSizePixel = 0
	mark.ZIndex = 3
	mark.Parent = track
	return mark
end

local function makeButton(parent: Instance, order: number, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0.32, 0, 0, BUTTON_HEIGHT)
	button.BackgroundColor3 = BUTTON_COLOR
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 15
	button.TextColor3 = BUTTON_TEXT_COLOR
	button.Text = text
	button.LayoutOrder = order
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	return button
end

function FightUI.new(): FightUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesFight"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 3

	local panel = Instance.new("Frame")
	panel.Name = "FightPanel"
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -16)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = panel

	local panelLayout = Instance.new("UIListLayout")
	panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
	panelLayout.Padding = UDim.new(0, 8)
	panelLayout.Parent = panel

	-- --------------------------------------------------------------
	-- Squaring up.
	-- --------------------------------------------------------------

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundTransparency = 1
	card.LayoutOrder = 0
	card.Parent = panel

	local cardLayout = Instance.new("UIListLayout")
	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cardLayout.Padding = UDim.new(0, 4)
	cardLayout.Parent = card

	local cardNameLabel = makeLabel(card, 0, 18, TITLE_COLOR, Enum.Font.GothamBold)
	local cardStyleLabel = makeLabel(card, 1, 13, FOE_COLOR, Enum.Font.GothamMedium)
	-- The advice, and the only place in the fight where the player is told anything in
	-- words. It is on the card and never during the bout: reading a sentence takes longer
	-- than a scrapper's wind-up, so help that arrives mid-fight is help that gets you hit.
	local cardBlurbLabel = makeLabel(card, 2, 13, CAPTION_COLOR, Enum.Font.Gotham)

	-- --------------------------------------------------------------
	-- The fight.
	-- --------------------------------------------------------------

	local bout = Instance.new("Frame")
	bout.Name = "Bout"
	bout.Size = UDim2.new(1, 0, 0, 0)
	bout.AutomaticSize = Enum.AutomaticSize.Y
	bout.BackgroundTransparency = 1
	bout.LayoutOrder = 1
	bout.Parent = panel

	local boutLayout = Instance.new("UIListLayout")
	boutLayout.SortOrder = Enum.SortOrder.LayoutOrder
	boutLayout.Padding = UDim.new(0, 5)
	boutLayout.Parent = bout

	local foeNameLabel = makeLabel(bout, 0, 14, TITLE_COLOR, Enum.Font.GothamBold)
	local foeFooting = makeBar(bout, 1, BAR_HEIGHT, FOE_COLOR)
	local intentLabel = makeLabel(bout, 2, 13, CAPTION_COLOR, Enum.Font.GothamMedium)

	-- The tell, taller than every other bar on the panel. The size *is* the signposting:
	-- the one thing worth watching should be the one thing hardest to miss.
	local tellTrack = Instance.new("Frame")
	tellTrack.Name = "TellTrack"
	tellTrack.Size = UDim2.new(1, 0, 0, TELL_HEIGHT)
	tellTrack.BackgroundColor3 = TRACK_COLOR
	tellTrack.BorderSizePixel = 0
	tellTrack.ClipsDescendants = true
	tellTrack.Visible = false
	tellTrack.LayoutOrder = 3
	tellTrack.Parent = bout

	local tellCorner = Instance.new("UICorner")
	tellCorner.CornerRadius = UDim.new(0, 3)
	tellCorner.Parent = tellTrack

	local tellFill = Instance.new("Frame")
	tellFill.Name = "Fill"
	tellFill.Size = UDim2.new(0, 0, 1, 0)
	tellFill.BackgroundColor3 = WIND_COLOR
	tellFill.BorderSizePixel = 0
	tellFill.Parent = tellTrack

	local tellFillCorner = Instance.new("UICorner")
	tellFillCorner.CornerRadius = UDim.new(0, 3)
	tellFillCorner.Parent = tellFill

	-- A gap between their half of the panel and yours. The two footing bars are the same
	-- shape and mean opposite things, and something has to sit between them or the eye
	-- reads one four-bar stack instead of two fighters.
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.BackgroundColor3 = TRACK_COLOR
	divider.BorderSizePixel = 0
	divider.LayoutOrder = 4
	divider.Parent = bout

	local selfFooting = makeBar(bout, 5, BAR_HEIGHT, SELF_COLOR)
	local staminaFill = makeBar(bout, 6, 6, STAMINA_COLOR)

	local chargeTrack = Instance.new("Frame")
	chargeTrack.Name = "ChargeTrack"
	chargeTrack.Size = UDim2.new(1, 0, 0, 10)
	chargeTrack.BackgroundColor3 = TRACK_COLOR
	chargeTrack.BorderSizePixel = 0
	chargeTrack.ClipsDescendants = true
	chargeTrack.LayoutOrder = 7
	chargeTrack.Parent = bout

	local chargeCorner = Instance.new("UICorner")
	chargeCorner.CornerRadius = UDim.new(0, 3)
	chargeCorner.Parent = chargeTrack

	local chargeFill = Instance.new("Frame")
	chargeFill.Name = "Fill"
	chargeFill.Size = UDim2.new(0, 0, 1, 0)
	chargeFill.BackgroundColor3 = CHARGE_COLOR
	chargeFill.BorderSizePixel = 0
	chargeFill.ZIndex = 2
	chargeFill.Parent = chargeTrack

	local chargeFillCorner = Instance.new("UICorner")
	chargeFillCorner.CornerRadius = UDim.new(0, 3)
	chargeFillCorner.Parent = chargeFill

	-- Positioned in Set from the shares the server sends, not here: the marks are the
	-- contract between what the player aims at and what the server judges, and a client
	-- that placed them from its own numbers could be wrong without anything saying so.
	local jabMark = makeMark(chargeTrack, 0)
	local breakMark = makeMark(chargeTrack, 0)
	local overMark = makeMark(chargeTrack, 0)

	local beatLabel = makeLabel(bout, 8, 13, CAPTION_COLOR, Enum.Font.GothamBold)

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
	buttons.BackgroundTransparency = 1
	buttons.LayoutOrder = 9
	buttons.Parent = bout

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonLayout.Padding = UDim.new(0, 8)
	buttonLayout.Parent = buttons

	-- Strike is first and leftmost because it is the one that is held to a decision, and
	-- the reading order of the panel should match the order the player learns them in.
	local strikeButton = makeButton(buttons, 0, "Hold to strike")
	local guardButton = makeButton(buttons, 1, "Hold to guard")
	local stepButton = makeButton(buttons, 2, "Sidestep")

	local resultLabel = makeLabel(panel, 2, 15, TITLE_COLOR, Enum.Font.GothamBold)

	screenGui.Parent = playerGui

	local self = setmetatable({
		screenGui = screenGui,
		panel = panel,
		card = card,
		cardNameLabel = cardNameLabel,
		cardStyleLabel = cardStyleLabel,
		cardBlurbLabel = cardBlurbLabel,
		bout = bout,
		foeNameLabel = foeNameLabel,
		foeFooting = foeFooting,
		intentLabel = intentLabel,
		tellTrack = tellTrack,
		tellFill = tellFill,
		selfFooting = selfFooting,
		staminaFill = staminaFill,
		chargeTrack = chargeTrack,
		chargeFill = chargeFill,
		jabMark = jabMark,
		breakMark = breakMark,
		overMark = overMark,
		beatLabel = beatLabel,
		strikeButton = strikeButton,
		guardButton = guardButton,
		stepButton = stepButton,
		resultLabel = resultLabel,
		holding = {},
		locked = false,
		onStrike = nil,
		onGuard = nil,
		onSidestep = nil,
	}, FightUI) :: FightUIHandle

	-- --------------------------------------------------------------
	-- Input.
	--
	-- Strike and guard are held, and a held button has one hard requirement: the release
	-- must be impossible to lose. A strike that is never released is a player frozen
	-- mid-wind-up while an opponent takes them apart, so every path that could end a hold
	-- -- letting go on the button, letting go anywhere else, dragging off, losing the
	-- window, or the server locking input out -- runs the same release.
	-- --------------------------------------------------------------

	local function bindHold(button: TextButton, action: string)
		button.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				setHeld(self, action, true)
			end
		end)
		button.InputEnded:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				setHeld(self, action, false)
			end
		end)
	end

	bindHold(strikeButton, "strike")
	bindHold(guardButton, "guard")

	-- The release that happened somewhere other than on the button: dragged off before
	-- letting go, which in a fight is not an edge case but the normal result of a player
	-- moving the mouse while they watch the tell.
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			setHeld(self, "strike", false)
			setHeld(self, "guard", false)
		end
	end)

	-- Alt-tabbing mid-charge. Without this the hold survives the player leaving, and they
	-- come back to a fight they lost while looking at something else.
	UserInputService.WindowFocusReleased:Connect(function()
		setHeld(self, "strike", false)
		setHeld(self, "guard", false)
	end)

	stepButton.Activated:Connect(function()
		if self.locked then
			return
		end
		local step = self.onSidestep
		if step ~= nil then
			step()
		end
	end)

	return self
end

function FightUI.OnStrike(self: FightUIHandle, callback: (held: boolean) -> ())
	self.onStrike = callback
end

function FightUI.OnGuard(self: FightUIHandle, callback: (held: boolean) -> ())
	self.onGuard = callback
end

function FightUI.OnSidestep(self: FightUIHandle, callback: () -> ())
	self.onSidestep = callback
end

local function setBar(fill: Frame, share: number)
	TweenService
		:Create(fill, BAR_TWEEN, { Size = UDim2.new(math.clamp(share, 0, 1), 0, 1, 0) })
		:Play()
end

-- Which colour the power meter is wearing, which is the same question as "what would this
-- strike do if released now".
--
-- Tested highest mark first, and the guard break is the highest: it sits above the
-- overcharge by a rule the server refuses to boot without, because a break that did not
-- cost you the long recovery would be the one correct charge for every fight. So the three
-- colours read outwards as "a jab", "committed", and "committed *and* it goes through a
-- guard" -- the last being strictly the most expensive thing the meter can say.
local function chargeColor(state: FightState): Color3
	if state.charge >= state.guardBreakShare then
		return CHARGE_BREAK_COLOR
	elseif state.charge >= state.overchargeShare then
		return CHARGE_OVER_COLOR
	end
	return CHARGE_COLOR
end

-- The whole panel, from one snapshot. Nil is the usual state and takes it down.
function FightUI.Set(self: FightUIHandle, state: FightState?)
	if state == nil then
		-- The holds are dropped with the panel rather than left set. A bout that ends
		-- mid-charge would otherwise leave `holding.strike` true, and the first press of
		-- the next fight would be swallowed as a repeat of a hold that ended days ago.
		-- Released before `locked` goes up, so it goes through the same one path.
		setHeld(self, "strike", false)
		setHeld(self, "guard", false)
		self.locked = true
		self.panel.Visible = false
		return
	end

	self.panel.Visible = true

	-- Squaring up: prose only, no instruments. The bars would all be full and none of
	-- them would mean anything yet, and a panel of full bars reads as a fight already
	-- in progress.
	if state.phase == "square" then
		self.locked = true
		self.card.Visible = true
		self.bout.Visible = false
		self.resultLabel.Visible = false
		self.cardNameLabel.Text = `{state.foeName} wants a fight.`
		self.cardStyleLabel.Text = state.foeStyle
		self.cardBlurbLabel.Text = state.foeBlurb
		return
	end

	self.card.Visible = false
	self.bout.Visible = true

	self.foeNameLabel.Text = `{state.foeName} -- {state.foeStyle}`
	setBar(self.foeFooting, if state.foeMaxFooting > 0 then state.foeFooting / state.foeMaxFooting else 0)
	setBar(self.selfFooting, if state.maxFooting > 0 then state.footing / state.maxFooting else 0)

	local staminaShare = if state.maxStamina > 0 then state.stamina / state.maxStamina else 0
	setBar(self.staminaFill, staminaShare)
	self.staminaFill.BackgroundColor3 = if staminaShare <= STAMINA_LOW_SHARE
		then STAMINA_LOW_COLOR
		else STAMINA_COLOR

	-- Two facts on the intent line, and the second one earns its place: out of range is
	-- where stamina comes back fastest, so "are we engaged" is a decision the player is
	-- making constantly and not one they should have to judge by eye.
	local word = INTENT_WORD[state.foeIntent] or state.foeIntent
	self.intentLabel.Text = if state.engaged then word else `{word} -- out of range`

	-- The tell is drawn straight, with no tween and no easing. It is a clock.
	self.tellTrack.Visible = state.foeWind > 0
	self.tellFill.Size = UDim2.new(math.clamp(state.foeWind, 0, 1), 0, 1, 0)

	self.jabMark.Position = UDim2.new(state.jabShare, -1, 0, 0)
	self.breakMark.Position = UDim2.new(state.guardBreakShare, -1, 0, 0)
	self.overMark.Position = UDim2.new(state.overchargeShare, -1, 0, 0)
	self.chargeFill.Size = UDim2.new(math.clamp(state.charge, 0, 1), 0, 1, 0)
	self.chargeFill.BackgroundColor3 = chargeColor(state)

	local beat = state.beat
	self.beatLabel.Visible = beat ~= nil
	if beat ~= nil then
		self.beatLabel.Text = beat
		self.beatLabel.TextColor3 = if state.beatGood then GOOD_COLOR else BAD_COLOR
	end

	local result = state.result
	self.resultLabel.Visible = result ~= nil
	if result ~= nil then
		self.resultLabel.Text = result
		self.resultLabel.TextColor3 = if state.won then GOOD_COLOR else BAD_COLOR
	end

	-- Locked out: either a recovery window is running, or the fight is not in a phase
	-- that takes input at all. Both grey the buttons, because to the player they are the
	-- same thing -- a moment where the three answers are not available.
	local locked = state.recover > 0 or state.phase ~= "fight"
	self.locked = locked
	if locked then
		-- Anything still held is released through setHeld, so the server is told.
		-- Silently clearing the flag here would leave the server charging a strike the
		-- client has already forgotten about, and the player holding a button that does
		-- nothing until they let go of it and press again.
		setHeld(self, "strike", false)
		setHeld(self, "guard", false)
	end

	local buttonColor = if locked then BUTTON_LOCKED_COLOR else BUTTON_COLOR
	local textColor = if locked then BUTTON_LOCKED_TEXT_COLOR else BUTTON_TEXT_COLOR
	self.strikeButton.BackgroundColor3 = if self.holding.strike then BUTTON_HELD_COLOR else buttonColor
	self.guardButton.BackgroundColor3 = if self.holding.guard then BUTTON_HELD_COLOR else buttonColor
	self.stepButton.BackgroundColor3 = buttonColor
	self.strikeButton.TextColor3 = textColor
	self.guardButton.TextColor3 = textColor
	self.stepButton.TextColor3 = textColor
end

return FightUI
