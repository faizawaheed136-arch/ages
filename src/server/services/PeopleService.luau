--!strict
-- The people in your life, standing where they live.
--
-- Everybody in AGES up to now was a delivery. They walked in through a door, did one
-- thing, walked out, and were forgotten -- and that is *why* the quiet stretches of a
-- life were quiet, because there was nobody to go and see. A world with a shop and a
-- school and a job in it still had no reason to walk anywhere that was not one of the
-- three. This is the fourth reason.
--
-- The loop, and it is the smallest one in the game on purpose:
--
--   You walk up to somebody. Three dots over their head wake up. You click them, and
--   what you could do with them comes up. You pick one. They say something back.
--
-- What makes it a system rather than a menu is that the list changes. Every person keeps
-- a bond -- how they feel about you -- and an offer states the bond it needs before it
-- appears at all. So what somebody who barely knows you has to offer is small talk, and
-- what somebody who does has to offer is money, comfort and favours. The player is never
-- shown the number. They watch the list get more generous.
--
-- Three rules hold it up, and dropping any one of them turns it back into a menu:
--
--   It decays.        A year you did not visit costs you. Without that, visiting is pure
--                     upside, the right play is one lap and never again, and a
--                     relationship becomes a collectible.
--   It is capped.     Config.People.VisitsPerYear each, currently one. Without a cap the
--                     right play is a lap of everybody, every year, forever -- a commute
--                     rather than a choice.
--   It pays out.      Into pocket money, into a job reference, into smarts. A bond that
--                     only bought more bond would be a score.
--
-- These are *your* family, so they are spawned per player rather than shared. That is a
-- real cost in a full server -- two players at home means two mothers -- and it is the
-- right trade anyway: a person's age window and their bond are both read off one
-- profile, and a single shared rig would have to be a compromise between two lives at
-- once. The same call DeliveryService already makes about visitors, for the same reason.
--
-- Since the town arrived this file also stands about thirty strangers, and they are the
-- same Person shape going through the same loop -- bond, decay, the once-a-year cap, the
-- offer fan, the odds on an ask. Nothing about a conversation knows the difference.
--
-- Two things do, and both are about cost rather than about who anybody is:
--
--   Presence   A townsperson is only given a body while the player is within
--              Config.Town.PresenceStuds of the place they live at, and there is a hard
--              ceiling on how many wear one at once. Building a rig is a yielding web
--              call; thirty at once is a stall on arrival and there is no version of it
--              that is not. Away from you they are a row in a table, which is all a
--              stranger across town has ever been.
--   The ring   They stand on a wider one. Your mother is in the room; the people at the
--              shop are around the shop, and there have to be room for a dozen of them.
--
-- Your family is never streamed. A house that emptied out when you walked to the far end
-- of it would be a worse bug than any number of rigs.
--
-- One more difference, and this one is not about cost: the town walks. A townsperson gets
-- a Roam, which wanders them around the place they belong to and stands them still in
-- between; the family does not, because your mother is in the kitchen because that is
-- where she is. Walking up to anybody stops them and turns them to face you, and walking
-- away lets them go -- see `holdFor` and `release`, which are the whole of it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Interact = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Interact"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local CompanionService = require(script.Parent.CompanionService)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local MoneyService = require(script.Parent.MoneyService)
local NPCService = require(script.Parent.NPCService)
local PlaceService = require(script.Parent.PlaceService)
local StatService = require(script.Parent.StatService)
local Cast = require(script.Parent.Parent.content.Cast)
local People = require(script.Parent.Parent.content.People)
local Ties = require(script.Parent.Parent.content.Ties)
local Ground = require(script.Parent.Parent.world.Ground)
local Roam = require(script.Parent.Parent.world.Roam)
local Routes = require(script.Parent.Parent.world.Routes)
local GossipService = require(script.Parent.GossipService)

type LifeData = Types.LifeData
type CastMember = Types.CastMember
type Person = Types.Person
type PersonOffer = Types.PersonOffer
type PersonState = Types.PersonState
type StatName = Types.StatName
type Gender = Types.Gender
type OfferedChoice = Types.OfferedChoice
type PersonRosterEntry = Types.PersonRosterEntry
type Visitor = NPCService.Visitor

local PeopleService = {}

local PersonUpdatedRemote = Remotes.Get("PersonUpdated")
local RequestPersonOfferRemote = Remotes.Get("RequestPersonOffer")
local PeopleRosterUpdatedRemote = Remotes.Get("PeopleRosterUpdated")
local RequestPersonContactRemote = Remotes.Get("RequestPersonContact")
local NoticeRemote = Remotes.Get("Notice")
local BOND_MILESTONE = Remotes.Get("BondMilestone")

local PEOPLE = Config.People
local TOWN = Config.Town

-- Two people are never set down nearer than this to each other. Not a design tunable:
-- it is the nominal body's width, so the ring is spaced by what a body is rather than
-- by a number that could be tuned under the fact.
local MIN_APART = Config.NPC.BodyRadius * 2

-- A rig's pivot sits at its root part rather than at its feet, so a spot on the floor
-- has to be lifted by roughly half a body before anyone is placed there. They are
-- unanchored and settle the rest of the way themselves; the lift only stops them being
-- spawned with their shins through the pavement.
local SPAWN_LIFT = Config.NPC.BodyHeight / 2

-- Somebody currently standing in the world for one player.
type Standing = {
	person: Person,
	visitor: Visitor,
	-- The three dots over their head. Optional only because attaching them can fail on
	-- a rig whose parts have not arrived yet; a person without them is a person you can
	-- walk up to and not talk to, so that failure is warned about rather than absorbed.
	dots: Interact.InteractHandle?,
	-- Their wandering, and nil for the family. Not an oversight: your mother is in the
	-- kitchen because that is where she is, and a parent who strolled off mid-sentence
	-- would be a bug rather than a life. The town walks because the town is the street.
	roam: Roam.Roam?,
}

-- Who is standing where, per player, keyed by person id.
local standing: { [Player]: { [string]: Standing } } = {}

-- A person who is mid-walk with a player. The walk is the one thing that gets to keep a
-- townsperson's body beyond the street's reach -- you asked them to come along, and the
-- despawn pass must not take them down for the same reason the player is still there. The
-- lease is set before the walk starts and cleared when it ends, so the despawn pass reads
-- it the same way it reads alive and gone.
local leased: { [Player]: { [string]: boolean } } = {}

local function isLeased(player: Player, personId: string): boolean
	local mine = leased[player]
	return mine ~= nil and mine[personId] == true
end

-- A townsperson with no body: where they are, where they are heading, and the wander that
-- decides both.
--
-- **Everybody in the town has one of these the whole time they are in the player's life,
-- bodied or not, and that is the entire point of the thing.** Before this, a person only
-- existed while the player was near the building they belong to, so presence was keyed on
-- the building -- which meant nobody could ever walk further from it than the range that
-- built them, or they would walk out of existence. That is why the town read as thirty
-- shop fittings. A position that is maintained whether or not anyone can see it costs a
-- lerp per person per second and buys a town whose people can cross it.
--
-- The `wander` is the same table the rig's Roam is driving when they have a body, which is
-- what makes the handoff free in both directions: a body is built at `at` and picks up the
-- journey mid-stride, and when it is taken down the ghost carries on from where the legs
-- had got to. Nobody teleports on either edge, which is the only reason this is worth more
-- than raising the range.
type Ghost = {
	at: Vector3,
	-- Where they are walking, or nil while they are standing about. The bodiless half of
	-- the rest that `Roam.Start` spends a `task.wait` on -- and the reason a town nobody
	-- is looking at does not march.
	goal: Vector3?,
	restUntil: number,
	wander: Roam.Wander,
}

-- Every townsperson's position, per player, keyed by person id. Per player rather than
-- global because who is in the town at all depends on whose life it is: an archetype is in
-- or out by the player's own age.
local ghosts: { [Player]: { [string]: Ghost } } = {}

-- Who could not be fitted at their place last time the roster was rebuilt, and why.
-- Kept only so `/people` can answer the one question a missing mother raises, which is
-- whether she was never written or simply had nowhere to stand.
local unplaced: { [Player]: { [string]: string } } = {}

-- Which places each player was last found to be near, as a sorted string. Compared
-- rather than recomputed-and-acted-on, because the answer is the same on almost every
-- check and a rebuild is the expensive thing on the other side of a change: walking
-- across the shop should cost nothing, and walking *into* the shop should cost one pass.
local presence: { [Player]: string } = {}

-- The conversation in front of a player. Only ever one -- you are next to somebody or
-- you are not.
type Chat = {
	personId: string,
	-- What is on the panel if the player clicks the dots. Held here as the authored
	-- offers rather than as what the client was shown, because this is also the list an
	-- answer coming back is checked against -- the client is told ids and labels, and
	-- what an id is worth is only ever read from here.
	offers: { PersonOffer },
	-- Nothing further to take. Set by every way a conversation can end -- an offer taken,
	-- a refusal at the door -- and it is what stops a second click paying out twice.
	-- Cleared by walking away, which is the only thing that clears it.
	done: boolean,
	replyLeft: number,
	replyText: string?,
	replyGood: boolean,
	-- True when this chat came from a roster tap rather than from standing next to
	-- somebody. A remote chat has no `stand`, so the walk has to find the person from
	-- their id and every place a body would appear must be skipped.
	remote: boolean,
}

local chats: { [Player]: Chat } = {}

-- The last thing pushed to each player, so an unchanged row is not re-sent four times a
-- second. Same reason work and school keep one.
local pushed: { [Player]: string } = {}

-- The last roster digest pushed to each player, so an unchanged list is not re-sent on
-- every rebuild. Same reason `pushed` exists one block up, for the row.
local pushedRoster: { [Player]: string } = {}

-- Approach tracking. Records the timestamp of each time the player walked into reach
-- of a new NPC. Used by the autonomy-rate debug command to report the real number,
-- so the quota is a thing you can see failing rather than a thing you assume.
--
-- Each entry is { at: number, personId: string }. The list is kept small: after twenty
-- approaches the oldest is dropped, which is roughly a minute at the tick rate and
-- enough for a rolling average that does not bounce on a single outlying visit.
type ApproachEntry = { at: number, personId: string }
local approaches: { [Player]: { ApproachEntry } } = {}
-- The person the player was last recorded approaching, so a player standing still
-- next to the same person does not flood the log on every tick.
local approachTarget: { [Player]: string } = {}

-- Studio harness switch. Off takes everybody out of the world, so the shop and the
-- school can be tested in a street that is not also full of relatives.
local enabled = true

-- Every place any authored person lives at, worked out once. Iterated rather than
-- `People.All` when rebuilding a roster, because the expensive half of the rebuild is
-- resolving a place point and several people share one.
local PLACE_IDS: { string } = {}
do
	local seen: { [string]: boolean } = {}
	for _, person in People.All do
		if not seen[person.placeId] then
			seen[person.placeId] = true
			table.insert(PLACE_IDS, person.placeId)
		end
	end
end

local function ageYearsOf(data: LifeData): number
	return data.ageMonths // Config.Time.MonthsPerYear
end


local function characterPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root.Position
end

-- Which places the player is close enough to for the town who live there to be worth
-- building bodies for, and how far each one is. Empty while there is no character to
-- measure from, which is correct rather than a special case: somebody who is not in the
-- world is not near anything, and the next check after they spawn puts it right.
--
-- Distances come back with it because the ceiling on bodied townsfolk has to drop the
-- furthest place rather than whichever one the loop reached last.
local function nearPlacesFor(position: Vector3?): { [string]: number }
	local near: { [string]: number } = {}
	if position == nil then
		return near
	end
	for _, placeId in PLACE_IDS do
		local place = PlaceService.Find(placeId)
		if place == nil then
			-- PlaceService has already warned about the missing tag, and the rebuild
			-- records it against the people who wanted it. Nothing to add here.
			continue
		end
		local distance = Ground.FlatDistance(position, place.part.Position)
		if distance <= TOWN.PresenceStuds then
			near[placeId] = distance
		end
	end
	return near
