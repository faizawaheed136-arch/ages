--!strict
-- The art canvas, drawn.
--
-- Bottom left, the same corner and the same palette as the lab's panel, because the two
-- can never be on screen together -- one subject occupies the afternoon -- and a player
-- who has learned where the school's activity surface lives should not have to learn it
-- twice.
--
-- **The one rule this file exists to hold: nothing here may ever mark a cell as wrong.**
--
-- No outline on a stale cell, no tick on a right one, no arrow, no count in the corner of
-- a square. The state this panel is handed does not contain the study and does not contain
-- a list of stale cells, and both of those omissions are deliberate on the server's side --
-- but the omission that matters is this one, because it is the one a well-meaning
-- afternoon of polish would undo. The subject is *comparing the canvas to the wall*. A
-- panel that did the comparing would leave the player a form to fill in, and the change
-- would look like an improvement in every screenshot.
--
-- The number of stale cells is shown. Which ones are not. That gap is the game.
--
-- **This module draws affordances off `atEasel` and `atCupboard` and off nothing else.**
-- Same contract LabUI holds: the server decides where the player is standing and every
-- control here is live exactly when the server would honour it, so there is no version of
-- this where a cell lights up under the cursor and then refuses the click.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type ArtState = Types.ArtState

local ART = Config.School.Art

-- The panel's own palette, copied from LabUI rather than shared with it. Two activity
-- surfaces that look alike should look alike because somebody decided they should, and a
-- shared constants file would mean re-colouring the lab silently re-colours the art room.
local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local CAPTION_COLOR = Color3.fromRGB(146, 150, 162)
local TRACK_COLOR = Color3.fromRGB(38, 39, 46)

-- Bare canvas. Deliberately not white and deliberately not any pigment's colour: white is
-- paint you can be handed, and an unpainted cell drawn in it would be a cell the player
-- believes they have already done.
local BLANK_COLOR = Color3.fromRGB(52, 50, 46)

-- The tube in hand. A ring around the swatch rather than a change to the swatch's own
-- colour, because the swatch *is* the paint and tinting it would be lying about what is
-- about to come out of the brush.
local HELD_STROKE_COLOR = Color3.fromRGB(240, 232, 214)

-- Paint in the pot, running down, and the last few. The same two-stage language the lab's
-- reagent bar uses, and orange rather than red for the same reason: running out costs a
-- walk, not a lesson.
local PAINT_COLOR = Color3.fromRGB(150, 196, 214)
local PAINT_LOW_COLOR = Color3.fromRGB(228, 148, 84)
local PAINT_LOW_SHARE = 1 / 4

-- The canvas clock.
local CLOCK_COLOR = Color3.fromRGB(235, 200, 120)
local CLOCK_URGENT_COLOR = Color3.fromRGB(228, 140, 80)
local CLOCK_URGENT_SHARE = 1 / 3

-- The debt. One colour, and it is the only warm thing on the panel that is not a clock,
-- because "three cells have gone" is the single line the player has to notice while
-- looking somewhere else entirely.
local STALE_COLOR = Color3.fromRGB(228, 168, 110)
local SETTLED_COLOR = Color3.fromRGB(120, 195, 165)

local BUTTON_LIVE_COLOR = Color3.fromRGB(235, 190, 90)
local BUTTON_DEAD_COLOR = Color3.fromRGB(56, 57, 66)
local BUTTON_LIVE_TEXT = Color3.fromRGB(26, 22, 12)
local BUTTON_DEAD_TEXT = Color3.fromRGB(130, 132, 142)

local NOTICE_COLOR = Color3.fromRGB(232, 176, 120)

-- Wider than the lab's, because this one contains a picture rather than a list. At 316
-- with a four-wide canvas a cell is sixty-eight pixels, which is a comfortable click
-- target on a phone and still leaves the panel narrower than a third of a tablet.
local PANEL_WIDTH = 316
local CELL_GAP = 4
local SWATCH_SIZE = 30

