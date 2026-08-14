--!strict
-- The people who want a fight, and the only thing that makes them different.
--
-- Three archetypes, no moves between them. Every one of these is the same opponent
-- running the same loop -- wait, wind up, strike, recover -- and what separates them is
-- how long the wind-up lasts, how hard it lands and how often they answer with a guard
-- instead. That is deliberate and it is the whole design: the player has three buttons
-- and never gets a fourth, so the only place depth can come from is the opponent.
--
-- Read them as three different questions asked of the same control set:
--
--   The brawler asks "can you wait?" -- an enormous tell and an enormous punish window
--   behind it, so the answer is to step around the big one and hit them while they are
--   still recovering. A player who panics and blocks pays for it, because the brawler
--   is the one opponent whose strike is big enough to hurt through a guard.
--
--   The scrapper asks "can you stop waiting?" -- half the tell, a third of the damage,
--   and no rest between attacks. Sidestepping is a trap here: the window is too short
--   to read and the stamina cost means two dodges leave you with nothing. The answer is
--   to hold guard, let the flurry spend itself against it, and take the gap.
--
--   The boxer asks "will you take the risk?" -- they guard half the time, and a guard only
--   breaks to a strike charged past GuardBreakShare, which sits *above* OverchargeShare by
--   a rule the service refuses to boot without. So there is no way through a boxer's guard
--   that does not also buy the near-second of recovery on the other side of it. There is no
--   safe answer to a boxer, only a bet, and that is the whole point of having one.
--
-- Which is why the brawler is first and the boxer last. The first fight a player is
-- ever offered should be the one whose tell is impossible to miss.
--
-- Bodies live here rather than in content/Cast.luau because the population you fight is
-- not the population you befriend. Pointing at a cast id would eventually put a street
-- tough and somebody's mother on the same rig, and the moment that happens the town
-- stops being legible.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type FighterDef = Types.FighterDef

-- Nothing bought or uploaded, on the same reasoning the generated town uses: a fighter
-- that needed a shopping trip before it existed would not exist.
local NO_ASSETS = {
	shirtAssetId = 0,
	pantsAssetId = 0,
	hairAssetId = 0,
}

