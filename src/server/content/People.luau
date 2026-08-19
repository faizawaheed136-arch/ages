--!strict
-- The people in a life, and what each of them is willing to do for you.
--
-- Four, and deliberately the four who were already in the game. These are the same ids
-- Cast.luau has been handing to visitor events since the beginning -- the neighbor who
-- knocks when you are nine really is the neighbor who knocks when you are forty -- and
-- this file is what finally gives that continuity somewhere to be recorded.
--
-- Where they stand is chosen to spread a life across the world rather than to be tidy.
-- Two parents at home, because home is where parents are. Mr. Alderman at the shop,
-- because a neighbor you only ever meet at your own front door is a doorbell rather
-- than a person -- and because the shop is where the job ladder starts, which is what
-- makes twenty years of being decent to him worth something at the end. Rae at school,
-- because that is where you meet the friend of a childhood.
--
-- Every place id here is one the world already needed. Nothing in this file asks
-- anybody to go and tag another part in Studio, which is a deliberate constraint: a
-- person who silently does not exist because a part was never tagged is the worst
-- possible failure this system could have, and the cheapest way to not have it is to
-- never ask for a part that is not already there.
--
-- What is deliberately not here: anybody dying. Parents run to the end of a life,
-- which is not true and is knowingly not true. Modelling it properly needs a death of
-- their own, an event to carry it and something to happen to the bond afterwards, and
-- half of that would be worse than none -- a mother who quietly stopped being spawned
-- at some threshold age is not grief, it is a bug that looks like grief.
--
-- What is also not here is Rae after seventeen. That one *is* a rough edge: they age
-- out with the school years and the game says nothing about it, which reads as losing
-- touch only if the player is feeling generous. It wants a line at the end of the last
-- school year and does not have one yet.
--
-- Four is no longer everybody, though. The town -- content/Townsfolk.luau -- generates a
-- population of strangers and they are appended to this list at the bottom of the file,
-- through the same validator. That is deliberate and it is the cheap part of having a
-- town at all: a generated person is a Person, so bonds, decay, the once-a-year cap, the
-- offer fan and the odds on an ask are all already written for them. Nothing below this
-- line knows the difference, and the only thing anywhere that does is PeopleService,
-- which gives the town bodies on approach and the four bodies always.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local Cast = require(script.Parent.Cast)
local Flags = require(script.Parent.Flags)
local Ties = require(script.Parent.Ties)
local Townsfolk = require(script.Parent.Townsfolk)

type Person = Types.Person
type PersonOffer = Types.PersonOffer
type StatName = Types.StatName
type FlagSet = Types.FlagSet

local PEOPLE = Config.People
-- The bond an offer must ask for to count as always available. Named rather than
-- written out at each use, because the coverage check below turns on it: an offer at
-- this level is one nobody can ever be too estranged to be given.
local ALWAYS = PEOPLE.MinBond

local VALID_STATS: { [string]: boolean } = {
	health = true,
	happiness = true,
	smarts = true,
	looks = true,
}

