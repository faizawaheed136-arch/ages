--!strict
-- What you are asked to do while you are on shift.
--
-- Content, and the reason this is a table rather than code: a shift is four real
-- minutes and it needs eight or nine things to happen in it, so the thing that has to
-- be cheap is *writing another one*. Adding a task here is one entry with a sentence
-- and two numbers, and it never touches the loop that runs it.
--
-- Almost every task is the same mechanic -- walk onto the lit marks, in order, before
-- the clock runs out -- and the variety is mostly in the words. That is a deliberate
-- limit, not a first pass. The shop assistant restocking a shelf and the clerk
-- carrying a file to the cabinet are doing exactly the same thing, and dressing them
-- as different systems would cost a lot of code to produce a difference the player's
-- hands cannot feel. What their hands can feel is the difference between one mark and
-- two, and between twelve seconds and twenty.
--
-- The knobs that actually matter per task:
--
--   `spots` is the shape. One mark is "go there and deal with it". Two is "fetch
--   this and bring it back", which is the only thing in this game that makes a
--   workplace feel like it has a layout rather than a spot you stand on.
--
--   `rush` is the one exception to the paragraph above -- the only field that buys a
--   genuinely different shape rather than a different sentence. It is one round trip
--   per person in a queue, back to a counter that does not move, so the thing
--   measuring the player is a line of people getting shorter rather than a bar getting
--   emptier. One per job, on purpose: a shift made entirely of rushes is a shift with
--   no room in it to be somewhere.
--
--   `customer` is who it is for, and it is the one field that changes what a task
--   feels like without changing a single rule of it. A person walks in, stands
--   across the last mark, and looks at you until you get there. Used sparingly on
--   purpose -- see the note on the print run.
--
--   `seconds` is the pressure, and it is per task rather than global because a task
--   with two marks in it plainly needs longer than one with a single mark. As a rule
--   of thumb the walk is a couple of seconds a mark, so these are generous by half --
--   the failure this loop wants is "I got distracted", never "I could not physically
--   get there".
--
-- Nothing here says *where*. The marks are found around wherever the player clocked
-- on, so a job gets tasks the moment it exists, no part in Studio has to be tagged,
-- and no author can accidentally send somebody into a wall in a room they never saw.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type JobTask = Types.JobTask

local JobTasks = {}

-- Read by the validator below and nowhere else. These are sanity bounds on the
-- authoring, not tuning: a task with no marks or no clock is a typo, and the point of
-- catching it here is that the alternative symptom is a shift that quietly stops
-- having anything in it.
local MAX_SPOTS = 3
local MIN_SECONDS = 4
-- Read from Config rather than restated, so the authoring limit and the limit the
-- shift actually enforces can never drift apart: a task authored for five people in a
-- game that seats four is a clock scaled for work the player is never asked to do.
local MAX_QUEUE = Config.Work.Customers.MaxQueue

