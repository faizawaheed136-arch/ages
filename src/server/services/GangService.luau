--!strict
-- Who you run with.
--
-- Everything in the crime tree below this is solitary. One player, one drawer, one alarm,
-- one pursuit -- a second person in the room is at best a convenience. This is the layer
-- that makes them matter, and the design problem it has to solve first is that the
-- standard version of this feature is a name tag, a chat channel, and a number that goes
-- up when you commit crimes. That is the idle payout pad wearing a jacket.
--
-- Two rules keep it from being that, and both are borrowed from elsewhere in this tree
-- rather than invented here.
--
-- **Standing is earned; rank is given.** Ties.luau argues that friendship cannot be a bond
-- threshold, because then "everybody you were reliably nice to would become your friend on
-- some birthday you were not paying attention on, and the game would be telling you about
-- your own life after the fact". A rank that auto-promotes at 400 points has exactly that
-- defect. So standing accrues quietly from work you did, and the rung is only ever handed
-- over by a person, off a panel, in a moment you walked across the city to be in. Reaching
-- the number is necessary and never sufficient. That is the entire reason `promotable` is
-- computed here and not on the client.
--
-- **The colors are worn, and they cut both ways.** Joining puts a bright band on your head.
-- It is what makes a room of mixed players and NPCs legible at a glance -- and it is what a
-- witness describes, so it multiplies every point of heat anything gives you while it is
-- on. Wearing your colors into a bank is a decision, and taking them off to do it is
-- another one. If the band were free, gangs would be a hat.
--
-- **What this file does not do.** It does not award standing for crimes; the crimes do
-- that, by calling `Credit` on their way past, which is why nothing here requires
-- TheftService or BankService. It does not decide heat (BountyService), and it deliberately
-- does not require BountyService either -- it reads `data.bounty` straight off the profile,
-- because BountyService needs to call *in* here on arrest and the two cannot both point at
-- each other.
--
-- **Part 2, NPC crew, is built.** A rung that carries slots (`Config.Gangs.Crew.SlotsByRank`,
-- absent below "name" on purpose) can bring somebody in off the boss's own panel, and
-- that somebody is a persisted `GangCrewMember` with a nerve rating that only ever rises --
-- see `creditStanding`, which is the one place both standing and nerve move together, on
-- the same work, for the same reason.
--
-- **Part 3, calling a job, has its first slice: sending your crew to the bank's alarm.**
-- `GangService.CrewFor`/`CastMemberFor` are the whole of this file's part in it --
-- BankService owns the actual role table (one seat, the alarm) and the roll against
-- nerve, because that room already was a shared, per-place thing rather than a per-player
-- one, which is what let a second body stand in it without a new state machine. A role is
-- still not a field on `GangCrewMember`: it is a fact about one robbery, held on
-- BankService's own `Room`, not a fact about the person.
--
-- **Theft's crew role shipped too, and it is not Bank's shape reused.** The till has no
-- second seat, only two independent attentions -- the clerk and the camera -- and
-- TheftService's own header is explicit that reading them *is* the activity ("this cannot
-- be played by counting. It has to be watched."). A helper who could stand in for either
-- would be a body that plays the mini-game for you, which is the thing Bank's crew helper
-- was careful never to be -- it only ever covers a second *location*, not a second
-- *attention*. So Theft's is a lookout instead: it never reads the clerk or the camera
-- for you, it only softens what one mistake costs, once per robbery -- see
-- TheftService's own `spawnLookout`/`tickLookout` and Config.Gangs.Jobs's
-- `TillCoverFailChance` notes.
--
-- **Territory shipped -- see TerritoryService.** The gangs' sides of the city
-- (content/Gangs.luau) are read now: crossing into a rival's on foot in your colors costs
-- standing once, getting back out pays it once, scaled by depth. This file still has
-- nothing to do with that directly -- TerritoryService reads `side` and calls back into
-- `Credit`/`Debit` the same way the crime services do -- but the comment that used to
-- live here calling territory unbuilt was wrong the day this line was written and is
-- corrected rather than left to keep misleading the next read of this file.
--
-- **Still deferred, and still on purpose:** the rest of calling a job -- a gang-wide crew
-- roster real players can join rather than each caller's own three recruits, a caller
-- assigning roles to people who are not their own recruits, and the vault's *drawer* seat
-- itself (Bank's crew helper only ever takes the alarm; nobody has asked a crew member to
-- hold the vault open). Each of those is a real matchmaking or ownership question this
-- file has deliberately not answered yet, not a gap nobody noticed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Interact = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Interact"))

local DataService = require(script.Parent.DataService)
local NPCService = require(script.Parent.NPCService)
local PlaceService = require(script.Parent.PlaceService)
local SkillService = require(script.Parent.SkillService)

local Cast = require(script.Parent.Parent.content.Cast)
local Colors = require(script.Parent.Parent.world.Colors)
local Gangs = require(script.Parent.Parent.content.Gangs)
local Public = require(script.Parent.Parent.content.Public)

type LifeData = Types.LifeData
type GangDef = Types.GangDef
type GangRankDef = Types.GangRankDef
type GangState = Types.GangState
type GangPanel = Types.GangPanel
type GangCrewMember = Types.GangCrewMember
type OfferedChoice = Types.OfferedChoice
type Visitor = NPCService.Visitor
type CastMember = Types.CastMember

local GANGS = Config.Gangs

