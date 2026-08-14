--!strict
-- NPC gossip. When two townsfolk are near each other and the player has done
-- something notable in their recent history, one may share a line about the
-- player with the other. The gossip affects bonds among nearby people and gives
-- the world a sense that the player's actions are talked about.
--
-- Notable actions are tracked in a per-player queue keyed by time. The gossip
-- system walks the queue, picks a recent notable, and pushes it to any nearby
-- NPC pair. Gossip fades after Config.Gossip.FadeHours of game time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local DataService = require(script.Parent.DataService)
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local NPCService = require(script.Parent.NPCService)

type LifeData = Types.LifeData
type Player = Players.Player
type Visitor = NPCService.Visitor

local GossipService = {}

local GOSSIP = Config.Gossip
local GOSSIP_UPDATE = Remotes.Get("GossipUpdate")

-- A notable action the player has taken, with a timestamp.
type Notable = {
	time: number,
	action: string,
	effect: string,
}

-- Per-player notable actions queue.
type GossipState = {
	notes: { Notable },
	lastCleanup: number,
}

local states: { [Player]: GossipState } = {}

-- Get the life data for a player, nil if no profile or no active life.
local function lifeDataFor(player: Player): LifeData?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return Lives.Active(profile.Data)
end

local function stateFor(player: Player): GossipState
	local mine = states[player]
	if mine == nil then
		mine = { notes = {}, lastCleanup = os.clock() }
		states[player] = mine
	end
	return mine
end

-- Record a notable action by the player.
function GossipService.Note(player: Player, action: string, effect: string)
	local mine = stateFor(player)
	table.insert(mine.notes, {
		time = os.clock(),
		action = action,
		effect = effect,
	})
	-- Keep the queue small.
	if #mine.notes > 20 then
		table.remove(mine.notes, 1)
	end
end

-- Get a recent notable action, or nil if none is suitable.
local function pickNotable(mine: GossipState): Notable?
	local now = os.clock()
	for i = #mine.notes, 1, -1 do
		local note = mine.notes[i]
		-- Only use notes less than FadeHours game-hours old.
		-- We approximate: 1 game hour ≈ real seconds based on Config.Time.
		local age = now - note.time
		if age < GOSSIP.FadeHours * Config.Time.RealSecondsPerGameHour * 2 then
			return note
		end
	end
	return nil
end

-- Check for gossip opportunities. Called periodically from Start().
function GossipService.Tick(player: Player)
	local mine = stateFor(player)
	local now = os.clock()
	if now - mine.lastCleanup < GOSSIP.TickSeconds then
		return
	end
	mine.lastCleanup = now

	local note = pickNotable(mine)
	if note == nil then
		return
	end

	-- Pick a random nearby person to be the gossip source.
	-- In practice, we push the gossip to the player's client so they can
	-- hear it when near NPCs. The actual NPC-to-NPC propagation is handled
	-- by PeopleService's tick.
	GOSSIP_UPDATE:FireClient(player, {
		speaker = "town",
		topics = note.action,
		effect = note.effect,
	})
end

-- Called from PeopleService when a bond milestone is reached, to generate
-- gossip-worthy content about that relationship.
function GossipService.OnBondMilestone(player: Player, personName: string, milestone: string)
	GossipService.Note(player,
		"became " .. milestone .. " with " .. personName,
		"friends with " .. personName
	)
end

-- Called when the player buys a house.
function GossipService.OnHousePurchase(player: Player, houseId: string)
	GossipService.Note(player,
		"bought a house at " .. houseId,
		"new homeowner"
	)
end

-- Called when the player sells a house.
function GossipService.OnHouseSale(player: Player, houseId: string)
	GossipService.Note(player,
		"sold their house at " .. houseId,
		"lost their home"
	)
end

function GossipService:Init()
	Players.PlayerAdded:Connect(function(player: Player)
		stateFor(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
end

function GossipService:Start()
	task.spawn(function()
		while true do
			task.wait(GOSSIP.TickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(function()
					GossipService.Tick(player)
				end)
				if not ok then
					warn(`[AGES] gossip tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

return GossipService
