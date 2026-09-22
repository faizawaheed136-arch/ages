--[[
	Writes an instance tree built under RobloxStub as a Rojo model file (.model.json), which
	`rojo build` then turns into a real .rbxmx -- attributes, tags, CFrames and all.

	Spliced after the stub and the builders by sandbox/dealership/export.py, which also supplies
	EXPORT_PLAN: which builder to run, at which corner, under which name.
]]

local function num(n: number): string
	if n ~= n or n == math.huge or n == -math.huge then
		error("RobloxStub export: a property is NaN or infinite")
	end
	if math.abs(n) < 1e-9 then
		return "0"
	end
	local s = string.format("%.6f", n)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

local function jstring(s: string): string
	local escaped = string.gsub(s, '[%c"\\]', function(c)
		if c == "\n" then
			return "\\n"
		elseif c == '"' then
			return '\\"'
		elseif c == "\\" then
			return "\\\\"
		end
		return string.format("\\u%04x", string.byte(c))
	end)
	return '"' .. escaped .. '"'
end

local function vec(v): string
	return `[{num(v.X)},{num(v.Y)},{num(v.Z)}]`
end

local function cframe(c): string
	local r = c.r
	return `\{"position":{vec(c.p)},"orientation":[[{num(r[1][1])},{num(r[1][2])},{num(r[1][3])}],[{num(r[2][1])},{num(r[2][2])},{num(r[2][3])}],[{num(r[3][1])},{num(r[3][2])},{num(r[3][3])}]]\}`
end

-- The legacy Font enum, as the FontFace Rojo writes. Gotham is Roblox's GothamSSm family.
local FONT_WEIGHTS = {
	GothamBlack = "Heavy",
	GothamBold = "Bold",
	GothamMedium = "Medium",
	Gotham = "Regular",
}

local function fontFace(item): string
	local weight = FONT_WEIGHTS[item.Name]
	if weight == nil then
		error(`RobloxStub export: no FontFace mapping for Enum.Font.{item.Name}; add one to FONT_WEIGHTS`)
	end
	return `\{"family":"rbxasset://fonts/families/GothamSSm.json","weight":"{weight}","style":"Normal"\}`
end

-- A property value, in the forms Rojo reads against its reflection database. Most may be implicit;
-- CFrame and UDim2 must be tagged with their type or Rojo rejects the whole file.
local function property(value): string?
	local kind = typeof(value)
	if kind == "string" then
		return jstring(value)
	elseif kind == "number" then
		return num(value)
	elseif kind == "boolean" then
		return if value then "true" else "false"
	elseif kind == "Vector3" then
		return vec(value)
	elseif kind == "CFrame" then
		return `\{"CFrame":{cframe(value)}\}`
	elseif kind == "Color3" then
		return `[{num(value.R)},{num(value.G)},{num(value.B)}]`
	elseif kind == "EnumItem" then
		return jstring(value.Name)
	elseif kind == "UDim2" then
		return `\{"UDim2":[[{num(value.X.Scale)},{num(value.X.Offset)}],[{num(value.Y.Scale)},{num(value.Y.Offset)}]]\}`
	elseif kind == "UDim" then
		return `\{"UDim":[{num(value.Scale)},{num(value.Offset)}]\}`
	end
	error(`RobloxStub export: cannot write a {kind} property`)
end

-- Attribute values carry their type explicitly: Rojo has no reflection entry to infer them from.
local function attribute(value): string
	local kind = typeof(value)
	if kind == "string" then
		return `\{"String":{jstring(value)}\}`
	elseif kind == "number" then
		return `\{"Float64":{num(value)}\}`
	elseif kind == "boolean" then
		return `\{"Bool":{if value then "true" else "false"}\}`
	elseif kind == "Vector3" then
		return `\{"Vector3":{vec(value)}\}`
	elseif kind == "CFrame" then
		return `\{"CFrame":{cframe(value)}\}`
	elseif kind == "Color3" then
		return `\{"Color3":[{num(value.R)},{num(value.G)},{num(value.B)}]\}`
	end
	error(`RobloxStub export: cannot write a {kind} attribute`)
end

-- Properties the file carries elsewhere, or that no .rbxmx needs.
local SKIPPED = { Name = true, WorldPivot = true }

local counts = { instances = 0 }

local function node(instance, isRoot: boolean): string
	counts.instances += 1
	local className = rawget(instance, "__class")
	local props = rawget(instance, "__props")
	local parts = {}
	if not isRoot then
		table.insert(parts, `"name":{jstring(props.Name)}`)
	end
	table.insert(parts, `"className":{jstring(className)}`)

	local names = {}
	for key in props do
		if not SKIPPED[key] then
			table.insert(names, key)
		end
	end
	table.sort(names)
	local written = {}
	for _, key in names do
		local value = props[key]
		if key == "Font" and typeof(value) == "EnumItem" then
			table.insert(written, `"FontFace":{fontFace(value)}`)
		else
			table.insert(written, `{jstring(key)}:{property(value)}`)
		end
	end
	if #written > 0 then
		table.insert(parts, `"properties":\{{table.concat(written, ",")}\}`)
	end

	local order = rawget(instance, "__attributeOrder")
	if #order > 0 then
		local attrs = {}
		local attributes = rawget(instance, "__attributes")
		for _, name in order do
			table.insert(attrs, `{jstring(name)}:{attribute(attributes[name])}`)
		end
		table.insert(parts, `"attributes":\{{table.concat(attrs, ",")}\}`)
	end

	local tags = rawget(instance, "__tags")
	if #tags > 0 then
		local quoted = {}
		for _, tag in tags do
			table.insert(quoted, jstring(tag))
		end
		table.insert(parts, `"tags":[{table.concat(quoted, ",")}]`)
	end

	local children = rawget(instance, "__children")
	if #children > 0 then
		local kids = {}
		for _, child in children do
			table.insert(kids, node(child, false))
		end
		table.insert(parts, `"children":[{table.concat(kids, ",")}]`)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- One document per planned model, each between markers the Python side splits on.
for _, plan in EXPORT_PLAN do
	local root = plan.build(CFrame.new(plan.x, plan.y, plan.z), workspace)
	counts.instances = 0
	local json = node(root, true)
	print(`=====BEGIN {plan.file} {counts.instances}`)
	print(json)
	print(`=====END {plan.file}`)
	root.Parent = nil
end
