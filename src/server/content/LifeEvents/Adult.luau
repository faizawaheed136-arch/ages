--!strict
-- Ages 18 and up, including the elder years. Adulthood is the longest stretch
-- of a life by far, so entries here are written to stay plausible across a wide
-- age band rather than pinning to a specific year.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LifeEvent = Types.LifeEvent

local Adult: { LifeEvent } = {
	{
		id = "adult_january",
		minAge = 18,
		maxAge = 55,
		delivery = "NPCApproach",
		cast = "neighbor",
		prompt = "It's January and you've signed up for something that involves getting up early and hurting on purpose. The neighbor has seen you carrying the bag and has come to say what everyone is saying.",
		choices = {
			{
				id = "stick",
				label = "Actually go, every week",
				outcome = "You went for eleven months straight. You felt better than you had in years and became insufferable about it.",
				effects = { health = 7, looks = 4, happiness = 2 },
			},
			{
				id = "twice",
				label = "Go twice and quietly stop",
				outcome = "You went twice. The charge kept coming out for another fourteen months before you noticed.",
				effects = { happiness = -2, health = 1 },
			},
			{
				id = "own_way",
				label = "Cancel it and just walk everywhere instead",
				outcome = "You walked. Everywhere, in all weathers, for years. It did more than the membership ever would have.",
				effects = { health = 5, smarts = 2 },
			},
		},
	},
	{
		id = "adult_night_class",
		minAge = 20,
		maxAge = 60,
		delivery = "Direct",
		prompt = "There's a course you keep reading about. It runs on Tuesday evenings and you are, technically, free on Tuesday evenings.",
		choices = {
			{
				id = "enroll",
				label = "Enroll",
				outcome = "You were the least experienced person in the room for about a month, and then you weren't.",
				effects = { smarts = 7, happiness = 3, health = -1 },
			},
			{
				id = "teach_self",
				label = "Try to teach yourself instead",
				outcome = "You got further than you expected and stalled at exactly the point a teacher would have helped.",
				effects = { smarts = 4, happiness = -1 },
			},
			{
				id = "next_year",
				label = "Say you'll do it next year",
				outcome = "You said that for six years running. You did eventually do it, and wished you'd started at the beginning.",
				effects = { happiness = -3, smarts = 1 },
			},
		},
	},
	{
		id = "adult_old_number",
		minAge = 25,
		maxAge = 70,
		delivery = "NPCApproach",
		cast = "friend",
		prompt = "Someone you haven't seen in years is standing on the doorstep. You almost don't recognise them, and then you do.",
		choices = {
			{
				id = "answer",
				label = "Answer it",
				outcome = "Two hours. You picked up somewhere in the middle of a conversation you'd left unfinished a decade earlier.",
				effects = { happiness = 7, smarts = 1 },
			},
			{
				id = "call_back",
				label = "Let it ring and call back tomorrow",
				outcome = "You called the next day, and the day after, and left it at that. You did meet up in the end, six months later.",
				effects = { happiness = 3 },
			},
			{
				id = "ignore",
				label = "Leave it",
				outcome = "You never called back. You thought about it every so often for years, usually late at night.",
				effects = { happiness = -5, smarts = 2 },
			},
		},
	},
	{
		id = "adult_check_up",
		minAge = 40,
		maxAge = 75,
		delivery = "Direct",
		prompt = "There's a letter about a routine appointment you've been putting off. It's been on the side for three weeks.",
		choices = {
			{
				id = "go",
				label = "Go",
				outcome = "An hour of your life, mostly waiting. They found something small and early, and small and early is the whole game.",
				effects = { health = 8, happiness = -1 },
			},
			{
				id = "reschedule",
				label = "Reschedule it for a better week",
				outcome = "You rescheduled it twice and went in the end. It was fine, and you'd spent four months not knowing that.",
				effects = { health = 3, happiness = -2 },
			},
			{
				id = "throw_out",
				label = "Throw it out, you feel fine",
				outcome = "You threw it out. You did feel fine, right up until the point that stopped being the relevant question.",
				effects = { health = -6, happiness = 2 },
			},
		},
	},
	{
		id = "elder_early_walk",
		minAge = 65,
		maxAge = 999,
		delivery = "Direct",
		prompt = "You're awake before everyone else again. The light outside is doing something worth looking at.",
		choices = {
			{
				id = "walk",
				label = "Get up and go out into it",
				outcome = "The same route, most mornings, for years. You knew every dog on it by name and half the owners by sight.",
				effects = { health = 5, happiness = 5 },
			},
			{
				id = "window",
				label = "Watch it from the window with something hot",
				outcome = "You sat with it until the street filled up. There are worse ways to start a day and you'd tried most of them.",
				effects = { happiness = 4, health = 1 },
			},
			{
				id = "back_to_sleep",
				label = "Go back to sleep",
				outcome = "You slept another two hours and missed it entirely. You'd earned it, and there would be other mornings.",
				effects = { health = 2, happiness = -1 },
			},
		},
	},

	-- Being unwell, grown up: the first illness with a job and a reason to go in
	-- anyway. The doctor is a third answer only when money allows -- a price is a
	-- gate, and a broke life has to make do with resting or pushing through.
	{
		id = "adult_caught_something",
		minAge = 18,
		maxAge = 75,
		delivery = "Direct",
		forbids = { "sick" },
		weight = 0.5,
		prompt = "You're coming down with something, and you can't decide whether it's worth being sensible about. There's stuff that needs doing.",
		choices = {
			{
				id = "take_the_day",
				label = "Take the day off",
				outcome = "You stayed in and slept it off. The stuff waited, the way it always does, and you got back a day you'd have lost anyway.",
				effects = { health = 4, happiness = -1 },
				sets = { "sick" },
			},
			{
				id = "power_through",
				label = "Power through it",
				outcome = "You did everything anyway, badly, with a hot face. It cost you more than it was worth, but you've never liked letting a day beat you.",
				effects = { happiness = 2, health = -3 },
				sets = { "sick" },
			},
			{
				id = "see_a_doctor",
				label = "See a doctor",
				outcome = "You sat in a waiting room for an hour and a half and left with a prescription and a bill. You didn't feel clever. You did feel looked at.",
				cost = 120,
				effects = { health = 6, happiness = 1 },
				sets = { "sick" },
			},
		},
	},
}

return Adult
