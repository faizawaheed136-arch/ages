--!strict
-- What a staged delivery *looks like*. DeliveryService decides when something
-- arrives and how long it waits; this decides what appears in the room.
--
-- Split out so the two can change independently: retiming the mail never touches
-- the envelope, and swapping the envelope for a nicer model never touches the
-- scheduler. It is also the seam a new mode lands on -- a mode is a builder
-- function here plus a row in Delivery.luau, and nothing else.
--
-- A presenter returns the anchor the player has to reach, plus a dismiss that
-- owns *all* of its teardown including the anchor itself. Owning teardown rather
-- than having the anchor destroyed for it is what lets a presentation end
-- gracefully: an NPC walks back out of the door instead of blinking away.
--
-- Presenters do not tag, own or register anything. DeliveryService does that to
-- whatever anchor comes back, so a new presenter cannot forget to and quietly
-- produce an object the player can never collect.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local NPCService = require(script.Parent.Parent.services.NPCService)

type LifeEvent = Types.LifeEvent
-- Lives in Types rather than here because NPCService returns one too, and a
-- shared type both modules require is what keeps them from having to require
-- each other.
type DeliveryPresentation = Types.DeliveryPresentation

local DeliveryPresenters = {}

export type Presenter = (player: Player, point: BasePart, event: LifeEvent) -> DeliveryPresentation?

-- Cosmetic dimensions, not design tunables -- an envelope's thickness is not a
-- number anyone balances the game with, so it stays out of Config where the
-- numbers that *are* balanced would have to compete with it for attention.
local LETTER_SIZE = Vector3.new(1.3, 0.07, 0.85)
local LETTER_LIFT = 0.05 -- Clear of the mat, so it doesn't z-fight with it.
local LETTER_YAW = -12 -- Degrees. Dropped mail is never square to the door.
local LETTER_COLOR = Color3.fromRGB(244, 240, 228)

-- Bright enough to find from the far side of a room without reading as a quest
-- marker. Alpha is on the fill, not the outline, so the object keeps its shape.
local HIGHLIGHT_FILL = 0.85
local HIGHLIGHT_OUTLINE = 0.15
local LETTER_ACCENT = Color3.fromRGB(245, 225, 160)
local PHONE_ACCENT = Color3.fromRGB(150, 205, 245)

-- The phone anchor is invisible: the thing to walk to is the phone that is
-- already modeled there, and spawning a second visible object next to it would
-- read as clutter rather than as a call.
local PHONE_ANCHOR_SIZE = Vector3.new(1, 1, 1)

local DELIVERIES_FOLDER = "AgesDeliveries"

-- One folder for everything staged, so a leak is visible in the explorer rather
-- than scattered through the house.
local function deliveriesFolder(): Folder
	local existing = workspace:FindFirstChild(DELIVERIES_FOLDER)
	if existing ~= nil then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = DELIVERIES_FOLDER
	folder.Parent = workspace
	return folder
end

-- An empty asset id means one has not been picked in Studio yet. Returning nil
-- rather than creating a Sound with an empty SoundId keeps the failure at
-- "silent for now" instead of a runtime error on a made-up id.
local function soundAt(parent: Instance, assetId: string, looped: boolean): Sound?
	if assetId == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.Looped = looped
	sound.RollOffMaxDistance = 60
	sound.Parent = parent
	sound:Play()
	return sound
end

local function highlightOn(adornee: Instance, color: Color3): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Adornee = adornee
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = HIGHLIGHT_FILL
	highlight.OutlineTransparency = HIGHLIGHT_OUTLINE
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = adornee
	return highlight
end

-- A delivery point is usually a marker inside the model it belongs to -- the
-- phone part inside the phone -- so the thing worth outlining is the model, not
-- the marker. Falls back to the point when it stands alone.
local function highlightTarget(point: BasePart): Instance
	local model = point:FindFirstAncestorOfClass("Model")
	if model ~= nil and model ~= workspace then
		return model
	end
	return point
end

local function presentLetter(_player: Player, point: BasePart, _event: LifeEvent): DeliveryPresentation?
	local envelope = Instance.new("Part")
	envelope.Name = "Letter"
	envelope.Size = LETTER_SIZE
	envelope.Color = LETTER_COLOR
	envelope.Material = Enum.Material.SmoothPlastic
	envelope.Anchored = true
	-- Non-colliding on purpose: a toddler-height player should walk over the mat
	-- to reach it, not trip on it or push it under the sofa.
	envelope.CanCollide = false
	envelope.CanQuery = false
	envelope.TopSurface = Enum.SurfaceType.Smooth
	envelope.BottomSurface = Enum.SurfaceType.Smooth
	envelope.CFrame = point.CFrame * CFrame.new(0, LETTER_LIFT, 0) * CFrame.Angles(0, math.rad(LETTER_YAW), 0)
	envelope.Parent = deliveriesFolder()

	highlightOn(envelope, LETTER_ACCENT)
	soundAt(envelope, Config.Assets.Sounds.LetterArrive, false)

	return {
		anchor = envelope,
		dismiss = function(_collected: boolean)
			envelope:Destroy()
		end,
	}
end

local function presentPhoneCall(_player: Player, point: BasePart, _event: LifeEvent): DeliveryPresentation?
	local anchor = Instance.new("Part")
	anchor.Name = "PhoneCall"
	anchor.Size = PHONE_ANCHOR_SIZE
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CFrame = point.CFrame
	anchor.Parent = deliveriesFolder()

	local target = highlightTarget(point)
	local highlight = highlightOn(target, PHONE_ACCENT)
	-- Parented to the anchor rather than the phone so the ring travels with the
	-- object that gets destroyed; the phone itself is permanent house geometry
	-- and must come out of this exactly as it went in.
	local ring = soundAt(anchor, Config.Assets.Sounds.PhoneRing, true)

	return {
		anchor = anchor,
		dismiss = function(_collected: boolean)
			if ring ~= nil then
				ring:Stop()
			end
			highlight:Destroy()
			anchor:Destroy()
		end,
	}
end

local function presentNPCApproach(player: Player, point: BasePart, event: LifeEvent): DeliveryPresentation?
	return NPCService.Arrive(player, point, event)
end

-- Closed record, matching the pattern used for delivery styles on the client:
-- add an Ambient mode in Delivery.luau and this stops type-checking until it has
-- been given something to look like.
local PRESENTERS: {
	Letter: Presenter,
	PhoneCall: Presenter,
	NPCApproach: Presenter,
} = {
	Letter = presentLetter,
	PhoneCall = presentPhoneCall,
	NPCApproach = presentNPCApproach,
}

-- Nil for the modes that have no world presence at all. Callers treat that as
-- "not stageable" rather than as an error, because Memory and Direct reaching
-- here would be a routing bug and Delivery.luau already prevents it.
function DeliveryPresenters.For(delivery: Types.EventDelivery): Presenter?
	return (PRESENTERS :: any)[delivery]
end

return DeliveryPresenters
