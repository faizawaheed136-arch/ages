--!strict
-- The bank. One verb -- hold -- and a room built so that holding it in two different
-- places means two opposite things.
--
-- **This is the till's question inverted, on purpose.** A shop till asks you not to be
-- seen: you read a clerk and a camera and you take money in the gap between them, and
-- being spotted is the failure. A bank takes being seen as given. The alarm goes the
-- instant you touch the door, before a penny has moved, and everything after that is one
-- question asked over and over: how much longer are you willing to stay? Nothing in this
-- file is a stealth check. It is a clock the player is choosing to run down.
--
-- Three things are happening at once and the third one is the floor plan:
--
--   the vault    pays out while you hold it, and only while you hold it.
--   the alarm    rings, and every second of ringing is heat *and a live fix on where you
--                actually are* -- not a last-known guess. Officers converge on you rather
--                than on a corner you left.
--   the room     puts the panel that silences the alarm forty-eight studs from the money.
--
-- So silencing the alarm costs the money you are not taking while you walk, and taking the
-- money costs the alarm you are not silencing. That is the whole activity, and it is made
-- of geometry rather than of a cooldown -- see the activity law on escalating by changing
-- the space. It is also why a second player matters and is never required: two people
-- never have to run, one person always does.
--
-- **The most useful thing the alarm does is freeze.** The live fix stops the moment it is
-- silenced, which means the police's picture of you sticks at wherever you were standing
-- when you silenced it -- the panel, by the entrance. Silence the alarm and you have
-- bought quiet at the vault by sending the search to your own way out. Nobody wrote that
-- rule; it falls out of the fix being continuous and then stopping, which is the kind of
-- consequence this system is supposed to produce.
--
-- Nothing is broadcast. There is no server message, no map ping and no announcement that a
-- bank is being robbed, which is the one thing The Wild West got right by removing it: a
-- global notification turns every robbery into the same event and hands the whole server a
-- free waypoint. What tells the town is heat, which is already built and already visible
-- as officers and as a crowd that recognises you.
--
-- What this file does not do: decide where the vault is (Vault, and content/Vaults), decide
-- what heat buys (BountyService), or put officers in the street (PoliceService). It opens a
-- door, rings a bell, and tells the bounty where somebody is standing.

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

local Ground = require(script.Parent.Parent.world.Ground)
local Public = require(script.Parent.Parent.content.Public)
local Vault = require(script.Parent.Parent.world.Vault)
local Vaults = require(script.Parent.Parent.content.Vaults)

type LifeData = Types.LifeData
type BankState = Types.BankState
type Visitor = NPCService.Visitor

local BankService = {}

local BANK = Config.Crime.Bank

local BankUpdatedRemote = Remotes.Get("BankUpdated")
local RequestBankOpenRemote = Remotes.Get("RequestBankOpen")
local RequestBankHoldRemote = Remotes.Get("RequestBankHold")

-- One bank, as a shared fact rather than a per-player one.
--
-- This is the single most important structural decision in the file and it is the whole of
-- what makes two players in one bank interesting. The vault a partner empties is empty for
-- you. The alarm a partner silences is silent for you. Neither of them has to know the
-- other is there and neither of them is handed a special co-op mode: they are simply both
-- reading the same room, which is what a shared world means and what the till already does
-- with its drawer.
type Room = {
	place: string,
	name: string,
	left: number,
	full: number,
	-- When it is worth robbing again, on the same clock everything else here uses. A moment
	-- rather than a countdown, so a bank nobody is standing in costs nothing.
	refillAt: number,

	-- Whether anybody has committed this visit. Cleared when the last person leaves the
	-- building, which is the only way out of it: once tripped, this room is against you
	-- until it is empty of robbers.
	tripped: boolean,
	-- Who opened it. Held for one reason only: the gang ladder pays standing for heat you
	-- took that was not yours, so the person whose robbery it is has to be excluded from
	-- that award -- their heat is theirs. Cleared with `tripped` when the room settles.
	--
	-- A Player rather than a name, and therefore a strong reference held only for as long
	-- as the room stays tripped. A player who leaves mid-robbery is dropped from the game
	-- but not from here until the last person walks out, which is at most one robbery's
	-- worth of a table entry and is not worth a weak table to avoid.
	trippedBy: Player?,
	ringing: boolean,
	-- When a silenced alarm arms itself again. 0 while ringing or untripped.
	rearmAt: number,
	ringingSince: number,

	guard: Visitor?,
	-- Set while a guard rig is being built, which yields. Without it a player who walks in,
	-- out and back in inside two seconds gets two guards on one floor.
	spawningGuard: boolean,
	-- Which patrol spot he is walking to. An index into the room's spot list, walked in a
	-- loop, so a bank with four spots patrols four rather than needing new code.
	leg: number,
	legUntil: number,
	-- When he stops staring at whoever he just caught and goes back to walking.
	noticeUntil: number,
	-- Whether his last look found somebody. Only for the panel to draw; the alarm it
	-- caused has already been rung by the time this is read.
	onSomebody: boolean,
}

