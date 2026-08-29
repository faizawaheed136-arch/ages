--!strict
-- What the player has got good at. One cumulative XP number per discipline, a shared
-- ladder over the top of it, and a push to the client whenever either moves.
--
-- This service does not decide when anything is earned. It has no tick, no proximity
-- check and no timer, on purpose: every award in the game comes from a service that
-- has just finished *judging* something the player did -- a sweep hit landing in the
-- sweet band, a lesson answer being right, a bout being taken, a canvas being signed.
-- That is the whole design constraint. The moment this file grows a loop that awards
-- XP to whoever is standing near a machine, skills stop being a record of play and
-- start being a record of attendance, and the game already has one number like that
-- it is trying to get rid of.
--
-- The corollary is that `Award` is the entire public surface besides reads. It is
-- deliberately hard to call by accident and deliberately impossible to call in a way
-- that pays for time: it takes a flat amount, clamps it, and has no concept of how
-- long anything took.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local DataService = require(script.Parent.DataService)

type LifeData = Types.LifeData
type SkillState = Types.SkillState
type Player = Players.Player

local SkillService = {}

local SKILLS = Config.Skills
local SKILLS_UPDATED = Remotes.Get("SkillsUpdated")

-- Built once from Config so that an award against a name nobody defined is caught by
-- a lookup rather than by silently growing a row the menu will never draw. A skill id
-- is content, and content errors in this tree announce themselves.
local DEFINED: { [string]: { id: string, label: string, earnedBy: string, color: Color3 } } = {}
for _, definition in SKILLS.Definitions do
	DEFINED[definition.id] = definition
end

local function lifeDataFor(player: Player): LifeData?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return Lives.Active(profile.Data)
end

-- Set by WorkService, not required by it. This file has no idea what a job is and
-- must stay that way -- WorkService already requires SkillService to read the athlete
-- ladder's `minSkill` gate, and a require back the other way would be a cycle over
-- nothing this file needs. A setter is the same fix `FightService.SetWitnessedHandler`
-- and `BountyService.SetArrestedHandler` use for the identical shape of problem: see
-- the comment on FightService's wiring in init.server.luau.
local levelUpHandler: ((Player, string, number, number) -> ())? = nil

-- Called once, from init.server.luau, after both services have started.
function SkillService.SetLevelUpHandler(handler: (Player, string, number, number) -> ())
	levelUpHandler = handler
end

-- Which rung a given XP total stands on, and where the next one begins.
--
-- A linear walk rather than a binary search, and it stays that way: the ladder is
-- eight entries long and this runs once per skill per push. Reaching for a search
-- here would trade nothing measurable for a fencepost bug in a table that has to be
-- exactly right or every bar in the panel draws at the wrong fill.
local function bandFor(xp: number): (number, string, number, number?)
	local levels = SKILLS.Levels
	local index = 1
	for position, band in levels do
		if xp >= band.atXp then
			index = position
		else
			break
		end
	end

	local current = levels[index]
	-- Not named `next`: that is a Lua global, and shadowing it in a file that iterates
	-- tables is the kind of thing that works until somebody adds a `pairs` below.
	local above = levels[index + 1]
	return current.level, current.name, current.atXp, if above ~= nil then above.atXp else nil
end

local function stateFor(life: LifeData): { SkillState }
	local states: { SkillState } = {}
	-- Iterated over Config rather than over the save, so the panel lists every
	-- discipline in a fixed order including the ones at zero. A skills screen that
	-- only shows what you have already done cannot tell you what there is to do.
	for _, definition in SKILLS.Definitions do
		local xp = life.skillXp[definition.id] or 0
		local level, levelName, bandFloorXp, nextLevelXp = bandFor(xp)
		table.insert(states, {
			id = definition.id,
			label = definition.label,
			earnedBy = definition.earnedBy,
			color = definition.color,
			level = level,
			levelName = levelName,
			xp = xp,
			bandFloorXp = bandFloorXp,
			nextLevelXp = nextLevelXp,
		})
	end
	return states
end

local function push(player: Player, life: LifeData)
	SKILLS_UPDATED:FireClient(player, {
		skills = stateFor(life),
		soccerCareer = life.soccerCareer,
		basketballCareer = life.basketballCareer,
		volleyballCareer = life.volleyballCareer,
	} :: Types.SkillsState)
end

