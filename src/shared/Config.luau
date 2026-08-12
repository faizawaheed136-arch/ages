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
}

-- How the player talks to anything at all. Three dots over its head; get near, they
-- wake up, click them and the options come up. One grammar for a person and for an
-- animal, because learning how to talk to this world should happen once.
--
-- Not for a lesson. A lesson is something you are already inside rather than a thing
-- in the room, so its questions open themselves; see SchoolService.
Config.Interact = {
	-- How close the player has to be before the dots can be clicked. Generous on
	-- purpose: this is a game partly played as a toddler at walkSpeed 4, and a
	-- reach that demands precision would turn talking to your mother into parking.
	-- Roughly a room's width. Safe range: 8-20.
	ReachStuds = 12,

	-- How long the dots take to wake up when you come into range, and to settle
	-- again when you leave. Short enough to read as a response to you rather than
	-- an animation playing at you. Safe range: 0.1-0.4.
	WakeSeconds = 0.18,

	-- The key that does the same thing as clicking the dots.
	--
	-- Set explicitly rather than left at the ProximityPrompt default, because the
	-- hint drawn beside the dots has to say the key that actually works, and a
	-- default that Roblox changes one day would leave the game telling the player
	-- to press a key that does nothing. One source, both ends.
	KeyboardKey = Enum.KeyCode.E,

	-- How far to the right of the dots the key hint sits, in scale units of the
	-- dots' own billboard. Far enough not to crowd them, near enough to read as
	-- belonging to them. Safe range: 0.5-1.1.
	KeyHintOffset = 0.78,

	-- How far the dots and the nameplate carry, as multiples of ReachStuds.
	--
	-- Two numbers rather than one because they answer different questions, and the gap
	-- between them is the whole design. The dots are *signposting* -- "there is somebody
	-- over there worth walking to" -- and they should out-range the reach that makes them
	-- clickable, or a person only announces themselves once you are standing on them. A
	-- name is *identification*, and it is only worth reading about somebody you are
	-- actually approaching.
	--
	-- The name used to carry further than the dots (3.5, so 42 studs on a town whose whole
	-- route graph spans about 150) and drew through walls, which meant standing anywhere
	-- outdoors put a drift of names across the screen belonging to people behind buildings
	-- on the other side of the street. Now it is the shorter of the two: you see that
	-- somebody is there from a long way off, and you learn who they are as you close.
	--
	-- Safe range: dots 2-3.5, name 1.2-2. Name below about 1.2 arrives after the dots are
	-- already clickable, which is too late to help you choose who to walk to.
	DotsRangeMultiplier = 2.5,
	NameRangeMultiplier = 1.6,
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

	-- How far away the sign is still drawn. Much larger than a choice label's range,
	-- because this one has a different job: a choice label is read once you have
	-- arrived, and this is read to decide whether to walk over at all. It should be
	-- legible from the far end of the street.
	-- Safe range: 40-250. Below ~40 you have to already be inside to learn the shop
	-- is hiring, which is the problem this exists to fix.
	SignMaxDistanceStuds = 160,
}

-- What you actually do for four minutes.
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
	-- waits out a gap before it appears.
	-- Safe range: Good 1, Ok 0.6-0.9, Poor 0.2-0.5, None 0-0.2, and descending.
	WageShareGood = 1,
	WageShareOk = 0.8,
	WageSharePoor = 0.3,
	WageShareNone = 0,

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
	-- False restores click-to-answer everywhere. Kept a switch rather than deleted
	-- because a lesson sat in a doorway is exactly the case where the panel is the
	-- right answer, and because the whole point of the room is a place discs can go.
	PhysicalLessons = true,

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
	-- The whole reason a bond is worth anything. Without this, every relationship in the
	-- game only ever climbs, visiting is pure upside, and the correct play is to do it
	-- once and never think about it again -- which is not a relationship, it is a
	-- collectible. Charged only for the years somebody was actually in your life, so
	-- nobody is penalised for failing to visit a friend they had not met yet.
	--
	-- Priced under what a single visit gives back, so one visit a year is comfortably
	-- ahead and the player is never running to stand still.
	-- Safe range: -6 to 0. At 0 the bond is a collectible again.
	DecayPerYearAway = -3,

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
		"suburb_50",
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
	-- **Prefer a whole multiple of #PATTERN in Townsfolk.luau** (17, so 34 is two of them).
	-- Genders alternate by index and archetypes repeat every #PATTERN, so a whole number of
	-- passes gives every archetype an exact half-and-half split; a partial pass leaves the
	-- last few slots one-sided. Townsfolk checks this at load and errors if any archetype
	-- ends up more than one out, so a number that breaks it will say so rather than quietly
	-- producing a town where every peer is a man.
	-- Safe range: 8-60. Above ~60 the rings around the four places start refusing spots.
	Count = 34,

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
}

