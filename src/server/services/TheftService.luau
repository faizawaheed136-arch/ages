--!strict
-- The take. One verb -- hold to empty the drawer -- and two things watching you do it.
--
-- The whole activity is the interference between the clerk's cycle and the camera's.
-- Neither knows about the other and neither is aimed at the player: the clerk turns to
-- the register and back on a short beat, the camera sweeps the room on a longer one, and
-- the windows where neither is on the till open and close as the two drift past each
-- other. Config.Crime.Theft explains the arithmetic; what matters here is the consequence,
-- which is that this cannot be played by counting. It has to be watched.
--
-- Both cycles are computed from the clock rather than stored, and that is load-bearing in
-- two ways. It means every player in a shop sees the same clerk in the same position, so
-- two thieves at one counter are playing the same game rather than two private ones. And
-- it means the camera part on the wall and the `cameraWatching` field on the panel are
-- derived from one number, so they can never disagree -- which they would within a minute
-- if either were allowed to drift.
--
-- **Being seen is never an arrest here and never ends the robbery.** It adds heat and
-- reports a sighting, which hands the player to the pursuit half that is already built.
-- That is deliberate to the point of being the reason this file exists in this shape: a
-- theft mini-game that could be failed would be a mini-game with a lose screen, and what
-- this is meant to produce is an afternoon that got complicated. See the soft-failure
-- requirement in the activity law -- the multiplier here is how much heat you leave with,
-- and it runs continuously from nothing to a manhunt.
--
-- What this file does not do: decide where a shop is (Till), decide what heat buys
-- (BountyService), or put officers in the street (PoliceService). It takes money out of a
-- drawer and tells the bounty when somebody watched it happen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local BountyService = require(script.Parent.BountyService)
local DataService = require(script.Parent.DataService)
local GangService = require(script.Parent.GangService)
local MoneyService = require(script.Parent.MoneyService)
local NPCService = require(script.Parent.NPCService)
local PlaceService = require(script.Parent.PlaceService)

local Colors = require(script.Parent.Parent.world.Colors)
local Public = require(script.Parent.Parent.content.Public)
local Tills = require(script.Parent.Parent.content.Tills)
local Till = require(script.Parent.Parent.world.Till)

type LifeData = Types.LifeData
type TheftState = Types.TheftState
type Visitor = NPCService.Visitor
type GangCrewMember = Types.GangCrewMember

local TheftService = {}

local THEFT = Config.Crime.Theft

local TheftUpdatedRemote = Remotes.Get("TheftUpdated")
local RequestTillHoldRemote = Remotes.Get("RequestTillHold")
local RequestTillOpenRemote = Remotes.Get("RequestTillOpen")
local RequestTillCallCrewRemote = Remotes.Get("RequestTillCallCrew")

-- The clerk's whole cycle, and the camera's. Named because both are used in three places
-- and a robbery that used a different period in the aiming code from the one it used in
-- the state push would be a camera that lied.
local CLERK_PERIOD = THEFT.ClerkLookSeconds + THEFT.ClerkAwaySeconds
local CAMERA_PERIOD = THEFT.CameraSweepSeconds

-- What is in a drawer right now, per shop rather than per player. A till emptied by one
-- thief is empty for the next one, which is the only honest reading of a shared world and
-- also the thing that makes a second player on the same street a rival rather than a
-- duplicate.
type Drawer = {
	left: number,
	full: number,
	-- When it is worth robbing again, on the same clock everything else here uses. Held as
	-- a moment rather than counted down, so a shop nobody is standing in costs nothing.
	refillAt: number,
}

