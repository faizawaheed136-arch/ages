--!strict
-- Ages 0-5. Answering one of these ends the year, so a life passes through
-- roughly one per year and the pool has to be deep enough that two lives in a
-- row don't look the same. The early ages are stocked hardest: a 0-1 band has
-- the fewest eligible entries and is therefore the first place repetition shows.
--
-- Delivery is "Wander": the event is not handed over on the birthday, it is put
-- somewhere across the room with its `lure` written over it and a line pointing at
-- it, and crawling to it is what opens it. The writing always assumed a real place
-- — a rug, a hedge, a plate — and this is that place finally existing. Adding an
-- entry needs no code: copy the shape below.
--
--
-- `lure` is not the prompt. It is what the thing says from thirty studs away and
-- from behind, before the player knows what they are walking toward — the reason to
-- go, never the content of what is there. "Something big, and it has seen you", not
-- "A dog wants to be petted".
--
-- The outcomes are still written in the past tense, from before any of this was
-- reachable ("You have liked dogs unconditionally ever since"). That is the next
-- pass and it is content work, not code: the machinery had to be proved first.
--
-- Every entry here is answered by *doing* it rather than by picking off a panel
-- — see the stamp at the bottom of the file, which is why no entry carries a
-- `resolution` field of its own. This is where it earns the most: a toddler is
-- already walking around a room, and a card appearing over that room is the thing
-- that most obviously breaks it.
--
-- An entry whose choices carry an `act` goes further and has no panel at all. Its
-- answers are objects put in the room around the player, and the answering is
-- picking one up, pushing it, walking to it or standing still. A choice `label` on
-- one of those is not a row, it is the words floating over the thing — so it is
-- written as an instruction to a child who cannot read yet being read out by
-- somebody who can, and it is capped by Config.Props.MaxLabelLength rather than the
-- longer panel limit.
--
-- Every entry in this file now carries acts except one. `big_dog` is Enacted and stays
-- that way: its three answers are gestures at an animal that reacts to each of them,
-- so it has a subject to hang dots on and putting a rug in that room would be
-- answering a different event. It is the only entry here with a subject, and that is
-- not a coincidence -- an Enacted event without one has nothing to hang dots on and
-- falls straight back to a panel, which is what the four "vocal" entries were quietly
-- doing until they were converted.
--
-- Converting those four was the whole argument for the layer, because a word is the
-- one answer with nothing to touch. The way through was that a word is always said
-- *to* somebody: which word it was is the part the outcome can tell you, and who you
-- crossed the room to say it at is the part only the player can decide, and they are
-- the same decision. "No" turned out not to need saying at all -- refusing to move,
-- shoving away the one thing you mind, and going out the door with them are the three
-- things a two-year-old means by it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type LifeEvent = Types.LifeEvent