local SOURCE: { Person } = {
	{
		id = "mom",
		castId = "mom",
		placeId = "home",
		minAge = 0,
		maxAge = 999,
		-- Late twenties when you were born, which is the most ordinary answer there is and
		-- therefore the right one for the person the game has said the least about.
		ageOffset = 28,
		-- Starts warmest of the four. A mother is not somebody a life has to get to know,
		-- and opening at nothing would have the game's first minute quietly claiming that
		-- she is a stranger. High enough that "friendly" is where a life begins and the
		-- first band above it is within a few visits, low enough that the top of the
		-- range is still most of a childhood away.
		startingBond = 35,
		busyLine = "Not now, love -- I've got my hands full. Come and find me another day.",
		offers = {
			{
				-- The universal small talk. Written first of every person's offers because
				-- the panel sorts by what an offer asks of the bond and throws the tail away:
				-- at the bottom of the range, where nothing else is left, this is the row
				-- somebody still has -- the quiet year, the person who keeps showing up.
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 5,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				line = "Oh, nothing needs saying to me. I like the quiet company.",
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				line = "...I see. We'll leave it there, then.",
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				line = "Right. Well. I won't keep you.",
			},
			{
				-- The apology, and the whole reason enemies are not a dead end. An ask,
				-- because at the bottom of the range the refusal odds genuinely read as a
				-- long shot -- which is exactly what an apology to somebody you have spent
				-- years souring should feel like. At maxBond = -1 it is on the floor the
				-- whole way the relationship is negative, not only at sworn-enemy depth.
				id = "make_right",
				label = "Try to make it right",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -1,
				bond = 8,
				ask = true,
				line = "That's all I wanted to hear. Come here, then.",
				refusedLine = "Love, I don't think sorry covers it yet. Give it time.",
			},
			{
				-- The companion walk. The walk is the content, so nothing else rides on it
				-- -- no stats, no money, just a little bond for the company. An ask, because
				-- asking somebody to come with you is exactly the kind of thing that can be
				-- turned down.
				id = "walks_shop",
				label = "Come to the shop with me",
				minAge = 16,
				maxAge = 999,
				minBond = 25,
				bond = 3,
				ask = true,
				line = "That'd be nice. Let me get my coat.",
				refusedLine = "Not today, love. I've got your father's tea on.",
				walksTo = "store",
				arrivalLine = "Well, here we are then. A lovely bit of company for the walk.",
			},
			{
				id = "walks_school",
				label = "Walk me to school",
				minAge = 5,
				maxAge = 11,
				minBond = 20,
				bond = 3,
				ask = true,
				line = "Of course. Coat on -- it'll be nippy by the gate.",
				refusedLine = "Not this morning, love. You'll be fine on your own.",
				walksTo = "school",
				arrivalLine = "Here we are. In you go -- make it count.",
			},
			{
				id = "mom_held",
				label = "Put your arms up",
				minAge = 0,
				maxAge = 4,
				minBond = ALWAYS,
				bond = 4,
				stats = { happiness = 3 },
				line = "Come here, you. Up we go.",
			},
			{
				id = "mom_hug",
				label = "Give her a hug",
				minAge = 3,
				maxAge = 12,
				minBond = ALWAYS,
				bond = 3,
				stats = { happiness = 2 },
				line = "Oh, that's the best thing that's happened all day.",
			},
			{
				id = "mom_hello",
				label = "Say hello",
				minAge = 13,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 2,
				stats = { happiness = 1 },
				line = "Hello, you. Sit down, you look worn out.",
			},
			{
				id = "mom_show",
				label = "Show her what you found",
				minAge = 2,
				maxAge = 9,
				minBond = ALWAYS,
				bond = 3,
				stats = { happiness = 2 },
				line = "Well, would you look at that. We'd better put it somewhere safe.",
			},
			{
				-- The first offer in the game that costs the player something they want in
				-- exchange for something a person wants. Doing the washing up is not fun and
				-- the happiness figure says so; it buys more bond than anything else at this
				-- age, and that trade is the whole system in one pad.
				id = "mom_dishes",
				label = "Help with the washing up",
				minAge = 7,
				maxAge = 17,
				minBond = ALWAYS,
				bond = 5,
				stats = { happiness = -1 },
				line = "You didn't have to do that. Thank you, sweetheart.",
			},
			{
				id = "mom_school",
				label = "Tell her about school",
				minAge = 6,
				maxAge = 17,
				minBond = 0,
				bond = 4,
				stats = { happiness = 1, smarts = 1 },
				line = "Is that right? And what did you say back?",
			},
			{
				-- Venting genuinely does feel better, so it genuinely pays happiness -- and
				-- it costs more bond than any other single pad in the file. A negative offer
				-- that bought nothing would be a trap rather than a choice, and no pad in
				-- this game is allowed to be a trap.
				id = "mom_argue",
				label = "Argue about nothing",
				minAge = 12,
				maxAge = 19,
				minBond = ALWAYS,
				bond = -6,
				stats = { happiness = 2 },
				line = "Fine. Fine! Go on up to your room, then.",
			},
			{
				id = "mom_advice",
				label = "Ask her what she would do",
				minAge = 16,
				maxAge = 999,
				minBond = 20,
				bond = 3,
				stats = { smarts = 2 },
				line = "I'd sleep on it. Things look different in the morning, they really do.",
			},
			{
				id = "mom_loan",
				label = "Ask her for money",
				minAge = 16,
				maxAge = 999,
				minBond = 45,
				bond = -2,
				money = 300,
				line = "Don't tell your father. Pay me back when you've got it.",
				ask = true,
				refusedLine = "Not this month, love. I'm sorry. Ask me again after payday.",
			},
			{
				-- Requires something that happened at a different door. The neighbor made
				-- the call; she is the one who wants to hear about it, and she cannot want
				-- to hear about it until it happened. This is the shape the whole flag
				-- system exists for -- one person's answer changing what another person has
				-- to say -- and it is here in the smallest possible form, so the shape is
				-- exercised by the game rather than only described by a type.
				id = "mom_the_word",
				label = "Tell her about the phone call",
				minAge = 15,
				maxAge = 999,
				minBond = 20,
				bond = 4,
				stats = { happiness = 3 },
				requires = { "had_a_word_put_in" },
				line = "He did that for you? Oh, that's -- that's a good man, that is.",
			},
			{
				id = "mom_sit",
				label = "Sit with her a while",
				minAge = 25,
				maxAge = 999,
				minBond = 45,
				bond = 5,
				stats = { happiness = 3 },
				line = "You don't have to say anything. It's nice just having you here.",
			},
			-- Only while she knows you're poorly. The sick flag is set by events and
			-- cleared at the next birthday, so this row is the game noticing a state it
			-- set itself -- a mother who fusses, and only then. Even a child who has let
			-- the bond rot is still somebody's child when they're ill.
			{
				id = "mom_look_after",
				label = "Let her fuss over you",
				minAge = 13,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 3,
				stats = { happiness = 3, health = 2 },
				requires = { "sick" },
				line = "Sit down, sit down. I've got the honey out. You look dreadful.",
			},
			-- The first years away from home, in one tight window: too old to live here
			-- and too new to where they are to have stopped reaching back. A phone call
			-- that makes the distance stop mattering for an hour.
			{
				id = "mom_empty_nest",
				label = "Ring her from the new place",
				minAge = 18,
				maxAge = 24,
				minBond = 35,
				bond = 4,
				stats = { happiness = 3 },
				line = "Oh, it's you! I was just thinking about you. Tell me everything -- no, wait. The food first.",
			},
			-- The other half of the flag pair. Owning up to breaking something buys her
			-- pride in you; hiding it buys her quiet disappointment -- a row that is only
			-- ever on the floor because the player chose the hiding answer, which is the
			-- flag system doing what it is for.
			{
				id = "mom_broke_hid",
				label = "Show her the thing you hid",
				minAge = 6,
				maxAge = 12,
				minBond = ALWAYS,
				bond = -2,
				stats = { happiness = -1 },
				requires = { "broke_it_hid_it" },
				line = "Oh, love. I know. I've known since Tuesday. Let's just... put it right, shall we?",
			},
		},
	},
	{
		id = "dad",
		castId = "dad",
		placeId = "home",
		minAge = 0,
		maxAge = 999,
		-- Three years on your mother, which is nothing anybody will ever notice and is
		-- there because two parents born in the same year is the kind of tidiness a
		-- generated world has and a real one does not.
		ageOffset = 31,
		startingBond = 30,
		busyLine = "Not just now -- I'm in the middle of something. Catch me another time.",
		offers = {
			{
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 5,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				line = "Sometimes it's nice to just sit and say nowt.",
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				line = "...Fine. I can take a hint.",
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				line = "Right. Well. Enjoy your walk.",
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
				line = "That's my boy. Water under the bridge.",
				refusedLine = "Not yet, son. You hurt me there, and I mean that.",
			},
			{
				id = "walks_shop",
				label = "Come to the shop with me",
				minAge = 16,
				maxAge = 999,
				minBond = 25,
				bond = 3,
				ask = true,
				line = "Aye, alright. Let me grab my coat.",
				refusedLine = "I'm mid-fix on this. Rain check?",
				walksTo = "store",
				arrivalLine = "There we are, then. Good walk that was.",
			},
			{
				id = "walks_crossing",
				label = "Walk me to the crossing",
				minAge = 5,
				maxAge = 12,
				minBond = 20,
				bond = 3,
				ask = true,
				line = "Aye, come on then. Hold on tight at the lights.",
				refusedLine = "Not now, love -- I'm right in the middle of this.",
				walksTo = "crossing",
				arrivalLine = "There's the lights. Straight across and mind the gap.",
			},
			{
				id = "dad_carry",
				label = "Get carried around",
				minAge = 0,
				maxAge = 4,
				minBond = ALWAYS,
				bond = 4,
				stats = { happiness = 3 },
				line = "Right then. One lap of the house and that's your lot.",
			},
			{
				id = "dad_climb",
				label = "Climb on him",
				minAge = 3,
				maxAge = 9,
				minBond = ALWAYS,
				bond = 4,
				stats = { happiness = 3 },
				line = "Oof. You're getting heavy, you know that?",
			},
			{
				id = "dad_hello",
				label = "Say hello",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 2,
				stats = { happiness = 1 },
				line = "There you are. Pull up a chair, I'm not doing anything important.",
			},
			{
				id = "dad_how",
				label = "Ask him how something works",
				minAge = 5,
				maxAge = 14,
				minBond = ALWAYS,
				bond = 3,
				stats = { smarts = 2 },
				line = "Right. So. You see this bit here -- that's the bit that does the work.",
			},
			{
				id = "dad_car",
				label = "Help him fix the car",
				minAge = 10,
				maxAge = 17,
				minBond = 20,
				bond = 5,
				stats = { smarts = 1, happiness = -1 },
				line = "Pass me the ten mil. No, the -- that's the one. Good.",
			},
			{
				id = "dad_day",
				label = "Ask about his day",
				minAge = 12,
				maxAge = 999,
				minBond = 0,
				bond = 4,
				stats = { happiness = 1 },
				line = "Same as every day. Long. Ask me again tomorrow, it'll be the same.",
			},
			{
				id = "dad_loan",
				label = "Ask him for money",
				minAge = 16,
				maxAge = 999,
				minBond = 45,
				bond = -2,
				money = 300,
				line = "Here. Don't make a habit of it, and don't tell your mother.",
				ask = true,
				refusedLine = "I haven't got it. I'd give it you if I had it, but I haven't.",
			},
			{
				id = "dad_pint",
				label = "Sit and put the world right",
				minAge = 21,
				maxAge = 999,
				minBond = 45,
				bond = 5,
				stats = { happiness = 3 },
				line = "See, that's what I've been saying for years. Nobody listens.",
			},
			-- Owning up to breaking something is the one childhood choice this game
			-- outright rewards, and here is the reward arriving through a person instead
			-- of through a stat: the version of your father who knows you told the truth.
			{
				id = "dad_broke_up",
				label = "Tell him you owned up",
				minAge = 6,
				maxAge = 14,
				minBond = 20,
				bond = 4,
				stats = { smarts = 1 },
				requires = { "broke_it_owned_up" },
				line = "Good. That's the hard part, and you did it. I'm proud of you -- put it on the shelf, we'll fix it Saturday.",
			},
			-- The narrow years when you're old enough to ask and still young enough that
			-- the answer is yes. Driving lessons cost money; a father costs nothing but
			-- patience, and he has some left.
			{
				id = "dad_drive",
				label = "Ask him to teach you to drive",
				minAge = 17,
				maxAge = 19,
				minBond = 30,
				bond = 3,
				stats = { smarts = 2 },
				line = "Right then. Clutch down -- gently, gently. That's the one. No, that was the brake. We'll go again.",
			},
			-- The dog event set one of two flags; this is the one that made him proud.
			-- A small deed carried by a father: the player knelt to a strange dog at six
			-- and his dad is still quietly pleased about it years later.
			{
				id = "dad_the_dog",
				label = "Tell him about the dog",
				minAge = 6,
				maxAge = 14,
				minBond = 20,
				bond = 4,
				stats = { happiness = 2 },
				requires = { "dog_loved" },
				line = "You know what I'd have done at your age? I'd have run a mile. You didn't. That's the difference between us and there's nothing wrong with that.",
			},
		},
	},
	{
		id = "neighbor",
		castId = "neighbor",
		placeId = "store",
		-- Six rather than nought, because this is somebody a life meets rather than is
		-- born to, and a toddler does not have a relationship with a man at the shop.
		minAge = 6,
		maxAge = 999,
		-- Old enough when you meet him to already have had the forty years at the shop he
		-- talks about, which is the one fact his whole voice rests on. Also the person
		-- Config.Town.OldestShownAge exists for: a life that runs long enough eventually
		-- stands next to a man the arithmetic says is a hundred and twenty, because
		-- nothing in AGES dies of old age yet.
		ageOffset = 45,
		-- Nothing. He is the only person in the file you start out not knowing, which is
		-- what makes him the one whose bond is unarguably yours: everything it ever
		-- reaches was put there by turning up.
		startingBond = 0,
		busyLine = "Another time -- I'm on my way somewhere. Good to see you though.",
		offers = {
			{
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 6,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				line = "And how's the world treating you, eh?",
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				line = "...Right. I'll not take any more of your time.",
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				line = "Suit yourself. I've got a shop to mind.",
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
				line = "We all say things. Water under the bridge, eh?",
				refusedLine = "Well. That one's going to take a bit more than an apology, I think.",
			},
			{
				id = "walks_shop",
				label = "Come to the shop with me",
				minAge = 16,
				maxAge = 999,
				minBond = 25,
				bond = 3,
				ask = true,
				line = "Happy to walk you over. I was heading that way anyway.",
				refusedLine = "Can't today -- stock's in. Another time.",
				walksTo = "store",
				arrivalLine = "Here we are. I'll tell the lad you're a regular.",
			},
			{
				id = "walks_gate",
				label = "Walk me to the gate",
				minAge = 6,
				maxAge = 999,
				minBond = 20,
				bond = 3,
				ask = true,
				line = "Course I will. I was going that way anyhow.",
				refusedLine = "Not today -- I've got a pot on and the door's unlocked.",
				walksTo = "gate",
				arrivalLine = "There's your gate. I'll not come further in case the dog's out.",
			},
			{
				id = "nb_hello",
				label = "Say hello",
				minAge = 6,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 2,
				stats = { happiness = 1 },
				line = "Hello there. Keeping out of trouble, are we?",
			},
			{
				id = "nb_bags",
				label = "Carry his bags out",
				minAge = 8,
				maxAge = 999,
				minBond = ALWAYS,
				bond = 5,
				stats = { happiness = -1 },
				line = "That's very good of you. Very good of you indeed.",
			},
			{
				id = "nb_story",
				label = "Listen to one of his stories",
				minAge = 6,
				maxAge = 999,
				minBond = 0,
				bond = 4,
				stats = { smarts = 1, happiness = 1 },
				line = "-- and that, I can tell you, was the last time I ever went near a horse.",
			},
			{
				id = "nb_shop",
				label = "Ask him about the shop",
				minAge = 14,
				maxAge = 999,
				minBond = 20,
				bond = 3,
				stats = { smarts = 1 },
				line = "Forty years I've been coming here. I know everyone worth knowing.",
			},
			{
				-- The rung, and the only one he has. A neighbor is not going to become your
				-- closest friend and it would cheapen the word if he could -- what he can
				-- become is somebody who knows you, which is the entire currency of the
				-- offer below.
				id = "nb_known",
				label = "Tell him who you are",
				minAge = 6,
				maxAge = 999,
				minBond = 15,
				bond = 4,
				stats = { happiness = 1 },
				gives = "known",
				line = "I know the house. I never knew the face went with it. Well, now I do.",
			},
			{
				-- The pad that tells the player what the last twenty years were for. It does
				-- nothing on its own -- no money, no stat, barely any bond -- because the
				-- thing it is about has already happened: the office reads the bond itself.
				-- This is him saying so out loud, once, so the payoff is not a door that
				-- silently stopped being locked.
				--
				-- Gated on the rung as well as the bond, because his refusal line has been
				-- saying exactly this since before there was a system for it: he will not
				-- put his name to somebody he does not know. A man who would make that call
				-- for a stranger with a high bond is not a reference, he is a lever.
				id = "nb_word",
				label = "Ask if he knows anyone",
				minAge = 15,
				maxAge = 999,
				minBond = 45,
				bond = 1,
				needsTie = "known",
				-- Set on the yes only, which is the whole reason the favour is worth
				-- asking for rather than worth having: a call that was not made is not a
				-- call, and the flag is the record of one that was.
				sets = { "had_a_word_put_in" },
				line = "For you? I'll make a call. They know me up at that office.",
				ask = true,
				refusedLine = "I'd have to know you a bit better before I put my name to it.",
			},
			-- The nervous side of the bond range, at the positive end. Below "friendly"
			-- he is a man you nod at rather than talk to, and the moment the bond crosses
			-- 19 this row is gone -- the arc is written into the gate itself. A player who
			-- only ever waves never learns the man.
			{
				id = "nb_wave",
				label = "Give him a small wave across the shop",
				minAge = 6,
				maxAge = 999,
				minBond = ALWAYS,
				maxBond = 19,
				bond = 1,
				line = "He looks up, nods, and goes back to the till. You both know the score.",
			},
			-- Trust enough to be let behind the counter. The shop closes and the man
			-- who never learned your name is handing you the till float -- which is what
			-- twenty years of turning up actually bought.
			{
				id = "nb_close_up",
				label = "Stay and help him close up",
				minAge = 16,
				maxAge = 999,
				minBond = 35,
				bond = 4,
				stats = { smarts = 1, happiness = -1 },
				line = "You're a good 'un, you are. Right -- tills, floor, float, and I'll see you Wednesday.",
			},
		},
	},
	{
		id = "friend",
		castId = "friend",
		placeId = "school",
		minAge = 6,
		maxAge = 17,
		-- Your age exactly, which is what a schoolfriend is and the only reason the two of
		-- you were ever put in the same room.
		ageOffset = 0,
		-- A little warmth to begin with, because you are six and so are they and that is
		-- all it takes.
		startingBond = 10,
		busyLine = "Can't right now! Later, yeah?",
		offers = {
			{
				id = "small_talk",
				label = "Talk about nothing in particular",
				minAge = 6,
				maxAge = 17,
				minBond = ALWAYS,
				bond = 1,
				stats = { happiness = 2 },
				line = "Just us again, like always.",
			},
			{
				id = "snub",
				label = "Snub them",
				minAge = 10,
				maxAge = 17,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -5,
				line = "...Wow. Okay.",
			},
			{
				id = "cold_shoulder",
				label = "Give them the cold shoulder",
				minAge = 10,
				maxAge = 17,
				minBond = ALWAYS,
				maxBond = -5,
				bond = -7,
				line = "Oh. I thought we were... yeah. Fine.",
			},
			{
				id = "make_right",
				label = "Try to make it right",
				minAge = 10,
				maxAge = 17,
				minBond = ALWAYS,
				maxBond = -1,
				bond = 8,
				ask = true,
				line = "I was hoping you'd say that. Forgiven.",
				refusedLine = "I don't know, man. That really hurt.",
			},
			{
				id = "walks_shop",
				label = "Come to the shop with me",
				minAge = 16,
				maxAge = 17,
				minBond = 25,
				bond = 3,
				ask = true,
				line = "Yeah! Let's go. I'll race you.",
				refusedLine = "Can't -- detention. Talk at lunch, yeah?",
				walksTo = "store",
				arrivalLine = "Made it! See, that wasn't so hard.",
			},
			{
				id = "walks_crossing",
				label = "Walk to the crossing with me",
				minAge = 6,
				maxAge = 12,
				minBond = 20,
				bond = 3,
				ask = true,
				line = "Yeah! Last one to the crossing buys the sweets.",
				refusedLine = "Can't -- my mum said straight home today.",
				walksTo = "crossing",
				arrivalLine = "Beat you! Right, cross on the green.",
			},
			{
				id = "rae_hi",
				label = "Say hi",
				minAge = 6,
				maxAge = 17,
				minBond = ALWAYS,
				bond = 2,
				stats = { happiness = 1 },
				line = "Hey! Sit here, I saved you a spot.",
			},
			{
				id = "rae_lunch",
				label = "Share your lunch",
				minAge = 6,
				maxAge = 13,
				minBond = ALWAYS,
				bond = 5,
				stats = { happiness = 1 },
				line = "You're the best. I forgot mine again.",
			},
			{
				-- The one pad in the file with a long fuse on it. Smarts is what the office
				-- job asks for at eighteen, so an afternoon of messing about is genuinely
				-- fun, genuinely free, and genuinely costs you something you will not find
				-- out about for a decade. That is the most honest thing this game says
				-- about being fourteen.
				id = "rae_mess",
				label = "Mess about instead of working",
				minAge = 8,
				maxAge = 17,
				minBond = ALWAYS,
				bond = 4,
				stats = { happiness = 3, smarts = -2 },
				line = "We are going to get in so much trouble. Worth it though.",
			},
			{
				id = "rae_study",
				label = "Study together",
				minAge = 10,
				maxAge = 17,
				minBond = 20,
				bond = 3,
				stats = { smarts = 3 },
				line = "Okay, but you're explaining the last one to me. Properly this time.",
			},
			-- The ladder, and Rae is the one person in the game it was written backwards
			-- from: "the friend of a childhood" was always the description, and until ties
			-- existed there was nothing anywhere that could make it true rather than
			-- implied. A schoolfriend the game never once called your friend is a
			-- classmate with better dialogue.
			--
			-- No `known` rung. Rae opens at a bond of ten and says "sit here, I saved you
			-- a spot" the first time you ever speak to them -- somebody who does that
			-- already knows you, and a row offering to introduce yourself would be the
			-- game contradicting its own first line.
			{
				id = "rae_always",
				label = "Make it the two of you, every day",
				minAge = 8,
				maxAge = 17,
				minBond = 35,
				bond = 6,
				stats = { happiness = 3 },
				gives = "friend",
				line = "Well, obviously. Who else was it going to be?",
			},
			{
				id = "rae_secret",
				label = "Tell them something you've told nobody",
				minAge = 13,
				maxAge = 17,
				minBond = 45,
				bond = 7,
				stats = { happiness = 3 },
				needsTie = "friend",
				line = "Okay. That stays with me. Obviously it does.",
			},
			{
				-- The top rung, and deliberately at the very end of the school years --
				-- the last thing Rae has to offer, in the last year they are in the life
				-- at all. That it lands the year before they age out is the point: this
				-- is a promise made at exactly the moment it stops being easy to keep.
				id = "rae_whatever_happens",
				label = "Promise it survives this place",
				minAge = 16,
				maxAge = 17,
				minBond = 70,
				bond = 9,
				stats = { happiness = 5 },
				needsTie = "friend",
				gives = "closest",
				line = "Then that's that. Wherever we both end up -- that's that.",
			},
			{
				-- The first pad in the game that is on the floor because of something the
				-- player did rather than something they are old enough for, and the
				-- clearest statement of what the flag system is for: a friendship where
				-- one of you knows a thing about the other is a different friendship, and
				-- this is what that looks like from the outside -- one extra option, in
				-- front of one person, that most lives never see.
				--
				-- Never a floor offer. Somebody's whole visit must never depend on a flag,
				-- or a life that did not earn it walks up to an empty patch of ground; the
				-- content check below counts on this and refuses a floor offer that is
				-- gated.
				id = "rae_show_the_gap",
				label = "Show them the way out of the field",
				minAge = 8,
				maxAge = 17,
				minBond = 15,
				bond = 8,
				stats = { happiness = 4, smarts = -1 },
				requires = { "wandered_off" },
				line = "How long have you known about this? How long have you KNOWN about this?",
			},
			{
				id = "rae_the_dog",
				label = "Take them to see the dog outside the shop",
				minAge = 8,
				maxAge = 15,
				minBond = 15,
				bond = 6,
				stats = { happiness = 3 },
				requires = { "dog_loved" },
				line = "Okay, you were right about it. I'm still not putting my hand near it though.",
			},
			-- The nervous early friendship, gone the moment it stops being necessary.
			-- Bond shapes it: below "friendly" you don't yet know what to say to each
			-- other, and the row vanishes at the top of the range -- the arc is in the
			-- gate, not in any writing.
			{
				id = "rae_quiet",
				label = "Sit next to them without saying anything",
				minAge = 6,
				maxAge = 12,
				minBond = ALWAYS,
				maxBond = 19,
				bond = 2,
				line = "Neither of you says anything for a while. Then they pass you half their crisps without looking up.",
			},
			-- The last school year, and the line the file's header says was missing:
			-- Rae ages out at seventeen and the game used to let that happen without a
			-- word. This is the word -- a row that appears exactly in the year it stops
			-- being possible to put the question off.
			{
				id = "rae_last_year",
				label = "Ask what happens after school",
				minAge = 16,
				maxAge = 17,
				minBond = 25,
				bond = 4,
				stats = { happiness = 1, smarts = 1 },
				line = "Dunno. We'll figure it out. That's kind of the whole thing -- we'll figure it out together.",
			},
			-- The dog event's other half. Rae shields you -- but only because you are
			-- the one who was ever frightened, which is a flag only a frightened life
			-- carries. The row is the game remembering a fear it set itself.
			{
				id = "rae_dog_feared",
				label = "Get them to stand between you and the dog",
				minAge = 6,
				maxAge = 15,
				minBond = 10,
				bond = 6,
				stats = { happiness = 2 },
				requires = { "dog_feared" },
				line = "Yeah, of course. It won't come near you -- I've got it. See? All good.",
			},
		},
	},
}

