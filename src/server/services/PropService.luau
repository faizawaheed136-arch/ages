--!strict
-- Answering an event by doing the thing it describes.
--
-- This is the third and last way an event can be answered, and it is the only one
-- with no list in it anywhere. A panel event is a list you read. An enacted event is
-- a list you walk to first -- the dots on the dog buy you the right to be asked, and
-- then a panel opens after all. This one never opens anything. The event's answers
-- are objects put in the room, and the answer is given by crawling to one, shoving
-- one, picking one up and carrying it somewhere, or by holding still and letting the
-- moment pass.
--
-- Childhood is the argument for it. A toddler cannot read, and every one of the
-- first five years was a paragraph and three sentences to click -- which is the one
-- interface a two-year-old is least equipped to use and the first thing a new player
-- is ever handed. "The bright thing is on the far side of a rug that has never
-- seemed so wide" was a sentence about a rug that was not there. Now there is a rug,
-- and you can shove it.
--
-- The division of labour is EnactService's, deliberately, because it was right
-- there. EventService alone decides which event fires and alone validates an answer;
-- this decides only that the room can hold the question, lays it out, and watches.
-- Every answer still arrives through EventService.ResolveChoice -- the same function
-- the panel's remote lands in -- so there is exactly one place a choice is ever paid
-- out, and a prop has never been a second way to cheat one. A forged remote and a
-- rug being pushed are the same three guards deep.
--
-- Nothing here talks to the client. The props are world objects and the labels over
-- them are BillboardGuis in the workspace, so the player sees them because they are
-- there, not because they were told. An answered prop event costs exactly the one
-- remote message the banner cost, and doing the thing costs none at all.
--
-- Best-effort, like everything else in this layer. A room with nowhere to lay the
-- set out is a panel. A prop that could not be built is a panel. A player who cannot
-- work out what to do gets the panel when the clock runs out. Answering by doing may
-- never be the reason an event cannot be answered at all.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local PropLabel = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("PropLabel"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local Ground = require(script.Parent.Parent.world.Ground)
local PropModels = require(script.Parent.Parent.world.PropModels)
local Props = require(script.Parent.Parent.content.Props)

type LifeEvent = Types.LifeEvent
type EventChoice = Types.EventChoice
type PropKind = Types.PropKind
type PropVerb = Types.PropVerb
type PropPlacement = Types.PropPlacement

local PROPS = Config.Props

local PropService = {}

-- What floats over something you are meant to pick up. One line for every carried
-- prop there will ever be, and not authored per event on purpose: the three answers
-- to "the last cookie" are the three places you can take it, and if the cookie
-- itself carried one of their labels it would read as a fourth.
local CARRY_LABEL = "Pick it up"

type Staged = {
	kind: PropKind,
	model: Model,
	-- Where it was put. Push measures against this rather than against the player,
	-- so a rug counts as moved when it has actually travelled, not when somebody has
	-- leaned on it for long enough.
	origin: Vector3,
	at: Vector3,
	label: PropLabel.PropLabelHandle?,
	near: boolean,
}

type Watch = {
	choiceId: string,
	verb: PropVerb,
	-- Nil only for a Stay given where the player already is.
	propId: string?,
	toId: string?,
	-- Stay's accumulator, in seconds. Reset rather than paused the moment the player
	-- moves: waiting to be picked up is a thing you are doing, and a bar that
	-- remembered progress across three false starts would let it be done by accident.
	stillFor: number,
}

type Active = {
	eventId: string,
	folder: Folder,
	props: { [string]: Staged },
	watches: { Watch },
	-- Which prop is in the player's arms, if any. One at a time: every Carry in an
	-- event shares its carried object, which is what makes picking it up a commitment
	-- to nothing.
	carrying: string?,
	carryWeld: Weld?,
	-- The label for a prop-less Stay, worn by the player themselves.
	selfLabel: PropLabel.PropLabelHandle?,
	-- Where the player was last tick, for working out how fast they are actually
	-- moving. Taken from displacement rather than from the humanoid's MoveDirection
	-- because that reports intent -- a child walking into a wall is trying to move
	-- and is not moving, and for Stay it is the second that matters.
	lastAt: Vector3?,
	-- When the set starts accepting answers. Everything is visible before then and
	-- nothing is live, so the seconds the player spends reading the banner cannot be
	-- mistaken for the seconds they spend standing still on purpose.
	liveAt: number,
	expiresAt: number?,
	-- Set the moment an answer is taken, before anything is paid out. Everything the
	-- tick does is guarded on it, so a second verb completing on the same frame as
	-- the first cannot also be resolved.
	answered: boolean,
}

local active: { [Player]: Active } = {}

-- Debug switch for the Studio harness, never touched in a live server. Off means
-- every event falls back to its panel, which is also the state to put the game in
-- while testing something that has nothing to do with props.
local enabled = true


local function characterOf(player: Player): (Model?, BasePart?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	return character, root
end

-- Everything one player's event has out lives in one folder, so a Studio session can
-- see the whole set at once and clear the lot if a test left something behind.
local function setFolder(player: Player): Folder
	local folder = Instance.new("Folder")
	folder.Name = `Props_{player.Name}`
	folder.Parent = workspace
	return folder
end

-- Puts a carried prop down, wherever it happens to be, and gives it back to the
-- world. Called on teardown rather than on a change of mind, because there is no
-- changing your mind about having picked something up -- only about where it goes.
local function release(current: Active)
	local weld = current.carryWeld
	if weld ~= nil then
		weld:Destroy()
		current.carryWeld = nil
	end

	local carried = current.carrying
	current.carrying = nil
	if carried == nil then
		return
	end
	local staged = current.props[carried]
	if staged == nil then
		return
	end
	for _, descendant in staged.model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
end

local function teardown(player: Player)
	local current = active[player]
	if current == nil then
		return
	end
	active[player] = nil

	release(current)
	for _, staged in current.props do
		local label = staged.label
		if label ~= nil then
			label.Destroy()
		end
	end
	local selfLabel = current.selfLabel
	if selfLabel ~= nil then
		selfLabel.Destroy()
	end
	current.folder:Destroy()
end

-- The set stays out for a moment after it has been answered, then goes. Short and
-- not zero: a rug that vanishes on the frame it finally gives way takes the answer
-- with it, and the player is left reading an outcome about something they never saw
-- happen.
--
-- Guarded on the event id so a linger started by one event cannot clear the set of
-- the next -- which is a real sequence, because answering a childhood event ends the
-- year and the birthday immediately stages another one.
local function lingerThenTeardown(player: Player, eventId: string)
	task.delay(PROPS.LingerSeconds, function()
		local current = active[player]
		if current ~= nil and current.eventId == eventId then
			teardown(player)
		end
	end)
end

-- Every prop the event needs, and where each one wants to be. Built once so that
-- placement can be tried as a set rather than a prop at a time: an arrangement is
-- only worth keeping if all of it fits.
local function placementsFor(event: LifeEvent): ({ PropPlacement }, boolean)
	local wanted: { PropPlacement } = {}
	local seen: { [string]: boolean } = {}

	local function add(placement: PropPlacement?): boolean
		if placement == nil then
			return true
		end
		if Props.ById[placement.prop] == nil then
			warn(`[AGES] event "{event.id}" names an unknown prop "{placement.prop}"; falling back to a panel`)
			return false
		end
		-- The carried object is declared by every Carry that uses it, so the same id
		-- arriving twice is expected. Content has already checked the repeats agree
		-- with each other; this only has to place it once.
		if not seen[placement.prop] then
			seen[placement.prop] = true
			table.insert(wanted, placement)
		end
		return true
	end

	for _, choice in event.choices do
		local act = choice.act
		if act == nil then
			continue
		end
		if not add(act.at) or not add(act.to) then
			return {}, false
		end
	end
	return wanted, true
end

-- A floor point at this bearing and distance that a body could stand on and get to,
-- or nil. The same three probes every system that puts something on the floor runs,
-- in the same order, for the reasons Ground gives at length.
local function spotAt(
	from: Vector3,
	bearingDegrees: number,
	distance: number,
	radius: number,
	height: number,
	ignore: { Instance }
): Vector3?
	-- Reachability is not optional here whatever the room says. A prop behind a wall,
	-- with an instruction floating over it that the player can read and can never act
	-- on, is worse than one answer fewer -- the event would look broken in a way that is
	-- entirely invisible from the outside.
	local direction = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(-bearingDegrees)) * Vector3.new(0, 0, -1)
	return Ground.SpotAt(from + direction * distance, radius, height, ignore, from)
end

-- How close the straight line from `from` to `to` ever gets to `point`, on the flat.
-- Segment rather than infinite line: a prop the player would only pass if they kept
-- walking past their destination is not on the way to anything.
local function distanceToPath(from: Vector3, to: Vector3, point: Vector3): number
	local start = Vector3.new(from.X, 0, from.Z)
	local finish = Vector3.new(to.X, 0, to.Z)
	local at = Vector3.new(point.X, 0, point.Z)

	local along = finish - start
	local length = along.Magnitude
	if length < 0.01 then
		return (at - start).Magnitude
	end
	local t = math.clamp((at - start):Dot(along) / (length * length), 0, 1)
	return (at - (start + along * t)).Magnitude
end

-- Tries to lay the whole set out along one base bearing, and reports the spots or
-- nothing. All or nothing on purpose: a set with two of its three answers placed is
-- an event the player can only answer two ways, and neither they nor anyone reading
-- a bug report would be able to tell that from the event simply being written that
-- way.
local function layOut(
	wanted: { PropPlacement },
	from: Vector3,
	baseBearing: number,
	radius: number,
	height: number,
	ignore: { Instance }
): { [string]: Vector3 }?
	local placed: { [string]: Vector3 } = {}
	local taken: { { at: Vector3, reach: number } } = {}

	for _, placement in wanted do
		local distance = placement.distance or PROPS.DefaultDistance
		local wish = baseBearing + (placement.offsetDegrees or 0)
		local reach = Props.ById[placement.prop].reachStuds

		local found: Vector3? = nil
		-- Straight out from the authored bearing first, then alternating either side
		-- of it in widening steps, so the arrangement keeps its shape whenever the
		-- room allows and bends only as far as it has to.
		for step = 0, PROPS.NudgeSteps do
			local nudge = (PROPS.NudgeDegrees / PROPS.NudgeSteps) * step
			for _, signed in { nudge, -nudge } do
				local spot = spotAt(from, wish + signed, distance, radius, height, ignore)
				if spot == nil then
					continue
				end
				-- Two rules, and the second is the one that took a bad playtest to
				-- find. The first is the obvious one: two props inside each other's
				-- reach means the player standing at one is standing at both, and the
				-- event answers itself with whichever this loop checked first.
				--
				-- The second is that a prop must not sit beside the walk to another
				-- one. A rug 4.9 studs off the line to the toy has a 5-stud reach, so
				-- crawling to the toy shoves the rug on the way past and takes an
				-- answer the player was not giving -- and from their side nothing
				-- happened except that the game decided for them. Checked both ways,
				-- because this spot can be beside an existing walk or have an existing
				-- prop beside its own.
				--
				-- Content authors the bearings that keep this true, but content cannot
				-- be the guarantee: a wall in the way sends a prop up to NudgeDegrees
				-- off where it was written to be, which is easily far enough to walk it
				-- into somebody else's path.
				local clear = true
				for _, other in taken do
					if Ground.FlatDistance(spot, other.at) < PROPS.MinSeparationStuds then
						clear = false
						break
					end
					if distanceToPath(from, spot, other.at) <= other.reach then
						clear = false
						break
					end
					if distanceToPath(from, other.at, spot) <= reach then
						clear = false
						break
					end
				end
				if clear then
					found = spot
					break
				end
			end
			if found ~= nil then
				break
			end
			if step == 0 then
				-- Zero and minus zero are the same bearing; skip the wasted second probe.
				continue
			end
		end

		if found == nil then
			return nil
		end
		placed[placement.prop] = found
		table.insert(taken, { at = found, reach = reach })
	end

	return placed
end

-- Where every prop goes, or nil when this room cannot hold the arrangement at all.
local function findSpots(character: Model, from: Vector3, wanted: { PropPlacement }): { [string]: Vector3 }?
	if #wanted == 0 then
		return {}
	end

	local ignore = Ground.IgnoreList({ character })
	local radius = Ground.BodyRadius(character)
	local height = Ground.BodyHeight(character)

	-- Straight ahead first, then alternating outward, so the set turns up where the
	-- player is already looking whenever the room allows it.
	for _, bearing in Ground.Bearings(PROPS.ArcDegrees, PROPS.Bearings) do
		local placed = layOut(wanted, from, bearing, radius, height, ignore)
		if placed ~= nil then
			return placed
		end
	end
	return nil
end

-- What the label over a prop should say, given everything the set is watching for.
-- A destination says what taking it there means; the carried object says only that
-- it can be picked up, because its three meanings are the three places it can go.
local function labelFor(watches: { Watch }, propId: string, choiceLabels: { [string]: string }): string?
	for _, watch in watches do
		if watch.toId == propId then
			return choiceLabels[watch.choiceId]
		end
	end
	for _, watch in watches do
		if watch.propId == propId then
			if watch.verb == "Carry" then
				return CARRY_LABEL
			end
			return choiceLabels[watch.choiceId]
		end
	end
	return nil
end

-- Called by EventService at the moment a prompt opens, and the answer decides what
-- the client is told. Returns false for every ordinary reason the room could not
-- hold the question, so callers must not treat false as a fault: it means "this one
-- is a panel", which is always a valid answer.
local function begin(player: Player, event: LifeEvent): boolean
	teardown(player)

	if not enabled then
		return false
	end

	local character, root = characterOf(player)
	if character == nil or root == nil then
		return false
	end

	local watches: { Watch } = {}
	local choiceLabels: { [string]: string } = {}
	for _, choice in event.choices do
		local act = choice.act
		if act == nil then
			continue
		end
		choiceLabels[choice.id] = choice.label
		table.insert(watches, {
			choiceId = choice.id,
			verb = act.verb,
			propId = if act.at ~= nil then act.at.prop else nil,
			toId = if act.to ~= nil then act.to.prop else nil,
			stillFor = 0,
		})
	end
	if #watches == 0 then
		return false
	end

	local wanted, ok = placementsFor(event)
	if not ok then
		return false
	end

	local spots = findSpots(character, root.Position, wanted)
	if spots == nil then
		return false
	end

	local folder = setFolder(player)
	local staged: { [string]: Staged } = {}
	for _, placement in wanted do
		local kind = Props.ById[placement.prop]
		local spot = spots[placement.prop]
		local model = PropModels.Build(kind)
		-- Built with its pivot at the centre of its own underside, so one PivotTo onto
		-- the floor point plus the prop's own lift puts it exactly where it belongs.
		local at = spot + Vector3.new(0, kind.liftStuds, 0)
		model:PivotTo(CFrame.new(at))
		model.Parent = folder

		local text = labelFor(watches, placement.prop, choiceLabels)
		staged[placement.prop] = {
			kind = kind,
			model = model,
			origin = at,
			at = at,
			-- Nil is survivable rather than fatal: a label that could not attach leaves
			-- a prop that still works and is merely harder to find, which is a much
			-- better failure than no prop at all.
			label = if text ~= nil then PropLabel.Attach(model, text, kind.reachStuds) else nil,
			near = false,
		}
	end

	-- A Stay given where the player already is has nothing in the room to be written
	-- over, so it is written over them. Deliberately not put on the floor under their
	-- feet: this game's grammar is that a thing with something to say wears it above
	-- its head, and the player is a thing.
	local selfLabel: PropLabel.PropLabelHandle? = nil
	for _, watch in watches do
		if watch.verb == "Stay" and watch.propId == nil then
			local handle = PropLabel.Attach(character, choiceLabels[watch.choiceId], PROPS.DefaultDistance)
			if handle ~= nil then
				-- Always within reach of itself, so it never gets to be asleep.
				handle.SetNear(true)
				selfLabel = handle
			end
			break
		end
	end

	active[player] = {
		eventId = event.id,
		folder = folder,
		props = staged,
		watches = watches,
		carrying = nil,
		carryWeld = nil,
		selfLabel = selfLabel,
		lastAt = root.Position,
		liveAt = os.clock() + PROPS.GraceSeconds,
		-- 0 means the fallback is off, which is a testing state only -- see the safe
		-- range on SecondsToChoose. Measured from here rather than from liveAt: the
		-- grace is part of the time the player has, not an extension of it.
		expiresAt = if PROPS.SecondsToChoose > 0 then os.clock() + PROPS.SecondsToChoose else nil,
		answered = false,
	}
	return true
end

-- Picks the thing up. Welded to the player rather than moved by the server every
-- tick, which is the one place this file lets physics do something: a weld hands
-- network ownership to the player, so the thing in their arms is exactly as smooth
-- as they are. Anything driven from here would arrive at whatever rate the tick runs
-- at, which is a cookie that stutters.
--
-- The constraints are made here rather than at build time so they capture an offset
-- that is definitely current -- the prop has been placed and possibly pushed since
-- it was built.
local function grab(player: Player, current: Active, propId: string)
	local staged = current.props[propId]
	if staged == nil then
		return
	end
	local character, root = characterOf(player)
	if character == nil or root == nil then
		return
	end
	local primary = staged.model.PrimaryPart
	if primary == nil then
		return
	end

	for _, descendant in staged.model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= primary then
			local hold = Instance.new("WeldConstraint")
			hold.Part0 = primary
			hold.Part1 = descendant
			hold.Parent = primary
		end
	end
	for _, descendant in staged.model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end

	-- A part's LookVector is its own -Z, and the character faces theirs, so the thing
	-- being carried sits at negative Z. Held in front and a little up: that is how a
	-- toddler carries anything, and it is also the only position where the player can
	-- still see what they picked up.
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = primary
	weld.C0 = CFrame.new(0, Ground.BodyHeight(character) * PROPS.CarryHeightFraction, -PROPS.CarryAheadStuds)
	weld.Parent = primary

	current.carrying = propId
	current.carryWeld = weld

	-- It is in their arms. An instruction to pick it up, still floating over it, would
	-- be telling them to do the thing they have just done.
	local label = staged.label
	if label ~= nil then
		label.SetText(nil)
	end
end

-- Shoves the prop along, away from the player, by a share of how far they actually
-- moved. Refused when the new spot is not one a body could stand in, which is what
-- stops a rug being walked through a wall and left there.
local function shove(
	character: Model,
	staged: Staged,
	playerAt: Vector3,
	moved: Vector3
): ()
	local away = Vector3.new(staged.at.X - playerAt.X, 0, staged.at.Z - playerAt.Z)
	if away.Magnitude < 0.05 then
		return
	end
	local direction = away.Unit

	local flatMoved = Vector3.new(moved.X, 0, moved.Z)
	-- Only a shove that was actually toward the thing counts. Walking backwards away
	-- from a rug must not drag it along behind you.
	local into = flatMoved:Dot(direction)
	if into <= 0 then
		return
	end

	local step = direction * (into * PROPS.PushShare)
	local candidate = staged.at + step

	-- No reachability: the prop is being shoved one short step by a player already
	-- touching it, so there is no route to check -- they are standing at both ends of it.
	local ignore = Ground.IgnoreList({ character, staged.model })
	local floor = Ground.SpotAt(candidate, Ground.BodyRadius(character), Ground.BodyHeight(character), ignore)
	if floor == nil then
		return
	end

	staged.at = floor + Vector3.new(0, staged.kind.liftStuds, 0)
	staged.model:PivotTo(CFrame.new(staged.at))
end

-- Takes the answer. Guarded twice over: `answered` stops a second verb completing on
-- the same frame from also being taken, and ResolveChoice itself refuses anything
-- whose event is no longer the player's pending one. Neither guard is redundant --
-- the first is about this tick and the second is about every other way an answer can
-- arrive.
local function resolve(player: Player, current: Active, choiceId: string)
	if current.answered then
		return
	end
	current.answered = true
	EventService.ResolveChoice(player, current.eventId, choiceId)
end

-- Whether the player is near enough to this prop to be doing something with it, and
-- keeping the label's waking-up in step with that answer. One place, so what the
-- player is told and what the game will accept can never disagree.
local function updateNear(staged: Staged, playerAt: Vector3): boolean
	local near = Ground.FlatDistance(playerAt, staged.at) <= staged.kind.reachStuds
	if near ~= staged.near then
		staged.near = near
		local label = staged.label
		if label ~= nil then
			label.SetNear(near)
		end
	end
	return near
end

local function tickPlayer(player: Player, current: Active, delta: number)
	local profile = DataService.GetProfile(player)
	-- The prompt is the authority, not this table. An event answered on a panel, a
	-- player who died, a life that ended, a profile that went away -- all of them show
	-- up here as "the pending id is no longer mine", so there is one condition to get
	-- right rather than a subscription to every service that could have ended it.
	if profile == nil or not Lives.Active(profile.Data).alive or Lives.Active(profile.Data).pendingEventId ~= current.eventId then
		teardown(player)
		return
	end

	local character, root = characterOf(player)
	if character == nil or root == nil then
		return
	end
	local playerAt = root.Position
	local moved = if current.lastAt ~= nil then playerAt - current.lastAt else Vector3.zero
	current.lastAt = playerAt
	local speed = Vector3.new(moved.X, 0, moved.Z).Magnitude / math.max(delta, 0.001)

	local expiresAt = current.expiresAt
	if expiresAt ~= nil and os.clock() >= expiresAt then
		-- The prompt stays open; only the way of answering it changes. Nothing has been
		-- lost and the player is not told off for taking too long -- the panel appears
		-- and every answer is still on it.
		local eventId = current.eventId
		teardown(player)
		EventService.FallBackToPanel(player, eventId)
		return
	end

	local settling = os.clock() < current.liveAt

	for _, watch in current.watches do
		if current.answered then
			return
		end

		local propId = watch.propId
		local staged = if propId ~= nil then current.props[propId] else nil
		if propId ~= nil and staged == nil then
			continue
		end

		-- Still readable, not yet answerable. The labels are kept in step so the set
		-- looks exactly as alive as it will be a second later -- what is withheld is the
		-- answer, not the signposting, because a prop that stayed dim until it was armed
		-- would teach the player that being close to it does nothing.
		if settling then
			if staged ~= nil then
				updateNear(staged, playerAt)
			end
			continue
		end

		if watch.verb == "Go" or watch.verb == "Take" then
			if staged ~= nil and updateNear(staged, playerAt) then
				resolve(player, current, watch.choiceId)
			end
		elseif watch.verb == "Push" then
			if staged ~= nil and updateNear(staged, playerAt) then
				shove(character, staged, playerAt, moved)
				if Ground.FlatDistance(staged.at, staged.origin) >= PROPS.PushStuds then
					resolve(player, current, watch.choiceId)
				end
			end
		elseif watch.verb == "Carry" then
			local toId = watch.toId
			local target = if toId ~= nil then current.props[toId] else nil
			if target == nil then
				continue
			end
			if current.carrying ~= propId then
				-- Not carrying it yet. Picking it up is not an answer to anything, so
				-- nothing is resolved here -- it only becomes possible to answer.
				if staged ~= nil and updateNear(staged, playerAt) and current.carrying == nil then
					grab(player, current, propId :: string)
				end
			elseif updateNear(target, playerAt) then
				resolve(player, current, watch.choiceId)
			end
		elseif watch.verb == "Stay" then
			local inPlace = staged == nil or updateNear(staged, playerAt)
			if inPlace and speed <= PROPS.StillSpeedStuds then
				watch.stillFor += delta
			else
				watch.stillFor = 0
			end

			local label = if staged ~= nil then staged.label else current.selfLabel
			if label ~= nil then
				-- Nil rather than zero when nothing is being held, so a player who moved
				-- off does not leave an empty bar sitting there looking broken.
				label.SetProgress(if watch.stillFor > 0 then watch.stillFor / PROPS.StayStillSeconds else nil)
			end

			if watch.stillFor >= PROPS.StayStillSeconds then
				resolve(player, current, watch.choiceId)
			end
		end
	end
end

local function tick(delta: number)
	if next(active) == nil then
		return
	end
	-- Collected first because tickPlayer can tear its own entry down, and removing a
	-- key mid-traversal is only safe for the key being visited -- a fallback that
	-- restaged something would add one.
	local players: { Player } = {}
	for player in active do
		table.insert(players, player)
	end

	for _, player in players do
		local current = active[player]
		if current == nil then
			continue
		end
		-- One player's set must not stop the next player's, so a fault here is
		-- reported and stepped over rather than taking the loop down.
		local ok, err = pcall(tickPlayer, player, current, delta)
		if not ok then
			warn(`[AGES] prop tick failed for {player.Name}: {err}`)
		end
	end
end

-- Answered, however it was answered -- by doing the thing, on a panel after a
-- fallback, or by the harness forcing it. The set stops being live immediately and
-- goes a moment later.
local function onAnswered(player: Player, event: LifeEvent, _choice: EventChoice)
	local current = active[player]
	if current == nil or current.eventId ~= event.id then
		return
	end
	current.answered = true
	-- Put down before the linger rather than after it: a cookie welded to a player who
	-- is already walking away from an outcome would follow them out of the scene.
	release(current)
	lingerThenTeardown(player, event.id)
end

-- Studio harness: what is out in the room right now, and what it is waiting for.
function PropService.Describe(player: Player): string
	local current = active[player]
	if current == nil then
		return `nothing staged | props {if enabled then "on" else "off"}`
	end

	local parts: { string } = {}
	for _, watch in current.watches do
		local where = watch.propId or "here"
		local staged = if watch.propId ~= nil then current.props[watch.propId] else nil
		local detail = ""
		if watch.verb == "Push" and staged ~= nil then
			detail = string.format(" %.1f/%.0f studs", Ground.FlatDistance(staged.at, staged.origin), PROPS.PushStuds)
		elseif watch.verb == "Stay" then
			detail = string.format(" %.1f/%.1fs", watch.stillFor, PROPS.StayStillSeconds)
		elseif watch.verb == "Carry" then
			detail = if current.carrying == watch.propId then ` held -> {watch.toId}` else ` -> {watch.toId}`
		end
		if staged ~= nil and staged.model.Parent == nil then
			detail ..= " PROP GONE"
		end
		table.insert(parts, `{watch.choiceId}={watch.verb}({where}){detail}`)
	end

	local remaining = if current.expiresAt ~= nil
		then string.format("%.0fs left", math.max(0, current.expiresAt - os.clock()))
		else "no timeout"
	local settling = current.liveAt - os.clock()
	local state = if current.answered
		then "ANSWERED"
		elseif settling > 0 then string.format("settling %.1fs", settling)
		else remaining
	return `"{current.eventId}" | {table.concat(parts, ", ")} | {state}`
end

function PropService.SetEnabled(value: boolean)
	enabled = value
	if value then
		return
	end
	-- Switching off mid-event leaves a prompt whose only way of being answered is
	-- about to stop existing. Hand each one back to its panel rather than stranding
	-- it. Collected first, because falling back must not run inside the traversal.
	local stranded: { { player: Player, eventId: string } } = {}
	for player, current in active do
		table.insert(stranded, { player = player, eventId = current.eventId })
	end
	for _, entry in stranded do
		teardown(entry.player)
		EventService.FallBackToPanel(entry.player, entry.eventId)
	end
end

-- Studio harness: clears every set on the server, for the test that left one behind.
function PropService.ClearAll()
	for _, player in Players:GetPlayers() do
		teardown(player)
	end
end

function PropService:Init()
	-- Injected rather than required the other way around: EventService is what this
	-- calls to resolve a choice, so it must not know about this file.
	EventService.SetActHandler(begin)
end

function PropService:Start()
	EventService.OnAnswered(onAnswered)
	Players.PlayerRemoving:Connect(teardown)

	task.spawn(function()
		while true do
			local delta = task.wait(PROPS.TickSeconds)
			tick(delta)
		end
	end)
end

return PropService