end

-- One bodiless townsperson, moved on by however long it has been since they were last
-- thought about.
--
-- Straight-line and flat, deliberately. There is no rig to collide with anything and
-- nobody watching, so pathfinding here would be paying Roblox to route somebody around a
-- bench that only exists as far as the renderer is concerned. The route itself is not
-- straight -- `Roam.NextLeg` hands back one town point at a time, and those are on the
-- paths -- so what this actually walks is the same polyline a body would, without the
-- steering.
--
-- Height comes from the goal on arrival rather than being tracked along the way: the leg
-- is short, the probe that turns a ghost back into a body looks six studs up and twelve
-- down for the floor anyway, and carrying a stale Y up a hill is cheaper to fix at the end
-- than to integrate all the way along.
local function stepGhost(ghost: Ghost, elapsed: number)
	local now = os.clock()
	local goal = ghost.goal
	if goal == nil then
		if now < ghost.restUntil then
			return
		end
		-- Nil means nothing was found to walk to -- no graph in reach and every probe
		-- blocked. The answer is the same as the walker's: stand there and ask again
		-- after the next rest, rather than burn a probe per tick forever.
		ghost.goal = Roam.NextLeg(ghost.wander, ghost.at)
		if ghost.goal == nil then
			ghost.restUntil = now + TOWN.PauseMinSeconds
		end
		return
	end

	local step = TOWN.WalkSpeed * elapsed
	local offset = Vector3.new(goal.X - ghost.at.X, 0, goal.Z - ghost.at.Z)
	if offset.Magnitude <= step then
		ghost.at = goal
		ghost.goal = nil
		ghost.restUntil = now + ghost.wander.rng:NextNumber(TOWN.PauseMinSeconds, TOWN.PauseMaxSeconds)
		return
	end
	ghost.at = ghost.at + offset.Unit * step
end

-- Brings the set of positions into line with who is in the town for this player, which is
-- the same idempotent shape as `rebuild` and for the same reason: a birthday changes who
-- is in the town, and every caller should be able to say "make this true" rather than know
-- which people to add.
--
-- New arrivals start at the place they belong to, which is the only honest answer -- they
-- have not been walking anywhere, because until this second they were not in this life.
local function ensureGhosts(player: Player, data: LifeData, age: number)
	local mine = ghosts[player]
	if mine == nil then
		mine = {}
		ghosts[player] = mine
	end

	-- Resolved once per pass. Several people share a place and `PlaceService.Find` is a
	-- tag lookup rather than a field read.
	local homes: { [string]: Vector3 } = {}
	local present: { [string]: boolean } = {}

	for _, person in People.All do
		if not People.IsTown(person.id) or not People.IsAround(person, age, data.flags) then
			continue
		end
		present[person.id] = true
		if mine[person.id] ~= nil then
			continue
		end

		local home = homes[person.placeId]
		if home == nil then
			local place = PlaceService.Find(person.placeId)
			if place == nil then
				-- PlaceService has already warned about the missing tag, and `rebuild`
				-- records it against everybody who wanted it. Nothing to start them from,
				-- so they simply have no position until it is tagged.
				continue
			end
			home = place.part.Position
			homes[person.placeId] = home
		end

		-- Unseeded, like the walker's, and for the same reason: where somebody happens to
		-- be standing is not part of who the town is. The stagger is what stops a place
		-- whose people all entered this life on one birthday sending all of them out of
		-- the door on the same second, which reads as a shift change.
		local rng = Random.new()
		local ghost: Ghost = {
			at = home,
			goal = nil,
			restUntil = os.clock() + rng:NextNumber(0, TOWN.PauseMaxSeconds),
			wander = { node = nil, previous = nil, home = home, rng = rng },
		}

		-- The town has already had a morning. Everybody starting life at the exact point
		-- their place is tagged puts six kids on your doorstep the second you are born and
		-- four regulars in the shop doorway, and no amount of walking afterwards undoes the
		-- first impression -- which is a spawner firing, not a street.
		--
		-- Walked rather than teleported to a random point, and that is the whole trick: the
		-- legs are the same legs `stepGhost` would have taken, so wherever they end up is
		-- somewhere the route graph actually goes and inside their own leash. It costs a
		-- handful of table reads, because a leg nobody can see does not have to be walked
		-- at walking pace.
		for _ = 1, rng:NextInteger(0, TOWN.SettleLegs) do
			local leg = Roam.NextLeg(ghost.wander, ghost.at)
			if leg == nil then
				break
			end
			ghost.at = leg
		end

		mine[person.id] = ghost
	end

	-- Anybody who has aged out of this life or been flagged away. Their body is taken down
	-- by the rebuild; this is the half of them that never had one, and left behind it would
	-- be a position quietly walking around the town for the rest of the session.
	for id in mine do
		if not present[id] then
			mine[id] = nil
		end
	end
end

-- Which townsfolk are close enough to the player to be worth building a body for, and how
-- far each one is.
--
-- Measured from the person rather than from the building they belong to. That one change
-- is the feature: the old test asked whether the player was near a place and then built
-- everybody who lived there, so a walk that took somebody a hundred studs down the road
-- was a walk out of existence, and the range that governed the walking had to stay smaller
-- than the range that governed the bodies.
--
-- The slack is hysteresis and it is not optional. Without it, somebody drifting along the
-- exact edge is built, measured, torn down and built again once a second -- a person
-- flickering rather than a person leaving -- and each of those builds is a web call.
local function townInRange(player: Player, position: Vector3?): { [string]: number }
	local near: { [string]: number } = {}
	if position == nil then
		return near
	end
	local mine = ghosts[player]
	if mine == nil then
		return near
	end

	local here = standing[player]
	local keep = TOWN.PresenceStuds * TOWN.DespawnSlack

	for id, ghost in mine do
		local stand = if here ~= nil then here[id] else nil
		local bodied = stand ~= nil and not stand.visitor.gone()
		-- A bodied person is asked where they are; a bodiless one is only ever where the
		-- integrator put them. One question, two places to ask it, which is the shape of
		-- this whole system.
		local at = if bodied and stand ~= nil then stand.visitor.at() else ghost.at
		local distance = Ground.FlatDistance(position, at)
		if distance <= (if bodied then keep else TOWN.PresenceStuds) then
			near[id] = distance
		end
	end
	return near
end

-- The set above as one comparable string. Sorted, so the same set of people never reads
-- two different ways and triggers a rebuild for having been iterated in a new order.
local function townDigest(near: { [string]: number }): string
	local ids: { string } = {}
	for id in near do
		table.insert(ids, id)
	end
	table.sort(ids)
	return table.concat(ids, ",")
end

-- How they feel about you. Never nil here, unlike the content module's version: this is
-- only ever asked about somebody already resolved out of the roster, so there is no
-- unwritten person for it to have no answer about.
local function bondOf(data: LifeData, person: Person): number
	return People.BondIn(data.bonds, person.id) or person.startingBond
end

-- How many times this person has been seen at this age. A record left over from an
-- earlier year reads as none, which is how a year rolls over without anything having to
-- be cleared on the birthday.
local function visitsAt(data: LifeData, personId: string, age: number): number
	local record = data.visits[personId]
	if record == nil or record.age ~= age then
		return 0
	end
	return record.count
end

