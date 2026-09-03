--!strict
-- The showcase place, started.
--
-- Order matters in exactly one place: the shell goes up before the services bind, because
-- everything tagged in it -- doors, lockers, rings, benches, the bag -- is found by
-- CollectionService at Start(). Bind first and the tags arrive to an empty listener.

local ServerScriptService = game:GetService("ServerScriptService")

local Shell = require(ServerScriptService:WaitForChild("ShowcaseWorld"):WaitForChild("Shell"))

-- Centred on the origin. The plan works in 0..400 by 0..448 and this is the only place a world
-- coordinate is added, so moving the whole academy is a change to this one line.
local ORIGIN = Vector3.new(-Shell.Width / 2, 0, -Shell.Depth / 2)

local ok, err = pcall(function()
	Shell.Build(ORIGIN)
end)
if not ok then
	warn(`[Showcase] the shell failed to build: {err}`)
end

-- **Always, even when the shell stood down.**
--
-- Shell.Build returns early if the baked model is already in the workspace, and the baked model
-- carries every *static* prop. What it cannot carry is a Seat or a bag on two constraints, so
-- those are laid here on every boot regardless of which path the shell took.
local Props = require(ServerScriptService:WaitForChild("ShowcaseWorld"):WaitForChild("Props"))
local placed, problem = pcall(function()
	Props.Dynamic(workspace, function(x: number, y: number, z: number)
		return ORIGIN + Vector3.new(x, y, z)
	end)
end)
if not placed then
	warn(`[Showcase] the dynamic props failed: {problem}`)
end

-- Best effort, each in its own pcall: a service that throws should cost its own feature and not
-- the six that come after it in this list.
for _, name in { "WardrobeService", "ScheduleService", "DoorService", "ArenaService", "GymService", "VendingService" } do
	local module = script:FindFirstChild(name)
	if module == nil then
		warn(`[Showcase] {name} is missing`)
		continue
	end
	local started, problem = pcall(function()
		require(module :: ModuleScript).Start()
	end)
	if not started then
		warn(`[Showcase] {name} failed to start: {problem}`)
	end
end
