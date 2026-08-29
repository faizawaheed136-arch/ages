--!strict
-- Studio-only test harness. Reaching an edge case in the aging system takes
-- real minutes of play, so this exposes chat commands that jump straight to
-- one. It bails out unless RunService:IsStudio(), so a live server never
-- registers the listener and there is nothing for a real player to reach.
--
-- Commands accept either prefix, e.g. "/ageup 5" or "!ageup 5". The "!" form
-- is a fallback for setups where the chat system swallows unknown "/" commands.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Money = require(ReplicatedStorage:WaitForChild("Money"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))
local Interact = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Interact"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local DataService = require(script.Parent.DataService)
local StatService = require(script.Parent.StatService)
local MoneyService = require(script.Parent.MoneyService)
local PocketMoneyService = require(script.Parent.PocketMoneyService)
local LifeService = require(script.Parent.LifeService)
local EventService = require(script.Parent.EventService)
local BodyService = require(script.Parent.BodyService)
local DeliveryService = require(script.Parent.DeliveryService)
local PlaceService = require(script.Parent.PlaceService)
local WorkService = require(script.Parent.WorkService)
local SchoolService = require(script.Parent.SchoolService)
local School = require(script.Parent.Parent.world.School)
local PEService = require(script.Parent.PEService)
local GymService = require(script.Parent.GymService)
local StadiumCrowdService = require(script.Parent.StadiumCrowdService)
local StadiumEntranceService = require(script.Parent.StadiumEntranceService)
local ScienceService = require(script.Parent.ScienceService)
local GeographyService = require(script.Parent.GeographyService)
local ArtService = require(script.Parent.ArtService)
local BullyService = require(script.Parent.BullyService)
local ReadingService = require(script.Parent.ReadingService)
local MusicService = require(script.Parent.MusicService)
local BountyService = require(script.Parent.BountyService)
local PoliceService = require(script.Parent.PoliceService)
local TheftService = require(script.Parent.TheftService)
local BankService = require(script.Parent.BankService)
local GangService = require(script.Parent.GangService)
local SkillService = require(script.Parent.SkillService)
local SettingsService = require(script.Parent.SettingsService)
local CodeService = require(script.Parent.CodeService)
local FightService = require(script.Parent.FightService)
local WitnessService = require(script.Parent.WitnessService)
local DisguiseService = require(script.Parent.DisguiseService)
local PeopleService = require(script.Parent.PeopleService)
local ChildhoodService = require(script.Parent.ChildhoodService)
local EnactService = require(script.Parent.EnactService)
local PropService = require(script.Parent.PropService)
local SceneService = require(script.Parent.SceneService)
local SetupService = require(script.Parent.SetupService)
local ReturnService = require(script.Parent.ReturnService)
local BillService = require(script.Parent.BillService)
local MilestoneService = require(script.Parent.MilestoneService)
local GossipService = require(script.Parent.GossipService)
local HouseService = require(script.Parent.HouseService)
local VehicleService = require(script.Parent.VehicleService)
local Vehicles = require(script.Parent.Parent.content.Vehicles)
local LifeEvents = require(script.Parent.Parent.content.LifeEvents)
local Flags = require(script.Parent.Parent.content.Flags)
local Hideouts = require(script.Parent.Parent.content.Hideouts)
local Vaults = require(script.Parent.Parent.content.Vaults)
local Bullies = require(script.Parent.Parent.content.Bullies)
local Gangs = require(script.Parent.Parent.content.Gangs)

type StatName = Types.StatName
type LifeData = Types.LifeData

-- Sorted, because an unordered dump of a keyed table comes out in a different order every
-- time it is read and the command is mostly used to compare two readings of it.
local function describeFlags(data: LifeData): string
	local held: { string } = {}
	for flagId, age in data.flags do
		table.insert(held, `{flagId} (age {age})`)
	end
	if #held == 0 then
		return "none yet"
	end
	table.sort(held)
	return table.concat(held, ", ")
end

local PREFIXES = { "/", "!" }
local MAX_AGE_UPS_PER_COMMAND = 200

-- A flat pad dropped in front of the player, sized and placed to read as
-- something on the floor you walk onto rather than an obstacle you bump into.
local ANCHOR_DISTANCE = 8
local ANCHOR_SIZE = Vector3.new(4, 0.2, 4)

-- How many interactables /dots prints before it stops. A harness listing, not a tunable:
-- the answer is always in the nearest few, and a busy street would otherwise fill the
-- output window with things behind the player.
local DOTS_LISTED = 8

local VALID_STATS: { [string]: boolean } = {
	health = true,
	happiness = true,
	smarts = true,
	looks = true,
}

local Commands: { [string]: (Player, { string }) -> string } = {}

-- Drives the real age-up path rather than writing ageMonths directly, so a
-- forced jump still runs yearly decay, stage transitions and mortality rolls.
-- If a roll kills the player mid-loop the remaining iterations no-op.
Commands.ageup = function(player: Player, args: { string }): string
	local requested = tonumber(args[1]) or 1
	local count = math.clamp(math.floor(requested), 1, MAX_AGE_UPS_PER_COMMAND)
	for _ = 1, count do
		LifeService.AgeUp(player, "Manual")
	end
	return `aged up {count}x -> age {LifeService.GetAgeYears(player)}`
end

Commands.age = function(player: Player, args: { string }): string
	local target = tonumber(args[1])
	if target == nil then
		return "usage: /age <years>"
	end
	local current = LifeService.GetAgeYears(player)
	if current == nil then
		return "no profile loaded yet"
	end
	if target <= current then
		return `already age {current}; /age only moves forward (use /die to restart)`
	end
	return Commands.ageup(player, { tostring(target - current) })
end

Commands.die = function(player: Player, _args: { string }): string
	LifeService.Die(player)
	return "forced death"
end

local VerdictService = require(script.Parent.VerdictService)

