--!strict
-- The body a life is currently living in. Through the toddler years the player's
-- capability *is* the progression: a crawler is slow, tiny and cannot jump, and
-- five years later the same house is crossable in seconds. Nothing about the
-- world changes to make that happen, so this service is the whole mechanism.
--
-- Server-authoritative on purpose. WalkSpeed and JumpPower are the difference
-- between a room being reachable and not, so a client that could set its own
-- would walk out of childhood early.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))

local DataService = require(script.Parent.DataService)

type ChildhoodBand = Types.ChildhoodBand

local warnedAboutRig = false

-- How long to wait on a spawning character for the parts this service needs.
-- Generous because both are waits on Roblox's own spawn sequence rather than on
-- anything here: exceeding either means something is wrong with the rig, which
-- is worth a warning rather than a longer wait.
local HUMANOID_TIMEOUT = 10
local SCALE_VALUE_TIMEOUT = 5

local BodyService = {}

function BodyService.BandForAge(ageYears: number): ChildhoodBand
	for _, band in Config.Childhood.Bands do
		if ageYears <= band.maxAge then
			return band
		end
	end
	-- Unreachable: the final band is unbounded. Returning it keeps the function
	-- total rather than making every caller handle a nil that cannot occur.
	return Config.Childhood.Bands[#Config.Childhood.Bands]
end

local function applyToHumanoid(humanoid: Humanoid, band: ChildhoodBand)
	humanoid.WalkSpeed = band.walkSpeed
	-- Newer rigs default to JumpHeight; forcing JumpPower makes the configured
	-- number the one that counts, including jumpPower = 0 meaning "cannot jump".
	humanoid.UseJumpPower = true
	humanoid.JumpPower = band.jumpPower
	humanoid.CameraOffset = Vector3.new(0, band.cameraOffsetY, 0)

	-- R15 exposes body proportions as NumberValues parented to the Humanoid. R6
	-- has no equivalent, so on an R6 rig the size ladder would silently not
	-- happen — hence the warning rather than a quiet no-op. Head stays large
	-- relative to the body, which is most of what reads as "young".
	local scales: { [string]: number } = {
		BodyHeightScale = band.bodyScale,
		BodyWidthScale = band.bodyScale,
		BodyDepthScale = band.bodyScale,
		HeadScale = band.headScale,
	}

	local scaled = true
	for valueName, target in scales do
		local value = humanoid:FindFirstChild(valueName)
		if value ~= nil and value:IsA("NumberValue") then
			value.Value = target
		else
			scaled = false
		end
	end

	if not scaled and not warnedAboutRig then
		warnedAboutRig = true
		warn("[AGES] character rig has no R15 scale values; the childhood size ladder will not show. Set the avatar rig type to R15.")
	end
end

-- Applies the band for a player's current age to their current character.
--
-- Does nothing without a profile or a character, which is correct for the
-- callers that re-apply a band to a life already underway -- aging up, dying --
-- since both of those hold one already. It is *not* a safe way to size a body
-- for the first time: the spawn path above waits for both rather than calling
-- this and hoping, because a miss there is a player who stays adult-sized for
-- their whole childhood.
function BodyService.Apply(player: Player)
	local profile = DataService.GetProfile(player)
	if profile == nil then
		return
	end

	local character = player.Character
	if character == nil then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end

	local ageYears = profile.Data.ageMonths // Config.Time.MonthsPerYear
	applyToHumanoid(humanoid, BodyService.BandForAge(ageYears))
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", HUMANOID_TIMEOUT)
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		warn(`[AGES] {player.Name} spawned without a Humanoid; body band not applied`)
		return
	end

	-- The scale values are created when the avatar's description is applied,
	-- which lands after the Humanoid itself does. Reading them on the frame the
	-- character appears therefore finds nothing on a perfectly good R15 rig, and
	-- the code below reports that as "this rig is R6" -- a wrong diagnosis that
	-- sends whoever reads it to change a setting that was never the problem.
	--
	-- Waiting on one is enough: they are created together, so if the first is
	-- there the rest are, and if it never comes the rig really has none.
	humanoid:WaitForChild("BodyHeightScale", SCALE_VALUE_TIMEOUT)

	-- The profile is what says how old this body is, and on a fresh join it is
	-- still loading from ProfileStore when the character spawns. Without this the
	-- player spawns adult-sized and stays that way for the whole first life,
	-- because nothing spawns them again to put it right -- which is exactly the
	-- silent no-op the old comment here mistook for a safe one.
	if DataService.WaitForProfile(player) == nil then
		warn(`[AGES] {player.Name} spawned before their profile loaded; body band not applied`)
		return
	end

	-- Both waits above yield, and a life can end or a player leave inside them.
	-- Applying a band to a character that has since been replaced would size the
	-- wrong body, or resurrect a stale one.
	if player.Character ~= character then
		return
	end

	BodyService.Apply(player)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	if player.Character ~= nil then
		onCharacterAdded(player, player.Character)
	end
end

function BodyService:Init()
	Players.PlayerAdded:Connect(watch)
end

function BodyService:Start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return BodyService