local all: { Person } = {}
local byId: { [string]: Person } = {}
local byPlace: { [string]: { Person } } = {}

-- Content mistakes are authoring bugs, not runtime conditions, so these throw at start
-- rather than producing somebody who stands in a room with an empty floor in front of
-- them and no way to say why.
local function validateOffer(person: Person, offer: PersonOffer, seen: { [string]: boolean })
	if seen[offer.id] then
		error(`[AGES content] person "{person.id}" has two offers with id "{offer.id}"`)
	end
	seen[offer.id] = true

	if offer.label == "" then
		error(`[AGES content] offer "{offer.id}" has no label, so its pad would be blank`)
	end
	if #offer.label > PEOPLE.MaxLabelLength then
		error(
			`[AGES content] offer "{offer.id}" has a {#offer.label}-character label; a pad holds `
				.. `{PEOPLE.MaxLabelLength}`
		)
	end
	if offer.line == "" then
		error(`[AGES content] offer "{offer.id}" has nothing said back, which is the point of it`)
	end

	-- Both directions, because both mistakes are silent at runtime. An ask with no
	-- refusal line shows a blank row on the one beat the player most needs a person in
	-- front of them; a refusal line on something that can never be refused is dead
	-- writing that reads, to the next author, as proof this offer can be turned down.
	local refusedLine = offer.refusedLine
	if offer.ask then
		if refusedLine == nil or refusedLine == "" then
			error(
				`[AGES content] offer "{offer.id}" is an ask, so it can be turned down, but has no `
					.. `refusedLine -- write what they say when they say no`
			)
		end
	elseif refusedLine ~= nil then
		error(
			`[AGES content] offer "{offer.id}" has a refusedLine but is not an ask, so it can never `
				.. `be refused; set ask = true or drop the line`
		)
	end

	if offer.minAge > offer.maxAge then
		error(`[AGES content] offer "{offer.id}" starts at {offer.minAge} and ends at {offer.maxAge}`)
	end
	-- Inside the person's own window, or the offer is written for years they are not
	-- there for -- which is invisible by reading either table on its own.
	if offer.minAge < person.minAge or offer.maxAge > person.maxAge then
		error(
			`[AGES content] offer "{offer.id}" runs {offer.minAge}-{offer.maxAge} but "{person.id}" `
				.. `is only around {person.minAge}-{person.maxAge}`
		)
	end

	if offer.minBond < PEOPLE.MinBond or offer.minBond > PEOPLE.MaxBond then
		error(
			`[AGES content] offer "{offer.id}" needs a bond of {offer.minBond}, outside the range `
				.. `{PEOPLE.MinBond}..{PEOPLE.MaxBond}, so it could never appear`
		)
	end

	-- The upper gate, the mirror of minBond. Two ends of one window, so a pair that
	-- reads as an empty window is caught here rather than by a panel that never fills.
	local maxBond = offer.maxBond
	if maxBond ~= nil then
		if maxBond < PEOPLE.MinBond or maxBond > PEOPLE.MaxBond then
			error(
				`[AGES content] offer "{offer.id}" is gone above a bond of {maxBond}, outside the `
					.. `range {PEOPLE.MinBond}..{PEOPLE.MaxBond}`
			)
		end
		if maxBond < offer.minBond then
			error(
				`[AGES content] offer "{offer.id}" needs {offer.minBond} and is gone above {maxBond}; `
					.. `a maxBond below its minBond is an offer nothing could ever be at`
			)
		end
	end

	-- A walk offer has to name a place the world can actually get to. The list it is
	-- checked against is deliberately small and lives in Config, separate from the
	-- world's parts -- the parts are built by the Street, and this is where a typo in
	-- content is caught at load rather than as an offer that starts a walk to nowhere.
	local walksTo = offer.walksTo
	if walksTo ~= nil then
		local known = false
		for _, id in Config.Places.Walkable do
			if id == walksTo then
				known = true
				break
			end
		end
		if not known then
			error(
				`[AGES content] offer "{offer.id}" walks to "{walksTo}", which is not in `
					.. `Config.Places.Walkable -- add the id there or fix the offer`
			)
		end
		if offer.arrivalLine == nil or offer.arrivalLine == "" then
			error(
				`[AGES content] offer "{offer.id}" walks to "{walksTo}" but has no arrivalLine -- `
					.. `say what they say when the place is reached`
			)
		end
	elseif offer.arrivalLine ~= nil then
		error(
			`[AGES content] offer "{offer.id}" has an arrivalLine but nothing to walk to; set `
				.. `walksTo or drop the line`
		)
	end

	local money = offer.money
	if money ~= nil then
		if money ~= math.floor(money) then
			error(`[AGES content] offer "{offer.id}" moves {money}; money is whole units only`)
		end
		-- Given, never taken, and this is a real restriction rather than a coincidence of
		-- what happens to be written today. The panel itself is willing -- it draws a price
		-- column and greys a row the player cannot pay for -- but PeopleService hands every
		-- offer over with no cost and no lock, and takes one without ever reading a wallet.
		-- So a negative figure here would not present as a price refused, it would present
		-- as an offer that silently empties a pocket it could not reach. Charging means
		-- pricing and gating in PeopleService first; this is where that gets said out loud.
		if money <= 0 then
			error(
				`[AGES content] offer "{offer.id}" moves {money}; an offer can only hand money over, `
					.. `because nothing on the people side checks the player can pay`
			)
		end
		if money > PEOPLE.MaxGift then
			error(
				`[AGES content] offer "{offer.id}" gives {money}, over the {PEOPLE.MaxGift} ceiling -- `
					.. `check for a stray zero`
			)
		end
	end

	local stats = offer.stats
	if stats ~= nil then
		for name in stats do
			if not VALID_STATS[name] then
				error(`[AGES content] offer "{offer.id}" moves "{name}", which is not a stat`)
			end
		end
	end

	local where = `person "{person.id}" offer "{offer.id}"`
	Flags.AssertKnown(offer.requires, where)
	Flags.AssertKnown(offer.forbids, where)
	Flags.AssertSatisfiable(offer.requires, offer.forbids, where)
	Flags.AssertKnown(offer.sets, where)
	Flags.AssertKnown(offer.clears, where)
	Flags.AssertNotBoth(offer.sets, offer.clears, where)

	Ties.AssertKnown(offer.gives, where)
	Ties.AssertKnown(offer.needsTie, where)

	-- A rung has to climb. `gives` at or below what `needsTie` already guarantees is an
	-- offer that is either invisible or does nothing, and which of the two it is depends
	-- on a rank comparison in another file -- so it is far better refused here than
	-- found by wondering why a panel row never appears.
	local gives = offer.gives
	-- "Does the tie this row already requires get you what the row hands out?" -- and if so
	-- the row can never appear. Asked through `Ties.Meets` rather than as a rank comparison,
	-- because rank 0 is shared by "off the ladder" and "no tie at all", so an offer giving
	-- "enemy" from no tie read as 0 <= 0 and was rejected as a rung that fails to climb. See
	-- `Ties.IsRung` for why naming the id "enemy" here instead was the wrong repair.
	if gives ~= nil and Ties.Meets(offer.needsTie, gives) then
		error(
			`[AGES content] offer "{offer.id}" gives "{gives}" but already needs `
				.. `"{offer.needsTie}", which already satisfies it -- the row could never appear`
		)
	end

	-- An ask that confers a *rung* would let a refusal be the thing standing between a
	-- player and the one relationship rung the game caps. Refused rather than resolved,
	-- because both resolutions are bad: paying it out on a no makes the refusal cosmetic,
	-- and withholding it makes a coin flip the gate on the scarcest thing here.
	--
	-- None of that is true off the ladder. "Make them your enemy" is done *to* somebody, and
	-- them refusing it is the content rather than a hole in it.
	if gives ~= nil and offer.ask and Ties.IsRung(gives) then
		error(
			`[AGES content] offer "{offer.id}" gives "{gives}" and is an ask; a rung that can be `
				.. `refused would make becoming somebody's friend a coin toss`
		)
	end
