--!strict
-- A lit disc on the floor with a word floating over it: go here.
--
-- It used to be more than that. A marker was also how you *answered* things -- four
-- discs fanned around a dog, and walking onto one was picking it -- and that is gone.
-- Choices are made by clicking three dots on the thing they are about and reading a
-- panel; see Interact. What is left is the half that was never about choosing: a
-- destination. The mark under a task at work, a hiring sign's pad, the "go to class"
-- disc outside the school, the lure that teaches a toddler to crawl. Every caller
-- means the same sentence by one now, which is why the type below no longer has to
-- answer where it is or how close counts -- nobody is standing on these to decide
-- anything, they are walking to them to arrive.
--
-- Shared rather than server-side, which it was until the hiring posts needed it.
-- Nothing about a marker was ever server-only -- it is a part, a tween and a label --
-- and some of them have to be built on the client, because a "take this job" mark has
-- to be gone for the one player who took it while it still stands for everybody else.
-- Who builds a marker is the caller's business; what one looks like is this file's.
--
-- The label is not decoration. A disc with no words on it is a coloured patch of
-- carpet, so it is built here rather than left as a later polish pass.

local TweenService = game:GetService("TweenService")

local ChoiceMarkers = {}

-- Cosmetic dimensions, kept out of Config for the reason DeliveryPresenters
-- gives: the thickness of a pad is not a number anyone balances the game with,
-- and putting it in Config makes it compete for attention with the numbers that
-- are. The one number here that *is* balanced -- how wide a marker counts as --
-- is how wide a marker counts as, and it is passed in by whoever knows.
local PAD_THICKNESS = 0.12
-- Sunk very slightly so the pad reads as painted on the floor rather than as a
-- step to trip over. Just enough to beat z-fighting against the floor below.
local PAD_SINK = 0.04

-- Pulsing rather than static. A static translucent disc reads as scenery; the
-- slow breath is what says "this is waiting for you" without an arrow or a
-- floating exclamation mark.
local PAD_TRANSPARENCY_DIM = 0.72
local PAD_TRANSPARENCY_BRIGHT = 0.42
local PULSE_SECONDS = 1.6

-- Warm, and the same family as the Interact accent on the client, so a marker
-- and the panel style it belongs to look like the same game.
local PAD_COLOR = Color3.fromRGB(245, 205, 120)
local LABEL_COLOR = Color3.fromRGB(255, 250, 240)
local LABEL_STROKE = Color3.fromRGB(20, 18, 14)

-- A destination the player cannot use yet. Grey, still, and dimmer than the dim end
-- of the pulse: it is still painted on the floor, because the player should be able
-- to see what they could have done and go and qualify for it, but nothing about it
-- invites being walked onto. The stillness does most of the work -- among two or
-- three breathing pads, the one holding its breath is unmistakable.
local PAD_LOCKED_COLOR = Color3.fromRGB(120, 118, 112)
local PAD_LOCKED_TRANSPARENCY = 0.82
local LABEL_LOCKED_COLOR = Color3.fromRGB(190, 186, 178)

-- The label floats above the pad rather than lying on it, because text painted on
-- the floor is unreadable from standing height -- which is the only height it is
-- ever read from.
local LABEL_LIFT = 2.6
local LABEL_WIDTH_STUDS = 9
local LABEL_HEIGHT_STUDS = 1.6
local LABEL_TEXT_SIZE = 15
local LABEL_STROKE_THICKNESS = 2
-- Beyond this the label is unreadable anyway and just adds clutter to the far side
-- of the room. Far enough to be legible from across a street, because a mark whose
-- words only appear once you are nearly standing on it has stopped being a signpost.
local LABEL_MAX_DISTANCE = 60

-- One field, and that is the whole of it now. A caller already knows where it put a
-- marker -- it passed the point in -- and every caller that cares how close counts
-- has its own figure for that, because arriving at a work task and arriving at a job
-- sign are different distances for reasons that belong to work and to hiring rather
-- than to the disc.
export type ChoiceMarker = {
	destroy: () -> (),
}

