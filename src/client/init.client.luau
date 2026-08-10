--!strict
-- Client bootstrap. The client only ever displays state pushed by the
-- server over Remotes — it never computes stats, age, or death itself.
-- Pressing Age Up sends a bare request; the server decides the outcome.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local StatsUI = require(script.ui.StatsUI)
local ChoicePanel = require(script.ui.ChoicePanel)
local LabUI = require(script.ui.LabUI)
local Guide = require(script.world.Guide)
local JobPosts = require(script.world.JobPosts)
local TaskMark = require(script.world.TaskMark)
local Prompts = require(script.world.Prompts)
local LabDots = require(script.world.LabDots)

type Stats = Types.Stats
type AgeUpCause = Types.AgeUpCause
type ManualAgeUpState = Types.ManualAgeUpState
type OfferedEvent = Types.OfferedEvent
type ShiftState = Types.ShiftState
type GuideState = Types.GuideState
type JobPostState = Types.JobPostState
type TaskState = Types.TaskState
type LessonState = Types.LessonState
type PersonState = Types.PersonState
type WorkoutState = Types.WorkoutState
type PersonRosterEntry = Types.PersonRosterEntry
type LabState = Types.LabState

-- SetCoreGuiEnabled throws while the core scripts are still loading, so this
-- retries for a few frames instead of giving up on the first attempt.
local CORE_GUI_RETRY_ATTEMPTS = 10

-- The HUD occupies the top-right corner, which is where the player list would
-- otherwise render on top of it.
local function hidePlayerList()
	for _ = 1, CORE_GUI_RETRY_ATTEMPTS do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		if ok then
			return
		end
		task.wait()
	end
	warn("AGES: could not hide the player list; it may overlap the HUD")
end

-- Spawned rather than awaited: retrying here on the main thread would delay the
-- remote connections below past the server's initial state push.
task.spawn(hidePlayerList)

local ui = StatsUI.new()
local panel = ChoicePanel.new()
local lab = LabUI.new()
local guide = Guide.new()
local jobPosts = JobPosts.Board()
local taskMark = TaskMark.new()
local prompts = Prompts.new()
local labDots = LabDots.new()

-- Nothing is known yet, and a HUD is a claim that a life is being lived. It goes up the
-- moment the server names a life stage, which it only does for a life that has begun --
-- see LifeService.pushInitialState. Starting it up and taking it down again a beat later
-- would make every new player's first sight of AGES a flicker.
ui:SetHudVisible(false)

local RequestAgeUpRemote = Remotes.Get("RequestAgeUp")
local RequestEventChoiceRemote = Remotes.Get("RequestEventChoice")
local RequestPersonOfferRemote = Remotes.Get("RequestPersonOffer")
local RequestPersonContactRemote = Remotes.Get("RequestPersonContact")
local RequestLessonAnswerRemote = Remotes.Get("RequestLessonAnswer")
local RequestReturnToLobbyRemote = Remotes.Get("RequestReturnToLobby")
local RequestStartWorkoutRemote = Remotes.Get("RequestStartWorkout")
local RequestRepRemote = Remotes.Get("RequestRep")
local RequestLabStepRemote = Remotes.Get("RequestLabStep")
local RequestLabUndoRemote = Remotes.Get("RequestLabUndo")
local RequestLabCommitRemote = Remotes.Get("RequestLabCommit")

-- The last thing the server said about the person in front of the player. Held
-- because the panel is opened by clicking three dots in the world, and that click
-- carries an id and nothing else -- everything it needs to draw was pushed here
-- already, when the row on the HUD was drawn.
local currentPerson: PersonState? = nil

ui:OnAgeUpActivated(function()
	RequestAgeUpRemote:FireServer()
end)

ui:OnPushActivated(function()
	RequestRepRemote:FireServer()
end)

panel:OnChoice(function(eventId: string, choiceId: string)
	RequestEventChoiceRemote:FireServer(eventId, choiceId)
end)

-- The only way out of this place, pressed off the death screen. The button does not take the
-- screen down and does not go grey: the answer to it is the place going away, and anything
-- else drawn in the meantime would be this client guessing at a teleport it cannot see.
ui:OnReturnActivated(function()
	RequestReturnToLobbyRemote:FireServer()
end)