local GangUpdatedRemote = Remotes.Get("GangUpdated")
local GangPanelUpdatedRemote = Remotes.Get("GangPanelUpdated")
local RequestGangOpenRemote = Remotes.Get("RequestGangOpen")
local RequestGangChoiceRemote = Remotes.Get("RequestGangChoice")
local RequestGangColorsRemote = Remotes.Get("RequestGangColors")

-- One boss standing at one place point, shared by everybody on the server.
--
-- Deliberately not per-player, unlike the family NPCs PeopleService spawns. A gang boss is
-- a fixture of the town rather than a person in your life: two players walking into the
-- same garage have to be looking at the same Marisol, or the moment one of them joins in
-- front of the other the world stops agreeing with itself.
type Post = {
	gangId: string,
	visitor: Visitor?,
	dots: Interact.InteractHandle?,
	spawning: boolean,
}

-- Per-player bookkeeping that is not worth persisting.
type Watch = {
	-- The highest bounty seen since the last time it was at zero. This is how an escape is
	-- noticed: heat that climbed to something real and then came all the way down without
	-- an arrest in between. Session-only, and safe to be -- `bounty` itself is persisted,
	-- so a player who rejoins mid-chase has their peak seeded from where they actually are
	-- rather than from nothing.
	peakBounty: number,
	-- Which boss they currently have a panel open with, or nil. Cleared when they walk out
	-- of range, which is what makes the panel a conversation rather than a menu.
	atGangId: string?,
	notice: string?,
}

local posts: { [string]: Post } = {}
local watches: { [Player]: Watch } = {}
local pushed: { [Player]: string } = {}
local pushedPanel: { [Player]: string } = {}
local enabled = true

local function dataFor(player: Player): LifeData?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return Lives.Active(profile.Data)
end

local function watchFor(player: Player): Watch
	local watch = watches[player]
	if watch == nil then
		watch = { peakBounty = 0, atGangId = nil, notice = nil }
		watches[player] = watch
	end
	return watch
end

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root ~= nil and root:IsA("BasePart") then root.Position else nil
end

-- The ladder, resolved.
--
-- Walks the config rungs in order and returns the last one the standing clears. Written as
-- a scan rather than as a stored index because the ladder is content: inserting a rung
-- between two existing ones must not silently renumber every player who already holds one.
local function rankFor(standing: number): GangRankDef
	local held = GANGS.Ranks[1]
	for _, rung in GANGS.Ranks do
		if standing >= rung.standing then
			held = rung
		end
	end
	return held
end

local function rankById(rankId: string?): GangRankDef?
	if rankId == nil then
		return nil
	end
	for _, rung in GANGS.Ranks do
		if rung.id == rankId then
			return rung
		end
	end
	return nil
end

-- The rung above the one held, or nil at the top.
local function nextRank(rankId: string?): GangRankDef?
	local heldIndex = 0
	for index, rung in GANGS.Ranks do
		if rung.id == rankId then
			heldIndex = index
			break
		end
	end
	return GANGS.Ranks[heldIndex + 1]
end

local function standingIn(data: LifeData, gangId: string): number
	return data.gangStanding[gangId] or 0
end

-- How many crew slots the rung held in this gang carries, or zero for both a rung with
-- no entry and for holding no rung at all -- `GANGS.Crew.SlotsByRank` omits the bottom
-- two rungs for exactly that reason, see its own comment.
local function crewSlotsFor(data: LifeData, gangId: string): number
	if data.gangId ~= gangId then
		return 0
	end
	return GANGS.Crew.SlotsByRank[data.gangRankId or ""] or 0
end

-- A crew id that is not already in use by this life's crew. Collision is vanishingly
-- unlikely at three slots and six digits, but the loop is nearly free and turns "a
-- client keys a list on this" from a hope into a guarantee.
local function newCrewId(data: LifeData): string
	while true do
		local id = `crew_{math.random(100000, 999999)}`
		local taken = false
		for _, member in data.gangCrew do
			if member.id == id then
				taken = true
				break
			end
		end
		if not taken then
			return id
		end
	end
end

local function crewIndexOf(data: LifeData, crewId: string): number?
	for index, member in data.gangCrew do
		if member.id == crewId then
			return index
		end
	end
	return nil
end

-- Whether the boss would hand over the next rung right now.
--
-- Three questions, not one, and the third is the reason this is a function rather than a
-- comparison at the call site: the top rung asks that you hold it nowhere else, which is
-- the same device Ties.luau uses to cap `closest` at one person. Since a life can only be
-- in one gang at a time today, that check reads as trivially true -- it is written anyway,
-- because the day a second gang can hold your standing is the day it stops being trivial
-- and nobody will remember to come back here.
local function promotableTo(data: LifeData, gangId: string): GangRankDef?
	if data.gangId ~= gangId then
		return nil
	end
	local upcoming = nextRank(data.gangRankId)
	if upcoming == nil then
		return nil
	end
	if standingIn(data, gangId) < upcoming.standing then
		return nil
	end
	if upcoming.oneGangOnly and data.gangId ~= nil and data.gangId ~= gangId then
		return nil
	end
	return upcoming
end

local function noticeFor(player: Player, text: string)
	watchFor(player).notice = text
end

-- Forward declarations.
--
-- `creditStanding` is called by `checkEscape` and defined below it, because it needs
-- `push`, which needs `stateFor`, which needs the ladder helpers above. Declared here
-- rather than left to resolve at runtime: a name used with no `local` in scope compiles to
-- a global read in Lua, so the version of this file that simply called it would have been
-- legal Luau, would have built, and would have died with "attempt to call a nil value" the
-- first time anybody got away from the police.
local creditStanding: (player: Player, points: number, reason: string) -> number
local push: (player: Player) -> ()

