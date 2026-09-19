--!strict
--[[
	Spins the showroom turntables at Meridian Motors, on each client.

	Client-side because a server that turned anchored parts every frame would replicate every one
	of those moves to everyone, forever, for a thing that changes nothing: which way a display car
	is facing is decoration. Here each client turns its own copy and the network hears nothing.

	THE CAR ON THE TURNTABLE ARRIVES LATE, and parts stream in and out. So nothing is moved by
	pivoting the rotor as a whole -- a part that arrived after the rotor had turned would be carried
	round from wherever the pivot had got to, and sit crooked on its disc. Instead each part's rest
	position is taken, relative to the turntable's centre, the moment it arrives, from the
	server's copy (which never turns), and every frame every part is put back at that rest position
	turned by the current angle. A part that arrives at any moment slots straight into step.

	The centre never moves, so a display car's prompts stay where the server measures them from:
	the car turns about its own middle.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Matches world/DealershipBuild's tag, which the server applies; the client cannot require it.
local TAG = "DealershipTurntable"

type Spinner = {
	centre: CFrame,
	seconds: number,
	rest: { [BasePart]: CFrame },
	connections: { RBXScriptConnection },
}

local DealershipTurntables = {}

local spinners: { [Instance]: Spinner } = {}

local function track(turntable: Instance)
	if spinners[turntable] ~= nil then
		return
	end
	local centre = turntable:GetAttribute("Centre")
	local seconds = turntable:GetAttribute("SpinSeconds")
	if typeof(centre) ~= "Vector3" or typeof(seconds) ~= "number" or seconds <= 0 then
		return
	end
	local rotor = turntable:FindFirstChild("Rotor")
	if rotor == nil then
		-- Streamed in ahead of its rotor: take it up again when the rotor arrives.
		local waiting: RBXScriptConnection
		waiting = turntable.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Rotor" then
				waiting:Disconnect()
				track(turntable)
			end
		end)
		return
	end
	local spinner: Spinner = {
		centre = CFrame.new(centre),
		seconds = seconds,
		rest = {},
		connections = {},
	}
	local function add(instance: Instance)
		if instance:IsA("BasePart") and spinner.rest[instance] == nil then
			spinner.rest[instance] = spinner.centre:ToObjectSpace(instance.CFrame)
		end
	end
	for _, d in rotor:GetDescendants() do
		add(d)
	end
	table.insert(spinner.connections, rotor.DescendantAdded:Connect(add))
	table.insert(
		spinner.connections,
		rotor.DescendantRemoving:Connect(function(instance: Instance)
			if instance:IsA("BasePart") then
				spinner.rest[instance] = nil
			end
		end)
	)
	spinners[turntable] = spinner
end

local function untrack(turntable: Instance)
	local spinner = spinners[turntable]
	if spinner == nil then
		return
	end
	for _, connection in spinner.connections do
		connection:Disconnect()
	end
	spinners[turntable] = nil
end

local function step()
	local now = os.clock()
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	for _, spinner in spinners do
		local turned = spinner.centre * CFrame.Angles(0, (now / spinner.seconds % 1) * math.pi * 2, 0)
		for part, rest in spinner.rest do
			table.insert(parts, part)
			table.insert(frames, turned * rest)
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function DealershipTurntables.Start()
	for _, turntable in CollectionService:GetTagged(TAG) do
		track(turntable)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(untrack)
	RunService.RenderStepped:Connect(step)
end

return DealershipTurntables
