--!strict
-- The park beside the garage. A place that changes meaning across a life:
-- a field of grass and plastic seats for a child, a somewhere-to-be for a teen,
-- a place to clear your head as an adult, and a bench you know by name in old
-- age. Events here are tagged with "park" so the context picker prefers them
-- when the player is at the park and lets them fire elsewhere when nothing
-- better matches the room.
--
-- The west gang (The Old Line) has its boss at the park, so a small number of
-- events thread through gang territory without turning the place into a gang
-- map. The park is not a gang place first and foremost; it is a park that
-- somebody happens to preside over.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LifeEvent = Types.LifeEvent

local Park: { LifeEvent } = {
	-- The first time the park is not just somewhere you pass but somewhere you
	-- stop. The swings are the obvious object and the right one: they make you
	-- go higher if you want to, which is the whole lesson.
	{
		id = "park_first_swings",
		minAge = 5,
		maxAge = 8,
		delivery = "Direct",
		writesBack = { "stat:happiness", "flag:park_first_swings", "flag:park_regular" },
		choices = {
			{
				id = "swing_high",
				label = "Go as high as you can",
				outcome = "You pumped your legs until the sky was the whole world and then you were back in it. Your mum called you away and you did not want to go.",
				effects = { happiness = 4 },
			},
			{
				id = "swing_gentle",
				label = "Swing slowly and watch the dogs",
				outcome = "You went nice and easy and watched every dog that walked past with its person. One of them looked at you the way dogs do when they know something.",
				effects = { happiness = 2, smarts = 1 },
			},
			{
				id = "slide_first",
				label = "Use the slide instead",
				outcome = "The slide was faster than the swings and less exhausting. You did it seven times and then your legs gave out.",
				effects = { happiness = 3 },
			},
		},
	},

	-- A child who has been told to stay on the path finds the gap in the hedge.
	-- The park is where this happens because the hedge borders it and the gap
	-- is the same gap the west gang uses to come and go.
	{
		id = "park_hedge_gap",
		minAge = 7,
		maxAge = 11,
		delivery = "Direct",
		forbids = { "park_regular" },
		writesBack = { "stat:happiness", "stat:smarts", "flag:park_first_swings" },
		choices = {
			{
				id = "squeeze_through",
				label = "Squeeze through the gap",
				outcome = "You made it. The grass on the other side was taller and the air felt different, like you were somewhere else even though it was the same park.",
				effects = { happiness = 3, smarts = 2 },
			},
			{
				id = "peer_through",
				label = "Look through but stay on the path",
				outcome = "You could see the old bench on the far side, the one with the crack in it. You decided you would sit there one day.",
				effects = { smarts = 1, happiness = 1 },
			},
			{
				id = "walk_away",
				label = "Walk away and tell nobody",
				outcome = "You walked home and never went back that way. The gap stayed there, waiting.",
				effects = { happiness = -1 },
			},
		},
	},

	-- A birthday at the park is the easy celebration: no hall to book, no cake
	-- to bake, just running until you are tired and then sitting down somewhere
	-- and eating what you brought. The cost is the cake.
	{
		id = "park_birthday",
		minAge = 6,
		maxAge = 10,
		delivery = "Direct",
		writesBack = { "stat:happiness", "stat:looks" },
		choices = {
			{
				id = "have_it",
				label = "Have a birthday at the park",
				outcome = "You ran until you could not run anymore and then you ate cake on the grass. It was the best birthday and you did not know why.",
				cost = 30,
				effects = { happiness = 6, looks = 1 },
			},
			{
				id = "invite_friends",
				label = "Invite two friends to come with you",
				outcome = "You brought someone and they brought someone, and the park was suddenly full of people who knew your name. It was more than you expected.",
				cost = 50,
				effects = { happiness = 7, smarts = 1 },
			},
			{
				id = "stay_home",
				label = "Stay home and have a small one",
				outcome = "You had cake at the kitchen table and went to bed early. It was fine. You were fine.",
				effects = { happiness = 2 },
			},
		},
	},

	-- Teen park hang. The park is the only public place where a teen can be
	-- without an adult telling them what to do, which is why it matters.
	{
		id = "park_after_school",
		minAge = 13,
		maxAge = 17,
		delivery = "Direct",
		requires = { "park_first_swings" },
		repeatable = true,
		weight = 0.7,
		tags = { "park" },
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "hang_out",
				label = "Just hang out and talk",
				outcome = "You sat on the bench and talked about nothing for an hour. It was the best part of the day.",
				effects = { happiness = 4, smarts = 1 },
			},
			{
				id = "exercise",
				label = "Do some proper exercise",
				outcome = "You ran the loop around the park three times and then did some stretches you saw online. Your legs hurt for two days.",
				effects = { health = 3, happiness = 1 },
			},
			{
				id = "avoid_home",
				label = "Stay until it is dark",
				outcome = "You stayed until the lights came on and then walked home. Your parents asked where you had been and you did not quite know how to answer.",
				effects = { happiness = -2, smarts = 2, health = 1 },
			},
		},
	},

	-- A teen at the park with someone they like. The bench is the object.
	{
		id = "park_first_kiss",
		minAge = 14,
		maxAge = 17,
		delivery = "Direct",
		requires = { "park_regular" },
		writesBack = { "stat:happiness", "stat:looks", "stat:smarts" },
		choices = {
			{
				id = "kiss",
				label = "Kiss them on the bench",
				outcome = "It was nothing like the movies and exactly better. You walked home feeling like you had learned something true.",
				effects = { happiness = 5, looks = 1 },
			},
			{
				id = "hold_hand",
				label = "Just hold their hand",
				outcome = "You held hands the whole way around the path and neither of you said anything about it. It was enough.",
				effects = { happiness = 4, smarts = 1 },
			},
			{
				id = "walk_away",
				label = "Walk them to the gate and say goodnight",
				outcome = "You walked them to the gate and stood there until they went inside. You went home and thought about it all evening.",
				effects = { happiness = 3, smarts = 2 },
			},
		},
	},

	-- The west gang is at the park. This event is about what you do when you
	-- notice them, not about joining them -- that is GangService's job. This
	-- is about the moment of choice: stay and risk it, or leave and pretend
	-- you did not see anything.
	{
		id = "park_gang_sight",
		minAge = 14,
		maxAge = 18,
		delivery = "Direct",
		tags = { "park" },
		writesBack = { "stat:happiness", "stat:smarts", "flag:park_gang_untouched" },
		choices = {
			{
				id = "keep_head_down",
				label = "Keep walking and look nowhere",
				outcome = "You walked past them with your eyes on the ground and they did not look up. Your heart was in your throat the whole way.",
				effects = { happiness = -2, smarts = 2 },
			},
			{
				id = "sit_away",
				label = "Sit on the far bench and wait",
				outcome = "You sat as far away as you could and waited until they left. They did not notice you at all, which was the point.",
				effects = { happiness = 1, smarts = 1 },
			},
			{
				id = "leave_immediately",
				label = "Turn around and go home",
				outcome = "You turned and walked home fast. You did not know what you had seen, but you knew you did not want to see it again.",
				effects = { happiness = -3, smarts = 3, health = 1 },
			},
		},
	},

	-- A teen who has been coming to the park long enough to know the regulars.
	-- One of them notices you and speaks first.
	{
		id = "park_teen_talk",
		minAge = 15,
		maxAge = 17,
		delivery = "NPCApproach",
		cast = "neighbor",
		requires = { "park_regular" },
		repeatable = true,
		weight = 0.5,
		tags = { "park" },
		writesBack = { "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "talk",
				label = "Talk to them",
				outcome = "They asked what you were doing there and you told them. They nodded like it made sense, which it sort of did.",
				effects = { happiness = 3, smarts = 1 },
			},
			{
				id = "nod",
				label = "Nod and keep to yourself",
				outcome = "You nodded and they nodded back. It was enough. You see each other at the park now and again and that is the relationship.",
				effects = { happiness = 1 },
			},
			{
				id = "walk_on",
				label = "Keep walking",
				outcome = "You kept walking and they called after you something you did not catch. You pretended you had not heard.",
				effects = { happiness = -2, smarts = 1 },
			},
		},
	},

	-- An adult who uses the park the way some people use a bar: to think.
	-- The bench is theirs now, or at least the one near the old tree.
	{
		id = "park_adult_bench",
		minAge = 22,
		maxAge = 55,
		delivery = "Direct",
		requires = { "park_regular" },
		repeatable = true,
		weight = 0.6,
		tags = { "park" },
		writesBack = { "stat:happiness", "stat:smarts", "stat:health" },
		choices = {
			{
				id = "sit_think",
				label = "Sit and think about nothing",
				outcome = "You sat on your bench and watched the world go by. It was not productive and it was exactly what you needed.",
				effects = { happiness = 3, smarts = 2 },
			},
			{
				id = "walk_think",
				label = "Walk the loop and sort it out",
				outcome = "You walked the same loop you always walk and by the third time around you had the answer. It was always there; you just needed the space to find it.",
				effects = { health = 2, happiness = 2, smarts = 3 },
			},
			{
				id = "bring_food",
				label = "Bring something to eat and make a meal of it",
				outcome = "You brought bread and cheese and sat where the sun was. It was the best lunch you had in months.",
				effects = { happiness = 4, health = 1 },
			},
		},
	},

	-- An adult who has started a dog. The park is where the dog goes and where
	-- the person goes with it. It is a different kind of regular.
	{
		id = "park_dog_walk",
		minAge = 20,
		maxAge = 60,
		delivery = "Direct",
		forbids = { "park_regular" },
		writesBack = { "stat:happiness", "stat:health", "flag:park_regular" },
		choices = {
			{
				id = "walk_daily",
				label = "Walk the dog here every day",
				outcome = "You came here every day and the dog knew the path by heart. You started recognizing the other regulars and then you started saying hello.",
				effects = { health = 4, happiness = 3 },
			},
			{
				id = "walk_sometimes",
				label = "Come here when the dog needs it",
				outcome = "You came when you could. The dog loved it every time and you loved watching it love it. That was enough.",
				effects = { health = 2, happiness = 2 },
			},
			{
				id = "too_busy",
				label = "Walk the dog around the block instead",
				outcome = "The block is fine. The dog is fine. You are fine. It is just not the same.",
				effects = { health = 1, happiness = -1 },
			},
		},
	},

	-- A picnic. The park is the default venue because it is free and open and
	-- somewhere everybody can get to. The cost is the food.
	{
		id = "park_picnic",
		minAge = 22,
		maxAge = 55,
		delivery = "Direct",
		writesBack = { "stat:happiness", "stat:health", "flag:park_confession" },
		choices = {
			{
				id = "family_picnic",
				label = "Have a family picnic",
				outcome = "You spread the blanket and everyone came. The kids ran and the adults talked and the food went faster than it should have.",
				cost = 80,
				effects = { happiness = 6, health = 1 },
			},
			{
				id = "romantic_picnic",
				label = "Have a picnic with your person",
				outcome = "You brought a bottle and two glasses and sat where the light was good. It was not fancy and it was perfect.",
				cost = 60,
				effects = { happiness = 7, looks = 1 },
			},
			{
				id = "solo_picnic",
				label = "Bring a sandwich and sit alone",
				outcome = "You ate your sandwich on the bench and watched the world. It was the most peaceful hour you had all month.",
				cost = 10,
				effects = { happiness = 3, smarts = 1 },
			},
		},
	},

	-- The park as a place to have a conversation that matters. Not a crisis --
	-- just something that needs to be said and is too much for a kitchen table.
	{
		id = "park_confession",
		minAge = 25,
		maxAge = 55,
		delivery = "NPCApproach",
		cast = "friend",
		requires = { "park_regular" },
		writesBack = { "stat:happiness", "stat:smarts", "flag:park_confession" },
		choices = {
			{
				id = "listen",
				label = "Listen without interrupting",
				outcome = "They talked and you let them. When they were done, you said what you needed to say and it landed. Not perfectly, but landed.",
				effects = { happiness = 4, smarts = 3 },
			},
			{
				id = "share_first",
				label = "Share your own trouble first",
				outcome = "You went first and that made it easier for them to go. You both left lighter than you arrived.",
				effects = { happiness = 5, smarts = 2 },
			},
			{
				id = "change_subject",
				label = "Talk about something else",
				outcome = "You talked about the weather and the football and nothing at all. It was enough. Some things do not need to be said.",
				effects = { happiness = 1 },
			},
		},
	},

	-- An adult who is not okay and comes to the park because it is the one
	-- place they can go without having to be anyone. This is the heavy one.
	{
		id = "park_bad_day",
		minAge = 20,
		maxAge = 55,
		delivery = "Direct",
		tags = { "park" },
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "sit_it_out",
				label = "Sit on the bench until it passes",
				outcome = "You sat until the sun went down and the bad day became a bad afternoon and then just a bad day. It would have been worse inside.",
				effects = { happiness = 2, health = 1 },
			},
			{
				id = "walk_it_off",
				label = "Walk until you are too tired to think",
				outcome = "You walked until your legs hurt and your mind went quiet. You walked home in a different head than the one you arrived in.",
				effects = { health = 3, happiness = 1, smarts = 1 },
			},
			{
				id = "go_home",
				label = "Go home and face it",
				outcome = "You turned around and went home. The day was still bad but it was your bad day and you were in your own house.",
				effects = { happiness = -1, smarts = 2 },
			},
		},
	},

	-- An older adult who has been coming to this park for decades. The bench
	-- is the same one they sat on as a child, if the park is the same park.
	{
		id = "park_older_days",
		minAge = 60,
		maxAge = 90,
		delivery = "Direct",
		requires = { "park_regular" },
		repeatable = true,
		weight = 0.5,
		tags = { "park" },
		writesBack = { "stat:happiness", "stat:smarts", "stat:health" },
		choices = {
			{
				id = "remember",
				label = "Sit and remember",
				outcome = "You sat on the bench and remembered every version of yourself that had sat on this bench. The one on the far side with the crack in it was still there.",
				effects = { happiness = 4, smarts = 2, health = 1 },
			},
			{
				id = "watch_young",
				label = "Watch the young ones play",
				outcome = "You watched a kid go down the slide and you smiled because you remembered what that felt like. It felt the same, somehow.",
				effects = { happiness = 5 },
			},
			{
				id = "doze",
				label = "Doze in the sun",
				outcome = "You dozed with your glasses on your belly and a dog came and lay down next to you. You did not move until it did.",
				effects = { health = 2, happiness = 2 },
			},
		},
	},

	-- An elder who feeds the ducks. Not everyone has ducks, but if the park
	-- has them and you are old enough to have time, this is what you do.
	{
		id = "park_ducks",
		minAge = 65,
		maxAge = 999,
		delivery = "Direct",
		repeatable = true,
		weight = 0.4,
		tags = { "park" },
		writesBack = { "stat:happiness", "stat:health" },
		choices = {
			{
				id = "feed_them",
				label = "Feed the ducks",
				outcome = "They came rushing like they had been starving and then they were gone again. You threw the rest and watched them circle.",
				effects = { happiness = 3, health = 1 },
			},
			{
				id = "watch_them",
				label = "Just watch them",
				outcome = "You sat and watched the ducks do what ducks do. It was peaceful and nothing more was needed.",
				effects = { happiness = 2 },
			},
			{
				id = "skip_today",
				label = "Skip the ducks today",
				outcome = "You walked past the water and kept going. The ducks would be there tomorrow.",
				effects = { happiness = -1 },
			},
		},
	},

	-- A repeatable ambient moment at the park. Not every visit needs a story;
	-- some are just visits. This fires when the player is at the park and
	-- nothing else more interesting is happening.
	{
		id = "park_quiet_moment",
		minAge = 16,
		maxAge = 80,
		delivery = "Direct",
		repeatable = true,
		weight = 0.3,
		tags = { "park" },
		writesBack = { "stat:happiness" },
		choices = {
			{
				id = "breathe",
				label = "Take a proper breath",
				outcome = "You stood where you were and breathed in and out three times. The air was better here than anywhere else.",
				effects = { happiness = 2 },
			},
			{
				id = "people_watch",
				label = "Watch people go by",
				outcome = "You watched the stream of people and made up stories about them. The one with the red bag was going to propose. The old man was going home to his cat.",
				effects = { happiness = 1, smarts = 1 },
			},
			{
				id = "check_phone",
				label = "Check your phone and keep walking",
				outcome = "You checked everything and nothing mattered. You put the phone away and kept walking.",
				effects = { happiness = -1 },
			},
		},
	},
}

return Park
