--!strict
-- The things in the school you can press E on.
--
-- Vending machines, the coffee machine, water fountains and the front doors. The building was
-- full of objects that looked like they did something and did nothing, which is a specific
-- kind of bad: a prop that invites a keypress and refuses it teaches the player that nothing
-- in this building is real, and they stop trying doors everywhere.
--
-- **Found by name, not by tag, and that is forced rather than chosen.** `Config.School.Building.Baked`
-- is true: the school is laid at runtime only to work out where its rooms are, and those parts
-- are destroyed without ever reaching the world. What the player actually walks around is the
-- baked `assets/School.rbxmx` mounted at `Workspace.School`. So tagging at build time -- which
-- is what GymService does and what I would otherwise copy -- would put tags on parts that are
-- thrown away a frame later. Names survive the bake; tags do not.
--
-- The cost of that is a name prefix being load-bearing. `PATTERNS` below is the whole contract
-- between this file and `world/School.luau`, and renaming a machine there silently unhooks it
-- here. It is written down in both places for that reason.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Interact = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Interact"))

local DataService = require(script.Parent.DataService)
local StatService = require(script.Parent.StatService)
local MoneyService = require(script.Parent.MoneyService)

local FixtureService = {}

local FIX = Config.Fixtures
local NoticeRemote = Remotes.Get("Notice")
local RequestUseFixtureRemote = Remotes.Get("RequestUseFixture")

-- Which part names are which kind of fixture, most specific first.
--
-- Order matters: "CorridorVendingCoffeeBody" contains "Vending", so the coffee test has to run
-- before any general vending test would. Keeping the list ordered rather than adding negative
-- lookaheads is the readable version of the same rule.
local PATTERNS: { { needle: string, kind: string } } = {
	{ needle = "CoffeeBody", kind = "coffee" },
	{ needle = "SnacksBody", kind = "snack" },
	-- The basin, not the back panel or the spout: the prompt should sit on the thing you lean
	-- over. `Fountain{floor}_{index}` is the basin's own name and the others all carry a
	-- suffix, so an exact-prefix test would be wrong -- this matches the body specifically.
	{ needle = "FountainBasin", kind = "fountain" },
	{ needle = "EntranceDoorLeaf", kind = "door" },
	-- Every room door, named `{roomId}DoorLeaf` in world/School.luau. This is the other half of
	-- the naming contract in the header: rename it there and every classroom in the school
	-- silently stops opening.
	{ needle = "DoorLeaf", kind = "door" },
}

local function kindOf(name: string): string?
	for _, entry in PATTERNS do
		if string.find(name, entry.needle, 1, true) ~= nil then
			return entry.kind
		end
	end
	return nil
end

-- Per player, per kind: when they may use one again. Session-local on purpose -- see the
-- Config header. These exist to stop somebody standing at a machine holding E, not to be an
-- economy worth persisting.
local nextUse: { [Player]: { [string]: number } } = {}

local attached: { [BasePart]: true } = {}

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	return character:GetPivot().Position
end

local function notice(player: Player, text: string)
	if text ~= "" then
		NoticeRemote:FireClient(player, text)
	end
end

-- Swings both leaves, or shuts them.
--
-- Tweened rather than set, because a door that teleports open is a door that looks broken.
--
-- **State is per door, not global.** There used to be one `doorsOpen` flag for the whole
-- building, which was defensible when the only doors were the two entrance leaves -- they are
-- one opening and a pair that could disagree about being open is a bug. It stopped being
-- defensible the moment every classroom got a door: pressing E at the science lab swung all
-- twelve doors in the school, including the ones on the floor above.
--
-- The entrance keeps the paired behaviour by being asked for as a group. Everything else is
-- keyed on the leaf itself.
local doorOpen: { [BasePart]: boolean } = {}
local doorRest: { [BasePart]: CFrame } = {}

-- Which edge a leaf is hinged on, and therefore which way it swings.
--
-- The entrance is a pair either side of the building centreline, so the sign of the leaf's own
-- X is which hand it is and the two open outward like gates. A room door is a single leaf and
-- the rule is different and more important: **it swings into its room, never into the
-- corridor.** A door that opens into circulation is one people get pinned by, which was the
-- original reason these were left as holes in the wall.
local function handOf(part: BasePart, rest: CFrame): number
	if string.find(part.Name, "EntranceDoorLeaf", 1, true) ~= nil then
		return if rest.Position.X >= 0 then -1 else 1
	end
	return 1
end

local function swingOne(part: BasePart, open: boolean)
	local rest = doorRest[part]
	if rest == nil then
		rest = part.CFrame
		doorRest[part] = rest
	end
	local hand = handOf(part, rest)
	local hinge = rest * CFrame.new(hand * part.Size.X / 2, 0, 0)
	local target = if open
		then hinge * CFrame.Angles(0, math.rad(hand * -FIX.DoorSwingDegrees), 0) * CFrame.new(-hand * part.Size.X / 2, 0, 0)
		else rest
	doorOpen[part] = open
	TweenService:Create(part, TweenInfo.new(FIX.DoorSwingSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target }):Play()
end

-- Swings the door the player is actually standing at. The entrance is the one exception: both
-- of its leaves move together, because it is one opening.
local function swingDoors(part: BasePart?)
	if part == nil then
		return
	end
	local leaf = part :: BasePart
	local open = not (doorOpen[leaf] == true)

	if string.find(leaf.Name, "EntranceDoorLeaf", 1, true) ~= nil then
		for other in attached do
			if other.Parent ~= nil and string.find(other.Name, "EntranceDoorLeaf", 1, true) ~= nil then
				swingOne(other, open)
			end
		end
		return
	end
	swingOne(leaf, open)
