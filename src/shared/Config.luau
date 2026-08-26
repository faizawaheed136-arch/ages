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

	-- Weeks in a year, for rates that are quoted by the week. There is no in-year
	-- week clock and deliberately isn't one: a week is simply how a person talks
	-- about small recurring money -- "you get five a week" -- while a birthday is
	-- the only moment the game has to actually hand any over. This is the number
	-- that turns the one into the other.
	--
	-- Not a tunable in any honest sense; a year has 52 weeks. It lives here because
	-- it appears in a payout, and a payout with a bare 52 sitting in it is exactly
	-- the magic number this file exists to stop.
	WeeksPerYear = 52,
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

-- The same rate limit, but for the years below ManualAgeUpMinAge. Shorter on
-- purpose: a toddler year has no shift to work and no lesson to sit, so
-- holding it to the same 60-second gate as a self-directed year would make
-- the button a waiting room rather than pacing. 15 still stops it being
-- spammed birth-to-five in one breath, which is what "SkipChildhood" is for
-- if a player wants that instead. Safe range: 5-30.
Config.ChildManualAgeUpCooldownSeconds = 15

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

-- How big a body is at a given age. **One curve for everybody in the world**, and
-- that is the entire point of it rather than a tidiness note.
--
-- Height used to be answered twice. The player's answer was the childhood band
-- ladder below -- a real one, with the head kept large so a toddler reads as a
-- toddler. Everybody else's answer was a number drawn once at generation and never
-- looked at again, which produced two separate wrongnesses at once: a child NPC was
-- a *short adult* rather than a child, because nothing scaled the head with the
-- body; and they never grew, so the kid you played out front with at four was
-- exactly as tall at seventeen. Both are the same bug, and the fix is that age
-- decides size for a townsperson exactly as it already did for the player.
--
-- Linear between keys, flat outside them. The first five keys reproduce the
-- childhood bands **exactly** -- they are where those numbers now live -- so
-- deriving the bands from this changes nothing about the player. The keys past
-- five are new, and they are the years nothing modelled before: a twelve-year-old
-- classmate is not adult-sized and never was.
--
-- head is deliberately above body everywhere below eighteen. Small people are
-- mostly head, and it is the whole of what reads as "young" at a distance without
-- a single piece of custom art.
Config.Growth = {
	-- Sorted by age, and must stay sorted -- the lookup walks them in order.
	-- Safe range: body 0.2-1.1, head 0.5-1.1, both climbing to 1 at eighteen.
	Keys = {
		{ age = 0, body = 0.30, head = 0.55 },
		{ age = 1, body = 0.38, head = 0.60 },
		{ age = 2, body = 0.46, head = 0.66 },
		{ age = 4, body = 0.58, head = 0.74 },
		{ age = 5, body = 0.68, head = 0.80 },
		{ age = 8, body = 0.76, head = 0.86 },
		{ age = 11, body = 0.83, head = 0.91 },
		{ age = 14, body = 0.91, head = 0.96 },
		{ age = 18, body = 1.00, head = 1.00 },
		-- People do lose height, and a life that runs to ninety standing next to a
		-- man who is exactly as tall as he was at twenty is a small lie the curve
		-- is already shaped to avoid telling. Slight on purpose: three percent is
		-- noticeable side by side and invisible on its own, which is correct.
		{ age = 75, body = 0.97, head = 1.00 },
	},
}

