--!strict
-- The props the interactive systems hook onto, placed against the open-arms plan.
--
-- Everything in `Static` is a plain anchored Part carrying a CollectionService tag, so it bakes
-- into the asset and stands in Studio without anybody pressing Play. Everything in `Dynamic` is
-- something a Part cannot be -- a `Seat`, or a bag on two constraints -- so it is laid at runtime.
-- That split is the shape of this file: bake what can be baked.
--
-- **On the fitness equipment.** Phases 5 to 7 built a sparring hall's worth of systems, and this
-- is now a school gymnasium with a maple court rather than a fight club. The systems are kept and
-- the content is re-read: the bags and benches are a fitness bay along the back of the hall, and
-- the tag that opens the records board sits on a court-side honours board. Same code, and it now
-- says something a school would say.
--
-- Positions all derive from Plan. Nothing here picks a coordinate.

local Plan = require(script.Parent.Plan)
local Kit = require(script.Parent.Kit)

local Props = {}

local IRON = Color3.fromRGB(48, 50, 56)
local IRON_LIT = Color3.fromRGB(72, 76, 84)
local TIMBER = Color3.fromRGB(122, 86, 58)
local TIMBER_DARK = Color3.fromRGB(88, 62, 42)
local CANVAS = Color3.fromRGB(64, 58, 52)

-- ---------------------------------------------------------------------------------------
-- Static: baked, tagged
-- ---------------------------------------------------------------------------------------

