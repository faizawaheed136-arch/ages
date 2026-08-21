--!strict
-- The drawer, the camera over it, and the spot the clerk stands on.
--
-- Split from TheftService for the reason Lab is split from ScienceService and Studio
-- from ArtService: where a thing stands and what happens when you reach it are different
-- questions, and re-laying a shop must never be able to touch what a robbery is worth.
--
-- Everything here is stood up relative to a place point rather than bolted onto the
-- shop's own furniture, and that is not laziness -- it is the only way this survives the
-- town being rebuilt. The generated city already puts a `Counter` box in every storefront
-- and a `Teller` in the bank, and hanging the game off those names would mean the day
-- somebody renames a box in the generator is the day four shops silently stop being
-- robbable. A place point is the town's own promise about where the counter is; see
-- PlaceService's first paragraph, which makes exactly this argument about coordinates.
--
-- The camera turns. That is worth stating plainly because it is the entire signposting
-- of the activity: there is no warning on the HUD and there is never going to be one, so
-- the housing physically sweeps and the lens is lit, and a player who wants to know when
-- it is safe to hold has to watch the thing on the wall. Signposting is part of the
-- mechanic here, not decoration on top of it.
--
-- Built lazily, one shop at a time, and left standing. Four tills' worth of parts is
-- nothing, and tearing a shop down when a player walks out would mean rebuilding it -- and
-- restarting its camera's sweep from zero -- every time somebody changes their mind at the
-- door, which is precisely when the sweep is being read most carefully.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Interact = require(ReplicatedStorage:WaitForChild("world"):WaitForChild("Interact"))

local Ground = require(script.Parent.Ground)

local Till = {}

local THEFT = Config.Crime.Theft

-- Cosmetic dimensions, kept out of Config for the reason ChoiceMarkers gives: nobody
-- balances this game by changing how tall a till is.
local DRAWER_SIZE = Vector3.new(2.6, 1.6, 1.8)
-- How far in front of the place point the drawer sits. The point itself is where the
-- player is put down, so the till goes a short step from it -- close enough that
-- "standing at the counter" and "in reach of the drawer" are the same place.
local DRAWER_FORWARD = 2.2
local DRAWER_LIFT = 3.2

local CAMERA_SIZE = Vector3.new(1.1, 1.1, 2.2)
local CAMERA_LENS_SIZE = Vector3.new(0.6, 0.6, 0.35)
-- High and behind the drawer, looking out into the room -- which is where a real one
-- would be and, more usefully, where the player can see it from the spot they have to
-- stand on. A camera above the player's own head would be a camera they never look at.
local CAMERA_LIFT = 9
local CAMERA_BACK = 3

-- The lens, off and on. Red is the one colour this game uses for "you are being seen"
-- and it is the same red the heat bar's border and the search ring take, so a player
-- learns it once.
local LENS_IDLE = Color3.fromRGB(70, 78, 88)
local LENS_LIVE = Color3.fromRGB(226, 78, 74)

local DRAWER_COLOR = Color3.fromRGB(150, 128, 92)
local HOUSING_COLOR = Color3.fromRGB(58, 62, 70)

-- How far the housing swings either side of straight ahead, in degrees. Wide enough that
-- which way it is pointed is legible from the counter, narrow enough that it reads as a
-- camera on a mount rather than a searchlight.
local SWEEP_DEGREES = 70

-- One built shop.
export type Fitting = {
	place: string,
	-- Where the drawer is, for the reach check. The part's position rather than the
	-- part, because reach is arithmetic and nothing outside this file should be holding
	-- a handle on a piece of shop furniture.
	drawer: Vector3,
	-- Where the clerk stands, facing the drawer. Nil when there was nowhere standable to
	-- put one, which is a real outcome in a shop packed with generated fittings -- the
	-- caller degrades to a camera-only shop rather than refusing the robbery, because a
	-- door that cannot be robbed for reasons invisible from outside it is the worst
	-- version of this.
	clerkSpot: Vector3?,
	clerkFacing: Vector3,
	-- Where a gang's lookout stands, watching the door rather than the drawer. Nil for the
	-- same reason `clerkSpot` can be: some shops have nowhere standable near the entrance
	-- either, and a robbery that refused itself over that would be worse than one crew role
	-- quietly unavailable there.
	lookoutSpot: Vector3?,
	lookoutFacing: Vector3,
	drawerPart: BasePart,
	housing: BasePart,
	-- Where the housing sits and which way "straight ahead" is for it. Held rather than
	-- read back off the part, because the part's rotation *is* the sweep -- reading the
	-- swing off a thing that has already been swung would compound the angle every tick
	-- and spin the camera like a top.
	housingBase: CFrame,
	lens: BasePart,
	dots: Interact.InteractHandle?,
}

local fittings: { [string]: Fitting } = {}
local folder: Folder? = nil