-- How long until this life may join another gang, in seconds, or zero if it may now.
local function rejoinWaitFor(data: LifeData): number
	local leftAt = data.leftGangAt
	if leftAt == nil then
		return 0
	end
	local waited = data.secondsSinceAgeUp - leftAt
	-- A birthday resets `secondsSinceAgeUp`, so a stamp taken before one reads as being in
	-- the future. That is not corruption and must not be treated as a very long wait: the
	-- window has plainly elapsed if a whole year turned over inside it.
	if waited < 0 then
		return 0
	end
	return math.max(GANGS.RejoinSeconds - waited, 0)
end

local function stateFor(player: Player): GangState?
	local data = dataFor(player)
	if data == nil then
		return nil
	end
	local gangId = data.gangId
	if gangId == nil then
		return nil
	end
	local def = Gangs.ById[gangId]
	if def == nil then
		-- The gang was deleted from content while somebody was in it. Reads as not being in
		-- one rather than erroring, because the alternative is a player who cannot load.
		return nil
	end
	local held = rankById(data.gangRankId) or GANGS.Ranks[1]
	local upcoming = nextRank(held.id)
	local watch = watches[player]
	return {
		gangId = gangId,
		name = def.name,
		color = def.color,
		rankId = held.id,
		rankLabel = held.label,
		nextLabel = if upcoming ~= nil then upcoming.label else nil,
		standing = standingIn(data, gangId),
		nextStanding = if upcoming ~= nil then upcoming.standing else nil,
		promotable = promotableTo(data, gangId) ~= nil,
		wearing = data.wearingColors,
		crew = data.gangCrew,
		crewSlots = crewSlotsFor(data, gangId),
		notice = if watch ~= nil then watch.notice else nil,
	}
end

-- The push-digest pattern, as everywhere else: name every drawn field, compare, fire only
-- on change. Standing moves in bursts -- a vault pays forty-five points in an instant and
-- then nothing for a minute -- so a fixed-rate push would spend most of its traffic
-- resending a number that had not moved.
function push(player: Player)
	local state = stateFor(player)
	local digest = "none"
	if state ~= nil then
		local crewBits: { string } = {}
		for _, member in state.crew do
			table.insert(crewBits, `{member.id}:{math.floor(member.nerve)}`)
		end
		digest = `{state.gangId}|{state.rankId}|{math.floor(state.standing)}|{tostring(state.promotable)}`
			.. `|{tostring(state.wearing)}|{table.concat(crewBits, ",")}|{tostring(state.notice)}`
	end
	if pushed[player] == digest then
		return
	end
	pushed[player] = digest
	GangUpdatedRemote:FireClient(player, state)
	-- Cleared after it has been sent, not after it has been shown: a notice that stayed in
	-- the digest would keep the panel redrawing the same line forever, and one that was
	-- cleared before the push would never arrive at all.
	local watch = watches[player]
	if watch ~= nil then
		watch.notice = nil
	end
end

-- What the boss in front of you says, and the rows under it.
local function panelFor(player: Player, gangId: string): GangPanel?
	local data = dataFor(player)
	if data == nil then
		return nil
	end
	local def = Gangs.ById[gangId]
	if def == nil then
		return nil
	end
	local boss = Cast.ById[def.bossCastId]
	local bossName = if boss ~= nil then boss.name else def.name

	local offers: { OfferedChoice } = {}
	local reply = def.pitch
	local replyGood = true

	if data.gangId == gangId then
		local held = rankById(data.gangRankId) or GANGS.Ranks[1]
		local upcoming = promotableTo(data, gangId)
		if upcoming ~= nil then
			reply = `You have done enough. You are {upcoming.label} now, if you want it.`
			table.insert(offers, { id = `take_{upcoming.id}`, label = `Take "{upcoming.label}"`, cost = nil, note = nil, locked = false })
		else
			local ahead = nextRank(held.id)
			if ahead == nil then
				reply = `There is nothing above you here. The {def.name} is yours to call.`
			else
				-- The gap, said as a number. A boss who only ever says "not yet" is a boss
				-- the player has no way to plan against, and the whole point of a rung
				-- being conferred rather than crossed is that the player chose to come and
				-- ask -- which is only a choice if the answer tells them something.
				local short = math.max(ahead.standing - standingIn(data, gangId), 0)
				reply = `You are {held.label}. {math.floor(short)} more and we will talk about "{ahead.label}".`
				replyGood = false
			end
		end

		-- Crew rows. Zero slots at the two lower rungs means this whole block draws
		-- nothing for a hanger-on or a hand, which is the rung ladder saying it rather
		-- than a comment saying it -- see GangState.crew's own note.
		local slots = crewSlotsFor(data, gangId)
		if slots > 0 then
			for _, member in data.gangCrew do
				table.insert(offers, {
					id = `dismiss_{member.id}`,
					label = `Let {member.name} go`,
					cost = nil,
					note = `nerve {math.floor(member.nerve)}`,
					locked = false,
				})
			end
			if #data.gangCrew < slots then
				table.insert(offers, {
					id = "recruit",
					label = "Bring somebody in",
					cost = nil,
					note = `{#data.gangCrew}/{slots}`,
					locked = false,
				})
			end
		end

		table.insert(offers, { id = "leave", label = "Walk away from them", cost = nil, note = "keeps your standing", locked = false })
	elseif data.gangId ~= nil then
		-- Somebody else's. Deliberately has no rows at all: a rival boss you can still do
		-- business with is not a rival, and an offer to defect would make the choice of
		-- gang reversible at the exact moment it is supposed to have cost something.
		local mine = Gangs.ById[data.gangId]
		reply = `You are wearing {if mine ~= nil then mine.name else "somebody else's"} colors. We have nothing for you.`
		replyGood = false
	else
		local wait = rejoinWaitFor(data)
		if wait > 0 then
			reply = `You just walked away from a gang. Come back when you know what you want.`
			replyGood = false
			table.insert(offers, {
				id = "join",
				label = `Run with {def.name}`,
				cost = nil,
				note = `{math.ceil(wait)}s`,
				locked = true,
			})
		else
			table.insert(offers, { id = "join", label = `Run with {def.name}`, cost = nil, note = nil, locked = false })
		end
	end

	return {
		gangId = gangId,
		name = def.name,
		color = def.color,
		bossName = bossName,
		reply = reply,
		replyGood = replyGood,
		offers = offers,
	}
