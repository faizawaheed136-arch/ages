--!strict
-- Answering an event by going to the thing it is about.
--
-- An event authored Enacted is one whose question has something standing in the
-- room behind it -- a dog, and later a vehicle or a machine. This puts three dots
-- over that thing and waits. The player walks across to it, clicks them, and the
-- choices come up. Nothing is answered by being anywhere; what walking buys is the
-- right to be asked.
--
-- That is a smaller job than it sounds and it is deliberately smaller than what was
-- here before. The previous version fanned each choice onto its own patch of floor
-- at its own bearing off the animal, so that walking to "Stand completely still" was
-- physically stepping aside from the dog. It was the most carefully built thing in
-- the game and it was the wrong shape: a Roblox player expects to walk up to a thing
-- and press it, not to read four discs on the carpet and stand in one. The walk to
-- the animal survived the change. The floor did not.
--
-- The division of labour is untouched, and it is the reason the change was cheap.
-- EventService alone decides which event fires and alone validates an answer. This
-- decides only that there is something worth walking to, and hangs an invitation on
-- it. Every answer still arrives through EventService.ResolveChoice, the same
-- function the panel's remote lands in, so there is exactly one place a choice can
-- be paid out and enactment has never been a second way to cheat one.
--
-- Nothing here talks to the client. The dots are a world object -- the client sees
-- them because they are in the workspace, not because they were told -- and the
-- panel they open was already pushed as the event offer. So an enacted event costs
-- one remote message, the same one a panel event costs, and clicking the dots costs
-- none at all.
--
-- Best-effort by design, unchanged in spirit and much rarer in practice. An event
-- with no subject has nothing to hang dots on and is a panel; so is one whose
-- subject could not be built. The timeout below is the last line: an animal that
-- wandered somewhere unreachable, or a player who simply does not want to walk,
-- gets the panel instead. Enactment may never be the reason an event cannot be
-- answered.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Interact = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Interact"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)

type LifeEvent = Types.LifeEvent

local EnactService = {}

-- The verb over the thing. One word for every enacted event there will ever be,
-- because the events are not alike -- a dog running at you and a stranger at the
-- door want different verbs -- and a wrong specific word reads worse than a right
-- vague one. Never drawn under the current style; see Interact.
local ACTION_TEXT = "Decide"

type Active = {
	eventId: string,
	-- The thing the dots are on. Held so the tick can notice it leaving the world,
	-- which is the one way an enactment becomes unanswerable without anybody being
	-- told.
	model: Model,
	dots: Interact.InteractHandle,
	-- os.clock() deadline, or nil when the fallback is switched off. In memory rather
	-- than in the profile: an enactment does not survive a rejoin, so a deadline that
	-- did would be counting down against nothing.
	expiresAt: number?,
}

local active: { [Player]: Active } = {}

-- Debug switch for the Studio harness, never touched in a live server. Off means
-- every event resolves on a panel, which is also the state to put the game in
-- while testing something that has nothing to do with enactment.
local enabled = true

-- Ends an enactment without answering it. Callers that also need the prompt dealt
-- with do that themselves -- this only takes the invitation off the thing.
local function stop(player: Player)
	local current = active[player]
	if current == nil then
		return
	end
	active[player] = nil
	current.dots.Destroy()
end

-- Called by EventService at the moment a prompt opens, and the answer decides what
-- the client is told. Returns false for every ordinary reason there is nothing to
-- walk to, so callers must not treat false as a fault: it means "this one is a
-- panel", which is always a valid answer.
--
-- `subject` is the model the event is about, which is why this is called after the
-- subject is placed rather than before -- the dots hang on it, so it has to exist
-- before they can. Nil means there is nothing to hang them on, which is true of most
-- events.
local function begin(player: Player, event: LifeEvent, subject: Types.StagedSubject?): boolean
	stop(player)

	if not enabled then
		return false
	end
	if subject == nil then
		return false
	end

	local dots = Interact.Attach(subject, {
		kind = "Event",
		id = event.id,
		actionText = ACTION_TEXT,
		objectText = subject.Name,
	})
	if dots == nil then
		-- Not warned about. Interact refuses when the rig has no part to adorn, which
		-- here means the subject is still assembling -- an ordinary race, and the
		-- panel is a complete answer to it.
		return false
	end

	active[player] = {
		eventId = event.id,
		model = subject,
		dots = dots,
		-- 0 means the fallback is off, which is a testing state only -- see the safe
		-- range on SecondsToChoose.
		expiresAt = if Config.Enact.SecondsToChoose > 0
			then os.clock() + Config.Enact.SecondsToChoose
			else nil,
	}
	return true
