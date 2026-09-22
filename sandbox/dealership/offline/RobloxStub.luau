--[[
	Just enough of Roblox's API, in plain Luau, to run world/DealershipBuild outside Studio.

	WHY. The dealership is laid by code, and that code needed Studio to run -- which made the
	dealership exist only in whichever place it had been run in. Run here instead, under the Luau
	command line, the same builder produces an instance tree that export.luau writes out as a Rojo
	model file, and Rojo turns that into a real .rbxmx: a dealership that can be inserted into AGES,
	or any place, with no Studio session and no MCP bridge in between.

	This is the builder's own vocabulary and nothing more: Vector3, CFrame (new, Angles, lookAt,
	products, object space), Color3, UDim/UDim2, Enum items, Instance.new with properties, parents,
	attributes and tags, and CollectionService:AddTag. A builder change that reaches for something
	not here fails loudly on the missing name, which is the point.

	And what it takes to run the game's own car builder, world/VehicleChassis.BuildDisplay, for the
	sandbox's display cars: Vector2, PhysicalProperties, IsA across the BasePart family,
	WaitForChild, and ReplicatedStorage and Players as services. The modules it requires come from
	export.py's registry, not from here.

	Not a module: sandbox/dealership/export.py splices it in front of the builder, because the Luau
	command line gives each required module its own globals and the builder reads these as globals.
]]

-- ---------------------------------------------------------------------------------------------
-- Vector3
-- ---------------------------------------------------------------------------------------------
local Vector3 = {}
local Vector3Meta = {}

local function v3(x: number, y: number, z: number)
	return setmetatable({ X = x, Y = y, Z = z, __kind = "Vector3" }, Vector3Meta)
end

Vector3Meta.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m == 0 then
			return v3(0, 0, 0)
		end
		return v3(self.X / m, self.Y / m, self.Z / m)
	elseif key == "Lerp" then
		return function(a, b, t)
			return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
		end
	elseif key == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y + a.Z * b.Z
		end
	elseif key == "Cross" then
		return function(a, b)
			return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
		end
	end
	error(`RobloxStub: Vector3 has no member "{tostring(key)}"`)
end
Vector3Meta.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3Meta.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vector3Meta.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
Vector3Meta.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3Meta.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
Vector3Meta.__tostring = function(a)
	return `{a.X}, {a.Y}, {a.Z}`
end

function Vector3.new(x: number?, y: number?, z: number?)
	return v3(x or 0, y or 0, z or 0)
end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)

-- ---------------------------------------------------------------------------------------------
-- CFrame: a position and a rotation matrix, rows R0..R2, with Roblox's column meanings --
-- RightVector is column 0, UpVector column 1, LookVector minus column 2.
-- ---------------------------------------------------------------------------------------------
local CFrame = {}
local CFrameMeta = {}

local function cf(px, py, pz, r)
	return setmetatable({ p = v3(px, py, pz), r = r, __kind = "CFrame" }, CFrameMeta)
end

local IDENTITY = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }

