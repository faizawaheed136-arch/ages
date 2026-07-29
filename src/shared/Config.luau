--!strict
-- Every tunable number in the game lives here. No magic numbers in system code.

local Config = {}

Config.Time = {
	-- Age is stored in months for future sub-year content, but aging currently
	-- moves a whole year at a time, so ageMonths is always a multiple of this.
	MonthsPerYear = 12,

	-- The world clock. Nothing displays it yet — the visible day/night cycle
	-- arrives with the world in a later build step — but durations are already
	-- expressed in game time so they don't need re-tuning when it lands.
	-- Safe range: 6-30. Below ~6 a day is over before anything can happen in it.
	RealMinutesPerGameDay = 12,
	GameHoursPerDay = 24,
}

-- Derived, not tuned: 12 real minutes across 24 game hours = 30 real seconds
-- per game hour. Change RealMinutesPerGameDay and every game-time duration in
-- the file rescales with it.
Config.Time.RealSecondsPerGameHour = (Config.Time.RealMinutesPerGameDay * 60) / Config.Time.GameHoursPerDay

-- Aging is player-driven: no wall clock advances the world. A year ends when
-- the player chooses to end it, or when a safety net decides they have been
-- living the same year long enough. Every timer below counts *in-server*
-- time only — time spent logged out never advances a life.

-- Game hours of active play before an adolescent/adult/elder is aged up for
-- them. At the current day length this is 100 x 30s = 50 real minutes.
-- Safe range: 24-300. Too low and the manual button stops feeling like the
-- player's decision; too high and an idle or distracted player stalls.
Config.AutoAgeUpGameHours = 100

-- Same, but for the years below ManualAgeUpMinAge, where there is no button to
-- press. 4 game hours = 2 real minutes, so early childhood costs
-- ManualAgeUpMinAge x that in total. Safe range: 1-12.
Config.ChildAutoAgeUpGameHours = 4

-- The age the player takes the wheel. Below this there is no Age Up button and
-- the safety net alone carries them, because an infant choosing to grow up
-- doesn't fit the fiction. From here on they can play sports, make friends and
-- decide when a year is done, so the choice becomes theirs.
-- Safe range: 0-12. At 0 there is no automatic-only stretch at all.
Config.ManualAgeUpMinAge = 5

-- Completed lives before the "Skip Childhood" button appears in the years below
-- ManualAgeUpMinAge. A first life always plays childhood through, because it is
-- content rather than a wait; from the second life on it is opt-in. At 0 the
-- skip exists immediately and most players would never see those years at all.
-- Safe range: 1-3.
Config.SkipChildhoodMinLives = 1

-- Minimum active seconds between two manual age-ups. Deliberately in *real*
-- seconds, not game time: this is an input rate limit, not a world duration, so
-- it shouldn't move when the day length is re-tuned. It is the "once per year"
-- gate that stops the button being spammed from birth to death in one breath,
-- and doubles as the retry guard on the RequestAgeUp remote.
-- At 60 a player doing nothing else lives 13 to 80 in about an hour, while the
-- auto net above is 50x slower — so pressing Age Up stays a deliberate act, not
-- the thing you do while waiting. Expected to rarely bind once there is enough
-- to do in a year. Safe range: 15-120.
Config.ManualAgeUpCooldownSeconds = 60

-- How often the server banks playtime and refreshes the HUD progress bar.
-- Safe range: 0.5-5. Lower is smoother but costs one remote per player per
-- tick; against a 50 minute threshold the bar looks continuous even at 5.
Config.AgeUpProgressTickSeconds = 1

Config.LifeStages = {
	{ id = "Childhood", minAge = 0, maxAge = 12 },
	{ id = "Adolescence", minAge = 13, maxAge = 17 },
	{ id = "Adulthood", minAge = 18, maxAge = 64 },
	{ id = "Elder", minAge = 65, maxAge = math.huge },
}

