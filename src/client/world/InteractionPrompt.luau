--!strict
-- The bottom‑centre interaction prompt. A big‑game‑style bar that tells the player
-- exactly what they can do right now and how to do it, without forcing them to hunt
-- for tiny dots somewhere above a character's head.
--
-- The three‑dot billboards above objects are still there (they are the signpost), but
-- the prompt bar is what the player actually reads. It shows:
--   [E]  Talk to Mom
--   [E]  Use Balance
--   [E]  Open
--
-- One bar, always centred at the bottom, fading in when you approach something and
-- fading out when you leave. The text comes from the same `actionText` / `objectText`
-- that `Interact.Attach` already stores on the ProximityPrompt, so nothing has to be
-- duplicated in content.
--
-- The bar is built once per client session and lives in its own ScreenGui at
-- DisplayOrder 1, below everything else.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local PROMPT = Config.InteractionPrompt

local InteractionPrompt = {}

type Handle = {
	Show: (action: string, object: string) -> (),
	Hide: () -> (),
	Destroy: () -> (),
}

-- The key currently active on this player's input device. Refreshed on every change
-- so a player who picks up a keyboard mid‑session gets the right letter without
-- restarting.
local function currentKey(): string
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return ""
	end
	return Config.Interact.KeyboardKey.Name
end

