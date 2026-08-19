--!strict
-- Preferences: what the player has turned on and off, and nothing about what those
-- switches do.
--
-- **Why the server owns a screen full of client-side switches.** Every option in
-- `Config.Settings.Options` is acted on by the client -- hiding a dial, suppressing a
-- popup, putting a confirm in front of a button. None of it needs a server. What needs a
-- server is that it survives a rejoin, and the only thing in this game that survives a
-- rejoin is the profile. Once the profile is the store, the client holding its own copy
-- buys nothing and costs a whole class of bug: a switch that looks flipped, quietly fails
-- to save, and comes back the other way an hour later with nothing in between to blame it
-- on. So the client draws only what it was pushed, never what it clicked, and this file is
-- the only writer.
--
-- **What is deliberately not here.** No effects. This service does not know that
-- `minimap` hides a dial, and it must not learn: the day it does, half of every option's
-- behaviour lives here and half lives in the client, and a switch that half-works becomes
-- something you debug in two files. It validates ids, stores booleans and pushes.
--
-- The save is sparse: only options the player has actually moved are written, and an
-- absent key means "still whatever Config says". That is what keeps a default changeable
-- later -- see the comment on `ProfileData.settings`.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local DataService = require(script.Parent.DataService)

type Player = Players.Player
type SettingState = Types.SettingState

local SettingsService = {}

local OPTIONS = Config.Settings.Options
local SETTINGS_UPDATED = Remotes.Get("SettingsUpdated")
local REQUEST_SET_SETTING = Remotes.Get("RequestSetSetting")

-- Built once from Config, for the same reason `SkillService` builds its own: a write
-- against a name nobody defined has to be caught by a lookup, not by silently growing a
-- key in a save file that nothing will ever draw or clean up.
local DEFINED: { [string]: typeof(OPTIONS[1]) } = {}
for _, option in OPTIONS do
	if DEFINED[option.id] ~= nil then
		error(`Config.Settings.Options: two options share the id "{option.id}". Ids key the save and must be unique.`)
	end
	DEFINED[option.id] = option
end

local function settingsTable(player: Player): { [string]: boolean }?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return profile.Data.settings
end

-- Read one option for this player, falling through to the Config default.
--
-- Public because the server side of an option is allowed to exist -- nothing today needs
-- it, but the first option that gates something server-side should ask here rather than
-- reaching into the profile, so that "what does absent mean" has exactly one answer.
function SettingsService.IsOn(player: Player, id: string): boolean
	local option = DEFINED[id]
	if option == nil then
		error(`SettingsService.IsOn: no setting "{id}". Add it to Config.Settings.Options or fix the id at the call site.`)
	end
	local settings = settingsTable(player)
	if settings == nil then
		return option.default
	end
	local stored = settings[id]
	if stored == nil then
		return option.default
	end
	return stored
end

-- Every option in Config order, with the caption that matches the state it is in.
--
-- Iterated over Config rather than over the save, which is the same rule the skills pane
-- follows and for a sharper reason here: the save is sparse, so a pane built from it would
-- list only the options the player had already found.
local function stateFor(player: Player): { SettingState }
	local settings = settingsTable(player)
	local states: { SettingState } = {}
	for _, option in OPTIONS do
		local on = option.default
		if settings ~= nil and settings[option.id] ~= nil then
			on = settings[option.id]
		end
		table.insert(states, {
			id = option.id,
			label = option.label,
			caption = if on then option.captionOn else option.captionOff,
			on = on,
		})
	end
	return states
end

-- Send the whole pane. Whole rather than one row, because the alternative is a client that
-- has to merge pushes, and four booleans are not worth a merge.
function SettingsService.Push(player: Player)
	if DataService.GetProfile(player) == nil then
		return
	end
	SETTINGS_UPDATED:FireClient(player, { settings = stateFor(player) } :: Types.SettingsState)
end

local function set(player: Player, id: string, on: boolean)
	local option = DEFINED[id]
	if option == nil then
		-- Refused rather than raised. This arrives from a client, and an unknown id here is
		-- either a stale build or somebody poking the remote -- neither of which is a reason
		-- to error out of a remote handler, and both of which are worth seeing in the log.
		warn(`SettingsService: refused an unknown setting id "{id}" from {player.Name}.`)
		return
	end

	local settings = settingsTable(player)
	if settings == nil then
		return
	end

	-- Stored even when it matches the default, and this is on purpose. Writing only
	-- non-default values would keep the save smaller and would silently move a player back
	-- onto a default that changed under them after they had explicitly chosen it. Once a
	-- player has touched a switch, that choice is theirs and outlives our opinion of it.
	settings[id] = on
	SettingsService.Push(player)
end

function SettingsService:Init()
	REQUEST_SET_SETTING.OnServerEvent:Connect(function(player: Player, id: unknown, on: unknown)
		if type(id) ~= "string" or type(on) ~= "boolean" then
			return
		end
		set(player, id, on)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		SettingsService.Push(player)
	end)
end

function SettingsService:Start()
	-- Nothing to run. Settings change when a player changes one, and never otherwise.
end

-- Every option on one line, for `/setting`. Reads the same `stateFor` the client is pushed,
-- so a row that draws wrong and a line that prints wrong are guaranteed to be one bug.
function SettingsService.Describe(player: Player): string
	local lines: { string } = {}
	for _, state in stateFor(player) do
		table.insert(lines, `{state.id}={if state.on then "on" else "off"}`)
	end
	return table.concat(lines, ", ")
end

-- Flip one from a debug command. Separate from the remote handler so that `/setting` tests
-- the same write path a click does, without inventing a second one that could drift.
function SettingsService.Force(player: Player, id: string, on: boolean): boolean
	if DEFINED[id] == nil then
		return false
	end
	set(player, id, on)
	return true
end

return SettingsService
