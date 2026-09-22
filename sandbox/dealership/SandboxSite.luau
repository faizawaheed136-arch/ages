--!strict
--[[
	The open space Meridian Motors is designed in, away from the AGES map.

	Only the surroundings the design depends on: a grass field at the height the builder calls its
	floor, and the two roads its real plot has -- one along the south edge, which the showroom and
	the lot's driveway face, and one down the west side with its pavement. The dealership's own
	sidewalk, kerbs and driveway are the builder's; this is only what they meet.

	Laid relative to the same corner the dealership is built from, so the relationship between the
	two is exactly the one it will have in AGES, where the plot is at (-280, 1.95, 1940).
]]

local SandboxSite = {}

SandboxSite.ModelName = "SandboxSite"

local GRASS = Color3.fromRGB(96, 140, 72)
local ASPHALT = Color3.fromRGB(48, 50, 54)
local LINE = Color3.fromRGB(236, 236, 230)
local PAVING = Color3.fromRGB(176, 174, 168)

local function box(parent: Instance, corner: CFrame, name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0)
	part.CFrame = corner * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function SandboxSite.Build(corner: CFrame, parent: Instance): Model
	local existing = parent:FindFirstChild(SandboxSite.ModelName)
	if existing then
		existing:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = SandboxSite.ModelName

	-- The field, its top level with the plot's grass.
	box(model, corner, "Grass", -220, 520, -4, 0, -160, 420, GRASS, Enum.Material.Grass)

	-- The south road: the frontage the showroom and the driveway face.
	box(model, corner, "SouthRoad", -220, 520, 0, 0.05, -38, -4, ASPHALT, Enum.Material.Asphalt)
	for x = -210, 510, 16 do
		box(model, corner, "Dash", x, x + 8, 0.05, 0.08, -21.3, -20.7, LINE, Enum.Material.SmoothPlastic)
	end
	box(model, corner, "Kerb", -220, 520, 0, 0.3, -4, -3.4, PAVING, Enum.Material.Concrete)

	-- The west road and its pavement, running north past the lot.
	box(model, corner, "WestRoad", -60, -26, 0, 0.05, -38, 420, ASPHALT, Enum.Material.Asphalt)
	for z = -30, 410, 16 do
		box(model, corner, "Dash", -43.3, -42.7, 0.05, 0.08, z, z + 8, LINE, Enum.Material.SmoothPlastic)
	end
	box(model, corner, "WestPavement", -24, -10, 0, 0.25, -4, 420, PAVING, Enum.Material.Pebble)

	model.Parent = parent
	return model
end

return SandboxSite