-- One player, inside one bank.
type Session = {
	place: string,
	-- Whether the client says their hands are on something. Never trusted on its own: every
	-- tick re-checks which control they are actually within reach of, and being at neither
	-- takes their hands off regardless of what the client last said.
	holding: boolean,
	taken: number,
	-- How long they have held the alarm panel. Counted up rather than down because it
	-- resets to zero the instant they let go or step away, which is much harder to get
	-- wrong in this direction -- the same argument the till's watch window makes.
	silencingFor: number,
	notice: string?,
	noticeLeft: number,
}

local rooms: { [string]: Room } = {}
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

-- The shared state for one bank, created on first use and then ticked for the rest of the
-- session. Refilling deliberately does not happen here: it is in tickRoom, so a vault comes
-- back on its own clock and its door closes with it, rather than staying open until the next
-- person happens to ask -- which for a bank could be twenty minutes of the town wearing a
-- sign saying this has already been done.
local function roomFor(place: string): Room?
	local existing = rooms[place]
	if existing ~= nil then
		return existing
	end

	local bank = Vaults.Get(place)
	if bank == nil then
		return nil
	end
	local full = BANK.VaultFloat * bank.richness
	local made: Room = {
		place = place,
		name = bank.name,
		left = full,
		full = full,
		refillAt = 0,
		tripped = false,
		trippedBy = nil,
		ringing = false,
		rearmAt = 0,
		ringingSince = 0,
		guard = nil,
		spawningGuard = false,
		leg = 1,
		legUntil = 0,
		noticeUntil = 0,
		onSomebody = false,
	}
	rooms[place] = made
	return made
end

local function noticeFor(session: Session, text: string)
	session.notice = text
	session.noticeLeft = 4
end

-- Everybody currently inside one bank. Walked rather than indexed because there is one
-- bank and at most a handful of people in it -- an index keyed by place would be a second
-- copy of the session table to keep honest for no measurable gain.
local function othersIn(place: string): { Player }
	local found: { Player } = {}
	for player, session in sessions do
		if session.place == place then
			table.insert(found, player)
		end
	end
	return found
end

-- Which of the room's two controls the player is standing at.
local function controlAt(place: string, at: Vector3): "vault" | "alarm" | "between"
	if Vault.AtVault(place, at) then
		return "vault"
	end
	if Vault.AtAlarm(place, at) then
		return "alarm"
	end
	return "between"
end

local function stateFor(player: Player): BankState?
	local session = sessions[player]
	if session == nil then
		return nil
	end
	local now = os.clock()
	local room = roomFor(session.place)
	if room == nil then
		return nil
	end
	local at = characterPosition(player)

	local alarm: "quiet" | "ringing" | "silenced"
	if not room.tripped then
		alarm = "quiet"
	elseif room.ringing then
		alarm = "ringing"
	else
		alarm = "silenced"
	end

	local guard: ("away" | "near" | "onYou")? = nil
	local body = room.guard
	if body ~= nil and not body.gone() then
		if room.onSomebody then
			guard = "onYou"
		elseif at ~= nil and Ground.FlatDistance(body.at(), at) <= BANK.GuardSeeStuds then
			guard = "near"
		else
			guard = "away"
		end
	end

	return {
		place = room.name,
		vaultLeft = room.left,
		vaultFull = room.full,
		taken = session.taken,
		at = if at ~= nil then controlAt(session.place, at) else "between",
		holding = session.holding,
		silencing = math.clamp(session.silencingFor / BANK.SilenceSeconds, 0, 1),
		alarm = alarm,
		rearmIn = if alarm == "silenced" then math.max(room.rearmAt - now, 0) else 0,
		ringingFor = if alarm == "ringing" then now - room.ringingSince else 0,
		guard = guard,
		notice = session.notice,
	}
