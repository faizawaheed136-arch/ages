--!strict
-- The town's roads, as a graph the people can be walked along.
--
-- Every node is a tagged part; any two within `RouteLinkStuds` of each other are joined.
-- That is the whole model, and it is deliberately the cheapest one that could work: the
-- builder tags corners, benches and the ends of paths in Studio, and the joining is done by
-- proximity rather than by anybody drawing edges by hand. A graph you have to author is a
-- graph that is wrong the first time somebody moves a wall.
--
-- **Which parts, though — and there are two answers, in order.** `AgesTownPoint` if any
-- part carries it, and nothing else is even looked at. Otherwise the `AgesPlacePoint` parts
-- the game already needs for its own reasons: your front gate, the crossing, the school
-- forecourt, outside the store.
--
-- That second tier is not a shortcut, it is the difference between a feature and a feature
-- with a manual. A world where nobody has done the tagging is the world the game is
-- actually in, and in that world the place points are already the only surveyed spots on
-- the map -- somebody put each of them at a specific doorway for a specific reason. Linking
-- them turns "wander to probed ground near your own building" into "walk between the places
-- this street is made of", which is the thing that was asked for, without a Studio step
-- nobody was told to take. Tag real path corners and this tier vanishes, silently and
-- completely, which is why it does not need a switch.
--
-- **Why a graph at all, when Roam already picked spots.** Roam probes the ground for a
-- standable point and walks there, which is fine for milling about outside a shop and is
-- useless for crossing a town: probed points are wherever the floor happens to be, so a
-- person crossing a street walks through the middle of the road, the flowerbed and the
-- neighbour's garden with equal enthusiasm. Nodes are on paths because a person put them
-- there. This is the difference between people wandering near buildings and people using
-- the streets.
--
-- **What happens with nothing tagged: nothing.** Every function here answers "no route"
-- and the caller falls back to the probe it used before, which is exactly the behaviour
-- the game had. That is the property that makes this worth building rather than raising
-- a radius -- the feature is turned on by tagging the world, not by a flag, and a world
-- that has not been tagged yet is not a broken world.
--
-- Nothing here knows what a person is. It answers "given that you are here and belong
-- over there, where is the next place worth walking to", and PeopleService decides who is
-- asking and whether they have a body at the time.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Ground = require(script.Parent.Ground)

local TOWN = Config.Town

local Routes = {}

-- Positions and the parts they came from, index-aligned. The parts are kept only so a
-- warning can name the thing the builder has to go and look at -- an island reported as
-- "node 14" is a warning nobody can act on.
local nodes: { Vector3 } = {}
local parts: { BasePart } = {}
local neighbors: { { number } } = {}

-- Which connected component each node is in, and how many there are. Worth computing
-- because two components is the single most confusing way a tagged world can be wrong:
-- everybody whose home is in one of them will look like they are refusing to go anywhere
-- near the other, which reads as a bug in the people rather than a gap in the paths.
local component: { number } = {}
local componentCount = 0
local edgeCount = 0

-- Which tag the current graph came from. Kept because the two tiers fail in different ways
-- and a harness reading "12 points, 3 pieces" cannot tell which it is looking at: three
-- islands of hand-tagged corners is a builder mistake, and three islands of place points is
-- just a town whose buildings are further apart than one road.
local sourceTag = ""

-- Built on first use and after any tag changes, rather than on a timer. Tagging happens
-- in Studio, in bursts, and a graph rebuilt per access would be a full O(n^2) pass every
-- time somebody took a step.
local stale = true

local warnedShapes: { [Instance]: boolean } = {}

-- Connected components, by flood fill. Iterative rather than recursive because the town
-- is one long path more often than it is a blob, and a recursive fill down a hundred-node
-- corridor is a hundred stack frames for no reason.
local function findComponents()
	table.clear(component)
	componentCount = 0

	for index = 1, #nodes do
		if component[index] ~= nil then
			continue
		end
		componentCount += 1
		local queue = { index }
		component[index] = componentCount
		while #queue > 0 do
			local at = table.remove(queue) :: number
			for _, other in neighbors[at] do
				if component[other] == nil then
					component[other] = componentCount
					table.insert(queue, other)
				end
			end
		end
	end
