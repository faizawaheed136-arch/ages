--!strict
-- The codes. What a player types into the box in the Codes pane, and what it pays them.
--
-- Content, not configuration, and the split matters. A code is a thing somebody writes on
-- a specific day for a specific reason -- a launch, an apology for an outage, a number a
-- video reads out -- and then retires. That is a list that gets edited constantly by hand,
-- so it lives here beside the ribbons and the jobs rather than in `Config`, which is for
-- numbers that tune how the game behaves.
--
-- Every entry has:
--   id       the permanent key. Written into the save. **Never reuse or rename one.**
--   code     what the player types, matched case-insensitively and space-insensitively.
--   label    what the pane calls it afterwards, in the player's words.
--   money    optional. Paid into the life being played.
--   spins    optional. Added to the account.
--   active   whether it can still be redeemed.
--
-- **`id` and `code` are two fields on purpose, and it is the single most important line in
-- this file.** The save is keyed by `id`, so `code` stays editable: a code that shipped
-- with a typo can be re-spelled tomorrow and the people who already redeemed it still
-- cannot redeem it again. Key the save by the typed string instead and every correction
-- ever made becomes free money for everybody who already had the old one.
--
-- **Retiring a code sets `active = false`; it does not delete the row.** The row is what
-- lets the pane keep saying what a player already got out of it, and a redeemed id with no
-- entry behind it would draw a receipt with the item missing. Deleting one is also how a
-- code becomes redeemable twice, the day somebody adds a new entry and reaches for an id
-- that "is not being used any more".

export type CodeEntry = {
	id: string,
	code: string,
	label: string,
	money: number?,
	spins: number?,
	active: boolean,
}

local Money = require(game:GetService("ReplicatedStorage"):WaitForChild("Money"))

local Codes = {}

-- The rewards here are deliberately small against what an hour of play pays. A code is a
-- thank-you, not a shortcut: the moment one is worth more than a shift, the fastest way to
-- play this game is to go and read a list of codes, and the work in it stops being the
-- point. `AGESLAUNCH` is the largest and it is roughly one shift.
local ENTRIES: { CodeEntry } = {
	{
		id = "launch",
		code = "AGESLAUNCH",
		label = "Launch",
		money = 8000,
		active = true,
	},
	{
		id = "welcome",
		code = "WELCOME",
		label = "Welcome",
		money = 2500,
		active = true,
	},
	{
		-- A spins code rather than a money one, so the pane has to render both shapes from
		-- the first day. A reward kind that has never shipped is a reward kind that has
		-- never been drawn, and the first one to try tends to find out in front of players.
		id = "firstspin",
		code = "FIRSTSPIN",
		label = "A pull on the house",
		spins = 1,
		active = true,
	},
	{
		id = "thanks",
		code = "THANKS",
		label = "Thanks for playing",
		money = 1500,
		spins = 1,
		active = true,
	},
}

-- Every code as one comparable string: uppercase, with all whitespace removed.
--
-- Whitespace removed rather than trimmed, because the two ways a code arrives wrong are a
-- trailing space from a copy-paste and a space typed into the middle of one that was
-- written with a gap in it. Trimming fixes the first and leaves the second, and the second
-- is the one that makes a player certain the code is broken.
function Codes.Normalize(input: string): string
	return string.upper((string.gsub(input, "%s", "")))
end

-- Built once at require, so a lookup is a hash rather than a walk, and so a duplicate is
-- caught at boot rather than by whichever of the two entries the loop happened to reach
-- first. Two rows sharing a typed string is a content mistake that would otherwise be
-- invisible: the code works, and one of the two rewards is simply unreachable forever.
local BY_CODE: { [string]: CodeEntry } = {}
local BY_ID: { [string]: CodeEntry } = {}
for _, entry in ENTRIES do
	local normalized = Codes.Normalize(entry.code)
	if normalized == "" then
		error(`Codes: entry "{entry.id}" has an empty code. Give it something to type.`)
	end
	if BY_CODE[normalized] ~= nil then
		error(
			`Codes: "{entry.code}" is spelled by both "{BY_CODE[normalized].id}" and "{entry.id}". `
				.. `One of them can never be redeemed -- change one of the strings.`
		)
	end
	if BY_ID[entry.id] ~= nil then
		error(`Codes: two entries share the id "{entry.id}". Ids are written into saves and must be unique.`)
	end
	if (entry.money or 0) <= 0 and (entry.spins or 0) <= 0 then
		error(`Codes: "{entry.id}" pays nothing. Give it money, spins, or both, or delete it.`)
	end
	BY_CODE[normalized] = entry
	BY_ID[entry.id] = entry
end

-- What the player typed, or nil. Takes the raw string and normalizes it here rather than
-- asking the caller to, so there is exactly one definition of "the same code" in the tree.
function Codes.Find(input: string): CodeEntry?
	return BY_CODE[Codes.Normalize(input)]
end

-- By save key, for drawing the list of what an account has already used.
function Codes.ById(id: string): CodeEntry?
	return BY_ID[id]
end

-- What an entry pays, written out for a player. Lives here rather than on the client
-- because the reward shapes are content: a code that starts paying something new should
-- need one edit in this file, not one here and one in a pane.
function Codes.Describe(entry: CodeEntry): string
	local parts: { string } = {}
	local money = entry.money or 0
	if money > 0 then
		table.insert(parts, Money.Format(money))
	end
	local spins = entry.spins or 0
	if spins > 0 then
		table.insert(parts, if spins == 1 then "1 spin" else `{spins} spins`)
	end
	return table.concat(parts, " and ")
end

-- Exposed after the checks above have run, so nothing can hold a reference to a list that
-- failed validation.
Codes.Entries = ENTRIES

return Codes