end

local function validate(person: Person)
	if byId[person.id] ~= nil then
		error(`[AGES content] duplicate person id "{person.id}"`)
	end
	if Cast.ById[person.castId] == nil then
		error(`[AGES content] person "{person.id}" is cast as "{person.castId}", who is not in the cast`)
	end
	if person.placeId == "" then
		error(`[AGES content] person "{person.id}" names no place, so there is nowhere for them to be`)
	end
	if person.busyLine == "" then
		error(`[AGES content] person "{person.id}" has no way of saying they are busy`)
	end
	if person.minAge > person.maxAge or person.minAge < 0 then
		error(`[AGES content] person "{person.id}" is around from {person.minAge} to {person.maxAge}`)
	end
	if person.ageOffset ~= math.floor(person.ageOffset) then
		error(`[AGES content] person "{person.id}" is {person.ageOffset} years older than you; ages are whole years`)
	end
	-- The one way an age offset can be wrong that reading it does not show: a person is
	-- only ever seen from inside their own age window, so an offset is fine or not fine
	-- relative to the youngest the player can be when they meet them. Get it wrong and
	-- the nameplate over somebody's head says they are minus two.
	if person.minAge + person.ageOffset < 0 then
		error(
			`[AGES content] person "{person.id}" is {person.ageOffset} years older than you and around `
				.. `from age {person.minAge}, so they would be {person.minAge + person.ageOffset} when you meet them`
		)
	end
	if person.startingBond < PEOPLE.MinBond or person.startingBond > PEOPLE.MaxBond then
		error(
			`[AGES content] person "{person.id}" starts at {person.startingBond}, outside `
				.. `{PEOPLE.MinBond}..{PEOPLE.MaxBond}`
		)
	end
	if #person.offers == 0 then
		error(`[AGES content] person "{person.id}" offers nothing, so walking up to them does nothing`)
	end

	Flags.AssertKnown(person.requires, `person "{person.id}"`)
	Flags.AssertKnown(person.forbids, `person "{person.id}"`)
	Flags.AssertSatisfiable(person.requires, person.forbids, `person "{person.id}"`)

	local seen: { [string]: boolean } = {}
	-- Which offer hands out each rung, so two of them handing out the same one is caught
	-- and so a rung nothing reaches can be.
	local ladder: { [string]: string } = {}
	for _, offer in person.offers do
		validateOffer(person, offer, seen)
		local gives = offer.gives
		if gives ~= nil then
			local clash = ladder[gives]
			if clash ~= nil then
				error(
					`[AGES content] person "{person.id}" reaches "{gives}" from both "{clash}" and `
						.. `"{offer.id}"; a rung is one row, or the player is shown two ways to `
						.. `become the same thing`
				)
			end
			ladder[gives] = offer.id
		end
	end

	-- A rung nobody can stand on. `needsTie` is satisfied by that tie or anything closer,
	-- and a tie is always a tie with one particular person -- so an offer needing "friend"
	-- is dead unless *this* person is somebody you can become a friend of. Dead in the
	-- silent way, too: a row that never appears looks exactly like a row you have not
	-- earned yet.
	for _, offer in person.offers do
		local needed = offer.needsTie
		if needed == nil then
			continue
		end
		local reachable = false
		for tieId in ladder do
			-- The same question the runtime gate asks, asked with the same function. As a
			-- rank comparison it called a row needing an off-ladder tie "reachable" the
			-- moment this person offered *anything*, because every rank is >= 0 -- so the
			-- one check that exists to find dead content would have certified it.
			if Ties.Meets(tieId, needed) then
				reachable = true
				break
			end
		end
		if not reachable then
			error(
				`[AGES content] person "{person.id}" offer "{offer.id}" needs "{needed}" but nothing `
					.. `they offer ever reaches it, so the row can never appear`
			)
		end
	end

	-- The check that earns its keep. Somebody standing in a room with nothing on the
	-- floor in front of them is the one failure of this system that looks exactly like a
	-- bug in the pad placement, and it is only ever caused here -- by an age with no
	-- offer written that anybody could take at any bond.
	for age = person.minAge, person.maxAge do
		local floor = 0
		local labels: { [string]: string } = {}
		for _, offer in person.offers do
			if age < offer.minAge or age > offer.maxAge then
				continue
			end
			-- Two identical labels on one floor is unreadable and cannot be seen by reading
			-- either offer on its own, only by reading the pair at an age they share.
			local clash = labels[offer.label]
			if clash ~= nil then
				error(
					`[AGES content] person "{person.id}" offers "{offer.label}" twice at age {age} `
						.. `("{clash}" and "{offer.id}")`
				)
			end
			labels[offer.label] = offer.id
			-- A conditional offer does not count toward the floor however low its bond
			-- is, because the floor's whole job is to be there for everybody and a life
			-- that never earned the condition would find the room empty. The check would
			-- otherwise pass on content that is broken for most players, which is worse
			-- than no check.
			--
			-- A rung is conditional in both directions, and the second one is the easy
			-- mistake to make: `needsTie` hides the row until you have climbed, and
			-- `gives` hides it again the moment you have -- so an offer that hands out a
			-- tie is the one kind that can be on the floor today and gone tomorrow with
			-- nothing about the life having got worse. It must never be what somebody's
			-- floor rests on.
			local unconditional = offer.requires == nil
				and offer.forbids == nil
				and offer.gives == nil
				and offer.needsTie == nil
			if offer.minBond <= PEOPLE.MinBond and unconditional then
				floor += 1
			end
		end
		if floor == 0 then
			error(
				`[AGES content] person "{person.id}" has nothing at age {age} that somebody at the `
					.. `bottom of the bond range could take; write one at minBond = MinBond`
			)
		end
	end
