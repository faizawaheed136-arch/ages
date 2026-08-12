--!strict
-- The things an Art lesson asks you to copy.
--
-- A study is a small picture pinned to the wall, written here as rows of letters so that
-- it can be *seen* in the source. Each letter is a pigment -- see shared/world/Pigments
-- for the shelf -- and each row is a row of the canvas, top to bottom.
--
-- Alongside every picture is a second grid the same size saying which parts of it are
-- allowed to move. That is the mechanic and not a decoration: a study that sat still
-- would be a colouring book, and the reason there is anything to think about here is
-- that the light shifts and somebody moves the fruit while you are painting. `.` is
-- nailed down and `*` may change. Every study needs at least one `*`, checked below,
-- because a study with none has no second queue in it -- and the whole difference
-- between this and a form to fill in is having two things to spend the next ten seconds
-- on.
--
-- Deliberately not banded by age, unlike Procedures. The difficulty in this subject does
-- not live in the picture, it lives in how many tubes of paint you have been handed --
-- see School.Art.PaletteByLevel -- so a six-year-old and a fourteen-year-old copying the
-- same harbour are having genuinely different afternoons, and splitting the pictures by
-- age on top of that would be pricing the same thing twice.
--
-- Nothing here scores anything or knows what a lesson is. This is the wall.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Pigments = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Pigments"))

local Studies = {}

local ART = Config.School.Art

-- One picture on the wall, as authored.
export type StudySource = {
	id: string,
	-- Said out loud when the lesson starts, and written under the wall. A title rather
	-- than a description, because being told "harbour, morning" and then having to work
	-- out which blue is the water is the closest this subject gets to a question.
	name: string,
	-- Top row first. One letter per cell, and every row must be Columns long.
	grid: { string },
	-- The same shape again: `.` fixed, `*` free to change while you paint.
	moves: { string },
}

-- One picture, parsed and ready to hand to a lesson.
export type Study = {
	id: string,
	name: string,
	-- Cell index 1..Columns*Rows, reading left to right then top to bottom -- the order
	-- the canvas draws in, so a cell index means the same thing on the wall, in the
	-- session and on screen without anything mapping between them.
	cells: { Pigments.Pigment },
	-- The indices that may shift, precomputed because the shift timer asks for one at
	-- random several times a lesson and walking the mask each time would be re-reading a
	-- constant.
	movable: { number },
	-- Every pigment this picture is made of, most-used first. This is what a palette is
	-- cut from: rung one hands over the first two, and the rungs above it hand over the
	-- rest -- so what levelling up buys is literally the colours the picture barely needs,
	-- which are the ones that make it look like the thing it is of.
	byUse: { Pigments.Pigment },
}

local COLUMNS = ART.Columns
local ROWS = ART.Rows
local CELLS = COLUMNS * ROWS

local SOURCE: { StudySource } = {
	-- Two thirds water and sky, and then four cells that are the entire picture: a sail,
	-- a hull and a buoy. The most pigments of any study here on purpose -- it is the one
	-- that still has something left to give at the top of the ladder.
	{
		id = "harbour",
		name = "Harbour, morning",
		grid = {
			"sssl",
			"swdl",
			"dkkr",
			"dddm",
		},
		moves = {
			"....",
			".*..",
			"..**",
			"....",
		},
	},

	-- The classroom still life, and the one where the shifting is somebody's hand rather
	-- than the weather: the fruit gets nudged around the board while you are looking down.
	{
		id = "fruit",
		name = "Three fruit on a board",
		grid = {
			"wwlw",
			"orwm",
			"kork",
			"kkkk",
		},
		moves = {
			"....",
			"**.*",
			".**.",
			"....",
		},
	},

	-- A window with the room dark around it. Only the light moves, which makes this the
	-- study where the volatile cells are all in one place -- so the right technique is to
	-- paint the frame first and leave the glass until last, and finding that out is the
	-- point.
	{
		id = "window",
		name = "The window, afternoon",
		grid = {
			"kssk",
			"kook",
			"lwwl",
			"kklk",
		},
		moves = {
			".**.",
			".**.",
			"....",
			"....",
		},
	},

	-- The opposite arrangement: the whole top row is sky and the whole top row moves, so
	-- there is no safe corner to hide in and the only question is whether you repaint a
	-- cloud or go and finish the road.
	{
		id = "hill",
		name = "Hill road",
		grid = {
			"ssss",
			"mmls",
			"mllm",
			"oomk",
		},
		moves = {
			"****",
			"....",
			"....",
			"....",
		},
	},

	-- Nearly monochrome, which makes it the hardest one to paint badly and the easiest
	-- one to paint dully: at two tubes it is genuinely almost right, and every rung after
	-- that is spent on four cells of highlight.
	{
		id = "kettle",
		name = "Kettle on the sill",
		grid = {
			"lllo",
			"lwwl",
			"lwkr",
			"kkkk",
		},
		moves = {
			"....",
			".**.",
			".**.",
			"....",
		},
	},
}

