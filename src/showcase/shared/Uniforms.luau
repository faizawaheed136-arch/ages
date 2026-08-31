--!strict
-- The uniform catalogue, and the only place in the project an asset id appears.
--
-- Shared, so the UI can draw names and blurbs without a round trip. But the client never sends
-- an id -- it sends a **key** from this table and the server looks the id up. A remote that
-- accepts an assetId from the client is a remote that will eventually be handed somebody else's
-- asset, or a decal that is not a jacket. The allowlist is the whole security model here.

export type Layer = {
	AssetId: number,
	AccessoryType: Enum.AccessoryType,
	Order: number,
	Puffiness: number?,
}

export type Uniform = {
	Key: string,
	Name: string,
	Blurb: string,
	Shirt: number,
	Pants: number,
	Layers: { Layer },
}

local Uniforms = {}

-- **Why layered clothing and not just a shirt texture.**
--
-- "Structured, high-collared, tucked in" and "loose-fit" are differences in *silhouette*, and a
-- Shirt is a texture painted onto the body mesh -- it has no shape of its own and cannot be
-- loose. So each variant below carries a Shirt and Pants for the fabric, and layered Accessory
-- assets for the shape.
--
-- `Puffiness` is what separates the two: 0 pulls the garment onto the body (structured, tucked),
-- higher values stand it off (loose, worn open). It is the single property doing the most work
-- in this file.
--
-- `Order` is the stacking order outward from the skin. Pants under jacket, always.
--
-- **The ids are placeholders.** Replace them with your own uploads. Until you do, the character
-- renders as the default avatar and *nothing errors* -- ApplyDescription treats id 0 as "none".
-- That silence is exactly why this paragraph is here.
Uniforms.Catalogue = {
	{
		Key = "academy",
		Name = "Academy Standard",
		Blurb = "High collar, structured shoulder, tucked. Issue uniform.",
		Shirt = 0,
		Pants = 0,
		Layers = {
			{ AssetId = 0, AccessoryType = Enum.AccessoryType.Pants, Order = 1, Puffiness = 0 },
			{ AssetId = 0, AccessoryType = Enum.AccessoryType.Jacket, Order = 2, Puffiness = 0 },
		},
	},
	{
		Key = "combat",
		Name = "Combat Variation",
		Blurb = "Untucked, open collar, cut loose at the shoulder for movement.",
		Shirt = 0,
		Pants = 0,
		Layers = {
			{ AssetId = 0, AccessoryType = Enum.AccessoryType.Pants, Order = 1, Puffiness = 0.15 },
			{ AssetId = 0, AccessoryType = Enum.AccessoryType.Jacket, Order = 2, Puffiness = 0.45 },
		},
	},
} :: { Uniform }

-- Keyed lookup, built once. The server validates against this and nothing else.
Uniforms.ByKey = {} :: { [string]: Uniform }
for _, uniform in Uniforms.Catalogue do
	Uniforms.ByKey[uniform.Key] = uniform
end

-- What a locker falls back to if a player has never chosen. Also what "reset" means.
Uniforms.Default = "academy"

return Uniforms
