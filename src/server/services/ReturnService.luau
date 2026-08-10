--!strict
-- The way out. The game place's half of the handshake `LobbyService.Play` starts.
--
-- **This file is what replaced being reborn where you stood.** Until part 3, dying wound the
-- same body back to age zero, cleared the setup and drew the character menu over the town --
-- so a player had exactly one life at a time and no way to look at it once it was over. Now
-- a life ends in the slot it was lived in and stays there, and the player comes back here to
-- pick a card: the one the dead person is in, to read them and delete them, or another one.
--
-- The trip is the same three steps as Play, in the same order and for the same reason (see
-- LobbyService's header): the profile is written, the player leaves, ProfileStore's session
-- ends and does its final save, and the *lobby* then opens a key nobody is holding. Nothing
-- travels in TeleportData. There is nothing to put in it -- the lobby reads the save.
--
-- The one thing this file does that Play does not: it is also the arrival check. A player
-- who lands in the game place on a slot with no life in it, or with a dead one, is a player
-- who got here by a route the lobby would not have offered -- joining the place id directly,
-- or dying and rejoining before the teleport landed. There is no menu here to show them any
-- more, so the only honest answer is to send them back to the one that exists.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local DataService = require(script.Parent.DataService)

local RequestReturnToLobbyRemote = Remotes.Get("RequestReturnToLobby")
local ReturnRefusedRemote = Remotes.Get("ReturnRefused")

local ReturnService = {}

-- Who has a teleport in the air, and since when. A timestamp rather than a boolean, for the
-- reason spelled out on the lobby's copy of this table: a boolean cleared only on success or
-- on a caught failure stays true forever the one time neither happens, and the player is then
-- looking at a death screen whose only button will never work again.
local inFlight: { [Player]: number } = {}

local function refuse(player: Player, reason: string)
	ReturnRefusedRemote:FireClient(player, reason)
end

-- Why the trip cannot be made, in a sentence, or nil.
--
-- Both refusals here are developer-facing and neither is hidden. A player will never see
-- either in a published build, and the developer who does see one has been handed the fix in
-- the same line rather than a teleport that quietly does nothing.
local function blockedBecause(player: Player): string?
	local since = inFlight[player]
	if since ~= nil and os.clock() - since < Config.Lobby.TeleportTimeoutSeconds then
		return "Already heading back -- hold on."
	end
	if RunService:IsStudio() then
		return "Teleporting does not work in Studio, so there is no way back to the menu from "
			.. "here. Publish both places and test in-game."
	end
	if Config.Lobby.LobbyPlaceId == 0 then
		return "This build has no lobby place id yet. Publish the lobby as the start place and "
			.. "set Config.Lobby.LobbyPlaceId to its id."
	end
	return nil
end

-- Retried rather than reported on the first failure, because the common failures here pass on
-- their own. Only the last one is ever shown, and it is always shown.
local function teleport(player: Player): (boolean, string?)
	local lastError: string? = nil
	for attempt = 1, Config.Lobby.TeleportRetries + 1 do
		if player.Parent ~= Players then
			-- They left while we were retrying, which is the outcome this function was trying
			-- to arrange anyway. Not an error, and firing a refusal at somebody who has gone is
			-- a warning in the log for nothing.
			return false, nil
		end
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(Config.Lobby.LobbyPlaceId, { player })
		end)
		if ok then
			return true, nil
		end
		lastError = tostring(err)
		if attempt <= Config.Lobby.TeleportRetries then
			task.wait(Config.Lobby.TeleportRetrySeconds)
		end
	end
	return false, lastError
end

-- Send the player back to the menu.
--
-- Public because three completely different things need it and all three mean the same thing:
-- the death screen's button, a player choosing to switch lives mid-run, and the arrival check
-- below finding nothing here to play. Safe to call twice -- the in-flight stamp makes the
-- second call a refusal rather than a second teleport.
function ReturnService.Send(player: Player)
	local blocked = blockedBecause(player)
	if blocked ~= nil then
		refuse(player, blocked)
		return
	end

	inFlight[player] = os.clock()
	local ok, err = teleport(player)
	if ok then
		return
	end
	inFlight[player] = nil
	if err ~= nil then
		warn(`[AGES] return: teleport to the lobby failed for {player.Name} after {Config.Lobby.TeleportRetries + 1} tries -- {err}`)
		refuse(player, "Could not get back to the menu -- Roblox refused the teleport. Try again in a moment.")
	end
end

-- Is there anything in this place for this player to do?
--
-- Deliberately not "is the life alive": an *unbegun* slot is the more likely of the two, and
-- it is the more dangerous. Every clock in this game checks `Lives.HasBegun` before it moves,
-- so a player standing in a slot with no setup in it is standing in a world that will never
-- start -- and before part 3 that was fine, because the menu was drawn over it. It is not
-- drawn over it any more.
local function onPlayerAdded(player: Player)
	task.spawn(function()
		local profile = DataService.WaitForProfile(player)
		if profile == nil or player.Parent ~= Players then
			return
		end
		local life = Lives.Active(profile.Data)
		if Lives.HasBegun(life) and life.alive then
			return
		end
		-- In Studio the player needs a moment to type /setup skip before we send them
		-- back. Delaying here is not a workaround -- it is the honest shape of the
		-- system: we know the teleport will refuse, so we let the player reach for the
		-- harness that puts a life into the slot they are standing in, and only send
		-- them on if they do not.
		if RunService:IsStudio() then
			task.wait(3)
			-- Re-read after the pause: a /setup skip in those three seconds has done
			-- its job and the life is begun. Nothing to refuse here.
			life = Lives.Active(profile.Data)
			if Lives.HasBegun(life) and life.alive then
				return
			end
			warn(
				`[AGES] return: {player.Name} still has no life after the Studio grace `
					.. `period -- sending them to /setup skip instructions`
			)
			refuse(player, "No life begun. Type /setup skip in chat to start one, then rejoin.")
			return
		end
		warn(
			`[AGES] return: {player.Name} arrived on slot {profile.Data.activeSlot} with no life to play `
				.. `(begun={Lives.HasBegun(life)}, alive={life.alive}); sending them back to the lobby`
		)
		ReturnService.Send(player)
	end)
end

function ReturnService:Init()
	RequestReturnToLobbyRemote.OnServerEvent:Connect(function(player: Player)
		ReturnService.Send(player)
	end)

	-- A teleport can fail *after* TeleportAsync returned successfully, and this is the only
	-- place that hears about it. Without it the player sits on a death screen whose button has
	-- already been pressed, refusing to work for TeleportTimeoutSeconds, saying nothing.
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		inFlight[player] = nil
		warn(`[AGES] return: teleport init failed for {player.Name} -- {result.Name}: {message}`)
		refuse(player, "Could not get back to the menu -- the teleport was rejected. Try again in a moment.")
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		inFlight[player] = nil
	end)
end

function ReturnService:Start()
	-- Connected in Start rather than Init so that a player arriving in the first moments of a
	-- server is checked by a service that is fully up, and -- more to the point -- so that the
	-- loop below cannot fire before DataService is ready to be waited on.
	Players.PlayerAdded:Connect(onPlayerAdded)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return ReturnService
