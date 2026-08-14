--!strict
-- The town: everybody in the world who is not one of the four people a life is made of.
--
-- Cast.luau says, correctly, that a small fixed cast beats generated strangers -- the
-- neighbor who knocks when you are nine has to be the neighbor who knocks when you are
-- forty. This file is not an argument with that. It is the other half of it. Those four
-- are the people a life is *made of*, and they are hand-written because being your mother
-- is a thing only writing can do. The town is the street those four stand on, and a
-- street cannot be hand-written thirty times over without becoming four rooms with a
-- crowd painted on the walls.
--
-- So the split is by what the person is for:
--
--   The cast     Four. Authored down to the sentence. In your life from birth or from
--                the year you meet them, and gone only when the writing says so.
--   The town     Thirty. Generated. Nobody's relative, nobody's plot. What they have
--                instead is that they are there every time you go, and that turning up
--                is the only thing that has ever changed them.
--
-- Generated ONCE, from a fixed seed, identically for every player and every server. That
-- is the load-bearing decision and everything else here bends around it. A bond is saved
-- against a person id; a population re-rolled per session would hand the friend you spent
-- fifteen years earning to a stranger wearing a different face, and it would do it
-- silently, because the id would still resolve. So the town is a fact about the world.
-- The bond is the only part of it that is yours.
--
-- The seed is used per person rather than as one stream, which is why `Config.Town.Count`
-- can be raised without disturbing anybody: townsperson 7 is a function of the seed and
-- the number 7 alone, so it does not matter how many draws townsperson 6 made, or whether
-- townsperson 31 exists. Their archetype comes off a fixed repeating pattern for the same
-- reason.
--
-- What is deliberately not here: any of them knowing your name, having a history with
-- you, or saying anything that only makes sense once. Those are the four's job. A
-- generated line that tried to be personal would be the exact moment the player noticed
-- these were generated.
--
-- What *is* here, and is the one thing a generated person can have that is genuinely
-- personal: a rung. Every archetype below carries a ladder -- knows you, friend, closest
-- friend -- and which of its six or eight copies you climbed it with is a fact about one
-- particular person that nothing generated it. See content/Ties.luau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local Ties = require(script.Parent.Ties)

type CastMember = Types.CastMember
type Gender = Types.Gender
type Person = Types.Person
type PersonOffer = Types.PersonOffer
type StatDelta = Types.StatDelta

local TOWN = Config.Town
local PEOPLE = Config.People
-- The bond an offer must ask for to be one nobody can ever be too estranged to take.
-- Same meaning it has in People.luau, and the floor check there counts on it.
local ALWAYS = PEOPLE.MinBond

-- Spread between one townsperson's seed and the next. A large odd number rather than 1,
-- because Random.new with adjacent seeds produces visibly related first draws -- which
-- would show up as neighbours on the ring being the same height and colour.
local SEED_STRIDE = 7919

-- Names are drawn from their own stream rather than from the body's, so that widening a
-- name pool later renames people without also resizing and recolouring them. Far enough
-- from any multiple of the stride that it cannot land on another townsperson's seed.
local NAME_STREAM = 104729

-- Tried before this file gives up on finding somebody an unused name. Only reachable if
-- the pools below shrink to near the population size, and reported rather than silently
-- producing two people called the same thing standing in one room.
local NAME_ATTEMPTS = 64

-- One thing an archetype can do with you. A PersonOffer with the per-person parts left
-- out: the id is built from whose offer it is, and the line is picked from several so
-- that eight people of the same kind do not answer in one voice.
type Template = {
	id: string,
	label: string,
	-- The player's ages, clamped into the archetype's own window at generation. Written
	-- as the years the *sentence* makes sense, so a template can be shared by two
	-- archetypes with different windows without being rewritten.
	minAge: number,
	maxAge: number,
	minBond: number,
	-- The upper gate, on the same terms as PersonOffer: while the bond sits above this
	-- the row is not offered. Hostile rows are written at maxBond = -5 so a cold
	-- relationship is the only one that can sour further, and the apology at maxBond = -1
	-- so it is on the floor for the whole of the negative range and gone once the damage
	-- is past. Checked against minBond here so the error names the template, not the
	-- fourteenth generated copy of it.
	maxBond: number?,
	bond: number,
	stats: StatDelta?,
	money: number?,
	ask: boolean?,
	lines: { string },
	-- Required when `ask` is set, refused otherwise. Same rule PersonOffer has, checked
	-- here so the error names the template rather than the fourteenth generated copy of
	-- it.
	refusedLines: { string }?,
	-- The answer is a walk rather than a talk, passed straight through to PersonOffer --
	-- see the note on PersonOffer.walksTo for what accepting one does. `arrivalLines` is
	-- plural, like `lines`, so eight people generated from one template do not all greet
	-- you at the destination in one voice.
	walksTo: string?,
	arrivalLines: { string }?,
	-- The rung, and what it takes to be standing on the one below. Passed straight
	-- through to PersonOffer -- see Types.luau and content/Ties.luau for what they mean.
	--
	-- These are what make thirty strangers into a town somebody actually lives in. A
	-- bond on its own only ever changed what was *offered*; a rung changes what a person
	-- *is*, and the reason it belongs on an archetype rather than only on the authored
	-- four is that friendship is the thing most likely to happen to you with somebody
	-- nobody wrote a name for.
	--
	-- Deliberately no `sets`/`clears` here. A flag is a fact about the life, and a flag
	-- set by a generated offer would be set identically by all six people generated from
	-- the same archetype -- which makes it a fact about having met *a* classmate, not
	-- about the one you met. That is what a tie is for.
	gives: string?,
	needsTie: string?,
}

-- A kind of person, and the only thing in this file that is really authored. Thirty
-- people is too many to write; five kinds of person is not, and it is where all of the
-- character in the town actually lives.
type Archetype = {
	id: string,
	placeId: string,
	-- The player's ages this kind of person is around for.
	minAge: number,
	maxAge: number,
	-- Years older than the player, drawn from this span. What separates the kid on your
	-- street from the man who is always in the shop, more than anything either of them
	-- says.
	minAgeOffset: number,
	maxAgeOffset: number,
	-- Build, drawn per person: how far off average for their age this one is, where 1 is
	-- average. **Not height.** Height comes from Config.Growth and the age offset above,
	-- which is what makes a school read as a school from across the yard and, more to the
	-- point, what makes the kid you played out front with at four taller at seventeen.
	--
	-- These used to be absolutes -- street kids were written at 0.8 to 0.95 -- and that was
	-- wrong twice over: a rig shrunk without its head shrunk less is a short adult rather
	-- than a child, and a number drawn once never grows. Every archetype now sits within a
	-- few percent of 1, because being unusually tall is a fact about a person and being
	-- four feet tall is a fact about being nine.
	minHeight: number,
	maxHeight: number,
	startingBond: number,
	busyLines: { string },
	offers: { Template },
	-- Contextual dialogue keyed by situation. Picked when the person is near the player
	-- and the offer panel is not open. Nil means no extra lines.
	contextualLines: { [string]: { string } }?,
}

-- Two lists rather than one, because a name has to agree with the person wearing it.
--
-- This was a single list of forty-two back when nothing read a townsperson's gender, so
-- nothing could disagree with their name. The moment anything surfaces it -- and the town
-- listing now shows the initial next to every row -- a "Marcus" the game privately
-- considers a woman is not a rounding error, it is the game contradicting a fact about a
-- stranger it has chosen to show. Splitting the list is what keeps name and person agreed.
--
-- Split rather than tagged per entry, so a name cannot be added without answering the
-- question, and drawn from *after* the gender is rolled, so the two are one decision.
-- The four that were genuinely unisex in the old list -- Hollis, Quill, Sunni, Wren --
-- were assigned rather than dropped; they are good names and the alternative is a shorter
-- world for a tidiness nobody would ever see.
--
-- Kept deliberately wide in origin. A town where everybody is named from one tradition is
-- a town that has quietly decided who lives there.
local MALE_FIRST_NAMES: { string } = {
	"Amos",
	"Callum",
	"Darius",
	"Eamon",
	"Farid",
	"Gus",
	"Hollis",
	"Isak",
	"Jonah",
	"Kaveh",
	"Linus",
	"Marcus",
	"Nico",
	"Odell",
	"Quill",
	"Rafi",
	"Tobias",
	"Vance",
	"Yusuf",
	"Zaid",
}

local FEMALE_FIRST_NAMES: { string } = {
	"Adaeze",
	"Anouk",
	"Bea",
	"Cleo",
	"Delia",
	"Esme",
	"Frida",
	"Halima",
	"Ines",
	"Junie",
	"Keziah",
	"Lena",
	"Mabel",
	"Nadia",
	"Oona",
	"Pilar",
	"Rosalind",
	"Sunni",
	"Trudy",
	"Ulla",
	"Wren",
	"Zora",
}

local LAST_NAMES: { string } = {
	"Ableman",
	"Barrow",
	"Cassar",
	"Dunmore",
	"Enright",
	"Fenwick",
	"Gale",
	"Hargreave",
	"Ijeoma",
	"Jarvis",
	"Kandel",
	"Lomax",
	"Mbeki",
	"Nightingale",
	"Okonkwo",
	"Pell",
	"Quinlan",
	"Rutledge",
	"Sandoval",
	"Tourville",
	"Ustinov",
	"Vasquez",
	"Whitlock",
	"Yardley",
	"Zeman",
	"Ashgrove",
	"Bellweather",
	"Coriander",
}

-- Skin tones, as HumanoidDescription takes them. A palette rather than a random channel
-- walk: three random bytes produce green people about as often as they produce anybody,
-- and a town is not a place to find that out in.
local SKIN_TONES: { Color3 } = {
	Color3.fromRGB(247, 214, 189),
	Color3.fromRGB(238, 199, 170),
	Color3.fromRGB(226, 181, 150),
	Color3.fromRGB(210, 163, 130),
	Color3.fromRGB(191, 143, 110),
	Color3.fromRGB(168, 124, 96),
	Color3.fromRGB(145, 104, 78),
	Color3.fromRGB(122, 86, 64),
	Color3.fromRGB(98, 68, 50),
	Color3.fromRGB(76, 52, 38),
}