-- Clicking the dots on whatever an event is about. The words are already on screen
-- as a banner; this is the player having gone over to the thing they are about.
prompts:On("Event", function(eventId: string)
	panel:OpenEnacted(eventId)
end)

-- Clicking the dots over somebody's head. The panel opens straight off the state the
-- HUD already pushed -- the standing person's offers are the ones drawn there -- and
-- anything else goes to the server, which is the same fallback the roster uses. That
-- second path matters more than it looks: the server pushes the standing person on a
-- beat, and a tap that lands in the gap between walking up and the push arriving would
-- otherwise be a dead click on a person who is plainly standing there.
prompts:On("Person", function(personId: string)
	local person = currentPerson
	if person ~= nil and person.id == personId and #person.offers > 0 then
		panel:ShowOptions({
			key = personId,
			prompt = person.name,
			options = person.offers,
			choose = function(offerId: string)
				RequestPersonOfferRemote:FireServer(personId, offerId)
			end,
		})
		return
	end
	RequestPersonContactRemote:FireServer(personId)
end)

-- Clicking the dots on a piece of lab equipment. A station is the one interactable in
-- the game that is not a *conversation* -- there is nothing to read and nothing to pick
-- from, because the choice was made at the board and this is the player carrying it out.
-- So it opens no panel at all: the click is the step.
--
-- The station id is the whole payload. Which bench it lands on, whether the player is
-- close enough, and whether there is a reagent left to spend are all the server's to
-- answer, because all three can have changed since this client was last told anything.
prompts:On("Station", function(stationId: string)
	RequestLabStepRemote:FireServer(stationId)
end)

-- Undo and Commit, off the panel rather than off anything in the world. Both are things
-- you do *to the bench you are standing at*, and the bench already has the player's
-- attention -- putting them on dots would mean walking up to a bench, clicking it to
-- open a menu, and picking "commit" from a list of one.
--
-- The bench index comes from the panel, which got it from the last push. The server
-- re-checks it against where the player actually is, so a stale index is refused rather
-- than acted on.
lab:OnUndo(function(benchIndex: number)
	RequestLabUndoRemote:FireServer(benchIndex)
end)

lab:OnCommit(function(benchIndex: number)
	RequestLabCommitRemote:FireServer(benchIndex)
end)

-- The lesson panel, which is the one panel in the game nobody clicks anything to
-- open. The question is put up and taken down by the server's pushes: answers on it
-- means a question is live, no answers means the teacher is explaining the last one
-- or the lesson is over. See SchoolService for why a lesson gets no dots.
--
-- Keyed by which question is up rather than by the lesson, so an answer that arrives
-- late -- the player clicked as the clock ran out -- is refused by the server against
-- a question that has already moved on.
--
-- The open key is held here because closing has to name what it is closing: between a
-- question expiring and the next push, a birthday can have put an event on screen,
-- and a lesson must never take down somebody else's panel.
local lessonPanelKey: string? = nil

local function drawLessonPanel(state: LessonState?)
	local wanted = if state ~= nil and #state.answers > 0 then `lesson:{state.index}` else nil

	local open = lessonPanelKey
	if open ~= nil and open ~= wanted then
		panel:CloseOptions(open)
		lessonPanelKey = nil
	end

	if state == nil or wanted == nil or lessonPanelKey == wanted then
		return
	end

	local index = state.index
	-- Only remembered as open if it actually opened. A refusal -- an outcome still
	-- being read -- is retried by the next push, which arrives four times a second
	-- because the clock on the row is part of what is being sent.
	--
	-- A physical lesson's rows are locked and the answers are discs on the floor, so
	-- the panel adds the line that says where the real answer is. The hint rides the
	-- question rather than being assumed, because a question the floor refused falls
	-- back to ordinary clickable rows and must not keep the instruction.
	if panel:ShowOptions({
		key = wanted,
		prompt = state.ask,
		options = state.answers,
		hint = if state.physical then "Walk to the disc with your answer." else nil,
		choose = function(answerId: string)
			RequestLessonAnswerRemote:FireServer(index, answerId)
		end,
	}) then
		lessonPanelKey = wanted
	end
