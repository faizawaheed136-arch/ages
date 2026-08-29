--!strict
-- Single source of truth for remotes. Both server and client require this
-- module; it lazily creates (server) or waits for (client) the RemoteEvent
-- instances so there is never a second place that spells out remote names.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- The `Request` remotes are the only client -> server ones; everything else is a
-- one-way state push. In the game place they carry no payload at all (RequestAgeUp)
-- or only ids, which the server checks against what it actually offered this player
-- — so there is nothing useful to forge. Clicking the dots over somebody's head is
-- not itself sent anywhere: it opens a menu the client was already holding, and only
-- what the player picks off that menu ever leaves this machine.
--
-- The one exception is `RequestCreateLife`, which carries a typed name, and it lives
-- in the *lobby*. That is not a coincidence: free text is the one input that needs a
-- filter and a refusal path, and putting the only screen that takes it in a place with
-- no world running behind it means a name being rejected costs the player nothing.
export type RemoteName =
	"StatsUpdated"
	| "MoneyUpdated"
	| "AgeUpdated"
	| "AgeUpProgress"
	| "LifeStageChanged"
	| "PlayerDied"
	| "RequestAgeUp"
	| "RequestReturnToLobby"
	| "ReturnRefused"
	| "EventOffered"
	| "EventResolved"
	| "RequestEventChoice"
	| "ShiftUpdated"
	| "Notice"
	| "GuideUpdated"
	| "JobPostsUpdated"
	| "TaskUpdated"
	| "LessonUpdated"
	| "PersonUpdated"
	| "RequestPersonOffer"
	| "RequestLessonAnswer"
	-- The two roster remotes. Their prose lives down in `REMOTE_NAMES` rather than being
	-- repeated here, the same as most of the names above them; what matters at this end is
	-- only that they are here at all. They were not, for a while, and the gap is worth a
	-- word because nothing caught it: `REMOTE_NAMES` is annotated `{ RemoteName }`, so a
	-- name in that list and missing from this union is a type error in two places at once
	-- -- the list literal and every `Remotes.Get` that spells it -- and yet the file
	-- compiles, both places build, and the remotes work perfectly at runtime. Only the
	-- analyzer ever objects, which means only Studio ever objects.
	| "PeopleRosterUpdated"
	| "RequestPersonContact"
	| "LobbySlotsUpdated"
	| "LobbySetupOptions"
	| "RequestPlay"
	| "PlayRefused"
	| "RequestSelectSlot"
	| "RequestDeleteSlot"
	| "RequestCreateLife"
	| "SlotActionRefused"
	-- The spins remotes. Live in this list for the same reason the rest of the lobby's do --
	-- one place that spells out remote names -- and the game place pays the same small cost
	-- as it already does for the slot remotes: a handful of RemoteEvents it never fires.
	--
	-- What this player owns and can still buy, pushed whole whenever either changes. Whole
	-- rather than split, on the same reasoning as `LobbySlotsUpdated`: spins and perks are
	-- read off the same page at the same moment, and a spin landing while a perk count is
	-- mid-flight is exactly the kind of out-of-order redraw a single push avoids.
	| "SpinsUpdated"
	-- "Open the purchase prompt for this product." Carries a product id from
	-- `Config.Spins.Products`; the server still bounds-checks it and still refuses a
	-- `productId` of 0, the same as if it had been typed. The grant itself never happens on
	-- this remote -- it happens in `ProcessReceipt`, which Roblox calls back on its own, so a
	-- client cannot claim spins by firing this a second time.
	| "RequestBuySpins"
	-- "Pull." No payload -- what it lands on is decided entirely server-side and pushed back
	-- as part of the next `SpinsUpdated`, so there is nothing on this wire a client could
	-- have forged the result of.
	| "RequestSpin"
	-- Why a spins purchase or a pull did not happen, in a sentence meant for the player.
	--
	-- Its own remote rather than a reuse of `SlotActionRefused`, on the precedent that already
	-- split `PlayRefused` from it: spins are read on a different page, at a different moment,
	-- from a different set of buttons, and a single shared channel would leave the client
	-- guessing which screen a refusal was even about.
	| "SpinActionRefused"
	-- The workout in progress, pushed as a whole snapshot. Its own remote rather than
	-- a field on StatsUpdated, because a workout changes four times a second during
	-- the sweep and the stat bars it moves change once or twice a minute.
	| "WorkoutUpdated"
	-- "Start a workout on this machine." Carries a machine kind string from the
	-- attribute on the part the player is standing next to; the server bounds-
	-- checks it against Config.Gym.Kinds and still refuses a kind it does not
	-- know. The session itself runs entirely server-side after this point.
	| "RequestStartWorkout"
	-- "I pushed." The player clicked the button at the right moment (or the wrong
	-- one). No payload beyond the fact of the click; the server decides quality
	-- from the sweep position it is already tracking, so a client that fires this
	-- twice gains nothing.
	| "RequestRep"
	-- The Science lab in progress, pushed as a whole snapshot. Its own remote rather
	-- than a field on LessonUpdated, because the two are different activities that
	-- happen to share a building: a lesson is one question and a clock, and a lab is two
	-- benches, a reagent pool and a mastery level. Folding them together would mean
	-- every quiz question carried an empty bench list.
	| "LabUpdated"
	-- "I clicked that station." Carries the station id off the prompt's own attribute.
	-- Never trusted: the server checks it against the stations it actually built and
	-- against the bench it would land on, and refuses a click from a player with no
	-- procedure running rather than starting one.
	| "RequestLabStep"
	-- "Take the last step back off that bench." Carries the bench index. The undo half
	-- of the commit-and-undo pair, and free -- there is no cost, no cooldown and no
	-- limit before commit, because a draft you are charged to edit is not a draft.
	| "RequestLabUndo"
	-- "Score that bench, I am done with it." Carries the bench index. The commit half,
	-- and the only irreversible thing in the verb: everything before it can be taken
	-- back and nothing after it can.
	| "RequestLabCommit"
	-- The report card waiting at the school, or nil when there is none.
	--
	-- Its own remote rather than a fifth thing on LessonUpdated, and the restraint is
	-- deliberate: that channel already carries a question, a verdict, a notice and a skip
	-- offer, told apart by which of its numbers are zero. A card is a different shape --
	-- rows that are not answers, prose that is not a question, and no clock at all -- and
	-- a fifth tenant told apart by yet another zero is how a channel stops being readable.
	| "ReportCardUpdated"
	-- "I have read it." Carries the age the card was about, which the server checks
	-- against the card it actually staged -- so a press that lands after a birthday has
	-- replaced the card cannot put away a year the player has not seen.
	| "RequestReportCardRead"
	-- The geography errand in progress, pushed as a whole snapshot: which stop you are on,
	-- what you have earned the right to be told about it, and the clock.
	--
	-- It has no request remote to pair with, and that is the verb rather than an oversight.
	-- Every other activity in the game answers by pressing something; this one is answered
	-- by *being somewhere*, so the only input is the character controller the player
	-- already has and the only judge is the server's own distance check. Adding a "check
	-- here" button would turn walking into a formality performed next to the answer.
	| "HuntUpdated"
	-- The art canvas in progress, pushed as a whole snapshot: what the player has painted,
	-- what paint they were handed, and how many cells have gone stale.
	--
	-- What it does *not* carry is the study being copied, and that omission is the subject.
	-- The picture is on the wall of the room; putting it on this channel would put it on
	-- screen an inch from the copy, and a comparison you can make without turning your head
	-- is not the comparison this lesson is about.
	| "ArtUpdated"
	-- Heat, pushed as a whole snapshot: what tier you are at, how many officers are out,
	-- whether anybody can see you this second, and where the police believe you are.
	--
	-- Carries no officer positions. The bodies are already in the world and finding them
	-- is the game -- a channel that shipped their coordinates would let a client draw the
	-- one thing this system is asking the player to work out.
	| "BountyUpdated"
	-- The till in front of you, pushed as a whole snapshot: what is left in the drawer,
	-- what you are holding, and -- the whole of it -- which way the clerk and the camera
	-- are currently pointed.
	--
	-- The two attentions are sent as *state*, not as a warning. There is no "you are
	-- about to be seen" field and there must never be one: the clerk turns and the camera
	-- sweeps in the world where the player can watch them, and a channel that told the
	-- client when to let go would be playing the activity on their behalf.
	| "TheftUpdated"
	-- "Put the tube I am holding on that cell." Carries the cell index and the pigment id.
	-- Never trusted: the server checks the cell is on the canvas, the pigment is one this
	-- rung was actually handed, the pot is not empty and the player is at the easel -- a
	-- painting made from the cupboard would make the paint run free.
	| "RequestArtPaint"
	-- "I am done, that is the painting." The commit, and the only irreversible act in the
	-- verb. Unlike the lab's it is a real decision rather than a formality, because the
	-- study keeps moving: holding on covers more of the canvas and lets what you have
	-- already done go stale.
	| "RequestArtSign"
	-- The stare-down in the corridor, pushed as a whole snapshot: both bars, the band the
	-- player is aiming to release inside, and how long the bell will wait.
	--
	-- The window is sent rather than derived on the client, and that is the load-bearing
	-- choice on this channel. It is what a life's nerve *buys* -- the band physically
	-- widens as you get harder to push around -- so a client that computed it could
	-- disagree with the server that scored against it, and the player would watch
	-- themselves release inside a green band and be told they backed down.
	--
	-- What it does not carry is who else is in the corridor. A bully working somebody else
	-- is a thing you see by looking down the hall, and a channel that listed them would
	-- turn a room you read into a list you read.
	| "NerveUpdated"
	-- Hold and release, as one boolean. The whole input of the corridor.
	--
	-- The release *value* is what decides the encounter and the server owns the bar, so
	-- this carries intent and never a score: a client that sent "I released at 0.71" would
	-- be a client that could send 0.71 whenever it liked.
	| "RequestNerveHold"
	-- The reading lesson: both words, the tray, what is in hand, and how many takebacks are
	-- left. Pushed whole rather than as deltas, for the reason every other school channel is
	-- -- the panel is redrawn on receipt and a tray that arrived in pieces could be drawn
	-- half-spent.
	--
	-- It carries the *answer* in the sense that the gaps and the tray together imply it, and
	-- that is unavoidable and fine: the subject is recognising which letters a word is
	-- missing, not being unable to see the letters. What it does not carry is which tile
	-- belongs in which gap.
	| "ReadingUpdated"
	-- Take a tile, or put the one in hand into a gap, or pull a placed one back out. One
	-- remote for all three because they are one verb with a target: nil target means put
	-- down what you are holding.
	| "RequestReadingPlace"
	-- Hand in a word as it stands. The commit, and the only irreversible thing in the
	-- lesson.
	| "RequestReadingSubmit"
	-- "My hands are in the drawer" / "they are not any more." One remote with a boolean
	-- rather than two, because the two are the same fact and a start that arrived without
	-- its stop -- or in the wrong order after a hiccup -- would leave a player taking
	-- money from across the street. The server re-checks reach on every tick regardless.
	| "RequestTillHold"
	-- "I clicked the drawer." Opens the panel and puts the player at that till, and does
	-- nothing else -- no money moves on this remote. Kept separate from the hold so that
	-- the click and the verb are separate acts, which is the whole reason a till is not a
	-- Station: clicking a station *is* the answer, and clicking a till is walking up to it.
	| "RequestTillOpen"
	-- "Send this one to watch the door." A crew id, checked against the caller's own
	-- roster server-side, same as RequestBankCallCrew -- the till has no seat to claim, so
	-- what this actually toggles is TheftService's own lookout state for that shop.
	| "RequestTillCallCrew"
	-- The bank room you are standing in, pushed as a whole snapshot: what is left in the
	-- vault, what the alarm is doing, where the guard is, and which of the room's two
	-- controls is within arm's reach right now.
	--
	-- The alarm's countdown *is* sent, which is the one place this system tells the client
	-- something the till's deliberately does not. That is not an inconsistency, it is the
	-- difference between the two rooms: a till asks you to read two attentions moving in
	-- the world, and a bank hands you a clock up front and asks how much of it you are
	-- willing to spend. Hiding a number the alarm is already screaming would be coy rather
	-- than skilful.
	| "BankUpdated"
	-- "I clicked the vault door." Puts the player in the room's activity and opens the
	-- panel. Takes nothing and trips nothing -- the alarm goes on the first *hold*, so
	-- walking up to a vault and reading the guard's patrol is free, which is the whole
	-- read-before-you-commit window this activity has.
	| "RequestBankOpen"
	-- "My hands are on it" / "they are not any more." One boolean for both of the room's
	-- controls, because which one it means is decided by where the player is standing and
	-- the server is the only end that gets to say. A client that could name the control
	-- could silence an alarm from the vault, which is the one shortcut that would delete
	-- the activity outright.
	| "RequestBankHold"
	-- "Send this one to the alarm." A crew id, checked against the caller's own roster
	-- server-side same as every other choice in this tree -- see GangService.CrewFor. Part
	-- 3's first slice: the seat this claims is BankService's, not a gang panel's, because
	-- it only means anything while standing in the room it is for.
	| "RequestBankCallCrew"
	-- Who you run with and how far up you are. Pushed on change rather than on a clock,
	-- because standing moves in bursts -- a vault pays forty-five points in one instant and
	-- then nothing for a minute -- and a fixed-rate push would spend most of its traffic
	-- resending a number that had not moved.
	| "GangUpdated"
	-- What the boss in front of you is saying, and what you can say back. Separate from
	-- GangUpdated because they have different lifetimes: your rank is true everywhere and
	-- all the time, whereas this is true only while you are standing in front of one
	-- specific person, and nil the moment you walk away.
	| "GangPanelUpdated"
	-- The map itself: its bounds, everything drawn on it, and the four sides. Sent once
	-- on join and never again, because none of it changes while the server is up -- the
	-- world is built before the first player arrives and no place point moves afterwards.
	| "MapData"
	-- Which side you are standing on and how deep into it. This one *is* on a clock: it
	-- is a question about where a body is, and a body moves continuously. Split from
	-- MapData for exactly that reason -- one is a fact about the world and one is a fact
	-- about you, and sending them together would resend the whole map twice a second.
	| "TerritoryUpdated"
	| "SkillsUpdated"
	-- Preferences, pushed whole on join and again after every change -- including after a
	-- change the client itself asked for. The client never draws what it clicked, only what
	-- came back, which is what stops a switch that failed to save from looking like it saved.
	| "SettingsUpdated"
	-- "Flip that one." Carries the setting id and the value wanted. Both are checked: an id
	-- that is not in `Config.Settings.Options` is refused rather than written, because the
	-- settings table is a dictionary in a save file and a client that could name its own key
	-- could grow that save without limit.
	| "RequestSetSetting"
	-- Which codes this account has already used, and what each one paid. Pushed on join and
	-- after every successful redeem.
	| "CodesUpdated"
	-- "I typed this." The one free-text remote in the game place, which is why it is rate
	-- limited, length capped and matched only against a fixed list. Nothing about the reward
	-- travels on this wire in either direction -- what a code pays is decided entirely from
	-- the content table, so a client that sent a longer string or a faster one gains nothing
	-- but a refusal.
	| "RequestRedeemCode"
	-- What happened to one attempt, in a sentence for the player. Sent for successes too:
	-- a box that only answers when you are wrong is a box you cannot tell you have used.
	| "CodeResult"
	-- "I clicked the boss." Opens the panel and nothing else -- joining is a row on it, not
	-- this. Walking up to all four bosses to read what they want is free, deliberately, for
	-- the same reason clicking a vault door trips nothing: a decision this permanent should
	-- not be made by the first person the player happened to bump into.
	| "RequestGangOpen"
	-- "I picked that row." Carries the row id only. What a row *costs* and whether it is
	-- allowed is decided here from the player's own standing, never from what was sent --
	-- a client that could name its own rung would be a client that promotes itself.
	| "RequestGangChoice"
	-- "Band on" / "band off." The one piece of gang state a player changes without a
	-- person present, because taking your colors off is something you do in an alley at the
	-- moment you decide to, and routing it through a boss would mean the only way to go
	-- unmarked was to walk back across the city to the person who marked you.
	| "RequestGangColors"
	-- House ownership updates. Pushed whenever a life buys or sells a suburb
	-- home, or changes the job linked to it. The client reads the whole table
	-- to redraw the property panel, so it always arrives complete.
	| "HouseUpdated"
	-- "I want to buy this suburb house." Carries the house id string; the
	-- server checks ownership limit, money, and id validity before granting.
	| "RequestBuyHouse"
	-- "I want to sell this suburb house." Carries the house id string. The
	-- server clears any linked home job first, then refunds the resale value.
	| "RequestSellHouse"
	-- "I want to link this job to my house." Carries the house id and the job id.
	-- The server checks ownership and that the job's placeId matches the house.
	| "RequestSetHomeJob"
	-- "I want to toggle this apartment door." Carries the door part; the
	-- server checks distance and animates the door.
	| "RequestToggleApartmentDoor"
	-- The dealership queue in progress, pushed as a whole snapshot: how many
	-- are waiting, who is at the front, and where the counter is. Its own remote
	-- rather than a field on ShiftUpdated because the queue is independent of
	-- any shift -- it exists whether the player is working at the dealership or not.
	| "CarDealerUpdated"
	-- "I served the customer at the counter." No payload -- the server checks
	-- that there is a queue and a front customer before granting the tip.
	| "RequestCarDealerServe"
	-- The showroom and the garage in one push: every car sold, what this life
	-- already owns, and which one -- if any -- is standing in the world. Its own
	-- remote rather than a field on CarDealerUpdated, on the same reasoning that
	-- keeps HouseUpdated separate from everything else at a counter: the queue is
	-- the room being alive whether or not anybody is buying a car, and a garage is
	-- a fact about one life's money, not about the shop floor.
	| "VehicleUpdated"
	-- "I want to buy this car." Carries a vehicle id from `content/Vehicles.luau`;
	-- the server checks the id is real, the price against the balance, and the
	-- garage is not already at Config.Vehicles.MaxOwned before granting anything.
	| "RequestBuyVehicle"
	-- "I want to sell this car." Carries a vehicle id. Refuses on the currently
	-- active one -- selling the car you are about to be told to get into would
	-- have to also answer what "active" now points at, and the honest UI move is
	-- to put it away first.
	| "RequestSellVehicle"
	-- "Bring this one out of the garage." Carries a vehicle id already owned; puts
	-- away whatever was active first, exactly one car standing in the world per
	-- life at a time. Server-built at a spot near the dealership rather than
	-- wherever the request was fired from, so a forged id cannot summon a car
	-- through a wall.
	| "RequestSpawnVehicle"
	-- "Put it away." No payload -- despawns whichever car is active, if any. The
	-- same action idle-timeout and a death both drive from the server side; this
	-- is the player choosing to do it early.
	| "RequestStoreVehicle"
	-- The fight in progress, pushed whole every tick it changes. Whole rather than
	-- split into "my bars" and "their bars" because a fight is read as one picture --
	-- a charge held against a wind-up filling opposite it -- and two remotes landing a
	-- frame apart would let the player see a strike land before the tell that sold it.
	| "FightUpdated"
	-- "I am holding the strike button / I let go / I am guarding / I stepped." Carries
	-- an action name and a boolean for the held ones. What it deliberately does not
	-- carry is a charge value: the server owns the clock the meter is drawn from, so
	-- the strongest thing a forged packet can claim is that a button went down.
	| "RequestFightAction"
	-- "Square up." Carries the id of the challenger whose dots were clicked, which the
	-- server checks against the one it actually stood in front of this player.
	| "RequestFightSquare"
	-- Monthly bill update. Pushed whenever a bill is charged or debt changes.
	| "BillDue"
	-- Savings account state, pushed on every balance change and on join.
	| "SavingsUpdated"
	-- "Put this amount into my savings account." Carries a positive number.
	| "RequestDeposit"
	-- "Take this amount out of my savings account." Carries a positive number.
	| "RequestWithdraw"
	-- A milestone was achieved this life. Carries milestone id, label, and bonus.
	| "MilestoneAchieved"
	-- A bond milestone was crossed with a specific person. Carries person name and milestone.
	| "BondMilestone"
	-- An NPC shared gossip about the player. Carries speaker, topic, and effect.
	| "GossipUpdate"
	-- A join code was entered. Carries the code string; the server looks it up
	-- and, if valid, selects the target slot and calls Play.
	| "RequestJoinByCode"
	-- Why a join code was not accepted, in a sentence meant for the player.
	| "JoinRefused"
	-- The chapter seam: a band boundary has been reached. Carries the age the
	-- next chapter starts at and the moments the shared "what happened" query
	-- found for the window since the last break. An empty list is the suppressed
	-- reel — the client opens the next chapter cold with no screen.
	| "ChapterBreak"
	-- "Give up the job I hold." No payload -- there is only ever one job to quit,
	-- and the server reads it off the profile rather than trust an id, so the worst
	-- a forged send does is quit a job the caller does not hold, which is a no-op.
	| "RequestQuitJob"
	-- "Point me at this job." Carries a job id off a post the player was already
	-- shown, which the server checks against Jobs.ById and PlaceService the same
	-- as every other id on the wire -- an unknown id is refused rather than
	-- pointing a line at nothing. Overrides the automatic best-job arrow until the
	-- player takes it, picks another, or it stops existing.
	| "RequestGuideToJob"
	-- "I pressed the pickup key at the mark I'm standing on." Carries the task id
	-- the mark belongs to and nothing else -- the client only ever claims it pressed
	-- the key, never that it was in range or that the pickup should count, and the
	-- server re-checks both against the shift it already has before anything
	-- happens. A press for a task that has finished, expired, or was never issued to
	-- this player is a no-op.
	| "RequestTaskPickup"
	-- "You just walked through the stadium's own gate." Carries no payload --
	-- StadiumEntranceService already decided this player earns the moment
	-- (once per session) before firing it, so there is nothing on the wire for
	-- a client to forge; the only thing this remote can do is play a camera
	-- cutscene early or not at all. The fan NPC that walks over is a real
	-- server-spawned visitor, not part of this payload, the same separation
	-- NPCService.Arrive already keeps between "play a moment" and "who is in it".
	| "StadiumEntranceCue"

