--!strict
-- Whose side of the map you are standing on, and what it costs to be standing there
-- in the wrong colors.
--
-- Gangs.luau wrote down a `side` for each of the four bosses and said, in a comment,
-- that nothing read it yet: "territory is deferred until the map expansion... the seam
-- is here; the districts hang off it when there are districts." This is that file. The
-- districts are not authored anywhere -- a side is simply the ground nearer to that
-- boss than to any other boss, which is computed in Shared/WorldMap from where the four
-- bosses actually stand. Nothing here to keep in step with the world when it changes.
--
-- **The mechanic, in one paragraph.** Wearing your colors on a rival's side costs you
-- standing with that rival, once, when you cross in. Getting back out pays standing with
-- your own gang, once, scaled by the deepest you actually got. Take the band off and
-- none of it applies -- which is the first time SetColors has been a decision rather
-- than a preference.
--
-- **Nothing here pays for time, and that is the whole design.** Config.Gangs.Earn says
-- of its largest award that escaping "is the only line here that cannot be farmed by
-- standing still and holding a button". An award for dwelling in rival turf would have
-- been exactly that button. So the award is a function of *depth* -- a maximum over the
-- positions you occupied, never a sum over seconds -- and a player who walks in and
-- stands there for an hour is paid precisely what a player who walked to the same spot
-- and turned round is paid.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local WorldMap = require(ReplicatedStorage:WaitForChild("WorldMap"))
local MapShapes = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("MapShapes"))

local Gangs = require(script.Parent.Parent.content.Gangs)
local GangService = require(script.Parent.GangService)
local PlaceService = require(script.Parent.PlaceService)

type Player = Players.Player
type Site = WorldMap.Site

local TerritoryService = {}

local TERRITORY = Config.Territory
local INCURSION = TERRITORY.Incursion

local TERRITORY_UPDATED = Remotes.Get("TerritoryUpdated")
local MAP_DATA = Remotes.Get("MapData")
local NOTICE = Remotes.Get("Notice")

-- What a player is in the middle of. `deepest` is the furthest inside the rival side
-- they have been on this trip, which is the only thing the award is computed from.
type Incursion = {
	rivalId: string,
	deepest: number,
}

type Watch = {
	region: string?,
	incursion: Incursion?,
}

local watches: { [Player]: Watch } = {}

local function watchFor(player: Player): Watch
	local existing = watches[player]
	if existing ~= nil then
		return existing
	end
	local made: Watch = { region = nil, incursion = nil }
	watches[player] = made
	return made
end

-- The four points the sides are grown from.
--
-- Rebuilt until it succeeds rather than cached on first call: place points are tagged
-- instances and the bosses' may not have streamed in when the first player joins, so a
-- cache taken too early would pin an empty table for the life of the server. Once all
-- four are found the answer cannot change, so it is cached then and not before.
local cachedSites: { Site }? = nil

local function sites(): { Site }
	local ready = cachedSites
	if ready ~= nil then
		return ready
	end

	local found: { Site } = {}
	for _, gang in Gangs.All do
		local place = PlaceService.Find(gang.bossPlaceId)
		if place ~= nil then
			local position = place.part.Position
			table.insert(found, { id = gang.id, x = position.X, z = position.Z })
		end
	end

	if #found == #Gangs.All then
		cachedSites = found
	end
	return found
end

-- The box the map is drawn in, measured from the places that exist.
--
-- Waypoints are excluded. They are routing nodes rather than destinations -- the
-- `wp_` prefix is what Config calls them -- and a map that stretched to include the
-- pathfinding scaffolding would be a map of the scaffolding.
local cachedBounds: WorldMap.Bounds? = nil

