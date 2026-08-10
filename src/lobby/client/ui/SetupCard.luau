--!strict
-- The card a life is made on. Gender, a name, a country, what you're good at, and which era
-- -- of which there is currently one, and the other three say so out loud.
--
-- **This used to be a screen in the game place and is now a page in the lobby.** The change
-- is not cosmetic. There, the card was drawn over a town that was deliberately frozen behind
-- it -- every clock in the game checked `setup == nil` before it moved -- so the first thing
-- a new player saw was a form on top of a world they could not touch, and the only way off it
-- was to fill it in. Here there is nothing behind it to freeze: the card is one of two pages
-- in the left column, the other page is the slot list, and Back is a real answer. A player
-- who opens it and changes their mind loses nothing, which is the correct cost of changing
-- your mind about a person who does not exist yet.
--
-- **One page, not a wizard.** A four-step flow would be more taps and would hide the shape of
-- the decision -- and the decision here is a *trade*, so the player has to be able to see the
-- points they are taking out of looks at the same moment as the ones they are putting into
-- smarts. Everything is on one card and the card scrolls.
--
-- The whole UI is built once in `new` and only ever *re-labelled* after that, by `Render`.
-- Nothing here creates or destroys an instance in response to a click. State lives in plain
-- fields on the handle, every click mutates a field and calls `Render`, and `Render` is the
-- only function that touches a property -- so there is exactly one description of what the
-- page looks like for a given state, rather than one per button that has to remember
-- everything the other buttons did.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type SetupOptions = Types.SetupOptions
type SetupRequest = Types.SetupRequest
type Country = Types.Country
type Era = Types.Era
type Gender = Types.Gender
type StatName = Types.StatName
type PerkOffer = Types.PerkOffer
type OwnedPerk = Types.OwnedPerk

-- The four stats in the order they are drawn. **Must match `LifeSetup.StatOrder`** -- not for
-- correctness, since the payload is keyed by name, but because a card that lists them in one
-- order while the refusal messages count them in another is a card that is hard to argue with.
local STAT_ORDER: { StatName } = { "health", "happiness", "smarts", "looks" }

local STAT_LABELS: { [string]: string } = {
	health = "Health",
	happiness = "Happiness",
	smarts = "Smarts",
	looks = "Looks",
}

-- The lobby palette. **One table, in Config, read by both files that draw this screen** -- see
-- `Config.Lobby.Menu.Palette`. The two meet at a seam the player can see: pressing "Create a
-- life" swaps the slot list for this card in the same column, in place, with no transition
-- between them, so a colour that differed by six points would read as two different games
-- stitched together. Both files used to keep their own copy with a comment apologising for it.
local P = Config.Lobby.Menu.Palette

local CARD = P.Panel
local ROW = P.Row
local ROW_HOVER = P.RowHover
local ROW_LOCKED = P.RowLocked
local EDGE = P.Edge
local TEXT = P.Text
local MUTED = P.Muted
local ACCENT = P.Accent
local WARN = P.Warn
local INK = P.Ink
local DISABLED = P.Disabled

-- This page settling into place, which is the same gesture a slot card makes when the list is
-- dealt -- so it is deliberately the same numbers. Two rises of slightly different length and
-- easing, alternating as the player moves between the two pages, is the kind of inconsistency
-- nobody can name and everybody feels.
local RISE_PIXELS = Config.Lobby.Menu.Motion.CardRisePixels
local RISE = TweenInfo.new(
	Config.Lobby.Menu.Motion.CardRiseSeconds,
	Enum.EasingStyle.Quint,
	Enum.EasingDirection.Out
)

local SetupCard = {}
SetupCard.__index = SetupCard

type StatRow = {
	valueLabel: TextLabel,
	deltaLabel: TextLabel,
	fill: Frame,
	minus: TextButton,
	plus: TextButton,
}

export type SetupCardHandle = typeof(setmetatable(
	{} :: {
		page: Frame,
		card: Frame,
		subtitleLabel: TextLabel,
		maleButton: TextButton,
		femaleButton: TextButton,
		firstBox: TextBox,
		lastBox: TextBox,
		countryLabel: TextLabel,
		eraLabel: TextLabel,
		eraBlurb: TextLabel,
		eraChip: TextLabel,
		pointsLabel: TextLabel,
		statRows: { [string]: StatRow },
		perkPrev: TextButton,
		perkNext: TextButton,
		perkLabel: TextLabel,
		perkBlurb: TextLabel,
		statusLabel: TextLabel,
		createButton: TextButton,
		surpriseButton: TextButton,
		backButton: TextButton,

		-- Everything the server sent. Nil until the lobby has been told, and the card refuses
		-- to open without it, so every reader may assume it after an `IsOpen` check.
		options: SetupOptions?,
		-- The perk catalog and the player's owned counts, pushed down from LobbyUI's
		-- `SpinsUpdated` handler rather than fetched here -- this card has no remote of its
		-- own, on the same principle as `options`: one file listens to the wire per fact, and
		-- everyone else is handed the answer.
		perkCatalog: { PerkOffer },
		-- Only the entries the player actually owns at least one of, in catalog order. Built
		-- once when the catalog or the owned counts change, rather than filtered on every
		-- `Render`, since `Render` runs on every keystroke in the name boxes.
		perkChoices: { PerkOffer },
		perkCounts: { [string]: number },
		-- 0 is "no perk" -- a real, always-available choice, not the absence of one. 1..#perkChoices
		-- indexes `perkChoices`. Kept as a plain number, like `countryIndex`/`eraIndex`, rather than
		-- an id, so stepping is the same one-line wraparound as the other two pickers.
		perkIndex: number,
		-- Which card this life is being made for. Carried on the request, because the server
		-- writes into a slot and there is no "current" slot for it to assume -- the player can
		-- be looking at slot 3 while slot 1 is the selected one.
		slot: number,
		gender: Gender,
		countryIndex: number,
		eraIndex: number,
		deltas: { [string]: number },
		-- The last name this card *suggested*, as opposed to one the player typed. Picking a
		-- gender or a country re-rolls the suggestion, and doing that over somebody's typed
		-- name would be the card deleting their work -- so the two have to be told apart.
		--
		-- Held as the text itself rather than as a "the player has typed" flag, which was the
		-- obvious version and is wrong: under Roblox's deferred signal behaviour the TextBox's
		-- Changed handler runs *after* the function that set the text, so a flag cleared by
		-- RollName would be set straight back to true by RollName's own writes. Comparing
		-- values has no ordering to get wrong.
		suggestedFirst: string,
		suggestedLast: string,
		-- `perkId` is not a field of `SetupRequest` -- see `LobbySetupService.luau` for why a
		-- perk must never be folded into the type `LifeSetup` also reads -- so it travels as
		-- its own argument here and gets merged into the wire payload by LobbyUI instead.
		onCreate: ((slot: number, request: SetupRequest, perkId: string?) -> ())?,
		onBack: (() -> ())?,
		waiting: boolean,
	},
	SetupCard
))

