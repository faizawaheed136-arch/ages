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
-- `rawequal`, not `false`. Luau calls `__eq` even when both operands are *the same table*
-- -- `a == a` is false under a metatable that returns false, which is not Lua 5.1's rule and
-- is not what anyone writing this expects. Verified directly:
--
--     local mt = { __eq = function() return false end }
--     local a = setmetatable({}, mt)
--     print(a == a, rawequal(a, a))  --> false  true
--
-- Since `Stub.__index` caches, `Enum.HumanoidRigType.R15` is one stable object, so identity
-- is the correct answer and the only one available. Returning a flat `false` made *every*
-- enum comparison in the tree false, which meant every `if x == Enum.Foo.Bar` branch was
-- silently skipped -- it made `ensureR15` decide a correctly-built R15 rig was R6, rebuild
-- the character into a stub and throw the real one away, so the body band then had nothing
-- to size. A harness bug that reads exactly like the game bug being hunted.
Stub.__eq = function(a, b)
	return rawequal(a, b)
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
-- Declared before `Vec.__index` because that closure calls it. A Lua closure captures the
-- local in scope where it is *written*, so a `local function vec` further down would be read
-- here as a nil global -- the same bug this harness caught in the bank buttons and in
-- `bondGain`, and it would have fired on the first `.Unit` in the tree.
local vec

-- `Magnitude` and `Unit` are derived here, not stored. They used to be the literals `0` and
-- `false`, and both halves of that were wrong:
--
--   * `Unit = false` meant `v.Unit.X` was an index into a boolean. That is what it did --
--     the lobby's stage code raised `attempt to index boolean with 'X'` the first time this
--     gate was pointed at a place that normalises a direction. Fifth harness artifact.
--   * `Magnitude = 0` was the quieter and worse one: it never throws, it just answers
--     "zero studs away" to every distance question in the game. Every proximity gate --
--     the NPC context radius, spotting, the whole crime stack -- passes here regardless of
--     what it actually says. A gate that answers 0 to every "how far" is certifying code it
--     has not exercised, which is this repo's oldest recurring defect wearing a new hat.
Vec.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	end
	if key == "Unit" then
		local magnitude = self.Magnitude
		-- Roblox answers nan for the zero vector here. The zero vector is returned instead
		-- on purpose: nan propagates silently through arithmetic and surfaces somewhere
		-- unrelated to the line that made it, which is the hardest possible thing to trace
		-- back to this file.
		if magnitude == 0 then
			return vec(0, 0, 0)
		end
		return vec(self.X / magnitude, self.Y / magnitude, self.Z / magnitude)
	end
	return rawget(Vec, key)
end

function vec(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vec)
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

-- The path a node sits at, for error messages that read like Roblox's own.
local function nodePath(node)
	local parts = {}
	local current = node
	while type(current) == "table" and rawget(current, "name") ~= nil do
		table.insert(parts, 1, rawget(current, "name"))
		current = rawget(current, "parent")
	end
	return table.concat(parts, ".")
end

-- A stub that remembers it came from asking a *mapped* node for a child it does not have.
--
-- The distinction matters and missing it is what let `require(script.Parent.Ribbons)` sit in
-- `VerdictService` while this gate reported the game place "clean -- 110 modules loaded".
-- Ribbons lives in `content/`, not `services/`, so in Studio that line raised "Ribbons is not
-- a valid member of Folder ServerScriptService.Server.services" and took the entire server
-- bootstrap down with it. The player saw a world with no services in it.
--
-- The old fallback handed back a plain stub for every unknown key, with a comment arguing
-- that "the harness's own coverage gaps are not the game's bugs". That is a real principle
-- and it is why fabricated service nodes still get the permissive path. But it does not
-- apply to the source tree: those nodes are built from the manifest, which is the actual
-- file list on disk, so a child missing *there* is not a gap in the harness -- it is a module
-- that does not exist, which is the exact thing Roblox refuses. Provenance is what tells the
-- two cases apart, so the stub carries it and `require` reads it back.
local function newMissing(parent, key)
	local stub = newStub(tostring(key))
	rawset(stub, "__missingFrom", nodePath(parent))
	rawset(stub, "__missingClass", rawget(parent, "class"))
	rawset(stub, "__missingKey", tostring(key))
	return stub
