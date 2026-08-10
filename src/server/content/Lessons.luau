--!strict
-- What school actually asks you.
--
-- Content, and a table rather than code for the reason JobTasks gives: a lesson is
-- five questions and a childhood is thirty-six lessons, so the thing that has to stay
-- cheap is writing another one. A question is four lines here and never touches the
-- loop that asks it.
--
-- Unlike a shift's tasks, these are not all the same thing in different words. A task
-- is a place to walk to and the words are decoration; a question has a right answer,
-- and it is the only thing in this game a player can be wrong about. Everything else
-- a life event asks you has three answers and three different lives afterwards. This
-- has three answers and one of them is simply correct, which is what makes a lesson
-- something you can be good at.
--
-- What is deliberately *not* here:
--
--   No syllabus, and no subjects. A child in this game is not being taught math and
--   then geography -- they are in a room with a board, being asked things. Sorting
--   these into subjects would buy a menu nobody asked for and would make every gap in
--   the bank look like a missing feature rather than a question not written yet.
--
--   That one is now overturned, and the paragraph above is left standing because the
--   reasoning in it was correct and stopped being correct for a reason worth recording.
--   It holds for exactly as long as every subject is the same act. Sorting one
--   multiple-choice question from another by subject really does buy nothing. Science
--   is no longer a multiple-choice question -- it is a procedure you walk, in a room
--   with benches in it -- and once one subject is a different thing to do with your
--   hands, the others need names to be told apart by. Types.SchoolSubject is the
--   timetable that resulted; content/Curriculum.luau is the list.
--
--   This bank did not become obsolete when that happened. It is what every subject
--   whose verb is not written yet still runs on, and the entries here are no longer
--   the whole of school -- they are the "quiz" verb, which is a placeholder with a
--   design attached and is meant to end up serving nothing.
--
--   No trick questions and no trivia. A question whose answer you either happen to
--   know or do not is a coin toss with extra reading. Every one of these is either
--   something a player can work out from the question, or something worth knowing --
--   and the `because` line means the ones they could not work out are worth getting
--   wrong once.
--
--   Nothing an eight-year-old at a keyboard would find upsetting or would need an
--   adult for. This is a game rated for everyone and school is the part of it most
--   likely to be read over a shoulder.
--
-- The age window on each question is what stops the whole bank being one room. A
-- seven-year-old is asked what half of twenty is and a sixteen-year-old is asked what
-- a deficit is, and a game that asked them the same thing would be admitting the nine
-- years in between did not happen. The bands overlap on purpose -- eleven is a
-- perfectly good age to still be asked how many sides a triangle has, and a hard
-- boundary would make a birthday feel like a different game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LessonQuestion = Types.LessonQuestion

local Lessons = {}

-- Read by the validator and nowhere else. Both come from Config rather than being
-- restated, so the authoring limit and the limit the lesson actually enforces can
-- never drift: a question with five answers in a game that paints four pads is a
-- question with an answer you cannot reach.
local MAX_ANSWERS = Config.School.MaxAnswers
local MAX_ASK = Config.School.MaxAskLength
-- The floor on how many answers a question may offer. Two, because a question with one
-- answer is a sentence with a pad under it.
local MIN_ANSWERS = 2

