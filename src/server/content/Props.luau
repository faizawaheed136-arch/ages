--!strict
-- The things childhood is made of.
--
-- Content data in the same sense as Subjects.luau and Cast.luau: authored
-- descriptions, no code, and adding a rug needs nothing but an entry. What makes
-- this file different from those two is that a prop is not scenery -- it is an
-- answer. An event's choices are these objects, laid out in the room, and the
-- player answers by doing something to one. See Types.ChoiceAct.
--
-- Sized against the childhood body ladder, the way subjects are. At
-- Config.Childhood.Bands a two-year-old is roughly 2.3 studs and a five-year-old
-- roughly 3.4, so a rug seven studs across really is one that "has never seemed so
-- wide" and a cookie at 0.7 really does need both hands. Sizing these against an
-- adult would produce a set of objects that are all technically present and all
-- read as doll's furniture.
--
-- Two colors each and no asset ids, for the reason SubjectModels gives at length:
-- an object that is the right size, in the right place, at the right moment is
-- already most of the event. Being made of oak is the part that can wait. Every one
-- of these is replaceable by a real model later without a line of this file moving
-- -- PropModels adopts anything dropped into the ServerStorage folder under a
-- matching name, exactly as SubjectModels does for the dog.
--
-- `reachStuds` is the one number here that is a game-feel decision rather than a
-- description, and it is authored per prop rather than shared because the right
-- answer genuinely differs: a rug is reached by being partway across it and a
-- cookie is reached by being close enough to have picked it up. Too generous and
-- the player answers by walking past; too tight and they orbit the thing they are
-- plainly trying to touch, which is the worse of the two failures and the one that
-- reads as the game being broken.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type PropKind = Types.PropKind

