--!strict
-- The lobby screen: the lives you own, the one you are about to open, and the card you make
-- a new one on.
--
-- **Two pages in one column, not two screens.** The left third holds either the slot list or
-- the create card; the right two-thirds is the avatar and nothing is ever drawn over it. That
-- is the shot, and covering it would undo the reason the lobby is a place rather than a menu.
-- Switching pages is two `Visible` writes -- neither page is torn down, so backing out of a
-- half-filled card and going back into it costs nothing and loses nothing that matters.
--
-- **Success is not an event this file listens for.** Creating a life is answered by the slot
-- list arriving with that slot filled in, and starting one is answered by the place going
-- away. Only refusals have their own message, because a refusal is the only outcome with
-- something to say. See the remotes: `SlotActionRefused` and `PlayRefused`.
--
-- Same raw-`Instance.new` idiom as ChoicePanel, StatsUI and SetupCard: no Roact, no templates
-- in the project file, and `.new()` returns a metatable handle. Consistency here is worth
-- more than any one of those choices -- five UI files in three idioms is how a codebase stops
-- being readable.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local SetupCard = require(script.Parent.SetupCard)

type LobbyState = Types.LobbyState
type SlotSummary = Types.SlotSummary
type SetupOptions = Types.SetupOptions
type SetupRequest = Types.SetupRequest
type SpinsState = Types.SpinsState
type PerkOffer = Types.PerkOffer
type SpinProduct = Types.SpinProduct

-- The same palette as SetupCard, and now the same *table* -- see `Config.Lobby.Menu.Palette`
-- for why the two files no longer each keep a copy. Bound to locals here so the rest of the
-- file reads as colour names rather than as paths.
local MENU = Config.Lobby.Menu
local MOTION = MENU.Motion
local P = MENU.Palette

local PANEL = P.Panel
local ROW = P.Row
local ROW_HOVER = P.RowHover
local EDGE = P.Edge
local TEXT = P.Text
local MUTED = P.Muted
local ACCENT = P.Accent
local ACCENT_HOVER = P.AccentHover
local ACCENT_DEEP = P.AccentDeep
local INK = P.Ink
local BUSY = P.Busy
local WARN = P.Warn
local LIVING = P.Living
local GONE = P.Gone
local ROW_LOCKED = P.RowLocked
local DISABLED = P.Disabled

local SLOT_CARD_HEIGHT = 92
-- The gap between cards. A plain number rather than a `UIListLayout`, and that swap is not
-- cosmetic: a layout owns the Position of everything under it, so a card in one cannot be
-- tweened -- not into place on arrival, and not sideways under the cursor. Three cards at a
-- fixed height need one multiplication to place, and buying that back buys all the motion.
local SLOT_CARD_GAP = 10

local function cardHomeY(index: number): number
	return (index - 1) * (SLOT_CARD_HEIGHT + SLOT_CARD_GAP)
end

local HOVER_INFO = TweenInfo.new(MOTION.HoverSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- The narrowest the column is allowed to get, and how much wider than that the scrim behind it
-- must be.
--
-- The column is a *fraction* of the screen with a pixel floor under it, and the scrim is a
-- fraction with no floor -- so on a narrow enough viewport the column stops shrinking and the
-- scrim does not, and the subtitle ends up hanging off the right-hand edge of its own backdrop
-- onto the lit scene. The margin is the column's right padding plus room for the fade to
-- actually happen in.
local COLUMN_MIN_WIDTH = 340
local SCRIM_MIN_MARGIN = 80

local SlotsUpdatedRemote = Remotes.Get("LobbySlotsUpdated")
local SetupOptionsRemote = Remotes.Get("LobbySetupOptions")
local RequestPlayRemote = Remotes.Get("RequestPlay")
local PlayRefusedRemote = Remotes.Get("PlayRefused")
local RequestSelectSlotRemote = Remotes.Get("RequestSelectSlot")
local RequestDeleteSlotRemote = Remotes.Get("RequestDeleteSlot")
local RequestCreateLifeRemote = Remotes.Get("RequestCreateLife")
local SlotActionRefusedRemote = Remotes.Get("SlotActionRefused")
local SpinsUpdatedRemote = Remotes.Get("SpinsUpdated")
local RequestBuySpinsRemote = Remotes.Get("RequestBuySpins")
local RequestSpinRemote = Remotes.Get("RequestSpin")
local SpinActionRefusedRemote = Remotes.Get("SpinActionRefused")
local RequestJoinByCodeRemote = Remotes.Get("RequestJoinByCode")
local JoinRefusedRemote = Remotes.Get("JoinRefused")

local LobbyUI = {}
LobbyUI.__index = LobbyUI

-- One slot card's instances, held so `render` can re-label them rather than rebuild them.
type SlotCard = {
	button: TextButton,
	outline: UIStroke,
	-- The coloured bar down the left edge. It carries the one fact the eye should get from a
	-- card without reading it -- empty, alive, dead, or armed for deletion -- which is exactly
	-- the fact the text takes a sentence to say.
	spine: Frame,
	nameLabel: TextLabel,
	detailLabel: TextLabel,
	indexLabel: TextLabel,
	actionButton: TextButton,
}

-- One perk catalog row's instances, on the same "build once, re-label forever" pattern as
-- `SlotCard`. Held by index rather than by perk id, like the slot cards, because the catalog
-- is a fixed-length list from the moment it arrives -- content ships with the build, not with
-- a live update -- so there is never a row to remove, only ever one to relabel.
type PerkRow = {
	frame: Frame,
	nameLabel: TextLabel,
	rarityLabel: TextLabel,
	blurbLabel: TextLabel,
	oddsLabel: TextLabel,
	ownedLabel: TextLabel,
}

-- One Robux product row, built once from `SpinsState.products` the first time it arrives.
-- Simpler than `PerkRow`: a product only ever has a name and a price to show, and pressing it
-- is the entire interaction, so there is nothing here for a later `redraw` to change.
type ProductRow = {
	button: TextButton,
}

-- Named `LobbyUIHandle` rather than `LobbyUI` to match SetupCard's `SetupCardHandle`. Luau
-- keeps types and values in separate namespaces so the collision would be legal, and a file
-- where `LobbyUI` means the module on one line and an instance of it on the next is a file
-- that reads wrong before it is understood.
export type LobbyUIHandle = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		column: Frame,
		slotsPage: Frame,
		subtitle: TextLabel,
		cardList: ScrollingFrame,
		cards: { [number]: SlotCard },
		playButton: TextButton,
		playLabel: TextLabel,
		-- The bright band that crosses Play. Held so the sheen loop can move it, and so that
		-- loop does not have to find it by name every pass.
		sheen: Frame,
		refusal: TextLabel,
		refusalToken: number,
		setupCard: SetupCard.SetupCardHandle,
		-- The entry point to the spins page, sat over the empty right-hand corner of the title
		-- block on the slot list. Its own field rather than reached by name, so `redrawSpins`
		-- can keep its count current without a page switch.
		spinsEntryButton: TextButton,
		spinsEntryLabel: TextLabel,
		spinsPage: Frame,
		spinsBackButton: TextButton,
		spinsSubtitle: TextLabel,
		spinsStatusLabel: TextLabel,
		-- One scrolling body holds both lists -- see its construction in `new` for why -- so
		-- perk rows and product rows are both parented here, distinguished only by LayoutOrder.
		spinsBody: ScrollingFrame,
		perkRows: { [number]: PerkRow },
		productRows: { [number]: ProductRow },
		spinButton: TextButton,
		spinButtonLabel: TextLabel,
		spinsState: SpinsState?,
		-- Locked the moment Spin is pressed and released only by the state that answers it --
		-- `SpinsUpdated` on a landed pull, `SpinActionRefused` on a refusal -- the same
		-- request/answer discipline `setBusy` gives Play, and for the same reason: a button
		-- that stays live while a roll is already in flight is a button a second click spends
		-- twice as many spins on.
		spinBusy: boolean,
		-- Whether the cards have been dealt in yet. The stagger is an arrival, so it plays on
		-- the first slot list to land and never again -- a list that re-flew in every time a
		-- life was created would be the screen celebrating its own redraw.
		hasDealt: boolean,
		-- Whether pressing Play right now would actually open a life. Kept as a field rather
		-- than recomputed in the hover handlers, because `playButton.Active` already means
		-- something else -- "no teleport in the air" -- and one boolean answering two questions
		-- is how a button ends up lighting up under the cursor for a slot it cannot open.
		playReady: boolean,
		state: LobbyState?,
		options: SetupOptions?,
		-- Which slot is one press away from being emptied, and until when.
		--
		-- Held here rather than on the card, because only one may be armed at a time: arming a
		-- second while the first is still live would leave two cards both saying "press again",
		-- and the player's next press would be aimed at whichever one they last read.
		pendingDelete: number?,
		pendingDeleteToken: number,
		-- The join-code section. A code is generated for the active slot and shown on screen;
		-- the player can copy it or regenerate it. Below that, a text input accepts a code
		-- from another player and joins the slot it points at.
		joinCodePanel: Frame,
		joinCodeCodeLabel: TextLabel,
		joinCodeCopyButton: TextButton,
		joinCodeRegenButton: TextButton,
		joinCodeHintLabel: TextLabel,
		joinCodeInput: TextBox,
		joinCodeJoinButton: TextButton,
		joinCodeInputLabel: TextLabel,
		joinCodeBusy: boolean,
	},
	LobbyUI
))

local function corner(parent: GuiObject, radius: number)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
end

local function stroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local instance = Instance.new("UIStroke")
	instance.Color = color
	instance.Thickness = thickness
	instance.Parent = parent
	return instance
end

-- A vertical gradient over whatever it is parented to.
--
-- `UIGradient.Color` *multiplies* the object's own colour rather than replacing it, which is
-- the property that makes this usable on the slot cards: the card keeps one `BackgroundColor3`
-- that hover tweens between, and the gradient shades whatever that happens to be. A gradient
-- written as two absolute colours would have to be re-authored every time the base moved.
local function gradient(parent: GuiObject, top: Color3, bottom: Color3): UIGradient
	local instance = Instance.new("UIGradient")
	instance.Color = ColorSequence.new(top, bottom)
	instance.Rotation = 90
	instance.Parent = parent
	return instance
end

