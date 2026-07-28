--!strict
-- Studio-only test harness. Reaching an edge case in the aging system takes
-- real minutes of play, so this exposes chat commands that jump straight to
-- one. It bails out unless RunService:IsStudio(), so a live server never
-- registers the listener and there is nothing for a real player to reach.
--
-- Commands accept either prefix, e.g. "/ageup 5" or "!ageup 5". The "!" form
-- is a fallback for setups where the chat system swallows unknown "/" commands.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local DataService = require(script.Parent.DataService)
local StatService = require(script.Parent.StatService)
local LifeService = require(script.Parent.LifeService)
local EventService = require(script.Parent.EventService)
local LifeEvents = require(script.Parent.Parent.content.LifeEvents)

type StatName = Types.StatName

local PREFIXES = { "/", "!" }
local MAX_AGE_UPS_PER_COMMAND = 200

local VALID_STATS: { [string]: boolean } = {
	health = true,
	happiness = true,
	smarts = true,
	looks = true,
}

local Commands: { [string]: (Player, { string }) -> string } = {}

-- Drives the real age-up path rather than writing ageMonths directly, so a
-- forced jump still runs yearly decay, stage transitions and mortality rolls.
-- If a roll kills the player mid-loop the remaining iterations no-op.
Commands.ageup = function(player: Player, args: { string }): string
	local requested = tonumber(args[1]) or 1
	local count = math.clamp(math.floor(requested), 1, MAX_AGE_UPS_PER_COMMAND)
	for _ = 1, count do
		LifeService.AgeUp(player, "Manual")
	end
	return `aged up {count}x -> age {LifeService.GetAgeYears(player)}`
end

Commands.age = function(player: Player, args: { string }): string
	local target = tonumber(args[1])
	if target == nil then
		return "usage: /age <years>"
	end
	local current = LifeService.GetAgeYears(player)
	if current == nil then
		return "no profile loaded yet"
	end
	if target <= current then
		return `already age {current}; /age only moves forward (use /die to restart)`
	end
	return Commands.ageup(player, { tostring(target - current) })
end

Commands.die = function(player: Player, _args: { string }): string
	LifeService.Die(player)
	return "forced death"
end

Commands.stat = function(player: Player, args: { string }): string
	local name = string.lower(args[1] or "")
	local value = tonumber(args[2])
	if not VALID_STATS[name] or value == nil then
		return "usage: /stat <health|happiness|smarts|looks> <0-100>"
	end
	StatService.SetStat(player, name :: StatName, value)
	return `{name} -> {value}`
end

-- Fast-forwards the automatic age-up timer so the safety net can be tested
-- without editing Config.AutoAgeUpGameHours and restarting.
Commands.bank = function(player: Player, args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end
	local seconds = tonumber(args[1])
	if seconds == nil then
		return "usage: /bank <seconds>"
	end
	profile.Data.secondsSinceAgeUp += seconds
	return `banked {seconds}s -> {string.format("%.1f", profile.Data.secondsSinceAgeUp)}s toward auto age-up`
end

-- Forces a specific event on screen without waiting for its age band to come
-- round, which is the only practical way to proof-read a new content entry.
Commands.event = function(player: Player, args: { string }): string
	local eventId = args[1]
	if eventId == nil then
		return "usage: /event <id> (see /events)"
	end
	if not EventService.ForceOffer(player, eventId) then
		return `no event with id "{eventId}"`
	end
	return `offered "{eventId}"`
end

-- Lists what is eligible right now, which is usually the question being asked
-- when an expected event doesn't fire.
Commands.events = function(player: Player, _args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end

	local ageYears = profile.Data.ageMonths // Config.Time.MonthsPerYear
	local eligible: { string } = {}
	local seenCount = 0

	for _, event in LifeEvents.All do
		if profile.Data.seenEventIds[event.id] then
			seenCount += 1
		elseif ageYears >= event.minAge and ageYears <= event.maxAge then
			table.insert(eligible, event.id)
		end
	end

	if #eligible == 0 then
		return `age {ageYears}: nothing eligible ({seenCount} seen, {#LifeEvents.All} total)`
	end
	return `age {ageYears}: {table.concat(eligible, ", ")} ({seenCount} seen)`
end

-- Clears the per-life seen list so the same content can be replayed without
-- dying first.
Commands.reevents = function(player: Player, _args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end
	EventService.ResetSeen(player)
	return "cleared seen events for this life"
end

Commands.life = function(player: Player, _args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end
	local data = profile.Data
	return string.format(
		"age=%d stage=%s alive=%s banked=%.1fs lives=%d pending=%s",
		data.ageMonths // Config.Time.MonthsPerYear,
		data.stage,
		tostring(data.alive),
		data.secondsSinceAgeUp,
		data.livesLived,
		data.pendingEventId or "none"
	)
end

local HELP_TEXT =
	"commands: /ageup [n], /age <years>, /die, /stat <name> <value>, /bank <seconds>, /life, /event <id>, /events, /reevents"

Commands.help = function(_player: Player, _args: { string }): string
	return HELP_TEXT
end

local function stripPrefix(message: string): string?
	for _, prefix in PREFIXES do
		if string.sub(message, 1, #prefix) == prefix then
			return string.sub(message, #prefix + 1)
		end
	end
	return nil
end

local function onChatted(player: Player, message: string)
	local body = stripPrefix(message)
	if body == nil then
		return
	end

	local parts = string.split(body, " ")
	local name = string.lower(table.remove(parts, 1) or "")
	local handler = Commands[name]
	if handler == nil then
		-- Not one of ours (could be a built-in like /e). Stay silent.
		return
	end

	local ok, result = pcall(handler, player, parts)
	if ok then
		print(`[AGES debug] {player.Name}: {result}`)
	else
		warn(`[AGES debug] /{name} failed: {result}`)
	end
end

local DebugService = {}

function DebugService:Init() end

function DebugService:Start()
	if not RunService:IsStudio() then
		return
	end

	local function watch(player: Player)
		player.Chatted:Connect(function(message: string)
			onChatted(player, message)
		end)
	end

	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	print(`[AGES debug] Studio commands active — {HELP_TEXT}`)
end

return DebugService