end

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
	-- Tagged rather than rejected here on purpose. An unknown key on a mapped node is only
	-- *certainly* wrong when it is required as a module; read as a property or called as an
	-- Instance method this harness has not implemented (`:GetFullName()`, `:Destroy()`), it
	-- is still the harness's gap and failing on it would be the false-positive class this
	-- file has already removed checks for. So record where it came from and let `require`,
	-- which cannot be anything but a module lookup, be the one to judge it.
	if rawget(self, "mapped") then
		return newMissing(self, key)
	end
	return newStub(tostring(key))
end

-- `WaitForChild` with no timeout does not fail for a child that never arrives -- it yields
-- forever. At module scope that parks the bootstrap thread permanently, so every service
-- after it never starts and the output holds no error at all, only a warning. This is the
-- worst shape a bug in this tree can take, and one shipped: CarDealerService asked
-- `ReplicatedStorage.world` for Customers and Ground, which live in `src/server/world`,
-- and the game place loaded with a world in it and nothing running.
--
-- This gate returned a stub instantly, so the wait it could not survive was the one thing
-- it never modelled. On a mapped node the answer is knowable -- the manifest is the file
-- list -- so a name that is not there is tagged the same way a dot-index is, and `require`
-- reports it. Unmapped nodes keep the permissive answer; their children genuinely are the
-- harness's blind spot rather than the game's mistake.
function Node.WaitForChild(self, name)
	local children = rawget(self, "children")
	if children and children[name] then
		return children[name]
	end
	if rawget(self, "mapped") then
		return newMissing(self, name)
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

-- Roblox's `IsA` walks the class tree, so `Part:IsA("BasePart")` is true. This used to be a
-- bare equality test, which answered false for every such question and made the lobby's
-- `StageService.Place` refuse a perfectly good character with "has no Humanoid or
-- HumanoidRootPart" -- the sixth harness artifact reading as a game bug.
--
-- Only the ancestors this repo actually asks about are listed. A full class database would
-- be a second copy of Roblox's API surface to keep current, and the failure mode of a stale
-- copy is this same false negative again; a missing entry here shows up as one warning
-- naming the class, which is a cheap thing to read and fix.
local CLASS_PARENT = {
	Part = "BasePart",
	MeshPart = "BasePart",
	SpawnLocation = "BasePart",
	BasePart = "PVInstance",
	Model = "PVInstance",
	PVInstance = "Instance",
	Folder = "Instance",
	ModuleScript = "LuaSourceContainer",
	Script = "LuaSourceContainer",
	LocalScript = "LuaSourceContainer",
	LuaSourceContainer = "Instance",
	Humanoid = "Instance",
	NumberValue = "Instance",
}

-- Shared by both instance flavours in this file -- the script-tree `Node` and the runtime
-- `Inst`. They are separate types with separate method tables, which is exactly how the
-- first version of this fix went in on `Node` alone and changed nothing: the character a
-- player wears is an `Inst`, so the lobby kept refusing it.
local function classIsA(className, class)
	local current = className
	while current ~= nil do
		if current == class then
			return true
		end
		current = CLASS_PARENT[current]
	end
	-- Every Instance is an Instance, including the classes not named above.
	return class == "Instance"
end

function Node.IsA(self, class)
	return classIsA(rawget(self, "class"), class)
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
	-- Built from the manifest, which is the file list on disk: this folder's children are
	-- known completely, so an unknown one is a missing module rather than a harness gap.
	rawset(node, "mapped", true)
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
		rawset(node, "mapped", true)
		rawget(dir, "children")[moduleName] = node
		sources[node] = rel
	end
