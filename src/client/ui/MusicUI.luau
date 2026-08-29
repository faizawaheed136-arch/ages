--!strict
-- The four lanes, drawn and judged.
--
-- Centre-bottom rather than the corner every other school panel lives in, and this is the
-- one placement in the school that has to break that rule: notes fall for two seconds before
-- they are hit, so the lanes need vertical room and the eye has to sit on them the whole
-- time. A corner panel would be a rhythm game played out of the side of your eye.
--
-- **This module judges. It is the only client file in the school that does.**
--
-- Everywhere else the server decides and the panel draws the answer. Here it cannot: the
-- windows are 25 to 124 milliseconds and a Roblox round trip is longer than the widest of
-- them, so a server-judged rhythm lesson is not a stricter game, it is an unplayable one.
-- What is sent is a *claim* -- this note, this many milliseconds off -- and the server
-- checks the note exists, is unjudged, is inside the window it granted, and was actually due
-- around now. See MusicService for the honest accounting of what that does and does not buy.
--
-- The clock is the client\'s own, started when the first active push arrives. It is never
-- reconciled against the server\'s, deliberately: the player is judged against the notes
-- *they saw fall*, and a correction mid-piece would move the beat under their hands. The
-- count-in exists partly to absorb the latency between the server starting the piece and
-- this file learning about it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type MusicState = Types.MusicState
type MusicNote = Types.MusicNote

local MUSIC = Config.School.Music

-- How far ahead of the judgement line a note appears, in seconds. This is the read-ahead,
-- and it is the number that decides whether the lesson is music or reaction: at 2 seconds a
-- player sees four beats at 120bpm, which is a bar, which is the unit music is actually read
-- in. Shorter and the chart stops having shape; much longer and the notes crowd.
local LEAD_SECONDS = 2

local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local CAPTION_COLOR = Color3.fromRGB(146, 150, 162)
local LANE_COLOR = Color3.fromRGB(30, 31, 38)
local LINE_COLOR = Color3.fromRGB(236, 238, 245)

-- One colour per lane, in the same order MusicRoom paints its posts. The two must agree:
-- the posts exist so a player can look up from the panel and still know which lane is which,
-- and two different orderings would make that actively misleading.
local LANE_COLORS = {
	Color3.fromRGB(232, 106, 118),
	Color3.fromRGB(238, 190, 96),
	Color3.fromRGB(108, 196, 142),
	Color3.fromRGB(104, 158, 232),
}

-- Keys, left to right. D F J K rather than 1 2 3 4 because they are where two hands already
-- rest, which is the layout every rhythm game converged on for four lanes.
local LANE_KEYS = { Enum.KeyCode.D, Enum.KeyCode.F, Enum.KeyCode.J, Enum.KeyCode.K }

export type MusicUIHandle = {
	gui: ScreenGui,
	frame: Frame,
	header: TextLabel,
	line: TextLabel,
	board: Frame,
	lanes: { Frame },
	buttons: { TextButton },
	footer: TextLabel,
	-- The chart, and which of it this panel has already claimed. Held here rather than read
	-- off the state each frame because the state is pushed on change and the notes fall every
	-- frame.
	notes: { MusicNote },
	claimed: { [number]: boolean },
	startedAt: number,
	active: boolean,
	perfectMs: number,
	greatMs: number,
	goodMs: number,
	atStand: boolean,
	-- One pooled frame per note, created when the chart arrives and moved every frame. Pooled
	-- rather than created and destroyed as notes scroll, because a hundred instances a lesson
	-- churning through Instance.new is the one thing in this panel that could actually cost
	-- frames -- and dropped frames in a rhythm game are dropped notes.
	dots: { Frame },
	connection: RBXScriptConnection?,
	onHit: ((index: number, offsetMs: number) -> ())?,
}

local MusicUI = {}
MusicUI.__index = MusicUI

