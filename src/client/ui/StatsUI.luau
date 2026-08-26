--!strict
-- The always-visible HUD: who you are this minute, and what you are doing this
-- minute. Age, life stage, money, the four primary stats, the age-up button, and a
-- row for each thing the world is currently asking of you -- a shift, its tasks, a
-- lesson, a workout sweep, somebody standing in front of you, a queue at the counter.
--
-- **The rule this file is now held to: if it is not about the minute the player is
-- in, it is not on the HUD.** Everything here either changes in the next few seconds
-- or is the answer to "how am I doing", and nothing else qualifies. The roster of
-- everyone you know, a savings balance, a bill, a house you own -- all of those are
-- facts you go and look up, and they were on this panel appearing and disappearing as
-- their services pushed. They live on the menu's Money and Relationships panes now,
-- which is a surface the player chooses to open.
--
-- That is not tidying. A HUD that shows everything trains the player to read none of
-- it, and the rows that suffered most were the ones that matter in the second they
-- appear: a task clock and a sweep needle were competing for attention with a savings
-- figure that had not changed in ten minutes.
--
-- This module renders server state and reports button presses. It never
-- decides whether aging up is allowed; that verdict arrives from the server.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))
local Money = require(game:GetService("ReplicatedStorage"):WaitForChild("Money"))
local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Types"))
-- Shared with GymService so the bar the player is looking at and the hit the server
-- grades are computed by the same function. See src/shared/Sweep.luau.
local Sweep = require(game:GetService("ReplicatedStorage"):WaitForChild("Sweep"))

type Stats = Types.Stats
type StatName = Types.StatName
type ManualAgeUpState = Types.ManualAgeUpState
type ShiftState = Types.ShiftState
type TaskState = Types.TaskState
type LessonState = Types.LessonState
type PersonState = Types.PersonState
type WorkoutState = Types.WorkoutState
type Ribbon = Types.Ribbon
type RibbonMoment = Types.RibbonMoment

local STAT_ORDER: { { name: StatName, label: string } } = {
	{ name = "health", label = "Health" },
	{ name = "happiness", label = "Happiness" },
	{ name = "smarts", label = "Smarts" },
	{ name = "looks", label = "Looks" },
}

local READY_COLOR = Color3.fromRGB(235, 190, 90)
local SKIP_COLOR = Color3.fromRGB(70, 70, 82)
local COOLDOWN_COLOR = Color3.fromRGB(52, 52, 60)
local PROGRESS_COLOR = Color3.fromRGB(110, 160, 220)
local GOOD_STAT_COLOR = Color3.fromRGB(90, 200, 120)
local WARN_STAT_COLOR = Color3.fromRGB(210, 60, 60)
-- Its own color, and deliberately not the green of a healthy stat bar: money is not
-- a score, and a balance that turns red at some threshold would be inventing a rule
-- the game does not have. One shade, always.
local MONEY_COLOR = Color3.fromRGB(225, 205, 130)
-- The shift bar. Deliberately not the money color: the bar is time, and the only
-- thing on this HUD that fills up while the player is doing something rather than
-- while something is being done to them.
local SHIFT_COLOR = Color3.fromRGB(120, 195, 165)
-- The task bar, and the only bar on this HUD that runs *down*. Everything else here
-- fills toward something good; this one is time being spent, so it empties, and the
-- direction alone tells the player which kind of bar they are looking at before they
-- have read a word of it.
local TASK_COLOR = Color3.fromRGB(235, 200, 120)
-- The last third. Not red -- nothing dies here, you just miss one -- but a clear
-- enough change to be caught out of the corner of an eye while you are running.
local TASK_URGENT_COLOR = Color3.fromRGB(228, 140, 80)
-- Rush tasks use this colour so the player can tell at a glance that the whole
-- task is a repeat cycle rather than a single fetch-or-carry. Different from
-- TASK_URGENT_COLOR because urgency is time-based and a rush is urgent from the
-- first second.
local TASK_RUSH_COLOR = Color3.fromRGB(220, 100, 80)
-- Two-mark fetch/hand cycles. Blue sets them apart from the single-mark tasks
-- and from the rush, so a player glancing at the HUD can tell whether they are
-- in a round-trip or a point-to-point before reading the label.
local TASK_FETCH_COLOR = Color3.fromRGB(120, 170, 230)
-- Single-mark tasks. Green is the default "go do this" colour, distinct from
-- blue (fetch cycle) and orange (rush), and from the urgent amber.
local TASK_HAND_COLOR = Color3.fromRGB(120, 200, 130)
-- Held while a prompt is open. Grey and still, the same language the locked choice
-- markers use: this is not a clock that has broken, it is one that is not running.
local TASK_PAUSED_COLOR = Color3.fromRGB(120, 118, 128)
-- Below this share of the clock, the bar goes urgent.
local TASK_URGENT_SHARE = 1 / 3
-- The caption's ordinary colour, kept as a name because the missed line borrows the
-- row for a few seconds and has to give it back.
local TASK_CAPTION_COLOR = Color3.fromRGB(140, 140, 155)

-- The gym sweep bar. The sweet zone is a gold band in the centre of the track,
-- the perfect zone is a brighter inner band, and the needle is white. These
-- colours deliberately do not share a palette with any other row: the sweep is
-- the only part of this HUD the player is actively looking at during a workout.
local SWEEP_BAND_COLOR = Color3.fromRGB(180, 150, 50)
local SWEEP_PERFECT_COLOR = Color3.fromRGB(230, 195, 60)
local SWEEP_NEEDLE_COLOR = Color3.fromRGB(245, 240, 230)
local PUSH_ACTIVE_COLOR = Color3.fromRGB(235, 190, 90)
local PUSH_INACTIVE_COLOR = Color3.fromRGB(70, 70, 82)
-- The sweet zone's half-widths as fractions of the track. Config's SweetFraction
-- and PerfectFraction are full widths; the bands are centred on 0.5, so each
-- extends half its width to either side -- the exact same halves the server
-- grades a hit against.
-- The bands start as a placeholder and are resized on every state that arrives.
-- Nothing about the sweep is a client-side constant any more: where the zone sits
-- depends on the machine, and how wide it is depends on the character's health, so
-- both come down with the state or the bar would draw a lie.
local PLACEHOLDER_HALF = 0.1

local StatsUI = {}
StatsUI.__index = StatsUI

-- The four parts of a task row that anything ever writes to. The track is not in here
-- on purpose: it is a backing plate and nothing ever changes it, and a field that is
-- held and never read is a field somebody later has to prove is dead.
type TaskRow = {
	row: Frame,
	label: TextLabel,
	caption: TextLabel,
	fill: Frame,
}

export type StatsUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		ageLabel: TextLabel,
		stageLabel: TextLabel,
		moneyLabel: TextLabel,
		shiftRow: Frame,
		shiftLabel: TextLabel,
		shiftCaption: TextLabel,
		shiftFill: Frame,
		shiftXpTrack: Frame,
		shiftXpFill: Frame,
		shiftXpLabel: TextLabel,
		-- Fixed at two, matching `Config.Work.Tasks.MaxConcurrent`, and built once at
		-- startup rather than created and destroyed as tasks arrive. A row that is
		-- rebuilt is a row that jumps the whole panel down a line the instant the shop
		-- asks for a second thing -- which is precisely the moment the player is reading
		-- the first one.
		taskRows: { TaskRow },
		lessonRow: Frame,
		lessonLabel: TextLabel,
		lessonCaption: TextLabel,
		lessonFill: Frame,
		personRow: Frame,
		personLabel: TextLabel,
		personCaption: TextLabel,
		progressFill: Frame,
		progressCaption: TextLabel,
		ageUpButton: TextButton,
		noticeFrame: Frame,
		noticeLabel: TextLabel,
		noticeToken: number,
		deathFrame: Frame,
		deathLabel: TextLabel,
		deathButton: TextButton,
		deathNoteLabel: TextLabel,
		-- Verdict UI elements, created once and hidden until a ribbon is earned.
		verdictTitle: TextLabel,
		verdictDesc: TextLabel,
		verdictMoments: TextLabel,
		verdictNearMiss: TextLabel,
		statBars: { [StatName]: { fill: Frame, label: TextLabel } },
		workoutRow: Frame,
		workoutLabel: TextLabel,
		workoutCaption: TextLabel,
		sweepTrack: Frame,
		sweepBand: Frame,
		sweepPerfect: Frame,
		sweepNeedle: Frame,
		pushButton: TextButton,
		sweepConnection: RBXScriptConnection?,
		sweepPhase: string?,
		sweepBaseProgress: number,
		sweepElapsed: number,
		dealerRow: Frame,
		dealerLabel: TextLabel,
	},
	StatsUI
))

