--!strict
-- The chalkboard's questions, without their answers.
--
-- **The answers are deliberately not in here.** This module is replicated, so anything in it is
-- readable by any client -- a question bank with its key attached is a quiz you have already
-- given away. The prompts and the options are shared so the panel can draw itself with no round
-- trip; the key lives in ChalkboardKey.luau on the server and never leaves it.
--
-- The client sends the *index* it picked. It is not trusted with what that index means.

export type Question = {
	Id: string,
	Prompt: string,
	Options: { string },
}

local Chalkboard = {}

Chalkboard.Questions = {
	{ Id = "q1", Prompt = "7 × 8", Options = { "54", "56", "48", "64" } },
	{ Id = "q2", Prompt = "144 ÷ 12", Options = { "11", "14", "12", "16" } },
	{ Id = "q3", Prompt = "3x = 27, so x =", Options = { "9", "8", "6", "12" } },
	{ Id = "q4", Prompt = "The area of a 9 × 6 rectangle", Options = { "15", "45", "54", "36" } },
	{ Id = "q5", Prompt = "0.25 as a fraction", Options = { "1/2", "1/5", "2/5", "1/4" } },
	{ Id = "q6", Prompt = "The next term: 2, 6, 18, 54, …", Options = { "108", "162", "72", "216" } },
} :: { Question }

Chalkboard.ByIdIndex = {} :: { [string]: number }
for index, question in Chalkboard.Questions do
	Chalkboard.ByIdIndex[question.Id] = index
end

-- How many questions make a lesson, and how long the board waits before it gives up on a player
-- who walked away mid-question.
Chalkboard.QuestionsPerLesson = 4
Chalkboard.AnswerCooldown = 0.4

return Chalkboard
