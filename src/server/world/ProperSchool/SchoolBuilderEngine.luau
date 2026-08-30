--!strict
-- The primitives every part of the new school is built from.
--
-- Three rules hold across the whole module, and they are the reason it exists rather than
-- callers writing `Instance.new("Part")` themselves:
--
--   * **Everything is anchored.** An unanchored building falls over on the first frame.
--   * **Every surface is Smooth.** Roblox still defaults `TopSurface` to `Studs` and
--     `BottomSurface` to `Inlet` on a fresh Part. Leave them and every slab in the building
--     gets a ring of bumps along its top edge, which is the single most recognisable "this was
--     made in 2010" tell there is. Nothing else in this file matters if that is wrong.
--   * **Every position is snapped to a grid.** Two walls meant to be flush, placed at
--     coordinates a ten-thousandth apart, produce a seam that flickers as the camera moves --
--     z-fighting. Snapping makes flush actually flush, and it makes hand-written coordinates
--     land where you meant rather than where the arithmetic drifted to.

local Engine = {}

-- ---------------------------------------------------------------------------------------
-- Standard layout parameters
-- ---------------------------------------------------------------------------------------

-- A quarter stud. Fine enough for trim and glazing bars, coarse enough that accumulated
-- floating-point error from repeated addition can never open a visible seam.
local GRID = 0.25

-- Glass that reads as glass. Fully transparent glass is a hole; opaque glass is a wall. The
-- pane also takes a little reflectance, which is what separates a window from a blue rectangle
-- under Future lighting.
local GLASS_TRANSPARENCY = 0.5
local GLASS_REFLECTANCE = 0.1

-- How much of a wall's thickness the pane occupies. Less than the wall, so the opening reads as
-- having a reveal -- a pane flush with both faces looks like film stretched over a hole.
local GLASS_DEPTH_SHARE = 0.4

-- ---------------------------------------------------------------------------------------
-- Internals
-- ---------------------------------------------------------------------------------------

local function snap(value: Vector3): Vector3
	return Vector3.new(
		math.round(value.X / GRID) * GRID,
		math.round(value.Y / GRID) * GRID,
		math.round(value.Z / GRID) * GRID
	)
end

-- A rotation from degrees, in the same Y-X-Z order the `Orientation` property uses.
--
-- Built from `CFrame.Angles` rather than `CFrame.fromOrientation` because the headless harness
-- that bakes this school to an asset reimplements only enough of CFrame to carry a translation
-- times a rotation. Staying inside that subset is what makes the module bakeable at all.
local function rotationOf(orientation: Vector3): CFrame
	return CFrame.Angles(0, math.rad(orientation.Y), 0)
		* CFrame.Angles(math.rad(orientation.X), 0, 0)
		* CFrame.Angles(0, 0, math.rad(orientation.Z))
end

