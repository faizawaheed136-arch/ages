--!strict
-- The pizzeria's flagship shift, made real. Three timing checks instead of three marks
-- on the floor: stretch the dough, top it in order, pull it from the oven -- the same
-- three things a real pizza cook does between an order coming in and a box going out.
--
-- Follows EaselUI's law: the whole panel runs client-side and grades itself, and the
-- server never sees a stretch or a topping click, only the one clamped score this
-- module sends back over RequestJobMinigameResult once the pie is boxed. Nothing here
-- is a source of money by itself -- WorkService.completeTask turns the score into a
-- tip the same way it always has, just scaled instead of flat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local PIZZA = Config.Work.Minigames.Pizza

local PANEL_COLOR = Color3.fromRGB(24, 18, 14)
local TITLE_COLOR = Color3.fromRGB(240, 230, 214)
local CAPTION_COLOR = Color3.fromRGB(196, 170, 140)
local TRACK_COLOR = Color3.fromRGB(46, 36, 28)
local FILL_COLOR = Color3.fromRGB(224, 156, 70)
local TARGET_COLOR = Color3.fromRGB(120, 196, 120)
local BUTTON_LIVE_COLOR = Color3.fromRGB(235, 150, 60)
local BUTTON_LIVE_TEXT = Color3.fromRGB(30, 20, 10)
local TOPPING_LIVE_COLOR = Color3.fromRGB(72, 58, 46)
local TOPPING_NEXT_COLOR = Color3.fromRGB(235, 150, 60)
local TOPPING_DONE_COLOR = Color3.fromRGB(120, 196, 120)

local PANEL_WIDTH = 300

-- The fixed tray a pizzeria keeps out. The order picks a subset of these, in an
-- order, and the pool the player clicks from never shrinks to match it -- finding
-- the right one in a full tray is the whole difficulty of the step.
local TOPPING_POOL = { "Pepperoni", "Mushroom", "Olive", "Pepper", "Onion", "Basil" }

local PizzaUI = {}
PizzaUI.__index = PizzaUI

export type PizzaUIHandle = typeof(setmetatable(
	{} :: {
		screenGui: ScreenGui,
		panel: Frame,
		titleLabel: TextLabel,
		captionLabel: TextLabel,
		track: Frame,
		fill: Frame,
		targetBand: Frame,
		actionButton: TextButton,
		orderFrame: Frame,
		orderSlots: { TextLabel },
		poolFrame: Frame,
		poolButtons: { TextButton },

		-- Which task this panel is currently answering. Nil when closed -- the one
		-- fact that decides whether a stray click does anything at all.
		taskId: string?,
		-- 1 stretch, 2 toppings, 3 oven, 4 boxed and waiting for the server to catch up.
		stage: number,
		heartbeat: RBXScriptConnection?,
		stageStart: number,
		holding: boolean,

		stretchScore: number,
		toppingScore: number,
		ovenScore: number,

		order: { string },
		orderIndex: number,
		toppingMistakes: number,

		onResult: ((taskId: string, score: number) -> ())?,
	},
	PizzaUI
))

-- A bar that climbs from empty to full and wraps straight back to empty, so holding
-- past the target is a real mistake rather than a safe place to wait. Both timing
-- checks in this panel are the same shape on purpose -- the game the player is
-- actually being asked to learn is "read the target, time the release", and dressing
-- it as two different mechanics would teach that skill twice as slowly.
local function sawtooth(elapsed: number, period: number): number
	if period <= 0 then
		return 0
	end
	return (elapsed % period) / period
end

local function scoreForTiming(value: number, low: number, high: number): number
	if value >= low and value <= high then
		return 1
	end
	local distance = if value < low then low - value else value - high
	return math.clamp(1 - distance / PIZZA.TimingFalloff, 0, 1)
end

