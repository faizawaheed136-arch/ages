--!strict
-- Events that exist only because a tie exists. A rival, a mentor, a sibling --
-- each is a relationship that the game does not model with a flag because the
-- relationship is always with one specific person, and a flag cannot carry that
-- weight. Instead these events carry tags that the context builder fills in
-- when the player stands near somebody they share that tie with, so the picker
-- can prefer them without the event needing to name a specific cast member.
--
-- The cast field is still required on each one so a rig appears when they fire.
-- The cast is the *kind* of person, not the tied individual -- the tied person
-- is who turns up, and the cast is what the world builds for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LifeEvent = Types.LifeEvent

local Ties: { LifeEvent } = {
	-- A mentor who has been waiting for you to be ready for something bigger.
	-- The mentor does not push -- they leave the door open and let you walk
	-- through it, which is the difference between guidance and pressure.
	{
		id = "tie_mentor_guidance",
		minAge = 16,
		maxAge = 70,
		delivery = "NPCApproach",
		cast = "mentor",
		repeatable = true,
		weight = 0.6,
		tags = { "tie:mentor:*" },
		prompt = "Your mentor is at the door with a folder under their arm. They do not sit down. 'I have something for you,' they say, and the way they say it tells you this is not a favour, it is an opportunity.",
		writesBack = { "stat:happiness", "stat:smarts", "stat:looks" },
		choices = {
			{
				id = "take_it",
				label = "Take it",
				outcome = "You took the folder and opened it on the table. It was more than you expected and less than you deserved, which is exactly what a real opportunity looks like.",
				effects = { happiness = 5, smarts = 4, looks = 1 },
			},
			{
				id = "ask_why",
				label = "Ask why them",
				outcome = "You asked why they were the one doing this, and they smiled the way people smile when the answer is simple and you have not thought of it yet. 'Because you listened,' they said.",
				effects = { happiness = 3, smarts = 5 },
			},
			{
				id = "decline",
				label = "Say you need to think about it",
				outcome = "They nodded and did not push. You watched them walk away and wondered whether you had just been polite about something you should have said yes to immediately.",
				effects = { happiness = -2, smarts = 2 },
			},
		},
	},

	-- A rival who has been watching and decides to make a move. Not hostile in
	-- the sharp sense -- a rival in this game is someone who respects you enough
	-- to chase you, not someone who wants to hurt you. The challenge is real,
	-- the stakes are real, and the outcome shifts who you are.
	{
		id = "tie_rival_challenge",
		minAge = 16,
		maxAge = 60,
		delivery = "NPCApproach",
		cast = "rival",
		repeatable = true,
		weight = 0.5,
		tags = { "tie:rival:*" },
		prompt = "Your rival is leaning against the wall where you pass every day. They do not move when you approach. 'I heard what you did,' they say. 'I want to see if you can do it again.'",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "accept",
				label = "Accept the challenge",
				outcome = "You said yes and meant it. They nodded once -- that was the agreement -- and walked away. You did not know what the challenge was yet, but you knew you were going to meet it.",
				effects = { happiness = 4, health = 2, smarts = 1 },
			},
			{
				id = "ask_details",
				label = "Ask what the challenge is",
				outcome = "They told you, and it was harder than you expected. Not because it was difficult but because it was personal, and that is the kind of challenge a rival gives.",
				effects = { happiness = 2, smarts = 4, health = -1 },
			},
			{
				id = "refuse",
				label = "Tell them you are not interested",
				outcome = "They did not look surprised. 'Figures,' they said, and walked away. The word sat with you for a week, and you did not know whether it was their word or yours.",
				effects = { happiness = -4, smarts = 2 },
			},
		},
	},

	-- A sibling who needs you. Not a crisis -- a sibling relationship in this
	-- game is about choice and permanence, and this is the moment the choice
	-- shows up as something you have to do rather than something you have to
	-- decide. The loyalty is the point.
	{
		id = "tie_sibling_loyalty",
		minAge = 16,
		maxAge = 60,
		delivery = "NPCApproach",
		cast = "sibling",
		repeatable = true,
		weight = 0.7,
		tags = { "tie:sibling:*" },
		prompt = "Your sibling is at the door and they do not look like themselves. 'I need you to do something,' they say, and the way they say it means this is not the first time and it will not be the last.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "help",
				label = "Help without asking questions",
				outcome = "You asked nothing and did everything. That is what siblings are for, and you knew it the moment they walked in. It was the easiest and the hardest thing you have ever done.",
				effects = { happiness = 6, health = -2, smarts = 1 },
			},
			{
				id = "ask_first",
				label = "Ask what they need",
				outcome = "They told you, and it was worse than you imagined. You said yes before they finished, which is the only right answer and also the only one that does not feel easy.",
				effects = { happiness = 4, smarts = 3, health = -1 },
			},
			{
				id = "delay",
				label = "Say you need to sort things out first",
				outcome = "They understood. Not because you explained -- you did not need to -- but because siblings understand that kind of pause. You will fix it, and they will wait.",
				effects = { happiness = -3, smarts = 3, health = 1 },
			},
		},
	},
	-- An enemy is the relationship that remains when the ladder is burned. Not
	-- a rival -- a rival still respects you enough to chase you. An enemy does
	-- not. They remember what you did, and every future encounter is a reminder
	-- that some bridges cannot be crossed back. The event exists because a life
	-- with one person who means this much in this direction needs a moment
	-- where that weight shows up as something the player has to face.
	{
		id = "tie_enemy_confrontation",
		minAge = 16,
		maxAge = 999,
		delivery = "NPCApproach",
		cast = "enemy",
		repeatable = true,
		weight = 0.4,
		tags = { "tie:enemy:*" },
		prompt = "Your enemy is at the end of the street and they see you. They do not look away. 'I have been waiting for this,' they say, and the way they say it makes it clear that whatever happens next will not be the last time either of you forgets.",
		writesBack = { "stat:happiness", "stat:health" },
		choices = {
			{
				id = "stand_your_ground",
				label = "Stand your ground",
				outcome = "You did not move. They did not either. The silence between you was heavier than words, and neither of you broke it. It was not a victory. It was not a defeat. It was just the truth of what you had made of each other.",
				effects = { happiness = -2, health = 1 },
			},
			{
				id = "walk_away",
				label = "Walk away",
				outcome = "You turned your back and walked. You did not look over your shoulder. Behind you, they did not call after you. Ahead of you, the street was empty and the weight did not go with them.",
				effects = { happiness = -5, smarts = 2 },
			},
			{
				id = "speak_first",
				label = "Say something first",
				outcome = "You spoke before they could. The words came out wrong -- too sharp, or too soft, or just not the right shape for what you meant. They listened without reacting, and when you finished, they nodded once and moved on. You were left with the echo.",
				effects = { happiness = -3, smarts = 3 },
			},
		},
	},
}

return Ties