-- ---------------------------------------------------------------------------
-- Construction helpers. Local functions rather than a shared builder module: this file and
-- LobbyUI are the only two that use them, and a UI kit with two consumers is a layer, not a
-- saving. They are duplicated between the two on purpose -- eight lines of `UICorner` copied
-- once is cheaper to read than a third file that both have to be opened alongside.
-- ---------------------------------------------------------------------------

local function corner(instance: Instance, radius: number)
	local ui = Instance.new("UICorner")
	ui.CornerRadius = UDim.new(0, radius)
	ui.Parent = instance
end

local function stroke(instance: Instance, color: Color3, transparency: number)
	local ui = Instance.new("UIStroke")
	ui.Color = color
	ui.Transparency = transparency
	ui.Thickness = 1
	ui.Parent = instance
end

-- A vertical gradient. Multiplies the object's own `BackgroundColor3` rather than replacing
-- it, so a row that hover-tweens between two colours keeps the same shading through the tween.
-- Same helper, same reasoning, as the one in LobbyUI -- see the note above on why the two files
-- duplicate their builders rather than sharing a third.
local function gradient(instance: GuiObject, top: Color3, bottom: Color3)
	local ui = Instance.new("UIGradient")
	ui.Color = ColorSequence.new(top, bottom)
	ui.Rotation = 90
	ui.Parent = instance
end

local function pad(instance: Instance, top: number, right: number, bottom: number, left: number)
	local ui = Instance.new("UIPadding")
	ui.PaddingTop = UDim.new(0, top)
	ui.PaddingRight = UDim.new(0, right)
	ui.PaddingBottom = UDim.new(0, bottom)
	ui.PaddingLeft = UDim.new(0, left)
	ui.Parent = instance
end

local function list(instance: Instance, spacing: number): UIListLayout
	local ui = Instance.new("UIListLayout")
	ui.SortOrder = Enum.SortOrder.LayoutOrder
	ui.Padding = UDim.new(0, spacing)
	ui.FillDirection = Enum.FillDirection.Vertical
	ui.Parent = instance
	return ui
end

local function label(parent: Instance, order: number, text: string, size: number, color: Color3): TextLabel
	local instance = Instance.new("TextLabel")
	instance.LayoutOrder = order
	instance.Size = UDim2.new(1, 0, 0, size + 6)
	instance.BackgroundTransparency = 1
	instance.Font = Enum.Font.Gotham
	instance.Text = text
	instance.TextSize = size
	instance.TextColor3 = color
	instance.TextXAlignment = Enum.TextXAlignment.Left
	instance.Parent = parent
	return instance
end

-- A section heading: small, spaced, muted. The only thing separating one question from the
-- next, since boxing each section would make the card look like a form.
local function heading(parent: Instance, order: number, text: string): TextLabel
	local instance = label(parent, order, string.upper(text), 12, MUTED)
	instance.Font = Enum.Font.GothamBold
	instance.Size = UDim2.new(1, 0, 0, 16)
	return instance
end

-- Hover feedback, wired once. Skipped when the button is inert, because a row that lights up
-- under the cursor and then does nothing is worse than one that never lit up.
local function hoverable(button: TextButton, idle: Color3, hover: Color3)
	button.MouseEnter:Connect(function()
		if button.Active then
			button.BackgroundColor3 = hover
		end
	end)
	button.MouseLeave:Connect(function()
		if button.Active then
			button.BackgroundColor3 = idle
		end
	end)
end

local function makeButton(parent: Instance, order: number, text: string, height: number): TextButton
	local button = Instance.new("TextButton")
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, height)
	button.BackgroundColor3 = ROW
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamMedium
	button.Text = text
	button.TextSize = 15
	button.TextColor3 = TEXT
	button.Parent = parent
	corner(button, 8)
	hoverable(button, ROW, ROW_HOVER)
	return button
end

-- A `< value >` stepper. Used for both country and era, because they are the same question --
-- pick one of a short ordered list -- and a scrolling sub-list for each would be two more
-- scroll regions on a card that already has one.
local function makeStepper(parent: Instance, order: number, height: number): (Frame, TextButton, TextButton, Frame)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, height)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local prev = Instance.new("TextButton")
	prev.Size = UDim2.new(0, 40, 1, 0)
	prev.Position = UDim2.new(0, 0, 0, 0)
	prev.BackgroundColor3 = ROW
	prev.BorderSizePixel = 0
	prev.AutoButtonColor = false
	prev.Font = Enum.Font.GothamBold
	prev.Text = "<"
	prev.TextSize = 18
	prev.TextColor3 = TEXT
	prev.Parent = row
	corner(prev, 8)
	hoverable(prev, ROW, ROW_HOVER)

	-- Named `forward` rather than the obvious `next`, which is a global iterator function this
	-- file would otherwise be shadowing for the rest of the scope.
	local forward = prev:Clone()
	forward.Text = ">"
	forward.Position = UDim2.new(1, -40, 0, 0)
	forward.Parent = row
	hoverable(forward, ROW, ROW_HOVER)

	local middle = Instance.new("Frame")
	middle.Size = UDim2.new(1, -92, 1, 0)
	middle.Position = UDim2.new(0, 46, 0, 0)
	middle.BackgroundColor3 = ROW
	middle.BorderSizePixel = 0
	middle.Parent = row
	corner(middle, 8)

	return row, prev, forward, middle
