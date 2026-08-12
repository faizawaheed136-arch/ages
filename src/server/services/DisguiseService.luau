--!strict
-- Changing your clothes, which is the one thing a wanted player can do about being wanted.
--
-- Everything else in this system happens *to* you. Heat climbs, officers arrive, the town
-- turns to look. This is the answer, and it is deliberately powerful: it does not reduce the
-- heat by a point. It deletes what the police know. Officers converging on a corner become
-- officers searching a place you are not, the crowd stops recognising you, and the whole
-- apparatus keeps running against a description nobody has any more.
--
-- What it costs is the only currency a chase has, which is time spent not running. You have
-- to be on one of four marks -- see content/Hideouts -- standing still, unwatched, for five
-- seconds, while the search ring drifts toward you. Getting there is the traversal the
-- activity needed; standing there is the commit; stepping off is the undo. Being seen
-- part-way through does not fail you, it just stops the count where it is, which is the soft
-- failure this project asks of everything.
--
-- Nothing is clicked. There is no panel, no remote and no client half at all -- the mark
-- counts when you stand on it and the sign above it says what is happening. That is not
-- minimalism, it is the same signposting argument the shop camera makes: during these five
-- seconds the player is looking at the spot they are standing on and the street beyond it,
-- and a HUD panel would be off to the side of the only thing on screen that matters.
--
-- Split from BountyService, which owns what the police believe, and from WitnessService,
-- which owns the crowd that reads it. This file owns the verb and nothing else.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Money = require(ReplicatedStorage:WaitForChild("Money"))

local BountyService = require(script.Parent.BountyService)
local MoneyService = require(script.Parent.MoneyService)
local PlaceService = require(script.Parent.PlaceService)

local Hideouts = require(script.Parent.Parent.content.Hideouts)
local Wardrobe = require(script.Parent.Parent.world.Wardrobe)

local DisguiseService = {}

local DISGUISE = Config.Crime.Disguise

-- One player, part-way through changing.
type Change = {
	place: string,
	-- Seconds banked so far. Held rather than an end time, because being watched pauses the
	-- count where it is instead of restarting it: an escape you had almost finished should
	-- be worth something when the officer walks past, or nobody will ever start one with
	-- anybody nearby, which is every interesting time to start one.
	heldFor: number,
	-- How long to keep the finished sign up before the mark goes quiet again. Purely so the
	-- player gets to see it land -- five seconds of standing still that ended with the sign
	-- blinking straight back to "Change" would read as a failure.
	doneFor: number,
}

local changes: { [Player]: Change } = {}
local enabled = true

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

local function labelFor(place: string): string
	local spot = Hideouts.Get(place)
	return if spot ~= nil then spot.label else "Change"
end

-- Off the mark, for whatever reason. The sign is released here rather than left to time out,
-- because a mark still owned by somebody who walked away is a mark the next player cannot
-- use -- the worst possible failure for a thing whose entire job is being available in an
-- emergency.
local function leave(player: Player)
	local change = changes[player]
	if change == nil then
		return
	end
	changes[player] = nil
	Wardrobe.Rest(change.place, player, labelFor(change.place))
end

-- The mark this player is standing on, or nil. Nearest wins -- see Wardrobe.DistanceTo for
-- why that is worth the extra line.
local function markUnder(at: Vector3): string?
	local best: string? = nil
	local bestDistance = math.huge
	for _, spot in Hideouts.Spots do
		local distance = Wardrobe.DistanceTo(spot.place, at)
		if distance ~= nil and distance <= DISGUISE.ReachStuds and distance < bestDistance then
			best = spot.place
			bestDistance = distance
		end
	end
	return best
end

-- Why this player cannot change right now, as a sentence for the sign over their head, or
-- nil if they can.
--
-- Ordered by what is most useful to read at a run. Being watched first because it is the one
-- that changes second to second and the one they can do something about by waiting; the
-- money last because it is a fact about the afternoon rather than about this moment.
local function blockedBecause(player: Player): string?
	-- Right now, not recently. Deliberately not a check on how stale the last sighting is:
	-- making the player wait out a sighting *and then* stand still for five seconds would
	-- double a cost that is already the whole point of the verb, and would mean the escape
	-- is unavailable during exactly the seconds it is worth having.
	if BountyService.IsSeen(player) then
		return "Not while they can see you"
	end
	if not MoneyService.CanAfford(player, DISGUISE.Cost) then
		return `{Money.Format(DISGUISE.Cost)} for clothes`
	end
	return nil
end