end

local function push(player: Player)
	local state = stateFor(player)
	local digest: string
	if state == nil then
		digest = "none"
	else
		-- Money to the whole unit and the two clocks to a tenth of a second, because both
		-- drain continuously and a panel redrawn every tick for a digit nobody can read at
		-- that precision would be a packet every 200ms of every robbery.
		digest = `{state.place}/{math.floor(state.vaultLeft)}/{math.floor(state.taken)}/`
			.. `{state.at}/{tostring(state.holding)}/{math.floor(state.silencing * 20)}/`
			.. `{state.alarm}/{math.floor(state.rearmIn * 10)}/{math.floor(state.ringingFor * 10)}/`
			.. `{tostring(state.guard)}/{tostring(state.notice)}`
	end

	if pushed[player] == digest then
		return
	end
	pushed[player] = digest
	BankUpdatedRemote:FireClient(player, state)
end

local function pushRoom(place: string)
	for _, player in othersIn(place) do
		push(player)
	end
end

-- The alarm goes. Idempotent, because three different things ring it -- the first hold on
-- the vault, the re-arm timer running out, and the guard looking up -- and two of them can
-- land on the same tick.
local function ring(room: Room, now: number)
	if room.ringing then
		return
	end
	room.ringing = true
	room.ringingSince = now
	room.rearmAt = 0
end

-- Back to nothing happening in this building. Only ever reached by the room emptying of
-- people: there is no "cancel", because the exit from this activity is the front door,
-- which is the same exit the player is going to want thirty seconds later anyway.
local function settle(room: Room)
	room.tripped = false
	room.trippedBy = nil
	room.ringing = false
	room.rearmAt = 0
	room.ringingSince = 0
	room.onSomebody = false
end

local function despawnGuard(room: Room)
	local guard = room.guard
	if guard ~= nil then
		room.guard = nil
		if not guard.gone() then
			guard.destroy()
		end
	end
end