end

-- ---------------------------------------------------------------------------

-- Built into a frame the lobby owns rather than a ScreenGui of its own.
--
-- That is the whole architectural difference from the version this replaces, and it is what
-- makes Back cheap: the page is a sibling of the slot list inside one column, so switching
-- between them is two `Visible` writes and neither page has to be torn down or rebuilt. A
-- second ScreenGui would have put this card *over* the lobby instead of *in* it, and the
-- avatar standing in the right two-thirds would have been behind a backdrop.
function SetupCard.new(parent: GuiObject): SetupCardHandle
	local page = Instance.new("Frame")
	page.Name = "CreatePage"
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.Visible = false
	page.Parent = parent

	local backButton = Instance.new("TextButton")
	backButton.Name = "Back"
	backButton.Size = UDim2.new(0, 96, 0, 26)
	backButton.Position = UDim2.new(0, 0, 0, 0)
	backButton.BackgroundTransparency = 1
	backButton.AutoButtonColor = false
	backButton.Font = Enum.Font.GothamMedium
	backButton.Text = "< Back"
	backButton.TextSize = 14
	backButton.TextColor3 = MUTED
	backButton.TextXAlignment = Enum.TextXAlignment.Left
	backButton.Parent = page

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.new(1, 0, 1, -36)
	card.Position = UDim2.new(0, 0, 0, 36)
	card.BackgroundColor3 = CARD
	card.BorderSizePixel = 0
	card.Parent = page
	corner(card, 14)
	stroke(card, EDGE, 0.4)
	-- Lit from the top, like the slot cards this page replaces in the column. A flat panel next
	-- to shaded rows is the seam these two files exist to not have.
	gradient(card, Color3.new(1, 1, 1), Color3.fromRGB(196, 196, 208))
	pad(card, 18, 18, 16, 18)

	local cardLayout = list(card, 10)
	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder

	-- Header ----------------------------------------------------------------
	local title = label(card, 1, "A NEW LIFE", 22, TEXT)
	title.Font = Enum.Font.GothamBold
	title.Size = UDim2.new(1, 0, 0, 28)

	-- The same short accent rule that sits under AGES on the other page, for the same reason:
	-- it is the mark that says the thing above it is a heading and not the first row of the
	-- form. Laid out by the list rather than positioned, so it moves with the title.
	local titleRule = Instance.new("Frame")
	titleRule.Name = "TitleRule"
	titleRule.LayoutOrder = 2
	titleRule.Size = UDim2.new(0, 56, 0, 2)
	titleRule.BackgroundColor3 = ACCENT
	titleRule.BorderSizePixel = 0
	titleRule.Parent = card
	corner(titleRule, 1)
	local ruleFade = Instance.new("UIGradient")
	ruleFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	ruleFade.Parent = titleRule

	local subtitleLabel = label(card, 3, "", 13, MUTED)
	subtitleLabel.Size = UDim2.new(1, 0, 0, 18)

	-- Body ------------------------------------------------------------------
	-- A scroller so the card survives a short screen. `AutomaticCanvasSize` means nothing in
	-- here has to know the total height, which matters because the era blurb wraps to a
	-- different number of lines per era.
	local body = Instance.new("ScrollingFrame")
	body.LayoutOrder = 4
	-- The fixed rows above and below it, plus the list's padding between them. Grew by the
	-- height of the accent rule and one more gap when that rule was added -- this number is the
	-- one thing on the card that has to be recounted whenever a sibling is added or removed.
	body.Size = UDim2.new(1, 0, 1, -152)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 3
	body.ScrollBarImageColor3 = EDGE
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.Parent = card
	list(body, 8)
	pad(body, 0, 8, 8, 0)

	-- Gender ----------------------------------------------------------------
	heading(body, 10, "You are")

	local genderRow = Instance.new("Frame")
	genderRow.LayoutOrder = 11
	genderRow.Size = UDim2.new(1, 0, 0, 44)
	genderRow.BackgroundTransparency = 1
	genderRow.Parent = body

	local maleButton = Instance.new("TextButton")
	maleButton.Size = UDim2.new(0.5, -5, 1, 0)
	maleButton.BackgroundColor3 = ROW
	maleButton.BorderSizePixel = 0
	maleButton.AutoButtonColor = false
	maleButton.Font = Enum.Font.GothamMedium
	maleButton.Text = "Male"
	maleButton.TextSize = 15
	maleButton.TextColor3 = TEXT
	maleButton.Parent = genderRow
	corner(maleButton, 8)

	local femaleButton = maleButton:Clone()
	femaleButton.Text = "Female"
	femaleButton.Position = UDim2.new(0.5, 5, 0, 0)
	femaleButton.Parent = genderRow

	-- Name ------------------------------------------------------------------
	heading(body, 20, "Called")

	local nameRow = Instance.new("Frame")
	nameRow.LayoutOrder = 21
	nameRow.Size = UDim2.new(1, 0, 0, 42)
	nameRow.BackgroundTransparency = 1
	nameRow.Parent = body

	local firstBox = Instance.new("TextBox")
	firstBox.Size = UDim2.new(0.5, -5, 1, 0)
	firstBox.BackgroundColor3 = ROW
	firstBox.BorderSizePixel = 0
	firstBox.Font = Enum.Font.Gotham
	firstBox.PlaceholderText = "First name"
	firstBox.PlaceholderColor3 = MUTED
	firstBox.Text = ""
	firstBox.TextSize = 15
	firstBox.TextColor3 = TEXT
	firstBox.ClearTextOnFocus = false
	firstBox.Parent = nameRow
	corner(firstBox, 8)

	local lastBox = firstBox:Clone()
	lastBox.PlaceholderText = "Last name"
	lastBox.Position = UDim2.new(0.5, 5, 0, 0)
	lastBox.Parent = nameRow

	local shuffleButton = makeButton(body, 22, "Shuffle a name", 32)
	shuffleButton.Font = Enum.Font.Gotham
	shuffleButton.TextSize = 13
	shuffleButton.TextColor3 = ACCENT

	-- Country ---------------------------------------------------------------
	heading(body, 30, "From")

	local _countryRow, countryPrev, countryNext, countryMiddle = makeStepper(body, 31, 44)
	local countryLabel = Instance.new("TextLabel")
	countryLabel.Size = UDim2.new(1, -16, 1, 0)
	countryLabel.Position = UDim2.new(0, 8, 0, 0)
	countryLabel.BackgroundTransparency = 1
	countryLabel.Font = Enum.Font.GothamMedium
	countryLabel.Text = ""
	countryLabel.TextSize = 15
	countryLabel.TextColor3 = TEXT
	countryLabel.TextTruncate = Enum.TextTruncate.AtEnd
	countryLabel.Parent = countryMiddle

	local countryNote = label(body, 32, "Where you're from decides what you're called.", 12, MUTED)
	countryNote.Size = UDim2.new(1, 0, 0, 16)

	-- Stats -----------------------------------------------------------------
	heading(body, 40, "Born with")

	local pointsLabel = label(body, 41, "", 12, ACCENT)
	pointsLabel.Size = UDim2.new(1, 0, 0, 16)

	-- The trade, said out loud, because a mechanic nobody finds is not a mechanic. Without
	-- this line the minus buttons read as a mistake to be avoided rather than as the other
	-- half of the pool, and the interesting decision here -- being deliberately bad at
	-- something in order to be genuinely good at something else -- never gets made.
	--
	-- Worded off no particular number. Health happens to start full today, so its plus is
	-- always dead and its minus is always live; saying that in so many words would be copy
	-- that quietly starts lying the day Config.Stats.Starting changes.
	local statNote = label(
		body,
		42,
		"Take points out of one to put them into another. A stat that's already full has nothing left to gain.",
		12,
		MUTED
	)
	statNote.Size = UDim2.new(1, 0, 0, 44)
	statNote.TextWrapped = true
	statNote.TextYAlignment = Enum.TextYAlignment.Top

	local statRows: { [string]: StatRow } = {}
	for index, statName in STAT_ORDER do
		local row = Instance.new("Frame")
		row.LayoutOrder = 42 + index
		row.Size = UDim2.new(1, 0, 0, 42)
		row.BackgroundColor3 = ROW
		row.BorderSizePixel = 0
		row.Parent = body
		corner(row, 8)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0, 100, 0, 18)
		nameLabel.Position = UDim2.new(0, 12, 0, 5)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamMedium
		nameLabel.Text = STAT_LABELS[statName] or statName
		nameLabel.TextSize = 14
		nameLabel.TextColor3 = TEXT
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = row

		-- The bar is under the name rather than beside it, so the four of them read as a single
		-- shape the player can compare at a glance. Reading four numbers is work; seeing that
		-- one bar is short is not.
		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, -160, 0, 6)
		track.Position = UDim2.new(0, 12, 0, 28)
		track.BackgroundColor3 = Color3.fromRGB(52, 52, 60)
		track.BorderSizePixel = 0
		track.Parent = row
		corner(track, 3)

		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.BackgroundColor3 = ACCENT
		fill.BorderSizePixel = 0
		fill.Parent = track
		corner(fill, 3)

		local deltaLabel = Instance.new("TextLabel")
		deltaLabel.Size = UDim2.new(0, 60, 0, 18)
		deltaLabel.Position = UDim2.new(0, 112, 0, 5)
		deltaLabel.BackgroundTransparency = 1
		deltaLabel.Font = Enum.Font.Gotham
		deltaLabel.Text = ""
		deltaLabel.TextSize = 12
		deltaLabel.TextColor3 = ACCENT
		deltaLabel.TextXAlignment = Enum.TextXAlignment.Left
		deltaLabel.Parent = row

		local minus = Instance.new("TextButton")
		minus.Size = UDim2.new(0, 30, 0, 30)
		minus.Position = UDim2.new(1, -108, 0, 6)
		minus.BackgroundColor3 = ROW_HOVER
		minus.BorderSizePixel = 0
		minus.AutoButtonColor = false
		minus.Font = Enum.Font.GothamBold
		minus.Text = "-"
		minus.TextSize = 18
		minus.TextColor3 = TEXT
		minus.Parent = row
		corner(minus, 6)

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Size = UDim2.new(0, 40, 0, 30)
		valueLabel.Position = UDim2.new(1, -74, 0, 6)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Font = Enum.Font.GothamBold
		valueLabel.Text = ""
		valueLabel.TextSize = 15
		valueLabel.TextColor3 = TEXT
		valueLabel.Parent = row

		local plus = minus:Clone()
		plus.Text = "+"
		plus.Position = UDim2.new(1, -36, 0, 6)
		plus.Parent = row

		statRows[statName] = {
			valueLabel = valueLabel,
			deltaLabel = deltaLabel,
			fill = fill,
			minus = minus,
			plus = plus,
		}
	end

	-- Era -------------------------------------------------------------------
	heading(body, 50, "Living in")

	local _eraRow, eraPrev, eraNext, eraMiddle = makeStepper(body, 51, 44)
	local eraLabel = Instance.new("TextLabel")
	eraLabel.Size = UDim2.new(1, -104, 1, 0)
	eraLabel.Position = UDim2.new(0, 8, 0, 0)
	eraLabel.BackgroundTransparency = 1
	eraLabel.Font = Enum.Font.GothamMedium
	eraLabel.Text = ""
	eraLabel.TextSize = 15
	eraLabel.TextColor3 = TEXT
	eraLabel.TextTruncate = Enum.TextTruncate.AtEnd
	eraLabel.Parent = eraMiddle

	local eraChip = Instance.new("TextLabel")
	eraChip.AnchorPoint = Vector2.new(1, 0.5)
	eraChip.Position = UDim2.new(1, -8, 0.5, 0)
	eraChip.Size = UDim2.new(0, 86, 0, 20)
	eraChip.BackgroundColor3 = Color3.fromRGB(58, 50, 38)
	eraChip.BorderSizePixel = 0
	eraChip.Font = Enum.Font.GothamBold
	eraChip.Text = "COMING SOON"
	eraChip.TextSize = 10
	eraChip.TextColor3 = ACCENT
	eraChip.Visible = false
	eraChip.Parent = eraMiddle
	corner(eraChip, 4)

	local eraBlurb = label(body, 52, "", 12, MUTED)
	eraBlurb.Size = UDim2.new(1, 0, 0, 44)
	eraBlurb.TextWrapped = true
	eraBlurb.TextYAlignment = Enum.TextYAlignment.Top

	-- Perk --------------------------------------------------------------------
	-- The same stepper widget as country and era, because it is the same question a third
	-- time: pick one of a short list. "None" is always the first stop rather than the picker
	-- opening on whatever was rolled last spin -- spending a perk is the exception, not the
	-- default, and a card that opened pre-armed would spend one on a player who never meant to.
	heading(body, 60, "Spend a perk")

	local _perkRow, perkPrev, perkNext, perkMiddle = makeStepper(body, 61, 44)
	local perkLabel = Instance.new("TextLabel")
	perkLabel.Size = UDim2.new(1, -16, 1, 0)
	perkLabel.Position = UDim2.new(0, 8, 0, 0)
	perkLabel.BackgroundTransparency = 1
	perkLabel.Font = Enum.Font.GothamMedium
	perkLabel.Text = "None"
	perkLabel.TextSize = 15
	perkLabel.TextColor3 = TEXT
	perkLabel.TextTruncate = Enum.TextTruncate.AtEnd
	perkLabel.Parent = perkMiddle

	local perkBlurb = label(body, 62, "", 12, MUTED)
	perkBlurb.Size = UDim2.new(1, 0, 0, 32)
	perkBlurb.TextWrapped = true
	perkBlurb.TextYAlignment = Enum.TextYAlignment.Top

	-- Footer ----------------------------------------------------------------
	-- `label` already sets the LayoutOrder from its second argument; the line that set it a
	-- second time here was doing nothing and is gone.
	local statusLabel = label(card, 5, "", 12, WARN)
	statusLabel.Size = UDim2.new(1, 0, 0, 30)
	statusLabel.TextWrapped = true
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top

	local footer = Instance.new("Frame")
	footer.LayoutOrder = 6
	footer.Size = UDim2.new(1, 0, 0, 46)
	footer.BackgroundTransparency = 1
	footer.Parent = card

	local surpriseButton = Instance.new("TextButton")
	surpriseButton.Size = UDim2.new(0.36, -5, 1, 0)
	surpriseButton.BackgroundColor3 = ROW
	surpriseButton.BorderSizePixel = 0
	surpriseButton.AutoButtonColor = false
	surpriseButton.Font = Enum.Font.GothamMedium
	surpriseButton.Text = "Surprise Me"
	surpriseButton.TextSize = 14
	surpriseButton.TextColor3 = TEXT
	surpriseButton.Parent = footer
	corner(surpriseButton, 10)
	hoverable(surpriseButton, ROW, ROW_HOVER)

	local createButton = Instance.new("TextButton")
	createButton.AnchorPoint = Vector2.new(1, 0)
	createButton.Position = UDim2.new(1, 0, 0, 0)
	createButton.Size = UDim2.new(0.64, -5, 1, 0)
	createButton.BackgroundColor3 = ACCENT
	createButton.BorderSizePixel = 0
	createButton.AutoButtonColor = false
	createButton.Font = Enum.Font.GothamBold
	createButton.Text = "Create Life"
	createButton.TextSize = 16
	createButton.TextColor3 = INK
	createButton.Parent = footer
	corner(createButton, 10)

	local self = setmetatable({
		page = page,
		card = card,
		subtitleLabel = subtitleLabel,
		maleButton = maleButton,
		femaleButton = femaleButton,
		firstBox = firstBox,
		lastBox = lastBox,
		countryLabel = countryLabel,
		eraLabel = eraLabel,
		eraBlurb = eraBlurb,
		eraChip = eraChip,
		pointsLabel = pointsLabel,
		statRows = statRows,
		perkPrev = perkPrev,
		perkNext = perkNext,
		perkLabel = perkLabel,
		perkBlurb = perkBlurb,
		statusLabel = statusLabel,
		createButton = createButton,
		surpriseButton = surpriseButton,
		backButton = backButton,

		options = nil,
		slot = 1,
		gender = "female" :: Gender,
		countryIndex = 1,
		eraIndex = 1,
		deltas = {},
		suggestedFirst = "",
		suggestedLast = "",
		perkCatalog = {},
		perkChoices = {},
		perkCounts = {},
		perkIndex = 0,
		onCreate = nil,
		onBack = nil,
		waiting = false,
	}, SetupCard)

	-- Wiring. Every one of these mutates state and calls Render; none of them touches a
	-- property directly, which is what keeps `Render` the only description of the page.
	maleButton.Activated:Connect(function()
		self:SetGender("male")
	end)
	femaleButton.Activated:Connect(function()
		self:SetGender("female")
	end)
	shuffleButton.Activated:Connect(function()
		self:RollName()
	end)
	countryPrev.Activated:Connect(function()
		self:StepCountry(-1)
	end)
	countryNext.Activated:Connect(function()
		self:StepCountry(1)
	end)
	eraPrev.Activated:Connect(function()
		self:StepEra(-1)
	end)
	eraNext.Activated:Connect(function()
		self:StepEra(1)
	end)
	perkPrev.Activated:Connect(function()
		self:StepPerk(-1)
	end)
	perkNext.Activated:Connect(function()
		self:StepPerk(1)
	end)
	surpriseButton.Activated:Connect(function()
		self:Surprise()
	end)
	createButton.Activated:Connect(function()
		self:Send()
	end)
	backButton.Activated:Connect(function()
		self:Back()
	end)
	backButton.MouseEnter:Connect(function()
		backButton.TextColor3 = TEXT
	end)
	backButton.MouseLeave:Connect(function()
		backButton.TextColor3 = MUTED
	end)

	for _, statName in STAT_ORDER do
		local row = statRows[statName]
		row.minus.Activated:Connect(function()
			self:StepStat(statName, -1)
		end)
		row.plus.Activated:Connect(function()
			self:StepStat(statName, 1)
		end)
	end

	-- Clamps to the server's limit at the keystroke rather than at the refusal. The box
	-- stopping is a much better explanation of a length limit than a sentence about one.
	--
	-- Cut on a character boundary rather than a byte one. `utf8.len` counts codepoints and
	-- `string.sub` counts bytes, so the obvious pairing of the two would slice a multi-byte
	-- letter in half and hand the server a string that is not text at all.
	--
	-- Nothing here records "the player typed" -- see the handle's suggested* fields for why a
	-- flag set here cannot be trusted.
	for _, box in { firstBox, lastBox } do
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local options = self.options
			if options == nil then
				return
			end
			-- Redrawn on every keystroke, because the Create button's own label reports whether
			-- there is a name in the boxes yet and a button that says "Enter a name" over a
			-- filled-in name is a button nobody trusts again.
			self:Render()
			local length = utf8.len(box.Text)
			if length == nil or length <= options.maxNameLength then
				return
			end
			local cut = utf8.offset(box.Text, options.maxNameLength + 1)
			if cut ~= nil then
				box.Text = string.sub(box.Text, 1, cut - 1)
			end
		end)
	end

	return self
