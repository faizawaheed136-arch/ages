--!strict
-- The event engine. It decides *which* life event fires and validates the
-- answer; it deliberately does not decide *how* the event reaches the player.
-- That belongs to the delivery layer on the client, keyed off the event's
-- `delivery` field, so the world-based presentations arriving with step 3 are a
-- new client handler rather than a change to anything in here.
--
-- One event may be outstanding at a time. It is stored in the profile, which
-- means an unanswered prompt survives a rejoin and, just as importantly, that
-- rejoining cannot be used to reroll one the player doesn't like.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local DataService = require(script.Parent.DataService)
local StatService = require(script.Parent.StatService)
local LifeEvents = require(script.Parent.Parent.content.LifeEvents)

type LifeEvent = Types.LifeEvent
type EventChoice = Types.EventChoice
type StatName = Types.StatName
type OfferedEvent = Types.OfferedEvent
type ProfileData = Types.ProfileData

local EventOfferedRemote = Remotes.Get("EventOffered")
local EventResolvedRemote = Remotes.Get("EventResolved")
local RequestEventChoiceRemote = Remotes.Get("RequestEventChoice")

local EventService = {}

-- Outcome lines and stat effects are withheld until a choice is made, so the
-- best answer can't be read straight off the payload.
local function toOffered(event: LifeEvent): OfferedEvent
	local choices: { { id: string, label: string } } = {}
	for _, choice in event.choices do
		table.insert(choices, { id = choice.id, label = choice.label })
	end
	return {
		id = event.id,
		delivery = event.delivery,
		prompt = event.prompt,
		choices = choices,
	}
end

local function pickForAge(data: ProfileData, ageYears: number): LifeEvent?
	local candidates: { LifeEvent } = {}
	local weights: { number } = {}
	local totalWeight = 0

	for _, event in LifeEvents.All do
		if ageYears >= event.minAge and ageYears <= event.maxAge and not data.seenEventIds[event.id] then
			local weight = event.weight or 1
			table.insert(candidates, event)
			table.insert(weights, weight)
			totalWeight += weight
		end
	end

	-- Every eligible event has already been seen this life. Running dry is a
	-- content gap, not an error: the year simply passes without one.
	if totalWeight <= 0 then
		return nil
	end

	local roll = math.random() * totalWeight
	for index, event in candidates do
		roll -= weights[index]
		if roll <= 0 then
			return event
		end
	end
	return candidates[#candidates]
end

local function offer(player: Player, data: ProfileData, event: LifeEvent)
	data.pendingEventId = event.id
	EventOfferedRemote:FireClient(player, toOffered(event))
end

-- Called by LifeService once a birthday has finished resolving.
function EventService.OfferForAge(player: Player, ageYears: number)
	local profile = DataService.GetProfile(player)
	if profile == nil or not profile.Data.alive then
		return
	end

	local data = profile.Data
	-- An unanswered prompt still stands. Stacking a second one on top would let
	-- the first quietly disappear along with the choice it was asking for.
	if data.pendingEventId ~= nil then
		return
	end

	local event = pickForAge(data, ageYears)
	if event ~= nil then
		offer(player, data, event)
	end
end

-- Public so the Studio harness can force a specific event without rolling for
-- it. Returns false when the id doesn't exist so the caller can say so.
function EventService.ForceOffer(player: Player, eventId: string): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	local event = LifeEvents.ById[eventId]
	if event == nil then
		return false
	end
	offer(player, profile.Data, event)
	return true
end

function EventService.ClearPending(player: Player)
	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		profile.Data.pendingEventId = nil
	end
end

-- A new life may live the same moments again, so the seen list is per-life.
function EventService.ResetSeen(player: Player)
	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		profile.Data.seenEventIds = {}
		profile.Data.pendingEventId = nil
	end
end

local function findChoice(event: LifeEvent, choiceId: string): EventChoice?
	for _, choice in event.choices do
		if choice.id == choiceId then
			return choice
		end
	end
	return nil
end

-- Both arguments arrive from the client and are therefore untrusted, including
-- their types. The only answer accepted is one belonging to the exact event
-- this player was offered.
local function onChoiceRequested(player: Player, eventId: any, choiceId: any)
	if typeof(eventId) ~= "string" or typeof(choiceId) ~= "string" then
		return
	end

	local profile = DataService.GetProfile(player)
	if profile == nil or not profile.Data.alive then
		return
	end

	local data = profile.Data
	if data.pendingEventId == nil or data.pendingEventId ~= eventId then
		-- Already answered, never offered, or forged. A duplicate press lands
		-- here too, which is what stops one prompt paying out twice.
		return
	end

	local event = LifeEvents.ById[eventId]
	if event == nil then
		-- The pending id survived in a profile but the content is gone.
		warn(`[AGES] pending event "{eventId}" no longer exists; dropping it`)
		data.pendingEventId = nil
		return
	end

	local choice = findChoice(event, choiceId)
	if choice == nil then
		return
	end

	-- Consumed before any stat is written, so a retry arriving behind this one
	-- fails the pending check above rather than applying the effects twice.
	data.pendingEventId = nil
	data.seenEventIds[event.id] = true

	-- Iterating a keyed table widens the key back to string, so the cast puts
	-- back what StatDelta already guarantees.
	for statName, delta in choice.effects do
		StatService.AddStat(player, statName :: StatName, delta)
	end

	-- No death check here on purpose. LifeService already tests health every
	-- tick, so a choice that empties it is lethal within the second without
	-- this service needing to reach into the life cycle.
	EventResolvedRemote:FireClient(player, event.id, choice.outcome)
end

-- Re-offers whatever was left unanswered when the player last left.
local function pushPending(player: Player)
	local profile = DataService.WaitForProfile(player)
	if profile == nil then
		return
	end

	local data = profile.Data
	local pendingId = data.pendingEventId
	if pendingId == nil or not data.alive then
		return
	end

	local event = LifeEvents.ById[pendingId]
	if event == nil then
		warn(`[AGES] pending event "{pendingId}" no longer exists; dropping it`)
		data.pendingEventId = nil
		return
	end

	EventOfferedRemote:FireClient(player, toOffered(event))
end

function EventService:Init()
	RequestEventChoiceRemote.OnServerEvent:Connect(onChoiceRequested)
end

function EventService:Start()
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(pushPending, player)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(pushPending, player)
	end
end

return EventService
