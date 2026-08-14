--!strict
-- The jobs that exist. Two, and they are the two ends of the building we already
-- put on the street: the shop floor is on the ground and the office is up the
-- stairs, so the career ladder is a literal staircase the player has to be old
-- enough to climb.
--
-- Salaries are authored yearly and only yearly. What a shift pays and what an
-- hour pays are divided out of this at the point of use, against
-- Config.Work.YearGameHours, so there is exactly one number here to argue about
-- and no second one to fall out of step with it.
--
-- The scale to judge them against is the note above Config.PocketMoney: a whole
-- childhood of allowance comes to somewhere near seven thousand, and that same
-- note puts a teenager doing nothing at about 2,400 a year before their allowance
-- would start out-earning a first job. So a first job pays 2,400 -- worth having,
-- not life-changing -- and adult work pays 8,000, which is the first income in a
-- life that is actually a living.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

-- Content asking content a question. The only thing this wants from People is whether
-- the person a job names as a reference actually exists, and that has to be answered at
-- load: a vouch pointing at nobody is a second route into a job that quietly never opens.
local People = require(script.Parent.People)

type Job = Types.Job

local SOURCE: { Job } = {
	{
		id = "shop_assistant",
		title = "Shop assistant",
		-- The shop floor, downstairs, where the tills and the aisles are.
		placeId = "store",
		-- Sixteen, which is the age this whole system was specified around: the
		-- first year you can trade your time for money instead of being given it.
		minAge = 16,
		yearlySalary = 2400,
		shiftEvents = {
			{ id = "shop_assistant.rude_customer", weight = 3, line = "A customer is complaining about the price. What do you do?", money = -20, happiness = -5 },
			{ id = "shop_assistant.helpful", weight = 4, line = "An elderly customer needs help reaching a shelf. You fetch it for them.", standing = 1, happiness = 3 },
			{ id = "shop_assistant.busy_lunch", weight = 2, line = "The lunch rush hits all at once. You keep your head.", standing = 1, money = 10 },
			{ id = "shop_assistant.found_money", weight = 1, line = "You find a forgotten five-dollar bill under the counter.", money = 5 },
		},
	},
	{
		id = "office_clerk",
		title = "Office clerk",
		-- Upstairs, through the stairwell we measured headroom on.
		placeId = "office",
		minAge = 18,
		yearlySalary = 8000,
		-- The staircase is the career, and this is the handrail. Turning eighteen is
		-- not enough on its own: the office wants to know what the shop floor made of
		-- you, which is the difference between a career and a birthday.
		--
		-- Six is the bottom of "well thought of" -- three or four shifts answered like
		-- someone who cared, or a full year of simply turning up and doing it. Priced
		-- so that a player who worked at sixteen walks up the stairs at eighteen and
		-- finds the door open, and a player who spent two years walking out early
		-- finds it shut and knows exactly why.
		requires = { jobId = "shop_assistant", standing = 6 },
		-- What school was for, and the only place in the game that reads smarts.
		--
		-- Priced off what a childhood actually does to the number. Everyone starts at
		-- 50. Twelve years of sitting lessons and answering most of them puts a child
		-- somewhere near the ceiling; twelve years of never turning up costs two a year
		-- and leaves them in the twenties. Sixty is set just above the line a player
		-- who did nothing could reach by standing still, and well below what anybody who
		-- went at all will have -- five good lessons out of a possible thirty-six clears
		-- it. It is not a wall for the diligent. It is a door that is shut, at eighteen,
		-- for the player who spent their childhood elsewhere, and the game will have
		-- told them the number on the office window for years by then.
		minSmarts = 60,
		-- And the way in that is not a classroom.
		--
		-- Mr. Alderman stands outside the shop the ladder starts at, and this is what
		-- twenty years of being decent to him is worth: he knows the office, and if he
		-- thinks well enough of you he says so. Forty-five is "close" -- roughly a decade
		-- of turning up -- and fifteen brings the bar down to forty-five smarts, which is
		-- a childhood with some school in it rather than none.
		--
		-- Priced so it is a second route and never a shortcut. A player who skipped every
		-- lesson lands in the twenties and is still short even with him vouching, so the
		-- door does not open on friendship alone; a player who went occasionally and knew
		-- their neighbor gets in where either on its own would not have been enough. That
		-- is the whole reason both systems exist in the same childhood.
		vouch = { personId = "neighbor", minBond = 45, worthSmarts = 15 },
		shiftEvents = {
			{ id = "office_clerk.filing_error", weight = 3, line = "You spot a filing error that could cost the company. Do you report it?", standing = 2 },
			{ id = "office_clerk.overwork", weight = 2, line = "The boss piles on extra paperwork at 4pm. You stay late to finish it.", happiness = -5, standing = 1 },
			{ id = "office_clerk.good_report", weight = 2, line = "Your quarterly report impressed the manager.", standing = 2, money = 50 },
			{ id = "office_clerk.paper Jam", weight = 4, line = "The copier jams during a busy morning. You clear it without being asked.", standing = 1 },
		},
	},
	{
		id = "manager",
		title = "Manager",
		-- Same building, different floor. The manager's office is upstairs from
		-- the clerk's, with a door that does not open until the office has had
		-- enough of you to trust you with the rest.
		placeId = "office",
		-- Two years of proving the clerk was not a fluke. Standing 14 is "relied
		-- on" -- four good shifts a year for three years, or two years of simply
		-- turning up and doing it properly.
		minAge = 20,
		-- Double the clerk. The first salary in the game that changes what a life
		-- looks like rather than what a week feels like.
		yearlySalary = 16000,
		-- The standing gate is the real door. Fourteen is the band where the office
		-- knows your name and what you can do. No vouch here: the office has had
		-- two years to make up its mind, and a word from someone outside it does
		-- not carry further than that.
		requires = { jobId = "office_clerk", standing = 14 },
		-- The top of what a childhood with some school in it reaches, and well
		-- below what a childhood full of it produces. The manager has to read a
		-- budget and talk to a client, which is not the same as being clever but
		-- is close enough that the number sits here rather than lower.
		minSmarts = 75,
		shiftEvents = {
			{ id = "manager.team_conflict", weight = 2, line = "Two clerks are arguing over shift coverage. You mediate.", standing = 2, happiness = 2 },
			{ id = "manager.quarterly_review", weight = 1, line = "Quarterly review: the numbers are solid. Your bonus reflects it.", money = 200, standing = 3 },
			{ id = "manager.staff_shortage", weight = 3, line = "Two people called in sick. You cover the floor yourself.", happiness = -5, standing = 1 },
		},
	},
	{
		id = "bakery",
		title = "Baker",
		-- The bread shop down the far street, and the second door a sixteen-year-old
		-- can walk through. Same rung as the shop assistant on purpose: the first
		-- job in a life should be a choice between two rooms, not a single sentence.
		placeId = "bakery",
		minAge = 16,
		-- The same wage as the shop floor, for the same reason: what the first job
		-- teaches is that you are worth something, not what you are worth.
		yearlySalary = 2400,
		shiftEvents = {
			{ id = "bakery.early_start", weight = 3, line = "The oven needs tending at 5am. You're here before dawn.", standing = 1 },
			{ id = "bakery.wasted_flour", weight = 2, line = "A batch of bread went stale. You dispose of it and start fresh.", money = -15 },
			{ id = "bakery.perfect_loaf", weight = 1, line = "The sourdough came out perfect. A customer asks for the recipe.", standing = 2, happiness = 5 },
			{ id = "bakery.busy_morning", weight = 3, line = "The breakfast rush never stops. Your arms ache but the display stays full.", standing = 1, money = 10 },
		},
	},
	{
		id = "librarian",
		title = "Librarian",
		-- The reading room up the far road. The smarts route out of the bakery: it
		-- pays more than the shop's office door for less standing, because the thing
		-- it is really asking for is that school happened.
		placeId = "library",
		minAge = 18,
		yearlySalary = 6000,
		-- Five is "well thought of" -- a single year of turning up at the bakery and
		-- doing the job. The ladder is two years long here rather than the office's
		-- three, because a baker's trade is smaller than a shop floor's and this is
		-- the quiet rung, not the top.
		requires = { jobId = "bakery", standing = 5 },
		-- The line school was always drawing. Fifty-five is a childhood with most
		-- of its lessons in it -- well clear of the twenty-somethings who never went,
		-- and below what a diligent child clears before they are fifteen. A librarian
		-- is not a genius. They are somebody who reads, which is close enough.
		minSmarts = 55,
		shiftEvents = {
			{ id = "librarian.misfiled", weight = 3, line = "A book is misfiled and a patron can't find it. You help locate it.", standing = 1, happiness = 2 },
			{ id = "librarian.quiet_afternoon", weight = 2, line = "A rare quiet afternoon. You get behind on reshelfing.", standing = 1 },
			{ id = "librarian.damaged_book", weight = 1, line = "A patron damaged a reference book. You process the replacement cost.", money = -25 },
			{ id = "librarian.children_hour", weight = 3, line = "Story time with the kids goes well. They ask when you're coming back.", happiness = 5 },
		},
	},
	{
		id = "mechanic",
		title = "Mechanic",
		-- The garage on the far side of the bakery, and the practical route out of
		-- it: the same standing door the librarian walks through, opened instead by
		-- working hands. This is the route that keeps a life whose smarts never
		-- reached the library's bar from ending at sixteen.
		placeId = "garage",
		minAge = 18,
		yearlySalary = 6400,
		requires = { jobId = "bakery", standing = 5 },
		-- Where the practical route lives. Forty-five is a childhood with a bit of
		-- school in it rather than none -- nobody who skipped every lesson for a
		-- decade clears it -- but it is well below the library's bar, because the
		-- garage will take the hands it is offered and train the rest.
		minSmarts = 45,
		-- The ladder man vouches, in a way that rhymes with his own story. Mr.
		-- Alderman's gutter comes away in summer and he holds no ladder steady, but
		-- he knows who keeps this town's cars and its rooflines working, and if he
		-- thinks well enough of you he says so. Worth less than his word to the
		-- office -- fifteen years of seeing you about the street is not the same as
		-- recommending you for the room where the money is -- but it will pull a
		-- player who half-went to school over the garage's lower line.
		vouch = { personId = "neighbor", minBond = 40, worthSmarts = 12 },
		shiftEvents = {
			{ id = "mechanic.tough_job", weight = 3, line = "An oldtimer's car needs more than expected. You talk them through it honestly.", standing = 2, happiness = 3 },
			{ id = "mechanic.parts_delay", weight = 2, line = "The parts order is late. You wait around doing inventory.", happiness = -3 },
			{ id = "mechanic.fix_it_right", weight = 2, line = "You caught a safety issue another shop missed. The customer is grateful.", standing = 2, money = 30 },
			{ id = "mechanic.oily_break", weight = 3, line = "A coffee break with the other mechanic. Good banter.", happiness = 3 },
		},
	},
	{
		id = "gym_instructor",
		title = "Gym instructor",
		-- The gym at the north end, and the only job in the game that is earned as
		-- much in the body as on the record. It sits off the mechanic's rung because
		-- the garage is where this town's physical work already happened; this is
		-- where it starts being paid to happen to other people.
		placeId = "gym",
		minAge = 20,
		yearlySalary = 8000,
		-- Ten is "relied on" -- roughly two good years at the garage. Being asked to
		-- run a room full of people who are hurting on purpose requires having done
		-- that yourself for a while.
		requires = { jobId = "mechanic", standing = 10 },
		-- Below the library's and clinic's bars, because the gym does not need to
		-- read a budget. It needs somebody who knows a movement from a mistake, and
		-- the way this game checks for that is that school happened at all.
		minSmarts = 50,
	},
	{
		id = "clinic_assistant",
		title = "Clinic assistant",
		-- The clinic on the south road. The top of the services row and the care
		-- route: the best-paid job in the game that does not sit upstairs in the
		-- office, and the one that asks the most of a childhood.
		placeId = "clinic",
		minAge = 20,
		yearlySalary = 12000,
		-- Twelve is "relied on" at the library -- two years of being the quiet rung
		-- this ladder is built on. There is no vouch and no shortcut: the clinic
		-- takes the people the library proved it could trust with other people's
		-- information, which is most of what a waiting room is.
		requires = { jobId = "librarian", standing = 12 },
		-- The top of what a childhood produces outside the office. Sixty-five is a
		-- childhood with most of its lessons in it and a library career on top, and
		-- it is the one bar on this row that a player who skipped school simply
		-- cannot reach from the bakery -- which is the point of the row.
		minSmarts = 65,
	},

	-- ------------------------------------------------------------------
	-- City careers.
	--
	-- The five ladders below grow out of the town's two first jobs: the shop
	-- floor's shelf work and a baker's shift are the two things this city
	-- already trusts, so they are the rungs the new rows stand on. The
	-- independent jobs are the city's fresh first rungs -- a sixteen-year-old
	-- should walk a street of open doors, not two sentences -- and they pay
	-- what a first job pays.
	--
	-- Retail ladder: shop floor -> specialist shops -> the market's manager.
	{
		id = "clothing_retail",
		title = "Clothing retail",
		placeId = "clothing_store",
		minAge = 18,
		yearlySalary = 6000,
		-- The same six shifts the shop floor asked for, because the city's
		-- shops are that ladder continuing rather than a fresh one.
		requires = { jobId = "shop_assistant", standing = 6 },
	},
	{
		id = "electronics_retail",
		title = "Electronics retail",
		placeId = "electronics",
		minAge = 18,
		yearlySalary = 6400,
		requires = { jobId = "shop_assistant", standing = 6 },
		-- Selling a thing you have to be able to explain. Fifty-five is the
		-- library's bar: a childhood with most of its lessons in it, which is
		-- what it takes to answer a question about what you are selling.
		minSmarts = 55,
	},
	{
		id = "supermarket_manager",
		title = "Supermarket manager",
		placeId = "supermarket",
		minAge = 20,
		yearlySalary = 16000,
		-- The market is the retail row's office, and it trusts the same way
		-- the office does: fourteen is "relied on", the door a building with a
		-- dozen tills opens to somebody it knows by name.
		requires = { jobId = "clothing_retail", standing = 14 },
		minSmarts = 70,
	},

	-- Food ladder: the bakery and the cafe are both first rungs; the pizza
	-- kitchen and the restaurant floor grow out of them, and the chef is the
	-- top of the row -- the clinic's pay for a kitchen's version of trust.
	{
		id = "barista",
		title = "Barista",
		placeId = "cafe",
		minAge = 18,
		yearlySalary = 6000,
	},
	{
		id = "pizzeria_cook",
		title = "Pizzeria cook",
		placeId = "pizzeria",
		minAge = 18,
		yearlySalary = 6400,
		requires = { jobId = "barista", standing = 5 },
	},
	{
		id = "restaurant_server",
		title = "Restaurant server",
		placeId = "restaurant",
		minAge = 18,
		yearlySalary = 6000,
		-- The bakery teaches what carrying a tray to somebody who is hungry
		-- takes: five shifts, the same door the librarian and the mechanic
		-- walk through off the same rung.
		requires = { jobId = "bakery", standing = 5 },
	},
	{
		id = "chef",
		title = "Chef",
		placeId = "dining_1",
		minAge = 20,
		yearlySalary = 12000,
		requires = { jobId = "pizzeria_cook", standing = 12 },
		-- A kitchen reads a menu, not a budget, so the bar sits with the
		-- librarian's rather than the office's: a childhood with most of its
		-- lessons in it, and a career of cooking on top.
		minSmarts = 55,
	},

	-- Service ladder: the post office sorts, the bank counts, and the hotel
	-- runs the front desk that both of those earn.
	{
		id = "postal_worker",
		title = "Postal worker",
		placeId = "post_office",
		minAge = 18,
		yearlySalary = 6000,
		requires = { jobId = "bakery", standing = 5 },
	},
	{
		id = "bank_teller",
		title = "Bank teller",
		placeId = "bank",
		minAge = 20,
		yearlySalary = 8000,
		requires = { jobId = "postal_worker", standing = 8 },
		-- The bar is here because a teller has to be trusted to add up.
		-- Fifty-five is a childhood with most of its lessons in it.
		minSmarts = 55,
	},
	{
		id = "hotel_receptionist",
		title = "Hotel receptionist",
		placeId = "hotel",
		minAge = 20,
		yearlySalary = 8000,
		requires = { jobId = "bank_teller", standing = 8 },
	},

	-- Health ladder: the pharmacy is the door into care, and the dental
	-- chair and the vet's table both stand on it.
	{
		id = "pharmacy_tech",
		title = "Pharmacy technician",
		placeId = "pharmacy",
		minAge = 18,
		yearlySalary = 6000,
		requires = { jobId = "shop_assistant", standing = 5 },
		-- A shelf you hand medicine off needs to be read properly. Fifty is
		-- the mechanic's bar: a childhood with some school in it rather than
		-- none, because the ones who skipped every lesson must be the ones
		-- who never get the job.
		minSmarts = 50,
	},
	{
		id = "dental_assistant",
		title = "Dental assistant",
		placeId = "dental",
		minAge = 20,
		yearlySalary = 8000,
		requires = { jobId = "pharmacy_tech", standing = 8 },
		minSmarts = 60,
	},
	{
		id = "vet_tech",
		title = "Vet technician",
		placeId = "vet",
		minAge = 20,
		yearlySalary = 8000,
		requires = { jobId = "pharmacy_tech", standing = 8 },
		minSmarts = 55,
	},

	-- Safety ladder: the site and the warehouse are the hands-first route,
	-- and the station and the precinct are where it ends up trusted.
	{
		id = "construction_worker",
		title = "Construction worker",
		placeId = "construction_site",
		minAge = 18,
		yearlySalary = 6400,
		requires = { jobId = "bakery", standing = 5 },
		shiftEvents = {
			{ id = "construction_worker.safety_check", weight = 3, line = "Safety inspector comes through. Everything passes on the first try.", standing = 2 },
			{ id = "construction_worker.bad_weather", weight = 2, line = "Rain delays the pour. You wait it out on the scaffolding.", happiness = -5 },
			{ id = "construction_worker.lift", weight = 2, line = "You helped a coworker lift a heavy beam. Teamwork counts.", standing = 1, happiness = 3 },
			{ id = "construction_worker.early_finish", weight = 1, line = "The wall went up ahead of schedule. Foreman lets you clock out early.", money = 20 },
		},
	},
	{
		id = "warehouse_worker",
		title = "Warehouse worker",
		placeId = "warehouse",
		minAge = 18,
		yearlySalary = 6400,
		requires = { jobId = "construction_worker", standing = 6 },
		shiftEvents = {
			{ id = "warehouse_worker.inv_count", weight = 3, line = "Inventory count is off by a few units. You reconcile it.", standing = 1 },
			{ id = "warehouse_worker.heavy_lift", weight = 2, line = "You moved a pallet that was supposed to be two people. Back aches.", happiness = -3, standing = 1 },
			{ id = "warehouse_worker.found_good", weight = 2, line = "You organized a messy aisle. The team thanks you.", standing = 2, happiness = 3 },
			{ id = "warehouse_worker.scanner_broke", weight = 1, line = "The scanner broke mid-shift. You hand-wrote the logs.", happiness = -5 },
		},
	},
	{
		id = "firefighter",
		title = "Firefighter",
		placeId = "fire_station",
		minAge = 20,
		yearlySalary = 12000,
		requires = { jobId = "warehouse_worker", standing = 10 },
		minSmarts = 60,
	},
	{
		id = "police_officer",
		title = "Police officer",
		placeId = "police_station",
		minAge = 20,
		yearlySalary = 12000,
		requires = { jobId = "warehouse_worker", standing = 10 },
		-- The highest bar on the safety row: a childhood with most of its
		-- lessons in it. Mr. Alderman's word pulls it down but never to the
		-- floor -- fifty-three still needs most of school.
		minSmarts = 65,
		vouch = { personId = "neighbor", minBond = 45, worthSmarts = 12 },
	},

	-- The city's fresh first jobs. Sixteen in the city is a street of open
	-- doors, and these are the doors.
	{
		id = "mall_cashier",
		title = "Mall cashier",
		placeId = "mall_entrance",
		minAge = 16,
		yearlySalary = 2400,
	},
	{
		id = "florist",
		title = "Florist",
		placeId = "florist",
		minAge = 16,
		yearlySalary = 2400,
	},
	{
		id = "bookseller",
		title = "Bookseller",
		placeId = "bookstore",
		minAge = 16,
		yearlySalary = 2400,
	},
	{
		id = "toy_seller",
		title = "Toy seller",
		placeId = "toy_store",
		minAge = 16,
		yearlySalary = 2400,
	},
	{
		id = "music_seller",
		title = "Music seller",
		placeId = "music_store",
		minAge = 16,
		yearlySalary = 2400,
	},
	{
		id = "laundry_worker",
		title = "Laundry worker",
		placeId = "laundromat",
		minAge = 16,
		yearlySalary = 2400,
	},
	{
		id = "gas_attendant",
		title = "Gas station attendant",
		placeId = "gas_station",
		minAge = 16,
		yearlySalary = 2400,
	},
	{
		id = "car_wash_worker",
		title = "Car wash attendant",
		placeId = "car_wash",
		minAge = 16,
		yearlySalary = 2400,
	},
	{
		id = "cinema_usher",
		title = "Cinema usher",
		placeId = "cinema",
		minAge = 16,
		yearlySalary = 2400,
	},
	{
		id = "bowling_attendant",
		title = "Bowling attendant",
		placeId = "bowling",
		minAge = 16,
		yearlySalary = 2400,
	},
	{
		id = "arcade_worker",
		title = "Arcade worker",
		placeId = "arcade",
		minAge = 16,
		yearlySalary = 2400,
	},
	{
		id = "farm_hand",
		title = "Farm hand",
		placeId = "farm",
		minAge = 16,
		yearlySalary = 2400,
	},

	-- The eighteen-year-old trades the city keeps off the ladders: work that
	-- asks for a finished childhood but does not sit on anybody's row.
	{
		id = "barber",
		title = "Barber",
		placeId = "barbershop",
		minAge = 18,
		yearlySalary = 6000,
		-- A trade a childhood with a bit of school in it can reach, and the
		-- one place Mr. Alderman's word reaches into this row: he knows who
		-- keeps a decent pair of scissors, and his say-so pulls the bar down
		-- to thirty -- a childhood with some school in it rather than none.
		minSmarts = 40,
		vouch = { personId = "neighbor", minBond = 35, worthSmarts = 10 },
	},
	{
		id = "hairdresser",
		title = "Hairdresser",
		placeId = "salon",
		minAge = 18,
		yearlySalary = 6000,
	},
	{
		id = "tattoo_artist",
		title = "Tattoo artist",
		placeId = "tattoo_parlor",
		minAge = 18,
		yearlySalary = 6400,
	},
	{
		id = "car_salesperson",
		title = "Car salesperson",
		placeId = "auto_dealer",
		minAge = 18,
		yearlySalary = 8000,
		-- The commission side of the job needs the reading a price list and a
		-- finance sheet take, so the bar sits with the bank's rather than the
		-- barber's: a childhood with most of its lessons in it.
		minSmarts = 55,
	},
	{
		id = "town_clerk",
		title = "Town clerk",
		placeId = "town_hall",
		minAge = 18,
		yearlySalary = 8000,
	},
	{
		id = "referee",
		title = "Sports referee",
		placeId = "soccer_field",
		minAge = 18,
		yearlySalary = 6400,
	},
	-- Work-from-home jobs. Each one is anchored to a suburb house the player can
	-- buy; the placeId is the house id, not a public building. A life must own
	-- the house and link the job before it shows up in the job posts.
	{
		id = "freelance_writer",
		title = "Freelance writer",
		placeId = "suburb_1",
		minAge = 16,
		yearlySalary = 2400,
		minSmarts = 50,
	},
	{
		id = "home_accountant",
		title = "Home accountant",
		placeId = "suburb_5",
		minAge = 18,
		yearlySalary = 6000,
		minSmarts = 60,
	},
	{
		id = "online_teacher",
		title = "Online tutor",
		placeId = "suburb_10",
		minAge = 18,
		yearlySalary = 6000,
		minSmarts = 55,
	},
	{
		id = "remote_coder",
		title = "Remote developer",
		placeId = "suburb_50",
		minAge = 20,
		yearlySalary = 12000,
		minSmarts = 70,
	},
	{
		id = "home_healthcare",
		title = "Home healthcare aid",
		placeId = "suburb_20",
		minAge = 18,
		yearlySalary = 8000,
		minSmarts = 55,
	},
	{
		id = "house_sitter",
		title = "House sitter",
		placeId = "suburb_30",
		minAge = 16,
		yearlySalary = 2400,
		minSmarts = 45,
	},
}