-- The dark wash the column stands on.
--
-- **Text on this screen sits directly on a lit 3D scene**, and the scene has a gold halo and a
-- character in it -- so a muted subtitle is legible over the backdrop and invisible over the
-- glow, depending only on where the drift has carried the camera. The scrim makes that
-- question not arise.
--
-- Faded to nothing on its right edge rather than ending, which is the whole difference between
-- a composition and a grey box pasted over the left of a screenshot. It is a gradient into the
-- shot, not a panel over it.
local function buildScrim(gui: ScreenGui): Frame
	local scrim = Instance.new("Frame")
	scrim.Name = "Scrim"
	-- Darker than `Panel`, and deliberately not equal to it: the scrim is meant to be the floor
	-- everything else is lit against, so anything drawn on top of it has somewhere to be lighter
	-- than.
	scrim.BackgroundColor3 = Color3.fromRGB(6, 6, 9)
	scrim.BackgroundTransparency = MENU.ScrimTransparency
	scrim.BorderSizePixel = 0
	scrim.Size = UDim2.new(MENU.ScrimWidth, 0, 1, 0)
	-- Behind the column, which is its only sibling. Explicit rather than relying on child order,
	-- because child order is a thing a later edit reorders without noticing.
	scrim.ZIndex = 0
	scrim.Parent = gui

	local fade = Instance.new("UIGradient")
	-- Rotation 0 -- this one runs left to right, unlike every other gradient in the file.
	--
	-- Held flat across the first `ScrimFadeStart` of the width and then run out to nothing, so
	-- the column has a constant tone under it and the fade happens entirely in the empty strip
	-- to its right. A fade that started at the left edge would shade the title differently from
	-- the subtitle under it.
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(MENU.ScrimFadeStart, 0.06),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = scrim

	-- Kept wider than the column can ever be -- see `COLUMN_MIN_WIDTH`.
	local width = Instance.new("UISizeConstraint")
	width.MinSize = Vector2.new(COLUMN_MIN_WIDTH + SCRIM_MIN_MARGIN, 0)
	width.Parent = scrim

	return scrim
end

