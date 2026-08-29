--!strict
-- Sitting down.
--
-- Every roleplay game of this kind has it and this one had nothing: a school full of sofas,
-- benches, bleachers and two hundred cafeteria stools, and no way to be on any of them. The
-- furniture was scenery.
--
-- **Client-side, deliberately.** `Humanoid.Sit` on your own character replicates to everyone
-- else on its own, so a remote round trip would add latency to an action whose whole appeal
-- is that it is instant. Nothing here is worth cheating at -- the worst a modified client can
-- do is sit down somewhere odd -- so the server is not asked to referee it. That is the same
-- reasoning the codebase applies to the rhythm lesson's judging, in the opposite direction:
-- there the client decides because it must, here because there is no cost to it.
--
-- The seat search is what makes it feel intentional rather than a pose. Pressing L next to a
-- bench should put you *on the bench*; pressing it in the middle of a corridor should sit you
-- where you stand. Both are one key, and which one happens is decided by what is near you --
-- the world is the menu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local SIT = Config.Sit

local Sit = {}

-- What counts as furniture you can be on. Matched on the part's name, because the school is
-- laid by Kit and Kit names what it builds -- LoungeSofa3, Bleacher2, CafeteriaChair11 -- and
-- a name is the one property every one of them already carries. Tagging every seat at build
-- time would be tidier and would also mean the baked asset had to be regenerated to add a
-- kind of chair, which is a worse trade.
local SEAT_WORDS = {
	"sofa",
	"chair",
	"bench",
	"stool",
	"bleacher",
	"armchair",
	"seat",
	"pew",
}

local function looksSittable(part: BasePart): boolean
	local name = string.lower(part.Name)
	for _, word in SEAT_WORDS do
		if string.find(name, word, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function characterParts(): (Model?, Humanoid?, BasePart?)
	local character = Players.LocalPlayer.Character
	if character == nil then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return character, humanoid, root
end

-- The nearest sittable surface, or nil. Searches the parts already near the player rather
-- than walking the whole Workspace: the school alone is seventeen hundred parts and this runs
-- on a keypress, not on a tick.
local function nearestSeat(root: BasePart): BasePart?
	local region = OverlapParams.new()
	region.FilterType = Enum.RaycastFilterType.Exclude
	local character = root.Parent
	if character ~= nil then
		region.FilterDescendantsInstances = { character }
	end

	local found = workspace:GetPartBoundsInRadius(root.Position, SIT.ReachStuds, region)
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, part in found do
		if looksSittable(part) then
			-- Its top has to be somewhere a person could actually perch: a skirting board
			-- called "BenchBase" is not a bench, and sitting on a wall reads as a bug.
			local top = part.Position.Y + part.Size.Y / 2
			local rise = top - (root.Position.Y - SIT.HipHeightStuds)
			if rise >= -SIT.MaxRiseStuds and rise <= SIT.MaxRiseStuds then
				local distance = (part.Position - root.Position).Magnitude
				if distance < bestDistance then
					best = part
					bestDistance = distance
				end
			end
		end
	end
	return best
end

-- Sits, or stands up if already sitting.
function Sit.Toggle()
	local character, humanoid, root = characterParts()
	if character == nil or humanoid == nil or root == nil then
		return
	end

	if humanoid.Sit then
		humanoid.Sit = false
		return
	end

	-- Not while doing something that owns the body. Sitting mid-fight or mid-swim is the kind
	-- of state nothing else in the game is written to expect.
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Swimming then
		return
	end

	local seat = nearestSeat(root)
	if seat ~= nil then
		-- Put them on it first, facing the way the seat faces. CFrame rather than Position so
		-- the turn comes with it: a character sitting on a bench side-on looks like a bug and
		-- costs nothing to avoid.
		local top = seat.Position.Y + seat.Size.Y / 2
		local facing = seat.CFrame.LookVector
		root.CFrame = CFrame.new(
			Vector3.new(seat.Position.X, top + SIT.HipHeightStuds, seat.Position.Z),
			Vector3.new(seat.Position.X, top + SIT.HipHeightStuds, seat.Position.Z) + facing
		)
	end

	humanoid.Sit = true
end

function Sit.Start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.L then
			Sit.Toggle()
		end
	end)
end

return Sit
