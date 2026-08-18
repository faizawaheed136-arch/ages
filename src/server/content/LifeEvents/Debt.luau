--!strict
-- Debt life events. These only fire when a life is in the red, and they are the
-- single thing that turns a penalty into a turning point: debt is the one number
-- in the game that compounds against the player, so content that reaches in
-- through it is the one that makes the whole economy legible.
--
-- Each event is gated by the `in_debt` flag and closes a door rather than only
-- opening one. An answer may set `loan_shark_deal` or `debt_relief`, which are
-- flags later events require, so debt does not just punish — it writes a path.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LifeEvent = Types.LifeEvent

local Debt: { LifeEvent } = {
	-- The first time debt becomes a choice rather than a number. A man who comes
	-- around on a Tuesday does not knock on the door — he waits until the door is
	-- already open — and the offer is real and the terms are not.
	{
		id = "debt_loan_shark",
		minAge = 18,
		maxAge = 80,
		delivery = "Direct",
		requires = { "in_debt" },
		weight = 0.4,
		prompt = "He knows your name and he knows the number you owe, and he is offering a number lower than both. 'Just a small fee up front,' he says, and it is not a small number.",
		writesBack = { "flag:loan_shark_deal", "flag:debt_relief" },
		choices = {
			{
				id = "take_it",
				label = "Take the deal",
				outcome = "The debt disappeared and the fee appeared on a different ledger. You did not sleep well for three months, but you slept at all, which was more than you had been doing.",
				sets = { "loan_shark_deal" },
				clears = { "in_debt" },
				effects = { happiness = -4, smarts = 2 },
			},
			{
				id = "refuse",
				label = "Tell him to leave",
				outcome = "He nodded the way people nod when they are counting on seeing you again. The bill was still there the next month, and so was he.",
				effects = { happiness = 2, smarts = 1 },
			},
			{
				id = "negotiate",
				label = "Ask for more time",
				outcome = "He gave you two more weeks and a number that was not kinder than the first one. You used the time, and it was not enough, which is what you should have known.",
				sets = { "loan_shark_deal" },
				effects = { happiness = -2, smarts = 3 },
			},
		},
	},

	-- A community program that exists because the council thought this was a good
	-- thing to name out loud. The counsellor is kind, which is the worst part: you
	-- want to do right by someone who is trying, and doing right means admitting
	-- the number was real.
	{
		id = "debt_counselling",
		minAge = 18,
		maxAge = 999,
		delivery = "Direct",
		requires = { "in_debt" },
		forbids = { "loan_shark_deal" },
		weight = 0.6,
		prompt = "A letter has arrived about a free session. You did not apply for it, which is the first thing you notice, and then you notice the rest of it.",
		writesBack = { "flag:debt_relief", "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "go",
				label = "Go and be honest",
				outcome = "You told a stranger the number and they wrote it down without looking up. It was the first time you had said it out loud, and the numbers on the page were the same ones you had been carrying.",
				effects = { happiness = 4, smarts = 3 },
				sets = { "debt_relief" },
			},
			{
				id = "go_light",
				label = "Go and downplay it",
				outcome = "You left out the bits that felt small and the counsellor filled them in from the letter. They were kind about it, which was worse than being angry would have been.",
				effects = { smarts = 1, happiness = -1 },
			},
			{
				id = "do_nothing",
				label = "Leave it unopened",
				outcome = "You put it in the recycling and went to work. It arrived again next month, and the month after, and you were tired of the letter and tired of yourself in about equal measure.",
				effects = { happiness = -3, smarts = 1 },
			},
		},
	},

	-- Money from someone who does not expect it back, which is the difference between
	-- help and a loan and also the thing that makes it complicated. You do not owe
	-- them, and that is heavier than you thought it would be.
	{
		id = "debt_family_help",
		minAge = 18,
		maxAge = 60,
		delivery = "Direct",
		requires = { "in_debt" },
		forbids = { "loan_shark_deal", "debt_relief" },
		weight = 0.5,
		prompt = "Your sister has texted three times in a week. She is not asking about you, and you know what it is before she says it.",
		writesBack = { "flag:debt_relief", "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "accept",
				label = "Take it",
				outcome = "She put the money in an envelope and you did not ask how much. It cleared the debt and left the relationship with the same shape it had always had, which felt wrong and right at once.",
				effects = { happiness = 1, smarts = 2 },
				sets = { "debt_relief" },
			},
			{
				id = "refuse",
				label = "Say no and figure it out alone",
				outcome = "You said no and she said she understood, and neither of you believed it. You paid the interest instead, which is what pride usually costs when it is honest about itself.",
				effects = { happiness = -3, smarts = 2 },
			},
			{
				id = "borrow",
				label = "Call it a loan and write the amount down",
				outcome = "You wrote it down and she signed it, and the paper made it feel like something other than a favour. It did not, and neither of you said so.",
				effects = { happiness = -1, smarts = 3 },
				sets = { "debt_relief" },
			},
		},
	},

	-- The month after debt. The interest has accumulated and the bill has arrived
	-- and the flags from the last event are still there, so this is the moment
	-- where the path you took matters. Fired for anyone who did not resolve the
	-- first event cleanly, or who took the shark deal and then needed more.
	{
		id = "debt_consequences",
		minAge = 18,
		maxAge = 999,
		delivery = "Direct",
		requires = { "in_debt" },
		forbids = { "debt_relief" },
		weight = 0.3,
		prompt = "The number has grown again, and you are not sure whether it is the interest or the new bill or both. The man came round on Tuesday and left a card for the month after.",
		writesBack = { "stat:happiness", "stat:health" },
		choices = {
			{
				id = "work_more",
				label = "Pick up extra shifts until it shrinks",
				outcome = "You did, and it shrank, and you were too tired to do anything else with the money once it was gone. The number went down and the year went by, which was the trade.",
				effects = { health = -4, happiness = -2, smarts = 1 },
			},
			{
				id = "sell_things",
				label = "Sell what you can",
				outcome = "You sold the things you said you would never sell and a few you thought you would. The house felt emptier and the bill was smaller, and you did not know which was worse.",
				effects = { happiness = -3, smarts = 2 },
			},
			{
				id = "walk_away",
				label = "Stop paying and deal with the calls",
				outcome = "The calls came, and you answered some and not others, and the number kept growing anyway. You learned what a collection agency sounds like on the telephone.",
				effects = { happiness = -5, health = -2 },
			},
		},
	},
}

return Debt
