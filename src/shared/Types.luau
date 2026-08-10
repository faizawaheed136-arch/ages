--!strict
-- Shared Luau type definitions. Pure types, no runtime content.

local Types = {}

export type StatName = "health" | "happiness" | "smarts" | "looks"

export type Stats = {
	health: number,
	happiness: number,
	smarts: number,
	looks: number,
}

export type LifeStageId = "Childhood" | "Adolescence" | "Adulthood" | "Elder" | "Death"

-- Why a year ended. The client only announces "Auto" — the others are either
-- the player's own doing or a silent state resync on join/respawn. "Skip" marks
-- the years crossed by Skip Childhood, which pass without offering an event.
-- "Event" is a childhood year ended by answering its event: silent, because the
-- outcome the player is already reading is the announcement.
export type AgeUpCause = "Manual" | "Auto" | "Sync" | "Skip" | "Event"

-- Server's verdict on the Age Up button, so the HUD never invents its own
-- gating rule: Hidden (dead, or a first life still in childhood), Cooldown
-- (too soon), Ready, SkipChildhood (offered instead of Ready before the manual
-- age, once the player has already lived childhood at least once).
export type ManualAgeUpState = "Hidden" | "Cooldown" | "Ready" | "SkipChildhood"

-- A partial map: a choice names only the stats it moves.
export type StatDelta = { [StatName]: number }

-- One thing a life can have done, declared in content/Flags.luau.
export type FlagDef = {
	id: string,
	-- What having it means, in the past tense, as a sentence about the player. Read
	-- by nothing at runtime and required anyway: a flag id is four words with the
	-- spaces taken out, and four words is not enough to stop two authors using the
	-- same one for two different things a year apart.
	meaning: string,
}

-- The flags a life is currently carrying, mapped to the age they were earned at.
--
-- The age is there because it costs one number and answers the question every piece of
-- writing about a flag wants to ask -- "ever since you were six" is a better sentence
-- than "ever since", and without this it is not a sentence the game can produce. Absent
-- means not held; there is no false, because a flag that was never earned and a flag
-- that was earned and undone are the same state and storing them apart would invite
-- content that tried to tell them apart.
export type FlagSet = { [string]: number }

-- One rung of the childhood body ladder: what a body of this age can *do*. Matched
-- by the first band whose maxAge the player's age falls under, so
-- Config.Childhood.Bands must stay sorted.
--
-- No size here. How big a body is at an age is Config.Growth, which is a continuous
-- curve rather than a ladder and applies to everybody in the world rather than only
-- to the player -- see the note on it.
export type ChildhoodBand = {
	id: string,
	maxAge: number,
	walkSpeed: number,
	jumpPower: number,
	cameraOffsetY: number,
}

-- What a body of a given age moves like, keyed by the slot names Roblox's own
-- Animate script uses -- "idle", "walk", "run", "jump", "fall", "climb". Partial
-- on purpose: a band that overrides only walking keeps Roblox's default for
-- everything else, which is the correct look for most of the ladder.
--
-- A crawl is not a slow walk. WalkSpeed alone gets a small person moving at a
-- believable speed and still standing upright, which reads as a shrunk adult
-- rather than a baby -- so the speed and the animation are one mechanic, not a
-- mechanic and a decoration.
export type AnimationSet = { [string]: string }

-- How an event reaches the player. The engine decides *which* event fires;
-- delivery decides *how*, and the two are kept separate so a mode can be added
-- here without touching content or selection logic.
--
-- Memory and Direct are handed over on a birthday and have no world presence at
-- all. Memory is now a legacy of the age before there was a world to put things
-- in, and childhood no longer uses it.
--
-- Wander is what childhood uses instead, and it is the mode for an event that has
-- no fixed home and no schedule: the server finds a piece of floor the player can
-- reach, puts the thing there, and points at it. Unlike Interact it needs nothing
-- hand-placed, which is the whole reason it exists -- a toddler's house cannot
-- require twenty-two tagged props to be playable, and an event that has to be
-- crawled to is a different mechanic from one that is handed over whether or not
-- the room is interesting.
--
-- Letter, PhoneCall and NPCApproach are the world coming to *you*: something is
-- staged in the house and the prompt only opens once you go to it. Which route
-- each mode takes -- and therefore which system is allowed to pick it -- lives
-- in Delivery.luau, so no system has to hardcode the list.
export type EventDelivery =
	"Memory"
	| "Direct"
	| "Wander"
	| "Interact"
	| "Letter"
	| "PhoneCall"
	| "NPCApproach"
	| "Shift"

-- How an event is *answered*, which is a separate question from how it reached
-- the player. A Panel event is read and clicked. An Enacted one puts its choices
-- three dots over the thing it is about, and you answer it by going over there and
-- clicking them -- the prompt stays on screen as a banner and the world stays live
-- behind it.
--
-- The two axes are independent on purpose: a letter can be read off a panel or
-- walked away from, and which it is should be a content decision rather than a
-- consequence of how the letter arrived.
--
-- A Handled event has no list of answers anywhere. Its choices are objects in the
-- room and you answer it by doing something to one of them -- crawling to the toy,
-- shoving the rug aside, carrying the cookie to your mouth. The prompt is on screen
-- as a banner, exactly as an enacted one is, and that is all: there is never a row
-- to click, because a row to click is what this exists instead of.
--
-- The difference from Enacted is what walking buys you. Enacted spends the walk on
-- the *right to be asked* -- you go to the dog, click the dots, and then choose. In
-- a Handled event the walk is the choosing. There is no moment where the world stops
-- and a menu opens.
--
-- Enacted and Handled are both always a *request*. If there is nothing in the room to
-- hang the dots on -- an event about nothing, or a subject the room had nowhere to
-- put -- and likewise if the room has nowhere to lay out a prop set, the event falls
-- back to a panel rather than becoming unanswerable. That means the field is never a
-- guarantee and no caller may treat it as one.
export type EventResolution = "Panel" | "Enacted" | "Handled"

-- Closed rather than a loose string, so that a third value can never arrive from
-- content and pass silently through a comparison that only ever tested for one of
-- these two.
--
-- What it is for is narrow and worth stating, because a type like this invites being
-- read as more than it is: it decides which first-name list a generated person is
-- named from, and nothing else. It is not attached to what anybody can *do* -- no job,
-- no event, no stat and no offer anywhere reads it -- and nothing in this game should
-- ever be gated on it. There is deliberately no partner system for it to feed: a
-- romantic relationship is the one thing this game cannot write and stay 13+.
export type Gender = "male" | "female"

-- One person the world can send to your door. Built from body scales and colors
-- rather than from a catalog bundle on purpose: those need no asset ids at all,
-- so the cast exists and reads as a person before a single id has been picked in
-- Studio. The id fields are polish layered on top, and 0 means "not chosen yet"
-- because that is what HumanoidDescription itself uses for an empty slot.
--
-- The cast is fixed rather than randomized so that the neighbor who turns up at
-- nine is the same neighbor at forty. That continuity is the whole reason these
-- are authored people instead of generated ones.
export type CastMember = {
	id: string,
	-- Shown over their head. Kept out of the event text so a line can be reused
	-- by a different visitor without being rewritten.
	name: string,
	-- Lives here rather than on Person because it belongs with the *name*, and the
	-- name is here. A generated person's first name is drawn from the list this
	-- picks, so the two cannot disagree without somebody deliberately editing one of
	-- them -- which is worth more than the convenience of reading it one hop closer
	-- to the offers that care.
	gender: Gender,
	skinColor: Color3,
	-- Build, **not size**: how far off average for their age this particular person
	-- is, with 1 meaning average. Age is applied on top by Config.Growth when the
	-- rig is built, so a schoolfriend at 0.9 is a slightly small six-year-old at six
	-- and a slightly small seventeen-year-old at seventeen -- which is what a person
	-- is. Writing an absolute here instead is what used to make every child NPC a
	-- short adult who never grew.
	-- Safe range: 0.85-1.15. Outside that they read as a caricature.
	heightScale: number,
	widthScale: number,
	headScale: number,
	proportionScale: number,
	bodyTypeScale: number,
	shirtAssetId: number,
	pantsAssetId: number,
	hairAssetId: number,
	-- Set only on peers: how many years off the player's own age this person is,
	-- so they are re-sized to the player's age every time they are sent rather
	-- than being whatever size they were written at. nil means an adult, whose
	-- size is a fact about them and not about you.
	--
	-- This is what makes the friend you play out front with at six a
	-- seventeen-year-old at seventeen without a second rig or a second id.
	-- Safe range: -3 to 3. Beyond that they are not a peer, they are a relative.
	ageOffset: number?,
}

-- The thing an event is *about*, when that thing is something you can look at.
-- "There is a dog. It is at least as tall as you are" is a sentence describing an
-- absent animal until a dog walks into the room; a subject is what makes the
-- second half of that true.
--
-- Distinct from CastMember, and deliberately not folded into it. A cast member is
-- a person the world sends to your door, they are the *delivery*, and they are
-- built from a HumanoidDescription because they are a Roblox avatar. A subject is
-- whatever the prompt happens to be about -- an animal, later a vehicle or a
-- machine -- it arrives with an event however that event was delivered, and it
-- has no avatar to be described by. Sharing a type would have meant a dog with a
-- shirt id.
--
-- Described in plain dimensions rather than by an asset id for the reason the
-- cast is described in body scales: these need nothing bought or uploaded, so the
-- subject exists and is the right size from the first run. A real model dropped
-- into the Studio folder named by Config.World.SubjectFolder takes over, and
-- nothing here changes when it does.
export type SceneSubject = {
	id: string,
	-- Never shown to the player -- there is no nameplate over a dog. This is what
	-- the warnings and the Studio harness call it.
	name: string,
	-- Top of the back, in studs. The number that decides whether the animal reads
	-- as looming or as underfoot, so it is measured against the childhood body
	-- ladder rather than against an adult: see Config.Childhood.Bands.
	shoulderHeight: number,
	bodyLength: number,
	bodyWidth: number,
	-- Studs per second on the way in. Slower than the thing itself would move,
	-- for the reason Config.NPC.WalkSpeed is slower than a player: the approach
	-- has to be legible, and something that crosses the room in half a second has
	-- not arrived so much as appeared.
	walkSpeed: number,
	color: Color3,
	-- Muzzle, paws, tail tip. One second color is the entire difference between a
	-- shape and an animal at placeholder fidelity.
	accentColor: Color3,
	-- True for a two-legged human figure. The placeholder builds two legs, two
	-- arms and a head instead of four legs, a tail and a snout, and the motion
	-- walks on two legs and nods instead of lying down.
	biped: boolean?,
}