local all: { Job } = {}
local byId: { [string]: Job } = {}

-- Content mistakes are authoring bugs, not runtime conditions, so these throw at
-- start rather than producing a job that quietly pays nothing and is never missed.
local function validate(job: Job)
	if byId[job.id] ~= nil then
		error(`[AGES content] duplicate job id "{job.id}"`)
	end
	if job.title == "" then
		error(`[AGES content] job "{job.id}" has no title; it is what the player is told they do`)
	end
	if job.placeId == "" then
		error(`[AGES content] job "{job.id}" names no place, so there is nowhere to clock on`)
	end
	if job.minAge < 0 then
		error(`[AGES content] job "{job.id}" has a negative minimum age`)
	end

	-- Whole units above zero. A salary of zero is a job that pays nothing, which
	-- is a content mistake rather than a design; a fractional one would be rounded
	-- somewhere downstream and silently stop adding up to the figure authored here.
	if job.yearlySalary <= 0 or job.yearlySalary ~= math.floor(job.yearlySalary) then
		error(`[AGES content] job "{job.id}" pays {job.yearlySalary} a year; a salary must be a whole number above zero`)
	end

	-- A smarts gate has to sit inside the range smarts can actually take, or it is a
	-- door with no key: above the ceiling nobody clears it however hard they worked,
	-- and at or below the floor everybody does and the gate is decoration.
	local minSmarts = job.minSmarts
	if minSmarts ~= nil then
		local stats = Config.Stats
		if minSmarts <= stats.Min or minSmarts > stats.Max then
			error(
				`[AGES content] job "{job.id}" asks for {minSmarts} smarts; it must be above the floor of `
					.. `{stats.Min} and no more than the ceiling of {stats.Max}`
			)
		end
	end

	local vouch = job.vouch
	if vouch ~= nil then
		if People.ById[vouch.personId] == nil then
			error(`[AGES content] job "{job.id}" is vouched for by "{vouch.personId}", who is not a person`)
		end
		-- A vouch with no bar to lower is a field that does nothing, which is worse than
		-- a missing feature: it reads as a route into the job that silently is not one.
		if minSmarts == nil then
			error(`[AGES content] job "{job.id}" has a vouch but asks for no smarts, so there is nothing to lower`)
		end
		local people = Config.People
		if vouch.minBond <= people.MinBond or vouch.minBond > people.MaxBond then
			error(
				`[AGES content] job "{job.id}" wants a bond of {vouch.minBond}, which is either below the `
					.. `floor of {people.MinBond} -- so everybody is vouched for -- or above the ceiling of `
					.. `{people.MaxBond}, so nobody ever is`
			)
		end
		-- Has to move the bar and must not move it to the floor. The first would be a
		-- reference nobody notices; the second a job that could be had on a friendship
		-- and no education at all, which is exactly what the bar is there to prevent.
		if vouch.worthSmarts <= 0 or minSmarts - vouch.worthSmarts <= Config.Stats.Min then
			error(
				`[AGES content] job "{job.id}" values a word from "{vouch.personId}" at {vouch.worthSmarts} `
					.. `smarts against a bar of {minSmarts}; it must be worth something and must leave a bar behind`
			)
		end
	end

	-- The one check that earns its keep. An hour's pay is the salary divided by the
	-- year's game hours, and that division has to come out whole or every hour
	-- worked pays a rounded figure and a full year of work quietly fails to add up
	-- to the salary printed above -- by a few dollars, invisibly, forever.
	if job.yearlySalary % Config.Work.YearGameHours ~= 0 then
		error(
			`[AGES content] job "{job.id}" pays {job.yearlySalary} a year, which does not divide evenly `
				.. `by the {Config.Work.YearGameHours} game hours in a working year; `
				.. `a year of work would not add up to the salary`
		)
	end
