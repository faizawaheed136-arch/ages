--!strict
-- Client bootstrap. The client only ever displays state pushed by the
-- server over Remotes — it never computes stats, age, or death itself.
-- Pressing Age Up sends a bare request; the server decides the outcome.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Money = require(ReplicatedStorage:WaitForChild("Money"))

local StatsUI = require(script.ui.StatsUI)
local ChoicePanel = require(script.ui.ChoicePanel)
local LabUI = require(script.ui.LabUI)
local HuntUI = require(script.ui.HuntUI)
local EaselUI = require(script.ui.EaselUI)
local HeatUI = require(script.ui.HeatUI)
local TillUI = require(script.ui.TillUI)
local BankUI = require(script.ui.BankUI)
local GangUI = require(script.ui.GangUI)
local FightUI = require(script.ui.FightUI)
local HouseUI = require(script.ui.HouseUI)
local CarDealerUI = require(script.ui.CarDealerUI)
local SavingsUI = require(script.ui.SavingsUI)
local MenuUI = require(script.ui.MenuUI)
local Minimap = require(script.ui.Minimap)
local MapUI = require(script.ui.MapUI)
local ChapterReel = require(script.ui.ChapterReel)
local MoneyPop = require(script.world.MoneyPop)
local BonusPop = require(script.world.BonusPop)
local MilestoneFlash = require(script.world.MilestoneFlash)
local BondCelebration = require(script.world.BondCelebration)
local Guide = require(script.world.Guide)
local JobPosts = require(script.world.JobPosts)
local TaskMark = require(script.world.TaskMark)
local Prompts = require(script.world.Prompts)
local LabDots = require(script.world.LabDots)
local SearchRing = require(script.world.SearchRing)
local DealerMark = require(script.world.DealerMark)

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
type HuntState = Types.HuntState
type ArtState = Types.ArtState
type BountyState = Types.BountyState
type TheftState = Types.TheftState
type BankState = Types.BankState
type GangState = Types.GangState
type GangPanel = Types.GangPanel
type ReportCard = Types.ReportCard
type FightState = Types.FightState

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
local hunt = HuntUI.new()
local easel = EaselUI.new()
local guide = Guide.new()
local jobPosts = JobPosts.Board()
local taskMark = TaskMark.new()
local prompts = Prompts.new()
local labDots = LabDots.new()
local heat = HeatUI.new()
local searchRing = SearchRing.new()
local till = TillUI.new()
local bank = BankUI.new()
local gang = GangUI.new()
local fight = FightUI.new()
local house = HouseUI.new()
local carDealer = CarDealerUI.new()
local savings = SavingsUI.new()
local menu = MenuUI.new()
local minimap = Minimap.new()
local mapSheet = MapUI.new()
local dealerMark = DealerMark.new()
local chapterReel = ChapterReel.new()

-- Nothing is known yet, and a HUD is a claim that a life is being lived. It goes up the
-- moment the server names a life stage, which it only does for a life that has begun --
-- see LifeService.pushInitialState. Starting it up and taking it down again a beat later
-- would make every new player's first sight of AGES a flicker.
ui:SetHudVisible(false)
-- The menu rail is down for the same reason and comes back on the same push. A rail of
-- tiles is a smaller claim than a HUD but it is the same claim.
menu:SetVisible(false)

local RequestAgeUpRemote = Remotes.Get("RequestAgeUp")
local RequestSetSettingRemote = Remotes.Get("RequestSetSetting")
local RequestRedeemCodeRemote = Remotes.Get("RequestRedeemCode")
local RequestEventChoiceRemote = Remotes.Get("RequestEventChoice")
local RequestPersonOfferRemote = Remotes.Get("RequestPersonOffer")
local RequestPersonContactRemote = Remotes.Get("RequestPersonContact")
local RequestLessonAnswerRemote = Remotes.Get("RequestLessonAnswer")
local RequestReportCardReadRemote = Remotes.Get("RequestReportCardRead")
local RequestReturnToLobbyRemote = Remotes.Get("RequestReturnToLobby")
local RequestStartWorkoutRemote = Remotes.Get("RequestStartWorkout")
local RequestRepRemote = Remotes.Get("RequestRep")
local RequestLabStepRemote = Remotes.Get("RequestLabStep")
local RequestLabUndoRemote = Remotes.Get("RequestLabUndo")
local RequestLabCommitRemote = Remotes.Get("RequestLabCommit")
local RequestArtPaintRemote = Remotes.Get("RequestArtPaint")
local RequestArtSignRemote = Remotes.Get("RequestArtSign")
local RequestTillOpenRemote = Remotes.Get("RequestTillOpen")
local RequestTillHoldRemote = Remotes.Get("RequestTillHold")
local RequestBankOpenRemote = Remotes.Get("RequestBankOpen")
local RequestBankHoldRemote = Remotes.Get("RequestBankHold")
local RequestGangOpenRemote = Remotes.Get("RequestGangOpen")
local RequestGangChoiceRemote = Remotes.Get("RequestGangChoice")
local RequestGangColorsRemote = Remotes.Get("RequestGangColors")
local RequestFightSquareRemote = Remotes.Get("RequestFightSquare")
local RequestFightActionRemote = Remotes.Get("RequestFightAction")
local RequestBuyHouseRemote = Remotes.Get("RequestBuyHouse")
local RequestSellHouseRemote = Remotes.Get("RequestSellHouse")
local RequestCarDealerServeRemote = Remotes.Get("RequestCarDealerServe")
local RequestToggleApartmentDoorRemote = Remotes.Get("RequestToggleApartmentDoor")

