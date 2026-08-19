--!strict
-- The world, painted into a square as rectangles. Used by the full sheet and by the
-- corner dial, which is the whole reason it is a module and not a function in one of them.
--
-- **Why the ground is drawn at all.** Both surfaces used to be a dark square with coloured
-- dots on it, and a dot is a label for a place, not a picture of one. You could be told
-- roughly which way the bank was; you could not look at the map and recognise the street
-- you were standing in. Streets, blocks and the coastline are the part a player reads
-- without being taught, and they were the part that was missing.
--
-- **Why it is safe to draw now.** Minimap's header used to say there was no terrain art
-- here and none planned, because a painted map is a second copy of the world and this
-- tree's most expensive recurring defect is one measurement written down twice. That
-- objection was right and it is the reason the copy is generated rather than drawn:
-- `tools/gen_mapshapes.py` reads the same `.rbxmx` files the game place mounts, and
-- `check_mapshapes` in `tools/check.py` fails the build if the two ever disagree. The
-- copy cannot go stale quietly, which is the only thing that made it a bad idea.
--
-- **What it does not do.** Nothing here reads the player, the zoom or the clock. It fills
-- a frame once and returns, and the two callers move that frame afterwards -- which is
-- what makes the dial affordable. See `Paint` for that.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local WorldMap = require(ReplicatedStorage:WaitForChild("WorldMap"))
local MapShapes = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("MapShapes"))

local SHAPES = Config.Map.Shapes
local PANEL = Config.UI.Palette.Panel

local MapTerrain = {}

-- The colour a world part should be on a map, which is not the colour it is in the world.
--
-- Dropping the raw colours on the sheet was the first version and it looks like somebody
-- pasted a screenshot into the menu: the ground shouts, and the icons and the territory
-- lines -- the two things the map exists to say -- have to fight it to be seen. So each
-- colour is pulled toward its own grey and then toward the panel it sits on. The world
-- keeps its shape and gives up its volume, which is what a background is.
function MapTerrain.Toned(color: Color3, saturation: number, tint: number): Color3
	local grey = (color.R + color.G + color.B) / 3
	local muted = Color3.new(
		grey + (color.R - grey) * saturation,
		grey + (color.G - grey) * saturation,
		grey + (color.B - grey) * saturation
	)
	return PANEL:Lerp(muted, tint)
end

-- Fill `into` with the world, and hand back how many rectangles that took.
--
-- `into` must be the frame that *is* the world square: everything is positioned and sized
-- in scale, so the caller resizes or moves that one frame and the whole town follows.
-- That is the difference between a dial that costs one property write per heartbeat and
-- one that costs two hundred and thirty-seven.
--
-- `squarePixels` is how wide `into` is on screen when the whole world is showing. It is
-- used for one thing -- deciding which rectangles are too small to be worth an instance --
-- and it is passed in rather than measured because `AbsoluteSize` is zero on the frame
-- Roblox has not laid out yet, which is every frame at the moment the map data arrives.
--
-- `groundZ` and `buildingZ` are the caller's own layer numbers. Buildings must sit above
-- ground or a roof is covered by the car park it stands in, but which integers those are
-- is the caller's business, and the dial and the sheet do not share a stack.
function MapTerrain.Paint(into: Frame, bounds: WorldMap.Bounds, squarePixels: number, groundZ: number, buildingZ: number): number
	for _, child in into:GetChildren() do
		child:Destroy()
	end

	local width = bounds.maxX - bounds.minX
	local depth = bounds.maxZ - bounds.minZ
	if width <= 0 or depth <= 0 then
		return 0
	end

	local pixelsPerStud = squarePixels / width
	local drawn = 0

	-- The shapes arrive already in painter's order -- ground low to high, then buildings --
	-- decided in the generator so that no client ever sorts a thousand entries. Walking
	-- them in order and letting child order do the rest is the point of that.
	for _, shape in MapShapes.All do
		-- Anything under a pixel is an instance that costs a frame and draws nothing. Most
		-- of what this removes are kerbs and lane markings, which are noise on a map even
		-- when they are visible.
		local shorter = math.min(shape.widthStuds, shape.depthStuds) * pixelsPerStud
		if shorter < SHAPES.MinPixels then
			continue
		end

		local u, v = WorldMap.Normalize(bounds, shape.x, shape.z)
		local building = shape.kind == "building"

		local block = Instance.new("Frame")
		block.Name = shape.kind
		block.AnchorPoint = Vector2.new(0.5, 0.5)
		block.Position = UDim2.fromScale(u, v)
		-- Sized in scale, unlike every icon on either map. A building is a piece of ground
		-- and has to grow with the ground when the sheet is zoomed; an icon is a label for
		-- a place and has to stay legible, which is why that one is in offset.
		block.Size = UDim2.fromScale(shape.widthStuds / width, shape.depthStuds / depth)
		block.Rotation = shape.rotationDegrees
		block.BackgroundColor3 = MapTerrain.Toned(
			shape.color,
			if building then SHAPES.BuildingSaturation else SHAPES.SurfaceSaturation,
			if building then SHAPES.BuildingTint else SHAPES.SurfaceTint
		)
		block.BorderSizePixel = 0
		block.ZIndex = if building then buildingZ else groundZ
		block.Parent = into
		drawn += 1
	end

	return drawn
end

return MapTerrain