end

--------------------------------------------------------------------------------
-- Wire the DataModel the way the project file does
--
-- Two places, and which one this run is about arrives as `AGES_PLACE`. This used to be
-- hardcoded to the game place, with a comment in `check.py` explaining that the lobby was
-- left out on purpose because it is a separate DataModel that "would need its own wiring".
-- That was true and it was still the wrong call: **the lobby is the start place -- it is the
-- one a player actually joins** -- so the gate was reporting on a place nobody lands in
-- first while the place they do land in was never executed at all.
--
-- What that cost: `src/lobby/server/services/LobbyService.luau` sat at **zero bytes** for
-- four days. `require` of an empty module returns nil, `init.server.luau` calls `:Init()` on
-- it, the lobby server dies on the first line of its bootstrap, and the player is left on a
-- stage where no button does anything. The gate was green throughout, because it was not
-- looking at the thing -- the exact defect class this file exists to end.
--------------------------------------------------------------------------------

local PLACE = AGES_PLACE or "game"

local srcShared = roots["src/shared"]
local profileStore = roots["vendor/ProfileStore"]

-- The three modules `lobby.project.json` mounts by path into `Server.shared` rather than
-- copying. They are given *fresh* nodes under that folder rather than the ones already
-- built under `src/server/services`, because `LifeSetup` requires `script.Parent.Countries`
-- and a node has one parent: reusing them would resolve that require against the game
-- place's tree and quietly prove nothing about the lobby's.
local LOBBY_SHARED = {
	DataService = "src/server/services/DataService.luau",
	Countries = "src/server/content/Countries.luau",
	LifeSetup = "src/server/content/LifeSetup.luau",
}

local ReplicatedStorage = srcShared
local ServerScriptService = newNode("ServerScriptService", "ServerScriptService", nil)
local StarterPlayer = newNode("StarterPlayer", "StarterPlayer", nil)

-- The one script this run exists to execute. Three places, three entry points, and the
-- client is one of them: `src/client/init.client.luau` requires thirty-six modules at the
-- top with no pcall, exactly like the two servers do, so one throw in any of them leaves a
-- player standing in a fully working world with **no UI at all** -- no stats, no choice
-- panel, no prompts, nothing to press. That is indistinguishable from "the server is dead"
-- from inside the game, and until now no gate in this repo had ever run a line of it.
local bootNode
if PLACE == "lobby" then
	bootNode = roots["src/lobby/server"]
	local shared = newNode("shared", "Folder", bootNode)
	rawget(bootNode, "children")["shared"] = shared
	for name, rel in LOBBY_SHARED do
		local node = newNode(name, "ModuleScript", shared)
		rawget(shared, "children")[name] = node
		sources[node] = rel
	end
	rawget(ServerScriptService, "children")["Server"] = bootNode
	rawset(bootNode, "parent", ServerScriptService)
elseif PLACE == "client" then
	bootNode = roots["src/client"]
	local starterScripts = newNode("StarterPlayerScripts", "StarterPlayerScripts", StarterPlayer)
	rawget(StarterPlayer, "children")["StarterPlayerScripts"] = starterScripts
	rawget(starterScripts, "children")["Client"] = bootNode
	rawset(bootNode, "parent", starterScripts)
else
	bootNode = roots["src/server"]
	rawget(ServerScriptService, "children")["Server"] = bootNode
	rawset(bootNode, "parent", ServerScriptService)
end

local ServerStorage = newNode("ServerStorage", "ServerStorage", nil)
if profileStore then
	rawget(ServerStorage, "children")["ProfileStore"] = profileStore
end