local function formatDuration(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function makeStatRow(parent: Instance, order: number, label: string): { fill: Frame, label: TextLabel }
	local row = Instance.new("Frame")
	row.Name = label .. "Row"
	row.Size = UDim2.new(1, 0, 0, 28)
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Parent = parent

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 10)
	track.Position = UDim2.new(0, 0, 1, -10)
	track.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	track.BorderSizePixel = 0
	track.Parent = row

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = GOOD_STAT_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Label"
	textLabel.Size = UDim2.new(1, 0, 0, 18)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.GothamMedium
	textLabel.TextSize = 14
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
	textLabel.Text = label .. ": --"
	textLabel.Parent = row

	return { fill = fill, label = textLabel }
end

-- One row of "go here before this runs out". Built by a function rather than written
-- twice because there are two of them now and there is exactly one thing worse than a
-- HUD that only reports half of what the shift is asking for: two rows that drifted
-- apart in font, height or urgency color and so read as two different kinds of demand.
local function makeTaskRow(parent: Instance, order: number): TaskRow
	local row = Instance.new("Frame")
	row.Name = "TaskRow"
	row.Size = UDim2.new(1, 0, 0, 34)
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Visible = false
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(240, 232, 214)
	label.Text = ""
	label.Parent = row

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.Size = UDim2.new(1, 0, 0, 13)
	caption.Position = UDim2.new(0, 0, 0, 15)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.Gotham
	caption.TextSize = 11
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextColor3 = TASK_CAPTION_COLOR
	caption.Text = ""
	caption.Parent = row

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 4)
	track.Position = UDim2.new(0, 0, 1, -4)
	track.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	track.BorderSizePixel = 0
	track.Parent = row

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = TASK_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track

	return { row = row, label = label, caption = caption, fill = fill }
end

