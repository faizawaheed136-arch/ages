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
-- **What is not here.** No decisions. Every pane draws state the server pushed and the
-- one control on any of them -- the gang colors toggle -- reports out through a
-- callback rather than flipping its own switch. This module holds four pushes and a
-- selection, and nothing else.
--
-- The panes deliberately share one row shape: a title, a right-aligned figure, and a
-- caption underneath. Four lists that looked like four different games would make the
-- panel read as four features bolted together, which is what it must not be.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type JobPostState = Types.JobPostState
type PersonRosterEntry = Types.PersonRosterEntry
type GangState = Types.GangState
type SkillsState = Types.SkillsState
type SkillState = Types.SkillState

local MENU = Config.UI.Menu

local BACKDROP_COLOR = Color3.fromRGB(6, 7, 10)
local PANEL_COLOR = Color3.fromRGB(18, 20, 26)
local HEADER_COLOR = Color3.fromRGB(24, 27, 34)
local ROW_COLOR = Color3.fromRGB(26, 29, 37)
local TEXT_COLOR = Color3.fromRGB(232, 236, 245)
local MUTED_COLOR = Color3.fromRGB(148, 155, 170)
local RAIL_IDLE_COLOR = Color3.fromRGB(22, 24, 30)

-- The height of one list row, and of the two lines inside it. Named because four panes
-- build rows and a pane that measured its own would be the one that drifts.
local ROW_HEIGHT = 46
local ROW_GAP = 5

local MenuUI = {}
MenuUI.__index = MenuUI

export type MenuUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		rail: Frame,
		panel: Frame,
		backdrop: TextButton,
		titleLabel: TextLabel,
		cardName: TextLabel,
		cardLine: TextLabel,
		content: ScrollingFrame,
		emptyLabel: TextLabel,
		railButtons: { [string]: TextButton },
		open: boolean,
		-- Which pane is showing. Held across closes so reopening returns the player to
		-- where they were rather than to the top of the rail, which is what a menu you
		-- dip into twenty times a life has to do.
		selected: string,
		jobs: { JobPostState },
		roster: { PersonRosterEntry },
		gang: GangState?,
		skills: SkillsState?,
		ageYears: number,
		stage: string,
		money: number,
		onColorsToggled: ((boolean) -> ())?,
	},
	MenuUI
))

-- One list row: a title on the left, a figure on the right, a caption underneath.
--
-- The figure column is fixed-width and the title is truncated into what is left, which
-- is deliberately the opposite of letting the title push the figure off the edge: a row
-- whose number has scrolled out of view has lost the only part of it that was worth
-- scanning.
local function makeRow(parent: Instance, order: number): (Frame, TextLabel, TextLabel, TextLabel)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = ROW_COLOR
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = row

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 6)
	padding.Parent = row

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -110, 0, 16)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.TextColor3 = TEXT_COLOR
	title.Text = ""
	title.Parent = row

	local figure = Instance.new("TextLabel")
	figure.Size = UDim2.new(0, 100, 0, 16)
	figure.Position = UDim2.new(1, -100, 0, 0)
	figure.BackgroundTransparency = 1
	figure.Font = Enum.Font.GothamBold
	figure.TextSize = 13
	figure.TextXAlignment = Enum.TextXAlignment.Right
	figure.TextColor3 = MUTED_COLOR
	figure.Text = ""
	figure.Parent = row

	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1, 0, 0, 14)
	caption.Position = UDim2.new(0, 0, 0, 18)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.Gotham
	caption.TextSize = 11
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextTruncate = Enum.TextTruncate.AtEnd
	caption.TextColor3 = MUTED_COLOR
	caption.Text = ""
	caption.Parent = row

	return row, title, figure, caption
end