end

local function build()
	stale = false
	table.clear(nodes)
	table.clear(parts)
	table.clear(neighbors)
	edgeCount = 0

	-- The two tiers, and the test is "is there anything at all", not "is there enough".
	-- A builder who has tagged three corners so far means those three corners and not a
	-- mixture of their work and the fallback -- a graph that is half one thing and half
	-- another is the one outcome nobody could reason about from Studio.
	sourceTag = Config.World.TownPointTag
	local tagged = CollectionService:GetTagged(sourceTag)
	if #tagged == 0 then
		sourceTag = Config.World.PlacePointTag
		tagged = CollectionService:GetTagged(sourceTag)
	end

	for _, instance in tagged do
		if not instance:IsA("BasePart") then
			if not warnedShapes[instance] then
				warnedShapes[instance] = true
				warn(`[AGES] town point "{instance:GetFullName()}" is a {instance.ClassName}, which has no position`)
			end
			continue
		end
		local part = instance :: BasePart
		if part.Parent == nil then
			continue
		end
		table.insert(nodes, part.Position)
		table.insert(parts, part)
		table.insert(neighbors, {})
	end

	-- The full pairwise pass. Quadratic, and that is fine at the scale this operates on --
	-- a hand-tagged town is tens of points, not thousands -- and it runs only when the
	-- tagging changes. A spatial index here would be a lot of code guarding a loop that
	-- costs nothing.
	for a = 1, #nodes do
		for b = a + 1, #nodes do
			if Ground.FlatDistance(nodes[a], nodes[b]) <= TOWN.RouteLinkStuds then
				table.insert(neighbors[a], b)
				table.insert(neighbors[b], a)
				edgeCount += 1
			end
		end
	end

	findComponents()

	-- Both of these are build mistakes that produce no error and no visible symptom except
	-- people not going where the builder expected, so they are said out loud once per build
	-- rather than left to be discovered by watching the street.
	--
	-- Only for hand-tagged points, though. On the place-point tier neither is a mistake: a
	-- school on the far side of town is further than one road from the crossing because
	-- that is where the school is, and warning about it would be the game complaining about
	-- its own map every time the graph was rebuilt. `/town routes` still reports both, which
	-- is where somebody asking the question would look.
	if sourceTag ~= Config.World.TownPointTag then
		return
	end

	for index, list in neighbors do
		if #list == 0 then
			warn(
				`[AGES] town point "{parts[index]:GetFullName()}" has no other point within `
					.. `{TOWN.RouteLinkStuds} studs, so nobody can walk to or from it`
			)
		end
	end
	if componentCount > 1 then
		local sizes: { number } = {}
		for _, id in component do
			sizes[id] = (sizes[id] or 0) + 1
		end
		local text: { string } = {}
		for id = 1, componentCount do
			table.insert(text, tostring(sizes[id] or 0))
		end
		warn(
			`[AGES] the town's paths are in {componentCount} disconnected pieces `
				.. `({table.concat(text, " + ")} points). Nobody can walk between them, which looks `
				.. `like people avoiding half the map. Tag a point in the gap to join them.`
		)
	end
end

local function ensure()
	if stale then
		build()
	end
end

-- Forces a rebuild. For the harness, and for the case the tag signals cannot see: a
-- builder who dragged a tagged part to a new spot changed the graph without adding or
-- removing anything, and no signal fires for that.
function Routes.Refresh()
	stale = true
	ensure()
end

function Routes.NodeCount(): number
	ensure()
	return #nodes
end

-- The nearest node to `at` that is also close enough to `home` to be allowed. Both halves
-- matter: the first is what makes a person join the paths near where they already are,
-- and the second is the leash that stops the whole town converging on one high street.
local function nearestWithin(at: Vector3, home: Vector3): number?
	local best: number? = nil
	local bestDistance = math.huge
	for index, position in nodes do
		if Ground.FlatDistance(position, home) > TOWN.RangeStuds then
			continue
		end
		local distance = Ground.FlatDistance(position, at)
		if distance < bestDistance then
			best = index
			bestDistance = distance
		end
	end
	return best
