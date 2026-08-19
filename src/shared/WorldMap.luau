--!strict
-- The geometry behind the map and behind whose side you are standing on. Pure
-- functions over numbers: no services, no remotes, no Roblox state beyond Vector3.
-- Server and client both require it, which is the point -- the overlay the player
-- reads and the rule the server enforces have to be the same arithmetic, or the map
-- is a decoration that lies.
--
-- Two ideas live here and they are the same idea twice:
--
-- 1. **The map's extent is measured, never written down.** Bounds come from the
--    place points that exist, so a regenerated or expanded city redraws its own map
--    with nothing edited. tools/world_plan.py holds the world's real numbers and this
--    file deliberately does not transcribe them -- a second copy of 1024 is the defect
--    this tree keeps producing.
--
-- 2. **A region is "nearer this boss than any other boss".** Four bosses, four sides,
--    no authored rectangles. It partitions the whole plane with no gaps and no overlaps
--    by construction, and it cannot disagree with where the bosses actually stand
--    because it is computed from where they actually stand.
--
-- Everything is flat: X and Z, Y discarded. A player on a first floor is on the same
-- side of the map as the pavement below them, and height has no opinion about turf.

export type Bounds = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}

-- A named point the regions are grown from. In practice a gang boss's place point,
-- but the maths does not care and the tests pass it plain tables.
export type Site = {
	id: string,
	x: number,
	z: number,
}

-- Which side a position is on, and how far inside it. `depthStuds` is the distance to
-- the nearest boundary with another side -- zero at the line, larger the deeper in.
-- Nil id only when there are no sites at all.
export type Standing = {
	id: string?,
	depthStuds: number,
}

local WorldMap = {}

-- Flat distance, squared. Squared because every comparison below is a comparison
-- between two of these and the square root would change no answer.
local function flatDistanceSquared(x1: number, z1: number, x2: number, z2: number): number
	local dx, dz = x1 - x2, z1 - z2
	return dx * dx + dz * dz
end

-- The box containing every point given, padded outward.
--
-- Padding is not decoration: place points sit *at* buildings, so an unpadded box
-- clips the map exactly at the outermost doorway and the edge of the world reads as
-- the edge of the paper. Returns nil for an empty list rather than a zero box, because
-- a zero box would divide by zero in Normalize and the caller has to know it has no
-- map rather than be handed a broken one.
function WorldMap.BoundsOf(points: { Vector3 }, padStuds: number): Bounds?
	if #points == 0 then
		return nil
	end

	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, point in points do
		minX = math.min(minX, point.X)
		maxX = math.max(maxX, point.X)
		minZ = math.min(minZ, point.Z)
		maxZ = math.max(maxZ, point.Z)
	end

	return {
		minX = minX - padStuds,
		maxX = maxX + padStuds,
		minZ = minZ - padStuds,
		maxZ = maxZ + padStuds,
	}
end

-- World X/Z to 0..1 across the bounds. Y is not a parameter because the map has no
-- opinion about height.
--
-- Returned unclamped on purpose. A caller drawing an icon wants to know the thing is
-- off the map so it can drop it or pin it to the rim, and clamping here would silently
-- stack everything outside the world onto the border instead.
--
-- Z maps straight through rather than being flipped. Roblox's +Z runs *south* on the
-- compass GeographyService uses, and a map is drawn with north at the top, so the
-- caller that draws it flips Y once at the point of drawing. Doing it here would put
-- the flip somewhere the maths cannot explain it.
function WorldMap.Normalize(bounds: Bounds, x: number, z: number): (number, number)
	local width = bounds.maxX - bounds.minX
	local depth = bounds.maxZ - bounds.minZ
	if width <= 0 or depth <= 0 then
		return 0.5, 0.5
	end
	return (x - bounds.minX) / width, (z - bounds.minZ) / depth
end

-- The reverse, for a click on the map becoming a place in the world.
function WorldMap.Denormalize(bounds: Bounds, u: number, v: number): (number, number)
	return bounds.minX + u * (bounds.maxX - bounds.minX), bounds.minZ + v * (bounds.maxZ - bounds.minZ)
end

-- The perpendicular distance from a point to the line equidistant between two sites.
--
-- Not (|PB| - |PA|) / 2, which is the tempting version and is wrong -- that quantity
-- is only proportional to the true distance when the point lies on the segment joining
-- the two sites. The identity that actually holds is
--
--     distance to bisector = (|PB|^2 - |PA|^2) / (2 * |AB|)
--
-- which falls out of expanding both squared distances: the |P|^2 terms cancel and what
-- is left is linear in P. Positive when P is on A's side. Exact, and three multiplies.
local function distanceToBisector(x: number, z: number, a: Site, b: Site): number
	local separation = math.sqrt(flatDistanceSquared(a.x, a.z, b.x, b.z))
	if separation <= 0 then
		-- Two bosses in the same spot have no bisector to be a distance from. Infinite
		-- rather than zero: there is no boundary here, so nothing should ever pick this
		-- pair as the nearest one.
		return math.huge
	end
	local toA = flatDistanceSquared(x, z, a.x, a.z)
	local toB = flatDistanceSquared(x, z, b.x, b.z)
	return (toB - toA) / (2 * separation)
end

-- Which site owns this ground, and how far in from the nearest border it is.
--
-- The border of a region is the nearest of its bisectors with every other site, so
-- depth is a minimum over the rivals rather than a distance to any single line. With
-- four sites that is three comparisons and no reason to be cleverer.
--
-- Depth is what the incursion award is measured in, and it is a property of *where you
-- are* rather than of how long you have been there -- which is the whole reason the
-- reward cannot be farmed by standing still.
function WorldMap.StandingAt(sites: { Site }, x: number, z: number): Standing
	if #sites == 0 then
		return { id = nil, depthStuds = 0 }
	end
	if #sites == 1 then
		-- One side owns everything and has no border to be deep inside of. Infinite
		-- depth would be truthful and useless; zero says "there is no line here", which
		-- is what every caller actually wants to hear.
		return { id = sites[1].id, depthStuds = 0 }
	end

	local nearest = sites[1]
	local nearestDistance = flatDistanceSquared(x, z, nearest.x, nearest.z)
	for index = 2, #sites do
		local site = sites[index]
		local distance = flatDistanceSquared(x, z, site.x, site.z)
		if distance < nearestDistance then
			nearest, nearestDistance = site, distance
		end
	end

	local depth = math.huge
	for _, site in sites do
		if site.id ~= nearest.id then
			depth = math.min(depth, distanceToBisector(x, z, nearest, site))
		end
	end
	if depth == math.huge then
		depth = 0
	end

	return { id = nearest.id, depthStuds = math.max(depth, 0) }
end

-- Convenience for the common call, which has a Vector3 and wants only the name.
function WorldMap.RegionAt(sites: { Site }, position: Vector3): string?
	return WorldMap.StandingAt(sites, position.X, position.Z).id
end

return WorldMap
