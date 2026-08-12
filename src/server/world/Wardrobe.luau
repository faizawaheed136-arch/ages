--!strict
-- The mark you stand on to change your clothes, and the sign over it that says how it is
-- going.
--
-- Split from DisguiseService for the reason Till is split from TheftService and Lab from
-- ScienceService: where a thing stands and what happens when you reach it are different
-- questions. Re-laying the town must never be able to touch what an escape is worth.
--
-- A floor mark rather than three dots over somebody's head, and that is the interaction
-- grammar being obeyed rather than bent. Dots are for *choices*; floor marks are for
-- destinations, and this is the purest destination in the game -- there is nothing to
-- decide when you get here, only somewhere to be. Nothing is clicked at any point: you run
-- onto it, it counts, and stepping off cancels. Under a chase that is the right shape,
-- because a panel you have to open is a panel you have to look away from the street to read.
--
-- Everything the player needs is written above the mark, in the world. That is deliberate
-- and it is the same argument the shop camera makes: during the five seconds this takes,
-- the player is standing still while officers converge, and the one thing they will be
-- looking at is the spot they are standing on. A HUD panel would be off to the side of the
-- only thing on screen that matters.
--
-- Stood up relative to a place point rather than bolted onto the room's own furniture, so
-- the day somebody renames a box in the generator is not the day four escapes disappear.
-- Built lazily and left standing: four marks' worth of parts is nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Wardrobe = {}

local DISGUISE = Config.Crime.Disguise

-- Cosmetic dimensions, kept out of Config for the reason ChoiceMarkers gives: nobody
-- balances this game by changing how wide a floor mark is.
--
-- The disc is drawn a little wider than ReachStuds rather than exactly it, because the mark
-- is what the player aims at and the reach is what actually counts -- a disc drawn to the
-- edge of its own tolerance would have players stepping off the paint and still working,
-- which teaches them the paint is a lie.
local DISC_THICKNESS = 0.2
local DISC_LIFT = 0.08
local RAIL_SIZE = Vector3.new(0.5, 0.5, 5.0)
local RAIL_LIFT = 6.5
local RAIL_BACK = 1.6
local POST_SIZE = Vector3.new(0.35, 6.5, 0.35)

local IDLE_COLOR = Color3.fromRGB(88, 96, 110)
-- Amber while it is counting, and it is the same amber the search ring takes, because both
-- of them mean "this is in progress and not yet true".
local BUSY_COLOR = Color3.fromRGB(238, 176, 74)
-- Red for blocked, matching the heat bar's border and the camera lens: this game uses one
-- red and it means "you are being seen".
local BLOCKED_COLOR = Color3.fromRGB(226, 78, 74)
local DONE_COLOR = Color3.fromRGB(126, 208, 130)
local RAIL_COLOR = Color3.fromRGB(150, 156, 168)

local BILLBOARD_SIZE = UDim2.fromOffset(220, 62)
local BILLBOARD_LIFT = 8.5

-- One built hideout.
export type Mark = {
	place: string,
	-- Where the mark is, for the reach check. A position rather than the part, because reach
	-- is arithmetic and nothing outside this file should be holding a piece of the world.
	at: Vector3,
	disc: BasePart,
	label: TextLabel,
	fill: Frame,
	-- Whose progress the sign is currently showing. Two players on one mark would otherwise
	-- flicker between two counts, and a sign that reads for nobody is worse than a sign that
	-- reads for one of them. First to arrive keeps it until they step off.
	owner: Player?,
}

local marks: { [string]: Mark } = {}
local folder: Folder? = nil

local function markFolder(): Folder
	local existing = folder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "AgesHideouts"
	made.Parent = workspace
	folder = made
	return made
end