local function matmul(a, b)
	local out = { {}, {}, {} }
	for i = 1, 3 do
		for j = 1, 3 do
			out[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
		end
	end
	return out
end

local function rotate(r, v)
	return v3(
		r[1][1] * v.X + r[1][2] * v.Y + r[1][3] * v.Z,
		r[2][1] * v.X + r[2][2] * v.Y + r[2][3] * v.Z,
		r[3][1] * v.X + r[3][2] * v.Y + r[3][3] * v.Z
	)
end

local function transpose(r)
	return {
		{ r[1][1], r[2][1], r[3][1] },
		{ r[1][2], r[2][2], r[3][2] },
		{ r[1][3], r[2][3], r[3][3] },
	}
end

local function inverse(c)
	local rt = transpose(c.r)
	local p = rotate(rt, c.p)
	return cf(-p.X, -p.Y, -p.Z, rt)
end

CFrameMeta.__index = function(self, key)
	if key == "Position" then
		return self.p
	elseif key == "X" then
		return self.p.X
	elseif key == "Y" then
		return self.p.Y
	elseif key == "Z" then
		return self.p.Z
	elseif key == "RightVector" then
		return v3(self.r[1][1], self.r[2][1], self.r[3][1])
	elseif key == "UpVector" then
		return v3(self.r[1][2], self.r[2][2], self.r[3][2])
	elseif key == "LookVector" then
		return v3(-self.r[1][3], -self.r[2][3], -self.r[3][3])
	elseif key == "Rotation" then
		return cf(0, 0, 0, self.r)
	elseif key == "Inverse" then
		return inverse
	elseif key == "ToObjectSpace" then
		return function(a, b)
			return inverse(a) * b
		end
	elseif key == "ToWorldSpace" then
		return function(a, b)
			return a * b
		end
	elseif key == "PointToObjectSpace" then
		return function(a, v)
			return inverse(a) * v
		end
	elseif key == "PointToWorldSpace" then
		return function(a, v)
			return a * v
		end
	elseif key == "VectorToWorldSpace" then
		return function(a, v)
			return rotate(a.r, v)
		end
	elseif key == "VectorToObjectSpace" then
		return function(a, v)
			return rotate(transpose(a.r), v)
		end
	end
	error(`RobloxStub: CFrame has no member "{tostring(key)}"`)
end
CFrameMeta.__mul = function(a, b)
	if b.__kind == "Vector3" then
		return a.p + rotate(a.r, b)
	end
	local p = a.p + rotate(a.r, b.p)
	return cf(p.X, p.Y, p.Z, matmul(a.r, b.r))
end
CFrameMeta.__add = function(a, v)
	return cf(a.p.X + v.X, a.p.Y + v.Y, a.p.Z + v.Z, a.r)
end
CFrameMeta.__sub = function(a, v)
	return cf(a.p.X - v.X, a.p.Y - v.Y, a.p.Z - v.Z, a.r)
end

function CFrame.new(x, y, z)
	if x == nil then
		return cf(0, 0, 0, IDENTITY)
	elseif type(x) == "table" then
		return cf(x.X, x.Y, x.Z, IDENTITY)
	end
	return cf(x, y, z, IDENTITY)
end

-- Rx * Ry * Rz, which is what CFrame.Angles (fromEulerAnglesXYZ) is.
function CFrame.Angles(rx: number, ry: number, rz: number)
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	local x = { { 1, 0, 0 }, { 0, cx, -sx }, { 0, sx, cx } }
	local y = { { cy, 0, sy }, { 0, 1, 0 }, { -sy, 0, cy } }
	local z = { { cz, -sz, 0 }, { sz, cz, 0 }, { 0, 0, 1 } }
	return cf(0, 0, 0, matmul(matmul(x, y), z))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles

function CFrame.lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - at).Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		-- Looking straight up or down: any right vector perpendicular to the look will do.
		right = look:Cross(v3(0, 0, 1))
	end
	right = right.Unit
	local upward = right:Cross(look)
	-- Columns: right, up, back (= -look).
	return cf(at.X, at.Y, at.Z, {
		{ right.X, upward.X, -look.X },
		{ right.Y, upward.Y, -look.Y },
		{ right.Z, upward.Z, -look.Z },
	})
end

-- ---------------------------------------------------------------------------------------------
-- Color3, UDim, UDim2
-- ---------------------------------------------------------------------------------------------
local Color3 = {}
function Color3.new(r: number, g: number, b: number)
	return { R = r, G = g, B = b, __kind = "Color3" }
end
function Color3.fromRGB(r: number, g: number, b: number)
	return Color3.new(r / 255, g / 255, b / 255)
end

local Vector2 = {}
function Vector2.new(x: number?, y: number?)
	return { X = x or 0, Y = y or 0, __kind = "Vector2" }
end

-- Physics only a moving car needs; a display car is anchored, and the exporter leaves it out.
local PhysicalProperties = {}
function PhysicalProperties.new(...)
	return { __kind = "PhysicalProperties" }
end

local UDim = {}
function UDim.new(scale: number, offset: number)
	return { Scale = scale, Offset = offset, __kind = "UDim" }
end

local UDim2 = {}
function UDim2.new(xs: number?, xo: number?, ys: number?, yo: number?)
	return { X = UDim.new(xs or 0, xo or 0), Y = UDim.new(ys or 0, yo or 0), __kind = "UDim2" }
end
function UDim2.fromScale(x: number, y: number)
	return UDim2.new(x, 0, y, 0)
end
function UDim2.fromOffset(x: number, y: number)
	return UDim2.new(0, x, 0, y)