local function makeCaption(parent: Instance, order: number, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = size
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.TextColor3 = color
	label.Text = ""
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

function PizzaUI.new(): PizzaUIHandle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesPizza"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 2

	local panel = Instance.new("Frame")
	panel.Name = "PizzaPanel"
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
	titleLabel.Text = "Pizza"
	titleLabel.LayoutOrder = 0
	titleLabel.Parent = panel

	local captionLabel = makeCaption(panel, 1, 12, CAPTION_COLOR)

	-- The timing track. Shared by the stretch and the oven stages -- only the target
	-- band and the button's word change between them.
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, 14)
	track.BackgroundColor3 = TRACK_COLOR
	track.BorderSizePixel = 0
	track.LayoutOrder = 2
	track.Parent = panel

	local targetBand = Instance.new("Frame")
	targetBand.Name = "Target"
	targetBand.BackgroundColor3 = TARGET_COLOR
	targetBand.BackgroundTransparency = 0.5
	targetBand.BorderSizePixel = 0
	targetBand.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 3, 1, 0)
	fill.BackgroundColor3 = FILL_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track

	-- The order line, for the toppings stage only. Named slots rather than one string
	-- so a completed one can change colour without redrawing the whole sentence.
	local orderFrame = Instance.new("Frame")
	orderFrame.Name = "Order"
	orderFrame.Size = UDim2.new(1, 0, 0, 20)
	orderFrame.BackgroundTransparency = 1
	orderFrame.LayoutOrder = 3
	orderFrame.Parent = panel

	local orderLayout = Instance.new("UIListLayout")
	orderLayout.FillDirection = Enum.FillDirection.Horizontal
	orderLayout.SortOrder = Enum.SortOrder.LayoutOrder
	orderLayout.Padding = UDim.new(0, 6)
	orderLayout.Parent = orderFrame

	local orderSlots: { TextLabel } = {}
	for index = 1, PIZZA.ToppingCount do
		local slot = Instance.new("TextLabel")
		slot.Name = `Slot{index}`
		slot.Size = UDim2.new(0, 0, 1, 0)
		slot.AutomaticSize = Enum.AutomaticSize.X
		slot.BackgroundTransparency = 1
		slot.Font = Enum.Font.GothamBold
		slot.TextSize = 13
		slot.TextColor3 = TOPPING_LIVE_COLOR
		slot.Text = ""
		slot.LayoutOrder = index
		slot.Parent = orderFrame
		orderSlots[index] = slot
	end

	-- The tray. Fixed, always the full pool, so the difficulty is finding the right
	-- one rather than a shrinking list handing the answer away.
	local poolFrame = Instance.new("Frame")
	poolFrame.Name = "Pool"
	poolFrame.Size = UDim2.new(1, 0, 0, 0)
	poolFrame.AutomaticSize = Enum.AutomaticSize.Y
	poolFrame.BackgroundTransparency = 1
	poolFrame.LayoutOrder = 4
	poolFrame.Parent = panel

	local poolLayout = Instance.new("UIGridLayout")
	poolLayout.CellSize = UDim2.new(0.5, -3, 0, 26)
	poolLayout.CellPadding = UDim2.new(0, 6, 0, 6)
	poolLayout.SortOrder = Enum.SortOrder.LayoutOrder
	poolLayout.Parent = poolFrame

	local poolButtons: { TextButton } = {}
	for index, name in TOPPING_POOL do
		local button = Instance.new("TextButton")
		button.Name = name
		button.BackgroundColor3 = TOPPING_LIVE_COLOR
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Font = Enum.Font.Gotham
		button.TextSize = 13
		button.TextColor3 = TITLE_COLOR
		button.Text = name
		button.LayoutOrder = index
		button.Parent = poolFrame

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 6)
		buttonCorner.Parent = button

		poolButtons[index] = button
	end

	local actionButton = Instance.new("TextButton")
	actionButton.Name = "Action"
	actionButton.Size = UDim2.new(1, 0, 0, 30)
	actionButton.BackgroundColor3 = BUTTON_LIVE_COLOR
	actionButton.BorderSizePixel = 0
	actionButton.AutoButtonColor = false
	actionButton.Font = Enum.Font.GothamBold
	actionButton.TextSize = 14
	actionButton.TextColor3 = BUTTON_LIVE_TEXT
	actionButton.Text = "Hold to stretch"
	actionButton.LayoutOrder = 5
	actionButton.Parent = panel

	local actionCorner = Instance.new("UICorner")
	actionCorner.CornerRadius = UDim.new(0, 6)
	actionCorner.Parent = actionButton

	screenGui.Parent = playerGui

	local self: PizzaUIHandle = setmetatable({
		screenGui = screenGui,
		panel = panel,
		titleLabel = titleLabel,
		captionLabel = captionLabel,
		track = track,
		fill = fill,
		targetBand = targetBand,
		actionButton = actionButton,
		orderFrame = orderFrame,
		orderSlots = orderSlots,
		poolFrame = poolFrame,
		poolButtons = poolButtons,
		taskId = nil,
		stage = 1,
		heartbeat = nil,
		stageStart = 0,
		holding = false,
		stretchScore = 0,
		toppingScore = 0,
		ovenScore = 0,
		order = {},
		orderIndex = 1,
		toppingMistakes = 0,
		onResult = nil,
	}, PizzaUI)

	actionButton.MouseButton1Down:Connect(function()
		if self.taskId == nil or self.stage ~= 1 then
			return
		end
		self.holding = true
		self.stageStart = os.clock()
	end)
	actionButton.MouseButton1Up:Connect(function()
		if self.taskId == nil or self.stage ~= 1 or not self.holding then
			return
		end
		self.holding = false
		local value = sawtooth(os.clock() - self.stageStart, PIZZA.StretchFillSeconds)
		self.stretchScore = scoreForTiming(value, PIZZA.StretchTargetLow, PIZZA.StretchTargetHigh)
		self:_enterStage(2)
	end)
	actionButton.Activated:Connect(function()
		if self.taskId == nil or self.stage ~= 3 then
			return
		end
		local value = sawtooth(os.clock() - self.stageStart, PIZZA.OvenSweepSeconds)
		self.ovenScore = scoreForTiming(value, PIZZA.OvenTargetLow, PIZZA.OvenTargetHigh)
		self:_enterStage(4)
	end)

	for index, button in poolButtons do
		button.Activated:Connect(function()
			if self.taskId == nil or self.stage ~= 2 then
				return
			end
			local name = TOPPING_POOL[index]
			if self.order[self.orderIndex] == name then
				self.orderSlots[self.orderIndex].TextColor3 = TOPPING_DONE_COLOR
				self.orderIndex += 1
				if self.orderIndex > #self.order then
					self.toppingScore = math.clamp(1 - self.toppingMistakes * PIZZA.ToppingMistakePenalty, 0, 1)
					self:_enterStage(3)
				else
					self:_drawOrder()
				end
			else
				self.toppingMistakes += 1
			end
		end)
	end

	return self
