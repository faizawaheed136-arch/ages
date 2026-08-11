--!strict
-- The Geography errand, drawn.
--
-- Bottom left, the same corner LabUI takes, and deliberately so: the two are the same
-- kind of thing -- the surface of the activity the player is currently doing -- and the
-- timetable runs one subject at a time, so they can never be on screen together.
--
-- **The hard rule for this panel is what it does not draw.** There is no marker in the
-- world, no beam, no line on the floor, and nothing here may ever add one. Every other
-- destination in AGES is a lit gold disc, because in those systems finding the place is
-- overhead. Here it is the activity, and the day a marker appears this subject has
-- nothing left in it. That is why the arrow at level three is drawn as a bearing on the
-- panel rather than as a thing in the world: an arrow you have to look at the HUD to read
-- and then translate onto the street is help, and a disc glowing through a wall is the
-- answer.
--
-- What the panel grows as the ladder is climbed is therefore the whole reward of the
-- subject, and it grows visibly:
--
--   level 1  a name.
--   level 2  and a compass sector -- one line appears.
--   level 3  and an arrow -- a dial appears beside the name.
--   level 4  and a distance -- the dial gains a number under it.
--   level 5  the subject is topped out and can be skipped.
--
-- Nothing here decides anything. The errand is answered by walking, and the server's
-- distance check is the only judge; there is no button on this panel at all, which makes
-- it the one activity surface in the game with no input on it. That is not an omission.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type HuntState = Types.HuntState

local HUNT = Config.School.Hunt

-- The panel's own palette, matching LabUI's rather than StatsUI's for the reason LabUI
-- gives: this is a place the player is in, not a readout they glance at.
local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TITLE_COLOR = Color3.fromRGB(236, 238, 245)
local CAPTION_COLOR = Color3.fromRGB(146, 150, 162)
local TRACK_COLOR = Color3.fromRGB(38, 39, 46)

-- The destination itself. Brighter and larger than anything else on the panel, because at
-- level one it is the entire lesson and a player who misreads it walks the wrong way for
-- a minute.
local PLACE_COLOR = Color3.fromRGB(244, 236, 214)

-- The compass arrow. Its own colour, and pointedly not the gold every guide beam and job
-- pad in the game uses: this is a hint the player earned, and it should not read as the
-- game having given in and marked the spot.
local ARROW_COLOR = Color3.fromRGB(150, 196, 214)

-- The stop clock, which runs down. The same three-stage language the task rows and the
-- bench clocks use, so a player who has worked a shift already knows what the colour
-- change means.
local CLOCK_COLOR = Color3.fromRGB(235, 200, 120)
local CLOCK_URGENT_COLOR = Color3.fromRGB(228, 140, 80)
local CLOCK_URGENT_SHARE = 1 / 3

local FOUND_COLOR = Color3.fromRGB(90, 200, 120)
local MISSED_COLOR = Color3.fromRGB(228, 148, 84)

local PANEL_WIDTH = 300

-- How big the arrow dial is, in pixels. Big enough to read a direction off at a glance
-- while walking, which is the only thing it is for.
local DIAL_SIZE = 46

-- What each rung of the ladder is called on the panel, in the player's words rather than
-- Config's. Keyed by the same words Config.School.Hunt.RevealedByLevel uses, so a rung
-- added there without a sentence here is caught below rather than printed as "nil".
local REVEAL_SENTENCE: { [string]: string } = {
	name = "the name of the place",
	area = "which end of town it is in",
	bearing = "which way to walk",
	range = "how far it is",
}

local HuntUI = {}
HuntUI.__index = HuntUI

export type HuntUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		titleLabel: TextLabel,
		placeRow: Frame,
		placeLabel: TextLabel,
		dial: Frame,
		arrowLabel: TextLabel,
		rangeLabel: TextLabel,
		areaLabel: TextLabel,
		clockTrack: Frame,
		clockFill: Frame,
		progressLabel: TextLabel,
		masteryLabel: TextLabel,
		arrivedLabel: TextLabel,
		summaryLabel: TextLabel,
		-- The last bearing the server sent, in world degrees clockwise from north.
		--
		-- Held rather than drawn straight onto the dial, because the arrow has to answer
		-- "which way from where I am *looking*" and the camera turns between pushes. The
		-- render loop below subtracts the live camera heading from this every frame; the
		-- server only ever has to say where the place is.
		bearing: number?,
		-- Connected only while an arrow is on screen, which is a few seconds per school
		-- year. A permanent per-frame connection for that is a cost the whole game pays
		-- for a feature almost none of it uses.
		render: RBXScriptConnection?,
	},
	HuntUI
))

