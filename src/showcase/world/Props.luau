--!strict
-- The props the eight phases of systems hook onto.
--
-- Everything in `Static` is a plain anchored Part carrying a CollectionService tag, so it bakes
-- into assets/showcase/Showcase.rbxmx and stands in Studio without anybody pressing Play.
--
-- Everything in `Dynamic` is something a Part cannot be -- a `Seat`, or a bag hanging off two
-- constraints -- so it is laid at runtime. That split is the whole shape of this file: bake what
-- can be baked, because a place that looks empty until F5 is indistinguishable from a broken one.
--
-- Positions all derive from Plan. Nothing here picks a coordinate.

local Plan = require(script.Parent.Plan)
local Kit = require(script.Parent.Kit)

local Props = {}

local IRON = Color3.fromRGB(38, 40, 44)
local IRON_LIT = Color3.fromRGB(60, 64, 70)
local CANVAS = Color3.fromRGB(64, 58, 52)
local PAINT = Color3.fromRGB(122, 52, 44)

-- ---------------------------------------------------------------------------------------
-- Static: baked, tagged
-- ---------------------------------------------------------------------------------------

function Props.Static(parent: Instance, toWorld: (number, number, number) -> Vector3)
	local X, Z, E = Plan.X, Plan.Z, Plan.Edge
	local gym = Plan.Gym()
	local floor = Plan.SlabStuds
	local folder = Instance.new("Folder")
	folder.Name = "Props"
	folder.Parent = parent

	-- ---- vending machines, in the courtyard against the north arcade
	--
	-- Two, at the third points of the colonnade rather than one in the middle: a machine on the
	-- axis of the entrance is the first thing you see through the arch, and a courtyard's centre
	-- should be empty.
	local courtX1, courtX2 = X[E.CourtNear], X[E.CourtFar]
	for index, share in { 0.28, 0.72 } do
		local x = courtX1 + (courtX2 - courtX1) * share
		local z = Z[E.CourtFar] - 3
		Kit.Block(folder, `Vending{index}`, toWorld(x, floor + 5.5, z), Vector3.new(7, 11, 3.5), IRON, {
			material = Enum.Material.Metal,
			tags = { "VendingMachine" },
		})
		Kit.Block(folder, `VendingFace{index}`, toWorld(x, floor + 6.5, z - 1.9), Vector3.new(5.4, 7, 0.3), Color3.fromRGB(96, 112, 128), {
			material = Enum.Material.Glass,
			transparency = 0.45,
			shadow = false,
			collide = false,
		})
	end

	-- ---- the sparring ring, in the middle of the hall
	local ringX = (gym.X1 + gym.X2) / 2
	local ringZ = (gym.Z1 + gym.Z2) / 2
	local ringHalf = 26
	Kit.Block(folder, "RingFloor", toWorld(ringX, floor + 1, ringZ), Vector3.new(ringHalf * 2, 2, ringHalf * 2), CANVAS, {
		material = Enum.Material.Fabric,
	})
	-- Four border rails, each tagged and each carrying the ring's id. RingId is read off the part
	-- or any ancestor, so tagging the rails individually still gives one board.
	for index, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local dx, dz = side[1], side[2]
		local length = if dx ~= 0 then 3 else ringHalf * 2 + 3
		local depth = if dx ~= 0 then ringHalf * 2 + 3 else 3
		Kit.Block(
			folder,
			`RingRope{index}`,
			toWorld(ringX + dx * ringHalf, floor + 5, ringZ + dz * ringHalf),
			Vector3.new(length, 1, depth),
			IRON_LIT,
			{ material = Enum.Material.Metal, tags = { "SparringRing" }, attrs = { RingId = "north" } }
		)
	end

	-- ---- the training target wall, on the hall's north face
	for index = 1, 6 do
		local x = gym.X1 + (gym.X2 - gym.X1) * (index / 7)
		Kit.Block(folder, `Target{index}`, toWorld(x, floor + 9, gym.Z2 - 2), Vector3.new(6, 6, 1), PAINT, {
			material = Enum.Material.Fabric,
			tags = { "TargetNode" },
		})
	end

	-- ---- the arena camera vantage: high on the hall's south side, looking at the ring.
	--
	-- Its CFrame *is* the shot -- ArenaCamera tweens to exactly this. Aim it in Studio and the
	-- framing is whatever you saw there. Invisible and non-collidable: it is a marker, not a prop.
	Kit.Block(folder, "ArenaVantage", toWorld(ringX, floor + 30, gym.Z1 + 8), Vector3.new(2, 2, 2), IRON, {
		transparency = 1,
		collide = false,
		shadow = false,
		tags = { "ArenaCamera" },
	})

	-- ---- locker doors down the south corridor, and the wardrobe bank at its west end
	--
	-- On the corridor's *band* wall, not free-standing: a locker island in a 24-wide corridor is
	-- the mistake v1 made three times (see its handover), and the corridor is circulation.
	local corridorZ = Z[E.BandInner] + 1.6
	local first, last = X[E.BandInner] + 14, X[E.CorridorFar] - 14
	for index = 0, 9 do
		local x = first + (last - first) * (index / 9)
		Kit.Block(folder, `Locker{index}`, toWorld(x, floor + 5.5, corridorZ), Vector3.new(4.5, 11, 2.4), IRON, {
			material = Enum.Material.Metal,
			tags = { "LockerDoor" },
			-- Alternating hinge side, so a run of open lockers does not read as a machine.
			attrs = { Hinge = if index % 2 == 0 then "Left" else "Right" },
		})
	end

	Kit.Block(folder, "WardrobeBank", toWorld(first - 10, floor + 5.5, corridorZ), Vector3.new(10, 11, 2.6), IRON_LIT, {
		material = Enum.Material.Metal,
		tags = { "Wardrobe" },
	})

	-- ---- classroom doors, in the south band's bay openings
	--
	-- **South band only.** Hinge derives the pivot from the leaf's local X, so a door leaf needs
	-- its width on X. These bays run along X; the east and west bands do not, and a baked box
	-- cannot be rotated -- rbxmx writes axis-aligned geometry. Doors on the side bands want a
	-- rotated leaf, which is a runtime prop, and they are deliberately not here yet.
	for _, room in Plan.Rooms() do
		if room.Floor ~= 1 or room.Z2 ~= Z[E.BandInner] or room.Label == "Stair" then
			continue
		end
		local centre = (room.X1 + room.X2) / 2
		Kit.Block(folder, `Door_{room.Id}`, toWorld(centre, floor + 7, Z[E.BandInner]), Vector3.new(12, 14, 1), IRON_LIT, {
			material = Enum.Material.Metal,
			tags = { "Door" },
			attrs = { Hinge = "Left" },
		})
	end

	return folder
