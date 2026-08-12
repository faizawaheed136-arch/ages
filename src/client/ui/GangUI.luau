--!strict
-- The gang row: who you run with, how far up you are, and whether the colors are on.
--
-- Bottom right, which is the last free corner and the correct one. The other three are
-- taken by things this must never fight with: the stats block is top right, the heat bar
-- is top centre, and every activity panel in the game -- the till, the vault, the bench,
-- the easel -- opens bottom left. That last one is not a coincidence to be worked around,
-- it is the whole reason this cannot join them: robbing a bank *while in a gang* is the
-- intended case, not an edge one, so the two have to be readable at the same time.
--
-- Three facts and a button:
--
--   who          the name, in their color, because the color is the thing worn on your
--                head and this is the only place you can check which one is yours. You
--                cannot see your own hat.
--   the rung     the label, said the way a person would say it -- "a hand", "who calls
--                it" -- never a number and never "rank 2 of 4".
--   the gap      a bar toward the next rung, with the shortfall written out under it.
--                The bar is the only place in this system a raw number appears, and it
--                appears because standing arrives in bursts: forty-five points for a
--                vault, nothing for the next minute. A bar with no figure under it would
--                leave the player unable to tell a big score from a small one.
--   the colors   a button, and the one thing on this panel that decides anything.
--
-- The button says what it costs, every time, in the same breath as what it does. Wearing
-- colors multiplies every point of heat anything gives you -- see Config.Gangs
-- .ColorsSuspicion and Lives.ColorsMultiplier -- so a toggle that only said ON and OFF
-- would be a switch the player flips once and never thinks about again. The number is
-- read out of Config rather than written here so the two cannot drift.
--
-- What is deliberately *not* here: any list of the four gangs, any map, any territory.
-- Those are the same feature and they are deferred until the city is expanded. A panel
-- that named the other three now would be promising a comparison there is nothing behind.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type GangState = Types.GangState

local GANGS = Config.Gangs

local PANEL_WIDTH = 236

local PANEL_COLOR = Color3.fromRGB(18, 19, 24)
local TRACK_COLOR = Color3.fromRGB(38, 39, 46)
local CAPTION_COLOR = Color3.fromRGB(158, 162, 174)
local NOTICE_COLOR = Color3.fromRGB(236, 238, 245)
local BUTTON_OFF_COLOR = Color3.fromRGB(44, 46, 54)
local BUTTON_TEXT_COLOR = Color3.fromRGB(236, 238, 245)

-- The button's own text goes dark when the colors are on, because the button then carries
-- the gang's color as its fill and light text on a saturated band is unreadable at four
-- of the four colors in Gangs.luau. Picked once here rather than contrast-matched per
-- gang: all four are deliberately bright, so the dark option is right for all four.
local BUTTON_ON_TEXT_COLOR = Color3.fromRGB(16, 16, 20)

-- Ready-to-take is the one state on this panel worth interrupting for, and it gets the
-- warm end of the same ramp the heat bar uses rather than a color of its own.
local READY_COLOR = Color3.fromRGB(238, 200, 96)

local GangUI = {}
GangUI.__index = GangUI

export type GangUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		nameLabel: TextLabel,
		rankLabel: TextLabel,
		track: Frame,
		fill: Frame,
		captionLabel: TextLabel,
		colorsButton: TextButton,
		noticeLabel: TextLabel,
		onColors: ((want: boolean) -> ())?,
		-- What the button would ask for if pressed right now. Held rather than read back
		-- off the button's own text, because the text is prose and parsing it to find out
		-- what it means would break the first time somebody rewrote a sentence.
		wearing: boolean,
	},
	GangUI
))

-- What the bar is measuring, in words, under the bar itself.
local function captionFor(state: GangState): string
	if state.promotable then
		return "They will move you up. Go and see them."
	end
	local nextStanding = state.nextStanding
	local nextLabel = state.nextLabel
	if nextStanding == nil or nextLabel == nil then
		return "There is nothing above you."
	end
	local short = math.max(nextStanding - state.standing, 0)
	return `{math.floor(short)} more to "{nextLabel}"`
end

-- How full the bar is. Not `standing / nextStanding`: standing is cumulative and the rungs
-- are absolute, so measuring from zero would have the bar three quarters full the moment a
-- player is promoted and would never once show an empty rung. Measured between the rung
-- held and the rung ahead instead, which is the gap the player is actually closing.
local function barShare(state: GangState, heldStanding: number): number
	local nextStanding = state.nextStanding
	if nextStanding == nil then
		return 1
	end
	local span = nextStanding - heldStanding
	if span <= 0 then
		return 1
	end
	return math.clamp((state.standing - heldStanding) / span, 0, 1)
end

-- The standing the rung you hold was offered at, which the server does not send because it
-- is content both ends already have. Looked up by id rather than by position so a ladder
-- that gains a rung in the middle does not silently shift every bar in the game.
local function standingOfRank(rankId: string): number
	for _, rank in GANGS.Ranks do
		if rank.id == rankId then
			return rank.standing
		end
	end
	return 0
end