-- What a staged delivery actually put in the world. `anchor` is the thing the
-- player has to reach, and it may move -- a visitor's is their own root part, so
-- reaching them means reaching where they now are rather than where they came
-- in. `dismiss` owns *all* teardown including the anchor, which is what lets a
-- presentation end gracefully instead of blinking out of existence.
export type DeliveryPresentation = {
	anchor: BasePart,
	-- `collected` distinguishes the player arriving from the delivery giving up,
	-- because those two endings should not look the same.
	dismiss: (collected: boolean) -> (),
}

-- A job you can hold. Content, not config: the numbers here are what the job is,
-- and adding a second shop assistant on a different street should be a new entry
-- rather than a new tunable.
--
-- `yearlySalary` is the authored figure and the only one written down, because it
-- is the one a person can judge. Everything else -- what a shift pays, what an
-- hour pays -- is divided out of it at the point of use, so the salary can be
-- retuned without a second number silently disagreeing with it.
--
-- `placeId` points at a place point in the built world (see Config.World
-- PlacePointTag). The job does not carry coordinates for the same reason nothing
-- else does: the shop floor is wherever the shop floor was built.
-- What a job asks of you before it will have you, beyond being old enough: a
-- standing at some *other* job. This is the career ladder, expressed as content
-- rather than as code, so adding a third rung is a table entry and branching into
-- two rungs off the same one is two entries naming the same prerequisite.
--
-- Deliberately a reference to another job rather than a global "career score".
-- Being relied on at the shop should say nothing about whether a hospital would
-- have you, and a single number would quietly claim that it does.
export type JobRequirement = {
	jobId: string,
	standing: number,
}

-- Somebody whose good word gets you in the door on less than the job would otherwise
-- ask for.
--
-- A reference, and the whole point of it is that there is no reference *object*: the
-- relationship is the reference. Nothing is handed over, nothing is stored on the
-- profile, no favour is spent. The office simply reads how the neighbor feels about you
-- on the day you apply, which is what makes twenty years of being decent to a man worth
-- something to a system that never mentioned him.
--
-- Lowers the bar rather than removing it, deliberately. A vouch that skipped `minSmarts`
-- outright would make school optional for anyone who had made a friend, and the two
-- things this game asks of a childhood have to add up rather than substitute.
export type JobVouch = {
	personId: string,
	-- What they have to think of you before they will say anything.
	minBond: number,
	-- How much of the smarts bar their word is worth. Never enough to reach the floor:
	-- a job that could be had on a reference and nothing else is a job with no bar.
	worthSmarts: number,
}

export type Job = {
	id: string,
	title: string,
	placeId: string,
	minAge: number,
	yearlySalary: number,
	-- What you must already have done elsewhere. Nil means the job is an entry
	-- point -- the bottom of a ladder, open to anyone old enough -- and at least one
	-- job must always be one of those or nobody could ever start working.
	requires: JobRequirement?,
	-- Smarts the job asks for, or nil for a job that does not care.
	--
	-- Deliberately separate from `requires` rather than another field inside it,
	-- because it is a different kind of claim: `requires` is about what you did at
	-- another job, this is about what you are. A job can ask either, both or neither.
	--
	-- This is the only thing in the game that reads `smarts`, and it is what school is
	-- for. A childhood spent sitting lessons and a childhood spent skipping them end
	-- twenty or thirty points apart, and this is the door that difference opens.
	minSmarts: number?,
	-- Who could put in a word for you here, if anyone would. Only ever read alongside
	-- `minSmarts`, because lowering a bar that does not exist is not a favour.
	vouch: JobVouch?,
}

-- What the HUD is told about the shift in progress. A snapshot rather than a
-- stream of deltas, because it is redrawn wholesale anyway and a client that
-- missed one push would otherwise be permanently wrong about the total.
--
-- `earned` is money already paid, not money pending: wages are credited as each
-- game hour completes, so this is a running receipt rather than a promise.
export type ShiftState = {
	-- Nil when the player holds no job, which is the ordinary state before 16.
	jobTitle: string?,
	onShift: boolean,
	-- Game hours into the current shift, and how many make a full one.
	gameHoursWorked: number,
	shiftGameHours: number,
	-- Paid so far in this shift, in whole currency units.
	earned: number,
	-- Against the year's allowance, in shifts rather than hours: "3 of 5" is
	-- something a player can hold in their head, "24 of 40 game hours" is not.
	shiftsThisYear: number,
	shiftsPerYear: number,
	-- How the job you hold thinks of you, as a phrase rather than a number
	-- ("well thought of"). A phrase because a record is an opinion people hold
	-- about you, and nobody has ever been told they are a 14.
	--
	-- Nil when there is no job to have an opinion.
	standing: string?,
	-- Why you cannot clock on at the station you are standing next to, in words the
	-- player can act on. Nil in the overwhelmingly common case of not standing next
	-- to one at all.
	--
	-- This exists because clocking on is automatic and proximity-based, which makes
	-- its failure mode silence: you walk up to the office at 18, nothing happens,
	-- and the game has told you nothing about why. A refusal has to say what it
	-- wants from you or the ladder is invisible.
	blockedReason: string?,
}

-- Where the game is currently pointing the player, and what they will find when they
-- get there. A nil `target` means "nowhere", and that is the state almost all of the
-- time: an arrow that is always up is nagging rather than guidance, and stops being
-- read long before it stops being drawn.
--
-- Drawn entirely on the client, which is the whole reason this crosses the wire as a
-- position instead of being a Beam the server parents into the workspace. A line
-- leading to your first job is personal -- three players in one shop would otherwise
-- stand in a cat's cradle of each other's directions.
--
-- The label travels with it because a line across the floor does not say what is at
-- the end of it. "Shop assistant" waiting there is the difference between being led
-- somewhere and being told where you are being led.
export type GuideState = {
	target: Vector3?,
	label: string?,
}

-- One "NOW HIRING" post standing at one workplace: a sign to read from the street
-- and a mark on the floor to step onto.
--
-- Sent per player and drawn on the client, for the same reason GuideState is. A post
-- is an offer, not scenery, and the one thing an offer has to do is stop being made
-- to the person who accepted it -- so the player who took the job is simply not sent
-- one. A single object in the workspace could never do that.
--
-- Being personal is also what lets `padLocked` exist. A shared pad had to invite
-- everybody, because it had no idea who was looking; this one is told, so a job you
-- are two years short of can be painted grey and still say what it wants.
--
-- Every string here is composed by the server. The client picks no words -- it
-- decides where the text sits and what colour it goes when locked, and nothing else.
export type JobPostState = {
	jobId: string,
	-- The job's place point: the floor at the counter. The sign floats above it and
	-- the pad is painted on it.
	position: Vector3,
	-- "NOW HIRING". Passed rather than hardcoded so a post can eventually say other
	-- things -- a job with nobody's shift free this year -- without a second builder.
	headline: string,
	title: string,
	-- The terms, shown on one line: pay, the age, whatever the ladder wants first.
	terms: { string },
	-- What the mark on the floor says. "Take the job" when it is open, and the reason
	-- it is not when it is locked.
	padLabel: string,
	padLocked: boolean,
}

-- One thing you are asked to do during a shift, as authored. Content, not state --
-- see TaskState for the one in progress.
--
-- Deliberately one primitive rather than a family of them. A task is some marks to
-- walk onto, in order, before a clock runs out, and that is all it will ever be: the
-- variety comes from the words and the numbers, not from new verbs. Restocking a
-- shelf and carrying a box to the stockroom are the same mechanic wearing different
-- sentences, and pretending otherwise would buy a lot of code for a difference the
-- player cannot feel.
--
-- What the marks are *near* is not authored. They are found at run time around
-- wherever the player clocked on, which is what lets a job get tasks without anybody
-- tagging six new parts in Studio, and what stops a task from ever sending somebody
-- into a wall in a room the author never saw.
export type JobTask = {
	id: string,
	-- What the HUD says you are doing. A sentence, in the present tense: the player
	-- reads it once, while walking.
	label: string,
	-- What the mark on the floor says. Shorter than the label, because it is read at
	-- a glance from across a room with a body in the way.
	mark: string,
	-- How many marks, visited in order. One is "go there"; two is "fetch it and bring
	-- it back", which is the only structure in the game that makes a workplace feel
	-- like it has a layout.
	-- Two is the practical ceiling: three marks in twenty seconds is a chore.
	spots: number,
	-- What the far mark says, on a task that has two. Defaults to `mark`, and is worth
	-- filling in on anything shaped like a fetch: "Fetch the box" written on the place
	-- you are bringing the box back *to* is the one word in the task pointing the wrong
	-- way.
	handMark: string?,
	-- How many people queue for this task, or nil for the ordinary shape.
	--
	-- The one field here that changes what a task *is* rather than what it says. A rush
	-- is one round trip per person in the queue -- fetch, hand over, fetch, hand over --
	-- so the clock stops being a countdown you walk out and becomes a line of people
	-- getting shorter. Being slow is visible from anywhere in the room, because the ones
	-- still waiting are standing in it.
	--
	-- The counter end stays put, because that is where the queue is. The other end is
	-- looked up again for every person, so a rush is a shop you have to know your way
	-- around under a clock rather than one lane run six times.
	--
	-- Needs `spots = 2` and a `customer` line, and the validator insists on both: a
	-- queue at one mark would be served without moving, and a queue with nobody in it
	-- is just a long task.
	rush: number?,
	-- The clock, in real seconds, for the whole task.
	--
	-- On a rush this is the clock for the authored number of people. A room with space
	-- for two of the three shortens the queue and shortens this with it, so a cramped
	-- shop is an easier shift to look at and exactly as hard a one to work.
	seconds: number,
	-- What the person waiting on this task says while they wait, or nil if nobody is.
	--
	-- The only field here that puts a body in the room, and it is one string because
	-- that is genuinely all the authoring a person needs: where they stand is found at
	-- run time from the mark, who they are is drawn from the public, and what they do
	-- is wait. A task with a line has somebody standing across its last mark looking
	-- at you; a task without one is the same task in an empty shop.
	--
	-- Written as speech, in their words, not the game's. "Just these, thanks" is a
	-- person; "Customer waiting for service" is a status bar with a head.
	customer: string?,
}