function Props.Static(parent: Instance, toWorld: (number, number, number) -> Vector3)
	local X, Z, E, ZE = Plan.X, Plan.Z, Plan.Edge, Plan.ZEdge
	local gym, atrium, cafe = Plan.Gym(), Plan.Atrium(), Plan.Cafeteria()
	local floor = Plan.SlabStuds
	local folder = Instance.new("Folder")
	folder.Name = "Props"
	folder.Parent = parent

	-- ---- vending, at the cafeteria's atrium edge where a queue does not block anything
	for index, share in { 0.35, 0.62 } do
		local z = cafe.Z1 + (cafe.Z2 - cafe.Z1) * share
		Kit.Block(folder, `Vending{index}`, toWorld(X[E.GalleryInner] - 2, floor + 5.5, z), Vector3.new(3.5, 11, 7), IRON, {
			material = Enum.Material.Metal,
			tags = { "VendingMachine" },
		})
		Kit.Block(folder, `VendingFace{index}`, toWorld(X[E.GalleryInner] - 3.9, floor + 6.5, z), Vector3.new(0.3, 7, 5.4), Color3.fromRGB(96, 112, 128), {
			material = Enum.Material.Glass,
			transparency = 0.45,
			shadow = false,
			collide = false,
		})
	end

	-- ---- the honours board, court-side. Carries the records tag.
	local courtX, courtZ = (gym.X1 + gym.X2) / 2, (gym.Z1 + gym.Z2) / 2
	Kit.Block(folder, "HonoursBoard", toWorld(gym.X2 - 2, floor + 10, courtZ), Vector3.new(1.5, 14, 40), TIMBER_DARK, {
		material = Enum.Material.Wood,
		reflectance = 0.06,
		tags = { "SparringRing" },
		attrs = { RingId = "north" },
	})

	-- ---- the fitness bay: a padded training wall across the back of the hall
	for index = 1, 6 do
		local x = gym.X1 + (gym.X2 - gym.X1) * (index / 7)
		Kit.Block(folder, `Target{index}`, toWorld(x, floor + 9, gym.Z2 - 2), Vector3.new(6, 6, 1), CANVAS, {
			material = Enum.Material.Fabric,
			tags = { "TargetNode" },
		})
	end

	-- ---- the camera vantage: high on the gallery side, framing the court.
	--
	-- Its CFrame *is* the shot -- ArenaCamera tweens to exactly this, so aim it in Studio and the
	-- framing is whatever you saw there. Invisible: a marker, not a prop.
	Kit.Block(folder, "ArenaVantage", toWorld(gym.X1 - 6, floor + 34, courtZ), Vector3.new(2, 2, 2), IRON, {
		transparency = 1,
		collide = false,
		shadow = false,
		tags = { "ArenaCamera" },
	})

	-- ---- lockers, down the west gallery's room-side wall
	--
	-- On the wall, not free-standing. A locker island in a 28-wide gallery is the mistake v1 made
	-- three times: the gallery is circulation and a view, and both want the floor clear.
	local lockerX = X[E.RoomInner] + 1.6
	local first, last = Z[ZE.GardenBack] + 20, Z[ZE.AtriumBack] - 20
	for index = 0, 9 do
		local z = first + (last - first) * (index / 9)
		Kit.Block(folder, `Locker{index}`, toWorld(lockerX, floor + 5.5, z), Vector3.new(2.4, 11, 4.5), IRON, {
			material = Enum.Material.Metal,
			tags = { "LockerDoor" },
			attrs = { Hinge = if index % 2 == 0 then "Left" else "Right" },
		})
	end

	-- ---- the changing-room wardrobe, east wing
	Kit.Block(folder, "WardrobeBank", toWorld(X[E.GalleryFar] + 1.6, floor + 5.5, Z[ZE.GardenBack] + 30), Vector3.new(2.6, 11, 10), IRON_LIT, {
		material = Enum.Material.Metal,
		tags = { "Wardrobe" },
	})

	-- ---- room doors, in each room's gallery-facing wall
	--
	-- The galleries run along Z, so these leaves are width-on-Z. Hinge measures the leaf's width
	-- axis rather than assuming local X, so an axis-aligned box is all this needs -- see its
	-- `widthOnX`. Getting that wrong is a door that pivots about its own face.
	local DOOR_W, DOOR_H, DOOR_T = 12, 14, 1
	for _, room in Plan.Rooms() do
		local base = if room.Floor == 1 then floor else Plan.GroundStoreyStuds + Plan.SlabStuds
		local west = room.X2 == X[E.RoomInner]
		local east = room.X1 == X[E.GalleryFar]
		if not (west or east) then
			continue
		end
		local x = if west then X[E.RoomInner] else X[E.GalleryFar]
		Kit.Block(folder, `Door_{room.Id}`, toWorld(x, base + DOOR_H / 2, (room.Z1 + room.Z2) / 2), Vector3.new(DOOR_T, DOOR_H, DOOR_W), TIMBER, {
			material = Enum.Material.Wood,
			tags = { "Door" },
			attrs = { Hinge = if west then "Left" else "Right" },
		})
	end

	-- ---- cafeteria tables, and the science lab's glass display cases
	for index = 1, 8 do
		local tz = cafe.Z1 + 14 + (index - 1) * 14
		Kit.Block(folder, `CafeTable{index}`, toWorld(cafe.X1 + 26, floor + 2.6, tz), Vector3.new(30, 0.6, 6), TIMBER, {
			material = Enum.Material.WoodPlanks,
		})
		for side = -1, 1, 2 do
			Kit.Block(folder, `CafeBench{index}_{side}`, toWorld(cafe.X1 + 26, floor + 1.6, tz + side * 5), Vector3.new(30, 0.5, 3), TIMBER_DARK, {
				material = Enum.Material.Wood,
			})
		end
	end

	local upper = Plan.GroundStoreyStuds + Plan.SlabStuds
	for _, room in Plan.Rooms() do
		if room.Label ~= "Science Lab" then
			continue
		end
		for index = 1, 4 do
			local z = room.Z1 + 12 + (index - 1) * 16
			Kit.Block(folder, `CaseFrame{index}`, toWorld(room.X1 + 6, upper + 6, z), Vector3.new(4, 12, 10), TIMBER_DARK, {
				material = Enum.Material.Wood,
			})
			Kit.Block(folder, `CaseGlass{index}`, toWorld(room.X1 + 3.9, upper + 6.5, z), Vector3.new(0.3, 10, 8.5), Color3.fromRGB(150, 176, 196), {
				material = Enum.Material.Glass,
				transparency = 0.5,
				shadow = false,
				collide = false,
			})
		end
	end

	-- ---- the art studio's skylights, punched in the roof above it
	for _, room in Plan.Rooms() do
		if room.Label ~= "Art Studio" then
			continue
		end
		for index = 1, 4 do
			local z = room.Z1 + 10 + (index - 1) * 14
			Kit.Block(folder, `Skylight{index}`, toWorld((room.X1 + room.X2) / 2, Plan.RoofStuds + 2, z), Vector3.new(room.X2 - room.X1 - 20, 0.5, 8), Color3.fromRGB(150, 176, 196), {
				material = Enum.Material.Glass,
				transparency = 0.55,
				shadow = false,
				collide = false,
			})
		end
	end

	return folder