end

local function pushPanel(player: Player)
	local watch = watches[player]
	local gangId = if watch ~= nil then watch.atGangId else nil
	local panel = if gangId ~= nil then panelFor(player, gangId) else nil
	local digest = "none"
	if panel ~= nil then
		local ids: { string } = {}
		for _, offer in panel.offers do
			-- `locked` is in the digest beside the id because a row that becomes takeable
			-- while the player stands there -- the rejoin window elapsing -- reads
			-- identically otherwise, and the panel must not keep drawing it greyed out.
			table.insert(ids, `{offer.id}:{tostring(offer.locked)}:{tostring(offer.note)}`)
		end
		digest = `{panel.gangId}|{panel.reply}|{tostring(panel.replyGood)}|{table.concat(ids, ",")}`
	end
	if pushedPanel[player] == digest then
		return
	end
	pushedPanel[player] = digest
	GangPanelUpdatedRemote:FireClient(player, panel)
end

-- Colors on the head, or off it.
--
-- Runs every tick for every player rather than only on the frames something changed, and
-- that is the point: a character that died and respawned has no band on it, and the only
-- thing that reliably knows a respawn happened is looking. `Colors.Apply` is idempotent
-- and cheap on the common path -- two comparisons and a return -- so the cost of asking
-- twice a second is far below the cost of a member who quietly lost their colors.
local function applyColors(player: Player, data: LifeData)
	local character = player.Character
	if character == nil then
		return
	end
	local gangId = data.gangId
	if gangId == nil or not data.wearingColors then
		Colors.Clear(character)
		return
	end
	local def = Gangs.ById[gangId]
	if def == nil then
		Colors.Clear(character)
		return
	end
	Colors.Apply(character, def.color)
end

-- Notices an escape.
--
-- An escape is heat that got real and then came all the way down with nobody arrested. The
-- arrest half is handled by `OnArrest` clearing the peak before this can ever see it, which
-- is why there is no "were they arrested" flag here: by the time the bounty reads zero
-- after an arrest, the peak reads zero too and the condition below cannot fire.
local function checkEscape(player: Player, data: LifeData, watch: Watch)
	if data.bounty > watch.peakBounty then
		watch.peakBounty = data.bounty
		return
	end
	if data.bounty > 0 or watch.peakBounty <= 0 then
		return
	end
	local peak = watch.peakBounty
	watch.peakBounty = 0
	if peak < GANGS.Earn.GotAwayNeedsBounty then
		return
	end

	-- Nerve, before the gang check and deliberately outside it. The standing below is a
	-- gang paying attention to one of its own; this is the player having got away with
	-- something, which is true whether anyone was watching. Gating the only discipline
	-- earned outside a room behind membership would make Nerve a members-only skill and
	-- leave a player who never joined with a row that can never move.
	SkillService.Award(player, "nerve", Config.Skills.Awards.GotAway, "got away clean")

	if data.gangId == nil then
		return
	end
	creditStanding(player, GANGS.Earn.GotAway, "got away clean")
end

local function tickPlayer(player: Player)
	local data = dataFor(player)
	if data == nil then
		return
	end
	applyColors(player, data)

	local watch = watchFor(player)
	checkEscape(player, data, watch)

	-- Standing in front of a boss is what keeps a panel open, and walking away is what
	-- closes it. Checked here rather than left to the client so that a client which simply
	-- never sends a close still loses the panel the moment it walks off.
	local atGangId = watch.atGangId
	if atGangId ~= nil then
		local post = posts[atGangId]
		local visitor = if post ~= nil then post.visitor else nil
		local at = characterPosition(player)
		if visitor == nil or visitor.gone() or at == nil then
			watch.atGangId = nil
		else
			local away = (visitor.at() - at)
			if math.sqrt(away.X * away.X + away.Z * away.Z) > Config.Interact.RangeStuds then
				watch.atGangId = nil
			end
		end
	end

	push(player)
	pushPanel(player)
end

local function despawnPost(post: Post)
	if post.dots ~= nil then
		post.dots.Destroy()
		post.dots = nil
	end
	if post.visitor ~= nil then
		post.visitor.destroy()
		post.visitor = nil
	end
end