Commands.verdict = function(player: Player, args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end
	local ribbonId = args[1]
	if ribbonId ~= nil then
		-- Force a specific ribbon for testing.
		local data = Lives.Active(profile.Data)
		data.verdict = {
			id = ribbonId,
			title = ribbonId,
			description = "forced for debug",
			moments = {},
			nearMisses = nil,
		} :: Types.Ribbon
		return `forced {ribbonId}`
	end
	local ribbon = VerdictService.Compute(player)
	if ribbon == nil then
		return "no ribbon (under MinAge or not enough data)"
	end
	return `ribbon: {ribbon.title} — {ribbon.description}`
end

Commands.moments = function(player: Player, _args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end
	local data = Lives.Active(profile.Data)
	local moments = LifeService.Moments(data, { maxCount = nil })
	if #moments == 0 then
		return "no moments in this life"
	end
	local lines: { string } = {}
	for _, m in moments do
		table.insert(lines, `  age {m.ageMonths // Config.Time.MonthsPerYear}: {m.line}`)
	end
	return table.concat(lines, "\n")
end

Commands.reel = function(player: Player, _args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end
	local data = Lives.Active(profile.Data)
	local moments = LifeService.Moments(data, {
		sinceMonths = data.lastChapterBreakMonths,
		maxCount = nil,
	})
	if #moments == 0 then
		return "nothing happened since the last chapter break"
	end
	local lines: { string } = {}
	for _, m in moments do
		table.insert(lines, `  age {m.ageMonths // Config.Time.MonthsPerYear}: {m.line}`)
	end
	return table.concat(lines, "\n")
end

Commands.stat = function(player: Player, args: { string }): string
	local name = string.lower(args[1] or "")
	local value = tonumber(args[2])
	if not VALID_STATS[name] or value == nil then
		return "usage: /stat <health|happiness|smarts|looks> <0-100>"
	end
	StatService.SetStat(player, name :: StatName, value)
	return `{name} -> {value}`
end

-- Fast-forwards the automatic age-up timer so the safety net can be tested
-- without editing Config.AutoAgeUpGameHours and restarting.
--
-- Named `/idle` and not `/bank`, which is what it was called until the vault arrived and
-- took the name. Two entries in this table with the same key is not an error in Lua -- the
-- second assignment simply wins at require time -- so the symptom was a command that had
-- worked for months answering with a bank's usage line and nothing anywhere saying why.
-- Both were even listed in HELP_TEXT. Worth remembering before adding the next one: this
-- table is the whole namespace, and it fails silently.
Commands.idle = function(player: Player, args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end
	local seconds = tonumber(args[1])
	if seconds == nil then
		return "usage: /idle <seconds>"
	end
	Lives.Active(profile.Data).secondsSinceAgeUp += seconds
	return `idled {seconds}s -> {string.format("%.1f", Lives.Active(profile.Data).secondsSinceAgeUp)}s toward auto age-up`
end

-- Forces a specific event on screen without waiting for its age band to come
-- round, which is the only practical way to proof-read a new content entry.
Commands.event = function(player: Player, args: { string }): string
	local eventId = args[1]
	if eventId == nil then
		return "usage: /event <id> (see /events)"
	end
	if LifeEvents.ById[eventId] == nil then
		return `no event with id "{eventId}"`
	end
	if not EventService.ForceOffer(player, eventId) then
		-- The id exists, so the only two ways left to be refused are a profile that has
		-- not loaded and a life that has not been chosen. Named, because "nothing
		-- happened" while sitting behind the setup menu is otherwise a five-minute hunt.
		return `could not offer "{eventId}" — no profile loaded, or still in setup (see /setup)`
	end
	return `offered "{eventId}"`
end

-- Lists what is eligible right now, which is usually the question being asked
-- when an expected event doesn't fire.
Commands.events = function(player: Player, _args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end

	local ageYears = Lives.Active(profile.Data).ageMonths // Config.Time.MonthsPerYear
	local eligible: { string } = {}
	local seenCount = 0

	for _, event in LifeEvents.All do
		if Lives.Active(profile.Data).seenEventIds[event.id] then
			seenCount += 1
		elseif ageYears >= event.minAge and ageYears <= event.maxAge then
			table.insert(eligible, event.id)
		end
	end

	if #eligible == 0 then
		return `age {ageYears}: nothing eligible ({seenCount} seen, {#LifeEvents.All} total)`
	end
	return `age {ageYears}: {table.concat(eligible, ", ")} ({seenCount} seen)`
end

-- Drops a tagged pad in front of the player, which is the only way to exercise
-- world-triggered events until the house exists in Studio. It is a real anchor,
-- not a simulation of one: same tag, same attribute, same code path, so testing
-- here proves the thing the authored world will rely on.
Commands.anchor = function(player: Player, args: { string }): string
	local eventId = args[1]
	if eventId == nil then
		return "usage: /anchor <id> (see /events)"
	end
	if LifeEvents.ById[eventId] == nil then
		return `no event with id "{eventId}"`
	end

	local character = player.Character
	if character == nil then
		return "no character spawned"
	end

	local pivot = character:GetPivot()
	local pad = Instance.new("Part")
	pad.Name = `AgesDebugAnchor_{eventId}`
	pad.Size = ANCHOR_SIZE
	pad.Anchored = true
	pad.CanCollide = false
	pad.Material = Enum.Material.Neon
	pad.Color = Color3.fromRGB(245, 205, 120)
	pad.Transparency = 0.35
	-- Dropped to the character's feet so the pad sits on the floor the player is
	-- standing on, whatever height a toddler's pivot happens to be at.
	pad.Position = (pivot * CFrame.new(0, 0, -ANCHOR_DISTANCE)).Position
		- Vector3.new(0, character:GetExtentsSize().Y / 2, 0)

	pad:SetAttribute(Config.World.InteractEventAttribute, eventId)
	pad.Parent = workspace
	-- Tagged last: the anchor is only live once it is in the world and carrying
	-- an id, and tagging first would briefly register an anchor that offers
	-- nothing and warns about it.
	CollectionService:AddTag(pad, Config.World.InteractTag)

	return `anchored "{eventId}" {ANCHOR_DISTANCE} studs ahead — walk onto it`
end

-- Stages an ambient delivery immediately, skipping the countdown and the
-- per-year cap but nothing else. The real staging path, so what appears here is
-- what appears when the scheduler does it -- including the walk-in, the head
-- tracking and the expiry clock.
Commands.deliver = function(player: Player, args: { string }): string
	local eventId = args[1]
	if eventId == nil then
		return "usage: /deliver <id> (any Letter/PhoneCall/NPCApproach event; see /events)"
	end
	if LifeEvents.ById[eventId] == nil then
		return `no event with id "{eventId}"`
	end
	if not DeliveryService.ForceStage(player, eventId) then
		return `could not stage "{eventId}" — not a world delivery, or the house has no point for it`
	end
	return `staged "{eventId}" — go find it`
end

-- The one command for "why has nothing arrived", which is the question this
-- system will generate more than any other. Prints both halves of the two-phase
-- state, so a profile that thinks something is out there while the room is empty
-- is visible at a glance rather than inferred.
Commands.deliveries = function(player: Player, _args: { string }): string
	return DeliveryService.Describe(player)
end

-- Silences the ambient scheduler so an unrelated test isn't interrupted by mail.
Commands.ambient = function(_player: Player, args: { string }): string
	local mode = string.lower(args[1] or "")
	if mode ~= "on" and mode ~= "off" then
		return `usage: /ambient <on|off> (currently {if DeliveryService.IsEnabled() then "on" else "off"})`
	end
	DeliveryService.SetEnabled(mode == "on")
	return `ambient deliveries {mode}`
end

-- The three questions enactment generates, on one command.
--
-- "/enact <id>" forces an event into the room whatever its content says, which is
-- the only practical way to proof-read a new one: the markers have to be walked
-- between to know whether the fan is too wide, the labels too long, or the spot
-- the player happens to be standing in too tight.
--
-- "/enact off" is the other half, and it matters as much. It forces every event
-- back onto a panel, which both tests the fallback path deliberately instead of
-- waiting out SecondsToChoose, and gets enactment out of the way while something
-- unrelated is being tested.
Commands.enact = function(player: Player, args: { string }): string
	local arg = string.lower(args[1] or "")
	if arg == "" then
		return EnactService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		EnactService.SetEnabled(arg == "on")
		return `enactment {arg}`
	end

	-- Not lowercased: event ids are case-sensitive, and only the switch words
	-- above are matched loosely.
	local eventId = args[1] :: string
	if LifeEvents.ById[eventId] == nil then
		return `no event with id "{eventId}" (see /events, or /enact <on|off>)`
	end
	if not EventService.ForceOffer(player, eventId, "Enacted") then
		return "no profile loaded, or still in setup (see /setup)"
	end
	-- Deliberately reports what actually happened rather than what was asked for.
	-- An event with nothing to hang dots on answers with a panel instead, and that is
	-- the single most useful thing this command can tell you.
	return `offered "{eventId}" — {EnactService.Describe(player)}`
end

-- The same three questions again, for the events whose answers are objects.
--
-- "/props <id>" forces one into the room whatever its content says, and this is the
-- command that matters most of the three, because a Handled event is the one kind
-- that cannot be proof-read by reading it. Whether two props are far enough apart to
-- tell which one you are reaching for, whether a rug ends up somewhere a cookie then
-- cannot be staged, and whether an instruction is legible from where the player
-- actually stands are all things only walking around finds.
--
-- The bare form reports what each answer is still waiting for -- how far the rug has
-- moved of the distance it needs, how long the player has stood still of the time it
-- takes, which thing is in their hands -- because none of that is visible from the
-- outside until the instant it resolves, and "nothing happened" is otherwise the
-- only symptom of every one of these going wrong.
--
-- "/props off" hands every open set back to its panel, which tests the fallback
-- deliberately instead of waiting out SecondsToChoose, and "/props clear" is for the
-- test that left a rug in the middle of the floor.
Commands.props = function(player: Player, args: { string }): string
	local arg = string.lower(args[1] or "")
	if arg == "" then
		return PropService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		PropService.SetEnabled(arg == "on")
		return `props {arg}`
	end

	if arg == "clear" then
		PropService.ClearAll()
		return "cleared every staged set on the server"
	end

	-- Not lowercased: event ids are case-sensitive, and only the switch words above
	-- are matched loosely.
	local eventId = args[1] :: string
	if LifeEvents.ById[eventId] == nil then
		return `no event with id "{eventId}" (see /events, or /props <on|off|clear>)`
	end
	if not EventService.ForceOffer(player, eventId, "Handled") then
		return "no profile loaded, or still in setup (see /setup)"
	end
	-- Reports what actually happened rather than what was asked for, exactly as
	-- /enact does. An event whose choices carry no acts, or whose props would not fit
	-- where the player is standing, becomes a panel -- and that is the one thing this
	-- command most needs to be able to tell you apart from a bug.
	return `offered "{eventId}" — {PropService.Describe(player)}`
end

-- What is standing in the room, and the switch to stop anything standing in it.
--
-- Deliberately not a way to *summon* a subject. A scene lives exactly as long as
-- the prompt it belongs to -- that is the one condition it polls, and it is what
-- guarantees an animal cannot outlive the question it is there to illustrate --
-- so a dog conjured with no pending event would clear itself within a tick. The
-- way to put one in the room is to open the event that is about it:
-- "/enact childhood_big_dog", or "/event childhood_big_dog" for the panel.
--
-- "/scene off" is the half that earns its keep day to day: it takes subjects out
-- of the picture while something unrelated is being tested, the same way
-- "/enact off" does for the dots.
Commands.scene = function(player: Player, args: { string }): string
	local arg = string.lower(args[1] or "")
	if arg == "" then
		return SceneService.Describe(player)
	end
	if arg ~= "on" and arg ~= "off" then
		return `usage: /scene [on|off] — {SceneService.Describe(player)}`
	end
	SceneService.SetEnabled(arg == "on")
	return `scenes {arg}`
end

-- Reads or moves a balance. Three forms, and the split is not cosmetic: a bare
-- number *sets*, which is how you get to the state a test needs, while "+n" and
-- "-n" go through Add and Spend, which are the functions the game itself uses. A
-- harness that could only set would never exercise the clamp, the overdraft refusal
-- or the ledger's sense of direction.
--
-- The two tests this exists for: "/money 0" then open a panel carrying a priced
-- choice (the row greys, its figure turns red, and clicking it does nothing), and
-- "/money 500" then the same row (lit, clickable, and the price comes off the
-- balance).
Commands.money = function(player: Player, args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end

	local arg = args[1]
	if arg == nil then
		return `balance {Money.Format(Lives.Active(profile.Data).money)}`
	end

	local amount = tonumber(arg)
	if amount == nil then
		return `usage: /money [<amount>|+<amount>|-<amount>] (currently {Money.Format(Lives.Active(profile.Data).money)})`
	end

	-- The sign is read off the text rather than off the number, because a set to
	-- zero and a relative move of zero are the same number and not the same command.
	local sign = string.sub(arg, 1, 1)
	if sign == "+" then
		MoneyService.Add(player, amount, "debug /money")
	elseif sign == "-" then
		-- tonumber already carried the minus, and Spend takes a magnitude.
		if not MoneyService.Spend(player, -amount, "debug /money") then
			return `refused: cannot spend {Money.Format(-amount)} of {Money.Format(Lives.Active(profile.Data).money)}`
		end
	else
		MoneyService.Set(player, amount)
	end

	return `balance {Money.Format(Lives.Active(profile.Data).money)}`
end

-- Reads or drives the pocket money ledger, and sends the person who carries it.
--
-- The real path is "/ageup and watch", but a birthday is a bad rig to test on: it
-- happens once, it moves the age underneath you, and if the parent fails to arrive
-- you have to wait a whole retry cycle to see what happens next. "/pocket owe 500"
-- puts a debt in the ledger with no birthday behind it, and the other two forms are
-- the two ways it can come out -- "send" for the good version, "pay" for the
-- fallback that runs when the good version could not happen.
--
-- Four tests this exists for:
--   /age 4 then /ageup          nothing is paid; five is the first birthday.
--   /pocket owe 500, /pocket send   a parent walks over, the money leaves their
--                               hands, they stand a moment and go.
--   /pocket owe 500, /pocket pay    the same five hundred off the player's own
--                               head, landing exactly once.
--   /pocket send in a cupboard  nothing sets off, and /pocket says why.
Commands.pocket = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = args[1]
	if arg == nil then
		return PocketMoneyService.Describe(player)
	end

	if arg == "pay" then
		local paid = PocketMoneyService.Settle(player)
		if paid <= 0 then
			return `nothing owed — {PocketMoneyService.Describe(player)}`
		end
		return `handed over {Money.Format(paid)} — {PocketMoneyService.Describe(player)}`
	end

	if arg == "send" then
		-- Yields on the avatar build, which is fine here: the command's reply is
		-- meant to be the answer to "did anyone actually set off".
		if not PocketMoneyService.Send(player) then
			return `nobody set off — {PocketMoneyService.Describe(player)}`
		end
		return `on the way — {PocketMoneyService.Describe(player)}`
	end

	if arg == "owe" then
		local amount = tonumber(args[2])
		if amount == nil or not PocketMoneyService.Owe(player, amount) then
			return `usage: /pocket owe <amount> — {PocketMoneyService.Describe(player)}`
		end
		return `owed — {PocketMoneyService.Describe(player)}`
	end

	return `usage: /pocket [send|pay|owe <amount>] — {PocketMoneyService.Describe(player)}`
end

-- Every named spot in the world, read out of the world itself. The one command
-- for "is the street actually built" and "did that point survive the last edit",
-- and the answer comes from the tags rather than from a list here, so a point
-- that was renamed in Studio shows up renamed.
Commands.places = function(_player: Player, _args: { string }): string
	local places = PlaceService.All()
	if #places == 0 then
		return `nothing tagged "{Config.World.PlacePointTag}" is in the world`
	end

	local lines: { string } = {}
	for _, place in places do
		table.insert(lines, `{place.id} ({place.label})`)
	end
	return `{#places} places: {table.concat(lines, ", ")}`
end

-- Every zone WorldEventService is currently willing to roll an ambient event
-- near. Exists because the zone set used to be silently empty forever -- nothing
-- in the built world was ever hand-tagged `AgesZone`, so the whole NPCApproach
-- pipeline behind it never had a reason to run -- and that failure had no
-- symptom a player would ever report; the world just stayed quiet. `/zones`
-- reading zero back is now the one-line proof that the place points fed it
-- correctly, without playing a whole life to find out by accident.
Commands.zones = function(_player: Player, _args: { string }): string
	local tagged = CollectionService:GetTagged(Config.World.ZoneTag)
	if #tagged == 0 then
		return `nothing tagged "{Config.World.ZoneTag}" is in the world -- ambient NPC approaches cannot fire`
	end
	local lines: { string } = {}
	for _, instance in tagged do
		local zoneId = instance:GetAttribute(Config.World.ZoneAttribute)
		table.insert(lines, `{instance.Name}={if typeof(zoneId) == "string" then zoneId else "?"}`)
	end
	return `{#tagged} zones: {table.concat(lines, ", ")}`
end

-- Stands the player at a named place. Walking there is the game; this is for
-- getting back to the far end of the street after a /die, and for checking that
-- a point is somewhere a body actually fits before a job is ever clocked in at it.
Commands.go = function(player: Player, args: { string }): string
	local id = args[1]
	if id == nil then
		return `usage: /go <place> (see /places)`
	end
	-- Not lowercased: place ids come from world_plan.py and are matched exactly,
	-- the same way event ids are.
	if not PlaceService.Send(player, id) then
		local place = PlaceService.Find(id)
		if place == nil then
			return `no place called "{id}" (see /places)`
		end
		return `found "{id}" but there is no character to move`
	end
	return `stood you at "{id}"`
end

-- Everything about working, on one command.
--
-- The real path is "/age 16, walk to the store, stand near the till", and that is
-- the thing to test — but it is a four-minute walk before anything can go wrong,
-- and most of what can go wrong is at the far end of it.
--
-- The tests this exists for:
--   /job                      what job, what hours, when the moment is due.
--   /age 16 then /job start   clock on from where you stand; the wage should tick
--                             every 30 seconds and the balance move with it.
--   /job moment               the shift's event now, instead of at hour 2-6.
--   /job hours 39             one game hour left in the year; the next shift
--                             should pay once and clock you straight back off.
--   /job start then walk off  the radius should end it, and /job should say so.
--   /job standing <id> <n>    set what a job makes of you. The only practical way
--                             to stand in front of the office door and watch it
--                             open: the honest route is several shifts downstairs.
--                             Set <n> to -1 and the thin-ice warning should land;
--                             to -8 the "one more bad shift" warning; to -10 a shift
--                             end should sack you at clock-off.
--   /age 18 then walk upstairs with a shop record below the requirement, the HUD
--                             should say what it wants instead of doing nothing.
--   /job quit                 give the job back, so the hiring pad can be tested
--                             more than once in a life. The record stays behind at
--                             the shop, which is the point of it.
--   /age 16 with no job       a line should appear leading to the store, and go out
--                             the moment you step onto the mark and take the work.
--   /job task                 the next task now, instead of after the gap. A mark
--                             should appear somewhere near the counter with a row on
--                             the HUD counting down over it. The only way to check
--                             where the search puts marks without working a shift.
--                             It clears the board first, so the shift is left holding
--                             exactly one thing however many it had a moment ago.
--   /job task twice           the whole reason the shift is worth working. Two marks
--                             lit at once, two rows on the HUD, two clocks running
--                             independently, and the second mark placed well away from
--                             the first -- if the two discs ever land within a stride
--                             of each other the player clears both standing still and
--                             the job is an idle payout pad again. That spacing is the
--                             one thing in this system that cannot be checked by
--                             reading the code, because it is a search over whatever
--                             floor the store happens to have.
--                             The second slot does not open until hour
--                             Config.Work.Tasks.SecondSlotFromHour, so in the opening
--                             minute of a shift this correctly refuses to hold two.
--   /job skip 3               wind the shift's clock to the end of hour 3, which is how
--                             the two-slot half of the shift is reached without standing
--                             in a shop for ninety seconds first. The hours are really
--                             worked on the way past, so the money and the shift moment
--                             behave as if you had waited. Forward only.
--   two live tasks, walk off  let one run out while finishing the other. The finished
--                             one should clear its row and mark on the spot; the missed
--                             one should hold its row saying "Missed" for a few seconds
--                             while the shift keeps issuing into the slot it freed. A
--                             miss that stalls the next task means MissLingerSeconds is
--                             being read as the refill gap, which is the bug the two
--                             clocks exist to prevent.
--   /job task till            that task by name, which is how the customer is tested
--                             without rolling for it. Somebody should walk in, stand
--                             across the mark facing you, and follow you with their
--                             head while the clock runs. Then "delivery" for the same
--                             thing on the second mark of a two-mark task.
--   /job task rush            the queue, and the one task with a shape of its own
--                             rather than a sentence of its own. Three people should
--                             arrive one after another and stand in a line pointing
--                             away from the counter, with only the front one saying
--                             anything. It is fetch, hand over, fetch, hand over, with
--                             the counter mark staying put and the fetch mark moving
--                             somewhere new every round. Each time you reach the counter
--                             the
--                             front one thanks you and goes, the line steps up, the
--                             speech moves to the new front, and the HUD row counts
--                             people down to "(last one)". "post" is the same task in
--                             the office.
--                             Worth watching for specifically: the line should hold
--                             its shape. Three rigs slowly shoving each other apart
--                             means the visitor collision group did not register, which
--                             NPCService will have warned about at start.
--   /job fail                 run the clock out on the oldest task still running, one
--                             per call. The mark should go, the row should say
--                             "Missed — out of time" for MissLingerSeconds, anybody
--                             waiting should leave without a word, and the shift's tally
--                             in /job should be one worse. Twice in a row is how both
--                             slots are failed; once with two live is how the "lost one
--                             while winning the other" case is looked at.
--   /job stall                marks the station as having asked for things and found
--                             nowhere to put them, which is the one shift ending that
--                             a correctly built station can never produce. Within a
--                             tick the shift should end by itself, the notice should
--                             say the station has nothing to do and you are not being
--                             paid to stand in it, and /job afterwards should show the
--                             money and the standing both unmoved. That last part is
--                             the whole point: this is the ending that used to pay a
--                             full year's salary for standing still.
--   /job task then /job       "shift worth +2" while you are finishing them and "+0"
--                             once you have missed most of them, which is the whole
--                             of what the tasks are for: the shift's tasks decide
--                             what the shift did to your record.
Commands.job = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return WorkService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		WorkService.SetEnabled(arg == "on")
		return `clocking on {arg} — {WorkService.Describe(player)}`
	end

	if arg == "start" then
		-- Reports the refusal rather than only failing. Since the ladder exists, the
		-- interesting failures are the ones with a reason attached -- too young, or not
		-- yet thought well enough of somewhere else -- and a bare "could not" would
		-- hide the exact thing this command is now most useful for testing.
		local started, refusal = WorkService.ForceStart(player)
		if not started then
			return `could not clock on: {refusal or "no reason given"} — {WorkService.Describe(player)}`
		end
		return `clocked on — {WorkService.Describe(player)}`
	end

	if arg == "task" then
		-- An optional task id, because four of the ten tasks are the interesting ones
		-- -- the two-mark fetches and the ones with somebody waiting at the end of them
		-- -- and rolling for them is a slow way to check a change to either.
		local taskId = args[2]
		if not WorkService.ForceTask(player, taskId) then
			-- Three very different failures with one message, on purpose: not on shift,
			-- no room near the station for a mark, or a task id this job does not have.
			-- Describe says which of the first two -- it prints whether a shift is
			-- running -- and the third is answered by the id being echoed back.
			local named = if taskId ~= nil then ` "{taskId}"` else ""
			return `no task{named} issued — not on shift, no such task for this job, or nowhere `
				.. `near the station to stand — {WorkService.Describe(player)}`
		end
		return `task issued — {WorkService.Describe(player)}`
	end

	if arg == "fail" then
		if not WorkService.ForceFailTask(player) then
			return `no task in hand to run out — {WorkService.Describe(player)}`
		end
		return `task expired — {WorkService.Describe(player)}`
	end

	if arg == "stall" then
		-- The station-has-nothing-to-ask-for ending, which cannot otherwise be reached
		-- at a station that was built properly. Takes effect on the next tick rather
		-- than here, so what gets tested is the check in the shift loop itself.
		if not WorkService.ForceStall(player) then
			return `not on shift — {WorkService.Describe(player)}`
		end
		return `station marked as having nothing to ask for; the shift should be called off `
			.. `unpaid within a tick — {WorkService.Describe(player)}`
	end

	if arg == "standing" then
		local jobId = args[2]
		local value = tonumber(args[3])
		if jobId == nil or value == nil or not WorkService.SetStanding(player, jobId, value) then
			local standing = Config.Work.Standing
			return `usage: /job standing <jobId> <{standing.Min}..{standing.Max}> — {WorkService.Describe(player)}`
		end
		return WorkService.Describe(player)
	end

	if arg == "end" then
		if not WorkService.ForceEnd(player) then
			return `not on shift — {WorkService.Describe(player)}`
		end
		return `clocked off — {WorkService.Describe(player)}`
	end

	if arg == "quit" then
		if not WorkService.Quit(player) then
			return `no job to quit — {WorkService.Describe(player)}`
		end
		return `quit — walk back onto the mark to be hired again. {WorkService.Describe(player)}`
	end

	-- The sacking, which quitting is not: quit leaves and can walk straight back on,
	-- fire is done *to* you and shuts the pad until your next birthday. Walk back onto
	-- the mark after this and the refusal should read; /ageup should then open it again.
	if arg == "fire" then
		local fired, refusal = WorkService.ForceFire(player)
		if not fired then
			return `could not let you go: {refusal or "no reason given"} — {WorkService.Describe(player)}`
		end
		return `let go — the pad refuses until your next birthday. {WorkService.Describe(player)}`
	end

	if arg == "moment" then
		if not WorkService.ForceEvent(player) then
			return `not on shift, so there is no shift for a moment to happen in`
		end
		-- Deliberately reports the state rather than "fired": the pick can legitimately
		-- come back empty when every work event has been lived this life, and that is
		-- the single most confusing thing this command can do silently.
		return `tried the shift moment — {WorkService.Describe(player)}`
	end

	if arg == "hours" then
		local hours = tonumber(args[2])
		if hours == nil or not WorkService.SetHoursWorked(player, hours) then
			return `usage: /job hours <0-{Config.Work.YearGameHours}> — {WorkService.Describe(player)}`
		end
		return WorkService.Describe(player)
	end

	-- Named apart from `hours` on purpose, and the two are the easiest pair of commands
	-- in this file to confuse: `hours` is the year's budget, this is where you are inside
	-- one shift. The refusal below says which one it is rather than just failing, because
	-- the wrong one of these succeeds silently and looks like the right one not working.
	if arg == "skip" then
		local hour = tonumber(args[2])
		if hour == nil or not WorkService.ForceShiftHour(player, hour) then
			return `usage: /job skip <1-{Config.Work.ShiftGameHours}>, forward only, and not the same thing as /job hours — {WorkService.Describe(player)}`
		end
		-- The hours are credited by the shift tick, not here, so the line below still
		-- reports the old count for the quarter-second before it catches up. Said out
		-- loud rather than papered over: a tester who reads "0 of 8" straight after
		-- skipping to hour 3 would otherwise conclude the command did nothing.
		return `clock wound to hour {math.floor(hour)}; the hours are credited on the next tick — {WorkService.Describe(player)}`
	end

	return `usage: /job [start|end|quit|fire|task [id]|fail|skip <n>|moment|hours <n>|standing <jobId> <n>|on|off] — {WorkService.Describe(player)}`
end

-- Everything about the gym, on one command.
--
-- The gym had a complete harness -- force a workout, end one, describe one, switch the
-- whole system off -- and no way to reach any of it, which is how the `enabled` flag
-- managed to read DISABLED forever without anybody noticing. The command exists so that
-- never happens twice.
--
-- The four machines are meant to feel different, and the only way to check that from a
-- keyboard is to read the numbers the grader actually used, so bare /gym prints the
-- window of whatever machine you are standing at rather than a generic summary:
--
--   /gym                      machines found, the nearby machine's curve, sweep length,
--                             zone centre and both half-widths *at your current health*,
--                             the running session, and each machine's yearly allowance.
--   /stat health 0 then /gym, /stat health 100 then /gym
--                             the same machine printed twice. The half-widths should
--                             grow by HealthWindowBonus across that span -- this is the
--                             progression the player is supposed to feel, and it is
--                             invisible in play until you have felt both ends of it.
--   /gym start                a workout where you stand. Refusals carry their reason,
--                             so "too young" and "used the year up" read differently.
--   walk between machines with /gym after each
--                             centre, curve and sweep should all change. If two machines
--                             print the same three numbers they are the same machine.
--   /gym end                  ends the session the way walking out does, so the reps
--                             banked so far are kept and the year is still spent.
--   /gym off                  the whole system dark, for telling a gym bug apart from a
--                             places or a stats one. A session already running is closed
--                             out rather than abandoned, so the client is never left
--                             holding a rep counter for a workout that no longer exists.
Commands.gym = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return GymService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		GymService.SetEnabled(arg == "on")
		return `gym {arg} — {GymService.Describe(player)}`
	end

	if arg == "start" then
		local started, refusal = GymService.ForceStart(player)
		if not started then
			return `could not start: {refusal or "no reason given"} — {GymService.Describe(player)}`
		end
		return `workout started — {GymService.Describe(player)}`
	end

	if arg == "end" then
		if not GymService.ForceEnd(player) then
			return `no workout running — {GymService.Describe(player)}`
		end
		return `workout ended — {GymService.Describe(player)}`
	end

	return `usage: /gym [start|end|on|off] — {GymService.Describe(player)}`
end


-- /stadium                     seat/roam pool counts against their caps, and how many
--                              anchors gen_city.py salted through the bowl.
-- /stadium on|off              enable/disable the crowd; off tears down every spawned
--                              rig, which is the fast way to tell "the crowd is thin"
--                              apart from "the crowd is gone".
Commands.stadium = function(_player: Player, args: { string }): string
	local arg = string.lower(args[1] or "")
	if arg == "on" or arg == "off" then
		StadiumCrowdService.SetEnabled(arg == "on")
		return `stadium crowd {arg} — {StadiumCrowdService.Describe()}`
	end
	return StadiumCrowdService.Describe()
end

-- /gate                the entrance moment's own state: gate count, how many
--                      players have played it this session, on/off.
-- /gate on|off         enable/disable the whole moment.
-- /gate play           force it for the caller right now, off the nearest
--                      gate, without walking to the stadium first -- the
--                      camera cutscene, the fan, all of it, exactly as a
--                      real crossing would trigger it.
-- /gate reset          clear the caller's own "already played" flag, so a
--                      second /gate play (or a real walk-through) fires again.
Commands.gate = function(player: Player, args: { string }): string
	local arg = string.lower(args[1] or "")
	if arg == "on" or arg == "off" then
		StadiumEntranceService.SetEnabled(arg == "on")
		return `stadium entrance {arg} — {StadiumEntranceService.Describe()}`
	end
	if arg == "reset" then
		StadiumEntranceService.ResetPlayer(player.UserId)
		return `cleared — {StadiumEntranceService.Describe()}`
	end
	if arg == "play" then
		if not StadiumEntranceService.ForcePlayer(player) then
			return `no gate found — {StadiumEntranceService.Describe()}`
		end
		return `fired — {StadiumEntranceService.Describe()}`
	end
	return StadiumEntranceService.Describe()
end

-- Everything about the fight, on one command.
--
-- A fight is the hardest system in the game to reach from a keyboard, because reaching it
-- in play means finding somebody in the street who wants one. So the first job here is
-- simply to conjure an opponent -- and the second is to be able to conjure a *specific*
-- one, because the whole claim of this system is that three archetypes want three
-- different answers out of the same three buttons, and that claim is only testable by
-- fighting them back to back:
--
--   /fight                    the running bout: both fighters' footing, the player's
--                             stamina and charge, what the opponent is doing this
--                             instant and how far through their wind-up they are. Every
--                             style and its three defining numbers are on the end of it
--                             either way, so the usage line never has to list them.
--   /fight brawler            stands Deke in front of you. The tell is 1.4s and the
--                             punish window 0.9s: sidestep the big one, hit the recovery.
--   /fight scrapper           Wex, at 0.55s. Sidestepping should now be a mistake and
--                             guarding should be right -- if both archetypes play the
--                             same way, the numbers in content/Fighters.luau are not
--                             far enough apart and the system has no depth in it.
--   /fight boxer              Ruiz, who guards half the time. Nothing but a strike held
--                             past the guard-break mark should get through him.
--   /fight rival               whoever runs the block you are standing on, per
--                             TerritoryService.RegionOf -- refused on your own side and
--                             refused off anybody's turf. A win moves gang standing the
--                             way an incursion does; a plain style id (enforcer_north and
--                             the like) still stands one up with no territory check, for
--                             testing the fight itself without walking to their side.
--   /fight win, /fight lose   skips to the result, which is the only way to check the
--                             payouts and the getting-back-up without winning a fight
--                             first. Both settle the bout the way the tick would.
--   /fight end                walks away from it: the opponent leaves, nothing is paid.
--   /fight off                the whole system dark, for telling a fight bug apart from
--                             an NPC one. A bout already running is closed out rather
--                             than abandoned, so nobody is left stood in the road.
Commands.fight = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		-- Describe already names every style and its three defining numbers, so there is
		-- nothing to append here. The style list is only spelled out again on a refusal,
		-- where the player has just typed one that does not exist.
		return FightService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		FightService.SetEnabled(arg == "on")
		return `fight {arg} — {FightService.Describe(player)}`
	end

	if arg == "win" or arg == "lose" then
		if not FightService.ForceDecide(player, arg == "win") then
			return `no fight running — {FightService.Describe(player)}`
		end
		return `forced a {arg} — {FightService.Describe(player)}`
	end

	if arg == "end" then
		if not FightService.ForceEnd(player) then
			return `no fight running — {FightService.Describe(player)}`
		end
		return `fight ended — {FightService.Describe(player)}`
	end

	if arg == "rival" then
		local ok, refusal = FightService.ChallengeRival(player)
		if not ok then
			return `could not square up: {refusal or "no reason given"}`
		end
		return `rival is waiting — {FightService.Describe(player)}`
	end

	-- Anything else is read as a style id, and an unknown one is refused by name rather
	-- than silently standing up the default. Typing /fight boxr and getting a brawler is
	-- the kind of thing that costs an hour before anybody suspects the command.
	local ok, refusal = FightService.Challenge(player, arg)
	if not ok then
		return `could not square up: {refusal or "no reason given"} — styles: {table.concat(FightService.Styles(), ", ")}`
	end
	return `{arg} is waiting — {FightService.Describe(player)}`
end

-- Everything about school, on one command.
--
-- The first thing to check is the one thing no code here can fix: school needs a part
-- in the world tagged with the place id, exactly as the store and the office do. With
-- no such part there is no sign, no attend pad and no way in, and bare /school says so
-- in those words rather than leaving a silent building to be hunted for.
--
--   /school                   whether the building was found, what age you are, how
--                             many lessons this year, how many questions are written
--                             for this age, and why you can or cannot sit one.
--   /school start             a lesson where you stand, without the walk. Refusals are
--                             reported with their reason, so being too young or having
--                             used the year up can be read rather than guessed at.
--   /school end               walk-out grading, without the walk. Unanswered questions
--                             count as wrong, which is the rule worth seeing land.
--   /age 6 then /school       the door should open at StartAge and shut after EndAge.
--   /age 18 then /school      the refusal at the far end, which is the one players will
--                             meet by living rather than by being sent there.
--   /school year 3            the year used up. /school should then refuse at the door
--                             and the pad should still be standing there refusing --
--                             the building does not vanish because you are done with it.
--   /school year 0 then /ageup
--                             the missed year. Smarts should drop by SmartsPerYearMissed
--                             on the birthday, and only inside the school ages.
--   /school start then walk off
--                             the room radius should end it and grade what was answered.
--   /school card              closes the year on the spot and stages its card. The card
--                             is *not* handed over here -- walk to the school for it,
--                             because that walk is the feature. Run it three times with
--                             /ageup in between to see the record line grow.
--   /school card with no lessons sat
--                             the absent card: three empty slots naming the subjects that
--                             were on, and a year graded "never turned up".
--   /school off               the whole system dark, for telling a school bug apart from
--                             a places or a body one.
Commands.school = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return SchoolService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		SchoolService.SetEnabled(arg == "on")
		return `school {arg} — {SchoolService.Describe(player)}`
	end

	if arg == "start" then
		local started, refusal = SchoolService.ForceStart(player)
		if not started then
			return `could not sit a lesson: {refusal or "no reason given"} — {SchoolService.Describe(player)}`
		end
		return `lesson started — {SchoolService.Describe(player)}`
	end

	if arg == "end" then
		if not SchoolService.ForceEnd(player) then
			return `no lesson in progress — {SchoolService.Describe(player)}`
		end
		return `lesson graded — {SchoolService.Describe(player)}`
	end

	if arg == "card" then
		local ok, refusal = SchoolService.StageReportCard(player)
		if not ok then
			return `no card staged: {refusal or "no reason given"} — {SchoolService.Describe(player)}`
		end
		-- Says where it is, because the one thing that looks like a bug here is the command
		-- working and nothing appearing. It is on the profile; the school is where it is
		-- read.
		return `card staged — walk to the school to collect it. {SchoolService.Describe(player)}`
	end

	if arg == "year" then
		local count = tonumber(args[2])
		if count == nil or not SchoolService.SetLessonsThisYear(player, count) then
			return `usage: /school year <0-{Config.School.LessonsPerYear}> — {SchoolService.Describe(player)}`
		end
		return SchoolService.Describe(player)
	end

	-- The command that makes the skip reachable at all. Topping a subject out honestly is
	-- eight good lessons in it, and at three lessons a year shared across six subjects
	-- that is most of a childhood -- so `/school mastery music 5` and then walking to the
	-- pad is the only practical way to see the door panel.
	--
	-- `/lab level <n>` does the same for Science alone and also updates a session already
	-- in progress, which this cannot. The two are kept apart because the lab's level
	-- changes what is on screen mid-run and no other subject's does.
	if arg == "mastery" then
		local subjectId = string.lower(args[2] or "")
		local level = tonumber(args[3])
		if subjectId == "" or level == nil then
			return `usage: /school mastery <subject> <1-{Config.School.Mastery.Levels}>`
				.. ` — {SchoolService.Describe(player)}`
		end
		local ok, refusal = SchoolService.SetMastery(player, subjectId, level)
		if not ok then
			return `{refusal or "could not set it"} — {SchoolService.Describe(player)}`
		end
		return SchoolService.Describe(player)
	end

	if arg == "interact" then
		-- Lists every hand-placed interact anchor in the school building, its
		-- event id, its configured position, and whether it is currently tagged
		-- in the world. A missing tag means the furniture model has not been
		-- placed yet — the event id is valid but nothing in the map will fire it.
		local tag = Config.World.InteractTag
		local eventAttr = Config.World.InteractEventAttribute
		local tagged: { [string]: boolean } = {}
		for _, instance in CollectionService:GetTagged(tag) do
			local id = instance:GetAttribute(eventAttr)
			if typeof(id) == "string" then
				tagged[id] = true
			end
		end
		local lines: { string } = {}
		for _, entry in Config.School.Anchors do
			local status = tagged[entry.eventId] and "tagged" or "not tagged"
			table.insert(lines, `  {entry.eventId} at ({entry.x}, {entry.z}) — {status}`)
		end
		return `school interact anchors ({#lines}):\n` .. table.concat(lines, "\n")
	end

	return `usage: /school [start|end|card|year <n>|mastery <subject> <n>|interact|on|off]`
		.. ` — {SchoolService.Describe(player)}`
end

-- Everything about the Science lab, on one command.
--
-- Separate from /school even though a procedure *is* a lesson, because they fail in
-- completely different places. School's failures are about the door -- wrong age, year
-- used up, no building tagged. The lab's are about the room: a station the floor refused
-- to take, a procedure that names one, a level that hides too much of the board. Folding
-- them into one command would mean the two most common questions ("why can I not start
-- one" and "why is this one unplayable") printing the same paragraph.
--
-- The first line of bare /lab is the one that matters and it is the missing-station list.
-- The floor can refuse a station -- a wall, a slope, another station already there -- and
-- Lab.CanRun then refuses every procedure that names it. Played rather than read, that is
-- a lesson that starts and immediately ends for no visible reason.
--
--   /lab                      whether the room got built and where, which stations the
--                             floor refused, your mastery level and how much of the board
--                             it shows, the live benches with their stacks and clocks,
--                             charges left, and which of the four places you are standing.
--   /lab start                a procedure where you stand -- but note the lab is always
--                             the lab: this teleports nothing, so run it from inside the
--                             room or the first proximity tick will find you outside it.
--   /lab end                  grades whatever is on the benches now, the way the clock
--                             running out does. The way to see a half-finished stack score
--                             rather than having to sit through eighty seconds.
--   /lab level 1 then /lab level 5
--                             the whole progression, twice, in ten seconds. At 1 the board
--                             shows three steps of an eight-step procedure and you will
--                             walk back to it four times; at 5 it shows all eight and the
--                             board is furniture. If those two feel the same, requirement
--                             six is not landing and no amount of play will tell you why.
--   /lab refill               the pool back to full without the cupboard trip, for testing
--                             scoring without the traversal in the way.
--   walk to a station with 0 charges
--                             should refuse by name rather than doing nothing. The click
--                             that silently fails is the one bug this activity cannot have.
--   /lab off                  the whole verb dark, for telling a lab bug apart from a
--                             school one -- /school start should then hand science to the
--                             quiz path instead of refusing.
Commands.lab = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return ScienceService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		ScienceService.SetEnabled(arg == "on")
		return `lab {arg} — {ScienceService.Describe(player)}`
	end

	if arg == "start" then
		local started, refusal = ScienceService.ForceStart(player)
		if not started then
			return `could not start a procedure: {refusal or "no reason given"} — {ScienceService.Describe(player)}`
		end
		return `procedure started — {ScienceService.Describe(player)}`
	end

	if arg == "end" then
		if not ScienceService.ForceEnd(player) then
			return `no procedure running — {ScienceService.Describe(player)}`
		end
		return `benches graded — {ScienceService.Describe(player)}`
	end

	if arg == "level" then
		local level = tonumber(args[2])
		if level == nil or not ScienceService.SetLevel(player, level) then
			return `usage: /lab level <1-{#Config.School.Science.RevealedStepsByLevel}> — {ScienceService.Describe(player)}`
		end
		return ScienceService.Describe(player)
	end

	if arg == "refill" then
		if not ScienceService.Refill(player) then
			return `nothing to refill — {ScienceService.Describe(player)}`
		end
		return `reagents topped up — {ScienceService.Describe(player)}`
	end

	return `usage: /lab [start|end|level <n>|refill|on|off] — {ScienceService.Describe(player)}`
end

-- Everything about the Geography errand, on one command.
--
-- Separate from /school and from /lab for the same reason those two are separate from each
-- other: this verb fails somewhere neither of them can. Its failures are about the *place
-- graph* -- too few sendable points, a town made entirely of route nodes, a destination
-- upstairs behind a door -- and none of that is visible from a lesson that simply does not
-- start.
--
-- The first line of bare /geo is the one that matters and it is the sendable count. The
-- errand skips waypoints and skips anything more than Hunt.MaxRiseStuds off the floor you
-- started on, so "382 tagged" and "0 sendable" is an entirely possible and entirely silent
-- state -- and it is what a half-built world looks like from in here.
--
--   /geo                      how many places are sendable out of how many are tagged,
--                             your mastery level and what it tells you, and the live
--                             errand: which stop, how far off you are, the clock, and the
--                             credit banked so far.
--   /geo start                an errand from where you stand. Unlike /lab start this is
--                             the real thing -- the first leg is measured from your feet,
--                             so it is worth running from somewhere other than the school
--                             to see what the town looks like from there.
--   /geo find                 counts the destination in hand as reached. The command to
--                             use, because the walk is thirty seconds and it stands in
--                             front of everything worth testing: the arrival beat, the
--                             next leg being drawn from the right spot, the closing line,
--                             and the report card row.
--   /geo end                  grades the errand where it stands, the way giving up does.
--   /geo level 1 then /geo level 4
--                             the whole progression in ten seconds, and the one thing to
--                             actually judge. At 1 you get a name and nothing else; at 4
--                             you get an arrow and a distance, which is very nearly the
--                             guide line the rest of the game gives away. If the town does
--                             not feel meaningfully more legible between those two, this
--                             subject has no reward in it and the ladder needs rewriting
--                             rather than retuning.
--   /geo off                  the whole verb dark, for telling a geography bug apart from
--                             a school one -- /school start should then hand geography to
--                             the quiz path instead of refusing.
Commands.geo = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return GeographyService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		GeographyService.SetEnabled(arg == "on")
		return `geography {arg} — {GeographyService.Describe(player)}`
	end

	if arg == "start" then
		local started, refusal = GeographyService.ForceStart(player)
		if not started then
			return `could not start an errand: {refusal or "no reason given"} — {GeographyService.Describe(player)}`
		end
		return `errand started — {GeographyService.Describe(player)}`
	end

	if arg == "find" then
		if not GeographyService.ForceFind(player) then
			return `nothing to find — {GeographyService.Describe(player)}`
		end
		return `stop reached — {GeographyService.Describe(player)}`
	end

	if arg == "end" then
		if not GeographyService.ForceEnd(player) then
			return `no errand running — {GeographyService.Describe(player)}`
		end
		return `errand graded — {GeographyService.Describe(player)}`
	end

	if arg == "level" then
		local level = tonumber(args[2])
		if level == nil or not GeographyService.SetLevel(player, level) then
			return `usage: /geo level <1-{#Config.School.Hunt.RevealedByLevel}> — {GeographyService.Describe(player)}`
		end
		return GeographyService.Describe(player)
	end

	return `usage: /geo [start|find|end|level <n>|on|off] — {GeographyService.Describe(player)}`
end

-- The art room, and the one verb whose bug you cannot see by looking at it.
--
-- Everything in Art is a colour on a part, so a wrong scoring rule and a right one look
-- identical on screen -- both are a wall and a canvas with paint on them. This command
-- exists to print the numbers underneath: which study is up, how many tubes you were
-- handed, how many cells are filled and how many have gone stale, and what the canvas
-- would score if you signed it now.
--
--   /art                      the wall, the palette, the canvas and the live score. The
--                             stale count here and the stale count on the panel must be
--                             the same number; if they ever differ, the panel is lying
--                             about the only thing it is allowed to tell you.
--   /art start                a lesson from where you stand, so the room can be tested
--                             without waiting for a birthday. You still have to walk to
--                             the easel -- the verb is not skippable and this does not
--                             skip it.
--   /art shift                moves one cell of the study now, instead of waiting out
--                             Config.School.Art.ShiftSeconds. The command to use: the
--                             whole subject is whether a player *notices* a shift, and
--                             the only way to judge that is to cause one while looking
--                             somewhere else on purpose.
--   /art refill               fills the paint back up without the walk, for testing the
--                             scoring apart from the errand.
--   /art sign                 hands the canvas in the way the button does.
--   /art end                  grades it where it stands, the way walking out does.
--   /art level 1 then /art level 5
--                             two tubes against eight, on the same study. At 1 a perfect
--                             copy barely passes, which is the point -- if it does not
--                             feel like being handed the picture's actual colours on the
--                             way up, the ladder is a number and needs rewriting rather
--                             than retuning.
--   /art off                  the whole verb dark, so an art bug can be told apart from a
--                             school one -- /school start should then hand art to the
--                             quiz path instead of refusing.
-- /nerve -- the corridor, and the one system in school you cannot test by walking to a
-- pad. Everything about a stare-down is over in five seconds and half of it depends on
-- what the life already is, so without this the only way to see the window widen is to
-- play thirty corridors and the only way to see an overhold tip into a fight is to lose
-- one on purpose at exactly the right moment.
--
--   /nerve                    both bars, the tier, the window this life has earned, and
--                             who is currently stood in front of you.
--   /nerve go [id]            puts somebody in front of you where you stand, ignoring
--                             cooldowns and the corridor -- see /nerve list for ids.
--   /nerve stood              ends it as though the release landed in the window.
--   /nerve backed             ends it as though the release landed under their patience.
--   /nerve over               ends it as an overhold, which is the only path into a
--                             fight and therefore the only way to test that door.
--   /nerve end                ends it the way walking away does: no outcome, no toll.
--   /nerve set <0-100>        sets this life\'s nerve, which is the only way to watch the
--                             release window physically widen without playing for it.
--   /nerve homework [on|off]  takes or returns the homework, for testing the library walk
--                             without having to lose a stare-down to somebody who wants it.
--   /nerve list               every archetype, with the drain and demand of each.
--   /nerve off                the corridor dark, so a bully bug can be told apart from a
--                             school bug by turning one of them off.
-- /read -- the reading board. Everything about it depends on what was dealt, so without
-- this the only way to see the hand-in, the scoring or the takeback ladder is to spell six
-- words by hand at the right desk at the right age.
--
--   /read                     both words with their answers, the tray, the clock and the
--                             takebacks left.
--   /read start               a lesson from where you stand, so the room can be tested
--                             without walking a childhood to it.
--   /read solve               fills every gap on the board correctly, which is the only
--                             quick way to reach the hand-in and the scoring.
--   /read end                 grades it where it stands, the way walking out does.
--   /read off                 the whole verb dark, so a reading bug can be told apart from
--                             a school bug by turning one of them off.
-- /music -- the rhythm lesson. Everything about it happens in a hundred-beat window at
-- millisecond resolution, so without an autoplay there is no way to reach the scoring, the
-- report line or a mastery rung except by playing a whole piece by hand at the right age.
--
--   /music                    the windows this life has earned, the tallies and the streak.
--   /music start              a piece from where you stand.
--   /music auto [grade]       judges every remaining note at perfect, great or good, which
--                             is the only quick way to see a band other than F.
--   /music end                grades it where it stands, the way walking off does.
--   /music off                the verb dark, so a music bug can be told apart from a school
--                             bug by turning one of them off.
Commands.music = function(player: Player, args: { string }): string
	local arg = args[1]

	if arg == nil then
		return MusicService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		MusicService.SetEnabled(arg == "on")
		return `music {arg} — {MusicService.Describe(player)}`
	end

	if arg == "start" then
		local started, refusal = MusicService.ForceStart(player)
		if not started then
			return `could not start a piece: {refusal or "no reason given"} — {MusicService.Describe(player)}`
		end
		return `piece started — {MusicService.Describe(player)}`
	end

	if arg == "auto" then
		local ok, refusal = MusicService.Autoplay(player, args[2] or "perfect")
		if not ok then
			return `could not autoplay: {refusal or "no reason given"} — {MusicService.Describe(player)}`
		end
		return `played out — {MusicService.Describe(player)}`
	end

	if arg == "end" then
		if not MusicService.ForceEnd(player) then
			return `no piece running — {MusicService.Describe(player)}`
		end
		return `graded where it stood — {MusicService.Describe(player)}`
	end

	return `usage: /music [start|auto [perfect|great|good]|end|on|off] — {MusicService.Describe(player)}`
end

Commands.read = function(player: Player, args: { string }): string
	local arg = args[1]

	if arg == nil then
		return ReadingService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		ReadingService.SetEnabled(arg == "on")
		return `reading {arg} — {ReadingService.Describe(player)}`
	end

	if arg == "start" then
		local started, refusal = ReadingService.ForceStart(player)
		if not started then
			return `could not start a board: {refusal or "no reason given"} — {ReadingService.Describe(player)}`
		end
		return `board dealt — {ReadingService.Describe(player)}`
	end

	if arg == "solve" then
		if not ReadingService.Solve(player) then
			return `no board to solve — {ReadingService.Describe(player)}`
		end
		return `every gap filled — {ReadingService.Describe(player)}`
	end

	if arg == "end" then
		if not ReadingService.ForceEnd(player) then
			return `no board running — {ReadingService.Describe(player)}`
		end
		return `graded where it stood — {ReadingService.Describe(player)}`
	end

	return `usage: /read [start|solve|end|on|off] — {ReadingService.Describe(player)}`
end

Commands.nerve = function(player: Player, args: { string }): string
	local arg = args[1]

	if arg == nil then
		return BullyService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		BullyService.SetEnabled(arg == "on")
		return `corridor {arg} — {BullyService.Describe(player)}`
	end

	if arg == "list" then
		local lines = { "bullies:" }
		for _, bully in Bullies.All do
			table.insert(
				lines,
				`  {bully.id}  {bully.body.name}  {bully.drain}/{bully.demand}`
					.. `  patience {bully.patienceSeconds}s  ages {bully.minAge}-{bully.maxAge}`
			)
		end
		return table.concat(lines, "\n")
	end

	if arg == "go" then
		local started, refusal = BullyService.ForceEngage(player, args[2])
		if not started then
			return `nobody stepped across you: {refusal or "no reason given"} — {BullyService.Describe(player)}`
		end
		return `somebody is in front of you — {BullyService.Describe(player)}`
	end

	if arg == "stood" or arg == "backed" or arg == "over" then
		-- "over" rather than "overheld" on the command line, because the outcome name the
		-- service uses is the one the code reads and this is the one a person types.
		local outcome = if arg == "over" then "overheld" else arg
		local ok, refusal = BullyService.ForceResolve(player, outcome)
		if not ok then
			return `could not resolve: {refusal or "no reason given"} — {BullyService.Describe(player)}`
		end
		return `resolved as {outcome} — {BullyService.Describe(player)}`
	end

	if arg == "end" then
		if not BullyService.ForceEnd(player) then
			return `nothing to walk away from — {BullyService.Describe(player)}`
		end
		return `you walked away — {BullyService.Describe(player)}`
	end

	if arg == "set" then
		local value = tonumber(args[2])
		if value == nil then
			return `usage: /nerve set <0-{Config.Stats.Max}> — {BullyService.Describe(player)}`
		end
		local ok, refusal = BullyService.SetNerve(player, value)
		if not ok then
			return `could not set nerve: {refusal or "no reason given"}`
		end
		return `nerve set — {BullyService.Describe(player)}`
	end

	if arg == "homework" then
		local taken = args[2] ~= "off"
		if not BullyService.SetHomeworkTaken(player, taken) then
			return "no profile loaded"
		end
		return `homework {if taken then "taken" else "returned"} — {BullyService.Describe(player)}`
	end

	return `usage: /nerve [go [id]|stood|backed|over|end|set <n>|homework [on|off]|list|on|off]`
		.. ` — {BullyService.Describe(player)}`
end

Commands.art = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return ArtService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		ArtService.SetEnabled(arg == "on")
		return `art {arg} — {ArtService.Describe(player)}`
	end

	if arg == "start" then
		local started, refusal = ArtService.ForceStart(player)
		if not started then
			return `could not start a study: {refusal or "no reason given"} — {ArtService.Describe(player)}`
		end
		return `study started — {ArtService.Describe(player)}`
	end

	if arg == "shift" then
		-- Takes no player on purpose. The wall is the room's rather than anybody's, and a
		-- shift landing for one painter and not the other beside them would be a different
		-- game from the one this is.
		if not ArtService.ForceShift() then
			return `nothing on the wall — {ArtService.Describe(player)}`
		end
		return `the study moved — {ArtService.Describe(player)}`
	end

	if arg == "refill" then
		if not ArtService.Refill(player) then
			return `nothing to refill — {ArtService.Describe(player)}`
		end
		return `paint topped up — {ArtService.Describe(player)}`
	end

	if arg == "sign" then
		if not ArtService.ForceSign(player) then
			return `no study running — {ArtService.Describe(player)}`
		end
		return `canvas signed — {ArtService.Describe(player)}`
	end

	if arg == "end" then
		if not ArtService.ForceEnd(player) then
			return `no study running — {ArtService.Describe(player)}`
		end
		return `canvas graded — {ArtService.Describe(player)}`
	end

	if arg == "level" then
		local level = tonumber(args[2])
		if level == nil or not ArtService.SetLevel(player, level) then
			return `usage: /art level <1-{#Config.School.Art.PaletteByLevel}> — {ArtService.Describe(player)}`
		end
		return ArtService.Describe(player)
	end

	return `usage: /art [start|sign|end|shift|refill|level <n>|on|off] — {ArtService.Describe(player)}`
end

-- Heat, and the whole reason this command exists rather than a crime to commit.
--
-- Part one of crime ships the *response* without anything to provoke it, which is
-- deliberate: the pursuit is the hard half and it is fully testable on its own, and
-- building the theft first would have meant tuning a chase by robbing a shop forty times.
-- `/bounty 50` is the shop.
--
-- Nothing in this system can be checked by looking at it. An officer walking toward you
-- looks identical whether it has seen you or is heading for a spot you left thirty seconds
-- ago, and those two are the entire feature. Bare `/bounty` and `/police` print the
-- difference.
--
--   /bounty                   the number, the tier, how long since anybody saw you, and
--                             where the police currently believe you are. The last two are
--                             the ones to read: if "unseen" is climbing while an officer
--                             is stood in front of you, sight is broken.
--   /bounty <n>               set the heat to n and let the town respond. The command.
--                             Try 20, then 50, then 95 and watch the street change shape
--                             rather than the numbers change size.
--   /bounty clear             drop it with no conviction, for testing the cool-down path
--                             without serving a sentence.
--   /bounty arrest            take the arrest now: the sentence, the confiscation and the
--                             record, without waiting to be cornered. The fastest way to
--                             check what a conviction actually costs a life.
--   /bounty off               freeze the decay without removing the heat, so a tier can be
--                             held still while the officers are watched.
Commands.bounty = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return BountyService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		BountyService.SetEnabled(arg == "on")
		return `bounty decay {arg} — {BountyService.Describe(player)}`
	end

	if arg == "clear" then
		BountyService.Clear(player)
		return `heat dropped — {BountyService.Describe(player)}`
	end

	if arg == "arrest" then
		if not BountyService.Arrest(player) then
			return `nothing to arrest you for — {BountyService.Describe(player)}`
		end
		return `arrested — {BountyService.Describe(player)}`
	end

	local amount = tonumber(arg)
	if amount == nil then
		return `usage: /bounty [<n>|clear|arrest|on|off] — {BountyService.Describe(player)}`
	end

	-- Set rather than add, because the thing being tested is a tier and the tester is
	-- holding a table of thresholds. Done as a clear followed by an add so that there is
	-- exactly one path that raises heat in the whole game, and the harness is on it -- a
	-- debug command with its own private way of writing the number is a debug command that
	-- eventually tests something the player can never reach.
	BountyService.Clear(player)
	if amount > 0 then
		BountyService.Add(player, amount, "Debug heat")
	end
	return BountyService.Describe(player)
end

-- The bodies, separately from the number that summoned them.
--
-- Split from /bounty for the same reason PoliceService is split from BountyService: when
-- a pursuit misbehaves the first question is always which half is wrong, and one command
-- printing both would make that the one thing it could not tell you.
--
--   /police                   every officer out: which post, whether it is pursuing or
--                             searching, and how far through an arrest it is. "searching"
--                             while stood next to you is the bug worth catching -- it
--                             means line of sight is failing, usually on geometry.
--   /police clear             every body off the street, leaving the heat alone. They
--                             should come straight back, which is the point: it tests that
--                             the response rebuilds from the number rather than being
--                             remembered.
--   /police off               no officers regardless of heat, for telling a pursuit bug
--                             apart from a bounty one.
-- The drawer, separately from the heat it earns.
--
--   /theft                    every shop in the content list: whether its till is built,
--                             what is left in it, and where its clerk and camera are
--                             pointed right now. "NOT BUILT" is the one worth catching --
--                             it means a place id in content/Tills.luau no longer names a
--                             room in the town, and the door would simply do nothing.
--   /theft go <place>         stand at that shop's counter. The walk is the game, but the
--                             walk is not the thing being tested when the question is
--                             whether a clerk turns.
--   /theft fill               every drawer back to full, without waiting out the refill.
--   /theft off                no robbery at any counter, for telling a theft bug apart
--                             from a bounty one.
--   /theft crew <id>          send that crew member (see /gang crew) to watch the door
--                             instead of taking your chances alone. Only works while
--                             already at a till -- `/theft go <place>` first.
Commands.theft = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return TheftService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		TheftService.SetEnabled(arg == "on")
		return `theft {arg} — {TheftService.Describe(player)}`
	end

	if arg == "fill" then
		TheftService.RefillAll()
		return `drawers filled — {TheftService.Describe(player)}`
	end

	if arg == "go" then
		local place = args[2]
		if place == nil then
			return "usage: /theft go <place>"
		end
		if not PlaceService.Send(player, place) then
			return `no place called "{place}"`
		end
		return `sent to {place} — {TheftService.Describe(player)}`
	end

	if arg == "crew" then
		local crewId = args[2]
		if crewId == nil then
			return `usage: /theft crew <id> — {TheftService.Describe(player)}`
		end
		local place = TheftService.PlaceOf(player)
		if place == nil then
			return `not at a till — {TheftService.Describe(player)}`
		end
		local ok, why = TheftService.CallCrew(player, place, crewId)
		if not ok then
			return `{why or "could not call them"} — {TheftService.Describe(player)}`
		end
		return `called — {TheftService.Describe(player)}`
	end

	return `usage: /theft [go <place>|fill|on|off|crew <id>] — {TheftService.Describe(player)}`
end

-- The vault, separately again, because the bank fails in ways a till cannot.
--
--   /bank                     every bank: whether the room is built, how many patrol spots
--                             survived the standable check, what is left in the vault, what
--                             the alarm is doing and how long it has left, how many people
--                             are inside, and where the guard is. Two lines here are worth
--                             catching before anything else. "NOT BUILT" means the place id
--                             in content/Vaults.luau no longer names a room. "0 patrol
--                             spot(s)" means the offsets in that file have drifted off the
--                             generated floor -- the bank still works, but it is running as
--                             a clean twelve-second metronome with nothing interfering with
--                             it, which is a much easier room than the one that was designed
--                             and reads as the guard being broken rather than absent.
--   /bank go                  stand in the bank. The walk across town is the game and is not
--                             what is being tested when the question is whether a door swings.
--   /bank reset               every vault full, every alarm quiet, every door shut. Both
--                             halves at once on purpose: the two questions a run answers are
--                             "can I open it" and "can I shut it up", and being handed a full
--                             vault behind a ringing bell would only ever let you retry one.
--   /bank off                 no vault opens anywhere, for telling a bank bug apart from a
--                             pursuit one -- with this off, a chase that starts at the bank
--                             is somebody else's fault.
--   /bank crew <id>           send that crew member (see /gang crew) to the alarm instead of
--                             holding it yourself. Only works while standing in a bank a
--                             session is already open in -- `/bank go` first.
Commands.bank = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return BankService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		BankService.SetEnabled(arg == "on")
		return `bank {arg} — {BankService.Describe(player)}`
	end

	if arg == "reset" then
		BankService.ResetAll()
		return `vaults reset — {BankService.Describe(player)}`
	end

	if arg == "go" then
		-- The place id rather than a name the player types, because there is one bank and
		-- asking for it by content id is what catches the case this command exists to catch:
		-- if the id has drifted, this refuses by name instead of walking somebody into a
		-- room with no vault in it.
		local place = args[2] or Vaults.Banks[1].place
		if not PlaceService.Send(player, place) then
			return `no place called "{place}"`
		end
		return `sent to {place} — {BankService.Describe(player)}`
	end

	if arg == "crew" then
		local crewId = args[2]
		if crewId == nil then
			return `usage: /bank crew <id> — {BankService.Describe(player)}`
		end
		local place = BankService.PlaceOf(player)
		if place == nil then
			return `not in a bank — {BankService.Describe(player)}`
		end
		local ok, why = BankService.CallCrew(player, place, crewId)
		if not ok then
			return `{why or "could not call them"} — {BankService.Describe(player)}`
		end
		return `called — {BankService.Describe(player)}`
	end

	return `usage: /bank [go [<place>]|reset|on|off|crew <id>] — {BankService.Describe(player)}`
end

-- Skills, which have no room to walk into and no panel of their own to force open, so
-- this is the only way to see one move without playing the discipline that feeds it.
--
--   /skill                    every discipline: rung, name, XP, and the next threshold.
--   /skill <id> <n>           n XP into that discipline, through SkillService.Award --
--                             the same seam every hook in the tree uses, so this is
--                             testing the real path rather than a debug-only one. Still
--                             clamped by Config.Skills.MaxPerAward, on purpose: a command
--                             that could jump the cap would be testing a path nothing else
--                             can reach.
--   /skill <id> max           straight to the top rung, for looking at what a Master row
--                             draws like without earning one. Loops Award rather than
--                             writing the number, so the clamp still holds and the pushes
--                             the client would really see still happen.
Commands.skill = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local skillId = string.lower(args[1] or "")
	if skillId == "" then
		return SkillService.Describe(player)
	end

	local amount = string.lower(args[2] or "")
	if amount == "" then
		return "usage: /skill <id> <n|max>"
	end

	local ladder = Config.Skills.Levels
	local top = ladder[#ladder].atXp
	local points = if amount == "max" then top else tonumber(amount)
	if points == nil then
		return "usage: /skill <id> <n|max>"
	end

	-- Looped rather than handed over in one call, because Award clamps and a single
	-- request for the whole ladder would silently become one capped grant. The bound is
	-- the ladder over the clamp plus slack, which is finite and small.
	local calls = math.ceil(points / Config.Skills.MaxPerAward)
	local ok, err = pcall(function()
		for _ = 1, calls do
			SkillService.Award(player, skillId, Config.Skills.MaxPerAward, "debug")
		end
	end)
	if not ok then
		return tostring(err)
	end

	return SkillService.Describe(player)
end

-- Codes. The redeem box is a text field in a menu, so it is perfectly reachable by hand --
-- what is not reachable by hand is the *second* attempt at a code you have already used,
-- which is the case worth testing and the one you can only reach by throwing a redemption
-- away first.
--
--   /code                     what this account has redeemed, and out of how many.
--   /code <string>            redeem through the same path the box uses, refusals and all.
--                             Deliberately not a shortcut past the checks: a command that
--                             granted a code directly would test nothing that matters.
--   /code clear               un-redeem everything, so the same code can be tested twice
--                             without a second account. The only way back -- nothing in the
--                             game removes a redemption, because a code that can be given
--                             back is a code that can be redeemed twice.
Commands.code = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = args[1] or ""
	if arg == "" then
		return CodeService.Describe(player)
	end

	if string.lower(arg) == "clear" then
		local cleared = CodeService.Clear(player)
		return `cleared {cleared} redemption(s) — {CodeService.Describe(player)}`
	end

	return CodeService.Force(player, arg)
end

-- Settings, which are four booleans that each change something somewhere else. The value
-- of this command is not flipping them -- the pane does that in one click -- it is being
-- able to read all of them back on one line while looking at whatever they were supposed
-- to have changed.
--
--   /setting                  every option and its state.
--   /setting <id> on|off      flip one, through the same write the pane's click uses.
Commands.setting = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local id = args[1] or ""
	if id == "" then
		return SettingsService.Describe(player)
	end

	local value = string.lower(args[2] or "")
	if value ~= "on" and value ~= "off" then
		return "usage: /setting <id> on|off"
	end

	if not SettingsService.Force(player, id, value == "on") then
		return `no setting "{id}" — {SettingsService.Describe(player)}`
	end
	return SettingsService.Describe(player)
end

-- The gang, which is the one crime system whose state outlives the run that made it.
--
--   /gang                     all four: standing with each, whether their boss is actually
--                             standing up, which one you run with (*), the rung you hold,
--                             what you could take right now, whether the colors are on and
--                             how long the rejoin window has left. "no boss" on all four at
--                             once means the posts have not been built yet -- they are torn
--                             down in an empty server and rebuilt on the next join, so this
--                             is normal for about half a second and a bug after that.
--   /gang go <id>             walk to whoever runs that gang. The four are deliberately in
--                             four different rooms and finding them is the content, which is
--                             not what is being tested when the question is whether a rung
--                             hands over.
--   /gang join <id>           in, without the walk. Still refuses if you are already in one
--                             and still honours the rejoin window, because those are the two
--                             rules worth testing and a debug join that skipped them would
--                             be testing something else.
--   /gang credit <n>          n standing with the gang you are in, through the same seam
--                             every robbery uses. The fast way to climb the ladder without
--                             emptying four vaults, and it takes the promotion notice with
--                             it -- which is the thing most likely to be wrong.
--   /gang colors [on|off]     the band, on or off. No argument toggles it. This is the one
--                             that changes how hard the game is: the colors multiply every
--                             point of heat, so /bounty and this belong in the same session.
--   /gang reset               out of the gang, standing wiped, band off. Unlike leaving,
--                             which keeps the standing -- a reset is a clean slate and a
--                             resignation is not.
--   /gang off                 nobody is standing at any of the four and no band goes on
--                             anybody's head, for telling a gang bug apart from a pursuit
--                             one -- with this off, heat is nobody's fault but yours.
--   /gang crew                who runs with you and their nerve, or how many slots your
--                             rung carries if it is none. Reads Describe's own line, so
--                             this is a convenience rather than a second source of truth.
--   /gang crew add            recruits through the real `recruit`, without the walk or the
--                             rung -- so a "name" can be tested straight away rather than
--                             ground up to 400 standing first. Still refuses past your
--                             rung's own slot count, because that check is the thing worth
--                             testing.
--   /gang crew drop <id>      dismisses through the real `dismiss`. The id is whatever
--                             `/gang crew` just printed, not the name -- two recruits can
--                             share a nickname, and an id never can.
Commands.gang = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return GangService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		GangService.SetEnabled(arg == "on")
		return `gang {arg} — {GangService.Describe(player)}`
	end

	if arg == "reset" then
		GangService.ResetPlayer(player)
		return `gang wiped — {GangService.Describe(player)}`
	end

	if arg == "colors" then
		local want = args[2]
		local target = if want == nil then not GangService.IsWearing(player) else string.lower(want) == "on"
		if not GangService.SetColors(player, target) then
			return `colors unchanged — {GangService.Describe(player)}`
		end
		return `colors {if target then "on" else "off"} — {GangService.Describe(player)}`
	end

	if arg == "credit" then
		local points = tonumber(args[2])
		if points == nil then
			return "usage: /gang credit <n>"
		end
		local after = GangService.Credit(player, points, "did something worth hearing about")
		return `standing {string.format("%.0f", after)} — {GangService.Describe(player)}`
	end

	if arg == "crew" then
		local sub = string.lower(args[2] or "")
		if sub == "add" then
			local data = DataService.GetProfile(player)
			local gangId = if data ~= nil then Lives.Active(data.Data).gangId else nil
			if gangId == nil then
				return `not in a gang — {GangService.Describe(player)}`
			end
			local id = GangService.ForceRecruit(player, gangId)
			if id == nil then
				return `could not recruit — {GangService.Describe(player)}`
			end
			return `recruited {id} — {GangService.Describe(player)}`
		end
		if sub == "drop" then
			local crewId = args[3]
			if crewId == nil then
				return "usage: /gang crew drop <id>"
			end
			if not GangService.ForceDismiss(player, crewId) then
				return `no crew member "{crewId}" — {GangService.Describe(player)}`
			end
			return `dropped {crewId} — {GangService.Describe(player)}`
		end
		return GangService.Describe(player)
	end

	if arg == "join" or arg == "go" then
		local gangId = string.lower(args[2] or "")
		local def = Gangs.ById[gangId]
		if def == nil then
			local ids: { string } = {}
			for _, entry in Gangs.All do
				table.insert(ids, entry.id)
			end
			return `usage: /gang {arg} <{table.concat(ids, "|")}>`
		end
		if arg == "go" then
			if not PlaceService.Send(player, def.bossPlaceId) then
				-- Names the place rather than shrugging, because the failure this catches is a
				-- boss whose bossPlaceId has drifted off the map -- which otherwise reads as a
				-- gang that simply cannot be joined, with nothing anywhere saying why.
				return `{def.name}'s boss is meant to be at "{def.bossPlaceId}", and there is no such place`
			end
			return `sent to {def.name} at {def.bossPlaceId} — {GangService.Describe(player)}`
		end
		if not GangService.ForceJoin(player, def.id) then
			return `could not join {def.name} — {GangService.Describe(player)}`
		end
		return `joined {def.name} — {GangService.Describe(player)}`
	end

	return `usage: /gang [go <id>|join <id>|credit <n>|colors [on|off]|crew [add|drop <id>]|reset|on|off] — {GangService.Describe(player)}`
end

Commands.police = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return PoliceService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		PoliceService.SetEnabled(arg == "on")
		return `police {arg} — {PoliceService.Describe(player)}`
	end

	if arg == "clear" then
		PoliceService.Clear(player)
		return `street cleared — {PoliceService.Describe(player)}`
	end

	return `usage: /police [clear|on|off] — {PoliceService.Describe(player)}`
end

-- How much you stand out, and how far every pair of eyes on you has got with it.
--
-- Its own command rather than a line inside /police or /crowd, because the number it prints
-- is the one thing both of those have in common and reading it in two places invites the
-- suspicion that they are two numbers. They are not, and the fastest way to be sure of that
-- is to see the same figure quoted by both halves of one line.
--
-- The three arguments exist because the terms are hard to isolate by playing: heat needs a
-- crime, movement needs somewhere to run, and colors need a gang. Being able to set one and
-- watch the notice clocks change is the difference between tuning this and guessing at it.
--
--   /spot                     the breakdown, plus every officer's notice and the crowd's
--   /spot heat <n>            set the bounty outright, to move the headline term
--   /spot colors [on|off]     put gang colors on or take them off
Commands.spot = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local function report(): string
		return `{BountyService.DescribeConspicuousness(player)}\n  police: {PoliceService.Describe(player)}\n  crowd: {WitnessService.Describe(player)}`
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return report()
	end

	if arg == "heat" then
		local points = tonumber(args[2])
		if points == nil then
			return `usage: /spot heat <n> — {report()}`
		end
		-- Cleared and re-added rather than written, for the same reason /bounty <n> does it:
		-- there is exactly one path in the game that raises heat and the harness stays on it.
		BountyService.Clear(player)
		if points > 0 then
			BountyService.Add(player, points, "Debug heat")
		end
		return report()
	end

	if arg == "colors" then
		local value = string.lower(args[2] or "")
		if value ~= "on" and value ~= "off" then
			return `usage: /spot colors [on|off] — {report()}`
		end
		if not GangService.SetColors(player, value == "on") then
			-- Named rather than shrugged, because the failure this catches is almost always
			-- "you are not in a gang", and a silent no-op here reads as the colors term being
			-- broken rather than as there being no colors to wear.
			return `colors unchanged — {GangService.Describe(player)}`
		end
		return report()
	end

	return `usage: /spot [heat <n>|colors on|off] — {report()}`
end

-- The town looking at you, and the one thing you can do about it.
--
-- Both on one command because they are one loop from the player's side -- the crowd reads a
-- description and the change of clothes destroys it -- and testing either without the other
-- tells you almost nothing. The two switches are separate for exactly the case where that
-- stops being true: with `/crowd witness off` a chase that never ends is the pursuit's
-- fault, and with `/crowd disguise off` an escape that happens anyway is not the mark's.
--
--   /crowd                    who is close enough to recognise you, how many are staring,
--                             and whether the police have a description at all -- which is
--                             the answer to "why is nobody reacting" nine times in ten.
--   /crowd go <n>             stand you on the nth hideout mark, because four of them are
--                             a long walk apart on purpose and testing the five-second
--                             count should not cost the walk every time.
--   /crowd describe           hand the police a description without committing a crime, so
--                             the crowd can be tested from a standing start.
--   /crowd witness [on|off]
--   /crowd disguise [on|off]
Commands.crowd = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local function report(): string
		return `{WitnessService.Describe(player)} — {DisguiseService.Describe(player)}`
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return report()
	end

	if arg == "witness" or arg == "disguise" then
		local value = string.lower(args[2] or "")
		if value ~= "on" and value ~= "off" then
			return `usage: /crowd {arg} [on|off] — {report()}`
		end
		if arg == "witness" then
			WitnessService.SetEnabled(value == "on")
		else
			DisguiseService.SetEnabled(value == "on")
		end
		return `{arg} {value} — {report()}`
	end

	if arg == "describe" then
		-- A sighting at the player's own feet, which is the one place in this codebase that
		-- is allowed to do that. Everywhere else handing the police the live position would
		-- delete the search -- see BountyService's header -- but the whole point here is to
		-- reach the described state without robbing anything first.
		local character = player.Character
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if root == nil then
			return "no body in the world"
		end
		BountyService.Sighted(player, (root :: BasePart).Position)
		return `described — {report()}`
	end

	if arg == "go" then
		local index = tonumber(args[2] or "")
		local spots = Hideouts.Spots
		if index == nil or index < 1 or index > #spots then
			local names = {}
			for order, spot in spots do
				table.insert(names, `{order}={spot.place}`)
			end
			return `usage: /crowd go <1-{#spots}> ({table.concat(names, ", ")})`
		end
		local place = spots[math.floor(index)].place
		if not PlaceService.Send(player, place) then
			return `hideout "{place}" has no place point in this world`
		end
		return `sent to {place} — {report()}`
	end

	return `usage: /crowd [go <n>|describe|witness on|off|disguise on|off] — {report()}`
end

-- The first five years, on one command.
--
-- The real path is "/die, then play", and unlike school and work that is genuinely quick
-- -- childhood is the opening five minutes and it is meant to be lived. This is for the
-- two things living it cannot tell you: why nothing appeared, and what a lure looks like
-- in a room you have not walked to yet.
--
--   /toddler                  what is on the floor, how far off it is, and if there is
--                             nothing, which of the four reasons it is. That last part is
--                             the whole command: an empty room has four causes and they
--                             are indistinguishable by standing in it.
--   /die then watch           the honest test. Something should be across the room within
--                             a few seconds of the new life starting, with a line to it.
--   /toddler next             the next thing now, wherever you are standing. The way to
--                             see how the placement behaves in a corridor, a corner or a
--                             doorway without dying repeatedly to get there.
--   crawl to it               it should open the way any event opens -- subject in the
--                             room, choices on the floor -- and answering should make you
--                             a year older and put the next one out about four seconds
--                             later. If it opens but nothing goes on the floor, that is
--                             the room being too tight and /enact will say so.
--   /toddler next in a closet nothing should be placed, and /toddler should say "nowhere
--                             in this room to put one" rather than failing silently. The
--                             one failure that otherwise looks exactly like a broken game.
--   /age 6                    the whole system should go dark and the line go out, mid
--                             crawl if necessary.
--   /toddler off              the toddler in an empty house, for telling a childhood bug
--                             apart from a body, places or enactment one.
Commands.toddler = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return ChildhoodService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		ChildhoodService.SetEnabled(arg == "on")
		return `childhood {arg} — {ChildhoodService.Describe(player)}`
	end

	if arg == "next" then
		if not ChildhoodService.ForceStage(player) then
			return `nothing placed — {ChildhoodService.Describe(player)}`
		end
		return `placed — {ChildhoodService.Describe(player)}`
	end

	return `usage: /toddler [next|on|off] — {ChildhoodService.Describe(player)}`
end

-- What this life has done, and what that has opened.
--
-- The command exists because flags are the one system in the game with no visible
-- surface of its own. A bond has a fan of pads that visibly widens; a flag looks like
-- nothing at all until an event that most lives never see turns up, and "an event that
-- did not turn up" is not something anybody can look at. So this is the surface.
--
--   /flags                    what you are carrying and the age you earned each one at.
--   /flags all                every flag that exists and what it means, which is the way
--                             to find the id to type into the next command.
--   /flags set dog_loved      the branch without the childhood. Then /age 7 and /event
--                             school_dog_again should be offerable; without the flag the
--                             same command should refuse it.
--   /flags set wandered_off   the people half. /age 8, walk up to Rae, and there should
--                             be one more pad in front of her than there was.
--   /flags clear dog_feared   proof the undo path works, which is what
--                             school_dog_still's third answer does the honest way.
--   /die                      flags are per life. Everything here should be empty in the
--                             next one, and the school branches gone with it.
Commands.flags = function(player: Player, args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end
	local data = Lives.Active(profile.Data)

	local arg = string.lower(args[1] or "")
	if arg == "all" then
		local lines: { string } = {}
		for _, def in Flags.All do
			table.insert(lines, `{def.id} — {def.meaning}`)
		end
		return table.concat(lines, "\n")
	end

	if arg == "set" or arg == "clear" then
		-- Not lowercased, for the same reason person ids are not: flag ids are matched
		-- exactly and only the switch words above are matched loosely.
		local flagId = args[2]
		if flagId == nil or Flags.ById[flagId] == nil then
			return `usage: /flags {arg} <id> — see /flags all`
		end
		if arg == "clear" then
			data.flags[flagId] = nil
		else
			data.flags[flagId] = data.ageMonths // Config.Time.MonthsPerYear
		end
		-- People are gated on flags, so the roster standing in the world was built
		-- against the old set and is wrong now. Rebuilt here rather than left to the
		-- next birthday, because the entire point of the command is to see the change.
		PeopleService.Rebuild(player)
		return `flags: {describeFlags(data)}`
	end

	if arg ~= "" then
		return "usage: /flags [all|set <id>|clear <id>]"
	end
	return `flags: {describeFlags(data)}`
end

-- Everything about the people in the world, on one command.
--
-- Same first check as school, and for the same reason: people stand at named places, so
-- with nothing in Studio tagged "home", "store" or "school" nobody is anywhere and bare
-- /people says which of them could not be found rather than leaving an empty street to
-- be puzzled over.
--
--   /people                   who should be in this life, whether they are standing in
--                             it, what they think of you, and how many offers that buys.
--                             The one command for "where is my mother".
--   /people bond mom 90       the top band without the childhood. Walk up afterwards and
--                             the fan should be wider, because offers are gated on bond.
--   /people bond neighbor 45  the office reference, which is the far end of this system:
--                             /age 18, then read the hiring sign upstairs. It should ask
--                             for 45 smarts instead of 60 and name Mr. Alderman.
--   /people bond mom 0        the other direction. Fewer pads, and the allowance on the
--                             next birthday should be the flat grant with no multiplier
--                             -- check it with /pocket.
--   /people clear             the once-a-year cap lifted, so the same conversation can be
--                             had twice without a birthday in between. Without this,
--                             walking back up gets the busy line.
--   /ageup with a bond set    decay. A person you did not visit should lose ground on the
--                             birthday; one you did should not.
--   /age 18 with Rae          the age window closing. She should be gone from the school
--                             the moment the birthday lands, without a rebuild by hand.
--   /people off               the street emptied, for telling a people bug apart from a
--                             places, body or NPC one.
Commands.people = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return PeopleService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		PeopleService.SetEnabled(arg == "on")
		return `people {arg} — {PeopleService.Describe(player)}`
	end

	if arg == "clear" then
		if not PeopleService.ClearVisits(player) then
			return `could not clear — {PeopleService.Describe(player)}`
		end
		return `visits cleared — {PeopleService.Describe(player)}`
	end

	if arg == "bond" then
		-- Not lowercased: person ids are matched exactly, the same way place and event
		-- ids are, and only the switch words above are matched loosely.
		local personId = args[2]
		local value = tonumber(args[3])
		if personId == nil or value == nil or not PeopleService.SetBond(player, personId, value) then
			local people = Config.People
			return `usage: /people bond <personId> <{people.MinBond}..{people.MaxBond}> — `
				.. PeopleService.Describe(player)
		end
		return PeopleService.Describe(player)
	end

	-- The pair this exists for, and neither is reachable by playing. "/people refuse
	-- always" then taking an ask shows the words somebody says when they turn you down;
	-- "never" shows the same row paying out. Without it, seeing both halves of a coin at
	-- one visit a year means burning in-game years to land on the side you wanted --
	-- and "/people clear" would hand back the visit but not the coin.
	if arg == "refuse" then
		local mode = string.lower(args[2] or "")
		if mode ~= "chance" and mode ~= "always" and mode ~= "never" then
			return `usage: /people refuse <chance|always|never> — {PeopleService.Describe(player)}`
		end
		PeopleService.SetRefusalMode(mode :: PeopleService.RefusalMode)
		return `refusals {mode} — {PeopleService.Describe(player)}`
	end

	return `usage: /people [bond <id> <n>|refuse <chance|always|never>|clear|on|off] — `
		.. PeopleService.Describe(player)
end

-- The town, which /people deliberately leaves out. Generated strangers who share every
-- system with the four and differ in exactly one way that matters here: they are only
-- given bodies while the player is near *them*, so "not standing there" is their ordinary
-- state rather than a fault. Everyone else is still somewhere -- walking, with no rig on
-- them -- which is why every row below carries a distance whether it has a body or not.
--
-- Which is the thing this command exists to make legible. Without it a street that is
-- meant to hold a dozen people and holds four looks identical to a broken generator, a
-- missing tag, and the rig ceiling doing exactly its job.
--
--   /town              how many are in this life at this age, how many wear a body
--                      against the ceiling, which places you are near and how far, and
--                      how many are old enough that their plate shows no age.
--   /town list         every row: name, archetype, place, shown age, bond, and distance.
--                      Nearest first, unbodied last.
--   /town near         only the ones standing in front of you, which is the reading to
--                      take while walking -- a row with a body is a row you can click.
--   walk away, /town   presence, the one part of this that runs by itself. The bodied
--                      count should fall as you leave the radius and climb again on the
--                      way back, with no command in between.
--   /town walk off     the town frozen where it stands. Everything else should behave
--                      exactly as it did before anybody could walk, which is how a
--                      walking bug is told apart from a bonding one. `on` again and
--                      they carry on without a rebuild.
--   /town list twice   the walk itself, and the half of it nobody can see. Every row
--                      ends in what that person is doing -- walking, resting, held, off,
--                      or "no body, N studs away, walking" for the ones with no rig --
--                      and running it twice a few seconds apart should show those
--                      changing and the distances moving on bodied and bodiless alike.
--                      A town where only the bodied rows move is a town whose ghosts
--                      have stopped being stepped.
--   /town routes       the roads. Zero tagged points is not a fault -- it means everyone
--                      is wandering to probed ground near their own place -- but two
--                      disconnected pieces is, and it looks exactly like people refusing
--                      to visit half the map.
--   walk up to one     the halt. They should stop, turn to square up to you, and stay
--                      turned while you walk around them; their row reads "held". Step
--                      away and they go back to "resting" and then walk off.
--   follow one, leave  the handoff, which is the one thing here that can only be seen by
--                      doing it. Walk somebody a long way from their place, back off
--                      until their row loses its body, then walk back: they should be
--                      near where you left them, not back at their building.
--   /town then /people the split. No id should be in both, and the four should never
--                      appear here.
--   /age 6, /town      the age windows. Classmates arrive with the school; before that
--                      those rows are simply absent, which is content and not a bug.
--   /people off        the town goes with it. It is one roster, so a town left standing
--                      would mean the presence pass is building people the service has
--                      been told not to have.
Commands.town = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return PeopleService.DescribeTown(player, "summary")
	end
	if arg == "list" then
		return PeopleService.DescribeTown(player, "all")
	end
	if arg == "near" then
		return PeopleService.DescribeTown(player, "bodied")
	end
	if arg == "routes" then
		return PeopleService.DescribeRoutes()
	end

	if arg == "walk" then
		local mode = string.lower(args[2] or "")
		if mode ~= "on" and mode ~= "off" then
			return `usage: /town walk <on|off> — {PeopleService.DescribeTown(player, "summary")}`
		end
		PeopleService.SetTownWalking(mode == "on")
		return `town walking {mode} — {PeopleService.DescribeTown(player, "summary")}`
	end

	return `usage: /town [list|near|routes|walk <on|off>] — {PeopleService.DescribeTown(player, "summary")}`
end

-- What the life is to the people in it, and the one thing about the people system that
-- has no number behind it to fall back on. A bond can be read off /people; a tie is
-- either there or it is not, and every way it can be wrong is silent -- a rung that never
-- appears, a rung that appeared twice, a capped rung spent by somebody who left.
--
--   /ties              everybody who is something, what they are, and whether each capped
--                      rung is full or open. "lapsed" means they hold a tie but are no
--                      longer in the life, which is the state that must NOT hold a slot.
--   /ties set <id> <tie>   makes it so without earning it, and deliberately ignores the
--                      cap -- producing two closest friends is the whole point, because
--                      that is the state the cap exists to prevent and the only way to
--                      see what it looks like if it ever slips through.
--   /ties clear <id>   takes one back off. The rung that gave it should reappear on that
--                      person's panel and the friend-only rows should vanish with it.
--
-- The walk-through worth doing once, on a classmate:
--
--   /age 12, /people bond <id> 15, click them   the "known" rung is on the panel and the
--                      "friend" one is not. Take it: their plate gains a second line.
--   click them again   the rung is gone from the list. It happened; it does not happen
--                      twice, and a row offering to introduce yourself to a friend would
--                      read as a bug rather than a rule.
--   bond to 40, /reevents, take the friend rung, then look at the panel   the friend-only
--                      row is there now and was not before.
--   bond to 75, take the closest rung, then walk to another classmate at the same bond
--                      their closest rung is absent. That is the cap, and /ties shows it
--                      as "closest full".
--   /age 18            the classmate ages out. /ties shows them "lapsed" and "closest
--                      open" again -- losing touch after school reopens the slot without
--                      ever unsaying what they were to you.
Commands.ties = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return PeopleService.DescribeTies(player)
	end

	if arg == "set" or arg == "clear" then
		local personId = args[2]
		if personId == nil then
			return `usage: /ties {arg} <personId>{if arg == "set" then " <tieId>" else ""}`
		end
		-- Nil is the clear, which is why this is one branch rather than two: the service
		-- takes a tie or the absence of one, and a "clear" that went through a different
		-- path would be a second way to write the same field.
		local tieId = if arg == "set" then args[3] else nil
		if arg == "set" and tieId == nil then
			return "usage: /ties set <personId> <tieId>"
		end
		if not PeopleService.SetTie(player, personId, tieId) then
			return `no person "{personId}" or no tie "{tieId or ""}" — {PeopleService.DescribeTies(player)}`
		end
		return PeopleService.DescribeTies(player)
	end

	return `usage: /ties [set <personId> <tieId>|clear <personId>] — {PeopleService.DescribeTies(player)}`
end

-- Approach-rate debug. Shows seconds-since-last-NPC-approach and the rolling average of
-- the last twenty intervals, so the quota ("at least one NPC-initiated interaction per
-- 60 seconds of walking") is visible rather than assumed.
--
--   /approach              prints the current rate; empty when there is not yet enough data.
Commands.approach = function(player: Player, _args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end
	local result = PeopleService.DescribeApproaches(player)
	if result == nil then
		return "approaches | no data yet — walk up to an NPC and wait a moment"
	end
	return result
end

-- Every interactable in the world, nearest first, and why the near ones are or are not
-- usable. The command for "I walked up to her and clicking did nothing".
--
-- Reads four things, in the order they go wrong:
--   * whether a prompt exists on that thing at all -- nothing attached is a spawn bug,
--     not an interaction one, and it is by far the most common answer;
--   * whether it carries a kind and an id, because a prompt without them is a thing the
--     player can click that the client will refuse to route;
--   * whether it is Enabled, which is how somebody who has already given you their time
--     this year is turned off without their name going dark;
--   * how far away it is against its own reach, since the dots are readable from two and
--     a half times the distance they are usable from, and the gap between those two
--     numbers is where "it isn't working" usually lives;
--   * whether the *name* is up, and from how far, which is a different range again and
--     deliberately the shortest of the three -- see Config.Interact.NameRangeMultiplier.
--
-- What it cannot see: whether the client actually connected the button. That connection
-- is made in client/world/Prompts.luau and marked with an attribute set on the client,
-- and a client-set attribute does not come back across. If everything below reads fine
-- and clicking still does nothing, the Output window is the place to look -- that path
-- warns rather than failing quietly.
Commands.dots = function(player: Player, _args: { string }): string
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local from = if root ~= nil and root:IsA("BasePart") then root.Position else nil

	type Row = { distance: number, text: string }
	local rows: { Row } = {}
	local reachable = 0

	for _, instance in Workspace:GetDescendants() do
		if instance.Name ~= Interact.PromptName or not instance:IsA("ProximityPrompt") then
			continue
		end
		local prompt = instance :: ProximityPrompt
		local adornee = prompt.Parent

		local distance = math.huge
		if from ~= nil and adornee ~= nil and adornee:IsA("BasePart") then
			distance = (from - adornee.Position).Magnitude
		end

		local kind = prompt:GetAttribute(Interact.KindAttribute)
		local id = prompt:GetAttribute(Interact.IdAttribute)
		local named = if type(kind) == "string" and type(id) == "string"
			then `{kind} "{id}"`
			else "NO KIND OR ID"

		local dots = if adornee ~= nil then adornee:FindFirstChild(Interact.DotsName) else nil
		local within = distance <= prompt.MaxActivationDistance
		if within and prompt.Enabled and dots ~= nil then
			reachable += 1
		end

		local why: { string } = {}
		if not prompt.Enabled then
			table.insert(why, "DISABLED")
		end
		if dots == nil then
			table.insert(why, "NO DOTS")
		end
		if not within then
			table.insert(why, `out of reach ({math.round(prompt.MaxActivationDistance)})`)
		end
		-- Kept out of `why`, which is a list of *faults*. Whether a name is up is a separate
		-- axis from whether the dots work -- that is the entire reason they are two
		-- billboards -- and folding it in would make a perfectly good row read as a problem.
		--
		-- Read off the billboard rather than recomputed from Config, because "that name is
		-- showing from too far away" is a question about what the gui was actually built
		-- with; a re-derivation here would agree with itself while disagreeing with the world.
		local plate = if adornee ~= nil then adornee:FindFirstChild(Interact.NameplateName) else nil
		local naming = if plate ~= nil and plate:IsA("BillboardGui") and plate.Enabled
			then (if distance <= plate.MaxDistance
				then ", name up"
				else `, name at {math.round(plate.MaxDistance)}`)
			else ""

		table.insert(rows, {
			distance = distance,
			text = `{named} at {if distance == math.huge then "?" else tostring(math.round(distance))} studs`
				.. (if #why > 0 then ` — {table.concat(why, ", ")}` else " — usable")
				.. naming,
		})
	end

	if #rows == 0 then
		return `nothing tagged "{Interact.PromptName}" is in the world — nobody has been spawned with dots`
	end

	table.sort(rows, function(a: Row, b: Row): boolean
		if a.distance == b.distance then
			return a.text < b.text
		end
		return a.distance < b.distance
	end)

	local texts: { string } = {}
	-- Capped because a busy street is a dozen rigs and the answer is always in the first
	-- few: the question this command answers is about the thing in front of the player.
	for index, row in rows do
		if index > DOTS_LISTED then
			break
		end
		table.insert(texts, row.text)
	end

	local head = `{#rows} interactables, {reachable} usable from here`
	if from == nil then
		head ..= " (no character, so every distance is unknown)"
	end
	if #rows > DOTS_LISTED then
		head ..= `, nearest {DOTS_LISTED} shown`
	end
	return `{head} | {table.concat(texts, " · ")}`
end

-- Clears the per-life seen list so the same content can be replayed without
-- dying first.
Commands.reevents = function(player: Player, _args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end
	EventService.ResetSeen(player)
	return "cleared seen events for this life"
end

Commands.life = function(player: Player, _args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end
	local data = Lives.Active(profile.Data)
	local country = SetupService.CountryOf(data)
	return string.format(
		"%s from %s (%s) | age=%d gender=%s stage=%s alive=%s money=%s banked=%.1fs lives=%d pending=%s",
		-- Falls back to the Roblox name, so a life that has not been set up yet reads as a
		-- player sitting in the menu rather than as a blank.
		SetupService.NameOf(data, player.Name),
		if country ~= nil then country.name else "nowhere yet",
		-- The gate itself, printed next to the name it gates: "begun=false" is the answer
		-- to every "why has nothing happened for a minute" this system can cause.
		if Lives.HasBegun(data) then "begun" else "in setup",
		data.ageMonths // Config.Time.MonthsPerYear,
		-- "unset" should be unreachable -- DataService fills it on load and again on
		-- rebirth -- so seeing it here is the symptom of one of those two not having run,
		-- which is worth being able to read rather than papering over with a default.
		data.gender or "unset",
		data.stage,
		tostring(data.alive),
		Money.Format(data.money),
		data.secondsSinceAgeUp,
		-- Off the profile, not the life: it counts the player's lives across every slot.
		profile.Data.livesLived,
		data.pendingEventId or "none"
	) .. ` delivering={data.deliveringEventId or "none"}`
end

-- Who this life is, and the way to give it somebody without leaving the place.
--
-- **`open` is gone, and its absence is the point of part 3.** It used to clear `setup` and
-- raise the character menu over the running town; there is no character menu here any more,
-- so clearing `setup` would now do nothing but strand the player in a world that will not
-- tick until they rejoin. Making a life is the lobby's job -- see `LobbySetupService`.
--
-- `skip` stays, and it matters more than it used to. In Studio there is no way to reach the
-- lobby at all, so this is the only thing that can put a life into the slot a test needs to
-- run in. It rolls a whole valid setup and starts it, by the same code path a real answer
-- takes.
Commands.setup = function(player: Player, args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end
	local data = Lives.Active(profile.Data)
	local action = string.lower(args[1] or "show")

	if action == "skip" or action == "restart" then
		-- `restart` discards whatever is in the active slot; `skip force` is the same thing
		-- spelled the other way, kept because the refusal below used to be the only hint and
		-- muscle memory reaches for the command it just failed.
		local force = action == "restart" or string.lower(args[2] or "") == "force"
		-- In Studio a developer typing `/setup skip` expects a fresh life, not a refusal
		-- about a slot occupied by a previous session. Auto-forcing here keeps the common
		-- path a one-command experience rather than a two-step puzzle.
		if not force and RunService:IsStudio() and Lives.HasBegun(data) then
			force = true
		end
		local rolled = SetupService.Skip(player, force)
		if rolled == nil then
			if force then
				-- Only reachable now with no profile: a forced skip resets the slot itself, so
				-- an occupied one is no longer a reason to refuse.
				return "nothing to restart -- no profile loaded yet"
			end
			return "slot " .. tostring(profile.Data.activeSlot)
				.. " already has a life in it -- /setup restart to discard it and start fresh, "
				.. "or /slots use <n> for an empty one then rejoin"
		end
		local verb = if action == "restart" or force then "restarted" else "skipped"
		return `{verb}: {rolled.firstName} {rolled.lastName} from {rolled.countryId}, era {rolled.eraId}`
	end

	if action == "show" then
		local setup = data.setup
		if setup == nil then
			return "in setup -- no life chosen yet, so the age clock is stopped"
		end
		local country = SetupService.CountryOf(data)
		return `{setup.firstName} {setup.lastName}, {if country ~= nil then country.name else setup.countryId}, `
			.. `era {setup.eraId}, gender {data.gender or "unset"}`
	end

	return "usage: /setup [show|skip|restart]"
end

-- The save slots, which are otherwise completely invisible from inside the game place --
-- there is no UI here that mentions them, because choosing one is the lobby's job.
--
-- `use` deliberately only moves the pointer and asks for a rejoin rather than swapping the
-- running life in place. Tearing down a life and standing up another one is real work --
-- body, world, people, HUD -- and it already has a home: the lobby, where no life is
-- running and there is nothing to tear down. A second half-version of it living in the
-- debug harness would be the exact duplicate-logic trap this codebase keeps avoiding, and
-- it would be the copy that silently rots.
--
-- `delete` refuses the active slot for the same reason: the life it would erase is the one
-- standing in the world right now, and every service is holding a reference to it.
Commands.slots = function(player: Player, args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end
	local data = profile.Data
	local action = string.lower(args[1] or "list")
	local index = tonumber(args[2])

	if action == "list" then
		local rows = {}
		for slot = 1, Config.Slots.Count do
			local life = data.slots[slot]
			local mark = if slot == data.activeSlot then ">" else " "
			if life == nil then
				-- Unreachable unless ensureSlots did not run. Worth reading as a fault
				-- rather than being quietly skipped over by the loop.
				table.insert(rows, `{mark} {slot}: MISSING -- ensureSlots did not fill this`)
			elseif not Lives.HasBegun(life) then
				table.insert(rows, `{mark} {slot}: empty`)
			else
				local country = SetupService.CountryOf(life)
				table.insert(
					rows,
					`{mark} {slot}: {SetupService.NameOf(life, player.Name)}, `
						.. `age {life.ageMonths // Config.Time.MonthsPerYear}, `
						.. `{if country ~= nil then country.name else "nowhere"}, `
						.. `{if life.alive then "alive" else "dead"}`
				)
			end
		end
		return `slot {data.activeSlot} of {Config.Slots.Count} active (schema {data.schema}, `
			.. `{data.livesLived} lives lived)\n`
			.. table.concat(rows, "\n")
	end

	if action == "use" then
		if index == nil then
			return `usage: /slots use <1-{Config.Slots.Count}>`
		end
		if index == data.activeSlot then
			return `already on slot {index}`
		end
		if not DataService.SetActiveSlot(player, index) then
			return `{index} is not a slot -- there are {Config.Slots.Count}`
		end
		return `active slot is now {index}. Rejoin to actually run it -- switching a life `
			.. "in place is the lobby's job, not this harness's."
	end

	if action == "delete" then
		if index == nil then
			return `usage: /slots delete <1-{Config.Slots.Count}>`
		end
		if index ~= math.floor(index) or index < 1 or index > Config.Slots.Count then
			return `{index} is not a slot -- there are {Config.Slots.Count}`
		end
		if index == data.activeSlot then
			return `refusing to delete slot {index}: it is the life you are standing in. `
				.. "Switch away first (/slots use <n>, rejoin), then delete it."
		end
		-- A fresh life rather than a nil hole, which is what "empty" means everywhere else
		-- and what keeps the list dense -- see the note on ProfileData.slots.
		data.slots[index] = Lives.New()
		return `slot {index} deleted -- it is an empty life again`
	end

	return "usage: /slots [list|use <n>|delete <n>]"
end

-- Back to the lobby.
--
-- No longer its own teleport. It used to be one, because it was the only route out of this
-- place and there was no menu to arrive at; now the death screen's button, the arrival check
-- and this command all go through `ReturnService.Send`, which is the one function that knows
-- how the handoff works -- retries, the in-flight stamp, and the two refusals worth reading.
-- A second copy here would be the copy that silently rots.
--
-- It does not end the profile session or touch `activeSlot`, and neither does ReturnService.
-- Leaving is what releases the session lock, and the lobby rewrites the slot the moment the
-- player picks one; doing either here would be this place reaching into a handoff it is on
-- the receiving end of.
--
-- Refusals arrive on the client as a line on the death screen, which is no use at all when
-- this was typed into the chat bar by somebody who is alive -- so the two that can be known
-- synchronously are answered here, in the console, where the command was given.
Commands.lobby = function(player: Player, _args: { string }): string
	if RunService:IsStudio() then
		return "teleports do not work in Studio -- publish both places to test the trip back"
	end
	if Config.Lobby.LobbyPlaceId == 0 then
		return "Config.Lobby.LobbyPlaceId is not set -- publish the lobby and put its id there"
	end
	ReturnService.Send(player)
	return "teleporting to the lobby"
end

-- Reads back what the age ladder actually did to the character, so a band that
-- failed to apply (an R6 rig, a missing Humanoid) is visible without guessing
-- from how the character feels to walk around.
Commands.band = function(player: Player, _args: { string }): string
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no profile loaded yet"
	end

	local ageYears = Lives.Active(profile.Data).ageMonths // Config.Time.MonthsPerYear
	local band = BodyService.BandForAge(ageYears)

	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid == nil then
		return string.format("age=%d band=%s (no character spawned)", ageYears, band.id)
	end

	local height = humanoid:FindFirstChild("BodyHeightScale")
	local headValue = humanoid:FindFirstChild("HeadScale")
	-- Size comes off the growth curve rather than the band now, so the wanted
	-- figure has to be read from the same place the body was -- printing the band's
	-- idea of it would answer a question nothing asks any more.
	local wantBody, wantHead = Config.Growth.At(ageYears)
	local body = string.format(
		"age=%d band=%s | want speed=%.1f jump=%.1f body=%.2f head=%.2f | live speed=%.1f jump=%.1f body=%s head=%s",
		ageYears,
		band.id,
		band.walkSpeed,
		band.jumpPower,
		wantBody,
		wantHead,
		humanoid.WalkSpeed,
		humanoid.JumpPower,
		if height ~= nil and height:IsA("NumberValue") then string.format("%.2f", height.Value) else "n/a (R6 rig?)",
		if headValue ~= nil and headValue:IsA("NumberValue") then string.format("%.2f", headValue.Value) else "n/a"
	)

	-- Reported next to the numbers rather than under its own command, because
	-- "why does my toddler look wrong" is one question and the speed and the
	-- animation are two halves of the answer.
	local animate = if character ~= nil then character:FindFirstChild("Animate") else nil
	local live = "no Animate script"
	if animate ~= nil then
		local walk = animate:FindFirstChild("walk")
		local track = if walk ~= nil then walk:FindFirstChildOfClass("Animation") else nil
		live = if track ~= nil then `walk={track.AnimationId}` else "no walk slot"
	end
	return `{body}\nanims: {BodyService.DescribeAnimations(band.id)} | live {live}`
end

-- Monthly bills: show debt, next bill amount, and payment status.
--   /bill                     show current bill state
--   /bill charge              force charge the next bill immediately
Commands.bill = function(player: Player, args: { string }): string
	if BillService.GetState(player) == nil then
		return "no active life"
	end

	local arg = string.lower(args[1] or "")
	if arg == "charge" then
		BillService.Charge(player)
		local state = BillService.GetState(player)
		return `bill charged — {state.debt > 0 and "debt {Money.Format(state.debt)}" or "no debt"}, next bill {Money.Format(state.totalThisMonth)} credits`
	end

	local state = BillService.GetState(player)
	if state == nil then
		return "no active life"
	end
	return `bill: debt {Money.Format(state.debt)}, next {Money.Format(state.totalThisMonth)}/mo, {state.paid and "paid" or "unpaid"} this cycle`
end

-- Milestones: show achieved milestones and trigger new ones.
--   /milestone                show all milestones
--   /milestone <id>           force trigger a specific milestone
--   /milestone reset          clear all milestones for this life
Commands.milestone = function(player: Player, args: { string }): string
	local life = Lives.Active(DataService.GetProfile(player) :: any)
	if life == nil then
		return "no active life"
	end

	local arg = string.lower(args[1] or "")
	if arg == "reset" then
		life.milestones = {}
		return "milestones cleared"
	end

	if arg ~= "" then
		MilestoneService.OnShiftComplete(player, life.bills.shiftsCompleted or 0)
		return "milestone check fired"
	end

	local achieved: { string } = {}
	for id, _ in life.milestones do
		table.insert(achieved, id)
	end
	if #achieved == 0 then
		return "no milestones achieved yet"
	end
	table.sort(achieved)
	return `milestones: {table.concat(achieved, ", ")}`
end

-- Gossip: show recent notable actions and fire a gossip check.
--   /gossip                   show current gossip notes
--   /gossip note <action> <effect>  add a notable action
--   /gossip tick              force a gossip tick
Commands.gossip = function(player: Player, args: { string }): string
	local arg = string.lower(args[1] or "")
	if arg == "tick" then
		GossipService.Tick(player)
		return "gossip tick fired"
	end

	if arg == "note" then
		local action = args[2] or "unknown action"
		local effect = args[3] or "notable"
		GossipService.Note(player, action, effect)
		return `noted: {action} — {effect}`
	end

	-- Describe current state from internal GossipState
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no active life"
	end
	-- Notes are per-session state; describe from recent service activity
	return "gossip: check /gossip note to add, /gossip tick to fire"
end

-- Houses: show owned houses, home jobs, and available options.
--   /house                    show house state
--   /house buy <houseId>      buy a suburb house
--   /house sell <houseId>     sell an owned house
--   /house job <houseId> <jobId>  link a home job to a house
Commands.house = function(player: Player, args: { string }): string
	local life = Lives.Active(DataService.GetProfile(player) :: any)
	if life == nil then
		return "no active life"
	end

	local houses = life.houses :: { owned: { [string]: boolean }, homeJob: { [string]: string } }
	local arg = string.lower(args[1] or "")

	if arg == "buy" then
		local houseId = args[2]
		if houseId == nil then
			return "usage: /house buy <houseId>"
		end
		local ok, result = HouseService.BuyHouse(player, houseId)
		return ok and `bought {houseId}` or `could not buy: {result}`
	end

	if arg == "sell" then
		local houseId = args[2]
		if houseId == nil then
			return "usage: /house sell <houseId>"
		end
		local ok, result = HouseService.SellHouse(player, houseId)
		return ok and `sold {houseId} for {result} credits` or `could not sell: {result}`
	end

	if arg == "job" then
		local houseId = args[2]
		local jobId = args[3]
		if houseId == nil or jobId == nil then
			return "usage: /house job <houseId> <jobId>"
		end
		local ok, result = HouseService.SetHomeJob(player, houseId, jobId)
		return ok and `linked {jobId} to {houseId}` or `could not link: {result}`
	end

	local owned: { string } = {}
	for houseId, _ in houses.owned do
		local jobId = houses.homeJob[houseId]
		table.insert(owned, jobId ~= nil and `{houseId} ({jobId})` or houseId)
	end
	if #owned == 0 then
		return "no houses owned"
	end
	table.sort(owned)
	return `houses: {table.concat(owned, ", ")}`
end

-- The showroom and the garage: buy, sell, bring one out, or put it away.
--   /car                      show the garage and what is out
--   /car list                 every car on the lot, price and rating
--   /car buy <id>             buy a car outright
--   /car sell <id>            sell one already owned
--   /car spawn <id>           bring an owned car out of the garage
--   /car store                put the active car away
Commands.car = function(player: Player, args: { string }): string
	local arg = string.lower(args[1] or "")

	if arg == "list" then
		local rows: { string } = {}
		for _, kind in Vehicles.All do
			table.insert(
				rows,
				string.format(
					"%s: %s (top %d, accel %d, steer %d)",
					kind.id,
					Money.Format(kind.price),
					kind.topSpeedStuds,
					kind.acceleration,
					kind.steerDegrees
				)
			)
		end
		return table.concat(rows, "\n")
	end

	if arg == "buy" then
		local vehicleId = args[2]
		if vehicleId == nil then
			return "usage: /car buy <vehicleId>"
		end
		local ok = VehicleService.Buy(player, vehicleId)
		return ok and `bought {vehicleId}` or `could not buy {vehicleId} -- see the notice on screen`
	end

	if arg == "sell" then
		local vehicleId = args[2]
		if vehicleId == nil then
			return "usage: /car sell <vehicleId>"
		end
		local ok = VehicleService.Sell(player, vehicleId)
		return ok and `sold {vehicleId}` or `could not sell {vehicleId} -- see the notice on screen`
	end

	if arg == "spawn" then
		local vehicleId = args[2]
		if vehicleId == nil then
			return "usage: /car spawn <vehicleId>"
		end
		local ok = VehicleService.Spawn(player, vehicleId)
		return ok and `{vehicleId} is out front` or `could not spawn {vehicleId} -- see the notice on screen`
	end

	if arg == "store" then
		local ok = VehicleService.Store(player)
		return ok and "parked" or "nothing was out"
	end

	return VehicleService.Describe(player)
end

-- Car dealership: show queue state and serve a customer.
--   /dealer                   show current queue state
--   /dealer serve             serve the front customer
Commands.dealer = function(player: Player, args: { string }): string
	local arg = string.lower(args[1] or "")
	if arg == "serve" then
		-- The queue is driven by distance to the counter; we cannot force-serve
		-- from the console without a world position, so we report state only.
		return "serve requires proximity to the dealership counter — walk there or use /dealer to check state"
	end

	-- Describe current dealer state
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return "no active life"
	end
	local place = PlaceService.Find("auto_dealer")
	if place == nil then
		return "auto_dealer not loaded"
	end
	return `dealer at {place.name}; walk to the counter to serve`
end

local HELP_TEXT = "commands: /ageup [n], /age <years>, /die, /stat <name> <value>, /idle <seconds>, /life, /band, "
	.. "/event <id>, /anchor <id>, /events, /reevents, /deliver <id>, /deliveries, /ambient <on|off>, "
	.. "/enact [id|on|off], /props [id|on|off|clear], /scene [on|off], /money [n|+n|-n], "
	.. "/pocket [send|pay|owe <n>], "
	.. "/places, /zones, /go <place>, /job [start|end|quit|task [id]|fail|skip <n>|moment|hours <n>|standing <jobId> <n>], "
	.. "/school [start|end|card|year <n>|mastery <subject> <n>|interact], /lab [start|end|level <n>|refill|on|off], "
	.. "/geo [start|find|end|level <n>|on|off], "
	.. "/art [start|sign|end|shift|refill|level <n>|on|off], /gym [start|end|on|off], "
	.. "/nerve [go [id]|stood|backed|over|end|set <n>|homework [on|off]|list|on|off], "
	.. "/read [start|solve|end|on|off], /music [start|auto [grade]|end|on|off], "
	.. "/pe [start|end|perfect|good|poor|on|off], /prom [on|off], "
	.. "/stadium [on|off], /gate [on|off|play|reset], "
	.. "/fight [<style>|rival|win|lose|end|on|off], "
	.. "/bounty [<n>|clear|arrest|on|off], /police [clear|on|off], /spot [heat <n>|colors on|off], "
	.. "/theft [go <place>|fill|on|off|crew <id>], "
	.. "/bank [go [<place>]|reset|on|off|crew <id>], "
	.. "/gang [go <id>|join <id>|credit <n>|colors [on|off]|crew [add|drop <id>]|reset|on|off], "
	.. "/skill [<id> <n|max>], "
	.. "/code [<string>|clear], "
	.. "/setting [<id> on|off], "
	.. "/crowd [go <n>|describe|witness on|off|disguise on|off], "
	.. "/people [bond <id> <n>|clear|on|off], /town [list|near|walk <on|off>], "
	.. "/ties [set <id> <tie>|clear <id>], /approach, /dots, /slots [list|use <n>|delete <n>], "
	.. "/toddler [next|on|off], /flags [all|set <id>|clear <id>], /setup [show|skip|restart], /lobby, "
	.. "/bill [charge], /milestone [reset], /gossip [note <action> <effect>|tick], "
	.. "/house [buy <id>|sell <id>|job <houseId> <jobId>], /dealer [serve], "
	.. "/verdict [name] — show or force a ribbon, /moments — print every moment, "
	.. "/reel — print moments since last chapter break, "
	.. "/car [list|buy <id>|sell <id>|spawn <id>|store]"

-- Dressing the gymnasium for a night, and taking it down again.
--
--   /prom                     what is on, if anything.
--   /prom on                  the gym dressed for prom: dance floor, stage and throne,
--                             balloon arch, streamers, coloured floor wash, chairs.
--                             Walk into the gym to see it -- the layer is laid over the
--                             room rather than replacing it, so the hoops and the wall
--                             bars are still there behind the decorations.
--   /prom off                 taken down. The gym should be exactly a gym again, which
--                             is the half worth checking: a layer that cannot be removed
--                             is the easy thing to get wrong.
--
-- Refuses before the building exists rather than silently doing nothing, because "I typed
-- /prom on and nothing happened" is otherwise indistinguishable from a broken layer.
Commands.prom = function(_player: Player, args: { string }): string
	local arg = string.lower(args[1] or "")

	if arg == "" then
		local current = School.Event()
		if current == nil then
			return "nothing on in the gym — /prom on to dress it"
		end
		return `the gym is dressed for {current} — /prom off to take it down`
	end

	if arg ~= "on" and arg ~= "off" then
		return "/prom, /prom on, or /prom off"
	end

	if arg == "off" then
		local changed = School.SetEvent(nil)
		return if changed then "prom taken down — the gym is a gym again" else "nothing was on"
	end

	if School.Plan() == nil then
		return "no school building yet, so no gym to dress — walk to the school first"
	end

	local changed = School.SetEvent("prom")
	return if changed then "the gym is dressed for prom — walk in and look" else "prom was already on"
end

-- PE, the graded sports drill -- the one subject that pays health into athletics rather
-- than smarts into academics.
--
--   /pe                       whether the field was found, your mastery level and fitness,
--                             the pass mark those two produce, and the drill if one is on.
--   /pe start                 a drill where you stand, without waiting for the timetable.
--                             The meter is three clicks: start, power, place.
--   /pe end                   the whistle, grading what was actually done.
--   /pe perfect | good | poor plays the drill out to that grade, for seeing the report card
--                             and the mastery rung without six clean clicks. The kind way to
--                             check the numbers, since the third click is the hard one.
--   /pe off                   the system dark, for telling a PE bug apart from a school one.
--
-- Worth watching once with `/stats` open: the reward lands in **health**, and nowhere else in
-- the school tree does that.
Commands.pe = function(player: Player, args: { string }): string
	if DataService.GetProfile(player) == nil then
		return "no profile loaded yet"
	end

	local arg = string.lower(args[1] or "")
	if arg == "" then
		return PEService.Describe(player)
	end

	if arg == "on" or arg == "off" then
		PEService.SetEnabled(arg == "on")
		return `PE {arg} — {PEService.Describe(player)}`
	end

	if arg == "start" then
		local started, refusal = PEService.ForceStart(player)
		if not started then
			return `could not start a drill: {refusal or "no reason given"}`
		end
		return PEService.Describe(player)
	end

	if arg == "end" then
		if not PEService.ForceEnd(player) then
			return "no drill running"
		end
		return PEService.Describe(player)
	end

	if arg == "perfect" or arg == "good" or arg == "poor" then
		local ok, refusal = PEService.Autoplay(player, arg)
		if not ok then
			return refusal or "could not play it out"
		end
		return PEService.Describe(player)
	end

	return "/pe, /pe start, /pe end, /pe perfect|good|poor, /pe on|off"
end

Commands.help = function(_player: Player, _args: { string }): string
	return HELP_TEXT
end

local function stripPrefix(message: string): string?
	for _, prefix in PREFIXES do
		if string.sub(message, 1, #prefix) == prefix then
			return string.sub(message, #prefix + 1)
		end
	end
	return nil
end

local NoticeRemote = Remotes.Get("Notice")

local function onChatted(player: Player, message: string)
	local body = stripPrefix(message)
	if body == nil then
		return
	end

	local parts = string.split(body, " ")
	local name = string.lower(table.remove(parts, 1) or "")
	local handler = Commands[name]
	if handler == nil then
		-- Not one of ours (could be a built-in like /e). Stay silent.
		return
	end

	local ok, result = pcall(handler, player, parts)
	if ok then
		print(`[AGES debug] {player.Name}: {result}`)
		-- Show the result in-game so the developer does not have to watch the
		-- Output window to see what a command did or why it refused.
		if result ~= nil and result ~= "" then
			NoticeRemote:FireClient(player, result)
		end
	else
		warn(`[AGES debug] /{name} failed: {result}`)
		NoticeRemote:FireClient(player, `/{name} error: {result}`)
	end
end

local DebugService = {}

function DebugService:Init() end

function DebugService:Start()
	if not RunService:IsStudio() then
		return
	end

	local function watch(player: Player)
		player.Chatted:Connect(function(message: string)
			onChatted(player, message)
		end)
	end

	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	print(`[AGES debug] Studio commands active — {HELP_TEXT}`)
end

return DebugService