-- Every rung has to have a sentence, or the mastery line prints nothing where the reward
-- should be -- which is the numbers-only failure this subject exists to avoid, arriving
-- through the UI instead of through the design. Loud at require time, like the ladder
-- check in GeographyService.
for level, word in HUNT.RevealedByLevel do
	if REVEAL_SENTENCE[word] == nil then
		error(
			`[AGES client] School.Hunt.RevealedByLevel[{level}] is "{word}", which HuntUI has no sentence for.`
				.. ` Add one to REVEAL_SENTENCE in client/ui/HuntUI.luau.`
		)
	end
end

local function formatClock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- Which way the camera is facing, in the same degrees-clockwise-from-north the server
-- sends a bearing in. Nil when there is no camera to ask, which happens for a frame or
-- two around a respawn.
local function cameraHeading(): number?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		-- Looking straight up or down, so there is no heading to subtract. The arrow holds
		-- its last rotation rather than snapping to north, which would read as the arrow
		-- being broken at exactly the moment the player is not looking at the street.
		return nil
	end
	return (math.deg(math.atan2(flat.X, -flat.Z)) + 360) % 360
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
	label.TextColor3 = color
	label.Text = ""
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

function HuntUI.new(): HuntUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesHunt"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 2

	local panel = Instance.new("Frame")
	panel.Name = "HuntPanel"
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
	titleLabel.Text = "Geography"
	titleLabel.LayoutOrder = 0
	titleLabel.Parent = panel

	-- The name and the dial, side by side. A row rather than two stacked captions because
	-- the arrow is read *against* the name -- "the pages & press, that way" is one thought
	-- -- and because a dial that appears in the middle of a column at level three would
	-- push the name the player is reading down the panel.
	local placeRow = Instance.new("Frame")
	placeRow.Name = "PlaceRow"
	placeRow.Size = UDim2.new(1, 0, 0, 0)
	placeRow.AutomaticSize = Enum.AutomaticSize.Y
	placeRow.BackgroundTransparency = 1
	placeRow.LayoutOrder = 1
	placeRow.Parent = panel

	local dial = Instance.new("Frame")
	dial.Name = "Dial"
	dial.Size = UDim2.new(0, DIAL_SIZE, 0, DIAL_SIZE)
	dial.AnchorPoint = Vector2.new(1, 0)
	dial.Position = UDim2.new(1, 0, 0, 0)
	dial.BackgroundColor3 = TRACK_COLOR
	dial.BorderSizePixel = 0
	dial.Visible = false
	dial.Parent = placeRow

	local dialCorner = Instance.new("UICorner")
	dialCorner.CornerRadius = UDim.new(1, 0)
	dialCorner.Parent = dial

	-- A glyph rather than an image, so there is no asset to upload and nothing to go
	-- missing in a place that has not been published. It points up at rotation zero, which
	-- is straight ahead -- and "up means the way you are facing" is the one convention a
	-- player does not have to be taught.
	local arrowLabel = Instance.new("TextLabel")
	arrowLabel.Name = "Arrow"
	arrowLabel.Size = UDim2.new(1, 0, 1, 0)
	arrowLabel.BackgroundTransparency = 1
	arrowLabel.Font = Enum.Font.GothamBold
	arrowLabel.TextSize = 22
	arrowLabel.TextColor3 = ARROW_COLOR
	arrowLabel.Text = "▲"
	arrowLabel.Parent = dial

	local rangeLabel = Instance.new("TextLabel")
	rangeLabel.Name = "Range"
	rangeLabel.Size = UDim2.new(0, DIAL_SIZE, 0, 14)
	rangeLabel.AnchorPoint = Vector2.new(1, 0)
	rangeLabel.Position = UDim2.new(1, 0, 0, DIAL_SIZE + 2)
	rangeLabel.BackgroundTransparency = 1
	rangeLabel.Font = Enum.Font.GothamMedium
	rangeLabel.TextSize = 12
	rangeLabel.TextColor3 = ARROW_COLOR
	rangeLabel.Text = ""
	rangeLabel.Visible = false
	rangeLabel.Parent = placeRow

	local placeLabel = Instance.new("TextLabel")
	placeLabel.Name = "Place"
	-- Width leaves the dial its corner whether or not the dial is showing. Deliberate: a
	-- name that reflows to a different number of lines the moment the player levels up
	-- would make the reward read as a layout glitch.
	placeLabel.Size = UDim2.new(1, -(DIAL_SIZE + 10), 0, 0)
	placeLabel.AutomaticSize = Enum.AutomaticSize.Y
	placeLabel.BackgroundTransparency = 1
	placeLabel.Font = Enum.Font.GothamBold
	placeLabel.TextSize = 18
	placeLabel.TextXAlignment = Enum.TextXAlignment.Left
	placeLabel.TextYAlignment = Enum.TextYAlignment.Top
	placeLabel.TextWrapped = true
	placeLabel.TextColor3 = PLACE_COLOR
	placeLabel.Text = ""
	placeLabel.Parent = placeRow

	local areaLabel = makeCaption(panel, 2, 13, CAPTION_COLOR)

	local clockTrack = Instance.new("Frame")
	clockTrack.Name = "ClockTrack"
	clockTrack.Size = UDim2.new(1, 0, 0, 5)
	clockTrack.BackgroundColor3 = TRACK_COLOR
	clockTrack.BorderSizePixel = 0
	clockTrack.LayoutOrder = 3
	clockTrack.Parent = panel

	local clockFill = Instance.new("Frame")
	clockFill.Name = "Fill"
	clockFill.Size = UDim2.new(1, 0, 1, 0)
	clockFill.BackgroundColor3 = CLOCK_COLOR
	clockFill.BorderSizePixel = 0
	clockFill.Parent = clockTrack

	local progressLabel = makeCaption(panel, 4, 12, CAPTION_COLOR)
	local masteryLabel = makeCaption(panel, 5, 12, CAPTION_COLOR)
	local arrivedLabel = makeCaption(panel, 6, 13, FOUND_COLOR)
	local summaryLabel = makeCaption(panel, 7, 13, TITLE_COLOR)

	screenGui.Parent = playerGui

	return setmetatable({
		screenGui = screenGui,
		panel = panel,
		titleLabel = titleLabel,
		placeRow = placeRow,
		placeLabel = placeLabel,
		dial = dial,
		arrowLabel = arrowLabel,
		rangeLabel = rangeLabel,
		areaLabel = areaLabel,
		clockTrack = clockTrack,
		clockFill = clockFill,
		progressLabel = progressLabel,
		masteryLabel = masteryLabel,
		arrivedLabel = arrivedLabel,
		summaryLabel = summaryLabel,
		bearing = nil,
		render = nil,
	}, HuntUI) :: HuntUIHandle