local function bandFor(bond: number): string
	for _, band in PEOPLE.Bands do
		if bond >= band.atLeast then
			return band.name
		end
	end
	-- Unreachable while the last band is anchored to MinBond and bonds are clamped to
	-- it, which is exactly why this says so rather than returning an empty string that
	-- would show up on the HUD as a missing word.
	return PEOPLE.Bands[#PEOPLE.Bands].name
end

local BOND_MILESTONE_LABELS: { [number]: string } = {
	[10] = "Acquaintance",
	[25] = "Friend",
	[50] = "Close Friend",
	[75] = "Best Friend",
	[100] = "Soul Friend",
}

local function milestoneLabel(milestone: number): string
	return BOND_MILESTONE_LABELS[milestone] or "Friend"
end

-- Record an interaction with a person. Rolling buffer of 5 per person: oldest
-- is dropped. The defining moment for that person is set when the bonding is
-- strongest yet, so the player remembers the line said at the peak of the bond.
local function recordInteraction(data: LifeData, personId: string, age: number, line: string)
	local list = data.interactions[personId]
	if list == nil then
		list = {}
		data.interactions[personId] = list
	end
	table.insert(list, { personId = personId, age = age, line = line })
	while #list > PEOPLE.InteractionsPerPerson do
		table.remove(list, 1)
	end
end

-- The odds this ask is turned down, from 0 to 1. Zero for everything that is not an
-- ask, which is most of what anybody has to say.
--
-- Read off the gap between the bond and what this particular offer asks of it. An ask
-- appears the very year the bond reaches its minBond, so at that moment the player is
-- asking for something the other person has only just become capable of saying yes to
-- -- and the further past it they are, the less of a question it is. That is the whole
-- rule, and it means no offer has to carry authored odds that could fall out of step
-- with the bond it already names.
local function refusalChance(offer: PersonOffer, bond: number): number
	if not offer.ask then
		return 0
	end
	local headroom = math.max(bond - offer.minBond, 0)
	local warmth = math.min(headroom / PEOPLE.RefuseFadeSpan, 1)
	return PEOPLE.RefuseAtFloor * (1 - warmth)
end

-- What those odds are called on the row, or nil when the ask has become safe enough
-- to stop warning about. The nil is the point: a row that quietly loses its note is
-- how the player finds out somebody came around.
local function riskNote(chance: number): string?
	for _, band in PEOPLE.RiskBands do
		if chance >= band.atLeast then
			return band.name
		end
	end
	return nil
end

-- Studio harness switch over the coin. "chance" is the game; the other two force the
-- branch, because a refusal is the one outcome in this system that cannot be reached on
-- purpose -- waiting on a 50/50 to see the words somebody says when they turn you down
-- is not a test, and at one visit a year a wrong guess costs a whole in-game year to
-- retry.
export type RefusalMode = "chance" | "always" | "never"
local refusalMode: RefusalMode = "chance"

-- Whether this ask is turned down. The single place the coin is flipped, so there is
-- exactly one thing to switch off and exactly one thing to read.
local function rollRefusal(offer: PersonOffer, bond: number): boolean
	-- Checked before the override, so forcing refusals on never turns small talk into
	-- something that can be refused. Nothing that is not an ask has words to say no with.
	if not offer.ask then
		return false
	end
	if refusalMode == "always" then
		return true
	end
	if refusalMode == "never" then
		return false
	end
	return math.random() < refusalChance(offer, bond)
end

local function nameOf(person: Person): string
	local member = Cast.ById[person.castId]
	if member == nil then
		-- Validated at content load, so this is only reachable if the validator was
		-- bypassed. Their id is a worse name than their name and a much better one than
		-- a blank row.
		return person.id
	end
	return member.name
end

-- Who they are, for the one thing in this game allowed to ask: which first-name list
-- they were named from. Nothing else reads it -- there is no partner system for it to
-- feed, and the town listing shows the initial only as a label on a row.
--
-- Optional for the same reason nameOf falls back to an id -- a cast entry that is not
-- there is a bypassed validator rather than a runtime state -- but answered with nil
-- rather than a guess, because a person nobody can classify belongs outside a count and
-- not in whichever half of it the fallback happened to pick.
local function genderOf(person: Person): Gender?
	local member = Cast.ById[person.castId]
	return if member ~= nil then member.gender else nil
end

-- Whether these two are close enough in age to be each other's contemporaries. Read from
-- the offset rather than from the archetype, so somebody who came out of the generator at
-- the near edge of a wide spread counts and somebody at the far edge of a narrow one does
-- not -- which is what the player sees, since what stands in front of them is a person of
-- an age and not a category.
local function isPeer(person: Person): boolean
	return math.abs(person.ageOffset) <= PEOPLE.PeerAgeGap
end

-- Whether this person still has anything to give the player today. Asked of the
-- profile rather than of an open conversation, because the answer has to be true from
-- across the room: the dots over somebody's head are a promise that walking over there
-- is worth the walk, and a lit set of dots on somebody you have already seen this year
-- is the game lying about that.
-- Everything that decides what is on somebody's panel, gathered in one place so that
-- what the dots promise and what the panel then shows are worked out from the same
-- answer. They were four arguments before ties existed and it did not matter; now that
-- one of them is a fact about the whole roster, two call sites assembling it separately
-- is two chances for a lit set of dots to open an empty list.
local function offerContext(data: LifeData, person: Person): People.OfferContext
	local age = ageYearsOf(data)
	return {
		age = age,
		bond = bondOf(data, person),
		flags = data.flags,
		tie = data.ties[person.id],
		tieFull = People.TieRoom(data.ties, age, data.flags),
	}
end

local function hasSomethingLeft(data: LifeData, person: Person): boolean
	if visitsAt(data, person.id, ageYearsOf(data)) >= PEOPLE.VisitsPerYear then
		return false
	end
	return #People.OffersFor(person, offerContext(data, person)) > 0
end

-- What a person can say to you from the phone. Everything `OffersFor` yields minus the
-- walks, because a walk is the one offer whose content is legs -- it needs the body
-- standing in front of you, and a call has none. This is what the roster's green dot
-- means and what a phone chat actually holds, so the two can never disagree.
local function callableOffers(data: LifeData, person: Person): { PersonOffer }
	local all = People.OffersFor(person, offerContext(data, person))
	local callable: { PersonOffer } = {}
	for _, offer in all do
		if offer.walksTo == nil then
			table.insert(callable, offer)
		end
	end
	return callable
end

-- Everything written over one person's head: the dots, lit or quiet to match what they
-- actually have, and the plate saying who they are and how old.
--
-- The dots are never taken away -- somebody who has given you their time this year is
-- still standing there and is still worth walking up to, and removing them would say
-- they had left. The plate is never taken away either, for a plainer reason: a name is
-- true whether or not there is anything left to say.
local function refreshOverhead(player: Player, stand: Standing)
	local profile = DataService.GetProfile(player)

	-- Ahead of the dots, and outside the nil check on them, because this is the one thing
	-- here that is not about the marker over somebody's head. Everybody in the world gets
	-- a year older on the player's birthday, and a body that did not resize is a classmate
	-- who is still six in the year you leave school. Cheap -- four NumberValues -- which is
	-- what lets a birthday resize the whole street instead of rebuilding it.
	if profile ~= nil then
		stand.visitor.setAge(math.max(ageYearsOf(Lives.Active(profile.Data)) + stand.person.ageOffset, 0))
	end

	local dots = stand.dots
	if dots == nil then
		return
	end
	local lit = profile ~= nil and Lives.Active(profile.Data).alive and enabled and hasSomethingLeft(Lives.Active(profile.Data), stand.person)
	dots.SetEnabled(lit)

	if profile ~= nil then
		dots.SetNameplate({
			name = nameOf(stand.person),
			age = People.ShownAge(stand.person, ageYearsOf(Lives.Active(profile.Data))),
			-- Nil for nearly everybody, which is the point of putting it here: a town
			-- where one head in thirty says "friend" is a town you can read at a glance,
			-- and it is the only place a tie is ever shown, because the alternative is a
			-- relationships screen and this game does not have screens.
			tie = Ties.LabelOf(Lives.Active(profile.Data).ties[stand.person.id]),
		})
	end
end

-- Every one of them, for the moments that change what everybody has at once: a birthday,
-- a flag moving, a harness command. Cheap enough to do wholesale -- it is a handful of
-- people and a table read each -- and doing it wholesale is what stops one path being
-- forgotten and leaving a single relative permanently lit.
--
-- A birthday is also the one moment every age on every plate is wrong at once, and it
-- already comes through here, which is why the plate rides along with the dots rather
-- than getting a refresh path of its own that a caller could forget.
local function refreshAllOverhead(player: Player)
	local here = standing[player]
	if here == nil then
		return
	end
	for _, stand in here do
		refreshOverhead(player, stand)
	end
end

local function stateFor(player: Player): PersonState?
	local chat = chats[player]
	if chat == nil then
		return nil
	end
	local person = People.ById[chat.personId]
	if person == nil then
		return nil
	end

	local profile = DataService.GetProfile(player)
	local bond = if profile ~= nil then bondOf(Lives.Active(profile.Data), person) else nil
	local band = if bond ~= nil then bandFor(bond) else ""

	-- Ids, labels, and how likely a no is. What an offer is *worth* stays on this
	-- machine: the panel is built to be read, and the answer that comes back off it is
	-- priced from `chat.offers` and never from what was sent.
	--
	-- The odds are the one thing that has to travel, because a gamble the player cannot
	-- see is not a gamble they are taking -- it is one the game is taking for them. Sent
	-- as the word rather than the number so the client has nothing to arithmetic with,
	-- and so the wording stays a single decision made here.
	local offers: { OfferedChoice } = {}
	for _, offer in chat.offers do
		local note = if bond ~= nil then riskNote(refusalChance(offer, bond)) else nil
		table.insert(offers, { id = offer.id, label = offer.label, cost = nil, note = note, locked = false })
	end

	-- Pick a contextual line if one is available for the current situation.
	local contextLine: string? = nil
	if person.contextualLines ~= nil and chat.replyText == nil then
		local data = Lives.Active(profile.Data)
		local age = ageYearsOf(data)
		local keys: { string } = {}
		if age < 16 then
			table.insert(keys, "unemployed")
		end
		if data.jobId ~= nil then
			table.insert(keys, "onShift")
		end
		table.insert(keys, "morning")
		if data.houses ~= nil and next(data.houses) ~= nil then
			table.insert(keys, "atHome")
		end
		for _, key in keys do
			local lines = person.contextualLines[key]
			if lines ~= nil and #lines > 0 then
				contextLine = lines[math.random(1, #lines)]
				break
			end
		end
	end

	return {
		id = person.id,
		name = nameOf(person),
		band = band,
		reply = chat.replyText,
		replyGood = chat.replyGood,
		offers = offers,
		-- The one thing the client cannot infer from the row: this chat has no body to
		-- walk to, so it must be drawn as a phone call rather than as a standing person.
		contact = chat.remote,
		contextualLine = contextLine,
	}
end

local function push(player: Player)
	local state = stateFor(player)
	local digest = "none"
	if state ~= nil then
		local ids: { string } = {}
		for _, offer in state.offers do
			table.insert(ids, offer.id)
		end
		-- The offer ids are in the digest because they are the only part of this that can
		-- change while the name and the band sit still -- taking one leaves a row that reads
		-- identically and a panel that must not.
		digest = `{state.id}|{state.band}|{tostring(state.reply)}|{tostring(state.replyGood)}|{tostring(state.contact)}|{tostring(state.contextualLine)}|{table.concat(ids, ",")}`
	end
	if pushed[player] == digest then
		return
	end
	pushed[player] = digest
	PersonUpdatedRemote:FireClient(player, state)
end

-- The people this player knows and could be speaking to, as a whole list for the HUD.
-- The same gate that decides who is in the world at all decides who is on this list --
-- it is the roster used to build the street, sent as rows -- and `available` is whether
-- tapping them has anything to say this year. Distinct from `stateFor`'s single row in
-- the same way `PeopleRosterUpdated` was split from `PersonUpdated`: one names everyone,
-- the other names who is next to you right now.
local function rosterFor(player: Player): { PersonRosterEntry }
	local profile = DataService.GetProfile(player)
	local entries: { PersonRosterEntry } = {}
	if profile == nil then
		return entries
	end
	local data = Lives.Active(profile.Data)
	if not data.alive then
		return entries
	end
	local age = ageYearsOf(data)
	for _, person in People.All do
		if not People.IsAround(person, age, data.flags) then
			continue
		end
		table.insert(entries, {
			id = person.id,
			name = nameOf(person),
			band = bandFor(bondOf(data, person)),
			-- Callable rather than everything they have left: the dot is what a tap on
			-- the roster is worth, and a walk that cannot transfer must not light it.
			available = visitsAt(data, person.id, age) < PEOPLE.VisitsPerYear
				and #callableOffers(data, person) > 0,
		})
	end
	return entries
end

local function pushRoster(player: Player)
	local entries = rosterFor(player)
	local digests: { string } = {}
	for _, entry in entries do
		table.insert(digests, `{entry.id}:{entry.name}:{entry.band}:{tostring(entry.available)}`)
	end
	local digest = table.concat(digests, "|")
	if pushedRoster[player] == digest then
		return
	end
	pushedRoster[player] = digest
	PeopleRosterUpdatedRemote:FireClient(player, entries)
end

-- A spot on the ring around a place that a body actually fits in, or nil if every
-- bearing was taken or blocked. Full circle rather than an arc, because a place point
-- is the middle of a room and there is no reason a mother should be in front of it.
--
-- The ring is passed in rather than read off Config here because there are two of them:
-- the family stand close, and the town stand on a wider circle with more bearings on it,
-- since a dozen strangers will not fit on a mother's.
local function spotFor(center: Vector3, taken: { Vector3 }, ringStuds: number, ringBearings: number): Vector3?
	local ignore = Ground.IgnoreList()
	local radius = Config.NPC.BodyRadius
	local height = Config.NPC.BodyHeight

	for _, bearing in Ground.Bearings(360, ringBearings) do
		local direction = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(-bearing)) * Vector3.new(0, 0, -1)
		local candidate = center + direction * ringStuds

		-- No reachability test, and that is deliberate rather than an omission. These
		-- people are not walking to the ring, they are already standing on it when the
		-- player comes into view -- a mother in her own kitchen does not have to be able
		-- to walk there from the middle of the room to be allowed to be in it.
		local floor = Ground.SpotAt(candidate, radius, height, ignore)
		if floor == nil then
			continue
		end
		if Ground.Apart(floor, taken, MIN_APART) then
			return floor
		end
	end

	return nil
end

-- Where to put a body for somebody who has been walking without one. Three tries, and the
-- order is the argument: exactly where they are, a step aside, and only then the ring
-- around the place they belong to.
--
-- The first is the one that matters -- a person coming into view should appear where they
-- had got to, because anything else is a teleport the player can see. The second covers
-- two people arriving at one corner. The third is the interesting one: in a world with
-- nothing tagged, everybody's ghost is still milling about within `RoamStuds` of their own
-- doorstep, so a crowded doorstep falls through to the ring and spreads out exactly as it
-- did before any of this existed. The old behaviour is the last resort rather than a
-- separate code path.
local function spotAt(at: Vector3, home: Vector3, taken: { Vector3 }): Vector3?
	local ignore = Ground.IgnoreList()
	local radius = Config.NPC.BodyRadius
	local height = Config.NPC.BodyHeight

	local floor = Ground.SpotAt(at, radius, height, ignore)
	if floor ~= nil and Ground.Apart(floor, taken, MIN_APART) then
		return floor
	end

	return spotFor(at, taken, TOWN.NudgeStuds, TOWN.StandBearings)
		or spotFor(home, taken, TOWN.StandStuds, TOWN.StandBearings)
end

local function takeDown(player: Player, personId: string)
	local here = standing[player]
	if here == nil then
		return
	end
	local stand = here[personId]
	if stand == nil then
		return
	end
	here[personId] = nil

	-- The despawn half of the handoff, and it has to happen before the rig goes: where the
	-- body had got to becomes where the person is. Without this, somebody the player
	-- followed down a street and then walked away from would snap back to wherever their
	-- ghost was last stepped, which is the doorstep they set off from.
	--
	-- The goal goes with the body rather than carrying over. The wander is shared and the
	-- rig has been advancing it all the time it was walking, so whatever this ghost was
	-- heading for before it grew legs is somewhere it has since walked past; asking for a
	-- fresh leg from where they now actually are is the only reading that is not stale.
	local mine = ghosts[player]
	local ghost = if mine ~= nil then mine[personId] else nil
	if ghost ~= nil and not stand.visitor.gone() then
		ghost.at = stand.visitor.at()
		ghost.goal = nil
		ghost.restUntil = os.clock()
	end

	-- Ahead of the rig, and by hand rather than left to the model going away. Destroying
	-- the character does take the prompt and the billboard with it, but not the three
	-- looping tweens driving the dots, and those would go on bobbing nothing forever.
	local dots = stand.dots
	if dots ~= nil then
		dots.Destroy()
	end
	-- Before the body, so the walk cannot issue one more leg against a rig that is
	-- already halfway out of the world.
	local roam = stand.roam
	if roam ~= nil then
		roam.stop()
	end
	stand.visitor.destroy()
end

local function despawnAll(player: Player)
	-- Ahead of the early return, and not inside it. This is the record of which places had
	-- bodies built for them, so it has to be wrong in the same direction as the world: left
	-- set, the next presence check would compare against a street that no longer exists and
	-- decide nothing had changed.
	presence[player] = nil
	-- And the positions with it. This is death, a new life or the harness switch, not the
	-- player walking away: there is no journey left to resume, and a ghost kept across one
	-- of those would have somebody from the last life still pacing the street.
	ghosts[player] = nil

	-- Any walk in progress ends here, ahead of the rigs below. Death, a new life and the
	-- harness switch are not walks that finish, they are walks that stop existing -- the
	-- callback fires once and the lease goes with the rigs.
	CompanionService.Dismiss(player)
	leased[player] = nil

	local here = standing[player]
	if here == nil then
		return
	end
	standing[player] = nil
	-- The reasons went with them. Left behind, they would have `/people` explaining why a
	-- mother could not be fitted into a room nobody is standing in any more.
	unplaced[player] = nil
	for _, stand in here do
		local dots = stand.dots
		if dots ~= nil then
			dots.Destroy()
		end
		local roam = stand.roam
		if roam ~= nil then
			roam.stop()
		end
		stand.visitor.destroy()
	end
end

-- Brings the set of people standing in the world into line with who is actually in this
-- player's life right now. Idempotent, which is the whole design: a birthday, a new life
-- and a debug command all just ask for this again rather than each knowing which rigs to
-- add or remove.
--
-- Yields -- building an avatar is a web-backed call -- so everything it holds across a
-- yield is re-checked afterwards.
local function rebuild(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil or not enabled then
		despawnAll(player)
		return
	end

	local data = Lives.Active(profile.Data)
	local age = ageYearsOf(data)

	-- Re-bound rather than used through the optional, because the spawn below is a closure
	-- over it and narrowing does not cross that boundary.
	local roster = standing[player]
	if roster == nil then
		roster = {}
		standing[player] = roster
	end
	local here: { [string]: Standing } = roster

	-- Where the player is standing, decided once at the top and used for the whole pass.
	-- Re-measuring per place would let somebody walking between two of them be counted as
	-- near neither, and the symptom of that is a shop that empties as you cross it.
	local position = characterPosition(player)

	-- Before anything measures a distance to a townsperson, because a distance to somebody
	-- with no position yet is a distance to their doorstep -- and on the birthday an
	-- archetype enters the life, that would build the whole set of them at their buildings
	-- rather than wherever the walking would have taken them.
	if data.alive then
		ensureGhosts(player, data, age)
	end

	local nearPlaces = nearPlacesFor(position)
	local inRange = townInRange(player, position)
	presence[player] = townDigest(inRange)

	-- Anybody who has aged out of this life, or all of them if there is no life to be in
	-- at the moment. Done first so their spot on the ring is free for whoever replaces
	-- them at the same place.
	--
	-- A townsperson the player has walked away from goes here too. It is the same removal
	-- for a different reason -- they have not left your life, you have left the street --
	-- and doing it in this pass is what frees the rig budget before the pass below starts
	-- spending it.
	for id, stand in here do
		local person = stand.person
		local streamedOut = People.IsTown(person.id) and inRange[person.id] == nil
		if
			not data.alive
			or not People.IsAround(person, age, data.flags)
			or stand.visitor.gone()
			-- Walking out of the street's reach does not take down somebody walking with
			-- you -- that is the whole point of the lease, and without the exception a
			-- companion would despawn the moment you led them past their own doorstep.
			or (streamedOut and not isLeased(player, id))
		then
			takeDown(player, id)
		end
	end
	if not data.alive then
		-- The dead do not walk. Any walk still in flight is ended rather than left to
		-- notice the gone visitor one tick later, and the leases go with the rigs.
		CompanionService.Dismiss(player)
		leased[player] = nil
		unplaced[player] = nil
		ghosts[player] = nil
		return
	end

	-- How much of the rig ceiling is already spent, counted after the take-down above so
	-- somebody who just walked out of range is not still holding a slot against the person
	-- replacing them.
	local townBodied = 0
	for _, stand in here do
		if People.IsTown(stand.person.id) then
			townBodied += 1
		end
	end

	local missing: { [string]: string } = {}
	unplaced[player] = missing

	-- Everything between "this person should be standing here" and "they are". Shared by
	-- the two passes below, because the only thing that differs between the family and the
	-- town is how the spot was chosen -- and a second copy of the spawn, the re-check and
	-- the dots is exactly the kind of duplication that drifts apart one bug fix at a time.
	--
	-- A closure rather than a file-level function so it can hold the profile, the roster
	-- and the reasons table without any of them having to be threaded through and, more to
	-- the point, without `profile`'s type having to be nameable from out here.
	--
	-- False means the world moved under one of the yields, and abandoning the pass is the
	-- caller's to do rather than this one's -- it does not know what else the caller was in
	-- the middle of.
	local function putDown(
		person: Person,
		member: CastMember,
		spot: Vector3,
		facing: Vector3,
		wander: Roam.Wander?,
		resume: Vector3?
	): boolean
		local at = spot + Vector3.new(0, SPAWN_LIFT, 0)

		-- Their real age, not the one on the nameplate. ShownAge stops reporting past
		-- OldestShownAge because the game declines to *claim* a number it does not model,
		-- but a body still has to be some size, and "no age shown" must not come out as
		-- "newborn". Floored at nought for the same reason it is on the nameplate: an
		-- offset can put somebody a year from being born and nothing should be built
		-- inside-out because of it.
		local visitorAge = math.max(ageYearsOf(data) + person.ageOffset, 0)
		local visitor = NPCService.Spawn(player, member, CFrame.lookAt(at, at + facing), visitorAge)
		if visitor == nil then
			-- NPCService has already said why.
			missing[person.id] = "could not be built"
			return true
		end

		-- Everything below was true before the spawn yielded and may not be now: the player
		-- can have left, died, had a birthday that aged this person out, or had their roster
		-- torn down and rebuilt underneath this loop.
		local current = DataService.GetProfile(player)
		if
			standing[player] ~= here
			or current ~= profile
			or not data.alive
			or not People.IsAround(person, ageYearsOf(data), data.flags)
		then
			visitor.destroy()
			return false
		end

		-- The invitation, attached to the rig itself so it travels with them. "Talk" and
		-- their name, which is the only place in this game a person's name is written in
		-- the world rather than on the HUD.
		--
		-- The plate goes on at attach rather than being left to the refresh below, so
		-- there is never a frame of a nameless stranger standing there. It is kept in
		-- step after that by `refreshOverhead`, which every birthday already runs.
		local dots = Interact.Attach(visitor.model, {
			kind = "Person",
			id = person.id,
			actionText = "Talk",
			objectText = member.name,
			nameplate = {
				name = member.name,
				age = People.ShownAge(person, ageYearsOf(data)),
			},
		})
		if dots == nil then
			-- Said out loud because the symptom is silent and looks like content: a
			-- relative standing in the kitchen that the player can circle forever and
			-- never speak to. They are left standing anyway -- a person with no dots is
			-- worse than a person, and much better than an empty room.
			warn(`[AGES] could not put dots over "{person.id}" for {player.Name}`)
		end

		-- The spawn half of the handoff, and nil for the family: your mother is in the
		-- kitchen because that is where she is. For the town, `wander` is the very table
		-- their position has been walking and `resume` is the leg it was partway through,
		-- so the legs pick the journey up mid-stride instead of setting off on a new one
		-- from wherever the body was set down.
		local roam = if wander ~= nil then Roam.Start(visitor, wander, resume) else nil

		local stand: Standing = { person = person, visitor = visitor, dots = dots, roam = roam }
		here[person.id] = stand
		refreshOverhead(player, stand)
		return true
	end

	-- **Pass one: the family**, on the ring around the place they belong to, nearest place
	-- first. They are never counted against the town's ceiling and never skipped for it --
	-- your mother is in the kitchen whether or not the street outside is busy.
	local orderedPlaces = table.clone(PLACE_IDS)
	table.sort(orderedPlaces, function(a: string, b: string): boolean
		local da = nearPlaces[a] or math.huge
		local db = nearPlaces[b] or math.huge
		if da == db then
			return a < b
		end
		return da < db
	end)

	for _, placeId in orderedPlaces do
		local wanted: { Person } = {}
		for _, person in People.At(placeId) do
			-- The town is pass two. They are placed by where they have walked to rather
			-- than by which building they belong to, which is a different question with a
			-- different answer, so it is not a branch inside this loop.
			if People.IsTown(person.id) then
				continue
			end
			if not People.IsAround(person, age, data.flags) or here[person.id] ~= nil then
				continue
			end
			table.insert(wanted, person)
		end
		if #wanted == 0 then
			continue
		end

		local place = PlaceService.Find(placeId)
		if place == nil then
			-- PlaceService has already warned once about the missing tag, and warning
			-- again per birthday would bury the log. Recorded so `/people` can say it out
			-- loud to whoever is standing in the room wondering where their mother is.
			for _, person in wanted do
				missing[person.id] = `no part tagged "{placeId}"`
			end
			continue
		end

		local center = place.part.Position
		local taken: { Vector3 } = {}
		for _, person in People.At(placeId) do
			local already = here[person.id]
			if already ~= nil then
				table.insert(taken, already.visitor.at())
			end
		end

		for _, person in wanted do
			local member = Cast.ById[person.castId]
			if member == nil then
				missing[person.id] = `cast as "{person.castId}", who is not in the cast`
				continue
			end

			local spot = spotFor(center, taken, PEOPLE.StandStuds, PEOPLE.StandBearings)
			if spot == nil then
				-- Not spawned rather than crammed in. A mother standing inside a wall is
				-- worse than a mother who is out at the moment, and this is the one failure
				-- of the system that looks exactly like a bug in the place tagging -- which
				-- is why it is written down instead of dropped.
				missing[person.id] = `no room to stand within {PEOPLE.StandStuds} studs of "{placeId}"`
				continue
			end
			-- Claimed before the yield below, so two people asked for in the same rebuild
			-- cannot be handed the same bearing.
			table.insert(taken, spot)

			-- Facing out from the middle of the place, so they are looking at whoever walks
			-- up rather than at the wall behind it. Head tracking takes over from there.
			local outward = spot - center
			local flat = Vector3.new(outward.X, 0, outward.Z)
			local facing = if flat.Magnitude < 0.01 then Vector3.new(0, 0, -1) else flat.Unit

			if not putDown(person, member, spot, facing, nil, nil) then
				return
			end
		end
	end

	-- **Pass two: the town**, and this one is ordered by where its people actually are
	-- rather than by which building they belong to. That is the same change as everywhere
	-- else in this file: when the ceiling is reached it is now somebody genuinely across
	-- town who goes without a body, rather than somebody standing in front of the player
	-- who happens to belong to a further-away place.
	local mine = ghosts[player] or {}

	-- One list for the whole town rather than one per place, because they are no longer at
	-- their places -- two people from opposite ends of the roster can be standing on the
	-- same corner, and a per-place list would let them into each other.
	local townTaken: { Vector3 } = {}
	for _, stand in here do
		if People.IsTown(stand.person.id) then
			table.insert(townTaken, stand.visitor.at())
		end
	end

	local townWanted: { { person: Person, ghost: Ghost, distance: number } } = {}
	for _, person in People.All do
		if not People.IsTown(person.id) or not People.IsAround(person, age, data.flags) then
			continue
		end
		if here[person.id] ~= nil then
			continue
		end

		local ghost = mine[person.id]
		if ghost == nil then
			-- `ensureGhosts` declines for exactly one reason. Recorded here rather than
			-- there because this is the table `/people` reads, and a townsperson missing
			-- because their building was never tagged looks identical from the pavement to
			-- one missing because they are across town.
			missing[person.id] = `no part tagged "{person.placeId}"`
			continue
		end

		local distance = inRange[person.id]
		if distance == nil then
			-- Out of range: a row in a table, and a position still walking around the town,
			-- until the player comes down whichever street they are on.
			continue
		end
		table.insert(townWanted, { person = person, ghost = ghost, distance = distance })
	end

	table.sort(townWanted, function(a, b): boolean
		if a.distance == b.distance then
			return a.person.id < b.person.id
		end
		return a.distance < b.distance
	end)

	for _, entry in townWanted do
		local person = entry.person
		if townBodied >= TOWN.MaxBodied then
			-- The ceiling, and it is a real one: every body past it is a yielding web call
			-- and a rig to animate. Written down rather than dropped quietly, because a
			-- street that is a third as busy as the content says it is looks exactly like a
			-- generator bug from the pavement.
			missing[person.id] = `over the {TOWN.MaxBodied}-body town limit`
			continue
		end

		local member = Cast.ById[person.castId]
		if member == nil then
			missing[person.id] = `cast as "{person.castId}", who is not in the cast`
			continue
		end

		local ghost = entry.ghost
		local spot = spotAt(ghost.at, ghost.wander.home, townTaken)
		if spot == nil then
			missing[person.id] = `no room to stand where they had walked to, nor at "{person.placeId}"`
			continue
		end
		table.insert(townTaken, spot)

		-- Facing the way they were already going, so somebody appearing at the edge of view
		-- is mid-journey rather than mid-turn. Standing still, they face away from the place
		-- they belong to, which is what the ring used to give them for free.
		local look = if ghost.goal ~= nil then ghost.goal - spot else spot - ghost.wander.home
		local flat = Vector3.new(look.X, 0, look.Z)
		local facing = if flat.Magnitude < 0.01 then Vector3.new(0, 0, -1) else flat.Unit

		-- A breath between strangers. Walking onto a busy street asks for up to a dozen
		-- rigs at once, and a dozen simultaneous web-backed avatar builds is a hitch you
		-- can feel; spread out, they fill in over about a second and read as people walking
		-- into view. Deliberately before the spawn rather than after, so the re-check inside
		-- `putDown` covers this yield as well as the build's.
		task.wait(TOWN.SpawnPaceSeconds)

		if not putDown(person, member, spot, facing, ghost.wander, ghost.goal) then
			return
		end
		-- Counted off the roster rather than off the call, because `putDown` reports a
		-- world that is still standing even when the rig itself could not be built.
		if here[person.id] ~= nil then
			townBodied += 1
		end
	end

	-- Everybody, not just the arrivals. This runs on every birthday and every flag that
	-- moves, and both of those change what people who were already standing there have
	-- left to give -- a year rolling over is what re-lights the whole street.
	refreshAllOverhead(player)

	-- The roster is rebuilt on exactly the occasions the world is -- join, birthday, a
	-- flag that moved -- because those are the same occasions a name can appear on it.
	pushRoster(player)
end

-- Rebuilds are serialized per player and coalesced, because `rebuild` yields and two
-- overlapping ones would each spawn the people the other had not finished spawning yet.
-- A request arriving mid-rebuild sets a flag rather than queueing, so any number of
-- birthdays in a row cost one extra pass.
local rebuilding: { [Player]: boolean } = {}
local rebuildAgain: { [Player]: boolean } = {}

local function requestRebuild(player: Player)
	if rebuilding[player] then
		rebuildAgain[player] = true
		return
	end
	rebuilding[player] = true

	task.spawn(function()
		repeat
			rebuildAgain[player] = false
			local ok, err = pcall(rebuild, player)
			if not ok then
				warn(`[AGES] could not put people in the world for {player.Name}: {err}`)
			end
		until not rebuildAgain[player]
		rebuilding[player] = nil
		rebuildAgain[player] = nil
	end)
end

-- What they say back, held on the row for a beat. `good` is only the colour of it, and a
-- refusal at the door comes through as a reply that is not good -- which is the honest
-- reading of somebody telling you they have no time today.
local function reply(chat: Chat, text: string, good: boolean)
	chat.replyText = text
	chat.replyGood = good
	chat.replyLeft = PEOPLE.ReplySeconds
end

-- Walking up to somebody. This is not the conversation -- that starts when the player
-- clicks the dots -- it is the game working out what would be on the panel if they did,
-- so the row on the HUD can name who they are next to and the panel can open the instant
-- it is asked for rather than a round trip later.
local function open(player: Player, data: LifeData, stand: Standing)
	local person = stand.person
	local chat: Chat = {
		personId = person.id,
		offers = {},
		done = false,
		replyLeft = 0,
		replyText = nil,
		replyGood = false,
	}
	chats[player] = chat
	stand.visitor.greet()

	local age = ageYearsOf(data)
	if visitsAt(data, person.id, age) >= PEOPLE.VisitsPerYear then
		-- Their line, said unprompted. Somebody you have already had your hour with this
		-- year tells you so as you walk up, rather than making you click three dots to be
		-- turned away by a panel with nothing on it.
		chat.done = true
		reply(chat, person.busyLine, false)
		refreshOverhead(player, stand)
		push(player)
		return
	end

	local offers = People.OffersFor(person, offerContext(data, person))
	if #offers == 0 then
		-- The content file checks every age of every person has something takeable at any
		-- bond, so this cannot happen while that check stands. Said out loud rather than
		-- left as somebody you can walk up to and get nothing from, which is precisely the
		-- symptom that check exists to prevent.
		chat.done = true
		warn(`[AGES] "{person.id}" has nothing to offer at age {age}`)
		refreshOverhead(player, stand)
		push(player)
		return
	end

	chat.offers = offers
	refreshOverhead(player, stand)
	push(player)
end

-- An offer taken, off the panel. Returns whether it was: an id that is not on the list
-- this player was actually offered is refused rather than guessed at.
local function take(player: Player, data: LifeData, chat: Chat, stand: Standing?, offerId: string): boolean
	local offer: PersonOffer? = nil
	for _, candidate in chat.offers do
		if candidate.id == offerId then
			offer = candidate
			break
		end
	end
	if offer == nil then
		return false
	end

	-- A conversation walked up to has a body to react; a conversation on the phone has
	-- only the profile. Everything below guards on `stand` so one path serves both.
	local person = if stand ~= nil then stand.person else People.ById[chat.personId]
	if person == nil then
		return false
	end
	local age = ageYearsOf(data)

	-- Rolled before anything is written, so the branch below is deciding what to record
	-- rather than unpicking what it already did. Rolled on the server and never sent as
	-- odds the client could re-roll: this is the verdict, and it happens once.
	local refused = rollRefusal(offer, bondOf(data, person))

	-- The conversation is closed and the visit is recorded before anything is paid out, so
	-- a second click arriving behind the first -- a double tap, a retry, a payout that
	-- yields -- finds a conversation that is already over rather than paying twice.
	--
	-- A refusal spends the visit exactly like a yes does, and that is the cost that makes
	-- asking a decision. At one visit a year, a no is the year -- so what the player is
	-- weighing on the panel is not "is this free to try" but "is this the year to try it".
	chat.offers = {}
	chat.done = true
	data.visits[person.id] = { age = age, count = visitsAt(data, person.id, age) + 1 }
	-- Visiting someone is an act of social agency. Each visit earns the right
	-- to one ambient event this chapter, capped so the player cannot bank
	-- hundreds of visits and then sit still while the world dumps content.
	EventService.AwardAutonomy(player, 1)

	-- Record this interaction in NPC memory. The line they said back is what
	-- the player will remember -- a refused ask keeps the refused line, a yes
	-- keeps the offer's promise. Rolling buffer of 5 per person, oldest dropped.
	local interactionLine = if refused
		then (offer.refusedLine or person.busyLine)
		else (offer.yesLine or offer.line or person.busyLine)
	recordInteraction(data, person.id, age, interactionLine)
	-- A defining moment is the strongest interaction yet -- the line said at the
	-- highest bond this person has ever reached with the player. Replaces the
	-- previous defining moment for this person only.
	if not refused then
		local existing = data.definingMoment[person.id]
		if existing == nil or bondGain > 0 then
			data.definingMoment[person.id] = {
				personId = person.id,
				age = age,
				line = interactionLine,
			}
		end
	end

	-- A refused ask keeps a share of what saying yes would have been worth: you turned up
	-- and you asked, and the turning up happened either way. Rounded away from zero on
	-- purpose, so a share that would round down to nothing still moves something -- the
	-- difference between a softened blow and no softening at all.
	--
	-- Only for an ask that pays bond, though. The two loans cost bond to accept, because
	-- taking money off your mother is not free with her -- and a refusal must not hand
	-- that back as a *gain*. Zero is the honest answer there: she said no, and nothing
	-- about the two of you moved.
	local bondGain = if refused
		then (if offer.bond > 0 then math.max(math.round(offer.bond * PEOPLE.RefusedBondShare), 1) else 0)
		else offer.bond
	data.bonds[person.id] = math.clamp(bondOf(data, person) + bondGain, PEOPLE.MinBond, PEOPLE.MaxBond)

	-- Check whether a bond milestone was just crossed, and seed gossip about it.
	local newBond = data.bonds[person.id]
	for _, milestone in PEOPLE.BondMilestones do
		if newBond >= milestone then
			local key = person.id .. "_" .. milestone
			if data.bondMilestones[key] ~= true then
				data.bondMilestones[key] = true
				local label = milestoneLabel(milestone)
				GossipService.OnBondMilestone(player, person.name, label)
				BOND_MILESTONE:FireClient(player, {
					person = person.name,
					milestone = milestone,
					label = label,
				})
			end
		end
	end

	if refused then
		-- Nothing else moves. The stats and the money are what the favour *was*, and a
		-- favour that was not done cannot pay half of itself out.
		if stand ~= nil then
			stand.visitor.talk()
		end
		-- Validated at content load, so an ask always has one. The fallback is here
		-- because a missing line would otherwise show an empty row rather than a person.
		reply(chat, offer.refusedLine or person.busyLine, false)
		if stand ~= nil then
			refreshOverhead(player, stand)
		end
		push(player)
		return true
	end

	-- What this leaves behind, written before anything that yields or can fail. Same
	-- ordering rule EventService uses on an answer, and for the same reason: the record
	-- of what you did and the thing you did are one write, so there is no window in which
	-- a payout has landed and the fact that earned it has not.
	--
	-- Cleared before set, so an offer that does both ends up holding what it sets.
	if offer.clears ~= nil then
		for _, flagId in offer.clears do
			data.flags[flagId] = nil
		end
	end
	if offer.sets ~= nil then
		for _, flagId in offer.sets do
			-- Not overwritten if already held, exactly as on an event answer: the age on
			-- a flag is the year the life first did this, and it should not be quietly
			-- moved to the present by doing it again.
			if data.flags[flagId] == nil then
				data.flags[flagId] = age
			end
		end
	end

	-- The rung. Guarded rather than assigned, because the panel was built from a snapshot
	-- of the life and a birthday or another answer can have landed between it opening and
	-- this row being clicked -- and the two ways that matters are the two ways it would
	-- be wrong: a tie that has since been climbed past must not be walked back down, and
	-- a capped rung somebody else has taken in the meantime must not be handed out twice.
	local gives = offer.gives
	if gives ~= nil then
		local held = data.ties[person.id]
		local room = People.TieRoom(data.ties, age, data.flags)
		if Ties.RankOf(gives) > Ties.RankOf(held) and not room[gives] then
			data.ties[person.id] = gives
		end
	end

	local stats = offer.stats
	if stats ~= nil then
		for statName, delta in stats do
			StatService.AddStat(player, statName :: StatName, delta)
		end
	end

	local money = offer.money
	if money ~= nil then
		MoneyService.Add(player, money, `{person.id}:{offer.id}`)
	end

	-- A flag that moved can have changed who is in the life at all -- people gate on
	-- flags exactly as offers do -- and waiting for the next birthday to notice would
	-- mean earning somebody and then standing in an empty room for a year. Only when
	-- flags actually moved: a tie needs no rebuild, because nobody anywhere is gated on
	-- one and the plate over their head is refreshed below either way.
	if offer.sets ~= nil or offer.clears ~= nil then
		requestRebuild(player)
	end

	if stand ~= nil then
		stand.visitor.talk()
	end
	reply(chat, offer.line, offer.bond >= 0)

	-- A walk offer is the one offer whose content is the person leaving with you: nothing
	-- else happens on it, just the lease and the walk. The lease is set before Start --
	-- Start is the thing that reads it, and the despawn pass can run between these lines.
	-- It is the visitor already standing in front of you that walks, so no double is ever
	-- spawned and there is no ownership to hand back when the walk ends.
	--
	-- Walks are cut out of the phone list before it is offered, so this branch cannot
	-- actually run with `stand == nil` -- it is guarded for the type checker, not for the
	-- game: a person you are talking to through the roster has no legs to walk with.
	local walksTo = offer.walksTo
	if walksTo ~= nil and stand ~= nil then
		local mine = leased[player]
		if mine == nil then
			mine = {}
			leased[player] = mine
		end
		mine[person.id] = true
		local started = CompanionService.Start(
			player,
			stand.visitor,
			stand.roam,
			walksTo,
			offer.arrivalLine or "",
			nameOf(person),
			function()
				local owned = leased[player]
				if owned ~= nil then
					owned[person.id] = nil
				end
				refreshAllOverhead(player)
			end
		)
		if not started then
			mine[person.id] = nil
			warn(`[AGES] walk to "{walksTo}" did not start for "{person.id}"`)
		end
	end

	if stand ~= nil then
		refreshOverhead(player, stand)
	end
	-- A take can change who has anything left to say -- the visit is spent, the bond moved
	-- -- so the roster is refreshed off the same answer.
	pushRoster(player)
	push(player)
	return true
end

-- The nearest person within reach, or nil. Nearest rather than first found, because two
-- parents in one room stand a few studs apart and walking up to your father should not
-- get you your mother on the strength of table order.
local function nearest(player: Player, position: Vector3): Standing?
	local here = standing[player]
	if here == nil then
		return nil
	end

	local best: Standing? = nil
	local bestDistance = PEOPLE.ReachStuds
	for _, stand in here do
		if stand.visitor.gone() then
			continue
		end
		local distance = Ground.FlatDistance(position, stand.visitor.at())
		if distance <= bestDistance then
			best = stand
			bestDistance = distance
		end
	end
	return best
end

-- Being spoken to. They stop walking and turn to look at whoever walked up.
--
-- Two halves of one gesture and both are needed. Stopping without turning leaves you
-- talking to somebody's back; turning without stopping has them square up to you and
-- then stroll off mid-sentence, which is worse than either. Called every tick rather
-- than once, so the turn follows a player who circles them.
--
-- Skipped entirely while the person is walking with you. Their facing is the walk's to
-- aim -- it stands them behind you and turns them to you when you stop -- and a hold
-- that fought it would have somebody sliding sideways down the street, two drivers on
-- one body.
local function holdFor(player: Player, stand: Standing, position: Vector3)
	if isLeased(player, stand.person.id) then
		return
	end
	local roam = stand.roam
	if roam ~= nil then
		roam.pause()
	end
	stand.visitor.face(position)
end

-- Letting go. The order matters: the hold is what has AutoRotate switched off, so
-- releasing it after the walk resumed would be a step or two of somebody sliding
-- sideways down the street before they turned to face where they were going.
--
-- Skipped while the person is walking with you for the same reason the hold is: the
-- walk paused the roam when it started and resumes it when it ends, and a release that
-- resumed it early would be the walk and the wander fighting over one set of legs.
local function release(player: Player, stand: Standing)
	if isLeased(player, stand.person.id) then
		return
	end
	stand.visitor.face(nil)
	local roam = stand.roam
	if roam ~= nil then
		roam.resume()
	end
end

-- Walking away. Nothing to take down -- the dots belong to the person and stay with
-- them -- so this is only the game forgetting what it had worked out, which is also what
-- makes walking a step away and back the way to get a stale panel recomputed.
--
-- It is also where somebody goes back to their day, and that has to happen here rather
-- than at any of the places a conversation ends: there are several of those and only one
-- of this, and a person left held forever is a person who never walks again.
local function closeChat(player: Player)
	local chat = chats[player]
	chats[player] = nil
	if chat == nil then
		return
	end
	local here = standing[player]
	local stand = if here ~= nil then here[chat.personId] else nil
	if stand ~= nil and not stand.visitor.gone() then
		release(player, stand)
	end
end

-- The town, one second at a time: everybody who has no body walks a little further, and
-- then the set of people close enough to deserve one is compared against what it was.
--
-- Both halves on one clock rather than two, and that is deliberate -- the second question
-- is asked about the answer to the first, and a presence check running against positions
-- from a different tick would build somebody at where they used to be.
--
-- Slower than the conversation tick because it is asking where in town somebody is, which
-- changes on the scale of a walk rather than of a frame. The comparison is against the
-- digest rather than against the rig list for the same reason: this has to be cheap enough
-- to run forever and do nothing, because doing nothing is the answer almost every time.
local function tickTown(player: Player, elapsed: number)
	local profile = DataService.GetProfile(player)
	if profile == nil or not enabled or not Lives.Active(profile.Data).alive then
		return
	end
	-- Mid-rebuild. The pass in flight is already measuring presence for itself, and moving
	-- people underneath it would put somebody between the take-down and the spawn.
	if rebuilding[player] then
		return
	end

	local mine = ghosts[player]
	if mine == nil then
		return
	end

	if Roam.IsEnabled() then
		local here = standing[player]
		for id, ghost in mine do
			-- Only the bodiless. Anybody with a rig is being walked by Roblox along this
			-- same wander, and integrating them as well would be two things moving one
			-- person -- the position would arrive at the far end of town while the body
			-- was still crossing the road.
			local stand = if here ~= nil then here[id] else nil
			if stand == nil or stand.visitor.gone() then
				stepGhost(ghost, elapsed)
			end
		end
	end

	local digest = townDigest(townInRange(player, characterPosition(player)))
	if presence[player] == digest then
		return
	end
	requestRebuild(player)
end

local function tickPlayer(player: Player, elapsed: number)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)
	local position = characterPosition(player)

	local chat = chats[player]
	if chat ~= nil then
		local here = standing[player]
		local stand = if here ~= nil then here[chat.personId] else nil

		-- A conversation on the phone. There is no body to walk away from, so the
		-- ends that matter are different: the person we called is now in the room, which
		-- hands the conversation straight back to the walk-up path; somebody else is
		-- standing in reach, which means the next tick's `open` would overwrite us anyway,
		-- so we end cleanly first.
		if chat.remote then
			if not enabled or not data.alive or position == nil then
				closeChat(player)
				push(player)
				return
			end

			if stand ~= nil and not stand.visitor.gone() then
				closeChat(player)
				open(player, data, stand)
				return
			end

			if nearest(player, position) ~= nil then
				closeChat(player)
				push(player)
				return
			end

			if chat.replyLeft > 0 then
				chat.replyLeft -= elapsed
				if chat.replyLeft <= 0 then
					chat.replyLeft = 0
					chat.replyText = nil
				end
			end
			push(player)
			return
		end

		-- Every way a conversation ends by itself, asked before anything is asked of the
		-- player. Walking away is the only one of these that is a choice.
		if
			not enabled
			or not data.alive
			or position == nil
			or stand == nil
			or stand.visitor.gone()
			or Ground.FlatDistance(position, stand.visitor.at()) > PEOPLE.ReachStuds
		then
			closeChat(player)
			push(player)
			return
		end

		-- Re-aimed every tick, so somebody who walks around the person they are talking
		-- to is followed rather than left looking at where they used to be.
		holdFor(player, stand, position)

		if chat.replyLeft > 0 then
			chat.replyLeft -= elapsed
			if chat.replyLeft <= 0 then
				chat.replyLeft = 0
				chat.replyText = nil
			end
			push(player)
			return
		end

		push(player)
		return
	end

	if not enabled or not data.alive or position == nil then
		return
	end

	local found = nearest(player, position)
	if found ~= nil then
		-- Held before the greeting rather than after, so a walker is stopped on the tick
		-- they are reached instead of taking one more stride out of range and closing the
		-- conversation that just opened.
		holdFor(player, found, position)
		open(player, data, found)

		-- Record the approach the first tick the player reaches this person. A player
		-- standing still next to the same NPC does not count as a new approach on every
		-- tick; the target is cleared when the player walks away or a different person
		-- is reached.
		local target = approachTarget[player]
		if target == nil or target ~= found.person.id then
			local list = approaches[player]
			if list == nil then
				list = {}
				approaches[player] = list
			end
			table.insert(list, { at = os.clock(), personId = found.person.id })
			if #list > 20 then
				table.remove(list, 1)
			end
			approachTarget[player] = found.person.id
		end
	else
		approachTarget[player] = nil
	end
end

-- Something picked off the panel in front of somebody.
--
-- Everything the client sent is re-derived here rather than trusted: which person, that
-- they are still standing there, that the player is still next to them, and that the
-- offer is one of the ones this profile was actually shown. The client is a screen. What
-- it says arrived is only ever a question.
local function onOfferRequested(player: Player, personId: unknown, offerId: unknown)
	if type(personId) ~= "string" or type(offerId) ~= "string" then
		return
	end
	if not enabled then
		return
	end
	local profile = DataService.GetProfile(player)
	if profile == nil or not Lives.Active(profile.Data).alive then
		return
	end

	-- `done` is the whole of the double-click defence. `take` sets it before it pays
	-- anything out, so a second click behind the first stops here.
	local chat = chats[player]
	if chat == nil or chat.done or chat.personId ~= personId then
		return
	end

	local here = standing[player]
	local stand = if here ~= nil then here[personId] else nil
	if stand == nil or stand.visitor.gone() then
		return
	end

	-- Checked again rather than taken from the fact that a conversation is open, because
	-- the panel stays up while the player walks: this is what stops somebody opening the
	-- dots on their mother and then collecting from the far side of the house.
	local position = characterPosition(player)
	if position == nil or Ground.FlatDistance(position, stand.visitor.at()) > PEOPLE.ReachStuds then
		return
	end

	take(player, Lives.Active(profile.Data), chat, stand, offerId)
end

-- A conversation started off the roster, without a body in the room. Same shape as `open`
-- -- the profile, the offers, the once-a-year visit -- but the person is resolved from
-- their id rather than a standing rig, `remote` marks it for the panel and the tick, and
-- the walks are cut out because a phone call has no legs.
local function openRemote(player: Player, data: LifeData, person: Person): boolean
	local chat: Chat = {
		personId = person.id,
		offers = {},
		done = false,
		replyLeft = 0,
		replyText = nil,
		replyGood = false,
		remote = true,
	}
	chats[player] = chat

	local age = ageYearsOf(data)
	if visitsAt(data, person.id, age) >= PEOPLE.VisitsPerYear then
		chat.done = true
		reply(chat, person.busyLine, false)
		push(player)
		return true
	end

	local callable = callableOffers(data, person)
	if #callable == 0 then
		-- The roster's green dot is callable offers, so this cannot happen while the
		-- roster and this function read the same list. Said out loud for the same reason
		-- `open` says its own impossible case out loud.
		chat.done = true
		reply(chat, person.busyLine, false)
		push(player)
		return true
	end

	chat.offers = callable
	push(player)
	return true
end

-- A name tapped on the roster. Everything the client sent is re-derived rather than
-- trusted, exactly as on an offer: that the person is real and in this life, and -- for
-- the one rule worth refusing over -- that no other conversation is already open.
local function onContactRequested(player: Player, personId: unknown)
	if type(personId) ~= "string" then
		return
	end
	if not enabled then
		return
	end
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)
	if not data.alive then
		return
	end

	-- The one-chat rule, refused out loud. There is no panel to overwrite here -- the
	-- roster is not in the room with you -- so the player who taps somebody while already
	-- mid-conversation gets told rather than silently ignored.
	local chat = chats[player]
	if chat ~= nil and not chat.done then
		if chat.personId == personId then
			push(player)
		else
			NoticeRemote:FireClient(player, "You're already in the middle of a conversation.")
		end
		return
	end

	local person = People.ById[personId]
	if person == nil or not People.IsAround(person, ageYearsOf(data), data.flags) then
		return
	end

	-- If the person we are calling is actually standing within reach, the tap is really
	-- a walk-up: open in person, so the dots and the reaction are real.
	local here = standing[player]
	local stand = if here ~= nil then here[personId] else nil
	if stand ~= nil and not stand.visitor.gone() then
		local position = characterPosition(player)
		if position ~= nil and Ground.FlatDistance(position, stand.visitor.at()) <= PEOPLE.ReachStuds then
			open(player, data, stand)
			return
		end
	end

	openRemote(player, data, person)
end

-- Forgets this player entirely. The people themselves go with `despawnAll`, and their
-- dots go with them -- there is nothing of this player's left in the workspace once
-- their rigs are gone.
local function forget(player: Player)
	closeChat(player)
	despawnAll(player)
	unplaced[player] = nil
	presence[player] = nil
	pushed[player] = nil
	pushedRoster[player] = nil
	rebuilding[player] = nil
	rebuildAgain[player] = nil
	approaches[player] = nil
	approachTarget[player] = nil
end

-- A birthday. Positives ratchet; decay is removed. Bonds only rise when you turn up;
-- they never fall from absence. The roster is rebuilt because a year is when people
-- arrive in a life and leave it.
--
-- LifeService calls this after the age has moved, so the year being judged is the one
-- just left: the age reached, less one. Getting that off by one would charge for a year
-- somebody was not around for and let the year they arrived go unjudged.
function PeopleService.OnAgeUp(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)

	-- No decay loop. Bonds are ratcheted gains only -- see Config.People.DecayPerYearAway = 0.

	requestRebuild(player)
	-- Ahead of the rebuild as well as inside it. The rebuild yields on avatar builds, and
	-- the year rolling over is what re-lights everybody -- a street that stays dark for
	-- however long a web call takes is a street that looks like it has nothing in it.
	refreshAllOverhead(player)
	push(player)
end

-- A new life. Nobody inherits a relationship, which is the point: a bond that survived
-- the person who had it would be the one thing in this game death did not cost.
--
-- Called twice by LifeService -- once when the player dies and once when the next one
-- starts -- and safe both times. The rebuild is delayed so the death screen is read over
-- an empty room rather than over four relatives waiting to meet the next occupant.
function PeopleService.ResetForNewLife(player: Player)
	closeChat(player)
	despawnAll(player)
	push(player)

	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	Lives.Active(profile.Data).bonds = {}
	Lives.Active(profile.Data).visits = {}
	-- Emptied with the bonds, and this one is the harder half to accept: the friend the
	-- last life earned is that person's friend, not the next child's. A tie that outlived
	-- its owner would be the one relationship in the game death did not cost, and it
	-- would also be nonsense -- the town is thirty adults, and a newborn who arrives
	-- already being somebody's closest friend has not been born, they have been restored.
	Lives.Active(profile.Data).ties = {}

	task.delay(PEOPLE.RespawnDelaySeconds, function()
		-- Re-read rather than closing over the profile: the player can leave, or die
		-- again, inside the delay.
		if DataService.GetProfile(player) ~= profile then
			return
		end
		requestRebuild(player)
	end)
end

-- Studio harness: sets what somebody thinks of this player, so the offers a bond unlocks
-- can be stood in front of without spending a childhood earning them.
function PeopleService.SetBond(player: Player, personId: string, bond: number): boolean
	local profile = DataService.GetProfile(player)
	local person = People.ById[personId]
	if profile == nil or person == nil then
		return false
	end
	Lives.Active(profile.Data).bonds[personId] = math.clamp(bond, PEOPLE.MinBond, PEOPLE.MaxBond)

	-- The offers held for them were worked out from the old number, so they are wrong now.
	-- Dropped rather than recomputed in place: a panel the player already has open would
	-- otherwise silently become a different list of things than the one they are reading.
	local chat = chats[player]
	if chat ~= nil and chat.personId == personId then
		closeChat(player)
	end
	refreshAllOverhead(player)
	push(player)
	return true
end

-- What the life is to everybody in it, for the harness. Only the people who are actually
-- something -- a list that named all thirty-four would be thirty-odd rows of "nothing in
-- particular" hiding the two that matter.
function PeopleService.DescribeTies(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "ties | no profile"
	end
	local data = Lives.Active(profile.Data)
	local age = ageYearsOf(data)

	local rows: { string } = {}
	local lapsed = 0
	for _, person in People.All do
		local tieId = data.ties[person.id]
		if tieId == nil then
			continue
		end
		local label = Ties.LabelOf(tieId) or tieId
		-- Marked rather than hidden, because "why is nobody offering me the closest-friend
		-- row" and "why *is* somebody offering it when I already have one" are the two
		-- questions this command exists to answer, and both turn on exactly this.
		if People.IsAround(person, age, data.flags) then
			table.insert(rows, `{nameOf(person)}: {label}`)
		else
			lapsed += 1
			table.insert(rows, `{nameOf(person)}: {label} (lapsed)`)
		end
	end

	local room = People.TieRoom(data.ties, age, data.flags)
	local capped: { string } = {}
	for _, def in Ties.All do
		if def.limit ~= nil then
			table.insert(capped, `{def.id} {if room[def.id] then "full" else "open"}`)
		end
	end

	local head = `ties | {#rows} held, {lapsed} lapsed | {table.concat(capped, ", ")}`
	if #rows == 0 then
		return `{head} | nobody in particular yet`
	end
	return `{head} | {table.concat(rows, " · ")}`
end

-- Approach-rate debug. Reports seconds-since-last-approach and the rolling average of
-- the last twenty intervals, so the quota ("at least one approach per sixty seconds
-- of walking") is visible rather than assumed.
--
-- Returns nil when there is no data to report.
function PeopleService.DescribeApproaches(player: Player): string?
	local list = approaches[player]
	if list == nil or #list < 2 then
		return nil
	end

	local now = os.clock()
	local last = list[#list]
	local secondsSince = now - last.at

	-- Rolling average of the intervals between the last twenty approaches.
	local total = 0.0
	for i = 2, #list do
		total += list[i].at - list[i - 1].at
	end
	local average = total / (#list - 1)

	return `approaches | last {math.floor(secondsSince)}s ago | rolling avg {math.floor(average)}s | {#list} recorded`
end

-- Studio harness: makes somebody what they would otherwise take a childhood of turning up
-- to become, so the offers a tie unlocks can be stood in front of. Deliberately ignores
-- the cap -- this is the one place that should be able to produce the state a capped rung
-- is supposed to make impossible, because that is the state worth testing.
function PeopleService.SetTie(player: Player, personId: string, tieId: string?): boolean
	local profile = DataService.GetProfile(player)
	local person = People.ById[personId]
	if profile == nil or person == nil then
		return false
	end
	if tieId ~= nil and Ties.ById[tieId] == nil then
		return false
	end
	Lives.Active(profile.Data).ties[personId] = tieId

	-- Same reason SetBond drops the open panel: the rows the player is reading were
	-- worked out from the old answer, and a tie changes which of them exist.
	local chat = chats[player]
	if chat ~= nil and chat.personId == personId then
		closeChat(player)
	end
	refreshAllOverhead(player)
	push(player)
	return true
end

-- Studio harness: clears the once-a-year cap, so the same visit can be run again without
-- waiting on a birthday.
function PeopleService.ClearVisits(player: Player): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	Lives.Active(profile.Data).visits = {}
	closeChat(player)
	refreshAllOverhead(player)
	push(player)
	return true
end

-- Everybody currently standing in the world for this player, as ids and positions.
--
-- Exists for WitnessService, which needs to know who can see a wanted player and must not
-- be given the rigs to find out: a service that could reach a Visitor could pause a walk,
-- turn a head or destroy a body, and the crowd's only business is looking. Positions rather
-- than handles is the whole of the encapsulation, and it is the same argument Till makes
-- about handing out a Vector3 instead of a piece of shop furniture.
--
-- Includes the family, who are people too and who live in rooms the player has every reason
-- to hide in. A mother who does not notice her son sprinting through the kitchen with the
-- police outside would be a strange thing to have built on purpose.
export type Bystander = {
	personId: string,
	position: Vector3,
}

function PeopleService.Bystanders(player: Player): { Bystander }
	local out: { Bystander } = {}
	local here = standing[player]
	if here == nil then
		return out
	end
	for personId, stand in here do
		local visitor = stand.visitor
		if visitor.gone() then
			continue
		end
		table.insert(out, { personId = personId, position = visitor.root.Position })
	end
	return out
end

-- Somebody stops walking and turns to look, or goes back to what they were doing.
--
-- The reaction, and it is the whole of the crowd's signposting: a witness is on screen for
-- Config.Crime.Witness.SeeSeconds *before* the report lands, which is the player's warning
-- and their chance to walk out of it. The gesture is deliberately the same one a person
-- makes when you walk up to talk to them -- stop, turn -- because a town has one vocabulary
-- and a second "notice" animation would read as a different kind of creature.
--
-- Refused outright while the player is mid-conversation with them. Two systems driving one
-- pair of legs is the bug the hold and release below were written to avoid, and a chat is
-- the one that was there first.
function PeopleService.Alarm(player: Player, personId: string, at: Vector3?): boolean
	local here = standing[player]
	local stand = if here ~= nil then here[personId] else nil
	if stand == nil or stand.visitor.gone() then
		return false
	end
	local chat = chats[player]
	if chat ~= nil and chat.personId == personId then
		return false
	end
	if at == nil then
		release(player, stand)
	else
		holdFor(player, stand, at)
	end
	return true
end

-- Off empties the street of everybody, on puts them back. Applied to every player rather
-- than to whoever typed it, because this is a switch on the world and a server with
-- people in it for one player and not another would be a worse test than either state.
function PeopleService.SetEnabled(value: boolean)
	enabled = value
	for _, player in Players:GetPlayers() do
		if not value then
			closeChat(player)
			push(player)
		end
		requestRebuild(player)
	end
end

-- What the harness prints. Everybody who should be in this life, whether they are
-- standing in it, and what they think of the player -- in that order, because that is
-- the order the questions get asked in when somebody is missing.
--
-- The four only. The town is thirty more rows of the same shape and would push the
-- family off the top of the output, which is the one thing this command exists to show;
-- `/town` answers for them, and it can answer in the terms that actually matter for a
-- stranger -- where they are and whether they have a body -- rather than these.
function PeopleService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "people: no profile loaded"
	end
	local data = Lives.Active(profile.Data)
	local age = ageYearsOf(data)

	local here = standing[player] or {}
	local missing = unplaced[player] or {}

	local lines: { string } = {}
	for _, person in People.All do
		if People.IsTown(person.id) or not People.IsAround(person, age, data.flags) then
			continue
		end
		local bond = bondOf(data, person)
		local where = if here[person.id] ~= nil
			then `at {person.placeId}`
			else `NOT SPAWNED ({missing[person.id] or "no reason recorded"})`
		local seen = visitsAt(data, person.id, age)
		local visited = if seen > 0 then `, seen {seen}/{PEOPLE.VisitsPerYear} this year` else ""
		local offers = People.OffersFor(person, offerContext(data, person))
		-- The odds spelled out as a figure, which is the one place in this system they
		-- are. The panel says "a long shot" because the player is making a judgement;
		-- a harness needs to know whether the number behind it is the one intended.
		local asks: { string } = {}
		for _, offer in offers do
			if offer.ask then
				table.insert(asks, `{offer.id} {math.round(refusalChance(offer, bond) * 100)}% no`)
			end
		end
		local risk = if #asks > 0 then `, asks: {table.concat(asks, ", ")}` else ""
		table.insert(lines, `{person.id} {where}, {bond} ({bandFor(bond)}), {#offers} offers{visited}{risk}`)
	end
	if #lines == 0 then
		table.insert(lines, `nobody is in this life at age {age}`)
	end

	local talking = "not talking to anybody"
	local chat = chats[player]
	if chat ~= nil then
		talking = `next to {chat.personId}, {#chat.offers} offers`
			.. (if chat.done then ", nothing left to take" else "")
	end

	return string.format(
		"people: %s | refusals %s | age %d | %s | %s | town: see /town",
		if enabled then "enabled" else "DISABLED",
		refusalMode,
		age,
		talking,
		table.concat(lines, " · ")
	)
end

-- The town, in the terms a town raises. Not "who is missing" -- thirty people with no
-- bodies is the normal state of this system -- but where the player is, how much of the
-- rig budget is spent, and who is close enough to walk up to.
--
-- `OldestShownAge` is reported as a count rather than left implicit, because a plate with
-- no age on it is the game declining to claim a number it does not model, and a hole like
-- that should be visible from the harness instead of only from the pavement.
export type TownDetail = "summary" | "all" | "bodied"

function PeopleService.DescribeTown(player: Player, detail: TownDetail): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "town: no profile loaded"
	end
	local data = Lives.Active(profile.Data)
	local age = ageYearsOf(data)

	local here = standing[player] or {}
	local mine = ghosts[player] or {}
	local position = characterPosition(player)
	local nearPlaces = nearPlacesFor(position)

	local inLife = 0
	local bodied = 0
	local ageless = 0
	local rows: { { text: string, distance: number } } = {}

	-- People close enough to your own age to be your contemporaries, counted separately
	-- from the roster because the roster answers "is the town there" and this answers "is
	-- there anybody in it your age", and for most of adulthood those had wildly different
	-- answers. Not split by anything: there is no partner system, so every peer counts the
	-- same, and the number that matters is simply whether it is zero.
	local peers = 0

	-- The youngest the player could be and have anybody in the town at all. Only ever
	-- printed when the answer is nobody, and it is the reading that would have saved the
	-- most time: an empty street looks exactly like a spawner that has stopped working,
	-- and the one thing that tells the two apart is that an age window has not opened yet.
	local soonest: number? = nil

	for _, person in People.All do
		if not People.IsTown(person.id) then
			continue
		end
		if not People.IsAround(person, age, data.flags) then
			-- Read through a local rather than compared against the upvalue directly, so the
			-- nil case is narrowed somewhere the checker can see it across the assignment.
			local best = soonest
			if person.minAge > age and (best == nil or person.minAge < best) then
				soonest = person.minAge
			end
			continue
		end
		inLife += 1
		if People.ShownAge(person, age) == nil then
			ageless += 1
		end

		local gender = genderOf(person)
		if isPeer(person) then
			peers += 1
		end

		local stand = here[person.id]
		if stand ~= nil then
			bodied += 1
		end
		if detail == "summary" or (detail == "bodied" and stand == nil) then
			continue
		end

		-- Distance to where they *are*, which for most of the town is a position with no
		-- rig on it. Reporting the place they belong to instead is what made the old
		-- listing agree with a bug: everybody read as being at their building because the
		-- only thing that had ever been measured was their building.
		local ghost = mine[person.id]
		local distance = if stand ~= nil and position ~= nil
			then Ground.FlatDistance(position, stand.visitor.at())
			elseif ghost ~= nil and position ~= nil then Ground.FlatDistance(position, ghost.at)
			else math.huge
		local shown = People.ShownAge(person, age)
		local roam = if stand ~= nil then stand.roam else nil
		local body = if stand ~= nil
			then `{math.round(distance)} studs away, {if roam ~= nil then roam.state() else "planted"}`
			elseif ghost ~= nil
				then `no body, {math.round(distance)} studs away, {if ghost.goal ~= nil then "walking" else "resting"}`
			else "no body, nowhere to be"
		local bond = bondOf(data, person)
		-- The gender initial is a bare label -- the only place gender surfaces to a human --
		-- and "peer" rides with the age rather than the name, because whether they counted
		-- in the peer tally above is only legible beside the number that put them there.
		local marks = if gender ~= nil then string.sub(gender, 1, 1) else "?"
		if isPeer(person) then
			marks ..= " peer"
		end
		table.insert(rows, {
			distance = distance,
			text = `{person.id} {nameOf(person)} ({People.ArchetypeOf(person.id) or "?"}) `
				.. `at {person.placeId}, age {if shown ~= nil then tostring(shown) else "hidden"} `
				.. `{marks}, bond {bond} ({bandFor(bond)}), {body}`,
		})
	end

	-- Nearest first, so the rows a harness cares about -- the people actually in front of
	-- the player -- are the ones at the top rather than wherever the id order put them.
	table.sort(rows, function(a, b): boolean
		if a.distance == b.distance then
			return a.text < b.text
		end
		return a.distance < b.distance
	end)

	local nearIds: { string } = {}
	for placeId, distance in nearPlaces do
		table.insert(nearIds, `{placeId} {math.round(distance)}`)
	end
	table.sort(nearIds)
	local nearText = if #nearIds > 0 then table.concat(nearIds, ", ") else "nowhere"

	local peerText = string.format("%d within %d years of you", peers, PEOPLE.PeerAgeGap)

	-- The tagged-point count is here rather than only in the listing because zero is the
	-- reading that explains the most: it means everyone is wandering to probed spots,
	-- which is working as designed and looks nothing like people using the streets.
	--
	-- The peer count is here for the mirror-image reason: zero peers is a generator that
	-- put nobody your age in the world, which reads as an empty life even when the roster
	-- is full -- and those two have to be tellable apart from one line.
	local head = string.format(
		"town: %d in this life at age %d (%s) | %s | %d/%d bodied | "
			.. "walking %s, %d town points tagged | near: %s | %d past age %d so no age shown",
		inLife,
		age,
		data.gender or "no gender",
		peerText,
		bodied,
		TOWN.MaxBodied,
		if Roam.IsEnabled() then "on" else "OFF",
		Routes.NodeCount(),
		nearText,
		ageless,
		TOWN.OldestShownAge
	)

	-- Zero is the one count that has to explain itself. Every other reading here can be
	-- chased -- no points tagged, walking OFF, nobody within the radius -- but "nobody in
	-- this life" is indistinguishable from a broken spawner unless the listing says out
	-- loud that it is an age window rather than a fault. That distinction cost a whole
	-- debugging session once; it is one line and it never has to cost it again.
	if inLife == 0 then
		local first = soonest
		if first ~= nil then
			head ..= ` | nobody is around at this age -- the earliest townsfolk turn up at {first}`
		else
			head ..= " | nobody is around at this age, and nobody ever will be -- check Townsfolk"
		end
	end

	if detail == "summary" then
		return head
	end
	if #rows == 0 then
		return `{head} | nobody to list`
	end

	local texts: { string } = {}
	for _, row in rows do
		table.insert(texts, row.text)
	end
	return `{head} | {table.concat(texts, " · ")}`
end

-- The roads the town walks on, for `/town routes`. Routed through here rather than reached
-- into from the debug service so that everything `/town` can answer comes from one place --
-- and because "how many points are tagged" and "who is standing where" are two halves of
-- the same question whenever the answer to either is surprising.
function PeopleService.DescribeRoutes(): string
	return Routes.Describe()
end

-- The town's legs, all of them at once. The one switch that tells a walking bug apart
-- from a bonding one: with this off the town is exactly the standing roster Part 1 had,
-- so anything still wrong is not the walking.
--
-- Nobody is taken down or moved, and nobody mid-stride is frozen -- the walk in flight
-- is called off and they settle where they are, which is also what makes turning it back
-- on cost nothing.
function PeopleService.SetTownWalking(value: boolean)
	Roam.SetEnabled(value)
end

-- Forces or frees the coin behind an ask. Affects the roll only: the words on the panel
-- still read off the real odds, so "always" is a way to see a refusal without also
-- lying to the player about how likely one was.
function PeopleService.SetRefusalMode(mode: RefusalMode)
	refusalMode = mode
end

-- Studio harness, and the hook below. Debounced like every other rebuild request, so
-- several flags moving in one answer costs one pass over the roster rather than one each.
function PeopleService.Rebuild(player: Player)
	requestRebuild(player)
end

-- An answer that changed what this life has done can have changed who is in it, and
-- waiting for the next birthday to notice would mean earning a friend and then standing
-- in an empty room for a year. Only when flags actually moved: every other answer in the
-- game leaves the roster exactly as it was, and rebuilding on all of them would put a
-- pass over every person behind every choice a player makes.
local function onAnswered(player: Player, _event: Types.LifeEvent, choice: Types.EventChoice)
	if choice.sets == nil and choice.clears == nil then
		return
	end
	requestRebuild(player)
end

function PeopleService:Start()
	EventService.OnAnswered(onAnswered)

	RequestPersonOfferRemote.OnServerEvent:Connect(function(player: Player, personId: unknown, offerId: unknown)
		local ok, err = pcall(onOfferRequested, player, personId, offerId)
		if not ok then
			warn(`[AGES] person offer failed for {player.Name}: {err}`)
		end
	end)

	RequestPersonContactRemote.OnServerEvent:Connect(function(player: Player, personId: unknown)
		local ok, err = pcall(onContactRequested, player, personId)
		if not ok then
			warn(`[AGES] person contact failed for {player.Name}: {err}`)
		end
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			if DataService.WaitForProfile(player) ~= nil then
				requestRebuild(player)
				push(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(forget)

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			if DataService.WaitForProfile(player) ~= nil then
				requestRebuild(player)
			end
		end)
	end

	task.spawn(function()
		while true do
			local elapsed = task.wait(PEOPLE.TickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player, elapsed)
				if not ok then
					warn(`[AGES] people tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)

	-- The town walking, and the town coming and going. Its own loop rather than a line in
	-- the tick above, because that one runs four times a second to keep a panel honest and
	-- this one is moving thirty people a stride -- a question worth a fraction of that.
	--
	-- `elapsed` is the real gap rather than the asked-for one, so the town covers the same
	-- ground on a struggling server as on an idle one instead of walking in slow motion
	-- whenever something else is busy.
	task.spawn(function()
		while true do
			local elapsed = task.wait(TOWN.PresenceTickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickTown, player, elapsed)
				if not ok then
					warn(`[AGES] town tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)
end

return PeopleService
