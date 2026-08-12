--!strict
-- The band on your head.
--
-- Small piece of geometry, and the most important thing in the gang feature. Everything
-- else -- standing, rungs, who runs which side -- is state a player reads off a panel.
-- This is the only part of it that is legible from across a street, and in a multiplayer
-- room mixing players with NPCs it is the entire answer to "whose side is that one on".
--
-- **Why it is geometry and not a nameplate.** A BillboardGui saying "Kestrel" over
-- somebody's head would be readable, always face you, and cost nothing -- and it would be
-- wrong, because it is readable *through walls* and at any distance, which turns a
-- recognition problem into a HUD. A band is occluded by the things that occlude a person,
-- goes ambiguous in a crowd at range, and can be taken off. Those are features. The
-- moment gangs can be identified perfectly, the disguise system stops meaning anything.
--
-- **Why it glows a little.** Config.Gangs.Bandana.Glow, not zero and not one. A purely
-- diffuse band drops to grey at dusk, which is exactly when a player most needs to count
-- who is in a room; a fully neon one reads as a powerup rather than as clothing.
--
-- Works on player characters and on NPC visitors without knowing the difference, because
-- both are Models with a Head, and a gang that could only be worn by one of the two would
-- be a gang whose members are only half visible.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local BANDANA = Config.Gangs.Bandana

-- The name the band is parented under, and the handle for finding one already there.
-- Anything looking for a band looks for this exact name, so it must not collide with a
-- Roblox accessory part -- "Handle" would, which is why this is not called that.
local BAND_NAME = "AgesGangBand"

-- How far the head can change size before the band is rebuilt rather than recolored.
--
-- Bands are welded at a fixed offset computed from the head they were built against, so a
-- life that grows from a nine-year-old to an adult inside one session would otherwise
-- wear a band sized for a child's skull, floating in front of an adult's. Half a stud is
-- comfortably below one growth band's worth of head and comfortably above float noise.
local RESIZE_TOLERANCE = 0.05

local Colors = {}

local function headOf(character: Model): BasePart?
	local head = character:FindFirstChild("Head")
	return if head ~= nil and head:IsA("BasePart") then head else nil
end

local function bandOf(character: Model): BasePart?
	local band = character:FindFirstChild(BAND_NAME)
	return if band ~= nil and band:IsA("BasePart") then band else nil
end

-- Whether this character is wearing a band right now. Read rather than remembered,
-- because the authority on what is on somebody's head is their head: a character can be
-- destroyed and respawned between any two ticks, and a cached answer would have the
-- service believing a dead body's hat.
function Colors.IsWearing(character: Model): boolean
	return bandOf(character) ~= nil
end

-- Take the band off. Safe to call on somebody who is not wearing one, which is most
-- people most of the time -- this runs on every tick for every player not in a gang.
function Colors.Clear(character: Model)
	local band = bandOf(character)
	if band ~= nil then
		band:Destroy()
	end
end

-- Put the band on, or leave it alone if the right one is already there.
--
-- Idempotent by construction and it has to be: the caller is a tick, so this is invoked
-- twice a second for the whole time somebody is in a gang. Rebuilding a welded part at
-- that rate would flicker and would churn the physics solver for no reason, so the common
-- path here is two comparisons and a return.
--
-- Returns false when there was nothing to put it on, which happens legitimately -- a
-- character mid-spawn has no Head yet -- and is the caller's cue to try again next tick
-- rather than to warn about it.
function Colors.Apply(character: Model, color: Color3): boolean
	local head = headOf(character)
	if head == nil then
		return false
	end

	local existing = bandOf(character)
	if existing ~= nil then
		-- Built against a head this size? Then the only thing that can have changed is
		-- which gang they are in, and that is a color assignment rather than a rebuild.
		local builtFor = existing:GetAttribute("HeadWidth")
		if type(builtFor) == "number" and math.abs(builtFor - head.Size.X) <= RESIZE_TOLERANCE then
			if existing.Color ~= color then
				existing.Color = color
			end
			return true
		end
		-- The head has grown. Fall through and build a new one; the old is destroyed
		-- below rather than here so that there is never a frame with no band at all,
		-- which at two ticks a second would read as a flicker.
	end

	local band = Instance.new("Part")
	band.Name = BAND_NAME
	-- Wider and deeper than the head it sits on by a small swell, so it reads as
	-- something worn rather than as a stripe painted on. Height is absolute rather than
	-- proportional: a band scaled to a child's head vanishes, and the whole point is that
	-- it survives being looked at from a distance.
	band.Size = Vector3.new(
		head.Size.X + BANDANA.Swell * 2,
		BANDANA.Height,
		head.Size.Z + BANDANA.Swell * 2
	)
	band.Color = color
	band.Material = Enum.Material.SmoothPlastic
	-- Every one of these matters and none is a default worth inheriting. A band that
	-- collided would push its wearer's own head; one that was queryable would be a
	-- sight-blocker between an officer and the face they are trying to describe, so
	-- joining a gang would make you *harder* to see -- backwards, and the exact class of
	-- bug the vault door's ignore flags were written to avoid. Massless keeps it off the
	-- humanoid's balance: a weighted hat on an R15 head changes how a character falls.
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.Massless = true
	band.CastShadow = false
	band.Anchored = false

	-- Remembered so the growth check above has something to compare against. On the part
	-- rather than in a table here, because the part outlives any bookkeeping this module
	-- could keep about a character that gets destroyed without telling anybody.
	band:SetAttribute("HeadWidth", head.Size.X)

	band.CFrame = head.CFrame * CFrame.new(0, BANDANA.Lift, 0)
	band.Parent = character

	-- WeldConstraint rather than Weld with an explicit C0: it takes the offset from where
	-- the two parts are at the moment it is enabled, which is what the line above just
	-- arranged, and it needs no rebuild when the head is rescaled by anything other than
	-- us. Parented to the band so that destroying the band takes the weld with it.
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = band
	weld.Parent = band

	if existing ~= nil then
		existing:Destroy()
	end

	return true
end

return Colors