end

-- Where to walk next, as a node index and the position to head for. Nil for both when
-- there is no graph in reach, which is the caller's signal to fall back to probing the
-- ground -- not an error, and the normal answer in a world nobody has tagged.
--
-- `previous` is where they came from, and it is avoided rather than forbidden. Forbidding
-- it would strand anybody standing on a dead end, and a person who walks to the end of a
-- cul-de-sac and then refuses to leave it is a worse artefact than one who occasionally
-- retraces a step.
function Routes.Step(
	fromNode: number?,
	previous: number?,
	at: Vector3,
	home: Vector3,
	rng: Random
): (number?, Vector3?)
	ensure()
	if #nodes == 0 then
		return nil, nil
	end

	-- Not on the graph: join it. Walking to the node they joined at is itself a real leg,
	-- so it is handed back as the goal rather than assumed to have already happened --
	-- otherwise somebody standing in a garden would teleport onto the pavement.
	if fromNode == nil or nodes[fromNode] == nil then
		local entry = nearestWithin(at, home)
		if entry == nil then
			return nil, nil
		end
		return entry, nodes[entry]
	end

	local preferred: { number } = {}
	local backtrack: { number } = {}
	for _, index in neighbors[fromNode] do
		if Ground.FlatDistance(nodes[index], home) > TOWN.RangeStuds then
			continue
		end
		if index == previous then
			table.insert(backtrack, index)
		else
			table.insert(preferred, index)
		end
	end

	local pool = if #preferred > 0 then preferred else backtrack
	if #pool == 0 then
		-- Every neighbour is past the leash, which happens to whoever is standing at the
		-- far edge of their range. Heading for the node nearest home is the one move that
		-- is always both legal and progress; picking nothing would leave them stood there
		-- for the rest of the life.
		local back = nearestWithin(home, home)
		if back == nil or back == fromNode then
			return nil, nil
		end
		return back, nodes[back]
	end

	local pick = pool[rng:NextInteger(1, #pool)]
	return pick, nodes[pick]
end

-- The harness line for `/town routes`. Refreshes first, because the question being asked
-- is almost always "I have just changed the tagging, did it take".
function Routes.Describe(): string
	Routes.Refresh()

	if #nodes == 0 then
		return `nothing tagged "{Config.World.TownPointTag}" or "{Config.World.PlacePointTag}" — `
			.. `townsfolk are wandering to probed ground within {TOWN.RoamStuds} studs of their `
			.. `own place, which is the fallback, not a fault`
	end

	local islands: { string } = {}
	for index, list in neighbors do
		if #list == 0 then
			table.insert(islands, parts[index].Name)
		end
	end

	-- Which tier first, because it changes what every number after it means. On place
	-- points, islands and pieces are the shape of the map; on town points they are a
	-- to-do list.
	local tier = if sourceTag == Config.World.TownPointTag
		then `hand-tagged "{sourceTag}"`
		else `falling back to "{sourceTag}" (tag "{Config.World.TownPointTag}" to override)`
	local text = `{#nodes} route points, {tier}, {edgeCount} links within `
		.. `{TOWN.RouteLinkStuds} studs, {componentCount} connected `
		.. `piece{if componentCount == 1 then "" else "s"}, leash {TOWN.RangeStuds} studs from home`
	if #islands > 0 then
		table.sort(islands)
		text ..= ` | {#islands} unreachable: {table.concat(islands, ", ")}`
	end
	return text
end

-- Marked stale rather than rebuilt on the spot: tagging a dozen points in Studio would
-- otherwise rebuild the graph a dozen times, and the next person to ask a question is
-- going to rebuild it once anyway.
-- Both tags, because either can change which tier the graph is on: the first town point
-- ever tagged replaces the whole place-point graph, and a place point added while there are
-- still no town points is a new node.
for _, tag in { Config.World.TownPointTag, Config.World.PlacePointTag } do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function()
		stale = true
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function()
		stale = true
	end)
end

return Routes
