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
--   `minigame` is the one deliberate exception to "almost every task is the same
--   mechanic" above, and it is spent on purpose rather than by default: reaching the
--   mark opens a client panel instead of completing the task outright, and the panel
--   is a real, separate thing to build per id. Used on a job's flagship task only --
--   pizzeria_cook's `make` is the worked example -- never as the default shape for a
--   new job, because forty-eight panels would be forty-eight times the cost of this
--   file for a difference most of those jobs' hands would never notice. A job earns
--   one when its real-world verb is something walking to a dot cannot say: stretching
--   dough, timing an oven, not filing a folder.
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
		{
			id = "fetch_bag",
			label = "Fetch and bag the order",
			mark = "Get it",
			handMark = "Bag it",
			-- The corner shop's signature rhythm: the customer has already chosen, the
			-- till is idle, and the only thing between them and their purchase is you
			-- walking the shelf and the bag. Two marks that each say something different
			-- about what your hands are doing — get, then bag — is what makes a corner
			-- shop feel like a place rather than a line of numbers.
			spots = 2,
			seconds = 18,
			customer = "I'll need a bag for those, please.",
			fetchBag = true,
		},
		{
			id = "bag",
			label = "Bag the purchases",
			mark = "Bag them",
			spots = 1,
			seconds = 12,
			-- A single-mark bagging task for when the player is already at the counter.
			-- It exists so the shift is not always asking the player to leave the till,
			-- and so a customer who has been ringing items up can hand them over without
			-- a second walk: the bag is the last step, not the first.
			customer = "All done?",
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

	clothing_retail = {
		{
			id = "fold",
			label = "Fold the arrivals rack",
			mark = "Fold them",
			spots = 1,
			seconds = 14,
		},
		{
			id = "size",
			label = "Find the right size on the shelf",
			mark = "Grab it",
			handMark = "Hand it over",
			spots = 2,
			seconds = 20,
		},
		{
			id = "window",
			label = "Dress the window mannequin",
			mark = "Style it",
			spots = 1,
			seconds = 16,
		},
		{
			id = "till",
			label = "Ring up the purchase",
			mark = "Ring it up",
			spots = 1,
			seconds = 11,
			customer = "Do you have this in medium?",
		},
		{
			id = "rails",
			label = "Straighten the clothing rails",
			mark = "Straighten",
			spots = 1,
			seconds = 13,
		},
		{
			id = "rush",
			label = "Get through the fitting-room queue",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Can I try this on?",
		},
	},

	electronics_retail = {
		{
			id = "stock",
			label = "Restock the display shelves",
			mark = "Restock",
			spots = 1,
			seconds = 14,
		},
		{
			id = "demo",
			label = "Set up the demo unit",
			mark = "Set it up",
			spots = 1,
			seconds = 16,
		},
		{
			id = "backroom",
			label = "Fetch stock from the back room",
			mark = "Fetch it",
			handMark = "Shelve it",
			spots = 2,
			seconds = 22,
		},
		{
			id = "till",
			label = "Ring up the sale",
			mark = "Ring it up",
			spots = 1,
			seconds = 11,
			customer = "Is this the latest model?",
		},
		{
			id = "cables",
			label = "Untangle the cable display",
			mark = "Untangle",
			spots = 1,
			seconds = 13,
		},
		{
			id = "rush",
			label = "Handle the checkout line",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Can I return this?",
		},
	},

	supermarket_manager = {
		{
			id = "aisles",
			label = "Stock the aisle end-caps",
			mark = "Stock them",
			spots = 1,
			seconds = 14,
		},
		{
			id = "inventory",
			label = "Check the cold-storage inventory",
			mark = "Check it",
			spots = 1,
			seconds = 15,
		},
		{
			id = "pallet",
			label = "Unload a delivery pallet",
			mark = "Unload it",
			handMark = "Stack it",
			spots = 2,
			seconds = 22,
		},
		{
			id = "till",
			label = "Cover the express lane",
			mark = "Ring it up",
			spots = 1,
			seconds = 11,
			customer = "Lane five needs help.",
		},
		{
			id = "floor",
			label = "Mop up the spill in aisle three",
			mark = "Mop it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "rush",
			label = "Clear the checkout queue",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "This lane is open!",
		},
	},

	barista = {
		{
			id = "grind",
			label = "Grind the morning beans",
			mark = "Grind",
			spots = 1,
			seconds = 13,
		},
		{
			id = "espresso",
			label = "Pull a set of espressos",
			mark = "Pull them",
			spots = 1,
			seconds = 14,
		},
		{
			id = "pastry",
			label = "Restock the pastry case",
			mark = "Restock",
			spots = 1,
			seconds = 12,
		},
		{
			id = "latte",
			label = "Pour a latte for the customer",
			mark = "Pour it",
			spots = 1,
			seconds = 11,
			customer = "Oat milk, please.",
		},
		{
			id = "dishes",
			label = "Clear the return counter",
			mark = "Clear it",
			spots = 1,
			seconds = 13,
		},
		{
			id = "rush",
			label = "Get through the morning rush",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Large flat white, please.",
		},
	},

	pizzeria_cook = {
		-- The flagship. Stretch, top and bake used to be four separate walk-to-a-mark
		-- tasks that only ever differed by their label -- see the header note above on
		-- why that was the right call for forty-eight other jobs and the wrong one for
		-- the game's own worked example. One mark, one minigame, three timing checks:
		-- see PizzaUI and Config.Work.Minigames.Pizza for the checks themselves.
		{
			id = "make",
			label = "Make the pizza",
			mark = "Make it",
			spots = 1,
			seconds = 25,
			minigame = "pizza",
		},
		{
			id = "prep",
			label = "Prep the vegetable toppings",
			mark = "Chop them",
			spots = 1,
			seconds = 15,
		},
		{
			id = "rush",
			label = "Clear the order rail",
			mark = "Fetch it",
			handMark = "Box it up",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Where's my pepperoni?",
		},
	},

	restaurant_server = {
		{
			id = "tables",
			label = "Set the table for the next seating",
			mark = "Set it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "order",
			label = "Take the order at table four",
			mark = "Write it down",
			spots = 1,
			seconds = 15,
		},
		{
			id = "kitchen",
			label = "Pick up the order from the pass",
			mark = "Pick it up",
			handMark = "Set it down",
			spots = 2,
			seconds = 20,
		},
		{
			id = "drinks",
			label = "Deliver the drinks tray",
			mark = "Deliver",
			spots = 1,
			seconds = 12,
			customer = "Still waiting on those drinks.",
		},
		{
			id = "bus",
			label = "Bus the finished table",
			mark = "Clear it",
			spots = 1,
			seconds = 13,
		},
		{
			id = "rush",
			label = "Get through the dinner rush",
			mark = "Fetch it",
			handMark = "Set it down",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Our food was supposed to be here ten minutes ago.",
		},
	},

	chef = {
		{
			id = "mise",
			label = "Complete the mise en place",
			mark = "Prep it",
			spots = 1,
			seconds = 15,
		},
		{
			id = "sauté",
			label = "Sauté the main course",
			mark = "Cook it",
			spots = 1,
			seconds = 16,
		},
		{
			id = "plate",
			label = "Plate the dish for service",
			mark = "Plate it",
			handMark = "Hand it off",
			spots = 2,
			seconds = 20,
		},
		{
			id = "taste",
			label = "Taste and adjust the seasoning",
			mark = "Taste it",
			spots = 1,
			seconds = 11,
		},
		{
			id = "pantry",
			label = "Rotate the stock in the walk-in",
			mark = "Rotate",
			spots = 1,
			seconds = 14,
		},
		{
			id = "rush",
			label = "Fire the dinner order rush",
			mark = "Fetch it",
			handMark = "Hand it off",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Table seven is still waiting.",
		},
	},

	postal_worker = {
		{
			id = "sort",
			label = "Sort the morning mail",
			mark = "Sort it",
			spots = 1,
			seconds = 15,
		},
		{
			id = "bag",
			label = "Load the delivery bag",
			mark = "Load it",
			spots = 1,
			seconds = 13,
		},
		{
			id = "deliver",
			label = "Deliver to the next address",
			mark = "Deliver",
			handMark = "Drop it off",
			spots = 2,
			seconds = 20,
		},
		{
			id = "signature",
			label = "Collect a signature for the parcel",
			mark = "Get the sign",
			spots = 1,
			seconds = 12,
			customer = "Sign here, please.",
		},
		{
			id = "return",
			label = "Return the misdelivered mail",
			mark = "Return it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "rush",
			label = "Clear the morning sort",
			mark = "Fetch it",
			handMark = "Drop it off",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "I've been waiting all week for that.",
		},
	},

	bank_teller = {
		{
			id = "open",
			label = "Open the vault for the day",
			mark = "Open it",
			spots = 1,
			seconds = 15,
		},
		{
			id = "deposit",
			label = "Process the deposit slip",
			mark = "Process it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "cash",
			label = "Count out the withdrawal",
			mark = "Count it",
			handMark = "Hand it over",
			spots = 2,
			seconds = 20,
		},
		{
			id = "transfer",
			label = "Enter the wire transfer",
			mark = "Enter it",
			spots = 1,
			seconds = 12,
			customer = "The account number is on the slip.",
		},
		{
			id = "balance",
			label = "Reconcile the end-of-day balance",
			mark = "Reconcile",
			spots = 1,
			seconds = 15,
		},
		{
			id = "rush",
			label = "Get through the teller queue",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Next in line, please.",
		},
	},

	hotel_receptionist = {
		{
			id = "checkin",
			label = "Check in the arriving guest",
			mark = "Check in",
			spots = 1,
			seconds = 15,
		},
		{
			id = "keys",
			label = "Prepare the room keys",
			mark = "Cut the keys",
			spots = 1,
			seconds = 12,
		},
		{
			id = "bell",
			label = "Escort the guest to the room",
			mark = "Show the way",
			handMark = "Hand over the key",
			spots = 2,
			seconds = 20,
		},
		{
			id = "phone",
			label = "Answer the ringing front desk phone",
			mark = "Pick up",
			spots = 1,
			seconds = 11,
			customer = "Room service, please.",
		},
		{
			id = "checkout",
			label = "Process the checkout folio",
			mark = "Check out",
			spots = 1,
			seconds = 14,
		},
		{
			id = "rush",
			label = "Handle the check-in rush",
			mark = "Fetch it",
			handMark = "Hand over the key",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "We just arrived — is our room ready?",
		},
	},

	pharmacy_tech = {
		{
			id = "count",
			label = "Count the morning tablet run",
			mark = "Count them",
			spots = 1,
			seconds = 15,
		},
		{
			id = "shelf",
			label = "Restock the prescription shelf",
			mark = "Restock",
			spots = 1,
			seconds = 13,
		},
		{
			id = "fill",
			label = "Fill the prescription bottle",
			mark = "Fill it",
			handMark = "Seal it",
			spots = 2,
			seconds = 20,
		},
		{
			id = "counter",
			label = "Hand the prescription to the customer",
			mark = "Hand it over",
			spots = 1,
			seconds = 11,
			customer = "Is this ready yet?",
		},
		{
			id = "labels",
			label = "Print and stick the labels",
			mark = "Label them",
			spots = 1,
			seconds = 13,
		},
		{
			id = "rush",
			label = "Clear the prescription queue",
			mark = "Fetch it",
			handMark = "Seal it",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "I need my medication before noon.",
		},
	},

	dental_assistant = {
		{
			id = "tray",
			label = "Lay out the dental tray",
			mark = "Set it up",
			spots = 1,
			seconds = 14,
		},
		{
			id = "suction",
			label = "Position the suction line",
			mark = "Position it",
			spots = 1,
			seconds = 12,
		},
		{
			id = "impression",
			label = "Take the dental impression",
			mark = "Take it",
			handMark = "Hand it off",
			spots = 2,
			seconds = 20,
		},
		{
			id = "chart",
			label = "Update the patient chart",
			mark = "Update it",
			spots = 1,
			seconds = 13,
			customer = "Open wide, please.",
		},
		{
			id = "sterilize",
			label = "Sterilize the instruments",
			mark = "Sterilize",
			spots = 1,
			seconds = 15,
		},
		{
			id = "rush",
			label = "Get through the afternoon patients",
			mark = "Fetch it",
			handMark = "Hand it off",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "The dentist is ready for you.",
		},
	},

	vet_tech = {
		{
			id = "exam",
			label = "Prepare the exam room",
			mark = "Set it up",
			spots = 1,
			seconds = 14,
		},
		{
			id = "chart",
			label = "Pull the patient chart",
			mark = "Pull it",
			spots = 1,
			seconds = 12,
		},
		{
			id = "vitals",
			label = "Take the animal's vitals",
			mark = "Check them",
			handMark = "Record them",
			spots = 2,
			seconds = 20,
		},
		{
			id = "meds",
			label = "Draw up the vaccination",
			mark = "Draw it up",
			spots = 1,
			seconds = 13,
			customer = "She's been scratching a lot.",
		},
		{
			id = "cage",
			label = "Clean the recovery cage",
			mark = "Clean it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "rush",
			label = "Handle the walk-in arrivals",
			mark = "Fetch it",
			handMark = "Record them",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "My dog ate something weird.",
		},
	},

	construction_worker = {
		{
			id = "haul",
			label = "Haul lumber to the site",
			mark = "Haul it",
			spots = 1,
			seconds = 15,
		},
		{
			id = "frame",
			label = "Frame the next wall section",
			mark = "Frame it",
			spots = 1,
			seconds = 16,
		},
		{
			id = "measure",
			label = "Measure and mark the cut",
			mark = "Measure it",
			handMark = "Make the cut",
			spots = 2,
			seconds = 20,
		},
		{
			id = "nail",
			label = "Nail the joists into place",
			mark = "Nail them",
			spots = 1,
			seconds = 14,
		},
		{
			id = "debris",
			label = "Clear the construction debris",
			mark = "Clear it",
			spots = 1,
			seconds = 13,
		},
		{
			id = "rush",
			label = "Get the materials to the crew",
			mark = "Fetch it",
			handMark = "Make the cut",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "We're held up without that lumber.",
		},
	},

	warehouse_worker = {
		{
			id = "pick",
			label = "Pick the items from the shelves",
			mark = "Pick them",
			spots = 1,
			seconds = 15,
		},
		{
			id = "wrap",
			label = "Wrap the outgoing shipment",
			mark = "Wrap it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "forklift",
			label = "Move the pallet with the jack",
			mark = "Move it",
			handMark = "Park it",
			spots = 2,
			seconds = 20,
		},
		{
			id = "scan",
			label = "Scan and log the inbound crate",
			mark = "Scan it",
			spots = 1,
			seconds = 12,
			customer = "Truck's here for unload.",
		},
		{
			id = "zone",
			label = "Reorganize the storage zone",
			mark = "Reorganize",
			spots = 1,
			seconds = 15,
		},
		{
			id = "rush",
			label = "Clear the dispatch queue",
			mark = "Fetch it",
			handMark = "Park it",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "That shipment is overdue.",
		},
	},

	firefighter = {
		{
			id = "gear",
			label = "Suit up the engine crew",
			mark = "Gear up",
			spots = 1,
			seconds = 14,
		},
		{
			id = "hose",
			label = "Deploy the hose line",
			mark = "Deploy it",
			spots = 1,
			seconds = 15,
		},
		{
			id = "rescue",
			label = "Carry the dummy to safety",
			mark = "Carry it",
			handMark = "Set it down",
			spots = 2,
			seconds = 22,
		},
		{
			id = "ladder",
			label = "Raise the extension ladder",
			mark = "Raise it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "roll",
			label = "Roll the hose back on the truck",
			mark = "Roll it",
			spots = 1,
			seconds = 13,
		},
		{
			id = "rush",
			label = "Respond to the alarm call",
			mark = "Fetch it",
			handMark = "Set it down",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "There's smoke on the second floor.",
		},
	},

	police_officer = {
		{
			id = "patrol",
			label = "Walk the patrol route",
			mark = "Patrol",
			spots = 1,
			seconds = 16,
		},
		{
			id = "paperwork",
			label = "File the incident report",
			mark = "File it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "radio",
			label = "Respond to the dispatch call",
			mark = "Head out",
			handMark = "Report in",
			spots = 2,
			seconds = 22,
		},
		{
			id = "evidence",
			label = "Bag and log the evidence",
			mark = "Bag it",
			spots = 1,
			seconds = 13,
			customer = "I found this at the scene.",
		},
		{
			id = "desk",
			label = "Man the front desk",
			mark = "Staff it",
			spots = 1,
			seconds = 12,
		},
		{
			id = "rush",
			label = "Clear the holding area",
			mark = "Fetch it",
			handMark = "Report in",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "I need to file a complaint.",
		},
	},

	mall_cashier = {
		{
			id = "scan",
			label = "Scan the items at the till",
			mark = "Scan them",
			spots = 1,
			seconds = 13,
		},
		{
			id = "bag",
			label = "Bag the purchases",
			mark = "Bag them",
			spots = 1,
			seconds = 12,
		},
		{
			id = "restock",
			label = "Restock the impulse-buy rack",
			mark = "Restock",
			spots = 1,
			seconds = 14,
		},
		{
			id = "gift",
			label = "Wrap the gift purchase",
			mark = "Wrap it",
			handMark = "Hand it over",
			spots = 2,
			seconds = 20,
			customer = "Can you wrap this for me?",
		},
		{
			id = "receipt",
			label = "Print and attach the receipt",
			mark = "Print it",
			spots = 1,
			seconds = 11,
		},
		{
			id = "rush",
			label = "Get through the mall queue",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "This line is so long.",
		},
	},

	florist = {
		{
			id = "bouquet",
			label = "Arrange the bouquet",
			mark = "Arrange it",
			spots = 1,
			seconds = 16,
		},
		{
			id = "water",
			label = "Water the display flowers",
			mark = "Water them",
			spots = 1,
			seconds = 13,
		},
		{
			id = "delivery",
			label = "Deliver the order to the door",
			mark = "Deliver it",
			handMark = "Hand it over",
			spots = 2,
			seconds = 20,
		},
		{
			id = "wedding",
			label = "Build the wedding centerpiece",
			mark = "Build it",
			spots = 1,
			seconds = 15,
			customer = "It needs to match the sample.",
		},
		{
			id = "trim",
			label = "Trim the thorny stems",
			mark = "Trim them",
			spots = 1,
			seconds = 13,
		},
		{
			id = "rush",
			label = "Fill the order backlog",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "I ordered these two days ago.",
		},
	},

	bookseller = {
		{
			id = "shelve",
			label = "Shelve the returns",
			mark = "Shelve them",
			spots = 1,
			seconds = 14,
		},
		{
			id = "display",
			label = "Set up the featured display",
			mark = "Set it up",
			spots = 1,
			seconds = 15,
		},
		{
			id = "order",
			label = "Pull the special order from the back",
			mark = "Pull it",
			handMark = "Hand it over",
			spots = 2,
			seconds = 20,
		},
		{
			id = "recommend",
			label = "Recommend a book to the browser",
			mark = "Recommend",
			spots = 1,
			seconds = 12,
			customer = "Something like the last one I bought.",
		},
		{
			id = "inventory",
			label = "Scan the inventory wand",
			mark = "Scan it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "rush",
			label = "Handle the signing queue",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Can you sign my copy?",
		},
	},

	toy_seller = {
		{
			id = "stock",
			label = "Restock the toy shelves",
			mark = "Restock",
			spots = 1,
			seconds = 14,
		},
		{
			id = "demo",
			label = "Demo the new model kit",
			mark = "Demo it",
			spots = 1,
			seconds = 15,
		},
		{
			id = "backroom",
			label = "Fetch the boxed set from the back",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			seconds = 20,
		},
		{
			id = "kid",
			label = "Help the kid find the right toy",
			mark = "Help them",
			spots = 1,
			seconds = 12,
			customer = "Do you have the space rocket?",
		},
		{
			id = "window",
			label = "Set up the window display",
			mark = "Set it up",
			spots = 1,
			seconds = 14,
		},
		{
			id = "rush",
			label = "Clear the checkout line",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Is this one in stock?",
		},
	},

	music_seller = {
		{
			id = "tune",
			label = "Tune the display guitar",
			mark = "Tune it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "demo",
			label = "Demonstrate the keyboard",
			mark = "Play it",
			spots = 1,
			seconds = 15,
		},
		{
			id = "stock",
			label = "Restock the sheet music rack",
			mark = "Restock",
			spots = 1,
			seconds = 13,
		},
		{
			id = "order",
			label = "Pull the special order from the back",
			mark = "Pull it",
			handMark = "Hand it over",
			spots = 2,
			seconds = 20,
			customer = "I ordered the jazz collection.",
		},
		{
			id = "setup",
			label = "Assemble the drum kit display",
			mark = "Assemble it",
			spots = 1,
			seconds = 16,
		},
		{
			id = "rush",
			label = "Handle the sale-day crowd",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Do you price-match?",
		},
	},

	laundry_worker = {
		{
			id = "load",
			label = "Load the industrial washer",
			mark = "Load it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "dry",
			label = "Transfer to the dryer",
			mark = "Transfer",
			spots = 1,
			seconds = 13,
		},
		{
			id = "fold",
			label = "Fold the clean laundry",
			mark = "Fold it",
			handMark = "Stack it",
			spots = 2,
			seconds = 20,
		},
		{
			id = "iron",
			label = "Press the dress shirt",
			mark = "Press it",
			spots = 1,
			seconds = 15,
			customer = "I need this by five.",
		},
		{
			id = "hang",
			label = "Hang the finished garments",
			mark = "Hang them",
			spots = 1,
			seconds = 12,
		},
		{
			id = "rush",
			label = "Clear the pickup counter",
			mark = "Fetch it",
			handMark = "Stack it",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Where's my dry cleaning?",
		},
	},

	gas_attendant = {
		{
			id = "pump",
			label = "Pump the fuel order",
			mark = "Pump it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "windshield",
			label = "Clean the windshield",
			mark = "Clean it",
			spots = 1,
			seconds = 11,
		},
		{
			id = "oil",
			label = "Check the oil level",
			mark = "Check it",
			handMark = "Top it off",
			spots = 2,
			seconds = 18,
		},
		{
			id = "register",
			label = "Ring up the fuel sale",
			mark = "Ring it up",
			spots = 1,
			seconds = 11,
			customer = "Pump three, regular.",
		},
		{
			id = "lot",
			label = "Collect the trolley from the lot",
			mark = "Collect it",
			spots = 1,
			seconds = 13,
		},
		{
			id = "rush",
			label = "Handle the morning fill-ups",
			mark = "Fetch it",
			handMark = "Top it off",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Can you check my tires too?",
		},
	},

	car_wash_worker = {
		{
			id = "prep",
			label = "Prep the car for the wash",
			mark = "Prep it",
			spots = 1,
			seconds = 13,
		},
		{
			id = "soap",
			label = "Apply the foam soap",
			mark = "Soap it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "dry",
			label = "Hand-dry the finish",
			mark = "Dry it",
			handMark = "Buff it",
			spots = 2,
			seconds = 20,
		},
		{
			id = "vacuum",
			label = "Vacuum the interior",
			mark = "Vacuum it",
			spots = 1,
			seconds = 15,
			customer = "Don't forget under the seats.",
		},
		{
			id = "wax",
			label = "Apply the wax coat",
			mark = "Wax it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "rush",
			label = "Get through the queue",
			mark = "Fetch it",
			handMark = "Buff it",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "I'm in a hurry.",
		},
	},

	cinema_usher = {
		{
			id = "tickets",
			label = "Tear the tickets at the door",
			mark = "Tear them",
			spots = 1,
			seconds = 12,
		},
		{
			id = "screen",
			label = "Check the screen room is clean",
			mark = "Check it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "popcorn",
			label = "Scoop the popcorn orders",
			mark = "Scoop it",
			handMark = "Hand it over",
			spots = 2,
			seconds = 18,
		},
		{
			id = "seats",
			label = "Guide guests to their seats",
			mark = "Guide them",
			spots = 1,
			seconds = 11,
			customer = "Where's screen three?",
		},
		{
			id = "clean",
			label = "Clean the auditorium between shows",
			mark = "Clean it",
			spots = 1,
			seconds = 15,
		},
		{
			id = "rush",
			label = "Handle the sold-out crowd",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Is there any seat left?",
		},
	},

	bowling_attendant = {
		{
			id = "lane",
			label = "Set up the lane for the next group",
			mark = "Set it up",
			spots = 1,
			seconds = 14,
		},
		{
			id = "shoes",
			label = "Hand out the bowling shoes",
			mark = "Hand them out",
			spots = 1,
			seconds = 12,
		},
		{
			id = "score",
			label = "Enter the scores on the board",
			mark = "Enter them",
			handMark = "Confirm them",
			spots = 2,
			seconds = 18,
		},
		{
			id = "food",
			label = "Bring the nachos to lane six",
			mark = "Deliver them",
			spots = 1,
			seconds = 11,
			customer = "Can we get some nachos?",
		},
		{
			id = "reset",
			label = "Reset the pins after the frame",
			mark = "Reset them",
			spots = 1,
			seconds = 13,
		},
		{
			id = "rush",
			label = "Handle the league night rush",
			mark = "Fetch it",
			handMark = "Confirm them",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "We need our lane now.",
		},
	},

	arcade_worker = {
		{
			id = "tokens",
			label = "Fill the token machine",
			mark = "Fill it",
			spots = 1,
			seconds = 13,
		},
		{
			id = "fix",
			label = "Fix the jammed claw machine",
			mark = "Fix it",
			spots = 1,
			seconds = 16,
		},
		{
			id = "prizes",
			label = "Restock the prize counter",
			mark = "Restock",
			handMark = "Arrange them",
			spots = 2,
			seconds = 20,
		},
		{
			id = "winner",
			label = "Hand out the prize to the winner",
			mark = "Hand it over",
			spots = 1,
			seconds = 11,
			customer = "I won the big one!",
		},
		{
			id = "floor",
			label = "Wipe down the game screens",
			mark = "Wipe them",
			spots = 1,
			seconds = 13,
		},
		{
			id = "rush",
			label = "Handle the after-school crowd",
			mark = "Fetch it",
			handMark = "Arrange them",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "My tokens ran out already.",
		},
	},

	farm_hand = {
		{
			id = "feed",
			label = "Feed the morning flock",
			mark = "Feed them",
			spots = 1,
			seconds = 15,
		},
		{
			id = "collect",
			label = "Collect the eggs from the coop",
			mark = "Collect them",
			spots = 1,
			seconds = 14,
		},
		{
			id = "barn",
			label = "Muck out the barn stalls",
			mark = "Muck it out",
			handMark = "Haul it away",
			spots = 2,
			seconds = 22,
		},
		{
			id = "hay",
			label = "Stack the hay bales in the loft",
			mark = "Stack them",
			spots = 1,
			seconds = 16,
			customer = "The goats are hungry again.",
		},
		{
			id = "fence",
			label = "Patch the fence along the south field",
			mark = "Patch it",
			spots = 1,
			seconds = 15,
		},
		{
			id = "rush",
			label = "Get through the evening chores",
			mark = "Fetch it",
			handMark = "Haul it away",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "They all want out at once.",
		},
	},

	barber = {
		{
			id = "prep",
			label = "Drape the client and prep the tools",
			mark = "Prep it",
			spots = 1,
			seconds = 13,
		},
		{
			id = "cut",
			label = "Give the client a fresh cut",
			mark = "Cut it",
			spots = 1,
			seconds = 16,
		},
		{
			id = "shave",
			label = "Lather and shave the beard",
			mark = "Shave it",
			handMark = "Towel off",
			spots = 2,
			seconds = 20,
		},
		{
			id = "wash",
			label = "Wash the client's hair",
			mark = "Wash it",
			spots = 1,
			seconds = 12,
			customer = "Short on the sides, please.",
		},
		{
			id = "sweep",
			label = "Sweep the floor between clients",
			mark = "Sweep",
			spots = 1,
			seconds = 12,
		},
		{
			id = "rush",
			label = "Get through the walk-in queue",
			mark = "Fetch it",
			handMark = "Towel off",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "How long is the wait?",
		},
	},

	hairdresser = {
		{
			id = "consult",
			label = "Consult on the new style",
			mark = "Consult",
			spots = 1,
			seconds = 13,
		},
		{
			id = "color",
			label = "Apply the color treatment",
			mark = "Apply it",
			spots = 1,
			seconds = 16,
		},
		{
			id = "blowdry",
			label = "Blow-dry and style the hair",
			mark = "Style it",
			handMark = "Set it",
			spots = 2,
			seconds = 22,
		},
		{
			id = "rinse",
			label = "Rinse the color at the basin",
			mark = "Rinse it",
			spots = 1,
			seconds = 12,
			customer = "I want to go a shade lighter.",
		},
		{
			id = "towels",
			label = "Replace the used towels",
			mark = "Replace them",
			spots = 1,
			seconds = 11,
		},
		{
			id = "rush",
			label = "Handle the Saturday rush",
			mark = "Fetch it",
			handMark = "Set it",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "I have a reservation at three.",
		},
	},

	tattoo_artist = {
		{
			id = "setup",
			label = "Set up the station and inks",
			mark = "Set it up",
			spots = 1,
			seconds = 14,
		},
		{
			id = "stencil",
			label = "Apply the stencil to the skin",
			mark = "Apply it",
			spots = 1,
			seconds = 13,
		},
		{
			id = "ink",
			label = "Trace the outline with the needle",
			mark = "Trace it",
			handMark = "Wipe it",
			spots = 2,
			seconds = 22,
		},
		{
			id = "aftercare",
			label = "Bandage the finished tattoo",
			mark = "Bandage it",
			spots = 1,
			seconds = 11,
			customer = "How long does it take to heal?",
		},
		{
			id = "clean",
			label = "Sterilize the workstation",
			mark = "Sterilize",
			spots = 1,
			seconds = 14,
		},
		{
			id = "rush",
			label = "Get through the walk-in queue",
			mark = "Fetch it",
			handMark = "Wipe it",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Do you have any openings today?",
		},
	},

	car_salesperson = {
		{
			id = "lot",
			label = "Walk the customer around the lot",
			mark = "Show them",
			spots = 1,
			seconds = 16,
		},
		{
			id = "demo",
			label = "Take the car for a test drive",
			mark = "Test-drive",
			spots = 1,
			seconds = 18,
		},
		{
			id = "paperwork",
			label = "Draw up the sales contract",
			mark = "Draw it up",
			handMark = "Hand it over",
			spots = 2,
			seconds = 22,
		},
		{
			id = "trade",
			label = "Appraise the trade-in vehicle",
			mark = "Appraise it",
			spots = 1,
			seconds = 14,
			customer = "What will you give me for my old car?",
		},
		{
			id = "detail",
			label = "Detail the showroom model",
			mark = "Detail it",
			spots = 1,
			seconds = 15,
		},
		{
			id = "rush",
			label = "Handle the end-of-month rush",
			mark = "Fetch it",
			handMark = "Hand it over",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "I need to drive it home today.",
		},
	},

	town_clerk = {
		{
			id = "permit",
			label = "Process the building permit",
			mark = "Process it",
			spots = 1,
			seconds = 15,
		},
		{
			id = "license",
			label = "Issue the business license",
			mark = "Issue it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "file",
			label = "File the records in the archive",
			mark = "File them",
			handMark = "Shelve them",
			spots = 2,
			seconds = 20,
		},
		{
			id = "counter",
			label = "Help the resident at the counter",
			mark = "Help them",
			spots = 1,
			seconds = 12,
			customer = "I need a copy of my birth certificate.",
		},
		{
			id = "mail",
			label = "Sort the incoming mail",
			mark = "Sort it",
			spots = 1,
			seconds = 13,
		},
		{
			id = "rush",
			label = "Clear the morning queue",
			mark = "Fetch it",
			handMark = "Shelve them",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "I've been waiting since eight.",
		},
	},

	referee = {
		{
			id = "inspect",
			label = "Inspect the field before kickoff",
			mark = "Inspect it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "whistle",
			label = "Signal the start of play",
			mark = "Blow it",
			spots = 1,
			seconds = 12,
		},
		{
			id = "foul",
			label = "Call the foul at midfield",
			mark = "Call it",
			handMark = "Mark it down",
			spots = 2,
			seconds = 18,
		},
		{
			id = "card",
			label = "Issue the caution card",
			mark = "Show the card",
			spots = 1,
			seconds = 11,
			customer = "That was a clean tackle!",
		},
		{
			id = "halftime",
			label = "Manage the halftime break",
			mark = "Manage it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "rush",
			label = "Keep up with the fast break",
			mark = "Fetch it",
			handMark = "Mark it down",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Ref, you missed that call!",
		},
	},

	freelance_writer = {
		{
			id = "research",
			label = "Research the article topic",
			mark = "Jot it down",
			spots = 1,
			seconds = 16,
		},
		{
			id = "draft",
			label = "Draft the first version",
			mark = "Type it out",
			spots = 1,
			seconds = 20,
		},
		{
			id = "edit",
			label = "Edit for clarity and tone",
			mark = "Sweep it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "submit",
			label = "Submit the finished piece",
			mark = "Send it",
			handMark = "File it",
			-- Two, not one. A `handMark` is the wording for the *far* mark, so a task
			-- carrying one is by definition a task with two places to stand -- and with
			-- `spots = 1` there was nowhere to put "File it". That is a require-time error
			-- on the boot path, so it did not degrade this one job, it stopped the server.
			-- Raised the spots rather than dropping the handMark because the second wording
			-- is authored content and the two ends say different things; `rush` below pairs
			-- a handMark with 2 the same way.
			spots = 2,
			seconds = 10,
		},
		{
			id = "rush",
			label = "Finish the rush assignment",
			mark = "Dash it",
			handMark = "Mark it down",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "I need this by tomorrow!",
		},
	},

	home_accountant = {
		{
			id = "file_taxes",
			label = "File the quarterly taxes",
			mark = "Stamp it",
			spots = 1,
			seconds = 18,
		},
		{
			id = "reconcile",
			label = "Reconcile the ledger",
			mark = "Tally it",
			spots = 1,
			seconds = 22,
		},
		{
			id = "audit_prep",
			label = "Prepare the audit file",
			mark = "Sort it",
			spots = 1,
			seconds = 16,
		},
		{
			id = "client_call",
			label = "Take the client call",
			mark = "Listen",
			spots = 1,
			seconds = 14,
		},
		{
			id = "rush",
			label = "Rush the end-of-year close",
			mark = "Hurry it",
			handMark = "Mark it down",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "I need my refund fast!",
		},
	},

	online_teacher = {
		{
			id = "prep_lesson",
			label = "Prepare the lesson plan",
			mark = "Write it",
			spots = 1,
			seconds = 18,
		},
		{
			id = "teach",
			label = "Run the online lesson",
			mark = "Teach it",
			spots = 1,
			seconds = 24,
		},
		{
			id = "grade",
			label = "Grade the homework",
			mark = "Mark it",
			spots = 1,
			seconds = 16,
		},
		{
			id = "parent_email",
			label = "Email the parent update",
			mark = "Type it",
			spots = 1,
			seconds = 12,
		},
		{
			id = "rush",
			label = "Rush the makeup session",
			mark = "Run it",
			handMark = "Mark it down",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Can you squeeze me in today?",
		},
	},

	remote_coder = {
		{
			id = "write_code",
			label = "Write the new module",
			mark = "Code it",
			spots = 1,
			seconds = 24,
		},
		{
			id = "review",
			label = "Review a pull request",
			mark = "Scan it",
			spots = 1,
			seconds = 18,
		},
		{
			id = "debug",
			label = "Debug the reported issue",
			mark = "Fix it",
			spots = 1,
			seconds = 20,
		},
		{
			id = "deploy",
			label = "Deploy to staging",
			mark = "Ship it",
			handMark = "Mark it down",
			-- Same defect as "freelance_writer/submit" above, and the only other one in the
			-- file: a far mark with nowhere to put it. "Ship it" and "Mark it down" are two
			-- ends of one task, so the second spot is the point of writing them.
			spots = 2,
			seconds = 12,
		},
		{
			id = "rush",
			label = "Rush the hotfix",
			mark = "Patch it",
			handMark = "Mark it down",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "It's on fire. Please hurry.",
		},
	},

	home_healthcare = {
		{
			id = "check_vitals",
			label = "Check the patient vitals",
			mark = "Record it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "med_reminder",
			label = "Administer the medication reminder",
			mark = "Log it",
			spots = 1,
			seconds = 12,
		},
		{
			id = "log_notes",
			label = "Write the care notes",
			mark = "Note it",
			spots = 1,
			seconds = 16,
		},
		{
			id = "care_plan",
			label = "Update the care plan",
			mark = "Draft it",
			spots = 1,
			seconds = 20,
		},
		{
			id = "rush",
			label = "Rush the urgent visit",
			mark = "Race it",
			handMark = "Mark it down",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "They need help now, please!",
		},
	},

	house_sitter = {
		{
			id = "feed_pet",
			label = "Feed the pets",
			mark = "Serve it",
			spots = 1,
			seconds = 10,
		},
		{
			id = "water_plants",
			label = "Water the plants",
			mark = "Pour it",
			spots = 1,
			seconds = 12,
		},
		{
			id = "collect_mail",
			label = "Collect and sort the mail",
			mark = "Gather it",
			spots = 1,
			seconds = 14,
		},
		{
			id = "security_check",
			label = "Do the security round",
			mark = "Check it",
			spots = 1,
			seconds = 16,
		},
		{
			id = "rush",
			label = "Rush the late-night check",
			mark = "Sweep it",
			handMark = "Mark it down",
			spots = 2,
			rush = 3,
			seconds = 30,
			customer = "Something's not right. Can you come back?",
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
