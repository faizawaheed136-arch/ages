--!strict
-- The reading board, drawn.
--
-- Bottom left, the same corner and the same palette as the lab and the easel, because the
-- three can never be on screen together -- one subject occupies the afternoon -- and a
-- player who has learned where the school\'s activity surface lives should not have to learn
-- it three times.
--
-- **The one rule this file exists to hold: nothing here may ever mark a placed letter as
-- right or wrong.**
--
-- No green square, no red outline, no tick, no count of how many are correct. The state this
-- panel is handed does not contain the answer and that omission is deliberate on the
-- server\'s side -- but the omission that matters is this one, because it is the one a
-- well-meaning afternoon of polish would undo. The subject is *looking at a word and seeing
-- what it is missing*. A panel that confirmed each letter would leave the player a form to
-- fill in, and the change would look like an improvement in every screenshot.
--
-- The takeback count is shown, prominently, because that is what mastery bought and a margin
-- the player cannot see is a margin that may as well not exist.
--
-- **This module draws affordances off `atDesk` and off nothing else.** Same contract LabUI
-- and EaselUI hold: the server decides where the player is standing and every control here
-- is live exactly when the server would honour it, so there is no version of this where a
-- tile lights up under the cursor and then refuses the click.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type ReadingState = Types.ReadingState

local READING = Config.School.Reading

-- The panel\'s own palette, copied from EaselUI rather than shared with it, for the reason
-- that file gives about copying LabUI\'s.
local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local CAPTION_COLOR = Color3.fromRGB(146, 150, 162)
local TRACK_COLOR = Color3.fromRGB(38, 39, 46)

-- A letter the word came with. Dimmer than a placed one: it is context rather than
-- something the player did.
local GIVEN_COLOR = Color3.fromRGB(58, 60, 70)
-- A gap. Deliberately the brightest empty thing on the panel -- the gaps are the lesson.
local GAP_COLOR = Color3.fromRGB(86, 90, 104)
-- A letter the player put there. Warm, and the same warm as the tile it came from, so the
-- eye can follow one to the other.
local PLACED_COLOR = Color3.fromRGB(196, 150, 74)
-- A tile still in the tray.
local TILE_COLOR = Color3.fromRGB(214, 168, 86)
-- A tile already spent. Kept on the tray rather than removed, so the tray never shuffles
-- under the thumb -- see the note on TrayTile.spent.
local SPENT_COLOR = Color3.fromRGB(44, 45, 52)
-- The tile in hand.
local HELD_COLOR = Color3.fromRGB(255, 214, 130)

export type WordUIHandle = {
	gui: ScreenGui,
	frame: Frame,
	header: TextLabel,
	line: TextLabel,
	board: Frame,
	trayRow: Frame,
	footer: TextLabel,
	onPlace: ((targetIndex: number?, cellIndex: number?, tileId: string?) -> ())?,
	onSubmit: ((targetIndex: number) -> ())?,
}

local WordUI = {}
WordUI.__index = WordUI

local function makeSquare(parent: Instance, text: string, color: Color3, textColor: Color3): TextButton
	local square = Instance.new("TextButton")
	square.Size = UDim2.new(0, 30, 0, 34)
	square.BackgroundColor3 = color
	square.BorderSizePixel = 0
	square.AutoButtonColor = false
	square.Font = Enum.Font.GothamBold
	square.TextSize = 17
	square.TextColor3 = textColor
	square.Text = text
	square.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = square
	return square
end

