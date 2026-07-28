--!strict
-- Ages 6-12. From here the player has an Age Up button, so these compete with
-- the option to simply move on — they need to be worth stopping for.
--
-- Delivery is "Direct" for now. When step 3 lands a world, most of these become
-- NPCApproach or Location events; only the delivery field changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LifeEvent = Types.LifeEvent

local School: { LifeEvent } = {
	{
		id = "school_two_wheels",
		minAge = 6,
		maxAge = 9,
		delivery = "Direct",
		prompt = "The stabilisers are off. Someone is holding the back of the saddle and promising not to let go.",
		choices = {
			{
				id = "pedal",
				label = "Pedal and don't look back",
				outcome = "They let go about four seconds in. You were halfway down the road before you realised, and you stayed up.",
				effects = { health = 5, happiness = 4 },
			},
			{
				id = "check",
				label = "Keep checking they're still there",
				outcome = "You looked back, saw nobody, and went straight into a hedge. You were riding properly by the weekend anyway.",
				effects = { health = -3, happiness = 2, smarts = 3 },
			},
			{
				id = "quit",
				label = "Say you'd rather do it another day",
				outcome = "You went inside. It sat there in the shed for a month before you wheeled it out on your own and taught yourself.",
				effects = { smarts = 4, happiness = -2 },
			},
		},
	},
	{
		id = "school_new_kid",
		minAge = 6,
		maxAge = 12,
		delivery = "Direct",
		prompt = "There's someone new in your class. At lunch they're sitting on their own at the end of a long table.",
		choices = {
			{
				id = "sit_with",
				label = "Go and sit with them",
				outcome = "You sat down and asked them something stupid about their lunch. They're still in your life, on and off, decades later.",
				effects = { happiness = 6, smarts = 1 },
			},
			{
				id = "invite",
				label = "Wave them over to your table",
				outcome = "You called across the hall, which was mortifying for both of you, but they came over and stayed.",
				effects = { happiness = 4, looks = 1 },
			},
			{
				id = "nothing",
				label = "Leave them to it",
				outcome = "You meant to say something all week and never did. They moved schools again in the spring.",
				effects = { happiness = -3, smarts = 2 },
			},
		},
	},
	{
		id = "school_test_answers",
		minAge = 8,
		maxAge = 12,
		delivery = "Direct",
		prompt = "You didn't revise. The person in front has left their paper at a very readable angle.",
		choices = {
			{
				id = "copy",
				label = "Read it",
				outcome = "You got a good mark for work you didn't do, and it sat badly all week. It turned out they'd got question four wrong too, identically.",
				effects = { smarts = -3, happiness = -2, looks = 1 },
			},
			{
				id = "guess",
				label = "Guess your way through it",
				outcome = "You guessed, badly, and got a talking-to. You revised for the next one out of pure embarrassment.",
				effects = { smarts = 4, happiness = -2 },
			},
			{
				id = "own_up",
				label = "Tell the teacher you weren't ready",
				outcome = "You said it quietly at the end. They let you take it again on Friday, and you didn't waste it.",
				effects = { smarts = 5, happiness = 2 },
			},
		},
	},
	{
		id = "school_play",
		minAge = 7,
		maxAge = 11,
		delivery = "Direct",
		prompt = "They're casting the school play. There's a lead, a tree, and a job doing the lights.",
		choices = {
			{
				id = "lead",
				label = "Go for the lead",
				outcome = "You got it, forgot two lines, and improvised something that got a bigger laugh than the real script.",
				effects = { looks = 4, happiness = 4, smarts = -1 },
			},
			{
				id = "tree",
				label = "Ask to be the tree",
				outcome = "You were an excellent tree. You had one line and you delivered it perfectly, and you enjoyed every second of not being looked at.",
				effects = { happiness = 3, smarts = 2 },
			},
			{
				id = "lights",
				label = "Take the lights",
				outcome = "You ran the whole board yourself. Nobody in the audience knew your name and the show didn't work without you.",
				effects = { smarts = 6, happiness = 2, looks = -1 },
			},
		},
	},
}

return School