-- One player, at one till.
type Session = {
	place: string,
	name: string,
	-- Whether the client says the hands are in the drawer. Never trusted on its own: every
	-- tick re-checks reach, the drawer's balance and whether the player is still alive, and
	-- any of those failing takes the hands out regardless of what the client last said.
	holding: boolean,
	taken: number,
	-- How long an attention has been on the till while holding. The undo window, counted up
	-- rather than down because it resets to zero the instant the player lets go -- which is
	-- the entire mechanic and is much harder to get wrong in this direction.
	watchedFor: number,
	spotted: boolean,
	notice: string?,
	noticeLeft: number,
	clerk: Visitor?,
	-- Set while a clerk rig is being built, which yields. Without it a player who walks in,
	-- out and back in inside two seconds gets two clerks behind one counter.
	spawningClerk: boolean,

	-- The lookout: somebody's own crew, sent to watch the door instead of taking their
	-- chances alone. Per session, not per shop -- unlike Bank's alarm seat, there is
	-- nothing here for two robbers to share, so a lookout is exactly as private as the
	-- clerk above already is.
	lookout: Visitor?,
	spawningLookout: boolean,
	-- Whose crew this is, so a swap or a departure can find them again.
	lookoutCrewId: string?,
	lookoutName: string?,
	-- Rolled once, from the nerve they had when they were called -- see Config.Gangs.Jobs.
	lookoutFailChance: number,
	-- Whether this session has already spent its one roll. Set the instant it is used, at
	-- the first spotted transition below, and not reset by being spotted again: nerve buys
	-- one shot at softening getting caught, not a standing discount on every one after it.
	lookoutRolled: boolean,
}

local drawers: { [string]: Drawer } = {}
local sessions: { [Player]: Session } = {}
local pushed: { [Player]: string } = {}
local enabled = true

local function dataFor(player: Player): LifeData?
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return DataService.CurrentLife(profile)
end

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return nil
	end
	return (root :: BasePart).Position
end

-- Where a shop's cycles are, right now.
--
-- Offset per shop by a hash of its id, so two shops on one street are never in step. Two
-- synchronised clerks would teach the player a single rhythm that worked everywhere, which
-- is the numbers-only version of this activity: the thing worth learning is that each shop
-- has to be read on arrival.
local function shopPhase(place: string): number
	local sum = 0
	for index = 1, #place do
		sum += string.byte(place, index) * index
	end
	return sum % 1000 / 1000
end

-- True while the clerk is facing the till.
local function clerkOnTill(place: string, now: number): boolean
	local share = ((now / CLERK_PERIOD) + shopPhase(place)) % 1
	return share * CLERK_PERIOD < THEFT.ClerkLookSeconds
end

-- Where the camera is through its sweep, 0 to 1, and whether it is pointed at the drawer.
--
-- The sweep is a triangle, so the middle of the travel is straight ahead -- at the till --
-- and the camera crosses it twice per period: once on the way out and once on the way
-- back. The two crossings are what stop the pattern reading as a metronome even before
-- the clerk is folded in.
local function cameraAt(place: string, now: number): (number, boolean)
	local share = ((now / CAMERA_PERIOD) + shopPhase(place) * 0.5) % 1
	local folded = if share < 0.5 then share * 2 else (1 - share) * 2
	return share, math.abs(folded - 0.5) * 2 < THEFT.CameraOnTillShare
end

local function drawerFor(place: string, now: number): Drawer
	local existing = drawers[place]
	if existing ~= nil then
		if existing.left <= 0 and now >= existing.refillAt then
			existing.left = existing.full
		end
		return existing
	end

	local shop = Tills.Get(place)
	local full = THEFT.TillFloat * (if shop ~= nil then shop.richness else 1)
	local made: Drawer = { left = full, full = full, refillAt = 0 }
	drawers[place] = made
	return made
end

local function noticeFor(session: Session, text: string)
	session.notice = text
	session.noticeLeft = 4
end

local function stateFor(player: Player): TheftState?
	local session = sessions[player]
	if session == nil then
		return nil
	end
	local now = os.clock()
	local drawer = drawerFor(session.place, now)
	local _, cameraOn = cameraAt(session.place, now)

	-- A lookout is not a shared seat here, so it costs nothing to keep offering the panel
	-- even while one is already out -- calling again with a different id swaps who is
	-- standing there, same as CallCrew's own note.
	local crewCallable: { GangCrewMember } = {}
	local crew = GangService.CrewFor(player)
	if #crew > 0 then
		crewCallable = crew
	end

	return {
		place = session.name,
		tillLeft = drawer.left,
		tillFull = drawer.full,
		taken = session.taken,
		holding = session.holding,
		clerkWatching = clerkOnTill(session.place, now),
		cameraWatching = cameraOn,
		spotted = session.spotted,
		crewCallable = crewCallable,
		crewOnLookout = if session.lookout ~= nil then session.lookoutName else nil,
		notice = session.notice,
	}
