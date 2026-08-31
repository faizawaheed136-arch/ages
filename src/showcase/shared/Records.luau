--!strict
-- The house records. Fixed history, not a live tally.
--
-- Deliberately static: a showcase scoreboard that counted real matches would be empty on the
-- day anybody visited, and an empty board says less than no board. These are the results the
-- building remembers.
--
-- Shared, so the client draws it without a round trip. Nothing here is authoritative over
-- anything, so there is no reason to hide it on the server.

export type Entry = {
	Rank: number,
	Name: string,
	House: string,
	Wins: number,
	Losses: number,
}

export type Ring = {
	Id: string,
	Title: string,
	Subtitle: string,
	Entries: { Entry },
}

local Records = {}

Records.Rings = {
	{
		Id = "north",
		Title = "NORTH RING",
		Subtitle = "Senior division · standing record",
		Entries = {
			{ Rank = 1, Name = "Arai, K.", House = "Iron", Wins = 47, Losses = 4 },
			{ Rank = 2, Name = "Mori, S.", House = "Ash", Wins = 41, Losses = 9 },
			{ Rank = 3, Name = "Tachibana, R.", House = "Iron", Wins = 38, Losses = 11 },
			{ Rank = 4, Name = "Kudo, H.", House = "Stone", Wins = 33, Losses = 15 },
			{ Rank = 5, Name = "Onishi, T.", House = "Ash", Wins = 29, Losses = 18 },
			{ Rank = 6, Name = "Fujita, M.", House = "Stone", Wins = 26, Losses = 21 },
		},
	},
	{
		Id = "south",
		Title = "SOUTH RING",
		Subtitle = "Junior division · standing record",
		Entries = {
			{ Rank = 1, Name = "Sakai, Y.", House = "Ash", Wins = 22, Losses = 2 },
			{ Rank = 2, Name = "Nomura, D.", House = "Stone", Wins = 19, Losses = 5 },
			{ Rank = 3, Name = "Ishii, A.", House = "Iron", Wins = 17, Losses = 8 },
			{ Rank = 4, Name = "Hayashi, K.", House = "Ash", Wins = 14, Losses = 10 },
			{ Rank = 5, Name = "Ueda, N.", House = "Iron", Wins = 11, Losses = 13 },
			{ Rank = 6, Name = "Sano, J.", House = "Stone", Wins = 9, Losses = 16 },
		},
	},
} :: { Ring }

Records.ByRing = {} :: { [string]: Ring }
for _, ring in Records.Rings do
	Records.ByRing[ring.Id] = ring
end

Records.DefaultRing = "north"

return Records
