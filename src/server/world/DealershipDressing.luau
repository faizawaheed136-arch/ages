--!strict
--[[
	Dresses Meridian Motors: swaps each of the builder's block stand-ins for the real model that
	content/DealershipProps names, fitted to the stand-in's space.

	The builder lays every chair, tree, planter, sofa and bin as primitives, because it must run
	with nothing uploaded -- offline in the sandbox exporter, from the command bar, in a place
	that has never seen the props. A stand-in is a Model with a `Prop` attribute (the key into
	DealershipProps), and optionally `Facing` (degrees, 0 = its front to local -Z, the same
	convention the builder's chairs use) and `Variant` (which set of parts to keep from a pack).

	At server start this loads each prop's asset once with InsertService, then for every
	stand-in: clones it, keeps the variant's parts or drops the listed ones, turns it to the
	stand-in's facing plus the prop's own yaw, scales it to the stand-in (by height, by width
	across its facing, or to fit its plan), stands it on the stand-in's floor at its centre, and
	removes the stand-in. Everything is worked out in the dealership's own frame -- its `Origin`
	attribute -- so it holds wherever the dealership is placed.

	Nothing here can leave a hole. A prop with no asset id, an asset that will not load (not yet
	through moderation, or owned by someone the place's creator is not), or a swap that fails
	leaves its stand-in exactly where it was, and says so once.
]]

local InsertService = game:GetService("InsertService")

local DealershipDressing = {}

DealershipDressing.PropAttribute = "Prop"
-- Set on a model once it has replaced its stand-in, so a second Dress leaves it alone.
DealershipDressing.DressedAttribute = "DressedProp"

-- What DealershipDressing reads from content/DealershipProps; declared here so the sandbox can
-- pass its own copy without this module requiring the game's content tree.
export type Prop = {
	key: string,
	assetId: number?,
	fit: "height" | "width" | "footprint",
	yaw: number,
	collide: boolean,
	drop: { string },
	variants: { { string } },
}

-- One loaded template per asset; false once it has failed, so it is tried once, not per stand-in.
local templates: { [number]: Instance | false } = {}

local function template(prop: Prop): Instance?
	local id = prop.assetId
	if id == nil then
		return nil
	end
	local cached = templates[id]
	if cached ~= nil then
		return if cached then cached else nil
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(id)
	end)
	if not ok or result == nil then
		warn(`[AGES dealership] prop "{prop.key}" (asset {id}) did not load, so its block stand-ins stay: {result}`)
		templates[id] = false
		return nil
	end
	-- LoadAsset wraps the asset in a Model; an uploaded model is usually one Model inside that.
	local container = result :: Instance
	local children = container:GetChildren()
	local root = if #children == 1 and children[1]:IsA("Model") then children[1] else container
	templates[id] = root
	return root
end

-- The box, in the dealership's frame, around every part under `root`.
local function localBounds(root: Instance, origin: CFrame): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	local function add(part: BasePart)
		local half = part.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local world = part.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
					local p = origin:PointToObjectSpace(world)
					lo = lo:Min(p)
					hi = hi:Max(p)
				end
			end
		end
	end
	if root:IsA("BasePart") then
		add(root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			add(d)
		end
	end
	return lo, hi
end

-- Keep only the variant's parts, or drop the listed ones. A filter that would empty the model is
-- ignored: names can come out of the importer differently from the file, and a whole pack is
-- better than nothing.
local function filter(model: Instance, prop: Prop, variant: number)
	local keep: { [string]: boolean }? = nil
	if #prop.variants > 0 then
		local names: { [string]: boolean } = {}
		for _, name in prop.variants[(variant - 1) % #prop.variants + 1] do
			names[name] = true
		end
		keep = names
	end
	local drop: { [string]: boolean } = {}
	for _, name in prop.drop do
		drop[name] = true
	end
	local doomed: { BasePart } = {}
	local kept = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if drop[d.Name] or (keep ~= nil and not keep[d.Name]) then
				table.insert(doomed, d)
			else
				kept += 1
			end
		end
	end
	if kept > 0 then
		for _, d in doomed do
			d:Destroy()
		end
	end
end

local function dress(standIn: Model, prop: Prop, source: Instance, origin: CFrame)
	local facing = standIn:GetAttribute("Facing")
	local variant = standIn:GetAttribute("Variant")
	local yaw = (if typeof(facing) == "number" then facing else 0) + prop.yaw

	local model = Instance.new("Model")
	model.Name = standIn.Name
	for _, child in source:GetChildren() do
		child:Clone().Parent = model
	end
	filter(model, prop, if typeof(variant) == "number" then variant else 1)

	-- Turn it about its own centre to face the way the stand-in does, in the dealership's frame.
	local lo, hi = localBounds(model, origin)
	model.WorldPivot = origin * CFrame.new((lo + hi) / 2)
	model:PivotTo(origin * CFrame.new((lo + hi) / 2) * CFrame.Angles(0, math.rad(yaw), 0))

	-- Scale it to the stand-in.
	local slo, shi = localBounds(standIn, origin)
	local want = shi - slo
	lo, hi = localBounds(model, origin)
	local have = hi - lo
	local across = math.abs(math.sin(math.rad(yaw))) > 0.7 -- turned side-on: its width runs along Z
	local factor
	if prop.fit == "height" then
		factor = want.Y / have.Y
	elseif prop.fit == "width" then
		factor = if across then want.Z / have.Z else want.X / have.X
	else
		factor = math.min(want.X / have.X, want.Z / have.Z)
	end
	model:ScaleTo(model:GetScale() * factor)

	-- Stand it on the stand-in's floor, at the stand-in's centre.
	lo, hi = localBounds(model, origin)
	local target = Vector3.new((slo.X + shi.X) / 2, slo.Y, (slo.Z + shi.Z) / 2)
	local current = Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	model:PivotTo(model:GetPivot() + origin:VectorToWorldSpace(target - current))

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = prop.collide
			d.CanTouch = false
			-- Out of every raycast, like the builder's glass: Ground.SpotAt looks along a ray
			-- from the counter to find where a bought car parks, and a prop must not block it.
			d.CanQuery = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	model:SetAttribute(DealershipDressing.DressedAttribute, prop.key)
	model.Parent = standIn.Parent
	standIn:Destroy()
end

--[[
	Swap every stand-in under `dealership` whose prop has an uploaded model. Returns how many were
	swapped and how many stayed as blocks.
]]
function DealershipDressing.Dress(dealership: Model, props: { [string]: Prop }): (number, number)
	local origin = dealership:GetAttribute("Origin")
	if typeof(origin) ~= "CFrame" then
		warn(`[AGES dealership] {dealership:GetFullName()} has no Origin attribute, so its props cannot be placed`)
		return 0, 0
	end
	local swapped, kept = 0, 0
	for _, d in dealership:GetDescendants() do
		local key = d:GetAttribute(DealershipDressing.PropAttribute)
		if typeof(key) ~= "string" or not d:IsA("Model") or d.Parent == nil then
			continue
		end
		local prop = props[key]
		local source = if prop then template(prop) else nil
		if prop == nil or source == nil then
			kept += 1
			continue
		end
		local ok, err = pcall(dress, d, prop, source, origin)
		if ok then
			swapped += 1
		else
			kept += 1
			warn(`[AGES dealership] could not place "{key}" at {d:GetFullName()}, so its stand-in stays: {err}`)
		end
	end
	return swapped, kept
end

return DealershipDressing