function MusicUI.new(): MusicUIHandle
	local gui = Instance.new("ScreenGui")
	gui.Name = "MusicUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -14)
	frame.Size = UDim2.new(0, 340, 0, 420)
	frame.BackgroundColor3 = PANEL_COLOR
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Position = UDim2.new(0, 12, 0, 8)
	header.Size = UDim2.new(1, -24, 0, 18)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBold
	header.TextSize = 15
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = TITLE_COLOR
	header.Text = "Music"
	header.Parent = frame

	local line = Instance.new("TextLabel")
	line.Name = "Line"
	line.Position = UDim2.new(0, 12, 0, 26)
	line.Size = UDim2.new(1, -24, 0, 16)
	line.BackgroundTransparency = 1
	line.Font = Enum.Font.GothamMedium
	line.TextSize = 12
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextColor3 = CAPTION_COLOR
	line.Text = ""
	line.Parent = frame

	-- The board: the falling area, with the judgement line at its foot.
	local board = Instance.new("Frame")
	board.Name = "Board"
	board.Position = UDim2.new(0, 12, 0, 48)
	board.Size = UDim2.new(1, -24, 0, 300)
	board.BackgroundTransparency = 1
	board.ClipsDescendants = true
	board.Parent = frame

	local lanes: { Frame } = {}
	local buttons: { TextButton } = {}
	local laneWidth = 1 / MUSIC.Lanes

	for lane = 1, MUSIC.Lanes do
		local column = Instance.new("Frame")
		column.Name = `Lane{lane}`
		column.Position = UDim2.new(laneWidth * (lane - 1), 3, 0, 0)
		column.Size = UDim2.new(laneWidth, -6, 1, 0)
		column.BackgroundColor3 = LANE_COLOR
		column.BorderSizePixel = 0
		column.Parent = board
		table.insert(lanes, column)

		local columnCorner = Instance.new("UICorner")
		columnCorner.CornerRadius = UDim.new(0, 5)
		columnCorner.Parent = column

		-- The judgement line, per lane rather than one bar across, so it reads as the place
		-- each note is going rather than as a divider.
		local hitLine = Instance.new("Frame")
		hitLine.Name = "HitLine"
		hitLine.AnchorPoint = Vector2.new(0, 1)
		hitLine.Position = UDim2.new(0, 0, 1, -22)
		hitLine.Size = UDim2.new(1, 0, 0, 3)
		hitLine.BackgroundColor3 = LINE_COLOR
		hitLine.BorderSizePixel = 0
		hitLine.Parent = column

		-- The key, and the touch target. Same control for both, sized past the 44px minimum so
		-- a thumb can find it -- this is the only input in the lesson and on a phone it is the
		-- whole of it.
		local button = Instance.new("TextButton")
		button.Name = `Key{lane}`
		button.Position = UDim2.new(laneWidth * (lane - 1), 3, 1, -60)
		button.Size = UDim2.new(laneWidth, -6, 0, 48)
		button.BackgroundColor3 = LANE_COLORS[((lane - 1) % #LANE_COLORS) + 1]
		button.BackgroundTransparency = 0.55
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Font = Enum.Font.GothamBold
		button.TextSize = 15
		button.TextColor3 = TITLE_COLOR
		button.Text = LANE_KEYS[lane] ~= nil and LANE_KEYS[lane].Name or tostring(lane)
		button.Parent = frame
		table.insert(buttons, button)

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 6)
		buttonCorner.Parent = button
	end

	local footer = Instance.new("TextLabel")
	footer.Name = "Footer"
	footer.Position = UDim2.new(0, 12, 1, -10)
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Size = UDim2.new(1, -24, 0, 14)
	footer.BackgroundTransparency = 1
	footer.Font = Enum.Font.GothamMedium
	footer.TextSize = 11
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.TextColor3 = CAPTION_COLOR
	footer.Text = ""
	footer.Parent = frame

	local self: MusicUIHandle = setmetatable({
		gui = gui,
		frame = frame,
		header = header,
		line = line,
		board = board,
		lanes = lanes,
		buttons = buttons,
		footer = footer,
		notes = {},
		claimed = {},
		startedAt = 0,
		active = false,
		perfectMs = 0,
		greatMs = 0,
		goodMs = 0,
		atStand = false,
		dots = {},
		connection = nil,
		onHit = nil,
	}, MusicUI) :: any

	for lane = 1, MUSIC.Lanes do
		buttons[lane].MouseButton1Down:Connect(function()
			MusicUI._strike(self, lane)
		end)
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not self.active then
			return
		end
		for lane, key in LANE_KEYS do
			if input.KeyCode == key then
				MusicUI._strike(self, lane)
				return
			end
		end
	end)

	return self
end

function MusicUI.OnHit(self: MusicUIHandle, handler: (index: number, offsetMs: number) -> ())
	self.onHit = handler
end

-- A lane was struck. Finds the nearest unclaimed note in that lane and judges it.
--
-- Nearest rather than first: on a chord or a fast run the next note in a lane may already be
-- behind the line while the one after it is closer, and taking the first would score the
-- wrong one and then miss the one the player actually hit.
function MusicUI._strike(self: MusicUIHandle, lane: number)
	if not self.active or not self.atStand then
		return
	end
	local now = (os.clock() - self.startedAt) * 1000

	local bestIndex: number? = nil
	local bestOffset = math.huge
	for index, note in self.notes do
		if note.lane == lane and not self.claimed[index] then
			local offset = now - note.atMs
			if math.abs(offset) < math.abs(bestOffset) then
				bestIndex = index
				bestOffset = offset
			end
		end
	end

	if bestIndex == nil or math.abs(bestOffset) > self.goodMs then
		-- A strike into empty air. Costs nothing at all, which is deliberate: penalising a
		-- stray tap would make the safe play "do not press unless certain", and hesitation is
		-- the opposite of what a rhythm lesson is teaching.
		return
	end

	self.claimed[bestIndex] = true
	local handler = self.onHit
	if handler ~= nil then
		handler(bestIndex, bestOffset)
	end

	-- The flash. The whole feedback layer, and deliberately the whole of it: the research
	-- constraint in the activity law is that both no juice and extreme juice make an
	-- experience worse, and a lane lighting under the hand is enough to say "that one
	-- counted" without competing with the notes still falling.
	local button = self.buttons[lane]
	if button ~= nil then
		button.BackgroundTransparency = 0.05
	end
