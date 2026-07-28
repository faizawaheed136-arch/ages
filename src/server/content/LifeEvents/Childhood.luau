--!strict
-- Ages 0-5. Answering one of these ends the year, so a life passes through
-- roughly one per year and the pool has to be deep enough that two lives in a
-- row don't look the same. The early ages are stocked hardest: a 0-1 band has
-- the fewest eligible entries and is therefore the first place repetition shows.
--
-- Delivery is "Memory" until the toddler world lands, at which point these
-- become world interactions and only the delivery field changes. The writing
-- already assumes a real place — a rug, a hedge, a plate — for that reason.
-- Adding an entry needs no code: copy the shape below.

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
		id = "childhood_mirror",
		minAge = 0,
		maxAge = 1,
		delivery = "Memory",
		prompt = "There is another baby in the shiny thing on the wall. They do everything you do, exactly when you do it.",
		choices = {
			{
				id = "test",
				label = "Move and see if they move",
				outcome = "You raised a hand. So did they. You worked at this for a long time and reached no conclusion you could have explained.",
				effects = { smarts = 5, happiness = 2 },
			},
			{
				id = "greet",
				label = "Shout at them",
				outcome = "You shouted. They shouted silently back. You decided you liked them and that was that.",
				effects = { happiness = 5, smarts = 1 },
			},
			{
				id = "behind",
				label = "Try to get behind the glass",
				outcome = "You went around the back and found nothing but wall. It was the first time the world had lied to you.",
				effects = { smarts = 6, happiness = -2 },
			},
		},
	},
	{
		id = "childhood_dropped_spoon",
		minAge = 0,
		maxAge = 1,
		delivery = "Memory",
		prompt = "From up here, things fall. You have a spoon, and someone keeps giving it back.",
		choices = {
			{
				id = "again",
				label = "Drop it again. And again.",
				outcome = "Fourteen times. You learned that objects fall and that adults return them, which is two laws of the universe in one afternoon.",
				effects = { smarts = 6, happiness = 3 },
			},
			{
				id = "watch",
				label = "Drop it once and watch where it goes",
				outcome = "You leaned out as far as the chair allowed and tracked it all the way down. Then you were satisfied.",
				effects = { smarts = 4, health = -1 },
			},
			{
				id = "keep",
				label = "Hold onto it",
				outcome = "You gripped it through the entire meal and would not be talked out of it. Nobody saw that spoon again until you were asleep.",
				effects = { happiness = 3, health = 2 },
			},
		},
	},
	{
		id = "childhood_handed_over",
		minAge = 0,
		maxAge = 2,
		delivery = "Memory",
		prompt = "A face you don't know is leaning in with their arms out, and the person holding you is already letting go.",
		choices = {
			{
				id = "go",
				label = "Go to them",
				outcome = "You went. They smelled wrong and sounded kind, and you were fine inside a minute.",
				effects = { happiness = 3, smarts = 2 },
			},
			{
				id = "object",
				label = "Object, loudly",
				outcome = "You were back in familiar arms within seconds and everyone apologized to you, which felt correct.",
				effects = { happiness = 2, smarts = 3, health = -1 },
			},
			{
				id = "stare",
				label = "Say nothing and stare at them",
				outcome = "You looked at them without blinking for the whole visit. They brought it up every time they saw you for years.",
				effects = { smarts = 5, looks = -1 },
			},
		},
	},
	{
		id = "childhood_the_word_no",
		minAge = 1,
		maxAge = 3,
		delivery = "Memory",
		prompt = "You have learned a word that stops adults where they stand. It has two letters.",
		choices = {
			{
				id = "everything",
				label = "Use it on everything",
				outcome = "You said it to food, baths, shoes and the sun. It worked about a third of the time, which was enough to keep going.",
				effects = { happiness = 4, smarts = 3 },
			},
			{
				id = "sparingly",
				label = "Save it for things you actually mean",
				outcome = "You used it rarely, and they listened when you did. You have negotiated that way ever since.",
				effects = { smarts = 6, happiness = 1 },
			},
			{
				id = "opposite",
				label = "Discover the other word instead",
				outcome = "You said yes to everything for a week and ended up at a swimming pool, a wedding, and somebody else's birthday party.",
				effects = { happiness = 5, health = 1, smarts = -1 },
			},
		},
	},
	{
		id = "childhood_stairs",
		minAge = 1,
		maxAge = 3,
		delivery = "Memory",
		prompt = "The stairs go up. You have watched everyone else use them and it looks straightforward enough.",
		choices = {
			{
				id = "climb",
				label = "Climb",
				outcome = "You made it four steps before anyone noticed, and the noise they made was far bigger than the situation warranted.",
				effects = { health = 3, happiness = 3, smarts = 1 },
			},
			{
				id = "backward",
				label = "Come down backward, like a ladder",
				outcome = "Somebody showed you once and you never did it any other way. It was slow, and you never fell.",
				effects = { smarts = 5, health = 2 },
			},
			{
				id = "hand",
				label = "Wait at the bottom for a hand",
				outcome = "You stood there with one arm up until somebody took it. It worked every single time, so you kept doing it.",
				effects = { happiness = 3, smarts = 2 },
			},
		},
	},
	{
		id = "childhood_one_toy",
		minAge = 1,
		maxAge = 4,
		delivery = "Memory",
		prompt = "There is one thing you will not be separated from. It is not the newest or the nicest and it is starting to smell.",
		choices = {
			{
				id = "everywhere",
				label = "Take it absolutely everywhere",
				outcome = "It came to the store, the doctor and both sets of grandparents. It lost an eye somewhere along the way and you loved it more.",
				effects = { happiness = 6, health = -1 },
			},
			{
				id = "hide",
				label = "Hide it so nobody can take it",
				outcome = "You hid it so well that you lost it for two days. Those were a bad two days for everyone in the house.",
				effects = { smarts = 3, happiness = -2 },
			},
			{
				id = "lend",
				label = "Let somebody else hold it",
				outcome = "You handed it over and watched them the entire time. Getting it back was the best part.",
				effects = { happiness = 4, smarts = 2 },
			},
		},
	},
	{
		id = "childhood_hiding",
		minAge = 2,
		maxAge = 4,
		delivery = "Memory",
		prompt = "Somebody is counting. You need somewhere they will never find you.",
		choices = {
			{
				id = "eyes",
				label = "Cover your eyes",
				outcome = "You stood in the middle of the room with both hands over your face and could not be found for a remarkably long time, because they were being kind.",
				effects = { happiness = 6, smarts = -1 },
			},
			{
				id = "curtain",
				label = "Behind the curtain, with your feet showing",
				outcome = "Your feet were in plain view. They walked past you three times announcing they had no idea where you could possibly be.",
				effects = { happiness = 5, smarts = 1 },
			},
			{
				id = "properly",
				label = "Find somewhere genuinely good",
				outcome = "You found a spot so good they stopped playing and started calling your name for real. You came out feeling powerful and a little guilty.",
				effects = { smarts = 5, happiness = 2 },
			},
		},
	},
	{
		id = "childhood_big_dog",
		minAge = 2,
		maxAge = 5,
		delivery = "Memory",
		prompt = "There is a dog. It is at least as tall as you are, and it has noticed you.",
		choices = {
			{
				id = "hand_out",
				label = "Put your hand out",
				outcome = "It shoved its whole head under your palm and nearly took you off your feet. You have liked dogs unconditionally ever since.",
				effects = { happiness = 6, health = 1 },
			},
			{
				id = "freeze",
				label = "Stand completely still",
				outcome = "You held still until it lost interest. You were proud of not running, which is a strange thing to be proud of at three.",
				effects = { smarts = 4, happiness = 1 },
			},
			{
				id = "behind",
				label = "Get behind an adult",
				outcome = "You watched it from behind somebody's leg. By the time you came out it was asleep, which was disappointing.",
				effects = { happiness = -1, smarts = 3 },
			},
		},
	},
	{
		id = "childhood_puddle",
		minAge = 2,
		maxAge = 5,
		delivery = "Memory",
		prompt = "A puddle covers the whole path, and you are wearing shoes that were clean this morning.",
		choices = {
			{
				id = "jump",
				label = "Jump in with both feet",
				outcome = "You went in flat-footed and soaked yourself to the waist. Worth it then, and you would do it now.",
				effects = { happiness = 6, health = -2 },
			},
			{
				id = "around",
				label = "Pick your way around the edge",
				outcome = "You got around it without a drop on you. You felt extremely sensible and slightly cheated.",
				effects = { smarts = 3, happiness = -1 },
			},
			{
				id = "test",
				label = "Put one foot in and find out how deep it is",
				outcome = "You tested it like an engineer, established the depth, and then jumped in anyway.",
				effects = { smarts = 4, happiness = 3, health = -1 },
			},
		},
	},
	{
		id = "childhood_broke_it",
		minAge = 3,
		maxAge = 5,
		delivery = "Memory",
		prompt = "It is in two pieces on the floor and nobody saw it happen.",
		choices = {
			{
				id = "own_up",
				label = "Go and tell them",
				outcome = "You told them immediately, in tears. They were considerably less angry than you had budgeted for.",
				effects = { smarts = 5, happiness = 2 },
			},
			{
				id = "repair",
				label = "Try to put it back together",
				outcome = "You balanced the two halves against each other and walked away quickly. It held for about an hour.",
				effects = { smarts = 3, happiness = -2 },
			},
			{
				id = "silence",
				label = "Say nothing",
				outcome = "You said nothing and waited. The waiting turned out to be the punishment.",
				effects = { happiness = -4, smarts = 4 },
			},
		},
	},
	{
		id = "childhood_helping",
		minAge = 3,
		maxAge = 5,
		delivery = "Memory",
		prompt = "An adult is doing something with tools, and you have decided that you are helping.",
		choices = {
			{
				id = "hold",
				label = "Hold things and pass them over",
				outcome = "You held the flashlight, mostly pointing at the wrong thing. They said you were essential and they meant it.",
				effects = { happiness = 5, smarts = 3 },
			},
			{
				id = "parallel",
				label = "Do your own version alongside them",
				outcome = "You worked on your own project next to theirs for an hour. Neither of you said a word and it was perfect.",
				effects = { smarts = 5, happiness = 3 },
			},
			{
				id = "names",
				label = "Ask what everything is called",
				outcome = "You asked forty questions and they answered every one. You still know what a washer is.",
				effects = { smarts = 6, happiness = 1 },
			},
		},
	},
	{
		id = "childhood_why",
		minAge = 3,
		maxAge = 5,
		delivery = "Memory",
		prompt = "You have found a question that works on absolutely anything, and it is one word long.",
		choices = {
			{
				id = "keep_going",
				label = "Keep asking until they run out",
				outcome = "You got to the bottom of it in about nine steps and they admitted they didn't know. That was the day adults got smaller.",
				effects = { smarts = 6, happiness = 1 },
			},
			{
				id = "self_answer",
				label = "Start answering it yourself",
				outcome = "You began supplying your own answers. They were confident, detailed, and almost entirely wrong.",
				effects = { happiness = 4, smarts = 2 },
			},
			{
				id = "read_the_room",
				label = "Stop when they get tired",
				outcome = "You heard the sigh and stopped. You were reading rooms before you could read words.",
				effects = { smarts = 5, happiness = -1 },
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