function WordUI.new(): WordUIHandle
	local gui = Instance.new("ScreenGui")
	gui.Name = "WordUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 18, 1, -18)
	frame.Size = UDim2.new(0, 430, 0, 300)
	frame.BackgroundColor3 = PANEL_COLOR
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.LayoutOrder = 1
	header.Size = UDim2.new(1, 0, 0, 20)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBold
	header.TextSize = 16
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = TITLE_COLOR
	header.Text = "Reading"
	header.Parent = frame

	local line = Instance.new("TextLabel")
	line.Name = "Line"
	line.LayoutOrder = 2
	line.Size = UDim2.new(1, 0, 0, 16)
	line.BackgroundTransparency = 1
	line.Font = Enum.Font.GothamMedium
	line.TextSize = 12
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextColor3 = CAPTION_COLOR
	line.Text = ""
	line.Parent = frame

	local board = Instance.new("Frame")
	board.Name = "Board"
	board.LayoutOrder = 3
	board.Size = UDim2.new(1, 0, 0, 150)
	board.BackgroundTransparency = 1
	board.Parent = frame

	local boardLayout = Instance.new("UIListLayout")
	boardLayout.FillDirection = Enum.FillDirection.Vertical
	boardLayout.Padding = UDim.new(0, 10)
	boardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	boardLayout.Parent = board

	local trayLabel = Instance.new("TextLabel")
	trayLabel.Name = "TrayLabel"
	trayLabel.LayoutOrder = 4
	trayLabel.Size = UDim2.new(1, 0, 0, 14)
	trayLabel.BackgroundTransparency = 1
	trayLabel.Font = Enum.Font.GothamMedium
	trayLabel.TextSize = 11
	trayLabel.TextXAlignment = Enum.TextXAlignment.Left
	trayLabel.TextColor3 = CAPTION_COLOR
	trayLabel.Text = "TRAY"
	trayLabel.Parent = frame

	local trayRow = Instance.new("Frame")
	trayRow.Name = "Tray"
	trayRow.LayoutOrder = 5
	trayRow.Size = UDim2.new(1, 0, 0, 76)
	trayRow.BackgroundColor3 = TRACK_COLOR
	trayRow.BackgroundTransparency = 0.5
	trayRow.BorderSizePixel = 0
	trayRow.Parent = frame

	local trayCorner = Instance.new("UICorner")
	trayCorner.CornerRadius = UDim.new(0, 6)
	trayCorner.Parent = trayRow

	local trayPad = Instance.new("UIPadding")
	trayPad.PaddingTop = UDim.new(0, 5)
	trayPad.PaddingLeft = UDim.new(0, 5)
	trayPad.Parent = trayRow

	local trayGrid = Instance.new("UIGridLayout")
	trayGrid.CellSize = UDim2.new(0, 30, 0, 30)
	trayGrid.CellPadding = UDim2.new(0, 4, 0, 4)
	trayGrid.SortOrder = Enum.SortOrder.LayoutOrder
	trayGrid.Parent = trayRow

	local footer = Instance.new("TextLabel")
	footer.Name = "Footer"
	footer.LayoutOrder = 6
	footer.Size = UDim2.new(1, 0, 0, 16)
	footer.BackgroundTransparency = 1
	footer.Font = Enum.Font.GothamMedium
	footer.TextSize = 12
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.TextColor3 = CAPTION_COLOR
	footer.Text = ""
	footer.Parent = frame

	local self: WordUIHandle = setmetatable({
		gui = gui,
		frame = frame,
		header = header,
		line = line,
		board = board,
		trayRow = trayRow,
		footer = footer,
		onPlace = nil,
		onSubmit = nil,
	}, WordUI) :: any

	return self
end

function WordUI.OnPlace(self: WordUIHandle, handler: (targetIndex: number?, cellIndex: number?, tileId: string?) -> ())
	self.onPlace = handler
end

function WordUI.OnSubmit(self: WordUIHandle, handler: (targetIndex: number) -> ())
	self.onSubmit = handler
end

