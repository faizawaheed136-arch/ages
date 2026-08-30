--!strict
-- Who the other students are.
--
-- The crowd worked and was anonymous: fourteen rigs walking a building, every one of them
-- nobody. That is a subtly worse failure than an empty school, because an empty room reads as
-- unfinished while a room full of blanks reads as *finished and hollow* -- the reference
-- photographs are wall-to-wall named students with a clique under the name, and that labelling
-- is most of why those corridors feel inhabited.
--
-- **A clique is a place, not a costume.** This is the whole reason the file is worth having.
-- A label floating over a rig is decoration and would deserve about six lines; what makes it
-- a system is that a clique says *where its people stand*. Athletes are by the gym, the art
-- club is in the art room, the band is outside music, bookworms are in the library. So the
-- building sorts itself the way a real school does, and a player who learns the map learns
-- where to find somebody -- which is knowledge, and knowledge is the thing a crowd of
-- interchangeable rigs can never have.
--
-- That also means the school's own rooms are doing double duty. The art room was built for
-- the art lesson; it now also explains why those four students are standing over there.
--
-- Names are deliberately plain and short. These are read at a glance off a billboard from
-- across a corridor, and a cast of unusual names reads as a fantasy game rather than as a
-- school.

local Students = {}

export type Clique = {
	id: string,
	-- Shown under the name, in the reference's own register: a one-word social position.
	label: string,
	-- The rooms this clique is found in, most likely first. Room ids as School.Plan names
	-- them; a clique naming a room the build does not have simply never places there, which
	-- is why every list has "corridor" in it as a fallback everybody shares.
	rooms: { string },
	-- One line under the label. Written as the student would put it, not as a stat block --
	-- the reference's bios are self-descriptions and that is what makes them read as people.
	bios: { string },
}

-- The name pool. One list rather than one per clique: a school is not sorted by name, and
-- tying names to cliques would make the clique guessable from the name, which is exactly the
-- kind of tidy-but-false pattern that makes a generated cast feel generated.
Students.Names = {
	"Alex", "Sam", "Riley", "Jordan", "Casey", "Morgan", "Taylor", "Jamie",
	"Avery", "Quinn", "Reese", "Rowan", "Skyler", "Emerson", "Finley", "Harper",
	"Kai", "Noor", "Zara", "Omar", "Mila", "Theo", "Ines", "Rafi",
	"Nina", "Dev", "Lena", "Cruz", "Iris", "Milo", "Sana", "Beau",
}

-- The cliques, and where each one lives.
--
-- Weighted by how many entries a clique has in the spawn table rather than by a number field:
-- a plain list is easier to read and to change, and the weighting is visible in the shape of
-- the file rather than hidden in an integer.
Students.Cliques = {
	{
		id = "student",
		label = "Student",
		rooms = { "corridor", "cafeteria", "lounge" },
		bios = {
			"just trying to get through the week",
			"here for the food, honestly",
			"knows every shortcut in this building",
			"has a locker that will not shut",
		},
	},
	{
		id = "athlete",
		label = "Athlete",
		rooms = { "corridor", "cafeteria", "lounge" },
		bios = {
			"training before school and after it",
			"captain, and will mention it",
			"eats four lunches a day",
			"knees are held together by tape",
		},
	},
	{
		id = "art",
		label = "Art Club",
		rooms = { "art", "art", "corridor", "lounge" },
		bios = {
			"quiet, kind, likes to draw",
			"paint on both sleeves, permanently",
			"sketching whoever is standing still",
			"has opinions about the good pencils",
		},
	},
	{
		id = "band",
		label = "Band",
		rooms = { "music", "music", "corridor" },
		bios = {
			"third chair and climbing",
			"humming something you almost know",
			"carries the case everywhere",
			"practises in the stairwell",
		},
	},
	{
		id = "bookworm",
		label = "Bookworm",
		rooms = { "library", "library", "reading", "corridor" },
		bios = {
			"two chapters from the end",
			"knows where everything is shelved",
			"reads while walking, badly",
			"has never returned a book late",
		},
	},
	{
		id = "science",
		label = "Science Club",
		rooms = { "science", "computers", "corridor" },
		bios = {
			"the experiment is going fine, probably",
			"safety goggles, always",
			"asks the question everyone was thinking",
			"lab coat is a lifestyle",
		},
	},
	{
		id = "cook",
		label = "Home Ec",
		rooms = { "cooking", "cafeteria", "corridor" },
		bios = {
			"brought enough to share",
			"the cake was structurally ambitious",
			"tastes everything twice",
			"flour on the blazer",
		},
	},
	{
		id = "freshman",
		label = "Freshman",
		rooms = { "corridor", "corridor", "cafeteria", "lounge" },
		bios = {
			"still holding the map",
			"new here, and it shows",
			"asked where room 12 was, twice",
			"early to everything",
		},
	},
}

-- One student's identity: a name, a clique, and a line.
--
-- Rolled rather than drawn from a pool without replacement. Two students sharing a name in a
-- school of eight hundred is true to life, and the alternative -- tracking which of thirty-two
-- names are in use across a crowd that is constantly being torn down and rebuilt as the player
-- walks in and out of range -- is bookkeeping that would buy nothing a player could notice.
function Students.Roll(): { name: string, clique: Clique, bio: string }
	local clique = Students.Cliques[math.random(1, #Students.Cliques)]
	return {
		name = Students.Names[math.random(1, #Students.Names)],
		clique = clique,
		bio = clique.bios[math.random(1, #clique.bios)],
	}
end

return Students