local ARCHETYPES: { Archetype } = {
	{
		-- The kids on your street. The only townsfolk who are around before school is,
		-- and the reason the first six years of a life have anybody in them but family.
		--
		-- From nought rather than from four, and that is not a bonding decision -- it is
		-- what stops the opening of the game being a world with two people in it. An age
		-- window here was doing two jobs at once: deciding who you can get to know, and
		-- deciding who *exists*. Nobody expects a two-year-old to make a friend. They do
		-- expect there to be somebody outside.
		--
		-- The offset floor is nought for the same reason it is not minus one: a kid a year
		-- younger than a toddler is a baby, and a baby standing on the pavement offering to
		-- be followed is worse than an empty pavement.
		id = "street",
		placeId = "home",
		minAge = 0,
		maxAge = 17,
		minAgeOffset = 0,
		maxAgeOffset = 3,
		minHeight = 0.94,
		maxHeight = 1.04,
		-- A little warmth to start with, for the same reason Rae has some: you are small
		-- and so are they and that is the entire basis of it.
		startingBond = 5,
		busyLines = {
			"Can't, I've got to go in. Tomorrow?",
			"Not now! We're in the middle of something.",
			"My mum's calling me. See you out here after.",
		},
		contextualLines = {
			morning = {
				"Wake up early, huh?",
				"The sun's nice today.",
				"Let's play until mum calls us in.",
			},
			onShift = {
				"You're working? Cool!",
				"Make lots of money!",
				"Can I come visit you?",
			},
			unemployed = {
				"What do you do all day?",
				"I wish I could play all day too.",
			},
		},
		offers = {
			-- The relationship block, shared by every archetype so whoever you are talking
			-- to -- a written name or one of thirty rolled strangers -- can be talked to at
			-- any depth, driven apart, and mended. Written first because the panel sorts by
			-- what a row asks of the bond and throws the tail away: at the bottom of the
			-- range, where the archetype's own rows have all asked for more warmth than is
			-- on offer, this is what somebody still has. The hostile rows and the apology
			-- carry no stats -- the relationship is the point, and the cold shoulder is not
			-- meant to be a treat.
			{
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 5,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				lines = {
					"Nothing much to do. I'm staying out here.",
					"What do you want to talk about? I'm bored, but I can talk.",
					"It's boring when there's nobody around. Good, then. You're here.",
				},
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				lines = {
					"Whatever. I'm not bothered.",
					"Come back when I feel like it. That could be a while.",
				},
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				lines = {
					"Don't talk to me. I mean it.",
					"Yeah. Whatever. I said whatever.",
				},
			},
			{
				id = "make_right",
				label = "Try to make it right",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -1,
				bond = 8,
				ask = true,
				lines = {
					"Alright. Fine. I'm still cross, but fine.",
				},
				refusedLines = {
					"Not yet. Give it time. A lot of time.",
					"You keep saying that. I don't believe you yet.",
				},
			},
			-- The toddler band, and the whole of what a street is to somebody who cannot
			-- yet say a sentence. Two rows, both cheap, both over by five -- deliberately
			-- thin, because the point of them is that the dots above somebody's head are
			-- lit rather than dark, not that a two-year-old has a social life. What they
			-- really teach is the grammar: three dots means a person you can answer, and a
			-- player who learns that at two knows it at forty.
			--
			-- They are also load-bearing. The floor check at the bottom of this file
			-- refuses an archetype with a year in it that nobody at the bottom of the bond
			-- range could take, so the window above cannot be widened without these --
			-- which is the right way round.
			{
				id = "toddle_after",
				label = "Toddle after them",
				minAge = 0,
				maxAge = 4,
				minBond = ALWAYS,
				bond = 3,
				stats = { happiness = 2 },
				lines = {
					"It's following me again. Muuum, it's following me.",
					"Come on then. Slowly. You're really slow.",
					"You can come. Hold my hand at the road bit.",
				},
			},
			{
				id = "copy_them",
				label = "Copy what they're doing",
				minAge = 0,
				maxAge = 4,
				minBond = 0,
				bond = 3,
				stats = { happiness = 2 },
				lines = {
					"No, like this. Like THIS. You're not doing it.",
					"Ha! Do it again. Do it again!",
					"Stop copying me. ...Okay, keep copying me.",
				},
			},
			{
				id = "out_front",
				label = "Go out front with them",
				minAge = 4,
				maxAge = 17,
				minBond = ALWAYS,
				bond = 3,
				stats = { happiness = 2 },
				lines = {
					"Come on then. Before it gets dark.",
					"Yes! I've been out here on my own for ages.",
					"Right. You're on my team, obviously.",
				},
			},
			{
				id = "swap",
				label = "Swap something with them",
				minAge = 6,
				maxAge = 14,
				minBond = ALWAYS,
				bond = 4,
				stats = { happiness = 1 },
				lines = {
					"Deal. No takebacks, that's the rule.",
					"Mine's better but fine. Fine!",
					"Don't tell anyone what I gave you for it.",
				},
			},
			{
				-- Costs health and pays happiness, which is the honest arithmetic of being
				-- nine. It is also the only thing on this list you have to have warmed to
				-- somebody to be offered, because nobody dares a stranger.
				id = "dare",
				label = "Take the dare",
				minAge = 7,
				maxAge = 15,
				minBond = 0,
				bond = 5,
				stats = { happiness = 3, health = -1 },
				lines = {
					"You actually did it. You actually did it!",
					"Okay, that was further than I'd have gone.",
					"I'm telling everyone about this. Everyone.",
				},
			},
			{
				id = "race",
				label = "Race them to the corner",
				minAge = 5,
				maxAge = 12,
				minBond = ALWAYS,
				bond = 3,
				stats = { happiness = 2, health = 1 },
				lines = {
					"Best of three. I wasn't ready that time.",
					"You went early! That doesn't count.",
					"Again. Come on, again.",
				},
			},
			{
				-- Costs bond and pays happiness, and it is here because a street with no
				-- way to fall out with anybody on it is not a street, it is a lobby.
				id = "fall_out",
				label = "Fall out over nothing",
				minAge = 8,
				maxAge = 16,
				minBond = ALWAYS,
				bond = -5,
				stats = { happiness = 1 },
				lines = {
					"Fine. Go home then.",
					"Whatever. I didn't even want to play.",
					"Don't bother knocking tomorrow.",
				},
			},
			{
				id = "walk_school",
				label = "Walk to school together",
				minAge = 6,
				maxAge = 17,
				minBond = 15,
				bond = 4,
				ask = true,
				walksTo = "school",
				lines = {
					"I'll wait on the wall for you. Don't be slow.",
					"Long way or short way? Long way.",
					"You're carrying my bag for the hill bit.",
				},
				refusedLines = {
					"Suit yourself. The long way's the best bit anyway.",
					"Rain's coming in. Maybe better not.",
					"Another time then. Don't be late.",
				},
				arrivalLines = {
					"Here we are. Reckon you could beat me to the gate?",
					"Right, you're handed over. Mind the teacher with the whistle.",
					"Made it. See you after last bell.",
				},
			},
			{
				id = "walk_park",
				label = "Walk to the park together",
				minAge = 5,
				maxAge = 17,
				minBond = 25,
				bond = 4,
				stats = { happiness = 3 },
				ask = true,
				walksTo = "park",
				lines = {
					"Race you to the far gate. No, that's cheating, the far gate.",
					"I found a new thing at the park. You have to see it.",
					"Bring a coat. We're staying till the lights come on.",
				},
				refusedLines = {
					"Fine. I'll find somebody who's not boring.",
					"Another day. I'm waiting for someone.",
				},
				arrivalLines = {
					"See? The swings do that thing. Watch.",
					"We're here. Don't tell your mum about the hill bit.",
					"Park's ours now. Nobody else is about.",
				},
			},
			{
				id = "cover",
				label = "Ask them to cover for you",
				minAge = 12,
				maxAge = 17,
				minBond = 40,
				bond = -1,
				stats = { happiness = 2 },
				ask = true,
				lines = {
					"You were here all afternoon. Obviously.",
					"I'll say it, but you owe me a big one.",
				},
				refusedLines = {
					"No. I'm not lying to your mum, she's terrifying.",
					"Ask me something else. Not that.",
				},
			},
			-- The ladder. Three rows across fourteen years, and they are the only rows on
			-- this list that change what somebody *is* rather than what they will do.
			--
			-- On the street it is made of the two things that actually decide a childhood
			-- friendship: which house you knock at, and who you are still out with when
			-- everyone else has gone in.
			{
				id = "know_names",
				label = "Learn each other's names",
				minAge = 4,
				maxAge = 17,
				minBond = 10,
				bond = 3,
				stats = { happiness = 1 },
				gives = "known",
				lines = {
					"I've seen you loads. I never knew that was your name.",
					"Right. I'll shout that up at your window then.",
					"Good name. Better than mine.",
				},
			},
			{
				id = "call_for_them",
				label = "Call for them every single day",
				minAge = 5,
				maxAge = 17,
				minBond = 35,
				bond = 6,
				stats = { happiness = 3 },
				needsTie = "known",
				gives = "friend",
				lines = {
					"You're always at that door. My mum says you live here now.",
					"Same time tomorrow. And the day after. Obviously.",
					"I wait by the window for you. Don't tell anyone I said that.",
				},
			},
			{
				id = "streetlights",
				label = "Stay out until the streetlights come on",
				minAge = 7,
				maxAge = 17,
				minBond = 70,
				bond = 8,
				stats = { happiness = 4, health = -1 },
				needsTie = "friend",
				gives = "closest",
				lines = {
					"We're both getting shouted at for this. Worth it.",
					"That's the light on. One more minute. One.",
					"Whoever you are when we're old -- this. Remember this bit.",
				},
			},
			-- The payoff, and the reason the rungs are worth climbing rather than just
			-- worth having. Only ever on the panel of somebody who is already a friend.
			{
				id = "back_you_up",
				label = "Have them back you up",
				minAge = 8,
				maxAge = 17,
				minBond = 45,
				bond = 4,
				stats = { happiness = 3, health = 1 },
				needsTie = "friend",
				lines = {
					"I was standing right there the whole time. Obviously.",
					"They're not going to say anything to you with me here.",
					"You don't even have to ask me that. Ever.",
				},
			},
		},
	},
	{
		-- School. The one archetype that ends -- they age out at seventeen with the
		-- school itself, exactly as Rae does, because a classmate you never saw again
		-- after the last day is what a classmate mostly is.
		id = "classmate",
		placeId = "school",
		minAge = 6,
		maxAge = 17,
		minAgeOffset = -1,
		maxAgeOffset = 1,
		minHeight = 0.94,
		maxHeight = 1.04,
		startingBond = 0,
		busyLines = {
			"Can't, I've got a thing. Later!",
			"Sorry -- late already. Catch me tomorrow.",
			"Not today. Ask me again, though.",
		},
		contextualLines = {
			morning = {
				"Hey! Did you finish the homework?",
				"Rough morning. Didn't sleep well.",
				"See you at lunch?",
			},
			onShift = {
				"You're working? That's awesome!",
				"What do you do there? Tell me about it!",
				"Good luck with the long hours!",
			},
			unemployed = {
				"What are you doing now that you're not in school?",
				"Must be nice to sleep in.",
				"School's better than nothing, right?",
			},
		},
		offers = {
			-- The relationship block, shared by every archetype so whoever you are talking
			-- to can be talked to at any depth, driven apart, and mended. Written first
			-- because the panel sorts by what a row asks of the bond and throws the tail
			-- away: at the bottom of the range this is what somebody still has.
			{
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 5,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				lines = {
					"Nothing doing this lesson. You want to just... not?",
					"It's quieter back here. I like it back here.",
					"I'll talk to you. The register can wait.",
				},
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				lines = {
					"Not talking to you today. Ask me tomorrow.",
					"Whatever. I don't even know you.",
				},
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				lines = {
					"Go sit somewhere else.",
					"I saw you. I decided not to say anything.",
				},
			},
			{
				id = "make_right",
				label = "Try to make it right",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -1,
				bond = 8,
				ask = true,
				lines = {
					"Fine. I'll sit with you again. Don't make it weird.",
				},
				refusedLines = {
					"I'm still mad. Ask me again later.",
					"No. I'm having lunch with other people.",
				},
			},
			{
				id = "sit_with",
				label = "Sit with them at lunch",
				minAge = 6,
				maxAge = 17,
				minBond = ALWAYS,
				bond = 3,
				stats = { happiness = 2 },
				lines = {
					"Shove up, then. There's room.",
					"You can have my crusts. I'm being generous.",
					"Good, I was going to have to sit on my own.",
				},
			},
			{
				-- Buys you the afternoon and costs you the thing school is for. The
				-- clearest small version of what this whole game is about.
				id = "copy",
				label = "Copy their homework",
				minAge = 9,
				maxAge = 17,
				minBond = ALWAYS,
				bond = -2,
				stats = { happiness = 2, smarts = -1 },
				lines = {
					"Change some of the words. Don't be obvious.",
					"Last time. I mean it this time.",
					"If we both get it wrong they'll know, you know.",
				},
			},
			{
				id = "explain",
				label = "Explain it to them",
				minAge = 8,
				maxAge = 17,
				minBond = 0,
				bond = 4,
				stats = { smarts = 2 },
				lines = {
					"Oh. OH. Why didn't they just say that?",
					"Say it again slower and I've got it.",
					"You're better at this than the teacher is.",
				},
			},
			{
				id = "team",
				label = "Pick them for your team",
				minAge = 6,
				maxAge = 14,
				minBond = ALWAYS,
				bond = 5,
				stats = { happiness = 1 },
				lines = {
					"Really? Yes. Yes!",
					"Nobody ever picks me first. Nobody.",
					"You won't regret it. Probably.",
				},
			},
			{
				id = "notes",
				label = "Ask to borrow their notes",
				minAge = 11,
				maxAge = 17,
				minBond = 25,
				bond = -1,
				stats = { smarts = 2 },
				ask = true,
				lines = {
					"Back to me before the test. Before.",
					"They're a mess, but they're all there.",
				},
				refusedLines = {
					"I need them. Sorry -- I actually need them.",
					"Ask literally anyone else. I'm behind too.",
				},
			},
			{
				id = "after_school",
				label = "Go into town after school",
				minAge = 13,
				maxAge = 17,
				minBond = 35,
				bond = 5,
				stats = { happiness = 3, smarts = -1 },
				lines = {
					"We're going to be so late back. Come on.",
					"Best afternoon in ages, that.",
					"Same again Friday. Say yes.",
				},
			},
			-- The ladder, in the one place where a friendship has a shape everybody
			-- recognises: a seat, a seat kept for you, and the thing you only tell one
			-- person. School is also the one archetype the ladder can *run out* on --
			-- classmates age out at seventeen with the school, so a closest friend made
			-- here is one you will lose touch with, and the slot they were holding
			-- quietly reopens. That is not a bug in the cap; that is what leaving
			-- school is.
			{
				id = "sit_next",
				label = "Sit next to them, not just near them",
				minAge = 6,
				maxAge = 17,
				minBond = 10,
				bond = 3,
				stats = { happiness = 1 },
				gives = "known",
				lines = {
					"You can, yeah. Nobody sits there anyway.",
					"Move up then. Go on.",
					"I was hoping you would, actually.",
				},
			},
			{
				id = "save_seat",
				label = "Save each other a seat every day",
				minAge = 7,
				maxAge = 17,
				minBond = 35,
				bond = 6,
				stats = { happiness = 3 },
				needsTie = "known",
				gives = "friend",
				lines = {
					"Bag's on it. It's always going to be on it.",
					"I got told off holding that for you. Still held it.",
					"Don't be weird about it, but -- every day, yeah.",
				},
			},
			{
				id = "tell_them",
				label = "Tell them the thing you've told nobody",
				minAge = 11,
				maxAge = 17,
				minBond = 70,
				bond = 8,
				stats = { happiness = 4 },
				needsTie = "friend",
				gives = "closest",
				lines = {
					"I'm not telling anyone. Not ever. You know that.",
					"Thanks for -- yeah. For picking me to say it to.",
					"Right. My turn then. Sit down for this one.",
				},
			},
			{
				id = "study_properly",
				label = "Actually study with them",
				minAge = 11,
				maxAge = 17,
				minBond = 45,
				bond = 4,
				stats = { smarts = 4, happiness = -1 },
				needsTie = "friend",
				lines = {
					"Four hours. We did four hours. I feel ill.",
					"You explain that bit, I'll do the rest. Deal.",
					"I'd never have got through that on my own.",
				},
			},
			{
				id = "walk_crossing",
				label = "Walk to the crossing with them",
				minAge = 7,
				maxAge = 16,
				minBond = 20,
				bond = 4,
				ask = true,
				walksTo = "crossing",
				lines = {
					"Your way's my way for a bit. Come on.",
					"I'll walk you as far as the lights.",
					"Race you to the crossing -- no, that's cheating.",
				},
				refusedLines = {
					"Fair enough. See you tomorrow.",
					"My mum's picking me up, so --",
					"Another day. I've got football.",
				},
				arrivalLines = {
					"Lights are changing. I'll leave you here.",
					"There's the crossing. Same tomorrow?",
					"Right, this is where I go back. Walk you home properly sometime.",
				},
			},
			{
				id = "walk_library",
				label = "Walk to the library together",
				minAge = 8,
				maxAge = 17,
				minBond = 30,
				bond = 4,
				stats = { smarts = 2, happiness = 1 },
				ask = true,
				walksTo = "library",
				lines = {
					"I've got to return something. Come keep me company.",
					"We could actually get the work done, if we go now.",
					"They got new books in. I saw the crate.",
				},
				refusedLines = {
					"Alright. Don't copy all my notes.",
					"Another time. I've got football practice.",
				},
				arrivalLines = {
					"Quiet corner's ours. Right, questions?",
					"Here we are. Ten minutes of work, then we look at the good ones.",
					"See the new ones? Told you about the crate.",
				},
			},
		},
	},
	{
		-- The people who are always in the shop. Older than you by a generation or two,
		-- around from before you can remember to the end, and the only townsfolk a whole
		-- life can be spent getting to know.
		--
		-- "From before you can remember" is now literally true rather than nearly true.
		-- They are the reason there is anybody on the road at all in the first years: the
		-- street kids are at your own front door, and a regular walking the length of the
		-- route graph from the shop is the only thing in the game that makes the ground
		-- between two buildings read as a place people pass through rather than as the gap
		-- between two crowds. That only works because the leash is longer than the town.
		id = "regular",
		placeId = "store",
		minAge = 0,
		maxAge = 999,
		minAgeOffset = 14,
		maxAgeOffset = 48,
		minHeight = 0.95,
		maxHeight = 1.06,
		startingBond = 0,
		busyLines = {
			"Another time. I'm halfway through my list.",
			"Not today, thank you. Good to see you though.",
			"I'm in a rush, of all things. At my age.",
		},
		contextualLines = {
			morning = {
				"Morning. Beautiful day, isn't it?",
				"Out for a walk? Take your time.",
				"The weather's turned. Nice change.",
			},
			onShift = {
				"Working hard? Don't forget to take a break.",
				"How's the job treating you?",
				"All that work, and you're still standing. Respect.",
			},
			unemployed = {
				"Looking for work? I heard the factory is hiring.",
				"Not working today? Enjoy the freedom while it lasts.",
				"The job market's tough, but you'll find something.",
			},
			atHome = {
				"Nice place you got there.",
				"Home sweet home, eh?",
				"First time in your own place?",
			},
		},
		offers = {
			-- The relationship block, shared by every archetype so whoever you are talking
			-- to can be talked to at any depth, driven apart, and mended. Written first
			-- because the panel sorts by what a row asks of the bond and throws the tail
			-- away: at the bottom of the range this is what somebody still has.
			{
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 5,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				lines = {
					"No rush. Talk to me, I'm in no hurry.",
					"I've got all day, and a good deal of it's already gone. What's new?",
					"Go on then, sit yourself down. I'm not going anywhere.",
				},
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				lines = {
					"Right. I see how it is.",
					"Fine. I won't be the one to break the silence.",
				},
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				lines = {
					"Hmph. Some people.",
					"I'll just stand here, then. We both know the rules.",
				},
			},
			{
				id = "make_right",
				label = "Try to make it right",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -1,
				bond = 8,
				ask = true,
				lines = {
					"Well. That took some doing. I accept.",
				},
				refusedLines = {
					"I've had a lifetime of making things right. Not this time.",
					"Give it more than a day. That's all I'll say.",
				},
			},
			-- The toddler band. An adult stranger and a child who cannot talk have exactly
			-- one thing between them and it is being made a fuss of in the street, so that
			-- is what these two are -- warm, brief, and gone by five, when "Say hello"
			-- takes over and the rest of a lifetime's worth of rows starts opening up.
			--
			-- The second one is the same verb the player already has with their mother
			-- ("Show her what you found"), pointed at somebody who is not family. That is
			-- the smallest statement this game can make that the world is bigger than the
			-- house, and it costs two rows to make it.
			{
				id = "made_a_fuss",
				label = "Let them make a fuss of you",
				minAge = 0,
				maxAge = 4,
				minBond = ALWAYS,
				bond = 2,
				stats = { happiness = 2 },
				lines = {
					"Haven't you grown. They grow while you're not looking.",
					"Oh, look at you. Look at YOU.",
					"Hello, trouble. Yes, I mean you.",
				},
			},
			{
				id = "show_them",
				label = "Show them what you're holding",
				minAge = 0,
				maxAge = 4,
				minBond = ALWAYS,
				bond = 3,
				stats = { happiness = 2 },
				lines = {
					"Is that right. That's the best one I've seen all week.",
					"Very good. Mind you don't drop it in the road.",
					"For me? No -- you keep hold of it. You keep hold.",
				},
			},
			{
				id = "hello",
				label = "Say hello",
				minAge = 5,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 2,
				stats = { happiness = 1 },
				lines = {
					"Hello there. You're getting tall.",
					"Well, hello. Haven't seen you in a while.",
					"Afternoon. Miserable weather, isn't it.",
				},
			},
			{
				id = "hand",
				label = "Give them a hand",
				minAge = 8,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 4,
				stats = { happiness = -1 },
				lines = {
					"That's kind. Most wouldn't have stopped.",
					"Thank you. My back's not what it was.",
					"There. Two minutes of your life well spent.",
				},
			},
			{
				id = "weather",
				label = "Let them talk",
				minAge = 5,
				maxAge = 999,
				minBond = 0,
				bond = 3,
				stats = { happiness = 1 },
				lines = {
					"-- and that's the third time this month. Third!",
					"Anyway. You didn't come here for all that.",
					"You're a good listener, you know that?",
				},
			},
			{
				id = "advice",
				label = "Ask what they would have done",
				minAge = 16,
				maxAge = 999,
				minBond = 30,
				bond = 2,
				stats = { smarts = 2 },
				lines = {
					"At your age? Nothing sensible, that's for certain.",
					"Wait a week. It'll look different in a week.",
					"Do the boring thing. It's boring because it works.",
				},
			},
			{
				id = "spot_me",
				label = "Ask them to spot you",
				minAge = 18,
				maxAge = 999,
				minBond = 50,
				bond = -2,
				money = 120,
				ask = true,
				lines = {
					"Go on then. Don't make a habit of it.",
					"Here. I've been where you are.",
				},
				refusedLines = {
					"I would if I had it. I haven't got it.",
					"No. And I'd think less of myself for saying yes.",
				},
			},
			-- The ladder. This is the only one that can run the whole length of a life --
			-- a regular is in the shop from the year you can walk to it to the year you
			-- stop -- so the rungs are spread wide on purpose. Becoming the closest friend
			-- of somebody thirty years older than you takes decades of turning up, and it
			-- ought to.
			{
				id = "know_regular",
				label = "Get properly introduced",
				minAge = 6,
				maxAge = 999,
				minBond = 10,
				bond = 3,
				stats = { happiness = 1 },
				gives = "known",
				lines = {
					"Well. Now I've got to remember it, haven't I.",
					"I've nodded at you for a year. About time.",
					"Pleasure. I'm here most days, as you've noticed.",
				},
			},
			{
				id = "outside_shop",
				label = "See them somewhere that isn't the shop",
				minAge = 14,
				maxAge = 999,
				minBond = 35,
				bond = 6,
				stats = { happiness = 3 },
				needsTie = "known",
				gives = "friend",
				lines = {
					"Funny, isn't it. Took us years to leave that aisle.",
					"Same again next week. I'll be the one already sat down.",
					"I've got people I've known forty years I've never done this with.",
				},
			},
			{
				id = "keep_up",
				label = "Keep up with them when you don't have to",
				minAge = 20,
				maxAge = 999,
				minBond = 70,
				bond = 8,
				stats = { happiness = 4 },
				needsTie = "friend",
				gives = "closest",
				lines = {
					"You'd have stopped coming years ago if you were going to.",
					"There's not many left who'd bother. You bother.",
					"I'll say the thing I don't say: I'm glad it's you.",
				},
			},
			{
				id = "put_aside",
				label = "Collect what they put aside for you",
				minAge = 12,
				maxAge = 999,
				minBond = 45,
				bond = 3,
				money = 40,
				needsTie = "friend",
				lines = {
					"Been under the counter with your name on a week.",
					"Don't argue. It was going in the bin otherwise.",
					"Take it. You'd do the same and we both know it.",
				},
			},
			{
				id = "walk_gate",
				label = "Walk you to the gate",
				minAge = 12,
				maxAge = 999,
				minBond = 25,
				bond = 4,
				ask = true,
				walksTo = "gate",
				lines = {
					"Just locking up. Walk you to your gate?",
					"I'm heading your way anyway. Come on.",
					"You look done in. I'll see you home.",
				},
				refusedLines = {
					"Alright. Goodnight then.",
					"Suit yourself. Stay out of trouble.",
					"Another time. I've got the float to count.",
				},
				arrivalLines = {
					"Here's your gate. That's me sorted too.",
					"Right, home you go. Goodnight.",
					"There we are. Say hello to whoever's in for me.",
				},
			},
			{
				id = "walk_bakery",
				label = "Walk to the bakery with them",
				minAge = 18,
				maxAge = 999,
				minBond = 35,
				bond = 4,
				stats = { happiness = 2, health = -1 },
				ask = true,
				walksTo = "bakery",
				lines = {
					"I'm getting the good bread while it's there. Come on.",
					"They save me the end of the sourdough. Walking by anyway.",
					"Treat yourself. That's what bakeries are for.",
				},
				refusedLines = {
					"Another time. I'm watching the figure, these days.",
					"Alright. I'll say you were there in spirit.",
				},
				arrivalLines = {
					"Right. Today's the day for a sticky bun, I can tell.",
					"Here we are. Half for you, half for me, no arguments.",
					"That's the smell. Worth the walk, every time.",
				},
			},
		},
	},
	{
		-- Work. The one archetype you cannot meet before you have a life of your own,
		-- which is what makes it the first evidence that adulthood has people in it.
		id = "coworker",
		placeId = "office",
		minAge = 16,
		maxAge = 999,
		minAgeOffset = -3,
		maxAgeOffset = 24,
		minHeight = 0.94,
		maxHeight = 1.07,
		startingBond = 0,
		busyLines = {
			"Snowed under. Grab me tomorrow?",
			"On a deadline. Sorry -- honestly, sorry.",
			"Not now. Ask me when this is off my desk.",
		},
		offers = {
			-- The relationship block, shared by every archetype so whoever you are talking
			-- to can be talked to at any depth, driven apart, and mended. Written first
			-- because the panel sorts by what a row asks of the bond and throws the tail
			-- away: at the bottom of the range this is what somebody still has.
			{
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 5,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				lines = {
					"Water-cooler chat. That's the height of my ambition for the hour.",
					"I could do with five minutes of not looking at my screen. Talk to me.",
					"This is the best part of my day, and I know how sad that sounds.",
				},
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				lines = {
					"Right. Keeping it professional, then. Fine.",
					"Fine. I can take a hint.",
				},
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				lines = {
					"I'll just get on with my work, then.",
					"Interesting. That's your answer, is it. Interesting.",
				},
			},
			{
				id = "make_right",
				label = "Try to make it right",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -1,
				bond = 8,
				ask = true,
				lines = {
					"Alright. Water under the bridge. Just don't make a habit of it.",
				},
				refusedLines = {
					"I'd rather we kept it at 'hello' for a bit.",
					"Not yet. I'm still getting over it. Weirdly.",
				},
			},
			{
				id = "morning",
				label = "Say morning",
				minAge = 16,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 2,
				stats = { happiness = 1 },
				lines = {
					"Morning. Is it Friday? It's not, is it.",
					"Morning! You look how I feel.",
					"Hello. Kettle's just gone on, if you're quick.",
				},
			},
			{
				id = "lunch",
				label = "Take lunch with them",
				minAge = 16,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 4,
				stats = { happiness = 2 },
				lines = {
					"Out, not at the desk. I insist.",
					"Same time tomorrow? Good.",
					"That's the most I've laughed all week.",
				},
			},
			{
				id = "cover_work",
				label = "Take some of their work",
				minAge = 18,
				maxAge = 999,
				minBond = 0,
				bond = 6,
				stats = { happiness = -2 },
				lines = {
					"You didn't have to do that. I won't forget it.",
					"Right -- I owe you. Properly owe you.",
					"You've just given me my evening back.",
				},
			},
			{
				id = "vent",
				label = "Complain about the place",
				minAge = 18,
				maxAge = 999,
				minBond = 20,
				bond = 3,
				stats = { happiness = 2 },
				lines = {
					"Thank you. I thought it was just me.",
					"Say that a bit louder, go on.",
					"One day. One day we're both walking out.",
				},
			},
			{
				id = "swap_shift",
				label = "Ask them to swap a shift",
				minAge = 18,
				maxAge = 999,
				minBond = 40,
				bond = -1,
				stats = { happiness = 2 },
				ask = true,
				lines = {
					"Go on. You'd do the same for me.",
					"Fine, but I'm having your Friday.",
				},
				refusedLines = {
					"I can't this week. Any other week.",
					"Sorry. I've got something on I can't move.",
				},
			},
			{
				id = "tide_over",
				label = "Ask them to tide you over",
				minAge = 20,
				maxAge = 999,
				minBond = 55,
				bond = -2,
				money = 250,
				ask = true,
				lines = {
					"Payday. Not before, not after.",
					"Take it. And don't look like that about it.",
				},
				refusedLines = {
					"I'd rather not mix that with this. Sorry.",
					"I'm as skint as you are. Genuinely.",
				},
			},
			-- The ladder, and at work it is made of exactly one thing: whether any of it
			-- survives outside the building. A colleague you have never seen in daylight
			-- is a colleague, however many years of it there have been.
			{
				id = "know_coworker",
				label = "Learn who they actually are",
				minAge = 16,
				maxAge = 999,
				minBond = 10,
				bond = 3,
				stats = { happiness = 1 },
				gives = "known",
				lines = {
					"Two years sat there and you're the first to ask. Cheers.",
					"That's me. Not very exciting, but that's me.",
					"Right -- and now I've got to ask you back, haven't I.",
				},
			},
			{
				id = "out_of_building",
				label = "Get out of the building with them",
				minAge = 17,
				maxAge = 999,
				minBond = 35,
				bond = 6,
				stats = { happiness = 3 },
				needsTie = "known",
				gives = "friend",
				lines = {
					"See, this is better. Nobody's listening out here.",
					"We should have been doing this the whole time.",
					"Same tomorrow. I'm not eating at that desk again.",
				},
			},
			{
				id = "say_it_out_loud",
				label = "Say what you actually think of this place",
				minAge = 19,
				maxAge = 999,
				minBond = 70,
				bond = 8,
				stats = { happiness = 4 },
				needsTie = "friend",
				gives = "closest",
				lines = {
					"You could get us both sacked saying that. Say more.",
					"I've thought it for years. I've never said it.",
					"Whatever happens to this job -- we keep this, right?",
				},
			},
			{
				id = "word_for_you",
				label = "Have them put in a word for you",
				minAge = 19,
				maxAge = 999,
				minBond = 45,
				bond = 2,
				stats = { smarts = 2 },
				money = 60,
				needsTie = "friend",
				lines = {
					"Already did it. Last week, before you asked.",
					"I told them the truth about you. That's the good version.",
					"They listen to me about one thing a year. I spent it.",
				},
			},
			{
				id = "walk_shop",
				label = "Walk to the shop after work",
				minAge = 16,
				maxAge = 999,
				minBond = 30,
				bond = 4,
				ask = true,
				walksTo = "store",
				lines = {
					"Downstairs when you're done? I could do with the air.",
					"Fancy a walk to the shop before the bus?",
					"I'm going that way. Come and keep me company.",
				},
				refusedLines = {
					"No worries. I'll see you tomorrow.",
					"Alright. I'd better not keep you.",
					"Another day then. The deadline's catching up with all of us.",
				},
				arrivalLines = {
					"Here we are. Right, what are you after?",
					"Shop's here. That walk fixed my head.",
					"Made it. Get yourself something cold.",
				},
			},
			{
				id = "walk_gym",
				label = "Walk to the gym after work",
				minAge = 18,
				maxAge = 999,
				minBond = 40,
				bond = 4,
				stats = { health = 1 },
				ask = true,
				walksTo = "gym",
				lines = {
					"I'm going down the gym. You look like you need the walk.",
					"Same time as usual? You were good last week.",
					"Come on. A few circuits and we've earned the evening.",
				},
				refusedLines = {
					"No worries. I'll tell you what I did tomorrow.",
					"Another time. I can barely lift my phone today.",
				},
				arrivalLines = {
					"Here we are. Let's get it over with, together.",
					"Made it. You've got the next set, go on.",
					"That walk's half the workout. The other half's in there.",
				},
			},
		},
	},
	{
		-- People roughly your own age, around town. Deliberately the vaguest of the five,
		-- because that is what most of the people in a life are: not from school, not from
		-- work, not related to you, and known anyway because you kept running into them.
		id = "local",
		placeId = "store",
		minAge = 12,
		maxAge = 999,
		minAgeOffset = -2,
		maxAgeOffset = 8,
		minHeight = 0.94,
		maxHeight = 1.06,
		startingBond = 0,
		busyLines = {
			"Can't stop -- I'm late for something.",
			"Another time, yeah? Properly, though.",
			"Not today. I'm no use to anyone today.",
		},
		offers = {
			-- The relationship block, shared by every archetype so whoever you are talking
			-- to can be talked to at any depth, driven apart, and mended. Written first
			-- because the panel sorts by what a row asks of the bond and throws the tail
			-- away: at the bottom of the range this is what somebody still has.
			{
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 5,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				lines = {
					"Here we are again. Good to see you out.",
					"No plans, nowhere to be. Perfect time to talk.",
					"I was hoping I'd catch you. I mean that.",
				},
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				lines = {
					"Oh. I thought we were past that. Clearly not.",
					"Right. I'll take that as a sign, then.",
				},
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				lines = {
					"We'll make this brief, then.",
					"I see. Well. I'll be going.",
				},
			},
			{
				id = "make_right",
				label = "Try to make it right",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -1,
				bond = 8,
				ask = true,
				lines = {
					"Thank you for saying that. I'd rather not lose you over it.",
				},
				refusedLines = {
					"Give me a bit. I need to think about it.",
					"I'm not ready yet. Ask me another time.",
				},
			},
			{
				id = "chat",
				label = "Stop and talk",
				minAge = 12,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 3,
				stats = { happiness = 1 },
				lines = {
					"I was hoping I'd run into someone.",
					"Look at you. How long has it been?",
					"Five minutes. Then I really do have to go.",
				},
			},
			{
				id = "walk_with",
				label = "Walk part of the way with them",
				minAge = 12,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 4,
				ask = true,
				walksTo = "home",
				lines = {
					"Go on then, I'll go the long way with you.",
					"This is nicer than the bus, I'll give you that.",
					"Right -- this is me. That was good, that.",
				},
				refusedLines = {
					"Fair enough. Take care of yourself.",
					"Alright, I'll see you around.",
					"Another time. I've got to run an errand.",
				},
				arrivalLines = {
					"Here we are, then. Your doorstep.",
					"That's the front path. Look after yourself.",
					"Home sweet home. I'll be in the shop if you need me.",
				},
			},
			{
				id = "walk_garage",
				label = "Walk to the garage with them",
				minAge = 16,
				maxAge = 999,
				minBond = 30,
				bond = 4,
				stats = { happiness = 1 },
				ask = true,
				walksTo = "garage",
				lines = {
					"I've got to pick something up from the garage. Walk with me?",
					"They said it'd be ready today. Come see it before I do.",
					"Help me carry? There's a box involved. There's always a box.",
				},
				refusedLines = {
					"Alright. It's just a box anyway.",
					"Another time. I'm waiting on a phone call.",
				},
				arrivalLines = {
					"Here we are. Right -- the box. You're not getting out of it.",
					"That's him. Morning. -- See? Exactly as exciting as I said.",
					"We're here. Thanks for the company. Better than doing it alone.",
				},
			},
			{
				id = "favour",
				label = "Do them a favour",
				minAge = 14,
				maxAge = 999,
				minBond = 0,
				bond = 6,
				stats = { happiness = -1 },
				lines = {
					"You are a lifesaver. An actual lifesaver.",
					"I'll pay you back in kind. Watch me.",
					"Nobody else said yes, you know.",
				},
			},
			{
				id = "confide",
				label = "Tell them how it is going",
				minAge = 18,
				maxAge = 999,
				minBond = 35,
				bond = 5,
				stats = { happiness = 3 },
				lines = {
					"That sounds hard. I mean it, that sounds hard.",
					"You don't have to be fine about it with me.",
					"Well I'm glad you told someone. Even me.",
				},
			},
			{
				id = "borrow",
				label = "Ask to borrow something",
				minAge = 16,
				maxAge = 999,
				minBond = 45,
				bond = -1,
				money = 90,
				ask = true,
				lines = {
					"Keep it as long as you need.",
					"Sure. Bring it back in one piece.",
				},
				refusedLines = {
					"Ah -- I'd rather not. It's a bit of a thing.",
					"Not that one. Sorry. Ask me another time.",
				},
			},
			-- The ladder, and here it is made of nothing in particular, which is the
			-- honest version for this archetype: there is no shared desk and no shared
			-- classroom, so the only thing holding it together is that both of you kept
			-- turning up. That makes it the hardest of the five to climb by accident and
			-- the most deliberate when it happens.
			{
				id = "know_local",
				label = "Swap names properly",
				minAge = 12,
				maxAge = 999,
				minBond = 10,
				bond = 3,
				stats = { happiness = 1 },
				gives = "known",
				lines = {
					"Ha -- we've been nodding at each other for months.",
					"Good. I was going to have to guess eventually.",
					"Now I have to actually say hello. Thanks for that.",
				},
			},
			{
				id = "make_a_plan",
				label = "Make an actual plan with them",
				minAge = 14,
				maxAge = 999,
				minBond = 35,
				bond = 6,
				stats = { happiness = 3 },
				needsTie = "known",
				gives = "friend",
				lines = {
					"A time and a place. Look at us, like proper people.",
					"I'll be there. I'm never there, but I'll be there.",
					"Bumping into each other was fine. This is better.",
				},
			},
			{
				id = "kept_turning_up",
				label = "Still be there years later",
				minAge = 22,
				maxAge = 999,
				minBond = 70,
				bond = 8,
				stats = { happiness = 4 },
				needsTie = "friend",
				gives = "closest",
				lines = {
					"Everyone else drifted. You didn't. I noticed.",
					"We had no reason to keep this going. We kept it going.",
					"You're the one I'd call. That's all I'm saying.",
				},
			},
			{
				id = "turn_up_for_you",
				label = "Have them turn up for you",
				minAge = 16,
				maxAge = 999,
				minBond = 45,
				bond = 4,
				stats = { happiness = 4, health = 1 },
				needsTie = "friend",
				lines = {
					"You didn't even have to ask. I heard, so I came.",
					"I'm not going anywhere today. Put the kettle on.",
					"Whatever it is. I'm here for whatever it is.",
				},
			},
		},
	},
	-- People your own age, in adult life.
	--
	-- This archetype exists because the world had a hole in it that only shows up when you
	-- go looking for somebody to build a life with. Count the age offsets on the five
	-- above: the two that are genuinely your own age -- `street` and `classmate` -- both
	-- **end at seventeen**. After that the town is people fourteen to forty-eight years
	-- older, plus whichever coworker or local happened to roll a small number.
	--
	-- So adult life had no guaranteed peers at all. Not "few" -- none guaranteed, and how
	-- many you got was a property of one fixed seed rather than of anything the player did.
	-- A life meant to be built around a closest friend could hand one player six candidates
	-- and another none, and neither would ever be told why. That is not difficulty, it is a
	-- world that quietly differs from the one the rules describe.
	--
	-- Sixteen rather than eighteen because that is when the rest of adult life opens here --
	-- `coworker` starts at sixteen and so do jobs -- and a peer who arrives two years after
	-- your first job is a peer who missed the part where you needed one.
	--
	-- At the store rather than the office, deliberately. `coworker` already owns "people you
	-- know because you are both paid to be there", and that comes with a reason to talk
	-- built in. These are people you know for no reason except that you keep being in the
	-- same places, which is where most adult friendships actually come from.
	{
		id = "peer",
		placeId = "store",
		minAge = 16,
		maxAge = 999,
		-- The tightest span of any archetype, because "my own age" is the entire point and
		-- a spread of eight would put a thirty-year-old in the pool at twenty-two.
		minAgeOffset = -2,
		maxAgeOffset = 2,
		minHeight = 0.94,
		maxHeight = 1.07,
		startingBond = 0,
		busyLines = {
			"Can't stop -- I'm late for the thing I'm always late for.",
			"Not now, sorry. Ask me when I look less like this.",
			"Rain check. I've got about four minutes and no brain.",
		},
		offers = {
			-- The relationship block, shared by every archetype so whoever you are talking
			-- to can be talked to at any depth, driven apart, and mended. Written first
			-- because the panel sorts by what a row asks of the bond and throws the tail
			-- away: at the bottom of the range this is what somebody still has.
			{
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 5,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				lines = {
					"No agenda. Just catching up. That's allowed, right?",
					"Say something interesting so I can tell people I have plans.",
					"Good to run into you. I mean it, that's not a reflex.",
				},
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				lines = {
					"Okay. I'll take that as the whole conversation.",
					"Right, well. I know when I'm not wanted.",
				},
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				lines = {
					"I'm not doing this with you today.",
					"Yeah. I saw you. I saw you see me.",
				},
			},
			{
				id = "make_right",
				label = "Try to make it right",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -1,
				bond = 8,
				ask = true,
				lines = {
					"That means something. I'm glad you said it.",
				},
				refusedLines = {
					"I'm not there yet. Don't rush it.",
					"You can't just say one thing and have it be fine.",
				},
			},
			{
				id = "peer_hello",
				label = "Say hello",
				minAge = 16,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 3,
				stats = { happiness = 1 },
				lines = {
					"Oh -- hello. I know you from somewhere, don't I?",
					"Hey. You're always in here, same as me.",
					"Hello, stranger. Sort of stranger.",
				},
			},
			{
				id = "peer_moan",
				label = "Complain about the same things",
				minAge = 16,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 4,
				stats = { happiness = 2 },
				lines = {
					"Right? RIGHT? Nobody else our age thinks it's mad.",
					"Oh, thank God. I thought it was just me.",
					"We should be allowed to complain professionally.",
				},
			},
			{
				id = "peer_go_along",
				label = "Go along to something with them",
				minAge = 17,
				maxAge = 999,
				minBond = 15,
				bond = 6,
				stats = { happiness = 3 },
				lines = {
					"Come. Say yes now, before you think about it.",
					"You'll like it. And if you don't, we'll leave.",
					"See, this is better than whatever you had on.",
				},
			},
			{
				id = "peer_late",
				label = "Stay out later than you meant to",
				minAge = 18,
				maxAge = 999,
				minBond = 30,
				bond = 6,
				stats = { happiness = 4, health = -2 },
				lines = {
					"One more. One. I have said that before, I know.",
					"It's not even late. It's early. That's different.",
					"We're going to regret this and I don't care.",
				},
			},
			{
				id = "peer_advice",
				label = "Ask what they would do",
				minAge = 18,
				maxAge = 999,
				minBond = 35,
				bond = 5,
				stats = { happiness = 2, smarts = 1 },
				lines = {
					"Honestly? I'd do the thing that scares you more.",
					"No idea. But I'd start by telling someone.",
					"Ask me again in ten years and I'll still guess.",
				},
			},
			-- The ladder. Made of the same stuff as `local`'s -- nothing holding it together but
			-- both of you turning up -- but it climbs earlier, because these are the people a
			-- life actually gets built with, and a rung you cannot reach until twenty-two puts
			-- the whole of early adulthood out of reach of it.
			{
				id = "know_peer",
				label = "Finally ask their name",
				minAge = 16,
				maxAge = 999,
				minBond = 10,
				bond = 3,
				stats = { happiness = 1 },
				gives = "known",
				lines = {
					"I'm glad you said. I'd got too far in to ask.",
					"Right, now we're obliged to acknowledge each other.",
					"Names. Very grown up of us.",
				},
			},
			{
				id = "peer_friends",
				label = "Ask them to be friends properly",
				minAge = 17,
				maxAge = 999,
				minBond = 30,
				bond = 6,
				stats = { happiness = 3 },
				needsTie = "known",
				gives = "friend",
				lines = {
					"Yes. Obviously yes. Was that hard to say?",
					"I already told people you were. Bit awkward otherwise.",
					"Good. I've got a shortage and you'll do nicely.",
				},
			},
			{
				id = "peer_closest",
				label = "Tell them they're the one you'd call",
				minAge = 19,
				maxAge = 999,
				minBond = 65,
				bond = 8,
				stats = { happiness = 4 },
				needsTie = "friend",
				gives = "closest",
				lines = {
					"Then call me. Any hour. I mean the bad hours too.",
					"You're mine as well. I thought that was established.",
					"Don't make it weird. But -- yeah. Same.",
				},
			},
			{
				id = "peer_carry",
				label = "Let them carry you through a bad stretch",
				minAge = 18,
				maxAge = 999,
				minBond = 45,
				bond = 4,
				stats = { happiness = 4, health = 1 },
				needsTie = "friend",
				lines = {
					"You'd do it for me. You have done it for me.",
					"I'm not keeping score. I'm just not going anywhere.",
					"Sit down. I'll deal with the rest of it.",
				},
			},
			{
				id = "walk_work",
				label = "Walk to work together",
				minAge = 16,
				maxAge = 999,
				minBond = 25,
				bond = 4,
				ask = true,
				walksTo = "work",
				lines = {
					"Same shift? Walk over together, save the air.",
					"I'll come by yours and we can go in together.",
					"You heading in? I'll walk with you.",
				},
				refusedLines = {
					"Alright, I'll see you inside.",
					"No worries. Don't want to be late.",
					"Another day. I've got to drop something off first.",
				},
				arrivalLines = {
					"Here we are. Work. The least good part of the day.",
					"Made it. Ready to earn our keep?",
					"Right, we're here. One of us has to make the tea.",
				},
			},
			{
				id = "walk_clinic",
				label = "Walk to the clinic with them",
				minAge = 16,
				maxAge = 999,
				minBond = 35,
				bond = 4,
				stats = { happiness = 2, health = 1 },
				ask = true,
				walksTo = "clinic",
				lines = {
					"I'm going to see someone at the clinic. I don't want to go in alone.",
					"They've asked me in for the results. Walk with me? I'll be fine, but --",
					"I've got an appointment. Company would help. It's just the walk there.",
				},
				refusedLines = {
					"Alright. I'll be fine. Thanks anyway.",
					"Another time. I've got to run an errand first.",
				},
				arrivalLines = {
					"Here we are. Thanks for coming with me. I'll see you after.",
					"That's the door. I'll be out before you know it.",
					"Right. I'm going in. -- It was good of you to come.",
				},
			},
		},
	},
	{
		-- People who hang out in the financial district. Bank tellers, office runners,
		-- the sort of person you pass every day on the walk to town and learn to
		-- recognise by their coat rather than their face.
		id = "city_worker",
		placeId = "bank",
		minAge = 16,
		maxAge = 999,
		minAgeOffset = -2,
		maxAgeOffset = 20,
		minHeight = 0.94,
		maxHeight = 1.07,
		startingBond = 0,
		busyLines = {
			"Lunch break's over. Catch me later?",
			"Running late already. I'll find you tomorrow.",
			"Not now -- the manager's watching. Sorry.",
		},
		offers = {
			{
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 5,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				lines = {
					"Staring out the window. The best part of the shift.",
					"Same as always. You?",
					"Tell me something good. I've had a morning of forms.",
				},
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				lines = {
					"Okay. I'll just go back to the desk.",
					"Right. Suit yourself.",
				},
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				lines = {
					"I'll pretend I didn't see that.",
					"Fine. I was going to ask you anyway.",
				},
			},
			{
				id = "make_right",
				label = "Try to make it right",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -1,
				bond = 8,
				ask = true,
				lines = {
					"Thanks. I was going to pretend it didn't happen, but -- thank you.",
				},
				refusedLines = {
					"I need a bit. Just -- tomorrow?",
					"Not today. I'm still working through it.",
				},
			},
			{
				id = "coffee_break",
				label = "Take a coffee break with them",
				minAge = 14,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 3,
				stats = { happiness = 2 },
				lines = {
					"Ten minutes. If the manager sees us I'm blaming you.",
					"I know a place around the corner. Cheap coffee, good pie.",
					"You look like you need a break. I do too.",
				},
			},
			{
				id = "walk_restaurant",
				label = "Walk to the restaurant with them",
				minAge = 16,
				maxAge = 999,
				minBond = 25,
				bond = 4,
				stats = { happiness = 2 },
				ask = true,
				walksTo = "restaurant",
				lines = {
					"I'm dying for a proper meal. Walk with me?",
					"There's a place near the office I like. Come on.",
					"My treat. You've earned it this week.",
				},
				refusedLines = {
					"Alright. Another time then.",
					"Suit yourself. I'll save you a seat.",
				},
				arrivalLines = {
					"Here we are. Right -- what are you having?",
					"Made it. Table for two? Or should I go sit at the bar?",
					"This place never lets me down. Same for you?",
				},
			},
			{
				id = "walk_cafe",
				label = "Walk to the cafe with them",
				minAge = 14,
				maxAge = 999,
				minBond = 20,
				bond = 3,
				stats = { happiness = 2 },
				ask = true,
				walksTo = "cafe",
				lines = {
					"I need caffeine. Walk with me to the cafe?",
					"Let's get out of the building for ten minutes.",
					"There's a new pastry I've been meaning to try. Come on.",
				},
				refusedLines = {
					"Alright. I'll go alone then.",
					"Another time. I've got paperwork.",
				},
				arrivalLines = {
					"Here we are. Order first -- I'm starving.",
					"Made it. What's your poison?",
					"Cafe's ours. Don't tell the boss we've been gone five minutes.",
				},
			},
			{
				id = "know_worker",
				label = "Learn their name",
				minAge = 12,
				maxAge = 999,
				minBond = 10,
				bond = 3,
				stats = { happiness = 1 },
				gives = "known",
				lines = {
					"Oh, we've never actually done that, have we?",
					"I've been standing here two years and you just noticed.",
					"Right. Now we're officially acquainted.",
				},
			},
			{
				id = "break_friend",
				label = "Take breaks with them properly",
				minAge = 14,
				maxAge = 999,
				minBond = 30,
				bond = 6,
				stats = { happiness = 3 },
				needsTie = "known",
				gives = "friend",
				lines = {
					"Same time tomorrow? Good. I was hoping you'd say yes.",
					"You're the only reason I look forward to coffee breaks.",
					"Nobody else here gets it. That's why it's us.",
				},
			},
			{
				id = "closest_worker",
				label = "Tell them something you haven't told anyone",
				minAge = 18,
				maxAge = 999,
				minBond = 65,
				bond = 8,
				stats = { happiness = 4 },
				needsTie = "friend",
				gives = "closest",
				lines = {
					"Nobody else knows this. That means something, right?",
					"Thanks for not... you know. Thanks for listening.",
					"This stays between us. Obviously.",
				},
			},
		},
	},
	{
		-- Young people around the sports facilities. Same energy as `peer`, but they
		-- hang in open spaces rather than at the till, and their life is measured in
		-- matches and games rather than shifts.
		id = "city_athlete",
		placeId = "soccer_field",
		minAge = 12,
		maxAge = 999,
		minAgeOffset = -3,
		maxAgeOffset = 5,
		minHeight = 0.92,
		maxHeight = 1.07,
		startingBond = 0,
		busyLines = {
			"Training's starting. I'll catch you after.",
			"Not now -- we're in the middle of a game.",
			"Give me five minutes. I'm about to go on.",
		},
		offers = {
			{
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 5,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				lines = {
					"Waiting for the rest of the team. You here often?",
					"Not much happening. Want to just... sit for a bit?",
					"Good day for it. The field's in great shape.",
				},
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				lines = {
					"Right. I'll just go find someone else.",
					"Whatever. I wasn't trying to talk.",
				},
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				lines = {
					"I see you. Don't pretend you didn't.",
					"Fine. I'll take my ball elsewhere.",
				},
			},
			{
				id = "make_right",
				label = "Try to make it right",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -1,
				bond = 8,
				ask = true,
				lines = {
					"Look, I didn't mean it like that. Sorry.",
				},
				refusedLines = {
					"I need a minute. Don't make it worse.",
					"Not now. Ask me later when I've cooled off.",
				},
			},
			{
				id = "watch_game",
				label = "Watch the game with them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 3,
				stats = { happiness = 3, health = 1 },
				lines = {
					"Come on, sit here. This match is going to be good.",
					"Watch this -- he always scores from this angle.",
					"We haven't missed a game all season. You're part of the team now.",
				},
			},
			{
				id = "join_practice",
				label = "Join practice with them",
				minAge = 10,
				maxAge = 999,
				minBond = 0,
				bond = 4,
				stats = { happiness = 2, health = 2 },
				lines = {
					"We could use one more. Don't be shy.",
					"Just keep up. You'll get the hang of it.",
					"This is the warm-up. Ready for the real stuff?",
				},
			},
			{
				id = "walk_basketball",
				label = "Walk to the basketball court with them",
				minAge = 12,
				maxAge = 999,
				minBond = 20,
				bond = 4,
				stats = { happiness = 2, health = 1 },
				ask = true,
				walksTo = "basketball_court",
				lines = {
					"Field's empty now. Let's go shoot some hoops.",
					"I need to work on my free throws. Come watch.",
					"Same court every day. You in?",
				},
				refusedLines = {
					"Alright. I'll save your spot.",
					"Another time. I'm waiting for the others.",
				},
				arrivalLines = {
					"Here we are. First to five wins, loser buys drinks.",
					"Made it. Your turn to shoot -- don't choke.",
					"This court's ours. No one else showing up today.",
				},
			},
			{
				id = "walk_playground",
				label = "Walk to the playground with them",
				minAge = 8,
				maxAge = 999,
				minBond = 15,
				bond = 3,
				stats = { happiness = 3 },
				ask = true,
				walksTo = "playground",
				lines = {
					"I'm heading to the playground. Want to come?",
					"The swings are free. Come on, before someone takes them.",
					"It's quiet over there. Good for talking.",
				},
				refusedLines = {
					"Okay. I'll be there later if you change your mind.",
					"Suit yourself. I'm going anyway.",
				},
				arrivalLines = {
					"Here. The good swing's free. Take it.",
					"We're here. Nobody's around -- it's all ours.",
					"Playground's quiet today. Perfect.",
				},
			},
			{
				id = "know_athlete",
				label = "Learn their name",
				minAge = 8,
				maxAge = 999,
				minBond = 10,
				bond = 3,
				stats = { happiness = 1 },
				gives = "known",
				lines = {
					"We see each other here all the time. I don't know your name?",
					"Oh, right. We should fix that.",
					"Nice to meet you. Properly, this time.",
				},
			},
			{
				id = "practice_friend",
				label = "Always practice together",
				minAge = 10,
				maxAge = 999,
				minBond = 30,
				bond = 6,
				stats = { happiness = 3, health = 1 },
				needsTie = "known",
				gives = "friend",
				lines = {
					"Same time tomorrow? Good. I'll save you a spot.",
					"You're the only person I practice with. Don't flake on me.",
					"We should get matching shirts. Just saying.",
				},
			},
			{
				id = "closest_athlete",
				label = "Tell them the thing you're most proud of",
				minAge = 14,
				maxAge = 999,
				minBond = 60,
				bond = 8,
				stats = { happiness = 4 },
				needsTie = "friend",
				gives = "closest",
				lines = {
					"No one else knows this. That's why I'm telling you.",
					"Thanks for not making it weird. I meant it.",
					"This is ours. Whatever happens, this stays between us.",
				},
			},
		},
	},

	{
		-- People at the fade offices between downtown and the residential grid.
		-- Mid-level workers who take the longer commute and hang out near the entrance.
		id = "fade_worker",
		placeId = "fade_1",
		minAge = 16,
		maxAge = 999,
		minAgeOffset = -2,
		maxAgeOffset = 18,
		minHeight = 0.94,
		maxHeight = 1.07,
		startingBond = 0,
		busyLines = {
			"Clocking out in ten. Walk with me?",
			"In a meeting. I'll find you tomorrow.",
			"Not now -- the elevators are brutal at this hour.",
		},
		offers = {
			{
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 5,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				lines = {
					"This building never gets any less crowded. You too?",
					"Same floor as me. I see you every day and never learn your name.",
					"Nice weather, isn't it? Hard to tell from in here.",
				},
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				lines = {
					"Okay. I'll just go back to the desk.",
					"Right. Suit yourself.",
				},
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				lines = {
					"I'll pretend I didn't see that.",
					"Fine. I was going to ask you anyway.",
				},
			},
			{
				id = "make_right",
				label = "Try to make it right",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -1,
				bond = 8,
				ask = true,
				lines = {
					"Thanks. I was going to pretend it didn't happen, but -- thank you.",
				},
				refusedLines = {
					"I need a bit. Just -- tomorrow?",
					"Not today. I'm still working through it.",
				},
			},
			{
				id = "walk_cafe",
				label = "Walk to the cafe with them",
				minAge = 14,
				maxAge = 999,
				minBond = 20,
				bond = 3,
				stats = { happiness = 2 },
				ask = true,
				walksTo = "cafe",
				lines = {
					"I need caffeine. Walk with me to the cafe?",
					"Let's get out of the building for ten minutes.",
					"There's a new pastry I've been meaning to try. Come on.",
				},
				refusedLines = {
					"Alright. I'll go alone then.",
					"Another time. I've got paperwork.",
				},
				arrivalLines = {
					"Here we are. Order first -- I'm starving.",
					"Made it. What's your poison?",
					"Cafe's ours. Don't tell the boss we've been gone five minutes.",
				},
			},
			{
				id = "walk_restaurant",
				label = "Walk to the restaurant with them",
				minAge = 16,
				maxAge = 999,
				minBond = 25,
				bond = 4,
				stats = { happiness = 2 },
				ask = true,
				walksTo = "restaurant",
				lines = {
					"I'm dying for a proper meal. Walk with me?",
					"There's a place near the office I like. Come on.",
					"My treat. You've earned it this week.",
				},
				refusedLines = {
					"Alright. Another time then.",
					"Suit yourself. I'll save you a seat.",
				},
				arrivalLines = {
					"Here we are. Right -- what are you having?",
					"Made it. Table for two? Or should I go sit at the bar?",
					"This place never lets me down. Same for you?",
				},
			},
			{
				id = "know_worker",
				label = "Learn their name",
				minAge = 12,
				maxAge = 999,
				minBond = 10,
				bond = 3,
				stats = { happiness = 1 },
				gives = "known",
				lines = {
					"Oh, we've never actually done that, have we?",
					"I've been standing here two years and you just noticed.",
					"Right. Now we're officially acquainted.",
				},
			},
			{
				id = "break_friend",
				label = "Take breaks with them properly",
				minAge = 14,
				maxAge = 999,
				minBond = 30,
				bond = 6,
				stats = { happiness = 3 },
				needsTie = "known",
				gives = "friend",
				lines = {
					"Same time tomorrow? Good. I was hoping you'd say yes.",
					"You're the only reason I look forward to coffee breaks.",
					"Nobody else here gets it. That's why it's us.",
				},
			},
			{
				id = "closest_worker",
				label = "Tell them something you haven't told anyone",
				minAge = 18,
				maxAge = 999,
				minBond = 65,
				bond = 8,
				stats = { happiness = 4 },
				needsTie = "friend",
				gives = "closest",
				lines = {
					"Nobody else knows this. That means something, right?",
					"Thanks for not... you know. Thanks for listening.",
					"This stays between us. Obviously.",
				},
			},
		},
	},
	{
		-- People who hang out at the north strip, just behind the civic buildings.
		-- Shop staff and regulars who fill the space between city hall and the street.
		id = "north_worker",
		placeId = "north_shop_1",
		minAge = 14,
		maxAge = 999,
		minAgeOffset = -3,
		maxAgeOffset = 15,
		minHeight = 0.92,
		maxHeight = 1.07,
		startingBond = 0,
		busyLines = {
			"Back in a sec. Just checking the stock.",
			"Busy right now -- sorry! Come back in a bit.",
			"I'm about to close up. Want to walk together?",
		},
		offers = {
			{
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 5,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				lines = {
					"Quiet morning. The best kind.",
					"You pass by here often? I see you sometimes.",
					"Not much happening today. How about you?",
				},
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				lines = {
					"Okay. I'll just go back to the counter.",
					"Right. Suit yourself.",
				},
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				lines = {
					"I'll pretend I didn't see that.",
					"Fine. I was going to ask you anyway.",
				},
			},
			{
				id = "make_right",
				label = "Try to make it right",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -1,
				bond = 8,
				ask = true,
				lines = {
					"Thanks. I was going to pretend it didn't happen, but -- thank you.",
				},
				refusedLines = {
					"I need a bit. Just -- tomorrow?",
					"Not today. I'm still working through it.",
				},
			},
			{
				id = "walk_park",
				label = "Walk to the park with them",
				minAge = 12,
				maxAge = 999,
				minBond = 20,
				bond = 3,
				stats = { happiness = 2 },
				ask = true,
				walksTo = "park",
				lines = {
					"I need some air. Walk with me to the park?",
					"The sun's out for once. Let's go stand in it.",
					"I always come here when I need to clear my head.",
				},
				refusedLines = {
					"Alright. Maybe another time.",
					"I can't right now, sorry.",
				},
				arrivalLines = {
					"Here we are. Nice out, isn't it?",
					"Made it. Want to sit on the bench?",
					"This is my favourite spot. Glad you came.",
				},
			},
			{
				id = "walk_soccer",
				label = "Walk to the soccer field with them",
				minAge = 14,
				maxAge = 999,
				minBond = 25,
				bond = 4,
				stats = { happiness = 2, health = 1 },
				ask = true,
				walksTo = "soccer_field",
				lines = {
					"Field's usually empty this time. Want to come?",
					"I've got to stretch my legs. Walk with me?",
					"There's a game starting soon. Want to watch?",
				},
				refusedLines = {
					"Alright. I'll go alone.",
					"Suit yourself. See you around.",
				},
				arrivalLines = {
					"Here we are. Want to kick a ball around?",
					"Made it. Grab a ball if you want to play.",
					"This is where everyone hangs after school. Same here now?",
				},
			},
			{
				id = "know_worker",
				label = "Learn their name",
				minAge = 12,
				maxAge = 999,
				minBond = 10,
				bond = 3,
				stats = { happiness = 1 },
				gives = "known",
				lines = {
					"Oh, we've never done that, have we?",
					"I've been here weeks and you just noticed.",
					"Right. Now we're officially acquainted.",
				},
			},
			{
				id = "break_friend",
				label = "Take breaks with them properly",
				minAge = 14,
				maxAge = 999,
				minBond = 30,
				bond = 6,
				stats = { happiness = 3 },
				needsTie = "known",
				gives = "friend",
				lines = {
					"Same time tomorrow? Good. I was hoping you'd say yes.",
					"You're the only reason I look forward to breaks.",
					"Nobody else here gets it. That's why it's us.",
				},
			},
			{
				id = "closest_worker",
				label = "Tell them something you haven't told anyone",
				minAge = 18,
				maxAge = 999,
				minBond = 65,
				bond = 8,
				stats = { happiness = 4 },
				needsTie = "friend",
				gives = "closest",
				lines = {
					"Nobody else knows this. That means something, right?",
					"Thanks for not... you know. Thanks for listening.",
					"This stays between us. Obviously.",
				},
			},
		},
	},
	{
		-- People at the car dealership. Sales staff and buyers who come and go.
		-- The dealership sits between the main street and the suburbs, so some
		-- folks walk from here toward home.
		id = "car_buyer",
		placeId = "auto_dealer",
		minAge = 16,
		maxAge = 999,
		minAgeOffset = -2,
		maxAgeOffset = 20,
		minHeight = 0.94,
		maxHeight = 1.07,
		startingBond = 0,
		busyLines = {
			"Just finishing up here. Talk to you tomorrow?",
			"The manager's calling. I'll find you later.",
			"Test drive schedule's full. Come back after lunch?",
		},
		offers = {
			{
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 5,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				lines = {
					"Nice car, huh? I've been looking at this model all week.",
					"Not much to do while waiting. You here often?",
					"This place is bigger than it looks. Want to take a look around?",
				},
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				lines = {
					"Okay. I'll just go back to the desk.",
					"Right. Suit yourself.",
				},
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				lines = {
					"I'll pretend I didn't see that.",
					"Fine. I was going to ask you anyway.",
				},
			},
			{
				id = "make_right",
				label = "Try to make it right",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -1,
				bond = 8,
				ask = true,
				lines = {
					"Thanks. I was going to pretend it didn't happen, but -- thank you.",
				},
				refusedLines = {
					"I need a bit. Just -- tomorrow?",
					"Not today. I'm still working through it.",
				},
			},
			{
				id = "walk_suburb",
				label = "Walk toward the suburbs with them",
				minAge = 16,
				maxAge = 999,
				minBond = 25,
				bond = 4,
				stats = { happiness = 2 },
				ask = true,
				walksTo = "suburb_1",
				lines = {
					"I live out that way. Walk with me for a bit?",
					"Heading home. Want some company?",
					"The suburbs are nicer this time of day. Come on.",
				},
				refusedLines = {
					"Alright. Another time then.",
					"Suit yourself. I'll save you a seat.",
				},
				arrivalLines = {
					"Here we are. Nice area, isn't it?",
					"Made it. This is my street. You live around here?",
					"This part of town is quiet. Glad I could show you.",
				},
			},
			{
				id = "know_worker",
				label = "Learn their name",
				minAge = 12,
				maxAge = 999,
				minBond = 10,
				bond = 3,
				stats = { happiness = 1 },
				gives = "known",
				lines = {
					"Oh, we've never done that, have we?",
					"I've been here two years and you just noticed.",
					"Right. Now we're officially acquainted.",
				},
			},
			{
				id = "break_friend",
				label = "Take breaks with them properly",
				minAge = 14,
				maxAge = 999,
				minBond = 30,
				bond = 6,
				stats = { happiness = 3 },
				needsTie = "known",
				gives = "friend",
				lines = {
					"Same time tomorrow? Good. I was hoping you'd say yes.",
					"You're the only reason I look forward to breaks.",
					"Nobody else here gets it. That's why it's us.",
				},
			},
			{
				id = "closest_worker",
				label = "Tell them something you haven't told anyone",
				minAge = 18,
				maxAge = 999,
				minBond = 65,
				bond = 8,
				stats = { happiness = 4 },
				needsTie = "friend",
				gives = "closest",
				lines = {
					"Nobody else knows this. That means something, right?",
					"Thanks for not... you know. Thanks for listening.",
					"This stays between us. Obviously.",
				},
			},
		},
	},
	{
		-- Dealership sales staff. They staff the counter and show around — distinct
		-- from the car_buyer archetype, which is the customer side of the same room.
		id = "car_salesperson",
		placeId = "auto_dealer",
		minAge = 18,
		maxAge = 999,
		minAgeOffset = -2,
		maxAgeOffset = 15,
		minHeight = 0.94,
		maxHeight = 1.07,
		startingBond = 0,
		busyLines = {
			"Just showing someone a sedan. One sec?",
			"The finance team is on the phone. Give me a moment.",
			"I'm between customers. Talk to you in a bit?",
		},
		offers = {
			{
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 5,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				lines = {
					"Another quiet day at the lot. Want to see the new arrivals?",
					"I've been at this counter since eight. You're not the only one up early.",
					"Cars are great, I suppose. I just prefer the people side.",
				},
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				lines = {
					"Okay. I'll just go back to the desk.",
					"Right. Suit yourself.",
				},
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				lines = {
					"I'll pretend I didn't see that.",
					"Fine. I was going to ask you anyway.",
				},
			},
			{
				id = "make_right",
				label = "Try to make it right",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -1,
				bond = 8,
				ask = true,
				lines = {
					"Thanks. I was going to pretend it didn't happen, but -- thank you.",
				},
				refusedLines = {
					"I need a bit. Just -- tomorrow?",
					"Not today. I'm still working through it.",
				},
			},
			{
				id = "walk_suburb",
				label = "Walk toward the suburbs with them",
				minAge = 16,
				maxAge = 999,
				minBond = 25,
				bond = 4,
				stats = { happiness = 2 },
				ask = true,
				walksTo = "suburb_1",
				lines = {
					"I live out that way. Walk with me for a bit?",
					"Clocking off early. Want some company?",
					"The suburbs are nicer this time of day. Come on.",
				},
				refusedLines = {
					"Alright. Another time then.",
					"Suit yourself. I'll save you a seat.",
				},
				arrivalLines = {
					"Here we are. Nice area, isn't it?",
					"Made it. This is my street. You live around here?",
					"This part of town is quiet. Glad I could show you.",
				},
			},
			{
				id = "know_worker",
				label = "Learn their name",
				minAge = 12,
				maxAge = 999,
				minBond = 10,
				bond = 3,
				stats = { happiness = 1 },
				gives = "known",
				lines = {
					"Oh, we've never done that, have we?",
					"I've been here two years and you just noticed.",
					"Right. Now we're officially acquainted.",
				},
			},
			{
				id = "break_friend",
				label = "Take breaks with them properly",
				minAge = 14,
				maxAge = 999,
				minBond = 30,
				bond = 6,
				stats = { happiness = 3 },
				needsTie = "known",
				gives = "friend",
				lines = {
					"Same time tomorrow? Good. I was hoping you'd say yes.",
					"You're the only reason I look forward to breaks.",
					"Nobody else here gets it. That's why it's us.",
				},
			},
			{
				id = "closest_worker",
				label = "Tell them something you haven't told anyone",
				minAge = 18,
				maxAge = 999,
				minBond = 65,
				bond = 8,
				stats = { happiness = 4 },
				needsTie = "friend",
				gives = "closest",
				lines = {
					"Nobody else knows this. That means something, right?",
					"Thanks for not... you know. Thanks for listening.",
					"This stays between us. Obviously.",
				},
			},
		},
	},

}