end

-- Points the arrow, every frame, at whatever bearing was last pushed -- relative to where
-- the camera is looking now. Started when a bearing first arrives and stopped the moment
-- there is not one, so a life that never reaches level three never connects it at all.
local function setBearing(self: HuntUIHandle, bearing: number?)
	self.bearing = bearing

	if bearing == nil then
		self.dial.Visible = false
		local render = self.render
		if render ~= nil then
			render:Disconnect()
			self.render = nil
		end
		return
	end

	self.dial.Visible = true
	if self.render ~= nil then
		return
	end
	self.render = RunService.RenderStepped:Connect(function()
		local want = self.bearing
		if want == nil then
			return
		end
		local heading = cameraHeading()
		if heading == nil then
			return
		end
		-- Clockwise in world degrees is clockwise in GUI rotation, so this is a
		-- subtraction and nothing more. Zero is straight up, which is straight ahead.
		self.arrowLabel.Rotation = (want - heading + 360) % 360
	end)
end

-- The mastery line: what this rung gives, and what the next one would.
--
-- Phrased as the thing itself rather than as a level, because the level is not the reward
-- -- the line appearing on this panel is. "Two more good errands and you will be told
-- which way to walk" is a sentence a player can want; "geography 2/5" is not.
local function masterySentence(state: HuntState): string
	if state.level >= state.levelMax then
		return "You know this town. Geography can be skipped."
	end
	local ladder = HUNT.RevealedByLevel
	local nextWord = ladder[math.clamp(state.level + 1, 1, #ladder)]
	local gains = REVEAL_SENTENCE[nextWord] or "more to go on"
	local left = state.passesPerLevel - state.passes
	local word = if left == 1 then "errand" else "errands"
	return `{left} good {word} until you are told {gains}.`
end

-- The whole panel, from one snapshot. Nil is the usual state and takes it down.
function HuntUI.Set(self: HuntUIHandle, state: HuntState?)
	if state == nil then
		self.panel.Visible = false
		setBearing(self, nil)
		return
	end

	self.panel.Visible = true

	-- The closing line replaces the working panel for a beat. Everything else goes away
	-- under it: a destination and a clock still on screen beside "that is the errand over"
	-- is the panel arguing with itself.
	local summary = state.summary
	if summary ~= nil then
		setBearing(self, nil)
		self.summaryLabel.Visible = true
		self.summaryLabel.Text = summary
		self.placeRow.Visible = false
		self.areaLabel.Visible = false
		self.clockTrack.Visible = false
		self.progressLabel.Visible = false
		self.masteryLabel.Visible = false
		self.arrivedLabel.Visible = false
		return
	end

	self.summaryLabel.Visible = false
	self.progressLabel.Visible = true
	self.masteryLabel.Visible = true
	-- Three facts on one row and all three earn their place: where you are in the errand,
	-- what you have already banked -- so a player who missed the first stop can see the
	-- other two still count -- and the clock as a number beside the bar, because a bar
	-- alone cannot be read as "forty seconds" by somebody who is running.
	self.progressLabel.Text =
		`Stop {state.stop} of {state.stops} -- {state.found} found -- {formatClock(state.secondsLeft)} left`
	self.masteryLabel.Text = masterySentence(state)

	-- The arrival beat. The destination comes off the panel entirely while it holds,
	-- which is what makes reaching somewhere land as a moment rather than as the name
	-- being quietly replaced by the next one.
	local arrived = state.arrived
	if arrived ~= nil then
		setBearing(self, nil)
		self.arrivedLabel.Visible = true
		self.arrivedLabel.Text = arrived
		-- Green for found, orange for the clock having taken it. Read off the sentence's
		-- own first word rather than off a second field, because the server already had to
		-- choose the sentence and a flag beside it is a second thing to keep in step.
		self.arrivedLabel.TextColor3 = if string.sub(arrived, 1, 5) == "Found" then FOUND_COLOR else MISSED_COLOR
		self.placeRow.Visible = false
		self.areaLabel.Visible = false
		self.clockTrack.Visible = false
		return
	end

	self.arrivedLabel.Visible = false
	self.placeRow.Visible = true
	self.clockTrack.Visible = true
	self.placeLabel.Text = state.label

	local area = state.area
	self.areaLabel.Visible = area ~= nil
	self.areaLabel.Text = if area ~= nil then `Somewhere on the {area} side of town.` else ""

	setBearing(self, state.bearing)

	local range = state.rangeStuds
	self.rangeLabel.Visible = range ~= nil
	-- Rounded to ten studs, because a distance that ticks every step is a number the player
	-- watches instead of the street -- and the reward being bought here is knowing roughly
	-- how far, not being given a countdown.
	self.rangeLabel.Text = if range ~= nil then `{math.floor(range / 10 + 0.5) * 10}m` else ""

	local share = if HUNT.SecondsPerStop > 0 then state.secondsLeft / HUNT.SecondsPerStop else 0
	self.clockFill.Size = UDim2.new(math.clamp(share, 0, 1), 0, 1, 0)
	self.clockFill.BackgroundColor3 = if share <= CLOCK_URGENT_SHARE then CLOCK_URGENT_COLOR else CLOCK_COLOR
end

return HuntUI