local COLUMNS = ART.Columns
local ROWS = ART.Rows
local CELLS = COLUMNS * ROWS

-- Every tube any rung could ever hand over, which is how many swatch buttons get built.
-- Built once at the maximum rather than rebuilt per push for the reason the lab builds
-- both bench blocks up front: the panel must not change height at the moment a player
-- levels up, because that is precisely when they are reading it.
local MAX_TUBES = 0
for _, count in ART.PaletteByLevel do
	if count > MAX_TUBES then
		MAX_TUBES = count
	end
end

local CELL_PIXELS = math.floor((PANEL_WIDTH - 24 - (COLUMNS - 1) * CELL_GAP) / COLUMNS)

local EaselUI = {}
EaselUI.__index = EaselUI

export type EaselUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		titleLabel: TextLabel,
		masteryLabel: TextLabel,
		canvasFrame: Frame,
		cells: { TextButton },
		paletteFrame: Frame,
		swatches: { TextButton },
		paletteHint: TextLabel,
		paintTrack: Frame,
		paintFill: Frame,
		progressLabel: TextLabel,
		clockTrack: Frame,
		clockFill: Frame,
		signButton: TextButton,
		noticeLabel: TextLabel,
		summaryLabel: TextLabel,
		-- The tube the player has clicked, as an index into the palette they were last
		-- pushed. Held here rather than read back off the state on every frame because a
		-- click has to feel instant: waiting a quarter of a second to see which colour is in
		-- your hand would make picking paint feel like it might not have worked.
		selected: number?,
		-- The ids behind the swatches, in palette order, so a cell click can name the
		-- pigment it wants without the server and the client having to agree on an index.
		-- Ids rather than positions on purpose: a palette that grew between the click and
		-- the send would otherwise paint the wrong colour.
		tubeIds: { string },
		onPaint: ((cellIndex: number, pigmentId: string) -> ())?,
		onSign: (() -> ())?,
	},
	EaselUI
))

local function formatClock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function makeCaption(parent: Instance, order: number, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = size
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.RichText = true
	label.TextColor3 = color
	label.Text = ""
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

local function makeTrack(parent: Instance, order: number, height: number, fillColor: Color3): (Frame, Frame)
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, height)
	track.BackgroundColor3 = TRACK_COLOR
	track.BorderSizePixel = 0
	track.LayoutOrder = order
	track.Parent = parent

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Parent = track

	return track, fill
end