-- Rebuilt wholesale on every push rather than diffed.
--
-- A board is at most two words of nine squares and a tray of twelve, which is thirty
-- instances -- and the pushes are throttled on the server to a signature change, so this
-- runs when something actually moved and not four times a second. Diffing it would be a
-- cache to keep in step with the server for no measurable gain, and the class of bug that
-- produces -- a tile that stays on screen after it was spent -- is exactly the kind this
-- panel must never have.
function WordUI.Set(self: WordUIHandle, state: ReadingState?)
	if state == nil then
		self.frame.Visible = false
		return
	end

	if not state.active then
		if state.line == "" then
			self.frame.Visible = false
			return
		end
		self.frame.Visible = true
		self.header.Text = "Reading"
		self.line.Text = state.line
		self.board.Visible = false
		self.trayRow.Visible = false
		self.footer.Text = ""
		return
	end

	self.frame.Visible = true
	self.board.Visible = true
	self.trayRow.Visible = true
	self.header.Text = `Reading — {state.wordsDone}/{state.wordsTarget} words`
	self.line.Text = if state.atDesk then state.line else "Go to the desk."

	for _, child in self.board:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for targetIndex, target in state.targets do
		local row = Instance.new("Frame")
		row.Name = target.id
		row.LayoutOrder = targetIndex
		row.Size = UDim2.new(1, 0, 0, 36)
		row.BackgroundTransparency = 1
		row.Parent = self.board

		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.Padding = UDim.new(0, 4)
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Parent = row

		for cellIndex, cell in target.cells do
			local text = if cell.gap then "" else cell.letter
			local color = if cell.gap then GAP_COLOR elseif cell.placed then PLACED_COLOR else GIVEN_COLOR
			local textColor = if cell.placed then PANEL_COLOR else TITLE_COLOR
			local square = makeSquare(row, text, color, textColor)
			square.LayoutOrder = cellIndex
			-- Dimmed rather than hidden once handed in, so the player sees the word they
			-- finished for a beat instead of a row that changed under them.
			square.BackgroundTransparency = if target.done then 0.6 else 0
			square.Active = state.atDesk and not target.done

			square.Activated:Connect(function()
				local handler = self.onPlace
				if handler ~= nil and not target.done then
					handler(targetIndex, cellIndex, nil)
				end
			end)
		end

		local hand = Instance.new("TextButton")
		hand.Name = "Submit"
		hand.LayoutOrder = 999
		hand.Size = UDim2.new(0, 62, 0, 30)
		hand.BackgroundColor3 = if target.done then TRACK_COLOR else TILE_COLOR
		hand.BorderSizePixel = 0
		hand.AutoButtonColor = false
		hand.Font = Enum.Font.GothamBold
		hand.TextSize = 12
		hand.TextColor3 = if target.done then CAPTION_COLOR else PANEL_COLOR
		hand.Text = if target.done then "DONE" else "HAND IN"
		hand.Active = state.atDesk and not target.done
		hand.Parent = row

		local handCorner = Instance.new("UICorner")
		handCorner.CornerRadius = UDim.new(0, 5)
		handCorner.Parent = hand

		hand.Activated:Connect(function()
			local handler = self.onSubmit
			if handler ~= nil and not target.done then
				handler(targetIndex)
			end
		end)
	end

	for _, child in self.trayRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for index, tile in state.tray do
		local held = state.heldTileId == tile.id
		local color = if tile.spent then SPENT_COLOR elseif held then HELD_COLOR else TILE_COLOR
		local textColor = if tile.spent then CAPTION_COLOR else PANEL_COLOR
		local square = makeSquare(self.trayRow, tile.letter, color, textColor)
		square.Size = UDim2.new(0, 30, 0, 30)
		square.LayoutOrder = index
		square.Active = state.atDesk and not tile.spent

		square.Activated:Connect(function()
			local handler = self.onPlace
			if handler ~= nil and not tile.spent then
				handler(nil, nil, tile.id)
			end
		end)
	end

	local takebacks = if state.takebacks == 1 then "1 takeback" else `{state.takebacks} takebacks`
	local shelf = if state.atShelf then "  ·  at the shelf" else ""
	self.footer.Text = `{takebacks} left  ·  level {state.masteryLevel}/{#READING.TakebacksByLevel}`
		.. `  ·  {math.floor(state.secondsLeft)}s{shelf}`
end

function WordUI.Destroy(self: WordUIHandle)
	self.gui:Destroy()
end

return WordUI
