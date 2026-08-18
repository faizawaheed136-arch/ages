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
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Delivery = require(ReplicatedStorage:WaitForChild("Delivery"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)
local StatService = require(script.Parent.StatService)
local MoneyService = require(script.Parent.MoneyService)
local LifeEvents = require(script.Parent.Parent.content.LifeEvents)
local Flags = require(script.Parent.Parent.content.Flags)
local NPCService = require(script.Parent.NPCService)

type LifeEvent = Types.LifeEvent
type EventChoice = Types.EventChoice
type StatName = Types.StatName
type OfferedEvent = Types.OfferedEvent
type OfferedChoice = Types.OfferedChoice
type LifeData = Types.LifeData
type EventResolution = Types.EventResolution

local EventOfferedRemote = Remotes.Get("EventOffered")
local EventResolvedRemote = Remotes.Get("EventResolved")
local RequestEventChoiceRemote = Remotes.Get("RequestEventChoice")

local EventService = {}

-- LifeService injects its AgeUp here at Init. Requiring it directly would be a
-- cycle, since LifeService already requires this service to offer an event once
-- a birthday has resolved.
type AgeUpHandler = (player: Player, cause: Types.AgeUpCause) -> ()
local ageUpHandler: AgeUpHandler? = nil

function EventService.SetAgeUpHandler(handler: AgeUpHandler)
	ageUpHandler = handler
end

-- DeliveryService injects this at Init. It stages the follow-up event named by
-- escalatesTo without EventService having to require DeliveryService back, which
-- would be a cycle since DeliveryService requires this service at the top level.
type EscalationHandler = (player: Player, eventId: string) -> ()
local escalationHandler: EscalationHandler? = nil

function EventService.SetEscalationHandler(handler: EscalationHandler)
	escalationHandler = handler
end

-- EnactService injects this at Init, for the same reason as above: it calls
-- ResolveChoice below, so it must be the one that knows about this service and
-- not the other way round.
--
-- Returning false is the *normal* answer, not a failure -- it means the room
-- could not hold the choices, which is common and always recoverable. This
-- service never learns why, only that the event is a panel after all.
--
-- `subject` is the thing the event is about, standing in the room, or nil when it
-- is about nothing or nothing could be placed. Passed straight through from the
-- scene handler and never read here: this service is a courier between the two,
-- which is what keeps a subject and an enactment from having to know about each
-- other. It only knows the order to call them in.
type EnactHandler = (player: Player, event: LifeEvent, subject: Types.StagedSubject?) -> boolean
local enactHandler: EnactHandler? = nil

function EventService.SetEnactHandler(handler: EnactHandler)
	enactHandler = handler
end

-- PropService injects this at Init, and it is the third and last way an event can
-- be answered. Same contract as the enact handler and for the same reason -- false
-- means the room could not hold the arrangement and the event is a panel after all
-- -- but what it stages is different in kind. Enactment puts dots on a subject and
-- still opens a list; this puts the answers themselves in the room as objects, and
-- there is no list at any point.
--
-- It is not passed the subject. A Handled event is about the things you handle, so
-- the one standing thing an event is "about" is either one of those props or is not
-- in the event at all -- and a handler that took a subject it could never place a
-- prop on would be an argument nobody could use.
type ActHandler = (player: Player, event: LifeEvent) -> boolean
local actHandler: ActHandler? = nil

function EventService.SetActHandler(handler: ActHandler)
	actHandler = handler
end

-- SceneService injects this at Init. Its return value is not for the client:
-- a subject changes what is standing in the room, not how the prompt is answered,
-- so an event whose animal could not be placed is byte-for-byte the same offer as
-- one that never named a subject. It is for the enact handler, which hangs the dots
-- on the animal.
type SceneHandler = (player: Player, event: LifeEvent) -> Types.StagedSubject?
local sceneHandler: SceneHandler? = nil

function EventService.SetSceneHandler(handler: SceneHandler)
	sceneHandler = handler
end

-- SceneService injects this too, and it is the other half of the same idea: the
-- scene handler above is told an event has opened, and this one is told how it
-- was answered, so that the thing standing in the room can do what the outcome
-- line says it did.
--
-- A handler rather than something read off the profile, because which choice was
-- taken is not saved anywhere -- and should not be. It matters for the few seconds
-- an animal is still in the room and never again, so persisting it would be
-- writing a field to a DataStore to carry a value across four seconds.
--
-- Fired for every answer, however it was given. Watching the dog come to you is
-- worth the same whether you crossed the room to click it or answered on a panel
-- where you stood, and an ending that only arrived when there had been something to
-- hang dots on would be a worse feature than no ending at all.
-- A list rather than a single slot, unlike every other injection point above.
-- Those are each one service's job -- there is one way to stage a scene and one
-- way to enact a choice -- but "an answer was given" is news that more than one
-- service legitimately wants: the scene reacts to it, and work records it against
-- your job. A setter would have made the second one silently replace the first.
type AnsweredHandler = (player: Player, event: LifeEvent, choice: EventChoice) -> ()
local answeredHandlers: { AnsweredHandler } = {}

function EventService.OnAnswered(handler: AnsweredHandler)
	table.insert(answeredHandlers, handler)
end

-- Puts the thing the event is about in the room, if it is about anything and if
-- there is anywhere to put it, and reports where it will come to rest.
--
-- Called *before* beginResolution at every site that opens a prompt, and the order
-- is the whole reason enactment works: the dots hang on the subject, so the subject
-- has to be in the room before there is anything to hang them on.
local function beginScene(player: Player, event: LifeEvent): Types.StagedSubject?
	if sceneHandler == nil then
		return nil
	end
	return sceneHandler(player, event)
end

-- Outcome lines, stat effects, payouts and how your employer will take it are all
-- withheld until a choice is made, so the best answer can't be read straight off
-- the payload -- least of all the work moments, where the choice that is best for
-- you and the one that is best for your record are deliberately not the same, and
-- a visible performance number would collapse that into arithmetic. Note the shape
-- rather than the omission does the work here: this builds each choice field by
-- field, so anything added to EventChoice is server-only until someone says
-- otherwise. Costs are the one thing
-- that has to go the other way -- an unpriced purchase is not a decision -- and
-- with them goes the server's verdict on whether the player can meet each one.
--
-- Takes the balance rather than the player because it is a pure translation, and
-- every caller has the profile open already: reading it again in here would be a
-- second lookup that could, in principle, see a different number than the one the
-- caller is acting on.
local function toOffered(event: LifeEvent, resolution: EventResolution, balance: number): OfferedEvent
	local choices: { OfferedChoice } = {}
	for _, choice in event.choices do
		local cost = choice.cost
		table.insert(choices, {
			id = choice.id,
			label = choice.label,
			cost = cost,
			locked = cost ~= nil and balance < cost,
		})
	end
	return {
		id = event.id,
		delivery = event.delivery,
		prompt = event.prompt,
		choices = choices,
		resolution = resolution,
	}
end

-- Puts the choices in the room if the event asked for that and the room can hold
-- them. Returns what the client should actually be told, which is the only thing
-- any caller needs -- "Panel" covers both an event that never wanted enacting and
-- one that wanted it and could not have it.
--
-- Deliberately called *before* the offer is sent rather than after. The dots are up
-- by the time the banner appears, so there is no window in which the player is told
-- to go and click something that is not yet clickable.
local function beginResolution(
	player: Player,
	event: LifeEvent,
	wanted: EventResolution?,
	subject: Types.StagedSubject?
): EventResolution
	if wanted == "Handled" and actHandler ~= nil then
		if actHandler(player, event) then
			return "Handled"
		end
		-- Falls all the way back to a panel rather than trying enactment next. A
		-- Handled event's answers are written to be done, not clicked at a distance,
		-- so there is nothing sensible to hang dots on when the props would not fit.
		return "Panel"
	end
	if wanted ~= "Enacted" or enactHandler == nil then
		return "Panel"
	end
	return if enactHandler(player, event, subject) then "Enacted" else "Panel"
end

-- The single eligibility rule, so a world object offering an event by name and
-- a birthday rolling for one can never disagree about what may fire.
--
-- A repeatable event stays eligible after it has been lived, which is the one
-- exception to the seen list. It has to live *here* rather than only in the picker
-- below: WorkService picks an event and then offers it by name through
-- OfferIfEligible, so a rule the picker knew and this did not would show up as
-- shifts whose moment was chosen and then silently refused on the way out.
local function isEligible(data: LifeData, event: LifeEvent, ageYears: number): boolean
	if ageYears < event.minAge or ageYears > event.maxAge then
		return false
	end
	-- Checked alongside age rather than in the picker, for the same reason the seen
	-- list is: a world object that offers an event by name comes through
	-- OfferIfEligible, and a branch the picker respected and this did not would be a
	-- lure the player crossed a room for and was then refused at.
	if not Flags.Meets(data.flags, event.requires, event.forbids) then
		return false
	end
	-- Cooldown is a delivery-rate limiter, not a one-time block. A missed call
	-- should come back; the timer tracks "don't send another of these too soon."
	if event.cooldown ~= nil and event.cooldown > 0 then
		local started = data.cooldownTimers[event.id]
		if started ~= nil and os.clock() < started then
			return false
		end
	end
	return not data.seenEventIds[event.id] or event.repeatable == true
end

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	return character:GetPivot().Position
end

-- What the player's current world situation looks like, as a set of tags the
-- picker can use to prefer events that belong here. Three sources: nearby
-- NPCs emit "npc:{cast}", tagged floor parts emit "zone:{id}", and each flag
-- listed in Config.Ambient.FlagContext emits "flag:{id}" when held.
--
-- An event with no tags fires anywhere. An event with tags fires here only
-- when at least one of its tags appears in this set -- or when no tagged
-- candidate exists, in which case the event still fires so the world is not
-- starved for content. The set is rebuilt every tick, so it always reflects
-- the player's current position and flags.
function EventService.getContextTags(player: Player): { [string]: boolean }
	local tags: { [string]: boolean } = {}
	local function add(tag: string)
		tags[tag] = true
	end

	local radius = Config.Ambient.NPCContextRadius
	local playerPos = characterPosition(player)
	if playerPos ~= nil then
		for _, posInfo in NPCService.GetPositions() do
			local distance = (playerPos - posInfo.position).Magnitude
			if distance <= radius then
				add("npc:" .. posInfo.id)
			end
		end
	end

	for _, part in CollectionService:GetTagged(Config.World.ZoneTag) do
		local zoneId = part:GetAttribute(Config.World.ZoneAttribute)
		if zoneId ~= nil and typeof(zoneId) == "string" then
			local partPos = (part :: BasePart).Position
			if partPos ~= nil
				and playerPos ~= nil
				and (playerPos - partPos).Magnitude <= Config.World.ZoneContextRadius
			then
				add("zone:" .. zoneId)
			end
		end
	end

	for flagId in Config.Ambient.FlagContext :: { string } do
		add("flag:" .. flagId)
	end

	return tags
end

-- Whether an event's tags match the current context, or the event has no tags
-- (making it universal). Used by the picker to filter candidates against
-- context without breaking when context is nil.
local function tagsMatchContext(
	event: LifeEvent,
	contextTags: { [string]: boolean }?
): boolean
	if contextTags == nil or event.tags == nil or #event.tags == 0 then
		return true
	end
	for _, tag in event.tags do
		if contextTags[tag] == true then
			return true
		end
	end
	return false
end

-- Weighted pick among the events eligible right now whose delivery takes the
-- given route. Routing by table rather than by name is what keeps a birthday
-- from ever handing over a letter: a mode is only reachable from the one system
-- that owns its route, and adding a mode without classifying it fails to compile
-- in Delivery.luau rather than leaking into the wrong pool here.
local function pickForRoute(
	data: LifeData,
	ageYears: number,
	route: Delivery.Route,
	filter: ((LifeEvent) -> boolean)?,
	contextTags: { [string]: boolean }?
): LifeEvent?
	-- Two pools, and the first non-empty one wins. Something the player has never
	-- lived always beats something they have, however heavily the repeat is
	-- weighted -- so a repeatable event can never crowd out fresh content, and the
	-- authored moments of a life are all spent before any of them comes round again.
	--
	-- Weights are only ever compared within a pool, which is what makes that
	-- guarantee absolute rather than statistical.
	--
	-- contextTags is used to prefer events whose tags match the current world
	-- situation. An event with no tags is always eligible; an event with tags
	-- is eligible only when at least one of its tags is in the context set --
	-- unless no tagged candidate exists, in which case all candidates qualify.
	local function pickInto(allowUntagged: boolean): (boolean, { LifeEvent }, { number }, number, { LifeEvent }, { number }, number)
		local fresh: { LifeEvent } = {}
		local freshWeights: { number } = {}
		local freshTotal = 0
		local repeats: { LifeEvent } = {}
		local repeatWeights: { number } = {}
		local repeatTotal = 0
		local hasTagged = false

		for _, event in LifeEvents.All do
			local presentable = filter == nil or filter(event)
			if not (presentable
				and Delivery.RouteOf(event.delivery) == route
				and isEligible(data, event, ageYears))
			then
				continue
			end

			local hasTags = event.tags ~= nil and #event.tags > 0
			if contextTags ~= nil and hasTags then
				if not tagsMatchContext(event, contextTags) then
					continue
				end
				hasTagged = true
			elseif contextTags ~= nil and not hasTags and not allowUntagged then
				continue
			end

			local weight = event.weight or 1
			if data.seenEventIds[event.id] then
				table.insert(repeats, event)
				table.insert(repeatWeights, weight)
				repeatTotal += weight
			else
				table.insert(fresh, event)
				table.insert(freshWeights, weight)
				freshTotal += weight
			end
		end

		return hasTagged, fresh, freshWeights, freshTotal, repeats, repeatWeights, repeatTotal
	end

	local hasTagged, fresh, freshWeights, freshTotal, repeats, repeatWeights, repeatTotal = pickInto(false)

	-- Second pass: if nothing tagged matched, allow untagged events through so the
	-- world is not starved for content when no authored route exists for the
	-- current context.
	if not hasTagged and contextTags ~= nil then
		hasTagged, fresh, freshWeights, freshTotal, repeats, repeatWeights, repeatTotal = pickInto(true)
	end

	local candidates = if freshTotal > 0 then fresh else repeats
	local weights = if freshTotal > 0 then freshWeights else repeatWeights
	local totalWeight = if freshTotal > 0 then freshTotal else repeatTotal

	-- Nothing unlived is eligible and nothing lived may be lived again. Running dry
	-- is a content gap, not an error: the year simply passes without one.
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

-- `resolution` overrides what the event asked for, and exists for the Studio
-- harness: forcing an event to enact is how a new one is proof-read, and forcing
-- it to a panel is how the fallback is tested without waiting out the clock.
-- Returns whether the prompt actually went out, so `OfferIfEligible` can keep its promise
-- that false means "inert right now" -- which a player still choosing a life is.
local function offer(player: Player, data: LifeData, event: LifeEvent, resolution: EventResolution?): boolean
	-- The choke point the setup menu really hangs on. Every route to a prompt -- a birthday,
	-- an ambient delivery reached on foot, a shift, a lesson, the debug harness -- arrives
	-- here, so one check makes "a question asked of somebody who has not chosen a life yet"
	-- unrepresentable rather than merely unlikely. The alternative was a `paused` test in
	-- each of six tick loops, which works exactly until the seventh loop is written.
	--
	-- Silent rather than a warn: this is a normal state, not a fault. The world behind the
	-- menu is deliberately still alive -- the town walks, so the player can see what they
	-- are about to be born into -- and it will occasionally decide something is due. It
	-- simply does not get to interrupt.
	if not Lives.HasBegun(data) then
		return false
	end

	data.pendingEventId = event.id
	data.pendingEventCountInChapter += 1
	-- Track world vs modal for the 70/30 ratio. Shift events are excluded —
	-- they are structurally different and managed by WorkService, not the life.
	local route = Delivery.RouteOf(event.delivery)
	if route == "Immediate" then
		data.modalEventsThisChapter += 1
	elseif route ~= "Shift" then
		data.worldEventsThisChapter += 1
	end
	-- Whatever the world was holding has now been reached, so the world stops
	-- holding it. Cleared here, at the moment the prompt opens, rather than by
	-- the delivery layer afterwards: that makes "a prompt is open while the
	-- letter is still on the mat" unrepresentable instead of merely unlikely.
	if data.deliveringEventId == event.id then
		data.deliveringEventId = nil
	end
	-- Written to the profile before anything goes near the room. Both the scene and
	-- the enactment watch pendingEventId to know they are still wanted, so setting
	-- it second would give either a tick in which it believed it had already been
	-- superseded.
	--
	-- Subject first, then the choices around it: an answer given by walking should
	-- be given by walking somewhere that means something, and there is nothing for
	-- "aside" to be aside *of* -- nor anything for an "at" choice to be worn by --
	-- until the thing the event is about is standing there.
	local subject = beginScene(player, event)
	local actual = beginResolution(player, event, resolution or event.resolution, subject)
	EventOfferedRemote:FireClient(player, toOffered(event, actual, data.money))
	return true
end

-- Re-sends a prompt that is already open, as a panel. This is the one way out of
-- an enactment that was never completed -- a player who cannot find the animal,
-- cannot reach it, or simply does not want to walk -- and it is deliberately
-- not a cancellation: the same event, the same choices, nothing consumed, only a
-- different way of answering.
--
-- Guarded on the id so a fallback that arrives late, after the player answered
-- some other way, cannot reopen a question that is already settled.
function EventService.FallBackToPanel(player: Player, eventId: string)
	local profile = DataService.GetProfile(player)
	if profile == nil or not Lives.Active(profile.Data).alive then
		return
	end
	if Lives.Active(profile.Data).pendingEventId ~= eventId then
		return
	end

	local event = LifeEvents.ById[eventId]
	if event == nil then
		warn(`[AGES] pending event "{eventId}" no longer exists; dropping it`)
		Lives.Active(profile.Data).pendingEventId = nil
		return
	end

	EventOfferedRemote:FireClient(player, toOffered(event, "Panel", Lives.Active(profile.Data).money))
end

-- Called by LifeService once a birthday has finished resolving.
function EventService.OfferForAge(player: Player, ageYears: number)
	local profile = DataService.GetProfile(player)
	if profile == nil or not Lives.Active(profile.Data).alive then
		return
	end

	local data = Lives.Active(profile.Data)
	-- An unanswered prompt still stands. Stacking a second one on top would let
	-- the first quietly disappear along with the choice it was asking for.
	if data.pendingEventId ~= nil then
		return
	end

	-- 70/30 ratio: a chapter should be mostly world-spawned. An Immediate event
	-- counts as modal, so refuse it if the world has not earned its share yet.
	-- With MaxPerChapter=3 this means at most one modal event per chapter.
	if data.worldEventsThisChapter * 10 < data.modalEventsThisChapter * 3 then
		return
	end

	-- Immediate only. A birthday hands over the events that have nowhere to be:
	-- staging a letter here would announce mail the player never went to fetch.
	-- Context tags are not passed: a birthday is age-gated, not location-gated.
	local event = pickForRoute(data, ageYears, "Immediate", nil, nil)
	if event ~= nil then
		offer(player, data, event)
	end
end

-- Picks something the world could stage right now *without* offering it, and
-- without writing anything to the profile. The ambient scheduler has to know
-- what it is staging before the player has reached it -- a letter and a ringing
-- phone are different objects -- so selection and offering are two steps here in
-- a way they never are for a birthday. The caller is responsible for the profile
-- write, and OfferIfEligible re-checks everything when the player arrives.
--
-- The Ambient route consumes an autonomy point: the player has to earn each
-- event by working, studying, or visiting, so the world is a response to what
-- they do rather than a noise machine. Shift and Immediate routes bypass the
-- gate -- a shift event is the reward for the shift itself, and a birthday is
-- the chapter spine; neither should stall because the player has not visited
-- enough people this chapter.
function EventService.PickStageable(
	player: Player,
	route: Delivery.Route,
	filter: ((LifeEvent) -> boolean)?,
	contextTags: { [string]: boolean }?
): LifeEvent?
	local profile = DataService.GetProfile(player)
	if profile == nil or not Lives.Active(profile.Data).alive then
		return nil
	end

	local data = Lives.Active(profile.Data)
	if data.pendingEventId ~= nil or data.deliveringEventId ~= nil then
		return nil
	end

	local ageYears = data.ageMonths // Config.Time.MonthsPerYear
	if data.pendingEventCountInChapter >= Config.Events.MaxPerChapter then
		return nil
	end
	-- The autonomy gate. Only the Ambient path spends a point; everything
	-- else is free.
	if route == "Ambient" and data.autonomyPoints <= 0 then
		return nil
	end
	return pickForRoute(data, ageYears, route, filter, contextTags)
end

-- Spend one autonomy point. Returns true when the player had a point to spend
-- and false when they are out. Called after a successful ambient stage so the
-- cost is only paid when the world actually put something on the mat.
function EventService.SpendAutonomy(player: Player): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	local data = Lives.Active(profile.Data)
	if data.autonomyPoints <= 0 then
		return false
	end
	data.autonomyPoints -= 1
	return true
end

-- Add autonomy points, capped at the chapter ceiling. Called by the services
-- that generate them -- WorkService on shift finish, the lesson services on
-- lesson end, PeopleService on first visit -- so the cap is the single place
-- that keeps the counter from drifting above the event cap.
function EventService.AwardAutonomy(player: Player, count: number)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)
	local next = data.autonomyPoints + count
	if next > Config.Autonomy.MaxPerChapter then
		next = Config.Autonomy.MaxPerChapter
	end
	data.autonomyPoints = next
