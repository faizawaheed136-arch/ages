--!strict
-- Locks the camera onto this player's stage and drifts it.
--
-- The framing itself is not computed here. The server built a `CameraSpot` marker as part of
-- the stage, and this reads it — which is the whole reason that marker exists. A client that
-- worked the shot out from `Config.Lobby.Stage` would be a second implementation of the
-- framing, and the day somebody moved `CameraOffset` the avatar would end up facing one
-- direction and the camera looking from another. One set of numbers, resolved once, on the
-- side that also turned the character.
--
-- The drift is the opposite: it is motion rather than framing, nothing on the server depends
-- on it, and running it here costs one CFrame write per frame on one machine instead of a
-- replicated camera. Movement belongs to whoever is watching.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

-- Written out here and in StageService, and nowhere else. See the note there on why these
-- are names under a per-player folder rather than CollectionService tags.
local STAGE_FOLDER = "AgesLobbyStages"
local MARK_NAME = "Mark"
local CAMERA_NAME = "CameraSpot"

local StageCamera = {}

local player = Players.LocalPlayer

-- Yields until the server has built this player's stage.
--
-- Waiting rather than polling-and-giving-up because there is no useful fallback: a lobby
-- camera pointed at the default spawn is a black screen with a menu over it, which reads as
-- a broken game rather than as a slow one. The stage always arrives -- `StageService.Ensure`
-- runs on PlayerAdded before anything else -- so the only case this covers is a client that
-- got here first.
-- Returns a table rather than two values, and that is not a style choice: a function whose
-- failure case is "no stage" cannot return `(BasePart, BasePart)?` in Luau -- there is no
-- optional tuple -- and returning two separate optionals pushes the same nil check onto the
-- caller twice, where it can be half-written.
local function waitForStage(): { mark: BasePart, spot: BasePart }?
	local folder = Workspace:WaitForChild(STAGE_FOLDER, 30)
	if folder == nil then
		warn(`[AGES] lobby: no {STAGE_FOLDER} in Workspace after 30s -- StageService did not start.`)
		return nil
	end
	local stage = folder:WaitForChild(`Stage_{player.UserId}`, 30)
	if stage == nil then
		warn(`[AGES] lobby: no stage was built for {player.Name} after 30s.`)
		return nil
	end
	local mark = stage:WaitForChild(MARK_NAME, 10)
	local spot = stage:WaitForChild(CAMERA_NAME, 10)
	if mark == nil or spot == nil or not mark:IsA("BasePart") or not spot:IsA("BasePart") then
		warn("[AGES] lobby: the stage is missing its Mark or CameraSpot.")
		return nil
	end
	return { mark = mark, spot = spot }
end

-- Waits rather than reading it once. `Workspace.CurrentCamera` is normally there before a
-- LocalScript runs, but "normally" is doing real work in that sentence and the failure is a
-- black screen with no message in it.
local function waitForCamera(): Camera?
	local deadline = os.clock() + 10
	while Workspace.CurrentCamera == nil and os.clock() < deadline do
		task.wait()
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		warn("[AGES] lobby: Workspace.CurrentCamera never appeared -- the lobby shot cannot be set.")
	end
	return camera
end

function StageCamera.Start()
	task.spawn(function()
		local found = waitForStage()
		if found == nil then
			return
		end
		local mark, spot = found.mark, found.spot

		local camera = waitForCamera()
		if camera == nil then
			return
		end

		-- Scriptable *before* the first CFrame write, or the default Custom camera overwrites
		-- it on the same frame and the shot flickers to the character's head on join.
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CameraSubject = nil
		camera.CFrame = spot.CFrame

		local settings = Config.Lobby.Stage
		local base = spot.CFrame
		local pivot = mark.Position
		local elapsed = 0

		-- RenderStepped rather than Heartbeat: a camera written on Heartbeat is a camera one
		-- frame stale every frame, which on a slow drift reads as a faint stutter rather than
		-- as lag -- the hardest kind of wrong to diagnose later.
		RunService.RenderStepped:Connect(function(delta)
			if camera.CameraType ~= Enum.CameraType.Scriptable then
				-- Something else took the camera (a respawn will). Take it straight back
				-- rather than fighting it every frame with a CFrame write it is ignoring.
				camera.CameraType = Enum.CameraType.Scriptable
				camera.CameraSubject = nil
			end

			elapsed += delta
			if settings.DriftSeconds <= 0 or settings.DriftDegrees <= 0 then
				camera.CFrame = base
				return
			end

			-- A sine rather than a sawtooth, so the drift eases at each end instead of
			-- snapping back at the turn. One `DriftSeconds` is a full there-and-back.
			local phase = math.sin((elapsed / settings.DriftSeconds) * math.pi * 2)
			local angle = math.rad(settings.DriftDegrees) * phase
			-- Orbited about the mark rather than rotated in place, so the avatar stays in the
			-- middle of the frame. A camera turned on its own axis would swing the character
			-- across the screen and out from behind the menu.
			local orbit = CFrame.new(pivot) * CFrame.Angles(0, angle, 0) * CFrame.new(-pivot)
			camera.CFrame = orbit * base
		end)
	end)
end

return StageCamera
