--!strict
-- Taking the map's own buildings out of the world, reversibly.
--
-- Several things in this tree lay a building in code on ground the map has already built on:
-- School replaces the street's school, GymRoom replaces the town's gym. Without this both
-- exist at once, and the result is not merely ugly -- **it is wrong**. The town gym is the
-- clear case: `Workspace.Town.Gym` carries real `GymKind` attributes on four machines, so a
-- second gym laid on top of it means GymService indexes two sets and half the equipment a
-- player walks up to is inside a wall.
--
-- **Hidden, never destroyed.** Everything named here belongs to the map, which is generated
-- by `tools/` and owned by another agent. Destroy is not reversible inside a session and a
-- mistake would cost a re-sync; parenting into ServerStorage means a wrong call costs a drag
-- in Studio instead, and means the decision can be reversed from a debug command while
-- standing in the room.
--
-- **What must never be stood down.** A model that carries attributes is load-bearing for some
-- other system, and taking it away silently breaks that system rather than tidying the world:
--
--   City.RunningTrack   FacilityKind=track
--   City.SoccerField    FacilityKind=soccer, SportsDrillKind=soccer
--   City.BoxingGym      FacilityKind=boxing, SportsDrillKind=boxing
--
-- Those stay. The one deliberate exception is `Town.Gym`, whose attributes are the very
-- thing being replaced -- GymRoom lays the same four kinds itself, so standing it down swaps
-- one complete set of machines for another rather than removing a capability.

local ServerStorage = game:GetService("ServerStorage")

local StandDown = {}

-- Where stood-down models are kept, one folder per caller so two callers cannot clear each
-- other's work.
local holds: { [string]: Folder } = {}

local function holdFor(key: string): Folder
	local existing = holds[key]
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = `StoodDown_{key}`
	made.Parent = ServerStorage
	holds[key] = made
	return made
end

export type Target = {
	-- The Workspace child the model lives under: "Street", "City", "Town".
	parent: string,
	-- The model's own name.
	model: string,
}

-- Stands a list of models down. Returns how many actually moved, so a caller can tell "there
-- was nothing there" from "it worked" -- the two look identical from the outside and only one
-- of them is worth reporting.
--
-- Safe to call repeatedly: a model already stood down is simply not found in Workspace again.
function StandDown.Hide(key: string, targets: { Target }): number
	local moved = 0
	for _, target in targets do
		local parent = workspace:FindFirstChild(target.parent)
		if parent ~= nil then
			local model = parent:FindFirstChild(target.model)
			if model ~= nil then
				-- The original parent is recorded on the model itself rather than in a table
				-- here, so Restore still works if this module is reloaded underneath it.
				model:SetAttribute("StoodDownFrom", target.parent)
				model.Parent = holdFor(key)
				moved += 1
			end
		end
	end
	return moved
end

-- Puts everything a key stood down back where it came from.
function StandDown.Restore(key: string): number
	local hold = holds[key]
	if hold == nil or hold.Parent == nil then
		return 0
	end
	local put = 0
	for _, model in hold:GetChildren() do
		local from = model:GetAttribute("StoodDownFrom")
		local parent = if typeof(from) == "string" then workspace:FindFirstChild(from) else nil
		if parent ~= nil then
			model:SetAttribute("StoodDownFrom", nil)
			model.Parent = parent
			put += 1
		end
	end
	hold:Destroy()
	holds[key] = nil
	return put
end

-- Whether anything is currently stood down under a key.
function StandDown.IsHidden(key: string): boolean
	local hold = holds[key]
	return hold ~= nil and hold.Parent ~= nil and #hold:GetChildren() > 0
end

-- What a key has stood down, by name, for a debug line that can say which models moved rather
-- than only how many.
function StandDown.Names(key: string): { string }
	local names = {}
	local hold = holds[key]
	if hold ~= nil and hold.Parent ~= nil then
		for _, model in hold:GetChildren() do
			table.insert(names, model.Name)
		end
	end
	table.sort(names)
	return names
end

return StandDown