local function buildPart(parent: Instance, name: string, at: CFrame, size: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = at
	part.Anchored = true
	-- Out of every ignore list in the game by construction. An officer's line of sight and a
	-- witness's are both raycasts, and a decoration a player could stand behind would let
	-- them hide behind the very thing telling them where to run.
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

-- The hideout, stood up. Nil when the place point has no heading to build against, which the
-- caller reports by name -- a mark that silently failed to appear is a corner of the map a
-- player sprints to during the worst thirty seconds of their afternoon and finds empty.
function Wardrobe.Build(place: string, at: CFrame, label: string): Mark?
	local existing = marks[place]
	if existing ~= nil and existing.disc.Parent ~= nil then
		return existing
	end

	local forward = at.LookVector
	local flat = Vector3.new(forward.X, 0, forward.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	flat = flat.Unit

	local group = Instance.new("Folder")
	group.Name = place
	group.Parent = markFolder()

	local base = at.Position
	local width = DISGUISE.ReachStuds * 2.2
	-- A cylinder's flat faces are on its X axis, so a disc lying on the floor is one turned
	-- on its side -- which is why the thickness is the X of the size and the roll is 90
	-- degrees. This is the one thing in the file that looks like a mistake and is not.
	local disc = buildPart(
		group,
		"Mark",
		CFrame.new(base + Vector3.new(0, DISC_LIFT, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(DISC_THICKNESS, width, width),
		IDLE_COLOR
	)
	disc.Shape = Enum.PartType.Cylinder

	-- A clothes rail behind the mark, so the thing is legible as somewhere you change rather
	-- than as a glowing circle on the floor. Cheap, and it is what makes a player who has
	-- never read a word of this understand the mark on sight.
	local railAt = base - flat * RAIL_BACK + Vector3.new(0, RAIL_LIFT, 0)
	buildPart(group, "Rail", CFrame.new(railAt, railAt + Vector3.new(flat.Z, 0, -flat.X)), RAIL_SIZE, RAIL_COLOR)
	for _, side in { -1, 1 } do
		local postAt = railAt
			+ Vector3.new(flat.Z, 0, -flat.X) * (RAIL_SIZE.Z / 2) * side
			- Vector3.new(0, POST_SIZE.Y / 2, 0)
		buildPart(group, "Post", CFrame.new(postAt), POST_SIZE, RAIL_COLOR)
	end

	local anchor = buildPart(group, "Sign", CFrame.new(base + Vector3.new(0, BILLBOARD_LIFT, 0)), Vector3.new(0.2, 0.2, 0.2), RAIL_COLOR)
	anchor.Transparency = 1

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Status"
	billboard.Size = BILLBOARD_SIZE
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	-- Not AlwaysOnTop. The search ring's pin is, because its whole job is telling you where
	-- the police are looking from inside the building you are hiding in -- but this sign is
	-- about a spot you have to physically be standing on, and one that showed through walls
	-- would advertise four hiding places across the whole map at all times.
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 90
	billboard.Adornee = anchor
	billboard.Parent = anchor

	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, 0, 0, 26)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamMedium
	text.TextSize = 18
	text.TextColor3 = Color3.fromRGB(238, 240, 244)
	text.TextStrokeTransparency = 0.4
	text.Text = label
	text.Parent = billboard

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -20, 0, 8)
	track.Position = UDim2.new(0, 10, 0, 32)
	track.BackgroundColor3 = Color3.fromRGB(28, 31, 38)
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = BUSY_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track

	local mark: Mark = {
		place = place,
		at = base,
		disc = disc,
		label = text,
		fill = fill,
		owner = nil,
	}
	marks[place] = mark
	return mark
end

function Wardrobe.Get(place: string): Mark?
	local mark = marks[place]
	if mark == nil or mark.disc.Parent == nil then
		return nil
	end
	return mark
end

-- How far a position is from the mark, flat, or nil if there is no mark there.
--
-- A distance rather than the yes/no the caller mostly wants, because the caller has four
-- marks to choose between and "am I on it" cannot break a tie. Two hideouts are never close
-- enough for that to matter today, but "whichever the loop reached first" is the kind of
-- rule that is fine until somebody puts two in one building and then is impossible to debug.
--
-- Flat, ignoring height, for the same reason every reach check in this game is: a player on
-- the step above a mark is standing on it as far as anybody watching is concerned.
function Wardrobe.DistanceTo(place: string, from: Vector3): number?
	local mark = Wardrobe.Get(place)
	if mark == nil then
		return nil
	end
	local dx = from.X - mark.at.X
	local dz = from.Z - mark.at.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Whether this player may drive the sign. First one on keeps it; everybody else is refused
-- until they step off, which is the only sane answer for one sign and two counts.
function Wardrobe.Claim(place: string, player: Player): boolean
	local mark = Wardrobe.Get(place)
	if mark == nil then
		return false
	end
	local owner = mark.owner
	if owner ~= nil and owner ~= player and owner.Parent ~= nil then
		return false
	end
	mark.owner = player
	return true
end

-- What the sign says and how full the bar is. `share` is 0 to 1.
--
-- Told what to draw rather than working it out, for the same reason Till.AimCamera is: the
-- timing is the activity and the activity lives in the service. This file paints.
function Wardrobe.Show(place: string, player: Player, headline: string, share: number, state: string)
	local mark = Wardrobe.Get(place)
	if mark == nil or mark.owner ~= player then
		return
	end
	mark.label.Text = headline
	mark.fill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
	local color = if state == "blocked"
		then BLOCKED_COLOR
		elseif state == "done" then DONE_COLOR
		elseif state == "busy" then BUSY_COLOR
		else IDLE_COLOR
	mark.fill.BackgroundColor3 = color
	mark.disc.Color = color
end

-- Back to nothing happening here. Idempotent, and it releases the sign -- a mark left owned
-- by somebody who walked away is a mark the next player cannot use, which is the worst
-- possible bug for a thing whose entire job is being available in an emergency.
function Wardrobe.Rest(place: string, player: Player, label: string)
	local mark = Wardrobe.Get(place)
	if mark == nil or (mark.owner ~= nil and mark.owner ~= player) then
		return
	end
	mark.owner = nil
	mark.label.Text = label
	mark.fill.Size = UDim2.fromScale(0, 1)
	mark.fill.BackgroundColor3 = BUSY_COLOR
	mark.disc.Color = IDLE_COLOR
end

return Wardrobe