--------------------------------------------------------------------------------
-- A player, a character, and signals that actually fire
--
-- Everything above this line proves the server *starts*. It does not prove the game can be
-- *played*, and those are different failures with the same symptom: you stand in the world
-- at default adult size and nothing happens. The boot gate was clean and the game was still
-- unplayable, because `Players.PlayerAdded:Connect(fn)` against a stub stored the listener
-- nowhere and fired never -- so the entire join path (profile load, life begin, body band)
-- was categorically untested.
--
-- So Players, RunService, the Player and the character are real objects here, with real
-- signals. `RunService:IsStudio()` returns true because that is the branch a person testing
-- this game actually takes, and it is the branch that force-rolls a child life.
--------------------------------------------------------------------------------

local joinFailures = {}

local Signal = {}
Signal.__index = Signal
local function newSignal(name)
	return setmetatable({ signalName = name, listeners = {} }, Signal)
end
function Signal:Connect(listener)
	table.insert(self.listeners, listener)
	return {
		Connected = true,
		Disconnect = function(this)
			this.Connected = false
			for i, existing in ipairs(self.listeners) do
				if existing == listener then
					table.remove(self.listeners, i)
					break
				end
			end
		end,
	}
end
Signal.Once = Signal.Connect
Signal.ConnectParallel = Signal.Connect
-- Returns immediately rather than blocking. Nothing here drives a scheduler, so a real
-- `Wait` would deadlock the harness; a caller that waits on an event gets one "tick".
function Signal:Wait()
	return nil
end
-- Each listener is called under its own pcall so that one throwing does not hide the rest.
-- A handler that dies is exactly what this whole phase exists to find, so it is recorded
-- rather than re-raised.
function Signal:Fire(...)
	for _, listener in ipairs(table.clone(self.listeners)) do
		local ok, err = pcall(listener, ...)
		if not ok then
			table.insert(joinFailures, { signal = self.signalName, err = tostring(err) })
		end
	end
end

-- A minimal but *real* Instance: properties are stored and read back, children can be found
-- by name and by class. Unknown reads still fall through to a stub, which keeps the
-- permissive contract the rest of this harness relies on.
local Inst = {}
Inst.__index = function(self, key)
	local children = rawget(self, "__children")
	if children[key] ~= nil then
		return children[key]
	end
	local props = rawget(self, "__props")
	if props[key] ~= nil then
		return props[key]
	end
	local method = rawget(Inst, key)
	if method ~= nil then
		return method
	end
	return newStub(tostring(key))
end
Inst.__newindex = function(self, key, value)
	rawget(self, "__props")[key] = value
end
Inst.__tostring = function(self)
	return tostring(rawget(self, "__props").Name)
end

local function newInst(name, class, parent)
	local inst = setmetatable({
		__props = { Name = name, ClassName = class, Parent = parent },
		__children = {},
	}, Inst)
	if parent ~= nil then
		rawget(parent, "__children")[name] = inst
	end
	return inst
end

function Inst.FindFirstChild(self, name)
	return rawget(self, "__children")[name]
end
function Inst.WaitForChild(self, name, _timeout)
	return rawget(self, "__children")[name]
end
function Inst.FindFirstChildOfClass(self, class)
	for _, child in pairs(rawget(self, "__children")) do
		if rawget(child, "__props").ClassName == class then
			return child
		end
	end
	return nil
end
-- Not an alias for `FindFirstChildOfClass`, which it used to be. `WhichIsA` accepts a
-- *base* class -- `FindFirstChildWhichIsA("BasePart")` has to match a Part -- and an exact
-- comparison silently answers nil for every such call, which reads as a missing child.
function Inst.FindFirstChildWhichIsA(self, class)
	for _, child in pairs(rawget(self, "__children")) do
		if classIsA(rawget(child, "__props").ClassName, class) then
			return child
		end
	end
	return nil
end
function Inst.GetChildren(self)
	local out = {}
	for _, child in pairs(rawget(self, "__children")) do
		table.insert(out, child)
	end
	return out
end
Inst.GetDescendants = Inst.GetChildren
function Inst.IsA(self, class)
	return classIsA(rawget(self, "__props").ClassName, class)
end
function Inst.Destroy(self)
	rawget(self, "__props").Parent = nil