end

-- ---------------------------------------------------------------------------------------------
-- Enum: any Enum.Type.Item, as a tagged record the exporter writes by name.
-- ---------------------------------------------------------------------------------------------
local Enum = setmetatable({}, {
	__index = function(enums, typeName)
		local items = setmetatable({}, {
			__index = function(itemsTable, itemName)
				local item = { Name = itemName, EnumType = typeName, __kind = "EnumItem" }
				rawset(itemsTable, itemName, item)
				return item
			end,
		})
		rawset(enums, typeName, items)
		return items
	end,
})

-- ---------------------------------------------------------------------------------------------
-- Instances
-- ---------------------------------------------------------------------------------------------
local InstanceMeta = {}
local Instance = {}

local function newInstance(className: string)
	local self = setmetatable({
		__kind = "Instance",
		__class = className,
		__props = { Name = className },
		__children = {},
		__parent = nil,
		__attributes = {},
		__attributeOrder = {},
		__tags = {},
	}, InstanceMeta)
	return self
end

local methods = {}

function methods.SetAttribute(self, name, value)
	if self.__attributes[name] == nil then
		table.insert(self.__attributeOrder, name)
	end
	self.__attributes[name] = value
end
function methods.GetAttribute(self, name)
	return self.__attributes[name]
end
function methods.FindFirstChild(self, name)
	for _, child in self.__children do
		if child.__props.Name == name then
			return child
		end
	end
	return nil
end
function methods.GetChildren(self)
	return table.clone(self.__children)
end
function methods.GetDescendants(self)
	local out = {}
	local function walk(node)
		for _, child in node.__children do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end
-- The part classes a builder here makes, for IsA("BasePart").
local BASE_PARTS = { Part = true, WedgePart = true, MeshPart = true, Seat = true, VehicleSeat = true, TrussPart = true }

function methods.IsA(self, className)
	if className == "BasePart" then
		return BASE_PARTS[self.__class] == true
	elseif className == "Instance" then
		return true
	end
	return self.__class == className
end
function methods.WaitForChild(self, name)
	local child = methods.FindFirstChild(self, name)
	if child == nil then
		error(`RobloxStub: {self.__props.Name} has no child "{name}" to wait for; nothing will ever add one here`)
	end
	return child
end
function methods.Destroy(self)
	self.Parent = nil
end

InstanceMeta.__index = function(self, key)
	if methods[key] then
		return methods[key]
	elseif key == "Parent" then
		return rawget(self, "__parent")
	elseif key == "ClassName" then
		return rawget(self, "__class")
	end
	local props = rawget(self, "__props")
	local value = props[key]
	if value == nil then
		error(`RobloxStub: {rawget(self, "__class")}.{tostring(key)} was read before it was set`)
	end
	return value
end
InstanceMeta.__newindex = function(self, key, value)
	if key == "Parent" then
		local old = rawget(self, "__parent")
		if old then
			local siblings = rawget(old, "__children")
			local index = table.find(siblings, self)
			if index then
				table.remove(siblings, index)
			end
		end
		rawset(self, "__parent", value)
		if value then
			table.insert(rawget(value, "__children"), self)
		end
		return
	end
	rawget(self, "__props")[key] = value
end

function Instance.new(className: string)
	return newInstance(className)
end

local CollectionService = {}
function CollectionService.AddTag(_, instance, tag)
	table.insert(rawget(instance, "__tags"), tag)
end

-- ReplicatedStorage holds a stand-in for each module export.py registers, so that
-- `require(ReplicatedStorage:WaitForChild("Config"))` finds a child with that name to hand to the
-- registry's require.
local ReplicatedStorage = newInstance("ReplicatedStorage")
ReplicatedStorage.Name = "ReplicatedStorage"
local Players = newInstance("Players")
Players.Name = "Players"

local game = {}
function game.GetService(_, name)
	if name == "CollectionService" then
		return CollectionService
	elseif name == "ReplicatedStorage" then
		return ReplicatedStorage
	elseif name == "Players" then
		return Players
	end
	error(`RobloxStub: no service "{name}"`)
end

local function typeof(value)
	if type(value) == "table" and value.__kind then
		return value.__kind
	end
	return type(value)
end

local workspace = newInstance("Workspace")
workspace.Name = "Workspace"
