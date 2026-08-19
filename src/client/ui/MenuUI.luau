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
-- The same formatter the HUD balance and every price tag in the game uses. Money that
-- is written one way on the shop marker and another way in the menu is money the player
-- has to stop and convert, which is the one thing a balance must never make them do.
local Money = require(ReplicatedStorage:WaitForChild("Money"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type JobPostState = Types.JobPostState
type PersonRosterEntry = Types.PersonRosterEntry
type GangState = Types.GangState
type SkillsState = Types.SkillsState
type SkillState = Types.SkillState
type BillState = Types.BillState
type SavingsState = Types.SavingsState
type HouseState = Types.HouseState
type SettingsState = Types.SettingsState
type CodesState = Types.CodesState

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

		-- Every row, including the spent ones. This is the only way to reach somebody who
		-- is not standing in front of you, and it came here from the HUD roster along with
		-- the list -- a relationships pane you can read but not act from would have taken a
		-- verb out of the game in the name of tidying the screen up.
		--
		-- Spent rows stay pressable on purpose. The refusal is a sentence the server sends
		-- back, and a button that silently does nothing teaches a player less than one that
		-- tells them they have already had this person's year.
		local personId = person.id
		local tap = Instance.new("TextButton")
		tap.Size = UDim2.new(1, 0, 1, 0)
		tap.BackgroundTransparency = 1
		tap.AutoButtonColor = false
		tap.Text = ""
		tap.Parent = row
		tap.Activated:Connect(function()
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
	local order = 0
	local function nextRow(): (Frame, TextLabel, TextLabel, TextLabel)
		order += 1
		return makeRow(self.content, order)
	end

	-- Always drawn, and the only row that is. A money pane whose first line depended on
	-- whether a bill had been charged yet would be a money pane that is sometimes empty
	-- while the player is holding money.
	local _, cashTitle, cashFigure, cashCaption = nextRow()
	cashTitle.Text = "Cash"
	cashFigure.Text = Money.Format(self.money)
	cashFigure.TextColor3 = Color3.fromRGB(225, 205, 130)
	cashCaption.Text = "On you, and spendable anywhere."

	local bill = self.bill
	if bill ~= nil and (bill.debt > 0 or bill.totalThisMonth > 0) then
		local _, billTitle, billFigure, billCaption = nextRow()
		billTitle.Text = "Bills"
		if bill.debt > 0 then
			billFigure.Text = Money.Format(bill.debt)
			billFigure.TextColor3 = Color3.fromRGB(230, 120, 80)
			billCaption.Text = if bill.paid
				then `Owed from before. This month is settled.`
				else `Owed, and this month is not paid either.`
		else
			billFigure.Text = Money.Format(bill.totalThisMonth)
			billFigure.TextColor3 = if bill.paid then Color3.fromRGB(140, 226, 160) else MUTED_COLOR
			billCaption.Text = if bill.paid
				then "This month is paid and you owe nothing."
				else "Due this month. Nothing owed from before."
		end
	end

	local savings = self.savings
	if savings ~= nil and savings.balance > 0 then
		local row, saveTitle, saveFigure, saveCaption = nextRow()
		saveTitle.Text = "Savings"
		saveFigure.Text = Money.Format(savings.balance)
		saveFigure.TextColor3 = Color3.fromRGB(140, 226, 160)
		saveCaption.Text = `Earns {math.floor(savings.interestRate * 100 + 0.5)}% a year. Deposit and withdraw at the bank.`
		-- Filled against the ceiling rather than against nothing, because the ceiling is
		-- the only fact about a savings balance the player cannot see anywhere else and
		-- it is the one that decides whether walking to the bank is still worth doing.
		if savings.maxBalance > 0 then
			addBar(row, savings.balance / savings.maxBalance, Color3.fromRGB(140, 226, 160))
		end
	end

	local house = self.house
	if house ~= nil then
		for houseId in house.owned do
			local _, homeTitle, homeFigure, homeCaption = nextRow()
			homeTitle.Text = houseName(houseId)
			homeFigure.Text = "Owned"
			homeFigure.TextColor3 = Color3.fromRGB(140, 226, 160)
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

-- The redeem box, whatever the server last said about an attempt, and a receipt for every
-- code this account has already used.
--
-- The box is drawn first and always, including for an account that has redeemed nothing.
-- It is the only thing on this pane the player came here to do, and a pane that led with an
-- empty history would have buried its own verb under a sentence saying there is nothing to
-- see.
--
-- Nothing here decides anything. The box does not know what a code is, does not check one,
-- and does not know what any of them pay -- it sends a string and draws the sentence that
-- comes back. That is not tidiness: a client that could recognise a valid code is a client
-- somebody can read the list of valid codes out of.
local function drawCodes(self: MenuUIHandle): string?
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local box = Instance.new("Frame")
	box.Size = UDim2.new(1, 0, 0, 78)
	box.BackgroundColor3 = ROW_COLOR
	box.BorderSizePixel = 0
	box.LayoutOrder = nextOrder()
	box.Parent = self.content

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 6)
	boxCorner.Parent = box

	local boxPadding = Instance.new("UIPadding")
	boxPadding.PaddingLeft = UDim.new(0, 10)
	boxPadding.PaddingRight = UDim.new(0, 10)
	boxPadding.PaddingTop = UDim.new(0, 9)
	boxPadding.Parent = box

	local prompt = Instance.new("TextLabel")
	prompt.Size = UDim2.new(1, 0, 0, 15)
	prompt.BackgroundTransparency = 1
	prompt.Font = Enum.Font.GothamMedium
	prompt.TextSize = 13
	prompt.TextXAlignment = Enum.TextXAlignment.Left
	prompt.TextColor3 = TEXT_COLOR
	prompt.Text = "Have a code?"
	prompt.Parent = box

	local field = Instance.new("TextBox")
	field.Position = UDim2.new(0, 0, 0, 22)
	field.Size = UDim2.new(1, -96, 0, 32)
	field.BackgroundColor3 = Color3.fromRGB(14, 16, 21)
	field.BorderSizePixel = 0
	field.Font = Enum.Font.GothamMedium
	field.TextSize = 14
	field.TextXAlignment = Enum.TextXAlignment.Left
	field.TextColor3 = TEXT_COLOR
	field.PlaceholderText = "Type it here"
	field.PlaceholderColor3 = MUTED_COLOR
	field.ClearTextOnFocus = false
	field.Text = self.codeDraft
	field.Parent = box

	local fieldCorner = Instance.new("UICorner")
	fieldCorner.CornerRadius = UDim.new(0, 5)
	fieldCorner.Parent = field

	local fieldPadding = Instance.new("UIPadding")
	fieldPadding.PaddingLeft = UDim.new(0, 9)
	fieldPadding.PaddingRight = UDim.new(0, 9)
	fieldPadding.Parent = field

	local submit = Instance.new("TextButton")
	submit.Position = UDim2.new(1, -88, 0, 22)
	submit.Size = UDim2.new(0, 88, 0, 32)
	submit.BackgroundColor3 = Color3.fromRGB(196, 160, 255)
	submit.BorderSizePixel = 0
	submit.AutoButtonColor = true
	submit.Font = Enum.Font.GothamBold
	submit.TextSize = 13
	submit.TextColor3 = Color3.fromRGB(20, 16, 30)
	submit.Text = "Redeem"
	submit.Parent = box

	local submitCorner = Instance.new("UICorner")
	submitCorner.CornerRadius = UDim.new(0, 5)
	submitCorner.Parent = submit

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
		local _, resultTitle, resultFigure, resultCaption = makeRow(self.content, nextOrder())
		resultTitle.Text = if self.codeResultOk then "Redeemed" else "Not redeemed"
		resultTitle.TextColor3 = if self.codeResultOk then Color3.fromRGB(140, 226, 160) else Color3.fromRGB(230, 120, 80)
		resultFigure.Text = ""
		resultCaption.Text = self.codeResult
		-- The one caption in the menu allowed to wrap. Everything else here is a fact that
		-- fits on a line; this is a sentence written for the moment it is read, and
		-- truncating a refusal at the point where it says why is worse than a taller row.
		resultCaption.TextTruncate = Enum.TextTruncate.None
		resultCaption.TextWrapped = true
		resultCaption.Size = UDim2.new(1, 0, 0, 24)
	end

	local codes = self.codes
	if codes ~= nil then
		for _, redeemed in codes.redeemed do
			local _, title, figure, caption = makeRow(self.content, nextOrder())
			title.Text = redeemed.label
			figure.Text = redeemed.reward
			figure.TextColor3 = Color3.fromRGB(140, 226, 160)
			caption.Text = `{redeemed.code} — already redeemed on this account.`
		end
	end

	return nil
end

-- The switches. Every row is the whole row, clickable end to end, the same shape the gang
-- colors toggle already uses -- one gesture for "flip a thing", learned once.
--
-- Draws what the server pushed and nothing else. Clicking sends and then waits: the row
-- does not flip itself, so a preference that failed to save never spends a moment looking
-- like it did. The cost is one round trip of latency on a toggle, which is the cheapest
-- honesty in the whole menu.
local function drawSettings(self: MenuUIHandle): string?
	local settings = self.settings
	if settings == nil or #settings.settings == 0 then
		return "Your settings have not loaded yet."
	end

	for order, option in settings.settings do
		local row, title, figure, caption = makeRow(self.content, order)
		title.Text = option.label
		figure.Text = if option.on then "On" else "Off"
		figure.TextColor3 = if option.on then Color3.fromRGB(140, 226, 160) else MUTED_COLOR
		caption.Text = option.caption
		if not option.on then
			row.BackgroundTransparency = 0.35
		end

		local id = option.id
		local on = option.on
		local toggle = Instance.new("TextButton")
		toggle.Size = UDim2.new(1, 0, 1, 0)
		toggle.BackgroundTransparency = 1
		toggle.AutoButtonColor = false
		toggle.Text = ""
		toggle.Parent = row
		toggle.Activated:Connect(function()
			local callback = self.onSettingToggled
			if callback ~= nil then
				callback(id, not on)
			end
		end)
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
	elseif self.selected == "money" then
		empty = drawMoney(self)
	elseif self.selected == "relationships" then
		empty = drawRelationships(self)
	elseif self.selected == "gangs" then
		empty = drawGangs(self)
	elseif self.selected == "skills" then
		empty = drawSkills(self)
	elseif self.selected == "codes" then
		empty = drawCodes(self)
	elseif self.selected == "settings" then
		empty = drawSettings(self)
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
local function redrawPane(self: MenuUIHandle, paneId: string)
	if self.selected ~= paneId then
		return
	end
	redraw(self)
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

function MenuUI.SetCodes(self: MenuUIHandle, state: CodesState)
	self.codes = state
	redrawPane(self, "codes")
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
	redrawPane(self, "codes")
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
	-- The last thing the box said dies with the visit. It is a reply to a keystroke, and a
	-- refusal still sitting there when the player comes back an hour later is answering a
	-- question they no longer remember asking. The draft survives -- that is theirs.
	self.codeResult = ""
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
