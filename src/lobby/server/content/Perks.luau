--!strict
-- What a spin can land on, and what landing on one does to a life.
--
-- **Lobby-only, on purpose.** A perk is spent the instant a life is created -- see
-- `LobbySetupService.Create` -- and from that moment on it is nothing but stats and money,
-- indistinguishable from a life that never had one. Nothing in the game place has ever
-- needed to know a perk existed, so this file is not mapped there the way `LifeSetup` and
-- `Countries` are; it lives beside `Stage.luau` as lobby-only content.
--
-- **Ten perks, four rarities, and rarity never means power.** That is the one rule the whole
-- spin design turns on -- see `ages_lobby_spec.md` -- so every effect below sits in the same
-- narrow band regardless of which tier it is filed under. A legendary perk is a rarer
-- *flavour* of ordinary start, never a stronger one. If a future perk needs a bigger number
-- than the others here, that is a sign it is miscategorised as a perk rather than as content
-- that belongs somewhere the game already handles power -- a job, a stat -- deliberately.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

-- Not a mapped module itself, so it is free to require one -- see the note on mapped
-- modules in CLAUDE.md, which restricts what a *mapped* file may require, not what a
-- lobby-only file like this one may require of a mapped one. `LifeSetup.StatOrder` is
-- reused here rather than re-declared, so the four stats are written in the one order the
-- rest of the lobby already agrees on.
local LifeSetup = require(script.Parent.Parent.shared.LifeSetup)

type Perk = Types.Perk
type PerkRarity = Types.PerkRarity
type LifeData = Types.LifeData
type StatName = Types.StatName

local Perks = {}

-- Rarities, written down once and in the order every list on screen draws them. The same
-- device as `LifeSetup.StatOrder`: `Config.Spins.RarityWeights` is a map, and map order is
-- whatever the hash says, so anything iterating it directly would reorder its own rows
-- between runs.
local RARITY_ORDER: { PerkRarity } = { "common", "uncommon", "rare", "legendary" }
Perks.RarityOrder = RARITY_ORDER

-- The ten perks. One common, three of each rarity above it -- the exact list the spin design
-- was approved with. Every effect is `birthCircumstance`: a handful of stat points in the
-- same range the setup card itself hands out (its pool is 8, spent up to 6 either way on one
-- stat), or a few hundred in starting money against a scale where an adult's month of wages
-- is low thousands (see `Config.Money`) -- both deliberately modest, so a spin changes what a
-- life *is about*, never how easy it is.
local ALL: { Perk } = {
	{
		id = "ordinary_start",
		name = "Ordinary Start",
		blurb = "No twist. You start life the way most people do.",
		rarity = "common",
		kind = "birthCircumstance",
		effect = {},
	},
	{
		id = "born_abroad",
		name = "Born Abroad",
		blurb = "Your first language isn't the one everyone around you grew up speaking.",
		rarity = "uncommon",
		kind = "birthCircumstance",
		effect = { statDeltas = { smarts = 2, happiness = -1 } },
	},
	{
		id = "a_knack",
		name = "A Knack",
		blurb = "Something has always come easily to you.",
		rarity = "uncommon",
		kind = "birthCircumstance",
		effect = { statDeltas = { smarts = 3 } },
	},
	{
		id = "big_family",
		name = "A Big Family",
		blurb = "You're one of many. There's always someone around.",
		rarity = "uncommon",
		kind = "birthCircumstance",
		effect = { statDeltas = { happiness = 3, looks = -1 } },
	},
	{
		id = "born_into_money",
		name = "Born Into Money",
		blurb = "Your family has never had to worry about rent.",
		rarity = "rare",
		kind = "birthCircumstance",
		effect = { startingMoney = 400 },
	},
	{
		id = "coming_apart",
		name = "A Family Coming Apart",
		blurb = "Something is breaking at home, and you can feel it.",
		rarity = "rare",
		kind = "birthCircumstance",
		effect = { statDeltas = { happiness = -3, smarts = 2 } },
	},
	{
		id = "one_grandparent",
		name = "Raised By One Grandparent",
		blurb = "It's just the two of you, and that's always been enough.",
		rarity = "rare",
		kind = "birthCircumstance",
		effect = { statDeltas = { happiness = 2, health = -1 } },
	},
	{
		id = "a_twin",
		name = "A Twin",
		blurb = "You've never known what it's like to be the only one.",
		rarity = "legendary",
		kind = "birthCircumstance",
		effect = { statDeltas = { happiness = 2, looks = 1 } },
	},
	{
		id = "born_famous",
		name = "Born Famous",
		blurb = "People knew your family's name before they knew yours.",
		rarity = "legendary",
		kind = "birthCircumstance",
		effect = { startingMoney = 250, statDeltas = { happiness = -2 } },
	},
	{
		id = "born_with_nothing",
		name = "Born With Nothing",
		blurb = "You start owing the world an explanation for none of this.",
		rarity = "legendary",
		kind = "birthCircumstance",
		effect = { statDeltas = { smarts = 2, happiness = 2 } },
	},
}
Perks.All = ALL

