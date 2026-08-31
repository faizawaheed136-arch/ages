--!strict
-- The heavy bag and the weight bench.
--
-- Both are "do a thing, count it, and when you have done enough the aura fires". The counting
-- lives here rather than in either station, so a session can be finished on whichever piece of
-- equipment the player happens to be standing at.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Aura = require(script.Parent.Aura)
local Workout = require(ReplicatedStorage:WaitForChild("Showcase"):WaitForChild("Workout"))

local BAG_TAG = "PunchingBag"
local BENCH_TAG = "WeightBench"

local THUD_SOUND = "rbxassetid://0" -- replace: leather, low, short. Not a punch whoosh.

local GymService = {}

local wired: { [Instance]: true } = {}
local progress: { [Player]: { strikes: number, reps: number } } = {}
local lastAction: { [Player]: number } = {}
local tracks: { [Humanoid]: { [string]: AnimationTrack } } = {}

-- ---------------------------------------------------------------------------------------
-- Animation
-- ---------------------------------------------------------------------------------------

-- **Cached per humanoid.** LoadAnimation allocates an AnimationTrack and an Animation instance
-- every call; doing it per punch on a bag somebody is hitting twice a second is a steady leak
-- that shows up half an hour into a session, not at the start.
local function trackFor(humanoid: Humanoid, id: string, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
	if id == "rbxassetid://0" then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		return nil
	end

	local byId = tracks[humanoid]
	if byId == nil then
		byId = {}
		tracks[humanoid] = byId
		-- Humanoids die and are replaced; without this the cache holds every character the
		-- player has ever had.
		humanoid.Destroying:Once(function()
			tracks[humanoid] = nil
		end)
	end

	local existing = (byId :: any)[id]
	if existing ~= nil then
		return existing
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or track == nil then
		return nil
	end
	track.Priority = priority
	track.Looped = looped
	;(byId :: any)[id] = track
	return track
end

-- ---------------------------------------------------------------------------------------
-- Progress
-- ---------------------------------------------------------------------------------------

local function ready(player: Player, cooldown: number): boolean
	local last = lastAction[player]
	if last ~= nil and os.clock() - last < cooldown then
		return false
	end
	lastAction[player] = os.clock()
	return true
end

local function record(player: Player, station: Workout.Station)
	local state = progress[player]
	if state == nil then
		state = { strikes = 0, reps = 0 }
		progress[player] = state
	end

	if station == "bag" then
		state.strikes += 1
	else
		state.reps += 1
	end

	-- Either station can finish a session, and finishing resets both counters -- so a session is
	-- something you complete rather than a running total that grants an aura every twelve hits
	-- forever.
	if state.strikes >= Workout.StrikesPerSession or state.reps >= Workout.RepsPerSession then
		state.strikes = 0
		state.reps = 0
		Aura.Grant(player)
	end
end

-- ---------------------------------------------------------------------------------------
-- 1. The heavy bag
-- ---------------------------------------------------------------------------------------

local function wireBag(instance: Instance)
	if wired[instance] or not instance:IsA("BasePart") then
		return
	end
	wired[instance] = true
	local bag = instance :: BasePart

	-- **The server simulates the bag.**
	--
	-- Left to default ownership, whichever client is nearest owns the physics and every other
	-- player sees a different swing -- the bag is somewhere else for everybody. Handing it to
	-- the server costs a little bandwidth and makes one swing that everyone agrees on.
	pcall(function()
		bag:SetNetworkOwner(nil)
	end)
	if bag.Anchored then
		warn(`[Gym] {bag:GetFullName()} is anchored -- it will never swing. Hang it on a RopeConstraint instead.`)
	end

	if THUD_SOUND ~= "rbxassetid://0" and bag:FindFirstChild("Thud") == nil then
		local sound = Instance.new("Sound")
		sound.Name = "Thud"
		sound.SoundId = THUD_SOUND
		-- Pitched down and rolled off hard: a heavy bag is a dull low sound you feel more than
		-- hear, and it should not carry across the hall.
		sound.Volume = 0.9
		sound.PlaybackSpeed = 0.82
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMaxDistance = 70
		sound.Parent = bag
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BagPrompt"
	prompt.ActionText = "Strike"
	prompt.ObjectText = "Heavy Bag"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = bag

	prompt.Triggered:Connect(function(player: Player)
		if not ready(player, Workout.StrikeCooldown) then
			return
		end
		local character = player.Character
		local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if humanoid == nil or root == nil then
			return
		end

		local strike = trackFor(humanoid, Workout.Animations.Strike, Enum.AnimationPriority.Action, false)
		if strike ~= nil then
			strike:Play(0.1)
		end

		-- Horizontal only. Including the vertical component means striking from slightly below
		-- launches the bag at the ceiling, which is the first thing anyone tries.
		local away = bag.Position - (root :: BasePart).Position
		local direction = Vector3.new(away.X, 0, away.Z)
		if direction.Magnitude > 0.01 then
			bag:ApplyImpulse(direction.Unit * Workout.StrikeImpulse)
		end

		local thud = bag:FindFirstChild("Thud") :: Sound?
		if thud ~= nil then
			thud:Play()
		end

		record(player, "bag")
	end)
end

-- ---------------------------------------------------------------------------------------
-- 2. The weight bench
-- ---------------------------------------------------------------------------------------

local function wireBench(instance: Instance)
	if wired[instance] or not instance:IsA("Seat") then
		return
	end
	wired[instance] = true
	local seat = instance :: Seat

	-- The bar is a sibling named Barbell. Optional: without it the reps still count and the
	-- animation still plays, there is just nothing to lift.
	local barbell = seat.Parent and seat.Parent:FindFirstChild("Barbell")
	local barbellPart = if barbell ~= nil and barbell:IsA("BasePart") then barbell :: BasePart else nil
	local barbellHome = if barbellPart ~= nil then barbellPart.CFrame else nil

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LiftPrompt"
	prompt.ActionText = "Lift"
	prompt.ObjectText = "Barbell"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	-- Off until somebody sits. A lift prompt floating over an empty bench invites a player to
	-- press it from standing and watch nothing happen.
	prompt.Enabled = false
	prompt.Parent = barbellPart or seat

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		if occupant == nil then
			prompt.Enabled = false
			return
		end
		local player = Players:GetPlayerFromCharacter(occupant.Parent)
		if player == nil then
			return
		end

		-- **Action priority is what makes this a bench press and not a sit.**
		--
		-- A Seat plays its own sitting pose at Core priority. A looped idle at Action outranks
		-- it and holds the character flat; drop it to Movement or below and the avatar sits
		-- bolt upright on the bench with the barbell going up and down above its head.
		local idle = trackFor(occupant, Workout.Animations.BenchIdle, Enum.AnimationPriority.Action, true)
		if idle ~= nil then
			idle:Play(0.25)
		end
		prompt.Enabled = true

		local connection: RBXScriptConnection
		connection = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			if seat.Occupant ~= occupant then
				connection:Disconnect()
				prompt.Enabled = false
				if idle ~= nil then
					idle:Stop(0.25)
				end
				if barbellPart ~= nil and barbellHome ~= nil then
					barbellPart.CFrame = barbellHome
				end
			end
		end)
		occupant.Died:Once(function()
			prompt.Enabled = false
		end)
	end)

	prompt.Triggered:Connect(function(player: Player)
		local occupant = seat.Occupant
		if occupant == nil or Players:GetPlayerFromCharacter(occupant.Parent) ~= player then
			return
		end
		if not ready(player, Workout.RepCooldown) then
			return
		end

		local press = trackFor(occupant, Workout.Animations.BenchPress, Enum.AnimationPriority.Action2, false)
		local duration = if press ~= nil and press.Length > 0 then press.Length else 1.0
		if press ~= nil then
			press:Play(0.08)
		end

		-- **The bar is tweened to the animation's own length, not to a fixed number.**
		--
		-- Swap in a longer press and the bar stays in sync for free. The better version welds
		-- the barbell to the hands so the animation moves it directly -- do that once you have
		-- a real rig; this keeps the two together in the meantime and needs no rig at all.
		if barbellPart ~= nil and barbellHome ~= nil then
			local half = TweenInfo.new(duration / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			local down = TweenService:Create(barbellPart, half, {
				CFrame = barbellHome * CFrame.new(0, -Workout.BarbellTravel, 0),
			})
			down.Completed:Once(function()
				TweenService:Create(barbellPart, half, { CFrame = barbellHome }):Play()
			end)
			down:Play()
		end

		record(player, "bench")
	end)
end

-- ---------------------------------------------------------------------------------------
-- Start
-- ---------------------------------------------------------------------------------------

local function bind(tag: string, wire: (Instance) -> ())
	for _, instance in CollectionService:GetTagged(tag) do
		wire(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(wire)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		wired[instance] = nil
	end)
end

function GymService.Start()
	bind(BAG_TAG, wireBag)
	bind(BENCH_TAG, wireBench)

	Players.PlayerRemoving:Connect(function(player)
		progress[player] = nil
		lastAction[player] = nil
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			-- A new character has no aura and no half-finished session. Leaving the counters
			-- alone means a player who dies at eleven strikes gets the aura from one punch.
			progress[player] = { strikes = 0, reps = 0 }
			Aura.Clear(character)
		end)
	end)
end

return GymService