-- A progress bar along the bottom edge of a row. Only two panes want one, which is why
-- it is a separate call rather than part of every row: a track drawn under a job advert
-- would be a bar measuring nothing.
local function addBar(row: Frame, fill: number, color: Color3)
	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, 0, 0, 4)
	track.Position = UDim2.new(0, 0, 1, -10)
	track.BackgroundColor3 = Color3.fromRGB(44, 48, 58)
	track.BorderSizePixel = 0
	track.Parent = row

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(math.clamp(fill, 0, 1), 0, 1, 0)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.Parent = track

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar
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
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	-- ---------------------------------------------------------------
	-- The rail. Always on screen, in its own frame so that hiding the panel below
	-- never touches it.
	-- ---------------------------------------------------------------

	local tabs = MENU.Tabs
	local railHeight = #tabs * MENU.RailTilePixels + (#tabs - 1) * MENU.RailGapPixels

	local rail = Instance.new("Frame")
	rail.Name = "Rail"
	rail.AnchorPoint = Vector2.new(0, 0.5)
	rail.Position = UDim2.new(0, MENU.RailInsetPixels, 0.5, 0)
	rail.Size = UDim2.new(0, MENU.RailTilePixels, 0, railHeight)
	rail.BackgroundTransparency = 1
	rail.ZIndex = 20
	rail.Parent = screenGui

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
	backdrop.BackgroundColor3 = BACKDROP_COLOR
	backdrop.BackgroundTransparency = 0.4
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 1
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 0.5)
	-- Anchored to the rail's right edge rather than centred, so that the tile the player
	-- clicked stays exactly where their cursor already is. A panel that opens centred
	-- moves the rail out from under the pointer and makes switching panes a hunt.
	panel.Position = UDim2.new(0, MENU.RailInsetPixels + MENU.RailTilePixels + 10, 0.5, 0)
	panel.Size = UDim2.new(MENU.PanelWidthFraction, 0, MENU.PanelHeightFraction, 0)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 2
	panel.Parent = screenGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel

	-- ---------------------------------------------------------------
	-- The player card. Top strip of the panel, the same on every pane, because the
	-- questions the panes answer are all about this person and a panel that forgot
	-- whose life it was describing would be four lists in a box.
	-- ---------------------------------------------------------------

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 62)
	header.BackgroundColor3 = HEADER_COLOR
	header.BorderSizePixel = 0
	header.ZIndex = 3
	header.Parent = panel

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 10)
	headerCorner.Parent = header

	local headerPadding = Instance.new("UIPadding")
	headerPadding.PaddingLeft = UDim.new(0, 16)
	headerPadding.PaddingRight = UDim.new(0, 16)
	headerPadding.PaddingTop = UDim.new(0, 11)
	headerPadding.Parent = header

	local cardName = Instance.new("TextLabel")
	cardName.Size = UDim2.new(1, -180, 0, 20)
	cardName.BackgroundTransparency = 1
	cardName.Font = Enum.Font.GothamBold
	cardName.TextSize = 17
	cardName.TextXAlignment = Enum.TextXAlignment.Left
	cardName.TextTruncate = Enum.TextTruncate.AtEnd
	cardName.TextColor3 = TEXT_COLOR
	cardName.Text = player.DisplayName
	cardName.ZIndex = 4
	cardName.Parent = header

	local cardLine = Instance.new("TextLabel")
	cardLine.Size = UDim2.new(1, -180, 0, 15)
	cardLine.Position = UDim2.new(0, 0, 0, 21)
	cardLine.BackgroundTransparency = 1
	cardLine.Font = Enum.Font.Gotham
	cardLine.TextSize = 12
	cardLine.TextXAlignment = Enum.TextXAlignment.Left
	cardLine.TextColor3 = MUTED_COLOR
	cardLine.Text = ""
	cardLine.ZIndex = 4
	cardLine.Parent = header

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(0, 170, 0, 20)
	titleLabel.Position = UDim2.new(1, -170, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 15
	titleLabel.TextXAlignment = Enum.TextXAlignment.Right
	titleLabel.TextColor3 = TEXT_COLOR
	titleLabel.Text = ""
	titleLabel.ZIndex = 4
	titleLabel.Parent = header

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.new(0, 170, 0, 15)
	closeButton.Position = UDim2.new(1, -170, 0, 21)
	closeButton.BackgroundTransparency = 1
	closeButton.AutoButtonColor = false
	closeButton.Font = Enum.Font.Gotham
	closeButton.TextSize = 11
	closeButton.TextXAlignment = Enum.TextXAlignment.Right
	closeButton.TextColor3 = MUTED_COLOR
	closeButton.Text = "Close  (Tab)"
	closeButton.ZIndex = 4
	closeButton.Parent = header

	-- ---------------------------------------------------------------
	-- The list.
	-- ---------------------------------------------------------------

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Position = UDim2.new(0, 14, 0, 72)
	content.Size = UDim2.new(1, -28, 1, -86)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 4
	content.ScrollBarImageColor3 = Color3.fromRGB(70, 76, 90)
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
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "Empty"
	emptyLabel.Position = UDim2.new(0, 14, 0, 96)
	emptyLabel.Size = UDim2.new(1, -28, 0, 40)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Font = Enum.Font.Gotham
	emptyLabel.TextSize = 13
	emptyLabel.TextWrapped = true
	emptyLabel.TextXAlignment = Enum.TextXAlignment.Left
	emptyLabel.TextYAlignment = Enum.TextYAlignment.Top
	emptyLabel.TextColor3 = MUTED_COLOR
	emptyLabel.Text = ""
	emptyLabel.Visible = false
	emptyLabel.ZIndex = 3
	emptyLabel.Parent = panel

	local self: MenuUIHandle = setmetatable({
		screenGui = screenGui,
		rail = rail,
		panel = panel,
		backdrop = backdrop,
		titleLabel = titleLabel,
		cardName = cardName,
		cardLine = cardLine,
		content = content,
		emptyLabel = emptyLabel,
		railButtons = {},
		open = false,
		selected = tabs[1].id,
		jobs = {},
		roster = {},
		gang = nil,
		skills = nil,
		ageYears = 0,
		stage = "",
		money = 0,
		onColorsToggled = nil,
	}, MenuUI)

	for order, tab in tabs do
		local button = Instance.new("TextButton")
		button.Name = tab.id
		button.Size = UDim2.new(0, MENU.RailTilePixels, 0, MENU.RailTilePixels)
		button.LayoutOrder = order
		button.BackgroundColor3 = RAIL_IDLE_COLOR
		button.BackgroundTransparency = 0.15
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Font = Enum.Font.GothamBold
		button.TextSize = 18
		button.TextColor3 = tab.color
		button.Text = tab.glyph
		button.ZIndex = 21
		button.Parent = rail

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 9)
		corner.Parent = button

		local stroke = Instance.new("UIStroke")
		stroke.Color = tab.color
		stroke.Thickness = 1
		stroke.Transparency = 0.75
		stroke.Parent = button

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
	end

	backdrop.Activated:Connect(function()
		MenuUI.Close(self)
	end)

	closeButton.Activated:Connect(function()
		MenuUI.Close(self)
	end)

	return self