end

for _, job in SOURCE do
	validate(job)
	byId[job.id] = job
	table.insert(all, job)
end

-- Prerequisites are checked in a second pass, because a job is allowed to require
-- one declared below it and the first pass has only seen what came before.
local function validateRequirement(job: Job)
	local requirement = job.requires
	if requirement == nil then
		return
	end

	if requirement.jobId == job.id then
		error(`[AGES content] job "{job.id}" requires standing at itself, which cannot be earned without it`)
	end

	local prerequisite = byId[requirement.jobId]
	if prerequisite == nil then
		error(`[AGES content] job "{job.id}" requires "{requirement.jobId}", which is not a job`)
	end

	-- Above the floor, or the requirement is met by everyone who has never worked a
	-- day and the gate is decoration. At or below the ceiling, or it can never be
	-- met by anyone and the job is unreachable -- which at runtime looks exactly
	-- like a door that is simply broken.
	local standing = Config.Work.Standing
	if requirement.standing <= 0 or requirement.standing > standing.Max then
		error(
			`[AGES content] job "{job.id}" requires standing {requirement.standing} at `
				.. `"{requirement.jobId}"; it must be above 0 and no more than the ceiling of {standing.Max}`
		)
	end

	-- A job you can only qualify for by already holding something further up the
	-- ladder is a job nobody can ever reach. Walked rather than checked one deep,
	-- because a three-job loop is just as unreachable and far harder to spot by eye.
	local seen: { [string]: boolean } = { [job.id] = true }
	local step: Job? = prerequisite
	while step ~= nil do
		if seen[step.id] then
			error(`[AGES content] job "{job.id}" sits in a loop of requirements, so nothing in it can ever be taken`)
		end
		seen[step.id] = true
		local nextRequirement = step.requires
		step = if nextRequirement ~= nil then byId[nextRequirement.jobId] else nil
	end
end

local hasEntryPoint = false
for _, job in all do
	validateRequirement(job)
	if job.requires == nil then
		hasEntryPoint = true
	end
end

-- Somewhere there has to be a job that asks nothing of you but your age, or the
-- ladder has no bottom rung and no player can ever start working at all. The one
-- content mistake here that would leave a completely silent game: no errors, no
-- warnings, just a world where clocking on never happens anywhere.
if not hasEntryPoint then
	error("[AGES content] every job requires standing at another one; there is no job anybody could take first")
end

local Jobs = {
	All = all,
	ById = byId,
}

-- What one game hour of this job pays, in whole units. The only place a salary is
-- ever divided, so the arithmetic exists once.
function Jobs.HourlyRate(job: Job): number
	return job.yearlySalary // Config.Work.YearGameHours
end

-- The lowest age at which any job at all can be held. Read off the content rather
-- than written down a second time in Config, so adding a job for a younger worker
-- moves it automatically.
function Jobs.MinimumWorkingAge(): number
	local lowest = math.huge
	for _, job in all do
		lowest = math.min(lowest, job.minAge)
	end
	return lowest
end

return Jobs