end

function SetupCard.OnCreate(self: SetupCardHandle, callback: (slot: number, request: SetupRequest) -> ())
	self.onCreate = callback
end

function SetupCard.OnBack(self: SetupCardHandle, callback: () -> ())
	self.onBack = callback
end

function SetupCard.IsOpen(self: SetupCardHandle): boolean
	return self.page.Visible
end

local function currentCountry(self: SetupCardHandle): Country?
	local options = self.options
	if options == nil then
		return nil
	end
	return options.countries[self.countryIndex]
end

local function currentEra(self: SetupCardHandle): Era?
	local options = self.options
	if options == nil then
		return nil
	end
	return options.eras[self.eraIndex]
end

-- `nil` for index 0 -- "no perk", which is a real, always-first choice rather than a hole in
-- the list. Everything downstream (`Render`, `Send`) reads this instead of touching
-- `perkChoices`/`perkIndex` directly, the same indirection `currentCountry`/`currentEra` give
-- their own indices.
local function currentPerk(self: SetupCardHandle): PerkOffer?
	if self.perkIndex == 0 then
		return nil
	end
	return self.perkChoices[self.perkIndex]
end

-- Whether what is in the boxes is the player's work rather than this card's suggestion.
-- Anything that is not exactly what was last suggested counts as theirs -- including an empty
-- box, which is somebody who cleared it on purpose and has not finished typing.
local function nameIsMine(self: SetupCardHandle): boolean
	return self.firstBox.Text ~= self.suggestedFirst or self.lastBox.Text ~= self.suggestedLast
