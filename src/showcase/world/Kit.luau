--!strict
-- One primitive. The block-out and its props need nothing else.
--
-- Deliberately not v1's Kit: that one lives in the AGES tree and carries materials, signs,
-- planters and a dozen options this place has no use for.

local CollectionService = game:GetService("CollectionService")

export type Options = {
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	collide: boolean?,
	shadow: boolean?,
	shape: Enum.PartType?,
	-- CollectionService tags. Every interactive system in src/showcase finds its geometry this
	-- way, so a prop is wired by being tagged and by nothing else.
	tags: { string }?,
	-- Attributes. **Strings only** -- the bake encoder in tools/rbxmx.py writes type 0x02 and
	-- nothing else, so a numeric attribute would survive at runtime and vanish from the baked
	-- asset. Anything numeric belongs in the service's config table instead.
	attrs: { [string]: string }?,
}

local Kit = {}

function Kit.Block(parent: Instance, name: string, centre: Vector3, size: Vector3, colour: Color3, options: Options?): BasePart
	local o = options or {} :: Options
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(centre)
	part.Anchored = true
	part.Color = colour
	-- Concrete by default. Section 02's build order puts materials after lighting, and a
	-- block-out that is already textured is one nobody is willing to move.
	part.Material = o.material or Enum.Material.Concrete
	part.Transparency = o.transparency or 0
	part.Reflectance = o.reflectance or 0
	part.CanCollide = if o.collide == nil then true else o.collide
	part.CastShadow = if o.shadow == nil then true else o.shadow
	if o.shape ~= nil then
		part.Shape = o.shape
	end
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent

	if o.attrs ~= nil then
		for key, value in o.attrs do
			part:SetAttribute(key, value)
		end
	end
	if o.tags ~= nil then
		for _, tag in o.tags do
			CollectionService:AddTag(part, tag)
		end
	end
	return part
end

return Kit