-- The toddler years are playable rather than narrated, and the thing that
-- progresses through them is the body itself: what you can do, how fast you can
-- do it, and how tall you are to the world. The house never changes — you do.
--
-- Bands are matched in order by the first maxAge the player's age falls under,
-- so they must stay sorted. The last band is the grown body and is deliberately
-- unbounded, which is what everyone past childhood gets.
Config.Childhood = {
	-- Last age of the playable toddler slice. Resolving an event advances the
	-- year at or below this age and nowhere else: childhood has roughly one
	-- event per year, but from age 6 the count per year climbs steeply and the
	-- same rule would fire a player through a whole life in minutes.
	-- Must line up with the last bounded band below. Safe range: 3-8.
	EndAge = 5,

	-- Quiet real seconds between a childhood event ending the year and the next
	-- one being offered. Without it the years chain nose-to-tail and childhood
	-- reads as a questionnaire; this is the room to look around in between.
	-- Real seconds rather than game time: it is a pacing beat for the person
	-- playing, not a duration in the world. Safe range: 5-45.
	NextEventDelaySeconds = 15,

	-- walkSpeed/jumpPower are Roblox defaults of 16 and 50 at the grown end.
	-- headScale stays high relative to bodyScale on purpose — small children are
	-- mostly head, and it reads instantly as "young" without any custom art.
	-- jumpPower 0 removes jumping entirely, which is the honest version of a
	-- body that cannot yet do it.
	Bands = {
		{ id = "Crawl", maxAge = 0, walkSpeed = 4, jumpPower = 0, bodyScale = 0.30, headScale = 0.55, cameraOffsetY = 0 },
		{ id = "Toddle", maxAge = 1, walkSpeed = 6, jumpPower = 0, bodyScale = 0.38, headScale = 0.60, cameraOffsetY = 0 },
		{ id = "Walk", maxAge = 2, walkSpeed = 8, jumpPower = 0, bodyScale = 0.46, headScale = 0.66, cameraOffsetY = 0 },
		{ id = "Steady", maxAge = 4, walkSpeed = 11, jumpPower = 25, bodyScale = 0.58, headScale = 0.74, cameraOffsetY = 0 },
		{ id = "Run", maxAge = 5, walkSpeed = 13, jumpPower = 35, bodyScale = 0.68, headScale = 0.80, cameraOffsetY = 0 },
		{ id = "Grown", maxAge = math.huge, walkSpeed = 16, jumpPower = 50, bodyScale = 1, headScale = 1, cameraOffsetY = 0 },
	},
}

-- The seam between hand-authored geometry and code. An object in the Studio
-- world becomes an event by being tagged and told which event id it carries, so
-- the house can be rebuilt or redressed without a line of code moving.
--
-- The tag never decides *whether* an event fires — the engine still owns
-- eligibility. A tagged object only says where an event may be reached.
Config.World = {
	-- CollectionService tag added in the Studio Tag Editor.
	InteractTag = "AgesEvent",

	-- Attribute on the tagged instance holding the event id it offers, e.g.
	-- "childhood_first_morning". Missing or unknown ids warn rather than
	-- failing quietly, because a mistyped id looks exactly like a dead object.
	InteractEventAttribute = "EventId",

	-- Studs from the object's center that count as reaching it. Generous on
	-- purpose: a toddler at walkSpeed 4 aiming at a flat rug should not have to
	-- be precise, and the alternative (a Touched event) misses objects the
	-- character never physically collides with.
	-- Safe range: 3-12. Above ~12 objects in one room start overlapping.
	InteractRadius = 6,

	-- How often the server checks players against tagged objects. Cheap at this
	-- scale: a handful of objects against a handful of players. Safe range:
	-- 0.1-1. Above ~1 a toddler can cross a small object between checks.
	InteractTickSeconds = 0.25,

	-- Attribute holding the UserId of the one player a tagged object belongs to.
	-- Hand-placed geometry leaves it off and is public: anyone who walks to the
	-- rug may have the rug's event. A staged delivery sets it, because a letter
	-- addressed to one player must not pay out for whoever else wanders past the
	-- doormat first.
	InteractOwnerAttribute = "OwnerUserId",

	-- Where staged deliveries appear. A point is an empty part in the house
	-- tagged with DeliveryPointTag and told which mode it serves, so the mat,
	-- the phone and the doorstep can be moved in Studio without code moving.
	DeliveryPointTag = "AgesDeliveryPoint",

	-- Attribute on a delivery point naming the mode it serves, matching a
	-- Types.EventDelivery value: "Letter", "PhoneCall" or "NPCApproach".
	DeliveryPointAttribute = "DeliveryMode",
}