end

local function push(player: Player)
	local state = stateFor(player)
	local digest: string
	if state == nil then
		digest = "none"
	else
		-- Money to the whole unit, because the drawer drains continuously and a panel
		-- redrawn on every cent would be a packet every tick of every robbery for a number
		-- nobody can read at that precision. Crew by id and nerve, not name, same reason as
		-- the bank digest: two members can share a name and must never share a digest entry.
		local crewBits = {}
		for _, member in state.crewCallable do
			table.insert(crewBits, `{member.id}:{math.floor(member.nerve)}`)
		end
		digest = `{state.place}/{math.floor(state.tillLeft)}/{math.floor(state.taken)}/`
			.. `{tostring(state.holding)}/{tostring(state.clerkWatching)}/{tostring(state.cameraWatching)}/`
			.. `{tostring(state.spotted)}/{table.concat(crewBits, ",")}/{tostring(state.crewOnLookout)}/`
			.. `{tostring(state.notice)}`
	end

	if pushed[player] == digest then
		return
	end
	pushed[player] = digest
	TheftUpdatedRemote:FireClient(player, state)
end

-- Somebody behind the counter, built once the player is standing at it.
--
-- A shop is not staffed until it is being robbed, which is a shortcut and worth naming as
-- one: staffing forty storefronts permanently is forty rigs the server builds for nobody.
-- What it costs is that a player who walks past an open door sees an empty shop, and the
-- honest fix for that is the ambient population work rather than a clerk per shop here.
local function spawnClerk(player: Player, session: Session)
	if session.clerk ~= nil or session.spawningClerk then
		return
	end
	local fitting = Till.Get(session.place)
	if fitting == nil then
		return
	end
	local spot = fitting.clerkSpot
	if spot == nil then
		-- No room behind this counter. The shop runs on its camera alone, which is easier
		-- and is allowed to be: a robbery that refused to start because the furniture was
		-- tight would be a door that does nothing for reasons nobody can see.
		return
	end

	session.spawningClerk = true
	task.spawn(function()
		local member = Public.Someone()
		local visitor = NPCService.Spawn(player, member, CFrame.new(spot, fitting.drawer))
		session.spawningClerk = false
		-- Everything below the spawn is re-checked, because Spawn yields on a web call and
		-- the player may have walked out, died or been arrested while it ran.
		if visitor == nil then
			return
		end
		if sessions[player] ~= session then
			visitor.destroy()
			return
		end
		session.clerk = visitor
	end)
end

local function despawnClerk(session: Session)
	local clerk = session.clerk
	if clerk ~= nil then
		session.clerk = nil
		if not clerk.gone() then
			clerk.destroy()
		end
	end
end

-- Turns the clerk. Facing the till or facing the shelves, which is the same fact the
-- panel's `clerkWatching` carries -- read off the same function, so the body and the
-- readout cannot drift apart.
local function aimClerk(session: Session, watching: boolean)
	local clerk = session.clerk
	if clerk == nil or clerk.gone() then
		return
	end
	local fitting = Till.Get(session.place)
	if fitting == nil then
		return
	end
	if watching then
		clerk.face(fitting.drawer)
		return
	end
	-- Away means away from the drawer, along the line from it, so the turn is the full
	-- hundred and eighty a player can read from the front of the counter rather than a
	-- glance to one side that looks the same from where they are standing.
	local from = clerk.at()
	clerk.face(from + (from - fitting.drawer))
end

-- Sends a body home. Called both when its owner walks out and when the crew member they
-- sent is no longer theirs to send -- dismissed off the gang panel while out on the job --
-- so the door is never watched by somebody who is not actually there anymore.
local function despawnLookout(session: Session)
	local lookout = session.lookout
	if lookout ~= nil then
		session.lookout = nil
		if not lookout.gone() then
			lookout.destroy()
		end
	end
	session.lookoutCrewId = nil
	session.lookoutName = nil
	session.lookoutFailChance = 0
	session.lookoutRolled = false
end

