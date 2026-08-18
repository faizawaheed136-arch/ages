--!strict
-- Events the world brings to you: mail on the mat, a phone ringing in the hall,
-- someone at the door. Kept in their own file rather than mixed into the age
-- files because they share a constraint the others don't -- none of them can
-- fire below Ambient.MinAge, since a resolved event advances the year for a
-- child and these arrive on their own schedule rather than on a birthday.
--
-- They also read differently on purpose. A letter or a call has already happened
-- to you by the time you are reading it, so the prompt is what is in front of
-- you rather than a situation you are standing in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LifeEvent = Types.LifeEvent

local Ambient: { LifeEvent } = {
	-- Letters. Patient by design -- they sit on the mat until the year turns --
	-- so they suit the events where thinking about it is part of the point.
	{
		id = "letter_school_report",
		minAge = 8,
		maxAge = 12,
		delivery = "Letter",
		prompt = "Your school report came in the post. It is face down on the mat and nobody has opened it yet.",
		writesBack = { "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "open_it",
				label = "Open it yourself",
				outcome = "You read it standing in the hall. It was worse in two places and better in one than you'd braced for, and knowing was easier than not knowing.",
				effects = { smarts = 3, happiness = -1 },
			},
			{
				id = "hand_it_over",
				label = "Take it to your parents unopened",
				outcome = "You handed it over and watched their face while they read it. They were kinder about it than you would have been.",
				effects = { happiness = 3, smarts = 1 },
			},
			{
				id = "hide_it",
				label = "Put it under the stairs",
				outcome = "It stayed under the stairs for eleven days. The school called on the twelfth, and the conversation you'd been avoiding happened anyway, just worse.",
				effects = { happiness = -5, smarts = 2 },
			},
		},
	},
	{
		id = "letter_the_thin_envelope",
		minAge = 17,
		maxAge = 21,
		delivery = "Letter",
		prompt = "The envelope you've been waiting on is here. It's thin. You've heard what a thin one usually means.",
		writesBack = { "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "read_now",
				label = "Open it in the doorway",
				outcome = "You tore it open on the spot. It was a no. You sat on the step for a while and then went inside and started working out what else there was.",
				effects = { happiness = -6, smarts = 5 },
			},
			{
				id = "wait",
				label = "Put it in your pocket and open it later",
				outcome = "You carried it around all day like it might change. It didn't, but by the time you opened it you'd already half-decided what you'd do either way.",
				effects = { smarts = 3, happiness = -2 },
			},
		},
	},
	{
		id = "letter_from_someone_gone",
		minAge = 30,
		maxAge = 75,
		delivery = "Letter",
		prompt = "Handwriting you recognize, from someone you stopped speaking to a long time ago. You don't know yet whether it's an apology.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "reply",
				label = "Write back",
				outcome = "You wrote back the same evening, badly, three times, and sent the third. It didn't fix it. It did end it properly, which turned out to be the thing you actually needed.",
				effects = { happiness = 7, health = 2 },
			},
			{
				id = "read_only",
				label = "Read it and leave it at that",
				outcome = "You read it twice and put it in a drawer. Some things you keep without answering, and that was allowed.",
				effects = { happiness = 2, smarts = 2 },
			},
			{
				id = "bin_it",
				label = "Throw it away unopened",
				outcome = "You put it straight in the bin and felt fine about it for about six years.",
				effects = { happiness = -4, smarts = 1 },
			},
		},
	},

	-- Calls. These expire, so they carry the events where being there mattered.
	{
		id = "call_friend_at_midnight",
		minAge = 14,
		maxAge = 22,
		delivery = "PhoneCall",
		prompt = "It's late and the phone is ringing. It's your friend, and from the first word you can tell something has gone wrong.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "go_to_them",
				label = "Get dressed and go to them",
				outcome = "You walked twenty minutes in the cold and sat with them until it got light. Neither of you has ever really talked about it since, and neither of you has forgotten it.",
				effects = { happiness = 6, health = -2, smarts = 1 },
			},
			{
				id = "stay_on",
				label = "Stay on the line as long as it takes",
				outcome = "You stayed on until they were tired enough to sleep. Two hours, mostly quiet. It was enough.",
				effects = { happiness = 4, health = -1 },
			},
			{
				id = "tomorrow",
				label = "Tell them you'll call in the morning",
				outcome = "You did call in the morning, and they were fine, and it was never quite the same afterwards.",
				effects = { happiness = -4, health = 2 },
			},
		},
	},
	{
		id = "call_the_offer",
		minAge = 22,
		maxAge = 55,
		delivery = "PhoneCall",
		prompt = "They're offering you the job. More money, and a city you don't know anybody in. They want an answer on the phone.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "take_it",
				label = "Say yes",
				outcome = "You said yes before you could talk yourself out of it. The first year was lonely and the second one wasn't, and you'd do it again.",
				effects = { smarts = 6, happiness = -2, health = -1 },
			},
			{
				id = "decline",
				label = "Say no",
				outcome = "You turned it down and stayed where your people were. You thought about it now and then, without much regret.",
				effects = { happiness = 5, smarts = -2 },
			},
			{
				id = "negotiate",
				label = "Ask for more and risk it",
				outcome = "You asked. There was a long pause that took a year off your life, and then they agreed to most of it.",
				effects = { smarts = 5, happiness = 2, health = -2 },
			},
		},
	},
	{
		id = "call_from_the_hospital",
		minAge = 35,
		maxAge = 80,
		delivery = "PhoneCall",
		prompt = "It's the hospital. Someone you love is in, it isn't an emergency yet, and they're asking whether you want to come now or wait for news.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "go_now",
				label = "Go now",
				outcome = "You dropped everything and drove. You sat in a corridor for six hours for twenty minutes of being useful, and you have never once counted that as a bad trade.",
				effects = { happiness = 5, health = -3 },
			},
			{
				id = "wait_for_news",
				label = "Wait for news",
				outcome = "You waited by the phone and it was fine, and you were sensible, and it sat oddly with you for a long time after.",
				effects = { happiness = -3, health = 1, smarts = 1 },
			},
		},
	},

	-- Visitors. Someone walks in and says this to your face, so the choices are
	-- things you say back rather than things you decide in private.
	{
		id = "visit_come_out",
		minAge = 6,
		maxAge = 14,
		delivery = "NPCApproach",
		cast = "friend",
		prompt = "Rae is at the door, out of breath, asking if you can come out. You're supposed to be doing something else.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "go",
				label = "Go",
				outcome = "You went. You were back late and in trouble for it, and it was one of about four afternoons from that whole year you can still see clearly.",
				effects = { happiness = 7, smarts = -2, health = 1 },
			},
			{
				id = "finish_first",
				label = "Say you'll come when you're done",
				outcome = "You finished what you were doing and went out an hour later. Rae had waited on the wall the whole time.",
				effects = { happiness = 3, smarts = 2 },
			},
			{
				id = "stay_in",
				label = "Say you can't",
				outcome = "You said no and watched from the window. You'd made the sensible call and it felt like nothing at all.",
				effects = { happiness = -3, smarts = 3 },
			},
		},
	},
	{
		id = "visit_the_ladder",
		minAge = 13,
		maxAge = 65,
		delivery = "NPCApproach",
		cast = "neighbor",
		prompt = "Mr. Alderman is on the step. His gutter's come away at one end and he's asking, in a roundabout way that takes a while, whether you'd hold the ladder.",
		writesBack = { "stat:happiness", "stat:health", "stat:looks", "stat:smarts" },
		choices = {
			{
				id = "help",
				label = "Hold the ladder",
				outcome = "It took forty minutes and most of that was him talking. You learned more about the street in that time than in the ten years you'd lived on it.",
				effects = { happiness = 4, smarts = 2, health = -1 },
			},
			{
				id = "do_it_yourself",
				label = "Send him inside and go up yourself",
				outcome = "You went up instead. It was higher than it looked from the ground, and he made you a cup of tea you didn't want and stayed until you'd drunk it.",
				effects = { happiness = 3, health = -3, looks = 1 },
			},
			{
				id = "excuse",
				label = "Say you're busy",
				outcome = "You said you were busy, which was true, and closed the door. He got it done eventually. You still think about the noise the ladder made.",
				effects = { happiness = -3, smarts = 1 },
			},
		},
	},
	{
		id = "visit_the_quiet_word",
		minAge = 16,
		maxAge = 40,
		delivery = "NPCApproach",
		cast = "mom",
		prompt = "Your mother has come round unannounced, which she doesn't do. She sits down before she says anything, which she really doesn't do.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "listen",
				label = "Let her get to it",
				outcome = "You let the silence run and she got there on her own. It took twenty minutes and it was worth every one of them.",
				effects = { happiness = 6, smarts = 2 },
			},
			{
				id = "press",
				label = "Ask her outright what's wrong",
				outcome = "You pushed and she told you, faster and flatter than she'd meant to. You both handled the rest of the afternoon carefully.",
				effects = { happiness = 2, smarts = 3 },
			},
			{
				id = "deflect",
				label = "Fill the silence and talk about anything else",
				outcome = "You talked about nothing for an hour and she left without saying it. She told you six months later, and by then it had been six months.",
				effects = { happiness = -5, health = -1 },
			},
		},
	},

	-- Being unwell, as something that came to the door. The one onset that can
	-- reach any age it wants, so the health loop's sickness occasionally begins
	-- here instead of on a birthday -- and being warned of it in person makes the
	-- rest of the year read differently than a roll of the dice would.
	{
		id = "ambient_flu",
		minAge = 13,
		maxAge = 70,
		delivery = "NPCApproach",
		cast = "friend",
		forbids = { "sick" },
		weight = 0.5,
		prompt = "Rae is at the door, coat still on, voice half gone. 'I've got it,' they say. 'You've probably got it. I thought you'd want to know.'",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts", "flag:sick" },
		choices = {
			{
				id = "let_them_in",
				label = "Let them in anyway",
				outcome = "You sat with them until it got dark, both of you wrecked and neither of you minded. Being ill with somebody is better than being ill alone.",
				effects = { happiness = 3, health = 2 },
				sets = { "sick" },
			},
			{
				id = "send_them_home",
				label = "Send them home to bed",
				outcome = "You sent them off with a full kettle and watched them go. Sensible. You thought about them most of the evening, and then you went down with it yourself.",
				effects = { health = 1, happiness = -1, smarts = 1 },
				sets = { "sick" },
			},
		},
	},

	-- Texture. These are the first repeatable ambient events, marked for exactly
	-- the reason the field exists: a birthday comes round every year and a sale
	-- comes round every few, and a life in this world should be able to live one
	-- twice without the game pretending it is the first time either has happened.
	-- Selection only reaches them after every fresh event has been lived, so they
	-- are what the world does when it has no news, which is what a quiet life
	-- mostly is.
	{
		id = "ambient_neighbor_birthday",
		minAge = 12,
		maxAge = 90,
		delivery = "NPCApproach",
		cast = "neighbor",
		repeatable = true,
		prompt = "There's a knock and then the neighbor's voice through the letterbox, asking whether you're in. It is, it turns out, their birthday.",
		writesBack = { "stat:happiness", "stat:health", "stat:looks", "stat:smarts" },
		choices = {
			{
				id = "bring_something",
				label = "Bring something over and stay for a bit",
				outcome = "You crossed the street with whatever you had and sat in their kitchen until the evening ran out. They told you about the one before this one.",
				effects = { happiness = 5, looks = 1 },
			},
			{
				id = "sing_through_door",
				label = "Sing badly through the letterbox",
				outcome = "You did, from the pavement, and they laughed loud enough that the street heard. It was the right amount for the day.",
				effects = { happiness = 4, health = -1 },
			},
			{
				id = "wish_them",
				label = "Wish them happy birthday and leave it there",
				outcome = "You said it through the door and went back to what you were doing. They thanked you twice, which was worse than not thanking you.",
				effects = { happiness = -1, smarts = 1 },
			},
		},
	},
	{
		id = "ambient_shop_sale",
		minAge = 14,
		maxAge = 999,
		delivery = "Letter",
		repeatable = true,
		prompt = "A leaflet came through the door -- the shop you actually use is having a clearance. There's a thing in the window you've looked at twice.",
		writesBack = { "stat:happiness", "stat:looks", "stat:smarts" },
		choices = {
			{
				id = "splurge",
				label = "Buy the thing you keep looking at",
				outcome = "You bought it at closing time. It was over in a week, and you got a month of looking at it first, which was the real part of the transaction.",
				cost = 20,
				effects = { happiness = 4, looks = 1 },
			},
			{
				id = "browse",
				label = "Browse and buy nothing",
				outcome = "You went down and looked at everything and bought nothing, which is a free afternoon and one of the nicer kinds. The thing was still there the week after.",
				effects = { happiness = 2 },
			},
			{
				id = "bin_it",
				label = "Put it straight in the recycling",
				outcome = "You binned it without reading it. You walked past the shop twice that week and caught yourself wondering what you'd have spent.",
				effects = { smarts = 1, happiness = -1 },
			},
		},
	},
	{
		id = "ambient_first_frost",
		minAge = 16,
		maxAge = 999,
		delivery = "NPCApproach",
		cast = "neighbor",
		repeatable = true,
		prompt = "The first frost of the year is on the ground, and the neighbor is by the fence with a torch in one hand and a jacket in the other, asking if you've seen it.",
		writesBack = { "stat:happiness", "stat:health", "stat:looks" },
		choices = {
			{
				id = "join_them",
				label = "Put on boots and go look at it",
				outcome = "You walked the whole street with them in the dark, stamping on puddles to hear them crack. You knew every house by the light in its window.",
				effects = { happiness = 5, health = 2, looks = -1 },
			},
			{
				id = "window_frost",
				label = "Look at it from the window",
				outcome = "You waved from the warm side of the glass. The frost did its thing and the neighbor did theirs, and both were fine from where you stood.",
				effects = { happiness = 1, health = 1 },
			},
			{
				id = "not_yet",
				label = "Tell them you'll see it tomorrow",
				outcome = "You went back to bed, and the frost was gone by midday. It comes again every year, and you have never once caught the first one.",
				effects = { happiness = -3, health = 2 },
			},
		},
	},
}

return Ambient