-- Somebody on the floor, built once the first player is in the room.
--
-- Spawned per *room* rather than per player, unlike the shop clerk, and that is the point:
-- two robbers in one bank are watched by one man and have to solve him together. A guard
-- each would be two private games in one building.
--
-- Lazy for the reason the clerk is -- staffing a room nobody is in is a rig built for
-- nobody -- and the cost of that is a player who walks past an open door seeing an empty
-- lobby. The honest fix for that is the ambient population work rather than a permanent
-- rig here. What matters for the activity is that he exists *before* anything is
-- committed: clicking the vault door opens the room and trips nothing, so the seconds
-- spent watching him walk are free, and they are the only read this activity gives you.
local function spawnGuard(player: Player, room: Room)
	if room.guard ~= nil or room.spawningGuard then
		return
	end
	local built = Vault.Get(room.place)
	if built == nil or #built.patrol < 2 then
		-- Nowhere standable to walk. The bank runs on its alarm alone, which is easier and
		-- is allowed to be: a robbery that refused to start because the floor was tight
		-- would be a door that does nothing for reasons nobody can see.
		return
	end

	room.spawningGuard = true
	task.spawn(function()
		local member = Public.Someone()
		local start = built.patrol[1]
		local visitor = NPCService.Spawn(player, member, CFrame.new(start, built.vault), BANK.GuardAgeYears)
		room.spawningGuard = false
		-- Everything below the spawn is re-checked, because Spawn yields on a web call and
		-- the room may have emptied, or a second player's tick may have built one already.
		if visitor == nil then
			return
		end
		if room.guard ~= nil or #othersIn(room.place) == 0 then
			visitor.destroy()
			return
		end
		-- His pace is derived from the patrol he was given rather than set as a number, so
		-- a bank whose spots are further apart does not silently get a faster guard: the
		-- loop takes GuardPatrolSeconds in every building, which is what the config note
		-- about not being a multiple of RearmSeconds is actually promising.
		local walked = 0
		for index, spot in built.patrol do
			local nextSpot = built.patrol[if index < #built.patrol then index + 1 else 1]
			walked += Ground.FlatDistance(spot, nextSpot)
		end
		visitor.setSpeed(math.max(walked / BANK.GuardPatrolSeconds, 1))
		room.guard = visitor
		room.leg = 1
		room.legUntil = 0
	end)
end

-- Walks the guard, and looks up.
--
-- His one action is re-arming the alarm, and he only ever takes it while the room is
-- already tripped: before that he is a man at work and a player standing at a vault is a
-- customer. That is what makes the read before committing worth anything -- commit while
-- he is at the door end and your first silence runs its full twelve seconds, commit while
-- he is at the vault end and it does not.
local function tickGuard(room: Room, now: number)
	local guard = room.guard
	if guard == nil then
		return
	end
	if guard.gone() then
		room.guard = nil
		return
	end
	local built = Vault.Get(room.place)
	if built == nil or #built.patrol < 2 then
		return
	end

	-- Looking first, because a man who has just caught somebody should stop where he is
	-- rather than take one more step and then react.
	if room.tripped and now >= room.noticeUntil then
		local ignore = Ground.IgnoreList()
		local from = guard.at()
		local caught: Vector3? = nil
		for _, player in othersIn(room.place) do
			local at = characterPosition(player)
			if at == nil then
				continue
			end
			-- Cast from him to them rather than the other way around, which is not
			-- symmetric: the origin is what the engine forgives for being inside a body,
			-- and the destination is what the ignore list has to cover. Same note as
			-- WitnessService, and the same trap.
			if Ground.FlatDistance(from, at) <= BANK.GuardSeeStuds and Ground.Reachable(from, at, 0, ignore) then
				caught = at
				break
			end
		end

		if caught ~= nil then
			room.onSomebody = true
			room.noticeUntil = now + BANK.GuardNoticeSeconds
			guard.halt()
			guard.face(caught)
			ring(room, now)
			return
		end
		room.onSomebody = false
	end

	if now < room.noticeUntil then
		return
	end

	-- Back to walking. `face(nil)` first because a body being held at an angle cannot also
	-- be steering itself -- see Visitor.face, which is emphatic about this.
	if room.onSomebody then
		room.onSomebody = false
		guard.face(nil)
		room.legUntil = 0
	end

	if now >= room.legUntil then
		room.leg = if room.leg < #built.patrol then room.leg + 1 else 1
		room.legUntil = now + BANK.GuardPatrolSeconds / #built.patrol
	end
	-- Re-aimed every tick rather than walked once, because a humanoid that was knocked off
	-- its destination by a player standing in the doorway would otherwise stop there and
	-- the patrol would end without anything reporting that it had.
	guard.moveTo(built.patrol[room.leg])
end

-- The room itself, once per tick, whether or not anybody is holding anything. Split from
-- the per-player tick because everything in it is shared: two robbers must not each be
-- able to advance one alarm clock.
local function tickRoom(room: Room, now: number, elapsed: number)
	-- Refilled and drawn before anything else, and for every room whether or not anybody is
	-- inside. The open door is how a bank tells the street it has already been done, so one
	-- that stayed open through its own refill -- because nobody had walked in to ask --
	-- would be the town wearing a sign that had stopped being true.
	if room.left <= 0 and now >= room.refillAt then
		room.left = room.full
	end
	Vault.ShowDoor(room.place, if room.full > 0 then 1 - room.left / room.full else 0)

	local here = othersIn(room.place)
	if #here == 0 then
		if room.tripped then
			settle(room)
		end
		despawnGuard(room)
		Vault.ShowAlarm(room.place, "quiet")
		return
	end

	if room.tripped and not room.ringing and now >= room.rearmAt then
		ring(room, now)
	end

	tickGuard(room, now)

	if room.ringing then
		-- The live fix, and this is the part that actually hurts. Re-reported every tick
		-- for every person in the building, because right now the police know exactly where
		-- each of them is -- which makes this and the till's "hands in the drawer" the only
		-- two moments in the game where their belief is continuously correct. Seen rather
		-- than Add is also what makes a second conviction cost more than the first, and
		-- this file does not have to know that.
		for _, player in here do
			local at = characterPosition(player)
			if at ~= nil then
				BountyService.Seen(player, BANK.HeatPerSecondRinging * elapsed, `The {room.name} alarm`, at)
			end
			-- Everybody in the room except whoever opened the vault.
			--
			-- This is the line that makes a second person worth having. The heat above is
			-- charged to the whole building rather than to the person holding the money, so
			-- standing on the panel while a gang-mate empties the vault means eating heat
			-- that was never yours -- and that is exactly the work a gang should be paying
			-- for. Excluding the tripper is what stops it being farmable: a lone robber
			-- would otherwise be paid twice for the same alarm, once in money and once in
			-- standing, for doing nothing but standing next to their own crime.
			if player ~= room.trippedBy then
				GangService.Credit(
					player,
					Config.Gangs.Earn.PerSecondSharedHeat * elapsed,
					`took heat at the {room.name}`
				)
			end
		end
	end

	Vault.ShowAlarm(room.place, if not room.tripped then "quiet" elseif room.ringing then "ringing" else "silenced")
end

local function endSession(player: Player)
	local session = sessions[player]
	if session == nil then
		return
	end
	sessions[player] = nil
	push(player)

	local room = rooms[session.place]
	local remaining = othersIn(session.place)

	-- Walking out on somebody.
	--
	-- Charged only when all three are true at once: the alarm is live, this player is not
	-- the one who opened it, and there is still somebody in there. That last clause is what
	-- keeps it honest -- leaving a room you are alone in is not a betrayal, it is escaping,
	-- which is a thing this game pays for elsewhere and must not punish here.
	--
	-- Read before `settle` below, because settle clears `trippedBy` and would make every
	-- departure look like the tripper's own.
	if room ~= nil and room.ringing and player ~= room.trippedBy and #remaining > 0 then
		GangService.OnBailed(player)
	end

	-- After the session is gone, so a room emptied by the last person leaving settles on
	-- this call rather than a fifth of a second later. Walking out of a bank should stop
	-- the alarm you can hear through the door.
	if room ~= nil and #remaining == 0 then
		settle(room)
		despawnGuard(room)
		Vault.ShowAlarm(session.place, "quiet")
	end
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
	if at == nil or not Vault.InRoom(session.place, at) then
		-- Leaving the building is how you leave. Not leaving the vault -- walking away from
		-- the vault is half the activity, and a session that ended at the drawer's reach
		-- would drop the player out of their own robbery the moment they went to silence
		-- the alarm.
		endSession(player)
		return
	end

	local room = roomFor(session.place)
	if room == nil then
		endSession(player)
		return
	end

	local control = controlAt(session.place, at)

	-- Hands off the moment there is nothing to put them on. Being caught holding an empty
	-- vault is the one flavour of unfair this activity can produce on its own.
	if session.holding and control == "between" then
		session.holding = false
		session.silencingFor = 0
	end
	if session.holding and control == "vault" and room.left <= 0 then
		session.holding = false
		noticeFor(session, "The vault is empty.")
	end

	if not session.holding or control ~= "alarm" then
		session.silencingFor = 0
	end

	if session.holding and control == "vault" and room.left > 0 then
		if not room.tripped then
			-- The commitment, and it is the first hold rather than the click that opened
			-- the panel. Straight past the first tier: two officers are dispatched by the
			-- act of starting, before a penny has moved, which is the promise this room
			-- makes up front and the reason none of what follows is a stealth check.
			room.tripped = true
			room.trippedBy = player
			ring(room, now)
			BountyService.Seen(player, BANK.HeatOnTrip, `Opened the {room.name} vault`, at)
			-- The set piece, paid flat and once. A vault is the event this whole tree
			-- builds toward and it should read as one on the ladder too, rather than
			-- arriving as a slightly faster trickle of the per-dollar rate below.
			GangService.Credit(player, Config.Gangs.Earn.VaultOpened, `opened the {room.name} vault`)
			noticeFor(session, "The alarm is going.")
			pushRoom(session.place)
		end

		local amount = math.min(BANK.TakePerSecond * elapsed, room.left)
		room.left -= amount
		session.taken += amount
		MoneyService.Add(player, amount, `Taken from the {room.name}`)
		-- The same per-dollar rate the till pays, on top of the flat award for opening the
		-- door. A vault is worth more than a drawer here because it *holds* more, not
		-- because it is scored differently -- one rate across every theft in the game means
		-- a player can reason about what a job is worth without being told.
		GangService.Credit(player, amount * Config.Gangs.Earn.PerMoneyStolen, `emptied the {room.name}`)
		if room.left <= 0 then
			room.refillAt = now + BANK.RefillSeconds
		end
	end

	if session.holding and control == "alarm" then
		if not room.tripped then
			-- Nothing to silence. Refused with a sentence rather than left to count against
			-- a clock that is not running, which would look exactly like the panel being
			-- broken.
			session.holding = false
			noticeFor(session, "Nothing to silence yet.")
		else
			session.silencingFor += elapsed
			if session.silencingFor >= BANK.SilenceSeconds then
				session.silencingFor = 0
				session.holding = false
				room.ringing = false
				room.rearmAt = now + BANK.RearmSeconds
				-- Deliberately not a sighting, and deliberately not a clearing of one
				-- either. The live fix simply stops, which leaves the police believing the
				-- last thing they were told -- that somebody is at this panel, by the front
				-- door. Silencing the alarm buys quiet at the vault by pointing the search
				-- at your own way out, and nobody had to write that down.
				noticeFor(session, "Quiet. It will arm itself again.")
				pushRoom(session.place)
			end
		end
	end

	push(player)
end

-- Clicking the dots on the vault door. Puts the player in the room's activity; it does not
-- open anything and does not trip anything.
function BankService.Open(player: Player, place: string): (boolean, string?)
	if not enabled then
		return false, "The bank is closed."
	end
	local data = dataFor(player)
	if data == nil or not data.alive then
		return false, "There is nobody to do it."
	end
	local bank = Vaults.Get(place)
	if bank == nil then
		return false, "There is no vault here."
	end
	local at = characterPosition(player)
	if at == nil or not Vault.InRoom(place, at) then
		return false, "You are not inside the bank."
	end
	local room = roomFor(place)
	if room == nil then
		return false, "There is no vault here."
	end

	local existing = sessions[player]
	if existing ~= nil then
		if existing.place == place then
			return true, nil
		end
		-- Two banks at once is not a state this has, and the newer one wins: the player is
		-- standing in this one. Unreachable with one bank in town and written anyway,
		-- because the day a second is added is not the day to discover this.
		endSession(player)
	end

	sessions[player] = {
		place = place,
		holding = false,
		taken = 0,
		silencingFor = 0,
		notice = nil,
		noticeLeft = 0,
	}
	spawnGuard(player, room)
	push(player)
	return true, nil
end

-- Hands on, hands off. Which control it means is decided here from where the player is
-- standing, never from anything the client said -- a client that could name the control
-- could silence the alarm from the vault, which would delete the activity.
function BankService.SetHolding(player: Player, holding: boolean): boolean
	local session = sessions[player]
	if session == nil then
		return false
	end
	if holding then
		local at = characterPosition(player)
		if at == nil or controlAt(session.place, at) == "between" then
			-- Refused rather than quietly ignored, because a hold that did nothing would
			-- look exactly like the button being broken from thirty studs away.
			return false
		end
	end
	session.holding = holding
	if not holding then
		session.silencingFor = 0
	end
	push(player)
	return true
end

-- Stands up every bank in the content list, once, and says which ones could not be built.
--
-- At startup rather than on arrival, so a missing place point is a line in the log on a
-- developer's first boot rather than a door that does nothing on a player's fiftieth
-- minute. It is also cheap: one room's worth of parts.
local function buildBanks()
	for _, bank in Vaults.Banks do
		local place = PlaceService.Find(bank.place)
		if place == nil then
			warn(
				`[AGES] bank "{bank.place}" has no place point in the built world, so it cannot be robbed. `
					.. `Either the town no longer has that room or the id in content/Vaults.luau is wrong.`
			)
			continue
		end
		-- The plan is copied field by field rather than the content row being passed whole.
		-- A Bank happens to carry everything a Plan needs and three things besides -- an id,
		-- a name and a richness -- and handing the world builder a row it could read the
		-- money off would be an invitation for it to start caring about what a vault is
		-- worth. Vault.luau builds a room out of numbers and is not told which room.
		local built = Vault.Build(bank.place, place.part.CFrame, bank.name, {
			roomStuds = bank.roomStuds,
			vault = bank.vault,
			alarm = bank.alarm,
			patrol = bank.patrol,
		})
		if built == nil then
			warn(`[AGES] could not stand up a vault at "{bank.place}"; its place point has no heading.`)
			continue
		end
		if #built.patrol < 2 then
			-- Not fatal and worth saying out loud: the bank still works, it is simply a
			-- clean twelve-second metronome with nothing interfering with it, which is a
			-- much easier room than the one that was designed.
			warn(
				`[AGES] bank "{bank.place}" has nowhere standable for a guard to patrol, so it will run `
					.. `on its alarm alone. Check the patrol offsets in content/Vaults.luau against the room.`
			)
		end
	end
end

-- Every vault back to full and every alarm quiet, right now. The harness only.
--
-- Exists because the refill is fifteen minutes and testing the take is the one thing a
-- developer does twenty times in a row. Settling the alarm as well as the money, because
-- the two halves of a test are "can I open it" and "can I shut it up", and being handed a
-- full vault behind a ringing bell would only ever let you retry one of them.
function BankService.ResetAll()
	for place, room in rooms do
		room.left = room.full
		room.refillAt = 0
		settle(room)
		Vault.ShowAlarm(place, "quiet")
		Vault.ShowDoor(place, 0)
	end
	for player in sessions do
		push(player)
	end
end

function BankService.SetEnabled(value: boolean)
	enabled = value
	if not value then
		for player in sessions do
			endSession(player)
		end
	end
end

-- For the harness, and phrased as the questions a broken bank raises: is the room built,
-- what is the alarm doing, and where is the guard.
function BankService.Describe(player: Player): string
	local now = os.clock()
	local session = sessions[player]

	local lines = { if enabled then "bank on" else "bank OFF" }
	for _, bank in Vaults.Banks do
		local built = Vault.Get(bank.place)
		local room = rooms[bank.place]
		if built == nil then
			table.insert(lines, `{bank.place}: NOT BUILT`)
			continue
		end
		local guard = "none"
		if room ~= nil and room.guard ~= nil then
			guard = if room.onSomebody then "ON SOMEBODY" else `walking to spot {room.leg}`
		end
		table.insert(
			lines,
			string.format(
				"%s: built, %d patrol spot(s), %.0f/%.0f left, alarm %s%s, %d inside, guard %s",
				bank.place,
				#built.patrol,
				if room ~= nil then room.left else BANK.VaultFloat * bank.richness,
				if room ~= nil then room.full else BANK.VaultFloat * bank.richness,
				if room == nil or not room.tripped then "quiet" elseif room.ringing then "RINGING" else "silenced",
				if room ~= nil and room.tripped and not room.ringing
					then string.format(" (%.1fs)", math.max(room.rearmAt - now, 0))
					else "",
				#othersIn(bank.place),
				guard
			)
		)
	end

	if session == nil then
		table.insert(lines, "not in a bank")
		return table.concat(lines, "\n")
	end

	local at = characterPosition(player)
	table.insert(
		lines,
		string.format(
			"in %s · at %s · %s · taken %.0f · silencing %.2f/%.2f",
			session.place,
			if at ~= nil then controlAt(session.place, at) else "nowhere",
			if session.holding then "HOLDING" else "hands off",
			session.taken,
			session.silencingFor,
			BANK.SilenceSeconds
		)
	)
	return table.concat(lines, "\n")
end

function BankService:Init()
	RequestBankOpenRemote.OnServerEvent:Connect(function(player: Player, place: any)
		-- The id the dots were built with, checked against the content list rather than
		-- used: a client that sent "pharmacy" would be asking to open a vault in a room
		-- that has none, and Open answers that by name.
		if typeof(place) ~= "string" then
			return
		end
		BankService.Open(player, place)
	end)

	RequestBankHoldRemote.OnServerEvent:Connect(function(player: Player, holding: any)
		-- The one thing the client is allowed to say, and it is a boolean. Anything else is
		-- dropped rather than coerced.
		if typeof(holding) ~= "boolean" then
			return
		end
		BankService.SetHolding(player, holding)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		endSession(player)
		pushed[player] = nil
	end)
end

function BankService:Start()
	buildBanks()

	task.spawn(function()
		while true do
			local elapsed = task.wait(BANK.TickSeconds)
			if enabled then
				local now = os.clock()
				-- Rooms before players, so the alarm a player is about to be judged against
				-- has already been armed or rung on this tick rather than on the last one.
				for _, room in rooms do
					local fine, problem = pcall(tickRoom, room, now, elapsed)
					if not fine then
						warn(`[AGES] bank room tick failed for {room.place}: {problem}`)
					end
				end
				for player in sessions do
					local fine, problem = pcall(tickPlayer, player, elapsed)
					if not fine then
						warn(`[AGES] bank tick failed for {player.Name}: {problem}`)
					end
				end
			end
		end
	end)
end

return BankService