function InteractionPrompt.new(): Handle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AgesInteractionPrompt"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 1
	screenGui.Parent = playerGui

	-- The bar itself. Dark, rounded, centred at the bottom.
	local bar = Instance.new("Frame")
	bar.Name = "PromptBar"
	bar.Size = UDim2.new(PROMPT.BarWidth, 0, 0, PROMPT.BarHeightStuds)
	bar.Position = UDim2.new(
		0.5 + PROMPT.HorizontalOffset,
		0,
		1,
		-PROMPT.BottomOffset - PROMPT.BarHeightStuds
	)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.BackgroundColor3 = PROMPT.BarColor
	bar.BackgroundTransparency = PROMPT.BarTransparency
	bar.BorderSizePixel = 0
	bar.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = bar

	local barStroke = Instance.new("UIStroke")
	barStroke.Color = PROMPT.BarStrokeColor
	barStroke.Thickness = 1
	barStroke.Transparency = 1
	barStroke.Parent = bar

	-- The key box on the left: a white rounded square with the letter inside.
	local keyBox = Instance.new("Frame")
	keyBox.Name = "KeyBox"
	keyBox.Size = UDim2.new(0, 36, 0, 36)
	keyBox.Position = UDim2.fromScale(0.12, 0.5)
	keyBox.AnchorPoint = Vector2.new(0, 0.5)
	keyBox.BackgroundColor3 = PROMPT.KeyBoxColor
	keyBox.BackgroundTransparency = 1
	keyBox.BorderSizePixel = 0
	keyBox.Parent = bar

	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(0, 6)
	keyCorner.Parent = keyBox

	local keyStroke = Instance.new("UIStroke")
	keyStroke.Color = PROMPT.KeyStrokeColor
	keyStroke.Thickness = 1.5
	keyStroke.Transparency = 1
	keyStroke.Parent = keyBox

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "KeyLabel"
	keyLabel.Size = UDim2.new(1, 0, 1, 0)
	keyLabel.BackgroundTransparency = 1
	keyLabel.Font = Enum.Font.GothamBold
	keyLabel.Text = currentKey()
	keyLabel.TextColor3 = PROMPT.KeyTextColor
	keyLabel.TextTransparency = 1
	keyLabel.TextScaled = true
	keyLabel.TextWrapped = false
	keyLabel.Parent = keyBox

	local keySizeConstraint = Instance.new("UITextSizeConstraint")
	keySizeConstraint.MaxTextSize = 18
	keySizeConstraint.Parent = keyLabel

	-- The action text on the right, next to the key box.
	-- "Talk to Mom" or "Use Balance" or "Open".
	local actionLabel = Instance.new("TextLabel")
	actionLabel.Name = "ActionLabel"
	actionLabel.Size = UDim2.new(1, -72, 1, 0)
	actionLabel.Position = UDim2.new(0.38, 0, 0.5, 0)
	actionLabel.AnchorPoint = Vector2.new(0, 0.5)
	actionLabel.BackgroundTransparency = 1
	actionLabel.Font = Enum.Font.GothamMedium
	actionLabel.Text = ""
	actionLabel.TextColor3 = PROMPT.ActionTextColor
	actionLabel.TextTransparency = 1
	actionLabel.TextScaled = true
	actionLabel.TextXAlignment = Enum.TextXAlignment.Left
	actionLabel.Parent = bar

	local actionSizeConstraint = Instance.new("UITextSizeConstraint")
	actionSizeConstraint.MaxTextSize = 20
	actionSizeConstraint.Parent = actionLabel

	-- Fade state. Every piece above starts fully transparent (the bar's own background,
	-- both strokes, the key box and both labels) rather than only the bar -- a child
	-- Frame or TextLabel's transparency does not inherit its parent's, so a bar that is
	-- itself invisible does nothing to hide a key box built with a fixed transparency of
	-- its own. That mismatch is exactly what used to leave a permanent "E" sitting at the
	-- bottom of the screen: the bar's fade tween was built but never `:Play()`-ed, and
	-- even if it had been, it would only ever have faded the bar's own background, not
	-- the five other instances layered on top of it.
	bar.BackgroundTransparency = 1
	local visible = false
	local activeTweens: { Tween } = {}

	local function cancelTweens()
		for _, tween in activeTweens do
			tween:Cancel()
		end
		table.clear(activeTweens)
	end

	-- Every faded instance moves together, in and out, as one group -- so `intoVisible`
	-- is the only thing a caller ever has to decide.
	local function fadeTo(intoVisible: boolean)
		cancelTweens()
		local direction = if intoVisible then Enum.EasingDirection.Out else Enum.EasingDirection.In
		local info = TweenInfo.new(PROMPT.FadeSeconds, Enum.EasingStyle.Quad, direction)
		local targets: { [Instance]: { [string]: any } } = {
			[bar] = { BackgroundTransparency = if intoVisible then PROMPT.BarTransparency else 1 },
			[barStroke] = { Transparency = if intoVisible then PROMPT.BarStrokeTransparency else 1 },
			[keyBox] = { BackgroundTransparency = if intoVisible then PROMPT.KeyBoxTransparency else 1 },
			[keyStroke] = { Transparency = if intoVisible then PROMPT.KeyStrokeTransparency else 1 },
			[keyLabel] = { TextTransparency = if intoVisible then 0 else 1 },
			[actionLabel] = { TextTransparency = if intoVisible then 0 else 1 },
		}
		for instance, goal in targets do
			local tween = TweenService:Create(instance, info, goal)
			tween:Play()
			table.insert(activeTweens, tween)
		end
	end

	-- Declared before the three methods below fill it in, so each one can be written as
	-- `function handle.X(...)` rather than three separate locals reassembled into a table
	-- at the bottom. Cast rather than left untyped: every field is filled in by the time
	-- `new()` returns and the cast says so once instead of asking every caller to trust it.
	local handle = {} :: Handle

	-- Show the prompt with the given action + object text.
	function handle.Show(action: string, object: string)
		if visible then
			-- Already shown: just update the text.
			keyLabel.Text = currentKey()
			actionLabel.Text = if object ~= "" then `{action} {object}` else action
			return
		end
		visible = true
		keyLabel.Text = currentKey()
		actionLabel.Text = if object ~= "" then `{action} {object}` else action
		fadeTo(true)
	end

	-- Hide the prompt with a fade out.
	function handle.Hide()
		if not visible then
			return
		end
		visible = false
		fadeTo(false)
	end

	-- Clean up on death / respawn.
	function handle.Destroy()
		cancelTweens()
		screenGui:Destroy()
	end

	-- React to input device changes so the key label stays correct.
	UserInputService.LastInputTypeChanged:Connect(function()
		if visible then
			keyLabel.Text = currentKey()
		end
	end)

	return handle
end

return InteractionPrompt
