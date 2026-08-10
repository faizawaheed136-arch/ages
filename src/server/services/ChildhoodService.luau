--!strict
-- The first five years, as something you do rather than something you are told.
--
-- Every other age in AGES has a verb. You walk to the shop and clock on, you sit in a
-- lesson and answer, you cross a room to your mother and she says something back. Nought
-- to five had none: the events were authored `Memory`, which means they were handed over
-- the instant the birthday landed, answered on a panel from a standstill, and then
-- nothing happened for fifteen seconds until the next one was handed over too. A small body in an empty room, reading. That is a montage with
-- a walk speed, and it was the first thing a new player ever saw.
--
-- What this does instead, and it is one sentence: the event is put across the room and
-- you have to get there.
--
--   Something appears on the floor some way off, with a few words over it and a line
--   pointing at it. You crawl to it. When you arrive it opens -- the dog walks in with
--   three dots over its head -- and answering it makes you a year older. Then the next
--   thing appears, and it is already there by the time the last one has finished.
--
-- Almost none of that is new machinery, which is the reason to do it this way. The scene,
-- the pads, the line, the year advancing on an answer -- all of it already worked and was
-- simply never reached, because the event never had anywhere to be. This gives it
-- somewhere to be.
--
-- Three things it is careful about:
--
--   The floor is found, not authored. A `Wander` event needs no tagged prop, which is what
--   separates it from `Interact` and is the entire reason it exists: a childhood that
--   required twenty-two hand-placed objects would be a childhood that does not work until
--   somebody dresses the house, and the opening five minutes of the game cannot be the
--   part that is waiting on art.
--
--   The distance does the growing up. The same twelve-to-twenty-eight studs is a long haul
--   at the Crawl band's speed of 4 and a short one at Run's 13, so the world gets smaller
--   as the body gets better without a single number being shown to anyone.
--
--   There is never nothing. The next thing is staged off the last one clearing rather than
--   off a timer, so the only quiet in childhood is the four seconds an outcome takes to
--   read. Idle time inside an activity is the bug this file was written to fix, and
--   re-introducing it as a "pacing beat" would be the same bug with a better name.
--
-- The guide line is shared with WorkService, which points a jobless sixteen-year-old at
-- the shop. They cannot both be talking: this only runs to Config.Childhood.EndAge and
-- that only starts at the minimum working age. If a third claimant ever appears the line
-- needs an owner rather than a third writer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local ChoiceMarkers = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("ChoiceMarkers"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local Ground = require(script.Parent.Parent.world.Ground)

type LifeData = Types.LifeData
type LifeEvent = Types.LifeEvent
type ChoiceMarker = ChoiceMarkers.ChoiceMarker

local ChildhoodService = {}

local GuideUpdatedRemote = Remotes.Get("GuideUpdated")

local WANDER = Config.Childhood.Wander

-- What is standing in the room for one player, waiting to be reached.
type Lure = {
	eventId: string,
	label: string,
	at: Vector3,
	marker: ChoiceMarker,
}

local lures: { [Player]: Lure } = {}

-- When the next one may be staged. Set the moment a prompt closes rather than the moment
-- one opens, so a player who takes a minute over an answer does not also serve the beat.
local readyAt: { [Player]: number } = {}

-- Whether a prompt was open last tick, which is the only way to notice one closing without
-- EventService having to announce it. Polled rather than pushed on purpose: the profile
-- field is the truth either way, and a callback would be a second thing to keep in step.
local wasPending: { [Player]: boolean } = {}

-- What the guide is currently pointing at, so an unchanged line is not re-sent four times
-- a second. Same reason WorkService keeps one.
local guided: { [Player]: string? } = {}

-- Studio harness switch. Off leaves the toddler in an empty house, which is how a body or
-- a places bug is told apart from a childhood one.
local enabled = true

local function ageYearsOf(data: LifeData): number
	return data.ageMonths // Config.Time.MonthsPerYear
end


-- Everything childhood puts on the floor lives in one folder, so a Studio session can see
-- what is out there and clear the lot if a test left something behind.
local function lureFolder(): Folder
	local existing = workspace:FindFirstChild("ChildhoodLures")
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "ChildhoodLures"
	folder.Parent = workspace
	return folder
end

local function setGuide(player: Player, lure: Lure?)
	local id = if lure ~= nil then lure.eventId else nil
	if guided[player] == id then
		return
	end
	guided[player] = id

	if lure == nil then
		GuideUpdatedRemote:FireClient(player, { target = nil, label = nil })
		return
	end
	GuideUpdatedRemote:FireClient(player, { target = lure.at, label = lure.label })
end

-- Takes down whatever is standing in the room and stops pointing at it. Safe to call on a
-- player who has nothing out, which is most of them most of the time.
local function clearLure(player: Player)
	local lure = lures[player]
	if lure ~= nil then
		lure.marker.destroy()
		lures[player] = nil
	end
	setGuide(player, nil)
end

-- A piece of floor the player could actually get to, or nil if this room has none.
--
-- Swept as rings rather than as a single circle because the far ring in a small bedroom is
-- entirely inside the walls, and a toddler's world is small rooms. Distance is preferred
-- over closeness -- the crawl is the mechanic, and a lure placed at arm's length is the old
-- behaviour wearing a pad -- but direction is picked at random within whichever ring is
-- reached, because "the furthest spot in the room" is the same corner every time and a
-- childhood spent crawling into one corner is not a childhood.
--
-- Nil is genuinely possible and genuinely rare: a closet with the door shut. Every room
-- larger than the player gets a spot, because after the rings comes FallbackStuds.
local function spotFor(character: Model, from: Vector3): Vector3?
	local ignore = Ground.IgnoreList({ character })
	local radius = Ground.BodyRadius(character)
	local height = Ground.BodyHeight(character)

	local bearings = Ground.Bearings(360, WANDER.Bearings)

	-- Every spot at one distance that the player could actually get to.
	local function ringAt(distance: number): { Vector3 }
		local found: { Vector3 } = {}
		for _, bearing in bearings do
			local direction = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(-bearing)) * Vector3.new(0, 0, -1)
			-- Reachability from where the toddler is, and it is the check that matters
			-- most here of the three: a thing behind a wall with a line pointing through
			-- the wall is worse than no thing at all. The player follows the line into
			-- plaster and concludes the game is broken, which on that evidence is a
			-- reasonable conclusion.
			local floor = Ground.SpotAt(from + direction * distance, radius, height, ignore, from)
			if floor ~= nil then
				table.insert(found, floor)
			end
		end
		return found
	end

	-- Outermost ring first, so distance is preferred, and a coin toss between the
	-- bearings that ring found, so direction is not.
	local span = WANDER.FarStuds - WANDER.NearStuds
	for ring = WANDER.Rings, 1, -1 do
		-- Rings-1 in the divisor so the last ring lands exactly on FarStuds rather
		-- than short of it, and a single ring is simply the near one.
		local share = if WANDER.Rings <= 1 then 0 else (ring - 1) / (WANDER.Rings - 1)
		local found = ringAt(WANDER.NearStuds + span * share)
		if #found > 0 then
			return found[math.random(#found)]
		end
	end

	-- Only now, and only because the alternative is an empty room forever.
	local close = ringAt(WANDER.FallbackStuds)
	if #close > 0 then
		return close[math.random(#close)]
	end
	return nil
end

local function characterOf(player: Player): (Model?, Vector3?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	return character, root.Position
end

-- Puts the next thing in the room. Returns false when there was nothing to stage or
-- nowhere to stage it, and the caller simply tries again next tick -- both are ordinary
-- and neither is worth a warning four times a second.
local function stage(player: Player, data: LifeData): boolean
	local character, position = characterOf(player)
	if character == nil or position == nil then
		return false
	end

	local event = EventService.PickStageable(player, "Wandered")
	if event == nil then
		return false
	end

	local spot = spotFor(character, position)
	if spot == nil then
		return false
	end

	-- Claimed in the profile before anything is built, so a rejoin mid-childhood finds the
	-- same event waiting rather than rolling a fresh one -- and so DeliveryService, which
	-- reads the same field, does not stage a letter on top of it.
	data.deliveringEventId = event.id

	local label = event.lure or WANDER.DefaultLure
	local marker = ChoiceMarkers.Build(lureFolder(), spot, WANDER.ReachStuds, {
		label = label,
		-- Never locked. Nothing here is refused: the pad is somewhere to crawl to.
		locked = false,
	})

	local lure: Lure = { eventId = event.id, label = label, at = spot, marker = marker }
	lures[player] = lure
	setGuide(player, lure)
	return true
end

-- Reached. Opens the prompt exactly the way a tagged object in the world does, which is
-- what keeps a wandered event and an anchored one the same kind of thing.
local function reach(player: Player, data: LifeData, lure: Lure)
	clearLure(player)

	-- Spawned rather than called: offering builds the scene, which yields, and this runs
	-- inside the loop that ticks every player. One toddler waiting on a model to assemble
	-- must not be every toddler on the server waiting with them.
	--
	-- Safe to leave the loop running underneath it because the lure is already down and the
	-- claim is still set, so the next tick returns at the pending-or-claimed guard and
	-- cannot stage a second thing or offer this one twice.
	task.spawn(function()
		if EventService.OfferIfEligible(player, lure.eventId) then
			return
		end
		-- Every ordinary reason -- aged past it since it was staged, already lived, a
		-- prompt open -- and none of them is a fault. The claim is dropped so the next
		-- tick can stage something the player can actually have.
		if data.deliveringEventId == lure.eventId then
			data.deliveringEventId = nil
		end
	end)
end

local function tickPlayer(player: Player, now: number)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)

	-- Noticed before anything else, because a prompt closing is what starts the beat and
	-- it can close on a tick where the player is also dying or growing out of childhood.
	local pending = data.pendingEventId ~= nil
	if wasPending[player] and not pending then
		readyAt[player] = now + WANDER.NextSeconds
	end
	wasPending[player] = pending

	if not enabled or not data.alive or ageYearsOf(data) > Config.Childhood.EndAge then
		clearLure(player)
		return
	end

	local lure = lures[player]
	if lure ~= nil then
		-- The prompt opened some other way -- forced from the harness, or another lure
		-- reached on the way over. Whatever is out there is now the answer to
		-- a question that is already being asked, so it comes down.
		if pending or data.deliveringEventId ~= lure.eventId then
			clearLure(player)
			return
		end

		local _, position = characterOf(player)
		if position == nil then
			return
		end
		if Ground.FlatDistance(position, lure.at) <= WANDER.ReachStuds then
			reach(player, data, lure)
		end
		return
	end

	if pending or data.deliveringEventId ~= nil then
		return
	end
	if now < (readyAt[player] or 0) then
		return
	end

	stage(player, data)
end

local function forget(player: Player)
	clearLure(player)
	readyAt[player] = nil
	wasPending[player] = nil
	guided[player] = nil
end

-- A new life, or the end of one. Called by LifeService at both ends for the same reason
-- PeopleService is: a thing on the floor inviting a dead child across the room is the
-- worst frame this system could draw.
function ChildhoodService.ResetForNewLife(player: Player)
	clearLure(player)
	readyAt[player] = nil
	wasPending[player] = nil
end

-- Studio harness: puts the next thing out now, without waiting for the beat.
function ChildhoodService.ForceStage(player: Player): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	clearLure(player)
	readyAt[player] = 0
	return stage(player, Lives.Active(profile.Data))
end

function ChildhoodService.SetEnabled(value: boolean)
	enabled = value
	for _, player in Players:GetPlayers() do
		if not value then
			clearLure(player)
		end
	end
end

function ChildhoodService.IsEnabled(): boolean
	return enabled
end

-- What the harness prints. The one question this system generates is "why is there nothing
-- in the room", and there are exactly four answers: too old for it, a prompt is already
-- open, nothing is left unlived at this age, or there is nowhere in this room to put one.
-- All four are said out loud here rather than left to be inferred from an empty floor.
function ChildhoodService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "childhood: no profile loaded"
	end
	local data = Lives.Active(profile.Data)
	local age = ageYearsOf(data)

	local out = "nothing out"
	local lure = lures[player]
	if lure ~= nil then
		local _, position = characterOf(player)
		local away = if position ~= nil then string.format("%.1f studs away", Ground.FlatDistance(position, lure.at)) else "nowhere to measure from"
		out = `"{lure.eventId}" out, {away} (reach {WANDER.ReachStuds})`
	end

	local why = ""
	if lure == nil then
		if age > Config.Childhood.EndAge then
			why = `; age {age} is past {Config.Childhood.EndAge}, so childhood is over`
		elseif data.pendingEventId ~= nil then
			why = `; "{data.pendingEventId}" is already being asked`
		elseif data.deliveringEventId ~= nil then
			why = `; "{data.deliveringEventId}" is claimed but not on the floor`
		elseif os.clock() < (readyAt[player] or 0) then
			why = `; {string.format("%.1f", (readyAt[player] or 0) - os.clock())}s of beat left`
		elseif EventService.PickStageable(player, "Wandered") == nil then
			why = `; nothing unlived is written for age {age}`
		else
			why = "; nowhere in this room to put one"
		end
	end

	return string.format(
		"childhood: %s | age %d | %s%s",
		if enabled then "enabled" else "DISABLED",
		age,
		out,
		why
	)
end

function ChildhoodService:Start()
	Players.PlayerRemoving:Connect(forget)

	task.spawn(function()
		while true do
			task.wait(WANDER.TickSeconds)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				-- One player's empty room must not stop the next player's, so a fault
				-- here is reported and stepped over rather than taking the loop down.
				local ok, err = pcall(tickPlayer, player, now)
				if not ok then
					warn(`[AGES] childhood tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

return ChildhoodService