end

-- How many of the pool are committed. Negative deltas give points *back*, which is the whole
-- mechanic, so this is a plain sum rather than a sum of the positive ones.
local function spent(self: SetupCardHandle): number
	local total = 0
	for _, statName in STAT_ORDER do
		total += self.deltas[statName] or 0
	end
	return total
end

function SetupCard.SetGender(self: SetupCardHandle, gender: Gender)
	if self.gender == gender then
		return
	end
	self.gender = gender
	-- A suggested name follows the gender it was suggested for; a typed one does not.
	if not nameIsMine(self) then
		self:RollName()
	end
	self:Render()
end

function SetupCard.StepCountry(self: SetupCardHandle, direction: number)
	local options = self.options
	if options == nil then
		return
	end
	local count = #options.countries
	self.countryIndex = ((self.countryIndex - 1 + direction) % count) + 1
	if not nameIsMine(self) then
		self:RollName()
	end
	self:Render()
end

function SetupCard.StepEra(self: SetupCardHandle, direction: number)
	local options = self.options
	if options == nil then
		return
	end
	local count = #options.eras
	self.eraIndex = ((self.eraIndex - 1 + direction) % count) + 1
	self:Render()
end

-- Cycles over "None" plus every perk owned, wrapping like the other two steppers. A no-op
-- when nothing is owned -- `Render` disables the buttons for exactly that case, so this
-- would only ever run with a single choice, and `(0 + direction) % 1` already lands back on
-- 0 without any special-casing here.
function SetupCard.StepPerk(self: SetupCardHandle, direction: number)
	local count = #self.perkChoices
	self.perkIndex = (self.perkIndex + direction) % (count + 1)
	self:Render()