-- How reliably a nerve rating covers a robbery once, the first time it is spotted. Same
-- shape and the same reason as the bank's alarmFailChanceFor: linear between the two config
-- ends, so the number on the crew panel is a promise rather than a suggestion.
local function tillCoverFailChanceFor(nerve: number): number
	local jobs = Config.Gangs.Jobs
	local share = math.clamp(nerve / Config.Gangs.Crew.NerveMax, 0, 1)
	return jobs.TillCoverFailChanceAtZeroNerve
		+ (jobs.TillCoverFailChanceAtMaxNerve - jobs.TillCoverFailChanceAtZeroNerve) * share
end

-- Sends one of the player's own crew to watch the door. Per session rather than per shop,
-- same as the clerk -- there is no seat here for a second robber to contest.
local function spawnLookout(player: Player, session: Session, crew: GangCrewMember)
	if session.lookout ~= nil or session.spawningLookout then
		return
	end
	local fitting = Till.Get(session.place)
	if fitting == nil then
		return
	end
	local spot = fitting.lookoutSpot
	if spot == nil then
		-- No room by the door. The robbery runs without one, same reason the clerk can be
		-- missing: a shop that refused a lookout for reasons invisible from outside it would
		-- be worse than the role quietly being unavailable there.
		return
	end

	session.spawningLookout = true
	task.spawn(function()
		local member = GangService.CastMemberFor(crew)
		local visitor = NPCService.Spawn(player, member, CFrame.new(spot, fitting.lookoutFacing))
		session.spawningLookout = false
		-- Re-checked, because Spawn yields on a web call: the player may have walked out,
		-- ended the session or called a different crew member while it ran.
		if visitor == nil then
			return
		end
		if sessions[player] ~= session or session.lookout ~= nil then
			visitor.destroy()
			return
		end
		session.lookout = visitor
		session.lookoutCrewId = crew.id
		session.lookoutName = crew.name
		session.lookoutFailChance = tillCoverFailChanceFor(crew.nerve)
		session.lookoutRolled = false
		local color = GangService.ColorOf(player)
		if color ~= nil and not Colors.Apply(visitor.model, color) then
			warn(`[AGES] could not band {crew.name} -- they will look like anybody else`)
		end
		push(player)
	end)
end

-- Keeps the lookout on their spot and drops them the instant they stop being crew. There is
-- nothing else to tick: the one thing they do is the roll in tickPlayer, at the moment a
-- robbery is first spotted, and that is not a per-tick action.
local function tickLookout(player: Player, session: Session)
	local lookout = session.lookout
	if lookout == nil then
		return
	end
	local crewId = session.lookoutCrewId
	if lookout.gone() or crewId == nil then
		despawnLookout(session)
		return
	end

	-- Dismissed off the gang panel while out on this job. Checked every tick rather than
	-- only on call, same reason as the bank's crew helper: the gang panel has nothing to do
	-- with this till and must not have to know it exists.
	local stillCrew = false
	for _, member in GangService.CrewFor(player) do
		if member.id == crewId then
			stillCrew = true
			break
		end
	end
	if not stillCrew then
		local name = session.lookoutName
		despawnLookout(session)
		noticeFor(session, `{name} isn't running with you anymore, and heads off.`)
		return
	end

	local fitting = Till.Get(session.place)
	if fitting ~= nil and fitting.lookoutSpot ~= nil then
		lookout.moveTo(fitting.lookoutSpot)
	end
end

local function endSession(player: Player)
	local session = sessions[player]
	if session == nil then
		return
	end
	despawnClerk(session)
	despawnLookout(session)
	sessions[player] = nil
	push(player)
end