-- Written in the second person and the present tense, because the HUD shows them
-- while the player is walking and "Restock the shelves" reads as an instruction where
-- "Restocking shelves" reads as a status. The mark under the words is shorter still:
-- it is read at a glance, across a room, past somebody's shoulder.
local SOURCE: { [string]: { JobTask } } = {
	shop_assistant = {
		{
			id = "restock",
			label = "Restock the shelves",
			mark = "Restock",
			spots = 1,
			seconds = 14,
		},
		{
			id = "stockroom",
			label = "Fetch a box from the stockroom",
			mark = "Fetch the box",
			handMark = "Put it away",
			-- Two, and it is the first task in this game with a there-and-back shape.
			-- The second mark is painted only once the first is reached, so the shop
			-- floor stops being a place you stand and becomes a place you cross.
			spots = 2,
			seconds = 22,
		},
		{
			id = "till",
			label = "Serve the customer at the till",
			mark = "Serve",
			-- The tightest clock in the shop, on purpose, and now the only one with a
			-- face attached to it. Being slow here is a thing you can picture because
			-- you can see the person you are being slow to.
			spots = 1,
			seconds = 11,
			customer = "Just these, thanks.",
		},
		{
			id = "sweep",
			label = "Sweep up the aisle",
			mark = "Sweep",
			spots = 1,
			seconds = 15,
		},
		{
			id = "delivery",
			label = "Bring the delivery in and sign for it",
			mark = "Get the box",
			handMark = "Sign for it",
			spots = 2,
			seconds = 24,
			-- Waiting at the *second* mark, which is where a customer always stands: the
			-- one you have to reach to finish. On a two-mark task that means you pick the
			-- box up and carry it to somebody, which is a better shape than being handed
			-- it and walking away -- and it is the reason the two marks are worded in
			-- that order rather than the other one.
			customer = "Delivery — sign here?",
		},
		{
			id = "rush",
			label = "Get through the queue",
			mark = "Fetch it",
			handMark = "Hand it over",
			-- The only task in the shop with a shape of its own rather than a sentence of
			-- its own. Three people are lined up at the counter and each of them wants
			-- something from a different part of the shop, so it is fetch, hand over,
			-- fetch, hand over -- and the queue in front of you gets shorter every time
			-- you make it back.
			--
			-- What it is for is that the other nine tasks are all "go somewhere before a
			-- number runs out", and the player is looking at the number. Here they are
			-- looking at three people, and the number is a thing they can feel without
			-- reading. It is deliberately the only one of its kind in the shop: a shift
			-- made entirely of rushes is a shift with no room in it to be somewhere.
			spots = 2,
			rush = 3,
			-- The tightest clock per thing-done in the game, which is the whole point --
			-- five seconds a leg against the eleven the till gets for one. Still nearly
			-- three times what the walking actually costs, because the failure this wants
			-- is "I lost track", never "I could not physically get there".
			seconds = 30,
			customer = "Three of these, please.",
		},
		{
			id = "display",
			label = "Arrange the window display",
			mark = "Set it up",
			spots = 1,
			seconds = 16,
		},
		{
			id = "register",
			label = "Count the register at close",
			mark = "Count it",
			spots = 1,
			seconds = 18,
		},
		{
			id = "find_item",
			label = "Help a customer find something",
			mark = "Find it",
			handMark = "Bring it back",
			spots = 2,
			seconds = 20,
			customer = "Do you have this in stock?",
		},
	},

	office_clerk = {
		{
			id = "filing",
			label = "File the morning's paperwork",
			mark = "File it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "printer",
			label = "Collect the print run",
			mark = "Collect",
			spots = 1,
			seconds = 12,
			-- Not every task gets a person and this one nearly did not. A colleague
			-- hovering by the printer is the office's version of the queue at the till,
			-- and an office where nobody else works is a strange place to be promoted
			-- into. The rest of the list is deliberately left empty: if every task had
			-- somebody standing over it, having somebody standing over you would stop
			-- meaning anything.
			customer = "Are these mine?",
		},
		{
			id = "courier",
			label = "Take the envelope down to the courier",
			mark = "Get the envelope",
			handMark = "Hand it over",
			spots = 2,
			seconds = 22,
			customer = "For the two o'clock run?",
		},
		{
			id = "post",
			label = "Get the afternoon post out",
			mark = "Fetch it",
			handMark = "Hand it over",
			-- The office's rush, and it is here for the same reason the shop's is: an
			-- office that is only ever quiet is a place, not a job. Three colleagues at
			-- the pigeonholes waiting on you is the one moment in a clerk's shift that
			-- has other people's time in it.
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Anything for me?",
		},
		{
			id = "ledger",
			label = "Check the ledger against yesterday's",
			mark = "Check it",
			-- The longest clock in the game, and the only task whose sentence implies
			-- sitting still. The clock is doing the acting here: an office should feel
			-- slower than a shop floor at the same time as paying three times as much,
			-- which is most of what the ladder is trying to say.
			spots = 1,
			seconds = 20,
		},
		{
			id = "meeting",
			label = "Set the meeting room up",
			mark = "Get the chairs",
			handMark = "Set it up",
			spots = 2,
			seconds = 24,
		},
		{
			id = "mail",
			label = "Sort the incoming mail",
			mark = "Sort it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "slides",
			label = "Prepare the meeting slides",
			mark = "Get the file",
			handMark = "Set it up",
			spots = 2,
			seconds = 22,
		},
		{
			id = "interoffice",
			label = "Deliver interoffice mail",
			mark = "Get the envelope",
			handMark = "Deliver it",
			spots = 2,
			seconds = 20,
			customer = "Thanks, I've been waiting.",
		},
	},

	manager = {
		{
			id = "report",
			label = "Review the weekly report",
			mark = "Review it",
			spots = 1,
			seconds = 18,
		},
		{
			id = "brief",
			label = "Brief the team",
			mark = "Get the brief",
			handMark = "Present it",
			spots = 2,
			seconds = 22,
			customer = "Ready when you are.",
		},
		{
			id = "budget",
			label = "Sign off on the budget",
			mark = "Get the file",
			handMark = "Sign it",
			spots = 2,
			seconds = 24,
		},
	},

	bakery = {
		{
			id = "knead",
			label = "Knead the morning dough",
			mark = "Knead it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "trays",
			label = "Fill the display trays",
			mark = "Fill them",
			spots = 1,
			seconds = 13,
		},
		{
			id = "oven",
			label = "Pull the first batch from the oven",
			mark = "Get the batch",
			handMark = "Set it down",
			spots = 2,
			seconds = 22,
		},
		{
			id = "front",
			label = "Serve a customer at the counter",
			mark = "Serve",
			spots = 1,
			seconds = 11,
			customer = "Two of the round ones, please.",
		},
		{
			id = "flour",
			label = "Sweep the flour off the floor",
			mark = "Sweep",
			spots = 1,
			seconds = 15,
		},
		{
			id = "boxes",
			label = "Box up the afternoon orders",
			mark = "Box them",
			spots = 1,
			seconds = 16,
		},
		{
			id = "rush",
			label = "Get through the morning queue",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "One of each, actually.",
		},
		{
			id = "rise",
			label = "Turn the dough to rise",
			mark = "Turn it",
			spots = 1,
			seconds = 14,
		},
	},

	librarian = {
		{
			id = "shelve",
			label = "Shelve the returns",
			mark = "Shelve them",
			spots = 1,
			seconds = 14,
		},
		{
			id = "stamp",
			label = "Stamp the new arrivals",
			mark = "Stamp them",
			spots = 1,
			seconds = 13,
		},
		{
			id = "cart",
			label = "Fetch the cart from the back",
			mark = "Get the cart",
			handMark = "Bring it out",
			spots = 2,
			seconds = 22,
		},
		{
			id = "request",
			label = "Find a book for a borrower",
			mark = "Find it",
			handMark = "Bring it over",
			spots = 2,
			seconds = 20,
			customer = "It's about trains.",
		},
		{
			id = "put_away",
			label = "Put the reading carts away",
			mark = "Put them away",
			spots = 1,
			seconds = 15,
		},
		{
			id = "rush",
			label = "Get through the return line",
			mark = "Take it",
			handMark = "Scan it",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Just returning these.",
		},
	},

	mechanic = {
		{
			id = "lift",
			label = "Run the car up on the lift",
			mark = "Lift it",
			spots = 1,
			seconds = 15,
		},
		{
			id = "oil",
			label = "Change the oil",
			mark = "Drain it",
			handMark = "Refill it",
			spots = 2,
			seconds = 24,
		},
		{
			id = "tyres",
			label = "Rotate the tyres",
			mark = "Rotate them",
			spots = 1,
			seconds = 16,
		},
		{
			id = "part",
			label = "Fetch the part and fit it",
			mark = "Get the part",
			handMark = "Fit it",
			spots = 2,
			seconds = 22,
			customer = "That the right one?",
		},
		{
			id = "test",
			label = "Test-drive it round the block",
			mark = "Drive it",
			spots = 1,
			seconds = 18,
		},
		{
			id = "rush",
			label = "Get through the bay queue",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "How long's it going to be?",
		},
	},

	gym_instructor = {
		{
			id = "warmup",
			label = "Take the class warm-up",
			mark = "Warm up",
			spots = 1,
			seconds = 14,
		},
		{
			id = "spot",
			label = "Spot someone on the bench",
			mark = "Spot them",
			spots = 1,
			seconds = 13,
			customer = "One more, I've got it.",
		},
		{
			id = "tour",
			label = "Show the new member around",
			mark = "Find them",
			handMark = "Show them",
			spots = 2,
			seconds = 22,
			customer = "First day here.",
		},
		{
			id = "rack",
			label = "Put the racks away",
			mark = "Rack them",
			spots = 1,
			seconds = 15,
		},
		{
			id = "demo",
			label = "Demonstrate the movement",
			mark = "Demo it",
			spots = 1,
			seconds = 12,
		},
		{
			id = "rush",
			label = "Keep the floor covered",
			mark = "Get to it",
			handMark = "Help them",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "How do I use this?",
		},
	},

	clinic_assistant = {
		{
			id = "intake",
			label = "Take the next patient's details",
			mark = "Take them",
			spots = 1,
			seconds = 14,
			customer = "Here for my appointment.",
		},
		{
			id = "room",
			label = "Get the examination room ready",
			mark = "Get the tray",
			handMark = "Set it up",
			spots = 2,
			seconds = 22,
		},
		{
			id = "blood",
			label = "Label the samples",
			mark = "Label them",
			spots = 1,
			seconds = 13,
		},
		{
			id = "bandage",
			label = "Help with the bandaging",
			mark = "Fetch the bandage",
			handMark = "Apply it",
			spots = 2,
			seconds = 24,
			customer = "Gently, please.",
		},
		{
			id = "files",
			label = "Put the files back",
			mark = "File them",
			spots = 1,
			seconds = 14,
		},
		{
			id = "rush",
			label = "Get through the waiting room",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Is it my turn?",
		},
	},
}

