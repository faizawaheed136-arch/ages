--!strict
-- Where a life can begin. Authored, ordered, and validated at server start.
--
-- **What a country does today: it names you.** A life begun in Lagos is named from
-- Lagos. That is the whole of it, and the floor is deliberate rather than unfinished.
-- The obvious next step -- countries that hand out stat bonuses -- is one this game is
-- not going to take: it would be AGES telling the player that people born in one place
-- are smarter or better-looking than people born in another, which is both untrue and
-- not a mechanic worth having. What a country is *for* later is content: the places you
-- can go, the schools, the jobs, what money is worth. Every one of those is a fact about
-- a society, and none of them is a modifier on a person.
--
-- So the names are the mechanic. They are not decoration either -- the name is the first
-- thing the player sees about who they are, it is on the death screen at the end, and it
-- is the one part of a life that is chosen before the life starts. A country that changes
-- it is a country that has changed something real.
--
-- **Ten names per list, not fifty.** These are picked from by a shuffle button the player
-- presses until they like the answer, so the list wants to be short enough that every
-- entry is one somebody would actually want and long enough that pressing it twice rarely
-- repeats. Common, current, unremarkable names on purpose: this is the name of the person
-- the player is about to be, not a costume.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Types"))

type Country = Types.Country
type Gender = Types.Gender

-- Ordered rather than a keyed map, because the menu steps through these with arrows and
-- the order it steps in has to be a decision somebody made rather than whatever the hash
-- happened to produce. Alphabetical by display name.
local COUNTRIES: { Country } = {
	{
		id = "br",
		name = "Brazil",
		firstNamesMale = {
			"Bruno", "Caio", "Diego", "Felipe", "Gustavo", "Lucas", "Mateus", "Rafael", "Thiago", "Vinicius",
		},
		firstNamesFemale = {
			"Amanda", "Beatriz", "Camila", "Fernanda", "Gabriela", "Juliana", "Larissa", "Mariana", "Rafaela", "Vitoria",
		},
		lastNames = {
			"Almeida", "Barbosa", "Carvalho", "Ferreira", "Gomes", "Lima", "Oliveira", "Pereira", "Ribeiro", "Santos",
		},
	},
	{
		id = "fr",
		name = "France",
		firstNamesMale = {
			"Antoine", "Bastien", "Clement", "Etienne", "Hugo", "Julien", "Mathis", "Olivier", "Raphael", "Theo",
		},
		firstNamesFemale = {
			"Amelie", "Camille", "Chloe", "Elise", "Ines", "Juliette", "Lea", "Manon", "Noemie", "Sylvie",
		},
		lastNames = {
			"Bernard", "Dubois", "Fournier", "Girard", "Lambert", "Leroy", "Marchand", "Moreau", "Petit", "Rousseau",
		},
	},
	{
		id = "in",
		name = "India",
		firstNamesMale = {
			"Aditya", "Arjun", "Devan", "Ishaan", "Karthik", "Nikhil", "Rohan", "Sameer", "Varun", "Vikram",
		},
		firstNamesFemale = {
			"Aisha", "Ananya", "Divya", "Ishita", "Kavya", "Meera", "Neha", "Priya", "Riya", "Sanya",
		},
		lastNames = {
			"Banerjee", "Chopra", "Desai", "Iyer", "Kapoor", "Menon", "Nair", "Rao", "Sharma", "Verma",
		},
	},
	{
		id = "jp",
		name = "Japan",
		firstNamesMale = {
			"Daiki", "Haruto", "Kenji", "Riku", "Ryo", "Sora", "Takumi", "Yuki", "Yuto", "Kaito",
		},
		firstNamesFemale = {
			"Aoi", "Hana", "Mei", "Nanami", "Rin", "Sakura", "Yui", "Yuna", "Emi", "Hikari",
		},
		lastNames = {
			"Fujita", "Hayashi", "Ishikawa", "Kobayashi", "Matsumoto", "Nakamura", "Sato", "Suzuki", "Tanaka", "Yamada",
		},
	},
	{
		id = "mx",
		name = "Mexico",
		firstNamesMale = {
			"Alejandro", "Andres", "Diego", "Emiliano", "Javier", "Mateo", "Miguel", "Rodrigo", "Santiago", "Tomas",
		},
		firstNamesFemale = {
			"Adriana", "Carmen", "Daniela", "Elena", "Guadalupe", "Isabel", "Lucia", "Regina", "Valeria", "Ximena",
		},
		lastNames = {
			"Castillo", "Flores", "Garcia", "Hernandez", "Jimenez", "Morales", "Ramirez", "Reyes", "Torres", "Vargas",
		},
	},
	{
		id = "ng",
		name = "Nigeria",
		firstNamesMale = {
			"Chidi", "Emeka", "Ifeanyi", "Kelechi", "Nnamdi", "Obinna", "Segun", "Tunde", "Uche", "Yemi",
		},
		firstNamesFemale = {
			"Adaeze", "Amaka", "Chiamaka", "Folake", "Ifeoma", "Ngozi", "Nkechi", "Simisola", "Temitope", "Zainab",
		},
		lastNames = {
			"Abiodun", "Adebayo", "Afolabi", "Chukwu", "Eze", "Nwachukwu", "Obi", "Okafor", "Okonkwo", "Oyelaran",
		},
	},
	{
		id = "uk",
		name = "United Kingdom",
		firstNamesMale = {
			"Alfie", "Callum", "Declan", "Ewan", "Harry", "Liam", "Oliver", "Rhys", "Toby", "Zack",
		},
		firstNamesFemale = {
			"Amelia", "Bethan", "Daisy", "Eleanor", "Freya", "Imogen", "Millie", "Niamh", "Poppy", "Sophie",
		},
		lastNames = {
			"Ashworth", "Baxter", "Clarke", "Ellis", "Hughes", "Morgan", "Norris", "Pryce", "Whitfield", "Wren",
		},
	},
	{
		id = "us",
		name = "United States",
		firstNamesMale = {
			"Andre", "Carter", "Dylan", "Elijah", "Isaiah", "Jonah", "Mason", "Nolan", "Tyler", "Wyatt",
		},
		firstNamesFemale = {
			"Abigail", "Brooke", "Delaney", "Harper", "Jasmine", "Maya", "Nora", "Peyton", "Sierra", "Zoey",
		},
		lastNames = {
			"Bennett", "Coleman", "Fletcher", "Grayson", "Hayes", "Mercer", "Parker", "Reyes", "Sullivan", "Winters",
		},
	},
}

