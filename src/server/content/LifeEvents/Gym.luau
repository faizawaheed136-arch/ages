--!strict
-- Gym and fitness life events. The gym opens at age 13 (Ambient.MinAge) and is
-- available for the rest of a life; these events fire as birthday moments or
-- ambient triggers and offer stat choices around health, looks, happiness, and
-- sometimes smarts. No performance scores (these are not shift events). Every
-- event has at least one free choice and every choice moves at least one stat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LifeEvent = Types.LifeEvent

local Gym: { LifeEvent } = {
	-- The first time the gym becomes an option: a free trial card through the
	-- door. Three ways to use it, all reasonable, none costing money.
	{
		id = "gym_easy_start",
		minAge = 13,
		maxAge = 50,
		delivery = "Direct",
		prompt = "There's a free trial card on the counter at the gym. You've walked past it enough times to know where it is.",
		choices = {
			{
				id = "treadmill",
				label = "Walk on the treadmill for half an hour",
				outcome = "You walked, slowly, while people who clearly knew what they were doing moved around you. By the third visit the headphones felt natural.",
				effects = { health = 2, happiness = 1 },
				sets = { "gym_joined" },
			},
			{
				id = "free_weights",
				label = "Go straight for the free weights",
				outcome = "You picked up something too heavy, put it back, and pretended you were just looking at it. A stranger showed you a different one and you both nodded.",
				effects = { health = 3, looks = 2, happiness = -1 },
				sets = { "gym_joined" },
			},
			{
				id = "stretching",
				label = "Just use the stretching area",
				outcome = "You spent forty minutes on the mats, bending in ways that turned out to matter more than you expected. Your back stopped hurting in about three weeks.",
				effects = { health = 1, happiness = 2 },
				sets = { "gym_joined" },
			},
		},
	},
	-- A specific, measurable goal. The training montage is the good ending;
	-- the park is the healthy compromise; the cafe is the human one.
	{
		id = "gym_goal",
		minAge = 16,
		maxAge = 55,
		delivery = "Direct",
		prompt = "There's a charity run in October. Six weeks away. You keep thinking about it and then not doing anything.",
		choices = {
			{
				id = "train",
				label = "Train for it seriously",
				outcome = "Six weeks of interval training and a spreadsheet you'd never admit to. You finished in the top third and felt like you could do anything.",
				effects = { health = 4, smarts = 1, happiness = 2 },
				sets = { "gym_joined" },
			},
			{
				id = "jog_park",
				label = "Jog around the park instead",
				outcome = "You ran three times a week, at your own pace, past the same dogs. You entered the run and finished it, which was the whole point.",
				effects = { health = 2, happiness = 3 },
				sets = { "gym_joined" },
			},
			{
				id = "cafe",
				label = "Watch it from the cafe",
				outcome = "You sat with a coffee and watched five hundred people in luminous vests run past. You clapped. It was genuinely moving.",
				effects = { happiness = 2, smarts = 1 },
			},
		},
	},
	-- A social moment at the gym: strangers becoming a semi-regular group.
	-- NPCApproach delivery with a neighbor cast.
	{
		id = "gym_running_group",
		minAge = 18,
		maxAge = 70,
		delivery = "NPCApproach",
		cast = "neighbor",
		prompt = "The neighbor from three doors down is stretching by the door in running gear. They've noticed you at the same time every week and have come over to ask.",
		choices = {
			{
				id = "join",
				label = "Join them",
				outcome = "You ran together every Tuesday and Thursday for over a year. The conversation covered everything and nothing, which is what a run is for.",
				effects = { health = 3, happiness = 4 },
				sets = { "gym_joined" },
			},
			{
				id = "own_pace",
				label = "Wave and keep your pace",
				outcome = "You nodded and carried on. They waved back and you both went your own way. You saw them next week and nodded again.",
				effects = { health = 2, happiness = -1 },
			},
			{
				id = "avoid",
				label = "Cross to the other side",
				outcome = "You dodged without thinking and spent the rest of the session wondering whether that was rude. It was, a bit.",
				effects = { happiness = -2, smarts = 1 },
			},
		},
	},
	-- Being new somewhere and having somebody show you around.
	-- Friend cast, so capped at teen years.
	{
		id = "gym_new_kid",
		minAge = 13,
		maxAge = 17,
		delivery = "NPCApproach",
		cast = "friend",
		prompt = "Your friend has just joined the gym and is standing in the middle of the floor looking lost. They have seen you and are heading over.",
		choices = {
			{
				id = "show_around",
				label = "Show them around",
				outcome = "You gave them the tour: which machines were broken, where the good mirrors were, and which treadmills had the wobble. They looked grateful.",
				effects = { happiness = 3 },
			},
			{
				id = "workout_together",
				label = "Work out together",
				outcome = "You ended up next to each other for an hour, swapping phones between sets. It was the most social either of you had been in weeks.",
				effects = { health = 2, happiness = 2 },
			},
			{
				id = "point_to_coach",
				label = "Point them to the coach",
				outcome = "You pointed at the desk and mouthed 'ask them' and went back to your set. They sorted it out. You met up afterwards for a drink.",
				effects = { happiness = 1 },
			},
		},
	},
	-- A workout that crosses the line from hard work to actual damage.
	-- Has a costed doctor option, mirroring adult_caught_something. Sets
	-- the "sick" flag so the event cannot repeat immediately.
	{
		id = "gym_pushed_too_hard",
		minAge = 16,
		maxAge = 70,
		delivery = "Direct",
		forbids = { "sick" },
		prompt = "You went hard yesterday and this morning something in your knee is clicking. It's not terrible but it's definitely there.",
		choices = {
			{
				id = "rest",
				label = "Take a few days off",
				outcome = "Three days of doing nothing and it sorted itself out. You'd been due a rest and your body had simply decided for you.",
				effects = { health = 2, happiness = -1 },
				sets = { "sick" },
			},
			{
				id = "push_through",
				label = "Push through it",
				outcome = "You ran on it anyway and it got worse for a week before it got better. You learned something about pride, which is what pain is usually teaching.",
				effects = { happiness = 1, health = -3 },
				sets = { "sick" },
			},
			{
				id = "see_doctor",
				label = "See a doctor about it",
				outcome = "A ten-minute appointment, a referral for a scan, and a bill. The scan was clear. You paid for the peace of mind and it was worth it.",
				cost = 120,
				effects = { health = 5, happiness = 1 },
				sets = { "sick" },
			},
		},
	},
	-- The long drift away from a routine. Only fires for someone who has
	-- already been going -- gated by "gym_joined" which gym_first_membership
	-- or any sustained attendance sets.
	{
		id = "gym_lapsed",
		minAge = 22,
		maxAge = 999,
		delivery = "Direct",
		requires = { "gym_joined" },
		prompt = "It has been four months. The direct debit keeps going out and you keep meaning to cancel it or go back, and you have done neither.",
		choices = {
			{
				id = "go_back",
				label = "Go back this week",
				outcome = "You went back on a Tuesday. Everything hurt for the first session and nothing did after the third. The treadmill remembered your speed.",
				effects = { health = 3, happiness = 3 },
			},
			{
				id = "cancel",
				label = "Cancel the membership",
				outcome = "You cancelled it and felt relief and loss in about equal measure. The money stayed; the habit didn't.",
				effects = { happiness = -1, health = -1 },
			},
			{
				id = "keep_deferring",
				label = "Keep putting it off",
				outcome = "Another six months went by before you noticed. The money kept leaving and the bag stayed by the door.",
				effects = { happiness = -3, health = -1 },
			},
		},
	},
	-- The fun run: looks are the point, but the health is a side effect
	-- nobody argues with. Direct, because it is a decision not a person.
	{
		id = "gym_fun_run",
		minAge = 16,
		maxAge = 60,
		delivery = "Direct",
		prompt = "A local five-kilometre fun run is being advertised everywhere. It is not serious and that is the whole appeal.",
		choices = {
			{
				id = "enter_serious",
				label = "Enter properly and train for it",
				outcome = "You ran it in under thirty minutes, which put you in the top quarter. You wore the medal to the shop afterwards.",
				effects = { health = 3, looks = 3, happiness = 2 },
				sets = { "gym_joined" },
			},
			{
				id = "enter_fun",
				label = "Enter and just enjoy it",
				outcome = "You ran in a silly costume with three friends and stopped for chips on the way back. Your time was terrible and your day was not.",
				effects = { health = 2, happiness = 4 },
				sets = { "gym_joined" },
			},
			{
				id = "volunteer",
				label = "Volunteer at the water station instead",
				outcome = "You handed out cups and cheered strangers for two hours. You were in bed by eight, satisfied in a way that surprised you.",
				effects = { happiness = 3, health = 1 },
			},
		},
	},
}

return Gym
