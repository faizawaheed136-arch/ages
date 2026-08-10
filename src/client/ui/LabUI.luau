--!strict
-- The Science lab, drawn.
--
-- Its own panel rather than a row on the HUD, and that is not a size decision. Every
-- other client display in this game is a *report* -- how much money you have, how long
-- is left on a shift -- that the player glances at between doing things. This one is the
-- thing they are doing. For the length of a procedure it is the game's main surface, and
-- a main surface squeezed into the corner beside four stat bars is how an activity ends
-- up feeling like a progress bar with a room around it.
--
-- Bottom left, because the HUD owns the top right and the choice panel owns the middle,
-- and because a player running a procedure is looking at the room -- the panel has to be
-- readable out of the corner of an eye rather than sit where the eye already is.
--
-- **This module draws affordances off `atBoard`, `atBench` and `atCupboard` and off
-- nothing else.** That is the contract LabState states from the other end: the server
-- decides where the player is standing, and every button here is live exactly when the
-- server would honour it. The client never guesses at distance, so there is no version
-- of this where a button lights up and then refuses -- which for an activity whose whole
-- input is *walking somewhere* would be the one bug that makes it unplayable.
--
-- Nothing here decides anything. Steps are taken by clicking a station in the world, not
-- on this panel; the two buttons on it send a bench index and wait to be told what
-- happened.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
-- The station catalogue, shared so that the name and colour on a step chip here are the
-- same name and colour on the model across the room. See shared/world/Stations.luau for
-- why that is a mechanic rather than a nicety.
local Stations = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Stations"))

type LabState = Types.LabState
type BenchState = Types.BenchState

local SCIENCE = Config.School.Science
local SCHOOL = Config.School

-- The panel's own palette. Deliberately not shared with StatsUI's: the lab is a place
-- rather than a readout, and the one thing the player must never do is mistake a step
-- chip for a stat bar while both are on screen.
local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local CAPTION_COLOR = Color3.fromRGB(146, 150, 162)
local TRACK_COLOR = Color3.fromRGB(38, 39, 46)

-- Reagents. One colour, and not a stat green: a supply that runs down is not a score,
-- and the only thing the player needs to read off it is "how many steps until the walk".
local REAGENT_COLOR = Color3.fromRGB(150, 196, 214)
-- The last couple of charges. Orange rather than red for the reason the task bar is:
-- running out costs a trip, not a life.
local REAGENT_LOW_COLOR = Color3.fromRGB(228, 148, 84)
-- The cupboard, filling up rather than running down. Its own colour because the same
-- bar reverses direction while the player stands there, and a bar that changes meaning
-- without changing colour is a bar that gets misread exactly once, at speed.
local REFILL_COLOR = Color3.fromRGB(120, 195, 165)

-- The bench clock, which runs down. Same three-stage language the task rows use, so a
-- player who has worked a shift already knows what the colour change means.
local CLOCK_COLOR = Color3.fromRGB(235, 200, 120)
local CLOCK_URGENT_COLOR = Color3.fromRGB(228, 140, 80)
local CLOCK_URGENT_SHARE = 1 / 3

-- The bench you have in hand. Everything about the active bench is drawn a shade
-- brighter, because "which bench does this click land on" is the single question the
-- player asks most often and it has to be answerable without reading a word.
local ACTIVE_COLOR = Color3.fromRGB(240, 232, 214)
local IDLE_COLOR = Color3.fromRGB(150, 152, 164)

local BUTTON_LIVE_COLOR = Color3.fromRGB(235, 190, 90)
local BUTTON_DEAD_COLOR = Color3.fromRGB(56, 57, 66)
local BUTTON_LIVE_TEXT = Color3.fromRGB(26, 22, 12)
local BUTTON_DEAD_TEXT = Color3.fromRGB(130, 132, 142)