end

-- The perk catalog and owned counts, handed down from LobbyUI's `SpinsUpdated` listener.
--
-- Recomputes `perkChoices` -- the owned subset, in catalog order -- rather than filtering on
-- every `Render`, since `Render` runs on every keystroke in the name boxes and the catalog is
-- ten records at most; still cheaper to do the work once here than ten times a second while
-- somebody types their name.
--
-- The current selection survives this by id rather than by index, because a purchase or a
-- spin landing while the card is open must not silently swap what "the perk I picked" points
-- at. If that id is no longer owned -- spent by another window, or this build's catalog
-- dropped it -- the pick falls back to "None" rather than pointing at a stale entry.
function SetupCard.SetPerks(self: SetupCardHandle, catalog: { PerkOffer }, owned: { OwnedPerk })
	local selectedId: string? = nil
	local previous = currentPerk(self)
	if previous ~= nil then
		selectedId = previous.id
	end

	local counts: { [string]: number } = {}
	for _, entry in owned do
		counts[entry.id] = entry.count
	end

	local choices: { PerkOffer } = {}
	for _, perk in catalog do
		if (counts[perk.id] or 0) > 0 then
			table.insert(choices, perk)
		end
	end

	self.perkCatalog = catalog
	self.perkCounts = counts
	self.perkChoices = choices

	self.perkIndex = 0
	if selectedId ~= nil then
		for index, perk in choices do
			if perk.id == selectedId then
				self.perkIndex = index
				break
			end
		end
	end

	if self.options ~= nil then
		self:Render()
	end