-- Content mistakes are authoring bugs, not runtime conditions, so these throw at
-- start rather than producing a shift that quietly has nothing in it. The symptom
-- they prevent is the worst kind: not an error, just a job that is boring, which
-- nobody would think to look in a content file for.
local function validate(jobId: string, task: JobTask, seen: { [string]: true })
	if seen[task.id] then
		error(`[AGES content] job "{jobId}" has two tasks called "{task.id}"`)
	end
	seen[task.id] = true

	if task.label == "" then
		error(`[AGES content] task "{jobId}/{task.id}" has no label; it is the only thing telling the player what to do`)
	end
	if task.mark == "" then
		error(`[AGES content] task "{jobId}/{task.id}" has nothing written on its mark`)
	end
	if task.handMark ~= nil and task.handMark == "" then
		error(
			`[AGES content] task "{jobId}/{task.id}" has an empty far mark; leave the field out `
				.. `and both ends will say "{task.mark}"`
		)
	end
	if task.handMark ~= nil and task.spots < 2 then
		error(`[AGES content] task "{jobId}/{task.id}" has a far mark and only one mark to put it on`)
	end
	if task.spots < 1 or task.spots > MAX_SPOTS or task.spots ~= math.floor(task.spots) then
		error(
			`[AGES content] task "{jobId}/{task.id}" wants {task.spots} marks; it must be a whole number from 1 to {MAX_SPOTS}`
		)
	end
	if task.customer ~= nil and task.customer == "" then
		error(
			`[AGES content] task "{jobId}/{task.id}" brings somebody to wait on it and gives them nothing to say; `
				.. `leave the field out entirely if the task has nobody in it`
		)
	end
	-- A rush is the only field here that changes the shape of a task rather than its
	-- wording, and it only works on top of the other two. Both of these would otherwise
	-- fail quietly and confusingly: a one-mark rush is served by standing still, and a
	-- rush with nobody in it is an ordinary task run three times for no stated reason.
	local rush = task.rush
	if rush ~= nil then
		if rush ~= math.floor(rush) or rush < 2 or rush > MAX_QUEUE then
			error(
				`[AGES content] task "{jobId}/{task.id}" queues {rush} people; it must be a whole number `
					.. `from 2 to {MAX_QUEUE} -- a queue of one is just a task`
			)
		end
		if task.spots ~= 2 then
			error(
				`[AGES content] task "{jobId}/{task.id}" is a rush with {task.spots} mark(s); it needs exactly 2, `
					.. `because a rush is those two alternated once per person`
			)
		end
		if task.customer == nil then
			error(
				`[AGES content] task "{jobId}/{task.id}" is a rush with nobody queueing for it; `
					.. `the line of people is the only thing that makes it read as one`
			)
		end
	end

	if task.seconds < MIN_SECONDS then
		error(
			`[AGES content] task "{jobId}/{task.id}" allows {task.seconds}s, which is under the {MIN_SECONDS}s floor `
				.. `a player needs to cross a room -- a task nobody can finish is a punishment, not a task`
		)
	end
end

for jobId, tasks in SOURCE do
	if #tasks == 0 then
		error(`[AGES content] job "{jobId}" has an empty task list; leave it out entirely instead`)
	end
	local seen: { [string]: true } = {}
	for _, task in tasks do
		validate(jobId, task, seen)
	end
end

-- Every task a job has, or an empty list. Empty is a legitimate answer and not an
-- error: a job with no tasks authored yet still pays, still counts hours and still
-- climbs the ladder -- it simply has nothing to do in it, which is exactly where
-- every job in this game was before this file existed.
function JobTasks.For(jobId: string): { JobTask }
	return SOURCE[jobId] or {}
end

return JobTasks