-- Hand a player XP in one discipline for one thing they just did.
--
-- Returns the level before and the level after, so a caller that wants to celebrate a
-- promotion can tell one happened without reading the ladder itself. Nobody needs the
-- XP total back: the number that means something to a player is the rung, and a caller
-- that starts making decisions on raw XP is a second copy of the curve waiting to
-- disagree with this one.
--
-- `reason` is not stored. It is here because an award with no sayable reason is
-- exactly the kind of award this service exists to prevent, and a caller forced to
-- write one down has to admit at the call site what was judged.
function SkillService.Award(player: Player, skillId: string, xp: number, reason: string): (number, number)
	local definition = DEFINED[skillId]
	if definition == nil then
		error(
			`SkillService.Award: no skill "{skillId}" ({reason}). Add it to Config.Skills.Definitions or fix the id at the call site.`
		)
	end

	local life = lifeDataFor(player)
	if life == nil then
		return 0, 0
	end

	-- Dead lives do not improve. Worth the check rather than trusting callers: several
	-- of the services that award here resolve an outcome a beat after the thing that
	-- caused it, and a bout whose last punch landed as the player died would otherwise
	-- pay into a life that has finished.
	if not life.alive then
		return 0, 0
	end

	if xp <= 0 then
		return 0, 0
	end

	local before = life.skillXp[skillId] or 0
	local granted = math.min(math.floor(xp), SKILLS.MaxPerAward)
	local after = before + granted
	life.skillXp[skillId] = after

	push(player, life)

	local beforeLevel = bandFor(before)
	local afterLevel = bandFor(after)

	-- Fired on every award that actually crosses a rung, not on every award -- most
	-- reps land inside the band they were already in, and a handler woken up on every
	-- one of those would be doing the threshold check itself just to throw the answer
	-- away. `afterLevel > beforeLevel` is that check, done once, here, for every caller.
	if afterLevel > beforeLevel and levelUpHandler ~= nil then
		levelUpHandler(player, skillId, beforeLevel, afterLevel)
	end

	return beforeLevel, afterLevel
end

-- The same read as `LevelOf`, off a `LifeData` directly rather than a `Player`. Split
-- out for callers that already have the data in hand and nothing else -- WorkService's
-- `hireRefusalFor` is the first of these, checking the athlete ladder's `minSkill`
-- gate against a life it was already handed, with no `Player` anywhere in the call. A
-- second copy of the band walk here would be exactly the kind of curve that drifts
-- from this one; there is one XP-to-level rule in the file and both entry points read
-- it the same way.
function SkillService.LevelOfData(life: LifeData, skillId: string): number
	local level = bandFor(life.skillXp[skillId] or 0)
	return level
end

-- The rung a player stands on in one discipline, for anything that wants to gate on
-- it. Zero for a player with no profile, no live life, or no practice -- all three of
-- which mean the same thing to a caller asking "are they any good at this yet".
function SkillService.LevelOf(player: Player, skillId: string): number
	local life = lifeDataFor(player)
	if life == nil then
		return 0
	end
	return SkillService.LevelOfData(life, skillId)
end

-- Re-send the whole panel. Called by anything that changed a life wholesale rather
-- than one skill at a time -- a new life beginning, a profile finishing its load -- and
-- also by SoccerService.recordCareer, the one place `soccerCareer` changes: that field
-- rides along on this same push (see Types.SkillsState) rather than behind SoccerUpdated,
-- which only reaches a player standing near the pitch, and the menu's Soccer Skills
-- section needs to read a whole life's tally from anywhere in the town.
function SkillService.Push(player: Player)
	local life = lifeDataFor(player)
	if life == nil then
		return
	end
	push(player, life)
end

-- Every discipline on one line, for /skill. Reads the same `stateFor` the client is
-- pushed rather than re-deriving anything, so a bar that draws wrong and a line that
-- prints wrong are guaranteed to be the same bug rather than two.
function SkillService.Describe(player: Player): string
	local life = lifeDataFor(player)
	if life == nil then
		return "no life"
	end

	local lines: { string } = {}
	for _, skill in stateFor(life) do
		local toward = if skill.nextLevelXp ~= nil then `/{skill.nextLevelXp}` else " (capped)"
		table.insert(lines, `{skill.label}: {skill.levelName} (lv{skill.level}) {skill.xp}{toward}`)
	end
	return table.concat(lines, ", ")
end

function SkillService:Init()
	Players.PlayerAdded:Connect(function(player: Player)
		SkillService.Push(player)
	end)
end

function SkillService:Start()
	-- No tick, and this is load-bearing rather than an omission. See the header: a
	-- background loop is the one shape this service must never take.
end

return SkillService