local Countries = {}

Countries.All = COUNTRIES

Countries.ById = {} :: { [string]: Country }
for _, country in COUNTRIES do
	Countries.ById[country.id] = country
end

-- The country a menu opens on when the player has never picked one.
--
-- A real id rather than the first entry of the list, so that reordering the table above
-- -- which is alphabetical and will be reordered the moment a country is added -- cannot
-- silently move everybody's default somewhere else.
Countries.DefaultId = "us"

-- The list a name is drawn from. Public because the setup menu's shuffle, "Surprise Me"
-- and the server's fallback name all have to draw from the *same* list, and three call
-- sites each picking `if gender == "male" then a else b` is three chances to get it
-- backwards.
function Countries.FirstNames(country: Country, gender: Gender): { string }
	return if gender == "male" then country.firstNamesMale else country.firstNamesFemale
end

-- A whole name, for the shuffle button and for anyone who declines to type one.
--
-- Unseeded, unlike the town: the town is a fact about the world and has to be identical
-- for everybody, and this is one player pressing a button until they like the answer.
function Countries.RollName(country: Country, gender: Gender): (string, string)
	local firstNames = Countries.FirstNames(country, gender)
	return firstNames[math.random(#firstNames)], country.lastNames[math.random(#country.lastNames)]
end

-- Run at server start rather than trusted, on the same rule as every other content file
-- here: a country with an empty name list is a shuffle button that errors under the
-- player's finger, and the id it happened to be is the only useful thing to say about it.
local function validate()
	if #COUNTRIES == 0 then
		error("[AGES content] there are no countries, so no life can be started")
	end

	local seen: { [string]: boolean } = {}
	for _, country in COUNTRIES do
		if country.id == "" then
			error(`[AGES content] country "{country.name}" has an empty id`)
		end
		if seen[country.id] then
			error(`[AGES content] two countries share the id "{country.id}"; ids are what saves store`)
		end
		seen[country.id] = true

		if country.name == "" then
			error(`[AGES content] country "{country.id}" has no display name`)
		end

		-- Named individually rather than checked as a group, because "one of this
		-- country's three name lists is empty" sends whoever reads it back to count
		-- three lists, and there is no reason for them to have to.
		for label, list in
			{
				firstNamesMale = country.firstNamesMale,
				firstNamesFemale = country.firstNamesFemale,
				lastNames = country.lastNames,
			} :: { [string]: { string } }
		do
			if #list == 0 then
				error(`[AGES content] country "{country.id}" has an empty {label}, so it can never name anybody`)
			end
			for _, name in list do
				if name == "" then
					error(`[AGES content] country "{country.id}" has a blank entry in {label}`)
				end
			end
		end
	end

	if Countries.ById[Countries.DefaultId] == nil then
		error(
			`[AGES content] the default country "{Countries.DefaultId}" is not in the list, `
				.. `so the setup menu would open on nothing`
		)
	end
end

validate()

return Countries