local Childhood: { LifeEvent } = {
	{
		id = "childhood_first_word",
		minAge = 0,
		maxAge = 1,
		delivery = "Wander",
		lure = "The big faces are watching",
		-- A word is said to somebody, so the answer is who you take it to. Which word it
		-- was is the part the outcome can tell you; who you crossed the room to say it
		-- at is the part only the player can decide, and it is the same decision.
		prompt = "Sound is a game. Every noise you make, the big faces lean in and wait to find out what it was for.",
		writesBack = { "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "their_word",
				label = "Say it back to them",
				act = { verb = "Go", at = { prop = "grown_up", distance = 11, offsetDegrees = -60 } },
				outcome = "You said it back. The room went up like you had won something.",
				effects = { smarts = 4, happiness = 3 },
			},
			{
				id = "own_word",
				label = "Make up a word for this",
				act = { verb = "Take", at = { prop = "bright_toy", distance = 10, offsetDegrees = 60 } },
				outcome = "You said a word nobody had taught you, about a thing nobody had named. They laughed for a full minute and you have been chasing that sound ever since.",
				effects = { happiness = 5, smarts = 1 },
			},
			{
				id = "listen",
				label = "Watch their mouths",
				act = { verb = "Stay" },
				outcome = "You stayed quiet for another month. Then you came out with a whole sentence.",
				effects = { smarts = 6, happiness = -1 },
			},
		},
	},
	{
		id = "childhood_across_the_rug",
		minAge = 0,
		maxAge = 1,
		-- The first entry whose answers are objects. The toy is a real distance away
		-- and the rug really slides, so "crawl to it" and "move the floor instead"
		-- are two different journeys rather than two rows that differ by a verb.
		--
		-- The rug is deliberately off to one side rather than between the player and
		-- the toy, even though the writing wants it in the way. A rug on the path is
		-- a rug you shove by accident on your way to the toy, and an event that
		-- answers itself while you are walking somewhere else is the worst failure
		-- this system has: the player did not choose, and has no way of knowing that.
		delivery = "Wander",
		lure = "The room keeps going",
		prompt = "The bright thing is all the way over there. You have never been all the way over there.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "crawl",
				label = "Crawl all the way to it",
				act = { verb = "Go", at = { prop = "bright_toy", distance = 15 } },
				outcome = "You made it the whole way on your own. Your knees were red for an hour and it was worth every inch.",
				effects = { health = 4, happiness = 2 },
			},
			{
				id = "cry",
				-- No prop, so the instruction is written over the player's own head.
				label = "Stay put and cry for it",
				act = { verb = "Stay" },
				outcome = "It arrived in under ten seconds. You filed that information away carefully.",
				effects = { happiness = 3, smarts = 2, health = -1 },
			},
			{
				id = "rug",
				-- Was "study your own hand", which was the clever answer written as
				-- giving up. Same stat shape, and now the clever answer is a thing you
				-- can actually do: you cannot move yourself that far, so move the floor.
				label = "Push the rug across the floor",
				-- 60 degrees off, not 45. At 45 the rug's edge sits 4.9 studs from the
				-- straight line to the toy, inside its own 5-stud reach, so crawling to
				-- the toy would shove it on the way past and answer the wrong choice.
				act = { verb = "Push", at = { prop = "rug", distance = 8, offsetDegrees = 60 } },
				outcome = "You shoved, and the whole floor moved. Nobody had told you the world was allowed to do that, and you spent the rest of the day testing what else was.",
				effects = { smarts = 5 },
			},
		},
	},
	{
		id = "childhood_first_steps",
		minAge = 1,
		maxAge = 2,
		delivery = "Wander",
		lure = "Someone is crouched with their arms out",
		prompt = "You are upright, holding the edge of the couch. Someone is crouched a few feet away with their arms out.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "let_go",
				label = "Let go and walk to them",
				act = { verb = "Go", at = { prop = "grown_up", distance = 12, offsetDegrees = -40 } },
				outcome = "Three steps, then the floor. You got up and did it again before anyone could reach you.",
				effects = { health = 5, happiness = 4 },
			},
			{
				id = "hold_on",
				label = "Edge along the couch",
				act = { verb = "Go", at = { prop = "couch", distance = 10, offsetDegrees = 40 } },
				outcome = "You walked the entire length of the couch without letting go once. Slower, but you never fell.",
				effects = { smarts = 4, health = 1 },
			},
			{
				id = "sit_down",
				label = "Sit down and laugh about it",
				act = { verb = "Stay" },
				outcome = "You sat down hard and found the whole situation hilarious. So did everyone else.",
				effects = { happiness = 5, health = -1 },
			},
		},
	},
	{
		id = "childhood_naming_things",
		minAge = 1,
		maxAge = 3,
		delivery = "Wander",
		lure = "Point at it and they say a word",
		prompt = "You have discovered that everything has a name, and that adults will supply one for anything you point at.",
		writesBack = { "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "point_everything",
				label = "Tip the whole box out",
				-- Pointing at everything is not a thing a room can watch you do. Emptying
				-- the box is: it is the same answer -- name all of it -- made of an act
				-- that has a floor covered in objects at the end of it.
				act = { verb = "Push", at = { prop = "toy_box", distance = 10, offsetDegrees = -60 } },
				outcome = "You spent an entire afternoon pointing. By evening you had thirty new words and one very tired adult.",
				effects = { smarts = 6, happiness = 2 },
			},
			{
				id = "one_thing",
				label = "Stand under the light",
				act = { verb = "Stay", at = { prop = "lamp", distance = 11 } },
				outcome = "It was the ceiling light. You made them say it forty times. You still remember the word.",
				effects = { smarts = 3, happiness = 4 },
			},
			{
				id = "make_up",
				label = "Give this one your own name",
				act = { verb = "Take", at = { prop = "stuffed_dog", distance = 9, offsetDegrees = 60 } },
				outcome = "For a while the dog was called Bo and the moon was called Bo. Your family used your words for years afterward.",
				effects = { happiness = 6, smarts = 1 },
			},
		},
	},
	{
		id = "childhood_sandbox",
		minAge = 2,
		maxAge = 4,
		delivery = "Wander",
		lure = "Another child, and a red shovel",
		prompt = "There is another child in the sandbox. They have a red shovel. You have no shovel.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "ask",
				label = "Ask them to share",
				act = { verb = "Go", at = { prop = "other_child", distance = 11, offsetDegrees = -65 } },
				outcome = "They handed it over without looking up. You dug together until it got dark. That was your first friend.",
				effects = { happiness = 6, smarts = 2 },
			},
			{
				id = "dig_hands",
				label = "Dig with your hands",
				act = { verb = "Stay", at = { prop = "sand_pit", distance = 13 } },
				outcome = "No shovel, no problem. By the end you had a hole deep enough to sit in and they asked to join you.",
				effects = { health = 3, happiness = 3, smarts = 1 },
			},
			{
				id = "watch",
				-- Watching needs somewhere to watch from that is not the sandbox, or the
				-- answer is given by standing in the sandbox not digging -- which is the
				-- other answer, held badly.
				label = "Sit on the wall and watch",
				act = { verb = "Go", at = { prop = "low_wall", distance = 10, offsetDegrees = 70 } },
				outcome = "You watched the whole time and learned exactly how they built it. You tried it yourself the next day and it worked.",
				effects = { smarts = 5, happiness = -2 },
			},
		},
	},
	{
		id = "childhood_end_of_yard",
		minAge = 2,
		maxAge = 5,
		delivery = "Wander",
		lure = "A gap in the hedge",
		prompt = "The yard has a gap in the hedge at the far end. You have never been through it.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts", "flag:wandered_off" },
		choices = {
			{
				id = "go_through",
				label = "Go through the gap",
				act = { verb = "Go", at = { prop = "hedge_gap", distance = 14 } },
				outcome = "It was another yard, almost the same as yours, with a cat in it. You were found twenty minutes later, filthy and delighted.",
				effects = { happiness = 6, health = -2, smarts = 3 },
				sets = { "wandered_off" },
			},
			{
				id = "look_only",
				-- Not "kneel at the gap": the gap is the other answer, and an answer given
				-- inside another answer's reach is a coin flip. Staying is done from here,
				-- which is also what the choice has always actually meant.
				label = "Stay where you are",
				act = { verb = "Stay" },
				outcome = "You stayed on your side of the yard for a long time, working out what was over there. You went through eventually. Just not that day.",
				effects = { smarts = 4, happiness = 1 },
			},
			{
				id = "tell",
				label = "Go and tell a grown-up",
				act = { verb = "Go", at = { prop = "grown_up", distance = 11, offsetDegrees = 75 } },
				outcome = "They came and looked, and said you were right, and held your hand while you went through together.",
				effects = { happiness = 4, health = 2 },
			},
		},
	},
	{
		id = "childhood_storm",
		minAge = 2,
		maxAge = 5,
		delivery = "Wander",
		lure = "The window is loud and white",
		prompt = "The sky cracks open in the middle of the night. The window is loud and white.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "go_to_them",
				label = "Go and find someone",
				act = { verb = "Go", at = { prop = "grown_up", distance = 12, offsetDegrees = -65 } },
				outcome = "They made room without a word. You slept through the rest of it.",
				effects = { happiness = 5, health = 2 },
			},
			{
				id = "watch_it",
				-- Stay rather than Go, because the answer is not reaching the window, it is
				-- being at it long enough to count the gaps.
				label = "Kneel and watch it",
				act = { verb = "Stay", at = { prop = "window", distance = 11 } },
				outcome = "You counted the gaps between the light and the noise. You didn't know why yet, but you knew it meant something.",
				effects = { smarts = 6, happiness = -1 },
			},
			{
				id = "under_covers",
				label = "Get under the covers",
				act = { verb = "Go", at = { prop = "bed", distance = 12, offsetDegrees = 65 } },
				outcome = "You stayed under there until it passed. In the morning it was just a wet yard and you felt a bit silly.",
				effects = { happiness = -2, smarts = 2, health = 1 },
			},
		},
	},
	{
		id = "childhood_last_cookie",
		minAge = 3,
		maxAge = 5,
		delivery = "Wander",
		lure = "One cookie left, and two of you",
		-- Three Carries on one cookie, which is the shape this event always wanted:
		-- what you did with it was never the taking, it was where it ended up. Picking
		-- it up commits to nothing, so a four-year-old can start toward the other child
		-- and change their mind halfway, which is a thing four-year-olds do.
		--
		-- The three destinations are the labels the player actually reads, because the
		-- cookie itself can only say "Pick it up" -- its three meanings are the three
		-- places it can go.
		prompt = "There is one cookie left and two of you looking at it.",
		writesBack = { "stat:happiness", "stat:health", "stat:looks", "stat:smarts" },
		choices = {
			{
				id = "split",
				label = "Put it back and split it",
				act = {
					verb = "Carry",
					at = { prop = "cookie", distance = 8 },
					to = { prop = "plate", distance = 13, offsetDegrees = -55 },
				},
				outcome = "You broke it badly and gave away the bigger piece. Somebody noticed, and mentioned it for years.",
				effects = { happiness = 4, smarts = 2 },
			},
			{
				id = "take",
				label = "Eat it in the corner",
				act = {
					verb = "Carry",
					at = { prop = "cookie", distance = 8 },
					to = { prop = "cushion", distance = 13, offsetDegrees = 55 },
				},
				outcome = "You took it to the corner and ate the whole thing facing the wall. It was a very good cookie and you have thought about it more than you'd like to admit.",
				effects = { happiness = 3, looks = -1, smarts = 1 },
			},
			{
				id = "give",
				label = "Give it to them",
				act = {
					verb = "Carry",
					at = { prop = "cookie", distance = 8 },
					to = { prop = "other_child", distance = 12, offsetDegrees = 150 },
				},
				outcome = "You said you weren't hungry, which was a lie. They remembered, and shared theirs the next time.",
				effects = { happiness = 2, smarts = 3, health = -1 },
			},
		},
	},
	{
		id = "childhood_same_story",
		minAge = 3,
		maxAge = 5,
		delivery = "Wander",
		lure = "The books, and you get to pick",
		-- The most natural Take in the whole band: "you are allowed to pick" already
		-- meant putting a hand on one, and picking it off a list was the only part
		-- that was ever a translation. The two books sit far enough apart that
		-- reaching one is never ambiguously reaching the other.
		prompt = "It is bedtime and you are allowed to pick the story.",
		writesBack = { "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "same_again",
				label = "The same one as last night",
				-- 35 degrees either side rather than 30, for the same reason the rug is at
				-- 60: at 30 a book sits 4.5 studs off the line to the shelf, and reaching
				-- for the shelf would pick a book up on the way.
				act = { verb = "Take", at = { prop = "book_worn", distance = 9, offsetDegrees = -35 } },
				outcome = "The same one. Again. You knew every word and corrected them whenever they tried to skip a page.",
				effects = { happiness = 5, smarts = 2 },
			},
			{
				id = "longest",
				label = "The longest one on the shelf",
				act = { verb = "Take", at = { prop = "book_thick", distance = 9, offsetDegrees = 35 } },
				outcome = "You picked it purely because it would take longest. You were asleep by the fourth page anyway.",
				effects = { smarts = 4, happiness = 2 },
			},
			{
				id = "make_one_up",
				-- Refusing the books has to be as physical as choosing one, or the third
				-- answer is the only one still made of words.
				label = "Push the shelf away instead",
				act = { verb = "Push", at = { prop = "shelf", distance = 12 } },
				outcome = "You shoved the whole shelf away and asked for a new one. They invented it on the spot, about a dog that could drive. It was terrible. You asked for it every night for a month.",
				effects = { happiness = 6, smarts = 3 },
			},
		},
	},
	{
		id = "childhood_mirror",
		minAge = 0,
		maxAge = 1,
		delivery = "Wander",
		lure = "There is another baby in there",
		prompt = "There is another baby in the shiny thing on the wall. They do everything you do, exactly when you do it.",
		writesBack = { "stat:happiness", "stat:smarts" },
		-- The hard one, and the reason it went last. All three answers are aimed at a
		-- single object, and one object can only ever be one answer -- so the third had
		-- to become a second place in the house rather than a second face of the glass.
		-- Which turned out to be truer anyway: a child who believes there is somebody in
		-- there goes looking for the room they are standing in.
		choices = {
			{
				id = "test",
				-- Holding still is a better test than moving, and it is the one a
				-- one-year-old can actually run. They stop when you stop.
				label = "Hold still and see",
				act = { verb = "Stay" },
				outcome = "You held still for as long as you could bear it. So did they. You worked at this for a long time and reached no conclusion you could have explained.",
				effects = { smarts = 5, happiness = 2 },
			},
			{
				id = "greet",
				label = "Get right up to them",
				act = { verb = "Go", at = { prop = "mirror", distance = 11 } },
				outcome = "You got close enough to fog it and shouted. They shouted silently back. You decided you liked them and that was that.",
				effects = { happiness = 5, smarts = 1 },
			},
			{
				id = "behind",
				label = "Round to the other side",
				act = { verb = "Go", at = { prop = "other_side", distance = 12, offsetDegrees = 65 } },
				outcome = "You went around to the other side and found nothing but wall. It was the first time the world had lied to you.",
				effects = { smarts = 6, happiness = -2 },
			},
		},
	},
	{
		id = "childhood_dropped_spoon",
		minAge = 0,
		maxAge = 1,
		delivery = "Wander",
		lure = "The spoon is on the floor again",
		prompt = "Things go away when you push them, and come back when somebody else decides they should. You have a spoon.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "again",
				label = "Send it away again",
				act = { verb = "Push", at = { prop = "spoon", distance = 9, offsetDegrees = -60 } },
				outcome = "Fourteen times. You learned that things go where you send them and that adults bring them back, which is two laws of the universe in one afternoon.",
				effects = { smarts = 6, happiness = 3 },
			},
			{
				id = "watch",
				label = "Watch where it goes",
				act = { verb = "Stay" },
				outcome = "You sent it once and tracked it the whole way, without following. Then you were satisfied.",
				effects = { smarts = 4, health = -1 },
			},
			{
				id = "keep",
				-- The spoon is what the other answer shoves, so holding on has to be
				-- holding something else. The bowl was always the other thing on the tray.
				label = "Hold onto the bowl instead",
				act = { verb = "Take", at = { prop = "bowl", distance = 9, offsetDegrees = 60 } },
				outcome = "You got both hands around the bowl and would not be talked out of it. Nobody saw that bowl again until you were asleep.",
				effects = { happiness = 3, health = 2 },
			},
		},
	},
	{
		id = "childhood_handed_over",
		minAge = 0,
		maxAge = 2,
		delivery = "Wander",
		lure = "A face you do not know",
		prompt = "A face you don't know is leaning in with their arms out, and the person holding you is already letting go.",
		writesBack = { "stat:happiness", "stat:health", "stat:looks", "stat:smarts" },
		choices = {
			{
				id = "go",
				label = "Go to them",
				act = { verb = "Go", at = { prop = "stranger", distance = 10, offsetDegrees = -55 } },
				outcome = "You went. They smelled wrong and sounded kind, and you were fine inside a minute.",
				effects = { happiness = 3, smarts = 2 },
			},
			{
				id = "object",
				label = "Get back to the one you know",
				act = { verb = "Go", at = { prop = "grown_up", distance = 10, offsetDegrees = 55 } },
				outcome = "You were back in familiar arms within seconds and everyone apologized to you, which felt correct.",
				effects = { happiness = 2, smarts = 3, health = -1 },
			},
			{
				id = "stare",
				label = "Stay put and stare",
				act = { verb = "Stay" },
				outcome = "You looked at them without blinking for the whole visit. They brought it up every time they saw you for years.",
				effects = { smarts = 5, looks = -1 },
			},
		},
	},
	{
		id = "childhood_the_word_no",
		minAge = 1,
		maxAge = 3,
		delivery = "Wander",
		lure = "The word that stops them",
		-- "No" is not a word here, it is a body. Refusing to move at all, shoving away
		-- the one thing you actually object to, and going out the door with them are the
		-- three things a two-year-old means by it, and none of them needed saying.
		prompt = "You have learned a word that stops adults where they stand. It has two letters. Today there is a bowl in front of you and a door somebody is holding open.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "everything",
				label = "Refuse everything",
				act = { verb = "Stay" },
				outcome = "You said it to food, baths, shoes and the sun. It worked about a third of the time, which was enough to keep going.",
				effects = { happiness = 4, smarts = 3 },
			},
			{
				id = "sparingly",
				label = "Push away the one you mind",
				act = { verb = "Push", at = { prop = "bowl", distance = 10, offsetDegrees = -60 } },
				outcome = "You used it rarely, and they listened when you did. You have negotiated that way ever since.",
				effects = { smarts = 6, happiness = 1 },
			},
			{
				id = "opposite",
				label = "Say yes and go with them",
				act = { verb = "Go", at = { prop = "front_door", distance = 13, offsetDegrees = 60 } },
				outcome = "You said yes to everything for a week and ended up at a swimming pool, a wedding, and somebody else's birthday party.",
				effects = { happiness = 5, health = 1, smarts = -1 },
			},
		},
	},
	{
		id = "childhood_stairs",
		minAge = 1,
		maxAge = 3,
		delivery = "Wander",
		lure = "The stairs go up",
		prompt = "The stairs go up. You have watched everyone else use them and it looks straightforward enough.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts", "flag:climbed_stairs", "flag:stayed_put" },
		choices = {
			{
				id = "climb",
				label = "Climb them",
				act = { verb = "Go", at = { prop = "stairs", distance = 12, offsetDegrees = -35 } },
				outcome = "You made it four steps before anyone noticed, and the noise they made was far bigger than the situation warranted.",
				effects = { health = 3, happiness = 3, smarts = 1 },
				sets = { "climbed_stairs" },
				clears = { "stayed_put" },
			},
			{
				id = "backward",
				label = "Hold onto the rail",
				act = { verb = "Take", at = { prop = "stair_rail", distance = 10, offsetDegrees = 35 } },
				outcome = "Somebody showed you once and you never did it any other way. It was slow, and you never fell.",
				effects = { smarts = 5, health = 2 },
			},
			{
				id = "hand",
				label = "Wait with one arm up",
				act = { verb = "Stay" },
				outcome = "You stood there with one arm up until somebody took it. It worked every single time, so you kept doing it.",
				effects = { happiness = 3, smarts = 2 },
				sets = { "stayed_put" },
				clears = { "climbed_stairs" },
			},
		},
	},
	{
		id = "childhood_one_toy",
		minAge = 1,
		maxAge = 4,
		delivery = "Wander",
		lure = "It is where you left it",
		prompt = "There is one thing you will not be separated from. It is not the newest or the nicest and it is starting to smell.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		-- Three Carries on one object, the same shape as the cookie and for the same
		-- reason: what you did with it was never the picking up, it was where it ended
		-- up. Here it earns more than it does there, because "you will not be separated
		-- from it" is a sentence that only means anything once the thing is in your arms
		-- and following you around the room.
		choices = {
			{
				id = "everywhere",
				label = "Take it out the front door",
				act = {
					verb = "Carry",
					at = { prop = "worn_toy", distance = 8 },
					to = { prop = "front_door", distance = 14, offsetDegrees = -70 },
				},
				outcome = "It came to the store, the doctor and both sets of grandparents. It lost an eye somewhere along the way and you loved it more.",
				effects = { happiness = 6, health = -1 },
			},
			{
				id = "hide",
				label = "Hide it in the cupboard",
				act = {
					verb = "Carry",
					at = { prop = "worn_toy", distance = 8 },
					to = { prop = "cupboard", distance = 13, offsetDegrees = 70 },
				},
				outcome = "You hid it so well that you lost it for two days. Those were a bad two days for everyone in the house.",
				effects = { smarts = 3, happiness = -2 },
			},
			{
				id = "lend",
				label = "Let them hold it",
				act = {
					verb = "Carry",
					at = { prop = "worn_toy", distance = 8 },
					to = { prop = "other_child", distance = 12, offsetDegrees = 175 },
				},
				outcome = "You handed it over and watched them the entire time. Getting it back was the best part.",
				effects = { happiness = 4, smarts = 2 },
			},
		},
	},
	{
		id = "childhood_hiding",
		minAge = 2,
		maxAge = 4,
		delivery = "Wander",
		lure = "Somebody has started counting",
		prompt = "Somebody is counting. You need somewhere they will never find you.",
		writesBack = { "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "eyes",
				-- The joke lands because the player really does stand in the open doing
				-- nothing while a set of perfectly good hiding places is on either side.
				label = "Cover your eyes",
				act = { verb = "Stay" },
				outcome = "You stood in the middle of the room with both hands over your face and could not be found for a remarkably long time, because they were being kind.",
				effects = { happiness = 6, smarts = -1 },
			},
			{
				id = "curtain",
				label = "Get behind the curtain",
				act = { verb = "Go", at = { prop = "curtain", distance = 11, offsetDegrees = -60 } },
				outcome = "Your feet were in plain view. They walked past you three times announcing they had no idea where you could possibly be.",
				effects = { happiness = 5, smarts = 1 },
			},
			{
				id = "properly",
				label = "Get inside the cupboard",
				act = { verb = "Go", at = { prop = "cupboard", distance = 12, offsetDegrees = 60 } },
				outcome = "You found a spot so good they stopped playing and started calling your name for real. You came out feeling powerful and a little guilty.",
				effects = { smarts = 5, happiness = 2 },
			},
		},
	},
	{
		id = "childhood_big_dog",
		minAge = 2,
		maxAge = 5,
		delivery = "Wander",
		lure = "Something big, and it has seen you",
		-- The first event that is about something rather than merely describing it.
		-- Every clause of the prompt is now checkable against the room: the dog is
		-- there, it really is 2.6 studs at the shoulder against a toddler's 2.3, and
		-- it turns and looks at you. The choices had nothing to point at before this.
		subject = "dog",
		prompt = "There is a dog. It is at least as tall as you are, and it has noticed you.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts", "flag:dog_feared", "flag:dog_loved" },
		-- Reacted, so the dog does the thing the outcome line says it did. Every line
		-- below already described something the animal was up to; until reactions
		-- existed it stood there identically under all three of them, which is a game
		-- telling the player their answer did not matter in the same breath as telling
		-- them it did. This is the event that made reactions necessary.
		choices = {
			{
				id = "hand_out",
				label = "Put your hand out",
				outcome = "It shoved its whole head under your palm and nearly took you off your feet. You have liked dogs unconditionally ever since.",
				effects = { happiness = 6, health = 1 },
				sets = { "dog_loved" },
				clears = { "dog_feared" },
				-- You went to it and it came the rest of the way. The choice the whole
				-- event is built around: you crossed the room to a dog taller than you
				-- are, and it closed the last of the distance itself.
				reaction = "approach",
			},
			{
				id = "freeze",
				label = "Stand completely still",
				outcome = "You held still until it lost interest. You were proud of not running, which is a strange thing to be proud of at three.",
				effects = { smarts = 4, happiness = 1 },
				-- "Until it lost interest" is a thing that happens rather than a thing
				-- that is reported, and it is the whole payoff of the choice: nothing
				-- you did made it leave, it simply stopped caring.
				reaction = "withdraw",
			},
			{
				id = "behind",
				label = "Get behind an adult",
				outcome = "You watched it from behind somebody's leg. By the time you came out it was asleep, which was disappointing.",
				effects = { happiness = -1, smarts = 3 },
				sets = { "dog_feared" },
				clears = { "dog_loved" },
				-- "By the time you came out it was asleep, which was disappointing" is
				-- the joke this event ends on, and it only lands if the animal is
				-- actually lying down when the player looks back at it.
				reaction = "settle",
			},
		},
	},
	{
		id = "childhood_puddle",
		minAge = 2,
		maxAge = 5,
		delivery = "Wander",
		lure = "The whole path is underwater",
		prompt = "A puddle covers the whole path, and you are wearing shoes that were clean this morning.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "jump",
				label = "Straight in, both feet",
				act = { verb = "Go", at = { prop = "puddle", distance = 11 } },
				outcome = "You went in flat-footed and soaked yourself to the waist. Worth it then, and you would do it now.",
				effects = { happiness = 6, health = -2 },
			},
			{
				id = "around",
				label = "Round the edge, stay dry",
				act = { verb = "Go", at = { prop = "dry_path", distance = 11, offsetDegrees = 70 } },
				outcome = "You got around it without a drop on you. You felt extremely sensible and slightly cheated.",
				effects = { smarts = 3, happiness = -1 },
			},
			{
				id = "test",
				-- Given from where the player is standing rather than at the puddle's edge,
				-- because the edge is inside the puddle's own reach and going in is already
				-- the first answer. Working it out first is the decision; going in anyway is
				-- what the outcome is for.
				label = "Stop and work it out",
				act = { verb = "Stay" },
				outcome = "You stood at the edge of it like an engineer, established the depth, and then jumped in anyway.",
				effects = { smarts = 4, happiness = 3, health = -1 },
			},
		},
	},
	{
		id = "childhood_broke_it",
		minAge = 3,
		maxAge = 5,
		delivery = "Wander",
		lure = "It is in two pieces",
		prompt = "It is in two pieces on the floor and nobody saw it happen.",
		writesBack = { "stat:happiness", "stat:smarts", "flag:broke_it_hid_it", "flag:broke_it_owned_up" },
		-- The one event where picking the thing up and not yet knowing where you are
		-- taking it is the whole feeling. A four-year-old holding the evidence, halfway
		-- between the grown-up and the shelf, is the event.
		choices = {
			{
				id = "own_up",
				label = "Take it to them",
				act = {
					verb = "Carry",
					at = { prop = "broken_half", distance = 8 },
					to = { prop = "grown_up", distance = 13, offsetDegrees = -65 },
				},
				outcome = "You told them immediately, in tears. They were considerably less angry than you had budgeted for.",
				effects = { smarts = 5, happiness = 2 },
				sets = { "broke_it_owned_up" },
				clears = { "broke_it_hid_it" },
			},
			{
				id = "repair",
				label = "Put it back on the shelf",
				act = {
					verb = "Carry",
					at = { prop = "broken_half", distance = 8 },
					to = { prop = "shelf", distance = 12, offsetDegrees = 65 },
				},
				outcome = "You balanced the two halves against each other and walked away quickly. It held for about an hour.",
				effects = { smarts = 3, happiness = -2 },
				sets = { "broke_it_hid_it" },
				clears = { "broke_it_owned_up" },
			},
			{
				id = "silence",
				label = "Say nothing",
				act = { verb = "Stay" },
				outcome = "You said nothing and waited. The waiting turned out to be the punishment.",
				effects = { happiness = -4, smarts = 4 },
				sets = { "broke_it_hid_it" },
				clears = { "broke_it_owned_up" },
			},
		},
	},
	{
		id = "childhood_helping",
		minAge = 3,
		maxAge = 5,
		delivery = "Wander",
		lure = "Tools, and nobody is using them",
		prompt = "An adult is doing something with tools, and you have decided that you are helping.",
		writesBack = { "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "hold",
				label = "Take them the flashlight",
				act = {
					verb = "Carry",
					at = { prop = "flashlight", distance = 8 },
					to = { prop = "grown_up", distance = 13, offsetDegrees = -70 },
				},
				outcome = "You held the flashlight, mostly pointing at the wrong thing. They said you were essential and they meant it.",
				effects = { happiness = 5, smarts = 3 },
			},
			{
				id = "parallel",
				label = "Work alongside them",
				act = { verb = "Stay", at = { prop = "workbench", distance = 12, offsetDegrees = 70 } },
				outcome = "You worked on your own project next to theirs for an hour. Neither of you said a word and it was perfect.",
				effects = { smarts = 5, happiness = 3 },
			},
			{
				id = "names",
				-- Asking what everything is called is forty questions; the room can only
				-- watch you ask one. So it is the one you would have asked -- the smallest
				-- thing on the floor, picked up and held out.
				label = "Pick up the one you can't name",
				act = { verb = "Take", at = { prop = "washer", distance = 9, offsetDegrees = 150 } },
				outcome = "You asked forty questions and they answered every one. You still know what a washer is.",
				effects = { smarts = 6, happiness = 1 },
			},
		},
	},
	{
		id = "childhood_why",
		minAge = 3,
		maxAge = 5,
		delivery = "Wander",
		lure = "They are talking about something",
		prompt = "You have found a question that works on absolutely anything, and it is one word long. Somebody is across the room, and so is the thing you were going to ask about.",
		writesBack = { "stat:happiness", "stat:smarts" },
		choices = {
			{
				id = "keep_going",
				label = "Ask them, and keep asking",
				act = { verb = "Go", at = { prop = "grown_up", distance = 12, offsetDegrees = -60 } },
				outcome = "You got to the bottom of it in about nine steps and they admitted they didn't know. That was the day adults got smaller.",
				effects = { smarts = 6, happiness = 1 },
			},
			{
				id = "self_answer",
				-- Going to look at the thing instead of asking about it is what answering
				-- it yourself is, before you have the words for either.
				label = "Work it out yourself",
				act = { verb = "Go", at = { prop = "lamp", distance = 11, offsetDegrees = 60 } },
				outcome = "You began supplying your own answers. They were confident, detailed, and almost entirely wrong.",
				effects = { happiness = 4, smarts = 2 },
			},
			{
				id = "read_the_room",
				label = "Stop, and let them finish",
				act = { verb = "Stay" },
				outcome = "You heard the sigh and stopped. You were reading rooms before you could read words.",
				effects = { smarts = 5, happiness = -1 },
			},
		},
	},
	{
		id = "childhood_first_morning",
		minAge = 4,
		maxAge = 5,
		delivery = "Wander",
		lure = "A room full of children you have never met",
		prompt = "First morning somewhere new, with a room full of children you have never met. Somebody lets go of your hand.",
		writesBack = { "stat:happiness", "stat:health", "stat:smarts" },
		choices = {
			{
				id = "join_in",
				label = "Straight into the middle",
				act = { verb = "Go", at = { prop = "other_child", distance = 12 } },
				outcome = "You were building something with three other children inside a minute. You forgot to say goodbye.",
				effects = { happiness = 6, smarts = 1 },
			},
			{
				id = "corner",
				label = "Find the corner by the window",
				act = { verb = "Go", at = { prop = "window", distance = 13, offsetDegrees = 70 } },
				outcome = "You sat by the window for most of the morning. By the afternoon someone had come to you, which was easier anyway.",
				effects = { smarts = 4, happiness = -1 },
			},
			{
				id = "cry",
				-- Standing exactly where you were left, doing nothing, for as long as it
				-- takes. The one answer in the file where the mechanic is the feeling.
				label = "Stay where they left you",
				act = { verb = "Stay" },
				outcome = "You cried until you ran out, and then you were fine. Nobody held it against you.",
				effects = { happiness = -3, health = 1, smarts = 2 },
			},
		},
	},
}

-- Stamped rather than written on every entry, because it is true of the whole
-- file and always will be: this is the age band the player spends on their feet
-- in one room, and there is no toddler event that would be better as a card.
--
-- Which of the two it gets is read off the entry rather than authored, because it
-- is not a separate decision. Writing an act onto every choice *is* saying the
-- answers are objects, and a second field agreeing with that would only ever be a
-- field that could disagree with it. Left as an override so one entry can still opt
-- out later without unpicking this.
for _, event in Childhood do
	if event.resolution ~= nil then
		continue
	end
	local handled = false
	for _, choice in event.choices do
		if choice.act ~= nil then
			handled = true
			break
		end
	end
	event.resolution = if handled then "Handled" else "Enacted"
end

return Childhood
