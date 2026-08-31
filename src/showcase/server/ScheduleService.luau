--!strict
-- Drives the academy day, and rings the bell.
--
-- The loop is self-correcting: it asks the clock what period it is, sleeps until that period
-- ends, then asks again. It never accumulates, so it cannot drift -- see Schedule.At.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Schedule = require(ReplicatedStorage:WaitForChild("Showcase"):WaitForChild("Schedule"))

-- **Replace this.** A heavy cast-iron tower bell with a long tail, not a school handbell.
-- Until it is a real id the system runs correctly and silently, which is worth knowing before
-- you spend an hour looking for the bug.
local BELL_ASSET = "rbxassetid://0"

-- Seconds between strikes when a period rings more than once. 2.4 is long enough that the tail
-- of one strike is still audible under the attack of the next, which is what makes a sequence
-- read as a tolling bell rather than as a repeated sound effect.
local STRIKE_GAP = 2.4

local ScheduleService = {}

local current: string? = nil
local bell: Sound? = nil

-- ---------------------------------------------------------------------------------------
-- Remotes
-- ---------------------------------------------------------------------------------------

local function folderUnder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		return existing :: Folder
	end
	local made = Instance.new("Folder")
	made.Name = name
	made.Parent = parent
	return made
end

local function remote(name: string): RemoteEvent
	local folder = folderUnder(folderUnder(ReplicatedStorage, "Showcase"), "Remotes")
	local existing = folder:FindFirstChild(name)
	if existing ~= nil then
		return existing :: RemoteEvent
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = folder
	return event
end

local PeriodChanged = remote("PeriodChanged")

-- ---------------------------------------------------------------------------------------
-- Audio
-- ---------------------------------------------------------------------------------------

-- **Why the server owns the sound.**
--
-- A Sound whose parent is not a BasePart or Attachment is non-positional: every listener hears
-- it at full volume wherever they are on the map. Parented to SoundService and played by the
-- server, its play state replicates -- so one call rings it for everybody, in sync, with no
-- remote of its own.
--
-- The alternative -- fire a remote and have each client play a local copy -- sounds identical
-- with one player and falls apart with several, because each client's copy starts whenever its
-- packet happened to land.
local function buildBell(): Sound
	local group = SoundService:FindFirstChild("Chime") :: SoundGroup?
	if group == nil then
		group = Instance.new("SoundGroup")
		group.Name = "Chime"
		-- Its own group so a mixer can duck the bell against ambience later without touching
		-- either one's Volume directly.
		group.Volume = 1
		group.Parent = SoundService

		-- "Resonant" is mostly these two, not the sample.
		local reverb = Instance.new("ReverbSoundEffect")
		reverb.DecayTime = 2.8
		reverb.Density = 0.9
		reverb.Diffusion = 0.9
		reverb.DryLevel = 0
		reverb.WetLevel = -6
		reverb.Parent = group

		-- Iron, rather than brass: lift the low end for weight and pull the top down so the
		-- strike stops sounding like a handbell.
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = 4
		eq.MidGain = -2
		eq.HighGain = -7
		eq.Parent = group
	end

	local sound = Instance.new("Sound")
	sound.Name = "IronBell"
	sound.SoundId = BELL_ASSET
	sound.Volume = 0.9
	-- Pitched down a fifth of an octave. The cheapest way to make any bell sample sound like a
	-- bigger, heavier bell than it was recorded from.
	sound.PlaybackSpeed = 0.85
	sound.SoundGroup = group
	sound.Parent = SoundService
	return sound
end

local function ring(times: number)
	local sound = bell
	if sound == nil then
		return
	end
	task.spawn(function()
		for strike = 1, times do
			-- A fresh play rather than a loop: a bell struck again while still ringing should
			-- layer over its own tail, and restarting the same Sound instance cuts it off.
			sound:Play()
			if strike < times then
				task.wait(STRIKE_GAP)
			end
		end
	end)
end

-- ---------------------------------------------------------------------------------------
-- The loop
-- ---------------------------------------------------------------------------------------

local function now(): number
	-- The clock both sides share. os.time() would work on the server alone but is not the
	-- clock the client can read, and os.clock() is per-machine uptime.
	return workspace:GetServerTimeNow()
end

local function announce(period: Schedule.Period, remaining: number, transition: boolean)
	PeriodChanged:FireAllClients(period.Key, remaining, transition)
	if transition then
		ring(period.Rings)
	end
end

function ScheduleService.Start()
	bell = buildBell()

	-- Preload, or the first strike of the session is silent. Roblox streams a sound on first
	-- play, so an unloaded bell either arrives late or is dropped entirely -- and it is always
	-- the first one, which is the one somebody is watching for.
	task.spawn(function()
		local sound = bell
		if sound ~= nil and sound.SoundId ~= "rbxassetid://0" then
			pcall(ContentProvider.PreloadAsync, ContentProvider, { sound })
		end
	end)

	-- A player who joins mid-period gets the period and its remaining time, but **no bell**:
	-- they did not witness a change, and ringing on join means the bell fires every time anyone
	-- connects rather than when the day moves.
	Players.PlayerAdded:Connect(function(player)
		local period, _, remaining = Schedule.At(now())
		PeriodChanged:FireClient(player, period.Key, remaining, false)
	end)

	task.spawn(function()
		while true do
			local period, _, remaining = Schedule.At(now())

			if period.Key ~= current then
				local transition = current ~= nil -- the very first tick is not a "change"
				current = period.Key
				announce(period, remaining, transition)
			end

			-- Sleep to the boundary and re-derive, so any overshoot is absorbed by the next
			-- iteration instead of accumulating. The small epsilon keeps a float landing exactly
			-- on the boundary from spinning.
			task.wait(math.max(remaining, 0) + 0.05)
		end
	end)
end

-- For a debug command: jump the day forward without waiting for it.
function ScheduleService.Current(): (Schedule.Period, number)
	local period, _, remaining = Schedule.At(now())
	return period, remaining
end

return ScheduleService