end

-- -------------------------------------------------------------------
-- Panes. One function each, all of them building into the same cleared list, all of
-- them returning the empty-state sentence for when they built nothing.
-- -------------------------------------------------------------------

local function drawJobs(self: MenuUIHandle): string?
	if #self.jobs == 0 then
		return "Nothing is hiring where you can see it. Job boards stand outside the places that are taking people on -- the map will show you where they are."
	end

	for order, post in self.jobs do
		local row, title, figure, caption = makeRow(self.content, order)
		title.Text = post.title
		-- The pad's own words for whether you can take it, which is the one thing a
		-- player reading a list of jobs actually wants: not what it pays, but whether
		-- this one is open to them right now.
		figure.Text = if post.padLocked then "Not yet" else "Open"
		figure.TextColor3 = if post.padLocked then MUTED_COLOR else Color3.fromRGB(140, 226, 160)
		caption.Text = if #post.terms > 0 then table.concat(post.terms, "  ·  ") else post.headline
		if post.padLocked then
			row.BackgroundTransparency = 0.35
		end
	end
	return nil
end

local function drawRelationships(self: MenuUIHandle): string?
	if #self.roster == 0 then
		return "You have not met anybody yet."
	end

	for order, person in self.roster do
		local row, title, figure, caption = makeRow(self.content, order)
		title.Text = person.name
		figure.Text = if person.available then "Free to talk" else "Seen this year"
		figure.TextColor3 = if person.available then Color3.fromRGB(140, 226, 160) else MUTED_COLOR
		-- The band is the word the game has always used for this bond -- "known",
		-- "friend", "closest friend". The tie, when there is one, is the structural
		-- thing on top of it and is said second because it is rarer and it is earned.
		caption.Text = if person.tie ~= nil then `{person.band}  ·  {person.tie}` else person.band
		if not person.available then
			row.BackgroundTransparency = 0.35
		end
	end
	return nil
