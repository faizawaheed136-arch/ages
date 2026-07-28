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
		choices = {
			{
				id = "all_night",
				label = "Stay up and do the rest",
				outcome = "You got through it all by three in the morning and sat the exam on four hours' sleep. You passed, and you felt terrible for two days.",
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
		choices = {
			{
				id = "take_it",
				label = "Take it",
				outcome = "Six months of early Saturdays. You were tired constantly and you have never since been impressed by anyone complaining about hard work.",
				effects = { smarts = 4, health = -2, happiness = -1 },
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
		delivery = "Direct",
		prompt = "There's a thing on Friday. Everyone's going. You've been standing near the door of it in your head all week.",
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
				outcome = "You found someone to walk in with. You spent most of it talking to them in a corridor, which turned out to be the good bit.",
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
		delivery = "Direct",
		prompt = "Your friends are walking out of the shop with things they haven't paid for. One of them is holding the door for you.",
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
				outcome = "You queued up like an idiot while they waited outside laughing. Two of them got caught the following month.",
				effects = { smarts = 5, happiness = -1 },
			},
			{
				id = "stop_them",
				label = "Tell them to put it back",
				outcome = "You said it out loud and it landed badly. One of them listened, though, and told you so years later.",
				effects = { smarts = 4, happiness = -2, looks = 1 },
			},
		},
	},
}

return Teen