end
function Inst.SetAttribute(self, key, value)
	rawget(self, "__props")["attr_" .. tostring(key)] = value
end
function Inst.GetAttribute(self, key)
	return rawget(self, "__props")["attr_" .. tostring(key)]
end
function Inst.GetPivot(self)
	return newStub("CFrame")
end
function Inst.PivotTo(self, _cf) end
function Inst.Clone(self)
	return self
end

local PlayersService = newInst("Players", "Players")
local playerList = {}
PlayersService.PlayerAdded = newSignal("Players.PlayerAdded")
PlayersService.PlayerRemoving = newSignal("Players.PlayerRemoving")
PlayersService.GetPlayers = function()
	return table.clone(playerList)
end
PlayersService.GetPlayerFromCharacter = function(_, character)
	for _, p in ipairs(playerList) do
		if rawget(p, "__props").Character == character then
			return p
		end
	end
	return nil
end
PlayersService.GetHumanoidDescriptionFromUserId = function()
	return newStub("HumanoidDescription")
end

-- A client script reads `Players.LocalPlayer` at the top of its body, and on a stub that is
-- a stub -- indexing forever and comparing false, so `LocalPlayer.Character` is a stub too
-- and `:WaitForChild("PlayerGui")` never resolves to anything a UI module can parent to. It
-- has to be a real player object, present *before* the client boots, because the require
-- chain reads it during the module bodies rather than later.
if PLACE == "client" then
	local localPlayer = newInst("LocalPlayer", "Player")
	localPlayer.UserId = 1
	localPlayer.Parent = PlayersService
	localPlayer.CharacterAdded = newSignal("Player.CharacterAdded")
	localPlayer.CharacterRemoving = newSignal("Player.CharacterRemoving")
	newInst("PlayerGui", "PlayerGui", localPlayer)
	table.insert(playerList, localPlayer)
	PlayersService.LocalPlayer = localPlayer
end

local RunServiceObject = newInst("RunService", "RunService")
RunServiceObject.IsStudio = function()
	return true
end
-- The client tree branches on these, so answering "server" during a client run would test
-- the wrong half of every one of those branches.
RunServiceObject.IsServer = function()
	return PLACE ~= "client"
end
RunServiceObject.IsClient = function()
	return PLACE == "client"
end
RunServiceObject.IsRunning = function()
	return true
end
RunServiceObject.Heartbeat = newSignal("RunService.Heartbeat")
RunServiceObject.Stepped = newSignal("RunService.Stepped")
RunServiceObject.PostSimulation = newSignal("RunService.PostSimulation")