end

local function drawGangs(self: MenuUIHandle): string?
	local gang = self.gang
	if gang == nil then
		return "You do not run with anybody. The four sides of the city each have somebody who decides who is in -- find one and talk to them."
	end

	local row, title, figure, caption = makeRow(self.content, 1)
	title.Text = gang.name
	title.TextColor3 = gang.color
	figure.Text = gang.rankLabel
	figure.TextColor3 = gang.color
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
		addBar(row, fill, gang.color)
	else
		caption.Text = `{math.floor(gang.standing)} standing — nothing left to climb`
	end

	-- The promotion, which is a fact rather than a button. Nothing here confers a rung:
	-- GangService hands one over face-to-face, off a panel, in a moment the player
	-- walked across the city to be in, and a menu that could do it from anywhere would
	-- undo the only rule that makes rank mean anything.
	if gang.promotable then
		local _, promoteTitle, promoteFigure, promoteCaption = makeRow(self.content, 2)
		promoteTitle.Text = "You have earned the next rung"
		promoteFigure.Text = gang.nextLabel or ""
		promoteFigure.TextColor3 = gang.color
		promoteCaption.Text = "Go and see whoever runs your side. Rank is handed over, never awarded."
	end

	local colorsRow, colorsTitle, colorsFigure, colorsCaption = makeRow(self.content, 3)
	colorsTitle.Text = "Colors"
	colorsFigure.Text = if gang.wearing then "On" else "Off"
	colorsFigure.TextColor3 = if gang.wearing then gang.color else MUTED_COLOR
	colorsCaption.Text = if gang.wearing
		then "Everyone can see whose side you are on. Every point of heat counts double."
		else "Nobody can tell. You earn nothing on anybody else's side while it is off."

	local toggle = Instance.new("TextButton")
	toggle.Size = UDim2.new(1, 0, 1, 0)
	toggle.BackgroundTransparency = 1
	toggle.AutoButtonColor = false
	toggle.Text = ""
	toggle.Parent = colorsRow
	toggle.Activated:Connect(function()
		local callback = self.onColorsToggled
		if callback ~= nil then
			callback(not gang.wearing)
		end
	end)

	return nil
end

local function drawSkills(self: MenuUIHandle): string?
	local skills = self.skills
	if skills == nil or #skills.skills == 0 then
		return "Nothing yet."
	end

	for order, skill in skills.skills do
		local row, title, figure, caption = makeRow(self.content, order)
		title.Text = skill.label
		title.TextColor3 = skill.color
		figure.Text = `{skill.levelName}  ·  lv{skill.level}`

		if skill.nextLevelXp ~= nil then
			local span = skill.nextLevelXp - skill.bandFloorXp
			-- Guarded rather than trusted. The span can only be zero if two ladder rungs
			-- were given the same threshold, which is a content mistake -- but the shape
			-- of that mistake here is a division by zero inside a draw loop, which takes
			-- the whole panel down rather than drawing one bad bar.
			local fill = if span > 0 then (skill.xp - skill.bandFloorXp) / span else 1
			caption.Text = `{skill.earnedBy}  ·  {skill.xp} / {skill.nextLevelXp}`
			addBar(row, fill, skill.color)
		else
			caption.Text = `{skill.earnedBy}  ·  {skill.xp}, as far as this goes`
			addBar(row, 1, skill.color)
		end
	end
	return nil