end

-- The town, folded in behind the four. They are the same shape and they go through the
-- same validator, which is most of why generating them is affordable at all: the floor
-- check, the age windows, the label clashes and the gift ceiling all apply to a stranger
-- at the shop exactly as they do to your mother, so a generator bug surfaces at server
-- start naming the person it made rather than as an empty patch of pavement.
for _, person in Townsfolk.People do
	table.insert(SOURCE, person)
end

for _, person in SOURCE do
	validate(person)
	byId[person.id] = person
	table.insert(all, person)
	local here = byPlace[person.placeId]
	if here == nil then
		here = {}
		byPlace[person.placeId] = here
	end
	table.insert(here, person)
end

local People = {}

People.All = all
People.ById = byId

-- Everybody who lives at a place, whatever age they are around for. Never nil, so a
-- caller can loop it without asking first.
function People.At(placeId: string): { Person }
	return byPlace[placeId] or {}
end

-- Whether this person is in the player's life at this age at all. The one question that
-- decides whether they are spawned, decayed against, or listed.
-- Flags are taken alongside age because the two say the same kind of thing -- whether
-- this person is in your life yet -- and separating them would let one caller ask about
-- years and another about history, which is how somebody ends up spawned in the world
-- and absent from the listing that explains who is spawned.
function People.IsAround(person: Person, age: number, flags: FlagSet): boolean
	if age < person.minAge or age > person.maxAge then
		return false
	end
	return Flags.Meets(flags, person.requires, person.forbids)
