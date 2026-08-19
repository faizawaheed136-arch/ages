--!nocheck
-- Does the server actually boot?
--
-- Every other gate in this repo reads the source without running it. That is why the game
-- was unplayable for four days behind `Config.SubjectPerks = { [undefined] = nil }`: a nil
-- key in a table constructor is perfectly good syntax, resolves to a name nothing binds,
-- and throws `table index is nil` only when the module body *executes*. Config is required
-- by every service in both places, so nothing loaded -- and Roblox still spawns a character
-- on its own, so the symptom was "I spawn normal size and cannot play" rather than any
-- error naming Config. Three separate static checks looked straight at that line.
--
-- So this one runs the code. It rebuilds enough of a DataModel to make `require` resolve
-- the way Rojo maps it, stubs the Roblox API surface a module body can touch, and then
-- requires every module in dependency order, reporting the ones that throw.
--
-- **What it can and cannot see.** It executes *module bodies* -- the top level of each
-- file, plus `Init()` and `Start()` on each service. It does not simulate a player, a
-- character, a remote or a heartbeat, so a bug that needs one of those is out of scope and
-- always will be. That is the honest boundary: this catches "the server never started",
-- which is the failure that looks like every other failure and is the one worth a tool.
--
-- **The stubs are permissive on purpose.** Any Roblox object returns a stub for any index
-- and is callable, comparable and arithmetic-able. A stricter stub would report the stub's
-- own gaps as bugs in the game, and a gate nobody trusts is a gate nobody runs. The cost is
-- that a real bug *inside* a Roblox call is invisible here; the benefit is that every error
-- it does report is in this repo's own code.

-- Sources arrive as globals rather than being read from disk: the standalone `luau`
-- binary ships no `io` library at all, so `tools/check.py` escapes every file into
-- `AGES_SOURCES` (repo-relative path -> source text) and concatenates that prelude in
-- front of this file. `AGES_MANIFEST` is the same paths in sorted order.
local SOURCES = AGES_SOURCES
local MANIFEST = AGES_MANIFEST

--------------------------------------------------------------------------------
-- Roblox API stubs
--------------------------------------------------------------------------------

local Stub = {}
Stub.__index = function(self, key)
	-- Instances are containers, so an index has to keep working forever -- `a.b.c.d` is
	-- ordinary Roblox code. Cached so identity is stable: `x.Foo == x.Foo` holds, which
	-- some module bodies rely on when they stash a reference and compare it later.
	local cache = rawget(self, "__cache")
	if cache[key] == nil then
		cache[key] = setmetatable({ __cache = {}, __name = tostring(key) }, Stub)
	end
	return cache[key]
end
Stub.__newindex = function() end
Stub.__call = function(self, ...)
	return setmetatable({ __cache = {}, __name = "call" }, Stub)
end
Stub.__tostring = function(self)
	return "Stub<" .. tostring(rawget(self, "__name")) .. ">"
end
-- Arithmetic and comparison return stubs / false rather than erroring. A module body that
-- computes `Config.X * 2` against a stubbed value must not be reported as a crash.
Stub.__add = Stub.__call
Stub.__sub = Stub.__call
Stub.__mul = Stub.__call
Stub.__div = Stub.__call
Stub.__mod = Stub.__call
Stub.__pow = Stub.__call
Stub.__unm = Stub.__call
Stub.__concat = function()
	return ""
end
Stub.__len = function()
	return 0
end
-- A stub iterates as empty. Without this, `for _, x in someStub do` falls back to calling
-- the stub as an iterator function, `__call` hands back a fresh stub every time, the loop
-- never sees nil and the harness hangs -- which is exactly what it did, on 39 of 112
-- modules, and looked precisely like an infinite loop in the game.
Stub.__iter = function()
	return function()
		return nil
	end
end
Stub.__eq = function()
	return false
end
Stub.__lt = function()
	return false
end
Stub.__le = function()
	return false
end

local function newStub(name)
	return setmetatable({ __cache = {}, __name = name or "stub" }, Stub)
end

--------------------------------------------------------------------------------
-- Real value types
--
-- Color3 and Vector3 are not opaque handles -- game code reads `.R` and `.X` off them and
-- does arithmetic and comparisons with the result. Stubbing them cost this harness four
-- false alarms on its first honest run (`math.sqrt` on a Color3 channel in Pigments and
-- Gangs, `prop.size.X <= 0` in Props), every one of which pointed at correct code. A gate
-- that reports good code as broken is worse than no gate, so these get real numbers.
--------------------------------------------------------------------------------