end

-- Rebuild whichever pane is showing. Called on every push as well as on every switch,
-- because a panel left open while the world changes underneath it is worse than one
-- that costs a few instances to keep honest -- and the lists here are tens of rows,
-- not thousands.
local function redraw(self: MenuUIHandle)
	if not self.open then
		return
	end

	for _, child in self.content:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local label = ""
	for _, tab in MENU.Tabs do
		if tab.id == self.selected then
			label = tab.label
		end
	end
	self.titleLabel.Text = label

	local empty: string?
	if self.selected == "jobs" then
		empty = drawJobs(self)
	elseif self.selected == "relationships" then
		empty = drawRelationships(self)
	elseif self.selected == "gangs" then
		empty = drawGangs(self)
	elseif self.selected == "skills" then
		empty = drawSkills(self)
	else
		-- A tab in Config with no pane behind it. Said out loud rather than drawn as a
		-- blank, because a blank panel reads as a bug in the data and this is a bug in
		-- the code -- and the two get debugged in completely different places.
		error(`MenuUI: no pane for tab "{self.selected}". Add one to redraw() or remove the tab from Config.UI.Menu.Tabs.`)
	end

	self.emptyLabel.Text = empty or ""
	self.emptyLabel.Visible = empty ~= nil
	self.content.Visible = empty == nil

	for id, button in self.railButtons do
		local on = id == self.selected and self.open
		button.BackgroundTransparency = if on then 0 else 0.15
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke ~= nil then
			stroke.Transparency = if on then 0 else 0.75
		end
	end
end

local function redrawCard(self: MenuUIHandle)
	local parts: { string } = {}
	if self.stage ~= "" then
		table.insert(parts, self.stage)
	end
	table.insert(parts, `Age {self.ageYears}`)
	table.insert(parts, `${self.money}`)
	self.cardLine.Text = table.concat(parts, "  ·  ")
end

-- -------------------------------------------------------------------
-- The pushes. Each stores and redraws, and redraw is a no-op while closed, so a
-- player who never opens the menu pays for four table assignments a life.
-- -------------------------------------------------------------------

function MenuUI.SetJobs(self: MenuUIHandle, posts: { JobPostState })
	self.jobs = posts
	redraw(self)
end

function MenuUI.SetRoster(self: MenuUIHandle, entries: { PersonRosterEntry })
	self.roster = entries
	redraw(self)
end

function MenuUI.SetGang(self: MenuUIHandle, state: GangState?)
	self.gang = state
	redraw(self)
end

function MenuUI.SetSkills(self: MenuUIHandle, state: SkillsState?)
	self.skills = state
	redraw(self)
end

function MenuUI.SetIdentity(self: MenuUIHandle, ageYears: number, stage: string, money: number)
	self.ageYears = ageYears
	self.stage = stage
	self.money = money
	redrawCard(self)
end

function MenuUI.OnColorsToggled(self: MenuUIHandle, callback: (boolean) -> ())
	self.onColorsToggled = callback
end

-- The rail comes down with the HUD and goes back up with it, for the reason the HUD
-- itself does: a menu offering four lists about a life is a claim that a life is being
-- lived, and there is not one yet on the frame before the first push lands.
function MenuUI.SetVisible(self: MenuUIHandle, visible: boolean)
	self.rail.Visible = visible
	if not visible then
		MenuUI.Close(self)
	end
end

function MenuUI.Open(self: MenuUIHandle)
	self.open = true
	self.panel.Visible = true
	self.backdrop.Visible = true
	redrawCard(self)
	redraw(self)
end

function MenuUI.Close(self: MenuUIHandle)
	if not self.open then
		return
	end
	self.open = false
	self.panel.Visible = false
	self.backdrop.Visible = false
	for _, button in self.railButtons do
		button.BackgroundTransparency = 0.15
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke ~= nil then
			stroke.Transparency = 0.75
		end
	end
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