-- until the player cannot find the menu. A shop that hires at sixteen is no use to
-- someone who never learned the shop was there, and "walk around until you find it"
-- is not discovery, it is a search. This draws the line from where you are to the
-- thing that just opened up.
--
-- Read by the client, which is what draws it. The server only decides where to
-- point and when to stop.
Config.Guide = {
	-- The same warm gold as a choice marker, and deliberately so: by the time a
	-- player follows one of these they have already learned that this color means
	-- "this is for you, go to it". A second accent color would be a second thing to
	-- learn for no gain.
	Color = Color3.fromRGB(245, 205, 120),

	-- How wide the core line is at the player's end and at the destination. Slim
	-- enough to read as a path marker rather than a highway, wide enough at the far
	-- end to taper the eye toward the destination.
	-- Safe range: 0.15-0.8, near below far.
	WidthNearStuds = 0.18,
	WidthFarStuds = 0.55,

	-- A second, wider beam behind the core that gives the line a soft glow halo.
	-- The halo is what makes the line feel warm rather than wire-like; the core is
	-- what gives it sharpness. Together they read at every distance.
	-- Safe range: 0.6-3, near below far.
	HaloWidthNearStuds = 0.9,
	HaloWidthFarStuds = 2.0,
	-- 0 = invisible, 1 = fully opaque. The halo should be felt more than seen.
	-- Safe range: 0.7-0.95.
	HaloTransparency = 0.82,

	-- A gentle width oscillation on the halo so the glow breathes. Zero disables.
	-- The core beam stays steady; only the halo pulses.
	-- Safe range: 0-0.3 studs, 0.5-3 Hz.
	PulseStrengthStuds = 0.12,
	PulseSpeed = 1.2,

	-- How high off the ground the line floats at each end. Lifted at the player so
	-- it leaves from about waist height instead of clipping through the floor on a
	-- slope, and dropped at the destination so it visibly lands on the spot.
	-- Safe range: 0-4.
	LiftAtPlayerStuds = 2,
	LiftAtTargetStuds = 1,

	-- How much the line sags between the two ends. A dead-straight line through
	-- three walls reads as a rendering fault; a curve reads as a path. Kept modest
	-- so the line reads as a gentle arc rather than a hanging rope.
	-- Safe range: 0-40. Above ~40 it loops so high it stops indicating direction.
	CurveStuds = 6,

	-- How often the client redraws. Only the player's end actually moves, and it
	-- moves with them, so this is about the destination label's distance readout
	-- rather than the line itself.
	-- Safe range: 0.1-1.
	RefreshSeconds = 0.25,

	-- Close enough to count as arrived, at which point the line would be pointing at
	-- the floor under your feet. The label stays up -- you still want to know what
	-- you are standing in front of -- but the line goes.
	-- Safe range: 8-40. Wants to be at or above Work.StationRadiusStuds so the line
	-- clears once you are inside the workplace rather than at the doorway.
	ArrivedRadiusStuds = 26,

	-- Scrolling arrows along the line, once there is an image to scroll. Empty means
	-- a plain glowing line, which is what ships today: an arrow texture is an asset
	-- upload, and there is no Roblox group to upload it to yet. Everything else here
	-- is already tuned for it, so this is a one-line change when the group exists.
	-- Safe range for the speed: 0.5-4, negative to run the arrows backwards.
	ArrowTexture = "",
	ArrowSpeed = 1.5,
	-- How many times the texture repeats across the line's length, per 10 studs.
	-- Safe range: 0.5-4.
	ArrowsPerTenStuds = 1.5,
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

	-- How long the death screen holds before the player is sent back to the lobby.
	--
	-- A ceiling rather than a wait: the screen has a "Back to the menu" button on it, and
	-- most players will press it. This is what happens for the ones who do not, so that a
	-- death is never a screen somebody is stuck looking at.
	-- Safe range: 3-15. Long enough to read the summary, short enough that it doesn't feel
	-- like a punishment.
	RespawnDelaySeconds = 5,
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

return Config