end

-- A conversation that has no body to walk to: the person was called from the roster,
-- so it opens in the phone's voice rather than as somebody standing in the room. Same
-- offers, same answers -- the phone is a window, not a different person.
--
-- Held the same way a lesson is, because the panel is one physical thing and a birthday
-- can put a lesson or an event over it: the open key is what lets a push that has no
-- business touching the phone know it is not the phone that is up.
local phonePanelKey: string? = nil

local function drawPhonePanel(state: PersonState)
	local key = `phone:{state.id}`
	if state.reply ~= nil then
		panel:ShowOutcome(key, state.reply)
		return
	end
	-- The remembered key can go stale: a lesson or an event takes the panel over by
	-- overwriting it, and those shows do not announce themselves. So the skip requires
	-- not just "we opened this once" but "this key is still the one the panel holds" --
	-- otherwise the second tap on the same person would find the remembered key and
	-- silently do nothing.
	if phonePanelKey == key and panel:IsOpen(key) then
		return
	end
	if #state.offers == 0 then
		return
	end
	if panel:ShowOptions({
		key = key,
		prompt = state.name,
		options = state.offers,
		phone = true,
		choose = function(offerId: string)
			RequestPersonOfferRemote:FireServer(state.id, offerId)
		end,
	}) then
		phonePanelKey = key
	end
end

-- The phone panel can be closed by things that are not the phone -- a lesson push, an
-- event, a death -- and those do not carry a phone-specific close signal. `OnHidden`
-- fires on any full teardown, which is the one case where the remembered key would
-- otherwise sit stale and swallow the next call's panel.
panel:OnHidden(function(key: string)
	if phonePanelKey ~= nil and phonePanelKey == key then
		phonePanelKey = nil
	end
	if workoutPanelKey ~= nil and workoutPanelKey == key then
		workoutPanelKey = nil
	end
end)

-- The workout offer panel, which opens when the player stands near a machine
-- that is not capped. Closed by pressing Start (server validates proximity
-- and cap again) or Leave. Walked-away-then-back re-opens it, because the
-- server pushes a fresh offer once the digest changes.
--
-- Held the same way a phone or a lesson panel is: between an offer closing
-- and a new push, a birthday can have put a different panel on screen, and
-- the workout must not take down something it did not raise.
local workoutPanelKey: string? = nil

local function drawWorkoutPanel(state: WorkoutState?)
	local wanted = if state ~= nil and state.phase == "offer" then "workout:offer" else nil

	local open = workoutPanelKey
	if open ~= nil and open ~= wanted then
		panel:CloseOptions(open)
		workoutPanelKey = nil
	end

	if state == nil or wanted == nil or workoutPanelKey == wanted then
		return
	end

	if panel:ShowOptions({
		key = wanted,
		prompt = state.machineLabel,
		options = {
			{ id = "start", label = "Start a workout", locked = false },
			{ id = "leave", label = "Leave", locked = false },
		},
		choose = function(choiceId: string)
			-- Close first so the panel never lingers while the server
			-- validates. Refused starts return a notice instead of a
			-- state change; the panel stays down and the player reads why.
			panel:CloseOptions(wanted)
			workoutPanelKey = nil
			if choiceId == "start" then
				RequestStartWorkoutRemote:FireServer(state.machine)
			end
		end,
	}) then
		workoutPanelKey = wanted
	end
end

Remotes.Get("EventOffered").OnClientEvent:Connect(function(offered: OfferedEvent)
	panel:Show(offered)
end)

Remotes.Get("EventResolved").OnClientEvent:Connect(function(eventId: string, outcome: string)
	panel:ShowOutcome(eventId, outcome)
end)

Remotes.Get("StatsUpdated").OnClientEvent:Connect(function(stats: Stats)
	ui:SetStats(stats)
end)

-- One number, pushed on join and on every movement. There is no request for it and
-- nothing to reconcile: whatever arrived last is the balance.
Remotes.Get("MoneyUpdated").OnClientEvent:Connect(function(balance: number)
	ui:SetMoney(balance)
end)

