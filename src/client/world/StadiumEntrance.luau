--!strict
-- The stadium entrance camera cutscene: cuts in close on the player for a few
-- seconds when StadiumEntranceService decides they have just walked through
-- the bowl's own gate -- the same walkout shot a sports broadcast gives a
-- player before kickoff (NBA 2K, EA FC). Purely local: the camera is the one
-- piece of a Roblox client that can never be somebody else's, so there is
-- nothing here for a server round trip to get right or wrong. The server's
-- whole job was deciding this player earns the moment (see
-- StadiumEntranceService); this file's whole job is showing it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local ENTRANCE = Config.StadiumEntrance

local StadiumEntrance = {}

local player = Players.LocalPlayer
local playing = false

-- The held shot's CFrame for this frame: a three-quarter portrait a fixed
-- offset behind, above and to the side of the character's root, looking at
-- chest height rather than the feet -- close enough to read as a zoom, wide
-- enough to keep the whole character in frame. Recomputed every frame off
-- the character's live position rather than tweened once, so a player who
-- keeps walking during the hold does not drift out of their own close-up.
local function framingCFrame(root: BasePart): CFrame
	local look = root.CFrame.LookVector
	local side = root.CFrame.RightVector
	local eye = root.Position
		+ Vector3.new(0, ENTRANCE.FramingHeightStuds, 0)
		- look * ENTRANCE.FramingDistanceStuds
		+ side * ENTRANCE.FramingSideStuds
	local at = root.Position + Vector3.new(0, ENTRANCE.FramingHeightStuds * 0.5, 0)
	return CFrame.lookAt(eye, at)
end

-- A rough "camera about to hand back to Custom" framing: behind the
-- character's own facing rather than the held shot's angle, since that is
-- close to where Roblox's default follow camera actually puts itself. The
-- release tween eases toward this so the hard switch to Custom at the end
-- is a small correction instead of a snap across the screen.
local function releaseCFrame(root: BasePart): CFrame
	local back = root.CFrame.LookVector
	local eye = root.Position - back * 12.0 + Vector3.new(0, 4.0, 0)
	local at = root.Position + Vector3.new(0, 2.0, 0)
	return CFrame.lookAt(eye, at)
end

function StadiumEntrance.Play()
	if playing then
		return
	end
	local character = player.Character
	local rootInstance = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if rootInstance == nil or not rootInstance:IsA("BasePart") or humanoid == nil then
		return
	end
	local root = rootInstance :: BasePart

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	playing = true
	local startFov = camera.FieldOfView

	camera.CameraType = Enum.CameraType.Scriptable

	local heldConnection: RBXScriptConnection? = nil
	local diedConnection: RBXScriptConnection? = nil

	local function stop()
		if heldConnection ~= nil then
			heldConnection:Disconnect()
			heldConnection = nil
		end
		if diedConnection ~= nil then
			diedConnection:Disconnect()
			diedConnection = nil
		end
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
		playing = false
	end

	-- A death mid-cutscene is the one interruption a tween's own Completed
	-- handler can never see coming -- hand the camera back immediately rather
	-- than hold a close-up on a character that is about to be removed.
	diedConnection = humanoid.Died:Connect(stop)

	local zoomTween = TweenService:Create(
		camera,
		TweenInfo.new(ENTRANCE.ZoomInSeconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ CFrame = framingCFrame(root), FieldOfView = ENTRANCE.FramingFov }
	)

	zoomTween.Completed:Connect(function()
		if not playing then
			return
		end

		-- Hold: track the character every frame rather than sit on the CFrame
		-- the zoom tween landed on, in case they are still moving.
		heldConnection = RunService.RenderStepped:Connect(function()
			if character.Parent == nil or root.Parent == nil then
				stop()
				return
			end
			camera.CFrame = framingCFrame(root)
		end)

		task.delay(ENTRANCE.HoldSeconds, function()
			if not playing or heldConnection == nil then
				return
			end
			heldConnection:Disconnect()
			heldConnection = nil

			if character.Parent == nil or root.Parent == nil then
				stop()
				return
			end

			local releaseTween = TweenService:Create(
				camera,
				TweenInfo.new(ENTRANCE.ReleaseSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
				{ CFrame = releaseCFrame(root), FieldOfView = startFov }
			)
			releaseTween.Completed:Connect(stop)
			releaseTween:Play()
		end)
	end)

	zoomTween:Play()
end

return StadiumEntrance