function GangUI.new(): GangUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesGang"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	-- The same tier as the heat bar and above the activity panels, because it is the same
	-- kind of thing: standing state that is true while you are doing something else. Below
	-- a choice panel, which is a decision and outranks weather.
	screenGui.DisplayOrder = 3
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "GangPanel"
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -16, 1, -16)
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

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, 0, 0, 18)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = ""
	nameLabel.LayoutOrder = 0
	nameLabel.Parent = panel

	local rankLabel = Instance.new("TextLabel")
	rankLabel.Name = "Rank"
	rankLabel.Size = UDim2.new(1, 0, 0, 15)
	rankLabel.BackgroundTransparency = 1
	rankLabel.Font = Enum.Font.Gotham
	rankLabel.TextSize = 13
	rankLabel.TextXAlignment = Enum.TextXAlignment.Left
	rankLabel.TextColor3 = CAPTION_COLOR
	rankLabel.Text = ""
	rankLabel.LayoutOrder = 1
	rankLabel.Parent = panel

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 6)
	track.BackgroundColor3 = TRACK_COLOR
	track.BorderSizePixel = 0
	track.LayoutOrder = 2
	track.Parent = panel

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = READY_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track

	local captionLabel = Instance.new("TextLabel")
	captionLabel.Name = "Caption"
	captionLabel.Size = UDim2.new(1, 0, 0, 0)
	captionLabel.AutomaticSize = Enum.AutomaticSize.Y
	captionLabel.BackgroundTransparency = 1
	captionLabel.Font = Enum.Font.Gotham
	captionLabel.TextSize = 12
	captionLabel.TextWrapped = true
	captionLabel.TextXAlignment = Enum.TextXAlignment.Left
	captionLabel.TextColor3 = CAPTION_COLOR
	captionLabel.Text = ""
	captionLabel.LayoutOrder = 3
	captionLabel.Parent = panel

	local colorsButton = Instance.new("TextButton")
	colorsButton.Name = "Colors"
	colorsButton.Size = UDim2.new(1, 0, 0, 30)
	colorsButton.BackgroundColor3 = BUTTON_OFF_COLOR
	colorsButton.BorderSizePixel = 0
	colorsButton.AutoButtonColor = true
	colorsButton.Font = Enum.Font.GothamMedium
	colorsButton.TextSize = 12
	colorsButton.TextColor3 = BUTTON_TEXT_COLOR
	colorsButton.Text = ""
	colorsButton.LayoutOrder = 4
	colorsButton.Parent = panel

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = colorsButton

	local noticeLabel = Instance.new("TextLabel")
	noticeLabel.Name = "Notice"
	noticeLabel.Size = UDim2.new(1, 0, 0, 0)
	noticeLabel.AutomaticSize = Enum.AutomaticSize.Y
	noticeLabel.BackgroundTransparency = 1
	noticeLabel.Font = Enum.Font.GothamMedium
	noticeLabel.TextSize = 12
	noticeLabel.TextWrapped = true
	noticeLabel.TextXAlignment = Enum.TextXAlignment.Left
	noticeLabel.TextColor3 = NOTICE_COLOR
	noticeLabel.Text = ""
	noticeLabel.Visible = false
	noticeLabel.LayoutOrder = 5
	noticeLabel.Parent = panel

	local self = setmetatable({
		screenGui = screenGui,
		panel = panel,
		nameLabel = nameLabel,
		rankLabel = rankLabel,
		track = track,
		fill = fill,
		captionLabel = captionLabel,
		colorsButton = colorsButton,
		noticeLabel = noticeLabel,
		onColors = nil,
		wearing = false,
	}, GangUI) :: GangUIHandle

	colorsButton.Activated:Connect(function()
		local callback = self.onColors
		if callback == nil then
			return
		end
		-- Asks for the opposite of what the server last said, never of what this panel last
		-- drew for itself. Nothing here flips its own state on the press: the button is a
		-- request, the band on the head is the answer, and a panel that went ahead and
		-- redrew itself would show colors on for the one frame before a refusal came back.
		callback(not self.wearing)
	end)

	return self
end

-- Whether the notice is worth a line. A push carries one at most, and it is cleared by the
-- server the moment it has been sent, so this goes up on the push that carries it and comes
-- down on the next one -- which is the same lifetime the heat bar's notice has.
function GangUI.Set(self: GangUIHandle, state: GangState?)
	if state == nil then
		self.panel.Visible = false
		self.wearing = false
		return
	end

	self.panel.Visible = true
	self.wearing = state.wearing

	self.nameLabel.Text = string.upper(state.name)
	self.nameLabel.TextColor3 = state.color

	-- No article added here. The labels in Config.Gangs.Ranks carry their own, because
	-- three of the four take one and the fourth -- "who calls it" -- does not.
	self.rankLabel.Text = `You are {state.rankLabel}.`

	self.fill.Size = UDim2.new(barShare(state, standingOfRank(state.rankId)), 0, 1, 0)
	-- The bar is the gang's color until there is something to collect, and then it is not.
	-- Handing the ready state its own color is the one moment this panel is allowed to
	-- interrupt: it is the only thing here the player has to walk somewhere to act on.
	self.fill.BackgroundColor3 = if state.promotable then READY_COLOR else state.color

	self.captionLabel.Text = captionFor(state)
	self.captionLabel.TextColor3 = if state.promotable then READY_COLOR else CAPTION_COLOR

	if state.wearing then
		self.colorsButton.Text = `COLORS ON  ·  heat ×{string.format("%.2f", GANGS.ColorsSuspicion)}`
		self.colorsButton.BackgroundColor3 = state.color
		self.colorsButton.TextColor3 = BUTTON_ON_TEXT_COLOR
	else
		self.colorsButton.Text = "COLORS OFF  ·  nobody knows you"
		self.colorsButton.BackgroundColor3 = BUTTON_OFF_COLOR
		self.colorsButton.TextColor3 = BUTTON_TEXT_COLOR
	end

	local notice = state.notice
	self.noticeLabel.Visible = notice ~= nil
	self.noticeLabel.Text = notice or ""
end

function GangUI.OnColorsToggled(self: GangUIHandle, callback: (want: boolean) -> ())
	self.onColors = callback
end

return GangUI