end

-- Picks an Ambient event weighted by the player's current context tags and
-- placed at the nearest matching NPC. The picker prefers events whose tags
-- match the live context; if none match, it falls back to untagged events.
-- This is what the proximity path calls rather than the timer path.
function EventService.PickNearby(player: Player): LifeEvent?
	local profile = DataService.GetProfile(player)
	if profile == nil or not Lives.Active(profile.Data).alive then
		return nil
	end

	local data = Lives.Active(profile.Data)
	if data.pendingEventId ~= nil or data.deliveringEventId ~= nil then
		return nil
	end

	if data.pendingEventCountInChapter >= Config.Events.MaxPerChapter then
		return nil
	end

	local ageYears = data.ageMonths // Config.Time.MonthsPerYear
	local contextTags = EventService.getContextTags(player)
	return pickForRoute(data, ageYears, "Ambient", nil, contextTags)
end

-- Public so the Studio harness can force a specific event without rolling for
-- it. Returns false when the id doesn't exist, and also when there is no life to
-- offer it to -- a profile still sitting in the setup menu -- so the caller can say
-- so. `resolution` overrides how it is answered, which is how /enact proof-reads an
-- event that is not authored Enacted.
function EventService.ForceOffer(player: Player, eventId: string, resolution: EventResolution?): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	local event = LifeEvents.ById[eventId]
	if event == nil then
		return false
	end
	return offer(player, Lives.Active(profile.Data), event, resolution)
