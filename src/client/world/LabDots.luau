--!strict
-- The lab's stations, lit or dark, for this player only.
--
-- The lab is one room. It is built once and everybody in the school stands in the same
-- copy of it, which is right -- furniture is a thing anybody walking past can see -- but
-- it means the server cannot turn a station's dots off for one player without turning
-- them off for the whole place. And they need turning off constantly: a beaker is a step
-- in a procedure for the twenty seconds somebody is running one, and a piece of scenery
-- for the rest of the school day.
--
-- Without this the stations would sit permanently lit, and a player crossing the lab
-- between lessons would click one and watch nothing happen. That is the silent failure
-- the whole three-dot grammar exists to prevent: dots are a promise that there is
-- something here to do, and a promise the game does not keep once is a promise the
-- player stops reading.
--
-- So it is done here, on the client, the same way every other per-player fact about a
-- shared world is. Writing `Enabled` on a replicated instance from the client is a local
-- change that never travels back, which is exactly what is wanted -- and it is safe from
-- being clobbered because Lab.luau sets these two properties once at build time and
-- never touches them again.
--
-- Driven off the same LabUpdated push the panel is, so the dots and the panel can never
-- disagree about whether there is a lesson on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Interact = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Interact"))

local LabDots = {}
LabDots.__index = LabDots

export type LabDotsHandle = typeof(setmetatable(
	{} :: {
		-- Whether a procedure is running right now. Held because stations stream in and
		-- out for the whole session and one that arrives mid-lesson has to be lit on the
		-- way in -- a station the player walked past while it was loading would otherwise
		-- stay dark for the rest of the lesson.
		lit: boolean,
	},
	LabDots
))

-- The dots beside a prompt. Siblings rather than nested, for the reason Prompts.luau
-- gives: a BillboardGui inside a ProximityPrompt is not a thing Roblox renders.
local function dotsFor(prompt: ProximityPrompt): BillboardGui?
	local parent = prompt.Parent
	if parent == nil then
		return nil
	end
	local dots = parent:FindFirstChild(Interact.DotsName)
	if dots ~= nil and dots:IsA("BillboardGui") then
		return dots
	end
	return nil
end

local function isStationPrompt(instance: Instance): boolean
	if not instance:IsA("ProximityPrompt") or instance.Name ~= Interact.PromptName then
		return false
	end
	return instance:GetAttribute(Interact.KindAttribute) == "Station"
end

local function apply(prompt: ProximityPrompt, lit: boolean)
	prompt.Enabled = lit
	local dots = dotsFor(prompt)
	if dots ~= nil then
		dots.Enabled = lit
	end
end

function LabDots.new(): LabDotsHandle
	-- Dark to begin with, because almost every moment of a life has no procedure in it
	-- and the first thing the player sees of the lab should be a quiet room. The first
	-- push of a lesson lights it.
	local self = setmetatable({ lit = false }, LabDots)

	for _, instance in Workspace:GetDescendants() do
		if isStationPrompt(instance) then
			apply(instance :: ProximityPrompt, self.lit)
		end
	end

	-- Stations stream in and out for the whole session. A cheap class test first, for the
	-- reason Prompts.luau does the same: this fires for every part of every rig in the town.
	Workspace.DescendantAdded:Connect(function(instance: Instance)
		if isStationPrompt(instance) then
			apply(instance :: ProximityPrompt, self.lit)
		end
	end)

	return self
end

-- Lit while a procedure is running, dark otherwise. Idempotent, and called on every
-- push -- which is four times a second during a lesson -- so it exits early rather than
-- walking the whole workspace to set a hundred properties to the values they already hold.
function LabDots.SetRunning(self: LabDotsHandle, running: boolean)
	if self.lit == running then
		return
	end
	self.lit = running

	for _, instance in Workspace:GetDescendants() do
		if isStationPrompt(instance) then
			apply(instance :: ProximityPrompt, running)
		end
	end
end

return LabDots
