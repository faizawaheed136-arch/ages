--!strict
-- What somebody standing in front of the player says, spoken from where they are
-- standing rather than printed in a corner of the screen. `PersonState.reply` already
-- carried this line; only where it is read changes here -- a person's own words belong
-- over their own head, not laid out flat against the HUD or trapped in the choice panel
-- until a timer lets it go.
--
-- Self-contained on purpose, and that is the whole shape of this file: it finds its
-- speaker by walking the same AgesInteractKind / AgesInteractId attributes Interact.luau
-- already stamps on every person's ProximityPrompt, rather than asking Prompts.luau or
-- Interact.luau for a lookup neither of them owns today. Nothing in either of those two
-- files changes for this to work.

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Interact = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Interact"))

local BUBBLE = Config.SpeechBubble

local SpeechBubble = {}

-- The part a person's dots and nameplate already hang from, found by the same kind/id
-- attributes Prompts.luau reads off the ProximityPrompt. A full descendant walk rather
-- than a held reference, because a reply arrives perhaps once every several seconds and
-- the population in reach of one is never more than a room's worth of rigs.
local function partFor(personId: string): BasePart?
	for _, instance in Workspace:GetDescendants() do
		if instance.Name ~= Interact.PromptName or not instance:IsA("ProximityPrompt") then
			continue
		end
		if instance:GetAttribute(Interact.KindAttribute) ~= "Person" then
			continue
		end
		if instance:GetAttribute(Interact.IdAttribute) ~= personId then
			continue
		end
		local parent = instance.Parent
		if parent ~= nil and parent:IsA("BasePart") then
			return parent
		end
	end
	return nil
end

-- How high above this particular person's own head the card has to float to clear the
-- three dots and the nameplate already stacked there -- see Interact.luau's DOTS_LIFT and
-- NAMEPLATE_LIFT, whose bounding-box math this mirrors rather than imports, on the same
-- reasoning SpeechBubble.luau opens with: nothing in Interact.luau moves for this file.
local function liftFor(part: BasePart): number
	local model = part:FindFirstAncestorOfClass("Model")
	if model == nil then
		return BUBBLE.LiftAboveHeadStuds
	end
	local box, size = model:GetBoundingBox()
	return (box.Position.Y + size.Y / 2) - part.Position.Y + BUBBLE.LiftAboveHeadStuds
end

-- One bubble per speaker. Held so a second reply arriving while the first is still
-- fading replaces it outright rather than stacking two cards over the same head.
local active: { [string]: { gui: BillboardGui, token: number } } = {}

function SpeechBubble.Show(personId: string, text: string, good: boolean)
	local part = partFor(personId)
	if part == nil then
		-- Genuinely possible: the reply push and the rig despawning can race. A line
		-- nobody is left standing to say is silently dropped rather than guessed at.
		return
	end

	local previous = active[personId]
	if previous ~= nil then
		previous.gui:Destroy()
		active[personId] = nil
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "AgesSpeechBubble"
	gui.Adornee = part
	gui.Size = UDim2.fromScale(BUBBLE.Width, BUBBLE.Height)
	gui.StudsOffsetWorldSpace = Vector3.new(0, liftFor(part), 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = BUBBLE.MaxDistanceStuds
	gui.Parent = part

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = BUBBLE.BackgroundColor
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = if good then BUBBLE.GoodStrokeColor else BUBBLE.StrokeColor
	stroke.Thickness = 1.5
	stroke.Transparency = 1
	stroke.Parent = card

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = card

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextWrapped = true
	label.TextScaled = true
	-- Quoted, the same convention the HUD caption used to carry: this is the one line on
	-- screen that is a person talking to the player rather than the game narrating.
	label.Text = `"{text}"`
	label.TextColor3 = if good then BUBBLE.GoodTextColor else BUBBLE.TextColor
	label.TextTransparency = 1
	label.Parent = card

	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MaxTextSize = BUBBLE.MaxTextSize
	sizeConstraint.Parent = label

	local fadeIn = TweenInfo.new(BUBBLE.FadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(card, fadeIn, { BackgroundTransparency = BUBBLE.BackgroundTransparency }):Play()
	TweenService:Create(label, fadeIn, { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, fadeIn, { Transparency = 0.2 }):Play()

	-- Stamped fresh per show and compared on the way out, so a bubble that has already
	-- been replaced or destroyed cannot have its old fade-out timer reach back in and
	-- tear down the new one.
	local token = os.clock()
	active[personId] = { gui = gui, token = token }

	task.delay(BUBBLE.HoldSeconds, function()
		local entry = active[personId]
		if entry == nil or entry.token ~= token then
			return
		end
		local fadeOut = TweenInfo.new(BUBBLE.FadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(card, fadeOut, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, fadeOut, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, fadeOut, { Transparency = 1 }):Play()
		task.delay(BUBBLE.FadeSeconds, function()
			local finished = active[personId]
			if finished ~= nil and finished.token == token then
				active[personId] = nil
			end
			gui:Destroy()
		end)
	end)
end

return SpeechBubble
