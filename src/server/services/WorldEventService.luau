--!strict
-- Lets the world start an event. An object in the Studio house is tagged and
-- given an event id, and reaching it offers that event — so a childhood memory
-- becomes somewhere you crawled to rather than a panel that appeared.
--
-- The division of labour is deliberate and one-way: the object says *where* an
-- event may be reached, and EventService alone says *whether* it may fire. An
-- object whose event is the wrong age, already lived, or blocked behind an open
-- prompt is simply inert, and nothing here needs to know which of those it is.
--
-- Server-side proximity, like everything else that changes state: the client is
-- never asked where it is standing.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local EventService = require(script.Parent.EventService)
local LifeEvents = require(script.Parent.Parent.content.LifeEvents)

local WorldEventService = {}

local anchors: { [Instance]: boolean } = {}
-- One complaint per object. A misconfigured anchor is checked every tick, and a
-- warning per tick would bury the log it is trying to draw attention to.
local warned: { [Instance]: boolean } = {}

local function warnOnce(instance: Instance, message: string)
	if warned[instance] then
		return
	end
	warned[instance] = true
	warn(`[AGES] tagged object "{instance:GetFullName()}" {message}`)
end

-- Anchors are usually a single part, but a rug or a crib is just as likely to
-- be a Model, so both are accepted and anything else is called out.
local function anchorPosition(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	warnOnce(instance, `is a {instance.ClassName}, which has no position; it can never be reached`)
	return nil
end

-- Read every tick rather than cached at tag time, so an id corrected in Studio
-- during a play session takes effect without a restart.
local function anchorEventId(instance: Instance): string?
	local raw = instance:GetAttribute(Config.World.InteractEventAttribute)
	if raw == nil then
		warnOnce(instance, `has no "{Config.World.InteractEventAttribute}" attribute, so it offers nothing`)
		return nil
	end
	if typeof(raw) ~= "string" then
		warnOnce(instance, `has a non-string "{Config.World.InteractEventAttribute}" attribute`)
		return nil
	end
	if LifeEvents.ById[raw] == nil then
		warnOnce(instance, `names event "{raw}", which does not exist`)
		return nil
	end
	return raw
end

-- Who a tagged object belongs to, or nil for the hand-placed geometry that
-- belongs to everyone. Public is the default because it is what the house is
-- full of: anyone who crawls to the rug may have the rug's event. Staged
-- deliveries set it, because a letter addressed to one player must not pay out
-- for whoever else wanders past the doormat first.
local function anchorOwner(instance: Instance): number?
	local raw = instance:GetAttribute(Config.World.InteractOwnerAttribute)
	if raw == nil then
		return nil
	end
	if typeof(raw) ~= "number" then
		warnOnce(instance, `has a non-number "{Config.World.InteractOwnerAttribute}" attribute; treating it as public`)
		return nil
	end
	return raw
end

-- DeliveryService injects this so it learns the moment one of its staged
-- objects pays out and can take the object away. Injected rather than required
-- to keep the dependency one-way: DeliveryService already requires this service.
type CollectedHandler = (player: Player, instance: Instance, eventId: string) -> ()
local collectedHandler: CollectedHandler? = nil

function WorldEventService.SetCollectedHandler(handler: CollectedHandler)
	collectedHandler = handler
end

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	-- GetPivot rather than HumanoidRootPart: it is correct for any rig, and a
	-- character mid-spawn may not have its root part yet.
	return character:GetPivot().Position
end

local function tick()
	if next(anchors) == nil then
		return
	end

	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end

	local radius = Config.World.InteractRadius
	for instance in anchors do
		local position = anchorPosition(instance)
		local eventId = if position ~= nil then anchorEventId(instance) else nil
		if position == nil or eventId == nil then
			continue
		end

		local owner = anchorOwner(instance)
		for _, player in players do
			if owner ~= nil and player.UserId ~= owner then
				continue
			end

			local here = characterPosition(player)
			if here ~= nil and (here - position).Magnitude <= radius then
				local offered = EventService.OfferIfEligible(player, eventId)
				-- An owned anchor is single-use by construction: it exists only
				-- because something was staged for this player, and it has now
				-- been reached. Hand it back to whoever staged it and stop
				-- looking -- the instance is about to stop existing. Clearing
				-- the current key mid-traversal is safe; nothing else is.
				if offered and owner ~= nil then
					if collectedHandler ~= nil then
						collectedHandler(player, instance, eventId)
					end
					break
				end
			end
		end
	end
end

local function addAnchor(instance: Instance)
	anchors[instance] = true
end

local function removeAnchor(instance: Instance)
	anchors[instance] = nil
	warned[instance] = nil
end

function WorldEventService:Init() end

function WorldEventService:Start()
	local tag = Config.World.InteractTag
	CollectionService:GetInstanceAddedSignal(tag):Connect(addAnchor)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(removeAnchor)
	for _, instance in CollectionService:GetTagged(tag) do
		addAnchor(instance)
	end

	task.spawn(function()
		while true do
			task.wait(Config.World.InteractTickSeconds)
			tick()
		end
	end)
end

return WorldEventService
