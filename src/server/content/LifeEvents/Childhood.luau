--!strict
-- Ages 0-5. These are the years with no Age Up button on a first life, so they
-- carry the most weight per entry: without them childhood is a progress bar.
--
-- Delivery is "Memory" for all of them. A toddler has no world to walk around,
-- so these are framed as first-person recollections rather than things you go
-- and find. Adding an entry needs no code — copy the shape below.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LifeEvent = Types.LifeEvent

local Childhood: { LifeEvent } = {
	{
		id = "childhood_first_word",
		minAge = 0,
		maxAge = 1,
		delivery = "Memory",
		prompt = "Sound is a game. Every noise you make, the big faces lean in and wait.",
		choices = {
			{
				id = "their_word",
				label = "Say the word they keep repeating at you",
				outcome = "You said it back. The room went up like you had won something.",
				effects = { smarts = 4, happiness = 3 },
			},
			{
				id = "own_word",
				label = "Say a different word entirely",
				outcome = "You said a word nobody had taught you. They laughed for a full minute and you have been chasing that sound ever since.",
				effects = { happiness = 5, smarts = 1 },
			},
			{
				id = "listen",
				label = "Say nothing and watch their mouths",
				outcome = "You stayed quiet for another month. Then you came out with a whole sentence.",
				effects = { smarts = 6, happiness = -1 },
			},
		},
	},
	{
		id = "childhood_across_the_rug",
		minAge = 0,
		maxAge = 1,
		delivery = "Memory",
		prompt = "There is something bright on the far side of the rug. The rug has never seemed so wide.",
		choices = {
			{
				id = "crawl",
				label = "Go and get it yourself",
				outcome = "You made it. The rug burn on your knees was worth it.",
				effects = { health = 4, happiness = 2 },
			},
			{
				id = "cry",
				label = "Cry until somebody brings it",
				outcome = "It arrived in under ten seconds. You filed that information away carefully.",
				effects = { happiness = 3, smarts = 2, health = -1 },
			},
			{
				id = "hand",
				label = "Lose interest and study your own hand",
				outcome = "Your hand turned out to be far more interesting. You watched it open and close until you fell asleep.",
				effects = { smarts = 5 },
			},
		},
	},
	{
		id = "childhood_first_steps",
		minAge = 1,
		maxAge = 2,
		delivery = "Memory",
		prompt = "You are upright, holding the edge of the couch. Someone is crouched a few feet away with their arms out.",
		choices = {
			{
				id = "let_go",
				label = "Let go",
				outcome = "Three steps, then the floor. You got up and did it again before anyone could reach you.",
				effects = { health = 5, happiness = 4 },
			},
			{
				id = "hold_on",
				label = "Keep hold of the couch and edge along it",
				outcome = "You walked the entire length of the couch without letting go once. Slower, but you never fell.",
				effects = { smarts = 4, health = 1 },
			},
			{
				id = "sit_down",
				label = "Sit down heavily and laugh about it",
				outcome = "You sat down hard and found the whole situation hilarious. So did everyone else.",
				effects = { happiness = 5, health = -1 },
			},
		},
	},
	{
		id = "childhood_naming_things",
		minAge = 1,
		maxAge = 3,
		delivery = "Memory",
		prompt = "You have discovered that everything has a name, and that adults will supply one for anything you point at.",
		choices = {
			{
				id = "point_everything",
				label = "Point at absolutely everything",
				outcome = "You spent an entire afternoon pointing. By evening you had thirty new words and one very tired adult.",
				effects = { smarts = 6, happiness = 2 },
			},
			{
				id = "one_thing",
				label = "Point at the same thing over and over",
				outcome = "It was the ceiling light. You made them say it forty times. You still remember the word.",
				effects = { smarts = 3, happiness = 4 },
			},
			{
				id = "make_up",
				label = "Make up your own names instead",
				outcome = "For a while the dog was called Bo and the moon was called Bo. Your family used your words for years afterward.",
				effects = { happiness = 6, smarts = 1 },
			},
		},
	},
	{
		id = "childhood_sandbox",
		minAge = 2,
		maxAge = 4,
		delivery = "Memory",
		prompt = "There is another child in the sandbox. They have a red shovel. You have no shovel.",
		choices = {
			{
				id = "ask",
				label = "Ask to share the shovel",
				outcome = "They handed it over without looking up. You dug together until it got dark. That was your first friend.",
				effects = { happiness = 6, smarts = 2 },
			},
			{
				id = "dig_hands",
				label = "Dig with your hands and out-build them",
				outcome = "No shovel, no problem. By the end you had a hole deep enough to sit in and they asked to join you.",
				effects = { health = 3, happiness = 3, smarts = 1 },
			},
			{
				id = "watch",
				label = "Sit at the edge and watch",
				outcome = "You watched the whole time and learned exactly how they built it. You tried it yourself the next day and it worked.",
				effects = { smarts = 5, happiness = -2 },
			},
		},
	},
	{
		id = "childhood_end_of_yard",
		minAge = 2,
		maxAge = 5,
		delivery = "Memory",
		prompt = "The yard has a gap in the hedge at the far end. You have never been through it.",
		choices = {
			{
				id = "go_through",
				label = "Go through the gap",
				outcome = "It was another yard, almost the same as yours, with a cat in it. You were found twenty minutes later, filthy and delighted.",
				effects = { happiness = 6, health = -2, smarts = 3 },
			},
			{
				id = "look_only",
				label = "Look through, but stay on your side",
				outcome = "You knelt at the gap for a long time, working out what was over there. You went through eventually. Just not that day.",
				effects = { smarts = 4, happiness = 1 },
			},
			{
				id = "tell",
				label = "Go and tell an adult about the gap",
				outcome = "They came and looked, and said you were right, and held your hand while you went through together.",
				effects = { happiness = 4, health = 2 },
			},
		},
	},
	{
		id = "childhood_storm",
		minAge = 2,
		maxAge = 5,
		delivery = "Memory",
		prompt = "The sky cracks open in the middle of the night. The window is loud and white.",
		choices = {
			{
				id = "go_to_them",
				label = "Go and find someone",
				outcome = "They made room without a word. You slept through the rest of it.",
				effects = { happiness = 5, health = 2 },
			},
			{
				id = "watch_it",
				label = "Kneel on the bed and watch it",
				outcome = "You counted the gaps between the light and the noise. You didn't know why yet, but you knew it meant something.",
				effects = { smarts = 6, happiness = -1 },
			},
			{
				id = "under_covers",
				label = "Hide under the covers until it stops",
				outcome = "You stayed under there until it passed. In the morning it was just a wet yard and you felt a bit silly.",
				effects = { happiness = -2, smarts = 2, health = 1 },
			},
		},
	},
	{
		id = "childhood_last_cookie",
		minAge = 3,
		maxAge = 5,
		delivery = "Memory",
		prompt = "There is one cookie left on the plate and two of you looking at it.",
		choices = {
			{
				id = "split",
				label = "Break it in half",
				outcome = "You broke it badly and gave away the bigger piece. Somebody noticed, and mentioned it for years.",
				effects = { happiness = 4, smarts = 2 },
			},
			{
				id = "take",
				label = "Take it",
				outcome = "You took it. It was a very good cookie and you have thought about it more than you'd like to admit.",
				effects = { happiness = 3, looks = -1, smarts = 1 },
			},
			{
				id = "give",
				label = "Let them have it",
				outcome = "You said you weren't hungry, which was a lie. They remembered, and shared theirs the next time.",
				effects = { happiness = 2, smarts = 3, health = -1 },
			},
		},
	},
	{
		id = "childhood_same_story",
		minAge = 3,
		maxAge = 5,
		delivery = "Memory",
		prompt = "It is bedtime and you are allowed to pick the story.",
		choices = {
			{
				id = "same_again",
				label = "The same one as last night",
				outcome = "The same one. Again. You knew every word and corrected them whenever they tried to skip a page.",
				effects = { happiness = 5, smarts = 2 },
			},
			{
				id = "longest",
				label = "The longest one on the shelf",
				outcome = "You picked it purely because it would take longest. You were asleep by the fourth page anyway.",
				effects = { smarts = 4, happiness = 2 },
			},
			{
				id = "make_one_up",
				label = "Ask them to make one up",
				outcome = "They invented one on the spot about a dog that could drive. It was terrible. You asked for it every night for a month.",
				effects = { happiness = 6, smarts = 3 },
			},
		},
	},
	{
		id = "childhood_first_morning",
		minAge = 4,
		maxAge = 5,
		delivery = "Memory",
		prompt = "First morning somewhere new, with a room full of children you have never met. Somebody lets go of your hand.",
		choices = {
			{
				id = "join_in",
				label = "Walk straight into the middle of it",
				outcome = "You were building something with three other children inside a minute. You forgot to say goodbye.",
				effects = { happiness = 6, smarts = 1 },
			},
			{
				id = "corner",
				label = "Find a corner and wait it out",
				outcome = "You sat by the window for most of the morning. By the afternoon someone had come to you, which was easier anyway.",
				effects = { smarts = 4, happiness = -1 },
			},
			{
				id = "cry",
				label = "Cry",
				outcome = "You cried until you ran out, and then you were fine. Nobody held it against you.",
				effects = { happiness = -3, health = 1, smarts = 2 },
			},
		},
	},
}

return Childhood