end

-- What somebody thinks of a profile, with the authored starting point already applied.
-- Nil for a person who is not written, which the caller has to treat as "no opinion" --
-- never as zero, because zero is a real bond somebody can be at.
--
-- Here rather than in PeopleService because the missing half of the answer is content:
-- an absent key means nothing has ever moved this relationship, and only this file knows
-- where a relationship opens. Takes the bonds table rather than the profile so the two
-- systems a bond pays into -- an allowance and a job reference -- can ask without either
-- of them having to know what a profile is.
function People.BondIn(bonds: { [string]: number }, personId: string): number?
	local person = byId[personId]
	if person == nil then
		return nil
	end
	local held = bonds[personId]
	if held == nil then
		return person.startingBond
	end
	return held
end

-- Which capped ties have no room left, given who is currently in the life.
--
-- The counting rule is the interesting part. A tie held by somebody whose years have
-- passed does not hold the slot: a closest friend from school who is no longer in your
-- life must not be the reason nobody at work can ever be one. Otherwise the single
-- scarcest thing in the game would be spent, permanently, by an eleven-year-old -- and
-- the player would have no way at all to find out why the row stopped appearing.
--
-- The tie itself is left alone either way. They are still on the record as what they
-- were, which is the truth about a friendship you had; the slot simply reopens.
function People.TieRoom(
	ties: { [string]: string },
	age: number,
	flags: FlagSet
): { [string]: boolean }
	local held: { [string]: number } = {}
	for personId, tieId in ties do
		local person = byId[personId]
		if person == nil or not People.IsAround(person, age, flags) then
			continue
		end
		held[tieId] = (held[tieId] or 0) + 1
	end

	local full: { [string]: boolean } = {}
	for _, def in Ties.All do
		local limit = def.limit
		if limit ~= nil and (held[def.id] or 0) >= limit then
			full[def.id] = true
		end
	end
	return full