-- One task in progress, pushed to the HUD. They arrive as a list, and an empty list
-- means "nothing right now" -- either between tasks or not on shift at all, which the
-- HUD does not need to tell apart because in both cases there is nothing to be doing.
--
-- Up to Config.Work.Tasks.MaxConcurrent of them at once, late in a shift. That is the
-- whole reason this is a list: a shift that can only ever ask for one thing is asking
-- how fast the player walks, and a shift that asks for two is asking which one they
-- would rather lose.
--
-- A whole snapshot every push, like every other state in this game: a dropped message
-- is corrected by the next one rather than leaving a countdown permanently a second
-- out, or a mark on the floor for a task that finished ten seconds ago.
export type TaskState = {
	-- The job task's authored id. Not shown anywhere -- it is how the client tells two
	-- live tasks apart between pushes, so it can leave one mark standing untouched
	-- while the other is replaced. Without it the client can only match by position in
	-- the list, and the list shortens from the middle every time the first of two is
	-- finished.
	id: string,
	label: string,
	-- Where the mark you are currently heading for goes, and what is written on it.
	--
	-- Drawn on the client for the third time in this system and for the same reason as
	-- the other two: a task is yours. Two shop assistants on the same floor would
	-- otherwise be walking through each other's instructions, each being told to sweep
	-- a spot the other one is being told to fetch a box from.
	--
	-- The server picks the position -- it is the one that knows where the walls are --
	-- and the server also decides when you have reached it. The client draws a disc
	-- there and nothing else; deleting it by hand would remove the mark and change
	-- nothing about whether the task can be completed.
	spot: Vector3,
	mark: string,
	-- Which mark you are on and how many there are, so the HUD can say "1 of 2"
	-- without knowing anything about what a task is.
	spotIndex: number,
	spotCount: number,
	-- How many people are still queueing for this one, or nil if it is not that kind of
	-- task. Replaces the mark count on the row rather than joining it: "3 of 6" is a
	-- true fact about a rush and a useless one, because what the player wants to know
	-- is how many more times they are doing this, and that is people, not marks.
	waiting: number?,
	secondsLeft: number,
	secondsTotal: number,
	-- True while the clock is held. Currently only ever because an event prompt is
	-- open: a shift moment is something to read and answer, and racing a task timer
	-- while doing it would teach players to dismiss the writing unread.
	--
	-- Sent rather than inferred from a frozen countdown, because a paused clock and a
	-- broken one look identical on a HUD and only one of them is worth waiting out.
	paused: boolean,
	-- The clock ran out on this one. It is still sent, for the few seconds before the
	-- next task, so that missing one is something the player is told rather than
	-- something they work out at the end of the shift from a number going the wrong
	-- way.
	--
	-- `spot` is still filled in and still real, but there is nowhere left to go: the
	-- client takes the mark off the floor and keeps the row. Which is the honest shape
	-- of it -- the task is over, the fact of it is not.
	missed: boolean,
}

-- One thing a lesson asks you.
--
-- Content data, and the whole reason school can be a mechanic rather than a stat that
-- goes up. What makes it one is the clock: five questions, twenty seconds each, and a
-- child who is getting them wrong finds that out while there are still some left.
--
-- Deliberately not a school syllabus. These are the things a child in this game would
-- plausibly be asked in a room with a board in it, kept short enough to be read and
-- answered inside twenty seconds.
export type LessonQuestion = {
	id: string,
	-- Asked in the second person where it can be, and never longer than a line. It sits
	-- on the panel above a twenty-second countdown; anything that needs re-reading has
	-- already failed.
	ask: string,
	-- Two to four of them, and exactly one is right. Order here is the order they were
	-- written, not the order they are shown -- the rows are shuffled per question, so
	-- an answer cannot be learned as "the top one".
	answers: { string },
	-- Which entry in `answers` is the right one, from 1.
	correct: number,
	-- What the teacher says once it has been answered, either way. The one thing that
	-- makes this school rather than a quiz: getting it wrong should still leave you
	-- knowing the answer, because that is what the lesson was for.
	because: string,
	-- An optional teacher gesture on a correct answer, overriding the default bow.
	-- Nil means the teacher bows. Content-only; wrong answers are never decorated.
	reaction: LessonReaction?,
	-- The youngest and oldest this is asked of. A seven-year-old and a sixteen-year-old
	-- are in different rooms, and a game that asked them the same thing would be
	-- admitting that the eleven years in between did not happen.
	minAge: number,
	maxAge: number,
}

-- The question in front of the player, pushed to the HUD. Nil means no lesson is
-- running, which is almost all of a life.
--
-- A whole snapshot every push, like every other state in this game, and that now
-- includes the answers: they are rows on a panel rather than discs on the classroom
-- floor, so they travel with the question rather than being built in the room around
-- it.
export type LessonState = {
	ask: string,
	-- The answers, and by their presence the thing that opens the panel: a lesson is
	-- the one thing in this game with nothing to click, so a push carrying answers *is*
	-- the question being asked, and a push carrying none closes it again. That covers
	-- the beat the teacher's line is up, the summary at the end of a lesson, and the
	-- refusal at the door of one you cannot sit.
	answers: { OfferedChoice },
	-- Which question of how many, so the row can say "3 of 8". Unlike a shift's marks,
	-- this genuinely is the number the player wants: a lesson is a fixed number of
	-- questions and knowing how much is left is knowing how the day is going.
	--
	-- Both zero on the two pushes that are not a question: the summary at the end of a
	-- lesson, and the refusal at the door of one you cannot sit. Those carry their whole
	-- message in `ask` and `verdict` and have no position in anything, which is what a
	-- zero here means -- see `secondsTotal`.
	index: number,
	count: number,
	-- How many of the ones asked so far were right. On screen the whole time rather
	-- than saved for a report at the end, because a child who is getting them wrong
	-- should find that out while there are still some left.
	right: number,
	secondsLeft: number,
	-- Zero means there is no clock on this at all, and the client draws no bar. The
	-- signal rather than an extra flag, because a countdown out of nothing is not a
	-- countdown -- and the two pushes it applies to, a lesson's closing summary and a
	-- refusal at the door, are exactly the two the player is not being timed on.
	secondsTotal: number,
	-- Set for the beat after an answer, and the only time this row says anything the
	-- player did not already know. Holds the question's `because` line, so getting it
	-- wrong teaches the answer instead of only recording that you did not have it.
	verdict: string?,
	-- Whether the answers are discs on the classroom floor this question -- the walk-
	-- to-answer mechanic -- rather than rows to click. The rows travel locked either
	-- way, so this is what the panel reads to know it is showing a reference list and
	-- to say so. Nil for the pushes that are not a question.
	physical: boolean?,
	-- Whether that verdict was a right answer, for the colour of it. Meaningless while
	-- `verdict` is nil.
	wasRight: boolean,
}

-- A workout in progress, pushed as a whole snapshot. Three phases:
-- "offer"  — the machine is near, the panel asks Start/Leave
-- "rep"    — the sweep bar is live, the PUSH button is up
-- "verdict" — the hit was scored, the beat before the next rep
--
-- The sweep fraction is computed client-side from `progress`, `sweetCenter`
-- and `sweetHalf`; no payload travels per frame.  The verdict phase is the
-- only push that carries a `grade` and the stat gains so far.
export type WorkoutState = {
	phase: "offer" | "rep" | "verdict",
	-- Machine kind string ("treadmill", "bench", "dumbbells", "pullup").
	machine: string,
	-- Human-readable label for the UI.
	machineLabel: string,
	-- Current rep number (1-indexed), only meaningful during rep/verdict.
	rep: number,
	-- Total reps attempted so far.
	reps: number,
	-- 0-1 position of the sweep needle, computed from elapsed time.
	progress: number,
	-- Centre of the sweet zone. Per-machine, and NOT 0.5 on three of the four --
	-- where the zone sits is one of the things that makes them different machines.
	sweetCenter: number,
	-- Half-widths of the sweet and perfect zones. Sent rather than read from Config
	-- because they are no longer constants: both widen with the character's health,
	-- so the bar the client draws has to come from the same place the grade does.
	sweetHalf: number,
	perfectHalf: number,
	-- How long this machine's sweep takes, and how the needle moves across it. The
	-- client needs both to draw the needle between server ticks; `curve` names a shape
	-- in src/shared/Sweep.luau, which is shared precisely so the drawn bar and the
	-- graded hit can never disagree.
	sweepSeconds: number,
	curve: string,
	-- Share of the sweep already elapsed, 0-1. The client accumulates forward from
	-- this every frame; `progress` is where the needle stood at the last server tick
	-- and is what the verdict freeze displays.
	elapsedShare: number,
	-- Session-local stamina remaining.
	stamina: number,
	maxStamina: number,
	-- Non-nil only during verdict: "Perfect", "Good", or "Miss".
	grade: string?,
	-- Running totals for the session, so the client can show gains.
	healthGained: number,
	looksGained: number,
}