function StatsUI.new(): StatsUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true

	local panel = Instance.new("Frame")
	panel.Name = "StatsPanel"
	-- Height follows its contents so hiding the Age Up button in the earliest
	-- years doesn't leave a hole in the panel.
	panel.Size = UDim2.new(0, 220, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 16)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
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
	layout.Padding = UDim.new(0, 4)
	layout.Parent = panel

	local ageLabel = Instance.new("TextLabel")
	ageLabel.Name = "AgeLabel"
	ageLabel.Size = UDim2.new(1, 0, 0, 20)
	ageLabel.BackgroundTransparency = 1
	ageLabel.Font = Enum.Font.GothamBold
	ageLabel.TextSize = 16
	ageLabel.TextXAlignment = Enum.TextXAlignment.Left
	ageLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	ageLabel.Text = "Age: --"
	ageLabel.LayoutOrder = 0
	ageLabel.Parent = panel

	local stageLabel = Instance.new("TextLabel")
	stageLabel.Name = "StageLabel"
	stageLabel.Size = UDim2.new(1, 0, 0, 16)
	stageLabel.BackgroundTransparency = 1
	stageLabel.Font = Enum.Font.Gotham
	stageLabel.TextSize = 13
	stageLabel.TextXAlignment = Enum.TextXAlignment.Left
	stageLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
	stageLabel.Text = "Childhood"
	stageLabel.LayoutOrder = 1
	stageLabel.Parent = panel

	-- Above the stat bars rather than among them, because it is not one. A balance is
	-- a fact about the player's situation like their age and their stage, and it wants
	-- to be readable at a glance from the same place they read those -- especially
	-- while standing in front of a choice they may not be able to afford.
	local moneyLabel = Instance.new("TextLabel")
	moneyLabel.Name = "MoneyLabel"
	moneyLabel.Size = UDim2.new(1, 0, 0, 18)
	moneyLabel.BackgroundTransparency = 1
	moneyLabel.Font = Enum.Font.GothamMedium
	moneyLabel.TextSize = 15
	moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
	moneyLabel.TextColor3 = MONEY_COLOR
	-- Formatted rather than a placeholder, because the server pushes the real balance
	-- on join and a life starts at zero anyway: "$0" is true from the first frame, and
	-- a dash would only ever be visible as a flicker.
	moneyLabel.Text = Money.Format(0)
	moneyLabel.LayoutOrder = 2
	moneyLabel.Parent = panel

	-- The workout: the one row that asks for timing. Shown only while a workout is
	-- running -- not while an offer is up, because the offer panel is the thing on
	-- screen then -- and built unlike any other row. Every other bar on this HUD
	-- fills toward something or empties away from it; this one is a needle the
	-- player has to hit, which is a different thing to read.
	--
	-- Hidden outright until a session starts, for the same reason the shift row is
	-- until a job exists: a row about nothing teaches the player not to look at it.
	-- UIListLayout skips invisible children, so this costs no space when it is off.
	local workoutRow = Instance.new("Frame")
	workoutRow.Name = "WorkoutRow"
	workoutRow.Size = UDim2.new(1, 0, 0, 46)
	workoutRow.LayoutOrder = 2.5
	workoutRow.BackgroundTransparency = 1
	workoutRow.Visible = false
	workoutRow.Parent = panel

	local workoutLabel = Instance.new("TextLabel")
	workoutLabel.Name = "Label"
	workoutLabel.Size = UDim2.new(1, 0, 0, 18)
	workoutLabel.BackgroundTransparency = 1
	workoutLabel.Font = Enum.Font.GothamMedium
	workoutLabel.TextSize = 14
	workoutLabel.TextXAlignment = Enum.TextXAlignment.Left
	workoutLabel.TextColor3 = Color3.fromRGB(240, 232, 214)
	workoutLabel.Text = ""
	workoutLabel.Parent = workoutRow

	-- The track the needle sweeps across. Wider and taller than a stat bar, because
	-- for ten seconds at a time it is the whole game.
	local sweepTrack = Instance.new("Frame")
	sweepTrack.Name = "Track"
	sweepTrack.Size = UDim2.new(1, 0, 0, 12)
	sweepTrack.Position = UDim2.new(0, 0, 0, 19)
	sweepTrack.BackgroundColor3 = Color3.fromRGB(34, 34, 40)
	sweepTrack.BorderSizePixel = 0
	sweepTrack.Parent = workoutRow

	-- The sweet zone: the band around centre that counts as a hit.
	local sweepBand = Instance.new("Frame")
	sweepBand.Name = "SweetBand"
	sweepBand.Size = UDim2.new(PLACEHOLDER_HALF * 2, 0, 1, 0)
	sweepBand.Position = UDim2.new(0.5 - PLACEHOLDER_HALF, 0, 0, 0)
	sweepBand.BackgroundColor3 = SWEEP_BAND_COLOR
	sweepBand.BorderSizePixel = 0
	sweepBand.Parent = sweepTrack

	-- The perfect zone: the inner, brighter band.
	local sweepPerfect = Instance.new("Frame")
	sweepPerfect.Name = "PerfectBand"
	sweepPerfect.Size = UDim2.new(PLACEHOLDER_HALF * 2, 0, 1, 0)
	sweepPerfect.Position = UDim2.new(0.5 - PLACEHOLDER_HALF, 0, 0, 0)
	sweepPerfect.BackgroundColor3 = SWEEP_PERFECT_COLOR
	sweepPerfect.BorderSizePixel = 0
	sweepPerfect.Parent = sweepTrack

	local sweepNeedle = Instance.new("Frame")
	sweepNeedle.Name = "Needle"
	sweepNeedle.Size = UDim2.new(0, 2, 1, 0)
	sweepNeedle.AnchorPoint = Vector2.new(0.5, 0)
	sweepNeedle.Position = UDim2.new(0, 0, 0, 0)
	sweepNeedle.BackgroundColor3 = SWEEP_NEEDLE_COLOR
	sweepNeedle.BorderSizePixel = 0
	sweepNeedle.Parent = sweepTrack

	local workoutCaption = Instance.new("TextLabel")
	workoutCaption.Name = "Caption"
	workoutCaption.Size = UDim2.new(1, 0, 0, 13)
	workoutCaption.Position = UDim2.new(0, 0, 0, 33)
	workoutCaption.BackgroundTransparency = 1
	workoutCaption.Font = Enum.Font.Gotham
	workoutCaption.TextSize = 11
	workoutCaption.TextXAlignment = Enum.TextXAlignment.Left
	workoutCaption.TextColor3 = TASK_CAPTION_COLOR
	workoutCaption.Text = ""
	workoutCaption.Parent = workoutRow

	-- Work. Hidden outright until the player holds a job, because for the first
	-- sixteen years of a life it would be a row about nothing -- and a HUD element
	-- that is empty most of the time teaches the player not to look at it.
	-- UIListLayout skips invisible children, so this costs no space when it is off.
	local shiftRow = Instance.new("Frame")
	shiftRow.Name = "ShiftRow"
	shiftRow.Size = UDim2.new(1, 0, 0, 38)
	shiftRow.LayoutOrder = 3
	shiftRow.BackgroundTransparency = 1
	shiftRow.Visible = false
	shiftRow.Parent = panel

	local shiftLabel = Instance.new("TextLabel")
	shiftLabel.Name = "Label"
	shiftLabel.Size = UDim2.new(1, 0, 0, 18)
	shiftLabel.BackgroundTransparency = 1
	shiftLabel.Font = Enum.Font.GothamMedium
	shiftLabel.TextSize = 14
	shiftLabel.TextXAlignment = Enum.TextXAlignment.Left
	shiftLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
	shiftLabel.Text = ""
	shiftLabel.Parent = shiftRow

	local shiftCaption = Instance.new("TextLabel")
	shiftCaption.Name = "Caption"
	shiftCaption.Size = UDim2.new(1, 0, 0, 14)
	shiftCaption.Position = UDim2.new(0, 0, 0, 17)
	shiftCaption.BackgroundTransparency = 1
	shiftCaption.Font = Enum.Font.Gotham
	shiftCaption.TextSize = 11
	shiftCaption.TextXAlignment = Enum.TextXAlignment.Left
	shiftCaption.TextColor3 = Color3.fromRGB(140, 140, 155)
	shiftCaption.Text = ""
	shiftCaption.Parent = shiftRow

	local shiftTrack = Instance.new("Frame")
	shiftTrack.Name = "Track"
	shiftTrack.Size = UDim2.new(1, 0, 0, 4)
	shiftTrack.Position = UDim2.new(0, 0, 1, -4)
	shiftTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	shiftTrack.BorderSizePixel = 0
	shiftTrack.Parent = shiftRow

	local shiftFill = Instance.new("Frame")
	shiftFill.Name = "Fill"
	shiftFill.Size = UDim2.new(0, 0, 1, 0)
	shiftFill.BackgroundColor3 = SHIFT_COLOR
	shiftFill.BorderSizePixel = 0
	shiftFill.Parent = shiftTrack

	-- The standing XP track beneath the shift clock. A thin progress bar so the player
	-- can see how close they are to the next band, independent of how much of the shift
	-- is left. Same width as the track above it, slightly dimmer colour so it reads as
	-- a second track rather than a doubled-up one.
	local shiftXpTrack = Instance.new("Frame")
	shiftXpTrack.Name = "XpTrack"
	shiftXpTrack.Size = UDim2.new(1, 0, 0, 2)
	shiftXpTrack.Position = UDim2.new(0, 0, 1, -2)
	shiftXpTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	shiftXpTrack.BorderSizePixel = 0
	shiftXpTrack.Parent = shiftRow

	local shiftXpFill = Instance.new("Frame")
	shiftXpFill.Name = "XpFill"
	shiftXpFill.Size = UDim2.new(0, 0, 1, 0)
	shiftXpFill.BackgroundColor3 = SHIFT_COLOR
	shiftXpFill.BorderSizePixel = 0
	shiftXpFill.Parent = shiftXpTrack

	local shiftXpLabel = Instance.new("TextLabel")
	shiftXpLabel.Name = "XpLabel"
	shiftXpLabel.Size = UDim2.new(1, 0, 0, 10)
	shiftXpLabel.Position = UDim2.new(0, 0, 1, -10)
	shiftXpLabel.BackgroundTransparency = 1
	shiftXpLabel.Font = Enum.Font.Gotham
	shiftXpLabel.TextSize = 9
	shiftXpLabel.TextXAlignment = Enum.TextXAlignment.Left
	shiftXpLabel.TextColor3 = Color3.fromRGB(120, 160, 140)
	shiftXpLabel.Text = ""
	shiftXpLabel.Parent = shiftRow

	-- AutoPia dealership: how many walk-ins are waiting and whether the front
	-- customer is currently being served. Hidden when there is nobody in queue
	-- and the player is not inside interact range, because a row that reads
	-- "0 waiting" every time the player walks past the dealership is noise.
	local dealerRow = Instance.new("Frame")
	dealerRow.Name = "DealerRow"
	dealerRow.Size = UDim2.new(1, 0, 0, 24)
	dealerRow.LayoutOrder = 4.25
	dealerRow.BackgroundTransparency = 1
	dealerRow.Visible = false
	dealerRow.Parent = panel

	local dealerLabel = Instance.new("TextLabel")
	dealerLabel.Name = "Label"
	dealerLabel.Size = UDim2.new(1, 0, 1, 0)
	dealerLabel.BackgroundTransparency = 1
	dealerLabel.Font = Enum.Font.GothamMedium
	dealerLabel.TextSize = 12
	dealerLabel.TextXAlignment = Enum.TextXAlignment.Left
	dealerLabel.TextColor3 = Color3.fromRGB(210, 195, 140)
	dealerLabel.Text = ""
	dealerLabel.Parent = dealerRow

	-- What you are doing this minute, as opposed to what you are doing this year.
	--
	-- Its own row directly under the shift, and hidden whenever there is no task,
	-- which is nearly always: this appears for fifteen seconds at a time, eight or
	-- nine times inside a four-minute shift, and never once in the sixteen years
	-- before the first job. A row that is empty most of the time teaches the player
	-- not to look at it -- so this one is never empty, it is simply not there.
	--
	-- Two of them, because for most of a shift the shop is asking for two things at
	-- once and a HUD that can only hold one of them would be hiding the entire decision
	-- the job is built around. They sit at 4 and 4.5 so the lesson row below keeps the
	-- number it has always had -- the second task row is squeezed into the gap rather
	-- than shifting every row under it, which is how a HUD stays stable while it grows.
	--
	-- Order is stable and meaningful: `SetTasks` fills them in the order the server sent,
	-- which is the order the tasks were issued, so the older task is always the upper
	-- row. The player's eye does not have to re-find which one is about to run out.
	local taskRows: { TaskRow } = { makeTaskRow(panel, 4), makeTaskRow(panel, 4.5) }

	-- The lesson row. Deliberately the task row again, one size larger: same shape,
	-- same colors, same countdown emptying left to right, because a lesson and a shift
	-- are the same promise to the player -- go somewhere before this runs out -- and a
	-- second visual language for the second half of that promise would be the game
	-- teaching itself twice.
	--
	-- Larger only because a question is a sentence and a task is a phrase. This is the
	-- one label on the HUD that wraps.
	local lessonRow = Instance.new("Frame")
	lessonRow.Name = "LessonRow"
	lessonRow.Size = UDim2.new(1, 0, 0, 48)
	lessonRow.LayoutOrder = 5
	lessonRow.BackgroundTransparency = 1
	lessonRow.Visible = false
	lessonRow.Parent = panel

	local lessonLabel = Instance.new("TextLabel")
	lessonLabel.Name = "Label"
	lessonLabel.Size = UDim2.new(1, 0, 0, 30)
	lessonLabel.BackgroundTransparency = 1
	lessonLabel.Font = Enum.Font.GothamMedium
	lessonLabel.TextSize = 13
	lessonLabel.TextXAlignment = Enum.TextXAlignment.Left
	lessonLabel.TextYAlignment = Enum.TextYAlignment.Top
	lessonLabel.TextWrapped = true
	lessonLabel.TextColor3 = Color3.fromRGB(240, 232, 214)
	lessonLabel.Text = ""
	lessonLabel.Parent = lessonRow

	local lessonCaption = Instance.new("TextLabel")
	lessonCaption.Name = "Caption"
	lessonCaption.Size = UDim2.new(1, 0, 0, 13)
	lessonCaption.Position = UDim2.new(0, 0, 0, 30)
	lessonCaption.BackgroundTransparency = 1
	lessonCaption.Font = Enum.Font.Gotham
	lessonCaption.TextSize = 11
	lessonCaption.TextXAlignment = Enum.TextXAlignment.Left
	lessonCaption.TextWrapped = true
	lessonCaption.TextColor3 = TASK_CAPTION_COLOR
	lessonCaption.Text = ""
	lessonCaption.Parent = lessonRow

	local lessonTrack = Instance.new("Frame")
	lessonTrack.Name = "Track"
	lessonTrack.Size = UDim2.new(1, 0, 0, 4)
	lessonTrack.Position = UDim2.new(0, 0, 1, -4)
	lessonTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	lessonTrack.BorderSizePixel = 0
	lessonTrack.Parent = lessonRow

	local lessonFill = Instance.new("Frame")
	lessonFill.Name = "Fill"
	lessonFill.Size = UDim2.new(1, 0, 1, 0)
	lessonFill.BackgroundColor3 = TASK_COLOR
	lessonFill.BorderSizePixel = 0
	lessonFill.Parent = lessonTrack

	-- Who you are standing next to, and what they just said back.
	--
	-- The only row on this HUD with no bar under it, and that absence is the design. A
	-- shift, a task and a lesson are all things with a clock running; a conversation is
	-- not, and drawing an empty track under it would promise a countdown that never
	-- comes. It is also the only row where the second line is somebody talking rather
	-- than the game reporting, which is why the reply is the part that gets the colour.
	local personRow = Instance.new("Frame")
	personRow.Name = "PersonRow"
	personRow.Size = UDim2.new(1, 0, 0, 44)
	personRow.LayoutOrder = 6
	personRow.BackgroundTransparency = 1
	personRow.Visible = false
	personRow.Parent = panel

	local personLabel = Instance.new("TextLabel")
	personLabel.Name = "Label"
	personLabel.Size = UDim2.new(1, 0, 0, 16)
	personLabel.BackgroundTransparency = 1
	personLabel.Font = Enum.Font.GothamBold
	personLabel.TextSize = 13
	personLabel.TextXAlignment = Enum.TextXAlignment.Left
	personLabel.TextColor3 = Color3.fromRGB(240, 232, 214)
	personLabel.Text = ""
	personLabel.Parent = personRow

	local personCaption = Instance.new("TextLabel")
	personCaption.Name = "Caption"
	personCaption.Size = UDim2.new(1, 0, 0, 26)
	personCaption.Position = UDim2.new(0, 0, 0, 17)
	personCaption.BackgroundTransparency = 1
	personCaption.Font = Enum.Font.Gotham
	personCaption.TextSize = 11
	personCaption.TextXAlignment = Enum.TextXAlignment.Left
	personCaption.TextYAlignment = Enum.TextYAlignment.Top
	personCaption.TextWrapped = true
	personCaption.TextColor3 = TASK_CAPTION_COLOR
	personCaption.Text = ""
	personCaption.Parent = personRow

	local progressRow = Instance.new("Frame")
	progressRow.Name = "AutoAgeUpRow"
	progressRow.Size = UDim2.new(1, 0, 0, 24)
	progressRow.LayoutOrder = 7
	progressRow.BackgroundTransparency = 1
	progressRow.Parent = panel

	local progressCaption = Instance.new("TextLabel")
	progressCaption.Name = "Caption"
	progressCaption.Size = UDim2.new(1, 0, 0, 14)
	progressCaption.BackgroundTransparency = 1
	progressCaption.Font = Enum.Font.Gotham
	progressCaption.TextSize = 11
	progressCaption.TextXAlignment = Enum.TextXAlignment.Left
	progressCaption.TextColor3 = Color3.fromRGB(140, 140, 155)
	progressCaption.Text = "Growing up"
	progressCaption.Parent = progressRow

	local progressTrack = Instance.new("Frame")
	progressTrack.Name = "Track"
	progressTrack.Size = UDim2.new(1, 0, 0, 4)
	progressTrack.Position = UDim2.new(0, 0, 1, -4)
	progressTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	progressTrack.BorderSizePixel = 0
	progressTrack.Parent = progressRow

	local progressFill = Instance.new("Frame")
	progressFill.Name = "Fill"
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.BackgroundColor3 = PROGRESS_COLOR
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressTrack

	local statBars: { [StatName]: { fill: Frame, label: TextLabel } } = {}
	for i, entry in STAT_ORDER do
		-- Offset past the fixed rows above: age, stage, money, shift, task, lesson, person,
		-- growing-up.
		statBars[entry.name] = makeStatRow(panel, i + 7, entry.label)
	end

	local ageUpButton = Instance.new("TextButton")
	ageUpButton.Name = "AgeUpButton"
	ageUpButton.Size = UDim2.new(1, 0, 0, 32)
	ageUpButton.LayoutOrder = #STAT_ORDER + 8
	ageUpButton.BackgroundColor3 = COOLDOWN_COLOR
	ageUpButton.BorderSizePixel = 0
	ageUpButton.AutoButtonColor = false
	ageUpButton.Font = Enum.Font.GothamBold
	ageUpButton.TextSize = 15
	ageUpButton.TextColor3 = Color3.fromRGB(120, 120, 130)
	ageUpButton.Text = "Age Up"
	ageUpButton.Visible = false
	ageUpButton.Parent = panel

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = ageUpButton

	local noticeFrame = Instance.new("Frame")
	noticeFrame.Name = "Notice"
	noticeFrame.AnchorPoint = Vector2.new(0.5, 1)
	noticeFrame.Position = UDim2.new(0.5, 0, 1, -48)
	noticeFrame.Size = UDim2.new(0, 420, 0, 40)
	noticeFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	noticeFrame.BackgroundTransparency = 1
	noticeFrame.BorderSizePixel = 0
	noticeFrame.Visible = false
	noticeFrame.Parent = screenGui

	local noticeCorner = Instance.new("UICorner")
	noticeCorner.CornerRadius = UDim.new(0, 8)
	noticeCorner.Parent = noticeFrame

	local noticeLabel = Instance.new("TextLabel")
	noticeLabel.Name = "Label"
	noticeLabel.Size = UDim2.new(1, -24, 1, 0)
	noticeLabel.Position = UDim2.new(0, 12, 0, 0)
	noticeLabel.BackgroundTransparency = 1
	noticeLabel.Font = Enum.Font.Gotham
	noticeLabel.TextSize = 14
	noticeLabel.TextColor3 = Color3.fromRGB(225, 225, 235)
	noticeLabel.TextTransparency = 1
	noticeLabel.Text = ""
	noticeLabel.Parent = noticeFrame

	local deathFrame = Instance.new("Frame")
	deathFrame.Name = "DeathScreen"
	deathFrame.Size = UDim2.new(1, 0, 1, 0)
	deathFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	deathFrame.BackgroundTransparency = 0.35
	deathFrame.Visible = false
	deathFrame.ZIndex = 10
	deathFrame.Parent = screenGui

	local deathLabel = Instance.new("TextLabel")
	deathLabel.Name = "DeathLabel"
	deathLabel.Size = UDim2.new(0, 500, 0, 80)
	deathLabel.AnchorPoint = Vector2.new(0.5, 1)
	deathLabel.Position = UDim2.new(0.5, 0, 0.5, 8)
	deathLabel.BackgroundTransparency = 1
	deathLabel.Font = Enum.Font.GothamBold
	deathLabel.TextSize = 28
	deathLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	deathLabel.Text = ""
	deathLabel.ZIndex = 11
	deathLabel.Parent = deathFrame

	-- The one control on the death screen, and the only way out of this place.
	--
	-- It is here rather than nowhere because a death screen that only ever clears on a timer
	-- is a screen the player is made to sit through. The server sends them back after
	-- `Config.Death.RespawnDelaySeconds` regardless -- this is the same trip, taken sooner,
	-- and pressing it is idempotent on the server side, so an impatient double-press is one
	-- teleport.
	local deathButton = Instance.new("TextButton")
	deathButton.Name = "BackToMenu"
	deathButton.Size = UDim2.new(0, 260, 0, 46)
	deathButton.AnchorPoint = Vector2.new(0.5, 0)
	deathButton.Position = UDim2.new(0.5, 0, 0.5, 20)
	deathButton.BackgroundColor3 = Color3.fromRGB(238, 232, 220)
	deathButton.AutoButtonColor = true
	deathButton.Font = Enum.Font.GothamBold
	deathButton.TextSize = 17
	deathButton.TextColor3 = Color3.fromRGB(24, 20, 14)
	deathButton.Text = "Back to the menu"
	deathButton.ZIndex = 11
	deathButton.Parent = deathFrame

	local deathButtonCorner = Instance.new("UICorner")
	deathButtonCorner.CornerRadius = UDim.new(0, 8)
	deathButtonCorner.Parent = deathButton

	-- Where a refusal lands. Under the button rather than in the log, because the two
	-- refusals that actually happen -- Studio, and an unpublished lobby place id -- are both
	-- sentences somebody needs to read while looking at the button that did nothing.
	local deathNoteLabel = Instance.new("TextLabel")
	deathNoteLabel.Name = "DeathNote"
	deathNoteLabel.Size = UDim2.new(0, 520, 0, 56)
	deathNoteLabel.AnchorPoint = Vector2.new(0.5, 0)
	deathNoteLabel.Position = UDim2.new(0.5, 0, 0.5, 78)
	deathNoteLabel.BackgroundTransparency = 1
	deathNoteLabel.Font = Enum.Font.Gotham
	deathNoteLabel.TextSize = 14
	deathNoteLabel.TextWrapped = true
	deathNoteLabel.TextColor3 = Color3.fromRGB(240, 180, 160)
	deathNoteLabel.Text = ""
	deathNoteLabel.ZIndex = 11
	deathNoteLabel.Parent = deathFrame

	-- Verdict content, hidden until a ribbon is earned.
	local verdictTitle = Instance.new("TextLabel")
	verdictTitle.Name = "VerdictTitle"
	verdictTitle.Size = UDim2.new(0, 520, 0, 48)
	verdictTitle.AnchorPoint = Vector2.new(0.5, 0)
	verdictTitle.Position = UDim2.new(0.5, 0, 0.5, 100)
	verdictTitle.BackgroundTransparency = 1
	verdictTitle.Font = Enum.Font.GothamBold
	verdictTitle.TextSize = 24
	verdictTitle.TextColor3 = Color3.fromRGB(255, 230, 180)
	verdictTitle.TextWrapped = false
	verdictTitle.Text = ""
	verdictTitle.ZIndex = 11
	verdictTitle.Visible = false
	verdictTitle.Parent = deathFrame

	local verdictDesc = Instance.new("TextLabel")
	verdictDesc.Name = "VerdictDesc"
	verdictDesc.Size = UDim2.new(0, 520, 0, 36)
	verdictDesc.AnchorPoint = Vector2.new(0.5, 0)
	verdictDesc.Position = UDim2.new(0.5, 0, 0.5, 152)
	verdictDesc.BackgroundTransparency = 1
	verdictDesc.Font = Enum.Font.Gotham
	verdictDesc.TextSize = 14
	verdictDesc.TextColor3 = Color3.fromRGB(200, 190, 175)
	verdictDesc.TextWrapped = true
	verdictDesc.Text = ""
	verdictDesc.ZIndex = 11
	verdictDesc.Visible = false
	verdictDesc.Parent = deathFrame

	local verdictMoments = Instance.new("TextLabel")
	verdictMoments.Name = "VerdictMoments"
	verdictMoments.Size = UDim2.new(0, 520, 0, 100)
	verdictMoments.AnchorPoint = Vector2.new(0.5, 0)
	verdictMoments.Position = UDim2.new(0.5, 0, 0.5, 194)
	verdictMoments.BackgroundTransparency = 1
	verdictMoments.Font = Enum.Font.Gotham
	verdictMoments.TextSize = 13
	verdictMoments.TextColor3 = Color3.fromRGB(180, 180, 195)
	verdictMoments.TextWrapped = true
	verdictMoments.Text = ""
	verdictMoments.ZIndex = 11
	verdictMoments.Visible = false
	verdictMoments.Parent = deathFrame

	local verdictNearMiss = Instance.new("TextLabel")
	verdictNearMiss.Name = "VerdictNearMiss"
	verdictNearMiss.Size = UDim2.new(0, 520, 0, 56)
	verdictNearMiss.AnchorPoint = Vector2.new(0.5, 0)
	verdictNearMiss.Position = UDim2.new(0.5, 0, 0.5, 300)
	verdictNearMiss.BackgroundTransparency = 1
	-- Enum.Font has no italic Gotham -- SourceSansItalic is the only italic face in
	-- it, and switching family for one footnote would read as a mistake next to the
	-- all-Gotham block above. Enum.Font.GothamItalic does not exist, and naming it
	-- threw on the client bootstrap, which is why no UI rendered at all. The
	-- footnote reading is already carried without italics: this is the smallest text
	-- in the death frame and the dimmest colour in it.
	verdictNearMiss.Font = Enum.Font.Gotham
	verdictNearMiss.TextSize = 12
	verdictNearMiss.TextColor3 = Color3.fromRGB(160, 155, 145)
	verdictNearMiss.TextWrapped = true
	verdictNearMiss.Text = ""
	verdictNearMiss.ZIndex = 11
	verdictNearMiss.Visible = false
	verdictNearMiss.Parent = deathFrame

	-- The one button that asks the player for timing. Bottom-centre, where a
	-- rhythm-action button belongs: it is the only thing on screen during a rep
	-- that is meant to be pressed, and it has to be findable while the eyes are
	-- on the sweep bar. Grey and inert while a verdict is up, because there is
	-- nothing to push during a verdict and a button that vanished would be harder
	-- to find when the next rep starts.
	local pushButton = Instance.new("TextButton")
	pushButton.Name = "PushButton"
	pushButton.Size = UDim2.new(0, 220, 0, 56)
	pushButton.AnchorPoint = Vector2.new(0.5, 1)
	pushButton.Position = UDim2.new(0.5, 0, 1, -24)
	pushButton.BackgroundColor3 = PUSH_INACTIVE_COLOR
	pushButton.AutoButtonColor = false
	pushButton.Font = Enum.Font.GothamBold
	pushButton.TextSize = 20
	pushButton.TextColor3 = Color3.fromRGB(120, 120, 130)
	pushButton.Text = "PUSH"
	pushButton.Visible = false
	pushButton.Parent = screenGui

	local pushCorner = Instance.new("UICorner")
	pushCorner.CornerRadius = UDim.new(0, 10)
	pushCorner.Parent = pushButton

	screenGui.Parent = playerGui

	return setmetatable({
		screenGui = screenGui,
		ageLabel = ageLabel,
		stageLabel = stageLabel,
		moneyLabel = moneyLabel,
		shiftRow = shiftRow,
		taskRows = taskRows,
		lessonRow = lessonRow,
		lessonLabel = lessonLabel,
		lessonCaption = lessonCaption,
		lessonFill = lessonFill,
		personRow = personRow,
		personLabel = personLabel,
		personCaption = personCaption,
		shiftLabel = shiftLabel,
		shiftCaption = shiftCaption,
		shiftFill = shiftFill,
		shiftXpTrack = shiftXpTrack,
		shiftXpFill = shiftXpFill,
		shiftXpLabel = shiftXpLabel,
		progressFill = progressFill,
		progressCaption = progressCaption,
		ageUpButton = ageUpButton,
		noticeFrame = noticeFrame,
		noticeLabel = noticeLabel,
		noticeToken = 0,
		deathFrame = deathFrame,
		deathLabel = deathLabel,
		deathButton = deathButton,
		deathNoteLabel = deathNoteLabel,
		statBars = statBars,
		workoutRow = workoutRow,
		workoutLabel = workoutLabel,
		workoutCaption = workoutCaption,
		sweepTrack = sweepTrack,
		sweepBand = sweepBand,
		sweepPerfect = sweepPerfect,
		sweepNeedle = sweepNeedle,
		pushButton = pushButton,
		sweepConnection = nil,
		sweepPhase = nil,
		sweepBaseProgress = 0,
		sweepElapsed = 0,
		dealerRow = dealerRow,
		dealerLabel = dealerLabel,
	}, StatsUI)