end

-- ---------------------------------------------------------------------------------------
-- Dynamic: runtime only
-- ---------------------------------------------------------------------------------------

-- A Seat is not a Part and a hanging bag is not anchored, so neither can be an axis-aligned box
-- in an rbxmx. These are the only things in the showcase that need Play to exist, and the list
-- is kept short on purpose.
function Props.Dynamic(parent: Instance, toWorld: (number, number, number) -> Vector3)
	local gym = Plan.Gym()
	local floor = Plan.SlabStuds
	local folder = Instance.new("Folder")
	folder.Name = "PropsDynamic"
	folder.Parent = parent

	local ringX = (gym.X1 + gym.X2) / 2
	local ringZ = (gym.Z1 + gym.Z2) / 2

	-- ---- three heavy bags, hung west of the ring
	for index = 1, 3 do
		local x = gym.X1 + 22
		local z = ringZ - 30 + (index - 1) * 24

		-- The mount is anchored; the bag is not. A bag that is anchored never swings, and
		-- DoorService's sibling in GymService warns about exactly that.
		local mount = Kit.Block(folder, `BagMount{index}`, toWorld(x, floor + 34, z), Vector3.new(3, 1, 3), IRON_LIT, {
			material = Enum.Material.Metal,
		})

		local bag = Instance.new("Part")
		bag.Name = `HeavyBag{index}`
		bag.Size = Vector3.new(4, 14, 4)
		bag.Shape = Enum.PartType.Cylinder
		bag.CFrame = CFrame.new(toWorld(x, floor + 20, z)) * CFrame.Angles(0, 0, math.rad(90))
		bag.Anchored = false
		bag.Color = CANVAS
		bag.Material = Enum.Material.Fabric
		-- Heavy, so the impulse in Workout.StrikeImpulse reads as moving something with mass
		-- rather than swatting a balloon. The constant is tuned against roughly this density.
		bag.CustomPhysicalProperties = PhysicalProperties.new(6, 0.6, 0.2, 1, 1)
		bag.Parent = folder

		local top = Instance.new("Attachment")
		top.Position = Vector3.new(7, 0, 0) -- the cylinder's +X end, which is its top once rotated
		top.Parent = bag
		local hook = Instance.new("Attachment")
		hook.Parent = mount

		-- The rope is the hard limit; the spring is the damping. Roblox has no air drag, so a
		-- rope on its own gives a pendulum that swings until the heat death of the server.
		local rope = Instance.new("RopeConstraint")
		rope.Attachment0 = hook
		rope.Attachment1 = top
		rope.Length = 8
		rope.Visible = true
		rope.Parent = bag

		local spring = Instance.new("SpringConstraint")
		spring.Attachment0 = hook
		spring.Attachment1 = top
		spring.FreeLength = 8
		spring.Stiffness = 4000
		spring.Damping = 900
		spring.Parent = bag
	end

	-- ---- two weight benches, east of the ring. Seat plus a sibling named Barbell.
	for index = 1, 2 do
		local x = gym.X2 - 26
		local z = ringZ - 14 + (index - 1) * 28

		local station = Instance.new("Model")
		station.Name = `Bench{index}`
		station.Parent = folder

		local seat = Instance.new("Seat")
		seat.Name = "Bench"
		seat.Size = Vector3.new(4, 1, 10)
		seat.CFrame = CFrame.new(toWorld(x, floor + 3, z))
		seat.Anchored = true
		seat.Color = IRON
		seat.Material = Enum.Material.Fabric
		seat.Parent = station
		station.PrimaryPart = seat
		game:GetService("CollectionService"):AddTag(seat, "WeightBench")

		-- GymService looks for a sibling named exactly this and tweens it to the press
		-- animation's own length. Without it the reps still count; there is just nothing to lift.
		local bar = Instance.new("Part")
		bar.Name = "Barbell"
		bar.Size = Vector3.new(14, 0.7, 0.7)
		bar.CFrame = CFrame.new(toWorld(x, floor + 8.5, z))
		bar.Anchored = true
		bar.Color = IRON_LIT
		bar.Material = Enum.Material.Metal
		bar.CanCollide = false
		bar.Parent = station
	end

	-- ---- spectator seating on the hall's south edge, facing the ring
	for index = 1, 6 do
		local x = ringX - 40 + (index - 1) * 16
		local seat = Instance.new("Seat")
		seat.Name = `Spectator{index}`
		seat.Size = Vector3.new(12, 1, 4)
		seat.CFrame = CFrame.new(toWorld(x, floor + 3, gym.Z1 + 10))
		seat.Anchored = true
		seat.Color = Color3.fromRGB(78, 78, 73)
		seat.Material = Enum.Material.Concrete
		seat.Parent = folder
		game:GetService("CollectionService"):AddTag(seat, "SpectatorSeat")
	end

	return folder
end

return Props