end

-- Moves every note. One connection for the whole panel rather than one per note.
function MusicUI._frame(self: MusicUIHandle)
	if not self.active then
		return
	end
	local now = (os.clock() - self.startedAt) * 1000
	local boardHeight = self.board.AbsoluteSize.Y
	local hitY = boardHeight - 22

	for index, note in self.notes do
		local dot = self.dots[index]
		if dot == nil then
			continue
		end
		local ahead = (note.atMs - now) / 1000
		if ahead > LEAD_SECONDS or ahead < -0.4 or self.claimed[index] then
			dot.Visible = false
		else
			dot.Visible = true
			-- 0 at the top of the lead window, 1 at the judgement line.
			local share = 1 - (ahead / LEAD_SECONDS)
			dot.Position = UDim2.new(0, 0, 0, math.floor(share * hitY) - dot.AbsoluteSize.Y)
		end
	end

	-- Let the key flashes decay. Cheap, and it keeps the flash out of the strike path.
	for _, button in self.buttons do
		if button.BackgroundTransparency < 0.55 then
			button.BackgroundTransparency = math.min(button.BackgroundTransparency + 0.06, 0.55)
		end
	end
end

-- Builds one frame per note in the chart. Called once, when a chart arrives.
function MusicUI._buildDots(self: MusicUIHandle)
	for _, dot in self.dots do
		dot:Destroy()
	end
	self.dots = {}

	for index, note in self.notes do
		local column = self.lanes[note.lane]
		if column == nil then
			continue
		end
		local dot = Instance.new("Frame")
		dot.Name = `Note{index}`
		dot.Size = UDim2.new(1, 0, 0, if note.holdMs > 0 then 34 else 14)
		dot.BackgroundColor3 = LANE_COLORS[((note.lane - 1) % #LANE_COLORS) + 1]
		dot.BorderSizePixel = 0
		dot.Visible = false
		dot.Parent = column
		self.dots[index] = dot

		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(0, 4)
		dotCorner.Parent = dot
	end
end

function MusicUI.Set(self: MusicUIHandle, state: MusicState?)
	if state == nil or not state.active then
		self.active = false
		local connection = self.connection
		if connection ~= nil then
			connection:Disconnect()
			self.connection = nil
		end
		if state ~= nil and state.line ~= "" then
			self.frame.Visible = true
			self.board.Visible = false
			for _, button in self.buttons do
				button.Visible = false
			end
			self.header.Text = "Music"
			self.line.Text = state.line
			self.footer.Text = ""
		else
			self.frame.Visible = false
		end
		return
	end

	-- A new chart. Recognised by the note count changing rather than by a lesson id, because
	-- the chart is the only thing that identifies a piece and it is fixed for its whole life.
	if #state.notes ~= #self.notes then
		self.notes = state.notes
		self.claimed = {}
		-- The clock starts when the chart lands here, not when the server started it. See the
		-- note at the top: the player is judged against the notes they saw fall, and the
		-- count-in absorbs the difference.
		self.startedAt = os.clock()
		MusicUI._buildDots(self)
	end

	self.active = true
	self.perfectMs = state.perfectMs
	self.greatMs = state.greatMs
	self.goodMs = state.goodMs
	self.atStand = state.atStand

	self.frame.Visible = true
	self.board.Visible = true
	for _, button in self.buttons do
		button.Visible = true
		button.Active = state.atStand
	end

	self.header.Text = `Music — {state.perfect + state.great + state.good}/{state.notesTotal}`
	self.line.Text = if state.atStand then state.line else "Go to the stand."
	self.footer.Text = `perfect {state.perfect}  great {state.great}  good {state.good}  missed {state.missed}`
		.. `  ·  streak {state.streak}  ·  window {math.floor(state.goodMs)}ms`
		.. `  ·  level {state.masteryLevel}`

	if self.connection == nil then
		self.connection = RunService.RenderStepped:Connect(function()
			MusicUI._frame(self)
		end)
	end
end

function MusicUI.Destroy(self: MusicUIHandle)
	local connection = self.connection
	if connection ~= nil then
		connection:Disconnect()
	end
	self.gui:Destroy()
end

return MusicUI
