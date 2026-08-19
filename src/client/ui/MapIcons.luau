--!strict
-- How a place id becomes a coloured dot, and how a region id becomes a name and a
-- colour. Shared by the minimap and the full sheet so the same building cannot be one
-- colour in the corner of the screen and another on the map behind it.
--
-- Pure lookups over Config and the pushed MapData. No instances, no state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

type MapData = Types.MapData

local ICONS = Config.Map.Icons
local DETAIL_ZOOM = Config.Map.DetailZoom

export type Style = {
	color: Color3,
	size: number,
	priority: number,
	kind: string,
	-- When this place is drawn, not what it is. The full sheet shows landmarks at rest
	-- and hands the rest back as the player zooms in -- see `Config.Map.DetailZoom`.
	-- The minimap ignores it: at a 260-stud radius there is no crowd to thin out, and a
	-- corner dial that hid the cafe you are standing next to would be worse than useless.
	tier: string,
}

local MapIcons = {}

-- Cached because the full sheet asks this once per place per open, the minimap asks it
-- once per place on the single push that builds its markers, and the answer for a given
-- id can never change while the server is up. The table is small -- one entry per place
-- that exists -- and bounded by the world rather than by time.
local cache: { [string]: Style } = {}

-- First matching prefix wins, which is why Config.Map.Icons.Rules is ordered rather
-- than a plain map: "city_park" has to be tested before "park" would swallow it, and a
-- hash lookup has no way to express that.
function MapIcons.StyleFor(placeId: string): Style
	local known = cache[placeId]
	if known ~= nil then
		return known
	end

	-- An id no rule claims is a generated address -- `apt_31`, `est_4`, whatever the next
	-- run of gen_city.py invents -- so it is filed as a street rather than as a landmark.
	-- Guessing generously here is how the sheet went back to being a wall of dots.
	local style: Style = {
		color = ICONS.Default.color,
		size = ICONS.Default.size,
		priority = ICONS.Default.priority,
		kind = "place",
		tier = "street",
	}

	for _, rule in ICONS.Rules do
		if string.sub(placeId, 1, #rule.prefix) == rule.prefix then
			local kind = ICONS.Kinds[rule.kind]
			if kind ~= nil then
				-- Said out loud rather than defaulted. A rule with no tier would draw at
				-- whatever tier the fallback happened to be, which is either a landmark that
				-- is not one or a landmark that never appears -- and both look like the map
				-- is broken rather than like Config is missing a word.
				if DETAIL_ZOOM[rule.tier] == nil then
					error(
						`MapIcons: rule "{rule.prefix}" has tier "{rule.tier}", which is not one of `
							.. `Config.Map.DetailZoom. Add the tier there or fix the rule.`
					)
				end
				style = {
					color = kind.color,
					size = kind.size,
					priority = kind.priority,
					kind = rule.kind,
					tier = rule.tier,
				}
			end
			break
		end
	end

	cache[placeId] = style
	return style
end

-- The gang colour for a side. Read off the pushed data rather than out of content,
-- because the client has no business requiring a server content module -- and because
-- the colours the map draws must be the ones the server actually assigned to those four
-- bosses, not a second copy that agrees today.
function MapIcons.RegionColor(data: MapData, regionId: string): Color3?
	for _, region in data.regions do
		if region.id == regionId then
			return region.color
		end
	end
	return nil
end

-- The gang's name for a side. Falls back to the id so a region the client was told
-- about but has no name for still reads as something rather than as blank.
function MapIcons.RegionName(data: MapData, regionId: string): string
	for _, region in data.regions do
		if region.id == regionId then
			return region.name
		end
	end
	return regionId
end

return MapIcons