local function tickPlayer(player: Player, elapsed: number)
	local session = sessions[player]
	if session == nil then
		return
	end

	local data = dataFor(player)
	if data == nil or not data.alive or not enabled then
		endSession(player)
		return
	end

	if session.noticeLeft > 0 then
		session.noticeLeft -= elapsed
		if session.noticeLeft <= 0 then
			session.notice = nil
			session.noticeLeft = 0
		end
	end

	local now = os.clock()
	local at = characterPosition(player)
	if at == nil or not Till.InReach(session.place, at) then
		-- Walking away is how you leave. There is no "stop robbing" button and there
		-- should not be one: the exit from this activity is the door, which is the same
		-- exit the player is going to want in a hurry a few seconds later.
		endSession(player)
		return
	end

	-- The camera is aimed by the town-wide sweep below, not from here. Asked for again at
	-- this point only as a number, because what the player is judged on has to be read off
	-- the same clock the part on the wall is turning to.
	local _, cameraOn = cameraAt(session.place, now)

	local clerkOn = clerkOnTill(session.place, now)
	aimClerk(session, clerkOn)
	tickLookout(player, session)

	local drawer = drawerFor(session.place, now)

	-- Hands out of the drawer the moment there is nothing in it, rather than leaving the
	-- player holding an empty till while the clerk turns around. Being seen robbing
	-- nothing is the one flavour of unfair this activity can actually produce.
	if drawer.left <= 0 and session.holding then
		session.holding = false
		noticeFor(session, "The drawer is empty.")
	end

	local watched = clerkOn or cameraOn
	if session.holding and watched then
		session.watchedFor += elapsed
		if session.watchedFor >= THEFT.GraceSeconds and not session.spotted then
			session.spotted = true
			local base = if clerkOn then "The clerk looked up." else "The camera is on you."

			-- The lookout's whole job: one roll, spent here and never again this session
			-- (see `lookoutRolled`), against the nerve they had when they were called --
			-- see Config.Gangs.Jobs. It only ever touches this one heat addition. Being
			-- spotted still happens and the notice still says so; the per-second heat
			-- below for staying spotted is untouched, because staying is still your own
			-- risk to run.
			local covered = false
			if session.lookout ~= nil and not session.lookoutRolled then
				session.lookoutRolled = true
				covered = math.random() >= session.lookoutFailChance
			end

			if covered then
				noticeFor(session, `{base} {session.lookoutName} covers you -- no heat, this once.`)
			else
				-- Heat and a sighting together, because they are one event: a shop that
				-- raised the number without reporting where would send the whole response
				-- to wherever the player happened to be seen next, which for a player
				-- standing still is nowhere. Seen rather than Add is also what makes a
				-- second conviction cost more than the first, and this file does not have
				-- to know that.
				BountyService.Seen(player, THEFT.HeatOnSpotted, `Caught at the {session.name}`, at)
				noticeFor(session, base)
			end
		end
	else
		session.watchedFor = 0
		if not session.holding then
			-- Letting go stops the bleeding but does not unsee anything. The heat already
			-- taken stays taken, which is what makes the grace window a decision worth
			-- making rather than a free retry.
			session.spotted = false
		end
	end

	if session.spotted and session.holding then
		-- Re-reported every tick, because they are watching you right now: this is the one
		-- place in the game where the police's belief about where you are is continuously
		-- correct, and it is correct for exactly as long as you keep your hands in the till.
		BountyService.Seen(player, THEFT.HeatPerSecondSpotted * elapsed, `Still at the {session.name}`, at)
	end

	if session.holding and drawer.left > 0 then
		local amount = math.min(THEFT.TakePerSecond * elapsed, drawer.left)
		drawer.left -= amount
		session.taken += amount
		MoneyService.Add(player, amount, `Taken from the {session.name}`)
		-- Paid per dollar rather than per drawer emptied, so a till abandoned halfway still
		-- counts for what came out of it. Deliberately small: money is already its own
		-- reward, and a ladder that paid richly per dollar would make the richest route the
		-- only route worth walking.
		GangService.Credit(player, amount * Config.Gangs.Earn.PerMoneyStolen, `emptied the {session.name}`)
		if drawer.left <= 0 then
			drawer.refillAt = now + THEFT.RefillSeconds
		end
	end

	push(player)
end

-- Clicking the dots. Puts the player at the till; it does not take anything.
function TheftService.Open(player: Player, place: string): (boolean, string?)
	if not enabled then
		return false, "The shop is closed."
	end
	local data = dataFor(player)
	if data == nil or not data.alive then
		return false, "There is nobody to do it."
	end
	local shop = Tills.Get(place)
	if shop == nil then
		return false, "There is nothing worth taking here."
	end
	local at = characterPosition(player)
	if at == nil or not Till.InReach(place, at) then
		return false, "You are not close enough to the counter."
	end

	local existing = sessions[player]
	if existing ~= nil then
		if existing.place == place then
			return true, nil
		end
		-- Two counters at once is not a state this has, and the newer one wins rather than
		-- the older: the player is standing at this one.
		endSession(player)
	end

	local session: Session = {
		place = place,
		name = shop.name,
		holding = false,
		taken = 0,
		watchedFor = 0,
		spotted = false,
		notice = nil,
		noticeLeft = 0,
		clerk = nil,
		spawningClerk = false,
		lookout = nil,
		spawningLookout = false,
		lookoutCrewId = nil,
		lookoutName = nil,
		lookoutFailChance = 0,
		lookoutRolled = false,
	}
	sessions[player] = session
	spawnClerk(player, session)
	push(player)
	return true, nil