local Vec = {}
Vec.__index = Vec
local function vec(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, Magnitude = 0, Unit = false }, Vec)
end
Vec.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vec.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vec.__mul = function(a, b)
	if type(b) == "number" then return vec(a.X * b, a.Y * b, a.Z * b) end
	if type(a) == "number" then return vec(b.X * a, b.Y * a, b.Z * a) end
	return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vec.__div = function(a, b)
	if type(b) == "number" then return vec(a.X / b, a.Y / b, a.Z / b) end
	return vec(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
Vec.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
Vec.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
Vec.__tostring = function(a) return `{a.X}, {a.Y}, {a.Z}` end

local Col = {}
Col.__index = Col
local function col(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Col)
end
Col.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
Col.__tostring = function(a) return `{a.R}, {a.G}, {a.B}` end

--------------------------------------------------------------------------------
-- The instance tree, mirroring how Rojo maps this repo
--------------------------------------------------------------------------------

local Node = {}
Node.__index = function(self, key)
	local children = rawget(self, "children")
	if children and children[key] then
		return children[key]
	end
	local method = rawget(Node, key)
	if method then
		return method
	end
	-- A real Instance property (Name, Parent, ClassName) or an unknown child. Unknown
	-- children must not be nil: `script.Parent.Foo` for a module this harness did not map
	-- would otherwise read as nil and produce a fake "attempt to index nil" that blames
	-- the game for the harness's own incompleteness.
	if key == "Name" then
		return rawget(self, "name")
	end
	if key == "Parent" then
		return rawget(self, "parent")
	end
	if key == "ClassName" then
		return rawget(self, "class")
	end
	return newStub(tostring(key))
end

function Node.WaitForChild(self, name)
	local children = rawget(self, "children")
	if children and children[name] then
		return children[name]
	end
	return newStub(name)
end
Node.FindFirstChild = Node.WaitForChild

function Node.GetChildren(self)
	local out = {}
	for _, child in pairs(rawget(self, "children") or {}) do
		table.insert(out, child)
	end
	return out
end
Node.GetDescendants = Node.GetChildren

function Node.IsA(self, class)
	return rawget(self, "class") == class
end

local function newNode(name, class, parent)
	return setmetatable({
		name = name,
		class = class,
		parent = parent,
		children = {},
	}, Node)
end

--------------------------------------------------------------------------------
-- Filesystem -> tree
--------------------------------------------------------------------------------

local entries = MANIFEST

-- Build the tree from the repo-relative paths in the manifest.
local roots = {}
local function ensureDir(parts, count)
	local key = table.concat(parts, "/", 1, count)
	if roots[key] then
		return roots[key]
	end
	local parent = count > 1 and ensureDir(parts, count - 1) or nil
	local node = newNode(parts[count], "Folder", parent)
	roots[key] = node
	if parent then
		rawget(parent, "children")[parts[count]] = node
	end
	return node
end

local sources = {}

for _, rel in ipairs(entries) do
	local parts = {}
	for part in rel:gmatch("[^/]+") do
		table.insert(parts, part)
	end
	local fileName = parts[#parts]
	local moduleName = fileName:gsub("%.luau$", "")
	local dir = ensureDir(parts, #parts - 1)

	if moduleName == "init" then
		-- Rojo folds `init.luau` into the folder itself.
		rawset(dir, "class", "ModuleScript")
		sources[dir] = rel
	elseif moduleName:match("^init%.") then
		-- init.server / init.client: the folder becomes that script.
		rawset(dir, "class", moduleName:match("server") and "Script" or "LocalScript")
		sources[dir] = rel
	else
		local node = newNode(moduleName, "ModuleScript", dir)
		rawget(dir, "children")[moduleName] = node
		sources[node] = rel
	end
end

--------------------------------------------------------------------------------
-- Wire the DataModel the way default.project.json does
--------------------------------------------------------------------------------

local srcServer = roots["src/server"]
local srcShared = roots["src/shared"]
local srcClient = roots["src/client"]
local profileStore = roots["vendor/ProfileStore"]

local ReplicatedStorage = srcShared
local ServerScriptService = newNode("ServerScriptService", "ServerScriptService", nil)
rawget(ServerScriptService, "children")["Server"] = srcServer
rawset(srcServer, "parent", ServerScriptService)

local ServerStorage = newNode("ServerStorage", "ServerStorage", nil)
if profileStore then
	rawget(ServerStorage, "children")["ProfileStore"] = profileStore
end

local services = {
	ReplicatedStorage = ReplicatedStorage,
	ServerScriptService = ServerScriptService,
	ServerStorage = ServerStorage,
	Players = newStub("Players"),
	RunService = newStub("RunService"),
	Workspace = newStub("Workspace"),
	Lighting = newStub("Lighting"),
	TeleportService = newStub("TeleportService"),
	HttpService = newStub("HttpService"),
	TweenService = newStub("TweenService"),
	UserInputService = newStub("UserInputService"),
	CollectionService = newStub("CollectionService"),
	MarketplaceService = newStub("MarketplaceService"),
	PathfindingService = newStub("PathfindingService"),
	SoundService = newStub("SoundService"),
	Debris = newStub("Debris"),
	ContextActionService = newStub("ContextActionService"),
	StarterGui = newStub("StarterGui"),
	Chat = newStub("Chat"),
	TextChatService = newStub("TextChatService"),
	PhysicsService = newStub("PhysicsService"),
	DataStoreService = newStub("DataStoreService"),
	MessagingService = newStub("MessagingService"),
	AnalyticsService = newStub("AnalyticsService"),
	ContentProvider = newStub("ContentProvider"),
	AssetService = newStub("AssetService"),
	MemoryStoreService = newStub("MemoryStoreService"),
	GroupService = newStub("GroupService"),
	BadgeService = newStub("BadgeService"),
	PolicyService = newStub("PolicyService"),
	LocalizationService = newStub("LocalizationService"),
}

local game = newStub("game")
rawset(game, "__cache", {
	ReplicatedStorage = ReplicatedStorage,
	ServerScriptService = ServerScriptService,
	ServerStorage = ServerStorage,
	Workspace = services.Workspace,
	Players = services.Players,
})

--------------------------------------------------------------------------------
-- The environment every module body sees
--------------------------------------------------------------------------------

local loaded = {}
local loading = {}
local failures = {}
local order = {}

-- Budget for unyielded waits, so a spin loop is reported against the module that owns it
-- instead of hanging the gate. Reset per module: the number is a "this one never returns"
-- threshold, not a total for the run.
local WAIT_BUDGET = 10000
local waits = 0
function AGES_TICK()
	waits += 1
	if waits > WAIT_BUDGET then
		error(`spun on task.wait {WAIT_BUDGET}+ times without yielding -- this loop never returns`, 0)
	end
end

local baseEnv
local function makeRequire(chain)
	return function(target)
		if type(target) ~= "table" or sources[target] == nil then
			-- A require of something this harness did not map (a stubbed instance, a
			-- vendored path it does not know). Hand back a stub rather than failing:
			-- the harness's own coverage gaps are not the game's bugs.
			return newStub("required")
		end
		if loaded[target] ~= nil then
			return loaded[target]
		end
		if loading[target] then
			-- A require cycle. check.py already gates these; returning a stub keeps this
			-- run going so it can report everything else in one pass.
			return newStub("cycle")
		end
		loading[target] = true

		local rel = sources[target]
		local src = SOURCES[rel]
		local chunk, compileErr = loadstring(src, rel)
		if chunk == nil then
			table.insert(failures, { rel = rel, err = "compile: " .. tostring(compileErr), chain = chain })
			loading[target] = nil
			loaded[target] = newStub("failed")
			return loaded[target]
		end

		local env = setmetatable({ script = target }, { __index = baseEnv })
		env.require = makeRequire(chain .. " -> " .. rel)
		setfenv(chunk, env)

		-- Printed before the call, not after, so the last line of a run that dies inside a
		-- module body names that module. Without this a hang or a hard crash says nothing
		-- at all about where it happened.
		print("BOOTCHECK-ENTER\t" .. rel)
		waits = 0
		local ok, result = pcall(chunk)
		loading[target] = nil
		if not ok then
			table.insert(failures, { rel = rel, err = tostring(result), chain = chain })
			loaded[target] = newStub("failed")
		else
			loaded[target] = result == nil and newStub("noreturn") or result
			table.insert(order, { rel = rel, value = loaded[target] })
		end
		return loaded[target]
	end
end

baseEnv = setmetatable({
	game = game,
	workspace = services.Workspace,
	Workspace = services.Workspace,
	shared = {},
	Instance = { new = function() return newStub("Instance") end },
	Enum = newStub("Enum"),
	Vector3 = {
		new = vec,
		zero = vec(0, 0, 0),
		one = vec(1, 1, 1),
		xAxis = vec(1, 0, 0),
		yAxis = vec(0, 1, 0),
		zAxis = vec(0, 0, 1),
		FromNormalId = function() return vec(0, 1, 0) end,
	},
	Vector2 = { new = function(x, y) return vec(x, y, 0) end, zero = vec(0, 0, 0) },
	CFrame = newStub("CFrame"),
	Color3 = {
		new = col,
		-- Roblox's fromRGB divides by 255, and content code compares channel distances in
		-- 0-255 space, so getting this wrong would make every colour-distance guard in the
		-- tree either always pass or always fail.
		fromRGB = function(r, g, b) return col((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end,
		fromHSV = function(h, s, v) return col(h or 0, s or 0, v or 0) end,
		fromHex = function() return col(0, 0, 0) end,
	},
	UDim = newStub("UDim"),
	UDim2 = newStub("UDim2"),
	BrickColor = newStub("BrickColor"),
	TweenInfo = newStub("TweenInfo"),
	NumberRange = newStub("NumberRange"),
	NumberSequence = newStub("NumberSequence"),
	ColorSequence = newStub("ColorSequence"),
	NumberSequenceKeypoint = newStub("NumberSequenceKeypoint"),
	ColorSequenceKeypoint = newStub("ColorSequenceKeypoint"),
	-- A real generator, not a stub, for the same reason Vector3 and Color3 are real:
	-- content generators feed `rng:NextNumber()` straight into `math.round` and into
	-- comparisons, and a stub hands back a table. That surfaces as "invalid argument #1
	-- to 'round' (number expected, got table)" pointing at a content file, which is a
	-- harness defect wearing a game bug's clothes -- exactly the false alarm the Color3
	-- stub produced four times before it was made real.
	--
	-- Deliberately seeded and deliberately not Roblox's algorithm. The harness only needs
	-- numbers in the right range in a stable sequence, so that a run is repeatable and a
	-- failure can be reproduced. It must never be read as evidence about what the game's
	-- actual random distribution looks like.
	Random = {
		new = function(seed)
			local state = math.floor(math.abs(tonumber(seed) or 12345)) % 2147483647
			if state <= 0 then
				state = 12345
			end
			local generator = {}
			local function nextUnit(): number
				-- Lehmer / Park-Miller. One multiply and a modulo, no state beyond a
				-- single integer, and it never returns exactly 0 or exactly 1.
				state = (state * 16807) % 2147483647
				return state / 2147483647
			end
			function generator:NextNumber(min, max)
				if min == nil then
					return nextUnit()
				end
				return min + nextUnit() * (max - min)
			end
			function generator:NextInteger(min, max)
				local span = (max - min) + 1
				return min + math.floor(nextUnit() * span) % span
			end
			function generator:NextUnitVector()
				return vec(nextUnit(), nextUnit(), nextUnit())
			end
			function generator:Clone()
				return generator
			end
			function generator:Shuffle(list)
				return list
			end
			return generator
		end,
	},
	Ray = newStub("Ray"),
	Rect = newStub("Rect"),
	Region3 = newStub("Region3"),
	RaycastParams = newStub("RaycastParams"),
	OverlapParams = newStub("OverlapParams"),
	PhysicalProperties = newStub("PhysicalProperties"),
	Font = newStub("Font"),
	DateTime = newStub("DateTime"),
	Faces = newStub("Faces"),
	Axes = newStub("Axes"),
	-- `task.spawn`/`defer`/`delay` deliberately do not run their function: a service's tick
	-- loop belongs to a scheduler this harness does not have, and running one would spin
	-- forever. `task.wait` returns instead of yielding for the same reason -- which means a
	-- `while true do task.wait() end` written *outside* a spawn is an infinite loop here.
	-- That is a real finding rather than a harness limit (nothing after it would ever run
	-- on a real server either), so it is counted and thrown rather than hung on.
	task = {
		wait = function()
			AGES_TICK()
			return 0
		end,
		spawn = function() end,
		defer = function() end,
		delay = function() end,
		cancel = function() end,
	},
	warn = function() end,
	tick = os.time,
	time = os.time,
	wait = function() return 0 end,
	spawn = function() end,
	delay = function() end,
	settings = function() return newStub("settings") end,
	setclipboard = function() end,
	elapsedTime = function() return 0 end,
	typeof = function(v)
		local mt = getmetatable(v)
		if mt == Stub then
			return "Instance"
		end
		if mt == Node then
			return "Instance"
		end
		return type(v)
	end,
}, { __index = _G })

-- `game:GetService` has to be a real function rather than a stub index, because a service
-- must come back as the mapped tree (ReplicatedStorage) and not as a generic stub -- every
-- `require(ReplicatedStorage:WaitForChild("Config"))` in the tree depends on it.
rawget(game, "__cache").GetService = function(_, name)
	return services[name] or newStub(name)
end
rawget(game, "__cache").FindService = rawget(game, "__cache").GetService

--------------------------------------------------------------------------------
-- Run it
--------------------------------------------------------------------------------

local serverInit = srcServer
local rootRequire = makeRequire("(boot)")

print("BOOTCHECK-BEGIN")

-- The bootstrap itself: requires every service and drives Init()/Start().
local ok, err = pcall(function()
	return rootRequire(serverInit)
end)
if not ok then
	table.insert(failures, { rel = "src/server/init.server.luau", err = tostring(err), chain = "(boot)" })
end

for _, f in ipairs(failures) do
	print("BOOTCHECK-FAIL\t" .. f.rel .. "\t" .. f.err:gsub("\n", " ") .. "\t" .. f.chain)
end
print("BOOTCHECK-LOADED\t" .. tostring(#order))
print("BOOTCHECK-END")
