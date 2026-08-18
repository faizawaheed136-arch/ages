--!strict
-- Career branching events. A life that has worked the shop floor once, or the
-- office stairs, or the trades, carries a flag from that first time — and these
-- events use it to ask whether the life goes deeper or wider.
--
-- They are not promotions. Promotions are numbers in a record. These are the
-- moments where a life decides what kind of work it is, and the decision writes
-- a new flag that only some future events will read.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LifeEvent = Types.LifeEvent

local CareerBranch: { LifeEvent } = {
	-- The shop floor taught you the building. Now someone upstairs is asking
	-- whether you would like to learn the other half, which is a different world
	-- in the same walls and the same commute.
	{
		id = "career_shop_to_office",
		minAge = 22,
		maxAge = 55,
		delivery = "Direct",
		requires = { "career_shop" },
		forbids = { "career_office" },
		weight = 0.3,
		prompt = "Your manager's manager has seen you around. They ask whether you would like to shadow the office team for a week, which is a question nobody asks twice and you are not sure how to answer.",
		writesBack = { "stat:happiness", "stat:smarts", "flag:career_office" },
		choices = {
			{
				id = "shadow_yes",
				label = "Take the week",
				outcome = "You sat in meetings that moved at the speed of paper and learned the names of people you had passed in the corridor for a year. It was quieter and stranger than the shop and you wanted to stay.",
				effects = { smarts = 5, happiness = 2 },
				sets = { "career_office" },
			},
			{
				id = "shadow_no",
				label = "Say you're happier on the floor",
				outcome = "You said it plainly and your manager nodded the way people nod when they have heard that answer before. The stairs stayed where they were.",
				effects = { happiness = 1, smarts = 1 },
			},
			{
				id = "shadow_sometimes",
				label = "Ask to do it part-time",
				outcome = "They said yes and you split your week between the two worlds. Neither one trusted you completely, which is the price of being good at more than one thing.",
				effects = { smarts = 4, happiness = -1 },
				sets = { "career_office" },
			},
		},
	},

	-- The office had its logic. You learned it, and now you are tired of it, and
	-- there is a trade that needs somebody who can read the paperwork as well as
	-- they can hold a tool.
	{
		id = "career_office_to_trades",
		minAge = 25,
		maxAge = 50,
		delivery = "Direct",
		requires = { "career_office" },
		forbids = { "career_trades" },
		weight = 0.3,
		prompt = "A former colleague from the warehouse is buying a van and asking whether you want in. It is not a promotion and it pays worse at first, which is what makes the question feel real.",
		writesBack = { "stat:happiness", "stat:health", "flag:career_trades" },
		choices = {
			{
				id = "join_them",
				label = "Take the van",
				outcome = "Your hands learned a new alphabet. The paper you used to move with a pen you now moved with your arms, and it felt like leaving something and arriving somewhere at the same time.",
				effects = { health = 3, happiness = 2, smarts = -1 },
				sets = { "career_trades" },
			},
			{
				id = "not_yet",
				label = "Say you need more time",
				outcome = "You meant it, and they understood, and they did not ask again for two years. By then it did not matter, because you had stopped wanting to.",
				effects = { happiness = -2, smarts = 1 },
			},
			{
				id = "consult",
				label = "Ask for a trial day first",
				outcome = "You spent eight hours in boots and got home with your back a different shape. You went back the next week, and the week after that, and the van was yours by the end of the month.",
				effects = { health = 2, happiness = 1, smarts = 1 },
				sets = { "career_trades" },
			},
		},
	},

	-- The bakery taught you patience. Now someone wants to put you in the front
	-- where people see you, which is a different kind of work and the same kind
	-- of early morning.
	{
		id = "career_bakery_front",
		minAge = 20,
		maxAge = 60,
		delivery = "Direct",
		requires = { "career_bakery" },
		weight = 0.2,
		prompt = "The owner has asked whether you would like to run the shop front on weekends. It means more customers and less flour, and a tip jar you do not have to share with anyone.",
		writesBack = { "stat:happiness", "stat:looks", "stat:smarts" },
		choices = {
			{
				id = "front_yes",
				label = "Take the front",
				outcome = "You learned the faces. Regulars became names, names became conversations, and the shop felt like a room you knew instead of a building you worked in.",
				effects = { looks = 2, happiness = 3, smarts = 1 },
			},
			{
				id = "back_yes",
				label = "Stay in the back and bake more",
				outcome = "You stayed where the heat was, and the bread got better, and the people who came in never knew how much of it had been your hands. That was fine.",
				effects = { smarts = 2, happiness = 1 },
			},
			{
				id = "neither",
				label = "Ask for weekday mornings instead",
				outcome = "They said yes and you traded the weekend crowd for the dawn, which was quieter and colder and exactly what you wanted.",
				effects = { health = 2, happiness = 2 },
			},
		},
	},

	-- You have been in the trades long enough to know which tools matter and which
	-- ones are just there. Now someone is asking whether you can run a crew, which
	-- is the difference between doing the work and deciding who does it.
	{
		id = "career_trades_lead",
		minAge = 25,
		maxAge = 60,
		delivery = "Direct",
		requires = { "career_trades" },
		forbids = { "career_office", "career_retired" },
		weight = 0.2,
		prompt = "The foreman has a bad knee and the company needs someone who can read the plans and tell the new people where to stand. It is not a promotion in title but it is one in practice.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "lead_take",
				label = "Take it",
				outcome = "You stood in different places now and talked to more people, and the work felt smaller and larger at the same time. The people listening to you had the same eyes you had had.",
				effects = { smarts = 4, happiness = 1, health = -1 },
			},
			{
				id = "lead_refuse",
				label = "Stay on the tools",
				outcome = "You said you were fine where you were, and the foreman believed you. The tools were heavy and the work was honest and you went home tired in a way that felt earned.",
				effects = { health = 2, happiness = 2 },
			},
			{
				id = "lead_split",
				label = "Take it part-time, keep your crew",
				outcome = "You split yourself between the plans and the ground, and some days you were good at neither. Both days were yours, which was the point and also the cost.",
				effects = { smarts = 2, happiness = -1, health = -1 },
			},
		},
	},

	-- Deliberate retirement. Not the kind that comes from a body that has had enough
	-- but the kind a life chooses while it still can, which is the difference between
	-- a number on a page and a sentence. Fires once the life has held any job for long
	-- enough to have something to leave.
	{
		id = "career_retire_deliberate",
		minAge = 55,
		maxAge = 999,
		delivery = "Direct",
		requires = { "career_shop" },
		forbids = { "career_retired" },
		weight = 0.2,
		prompt = "You are tired of the thing you have been doing, and it has been a long thing. The question is not whether you can keep going — you can — but whether you want to, and that is a harder question than the first one.",
		writesBack = { "flag:career_retired", "stat:happiness", "stat:health" },
		choices = {
			{
				id = "leave_now",
				label = "Leave while you still can",
				outcome = "You walked out on a Tuesday and did not come back. The first month was the hardest and the second was the strangest, and by the third you had made a life that did not include the thing you had done for thirty years.",
				effects = { health = 3, happiness = 4 },
				sets = { "career_retired" },
			},
			{
				id = "wind_down",
				label = "Scale back instead",
				outcome = "You moved to half-days and then quarter-days, and the people who depended on you found someone else. It was kinder than a door closing and slower than you expected.",
				effects = { health = 2, happiness = 2, smarts = 1 },
				sets = { "career_retired" },
			},
			{
				id = "stay",
				label = "Stay and do it until you cannot",
				outcome = "You stayed, and the years kept coming, and one of them arrived when you could not climb the stairs anymore. You had known this might happen and you had chosen it anyway.",
				effects = { health = -2, happiness = -1 },
			},
		},
	},
}

return CareerBranch