end

-- Hands in, hands out. Refused rather than corrected when the player is not at a till,
-- because a hold that quietly did nothing would look exactly like the button being broken.
function TheftService.SetHolding(player: Player, holding: boolean): boolean
	local session = sessions[player]
	if session == nil then
		return false
	end
	if holding then
		local drawer = drawerFor(session.place, os.clock())
		if drawer.left <= 0 then
			noticeFor(session, "The drawer is empty.")
			push(player)
			return false
		end
		local at = characterPosition(player)
		if at == nil or not Till.InReach(session.place, at) then
			return false
		end
	end
	session.holding = holding
	if not holding then
		session.watchedFor = 0
	end
	push(player)
	return true
end

-- Sends one of the player's own crew to watch the door. The till's answer to Bank's
-- CallCrew, and the shape is different for the reason GangService's own note gives: there
-- is no seat here to claim, so what this actually does is set this session's own lookout
-- rather than a room's. Calling again with a different id swaps who is standing there;
-- calling with the one already out is a no-op success rather than a second body.
function TheftService.CallCrew(player: Player, place: string, crewId: string): (boolean, string?)
	local session = sessions[player]
	if session == nil or session.place ~= place then
		return false, "You are not at this till."
	end
	if session.lookout ~= nil and session.lookoutCrewId == crewId then
		return true, nil
	end

	local chosen: GangCrewMember? = nil
	for _, member in GangService.CrewFor(player) do
		if member.id == crewId then
			chosen = member
			break
		end
	end
	if chosen == nil then
		return false, "That's not your crew."
	end

	if session.lookout ~= nil then
		despawnLookout(session)
	end
	spawnLookout(player, session, chosen)
	return true, nil
end

-- Which till a player is currently at, for callers outside this file that need to name
-- it -- the debug command, mainly, same reason BankService.PlaceOf exists.
function TheftService.PlaceOf(player: Player): string?
	local session = sessions[player]
	return if session ~= nil then session.place else nil
end

-- Stands up every shop in the content list, once, and says which ones could not be built.
--
-- Done at startup rather than on arrival so that a missing place point is a line in the
-- log on a developer's first boot rather than a door that does nothing on a player's
-- fiftieth minute. It is also cheap: four shops' worth of parts.
local function buildShops()
	for _, shop in Tills.Shops do
		local place = PlaceService.Find(shop.place)
		if place == nil then
			warn(
				`[AGES] till shop "{shop.place}" has no place point in the built world, so it cannot be robbed. `
					.. `Either the town no longer has that room or the id in content/Tills.luau is wrong.`
			)
			continue
		end
		if Till.Build(shop.place, place.part.CFrame, shop.name) == nil then
			warn(`[AGES] could not stand up a till at "{shop.place}"; its place point has no heading.`)
		end
	end
end

-- Every drawer back to full, right now. The harness only.
--
-- Exists because the refill is five minutes and testing the *take* is the one thing a
-- developer does twenty times in a row: without this the second run of a test plan is
-- spent standing in an empty shop waiting for a timer that was tuned for a player who
-- has a whole town to walk. It does not touch a live session -- a player holding the
-- drawer when this fires simply keeps pulling, which is the honest behaviour for "the
-- till is full again" and needs no special case.
function TheftService.RefillAll()
	for _, drawer in drawers do
		drawer.left = drawer.full
		drawer.refillAt = 0
	end
	for player in sessions do
		push(player)
	end
end

function TheftService.SetEnabled(value: boolean)
	enabled = value
	if not value then
		for player in sessions do
			endSession(player)
		end
	end
end

function TheftService.IsEnabled(): boolean
	return enabled
end