-- The screen arriving.
--
-- **The first thing this game ever does, so it is deliberately over before it is noticed.** The
-- column slides in from the left and the scrim comes up under it. Nothing is gated on either
-- finishing: a player who joins with their hand already on the mouse can press a card mid-tween
-- and it works. An entrance that has to complete before the menu is usable is an animation
-- charging rent.
--
-- A plain function rather than a method, because the scrim is not on the handle -- nothing
-- after this moment ever touches it again, and a field held solely to be read once by the
-- function that created it is state pretending to be structure.
local function playEntrance(column: Frame, scrim: Frame)
	local info = TweenInfo.new(MOTION.EnterSeconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

	column.Position = UDim2.new(0, -MOTION.EnterPixels, 0, 0)
	TweenService:Create(column, info, { Position = UDim2.new(0, 0, 0, 0) }):Play()

	scrim.BackgroundTransparency = 1
	TweenService:Create(scrim, info, { BackgroundTransparency = MENU.ScrimTransparency }):Play()
end

function LobbyUI.new(): LobbyUIHandle
	local gui = Instance.new("ScreenGui")
	gui.Name = "AgesLobby"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Above anything the game place ever draws. Nothing else exists in this place, so the
	-- number is a statement of intent rather than a resolution of a conflict.
	gui.DisplayOrder = 30
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local scrim = buildScrim(gui)

	local column = Instance.new("Frame")
	column.Name = "Column"
	column.BackgroundTransparency = 1
	column.Size = UDim2.new(0.34, 0, 1, 0)
	column.Position = UDim2.new(0, 0, 0, 0)
	column.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 48)
	padding.PaddingRight = UDim.new(0, 24)
	padding.PaddingTop = UDim.new(0, 56)
	padding.PaddingBottom = UDim.new(0, 48)
	padding.Parent = column

	-- Stops the column becoming unreadably narrow on a phone held upright, where 34% of the
	-- width is about two hundred pixels and the stat steppers on the create card would have
	-- nowhere to sit. It grows over the avatar rather than squeezing, which is the right
	-- trade: an unreadable menu costs more than a partly hidden character.
	local columnWidth = Instance.new("UISizeConstraint")
	columnWidth.MinSize = Vector2.new(COLUMN_MIN_WIDTH, 0)
	columnWidth.Parent = column

	-- Page one: the lives you own -------------------------------------------
	local slotsPage = Instance.new("Frame")
	slotsPage.Name = "SlotsPage"
	slotsPage.BackgroundTransparency = 1
	slotsPage.Size = UDim2.new(1, 0, 1, 0)
	slotsPage.Parent = column

	-- The one line above the title. Small, spaced-out capitals doing the job a logo would do if
	-- this build had one: saying what kind of game this is before the player has pressed
	-- anything. `AGES` alone is a word, not a promise.
	local eyebrow = Instance.new("TextLabel")
	eyebrow.Name = "Eyebrow"
	eyebrow.BackgroundTransparency = 1
	eyebrow.Size = UDim2.new(1, 0, 0, 14)
	eyebrow.Position = UDim2.new(0, 0, 0, 0)
	eyebrow.Font = Enum.Font.GothamBold
	eyebrow.Text = "L I V E   A N O T H E R   L I F E"
	eyebrow.TextSize = 11
	eyebrow.TextColor3 = ACCENT
	eyebrow.TextTransparency = 0.35
	eyebrow.TextXAlignment = Enum.TextXAlignment.Left
	eyebrow.Parent = slotsPage

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 66)
	title.Position = UDim2.new(0, 0, 0, 16)
	title.Font = Enum.Font.GothamBlack
	title.Text = "AGES"
	title.TextSize = 62
	-- White, because the gradient below multiplies this rather than replacing it -- anything
	-- other than white here would tint the gradient a second time.
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = slotsPage
	gradient(title, TEXT, ACCENT_DEEP)

	-- A dark outline rather than a glow. The title sits over the scrim's darkest strip today,
	-- but the scrim is a Config number and the halo is behind it -- the stroke is what makes the
	-- word survive somebody turning either of those up.
	local titleEdge = stroke(title, Color3.fromRGB(10, 9, 12), 2)
	titleEdge.Transparency = 0.45

	-- The rule under the title. Short, so it reads as an underline on the word rather than as a
	-- divider across the column -- there is a divider's worth of space under the subtitle
	-- already, and two horizontals that close together is a form, not a title.
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.BackgroundColor3 = ACCENT
	rule.BorderSizePixel = 0
	rule.Size = UDim2.new(0, 76, 0, 3)
	rule.Position = UDim2.new(0, 2, 0, 84)
	rule.Parent = slotsPage
	corner(rule, 2)
	local ruleFade = Instance.new("UIGradient")
	-- Fades out along its own length, so the rule ends rather than stops.
	ruleFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	ruleFade.Parent = rule

	-- The entry point to the spins page. Pinned to the corner rather than laid out in the flow
	-- below, because nothing else on this row claims it -- the eyebrow and the title are both
	-- short words on a wide row -- and the spin count is the one thing on this screen worth
	-- checking before a card has even been opened.
	local spinsEntryButton = Instance.new("TextButton")
	spinsEntryButton.Name = "SpinsEntry"
	spinsEntryButton.AnchorPoint = Vector2.new(1, 0)
	spinsEntryButton.Position = UDim2.new(1, 0, 0, 2)
	spinsEntryButton.Size = UDim2.new(0, 92, 0, 28)
	spinsEntryButton.BackgroundColor3 = ROW
	spinsEntryButton.BorderSizePixel = 0
	spinsEntryButton.AutoButtonColor = false
	spinsEntryButton.Text = ""
	spinsEntryButton.Parent = slotsPage
	corner(spinsEntryButton, 8)
	stroke(spinsEntryButton, EDGE, 1)

	local spinsEntryLabel = Instance.new("TextLabel")
	spinsEntryLabel.Name = "Label"
	spinsEntryLabel.BackgroundTransparency = 1
	spinsEntryLabel.Size = UDim2.new(1, 0, 1, 0)
	spinsEntryLabel.Font = Enum.Font.GothamBold
	spinsEntryLabel.Text = "Spins"
	spinsEntryLabel.TextSize = 13
	spinsEntryLabel.TextColor3 = ACCENT
	spinsEntryLabel.Parent = spinsEntryButton

	spinsEntryButton.MouseEnter:Connect(function()
		TweenService:Create(spinsEntryButton, HOVER_INFO, { BackgroundColor3 = ROW_HOVER }):Play()
	end)
	spinsEntryButton.MouseLeave:Connect(function()
		TweenService:Create(spinsEntryButton, HOVER_INFO, { BackgroundColor3 = ROW }):Play()
	end)

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, 0, 0, 22)
	subtitle.Position = UDim2.new(0, 0, 0, 98)
	subtitle.Font = Enum.Font.Gotham
	subtitle.Text = "Loading your lives..."
	subtitle.TextSize = 15
	subtitle.TextColor3 = MUTED
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextWrapped = true
	subtitle.Parent = slotsPage

	-- Scrolls, even though three cards fit on every screen this game will ever run on. Slot
	-- count is a Config number that is safe to raise, and the day it is raised this is the
	-- difference between "six lives" and "six lives, three of which are off the bottom".
	local cardList = Instance.new("ScrollingFrame")
	cardList.Name = "Slots"
	cardList.BackgroundTransparency = 1
	cardList.BorderSizePixel = 0
	cardList.Size = UDim2.new(1, 0, 1, -286)
	cardList.Position = UDim2.new(0, 0, 0, 130)
	cardList.ScrollBarThickness = 3
	cardList.ScrollBarImageColor3 = EDGE
	-- Set by `ensureCards` from the slot count rather than grown automatically, because the
	-- cards are positioned by hand -- see `SLOT_CARD_GAP`. Automatic canvas sizing measures a
	-- layout, and there is no longer a layout to measure.
	cardList.CanvasSize = UDim2.new()
	cardList.ScrollingDirection = Enum.ScrollingDirection.Y
	cardList.Parent = slotsPage

	-- Join-code section: sits between the cards and Play. A code is generated for the
	-- active slot so a second device (or another player at the same keyboard) can join
	-- it by typing the string. The same panel also accepts a code and jumps to the slot
	-- it points at, which is how the debug harness tests the join path without publishing.
	local joinCodePanel = Instance.new("Frame")
	joinCodePanel.Name = "JoinCode"
	joinCodePanel.BackgroundColor3 = PANEL
	joinCodePanel.BorderSizePixel = 0
	joinCodePanel.Size = UDim2.new(1, 0, 0, 110)
	joinCodePanel.Position = UDim2.new(0, 0, 1, -186)
	joinCodePanel.Parent = slotsPage
	corner(joinCodePanel, 10)
	stroke(joinCodePanel, EDGE, 1)

	local joinCodeHeader = Instance.new("TextLabel")
	joinCodeHeader.Name = "Header"
	joinCodeHeader.BackgroundTransparency = 1
	joinCodeHeader.Size = UDim2.new(1, 0, 0, 16)
	joinCodeHeader.Position = UDim2.new(0, 12, 0, 8)
	joinCodeHeader.Font = Enum.Font.GothamMedium
	joinCodeHeader.Text = "JOIN CODE"
	joinCodeHeader.TextSize = 10
	joinCodeHeader.TextColor3 = MUTED
	joinCodeHeader.TextXAlignment = Enum.TextXAlignment.Left
	joinCodeHeader.Parent = joinCodePanel

	-- The code string for the active slot, or a hint when none is generated yet.
	local joinCodeCodeLabel = Instance.new("TextLabel")
	joinCodeCodeLabel.Name = "Code"
	joinCodeCodeLabel.BackgroundTransparency = 1
	joinCodeCodeLabel.Size = UDim2.new(1, -180, 0, 28)
	joinCodeCodeLabel.Position = UDim2.new(0, 12, 0, 28)
	joinCodeCodeLabel.Font = Enum.Font.GothamMonoBold
	joinCodeCodeLabel.Text = ""
	joinCodeCodeLabel.TextSize = 20
	joinCodeCodeLabel.TextColor3 = ACCENT
	joinCodeCodeLabel.TextXAlignment = Enum.TextXAlignment.Left
	joinCodeCodeLabel.TextTruncate = Enum.TextTruncate.AtEnd
	joinCodeCodeLabel.Parent = joinCodePanel

	local joinCodeHintLabel = Instance.new("TextLabel")
	joinCodeHintLabel.Name = "Hint"
	joinCodeHintLabel.BackgroundTransparency = 1
	joinCodeHintLabel.Size = UDim2.new(1, -180, 0, 16)
	joinCodeHintLabel.Position = UDim2.new(0, 12, 0, 58)
	joinCodeHintLabel.Font = Enum.Font.Gotham
	joinCodeHintLabel.Text = "Press Generate to create a code for this slot."
	joinCodeHintLabel.TextSize = 11
	joinCodeHintLabel.TextColor3 = MUTED
	joinCodeHintLabel.TextXAlignment = Enum.TextXAlignment.Left
	joinCodeHintLabel.TextWrapped = true
	joinCodeHintLabel.Parent = joinCodePanel

	-- Copy the visible code to the clipboard. No remote is needed: the string is
	-- already on screen and the only thing the clipboard does is move it off the
	-- device so it can be typed into a second one.
	local joinCodeCopyButton = Instance.new("TextButton")
	joinCodeCopyButton.Name = "Copy"
	joinCodeCopyButton.AnchorPoint = Vector2.new(1, 0)
	joinCodeCopyButton.Position = UDim2.new(1, -12, 0, 28)
	joinCodeCopyButton.Size = UDim2.new(0, 72, 0, 28)
	joinCodeCopyButton.BackgroundColor3 = ROW
	joinCodeCopyButton.BorderSizePixel = 0
	joinCodeCopyButton.AutoButtonColor = false
	joinCodeCopyButton.Font = Enum.Font.GothamMedium
	joinCodeCopyButton.Text = ""
	joinCodeCopyButton.TextSize = 12
	joinCodeCopyButton.TextColor3 = TEXT
	joinCodeCopyButton.Parent = joinCodePanel
	corner(joinCodeCopyButton, 6)
	gradient(joinCodeCopyButton, Color3.new(1, 1, 1), Color3.fromRGB(178, 178, 190))
	local joinCodeCopyLabel = Instance.new("TextLabel")
	joinCodeCopyLabel.Name = "Label"
	joinCodeCopyLabel.BackgroundTransparency = 1
	joinCodeCopyLabel.Size = UDim2.new(1, 0, 1, 0)
	joinCodeCopyLabel.Font = Enum.Font.GothamMedium
	joinCodeCopyLabel.Text = "Copy"
	joinCodeCopyLabel.TextSize = 12
	joinCodeCopyLabel.TextColor3 = INK
	joinCodeCopyLabel.Parent = joinCodeCopyButton

	-- Regenerate replaces the current code. One use per code, the old one expires
	-- the moment a new one is issued.
	local joinCodeRegenButton = Instance.new("TextButton")
	joinCodeRegenButton.Name = "Regen"
	joinCodeRegenButton.AnchorPoint = Vector2.new(1, 0)
	joinCodeRegenButton.Position = UDim2.new(1, -12, 0, 60)
	joinCodeRegenButton.Size = UDim2.new(0, 108, 0, 24)
	joinCodeRegenButton.BackgroundColor3 = ROW
	joinCodeRegenButton.BorderSizePixel = 0
	joinCodeRegenButton.AutoButtonColor = false
	joinCodeRegenButton.Font = Enum.Font.GothamMedium
	joinCodeRegenButton.Text = ""
	joinCodeRegenButton.TextSize = 12
	joinCodeRegenButton.TextColor3 = MUTED
	joinCodeRegenButton.Parent = joinCodePanel
	corner(joinCodeRegenButton, 6)
	local joinCodeRegenLabel = Instance.new("TextLabel")
	joinCodeRegenLabel.Name = "Label"
	joinCodeRegenLabel.BackgroundTransparency = 1
	joinCodeRegenLabel.Size = UDim2.new(1, 0, 1, 0)
	joinCodeRegenLabel.Font = Enum.Font.GothamMedium
	joinCodeRegenLabel.Text = "Regenerate"
	joinCodeRegenLabel.TextSize = 12
	joinCodeRegenLabel.TextColor3 = MUTED
	joinCodeRegenLabel.Parent = joinCodeRegenButton

	-- A thin divider separates the "my code" section from the "join someone" section.
	local joinCodeDivider = Instance.new("Frame")
	joinCodeDivider.Name = "Divider"
	joinCodeDivider.BackgroundColor3 = EDGE
	joinCodeDivider.BorderSizePixel = 0
	joinCodeDivider.Size = UDim2.new(1, -24, 0, 1)
	joinCodeDivider.Position = UDim2.new(0, 12, 0, 88)
	joinCodeDivider.Parent = joinCodePanel

	-- A text input for entering another player's code, and a button to submit it.
	-- The button fires the remote; the remote owns all validation and the server
	-- fires back on JoinRefused with either a human-readable refusal or the generated
	-- code when no payload is given (generation path).
	local joinCodeInput = Instance.new("TextBox")
	joinCodeInput.Name = "Input"
	joinCodeInput.BackgroundColor3 = ROW
	joinCodeInput.BorderSizePixel = 0
	joinCodeInput.Size = UDim2.new(0.5, -18, 0, 28)
	joinCodeInput.Position = UDim2.new(0, 12, 0, 92)
	joinCodeInput.Font = Enum.Font.GothamMonoBold
	joinCodeInput.Text = ""
	joinCodeInput.TextSize = 16
	joinCodeInput.TextColor3 = TEXT
	joinCodeInput.PlaceholderText = "Enter code..."
	joinCodeInput.ClearTextOnFocus = false
	joinCodeInput.Parent = joinCodePanel
	corner(joinCodeInput, 6)

	local joinCodeJoinButton = Instance.new("TextButton")
	joinCodeJoinButton.Name = "Join"
	joinCodeJoinButton.BackgroundColor3 = ACCENT
	joinCodeJoinButton.BorderSizePixel = 0
	joinCodeJoinButton.Size = UDim2.new(0, 86, 0, 28)
	joinCodeJoinButton.Position = UDim2.new(0.5, 6, 0, 92)
	joinCodeJoinButton.AutoButtonColor = false
	joinCodeJoinButton.Font = Enum.Font.GothamBold
	joinCodeJoinButton.Text = ""
	joinCodeJoinButton.TextSize = 14
	joinCodeJoinButton.TextColor3 = INK
	joinCodeJoinButton.Parent = joinCodePanel
	corner(joinCodeJoinButton, 8)
	gradient(joinCodeJoinButton, Color3.new(1, 1, 1), Color3.fromRGB(216, 200, 176))
	local joinCodeJoinLabel = Instance.new("TextLabel")
	joinCodeJoinLabel.Name = "Label"
	joinCodeJoinLabel.BackgroundTransparency = 1
	joinCodeJoinLabel.Size = UDim2.new(1, 0, 1, 0)
	joinCodeJoinLabel.Font = Enum.Font.GothamBold
	joinCodeJoinLabel.Text = "Join"
	joinCodeJoinLabel.TextSize = 14
	joinCodeJoinLabel.TextColor3 = INK
	joinCodeJoinLabel.Parent = joinCodeJoinButton

	local playButton = Instance.new("TextButton")
	playButton.Name = "Play"
	playButton.AnchorPoint = Vector2.new(0, 1)
	playButton.Size = UDim2.new(1, 0, 0, 68)
	playButton.Position = UDim2.new(0, 0, 1, -76)
	playButton.BackgroundColor3 = ACCENT
	playButton.AutoButtonColor = false
	-- The button's own text is empty and a child label carries it. Two lines of different
	-- sizes cannot live in one TextButton, and "PLAY" over "Ellis Mercer, age 12" is the whole
	-- point of the button -- it has to say which life it opens.
	playButton.Text = ""
	-- For the sheen, which is a bar wider than the button that has to disappear at each edge
	-- rather than stop. Clips to the rounded corners, so the highlight follows the button's
	-- actual shape.
	playButton.ClipsDescendants = true
	playButton.Parent = slotsPage
	corner(playButton, 10)
	-- Multiplies whatever `BackgroundColor3` currently is, so the same gradient shades the live
	-- button, the hover, and the greyed-out busy state without any of them knowing about it.
	gradient(playButton, Color3.new(1, 1, 1), Color3.fromRGB(216, 200, 176))

	-- The highlight that crosses the button. Rotated, taller than the button, and started
	-- outside it on the left; `runSheen` walks it across and off the right edge.
	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.BackgroundTransparency = 0.78
	sheen.BorderSizePixel = 0
	sheen.AnchorPoint = Vector2.new(0.5, 0.5)
	sheen.Size = UDim2.new(0, 44, 2, 0)
	sheen.Position = UDim2.new(-0.3, 0, 0.5, 0)
	sheen.Rotation = 18
	-- Over the two labels rather than under them. A highlight that passes behind the word PLAY
	-- is a highlight with a hole in it.
	sheen.ZIndex = 3
	sheen.Visible = false
	sheen.Parent = playButton

	local playTitle = Instance.new("TextLabel")
	playTitle.Name = "PlayTitle"
	playTitle.BackgroundTransparency = 1
	playTitle.Size = UDim2.new(1, 0, 0, 30)
	playTitle.Position = UDim2.new(0, 0, 0, 10)
	playTitle.Font = Enum.Font.GothamBold
	playTitle.Text = "PLAY"
	playTitle.TextSize = 24
	playTitle.TextColor3 = INK
	playTitle.Parent = playButton

	local playLabel = Instance.new("TextLabel")
	playLabel.Name = "PlaySubtitle"
	playLabel.BackgroundTransparency = 1
	playLabel.Size = UDim2.new(1, -20, 0, 20)
	playLabel.Position = UDim2.new(0, 10, 0, 38)
	playLabel.Font = Enum.Font.GothamMedium
	playLabel.Text = ""
	playLabel.TextSize = 14
	playLabel.TextColor3 = Color3.fromRGB(70, 58, 36)
	playLabel.TextTruncate = Enum.TextTruncate.AtEnd
	playLabel.Parent = playButton

	-- Sits *under* the Play button rather than floating over the middle of the screen. A
	-- refusal is an answer to the thing that was just pressed, and an answer belongs next to
	-- the question. Parented to the column rather than to the slots page, because a create
	-- that is refused for a reason the card cannot show -- a save that stopped loading -- has
	-- to land somewhere the player is looking either way.
	local refusal = Instance.new("TextLabel")
	refusal.Name = "Refusal"
	refusal.AnchorPoint = Vector2.new(0, 1)
	refusal.BackgroundColor3 = PANEL
	refusal.BackgroundTransparency = 1
	refusal.Size = UDim2.new(1, 0, 0, 64)
	refusal.Position = UDim2.new(0, 0, 1, 0)
	refusal.Font = Enum.Font.Gotham
	refusal.Text = ""
	refusal.TextSize = 14
	refusal.TextColor3 = WARN
	refusal.TextTransparency = 1
	refusal.TextXAlignment = Enum.TextXAlignment.Left
	refusal.TextYAlignment = Enum.TextYAlignment.Top
	refusal.TextWrapped = true
	refusal.ZIndex = 2
	refusal.Parent = column
	corner(refusal, 8)
	stroke(refusal, EDGE, 1)

	-- Page two: the card a life is made on ----------------------------------
	local setupCard = SetupCard.new(column)

	-- Page three: spins, disclosed odds, and what Robux buys ----------------
	--
	-- Built the same way as the setup card -- a page under `column`, a Back button above a
	-- rounded card, one scrolling body -- rather than a shared page-shell function, on the same
	-- reasoning `SetupCard`'s own construction helpers give for their own duplication: this is
	-- the second consumer of the shape, and a third file wrapping "page with a back button and
	-- a card" would be a layer over four lines.
	local spinsPage = Instance.new("Frame")
	spinsPage.Name = "SpinsPage"
	spinsPage.Size = UDim2.new(1, 0, 1, 0)
	spinsPage.BackgroundTransparency = 1
	spinsPage.Visible = false
	spinsPage.Parent = column

	local spinsBackButton = Instance.new("TextButton")
	spinsBackButton.Name = "Back"
	spinsBackButton.Size = UDim2.new(0, 96, 0, 26)
	spinsBackButton.Position = UDim2.new(0, 0, 0, 0)
	spinsBackButton.BackgroundTransparency = 1
	spinsBackButton.AutoButtonColor = false
	spinsBackButton.Font = Enum.Font.GothamMedium
	spinsBackButton.Text = "< Back"
	spinsBackButton.TextSize = 14
	spinsBackButton.TextColor3 = MUTED
	spinsBackButton.TextXAlignment = Enum.TextXAlignment.Left
	spinsBackButton.Parent = spinsPage
	spinsBackButton.MouseEnter:Connect(function()
		spinsBackButton.TextColor3 = TEXT
	end)
	spinsBackButton.MouseLeave:Connect(function()
		spinsBackButton.TextColor3 = MUTED
	end)

	local spinsCard = Instance.new("Frame")
	spinsCard.Name = "Card"
	spinsCard.Size = UDim2.new(1, 0, 1, -36)
	spinsCard.Position = UDim2.new(0, 0, 0, 36)
	spinsCard.BackgroundColor3 = PANEL
	spinsCard.BorderSizePixel = 0
	spinsCard.Parent = spinsPage
	corner(spinsCard, 14)
	stroke(spinsCard, EDGE, 0.4)
	gradient(spinsCard, Color3.new(1, 1, 1), Color3.fromRGB(196, 196, 208))

	local spinsCardPad = Instance.new("UIPadding")
	spinsCardPad.PaddingTop = UDim.new(0, 18)
	spinsCardPad.PaddingRight = UDim.new(0, 18)
	spinsCardPad.PaddingBottom = UDim.new(0, 16)
	spinsCardPad.PaddingLeft = UDim.new(0, 18)
	spinsCardPad.Parent = spinsCard

	local spinsCardLayout = Instance.new("UIListLayout")
	spinsCardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	spinsCardLayout.Padding = UDim.new(0, 10)
	spinsCardLayout.Parent = spinsCard

	local spinsTitle = Instance.new("TextLabel")
	spinsTitle.LayoutOrder = 1
	spinsTitle.BackgroundTransparency = 1
	spinsTitle.Size = UDim2.new(1, 0, 0, 28)
	spinsTitle.Font = Enum.Font.GothamBold
	spinsTitle.Text = "SPINS"
	spinsTitle.TextSize = 22
	spinsTitle.TextColor3 = TEXT
	spinsTitle.TextXAlignment = Enum.TextXAlignment.Left
	spinsTitle.Parent = spinsCard

	-- The same short accent rule as the other two pages' titles, for the same reason: one
	-- family of headings across all three, so the third page reads as part of the same screen
	-- instead of a menu bolted onto it.
	local spinsTitleRule = Instance.new("Frame")
	spinsTitleRule.LayoutOrder = 2
	spinsTitleRule.Size = UDim2.new(0, 56, 0, 2)
	spinsTitleRule.BackgroundColor3 = ACCENT
	spinsTitleRule.BorderSizePixel = 0
	spinsTitleRule.Parent = spinsCard
	corner(spinsTitleRule, 1)
	local spinsRuleFade = Instance.new("UIGradient")
	spinsRuleFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	spinsRuleFade.Parent = spinsTitleRule

	local spinsSubtitle = Instance.new("TextLabel")
	spinsSubtitle.LayoutOrder = 3
	spinsSubtitle.BackgroundTransparency = 1
	spinsSubtitle.Size = UDim2.new(1, 0, 0, 18)
	spinsSubtitle.Font = Enum.Font.Gotham
	spinsSubtitle.Text = "Loading..."
	spinsSubtitle.TextSize = 13
	spinsSubtitle.TextColor3 = MUTED
	spinsSubtitle.TextXAlignment = Enum.TextXAlignment.Left
	spinsSubtitle.Parent = spinsCard

	-- One scrolling body rather than nested scroll regions for the odds list and the buy list
	-- separately -- the same choice `SetupCard` makes for its own sections, and for the same
	-- reason: two independent scrollbars on one small card is two things fighting the cursor
	-- for one wheel.
	local spinsBody = Instance.new("ScrollingFrame")
	spinsBody.LayoutOrder = 4
	spinsBody.Size = UDim2.new(1, 0, 1, -110)
	spinsBody.BackgroundTransparency = 1
	spinsBody.BorderSizePixel = 0
	spinsBody.ScrollBarThickness = 3
	spinsBody.ScrollBarImageColor3 = EDGE
	spinsBody.CanvasSize = UDim2.new()
	spinsBody.AutomaticCanvasSize = Enum.AutomaticSize.Y
	spinsBody.ScrollingDirection = Enum.ScrollingDirection.Y
	spinsBody.Parent = spinsCard
	local spinsBodyLayout = Instance.new("UIListLayout")
	spinsBodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	spinsBodyLayout.Padding = UDim.new(0, 8)
	spinsBodyLayout.Parent = spinsBody
	local spinsBodyPad = Instance.new("UIPadding")
	spinsBodyPad.PaddingRight = UDim.new(0, 8)
	spinsBodyPad.PaddingBottom = UDim.new(0, 8)
	spinsBodyPad.Parent = spinsBody

	-- The spin itself, first in the body -- the one action on this whole page that is not
	-- "look" or "buy", and the reason a player opened it.
	local spinButton = Instance.new("TextButton")
	spinButton.LayoutOrder = 1
	spinButton.Size = UDim2.new(1, 0, 0, 44)
	spinButton.BackgroundColor3 = ACCENT
	spinButton.BorderSizePixel = 0
	spinButton.AutoButtonColor = false
	spinButton.Text = ""
	-- Closed until the first `SpinsUpdated` lands and `redrawSpins` opens it for real --
	-- otherwise there is a window, between this button existing and any state describing it,
	-- where a press would fire a spin the server has nothing to answer honestly.
	spinButton.Active = false
	spinButton.Parent = spinsBody
	corner(spinButton, 10)

	local spinButtonLabel = Instance.new("TextLabel")
	spinButtonLabel.Name = "Label"
	spinButtonLabel.BackgroundTransparency = 1
	spinButtonLabel.Size = UDim2.new(1, 0, 1, 0)
	spinButtonLabel.Font = Enum.Font.GothamBold
	spinButtonLabel.Text = "Spin"
	spinButtonLabel.TextSize = 16
	spinButtonLabel.TextColor3 = INK
	spinButtonLabel.Parent = spinButton

	local oddsHeading = Instance.new("TextLabel")
	oddsHeading.LayoutOrder = 10
	oddsHeading.BackgroundTransparency = 1
	oddsHeading.Size = UDim2.new(1, 0, 0, 16)
	oddsHeading.Font = Enum.Font.GothamBold
	oddsHeading.Text = "WHAT YOU CAN LAND ON"
	oddsHeading.TextSize = 12
	oddsHeading.TextColor3 = MUTED
	oddsHeading.TextXAlignment = Enum.TextXAlignment.Left
	oddsHeading.Parent = spinsBody

	-- Perk rows are built lazily by `ensurePerkRows`, once the catalog has actually arrived --
	-- there is no Config number for "how many perks" to build them from ahead of time, on the
	-- same principle `ensureCards` follows for the slot count.

	local buyHeading = Instance.new("TextLabel")
	buyHeading.LayoutOrder = 30
	buyHeading.BackgroundTransparency = 1
	buyHeading.Size = UDim2.new(1, 0, 0, 16)
	buyHeading.Font = Enum.Font.GothamBold
	buyHeading.Text = "BUY SPINS"
	buyHeading.TextSize = 12
	buyHeading.TextColor3 = MUTED
	buyHeading.TextXAlignment = Enum.TextXAlignment.Left
	buyHeading.Parent = spinsBody

	-- Product rows are built lazily too, the same way and for the same reason -- see
	-- `ensureProductRows`.

	local spinsStatusLabel = Instance.new("TextLabel")
	spinsStatusLabel.LayoutOrder = 5
	spinsStatusLabel.BackgroundTransparency = 1
	spinsStatusLabel.Size = UDim2.new(1, 0, 0, 30)
	spinsStatusLabel.Font = Enum.Font.Gotham
	spinsStatusLabel.Text = ""
	spinsStatusLabel.TextSize = 12
	spinsStatusLabel.TextColor3 = WARN
	spinsStatusLabel.TextWrapped = true
	spinsStatusLabel.TextYAlignment = Enum.TextYAlignment.Top
	spinsStatusLabel.Parent = spinsCard

	local self = setmetatable({
		gui = gui,
		column = column,
		slotsPage = slotsPage,
		subtitle = subtitle,
		cardList = cardList,
		cards = {},
		playButton = playButton,
		playLabel = playLabel,
		sheen = sheen,
		refusal = refusal,
		refusalToken = 0,
		setupCard = setupCard,
		hasDealt = false,
		playReady = false,
		state = nil,
		options = nil,
		pendingDelete = nil,
		pendingDeleteToken = 0,
		spinsEntryButton = spinsEntryButton,
		spinsEntryLabel = spinsEntryLabel,
		spinsPage = spinsPage,
		spinsBackButton = spinsBackButton,
		spinsSubtitle = spinsSubtitle,
		spinsStatusLabel = spinsStatusLabel,
		spinsBody = spinsBody,
		perkRows = {},
		productRows = {},
		spinButton = spinButton,
		spinButtonLabel = spinButtonLabel,
		spinsState = nil,
		spinBusy = false,
		joinCodePanel = joinCodePanel,
		joinCodeCodeLabel = joinCodeCodeLabel,
		joinCodeCopyButton = joinCodeCopyButton,
		joinCodeRegenButton = joinCodeRegenButton,
		joinCodeHintLabel = joinCodeHintLabel,
		joinCodeInput = joinCodeInput,
		joinCodeJoinButton = joinCodeJoinButton,
		joinCodeBusy = false,
	}, LobbyUI)

	-- Tweened rather than assigned, like the slot cards, so the whole screen answers the cursor
	-- at one speed. A menu where one control snaps and the others ease reads as unfinished even
	-- to somebody who could not say why.
	playButton.MouseEnter:Connect(function()
		if playButton.Active and self.playReady then
			TweenService:Create(playButton, HOVER_INFO, { BackgroundColor3 = ACCENT_HOVER }):Play()
		end
	end)
	playButton.MouseLeave:Connect(function()
		if playButton.Active and self.playReady then
			TweenService:Create(playButton, HOVER_INFO, { BackgroundColor3 = ACCENT }):Play()
		end
	end)
	playButton.Activated:Connect(function()
		self:onPlay()
	end)

	spinsEntryButton.Activated:Connect(function()
		self:showSpins()
	end)
	spinsBackButton.Activated:Connect(function()
		self:showSlots()
	end)
	spinButton.MouseEnter:Connect(function()
		if spinButton.Active then
			TweenService:Create(spinButton, HOVER_INFO, { BackgroundColor3 = ACCENT_HOVER }):Play()
		end
	end)
	spinButton.MouseLeave:Connect(function()
		if spinButton.Active then
			TweenService:Create(spinButton, HOVER_INFO, { BackgroundColor3 = ACCENT }):Play()
		end
	end)
	spinButton.Activated:Connect(function()
		self:onSpin()
	end)

	setupCard:OnBack(function()
		self:showSlots()
	end)
	-- `perkId` travels outside the `SetupRequest`-typed table -- see `SetupCard`'s own comment
	-- on `onCreate` -- and gets folded into the payload here, on the way out, rather than in a
	-- type both places would have to agree includes it.
	setupCard:OnCreate(function(slot: number, request: SetupRequest, perkId: string?)
		if perkId == nil then
			RequestCreateLifeRemote:FireServer(slot, request)
		else
			RequestCreateLifeRemote:FireServer(slot, {
				gender = request.gender,
				firstName = request.firstName,
				lastName = request.lastName,
				countryId = request.countryId,
				eraId = request.eraId,
				statDeltas = request.statDeltas,
				perkId = perkId,
			})
		end
	end)

	joinCodeCopyButton.Activated:Connect(function()
		self:onCopyCode()
	end)
	joinCodeRegenButton.Activated:Connect(function()
		self:onRegenCode()
	end)
	joinCodeJoinButton.Activated:Connect(function()
		self:onJoinByCode()
	end)

	playEntrance(column, scrim)
	self:runSheen()

	return self