-- The world bringing an event to you, rather than a birthday handing it over or
-- you walking into it. Every number here is in *real* seconds: these are pacing
-- beats for the person playing, not durations in the world, so they must not
-- move when the day length is re-tuned. Same reasoning as NextEventDelaySeconds.
Config.Ambient = {
	-- Ambient events start the year *after* childhood ends, and the offset is
	-- derived rather than typed twice. This is not a taste call: below and at
	-- Childhood.EndAge, answering any event advances the year (see EventService),
	-- so an ambient event down there would burn years two at a time and wreck
	-- the one-event-per-year rhythm the toddler slice is built on.
	MinAge = Config.Childhood.EndAge + 1,

	-- The gap before the next ambient delivery is picked uniformly from this
	-- window each time, so the world never arrives on a metronome. At these
	-- values a player aging quickly meets one roughly every year and a half,
	-- while one who lingers gets MaxPerYear and then quiet.
	-- Safe range: 45-600, and Min must stay below Max.
	MinSecondsBetween = 90,
	MaxSecondsBetween = 240,

	-- Ceiling per year of life. The auto age-up net is 50 real minutes, so
	-- without a cap a single unhurried year could carry a dozen of these.
	-- Safe range: 1-5. Above ~5 a year stops having any quiet in it.
	MaxPerYear = 2,

	-- How often the scheduler counts down and considers staging. Coarse on
	-- purpose: this decides when something *starts*, not whether the player has
	-- reached it, so it does not need the interact loop's resolution.
	-- Safe range: 0.5-5.
	TickSeconds = 1,

	-- How long a staged delivery waits before giving up, per mode. Expiry is
	-- silent and the event is *not* marked seen, so a missed one can come back
	-- later in the life -- missing a phone call should feel like missing a phone
	-- call, not like a penalty screen.
	--
	-- 0 means it never expires on a timer. A letter on the mat is patient; it is
	-- cleared at the next birthday instead, along with the year it belonged to.
	-- Safe range: 0, or 20-180. Below ~20 nothing in another room is reachable.
	ExpirySeconds = {
		Letter = 0,
		PhoneCall = 45,
		NPCApproach = 60,
	},
}

-- Answering an event by doing it. An enacted event puts its choices on the floor
-- in front of the player as places to stand, and walking onto one is the answer.
-- The prompt stays on screen, but as a banner: no dimming, no buttons, nothing
-- that takes the room away, because the room is now how the question is answered.
--
-- The markers are fanned around the player at the moment the prompt opens rather
-- than authored into the house. That is the simplest version that works for every
-- event at once, and it is flagged as such: the ambitious version places each
-- choice on a specific real thing -- the crib, the door, the far side of the rug
-- -- and that needs a per-event authoring pass this deliberately does not block.
Config.Enact = {
	-- Studs from the player each marker is placed. Far enough that walking to one
	-- is a decision rather than a step, close enough to fit indoors alongside
	-- furniture. Must stay above MarkerRadius or the markers overlap the player.
	-- Safe range: 4-10.
	MarkerSpread = 7,

	-- The largest a marker may be drawn, in studs from its center, which is also
	-- what counts as standing on it. Kept near World.InteractRadius' reasoning --
	-- a toddler at walkSpeed 4 should not have to be precise -- but smaller,
	-- because here the markers must not overlap each other.
	--
	-- A ceiling rather than the size: at the spread and fan below, three markers
	-- sit about 5.9 studs apart, so a 3-stud radius has them just touching, and
	-- the retry spread would have them overlapping outright. EnactService shrinks
	-- them to whatever the spread it actually used will hold. Raising this past
	-- half the gap therefore changes nothing. Safe range: 1.5-4.
	MarkerRadius = 3,

	-- How far above or below a marker still counts as reaching it. Guards against
	-- answering an event through a floor: the storeys of this house are ~16 studs
	-- apart, so anything well under that is safe. Safe range: 3-8.
	ReachHeightStuds = 5,

	-- Total angle the choices are spread across, centered on the way the player is
	-- facing. Wide enough that the choices are visibly different directions,
	-- narrow enough that they all start on screen. Safe range: 60-160.
	FanDegrees = 100,

	-- A room is not an open field, so a fan that doesn't fit is retried once drawn
	-- in toward the player by this factor. Below ~0.4 the markers crowd each other
	-- and the choice stops reading as a choice. Safe range: 0.4-0.9.
	RetrySpreadScale = 0.6,

	-- How long the markers stand before the event gives up and becomes a panel.
	-- This is the anti-softlock: a player who cannot find the markers, cannot
	-- reach them, or simply does not want to walk still gets their choice.
	-- Long enough to cross a room at a toddler's walkSpeed 4 several times over.
	-- Safe range: 30-180. 0 disables the fallback, which is only safe in testing.
	SecondsToChoose = 75,

	-- How often the server checks players against their own markers. Matches
	-- World.InteractTickSeconds' reasoning and is deliberately no finer: the
	-- markers are larger than a tagged object and the player is slower than the
	-- tick. Safe range: 0.1-1.
	TickSeconds = 0.25,

	-- Content limits, enforced at server start rather than discovered in play.
	-- More markers than this crowd the fan until each one shrinks below a size
	-- worth walking at, and a label longer than this cannot be read off a floor
	-- marker at a glance -- both are authoring mistakes that would otherwise look
	-- like a bad-feeling event rather than like a mistake.
	-- Safe range: 2-5 and 24-64.
	MaxChoices = 4,
	MaxLabelLength = 48,
}