-- The last thing the server said about the person in front of the player. Held
-- because the panel is opened by clicking three dots in the world, and that click
-- carries an id and nothing else -- everything it needs to draw was pushed here
-- already, when the row on the HUD was drawn.
local currentPerson: PersonState? = nil

-- The three figures on the menu's player card, held because they arrive on three
-- separate pushes and the card draws all of them at once. Nothing derives anything from
-- these -- StatsUI is still told each figure directly by the same handler -- so a stale
-- one costs the card a wrong line and nothing else.
local cardAge = 0
local cardStage = ""
local cardMoney = 0

-- What the player has turned on, as this client last heard it.
--
-- Every one of these starts at the value that reproduces the game as it played before
-- Settings existed, and is overwritten by the first `SettingsUpdated` -- which arrives on
-- join, before the world has finished streaming in. The window in which a preference is
-- wrong is therefore the same window in which there is nothing on screen to be wrong
-- about, and starting from the old behaviour rather than from the Config default keeps
-- the two ends from having to agree about what a default is.
local settingAgeUpConfirm = false
local settingMoneyPops = true
local settingCelebrations = true

-- Applied by name. An explicit arm per id rather than a table of handlers, so that a
-- setting added to Config and forgotten here is a crash on the first push with the id in
-- the message -- rather than a switch that ships, draws, saves, and does nothing.
local function applySetting(id: string, on: boolean)
	if id == "ageUpConfirm" then
		settingAgeUpConfirm = on
	elseif id == "minimap" then
		minimap:SetHidden(not on)
	elseif id == "moneyPops" then
		settingMoneyPops = on
	elseif id == "celebrations" then
		settingCelebrations = on
	else
		error(`client: no effect wired for setting "{id}". Add an arm to applySetting or remove it from Config.Settings.Options.`)
	end
end

