--!strict
-- The menu: a rail of tiles down the left edge, and a panel that opens beside it.
--
-- **Why a rail and not a keybind.** Every pane behind this answers a question the
-- player has while standing in the street -- what work is going, who is worth calling,
-- what am I actually good at -- and a question you have in the street wants something
-- to click, not a shortcut to have learned. Tab opens it too, for the players who will
-- find that, but the rail is the surface that makes the panes discoverable at all.
--
-- **Why the panel is not full-screen.** The map sheet is the full-screen surface in
-- this game. Two things that take over the whole display is one too many, and the map
-- would stop feeling like the one that does.
--
-- **What is not here.** No decisions. Every pane draws state the server pushed, and the
-- controls on them -- the gang colours switch, a settings toggle, the redeem box --
-- report out through a callback rather than flipping their own state. This module holds
-- the pushes and a selection, and nothing else.
--
-- The panes deliberately share one row shape: a title, a right-aligned figure, and a
-- caption underneath. Seven lists that looked like seven different games would make the
-- panel read as seven features bolted together, which is what it must not be.
--
-- **On the look, because this file was rebuilt for it once already.** The first version
-- was correct and looked like a debug build: single capital letters for icons, a cold
-- blue-grey that shared nothing with the lobby the player had just come from, and not one
-- moving pixel anywhere. Three things fixed that, and they are the three worth protecting:
--
--   * **The colours are the lobby's colours.** `Config.UI.Palette` is the same warm
--     near-black and the same gold a player met on the slot screen a minute earlier.
--     A menu in a different key from the screen before it reads as a different product.
--   * **Every icon is drawn, never uploaded.** See `MenuIcons`. An asset that has not
--     cleared moderation renders as nothing, and a rail of blank squares is the worst
--     kind of failure -- silent, and on the surface that has to be legible first.
--   * **Three curves and nothing else.** In on `Back.Out`, out on `Quad.In` and faster,
--     transitions on `Quint.Out`. Everything under a third of a second. Most UI that
--     feels cheap is the right curves played too slowly.
--
-- **Nothing here is gated on an animation finishing.** The panel is clickable on the
-- frame it appears, a rail tile acknowledges a press before the pane behind it has built
-- a single row, and every tween moves pixels rather than permission. A menu that makes
-- the player wait for its own entrance has decided its animation matters more than the
-- press it is delaying.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
-- The same formatter the HUD balance and every price tag in the game uses. Money that
-- is written one way on the shop marker and another way in the menu is money the player
-- has to stop and convert, which is the one thing a balance must never make them do.
local Money = require(ReplicatedStorage:WaitForChild("Money"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local MenuIcons = require(script.Parent.MenuIcons)

type JobPostState = Types.JobPostState
type ShiftState = Types.ShiftState
type PersonRosterEntry = Types.PersonRosterEntry
type GangState = Types.GangState
type SkillsState = Types.SkillsState
type BillState = Types.BillState
type SavingsState = Types.SavingsState
type HouseState = Types.HouseState
type SettingsState = Types.SettingsState
type CodesState = Types.CodesState

local MENU = Config.UI.Menu
local MOTION = MENU.Motion
local PALETTE = Config.UI.Palette

-- -------------------------------------------------------------------
-- Type.
--
-- `FontFace` rather than the legacy `Font` property, everywhere. The legacy enum can say
-- "GothamBold" but it cannot say "Gotham at weight 600", so a type ramp built on it has
-- exactly the three weights somebody happened to make enum members for. Named here so
-- that changing the family is one edit rather than sixty.
--
-- `TextScaled` appears nowhere in this file on purpose. It is the fastest way to get text
-- that fits and the surest way to get a list whose rows are each set in a different size,
-- because every label solves for its own box. Fixed sizes, and a `TextTruncate` on
-- anything that can overflow.
-- -------------------------------------------------------------------

local FONT_BOLD = Font.fromEnum(Enum.Font.GothamBold)
local FONT_MEDIUM = Font.fromEnum(Enum.Font.GothamMedium)
local FONT_BODY = Font.fromEnum(Enum.Font.Gotham)

-- -------------------------------------------------------------------
-- Motion. Three curves, defined once.
-- -------------------------------------------------------------------

local ENTER_MOVE = TweenInfo.new(MOTION.EnterSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- Transparency gets `Quint` rather than `Back`, because `Back` overshoots past its target
-- and a transparency that overshoots below zero is a value the engine clamps -- so the
-- last third of the curve would be a tween playing against a property that had already
-- stopped moving.
local ENTER_FADE = TweenInfo.new(MOTION.EnterSeconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local EXIT = TweenInfo.new(MOTION.ExitSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOVER = TweenInfo.new(MOTION.HoverSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BLUR_IN = TweenInfo.new(MOTION.BlurSeconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- -------------------------------------------------------------------
-- Geometry. Pulled out of Config once, because these are read in every row builder and
-- `MENU.RowPixels` written forty times reads as forty separate decisions.
-- -------------------------------------------------------------------

local ROW_HEIGHT = MENU.RowPixels
local ROW_GAP = MENU.RowGapPixels
-- The left inset every line of text in a row shares, and the width reserved on the right
-- for the figure. Fixed rather than fitted, because the figure is the part of a row worth
-- scanning and a title long enough to push it off the edge has taken the row's point away.
local ROW_TEXT_LEFT = 16
local ROW_TEXT_RIGHT = 14
local FIGURE_WIDTH = 116
-- The coloured bar down the left edge of a row, at rest. Named because two places need the
-- same number: `addSpine` draws it and `pressable` grows it away from and back to it.
local SPINE_HEIGHT = ROW_HEIGHT - 18

-- Where the list starts inside the panel, and the breathing room under the last row. Both
-- at module scope because the panel is sized to its contents on every redraw and the sum
-- that does it lives outside the function that builds the panel.
local CONTENT_TOP = MENU.HeaderPixels + MENU.TitleBarPixels + 6
local CONTENT_BOTTOM_PAD = 14
-- The empty-state block: how far under the list's top edge the icon sits, and how much
-- room the icon plus its sentence needs.
local EMPTY_TOP = 26
local EMPTY_HEIGHT = 140

local MenuUI = {}
MenuUI.__index = MenuUI

export type MenuUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		rail: Frame,
		panel: CanvasGroup,
		-- Where the panel rests. Held rather than recomputed, because the entrance starts a
		-- few pixels to the left of it and the exit goes back there -- so three places need
		-- the same number and two of them are not in the function that worked it out.
		panelHome: UDim2,
		backdrop: TextButton,
		blur: BlurEffect,
		titleLabel: TextLabel,
		titleRule: Frame,
		cardName: TextLabel,
		cardLine: TextLabel,
		content: ScrollingFrame,
		emptyHolder: Frame,
		emptyIcon: Frame,
		emptyLabel: TextLabel,
		railButtons: { [string]: TextButton },
		railIcons: { [string]: Frame },
		-- The name-on-hover flags, held so that `paintRail` can decide whether any of them
		-- may show at all. They would otherwise be per-tile closures, and the rule about when
		-- a tip is allowed is a rule about the whole rail -- see `paintRail`.
		railTips: { [string]: Frame },
		railHovered: string?,
		open: boolean,
		-- Which pane is showing. Held across closes so reopening returns the player to
		-- where they were rather than to the top of the rail, which is what a menu you
		-- dip into twenty times a life has to do.
		selected: string,
		-- The selected pane's colour, and the row counter the stagger is measured off.
		-- Both are set by `redraw` immediately before it dispatches, so a pane builder can
		-- ask for a row without also having to be told which pane it is.
		accent: Color3,
		rowIndex: number,
		-- The height the rows just built add up to, accumulated as they are built.
		--
		-- Counted here rather than read back off the `UIListLayout`, because
		-- `AbsoluteContentSize` is only right after the layout has run -- which is the frame
		-- *after* the one that needs the number. A panel that resized itself one frame late
		-- would visibly settle every time a pane was switched.
		contentHeight: number,
		-- Whether the rows about to be built should animate in.
		--
		-- **False on a data push, true on a switch or an open**, and this distinction is the
		-- whole reason it exists. A wage lands every few seconds during a shift; if that
		-- rebuilt the money pane with the full staggered entrance, an open menu would be a
		-- list flickering on a timer. Motion is for a thing the player just did.
		animate: boolean,
		jobs: { JobPostState },
		-- The job the player currently holds, if any -- the same shape the HUD's shift
		-- clock reads, sent here too so the pane can show the one thing a list of
		-- openings cannot: what you already have. Nil exactly when jobId is nil on it.
		currentJob: ShiftState?,
		onQuitJob: (() -> ())?,
		onJobTapped: ((jobId: string) -> ())?,
		-- A row pressed on the Locations pane. Static content -- Config.Locations.List
		-- rather than anything pushed -- so there is no LocationsState to hold here, only
		-- the one callback the row's press needs.
		onLocationTapped: ((id: string) -> ())?,
		roster: { PersonRosterEntry },
		gang: GangState?,
		skills: SkillsState?,
		-- The three halves of the money pane, held separately because they arrive on three
		-- separate remotes from three separate services. Combined into one pushed shape
		-- they would need a fourth service to own the combining, and any of the three
		-- pushing on its own would then have to re-send the other two.
		bill: BillState?,
		savings: SavingsState?,
		house: HouseState?,
		settings: SettingsState?,
		codes: CodesState?,
		-- The last thing the server said about a redeem attempt, and whether it worked.
		-- Held rather than shown-and-forgotten because the pane is rebuilt from scratch on
		-- every push, and a result that lived only in a label would be wiped by the very
		-- `CodesUpdated` that a successful redeem triggers -- so the one message worth
		-- keeping would be the only one nobody ever read.
		codeResult: string,
		codeResultOk: boolean,
		-- What is in the box. Held for the same reason: a redraw destroys the TextBox, and
		-- a player whose typing is erased by an unrelated push has a broken field.
		codeDraft: string,
		onCodeSubmitted: ((code: string) -> ())?,
		onSettingToggled: ((id: string, on: boolean) -> ())?,
		ageYears: number,
		stage: string,
		money: number,
		onColorsToggled: ((boolean) -> ())?,
		onPersonTapped: ((personId: string) -> ())?,
	},
	MenuUI
))

-- -------------------------------------------------------------------
-- The small drawing helpers. Deliberately the same four the lobby's menu is built out
-- of, with the same names, because these two files are one screen as far as a player is
-- concerned and somebody reading them back to back should not have to learn two dialects.
-- -------------------------------------------------------------------

local function corner(parent: GuiObject, radius: number)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = UDim.new(0, radius)
	instance.Parent = parent
end

local function stroke(parent: GuiObject, color: Color3, thickness: number, transparency: number): UIStroke
	local instance = Instance.new("UIStroke")
	instance.Color = color
	instance.Thickness = thickness
	instance.Transparency = transparency
	instance.Parent = parent
	return instance
end

-- A vertical gradient over whatever it is parented to.
--
-- `UIGradient.Color` *multiplies* the object's own colour rather than replacing it, which
-- is the property that makes this usable on the rail tiles: a tile keeps one
-- `BackgroundColor3` that hover and selection tween between, and the gradient shades
-- whatever that happens to be. Written as two absolute colours it would have to be
-- re-authored every time the base moved.
local function gradient(parent: GuiObject, top: number, bottom: number)
	local instance = Instance.new("UIGradient")
	instance.Color = ColorSequence.new(Color3.new(top, top, top), Color3.new(bottom, bottom, bottom))
	instance.Rotation = 90
	instance.Parent = parent
end

-- A hairline. One pixel of `Edge`, used to separate a header from the list under it and
-- nothing else -- a panel ruled into sections by lines is a form, and this is a list.
local function hairline(parent: GuiObject, y: UDim2, inset: number): Frame
	local line = Instance.new("Frame")
	line.Position = y
	line.Size = UDim2.new(1, -inset * 2, 0, 1)
	line.BackgroundColor3 = PALETTE.Edge
	line.BackgroundTransparency = 0.45
	line.BorderSizePixel = 0
	line.ZIndex = 3
	line.Parent = parent
	return line
end

-- A label, because seven panes and a header build about forty of them and the six lines
-- of property-setting were the bulk of this file before it was rebuilt.
local function label(parent: Instance, font: Font, size: number, color: Color3, align: Enum.TextXAlignment): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.FontFace = font
	text.TextSize = size
	text.TextColor3 = color
	text.TextXAlignment = align
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.Text = ""
	text.ZIndex = 3
	text.Parent = parent
	return text
end

-- The rail's colours, keyed once. `Config.UI.Menu.Tabs` is an ordered list because the
-- rail draws top to bottom, and a list is the wrong shape to ask "what colour is the
-- gangs pane" forty times a redraw.
local TAB_COLOR: { [string]: Color3 } = {}
for _, tab in MENU.Tabs do
	TAB_COLOR[tab.id] = tab.color
end

-- -------------------------------------------------------------------
-- Rows.
--
-- **Every row is two frames, and the outer one exists solely so the inner one can move.**
-- A `UIListLayout` owns the `Position` of everything it lays out, so a card that is laid
-- out directly cannot rise on entry or slide under the cursor -- the layout writes over it
-- on the next frame. So the layout gets a slot, the slot never moves, and the card inside
-- it is free. That is the whole reason for the extra Frame, and it is worth one instance
-- per row: without it this file has no motion at all, which is where it started.
-- -------------------------------------------------------------------

local function makeSlot(self: MenuUIHandle, height: number): (Frame, Frame)
	self.rowIndex += 1
	-- Every slot the panel is asked to fit, added up as it is asked for. See
	-- `MenuUIHandle.contentHeight` for why this is counted rather than measured.
	self.contentHeight += height + (if self.rowIndex > 1 then ROW_GAP else 0)

	local slot = Instance.new("Frame")
	slot.Name = `Slot{self.rowIndex}`
	slot.Size = UDim2.new(1, 0, 0, height)
	slot.BackgroundTransparency = 1
	slot.BorderSizePixel = 0
	slot.LayoutOrder = self.rowIndex
	slot.ZIndex = 3
	slot.Parent = self.content

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = PALETTE.Row
	card.BorderSizePixel = 0
	card.ZIndex = 3
	card.Parent = slot

	corner(card, 8)
	gradient(card, 1, 0.86)

	if self.animate then
		-- Capped, so a forty-row relationships list costs the same wait as a ten-row one.
		-- Without the cap the stagger is linear in the row count and the last card of a big
		-- pane lands nearly a second after the first, which stops reading as a list being
		-- dealt and starts reading as a slow menu.
		local step = math.min(self.rowIndex - 1, MOTION.RowStaggerLimit)
		card.Position = UDim2.new(0, 0, 0, MOTION.RowRisePixels)
		TweenService
			:Create(
				card,
				TweenInfo.new(
					MOTION.RowRiseSeconds,
					Enum.EasingStyle.Quint,
					Enum.EasingDirection.Out,
					0,
					false,
					step * MOTION.RowStaggerSeconds
				),
				{ Position = UDim2.new(0, 0, 0, 0) }
			)
			:Play()
	end

	return slot, card
end

-- A coloured spine down the left edge of a row.
--
-- This is where a pane's colour lives once the player is inside it. The rail tile is
-- gone from under the cursor by then and the title is one line at the top, so without the
-- spine a list of jobs and a list of skills are the same grey rectangle -- and the whole
-- point of colouring the tabs was that a player should know which pane they are in from
-- the corner of their eye.
local function addSpine(card: Frame, color: Color3)
	local spine = Instance.new("Frame")
	spine.Name = "Spine"
	spine.AnchorPoint = Vector2.new(0, 0.5)
	spine.Position = UDim2.new(0, 0, 0.5, 0)
	spine.Size = UDim2.new(0, 3, 0, SPINE_HEIGHT)
	spine.BackgroundColor3 = color
	spine.BorderSizePixel = 0
	spine.ZIndex = 4
	spine.Parent = card

	corner(spine, 2)
end

-- One list row: a title on the left, a figure on the right, a caption underneath.
--
-- The figure column is fixed-width and the title is truncated into what is left, which
-- is deliberately the opposite of letting the title push the figure off the edge: a row
-- whose number has scrolled out of view has lost the only part of it that was worth
-- scanning.
local function makeRow(self: MenuUIHandle): (Frame, TextLabel, TextLabel, TextLabel)
	local _, card = makeSlot(self, ROW_HEIGHT)
	addSpine(card, self.accent)

	local title = label(card, FONT_MEDIUM, 15, PALETTE.Text, Enum.TextXAlignment.Left)
	title.Position = UDim2.new(0, ROW_TEXT_LEFT, 0, 9)
	title.Size = UDim2.new(1, -(ROW_TEXT_LEFT + ROW_TEXT_RIGHT + FIGURE_WIDTH + 10), 0, 18)

	local figure = label(card, FONT_BOLD, 13, PALETTE.Muted, Enum.TextXAlignment.Right)
	figure.Position = UDim2.new(1, -(ROW_TEXT_RIGHT + FIGURE_WIDTH), 0, 10)
	figure.Size = UDim2.new(0, FIGURE_WIDTH, 0, 16)

	local caption = label(card, FONT_BODY, 12, PALETTE.Muted, Enum.TextXAlignment.Left)
	caption.Position = UDim2.new(0, ROW_TEXT_LEFT, 0, 27)
	caption.Size = UDim2.new(1, -(ROW_TEXT_LEFT + ROW_TEXT_RIGHT), 0, 15)

	return card, title, figure, caption
end

-- A progress bar along the bottom edge of a row. Only two panes want one, which is why
-- it is a separate call rather than part of every row: a track drawn under a job advert
-- would be a bar measuring nothing.
local function addBar(card: Frame, fill: number, color: Color3)
	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -(ROW_TEXT_LEFT + ROW_TEXT_RIGHT), 0, 4)
	track.Position = UDim2.new(0, ROW_TEXT_LEFT, 1, -11)
	track.BackgroundColor3 = PALETTE.Edge
	track.BackgroundTransparency = 0.5
	track.BorderSizePixel = 0
	track.ZIndex = 4
	track.Parent = card

	corner(track, 2)

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(math.clamp(fill, 0, 1), 0, 1, 0)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.ZIndex = 5
	bar.Parent = track

	corner(bar, 2)
end

-- The invisible button that makes a whole row pressable, plus the hover it earns by
-- being one.
--
-- **Only rows that do something get one.** A hover state on a row that cannot be pressed
-- is a lie the player only finds out about by pressing it, and it costs more than the
-- affordance is worth: after the first dead row they stop trusting the highlight and the
-- rows that *are* live lose their signal too.
local function pressable(self: MenuUIHandle, card: Frame, activated: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 1, 0)
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = 6
	button.Parent = card

	-- The hover moves the spine, not the row. A row sliding sideways under the cursor is
	-- the obvious version and it was the first one; in a list it breaks the vertical line
	-- the spines make down the left edge, so the eye is pulled to the gap that opened
	-- rather than to the row that is live. Growing the spine says the same thing and
	-- leaves every other row where it was. See `Config.UI.Menu.Motion.HoverSpinePixels`.
	local spine = card:FindFirstChild("Spine")
	local spineTall = SPINE_HEIGHT + MOTION.HoverSpinePixels * 2

	button.MouseEnter:Connect(function()
		TweenService:Create(card, HOVER, { BackgroundColor3 = PALETTE.RowHover }):Play()
		if spine ~= nil and spine:IsA("Frame") then
			TweenService:Create(spine, HOVER, { Size = UDim2.new(0, 3, 0, spineTall) }):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(card, HOVER, { BackgroundColor3 = PALETTE.Row }):Play()
		if spine ~= nil and spine:IsA("Frame") then
			TweenService:Create(spine, HOVER, { Size = UDim2.new(0, 3, 0, SPINE_HEIGHT) }):Play()
		end
	end)

	-- Acknowledged on the frame of the press, before the callback runs and long before the
	-- server answers. Everything a row can do here is a round trip -- a call put through, a
	-- setting saved, colours turned on -- and the honest way to stay responsive without
	-- pretending to know the answer is to confirm the *press* rather than the outcome. A
	-- refusal that arrives 200ms later still feels immediate if the row moved at 20.
	button.MouseButton1Down:Connect(function()
		card.BackgroundColor3 = PALETTE.RowHover:Lerp(self.accent, 0.35)
		TweenService:Create(card, HOVER, { BackgroundColor3 = PALETTE.RowHover }):Play()
	end)

	button.Activated:Connect(activated)
	return button
end

-- A switch, for a row whose figure is a state rather than a number.
--
-- The word "On" in the figure column was what the settings pane shipped with and it was
-- wrong in a way that is easy to miss: a pane of seven identical rows differing only in a
-- two-letter word is a pane you have to read rather than scan. A switch has a position,
-- and a position is visible from further away than a word is.
--
-- **It does not move when it is pressed.** The state it draws is the state the server
-- pushed, and a switch that slides on the click and slides back when the save fails is a
-- worse lie than one that takes a round trip to move. The press is acknowledged by the row
-- under it -- see `pressable`.
local function makeSwitch(parent: Frame, on: boolean, accent: Color3)
	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -ROW_TEXT_RIGHT, 0.5, 0)
	track.Size = UDim2.fromOffset(46, 26)
	track.BackgroundColor3 = if on then accent:Lerp(PALETTE.Panel, 0.28) else PALETTE.RowLocked
	track.BorderSizePixel = 0
	track.ZIndex = 4
	track.Parent = parent

	corner(track, 13)
	stroke(track, if on then accent else PALETTE.Edge, 1, if on then 0.4 else 0.5)

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = if on then UDim2.new(1, -23, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
	knob.Size = UDim2.fromOffset(20, 20)
	knob.BackgroundColor3 = if on then accent else PALETTE.Muted
	knob.BorderSizePixel = 0
	knob.ZIndex = 5
	knob.Parent = track

	corner(knob, 10)
end

-- Every tile repainted for the current selection and hover.
--
-- One function for all seven rather than a per-tile handler, because the states are not
-- independent: selecting one tile deselects another, and two handlers each certain about
-- their own tile is how a rail ends up with two of them lit.
local function paintRail(self: MenuUIHandle)
	for _, tab in MENU.Tabs do
		local button = self.railButtons[tab.id]
		local icon = self.railIcons[tab.id]
		if button == nil or icon == nil then
			continue
		end

		local selected = self.open and self.selected == tab.id
		local hovered = self.railHovered == tab.id

		-- The name-on-hover, and **only while the panel is shut.** Open, the tip is drawn
		-- into the strip of screen the panel is sitting in -- it lands on the panel's left
		-- edge and over whichever row happens to be there, which is a label from one
		-- surface printed on top of another. It is also redundant by then: the panel's own
		-- title bar names the pane in the pane's colour, one line from the tile. So the tip
		-- teaches the rail while there is nothing else to read, and gets out of the way the
		-- moment there is.
		local tip = self.railTips[tab.id]
		if tip ~= nil then
			tip.Visible = hovered and not self.open
		end

		local fill: Color3
		local ink: Color3
		local edgeAlpha: number
		if selected then
			-- The pane's own colour, taken almost all the way down to the panel. A tile
			-- filled with the full hue would be the brightest thing on the screen and the
			-- rail would out-shout the list it opened.
			fill = tab.color:Lerp(PALETTE.Panel, 0.76)
			ink = tab.color
			edgeAlpha = 0.2
		elseif hovered then
			fill = PALETTE.RowHover
			ink = tab.color
			edgeAlpha = 0.55
		else
			-- Desaturated at rest, full colour under the cursor. Seven saturated icons
			-- stacked down the edge of the screen is a row of traffic lights; the colour is
			-- worth more spent on telling the player which one they are pointing at.
			fill = PALETTE.Row
			ink = tab.color:Lerp(PALETTE.Muted, 0.5)
			edgeAlpha = 1
		end

		TweenService:Create(button, HOVER, { BackgroundColor3 = fill }):Play()

		local edge = button:FindFirstChildOfClass("UIStroke")
		if edge ~= nil then
			edge.Color = tab.color
			TweenService:Create(edge, HOVER, { Transparency = edgeAlpha }):Play()
		end

		local pip = button:FindFirstChild("Pip")
		if pip ~= nil and pip:IsA("Frame") then
			TweenService:Create(pip, HOVER, { BackgroundTransparency = if selected then 0 else 1 }):Play()
		end

		-- Snapped rather than tweened. An icon is six frames and a stroke, so a colour tween
		-- here is forty tweens per hover across the rail -- for a change the eye reads as
		-- instant anyway because the tile behind it is what is actually moving.
		MenuIcons.Paint(icon, ink)
	end
end

function MenuUI.new(): MenuUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesMenu"
	-- Under the map sheet and over the heat banner. The map is the thing that takes the
	-- screen; this sits below it so that opening a map with the menu up does not leave a
	-- list of jobs floating over the town.
	screenGui.DisplayOrder = 4
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- `ScreenInsets` rather than `IgnoreGuiInset`, which is the older spelling of roughly
	-- this and does not compose with it: setting `IgnoreGuiInset = true` while the insets
	-- are `CoreUISafeInsets` silently switches them to `DeviceSafeInsets` instead, and the
	-- symptom is a backdrop that stops short of a phone's notch on some devices and not
	-- others. Said once, explicitly: full bleed, except where the hardware is.
	screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	screenGui.Parent = playerGui

	-- The one blur in the game, and it only ever runs behind an open panel.
	--
	-- Blurring the screen during play is a fault -- it costs a frame's worth of fill rate
	-- to make the thing the player is trying to look at harder to see. Behind a menu it is
	-- the opposite: it is what makes the panel read as a sheet in front of the town rather
	-- than a rectangle painted on it, and the player is not looking at the town anyway.
	local blur = Instance.new("BlurEffect")
	blur.Name = "AgesMenuBlur"
	blur.Size = 0
	blur.Parent = Lighting

	-- ---------------------------------------------------------------
	-- The rail. Always on screen, in its own frame so that hiding the panel below
	-- never touches it.
	--
	-- The tiles sit on a plate rather than floating individually, which is the difference
	-- between seven buttons someone left down the side of the screen and one object that
	-- belongs there. It is also what gives a tile somewhere to be lighter *than*.
	-- ---------------------------------------------------------------

	local tabs = MENU.Tabs
	local plateWidth = MENU.RailTilePixels + MENU.RailPadPixels * 2
	local plateHeight = #tabs * MENU.RailTilePixels
		+ (#tabs - 1) * MENU.RailGapPixels
		+ MENU.RailPadPixels * 2

	local rail = Instance.new("Frame")
	rail.Name = "Rail"
	rail.AnchorPoint = Vector2.new(0, 0.5)
	rail.Position = UDim2.new(0, MENU.RailInsetPixels, 0.5, 0)
	rail.Size = UDim2.fromOffset(plateWidth, plateHeight)
	rail.BackgroundColor3 = PALETTE.Panel
	rail.BackgroundTransparency = 0.12
	rail.BorderSizePixel = 0
	rail.ZIndex = 20
	rail.Parent = screenGui

	corner(rail, 16)
	gradient(rail, 1, 0.82)
	stroke(rail, PALETTE.Edge, 1, 0.5)

	local railPadding = Instance.new("UIPadding")
	railPadding.PaddingTop = UDim.new(0, MENU.RailPadPixels)
	railPadding.PaddingBottom = UDim.new(0, MENU.RailPadPixels)
	railPadding.PaddingLeft = UDim.new(0, MENU.RailPadPixels)
	railPadding.PaddingRight = UDim.new(0, MENU.RailPadPixels)
	railPadding.Parent = rail

	local railLayout = Instance.new("UIListLayout")
	railLayout.FillDirection = Enum.FillDirection.Vertical
	railLayout.Padding = UDim.new(0, MENU.RailGapPixels)
	railLayout.SortOrder = Enum.SortOrder.LayoutOrder
	railLayout.Parent = rail

	-- ---------------------------------------------------------------
	-- The backdrop and the panel.
	-- ---------------------------------------------------------------

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = PALETTE.Backdrop
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 1
	backdrop.Parent = screenGui

	-- A `CanvasGroup` rather than a `Frame`, for one property: `GroupTransparency` fades
	-- the panel and everything in it with a single tween. The alternative is tweening the
	-- background, six labels per row and forty rows -- which is not just tedious, it is the
	-- reason the first version of this file had no fade at all.
	local panel = Instance.new("CanvasGroup")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	-- Anchored to the rail's right edge rather than centred, so that the tile the player
	-- clicked stays exactly where their cursor already is. A panel that opens centred
	-- moves the rail out from under the pointer and makes switching panes a hunt.
	panel.Position = UDim2.new(0, MENU.RailInsetPixels + plateWidth + 14, 0.5, 0)
	-- Height in offset, and set for real by `fitPanel` on every redraw -- this is only the
	-- floor it starts at so that the first frame is not a zero-height sliver.
	panel.Size = UDim2.new(MENU.PanelWidthFraction, 0, 0, MENU.PanelMinHeightPixels)
	panel.BackgroundColor3 = PALETTE.Panel
	panel.BorderSizePixel = 0
	panel.GroupTransparency = 1
	panel.Visible = false
	panel.ZIndex = 2
	panel.Parent = screenGui

	corner(panel, 14)
	gradient(panel, 1, 0.78)
	stroke(panel, PALETTE.Edge, 1, 0.35)

	-- A fraction alone is wrong at both ends of the range of screens this runs on: 56% of a
	-- phone held sideways is too narrow for a row with a figure column in it, and 56% of an
	-- ultrawide is a panel you have to move your head to read.
	local panelWidth = Instance.new("UISizeConstraint")
	panelWidth.MinSize = Vector2.new(MENU.PanelMinWidthPixels, 0)
	panelWidth.MaxSize = Vector2.new(MENU.PanelMaxWidthPixels, math.huge)
	panelWidth.Parent = panel

	-- ---------------------------------------------------------------
	-- The player card. Top strip of the panel, the same on every pane, because the
	-- questions the panes answer are all about this person and a panel that forgot
	-- whose life it was describing would be seven lists in a box.
	-- ---------------------------------------------------------------

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, MENU.HeaderPixels)
	header.BackgroundTransparency = 1
	header.ZIndex = 3
	header.Parent = panel

	local headerPadding = Instance.new("UIPadding")
	headerPadding.PaddingLeft = UDim.new(0, 18)
	headerPadding.PaddingRight = UDim.new(0, 18)
	headerPadding.PaddingTop = UDim.new(0, 14)
	headerPadding.Parent = header

	-- The player's own face, pulled straight off the thumbnail service by content URL.
	--
	-- No `GetUserThumbnailAsync`, which is a yielding web call that can fail, can be
	-- rate-limited, and would put a network round trip on the path that builds the menu.
	-- `rbxthumb://` is resolved by the engine like any other image: it costs nothing here,
	-- it cannot throw, and the worst case is a circle that is empty for a moment.
	local avatarHolder = Instance.new("Frame")
	avatarHolder.Name = "Avatar"
	avatarHolder.Position = UDim2.fromOffset(0, 4)
	avatarHolder.Size = UDim2.fromOffset(52, 52)
	avatarHolder.BackgroundColor3 = PALETTE.Row
	avatarHolder.BorderSizePixel = 0
	avatarHolder.ClipsDescendants = true
	avatarHolder.ZIndex = 3
	avatarHolder.Parent = header

	corner(avatarHolder, 26)
	stroke(avatarHolder, PALETTE.Accent, 1.5, 0.55)

	local avatar = Instance.new("ImageLabel")
	avatar.Size = UDim2.new(1, 0, 1, 0)
	avatar.BackgroundTransparency = 1
	avatar.Image = `rbxthumb://type=AvatarHeadShot&id={player.UserId}&w=150&h=150`
	avatar.ZIndex = 4
	avatar.Parent = avatarHolder

	local cardName = label(header, FONT_BOLD, 18, PALETTE.Text, Enum.TextXAlignment.Left)
	cardName.Position = UDim2.fromOffset(66, 8)
	cardName.Size = UDim2.new(1, -110, 0, 22)
	cardName.Text = player.DisplayName

	local cardLine = label(header, FONT_BODY, 13, PALETTE.Muted, Enum.TextXAlignment.Left)
	cardLine.Position = UDim2.fromOffset(66, 32)
	cardLine.Size = UDim2.new(1, -110, 0, 17)

	-- Two rotated bars rather than the letter X, for the same reason the rail draws its
	-- icons: a glyph borrowed to stand in for a shape is the tell that nobody drew one.
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, 0, 0, 6)
	closeButton.Size = UDim2.fromOffset(32, 32)
	closeButton.BackgroundColor3 = PALETTE.Row
	closeButton.BackgroundTransparency = 0.2
	closeButton.BorderSizePixel = 0
	closeButton.AutoButtonColor = false
	closeButton.Text = ""
	closeButton.ZIndex = 4
	closeButton.Parent = header

	corner(closeButton, 16)

	local closeInk: { Frame } = {}
	for _, angle in { 45, -45 } do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(14, 2)
		bar.Rotation = angle
		bar.BackgroundColor3 = PALETTE.Muted
		bar.BorderSizePixel = 0
		bar.ZIndex = 5
		bar.Parent = closeButton
		corner(bar, 1)
		table.insert(closeInk, bar)
	end

	hairline(panel, UDim2.new(0, 18, 0, MENU.HeaderPixels), 18)

	-- ---------------------------------------------------------------
	-- The title bar: which pane this is, in that pane's colour.
	-- ---------------------------------------------------------------

	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Position = UDim2.new(0, 0, 0, MENU.HeaderPixels)
	titleBar.Size = UDim2.new(1, 0, 0, MENU.TitleBarPixels)
	titleBar.BackgroundTransparency = 1
	titleBar.ZIndex = 3
	titleBar.Parent = panel

	local titleRule = Instance.new("Frame")
	titleRule.Name = "Rule"
	titleRule.AnchorPoint = Vector2.new(0, 0.5)
	titleRule.Position = UDim2.new(0, 18, 0.5, 0)
	titleRule.Size = UDim2.fromOffset(3, 16)
	titleRule.BackgroundColor3 = PALETTE.Accent
	titleRule.BorderSizePixel = 0
	titleRule.ZIndex = 4
	titleRule.Parent = titleBar

	corner(titleRule, 2)

	local titleLabel = label(titleBar, FONT_BOLD, 15, PALETTE.Text, Enum.TextXAlignment.Left)
	titleLabel.AnchorPoint = Vector2.new(0, 0.5)
	titleLabel.Position = UDim2.new(0, 29, 0.5, 0)
	titleLabel.Size = UDim2.new(1, -47, 0, 20)
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center

	-- ---------------------------------------------------------------
	-- The list.
	-- ---------------------------------------------------------------

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Position = UDim2.new(0, 14, 0, CONTENT_TOP)
	content.Size = UDim2.new(1, -28, 1, -(CONTENT_TOP + CONTENT_BOTTOM_PAD))
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 3
	content.ScrollBarImageColor3 = PALETTE.Edge
	content.ScrollBarImageTransparency = 0.25
	-- Y only. A list that can be dragged sideways is a list somebody will accidentally
	-- drag sideways, and there is nothing out there to find.
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.ZIndex = 3
	content.Parent = panel

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.FillDirection = Enum.FillDirection.Vertical
	contentLayout.Padding = UDim.new(0, ROW_GAP)
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Parent = content

	-- Sits outside the scrolling frame on purpose. Inside it, an empty-state line would
	-- be a canvas item and would push the scroll height around as panes changed.
	--
	-- It carries the pane's own icon, greyed. An empty pane is the most common thing a new
	-- player sees -- they have no job, no friends, no gang and no skills for the first few
	-- minutes -- so this is the state that has to look deliberate rather than broken.
	local emptyHolder = Instance.new("Frame")
	emptyHolder.Name = "Empty"
	emptyHolder.Position = UDim2.new(0, 22, 0, CONTENT_TOP + EMPTY_TOP)
	emptyHolder.Size = UDim2.new(1, -44, 0, EMPTY_HEIGHT)
	emptyHolder.BackgroundTransparency = 1
	emptyHolder.Visible = false
	emptyHolder.ZIndex = 3
	emptyHolder.Parent = panel

	local emptyIconBox = Instance.new("Frame")
	emptyIconBox.Name = "IconBox"
	emptyIconBox.Size = UDim2.fromOffset(34, 34)
	emptyIconBox.BackgroundTransparency = 1
	emptyIconBox.ZIndex = 3
	emptyIconBox.Parent = emptyHolder

	local emptyLabel = label(emptyHolder, FONT_BODY, 13, PALETTE.Muted, Enum.TextXAlignment.Left)
	emptyLabel.Position = UDim2.fromOffset(0, 48)
	emptyLabel.Size = UDim2.new(1, 0, 0, 92)
	emptyLabel.TextWrapped = true
	emptyLabel.TextTruncate = Enum.TextTruncate.None

	local self: MenuUIHandle = setmetatable({
		screenGui = screenGui,
		rail = rail,
		panel = panel,
		panelHome = panel.Position,
		backdrop = backdrop,
		blur = blur,
		titleLabel = titleLabel,
		titleRule = titleRule,
		cardName = cardName,
		cardLine = cardLine,
		content = content,
		emptyHolder = emptyHolder,
		emptyIcon = emptyIconBox,
		emptyLabel = emptyLabel,
		railButtons = {},
		railIcons = {},
		railTips = {},
		railHovered = nil,
		open = false,
		selected = tabs[1].id,
		accent = tabs[1].color,
		rowIndex = 0,
		contentHeight = 0,
		animate = false,
		jobs = {},
		currentJob = nil,
		onQuitJob = nil,
		onJobTapped = nil,
		onLocationTapped = nil,
		roster = {},
		gang = nil,
		skills = nil,
		bill = nil,
		savings = nil,
		house = nil,
		settings = nil,
		codes = nil,
		codeResult = "",
		codeResultOk = false,
		codeDraft = "",
		onCodeSubmitted = nil,
		onSettingToggled = nil,
		ageYears = 0,
		stage = "",
		money = 0,
		onColorsToggled = nil,
		onPersonTapped = nil,
	}, MenuUI)

	for order, tab in tabs do
		local button = Instance.new("TextButton")
		button.Name = tab.id
		button.Size = UDim2.fromOffset(MENU.RailTilePixels, MENU.RailTilePixels)
		button.LayoutOrder = order
		button.BackgroundColor3 = PALETTE.Row
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Text = ""
		button.ZIndex = 21
		button.Parent = rail

		corner(button, 12)
		gradient(button, 1, 0.84)
		stroke(button, tab.color, 1, 1)

		-- The press punch lives on a `UIScale` rather than on the tile's own `Size`,
		-- because the tile is laid out by a `UIListLayout` and growing it would push the six
		-- tiles under it down the rail every time one was clicked.
		local scale = Instance.new("UIScale")
		scale.Parent = button

		-- The marker for the pane that is open, sitting in the plate's padding to the left
		-- of the tile rather than inside it. Inside, it would be one more thing competing
		-- for a 46-pixel square that already has an icon in it.
		local pip = Instance.new("Frame")
		pip.Name = "Pip"
		pip.AnchorPoint = Vector2.new(0.5, 0.5)
		pip.Position = UDim2.new(0, -4, 0.5, 0)
		pip.Size = UDim2.fromOffset(3, 18)
		pip.BackgroundColor3 = tab.color
		pip.BackgroundTransparency = 1
		pip.BorderSizePixel = 0
		pip.ZIndex = 22
		pip.Parent = button

		corner(pip, 2)

		-- Errors here, at build time, if the tab has no picture behind it -- see
		-- `MenuIcons.Draw`. A rail that boots is a rail with seven icons in it.
		local icon = MenuIcons.Draw(button, tab.id, MENU.RailIconPixels, tab.color)

		-- The tile's name, on hover, because an icon is only unambiguous once you already
		-- know what it means. This is what teaches it: seven shapes with the words beside
		-- them for the first life, and no words needed after that.
		local tip = Instance.new("Frame")
		tip.Name = "Tip"
		tip.AnchorPoint = Vector2.new(0, 0.5)
		tip.Position = UDim2.new(1, 12, 0.5, 0)
		tip.AutomaticSize = Enum.AutomaticSize.XY
		tip.Size = UDim2.fromOffset(0, 0)
		tip.BackgroundColor3 = PALETTE.Panel
		tip.BackgroundTransparency = 0.05
		tip.BorderSizePixel = 0
		tip.Visible = false
		tip.ZIndex = 30
		tip.Parent = button

		corner(tip, 6)
		stroke(tip, PALETTE.Edge, 1, 0.45)

		local tipPadding = Instance.new("UIPadding")
		tipPadding.PaddingLeft = UDim.new(0, 10)
		tipPadding.PaddingRight = UDim.new(0, 10)
		tipPadding.PaddingTop = UDim.new(0, 6)
		tipPadding.PaddingBottom = UDim.new(0, 6)
		tipPadding.Parent = tip

		local tipText = label(tip, FONT_MEDIUM, 13, PALETTE.Text, Enum.TextXAlignment.Left)
		tipText.AutomaticSize = Enum.AutomaticSize.XY
		tipText.Size = UDim2.fromOffset(0, 0)
		tipText.TextTruncate = Enum.TextTruncate.None
		tipText.Text = tab.label
		tipText.ZIndex = 31

		local pressTween = TweenInfo.new(MOTION.PressOutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local settleTween = TweenInfo.new(MOTION.PressBackSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local function settle()
			TweenService:Create(scale, settleTween, { Scale = 1 }):Play()
		end

		button.MouseEnter:Connect(function()
			self.railHovered = tab.id
			paintRail(self)
		end)

		button.MouseLeave:Connect(function()
			if self.railHovered == tab.id then
				self.railHovered = nil
			end
			settle()
			paintRail(self)
		end)

		-- On the *down*, not on the activation. The pane behind a tile can be forty rows,
		-- and the whole of that build happens between the click and the next frame -- so a
		-- reaction hung off `Activated` is a reaction the player sees after the work. This
		-- one is on screen before the first row exists.
		button.MouseButton1Down:Connect(function()
			TweenService:Create(scale, pressTween, { Scale = MOTION.PressScale }):Play()
		end)
		button.MouseButton1Up:Connect(settle)

		button.Activated:Connect(function()
			-- Clicking the pane you are already on closes the panel. The rail is then a
			-- toggle per pane rather than an open-only control, which is what stops the
			-- only way out being a key or a corner the mouse has to travel to.
			if self.open and self.selected == tab.id then
				MenuUI.Close(self)
				return
			end
			self.selected = tab.id
			MenuUI.Open(self)
		end)

		self.railButtons[tab.id] = button
		self.railIcons[tab.id] = icon
		self.railTips[tab.id] = tip
	end

	closeButton.MouseEnter:Connect(function()
		TweenService:Create(closeButton, HOVER, { BackgroundColor3 = PALETTE.RowHover }):Play()
		for _, bar in closeInk do
			TweenService:Create(bar, HOVER, { BackgroundColor3 = PALETTE.Text }):Play()
		end
	end)
	closeButton.MouseLeave:Connect(function()
		TweenService:Create(closeButton, HOVER, { BackgroundColor3 = PALETTE.Row }):Play()
		for _, bar in closeInk do
			TweenService:Create(bar, HOVER, { BackgroundColor3 = PALETTE.Muted }):Play()
		end
	end)

	backdrop.Activated:Connect(function()
		MenuUI.Close(self)
	end)

	closeButton.Activated:Connect(function()
		MenuUI.Close(self)
	end)

	paintRail(self)
	return self
end

-- -------------------------------------------------------------------
-- Panes. One function each, all of them building into the same cleared list, all of
-- them returning the empty-state sentence for when they built nothing.
-- -------------------------------------------------------------------

-- The height of the current-job card: a title row, a wage figure, a standing line,
-- a progress bar and a Quit button, all in one card rather than the two-line shape
-- every other row here uses -- because holding a job is the one fact on this pane
-- that is more than a title and a figure.
local CURRENT_JOB_HEIGHT = 108

-- What you already have, drawn once above the list of what you could take instead.
-- Its own card rather than a row in the same shape as the openings below it: an
-- opening is a title and a figure, and a job you hold has a wage, a rank and a way
-- out, none of which fit the two lines everything else on this pane gets.
local function drawCurrentJob(self: MenuUIHandle)
	local job = self.currentJob
	if job == nil or job.jobId == nil then
		return
	end

	local _, card = makeSlot(self, CURRENT_JOB_HEIGHT)
	addSpine(card, PALETTE.Good)

	local title = label(card, FONT_BOLD, 16, PALETTE.Text, Enum.TextXAlignment.Left)
	title.Position = UDim2.new(0, ROW_TEXT_LEFT, 0, 10)
	title.Size = UDim2.new(1, -(ROW_TEXT_LEFT + ROW_TEXT_RIGHT + 108), 0, 20)
	title.Text = job.jobTitle or ""

	local wageFigure = label(card, FONT_BOLD, 15, PALETTE.Accent, Enum.TextXAlignment.Right)
	wageFigure.Position = UDim2.new(1, -(ROW_TEXT_RIGHT + FIGURE_WIDTH), 0, 11)
	wageFigure.Size = UDim2.new(0, FIGURE_WIDTH, 0, 18)
	wageFigure.Text = if job.wage ~= nil then `{Money.Format(job.wage)}/hr` else ""

	local standingCaption = label(card, FONT_BODY, 12, PALETTE.Muted, Enum.TextXAlignment.Left)
	standingCaption.Position = UDim2.new(0, ROW_TEXT_LEFT, 0, 33)
	standingCaption.Size = UDim2.new(1, -(ROW_TEXT_LEFT + ROW_TEXT_RIGHT), 0, 15)
	local standingWord = if job.standing ~= nil then job.standing else "New"
	standingCaption.Text = if job.onShift then `{standingWord}  ·  On shift now` else standingWord

	-- The same fraction the HUD's own standing bar reads off this state, so a player
	-- who checks both sees one number, not two that happen to agree.
	if job.nextBandXp ~= nil and job.nextBandXp > 0 then
		addBar(card, math.clamp(job.standingXp / job.nextBandXp, 0, 1), PALETTE.Good)
	end

	local quit = Instance.new("TextButton")
	quit.AnchorPoint = Vector2.new(1, 0)
	quit.Position = UDim2.new(1, -ROW_TEXT_RIGHT, 0, 58)
	quit.Size = UDim2.fromOffset(94, 32)
	quit.BackgroundColor3 = PALETTE.RowLocked
	quit.BorderSizePixel = 0
	quit.AutoButtonColor = false
	quit.FontFace = FONT_BOLD
	quit.TextSize = 13
	quit.TextColor3 = PALETTE.Warn
	quit.Text = "Quit job"
	quit.ZIndex = 4
	quit.Parent = card

	corner(quit, 7)
	stroke(quit, PALETTE.Warn, 1, 0.55)

	quit.MouseEnter:Connect(function()
		TweenService:Create(quit, HOVER, { BackgroundColor3 = PALETTE.Warn:Lerp(PALETTE.Panel, 0.2) }):Play()
	end)
	quit.MouseLeave:Connect(function()
		TweenService:Create(quit, HOVER, { BackgroundColor3 = PALETTE.RowLocked }):Play()
	end)
	quit.Activated:Connect(function()
		local callback = self.onQuitJob
		if callback ~= nil then
			callback()
		end
	end)
end

-- Every destination in Config.Locations.List, as one pressable row apiece. The pane leads
-- the rail (see Config.UI.Menu.Tabs) precisely because this is the fastest way to any of
-- the other rows this menu, or a job post in the world, already points the guide arrows
-- at -- pressing one fires RequestGuideToLocation and the player still walks there, the
-- same arrow a job destination gets.
local function drawLocations(self: MenuUIHandle): string?
	local places = Config.Locations.List
	if #places == 0 then
		return "Nowhere is mapped yet."
	end

	for _, place in places do
		local card, title, _, caption = makeRow(self)
		title.Text = place.label
		caption.Text = "Point the guide arrows here."

		local id = place.id
		pressable(self, card, function()
			local callback = self.onLocationTapped
			if callback ~= nil then
				callback(id)
			end
		end)
	end
	return nil
end

local function drawJobs(self: MenuUIHandle): string?
	drawCurrentJob(self)

	if #self.jobs == 0 then
		if self.currentJob ~= nil and self.currentJob.jobId ~= nil then
			return nil
		end
		return "Nothing is hiring where you can see it. Job boards stand outside the places that are taking people on -- the map will show you where they are."
	end

	for _, post in self.jobs do
		local card, title, figure, caption = makeRow(self)
		title.Text = post.title
		-- The pad's own words for whether you can take it, which is the one thing a
		-- player reading a list of jobs actually wants: not what it pays, but whether
		-- this one is open to them right now.
		figure.Text = if post.padLocked then "Not yet" else "Open"
		figure.TextColor3 = if post.padLocked then PALETTE.Muted else PALETTE.Good
		caption.Text = if #post.terms > 0 then table.concat(post.terms, "  ·  ") else post.headline
		if post.padLocked then
			-- Recessed rather than faded. A row at 35% transparency is a row you can see the
			-- panel's gradient through, which reads as a card that failed to finish drawing;
			-- a darker fill reads as a card that is deliberately not available.
			card.BackgroundColor3 = PALETTE.RowLocked
			title.TextColor3 = PALETTE.Muted
		end

		-- Pressable whether open or locked, on the same reasoning the relationships pane
		-- already presses on a spent row: knowing where a job is is worth acting on even
		-- before you qualify for it, and the arrow is the one thing this row can offer
		-- that reading it cannot.
		local jobId = post.jobId
		pressable(self, card, function()
			local callback = self.onJobTapped
			if callback ~= nil then
				callback(jobId)
			end
		end)
	end
	return nil
end

local function drawRelationships(self: MenuUIHandle): string?
	if #self.roster == 0 then
		return "You have not met anybody yet."
	end

	for _, person in self.roster do
		local card, title, figure, caption = makeRow(self)
		title.Text = person.name
		figure.Text = if person.available then "Free to talk" else "Seen this year"
		figure.TextColor3 = if person.available then PALETTE.Good else PALETTE.Muted
		-- The band is the word the game has always used for this bond -- "known",
		-- "friend", "closest friend". The tie, when there is one, is the structural
		-- thing on top of it and is said second because it is rarer and it is earned.
		caption.Text = if person.tie ~= nil then `{person.band}  ·  {person.tie}` else person.band
		if not person.available then
			card.BackgroundColor3 = PALETTE.RowLocked
		end

		-- Every row, including the spent ones. This is the only way to reach somebody who
		-- is not standing in front of you, and it came here from the HUD roster along with
		-- the list -- a relationships pane you can read but not act from would have taken a
		-- verb out of the game in the name of tidying the screen up.
		--
		-- Spent rows stay pressable on purpose. The refusal is a sentence the server sends
		-- back, and a button that silently does nothing teaches a player less than one that
		-- tells them they have already had this person's year.
		local personId = person.id
		pressable(self, card, function()
			local callback = self.onPersonTapped
			if callback ~= nil then
				callback(personId)
			end
		end)
	end
	return nil
end

-- `suburb_5` as a player would say it. The house ids in this world are generated, so
-- there is no authored label to look up and inventing a table of them would go stale the
-- next time the suburb is regenerated with one more plot in it.
local function houseName(houseId: string): string
	local word, number = string.match(houseId, "^(%a+)_(%d+)$")
	if word == nil or number == nil then
		return houseId
	end
	return `{string.upper(string.sub(word, 1, 1))}{string.sub(word, 2)} {number}`
end

-- What you have, what you owe, and what you own.
--
-- These were four rows stacked on the HUD, appearing and disappearing as their services
-- pushed, and none of them was about the minute the player was in: a savings balance is
-- not a thing you glance at while running to a shift mark. They are looked up, so they
-- live somewhere you look things up.
--
-- Draws the rows that have something to say and silently omits the rest, so an early
-- life shows one row and a settled one shows four. The alternative -- every row always
-- present with a zero in it -- is a panel that teaches the player it has nothing to
-- tell them, and they stop opening it.
local function drawMoney(self: MenuUIHandle): string?
	-- Always drawn, and the only row that is. A money pane whose first line depended on
	-- whether a bill had been charged yet would be a money pane that is sometimes empty
	-- while the player is holding money.
	local _, cashTitle, cashFigure, cashCaption = makeRow(self)
	cashTitle.Text = "Cash"
	cashFigure.Text = Money.Format(self.money)
	cashFigure.TextColor3 = PALETTE.Accent
	cashCaption.Text = "On you, and spendable anywhere."

	local bill = self.bill
	if bill ~= nil and (bill.debt > 0 or bill.totalThisMonth > 0) then
		local _, billTitle, billFigure, billCaption = makeRow(self)
		billTitle.Text = "Bills"
		if bill.debt > 0 then
			billFigure.Text = Money.Format(bill.debt)
			billFigure.TextColor3 = PALETTE.Warn
			billCaption.Text = if bill.paid
				then `Owed from before. This month is settled.`
				else `Owed, and this month is not paid either.`
		else
			billFigure.Text = Money.Format(bill.totalThisMonth)
			billFigure.TextColor3 = if bill.paid then PALETTE.Good else PALETTE.Muted
			billCaption.Text = if bill.paid
				then "This month is paid and you owe nothing."
				else "Due this month. Nothing owed from before."
		end
	end

	local savings = self.savings
	if savings ~= nil and savings.balance > 0 then
		local card, saveTitle, saveFigure, saveCaption = makeRow(self)
		saveTitle.Text = "Savings"
		saveFigure.Text = Money.Format(savings.balance)
		saveFigure.TextColor3 = PALETTE.Good
		saveCaption.Text = `Earns {math.floor(savings.interestRate * 100 + 0.5)}% a year. Deposit and withdraw at the bank.`
		-- Filled against the ceiling rather than against nothing, because the ceiling is
		-- the only fact about a savings balance the player cannot see anywhere else and
		-- it is the one that decides whether walking to the bank is still worth doing.
		if savings.maxBalance > 0 then
			addBar(card, savings.balance / savings.maxBalance, PALETTE.Good)
		end
	end

	local house = self.house
	if house ~= nil then
		for houseId in house.owned do
			local _, homeTitle, homeFigure, homeCaption = makeRow(self)
			homeTitle.Text = houseName(houseId)
			homeFigure.Text = "Owned"
			homeFigure.TextColor3 = PALETTE.Good
			local job = house.homeJob[houseId]
			homeCaption.Text = if job ~= nil
				then `You work from here as a {string.lower(job)}.`
				else "Nothing links a job to this address yet."
		end
	end

	return nil
end

local function drawGangs(self: MenuUIHandle): string?
	local gang = self.gang
	if gang == nil then
		return "You do not run with anybody. The four sides of the city each have somebody who decides who is in -- find one and talk to them."
	end

	local card, title, figure, caption = makeRow(self)
	title.Text = gang.name
	title.TextColor3 = gang.color
	figure.Text = gang.rankLabel
	figure.TextColor3 = gang.color
	-- The one row in the menu whose spine is not the pane's colour. A gang's colour is the
	-- thing the whole system is about, and painting this row with the pane's generic orange
	-- while naming the gang in its own would be the menu contradicting itself.
	local spine = card:FindFirstChild("Spine")
	if spine ~= nil and spine:IsA("Frame") then
		spine.BackgroundColor3 = gang.color
	end

	if gang.nextStanding ~= nil then
		-- Filled between the rung held and the rung above it, not from zero. Filling from
		-- zero is the easy version and it lies in the player's favour at the top: a
		-- `name` on 401 of 1000 would draw a bar that is 40% along when they have in fact
		-- just started the longest climb in the ladder.
		local floorStanding = 0
		for _, rung in Config.Gangs.Ranks do
			if rung.id == gang.rankId then
				floorStanding = rung.standing
			end
		end
		local span = gang.nextStanding - floorStanding
		local fill = if span > 0 then (gang.standing - floorStanding) / span else 1
		caption.Text = `{math.floor(gang.standing)} standing toward {gang.nextLabel}`
		addBar(card, fill, gang.color)
	else
		caption.Text = `{math.floor(gang.standing)} standing — nothing left to climb`
	end

	-- The promotion, which is a fact rather than a button. Nothing here confers a rung:
	-- GangService hands one over face-to-face, off a panel, in a moment the player
	-- walked across the city to be in, and a menu that could do it from anywhere would
	-- undo the only rule that makes rank mean anything.
	if gang.promotable then
		local _, promoteTitle, promoteFigure, promoteCaption = makeRow(self)
		promoteTitle.Text = "You have earned the next rung"
		promoteFigure.Text = gang.nextLabel or ""
		promoteFigure.TextColor3 = gang.color
		promoteCaption.Text = "Go and see whoever runs your side. Rank is handed over, never awarded."
	end

	-- Who runs with you. Zero slots -- "hanger-on" and "hand" -- draws nothing at all,
	-- same as the promotion row above: a section for a feature this rung does not have
	-- would be the menu promising a comparison there is nothing behind, the exact thing
	-- this pane's own header rules out for the other three gangs.
	if gang.crewSlots > 0 then
		if #gang.crew == 0 then
			local _, crewTitle, crewFigure, crewCaption = makeRow(self)
			crewTitle.Text = "Crew"
			crewFigure.Text = `0 / {gang.crewSlots}`
			crewCaption.Text = "Nobody runs with you yet. Whoever runs your side can bring somebody in."
		else
			for _, member in gang.crew do
				local card, title, figure, caption = makeRow(self)
				title.Text = member.name
				figure.Text = `nerve {math.floor(member.nerve)}`
				figure.TextColor3 = gang.color
				caption.Text = "Runs with you. Nerve only ever rises, the more work you pull together."
				local spine = card:FindFirstChild("Spine")
				if spine ~= nil and spine:IsA("Frame") then
					spine.BackgroundColor3 = gang.color
				end
			end
		end
	end

	local colorsCard, colorsTitle, _, colorsCaption = makeRow(self)
	colorsTitle.Text = "Colors"
	colorsCaption.Text = if gang.wearing
		then "Everyone can see whose side you are on. Every point of heat counts double."
		else "Nobody can tell. You earn nothing on anybody else's side while it is off."
	makeSwitch(colorsCard, gang.wearing, gang.color)

	local wearing = gang.wearing
	pressable(self, colorsCard, function()
		local callback = self.onColorsToggled
		if callback ~= nil then
			callback(not wearing)
		end
	end)

	return nil
end

-- Soccer's own record, under the ladder rather than folded into the Athletics row: a
-- level and an XP bar say how good the discipline has gotten, but they cannot say what
-- any of it was *for* -- whether the practice went into goals, into the tackles that won
-- the ball back, or into shots that never found the target. Career totals answer that,
-- and they answer it for a life rather than a year, on the same reasoning
-- LifeData.soccerCareer's own header gives -- see SoccerService's header for why a match
-- is always running and never gated behind PE.
local function drawSoccerCareer(self: MenuUIHandle, athleticsColor: Color3)
	local skills = self.skills
	if skills == nil then
		return
	end
	local career = skills.soccerCareer

	local card, title, figure, caption = makeRow(self)
	title.Text = "Soccer"
	title.TextColor3 = athleticsColor
	figure.Text = `{career.goals} goals`

	local spine = card:FindFirstChild("Spine")
	if spine ~= nil and spine:IsA("Frame") then
		spine.BackgroundColor3 = athleticsColor
	end

	if career.matchesPlayed == 0 then
		caption.Text =
			"No matches yet. The 3v3 pitch runs all the time, bot-filled -- walk on and take a bot's spot."
	else
		local accuracy = if career.shotsTaken > 0 then `{career.shotsOnTarget}/{career.shotsTaken} on target` else "no shots taken"
		caption.Text =
			`{career.matchesPlayed} matches  ·  {career.assists} assists  ·  {career.tackles} tackles  ·  {accuracy}`
	end
end

local function drawSkills(self: MenuUIHandle): string?
	local skills = self.skills
	if skills == nil or #skills.skills == 0 then
		return "Nothing yet. Skills come out of things you have been graded on -- a shift worked, a lesson sat, a set finished -- and never out of time spent standing near them."
	end

	local athleticsColor = self.accent
	for _, skill in skills.skills do
		local card, title, figure, caption = makeRow(self)
		title.Text = skill.label
		title.TextColor3 = skill.color
		figure.Text = `{skill.levelName}  ·  lv{skill.level}`

		local spine = card:FindFirstChild("Spine")
		if spine ~= nil and spine:IsA("Frame") then
			spine.BackgroundColor3 = skill.color
		end

		if skill.id == "athletics" then
			athleticsColor = skill.color
		end

		if skill.nextLevelXp ~= nil then
			local span = skill.nextLevelXp - skill.bandFloorXp
			-- Guarded rather than trusted. The span can only be zero if two ladder rungs
			-- were given the same threshold, which is a content mistake -- but the shape
			-- of that mistake here is a division by zero inside a draw loop, which takes
			-- the whole panel down rather than drawing one bad bar.
			local fill = if span > 0 then (skill.xp - skill.bandFloorXp) / span else 1
			caption.Text = `{skill.earnedBy}  ·  {skill.xp} / {skill.nextLevelXp}`
			addBar(card, fill, skill.color)
		else
			caption.Text = `{skill.earnedBy}  ·  {skill.xp}, as far as this goes`
			addBar(card, 1, skill.color)
		end
	end

	-- Under the ladder rather than beside "Athletics" specifically -- see this
	-- function's own header -- so it reads as this discipline's detail rather than a
	-- seventh row competing with the six the ladder is deliberately kept short at.
	drawSoccerCareer(self, athleticsColor)
	return nil
end

-- The redeem box, whatever the server last said about an attempt, and a receipt for every
-- code this account has already used. Folded into the settings pane below rather than
-- given a tab of its own -- Config.UI.Menu.Tabs explains why -- so it is a void helper
-- rather than a pane function: drawSettings decides whether the whole pane is empty.
--
-- The box is drawn always, including for an account that has redeemed nothing. It is the
-- one thing here the player might actually come to do, and a section that led with an
-- empty history would have buried its own verb under a sentence saying there is nothing to
-- see.
--
-- Nothing here decides anything. The box does not know what a code is, does not check one,
-- and does not know what any of them pay -- it sends a string and draws the sentence that
-- comes back. That is not tidiness: a client that could recognise a valid code is a client
-- somebody can read the list of valid codes out of.
local function drawCodeRedemption(self: MenuUIHandle)
	local _, box = makeSlot(self, 88)
	addSpine(box, self.accent)

	local prompt = label(box, FONT_MEDIUM, 14, PALETTE.Text, Enum.TextXAlignment.Left)
	prompt.Position = UDim2.fromOffset(ROW_TEXT_LEFT, 11)
	prompt.Size = UDim2.new(1, -(ROW_TEXT_LEFT + ROW_TEXT_RIGHT), 0, 18)
	prompt.Text = "Have a code?"

	local field = Instance.new("TextBox")
	field.Position = UDim2.fromOffset(ROW_TEXT_LEFT, 36)
	field.Size = UDim2.new(1, -(ROW_TEXT_LEFT + ROW_TEXT_RIGHT + 108), 0, 36)
	field.BackgroundColor3 = PALETTE.PanelDeep
	field.BorderSizePixel = 0
	field.FontFace = FONT_MEDIUM
	field.TextSize = 15
	field.TextXAlignment = Enum.TextXAlignment.Left
	field.TextColor3 = PALETTE.Text
	field.PlaceholderText = "Type it here"
	field.PlaceholderColor3 = PALETTE.Muted
	field.ClearTextOnFocus = false
	field.Text = self.codeDraft
	field.ZIndex = 4
	field.Parent = box

	corner(field, 7)
	stroke(field, PALETTE.Edge, 1, 0.5)

	local fieldPadding = Instance.new("UIPadding")
	fieldPadding.PaddingLeft = UDim.new(0, 11)
	fieldPadding.PaddingRight = UDim.new(0, 11)
	fieldPadding.Parent = field

	local submit = Instance.new("TextButton")
	submit.AnchorPoint = Vector2.new(1, 0)
	submit.Position = UDim2.new(1, -ROW_TEXT_RIGHT, 0, 36)
	submit.Size = UDim2.fromOffset(98, 36)
	submit.BackgroundColor3 = self.accent
	submit.BorderSizePixel = 0
	submit.AutoButtonColor = false
	submit.FontFace = FONT_BOLD
	submit.TextSize = 14
	-- Dark text on the one filled control in the menu. Everything else here is light text
	-- on a dark card, and the inversion is the whole signal: this is the button.
	submit.TextColor3 = PALETTE.Ink
	submit.Text = "Redeem"
	submit.ZIndex = 4
	submit.Parent = box

	corner(submit, 7)
	gradient(submit, 1, 0.86)

	-- Mirrored into the handle on every keystroke, not read off the box at submit time.
	-- A push from any of the other services rebuilds this pane and destroys the TextBox
	-- with whatever was half-typed in it, and a field that loses your typing because a bill
	-- came due somewhere else is a field nobody trusts twice.
	field:GetPropertyChangedSignal("Text"):Connect(function()
		self.codeDraft = field.Text
	end)

	local function send()
		local typed = self.codeDraft
		if typed == "" then
			return
		end
		local callback = self.onCodeSubmitted
		if callback ~= nil then
			callback(typed)
		end
	end

	submit.MouseEnter:Connect(function()
		TweenService:Create(submit, HOVER, { BackgroundColor3 = self.accent:Lerp(PALETTE.Text, 0.3) }):Play()
	end)
	submit.MouseLeave:Connect(function()
		TweenService:Create(submit, HOVER, { BackgroundColor3 = self.accent }):Play()
	end)

	-- Enter submits as well as the button. The box is a place people type into and press
	-- return; making them reach for a button afterwards is the sort of thing that reads as
	-- the code having failed.
	field.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			send()
		end
	end)
	submit.Activated:Connect(send)

	if self.codeResult ~= "" then
		local _, banner = makeSlot(self, 58)
		local tone = if self.codeResultOk then PALETTE.Good else PALETTE.Warn
		banner.BackgroundColor3 = PALETTE.Row
		addSpine(banner, tone)

		local resultTitle = label(banner, FONT_MEDIUM, 14, tone, Enum.TextXAlignment.Left)
		resultTitle.Position = UDim2.fromOffset(ROW_TEXT_LEFT, 9)
		resultTitle.Size = UDim2.new(1, -(ROW_TEXT_LEFT + ROW_TEXT_RIGHT), 0, 17)
		resultTitle.Text = if self.codeResultOk then "Redeemed" else "Not redeemed"

		-- The one caption in the menu allowed to wrap. Everything else here is a fact that
		-- fits on a line; this is a sentence written for the moment it is read, and
		-- truncating a refusal at the point where it says why is worse than a taller row.
		local resultCaption = label(banner, FONT_BODY, 12, PALETTE.Muted, Enum.TextXAlignment.Left)
		resultCaption.Position = UDim2.fromOffset(ROW_TEXT_LEFT, 28)
		resultCaption.Size = UDim2.new(1, -(ROW_TEXT_LEFT + ROW_TEXT_RIGHT), 0, 24)
		resultCaption.TextTruncate = Enum.TextTruncate.None
		resultCaption.TextWrapped = true
		resultCaption.Text = self.codeResult
	end

	local codes = self.codes
	if codes ~= nil then
		for _, redeemed in codes.redeemed do
			local _, title, figure, caption = makeRow(self)
			title.Text = redeemed.label
			figure.Text = redeemed.reward
			figure.TextColor3 = PALETTE.Good
			caption.Text = `{redeemed.code} — already redeemed on this account.`
		end
	end
end

-- The switches, then the redeem box below them. Draws what the server pushed and nothing
-- else for the switches: clicking sends and then waits, the switch does not slide itself,
-- so a preference that failed to save never spends a moment looking like it did. The cost
-- is one round trip of latency, and it is paid for by the row flashing under the cursor on
-- the press -- the player is told they were heard immediately and told the answer when
-- there is one, which are two different things and should look it.
--
-- Never empty. drawCodeRedemption's box draws unconditionally, so a settings pane that
-- has not loaded yet still has something in it worth pressing rather than a bare sentence.
local function drawSettings(self: MenuUIHandle): string?
	local settings = self.settings
	if settings ~= nil then
		for _, option in settings.settings do
			local card, title, _, caption = makeRow(self)
			title.Text = option.label
			caption.Text = option.caption
			if not option.on then
				title.TextColor3 = PALETTE.Muted
			end
			makeSwitch(card, option.on, self.accent)

			local id = option.id
			local on = option.on
			pressable(self, card, function()
				local callback = self.onSettingToggled
				if callback ~= nil then
					callback(id, not on)
				end
			end)
		end
	end

	drawCodeRedemption(self)
	return nil
end

-- Rebuild whichever pane is showing. Called on every push as well as on every switch,
-- because a panel left open while the world changes underneath it is worse than one
-- that costs a few instances to keep honest -- and the lists here are tens of rows,
-- not thousands.
-- The panel resized to hold exactly what was just built into it.
--
-- **The panel is as tall as its pane, not as tall as the screen.** A fixed fraction is the
-- version this shipped with and it is what made the menu look unfinished: money is five
-- rows, settings is six, gangs when you are in none is a single sentence -- and all three
-- were drawn into a sheet claiming three quarters of the screen, so the first thing the eye
-- found was the empty two thirds under the last row. A surface that is the size of its
-- contents reads as deliberate at any length.
--
-- Clamped at both ends. The floor stops a one-row pane becoming a strip; the ceiling stops
-- a forty-row relationships list running off the top and bottom of the screen, and past it
-- the `ScrollingFrame` inside takes over -- which is the one case the scroll bar was ever
-- for.
local function fitPanel(self: MenuUIHandle, empty: boolean)
	local wanted: number
	if empty then
		wanted = CONTENT_TOP + EMPTY_TOP + EMPTY_HEIGHT + CONTENT_BOTTOM_PAD
	else
		wanted = CONTENT_TOP + self.contentHeight + CONTENT_BOTTOM_PAD
	end

	local viewport = self.screenGui.AbsoluteSize.Y
	local ceiling = viewport * MENU.PanelHeightFraction
	-- On a screen short enough that the floor is above the ceiling, the ceiling wins: a
	-- panel taller than the window it is in has its close button off the top edge.
	local height = math.min(math.max(wanted, MENU.PanelMinHeightPixels), ceiling)

	self.panel.Size = UDim2.new(MENU.PanelWidthFraction, 0, 0, height)
end

local function redraw(self: MenuUIHandle, animate: boolean)
	if not self.open then
		return
	end

	for _, child in self.content:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local heading = ""
	local accent = PALETTE.Accent
	for _, tab in MENU.Tabs do
		if tab.id == self.selected then
			heading = tab.label
			accent = tab.color
		end
	end
	self.titleLabel.Text = heading
	self.titleLabel.TextColor3 = accent
	self.titleRule.BackgroundColor3 = accent

	-- Set before the dispatch, read by every row the dispatch builds. A pane function asks
	-- for a row and gets one already wearing the right colour, which is what stops seven
	-- pane builders each having to be told which pane they are.
	self.accent = accent
	self.rowIndex = 0
	self.contentHeight = 0
	self.animate = animate

	local empty: string?
	if self.selected == "locations" then
		empty = drawLocations(self)
	elseif self.selected == "jobs" then
		empty = drawJobs(self)
	elseif self.selected == "money" then
		empty = drawMoney(self)
	elseif self.selected == "relationships" then
		empty = drawRelationships(self)
	elseif self.selected == "gangs" then
		empty = drawGangs(self)
	elseif self.selected == "skills" then
		empty = drawSkills(self)
	elseif self.selected == "settings" then
		empty = drawSettings(self)
	else
		-- A tab in Config with no pane behind it. Said out loud rather than drawn as a
		-- blank, because a blank panel reads as a bug in the data and this is a bug in
		-- the code -- and the two get debugged in completely different places.
		error(`MenuUI: no pane for tab "{self.selected}". Add one to redraw() or remove the tab from Config.UI.Menu.Tabs.`)
	end

	self.emptyLabel.Text = empty or ""
	self.emptyHolder.Visible = empty ~= nil
	self.content.Visible = empty == nil

	if empty ~= nil then
		-- The pane's own icon over its own sentence, in its own colour taken most of the way
		-- to grey. An empty pane is the first thing a new player sees on five of these seven,
		-- and a bare line of text in the top corner of a large panel reads as something that
		-- failed to load rather than as an answer.
		for _, child in self.emptyIcon:GetChildren() do
			child:Destroy()
		end
		MenuIcons.Draw(self.emptyIcon, self.selected, 34, PALETTE.Muted:Lerp(accent, 0.35))
	end

	-- Last, because it needs the row count the dispatch above produced. Not tweened: this
	-- runs on every push as well as on every open, and a panel whose edges were sliding
	-- around each time a wage landed would be worse than one that was the wrong size.
	fitPanel(self, empty ~= nil)

	paintRail(self)
end

-- Rebuild, but only if the pane that owns this data is the one on screen.
--
-- The unscoped version was fine while every pane was a list of labels: a rebuild the player
-- cannot see costs a few instances and nothing else. The codes pane is what makes it wrong.
-- It contains a TextBox, a redraw destroys and recreates it, and `MoneyUpdated` fires every
-- few seconds during a shift -- so a player typing a code into an open menu would have had
-- the field yanked out from under the cursor mid-word by a wage landing somewhere else.
-- The text itself is mirrored into the handle and survives; the focus does not, and a field
-- that drops focus while you type is a field that looks broken.
--
-- Scoping it fixes that and pays for itself twice over: the relationships pane no longer
-- rebuilds forty rows every time a bill is charged either.
--
-- Never animates. See `MenuUIHandle.animate`: a pane that replayed its entrance every time
-- a wage landed would be a list flickering on a timer.
local function redrawPane(self: MenuUIHandle, paneId: string)
	if self.selected ~= paneId then
		return
	end
	redraw(self, false)
end

local function redrawCard(self: MenuUIHandle)
	local parts: { string } = {}
	if self.stage ~= "" then
		table.insert(parts, self.stage)
	end
	table.insert(parts, `Age {self.ageYears}`)
	table.insert(parts, Money.Format(self.money))
	self.cardLine.Text = table.concat(parts, "  ·  ")
end

-- -------------------------------------------------------------------
-- The pushes. Each stores its state and asks the one pane that owns it to redraw, and a
-- redraw is a no-op while the menu is closed -- so a player who never opens the menu pays
-- one table assignment per push and nothing else.
-- -------------------------------------------------------------------

function MenuUI.SetJobs(self: MenuUIHandle, posts: { JobPostState })
	self.jobs = posts
	redrawPane(self, "jobs")
end

-- The same push the HUD's shift clock reads, mirrored here so the pane can show what
-- you already have above the list of what you could take instead. Arrives every time
-- the shift state changes, including several times a minute while on shift, which is
-- why the current-job card never animates in -- see `MenuUIHandle.animate`.
function MenuUI.SetCurrentJob(self: MenuUIHandle, state: ShiftState)
	self.currentJob = state
	redrawPane(self, "jobs")
end

-- "Quit job" pressed on the pane. What that means -- ending a shift in progress,
-- clearing the record, anything at all -- is entirely the caller's decision; this
-- module only reports the press.
function MenuUI.OnQuitJob(self: MenuUIHandle, callback: () -> ())
	self.onQuitJob = callback
end

-- A job row pressed on the pane, open or locked. Carries the id off the post the
-- server already sent, the same as OnPersonTapped carries an id off the roster.
function MenuUI.OnJobTapped(self: MenuUIHandle, callback: (jobId: string) -> ())
	self.onJobTapped = callback
end

-- A row pressed on the Locations pane. Carries the place id straight off
-- Config.Locations.List, the same as OnJobTapped carries one off a job post.
function MenuUI.OnLocationTapped(self: MenuUIHandle, callback: (id: string) -> ())
	self.onLocationTapped = callback
end

function MenuUI.SetRoster(self: MenuUIHandle, entries: { PersonRosterEntry })
	self.roster = entries
	redrawPane(self, "relationships")
end

function MenuUI.SetGang(self: MenuUIHandle, state: GangState?)
	self.gang = state
	redrawPane(self, "gangs")
end

function MenuUI.SetSkills(self: MenuUIHandle, state: SkillsState?)
	self.skills = state
	redrawPane(self, "skills")
end

function MenuUI.SetBill(self: MenuUIHandle, state: BillState?)
	self.bill = state
	redrawPane(self, "money")
end

function MenuUI.SetSavings(self: MenuUIHandle, state: SavingsState?)
	self.savings = state
	redrawPane(self, "money")
end

function MenuUI.SetHouse(self: MenuUIHandle, state: HouseState?)
	self.house = state
	redrawPane(self, "money")
end

function MenuUI.SetIdentity(self: MenuUIHandle, ageYears: number, stage: string, money: number)
	self.ageYears = ageYears
	self.stage = stage
	self.money = money
	redrawCard(self)
	-- The card is not the only thing holding this number: the money pane's Cash row is the
	-- same balance, and a pane that kept showing the old one while the header above it
	-- showed the new one would be the menu disagreeing with itself on one screen.
	redrawPane(self, "money")
end

function MenuUI.OnColorsToggled(self: MenuUIHandle, callback: (boolean) -> ())
	self.onColorsToggled = callback
end

function MenuUI.SetSettings(self: MenuUIHandle, state: SettingsState)
	self.settings = state
	redrawPane(self, "settings")
end

-- The redeem box now draws inside the settings pane -- see Config.UI.Menu.Tabs -- so it
-- redraws that pane's id, not a "codes" id that no longer names a tab.
function MenuUI.SetCodes(self: MenuUIHandle, state: CodesState)
	self.codes = state
	redrawPane(self, "settings")
end

-- The answer to one redeem attempt.
--
-- Clears the box on success and leaves it alone on failure, which is the only pairing that
-- is right in both directions: a code that worked is done with and a box still holding it
-- invites a second press that can only be refused, whereas a code that was mistyped is one
-- character away from correct and erasing it makes the player type the whole thing again.
function MenuUI.SetCodeResult(self: MenuUIHandle, ok: boolean, message: string)
	self.codeResult = message
	self.codeResultOk = ok
	if ok then
		self.codeDraft = ""
	end
	redrawPane(self, "settings")
end

function MenuUI.OnCodeSubmitted(self: MenuUIHandle, callback: (code: string) -> ())
	self.onCodeSubmitted = callback
end

function MenuUI.OnSettingToggled(self: MenuUIHandle, callback: (id: string, on: boolean) -> ())
	self.onSettingToggled = callback
end

-- A name pressed on the relationships pane. What happens next is not this module's
-- business: the caller decides whether that means opening the panel for somebody
-- standing in front of the player or asking the server to put a call through.
function MenuUI.OnPersonTapped(self: MenuUIHandle, callback: (personId: string) -> ())
	self.onPersonTapped = callback
end

-- The rail comes down with the HUD and goes back up with it, for the reason the HUD
-- itself does: a menu offering seven lists about a life is a claim that a life is being
-- lived, and there is not one yet on the frame before the first push lands.
function MenuUI.SetVisible(self: MenuUIHandle, visible: boolean)
	self.rail.Visible = visible
	if not visible then
		MenuUI.Close(self)
	end
end

-- **Everything below the tweens runs first, and that is the point.** The rows are built,
-- the card is filled and the rail is repainted before a single pixel moves, so the panel is
-- complete and clickable on the frame it becomes visible. The tween is decoration over a
-- finished screen rather than a curtain the player has to wait behind.
function MenuUI.Open(self: MenuUIHandle)
	local wasOpen = self.open
	self.open = true
	self.panel.Visible = true
	self.backdrop.Visible = true
	redrawCard(self)
	-- Animated on a switch as well as on an open. Switching panes replaces every row on
	-- screen, and a list that swaps its contents with no motion at all reads as a redraw
	-- glitch rather than as a different page.
	redraw(self, true)

	if not wasOpen then
		self.panel.Position = self.panelHome + UDim2.fromOffset(-MOTION.EnterPixels, 0)
		self.panel.GroupTransparency = 1
		TweenService:Create(self.panel, ENTER_MOVE, { Position = self.panelHome }):Play()
		TweenService:Create(self.panel, ENTER_FADE, { GroupTransparency = 0 }):Play()
		TweenService:Create(self.backdrop, ENTER_FADE, { BackgroundTransparency = PALETTE.BackdropTransparency }):Play()
		TweenService:Create(self.blur, BLUR_IN, { Size = MOTION.BlurSize }):Play()
	end

	paintRail(self)
end

function MenuUI.Close(self: MenuUIHandle)
	if not self.open then
		return
	end
	self.open = false
	-- The last thing the box said dies with the visit. It is a reply to a keystroke, and a
	-- refusal still sitting there when the player comes back an hour later is answering a
	-- question they no longer remember asking. The draft survives -- that is theirs.
	self.codeResult = ""

	TweenService
		:Create(self.panel, EXIT, {
			Position = self.panelHome + UDim2.fromOffset(-MOTION.EnterPixels, 0),
			GroupTransparency = 1,
		})
		:Play()
	TweenService:Create(self.backdrop, EXIT, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(self.blur, EXIT, { Size = 0 }):Play()

	-- Hidden after the fade rather than with it, and re-checked when the timer comes back.
	-- A player who closes the menu and immediately reopens it -- which is what
	-- double-clicking a rail tile is -- would otherwise have the panel yanked invisible a
	-- tenth of a second into its second entrance.
	task.delay(MOTION.ExitSeconds, function()
		if self.open then
			return
		end
		self.panel.Visible = false
		self.backdrop.Visible = false
	end)

	paintRail(self)
end

function MenuUI.Toggle(self: MenuUIHandle)
	if self.open then
		MenuUI.Close(self)
	else
		MenuUI.Open(self)
	end
end

function MenuUI.IsOpen(self: MenuUIHandle): boolean
	return self.open
end

return MenuUI