-- Roblox asset ids, kept together because they are the one class of value that
-- cannot be decided from here: an id has to be picked in Studio or uploaded to
-- an account, and a wrong one fails at runtime rather than at build.
--
-- An empty string means "not chosen yet" and is handled everywhere it is read --
-- the phone simply rings silently rather than erroring on a made-up id. That is
-- deliberate: a placeholder id that happens to resolve to someone else's asset
-- is far worse than no sound. Fill these in from the Studio asset picker.
Config.Assets = {
	Sounds = {
		PhoneRing = "",
		LetterArrive = "",
		DoorKnock = "",
	},

	-- Animation ids for visitors. Empty means the rig falls back to standing
	-- still, which looks wrong on purpose -- a visibly unfinished NPC is better
	-- than one that silently never animates and is assumed to be working.
	-- Greet and Talk are one-shot; Idle and Walk are looped and cross-faded.
	Animations = {
		NPCIdle = "",
		NPCWalk = "",
		NPCGreet = "",
		NPCTalk = "",
	},
}

-- Visitors: the people the world can send to your door. Movement is a straight
-- walk from the doorstep to a waiting spot, with no pathfinding graph -- the
-- simplest version that is honest about what it does, flagged here because the
-- moment a visitor has to cross a cluttered room it will need replacing with
-- PathfindingService.
Config.NPC = {
	-- How far in from the door a visitor comes before waiting. Far enough to be
	-- indoors and clear of the door swing, close enough that they are not
	-- standing in the middle of the room. Safe range: 3-10.
	ApproachStuds = 6,

	-- Slower than a player on purpose: someone arriving at your door is not in a
	-- hurry, and it gives the walk time to read. Safe range: 6-16.
	WalkSpeed = 9,

	-- Seconds allowed for a walk in or out before the rig is removed regardless.
	-- Movement can stall against geometry, and a visitor frozen in the hallway
	-- forever is worse than one who quietly gives up. Safe range: 4-20.
	WalkTimeoutSeconds = 8,

	-- Head tracking. This is the whole difference between a mannequin and a
	-- person and it costs no assets at all, so it runs even before a single
	-- animation id has been filled in above.
	-- LookTickSeconds safe range: 0.03-0.2 -- above ~0.2 the head visibly steps.
	LookTickSeconds = 0.06,
	-- Past these a real person turns their body rather than their neck, so the
	-- head clamps instead of swivelling like an owl. Degrees.
	-- Safe range: 40-90 and 15-40.
	LookMaxYawDegrees = 70,
	LookMaxPitchDegrees = 25,
	-- How much of the remaining angle the head closes each tick, 0-1. Low is
	-- languid, 1 snaps instantly. Safe range: 0.05-0.4.
	LookResponsiveness = 0.18,

	-- How far away a visitor bothers tracking the player at all. Beyond this
	-- they face front. Safe range: 10-60.
	LookMaxDistance = 30,

	-- How long a visitor stays talking after the player reaches them, before
	-- turning to leave. Runs underneath the prompt the player is reading, so it
	-- wants to be close to how long that takes -- see UI.EventOutcomeSeconds.
	-- Safe range: 0-8. At 0 they turn on their heel mid-sentence.
	TalkBeatSeconds = 3,
}

Config.Stats = {
	Min = 0,
	Max = 100,
	WarningThreshold = 15,

	Starting = {
		health = 100,
		happiness = 70,
		smarts = 50,
		looks = 50,
	},

	-- Flat decay applied once per in-game year.
	DecayPerYear = {
		health = 1,
		happiness = 1,
		smarts = 0,
		looks = 1,
	},

	-- Decay is multiplied by this once age crosses ElderDecayStartAge.
	ElderDecayStartAge = 60,
	ElderDecayMultiplier = 3,
}

Config.UI = {
	-- How long a passive notice (e.g. an automatic age-up) stays on screen, and
	-- how long it takes to fade in/out. Safe range: 2-8 and 0.2-1.
	NoticeSeconds = 4.5,
	NoticeFadeSeconds = 0.4,

	-- How long the outcome of a choice stays up before the panel clears. Long
	-- enough to read two sentences without rushing. Safe range: 3-10.
	EventOutcomeSeconds = 5.5,

	-- The server answers every accepted choice, so silence means it was refused
	-- or dropped in flight. After this the choices come back rather than leaving
	-- a dead panel on screen. Safe range: 2-10 — long enough that a slow server
	-- doesn't re-enable a choice that is about to resolve.
	EventResponseTimeoutSeconds = 5,
}

Config.Death = {
	-- Natural mortality only rolls once age >= RampStartAge.
	-- ChancePerYear = min(MaxChancePerYear, BaseChancePerYear * (age - RampStartAge) ^ Exponent)
	RampStartAge = 65,
	BaseChancePerYear = 0.01,
	Exponent = 1.6,
	MaxChancePerYear = 0.6,

	-- How long the death screen holds before the next life starts.
	-- Safe range: 3-15. Long enough to read the summary, short enough that it
	-- doesn't feel like a punishment.
	RespawnDelaySeconds = 5,
}

return Config
