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
		delivery = "NPCApproach",
		cast = "friend",
		prompt = "The training wheels are off. Someone is holding the back of the seat and promising not to let go.",
		choices = {
			{
				id = "pedal",
				label = "Pedal and don't look back",
				outcome = "They let go about four seconds in. You were halfway down the road before you realized, and you stayed up.",
				effects = { health = 5, happiness = 4 },
			},
			{
				id = "check",
				label = "Keep checking they're still there",
				outcome = "You looked back, saw nobody, and went straight into the bushes. You were riding properly by the weekend anyway.",
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
		delivery = "NPCApproach",
		cast = "friend",
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
				outcome = "You called across the cafeteria, which was mortifying for both of you, but they came over and stayed.",
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
		delivery = "NPCApproach",
		cast = "friend",
		prompt = "You didn't study. The person in front has left their paper at a very readable angle.",
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
				outcome = "You guessed, badly, and got a talking-to. You studied for the next one out of pure embarrassment.",
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
		delivery = "NPCApproach",
		cast = "friend",
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

	-- Everything below here only exists in some lives.
	--
	-- These are the first events whose reason for being offered is a decision the
	-- player made rather than a birthday they reached, and they are written so the
	-- earlier decision is legible without being narrated. Nobody is told "because you
	-- knelt down to that dog at three". They are simply the child who is not
	-- frightened of the thing in the doorway, and if the player remembers why then the
	-- game has done its job, and if they do not then it still has not lied to them.
	--
	-- Written in pairs on purpose. A branch that only pays out one way is a reward for
	-- having guessed right, and the premise here is that there was nothing to guess: a
	-- three-year-old backing away from an animal twice their size is not making a
	-- mistake.
	{
		id = "school_dog_again",
		minAge = 6,
		maxAge = 10,
		delivery = "Direct",
		requires = { "dog_loved" },
		prompt = "There's a dog tied up outside the shop, and it has started making a noise at you that you're fairly sure is friendly.",
		choices = {
			{
				id = "straight_in",
				label = "Go straight over",
				outcome = "You were on your knees in front of it before its owner got out of the shop. They said it never does that with kids. You knew it would.",
				effects = { happiness = 6, looks = 1 },
			},
			{
				id = "ask_first",
				label = "Wait and ask the owner first",
				outcome = "You waited, asked properly, and got a yes and an extra minute for asking. Somebody's parent said something approving about you within earshot.",
				effects = { smarts = 5, happiness = 3 },
			},
			{
				id = "walk_on",
				label = "Walk on past",
				outcome = "You were late and you walked on, and thought about it again that evening. It is a small thing to still remember.",
				effects = { happiness = -2, smarts = 2 },
			},
		},
	},
	{
		id = "school_dog_still",
		minAge = 6,
		maxAge = 10,
		delivery = "Direct",
		requires = { "dog_feared" },
		prompt = "There's a dog tied up outside the shop. The doorway is narrow and it is lying across most of it.",
		choices = {
			{
				id = "long_way",
				label = "Go round the long way",
				outcome = "You went round the block rather than past it. Nobody noticed and nobody would have minded, and you were furious with yourself the whole way.",
				effects = { happiness = -3, smarts = 3 },
			},
			{
				id = "edge_past",
				label = "Edge past it against the wall",
				outcome = "You got past with your back flat to the brick and your breath held. It did not even lift its head. That helped, slightly.",
				effects = { health = 1, smarts = 4, happiness = 1 },
			},
			{
				id = "hand_out_again",
				label = "Put your hand out, the way you were shown",
				outcome = "You put your hand out the way somebody had told you to, and it sniffed you and went back to sleep. It was not the cure. It was the first day it was survivable.",
				effects = { happiness = 5, health = 2 },
				-- The one place in the game where a flag is undone, and the reason
				-- `clears` exists on a choice at all. Being frightened of dogs is not a
				-- sentence handed down at three, and a system that could only ever add
				-- to what you are would be a system quietly claiming it is. The price is
				-- walking up to the thing you are afraid of, which is the correct price
				-- and the whole reason this is allowed to work.
				clears = { "dog_feared" },
			},
		},
	},
	{
		id = "school_the_gap",
		minAge = 6,
		maxAge = 11,
		delivery = "Direct",
		requires = { "wandered_off" },
		prompt = "You know a way out of the school field that the teachers don't. You found it the same way you found the hedge.",
		choices = {
			{
				id = "use_it",
				label = "Use it",
				outcome = "You were home forty minutes early and nobody ever asked how. You used it for two more years.",
				effects = { happiness = 5, smarts = 3, health = -1 },
			},
			{
				id = "show_someone",
				label = "Show someone else",
				outcome = "You showed one person, who showed four, and it was fenced off inside a fortnight. You were briefly the most important person in your year.",
				effects = { looks = 4, happiness = 3, smarts = -2 },
			},
			{
				id = "keep_it",
				label = "Keep it to yourself and never use it",
				outcome = "You kept it. Knowing the way out turned out to be worth more than going through it, which is a lesson that took decades to stop being useful.",
				effects = { smarts = 6, happiness = 1 },
			},
		},
	},
	{
		id = "school_the_window",
		minAge = 7,
		maxAge = 12,
		delivery = "Direct",
		requires = { "broke_it_owned_up" },
		prompt = "A window is broken and the whole class is being kept in until somebody says something. It was not you.",
		choices = {
			{
				id = "say_nothing",
				label = "Say nothing",
				outcome = "You said nothing, which was true and still somehow felt like lying. Everyone went home an hour late.",
				effects = { happiness = -3, smarts = 3 },
			},
			{
				id = "vouch",
				label = "Say you saw who it was",
				outcome = "You said it out loud in front of everybody. It was the right thing and it cost you two friendships, and you would do it again, which is the part that worries you.",
				effects = { smarts = 4, happiness = -2, looks = 2 },
			},
			{
				id = "take_it",
				label = "Say it was you",
				outcome = "You took it for somebody who never found out it was you. You have never told anyone and you are still slightly proud of it.",
				effects = { happiness = 4, smarts = 2, looks = -1 },
			},
		},
	},

	-- Being unwell. The birthday health loop (see LifeService) hands out sickness
	-- as a number; these are the times it is handed over by name, so the response
	-- to it is a choice instead of a notice. Forbids so an illness already begun
	-- can never be begun again by content -- the flag is the state, and there is
	-- nothing a second set would add. Weighted below an ordinary event on purpose:
	-- either answer commits the rest of the year.
	{
		id = "school_sick_day",
		minAge = 6,
		maxAge = 12,
		delivery = "Direct",
		forbids = { "sick" },
		weight = 0.5,
		prompt = "You wake up with a sore throat and a head full of cotton. It's a school morning, and you can feel in your bones that it isn't going to be one.",
		choices = {
			{
				id = "stay_in_bed",
				label = "Stay in bed",
				outcome = "You rolled over and slept until the house went quiet. You needed it, and the day was wasted in the one way that isn't.",
				effects = { health = 4, happiness = -2 },
				sets = { "sick" },
			},
			{
				id = "go_anyway_school",
				label = "Get up and go anyway",
				outcome = "You went in and sat through it like a bad dream. You don't remember a word of any lesson, but nobody can say you missed school.",
				effects = { smarts = 2, health = -2, happiness = -1 },
				sets = { "sick" },
			},
		},
	},

	-- Interact events: the player walks to something in the school and clicks the dots
	-- on it. Zero events in the whole game used this delivery before these four, and
	-- that is the gap these fill: school had a door and nothing inside, and these are
	-- the things inside.
	{
		id = "school_locker_note",
		minAge = 7,
		maxAge = 12,
		delivery = "Interact",
		prompt = "There's a note slipped through the grille of your locker. It's folded in the careful way people write things they don't want everyone to read.",
		choices = {
			{
				id = "read_alone",
				label = "Read it right there",
				outcome = "It was from someone who sat next to you and wanted to be your friend. You were too surprised to do anything about it until the next day.",
				effects = { happiness = 4, looks = 1 },
			},
			{
				id = "read_toilet",
				label = "Take it to the bathroom to read",
				outcome = "You read it alone and it made you smile for the rest of the afternoon. You kept it in your pocket for a week.",
				effects = { happiness = 3, smarts = 2 },
			},
			{
				id = "bin_it",
				label = "Put it in the bin without reading it",
				outcome = "You binned it, and it was only later you realised you'd never find out who wrote it. Sometimes you still wonder.",
				effects = { happiness = -2 },
			},
		},
	},
	{
		id = "school_water_fountain",
		minAge = 6,
		maxAge = 12,
		delivery = "Interact",
		prompt = "The water fountain is making that noise again -- half cough, half splutter -- but you haven't had a drink since break.",
		choices = {
			{
				id = "drink_anyway",
				label = "Drink anyway",
				outcome = "You drank. It tasted like cold metal and the pipes, and you were fine. You were thirsty and it worked.",
				effects = { health = 2, happiness = 1 },
			},
			{
				id = "wait_for_it",
				label = "Wait for the next person to try first",
				outcome = "A year six went first and it worked, so you went second. You learned something about patience and something about plumbing.",
				effects = { smarts = 3, happiness = 1 },
			},
			{
				id = "tap_it",
				label = "Tap the side of it firmly",
				outcome = "You hit it once, hard, and the water came out clean. Nobody saw. You used the same trick for three years.",
				effects = { smarts = 4, happiness = 2 },
			},
		},
	},
	{
		id = "school_notice_board",
		minAge = 7,
		maxAge = 12,
		delivery = "Interact",
		prompt = "There's a notice pinned to the board that's been there since last term. Somebody has drawn a moustache on the headmaster's photo.",
		choices = {
			{
				id = "add_to_it",
				label = "Add a pair of glasses",
				outcome = "You added the glasses and three people laughed at lunch. The photo came down the next day and you felt briefly responsible for something good.",
				effects = { happiness = 5, looks = 2, smarts = -1 },
			},
			{
				id = "take_photo",
				label = "Take a photo of it",
				outcome = "You took a photo and showed it to three people on the way home. It was the first thing that made you laugh all week.",
				effects = { happiness = 3 },
			},
			{
				id = "ignore_board",
				label = "Walk past it",
				outcome = "You walked past and forgot about it by lunch. The headmaster's photo looked exactly the same tomorrow.",
				effects = { smarts = 1 },
			},
		},
	},
	{
		id = "school_library_book",
		minAge = 7,
		maxAge = 12,
		delivery = "Interact",
		prompt = "There's a book on the library shelf with your name in it -- not written, but printed. It's about something you've never heard of and it's got a torn jacket.",
		choices = {
			{
				id = "borrow_it",
				label = "Borrow it",
				outcome = "You took it home and read it in two days. It was about a boy who built a radio, and you spent the next month trying to make one from parts in the kitchen drawer.",
				effects = { smarts = 6, happiness = 3 },
			},
			{
				id = "read_there",
				label = "Read the first chapter right there",
				outcome = "You sat on the floor and read until the librarian moved you on. You learned enough to want more but not enough to know what happened.",
				effects = { smarts = 4, happiness = 2 },
			},
			{
				id = "put_back",
				label = "Put it back on the shelf",
				outcome = "You put it back and walked out. The librarian reshelved it the next day and it sat there for another year.",
				effects = { happiness = -1 },
			},
		},
	},
}

return School