-- Everything about how a marker reads, in one argument. An options table rather than
-- positional parameters because the next thing a marker has to say about itself --
-- and there will be one -- should not change this signature again, and because
-- `Build(parent, at, radius, label, false)` at the call site says nothing about what
-- the false is refusing.
export type ChoiceLook = {
	label: string,
	-- Whether walking onto this would be refused -- a job the player is not qualified
	-- for, and nothing else today. Grey and still rather than absent, because a
	-- destination you cannot use yet is worth being able to see and walk toward.
	--
	-- A marker used to be able to carry a price too, back when one was a choice you
	-- answered by standing on it. Money moves through the panel now, and every caller
	-- left builds destinations, so there is no priced disc anywhere in the game -- see
	-- ChoicePanel, which draws the price column that used to live here.
	locked: boolean,
}

-- An outline rather than a backing panel: a panel would be a small piece of UI
-- floating in the room, which is the exact thing this system exists to get rid
-- of. The stroke is what keeps the text readable against a bright wall.
local function outline(into: Instance)
	local stroke = Instance.new("UIStroke")
	stroke.Color = LABEL_STROKE
	stroke.Thickness = LABEL_STROKE_THICKNESS
	stroke.Parent = into
end

-- The words.
local function label(into: BillboardGui, look: ChoiceLook)
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.new(1, 0, 1, 0)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamMedium
	text.TextSize = LABEL_TEXT_SIZE
	text.TextColor3 = if look.locked then LABEL_LOCKED_COLOR else LABEL_COLOR
	text.TextWrapped = true
	text.Text = look.label
	text.Parent = into
	outline(text)
end

-- `at` is the point on the floor the marker is painted onto. Radius should be the
-- same number the caller's own arrival test uses, so the disc the player sees is
-- exactly the disc that counts -- a mark that pays out from outside its own edge, or
-- fails to from inside it, is the worst thing to get wrong here.
function ChoiceMarkers.Build(parent: Instance, at: Vector3, radius: number, look: ChoiceLook): ChoiceMarker
	local locked = look.locked

	local pad = Instance.new("Part")
	pad.Name = "ChoiceMarker"
	pad.Shape = Enum.PartType.Cylinder
	-- A cylinder's length runs along its local X, so it is stood on its end to
	-- lie flat: local X becomes world Y and becomes the pad's thickness.
	pad.Size = Vector3.new(PAD_THICKNESS, radius * 2, radius * 2)
	pad.CFrame = CFrame.new(at + Vector3.new(0, PAD_THICKNESS / 2 - PAD_SINK, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pad.Color = if locked then PAD_LOCKED_COLOR else PAD_COLOR
	pad.Material = Enum.Material.Neon
	pad.Transparency = if locked then PAD_LOCKED_TRANSPARENCY else PAD_TRANSPARENCY_DIM
	pad.Anchored = true
	-- Walked over, not into. A pad that collided would be a lip to trip on at a
	-- toddler's scale, and one that answered queries would catch raycasts meant
	-- for the floor underneath it.
	pad.CanCollide = false
	pad.CanQuery = false
	pad.CanTouch = false
	pad.CastShadow = false
	pad.Parent = parent

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.new(LABEL_WIDTH_STUDS, 0, LABEL_HEIGHT_STUDS, 0)
	billboard.SizeOffset = Vector2.new(0, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, LABEL_LIFT, 0)
	-- Drawn through the furniture it stands behind. A choice the player cannot
	-- read is a choice they cannot make, and half-occluded text is worse than no
	-- text because it looks like a rendering fault rather than a hidden option.
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = LABEL_MAX_DISTANCE
	billboard.Parent = pad

	label(billboard, look)

	-- No pulse on a locked marker, and no tween to cancel later. The absence is the
	-- signal: the pads that are waiting for you breathe, and this one does not.
	local pulse: Tween? = nil
	if not locked then
		pulse = TweenService:Create(
			pad,
			TweenInfo.new(PULSE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = PAD_TRANSPARENCY_BRIGHT }
		)
	end
	if pulse ~= nil then
		pulse:Play()
	end

	return {
		destroy = function()
			-- Cancelled before the part goes, so the tween is not left running
			-- against a destroyed instance for the rest of the server's life.
			local running = pulse
			if running ~= nil then
				running:Cancel()
			end
			pad:Destroy()
		end,
	}
end

return ChoiceMarkers
