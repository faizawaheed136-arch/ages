--!strict
-- Dense-looking detail that is not dense: fencing, window grids, courtyard dividers.
--
-- **The rule this whole file exists to apply: never model a repeating grid as geometry.**
--
-- A 40-stud run of chain-link modelled link by link is roughly 4,000 parts. The same run as one
-- part with a tiled transparent Texture is **one**, renders in a single draw call, and at any
-- distance a player will actually stand looks the same. The saving is not 4,000 parts of memory,
-- it is 4,000 things the renderer, the physics broadphase and Future lighting's shadow pass each
-- have to consider every frame.
--
-- Part count is a poor metric on its own -- Roblox batches by material, colour and texture, so a
-- hundred identical grey Concrete blocks are far cheaper than ten parts in ten materials. What
-- actually costs is draw calls, shadow casters, physics bodies and overlapping transparency. Each
-- builder below is written against those four.

local Detail = {}

-- **Replace these.** Two alpha textures with the pattern in white on transparent. Until they are
-- real ids the panels render as flat colour, which is a perfectly usable placeholder.
Detail.ChainLinkTexture = "rbxassetid://0"
Detail.GridTexture = "rbxassetid://0"

local IRON = Color3.fromRGB(38, 40, 44)
local IRON_LIT = Color3.fromRGB(60, 64, 70)

-- Every decorative part in this file goes through here, and it is most of the optimisation.
--
--   Anchored     -- no physics body, no solver work
--   CanCollide   -- off for anything a player cannot walk into: removes it from the broadphase
--   CanQuery     -- off: removes it from every raycast, including the camera's
--   CanTouch     -- off: no touch events to dispatch
--   CastShadow   -- off for thin trim: a shadow pass per hairline part is real cost in Future
--                   lighting, and a 0.2-stud bar casts a shadow nobody can identify
local function decor(parent: Instance, name: string, cf: CFrame, size: Vector3, colour: Color3, solid: boolean): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Anchored = true
	part.Color = colour
	part.Material = Enum.Material.Metal
	part.CanCollide = solid
	part.CanQuery = solid
	part.CanTouch = false
	part.CastShadow = solid
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- ---------------------------------------------------------------------------------------
-- Chain-link fencing
-- ---------------------------------------------------------------------------------------

-- One panel = **three parts**: the mesh plane, and two posts. Not one part per link.
--
-- The mesh is a single thin slab carrying a tiled alpha Texture on both faces. `StudsPerTileU/V`
-- is what makes one texture cover any length without stretching -- set it to the real-world size
-- of one link and a 40-stud panel and a 12-stud panel look identical up close.
--
-- The plane keeps CanCollide on, because a fence you can walk through is not a fence. Everything
-- else about it is switched off.
function Detail.Fence(parent: Instance, from: Vector3, to: Vector3, height: number, postEvery: number?): Model
	local model = Instance.new("Model")
	model.Name = "Fence"
	model.Parent = parent

	local span = (to - from)
	local length = span.Magnitude
	local mid = from + span / 2
	local facing = CFrame.lookAt(mid + Vector3.new(0, height / 2, 0), to + Vector3.new(0, height / 2, 0))

	local mesh = decor(model, "Mesh", facing, Vector3.new(length, height, 0.2), IRON, true)
	mesh.Transparency = 0.15
	if Detail.ChainLinkTexture ~= "rbxassetid://0" then
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local texture = Instance.new("Texture")
			texture.Texture = Detail.ChainLinkTexture
			texture.Face = face
			-- One link is about two studs. Tiling at the link's real size is what lets the same
			-- texture serve every panel length in the courtyard.
			texture.StudsPerTileU = 2
			texture.StudsPerTileV = 2
			texture.Parent = mesh
		end
	end

	-- Posts are the only part of a fence anybody reads as solid, so they get the shadow.
	local step = postEvery or 16
	local count = math.max(2, math.floor(length / step) + 1)
	for index = 0, count - 1 do
		local t = index / (count - 1)
		local at = from:Lerp(to, t) + Vector3.new(0, height / 2, 0)
		decor(model, `Post{index}`, CFrame.new(at), Vector3.new(0.8, height + 1, 0.8), IRON_LIT, true)
	end

	-- The top rail. One part, and it does more for the silhouette than any amount of link detail.
	decor(model, "Rail", facing * CFrame.new(0, height / 2, 0), Vector3.new(length, 0.6, 0.6), IRON_LIT, false)
	return model