end

-- Offers a *named* event, but only if the engine would have allowed it anyway.
-- This is what a tagged object in the world calls: the object says where the
-- event lives, this decides whether the player may have it. Returns false for
-- every ordinary reason an object is inert right now — wrong age, already
-- lived, a prompt still open, dead — so callers must not treat false as a
-- fault. A missing id is the one real error and warns on the caller's side.
function EventService.OfferIfEligible(player: Player, eventId: string): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil or not Lives.Active(profile.Data).alive then
		return false
	end

	local data = Lives.Active(profile.Data)
	if data.pendingEventId ~= nil then
		return false
	end

	local event = LifeEvents.ById[eventId]
	if event == nil then
		return false
	end

	local ageYears = data.ageMonths // Config.Time.MonthsPerYear
	if not isEligible(data, event, ageYears) then
		return false
	end

	return offer(player, data, event)
end

function EventService.ClearPending(player: Player)
	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		Lives.Active(profile.Data).pendingEventId = nil
	end
end

-- A new life may live the same moments again, so the seen list is per-life.
-- deliveringEventId goes with it: a letter addressed to the person who just died
-- is not still on the mat for the child who replaces them. The physical object
-- is DeliveryService's to remove -- this clears the state that authorizes it.
function EventService.ResetSeen(player: Player)
	local profile = DataService.GetProfile(player)
	if profile ~= nil then
		Lives.Active(profile.Data).seenEventIds = {}
		-- Goes with the seen list rather than persisting: flags are what *this* life
		-- did, and a new one inheriting them would open branches for a child who has
		-- no memory of earning them.
		Lives.Active(profile.Data).flags = {}
		Lives.Active(profile.Data).pendingEventId = nil
		Lives.Active(profile.Data).deliveringEventId = nil
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

