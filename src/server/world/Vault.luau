--!strict
-- The vault door at the back of the bank, the alarm panel by the entrance, and the ground
-- the guard walks between them.
--
-- Split from BankService for the reason Till is split from TheftService, Lab from
-- ScienceService and Wardrobe from DisguiseService: where a thing stands and what happens
-- when you reach it are different questions, and re-laying a room must never be able to
-- touch what a robbery is worth.
--
-- Stood up relative to a place point and a floor plan handed in from content, never off
-- the generated room's own furniture. The city generator already puts a box called `Vault`
-- in here and hanging the game off that name would mean the day somebody renames it is the
-- day the bank silently stops being robbable. See content/Vaults, which owns the plan and
-- explains why the numbers in it are the difficulty of this activity.
--
-- **Two things in this file are signposting rather than decoration, and both are load
-- bearing.** The door swings as the vault empties, so a bank that has already been done is
-- legible from the lobby -- which matters most to the second player through the entrance.
-- And the lamp on the alarm panel is the only readout that exists inside the room: it is
-- forty-eight studs from the vault on purpose, which is far enough that a player standing
-- at the money has to actually look up and across at it. A HUD light would have been read
-- without turning round, and turning round is the activity.
--
-- Built lazily, once, and left standing. One room's worth of parts is nothing, and tearing
-- it down when the last player leaves would restart the door's pose from closed -- which
-- would erase the one piece of shared state the room is carrying in the world.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Interact = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Interact"))

local Ground = require(script.Parent.Ground)

local Vault = {}

local BANK = Config.Crime.Bank

-- Cosmetic dimensions, kept out of Config for the reason ChoiceMarkers gives: nobody
-- balances this game by changing how thick a vault door is.
local DOOR_SIZE = Vector3.new(7, 9, 1.4)
local MOUTH_SIZE = Vector3.new(8.6, 10.2, 0.8)
-- How far behind the door the dark recess sits, so a door standing open reveals something
-- rather than revealing the wall behind it.
local MOUTH_BACK = 1.6
local WHEEL_SIZE = Vector3.new(0.5, 3.4, 3.4)
local WHEEL_OUT = 0.9
-- How far the door swings when the vault is empty, in degrees. Not a full ninety: a door
-- flat against the wall reads as scenery, and one at three-quarters still reads as a door
-- somebody opened.
local DOOR_SWING_DEGREES = 74
-- How many turns the wheel makes across the whole emptying. Enough that it is visibly
-- moving while the player holds, which is the only feedback the door itself gives.
local WHEEL_TURNS = 2.5

local PANEL_SIZE = Vector3.new(2.4, 3.2, 0.6)
local PANEL_LIFT = 4.6
local LAMP_SIZE = Vector3.new(1.5, 1.5, 1.5)
local LAMP_LIFT = 6.8

local DOOR_COLOR = Color3.fromRGB(96, 102, 114)
local WHEEL_COLOR = Color3.fromRGB(168, 152, 106)
local MOUTH_COLOR = Color3.fromRGB(16, 17, 21)
local PANEL_COLOR = Color3.fromRGB(58, 62, 70)

-- The lamp, in its three states. Red is the one colour this game uses for "you are being
-- seen" -- the same red as the heat bar's border, the shop camera's lens and the search
-- ring -- and amber is the one it uses for "in progress and not yet true", the same amber
-- as the hideout mark and the ring's sweep. A player learns both once.
local LAMP_QUIET = Color3.fromRGB(52, 56, 64)
local LAMP_RINGING = Color3.fromRGB(226, 78, 74)
local LAMP_SILENCED = Color3.fromRGB(238, 176, 74)

-- How far the light on the panel throws while the alarm is ringing. Reaches most of the
-- room without lighting the street outside, because the alarm is a fact about the building
-- and not an announcement to the town -- see BankService on why nothing here is broadcast.
local GLOW_RANGE = 34
local GLOW_BRIGHTNESS = 3
-- How long one blink of the lamp takes. Slow enough to read as an alarm bell rather than a
-- strobe, which matters because this thing is on for most of a minute.
local FLASH_SECONDS = 1.1