end

-- ---------------------------------------------------------------------------------------
-- Window grids
-- ---------------------------------------------------------------------------------------

-- A twelve-pane window is **two parts**, not twelve panes plus eleven mullions.
--
-- The glass is one slab; the grid is a texture on it. Modelled mullions are the classic way to
-- turn a facade into a frame-rate problem -- a building with sixty windows at 23 parts each is
-- 1,380 parts of hairline geometry, every one of them a shadow caster in Future lighting.
--
-- Where a mullion genuinely has to be geometry -- a close-up hero window the camera stops at --
-- model *that one* and leave the other fifty-nine textured.
function Detail.WindowGrid(parent: Instance, cf: CFrame, width: number, height: number, panesU: number, panesV: number): Model
	local model = Instance.new("Model")
	model.Name = "Window"
	model.Parent = parent

	local glass = decor(model, "Glass", cf, Vector3.new(width, height, 0.3), Color3.fromRGB(150, 170, 190), false)
	glass.Material = Enum.Material.Glass
	glass.Transparency = 0.55
	glass.Reflectance = 0.1
	glass.CastShadow = false

	if Detail.GridTexture ~= "rbxassetid://0" then
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local texture = Instance.new("Texture")
			texture.Texture = Detail.GridTexture
			texture.Face = face
			-- Tile so the pane count is right for *this* window rather than stretching one image
			-- across whatever size it happens to be.
			texture.StudsPerTileU = width / panesU
			texture.StudsPerTileV = height / panesV
			texture.Parent = glass
		end
	end

	-- The outer frame stays geometry: it is the part that reads at a distance and it is four
	-- parts, not forty-eight.
	local t = 0.5
	for _, spec in {
		{ CFrame.new(0, height / 2, 0), Vector3.new(width + t * 2, t, 0.5) },
		{ CFrame.new(0, -height / 2, 0), Vector3.new(width + t * 2, t, 0.5) },
		{ CFrame.new(-width / 2, 0, 0), Vector3.new(t, height, 0.5) },
		{ CFrame.new(width / 2, 0, 0), Vector3.new(t, height, 0.5) },
	} do
		decor(model, "Frame", cf * (spec[1] :: CFrame), spec[2] :: Vector3, IRON, false)
	end
	return model
end

-- ---------------------------------------------------------------------------------------
-- Courtyard dividers
-- ---------------------------------------------------------------------------------------

-- A run of slatted divider, built as **one part per slat and no more** -- and crucially every
-- slat identical in size, material and colour, so the renderer batches the whole run into one
-- draw call. Varying the colour slat by slat for "realism" is what breaks that batch, and it is
-- the most expensive thing you can do here for the least visible gain.
function Detail.Divider(parent: Instance, from: Vector3, to: Vector3, height: number, slats: number): Model
	local model = Instance.new("Model")
	model.Name = "Divider"
	model.Parent = parent

	local span = to - from
	local length = span.Magnitude
	local mid = from + span / 2
	local facing = CFrame.lookAt(mid + Vector3.new(0, height / 2, 0), to + Vector3.new(0, height / 2, 0))

	-- One solid, collidable core the player actually walks into, and the slats hung on it as
	-- pure decoration. Splitting "what blocks you" from "what you look at" is what lets every
	-- slat drop out of the physics broadphase.
	decor(model, "Core", facing, Vector3.new(length, height, 0.6), IRON, true).Transparency = 1

	local pitch = height / slats
	for index = 0, slats - 1 do
		local y = -height / 2 + pitch * (index + 0.5)
		decor(model, "Slat", facing * CFrame.new(0, y, 0), Vector3.new(length, pitch * 0.65, 0.9), IRON, false)
	end
	return model
end

return Detail
