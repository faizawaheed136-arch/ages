--!strict
-- A number leaving the world. When money moves, the amount floats up off the spot
-- it came from and fades out.
--
-- It exists because money has started arriving unasked. Everything that paid out
-- before this was the answer to a prompt the player was already reading, so a
-- balance moving needed no explanation -- they had just clicked the thing that
-- moved it. Pocket money lands on a birthday with nothing else on screen, and a
-- balance that changes in silence is the one thing an economy cannot do: the player
-- either misses it entirely or notices later and has no way to find out why.
--
-- In the room rather than on the HUD, which is the whole rule the game is built on.
-- A toast in the corner would be a small piece of UI announcing something that
-- happened three feet in front of the player, and the point of putting it in the
-- world is that it can be attached to whoever handed it over -- a parent's hands
-- when one crossed the room, and the player's own head when nobody could, which is
-- the visible difference between the two.
--
-- Cosmetic through and through, so every dimension below is a local rather than a
-- Config entry, on the same rule ChoiceMarkers and DeliveryPresenters follow:
-- nobody balances this game by adjusting how far a number drifts before it fades.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Money = require(ReplicatedStorage:WaitForChild("Money"))

local MoneyPop = {}

-- One folder for all of them, so a leak shows up as a fat folder in the explorer
-- rather than as debris scattered through the house.
local POPS_FOLDER = "AgesMoneyPops"

-- How far it drifts and how long it lives. Slow enough to read a four-figure sum,
-- short enough that two payments close together do not stack up into a column.
local RISE_STUDS = 2.4
local HOLD_SECONDS = 0.5
local FADE_SECONDS = 1.1
-- Derived so the drift and the fade finish together: a number that stops moving and
-- then hangs there fading reads as a UI element that got stuck.
local LIFE_SECONDS = HOLD_SECONDS + FADE_SECONDS

-- The same gold the price line on a choice marker is written in. Money has one
-- color in this game and it was set there; a second one here would be a second
-- currency as far as the player is concerned. Direction is carried by the sign in
-- front of the figure, which is what will keep a payment and a purchase legible
-- when there is something to buy.
local AMOUNT_COLOR = Color3.fromRGB(245, 218, 150)
local AMOUNT_STROKE = Color3.fromRGB(20, 18, 14)
local AMOUNT_TEXT_SIZE = 22
local AMOUNT_STROKE_THICKNESS = 2

local LABEL_WIDTH_STUDS = 8
local LABEL_HEIGHT_STUDS = 1.4
-- Past this it is an unreadable smudge on the far side of the house. Well inside
-- a choice label's range, because this one is about something that happened where
-- the player already is.
local LABEL_MAX_DISTANCE = 45

local function popsFolder(): Folder
	local existing = workspace:FindFirstChild(POPS_FOLDER)
	if existing ~= nil then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = POPS_FOLDER
	folder.Parent = workspace
	return folder
end

-- Floats an amount up from a point in the world.
--
-- The sign is read off the amount rather than passed in, so the one function is
-- already right for money going out -- and a zero shows nothing at all, because
-- "you have been paid nothing" is a sentence no player should ever be shown.
function MoneyPop.Show(at: Vector3, amount: number)
	local whole = math.floor(math.abs(amount))
	if whole == 0 then
		return
	end
	local sign = if amount < 0 then "-" else "+"

	-- An anchor part rather than a bare BillboardGui, because a gui needs something
	-- to adorn and tweening the part is what carries the drift. Invisible, and deaf
	-- to everything: it must never catch a raycast meant for the floor it is
	-- standing over, and it must never be something a toddler can trip on.
	local anchor = Instance.new("Part")
	anchor.Name = "MoneyPop"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = popsFolder()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Amount"
	billboard.Size = UDim2.new(LABEL_WIDTH_STUDS, 0, LABEL_HEIGHT_STUDS, 0)
	-- Drawn through whatever it is standing behind, for the reason a choice label is:
	-- the moment this most needs to be readable is the moment the player is behind
	-- the sofa and does not know why their balance moved.
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = LABEL_MAX_DISTANCE
	billboard.Parent = anchor

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = AMOUNT_TEXT_SIZE
	text.TextColor3 = AMOUNT_COLOR
	text.Text = `{sign}{Money.Format(whole)}`
	text.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = AMOUNT_STROKE
	stroke.Thickness = AMOUNT_STROKE_THICKNESS
	stroke.Parent = text

	local rise = TweenService:Create(
		anchor,
		TweenInfo.new(LIFE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = anchor.CFrame + Vector3.new(0, RISE_STUDS, 0) }
	)
	-- Held solid before it starts going, so the figure is legible at full contrast
	-- for long enough to actually be read. The delay is the tween's own rather than a
	-- task.delay, so nothing has to survive the part being destroyed under it.
	local fade = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, 0, false, HOLD_SECONDS)
	local fadeText = TweenService:Create(text, fade, { TextTransparency = 1 })
	local fadeStroke = TweenService:Create(stroke, fade, { Transparency = 1 })

	rise:Play()
	fadeText:Play()
	fadeStroke:Play()

	-- Debris rather than a task.delay, so a server shutting down mid-flight does not
	-- leave a thread holding a destroyed part. Nothing cancels the tweens: they die
	-- with the instances they are running on, which happens here and only here.
	Debris:AddItem(anchor, LIFE_SECONDS)
end

-- Clears any still in flight. Used at server start, where a Rojo sync mid-session
-- can otherwise leave numbers hanging in the air with nothing left to remove them.
function MoneyPop.ClearAll()
	local folder = workspace:FindFirstChild(POPS_FOLDER)
	if folder ~= nil then
		folder:ClearAllChildren()
	end
end

return MoneyPop
