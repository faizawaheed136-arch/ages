--!strict
-- The academy's mood, applied only to whoever is standing in it.
--
-- **The problem this exists to solve.** There is one Lighting service per place. AGES's is tuned
-- bright so the town and the interiors of v1's school are readable -- Brightness 2.1,
-- ExposureCompensation 0.1, EnvironmentDiffuseScale 0.75. The academy wants the opposite:
-- Brightness 3, exposure -0.45, diffuse 0.18. Writing the second set into default.project.json
-- would darken the entire town and city, which is not a trade anybody asked for.
--
-- **Why the client can fix this and the server cannot.** Lighting properties set on a client
-- affect only that client and do not replicate. So the mood can be per-player: the town stays
-- bright for everyone outside, and whoever walks into the academy gets the Gakuran grade. No
-- remote, no server state, nothing to keep in sync.
--
-- ClockTime and GeographicLatitude are deliberately *not* touched. They set the sun's direction,
-- and swinging the sun across the sky as somebody steps through a door would be far more
-- jarring than the grade change is worth -- it would also rotate every shadow in the town for
-- that player.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LightingZone = {}

-- The academy's footprint, from Plan via the bake. A box test rather than a part with a Touched
-- event: touch events on a 400 x 448 volume fire constantly and cost more than five distance
-- checks a second.
local MIN = Vector3.new(-440, -8, -956)
local MAX = Vector3.new(-40, 70, -508)

-- 5 Hz. A grade that takes a fifth of a second to *start* is imperceptible against a 1.2 second
-- crossfade; a Heartbeat check would be twelve times the cost for no visible difference.
local POLL = 0.2
local FADE = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Captured at startup rather than written down here, so the outside stays whatever AGES says it
-- is. Hardcoding the town's values would mean this file silently overriding any future change
-- Agent A makes to default.project.json's Lighting.
local outside: { [string]: any } = {}
local outsideAtmosphere: { [string]: any } = {}

local INSIDE = {
	Brightness = 3,
	ExposureCompensation = -0.45,
	Ambient = Color3.fromRGB(10, 12, 18),
	OutdoorAmbient = Color3.fromRGB(28, 33, 46),
	ColorShift_Top = Color3.fromRGB(255, 224, 186),
	ColorShift_Bottom = Color3.fromRGB(28, 38, 58),
	EnvironmentDiffuseScale = 0.18,
	EnvironmentSpecularScale = 0.45,
}

local INSIDE_ATMOSPHERE = {
	Density = 0.42,
	Offset = 0.28,
	Haze = 2.4,
	Glare = 0.45,
	Color = Color3.fromRGB(126, 134, 152),
	Decay = Color3.fromRGB(72, 84, 110),
}

local inside = false
local grade: ColorCorrectionEffect? = nil

local function capture()
	for key in INSIDE do
		outside[key] = (Lighting :: any)[key]
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere ~= nil then
		for key in INSIDE_ATMOSPHERE do
			outsideAtmosphere[key] = (atmosphere :: any)[key]
		end
	end

	-- AGES has Bloom and SunRays but no ColorCorrection, and the contrast in section 03 is most
	-- of the look. Added here rather than to the project file so it exists only on this client
	-- and sits neutral until the player is actually inside.
	local existing = Lighting:FindFirstChild("AcademyGrade")
	if existing ~= nil then
		grade = existing :: ColorCorrectionEffect
	else
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "AcademyGrade"
		effect.Brightness = 0
		effect.Contrast = 0
		effect.Saturation = 0
		effect.TintColor = Color3.new(1, 1, 1)
		effect.Parent = Lighting
		grade = effect
	end
end

local function apply(target: boolean)
	if target == inside then
		return
	end
	inside = target

	local goal = {}
	for key, value in INSIDE do
		goal[key] = if target then value else outside[key]
	end
	TweenService:Create(Lighting, FADE, goal):Play()

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere ~= nil and next(outsideAtmosphere) ~= nil then
		local air = {}
		for key, value in INSIDE_ATMOSPHERE do
			air[key] = if target then value else outsideAtmosphere[key]
		end
		TweenService:Create(atmosphere, FADE, air):Play()
	end

	local effect = grade
	if effect ~= nil then
		TweenService:Create(effect, FADE, {
			Contrast = if target then 0.24 else 0,
			Saturation = if target then -0.15 else 0,
			Brightness = if target then -0.02 else 0,
			TintColor = if target then Color3.fromRGB(226, 233, 255) else Color3.new(1, 1, 1),
		}):Play()
	end
end

function LightingZone.Start()
	capture()

	task.spawn(function()
		while true do
			task.wait(POLL)
			local character = Players.LocalPlayer.Character
			local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
			if root == nil then
				-- Dead or still loading. Restore rather than hold the interior grade over a
				-- respawn screen, which would leave the town dark for a player standing in it.
				apply(false)
				continue
			end
			local p = (root :: BasePart).Position
			apply(
				p.X >= MIN.X and p.X <= MAX.X
					and p.Y >= MIN.Y and p.Y <= MAX.Y
					and p.Z >= MIN.Z and p.Z <= MAX.Z
			)
		end
	end)
end

return LightingZone