-- Stands a boss up at their place point.
--
-- Yields on a web call inside NPCService.Spawn, so everything after it is re-checked. The
-- `player` argument exists only for the peer-age rule NPCService applies to strangers, and
-- passing an explicit age makes it irrelevant -- which is what lets a boss be a fixture of
-- the town rather than somebody's personal NPC.
local function spawnPost(player: Player, post: Post)
	if post.visitor ~= nil or post.spawning then
		return
	end
	local def = Gangs.ById[post.gangId]
	if def == nil then
		return
	end
	local member = Cast.ById[def.bossCastId]
	local place = PlaceService.Find(def.bossPlaceId)
	if member == nil or place == nil then
		return
	end

	post.spawning = true
	task.spawn(function()
		local at = place.part.CFrame
		local visitor = NPCService.Spawn(player, member, at, GANGS.BossAgeYears)
		post.spawning = false
		if visitor == nil then
			return
		end
		if post.visitor ~= nil then
			visitor.destroy()
			return
		end
		post.visitor = visitor
		-- The boss wears it too, and this is not decoration. The band is the whole answer to
		-- "which of the people in this room is the one I came for", and a gang boss standing
		-- bare-headed would be the one person in the system you have to walk up to and read a
		-- nameplate to identify -- in a game whose stated rule is that gangs are legible from
		-- across a street. Applied once here rather than on a tick because an NPC rig does not
		-- respawn: if the model goes, the post goes with it and is rebuilt from scratch.
		if not Colors.Apply(visitor.model, def.color) then
			warn(`[AGES] could not band the {def.name} boss -- they will look like anybody else`)
		end
		local dots = Interact.Attach(visitor.model, {
			kind = "Boss",
			id = def.id,
			actionText = "Talk",
			objectText = member.name,
			nameplate = { name = member.name, age = GANGS.BossAgeYears },
		})
		if dots == nil then
			-- Worth saying out loud because the symptom is silent and looks like content: a
			-- person standing in a garage who can be circled forever and never spoken to,
			-- and therefore a gang that cannot be joined by anybody.
			warn(`[AGES] could not put dots over the {def.name} boss at "{def.bossPlaceId}"`)
		end
		post.dots = dots
	end)
end

-- Keeps the four standing.
--
-- Re-checked on a tick rather than spawned once at Start, because a boss can be lost --
-- streaming, a rig that failed to build, a visitor destroyed by something else -- and a
-- gang whose boss quietly vanished is a gang nobody can join with no error anywhere.
local function tickPosts()
	local anybody = Players:GetPlayers()[1]
	if anybody == nil then
		-- Nobody to build against. The bosses are torn down rather than left standing in an
		-- empty server: NPCService.Spawn needs a player, so the next join rebuilds them
		-- anyway, and leaving four rigs pathfinding around an empty town is pure cost.
		for _, post in posts do
			despawnPost(post)
		end
		return
	end
	for _, post in posts do
		local visitor = post.visitor
		if visitor ~= nil and visitor.gone() then
			despawnPost(post)
		end
		spawnPost(anybody, post)
	end
end

-- Award standing for something that helped.
--
-- The single seam every other system uses, and deliberately the only one: theft, the vault,
-- shared heat and escapes all arrive here, so the ladder has one place that decides what
-- work is worth and one place that clamps it. Callers pass what they did and how much of
-- it, never a rung.
--
-- Silently does nothing for a player who is not in a gang, which is most players most of
-- the time. That is not a failure worth reporting -- it is the ordinary case, and making
-- every crime in the game branch on gang membership before calling would put the same
-- three lines in five files.
function creditStanding(player: Player, points: number, reason: string): number
	if not enabled or points <= 0 then
		return 0
	end
	local data = dataFor(player)
	if data == nil then
		return 0
	end
	local gangId = data.gangId
	if gangId == nil then
		return 0
	end
	local before = standingIn(data, gangId)
	local after = before + points
	data.gangStanding[gangId] = after

	-- Steadier every time you pull work together, split across the crew rather than
	-- multiplied by its size -- see Config.Gangs.Crew.NerveGainPerPoint. Never decays:
	-- the same ratchet-only rule Ties.luau keeps for a bond, kept here for a crew.
	if #data.gangCrew > 0 then
		local gain = points * GANGS.Crew.NerveGainPerPoint
		for _, member in data.gangCrew do
			member.nerve = math.min(member.nerve + gain, GANGS.Crew.NerveMax)
		end
	end

	-- Said only when it crosses a rung, and said as an invitation rather than as a
	-- promotion. This is the moment the design turns on: the number is sufficient and the
	-- rung still is not given, so the line has to send the player to a person.
	--
	-- The reason is named in it because the alternative -- "your standing went up" -- is a
	-- progress bar talking, and the whole argument for conferring rungs face to face is
	-- that the player should be able to see which thing they did was the thing that
	-- counted.
	local upcoming = nextRank(data.gangRankId)
	if upcoming ~= nil and before < upcoming.standing and after >= upcoming.standing then
		local def = Gangs.ById[gangId]
		noticeFor(player, `They heard you {reason}. Go and see {if def ~= nil then def.name else "them"}.`)
	end

	push(player)
	return after
end

local GangService = {}

GangService.Credit = creditStanding

-- Standing lost, floored. Never takes a rung away: a rung was conferred in a moment by a
-- person, and deleting it later is the exact "telling you about your own life after the
-- fact" that conferring it face to face exists to prevent.
function GangService.Charge(player: Player, points: number, reason: string): number
	if not enabled or points <= 0 then
		return 0
	end
	local data = dataFor(player)
	if data == nil then
		return 0
	end
	local gangId = data.gangId
	if gangId == nil then
		return 0
	end
	local after = math.max(standingIn(data, gangId) - points, GANGS.Lose.Floor)
	data.gangStanding[gangId] = after
	noticeFor(player, `{reason}. Your standing took it.`)
	push(player)
	return after
end