-- What the guard needs to stand in, for the standable check. A person's shoulders and a
-- person's height, which is what every other placement in this tree asks for.
local GUARD_RADIUS = 2
local GUARD_HEIGHT = 5

-- A spot on the floor, in studs from the place point. Declared here rather than imported
-- from content so that this file requires nothing but Config, Interact and Ground -- it
-- builds a room out of numbers and does not care who chose them. Structurally identical to
-- Vaults.Offset, which is what lets the plan be passed straight through.
export type Offset = {
	forward: number,
	side: number,
}

export type Plan = {
	roomStuds: number,
	vault: Offset,
	alarm: Offset,
	patrol: { Offset },
}

-- One built bank.
export type Room = {
	place: string,
	-- Where the entrance is and how far from it still counts as inside. Positions rather
	-- than parts, because every question asked of this room is arithmetic and nothing
	-- outside this file should be holding a handle on a piece of bank furniture.
	door: Vector3,
	roomStuds: number,
	vault: Vector3,
	alarm: Vector3,
	-- Where the guard walks, in order. Empty when there was nowhere standable to put him,
	-- which is a real outcome in a generated room -- the caller degrades to a bank with no
	-- guard rather than refusing the robbery, because a vault that cannot be opened for
	-- reasons invisible from the lobby is the worst version of this.
	patrol: { Vector3 },

	doorPart: BasePart,
	-- The closed door's pose, and the edge it turns about. Held rather than read back off
	-- the part, because the part's rotation *is* the swing -- reading the angle off a thing
	-- that has already been swung would compound it and spin the door off its frame. Same
	-- reason Till holds housingBase.
	hinge: CFrame,
	wheel: BasePart,
	wheelOffset: CFrame,
	lamp: BasePart,
	glow: PointLight,
	dots: Interact.InteractHandle?,
}

local rooms: { [string]: Room } = {}
local folder: Folder? = nil

local function vaultFolder(): Folder
	local existing = folder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "AgesVaults"
	made.Parent = workspace
	folder = made
	return made
end

