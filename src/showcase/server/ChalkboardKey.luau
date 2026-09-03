--!strict
-- The answer key. Server-only, and that is the whole point of the file existing separately.
--
-- Chalkboard.luau lives in ReplicatedStorage so the panel can draw itself without asking; this
-- does not, so the option a client should have picked is never on the client. The remote carries
-- an index and the server decides what it was worth.

local ChalkboardKey = {}

-- Index into the matching question's Options list.
ChalkboardKey.Answers = {
	q1 = 2, -- 56
	q2 = 3, -- 12
	q3 = 1, -- 9
	q4 = 3, -- 54
	q5 = 4, -- 1/4
	q6 = 2, -- 162
} :: { [string]: number }

function ChalkboardKey.IsCorrect(questionId: string, chosen: number): boolean
	return ChalkboardKey.Answers[questionId] == chosen
end

return ChalkboardKey
