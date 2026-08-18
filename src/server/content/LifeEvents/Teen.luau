--!strict
-- Ages 13-17. The first years where a choice can cost something real, so the
-- stat swings are wider than childhood's and more of them cut both ways.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LifeEvent = Types.LifeEvent

local Teen: { LifeEvent } = {
	{
		id = "teen_night_before",
		minAge = 15,
		maxAge = 17,
		delivery = "Direct",
		prompt = "Big exam in the morning. It's already late and you've covered about half of what you meant to.",
		writesBack = { "stat:happiness", "stat:health", "stat:looks", "stat:smarts" },
		choices = {
			{
				id = "all_night",
				label = "Stay up and do the rest",
				outcome = "You got through it all by three in the morning and took the exam on four hours' sleep. You passed, and you felt terrible for two days.",
				effects = { smarts = 6, health = -4, looks = -2 },
			},
			{
				id = "sleep",
				label = "Go to bed",
				outcome = "You shut the book and slept properly. You didn't know everything, but what you did know came out cleanly.",
				effects = { health = 4, smarts = 2, happiness = 1 },
			},
			{
				id = "give_up",
				label = "Give up and watch something",
				outcome = "You watched three hours of nothing and went in cold. It went about as well as you'd expect, and it stung enough to change how you did it next time.",
				effects = { smarts = -3, happiness = 2, health = -1 },
			},
		},
	},
	{
		id = "teen_first_job",
		minAge = 15,
		maxAge = 17,
		delivery = "Direct",
		prompt = "There's a weekend job going. It's dull, it's badly paid, and it's yours if you want it.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "take_it",
				label = "Take it",
				outcome = "Six months of early Saturdays. You were tired constantly and you have never since been impressed by anyone complaining about hard work.",
				effects = { smarts = 4, health = -2, happiness = -1 },
				-- Six hours a Saturday for six months at a teenager's rate, which is
				-- well under the twenty an adult hour is worth in this game -- the
				-- prompt says badly paid and the figure has to agree with it. Held as
				-- one sum rather than paid weekly because the outcome covers the whole
				-- six months in a sentence; when careers exist they will pay by the
				-- hour and this stays what it is, a first job summarized.
				payout = 1800,
			},
			{
				id = "study_instead",
				label = "Turn it down and use the time to study",
				outcome = "You kept your weekends and put them into your own work. It paid off later, though it didn't feel like it at the time.",
				effects = { smarts = 5, happiness = -2 },
			},
			{
				id = "free_time",
				label = "Turn it down and do nothing in particular",
				outcome = "You spent those Saturdays with your friends doing absolutely nothing. You'd defend that decision now.",
				effects = { happiness = 6, smarts = -2 },
			},
		},
	},
	{
		id = "teen_dance",
		minAge = 14,
		maxAge = 17,
		delivery = "NPCApproach",
		cast = "friend",
		prompt = "There's a thing on Friday and everyone's going. Your friend has just turned up on the doorstep to make sure you're in.",
		writesBack = { "stat:happiness", "stat:health", "stat:looks", "stat:smarts" },
		choices = {
			{
				id = "go_alone",
				label = "Go on your own and see who's there",
				outcome = "You walked in alone, which was the hardest part, and then it was fine. It was better than fine.",
				effects = { happiness = 5, looks = 2, smarts = 1 },
			},
			{
				id = "go_with",
				label = "Only go if someone goes with you",
				outcome = "You found someone to walk in with. You spent most of it talking to them in a hallway, which turned out to be the good bit.",
				effects = { happiness = 4, looks = 1 },
			},
			{
				id = "stay_home",
				label = "Stay home",
				outcome = "You stayed in and heard about it all on Monday. You've wondered about it occasionally ever since.",
				effects = { happiness = -4, smarts = 2, health = 1 },
			},
		},
	},
	{
		id = "teen_borrowed_trouble",
		minAge = 13,
		maxAge = 17,
		delivery = "NPCApproach",
		cast = "friend",
		prompt = "Your friends are walking out of the store with things they haven't paid for. One of them is holding the door for you.",
		writesBack = { "stat:happiness", "stat:health", "stat:looks", "stat:smarts" },
		choices = {
			{
				id = "walk_out",
				label = "Walk out with them",
				outcome = "Nothing happened, which was almost worse. You spent the next week convinced you'd be found out, and you never did it again.",
				effects = { happiness = -4, smarts = 2, health = -1 },
			},
			{
				id = "pay",
				label = "Pay for yours and leave",
				outcome = "You stood in line like an idiot while they waited outside laughing. Two of them got caught the following month.",
				effects = { smarts = 5, happiness = -1 },
				-- The price of doing the right thing, and it is deliberately small: this
				-- is whatever a teenager is holding in a store, not a purchase to weigh
				-- up. What makes it worth having is what happens when the answer is no
				-- -- a player with nothing in their pocket finds this choice locked and
				-- has to walk out or speak up, which is a truer version of the moment
				-- than one where paying is always available.
				cost = 8,
			},
			{
				id = "stop_them",
				label = "Tell them to put it back",
				outcome = "You said it out loud and it landed badly. One of them listened, though, and told you so years later.",
				effects = { smarts = 4, happiness = -2, looks = 1 },
			},
		},
	},

	-- Being unwell, mid-teens: the first sickness that can cost you something you
	-- chose. Forbids an illness the birthday roll already started, and weighted
	-- below an ordinary event -- either answer commits the rest of the year.
	{
		id = "teen_sick_that_week",
		minAge = 13,
		maxAge = 17,
		delivery = "Direct",
		forbids = { "sick" },
		weight = 0.5,
		prompt = "You've gone and come down with something, and you're meant to be out this weekend. You can feel it in your bones already.",
		writesBack = { "stat:happiness", "stat:health", "flag:sick" },
		choices = {
			{
				id = "call_it_off",
				label = "Call it off and rest",
				outcome = "You cancelled and spent the weekend on the sofa with the heating on. You got better. You're still slightly annoyed about it.",
				effects = { health = 4, happiness = -2 },
				sets = { "sick" },
			},
			{
				id = "go_anyway_teen",
				label = "Go anyway",
				outcome = "You went, and you were a ghost at your own night. You paid for it for a week afterwards, and you'd make the same call again.",
				effects = { happiness = 3, health = -3 },
				sets = { "sick" },
			},
		},
	},
}

return Teen