-- One thing you can do with somebody: one row on the panel their dots open.
--
-- Shaped after EventChoice on purpose, because it is the same idea seen from the other
-- end: a choice is the world asking you something, an offer is a person doing it. The
-- fields that differ are the ones that only make sense when there is somebody there --
-- what it does to the bond, and what they say back.
export type PersonOffer = {
	id: string,
	-- Written as the thing you are about to do, not as a question. You are picking it
	-- off a short list while standing in front of the person it is about, so it reads
	-- as the sentence you would say to them.
	label: string,
	-- The years this is on offer. What you do with your father at eight and at forty are
	-- not the same thing, and a person whose offers never changed would be a person the
	-- game had stopped writing.
	minAge: number,
	maxAge: number,
	-- The bond this needs before it appears at all, and the whole reason a bond exists.
	--
	-- This is what makes a relationship visible without a number: the pads in front of
	-- somebody who barely knows you are small talk, and the ones in front of somebody
	-- who does are money, comfort and favours. The player never reads a stat -- they
	-- watch the floor get more generous.
	minBond: number,
	-- What doing it does to how they feel about you. Usually positive, because turning
	-- up is the point -- but not always, and an offer that costs you something with
	-- somebody is the most interesting kind there is.
	bond: number,
	-- What it does to you, if anything. Nil for the many offers that are only about the
	-- other person.
	stats: StatDelta?,
	-- Money they hand you. Nil rather than zero when none does, so "no money involved"
	-- and "gave you nothing" are not the same value in the table.
	--
	-- Only ever positive, and the content file refuses anything else. Nobody you know
	-- charges you for talking to them, and an offer that did would need a price and a
	-- greyed-out row, neither of which a conversation should have.
	money: number?,
	-- What they say once it is done. Their voice, not the game's -- this is the only
	-- writing in AGES that is a person talking to the player rather than the world
	-- narrating at them, and it should sound like it.
	line: string,
	-- Whether this is a favour rather than a moment, and so whether it can be turned
	-- down. Nil and false both mean it cannot.
	--
	-- Authored rather than derived from what the offer gives, because "is this a thing
	-- you are asking of somebody" is a judgement about the sentence and not about its
	-- payout. Asking your mother to sit with you is an ask; her telling you about her
	-- day is not, and no rule about money or bond separates those two.
	--
	-- The odds themselves are not written here. They come off the gap between the
	-- bond and this offer's own minBond -- see Config.People.RefuseAtFloor -- so an
	-- ask is riskiest the year it first appears and safe once somebody has warmed to
	-- you, without an author having to keep a second set of numbers in step.
	ask: boolean?,
	-- What they say when they say no. Required on an ask and refused on anything else,
	-- because a refusal in the game's own voice would break the one rule `line` holds:
	-- the words a person says are theirs. "Not this month, love" is a character; "the
	-- offer was declined" is a system.
	refusedLine: string?,
	-- What must and must not be true of the life for this to be on the floor. Ids from
	-- content/Flags.luau; unknown ones are refused at load.
	--
	-- The finer-grained half of gating a person: somebody who is in every life, but who
	-- has something to say to you that they have to no one else, because of something
	-- you did. A shared history is mostly this rather than a whole extra person.
	requires: { string }?,
	forbids: { string }?,
	-- What doing this makes permanently true about the life. Same field, same ids and
	-- same rules as on EventChoice, because it is the same idea: a decision the player
	-- made, remembered.
	--
	-- The reason it exists here at all is that without it an offer could move a bond and
	-- hand money over and still leave nothing about the life different -- so there was no
	-- way to write a person whose later years know what you did with them in the earlier
	-- ones. Setting and clearing the same flag in one offer is refused at load.
	--
	-- Only ever applied on a yes. An ask that was turned down did not happen, and a
	-- refusal that quietly wrote a flag would be the game recording something the player
	-- watched not occur.
	sets: { string }?,
	clears: { string }?,
	-- What this person becomes to you: a tie id from content/Ties.luau, refused at load
	-- if unknown.
	--
	-- The other half of the same gap, and it is its own field rather than a flag because
	-- a flag is a fact about the *life* and this is a fact about the two of you. Most of
	-- the people in AGES are generated -- the town is thirty ids nobody typed -- so "you
	-- are close to this one" cannot be a declared flag id without declaring thirty of
	-- them, and the moment Config.Town.Count moved it would need thirty-one.
	--
	-- Nil on the great majority of offers. Becoming somebody's friend should be a handful
	-- of rungs in a life, not something that happens on every row of every panel.
	gives: string?,
	-- What they have to already be to you for this to be on the panel. Satisfied by that
	-- tie or any closer one, so an offer written for a friend is not hidden from a best
	-- friend -- rungs, not slots.
	--
	-- This is what makes a friendship worth having rather than a word on a nameplate:
	-- there are things people will only do for somebody they are actually close to, and
	-- this is where that gets said.
	needsTie: string?,
	-- The most the offer appears at, as an upper bound on the bond. The inverse of
	-- minBond and the second half of the gate: minBond says "you need to be at least
	-- this close" and maxBond says "and no closer than this either". Nil means no
	-- ceiling, which is every friendly offer there is.
	--
	-- Its only use is the offers for when a relationship has gone cold -- the snub,
	-- the argument, the cold shoulder -- that would read as bugs if they appeared
	-- while somebody still liked you. They gate on being low, and the repair offer
	-- gates on being low too, so a relationship can be actively damaged and then
	-- actively mended on the same floor.
	maxBond: number?,
	-- What this doing is, when the answer is a walk rather than a talk.
	--
	-- `walksTo` is the id of a place the two of you go to together -- see
	-- Config.Places.Walkable for which ids are legal -- and setting it changes what
	-- accepting does: the person sets off with you, walks behind you along your path,
	-- and says `arrivalLine` when the place is reached. The walk is the content, so a
	-- companion offer carries no stats or money.
	walksTo: string?,
	arrivalLine: string?,
}

-- A kind of relationship somebody can be to you: content, like a flag.
--
-- Kept small on purpose. These are the words a life uses about people, and a game with
-- eleven grades of friendship has replaced a relationship with a progress bar -- which is
-- the exact thing bonds are hidden for.
export type TieDef = {
	id: string,
	-- What goes on their nameplate, lowercase, as you would say it: "friend".
	label: string,
	-- How close this is. Higher is closer, and a tie is only ever replaced by a closer
	-- one -- there is no offer anywhere that walks somebody back down, because the way a
	-- friendship ends in this game is that you stop turning up and the bond decays.
	rank: number,
	-- How many people can be this to you at once, or nil for no limit.
	--
	-- The whole reason a top rung is worth reaching. Without a limit, "best friend" is
	-- something you collect from everybody who ever hit the bond for it, and the word
	-- stops meaning anything. Counted against people *currently in your life*, so a best
	-- friend at school whose years have passed does not hold the slot shut against one
	-- at work.
	limit: number?,
}

-- Somebody who exists in your life. Content, like a job: who they are, where they
-- stand, when they are around, and what they are willing to do for you.
--
-- `castId` points into content/Cast.luau rather than repeating a body here, so the
-- neighbor you visit at nine is built from the same description as the neighbor who
-- knocks at forty and is recognisably the same man.
export type Person = {
	id: string,
	castId: string,
	-- Which place point they stand at. Deliberately reuses the ids the world already
	-- needs -- home, school, store -- because every new id is a part somebody has to
	-- remember to tag in Studio, and a person who silently does not exist is worse than
	-- a person who shares a room.
	placeId: string,
	-- The years they are in your life at all. Outside these they are not spawned, they
	-- are not decayed against, and they are not in the listing: a friend you meet at six
	-- is not somebody you were neglecting at four.
	minAge: number,
	maxAge: number,
	-- How many years older than the player they are. Their age, written as the one thing
	-- about it that never changes.
	--
	-- Stored this way rather than as a number of years because there is no clock in this
	-- game except the player's birthdays -- a life is the only thing time happens to --
	-- so an absolute age would be a figure that had to be nudged forward by hand every
	-- year and would be wrong the moment anything forgot to. A gap between two birth
	-- years is simply true forever, and it says the interesting thing directly: your
	-- mother is twenty-eight years older than you at every age either of you ever is.
	--
	-- Negative for anybody younger. Zero is somebody your own age, which is what a
	-- schoolfriend is.
	ageOffset: number,
	-- Where the bond starts the first time anything moves it. A parent does not begin
	-- indifferent; a neighbor does.
	startingBond: number,
	-- How they turn you away once they have given you their time this year. Their own
	-- sentence rather than a shared one, because "Not now, love, I'm cooking" and "Some
	-- other time" are the same rule said by two different people, and the rule is the
	-- least interesting thing about it.
	busyLine: string,
	-- What must and must not be true of the life for this person to be in it. Ids from
	-- content/Flags.luau; unknown ones are refused at load.
	--
	-- The answer to "if I make a decision for a friend then there should be a friend
	-- for me at school". A gated person is not spawned, not decayed against and not
	-- listed, exactly as if their years had not come round yet -- so a life that never
	-- earned them is not a life that is missing them, it is a life they were never in.
	--
	-- Use it sparingly and never on family. A mother who exists conditionally is not a
	-- branch, she is a bug that looks like one.
	requires: { string }?,
	forbids: { string }?,
	offers: { PersonOffer },
}