local function buildBlock(parent: Instance, name: string, at: CFrame, size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = at
	part.Anchored = true
	-- Out of every ignore list in the game by construction, and the vault door especially.
	-- It swings, so a queryable one would be a sight-blocker whose position depends on how
	-- much of the vault the player has already taken -- which is to say the more you had
	-- stolen the easier it would be to hide from the guard. That is exactly backwards, and
	-- it is the kind of thing that would have read as the guard being unreliable rather
	-- than as a door being in the way.
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- The bank, stood up. Nil when the place point has no heading to build against, which the
-- caller reports by name -- a vault that silently failed to appear is a room the player
-- walks into and finds nothing in.
function Vault.Build(place: string, at: CFrame, label: string, plan: Plan): Room?
	local existing = rooms[place]
	if existing ~= nil and existing.doorPart.Parent ~= nil then
		return existing
	end

	local forward = at.LookVector
	local flat = Vector3.new(forward.X, 0, forward.Z)
	if flat.Magnitude < 1e-3 then
		-- A place point lying flat is a point with no heading to build against. Refused
		-- rather than guessed at: a vault built on a coin flip would be a vault inside a
		-- wall half the time, and a robbery that fails for reasons nobody can see.
		return nil
	end
	flat = flat.Unit
	-- To the right of somebody standing on the point looking into the room, which is what
	-- content/Vaults means by a positive `side`.
	local right = Vector3.new(flat.Z, 0, -flat.X)

	local group = Instance.new("Folder")
	group.Name = place
	group.Parent = vaultFolder()

	local base = at.Position
	local function spotFor(offset: Offset): Vector3
		return base + flat * offset.forward + right * offset.side
	end

	-- The vault, at the back. The door faces back into the room -- toward the player who
	-- has to stand at it -- rather than out along the place point's heading.
	local vaultAt = spotFor(plan.vault)
	local doorAt = vaultAt + Vector3.new(0, DOOR_SIZE.Y / 2, 0)
	local doorPart = buildBlock(group, "VaultDoor", CFrame.new(doorAt, doorAt - flat), DOOR_SIZE, DOOR_COLOR)

	local mouthAt = doorAt + flat * MOUTH_BACK
	buildBlock(group, "VaultMouth", CFrame.new(mouthAt, mouthAt - flat), MOUTH_SIZE, MOUTH_COLOR)

	-- The wheel. A cylinder's flat faces are on its X axis, so standing one against a door
	-- means turning it a quarter turn about Y first -- after which its spin is a roll about
	-- its own X. Same shape of correction Wardrobe's floor disc needs, and the same note:
	-- this is the one line here that looks like a mistake and is not.
	local wheelOffset = CFrame.new(0, 0, -WHEEL_OUT) * CFrame.Angles(0, math.rad(90), 0)
	local wheel = buildBlock(group, "VaultWheel", doorPart.CFrame * wheelOffset, WHEEL_SIZE, WHEEL_COLOR)
	wheel.Shape = Enum.PartType.Cylinder

	-- The alarm panel, by the entrance.
	local alarmAt = spotFor(plan.alarm)
	local panelAt = alarmAt + Vector3.new(0, PANEL_LIFT, 0)
	buildBlock(group, "AlarmPanel", CFrame.new(panelAt, panelAt - flat), PANEL_SIZE, PANEL_COLOR)

	local lampAt = alarmAt + Vector3.new(0, LAMP_LIFT, 0)
	local lamp = buildBlock(group, "AlarmLamp", CFrame.new(lampAt, lampAt - flat), LAMP_SIZE, LAMP_QUIET)
	lamp.Material = Enum.Material.Neon

	local glow = Instance.new("PointLight")
	glow.Name = "AlarmGlow"
	glow.Color = LAMP_RINGING
	glow.Range = GLOW_RANGE
	glow.Brightness = GLOW_BRIGHTNESS
	glow.Enabled = false
	glow.Parent = lamp

	-- Somewhere for the guard to walk. Asked of Ground rather than assumed, because the
	-- room is generated and what is standable in it differs from one build of the town to
	-- the next. Spots that do not survive are dropped rather than nudged: a patrol that
	-- silently moved itself would be a patrol the player learned and then found had changed.
	local ignore = Ground.IgnoreList({ group })
	local patrol: { Vector3 } = {}
	for _, offset in plan.patrol do
		local standable = Ground.SpotAt(spotFor(offset), GUARD_RADIUS, GUARD_HEIGHT, ignore, base)
		if standable ~= nil then
			table.insert(patrol, standable)
		end
	end
	if #patrol < 2 then
		-- One spot is not a patrol, it is a post. The caller runs the bank on its alarm
		-- alone, which is easier and is allowed to be.
		table.clear(patrol)
	end

	local room: Room = {
		place = place,
		door = base,
		roomStuds = plan.roomStuds,
		vault = vaultAt,
		alarm = alarmAt,
		patrol = patrol,
		doorPart = doorPart,
		hinge = doorPart.CFrame * CFrame.new(-DOOR_SIZE.X / 2, 0, 0),
		wheel = wheel,
		wheelOffset = wheelOffset,
		lamp = lamp,
		glow = glow,
		dots = nil,
	}

	-- The invitation, and it is on the vault door alone. The alarm panel deliberately has
	-- no dots on it: dots are how you enter an activity, and by the time the panel matters
	-- the player is already inside one. Its control lives on the panel that this click
	-- opens, which is also the only place it can live -- a second set of dots would mean
	-- two things in one room competing to be the nearest prompt while somebody runs
	-- between them.
	room.dots = Interact.Attach(doorPart, {
		kind = "Vault",
		id = place,
		actionText = "Open",
		objectText = label,
	})

	rooms[place] = room
	return room
end

function Vault.Get(place: string): Room?
	local room = rooms[place]
	if room == nil or room.doorPart.Parent == nil then
		return nil
	end
	return room
end

-- Whether a position is inside the building at all. What the whole robbery is held by:
-- walking away from the vault is the activity, walking out of here is the exit.
function Vault.InRoom(place: string, from: Vector3): boolean
	local room = Vault.Get(place)
	if room == nil then
		return false
	end
	return Ground.FlatDistance(from, room.door) <= room.roomStuds
end

-- Whether a position is close enough to have hands on the vault door.
function Vault.AtVault(place: string, from: Vector3): boolean
	local room = Vault.Get(place)
	if room == nil then
		return false
	end
	return Ground.FlatDistance(from, room.vault) <= BANK.ReachStuds
end

-- And on the alarm panel. The same reach as the vault, because it is the same gesture and
-- two numbers for "you are close enough to touch this" would be two things to learn.
function Vault.AtAlarm(place: string, from: Vector3): boolean
	local room = Vault.Get(place)
	if room == nil then
		return false
	end
	return Ground.FlatDistance(from, room.alarm) <= BANK.ReachStuds
end

-- Swings the door and turns the wheel. `emptyShare` is how much of the vault is gone, 0 to 1.
--
-- Told what to draw rather than working it out, for the same reason Till.AimCamera and
-- Wardrobe.Show are: what the money is doing is the activity and the activity lives in
-- BankService. This file turns a part.
function Vault.ShowDoor(place: string, emptyShare: number)
	local room = Vault.Get(place)
	if room == nil then
		return
	end
	local share = math.clamp(emptyShare, 0, 1)
	room.doorPart.CFrame = room.hinge
		* CFrame.Angles(0, math.rad(-DOOR_SWING_DEGREES * share), 0)
		* CFrame.new(DOOR_SIZE.X / 2, 0, 0)
	room.wheel.CFrame = room.doorPart.CFrame
		* room.wheelOffset
		* CFrame.Angles(share * WHEEL_TURNS * math.pi * 2, 0, 0)
end

-- Paints the lamp. `state` is "quiet", "ringing" or "silenced".
--
-- The flash's rate is worked out here rather than handed in, which is the opposite of what
-- Till.AimCamera does and the difference is worth naming. A shop camera's sweep *is* the
-- activity -- the player is timing a hold against it -- so it has to come off the same
-- clock the rules are read from. A bank alarm's blink is not timing anything; it is the
-- lamp being obviously on. Making it a number the service passed down would have implied a
-- beat there was something to play against.
--
-- Folded rather than a one-way fade, so the lamp is at its brightest twice a cycle and
-- reads as a beacon rather than as something warming up.
function Vault.ShowAlarm(place: string, state: string)
	local room = Vault.Get(place)
	if room == nil then
		return
	end
	if state == "ringing" then
		local pulse = (os.clock() / FLASH_SECONDS) % 1
		local folded = if pulse < 0.5 then pulse * 2 else (1 - pulse) * 2
		room.lamp.Color = LAMP_RINGING
		-- Never fully dark on the off beat. A lamp that blinked out would be a lamp a
		-- player glancing across the room at the wrong quarter-second reads as silent,
		-- which is the one lie this readout must not tell.
		room.lamp.Transparency = 0.45 * (1 - folded)
		room.glow.Enabled = true
		room.glow.Brightness = GLOW_BRIGHTNESS * (0.4 + 0.6 * folded)
		return
	end

	room.lamp.Transparency = 0
	room.glow.Enabled = false
	room.lamp.Color = if state == "silenced" then LAMP_SILENCED else LAMP_QUIET
end

return Vault