local function tillFolder(): Folder
	local existing = folder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "AgesTills"
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
	part.CanCollide = false
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- The shop, stood up. Nil when the place id is not in the built world at all, which the
-- caller reports by name -- a till that silently failed to appear is a shop the player
-- walks into and finds nothing in.
function Till.Build(place: string, at: CFrame, label: string): Fitting?
	local existing = fittings[place]
	if existing ~= nil and existing.drawerPart.Parent ~= nil then
		return existing
	end

	local parent = tillFolder()
	local group = Instance.new("Folder")
	group.Name = place
	group.Parent = parent

	-- The place point faces into the room, so "forward" from it is where a player stands
	-- and "back" is the counter. The drawer therefore goes behind the point and the
	-- camera further behind and above it.
	local forward = at.LookVector
	local flat = Vector3.new(forward.X, 0, forward.Z)
	if flat.Magnitude < 1e-3 then
		-- A place point lying flat is a point with no heading to build against. Refused
		-- rather than guessed at: a drawer built on a coin flip would be a drawer inside
		-- a wall half the time, and a robbery that fails for reasons nobody can see.
		group:Destroy()
		return nil
	end
	flat = flat.Unit

	local base = at.Position
	local drawerAt = base + flat * DRAWER_FORWARD + Vector3.new(0, DRAWER_LIFT, 0)
	local drawerPart = buildBlock(group, "Drawer", CFrame.new(drawerAt, drawerAt + flat), DRAWER_SIZE, DRAWER_COLOR)

	local cameraAt = base - flat * CAMERA_BACK + Vector3.new(0, CAMERA_LIFT, 0)
	local housing = buildBlock(group, "Camera", CFrame.new(cameraAt, cameraAt + flat), CAMERA_SIZE, HOUSING_COLOR)
	local lensAt = cameraAt + flat * (CAMERA_SIZE.Z / 2)
	local lens = buildBlock(group, "Lens", CFrame.new(lensAt, lensAt + flat), CAMERA_LENS_SIZE, LENS_IDLE)
	lens.Material = Enum.Material.Neon

	-- Somewhere for a clerk to stand: behind the drawer, off to one side, facing it. Asked
	-- of Ground rather than assumed, because the shops are generated and what is behind a
	-- counter differs from one to the next.
	local ignore = Ground.IgnoreList({ group })
	local clerkWanted = base - flat * 3.5 + Vector3.new(flat.Z, 0, -flat.X) * 2.5
	local clerkSpot = Ground.SpotAt(clerkWanted, 2, 5, ignore, drawerAt)

	-- Near the place point itself -- roughly where a customer walking in first stands --
	-- and off the opposite side from the clerk, so the two never fight over the same patch
	-- of floor. Still asked to be reachable from the drawer, same guard as the clerk: a
	-- lookout who could not actually be walked to from the counter would be a body in a
	-- room the robbery cannot see.
	local lookoutWanted = base + Vector3.new(-flat.Z, 0, flat.X) * 3
	local lookoutSpot = Ground.SpotAt(lookoutWanted, 2, 5, ignore, drawerAt)

	local fitting: Fitting = {
		place = place,
		drawer = drawerAt,
		clerkSpot = clerkSpot,
		clerkFacing = drawerAt,
		-- Facing back out the way a customer came in, since watching the door is the whole
		-- point of standing here.
		lookoutSpot = lookoutSpot,
		lookoutFacing = base - flat * 20,
		drawerPart = drawerPart,
		housing = housing,
		housingBase = housing.CFrame,
		lens = lens,
		dots = nil,
	}

	-- The invitation. Clicking it only ever puts the player at the till -- the verb is
	-- held, from the panel that opens -- which is why this is a Till and not a Station;
	-- see Interact.InteractKind, where the same distinction is made from the other side.
	fitting.dots = Interact.Attach(drawerPart, {
		kind = "Till",
		id = place,
		actionText = "Open",
		objectText = label,
	})

	fittings[place] = fitting
	return fitting
end

function Till.Get(place: string): Fitting?
	local fitting = fittings[place]
	if fitting == nil or fitting.drawerPart.Parent == nil then
		return nil
	end
	return fitting
end

-- Points the camera. `share` is where it is through its sweep, 0 to 1, and `onTill` is
-- whether it is currently looking at the drawer.
--
-- Both are handed in rather than worked out here, because the sweep's timing is the
-- activity and the activity lives in TheftService. This file turns a part.
function Till.AimCamera(place: string, share: number, onTill: boolean)
	local fitting = Till.Get(place)
	if fitting == nil then
		return
	end
	-- A triangle rather than a sine, so the camera pauses at the ends of its travel the
	-- way a real mount does and the player has a moment to read "it has turned away"
	-- rather than a continuous glide they have to guess at.
	local folded = if share < 0.5 then share * 2 else (1 - share) * 2
	local swing = (folded - 0.5) * 2 * SWEEP_DEGREES
	fitting.housing.CFrame = fitting.housingBase * CFrame.Angles(0, math.rad(swing), 0)
	fitting.lens.CFrame = fitting.housing.CFrame * CFrame.new(0, 0, -(CAMERA_SIZE.Z / 2))
	fitting.lens.Color = if onTill then LENS_LIVE else LENS_IDLE
end

-- Whether a position is close enough to have hands in the drawer. Here rather than in
-- TheftService because it is a question about where the furniture is, and the answer has
-- to stay true when the shop moves.
function Till.InReach(place: string, from: Vector3): boolean
	local fitting = Till.Get(place)
	if fitting == nil then
		return false
	end
	return Ground.FlatDistance(from, fitting.drawer) <= THEFT.ReachStuds
end

return Till