-- The person in front of the player, pushed to the HUD. Nil means nobody is, which is
-- most of a life.
--
-- Carries what they have to offer, for the same reason a lesson carries its answers:
-- the panel that opens when the player clicks the dots over their head is built from
-- this, so it opens the instant it is asked for rather than after a round trip.
export type PersonState = {
	-- Which person this is, so an answer coming back can be checked against who the
	-- player is actually standing next to. Never trusted on its own.
	id: string,
	-- Their name as it is written over their head, so the row and the body agree.
	name: string,
	-- What the bond is called, from People.Bands. A phrase and never the number: the
	-- player should know their father is close to them without being shown a score for
	-- it, which would turn a relationship into a progress bar.
	band: string,
	-- Set for the beat after an offer is taken, holding what they said back. Nil the
	-- rest of the time, when the row is only announcing who you are standing next to.
	reply: string?,
	-- Whether that reply was a good one, for the colour of it. Meaningless while `reply`
	-- is nil. A refusal at the door -- somebody who has no time this year -- comes
	-- through as a reply that is not good, which is the honest reading of it.
	replyGood: boolean,
	-- What is on the panel when the player clicks them. Empty for somebody who has
	-- already given you their time this year, and that emptiness is what quiets the
	-- dots over their head: still worth walking up to, nothing left to take.
	offers: { OfferedChoice },
	-- Whether this is a phone call rather than standing next to them. A phone call
	-- opens the same panel in the PhoneCall voice, and the row saying who you are
	-- standing next to does not appear for one, because you are not next to them.
	contact: boolean,
}

-- The people the player has met, as a list the HUD can render as a tappable roster
-- without querying the server. Sent whole on every change (birthday, flag move, offer
-- taken) for the same reason LobbySlotsUpdated is: a per-row push could land out of
-- order and leave a stale row. The player never types into this list -- they only tap
-- a row -- so there is nothing on this wire worth forging.
export type PersonRosterEntry = {
	id: string,
	name: string,
	-- The bond's name, from People.Bands, the same phrase the in-person row uses.
	band: string,
	-- Whether calling is worth it this year: a visit not spent and something left to
	-- offer. What the dot next to a row means.
	available: boolean,
}

-- How many times one person has been visited, and which year those visits belong to.
--
-- One record rather than a `visitsThisYear` and a separate `lastSeen`, because the two
-- are always written in the same breath and two independent fields holding halves of one
-- fact eventually disagree. The year is carried alongside the count instead of the count
-- being cleared on every birthday: a person nobody went to see never needs touching, so
-- an old year simply reads as nought visits when it is next looked at.
export type PersonVisits = {
	-- The age the player was when these visits happened.
	age: number,
	-- How many of them, against Config.People.VisitsPerYear.
	count: number,
}

-- A named somewhere in the world, resolved from the part that marks it rather
-- than from a table of coordinates. `part` is the marker, so `part.Position` is
-- the floor at that spot and is correct however far the building has been moved
-- since the id was written down.
--
-- `label` is the sentence a listing prints ("the shop floor"), and is separate
-- from the id for the same reason an event's title is separate from its id: one
-- of them is shown to a person and one of them is matched against.
export type Place = {
	id: string,
	label: string,
	part: BasePart,
}

-- What putting the subject in the room actually produced: the animal itself, or nil
-- when nothing was staged.
--
-- It used to also carry the point the animal would come to rest on, because floor
-- markers had to be laid out around a spot before the animal reached it. The dots
-- ride the model instead, so what a caller needs is the thing rather than the place
-- -- and the thing stays true continuously, while the place was only ever true at
-- the moment the prompt opened.
export type StagedSubject = Model

-- What the thing the event is about does once the choice has been made, before it
-- leaves. Only meaningful for an event with a subject in the room.
--
--   approach  comes to the player and stands with them
--   withdraw  turns away and goes, without a last look
--   settle    lies down where it is
--
-- The outcome line is the reason this exists. "It shoved its whole head under your
-- palm" and "you held still until it lost interest" are two different things
-- happening in the room, and until now they were the same thing happening on a
-- banner over an animal that stood there either way. A choice whose consequence
-- can be watched should be watched.
--
-- A relationship rather than a clip name: content says what happened and SceneService
-- decides what that looks like. It is also what keeps a bought model a drop-in --
-- "approach" is a route either way, and "settle" is a folded pose here or a Rest clip
-- there.
--
-- Nil is the ordinary answer and means what it always meant: the animal holds
-- where it is while the outcome is read, and then leaves the way it came.
export type ChoiceReaction = "approach" | "withdraw" | "settle"

-- A teacher gesture on a right answer, overriding the default bow. "settle" is a
-- calm nod for questions that are merely correct; "approach" is a step toward the
-- player for the ones that were genuinely earned. Wrong answers always step back
-- regardless.
export type LessonReaction = "settle" | "approach"

export type EventChoice = {
	id: string,
	label: string,
	-- Shown after the choice is made. Second person, past tense.
	outcome: string,
	effects: StatDelta,
	-- All or nothing across an event's choices, enforced at content load: three
	-- answers where one makes the dog do something and the other two leave it
	-- standing reads as two answers that failed rather than as one that was special.
	reaction: ChoiceReaction?,
	-- What taking this answer costs, in whole currency units. Nil means free, which
	-- is true of nearly every choice in the game.
	--
	-- A separate field from `effects` rather than a fifth stat, because money does
	-- not behave like one: a stat is clamped to 0-100 and decays on its own, and
	-- money is unbounded, exact, and only ever moves because something happened. A
	-- choice with a cost the player cannot meet is offered but refused -- see
	-- OfferedChoice.locked -- so a price is a gate as well as a number.
	cost: number?,
	-- What taking it pays. Withheld from the client until the choice is made, unlike
	-- cost, and the asymmetry is deliberate: you cannot decide whether to spend
	-- without being told the price, but being told in advance which answer pays best
	-- turns a life decision into an arithmetic one. Same reason the outcome line and
	-- the stat effects are withheld.
	payout: number?,
	-- What taking this answer does to your record at the job you are working. Whole
	-- units, either direction, and zero is a legal and useful value: an answer your
	-- employer would have no opinion about is a real kind of answer.
	--
	-- All or nothing across an event's choices, and required on every Shift event,
	-- both enforced at content load. Required because a record is the whole reason a
	-- shift has moments in it -- a work event whose answers left no trace would be a
	-- moment your job did not notice, which is exactly what these replaced.
	--
	-- Withheld from the client alongside the outcome and the effects. Being told
	-- which answer your manager would prefer, before you choose, is the same
	-- arithmetic problem as being told which one pays best.
	performance: number?,
	-- What taking this answer makes permanently true about the life, and what it
	-- makes untrue again. Ids from content/Flags.luau; unknown ones are refused at
	-- load.
	--
	-- This and PersonOffer.sets are the only two ways a flag is ever earned, and they
	-- are the same way seen from two ends: an answer the player gave. Deliberately no
	-- third -- a flag written by a service somewhere would be a fact about the player
	-- that no decision of theirs is responsible for, and the whole value of the system
	-- is that every one of them can be traced back to a moment they remember.
	--
	-- `clears` exists for the pairs that are genuinely exclusive -- you cannot both
	-- have been frightened of the dog and not have been -- rather than as a general
	-- undo. Setting and clearing the same flag in one choice is refused at load.
	sets: { string }?,
	clears: { string }?,
	-- The thing you physically do to give this answer, instead of clicking a row.
	-- Nil means this choice is a row on a panel, which is still true of most of the
	-- game. All or nothing across an event's choices, enforced at content load: two
	-- answers you perform and one you click reads as a bug in the two, not as a
	-- third option.
	act: ChoiceAct?,
}

-- How a choice is performed, when performing it is the point.
--
-- Five verbs, and the list is short on purpose. They were not invented and then
-- looked for -- they were read off the sixty-six childhood answers that already
-- existed, and these are what those answers turned out to be. A sixth would mean
-- a new kind of thing a body can do, which is a real addition; a sixth that only
-- one event uses is a bespoke minigame wearing the costume of a system.
--
--   Go     -- get yourself there. Into the puddle, up the stairs, through the gap.
--   Take   -- put your hands on it, and that is the answer. The spoon, the cookie.
--   Carry  -- Take, and then bring it somewhere. Grabbing commits you to nothing;
--            arriving is the answer, so you can pick the cookie up and still be
--            deciding who gets it. The only verb with two halves, and the reason
--            is that changing your mind halfway is a thing children do.
--   Push   -- put your body against it and move it. The rug.
--   Stay   -- be still and let it happen. The one answer that is not an action,
--            which is why it needs a verb of its own: without one it would be
--            indistinguishable from a player who has not decided yet.
export type PropVerb = "Go" | "Take" | "Carry" | "Push" | "Stay"

-- One prop and where it goes, measured from the player at the moment the event
-- opens: how far away, and how far round from the direction the set was laid out in.
--
-- Authored rather than scattered, because distance is meaning here. The rug in
-- "across the rug" has to be between the child and the bright thing, and it is
-- between them because it was written at seven studs and the toy at sixteen on the
-- same bearing. A placement that fanned them at random would be the same three
-- objects and a different event.
--
-- Both numbers are wishes and the room has the veto. A spot inside a wall slides
-- round the arc until it isn't one, and a set that cannot fit at all gives up and
-- becomes a panel. See PropService.
export type PropPlacement = {
	-- An id from content/Props.luau. Unknown ones are refused at load.
	prop: string,
	distance: number?,
	offsetDegrees: number?,
}

export type ChoiceAct = {
	verb: PropVerb,
	-- The thing this answer is given on: the rug you push, the toy you crawl to, the
	-- cookie you pick up. Nil is legal only for Stay, whose answer is given where the
	-- player already is -- so its label floats over their own head instead of over an
	-- object.
	--
	-- Two acts in one event may name the same prop here only when both are Carry,
	-- because a Carry is the one verb whose answer is not given by touching this. Any
	-- other overlap is refused at load: two answers triggered by the same touch means
	-- the event resolves as whichever the loop happened to check first.
	at: PropPlacement?,
	-- Carry only, and required for it: where this one has to be brought. Refused at
	-- load on any other verb, because a destination for something you were never
	-- going to pick up is a line nobody will read again.
	to: PropPlacement?,
}

