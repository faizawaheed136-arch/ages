--!strict
-- Merges the event content modules into one table and validates them at server
-- start. A content mistake is an authoring bug, not a runtime condition, so
-- these throw immediately and loudly rather than quietly dropping an entry that
-- would then never fire and never be missed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Delivery = require(ReplicatedStorage:WaitForChild("Delivery"))

local Cast = require(script.Parent.Cast)

type LifeEvent = Types.LifeEvent

local SOURCES: { { LifeEvent } } = {
	require(script.Childhood),
	require(script.School),
	require(script.Teen),
	require(script.Adult),
	require(script.Ambient),
}

-- One option is not a choice.
local MIN_CHOICES = 2

local all: { LifeEvent } = {}
local byId: { [string]: LifeEvent } = {}

local function validate(event: LifeEvent)
	if byId[event.id] ~= nil then
		error(`[AGES content] duplicate event id "{event.id}"`)
	end
	if event.minAge > event.maxAge then
		error(`[AGES content] event "{event.id}" has minAge above maxAge`)
	end
	if #event.choices < MIN_CHOICES then
		error(`[AGES content] event "{event.id}" needs at least {MIN_CHOICES} choices`)
	end

	-- Casting only means anything for a visitor, so an id on anything else is a
	-- copy-paste that would silently do nothing.
	if event.cast ~= nil then
		if event.delivery ~= "NPCApproach" then
			error(`[AGES content] event "{event.id}" casts "{event.cast}" but is delivered by {event.delivery}`)
		end
		if Cast.ById[event.cast] == nil then
			error(`[AGES content] event "{event.id}" casts "{event.cast}", who is not in the cast`)
		end
	end

	-- An ambient event below this age could never fire, because the scheduler
	-- will not stage one there -- and it must not, since resolving an event at
	-- that age advances the year. Caught here rather than at runtime, where it
	-- would look like an event that simply never came up.
	if Delivery.RouteOf(event.delivery) == "Ambient" and event.minAge < Config.Ambient.MinAge then
		error(
			`[AGES content] ambient event "{event.id}" starts at age {event.minAge}, `
				.. `below Ambient.MinAge ({Config.Ambient.MinAge}); it could never be staged`
		)
	end

	local seenChoiceIds: { [string]: boolean } = {}
	for _, choice in event.choices do
		if seenChoiceIds[choice.id] then
			error(`[AGES content] event "{event.id}" repeats choice id "{choice.id}"`)
		end
		seenChoiceIds[choice.id] = true

		-- Per the design spec: a choice that doesn't move a stat should be cut,
		-- because it gives the player nothing to weigh.
		local movesSomething = false
		for _, delta in choice.effects do
			if delta ~= 0 then
				movesSomething = true
				break
			end
		end
		if not movesSomething then
			error(`[AGES content] choice "{choice.id}" in event "{event.id}" moves no stat`)
		end
	end
end

for _, source in SOURCES do
	for _, event in source do
		validate(event)
		byId[event.id] = event
		table.insert(all, event)
	end
end

local LifeEvents = {
	All = all,
	ById = byId,
}

return LifeEvents