end

-- Whether this id belongs to the generated town rather than to the four.
--
-- The one thing outside this file that has to be able to tell them apart, and it is not
-- about who they are -- it is about cost. Your mother is spawned the moment you have a
-- profile and stays; a stranger at the shop is given a body when you are near enough to
-- see them and takes it away again when you are not. Doing that to a parent would mean a
-- house that empties out when you walk to the far end of it.
function People.IsTown(personId: string): boolean
	return Townsfolk.IsTown[personId] == true
end

-- Which kind of townsperson somebody is, for the harness only. Nil for the four, who are
-- not a kind of anything.
function People.ArchetypeOf(personId: string): string?
	return Townsfolk.ArchetypeOf[personId]
end

-- How old somebody is, to write over their head. Nil past Config.Town.OldestShownAge,
-- and the nil is deliberate rather than a clamp.
--
-- Nobody in AGES dies of old age yet, so a life that runs to eighty stands next to a
-- neighbor the arithmetic says is a hundred and twenty-five. A clamped number would be a
-- lie the game had decided to tell; no number at all is the game declining to claim
-- something it does not model. `/town` counts how many people are past it, so the hole
-- stays visible until NPC mortality closes it properly.
function People.ShownAge(person: Person, playerAge: number): number?
	local age = playerAge + person.ageOffset
	if age > Config.Town.OldestShownAge then
		return nil
	end
	return math.max(age, 0)
