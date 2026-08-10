--!strict
-- Lobby client bootstrap. Two things: take the camera, and draw the menu.
--
-- The camera goes first and not as a matter of taste. `StageCamera.Start` sets the camera
-- Scriptable before it writes a CFrame, and until it has, Roblox's default camera is
-- following the character — which on a fresh join is falling toward a mark it has not been
-- placed on yet. Starting the UI first would put a menu over a second of that.
--
-- Neither call yields: both spawn their own waiting.

local StageCamera = require(script.StageCamera)
local LobbyUI = require(script.ui.LobbyUI)

StageCamera.Start()
LobbyUI.Start()