ui:OnAgeUpActivated(function()
	if not settingAgeUpConfirm then
		RequestAgeUpRemote:FireServer()
		return
	end
	-- The same panel every other decision in this game is made on, rather than a bespoke
	-- dialog. A year is spent by picking a row off a list here exactly like a job or a gang
	-- rung is taken, and the confirm is worth nothing if it does not look like the rest of
	-- the game's yes.
	panel:ShowOptions({
		key = "ageUpConfirm",
		prompt = `Age up to {cardAge + 1}?`,
		options = {
			{ id = "yes", label = "Age up", note = "+1 year", locked = false },
			{ id = "no", label = "Not yet", locked = false },
		},
		hint = "A year passes as soon as you say so. Nothing you had planned for this one is waiting for you afterwards.",
		choose = function(choiceId: string)
			if choiceId == "yes" then
				RequestAgeUpRemote:FireServer()
			end
		end,
	})
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

-- Clicking the dots on a drawer. Unlike a station this opens something, and unlike a
-- person what it opens is not a list of choices -- it is the counter itself, with one
-- control on it that has to be held. The click is walking up to the till and nothing more,
-- which is why the payload is the place id and why no money can possibly move on it.
prompts:On("Till", function(place: string)
	RequestTillOpenRemote:FireServer(place)
end)

-- Hands in, hands out. Off the panel rather than off the dots, because a hold is not
-- something you can do to three dots -- and because the release has to be able to happen
-- when the player has already looked away from the drawer to watch the clerk.
till:OnHold(function(holding: boolean)
	RequestTillHoldRemote:FireServer(holding)
end)

-- Clicking the dots on a vault door. Its own kind rather than a Till with a different id,
-- because the client dispatches on kind alone and a vault that called itself a Till would
-- open a shop panel over a bank -- a bug that would look exactly like the alarm not being
-- wired up. Like the till, the click only ever puts the player *in* the room: nothing is
-- taken and nothing is tripped until something is held.
prompts:On("Vault", function(place: string)
	RequestBankOpenRemote:FireServer(place)
end)

-- Clicking the dots over the head of the person who runs a gang. Its own kind rather than
-- a Person, because the client dispatches on kind alone and a boss registered as a Person
-- would open the ordinary chat panel over them -- a panel whose rows are the offers the
-- *server* pushed for whoever you are standing next to, which for a boss is nobody. The
-- symptom would be a person you can talk to who has nothing to say.
--
-- Unlike a person, nothing is drawn off held state: the request goes up and the panel comes
-- back. That is not an oversight -- what a boss says depends on your standing with *them*,
-- which is four numbers the HUD has no row for and no reason to hold.
prompts:On("Boss", function(gangId: string)
	RequestGangOpenRemote:FireServer(gangId)
end)

-- Clicking the dots over the head of somebody who wants a fight. Its own kind for the same
-- reason a boss is: dispatch is by kind alone, so a fighter registered as a Person would
-- open the ordinary chat panel over somebody who is about to swing at you.
--
-- The id goes up and the server checks it against the opponent actually stood in front of
-- this player rather than looking it up in the content table -- so this being a value the
-- client chose does not let the client choose who it is fighting, or conjure a second one.
prompts:On("Fight", function(fighterId: string)
	RequestFightSquareRemote:FireServer(fighterId)
end)

-- Clicking the dots on an apartment entrance door. Opens or closes it -- the server
-- animates the swing and validates distance. The click is the whole answer, no panel.
prompts:On("Apartment", function(blockName: string)
	RequestToggleApartmentDoorRemote:FireServer(blockName)
end)

-- Clicking the dots at the car dealership counter. Its own kind so the client
-- dispatches on type rather than id: a dealership dot registered as a Station
-- would open a lab panel over a sales floor, and nobody wants that confusion.
prompts:On("Dealer", function()
	carDealer:Open()
end)

-- The three answers, and all three go up as bare requests: what a strike is worth is
-- decided entirely by how long the *server* saw the button held, not by anything sent from
-- here. A client that sent a power value would be a client that could send 1.0 every time.
--
-- Strike and guard send their held state on both edges. The release is the half that
-- matters -- it is what commits a charge -- so FightUI is careful to have exactly one path
-- that can change a hold, and every way a hold can end runs through it.
fight:OnStrike(function(held: boolean)
	RequestFightActionRemote:FireServer("strike", held)
end)

fight:OnGuard(function(held: boolean)
	RequestFightActionRemote:FireServer("guard", held)
end)

fight:OnSidestep(function()
	RequestFightActionRemote:FireServer("sidestep")
end)

-- One boolean for both of the room's controls, and which one it means is never named here.
-- The server decides from where the player is standing, because a client that could say
-- "silence" while stood at the vault would delete the walk that is the entire activity.
bank:OnHold(function(holding: boolean)
	RequestBankHoldRemote:FireServer(holding)
end)

house:OnBuyHouse(function(houseId: string)
	RequestBuyHouseRemote:FireServer(houseId)
end)

house:OnSellHouse(function(houseId: string)
	RequestSellHouseRemote:FireServer(houseId)
end)

house:OnSetHomeJob(function(houseId: string)
	local RequestSetHomeJobRemote = Remotes.Get("RequestSetHomeJob")
	RequestSetHomeJobRemote:FireServer(houseId, "")
end)

local RequestDepositRemote = Remotes.Get("RequestDeposit")
local RequestWithdrawRemote = Remotes.Get("RequestWithdraw")

-- Declared here rather than beside the pushes that fill them, six hundred lines down, and
-- that is the whole fix: these three buttons read them, and a Lua closure captures the
-- *local in scope at the point the closure is written*. There was no local in scope here,
-- so all three read a global that nothing ever assigns, every one of them saw nil, and every
-- deposit and withdraw in the game was a button that lit up, clicked, and did nothing.
--
-- Nothing said so. `--!strict` is happy -- an unbound name is a legal read of a nil global --
-- the remotes exist, the server handlers exist and work, and the UI gives no feedback for a
-- press that fires nothing. `tools/check.py`'s "names read but never bound" pass is the only
-- thing in the tree that could see it.
--
-- Both are the *last pushed* value, not a request: money and savings are pushed whole on
-- every change, so whatever arrived last is the balance and there is nothing to reconcile.
-- The server re-checks the amount anyway, so a stale number is refused rather than acted on.
local moneyPrevious: number? = nil
local savingsBalance: number? = nil

savings:OnDepositAll(function()
	if moneyPrevious ~= nil and moneyPrevious > 0 then
		RequestDepositRemote:FireServer(moneyPrevious)
	end
end)

savings:OnDepositHalf(function()
	if moneyPrevious ~= nil and moneyPrevious > 0 then
		RequestDepositRemote:FireServer(math.floor(moneyPrevious / 2))
	end
end)

savings:OnWithdrawAll(function()
	if savingsBalance ~= nil and savingsBalance > 0 then
		RequestWithdrawRemote:FireServer(savingsBalance)
	end
end)

carDealer:OnServe(function()
	RequestCarDealerServeRemote:FireServer()
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

-- A square of the canvas and the tube in hand. Off the panel for the same reason Undo
-- and Commit are, only more so: sixteen cells and up to eight tubes is twenty-four things
-- to click, and putting any of them in the world would mean a player choosing a colour by
-- walking up to it.
--
-- Both numbers are the client's opinion and neither is trusted. The server re-checks the
-- cell is on the canvas, the pigment is one this player was actually handed, that they are
-- standing at the easel and that there is paint left -- and refuses with a line rather than
-- silently, because a brush that sometimes does nothing is the worst thing this verb could
-- feel like.
easel.onPaint = function(cellIndex: number, pigmentId: string)
	RequestArtPaintRemote:FireServer(cellIndex, pigmentId)
end

-- Handing the canvas in early, which is a real decision here rather than a formality:
-- the study keeps moving while you hold it, so twelve good cells now can be worth more
-- than sixteen with four gone stale.
easel.onSign = function()
	RequestArtSignRemote:FireServer()
end

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

-- Last year's report card, handed over at the school. The one panel in the game that is
-- not a question: every row but the last is locked, because the rows *are* the news --
-- what was on, how it went, what it paid -- and the only thing to press is the one that
-- says you have read it.
--
-- Keyed on the year rather than on the card, so a birthday landing while the previous
-- year's card is still on screen replaces it rather than being swallowed by an open key
-- that happens to match. Held for the same reason every other panel key here is held:
-- taking the panel down has to name what it is taking down, and an event can have arrived
-- over the top in between.
local reportPanelKey: string? = nil

local function drawReportCard(card: ReportCard?)
	local wanted = if card ~= nil then `report:{card.ageYears}` else nil

	local open = reportPanelKey
	if open ~= nil and open ~= wanted then
		panel:CloseOptions(open)
		reportPanelKey = nil
	end

	if card == nil or wanted == nil or reportPanelKey == wanted then
		return
	end

	if panel:ShowOptions({
		key = wanted,
		prompt = card.title,
		options = card.rows,
		-- Empty for a first card, which has no record behind it and nothing close --
		-- passed as nil rather than as a blank string so the label is hidden rather than
		-- reserving a line of nothing under the rows.
		hint = if card.footnote ~= "" then card.footnote else nil,
		-- The row id is not sent, because there is only one pressable row and "which"
		-- is not a question. The *year* is, and the server checks it against the card it
		-- has staged: a birthday landing while this panel is up replaces the card, and a
		-- press already on its way from the old one must not clear the new one unread.
		choose = function()
			RequestReportCardReadRemote:FireServer(card.ageYears)
		end,
	}) then
		reportPanelKey = wanted
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
		prompt = state.contextualLine or state.name,
		options = state.offers,
		phone = true,
		choose = function(offerId: string)
			RequestPersonOfferRemote:FireServer(state.id, offerId)
		end,
	}) then
		phonePanelKey = key
	end