-- Which archetype townsperson N is, as a fixed repeating pattern rather than a weighted
-- draw. Two reasons, and both matter more than the tidiness of a weight table would.
--
-- It is stable against `Config.Town.Count`: raising the population adds people to the
-- end and disturbs nobody already saved against. A weighted draw would re-deal the whole
-- town every time the number moved.
--
-- And it is stable against the *order* of the list above: townsperson 7 is a classmate
-- because this pattern says so at position 7, not because a random number landed in a
-- range whose size depends on how many archetypes there happen to be.
--
-- The mix is what a life actually has in it, which is not an even six ways: school and
-- the street are where a childhood's people come from and there are more of both.
--
-- **The length of this list must stay odd.** Gender is alternated by index rather than
-- rolled (see the build loop below for why), and a slot recurs every #PATTERN people --
-- so an odd length lands each slot's two people on opposite parities and every archetype
-- comes out exactly half and half. An even length would give each archetype a single
-- gender throughout. `assertPatternParity` refuses that at load rather than leaving it to
-- be discovered by counting heads.
--
-- One `classmate` gave way to make room for `peer` rather than the list simply growing:
-- eight classmates was already the largest group in a school-years population that also
-- has six street kids, and adult life needed the slot more than one more desk did.
--
-- Two `city_worker` and `city_athlete` slots were added to seed the new districts with
-- people -- the city was going to be beautiful and empty without them.
local PATTERN: { string } = {
	"street",
	"classmate",
	"regular",
	"local",
	"classmate",
	"coworker",
	"peer",
	"street",
	"local",
	"classmate",
	"regular",
	"coworker",
	"peer",
	"street",
	"local",
	"coworker",
	"city_worker",
	"peer",
	"city_athlete",
	"fade_worker",
	"north_worker",
	"car_buyer",
	"car_salesperson",
}