-- Written as a teacher would say them out loud, because that is the register the
-- `because` line has to hold: it is the one sentence in this system that is neither an
-- instruction nor a score, and it is read by somebody who has just got it wrong.
local SOURCE: { LessonQuestion } = {
	-- The early years. Arithmetic you can do on your fingers, words you have seen
	-- written down, and facts about the world that are true outside the game too.
	{
		id = "add_small",
		ask = "What is 2 + 3?",
		answers = { "4", "5", "6" },
		correct = 2,
		because = "Two, and then three more, makes five.",
		minAge = 6,
		maxAge = 9,
	},
	{
		id = "subtract_small",
		ask = "What is 10 - 4?",
		answers = { "5", "6", "7" },
		correct = 2,
		because = "Take four away from ten and six is left.",
		minAge = 6,
		maxAge = 9,
	},
	{
		id = "triangle_sides",
		ask = "How many sides does a triangle have?",
		answers = { "Three", "Four", "Six" },
		correct = 1,
		because = "Three. That is what the tri in triangle means.",
		minAge = 6,
		maxAge = 10,
	},
	{
		id = "color_mix",
		ask = "Blue and yellow mixed together make what?",
		answers = { "Green", "Purple", "Orange" },
		correct = 1,
		because = "Blue and yellow make green.",
		minAge = 6,
		maxAge = 9,
	},
	{
		id = "days_week",
		ask = "How many days are there in a week?",
		answers = { "Five", "Seven", "Ten" },
		correct = 2,
		because = "Seven, Monday all the way around to Sunday.",
		minAge = 6,
		maxAge = 9,
	},
	{
		id = "months_year",
		ask = "How many months are there in a year?",
		answers = { "Ten", "Twelve", "Twenty" },
		correct = 2,
		because = "Twelve, January through December.",
		minAge = 6,
		maxAge = 9,
	},
	{
		id = "spell_friend",
		ask = "Which of these is spelled correctly?",
		answers = { "freind", "friend", "frend" },
		correct = 2,
		because = "Friend. The i comes before the e.",
		minAge = 6,
		maxAge = 10,
	},
	{
		id = "spider_legs",
		ask = "How many legs does a spider have?",
		answers = { "Six", "Eight", "Ten" },
		correct = 2,
		because = "Eight. Insects have six legs, and a spider is not an insect.",
		minAge = 6,
		maxAge = 10,
	},
	{
		id = "water_cold",
		ask = "What happens to water when it gets very cold?",
		answers = { "It freezes", "It boils", "It disappears" },
		correct = 1,
		because = "It freezes, and turns into ice.",
		minAge = 6,
		maxAge = 9,
	},
	{
		id = "biggest_number",
		ask = "Which of these numbers is the biggest?",
		answers = { "19", "91", "9" },
		correct = 2,
		because = "91. The nine is in the tens column, so it counts for ninety.",
		minAge = 6,
		maxAge = 10,
	},
	{
		id = "sun_direction",
		ask = "Which way does the sun come up in the morning?",
		answers = { "The east", "The west", "The north" },
		correct = 1,
		because = "The sun rises in the east and sets in the west.",
		minAge = 6,
		maxAge = 10,
	},
	{
		id = "money_add",
		ask = "You have $6 and you are given $4. How much do you have?",
		answers = { "$8", "$10", "$12" },
		correct = 2,
		because = "Six and four make ten.",
		minAge = 6,
		maxAge = 9,
	},
	{
		id = "not_animal",
		ask = "Which of these is not an animal?",
		answers = { "A rabbit", "An oak tree", "A sparrow" },
		correct = 2,
		because = "An oak is a tree, and a tree is a plant.",
		minAge = 6,
		maxAge = 9,
	},
	{
		id = "half_twenty",
		ask = "What is half of 20?",
		answers = { "5", "10", "15" },
		correct = 2,
		because = "Twenty split into two equal halves gives ten each.",
		minAge = 6,
		maxAge = 10,
	},
	{
		id = "opposite_heavy",
		ask = "What is the opposite of heavy?",
		answers = { "Light", "Tall", "Loud" },
		correct = 1,
		because = "Light is the opposite of heavy.",
		minAge = 6,
		maxAge = 9,
	},
	{
		id = "baby_cat",
		ask = "What is a baby cat called?",
		answers = { "A kitten", "A puppy", "A cub" },
		correct = 1,
		because = "A kitten. A puppy is a baby dog.",
		minAge = 6,
		maxAge = 9,
	},
	{
		id = "plural_mouse",
		ask = "What do you call more than one mouse?",
		answers = { "Mouses", "Mice", "Mouse" },
		correct = 2,
		because = "Mice. English does not always just add an s.",
		minAge = 6,
		maxAge = 10,
	},
	{
		id = "brush_teeth",
		ask = "Why do you brush your teeth?",
		answers = { "To stop them rotting", "To make them grow", "To make them sharper" },
		correct = 1,
		because = "Brushing takes away what would otherwise rot them.",
		minAge = 6,
		maxAge = 9,
	},

	-- The middle years. Arithmetic with a step in it, and the first questions whose
	-- answer is a thing you were told rather than a thing you can count.
	{
		id = "times_seven_eight",
		ask = "What is 7 x 8?",
		answers = { "54", "56", "64" },
		correct = 2,
		because = "Fifty-six. Seven eights are fifty-six.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "continent",
		ask = "Which of these is a continent?",
		answers = { "Africa", "Egypt", "The Nile" },
		correct = 1,
		because = "Africa is a continent. Egypt is a country in it.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "closest_planet",
		ask = "Which planet is closest to the Sun?",
		answers = { "Earth", "Mercury", "Mars" },
		correct = 2,
		because = "Mercury. It is the innermost of the planets.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "bigger_fraction",
		ask = "Which is bigger, one half or one third?",
		answers = { "One half", "One third", "They are the same" },
		correct = 1,
		because = "Cut a cake in two and your piece is bigger than if you cut it in three.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "which_verb",
		ask = "Which of these words is a verb?",
		answers = { "Quickly", "Running", "Bright" },
		correct = 2,
		because = "A verb is something being done, and running is being done.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "capital_france",
		ask = "What is the capital of France?",
		answers = { "Paris", "Rome", "Madrid" },
		correct = 1,
		because = "Paris. Rome is Italy's and Madrid is Spain's.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "plant_food",
		ask = "What do plants use to make their own food?",
		answers = { "Sunlight", "Moonlight", "Wind" },
		correct = 1,
		because = "Sunlight. The word for it is photosynthesis.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "states_matter",
		ask = "Ice, water and steam are one substance in three what?",
		answers = { "Colors", "States", "Weights" },
		correct = 2,
		because = "States. Solid, liquid and gas are the three states of matter.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "square_perimeter",
		ask = "A square has sides of 4. How far is it all the way around?",
		answers = { "8", "12", "16" },
		correct = 3,
		because = "Four sides of four, so sixteen.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "its_apostrophe",
		ask = "Which sentence is written correctly?",
		answers = { "The dog wagged it's tail", "The dog wagged its tail" },
		correct = 2,
		because = "Its shows belonging. It's is short for it is.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "skeleton",
		ask = "What is your skeleton mostly there to do?",
		answers = { "Hold you up", "Keep you warm", "Digest your food" },
		correct = 1,
		because = "Your bones are the frame the rest of you is built on.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "average_three",
		ask = "What is the average of 4, 6 and 8?",
		answers = { "6", "7", "18" },
		correct = 1,
		because = "They add up to eighteen, and eighteen shared between three is six.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "largest_ocean",
		ask = "Which is the largest ocean?",
		answers = { "The Atlantic", "The Pacific", "The Arctic" },
		correct = 2,
		because = "The Pacific, and by a long way.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "prime_number",
		ask = "Which of these is a prime number?",
		answers = { "9", "15", "17" },
		correct = 3,
		because = "Seventeen. Nothing divides into it but one and itself.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "silent_letter",
		ask = "Which letter is silent in the word knee?",
		answers = { "The k", "The n", "The e" },
		correct = 1,
		because = "The k is written down but never said.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "century",
		ask = "How many years are there in a century?",
		answers = { "Ten", "One hundred", "One thousand" },
		correct = 2,
		because = "A hundred. A thousand years is a millennium.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "lungs",
		ask = "What do your lungs do?",
		answers = { "Take in air", "Pump blood", "Digest food" },
		correct = 1,
		because = "They take the oxygen out of the air you breathe in.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "rectangle_area",
		ask = "A rectangle is 5 across and 3 down. What is its area?",
		answers = { "8", "15", "16" },
		correct = 2,
		because = "Multiply the two sides: five times three is fifteen.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "which_noun",
		ask = "Which of these words is a noun?",
		answers = { "Slowly", "Bridge", "Happily" },
		correct = 2,
		because = "A noun is a thing, and a bridge is a thing.",
		minAge = 9,
		maxAge = 13,
	},

	-- The last years, and the only ones that ask about the life the player is about to
	-- be living. A sixteen-year-old in this game is a week away from a wage, so half of
	-- these are about wages -- which is the closest school here gets to saying what it
	-- is for.
	{
		id = "percent_of",
		ask = "What is 15% of 200?",
		answers = { "15", "30", "45" },
		correct = 2,
		because = "Ten percent is twenty and five percent is ten, so fifteen percent is thirty.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "solve_x",
		ask = "If 3x = 21, what is x?",
		answers = { "6", "7", "8" },
		correct = 2,
		because = "Divide both sides by three and you are left with x = 7.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "supply_demand",
		ask = "Lots of people want something and there is little of it. The price usually does what?",
		answers = { "Goes up", "Goes down", "Stays the same" },
		correct = 1,
		because = "Short supply and high demand push a price up.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "interest_year",
		ask = "You save $100 at 5% a year. How much interest is that in a year?",
		answers = { "$5", "$15", "$50" },
		correct = 1,
		because = "Five percent of a hundred is five.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "plant_gas",
		ask = "Which gas do plants take in to make their food?",
		answers = { "Oxygen", "Carbon dioxide", "Nitrogen" },
		correct = 2,
		because = "They take in carbon dioxide and give out oxygen, which is the other half of breathing.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "metaphor",
		ask = "The city never sleeps. What is that an example of?",
		answers = { "A metaphor", "A statistic", "A rhyme" },
		correct = 1,
		because = "It gives a city a human habit, and that is what a metaphor does.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "deduction",
		ask = "Money taken out of your pay before you get it is called what?",
		answers = { "A deduction", "A bonus", "A refund" },
		correct = 1,
		because = "A deduction. Tax is the one almost everybody has.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "dna",
		ask = "What does DNA mostly carry?",
		answers = { "Instructions", "Blood", "Water" },
		correct = 1,
		because = "The instructions for building and running a living thing.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "moon_drop",
		ask = "Drop a hammer and a feather on the Moon. What happens?",
		answers = { "They land together", "The hammer lands first", "The feather lands first" },
		correct = 1,
		because = "There is no air up there to slow the feather, so gravity pulls both the same.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "deficit",
		ask = "You earn $400 a month and spend $450. What is that called?",
		answers = { "A surplus", "A deficit", "A profit" },
		correct = 2,
		because = "A deficit. Spending more than you take in leaves a hole.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "thesis",
		ask = "What is the thesis of an essay?",
		answers = { "The point it argues for", "Its last line", "Its list of sources" },
		correct = 1,
		because = "It is the claim the rest of the essay exists to back up.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "triangle_angles",
		ask = "The angles inside a triangle add up to how many degrees?",
		answers = { "90", "180", "360" },
		correct = 2,
		because = "Always a hundred and eighty, whatever shape the triangle is.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "resume",
		ask = "What is a resume for?",
		answers = { "Showing an employer what you have done", "Paying your taxes", "Renting a home" },
		correct = 1,
		because = "It is the short account of your work an employer reads before they meet you.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "vote",
		ask = "In a democracy, what does a vote decide?",
		answers = { "Who holds office", "What the weather does", "What things cost" },
		correct = 1,
		because = "Voting is how the people choose who governs them.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "water_made_of",
		ask = "Water is made of hydrogen and what else?",
		answers = { "Oxygen", "Carbon", "Helium" },
		correct = 1,
		because = "Oxygen. H2O is two hydrogen and one oxygen.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "rent",
		ask = "Money paid every month to live somewhere you do not own is called what?",
		answers = { "Rent", "Wages", "A deposit" },
		correct = 1,
		because = "Rent. A deposit is the one-off sum you leave at the start.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "speed",
		ask = "You walk 12 miles in 3 hours. How fast were you going?",
		answers = { "3 miles an hour", "4 miles an hour", "6 miles an hour" },
		correct = 2,
		because = "Twelve miles shared over three hours is four an hour.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "late_payment",
		ask = "You borrow money and pay it back late. What usually happens?",
		answers = { "It costs you more", "It costs you less", "Nothing at all" },
		correct = 1,
		because = "Interest keeps running and charges get added, so late borrowing is expensive borrowing.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "income_tax",
		ask = "Income tax is worked out on what?",
		answers = { "What you earn", "What you own", "Where you live" },
		correct = 1,
		because = "On your earnings. It is a share of what you are paid.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "negative_add",
		ask = "What is -5 + 8?",
		answers = { "3", "-3", "13" },
		correct = 1,
		because = "Count up eight from minus five and you arrive at three.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "evaporation",
		ask = "Wet clothes dry on a line. Where did the water go?",
		answers = { "Into the air", "Into the ground", "Further into the cloth" },
		correct = 1,
		because = "It evaporated into the air, which is where puddles go too.",
		minAge = 13,
		maxAge = 17,
	},

	-- A4 additions: breadth across the three bands, with per-question teacher
	-- reactions on the ones where the gesture matters more than the default bow.

	-- Early (6-9/10): the questions a seven-year-old actually gets asked.
	{
		id = "five_threes",
		ask = "What is 5 groups of 3?",
		answers = { "8", "15", "18" },
		correct = 2,
		because = "Three, six, nine, twelve, fifteen — five threes make fifteen.",
		minAge = 6,
		maxAge = 9,
	},
	{
		id = "coin_quarter",
		ask = "Which coin is worth twenty-five cents?",
		answers = { "Quarter", "Dime", "Nickel" },
		correct = 1,
		because = "A quarter. The name gives it away — a quarter of a dollar.",
		minAge = 6,
		maxAge = 10,
	},
	{
		id = "season_after",
		ask = "Which season comes right after winter?",
		answers = { "Spring", "Summer", "Autumn" },
		correct = 1,
		because = "Spring: the days get longer and things start growing again.",
		minAge = 6,
		maxAge = 8,
	},
	{
		id = "rain_clouds",
		ask = "Where does rain actually come from?",
		answers = { "Clouds", "The ground", "The sun" },
		correct = 1,
		because = "Clouds. Water evaporates, forms clouds, and falls back as rain.",
		minAge = 6,
		maxAge = 9,
	},
	{
		id = "metre_longer",
		ask = "Which is longer: a metre or a foot?",
		answers = { "A metre", "A foot", "They are the same" },
		correct = 1,
		because = "A metre — just over three feet, which is why the metric system caught on.",
		minAge = 6,
		maxAge = 10,
	},
	{
		id = "drawer_push",
		ask = "A wooden drawer is stuck. What do you do?",
		answers = { "Pull it", "Push it", "Kick it" },
		correct = 1,
		because = "Pull it. Drawers open toward you, which is the whole point of a drawer.",
		minAge = 6,
		maxAge = 8,
	},
	{
		id = "carrot_grow",
		ask = "Where do carrots grow?",
		answers = { "In the ground", "On trees", "In water" },
		correct = 1,
		because = "Underground. The orange bit is the root, which is why you have to pull them up.",
		minAge = 6,
		maxAge = 9,
	},
	{
		id = "clock_minutes",
		ask = "How many minutes are in one hour?",
		answers = { "60", "100", "24" },
		correct = 1,
		because = "Sixty. The clock face has twelve fives, and twelve times five is sixty.",
		minAge = 6,
		maxAge = 10,
	},

	-- Middle (9-13): the bridge between arithmetic and the world using it.
	{
		id = "nine_squares",
		ask = "What is 9 x 9?",
		answers = { "72", "81", "89" },
		correct = 2,
		because = "Eighty-one. Nine nines are eighty-one, which is also nine squared.",
		minAge = 9,
		maxAge = 13,
		reaction = "settle",
	},
	{
		id = "quarter_twenty",
		ask = "What is one quarter of 20?",
		answers = { "4", "5", "10" },
		correct = 2,
		because = "Five. A quarter means divide by four, and twenty divided by four is five.",
		minAge = 9,
		maxAge = 13,
		reaction = "settle",
	},
	{
		id = "equal_half",
		ask = "If two people split 1.50 equally, how much does each get?",
		answers = { "75p", "50p", "1.00" },
		correct = 1,
		because = "Seventy-five pence each — half of a pound fifty is seventy-five pence.",
		minAge = 9,
		maxAge = 12,
	},
	{
		id = "theyre_their",
		ask = "Which is correct: 'they are happy' or 'their happy'?",
		answers = { "They are happy", "Their happy", "Neither" },
		correct = 1,
		because = "'They are' contracts to 'they're'. 'Their' belongs to somebody.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "seconds_minute",
		ask = "How many seconds are in three minutes?",
		answers = { "120", "180", "300" },
		correct = 2,
		because = "One hundred and eighty — three times sixty.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "renewable",
		ask = "Which of these is a renewable energy source?",
		answers = { "Coal", "Solar", "Natural gas" },
		correct = 2,
		because = "Solar. The sun is not running out any time soon; fossil fuels are.",
		minAge = 9,
		maxAge = 13,
	},
	{
		id = "map_north",
		ask = "On a map, which direction is typically at the top?",
		answers = { "North", "South", "East" },
		correct = 1,
		because = "North. Maps are conventionally drawn with north at the top.",
		minAge = 9,
		maxAge = 12,
	},

	-- Late (13-17): the questions that use the world they are about to enter.
	{
		id = "extra_hours",
		ask = "You work 2 extra hours at $10 an hour. How much do you earn?",
		answers = { "$20", "$12", "$200" },
		correct = 1,
		because = "Twenty dollars. Two times ten, which is the arithmetic every payslip uses.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "net_pay",
		ask = "Your payslip says $500 gross and $400 net. What is the difference?",
		answers = { "Tax and deductions", "A mistake", "Your bonus" },
		correct = 1,
		because = "Net is what you take home after tax and other deductions come out of the gross.",
		minAge = 13,
		maxAge = 17,
		reaction = "settle",
	},
	{
		id = "quarter_rent",
		ask = "Rent is $800 a month. What do you pay in a quarter?",
		answers = { "$200", "$2,400", "$400" },
		correct = 2,
		because = "Two thousand four hundred — three months at eight hundred each.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "fixed_cost",
		ask = "Which of these is a fixed cost?",
		answers = { "Monthly rent", "Electricity bill", "Groceries" },
		correct = 1,
		because = "Rent stays the same each month. The others change with how much you use.",
		minAge = 13,
		maxAge = 17,
	},
	{
		id = "inflation",
		ask = "Prices rise 3% a year. What happens to your savings?",
		answers = {
			"They buy less over time",
			"They buy more over time",
			"Nothing changes",
		},
		correct = 1,
		because = "Inflation erodes purchasing power — the same money buys fewer things each year.",
		minAge = 14,
		maxAge = 17,
		reaction = "approach",
	},
	{
		id = "compound",
		ask = "You earn 10% interest, then 10% on that. Is the total more than 20%?",
		answers = { "Yes", "No", "It depends on the bank" },
		correct = 1,
		because = "Yes — compound interest earns interest on interest, so it grows faster than simple addition.",
		minAge = 14,
		maxAge = 17,
		reaction = "approach",
	},
	{
		id = "contract",
		ask = "You sign a contract. What does it create?",
		answers = {
			"A legal obligation",
			"A friendly promise",
			"An optional agreement",
		},
		correct = 1,
		because = "A contract is a legally binding agreement — breaking it has consequences a handshake does not.",
		minAge = 14,
		maxAge = 17,
	},
}

