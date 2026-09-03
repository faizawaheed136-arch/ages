--!strict
-- The camera, and the only thing allowed to touch it.
--
-- **Why the seat vantage and the impact shake live in one module.**
--
-- Both want to write `camera.CFrame` every frame. As two modules, whichever ran second each
-- frame would erase the first -- a shake while seated would fight the fixed vantage and produce
-- a camera that flickers between two positions rather than a fixed shot that trembles.
--
-- So there is one owner. It keeps a `base` CFrame -- what the camera would be without any
-- disturbance -- and composes the shake on top of it once per frame:
--
--     camera.CFrame = base * shake
--
-- Seating tweens `base`. Impacts add trauma. Neither knows about the other.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local remotes = ReplicatedStorage:WaitForChild("Showcase"):WaitForChild("Remotes")
local SeatCamera = remotes:WaitForChild("SeatCamera") :: RemoteEvent
local Impact = remotes:WaitForChild("Impact") :: RemoteEvent

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Wide-angle by *framing*, not by distortion. 78 opens the shot up enough to hold the ring and
-- the far bench in one frame; much past 85 and the near ropes start to bow, which reads as a
-- fisheye lens rather than as a wide shot.
local SEATED_FOV = 78
local NORMAL_FOV = 70

local MOVE_IN = TweenInfo.new(1.15, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local MOVE_OUT = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- **Trauma, not amplitude.** Impacts add trauma; trauma decays on its own; the offset applied is
-- trauma *squared*. Squaring is what makes a hard hit feel disproportionately harder than a soft
-- one and, more usefully, makes the tail die away smoothly instead of ending on a visible step.
local TRAUMA_DECAY = 1.6
local MAX_ANGLE = math.rad(3.4)
local MAX_SHIFT = 0.75
local SHAKE_FREQUENCY = 26

local ArenaCamera = {}

local seated = false
local trauma = 0
local seed = math.random() * 1000

local base = Instance.new("CFrameValue")
base.Name = "ArenaCameraBase"

-- ---------------------------------------------------------------------------------------
-- Shake
-- ---------------------------------------------------------------------------------------

local function shakeOffset(clock: number): CFrame
	if trauma <= 0 then
		return CFrame.identity
	end
	-- Squared, so the falloff is smooth rather than linear-and-then-gone.
	local magnitude = trauma * trauma
	local t = clock * SHAKE_FREQUENCY

	-- math.noise rather than math.random: successive random values jump, which reads as static.
	-- Sampling smooth noise at three offsets gives three independent but continuous curves, and
	-- continuity is the difference between a camera shaking and a camera glitching.
	local yaw = math.noise(t, seed, 0) * MAX_ANGLE * magnitude
	local pitch = math.noise(t, seed, 8) * MAX_ANGLE * magnitude
	local roll = math.noise(t, seed, 16) * MAX_ANGLE * magnitude
	local shiftX = math.noise(t, seed, 24) * MAX_SHIFT * magnitude
	local shiftY = math.noise(t, seed, 32) * MAX_SHIFT * magnitude

	return CFrame.new(shiftX, shiftY, 0) * CFrame.Angles(pitch, yaw, roll)
end

function ArenaCamera.AddTrauma(amount: number)
	trauma = math.clamp(trauma + amount, 0, 1)
end

-- ---------------------------------------------------------------------------------------
-- Seating
-- ---------------------------------------------------------------------------------------

local function sit(target: CFrame, fov: number?)
	if seated then
		return
	end
	seated = true
	-- The caller names the lens. The gym's benches want the wide 78; a classroom desk wants
	-- something nearer a reading distance, because 78 puts half the room in frame and makes the
	-- chalkboard tiny. Defaulting keeps every existing caller unchanged.
	local lens = fov or SEATED_FOV

	-- Start from where the camera already is, so the move reads as a camera travelling rather
	-- than a cut. Setting Scriptable first and then tweening from a stale value is what produces
	-- the snap-then-glide that looks broken.
	base.Value = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable

	TweenService:Create(base, MOVE_IN, { Value = target }):Play()
	TweenService:Create(camera, MOVE_IN, { FieldOfView = lens }):Play()
end

local function stand()
	if not seated then
		return
	end
	seated = false

	TweenService:Create(camera, MOVE_OUT, { FieldOfView = NORMAL_FOV }):Play()

	-- Ease back toward a spot behind the character before handing control back, rather than
	-- setting CameraType = Custom immediately. Custom snaps to its own idea of where the camera
	-- belongs, and after a wide arena shot that snap is violent.
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root ~= nil then
		local behind = (root :: BasePart).CFrame * CFrame.new(0, 3, 12)
		local tween = TweenService:Create(base, MOVE_OUT, { Value = CFrame.lookAt(behind.Position, (root :: BasePart).Position + Vector3.new(0, 2, 0)) })
		tween.Completed:Once(function()
			camera.CameraType = Enum.CameraType.Custom
		end)
		tween:Play()
	else
		camera.CameraType = Enum.CameraType.Custom
	end
end

-- ---------------------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------------------

function ArenaCamera.Start()
	SeatCamera.OnClientEvent:Connect(function(on: boolean, target: CFrame?, fov: number?)
		if on and target ~= nil then
			sit(target, fov)
		else
			stand()
		end
	end)

	Impact.OnClientEvent:Connect(function(strength: number)
		ArenaCamera.AddTrauma(math.clamp(strength, 0, 1) * 0.85)
	end)

	-- A respawn resets CameraType behind our back. If it happens while seated the camera would
	-- otherwise be left scriptable and pointed at the ring with the player somewhere else.
	player.CharacterAdded:Connect(function()
		if seated then
			seated = false
			trauma = 0
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = NORMAL_FOV
		end
	end)

	-- **After the camera, not before.** Bound one step later than Enum.RenderPriority.Camera so
	-- the shake is applied on top of whatever the default camera just computed. Bound earlier
	-- and the built-in camera overwrites it the same frame, which looks like the shake silently
	-- not working.
	RunService:BindToRenderStep("ArenaCameraShake", Enum.RenderPriority.Camera.Value + 1, function(delta: number)
		camera = workspace.CurrentCamera

		if trauma > 0 then
			trauma = math.max(trauma - TRAUMA_DECAY * delta, 0)
		end

		local clock = os.clock()
		if seated then
			camera.CFrame = base.Value * shakeOffset(clock)
		elseif trauma > 0 then
			-- Free camera: compose onto whatever the default camera produced this frame.
			camera.CFrame = camera.CFrame * shakeOffset(clock)
		end
	end)
end

return ArenaCamera