local archetypeById: { [string]: Archetype } = {}
for _, archetype in ARCHETYPES do
	if archetypeById[archetype.id] ~= nil then
		error(`[AGES content] two townsfolk archetypes share the id "{archetype.id}"`)
	end
	archetypeById[archetype.id] = archetype
end

for index, id in PATTERN do
	if archetypeById[id] == nil then
		error(
			`[AGES content] the townsfolk pattern asks for "{id}" at position {index}, `
				.. `which is not an archetype -- fix the name or add the archetype`
		)
	end
end

-- The gender split, checked rather than trusted.
--
-- Genders alternate by index and archetypes repeat every #PATTERN, so the two interleave
-- correctly only while that length is odd -- and the failure when it is not is completely
-- silent. Nothing errors, nothing looks wrong in a diff, and every classmate in the game
-- is simply a boy. Somebody would eventually notice by playing a whole school year and
-- wondering; that is far too late and far too expensive a way to find out that a list got
-- one entry longer.
--
-- Counted honestly rather than asserted from the parity rule, so this keeps working if
-- either half of the arrangement is ever replaced by something cleverer.
do
	local male: { [string]: number } = {}
	local female: { [string]: number } = {}
	for index = 1, TOWN.Count do
		local id = PATTERN[((index - 1) % #PATTERN) + 1]
		if index % 2 == 0 then
			female[id] = (female[id] or 0) + 1
		else
			male[id] = (male[id] or 0) + 1
		end
	end
	for _, archetype in ARCHETYPES do
		local men = male[archetype.id] or 0
		local women = female[archetype.id] or 0
		if men + women == 0 then
			-- Not fatal on its own -- an archetype can legitimately sit unused while it is
			-- being written -- but it is worth saying out loud, because the usual cause is
			-- a name typed into ARCHETYPES and forgotten in PATTERN, and the symptom is a
			-- population that silently never contains that kind of person.
			warn(`[AGES content] archetype "{archetype.id}" is never used by the townsfolk pattern`)
			continue
		end
		if math.abs(men - women) > 1 then
			error(
				`[AGES content] archetype "{archetype.id}" generates {men} men and {women} women. `
					.. `Genders alternate by index, so #PATTERN ({#PATTERN}) must be odd and `
					.. `Config.Town.Count ({TOWN.Count}) should be a whole number of patterns -- `
					.. `otherwise a whole archetype comes out one gender and nothing else says so`
			)
		end
	end
end

-- Everything about an archetype that can be wrong by reading it, checked here rather
-- than left to People.luau's validator. Both would catch most of this, but the message
-- there names "town14" -- and the fix is never in town14, it is in the archetype fourteen
-- happens to be built from.
local function validateArchetype(archetype: Archetype)
	if archetype.minAge > archetype.maxAge then
		error(`[AGES content] archetype "{archetype.id}" is around from {archetype.minAge} to {archetype.maxAge}`)
	end
	if archetype.minAgeOffset > archetype.maxAgeOffset then
		error(
			`[AGES content] archetype "{archetype.id}" draws an age offset from `
				.. `{archetype.minAgeOffset}..{archetype.maxAgeOffset}, which is backwards`
		)
	end
	if archetype.minHeight > archetype.maxHeight or archetype.minHeight <= 0 then
		error(`[AGES content] archetype "{archetype.id}" draws a height from {archetype.minHeight}..{archetype.maxHeight}`)
	end
	if #archetype.busyLines == 0 then
		error(`[AGES content] archetype "{archetype.id}" has no way of saying it is busy`)
	end
	if #archetype.offers == 0 then
		error(`[AGES content] archetype "{archetype.id}" offers nothing, so walking up to one does nothing`)
	end

	local seen: { [string]: boolean } = {}
	local labels: { [string]: string } = {}
	-- Which template hands out each rung, so two of them handing out the same one can be
	-- caught, and so the reachability pass below has something to ask.
	local ladder: { [string]: string } = {}
	for _, template in archetype.offers do
		local where = `archetype "{archetype.id}" offer "{template.id}"`
		if seen[template.id] then
			error(`[AGES content] {where} is written twice`)
		end
		seen[template.id] = true

		-- Two identical labels on one panel is unreadable, and unlike People.luau this can
		-- be settled without walking the ages: every generated copy shares these labels.
		local clash = labels[template.label]
		if clash ~= nil then
			error(`[AGES content] {where} and "{clash}" both read "{template.label}"`)
		end
		labels[template.label] = template.id

		if #template.lines == 0 then
			error(`[AGES content] {where} has nothing said back, which is the point of it`)
		end
		-- Both directions, matching PersonOffer's own rule. A missing refusal line shows a
		-- blank row on the one beat the player most needs a person in front of them.
		if template.ask then
			local refused = template.refusedLines
			if refused == nil or #refused == 0 then
				error(`[AGES content] {where} is an ask but has no refusedLines -- write what they say when they say no`)
			end
		elseif template.refusedLines ~= nil then
			error(`[AGES content] {where} has refusedLines but is not an ask, so they could never be said`)
		end
		local walksTo = template.walksTo
		if walksTo ~= nil then
			local walkable = false
			for _, place in Config.Places.Walkable do
				if place == walksTo then
					walkable = true
					break
				end
			end
			if not walkable then
				error(`[AGES content] {where} walks to "{walksTo}", which is not a place a walk can end at`)
			end
			if template.arrivalLines == nil or #template.arrivalLines == 0 then
				error(`[AGES content] {where} is a walk but has no arrivalLines -- what do they say when you get there?`)
			end
			-- The walk is the walking. See the note on PersonOffer.walksTo: a companion
			-- offer carries no stats or money, and a walk that paid out would be the one
			-- content mistake in this file with no sentence attached to it.
			if template.stats ~= nil or template.money ~= nil then
				error(`[AGES content] {where} walks somewhere but also hands out stats or money; a walk is the walking`)
			end
		elseif template.arrivalLines ~= nil then
			error(`[AGES content] {where} has arrivalLines but walks nowhere; set walksTo or drop them`)
		end
		local maxBond = template.maxBond
		if maxBond ~= nil and maxBond < template.minBond then
			error(
				`[AGES content] {where} needs {template.minBond} and is gone above {maxBond}; `
					.. `a maxBond below its minBond is an offer nothing could ever be at`
			)
		end

		Ties.AssertKnown(template.gives, where)
		Ties.AssertKnown(template.needsTie, where)
		local gives = template.gives
		if gives ~= nil then
			if Ties.RankOf(gives) <= Ties.RankOf(template.needsTie) then
				error(
					`[AGES content] {where} gives "{gives}" but already needs "{template.needsTie}", `
						.. `which is as close or closer -- a rung has to climb`
				)
			end
			if template.ask then
				error(
					`[AGES content] {where} gives "{gives}" and is an ask; a rung that can be refused `
						.. `would make becoming somebody's friend a coin toss`
				)
			end
			if ladder[gives] ~= nil then
				error(
					`[AGES content] archetype "{archetype.id}" reaches "{gives}" from both `
						.. `"{ladder[gives]}" and "{template.id}"; a rung is one row, or the player `
						.. `is shown two ways to become the same thing`
				)
			end
			ladder[gives] = template.id
		end
	end

	-- A rung nobody can stand on. `needsTie` is satisfied by that tie or anything closer,
	-- so an offer needing "friend" is dead unless something in this archetype hands out
	-- "friend" or better -- and dead content here is dead across every copy generated
	-- from it, with no runtime symptom at all beyond a row that never appears.
	--
	-- Only checked within the archetype because that is the only place it is knowable:
	-- a tie earned from a classmate is a tie with *that classmate*, so a coworker's
	-- friend-only offer is not reachable through them.
	for _, template in archetype.offers do
		local needed = template.needsTie
		if needed == nil then
			continue
		end
		local reachable = false
		for tieId, _ in ladder do
			if Ties.RankOf(tieId) >= Ties.RankOf(needed) then
				reachable = true
				break
			end
		end
		if not reachable then
			error(
				`[AGES content] archetype "{archetype.id}" offer "{template.id}" needs "{needed}" but `
					.. `nothing this archetype offers ever reaches it, so the row can never appear`
			)
		end
	end

	-- The check that earns its keep, and the reason it is here rather than only in
	-- People.luau: an archetype with a gap in its floor produces however many townsfolk
	-- the pattern asks for, and every one of them errors at load with the same fix.
	--
	-- Nothing generated here is flag-gated, but the rungs are tie-gated in both
	-- directions -- `needsTie` hides a row until you have climbed and `gives` hides it
	-- once you have -- so they are discounted here exactly as People.luau discounts them.
	-- An archetype whose floor rested on a rung would empty out for the one player who
	-- took it, which is the opposite of what a floor is.
	for age = archetype.minAge, archetype.maxAge do
		local floor = 0
		for _, template in archetype.offers do
			local minAge = math.max(template.minAge, archetype.minAge)
			local maxAge = math.min(template.maxAge, archetype.maxAge)
			local unconditional = template.gives == nil and template.needsTie == nil
			if age >= minAge and age <= maxAge and template.minBond <= ALWAYS and unconditional then
				floor += 1
			end
		end
		if floor == 0 then
			error(
				`[AGES content] archetype "{archetype.id}" has nothing at age {age} that somebody at the `
					.. `bottom of the bond range could take; widen an offer or write one at minBond = MinBond`
			)
		end
	end
end

for _, archetype in ARCHETYPES do
	validateArchetype(archetype)
end

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function round2(value: number): number
	return math.round(value * 100) / 100
end

local bodies: { CastMember } = {}
local people: { Person } = {}
local isTown: { [string]: boolean } = {}
local archetypeOf: { [string]: string } = {}
local takenNames: { [string]: boolean } = {}

-- Takes the gender rather than rolling one, so a person is named from the list that
-- matches them by construction and there is no later check that could pass or fail.
local function nameFor(index: number, gender: Gender): string
	local firstNames = if gender == "male" then MALE_FIRST_NAMES else FEMALE_FIRST_NAMES
	for attempt = 0, NAME_ATTEMPTS do
		local rng = Random.new(TOWN.Seed + index * SEED_STRIDE + NAME_STREAM + attempt)
		local name = `{pick(rng, firstNames)} {pick(rng, LAST_NAMES)}`
		if not takenNames[name] then
			takenNames[name] = true
			return name
		end
	end
	error(
		`[AGES content] could not find an unused name for townsperson {index} in {NAME_ATTEMPTS} tries; `
			.. `the name pools are too small for Config.Town.Count`
	)
end

for index = 1, TOWN.Count do
	local id = string.format("town%02d", index)
	local archetype = archetypeById[PATTERN[((index - 1) % #PATTERN) + 1]]
	local rng = Random.new(TOWN.Seed + index * SEED_STRIDE)

	-- Alternated, not rolled, and this is the one attribute in this loop that is not
	-- random. A fair coin flipped thirty-four times against a *fixed* seed does not give
	-- a town that is roughly half and half -- it gives whatever that one seed happens to
	-- say, forever, identically for every player. Twenty-two of one and twelve of the
	-- other is an ordinary outcome for a coin and a bad outcome for a world, and because
	-- the seed never changes there would be no second sample to correct it.
	--
	-- Alternating makes the split exact, and the interaction with PATTERN is the reason
	-- its length must stay **odd**: a slot recurs every #PATTERN people, so with an odd
	-- length the two people in each slot land on opposite parities and every archetype
	-- comes out exactly half and half. Make it even and each archetype collapses to a
	-- single gender -- every classmate a boy, every coworker a girl -- which is the sort
	-- of failure that looks like a content mistake for a week before anybody counts.
	-- assertPatternParity below refuses that rather than leaving it to be noticed.
	local gender: Gender = if index % 2 == 0 then "female" else "male"

	local body: CastMember = {
		id = id,
		name = nameFor(index, gender),
		gender = gender,
		skinColor = pick(rng, SKIN_TONES),
		heightScale = round2(rng:NextNumber(archetype.minHeight, archetype.maxHeight)),
		widthScale = round2(rng:NextNumber(0.88, 1.12)),
		headScale = round2(rng:NextNumber(0.96, 1.06)),
		proportionScale = round2(rng:NextNumber(0, 1)),
		bodyTypeScale = round2(rng:NextNumber(0.45, 0.9)),
		-- Nothing bought or uploaded, exactly as the authored four are. A town that
		-- needed a shopping trip before it existed would not exist.
		shirtAssetId = 0,
		pantsAssetId = 0,
		hairAssetId = 0,
	}
	table.insert(bodies, body)

	local offers: { PersonOffer } = {}
	for _, template in archetype.offers do
		-- Clamped rather than trusted, so a template can say the years its sentence makes
		-- sense in and be shared by two archetypes with different windows. People.luau
		-- refuses an offer written outside its person's years, and this is what keeps
		-- that from being an authoring trap.
		local minAge = math.max(template.minAge, archetype.minAge)
		local maxAge = math.min(template.maxAge, archetype.maxAge)
		if minAge > maxAge then
			continue
		end

		local offer: PersonOffer = {
			id = `{id}_{template.id}`,
			label = template.label,
			minAge = minAge,
			maxAge = maxAge,
			minBond = template.minBond,
			maxBond = template.maxBond,
			bond = template.bond,
			stats = template.stats,
			money = template.money,
			line = pick(rng, template.lines),
			ask = template.ask,
			-- Checked above, so an ask always has some. Read through a local rather than
			-- indexed twice so the type checker can see it is not nil here.
			refusedLine = nil,
			gives = template.gives,
			needsTie = template.needsTie,
			walksTo = template.walksTo,
			arrivalLine = nil,
		}
		local refusedLines = template.refusedLines
		if template.ask and refusedLines ~= nil then
			offer.refusedLine = pick(rng, refusedLines)
		end
		local arrivalLines = template.arrivalLines
		if template.walksTo ~= nil and arrivalLines ~= nil and #arrivalLines > 0 then
			offer.arrivalLine = pick(rng, arrivalLines)
		end
		table.insert(offers, offer)
	end

	local person: Person = {
		id = id,
		castId = id,
		placeId = archetype.placeId,
		minAge = archetype.minAge,
		maxAge = archetype.maxAge,
		ageOffset = rng:NextInteger(archetype.minAgeOffset, archetype.maxAgeOffset),
		startingBond = archetype.startingBond,
		busyLine = pick(rng, archetype.busyLines),
		offers = offers,
		contextualLines = archetype.contextualLines,
	}
	table.insert(people, person)
	isTown[id] = true
	archetypeOf[id] = archetype.id
end

return {
	-- The bodies, for Cast.luau to merge. Separate from the people because a body is what
	-- NPCService builds and a person is what PeopleService stands somewhere, and those
	-- two files have never had to know about each other.
	Bodies = bodies,
	People = people,
	-- Whether an id belongs to the town rather than to the cast. Read by PeopleService,
	-- which bodies these on approach and the authored four always -- your mother is not
	-- somebody the world should be streaming in.
	IsTown = isTown,
	-- Which kind of person each of them is. Only the harness reads it: the game never
	-- needs to know, because everything an archetype decides has already been baked into
	-- the person by the time anything asks.
	ArchetypeOf = archetypeOf,
}