end

function StatsUI.SetAge(self: StatsUIHandle, years: number)
	self.ageLabel.Text = `Age: {years}`
end

function StatsUI.SetStage(self: StatsUIHandle, stage: string)
	self.stageLabel.Text = stage
end

-- No animation and no flash. A balance that counted up would be a slot machine, and
-- the one thing the money in this game must never feel like is a reward for
-- pressing something.
function StatsUI.SetMoney(self: StatsUIHandle, balance: number)
	self.moneyLabel.Text = Money.Format(balance)
end

-- The shift, or the lack of one. Four states, deliberately different shapes rather
-- than the same row with blanks in it:
--
--   nothing     hidden. Most of a life, and a row about nothing is a row the
--               player learns to stop reading.
--   turned away what this place wants from you before it will have you. Shown even
--               with no job at all -- see below, it is the most important of the
--               four despite being the rarest.
--   off shift   what you do, what they make of you, and how much of the year you
--               have worked. Answers "can I go and earn something right now".
--   on shift    a bar that fills, and what it has paid so far.
--
-- Earnings are shown against the shift, never as a rate. A wage of "$200 an hour"
-- is arithmetic that happens to be true and reads as a lie, because the hour it
-- refers to is a game hour and lasts thirty seconds.
--
-- A record is shown as a phrase and never as a number, for a related reason: "14"
-- is a true thing about a hidden variable, and "Well thought of" is the thing the
-- number was always standing in for.
function StatsUI.SetShift(self: StatsUIHandle, state: ShiftState)
	local title = state.jobTitle
	local blockedReason = state.blockedReason

	if title == nil and blockedReason == nil then
		self.shiftRow.Visible = false
		return
	end
	self.shiftRow.Visible = true

	-- Takes priority over everything, including a shift's own progress, because the
	-- server only ever sets it for a player standing at a station they cannot use.
	-- Clocking on is automatic and proximity-based, so being turned away is
	-- otherwise *silent*: you walk into the office at eighteen, nothing happens, and
	-- a career ladder you cannot see is indistinguishable from a door that is broken.
	if blockedReason ~= nil then
		self.shiftLabel.Text = title or "Not hired here"
		self.shiftCaption.Text = blockedReason
		self.shiftFill.Size = UDim2.new(0, 0, 1, 0)
		self.shiftXpTrack.Visible = false
		self.shiftXpLabel.Text = ""
		return
	end

	-- Past this point there is a job, since having neither was handled above. The
	-- cast says what the control flow already guarantees and the type cannot see.
	local heldTitle = title :: string

	if not state.onShift then
		self.shiftLabel.Text = heldTitle
		-- The record leads, because off shift it is what has changed since the player
		-- last looked and what decides whether the next rung is open to them.
		--
		-- Sentence-cased here rather than authored capitalized, because the same
		-- phrase has to read correctly mid-sentence in a refusal ("You need to be well
		-- thought of as a Shop assistant first") and as a heading in this row.
		local standing = state.standing
		local worked = `{state.shiftsThisYear} of {state.shiftsPerYear} shifts this year`
		self.shiftCaption.Text = if standing ~= nil
			then `{string.upper(string.sub(standing, 1, 1))}{string.sub(standing, 2)} · {worked}`
			else worked
		self.shiftFill.Size = UDim2.new(0, 0, 1, 0)
		self.shiftXpTrack.Visible = false
		self.shiftXpLabel.Text = ""
		return
	end

	local fraction = if state.shiftGameHours > 0
		then math.clamp(state.gameHoursWorked / state.shiftGameHours, 0, 1)
		else 0
	self.shiftFill.Size = UDim2.new(fraction, 0, 1, 0)

	self.shiftLabel.Text = `{heldTitle} — on shift`
	-- Hours floored rather than rounded: an hour is only worked once it is over,
	-- and it is only paid then too, so a caption reading "3 hrs" while the bar is
	-- most of the way through the fourth is telling the truth about the money.
	self.shiftCaption.Text = string.format(
		"%d of %d hrs · %s earned",
		math.floor(state.gameHoursWorked),
		state.shiftGameHours,
		Money.Format(state.earned)
	)

	-- The XP bar underneath the shift clock. Emptied whenever there is no job,
	-- because a bar that reads "0 / --" is worse than a bar that is not there.
	if state.nextBandXp ~= nil and state.nextBandXp > 0 then
		self.shiftXpTrack.Visible = true
		self.shiftXpFill.Size = UDim2.new(
			math.clamp(state.standingXp / state.nextBandXp, 0, 1), 0, 1, 0
		)
		self.shiftXpLabel.Text =
			`{state.standingXp} / {state.nextBandXp} to {string.lower(heldTitle)}`
	else
		self.shiftXpTrack.Visible = false
		self.shiftXpLabel.Text = ""
	end
end

-- One row of the only thing on this HUD that is about the next fifteen seconds.
--
-- Everything else in this panel is a standing fact -- your age, your money, your
-- record, how much of the shift is left -- and none of it changes because of anything
-- you do in the moment. These rows do. They are the only place the game asks the player
-- for something and then watches a clock, so they are the only rows allowed to be loud,
-- and the only ones that disappear completely the second they have nothing to say.
local function drawTask(parts: TaskRow, state: TaskState)
	parts.row.Visible = true

	-- The count only appears when there is one to give. "1 of 1" is a fact about the
	-- implementation; a single-mark task should just say what it is.
	--
	-- People before marks, when the task has both. On a rush the marks are the same two
	-- over and over, so "3 of 6" is a true count of nothing the player is thinking
	-- about -- what they want is how many more of these there are, and the answer to
	-- that is standing in a line in front of them. The row only has to agree with it.
	local waiting = state.waiting
	if waiting ~= nil then
		parts.label.Text = if waiting == 1
			then `{state.label}  (last one)`
			else `{state.label}  ({waiting} waiting)`
	elseif state.spotCount > 1 then
		parts.label.Text = `{state.label}  ({state.spotIndex}/{state.spotCount})`
	else
		parts.label.Text = state.label
	end

	local total = math.max(state.secondsTotal, 1)
	local left = math.max(state.secondsLeft, 0)
	local share = math.clamp(left / total, 0, 1)
	parts.fill.Size = UDim2.new(share, 0, 1, 0)

	if state.missed then
		-- The row outlives the task by a few seconds, and this is the only reason it
		-- does. Everywhere else the HUD reports a state; here it reports something that
		-- has already happened, because the alternative is a mark and a row both
		-- vanishing at once and a player who cannot tell whether they failed something
		-- or the game simply stopped asking. The shift is going to charge them for this
		-- at the end -- that price is only fair if they saw it being incurred.
		--
		-- It matters more now than it did with one task. A miss no longer means an empty
		-- HUD -- the other task is still running, still counting down, still lit on the
		-- floor -- so without this the failure would be swallowed whole by the thing the
		-- player was doing instead. Two rows is the only arrangement in which "you lost
		-- that one while you were winning this one" can be said at all.
		parts.label.Text = state.label
		parts.caption.Text = "Missed — out of time"
		parts.caption.TextColor3 = TASK_URGENT_COLOR
		parts.fill.BackgroundColor3 = TASK_URGENT_COLOR
		return
	end
	parts.caption.TextColor3 = TASK_CAPTION_COLOR

	if state.paused then
		-- Said in words rather than left to a frozen bar, because a clock that has
		-- stopped and one that has broken look exactly the same, and only one of them
		-- is worth standing still for. The player is mid-prompt and needs to know that
		-- reading it is free.
		parts.caption.Text = "Paused while you answer"
		parts.fill.BackgroundColor3 = TASK_PAUSED_COLOR
		return
	end

	-- Ceiling rather than floor, so the number reaches zero exactly as the time does
	-- instead of sitting on "0s" for a whole second while the task is still winnable.
	parts.caption.Text = `{math.ceil(left)}s left`
	local baseColor = if state.rush then TASK_RUSH_COLOR
		elseif state.spotCount > 1 then TASK_FETCH_COLOR
		else TASK_HAND_COLOR
	parts.fill.BackgroundColor3 = if share <= TASK_URGENT_SHARE then TASK_URGENT_COLOR else baseColor
end

-- Every task the shift is currently asking for, all of them every time.
--
-- A list rather than one state, and it is the whole point of the job: with one task the
-- only question a shift could ask was how fast the player walks, and there is exactly
-- one right answer to that at every instant, which is not a decision. Two running clocks
-- with two marks in two directions is the first moment the shift asks something the
-- player can get wrong on purpose -- which one to abandon.
--
-- An empty list is the usual state and it is not an error: it means the gap between
-- tasks, or the eight hours of a shift at a job with nothing authored, or the sixteen
-- years before a first job. Every row is hidden in all three, because a HUD element that
-- is empty most of the time is one players stop reading.
--
-- Extra states beyond the rows built are dropped rather than queued. The server caps
-- itself at `Config.Work.Tasks.MaxConcurrent` and this is sized to match, so a state
-- with nowhere to go means those two numbers have come apart -- and the honest failure
-- for that is a task the player cannot see, not a HUD that grows a third row nobody
-- designed the panel around.
function StatsUI.SetTasks(self: StatsUIHandle, states: { TaskState })
	for index, parts in self.taskRows do
		local state = states[index]
		if state == nil then
			parts.row.Visible = false
		else
			drawTask(parts, state)
		end
	end
end

-- The task row's twin, for the half of a life that has no job in it.
--
-- Nil is the ordinary state here too, and for longer: most of a life is not spent in a
-- lesson. Same rule as the task row -- nothing to say, nothing on screen.
--
-- Four things arrive through this one channel and they are told apart by the state
-- itself rather than by a flag, because each distinction is already visible in the
-- numbers. A live question has a clock and no verdict. A verdict has a clock's worth of
-- context but no time left on it. A notice -- a lesson's closing summary, or the door
-- refusing you -- has `count` of zero, which is the server saying this is not a question
-- and has no position in anything. And the skip offer at the door has no clock and no
-- verdict either: it is a question about the afternoon rather than about a subject, and
-- the only thing this row draws for it is the line saying what is on.
function StatsUI.SetLesson(self: StatsUIHandle, state: LessonState?)
	if state == nil then
		self.lessonRow.Visible = false
		return
	end
	self.lessonRow.Visible = true
	self.lessonLabel.Text = state.ask

	-- Kept in front of the verdict as well as the countdown, so that being told why an
	-- answer was wrong does not cost the player the one number that says how much of the
	-- lesson is left to fix it in. Absent entirely on a notice, which is about the whole
	-- lesson rather than any question in it.
	local position = if state.count > 0 then `{state.index} of {state.count} · ` else ""

	local verdict = state.verdict
	if verdict ~= nil then
		-- Green for right and the task row's urgent orange for wrong, rather than a red:
		-- a wrong answer here has already cost what it is going to cost, and the row's
		-- job now is to be read, not to alarm. The bar is emptied rather than hidden
		-- because the clock genuinely is spent -- either the question is over or there
		-- was never one running.
		local color = if state.wasRight then GOOD_STAT_COLOR else TASK_URGENT_COLOR
		self.lessonCaption.Text = position .. verdict
		self.lessonCaption.TextColor3 = color
		self.lessonFill.BackgroundColor3 = color
		self.lessonFill.Size = UDim2.new(0, 0, 1, 0)
		return
	end
	self.lessonCaption.TextColor3 = TASK_CAPTION_COLOR

	-- A push with no clock and nothing to explain: the skip offer at the school door,
	-- which is a question about the day rather than a question in a lesson. The row says
	-- what is on and the panel underneath carries the two answers, so a caption here would
	-- have to invent something -- and the arithmetic below invents "0 right · 0s left",
	-- which reads as a lesson already lost before it has started.
	--
	-- Guarded on the clock rather than on the answers, because "there is no time running"
	-- is the honest test and it is the same signal the bar is already documented as
	-- reading. See LessonState.secondsTotal.
	if state.secondsTotal <= 0 then
		self.lessonCaption.Text = ""
		self.lessonFill.Size = UDim2.new(0, 0, 1, 0)
		self.lessonFill.BackgroundColor3 = TASK_COLOR
		return
	end

	local total = math.max(state.secondsTotal, 1)
	local share = math.clamp(math.max(state.secondsLeft, 0) / total, 0, 1)
	self.lessonFill.Size = UDim2.new(share, 0, 1, 0)
	self.lessonFill.BackgroundColor3 = if share <= TASK_URGENT_SHARE then TASK_URGENT_COLOR else TASK_COLOR

	-- The running score sits between the position and the clock because it is the one
	-- number the player can still change, and the only one the smarts award is read off.
	self.lessonCaption.Text = `{position}{state.right} right · {math.ceil(math.max(state.secondsLeft, 0))}s left`
end

-- Who the player is standing next to. Nil means nobody is, which is most of a life.
--
-- The top line is a fact that holds for as long as you stand there -- their name and
-- what you are to each other. The bottom line is the contextual flavour the server
-- picked for the situation (morning, on shift, unemployed, at home) -- a mood, not a
-- moment: what they just said now speaks from over their own head instead, see
-- SpeechBubble.Show in init.client.luau, so this row never has to carry both a fact
-- that holds and a line that expires on the same beat.
--
-- The band is shown as a phrase and never as a number, because a score next to your
-- mother's name is a progress bar where a relationship should be.
function StatsUI.SetPerson(self: StatsUIHandle, state: PersonState?)
	if state == nil then
		self.personRow.Visible = false
		return
	end
	self.personRow.Visible = true
	-- The tie is shown between the name and the bond band when it exists, because a
	-- relationship label is what the row is for: it tells you who this person is to
	-- you, not just how close you are. A rival who is also "close" reads differently
	-- from a friend who is "close", and the tie is the word that makes the difference.
	local label = `{state.name} · {state.band}`
	if state.tie ~= nil and state.tie ~= "" then
		label = `{state.name} · {state.tie} · {state.band}`
	end
	self.personLabel.Text = label

	local ctx = state.contextualLine
	self.personCaption.Text = ctx ~= nil and `"{ctx}"` or ""
	self.personCaption.TextColor3 = TASK_CAPTION_COLOR
end

-- The workout, or the lack of one.
--
-- Nil and "offer" are the two ways nothing is being asked of the player right
-- now; both hide the row, because an offer is a panel and a row about a workout
-- that has not started would be a row about nothing. Rep and verdict are the two
-- ways something is: the row appears, the PUSH button appears, and the sweep
-- needle runs.
--
-- The needle is animated client-side between the server's pushes, which arrive
-- about five times a second -- a sweep that only moved in server ticks would be
-- a stagger, not a bar. Each push re-anchors the base so the client's guess is
-- corrected before it can drift by more than a tick.
function StatsUI.SetWorkout(self: StatsUIHandle, state: WorkoutState?)
	if self.sweepConnection ~= nil then
		self.sweepConnection:Disconnect()
		self.sweepConnection = nil
	end

	if state == nil or state.phase == "offer" then
		self.workoutRow.Visible = false
		self.pushButton.Visible = false
		self.sweepPhase = nil
		return
	end

	self.workoutRow.Visible = true
	self.sweepPhase = state.phase
	self.workoutLabel.Text = `{state.machineLabel} — rep {state.rep} of {state.reps}`

	-- The bands are redrawn from the state every time rather than set once at build.
	-- Two things move them: which machine this is, and how fit the character is. The
	-- second is the point -- health widens the window, and a widening the player
	-- cannot see is progression that may as well not exist.
	self.sweepBand.Size = UDim2.new(state.sweetHalf * 2, 0, 1, 0)
	self.sweepBand.Position = UDim2.new(state.sweetCenter - state.sweetHalf, 0, 0, 0)
	self.sweepPerfect.Size = UDim2.new(state.perfectHalf * 2, 0, 1, 0)
	self.sweepPerfect.Position = UDim2.new(state.sweetCenter - state.perfectHalf, 0, 0, 0)

	local staminaLine = `{state.stamina} of {state.maxStamina} stamina`
	if state.phase == "verdict" then
		-- Frozen at the position the hit landed. The bar is still, the grade
		-- is spoken, and there is nothing to time until the next rep starts.
		self.sweepNeedle.Position = UDim2.new(state.progress, 0, 0, 0)
		self.workoutCaption.Text = `{state.grade or "..."} · {staminaLine}`
		self.pushButton.BackgroundColor3 = PUSH_INACTIVE_COLOR
		self.pushButton.TextColor3 = Color3.fromRGB(120, 120, 130)
	else
		-- Interpolated forward in the machine's own curve, from the share of the
		-- sweep the server says has run. Accumulating share and re-curving it -- as
		-- opposed to advancing the needle position directly -- is what keeps a
		-- quickening bar quickening between ticks instead of sliding linearly and
		-- then jumping when the next state lands.
		self.sweepBaseProgress = state.elapsedShare
		self.sweepElapsed = 0
		self.workoutCaption.Text = staminaLine
		self.pushButton.BackgroundColor3 = PUSH_ACTIVE_COLOR
		self.pushButton.TextColor3 = Color3.fromRGB(30, 25, 10)

		local sweepSeconds = state.sweepSeconds
		local curve = state.curve
		self.sweepConnection = RunService.RenderStepped:Connect(function(dt: number)
			self.sweepElapsed += dt
			local share = math.min(1, self.sweepBaseProgress + self.sweepElapsed / sweepSeconds)
			self.sweepNeedle.Position = UDim2.new(Sweep.At(curve, share), 0, 0, 0)
		end)
	end

	self.pushButton.Visible = true
end

-- Pressed while the needle is sweeping. The server decides the quality of the
-- hit; this button only reports that a hit was attempted.
function StatsUI.OnPushActivated(self: StatsUIHandle, callback: () -> ())
	self.pushButton.Activated:Connect(callback)
end

function StatsUI.OnAgeUpActivated(self: StatsUIHandle, callback: () -> ())
	self.ageUpButton.Activated:Connect(callback)
end

function StatsUI.SetAgeUpProgress(self: StatsUIHandle, seconds: number, thresholdSeconds: number, state: ManualAgeUpState)
	local fraction = if thresholdSeconds > 0 then math.clamp(seconds / thresholdSeconds, 0, 1) else 0
	self.progressFill.Size = UDim2.new(fraction, 0, 1, 0)

	-- Through the early years the year is something happening to the player
	-- rather than something they end — true of the per-year child button as
	-- much as of the skip, since neither one is a shift or a lesson ending.
	local childhood = state == "Hidden" or state == "SkipChildhood" or state == "ChildReady" or state == "ChildCooldown"
	-- The bar names what it fills toward but never how long that takes. The
	-- threshold is a real-world duration, so showing it both broke the fiction
	-- and told the player the game would advance itself if they sat still.
	self.progressCaption.Text = if childhood then "Growing up" else "Next year"

	self.ageUpButton.Visible = state ~= "Hidden"
	if state == "SkipChildhood" then
		-- Offered only on a life after the first. Muted rather than gold: it is
		-- an escape hatch for someone who has been here before, not the thing
		-- the screen is inviting a new player to press.
		self.ageUpButton.Text = "Skip Childhood"
		self.ageUpButton.BackgroundColor3 = SKIP_COLOR
		self.ageUpButton.TextColor3 = Color3.fromRGB(215, 215, 225)
	elseif state == "Ready" or state == "ChildReady" then
		self.ageUpButton.Text = "Age Up"
		self.ageUpButton.BackgroundColor3 = READY_COLOR
		self.ageUpButton.TextColor3 = Color3.fromRGB(30, 25, 10)
	elseif state == "ChildCooldown" then
		-- Same countdown treatment as the adult cooldown below, but against the
		-- shorter child constant -- reading the adult one here would count down
		-- from a number four times too long against a bar that fills in 15.
		local remaining = math.max(0, Config.ChildManualAgeUpCooldownSeconds - seconds)
		self.ageUpButton.Text = `Age Up ({formatDuration(remaining)})`
		self.ageUpButton.BackgroundColor3 = COOLDOWN_COLOR
		self.ageUpButton.TextColor3 = Color3.fromRGB(120, 120, 130)
	else
		-- Count the wait down rather than just greying out: at a minute-long
		-- cooldown an unexplained dead button reads as a bug, not a rule.
		local remaining = math.max(0, Config.ManualAgeUpCooldownSeconds - seconds)
		self.ageUpButton.Text = `Age Up ({formatDuration(remaining)})`
		self.ageUpButton.BackgroundColor3 = COOLDOWN_COLOR
		self.ageUpButton.TextColor3 = Color3.fromRGB(120, 120, 130)
	end
end

-- A passive, expected event — it fades in at the bottom of the screen and
-- leaves on its own. Deliberately not styled like an error.
function StatsUI.ShowNotice(self: StatsUIHandle, text: string)
	self.noticeToken += 1
	local token = self.noticeToken

	self.noticeLabel.Text = text
	self.noticeFrame.Visible = true

	local fadeIn = TweenInfo.new(Config.UI.NoticeFadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(self.noticeFrame, fadeIn, { BackgroundTransparency = 0.2 }):Play()
	TweenService:Create(self.noticeLabel, fadeIn, { TextTransparency = 0 }):Play()

	task.delay(Config.UI.NoticeSeconds, function()
		-- A newer notice has taken over this frame; leave it alone.
		if self.noticeToken ~= token then
			return
		end
		local fadeOut = TweenInfo.new(Config.UI.NoticeFadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(self.noticeFrame, fadeOut, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(self.noticeLabel, fadeOut, { TextTransparency = 1 }):Play()

		task.delay(Config.UI.NoticeFadeSeconds, function()
			if self.noticeToken == token then
				self.noticeFrame.Visible = false
			end
		end)
	end)
end

function StatsUI.SetStats(self: StatsUIHandle, stats: Stats)
	for _, entry in STAT_ORDER do
		local bar = self.statBars[entry.name]
		local value = (stats :: any)[entry.name] :: number
		bar.fill.Size = UDim2.new(value / Config.Stats.Max, 0, 1, 0)
		bar.label.Text = `{entry.label}: {value}`

		if value <= Config.Stats.WarningThreshold then
			bar.fill.BackgroundColor3 = WARN_STAT_COLOR
			bar.label.TextColor3 = Color3.fromRGB(255, 140, 140)
		else
			bar.fill.BackgroundColor3 = GOOD_STAT_COLOR
			bar.label.TextColor3 = Color3.fromRGB(235, 235, 235)
		end
	end
end

-- Pressed to go back to the lobby. Not `Once`: a refusal leaves the screen up and the button
-- live, which is the whole reason a refusal is drawn on it.
function StatsUI.OnReturnActivated(self: StatsUIHandle, callback: () -> ())
	self.deathButton.Activated:Connect(callback)
end

-- The last thing this place says about a life.
--
-- "Restarting..." is what this used to say, and it was true until part 3: the same body wound
-- back to age zero and the character menu came up over the town. Nothing restarts now -- the
-- life stays dead in the slot it was lived in, and the player goes back to the menu to pick
-- another card or delete this one. The wording says so, because a screen that promises a
-- restart and then teleports somewhere else is a screen that lied.
function StatsUI.ShowDeath(self: StatsUIHandle, ageYears: number, ribbon: Ribbon?)
	if ribbon ~= nil then
		self:ShowVerdict(ribbon)
		return
	end
	self.deathLabel.Text = `You died at age {ageYears}.`
	self.deathNoteLabel.Text = ""
	self.deathFrame.Visible = true
end

function StatsUI.ShowVerdict(self: StatsUIHandle, ribbon: Ribbon)
	self.deathLabel.Text = ribbon.title
	self.deathLabel.Size = UDim2.new(0, 520, 0, 48)
	self.deathLabel.Position = UDim2.new(0.5, 0, 0.5, 100)
	self.deathLabel.AnchorPoint = Vector2.new(0.5, 0)
	self.deathLabel.TextColor3 = Color3.fromRGB(255, 230, 180)

	self.deathNoteLabel.Text = ribbon.description
	self.deathNoteLabel.Size = UDim2.new(0, 520, 0, 36)
	self.deathNoteLabel.Position = UDim2.new(0.5, 0, 0.5, 152)
	self.deathNoteLabel.AnchorPoint = Vector2.new(0.5, 0)
	self.deathNoteLabel.TextColor3 = Color3.fromRGB(200, 190, 175)
	self.deathNoteLabel.TextWrapped = true

	self.verdictMoments.Text = ""
	for i, moment in ribbon.moments do
		if i > 1 then
			self.verdictMoments.Text = self.verdictMoments.Text .. "\n"
		end
		self.verdictMoments.Text = self.verdictMoments.Text
			.. `  {moment.line}`
	end
	self.verdictMoments.Size = UDim2.new(0, 520, 0, 100)
	self.verdictMoments.Position = UDim2.new(0.5, 0, 0.5, 194)
	self.verdictMoments.AnchorPoint = Vector2.new(0.5, 0)
	self.verdictMoments.Visible = #ribbon.moments > 0

	self.verdictNearMiss.Text = ""
	if ribbon.nearMisses ~= nil then
		for i, miss in ribbon.nearMisses do
			if i > 1 then
				self.verdictNearMiss.Text = self.verdictNearMiss.Text .. "\n"
			end
			self.verdictNearMiss.Text = self.verdictNearMiss.Text .. "· " .. miss
		end
		self.verdictNearMiss.Visible = true
	else
		self.verdictNearMiss.Visible = false
	end
	self.verdictNearMiss.Size = UDim2.new(0, 520, 0, 56)
	self.verdictNearMiss.Position = UDim2.new(0.5, 0, 0.5, 300)
	self.verdictNearMiss.AnchorPoint = Vector2.new(0.5, 0)

	self.deathButton.Position = UDim2.new(0.5, 0, 0.5, 365)

	self.deathFrame.Visible = true
end

-- Why the trip back did not happen, printed under the button that did not work. Cleared by
-- the next `ShowDeath` rather than on a timer: there is nothing else to read on this screen,
-- and the reason is still true for as long as it is up.
function StatsUI.ShowReturnRefusal(self: StatsUIHandle, reason: string)
	self.deathNoteLabel.Text = reason
end

-- Whether there is a life to show a HUD for at all.
--
-- The whole ScreenGui rather than the stats panel, because the death overlay lives in here
-- too and the two are switched together on purpose: a HUD is a claim that somebody is alive
-- to have stats, and a death screen is a claim that somebody just stopped being. There is no
-- state in which one of them belongs on screen without the other.
--
-- Enabled rather than Visible so nothing inside has to be put back the way it was: rows the
-- server pushes while this is off -- stats, money -- are written to a HUD that is simply not
-- being drawn, and are already correct when it comes back.
function StatsUI.SetHudVisible(self: StatsUIHandle, visible: boolean)
	self.screenGui.Enabled = visible
end

-- The dealership queue state. Shown when the player is near the counter and
-- there are walk-ins waiting, or when the front customer is currently being
-- served. Hidden when there is no queue and the player is out of range.
function StatsUI.SetCarDealer(self: StatsUIHandle, state: Types.CarDealerState?)
	if state == nil then
		self.dealerRow.Visible = false
		return
	end
	if state.waiting == 0 and not state.served then
		self.dealerRow.Visible = false
		return
	end
	self.dealerRow.Visible = true
	if state.greeting ~= nil and state.greeting ~= "" then
		self.dealerLabel.Text = state.greeting
	elseif state.waiting > 0 then
		self.dealerLabel.Text = `AutoPia: {state.waiting} customer{if state.waiting > 1 then "s" else ""} waiting`
	elseif state.served then
		self.dealerLabel.Text = "AutoPia: serving customer"
	else
		self.dealerLabel.Text = "AutoPia: no customers"
	end
end

-- A milestone was achieved. Shows a brief flash-style notice.
function StatsUI.ShowMilestone(self: StatsUIHandle, label: string, bonus: number)
	self:ShowNotice(`Milestone: {label}! +{Money.Format(bonus)}`)
end

-- Freezes the shift and task rows while the chapter reel is on screen. The
-- seam is the only time the world is allowed to be still, so the HUD should
-- not lie and show activity that is not happening. When active, rows are
-- grayed out with a "Paused while you read" caption; when false, the method
-- is a no-op because the next SetShift / SetTasks push restores the real
-- state anyway.
function StatsUI.SetSeam(self: StatsUIHandle, active: boolean)
	if not active then
		return
	end
	if self.shiftRow.Visible then
		self.shiftCaption.Text = "Paused while you read"
		self.shiftFill.BackgroundColor3 = TASK_PAUSED_COLOR
	end
	for _, parts in self.taskRows do
		if parts.row.Visible then
			parts.caption.Text = "Paused while you read"
			parts.fill.BackgroundColor3 = TASK_PAUSED_COLOR
		end
	end
end

return StatsUI