-- The lookup, and the one function in this file. It lives here rather than in a
-- module of its own because the childhood bands below are *derived from it* at
-- load, and a module Config required could not itself require Config. Keeping the
-- keys and the reading of them together is what stops the two answers drifting
-- apart again, which is the bug this whole section exists to close.
function Config.Growth.At(ageYears: number): (number, number)
	local keys = Config.Growth.Keys
	local first = keys[1]
	if ageYears <= first.age then
		return first.body, first.head
	end
	for index = 2, #keys do
		local key = keys[index]
		if ageYears <= key.age then
			local previous = keys[index - 1]
			local span = key.age - previous.age
			-- Guard rather than assume: two keys written at the same age would be a
			-- divide by zero that produced a nan-sized body, which Roblox renders as
			-- nothing at all and no error anywhere says why.
			local t = if span > 0 then (ageYears - previous.age) / span else 1
			return previous.body + (key.body - previous.body) * t,
				previous.head + (key.head - previous.head) * t
		end
	end
	local last = keys[#keys]
	return last.body, last.head
end

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
	-- one being *handed over*, on the birthday path. Only reached by an event
	-- authored Memory or Direct, which childhood no longer uses -- the toddler
	-- years go through Wander below. Kept because that path is still legal and a
	-- childhood event re-authored onto it tomorrow should not chain nose-to-tail.
	-- Real seconds rather than game time: it is a pacing beat for the person
	-- playing, not a duration in the world. Safe range: 5-45.
	NextEventDelaySeconds = 15,

	-- The toddler loop. A childhood event is not handed over on a birthday: it is
	-- put somewhere on the floor with a line pointing at it, and reaching it is
	-- what opens it. This is the whole of what a nought-to-five-year-old does, so
	-- the numbers here are the pacing of the opening five minutes of the game.
	Wander = {
		-- How far off the thing is put, in studs. The floor of this is the number
		-- that matters: too near and it is handed to you after all, which is the
		-- exact failure this replaced. Twelve studs is three seconds of crawling at
		-- the Crawl band's speed of 4 and about one at Run's 13, so the journey
		-- shortens as the body gets better -- which is the growing up, told by
		-- movement instead of by a number on a panel.
		-- Safe range: 8-20 near, 20-45 far. Far must exceed near.
		NearStuds = 12,
		FarStuds = 28,

		-- How many directions are tried before giving up on this tick. A full
		-- circle is swept, because a toddler's room has no front. Twelve is one
		-- every thirty degrees, which is finer than a body is wide at this
		-- distance, so a reachable spot is not missed for want of looking.
		-- Safe range: 6-24. Higher costs raycasts, not quality.
		Bearings = 12,

		-- How many distances are tried on each bearing, between NearStuds and
		-- FarStuds. Two is near and far; more fills in between, which matters in a
		-- small room where the far ring is entirely inside the walls.
		-- Safe range: 2-6.
		Rings = 3,

		-- The distance tried only when every ring above has failed. A bedroom can
		-- be under twenty-four studs corner to corner, and in that room NearStuds
		-- is already through a wall -- so without this the honest rule "never put
		-- it within arm's reach" quietly becomes "never put out anything at all",
		-- and childhood is an empty floor. A short crawl is worse than a long one
		-- and far better than nothing, which is the whole order of preference.
		-- Safe range: 4-10. Must be below NearStuds or it is not a fallback.
		FallbackStuds = 6,

		-- How close counts as having got there. Generous on purpose: this is a
		-- toddler with no jump and a wide turning circle, and a target that has to
		-- be hit precisely would be a dexterity test at the age the player has the
		-- least control they will ever have. Safe range: 3-7.
		ReachStuds = 4.5,

		-- How often the loop looks at where the player is. Safe range: 0.1-0.5.
		TickSeconds = 0.25,

		-- The beat between an event resolving and the next thing appearing across
		-- the room. Not dead time: the outcome line is still on screen and the
		-- subject of the last scene is still walking out, so this is the length of
		-- the ending rather than a gap before the beginning. Anything much longer
		-- and the toddler is standing in a room with nothing in it, which is the
		-- one state this whole system exists to make impossible.
		-- Safe range: 2-8.
		NextSeconds = 4,

		-- What is written over the thing when the event did not author a lure.
		-- Deliberately plain and deliberately not empty: a pad with no words on it
		-- is scenery, and a toddler who cannot tell it apart from the furniture has
		-- nothing to do.
		DefaultLure = "Something over here",
	},

	-- walkSpeed/jumpPower are Roblox defaults of 16 and 50 at the grown end.
	-- jumpPower 0 removes jumping entirely, which is the honest version of a
	-- body that cannot yet do it.
	--
	-- **Size is not here.** A band says what a body can *do*; Config.Growth above
	-- says how big it is, continuously and for everybody, and the two were split
	-- the day townsfolk needed the second answer without wanting the first. A band
	-- carrying its own bodyScale meant the player grew in five visible steps and
	-- an NPC never grew at all -- and it meant "how tall is a two-year-old" had two
	-- answers in two files, which is the shape of a bug rather than of a tunable.
	--
	-- The bands still end at five while the curve runs to eighteen, and that is
	-- correct: what changes between six and eighteen is your height, not whether
	-- you can jump.
	Bands = {
		{ id = "Crawl", maxAge = 0, walkSpeed = 4, jumpPower = 0, cameraOffsetY = 0 },
		{ id = "Toddle", maxAge = 1, walkSpeed = 6, jumpPower = 0, cameraOffsetY = 0 },
		{ id = "Walk", maxAge = 2, walkSpeed = 8, jumpPower = 0, cameraOffsetY = 0 },
		{ id = "Steady", maxAge = 4, walkSpeed = 11, jumpPower = 25, cameraOffsetY = 0 },
		{ id = "Run", maxAge = 5, walkSpeed = 13, jumpPower = 35, cameraOffsetY = 0 },
		{ id = "Grown", maxAge = math.huge, walkSpeed = 16, jumpPower = 50, cameraOffsetY = 0 },
	},

	-- How each band moves, keyed by band id, then by the slot names Roblox's own
	-- Animate script uses: idle, walk, run, jump, fall, climb. A band with no
	-- entry moves the way Roblox ships; a slot with no entry inside a band does
	-- too, so overriding a crawl does not cost you a jump animation.
	--
	-- Ids may be written as a bare number or as "rbxassetid://N"; both are
	-- normalised at startup, and anything else is refused there rather than
	-- becoming a body that silently keeps standing up.
	--
	-- Empty because the animations are not uploaded yet -- that needs a Roblox
	-- group to own them. This is the seam, not the content: filling in the two
	-- commented lines below is the entire job once the group exists, and no code
	-- changes with them.
	--
	--   Crawl = { idle = 0, walk = 0, run = 0 },
	--   Toddle = { walk = 0, run = 0 },
	--
	-- Only the first three bands are likely to want anything. By Steady a child
	-- walks like a short adult, which Roblox's default already is.
	Animations = {} :: { [string]: { [string]: string | number } },
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

	-- CollectionService tag that marks floor/wall parts as a named zone.
	-- WorldEventService reads this and emits "zone:{zoneId}" into context
	-- tags whenever a player stands inside a tagged part, so events can
	-- prefer to fire when the player is in the right room -- gym events
	-- when they are on the gym floor, for instance.
	ZoneTag = "AgesZone",

	-- Attribute on a zone-part holding its string id. The id is free-form
	-- and becomes the tail of the context tag: a part tagged with ZoneTag
	-- and an AgesZoneId attribute of "gym" emits "zone:gym". Unknown ids
	-- are harmless — the picker simply sees a tag it has no event for and
	-- moves on.
	ZoneAttribute = "AgesZoneId",

	-- How close the player has to be to a zone part before its id is emitted
	-- as a context tag. Generous so a player who is in the room -- even standing
	-- away from the tagged floor -- is "in" the zone. Safe range: 10-40.
	ZoneContextRadius = 20,

	-- Where staged deliveries appear. A point is an empty part in the house
	-- tagged with DeliveryPointTag and told which mode it serves, so the mat,
	-- the phone and the doorstep can be moved in Studio without code moving.
	DeliveryPointTag = "AgesDeliveryPoint",

	-- Attribute on a delivery point naming the mode it serves, matching a
	-- Types.EventDelivery value: "Letter", "PhoneCall" or "NPCApproach".
	DeliveryPointAttribute = "DeliveryMode",

	-- Folder in ServerStorage holding real models for event subjects, each named
	-- after the subject id it replaces -- a Model called "dog" takes over from the
	-- built-in placeholder for the "dog" subject and nothing else changes.
	--
	-- The folder does not have to exist. Missing, or missing the model, is the
	-- ordinary state and means the placeholder stands in, so a subject is never
	-- blocked on a shopping trip. ServerStorage rather than ReplicatedStorage
	-- because only the server ever builds one, and a model the client holds a copy
	-- of is a model the client can read the game out of.
	SubjectFolder = "AgesSubjects",

	-- The same arrangement for props, and separate from the folder above rather
	-- than shared with it because the two are different jobs: a subject is an
	-- animal that walks in, and a prop is a rug you shove. Sharing one folder would
	-- make "dog" ambiguous the first time somebody wants a toy dog.
	PropFolder = "AgesProps",

	-- Somewhere in the world the game can name. A place point is an empty part
	-- tagged with PlacePointTag and told which id it answers to, and it exists
	-- because the alternative is a table of coordinates in Luau: the moment a
	-- wall moves in Studio, that table is a list of spots inside walls and
	-- nothing in the game is in a position to notice.
	--
	-- Not a teleport network and not a fast-travel menu. It is the vocabulary a
	-- system uses to say "the shop floor" -- what the debug console goes to now,
	-- what a job will clock in at later, and what an event will one day be told
	-- to fire at. The player still walks.
	PlacePointTag = "AgesPlacePoint",

	-- Attribute on a place point holding its id: "home", "school", "store". Ids
	-- come from tools/world_plan.py, which is also what generates the points, so
	-- read_house.py can hold the two to each other and fail when they disagree.
	PlacePointAttribute = "PlaceId",

	-- Attribute holding the human sentence for the same point, which is what a
	-- listing prints. On the part rather than in a table here for the reason the
	-- position is: one of the two would rot, and it would be this one.
	PlacePointLabelAttribute = "PlaceLabel",

	-- The id prefix both world generators use for a place point that is a *route
	-- node* rather than a destination: a crossing, the middle of an avenue, the
	-- corridor through the mall. Roughly 174 of the city's 382 points are these.
	--
	-- Here rather than open-coded in the one system that has to tell them apart,
	-- because it is the world's own naming convention -- gen_town.py and
	-- gen_city.py both hold to it -- and this block is already where the rest of
	-- that convention is written down. A system that needs somewhere a player can
	-- be *sent* (Geography's hunt is the first) must skip these: "go to cross
	-- street 4" names a road marking, not a place, and being told to find one is
	-- being told to find nothing.
	--
	-- If the generators ever rename the convention, this is the one line to change.
	PlaceWaypointPrefix = "wp_",

	-- How far above a place point a character is set down. A place point marks
	-- the floor, and a body dropped with its middle on the floor is a body
	-- half in it -- this is a body's own half-height plus a little air to fall
	-- through, so the landing is a step rather than a shove.
	-- Safe range: 3-8. Below ~3 the character can spawn inside the floor.
	PlaceDropStuds = 4,

	-- Somewhere a townsperson might be walking to. An empty part tagged with this and
	-- nothing else -- no id, no label -- because unlike a place point it is not a spot
	-- anything asks for by name. It is a street corner, a bench, the end of a path.
	--
	-- **Entirely optional.** With none of these tagged, townsfolk wander to probed spots
	-- around the place they belong to, which works in a bare world and is what the game
	-- does today. Tagging them is how a builder turns aimless wandering into people using
	-- the paths that were actually built, without a line of code moving.
	TownPointTag = "AgesTownPoint",

	-- Sports facilities. Each interactive piece (goal, hoop, net, swing) is tagged
	-- with SportTag and carries a FacilityKind attribute whose value is one of the
	-- kind constants below. The code reads the tag to discover interactivity; the
	-- kind tells it what kind of interaction to offer.
	SportTag = "AgesSportFacility",
	SportKindAttribute = "FacilityKind",
	SportKind = {
		Soccer = "soccer",
		Basketball = "basketball",
		Tennis = "tennis",
		Playground = "playground",
		Track = "track",
	},
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

	-- How close an NPC has to be to the player for their cast to count as
	-- "someone is nearby" in context routing. A friend at the end of the
	-- hallway should weight a friend-tagged event; a stranger across town
	-- should not. Measured in studs from the player's root part to the NPC's
	-- root part. Safe range: 5-30.
	NPCContextRadius = 15,

	-- Which life flags are reported as context tags when the picker is
	-- looking for a candidate. Each string here is emitted as "flag:{flagId}"
	-- so an event can say "I prefer to fire when this flag is held" and another
	-- event can say "I only fire when it is absent" via its `forbids` field.
	-- Only flags that appear in Config.Flags should be listed; unknown flags
	-- silently produce no tag rather than error, because the list grows with
	-- content and the picker must not break when a new flag is authored.
	FlagContext = { "sick", "gym_joined", "in_debt" },
}

-- How the player talks to anything at all. A badge on its chest reading "E"; get
-- near, it wakes up, click it or press the key and the options come up. One
-- grammar for a person and for an animal, because learning how to talk to this
-- world should happen once.
--
-- Not for a lesson. A lesson is something you are already inside rather than a thing
-- in the room, so its questions open themselves; see SchoolService.
Config.Interact = {
	-- How close the player has to be before the badge can be clicked. Generous on
	-- purpose: this is a game partly played as a toddler at walkSpeed 4, and a
	-- reach that demands precision would turn talking to your mother into parking.
	-- Roughly a room's width. Safe range: 8-20.
	ReachStuds = 12,

	-- How long the badge takes to wake up when you come into range, and to settle
	-- again when you leave. Short enough to read as a response to you rather than
	-- an animation playing at you. Safe range: 0.1-0.4.
	WakeSeconds = 0.18,

	-- The key that does the same thing as clicking the badge, and the letter printed
	-- on it.
	--
	-- Set explicitly rather than left at the ProximityPrompt default, because the
	-- badge has to print the key that actually works, and a default that Roblox
	-- changes one day would leave the game telling the player to press a key that
	-- does nothing. One source, both ends.
	KeyboardKey = Enum.KeyCode.E,

	-- The universal pickup key. Everything a shift ever asks you to physically pick
	-- up or hand off -- a shelf item, a topping, a package -- answers to this one
	-- key rather than each task inventing its own, for the same reason E is one key
	-- and not forty-nine: a player who has learned it once has learned it for the
	-- rest of the game. Distinct from KeyboardKey because the two answer different
	-- questions -- E opens a conversation, P does something with your hands -- and a
	-- prompt that used the same key for both would leave a player unable to tell,
	-- from the letter alone, which one they were about to press.
	PickupKeyboardKey = Enum.KeyCode.P,

	-- How far the badge and the nameplate carry, as multiples of ReachStuds.
	--
	-- Two numbers rather than one because they answer different questions, and the gap
	-- between them is the whole design. The badge is *signposting* -- "there is somebody
	-- over there worth walking to" -- and it should out-range the reach that makes it
	-- clickable, or a person only announces themselves once you are standing on them. A
	-- name is *identification*, and it is only worth reading about somebody you are
	-- actually approaching.
	--
	-- The name used to carry further than the badge (3.5, so 42 studs on a town whose whole
	-- route graph spans about 150) and drew through walls, which meant standing anywhere
	-- outdoors put a drift of names across the screen belonging to people behind buildings
	-- on the other side of the street. Now it is the shorter of the two: you see that
	-- somebody is there from a long way off, and you learn who they are as you close.
	--
	-- Safe range: badge 2-3.5, name 1.2-2. Name below about 1.2 arrives after the badge is
	-- already clickable, which is too late to help you choose who to walk to.
	DotsRangeMultiplier = 2.5,
	NameRangeMultiplier = 1.6,
}

Config.SpeechBubble = {
	-- What a person says while standing in front of the player, read from over their own
	-- head. See SpeechBubble.luau -- this replaces the reply that used to sit in the HUD's
	-- standing-next-to caption, on the same "a person's words belong to that person" logic
	-- the quoted caption already used.
	Width = 5.6,
	Height = 1.4,
	MaxTextSize = 16,
	-- How high above the top of a person's own bounding box the card floats, on top of the
	-- three-dot billboard and the nameplate already stacked there -- DOTS_LIFT (1.1) plus
	-- NAMEPLATE_LIFT (0.95) plus the nameplate's own height in Interact.luau. Not measured
	-- to the pixel against that stack; generous on purpose so a tall nameplate can never
	-- clip the bottom of a reply. Safe range: 2.2-3.2.
	LiftAboveHeadStuds = 2.7,
	MaxDistanceStuds = 45,
	-- How long a line holds before it fades, and how long the fade itself takes.
	HoldSeconds = 3.5,
	FadeSeconds = 0.25,
	BackgroundColor = Color3.fromRGB(18, 18, 22),
	BackgroundTransparency = 0.12,
	StrokeColor = Color3.fromRGB(255, 255, 255),
	-- The one color channel this card has, same rule ChoicePanel's outcome color follows:
	-- warm when the answer was good, the panel's own color otherwise. A refusal is not an
	-- error, so it is never colored like one.
	GoodStrokeColor = Color3.fromRGB(120, 220, 150),
	TextColor = Color3.fromRGB(238, 234, 226),
	GoodTextColor = Color3.fromRGB(150, 235, 170),
}

-- Answering an event by going to the thing it is about. An enacted event puts three
-- dots over whatever it is about -- a dog, later a vehicle or a machine -- and the
-- player walks across to it and clicks them. The prompt stays on screen as a banner
-- while they do: no dimming, no buttons, nothing that takes the room away, because
-- the room is the thing being crossed.
--
-- The four numbers below are all that is left of a much larger system. There used to
-- be a fan of lit discs on the floor, one per choice, each at its own bearing off the
-- animal, and walking onto one was the answer; roughly two thirds of this file was the
-- geometry for fitting that arrangement into a living room. It is gone. A Roblox
-- player expects to walk up to a thing and press it, and that is now what happens.
--
-- What survived is the walk. That was always the mechanic and it never needed the
-- floor.
Config.Enact = {
	-- How long the dots stand before the event gives up and becomes a panel. This is
	-- the anti-softlock: a player who cannot find the animal, cannot reach it, or
	-- simply does not want to walk still gets their choice. Long enough to cross a
	-- room at a toddler's walkSpeed 4 several times over.
	-- Safe range: 30-180. 0 disables the fallback, which is only safe in testing.
	SecondsToChoose = 75,

	-- How often the server checks that an enactment is still answerable -- its subject
	-- still in the world, its prompt still the player's, its clock not yet run out.
	-- Nothing about answering runs on this tick: a click arrives on its own remote the
	-- instant it happens. Safe range: 0.1-1.
	TickSeconds = 0.25,

	-- Content limits, enforced at server start rather than discovered in play. More
	-- than MaxChoices answers is a menu rather than a decision, and a label past
	-- MaxLabelLength wraps to three lines on a 400-stud panel and stops being
	-- readable at a glance. Both are authoring mistakes that would otherwise look
	-- like a bad-feeling event rather than like a mistake.
	-- Safe range: 2-5 and 24-64.
	MaxChoices = 4,
	MaxLabelLength = 48,
}

-- The schema fields every event carries, regardless of delivery. These are
-- the bounds on the fields that have bounds; the rest are validated by the
-- content loader against their own registries (Flags, StatName, the future
-- Ties registry phase 5 installs). See `docs/phase2_event_schema.md` and
-- Types.LifeEvent.
Config.Events = {
	-- Upper bound on `cooldown`, in real seconds. Twice the longest ambient
	-- gap, so a cooldown never outlasts the schedule that would have asked
	-- for the event again. Above this, an authored cooldown is almost
	-- certainly a number written in a different unit (game months, say)
	-- rather than a longer real window; the check at load is what catches
	-- that before a player notices the event they expected never came back.
	-- Safe range: 300-1200.
	MaxCooldownSeconds = 960,

	-- Per-chapter cap on delivered events, taken from lifesim_design.md:
	-- "1–3 events per age chapter. More than that and no single one
	-- registers." The picker refuses to deliver past this in a chapter;
	-- see EventService.PickStageable. Shift events bypass it, because a
	-- mid-shift refusal leaves the player with nothing happening, which
	-- is the worse failure.
	-- Safe range: 2-5. Below 2 and a chapter feels empty; above 5 and no
	-- single one registers, per the design.
	MaxPerChapter = 3,
}

-- How many ambient events a player can have this chapter, gated behind the
-- actions they actually do. The world only brings events to a player who has
-- earned them -- by working a shift, sitting a lesson, or paying a visit -- so
-- the life feels responsive rather than pelted. Reset to 0 at every chapter
-- break alongside pendingEventCountInChapter.
--
-- MaxPerChapter here is deliberately the same number as Config.Events.MaxPerChapter:
-- the autonomy cap and the event cap are the same ceiling, because an event
-- that fires without a point to spend costs the player nothing and the whole
-- point of the gate is that it costs something.
Config.Autonomy = {
	-- Upper bound on autonomy points the player can hold at any one time.
	-- Same as Events.MaxPerChapter because each point buys one ambient event,
	-- and the event cap says there are at most this many ambient events per
	-- chapter anyway.
	MaxPerChapter = 3,
}

-- Answering an event by doing the thing it describes.
--
-- The other two resolutions both end at a list. A panel event is a list you read; an
-- enacted one is a list you walk to first. This one has no list anywhere. The event's
-- answers are objects laid out in the room -- a rug, a puddle, a cookie -- and the
-- answer is given by crawling to one, shoving one, picking one up and carrying it
-- somewhere, or by holding still and letting the moment pass.
--
-- Childhood is what this was built for and childhood is the whole argument for it. A
-- toddler cannot read. Every one of the first five years was, until now, a paragraph
-- and three sentences to click, which is the one interface a two-year-old is least
-- equipped to use and the first thing a new player is ever handed.
--
-- Everything below is either a tolerance or a tuning on how forgiving the verbs are.
-- None of it decides what any event means; that is authored on the choice, in its
-- act. See Types.ChoiceAct.
Config.Props = {
	-- How long the props stand before the event gives up and becomes a panel. The
	-- same anti-softlock as Enact.SecondsToChoose and set higher for the obvious
	-- reason: clicking three dots is one walk, and carrying a cookie across a room to
	-- somebody is several. A player who cannot work out what to do still gets to
	-- answer.
	-- Safe range: 45-240. 0 disables the fallback, which is only safe in testing.
	SecondsToChoose = 110,

	-- How often the server asks whether anything has been done yet. Faster than the
	-- enactment tick and deliberately so: that one watches for a slow failure, and
	-- this one is the input. At 0.25 a child who crawls over a prop's edge and out the
	-- far side can cross its whole reach between two checks and answer nothing, which
	-- reads exactly like the prop being broken.
	-- Safe range: 0.05-0.2. Below 0.05 is spending a frame budget on a distance check.
	TickSeconds = 0.1,

	-- How far a prop is put from the player when its act does not say. Far enough that
	-- reaching one is a decision rather than a step. Safe range: 6-20.
	DefaultDistance = 12,

	-- Total angle the set is laid out across, and how many base bearings are tried
	-- within it before giving up. The set picks one direction with room in it and
	-- every prop's offsetDegrees is measured from there, so an authored arrangement
	-- keeps its shape wherever in the house it lands -- the rug stays between the
	-- child and the toy whichever way the child happens to be facing.
	-- Safe range: 180-360 and 8-24.
	ArcDegrees = 360,
	Bearings = 16,

	-- How far round from its authored bearing a single prop may slide when its own
	-- spot is inside a wall, and in how many steps. The set's shape bends before the
	-- set is abandoned, because a rug two feet to the left of where it was written is
	-- still the event, and a panel is not. Safe range: 20-70 and 2-6.
	NudgeDegrees = 40,
	NudgeSteps = 4,

	-- How close a prop may be staged to another in the same set, measured centre to
	-- centre. Below this the player reaching one is inside the reach of both, and the
	-- event answers itself with whichever the loop happened to check first.
	-- Safe range: 4-12.
	MinSeparationStuds = 6,

	-- Stay: how long the player has to hold still, and what counts as still. The
	-- seconds are the mechanic -- a child waiting to be picked up is doing something,
	-- and it should feel like a decision to keep doing it rather than like a pause.
	-- The speed is a tolerance for a thumbstick drifting, not permission to walk.
	-- Safe range: 1.5-5 and 0.5-3.
	StayStillSeconds = 2.6,
	StillSpeedStuds = 1.5,

	-- Push: how far the prop has to travel from where it started before that counts as
	-- having moved it, and how much of the player's shove it yields to. Below about
	-- 1.5 studs a player who walks past it has answered by accident. The share being
	-- under 1 is what makes it feel like weight rather than like a thing stuck to your
	-- chest. Safe range: 1.5-6 and 0.3-0.9.
	PushStuds = 3,
	PushShare = 0.55,

	-- Carry: how far in front of the player the carried thing rides, and how high up it
	-- as a fraction of their own height. A toddler carries something in both arms in
	-- front of them, which is also the only place the player can still see it.
	--
	-- There is deliberately no smoothing number here. The carried thing is welded to
	-- the character rather than moved from the server tick, so it is already exactly as
	-- smooth as the player is, and a catch-up rate would only be able to make it worse.
	-- Safe range: 1.2-3 and 0.5-2.5.
	CarryAheadStuds = 1.8,
	CarryHeightFraction = 0.62,

	-- How long the set is out and readable before any of it will take an answer. Not a
	-- polish number: without it a Stay is answered by the player doing what every
	-- player does for the first few seconds of a new prompt, which is stand still and
	-- read it. The banner has to be readable before standing still can mean anything,
	-- or the one answer that requires no action is the one nobody chooses on purpose.
	--
	-- It covers every verb rather than only Stay, because a prop that lands within
	-- reach of where the player is already standing would otherwise answer the event on
	-- the frame it appeared. The labels wake and dim normally throughout -- the set is
	-- alive to look at, just not yet to answer.
	-- Safe range: 1.5-4. Below about 1.5 a slow reader answers by accident; above 4 the
	-- player has already walked to something and is waiting on the game.
	GraceSeconds = 2.5,

	-- How long the set stays in the room after it has been answered. Short, and not
	-- zero: a rug that vanishes on the frame it finally gives way takes the answer
	-- with it, and the player is left reading an outcome about a thing they never saw
	-- happen. Long enough to watch it finish moving.
	-- Safe range: 0.8-3. Above about 3 the next event is already being staged.
	LingerSeconds = 1.6,

	-- The label over a prop: how much further away it can be read than the prop can be
	-- reached, and how much bigger it gets when you are close enough to use it. Both
	-- mirror Interact's dots, and mirror them on purpose -- a player should learn one
	-- rule about when a thing in this world is ready for them, not two.
	-- Safe range: 1.5-4 and 1.05-1.4.
	LabelDistanceMultiplier = 2.5,
	LabelNearScale = 1.18,

	-- Content limit, enforced at server start. A label past this wraps over the prop it
	-- is meant to be naming. Shorter than Enact.MaxLabelLength because this one is read
	-- in the world at distance rather than on a panel a foot from your eyes.
	-- Safe range: 16-40.
	MaxLabelLength = 32,
}

-- The thing the event is about, standing in the room. An event that names a
-- subject spawns it when the prompt opens, walks it in, and takes it away again
-- when the prompt is done with.
--
-- This is the half of an event that was previously only a sentence. "There is a
-- dog. It is at least as tall as you are, and it has noticed you" was, until now,
-- a description of an animal that was not there. It is also what enactment needs:
-- three dots have to hang over something, and the subject is that something.
--
-- Best-effort throughout, on the same terms as enactment: a room with nowhere to
-- put the animal simply doesn't get one. A subject may never be the reason an
-- event cannot be answered, so every failure below is silent and ordinary.
Config.Scene = {
	-- How close the subject settles to the player, measured to its *near edge* --
	-- the scene adds the subject's own half-length, so one number here is right for a
	-- cat and a dog alike.
	--
	-- Derived rather than typed, because it is a constraint and not a taste call: it
	-- must come to rest outside arm's reach, or the event answers itself from where the
	-- player is already standing. That is the failure this number exists to prevent --
	-- the dog trots in, stops inside Interact.ReachStuds, and its dots are clickable
	-- before the player has taken a step. The walk to the animal is the mechanic, and a
	-- walk of zero studs is a panel with extra steps.
	--
	-- The four studs on top are what makes the walk read as one. Below about two the
	-- animal is close enough that a player who was already drifting forward arrives
	-- without meaning to. Safe range: ReachStuds + 3 to ReachStuds + 8; larger fails to
	-- place indoors more often, because the room has to hold it.
	ApproachStuds = Config.Interact.ReachStuds + 4,

	-- How far beyond its resting place the subject appears, i.e. the length of the
	-- walk in. This is the whole performance: something that materializes at its
	-- final position has not arrived, it has popped. Safe range: 4-16. Larger
	-- needs a bigger room and fails to place more often.
	WalkInStuds = 8,

	-- Retried once at this fraction of the walk-in when the full length won't fit,
	-- for the reason Enact.SpreadSteps exists: a house is not a field. Below
	-- ~0.3 the walk is over before it reads. Safe range: 0.3-0.9.
	RetryWalkInScale = 0.5,

	-- Total angle in front of the player that resting places are searched across,
	-- and how many bearings are tried within it. Centered on the way the player is
	-- facing, so the subject arrives where they are already looking.
	-- Safe range: 60-200 and 3-15. More bearings costs three probes each.
	ArcDegrees = 120,
	Bearings = 7,

	-- How much of the remaining turn the subject closes each frame while it faces
	-- the player, 0-1. Low is a slow head-turn, 1 snaps. Same reasoning as
	-- NPC.LookResponsiveness -- an animal that tracks you perfectly is a turret.
	-- Safe range: 0.05-0.4.
	TurnResponsiveness = 0.12,

	-- How long the subject holds its reaction to the answer before it leaves. It
	-- runs under the outcome the player is reading, so it wants to be close to
	-- UI.EventOutcomeSeconds -- an animal that vanishes on the click undoes the
	-- whole reason it walked in. Safe range: 0-8. At 0 it disappears mid-sentence.
	--
	-- Time spent walking is on top of this rather than inside it: an approach and
	-- the walk out are journeys the player watches, not part of the pause, so a
	-- subject that comes over stays a couple of seconds longer than one that does
	-- not. That is deliberate -- it is also the answer that earned it.
	LingerSeconds = 4,

	-- How close an approaching subject comes, edge to edge. The scene adds the
	-- player's own body radius and the animal's half-length, so one number here is
	-- right for a toddler meeting a dog and an adult meeting a cat alike.
	--
	-- Safe range: 0.5-4. Below half a stud the animal is standing inside the player,
	-- and past four it has not really come to them. Measured from wherever the player
	-- is when they answer, which is next to the animal rather than where the prompt
	-- opened -- so this is a small step on top of an already short distance.
	ReactionCloseStuds = 1.5,

	-- How often a scene checks that it is still wanted. Only bounds how quickly a
	-- subject clears after the prompt it belongs to has gone, so it can be coarse.
	-- Safe range: 0.1-1.
	TickSeconds = 0.25,
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
		PhoneRing = "rbxassetid://123456789",
		LetterArrive = "rbxassetid://123456789",
		DoorKnock = "rbxassetid://123456789",
	},

	-- Animation ids for visitors. Empty means the rig falls back to standing
	-- still, which looks wrong on purpose -- a visibly unfinished NPC is better
	-- than one that silently never animates and is assumed to be working.
	-- Greet and Talk are one-shot; Idle and Walk are looped and cross-faded.
	Animations = {
		NPCIdle = "rbxassetid://123456789",
		NPCWalk = "rbxassetid://123456789",
		NPCGreet = "rbxassetid://123456789",
		NPCTalk = "rbxassetid://123456789",
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

	-- What has to fit for a visitor to stand somewhere. Nominal rather than measured,
	-- because anything looking for a place to put one has to ask before the avatar
	-- exists -- building it is a web-backed call, and spawning a person in order to
	-- discover there was nowhere for them to go is the wrong order to do it in.
	--
	-- Deliberately a little larger than any cast member actually is, so the error is
	-- a spot rejected rather than a parent standing in a wall. Radius, so it is the
	-- same measurement Ground.BodyRadius returns for a player.
	-- Safe range: 1-2 and 5-7.
	BodyRadius = 1.4,
	BodyHeight = 5.8,

	-- One leg of a computed path. Bounds a *waypoint*, not a journey, so it is much
	-- shorter than WalkTimeoutSeconds above: waypoints are a few studs apart and one that
	-- has not been reached in this long means the walk is wedged rather than slow. Timing
	-- out abandons the whole path, which is the self-healing case -- the walker pauses and
	-- picks somewhere else instead of grinding against whatever stopped them.
	-- Safe range: 1.5-8.
	WaypointTimeoutSeconds = 3,

	-- Turning on the spot to look at somebody who has walked up.
	--
	-- Separate from the head tracking above and doing a different job: the neck says "I
	-- have noticed you", the body says "I have stopped what I was doing". A person who
	-- only ever did the first, with their back to you through a whole conversation, is the
	-- single most mannequin thing a rig can do.
	--
	-- TurnResponsiveness is how much of the remaining angle is closed each tick, 0-1.
	-- Safe ranges: 0.03-0.2, 0.05-0.5, 1-15.
	TurnTickSeconds = 0.05,
	TurnResponsiveness = 0.16,
	-- Within this many degrees of facing them, stop stepping. Not zero, because easing
	-- toward an angle never quite arrives and a rig that never stops nudging is a rig that
	-- jitters forever.
	TurnDoneDegrees = 2,
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

-- Money. Arrives with the world because this is the first build in which there is
-- both something to earn it from and something to spend it on.
--
-- The scale every authored price is measured against, written down here because
-- content carries the prices and nothing else records what they are supposed to
-- mean: an adult hour of ordinary work is worth about twenty of these. So a small
-- child's pocket money is single digits, a teenager's weekend is tens, a month of
-- adult wages is low thousands, and anything above five figures is a life event
-- rather than a purchase. Realistic numbers on purpose -- a player who recognizes
-- what a week's wages feels like is a player who can feel a price.
Config.Money = {
	-- What a life begins with. Zero because you are born owning nothing, and because
	-- every unit in the game should be traceable to something that happened in it.
	--
	-- Read through MoneyService.StartingBalance rather than used directly anywhere,
	-- and that indirection is the whole point: it is the one seam inherited money
	-- has to slot into. A life born into a family with something behind it changes
	-- what that function returns, and nothing downstream of it needs to know.
	-- Safe range: 0-1000. Past that an ordinary first life starts solvent, which
	-- takes the meaning out of the first thing the player earns.
	StartingBalance = 0,

	-- Ceiling on a balance. Not a game rule -- no authored content comes within
	-- several orders of magnitude of it -- but a guard, so that a payout loop
	-- introduced by a future bug produces a visibly pinned balance rather than a
	-- number too large to draw, or one large enough that integer arithmetic quietly
	-- stops being exact. Comfortably below 2^53, where that would start.
	-- Safe range: 1e6-1e12.
	MaxBalance = 1e9,
}

-- Money you are given for being a child. The first income in a life, and the only
-- one that arrives without being earned.
--
-- Quoted weekly and paid yearly, which is not a compromise but the honest shape of
-- the thing. "You get five a week" is what an allowance is called by everyone who
-- has ever had one, and a birthday is the only clock the game currently has to pay
-- it out on -- so the rate is weekly, the grant is a year of it, and the player is
-- told both.
--
-- Scaled with age on purpose. A seventeen-year-old on a five-year-old's allowance
-- is a joke about being treated like a child, and a number that climbs every
-- birthday is the cheapest way there is to make a birthday feel like a promotion.
Config.PocketMoney = {
	-- The first birthday that pays. Below this a child has nothing to spend it on
	-- and no sense that it is theirs. The same age as ManualAgeUpMinAge, so the year
	-- the player takes the wheel is the year they are handed something to steer
	-- with -- but written out rather than derived from it, because the two would
	-- move for entirely different reasons.
	-- Safe range: 3-8.
	StartAge = 5,

	-- The last birthday that pays. After this you are expected to earn it and wages
	-- take over. Safe range: 15-18.
	EndAge = 17,

	-- Dollars per week, per year of age: at 1 a ten-year-old gets ten a week. The
	-- scale to judge it against is the note above Config.Money -- an adult hour of
	-- ordinary work is worth about twenty -- which puts a whole childhood at this
	-- rate somewhere around seven thousand: real money to a child, a rounding error
	-- to an adult, which is the shape it should have.
	-- Safe range: 0.5-3. Above about 3 a teenager doing nothing out-earns a first
	-- job, and the first wage packet stops meaning anything.
	WeeklyPerYearOfAge = 1,

	-- What being close to the parent bringing it is worth, as a share added on top.
	--
	-- Which parent turns up alternates by age, and this reads that same parent's bond --
	-- so a childhood spent going and seeing your mother pays better on even years, and
	-- the player works that out from the number rather than from being told. It is the
	-- first place a bond turns into anything, years before a job reference could.
	--
	-- Only ever adds. A parent who barely speaks to you still hands over the full
	-- allowance, because docking a child's pocket money for not visiting would be a
	-- punishment stacked on the loss itself -- and "failure worth playing" means a
	-- neglected childhood is poorer than it could have been, not one that cannot afford
	-- to be a childhood.
	--
	-- At 0.5, a bond at the ceiling is worth half as much again -- roughly a thousand
	-- across a childhood, which buys something and does not rewrite the economy.
	-- Safe range: 0-1. Above 1 the allowance is mostly the relationship.
	BondBonusShare = 0.5,

	-- How the money actually reaches the player: a parent appears somewhere in the
	-- room, walks over and hands it to them.
	--
	-- Not a cutscene, and that is a rule rather than a shortcut. Nothing in this game
	-- takes the room away from the player -- an enacted prompt is a banner precisely
	-- so it cannot -- and a birthday happens thirteen times in a childhood, which
	-- makes it the very worst place to start seizing the camera. They come to you,
	-- you keep control, and the scene reads as a scene because a person crossed a
	-- room to find you.

	-- How far off a parent appears, and the drawn-in second attempt for a room that
	-- cannot hold the first. Far enough that the walk is visible and reads as someone
	-- arriving, close enough to fit in a real room of this house.
	--
	-- Two attempts rather than a search, which is what EnactService and SceneService
	-- both do and for the same reason: the difference between the two is the
	-- difference between a room and a corner, and every value in between buys a scene
	-- that is slightly worse for nobody's benefit. The retry was measured rather than
	-- guessed -- at the full distance alone a parent can be staged in 54% of this
	-- house, and with the retry in 83%, nearly all of the difference upstairs where no
	-- bedroom is fourteen studs across.
	--
	-- Safe range: 8-20 and 0.4-0.8. Above about 20 nothing indoors can hold the first
	-- attempt. Below about 0.4 the second one arrives already at arm's length, which
	-- is a parent appearing beside you rather than coming to find you -- worse than
	-- the fallback, which at least does not pretend to be a scene.
	SpawnStuds = 14,
	RetrySpawnScale = 0.5,

	-- The arc around the player's facing they may appear in, and how many bearings
	-- are tried inside it. Much wider than a subject's, because a parent is a person
	-- who lives here and may perfectly well come from behind you -- unlike a dog,
	-- which has to be seen arriving or it has teleported.
	-- Safe range: 120-360 and 5-16.
	ArcDegrees = 300,
	Bearings = 9,

	-- How close they get before handing it over. Measured between middles, so this
	-- is roughly arm's length once both bodies are accounted for.
	-- Safe range: 2-6. Below about 2 they walk into the player trying to reach it.
	HandoverStuds = 4,

	-- How long they stay after handing it over, before turning to leave. The money
	-- is floating over their hands during this, so it is really "how long the number
	-- is readable with the person who gave it to you still standing there".
	-- Safe range: 1-6.
	LingerSeconds = 3,

	-- How often the chase re-aims at the player and checks whether it has arrived.
	-- Safe range: 0.1-0.5. Above ~0.5 a walking player visibly out-runs the aim.
	TickSeconds = 0.25,

	-- How often the server looks for anyone still owed money and tries again. Only
	-- ever runs for a player whose ledger is not empty, which is rare.
	-- Safe range: 10-120.
	RetrySeconds = 25,

	-- Failed handovers before the money is simply credited where the player stands.
	--
	-- This is the panel-fallback of this feature and it has to exist: a player whose
	-- corner cannot hold a parent must still be paid, because an allowance that never
	-- arrives is indistinguishable from a broken game. Not the good version, and
	-- never a silent failure.
	-- Safe range: 1-6. At 1 there is no second chance at the good version.
	MaxAttempts = 3,
}

-- Work. The first money in a life that is neither given nor found, and the reason
-- the workplace was built at the far end of the street rather than bolted to the
-- house: a wage should cost a walk.
--
-- The numbers here are shape, not price. What a job pays is authored per job in
-- content/Jobs.luau as a yearly salary, and every rate the game actually uses is
-- divided back out of that -- so a wage can be retuned in one place, by a person
-- reading a figure they can judge, without a second number left disagreeing.
Config.Work = {
	-- A shift, in game hours. At RealSecondsPerGameHour (30) this is the four
	-- real minutes a shift was designed around: long enough to be a stretch of
	-- time you decided to spend, short enough to sit inside one sitting.
	-- Safe range: 4-12. Below ~4 a shift is a button press; above ~12 it outlasts
	-- the patience of anyone not already being paid.
	ShiftGameHours = 8,

	-- Shifts in a working year. Working all of them earns exactly the job's
	-- authored yearly salary, which is the entire reason this number exists: it
	-- is the divisor that turns a salary a person can judge into an hourly rate
	-- the game can pay out.
	--
	-- Also the year's ceiling. Not a punishment but the thing that keeps a salary
	-- meaningful -- without it, "8,000 a year" describes nothing, because the
	-- answer to "how much can I earn?" would be "how long can you stand there?".
	-- Safe range: 3-10. Higher makes a year of work a grind; lower makes each
	-- individual shift carry so much of the salary that missing one hurts.
	ShiftsPerYear = 5,

	-- How near a job's place point you must be to clock on. Small, because
	-- clocking in should be a thing you did rather than a thing that happened to
	-- you while walking past.
	-- Safe range: 4-10.
	ClockInRadiusStuds = 6,

	-- How far you may roam from that point while still counted as working.
	-- Deliberately room-sized rather than a dot: standing to attention for four
	-- minutes is not a job, and the shop floor was built to be walked around.
	-- Leaving this radius clocks you out.
	-- Safe range: 12-40. Below ~12 the shop floor itself would clock you out;
	-- above ~40 you could leave the building and still be drawing a wage.
	StationRadiusStuds = 24,

	-- How often the shift clock is read. Wages are credited per completed game
	-- hour regardless, so this only sets how promptly leaving your station is
	-- noticed and how smoothly the HUD moves.
	-- Safe range: 0.1-1.
	TickSeconds = 0.25,

	-- The window, in game hours into a shift, within which the shift's one moment
	-- can fire. Not at the start, because a thing that happens the instant you
	-- clock on reads as a cutscene attached to the button; not at the very end,
	-- because an event still open when the shift runs out is a question you
	-- answer after the fact.
	-- Safe range: 1 to ShiftGameHours - 1, low below high.
	EventEarliestGameHour = 2,
	EventLatestGameHour = 6,
	-- Allow work-from-home jobs whose placeId points to a suburb house.
	-- When false, home-based jobs are silently excluded from the job posts.
	HomeJobAllowed = true,
}

-- The corner shop. A place with aisles and a counter, and a job that asks you
-- to walk them in order rather than stand at one spot and click.
--
-- The swap contract: the generator stamps these tags on the parts that exist in
-- the floor plan, and the service reads by tag rather than by name. A rebuild
-- that swaps CounterBase for a different mesh keeps working because the tag is
-- what the service looks for, not the part's name.
Config.Shop = {
	-- The tagged parts the service uses to resolve fetch-and-bag geometry.
	-- Each is a CollectionService tag; the attribute on the part says which zone
	-- it is, so one tag covers every instance across every shop in the game.
	CounterTag = "AgesShopCounter",
	ShelfTag = "AgesShopShelf",
	CrateTag = "AgesShopCrate",
	ChillerTag = "AgesShopChiller",
	QueueTag = "AgesShopQueue",

	-- The attribute name read off every tagged part to learn which zone it is.
	-- Values are "counter", "shelf_food", "shelf_chilled", "crate", "queue".
	ShopZoneAttribute = "ShopZone",

	-- Fetch-and-bag tuning. The corner shop's signature rhythm.
	FetchBag = {
		-- How many items a customer orders, per task. Randomised between these
		-- bounds so a shift is not a metronome of identical lengths.
		MinItems = 2,
		MaxItems = 4,
		-- How many items the player can carry in their basket at once. Starts at
		-- one and grows with standing, but the config sets the baseline.
		BaseBasketSize = 1,
		-- How long the customer's patience bar runs, in real seconds. A full order
		-- should be doable in well under this; the bar is a pressure dial, not a
		-- soft lock.
		PatienceSeconds = 45,
		-- How much of the base tip survives when patience is half spent. At 0.5
		-- a patient customer tips normally and an impatient one still leaves
		-- something on the counter rather than nothing at all.
		TipFloorAtHalfPatience = 0.5,
		-- What the customer might ask for. Each entry is a grocery name that the
		-- order resolver picks from at random. Kept short so every name reads as
		-- something a person would actually say at a till.
		Items = {
			"bread",
			"milk",
			"eggs",
			"butter",
			"cheese",
			"apples",
			"bananas",
			"cereal",
			"coffee",
			"tea",
			"sugar",
			"flour",
			"rice",
			"pasta",
			"soup",
			"sandwich",
			"chips",
			"yogurt",
			"carrots",
			"oranges",
		},
	},
}

-- Being hired, as opposed to working. Two different things that used to be one:
-- standing near the counter used to hire you and clock you on in the same silent
-- motion, so the moment a life gains its first job passed without being a moment at
-- all. Now the workplace advertises, and taking the job is something you walk onto.
Config.Work.Hiring = {
	-- How close to the hire pad counts as stepping on it. Smaller than
	-- ClockInRadiusStuds on purpose, and that gap is the whole design: you can be
	-- near enough to work at a counter you already work at without being near enough
	-- to accidentally take a job you never chose.
	-- Safe range: 2-5, and must stay below ClockInRadiusStuds or being hired and
	-- clocking on collapse back into one event.
	PadRadiusStuds = 3,

	-- How high the hiring sign floats above the job's place point. Head height and
	-- then some, so it reads as a sign over a counter rather than as something lying
	-- on it.
	-- Safe range: 3-8.
	SignLiftStuds = 5,

	-- How far away the sign is still drawn. Larger than a choice label's range,
	-- because this one has a different job: a choice label is read once you have
	-- arrived, and this is read to decide whether to walk over at all.
	--
	-- This was 160, chosen to be "legible from the far end of the street", and the
	-- street turned out to be the wrong unit. Measured against the town: the median
	-- place point has **31 other place points within 160 studs, and the worst has
	-- 49** -- every job in the game. Signs are AlwaysOnTop, so all of them draw
	-- through the buildings between, and standing anywhere in town meant reading
	-- thirty overlapping NOW HIRING cards stacked through the walls. A sign that is
	-- always on screen is wallpaper, and wallpaper is not signposting.
	--
	-- 45 is 2.5x the 18-stud median gap between neighbouring place points, so it
	-- reaches the shop you are outside and its immediate neighbours -- a median of 3
	-- at once, worst case 6 -- and stops there. Re-measure with the block in
	-- tools/check_town.py if the generator's frontage spacing changes; this number is
	-- a multiple of that spacing, not a distance somebody liked the look of.
	-- Safe range: 40-70. Below ~40 you have to already be inside to learn the shop
	-- is hiring, which is the problem this exists to fix; above ~70 the stacking
	-- starts again.
	SignMaxDistanceStuds = 45,

	-- How many years before a job's minAge its sign starts appearing.
	--
	-- The signs used to be pushed to every living player at every age, which is how
	-- a one-year-old ended up surrounded by job adverts. But hiding them until the
	-- birthday you qualify is the opposite mistake, and the reason is already written
	-- into postsFor: "a job that is invisible until the year you qualify is a job
	-- nobody plans for."
	--
	-- 4 is that comment's own example made into a number -- a twelve-year-old walking
	-- past the shop and learning it hires at sixteen. So the signposting survives
	-- intact and only stops reaching the ages that could not act on it under any
	-- circumstances.
	-- Safe range: 2-6. At 0 the sign is news you can do nothing with; above ~6 a
	-- child is being advertised at again.
	SignLeadYears = 4,
}

-- House ownership. Suburb homes a player can buy and use as a workplace.
--
-- All data is per-life, resetting on death just like money and bonds. A life
-- that dies with a house leaves no inheritance -- the property vanishes with
-- the slot, and the new life starts with nothing.
Config.House = {
	-- Price to buy one suburb house. Single-digit thousands, so a teen can
	-- afford it after a year of part-time work, but not so cheap that it's
	-- meaningless.
	BuyPrice = 5000,
	-- Maximum houses a single life can own at once. One is the intended
	-- experience -- a home base to return to -- but two or three won't break
	-- anything for players who want property investment.
	MaxPerPlayer = 1,
	-- Fraction of BuyPrice returned when selling. Seven-tenths encourages
	-- buying and selling as a cycle rather than hoarding; the 30% loss is
	-- the cost of ownership, like property tax in the real world.
	ResaleFraction = 0.7,
}

-- Apartment entrance doors. Every door is a tagged part in the generated world;
-- ApartmentDoorService attaches the open/close interaction and swings it on a
-- tween rather than teleporting the part, so walking up to a block reads as
-- entering a building and not clipping through a wall.
Config.ApartmentDoor = {
	-- How far the door swings open, in degrees, about its hinge edge. 90 is a
	-- push-open door standing fully clear of the frame; more than that and it
	-- would swing back past the wall it is hinged to.
	-- Safe range: 60-100.
	SwingDegrees = 90,
	-- How long the open/close tween takes, in seconds. Quick enough that
	-- walking through does not feel like waiting on the door, slow enough
	-- that the swing reads as a door and not a flicker.
	-- Safe range: 0.2-0.6.
	AnimationSeconds = 0.4,
}

-- The car dealership queue. Runs alongside the work shift at auto_dealer so the place
-- feels alive even when nobody is on the clock -- customers line up at the showroom and
-- the player can serve them whether they are working there or just walking past.
Config.CarDealer = {
	-- How many customers wait in line at once. More than three is a chore; two is a
	-- conversation.
	-- Safe range: 2-4.
	MaxQueue = 3,
	-- How long between one customer arriving and the next, in real seconds. Staggered
	-- so the queue builds visibly rather than appearing full all at once.
	-- Safe range: 8-20.
	CustomerGapSeconds = 12,
	-- How often the service ticks to check for new arrivals and advance the queue.
	-- Safe range: 1-3.
	TickSeconds = 2,
	-- What a walk-in tip is worth, as a share of what the counter's own job pays for
	-- the same stretch of time. A share rather than a price, because a price here was
	-- how the dealership came to out-earn employment at it.
	--
	-- The flat 100 this replaces was worth more per minute than the job: car_salesperson
	-- is 8,000 a year, which Work.YearGameHours divides to 200 a game hour, and a game
	-- hour is 30 real seconds -- 2.5 customers at CustomerGapSeconds. So the counter paid
	-- 100 x 2.5 = 250 a game hour to a passer-by and 200 to the person employed there,
	-- and unlike the job it had no yearly ceiling. Work.ShiftsPerYear exists precisely so
	-- that "how much can I earn?" is not answered with "how long can you stand there?",
	-- and this was answering it that way.
	--
	-- A quarter, because a walk-in is a tip and not a commission: real money for a real
	-- favour, never a reason to skip the shift. The arithmetic is done in CarDealerService
	-- off Jobs.HourlyRate, so a content author who retunes the salary retunes this with it
	-- and no second number is left disagreeing.
	-- Safe range: 0.1-0.5. Above ~0.5 standing at the counter starts to compete with
	-- holding the job; at 0 the queue is scenery and serving it is a chore with no point.
	WalkInTipShare = 0.25,
}

-- Look a life stage up by id and answer the age it starts at. Used to derive an
-- age gate from the stage that actually motivates it, rather than typing the same
-- number twice and letting the two drift. Errors rather than defaulting: a missing
-- stage means the table above was edited, and a gate that quietly falls back to
-- zero is the failure this is here to prevent.
local function stageMinAge(id: string): number
	for _, stage in Config.LifeStages do
		if stage.id == id then
			return stage.minAge
		end
	end
	error(`[AGES] Config: no life stage "{id}" to derive an age from`)
end

-- Drivable cars. What the dealership actually sells, on top of the counter job --
-- see content/Vehicles.luau for the cars themselves and world/VehicleChassis.luau
-- for the physics these numbers tune.
--
-- **The chassis is raycast suspension, not a physical wheel.** Four rays, one per
-- corner, each pushing a damped spring: `F = k*x - c*v`, applied through a
-- VectorForce rather than through a collider a curb can catch. A city built of
-- kerbs and pavements is exactly the geometry a HingeConstraint wheel gets stuck
-- on, and the whole reason this chassis was chosen over the older, simpler one is
-- that it does not touch the road at all -- it only ever measures the distance to
-- it.
--
-- **Ownership is Roblox's own, not a custom one.** The driver's client is handed
-- network ownership of the assembly the moment they sit down and it is handed back
-- to the server the moment they stand up. That is the entire multiplayer story: no
-- Server Authority migration, no clone-and-blend render, because a car -- unlike a
-- shared ball -- has exactly one owner at a time and Roblox already solves that
-- correctly once the seat-enter handoff is done explicitly. See VehicleService.
Config.Vehicles = {
	-- How many cars a single life may own at once. More than a couple is a garage
	-- nobody visits; the point is trading up, not collecting.
	-- Safe range: 1-4.
	MaxOwned = 2,
	-- Fraction of the buy price refunded on sale, the same shape and the same
	-- reasoning as Config.House.ResaleFraction: it makes buying and selling a
	-- cycle instead of a one-way ratchet, and the loss is the cost of having
	-- driven it.
	ResaleFraction = 0.6,

	-- Suspension spring stiffness, in the raycast chassis's own force units --
	-- not a real-world spring constant, just the k in F = kx - cv. Higher holds
	-- the body up stiffer and fights bottoming out on landings harder.
	-- Safe range: 12000-22000.
	SuspensionStiffness = 17000,
	-- Damping, c in the same equation. The tutorial rule of thumb this was tuned
	-- from -- "damping should run about a tenth of stiffness" -- is a starting
	-- point, not a law: too low and the body bounces after every bump, too high
	-- and the suspension stops absorbing anything at all.
	-- Safe range: 1200-2600.
	SuspensionDamping = 1800,
	-- How far the suspension can travel before the wheel is airborne, in studs.
	-- This is also how far a wheel hangs below the body at full droop, which is
	-- the number that decides whether a car clears a kerb or catches on it.
	-- Safe range: 1.2-2.2.
	SuspensionLength = 1.6,
	-- Wheel radius, in studs. Purely geometric -- where the raycast starts
	-- counting from -- and it is also what the wheel model is built at, so the
	-- two can never disagree about where the tyre actually is.
	-- Safe range: 1.2-1.8.
	WheelRadius = 1.4,

	-- How much of a car's rated `acceleration` actually reaches the road once it
	-- is already near top speed, 0-1. Straight-line acceleration at low speed
	-- for the first plate; a diminishing force as it approaches topSpeedStuds is
	-- what makes "flat out" mean something rather than the car just stopping
	-- dead at a wall.
	-- Safe range: 0.1-0.4.
	TopSpeedTaper = 0.25,
	-- Steering is scaled down as the car speeds up, from full `steerDegrees` at a
	-- stop to this share of it flat out -- the reason a car that turns sharply in
	-- a parking lot does not spin out doing the same turn at speed. 1 would mean
	-- no scaling at all.
	-- Safe range: 0.25-0.55.
	HighSpeedSteerShare = 0.4,
	-- Studs per second above which the steering scale in HighSpeedSteerShare is
	-- fully applied. Below this a car steers at its full rating regardless of
	-- speed -- parking-lot manoeuvring should feel like parking-lot manoeuvring.
	-- Safe range: 25-45.
	SteerTaperStuds = 34,

	-- How many bearings the parking search fans out across, and how wide, when
	-- looking for somewhere to stand a spawned car near the dealership. Same
	-- Ground.Bearings pattern every other placement in the game uses, sized for a
	-- forecourt rather than a room -- a car needs more clearance than a person.
	-- Safe range: 90-180 degrees, 5-9 bearings.
	ParkArcDegrees = 140,
	ParkBearings = 7,
	-- How far out from the dealership's place point the search starts, and how
	-- much further it tries once before giving up. A car is bigger than a body,
	-- so this starts further out than PocketMoneyService's parent-arrival search
	-- does for a person.
	-- Safe range: 14-26 studs.
	ParkStuds = 18,
	ParkRetryScale = 1.6,

	-- A car left both empty and unridden this long returns to the dealership on
	-- its own, so an afternoon of parked cars does not become litter across the
	-- city. Long enough that stepping into a shop for a shift does not lose the
	-- car parked outside it.
	-- Safe range: 300-1200 seconds.
	IdleDespawnSeconds = 600,
	-- How often the chassis re-derives its suspension forces and drive force.
	-- Every RenderStepped-equivalent tick, on the server: fast enough that the
	-- ride does not feel quantised, slow enough not to be the most expensive
	-- thing running.
	-- Safe range: 1/60-1/30.
	TickSeconds = 1 / 60,
}

-- Monthly living expenses. Money leaves every game month whether the player
-- wants it to or not, which is the one force that keeps a life from running
-- forward on autopilot and turning the pocket-money trickle into a flood.
Config.Bills = {
	-- The age a life starts paying its own way. Below it there are no bills at all
	-- -- not a bill of zero, no bill.
	--
	-- This was missing, and its absence was not a rounding error: a newborn was
	-- charged BaseMonthly on its first birthday, could not pay it, and was carrying
	-- the "in_debt" flag at age one. Every consequence hung off that -- the happiness
	-- drain, the loan-shark content door -- so the toddler years opened with a debt
	-- spiral nobody could have avoided and no mechanic could answer.
	--
	-- Derived from Adulthood rather than typed because "you pay your own way once
	-- you are an adult" is the actual rule; the number is a consequence of it. It is
	-- deliberately not the first job at sixteen: a sixteen-year-old with a shop job
	-- still lives at home, and the two years where you are earning and not yet
	-- paying rent are the years the game gives you to build a cushion.
	MinAge = stageMinAge("Adulthood"),
	-- The base cost of existing in the world each month, before anything else
	-- is factored in. Small enough that a first job can cover it, large enough
	-- that skipping work for a month leaves you behind.
	-- Safe range: 100-400.
	BaseMonthly = 200,
	-- Extra cost per suburb house owned. A home is not free to maintain, and
	-- this is the monthly slice of the 30% resale loss that the plan names
	-- "property tax." The house already cost BuyPrice to enter; this is the
	-- rent you pay for staying.
	-- Safe range: 100-500.
	HouseMonthly = 200,
	-- Money held above this threshold shifts you into a higher lifestyle tier,
	-- and the monthly bill scales with it. A life that accumulates ten thousand
	-- without paying more than a starter keeps drifting further ahead of the
	-- curve -- this keeps the curve from becoming invisible.
	-- Safe range: 5000-20000.
	LuxuryThreshold = 10000,
	-- Bill multiplier once the luxury threshold is passed. A life that has
	-- climbed past the entry-level band pays more, not because the game is
	-- punishing wealth but because a bigger life costs more to sustain.
	-- Safe range: 1.2-2.0.
	LuxuryMultiplier = 1.5,
	-- What accumulates when a bill cannot be paid in full. Debt grows on top
	-- of debt and the interest is what makes a life that runs behind for a
	-- year hard to climb out of without a meaningful change.
	-- Safe range: 0.03-0.10.
	DebtInterestRate = 0.05,
	-- Hard ceiling on how much debt a life can carry. Above this the life
	-- flags as financially distressed and happiness drains faster; the cap
	-- exists so the number never becomes abstract.
	-- Safe range: 2000-10000.
	MaxDebt = 5000,
}

-- A place to park money so it earns interest rather than sitting idle.
-- The inverse of bills: debt compounds against you, savings compound for you.
-- The gap between the two rates is what makes a life that saves feel the relief
-- of compound growth, and what makes a life that defaults feel the squeeze of
-- both sides of the same formula.
Config.Savings = {
	-- Maximum balance a life can hold. Above this extra deposits go to money,
	-- so the cap only applies to the savings account itself and never to the
	-- total a life carries. Small enough that most lives never hit it; large
	-- enough that a saver who stays on track has a real difference over time.
	-- Safe range: 5000-20000.
	MaxBalance = 10000,
	-- Monthly interest paid on the savings balance. Compounded: interest
	-- earned each month is added to the balance and earns interest itself the
	-- following month. The rate is deliberately lower than debt interest so the
	-- gap punishes default while rewarding caution, not so that saving beats
	-- working.
	-- Safe range: 0.005-0.02.
	InterestRate = 0.01,
}

--
-- A shift used to be a timer. You walked to a marker, stood on it, and a number went
-- up for four real minutes -- which is not a job, it is a loading screen you are paid
-- for. Everything in this block exists to fill that time with somewhere to be.
--
-- The loop is deliberately small and always the same: a mark appears somewhere in the
-- workplace with an instruction over it, you have a few seconds to get there, and
-- then another one appears. It is the same verb as every other choice in this game --
-- walk onto the lit thing -- which is the point. A shift should not need teaching.
--
-- The numbers below are all about *pace*. They are the difference between a shift
-- that feels like work and one that feels like being nagged, and they are the first
-- thing to reach for if playtesting says the shift is either frantic or dead.
Config.Work.Tasks = {
	-- How long after clocking on before the first task appears, and how long between
	-- one ending and the next arriving.
	--
	-- Short on purpose. Idle time inside an activity is the bug this whole block
	-- exists to fix, so the gap is only long enough to read what just happened --
	-- "done, +$12" needs a beat to land, and a task that arrived the same frame the
	-- last one ended would eat its own feedback.
	-- Safe range: 1.5-6. Above ~6 the shift starts to have holes in it again.
	GapSeconds = 3,

	-- How many tasks may be running at once, late in a shift.
	--
	-- This is the difference between a to-do list and a shift. With one task at a time
	-- the only question a shift ever asks is "how fast can you walk", and there is
	-- exactly one right answer to it at every moment -- which means there is no
	-- decision in the loop at all, only execution. With two, the shop is asking for two
	-- things at once and the player has to decide which one to lose or which order to
	-- take them in, and that decision is the skill the job is actually teaching.
	--
	-- Two and not three. Three marks lit on one shop floor is a scavenger hunt rather
	-- than a job, the HUD would need a scrolling list, and the moment a player cannot
	-- hold the whole problem in their head they stop planning and start reacting --
	-- which is the very thing the second slot exists to move them away from.
	-- Safe range: 1-2. At 1 the shift is a to-do list again, which is a legitimate
	-- setting if the double load ever proves too much for the age range.
	MaxConcurrent = 2,

	-- The game hour of the shift from which a second task may be live.
	--
	-- The shift escalates by changing its shape rather than by tightening its numbers:
	-- the clocks and the marks stay exactly as they were, and what changes is how much
	-- of the room is asking for you at once. So a shift opens as the tutorial version
	-- of itself -- one thing at a time, learn the floor -- and turns into the real one
	-- a third of the way in, without a single number moving.
	--
	-- Also the reason a first shift is never unfair. A player's first two hours at any
	-- new job are single-task, every time, including the day they are promoted into a
	-- building they have never worked in.
	-- Safe range: 2 to ShiftGameHours - 2. At 1 there is no ramp; above that the shift
	-- ends before the second slot has been open long enough to matter.
	SecondSlotFromHour = 3,

	-- How much longer the wait is when a task is already in hand.
	--
	-- The two slots must fill *staggered*, never together. Two tasks arriving on the
	-- same tick is one big task with two halves and the player just does them in the
	-- order they are listed; a second one landing while the first is half walked is a
	-- genuine interruption, and being interrupted is the thing being practiced.
	--
	-- At 2.5 against a 3s gap the second lands about seven seconds in, which is inside
	-- every clock in JobTasks and outside the walk to a single mark -- so it reliably
	-- arrives while the player is committed to something and reliably leaves them able
	-- to still make it.
	-- Safe range: 1.5-4. Below 1.5 the two arrive as a pair; above 4 the second slot
	-- stops being used often enough to be worth having.
	SecondTaskGapMultiplier = 2.5,

	-- How long a missed task keeps its row on the HUD before it goes.
	--
	-- Its own number rather than GapSeconds, which used to do both jobs. With one slot
	-- they were genuinely the same wait -- the miss sat there and the shift was idle
	-- until the next task, so one clock described both. With two they are different
	-- questions asked of different things: how long a miss stays readable is about the
	-- player's attention, and how soon the next task arrives is about the shop's
	-- workload. Sharing a field meant a missed task blocked the slot it was no longer
	-- using, which with two slots is a quarter of the shift spent a task short for no
	-- reason the player could see.
	-- Safe range: 2-5. Under ~2 the row is gone before it has been read.
	MissLingerSeconds = 3,

	-- How far from the station a task mark can be painted, as a share of the distance
	-- a player is allowed to wander before they count as having walked out.
	--
	-- Well inside it, and that gap is load-bearing: a task that sent you past
	-- StationRadiusStuds would end your own shift for abandoning it, which is the
	-- funniest possible bug and would be very hard to diagnose from the symptom.
	-- Safe range: 0.25-0.7.
	SpreadShareOfStation = 0.45,

	-- The closest a task mark may be painted. Below this it lands under the feet of
	-- somebody already standing at the counter, and a task you complete by not moving
	-- is a task that taught the player the marks can be ignored.
	-- Safe range: 4-12, and must stay below SpreadShareOfStation * StationRadiusStuds.
	MinSpreadStuds = 7,

	-- Arcs tried when looking for somewhere to paint a mark, in degrees around the
	-- station, and how many bearings inside that arc. A full circle because a
	-- workplace is a room you are in the middle of rather than a thing you face.
	-- Safe range: arc 180-360, count 6-16. More bearings is a better chance of
	-- finding a spot in a cluttered room and slightly more raycasting per task.
	SearchArcDegrees = 360,
	SearchBearings = 12,

	-- Fractions of the spread tried along each bearing, near to far. Gives a cramped
	-- stockroom somewhere to put a mark when the full spread is inside a wall.
	SearchSteps = { 1, 0.75, 0.5 },

	-- How close to the mark counts as reaching it. Matches the hire pad rather than
	-- the clock-in radius: this is a thing you step onto, not a place you stand near.
	-- Safe range: 2-5.
	ReachStuds = 3,

	-- What finishing a task pays, as a share of an hour's wage at that job.
	--
	-- A share rather than a number, so the tip climbs with the ladder and with your
	-- record without a second table to keep in step: the office pays better per task
	-- for the same reason it pays better per hour. At 0.2 a good shift adds roughly a
	-- fifth again on top of the wage, which is worth chasing and is not a second
	-- income.
	-- Safe range: 0-0.5. At 0 tasks are worth only your record, which is a legitimate
	-- setting if tips ever start to distort the economy.
	TipShareOfHour = 0.2,

	-- The ceiling on what one shift's tips may add up to, as a share of a full
	-- shift's wage at that job.
	--
	-- Without a cap, tips are unbounded. A task closes the instant a foot touches its
	-- mark and the next arrives GapSeconds later, so a player who ping-pongs between
	-- marks clears forty-odd tasks in a four-minute shift rather than the eight or
	-- nine this block was written for. Tips then out-earn the wage by more than
	-- double, and because they never touch workGameHoursThisYear they slip straight
	-- past the year's cap -- which breaks the promise Jobs.luau makes in its own
	-- header that a job's pay is one authored salary.
	--
	-- At 0.25 the ceiling sits just above what TipShareOfHour always claimed tips
	-- were worth ("roughly a fifth again on top of the wage"), so this enforces the
	-- original intent rather than changing it. Tasks past the cap still count toward
	-- the shift's verdict and still pay standing -- they simply stop paying money, so
	-- the reason to keep working is the record rather than the tip.
	-- Safe range: 0.1-0.6. At 0, tips are off entirely.
	TipCapShareOfShift = 0.25,

	-- What an hour of the shift actually pays, as a multiple of the job's rate,
	-- decided by how the shift has gone by the time that hour lands.
	--
	-- This is the line between a job and an idle payout pad. The wage was credited
	-- off a wall clock that read no task field whatsoever, so standing inside the
	-- station radius for four minutes and touching nothing paid exactly what working
	-- the shift properly paid. When outcomes do not differentiate, the skill has been
	-- deleted -- there is no reason to do the tasks except the tips, and no reason to
	-- clock on at all except to wait.
	--
	-- Graded rather than pass/fail, on Work at a Pizza Place's star model: a bad
	-- shift should cost money, not the job. The bands reuse GoodShare and OkShare so
	-- there is one definition of a good shift in this file rather than two that can
	-- drift apart.
	--
	-- An hour that lands before the shift has issued its first task pays in full:
	-- nothing was asked, so nothing can have been missed. That grace is also what
	-- keeps the first hour of every shift honest, since the first task deliberately
	-- waits out a gap before it appears. It lapses the moment the shop tries to ask
	-- for something and comes up with nothing -- see UnansweredAsksBeforeBroken.
	-- Safe range: Good 1, Ok 0.6-0.9, Poor 0.2-0.5, None 0-0.2, and descending.
	WageShareGood = 1,
	WageShareOk = 0.8,
	WageSharePoor = 0.3,
	WageShareNone = 0,

	-- How many times the shop may ask for something, find nowhere to put it, and be
	-- given the benefit of the doubt before the shift is called off.
	--
	-- The grace above is written for a shift that has not started yet, and for a long
	-- time nothing distinguished that from a shift that can never start. A station
	-- whose room is too cramped to fan a mark out in issues no tasks, so it misses
	-- none, so it reads as a shift where nothing was asked -- which paid a full wage
	-- and climbed the ladder at base rate for standing perfectly still. At 40 game
	-- hours a year that is an entire salary for a player who never moved, and it is
	-- the single largest hole this block was written to close.
	--
	-- Only counted when the floor is completely clear, which is what makes the count
	-- trustworthy: a second-slot ask can fail honestly because the first task's marks
	-- are standing in the space the second one wanted, and a station that works
	-- perfectly well would otherwise condemn itself on its own busyness.
	--
	-- Three against a 3s gap calls it after about nine seconds, well inside the first
	-- game hour, so a broken station is caught before it can pay for one.
	-- Safe range: 2-6. At 1 a single unlucky search ends the shift; above ~6 the
	-- player stands there long enough to wonder whether they are doing it wrong.
	UnansweredAsksBeforeBroken = 3,

	-- What the shift's tasks do to your record.
	--
	-- Deliberately *not* per task. Standing bands sit at 6, 14 and 24 and a whole
	-- finished shift is worth PerShiftWorked = 1, so paying a point per task -- eight
	-- or nine a shift -- would flatten the entire ladder in one afternoon. Instead the
	-- tasks decide what the shift was worth: work it properly and the shift counts
	-- double, coast through it and it counts for nothing.
	--
	-- The share of the shift's tasks that has to be finished for each verdict.
	-- Safe range: Good 0.7-0.95, Ok 0.3-0.6, Good above Ok.
	GoodShare = 0.8,
	OkShare = 0.4,

	-- Added to PerShiftWorked when the shift came in at or above GoodShare. The whole
	-- reason to do the tasks rather than stand there: it is the difference between
	-- reaching the office in three shifts and reaching it in six.
	-- Safe range: 0-2.
	PerGoodShift = 1,

	-- What a shift below OkShare is worth, replacing PerShiftWorked entirely. Zero
	-- rather than negative: turning up and doing nothing should not climb the ladder,
	-- and it is not the same offense as walking out, which already costs -2.
	-- Safe range: -1 to 1.
	PoorShiftStanding = 0,

	-- XP toward the next standing band, shown as a thin bar under the shift
	-- progress. Distinct from standing itself: standing is the record the job
	-- keeps, XP is the visible progress the player watches climb. Reset each
	-- shift so the bar always shows how far into the current shift the next band
	-- is. Per-task and per-event values are small so a shift of four minutes
	-- yields a meaningful fill without making the bar a speed test.
	-- Safe range: 1-10 per task, 1-5 per event.
	StandingXp = {
		PerTask = 5,
		PerEvent = 3,
	},
}

-- The people a task is for.
--
-- A task with somebody waiting on it is a different thing to do than the same task
-- alone in a room, and none of that difference is in the rules -- the clock, the
-- marks and the tip are identical. It is entirely that a person is standing there
-- looking at you, which is the one thing this engine gives away for free: the head
-- tracking in Config.NPC costs no asset and no animation and does more for a shift
-- than any number here.
--
-- Everything in this block is about where they stand, and the whole block is
-- optional: a room too tight to fit a customer runs the task without one rather than
-- failing it.
Config.Work.Customers = {
	-- How far beyond the mark the customer stands, along the line out from the
	-- station. So the player steps onto the mark and the customer is across it facing
	-- them, which is what a counter looks like from either side.
	--
	-- Must be more than a body's width. Visitors are solid to the player -- they are
	-- real rigs, not props -- so too small a figure here is a shift spent shouldering
	-- somebody out of the way at every till.
	-- Safe range: 2.5-5.
	StandOffStuds = 3.2,

	-- How far out past their standing spot they walk in from. This is the whole
	-- arrival: they appear here and walk to the counter, so it wants to be far enough
	-- to be a walk and short enough to be over before the player has crossed the room.
	-- Safe range: 8-24. Above ~24 they are still coming when the clock runs out.
	ArriveFromStuds = 14,

	-- How long they stay after being served before turning to leave. The beat where
	-- they say something and you have already been paid.
	-- Safe range: 0-4. At 0 they turn on their heel mid-sentence.
	ServedBeatSeconds = 1.6,

	-- How high above the head the line they say floats, in studs, and how far away it
	-- can still be read. Name tags are off for these people -- a stranger in a shop
	-- does not wear one -- so this text is the only thing over them.
	-- Safe range: 2.5-5 and 20-80.
	SpeechHeightStuds = 3.4,
	SpeechRangeStuds = 45,

	-- A queue is several of them, one behind the other, and these three numbers are
	-- all it is.
	--
	-- The gap between one person and the next, measured back along the same line out
	-- from the station. Wide enough that four of them read as a queue rather than as a
	-- crowd, tight enough that the back of the line is still inside the room.
	-- Safe range: 2-4. Below ~2 they overlap; above ~4 the line stops looking like one.
	QueueSpacingStuds = 2.6,

	-- How long between one person arriving and the next. They turn up one at a time so
	-- the queue is seen forming rather than found already there, which is the
	-- difference between a rush starting and a rush having been placed.
	-- Safe range: 0.3-1.5. Above ~1.5 the back of the queue arrives after the clock.
	QueueArriveGapSeconds = 0.7,

	-- The most people a task may ever put in a line, whatever it asks for. A ceiling
	-- rather than a tuning knob: a queue of six is six round trips on one clock, which
	-- stops being pressure and becomes a chore.
	-- Safe range: 3-5.
	MaxQueue = 4,
}

-- What a job makes of you, and what that is worth.
--
-- The point of this whole block is that a wage should answer "how well do you do
-- this?" and not only "how long did you stand there?". Standing is earned per job
-- -- see LifeData.jobStanding -- and buys two things: a raise where you are, and
-- the right to be hired somewhere better.
Config.Work.Standing = {
	-- The floor. Deep enough that a run of bad shifts genuinely costs you the
	-- ladder, shallow enough to be climbable back out of inside a year.
	-- Safe range: -20 to -4.
	Min = -10,

	-- The ceiling. Reached by roughly two good years at one job, which is about the
	-- point where a job has nothing further to say about you and the answer is a
	-- different job.
	-- Safe range: 20-60.
	Max = 30,

	-- Working a shift all the way out, on its own, with nothing happening in it.
	-- Turning up is worth something and this is how much: enough that a player who
	-- simply does the job climbs, slowly, without ever seeing a moment.
	-- Safe range: 0-2. At 0, only events move your record.
	PerShiftWorked = 1,

	-- Leaving your station mid-shift. Costs more than a finished shift pays, so
	-- walking out is never a way to farm anything, and a habit of it shows.
	-- Safe range: -4 to 0.
	PerWalkOut = -2,

	-- Rock bottom. Let your standing sink all the way to the floor and the job lets
	-- you go: the sacking lands at clock-off, not mid-shift, so a bad shift finishes
	-- before it costs you the job. Anchored to Min so "on thin ice" is exactly the
	-- warning band -- the last stretch before the drop -- and moving Min moves the
	-- warning with it. Must satisfy Min <= FireAt < 0 (checked in WorkService).
	-- Safe range: same as Min.
	FireAt = -10,

	-- The last warning before the sack, and it is deliberately literal: from here a
	-- single worst answer (a -3 performance) reaches the floor, so "one more bad
	-- shift" is exactly what the line means. Crossing at or below it pushes the
	-- player the warning that one shift decides it. Must sit strictly between
	-- FireAt and 0 so the two warnings land in order (checked in WorkService).
	-- Safe range: FireAt + 1 .. -1.
	FinalWarnAt = -8,
}

-- What each stretch of standing is called and what it pays, best first.
--
-- Read top-down: the first band whose `atLeast` you meet is the one you are in.
-- Declared after the table above so the bottom band can be anchored to Min rather
-- than to a magic number that would silently stop covering the range if Min moved.
--
-- `raise` is a fraction of the job's base hourly rate, added on top and floored to
-- whole units. A fraction rather than a flat figure because the same raise has to
-- mean the same thing to a $60 shop hour and a $200 office one -- a flat $20 would
-- be a third of one and a tenth of the other.
--
-- Nothing below "well thought of" pays a bonus, and nothing pays a *penalty*. A bad
-- record costs you the ladder, which is punishment enough and far more legible than
-- a wage that quietly shrinks while you are trying to work out what you did wrong.
--
-- `name` is a lowercase phrase that has to read correctly in both places it is
-- used: on the HUD ("Well thought of · 3 of 5 shifts this year") and inside the
-- sentence explaining a job you cannot take yet ("You need to be well thought of as
-- a Shop assistant first"). A phrase that does not fit both is the wrong phrase.
Config.Work.Standing.Bands = {
	{ atLeast = 24, name = "the one they ask for", raise = 0.35 },
	{ atLeast = 14, name = "relied on", raise = 0.20 },
	{ atLeast = 6, name = "well thought of", raise = 0.10 },
	{ atLeast = 0, name = "finding your feet", raise = 0 },
	{ atLeast = Config.Work.Standing.Min, name = "on thin ice", raise = 0 },
}

-- Game hours of paid work available in a year. Derived rather than authored, so
-- the cap and the salary can never drift apart: this is the number a yearly
-- salary is divided by to get an hourly rate, and the number a year of work is
-- measured against. Change either constant above and both move together.
Config.Work.YearGameHours = Config.Work.ShiftGameHours * Config.Work.ShiftsPerYear

-- Health: being run down, and being ill.
--
-- Health is the one stat that can end a life, and until now it could only end it all
-- at once: a life at 1 health was a life at no health, and everything below the
-- ceiling was a warning you read rather than a system you played. This block is the
-- middle of that range. A life that lets itself fall below RiskHealth starts catching
-- things on birthdays, and being ill is a year that costs more than an ordinary one --
-- extra drain on top of the ordinary decay, and a working year that reads as a bad
-- one. Keeping health above the line is the point of every restful and healthy choice
-- in the game, and it is the first number below the ceiling that actually threatens
-- the life above it.
Config.Health = {
	-- The line health must stay above to keep a clean record. A life at or above this
	-- never falls ill on a birthday -- illness is the tax on being run down, not a
	-- lottery everyone is in -- and below it, every birthday carries a chance to catch
	-- something. Sickness is still possible above the line, but only as content, never
	-- as a birthday roll: the loop never invents it for a healthy life.
	-- Safe range: 30-60. Below ~30 illness is too rare to be the mechanism; above ~60
	-- a life has to be nearly ruined before the loop can ever touch it.
	RiskHealth = 40,

	-- The birthday chance of falling ill, at its floor and its ceiling. The chance
	-- rises in a straight line from BaseIllnessChance at RiskHealth to
	-- MaxIllnessChance at zero health, so every point of health below the line is a
	-- little more of the body failing to hold the line.
	-- Safe range: floor 0.03-0.15, ceiling 0.2-0.5, floor strictly below ceiling.
	BaseIllnessChance = 0.08,
	MaxIllnessChance = 0.35,

	-- What a year of being ill costs, on top of the ordinary yearly decay. The health
	-- figure is the threat and the happiness figure is the feel: an illness should dim
	-- a life even when it cannot end one. Kept near the ordinary decay so an ill year
	-- reads as "twice a normal year" rather than as a cliff.
	-- Safe range: health 3-10, happiness 2-8.
	SickHealthPerYear = 6,
	SickHappinessPerYear = 4,

	-- A shift worked while ill is a bad shift before it has even been one. Applied once
	-- at clock-off on top of the shift's own verdict, so a life that goes in sick pays
	-- for it in the only currency work understands. Small enough that a good record
	-- shrugs it off, and small enough that a thin one notices.
	-- Safe range: -4 to -1.
	SickShiftStanding = -2,

	-- What a birthday spent recovering puts back at once. Smaller than a sick year
	-- takes out, so recovering is a reprieve rather than a refill: an ill year drains
	-- roughly seven points and this restores four, which is the whole shape of the loop
	-- -- a life that falls ill pays a little each time until it either gets well or
	-- runs out of the middle of the bar.
	-- Safe range: 3-10. Near the sick health drain is where it stops being a tax.
	RecoverHealth = 4,
}

-- School: the first half of a life, which until now had nothing in it to do.
--
-- Everything between being born and turning sixteen was a stat readout and a text
-- prompt on a birthday. A player could not spend an afternoon being a child, because
-- there was no afternoon -- childhood was a loading bar in front of the job.
--
-- The loop is the shift's loop with the walking taken out of the middle. A shift asks
-- you to get somewhere before a clock; a lesson asks you to get the answer right before
-- one. The walk is spent once, at the door -- you went to the school -- and the twenty
-- seconds after that are thinking rather than travelling, which is the one place in
-- this game where that is the right trade.
--
-- What it is for, mechanically, is that `smarts` was a number nothing in the game read.
-- No job asked for it, no event moved it, and it decayed at zero a year. School is the
-- one thing that moves it and the office is the one thing that wants it -- so the
-- afternoons a nine-year-old spends here are the reason a sixteen-year-old can be
-- something other than a shop assistant. That is the whole point of the system: it
-- makes the first half of a life pay into the second.
--
-- Nothing here says what an answer looks like. It is a row on the one panel every
-- question in this game is asked on, so its limits are Config.Enact's and there is
-- deliberately no second set of numbers to keep in step.
Config.School = {
	-- The years school runs over. Six because that is when the existing childhood
	-- events start treating a life as old enough to be somewhere on its own, and
	-- seventeen because eighteen is Adulthood -- the last school year is the year
	-- before you are expected to be earning.
	--
	-- Deliberately overlapping Work.Hiring's first job at sixteen rather than handing
	-- over cleanly at it. The two years where you could be at school or at work and
	-- have time for neither are the most interesting years this game currently has.
	-- Safe range: 5-8 and 15-18, low below high.
	StartAge = 6,
	EndAge = 17,

	-- Lessons in a school year, and the year's ceiling. The same idea as
	-- Work.ShiftsPerYear and a smaller number on purpose: a year of school should be
	-- one good afternoon's decision rather than a thing to grind, because there are
	-- twelve of these years and only about four of the working ones before the money
	-- stops being the point.
	-- Safe range: 2-6. Above ~6 a full childhood is over an hour of lessons.
	LessonsPerYear = 3,

	-- Questions in a lesson. Long enough that one lucky guess does not decide it,
	-- short enough that a lesson is about ninety seconds -- roughly a third of a
	-- shift, which is the right relative weight for a thing you do three times a year
	-- rather than five.
	-- Safe range: 3-8.
	QuestionsPerLesson = 5,

	-- How long you have to pick an answer.
	--
	-- Generous by design. It is thinking time and nothing else now that the answers are
	-- a click rather than a walk, and it is deliberately not shortened to match: a clock
	-- this loose fails only the player who did not know the answer, which is exactly who
	-- school is
	-- supposed to be failing.
	-- Safe range: 10-40. Below ~10 a child at walkSpeed 8 is being tested on running.
	SecondsPerQuestion = 20,

	-- How long the answer's explanation holds before the next question. The one beat
	-- in this system that is not a mechanic, and it is the reason it is school rather
	-- than a quiz: getting it wrong tells you why, and the next lesson may ask again.
	-- Safe range: 2-6. Below ~2 the line cannot be read; above ~6 the lesson has
	-- holes in it, which is the bug Work.Tasks.GapSeconds exists to avoid.
	VerdictSeconds = 3.5,

	-- How often the server checks players against their answer pads. Matches
	-- Enact.TickSeconds because it is doing the identical job on identical pads.
	-- Safe range: 0.1-1.
	TickSeconds = 0.25,

	-- How near the school's place point you must be to go in, and how far you may
	-- wander before the lesson counts as walked out of. The same two radii as a shift
	-- and for the same reasons -- see Work.ClockInRadiusStuds and StationRadiusStuds.
	--
	-- The room is tighter than a workplace because a classroom you can leave and still
	-- be answering questions in is not a classroom. It is the only thing holding the
	-- player in the lesson, now that the answers travel with them rather than lying on
	-- the floor. Safe range: 4-10 and 12-30.
	AttendRadiusStuds = 6,
	RoomRadiusStuds = 20,

	-- Whether a lesson's answers are discs on the classroom floor that you answer by
	-- walking onto, rather than rows on a panel you click. The panel still opens -- it
	-- carries the question and the answer text, for reading -- but with discs down the
	-- rows are locked and the floor is the interface.
	--
	-- False, and deliberately: docs/interaction_grammar.md settled this months before
	-- this switch was written, in the user's own words -- "instead of places on the
	-- floor to walk on, make the mechanic more appealing like 3 dots over each
	-- characters head and then the options come up" -- and named lesson answers as one
	-- of the three examples in the same breath as person offers and event choices. A
	-- lesson answered by walking onto a disc is the one place that grammar regressed;
	-- this is what puts it back. Kept a switch rather than deleted because a lesson
	-- sat in a doorway is exactly the case where the panel is the right answer, and
	-- because the whole point of the room is a place discs *could* go if that
	-- decision is ever revisited -- it is not a decision this file gets to make twice.
	PhysicalLessons = false,

	-- The fan the answer discs are placed in. Distance is how far from the player the
	-- fan reaches; reach is how near a disc counts as standing on it, and it is also
	-- the radius the disc is drawn at, so the disc the player sees is the disc that
	-- counts. The two are kept apart so a question is never answered by the disc it
	-- was placed under your feet, and the arc widens with the answer count so no two
	-- discs sit within reach of each other.
	-- Safe range: Distance 4-7, Reach 2-3, Reach below Distance - 2, Arc 100-200.
	DiscDistanceStuds = 5.5,
	DiscReachStuds = 2.5,
	DiscArcDegrees = 150,

	-- Teacher. A humanoid at the front of the room facing the student while the
	-- lesson is in session, reacting to answers -- a bow on right, a step back
	-- on wrong. Placed opposite the player from the room centre, walked in at
	-- the start and despawned at the end. Gateable for testing the lesson loop
	-- without the presence, and gracefully skipped if the floor refuses a spot.
	TeacherEnabled = true,
	TeacherFrontStuds = 13, -- distance of the teacher's standing spot from the room centre
	TeacherWalkInStuds = 5, -- how far behind the front spot the teacher spawns
	TeacherNodSeconds = 1.2, -- how long the teacher holds a bow for a right answer
	TeacherBackStuds = 2, -- how far the teacher steps back on a wrong answer
	TeacherBackHoldSeconds = 1.2, -- how long they hold there before re-centring

	-- The share of a lesson's questions you have to get right for each verdict. The
	-- same shape as Work.Tasks' shares, and a lower bar: a shift's tasks are a test of
	-- attention and these are a test of knowing, so four in five is a good day.
	-- Safe range: Good 0.7-0.95, Ok 0.3-0.6, Good above Ok.
	GoodShare = 0.8,
	OkShare = 0.4,

	-- What a lesson is worth in smarts, by verdict.
	--
	-- Per lesson rather than per answer, for exactly the reason work pays standing per
	-- shift rather than per task: smarts runs 0-100 and starts at 50, so there are
	-- fifty points of headroom to spend across twelve years. At two a lesson, a child
	-- who attends and pays attention arrives at sixteen near the ceiling, and one who
	-- turns up and guesses arrives about halfway there. A point an answer would cap
	-- them both out before they were ten and make the back half of childhood pointless.
	-- Safe range: 1-4, 0-2 and 0-1, best first.
	SmartsPerGoodLesson = 2,
	SmartsPerOkLesson = 1,
	SmartsPerPoorLesson = 0,

	-- What a school year you never turned up to costs, applied on the birthday that
	-- ends it. Only ever between StartAge and EndAge, and only when the year had zero
	-- lessons in it -- one lesson is enough to prove you went.
	--
	-- This is the entire stake. Without it school is free upside and skipping it costs
	-- nothing but the upside, which is not a decision -- and a game where the whole of
	-- childhood is optional has spent twelve years saying nothing. Smaller than a good
	-- lesson pays, so a year you half-attended still comes out ahead of one you did
	-- not, and a childhood spent elsewhere ends around thirty smarts rather than at
	-- zero: behind, not ruined.
	-- Safe range: -4 to 0. At 0 school has no downside and the office job is the only
	-- reason to attend.
	SmartsPerYearMissed = -2,

	-- The mastery ladder, and it is per subject rather than per school: being good at
	-- Science says nothing about Music, and one number over the whole timetable would let
	-- a player master the one subject with a real verb and skip the five they had never
	-- touched.
	--
	-- This is the Bully rule, and it is the reason school has an end rather than just a
	-- last year. Attending a subject you have already beaten is the purest version of the
	-- unskilled-dead-time anti-pattern: the same lesson, the same clock, and nothing left
	-- in it to learn. So passing enough of a subject buys the right to stop sitting it --
	-- see School.Mastery.Levels for what "enough" is -- and the afternoon it hands back is
	-- the reward. Not a number: an hour of childhood you get to spend somewhere else.
	Mastery = {
		-- Rungs on the ladder, shared by every subject. Five because it has to be reachable
		-- inside a childhood and still cost something: at PassesPerLevel = 2 that is eight
		-- good lessons to top a subject out, against thirty-six lessons in a whole school
		-- career -- so a player can master two or three subjects by graduation and not all
		-- six, which is the shape that makes it a choice about what you are good at.
		--
		-- Science's RevealedStepsByLevel must be exactly this long. It is the one verb that
		-- currently gives a level a meaning of its own, and a ladder with a rung the verb
		-- has no answer for is a promotion that visibly does nothing.
		-- Safe range: 3-6. Above ~6 the top rung arrives after school has ended.
		Levels = 5,

		-- Lessons at or above GoodShare that buy a rung. Two so a single lucky lesson does
		-- not promote and a single bad one does not feel like it undid anything.
		-- Safe range: 2-4.
		PassesPerLevel = 2,
	},

	-- Geography, which is the errand: you are told the *name* of somewhere and you go
	-- there. No lit disc, no line on the floor.
	--
	-- That absence is the whole verb, and it only works because of how much the rest of
	-- the game does the opposite. Every other destination in AGES arrives as a gold disc
	-- with a beam pointing at it and the distance written on the waypoint -- the shift,
	-- the lure, the job post. A child has spent ten years being led by the hand. This is
	-- the one lesson that lets go, and the skill being tested is the only one a town can
	-- honestly test: do you know where anything is.
	--
	-- Nothing here names a place. The destinations are drawn from the live place graph at
	-- the moment the lesson starts, so a town that grows grows the subject with it and a
	-- place renamed in Studio is never a lesson pointing at somewhere that no longer
	-- exists. See GeographyService.
	Hunt = {
		-- Destinations in one lesson. Three, which at the leg lengths below is a lesson of
		-- roughly the same ninety seconds a quiz is -- and, more to the point, three is
		-- enough for a bad first guess to be recoverable and few enough that each one still
		-- counts for a third of the grade.
		-- Safe range: 2-5. Above ~5 the lesson outlasts the walk home.
		Stops = 3,

		-- How far apart consecutive destinations may be, in studs. The town is about 930
		-- studs across and a schoolchild walks at 16, so the far end of this band is a
		-- twenty-eight second leg and the near end about twelve.
		--
		-- A band rather than a maximum, and the minimum is the important half: without it
		-- the draw happily picks the shop next door, and a lesson made of three ten-stud
		-- hops is not a lesson about a town. With it, a hunt walks a loop around a district
		-- rather than crossing the map twice.
		-- Safe range: 120-300 and 350-650, low below high.
		MinLegStuds = 200,
		MaxLegStuds = 450,

		-- How near a destination counts as arriving. Looser than a classroom's attend
		-- radius on purpose: a place point sits behind a counter or inside a doorway, and
		-- being made to find the exact tile after already finding the building is precision
		-- for its own sake -- the walk was the lesson and it is already over.
		-- Safe range: 8-25.
		ArriveRadiusStuds = 14,

		-- How far above or below the spot the lesson started from a destination may be
		-- and still be drawable, in studs.
		--
		-- This is the upstairs test. The city's fifty-six first-floor apartments are
		-- place points like any other, sixteen studs up, and every one of them is a
		-- stranger's home behind a door with no sign on it. A verb that gives you a name
		-- and no marker can only be played by a player who can *see* the destination from
		-- the street, so a place you have to already know the way into is not a
		-- destination -- it is a riddle. Ground-floor shop interiors are well inside this
		-- and stay drawable, which is right: the mall is findable from outside.
		-- Safe range: 5-12. Above ~16 the upstairs flats come back.
		MaxRiseStuds = 8,

		-- The most a stop the clock ran out on can still be worth, as a share of one
		-- found, scaled by how much of the way there the player actually got.
		--
		-- Without this the lesson has four possible scores -- none, one, two or three of
		-- three -- and a player who was thirty studs from the bookstore when time went
		-- scores exactly what a player who never left the school scores. That is the
		-- undifferentiated-outcome trap, and the fix has to be in the verb's own units,
		-- which are distance: credit is the fraction of the original gap closed at the
		-- player's nearest approach. It is not a speed bonus and must never become one --
		-- getting there fast earns nothing extra, because wandering is what the subject
		-- is for.
		-- Safe range: 0.3-0.6. At 1 a near miss pays the same as arriving.
		MissedCreditCap = 0.5,

		-- How often a running hunt re-reads where the player is standing. Matches
		-- School.TickSeconds because it is the identical proximity job.
		-- Safe range: 0.1-0.5. Above ~0.5 arrival visibly lags the footstep.
		TickSeconds = 0.25,

		-- How long each destination may take before the lesson gives up on it and moves on.
		-- Sixty seconds is nearly four times the longest leg, so this only ever fires on a
		-- player who is genuinely lost -- which is the honest failure for this verb.
		--
		-- Moving on rather than ending, deliberately: a missed stop scores nothing and the
		-- lesson continues. A verb whose failure state is "the activity stops" punishes by
		-- waiting, which is the one consequence shape we have ruled out everywhere else.
		-- Safe range: 30-120. Below ~30 a wrong first guess cannot be recovered from.
		SecondsPerStop = 60,

		-- How long the line about the stop you just reached holds before the next name is
		-- given. The same beat a lesson's verdict gets and for the same reason: arriving is
		-- the payoff and a payoff with no pause is one nobody registers.
		-- Safe range: 1-4.
		ArrivedSeconds = 2,

		-- What each mastery rung tells you, on top of everything the rungs below it told
		-- you. This is the entire reward of the subject and it is deliberately not a
		-- number: a level does not make you walk faster or score more, it makes the town
		-- legible. That is Bully's map markers, which is the best reward in that game, and
		-- it is the one progression a player feels as the world changing rather than as a
		-- statistic moving.
		--
		-- Must be exactly School.Mastery.Levels long, checked at require time in
		-- GeographyService for the same reason Science's RevealedStepsByLevel is: a rung
		-- the verb has no answer for is a promotion that visibly does nothing.
		--
		--   name    -- the place's own label, and nothing else. Level one is being told
		--              "the pages & press" and having to know that is the bookstore.
		--   area    -- roughly where in town it is, as a compass sector from the school.
		--   bearing -- an arrow at the top of the screen pointing at it. Direction only.
		--   range   -- how far away it is, which with the arrow is very nearly the guide
		--              line the rest of the game gives away for free.
		--
		-- The fifth rung adds nothing to the list because the fifth rung is the exit: it
		-- tops the subject out and buys the right to skip, which is what every subject's
		-- top rung buys.
		RevealedByLevel = { "name", "area", "bearing", "range", "range" },
	},

	-- Content limits, enforced at server start rather than found in play. The answer
	-- count is Enact's, because these are Enact's pads and a fifth of them crowds the
	-- fan the same way whoever is asking -- and the question length is longer than a
	-- choice label because a question is read from a HUD row rather than off the floor.
	-- Safe range: 60-160.
	MaxAnswers = Config.Enact.MaxChoices,
	MaxAskLength = 96,
}

-- Science. The first subject with a verb of its own rather than a question with the
-- word "science" written above it.
--
-- The shape is Bully's: every subject is a different *thing you do*, not a different
-- question set, and passing buys the right to skip rather than the right to do it
-- again. What Science does is run a procedure -- a board names an ordered list of
-- stations, you walk the room clicking them in order, and each click stacks a step on
-- a bench. Nothing is scored until you commit the bench, so the whole stack is undoable
-- right up to that moment; that is the commit-and-undo pair every activity here owes.
--
-- Two benches run at once against a shared set of stations, which is where the load
-- comes from: the second procedure is not twice the work, it is the same work with the
-- room contested. Reagents are the traversal forcer -- steps spend from a shared pool
-- and the cupboard is across the room -- and mastery does not raise a number, it shows
-- you more of the board at once, so a level is felt as fewer walks back to read it.
--
-- Nothing in here restates a verdict share or a smarts payout. A procedure's score is
-- a 0-1 share like a lesson's, so it lands on Config.School's GoodShare/OkShare and
-- SmartsPer*Lesson and there is deliberately no second ladder to keep in step.

-- Passive bonuses a life earns when a subject reaches mastery level 5 (cleared).
-- Applied as a reduction to `minSmarts` on jobs that have both `minSmarts` and a
-- gate for that subject. A life with smarts 50 and science level 5 hires for a
-- job that asks for smarts 50 and science = 3, even though the raw number is
-- exactly at the line -- the perk pushed it just over.
--
-- C decides which subjects get perks and at what level; B consumes them.
-- Map entry keyed by subject id; absent key means no perk for that subject.
-- Empty until C fills it in, and empty means `{}`. This was written as
-- `{ [undefined] = nil }` to say "nothing here yet", which is not what it says to Lua:
-- `undefined` is an unbound global, so the key is nil, and a nil key in a table
-- constructor is a hard "table index is nil" thrown while Config's own module body is
-- running. Every service in both places requires this file, so nothing in the game --
-- not one service, in the lobby or the game place -- ever loaded. The player still got a
-- character, because Roblox spawns that itself, which is why the symptom was "I spawn
-- normal size and cannot play" rather than an error naming Config.
-- `WorkService` reads this with a keyed lookup, so zero entries is inert, not special.
Config.SubjectPerks = {}

Config.School.Science = {
	-- Benches running at once. Two, because one is a queue and three is a spectacle you
	-- watch rather than a room you work: with two, every trip to a station is a choice
	-- about which procedure it serves, and that choice is the whole mechanic.
	-- Safe range: 1-3. At 1 there is no contention and this is a fetch quest.
	Benches = 2,

	-- The second bench does not open until the first procedure is this far along, so the
	-- opening seconds teach the verb before they test it.
	-- Safe range: 0.2-0.5. Above ~0.5 the second bench cannot be finished in time.
	SecondBenchAtShare = 0.3,

	-- The shortest procedure worth authoring. Four is long enough that order matters --
	-- below it there is no sequence to get wrong, only a list to tick off. The ceiling is
	-- MaxSteps, further down, and there is deliberately only one of those: two separately
	-- tunable maximums is how a content check ends up quietly enforcing the looser one.
	-- Safe range: 3-6, and below MaxSteps.
	StepsMin = 4,

	-- How long a procedure stands before the bench spoils and scores itself where it is.
	-- Sized so an unmastered player crossing the room to re-read the board can finish
	-- one bench comfortably and two only by planning the order of their trips.
	-- Safe range: 50-120. Below ~50 the cupboard trip alone eats the clock.
	SecondsPerProcedure = 80,

	-- Speed is a multiplier on the score, never the score itself, and it has a floor: a
	-- correct procedure committed on the buzzer is still worth most of a correct
	-- procedure. Full credit needs this share of the clock still unspent at commit.
	-- Safe range: Floor 0.6-0.85, FullShare 0.25-0.5. A floor of 0 makes a slow-but-right
	-- run worthless, which punishes the player who is learning the room.
	SpeedFloorFactor = 0.7,
	SpeedFullShare = 0.4,

	-- Reagents. Every step spends from one shared pool, refilled at a cupboard that is
	-- deliberately not next to either bench. Twelve charges against a 4-8 step procedure
	-- means roughly one cupboard trip per procedure and about one every fifty seconds
	-- with two benches running -- close enough to the forty-to-sixty window that the room
	-- never goes quiet, without the trip becoming the activity.
	--
	-- Shared rather than per-bench on purpose: it is the second thing the two procedures
	-- have to fight over, and it is the one that makes committing a bench early a real
	-- decision rather than always the safe one.
	-- Safe range: Charges 8-20, ChargesPerStep 1-2, Refill 1.5-4.
	SupplyCharges = 12,
	ChargesPerStep = 1,
	CupboardRefillSeconds = 2,

	-- How much of the board you can see at once, by mastery level. This is requirement
	-- six and the only progression the verb has: the player does not get faster hands or
	-- a bigger number, they get to hold more of the procedure in their head at a time,
	-- and they feel it as trips to the board that stop being necessary. At level one
	-- three steps is one comfortable walk; by level five the whole longest procedure is
	-- on screen and the board is furniture.
	--
	-- The length of this list is also the level ceiling -- ScienceService reads
	-- `#RevealedStepsByLevel` rather than holding a separate maximum -- so adding a sixth
	-- number here adds a sixth level and nothing else has to be told.
	-- Safe range: rising, first 2-4, last at or above the longest authored procedure.
	RevealedStepsByLevel = { 3, 4, 5, 6, 8 },

	-- Escalation is deliberately *not* a station count that grows with mastery, which is
	-- what this block held first. The lab is one room built once and shared by everyone
	-- standing in it -- two players at different levels cannot be in differently furnished
	-- versions of the same place -- so every station stands from the start, and the space
	-- escalates by which stations a *procedure* sends you to. A nine-year-old's four-step
	-- errand walks past five machines it never touches, which is also what a school lab
	-- actually looks like.

	-- What a pass is and how many buy a level both live on School.Mastery now, because
	-- every subject climbs the same ladder and two ladders drifting apart would mean a
	-- procedure and a quiz disagreeing about what "mastered" is. What is still Science's
	-- own is what a level *buys*, which is RevealedStepsByLevel above -- and the length of
	-- that list must equal School.Mastery.Levels, which ScienceService asserts at require
	-- time rather than trusting.

	-- Room and reach. The board is read from further away than a station is clicked from,
	-- because reading is not an interaction and standing in the doorway squinting is a
	-- legitimate way to play. Station reach is tight enough that two stations can stand
	-- near each other without either answering for the other.
	-- Safe range: Station 3-5, Bench 4-6, Board 5-9, Cupboard 3-5, Room 30-60.
	StationRadiusStuds = 4,
	BenchRadiusStuds = 5,
	BoardRadiusStuds = 7,
	CupboardRadiusStuds = 4,
	RoomRadiusStuds = 40,

	-- How often the server re-checks players against benches, stations and the cupboard.
	-- Matches School.TickSeconds because it is the identical proximity job.
	-- Safe range: 0.1-1.
	TickSeconds = 0.25,

	-- How long a committed bench holds its result before it clears and re-lays. The same
	-- beat as a lesson's verdict and for the same reason: the run has to be legible
	-- before the next one starts.
	-- Safe range: 2-6.
	VerdictSeconds = 3.5,

	-- Content limits, enforced at server start rather than found in play. A step label is
	-- shorter than a question because it is read off a board in a list rather than a HUD
	-- row, and ten steps is where the walk stops being a plan and becomes a memory test.
	-- Safe range: MaxSteps 6-12 and above StepsMin, MaxStepLabelLength 16-40.
	MaxSteps = 10,
	MaxStepLabelLength = 28,

	-- Where the lab's furniture stands, as fractions of RoomRadiusStuds rather than as
	-- studs, so widening the room moves everything in it and nothing has to be re-measured.
	--
	-- The arrangement is the mechanic in physical form and the fractions are not
	-- arbitrary. The board and the cupboard are on *opposite* sides, because the two
	-- errands the verb forces -- go and re-read, go and refill -- have to be different
	-- journeys or the player batches them into one and neither costs anything. The
	-- benches sit between them on the cross axis so that every commit is a decision made
	-- in the middle of the room rather than on the way past something else. The stations
	-- ring the outside, further out than any of it, because they are the steps and the
	-- steps are what the player should be spending their walking on.
	Build = {
		-- Safe range: 0.4-0.7 each, Station above both. Station at or above 1.0 puts a
		-- step outside the room the player is held in and ends the lesson mid-procedure.
		BoardDistanceShare = 0.55,
		CupboardDistanceShare = 0.55,
		BenchDistanceShare = 0.35,
		StationDistanceShare = 0.75,

		-- Bearings, in degrees clockwise from the room's forward. Board and cupboard face
		-- each other across the room; the benches take the cross axis. Written out rather
		-- than derived so a builder rearranging the room can see the whole layout in four
		-- numbers.
		BoardBearing = 0,
		CupboardBearing = 180,
		FirstBenchBearing = 90,
		BenchBearingStep = 180,

		-- How far off a station may be nudged when the floor refuses its first spot, as a
		-- share of the room radius, and how many rings out are tried. Some floor is
		-- better than a station that does not exist -- a missing station is a procedure
		-- that cannot be finished, which is the one failure the player cannot play
		-- around. Safe range: 0.05-0.2, 2-5.
		StationRetryShare = 0.1,
		StationRetries = 3,

		-- Placeholder furniture, in studs. Sized so a bench reads as something you stand
		-- at and a station as something you reach, from across a forty-stud room, and
		-- deliberately blocky: these are stand-ins for models a builder drops in later,
		-- and anything prettier here would only be harder to throw away.
		-- Safe range: 2-6 wide, 1-4 tall.
		StationSize = Vector3.new(2.6, 3, 2.6),
		BenchSize = Vector3.new(6, 3, 3),
		CupboardSize = Vector3.new(3.5, 6, 2),
		BoardSize = Vector3.new(10, 6, 0.6),

		-- How far away a station's own name label can still be read. Shorter than a shop
		-- sign because it is not deciding whether you walk over -- the board already did
		-- that -- it is confirming which thing you arrived at.
		-- Safe range: 30-90.
		LabelMaxDistanceStuds = 60,
	},
}

-- Art. The study: a small picture is pinned to the wall of the room and you copy it,
-- cell by cell, onto a canvas.
--
-- The line that makes this a different subject from Science rather than the same one
-- with paint on it: **Science hides the board and asks you to remember. Art shows you
-- everything and asks you to notice.** The wall is always in the room, the canvas is
-- always on screen, and neither is ever annotated -- nothing marks a cell as wrong,
-- ever. The verb is the comparison, and the day a feature helpfully outlines the cells
-- that do not match is the day this subject stops existing.
--
-- Which is why the picture moves. A study that sat still would be a form to fill in, so
-- part of every study is allowed to shift while you paint -- the light turns, somebody
-- nudges the fruit -- and cells you have already painted quietly stop being right. You
-- are told how many have gone stale and never which, so the two things worth doing at
-- any moment are "paint an empty cell" and "go and find the one that changed", which is
-- the two-queue requirement arriving from a single rule rather than from a second bench.
--
-- Signing is the commit and it is a real decision, unlike the lab's. Your score is the
-- canvas at the moment you sign, and the canvas rots while you hold it -- so finishing
-- is a trade between covering more of the picture and keeping what you have.
--
-- Nothing in here restates a verdict share or a smarts payout. A canvas scores a 0-1
-- share exactly as a procedure and a quiz do, and lands on Config.School's GoodShare /
-- OkShare and SmartsPer*Lesson.
Config.School.Art = {
	-- The canvas, in cells. Sixteen is the number where the picture is still a picture --
	-- a harbour with a sail and a hull in it -- and the painting is still about eighty
	-- clicks including repairs, which is a ninety-second lesson at a comfortable pace
	-- rather than a typing test.
	--
	-- Both numbers are load bearing on the content: every study in content/Studies is
	-- authored as exactly Rows strings of exactly Columns letters, and changing either of
	-- these without redrawing all five pictures errors at require time by design.
	-- Safe range: 3-6 each. At 8x8 a lesson is four hundred clicks.
	Columns = 4,
	Rows = 4,

	-- How long the canvas may be worked on before it is taken away and scored as it
	-- stands. Longer than a quiz because there are sixteen cells to visit rather than
	-- five questions, and short enough that the last thirty seconds are spent choosing
	-- what to fix rather than idly touching up a finished picture.
	-- Safe range: 60-180. Below ~60 nobody at two tubes can cover the canvas at all.
	SecondsPerCanvas = 120,

	-- How often something in the study is allowed to move, and how many cells go at once.
	--
	-- This is the pacing of the whole subject. At eighteen seconds a two-minute canvas
	-- shifts about six times, so roughly a third of the lesson is spent repairing -- enough
	-- that ignoring it loses the grade, few enough that the picture is still recognisably
	-- the thing you started copying. One cell at a time rather than two, because a shift
	-- you have to hunt for is the mechanic and a shift that redraws half the wall is just
	-- the wall being replaced.
	-- Safe range: 12-30 and 1-2. Below ~12 the canvas rots faster than anyone can paint.
	ShiftSeconds = 18,
	ShiftCells = 1,

	-- Strokes in the pot, and how near the supply cupboard you have to get to fill it.
	--
	-- The traversal forcer, and it is a shared pot rather than one per tube on purpose:
	-- per-tube supply would quietly delete this requirement at the top of the ladder,
	-- where a player holds eight tubes and therefore four times the paint. Fourteen
	-- against sixteen cells means every canvas needs at least one trip and a canvas with
	-- repairs in it needs two.
	--
	-- What the trip costs is not the seconds. It is that the study wall is behind you the
	-- whole way there and back -- see Build.CupboardBearing -- so the shift that happens
	-- while you are fetching paint is the one you have no idea about. That is the
	-- difference between this errand and the lab's, which only ever costs time.
	-- Safe range: 10-24 and 4-10. Above ~24 the cupboard never gets visited.
	StrokesPerRefill = 14,
	CupboardRadiusStuds = 7,

	-- How near the easel you have to be to put paint on the canvas. Tight, because the
	-- easel is the one place in the room where the study and the canvas are both in front
	-- of you, and painting from the cupboard would make the trip free.
	-- Safe range: 4-10. Above ~10 it starts to overlap the cupboard's own radius.
	EaselRadiusStuds = 6,

	-- How far the player may get from the middle of the room before the canvas counts as
	-- walked away from, and the scale everything in Build is laid out against.
	--
	-- Half again the size of the lab, which is the one number in this block that had to be
	-- argued for. At the lab's forty the easel and the cupboard end up about twenty-five
	-- studs apart, which a schoolchild covers in a second and a half -- and a fetch that
	-- takes three seconds round trip is not a pacing interrupt, it is a button with a walk
	-- animation. At sixty the trip is closer to seven seconds of not being able to see the
	-- wall, against a study that moves every eighteen, so going for paint genuinely risks
	-- missing something. The room is big because the mechanic is *distance from the
	-- picture*, and there is no other way to buy that.
	-- Safe range: 40-90. Below ~40 the cupboard stops costing anything.
	RoomRadiusStuds = 60,

	-- How often a running canvas re-reads where the player is standing and runs its
	-- clocks. Matches School.TickSeconds because it is the identical proximity job.
	-- Safe range: 0.1-0.5.
	TickSeconds = 0.25,

	-- How many tubes of paint each mastery rung hands over, taken from the study's own
	-- colours most-used first -- so rung one gives you the two the picture is mostly made
	-- of, and the rungs above it give you the ones it is barely made of, which are exactly
	-- the ones that make it look like the thing it is of. A sail, a hull, a highlight.
	--
	-- This is the entire reward of the subject, and unlike Geography's it is not
	-- information: it is how much room you have to be wrong. At two tubes the best
	-- possible copy of the tightest study here scores 0.835 against a GoodShare of 0.8 --
	-- a perfect painting barely passes, and every cell you fail to reach costs you the
	-- lesson. At the top rung the ceiling is 1.0 and there is slack in it for a corner you
	-- never got to. That is progression widening the player's own tolerance rather than
	-- moving a number outside the verb, and it is checked at require time in ArtService:
	-- a first rung whose ceiling drops under GoodShare would be a subject nobody could
	-- ever pass their way out of.
	--
	-- The last entry is the whole shelf rather than six, because a study may be made of
	-- more colours than five and the top rung is also the rung that buys the right to
	-- skip -- so it should be the one where a perfect copy is actually possible.
	-- Must be exactly School.Mastery.Levels long.
	-- Safe range: 2-8 each, rising, first at or above 2. At 1 there is nothing to choose.
	PaletteByLevel = { 2, 3, 4, 5, 8 },

	-- How long the closing line holds before the panel clears. The same beat every other
	-- subject's verdict gets.
	-- Safe range: 2-6.
	VerdictSeconds = 3.5,

	-- Where the art room's furniture stands, in the same fractions-of-the-radius terms the
	-- lab's Build block uses, so the two rooms are re-laid the same way.
	--
	-- The arrangement is the mechanic, again, and it is nearly the opposite of the lab's.
	-- There the board and the cupboard face each other so the two errands cannot be
	-- batched. Here there are not two errands -- there is one thing you must be looking at
	-- and one thing you must occasionally walk to, and they are put on opposite sides so
	-- that walking to the paint turns you away from the picture.
	Build = {
		-- Safe range: 0.4-0.8 each, Easel below both. The easel sits nearer the wall than
		-- the middle so the study fills the view from it.
		WallDistanceShare = 0.7,
		EaselDistanceShare = 0.25,
		CupboardDistanceShare = 0.65,

		-- Bearings in degrees clockwise from the room's forward, matching the lab's
		-- convention. The wall and the cupboard face each other across the easel.
		WallBearing = 0,
		EaselBearing = 0,
		CupboardBearing = 180,

		-- One cell of the study wall, in studs, and the gap between them. Big because the
		-- whole subject is reading this thing from across a room -- a wall you have to walk
		-- up to would make every comparison a round trip and the lesson would be a
		-- pilgrimage. At 4.5 studs a four-wide study is about twenty studs across, which is
		-- legible from the easel at the distances above.
		-- Safe range: 3-7 and 0.1-0.6.
		WallCellStuds = 4.5,
		WallCellGapStuds = 0.35,

		-- How far off the floor the bottom row of the wall sits, and how thick the panels
		-- are. Lifted so the study is at eye height from a standing child rather than
		-- something they are looking down at.
		-- Safe range: 2-8 and 0.2-1.
		WallLiftStuds = 4,
		WallDepthStuds = 0.4,

		-- Placeholder furniture, in studs, in the same blocky spirit as the lab's: these
		-- are stand-ins for models a builder drops in later.
		EaselSize = Vector3.new(3, 5, 2),
		CupboardSize = Vector3.new(3.5, 6, 2),

		-- How far away the room's own labels can still be read. Matches the lab's.
		-- Safe range: 30-90.
		LabelMaxDistanceStuds = 60,

		-- Hand-placed interact anchors in the school building. Each entry names an
		-- event id from LifeEvents/School.luau and a world position (x, z) where its
		-- tagged anchor part lives. The service reads the tag and attribute itself;
		-- this block is the inventory so the debug path can list and relist them.
		-- Safe range: one entry per event, positions inside the school footprint.
		Anchors = {
			{ eventId = "school_notice_board", x = -114.0, z = 42.0 },
			{ eventId = "school_water_fountain", x = -138.0, z = 48.0 },
			{ eventId = "school_locker_note", x = -150.0, z = 22.0 },
			{ eventId = "school_library_book", x = -150.0, z = 43.0 },
		},
	},
}

-- The gym. A room full of machines that is also a place a life goes to spend
-- effort on itself.
--
-- The swap contract the user asked for lives here in its simplest form: the
-- world's equipment is found by tag, not by name, so whoever builds a nicer
-- treadmill into the gym later can replace the part and keep the mechanic. The
-- generator stamps the tag on the machine and an attribute naming which machine
-- it is; this file is the only place the two strings are agreed.
Config.Gym = {
	-- The tag a part carries to be read as gym equipment, and the attribute
	-- naming the machine: "treadmill", "bench", "dumbbells", "pullup". A kind
	-- the service has no routine for is refused at load, not in play.
	EquipmentTag = "AgesGymEquipment",
	GymKindAttribute = "GymKind",

	-- How near a machine you must be to use it. Slightly tighter than a person's
	-- reach, because a machine is a thing you stand at rather than a conversation
	-- you stand in. Safe range: 4-10.
	ReachStuds = 6,

	-- A workout is a deliberate hour, not a button you can hammer: after one, the
	-- machine is spent for the rest of the game year. Nil-able by the day's end
	-- logic if a year ever needs it, and the reason it exists is that a machine
	-- with unlimited reps is a stat button, which is not a life.
	--
	-- Safe range: 1-5. At 1 a gym session is once a year per machine and the room
	-- has about as many sessions as school has lessons.
	WorkoutsPerYear = 2,

	-- Stamina. A session-local bar that drains per rep and penalises misses.
	-- Push-your-luck: go for every rep and you finish with nothing left; miss
	-- early and you lose the last rep or two.
	--
	-- Both live here rather than on the machine because they describe the body,
	-- not the equipment: a missed lift and a missed pull-up tire you the same way.
	MaxStamina = 100,
	MissStamina = 5,

	-- How much the sweet zone widens as health climbs, as a share of the machine's
	-- own base width, at Config.Stats.Max health.
	--
	-- This is the whole reason the gym is worth repeating. Progression used to be a
	-- health number that lived entirely outside the verb: a character at 90 health
	-- had exactly the same timing window as one at 10, so getting fitter changed a
	-- readout and nothing you could feel. Now the bar you are aiming at physically
	-- grows, and you can see your own margin widen between one workout and the next.
	--
	-- At 0.6 a maxed character's window is 1.6x a beginner's -- a large, legible
	-- difference that still leaves the hardest machine demanding at full health.
	-- The Perfect band widens by the same share, so the ratio of Perfect to Good
	-- holds and fitness never turns the machine into a single undifferentiated
	-- target. Safe range: 0-1. At 0 the window is fixed and requirement 6 is gone.
	HealthWindowBonus = 0.6,

	-- The four machines.
	--
	-- Every field is stated by every machine, deliberately: these used to share one
	-- set of numbers and one `gradeFor(progress)` that never saw which machine it
	-- was grading, so the treadmill and the bench press ran byte-identical code and
	-- differed only in the string on the panel. Four machines wearing one minigame
	-- is not four machines.
	--
	-- What separates them is the shape of the timing problem, not its difficulty:
	--
	--   sweepSeconds   how long the needle takes to cross the bar
	--   sweetCenter    where on the bar the zone sits -- NOT always the middle
	--   sweetFraction  the zone's width as a share of the bar
	--   perfectFrac    the inner band, same units
	--   curve          how the needle moves: see SHAPES in GymService
	--
	--   "steady"      constant speed. Read it and press.
	--   "quickening"  creeps, then rushes. You have to commit before it looks right.
	--   "easing"      rushes, then crawls. Generous, and tempts you into over-waiting.
	--
	-- Same one input on all four; four different things to learn. A player who has
	-- mastered the treadmill knows nothing yet about the pull-up bar, which is the
	-- only way one button survives a hundred repetitions.
	Kinds = {
		-- The teaching machine. Middle of the bar, constant speed, widest zone,
		-- cheapest reps, most of them. Health-heavy: running is not what makes you
		-- look good, it is what makes you last.
		treadmill = {
			label = "Treadmill",
			curve = "steady",
			sweepSeconds = 2.2,
			sweetCenter = 0.5,
			sweetFraction = 0.24,
			perfectFraction = 0.09,
			reps = 12,
			repStamina = 7,
			healthPerPerfect = 2,
			healthPerGood = 1,
			looksPerPerfect = 0,
			looksPerGood = 0,
		},

		-- Power. Few, heavy, expensive reps against a needle that creeps and then
		-- rushes into a late zone -- you press where you think it will be, not where
		-- it is. Biggest single-rep payout in the room and the fastest to exhaust.
		bench = {
			label = "Bench Press",
			curve = "quickening",
			sweepSeconds = 3.0,
			sweetCenter = 0.74,
			sweetFraction = 0.18,
			perfectFraction = 0.06,
			reps = 7,
			repStamina = 15,
			healthPerPerfect = 3,
			healthPerGood = 1,
			looksPerPerfect = 1,
			looksPerGood = 0,
		},

		-- Control. The needle arrives fast and then crawls through a middle zone, so
		-- the window is forgiving but sitting in it invites you to wait for a Perfect
		-- that is already behind you. The looks machine.
		dumbbells = {
			label = "Dumbbells",
			curve = "easing",
			sweepSeconds = 2.6,
			sweetCenter = 0.52,
			sweetFraction = 0.20,
			perfectFraction = 0.07,
			reps = 10,
			repStamina = 10,
			healthPerPerfect = 1,
			healthPerGood = 0,
			looksPerPerfect = 2,
			looksPerGood = 1,
		},

		-- The hard one. Early, narrow and quickening: the zone is past before a new
		-- player has decided to press. Pays both stats well and costs the most per
		-- rep, so it is the machine you graduate onto rather than the one you start
		-- on. Nothing gates it -- the timing does.
		pullup = {
			label = "Pull-Up Bar",
			curve = "quickening",
			sweepSeconds = 2.4,
			sweetCenter = 0.34,
			sweetFraction = 0.15,
			perfectFraction = 0.05,
			reps = 8,
			repStamina = 13,
			healthPerPerfect = 2,
			healthPerGood = 1,
			looksPerPerfect = 2,
			looksPerGood = 0,
		},
	},

	-- How long the verdict beat lasts before the next rep starts.
	-- Long enough to read "Perfect" or "Good", short enough not to stall.
	VerdictSeconds = 1.2,

	-- How often the server ticks the sweep forward. 5-6 times per sweep
	-- second gives smooth motion without burning budget.
	TickSeconds = 0.18,

	-- How far from a machine's centre the player must stay. Matches the
	-- school's room radius: a gym is the same size box as a classroom.
	RoomRadiusStuds = 20,
}

-- The stadium's ambient crowd. tools/gen_city.py builds every seat in every
-- tier as a real `AgesStadiumCrowdSeat` anchor now -- there is no separate
-- static-mannequin fill any more, an empty seat is just an empty seat -- plus
-- six roam anchors per stand's concourse (`AgesStadiumCrowdRoam`), and
-- StadiumCrowdService reads both by tag to seat and walk real NPCs through
-- the bowl. "The crowd looks fake" is only avoided while the caps below stay
-- fed, which is why StandUp* and SpawnPerTick exist alongside them.
--
-- The tag/attribute names here are the Luau side of a pair; the Python side
-- is `STADIUM_CROWD_SEAT_TAG`/`STADIUM_CROWD_ROAM_TAG`/`STADIUM_CROWD_STAND_
-- ATTR` in gen_city.py and the two literal strings must match exactly or the
-- service finds nothing -- there is no shared source for this pair, the same
-- way `Config.Gym.EquipmentTag` and gen_city.py's own gym tag are two
-- independently-typed copies of one string.
Config.Stadium = {
	SeatTag = "AgesStadiumCrowdSeat",
	RoamTag = "AgesStadiumCrowdRoam",
	StandAttribute = "Stand",

	-- How many real NPCs are ever seated/roaming at once. A hard ceiling
	-- rather than "spawn one per anchor found" for the same reason
	-- Config.Town.MaxBodied exists: NPCService.Spawn is a web call per rig,
	-- and nothing under it stops a caller asking for hundreds at once --
	-- there are well over a thousand seat anchors in the bowl now (every
	-- seat is one, see gen_city.py's `stadium_seat`). Safe range: 8-200
	-- seated, 4-48 roaming; MaxRoamingCrowd should stay a multiple of 4 so
	-- StadiumCrowdService.indexAnchors can split it evenly across the four
	-- stands. Raised well past the old 40/16 now that density is not the
	-- bottleneck any more -- SpawnPerTick below is what keeps a cap this
	-- size from asking NPCService for all of it in one burst.
	MaxSeatedCrowd = 120,
	MaxRoamingCrowd = 40,

	-- How fast a roaming spectator walks the concourse. Slower than a
	-- townsperson (Config.NPC.WalkSpeed) -- someone browsing a concourse
	-- between stands is not in a hurry to get anywhere.
	RoamWalkSpeed = 6,

	-- How long a roamer waits at each concourse stop before moving to the
	-- next. Safe range: 3-20.
	RoamPauseMinSeconds = 4,
	RoamPauseMaxSeconds = 12,

	-- How often the crowd is re-checked and topped back up to its caps --
	-- a lost rig (streaming, a failed build) is rebuilt on the next tick
	-- rather than left as a gap for the rest of the server's life. Matches
	-- GangService's TickSeconds for the same "not every frame, not so rare
	-- it visibly lags" reasoning. Safe range: 2-15.
	TickSeconds = 5,

	-- How many empty slots (seated and roaming counted together) tickCrowd
	-- is allowed to start spawning on any one tick. MaxSeatedCrowd and
	-- MaxRoamingCrowd together can be asking for over 150 rigs from an empty
	-- server the moment the first player loads in, and NPCService.Spawn is a
	-- web call per rig -- firing all of them from the same tick in one burst
	-- of task.spawn calls is the exact overload Config.Town's own bodied-NPC
	-- cap exists to avoid elsewhere. A low cap here does not slow the crowd
	-- down for long: at TickSeconds=5 and 8 a tick, the bowl is full inside
	-- a couple of minutes of a server starting, which nobody is standing in
	-- the forecourt timing. Safe range: 2-16.
	SpawnPerTick = 8,

	-- A seated fan sometimes stands up, takes a few steps back into the row
	-- behind their seat, and sits back down -- read independently per
	-- occupied seat on every tick, so no two get up in step with each
	-- other. StandUpChancePerTick is deliberately tiny: at TickSeconds=5 and
	-- a 120-seat crowd, 0.002 means roughly one fan in the whole bowl stands
	-- up every couple of ticks, which is already enough motion to keep a
	-- full stand from reading as a photograph. The step is straight back
	-- along the stand's own StandFacing direction (see below), away from
	-- the pitch and into the gap behind the row, not a pathfind through the
	-- packed seats either side. Safe range: chance 0.0005-0.01, step 3-8
	-- studs, seconds 3-15.
	StandUpChancePerTick = 0.002,
	StandUpStepStuds = 5.0,
	StandUpMinSeconds = 4,
	StandUpMaxSeconds = 10,

	-- Every stand's outward-facing direction, as a unit-length (x, z) --
	-- which way a seated spectator in that stand looks to be watching the
	-- pitch rather than the wall behind them. A seat anchor is a plain,
	-- unrotated `box()` part (see gen_city.py), so this is the only place
	-- that direction is recorded at all.
	StandFacing = {
		StandSouth = { x = 0, z = 1 },
		StandNorth = { x = 0, z = -1 },
		StandWest = { x = 1, z = 0 },
		StandEast = { x = -1, z = 0 },
	},

	-- The same two colours tools/gen_city.py's STAD_SEATS paints the tiers in
	-- (home red, alternating away pale) -- no shared source between the two,
	-- same as the tag names above, so a change to one palette means changing
	-- both by hand. StadiumCrowdService alternates a seated fan between these
	-- instead of a random Townsfolk shirt colour, so the stand reads as a
	-- crowd in kit rather than a crowd that happens to be sitting together.
	HomeShirtColor = Color3.fromRGB(178, 46, 46),
	AwayShirtColor = Color3.fromRGB(210, 210, 214),
}

-- The stadium's entrance moment: walking through the bowl's own gate (not the
-- forecourt atrium's front door, which is just the building's own threshold)
-- plays a cinematic camera beat and sends a fan over for an autograph, once
-- per player per server session. StadiumEntranceService reads GateTag off the
-- single invisible trigger part tools/gen_city.py's GateArch stands in the
-- doorway (STADIUM_GATE_TAG there) -- no shared source, so the literal string
-- must match exactly, the same arrangement as Config.Stadium's tags above.
Config.StadiumEntrance = {
	GateTag = "AgesStadiumGate",

	-- Studs from the trigger part that count as having crossed the gate. Wider
	-- than Config.World.InteractRadius's tighter room distance on purpose: this
	-- is a doorway a player walks straight through at a normal pace, not an
	-- object they stop in front of, and the check has to catch a crossing that
	-- might only be a couple of ticks wide.
	-- Safe range: 6-14.
	TriggerRadius = 10,

	-- How often the server checks players against the gate. Cheap: one part,
	-- checked against whoever is near the stadium. Safe range: 0.1-0.5.
	TickSeconds = 0.2,

	-- Seconds the camera takes to snap in from the normal follow shot to the
	-- close cinematic framing. Quick, so it reads as a cut to a replay angle
	-- rather than a slow pan catching up to something that already happened.
	-- Safe range: 0.3-1.2.
	ZoomInSeconds = 0.6,

	-- Seconds the camera holds the close framing before releasing -- long
	-- enough to read the fan's approach and the autograph beat; too long and
	-- standing still stops feeling like an entrance and starts feeling like a
	-- wait. Safe range: 2.5-6.
	HoldSeconds = 3.5,

	-- Seconds the camera takes easing back out to the normal follow shot.
	-- Safe range: 0.4-1.5.
	ReleaseSeconds = 0.8,

	-- The held shot's framing relative to the player: how far back, how high,
	-- and how far to the side -- a three-quarter portrait rather than a
	-- straight-on selfie, the same angle a walkout camera holds.
	-- Safe range: distance 5-10, height 2-5, side 1.5-4.
	FramingDistanceStuds = 7,
	FramingHeightStuds = 3.2,
	FramingSideStuds = 2.4,

	-- Field of view during the held shot. Roblox's default is 70; a narrower
	-- angle is what reads as a lens actually zoomed in rather than a camera
	-- that just moved closer with the same wide lens.
	-- Safe range: 35-55.
	FramingFov = 42,

	-- Studs from the player the fan stops at to ask for the autograph -- mirrors
	-- Config.NPC.ApproachStuds, kept separate because this beat is much shorter
	-- and closer than a delivery's doorstep wait.
	-- Safe range: 3-6.
	FanApproachStuds = 4,

	-- Seconds the fan holds the "talk" beat once arrived, before turning away.
	-- Safe range: 1.5-4.
	FanTalkBeatSeconds = 2.5,
}


-- People. The pillar of a life this game did not have.
--
-- Everybody in AGES until now was a delivery. Somebody walked in, handed over a line
-- or a five-dollar bill, walked out, and was gone -- and the next one was drawn from
-- the same four ids with no memory that the first had ever happened. A life made of
-- those is a life in which nobody knows you.
--
-- That absence is why the empty stretches of a life are empty. A sixty-five-year-old
-- has nothing to do not because nothing was written for them, but because there is
-- nobody to go and see; a toddler's parents are scenery for the same reason. Work gave
-- the middle of a life somewhere to be and school gave the first half of it. This is
-- what gives the whole of it somebody to be there with.
--
-- The verb is the game's only verb. They stand somewhere, you walk up, three dots wake
-- over their head, and you click them -- the same sentence as a dog, a hiring sign or a
-- birthday. What is on the list those dots open is the entire mechanic: somebody who
-- barely knows you has small talk on offer and nothing else, and somebody who does will
-- lend you money, talk you round, or put your name in somewhere. The relationship is
-- read off what they will do for you rather than off a number.
--
-- Nobody gets a sign. A hiring post and a school need one because a building cannot say
-- what it is, but a person already has their name over their head -- the humanoid draws
-- it -- and hanging a placard on somebody would make them premises.
--
-- Nothing here says who exists, where they stand or what they will do for you. That is
-- content, in content/People.luau, for the same reason jobs and lessons are: adding a
-- sister should be a table entry and not a tunable.
Config.People = {
	-- The range a bond moves in.
	--
	-- The floor is shallower than a job's, deliberately. A record at work is an opinion
	-- held by an institution and it is allowed to be brutal; the floor of a person is
	-- how bad it gets with somebody who is still, in the end, your mother. Below this
	-- there is nothing further for the number to say and no story in saying it.
	--
	-- The ceiling is high enough that a whole life of turning up is still climbing at
	-- the end of it. Reached by roughly ten good visits from a standing start, which is
	-- a decade -- so it is an achievement of a childhood rather than of a year.
	-- Safe range: -40 to -8, and 60-200.
	MinBond = -20,
	MaxBond = 100,

	-- How close you have to get before somebody has time for you. Generous compared to
	-- a job's clock-in radius, because walking up to a person is not a precision act --
	-- you are near them or you are not, and being made to shuffle onto an exact spot to
	-- talk to your dad would be the game asking for something nobody would think to give.
	-- Safe range: 5-14. Above about 14 they notice you from across a room.
	ReachStuds = 8,

	-- What a year of not turning up costs.
	--
	-- SET TO 0: Positives ratchet, decay dies. The design document explicitly rejects
	-- decay-on-neglect as a trap that turns relationships into a collectible grind.
	-- Bonds only rise when you turn up; they never fall from absence. A relationship
	-- that survives is one you chose to maintain, not one the game forced you to.
	-- Safe range: -6 to 0. At 0 the bond is a collectible again -- which is the point.
	DecayPerYearAway = 0,

	-- Visits per person per year.
	--
	-- One, and this is the number that keeps the system from becoming a chore. Without a
	-- cap the optimal play is a lap of everybody you know every year, forever, which is
	-- a commute rather than a choice -- and the moment a game rewards a lap, players run
	-- laps and stop enjoying it. One visit each means the question is *who* you go and
	-- see this year, which is the question worth asking.
	--
	-- The same shape as five shifts and three lessons: a year holds a little of each of
	-- the things a life is made of, and none of them can be ground.
	-- Safe range: 1-3. Above 3 a year is mostly spent in conversation.
	VisitsPerYear = 1,

	-- How long what they say back stays on the row before it clears. Longer than a
	-- lesson's verdict, because this is the only writing in the game that is somebody
	-- talking to you rather than the game explaining itself, and it is worth the beat.
	-- Safe range: 2.5-8.
	ReplySeconds = 5,

	-- The odds a favour is turned down, at the exact moment it becomes askable.
	--
	-- Only offers authored as an `ask` roll at all -- see PersonOffer. Small talk is
	-- never refused, because being told no to "how have you been" is not a game.
	--
	-- The odds need no authored number because the offer already carries one. An ask
	-- appears the instant the bond reaches its minBond, so asking right then is asking
	-- somebody for something they have only just become willing to consider, and that
	-- is where a no belongs. The distance the bond has climbed *past* that figure is
	-- the whole of how safe it has become.
	--
	-- A coin flip at the floor. Higher and the ask may as well not have appeared yet;
	-- lower and there is no decision in waiting for a better year.
	-- Safe range: 0.25-0.7. At 0 nobody ever refuses and the system is off.
	RefuseAtFloor = 0.5,

	-- How far past an offer's minBond the odds take to fade to nothing.
	--
	-- A good visit is worth 3 to 5, so this is six or seven years of turning up every
	-- year -- and the asks that exist today all unlock at 45, which puts a certain yes
	-- at a bond of 70 out of 100. Long, deliberately. The ask is never locked, so the
	-- span is not a wait for permission; it is how long somebody takes to become the
	-- kind of person who does not have to think about it. That is the arc worth having,
	-- and it is what makes a bond legible without a number: the same sentence that was
	-- a coin flip at sixteen is simply true at twenty-three, and the player learns it
	-- by asking rather than by reading a stat.
	-- Safe range: 12-45. Below ~12 the gamble is over before it is noticed.
	RefuseFadeSpan = 25,

	-- What a refused ask still gives back, as a share of what taking it would have.
	--
	-- Not zero, and this is the number that keeps asking worth doing. A refusal
	-- already costs the visit, which at one visit a year is the whole year with that
	-- person. If it cost the bond as well, the year would end further from the thing
	-- than it started -- decay would eat the difference -- and the correct play would
	-- be to never ask at all, which deletes the mechanic rather than tensioning it.
	-- You turned up and you asked; you get the turning up.
	-- Safe range: 0.15-0.5. At 0 asking is strictly worse than small talk.
	RefusedBondShare = 0.3,

	-- How often the world is checked for a player standing near somebody. The same
	-- quarter-second as work and school, and for the same reason: it is the rate at
	-- which walking into a radius feels like arriving rather than like waiting.
	-- Safe range: 0.1-0.5.
	TickSeconds = 0.25,

	-- Where somebody stands, relative to the place point they live at.
	--
	-- Several people share a place -- a house has a mother and a father in it -- so they
	-- are set out around it on a ring rather than at it, and the bearings are how many
	-- spots on that ring are tried before giving up on fitting one more in. A person who
	-- cannot be fitted simply is not spawned, and the debug command says so: a mother
	-- standing inside a wall is worse than a mother who is out at the moment.
	-- Safe range: 4-12 and 6-16.
	StandStuds = 7,
	StandBearings = 10,

	-- How long after a life ends before the people are put back. Nothing to do with
	-- feel: it is a beat for the death screen to be read over an empty room rather than
	-- over four relatives standing about waiting to meet the next occupant.
	-- Safe range: 0.5-4.
	RespawnDelaySeconds = 1.5,

	-- How many years apart two people can be and still count as each other's age.
	--
	-- Not a rule about who may be talked to -- everybody may -- but the definition the
	-- game uses for "somebody you could build a life with", and so the thing `/town`
	-- counts and the thing dating will read. It exists as one number in one place
	-- because those two must never be able to disagree: a harness that says there are
	-- four people your age, next to a world where none of them can be asked out, is a
	-- bug report about the wrong system.
	--
	-- Three rather than the peer archetype's own spread of two, because a peer is not
	-- the only person who happens to be your age -- the older kid off your street and
	-- the youngest person at your office land here too, and they should. Wider and it
	-- stops meaning anything: at eighteen, a coworker two decades out would start being
	-- counted as a contemporary of yours.
	-- Safe range: 1-6. At 0 only somebody born the same year as you counts.
	PeerAgeGap = 3,

	-- Content limits, enforced at server start rather than found in play.
	--
	-- The offer count and the label length are Enact's, because this is Enact's panel and
	-- a fifth row is a menu whoever is asking. The gift ceiling is the only number here
	-- that is really a safety catch: an authoring slip of an extra zero on a
	-- parent's loan is not visible by reading the line, and it would quietly hand a
	-- nine-year-old more money than a year of adult work.
	-- Safe range: 500-5000.
	MaxOffers = Config.Enact.MaxChoices,
	MaxLabelLength = Config.Enact.MaxLabelLength,
	MaxGift = 2000,

	-- Walking with somebody: the "come with me" offer, and how the person who accepts
	-- it moves.
	--
	-- The whole mechanic is one visitor trailing the player at a fixed distance,
	-- re-aimed every tick at a point just behind them, so the person walks the exact
	-- path the player walks rather than cutting across it. These are the numbers that
	-- make that read as two people out together rather than as a queue or a chase.
	--
	-- Safe ranges: FollowBehindStuds 2-6, FollowTickSeconds 0.1-0.4, ArriveRadiusStuds
	-- 8-16, MaxWalkSeconds 90-600.
	Companion = {
		-- How far behind the player the companion aims for. Two studs is a queue, six
		-- is losing them; three is walking with somebody.
		FollowBehindStuds = 3,
		-- How often the follow target is re-aimed. The pocket-money chase re-aims on
		-- the same order of magnitude; slower reads as lag and faster is wasted work.
		FollowTickSeconds = 0.2,
		-- How close to the destination place point the walk counts as over.
		ArriveRadiusStuds = 12,
		-- The longest a walk may run, so a companion can never be followed for the
		-- rest of a life that never reaches the shop.
		MaxWalkSeconds = 240,
	},

	-- Bond milestones. When a bond crosses one of these thresholds the game fires
	-- a celebration and the person's offers change character. The numbers sit
	-- between MinBond and MaxBond and are checked in ascending order: the first
	-- one the current bond meets is the one that fires, and each threshold fires
	-- only once per life so the player gets the fanfare exactly once per rung.
	-- Safe range: integers between MinBond (-20) and MaxBond (100), ascending.
	BondMilestones = { 10, 25, 50, 75, 100 },

	-- NPC memory. The rolling buffer of interactions per person.
	-- Five is enough to feel like a history without being a novel the player
	-- will never read. Defining moment is one per person, written at the
	-- peak bond interaction.
	InteractionsPerPerson = 5,

	-- The odds that, when a person has a defining moment on record and no more
	-- specific contextual line beats it, they call it back instead of saying
	-- their flat ambient line. Not 1: a parent who recited the same memory
	-- word for word on every single visit would stop sounding like she
	-- remembered it and start sounding like the game replaying a save file.
	-- Safe range: 0.2-0.5. Below that it never surfaces; above it drowns out
	-- the ordinary contextual lines that give a person their everyday voice.
	MemoryCallbackChance = 0.35,

}

-- Places a person can be asked to walk to with you.
--
-- The world's destinations are parts in the Street, not numbers here -- this list is
-- not where a place lives, it is where an offer's `walksTo` is checked against at
-- load so a typo in content is caught on startup rather than showing the player an
-- offer that silently does nothing. It must never be the source a destination is
-- built from.
Config.Places = {
	Walkable = {
		"store",
		"school",
		"classroom",
		"home",
		"crossing",
		"gate",
		"work",
		"office",
		"gym",
		"library",
		"clinic",
		"bakery",
		"garage",
		"park",
		"home_1",
		"home_2",
		"home_3",
		"home_4",
		-- City. Sports and a spread of commercial spots so the new districts
		-- have people on the streets; a handful of suburb homes so companion
		-- walks reach the residential side of the map.
		"soccer_field",
		"basketball_court",
		"tennis_court",
		"playground",
		"running_track",
		"cafe",
		"restaurant",
		"supermarket",
		"bank",
		"cinema",
		"pharmacy",
		"suburb_1",
		"suburb_5",
		"suburb_10",
		"suburb_20",
		"suburb_30",
		"suburb_50",
		-- New districts: fade offices and north strip so companions can walk there.
		"fade_1",
		"north_shop_1",
		"auto_dealer",
	},
}

-- The town. Everybody in the world who is not one of the four people a life is made of.
--
-- Generated rather than authored, because "a lot of them" and "hand-written" are not
-- both possible, and because the thing that makes the four worth writing -- that they
-- are *your* mother, *your* friend -- is exactly what a stranger at the shop should not
-- have. What a stranger has instead is that they are there every time you go, and that
-- turning up is the only thing that ever changes them.
--
-- Generated *once, from a fixed seed, the same for everybody*, and that is the load-
-- bearing decision in this whole block. A bond is stored against a person id, so a
-- population re-rolled per server or per player would hand the friend you spent fifteen
-- years earning to a stranger with a different face. The town is a fact about the world;
-- the bond is the only part of it that is yours.
Config.Town = {
	-- The seed the whole population comes out of. Names, faces, ages, where they stand
	-- and what they have to say are all downstream of this one number.
	--
	-- CHANGING THIS RE-ROLLS EVERY TOWNSPERSON. Ids stay put, so nothing errors -- but
	-- every saved bond silently ends up against a different person, which is worse than
	-- an error because it looks like the save worked. Change it before there are saves
	-- worth keeping, or not at all.
	Seed = 20260802,

	-- How many of them there are. The number that decides whether the world reads as a
	-- place people live or as four rooms with relatives in them.
	--
	-- Not a performance figure -- PresenceStuds and MaxBodied are what bound the cost --
	-- so this is only "how big is the town". Enough that you cannot know everybody in one
	-- life, which is the point.
	--
	-- **Prefer a whole multiple of #PATTERN in Townsfolk.luau** (23, so 46 is two of them).
	-- This used to read "(17, so 34 is two of them)" and both numbers had gone stale:
	-- PATTERN grew to 23 entries and Count was never moved with it, so 34 was one full
	-- pass plus a partial one, `coworker` came out 1 man to 3 women, and Townsfolk threw
	-- at require time on the boot path -- which took the whole server down rather than
	-- producing a lopsided town. 46 is the only value in the safe range below that works:
	-- 23 is a whole pass but still fails, because an archetype that appears more than once
	-- inside one pattern lands on the same parity each time.
	-- Genders alternate by index and archetypes repeat every #PATTERN, so a whole number of
	-- passes gives every archetype an exact half-and-half split; a partial pass leaves the
	-- last few slots one-sided. Townsfolk checks this at load and errors if any archetype
	-- ends up more than one out, so a number that breaks it will say so rather than quietly
	-- producing a town where every peer is a man.
	-- Safe range: 8-60. Above ~60 the rings around the four places start refusing spots.
	Count = 46,

	-- Where townsfolk stand, relative to the place point they live at.
	--
	-- A wider ring than the family's, and further out on purpose. Your mother is in the
	-- room; the people at the shop are around the shop. It also has to hold many more
	-- bodies -- a bearing on a 16-stud ring is about 4 studs of arc, which is a person's
	-- width and a bit.
	-- Safe range: 10-26 and 12-36.
	StandStuds = 16,
	StandBearings = 24,

	-- How near the player has to be **to a townsperson** before that person is given a
	-- body at all.
	--
	-- Measured from the person, not from the place they belong to, and that is what lets
	-- them leave it. Somebody with no body is not nowhere: they have a position that goes
	-- on advancing along the paths while nobody is looking, so following one down a street
	-- keeps them in front of you and turning a corner into a stranger spawns them there.
	--
	-- The whole reason a town of this size is affordable. A rig is a yielding web call
	-- and there is no version of thirty of them at once that is not a stall on arrival,
	-- so a townsperson away across the map is a row in a table and nothing else. Set
	-- comfortably beyond the distance the dots are readable from, so nobody is ever seen
	-- arriving.
	-- Safe range: 60-250. Below about 60 they pop in while you are looking at them.
	PresenceStuds = 140,

	-- The hard ceiling on town rigs standing at once, whatever the radius lets through.
	--
	-- Belt and braces over PresenceStuds: two places tagged near each other would
	-- otherwise put the whole town in one frame. Nearest place first, so what gets
	-- dropped is always the furthest thing from the player.
	-- Safe range: 6-24.
	MaxBodied = 12,

	-- How often the world is re-checked for which places the player is near. Coarser
	-- than the people tick because crossing a 140-stud radius is not a precise moment
	-- and a rebuild is the expensive thing on the other side of it.
	-- Safe range: 0.5-4.
	PresenceTickSeconds = 1,

	-- A pause between two town rigs being built, so a walk into a busy place spreads its
	-- avatar calls over a second or so instead of firing a dozen at once. They arrive
	-- visibly one after another, which reads as people rather than as a spawn.
	-- Safe range: 0-0.5. At 0 they all arrive on the same frame.
	SpawnPaceSeconds = 0.12,

	-- Past this, a nameplate shows the name and no age.
	--
	-- A patch over a hole rather than a rule: nobody in AGES dies of old age yet, so a
	-- long life eventually stands next to a man the arithmetic says is a hundred and
	-- thirty. Showing nothing is the smallest honest thing to do about that until NPC
	-- mortality exists, and `/town` counts how many people are past it so the hole stays
	-- visible rather than becoming a feature.
	-- Safe range: 85-105.
	OldestShownAge = 96,

	-- How far from the place they belong to a townsperson wanders **when the world has no
	-- paths tagged**. The fallback, not the rule.
	--
	-- Bounded because a probed spot is wherever the floor happens to be: somebody given a
	-- hundred studs of open ground to aim at walks through the road, the flowerbed and the
	-- neighbour's garden with equal enthusiasm. Tag some AgesTownPoints and RangeStuds
	-- below takes over, which is a leash on a road network rather than on open country and
	-- can therefore be much longer.
	-- Safe range: 20-90.
	RoamStuds = 55,

	-- How far apart two route points can be and still be joined into one road.
	--
	-- This is the only thing deciding what "connected" means, so it wants to be a little
	-- more than the gap a builder naturally leaves between corners -- generous enough that
	-- a path tagged at reasonable intervals comes out as one network, tight enough that
	-- two points either side of a building are not treated as a road through it. `/town
	-- routes` reports how many disconnected pieces the current number produces, which is
	-- the way to tune it.
	--
	-- 70 rather than a rounder 60 because of the street the game actually ships with: its
	-- crossing is 65 studs from the school forecourt and 66 from outside the store, so 60
	-- cuts that town into three islands and 70 makes it one. Raising it further starts
	-- linking the school to the shop directly, which is a road through the houses.
	-- Safe range: 30-120.
	RouteLinkStuds = 70,

	-- How far from their own place a townsperson will ever get, once there are paths to
	-- walk on.
	--
	-- The number that decides whether this is a town or a set of four unrelated crowds.
	-- Long enough that a classmate can turn up near the shop and the streets between the
	-- buildings have somebody on them; short enough that the shop still has regulars and
	-- the school still has your year group. Not a performance figure -- PresenceStuds and
	-- MaxBodied bound the cost -- so this is purely about how far people's lives spread.
	-- Safe range: 80-500.
	RangeStuds = 250,

	-- How much further than PresenceStuds somebody has to get before their body is taken
	-- away again.
	--
	-- Hysteresis, and it is not optional. Spawn and despawn at one threshold means a
	-- player standing at exactly that distance builds and destroys a rig every tick
	-- forever -- and building a rig is a yielding web call, so it is the most expensive
	-- possible thing to do on a loop.
	-- Safe range: 1.05-1.4. At 1 it thrashes.
	DespawnSlack = 1.15,

	-- How far to step aside when two townsfolk arrive at the same corner at the same time.
	-- Only ever used at the moment a body is built, since two bodies walking is Roblox's
	-- problem rather than ours.
	-- Safe range: 2-6.
	NudgeStuds = 3,

	-- The shortest walk worth taking. Below this they are shuffling on the spot, which
	-- reads as indecision rather than as somebody going somewhere.
	-- Safe range: 8-25, and always less than RoamStuds.
	MinLegStuds = 14,

	-- How many legs a townsperson has already walked by the time you first exist.
	--
	-- Without this everybody begins life standing exactly on the point their place is
	-- tagged at, so the moment a life starts there is a huddle at your front door and
	-- another in the shop doorway. They disperse within a minute, which does not help --
	-- the first thing the player ever sees is the thing they remember, and a crowd that
	-- melts is more obviously a spawner than a crowd that stays.
	--
	-- Drawn from 0 to this, not fixed at it: some of them *should* still be near home,
	-- because some of them live there. At roughly a route link per leg, six is about four
	-- hundred studs of walking, which is further than the leash -- so the draw spreads
	-- people across the whole of their range rather than pushing them all to the edge of
	-- it.
	-- Safe range: 0-12. At 0 the huddle is back; above about 12 it costs a visible pause
	-- on the first rebuild of a life and buys nothing, since the leash has already bound
	-- where they can be.
	SettleLegs = 6,

	-- How long they stand still at the end of a walk, picked uniformly from this window.
	-- The pause is what makes it a person going about their day rather than a patrol: a
	-- town that never stops moving is a town of couriers.
	-- Safe range: 1-20, min below max.
	PauseMinSeconds = 3,
	PauseMaxSeconds = 11,

	-- A stroll, and slower than the visitor who came to your door because they are not
	-- going anywhere in particular. Also what makes them catchable -- a player at 16 has
	-- to be able to walk somebody down to talk to them.
	-- Safe range: 4-12, and always below the player's speed.
	WalkSpeed = 8,

	-- How many spots are tried before a leg is given up on and the pause simply runs
	-- again. Ground probes are cheap; a townsperson pinned in a corner is not, so the fan
	-- wants to be wide enough to find the one bearing out of an alcove.
	-- Safe range: 4-32.
	RoamAttempts = 14,
}

-- What each stretch of a bond is called, best first.
--
-- Read top-down, exactly like the work bands: the first band whose `atLeast` you meet
-- is the one you are in, and the bottom one is anchored to MinBond rather than to a
-- magic number that would silently stop covering the range if the floor moved.
--
-- `name` is a lowercase phrase that has to read correctly in the two places it is used:
-- on the HUD next to somebody's name ("Dad · close") and inside a sentence explaining
-- what a bond is not yet enough for ("Rae would have to be close to you first"). A
-- phrase that only fits one of those is the wrong phrase.
--
-- Deliberately no `raise` or any other number attached, unlike the work bands. What a
-- bond is worth is written on the pads it unlocks, one offer at a time, in content --
-- because "close" should mean your father will lend you rent, not that a hidden
-- multiplier moved.
Config.People.Bands = {
	{ atLeast = 70, name = "inseparable" },
	{ atLeast = 45, name = "close" },
	{ atLeast = 20, name = "friendly" },
	{ atLeast = 0, name = "on speaking terms" },
	{ atLeast = -8, name = "barely speaking" },
	-- The bottom of the range, kept for the relationships a life can actively ruin
	-- rather than merely drift away from. Reached only by a run of hostile offers on
	-- top of the ordinary decay -- becoming enemies is a choice, like becoming a
	-- friend is -- and reversible, because the repair offer gates on the same low
	-- territory.
	{ atLeast = Config.People.MinBond, name = "sworn enemies" },
}

-- What an ask's odds are called on the panel row, matched by the first `atLeast` the
-- refusal chance meets. Words rather than a percentage, for the same reason a bond is
-- a phrase: a figure invites arithmetic, and the player should be weighing whether to
-- risk their one visit this year, not computing it.
--
-- An ask safer than the last band here shows no note at all, and that silence is the
-- signal. A row that used to say "a long shot" and now says nothing is the game
-- telling the player their father came around, without ever showing them a number.
Config.People.RiskBands = {
	{ atLeast = 0.34, name = "a long shot" },
	{ atLeast = 0.01, name = "they might say no" },
}

-- Pointing the player at something worth walking to.
--
-- The world is the menu in this game, which is a good thing to believe right up
-- Crime, and the price of it.
--
-- The system is two halves and one number joins them: a crime *spends* heat and the
-- police are what heat *buys*. Nothing here is a punishment bolted onto a reward -- how
-- much you took is literally the difficulty setting for the next several minutes, which
-- is the only reason taking more is a decision rather than a preference.
--
-- The load-bearing idea in this whole block is that the police do not know where you
-- are. They know where you were *last seen*, and they search outward from it. Every
-- number below that looks like it is about difficulty is really about that one fact:
-- SearchRadiusStuds is how wrong they are allowed to be, SightStuds is how easily you
-- make them right again, and ContactSeconds is how long being wrong saves you. Tune
-- them together or not at all -- an officer who can see far enough to never lose you
-- turns the whole system into a chase you cannot win, which is a different game and a
-- worse one.
--
-- Deliberately no combat anywhere in here, and not because of the rating: if the police
-- could be fought then the answer to every pursuit is to turn around, and last known
-- position, dumping the goods and changing your coat all stop being decisions on the
-- same afternoon. Running has to be the only verb or none of the rest of it has teeth.
Config.Crime = {
	-- The heat number itself. Unbounded at the bottom by zero and capped here, because
	-- every tier below reads off this scale and a bounty that could run away past the
	-- top tier would be a fifth tier nobody wrote.
	-- Safe range: 100 only. Change the tiers instead -- this is the scale they are cut
	-- from, not a difficulty knob.
	MaxBounty = 100,

	-- How fast heat bleeds off, in points per second, once nobody has eyes on you.
	--
	-- Two and a half minutes from the cap to clean if you are never seen again. Long
	-- enough that a big score is genuinely an afternoon you have to survive rather than
	-- a corner to hide behind for twenty seconds; short enough that it is over inside one
	-- sitting. The whole of it is spent hiding, which is why the decay is the pacing of
	-- this system and not a formality.
	-- Safe range: 0.4-1.2. Above ~1.2 the top tier never gets to happen.
	DecayPerSecond = 0.65,

	-- Heat does not fall at all while any officer can see you, and this is how long after
	-- losing sight of you it stays frozen before the decay restarts. The pause is the
	-- thing that makes breaking line of sight feel like it did something *later* rather
	-- than instantly -- an officer who turns a corner has not given up, and a bounty that
	-- resumed cooling the same frame would say they had.
	-- Safe range: 3-12. Below ~3 there is no reason to hide rather than to keep running.
	CoolStartSeconds = 6,

	-- What the police can do at each level of heat, and the only place difficulty is
	-- written. Escalation here is by *changing the space* rather than by raising numbers:
	-- one officer who searches where you were is a different problem from four who spread
	-- out, and neither is the same problem with a bigger multiplier.
	--
	-- `officers` is a hard cap on bodies in the world, and it is a performance budget as
	-- much as a design one -- see PoliceService for the per-tick cost of one.
	-- `sightStuds` is how far an officer recognises you at, which is the real difficulty
	-- dial: it is how quickly a search turns back into a pursuit.
	-- `searchRadiusStuds` is how far from your last known position they are willing to
	-- spread. Bigger is harder, because standing still stops working.
	-- Safe range: 1-6 officers. Past ~6 the town reads as a cordon rather than a response.
	Tiers = {
		{ atLeast = 0, name = "clean", officers = 0, sightStuds = 0, searchRadiusStuds = 0 },
		{ atLeast = 15, name = "reported", officers = 1, sightStuds = 55, searchRadiusStuds = 40 },
		{ atLeast = 40, name = "wanted", officers = 2, sightStuds = 70, searchRadiusStuds = 70 },
		{ atLeast = 65, name = "manhunt", officers = 4, sightStuds = 85, searchRadiusStuds = 110 },
		{ atLeast = 88, name = "citywide", officers = 6, sightStuds = 100, searchRadiusStuds = 160 },
	},

	-- How long an officer has to stay within ArrestStuds of you before it is an arrest.
	--
	-- The single most important number for how this feels. An instant arrest on contact
	-- means one bad corner ends the afternoon and the player never learns what went
	-- wrong; three seconds means being caught is something you can see coming and
	-- sometimes escape, which is the difference between a fail state and a near miss.
	-- This is the soft-failure requirement for the chase half, and it is the whole of it.
	-- Safe range: 2-5. Below ~2 there is no near miss and above ~5 they never catch you.
	ContactSeconds = 3,
	-- Safe range: 6-14. Wider than a conversation because a humanoid closing on a moving
	-- target overshoots, and an arrest that needed a perfect stop would mostly not happen.
	ArrestStuds = 9,

	-- How fast an officer moves, against Config.NPC.WalkSpeed for an ordinary person.
	--
	-- Slightly *under* the player's run on purpose. A pursuer who is faster than you
	-- reduces every chase to how long the straight road is, and the interesting version
	-- of this is one you can outrun in the open but not out-corner -- so the officers buy
	-- their difficulty with numbers and knowing where you were, never with speed.
	-- Safe range: 14-19. At or above the player's speed the chase stops being winnable.
	OfficerWalkSpeed = 17,

	-- How often the pursuit re-reads the world. Separate from the decay tick because the
	-- two are asking different questions at different rates: where everyone is standing
	-- has to be fresh, and a number falling by half a point does not.
	-- Safe range: 0.15-0.4. Below ~0.15 the pathfinder is the bottleneck, not the tick.
	TickSeconds = 0.2,

	-- How stale a last known position may get before the officers stop believing it and
	-- start spreading out instead of converging. Without this they walk to a spot, stand
	-- on it and stay there, which reads as broken rather than as searching.
	-- Safe range: 5-15.
	SightingHoldSeconds = 9,

	-- Custody, in years off the life, by the tier you were caught at.
	--
	-- Years rather than months because a year is the game's own unit of time and the
	-- machinery for spending one already exists and already does the right things -- see
	-- LifeService.AgeUp and the note on skipChildhood. Writing months directly would skip
	-- the stat decay and the stage boundaries, which is the difference between a sentence
	-- costing you something and a sentence costing you a number.
	--
	-- Never served in real time. The player is not made to sit in a cell: idle time inside
	-- an activity is a bug by this project's own rules, and a jail you wait out is the
	-- purest possible form of it. The years are spent, the life moves on, and what is left
	-- behind is the record -- which is the actual sentence.
	-- Safe range: 1-4. Past ~4 a single bust ends a life's prospects outright.
	CustodyYearsByTier = { 0, 1, 1, 2, 3 },

	-- What a record does, once you have one.
	--
	-- Both of these are multipliers on difficulty rather than locks, which is the whole
	-- design of the consequence: a wall tells the player their save is ruined, a raised
	-- bar tells them to be better. It also makes the only interesting version of this
	-- character possible -- the one grinding stats to clear a bar everybody else walks
	-- under.
	Record = {
		-- Cameras and officers recognise a known face faster. Multiplies the rate at
		-- which being seen turns into heat.
		-- Safe range: 1.2-2.5.
		SuspicionMultiplier = 1.6,
		-- Every job's stat requirements go up by this fraction. Not a refusal: a
		-- requirement.
		-- Safe range: 0.1-0.4. Past ~0.4 the top jobs are unreachable rather than hard.
		HiringBarIncrease = 0.2,
	},

	-- The take. What you actually do to earn the heat above.
	--
	-- One verb: hold to empty the till. Everything interesting here is in the two
	-- rhythms you have to hold *between*, and the numbers below are chosen so that the
	-- two never settle into one pattern:
	--
	--   the clerk    turns to the register, then away to the shelves. A short cycle you
	--                can count, and the one you learn first.
	--   the camera   sweeps the room on its own clock, longer and slower, and it does
	--                not care where the clerk is looking.
	--
	-- The two periods are deliberately not multiples of each other. The gaps where
	-- neither is on the till therefore drift -- sometimes four seconds long, sometimes
	-- none at all -- and the skill of this activity is reading the alignment rather than
	-- counting to four. That is the whole design, and it is two numbers.
	--
	-- Being seen is never an arrest and never ends the robbery. It is heat and a
	-- sighting, which is to say it hands you straight to the half of the system that is
	-- already built. The soft failure is the point: a robbery that goes wrong should be
	-- the *beginning* of the interesting part of the afternoon.
	Theft = {
		-- What a full shop till holds, against the note above Config.Money: an adult
		-- hour of ordinary work is about twenty, and a first job is 2,400 a year. So a
		-- clean till is worth about a fortnight of legitimate wages -- plainly worth
		-- doing, and plainly not a career on its own.
		-- Safe range: 120-400. Past ~400 one shop is a year's wages and nothing else in
		-- the economy matters.
		TillFloat = 220,

		-- How fast it comes out while you are holding.
		--
		-- Set against the clerk's away window on purpose: one uninterrupted window is
		-- worth a little over half a till, so a full till *cannot* be taken in one go.
		-- The player has to either leave money in the drawer and walk, or stay for a
		-- second window and take the alignment they are given. That choice, made every
		-- few seconds, is the activity.
		-- Safe range: 15-40. At the value where one window empties a till the whole
		-- decision disappears.
		TakePerSecond = 26,

		-- How long a robbed till takes to be worth robbing again. Long enough that the
		-- answer to "I want more" is the next shop rather than this one, which is what
		-- makes a spree a walk across town with heat on you.
		-- Safe range: 180-600.
		RefillSeconds = 300,

		-- The clerk's cycle, in seconds: facing the till, then away from it.
		-- Safe range: 2-5 looking, 3-7 away. Away below ~3 leaves no window at all.
		ClerkLookSeconds = 3.2,
		ClerkAwaySeconds = 4.6,

		-- The camera's, which is one number because a sweep is one motion. The share of
		-- it spent pointed at the till is what makes the two rhythms interfere: 9 and
		-- 7.8 have a lowest common multiple of about a minute, so the pattern the player
		-- is reading takes a minute to repeat and never feels like a metronome.
		-- Safe range: 7-14 seconds, 0.25-0.5 on the till.
		CameraSweepSeconds = 9,
		CameraOnTillShare = 0.35,

		-- How close you have to be to have your hands in the drawer.
		-- Safe range: 6-10. This is a reach, not a room.
		ReachStuds = 8,

		-- The undo window. How long after an attention turns onto you before it counts
		-- as being seen -- which is to say, how long you have to let go.
		--
		-- The single most important number in this half of the system, the way
		-- ContactSeconds is in the other. It is what makes releasing a decision the
		-- player makes rather than a reaction they fail: half a second is enough to act
		-- on something you were watching for and nowhere near enough to bail on
		-- something you were not.
		-- Safe range: 0.3-0.9. Above ~0.9 you can hold through a whole glance.
		GraceSeconds = 0.5,

		-- What being caught with your hands in it costs, in heat. Roughly the first
		-- tier's threshold, so one bad window is one officer -- a consequence you can
		-- see walking toward you rather than a number you read.
		-- Safe range: 10-30.
		HeatOnSpotted = 18,

		-- And what it costs to keep holding after that. Per second, so a player who
		-- brazens it out climbs tiers rather than sitting at one -- which is the version
		-- of "go loud" this game can have without giving anybody a weapon.
		-- Safe range: 3-12.
		HeatPerSecondSpotted = 6,

		-- How often the take is re-read. The same rate as the pursuit, because the two
		-- are one activity from the player's side and a till that paid on a different
		-- beat from the officers arriving would feel like two games.
		-- Safe range: 0.1-0.3.
		TickSeconds = 0.2,
	},

	-- Being noticed, which until now was two different questions with two different
	-- answers and no name.
	--
	-- An officer used to see you the instant you crossed a distance line, and a passer-by
	-- used to need a flat 2.2 seconds regardless of anything about you. Neither asked the
	-- question the chase is actually built on: *how much do you stand out right now*. So
	-- the player had no lever between "wanted" and "not wanted" -- nothing to do with a
	-- street full of people except avoid it -- and the one number that should obviously
	-- have made you easier to spot, the bounty on your head, did nothing of the kind.
	--
	-- Now both observers accumulate the same `notice`, at a rate set by how conspicuous
	-- you are, and being spotted happens when it fills. That single change is what turns
	-- a set of range checks into a system with play in it, because every term below is a
	-- lever the player can move:
	--
	--   heat     the headline rule -- the more wanted you are, the faster anybody makes
	--            you. This is what stops a citywide manhunt feeling identical to a first
	--            report, without touching a single officer's stats.
	--   speed    sprinting past a crowd is louder than walking through it. This is the
	--            one term the player controls second to second, and it is the reason
	--            "keep your head down" is now a real instruction rather than flavour.
	--   colors   a gang bandana is meant to be legible across a street -- that is its
	--            whole job -- so wearing one while wanted has to cost something. It is
	--            also what Part 4 needs: being made in enemy territory is the trigger.
	--
	-- Notice resets the moment line of sight breaks, for both observers, and that is
	-- deliberate rather than an omission: it is what keeps breaking sight a *move* rather
	-- than a pause, which is the rule WitnessService was already built on and the one the
	-- whole hiding half of the chase rests on.
	Spotting = {
		-- What you are worth noticing at all, wanted or not, stood perfectly still with
		-- nothing on. The floor rather than the norm -- everything else adds to it.
		-- Safe range: 0.2-0.5. At 0 a clean player standing still is literally invisible,
		-- which reads as a broken officer rather than as good play.
		Base = 0.35,

		-- How much of the rate the bounty is worth, at full heat. The largest single term
		-- on purpose: "easier to spot with a higher bounty" is the rule this table exists
		-- to implement, and it should dominate the others rather than sit alongside them.
		-- Safe range: 0.4-0.9.
		HeatShare = 0.65,

		-- How much moving flat out is worth, against standing still.
		--
		-- Smaller than heat, and it has to be: if running were the dominant term then the
		-- correct play at every tier would be to walk everywhere, and a chase you win by
		-- strolling is not a chase. It is a discount for playing carefully, not a
		-- replacement for being uninteresting to the police.
		-- Safe range: 0.2-0.6.
		MovementShare = 0.4,

		-- What counts as flat out, in studs per second, for the term above. Anything at
		-- or past this is fully conspicuous; the scale is linear below it.
		-- Safe range: 16-24. Should sit at or near the player's actual run speed, or the
		-- term saturates before the player is really running and stops discriminating.
		RunSpeedStuds = 20,

		-- Wearing gang colors, flat. Not scaled by anything, because a bandana is either
		-- on your head or it is not, and the whole design of gang colors is that they are
		-- readable from across a street.
		-- Safe range: 0.15-0.5.
		ColorsBonus = 0.3,

		-- How much of the rate survives at the very edge of an observer's range.
		--
		-- Without a falloff, sightStuds is a hard line: one stud closer and you are made
		-- at full speed. With it, the edge of somebody's vision is a place you can be
		-- briefly and get away with, which is what makes distance a thing to manage
		-- rather than a boolean to be on the right side of.
		-- Safe range: 0.2-0.5. At 1 the falloff is switched off entirely.
		EdgeShare = 0.35,

		-- Seconds for a *trained* observer to make you at point-blank range with a
		-- conspicuousness of exactly 1. Officers only.
		--
		-- Short, because an officer who has to study you is an officer you can walk past,
		-- and the pursuit half of this system was never the part that needed slowing
		-- down. What this buys is the moment of grace that did not exist before: at low
		-- heat, moving slowly, at the edge of their vision, you are not made instantly --
		-- and that moment is the entire reason spotting is a system rather than a check.
		-- Safe range: 0.6-2. Above ~2 officers stop feeling like a threat at all.
		OfficerSeconds = 1.1,
	},

	-- The town, once it has your description.
	--
	-- The chase's second opponent, and the reason it exists is that without it the whole
	-- of being wanted is standing behind a wall for two and a half minutes waiting for
	-- DecayPerSecond to finish. That is the unskilled-dead-time bug this project keeps
	-- designing away, sitting in the middle of the best part of the system. Ordinary
	-- people recognising you turns hiding from a wait into a route: the empty back street
	-- is now genuinely better than the busy one, and that is a decision made continuously
	-- rather than once.
	--
	-- Only ever while the police have a description of you -- see Disguise below, which
	-- is the answer to this and the verb the chase was missing.
	Witness = {
		-- How far away an ordinary person recognises a face they have been told to look
		-- for. Deliberately shorter than every officer's sightStuds, including the
		-- lowest: a passer-by glancing up is not a trained search, and a crowd that saw
		-- further than the police would make the officers irrelevant.
		-- Safe range: 30-60. Above ~60 a busy street is impassable at any tier.
		SeeStuds = 45,

		-- How long a passer-by needs to place a face of conspicuousness exactly 1, stood
		-- right in front of them. No longer a flat hold: it is the denominator of the
		-- rate in Crime.Spotting, so a calm clean player takes several times this and a
		-- sprinting banded-up one takes well under it. Point-blank, too -- across the
		-- street it stretches by the falloff in EdgeShare.
		--
		-- Still the undo window, and still the same idea as the till's GraceSeconds:
		-- long enough that walking briskly past somebody is not automatically a report,
		-- short enough that loitering in a crowd is. It is also the time their reaction
		-- is on screen -- they stop and turn to face you the moment the notice starts
		-- filling -- so this doubles as how much warning the player gets.
		-- Safe range: 1.5-4. Below ~1.5 there is no warning, only a punishment.
		SeeSeconds = 2.2,

		-- What one report costs. Small on purpose: a witness is not a disaster, it is a
		-- reason to keep moving. What actually hurts is the sighting it carries, which
		-- drags the search back onto you.
		-- Safe range: 2-8.
		Heat = 4,

		-- How long before the same person will report you again. Without it, standing in
		-- front of one pedestrian is a heat firehose and the tier climbs on its own with
		-- nothing interesting having happened.
		-- Safe range: 12-40.
		CooldownSeconds = 20,
	},

	-- Changing your clothes, which is the chase's verb.
	--
	-- Everything above is something happening *to* the player. This is the one thing they
	-- can do about it, and it is deliberately powerful: it does not reduce the heat, it
	-- deletes the police's belief about where you are. Officers converging on a corner
	-- become officers searching a place you are not, and the town stops recognising you
	-- until an officer lays eyes on you again.
	--
	-- Powerful, and paid for in the only currency a chase has: you have to be somewhere
	-- specific, standing still, with nobody watching, for five seconds, while the search
	-- ring drifts. Getting there is the traversal this activity needs; standing there is
	-- the commit; walking off is the undo.
	Disguise = {
		-- How long you have to stand on the mark. The commit window, and the number that
		-- decides whether this is a decision or a formality: five seconds is long enough
		-- that starting it with an officer one street over is a genuine gamble.
		-- Safe range: 3-8. Below ~3 it is free; above ~8 nobody will ever risk it.
		ChangeSeconds = 5,

		-- How close to the mark counts as standing on it. Generous, because the player
		-- arrives here at a run and a rail that needed a precise stop would be a rail
		-- nobody uses under pressure.
		-- Safe range: 4-9.
		ReachStuds = 6,

		-- What a change of clothes costs. Priced against a small till float, so a spree
		-- pays for its own escapes and a player who is caught broke has to run instead.
		-- Not a lock: the heat still decays on its own, so being unable to afford this is
		-- a worse afternoon rather than a dead end.
		-- Safe range: 0-80. Above ~80 the escape costs more than the crime paid.
		Cost = 35,

		-- How often the mark re-reads who is standing on it and whether they are being
		-- watched. The same beat as the pursuit, because a change that completed on a
		-- different clock from the officer walking in would read as unfair.
		-- Safe range: 0.1-0.3.
		TickSeconds = 0.2,
	},

	-- The bank.
	--
	-- Deliberately not a bigger till, and this is the whole of the design. Escalation in this
	-- project is by changing the space rather than by raising numbers -- see the note on
	-- Tiers, which makes the same argument about officers -- and a vault that was a drawer
	-- with more in it would be the numbers-only version of an activity we already have.
	--
	-- So it asks the opposite question with the same input. A till is "do not be seen": you
	-- read two attentions and hold in the gap between them, and being spotted is the failure.
	-- A bank is "you *will* be seen": the alarm goes the moment you commit, before you have
	-- taken a penny, and the game is how long you are willing to stay. Nothing here is a
	-- stealth check. Everything here is a clock you are choosing to run down.
	--
	-- Three things at once instead of the till's two, and the third is the room itself. The
	-- vault is forty-odd studs from the alarm panel by the door, so silencing the alarm means
	-- leaving the money -- which is the traversal requirement met by the floor plan rather
	-- than by inventing a consumable to fetch. It is also the reason a second person is worth
	-- having and never required: two players never run, one player always does.
	Bank = {
		-- What is in the vault, against a small shop's whole float of 220. Six or seven
		-- tills, which is what makes this the afternoon rather than a stop on the way
		-- through one -- and it has to be, because the heat it buys cannot be walked off in
		-- the time a corner store's can.
		-- Safe range: 900-2200. Below ~900 nobody would take the alarm for it.
		VaultFloat = 1400,

		-- How fast it comes out once the door is moving. Twenty-five seconds for the whole
		-- vault, which is four times the till's window and is meant to be: the number the
		-- player is really deciding is how much of those twenty-five seconds they can afford,
		-- and every second of it is a second the officers are closer.
		-- Safe range: 40-80. Above ~80 the alarm never gets to matter.
		TakePerSecond = 55,

		-- How long a robbed vault takes to be worth robbing again. Long, because a bank you
		-- could go back to in five minutes would make the whole town's four tills pointless.
		-- Safe range: 600-1800.
		RefillSeconds = 900,

		-- What tripping the alarm costs the instant you touch the door, before any money.
		-- Straight past the first rung onto the second: two officers are dispatched by the
		-- act of starting, which is the promise the activity makes up front.
		-- Safe range: 20-45. Below ~20 the opening is not the commitment it should be.
		HeatOnTrip = 30,

		-- How long after being silenced before the alarm arms itself again.
		--
		-- The metronome the whole room is played against, and it is set so that a solo player
		-- can just about hold the pattern together: a round trip to the panel is roughly six
		-- seconds of running and holding, so twelve seconds means about a third of a solo
		-- robbery is spent not at the vault. Two players spend none of it.
		-- Safe range: 8-20. Below ~8 solo is impossible; above ~20 the panel is scenery.
		RearmSeconds = 12,

		-- What the alarm costs per second while it is ringing. On top of a live fix on your
		-- position -- see BankService -- which is the part that actually hurts: ringing means
		-- the officers converge on you, and silenced means they are searching a building.
		-- Safe range: 3-9.
		HeatPerSecondRinging = 5,

		-- How long you have to hold the panel to silence it. Short, because the cost of the
		-- trip is the trip; making the hold long as well would just be the same tax twice.
		-- Safe range: 1-3.
		SilenceSeconds = 2,

		-- How close counts as being at the vault door or at the panel. The same reach as a
		-- till drawer, because it is the same gesture and two different numbers for "you are
		-- close enough to touch this" would be two things for the player to learn.
		-- Safe range: 6-10.
		ReachStuds = 8,

		-- The guard.
		--
		-- The reason the alarm is not a clean twelve-second beat you can count. He walks a
		-- patrol, and when he sees somebody at the vault he re-arms the panel there and then
		-- -- which is the whole of what he does. He never touches the player, never blocks a
		-- door and never ends anything: he is a non-combat opponent whose only weapon is
		-- ruining your timing, and reading his patrol is the same skill as reading a clerk's
		-- shoulders. Continuity with the till is the point.
		--
		-- How far he recognises somebody at the vault. Set against the floor plan rather
		-- than against a feeling: from the door end of his patrol the vault is forty studs
		-- away, so thirty means there is a stretch of his walk during which he genuinely
		-- cannot see it. That stretch is the window, and it is the difference between a
		-- guard who is an obstacle and a guard who is a rhythm.
		-- Safe range: 20-38. At 40+ the window closes and the panel becomes unusable.
		GuardSeeStuds = 30,

		-- How old the guard is. Here rather than left to NPCService's default, which picks
		-- an age near the player's -- a fine rule for a stranger in the street and the wrong
		-- one for a man employed to stand in a bank, because it would put a nine-year-old on
		-- the door for a nine-year-old robber.
		-- Safe range: 25-55.
		GuardAgeYears = 34,

		-- How long his loop takes end to end. Deliberately not a multiple of RearmSeconds,
		-- for the reason the clerk and the camera are not multiples of each other: the
		-- interference is the thing worth reading.
		-- Safe range: 12-30.
		GuardPatrolSeconds = 17,

		-- How long he stops and looks at you after catching you, before resuming his walk.
		--
		-- Not a cooldown and not a punishment -- the alarm has already gone by then. It is
		-- there so the player can see *who* ruined their timing: an alarm that re-armed
		-- while a man carried on strolling past would read as the twelve-second clock being
		-- broken rather than as somebody having spotted them.
		-- Safe range: 1.5-4. Below ~1.5 the stop is not visible from across the room.
		GuardNoticeSeconds = 2.5,

		-- How often the room is re-read. The same beat as the pursuit and the take, because
		-- from the player's side this is one activity and a vault that paid on a different
		-- clock from the officers arriving would feel like two games.
		-- Safe range: 0.1-0.3.
		TickSeconds = 0.2,
	},
}

-- Who you run with.
--
-- The crime systems above are all solitary: one player, one drawer, one alarm, one
-- pursuit. This is the layer that makes a second person mean something, and the
-- design problem it has to solve is that the standard version of this feature is a
-- name tag, a chat channel, and a number that goes up when you commit crimes -- which
-- is the idle payout pad wearing a jacket.
--
-- Two things stop it being that, and both are rules borrowed from elsewhere in the
-- tree rather than invented here:
--
-- **Standing is earned, rank is given.** `Ties.luau` argues that friendship cannot be a
-- bond threshold, because then "everybody you were reliably nice to would become your
-- friend on some birthday you were not paying attention on, and the game would be
-- telling you about your own life after the fact". A rank that auto-promotes at 500
-- points has exactly that defect. So standing accrues quietly and the *rung* is only
-- ever conferred face to face, off a panel, by the person who runs the gang.
--
-- **The colors are worn.** Joining puts a bright band on your head, one color to a
-- gang, readable across a street. That is what makes a mixed room of players and NPCs
-- legible at a glance -- and it is also a liability, because the same band is what a
-- witness describes. The bandana is an identity and a tell at once, and the whole
-- feature leans on that being true in both directions.
Config.Gangs = {
	-- The four rungs, and the ladder is deliberately short for the reason Ties.luau
	-- keeps three: a ladder with eleven grades on it has quietly replaced a
	-- relationship with a progress bar.
	--
	-- `standing` is what the rung costs to be *offered*. Reaching it is necessary and
	-- never sufficient -- the boss still has to hand it to you.
	--
	-- Read in order and the last one reached wins, so these must stay ascending.
	--
	-- The labels carry their own article -- "a hand", not "hand" -- because three of the
	-- four take one and the fourth does not, and a caller that wrote `You are a {label}`
	-- would say "You are a who calls it". Putting the article in the content is what lets
	-- every line that says a rung out loud be written the same way.
	Ranks = {
		-- Rung zero has no entry here: not being in a gang is the absence of a rank,
		-- not a rank called "nobody", and giving it a row would put it on nameplates.

		-- You are around. Nobody has asked you to do anything, and your cut is whatever
		-- you were standing close enough to pick up.
		{ id = "hanger_on", label = "a hanger-on", standing = 0 },
		-- You get handed one job and told what to hold. The first rung that is worth
		-- anything, because it is the first one where somebody else's plan has a slot
		-- with your name in it.
		{ id = "hand", label = "a hand", standing = 120 },
		-- You pick your own role, and you can bring one person. The rung where the game
		-- stops telling you where to stand.
		{ id = "name", label = "a name", standing = 400 },
		-- You choose the job, the crew, and who holds what.
		--
		-- Capped at one gang, which is the same device `closest` uses in Ties.luau and
		-- is here for the same reason: it is the first gang decision that costs
		-- something. Running the east side means not running the west side.
		{ id = "caller", label = "who calls it", standing = 1000, oneGangOnly = true },
	},

	-- What standing a piece of work is worth.
	--
	-- The user's rule is that anything helping the gang counts, so this is deliberately
	-- broad rather than a bank-robbery counter. The numbers are ratios first and
	-- absolutes second: a till is a chore, a vault is an event, and getting clear
	-- afterwards is worth more than either because it is the part players skip.
	Earn = {
		-- Per unit of money taken from a till or a vault. Small on purpose -- money is
		-- already its own reward, and paying standing per dollar as well would make the
		-- richest route the only route.
		-- Safe range: 0.01-0.06.
		PerMoneyStolen = 0.02,

		-- Flat, once, for tripping a vault. The bank is the set piece and it should read
		-- as one on the ladder too.
		-- Safe range: 20-80.
		VaultOpened = 45,

		-- Flat, for coming down from a real bounty to nothing without being arrested.
		-- The largest single award in the table, because escaping is the only line here
		-- that cannot be farmed by standing still and holding a button.
		-- Safe range: 40-140.
		GotAway = 90,

		-- The bounty you must have actually reached for GotAway to pay. Stops a player
		-- collecting an escape award for the two points a witness gave them.
		-- Safe range: 25-80.
		GotAwayNeedsBounty = 40,

		-- Per second spent inside a room where somebody else's alarm is ringing.
		--
		-- This is the one that makes a second person worth having. BankService already
		-- charges heat to everybody in the room rather than to whoever tripped it, so
		-- standing on the panel while a gang-mate empties the vault is heat you took
		-- that was not yours -- and that is precisely the thing a gang should reward.
		-- Safe range: 1-6.
		PerSecondSharedHeat = 3,
	},

	-- What it costs.
	--
	-- Failure has to be worth playing, so these are real rather than decorative -- but
	-- none of them can take a rung away. A rung was conferred in a moment by a person,
	-- and quietly deleting it later is the exact "telling you about your own life after
	-- the fact" that the offer model exists to prevent. Standing falls; the rung holds.
	Lose = {
		-- Standing lost on arrest. Being caught is not a betrayal, it is an occupational
		-- hazard, so this is a setback and not a purge.
		-- Safe range: 60-200.
		OnArrest = 120,

		-- Standing lost for leaving a room while its alarm was ringing and somebody else
		-- was still holding the vault. This is the betrayal, and it is the only entry
		-- here that is about another person rather than about the police.
		-- Safe range: 100-300.
		OnBailing = 180,

		-- The floor. Standing never goes below this, so a bad night cannot cost a player
		-- a rung's worth of history they earned weeks ago.
		-- Safe range: 0-50.
		Floor = 0,
	},

	-- Part 2: who runs with you. Slots, not a cost -- reaching the rung is the cost, the
	-- same way reaching a rung is the only price a promotion ever has, and recruiting is
	-- something the boss does for you rather than something bought off a menu.
	Crew = {
		-- Total crew slots at each rung, keyed by GangRankDef.id. "hanger-on" and "hand"
		-- are deliberately absent rather than zero: GangService.crewSlotsFor treats a
		-- missing rung as zero, and leaving them out says the same thing the spec does --
		-- those two rungs are where somebody else's plan has a slot with your name in it,
		-- not the other way round.
		-- Safe range: 1-2 for "name", 2-4 for "caller".
		SlotsByRank = {
			name = 1,
			caller = 3,
		},

		-- Where a new recruit's nerve starts. Low: they have not done anything with you
		-- yet, and a recruit who started confident would make the meter a formality
		-- rather than something earned.
		-- Safe range: 10-30.
		NerveStart = 20,

		-- The ceiling. Never lowered, never spent -- see GangCrewMember.nerve.
		NerveMax = 100,

		-- Nerve gained per point of standing credited while this crew exists, split
		-- across every member rather than multiplied by their count. A three-person crew
		-- does not make the same job worth three times the steadying; it is still one
		-- job.
		-- Safe range: 0.05-0.2.
		NerveGainPerPoint = 0.1,
	},

	-- Part 3: sending that crew on a job, rather than doing every job yourself. The bank's
	-- alarm control is the whole role table for now -- one seat, filled by you or by them --
	-- because it is the one control in the game that was already a shared, room-level thing
	-- rather than a per-player one, which is what makes handing it to somebody else legible.
	Jobs = {
		-- The chance a called crew member simply fails to make the alarm go quiet, once per
		-- time it rings, rolled at the low and high end of nerve and lerped between. This is
		-- the "badly" in the spec's "NPC crew execute them, badly if their nerve is low" --
		-- a fresh recruit (Crew.NerveStart, 20) is still wrong more often than not, so
		-- sending one on a bank on day one is a real gamble, not a formality with a body
		-- attached to it.
		-- Safe range: 0.5-0.9.
		AlarmFailChanceAtZeroNerve = 0.75,
		-- Never zero -- a maxed-out crew member is reliable, not a second silence button
		-- that never misses.
		-- Safe range: 0.02-0.15.
		AlarmFailChanceAtMaxNerve = 0.05,

		-- A till has no seat to hand off -- the clerk and the camera are the whole
		-- activity and stay the player's to read, on purpose (see TheftService's header).
		-- What a lookout can do instead is soften getting caught, not prevent it: the
		-- *first* time a robbery is spotted this session, one roll against their nerve
		-- decides whether that one HeatOnSpotted hit lands or gets waived. Being spotted
		-- still happens, the notice still says so, and the ongoing per-second heat while
		-- you keep holding through it is untouched -- staying spotted is still on you.
		-- Same fail-chance shape as the alarm, same reason: a fresh recruit misses this
		-- more often than not.
		-- Safe range: 0.5-0.9.
		TillCoverFailChanceAtZeroNerve = 0.75,
		-- Safe range: 0.02-0.15.
		TillCoverFailChanceAtMaxNerve = 0.05,
	},

	-- The head covering.
	--
	-- Sized in studs against an unscaled R15 head, then scaled with the head it sits on,
	-- so it fits a nine-year-old and a grown adult without a second set of numbers.
	Bandana = {
		-- How far the band sticks out past the head on each axis. Small: this is a band
		-- around a head, not a helmet, and a value large enough to read as headgear from
		-- across a street is also large enough to clip through a hair accessory.
		-- Safe range: 0.05-0.25.
		Swell = 0.12,

		-- How tall the band is, and how far above the head's center it sits. Together
		-- these put it across the forehead rather than over the eyes or on the crown.
		-- Safe range: Height 0.3-0.8, Lift 0.1-0.45.
		Height = 0.52,
		Lift = 0.26,

		-- How much of the color is emitted rather than lit. The point of the band is to
		-- be identifiable at a distance in any weather and at night, and a purely
		-- diffuse band goes grey at dusk exactly when a gang most needs to be counted.
		-- Not 1: a fully neon head reads as a powerup, not as clothing.
		-- Safe range: 0.25-0.7.
		Glow = 0.45,
	},

	-- How much easier the colors make you to describe.
	--
	-- Multiplies heat from anything that saw you while you were wearing them, on top of
	-- the record multiplier BountyService already applies. This is the liability half of
	-- the bandana and it is what makes taking it off a real decision rather than a
	-- cosmetic one.
	-- Safe range: 1.1-1.8. At 1 the colors are free and the choice disappears.
	ColorsSuspicion = 1.35,

	-- How long you must be out of a gang before another will take you.
	--
	-- Not a punishment -- it is here so that "which gang" is a decision with a cost
	-- rather than a menu a player reopens whenever a rival's job looks better. In game
	-- seconds, real time.
	-- Safe range: 60-600.
	RejoinSeconds = 180,

	-- How old the four bosses are.
	--
	-- Here for the same reason the bank guard's age is: NPCService otherwise picks an age
	-- near the player's, which is right for a stranger in the street and wrong for somebody
	-- who runs a gang -- it would put a nine-year-old in charge of the east side for a
	-- nine-year-old player, and the one thing a boss has to read as is somebody older than
	-- you who was already here.
	-- Safe range: 28-60.
	BossAgeYears = 41,

	-- How often membership is re-read: colors re-applied after a respawn, standing
	-- pushed to the client, escapes noticed. Slower than the crime tick because nothing
	-- here is a reaction time.
	-- Safe range: 0.4-1.5.
	TickSeconds = 0.5,
}

-- The map the player reads: the minimap in the corner and the full sheet behind it.
--
-- The map has no extent written down here. It is measured from the place points that
-- exist, so a city that grows draws a bigger map with nothing edited -- the same reason
-- Territory has no region bounds. tools/world_plan.py owns the world's real numbers and
-- nothing in Config transcribes them.
Config.Map = {
	-- How far past the outermost place point the drawn map extends, in studs. Place
	-- points sit at doorways, so an unpadded map is cropped exactly at the last building
	-- and the world reads as ending at its own front step.
	-- Safe range: 40-200.
	EdgePadStuds = 90,

	-- How many real place points must exist before the measured bounds are trusted and
	-- cached. Place points are tagged instances that stream in, so a bounds taken from
	-- the first three that happen to be loaded would pin a map the size of one street
	-- for the life of the server. Below this the bounds are recomputed next time.
	-- Safe range: 8-40.
	MinPlacesForBounds = 12,

	-- How much of the world the minimap shows, as a radius in studs from the player.
	-- Small enough that the icons on it are the ones you could walk to in the next
	-- minute; the full sheet is where you plan anything longer.
	-- Safe range: 120-500.
	MinimapRadiusStuds = 260,

	-- How often the minimap re-reads the player's position and redraws, in seconds.
	-- This is a camera-follow rather than a state push, so it wants to be smooth rather
	-- than cheap -- but it is still redrawing icons, so it is not every frame.
	-- Safe range: 0.03-0.2.
	MinimapRefreshSeconds = 0.06,

	-- The side of the square the full map is drawn in, as a fraction of the shorter
	-- screen axis. Under 1 so the sheet never touches the screen edges.
	-- Safe range: 0.6-0.95.
	SheetScreenFraction = 0.82,

	-- How wide to assume the map sheet is, in pixels, before Roblox has laid it out.
	--
	-- Only the terrain cull reads it: it decides which world rectangles are too small to
	-- be worth an instance, and it needs a pixel size at the moment the server pushes map
	-- data -- which is before the sheet has ever been shown, so `AbsoluteSize` is zero.
	-- Being wrong here costs a few hundred extra or missing hairline rectangles, not a
	-- broken map, so a sensible middle is better than a lazy first-open rebuild.
	-- Safe range: 400-1200.
	SheetAssumedPixels = 700,

	-- How far in the sheet can be zoomed, and by how much per wheel click or button
	-- press.
	--
	-- **Zoom is what makes the "main spots only" rule affordable.** This world has
	-- several hundred place points and drawing all of them at once is a sheet nobody can
	-- read -- but dropping the rest permanently would mean the map could not answer
	-- "where is the nearest cafe", which is most of what a map is for. So the sheet shows
	-- the landmarks at rest and hands the rest back as you zoom in. Nothing is hidden;
	-- it is filed.
	-- Safe range: 3-8 for the ceiling, 1.15-1.6 for the step. A step under about 1.15
	-- takes too many clicks to cross the range and starts feeling broken.
	MaxZoom = 5,
	ZoomStep = 1.3,
	-- How long a zoom takes to land. Short: this is a direct manipulation, and anything
	-- a player is holding a wheel down to do must not queue up behind its own animation.
	-- Safe range: 0.06-0.2.
	ZoomSeconds = 0.12,

	-- The zoom a place has to be at before it is drawn, and before its name is printed
	-- beside it, by tier. Every rule in `Icons.Rules` names one of these three.
	--
	-- A name costs far more room than a dot does, so every label threshold sits above its
	-- own dot threshold: a place appears first, and tells you what it is when there is
	-- space to say so.
	-- Safe range: 1 for landmark (it must be the resting picture), then increasing.
	DetailZoom = {
		-- The dozen or so places that are the reason to open a map at all: the bank, the
		-- school, the hospital, the park, your own front door.
		landmark = 1,
		-- The rest of the named world -- offices, cafes, the gym, a marina.
		district = 1.8,
		-- Every generated address. Hundreds of them, and only worth drawing once the
		-- player has zoomed far enough in that a street is what they are looking at.
		street = 2.8,
	},
	LabelZoom = {
		landmark = 1,
		district = 2.4,
		street = 3.6,
	},

	-- The graticule: one line every this many studs, in both axes.
	--
	-- Without it the sheet is dots on a void and the zoom has nothing to move against --
	-- a player zooming into an empty patch cannot tell that anything happened. A grid
	-- that scales with the zoom is the cheapest possible answer to both.
	-- Safe range: 100-400. Under 100 it is a texture rather than a grid.
	GridStuds = 200,

	-- How many points across a strip are probed to find where the side changes.
	--
	-- This is a *search* width, not a drawing resolution, and it does not put a step in
	-- the picture: a probe only says "the boundary is somewhere between these two", and
	-- the exact crossing is then bisected to well under a pixel. So this only has to be
	-- fine enough that no side is ever entirely skipped over between two probes -- a side
	-- narrower than one probe spacing at some latitude would be missed.
	-- Safe range: 24-72. Four sides on a world this size need nowhere near the top of it.
	RegionSampleCells = 44,

	-- How many horizontal strips the fill is cut into.
	--
	-- **This is the only place a staircase can still show, so it is much finer than the
	-- column count above.** A side is a Voronoi cell and a Frame is a rectangle, so the
	-- fill has to be built out of strips; the *ends* of each strip are solved for exactly
	-- (see `buildRegions`), which leaves the strip height as the one remaining step. At
	-- 44 that step is a visible ledge the moment anybody zooms in -- which was the whole
	-- complaint about the old mosaic, reproduced at a quarter of the frame count.
	--
	-- Cost is roughly this many Frames times the number of sides a row crosses, so
	-- doubling it doubles the build, and the build happens once when the overlay is first
	-- switched on.
	-- Safe range: 120-320. Below about 100 the ledges come back.
	RegionRows = 220,

	-- How opaque the region wash is. It sits under the icons and must never compete
	-- with them -- it is an answer to "whose side is that", not a layer to read.
	-- Safe range: 0.55-0.9.
	RegionTransparency = 0.72,

	-- The full sheet draws the same sampling as two layers rather than one, and this is
	-- the pair of numbers that separates them.
	--
	-- **A flat mosaic is not a territory map.** Colouring every sampled cell at one
	-- transparency -- which is what this did first -- gives four large blurry stains with
	-- a visible grid in them, and the thing a player actually wants off a territory map
	-- is the *line*: where does one side stop. So the fill is taken almost all the way
	-- out, and the cells that have a different owner next to them are drawn again, bright
	-- and opaque, as a border. Same sampling, same correctness, a picture with edges in
	-- it.
	-- Safe range: 0.8-0.94 fill, 0-0.3 border. The gap between them is the whole effect.
	RegionFillTransparency = 0.88,
	RegionBorderTransparency = 0.1,
	-- How thick that border is drawn, in pixels at rest. It is drawn in offset so it
	-- stays one line thick at every zoom -- a border that thickened as you zoomed in
	-- would swallow the region it was outlining.
	-- Safe range: 1-4.
	RegionBorderPixels = 2,

	-- How the drawn world is toned before it goes on the sheet.
	--
	-- `src/shared/world/MapShapes.luau` carries every shape in the colour the world
	-- actually paints it, and dropping those on the sheet raw was the first version: it
	-- looks like somebody pasted a screenshot into the menu. Bright green lawns and white
	-- roofs against a near-black panel out-shout the icons, the territory lines and the
	-- you-marker -- which are the things the map is *for*. The picture is the background
	-- and has to behave like one.
	--
	-- Two knobs, applied in this order:
	--
	-- `Saturation` is how much of the colour's own hue survives. At 0 the world is
	-- greyscale, which reads as a printed street map; at 1 it is the world's own palette.
	-- In between you keep "grass is greener than asphalt" while losing "grass is loud".
	--
	-- `Tint` is how far the result then sits from the panel behind it. At 0 a shape is
	-- invisible; at 1 it is at full strength. This is the contrast dial.
	--
	-- Buildings sit above ground on both, so that the blocks read as raised out of the
	-- streets between them without needing an outline on nine hundred Frames.
	-- Safe range: 0.2-0.7 for saturation, 0.35-0.8 for tint. Push tint past about 0.8 and
	-- the icons stop winning.
	Shapes = {
		SurfaceSaturation = 0.4,
		SurfaceTint = 0.5,
		BuildingSaturation = 0.45,
		BuildingTint = 0.62,

		-- Shapes below this many pixels on their short side are skipped at build time
		-- rather than drawn. Not a look setting -- a Frame under a pixel wide costs
		-- exactly as much as one that can be seen. This is measured at the resting zoom,
		-- so anything dropped was never visible without zooming in.
		-- Safe range: 0-1.5. At 0 nothing is skipped.
		MinPixels = 0.6,
	},

	-- What each kind of place draws as, and how a place id is sorted into a kind.
	--
	-- Matched by prefix, in order, first hit wins -- so the longer, more specific rules
	-- must come before the shorter ones. Prefix rather than an exact list because most
	-- place ids in this world are generated: gen_city.py emits apt_3, office_7, rise_2,
	-- fade_5, est_haulage and a dozen suburb_n, so an exhaustive table would be stale the
	-- next time the city is regenerated with one more block in it.
	--
	-- Anything matching nothing draws as `Default`, which is the honest outcome for a
	-- place this table has not been taught about: a plain dot that is still findable and
	-- still labelled, rather than an invisible one or a crash. A map is the wrong place
	-- to be strict -- a missing category should cost the player a colour, not a marker.
	Icons = {
		Default = { color = Color3.fromRGB(176, 182, 196), size = 5, priority = 0 },

		-- Ordered longest-prefix-first where two could both match.
		--
		-- `tier` is *when* it is drawn, not what it is -- see `DetailZoom`. A landmark is a
		-- place a player would name if you asked them where they were headed; a street is a
		-- generated address that only matters once you are already looking at that street.
		-- Getting this wrong in the generous direction is what turns the sheet back into
		-- the wall of dots it was, so there is no default: `StyleFor` errors on a rule with
		-- no tier rather than guessing one.
		Rules = {
			-- Where you live. The one icon a player looks for to orient themselves, so it
			-- is the largest and warmest thing on the sheet that is not a boss.
			{ prefix = "home", kind = "home", tier = "landmark" },
			{ prefix = "suburb_", kind = "home", tier = "street" },
			{ prefix = "apt_", kind = "home", tier = "street" },

			-- Money and civic business.
			{ prefix = "bank", kind = "civic", tier = "landmark" },
			{ prefix = "town_hall", kind = "civic", tier = "landmark" },
			{ prefix = "school", kind = "civic", tier = "landmark" },
			{ prefix = "library", kind = "civic", tier = "landmark" },
			{ prefix = "hospital", kind = "civic", tier = "landmark" },
			{ prefix = "police", kind = "civic", tier = "landmark" },

			-- Places that pay. The works district and every generated industrial estate
			-- unit, which between them are most of the east of the map.
			{ prefix = "works_", kind = "work", tier = "district" },
			{ prefix = "est_", kind = "work", tier = "street" },
			{ prefix = "office_", kind = "work", tier = "street" },
			{ prefix = "factory", kind = "work", tier = "district" },
			{ prefix = "freight_depot", kind = "work", tier = "district" },
			{ prefix = "timber_mill", kind = "work", tier = "district" },
			{ prefix = "power_plant", kind = "work", tier = "district" },
			{ prefix = "scrapyard", kind = "work", tier = "district" },
			{ prefix = "auto_dealer", kind = "work", tier = "district" },

			-- Somewhere to be that is not work or home.
			{ prefix = "cinema", kind = "leisure", tier = "landmark" },
			{ prefix = "city_park", kind = "leisure", tier = "landmark" },
			{ prefix = "park", kind = "leisure", tier = "district" },
			{ prefix = "gym", kind = "leisure", tier = "district" },
			{ prefix = "cafe", kind = "leisure", tier = "district" },
			{ prefix = "mall_entrance", kind = "leisure", tier = "landmark" },
			{ prefix = "marina", kind = "leisure", tier = "district" },
			{ prefix = "baywalk", kind = "leisure", tier = "district" },
			{ prefix = "circus_", kind = "leisure", tier = "district" },
		},

		-- Size is a radius in pixels on the full sheet; the minimap scales these down by
		-- MinimapIconScale. Priority decides who draws on top when two icons land in the
		-- same few pixels, which on a city this dense is most of them.
		Kinds = {
			home = { color = Color3.fromRGB(245, 205, 120), size = 7, priority = 40 },
			civic = { color = Color3.fromRGB(126, 196, 244), size = 6, priority = 30 },
			work = { color = Color3.fromRGB(150, 210, 158), size = 5, priority = 20 },
			leisure = { color = Color3.fromRGB(226, 158, 226), size = 5, priority = 10 },
		},

		-- How much smaller an icon is on the minimap than on the sheet. The minimap is
		-- about a quarter the width and the icons cannot shrink by the same factor or
		-- they stop being clickable targets, so this is deliberately gentler than the
		-- size ratio between the two surfaces.
		-- Safe range: 0.5-0.9.
		MinimapIconScale = 0.7,
	},

	-- The player's own marker, on both surfaces. Bright, and the one thing on the map
	-- drawn in a colour nothing else is allowed to use -- Config.Guide.Color is gold and
	-- the gang bands own cyan, orange, magenta and lime, so this is none of those.
	YouColor = Color3.fromRGB(96, 250, 140),
	YouSizePixels = 9,
}

-- Whose side of the map you are standing on.
--
-- Gangs.luau has carried a `side` field read by nothing since it was written, waiting
-- for "the map expansion". This is that expansion. The four sides stop being a label on
-- a boss and become a partition of the ground.
--
-- **There are no bounds in this table, on purpose.** A region is "the ground closer to
-- this boss than to any other boss" -- nearest-of-four, measured from the boss place
-- points themselves. Authoring four rectangles here would have meant four more numbers
-- to re-derive by hand every time the world regenerates or a boss moves, and this
-- tree's most repeated defect is exactly that: one measurement written down twice.
-- Nearest-boss cannot drift, covers the whole map with no gaps and no overlaps by
-- construction, and needs no maintenance when the city grows.
Config.Territory = {
	-- How often a player's position is re-tested against the four sides. This decides
	-- how quickly crossing a line is noticed and nothing else -- no reaction time hangs
	-- off it, so it is slow. Matched to Gangs.TickSeconds because both are asking a
	-- question about the same membership.
	-- Safe range: 0.4-2.
	TickSeconds = 0.5,

	-- How far past the line you must be before a crossing counts, in studs. Without it
	-- a player walking the boundary would trip a crossing every tick, and every notice
	-- the system can send would fire in a loop for as long as they stood there.
	-- Hysteresis rather than a cooldown: the band is a place, so the fix belongs in
	-- space rather than in time.
	-- Safe range: 8-40.
	EdgeBandStuds = 18,

	-- What running the line pays, and what it costs.
	--
	-- **Nothing here pays for time.** Config.Gangs.Earn says of GotAway that it is the
	-- largest award in that table "because escaping is the only line here that cannot be
	-- farmed by standing still and holding a button", and that is the law this block is
	-- written against. Depth is the only thing measured: how far into somebody else's
	-- side you actually walked. Standing still adds nothing at any point, because the
	-- award is a maximum over positions and never a sum over seconds.
	Incursion = {
		-- Standing with your own gang per stud of the deepest point you reached inside a
		-- rival side, paid once when you come back out. Small per stud because the
		-- distances are hundreds: crossing a side at its middle is worth a few hundred
		-- studs of depth.
		-- Safe range: 0.05-0.4.
		PerStudDepth = 0.15,

		-- The most one incursion can pay, whatever the depth. The map's long axis is over
		-- 1600 studs, and without a ceiling a single walk corner to corner would outpay a
		-- bank vault -- which would make the ladder a hiking trail.
		-- Safe range: 40-160.
		MaxAward = 80,

		-- How deep you must go before it pays at all. Stops a player farming the boundary
		-- by stepping over it and back: a crossing has to be a trip into their side, not a
		-- toe over the line.
		-- Safe range: 40-160.
		MinDepthStuds = 90,

		-- Standing lost with the gang whose side you walked onto, charged once on entry
		-- while wearing another gang's colors. This is the price and it is a real one:
		-- standing gates what that gang will ever offer you, so running their line often
		-- enough is how you make sure they never take you. Choosing a side by wearing it
		-- where it is not welcome is the whole point.
		-- Safe range: 10-60.
		RivalCost = 25,
	},
}

-- until the player cannot find the menu. A shop that hires at sixteen is no use to
-- someone who never learned the shop was there, and "walk around until you find it"
-- is not discovery, it is a search. This draws the line from where you are to the
-- thing that just opened up.
--
-- Read by the client, which is what draws it. The server only decides where to
-- point and when to stop.
Config.Guide = {
	-- A punchier, more saturated amber than the old pale gold -- the same family
	-- as a choice marker so it keeps meaning "this is for you, go to it", but
	-- bright enough to read against grass, asphalt and every skybox this game
	-- ships rather than washing out against anything light.
	Color = Color3.fromRGB(255, 176, 34),

	-- Every wing gets a dark rim: a slightly larger, slightly lower backing part
	-- in near-black behind the bright one. This is the standard "bright core,
	-- dark outline" wayfinding trick -- it is what keeps a white or gold arrow
	-- legible in Immortals Fenyx Rising's path regardless of what ground color it
	-- crosses -- and it is why the arrow reads as a solid marker instead of a
	-- neon smear the instant it crosses pale stone or sand.
	OutlineColor = Color3.fromRGB(18, 14, 8),
	-- How much larger the outline is than the wing it backs, added on every side.
	-- Safe range: 0.03-0.12. Below ~0.03 the rim is too thin to read at a glance;
	-- above 0.12 it starts to swallow the bright core it is supposed to frame.
	ArrowOutlineMarginStuds = 0.06,
	-- How far below the wing (along the ground normal) the outline sits, so the
	-- bright top face is never fully covered by its own rim.
	-- Safe range: 0.02-0.08.
	ArrowOutlineDropStuds = 0.035,
	-- The outline's own rest transparency. Not neon and not animated by the flow
	-- wave -- it stays close to solid so the rim it draws never itself washes out,
	-- only fading in step with the wing it backs at the path's edges.
	-- Safe range: 0.0-0.3.
	OutlineTransparency = 0.12,

	-- Each arrow is two thin neon bars meeting in a "V", built from vectors rather
	-- than a texture -- there is still no Roblox group to upload a chevron image
	-- to, and a shape built from two boxes needs no asset at all. The angle is
	-- measured from the direction of travel to each bar, so a wide angle reads as
	-- a shallow, open chevron and a narrow one reads as a sharp arrowhead.
	-- Bolder and flatter than the first pass: thicker bars read as a solid
	-- painted mark instead of a wire, and a lower profile keeps them from casting
	-- odd shadows or clipping the camera on a shallow slope.
	-- Safe range: length 0.9-2.2, thickness 0.12-0.3, height 0.06-0.2, angle 20-50.
	ArrowWingLengthStuds = 1.6,
	ArrowWingThicknessStuds = 0.28,
	ArrowWingHeightStuds = 0.07,
	ArrowWingAngleDegrees = 32,

	-- Centre-to-centre gap between one arrow and the next along the path.
	-- Safe range: 3-10. Below ~3 the chevrons blur into a solid stripe; above 10
	-- the path reads as scattered dashes rather than a direction.
	ArrowSpacingStuds = 5,

	-- Hard cap on how many arrows exist at once. Built once in Guide.new() and
	-- only ever repositioned or hidden, never recreated -- a path longer than
	-- MaxArrows * ArrowSpacingStuds spaces its arrows further apart instead of
	-- growing the pool, so a cross-map guide never costs more than a next-door one.
	-- Safe range: 20-60.
	MaxArrows = 36,

	-- How high above the real ground each arrow floats, along the ground's own
	-- normal so it stays flush on a slope rather than only a flat floor. Just
	-- enough to clear a kerb or a paving seam without visibly hovering.
	-- Safe range: 0.15-0.6.
	ArrowLiftStuds = 0.35,

	-- The stretch at each end of the path where arrows fade out instead of
	-- stopping dead: nearest the player, so the path does not look welded to your
	-- feet, and nearest the destination, so it does not look stabbed into the
	-- doorway.
	-- Safe range: 4-15.
	ArrowEdgeFadeStuds = 8,

	-- The travelling brightness wave that makes the path feel like it is flowing
	-- toward the destination rather than just sitting there. FlowSpeedStuds is how
	-- fast the bright band moves along the path; FlowWaveLengthStuds is the
	-- distance from one bright band to the next; the two transparency values are
	-- what an arrow fades between at rest and at the peak of the wave passing
	-- through it. FlowPeakColor is what the wing's own Color lerps toward at the
	-- peak of the wave -- a near-white flash rather than only a brightness change,
	-- so the flow reads as energy passing through gold rather than gold merely
	-- dimming and brightening.
	-- Safe range: speed 4-16, wavelength 8-25, rest 0.55-0.8, peak 0.05-0.25.
	FlowSpeedStuds = 12,
	FlowWaveLengthStuds = 12,
	FlowRestTransparency = 0.6,
	FlowPeakTransparency = 0.05,
	FlowPeakColor = Color3.fromRGB(255, 244, 214),

	-- How high off the ground the destination anchor sits, before the waypoint's
	-- own separate lift (WAYPOINT_LIFT_STUDS in Guide.luau) stacks on top of it.
	-- Only needs to clear the exact floor point now that the path itself hugs the
	-- real ground instead of running to an artificial height.
	-- Safe range: 0-3.
	LiftAtTargetStuds = 1,

	-- How often the client re-walks the path: re-raycasts every arrow's ground
	-- height and repositions the pool. The flow animation above updates every
	-- frame regardless of this -- this interval is about the shape of the path,
	-- which only changes as fast as the player walks.
	-- Safe range: 0.1-1.
	RefreshSeconds = 0.25,

	-- How often the road-following route itself is recomputed against the navmesh --
	-- a separate, much coarser interval than RefreshSeconds above, because asking
	-- PathfindingService for a route is real work and the corners it finds do not
	-- move just because the player took another step. The leg nearest the player is
	-- re-anchored to their live position every RefreshSeconds regardless of this, so
	-- the path never visibly lags behind their feet even between recomputes.
	-- Safe range: 0.75-4.
	RouteRefreshSeconds = 1.5,

	-- Close enough to count as arrived, at which point the path would be pointing
	-- at the ground under your own feet. The label stays up -- you still want to
	-- know what you are standing in front of -- but the arrows go.
	-- Safe range: 8-40. Wants to be at or above Work.StationRadiusStuds so the
	-- path clears once you are inside the workplace rather than at the doorway.
	ArrivedRadiusStuds = 26,
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

	-- The game's one palette.
	--
	-- **These are the lobby's colours, and that is the point.** A player meets this game in
	-- the lobby -- a warm near-black with a single gold standing on it -- and thirty seconds
	-- later they are in a town opening a menu. If that menu is cold blue-grey with a
	-- different white in it, the two places read as two products, and the seam between them
	-- is exactly where somebody decides whether the thing they are in was made by one hand.
	--
	-- Warm and low-saturation on purpose. This is a life sim and the register it wants is
	-- lived-in, not clinical. The saturation budget is spent on the things that carry
	-- meaning -- a gang's colour, a bar that is filling, a refusal -- and nowhere else: a
	-- surface bright enough to compete with a warning has taken the warning's job.
	--
	-- `Config.Lobby.Menu.Palette` is this same identity written a second time for the
	-- lobby's own two files. The two must agree; when the lobby is next opened it should be
	-- folded into this one.
	Palette = {
		-- The ground, and the three steps up from it. `Panel` is the sheet, `PanelDeep` is
		-- the bottom of its gradient, `Row` is a card at rest and `RowHover` is one under
		-- the cursor. Four values rather than two because a panel with a single flat fill in
		-- it has no depth to hang a hierarchy on, and every list on it then reads as one
		-- undifferentiated block.
		Panel = Color3.fromRGB(18, 18, 22),
		PanelDeep = Color3.fromRGB(13, 13, 16),
		Row = Color3.fromRGB(30, 30, 36),
		RowHover = Color3.fromRGB(44, 44, 52),
		-- A row that is present and cannot be acted on. Darker than `Row`, so it recedes
		-- rather than looking like a card that failed to load.
		RowLocked = Color3.fromRGB(24, 24, 28),
		-- Hairlines, strokes and scroll bars. Never a fill.
		Edge = Color3.fromRGB(62, 60, 72),

		Text = Color3.fromRGB(240, 236, 228),
		Muted = Color3.fromRGB(148, 144, 156),

		-- The one warm colour and the game's signature, carried over from the lobby title.
		Accent = Color3.fromRGB(225, 200, 150),
		AccentDeep = Color3.fromRGB(198, 158, 92),
		-- Dark text on an accent fill.
		Ink = Color3.fromRGB(24, 20, 14),

		-- A refusal, a debt, a thing that is going wrong. The only red on the screen.
		Warn = Color3.fromRGB(214, 126, 116),
		-- Open, paid, owned, earned. The only green.
		Good = Color3.fromRGB(126, 198, 148),

		-- The wash behind an open panel, and how far through it the world still shows.
		-- Not opaque: the point of a menu that does not take the whole screen is that the
		-- town is still there behind it, and a backdrop dark enough to hide the town would
		-- have made the panel full-screen by another route.
		-- Safe range: 0.15-0.6.
		Backdrop = Color3.fromRGB(6, 6, 9),
		BackdropTransparency = 0.35,
	},

	-- The menu: a rail of tiles down the left edge, and a panel that opens beside it.
	--
	-- The rail is always on screen and the panel is not, which is the whole shape of
	-- the thing. A menu you have to remember a key for is a menu most players never
	-- open, and every pane behind this one answers a question a player has while they
	-- are standing in the street -- what work is going, who is worth calling, what am
	-- I actually good at. Those want a thing to click, not a shortcut to learn.
	Menu = {
		-- The rail's tiles. Square, so this is both dimensions.
		-- Safe range: 34-56.
		RailTilePixels = 46,
		-- The gap between tiles, and the rail's inset from the left edge.
		-- Safe range: 4-12.
		RailGapPixels = 7,
		-- Safe range: 8-24.
		RailInsetPixels = 14,
		-- The padding inside the rail's own backing plate, which is what turns seven
		-- separate tiles into one object sitting on the screen.
		-- Safe range: 0-10.
		RailPadPixels = 6,
		-- The icon drawn inside a tile. Smaller than the tile by enough that the tile
		-- still reads as a target rather than as a frame around a picture.
		-- Safe range: 16-30, and never above `RailTilePixels - 8`.
		RailIconPixels = 24,

		-- The panel's *ceiling*, not its height. The panel is as tall as the pane it is
		-- showing and no taller; this is the point past which it stops growing and the
		-- list starts scrolling instead.
		--
		-- It was a flat fraction first, and that was the single worst thing about the
		-- panel: five rows of money inside a sheet claiming three quarters of the screen
		-- reads as a page that failed to finish loading, and the eye goes to the empty two
		-- thirds rather than to the five rows. Deliberately not the whole screen either --
		-- the map sheet is the full-screen surface, and a second one would take away the
		-- one thing that makes the map feel like it takes over.
		-- Safe range: 0.6-0.9.
		PanelHeightFraction = 0.76,
		-- And the floor, so a one-row pane is still a panel rather than a strip. Below
		-- about this a surface stops reading as a surface and starts reading as a tooltip
		-- that got out of hand.
		-- Safe range: 200-320, and never above `PanelHeightFraction` of a phone screen.
		PanelMinHeightPixels = 260,
		-- Safe range: 0.4-0.75.
		PanelWidthFraction = 0.56,
		-- And the pixels that fraction is clamped between.
		--
		-- A fraction on its own is wrong at both ends of the range of screens this game
		-- runs on: 56% of a phone held sideways is too narrow for a row with a figure
		-- column, and 56% of an ultrawide is a panel you have to move your head to read.
		-- Safe range: 380-460 min, 640-820 max, and min must stay below max.
		PanelMinWidthPixels = 420,
		PanelMaxWidthPixels = 720,

		-- The header strip: the player card, and the title bar under it.
		-- Safe range: 68-100 and 26-44.
		HeaderPixels = 86,
		TitleBarPixels = 34,
		-- One list row, and the gap between two.
		-- Safe range: 44-64 and 4-10.
		RowPixels = 54,
		RowGapPixels = 6,

		-- How the menu moves.
		--
		-- **Three curves, and everything here is one of them.** In on `Back.Out`, out on
		-- `Quad.In`, and the out is faster than the in -- a player closing a menu has
		-- already decided and is waiting on the animation, whereas a player opening one is
		-- being shown something. Most UI that feels unjuicy is the right curves played too
		-- slowly; nothing in this table is above a third of a second.
		Motion = {
			-- The panel arriving: how far it travels from the rail, and how long it takes.
			-- Nothing is gated on it finishing -- the panel is clickable from frame one.
			-- Safe range: 0-48 pixels, 0.1-0.35 seconds. Zero on either is an instant menu.
			EnterPixels = 26,
			EnterSeconds = 0.22,
			-- Leaving. Kept under the entrance on purpose; see above.
			-- Safe range: 0.06-0.2.
			ExitSeconds = 0.14,

			-- How long between one row landing and the next, and how far each rises.
			--
			-- The stagger is the difference between a list being dealt and a block
			-- appearing. It is small because the longest pane here can be forty rows:
			-- multiply this by the row count and keep the total under about a third of a
			-- second, or a big relationships list becomes a wait.
			-- Safe range: 0-0.05 stagger, 0-24 pixels. Zero on the stagger lands them together.
			RowStaggerSeconds = 0.022,
			RowRiseSeconds = 0.26,
			RowRisePixels = 14,
			-- The most rows that are allowed to stagger at all. Past this they all land on
			-- the last offset, so a forty-row pane costs the same wait as a ten-row one.
			-- Safe range: 6-20.
			RowStaggerLimit = 12,

			-- A row under the cursor: how much its coloured spine grows at each end, and how
			-- long the colour takes to get there. Tiny and fast -- this is feedback that the
			-- thing is live, not an animation worth watching, and above about 0.2 seconds it
			-- lags behind a player running down a list.
			--
			-- **The spine grows; the row does not slide.** Sliding the row sideways was the
			-- first version and it is wrong in a list: the spines make one vertical line down
			-- the left edge of the pane, and pushing a single row out of that line breaks the
			-- alignment of the two rows either side of it. The hover then draws the eye to the
			-- seam rather than to the row.
			-- Safe range: 0-10 pixels, 0.05-0.2 seconds.
			HoverSpinePixels = 5,
			HoverSeconds = 0.12,

			-- The squash a rail tile does when it is pressed: how far past its own size it
			-- goes, and the two halves of the bounce. This is the whole of the menu's
			-- click feel and it happens before the panel has drawn anything, which is the
			-- point -- the press is acknowledged in under a tenth of a second regardless of
			-- what the pane behind it costs to build.
			-- Safe range: 1.0-1.25, 0.05-0.12, 0.08-0.18.
			PressScale = 1.14,
			PressOutSeconds = 0.07,
			PressBackSeconds = 0.12,

			-- How far the world behind the panel is blurred, and how long the blur takes to
			-- arrive. The one place in this game allowed to blur the screen: a backdrop
			-- behind a menu is a depth cue, whereas a blur during play is a fault.
			-- Safe range: 0-28. Zero turns it off entirely.
			BlurSize = 16,
			BlurSeconds = 0.2,
		},

		-- The order the rail draws in, and the pane each tile opens.
		--
		-- `id` is also the icon: `MenuIcons` draws a shape per id and errors on one it has
		-- never heard of, so a tab added here without a picture behind it is a boot failure
		-- naming the tab rather than a blank square in the rail. Same rule as the pane
		-- switch in `MenuUI`, for the same reason.
		--
		-- `color` is what that pane is worth on screen: the tile's icon, the stripe down the
		-- left of its rows, and its title. Every one of them is desaturated against what it
		-- would be on a white background, because they sit on a near-black panel and a
		-- fully-saturated hue on this ground is a hue that glows.
		Tabs = {
			{ id = "jobs", label = "Jobs Available", color = Color3.fromRGB(132, 186, 232) },
			-- Second because it is the pane a player opens most often after work, and
			-- because it is the one that used to be four rows stacked on the HUD: what a
			-- house cost, what a bill wants and what is in the bank are facts you go and
			-- look up, not things you need in your eyeline while you are walking.
			{ id = "money", label = "Money", color = Color3.fromRGB(225, 200, 150) },
			{ id = "relationships", label = "Relationships", color = Color3.fromRGB(226, 150, 172) },
			{ id = "gangs", label = "Gangs", color = Color3.fromRGB(224, 124, 96) },
			{ id = "skills", label = "Skills", color = Color3.fromRGB(126, 198, 148) },
			-- The last two are the housekeeping pair, and they sit at the bottom because
			-- nothing about the life being played is behind them. A player opens the five
			-- above during a life and these two either once, or when something has gone
			-- wrong -- which is exactly the ordering the rail should teach.
			{ id = "codes", label = "Codes", color = Color3.fromRGB(178, 158, 220) },
			{ id = "settings", label = "Settings", color = Color3.fromRGB(150, 146, 158) },
		},
	},
}

Config.Death = {
	-- Natural mortality only rolls once age >= RampStartAge.
	-- ChancePerYear = min(MaxChancePerYear, BaseChancePerYear * (age - RampStartAge) ^ Exponent)
	RampStartAge = 65,
	BaseChancePerYear = 0.01,
	Exponent = 1.6,
	MaxChancePerYear = 0.6,

	-- How long the death screen holds before the player is sent back to the lobby.
	--
	-- A ceiling rather than a wait: the screen has a "Back to the menu" button on it, and
	-- most players will press it. This is what happens for the ones who do not, so that a
	-- death is never a screen somebody is stuck looking at.
	-- Safe range: 3-15. Long enough to read the summary, short enough that it doesn't feel
	-- like a punishment.
	RespawnDelaySeconds = 5,
}

Config.Verdict = {
	-- Under this age, a life gets no ribbon and the death screen stays blank.
	-- Childhood deaths and early deaths are honest rather than forced into a
	-- category they did not earn.
	-- Safe range: 14-18. Sixteen matches the age the working life begins.
	MinAge = 16,
}

-- The chapter spine. A life is six bands of ages, and a "months passed" reel is
-- shown at every band boundary the player has lived up to, suppressed when the
-- shared "what happened" query returns no moments for the window.
--
-- The bands are a player-experience decision, not a calendar one. They sit on
-- the design's own age-of-decision splits: ages 0-5 carry the ambient-event
-- toy years, age 6 onwards turns the year over to events without aging, age 15
-- opens the working life, age 20 is where the long adult band begins. The
-- bands are wide enough to span 5-10 minutes each at walking pace; the last
-- adult band is the widest because the verbs accumulate there.
--
-- `ChapterBands` is read by `LifeService` to decide when to fire a break and
-- where to age the life to on continue. `ChapterMinAge` and `ChapterMaxAge`
-- are derived from the first and last entries, kept here so a service does not
-- have to walk the table every tick to find them.
Config.Life = {
	-- Each entry is `{ fromAge, toAge }` inclusive on both ends. Adjacent bands
	-- share no ages — a 5 year old is in band 2, not band 1 — and the union of
	-- all bands is the whole of a life. Adding a band is an edit here and nothing
	-- else.
	ChapterBands = {
		{ 0, 4 },
		{ 5, 9 },
		{ 10, 14 },
		{ 15, 19 },
		{ 20, 39 },
		{ 40, 80 },
	},
}

-- The menu a life is chosen in, before it starts running.
--
-- The load-bearing idea, and the reason this is not just a cosmetic screen: **the world
-- is stopped while it is open.** A profile with no `setup` is a life that has not begun,
-- and the age-up clock reads that before it banks a second. Without it the menu would be
-- a thing the player has to beat, and the first thing AGES ever asked them to do would be
-- to hurry.
Config.Slots = {
	-- How many lives a player can keep at once.
	--
	-- Three because the menu has to show them all at a glance -- a slot you have to scroll
	-- to is a slot you forget you own -- and because two reads as "your life and a spare"
	-- while three reads as a choice about how you want to play.
	--
	-- **Raising this is safe at any time.** Every load runs `Lives.Reconcile` over the slot
	-- list and appends empty lives up to this number, so an existing save simply gains the
	-- new slots. **Lowering it is not**: slots past the new count stop being reachable and
	-- the lives in them become invisible rather than deleted. Nothing in the code prevents
	-- it, because the honest fix is a migration that asks the player which to keep, and that
	-- is a feature rather than a guard.
	-- Safe range: 1-6 going up. Do not go down on a build that has shipped.
	Count = 3,

	-- How long the delete confirmation stays armed, in seconds.
	--
	-- Deleting a life is the only irreversible thing in this game that is not dying, so it
	-- takes two presses -- and the arming lapses rather than sticking, so a player who armed
	-- it and walked away does not come back to a menu one stray click from erasing a life.
	-- Safe range: 3-15. Below ~3 the second press becomes a race.
	DeleteConfirmSeconds = 6,
}

-- The lobby: a second Roblox *place*, not a screen inside this one.
--
-- The player joins the lobby first, stands on a composed stage as their real Roblox
-- avatar, picks a life, and is teleported into the game place. That split was the user's
-- call -- "it would make life much easier for later updates" -- and it is the right one for
-- a reason worth writing down: the game place is thirteen per-player tick loops, a streamed
-- town and a house full of props, none of which have any business existing while somebody
-- is reading a menu. A menu drawn over a running world has to *suppress* all of that and
-- keep suppressing it as the world grows. A menu in its own place never has to.
--
-- The cost of the split is the handoff, and it is real: the two places share one
-- ProfileStore session lock, so the lobby has to let go of the profile before the game
-- place can pick it up. See LobbyService for how that is sequenced and what it means for
-- how long Play takes.
Config.Lobby = {
	-- **Both must be filled in before either place works, and they are the one pair of
	-- numbers in this codebase that cannot be derived or defaulted.** A Roblox place id
	-- only exists once the place has been published, so there is no honest value to ship:
	-- zero means "not published yet", and every path that would use one says so by name
	-- rather than failing at a web call.
	--
	-- To fill them in: publish the lobby as the *start place* of the experience and the
	-- game as a second place under it, then read both ids off the Creator Dashboard.
	-- GamePlaceId is where Play sends you; LobbyPlaceId is where the game place sends you
	-- back to.
	GamePlaceId = 0,
	LobbyPlaceId = 0,

	-- How long the lobby waits for a profile before it gives up on the Play button.
	--
	-- Longer than the game place's equivalent wait on purpose. Arriving at the lobby is the
	-- *first* thing that happens to a player, so nothing is competing for the datastore and
	-- a slow load here is a cold start rather than a contended lock -- but it is also the
	-- one load with nothing behind it to fall back on, so waiting is strictly better than
	-- refusing. Safe range: 10-60.
	ProfileWaitSeconds = 30,

	-- How long a Play press stays "in flight" before the lobby will accept another one.
	--
	-- `TeleportAsync` is a yielding web call, and a player who presses Play twice would
	-- otherwise fire two of them. This is not a cooldown on pressing Play -- it is the
	-- window in which the *first* press is still being answered. A failed teleport clears
	-- it immediately, so this number is only ever reached when Roblox itself has gone quiet.
	-- Safe range: 10-60.
	TeleportTimeoutSeconds = 20,

	-- How many times a failed teleport is retried, and how long between tries.
	--
	-- Teleports fail for reasons that pass on their own -- rate limits, a place still
	-- starting up -- so a single failure is not news worth showing the player. Retried
	-- silently; only the last failure is ever reported, and it is reported.
	-- Safe range: 0-5 tries, 1-10 seconds.
	TeleportRetries = 3,
	TeleportRetrySeconds = 2,

	-- The stage the avatar stands on. All of it is measured from the mark the character
	-- stands on, which is the origin of the composition -- see `content/Stage.luau` for why
	-- nothing here is an absolute world position.
	Stage = {
		-- Where the first stage sits in the world.
		--
		-- **The world origin, and that is not arbitrary.** An earlier version put the set 200
		-- studs up to keep the void out of shot -- which the backdrop and the fog already do --
		-- and it created a real problem in exchange: (0, 0, 0) is where Roblox puts a character
		-- when there is no SpawnLocation yet, so the one spot a character can accidentally
		-- appear was two hundred studs from the only floor in the place. Standing the set on
		-- the origin means that accident lands on the disc instead of in the void.
		Origin = Vector3.new(0, 0, 0),

		-- How far apart two players' stages are built, in studs along X.
		--
		-- **Every player in the lobby gets their own stage, and this is why.** The screen is
		-- one composed shot of *your* avatar; a shared stage would put every other player in
		-- the lobby standing inside you on the mark. The alternatives are worse in both
		-- directions -- separate marks around one stage means everyone else walks through
		-- your shot, and hiding other characters means a client-side transparency loop that
		-- is wrong for one frame every time somebody joins.
		--
		-- Must comfortably exceed the backdrop width (220 studs) or a neighbour's scenery
		-- appears past the edge of yours. Twenty-odd anchored parts per player is nothing.
		-- Safe range: 300-1000.
		Spacing = 400,

		-- Where the camera sits relative to the mark, and what it looks at relative to the
		-- mark. Behind-right and slightly above, aimed at chest height rather than at the
		-- feet: a camera level with the mark looks up somebody's nose, and one aimed at
		-- head height leaves them standing on the bottom edge of the screen.
		-- Safe range: 9-20 studs back, 3-8 up.
		CameraOffset = Vector3.new(6.5, 4.2, 12),
		CameraLookAt = Vector3.new(0, 3, 0),

		-- The slow drift, so the screen is never a still image. Degrees of orbit either side
		-- of the framing above, and seconds for one full there-and-back.
		--
		-- Small and slow on purpose: this has to sit behind a menu somebody is reading. A
		-- drift wide enough to notice as movement is wide enough to be motion sickness by
		-- the third life. Safe range: 0-6 degrees, 20-90 seconds. Zero holds it still.
		DriftDegrees = 2.5,
		DriftSeconds = 44,
	},

	-- What the menu drawn over that stage looks like.
	--
	-- **One palette, in one place, because the two files that draw the lobby meet at a seam
	-- the player can see.** Pressing "Create a life" swaps the slot list for the setup card in
	-- the same column, in place, with no transition between them -- so a colour that differed
	-- by six points between `LobbyUI` and `SetupCard` would read as two different games
	-- stitched together at the exact moment the player is deciding whether to trust this one.
	-- Both files used to carry their own copy with a comment on each apologising for it; this
	-- is that comment made structural.
	--
	-- Colours are `Color3.fromRGB`. There is no safe range for a colour, but there is a rule:
	-- `Text` on `Panel` and `Ink` on `Accent` are the two pairs that carry every word on the
	-- screen, and both must stay far enough apart to read on a phone in daylight.
	Menu = {
		Palette = {
			-- The dark ground everything sits on, and the two steps up from it. `Row` is a
			-- card at rest, `RowHover` is one under the cursor.
			Panel = Color3.fromRGB(18, 18, 22),
			Row = Color3.fromRGB(30, 30, 36),
			RowHover = Color3.fromRGB(44, 44, 52),
			-- A row that exists but cannot be pressed -- a locked era. Darker than `Row`, so it
			-- reads as recessed rather than as a card that failed to load.
			RowLocked = Color3.fromRGB(24, 24, 28),
			Edge = Color3.fromRGB(62, 60, 72),

			Text = Color3.fromRGB(240, 236, 228),
			Muted = Color3.fromRGB(148, 144, 156),

			-- The one warm colour, and the game's signature. Used for exactly three things:
			-- the title, the selected slot, and Play. Spending it on a fourth would cost it
			-- the first three.
			Accent = Color3.fromRGB(225, 200, 150),
			AccentHover = Color3.fromRGB(240, 218, 168),
			-- The deep end of the title and Play gradients. Gold falling into amber, rather
			-- than into brown -- keep the hue, drop the value.
			AccentDeep = Color3.fromRGB(198, 158, 92),
			-- Dark text on an accent fill.
			Ink = Color3.fromRGB(24, 20, 14),

			-- A refusal, and an armed delete. The only red on the screen.
			Warn = Color3.fromRGB(214, 126, 116),
			-- A life that is running. The spine on a playable slot card, and nothing else --
			-- it is the colour that means "there is somebody alive in here".
			Living = Color3.fromRGB(126, 198, 148),
			-- A life that has ended. Grey rather than red: a dead slot is a record the player
			-- earned, not an error, and colouring it like a failure would be the wrong reading
			-- of the one screen where finished lives are kept.
			Gone = Color3.fromRGB(120, 116, 126),
			-- A control that is mid-request. Desaturated rather than transparent, so the button
			-- stays exactly where it was and the screen never appears to lose a control.
			Busy = Color3.fromRGB(118, 112, 98),
			-- A control that is present and cannot be used right now -- the minus on a stat
			-- already at its floor. Darker than `Muted`, because a disabled control has to lose
			-- against body text it sits next to: the player should read the number, not the
			-- button that will not move it.
			Disabled = Color3.fromRGB(90, 88, 98),
		},

		Motion = {
			-- The column's arrival: how far it travels, and how long it takes.
			--
			-- **The first motion in the game, so it sets the register for everything after it.**
			-- Short and small: a menu that makes the player wait for it to finish assembling is
			-- a menu that has decided its own animation matters more than the press it is
			-- delaying. Everything is interactive from frame one regardless -- the tween moves
			-- pixels, it does not gate input.
			-- Safe range: 0-80 pixels, 0-1.2 seconds. Zero on either is an instant menu.
			EnterPixels = 44,
			EnterSeconds = 0.42,

			-- How long between one slot card arriving and the next.
			--
			-- The stagger is what makes three cards read as a list being dealt rather than as a
			-- block appearing. Multiplied by the card index, so the last card of `Config.Slots.Count`
			-- sets the total -- keep `Count * CardStaggerSeconds` under about a third of a second
			-- or raising the slot count turns the menu into a wait.
			-- Safe range: 0-0.12. Zero lands them all together.
			CardStaggerSeconds = 0.06,
			CardRiseSeconds = 0.34,
			-- How far a card travels on the way in, in pixels, and how far one slides right
			-- under the cursor. The hover slide is deliberately tiny: it is feedback that the
			-- row is live, not an animation worth watching.
			-- Safe range: 0-60 rise, 0-12 hover.
			CardRisePixels = 26,
			CardHoverPixels = 6,
			-- Hover in and out. Fast enough that the card feels attached to the cursor;
			-- anything above ~0.2 lags behind a player moving down a list.
			-- Safe range: 0.05-0.25.
			HoverSeconds = 0.12,

			-- The sheen that crosses the Play button, and how often.
			--
			-- **Only ever runs while Play would actually work.** A button that shines while
			-- refusing to open anything is a button advertising a thing it will not do, and the
			-- player learns to distrust the shine rather than reading the label under it.
			-- Safe range: 2-12 seconds between passes, 0.5-1.6 per pass. Below ~2 it is a
			-- strobe rather than a highlight.
			SheenPeriodSeconds = 4.5,
			SheenSweepSeconds = 0.9,
		},

		-- How wide the readability scrim behind the column is, as a fraction of the screen,
		-- and how far into that width the fade to transparent runs.
		--
		-- The column is text standing directly on a 3D scene, and the scene has a lit avatar
		-- and glowing shards in it. Without a scrim the subtitle is legible on a dark shoulder
		-- and gone against the halo. The fade is what stops it reading as a grey box pasted on
		-- the left: it is a gradient into the shot, not a panel over it.
		-- Safe range: 0.3-0.7 width, and a fade start of 0.4-0.9 of that width. The fade start
		-- must stay below 1 or there is no gradient at all.
		ScrimWidth = 0.46,
		ScrimFadeStart = 0.55,
		-- How dark the scrim is at its darkest, left edge. Safe range: 0.05-0.5. At 0 the left
		-- edge of the screen is pure black and the composition loses its floor.
		ScrimTransparency = 0.12,
	},

	-- Join codes: a short string a player generates for one of their slots, then
	-- enters (by hand or on another device) to jump straight to Play. It is a
	-- convenience, not a security feature -- the code is checked against the
	-- server's own table and the slot is still bounds-checked on arrival.
	JoinCode = {
		-- How many characters the code has. Six is long enough to not collide by
		-- chance (36^6 ≈ 2 billion) and short enough to type without mistyping.
		Length = 6,

		-- What characters are allowed. Uppercase digits and letters only -- no
		-- I, O, or l which look like 1 and 0 on small screens.
		Charset = "0123456789ABCDEFGHJKMNPQRSTUVWXYZ",

		-- How long a code lives after it is generated. Five minutes is enough to
		-- type it into a second device and press Enter, and short enough that a
		-- leaked code expires before it is worth anything.
		TTLSeconds = 300,

		-- How many active codes a single player may hold at once. One is the
		-- sensible default -- a code is a one-time shortcut, not a persistent
		-- share link -- and keeping it low means the server table stays small.
		MaxPerPlayer = 1,
	},
}

-- Spins: Robux buys a pull at a perk, disclosed odds and all. The one deliberate exception
-- to the no-gambling rule in the content guidelines -- see `ages_lobby_spec.md` -- and the
-- reason the exception is survivable is that a perk never gates content and, per the spec,
-- rarer is never stronger: every pull is a flavour of ordinary start, not a chance at power.
Config.Spins = {
	-- The odds, by rarity tier. Whole numbers out of their own sum rather than fractions of
	-- one, so `RarityWeights.common / total` reads as a percentage without anyone doing the
	-- division in their head first -- and so a designer can compare two tiers by eye.
	--
	-- Roblox requires the *per-item* probability be shown before a paid random purchase, not
	-- just the tier's. `content/Perks.luau` divides a tier's weight by how many perks are in
	-- it to get there -- see `Perks.Odds` -- so this table is the one place the tier-level
	-- number is decided and every perk in a tier is owed an equal share of it.
	-- Safe range: any positive integers. Must total something a human reads easily -- 100 is
	-- not required, but it is why these four were picked.
	RarityWeights = {
		common = 55,
		uncommon = 28,
		rare = 13,
		legendary = 4,
	},

	-- What Robux buys. Each entry is a developer product -- created once in the Creator
	-- Dashboard, then its id pasted in here, the same refuse-by-name pattern as
	-- `Config.Lobby.GamePlaceId`: a `ProductId` of 0 means "not published yet", and
	-- `SpinsService` refuses that product by name rather than failing inside a Robux call.
	--
	-- `Spins` is what one purchase grants, and `RobuxPrice` is display-only -- the real price
	-- is whatever was set on the product in the Dashboard, and this number exists only so the
	-- buy page can show a price before it asks Roblox to open the purchase prompt. If the two
	-- ever drift, the Dashboard is correct and this needs updating to match it.
	Products = {
		{
			id = "spins_1",
			name = "1 Spin",
			spins = 1,
			robuxPrice = 25,
			productId = 0,
		},
		{
			id = "spins_5",
			name = "5 Spins",
			spins = 5,
			robuxPrice = 100,
			productId = 0,
		},
		{
			id = "spins_12",
			name = "12 Spins",
			spins = 12,
			robuxPrice = 200,
			productId = 0,
		},
	},
}

Config.Setup = {
	-- Points to spend across the four stats, on top of the starting values.
	--
	-- The mechanic, not a bonus. Points can be taken *out* of a stat as well as put in
	-- (see MinPerStat), so the real question is not "where do my eight points go" but
	-- "what am I willing to be bad at" -- and a menu that only ever gave things away
	-- would be a reward screen with no decision in it.
	--
	-- Eight against starting values of 100/70/50/50 is deliberately modest: enough that
	-- a choice is visible in the first years, far too little to buy a life. Two decades
	-- of school move smarts further than this does.
	-- Safe range: 0-25. At 0 the section is dead weight and should be removed rather
	-- than zeroed; above ~25 the menu decides more about a life than the life does.
	StatPoints = 8,

	-- How far one stat can be pushed either way.
	--
	-- The floor is what makes the pool a trade rather than a wallet: -4 on looks buys
	-- four more points for smarts, and the player has decided to be a plain clever child
	-- instead of an average one. Capped well short of the pool in both directions so that
	-- no single stat can absorb everything -- a menu whose optimal play is "all eight into
	-- smarts, every life" is a menu with one answer.
	--
	-- Health is exempt in practice rather than by rule: it starts at 100 and StatService
	-- clamps to Config.Stats.Max, so buying it up does nothing and the menu says so.
	-- Safe range: 1 to StatPoints for the max, and -(StatPoints) to 0 for the min.
	MaxPerStat = 6,
	MinPerStat = -4,

	-- The longest a typed first or last name may be.
	--
	-- Short on purpose. This name goes on a nameplate, a death screen and a debug row,
	-- and none of those has room for a paragraph -- a limit the player meets while typing
	-- is far kinder than a name that silently renders off the edge of a panel later.
	-- Safe range: 8-24.
	MaxNameLength = 16,

	-- Eras. One real, three signposts.
	--
	-- The locked ones are here as *entries* rather than as a label reading "more coming",
	-- because a row the player can read and press -- and be told, by name, that it is not
	-- ready yet -- is a promise this game has made and can be held to. It is also the only
	-- honest way to answer "what else is there": pointing at the actual list.
	--
	-- Adding one is meant to be this small: flip `available` once the content behind it
	-- exists. Nothing else reads the id yet, which is exactly why the setup validator
	-- refuses an unavailable era rather than trusting the menu to have greyed it out.
	Eras = {
		{
			id = "modern",
			name = "Modern Day",
			blurb = "The world as it is. Phones, jobs, school, rent.",
			available = true,
		},
		{
			id = "eighties",
			name = "The Eighties",
			blurb = "No internet. One phone, in the hall, and everyone can hear you.",
			available = false,
		},
		{
			id = "victorian",
			name = "1880s",
			blurb = "Work starts at twelve and medicine is mostly guessing.",
			available = false,
		},
		{
			id = "future",
			name = "Near Future",
			blurb = "The jobs are different. So is how long you get.",
			available = false,
		},
	},
}

-- ---------------------------------------------------------------------------
-- Fighting.
--
-- A fight in AGES is a contest for *footing*, not for health. You do not injure
-- anybody; you take them off their feet, they go down, and they get back up. That
-- is not a content filter bolted on top of a damage system -- it is the damage
-- system, and it is what keeps a brawl inside 13+ without anybody having to
-- remember a rule. There is no blood, no injury state and no death animation here
-- because there is nothing in the mechanic for one to describe.
--
-- The verb is charge-and-release, the same primitive the sports work settled on, so
-- the game keeps one input language: hold to wind up, let go to commit. Around it sit
-- two answers -- guard and sidestep -- and the three of them make a triangle rather
-- than a ladder. Guard turns a strike into stamina loss; a *fully charged* strike
-- breaks a guard; a sidestep beats anything already committed. Which means holding
-- the charge longer is not simply better, and that is the whole game: the wind-up
-- that breaks a guard is the wind-up somebody can step around.
--
-- Stamina is what stops all three being free, and it is the pacing mechanism as
-- well. It recovers slowly while you are in range and quickly while you are not, so
-- a fight paces itself into exchange, break, exchange without a timer anywhere in
-- this table telling it to.
-- ---------------------------------------------------------------------------
Config.Fight = {
	-- Server tick. Matches the gym's rate: fast enough that a released charge lands on
	-- the value the player saw, slow enough that a busy street is not paying for it.
	-- Safe range: 0.05 .. 0.15.
	TickSeconds = 0.1,

	-- How much footing everybody starts a fight with before health is counted.
	-- Safe range: 40 .. 80.
	BaseFooting = 60,

	-- What a full health bar adds to that, as a share of BaseFooting. This is the only
	-- progression in the system and it is deliberately inside the mechanic rather than
	-- beside it: a player who has been to the gym watches their own footing bar draw
	-- longer, which is what GymService already does with its sweet zone and what the
	-- activity law asks for in place of a number on a menu.
	-- Safe range: 0.3 .. 1.0.
	HealthFootingBonus = 0.6,

	-- The shared pool every action spends from.
	-- Safe range: 80 .. 140.
	MaxStamina = 100,
	-- Recovery while still in range of the opponent, per second. Low on purpose --
	-- standing toe to toe should not refill you.
	-- Safe range: 4 .. 14.
	StaminaPerSecondEngaged = 9,
	-- Recovery once you have broken off. The gap between these two is what makes
	-- backing out of range a decision rather than a retreat, and it is where the verse
	-- and chorus of a fight comes from.
	-- Safe range: 15 .. 30.
	StaminaPerSecondClear = 22,

	-- Charge-and-release. Seconds to wind a strike from nothing to full.
	-- Safe range: 0.7 .. 1.2.
	ChargeSeconds = 0.9,
	-- Below this share of a full charge a release is a jab: cheap, fast, and it will
	-- not break anybody's guard. There is no dead zone where a release does nothing,
	-- because an input that silently does nothing is the one thing a player cannot
	-- learn from.
	-- Safe range: 0.15 .. 0.35.
	JabShare = 0.25,
	-- Past this share the wind-up is an overcharge: it hits harder than a full charge
	-- but leaves you in recovery for much longer, so the biggest punch in the game is
	-- also the most punishable. Free risk/reward for one number, the same shape as the
	-- golf-meter overswing.
	-- Safe range: 0.8 .. 0.95.
	OverchargeShare = 0.85,
	-- What a strike costs, and what it takes off an opponent at minimum and maximum
	-- charge. The floor is not zero: a jab that did nothing would make the fast option
	-- a trap rather than a choice.
	-- Safe range: StrikeStamina 10 .. 20, footing 4 .. 10 and 16 .. 26.
	StrikeStamina = 14,
	StrikeFootingMin = 6,
	StrikeFootingMax = 20,
	-- Extra footing an overcharged strike takes, as a multiplier on the maximum.
	-- Safe range: 1.2 .. 1.8.
	OverchargeFootingScale = 1.4,

	-- Recovery: seconds of lockout after committing, during which nothing is available.
	-- These three are the entire punish economy and they are ordered on purpose -- a
	-- clean strike costs least, an overcharge more, and a strike that hit nothing at
	-- all costs most.
	-- Safe range: 0.3 .. 0.6, 0.7 .. 1.1, 0.9 .. 1.4.
	StrikeRecoverSeconds = 0.45,
	OverchargeRecoverSeconds = 0.9,
	WhiffRecoverSeconds = 1.1,

	-- Guard. Holding costs stamina per second, so a permanent block is not a strategy.
	-- Safe range: 8 .. 18.
	GuardStaminaPerSecond = 12,
	-- What still gets through a successful block, as shares of the incoming strike.
	-- Some footing leaks -- a block should be the better outcome, never a free one --
	-- and the rest arrives as stamina cost, which is what eventually opens a turtling
	-- player up without needing a rule that says "you may not block".
	-- Safe range: footing 0.1 .. 0.25, stamina 0.6 .. 1.0.
	GuardedFootingShare = 0.15,
	GuardedStaminaShare = 0.8,
	-- The charge at which a strike breaks a guard outright. Sent to the client so the
	-- power meter can draw the line: the player has to see the threshold they are
	-- holding for, or the overcharge decision is being made blind.
	--
	-- **This must stay above OverchargeShare, and FightService refuses to load if it is
	-- not.** The two numbers together are the whole question the boxer asks. Below
	-- overcharge, a guard could be broken by a strike that never entered the punishing
	-- zone -- so breaking a guard would cost nothing at all, the safest play against a
	-- fifty-percent guard would be to hold exactly this much every single time, and an
	-- opponent built entirely around risk would have no risk left in him. Above it, there
	-- is no way through a guard that does not also accept the near-second of recovery,
	-- which is what makes squaring up to a boxer a bet rather than a routine.
	-- Safe range: 0.88 .. 0.95, and always greater than OverchargeShare.
	GuardBreakShare = 0.92,
	-- What breaking a guard is worth, as a multiplier on the strike's footing.
	-- Safe range: 1.3 .. 2.0.
	GuardBreakFootingScale = 1.5,
	-- Lockout on the guard that was broken. The reward for the read.
	-- Safe range: 0.5 .. 1.0.
	GuardBreakRecoverSeconds = 0.7,

	-- Sidestep. Expensive, brief and total: inside the window nothing lands. It has to
	-- be expensive, because a cheap dodge answers every question in the triangle.
	-- Safe range: stamina 18 .. 30, window 0.25 .. 0.45.
	SidestepStamina = 22,
	SidestepSeconds = 0.35,
	SidestepRecoverSeconds = 0.3,

	-- Inside this many studs you can hit and be hit.
	-- Safe range: 9 .. 16.
	RangeStuds = 12,
	-- Get this far away and the fight is over -- you walked out of it. Generous, so
	-- that backing off to recover stamina cannot end a fight by accident.
	-- Safe range: 40 .. 80.
	BreakStuds = 55,

	-- How long somebody stays down before getting back up. The fight is already over
	-- when this starts; it is a beat for the result to land, not a punishment, and it
	-- is short because the 13+ line is specifically about not dwelling here.
	-- Safe range: 2 .. 4.
	DownSeconds = 3,

	-- How long the result stays on screen after they are back up.
	-- Safe range: 2 .. 5.
	OverSeconds = 3,

	-- How far in front of the player a challenger squares up.
	-- Safe range: 6 .. 10.
	SquareUpStuds = 8,

	-- Walk speed an opponent closes at. Slower than a running player on purpose:
	-- breaking off has to be possible, or the stamina economy has no exit.
	-- Safe range: 10 .. 18.
	FoeWalkSpeed = 14,

	-- How long a beat line ("Blocked", "Broke guard") stays on the client.
	-- Safe range: 0.5 .. 1.5.
	BeatSeconds = 0.9,

	-- What losing costs, and what winning is worth.
	--
	-- Small on purpose, and health rather than money: a fight you lose should cost you
	-- the thing that makes the next fight harder, not the thing that makes the next
	-- hour harder. Because footing scales off health, a beating shortens your own bar
	-- the next time somebody squares up -- the loop closes on itself without a single
	-- number outside the mechanic, and a player on a losing streak feels it in the bar
	-- they are watching rather than in a wallet they are not.
	--
	-- The win pays happiness because nothing else honestly fits. Winning a street fight
	-- does not make you fitter or better looking, and paying it in money would make the
	-- town's toughs an income stream -- which is the "idle payout pad" the activity law
	-- names as the thing to avoid, just with a punch on the front of it.
	-- Safe range: 4 .. 12, 2 .. 8.
	LossHealth = 8,
	WinHappiness = 4,

	-- Notoriety: how known this life is for fighting, tracked in LifeData.notoriety.
	-- Ratchet-only, the same rule gang standing and crew nerve already use -- a loss
	-- never takes it back. Paid on every win, street tough or rival, so it is a
	-- straight count of fights won rather than a currency with an exchange rate.
	-- Safe range: 1 .. 3.
	NotorietyPerWin = 1,

	-- Getting caught. A fight is legal -- nobody is arrested for winning one -- but a
	-- brawl loud enough for a stranger to watch the whole way through is still a
	-- disturbance, and that is worth a small amount of heat, not a bounty tier. This
	-- is deliberately a single roll at the bout's end rather than WitnessService's
	-- continuous fill: a fight is over in twenty seconds, too short for a look-then-fill
	-- gesture to read as anything but instant, so it is asked once rather than every tick.
	--
	-- Safe range: 10 .. 20.
	WitnessSeeStuds = 14,
	-- Chance any one bystander within range caught the whole thing, rolled once per
	-- bystander at bout resolution. Several people nearby means several rolls, not
	-- a bigger single one -- a crowd is more likely to have caught it, not more
	-- damning when it does.
	-- Safe range: 0.15 .. 0.4.
	WitnessCatchChance = 0.25,
	-- What being caught costs, in heat, same scale as Config.Crime. Well under
	-- Config.Crime.Theft.HeatOnSpotted (18): the police are interested that a fight
	-- happened, not that a crime did.
	-- Safe range: 4 .. 10.
	WitnessHeat = 6,

	-- Rival gang fights. Standing paid to your own gang on a win is deliberately close
	-- to Config.Gangs.Earn.VaultOpened (45) -- beating one of their own is worth about
	-- what a job is -- and the charge against the rival gang mirrors
	-- Config.Territory.Incursion.RivalCost, because losing an enforcer on their own
	-- ground is the same kind of loss as being caught running their line. A loss costs
	-- neither side any standing: only LossHealth, the same as any other fight.
	-- Safe range: standing 30 .. 60, charge 15 .. 35.
	RivalWinStanding = 45,
	RivalWinChargeRival = 25,
}

-- Milestones. One-time bonuses for hitting life landmarks, fired once per life
-- so the player gets the celebration exactly once. Each entry names the trigger,
-- the label the client shows, and the money bonus attached.
Config.Milestones = {
	FirstJob = { label = "First Job", bonus = 500 },
	FirstHouse = { label = "Homeowner", bonus = 1000 },
	TenShifts = { label = "Steady Worker", bonus = 300 },
	FiftyShifts = { label = "Dedicated", bonus = 1000 },
	MaxStanding = { label = "Top Performer", bonus = 2000 },
	Age30 = { label = "Thirty", bonus = 1000 },
	Age50 = { label = "Fifty", bonus = 2000 },
	Age80 = { label = "Long Life", bonus = 5000 },
}

-- Skills. What the player has got good at, one line per discipline, earned by doing
-- the thing and graded on how well it went.
--
-- The rule that shapes every number below: **XP is only ever awarded for a graded
-- outcome, never for elapsed time and never for arriving somewhere.** A skill that
-- ticks up while a player stands in a gym is not a skill, it is a clock with a label
-- on it, and this game already has one of those it is trying to get rid of. Every
-- Award call in the tree is downstream of something the server judged: a sweep hit
-- landing in the sweet band, a lesson answer being right, a bout being won, a canvas
-- being signed. If a hook cannot name the thing that was judged, it is not a hook.
--
-- Per life, like money and the job. A skill that survived death would make dying a
-- setback rather than an ending, which is the one thing this game will not do.
Config.Skills = {
	-- The ladder, shared by every skill so that "level 4" means the same amount of
	-- work everywhere. Thresholds are cumulative XP, and the last band is the cap --
	-- a skill that ran off the end of this table would have no name to show.
	--
	-- Superlinear, but only gently: each band costs roughly a third more than the one
	-- before rather than double. Doubling is the usual choice and it is wrong here,
	-- because the top of a doubling ladder is unreachable inside one life and a rung
	-- nobody can stand on is decoration. These add up to 4,700 XP, which a player who
	-- actually plays one discipline can finish.
	Levels = {
		{ level = 1, atXp = 0, name = "Beginner" },
		{ level = 2, atXp = 120, name = "Novice" },
		{ level = 3, atXp = 320, name = "Capable" },
		{ level = 4, atXp = 640, name = "Skilled" },
		{ level = 5, atXp = 1100, name = "Practiced" },
		{ level = 6, atXp = 1750, name = "Sharp" },
		{ level = 7, atXp = 2600, name = "Expert" },
		{ level = 8, atXp = 4700, name = "Master" },
	},

	-- The disciplines, in the order the menu lists them. `id` is what services award
	-- against and what the save is keyed by, so renaming one silently zeroes every
	-- player's progress in it -- add a new id rather than editing an old one.
	--
	-- Deliberately short. Six lines a player can name beats fifteen they cannot, and
	-- every entry here has at least one service already grading something that feeds
	-- it. A skill with no source is a row that never moves, and a row that never moves
	-- teaches the player to stop reading the panel.
	Definitions = {
		{
			id = "fighting",
			label = "Fighting",
			-- What it is earned by, shown under the bar. Written as the player's own
			-- action rather than as a system name: "Won squares in a fight" is
			-- something they remember doing, "FightService outcomes" is not.
			earnedBy = "Winning squares and taking bouts",
			color = Color3.fromRGB(232, 92, 76),
		},
		{
			id = "athletics",
			label = "Athletics",
			earnedBy = "Timing sweeps on the gym machines",
			color = Color3.fromRGB(96, 200, 255),
		},
		{
			id = "academics",
			label = "Academics",
			earnedBy = "Answering lessons correctly",
			color = Color3.fromRGB(150, 140, 255),
		},
		{
			id = "science",
			label = "Science",
			earnedBy = "Committing a lab run that holds up",
			color = Color3.fromRGB(94, 226, 178),
		},
		{
			id = "art",
			label = "Art",
			earnedBy = "Signing a canvas you finished",
			color = Color3.fromRGB(255, 176, 74),
		},
		{
			id = "nerve",
			label = "Nerve",
			earnedBy = "Getting away with it",
			color = Color3.fromRGB(236, 120, 200),
		},
	},

	-- The most XP one call may award, whatever it asks for. A guard on the callers
	-- rather than a tuning knob: every hook in the tree passes a small constant today,
	-- and this exists so that a future one multiplying by a streak, a combo count or a
	-- payout cannot quietly turn a single action into a level.
	-- Safe range: 20-100.
	MaxPerAward = 60,

	-- What each judged outcome is worth. Every name here corresponds to exactly one
	-- call site, and the call site is named in the comment, so a number that looks
	-- wrong can be traced to the thing it pays for without a search.
	--
	-- Sized against the ladder above: a Master at 4,700 XP is roughly 800 perfect gym
	-- reps, 940 right answers, or 235 bouts taken. Those are large and they are meant
	-- to be -- Master is one life's worth of one discipline, not an afternoon's.
	Awards = {
		-- GymService.answer, per rep, on the grade the sweep was judged at. A miss pays
		-- nothing at all rather than a consolation trickle: the sweep is the only thing
		-- the gym asks the player to get right, and paying for a miss would make the
		-- timing decorative.
		-- Safe range: 2-12.
		GymPerfect = 6,
		-- Safe range: 1-6.
		GymGood = 3,

		-- SchoolService.answer, per right answer. Time running out is a wrong answer
		-- here, exactly as it is for the lesson's own grade.
		-- Safe range: 2-10.
		LessonCorrect = 5,

		-- FightService.decide, on a bout the player took. Nothing for a loss, and that
		-- is not a judgement about whether losing teaches you something -- it is that a
		-- loss is the one fight outcome a player can produce on demand by standing
		-- still and being hit, which is the exact shape this whole table exists to
		-- refuse.
		-- Safe range: 10-40.
		FightWon = 25,

		-- ScienceService, per procedure step matched in order on a committed bench.
		-- Multiplied by the match count at the call site, which is the one place in the
		-- tree where MaxPerAward is doing real work rather than sitting as a guard.
		-- Safe range: 2-8.
		LabStepMatched = 4,

		-- ArtService.finish, multiplied by the share of the study actually reproduced,
		-- so a canvas walked away from at a tenth done pays a tenth. Awarded however
		-- the session ended, for the reason the lesson count is: leaving early is a way
		-- of doing it badly, not a way of avoiding being graded.
		-- Safe range: 15-50.
		ArtCanvas = 30,

		-- GangService.checkEscape, when a bounty that got above
		-- Config.Gangs.Earn.GotAwayNeedsBounty falls to nothing without an arrest.
		--
		-- Deliberately paid to everybody, gang or not, unlike the standing award beside
		-- it. Nerve is about what you got away with; needing a gang to be credited for
		-- it would make the only unbanked discipline in the game a members-only one.
		-- Safe range: 15-45.
		GotAway = 30,
	},
}

-- NPC gossip. When two townsfolk are near each other and the player has done
-- something notable, one may share a line about the player with the other.
-- The gossip fades over time and nudges bonds among nearby people.
Config.Gossip = {
	-- How many game hours gossip stays active before fading.
	-- Safe range: 24-96.
	FadeHours = 48,
	-- How often the gossip system checks for new opportunities.
	-- Safe range: 30-120 seconds.
	TickSeconds = 60,
}

-- Preferences. Every one of these is a switch that changes something the player can point
-- at, and that is the entry bar rather than a style note: a settings screen collects
-- switches by gravity, and the first one that toggles nothing teaches the player that none
-- of them do.
--
-- The list is content and the *effects* are not. Each id below is matched by an explicit
-- arm in the client, which errors by name on an id it does not know -- so adding a row
-- here without wiring it is a crash on the first push rather than a dead switch shipping.
--
-- All of them default to the game as it plays today. Nobody is opted into a change by an
-- update, and a player who never opens this pane never notices it exists.
Config.Settings = {
	Options = {
		{
			id = "ageUpConfirm",
			label = "Confirm before ageing up",
			-- Two captions, one per state, in the player's words. See `SettingState` for why
			-- a caption beats an "On"/"Off" figure.
			captionOn = "Pressing Age Up asks first. A year is never spent by a misclick.",
			captionOff = "Pressing Age Up spends the year immediately.",
			-- Off, and it is the one row here where that is a close call. Ageing up is
			-- irreversible and the button sits under the cursor for the whole life -- but a
			-- confirm on the single most-pressed control in the game is a second click every
			-- year for a player who never misclicks, and the ones who want it will find it
			-- here the first time it costs them.
			default = false,
		},
		{
			id = "minimap",
			label = "Minimap",
			captionOn = "The dial in the corner is showing.",
			captionOff = "Hidden. The full map still opens on M.",
			default = true,
		},
		{
			id = "moneyPops",
			label = "Money popups",
			captionOn = "Every payment and charge floats up where it happened.",
			captionOff = "Money changes silently. The balance is still on the HUD.",
			default = true,
		},
		{
			id = "celebrations",
			label = "Celebrations",
			captionOn = "Milestones and new friendships take the screen for a moment.",
			captionOff = "They pass as a line of text instead.",
			default = true,
		},
	},
}

-- Codes. The redeem box, not the codes themselves -- those are content and live in
-- `src/server/content/Codes.luau`, because a code is a thing somebody writes, dates and
-- retires, and Config is for numbers that tune behaviour.
Config.Codes = {
	-- The longest string the box will look at. A guard rather than a limit on what a code
	-- may be called: the field is free text arriving from a client, and every free-text
	-- field in this tree has a length it stops reading at.
	-- Safe range: 16-64.
	MaxLength = 32,
	-- How long a player must wait between attempts.
	--
	-- The only reason this exists is that a code box is a guessing surface -- it is the one
	-- input in the game where a client that fires it a thousand times a second is trying to
	-- win rather than misbehaving. A second is invisible to somebody typing and ruinous to
	-- somebody enumerating.
	-- Safe range: 0.5-5.
	AttemptCooldownSeconds = 1,
	-- The most codes one account may hold. Not a balance lever -- the reward per code is
	-- the balance lever -- but a bound on the size of a field that is written to the save
	-- and never pruned.
	-- Safe range: 50-500.
	MaxRedeemed = 200,
}

return Config