-- Content mistakes are authoring bugs, so these throw at start rather than producing a
-- lesson that quietly has a question with two right answers in it. Same reasoning as
-- JobTasks: the symptom of a bad question is not an error, it is a player being marked
-- wrong for being right, and nobody would think to look in a content file for that.
local function validate(question: LessonQuestion, seen: { [string]: true })
	local id = question.id

	if seen[id] then
		error(`[AGES content] two lesson questions are called "{id}"`)
	end
	seen[id] = true

	if question.ask == "" then
		error(`[AGES content] question "{id}" asks nothing`)
	end
	if #question.ask > MAX_ASK then
		error(
			`[AGES content] question "{id}" is {#question.ask} characters, over the {MAX_ASK} a player can read `
				.. `off a HUD row while walking`
		)
	end
	if question.because == "" then
		error(
			`[AGES content] question "{id}" has no explanation; it is the only thing that makes getting this `
				.. `wrong worth anything`
		)
	end

	local answers = question.answers
	if #answers < MIN_ANSWERS or #answers > MAX_ANSWERS then
		error(
			`[AGES content] question "{id}" offers {#answers} answers; it must be from {MIN_ANSWERS} to {MAX_ANSWERS}, `
				.. `because that is how many pads fit on the floor`
		)
	end

	-- Two answers reading the same is the one authoring mistake that cannot be seen by
	-- reading the lesson: the player walks onto a pad saying exactly what they were
	-- asked for and is marked wrong, because it was the other one.
	local written: { [string]: true } = {}
	for index, answer in answers do
		if answer == "" then
			error(`[AGES content] question "{id}" has an answer with nothing written on it`)
		end
		if written[answer] then
			error(`[AGES content] question "{id}" offers "{answer}" twice; only one of them can be the right one`)
		end
		written[answer] = true
		if #answer > Config.Enact.MaxLabelLength then
			error(
				`[AGES content] answer {index} of "{id}" is {#answer} characters, over the `
					.. `{Config.Enact.MaxLabelLength} that fits a panel row without wrapping to three lines`
			)
		end
	end

	if question.correct ~= math.floor(question.correct) or question.correct < 1 or question.correct > #answers then
		error(`[AGES content] question "{id}" says answer {question.correct} is right, and there is no such answer`)
	end

	local school = Config.School
	if question.minAge > question.maxAge then
		error(`[AGES content] question "{id}" is asked from {question.minAge} to {question.maxAge}, which is no ages`)
	end
	if question.minAge < school.StartAge or question.maxAge > school.EndAge then
		error(
			`[AGES content] question "{id}" is asked from {question.minAge} to {question.maxAge}, outside the `
				.. `{school.StartAge}-{school.EndAge} school runs over; it would never be asked`
		)
	end