end

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

-- The person who runs a gang, talking. Raised and taken down entirely by the server: it
-- goes up when the player clicks the dots and standing in front of them is what keeps it
-- there, so walking off closes it without this client sending anything.
--
-- Deliberately re-shown on *every* push rather than skipped when the key is unchanged, which
-- is the opposite of what the workout panel does. The difference is that this panel's rows
-- change while the player stands still and the key does not: the rejoin countdown ticks down
-- to a row that unlocks, and standing crossing a rung turns "412 more" into a rung you can
-- take. The server already filters -- see GangService.pushPanel, whose digest carries every
-- row's locked flag and note -- so a push arriving *is* the news that something moved.
--
-- The reply goes in the prompt rather than the hint because it is the fiction, and the
-- speaker's name goes underneath because the nameplate over their head has already
-- answered "who" by the time anybody has read this far.
local gangPanelKey: string? = nil

local function drawGangPanel(state: GangPanel?)
	local wanted = if state ~= nil then `gang:{state.gangId}` else nil

	local open = gangPanelKey
	if open ~= nil and open ~= wanted then
		panel:CloseOptions(open)
		gangPanelKey = nil
	end

	if state == nil or wanted == nil then
		return
	end

	if panel:ShowOptions({
		key = wanted,
		prompt = state.reply,
		options = state.offers,
		hint = `{state.bossName} · {state.name}`,
		-- Their color when the news is good, and the panel's own when it is not. One
		-- channel with one meaning -- whether this gang is currently on your side -- rather
		-- than a gang color that is always on and therefore says nothing. `replyGood` is
		-- the server's judgement of its own sentence, so a rewritten line cannot end up
		-- tinted against what it says.
		accent = if state.replyGood then state.color else nil,
		choose = function(choiceId: string)
			RequestGangChoiceRemote:FireServer(state.gangId, choiceId)
		end,
	}) then
		gangPanelKey = wanted
	end
end

