--!strict
-- What a choice looks like when it is standing in the room. EnactService decides
-- where the choices go and notices the player reaching one; this decides what
-- they look like when they get there.
--
-- Same split, and for the same reason, as DeliveryService and DeliveryPresenters:
-- retuning how far apart the choices stand never touches the pad, and replacing
-- the pad with a real prop never touches the placement math.
--
-- A marker is a pad on the floor with its choice written above it. The label is
-- not decoration -- it is the entire reason walking onto a patch of floor means
-- anything, so it is built here rather than left as a later polish pass.

local TweenService = game:GetService("TweenService")

local ChoiceMarkers = {}

-- Cosmetic dimensions, kept out of Config for the reason DeliveryPresenters
-- gives: the thickness of a pad is not a number anyone balances the game with,
-- and putting it in Config makes it compete for attention with the numbers that
-- are. The one number here that *is* balanced -- how wide a marker counts as --
-- is Config.Enact.MarkerRadius, and it is passed in.
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

-- The label floats above the pad rather than lying on it, because text painted on
-- the floor is unreadable from standing height -- which is the only height it is
-- ever read from.
local LABEL_LIFT = 2.6
local LABEL_WIDTH_STUDS = 9
local LABEL_HEIGHT_STUDS = 1.6
local LABEL_TEXT_SIZE = 15
local LABEL_STROKE_THICKNESS = 2
-- Beyond this the label is unreadable anyway and just adds clutter to the far
-- side of the room. Comfortably past MarkerSpread so it never hides the choice
-- the player is being asked to walk to.
local LABEL_MAX_DISTANCE = 60

export type ChoiceMarker = {
	-- Where a player has to stand. The pad's own position, held separately
	-- because the pad is a presentation detail and may stop being a part at all.
	position: Vector3,
	destroy: () -> (),
}

-- `at` is the point on the floor the marker is painted onto. Radius is the same
-- number the reach test uses, so the disc the player sees is exactly the disc
-- that counts -- a marker that pays out from outside its own edge, or fails to
-- from inside it, would be the worst possible thing to get wrong here.
function ChoiceMarkers.Build(parent: Instance, at: Vector3, label: string, radius: number): ChoiceMarker
	local pad = Instance.new("Part")
	pad.Name = "ChoiceMarker"
	pad.Shape = Enum.PartType.Cylinder
	-- A cylinder's length runs along its local X, so it is stood on its end to
	-- lie flat: local X becomes world Y and becomes the pad's thickness.
	pad.Size = Vector3.new(PAD_THICKNESS, radius * 2, radius * 2)
	pad.CFrame = CFrame.new(at + Vector3.new(0, PAD_THICKNESS / 2 - PAD_SINK, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pad.Color = PAD_COLOR
	pad.Material = Enum.Material.Neon
	pad.Transparency = PAD_TRANSPARENCY_DIM
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

	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, 0, 1, 0)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamMedium
	text.TextSize = LABEL_TEXT_SIZE
	text.TextColor3 = LABEL_COLOR
	text.TextWrapped = true
	text.Text = label
	text.Parent = billboard

	-- An outline rather than a backing panel: a panel would be a small piece of UI
	-- floating in the room, which is the exact thing this system exists to get rid
	-- of. The stroke is what keeps the text readable against a bright wall.
	local stroke = Instance.new("UIStroke")
	stroke.Color = LABEL_STROKE
	stroke.Thickness = LABEL_STROKE_THICKNESS
	stroke.Parent = text

	local pulse = TweenService:Create(
		pad,
		TweenInfo.new(PULSE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = PAD_TRANSPARENCY_BRIGHT }
	)
	pulse:Play()

	return {
		position = at,
		destroy = function()
			-- Cancelled before the part goes, so the tween is not left running
			-- against a destroyed instance for the rest of the server's life.
			pulse:Cancel()
			pad:Destroy()
		end,
	}
end

return ChoiceMarkers