local services = {
	ReplicatedStorage = ReplicatedStorage,
	ServerScriptService = ServerScriptService,
	ServerStorage = ServerStorage,
	Players = PlayersService,
	RunService = RunServiceObject,
	StarterPlayer = StarterPlayer,
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
		if type(target) == "table" and rawget(target, "__missingFrom") ~= nil then
			-- The path walked off the end of a folder built from the file list on disk.
			-- Roblox raises on the *index*, before require ever sees it, so this is a hard
			-- failure and the message is worded the way Studio words it.
			table.insert(failures, {
				rel = chain:match("[^ ]+$") or chain,
				err = `{rawget(target, "__missingKey")} is not a valid member of `
					.. `{rawget(target, "__missingClass")} "{rawget(target, "__missingFrom")}" `
					.. `-- required a module that is not there. Check which folder it lives in.`,
				chain = chain,
			})
			return newStub("missing")
		end
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
		elseif result == nil and rawget(target, "class") == "ModuleScript" then
			-- A ModuleScript that returns nothing is a hard error in Roblox ("Module code did
			-- not return exactly one value"), and every consumer of it indexes nil. This used
			-- to hand back a permissive stub, and that one line is why the gate stayed green
			-- while `src/lobby/server/services/LobbyService.luau` sat at **zero bytes** for
			-- four days: an empty file returns nil, the stub answered `:Init()` and `:Start()`
			-- happily, and the lobby "booted" in a harness where the only service that
			-- teleports a player into the game did not exist.
			--
			-- The permissiveness above it is still right and stays: a require of something
			-- this harness never mapped is a gap in the harness. This is the opposite case --
			-- the file was found, it was run, and what it did was wrong.
			table.insert(failures, {
				rel = rel,
				err = "returned nil -- a ModuleScript must return a value, and Roblox raises "
					.. "'Module code did not return exactly one value'. An empty file does this.",
				chain = chain,
			})
			loaded[target] = newStub("noreturn")
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

local serverInit = bootNode
local rootRequire = makeRequire("(boot)")

print("BOOTCHECK-BEGIN")

-- ProfileStore is vendor code and is not what this gate is testing. Run against a stubbed
-- DataStoreService the real one would either fail or yield forever inside
-- `StartSessionAsync`, and every service downstream would then be reading fields off a
-- stub -- which reports as a cascade of fake bugs in our code. So the module is swapped for
-- a mock that honours the contract DataService actually depends on: a session returns a
-- deep copy of the template, `Reconcile` fills missing top-level keys from it, and the data
-- is a real table all the way down so `Lives.Active(profile.Data)` is a real life.
local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = deepCopy(v)
	end
	return out
end

if profileStore ~= nil then
	loaded[profileStore] = {
		New = function(_name, template)
			local store = {}
			function store:StartSessionAsync(_key, _params)
				local session = {
					Data = deepCopy(template),
					UserIds = {},
					OnSessionEnd = newSignal("Profile.OnSessionEnd"),
				}
				function session:AddUserId(id)
					table.insert(self.UserIds, id)
				end
				function session:Reconcile()
					for k, v in pairs(template) do
						if self.Data[k] == nil then
							self.Data[k] = deepCopy(v)
						end
					end
				end
				function session:IsActive()
					return true
				end
				function session:EndSession() end
				function session:Save() end
				return session
			end
			return store
		end,
	}
end

-- The bootstrap itself: requires every service and drives Init()/Start().
local ok, err = pcall(function()
	return rootRequire(serverInit)
end)
if not ok then
	table.insert(failures, { rel = "src/server/init.server.luau", err = tostring(err), chain = "(boot)" })
end

--------------------------------------------------------------------------------
-- Can it actually be played?
--
-- Boot proves the services started. This proves a player can join, get a profile, have a
-- life begun and have a body applied -- the path whose failure looks exactly like a
-- successful boot from the outside.
--------------------------------------------------------------------------------

local function newCharacter(name)
	local model = newInst(name, "Model")
	local humanoid = newInst("Humanoid", "Humanoid", model)
	-- Matched to what `ensureR15` tests. The Enum stub caches by key, so this is the *same*
	-- table the game reads -- and `Stub.__eq` must answer `rawequal` for that to mean
	-- anything, because Luau consults `__eq` even on identical references (see the note on
	-- it). Get either half wrong and BodyService decides this rig is R6, rebuilds the
	-- character into a stub and the band sizes nothing: a harness artifact that reads
	-- exactly like the real body bug, which is what it did on the first run of this phase.
	humanoid.RigType = baseEnv.Enum.HumanoidRigType.R15
	humanoid.WalkSpeed = 16
	humanoid.JumpPower = 50
	for _, scale in
		{
			"BodyHeightScale",
			"BodyWidthScale",
			"BodyDepthScale",
			"HeadScale",
			"BodyProportionScale",
			"BodyTypeScale",
		}
	do
		local value = newInst(scale, "NumberValue", humanoid)
		value.Value = 1
	end
	newInst("Animate", "LocalScript", model)
	newInst("HumanoidRootPart", "Part", model)
	newInst("Head", "Part", model)
	return model
end

-- The join phase is a *server* question: a player arrives, a profile loads, a life begins,
-- a body is sized. On the client there is no such moment -- the script runs as the player,
-- so getting through its own require chain and building its UI is the whole test, and it
-- has already happened above. Driving PlayerAdded here would be asking the client to answer
-- for the server and reporting its silence as a failure.
if ok and PLACE ~= "client" then
	-- From here on, deferred work actually runs, and warnings are actually heard.
	--
	-- Both are off during boot for good reasons (a service's tick loop belongs to a
	-- scheduler that does not exist here; a module body that warns at load is noise). Neither
	-- reason survives the join phase. `LifeService:Start` hooks PlayerAdded with
	-- `task.spawn(pushInitialState, player)` -- the call that gives the client its age, its
	-- money and its first event -- so a `spawn` that swallows its function leaves the single
	-- most player-visible path on the join untested, and the harness would call a player who
	-- sees no HUD at all a clean join.
	--
	-- The spin risk is handled rather than avoided: `task.wait` still burns the same budget
	-- and still throws past it, and each body runs under its own pcall, so a `while true` in
	-- a spawned function is *recorded against the join* instead of hanging the gate.
	--
	-- Warnings matter here because this game diagnoses itself in them. "spawned before their
	-- profile loaded", "rig has no R15 scale values", "arrived on slot N with no life to
	-- play" -- every one of those is the answer to the question this phase is asking, written
	-- by the person who wrote the path, and `warn = function() end` threw them all away.
	local joinWarnings = {}
	baseEnv.warn = function(...)
		local parts = {}
		for index = 1, select("#", ...) do
			table.insert(parts, tostring((select(index, ...))))
		end
		table.insert(joinWarnings, table.concat(parts, " "))
	end
	local function runDeferred(fn, ...)
		if type(fn) ~= "function" then
			-- `task.spawn(thread)` is legal Roblox. Nothing in this tree does it, and
			-- resuming a coroutine here would need a scheduler, so it stays a no-op.
			return
		end
		local args = table.pack(...)
		-- Per body, not per run: the budget means "this one never returns", so a tenth
		-- spawned function must not inherit nine functions' worth of legitimate waiting.
		waits = 0
		local spawnedOk, spawnErr = pcall(function()
			fn(table.unpack(args, 1, args.n))
		end)
		if not spawnedOk then
			table.insert(joinFailures, { signal = "task.spawn", err = tostring(spawnErr) })
		end
	end
	baseEnv.task.spawn = runDeferred
	baseEnv.task.defer = runDeferred
	baseEnv.task.delay = function(_seconds, fn, ...)
		runDeferred(fn, ...)
	end
	baseEnv.spawn = runDeferred

	local player = newInst("TestPlayer", "Player", nil)
	player.UserId = 1
	player.Parent = PlayersService
	player.CharacterAdded = newSignal("Player.CharacterAdded")
	player.CharacterRemoving = newSignal("Player.CharacterRemoving")
	player.Kick = function(_, reason)
		table.insert(joinFailures, { signal = "Player:Kick", err = tostring(reason) })
	end
	table.insert(playerList, player)

	-- Order mirrors Roblox: the player exists, then PlayerAdded fires, then a character
	-- spawns. Studio's own "player is already here before the server starts" case is what
	-- ReturnService:Start's GetPlayers loop covers, and that already ran during boot.
	local firedOk, fireErr = pcall(function()
		PlayersService.PlayerAdded:Fire(player)
	end)
	if not firedOk then
		table.insert(joinFailures, { signal = "PlayerAdded", err = tostring(fireErr) })
	end

	local character = newCharacter("TestPlayer")
	player.Character = character
	local charOk, charErr = pcall(function()
		player.CharacterAdded:Fire(character)
	end)
	if not charOk then
		table.insert(joinFailures, { signal = "CharacterAdded", err = tostring(charErr) })
	end

	-- What the player would actually see. A life that never begins is the exact symptom
	-- being chased: you stand in the world, adult-sized, and nothing happens.
	local report = { "unknown" }
	local probeOk, probeErr = pcall(function()
		local dataService = nil
		local lives = nil
		for _, entry in ipairs(order) do
			if entry.rel == "src/server/services/DataService.luau" then
				dataService = entry.value
			elseif entry.rel == "src/shared/Lives.luau" then
				lives = entry.value
			end
		end
		if dataService == nil or lives == nil then
			report = { "could not find DataService or Lives in the loaded set" }
			return
		end
		local profile = dataService.GetProfile(player)
		if profile == nil then
			report = { "no profile: DataService never stored one for the joining player" }
			return
		end
		-- The lobby stops here on purpose. A life is not begun and no body band is applied
		-- there -- that is the game place's job, after the teleport -- so asserting either
		-- would be inventing a requirement and failing the lobby for meeting its own spec.
		-- What the lobby has to do on join is load the profile and push the slots, and a
		-- profile that arrived is the half of that this harness can see honestly.
		if PLACE == "lobby" then
			local slots = profile.Data.slots
			report = {
				`profile=loaded`,
				`slots={tostring(if type(slots) == "table" then #slots else "missing")}`,
			}
			return
		end
		local life = lives.Active(profile.Data)
		-- Read off the character the player is *currently* wearing, not the one this driver
		-- built: `ensureR15` legitimately replaces the character, and reporting the scales of
		-- a body nobody is in would be a green light for a player standing there adult-sized.
		local worn = player.Character
		local humanoid = worn ~= nil and worn:FindFirstChildOfClass("Humanoid") or nil
		if humanoid == nil then
			report = { "no humanoid: the character the player ended up wearing has none" }
			return
		end
		report = {
			`begun={tostring(lives.HasBegun(life))}`,
			`alive={tostring(life.alive)}`,
			`ageMonths={tostring(life.ageMonths)}`,
			`heightScale={tostring(humanoid.BodyHeightScale.Value)}`,
			`walkSpeed={tostring(humanoid.WalkSpeed)}`,
		}
	end)
	if not probeOk then
		report = { "probe threw: " .. tostring(probeErr) }
	end
	print("BOOTCHECK-PLAY\t" .. table.concat(report, "  "))

	for _, f in ipairs(joinFailures) do
		print("BOOTCHECK-JOINFAIL\t" .. f.signal .. "\t" .. f.err:gsub("\n", " "))
	end
	-- Warnings this harness *causes* are not findings, and printing them is how a gate stops
	-- being read. This one mounts the script tree and nothing else -- no `assets/*.rbxmx` --
	-- so `CollectionService:GetTagged` is empty by construction and every place lookup warns
	-- that its point is missing. That is a statement about the harness, not about the town,
	-- and `tools/check_town.py` is the gate that actually checks the town has its points.
	--
	-- Kept to exact substrings of warnings whose cause is a mounting decision made in this
	-- file. Anything wider would start hiding the game's own diagnosis, which is the entire
	-- reason `warn` was made to speak at all.
	local harnessBlindSpots = {
		'nothing tagged "AgesPlacePoint"',
	}
	local seenWarning = {}
	for _, message in ipairs(joinWarnings) do
		local flat = message:gsub("\n", " ")
		local blind = false
		for _, needle in ipairs(harnessBlindSpots) do
			if string.find(flat, needle, 1, true) ~= nil then
				blind = true
				break
			end
		end
		-- Deduplicated because one warning per retry becomes a wall, and a wall is read as
		-- noise and then not read at all.
		if not blind and not seenWarning[flat] then
			seenWarning[flat] = true
			print("BOOTCHECK-JOINWARN\t" .. flat)
		end
	end
end

for _, f in ipairs(failures) do
	print("BOOTCHECK-FAIL\t" .. f.rel .. "\t" .. f.err:gsub("\n", " ") .. "\t" .. f.chain)
end
print("BOOTCHECK-LOADED\t" .. tostring(#order))
print("BOOTCHECK-END")