-- For the harness, and phrased as the two questions a broken robbery raises: is the shop
-- built, and where are its two attentions right now.
function TheftService.Describe(player: Player): string
	local session = sessions[player]
	local now = os.clock()
	if session == nil then
		local lines = {}
		for _, shop in Tills.Shops do
			local built = Till.Get(shop.place) ~= nil
			local drawer = drawers[shop.place]
			local clerk = clerkOnTill(shop.place, now)
			local _, camera = cameraAt(shop.place, now)
			table.insert(
				lines,
				string.format(
					"%s: %s, %.0f left, clerk %s, camera %s",
					shop.place,
					if built then "built" else "NOT BUILT",
					if drawer ~= nil then drawer.left else THEFT.TillFloat * shop.richness,
					if clerk then "ON" else "away",
					if camera then "ON" else "away"
				)
			)
		end
		return `not at a till · {if enabled then "on" else "off"}\n` .. table.concat(lines, "\n")
	end

	local drawer = drawerFor(session.place, now)
	local _, camera = cameraAt(session.place, now)
	local lookout = "none"
	if session.lookout ~= nil then
		lookout = string.format(
			"%s (fail %.0f%%, %s)",
			session.lookoutName or "?",
			session.lookoutFailChance * 100,
			if session.lookoutRolled then "spent" else "unspent"
		)
	end
	return string.format(
		"at %s · %.0f left of %.0f · taken %.0f · %s · clerk %s · camera %s · watched %.2fs of %.2f · %s · lookout %s",
		session.place,
		drawer.left,
		drawer.full,
		session.taken,
		if session.holding then "HOLDING" else "hands out",
		if clerkOnTill(session.place, now) then "ON" else "away",
		if camera then "ON" else "away",
		session.watchedFor,
		THEFT.GraceSeconds,
		if session.spotted then "SPOTTED" else "unseen",
		lookout
	)
end

function TheftService:Init()
	RequestTillOpenRemote.OnServerEvent:Connect(function(player: Player, place: any)
		-- The id the dots were built with, and it is checked against the content list
		-- rather than used: a client that sent "bank" would be asking to rob a room that
		-- has no drawer in it, and Open answers that by name.
		if typeof(place) ~= "string" then
			return
		end
		TheftService.Open(player, place)
	end)

	RequestTillHoldRemote.OnServerEvent:Connect(function(player: Player, holding: any)
		-- The one thing the client is allowed to say, and it is a boolean. Anything else
		-- is dropped rather than coerced: a robbery that accepted a string would be a
		-- robbery somebody could hold with a table.
		if typeof(holding) ~= "boolean" then
			return
		end
		TheftService.SetHolding(player, holding)
	end)

	RequestTillCallCrewRemote.OnServerEvent:Connect(function(player: Player, place: any, crewId: any)
		if typeof(place) ~= "string" or typeof(crewId) ~= "string" then
			return
		end
		TheftService.CallCrew(player, place, crewId)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		endSession(player)
		pushed[player] = nil
	end)
end

-- Every camera in town, turned, whether or not anybody is robbing anything.
--
-- Deliberately outside the per-player tick. The camera *is* the warning -- there is none on
-- the HUD and there never will be -- so a player standing in the doorway deciding whether to
-- walk up to the counter has to be able to watch it sweep before they commit to anything.
-- Driven off the sessions instead, it would sit dead still until the moment it stopped
-- mattering, and an unrobbed shop's camera would be frozen at whatever angle the last
-- robber happened to leave it pointing. Four parts at 5 Hz.
local function sweepCameras()
	local now = os.clock()
	for _, shop in Tills.Shops do
		local share, onTill = cameraAt(shop.place, now)
		-- Shops that failed to build are skipped inside AimCamera, so a town missing a
		-- place point costs one table lookup a tick rather than a warning every 200ms.
		Till.AimCamera(shop.place, share, onTill)
	end
end

function TheftService:Start()
	buildShops()

	task.spawn(function()
		while true do
			local elapsed = task.wait(THEFT.TickSeconds)
			sweepCameras()
			for player in sessions do
				local fine, problem = pcall(tickPlayer, player, elapsed)
				if not fine then
					warn(`[AGES] theft tick failed for {player.Name}: {problem}`)
				end
			end
		end
	end)
end

return TheftService