-- The one place a choice is ever applied. There is only one remote now -- the panel
-- opens the same way whether the player clicked a row on a birthday card or three
-- dots on a dog -- and this is where it lands. That is what keeps enactment from
-- being a second way to pay out an event, and more to the point from being a second
-- set of rules about when that is allowed.
--
-- Returns whether the answer was taken, so a caller that has just taken its dots
-- down can tell a real answer from one that arrived too late.
function EventService.ResolveChoice(player: Player, eventId: string, choiceId: string): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil or not Lives.Active(profile.Data).alive then
		return false
	end

	local data = Lives.Active(profile.Data)
	if data.pendingEventId == nil or data.pendingEventId ~= eventId then
		-- Already answered, never offered, or forged. A duplicate press lands
		-- here too, which is what stops one prompt paying out twice.
		return false
	end

	local event = LifeEvents.ById[eventId]
	if event == nil then
		-- The pending id survived in a profile but the content is gone.
		warn(`[AGES] pending event "{eventId}" no longer exists; dropping it`)
		data.pendingEventId = nil
		return false
	end

	local choice = findChoice(event, choiceId)
	if choice == nil then
		return false
	end

	-- Affordability is a guard like every other one above, not a step in applying the
	-- answer: a choice the player cannot pay for was never a legal answer. Checked
	-- here even though the client was already told the choice was locked, because
	-- that flag is a courtesy and this is the rule -- a forged remote and a panel left
	-- open from a question that has already been settled both arrive at this line.
	--
	-- Before anything is consumed, so a refusal costs the player nothing. The prompt
	-- is still open and every other answer is still available.
	local cost = choice.cost
	if cost ~= nil and not MoneyService.CanAfford(player, cost) then
		return false
	end

	-- Consumed before any stat is written, so a retry arriving behind this one
	-- fails the pending check above rather than applying the effects twice.
	data.pendingEventId = nil
	data.seenEventIds[event.id] = true

	-- Flags go in with the seen mark, in the same block of straight-line code with
	-- nothing between them that can yield or fail. What you did and the fact that you
	-- did it are one write: a life that recorded the answer but not its consequence
	-- would go on to be a life the branch never opened for, with nothing anywhere
	-- saying why.
	--
	-- Cleared before set, so a choice that does both ends up holding what it sets.
	-- That ordering is the only thing that makes exclusive pairs writable in one
	-- answer, which is most of what `clears` is for.
	local ageYears = data.ageMonths // Config.Time.MonthsPerYear
	if choice.clears ~= nil then
		for _, flagId in choice.clears do
			data.flags[flagId] = nil
		end
	end
	if choice.sets ~= nil then
		for _, flagId in choice.sets do
			-- Not overwritten if already held: the age on a flag is when the life
			-- first did this, and a repeatable event re-earning it should not quietly
			-- move a childhood memory to the present.
			if data.flags[flagId] == nil then
				data.flags[flagId] = ageYears
			end
		end
	end

	-- Money before stats, and both before the client is told anything. Affordability
	-- was established a few lines up with no yield in between, so Spend cannot fail
	-- here -- and says so loudly if it somehow does, rather than letting an event
	-- hand out its effects for free.
	if cost ~= nil then
		MoneyService.Spend(player, cost, `{event.id}:{choice.id}`)
	end
	local payout = choice.payout
	if payout ~= nil then
		MoneyService.Add(player, payout, `{event.id}:{choice.id}`)
	end

	-- Iterating a keyed table widens the key back to string, so the cast puts
	-- back what StatDelta already guarantees.
	for statName, delta in choice.effects do
		StatService.AddStat(player, statName :: StatName, delta)
	end

	-- No death check here on purpose. LifeService already tests health every
	-- tick, so a choice that empties it is lethal within the second without
	-- this service needing to reach into the life cycle.
	EventResolvedRemote:FireClient(player, event.id, choice.outcome)

	-- Told at the same moment as the client, so whatever is standing in the room
	-- starts reacting on the frame the outcome appears rather than after it. Called
	-- here rather than at the top of the function because a choice that failed any
	-- guard above never happened, and nothing should react to it.
	--
	-- Each listener is isolated, because they are unrelated to each other and one
	-- throwing must not cost the others their news -- an animal that failed to react
	-- should not also mean the shift quietly forgot how you answered it. Loud, not
	-- swallowed: the warning names the event so the fault is findable.
	for _, handler in answeredHandlers do
		local ok, err = pcall(handler, player, event, choice)
		if not ok then
			warn(`[AGES] an answered-handler failed for "{event.id}":"{choice.id}": {err}`)
		end
	end

	-- In the toddler years answering an event *is* the year passing, so a child
	-- grows by living rather than by waiting out a timer. Deliberately not true
	-- above EndAge: from there a year holds many events, and advancing on each
	-- would burn a whole life in minutes. The age-up offers the next year's
	-- event in turn, which is what chains childhood together.
	--
	-- Still the age read at the top of this function, before any of the answer was
	-- applied, which is the right one: nothing here moves the clock, and the flags
	-- written above were earned at the age the player was when they answered.
	if ageYears <= Config.Childhood.EndAge and ageUpHandler ~= nil then
		ageUpHandler(player, "Event")
	end

	-- Escalation chain: if this event named a follow-up, stage it now. The
	-- follow-up is a world delivery (Ambient route), not a modal panel -- it
	-- arrives when the player reaches it, not as a surprise prompt. If the
	-- follow-up is not stageable (age, flags, cooldown, etc.), the chain
	-- simply stops; no warning, no error.
	if event.escalatesTo ~= nil and escalationHandler ~= nil then
		escalationHandler(player, event.escalatesTo)
	end

	return true