local Fighters: { FighterDef } = {
	{
		id = "brawler",
		name = "Brawler",
		blurb = "Winds up big and slow. Step around it and hit them while they are still swinging.",
		body = {
			id = "fighter_brawler",
			name = "Deke",
			gender = "male" :: Types.Gender,
			skinColor = Color3.fromRGB(197, 154, 118),
			-- The one visibly large opponent in the set. Build is doing the signposting
			-- here: you should be able to tell across a street which question is about to
			-- be asked of you, and the heaviest hitter reading as the heaviest body is the
			-- cheapest possible way to say it.
			heightScale = 1.09,
			widthScale = 1.12,
			headScale = 1,
			proportionScale = 1,
			bodyTypeScale = 1,
			shirtAssetId = NO_ASSETS.shirtAssetId,
			pantsAssetId = NO_ASSETS.pantsAssetId,
			hairAssetId = NO_ASSETS.hairAssetId,
		},
		ageYears = 31,
		-- Tougher than the others, because the fight against him is long: the answer is
		-- to wait for a slow tell, and waiting has to be worth doing more than twice.
		footingScale = 1.25,
		-- Enormous. Nobody should ever fail to see this coming, and a player who does see
		-- it coming and still blocks should feel that they chose wrong rather than that
		-- the game was quick.
		windSeconds = 1.4,
		-- The hardest hit in the file, and hard enough that GuardedFootingShare still
		-- stings through a block. Blocking a brawler is survival, not an answer.
		strikeFooting = 20,
		-- The longest recovery, which is the reward for reading him. This number and
		-- windSeconds are the same design decision seen from both ends.
		recoverSeconds = 0.9,
		-- Barely ever. He is here to be punished, and a defensive brawler would just be
		-- a slower boxer.
		guardChance = 0.1,
		guardSeconds = 0.8,
		restSeconds = 0.7,
	},
	{
		id = "scrapper",
		name = "Scrapper",
		blurb = "Fast and constant. Hold guard, let the flurry spend itself, then take the gap.",
		body = {
			id = "fighter_scrapper",
			name = "Wex",
			gender = "female" :: Types.Gender,
			skinColor = Color3.fromRGB(154, 116, 88),
			heightScale = 0.94,
			widthScale = 0.93,
			headScale = 1,
			proportionScale = 1,
			bodyTypeScale = 1,
			shirtAssetId = NO_ASSETS.shirtAssetId,
			pantsAssetId = NO_ASSETS.pantsAssetId,
			hairAssetId = NO_ASSETS.hairAssetId,
		},
		ageYears = 24,
		-- Fragile. She has to be: an opponent this relentless who also took a long time
		-- to put down would simply outlast the stamina bar, and the fight would be
		-- decided by the pool rather than by the read.
		footingScale = 0.8,
		-- Half the brawler's tell. Deliberately inside the range where sidestepping is a
		-- gamble rather than a plan -- there is time to press guard and not much more,
		-- which is exactly the lesson.
		windSeconds = 0.55,
		-- Small enough that a guard turns the flurry into a stamina problem instead of a
		-- footing one, which is the whole reason guard is the right answer to her.
		strikeFooting = 8,
		recoverSeconds = 0.35,
		guardChance = 0.05,
		guardSeconds = 0.6,
		-- Almost none. The pressure is the personality.
		restSeconds = 0.2,
	},
	{
		id = "boxer",
		name = "Boxer",
		blurb = "Guards half the time. Only a charge held past the mark will break it.",
		body = {
			id = "fighter_boxer",
			name = "Ruiz",
			gender = "male" :: Types.Gender,
			skinColor = Color3.fromRGB(120, 88, 66),
			heightScale = 1.02,
			widthScale = 1.01,
			headScale = 1,
			proportionScale = 1,
			bodyTypeScale = 1,
			shirtAssetId = NO_ASSETS.shirtAssetId,
			pantsAssetId = NO_ASSETS.pantsAssetId,
			hairAssetId = NO_ASSETS.hairAssetId,
		},
		ageYears = 28,
		footingScale = 1,
		-- Right in the middle, and that is the difficulty: there is enough time to
		-- sidestep and enough time to guard, so neither is obviously correct and the
		-- player has to decide rather than react.
		windSeconds = 0.9,
		strikeFooting = 13,
		recoverSeconds = 0.5,
		-- The high one. Half his answers are a guard, so half the time the player is
		-- holding a charge into overcharge territory to break it -- and eating the near
		-- second of recovery that costs if he drops the guard and steps in first.
		guardChance = 0.5,
		guardSeconds = 1.4,
		restSeconds = 0.45,
	},
}

local byId: { [string]: FighterDef } = {}
for _, def in Fighters do
	if byId[def.id] ~= nil then
		error(`[AGES content] duplicate fighter id "{def.id}"`)
	end
	-- A wind-up shorter than the client's own redraw is a tell nobody can see, and it
	-- would present as an opponent who lands unavoidable hits rather than as a bad
	-- number. Checked here because it is the one value in the file that can be wrong in
	-- a way the fight cannot recover from.
	if def.windSeconds <= 0 then
		error(`[AGES content] fighter "{def.id}" has windSeconds {def.windSeconds}; it must be above zero or its strike lands with no tell`)
	end
	if def.footingScale <= 0 then
		error(`[AGES content] fighter "{def.id}" has footingScale {def.footingScale}; it must be above zero or they start the fight already down`)
	end
	byId[def.id] = def
end

if #Fighters == 0 then
	error("[AGES content] there are no fighters, so nobody could ever be squared up to")
end

return {
	All = Fighters,
	ById = byId,
	-- Who turns up when nothing said. The brawler, because their tell is the one that
	-- teaches the mechanic, and the first fight a player is offered is a tutorial
	-- whether or not it is labelled one.
	Default = Fighters[1],
}