-- What a prop looks like, in the same spirit as SceneSubject and for the same
-- reason: plain dimensions and two colors, no asset ids, so the rug is a rug on
-- the day it is written rather than on the day somebody models one.
--
-- Deliberately not merged with SceneSubject even though the fields rhyme. A
-- subject walks in, holds a stance and reacts to what you decided; a prop is
-- furniture you do something to. Sharing a type would have given the cookie a
-- walk speed.
-- Figure is the one that is not a primitive: a body and a head, in the two colors,
-- at whatever size the prop declares. It exists because "give the cookie to the
-- other child" is an instruction that means nothing when it is pointed at a cube,
-- and because a child in a sandbox is not worth the avatar machinery a CastMember
-- brings with it -- nobody talks to them, they have no name over their head, and
-- they are gone when the year is.
export type PropShape = "Block" | "Ball" | "Cylinder" | "Figure"

export type PropKind = {
	id: string,
	-- Never shown. What the warnings and the Studio harness call it.
	name: string,
	shape: PropShape,
	size: Vector3,
	color: Color3,
	accentColor: Color3,
	-- How close counts as having reached it. Bigger than it looks for anything a
	-- body is meant to end up *on* rather than next to -- a puddle you are standing
	-- in the middle of, a rug you are halfway across.
	reachStuds: number,
	-- How high above the floor it sits, in studs, measured to its underside. Zero
	-- for anything lying on the ground. Nonzero for a thing at hand height, which is
	-- the difference between a cookie on a plate and a cookie on the carpet.
	liftStuds: number,
}

export type LifeEvent = {
	id: string,
	minAge: number,
	maxAge: number,
	delivery: EventDelivery,
	prompt: string,
	choices: { EventChoice },
	-- How the player answers. Nil means "Panel", so an event written before
	-- enactment existed keeps behaving exactly as it did.
	resolution: EventResolution?,
	-- Relative selection weight among eligible events. Defaults to 1.
	weight: number?,
	-- For NPCApproach events, which member of the cast turns up. Ignored by every
	-- other delivery. Nil is allowed and falls back to the first cast member, so
	-- writing a visitor event is never blocked on casting it -- but an id that
	-- doesn't exist is a content error and throws at start.
	cast: string?,
	-- What the prompt is about, if it is about something you can see. Independent
	-- of delivery and of resolution: the dog turns up whether the event reached you
	-- on a birthday or off a doormat, and whether you answer it on a panel or by
	-- walking. Nil means the event is about nothing in particular, which is true of
	-- most of them -- there is no prop for "you have learned a word that stops
	-- adults where they stand".
	--
	-- Like Enacted, this is always a *request*. A room with nowhere to put the
	-- subject simply doesn't get one, and the event plays exactly as it did before
	-- subjects existed. It must never be the reason a prompt cannot be answered.
	subject: string?,
	-- What is written over the thing the player walks to, for a Wander event. Read
	-- from across the room and from behind, so it is the reason to go rather than
	-- the prompt: "Something is moving under the table", not "A cat has got in".
	--
	-- Ignored by every other delivery, because nothing else puts a nameless object
	-- on the floor -- a letter is a letter and says so by being one.
	--
	-- Nil falls back to a generic line rather than an empty label. An unauthored
	-- lure should read as plain, never as a blank pad the player cannot tell is
	-- interactive at all.
	lure: string?,
	-- Whether this event may be lived more than once in a life. Nil means no, which
	-- is right for nearly everything: the day you were offered a dog happened once.
	--
	-- It exists for work. A career is hundreds of shifts and there will never be
	-- hundreds of authored moments, so without this every shift past the last unseen
	-- event is silent forever -- and a job that stopped having anything happen in it
	-- is a job that went back to being a timer. Selection always prefers something
	-- unseen and only falls back to these once nothing new is left, so a repeatable
	-- event never crowds out a fresh one.
	--
	-- Author it on texture, not on milestones. A quiet hour with nobody in the shop
	-- happens a hundred times in a working life; being handed your first set of keys
	-- happens once.
	repeatable: boolean?,
	-- What must and must not already be true of the life for this to be offered at
	-- all. Ids from content/Flags.luau; unknown ones are refused at load.
	--
	-- This is branching. An event that requires a flag is a piece of the game that
	-- only some lives contain, and the reason a life contains it is a decision its
	-- owner made and can name. Age already gates *when* something can happen; this
	-- gates *whether*, which is the difference between a life with a shape and a
	-- life with a schedule.
	--
	-- Requires is all of them, never any. Two ids together are one condition with two
	-- halves; alternatives are written as two events, which is also how they get to
	-- have two different sets of words.
	requires: { string }?,
	forbids: { string }?,
	-- For Shift events only: WorkService's moment picker is the one thing that
	-- reads these. `minStanding` is a floor on the player's standing at the job
	-- they are working, so a moment can be the thing the ladder unlocks rather
	-- than a label the ladder wears; `jobs` is the list of jobs the moment may
	-- fire on, nil meaning any. Both are ignored by every other delivery, and a
	-- gate that cannot be met just means the event never fires.
	minStanding: number?,
	jobs: { string }?,
}

-- One choice as the client is allowed to see it: the words, the price, and the
-- server's verdict on whether it may be taken.
--
-- `locked` is sent rather than worked out on the client, even though the client
-- knows both the price and the balance and could subtract them itself. Two reasons.
-- The rule about who may spend what belongs on the server, and a client that
-- derives it locally is a second implementation of that rule that can disagree.
-- And a choice locked for some reason other than money -- there will be others --
-- then needs no new field and no new client arithmetic.
export type OfferedChoice = {
	id: string,
	label: string,
	-- What taking it costs, for display. Nil for the overwhelming majority.
	cost: number?,
	-- A short phrase in the same right-hand column a price uses, for a row that has
	-- something to say about itself that is not a figure -- today, the odds on an ask
	-- being refused, in words. Nil for almost every row, and never set together with
	-- `cost`: one column, one thing in it.
	--
	-- Words rather than a number on purpose. The player is deciding whether to spend
	-- their one visit this year on a maybe, and that is a judgement about somebody
	-- they know rather than a sum.
	note: string?,
	-- Presentation only. The server checks affordability again when the answer
	-- arrives, so a client that ignores this gets refused rather than obeyed.
	locked: boolean,
}

-- What the client is told about an offered event. Effects and outcome lines are
-- withheld until a choice is made, so the answer can't be read off the payload.
export type OfferedEvent = {
	id: string,
	delivery: EventDelivery,
	prompt: string,
	choices: { OfferedChoice },
	-- What the *server actually did*, not what the content asked for. An event
	-- authored Enacted arrives here as "Panel" whenever there was nothing in the room
	-- to hang the dots on, so the client renders what exists rather than what was
	-- intended and a fallback needs no second message to announce itself.
	resolution: EventResolution,
}

-- Who the player decided to be, before the life started running.
--
-- Identity only. What the setup menu spent on *stats* is deliberately not in here:
-- those points were added to `stats` the moment the life began and that is where they
-- live, so a copy of them here would be a second answer to a question `stats` already
-- answers -- and the two would drift the first time anything else moved a stat, which
-- is on the very first birthday.
--
-- Gender is likewise not in here even though the menu picks it, because `ProfileData`
-- already has a `gender` field that everything else reads. One fact, one field.
export type LifeSetup = {
	firstName: string,
	lastName: string,
	-- Ids from content/Countries.luau and Config.Setup.Eras. Stored rather than the
	-- display names, so renaming a country in content does not leave old saves showing
	-- a name that no longer exists anywhere.
	countryId: string,
	eraId: string,
}

-- One country a life can begin in.
--
-- What it does today is supply the names -- a life begun in Lagos is named from Lagos --
-- and nothing else. That is a deliberate floor rather than a placeholder: a country that
-- handed out stat bonuses would be this game telling the player that people from one
-- place are born smarter than people from another, which it is not going to do. What it
-- is *for* later is content -- the places, the schools, the jobs, the money -- and every
-- one of those is a fact about a society rather than about a person.
export type Country = {
	id: string,
	name: string,
	-- Drawn from by the shuffle button and by "Surprise Me". Split by gender for the same
	-- reason the town's lists are: a name is picked from the matching list by construction,
	-- so there is no later check that could pass or fail.
	firstNamesMale: { string },
	firstNamesFemale: { string },
	lastNames: { string },
}

-- One era, which today means "one era and three signposts".
--
-- The unavailable ones are real entries rather than text on a wall, because a row the
-- player can see, read and press -- and be told it is not ready yet -- is a promise the
-- game has made and can be held to. A hard-coded "coming soon" label is decoration.
export type Era = {
	id: string,
	name: string,
	-- Shown under the name. On a locked era this is what it *will* be, which is the only
	-- reason a locked row is worth drawing at all.
	blurb: string,
	available: boolean,
}

-- How rare a perk is to roll. Purely a weighting bucket -- rarer is not stronger, per the
-- settled spin design, so this never gates power, only how often a perk comes up.
export type PerkRarity = "common" | "uncommon" | "rare" | "legendary"

-- What kind of thing a perk actually changes. A union rather than a single authored kind,
-- because only one kind exists today (`birthCircumstance`) and the spin system is built to
-- outlive it -- a money-boost multiplier is the next one, and it must not require reshaping
-- this type when it arrives. Every reader of `Perk.effect` is written as a kind-by-kind
-- branch for exactly this reason: adding a case is additive, not a rewrite.
export type PerkKind = "birthCircumstance" | "moneyBoost"