end

-- What goes on the panel when somebody is clicked, best first.
--
-- Sorted by what the offer asks of the bond rather than shuffled, and that ordering is
-- the mechanic rather than a tidiness choice. There are more offers written than there
-- are rows to put them on, so the ones that need the most are the ones that get shown --
-- which means a rising bond visibly pushes the small talk off the list and replaces it
-- with money, comfort and favours. The player never reads a number; they watch what
-- somebody is willing to offer them get more generous.
--
-- Deterministic, so the same visit shows the same panel. A once-a-year decision that
-- reshuffled itself would be a slot machine.
--
-- Everything about the life that can hide or reveal a row, gathered into one argument
-- rather than four. Assembled by PeopleService, because two of these are facts about the
-- whole roster rather than about this person, and the content layer has no roster.
export type OfferContext = {
	age: number,
	bond: number,
	flags: FlagSet,
	-- What this person already is to the player, or nil.
	tie: string?,
	-- Tie ids that have no room left -- Ties with a `limit` already spoken for by
	-- somebody still in the player's life. An offer that would confer one of these is
	-- not shown, which is how "you get one closest friend" is enforced without ever
	-- taking one away from the person who has it.
	tieFull: { [string]: boolean },
}

function People.OffersFor(person: Person, context: OfferContext): { PersonOffer }
	local eligible: { PersonOffer } = {}
	for _, offer in person.offers do
		if context.age < offer.minAge or context.age > offer.maxAge or context.bond < offer.minBond then
			continue
		end
		-- The upper gate: a hostile offer is only on the floor while the relationship is
		-- actually cold, and the apology is only on the floor while it has something to
		-- fix. Both vanish as the bond climbs back past their maxBond, which is what makes
		-- the damage range-shaped rather than permanent.
		if offer.maxBond ~= nil and context.bond > offer.maxBond then
			continue
		end
		if not Flags.Meets(context.flags, offer.requires, offer.forbids) then
			continue
		end
		if not Ties.Meets(context.tie, offer.needsTie) then
			continue
		end
		local gives = offer.gives
		if gives ~= nil then
			-- Something already held, with this person or with anybody. Hidden rather than
			-- shown-and-refused, because a row offering to make somebody your friend when
			-- they already are reads as a bug in the game rather than as a rule.
			--
			-- `Ties.Meets` is what "already held" means, and it means two different things
			-- on purpose. On the ladder it is "at this rung or above", so climbing past
			-- friend retires the friend row. Off the ladder it is "is exactly this", because
			-- a fall is not a height: burning the ladder stays available from *any* rung --
			-- closest, mentor, rival, sibling -- and is held off by bond instead
			-- (minBond = ALWAYS, maxBond = -20), so it only surfaces once the relationship
			-- has already been destroyed. The one thing it does retire is itself: there is
			-- no offer to make an enemy of somebody who is already your enemy.
			if Ties.Meets(context.tie, gives) or context.tieFull[gives] then
				continue
			end
		end
		table.insert(eligible, offer)
	end

	-- Written order, so the sort can fall back on it: two offers asking the same bond come
	-- out in the order they were authored, which keeps the list stable between visits.
	local order: { [string]: number } = {}
	for index, offer in person.offers do
		order[offer.id] = index
	end
	table.sort(eligible, function(a: PersonOffer, b: PersonOffer): boolean
		-- A rung outranks everything, and this is not a tidiness choice either. There are
		-- more offers eligible than there are rows, so the tail of the list is thrown
		-- away -- and the one row that must never be the one thrown away is the one that
		-- changes what two people are to each other. It happens a handful of times in a
		-- whole life and it is the only row that cannot be had again next year.
		local aGives = a.gives ~= nil
		local bGives = b.gives ~= nil
		if aGives ~= bGives then
			return aGives
		end
		if a.minBond ~= b.minBond then
			return a.minBond > b.minBond
		end
		return order[a.id] < order[b.id]
	end)

	local picked: { PersonOffer } = {}
	for index = 1, math.min(PEOPLE.MaxOffers, #eligible) do
		table.insert(picked, eligible[index])
	end
	return picked
end

return People