local function mapBounds(): WorldMap.Bounds?
	local ready = cachedBounds
	if ready ~= nil then
		return ready
	end

	local points: { Vector3 } = {}
	for _, place in PlaceService.All() do
		if string.sub(place.id, 1, #Config.World.PlaceWaypointPrefix) == Config.World.PlaceWaypointPrefix then
			continue
		end
		table.insert(points, place.part.Position)
	end

	-- The drawn world's own corners, thrown in with the doorways.
	--
	-- Place points sit at things you can walk into, and a coastline is not one -- so a
	-- box measured from doorways alone stops short of the sea, the beach and the outer
	-- ring road, and the map crops the edge of the world off. Two corners is enough:
	-- `BoundsOf` only ever takes a minimum and a maximum.
	local extent = MapShapes.Extent
	table.insert(points, Vector3.new(extent.minX, 0, extent.minZ))
	table.insert(points, Vector3.new(extent.maxX, 0, extent.maxZ))

	local bounds = WorldMap.BoundsOf(points, Config.Map.EdgePadStuds)
	if bounds ~= nil and #points >= Config.Map.MinPlacesForBounds then
		cachedBounds = bounds
	end
	return bounds
end

-- Where the player's body is, flat. Nil whenever there is no body to ask, which is
-- every frame between dying and respawning.
local function positionOf(player: Player): Vector3?
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

local function gangName(gangId: string): string
	local def = Gangs.ById[gangId]
	return if def ~= nil then def.name else gangId
end

-- End the trip without paying for it.
--
-- Two things void a run, and both are the player ceasing to be the thing the award is
-- for. Taking the band off mid-run is the obvious one: the reward is for being seen in
-- the wrong colors, so a player who pockets them has stopped taking the risk and cannot
-- keep the fee. Without this the exploit is complete and cheap -- cross the line wearing
-- them, pay the entry cost once, immediately go grey, wander the whole side in safety,
-- and collect on the way home for a walk nobody could see you take.
--
-- Dying is the other. The award is paid for *getting out*, and a player carried out is
-- not one who got out; leaving it open would have made dying deep in rival ground pay
-- exactly as well as walking home from it, which is the wrong lesson twice over.
local function voidIncursion(watch: Watch)
	watch.incursion = nil
end

-- Settle whatever trip the player was on and pay for it.
--
-- Paid on the way *out*, never on the way in and never while inside, so the award has
-- a moment rather than a rate. A player who never leaves is never paid, which is the
-- correct answer to standing still in enemy territory: it is not brave, it is just
-- standing.
local function settleIncursion(player: Player, watch: Watch)
	local incursion = watch.incursion
	if incursion == nil then
		return
	end
	watch.incursion = nil

	if incursion.deepest < INCURSION.MinDepthStuds then
		return
	end

	local award = math.floor(math.min(incursion.deepest * INCURSION.PerStudDepth, INCURSION.MaxAward))
	if award <= 0 then
		return
	end

	GangService.Credit(player, award, `ran the {gangName(incursion.rivalId)} line`)
end

-- Called once per crossing, after the edge band has been cleared in the new side.
local function onCrossing(player: Player, watch: Watch, into: string)
	local previous = watch.region
	watch.region = into

	local gangId = GangService.GangOf(player)

	-- Not in a gang, or carrying the band in a pocket. Territory is still reported to
	-- the client -- knowing which side you are on is a fact about the map, not a reward
	-- -- but nothing is charged and nothing is owed. Travelling with the colors off is
	-- meant to be the safe way to cross the city, and this is the line that makes it so.
	if gangId == nil or not GangService.IsWearing(player) then
		settleIncursion(player, watch)
		return
	end

	-- Leaving wherever we were settles it, including rival-to-rival: the trip that is
	-- ending is the one that gets paid, and the next crossing opens a new one.
	settleIncursion(player, watch)

	if into == gangId then
		return
	end

	watch.incursion = { rivalId = into, deepest = 0 }
	GangService.ChargeIn(player, into, INCURSION.RivalCost, "seen on their side")

	-- Silent on the very first crossing of a life, which is the one the player did not
	-- make: it is the tick noticing where they already were. Every crossing after that
	-- is a decision and gets told about.
	if previous ~= nil then
		NOTICE:FireClient(player, `You are on {gangName(into)}'s side, wearing someone else's colors.`)
	end
end

local function pushState(player: Player, watch: Watch, depth: number)
	local state: Types.TerritoryState = {
		regionId = watch.region,
		depthStuds = math.floor(depth),
		onIncursion = watch.incursion ~= nil,
		deepestStuds = if watch.incursion ~= nil then math.floor(watch.incursion.deepest) else 0,
	}
	TERRITORY_UPDATED:FireClient(player, state)
end

-- One player, one tick.
local function step(player: Player)
	local watch = watchFor(player)
	local position = positionOf(player)
	if position == nil then
		return
	end

	local here = sites()
	if #here == 0 then
		return
	end

	local standing = WorldMap.StandingAt(here, position.X, position.Z)
	local region = standing.id
	if region == nil then
		return
	end

	-- Checked every tick rather than only on a crossing, because taking the band off is
	-- not a crossing -- it happens standing still, in the middle of somebody else's side,
	-- and a run that is only re-examined at borders would never notice.
	if watch.incursion ~= nil and not GangService.IsWearing(player) then
		voidIncursion(watch)
	end

	-- Deepest-so-far is tracked every tick, but only ever by taking a maximum. Two
	-- players standing in the same doorway for different lengths of time are owed the
	-- same amount, because this line cannot accumulate.
	local incursion = watch.incursion
	if incursion ~= nil and region == incursion.rivalId then
		incursion.deepest = math.max(incursion.deepest, standing.depthStuds)
	end

	-- Inside the band around the border, nothing is decided. A player pacing the line
	-- would otherwise trip a crossing every tick in both directions and be charged for
	-- each one; the band is what makes a boundary a place rather than an instant.
	if standing.depthStuds < TERRITORY.EdgeBandStuds then
		pushState(player, watch, standing.depthStuds)
		return
	end

	if region ~= watch.region then
		onCrossing(player, watch, region)
	end

	pushState(player, watch, standing.depthStuds)
end

-- The static half: where the map is, what is on it, and which color each side draws in.
-- Sent once per join rather than per tick because none of it changes while the server
-- is up.
local function pushMapData(player: Player)
	local bounds = mapBounds()
	if bounds == nil then
		return
	end

	local icons: { Types.MapIcon } = {}
	for _, place in PlaceService.All() do
		if string.sub(place.id, 1, #Config.World.PlaceWaypointPrefix) == Config.World.PlaceWaypointPrefix then
			continue
		end
		local position = place.part.Position
		local u, v = WorldMap.Normalize(bounds, position.X, position.Z)
		table.insert(icons, { id = place.id, label = place.label, u = u, v = v })
	end

	local regions: { Types.MapRegion } = {}
	for _, site in sites() do
		local def = Gangs.ById[site.id]
		if def == nil then
			continue
		end
		local u, v = WorldMap.Normalize(bounds, site.x, site.z)
		table.insert(regions, { id = site.id, name = def.name, color = def.color, u = u, v = v })
	end

	MAP_DATA:FireClient(player, {
		minX = bounds.minX,
		maxX = bounds.maxX,
		minZ = bounds.minZ,
		maxZ = bounds.maxZ,
		icons = icons,
		regions = regions,
	} :: Types.MapData)
end

-- Which side a position is on, for anything else that wants to ask. Nil before the
-- bosses have streamed in.
function TerritoryService.RegionAt(position: Vector3): string?
	return WorldMap.RegionAt(sites(), position)
end

-- Which side a player is on right now, as last decided by the tick. Deliberately the
-- committed region rather than a fresh measurement, so a caller and the player's own
-- HUD never disagree about which side they are standing on.
function TerritoryService.RegionOf(player: Player): string?
	local watch = watches[player]
	return if watch ~= nil then watch.region else nil
end

-- Losing the body ends the run and forgets where it was.
--
-- Both halves matter. Voiding is what stops dying in rival ground paying the same as
-- walking out of it. Clearing the region is what stops the respawn being read as a
-- crossing: a player who dies on the east side and wakes up at home has not walked
-- anywhere, and a stale region would make the tick charge them for a journey the
-- ambulance made. Nil means "wherever they turn out to be is simply where they are",
-- which is also why the first crossing of a life sends no notice.
local function forget(player: Player)
	local watch = watches[player]
	if watch == nil then
		return
	end
	voidIncursion(watch)
	watch.region = nil
end

function TerritoryService:Init()
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterRemoving:Connect(function()
			forget(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		watches[player] = nil
	end)
end

function TerritoryService:Start()
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(pushMapData, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(pushMapData, player)
	end

	task.spawn(function()
		while true do
			task.wait(TERRITORY.TickSeconds)
			for _, player in Players:GetPlayers() do
				step(player)
			end
		end
	end)
end

return TerritoryService
