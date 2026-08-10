--!strict
-- What a prop says it is for.
--
-- Three dots over a dog's head mean "there is something here, come and click it".
-- A prop is not that. There is nothing to click and the answer is the doing, so what
-- floats over a rug is not an invitation but an instruction: `Push it aside`. Same
-- position, same waking-up, deliberately different words -- the player learns one
-- rule about *when* a thing in this world is ready for them, and reads the object
-- itself to find out *what*.
--
-- That reading is not decoration, it is the mechanic. An event whose answers are
-- objects has failed completely if the player cannot tell which objects those are,
-- and a five-year-old crawling round a living room touching furniture at random is
-- the exact failure this file exists to prevent. Signposting is part of the
-- mechanic, not a hint layered over one.
--
-- Deliberately not built on a ProximityPrompt, which is the one thing here that
-- differs from Interact and is worth saying why. A prompt exists to turn a keypress,
-- a gamepad button and a tap into one event, and none of those are how any of this
-- is answered -- you answer by being somewhere, or by having moved something. There
-- is no button, so there is nothing for a prompt to normalize, and a prompt that was
-- there anyway would put a phantom `E` on a phone screen over an object that does
-- not respond to it.
--
-- Everything here is driven from the server, which already knows every distance it
-- would need: PropService measures the player against every prop in the set several
-- times a second because that is how the answer is detected at all. Asking the
-- client to do it again, and to be told which billboards to watch, would be a second
-- copy of the same arithmetic that could disagree with the first.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local PROPS = Config.Props
local INTERACT = Config.Interact

local LABEL_NAME = "AgesPropLabel"

-- Cosmetic, and kept out of Config for the reason ChoiceMarkers and Interact both
-- give: the corner radius of a label is not a number anybody balances a life
-- simulator with, and putting it beside the numbers that are makes both harder to
-- find.
local TEXT_COLOR = Color3.fromRGB(255, 250, 240)
local STROKE_COLOR = Color3.fromRGB(20, 18, 14)
local TEXT_SIZE = 15

-- Legible from across the room without being shouted. Matches the dots: dimmed
-- rather than hidden, because a world whose objects only announce themselves once
-- you are touching them is a world you have to walk into wall-first to read.
local FAR_TRANSPARENCY = 0.4
local NEAR_TRANSPARENCY = 0

-- How high above the top of the thing the label floats. Measured off the model's own
-- box rather than guessed, so a rug lying flat on the floor and a child standing up
-- both wear theirs clear of themselves by the same visible margin.
local LIFT_STUDS = 1.1

-- The Stay bar. Under the words rather than around them, and only drawn while
-- something is actually being held -- an empty progress bar over every prop would
-- read as five things loading.
local BAR_HEIGHT = 0.1
local BAR_GAP = 0.06
local BAR_BACKGROUND = Color3.fromRGB(28, 26, 22)
local BAR_FILL = Color3.fromRGB(246, 226, 168)

local PropLabel = {}

PropLabel.Name = LABEL_NAME

export type PropLabelHandle = {
	-- Nil hides the label entirely, which is what a prop that has been picked up
	-- does: it is in the player's arms, it is no longer a thing to go to, and a
	-- `Pick it up` still floating over it would be an instruction to do the thing
	-- that has just been done.
	SetText: (text: string?) -> (),
	SetNear: (near: boolean) -> (),
	-- Stay only. Nil takes the bar away rather than emptying it, so a player who
	-- moves off does not leave a zeroed bar sitting there looking broken.
	SetProgress: (fraction: number?) -> (),
	Destroy: () -> (),
}

-- A BillboardGui cannot adorn a Model, and the part it does adorn has to be one that
-- moves when the thing moves -- otherwise the label stays behind on the carpet while
-- the rug slides out from under it. Same rule, same order of preference, as Interact.
local function adorneeFor(target: Model | BasePart): BasePart?
	if target:IsA("BasePart") then
		return target
	end
	local head = target:FindFirstChild("Head")
	if head ~= nil and head:IsA("BasePart") then
		return head
	end
	return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
end

local function liftFor(target: Model | BasePart, adornee: BasePart): number
	if target:IsA("BasePart") then
		return target.Size.Y / 2 + LIFT_STUDS
	end
	local box, size = target:GetBoundingBox()
	return (box.Position.Y + size.Y / 2) - adornee.Position.Y + LIFT_STUDS