end

-- ---------------------------------------------------------------------------------------
-- Dynamic: runtime only
-- ---------------------------------------------------------------------------------------

function Props.Dynamic(parent: Instance, toWorld: (number, number, number) -> Vector3)
	local CollectionService = game:GetService("CollectionService")
	local gym, atrium = Plan.Gym(), Plan.Atrium()
	local floor = Plan.SlabStuds
	local folder = Instance.new("Folder")
	folder.Name = "PropsDynamic"
	folder.Parent = parent

	local courtZ = (gym.Z1 + gym.Z2) / 2

	-- ---- three heavy bags in the fitness bay along the hall's back wall
	for index = 1, 3 do
		local x = gym.X1 + 18 + (index - 1) * 22
		local z = gym.Z2 - 18

		local mount = Kit.Block(folder, `BagMount{index}`, toWorld(x, floor + 30, z), Vector3.new(3, 1, 3), IRON_LIT, {
			material = Enum.Material.Metal,
		})

		local bag = Instance.new("Part")
		bag.Name = `HeavyBag{index}`
		bag.Size = Vector3.new(4, 14, 4)
		bag.Shape = Enum.PartType.Cylinder
		bag.CFrame = CFrame.new(toWorld(x, floor + 16, z)) * CFrame.Angles(0, 0, math.rad(90))
		bag.Anchored = false
		bag.Color = CANVAS
		bag.Material = Enum.Material.Fabric
		-- Heavy, so Workout.StrikeImpulse reads as moving something with mass. That constant is
		-- tuned against roughly this density.
		bag.CustomPhysicalProperties = PhysicalProperties.new(6, 0.6, 0.2, 1, 1)
		bag.Parent = folder

		local top = Instance.new("Attachment")
		top.Position = Vector3.new(7, 0, 0)
		top.Parent = bag
		local hook = Instance.new("Attachment")
		hook.Parent = mount

		-- The rope is the hard limit; the spring is the damping. Roblox has no air drag, so a
		-- rope alone gives a pendulum that swings until the server dies.
		local rope = Instance.new("RopeConstraint")
		rope.Attachment0, rope.Attachment1 = hook, top
		rope.Length = 7
		rope.Visible = true
		rope.Parent = bag

		local spring = Instance.new("SpringConstraint")
		spring.Attachment0, spring.Attachment1 = hook, top
		spring.FreeLength = 7
		spring.Stiffness = 4000
		spring.Damping = 900
		spring.Parent = bag
	end

	-- ---- two weight benches, Seat plus a sibling named Barbell
	for index = 1, 2 do
		local x = gym.X2 - 22
		local z = gym.Z2 - 30 + (index - 1) * 20

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
		CollectionService:AddTag(seat, "WeightBench")

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

	-- ---- the learning stair's tiers are the real seating, so the spectator seats go court-side
	for index = 1, 6 do
		local z = courtZ - 40 + (index - 1) * 16
		local seat = Instance.new("Seat")
		seat.Name = `Spectator{index}`
		seat.Size = Vector3.new(4, 1, 12)
		seat.CFrame = CFrame.new(toWorld(gym.X1 + 6, floor + 3, z))
		seat.Anchored = true
		seat.Color = TIMBER
		seat.Material = Enum.Material.WoodPlanks
		seat.Parent = folder
		CollectionService:AddTag(seat, "SpectatorSeat")
	end

	return folder
end

return Props