-- Standing lost with a gang that is not yours.
--
-- Charge above can only ever reach the gang you run with, which was the right and only
-- shape while every loss in the game was something your own side held against you. It
-- cannot express the one TerritoryService needs: walking somebody else's side wearing
-- another band costs you with *them*, and you may well not be in a gang they would ever
-- speak to.
--
-- That standing is not idle. It is what a gang would ever offer you, so spending it is
-- spending a door -- run the west line often enough in eastern colors and the west is a
-- gang that will not take you. Deliberately has no rung logic and sends no notice about
-- rungs: this can only lower a number, and a rung once conferred is never taken back.
function GangService.ChargeIn(player: Player, gangId: string, points: number, reason: string): number
	if not enabled or points <= 0 then
		return 0
	end
	local data = dataFor(player)
	if data == nil then
		return 0
	end
	local after = math.max(standingIn(data, gangId) - points, GANGS.Lose.Floor)
	data.gangStanding[gangId] = after
	push(player)
	return after
end

-- Called by BountyService on the way through an arrest.
--
-- Does two things that must happen together: charges the standing, and clears the escape
-- peak so that the bounty dropping to zero as part of the arrest is not then read as
-- having got away with it. Splitting them would make an arrest pay out the largest award
-- in the table.
function GangService.OnArrest(player: Player)
	watchFor(player).peakBounty = 0
	GangService.Charge(player, GANGS.Lose.OnArrest, "Arrested")
end

-- Called by BankService when somebody leaves a room with the alarm still ringing and
-- somebody else still holding the vault. The one entry in the loss table that is about
-- another person rather than about the police.
function GangService.OnBailed(player: Player)
	GangService.Charge(player, GANGS.Lose.OnBailing, "You left them in there")
end

function GangService.IsMember(player: Player): boolean
	local data = dataFor(player)
	return data ~= nil and data.gangId ~= nil
end

-- Which gang somebody runs with, for anything that needs to tell two people apart. Nil for
-- most players.
function GangService.GangOf(player: Player): string?
	local data = dataFor(player)
	return if data ~= nil then data.gangId else nil
end

-- The color a body sent by this player's crew should wear. Nil for a life not currently in
-- a gang, which cannot happen for anyone who actually has crew to send -- crew is cleared
-- the moment you leave, see `leave` -- but a caller checking a body it is about to band
-- should not have to know that on faith.
function GangService.ColorOf(player: Player): Color3?
	local data = dataFor(player)
	if data == nil or data.gangId == nil then
		return nil
	end
	local def = Gangs.ById[data.gangId]
	return if def ~= nil then def.color else nil
end

-- Whether the band is actually on their head right now, which is not the same question as
-- whether they are in a gang: taking the colors off is a thing a member does on purpose.
-- Asked through Lives rather than read off the profile here so that every caller gets the
-- same two-part answer -- in a gang, and wearing it -- and none of them can forget the first
-- half. See Lives.WearingColors, which is where BountyService reads it from too.
function GangService.IsWearing(player: Player): boolean
	local data = dataFor(player)
	return data ~= nil and Lives.WearingColors(data)
end

-- Band on, band off.
--
-- The one piece of gang state a player changes with nobody present, and it is not a cosmetic
-- toggle: the colors multiply every point of heat anything gives you while they are on, so
-- this is the trade between being counted by your own side and being described by everybody
-- else.
--
-- Public because the remote handler and the debug command both want it and there is exactly
-- one correct sequence -- write, re-band the character, say so, push -- which is precisely
-- the kind of thing that gets half-copied into a second caller.
function GangService.SetColors(player: Player, want: boolean): boolean
	local data = dataFor(player)
	if data == nil or data.gangId == nil then
		return false
	end
	if data.wearingColors == want then
		return false
	end
	data.wearingColors = want
	applyColors(player, data)
	noticeFor(player, if want then "Colors on." else "Colors off. Nobody knows you.")
	push(player)
	return true
end

-- Who this player could send on a job right now. Empty for a life with no gang, no rank
-- that carries a slot, or nobody recruited into it -- almost everybody, almost always --
-- so a caller can check length rather than asking three separate questions first.
function GangService.CrewFor(player: Player): { GangCrewMember }
	local data = dataFor(player)
	if data == nil then
		return {}
	end
	return data.gangCrew
end

-- Gives a crew member a body to send on a job. A crew member has no persistent look of
-- their own, only a name and a nerve rating -- Part 2 deliberately stopped at that, see
-- this file's own header -- so this borrows whichever stranger content/Public would have
-- handed the bank's guard or the till's clerk and relabels it, the same anonymous-body
-- pool the rest of the crime tree already draws from.
function GangService.CastMemberFor(crew: GangCrewMember): CastMember
	local base = Public.Someone()
	return {
		id = crew.id,
		gender = base.gender,
		name = crew.name,
		skinColor = base.skinColor,
		heightScale = base.heightScale,
		widthScale = base.widthScale,
		headScale = base.headScale,
		proportionScale = base.proportionScale,
		bodyTypeScale = base.bodyTypeScale,
		shirtAssetId = base.shirtAssetId,
		pantsAssetId = base.pantsAssetId,
		hairAssetId = base.hairAssetId,
	}
end

local function join(player: Player, data: LifeData, def: GangDef)
	if data.gangId ~= nil then
		return
	end
	if rejoinWaitFor(data) > 0 then
		return
	end
	data.gangId = def.id
	-- The bottom rung, always, whatever standing is banked from a previous run with them.
	-- Standing is what they remember about you; the rung is what you currently are, and
	-- walking back in at the top because you used to be there would make leaving free.
	data.gangRankId = GANGS.Ranks[1].id
	data.wearingColors = true
	data.leftGangAt = nil
	noticeFor(player, `You run with {def.name}. Wear it.`)