end

-- Attaches the instruction. `target` is borrowed and never owned: nothing here
-- parents it, poses it or takes it away, because PropService is very likely still
-- sliding it around. Destroy removes exactly what was added.
function PropLabel.Attach(target: Model | BasePart, text: string, reachStuds: number): PropLabelHandle?
	local adornee = adorneeFor(target)
	if adornee == nil then
		-- Genuinely possible: a model whose parts have not replicated yet. Refused
		-- rather than guessed at, because a label adorned to nothing is an answer the
		-- player is never told exists.
		return nil
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = LABEL_NAME
	billboard.Adornee = adornee
	billboard.Size = UDim2.fromScale(5.2, 1)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, liftFor(target, adornee), 0)
	-- Seen through whatever it is behind. A cookie half-hidden by a chair leg is
	-- exactly the moment knowing it is an answer matters most.
	billboard.AlwaysOnTop = true
	-- Readable from further than it is usable, so the player can plan a route across
	-- the room instead of discovering their options by bumping into them.
	billboard.MaxDistance = reachStuds * PROPS.LabelDistanceMultiplier
	billboard.Parent = adornee

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = billboard

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = holder

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Text"
	textLabel.AnchorPoint = Vector2.new(0.5, 1)
	textLabel.Position = UDim2.fromScale(0.5, 1 - BAR_HEIGHT - BAR_GAP)
	textLabel.Size = UDim2.fromScale(1, 1 - BAR_HEIGHT - BAR_GAP)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = text
	textLabel.TextColor3 = TEXT_COLOR
	textLabel.TextScaled = false
	textLabel.TextSize = TEXT_SIZE
	textLabel.Font = Enum.Font.GothamMedium
	textLabel.TextTransparency = FAR_TRANSPARENCY
	textLabel.Parent = holder

	-- Without this the words disappear entirely against a light wall, which is most
	-- walls in a house.
	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE_COLOR
	stroke.Thickness = 2
	stroke.Transparency = FAR_TRANSPARENCY
	stroke.Parent = textLabel

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.fromScale(0.5, 1)
	bar.Size = UDim2.fromScale(0.42, BAR_HEIGHT)
	bar.BackgroundColor3 = BAR_BACKGROUND
	bar.BackgroundTransparency = 0.25
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = holder

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = BAR_FILL
	fill.BorderSizePixel = 0
	fill.Parent = bar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local destroyed = false
	local tweens: { Tween } = {}

	-- Cancelled before each new one rather than left to overlap. A player walking in
	-- and out of reach at the edge of a prop would otherwise stack a tween per tick,
	-- and the label would visibly stutter at exactly the distance it matters most.
	local function retween(near: boolean)
		for _, tween in tweens do
			tween:Cancel()
		end
		table.clear(tweens)

		local info = TweenInfo.new(INTERACT.WakeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local transparency = if near then NEAR_TRANSPARENCY else FAR_TRANSPARENCY

		local scaleTween = TweenService:Create(
			scale,
			TweenInfo.new(INTERACT.WakeSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = if near then PROPS.LabelNearScale else 1 }
		)
		local textTween = TweenService:Create(textLabel, info, { TextTransparency = transparency })
		local strokeTween = TweenService:Create(stroke, info, { Transparency = transparency })

		scaleTween:Play()
		textTween:Play()
		strokeTween:Play()
		table.insert(tweens, scaleTween)
		table.insert(tweens, textTween)
		table.insert(tweens, strokeTween)
	end

	return {
		SetText = function(value: string?)
			if destroyed then
				return
			end
			billboard.Enabled = value ~= nil
			if value ~= nil then
				textLabel.Text = value
			end
		end,
		SetNear = function(near: boolean)
			if destroyed then
				return
			end
			retween(near)
		end,
		SetProgress = function(fraction: number?)
			if destroyed then
				return
			end
			bar.Visible = fraction ~= nil
			if fraction ~= nil then
				-- Set outright rather than tweened. This is driven every tick from a
				-- clock that is already running, so a tween would be an animation
				-- chasing an animation and would lag visibly behind the moment the
				-- answer actually lands.
				fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			end
		end,
		Destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			for _, tween in tweens do
				tween:Cancel()
			end
			billboard:Destroy()
		end,
	}
end

return PropLabel
