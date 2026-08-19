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
-- `ensureR15` parents the rebuilt character here. Every other file in this tree binds the
-- service this way; this one read a bare `Workspace` instead, which is not a Luau global --
-- so the R6 rebuild path threw on the assignment, and an R6 player was left standing in a
-- destroyed-then-not-replaced character. Only R6 avatars ever reached that line, which is
-- why it survived: on an R15 account the function returns two lines earlier.
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Lives = require(ReplicatedStorage:WaitForChild("Lives"))

local DataService = require(script.Parent.DataService)

type ChildhoodBand = Types.ChildhoodBand
type AnimationSet = Types.AnimationSet

local warnedAboutRig = false
local warnedAboutAnimate = false

-- The slots Roblox's own Animate script exposes as StringValue children. Checked
-- against rather than trusted, because a mistyped slot -- "wlak" -- would set an
-- animation on nothing at all and look exactly like an animation that failed to
-- load, which is the wrong thing to go and investigate.
local ANIMATION_SLOTS: { [string]: boolean } = {
	idle = true,
	walk = true,
	run = true,
	jump = true,
	fall = true,
	climb = true,
	swim = true,
	swimidle = true,
	sit = true,
}

-- Bands are matched by id, so an entry under a band that does not exist is a
-- typo that would otherwise be a body that never changes how it moves.
local function bandExists(id: string): boolean
	for _, band in Config.Childhood.Bands do
		if band.id == id then
			return true
		end
	end
	return false
end

-- "rbxassetid://507777826" and 507777826 both mean the same thing to a person
-- and only one of them means anything to an Animation, so both are accepted and
-- exactly one form leaves here.
local function normalizeAssetId(raw: string | number, where: string): string
	if type(raw) == "number" then
		if raw <= 0 or raw % 1 ~= 0 then
			error(`[AGES config] {where} is {raw}; an animation asset id is a positive whole number`)
		end
		return `rbxassetid://{raw}`
	end
	local digits = string.match(raw, "^rbxassetid://(%d+)$") or string.match(raw, "^(%d+)$")
	if digits == nil then
		error(`[AGES config] {where} is "{raw}"; expected a number or "rbxassetid://<number>"`)
	end
	return `rbxassetid://{digits}`
end

-- Read once, at load, so a bad id is a server that refuses to start rather than
-- a toddler who stands up in one specific room.
local ANIMATIONS: { [string]: AnimationSet } = {}
for bandId, set in Config.Childhood.Animations do
	if not bandExists(bandId) then
		error(`[AGES config] Childhood.Animations has an entry for band "{bandId}", which is not in Childhood.Bands`)
	end
	local resolved: AnimationSet = {}
	for slot, raw in set do
		if not ANIMATION_SLOTS[slot] then
			error(`[AGES config] Childhood.Animations.{bandId} has slot "{slot}", which the Animate script has no place for`)
		end
		resolved[slot] = normalizeAssetId(raw, `Childhood.Animations.{bandId}.{slot}`)
	end
	ANIMATIONS[bandId] = resolved
end

-- What each Animation held before we first touched it, so a band with no
-- override for a slot puts Roblox's own back rather than leaving the last band's
-- animation on a body that has outgrown it. Weak-keyed: a character that has
-- been destroyed should not be kept alive by our memory of how it used to move.
local originals: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any

-- How long to wait on a spawning character for the parts this service needs.
-- Generous because both are waits on Roblox's own spawn sequence rather than on
-- anything here: exceeding either means something is wrong with the rig, which
-- is worth a warning rather than a longer wait.
local HUMANOID_TIMEOUT = 10
local SCALE_VALUE_TIMEOUT = 5

-- Rebuild an R6 character as R15, from the player's own appearance.
--
-- The size ladder is written onto R15 scale values, which an R6 rig does not have --
-- so an R6 avatar loads normal-sized and the baby body silently does not show, which
-- reads as a broken mechanic rather than a wrong avatar setting. Rather than warn and
-- leave it, swap in an R15 version of the same person: `GetHumanoidDescriptionFromUserId`
-- reads their exact appearance and `CreateHumanoidModelFromDescription` rebuilds it as
-- R15, so nobody sees a different avatar, only the same one at the same spot that can
-- now shrink. Reassigning `player.Character` fires CharacterAdded again, so the rebuilt
-- character takes the ordinary path below and this call stops here.
--
-- Returns true when the character can keep going (it is R15, or the rebuild failed and
-- the fallback warning applies), false when the hand-off is done and the caller must
-- return. BodyService is the only CharacterAdded listener in this place, so the second
-- event is observed here and nowhere else.
local function ensureR15(player: Player, character: Model, humanoid: Humanoid): boolean
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return true
	end
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	local rebuilt: Model? = nil
	if ok and description ~= nil then
		rebuilt = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end
	if rebuilt == nil then
		warn(`[AGES] {player.Name} loaded an R6 character and it could not be rebuilt as R15; the size ladder will not show`)
		return true
	end
	rebuilt.Parent = Workspace
	rebuilt:PivotTo(character:GetPivot())
	player.Character = rebuilt
	character:Destroy()
	return false
end

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