local GOOD_COLOR = Color3.fromRGB(90, 200, 120)
local OK_COLOR = Color3.fromRGB(226, 200, 110)
local POOR_COLOR = Color3.fromRGB(214, 108, 92)

local NOTICE_COLOR = Color3.fromRGB(232, 176, 120)

local PANEL_WIDTH = 300

local LabUI = {}
LabUI.__index = LabUI

-- The parts of one bench block anything ever writes to. Built once at startup for both
-- benches -- see `new` -- so the panel never changes height when the second bench opens,
-- which is precisely the moment the player is reading the first one.
type BenchBlock = {
	frame: Frame,
	title: TextLabel,
	stack: TextLabel,
	track: Frame,
	fill: Frame,
	verdict: TextLabel,
}

export type LabUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		titleLabel: TextLabel,
		masteryLabel: TextLabel,
		reagentLabel: TextLabel,
		reagentTrack: Frame,
		reagentFill: Frame,
		boardFrame: Frame,
		boardLabel: TextLabel,
		benchBlocks: { BenchBlock },
		buttonRow: Frame,
		undoButton: TextButton,
		commitButton: TextButton,
		buttonHint: TextLabel,
		noticeLabel: TextLabel,
		summaryLabel: TextLabel,
		-- The bench the two buttons are currently pointed at, which is whatever the last
		-- push said the player was standing at. Held rather than read back off the state
		-- because a click arrives between pushes and has to send *something*; nil is a
		-- button that does nothing, and it is drawn dead so it is never clicked.
		activeBench: number?,
		onUndo: ((benchIndex: number) -> ())?,
		onCommit: ((benchIndex: number) -> ())?,
	},
	LabUI
))

local function formatClock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- A station's name in its own colour, for a RichText label.
--
-- Rich text rather than a chip instance per step, and that is worth stating because the
-- instance version was the obvious build. A procedure is up to ten steps across two
-- benches plus a revealed window, so the chip version is thirty-odd frames created and
-- destroyed on a stack that changes every time the player clicks anything -- four times
-- a second in the worst case. One label that wraps is both cheaper and, more usefully,
-- impossible to leave stale: there is nothing to forget to destroy.
local function colored(stationId: string): string
	local station = Stations.Get(stationId)
	if station == nil then
		-- An id nothing authors any more, which a live life can genuinely be holding.
		-- Said plainly rather than dropped: a step that vanishes off a stack is worse
		-- than one the player does not recognise.
		return stationId
	end
	return string.format(
		'<font color="rgb(%d,%d,%d)">%s</font>',
		math.round(station.color.R * 255),
		math.round(station.color.G * 255),
		math.round(station.color.B * 255),
		station.name
	)
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

local function makeBenchBlock(parent: Instance, order: number): BenchBlock
	local frame = Instance.new("Frame")
	frame.Name = "BenchBlock"
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = order
	frame.Visible = false
	frame.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 17)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = IDLE_COLOR
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = ""
	title.LayoutOrder = 0
	title.Parent = frame

	local stack = makeCaption(frame, 1, 12, CAPTION_COLOR)
	local verdict = makeCaption(frame, 2, 12, CAPTION_COLOR)

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 4)
	track.BackgroundColor3 = TRACK_COLOR
	track.BorderSizePixel = 0
	track.LayoutOrder = 3
	track.Parent = frame

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = CLOCK_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track

	return { frame = frame, title = title, stack = stack, track = track, fill = fill, verdict = verdict }
end