-- One perk effect. Only the fields for the perk's own `kind` are meaningful; the others are
-- absent. A flat table with every field optional rather than one union type per kind, because
-- Luau's `--!strict` cannot narrow a tagged union by string comparison inside `content/
-- Perks.luau` the way it would in a language with real pattern matching -- this shape reads
-- the same either way and keeps `Perks.luau` free of `:: any` casts.
export type PerkEffect = {
	-- birthCircumstance: added to the starting stats the same way a player's own spent
	-- points are, then clamped by the same rule -- so a perk can never hand out a stat
	-- outside the range a player could have chosen themselves.
	statDeltas: { [string]: number }?,
	-- birthCircumstance: whole currency units the life begins with, on top of the usual
	-- zero. Life's `money` field is never negative, so this is never negative either.
	startingMoney: number?,
	-- moneyBoost: a multiplier applied wherever a life's money changes. Unused until
	-- MoneyService is taught to read it -- present now only so the type does not have to
	-- move the day it is.
	moneyMultiplier: number?,
}

-- One perk a spin can land on, and that a player can carry into a new life.
--
-- Content, not Config -- like `Country` and `Era` above, a perk is a fact with a name and a
-- blurb, not a tunable number, so it lives in `content/Perks.luau` the same way countries
-- live in `content/Countries.luau`. Only defined for the lobby: nothing in the game place
-- ever reads a `Perk`, because a perk is spent the moment a life is created and from then on
-- it is just stats and money like any other life's.
export type Perk = {
	id: string,
	name: string,
	-- Shown on the card and in the odds list, so the player knows what they are buying
	-- before they spin and what they are choosing before they spend it.
	blurb: string,
	rarity: PerkRarity,
	kind: PerkKind,
	effect: PerkEffect,
}

-- A perk this player actually owns, and how many. The wire shape of one entry in
-- `ProfileData.perks`, which is a count keyed by id -- this is the same fact spelled out as a
-- row a picker can iterate, the same relationship `SlotSummary` has to `LifeData`.
export type OwnedPerk = {
	id: string,
	count: number,
}

-- One perk as the spin page draws it: everything `content/Perks.luau` knows about it, plus
-- the one number that file computes rather than authors -- its individual odds. Sent rather
-- than left for the client to divide a rarity's weight by a count itself, on the rule every
-- menu in this codebase follows: the numbers on screen are the numbers the server already
-- computed, not a second copy of the same arithmetic that could drift from it.
export type PerkOffer = {
	id: string,
	name: string,
	blurb: string,
	rarity: PerkRarity,
	-- Out of 1. `content/Perks.luau`'s `Odds` divides a tier's weight by how many perks
	-- share it, which is what Roblox requires disclosed before a paid random purchase.
	odds: number,
}

-- One Robux bundle the buy page can offer, mirroring `Config.Spins.Products`. Sent rather
-- than read from Config directly for the same reason `SetupOptions` is: `productId` is what
-- the server is about to check a purchase prompt against, so the page can never dangle a
-- button that opens a prompt for a product that does not exist.
export type SpinProduct = {
	id: string,
	name: string,
	spins: number,
	robuxPrice: number,
	-- 0 until published, exactly like `Config.Lobby.GamePlaceId` -- refused by name rather
	-- than by a failed Robux call.
	productId: number,
}

-- Everything the spins page needs, pushed whenever any of it changes and once on join.
--
-- The catalog and the products ride along on every push rather than arriving on a separate
-- remote the way `LobbySetupOptions` does, and that is a deliberate difference and not an
-- oversight: `SetupOptions` was split off to avoid resending a country list -- dozens of
-- countries, each carrying three name arrays -- on every slot delete. Ten short perk records
-- and three products are close enough to free that a second remote would be ceremony bought
-- with nothing.
export type SpinsState = {
	spinsAvailable: number,
	perksOwned: { OwnedPerk },
	catalog: { PerkOffer },
	products: { SpinProduct },
}

-- Everything the setup menu needs to draw itself, sent once when the menu is called for.
--
-- Sent rather than read from Config by the client, even though the client could require
-- Config directly. The numbers here are the ones the server is about to *validate*
-- against, so shipping them from the same place that enforces them means a menu can
-- never offer a spend the server will then refuse.
export type SetupOptions = {
	-- Which life this is -- 1 for a player's first ever. Purely so the menu can say so.
	lifeNumber: number,
	statPoints: number,
	minPerStat: number,
	maxPerStat: number,
	maxNameLength: number,
	startingStats: Stats,
	countries: { Country },
	-- Which country the card opens on. Sent rather than left as "whichever is first",
	-- because the list is sorted alphabetically for the player's benefit and opening every
	-- menu in the game on whichever nation happens to sort first would be an accident that
	-- reads as a decision. Not a restriction of any kind: the stepper reaches all of them.
	defaultCountryId: string,
	eras: { Era },
}

-- What the client asks for. Every field is checked server-side against the same
-- content and Config the options were built from, so this is a request and not an
-- instruction: a client that sends a country that does not exist, an era that is not
-- ready, or eleven points of stats is refused with a reason rather than obeyed.
export type SetupRequest = {
	gender: Gender,
	firstName: string,
	lastName: string,
	countryId: string,
	eraId: string,
	-- Added to the starting stats. May be negative -- taking looks to buy smarts is the
	-- whole of the mechanic, and a menu that only ever gave points away would be a
	-- reward screen rather than a decision.
	statDeltas: { [string]: number },
}

-- One life: everything that is true of the person currently being played, and nothing
-- that is true of the player.
--
-- The split from `ProfileData` below is what makes save slots possible. The test for which
-- side a field belongs on is not "does it feel permanent" but **does it die when the person
-- does** -- money, bonds, the job and the education are all facts about a human being and
-- go here; how many lives the player has lived is a fact about the player and does not.
--
-- Structurally identical to what `ProfileData` was before slots existed, minus `livesLived`.
-- That is deliberate: every service that reads a life reads exactly the fields it always
-- did, so the slot refactor changed where a life is *found* and nothing about what one *is*.
export type LifeData = {
	ageMonths: number,
	stage: LifeStageId,
	alive: boolean,
	stats: Stats,
	-- Whole currency units held right now. Never negative and never fractional --
	-- MoneyService is the only thing that writes it and guarantees both.
	--
	-- Per life, not per player: it is reset when a new life begins, for the same
	-- reason the seen list is. Money that survived death would be the one thing a
	-- player carried between lives, which turns dying into a setback in a game where
	-- it is meant to be an ending.
	money: number,
	-- Pocket money counted at a birthday but not yet in the player's hands. Its own
	-- field rather than being added straight to `money`, because the two answer
	-- different questions: this is what the player is owed, and money is what they
	-- have.
	--
	-- Non-zero for as long as it takes a parent to cross a room, which is the reason
	-- it is a field at all: a handover nobody could be reached for comes out as money
	-- delayed rather than money lost, and this is the whole difference between the
	-- two. It survives leaving the server for the same reason -- a player who logs
	-- off mid-walk is owed it when they come back. Never destroyed except by death.
	pocketMoneyOwed: number,
	-- The last birthday whose pocket money has been counted into the field above.
	--
	-- This is what makes the grant idempotent: a birthday that somehow runs twice
	-- finds this already at the current age and adds nothing. It also makes a life
	-- that jumps several years at once pay for each of them rather than only the
	-- last, which is exactly what a skipped childhood is.
	--
	-- Clamped up to the player's real age when a profile loads, which is what stops a
	-- save written before pocket money existed from back-paying an entire childhood
	-- on its owner's next birthday.
	pocketMoneyPaidThroughAge: number,
	-- Active in-server seconds banked since the last age-up. Persisted so a
	-- player who leaves mid-year resumes their progress instead of restarting it.
	secondsSinceAgeUp: number,
	-- Events already answered in the *current* life, so a year can't repeat one.
	-- Cleared on respawn: living the same moment again in a new life is fine.
	seenEventIds: { [string]: boolean },
	-- What this life has done, mapped to the age it did it at. Written only by
	-- answering an event, read by events, people and what people offer.
	--
	-- Cleared with the seen list for the same reason and at the same moment: the
	-- friend you made is that child's friend, and a new life that began already
	-- knowing them would be a life that had inherited somebody else's history.
	flags: FlagSet,
	-- The event offered but not yet answered. Persisted so it survives a rejoin,
	-- and so re-joining can't be used to reroll an unwanted prompt.
	pendingEventId: string?,
	-- The event picked and physically placed in the world but not yet reached:
	-- a letter on the mat, a phone ringing in the hall. Deliberately a separate
	-- field from pendingEventId rather than a flag on it, because the two mean
	-- different things to every check that reads them -- "there is something to
	-- find" versus "there is a question open". Persisted, so the letter is still
	-- on the mat after a rejoin instead of vanishing with the session that
	-- staged it.
	deliveringEventId: string?,
	-- Real seconds until the ambient scheduler next tries to stage something.
	-- Counts down only while the player is in a server, so logging out neither
	-- banks quiet time nor resets it. Reset to a fresh random gap after each
	-- staging, which is what keeps ambient events from arriving on a metronome.
	deliveryCountdown: number,
	-- Ambient deliveries staged in the current year, against Ambient.MaxPerYear.
	-- Without this a player who lingers in one year would be buried in mail.
	deliveriesThisYear: number,
	-- The job held right now, or nil for the whole of childhood. Per life like
	-- money is: a career does not survive the person who had it.
	jobId: string?,
	-- Game hours worked in the current year, against ShiftsPerYear * ShiftGameHours.
	--
	-- Hours rather than shifts, and that is the whole design of the cap. Counting
	-- completed shifts would let a player work seven hours, walk out before the
	-- eighth, and come back to a fresh shift forever -- paid without ever spending
	-- one. An hour worked is an hour spent, so there is no length of shift that
	-- games it, and working the full five earns exactly the authored salary.
	--
	-- Persisted, because the year it belongs to outlives the session.
	workGameHoursThisYear: number,
	-- What each job you have ever worked thinks of you, keyed by job id. Built up by
	-- turning up, worked out by walking out, and moved most by how you answer the
	-- things that happen mid-shift.
	--
	-- Kept per job rather than as one number, because it is the ladder: the office
	-- asks what the shop floor made of you, and a single figure would let a good
	-- record anywhere stand in for a good record *there*. It also means a career
	-- change starts you at nothing again, which is true of career changes.
	--
	-- Per life, like the job and the money. Absent keys read as zero, so a job you
	-- have never worked and a job that has no opinion of you yet are the same thing,
	-- which they are.
	jobStanding: { [string]: number },
	-- Jobs that have let you go this year, keyed by job id. Set when standing hits
	-- Config.Work.Standing.FireAt; blocks re-hire at that one employer until the next
	-- birthday clears it. A cooldown rather than a permanent ban -- being sacked costs
	-- you the rest of the year there, not the job forever -- and per job, because the
	-- shop letting you go says nothing about whether the office will have you. Absent
	-- keys read as false: never fired and fired-then-a-year-passed are the same thing.
	firedFrom: { [string]: boolean },
	-- Workouts completed per machine kind in the current year, against
	-- Config.Gym.WorkoutsPerYear. Keyed by machine kind ("treadmill", "bench",
	-- etc.) rather than a single count, so using the treadmill does not spend the
	-- bench. Nil-safe: absent keys read as zero.
	--
	-- Per life, like lessonsThisYear and for the same reason: a new body has not
	-- worked out anywhere yet.
	workoutsThisYear: { [string]: number },
	-- Lessons sat in the current year, against School.LessonsPerYear. The same cap as
	-- workGameHoursThisYear and for the same reason: a player who lingers in one year
	-- should not be able to grind a childhood's worth of smarts out of it.
	--
	-- Also the attendance record, and the only one there is: zero on the birthday that
	-- ends a school year is what charges SmartsPerYearMissed. There is deliberately no
	-- lifetime tally of questions asked and got right, because `smarts` already is one
	-- -- it is the number school exists to move, and a second record of the same fact
	-- would be a number nothing reads.
	--
	-- Per life, like the job and the money: nobody inherits an education.
	lessonsThisYear: number,
	-- How each person you know feels about you, keyed by person id, between
	-- People.MinBond and People.MaxBond.
	--
	-- Deliberately shaped like jobStanding and for the same reason: a relationship is
	-- an opinion held by somebody in particular, and one number covering everybody
	-- would let being adored by your mother stand in for being known by your neighbor.
	--
	-- Absent keys do *not* read as zero here, which is the one place this differs from
	-- jobStanding. A person is authored with a bond they start at -- a mother does not
	-- begin a life indifferent to you -- so an absent key means "has not been met yet"
	-- and the starting figure is what gets written the first time anything moves.
	--
	-- Per life. The hardest of these to accept and the most important: dying does not
	-- carry your family over to the next child, because a relationship that survived
	-- the person who had it would be the one thing in this game that death did not
	-- cost, and everything else here is built on death costing everything.
	bonds: { [string]: number },
	-- Who has been visited, how often, and in which year -- keyed by person id.
	--
	-- Two jobs off one record. It is the yearly cap, because a person already seen
	-- Config.People.VisitsPerYear times at the age you are now has no more time for you;
	-- and it is the decay check, because a person whose record is for an older year than
	-- the one just ending is somebody you did not go to see.
	--
	-- Per life, like the bonds it caps: a new child has been nowhere.
	visits: { [string]: PersonVisits },
	-- What each person you know actually *is* to you -- a tie id from content/Ties.luau
	-- -- keyed by person id. Absent means nothing in particular, which is what almost
	-- everybody is.
	--
	-- Separate from `bonds` rather than derived from it, and that is the whole design.
	-- A bond is how somebody feels about you and it moves both ways on its own: it rises
	-- by turning up and falls by not. A tie is something that was decided, once, by an
	-- offer the player picked -- so it does not quietly appear the year a number crosses
	-- a line, and it does not quietly vanish the year it slips back under. Deriving it
	-- from the bond would make friendship a threshold, which is a thing that happens to
	-- you rather than a thing you did.
	--
	-- Per life, like the bonds beside it, and for the same reason.
	ties: { [string]: string },
	-- Who this life was born as.
	--
	-- Optional, and the absence is load-bearing rather than laziness -- it is the same
	-- device `jobId` and `pendingEventId` use in this type. There is no honest default:
	-- every value biases somebody, and a template that said "male" would hand every
	-- player's *first* life the same answer, because a fresh profile is filled in from
	-- the template exactly like a stored one. Absent means "not decided yet", which is
	-- true of a profile that has never started a life, and DataService rolls it the
	-- moment one does.
	--
	-- Per life, like the bonds and the ties: a new life is a different person.
	gender: Gender?,
	-- Who the player chose to be this life, or absent if they have not chosen yet.
	--
	-- The absence is not just "no name yet" -- it is the *gate*. A profile with no setup
	-- is a life that has not started, and the clock, the auto age-up and the first event
	-- of the year all check it before they move. That is why this is one optional field
	-- rather than a `setupDone` boolean beside a `setup` table: two fields can disagree
	-- about whether a life is running, and exactly one of those disagreements is a life
	-- that ages while the player is still choosing their name.
	--
	-- Per life, like everything above it. Cleared on death, which is what brings the menu
	-- back for the next one.
	setup: LifeSetup?,
}

-- The account: one player, several lives, and the few things that outlive all of them.
--
-- Everything here is deliberately *not* a fact about a person. If a field would be untrue
-- the moment the player started a different life, it belongs in `LifeData` above.
export type ProfileData = {
	-- Which shape this save is in, so a load can tell a save written by an older build from
	-- one written by this one and migrate it rather than misreading it.
	--
	-- Its own field rather than sniffing for a missing key, because "is `slots` absent?"
	-- stops being answerable the moment `Reconcile` fills it in -- which happens before any
	-- migration could look. A version number is the only thing Reconcile cannot forge, since
	-- a save written before this field existed reconciles to the template's value and the
	-- migration reads that as "old", which is exactly right.
	schema: number,
	-- Every life this player has, empty or not. Always exactly `Config.Slots.Count` long,
	-- and never sparse.
	--
	-- Fixed length with empty lives in it rather than a list that grows, because a nil hole
	-- in a Luau array breaks `#` and `ipairs` in ways that are silent and intermittent --
	-- and a "deleted slot 2" would be exactly such a hole. An empty slot is a real LifeData
	-- with no `setup`, which is the same thing "no life here" already meant everywhere else
	-- in this codebase (see Lives.HasBegun), so nothing had to learn a second way to say it.
	slots: { LifeData },
	-- Which slot is being played, 1..#slots. Always valid: clamped on load.
	--
	-- **This is how the lobby tells the game place which life to run.** Deliberately stored
	-- on the profile rather than passed through TeleportData, because teleport payloads are
	-- a channel the server has to treat as untrusted, and "which of my saves am I opening"
	-- is exactly the kind of thing that must not be assertable by a client.
	activeSlot: number,
	-- How many lives this player has finished, across every slot. Account-level on purpose:
	-- it is the measure of how much of this game the player has seen, which is what
	-- `Config.SkipChildhoodMinLives` is really asking about -- somebody on their fourth life
	-- has sat through childhood three times regardless of which slots they were in.
	livesLived: number,
	-- Unspent spins, bought with Robux and waiting to be pulled. Account-level like
	-- `livesLived`, and for the same kind of reason: a spin is not a fact about any one
	-- life, it is a fact about what the player is owed by this account.
	spinsAvailable: number,
	-- Perks this player owns but has not yet spent, keyed by perk id and counting how many
	-- copies -- a dictionary rather than a growable array for two reasons at once: the
	-- ProfileStore array-reconcile gap that `Lives.Reconcile` exists to work around only
	-- bites arrays, so a dictionary sidesteps it outright, and "how many of this perk" is
	-- the only question a perk picker ever asks, which a count answers directly and a list
	-- of duplicate rows would not. A perk is consumed by decrementing its count, never by
	-- removing the key, so "owns none" and "has never owned" read the same -- absent and
	-- zero are both nothing to spend.
	perks: { [string]: number },
	-- Robux purchases already granted, keyed by `receiptInfo.PurchaseId`. What makes
	-- `ProcessReceipt` idempotent: Roblox's own retry system can hand the same receipt to
	-- this callback more than once, and a purchase already in this table is granted again
	-- by name rather than by spins -- checked and recorded before anything is added to
	-- `spinsAvailable`, never after.
	processedReceipts: { [string]: boolean },
}