-- Every part in the school comes through here, so the three rules above are enforced in exactly
-- one place and cannot drift between call sites.
--
-- **Placement is a CFrame, never `.Position` plus `.Orientation`.** Those two are equivalent in
-- Studio but not everywhere else: the asset bake records what a part was *assigned*, and a part
-- given a Position and an Orientation separately bakes with its rotation thrown away. One CFrame
-- carries both, so what Studio shows and what the bake writes cannot disagree.
local function spawn(
	name: string,
	position: Vector3,
	size: Vector3,
	material: Enum.Material,
	color: Color3,
	parent: Instance,
	orientation: Vector3?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	-- The identity case is skipped rather than multiplied through: an unrotated part is the
	-- common one, and `CFrame.new()` with no arguments is not something every environment this
	-- module runs under implements.
	local frame = CFrame.new(snap(position))
	if orientation ~= nil then
		frame = frame * rotationOf(orientation)
	end
	part.CFrame = frame
	part.Anchored = true
	part.CastShadow = true
	part.Material = material
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function assertPositive(size: Vector3, what: string)
	if size.X <= 0 or size.Y <= 0 or size.Z <= 0 then
		error(`[SchoolBuilderEngine] {what} must be positive on every axis, got {size}`, 3)
	end
end

-- ---------------------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------------------

-- A single wall panel.
--
-- `orientation` is in degrees and is set through the `Orientation` property rather than a
-- CFrame, so the numbers here are the same numbers Studio's property panel shows -- which is
-- what you want when you are checking a build by eye against the code that made it.
function Engine.CreateWall(
	position: Vector3,
	size: Vector3,
	orientation: Vector3,
	material: Enum.Material,
	color: Color3,
	parent: Instance
): Part
	assertPositive(size, "wall size")
	return spawn("Wall", position, size, material, color, parent, orientation)
end

-- A floor plate.
--
-- Deliberately not a thin wall with different arguments: a floor is the one surface players
-- stand on, so it is worth having a call that cannot be given an orientation by accident and
-- tilted half a degree.
function Engine.CreateFloor(
	position: Vector3,
	size: Vector3,
	material: Enum.Material,
	color: Color3,
	parent: Instance
): Part
	assertPositive(size, "floor size")
	return spawn("Floor", position, size, material, color, parent)
end

-- A wall with a window in it.
--
-- **Roblox cannot punch a hole in a Part, so this frames around one.** There is no runtime
-- boolean subtraction worth using here -- CSG at build time is slow, produces unions that cost
-- more to render than the parts they replace, and breaks streaming. What a careful builder does
-- instead is exactly what a real one does: two piers either side of the opening, a header over
-- it, a sill under it, and the pane in the gap. Five parts, all primitives, all cheap.
--
-- The wall runs along its local X. `wallSize.X` is its length, `.Y` its height, `.Z` its
-- thickness; `windowSize.X` and `.Y` are the opening, and `windowSize.Z` is ignored -- the pane
-- takes its depth from the wall so it can never end up thicker than what it sits in.
--
-- `orientation` is optional and trails the given signature, so a wall that does not run along
-- world X is still one call.
function Engine.CreateWindowCutout(
	wallPosition: Vector3,
	wallSize: Vector3,
	windowSize: Vector3,
	parent: Instance,
	orientation: Vector3?,
	material: Enum.Material?,
	color: Color3?
): Model
	assertPositive(wallSize, "wall size")
	assertPositive(windowSize, "window size")
	if windowSize.X >= wallSize.X or windowSize.Y >= wallSize.Y then
		error(
			`[SchoolBuilderEngine] window {windowSize.X}x{windowSize.Y} does not fit inside wall`
				.. ` {wallSize.X}x{wallSize.Y} -- it would leave a pier or a header of zero width,`
				.. ` and a zero-size Part is clamped to 0.05 rather than omitted.`,
			2
		)
	end

	local wallMaterial = material or Enum.Material.SmoothPlastic
	local wallColor = color or Color3.fromRGB(226, 228, 232)

	local model = Instance.new("Model")
	model.Name = "WindowWall"

	local pierWidth = (wallSize.X - windowSize.X) / 2
	local bandHeight = (wallSize.Y - windowSize.Y) / 2
	local glassDepth = wallSize.Z * GLASS_DEPTH_SHARE

	-- Laid out in the wall's own frame first, then moved as one. Building in local space and
	-- transforming once is what lets the same code serve any orientation without every piece
	-- needing its own trigonometry.
	local pieces: { { name: string, offset: Vector3, size: Vector3 } } = {
		{
			name = "PierLeft",
			offset = Vector3.new(-(windowSize.X + pierWidth) / 2, 0, 0),
			size = Vector3.new(pierWidth, wallSize.Y, wallSize.Z),
		},
		{
			name = "PierRight",
			offset = Vector3.new((windowSize.X + pierWidth) / 2, 0, 0),
			size = Vector3.new(pierWidth, wallSize.Y, wallSize.Z),
		},
		{
			name = "Header",
			offset = Vector3.new(0, (windowSize.Y + bandHeight) / 2, 0),
			size = Vector3.new(windowSize.X, bandHeight, wallSize.Z),
		},
		{
			name = "Sill",
			offset = Vector3.new(0, -(windowSize.Y + bandHeight) / 2, 0),
			size = Vector3.new(windowSize.X, bandHeight, wallSize.Z),
		},
	}

	local base = CFrame.new(snap(wallPosition))
	if orientation ~= nil then
		base = base * rotationOf(orientation)
	end

	for _, piece in pieces do
		local part = spawn(piece.name, wallPosition, piece.size, wallMaterial, wallColor, model)
		part.CFrame = base * CFrame.new(piece.offset)
	end

	local glass = spawn(
		"Glass",
		wallPosition,
		Vector3.new(windowSize.X, windowSize.Y, glassDepth),
		Enum.Material.Glass,
		Color3.fromRGB(198, 220, 236),
		model
	)
	glass.CFrame = base
	glass.Transparency = GLASS_TRANSPARENCY
	glass.Reflectance = GLASS_REFLECTANCE

	model.PrimaryPart = glass
	model.Parent = parent
	return model
end

return Engine