end

-- ---------------------------------------------------------------------------
-- Motion
-- ---------------------------------------------------------------------------

-- Walk the highlight across Play, forever, but only while pressing Play would do something.
--
-- The gate is the point. A button that shines while refusing to open anything is advertising a
-- thing it will not do, and a player who presses it twice on the strength of the shine learns
-- to stop believing the button rather than to read the line under it -- so a dead slot, an
-- empty slot and a teleport already in flight are all silent.
--
-- The loop ends when the ScreenGui does, which in this place means the teleport landed.
function LobbyUI.runSheen(self: LobbyUIHandle)
	task.spawn(function()
		local travel = TweenInfo.new(MOTION.SheenSweepSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		while self.gui.Parent ~= nil do
			task.wait(MOTION.SheenPeriodSeconds)
			if not (self.playReady and self.playButton.Active) then
				continue
			end
			self.sheen.Position = UDim2.new(-0.3, 0, 0.5, 0)
			self.sheen.Visible = true
			TweenService:Create(self.sheen, travel, { Position = UDim2.new(1.3, 0, 0.5, 0) }):Play()
			task.wait(MOTION.SheenSweepSeconds)
			self.sheen.Visible = false
		end
	end)
end

-- Deal the cards in, one after another, once.
--
-- Runs off the first slot list to arrive rather than off `new`, because there are no cards
-- until the server has said how many -- and it runs once, because a list that re-flew in every
-- time a life was created would be the screen applauding its own redraw.
function LobbyUI.deal(self: LobbyUIHandle, count: number)
	for index = 1, count do
		local card = self.cards[index]
		if card == nil then
			continue
		end
		local home = cardHomeY(index)
		card.button.Position = UDim2.new(0, 0, 0, home + MOTION.CardRisePixels)
		-- The stagger is the TweenInfo's delay rather than a `task.delay` per card, so it is one
		-- scheduling decision made by the engine instead of N timers this file would have to be
		-- sure it cancelled if the player left mid-deal.
		TweenService:Create(
			card.button,
			TweenInfo.new(
				MOTION.CardRiseSeconds,
				Enum.EasingStyle.Quint,
				Enum.EasingDirection.Out,
				0,
				false,
				(index - 1) * MOTION.CardStaggerSeconds
			),
			{ Position = UDim2.new(0, 0, 0, home) }
		):Play()
	end
end

-- ---------------------------------------------------------------------------
-- Slot cards
-- ---------------------------------------------------------------------------

-- Built on demand rather than in `new`, because how many there are is the server's answer
-- (`state.slotCount`) and not this file's. Reading `Config.Slots.Count` here would work today
-- and would be a second answer to a question the payload already answers -- and the whole
-- reason `slotCount` is on the wire is that a card must never appear for a slot the server
-- would refuse. Idempotent: cards already made are left exactly as they are.
local function ensureCards(self: LobbyUIHandle, count: number)
	for index = 1, count do
		if self.cards[index] ~= nil then
			continue
		end

		local button = Instance.new("TextButton")
		button.Name = `Slot{index}`
		button.Size = UDim2.new(1, 0, 0, SLOT_CARD_HEIGHT)
		button.Position = UDim2.new(0, 0, 0, cardHomeY(index))
		button.BackgroundColor3 = ROW
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Text = ""
		button.Parent = self.cardList
		corner(button, 12)
		gradient(button, Color3.new(1, 1, 1), Color3.fromRGB(178, 178, 190))
		local outline = stroke(button, EDGE, 1)
		outline.Name = "Outline"

		-- Inset from the edge rather than flush with it, so the bar is a floating pill inside
		-- the card. Flush against a corner radius of 12 would clip its own ends off.
		local spine = Instance.new("Frame")
		spine.Name = "Spine"
		spine.AnchorPoint = Vector2.new(0, 0.5)
		spine.Position = UDim2.new(0, 10, 0.5, 0)
		spine.Size = UDim2.new(0, 4, 1, -28)
		spine.BackgroundColor3 = EDGE
		spine.BorderSizePixel = 0
		spine.Parent = button
		corner(spine, 2)

		local indexLabel = Instance.new("TextLabel")
		indexLabel.Name = "Index"
		indexLabel.BackgroundTransparency = 1
		indexLabel.AnchorPoint = Vector2.new(1, 0)
		indexLabel.Position = UDim2.new(1, -12, 0, 10)
		indexLabel.Size = UDim2.new(0, 60, 0, 14)
		indexLabel.Font = Enum.Font.GothamBold
		indexLabel.Text = `SLOT {index}`
		indexLabel.TextSize = 10
		indexLabel.TextColor3 = MUTED
		indexLabel.TextXAlignment = Enum.TextXAlignment.Right
		indexLabel.Parent = button

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Name"
		nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.new(0, 26, 0, 14)
		nameLabel.Size = UDim2.new(1, -102, 0, 26)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.Text = ""
		nameLabel.TextSize = 19
		nameLabel.TextColor3 = TEXT
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Parent = button

		local detailLabel = Instance.new("TextLabel")
		detailLabel.Name = "Detail"
		detailLabel.BackgroundTransparency = 1
		detailLabel.Position = UDim2.new(0, 26, 0, 42)
		detailLabel.Size = UDim2.new(1, -40, 0, 18)
		detailLabel.Font = Enum.Font.Gotham
		detailLabel.Text = ""
		detailLabel.TextSize = 13
		detailLabel.TextColor3 = MUTED
		detailLabel.TextXAlignment = Enum.TextXAlignment.Left
		detailLabel.TextTruncate = Enum.TextTruncate.AtEnd
		detailLabel.Parent = button

		-- One button, two jobs, because a card is only ever in one of two states: empty, and
		-- then the only thing to do with it is fill it; or occupied, and then the only thing
		-- this row offers beyond selecting it is emptying it. Two buttons would mean one of
		-- them is always dead, and a permanently greyed control on every card is clutter that
		-- teaches the player to stop reading that corner.
		local actionButton = Instance.new("TextButton")
		actionButton.Name = "Action"
		actionButton.AnchorPoint = Vector2.new(1, 1)
		actionButton.Position = UDim2.new(1, -12, 1, -10)
		actionButton.Size = UDim2.new(0, 108, 0, 24)
		actionButton.BackgroundColor3 = ROW_HOVER
		actionButton.BorderSizePixel = 0
		actionButton.AutoButtonColor = false
		actionButton.Font = Enum.Font.GothamMedium
		actionButton.Text = ""
		actionButton.TextSize = 12
		actionButton.TextColor3 = TEXT
		actionButton.Parent = button
		corner(actionButton, 6)

		self.cards[index] = {
			button = button,
			outline = outline,
			spine = spine,
			nameLabel = nameLabel,
			detailLabel = detailLabel,
			indexLabel = indexLabel,
			actionButton = actionButton,
		}

		-- **Hover owns Position and BackgroundColor3; `redraw` owns everything else.** That split
		-- is what keeps the two from fighting, and it is the reason the selected card is outlined
		-- rather than filled -- an outline is `redraw`'s to colour and the fill is hover's, so a
		-- selected card under the cursor shows both instead of one overwriting the other.
		local home = cardHomeY(index)
		button.MouseEnter:Connect(function()
			TweenService:Create(button, HOVER_INFO, {
				BackgroundColor3 = ROW_HOVER,
				Position = UDim2.new(0, MOTION.CardHoverPixels, 0, home),
			}):Play()
		end)
		button.MouseLeave:Connect(function()
			TweenService:Create(button, HOVER_INFO, {
				BackgroundColor3 = ROW,
				Position = UDim2.new(0, 0, 0, home),
			}):Play()
		end)
		button.Activated:Connect(function()
			self:onSelect(index)
		end)
		actionButton.Activated:Connect(function()
			self:onCardAction(index)
		end)
	end

	-- Set from the count rather than measured, because nothing measures these any more -- the
	-- cards are placed by hand. The trailing gap is subtracted so the last card sits against the
	-- bottom of the canvas instead of ten pixels of nothing scrolling past it.
	self.cardList.CanvasSize = UDim2.new(0, 0, 0, math.max(0, cardHomeY(count + 1) - SLOT_CARD_GAP))
end

local function slotAt(state: LobbyState, index: number): SlotSummary?
	for _, slot in state.slots do
		if slot.index == index then
			return slot
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function LobbyUI.showSlots(self: LobbyUIHandle)
	self.setupCard:Hide()
	self.spinsPage.Visible = false
	self.slotsPage.Visible = true
end

-- Open the create card on a slot. Refuses on this side when the options have not arrived,
-- which is the one refusal that is right to make here: the server would say the same thing,
-- and a round trip to be told "your options have not loaded" is a round trip that needs them
-- to have loaded.
function LobbyUI.showCreate(self: LobbyUIHandle, index: number)
	local options = self.options
	if options == nil then
		self:refuse("Still loading. Give it a moment and try again.")
		return
	end
	self:clearPendingDelete()
	self:clearRefusal()
	self.spinsPage.Visible = false
	self.slotsPage.Visible = false
	self.setupCard:Show(options, index)
end

-- Open the spins page. Refuses on this side, the same way `showCreate` does for the setup
-- card, when the state has not arrived yet -- there is nothing to draw and the server would
-- refuse a buy or a spin fired blind the same way.
function LobbyUI.showSpins(self: LobbyUIHandle)
	if self.spinsState == nil then
		self:refuse("Still loading. Give it a moment and try again.")
		return
	end
	self:clearPendingDelete()
	self:clearRefusal()
	self.setupCard:Hide()
	self.slotsPage.Visible = false
	self.spinsPage.Visible = true
	self:redrawSpins()
end

function LobbyUI.onSelect(self: LobbyUIHandle, index: number)
	-- Selecting any card disarms a delete waiting on another one. The player has moved on, and
	-- an armed delete they are no longer looking at is a trap.
	if self.pendingDelete ~= nil and self.pendingDelete ~= index then
		self:clearPendingDelete()
	end
	local state = self.state
	if state == nil then
		self:refuse("Your lives have not loaded yet. Give it a moment.")
		return
	end
	self:clearRefusal()
	RequestSelectSlotRemote:FireServer(index)
end

-- The corner button. Create on an empty card; delete, twice, on a full one.
function LobbyUI.onCardAction(self: LobbyUIHandle, index: number)
	local state = self.state
	if state == nil then
		self:refuse("Your lives have not loaded yet. Give it a moment.")
		return
	end
	local slot = slotAt(state, index)
	if slot == nil then
		return
	end

	if not slot.begun then
		self:showCreate(index)
		return
	end

	if self.pendingDelete == index then
		-- The second press. Everything about this is deliberately not undoable, which is why it
		-- took two presses and a countdown to get here.
		self:clearPendingDelete()
		self:clearRefusal()
		RequestDeleteSlotRemote:FireServer(index)
		return
	end

	self:armDelete(index)
end

-- Put one card into "press again" for a few seconds.
--
-- **Deleting a life is the only irreversible thing in this game that is not dying**, so it
-- takes two presses -- see `Config.Slots.DeleteConfirmSeconds`. A modal dialog would be the
-- other way to ask, and it would be worse: a dialog is a thing to be dismissed, and the
-- muscle memory for dismissing one is a click in roughly the place the confirm button is.
-- Arming the button the player is already pointing at, in place, with the name of the person
-- it is about to erase written next to it, asks the question where the answer will be given.
function LobbyUI.armDelete(self: LobbyUIHandle, index: number)
	self.pendingDelete = index
	self.pendingDeleteToken += 1
	local token = self.pendingDeleteToken
	self:redraw()

	task.delay(Config.Slots.DeleteConfirmSeconds, function()
		-- The token is what makes arming a second card safe: the first one's timer wakes up,
		-- finds it is no longer the current arming, and does nothing rather than disarming the
		-- one the player is now looking at.
		if self.pendingDeleteToken ~= token then
			return
		end
		self.pendingDelete = nil
		self:redraw()
	end)
end

function LobbyUI.clearPendingDelete(self: LobbyUIHandle)
	if self.pendingDelete == nil then
		return
	end
	self.pendingDelete = nil
	self.pendingDeleteToken += 1
	self:redraw()
end

function LobbyUI.onPlay(self: LobbyUIHandle)
	if not self.playButton.Active then
		return
	end
	local state = self.state
	if state == nil then
		-- Refused on the client, and this is the one refusal that is right to make here: the
		-- server would say the same thing, and a round trip to be told "your save has not
		-- loaded" is a round trip that needs the save to have loaded.
		self:refuse("Your lives have not loaded yet. Give it a moment.")
		return
	end
	self:clearPendingDelete()
	self:clearRefusal()
	self:setBusy(true)
	RequestPlayRemote:FireServer(state.activeSlot)
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local function describe(slot: SlotSummary): string
	if not slot.begun then
		return "Nobody here yet"
	end
	local age = slot.ageYears or 0
	local country = slot.country or "?"
	if slot.alive == false then
		return `Died at {age} -- {country}`
	end
	return `Age {age} -- {country}`
end

function LobbyUI.render(self: LobbyUIHandle, state: LobbyState)
	self.state = state
	-- A delete armed on a card whose contents have just changed underneath it is disarmed
	-- rather than carried over. The name next to the button is what the player agreed to
	-- erase, and once that name can have moved, the agreement no longer covers it.
	self.pendingDelete = nil
	self.pendingDeleteToken += 1
	self:redraw()
end

-- Everything the slot list looks like, for the state it is in. The only function in this file
-- that writes a card property after construction -- so there is one description of the screen
-- rather than one per button that has to remember what the other buttons did.
function LobbyUI.redraw(self: LobbyUIHandle)
	local state = self.state
	if state == nil then
		return
	end
	ensureCards(self, state.slotCount)

	-- Dealt here rather than in `ensureCards`, because building a card and animating one are
	-- different questions with different answers: cards are built the first time a slot count is
	-- seen, and dealt the first time this screen is drawn at all. Raising `Config.Slots.Count`
	-- mid-session would build a fourth card and correctly not re-deal the other three.
	if not self.hasDealt then
		self.hasDealt = true
		self:deal(state.slotCount)
	end

	local begun = 0
	for _, slot in state.slots do
		if slot.begun then
			begun += 1
		end
	end
	-- Counted off `state.slotCount` rather than written out in words, so raising the slot count
	-- in Config does not leave the subtitle insisting there are three of them.
	self.subtitle.Text = if begun == 0
		then `{state.slotCount} slots, no lives yet. Start one.`
		elseif state.livesLived == 0 then `{begun} of {state.slotCount} slots in use`
		else `{begun} of {state.slotCount} slots in use -- {state.livesLived} lives lived`

	self:redrawJoinCode()

	for index = 1, state.slotCount do
		local card = self.cards[index]
		if card == nil then
			continue
		end
		local slot = slotAt(state, index)
		local begunHere = slot ~= nil and slot.begun
		local dead = slot ~= nil and slot.alive == false
		local selected = state.activeSlot == index
		local arming = self.pendingDelete == index

		card.nameLabel.Text = if slot ~= nil and slot.name ~= nil then slot.name else "Empty slot"
		card.nameLabel.TextColor3 = if not begunHere then MUTED elseif dead then GONE else TEXT
		card.detailLabel.Text = if arming
			then "Press again to delete this life forever."
			elseif slot ~= nil then describe(slot)
			else "Nobody here yet"
		card.detailLabel.TextColor3 = if arming then WARN elseif dead then GONE else MUTED
		card.indexLabel.TextColor3 = if selected then ACCENT else MUTED

		-- The spine answers "is there somebody in here, and are they alive" and nothing else.
		-- Selection is deliberately not in it: selection is a thing the player just did and can
		-- undo, and life and death are not, so putting both on one strip of colour would let the
		-- reversible fact hide the permanent one.
		card.spine.BackgroundColor3 = if arming
			then WARN
			elseif not begunHere then EDGE
			elseif dead then GONE
			else LIVING

		-- The selected card is outlined rather than filled, so the highlight survives the hover
		-- colour landing on top of it. Two things that both change the background is how a card
		-- ends up looking selected because the cursor happens to be over it.
		card.outline.Color = if arming then WARN elseif selected then ACCENT else EDGE
		card.outline.Thickness = if arming or selected then 2 else 1

		card.actionButton.Text = if not begunHere
			then "Create a life"
			elseif arming then "Delete forever"
			else "Delete"
		card.actionButton.TextColor3 = if not begunHere then ACCENT elseif arming then INK else MUTED
		card.actionButton.BackgroundColor3 = if arming then WARN else ROW_HOVER
	end

	-- A finished life stays in its slot on purpose: it is a record of somebody the player
	-- actually lived, and this list is the only place that record is kept. What it is not is
	-- somewhere to press Play, so a dead slot is not ready even though it is not empty.
	local active = slotAt(state, state.activeSlot)
	self.playReady = active ~= nil and active.begun and active.alive ~= false

	-- The button reports what pressing it will do, including when that is nothing. A button
	-- that looks live and then refuses is a button the player learns to distrust; one that says
	-- "Slot 2 is empty" has already answered the press.
	self.playLabel.Text = if active == nil
		then `Slot {state.activeSlot}`
		elseif not active.begun then `Slot {active.index} is empty -- create a life in it first`
		elseif active.alive == false then `Slot {active.index} -- {active.name or "?"} has died. Delete it to start again.`
		-- The country is on the card and not repeated here. This line has one job -- say which
		-- person this button opens -- and it truncates, so anything after the name is a gamble.
		else `Slot {active.index} -- {active.name or "?"}, age {active.ageYears or 0}`

	-- Left alone while a teleport is in the air, because `setBusy` owns the colour then and two
	-- writers would race to say what the button looks like.
	if self.playButton.Active then
		self.playButton.BackgroundColor3 = if self.playReady then ACCENT else BUSY
	end
end

-- ---------------------------------------------------------------------------
-- Spins
-- ---------------------------------------------------------------------------

-- Built lazily, on the same "ensure" pattern `ensureCards` follows for slot count: there is
-- no Config number for how many perks exist to build rows from ahead of time, only the
-- catalog the server actually sent, so the rows cannot exist before the first `SpinsUpdated`.
-- Idempotent, like `ensureCards` -- rows already built are left exactly as they are.
local function ensurePerkRows(self: LobbyUIHandle, count: number)
	for index = 1, count do
		if self.perkRows[index] ~= nil then
			continue
		end

		local frame = Instance.new("Frame")
		frame.Name = `Perk{index}`
		frame.LayoutOrder = 11 + index
		frame.Size = UDim2.new(1, 0, 0, 70)
		frame.BackgroundColor3 = ROW
		frame.BorderSizePixel = 0
		frame.Parent = self.spinsBody
		corner(frame, 8)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Name"
		nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.new(0, 10, 0, 6)
		nameLabel.Size = UDim2.new(1, -100, 0, 18)
		nameLabel.Font = Enum.Font.GothamMedium
		nameLabel.Text = ""
		nameLabel.TextSize = 14
		nameLabel.TextColor3 = TEXT
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = frame

		local rarityLabel = Instance.new("TextLabel")
		rarityLabel.Name = "Rarity"
		rarityLabel.BackgroundTransparency = 1
		rarityLabel.Position = UDim2.new(0, 10, 0, 24)
		rarityLabel.Size = UDim2.new(1, -100, 0, 14)
		rarityLabel.Font = Enum.Font.GothamBold
		rarityLabel.Text = ""
		rarityLabel.TextSize = 10
		rarityLabel.TextColor3 = MUTED
		rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
		rarityLabel.Parent = frame

		local blurbLabel = Instance.new("TextLabel")
		blurbLabel.Name = "Blurb"
		blurbLabel.BackgroundTransparency = 1
		blurbLabel.Position = UDim2.new(0, 10, 0, 42)
		blurbLabel.Size = UDim2.new(1, -20, 0, 24)
		blurbLabel.Font = Enum.Font.Gotham
		blurbLabel.Text = ""
		blurbLabel.TextSize = 11
		blurbLabel.TextColor3 = MUTED
		blurbLabel.TextXAlignment = Enum.TextXAlignment.Left
		blurbLabel.TextWrapped = true
		blurbLabel.TextYAlignment = Enum.TextYAlignment.Top
		blurbLabel.Parent = frame

		-- Disclosed per-perk odds -- see `Perks.Odds` server-side -- not just the tier's, which
		-- is what Roblox requires shown before a paid random-item purchase.
		local oddsLabel = Instance.new("TextLabel")
		oddsLabel.Name = "Odds"
		oddsLabel.AnchorPoint = Vector2.new(1, 0)
		oddsLabel.Position = UDim2.new(1, -10, 0, 6)
		oddsLabel.Size = UDim2.new(0, 80, 0, 18)
		oddsLabel.Font = Enum.Font.GothamBold
		oddsLabel.Text = ""
		oddsLabel.TextSize = 13
		oddsLabel.TextColor3 = ACCENT
		oddsLabel.TextXAlignment = Enum.TextXAlignment.Right
		oddsLabel.Parent = frame

		local ownedLabel = Instance.new("TextLabel")
		ownedLabel.Name = "Owned"
		ownedLabel.AnchorPoint = Vector2.new(1, 0)
		ownedLabel.Position = UDim2.new(1, -10, 0, 24)
		ownedLabel.Size = UDim2.new(0, 80, 0, 14)
		ownedLabel.Font = Enum.Font.Gotham
		ownedLabel.Text = ""
		ownedLabel.TextSize = 11
		ownedLabel.TextColor3 = LIVING
		ownedLabel.TextXAlignment = Enum.TextXAlignment.Right
		ownedLabel.Parent = frame

		self.perkRows[index] = {
			frame = frame,
			nameLabel = nameLabel,
			rarityLabel = rarityLabel,
			blurbLabel = blurbLabel,
			oddsLabel = oddsLabel,
			ownedLabel = ownedLabel,
		}
	end
end

-- Built lazily too, from the length of `SpinsState.products` as sent over the wire rather
-- than `Config.Spins.Products` read directly -- the client could read Config here, but the
-- wire list is what the server will actually honour a buy against, and one source avoids the
-- two ever disagreeing about how many there are.
local function ensureProductRows(self: LobbyUIHandle, count: number)
	for index = 1, count do
		if self.productRows[index] ~= nil then
			continue
		end

		local button = Instance.new("TextButton")
		button.Name = `Product{index}`
		button.LayoutOrder = 31 + index
		button.Size = UDim2.new(1, 0, 0, 40)
		button.BackgroundColor3 = ROW
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Font = Enum.Font.GothamMedium
		button.Text = ""
		button.TextSize = 14
		button.TextColor3 = TEXT
		button.Parent = self.spinsBody
		corner(button, 8)

		button.MouseEnter:Connect(function()
			if button.Active then
				TweenService:Create(button, HOVER_INFO, { BackgroundColor3 = ROW_HOVER }):Play()
			end
		end)
		button.MouseLeave:Connect(function()
			if button.Active then
				TweenService:Create(button, HOVER_INFO, { BackgroundColor3 = ROW }):Play()
			end
		end)
		-- Reads the product back off `spinsState` by index at click time rather than closing
		-- over the record handed to `ensureProductRows` -- the row is built once but `redrawSpins`
		-- keeps relabelling it, and this way the two can never name different products.
		button.Activated:Connect(function()
			local state = self.spinsState
			if state == nil then
				return
			end
			local product = state.products[index]
			if product == nil then
				return
			end
			self:onBuy(product)
		end)

		self.productRows[index] = { button = button }
	end
end

function LobbyUI.redrawJoinCode(self: LobbyUIHandle)
	local state = self.state
	if state == nil then
		return
	end
	local code = state.joinCode
	self.joinCodeCodeLabel.Text = if code ~= nil then code else ""
	self.joinCodeHintLabel.Visible = code == nil
	self.joinCodeCodeLabel.Visible = code ~= nil
	self.joinCodeCopyButton.Active = code ~= nil and not self.joinCodeBusy
	self.joinCodeRegenButton.Active = code ~= nil and not self.joinCodeBusy
	self.joinCodeJoinButton.Active = code ~= nil and not self.joinCodeBusy
end

-- Everything the spins page looks like, for the state it is in -- the only function in this
-- file that writes a perk-row or product-row property after construction, on the same
-- one-writer rule `redraw` follows for the slot cards.
function LobbyUI.redrawSpins(self: LobbyUIHandle)
	local state = self.spinsState
	if state == nil then
		return
	end
	ensurePerkRows(self, #state.catalog)
	ensureProductRows(self, #state.products)

	self.spinsSubtitle.Text = if state.spinsAvailable == 1
		then "1 spin available"
		else `{state.spinsAvailable} spins available`

	local owned: { [string]: number } = {}
	for _, entry in state.perksOwned do
		owned[entry.id] = entry.count
	end

	for index, perk in state.catalog do
		local row = self.perkRows[index]
		if row == nil then
			continue
		end
		row.nameLabel.Text = perk.name
		row.rarityLabel.Text = string.upper(perk.rarity)
		row.blurbLabel.Text = perk.blurb
		-- Out of 1 on the wire -- see `Types.PerkOffer` -- shown as a percentage to one decimal
		-- place, which is precise enough to disclose honestly and short enough to read at a
		-- glance.
		row.oddsLabel.Text = `{string.format("%.1f", perk.odds * 100)}%`
		local count = owned[perk.id] or 0
		row.ownedLabel.Text = if count > 0 then `Owned x{count}` else ""
	end

	for index, product in state.products do
		local row = self.productRows[index]
		if row == nil then
			continue
		end
		-- The same refuse-by-name pattern as `Config.Lobby.GamePlaceId`: a product with no id
		-- yet is shown rather than hidden, so the catalogue reads as "coming soon" instead of
		-- quietly missing a row, and pressing it explains itself instead of doing nothing.
		local published = product.productId ~= 0
		row.button.Text = if published
			then `{product.name} -- R$ {product.robuxPrice}`
			else `{product.name} -- not available yet`
		row.button.Active = published
		row.button.BackgroundColor3 = if published then ROW else ROW_LOCKED
		row.button.TextColor3 = if published then TEXT else DISABLED
	end

	local canSpin = state.spinsAvailable > 0 and not self.spinBusy
	self.spinButton.Active = canSpin
	self.spinButton.BackgroundColor3 = if self.spinBusy or state.spinsAvailable <= 0 then BUSY else ACCENT
	-- Same rule as the Play button's label: the button says why it cannot be pressed rather
	-- than sitting there greyed and mute.
	self.spinButtonLabel.Text = if self.spinBusy
		then "Spinning..."
		elseif state.spinsAvailable <= 0 then "No spins -- buy one below"
		else "Spin"

	self.spinsEntryLabel.Text = if state.spinsAvailable == 1 then "1 spin" else `{state.spinsAvailable} spins`
end

-- One pull. Locked immediately, exactly like `onPlay` locks Play -- the answer is on the wire
-- and a second press before it lands would be a second spin spent on the strength of a button
-- that had not caught up yet.
function LobbyUI.onSpin(self: LobbyUIHandle)
	if not self.spinButton.Active then
		return
	end
	self.spinBusy = true
	self.spinsStatusLabel.Text = ""
	self:redrawSpins()
	RequestSpinRemote:FireServer()
end

-- Opens the Robux purchase prompt for one product. Nothing here grants a spin -- see
-- `SpinsService.RequestBuy` -- so there is nothing to lock: Roblox owns the prompt from here,
-- and the eventual grant answers itself by `SpinsUpdated` arriving with a higher count.
function LobbyUI.onBuy(_self: LobbyUIHandle, product: SpinProduct)
	RequestBuySpinsRemote:FireServer(product.id)
end

function LobbyUI.onCopyCode(self: LobbyUIHandle)
	local code = self.state.joinCode
	if code == nil or self.joinCodeBusy then
		return
	end
	self.joinCodeBusy = true
	self:redrawJoinCode()
	-- The clipboard is a client-only copy -- no remote needed, because the code is already
	-- on screen and the only thing the clipboard does is move it off this device.
	local ok, err = pcall(function()
		setclipboard(code)
	end)
	if ok then
		self.joinCodeCopyButton.Text = "Copied"
		task.delay(1.5, function()
			self.joinCodeCopyButton.Text = ""
			self.joinCodeBusy = false
			self:redrawJoinCode()
		end)
	else
		self:refuse(`Could not copy to clipboard: {err}`)
		self.joinCodeBusy = false
		self:redrawJoinCode()
	end
end

function LobbyUI.onRegenCode(self: LobbyUIHandle)
	if self.joinCodeBusy then
		return
	end
	self.joinCodeBusy = true
	self:redrawJoinCode()
	RequestJoinByCodeRemote:FireServer()
	-- The server pushes a new state; the redraw joins it. Until it lands the button stays
	-- locked so a double-press does not queue two generations.
	task.delay(Config.Lobby.JoinCode.TTLSeconds, function()
		-- Failsafe: if the server pushed nothing at all (unlikely), unlock after a long wait
		-- rather than leaving the button permanently grey.
		if self.joinCodeBusy then
			self.joinCodeBusy = false
			self:redrawJoinCode()
		end
	end)
end

function LobbyUI.onJoinByCode(self: LobbyUIHandle)
	if self.joinCodeBusy then
		return
	end
	local code = self.joinCodeInput.Text
	if code == "" then
		self:refuse("Type a code to join.")
		return
	end
	self.joinCodeBusy = true
	self:redrawJoinCode()
	RequestJoinByCodeRemote:FireServer(code)
	-- The server either teleports (success) or refuses on JoinRefused. Both are terminal:
	-- on success the screen goes away, on refusal the refusal handler re-arms the button.
	task.delay(5, function()
		-- Failsafe for a stuck UI if the server never answers.
		if self.joinCodeBusy then
			self.joinCodeBusy = false
			self:redrawJoinCode()
		end
	end)
end

-- Greyed and unclickable while a Play is being answered.
--
-- A second guard on top of the server's `inFlight` window, and both are needed for different
-- reasons. The server's is the one that matters -- a client can be edited -- but a button that
-- stays bright and clickable while nothing visibly happens is a button a player presses again,
-- and the honest answer to the second press is "you already did that", which is worse than the
-- press not landing.
--
-- Only ever cleared by a refusal, because success is not an event that arrives here: it is the
-- place going away.
function LobbyUI.setBusy(self: LobbyUIHandle, busy: boolean)
	self.playButton.Active = not busy
	self.playButton.BackgroundColor3 = if busy then BUSY else ACCENT
	if not busy then
		self:redraw()
	end
end

function LobbyUI.clearRefusal(self: LobbyUIHandle)
	self.refusalToken += 1
	self.refusal.TextTransparency = 1
	self.refusal.BackgroundTransparency = 1
	self.refusal.Text = ""
end

function LobbyUI.refuse(self: LobbyUIHandle, reason: string)
	-- Every refusal releases the button, including ones raised on this side. A refusal is by
	-- definition the end of an attempt, and leaving the release to individual call sites is how
	-- one of them eventually forgets.
	self:setBusy(false)
	self.refusalToken += 1
	local token = self.refusalToken
	self.refusal.Text = reason
	TweenService:Create(self.refusal, TweenInfo.new(Config.UI.NoticeFadeSeconds), {
		TextTransparency = 0,
		BackgroundTransparency = 0.15,
	}):Play()

	task.delay(Config.UI.NoticeSeconds, function()
		-- The token is what makes two refusals in quick succession safe: the first one's timer
		-- wakes up, finds it is no longer the current message, and does nothing rather than
		-- fading out the second one early.
		if self.refusalToken ~= token then
			return
		end
		TweenService:Create(self.refusal, TweenInfo.new(Config.UI.NoticeFadeSeconds), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		}):Play()
	end)
end

function LobbyUI.Start(): LobbyUIHandle
	local ui = LobbyUI.new()

	SlotsUpdatedRemote.OnClientEvent:Connect(function(state: LobbyState)
		local wasCreating = ui.setupCard:IsOpen()
		local targetSlot = ui.setupCard.slot
		ui:render(state)

		-- **This is how a successful create is answered.** There is no acceptance remote,
		-- because the slot list arriving with that slot filled in is a more truthful signal
		-- than one: it says the life is actually in the save, not merely that a handler ran.
		-- Anything else that could fill the slot -- a second session, a debug command -- closes
		-- the card for the same reason, and should.
		if wasCreating then
			local slot = slotAt(state, targetSlot)
			if slot ~= nil and slot.begun then
				ui:showSlots()
			end
		end
	end)

	SetupOptionsRemote.OnClientEvent:Connect(function(options: SetupOptions)
		ui.options = options
	end)

	PlayRefusedRemote.OnClientEvent:Connect(function(reason: string)
		ui:refuse(reason)
	end)

	SlotActionRefusedRemote.OnClientEvent:Connect(function(reason: string)
		-- Shown on whichever page the player is looking at. The create card has its own status
		-- line under the fields, which is where an answer about the name they just typed
		-- belongs; the slot list has the line under Play.
		if ui.setupCard:IsOpen() then
			ui.setupCard:ShowRefusal(reason)
		else
			ui:refuse(reason)
		end
	end)

	-- The one event that answers both a spin and a Robux purchase -- see `SpinsService.Push`.
	-- Neither has its own success remote, for the same reason `SlotsUpdated` doubles as the
	-- create-success signal: the state arriving with a higher count is a more truthful answer
	-- than a second event that merely says a handler ran. Feeds the create card's perk picker
	-- too, since ownership is what `SetPerks` needs and this is the only place it changes.
	SpinsUpdatedRemote.OnClientEvent:Connect(function(state: SpinsState)
		ui.spinsState = state
		ui.spinBusy = false
		ui.setupCard:SetPerks(state.catalog, state.perksOwned)
		if ui.spinsPage.Visible then
			ui:redrawSpins()
		else
			ui.spinsEntryLabel.Text = if state.spinsAvailable == 1 then "1 spin" else `{state.spinsAvailable} spins`
		end
	end)

	SpinActionRefusedRemote.OnClientEvent:Connect(function(reason: string)
		ui.spinBusy = false
		if ui.spinsPage.Visible then
			ui.spinsStatusLabel.Text = reason
			ui:redrawSpins()
		else
			ui:refuse(reason)
		end
	end)

	JoinRefusedRemote.OnClientEvent:Connect(function(reason: string)
		-- A join-by-code attempt was refused. Re-arm the button so the player can try again.
		ui.joinCodeBusy = false
		ui:redrawJoinCode()
		-- Shown under the slot list, the same place every other refusal appears.
		ui:refuse(reason)
	end)

	return ui
end

return LobbyUI