-- A whole snapshot each time rather than a delta, so a dropped push is corrected
-- by the next one instead of leaving the row permanently a few dollars out.
Remotes.Get("ShiftUpdated").OnClientEvent:Connect(function(state: ShiftState)
	ui:SetShift(state)
end)

-- A finished sentence the server wants said now -- the first of them is "you've been
-- let go". Shown on the same transient banner an auto age-up already raises; the client
-- only displays it, because it is news it could not have drawn off any state it holds.
Remotes.Get("Notice").OnClientEvent:Connect(function(text: string)
	ui:ShowNotice(text)
end)

-- Where to go next, if anywhere. Nearly always nowhere: this fires when a life gains
-- a reason to walk somewhere it has never been, which happens perhaps twice.
Remotes.Get("GuideUpdated").OnClientEvent:Connect(function(state: GuideState)
	guide:Set(state)
end)

-- The hiring signs and their marks, as a whole list. Drawn here rather than by the
-- server because a post is an offer: the one thing it has to do is stop existing for
-- the player who accepted it, and a single sign in the workspace is seen by everyone
-- in the room. The list arriving without a job on it is what takes that job's sign
-- down, and it is why taking a job makes the mark under your feet disappear.
Remotes.Get("JobPostsUpdated").OnClientEvent:Connect(function(states: { JobPostState })
	jobPosts.Set(states)
end)

-- The things you are doing right now, inside the shift you are already on. Two
-- displays of one fact: a row on the HUD per task saying what it is and how long is
-- left, and a lit mark on the floor per task saying where.
--
-- Both driven from the same push rather than from two, because they are never allowed
-- to disagree: a mark on the floor with no row above it is a player who has no idea
-- why they are being sent somewhere, and a row with no mark is a player being told to
-- hurry to nowhere. An empty list clears both, which is the state between tasks and the
-- state of almost every minute of almost every life.
--
-- The whole set arrives every time, never one task at a time, because both halves below
-- are written as "here is everything that should be true now" rather than as edits. With
-- two live tasks that stops being a style choice: an update about one of them would
-- leave this guessing which of two discs it was about.
Remotes.Get("TaskUpdated").OnClientEvent:Connect(function(states: { TaskState })
	ui:SetTasks(states)
	-- The one case where the two halves deliberately part company: a missed task keeps
	-- its row for a few seconds to say so, and loses its mark immediately, because
	-- there is no longer anywhere worth walking to. Leaving the disc lit would be the
	-- game still pointing at a spot it has stopped rewarding -- and now that a second
	-- task is usually still running, it would be pointing the player away from the one
	-- thing they can still save.
	local marks: { TaskMark.Mark } = {}
	for _, state in states do
		if not state.missed then
			table.insert(marks, { id = state.id, spot = state.spot, label = state.mark })
		end
	end
	taskMark.Set(marks)
end)

-- The lesson you are sitting. Kept here as well as drawn, because the answers ride
-- along with the question now and the panel is built from them the moment the player
-- clicks the dots on the board.
Remotes.Get("LessonUpdated").OnClientEvent:Connect(function(state: LessonState?)
	ui:SetLesson(state)
	drawLessonPanel(state)
end)

-- The workout in progress, or an offer to start one. Two halves of one thing:
-- the push updates the HUD row (the sweep bar, the rep counter, the PUSH
-- button) and opens or closes the offer panel on the machine you are standing
-- at. Nil is the usual state: most of a life has no workout in it, and a
-- silent HUD is the right HUD when nothing is being asked of the player.
Remotes.Get("WorkoutUpdated").OnClientEvent:Connect(function(state: WorkoutState?)
	ui:SetWorkout(state)
	drawWorkoutPanel(state)
end)

-- The Science lab in progress. Two halves of one fact, and they are driven from the same
-- push precisely so they cannot disagree: the panel says what the procedure is, and the
-- dots on the stations say whether the room is currently something you can act on. A lit
-- beaker with no panel up would be an invitation the server would refuse.
Remotes.Get("LabUpdated").OnClientEvent:Connect(function(state: LabState?)
	lab:Set(state)
	labDots:SetRunning(state ~= nil and state.summary == nil)
end)

