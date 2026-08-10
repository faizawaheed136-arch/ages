--!strict
-- The world coming to you. Decides when something arrives, puts it in the house,
-- and takes it away again when it is collected or gives up waiting.
--
-- The division of labour continues the one WorldEventService already set out.
-- EventService alone says *whether* an event may fire; this says *when* one is
-- staged and *where* it sits; DeliveryPresenters says what it looks like; and
-- WorldEventService, unchanged in principle, notices the player reaching it. No
-- part of that chain needs to know what the others chose.
--
-- Delivery is two-phase, and the two phases are two different profile fields:
--
--   deliveringEventId  picked and physically present, not yet reached
--   pendingEventId     reached, prompt open, waiting on an answer
--
-- Keeping them separate is what makes "a prompt is open while the letter is
-- still on the mat" unrepresentable rather than merely unlikely. The first is
-- persisted for the same reason as the second: leaving and rejoining must not be
-- a way to reroll what the world brought you, and a letter that vanished with
-- the session that delivered it would be exactly that.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Delivery = require(ReplicatedStorage:WaitForChild("Delivery"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local WorldEventService = require(script.Parent.WorldEventService)
local LifeEvents = require(script.Parent.Parent.content.LifeEvents)
local DeliveryPresenters = require(script.Parent.Parent.world.DeliveryPresenters)

type LifeEvent = Types.LifeEvent
type LifeData = Types.LifeData
type EventDelivery = Types.EventDelivery
type DeliveryPresentation = Types.DeliveryPresentation

local DeliveryService = {}

type Staged = {
	eventId: string,
	delivery: EventDelivery,
	presentation: DeliveryPresentation,
	-- os.clock() deadline, or nil for the modes that never time out. Held in
	-- memory rather than in the profile on purpose: a phone that rang while the
	-- player was logged out for a week has not been ringing all week, so a
	-- restored delivery starts its clock again from the moment they walk back in.
	expiresAt: number?,
}

local staged: { [Player]: Staged } = {}

-- Set while a presenter is being built. Building a visitor is a web-backed call
-- that yields, and without this a tick landing inside that yield would start a
-- second one. deliveringEventId guards the same thing in the profile, but only
-- once it has been written, and the write happens before the yield precisely so
-- that both guards close the same window from both sides.
local building: { [Player]: boolean } = {}

-- Every instance tagged as somewhere a delivery can appear. Attributes are read
-- at use rather than cached at tag time, matching WorldEventService: a mode
-- corrected in Studio mid-session then takes effect without a restart.
local deliveryPoints: { [BasePart]: boolean } = {}

local warnedModes: { [string]: boolean } = {}
local warnedPoints: { [Instance]: boolean } = {}

-- Debug switch for the Studio harness. Never touched in a live server.
local enabled = true

local function warnPointOnce(instance: Instance, message: string)
	if warnedPoints[instance] then
		return
	end
	warnedPoints[instance] = true
	warn(`[AGES] delivery point "{instance:GetFullName()}" {message}`)
end

-- Which mode a point serves, or nil if it is misconfigured. A point that names a
-- mode with no presenter is called out rather than ignored, because an unreached
-- delivery point looks exactly like a working one that nothing has needed yet.
local function pointMode(point: BasePart): EventDelivery?
	local raw = point:GetAttribute(Config.World.DeliveryPointAttribute)
	if raw == nil then
		warnPointOnce(point, `has no "{Config.World.DeliveryPointAttribute}" attribute, so nothing can appear at it`)
		return nil
	end
	if typeof(raw) ~= "string" then
		warnPointOnce(point, `has a non-string "{Config.World.DeliveryPointAttribute}" attribute`)
		return nil
	end
	if DeliveryPresenters.For(raw :: EventDelivery) == nil then
		warnPointOnce(point, `serves mode "{raw}", which nothing knows how to present`)
		return nil
	end
	return raw :: EventDelivery
end

local function pointsFor(delivery: EventDelivery): { BasePart }
	local matches: { BasePart } = {}
	for point in deliveryPoints do
		if point.Parent ~= nil and pointMode(point) == delivery then
			table.insert(matches, point)
		end
	end
	return matches
end

-- Nil when the house has nowhere to put this. Warned once per mode rather than
-- once per attempt: a missing doormat is a build problem that would otherwise
-- reprint every few minutes forever and bury everything else in the log.
local function choosePoint(delivery: EventDelivery): BasePart?
	local matches = pointsFor(delivery)
	if #matches == 0 then
		if not warnedModes[delivery] then
			warnedModes[delivery] = true
			warn(
				`[AGES] no delivery point tagged "{Config.World.DeliveryPointTag}" serves "{delivery}"; `
					.. `those events cannot be staged until one exists`
			)
		end
		return nil
	end
	return matches[math.random(#matches)]
end

local function canPresent(event: LifeEvent): boolean
	return DeliveryPresenters.For(event.delivery) ~= nil and #pointsFor(event.delivery) > 0
end

local function nextGap(): number
	local low = Config.Ambient.MinSecondsBetween
	local high = Config.Ambient.MaxSecondsBetween
	return low + math.random() * (high - low)
end

local function expiryFor(delivery: EventDelivery): number?
	local seconds = (Config.Ambient.ExpirySeconds :: any)[delivery]
	-- 0 means "waits indefinitely" -- a letter on the mat is patient, and gets
	-- cleared at the next birthday along with the year it belonged to.
	if seconds == nil or seconds <= 0 then
		return nil
	end
	return os.clock() + seconds
end

local function tagAnchor(anchor: BasePart, player: Player, eventId: string)
	anchor:SetAttribute(Config.World.InteractEventAttribute, eventId)
	-- Owned, so the letter on the mat pays out for the player it was addressed
	-- to and nobody else. Set before the tag, because the tag is what makes
	-- WorldEventService start looking at it.
	anchor:SetAttribute(Config.World.InteractOwnerAttribute, player.UserId)
	CollectionService:AddTag(anchor, Config.World.InteractTag)
end

local function untagAnchor(anchor: BasePart)
	-- Untagged before dismissal rather than after, because a visitor keeps
	-- existing while they walk back out and a still-tagged anchor could pay out
	-- a second time on the way to the door.
	CollectionService:RemoveTag(anchor, Config.World.InteractTag)
	anchor:SetAttribute(Config.World.InteractOwnerAttribute, nil)
	anchor:SetAttribute(Config.World.InteractEventAttribute, nil)
end

-- Ends whatever is staged. `collected` tells the presentation how to bow out.
-- `clearProfile` is false in exactly one case -- the player leaving -- where the
-- object has to come out of the world because there is nobody to collect it, but
-- deliveringEventId must survive so the letter is on the mat when they return.
local function finish(player: Player, collected: boolean, clearProfile: boolean)
	local current = staged[player]
	if current == nil then
		return
	end
	staged[player] = nil

	untagAnchor(current.presentation.anchor)
	current.presentation.dismiss(collected)

	if not clearProfile then
		return
	end

	local profile = DataService.GetProfile(player)
	if profile ~= nil and Lives.Active(profile.Data).deliveringEventId == current.eventId then
		-- Only when it is still *this* event. On collection EventService has
		-- already cleared it while opening the prompt, and a new life may have
		-- staged something else entirely; either way this must not clobber it.
		--
		-- The event is deliberately not marked seen. Expiry is silent and it
		-- returns to the pool, because missing a phone call should feel like
		-- missing a phone call rather than like losing something.
		Lives.Active(profile.Data).deliveringEventId = nil
	end
end

-- Builds and installs the world object for an event that the profile already
-- says is being delivered. Returns whether anything ended up in the room.
-- Shared by first staging and by rebuilding after a rejoin, so the two can never
-- put a different thing on the mat.
local function present(player: Player, event: LifeEvent): boolean
	local point = choosePoint(event.delivery)
	if point == nil then
		return false
	end

	local presenter = DeliveryPresenters.For(event.delivery)
	if presenter == nil then
		return false
	end

	-- May yield: a visitor is an avatar built from a web-backed description.
	local presentation = presenter(player, point, event)
	if presentation == nil then
		return false
	end

	-- Everything below re-checks the world as it is *now*, because the yield
	-- above is long enough for the player to have died, left, been handed
	-- something else, or started a whole new life.
	local profile = DataService.GetProfile(player)
	local stillWanted = profile ~= nil
		and Lives.Active(profile.Data).alive
		and Lives.Active(profile.Data).deliveringEventId == event.id
		and Lives.Active(profile.Data).pendingEventId == nil
		and player.Parent == Players

	if not stillWanted then
		presentation.dismiss(false)
		return false
	end

	tagAnchor(presentation.anchor, player, event.id)
	staged[player] = {
		eventId = event.id,
		delivery = event.delivery,
		presentation = presentation,
		expiresAt = expiryFor(event.delivery),
	}
	return true
end

-- Picks something, claims it in the profile, then builds it. The claim happens
-- before the build because the build yields: a second attempt arriving inside
-- that window fails PickStageable's deliveringEventId check rather than putting
-- two letters on one mat.
local function stage(player: Player, data: LifeData)
	if building[player] then
		return
	end
	building[player] = true

	local event = EventService.PickStageable(player, "Ambient", canPresent)
	if event == nil then
		-- Nothing eligible left, or nothing the house can hold. A content gap,
		-- not an error: the world is simply quiet for a while longer.
		building[player] = false
		return
	end

	data.deliveringEventId = event.id

	local placed = present(player, event)
	if placed then
		-- Counted on success only. A staging that failed cost the player nothing
		-- and must not cost them one of the year's two.
		data.deliveriesThisYear += 1
	elseif data.deliveringEventId == event.id then
		data.deliveringEventId = nil
	end

	building[player] = false
end

local function tick()
	if not enabled then
		return
	end

	for _, player in Players:GetPlayers() do
		local profile = DataService.GetProfile(player)
		if profile == nil then
			continue
		end

		local data = Lives.Active(profile.Data)
		local current = staged[player]

		if current ~= nil then
			if current.expiresAt ~= nil and os.clock() >= current.expiresAt then
				finish(player, false, true)
			end
			-- One at a time either way. Two things arriving at once would make
			-- the second unreachable while the first still stands.
			continue
		end

		if not data.alive or data.pendingEventId ~= nil or data.deliveringEventId ~= nil then
			continue
		end

		local ageYears = data.ageMonths // Config.Time.MonthsPerYear
		-- Below MinAge the countdown does not run at all, rather than running
		-- and being ignored. Otherwise childhood would silently spend the whole
		-- window and the first ambient event would land the instant the player
		-- turned old enough for one.
		if ageYears < Config.Ambient.MinAge then
			continue
		end

		if data.deliveriesThisYear >= Config.Ambient.MaxPerYear then
			continue
		end

		data.deliveryCountdown -= Config.Ambient.TickSeconds
		if data.deliveryCountdown > 0 then
			continue
		end

		-- Reset before the attempt, not after, so a failed staging waits out a
		-- full gap instead of retrying every tick.
		data.deliveryCountdown = nextGap()
		task.spawn(stage, player, data)
	end
end

-- Rebuilds whatever the player left standing in the world. The profile is the
-- authority: if it says a letter is out there, one goes back on the mat.
local function restore(player: Player)
	local profile = DataService.WaitForProfile(player)
	if profile == nil then
		return
	end

	local data = Lives.Active(profile.Data)
	local eventId = data.deliveringEventId
	if eventId == nil or not data.alive then
		return
	end

	local event = LifeEvents.ById[eventId]
	if event == nil then
		warn(`[AGES] delivered event "{eventId}" no longer exists; dropping it`)
		data.deliveringEventId = nil
		return
	end

	-- The field is shared with every system that puts something in the world to be walked
	-- to, and rebuilding somebody else's is not the same as rebuilding one of ours: there
	-- is no presenter for a wandered event, so this would fail to stage it and then clear
	-- the claim -- quietly stealing it from the system that is about to put it out.
	if Delivery.RouteOf(event.delivery) ~= "Ambient" then
		return
	end

	if building[player] then
		return
	end
	building[player] = true

	-- Clearing on failure matters more here than anywhere else. A profile that
	-- claims something is being delivered while nothing is in the room would
	-- block every future delivery for the rest of that life, silently.
	if not present(player, event) and data.deliveringEventId == eventId then
		data.deliveringEventId = nil
	end

	building[player] = false
end

-- WorldEventService hands this back the moment one of our anchors pays out.
local function onCollected(player: Player, instance: Instance, _eventId: string)
	local current = staged[player]
	if current == nil or current.presentation.anchor ~= instance then
		return
	end
	finish(player, true, true)
end

-- A year ended, so anything still waiting belonged to it. One rule rather than
-- two: it clears the letter that never expires as well as a call still ringing,
-- and it is also the only thing that refills the per-year allowance.
function DeliveryService.OnAgeUp(player: Player)
	finish(player, false, true)

	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		Lives.Active(profile.Data).deliveriesThisYear = 0
	end
end

-- A new life. The countdown restarts rather than carrying over, so the first
-- ambient event of a life is always a wait.
function DeliveryService.ResetForNewLife(player: Player)
	finish(player, false, true)

	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		Lives.Active(profile.Data).deliveriesThisYear = 0
		Lives.Active(profile.Data).deliveryCountdown = nextGap()
	end
end

-- Studio harness: stages a named event now, bypassing the countdown and the
-- per-year cap but nothing else. Returns false when the id is unknown or its
-- delivery has no world presence, so the caller can say which.
function DeliveryService.ForceStage(player: Player, eventId: string): boolean
	local event = LifeEvents.ById[eventId]
	if event == nil or DeliveryPresenters.For(event.delivery) == nil then
		return false
	end

	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end

	finish(player, false, true)
	Lives.Active(profile.Data).deliveringEventId = event.id
	if not present(player, event) and Lives.Active(profile.Data).deliveringEventId == event.id then
		Lives.Active(profile.Data).deliveringEventId = nil
		return false
	end
	return true
end

function DeliveryService.SetEnabled(value: boolean)
	enabled = value
end

function DeliveryService.IsEnabled(): boolean
	return enabled
end

-- What the harness prints for /deliveries.
function DeliveryService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded"
	end

	local data = Lives.Active(profile.Data)
	local current = staged[player]
	local placed = if current ~= nil
		then `{current.delivery} "{current.eventId}"`
		else "nothing in the world"

	local remaining = math.max(0, data.deliveryCountdown)
	return string.format(
		"%s | profile says %s | next in %.0fs | %d/%d this year | ambient %s",
		placed,
		data.deliveringEventId or "nothing",
		remaining,
		data.deliveriesThisYear,
		Config.Ambient.MaxPerYear,
		if enabled then "on" else "off"
	)
end

function DeliveryService:Init()
	WorldEventService.SetCollectedHandler(onCollected)
end

function DeliveryService:Start()
	local tag = Config.World.DeliveryPointTag
	local function add(instance: Instance)
		if instance:IsA("BasePart") then
			deliveryPoints[instance :: BasePart] = true
		else
			warnPointOnce(instance, `is a {instance.ClassName}, which has no position; nothing can appear at it`)
		end
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			deliveryPoints[instance :: BasePart] = nil
		end
		warnedPoints[instance] = nil
	end)
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(restore, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		-- The object leaves the world; the profile keeps saying it is out there,
		-- which is what puts it back on the mat when they rejoin.
		finish(player, false, false)
		building[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(restore, player)
	end

	task.spawn(function()
		while true do
			task.wait(Config.Ambient.TickSeconds)
			tick()
		end
	end)
end

return DeliveryService