function EaselUI.new(): EaselUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesEasel"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 2

	local panel = Instance.new("Frame")
	panel.Name = "EaselPanel"
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 16, 1, -16)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.1
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

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = panel

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 16
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.TextColor3 = TITLE_COLOR
	titleLabel.Text = "Art"
	titleLabel.LayoutOrder = 0
	titleLabel.Parent = panel

	local masteryLabel = makeCaption(panel, 1, 12, CAPTION_COLOR)

	-- The canvas. A grid of buttons and nothing else -- no borders between cells beyond
	-- the gap, no coordinates, no numbers. It has to read as a painting rather than as a
	-- spreadsheet, because the thing it is being held up against is a picture on a wall.
	local canvasFrame = Instance.new("Frame")
	canvasFrame.Name = "Canvas"
	canvasFrame.Size = UDim2.new(1, 0, 0, ROWS * CELL_PIXELS + (ROWS - 1) * CELL_GAP)
	canvasFrame.BackgroundTransparency = 1
	canvasFrame.LayoutOrder = 2
	canvasFrame.Parent = panel

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, CELL_PIXELS, 0, CELL_PIXELS)
	grid.CellPadding = UDim2.new(0, CELL_GAP, 0, CELL_GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirectionMaxCells = COLUMNS
	grid.Parent = canvasFrame

	local cells: { TextButton } = {}
	for index = 1, CELLS do
		local cell = Instance.new("TextButton")
		cell.Name = `Cell{index}`
		cell.BackgroundColor3 = BLANK_COLOR
		cell.BorderSizePixel = 0
		cell.AutoButtonColor = false
		cell.Text = ""
		cell.LayoutOrder = index
		cell.Parent = canvasFrame

		local cellCorner = Instance.new("UICorner")
		cellCorner.CornerRadius = UDim.new(0, 3)
		cellCorner.Parent = cell

		cells[index] = cell
	end

	-- The tubes. In palette order, which is most-used-in-this-picture first, so the
	-- colours a lower rung would not have had are always the ones on the right -- levelling
	-- up is the row getting longer at the end rather than reshuffling.
	local paletteFrame = Instance.new("Frame")
	paletteFrame.Name = "Palette"
	paletteFrame.Size = UDim2.new(1, 0, 0, SWATCH_SIZE)
	paletteFrame.BackgroundTransparency = 1
	paletteFrame.LayoutOrder = 3
	paletteFrame.Parent = panel

	local paletteLayout = Instance.new("UIListLayout")
	paletteLayout.FillDirection = Enum.FillDirection.Horizontal
	paletteLayout.SortOrder = Enum.SortOrder.LayoutOrder
	paletteLayout.Padding = UDim.new(0, CELL_GAP)
	paletteLayout.Parent = paletteFrame

	local swatches: { TextButton } = {}
	for index = 1, MAX_TUBES do
		local swatch = Instance.new("TextButton")
		swatch.Name = `Tube{index}`
		swatch.Size = UDim2.new(0, SWATCH_SIZE, 0, SWATCH_SIZE)
		swatch.BackgroundColor3 = BLANK_COLOR
		swatch.BorderSizePixel = 0
		swatch.AutoButtonColor = false
		swatch.Text = ""
		swatch.Visible = false
		swatch.LayoutOrder = index
		swatch.Parent = paletteFrame

		local swatchCorner = Instance.new("UICorner")
		swatchCorner.CornerRadius = UDim.new(1, 0)
		swatchCorner.Parent = swatch

		local stroke = Instance.new("UIStroke")
		stroke.Name = "Held"
		stroke.Color = HELD_STROKE_COLOR
		stroke.Thickness = 2
		stroke.Enabled = false
		stroke.Parent = swatch

		swatches[index] = swatch
	end

	local paletteHint = makeCaption(panel, 4, 11, CAPTION_COLOR)

	local paintTrack, paintFill = makeTrack(panel, 5, 4, PAINT_COLOR)
	local progressLabel = makeCaption(panel, 6, 12, CAPTION_COLOR)
	local clockTrack, clockFill = makeTrack(panel, 7, 4, CLOCK_COLOR)

	local signButton = Instance.new("TextButton")
	signButton.Name = "SignButton"
	signButton.Size = UDim2.new(1, 0, 0, 28)
	signButton.BackgroundColor3 = BUTTON_DEAD_COLOR
	signButton.BorderSizePixel = 0
	signButton.AutoButtonColor = false
	signButton.Font = Enum.Font.GothamBold
	signButton.TextSize = 13
	signButton.TextColor3 = BUTTON_DEAD_TEXT
	signButton.Text = "Sign it"
	signButton.LayoutOrder = 8
	signButton.Parent = panel

	local signCorner = Instance.new("UICorner")
	signCorner.CornerRadius = UDim.new(0, 6)
	signCorner.Parent = signButton

	local noticeLabel = makeCaption(panel, 9, 12, NOTICE_COLOR)
	local summaryLabel = makeCaption(panel, 10, 13, TITLE_COLOR)

	screenGui.Parent = playerGui

	local self: EaselUIHandle = setmetatable({
		screenGui = screenGui,
		panel = panel,
		titleLabel = titleLabel,
		masteryLabel = masteryLabel,
		canvasFrame = canvasFrame,
		cells = cells,
		paletteFrame = paletteFrame,
		swatches = swatches,
		paletteHint = paletteHint,
		paintTrack = paintTrack,
		paintFill = paintFill,
		progressLabel = progressLabel,
		clockTrack = clockTrack,
		clockFill = clockFill,
		signButton = signButton,
		noticeLabel = noticeLabel,
		summaryLabel = summaryLabel,
		selected = nil,
		tubeIds = {},
		onPaint = nil,
		onSign = nil,
	}, EaselUI)

	for index, swatch in swatches do
		swatch.Activated:Connect(function()
			-- Picking paint up is pure client state. It sends nothing, costs nothing and
			-- cannot be refused -- the server only ever hears about it when a cell is
			-- actually painted, which is the only moment it means anything.
			if self.tubeIds[index] == nil then
				return
			end
			self.selected = index
			self:_drawPalette()
		end)
	end

	for index, cell in cells do
		cell.Activated:Connect(function()
			local slot = self.selected
			if slot == nil then
				return
			end
			local id = self.tubeIds[slot]
			local handler = self.onPaint
			if id == nil or handler == nil then
				return
			end
			handler(index, id)
		end)
	end

	signButton.Activated:Connect(function()
		local handler = self.onSign
		if handler ~= nil then
			handler()
		end
	end)

	return self
end

-- Redraws the tube row off `selected` and `tubeIds`. Split out because a swatch click
-- has to change the ring immediately, before the server has said anything back, and the
-- alternative was the whole panel redrawing itself from a state it does not have yet.
function EaselUI._drawPalette(self: EaselUIHandle)
	for index, swatch in self.swatches do
		local stroke = swatch:FindFirstChild("Held")
		if stroke ~= nil and stroke:IsA("UIStroke") then
			stroke.Enabled = self.selected == index and self.tubeIds[index] ~= nil
		end
	end
end

-- The mastery line, phrased as the thing itself rather than as a score. "Two good
-- lessons until you are given another colour" is a sentence about painting; "art 2/5" is
-- a sentence about a database, and a player reading the second one has been told the
-- progression is bookkeeping.
local function masterySentence(state: ArtState): string
	if state.level >= state.levelMax then
		return "You have the whole box. Art can be skipped."
	end
	local left = math.max(1, state.passesPerLevel - state.passes)
	local word = if left == 1 then "lesson" else "lessons"
	return `{left} good {word} until you are handed another colour.`
end

function EaselUI.Set(self: EaselUIHandle, state: ArtState?)
	if state == nil then
		self.panel.Visible = false
		self.selected = nil
		self.tubeIds = {}
		return
	end

	self.panel.Visible = true

	-- The closing line, alone. Everything else goes, including the canvas: the painting is
	-- finished and on the wall of a classroom somewhere, and leaving a grid of squares up
	-- underneath a verdict invites one more click at something that is no longer listening.
	local closing = state.summary
	if closing ~= nil then
		self.titleLabel.Text = state.title
		self.masteryLabel.Visible = false
		self.canvasFrame.Visible = false
		self.paletteFrame.Visible = false
		self.paletteHint.Visible = false
		self.paintTrack.Visible = false
		self.progressLabel.Visible = false
		self.clockTrack.Visible = false
		self.signButton.Visible = false
		self.noticeLabel.Visible = false
		self.summaryLabel.Visible = true
		self.summaryLabel.Text = closing
		return
	end

	self.titleLabel.Text = state.title
	self.masteryLabel.Visible = true
	self.masteryLabel.Text = masterySentence(state)
	self.canvasFrame.Visible = true
	self.paletteFrame.Visible = true
	self.paletteHint.Visible = true
	self.paintTrack.Visible = true
	self.progressLabel.Visible = true
	self.clockTrack.Visible = true
	self.signButton.Visible = true
	self.summaryLabel.Visible = false

	-- The canvas. Painted cells in their own paint, everything else bare -- and nothing
	-- else, ever. See the note at the top of this file: the moment a cell here carries a
	-- mark saying it is wrong, the subject is gone.
	for index, cell in self.cells do
		local color = state.painted[index]
		cell.BackgroundColor3 = if color ~= nil then color else BLANK_COLOR
		-- Greyed away from the easel, which is the whole of what "you cannot paint from
		-- over here" needs to look like. The cells stay readable because the player is
		-- still allowed to *plan* from the cupboard -- they just cannot put paint down.
		cell.BackgroundTransparency = if state.atEasel then 0 else 0.45
	end

	local tubeIds: { string } = {}
	for index, swatch in self.swatches do
		local tube = state.palette[index]
		swatch.Visible = tube ~= nil
		if tube ~= nil then
			swatch.BackgroundColor3 = tube.color
			tubeIds[index] = tube.id
		end
	end
	self.tubeIds = tubeIds

	-- Seeded from the server's idea of what is in hand, and only while nothing is picked.
	-- After that the local selection wins, because it is the one the player just made.
	if self.selected == nil then
		self.selected = state.held
	end
	if self.selected ~= nil and tubeIds[self.selected] == nil then
		-- The palette shrank under a held tube, which only a debug level change does. Let
		-- go rather than silently pointing at a different colour.
		self.selected = nil
	end
	self:_drawPalette()

	local named = if self.selected ~= nil then state.palette[self.selected] else nil
	self.paletteHint.Text = if named ~= nil
		then `Brush: {named.name}`
		else "Pick a colour, then tap the canvas."

	local paintShare = if state.strokesMax > 0 then state.strokes / state.strokesMax else 0
	self.paintFill.Size = UDim2.new(math.clamp(paintShare, 0, 1), 0, 1, 0)
	self.paintFill.BackgroundColor3 = if paintShare <= PAINT_LOW_SHARE then PAINT_LOW_COLOR else PAINT_COLOR

	-- One line carrying all three of the things the player has to weigh: how much canvas
	-- is covered, how much of it has gone stale, and how much paint is left to do anything
	-- about either. Deliberately one line rather than three rows -- the decision is a
	-- comparison between them, and a player who has to read three separate numbers to make
	-- it is being asked to do the arithmetic the panel should have already done.
	local staleText = if state.stale > 0
		then string.format(
			'<font color="rgb(%d,%d,%d)">%d stale</font>',
			math.round(STALE_COLOR.R * 255),
			math.round(STALE_COLOR.G * 255),
			math.round(STALE_COLOR.B * 255),
			state.stale
		)
		else string.format(
			'<font color="rgb(%d,%d,%d)">all matching</font>',
			math.round(SETTLED_COLOR.R * 255),
			math.round(SETTLED_COLOR.G * 255),
			math.round(SETTLED_COLOR.B * 255)
		)
	self.progressLabel.Text =
		`{state.filled}/{CELLS} painted · {staleText} · {state.strokes} paint · {formatClock(state.secondsLeft)}`

	local clockShare = if ART.SecondsPerCanvas > 0 then state.secondsLeft / ART.SecondsPerCanvas else 0
	self.clockFill.Size = UDim2.new(math.clamp(clockShare, 0, 1), 0, 1, 0)
	self.clockFill.BackgroundColor3 = if clockShare <= CLOCK_URGENT_SHARE then CLOCK_URGENT_COLOR else CLOCK_COLOR

	-- Live only at the easel, because that is the only place the server will take it.
	local canSign = state.atEasel
	self.signButton.BackgroundColor3 = if canSign then BUTTON_LIVE_COLOR else BUTTON_DEAD_COLOR
	self.signButton.TextColor3 = if canSign then BUTTON_LIVE_TEXT else BUTTON_DEAD_TEXT
	self.signButton.Text = if canSign
		then "Sign it"
		elseif state.atCupboard then "Filling up — go back to the easel"
		else "Go back to the easel"

	local notice = state.notice
	self.noticeLabel.Visible = notice ~= nil
	self.noticeLabel.Text = notice or ""
end

function EaselUI.Destroy(self: EaselUIHandle)
	self.screenGui:Destroy()
end

return EaselUI
