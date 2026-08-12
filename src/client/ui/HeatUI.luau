--!strict
-- The heat bar: how much of the town is currently looking for you.
--
-- Top centre, and the only panel in the game that sits there. Every other surface is in
-- a corner because it is read at a glance between other things; this one is read while
-- sprinting down a street with the camera swinging, and the middle of the top edge is
-- the one place on screen that is never behind the player's own character and never
-- competes with the stats block, an activity panel or a choice.
--
-- Three facts and no more:
--
--   the tier      one word -- "reported", "manhunt" -- because a number invites the
--                 player to optimise against the thresholds instead of against the
--                 street. The server does not send the raw bounty at all; see
--                 Types.BountyState, which leaves it out on purpose.
--   the officers  a count, because "four" is a thing you can act on and a bar is not.
--   seen          the load-bearing one. Whether anybody has eyes on you *this second*
--                 is the entire feedback loop of the chase: without it a player cannot
--                 tell a hide that worked from a chase that happened to end, and the
--                 system teaches them nothing.
--
-- `seen` gets more than a word. The screen takes a red border while it holds, because a
-- player being chased is not looking at the top of the screen -- they are looking at the
-- corner they are about to turn -- and the one piece of feedback that has to survive that
-- is the one that says whether turning it worked.
--
-- The bar freezes rather than falling while you are seen, and for CoolStartSeconds after.
-- That freeze is deliberately visible: `cooling` is a separate field from `not seen` for
-- exactly this reason, and the caption says which of the two is true. A bar that sat still
-- with no explanation would read as a bug in the one moment the player most needs to
-- believe the rules.
--
-- What is *not* on this panel is where the police think you are. That is the best piece
-- of information in the system and it is drawn in the world instead, by
-- client/world/SearchRing -- the same split as LabUI and LabDots, and for the same
-- reason: a belief about a place belongs on the place. Both are driven from the one
-- BountyUpdated handler in init.client, so they cannot disagree.
--
-- Nothing here decides anything, and there is no button on it. Heat is spent by walking.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type BountyState = Types.BountyState

local CRIME = Config.Crime

local PANEL_WIDTH = 260

local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TRACK_COLOR = Color3.fromRGB(38, 39, 46)
local CAPTION_COLOR = Color3.fromRGB(158, 162, 174)
local NOTICE_COLOR = Color3.fromRGB(236, 238, 245)

-- The two ends of the heat ramp. Tier colours are interpolated between these by the
-- tier's position in Config.Crime.Tiers rather than authored one per rung, so a sixth
-- tier added to Config gets a colour instead of getting black. The ramp is the same
-- amber-to-red the search ring uses, because they are the same fact drawn twice.
local CALM_COLOR = Color3.fromRGB(238, 200, 96)
local CRITICAL_COLOR = Color3.fromRGB(214, 62, 58)

-- The seen border. Thick enough to be caught in peripheral vision, transparent enough
-- not to be a thing the player is looking through.
local SEEN_BORDER_COLOR = Color3.fromRGB(226, 78, 74)
local SEEN_BORDER_THICKNESS = 6
local SEEN_BORDER_TRANSPARENCY = 0.25

local HeatUI = {}
HeatUI.__index = HeatUI

export type HeatUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		tierLabel: TextLabel,
		track: Frame,
		fill: Frame,
		statusLabel: TextLabel,
		noticeLabel: TextLabel,
		borderFrame: Frame,
	},
	HeatUI
))

-- Which rung of the ladder a tier name is, for the colour ramp. Built once from Config
-- rather than looked up by scanning on every push -- this runs five times a second in a
-- pursuit and the answer never changes.
local TIER_RANK: { [string]: number } = {}
for index, tier in CRIME.Tiers do
	TIER_RANK[tier.name] = index
end

local function tierColor(name: string): Color3
	local rank = TIER_RANK[name]
	local top = #CRIME.Tiers
	if rank == nil or top <= 1 then
		return CRITICAL_COLOR
	end
	-- Rung one is "clean", which never reaches the screen -- the server sends nil rather
	-- than a zeroed snapshot -- so the ramp is measured from rung two, and the first tier
	-- the player ever sees is already the calm end of it rather than a third of the way up.
	return CALM_COLOR:Lerp(CRITICAL_COLOR, math.clamp((rank - 2) / math.max(top - 2, 1), 0, 1))
end

-- What the bar is doing, in the player's words. The order matters: seen beats everything,
-- because while it is true nothing else on the panel is the thing to act on.
local function statusSentence(state: BountyState): string
	local officers = state.officers
	local word = if officers == 1 then "officer" else "officers"
	if state.seen then
		return `Seen. {officers} {word} out.`
	end
	if state.cooling then
		return `Cooling. {officers} {word} still looking.`
	end
	if officers > 0 then
		return `Lost them. {officers} {word} searching where you were.`
	end
	return "Nobody is looking yet."
