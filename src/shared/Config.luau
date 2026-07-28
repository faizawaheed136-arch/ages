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