local function makeButton(parent: Instance, order: number, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = text .. "Button"
	button.Size = UDim2.new(0.5, -3, 1, 0)
	button.BackgroundColor3 = BUTTON_DEAD_COLOR
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.TextColor3 = BUTTON_DEAD_TEXT
	button.Text = text
	button.LayoutOrder = order
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	return button
end

function LabUI.new(): LabUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesLab"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 2

	local panel = Instance.new("Frame")
	panel.Name = "LabPanel"
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
	titleLabel.TextColor3 = TITLE_COLOR
	titleLabel.Text = "Science lab"
	titleLabel.LayoutOrder = 0
	titleLabel.Parent = panel

	-- The mastery line, and it is on screen for a reason that is not bookkeeping. What a
	-- level buys is invisible by nature -- it is a list getting longer on a board the
	-- player is only sometimes standing at -- so without this the one progression the
	-- verb has would arrive unannounced and be mistaken for the board behaving oddly.
	local masteryLabel = makeCaption(panel, 1, 12, CAPTION_COLOR)

	local reagentLabel = makeCaption(panel, 2, 12, CAPTION_COLOR)

	local reagentTrack = Instance.new("Frame")
	reagentTrack.Name = "ReagentTrack"
	reagentTrack.Size = UDim2.new(1, 0, 0, 5)
	reagentTrack.BackgroundColor3 = TRACK_COLOR
	reagentTrack.BorderSizePixel = 0
	reagentTrack.LayoutOrder = 3
	reagentTrack.Parent = panel

	local reagentFill = Instance.new("Frame")
	reagentFill.Name = "Fill"
	reagentFill.Size = UDim2.new(1, 0, 1, 0)
	reagentFill.BackgroundColor3 = REAGENT_COLOR
	reagentFill.BorderSizePixel = 0
	reagentFill.Parent = reagentTrack

	-- The board's window. Visible only while the player stands at the board, which is the
	-- entire verb: see the note on BenchState.revealed. Drawn as its own framed block so
	-- that walking up to the board is a visible event on the panel and not a caption
	-- quietly changing somewhere in the middle of it.
	local boardFrame = Instance.new("Frame")
	boardFrame.Name = "Board"
	boardFrame.Size = UDim2.new(1, 0, 0, 0)
	boardFrame.AutomaticSize = Enum.AutomaticSize.Y
	boardFrame.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
	boardFrame.BackgroundTransparency = 0.2
	boardFrame.BorderSizePixel = 0
	boardFrame.LayoutOrder = 4
	boardFrame.Visible = false
	boardFrame.Parent = panel

	local boardCorner = Instance.new("UICorner")
	boardCorner.CornerRadius = UDim.new(0, 6)
	boardCorner.Parent = boardFrame

	local boardPadding = Instance.new("UIPadding")
	boardPadding.PaddingTop = UDim.new(0, 6)
	boardPadding.PaddingBottom = UDim.new(0, 6)
	boardPadding.PaddingLeft = UDim.new(0, 8)
	boardPadding.PaddingRight = UDim.new(0, 8)
	boardPadding.Parent = boardFrame

	local boardLabel = makeCaption(boardFrame, 0, 12, TITLE_COLOR)

	-- Both benches built now, not when the second opens. A block that appears mid-run
	-- pushes everything below it down the screen at the exact moment the player is
	-- reading a stack off it -- the same reason StatsUI builds both task rows up front.
	local benchBlocks: { BenchBlock } = {}
	for index = 1, SCIENCE.Benches do
		table.insert(benchBlocks, makeBenchBlock(panel, 4 + index))
	end

	local buttonRow = Instance.new("Frame")
	buttonRow.Name = "Buttons"
	buttonRow.Size = UDim2.new(1, 0, 0, 30)
	buttonRow.BackgroundTransparency = 1
	buttonRow.LayoutOrder = 20
	buttonRow.Parent = panel

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Padding = UDim.new(0, 6)
	buttonLayout.Parent = buttonRow

	local undoButton = makeButton(buttonRow, 0, "Undo")
	local commitButton = makeButton(buttonRow, 1, "Commit")

	-- Why the buttons are dead, said out loud. Without it the player standing in the
	-- middle of the room reads two grey buttons as the game having stopped working,
	-- rather than as an instruction to walk five steps.
	local buttonHint = makeCaption(panel, 21, 11, CAPTION_COLOR)

	local noticeLabel = makeCaption(panel, 22, 12, NOTICE_COLOR)
	local summaryLabel = makeCaption(panel, 23, 13, TITLE_COLOR)

	screenGui.Parent = playerGui

	local self = setmetatable({
		screenGui = screenGui,
		panel = panel,
		titleLabel = titleLabel,
		masteryLabel = masteryLabel,
		reagentLabel = reagentLabel,
		reagentTrack = reagentTrack,
		reagentFill = reagentFill,
		boardFrame = boardFrame,
		boardLabel = boardLabel,
		benchBlocks = benchBlocks,
		buttonRow = buttonRow,
		undoButton = undoButton,
		commitButton = commitButton,
		buttonHint = buttonHint,
		noticeLabel = noticeLabel,
		summaryLabel = summaryLabel,
		activeBench = nil,
		onUndo = nil,
		onCommit = nil,
	}, LabUI)

	undoButton.Activated:Connect(function()
		local bench = self.activeBench
		local callback = self.onUndo
		if bench ~= nil and callback ~= nil then
			callback(bench)
		end
	end)

	commitButton.Activated:Connect(function()
		local bench = self.activeBench
		local callback = self.onCommit
		if bench ~= nil and callback ~= nil then
			callback(bench)
		end
	end)

	return self
end

-- One bench, drawn. Three states and they look nothing like each other on purpose: a
-- committed bench is a result, an active bench is a thing being done, and an idle bench
-- is a thing waiting -- and a player glancing down has to tell them apart before reading.
local function drawBench(block: BenchBlock, state: BenchState)
	block.frame.Visible = true

	if state.committed then
		block.title.TextColor3 = IDLE_COLOR
		block.title.Text = `{state.name} -- done`

		local score = state.score or 0
		local color: Color3
		if score >= SCHOOL.GoodShare then
			color = GOOD_COLOR
		elseif score >= SCHOOL.OkShare then
			color = OK_COLOR
		else
			color = POOR_COLOR
		end
		block.stack.TextColor3 = color
		block.stack.Text = `{math.round(score * 100)}%`
		-- The sentence, not just the number. A score with nothing attached teaches
		-- nothing, which is the same reason a question carries a `because` line.
		block.verdict.Text = state.verdict or ""
		block.verdict.Visible = state.verdict ~= nil
		block.track.Visible = false
		return
	end

	block.track.Visible = true
	block.verdict.Visible = false

	local taken = state.taken
	block.title.TextColor3 = if state.active then ACTIVE_COLOR else IDLE_COLOR
	local suffix = if state.active then "" else "  (walk over to use)"
	block.title.Text = `{state.name} -- {#taken}/{state.total}{suffix}`

	-- What has been done, in order, in the stations' own colours. Deliberately the whole
	-- stack rather than the last few: this is the bench's *record*, and the board only
	-- ever shows what comes next, so if this were trimmed there would be no surface in
	-- the game that answers "wait, did I already do the balance?".
	if #taken == 0 then
		block.stack.TextColor3 = CAPTION_COLOR
		block.stack.Text = "Nothing done yet."
	else
		local parts: { string } = {}
		for _, stationId in taken do
			table.insert(parts, colored(stationId))
		end
		block.stack.TextColor3 = CAPTION_COLOR
		block.stack.Text = table.concat(parts, " > ")
	end

	local share = if state.secondsTotal > 0 then state.secondsLeft / state.secondsTotal else 0
	block.fill.Size = UDim2.new(math.clamp(share, 0, 1), 0, 1, 0)
	block.fill.BackgroundColor3 = if share <= CLOCK_URGENT_SHARE then CLOCK_URGENT_COLOR else CLOCK_COLOR
end

-- The board, which is only ever drawn while standing at it.
local function drawBoard(self: LabUIHandle, state: LabState)
	if not state.atBoard then
		self.boardFrame.Visible = false
		return
	end

	local lines: { string } = {}
	for _, bench in state.benches do
		if bench.committed then
			continue
		end

		-- An empty window on a bench that is still open means the stack has reached the
		-- end of the procedure -- see BenchState.revealedFrom. Said out loud rather than
		-- skipped, because the player is standing at the board precisely to find out what
		-- is next, and a bench that quietly disappears off it reads as the game having
		-- lost their work.
		if #bench.revealed == 0 then
			table.insert(lines, `<b>{bench.name}</b>  --  that is all {bench.total} steps. Go and commit it.`)
			continue
		end

		local last = bench.revealedFrom + #bench.revealed - 1
		table.insert(lines, `<b>{bench.name}</b>  --  steps {bench.revealedFrom}-{last} of {bench.total}`)
		for offset, step in bench.revealed do
			table.insert(lines, `   {bench.revealedFrom + offset - 1}. {colored(step.station)}  {step.label}`)
		end
		-- Said only when there is a tail, and said every time there is one. A player who
		-- cannot see that the procedure continues past what is on the board has no way to
		-- know a level would buy them anything, which turns the one progression this verb
		-- has into a number that changes silently.
		if last < bench.total then
			table.insert(lines, `   <i>...{bench.total - last} more, out of sight for now.</i>`)
		end
	end

	if #lines == 0 then
		self.boardFrame.Visible = false
		return
	end

	self.boardFrame.Visible = true
	self.boardLabel.Text = table.concat(lines, "\n")
end

local function drawReagents(self: LabUIHandle, state: LabState)
	if state.atCupboard and state.charges < state.chargesMax then
		-- The same bar, running the other way. Colour changes with the direction because
		-- a bar that reverses meaning without changing colour gets misread exactly once,
		-- and it will be while the player is in a hurry.
		self.reagentFill.BackgroundColor3 = REFILL_COLOR
		self.reagentFill.Size = UDim2.new(math.clamp(state.refillProgress, 0, 1), 0, 1, 0)
		self.reagentLabel.TextColor3 = REFILL_COLOR
		self.reagentLabel.Text = "Refilling -- stay at the cupboard"
		return
	end

	local share = if state.chargesMax > 0 then state.charges / state.chargesMax else 0
	self.reagentFill.Size = UDim2.new(math.clamp(share, 0, 1), 0, 1, 0)

	if state.charges <= 0 then
		self.reagentFill.BackgroundColor3 = REAGENT_LOW_COLOR
		self.reagentLabel.TextColor3 = REAGENT_LOW_COLOR
		self.reagentLabel.Text = "Out of reagents -- go to the supply cupboard"
	elseif state.charges <= SCIENCE.ChargesPerStep * 2 then
		self.reagentFill.BackgroundColor3 = REAGENT_LOW_COLOR
		self.reagentLabel.TextColor3 = REAGENT_LOW_COLOR
		self.reagentLabel.Text = `Reagents {state.charges}/{state.chargesMax} -- nearly out`
	else
		self.reagentFill.BackgroundColor3 = REAGENT_COLOR
		self.reagentLabel.TextColor3 = CAPTION_COLOR
		self.reagentLabel.Text = `Reagents {state.charges}/{state.chargesMax}`
	end
end

local function drawButtons(self: LabUIHandle, state: LabState)
	-- The bench the player is standing at, and only if it is still a bench they can act
	-- on. A committed bench is still a bench you are standing at, and the server would
	-- refuse both verbs on it -- so it is drawn dead here rather than allowed to send.
	local at = state.atBench
	local bench: BenchState? = nil
	if at ~= nil then
		for _, candidate in state.benches do
			if candidate.index == at and not candidate.committed then
				bench = candidate
				break
			end
		end
	end

	if bench == nil then
		self.activeBench = nil
		for _, button in { self.undoButton, self.commitButton } do
			button.BackgroundColor3 = BUTTON_DEAD_COLOR
			button.TextColor3 = BUTTON_DEAD_TEXT
			button.AutoButtonColor = false
		end
		self.undoButton.Text = "Undo"
		self.commitButton.Text = "Commit"
		self.buttonHint.Text = "Stand at a bench to undo a step or commit it."
		return
	end

	self.activeBench = bench.index
	self.commitButton.BackgroundColor3 = BUTTON_LIVE_COLOR
	self.commitButton.TextColor3 = BUTTON_LIVE_TEXT
	self.commitButton.AutoButtonColor = true
	self.commitButton.Text = "Commit"

	-- Undo is live only when there is something to take back. Grey with nothing on the
	-- stack rather than live-and-refusing, because the panel's whole promise is that a
	-- button you can press is a button that does something.
	local canUndo = #bench.taken > 0
	self.undoButton.BackgroundColor3 = if canUndo then BUTTON_LIVE_COLOR else BUTTON_DEAD_COLOR
	self.undoButton.TextColor3 = if canUndo then BUTTON_LIVE_TEXT else BUTTON_DEAD_TEXT
	self.undoButton.AutoButtonColor = canUndo
	self.undoButton.Text = "Undo"

	-- Naming the cost, because undo being free of *charges* is the one thing about it a
	-- player will assume wrongly. The reagent is spent when the step is taken; taking the
	-- step back does not put it back in the cupboard.
	self.buttonHint.Text = if canUndo
		then `{bench.name} -- {formatClock(bench.secondsLeft)} left. Undo does not return the reagent.`
		else `{bench.name} -- {formatClock(bench.secondsLeft)} left.`
end

-- The whole panel, from one snapshot. Nil is the usual state and takes it down.
function LabUI.Set(self: LabUIHandle, state: LabState?)
	if state == nil then
		self.panel.Visible = false
		self.activeBench = nil
		return
	end

	self.panel.Visible = true

	-- The summary replaces the working panel for a beat at the end. Everything else goes
	-- away under it: a stack and a clock still on screen beside "that is the lesson over"
	-- is the panel arguing with itself.
	local summary = state.summary
	if summary ~= nil then
		self.summaryLabel.Visible = true
		self.summaryLabel.Text = summary
		self.masteryLabel.Visible = false
		self.reagentLabel.Visible = false
		self.reagentTrack.Visible = false
		self.boardFrame.Visible = false
		self.buttonRow.Visible = false
		self.buttonHint.Visible = false
		self.noticeLabel.Visible = false
		for _, block in self.benchBlocks do
			block.frame.Visible = false
		end
		return
	end

	self.summaryLabel.Visible = false
	self.masteryLabel.Visible = true
	self.reagentLabel.Visible = true
	self.reagentTrack.Visible = true
	self.buttonRow.Visible = true
	self.buttonHint.Visible = true

	if state.level >= state.levelMax then
		self.masteryLabel.Text = `Lab skill {state.level} of {state.levelMax} -- the whole board at once`
	else
		local left = state.passesPerLevel - state.passes
		local word = if left == 1 then "run" else "runs"
		self.masteryLabel.Text =
			`Lab skill {state.level} of {state.levelMax} -- {left} good {word} to see one more step`
	end

	drawReagents(self, state)
	drawBoard(self, state)
	drawButtons(self, state)

	for index, block in self.benchBlocks do
		local bench = state.benches[index]
		if bench == nil then
			block.frame.Visible = false
		else
			drawBench(block, bench)
		end
	end

	local notice = state.notice
	self.noticeLabel.Visible = notice ~= nil
	self.noticeLabel.Text = notice or ""
end

function LabUI.OnUndo(self: LabUIHandle, callback: (benchIndex: number) -> ())
	self.onUndo = callback
end

function LabUI.OnCommit(self: LabUIHandle, callback: (benchIndex: number) -> ())
	self.onCommit = callback
end

return LabUI
