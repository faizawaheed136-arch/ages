--!strict
-- The hand wraps a locker gives you.
--
-- Built in code rather than dragged into ServerStorage by hand, so it is version-controlled as
-- text and every showcase place gets the same tool. Swap `buildHandle` for a MeshPart clone
-- when you have real geometry -- nothing else in this file changes.

local ServerStorage = game:GetService("ServerStorage")

local TOOL_NAME = "Hand Wraps"

local HandWraps = {}

local template: Tool? = nil

local function buildHandle(): BasePart
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	-- Roughly a fist's worth of wrapped cloth. Small, because a Tool handle that is too big
	-- clips through the forearm on most idle animations.
	handle.Size = Vector3.new(1, 0.45, 1.5)
	handle.Color = Color3.fromRGB(206, 200, 186)
	handle.Material = Enum.Material.Fabric
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	-- Massless, or the tool changes how the character moves. A player who picks up wraps and
	-- starts walking differently is a bug nobody thinks to look for in a Tool.
	handle.Massless = true
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	return handle
end

local function build(): Tool
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.ToolTip = "Cloth wraps. Standard issue."
	tool.RequiresHandle = true
	-- **False, deliberately.** In a showcase, droppable tools end up as a field of wraps on the
	-- corridor floor within a minute of anyone finding the backspace key.
	tool.CanBeDropped = false

	local handle = buildHandle()
	handle.Parent = tool

	-- Sits in the palm rather than at the wrist. Adjust with the Grip properties in Studio and
	-- copy the number back here -- eyeballing this in code is slower than it looks.
	tool.Grip = CFrame.new(0, -0.15, 0.1)

	tool.Parent = ServerStorage
	return tool
end

function HandWraps.Template(): Tool
	if template == nil or template.Parent == nil then
		local existing = ServerStorage:FindFirstChild(TOOL_NAME)
		template = if existing ~= nil then existing :: Tool else build()
	end
	return template :: Tool
end

-- Idempotent on purpose: opening a second locker should not hand out a second pair.
function HandWraps.Give(player: Player): boolean
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack == nil then
		return false
	end
	if backpack:FindFirstChild(TOOL_NAME) ~= nil then
		return false
	end
	-- Also check the character: a tool the player is currently *holding* has been reparented out
	-- of the Backpack, so checking only the Backpack hands out a duplicate to anyone with the
	-- wraps already equipped.
	local character = player.Character
	if character ~= nil and character:FindFirstChild(TOOL_NAME) ~= nil then
		return false
	end

	HandWraps.Template():Clone().Parent = backpack
	return true
end

function HandWraps.HasWraps(player: Player): boolean
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	return (backpack ~= nil and backpack:FindFirstChild(TOOL_NAME) ~= nil)
		or (character ~= nil and character:FindFirstChild(TOOL_NAME) ~= nil)
end

return HandWraps
