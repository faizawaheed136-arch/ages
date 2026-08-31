--!strict
-- One primitive. The block-out needs nothing else.
--
-- Deliberately not v1's Kit: that one lives in the AGES tree and carries materials, signs,
-- planters and a dozen options this place has no use for. A showcase in its own place should
-- not reach across into another place's world code for a box.

local Kit = {}

function Kit.Block(parent: Instance, name: string, centre: Vector3, size: Vector3, colour: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(centre)
	part.Anchored = true
	part.Color = colour
	-- Concrete everywhere on purpose. Section 02's build order puts materials after lighting,
	-- and a block-out that is already textured is one nobody is willing to move.
	part.Material = Enum.Material.Concrete
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

return Kit