local function applyToHumanoid(humanoid: Humanoid, band: ChildhoodBand, ageYears: number)
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
	--
	-- Read off the age rather than off the band, so growing up is continuous and
	-- goes on past the last band: the bands stop at five because that is where
	-- jumping and running stop changing, but a twelve-year-old is not adult-sized
	-- and used to be. Same curve every townsperson is built from, which is what
	-- makes a classmate your own age actually your own height.
	local body, head = Config.Growth.At(ageYears)
	local scales: { [string]: number } = {
		BodyHeightScale = body,
		BodyWidthScale = body,
		BodyDepthScale = body,
		HeadScale = head,
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

-- The Animate script reads its ids once and caches them, so writing new ones is
-- only half the job -- it has to be made to look again. Disabling and re-enabling
-- is the whole reload: it drops the running track and rebuilds the set from what
-- the children say now.
--
-- Deferred rather than waited on, because Apply runs on the aging-up path and a
-- yield there would put a frame between the new body and the new speed.
local function reloadAnimate(animate: BaseScript)
	animate.Disabled = true
	task.defer(function()
		-- The character can be gone by the next frame -- a death on the same tick
		-- as a birthday -- and re-enabling a script that has been reparented out
		-- of a destroyed model achieves nothing except a confusing warning.
		if animate.Parent ~= nil then
			animate.Disabled = false
		end
	end)
end

-- Swaps the character's animation set to the one this band moves with, and puts
-- Roblox's defaults back for every slot the band does not name.
local function applyAnimations(character: Model, band: ChildhoodBand)
	local set = ANIMATIONS[band.id]

	local animate = character:FindFirstChild("Animate")
	if animate == nil or not animate:IsA("BaseScript") then
		-- Silent when there is nothing to apply: a rig with no Animate script and
		-- no overrides configured is just Roblox's default behaviour, which is
		-- not a fault. Only worth saying when we had something to say and no
		-- surface to say it on.
		if set ~= nil and not warnedAboutAnimate then
			warnedAboutAnimate = true
			warn(`[AGES] {character.Name} has no Animate script; band "{band.id}" will move like a default rig`)
		end
		return
	end

	local changed = false
	for _, slot in animate:GetChildren() do
		if not slot:IsA("StringValue") then
			continue
		end
		local override = if set ~= nil then set[slot.Name] else nil

		-- Every Animation under the slot, not the first: idle ships as two
		-- variants the script alternates between, and swapping one of them is a
		-- body that crawls half the time.
		for _, animation in slot:GetChildren() do
			if not animation:IsA("Animation") then
				continue
			end
			if originals[animation] == nil then
				originals[animation] = animation.AnimationId
			end
			local target = override or originals[animation]
			if animation.AnimationId ~= target then
				animation.AnimationId = target
				changed = true
			end
		end
	end

	-- Reloading unconditionally would restart the walk cycle on every birthday
	-- and every respawn, including the ones where nothing about the set moved.
	if changed then
		reloadAnimate(animate)
	end
end

-- What a band actually moves with, for the debug command. Says which slots are
-- overridden and which are Roblox's, because "the crawl is not playing" has two
-- very different causes and they are told apart here.
function BodyService.DescribeAnimations(bandId: string): string
	local set = ANIMATIONS[bandId]
	if set == nil then
		return `{bandId}: default rig animations, nothing overridden`
	end
	local slots: { string } = {}
	for slot, id in set do
		table.insert(slots, `{slot}={id}`)
	end
	table.sort(slots)
	return `{bandId}: {table.concat(slots, ", ")}`
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

	local ageYears = Lives.Active(profile.Data).ageMonths // Config.Time.MonthsPerYear
	local band = BodyService.BandForAge(ageYears)
	applyToHumanoid(humanoid, band, ageYears)
	applyAnimations(character, band)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", HUMANOID_TIMEOUT)
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		warn(`[AGES] {player.Name} spawned without a Humanoid; body band not applied`)
		return
	end

	-- Before the scale-value wait, so an R6 character is never read for the values it
	-- cannot have. On an R6 avatar this rebuilds the character and returns false; the
	-- CharacterAdded event the rebuild fires then runs this same path against the R15.
	if not ensureR15(player, character, humanoid) then
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

	-- Roblox parents the Animate script after the Humanoid too, and a band whose
	-- animations are applied before it arrives is a toddler who walks upright for
	-- their whole first life -- the same class of miss as the scale values above,
	-- with the same fix.
	character:WaitForChild("Animate", SCALE_VALUE_TIMEOUT)

	-- The profile is what says how old this body is, and on a fresh join it is
	-- still loading from ProfileStore when the character spawns. Without this the
	-- player spawns adult-sized and stays that way for the whole first life,
	-- because nothing spawns them again to put it right -- which is exactly the
	-- silent no-op the old comment here mistook for a safe one.
	-- Bound, not discarded. This call used to be written as a bare `... == nil` test and the
	-- profile it returned was thrown away, while the `Lives.Active(profile.Data)` forty lines
	-- down read `profile` as a *global* -- nil -- and threw on the index. Every spawn died
	-- there, one line above the `BodyService.Apply` that is the entire point of this function,
	-- so every player stood up adult-sized no matter how correct the rest of the path was.
	local profile = DataService.WaitForProfile(player)
	if profile == nil then
		warn(`[AGES] {player.Name} spawned before their profile loaded; body band not applied`)
		return
	end

	-- Both waits above yield, and a life can end or a player leave inside them.
	-- Applying a band to a character that has since been replaced would size the
	-- wrong body, or resurrect a stale one.
	if player.Character ~= character then
		return
	end

	-- An unbegun slot has no setup yet, so its age is still zero and its body has
	-- no band. Applying one here would size the character adult on the first frame,
	-- before ReturnService has had a chance to begin a child life and put the right
	-- scales on. Wait for the life to be begun, then apply.
	local data = Lives.Active(profile.Data)
	if not Lives.HasBegun(data) then
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