end

local function leave(player: Player, data: LifeData, def: GangDef)
	if data.gangId ~= def.id then
		return
	end
	data.gangId = nil
	data.gangRankId = nil
	data.wearingColors = false
	-- Cleared, unlike gangStanding. A crew is people who chose to run with *this*
	-- membership -- see GangCrewMember's own comment -- and carrying them across into
	-- whatever is joined next would mean somebody else's boss inherited a crew they
	-- never brought in.
	data.gangCrew = {}
	-- Stamped so the rejoin window has something to measure from. Standing is left exactly
	-- where it was, on purpose: leaving does not make the work not have happened, and a
	-- gang you left at nine hundred should not take you back as a stranger.
	data.leftGangAt = data.secondsSinceAgeUp
	noticeFor(player, `You are nobody's now.`)
	local character = player.Character
	if character ~= nil then
		Colors.Clear(character)
	end
end

-- Brings somebody in. The boss's act, not a purchase -- see Config.Gangs.Crew's own
-- header -- so the only checks are the ones that make a slot real: you have to be in
-- this gang, and you have to have room.
local function recruit(player: Player, data: LifeData, def: GangDef)
	if data.gangId ~= def.id then
		return
	end
	local slots = crewSlotsFor(data, def.id)
	if #data.gangCrew >= slots then
		noticeFor(player, "Nobody else to bring in. You are full up.")
		return
	end
	local name = Gangs.CrewNames[math.random(1, #Gangs.CrewNames)]
	local member: GangCrewMember = { id = newCrewId(data), name = name, nerve = GANGS.Crew.NerveStart }
	table.insert(data.gangCrew, member)
	noticeFor(player, `{name} is running with you now.`)
end

-- Lets somebody go. Always available to the player who holds the crew, unlike
-- recruiting -- bringing somebody in is the boss doing you a favour, but cutting them
-- loose is your own call, and gating that behind a conversation would mean a slot
-- could be stuck full of somebody the player no longer wanted between two visits to a
-- garage.
local function dismiss(player: Player, data: LifeData, def: GangDef, crewId: string)
	if data.gangId ~= def.id then
		return
	end
	local index = crewIndexOf(data, crewId)
	if index == nil then
		return
	end
	local member = table.remove(data.gangCrew, index)
	if member ~= nil then
		noticeFor(player, `{member.name} is not running with you anymore.`)
	end
end

local function takeRank(player: Player, data: LifeData, def: GangDef, rankId: string)
	local upcoming = promotableTo(data, def.id)
	-- Re-checked against the server's own answer rather than trusted from the row that was
	-- clicked. A client that could name its own rung would be a client that promotes
	-- itself, and the id is compared as well as the eligibility so that a stale panel --
	-- one drawn before somebody else's tick moved the standing -- cannot cash in a rung
	-- that is no longer the next one.
	if upcoming == nil or upcoming.id ~= rankId then
		noticeFor(player, "Not yet.")
		return
	end
	data.gangRankId = upcoming.id
	noticeFor(player, `You are {upcoming.label} now.`)
end

-- Puts somebody in a gang without the walk and the conversation, so the ladder can be tested
-- more than once in a life.
--
-- Goes through the same `join` the panel does rather than writing the two fields itself, and
-- that is the whole point of it: it still refuses somebody already in a gang and it still
-- honours the rejoin window, so what gets tested is the join that exists. A debug path that
-- set `gangId` directly would be a second, easier join that only the developer ever sees.
function GangService.ForceJoin(player: Player, gangId: string): boolean
	local data = dataFor(player)
	local def = Gangs.ById[gangId]
	if data == nil or def == nil then
		return false
	end
	join(player, data, def)
	applyColors(player, data)
	push(player)
	pushPanel(player)
	return data.gangId == def.id
end

-- Recruits without the walk, through the same `recruit` the panel's "Bring somebody
-- in" row calls -- so what gets tested is the slot check that exists, not a second one
-- written for the debug path. Returns the new member's id so `/gang crew` can print it
-- straight back without a second lookup.
function GangService.ForceRecruit(player: Player, gangId: string): string?
	local data = dataFor(player)
	local def = Gangs.ById[gangId]
	if data == nil or def == nil then
		return nil
	end
	local before = #data.gangCrew
	recruit(player, data, def)
	push(player)
	pushPanel(player)
	if #data.gangCrew <= before then
		return nil
	end
	return data.gangCrew[#data.gangCrew].id
end

-- Dismisses without the walk, through the same `dismiss` the panel's "Let X go" row
-- calls.
function GangService.ForceDismiss(player: Player, crewId: string): boolean
	local data = dataFor(player)
	if data == nil or data.gangId == nil then
		return false
	end
	local def = Gangs.ById[data.gangId]
	if def == nil then
		return false
	end
	local before = #data.gangCrew
	dismiss(player, data, def, crewId)
	push(player)
	pushPanel(player)
	return #data.gangCrew < before
end

local function onChoice(player: Player, gangIdRaw: unknown, choiceRaw: unknown)
	if not enabled then
		return
	end
	if type(gangIdRaw) ~= "string" or type(choiceRaw) ~= "string" then
		return
	end
	local data = dataFor(player)
	if data == nil then
		return
	end
	local def = Gangs.ById[gangIdRaw]
	if def == nil then
		return
	end
	-- You have to be standing there. The panel is a conversation and the server is the end
	-- that decides whether it is still happening, so a client replaying a choice from
	-- across the city is answered by a person who is not there.
	local watch = watchFor(player)
	if watch.atGangId ~= def.id then
		return
	end

	if choiceRaw == "join" then
		join(player, data, def)
	elseif choiceRaw == "leave" then
		leave(player, data, def)
	elseif choiceRaw == "recruit" then
		recruit(player, data, def)
	else
		local rankId = string.match(choiceRaw, "^take_(.+)$")
		if rankId ~= nil then
			takeRank(player, data, def, rankId)
		end
		local crewId = string.match(choiceRaw, "^dismiss_(.+)$")
		if crewId ~= nil then
			dismiss(player, data, def, crewId)
		end
	end

	push(player)
	pushPanel(player)
end

local function onOpen(player: Player, gangIdRaw: unknown)
	if not enabled then
		return
	end
	if type(gangIdRaw) ~= "string" then
		return
	end
	local def = Gangs.ById[gangIdRaw]
	if def == nil then
		return
	end
	local post = posts[def.id]
	local visitor = if post ~= nil then post.visitor else nil
	local at = characterPosition(player)
	if visitor == nil or visitor.gone() or at == nil then
		return
	end
	local away = (visitor.at() - at)
	if math.sqrt(away.X * away.X + away.Z * away.Z) > Config.Interact.RangeStuds then
		return
	end
	watchFor(player).atGangId = def.id
	pushPanel(player)
end

local function onColors(player: Player, wantRaw: unknown)
	if not enabled or type(wantRaw) ~= "boolean" then
		return
	end
	GangService.SetColors(player, wantRaw)
end

function GangService.SetEnabled(value: boolean)
	enabled = value
	if not enabled then
		for _, post in posts do
			despawnPost(post)
		end
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character ~= nil then
				Colors.Clear(character)
			end
		end
	end
end

function GangService.IsEnabled(): boolean
	return enabled
end

-- Wipes gang membership from the life in front of us, for testing the join flow more than
-- once without starting a new life. Standing goes too, unlike leaving, because the point of
-- a reset is a clean slate rather than a resignation.
function GangService.ResetPlayer(player: Player)
	local data = dataFor(player)
	if data == nil then
		return
	end
	data.gangId = nil
	data.gangRankId = nil
	data.gangStanding = {}
	data.gangCrew = {}
	data.leftGangAt = nil
	data.wearingColors = false
	watchFor(player).peakBounty = 0
	local character = player.Character
	if character ~= nil then
		Colors.Clear(character)
	end
	push(player)
	pushPanel(player)
end

function GangService.Describe(player: Player): string
	local data = dataFor(player)
	if data == nil then
		return "no profile loaded yet"
	end
	local standings: { string } = {}
	for _, def in Gangs.All do
		local post = posts[def.id]
		local up = post ~= nil and post.visitor ~= nil and not post.visitor.gone()
		table.insert(
			standings,
			string.format("%s(%s) %d%s", def.id, if up then "boss up" else "no boss", standingIn(data, def.id), if data.gangId == def.id then "*" else "")
		)
	end
	local held = rankById(data.gangRankId)
	local upcoming = promotableTo(data, data.gangId or "")
	local crewBits: { string } = {}
	for _, member in data.gangCrew do
		table.insert(crewBits, `{member.name}(nerve {math.floor(member.nerve)})`)
	end
	local crewDescription = if #crewBits == 0
		then `crew 0/{crewSlotsFor(data, data.gangId or "")}`
		else `crew {#crewBits}/{crewSlotsFor(data, data.gangId or "")}: {table.concat(crewBits, ", ")}`
	return string.format(
		"%s · rank %s · %s · colors %s · %s · rejoin in %.0fs · %s · %s",
		if data.gangId ~= nil then data.gangId else "no gang",
		if held ~= nil then held.label else "-",
		if upcoming ~= nil then `can take "{upcoming.label}"` else "nothing to take",
		if data.wearingColors then "on" else "off",
		crewDescription,
		rejoinWaitFor(data),
		table.concat(standings, ", "),
		if enabled then "on" else "off"
	)
end

function GangService:Init()
	for _, def in Gangs.All do
		posts[def.id] = { gangId = def.id, visitor = nil, dots = nil, spawning = false }
	end

	RequestGangOpenRemote.OnServerEvent:Connect(function(player: Player, gangId: unknown)
		local ok, err = pcall(onOpen, player, gangId)
		if not ok then
			warn(`[AGES] gang open failed for {player.Name}: {err}`)
		end
	end)
	RequestGangChoiceRemote.OnServerEvent:Connect(function(player: Player, gangId: unknown, choice: unknown)
		local ok, err = pcall(onChoice, player, gangId, choice)
		if not ok then
			warn(`[AGES] gang choice failed for {player.Name}: {err}`)
		end
	end)
	RequestGangColorsRemote.OnServerEvent:Connect(function(player: Player, want: unknown)
		local ok, err = pcall(onColors, player, want)
		if not ok then
			warn(`[AGES] gang colors failed for {player.Name}: {err}`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		watches[player] = nil
		pushed[player] = nil
		pushedPanel[player] = nil
	end)
end

function GangService:Start()
	task.spawn(function()
		while true do
			task.wait(GANGS.TickSeconds)
			if enabled then
				local ok, err = pcall(tickPosts)
				if not ok then
					warn(`[AGES] gang posts tick failed: {err}`)
				end
			end
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player)
				if not ok then
					warn(`[AGES] gang tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

return GangService
