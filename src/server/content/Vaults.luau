--!strict
-- Which places in town have a vault, and where the furniture is inside them.
--
-- Content, and a list of one today. It is a list rather than a constant for the reason
-- Tills is: the brief for this system has always said "and other stores added later", and
-- a second bank should cost a table row rather than a refactor of the file that robs it.
--
-- **The offsets are the whole point of this file.** Everything the bank activity needs is
-- a floor plan -- how far the vault is from the door, where the alarm panel is, where the
-- guard walks -- and all of it is written here as studs from the place point rather than
-- read off the generated room. That is the same argument PlaceService's header makes and
-- Till repeats: the town is generated, the generator already puts a box named `Vault` and
-- a box named `Teller` in this room, and hanging the game off those names would mean the
-- day somebody renames a box is the day the bank silently stops working. A place point is
-- the town's own promise about where the door is. Measured against the generated bank as
-- it stands, so the numbers are true today and are *checkable* -- if the room moves, this
-- file is the one place that has to change.
--
-- The distance from the alarm panel to the vault is the difficulty of this activity, and
-- it is set in studs on this page rather than as a multiplier in Config. That is
-- deliberate: escalation in this project is by changing the space, and the space is here.
-- Config.Crime.Bank.RearmSeconds is tuned *against* these numbers -- roughly six seconds
-- of running for a round trip -- so the two have to be read together.

local Vaults = {}

-- A spot on the floor of the room, from the place point.
--
-- `forward` is into the room, along the way the place point faces. `side` is to the right
-- of somebody standing on the point looking in, and negative is to their left. Two numbers
-- rather than a Vector3 because the third one is always the floor: nothing in a bank is
-- placed by height, only the parts that hang off these are.
export type Offset = {
	forward: number,
	side: number,
}

-- One robbable bank.
export type Bank = {
	-- The place id, which has to be a place point in the built world -- the same ids
	-- PlaceService indexes.
	place: string,
	-- What the player calls it. The place point's own label is a sentence about where to
	-- stand; a heat notice needs a name.
	name: string,

	-- How far from the place point still counts as being inside, flat.
	--
	-- This is what the session is held by: a bank robbery does not end when you step away
	-- from the vault -- you are *meant* to walk away from the vault, that is the activity --
	-- it ends when you leave the building. A circle over a rectangular room, which spills a
	-- little past the front door, and that is the right way for it to be wrong: you are not
	-- out until you are properly out.
	-- Safe range: enough to cover the far corner of the room plus a couple of studs.
	roomStuds: number,

	-- The vault door.
	vault: Offset,
	-- The alarm panel. By the entrance on purpose, which is what makes silencing the alarm
	-- cost the walk away from the money.
	alarm: Offset,
	-- Where the guard walks, in order, returning to the first. At least two, or he is not
	-- patrolling, he is standing somewhere.
	patrol: { Offset },

	-- What the vault is worth, as a share of Config.Crime.Bank.VaultFloat. The one
	-- difficulty dial here, and as in Tills it is set against how exposed the building is
	-- rather than against what it holds.
	-- Safe range: 0.6-1.4.
	richness: number,
}

local Banks: { Bank } = {
	-- The generated bank on the civic row. Measured: the room runs x 683..733 and
	-- z 968..1012, the place point is the door at (708, 970) facing north into it, and the
	-- vault sits in the far corner at (729.5, 1007.5) -- 43 studs from the door.
	--
	-- The alarm panel goes on the wall to the left of the entrance, twelve studs in, which
	-- puts it 48 studs from the vault: three seconds of running each way at an ordinary
	-- walk. That number is the metronome the whole activity is played against and it is not
	-- an accident of the floor plan -- it was chosen and the room was measured to hold it.
	--
	-- The patrol crosses the room diagonally rather than running along one wall, so the
	-- guard is never at a fixed distance from either the vault or the panel, and so the
	-- moment he can no longer see the vault is a moment the player can watch arrive. From
	-- the door end of his walk the vault is 40 studs away, which is outside his sight: that
	-- gap is the window, and it is geometry rather than a timer.
	{
		place = "bank",
		name = "First National",
		roomStuds = 52,
		vault = { forward = 37.5, side = 21.5 },
		alarm = { forward = 3, side = -12 },
		patrol = {
			{ forward = 32, side = 14 },
			{ forward = 8, side = -6 },
		},
		richness = 1,
	},
}

-- Loud at require time rather than at the moment somebody walks into the lobby, which is
-- the standing rule for content in this tree.
local seen: { [string]: boolean } = {}
for index, bank in Banks do
	if bank.place == "" then
		error(`[AGES content] Vaults[{index}] has no place id. Every bank must name a place point.`)
	end
	if seen[bank.place] then
		error(
			`[AGES content] two banks claim the place "{bank.place}". `
				.. `A place point can only hold one vault -- remove one of them from Vaults.luau.`
		)
	end
	seen[bank.place] = true

	if bank.richness <= 0 then
		error(
			`[AGES content] bank "{bank.place}" has richness {bank.richness}. `
				.. `A vault worth nothing is a room the player opens once and never returns to; `
				.. `remove it from Vaults.luau instead.`
		)
	end

	if #bank.patrol < 2 then
		error(
			`[AGES content] bank "{bank.place}" has {#bank.patrol} patrol spot(s). `
				.. `A guard with fewer than two stands still, and a guard who stands still is a `
				.. `fixed obstacle rather than a rhythm to read -- give him somewhere to walk to.`
		)
	end

	-- The one relationship in this file that can be wrong without looking wrong. A panel
	-- next to the vault would leave the whole activity intact and completely free, because
	-- silencing the alarm would cost nothing at all -- and nothing else in the tree would
	-- have anything to say about it.
	local apart = math.sqrt(
		(bank.vault.forward - bank.alarm.forward) ^ 2 + (bank.vault.side - bank.alarm.side) ^ 2
	)
	if apart < 20 then
		error(
			`[AGES content] bank "{bank.place}" has its alarm panel {string.format("%.1f", apart)} studs `
				.. `from its vault. The walk between them is the entire cost of silencing the alarm, so a `
				.. `panel this close makes the robbery free. Move one of them in Vaults.luau.`
		)
	end

	-- Everything has to be inside the room the session is held by, or the player would be
	-- dropped out of their own robbery by walking to the thing the robbery is about.
	local function within(what: string, spot: Offset)
		local reach = math.sqrt(spot.forward ^ 2 + spot.side ^ 2)
		if reach > bank.roomStuds then
			error(
				`[AGES content] bank "{bank.place}" puts its {what} {string.format("%.1f", reach)} studs `
					.. `from the place point but only counts {bank.roomStuds} as inside. Walking to it would `
					.. `end the robbery. Raise roomStuds or move it in Vaults.luau.`
			)
		end
	end
	within("vault", bank.vault)
	within("alarm panel", bank.alarm)
	for spotIndex, spot in bank.patrol do
		within(`patrol spot {spotIndex}`, spot)
	end
end

Vaults.Banks = Banks

-- Nil for a place with no vault in it, which is every place in town but one. Every caller
-- handles that rather than being handed a default.
function Vaults.Get(place: string): Bank?
	for _, bank in Banks do
		if bank.place == place then
			return bank
		end
	end
	return nil
end

return Vaults
