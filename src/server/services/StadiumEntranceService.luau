--!strict
-- The stadium's entrance moment: walk through the bowl's own gate and the
-- camera cuts in close on you while a fan jogs over for an autograph -- the
-- same walkout beat a broadcast gives a player before kickoff (NBA 2K,
-- EA FC). Once per player per server session -- there is no save-file flag
-- for this, and there does not need to be one: the moment is meant to land
-- the first time a life walks in this session, not to be re-earned every
-- life or suppressed forever the first time it fires.
--
-- Split the same way every other cutscene-shaped feature in this codebase
-- is: the server decides *whether* (crossed the gate, hasn't seen it yet)
-- and *who* (which fan), the client owns the camera, because a camera is
-- inherently local -- two players walking through the gate together must
-- each get their own close shot without either one seeing the other's.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local NPCService = require(script.Parent.NPCService)
local Public = require(script.Parent.Parent.content.Public)

local ENTRANCE = Config.StadiumEntrance

local CUE = Remotes.Get("StadiumEntranceCue")

local StadiumEntranceService = {}

local gates: { BasePart } = {}
-- Who has already played the moment this server session. Keyed by UserId
-- rather than Player so a mid-session rejoin (same account, new Player
-- instance) still counts as already seen -- the whole point is "once", not
-- "once per connection".
local seen: { [number]: boolean } = {}
local enabled = true

local function indexGates()
	gates = {}
	for _, instance in CollectionService:GetTagged(ENTRANCE.GateTag) do
		if instance:IsA("BasePart") then
			table.insert(gates, instance)
		end
	end
end

-- The fan's own brief beat: walk in from beside the gate, ask for the
-- autograph, hold, then head back into the concourse crowd. A thin wrapper
-- around NPCService.Spawn/walkTo/talk rather than NPCService.Arrive -- Arrive
-- is written for a doorstep delivery that waits to be *reached*; this fan
-- reaches the player instead, and leaves on a timer rather than a pickup.
local function runFan(player: Player, gate: BasePart)
	local member = Public.Someone()
	-- The invisible gate trigger spans GROUND..GROUND+6 (see gen_city.py's
	-- EntranceTrigger); half that gets back to floor height without the
	-- service needing to know the world generator's own GROUND constant.
	local floorY = gate.Position.Y - 3.0
	-- A little inside the concourse the player is walking into and off to one
	-- side, not blocking the doorway itself.
	local startPosition = Vector3.new(gate.Position.X + 6.0, floorY, gate.Position.Z + 4.0)

	task.spawn(function()
		local visitor = NPCService.Spawn(player, member, CFrame.new(startPosition))
		if visitor == nil then
			return
		end
		local character = player.Character
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if root == nil or not root:IsA("BasePart") or visitor.gone() then
			visitor.destroy()
			return
		end

		local toPlayer = root.Position - startPosition
		local flat = Vector3.new(toPlayer.X, 0, toPlayer.Z)
		local approachFrom = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, 1)
		local waitPosition = root.Position - approachFrom * ENTRANCE.FanApproachStuds

		visitor.walkTo(waitPosition)
		if visitor.gone() then
			return
		end
		local liveCharacter = player.Character
		local liveRoot = if liveCharacter ~= nil then liveCharacter:FindFirstChild("HumanoidRootPart") else nil
		visitor.face(if liveRoot ~= nil and liveRoot:IsA("BasePart") then liveRoot.Position else nil)
		visitor.greet()
		task.wait(ENTRANCE.FanTalkBeatSeconds)
		if visitor.gone() then
			return
		end
		visitor.talk()
		task.wait(1.0)
		if visitor.gone() then
			return
		end
		visitor.face(nil)
		visitor.walkTo(startPosition)
		visitor.destroy()
	end)
end

-- Marks the player seen, cues the client's camera, and sends a fan over.
-- Shared by the tick's own crossing check and by the debug command below, so
-- a developer forcing the moment early exercises exactly the same path a
-- real crossing does rather than a second, drifting copy of it.
local function fire(player: Player, gate: BasePart)
	seen[player.UserId] = true
	CUE:FireClient(player)
	runFan(player, gate)
end

local function tick()
	if not enabled or #gates == 0 then
		return
	end
	local radius = ENTRANCE.TriggerRadius
	for _, player in Players:GetPlayers() do
		if seen[player.UserId] then
			continue
		end
		local character = player.Character
		if character == nil then
			continue
		end
		local pivot = character:GetPivot().Position
		for _, gate in gates do
			if (pivot - gate.Position).Magnitude <= radius then
				fire(player, gate)
				break
			end
		end
	end
end

function StadiumEntranceService.SetEnabled(value: boolean)
	enabled = value
end

function StadiumEntranceService.IsEnabled(): boolean
	return enabled
end

-- Debug only: clears one player's "already played" flag so a developer can
-- walk back through the gate and watch the moment fire again without
-- restarting the server.
function StadiumEntranceService.ResetPlayer(userId: number)
	seen[userId] = nil
end

-- Debug only: fires the moment for this player right now, off whichever gate
-- is nearest them, without needing to actually walk to the stadium first.
-- Refuses rather than picking an arbitrary gate when none has been indexed,
-- because "silently did nothing" and "there is no gate in this world" read
-- identically from the command line otherwise.
function StadiumEntranceService.ForcePlayer(player: Player): boolean
	if #gates == 0 then
		return false
	end
	local character = player.Character
	if character == nil then
		return false
	end
	local pivot = character:GetPivot().Position
	local nearest, nearestDistance = gates[1], math.huge
	for _, gate in gates do
		local distance = (pivot - gate.Position).Magnitude
		if distance < nearestDistance then
			nearest, nearestDistance = gate, distance
		end
	end
	fire(player, nearest)
	return true
end

function StadiumEntranceService.Describe(): string
	local played = 0
	for _ in seen do
		played += 1
	end
	return `stadium entrance: {#gates} gate(s), {played} player(s) have played it this session ({if enabled then "on" else "DISABLED"})`
end

function StadiumEntranceService:Init()
	indexGates()
end

function StadiumEntranceService:Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		seen[player.UserId] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(ENTRANCE.TickSeconds)
			local ok, err = pcall(tick)
			if not ok then
				warn(`[AGES] stadium entrance tick failed: {err}`)
			end
		end
	end)
end

return StadiumEntranceService
