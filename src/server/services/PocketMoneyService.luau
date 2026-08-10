--!strict
-- Pocket money. From Config.PocketMoney.StartAge to EndAge, every birthday hands
-- the player a year of an allowance quoted by the week.
--
-- The first money in a life that arrives without being earned, and the first thing
-- in the game that pays out without a prompt attached to it. Both of those are the
-- point: an economy where every unit came from answering a question is an economy
-- made entirely of quiz rewards, and pocket money is what makes being a child of a
-- particular age worth something on its own.
--
-- Three steps, and the gap between the first two is the whole feature:
--
--   accrue    A birthday counts what it is worth into pocketMoneyOwed.
--   handover  A parent appears, crosses the room and gives it to the player.
--   settle    Whatever is owed comes out of the ledger and into the balance.
--
-- Accrue is instant and atomic; the handover takes several seconds and can fail in
-- half a dozen ordinary ways -- a room too tight to put an adult in, a player who
-- died on the birthday, a child who runs off mid-walk. Money is therefore counted as
-- owed the moment it is earned and only cleared when it is actually handed across,
-- so every one of those failures comes out as money *delayed* rather than money
-- quietly not paid. A retry loop asks again, and after MaxAttempts the money is
-- simply credited where the player stands.
--
-- That fallback is the ugly version on purpose and it is never removed. An allowance
-- that sometimes fails to arrive is indistinguishable from a broken game, and the
-- one thing this file will not do is let a scene it could not stage cost the player
-- anything. It was built before the scene was, for the same reason.
--
-- Not a cutscene, and that is a rule rather than a shortcut. Nothing in this game
-- takes the room away from the player -- an enacted prompt is a banner precisely so
-- that it cannot -- and thirteen birthdays in a childhood is the worst place in the
-- game to start seizing the camera. They come to you and you keep control the whole
-- time; it reads as a scene because somebody crossed a room to find you.
--
-- Idempotency lives here rather than in MoneyService, which says so explicitly: the
-- balance is a dumb, atomic number and every caller is responsible for not paying
-- twice. pocketMoneyPaidThroughAge is how this one does it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Money = require(ReplicatedStorage:WaitForChild("Money"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)
local MoneyService = require(script.Parent.MoneyService)
local NPCService = require(script.Parent.NPCService)
local Cast = require(script.Parent.Parent.content.Cast)
local People = require(script.Parent.Parent.content.People)
local Ground = require(script.Parent.Parent.world.Ground)
local MoneyPop = require(script.Parent.Parent.world.MoneyPop)

type LifeData = Types.LifeData
type CastMember = Types.CastMember
type Visitor = NPCService.Visitor

local PocketMoneyService = {}

-- How far above the head the figure appears when the money simply lands, and how far
-- above a parent's root when they hand it over -- the second is larger because a
-- root part sits at the hips and the money should leave their hands. Cosmetic, so
-- locals: nobody balances this game by adjusting where a number floats.
local POP_LIFT = 1.4
local HANDOVER_POP_LIFT = 1.6

-- Below this a direction is noise rather than a heading -- a player looking straight
-- down, or a parent asked to face a point they are standing on.
local MIN_DIRECTION = 1e-3

-- How much short of HandoverStuds still counts as having arrived.
--
-- Needed because a humanoid told to walk somewhere stops when it is near enough
-- rather than on the dot, and without any slack the chase would re-aim forever a few
-- inches out and then time out on a handover the player watched happen. Cosmetic in
-- the sense that matters: it changes nothing about how close a parent gets, only
-- about when this file agrees that they got there.
local HANDOVER_SLACK = 0.75

-- Who turns up. Alternating on age rather than chosen at random, so both parents
-- appear across a childhood and so a birthday replayed in the harness produces the
-- same person: a scene that is different every time it is run is a scene that cannot
-- be tested. Even ages are the first of these.
--
-- Cast ids rather than Config entries, because these are content -- the recurring
-- people the house belongs to -- and not numbers anyone tunes.
local PARENTS = { "mom", "dad" }

-- Which of them a given birthday belongs to. One line, but it is read from three places
-- -- who is sent, whose bond the allowance is scaled by, and what the harness prints --
-- and two copies of this that drifted apart would mean a mother handing over money
-- scaled by her husband's opinion of you.
local function parentIdFor(ageYears: number): string
	return PARENTS[(ageYears % 2) + 1]
end

-- What the allowance is worth per week at a given age, in whole units.
--
-- Rounded down at the *weekly* rate rather than at the yearly total, because the
-- weekly figure is the one the player is told and a rate quoted in fractions of a
-- dollar is not a rate anybody has ever been given. Zero outside the window, which
-- is what makes the window a fact about the money rather than a check every caller
-- has to remember to make.
function PocketMoneyService.WeeklyRate(ageYears: number): number
	if ageYears < Config.PocketMoney.StartAge or ageYears > Config.PocketMoney.EndAge then
		return 0
	end
	return math.floor(ageYears * Config.PocketMoney.WeeklyPerYearOfAge)
end

-- What a birthday at this age is worth: the weekly rate, multiplied out.
function PocketMoneyService.GrantFor(ageYears: number): number
	return PocketMoneyService.WeeklyRate(ageYears) * Config.Time.WeeksPerYear
end

-- What the parent who brings this birthday's money thinks of the player, as a
-- multiplier on it.
--
-- Reads the same parent `parentFor` will send, so the two cannot disagree: the year your
-- mother is due is the year her bond is the one that counts. One for anybody the game
-- has no opinion about, and never less than one -- see Config.PocketMoney.BondBonusShare
-- for why a bad relationship does not take money off a child.
local function parentBonus(data: LifeData, ageYears: number): number
	local bond = People.BondIn(data.bonds, parentIdFor(ageYears))
	if bond == nil then
		return 1
	end
	local share = math.clamp(bond, 0, Config.People.MaxBond) / Config.People.MaxBond
	return 1 + share * Config.PocketMoney.BondBonusShare
end

-- Counts every birthday not yet counted into what the player is owed.
--
-- A loop rather than a single add, and it is doing two jobs at once. It is the
-- idempotency guard -- run this twice for one birthday and the second pass finds
-- paidThroughAge already level with the age and adds nothing -- and it is also what
-- makes a multi-year jump pay correctly, which is what "Skip Childhood" is. A life
-- that skips five to nine in one motion is owed five birthdays, not the last one.
--
-- No yields anywhere in it, which is what makes the whole read-modify-write atomic
-- on the same terms MoneyService relies on.
local function accrue(data: LifeData)
	local ageYears = data.ageMonths // Config.Time.MonthsPerYear

	while data.pocketMoneyPaidThroughAge < ageYears do
		data.pocketMoneyPaidThroughAge += 1
		local age = data.pocketMoneyPaidThroughAge
		-- The bonus is read per year inside the loop rather than once outside it, so a
		-- skipped childhood is paid at the bond each of those years actually had. Floored
		-- per birthday for the same reason the weekly rate is: money is whole units.
		data.pocketMoneyOwed += math.floor(PocketMoneyService.GrantFor(age) * parentBonus(data, age))
	end
end

-- Shows the amount, over the hands that gave it when there were hands and over the
-- player's own head when there were not. Feedback only: the money is already in the
-- balance by the time this runs, so a character that is mid-load or mid-removal
-- costs a float and nothing else. That is the correct trade -- being paid silently
-- is a bad birthday, being paid nothing is a broken game.
--
-- The two cases are not cosmetic variants of each other. Money appearing over a
-- parent who just walked across the room is somebody giving you something; the same
-- number over your own head is the game crediting an account. The second is the
-- fallback and is meant to read as the lesser of the two.
local function announce(player: Player, amount: number, at: Vector3?)
	if at ~= nil then
		MoneyPop.Show(at, amount)
		return
	end

	local character = player.Character
	if character == nil then
		return
	end
	local head = character:FindFirstChild("Head") :: BasePart?
	if head == nil then
		return
	end
	MoneyPop.Show(head.Position + Vector3.new(0, POP_LIFT, 0), amount)
end

-- Hands over everything outstanding, right now, wherever the player happens to be.
-- Returns the amount, which is zero when there was nothing owed.
--
-- The balance is credited before the ledger is cleared, and the order is a
-- deliberate choice about which way to be wrong. Neither is actually reachable --
-- nothing between the two lines yields, so they are one atomic step -- but if that
-- ever stops being true, this order pays a player twice and the other loses money
-- they were owed. Only one of those is a betrayal.
--
-- `at` is where the money should be seen to come from, and is the whole difference
-- between the two ways this is reached: a parent passes the point their hands are at
-- and the number floats out of them, while every other caller passes nothing and it
-- floats over the player instead.
--
-- Public because three callers need it: the handover below, the fallback that runs
-- when the handover could not happen, and the Studio harness.
function PocketMoneyService.Settle(player: Player, at: Vector3?): number
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return 0
	end

	local data = Lives.Active(profile.Data)
	local owed = data.pocketMoneyOwed
	if owed <= 0 then
		return 0
	end

	MoneyService.Add(player, owed, "pocket money")
	data.pocketMoneyOwed = 0

	announce(player, owed, at)
	return owed
end

-- Flattened onto the floor plane, so a player looking at their feet or up the stairs
-- cannot tip the arc of bearings over. The same guard, for the same reason, as the
-- one in SceneService.
local function flatten(direction: Vector3): Vector3?
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < MIN_DIRECTION then
		return nil
	end
	return flat.Unit
end

-- Where a parent can appear, or nil if this room cannot hold one.
--
-- The same three probes every placement in this game runs, asked about an adult:
-- there has to be a floor, a body has to fit standing on it, and there has to be a
-- clear line back to the player -- a parent who materializes in the next room and
-- walks into the wall between you is worse than one who never came.
--
-- Measured with Config.NPC.BodyRadius and BodyHeight rather than off the rig,
-- because the rig does not exist yet: building it is a web-backed call, and spawning
-- a person in order to discover there was nowhere to put them is the wrong order.
-- The reach test uses the parent's height too, since the parent is the one walking.
--
-- The full arc first and then the whole arc again drawn in, rather than one sweep
-- that gives up. Measured, not assumed: the far distance alone can stage a parent in
-- 54% of this house and the pair manage 83%, and nearly every room that changed its
-- answer is upstairs, where nothing is fourteen studs across.
local function spawnSpot(character: Model): Vector3?
	local pivot = character:GetPivot()
	local origin = pivot.Position
	local forward = flatten(pivot.LookVector)
	if forward == nil then
		return nil
	end

	local radius = Config.NPC.BodyRadius
	local height = Config.NPC.BodyHeight
	local ignore = Ground.IgnoreList()

	local far = Config.PocketMoney.SpawnStuds
	local bearings = Ground.Bearings(Config.PocketMoney.ArcDegrees, Config.PocketMoney.Bearings)

	for _, out in { far, far * Config.PocketMoney.RetrySpawnScale } do
		for _, angle in bearings do
			local direction = CFrame.Angles(0, math.rad(angle), 0) * forward

			-- Reachability measured from the player, which is what "a parent can get to
			-- you from there" means. This used to cast the other way; see `Ground.SpotAt`
			-- for why the direction is fixed there rather than chosen per caller.
			local ground = Ground.SpotAt(origin + direction * out, radius, height, ignore, origin)
			if ground == nil then
				continue
			end

			return ground
		end
	end

	return nil
end

-- Where a parent should be walking to right now: HandoverStuds out from the player,
-- along the line they are already approaching on.
--
-- Recomputed every tick rather than fixed when the walk began, because the target is
-- a child who can run. Measured from the player outward rather than from the parent
-- inward so the spot stays put when the parent is already close -- aiming at a point
-- a fixed distance ahead of themselves would have them orbiting.
local function handoverSpot(character: Model, from: Vector3): Vector3?
	local origin = character:GetPivot().Position
	local direction = flatten(from - origin)
	if direction == nil then
		return nil
	end
	return origin + direction * Config.PocketMoney.HandoverStuds
end

-- Which parent turns up. Alternating on age rather than random: both of them appear
-- across a childhood, and a birthday replayed in the harness produces the same
-- person, which is the difference between a scene that can be tested and one that
-- cannot.
local function parentFor(ageYears: number): CastMember
	local id = parentIdFor(ageYears)
	local member = Cast.ById[id]
	if member == nil then
		-- The cast is content and could be edited out from under this. Warn and send
		-- somebody rather than let a birthday go unpaid over a missing id.
		warn(`[AGES] pocket money wanted "{id}", who is not in the cast; sending {Cast.Default.name}`)
		return Cast.Default
	end
	return member
end

-- One parent, mid-errand.
type Handover = {
	member: CastMember,
	visitor: Visitor,
	-- Where they came in, which is also where they leave by, so the exit is the
	-- entrance run backwards rather than a second piece of placement that could fail.
	spawnAt: Vector3,
	-- Set by stop(); the chase loop checks it. A handover owns a coroutine and a rig,
	-- and this is the one thing that ends both.
	cancelled: boolean,
}

local inFlight: { [Player]: Handover } = {}

-- Set for the length of the Spawn call, which yields -- building an avatar from a
-- description is a web-backed round trip. Without this, two birthdays landing either
-- side of that yield each look to the other like nobody is coming, and two parents
-- walk out of two walls holding the same money.
local starting: { [Player]: boolean } = {}

-- Handovers that could not be made since the last one that was. In memory rather
-- than on the profile, deliberately: rejoining resets the count, which costs one
-- retry cycle before the fallback pays out and never costs the money itself, and a
-- persisted counter would be a third piece of state to keep in step with the ledger
-- for no gain at all.
local failures: { [Player]: number } = {}

-- Ends a handover immediately and without ceremony -- a death, a player leaving, a
-- server sweep. Everything with a graceful ending goes through finish() instead.
local function stop(player: Player)
	local current = inFlight[player]
	if current == nil then
		return
	end
	inFlight[player] = nil
	current.cancelled = true
	current.visitor.destroy()
end

-- Ends a handover from inside its own coroutine, and only if it is still the one in
-- play: run() reaches its tail across several yields, and clearing by player alone
-- would take down a newer handover that had superseded this one.
--
-- `graceful` is whether they walk back out or simply vanish, and the caller decides
-- it by asking whether anyone is left to watch. Nobody sees a parent leave a room
-- the player has just died in, and making them walk it anyway holds a rig alive
-- through a death for the benefit of an empty screen.
local function finish(player: Player, current: Handover, graceful: boolean)
	if inFlight[player] ~= current then
		return
	end

	if graceful then
		current.visitor.walkTo(current.spawnAt)
		-- The walk yields, and anything at all may have happened across it.
		if inFlight[player] ~= current then
			return
		end
	end

	stop(player)
end

-- Whether there is still a reason for anyone to be crossing the room. Every way a
-- handover can stop being wanted -- the debt paid by the harness, a death, a life
-- ended, a profile gone -- shows up here as one condition, which is the same trick
-- the scene and enactment loops use.
local function stillOwed(player: Player): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil or not Lives.Active(profile.Data).alive then
		return false
	end
	return Lives.Active(profile.Data).pocketMoneyOwed > 0
end

-- Credits the ledger where the player stands, because the good version could not
-- happen often enough that waiting longer is no longer honest.
--
-- Counted rather than immediate, so a single bad moment -- a player in a doorway,
-- a character mid-respawn -- costs a retry rather than the scene. Loud when it
-- finally fires: this is a real failure of the intended feature and the log is the
-- only place anyone would ever find out it had been happening.
local function missed(player: Player)
	if not stillOwed(player) then
		-- Nothing left to hand over; whatever went wrong stopped mattering.
		return
	end

	local count = (failures[player] or 0) + 1
	failures[player] = count
	if count < Config.PocketMoney.MaxAttempts then
		return
	end

	local paid = PocketMoneyService.Settle(player)
	failures[player] = nil
	if paid > 0 then
		warn(
			`[AGES] no parent could reach {player.Name} in {count} attempts; `
				.. `credited {Money.Format(paid)} of pocket money directly`
		)
	end
end

-- The whole life of a handover: cross the room, hand it over, stand there a moment
-- while the number is read, and walk back out.
local function run(player: Player, current: Handover)
	local visitor = current.visitor
	local arrived = false
	local waited = 0

	-- Bounded by the same timeout an ordinary walk gets. A chase has no natural end
	-- -- the player can simply keep running -- and a parent trailing a sprinting
	-- child around the house forever is not a scene, it is a bug with a face on it.
	while waited < Config.NPC.WalkTimeoutSeconds do
		-- Cancelled means stop() has already cleared the table and destroyed the rig,
		-- so there is nothing left here to do or to tidy.
		if current.cancelled then
			return
		end
		-- These two are not that, and are not failures either: the rig went out from
		-- under this errand -- a server sweep, a hot reload -- or the debt did, which
		-- is what the harness paying it out by hand looks like from in here. Drop the
		-- errand, tidy the parent away, and do not count it against the fallback.
		if visitor.gone() or not stillOwed(player) then
			finish(player, current, false)
			return
		end

		local character = player.Character
		if character ~= nil then
			local at = visitor.at()
			local gap = Ground.FlatDistance(at, character:GetPivot().Position)
			if gap <= Config.PocketMoney.HandoverStuds + HANDOVER_SLACK then
				arrived = true
				break
			end
			-- Re-aimed rather than walked: a humanoid holds the last destination it
			-- was given, so following something that moves is this call on a tick.
			local target = handoverSpot(character, at)
			if target ~= nil then
				visitor.moveTo(target)
			end
		end

		waited += task.wait(Config.PocketMoney.TickSeconds)
	end

	if current.cancelled then
		return
	end
	if visitor.gone() then
		finish(player, current, false)
		return
	end

	if not arrived then
		finish(player, current, false)
		missed(player)
		return
	end

	-- Stopped explicitly, because moveTo has no "and stop here": a parent who simply
	-- stopped being re-aimed would keep walking into the player.
	visitor.halt()
	visitor.greet()

	-- The money comes out of their hands rather than off the top of the player's
	-- head, which is the entire reason anyone walked anywhere.
	PocketMoneyService.Settle(player, visitor.at() + Vector3.new(0, HANDOVER_POP_LIFT, 0))
	failures[player] = nil

	-- Still standing there while the number is readable. Vanishing on the instant of
	-- payment would undo the handover as surely as never having walked in.
	task.wait(Config.PocketMoney.LingerSeconds)

	local profile = DataService.GetProfile(player)
	local watched = profile ~= nil and Lives.Active(profile.Data).alive and player.Character ~= nil
	finish(player, current, watched)
end

-- Puts a parent in the room and starts them walking. Yields, and reports whether
-- anyone is actually on the way -- false is an ordinary answer meaning "not here,
-- not now", and the caller counts it toward the fallback.
local function begin(player: Player): boolean
	if inFlight[player] ~= nil or starting[player] then
		return false
	end

	local profile = DataService.GetProfile(player)
	if profile == nil or not Lives.Active(profile.Data).alive then
		return false
	end

	local character = player.Character
	if character == nil then
		return false
	end

	local spot = spawnSpot(character)
	if spot == nil then
		return false
	end

	local ageYears = Lives.Active(profile.Data).ageMonths // Config.Time.MonthsPerYear
	local member = parentFor(ageYears)

	-- Lifted to hip height, because an R15 model's pivot is its root part and putting
	-- that on the floor buries the parent to the waist. Erring high instead costs a
	-- short drop the humanoid absorbs on the first frame.
	local lift = Vector3.new(0, Config.NPC.BodyHeight / 2, 0)
	local from = spot + lift
	-- Facing the player from the first frame. A parent who appears with their back
	-- turned and then spins is somebody who was placed there, not somebody who came.
	local facing = flatten(character:GetPivot().Position - spot)
	local pose = if facing ~= nil then CFrame.lookAt(from, from + facing) else CFrame.new(from)

	starting[player] = true
	local visitor = NPCService.Spawn(player, member, pose)
	starting[player] = nil

	if visitor == nil then
		return false
	end
	local arriving = visitor :: Visitor

	-- Spawn yielded, and a life can end inside a yield. A parent built for a birthday
	-- that is no longer owed is a rig standing in an empty house.
	if not stillOwed(player) then
		arriving.destroy()
		return false
	end

	local current: Handover = {
		member = member,
		visitor = arriving,
		spawnAt = spot,
		cancelled = false,
	}
	inFlight[player] = current
	task.spawn(run, player, current)

	return true
end

-- Someone is owed money: send a parent, or count the failure to.
--
-- A parent already crossing the room is neither, and returns without counting
-- anything: the second birthday's money is added to the ledger the first one is
-- already on its way to settle, and gets handed over in the same motion.
local function dispatch(player: Player)
	if not stillOwed(player) then
		return
	end
	if inFlight[player] ~= nil or starting[player] then
		return
	end
	if begin(player) then
		return
	end
	missed(player)
end

-- Studio harness: send a parent now, for a debt that already exists. Returns whether
-- one set off, so the harness can say why not.
function PocketMoneyService.Send(player: Player): boolean
	if not stillOwed(player) then
		return false
	end
	return begin(player)
end

-- Called by LifeService on every birthday. Safe on a birthday that pays nothing,
-- which is most of them: below StartAge and above EndAge accrue adds zero and
-- dispatch finds an empty ledger and does nothing at all.
--
-- The accrual is synchronous and the handover is not, and that split is the whole
-- design in one line. Counting what is owed happens now, inside the same atomic
-- stretch as the birthday itself; the person carrying it across the room takes
-- several seconds and must not be standing between a birthday and the death rolls
-- that follow it.
function PocketMoneyService.OnAgeUp(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil or not Lives.Active(profile.Data).alive then
		return
	end

	accrue(Lives.Active(profile.Data))
	task.spawn(dispatch, player)
end

-- Called by LifeService when a life ends, alongside the rest of the teardown.
--
-- The two fields are zeroed even though the life they belong to is about to be left behind
-- untouched, and that is on purpose: a dead life is still readable -- the lobby draws it on a
-- card, and a later screen may well summarise it -- and "the world owes this dead person
-- $40" is not a fact worth keeping. The stopping below is the part that matters right now.
function PocketMoneyService.ResetForNewLife(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local data = Lives.Active(profile.Data)
	data.pocketMoneyOwed = 0
	data.pocketMoneyPaidThroughAge = 0

	-- And anyone still carrying this life's money across the room. Abruptly, because the
	-- person they were bringing it to has just died -- a parent finishing the walk and
	-- politely letting themselves out is not a nicer ending, it is a stranger in the house.
	stop(player)
	failures[player] = nil
end

-- Brings a freshly loaded profile's paid-through age up to the age it is actually
-- at, without paying for the difference.
--
-- This is the migration, and it only has one job: a save written before pocket money
-- existed reconciles to a paid-through age of zero, and its owner may be twelve. Left
-- alone, their next birthday would walk the accrual loop from one to thirteen and
-- hand them the entire childhood they already lived through in a lump.
--
-- A clamp rather than a rewrite, so it can only ever move forward. The cost is that
-- it also forfeits a birthday in one genuinely broken case -- a server that died
-- between advancing the age and running the grant -- and that is the trade being
-- made on purpose: at most one missed birthday, against back-paying thirteen.
local function catchUpOnLoad(player: Player)
	local profile = DataService.WaitForProfile(player)
	if profile == nil then
		return
	end

	local data = Lives.Active(profile.Data)
	local ageYears = data.ageMonths // Config.Time.MonthsPerYear
	if data.pocketMoneyPaidThroughAge < ageYears then
		data.pocketMoneyPaidThroughAge = ageYears
	end
end

-- Studio harness only: puts a debt in the ledger without a birthday to justify it.
--
-- It exists because the only honest way to reach the state a handover starts from is
-- to have a birthday, and a birthday is a poor test rig: it happens once, it moves
-- the age out from under you, and it cannot be repeated without dying first. This
-- puts the ledger in that state directly, so "/pocket owe 500" then "/pocket send"
-- is the whole scene on demand, as many times as it takes to watch it properly.
--
-- Kept out of the accrual path so a debt conjured by a tester can never be mistaken
-- for one the game granted -- paidThroughAge does not move, so nothing here can
-- silently pay for a birthday that has not happened.
function PocketMoneyService.Owe(player: Player, amount: number): boolean
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return false
	end
	local owed = math.floor(amount)
	if owed <= 0 then
		return false
	end
	Lives.Active(profile.Data).pocketMoneyOwed += owed
	return true
end

-- Studio harness: the rate, the ledger, how far the grant has been counted, and
-- whether anybody is currently crossing a room with it.
--
-- The last of those is the reason this exists in its current form. "Owed $312" is
-- the same line whether a parent is three steps away or whether the room could not
-- hold one and the money is quietly waiting on a retry, and those are completely
-- different things to go and fix.
function PocketMoneyService.Describe(player: Player): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end

	local data = Lives.Active(profile.Data)
	local ageYears = data.ageMonths // Config.Time.MonthsPerYear
	local weekly = PocketMoneyService.WeeklyRate(ageYears)
	local bonus = parentBonus(data, ageYears)
	local rate = if weekly > 0
		then `{Money.Format(weekly)}/week -> `
			.. `{Money.Format(math.floor(PocketMoneyService.GrantFor(ageYears) * bonus))} a birthday `
			.. `(x{string.format("%.2f", bonus)} from {parentIdFor(ageYears)})`
		else `nothing at {ageYears} (pays {Config.PocketMoney.StartAge}-{Config.PocketMoney.EndAge})`

	local current = inFlight[player]
	local misses = failures[player] or 0
	local status: string
	if current ~= nil then
		local character = player.Character
		local away = if character ~= nil
			then string.format("%.1f studs away", Ground.FlatDistance(current.visitor.at(), character:GetPivot().Position))
			else "nobody to reach"
		status = `{current.member.name} on the way, {away}`
	elseif starting[player] then
		status = "a parent is being built"
	elseif misses > 0 then
		status = `nobody on the way, {misses}/{Config.PocketMoney.MaxAttempts} missed`
	else
		status = "nobody on the way"
	end

	return `age {ageYears} | {rate} | owed {Money.Format(data.pocketMoneyOwed)} `
		.. `| counted through age {data.pocketMoneyPaidThroughAge} | {status}`
end

function PocketMoneyService:Init() end

function PocketMoneyService:Start()
	MoneyPop.ClearAll()

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(catchUpOnLoad, player)
	end)
	-- And whoever is already here, which in Studio is always the person testing:
	-- services start after the local player has joined, so PlayerAdded alone would
	-- never run the migration in the one place it is being written to be checked.
	for _, player in Players:GetPlayers() do
		task.spawn(catchUpOnLoad, player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		stop(player)
		-- Both keyed by Player, so leaving them behind holds a reference to somebody
		-- who has gone. Small, and exactly the kind of small that accumulates over a
		-- server's lifetime.
		starting[player] = nil
		failures[player] = nil
	end)

	-- The one thing that makes a delayed handover a delay rather than a loss.
	--
	-- Everything above only tries at the moment of a birthday, and the moment of a
	-- birthday is a bad time to need a room: the player may be in a doorway, mid
	-- respawn, or halfway up the stairs. This comes back and asks again, and keeps
	-- asking until either a parent gets through or the fallback pays out -- so
	-- "nowhere to stand right now" costs seconds instead of an allowance.
	--
	-- Cheap to leave running: it only does anything for a player whose ledger is not
	-- empty, which is the few seconds after a birthday and otherwise never.
	task.spawn(function()
		while true do
			task.wait(Config.PocketMoney.RetrySeconds)
			for _, player in Players:GetPlayers() do
				-- Spawned per player rather than awaited in turn, because begin()
				-- yields on a web call and one player's slow avatar build must not
				-- hold up everybody else's.
				task.spawn(dispatch, player)
			end
		end
	end)
end

return PocketMoneyService