local BY_ID: { [string]: Perk } = {}
for _, perk in ALL do
	BY_ID[perk.id] = perk
end
Perks.ById = BY_ID

local BY_RARITY: { [PerkRarity]: { Perk } } = { common = {}, uncommon = {}, rare = {}, legendary = {} }
for _, perk in ALL do
	table.insert(BY_RARITY[perk.rarity], perk)
end
Perks.ByRarity = BY_RARITY

local function totalWeight(): number
	local sum = 0
	for _, weight in Config.Spins.RarityWeights do
		sum += weight
	end
	return sum
end

-- The exact probability of landing on every individual perk, out of 1. What the buy page
-- shows before a purchase, and it has to be per-perk rather than per-tier: Roblox requires
-- the odds of a paid random item disclosed by the item, and a tier's share is split evenly
-- across however many perks are filed under it, so three rares each show a third of the rare
-- tier's weight rather than the whole of it three times over.
function Perks.Odds(): { [string]: number }
	local total = totalWeight()
	local odds: { [string]: number } = {}
	for _, rarity in RARITY_ORDER do
		local perksInTier = BY_RARITY[rarity]
		local tierChance = (Config.Spins.RarityWeights[rarity] :: number) / total
		local perPerk = tierChance / #perksInTier
		for _, perk in perksInTier do
			odds[perk.id] = perPerk
		end
	end
	return odds
end

-- One pull. `rng` is accepted rather than always reaching for a fresh `Random.new()`, so the
-- debug harness can hand this a seeded one and get a repeatable result to test against.
function Perks.Roll(rng: Random?): Perk
	local random = rng or Random.new()
	local total = totalWeight()
	local roll = random:NextNumber(0, total)

	local cursor = 0
	for _, rarity in RARITY_ORDER do
		cursor += Config.Spins.RarityWeights[rarity]
		if roll <= cursor then
			local perksInTier = BY_RARITY[rarity]
			return perksInTier[random:NextInteger(1, #perksInTier)]
		end
	end

	-- Unreachable except by floating-point error landing `roll` a hair above `total`, which
	-- `NextNumber`'s own inclusive-exclusive range makes possible at the very edge. Falls
	-- back to the last rarity in order rather than erroring, because a spin the player paid
	-- for has to land on *something*.
	local lastTier = BY_RARITY[RARITY_ORDER[#RARITY_ORDER]]
	return lastTier[random:NextInteger(1, #lastTier)]
end

-- Spend a perk onto a freshly built life. Called once, at creation, after
-- `LifeSetup.StartingStats` has already written the base stats -- this only adds to what is
-- already there, through the same clamp, so a perk can never hand out a stat outside the
-- range a player's own points could have reached.
function Perks.Apply(life: LifeData, perkId: string): boolean
	local perk = BY_ID[perkId]
	if perk == nil then
		return false
	end

	-- Walked by `LifeSetup.StatOrder` rather than iterated straight off `statDeltas`, the same
	-- device `LifeSetup.StartingStats` uses and for the same reason: `statDeltas` is keyed by
	-- plain `string`, because it is authored as a small untyped table above, and indexing
	-- `life.stats` -- keyed by the four-way `StatName` union -- with a bare string is exactly
	-- the kind of thing that reads fine and fails `--!strict`. Going the other way round, one
	-- known `StatName` at a time, keeps every index on the narrower type.
	local statDeltas = perk.effect.statDeltas
	if statDeltas ~= nil then
		for _, statName in LifeSetup.StatOrder :: { StatName } do
			local delta = statDeltas[statName]
			if delta ~= nil and delta ~= 0 then
				local value = life.stats[statName] + delta
				life.stats[statName] = math.clamp(value, Config.Stats.Min, Config.Stats.Max)
			end
		end
	end

	local startingMoney = perk.effect.startingMoney
	if startingMoney ~= nil then
		life.money = math.clamp(life.money + startingMoney, 0, Config.Money.MaxBalance)
	end

	return true
end

return Perks