end

-- Drawn from the same lists the server would use, because the server sent them. So the
-- shuffle is instant and offline -- no round trip to find out what you might be called.
function SetupCard.RollName(self: SetupCardHandle)
	local country = currentCountry(self)
	if country == nil then
		return
	end
	local firstNames = if self.gender == "male" then country.firstNamesMale else country.firstNamesFemale
	local first = firstNames[math.random(#firstNames)]
	local last = country.lastNames[math.random(#country.lastNames)]
	-- Recorded as well as written, so that this counts as the card's suggestion until the
	-- player changes one character of it.
	self.suggestedFirst = first
	self.suggestedLast = last
	self.firstBox.Text = first
	self.lastBox.Text = last
	self:Render()
end

function SetupCard.StepStat(self: SetupCardHandle, statName: StatName, direction: number)
	local options = self.options
	if options == nil then
		return
	end
	local current = self.deltas[statName] or 0
	local wanted = current + direction
	if wanted > options.maxPerStat or wanted < options.minPerStat then
		return
	end
	-- Going up has to fit the budget; going down always may, since it is what *makes* budget.
	-- Without the direction check, a player who overspent could not climb back out of it.
	if direction > 0 and spent(self) + 1 > options.statPoints then
		return
	end
	local starting = (options.startingStats :: any)[statName] :: number
	local resulting = starting + wanted
	if resulting > Config.Stats.Max or resulting < Config.Stats.Min + 1 then
		-- Refused rather than clamped. A + that silently does nothing is a broken button; a +
		-- that is *drawn* as unavailable, which Render does, is an explanation.
		return
	end
	self.deltas[statName] = wanted
	self:Render()
end

-- A whole life, rolled. For the player who has done this eleven times and wants the game
-- rather than the form -- and, honestly, for the player who does not want to decide.
function SetupCard.Surprise(self: SetupCardHandle)
	local options = self.options
	if options == nil then
		return
	end
	self.gender = if math.random() < 0.5 then "female" else "male"
	self.countryIndex = math.random(#options.countries)

	-- Eras are picked from the *available* ones only. Rolling a locked era would be the game
	-- handing the player a dead end it just built the greying-out to prevent.
	local pickable: { number } = {}
	for index, era in options.eras do
		if era.available then
			table.insert(pickable, index)
		end
	end
	if #pickable > 0 then
		self.eraIndex = pickable[math.random(#pickable)]
	end

	-- Spends the whole pool, one point at a time, on whatever will still take one. A single
	-- random split could land entirely on health, which is capped and would eat the points
	-- silently.
	self.deltas = {}
	for _ = 1, options.statPoints do
		local candidates: { StatName } = {}
		for _, statName in STAT_ORDER do
			local delta = (self.deltas[statName] or 0) + 1
			local starting = (options.startingStats :: any)[statName] :: number
			if delta <= options.maxPerStat and starting + delta <= Config.Stats.Max then
				table.insert(candidates, statName)
			end
		end
		if #candidates == 0 then
			break
		end
		local pick = candidates[math.random(#candidates)]
		self.deltas[pick] = (self.deltas[pick] or 0) + 1
	end

	self:RollName()
	self:Render()
end

-- Everything the page looks like, for the state it is in. The only function in this file
-- that writes a property after construction.
function SetupCard.Render(self: SetupCardHandle)
	local options = self.options
	if options == nil then
		return
	end

	-- Names the slot, which the version in the game place had no need to: there was only ever
	-- one life to be making. Here the same card fills three different cards on the screen
	-- behind it, and a player who pressed Create on the wrong one should find that out now
	-- rather than after the life exists.
	self.subtitleLabel.Text = if options.lifeNumber <= 1
		then `Slot {self.slot}. Choose who you'll be.`
		else `Slot {self.slot} -- life {options.lifeNumber}. Choose who you'll be this time.`

	self.maleButton.BackgroundColor3 = if self.gender == "male" then ACCENT else ROW
	self.maleButton.TextColor3 = if self.gender == "male" then INK else TEXT
	self.femaleButton.BackgroundColor3 = if self.gender == "female" then ACCENT else ROW
	self.femaleButton.TextColor3 = if self.gender == "female" then INK else TEXT

	local country = currentCountry(self)
	self.countryLabel.Text = if country ~= nil then country.name else "--"

	local era = currentEra(self)
	local eraAvailable = era ~= nil and era.available
	self.eraLabel.Text = if era ~= nil then era.name else "--"
	self.eraLabel.TextColor3 = if eraAvailable then TEXT else MUTED
	self.eraBlurb.Text = if era ~= nil then era.blurb else ""
	self.eraBlurb.TextColor3 = if eraAvailable then MUTED else Color3.fromRGB(112, 108, 118)
	self.eraChip.Visible = era ~= nil and not era.available

	-- Same "greyed and unclickable" treatment as the stat steppers -- see below -- rather than
	-- hidden, so a player with nothing owned yet still sees the row exist and learns where a
	-- perk would go once they have one.
	local perk = currentPerk(self)
	local perkCount = #self.perkChoices
	local perkPickable = perkCount > 0
	self.perkLabel.Text = if perk ~= nil then perk.name else "None"
	self.perkLabel.TextColor3 = if perkPickable then TEXT else MUTED
	self.perkBlurb.Text = if perk ~= nil
		then `{perk.blurb} ({string.format("%.1f", perk.odds * 100)}% odds, {string.upper(perk.rarity)})`
		elseif perkPickable then "Spent on this life only -- step through to pick one you own."
		else "No perks yet -- spins in the lobby menu can land you one."
	self.perkPrev.Active = perkPickable
	self.perkNext.Active = perkPickable
	self.perkPrev.TextColor3 = if perkPickable then TEXT else DISABLED
	self.perkNext.TextColor3 = if perkPickable then TEXT else DISABLED
	self.perkPrev.BackgroundColor3 = if perkPickable then ROW else ROW_LOCKED
	self.perkNext.BackgroundColor3 = if perkPickable then ROW else ROW_LOCKED

	local left = options.statPoints - spent(self)
	self.pointsLabel.Text = if left == 1 then "1 point left to spend" else `{left} points left to spend`
	self.pointsLabel.TextColor3 = if left == 0 then MUTED else ACCENT

	for _, statName in STAT_ORDER do
		local row = self.statRows[statName]
		local delta = self.deltas[statName] or 0
		local starting = (options.startingStats :: any)[statName] :: number
		local value = starting + delta

		row.valueLabel.Text = tostring(value)
		row.deltaLabel.Text = if delta > 0 then `+{delta}` elseif delta < 0 then tostring(delta) else ""
		row.deltaLabel.TextColor3 = if delta < 0 then WARN else ACCENT
		row.fill.Size = UDim2.new(math.clamp(value / Config.Stats.Max, 0, 1), 0, 1, 0)

		-- The buttons are drawn as unavailable for exactly the reasons StepStat refuses, which
		-- is the point of both existing: the rule is enforced in one place and explained in
		-- the other.
		local canAdd = delta < options.maxPerStat and left > 0 and value < Config.Stats.Max
		local canTake = delta > options.minPerStat and value > Config.Stats.Min + 1
		row.plus.Active = canAdd
		row.plus.TextColor3 = if canAdd then TEXT else DISABLED
		row.plus.BackgroundColor3 = if canAdd then ROW_HOVER else ROW_LOCKED
		row.minus.Active = canTake
		row.minus.TextColor3 = if canTake then TEXT else DISABLED
		row.minus.BackgroundColor3 = if canTake then ROW_HOVER else ROW_LOCKED
	end

	local hasName = self.firstBox.Text ~= "" and self.lastBox.Text ~= ""
	local ready = hasName and eraAvailable and not self.waiting
	self.createButton.Active = ready
	self.createButton.BackgroundColor3 = if ready then ACCENT else Color3.fromRGB(70, 68, 62)
	self.createButton.TextColor3 = if ready then INK else Color3.fromRGB(140, 136, 130)
	-- The button says *why* it cannot be pressed rather than sitting there greyed and mute. An
	-- unexplained disabled button is the single most common way a menu loses somebody.
	self.createButton.Text = if self.waiting
		then "Creating..."
		elseif not hasName then "Enter a name"
		elseif not eraAvailable then "Pick a playable era"
		elseif left > 0 then `Create Life ({left} unspent)`
		else "Create Life"

	self.surpriseButton.Active = not self.waiting
	-- Back is closed while a create is in flight, on the same argument as the Create button
	-- locking: the answer is on the wire and leaving the page would mean the life appears on a
	-- screen the player has already walked away from.
	self.backButton.Active = not self.waiting
	self.backButton.TextTransparency = if self.waiting then 0.6 else 0
end

-- Open the page on a named slot, with a fresh person suggested.
--
-- Everything is reset rather than carried over, including from a card the player backed out
-- of thirty seconds ago. Two slots filled in a row should not start the second one holding
-- the first one's stat spread: that is the previous life leaking into the next one, which is
-- exactly the thing slots exist to prevent.
function SetupCard.Show(self: SetupCardHandle, options: SetupOptions, slot: number)
	self.options = options
	self.slot = slot
	self.waiting = false
	self.statusLabel.Text = ""
	self.deltas = {}
	self.suggestedFirst = ""
	self.suggestedLast = ""
	-- Opens on "None" every time, even though `perkChoices` itself is carried over -- what a
	-- player owns does not reset between cards, but which one they meant to spend on *this*
	-- life should never be assumed from the last one they opened.
	self.perkIndex = 0

	-- Falls back to the first entry if the server named a country this build has never heard
	-- of, which cannot happen while both ends read the same list and is exactly the kind of
	-- thing that stops being true the day they don't.
	self.countryIndex = 1
	for index, country in options.countries do
		if country.id == options.defaultCountryId then
			self.countryIndex = index
			break
		end
	end

	-- Opens on the first *playable* era, so the card never opens on a row that cannot be used.
	-- Config puts the available one first today; this survives it not doing so.
	self.eraIndex = 1
	for index, era in options.eras do
		if era.available then
			self.eraIndex = index
			break
		end
	end

	self.gender = if math.random() < 0.5 then "female" else "male"
	self:RollName()
	self:Render()

	self.page.Visible = true
	self.card.Position = UDim2.new(0, 0, 0, 36 + RISE_PIXELS)
	TweenService:Create(self.card, RISE, { Position = UDim2.new(0, 0, 0, 36) }):Play()
end

function SetupCard.Hide(self: SetupCardHandle)
	self.waiting = false
	self.page.Visible = false
end

function SetupCard.Back(self: SetupCardHandle)
	if self.waiting or not self.backButton.Active then
		return
	end
	local callback = self.onBack
	if callback ~= nil then
		callback()
	end
end

-- The server said no. Re-enables the card so the player can fix it, which is the entire
-- reason a refusal is a message and not a silence.
function SetupCard.ShowRefusal(self: SetupCardHandle, reason: string)
	if not self:IsOpen() then
		return
	end
	self.waiting = false
	self.statusLabel.Text = reason
	self:Render()
end

function SetupCard.Send(self: SetupCardHandle)
	local options = self.options
	local callback = self.onCreate
	if options == nil or callback == nil or self.waiting then
		return
	end
	if not self.createButton.Active then
		return
	end
	local country = currentCountry(self)
	local era = currentEra(self)
	if country == nil or era == nil then
		return
	end

	-- Locked immediately, exactly like ChoicePanel locks its choices on the way out: the
	-- answer is in flight and a second press would be a second life.
	self.waiting = true
	self.statusLabel.Text = ""
	self:Render()

	local perk = currentPerk(self)
	callback(self.slot, {
		gender = self.gender,
		firstName = self.firstBox.Text,
		lastName = self.lastBox.Text,
		countryId = country.id,
		eraId = era.id,
		statDeltas = self.deltas,
	}, if perk ~= nil then perk.id else nil)
end

return SetupCard
