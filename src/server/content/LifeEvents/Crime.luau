--!strict
-- Crime life events. These are the narrative consequences of the mechanical
-- systems — theft, bounty, police, gangs — and they only fire when the player
-- has done something that leaves a flag behind. No event here triggers a mini-game;
-- they respond to one.
--
-- Every event writes at least one durable thing (flag, stat, or money) so the
-- loader's writesBack check is satisfied, and every event has an outcome that
-- reads like a memory rather than a tutorial.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LifeEvent = Types.LifeEvent

local Crime: { LifeEvent } = {
	-- The first time a life crosses the line from wanting something to taking it.
	-- Small, almost comic — eight dollars from a till — but the flag it sets is
	-- the hinge everything else turns on. No cast, because the event is about
	-- the player's own decision, not somebody else's presence.
	{
		id = "crime_first_shoplift",
		minAge = 13,
		maxAge = 17,
		delivery = "Direct",
		weight = 0.3,
		prompt = "The shop is quiet and the till is open. You have four dollars and the shelf is full of things you cannot afford. Nobody is watching.",
		writesBack = { "flag:first_crime", "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "take_it",
				label = "Take it",
				outcome = "You walked out with eight dollars in your pocket and your heart in your throat. It was the stupidest thing you had ever done, and you did not know that yet.",
				effects = { happiness = 3, smarts = -2 },
				sets = { "first_crime" },
			},
			{
				id = "take_almost",
				label = "Take something smaller and leave the rest",
				outcome = "You took a single snack and put the rest back. The guilt was smaller, and the thrill was smaller still, and you wondered which was worse.",
				effects = { happiness = 1, smarts = -1 },
				sets = { "first_crime" },
			},
			{
				id = "walk_away",
				label = "Walk away and pretend you were never tempted",
				outcome = "You walked out empty-handed and told yourself you had never wanted anything. The lie was easy, and it was also a choice.",
				effects = { smarts = 2, happiness = -1 },
			},
		},
	},

	-- The moment the line becomes a wall. Caught in the act, with the clerk's
	-- voice still ringing in your ears. The bounty spike is real — the service
	-- handles that — but this event is about what the moment feels like from
	-- the inside.
	{
		id = "crime_caught_shoplift",
		minAge = 14,
		maxAge = 18,
		delivery = "Direct",
		requires = { "first_crime" },
		forbids = { "convicted" },
		weight = 0.6,
		prompt = "You are still in the aisle when the clerk's hand lands on your shoulder. You have not even reached the door yet. The other customers are looking, and you are not sure who is worse — the ones who recognise you or the ones who do not.",
		writesBack = { "flag:busted", "stat:happiness", "stat:health" },
		choices = {
			{
				id = "freeze",
				label = "Stand still and say nothing",
				outcome = "You stood there while the clerk called the police and you counted the seconds. It was the worst ten seconds of your life and also the shortest.",
				effects = { happiness = -5, health = -1 },
				sets = { "busted" },
			},
			{
				id = "run",
				label = "Run",
				outcome = "You ran. The door caught your jacket and you tore it free, and then you were outside and the street was full of people who had just seen you run. You did not look back.",
				effects = { happiness = -3, health = -2, smarts = 1 },
				sets = { "busted" },
			},
			{
				id = "apologize",
				label = "Put it back and say sorry",
				outcome = "You put it back and said sorry before the clerk could say anything. They did not believe you, but the police came anyway — sorry does not cancel a report, only softens it.",
				effects = { happiness = -2, smarts = 3 },
				sets = { "busted" },
			},
		},
	},

	-- The first time somebody who runs with a gang notices you. This is not an
	-- invitation to join — it is an invitation to be seen, which is the harder
	-- choice. Gated on first_crime because a clean life is not interesting to
	-- them, and on not_busted because a known kid is already taken care of.
	{
		id = "crime_gang_approach",
		minAge = 15,
		maxAge = 20,
		delivery = "NPCApproach",
		cast = "neighbor",
		requires = { "first_crime" },
		forbids = { "busted", "convicted", "gang_recruited" },
		weight = 0.4,
		prompt = "A person you do not know but recognise — they live three streets over and you have seen them with people you do not want to know — stops you on the corner. ' heard you have nerve. We could use that.'",
		writesBack = { "flag:gang_recruited", "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "listen",
				label = "Ask what they mean",
				outcome = "They told you. It sounded easy in their voice, and harder in yours. You did not say yes, but you did not say no either, and that was the point.",
				effects = { happiness = 2, smarts = -1 },
				sets = { "gang_recruited" },
			},
			{
				id = "refuse",
				label = "Tell them you are not interested",
				outcome = "They nodded the way people nod when they are counting on seeing you again. You walked away clean, and you knew you would be noticed again.",
				effects = { happiness = -1, smarts = 2 },
			},
			{
				id = "walk_away_silent",
				label = "Walk away without answering",
				outcome = "You kept walking. Behind you, the voice said nothing, which was worse than an answer would have been.",
				effects = { happiness = -3, smarts = 1 },
			},
		},
	},

	-- The loyalty test. A gang member asks you to do something small and illegal
	-- as a way of proving you belong. The consequences are real — bounty, record,
	-- a choice that cannot be undone — but the event is about the pressure of the
	-- moment, not the arithmetic.
	{
		id = "crime_gang_test",
		minAge = 16,
		maxAge = 22,
		delivery = "NPCApproach",
		cast = "neighbor",
		requires = { "gang_recruited" },
		forbids = { "convicted" },
		weight = 0.5,
		prompt = "The same person from the corner is back, and this time they are not asking for an answer — they are asking for a favour. 'Just this once. Nobody gets hurt.'",
		writesBack = { "flag:escalated_to_big_crime", "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "do_it",
				label = "Do it",
				outcome = "You did it. It was smaller than they made it sound and larger than you expected, and the look on their face when you finished was the first time you understood what loyalty costs.",
				effects = { happiness = -2, health = -1, smarts = 1 },
				sets = { "escalated_to_big_crime" },
			},
			{
				id = "refuse_soft",
				label = "Say you will think about it",
				outcome = "You bought time, and they accepted the answer you did not give. The next time they ask will be harder.",
				effects = { happiness = -1, smarts = 2 },
			},
			{
				id = "refuse_hard",
				label = "Say no",
				outcome = "You said no out loud, and the silence after was louder than yes would have been. They did not threaten you — they did not need to.",
				effects = { happiness = -3, smarts = 3 },
			},
		},
	},

	-- The arrest aftermath. You are out of custody and the world has not changed,
	-- but everything around you has. Employers ask different questions. Police
	-- watch you differently. The flag is what matters — this event is the moment
	-- you realise the record is real.
	{
		id = "crime_arrest_aftermath",
		minAge = 16,
		maxAge = 40,
		delivery = "Direct",
		requires = { "convicted" },
		forbids = { "on_parole" },
		weight = 0.5,
		prompt = "You are out. The door closed behind you and the street looked the same, but it did not. People you pass seem to know, or they think they know, and you are not sure which is worse.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "keep_head_down",
				label = "Keep your head down and move on",
				outcome = "You did. For a while it worked, and then it did not — staying invisible is exhausting, and the exhaustion shows.",
				effects = { happiness = -3, health = -2, smarts = 1 },
			},
			{
				id = "own_it",
				label = "Own it and keep going",
				outcome = "You told the people who asked and moved on. Some believed you, some did not, and the ones who did not were the ones who mattered.",
				effects = { happiness = 2, smarts = 2, health = -1 },
			},
			{
				id = "leave_town",
				label = "Leave and do not look back",
				outcome = "You left. The town was small enough that leaving was visible, and people talked about you after you went. Talking is a kind of presence.",
				effects = { happiness = -4, smarts = 1 },
			},
		},
	},

	-- The parole check-in. A uniformed person at a desk, a form to sign, a
	-- question about where you have been. It is not dramatic — it is administrative,
	-- which is the point. The record follows you into rooms you thought were yours.
	{
		id = "crime_parole_check",
		minAge = 16,
		maxAge = 40,
		delivery = "Direct",
		requires = { "on_parole" },
		weight = 0.7,
		prompt = "You have to go to the office. The officer behind the desk does not look up when you sit down. 'Where have you been this month?' it is not a friendly question.",
		writesBack = { "flag:on_parole", "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "tell_truth",
				label = "Tell the truth",
				outcome = "You told them. It was harder than you expected and easier than you feared — the officer wrote it down and moved to the next line.",
				effects = { happiness = 1, smarts = 2 },
				clears = { "on_parole" },
			},
			{
				id = "leave_out",
				label = "Leave out the bits that sound bad",
				outcome = "You edited. It was not a lie, exactly, but the officer had heard the other version and knew the difference between the two.",
				effects = { happiness = -3, smarts = 1 },
			},
			{
				id = "shut_down",
				label = "Say nothing until they move on",
				outcome = "You stayed quiet. Silence is not evidence, but it is not innocence either, and the officer filed it away.",
				effects = { happiness = -2, smarts = -1 },
			},
		},
	},

	-- Employment stigma. You apply for a job and the background check comes back.
	-- The gate is not absolute — some employers do not care, some care too much —
	-- but the flag is what opens the door that stays open.
	{
		id = "crime_job_stigma",
		minAge = 18,
		maxAge = 55,
		delivery = "Direct",
		requires = { "convicted" },
		weight = 0.4,
		prompt = "You applied for a job that would have been fine if they had not asked about your record. They asked. You told the truth, and then they asked again, softer, like they hoped you had forgotten how to say it.",
		writesBack = { "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "try_again",
				label = "Apply somewhere else",
				outcome = "You applied somewhere else. The second place did not ask, or they asked and did not care, and you wondered which was luck and which was skill.",
				effects = { happiness = 1, smarts = 2 },
			},
			{
				id = "push",
				label = "Push back and insist you are qualified",
				outcome = "You pushed. It did not help — the record was the record, and your qualifications were real but secondary to a piece of paper neither of you could see.",
				effects = { happiness = -3, smarts = 1 },
			},
			{
				id = "give_up_temp",
				label = "Take anything for now and hope it changes",
				outcome = "You took anything. It paid, and it was beneath you, and you told yourself it was temporary — which is what you tell yourself until it is not.",
				effects = { happiness = -2, smarts = -1 },
			},
		},
	},

	-- The debt-crime spiral. Debt pushes you toward crime; crime pushes you
	-- deeper into debt through fines, lost wages, and the attention it attracts.
	-- This event is the moment you notice the circle.
	{
		id = "crime_debt_spiral",
		minAge = 18,
		maxAge = 40,
		delivery = "Direct",
		requires = { "in_debt", "first_crime" },
		forbids = { "convicted" },
		weight = 0.5,
		prompt = "The bill arrived and you looked at the number and then at the shop down the street with the open till. You have stolen before. You know how it works. The math is simple and the answer is not.",
		writesBack = { "flag:escalated_to_big_crime", "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "do_it_again",
				label = "Do it again",
				outcome = "You did. The money helped for three weeks and then the bounty did not, and the bill was still there, and now you were watching your back in the shop too.",
				effects = { happiness = -4, health = -2, smarts = 1 },
				sets = { "escalated_to_big_crime" },
			},
			{
				id = "ask_for_help",
				label = "Ask somebody for help instead",
				outcome = "You asked. They said no, or they said maybe, or they said nothing at all — which is the same thing — and you went home and looked at the bill again.",
				effects = { happiness = -2, smarts = 2 },
			},
			{
				id = "find_another_way",
				label = "Find another way",
				outcome = "You found another way. It was slower and harder and paid less, but it was yours, and the bill shrank by a different amount than you expected.",
				effects = { happiness = 1, smarts = 3, health = -1 },
			},
		},
	},

	-- The escalation. You have stolen before, you are not busted, and somebody
	-- with more experience offers you a bigger job. The offer is real and the
	-- stakes are higher, and the choice is between the known risk and the unknown
	-- one.
	{
		id = "crime_escalation_offer",
		minAge = 17,
		maxAge = 30,
		delivery = "NPCApproach",
		cast = "neighbor",
		requires = { "first_crime" },
		forbids = { "busted", "convicted", "gang_recruited" },
		weight = 0.3,
		prompt = "Someone older than you, with the look of somebody who has done this before, catches your eye in the queue. 'You look like you know how to keep your mouth shut. I have a job that pays better than the shop.'",
		writesBack = { "flag:escalated_to_big_crime", "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "take_it",
				label = "Take the job",
				outcome = "You took it. It paid well and it went wrong in a way that had nothing to do with the money, and you wished you had said no before you wished for anything else.",
				effects = { happiness = -3, smarts = 2 },
				sets = { "escalated_to_big_crime" },
			},
			{
				id = "ask_details",
				label = "Ask what the job actually is",
				outcome = "They told you. It was worse than you expected and better paid, and you understood why they had not led with the details.",
				effects = { smarts = 3, happiness = -1 },
			},
			{
				id = "refuse",
				label = "Say no and keep walking",
				outcome = "You said no. They did not look surprised, which was worse than anger would have been — it meant they had already decided you would come around.",
				effects = { happiness = 1, smarts = 1 },
			},
		},
	},

	-- The conviction that changes everything. A second arrest, a longer sentence,
	-- and the realisation that the record is not a mark — it is a shape, and it
	-- is reshaping the life around it. This only fires for lives that have been
	-- convicted before and are caught again.
	{
		id = "crime_second_conviction",
		minAge = 18,
		maxAge = 50,
		delivery = "Direct",
		requires = { "convicted" },
		forbids = { "on_parole" },
		weight = 0.3,
		prompt = "You thought the first time was the only time. It was not. The second time is different — longer, louder, and with people who remember you from before. The court does not care that you have been here.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "accept",
				label = "Accept it and move through it",
				outcome = "You moved through it. The years went and then they did not, and you came out older and harder and not entirely sorry for the people you had become in between.",
				effects = { happiness = -5, health = -3, smarts = 2 },
			},
			{
				id = "fight",
				label = "Fight it",
				outcome = "You fought. It cost more than accepting would have, and it changed nothing, and you learned something about yourself that you wish you had not.",
				effects = { happiness = -4, health = -2, smarts = 1 },
			},
			{
				id = "break",
				label = "Break and say nothing",
				outcome = "You broke. The silence lasted through the whole thing, and when it was over you did not know who you were anymore, only that you were still here.",
				effects = { happiness = -7, health = -4 },
			},
		},
	},

	-- The release. You walk out of custody and the world is the same and not the
	-- same. The on_parole flag is set here and drives the next set of events.
	{
		id = "crime_release",
		minAge = 16,
		maxAge = 50,
		delivery = "Direct",
		requires = { "convicted" },
		forbids = { "on_parole" },
		weight = 0.8,
		prompt = "The door closes behind you and the air outside is the same as it was before. It is not. You can feel the difference even if nobody else can, and that is the hardest part.",
		writesBack = { "flag:on_parole", "stat:happiness", "stat:health" },
		choices = {
			{
				id = "face_it",
				label = "Face it head-on",
				outcome = "You faced it. The first week was the hardest and then the weeks blurred together, and you learned that time passes differently when you are not running from it.",
				effects = { happiness = 2, health = 1 },
				sets = { "on_parole" },
			},
			{
				id = "disappear",
				label = "Disappear for a while",
				outcome = "You disappeared. For two weeks nobody knew where you were, and then you came back and the world had kept turning without you, which was either comforting or devastating.",
				effects = { happiness = -3, smarts = 1 },
				sets = { "on_parole" },
			},
			{
				id = "reach_out",
				label = "Reach out to somebody",
				outcome = "You reached out. They answered, or they did not, but the reaching was the point — the answer was just the answer.",
				effects = { happiness = 3, smarts = 2 },
				sets = { "on_parole" },
			},
		},
	},
}

return Crime