end

local seen: { [string]: true } = {}
for _, question in SOURCE do
	validate(question, seen)
end

-- The check that actually matters, and the reason the age windows overlap.
--
-- A lesson asks QuestionsPerLesson distinct questions, so an age with fewer than that
-- in the bank silently runs a short lesson -- which grades out of the wrong total and
-- looks, from the outside, like the lesson broke halfway through. Caught here because
-- the alternative is discovering it as an eleven-year-old, once, on somebody's save.
for age = Config.School.StartAge, Config.School.EndAge do
	local available = 0
	for _, question in SOURCE do
		if age >= question.minAge and age <= question.maxAge then
			available += 1
		end
	end
	if available < Config.School.QuestionsPerLesson then
		error(
			`[AGES content] age {age} has only {available} questions written for it and a lesson asks `
				.. `{Config.School.QuestionsPerLesson}; widen an age window or write more`
		)
	end
end

-- The questions a lesson at this age is made of, in the order they are asked.
--
-- Distinct within the lesson and shuffled across it, which are two different needs:
-- distinct because being asked the same thing twice in five minutes is the game
-- forgetting what it just said, and shuffled because the bank is written in age order
-- and a lesson that walked it top-down would ask the easiest five every time.
--
-- Returns fewer than asked for only if the bank is thin, which the check above makes
-- impossible at start -- so the caller can treat a short list as a real lesson rather
-- than as a failure, and grades it out of what it actually got.
function Lessons.For(age: number, count: number): { LessonQuestion }
	local pool: { LessonQuestion } = {}
	for _, question in SOURCE do
		if age >= question.minAge and age <= question.maxAge then
			table.insert(pool, question)
		end
	end

	for index = #pool, 2, -1 do
		local swap = math.random(index)
		pool[index], pool[swap] = pool[swap], pool[index]
	end

	local picked: { LessonQuestion } = {}
	for index = 1, math.min(count, #pool) do
		table.insert(picked, pool[index])
	end
	return picked
end

return Lessons