local list: { PropKind } = {
	-- childhood_across_the_rug ------------------------------------------------

	{
		id = "bright_toy",
		name = "the bright thing",
		shape = "Ball",
		-- Small enough to be a toy and big enough to be visible from the far side of
		-- a room at a toddler's eye height, which is about two studs off the floor.
		size = Vector3.new(0.9, 0.9, 0.9),
		color = Color3.fromRGB(240, 176, 44),
		accentColor = Color3.fromRGB(232, 88, 62),
		reachStuds = 3,
		-- Sat on the floor. Everything in a toddler's world is on the floor.
		liftStuds = 0,
	},
	{
		id = "rug",
		name = "the rug",
		shape = "Block",
		-- The number the prompt is about. Seven studs is three body lengths for the
		-- child crossing it, which is what "a rug that has never seemed so wide"
		-- has to mean for the sentence to survive contact with the room.
		size = Vector3.new(7, 0.08, 5),
		color = Color3.fromRGB(150, 76, 68),
		accentColor = Color3.fromRGB(196, 154, 118),
		-- Reached from well inside it, because pushing a rug is done from on top of
		-- it. A reach that required standing on the edge would make shoving it a
		-- matter of finding one exact stud.
		reachStuds = 5,
		liftStuds = 0,
	},

	-- childhood_last_cookie ---------------------------------------------------

	{
		id = "cookie",
		name = "the last cookie",
		shape = "Cylinder",
		size = Vector3.new(0.7, 0.18, 0.7),
		color = Color3.fromRGB(198, 152, 96),
		accentColor = Color3.fromRGB(96, 62, 38),
		reachStuds = 3,
		-- Off the floor, at the height of the low table it is implicitly on. A
		-- cookie on the carpet is a different and much less tempting object.
		liftStuds = 1.4,
	},
	{
		id = "plate",
		name = "the plate",
		shape = "Cylinder",
		size = Vector3.new(1.7, 0.12, 1.7),
		color = Color3.fromRGB(236, 232, 224),
		accentColor = Color3.fromRGB(180, 176, 168),
		reachStuds = 4,
		liftStuds = 1.4,
	},
	{
		id = "cushion",
		name = "the cushion in the corner",
		shape = "Block",
		size = Vector3.new(1.9, 0.5, 1.9),
		color = Color3.fromRGB(86, 106, 132),
		accentColor = Color3.fromRGB(60, 74, 94),
		reachStuds = 4,
		liftStuds = 0,
	},
	{
		id = "other_child",
		name = "the other child",
		shape = "Figure",
		-- Deliberately the same height as the player is at the ages this can fire.
		-- The event is about two people with an equal claim, and a child you look
		-- down at is a child you would simply take it from.
		size = Vector3.new(1.1, 2.4, 0.7),
		color = Color3.fromRGB(108, 140, 196),
		accentColor = Color3.fromRGB(226, 188, 160),
		reachStuds = 4,
		liftStuds = 0,
	},

	-- childhood_same_story ----------------------------------------------------

	{
		id = "book_worn",
		name = "the one you always have",
		shape = "Block",
		size = Vector3.new(0.9, 0.2, 1.2),
		-- Faded, and the accent is the only bright thing left on it. This is the
		-- book that has been read four hundred times and it should look it.
		color = Color3.fromRGB(178, 158, 132),
		accentColor = Color3.fromRGB(206, 118, 92),
		reachStuds = 3,
		liftStuds = 0,
	},
	{
		id = "book_thick",
		name = "the longest one",
		shape = "Block",
		-- The only thing that distinguishes it in the prompt is that it is the
		-- biggest, so it has to actually be the biggest object in the set.
		size = Vector3.new(1.1, 0.55, 1.4),
		color = Color3.fromRGB(58, 78, 120),
		accentColor = Color3.fromRGB(212, 186, 108),
		reachStuds = 3,
		liftStuds = 0,
	},
	{
		id = "shelf",
		name = "the shelf",
		shape = "Block",
		size = Vector3.new(3.4, 0.3, 0.9),
		color = Color3.fromRGB(122, 96, 70),
		accentColor = Color3.fromRGB(88, 68, 50),
		reachStuds = 4,
		liftStuds = 0,
	},

	-- People ------------------------------------------------------------------
	--
	-- Not subjects. A subject is what an event is *about* and gets a rig, a gait and
	-- a reaction to how it was answered; these are furniture that happens to be
	-- person-shaped, and they are here because half of childhood is answered by
	-- choosing which person to walk to. Sharing one grown-up across six events is
	-- deliberate: it is the same adult, in the same house, and giving each event its
	-- own would be six subtly different people for no reason a player could ever see.

	{
		id = "grown_up",
		name = "the grown-up",
		shape = "Figure",
		-- Adult height against a childhood ladder that tops out at 3.4. The gap is
		-- the point: every event that offers this as an answer is offering the option
		-- of being carried, fetched or rescued by something much bigger than you.
		size = Vector3.new(1.6, 5, 0.9),
		color = Color3.fromRGB(96, 112, 104),
		accentColor = Color3.fromRGB(226, 188, 160),
		reachStuds = 4,
		liftStuds = 0,
	},
	{
		id = "stranger",
		name = "the face you don't know",
		shape = "Figure",
		size = Vector3.new(1.6, 5, 0.9),
		-- Same size as the grown-up and a different color, which is the whole of what
		-- a one-year-old is working with: this is a person exactly like the one holding
		-- you, except that it is not them.
		color = Color3.fromRGB(140, 108, 132),
		accentColor = Color3.fromRGB(226, 188, 160),
		reachStuds = 4,
		liftStuds = 0,
	},

	-- childhood_first_steps ---------------------------------------------------

	{
		id = "couch",
		name = "the couch",
		shape = "Block",
		-- Long, because the answer that uses it is edging along its whole length. A
		-- couch you could cross in two steps would make the careful answer the fast one.
		size = Vector3.new(6, 1.6, 2.4),
		color = Color3.fromRGB(132, 118, 100),
		accentColor = Color3.fromRGB(98, 86, 72),
		reachStuds = 4,
		liftStuds = 0,
	},

	-- childhood_naming_things -------------------------------------------------

	{
		id = "toy_box",
		name = "the box of everything",
		shape = "Block",
		size = Vector3.new(2.4, 1.4, 1.8),
		color = Color3.fromRGB(206, 118, 92),
		accentColor = Color3.fromRGB(240, 176, 44),
		reachStuds = 4,
		liftStuds = 0,
	},
	{
		id = "lamp",
		name = "the light",
		shape = "Block",
		-- Tall and thin so it reads from across the room, and so that standing under it
		-- and pointing up is a thing the player can see themselves doing.
		size = Vector3.new(0.6, 5.5, 0.6),
		color = Color3.fromRGB(210, 204, 190),
		accentColor = Color3.fromRGB(248, 226, 150),
		reachStuds = 4,
		liftStuds = 0,
	},
	{
		id = "stuffed_dog",
		name = "the stuffed dog",
		shape = "Figure",
		size = Vector3.new(0.8, 1.2, 0.5),
		color = Color3.fromRGB(168, 140, 108),
		accentColor = Color3.fromRGB(120, 96, 74),
		reachStuds = 3,
		liftStuds = 0,
	},

	-- childhood_sandbox -------------------------------------------------------

	{
		id = "sand_pit",
		name = "the sandbox",
		shape = "Block",
		size = Vector3.new(7, 0.4, 7),
		color = Color3.fromRGB(224, 202, 154),
		accentColor = Color3.fromRGB(150, 122, 84),
		-- Generous, because the answer is digging *in* it rather than touching it. A
		-- tight reach would have the player hunting for the one stud that counts as
		-- being in a sandbox seven studs across.
		reachStuds = 5,
		liftStuds = 0,
	},
	{
		id = "low_wall",
		name = "the low wall",
		shape = "Block",
		-- Somewhere to be that is not the sandbox. The answer it carries is watching
		-- rather than joining, and that only reads as a decision if there is a second
		-- place in the yard to make it from.
		size = Vector3.new(5, 1.2, 0.8),
		color = Color3.fromRGB(164, 156, 144),
		accentColor = Color3.fromRGB(124, 118, 108),
		reachStuds = 3,
		liftStuds = 0,
	},

	-- childhood_end_of_yard ---------------------------------------------------

	{
		id = "hedge_gap",
		name = "the gap in the hedge",
		shape = "Block",
		-- Child-sized, which is the entire reason the gap is interesting: it is the one
		-- door in the yard that was not built for the people who tell you where to go.
		size = Vector3.new(2.2, 3, 0.8),
		color = Color3.fromRGB(74, 104, 68),
		accentColor = Color3.fromRGB(46, 68, 44),
		reachStuds = 4,
		liftStuds = 0,
	},

	-- childhood_storm ---------------------------------------------------------

	{
		id = "window",
		name = "the window",
		shape = "Block",
		size = Vector3.new(3.2, 4, 0.3),
		color = Color3.fromRGB(122, 140, 164),
		accentColor = Color3.fromRGB(228, 234, 242),
		reachStuds = 4,
		liftStuds = 0,
	},
	{
		id = "bed",
		name = "the bed",
		shape = "Block",
		size = Vector3.new(4, 1.4, 6),
		color = Color3.fromRGB(198, 190, 178),
		accentColor = Color3.fromRGB(146, 136, 122),
		reachStuds = 4,
		liftStuds = 0,
	},

	-- childhood_dropped_spoon -------------------------------------------------

	{
		id = "spoon",
		name = "the spoon",
		shape = "Block",
		size = Vector3.new(0.25, 0.12, 1.2),
		color = Color3.fromRGB(206, 208, 212),
		accentColor = Color3.fromRGB(150, 154, 160),
		reachStuds = 3,
		liftStuds = 0,
	},
	{
		id = "bowl",
		name = "the bowl",
		shape = "Cylinder",
		size = Vector3.new(1.4, 0.7, 1.4),
		color = Color3.fromRGB(238, 214, 168),
		accentColor = Color3.fromRGB(180, 148, 96),
		reachStuds = 3,
		liftStuds = 1.4,
	},

	-- childhood_stairs --------------------------------------------------------

	{
		id = "stairs",
		name = "the stairs",
		shape = "Block",
		size = Vector3.new(4.5, 3, 6),
		color = Color3.fromRGB(146, 124, 100),
		accentColor = Color3.fromRGB(108, 90, 72),
		reachStuds = 4,
		liftStuds = 0,
	},
	{
		id = "stair_rail",
		name = "the rail",
		shape = "Block",
		size = Vector3.new(0.35, 3.2, 5),
		color = Color3.fromRGB(122, 96, 70),
		accentColor = Color3.fromRGB(88, 68, 50),
		-- Tight on purpose. Holding a rail means being against it, and the answer that
		-- uses it is the careful one -- it should have to be done carefully.
		reachStuds = 3,
		liftStuds = 0,
	},

	-- childhood_one_toy -------------------------------------------------------

	{
		id = "worn_toy",
		name = "the one you keep",
		shape = "Figure",
		size = Vector3.new(0.9, 1.4, 0.6),
		-- Drab, and the accent is barely there. The prompt says it is not the newest or
		-- the nicest, so it must not be the brightest thing on the floor either.
		color = Color3.fromRGB(158, 146, 130),
		accentColor = Color3.fromRGB(184, 160, 128),
		reachStuds = 3,
		liftStuds = 0,
	},
	{
		id = "front_door",
		name = "the front door",
		shape = "Block",
		size = Vector3.new(3.4, 6.4, 0.4),
		color = Color3.fromRGB(84, 92, 108),
		accentColor = Color3.fromRGB(196, 176, 120),
		reachStuds = 4,
		liftStuds = 0,
	},

	-- childhood_hiding --------------------------------------------------------

	{
		id = "curtain",
		name = "the curtain",
		shape = "Block",
		size = Vector3.new(2.6, 5.6, 0.3),
		color = Color3.fromRGB(148, 108, 116),
		accentColor = Color3.fromRGB(108, 76, 84),
		reachStuds = 3,
		liftStuds = 0,
	},
	{
		id = "cupboard",
		name = "the cupboard",
		shape = "Block",
		size = Vector3.new(2.6, 3.6, 1.6),
		color = Color3.fromRGB(112, 92, 78),
		accentColor = Color3.fromRGB(78, 64, 54),
		reachStuds = 4,
		liftStuds = 0,
	},

	-- childhood_puddle --------------------------------------------------------

	{
		id = "puddle",
		name = "the puddle",
		shape = "Block",
		-- Wide enough that going around it is a genuine detour rather than a sidestep,
		-- which is the only thing that makes the careful answer cost anything.
		size = Vector3.new(6, 0.06, 5),
		color = Color3.fromRGB(108, 128, 142),
		accentColor = Color3.fromRGB(150, 172, 186),
		reachStuds = 4,
		liftStuds = 0,
	},
	{
		id = "dry_path",
		name = "the dry side",
		shape = "Block",
		size = Vector3.new(3.2, 0.1, 3.2),
		color = Color3.fromRGB(178, 170, 156),
		accentColor = Color3.fromRGB(140, 132, 120),
		reachStuds = 3,
		liftStuds = 0,
	},

	-- childhood_broke_it ------------------------------------------------------

	{
		id = "broken_half",
		name = "the broken half",
		shape = "Block",
		size = Vector3.new(0.9, 0.7, 0.7),
		color = Color3.fromRGB(232, 226, 214),
		accentColor = Color3.fromRGB(164, 156, 142),
		reachStuds = 3,
		liftStuds = 0,
	},

	-- childhood_mirror --------------------------------------------------------

	{
		id = "mirror",
		name = "the other baby",
		shape = "Block",
		-- Named for what is in it rather than for what it is, because at one year old
		-- those are not the same object and the event is entirely about the difference.
		size = Vector3.new(2.6, 4.4, 0.3),
		color = Color3.fromRGB(206, 220, 228),
		accentColor = Color3.fromRGB(140, 118, 92),
		reachStuds = 4,
		liftStuds = 0,
	},
	{
		id = "other_side",
		name = "the other side",
		shape = "Block",
		-- The answer to "where is the baby actually standing", crawled to and found to
		-- be nothing. It has to be a real place across the room rather than a face of
		-- the mirror: two answers on one object is a coin flip, and more to the point a
		-- child who thinks there is somebody in there goes looking for the room they
		-- are in, not for the back of a pane of glass.
		size = Vector3.new(4, 6, 0.5),
		color = Color3.fromRGB(188, 180, 168),
		accentColor = Color3.fromRGB(148, 140, 130),
		reachStuds = 3,
		liftStuds = 0,
	},

	-- childhood_helping -------------------------------------------------------

	{
		id = "flashlight",
		name = "the flashlight",
		shape = "Block",
		size = Vector3.new(0.4, 0.4, 1.5),
		color = Color3.fromRGB(66, 72, 80),
		accentColor = Color3.fromRGB(248, 232, 168),
		reachStuds = 3,
		liftStuds = 0,
	},
	{
		id = "workbench",
		name = "what they are working on",
		shape = "Block",
		size = Vector3.new(4.2, 2.6, 1.8),
		color = Color3.fromRGB(134, 106, 78),
		accentColor = Color3.fromRGB(96, 78, 58),
		reachStuds = 4,
		liftStuds = 0,
	},
	{
		id = "washer",
		name = "the small metal one",
		shape = "Cylinder",
		-- The smallest thing in this file, and that is the joke: the answer that ends
		-- with "you still know what a washer is" should be the player picking up the
		-- one object on the floor they could not possibly name.
		size = Vector3.new(0.35, 0.1, 0.35),
		color = Color3.fromRGB(178, 182, 188),
		accentColor = Color3.fromRGB(126, 130, 136),
		reachStuds = 3,
		liftStuds = 0,
	},
}

local byId: { [string]: PropKind } = {}
for _, prop in list do
	if byId[prop.id] ~= nil then
		error(`[AGES content] duplicate prop id "{prop.id}"`)
	end
	-- A prop with no size is invisible and unreachable, and the symptom is an event
	-- with one fewer answer than it was written with -- which looks like the event
	-- being wrong rather than like this line being missing.
	if prop.size.X <= 0 or prop.size.Y <= 0 or prop.size.Z <= 0 then
		error(`[AGES content] prop "{prop.id}" has a zero or negative size`)
	end
	if prop.reachStuds <= 0 then
		error(`[AGES content] prop "{prop.id}" has a reachStuds of {prop.reachStuds}, so it could never be reached`)
	end
	byId[prop.id] = prop
end

return {
	All = list,
	ById = byId,
}
