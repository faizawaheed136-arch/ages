--!strict
-- The dealership landmark: a teal breathing disc at the counter with a floating
-- "AUTOPIA" sign above it.
--
-- Gold discs in this game mean "walk here to do something." The dealership is
-- different — it is a place the player visits, browses, and serves from. A blue-
-- green disc under the counter and a name floating above it make the showroom
-- immediately recognisable from across the street, even when no customer is in
-- line and no shift is running.
--
-- The marker follows the counter position the server pushes each tick. If the
-- city rebuilds and the counter moves, the disc and sign track it without a
-- rebuild by simply moving the parent part.
--
-- Drawn on the client so it stays per-player and does not leak into the server
-- or another person's view of the same spot.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DealerMark = {}

-- Same teal family as the queue bar in CarDealerUI — the same colour on the
-- floor and in the panel tells the player these are the same thing.
local DISC_COLOR = Color3.fromRGB(50, 170, 200)
local DISC_DIM = 0.72
local DISC_BRIGHT = 0.38
local PULSE_SECONDS = 2.0

-- Sign sizing.
local SIGN_WIDTH = 10
local SIGN_HEIGHT = 3
local TITLE_SIZE = 22
local SUB_SIZE = 13
local TITLE_COLOR = Color3.fromRGB(255, 252, 245)
local SUB_COLOR = Color3.fromRGB(160, 220, 230)
local STROKE = Color3.fromRGB(18, 16, 14)
local LIFT = 5

export type Handle = {
	Set: (counter: Vector3?) -> (),
	Destroy: () -> (),
}

function DealerMark.new(): Handle
	local folder = Instance.new("Folder")
	folder.Name = "AgesDealerMark"
	folder.Parent = Workspace

	local disc = Instance.new("Part")
	disc.Name = "Disc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.1, 3, 3)
	disc.CFrame = CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90))
	disc.Color = DISC_COLOR
	disc.Material = Enum.Material.Neon
	disc.Transparency = DISC_DIM
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Parent = folder

	local pulse = TweenService:Create(
		disc,
		TweenInfo.new(PULSE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = DISC_BRIGHT }
	)

	local anchor = Instance.new("Part")
	anchor.Name = "SignAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = folder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Sign"
	billboard.Size = UDim2.new(SIGN_WIDTH, 0, SIGN_HEIGHT, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, LIFT, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 80
	billboard.Enabled = false
	billboard.Parent = anchor

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.6, 0)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = TITLE_SIZE
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextColor3 = TITLE_COLOR
	title.Text = "AUTOPIA"
	title.Parent = billboard

	local stroke1 = Instance.new("UIStroke")
	stroke1.Color = STROKE
	stroke1.Thickness = 2
	stroke1.Parent = title

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Size = UDim2.new(1, 0, 0.4, 0)
	sub.Position = UDim2.new(0, 0, 0.6, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextSize = SUB_SIZE
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.TextColor3 = SUB_COLOR
	sub.Text = "CAR DEALERSHIP"
	sub.Parent = billboard

	local stroke2 = Instance.new("UIStroke")
	stroke2.Color = STROKE
	stroke2.Thickness = 2
	stroke2.Parent = sub

	local handle = {}

	function handle.Set(counter: Vector3?)
		if counter == nil then
			disc.Transparency = 1
			pulse:Cancel()
			billboard.Enabled = false
			return
		end

		disc.Transparency = DISC_DIM
		if not pulse.IsPlaying then
			pulse:Play()
		end

		local discPos = counter + Vector3.new(0, 0.05, 0)
		disc.CFrame = CFrame.new(discPos) * CFrame.Angles(0, 0, math.rad(90))

		anchor.CFrame = CFrame.new(counter + Vector3.new(0, LIFT, 0))
		billboard.Enabled = true
	end

	function handle.Destroy()
		pulse:Cancel()
		folder:Destroy()
	end

	return handle
end

return DealerMark