-- A panel can be closed by something that is not the thing that opened it -- a lesson
-- push, an event, a death -- and none of those carry a close signal the phone, the workout
-- or the report card would recognize. `OnHidden` fires on any full teardown, which is the
-- one case where a remembered key would otherwise sit stale and silently swallow the next
-- push that wanted the panel.
--
-- **Deliberately placed below every key it clears, and this is not a style choice.** A name
-- used with no `local` in scope compiles to a *global* read in Lua rather than an error, so
-- when this block sat above `workoutPanelKey` it read a global that was always nil, the
-- workout branch never once ran, and the exact staleness this exists to prevent was live
-- the whole time. Nothing warns about it. Any key added here has to be declared above.
panel:OnHidden(function(key: string)
	if phonePanelKey ~= nil and phonePanelKey == key then
		phonePanelKey = nil
	end
	if workoutPanelKey ~= nil and workoutPanelKey == key then
		workoutPanelKey = nil
	end
	if reportPanelKey ~= nil and reportPanelKey == key then
		reportPanelKey = nil
	end
	if gangPanelKey ~= nil and gangPanelKey == key then
		gangPanelKey = nil
	end
end)

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
-- nothing to reconcile: whatever arrived last is the balance. The client also
-- tracks the previous balance so it can show a directional pop for every change --
-- and the savings panel's deposit buttons spend it, which is why `moneyPrevious` is
-- declared up beside them rather than here.
Remotes.Get("MoneyUpdated").OnClientEvent:Connect(function(balance: number, reason: string?)
	local previous = moneyPrevious
	moneyPrevious = balance
	ui:SetMoney(balance)
	cardMoney = balance
	menu:SetIdentity(cardAge, cardStage, cardMoney)
	if previous ~= nil then
		local delta = balance - previous
		if delta ~= 0 and settingMoneyPops then
			MoneyPop.Show(nil, delta)
			if reason ~= nil then
				BonusPop.Show(nil, math.abs(delta), reason)
			end
		end
	end
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
	menu:SetJobs(states)
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

-- The report card, raised and taken down entirely by the server: it goes up when the
-- player is standing at the school with an uncollected one, and comes down when they press
-- Continue or walk off. Nothing on this client asks for it -- there is nothing to click,
-- because arriving is the click.
--
-- No HUD half to go with it, unlike a lesson or a workout. A card is a thing you read once
-- and are finished with; a row saying "you have a report card" would still be there three
-- years later, which is what a HUD row is for and this is not.
Remotes.Get("ReportCardUpdated").OnClientEvent:Connect(function(card: ReportCard?)
	drawReportCard(card)
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

-- The Geography errand in progress. One half of one fact, which makes it the shortest
-- handler here and the point is that it stays that way: there is no second half in the
-- world, no dots to light and no mark to drop. The panel is the whole interface, because
-- the town is the rest of it.
Remotes.Get("HuntUpdated").OnClientEvent:Connect(function(state: HuntState?)
	hunt:Set(state)
end)

-- The fight in progress. One half of one fact, and the other half is the opponent
-- themselves -- who is stood in front of the player, winding up, in the world. That is
-- deliberate and it is why the tell is drawn twice: the panel's bar is the precise one and
-- the body is the readable one, and a player should be able to learn to fight off either.
--
-- Nothing is drawn on the floor. Every other destination in the game is a lit disc, but a
-- fight has no destination -- the whole of it happens inside twelve studs of where you are
-- already standing, and a marker under somebody's feet would be marking the obvious.
Remotes.Get("FightUpdated").OnClientEvent:Connect(function(state: FightState?)
	fight:Set(state)
end)

-- The canvas in progress. As short as the hunt's and for a different reason: the other
-- half of this fact is already in the world and is not ours to draw. The study on the wall
-- is built by the server as parts, shared by everybody in the room, and it changes by a
-- part changing colour with nothing announcing it. There is deliberately no client-side
-- flash, outline or marker to go with a shift -- lighting up the cell that moved would
-- hand over the one thing this subject is asking the player to find for themselves.
Remotes.Get("ArtUpdated").OnClientEvent:Connect(function(state: ArtState?)
	easel:Set(state)
end)

-- How much of the town is looking for you. Two halves of one fact, driven from the one
-- push for the same reason the lab's two halves are: the bar says how bad it is, the ring
-- on the street says where they think you are, and a bar reading "manhunt" over a ring
-- that had stopped moving would be the game lying about the only thing the player can
-- actually act on.
--
-- The ring is fed the state's own `lastKnown`, which is a *belief* and not a position --
-- see BountyService, which never once reads where the player really is. Anything here
-- that substituted the local character's position for it would delete the entire system
-- while leaving every panel on screen looking perfectly correct.
-- The drawer in front of you. One half of one fact and it stays that way: the clerk and
-- the camera are already in the room, moving, and the panel says only where they are
-- pointed this second. There is deliberately nothing drawn in the world to go with this --
-- no highlight on the till, no arc showing the camera's cone -- because the whole verb is
-- reading two things that were always going to be visible anyway.
Remotes.Get("TheftUpdated").OnClientEvent:Connect(function(state: TheftState?)
	till:Set(state)
end)

-- The bank room you are in. Unlike the till there *is* something drawn in the world to go
-- with this -- the lamp on the alarm panel and the vault door swinging as it empties -- and
-- that is not an inconsistency: those two are shared facts about a room that a second
-- player has to be able to read without a panel of their own.
Remotes.Get("BankUpdated").OnClientEvent:Connect(function(state: BankState?)
	bank:Set(state)
end)

-- Who you run with. Nil for most players and most of most lives, and nil is the state that
-- takes the corner back -- there is no "you are in no gang" row, because a HUD row is a
-- claim that something is going on and not being in a gang is not going on.
--
-- One half of one fact here, and the other half is not drawn by this client at all: it is
-- the band on your own head, which is a part in the world built by the server because
-- everybody else in the room has to be able to read it too. That split is the same one the
-- lab and the search ring make, and it is why the panel says "COLORS ON" rather than
-- drawing a swatch and calling it done -- the swatch would be a picture of a hat the player
-- is already wearing.
Remotes.Get("GangUpdated").OnClientEvent:Connect(function(state: GangState?)
	gang:Set(state)
	menu:SetGang(state)
end)

Remotes.Get("GangPanelUpdated").OnClientEvent:Connect(function(state: GangPanel?)
	drawGangPanel(state)
end)

-- The band, on or off. The only button in the game that makes the player easier to
-- describe: it is asked for here and answered by the server, which is why the panel never
-- flips its own switch -- see GangUI's Activated handler.
gang:OnColorsToggled(function(want: boolean)
	RequestGangColorsRemote:FireServer(want)
end)

-- The world, once. Sent when the server has resolved every place and measured the bounds,
-- which happens after the town is built and therefore later than this script runs -- so both
-- surfaces sit blank rather than drawing an empty world, and come up together when it lands.
-- The full sheet builds its region wash off this push and the minimap builds its markers,
-- both of which are expensive and both of which are done exactly once.
Remotes.Get("MapData").OnClientEvent:Connect(function(data: Types.MapData)
	minimap:SetMapData(data)
	mapSheet:SetMapData(data)
end)

-- Where the player is standing, in whose ground, and how far in. Pushed on a beat by
-- TerritoryService rather than computed here: the client has no list of gang bosses and no
-- business deciding whose side it is on, because that answer is what the standing mechanic
-- charges for.
Remotes.Get("TerritoryUpdated").OnClientEvent:Connect(function(state: Types.TerritoryState?)
	minimap:SetTerritory(state)
	mapSheet:SetTerritory(state)
end)

-- Clicking the dial opens the sheet. The minimap does not know the sheet exists -- it is a
-- dial with a button on it and one callback out -- which is what lets the sheet be opened
-- from a key as well without either of them growing a reference to the other.
minimap:SetOnOpen(function()
	mapSheet:Toggle()
end)

-- What the player has got good at. Six rows, pushed whole on every award, which is
-- cheap because an award is a thing somebody just did rather than a thing on a clock.
Remotes.Get("SkillsUpdated").OnClientEvent:Connect(function(state: Types.SkillsState)
	menu:SetSkills(state)
end)

-- The band, asked for from the menu instead of the corner panel. Same remote and the
-- same rule: the menu never flips its own switch, because the server decides whether a
-- player is wearing anything.
menu:OnColorsToggled(function(want: boolean)
	RequestGangColorsRemote:FireServer(want)
end)

-- M, and Escape to close. Safe to claim: nothing else in this client binds a key at all --
-- every other interaction in the game is a tap on a three-dot marker or a button -- so there
-- is no rebinding to do and nothing to collide with. GameProcessedEvent is honoured so that
-- typing an M into the chat bar does not throw the map over the conversation.
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.M then
		mapSheet:Toggle()
	elseif input.KeyCode == Enum.KeyCode.Tab then
		menu:Toggle()
	elseif input.KeyCode == Enum.KeyCode.Escape then
		-- One at a time, map first, because the map draws over the menu and closing the
		-- thing underneath the thing you are looking at is not what Escape means.
		if mapSheet:IsOpen() then
			mapSheet:Close()
		else
			menu:Close()
		end
	end
end)

Remotes.Get("BountyUpdated").OnClientEvent:Connect(function(state: BountyState?)
	heat:Set(state)
	if state == nil then
		searchRing.Set(nil, 0, false)
		return
	end
	searchRing.Set(state.lastKnown, state.searchRadiusStuds, state.seen)
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

Remotes.Get("HouseUpdated").OnClientEvent:Connect(function(state: Types.HouseState?)
	house:Set(state)
	menu:SetHouse(state)
end)

Remotes.Get("CarDealerUpdated").OnClientEvent:Connect(function(state: Types.CarDealerState?)
	carDealer:Set(state)
	ui:SetCarDealer(state)
	if state ~= nil then
		dealerMark:Set(state.counter)
	else
		dealerMark:Set(nil)
	end
end)

Remotes.Get("BillDue").OnClientEvent:Connect(function(state: Types.BillState?)
	menu:SetBill(state)
end)

-- `savingsBalance` is declared beside the withdraw button that spends it. Read off the
-- pushed snapshot rather than accumulated, so a dropped push is corrected by the next one.
Remotes.Get("SavingsUpdated").OnClientEvent:Connect(function(state: Types.SavingsState?)
	-- The parameter is optional and was indexed unconditionally. Nothing sends nil today,
	-- so this never fired -- but a nil push is the one that clears the panel, and it would
	-- have thrown here and left the *old* balance on screen and in the withdraw button.
	savingsBalance = if state ~= nil then state.balance else nil
	menu:SetSavings(state)
	savings:Set(state)
end)

Remotes.Get("MilestoneAchieved").OnClientEvent:Connect(function(event: Types.MilestoneEvent)
	if settingCelebrations then
		MilestoneFlash.Show(event.label, event.bonus)
	end
	-- Outside the branch on purpose. Turning celebrations off is a request for less screen,
	-- not for less information, and the notice line is what is left when the fanfare goes.
	ui:ShowNotice(`Milestone: {event.label}! +{Money.Format(event.bonus)}`)
end)

Remotes.Get("BondMilestone").OnClientEvent:Connect(function(event: Types.BondMilestoneEvent)
	if settingCelebrations then
		BondCelebration.Show(event.person, event.label)
		return
	end
	ui:ShowNotice(`{event.person} is now your {string.lower(event.label)}.`)
end)

Remotes.Get("GossipUpdate").OnClientEvent:Connect(function(event: Types.GossipEvent)
	ui:ShowNotice(`The townsfolk are talking about: "{event.topics}"`)
end)

-- Who you know and what they have left, as a whole list for the menu's Relationships
-- tab. Whole rather than per-row for the same reason the server sends it whole: the rows
-- are read side by side, and a per-person push could land out of order and leave one dot
-- wrong. It is pushed even while the menu is shut -- the list has to be right the instant
-- it opens, and a roster that fills in a frame late reads as a bug.
Remotes.Get("PeopleRosterUpdated").OnClientEvent:Connect(function(entries: { PersonRosterEntry })
	menu:SetRoster(entries)
end)

-- A name tapped in the Relationships tab. If it is the person already standing in front
-- of the player, the standing panel opens directly; otherwise the request goes up and the
-- phone panel comes back in the reply -- which is the only way to reach somebody who is
-- not in front of you, so it survived the move off the HUD unchanged.
menu:OnPersonTapped(function(personId: string)
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

-- Preferences. Applied *and* drawn from the same push, which is what keeps the switch on
-- screen and the behaviour behind it from ever disagreeing: there is one arrival, and both
-- halves happen inside it.
--
-- The client never applies what it clicked. Clicking sends a request and nothing else, and
-- the row does not move until this handler runs -- so a preference that failed to save is a
-- switch that visibly did not flip, rather than one that flipped and lied.
Remotes.Get("SettingsUpdated").OnClientEvent:Connect(function(state: Types.SettingsState)
	for _, option in state.settings do
		applySetting(option.id, option.on)
	end
	menu:SetSettings(state)
end)

menu:OnSettingToggled(function(id: string, on: boolean)
	RequestSetSettingRemote:FireServer(id, on)
end)

Remotes.Get("CodesUpdated").OnClientEvent:Connect(function(state: Types.CodesState)
	menu:SetCodes(state)
end)

-- The answer to one attempt, shown on the pane the player typed into rather than on the
-- HUD banner. A refusal belongs next to the box that caused it: the banner is for news the
-- world sent, and this is a reply to something the player just did with their hands.
Remotes.Get("CodeResult").OnClientEvent:Connect(function(result: Types.CodeResult)
	menu:SetCodeResult(result.ok, result.message)
end)

menu:OnCodeSubmitted(function(code: string)
	RequestRedeemCodeRemote:FireServer(code)
end)

Remotes.Get("AgeUpdated").OnClientEvent:Connect(function(years: number, cause: AgeUpCause)
	ui:SetAge(years)
	cardAge = years
	menu:SetIdentity(cardAge, cardStage, cardMoney)
	if cause == "Auto" then
		ui:ShowNotice("A year has passed while you were living your life...")
	end
end)

Remotes.Get("AgeUpProgress").OnClientEvent:Connect(function(seconds: number, thresholdSeconds: number, state: ManualAgeUpState)
	ui:SetAgeUpProgress(seconds, thresholdSeconds, state)
end)

-- The chapter seam: a band boundary has been reached and the shared "what happened"
-- query has produced a list of moments. The client opens the reel; an empty list
-- is suppressed and the player presses through immediately.
Remotes.Get("ChapterBreak").OnClientEvent:Connect(function(payload: {
	ageMonths: number,
	moments: { Types.Moment },
})
	ui:SetSeam(true)
	chapterReel:Set(payload.ageMonths, payload.moments)
end)

chapterReel:OnContinueActivated(function()
	chapterReel:Hide()
	ui:SetSeam(false)
end)

-- Also the signal that there is a life at all. The server only names a stage for a profile
-- that has been set up, so this arriving means the menu's work is done -- on a fresh join
-- into a life already under way, where no menu was ever raised, and on the first push of a
-- life that has just been chosen. Both want the same thing: the HUD back.
Remotes.Get("LifeStageChanged").OnClientEvent:Connect(function(stage: string)
	ui:SetStage(stage)
	ui:SetHudVisible(true)
	cardStage = stage
	menu:SetIdentity(cardAge, cardStage, cardMoney)
	-- The rail comes up with the HUD and for the same reason: four lists about a life
	-- are a claim that there is one, and until this fires there is not.
	menu:SetVisible(true)
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
Remotes.Get("PlayerDied").OnClientEvent:Connect(function(ageYears: number, ribbon: Types.Ribbon?)
	panel:Hide()
	-- The lab comes down with everything else. The server drops the session on death and
	-- pushes nil, but the order of those two arriving is not guaranteed, and a bench
	-- clock still counting down under a death notice would be the game insisting there is
	-- something left to hurry for.
	lab:Set(nil)
	labDots:SetRunning(false)
	-- And the errand, for the same reason: the server drops the hunt on death and pushes
	-- nil, but the order the two arrive in is not guaranteed, and a stop clock counting
	-- down under a death notice would be the game insisting there is somewhere left to be.
	hunt:Set(nil)
	-- And the canvas. Same race, and the same reason not to trust it: a paint count and a
	-- clock still running under a death notice would be the game asking somebody who is
	-- gone to hurry up and finish. The wall itself is the server's and comes down with the
	-- session.
	easel:Set(nil)
	-- And the manhunt, which is the one of these that would be actively cruel to leave
	-- up: a search ring still creeping across the street under a death notice would have
	-- the player watching for a corner they cannot turn any more. The server stops caring
	-- about a dead player's bounty on its next tick -- BountyService.Get returns zero for
	-- one -- but that is a tick away and this is now.
	heat:Set(nil)
	searchRing.Set(nil, 0, false)
	-- And the drawer. The server drops the session on the next tick when it reads a dead
	-- player, but a HOLD TO TAKE button standing under a death notice would be an
	-- invitation to rob a shop with nobody left to do it.
	till:Set(nil)
	-- And the bank. Same reason, and worse: a HOLD TO SILENCE button under a death notice
	-- would be asking somebody who is gone to run back across a room.
	bank:Set(nil)
	-- And the gang. Milder than the rest -- nothing on it is counting down -- but a COLORS
	-- button under a death notice is a control offering to change something about a person
	-- who no longer has a head, and the corner is better empty.
	gang:Set(nil)
	-- And the fight, which needs it most: a fight panel is three live buttons, and leaving
	-- them under a death notice would be offering to keep swinging. The server has already
	-- ended the bout -- this is the client refusing to be the one that lags behind.
	fight:Set(nil)
	-- And the property panel and the dealership queue. Neither is a countdown, but a
	-- buy button or a serve button under a death notice is still a control over a person
	-- who no longer has a head, and the corner is better empty.
	house:Set(nil)
	carDealer:Set(nil)
	savings:Set(nil)
	-- And the map sheet, which is the only one of these that covers the whole screen: left
	-- open it would hide the death notice entirely, and the player would be reading a map of
	-- a town they are no longer in. The dial in the corner stays -- it is not a control.
	mapSheet:Close()
	-- And the menu, rail and all. Every pane on it is about a life that is still being
	-- lived -- what is hiring, who is worth calling, what there is left to get good at --
	-- and offering those under a death notice would be the game asking somebody who is
	-- gone what they plan to do next.
	menu:SetVisible(false)
	chapterReel:Hide()
	currentPerson = nil
	lessonPanelKey = nil
	phonePanelKey = nil
	workoutPanelKey = nil
	reportPanelKey = nil
	gangPanelKey = nil
	ui:ShowDeath(ageYears, ribbon)
end)

-- The trip back did not happen. Almost always Studio, where teleports do not work at all, or
-- an unpublished lobby place id -- so this is read far more often by a developer than by a
-- player, and it goes on the death screen itself rather than into the log for exactly that
-- reason: the alternative is a button that appears to do nothing.
Remotes.Get("ReturnRefused").OnClientEvent:Connect(function(reason: string)
	ui:ShowReturnRefusal(reason)
end)