end

function HeatUI.new(): HeatUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesHeat"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	-- Above the activity panels and below a choice. A choice panel opening over the heat
	-- bar is correct: the panel is a decision and the bar is weather.
	screenGui.DisplayOrder = 3
	screenGui.Parent = playerGui

	-- The border is a full-screen frame with nothing in it but a stroke, which is the
	-- cheapest vignette there is -- one instance, no image asset to upload, and no
	-- per-frame work. It is a sibling of the panel rather than a child so the panel can
	-- keep its own rounded corner.
	local borderFrame = Instance.new("Frame")
	borderFrame.Name = "SeenBorder"
	borderFrame.Size = UDim2.new(1, 0, 1, 0)
	borderFrame.BackgroundTransparency = 1
	borderFrame.Visible = false
	borderFrame.Parent = screenGui

	local border = Instance.new("UIStroke")
	border.Color = SEEN_BORDER_COLOR
	border.Thickness = SEEN_BORDER_THICKNESS
	border.Transparency = SEEN_BORDER_TRANSPARENCY
	border.Parent = borderFrame

	local panel = Instance.new("Frame")
	panel.Name = "HeatPanel"
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 14)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.Parent = panel

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "Tier"
	tierLabel.Size = UDim2.new(1, 0, 0, 18)
	tierLabel.BackgroundTransparency = 1
	tierLabel.Font = Enum.Font.GothamBold
	tierLabel.TextSize = 15
	tierLabel.TextXAlignment = Enum.TextXAlignment.Center
	tierLabel.Text = ""
	tierLabel.LayoutOrder = 0
	tierLabel.Parent = panel

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 6)
	track.BackgroundColor3 = TRACK_COLOR
	track.BorderSizePixel = 0
	track.LayoutOrder = 1
	track.Parent = panel

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = CALM_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, 0, 0, 0)
	statusLabel.AutomaticSize = Enum.AutomaticSize.Y
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 12
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center
	statusLabel.TextColor3 = CAPTION_COLOR
	statusLabel.Text = ""
	statusLabel.LayoutOrder = 2
	statusLabel.Parent = panel

	local noticeLabel = Instance.new("TextLabel")
	noticeLabel.Name = "Notice"
	noticeLabel.Size = UDim2.new(1, 0, 0, 0)
	noticeLabel.AutomaticSize = Enum.AutomaticSize.Y
	noticeLabel.BackgroundTransparency = 1
	noticeLabel.Font = Enum.Font.GothamMedium
	noticeLabel.TextSize = 13
	noticeLabel.TextWrapped = true
	noticeLabel.TextXAlignment = Enum.TextXAlignment.Center
	noticeLabel.TextColor3 = NOTICE_COLOR
	noticeLabel.Text = ""
	noticeLabel.Visible = false
	noticeLabel.LayoutOrder = 3
	noticeLabel.Parent = panel

	return setmetatable({
		screenGui = screenGui,
		panel = panel,
		tierLabel = tierLabel,
		track = track,
		fill = fill,
		statusLabel = statusLabel,
		noticeLabel = noticeLabel,
		borderFrame = borderFrame,
	}, HeatUI) :: HeatUIHandle
end

-- The whole panel and the whole ring, from one snapshot. Nil is the usual state -- most
-- of most lives -- and takes both off screen.
function HeatUI.Set(self: HeatUIHandle, state: BountyState?)
	if state == nil then
		self.panel.Visible = false
		self.borderFrame.Visible = false
		return
	end

	self.panel.Visible = true

	local color = tierColor(state.tier)
	-- Uppercase, which is the one place in this game's UI that shouts. It is a siren.
	local tierText = string.upper(state.tier)
	if state.hasRecord then
		-- One word, and it is the whole of the record's presence on screen. It changes
		-- nothing here -- the record's teeth are in BountyService.SuspicionMultiplier and
		-- in the hiring bar -- but a difficulty that changed with nothing on screen to
		-- explain it would read as the game being unfair rather than as consequence.
		tierText ..= "  ·  ON RECORD"
	end
	self.tierLabel.Text = tierText
	self.tierLabel.TextColor3 = color

	self.fill.Size = UDim2.new(math.clamp(state.share, 0, 1), 0, 1, 0)
	self.fill.BackgroundColor3 = color

	self.statusLabel.Text = statusSentence(state)

	local notice = state.notice
	self.noticeLabel.Visible = notice ~= nil
	self.noticeLabel.Text = notice or ""

	self.borderFrame.Visible = state.seen
end

return HeatUI