-- One slot as the lobby menu draws it: enough to fill a card, and nothing else.
--
-- **A summary rather than the LifeData itself, and that is a deliberate boundary.** Sending
-- the whole life down would work today and would quietly make every per-life field part of
-- the client contract -- so the day something private is added to a life (an event's
-- pending id, a flag the player is not meant to see yet) it would already be on the wire.
-- The card needs six facts, so six facts is what crosses.
--
-- `begun` is separate from having a `name` because an empty slot has neither, and a slot
-- being empty is the single thing the card's whole layout branches on. Deriving it from
-- `name == nil` would work and would be a rule written down in two places.
export type SlotSummary = {
	index: number,
	begun: boolean,
	-- All five absent on an empty slot. Absence is the state here for the same reason it is
	-- everywhere else in this codebase -- there is no honest "no name" string, and any
	-- placeholder would be a value the card has to know to special-case.
	name: string?,
	country: string?,
	gender: Gender?,
	ageYears: number?,
	alive: boolean?,
}

-- What the lobby knows about this player, pushed whole whenever any of it changes.
--
-- Carries `slotCount` rather than letting the client read `Config.Slots.Count`, on the same
-- rule as SetupOptions: the client draws exactly what the server is prepared to accept, so
-- a fourth card can never appear for a slot the server would refuse.
export type LobbyState = {
	slots: { SlotSummary },
	activeSlot: number,
	slotCount: number,
	livesLived: number,
}

return Types