end

-- Answering a childhood event ends the year, and the birthday that follows may
-- offer -- and enact -- the next one immediately. Adding a key to `active` while it
-- is being traversed is undefined in Lua, so the traversal decides and this list
-- acts, strictly afterwards.
local function tick()
	if next(active) == nil then
		return
	end

	local stranded: { { player: Player, eventId: string } } = {}

	for player, current in active do
		-- The prompt is the authority, not this table. An event answered on a panel, a
		-- player who died, a life that ended, a profile that went away -- all of them
		-- show up here as "the pending id is no longer mine", so there is one condition
		-- to get right instead of a subscription to every service that could have ended
		-- it. Clearing keys mid-traversal is safe; adding is what the list above exists
		-- to avoid.
		local profile = DataService.GetProfile(player)
		if profile == nil or not Lives.Active(profile.Data).alive or Lives.Active(profile.Data).pendingEventId ~= current.eventId then
			stop(player)
			continue
		end

		-- The thing has left the world and taken the dots with it. Rare -- the scene
		-- holds the subject for as long as the prompt is open -- and worth catching
		-- anyway, because the symptom is a question with no visible way to answer it.
		local gone = current.model.Parent == nil
		local late = current.expiresAt ~= nil and os.clock() >= current.expiresAt
		if gone or late then
			-- The prompt stays open; only the way of answering it changes. The player has
			-- not lost anything and is not told off for taking too long -- the panel simply
			-- appears and the choices are still all there.
			stop(player)
			table.insert(stranded, { player = player, eventId = current.eventId })
		end
	end

	for _, entry in stranded do
		EventService.FallBackToPanel(entry.player, entry.eventId)
	end
end

-- Answered, however it was answered. Takes the dots down on the same frame rather
-- than leaving them for the tick to notice, because the outcome is on screen
-- immediately and three dots still bobbing over the dog under it would be an
-- invitation to answer a question that is already settled.
local function onAnswered(player: Player, _event: LifeEvent, _choice: Types.EventChoice)
	stop(player)
end

-- Studio harness: what is standing in the room right now.
function EnactService.Describe(player: Player): string
	local current = active[player]
	if current == nil then
		return `nothing enacted | enactment {if enabled then "on" else "off"}`
	end

	local remaining = if current.expiresAt ~= nil
		then string.format("%.0fs left", math.max(0, current.expiresAt - os.clock()))
		else "no timeout"
	-- Whether the thing is still there is the first question about an enactment that
	-- feels broken, because a subject that left is the one failure that looks exactly
	-- like the dots never having been attached.
	local where = if current.model.Parent ~= nil then `dots on "{current.model.Name}"` else "SUBJECT GONE"
	return `"{current.eventId}" | {where} | {remaining}`
end

function EnactService.SetEnabled(value: boolean)
	enabled = value
	if value then
		return
	end
	-- Switching off mid-enactment leaves a prompt whose only way of being answered is
	-- about to stop existing. Hand each one back to its panel rather than stranding
	-- it. Collected first for the reason tick() collects: falling back must not run
	-- inside the traversal.
	local stranded: { { player: Player, eventId: string } } = {}
	for player, current in active do
		table.insert(stranded, { player = player, eventId = current.eventId })
	end
	for _, entry in stranded do
		stop(entry.player)
		EventService.FallBackToPanel(entry.player, entry.eventId)
	end
end

function EnactService:Init()
	-- Injected rather than required the other way around: EventService is what this
	-- calls to resolve a choice, so it must not know about this file.
	EventService.SetEnactHandler(begin)
end

function EnactService:Start()
	EventService.OnAnswered(onAnswered)
	Players.PlayerRemoving:Connect(stop)

	task.spawn(function()
		while true do
			task.wait(Config.Enact.TickSeconds)
			tick()
		end
	end)
end

return EnactService