-- Parsed once at require time, and every failure names the study, the row and what to do
-- about it. A study is sixteen characters of hand-typed picture; the odds of one of them
-- being a typo over the life of this file are close to one, and the symptom of an
-- unchecked typo is a wall with a colour on it nobody chose.
local ALL: { Study } = {}
local byId: { [string]: Study } = {}

-- Reads one letter grid into a flat list, or errors saying exactly where it went wrong.
-- Shared by the picture and the movement mask because both are the same shape, and the
-- day they stopped being the same shape is the day a mask would start marking the wrong
-- cell as volatile without anything noticing.
local function eachCell(study: StudySource, rows: { string }, label: string, visit: (number, string) -> ())
	if #rows ~= ROWS then
		error(
			`[AGES content] study "{study.id}" has {#rows} {label} rows but School.Art.Rows is {ROWS}.`
				.. ` A canvas and the wall it is copied from have to be the same shape.`
		)
	end
	for row, text in rows do
		if #text ~= COLUMNS then
			error(
				`[AGES content] study "{study.id}" {label} row {row} is "{text}", which is {#text} characters`
					.. ` against School.Art.Columns of {COLUMNS}. Every row must be exactly that long.`
			)
		end
		for column = 1, COLUMNS do
			visit((row - 1) * COLUMNS + column, string.sub(text, column, column))
		end
	end
end

for _, source in SOURCE do
	if byId[source.id] ~= nil then
		error(`[AGES content] duplicate study id "{source.id}"`)
	end

	local cells: { Pigments.Pigment } = {}
	local counts: { [string]: number } = {}
	eachCell(source, source.grid, "grid", function(index, letter)
		local pigment = Pigments.FromLetter(letter)
		if pigment == nil then
			error(
				`[AGES content] study "{source.id}" uses the letter "{letter}", which no pigment claims.`
					.. ` Either fix the typo or add the paint in shared/world/Pigments -- a wall cannot be`
					.. ` built out of a colour the game does not stock.`
			)
		end
		cells[index] = pigment
		counts[pigment.id] = (counts[pigment.id] or 0) + 1
	end)

	local movable: { number } = {}
	eachCell(source, source.moves, "moves", function(index, mark)
		if mark == "*" then
			table.insert(movable, index)
		elseif mark ~= "." then
			error(
				`[AGES content] study "{source.id}" has "{mark}" in its movement mask, which means nothing.`
					.. ` Use "." for a cell that stays put and "*" for one that may change.`
			)
		end
	end)

	if #movable == 0 then
		error(
			`[AGES content] study "{source.id}" has no "*" in its movement mask, so nothing in it ever`
				.. ` changes. That is a colouring book rather than a study -- mark at least one cell.`
		)
	end

	-- Most-used first, and ties broken by the shelf order rather than by whatever order
	-- the hash table happened to be walked in. Without that tiebreak a study would hand
	-- out a different two-tube palette between server restarts, and a player who learned
	-- that the harbour gives you blue and sky would be right two runs in three.
	local byUse: { Pigments.Pigment } = {}
	for _, pigment in Pigments.All do
		if counts[pigment.id] ~= nil then
			table.insert(byUse, pigment)
		end
	end
	table.sort(byUse, function(a: Pigments.Pigment, b: Pigments.Pigment): boolean
		local left = counts[a.id] or 0
		local right = counts[b.id] or 0
		if left ~= right then
			return left > right
		end
		return a.id < b.id
	end)

	if #byUse < 2 then
		error(
			`[AGES content] study "{source.id}" is painted in only one colour, so a cell that is allowed to`
				.. ` move has nothing to move to. Every study needs at least two pigments in it.`
		)
	end

	local study: Study = {
		id = source.id,
		name = source.name,
		cells = cells,
		movable = movable,
		byUse = byUse,
	}
	ALL[#ALL + 1] = study
	byId[source.id] = study
end

if #ALL == 0 then
	-- Reachable only by emptying SOURCE, and worth saying out loud rather than letting
	-- Art refuse at the door with "nothing is up today" every lesson forever.
	error("[AGES content] there are no studies, so Art has nothing to copy. Add one in content/Studies.")
end

-- How many cells a canvas has. Read off the same two Config numbers everything else here
-- is built from, and exported so the service and the room do not each recompute it and
-- then disagree about it by one.
Studies.CellCount = CELLS

Studies.All = ALL

-- Nil for an id nothing authors any more, the same contract Curriculum.Get offers and for
-- the same reason: an id can outlive its content, and the caller that held it is the one
-- that knows what to say about it.
function Studies.Get(id: string): Study?
	return byId[id]
end

return Studies