local function tickPlayer(player: Player, elapsed: number)
	local at = characterPosition(player)
	if at == nil then
		leave(player)
		return
	end

	local place = markUnder(at)
	if place == nil then
		leave(player)
		return
	end

	-- Nothing to hide from, so the mark stays quiet. This is not a refusal and must not read
	-- as one: home is on the hideout list, a player walks across their own kitchen a hundred
	-- times a life, and a floor that went red and told them off every time would turn the one
	-- thing they need to recognise instantly under pressure into wallpaper they have learned
	-- to ignore. The mark only ever speaks when it has something to offer.
	if not BountyService.Described(player) then
		leave(player)
		return
	end

	local change = changes[player]
	if change ~= nil and change.place ~= place then
		-- Walked from one mark straight onto another, which is only reachable by a debug
		-- teleport today. The banked seconds do not travel: they were spent standing in a
		-- particular room, and carrying them would make a chain of marks a way of doing this
		-- in installments from anywhere.
		leave(player)
		change = nil
	end

	if change == nil then
		if not Wardrobe.Claim(place, player) then
			return
		end
		change = { place = place, heldFor = 0, doneFor = 0 }
		changes[player] = change
	end

	local held = change :: Change

	-- The moment after. Held on screen rather than cleared, so five seconds of standing
	-- perfectly still visibly ends in something.
	if held.doneFor > 0 then
		held.doneFor -= elapsed
		Wardrobe.Show(place, player, "Changed", 1, "done")
		if held.doneFor <= 0 then
			leave(player)
		end
		return
	end

	local blocked = blockedBecause(player)
	if blocked ~= nil then
		-- Paused, not reset. See Change.heldFor: an escape you had almost finished has to be
		-- worth something when somebody walks past, or nobody will ever start one at the only
		-- times it is interesting to.
		Wardrobe.Show(place, player, blocked, held.heldFor / DISGUISE.ChangeSeconds, "blocked")
		return
	end

	held.heldFor += elapsed
	if held.heldFor < DISGUISE.ChangeSeconds then
		Wardrobe.Show(
			place,
			player,
			`Changing… {math.ceil(DISGUISE.ChangeSeconds - held.heldFor)}s`,
			held.heldFor / DISGUISE.ChangeSeconds,
			"busy"
		)
		return
	end

	-- Decided before anything is written, then recorded, which is this project's standing
	-- rule for anything a retry could reach. The money goes first: a spend that failed after
	-- the description was already gone would be a free escape, and there is no unpicking a
	-- belief you have already deleted.
	if not MoneyService.Spend(player, DISGUISE.Cost, "a change of clothes") then
		held.heldFor = 0
		Wardrobe.Show(place, player, `{Money.Format(DISGUISE.Cost)} for clothes`, 0, "blocked")
		return
	end

	BountyService.LoseDescription(player)
	held.heldFor = 0
	held.doneFor = 1.5
end

-- Stands up every mark in the content list, once, and says which ones could not be built.
--
-- At startup rather than on arrival, so a missing place point is a line in the log on a
-- developer's first boot rather than a corner of the map a player sprints to under pressure
-- and finds empty.
local function buildMarks()
	for _, spot in Hideouts.Spots do
		local place = PlaceService.Find(spot.place)
		if place == nil then
			warn(
				`[AGES] hideout "{spot.place}" has no place point in the built world, so there is `
					.. `nowhere to change there. Either the town no longer has that room or the id in `
					.. `content/Hideouts.luau is wrong.`
			)
			continue
		end
		if Wardrobe.Build(spot.place, place.part.CFrame, spot.label) == nil then
			warn(`[AGES] could not stand up a hideout at "{spot.place}"; its place point has no heading.`)
		end
	end
end

-- Off leaves the marks standing but dead, which is the useful state for telling a disguise
-- bug apart from a pursuit one: with this off, a chase that never ends is the pursuit's
-- fault and a chase that ends anyway is not.
function DisguiseService.SetEnabled(value: boolean)
	enabled = value
	if not value then
		for player in changes do
			leave(player)
		end
	end
end

function DisguiseService.IsEnabled(): boolean
	return enabled
end

-- For the harness, and phrased as the two questions a broken escape raises: is there a mark
-- under me, and if I am not counting, why not.
function DisguiseService.Describe(player: Player): string
	local at = characterPosition(player)
	local lines = { if enabled then "disguise on" else "disguise OFF" }

	local built = 0
	for _, spot in Hideouts.Spots do
		if Wardrobe.Get(spot.place) ~= nil then
			built += 1
		end
	end
	table.insert(lines, `{built}/{#Hideouts.Spots} marks built`)

	if at == nil then
		table.insert(lines, "no body in the world")
		return table.concat(lines, " · ")
	end

	local place = markUnder(at)
	if place == nil then
		table.insert(lines, "not on a mark")
	else
		local change = changes[player]
		local held = if change ~= nil then change.heldFor else 0
		table.insert(lines, `on "{place}" at {string.format("%.1f", held)}/{DISGUISE.ChangeSeconds}s`)
		table.insert(lines, blockedBecause(player) or "counting")
	end
	return table.concat(lines, " · ")
end

function DisguiseService:Start()
	buildMarks()

	Players.PlayerRemoving:Connect(leave)

	task.spawn(function()
		while true do
			local elapsed = task.wait(DISGUISE.TickSeconds)
			if enabled then
				for _, player in Players:GetPlayers() do
					local fine, problem = pcall(tickPlayer, player, elapsed)
					if not fine then
						warn(`[AGES] disguise tick failed for {player.Name}: {problem}`)
					end
				end
			end
		end
	end)
end

return DisguiseService