-- Who you are standing next to, and what they have to offer. The row keeps saying who
-- it is long after there is anything left to take, because a person you are standing
-- next to is still there when the conversation is over.
Remotes.Get("PersonUpdated").OnClientEvent:Connect(function(state: PersonState?)
	currentPerson = state
	if state ~= nil and state.contact then
		-- A phone call, not a person in the room: it gets the phone panel rather than
		-- the standing row, which would otherwise claim somebody is next to you.
		drawPhonePanel(state)
		return
	end
	if phonePanelKey ~= nil then
		panel:CloseOptions(phonePanelKey)
		phonePanelKey = nil
	end
	ui:SetPerson(state)
end)

-- Who you know and what they have left, as a whole list for the HUD. Whole rather
-- than per-row for the same reason the server sends it whole: the rows are read side
-- by side, and a per-person push could land out of order and leave one dot wrong.
Remotes.Get("PeopleRosterUpdated").OnClientEvent:Connect(function(entries: { PersonRosterEntry })
	ui:SetRoster(entries)
end)

-- A name tapped on the roster. If it is the person already standing in front of the
-- player, the standing panel opens directly; otherwise the request goes up and the
-- phone panel comes back in the reply.
ui:OnPersonTapped(function(personId: string)
	local person = currentPerson
	if person ~= nil and person.id == personId and #person.offers > 0 then
		panel:ShowOptions({
			key = personId,
			prompt = person.name,
			options = person.offers,
			choose = function(offerId: string)
				RequestPersonOfferRemote:FireServer(personId, offerId)
			end,
		})
		return
	end
	RequestPersonContactRemote:FireServer(personId)
end)

Remotes.Get("AgeUpdated").OnClientEvent:Connect(function(years: number, cause: AgeUpCause)
	ui:SetAge(years)
	if cause == "Auto" then
		ui:ShowNotice("A year has passed while you were living your life...")
	end
end)

Remotes.Get("AgeUpProgress").OnClientEvent:Connect(function(seconds: number, thresholdSeconds: number, state: ManualAgeUpState)
	ui:SetAgeUpProgress(seconds, thresholdSeconds, state)
end)

-- Also the signal that there is a life at all. The server only names a stage for a profile
-- that has been set up, so this arriving means the menu's work is done -- on a fresh join
-- into a life already under way, where no menu was ever raised, and on the first push of a
-- life that has just been chosen. Both want the same thing: the HUD back.
Remotes.Get("LifeStageChanged").OnClientEvent:Connect(function(stage: string)
	ui:SetStage(stage)
	ui:SetHudVisible(true)
end)

-- The last thing this place ever says about this life.
--
-- Nothing takes this screen down again. There is no `PlayerRespawned` to pair with it any
-- more and no menu behind it to be revealed -- a life ends where it was lived and stays
-- there, and what happens next is a teleport back to the lobby, either because the player
-- pressed the button or because the server sent them after the delay. Everything belonging
-- to the life comes down under it, because the screen is translucent and a choice panel
-- still standing behind a death notice is a decision nobody can make any more. The HUD is
-- the deliberate exception: it stays up, showing the stats and the age this person finished
-- on, which is the only thing on screen worth reading while the summary holds.
Remotes.Get("PlayerDied").OnClientEvent:Connect(function(ageYears: number)
	panel:Hide()
	-- The lab comes down with everything else. The server drops the session on death and
	-- pushes nil, but the order of those two arriving is not guaranteed, and a bench
	-- clock still counting down under a death notice would be the game insisting there is
	-- something left to hurry for.
	lab:Set(nil)
	labDots:SetRunning(false)
	currentPerson = nil
	lessonPanelKey = nil
	phonePanelKey = nil
	workoutPanelKey = nil
	ui:ShowDeath(ageYears)
end)

-- The trip back did not happen. Almost always Studio, where teleports do not work at all, or
-- an unpublished lobby place id -- so this is read far more often by a developer than by a
-- player, and it goes on the death screen itself rather than into the log for exactly that
-- reason: the alternative is a button that appears to do nothing.
Remotes.Get("ReturnRefused").OnClientEvent:Connect(function(reason: string)
	ui:ShowReturnRefusal(reason)
end)