end

-- Uses a fixture. The id is the kind; the part is found by proximity rather than trusted from
-- the client, which is the same rule every other interact in this game follows.
local function use(player: Player, kind: string)
	local spec = FIX.Kinds[kind]
	if spec == nil then
		return
	end

	local position = characterPosition(player)
	if position == nil then
		return
	end

	-- Standing near one of this kind. The client says which kind it clicked; the server checks
	-- there is actually one of those within reach, so a forged message buys nothing.
	-- Keeps the closest rather than the first: with a door on every room, "one of this kind is
	-- within reach" is no longer the same question as "which one did they mean".
	local nearest: BasePart? = nil
	local nearestDistance = math.huge
	for part in attached do
		if part.Parent ~= nil and kindOf(part.Name) == kind then
			local distance = (part.Position - position).Magnitude
			if distance <= FIX.ReachStuds and distance < nearestDistance then
				nearest = part
				nearestDistance = distance
			end
		end
	end
	if nearest == nil then
		-- Said out loud. Every silent `return` in this function presents to the player as a
		-- prompt that does nothing, which is indistinguishable from a bug in the fixture.
		warn(`[AGES] {player.Name} pressed a "{kind}" prompt with nothing of that kind inside {FIX.ReachStuds} studs`)
		return
	end

	-- **Doors are answered here, before any of the checks below.**
	--
	-- The prompt was appearing and the keypress was doing nothing, and the reason is that a
	-- door was being made to walk the whole fixture gauntlet -- profile loaded, cooldown, money
	-- -- before it was allowed to swing. Two of those paths `return` without saying anything,
	-- so any one of them failing looked identical to the door being broken.
	--
	-- A door is not an economy interaction. It has no cost, no cooldown and no stat, and the
	-- reward for opening it is that it is open. It should not be able to fail because a profile
	-- has not finished loading.
	if kind == "door" then
		swingDoors(nearest)
		return
	end

	local now = os.clock()
	local mine = nextUse[player]
	if mine == nil then
		mine = {}
		nextUse[player] = mine
	end
	local ready = mine[kind]
	if ready ~= nil and now < ready then
		notice(player, FIX.TooSoon)
		return
	end

	if DataService.GetProfile(player) == nil then
		warn(`[AGES] {player.Name} used a "{kind}" with no profile loaded -- refused`)
		return
	end

	if spec.cost > 0 then
		-- Spend before the effect, and bail if it fails. The other order would hand out the
		-- happiness and then discover there was no money, which is the shape of every
		-- duplication bug ever written.
		if not MoneyService.Spend(player, spec.cost, `fixture:{kind}`) then
			notice(player, spec.broke)
			return
		end
	end

	if spec.happiness ~= 0 then
		StatService.AddStat(player, "happiness", spec.happiness)
	end
	if spec.health ~= 0 then
		StatService.AddStat(player, "health", spec.health)
	end

	mine[kind] = now + spec.cooldownSeconds
	notice(player, spec.notice)
end

-- Hangs a prompt on one part.
local function attach(part: BasePart)
	if attached[part] then
		return
	end
	local kind = kindOf(part.Name)
	if kind == nil then
		return
	end
	local spec = FIX.Kinds[kind]
	if spec == nil then
		return
	end
	local handle = Interact.Attach(part, {
		kind = "Fixture",
		id = kind,
		actionText = spec.action,
		objectText = spec.label,
	})
	if handle == nil then
		return
	end
	handle.prompt.MaxActivationDistance = FIX.PromptDistanceStuds
	attached[part] = true
end

-- Walks the school for anything that should have a prompt on it.
--
-- Run once at start and again whenever the model arrives, because the baked asset is mounted
-- by the project file and may not exist on the first tick of a fresh server.
local function sweep()
	local school = workspace:FindFirstChild("School")
	if school == nil then
		return false
	end
	for _, descendant in school:GetDescendants() do
		if descendant:IsA("BasePart") then
			attach(descendant)
		end
	end
	return true
end

function FixtureService.Describe(): string
	local counts: { [string]: number } = {}
	for part in attached do
		local kind = kindOf(part.Name)
		if kind ~= nil then
			counts[kind] = (counts[kind] or 0) + 1
		end
	end
	local parts = {}
	for kind, count in counts do
		table.insert(parts, `{kind}={count}`)
	end
	table.sort(parts)
	if #parts == 0 then
		return "fixtures: none found"
	end
	return "fixtures: " .. table.concat(parts, "  ")
end

function FixtureService:Start()
	if not sweep() then
		-- The school has not streamed in. Retried rather than given up on, for the reason
		-- every other builder in this codebase retries: an asset that arrives late would
		-- otherwise be an asset nobody can ever interact with.
		task.spawn(function()
			for _ = 1, 30 do
				task.wait(2)
				if sweep() then
					return
				end
			end
			warn("[AGES] no School model found -- nothing in the school is interactable")
		end)
	end

	RequestUseFixtureRemote.OnServerEvent:Connect(function(player: Player, kind: unknown)
		if typeof(kind) ~= "string" then
			return
		end
		local ok, err = pcall(use, player, kind)
		if not ok then
			warn(`[AGES] fixture use failed for {player.Name}: {err}`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		nextUse[player] = nil
	end)
end

return FixtureService