end

function PizzaUI._drawOrder(self: PizzaUIHandle)
	for index, slot in self.orderSlots do
		local name = self.order[index]
		slot.Text = name or ""
		if index < self.orderIndex then
			slot.TextColor3 = TOPPING_DONE_COLOR
		elseif index == self.orderIndex then
			slot.TextColor3 = TOPPING_NEXT_COLOR
		else
			slot.TextColor3 = TOPPING_LIVE_COLOR
		end
	end
end

function PizzaUI._enterStage(self: PizzaUIHandle, stage: number)
	self.stage = stage
	self.stageStart = os.clock()
	self.holding = false

	self.track.Visible = stage == 1 or stage == 3
	self.orderFrame.Visible = stage == 2
	self.poolFrame.Visible = stage == 2

	if stage == 1 then
		self.captionLabel.Text = "Hold the button, let go when the dough band lights up green."
		self.actionButton.Text = "Hold to stretch"
		self.actionButton.Visible = true
		self.targetBand.Position = UDim2.new(PIZZA.StretchTargetLow, 0, 0, 0)
		self.targetBand.Size = UDim2.new(PIZZA.StretchTargetHigh - PIZZA.StretchTargetLow, 0, 1, 0)
	elseif stage == 2 then
		self.captionLabel.Text = "Top it in order -- the tray does not shrink to help you."
		self.actionButton.Visible = false
		local random = Random.new()
		local pool = table.clone(TOPPING_POOL)
		local order: { string } = {}
		for _ = 1, PIZZA.ToppingCount do
			local pick = random:NextInteger(1, #pool)
			table.insert(order, table.remove(pool, pick) :: string)
		end
		self.order = order
		self.orderIndex = 1
		self.toppingMistakes = 0
		self:_drawOrder()
	elseif stage == 3 then
		self.captionLabel.Text = "Pull it out the moment the band lights up green."
		self.actionButton.Text = "Pull it out"
		self.actionButton.Visible = true
		self.targetBand.Position = UDim2.new(PIZZA.OvenTargetLow, 0, 0, 0)
		self.targetBand.Size = UDim2.new(PIZZA.OvenTargetHigh - PIZZA.OvenTargetLow, 0, 1, 0)
	elseif stage == 4 then
		self.captionLabel.Text = "Boxed up and sent out."
		self.actionButton.Visible = false
		local score = (self.stretchScore + self.toppingScore + self.ovenScore) / 3
		local handler = self.onResult
		local taskId = self.taskId
		if handler ~= nil and taskId ~= nil then
			handler(taskId, score)
		end
	end
end

-- Opens the panel on the given task and starts the stretch stage. Called by the
-- client dispatcher the moment a push carries `minigame == "pizza"` and
-- `minigameOpen == true` for a task this panel is not already showing.
function PizzaUI.Open(self: PizzaUIHandle, taskId: string)
	if self.taskId == taskId then
		return
	end
	self.taskId = taskId
	self.stretchScore = 0
	self.toppingScore = 0
	self.ovenScore = 0
	self.panel.Visible = true
	self:_enterStage(1)

	if self.heartbeat == nil then
		self.heartbeat = RunService.Heartbeat:Connect(function()
			self:_tick()
		end)
	end
end

function PizzaUI._tick(self: PizzaUIHandle)
	if self.taskId == nil then
		return
	end
	if self.stage == 1 then
		local value = if self.holding then sawtooth(os.clock() - self.stageStart, PIZZA.StretchFillSeconds) else 0
		self.fill.Size = UDim2.new(value, 0, 1, 0)
	elseif self.stage == 3 then
		local value = sawtooth(os.clock() - self.stageStart, PIZZA.OvenSweepSeconds)
		self.fill.Size = UDim2.new(value, 0, 1, 0)
	end
end

-- Closed by the dispatcher once the task the panel was answering is no longer open --
-- either the server completed it off the score this panel already sent, or the shift
-- ended out from under it. Never sends a result itself; Open/the stage machine already
-- did that, or never got the chance to, and either way there is nothing left to say.
function PizzaUI.Close(self: PizzaUIHandle)
	if self.taskId == nil then
		return
	end
	self.taskId = nil
	self.holding = false
	self.panel.Visible = false
	if self.heartbeat ~= nil then
		self.heartbeat:Disconnect()
		self.heartbeat = nil
	end
end

function PizzaUI.Destroy(self: PizzaUIHandle)
	self:Close()
	self.screenGui:Destroy()
end

return PizzaUI