end

-- Both arguments arrive from the client and are therefore untrusted, including
-- their types. Everything past the type check is the shared path above, so the
-- remote adds no rule of its own -- it only proves it was handed two strings.
local function onChoiceRequested(player: Player, eventId: any, choiceId: any)
	if typeof(eventId) ~= "string" or typeof(choiceId) ~= "string" then
		return
	end
	EventService.ResolveChoice(player, eventId, choiceId)
end

-- Re-offers whatever was left unanswered when the player last left.
local function pushPending(player: Player)
	local profile = DataService.WaitForProfile(player)
	if profile == nil then
		return
	end

	local data = Lives.Active(profile.Data)
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

	-- Re-enacted rather than restored. The animal stood wherever the player was when
	-- the prompt first opened, in a session that has since ended; putting it in the
	-- room they are in *now* is both simpler and more correct than remembering where
	-- it used to be.
	--
	-- If the character has not spawned yet this lands on the panel, which is the
	-- honest outcome -- there is nothing to walk to and nobody to walk. The profile
	-- has already been waited on above, which is a DataStore round trip, so in
	-- practice the character is nearly always there.
	--
	-- Re-staged in the same order as a fresh offer, and for the same reason: the
	-- animal stood wherever the player was when the prompt first opened, and that
	-- was a different session, so it has to be placed again before the choices can
	-- be arranged around it.
	local subject = beginScene(player, event)
	local actual = beginResolution(player, event, event.resolution, subject)
	EventOfferedRemote:FireClient(player, toOffered(event, actual, data.money))
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