local REMOTE_NAMES: { RemoteName } = {
	"StatsUpdated",
	-- Its own remote rather than a fifth field on StatsUpdated. Money is not a stat
	-- -- it is unbounded, it does not decay, and it moves on different occasions --
	-- and folding it in would mean every stat push carried a balance and every
	-- balance change redrew four bars.
	"MoneyUpdated",
	"AgeUpdated",
	"AgeUpProgress",
	"LifeStageChanged",
	-- A life ending, carrying the age it ended at and the ribbon it earned. There is no
	-- `PlayerRespawned` to pair with it any more, and its absence is the whole of part 3
	-- in one line: a life does not restart in place. It stays dead in the slot it was lived
	-- in, and the player goes back to the lobby to pick another card. The death screen is
	-- therefore the last thing this place ever says to that life -- nothing takes it down,
	-- the place going away does.
	"PlayerDied",
	"RequestAgeUp",
	-- "Take me back to the menu." Pressed off the death screen, and available from the HUD
	-- for a player who simply wants to change life mid-run.
	--
	-- A request rather than the client teleporting itself, because a teleport out is also a
	-- profile handoff: the session in this place has to end cleanly for the lobby to be able
	-- to open the same key, and only the server knows when it has.
	"RequestReturnToLobby",
	-- Why the trip back did not happen. Almost always one of exactly two things -- running
	-- in Studio, where teleports do not work at all, or an unpublished lobby place id -- and
	-- both are sentences a developer needs to read rather than errors a player caused.
	--
	-- Load-bearing for the same reason PlayRefused is: the death screen's only button
	-- silently doing nothing is indistinguishable from the game having hung.
	"ReturnRefused",
	"EventOffered",
	"EventResolved",
	"RequestEventChoice",
	-- The shift in progress, pushed as a whole snapshot. Its own remote rather than
	-- a field on MoneyUpdated for the same reason money is not a fifth stat: a wage
	-- arriving is a balance change, but being three hours into a shift is not, and
	-- folding them together would redraw the shift row every time a letter paid out.
	"ShiftUpdated",
	-- A single sentence for the player, spoken by the server and shown as the same
	-- transient banner the client already raises on an auto age-up. A general channel
	-- rather than a firing-specific remote, because the thing being said -- "you've
	-- been let go" -- is one the server composes and the client only displays: the
	-- client cannot know it was coming, so it cannot draw it off any state it holds.
	-- Carries only the finished string; nothing on this wire is acted on, only read.
	"Notice",
	-- Where the player is being pointed, if anywhere. Sent rather than drawn on the
	-- server because guidance is addressed to exactly one person: most of what this
	-- game puts in the workspace -- a choice pad, a dog, a delivery van -- is meant
	-- to be seen by whoever walks past, and a line to your first job is not.
	"GuideUpdated",
	-- The "NOW HIRING" posts this player should be looking at, as a whole list.
	--
	-- The same argument as GuideUpdated, arrived at the hard way. These were once
	-- built by the server and shared by everyone in the room, which was fine right up
	-- until somebody took the job: the sign and the mark stayed standing over the head
	-- of the one person they were no longer for. An offer has to stop being made once
	-- it is accepted, and only a per-player post can do that.
	"JobPostsUpdated",
	-- What the player is doing this minute, inside the shift they are already on.
	--
	-- Its own remote rather than a field on ShiftUpdated, on the rule that keeps money
	-- and shifts apart: a shift is eight game hours and a wage, and it changes when an
	-- hour completes. A task is a sentence and a countdown, and it changes four times
	-- a second. Folding them together would redraw the whole shift row every tick for
	-- the sake of one number.
	"TaskUpdated",
	-- The question in front of the player, inside the lesson they are already in.
	--
	-- Exactly the same argument as TaskUpdated, which is the point: school and work are
	-- the two things this game asks you to actually do, and they push at the same rate
	-- for the same reason. The answers themselves are not in here -- those are pads on
	-- the floor, built by the server, because an answer you give by walking has to be
	-- somewhere you can walk.
	"LessonUpdated",
	-- Who the player is standing next to, and what they just said back.
	--
	-- The third of the three rows that are pushed rather than drawn, alongside a task and
	-- a lesson, and it is here for the same reason as both: the pads in front of a person
	-- are built by the server, because an offer you take by walking has to be somewhere you
	-- can walk, but what is written on them was decided by reading one profile.
	--
	-- Further than a lesson, in fact. The person themselves is spawned per player rather
	-- than shared: who is around depends on the player's age and what they say depends on
	-- the player's bond, so two players standing in the same kitchen are looking at two
	-- rigs offering two different things. Family is not scenery.
	"PersonUpdated",
	-- What the player picked off the panel in front of somebody, and off the panel in a
	-- lesson. Their own remotes rather than a shared one carrying a kind and an id,
	-- because a person and a lesson are checked against completely different things --
	-- who you are standing next to and their bond, versus which question you are on --
	-- and one handler doing both would be one handler that could confuse them.
	"RequestPersonOffer",
	"RequestLessonAnswer",
	-- The people the player has met, as a whole list for the HUD's people section.
	--
	-- Distinct from PersonUpdated in the way a whole list is always distinct from a
	-- single row: PersonUpdated names who is standing next to you and what they will
	-- say; this names everyone whose name you know, whether or not they are near. The
	-- HUD's avatars are built from it, and the list is why tapping an avatar is a
	-- conversation rather than a guess — the server sent the person's name and face,
	-- and the tap only carries their id.
	"PeopleRosterUpdated",
	-- "I tapped this avatar, open the conversation." Carries a person id, checked
	-- against the roster the server sent, and the conversation itself is answered by
	-- the same PersonUpdated push a proximity approach already raises.
	"RequestPersonContact",
	-- The lobby remotes. They live in this list rather than a `LobbyRemotes` module of
	-- their own for the reason at the top of the file -- one place that spells out remote
	-- names -- and the cost is that each place creates a handful of RemoteEvents it never
	-- fires. A few unused instances is a smaller price than two files that can disagree
	-- about a string.
	--
	-- Every slot the player owns, as a whole list, whenever any of it changes. A whole
	-- list rather than a per-slot push because the menu is three cards read side by side:
	-- there is no moment where one card is meaningfully newer than the others, and a
	-- per-slot remote would let a delete and a rebuild land out of order and leave a card
	-- showing a life that no longer exists.
	"LobbySlotsUpdated",
	-- "Choose who you are about to be", carrying everything the create page needs to draw
	-- itself. Sent rather than the client reading Config, because these are the exact
	-- numbers the server is about to validate the answer against -- so a page physically
	-- cannot offer a spend that will then be refused.
	--
	-- Its own remote rather than a field on LobbySlotsUpdated, even though both are pushed
	-- on load. Slots change every time a card is touched; the options change only when a
	-- life *ends*, which happens in the other place entirely. Folding them together would
	-- resend the full country list on every delete.
	--
	-- The client holds the Create button disabled until this arrives, rather than opening a
	-- page with empty steppers on it. There is no honest thing to draw before it lands.
	"LobbySetupOptions",
	-- "Start this slot." Carries the slot number, which the server bounds-checks against
	-- Config.Slots.Count exactly as if it had been typed -- the client picked it off a
	-- list the server sent, but the client is still the client.
	"RequestPlay",
	-- Why Play did not happen, in a sentence meant for the player. The accepted path
	-- already announces itself by teleporting you, so the only outcome needing words is
	-- the one that did not.
	--
	-- Kept apart from SlotActionRefused below, which is the one distinction between these
	-- two refusal channels that is worth a remote: everything on the cards is instant and
	-- local, and Play is a slow call to another server that can fail *after* the screen has
	-- already gone busy. They are read in different places on screen and at different
	-- moments, so a single remote would have the client guessing which one it just got.
	--
	-- Load-bearing, because the most likely refusal here is not the player's fault at all
	-- -- an unpublished place id, a teleport rate limit, a profile that has not loaded yet.
	-- A Play button that silently does nothing is indistinguishable from a frozen game.
	"PlayRefused",
	-- "Make this card the one Play uses." Carries a slot number and nothing else.
	--
	-- A remote at all, rather than the client remembering which card is highlighted and
	-- telling the server only at Play time, because the choice is *persisted* -- it is
	-- written to `activeSlot` on the profile, which is how the game place learns which life
	-- to run. See ProfileData.activeSlot: that field is deliberately not something a
	-- teleport payload can assert.
	"RequestSelectSlot",
	-- "Delete the life in this slot." The only irreversible thing in this game that is not
	-- dying, so the card asks twice before it fires -- but the second press is a fact about
	-- the *screen*, not about the wire, and the server does not attempt to verify that it
	-- happened. It cannot: any check it could make is a value the client would be sending
	-- itself. What the server does enforce is that the slot is real, that something is in
	-- it, and that it is not the slot currently mid-teleport.
	"RequestDeleteSlot",
	-- The answer to the create page: a slot number and the life to put in it.
	--
	-- The only remote in the game that carries free text -- a name the player typed, which
	-- goes through TextService before it is stored and is refused outright if the filter
	-- cannot be reached.
	"RequestCreateLife",
	-- Why a card action was not accepted, in a sentence meant to be read by the player
	-- rather than by a log. Shared by select, delete and create because all three are
	-- answered in the same instant and read on the same line under the cards.
	--
	-- A sentence rather than a code, and a refusal rather than an acceptance flag: the
	-- accepted path already has a message -- the cards redrawing -- and a boolean that is
	-- false only on failure is a sentence with nowhere to put the reason.
	"SlotActionRefused",
	"SpinsUpdated",
	"RequestBuySpins",
	"RequestSpin",
	"SpinActionRefused",
	"WorkoutUpdated",
	"RequestStartWorkout",
	"RequestRep",
	"LabUpdated",
	"RequestLabStep",
	"RequestLabUndo",
	"RequestLabCommit",
	"ReportCardUpdated",
	"RequestReportCardRead",
	"HuntUpdated",
	"ArtUpdated",
	"BountyUpdated",
	"TheftUpdated",
	"RequestArtPaint",
	"RequestArtSign",
	"NerveUpdated",
	"RequestNerveHold",
	"ReadingUpdated",
	"RequestReadingPlace",
	"RequestReadingSubmit",
	"RequestTillHold",
	"RequestTillOpen",
	"RequestTillCallCrew",
	"BankUpdated",
	"RequestBankOpen",
	"RequestBankHold",
	"RequestBankCallCrew",
	"GangUpdated",
	"GangPanelUpdated",
	"MapData",
	"TerritoryUpdated",
	"SkillsUpdated",
	"SettingsUpdated",
	"RequestSetSetting",
	"CodesUpdated",
	"RequestRedeemCode",
	"CodeResult",
	"RequestGangOpen",
	"RequestGangChoice",
	"RequestGangColors",
	"HouseUpdated",
	"RequestBuyHouse",
	"RequestSellHouse",
	"RequestSetHomeJob",
	"RequestToggleApartmentDoor",
	"CarDealerUpdated",
	"RequestCarDealerServe",
	"VehicleUpdated",
	"RequestBuyVehicle",
	"RequestSellVehicle",
	"RequestSpawnVehicle",
	"RequestStoreVehicle",
	"FightUpdated",
	"RequestFightAction",
	"RequestFightSquare",
	"BillDue",
	"SavingsUpdated",
	"RequestDeposit",
	"RequestWithdraw",
	"MilestoneAchieved",
	"BondMilestone",
	"GossipUpdate",
	"RequestJoinByCode",
	"JoinRefused",
	"ChapterBreak",
	"RequestQuitJob",
	"RequestGuideToJob",
	"RequestTaskPickup",
	"StadiumEntranceCue",
}

local FOLDER_NAME = "RemoteEvents"

local Remotes = {}

local function getFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		return existing :: Folder
	end

	if RunService:IsServer() then
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		for _, name in REMOTE_NAMES do
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		folder.Parent = ReplicatedStorage
		return folder
	end

	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Remotes.Get(name: RemoteName): RemoteEvent
	local folder = getFolder()
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
