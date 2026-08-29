--!strict
-- The town gym, as a room that exists.
--
-- The equipment in this game has always been *found* rather than built: GymService walks
-- CollectionService for parts tagged AgesGymEquipment and reads a GymKind off each. That is
-- a good design -- it means a builder can drag a treadmill into Studio and it works -- and
-- none of it changes here. What it also meant is that on a fresh place there was no gym at
-- all: four machines had to be hand-placed before the whole system existed.
--
-- So this lays a gym and tags what it lays. GymService cannot tell the difference; a bench
-- built here and a bench dragged in by hand arrive down the same signal, and anything
-- hand-placed keeps working exactly as it did. **Nothing in this file knows what a workout
-- is** -- it puts iron on a floor and puts a tag on the iron.
--
-- Modelled on a powerlifting floor rather than a health club: racks on platforms down the
-- back, benches in the middle, cardio along the glass, dumbbells on the mirrored wall. Dense
-- on purpose. A gym reads as serious because every square foot has something heavy on it,
-- and a sparse room with four machines in it reads as a showroom -- which is exactly what
-- the old four-hand-placed-parts version looked like.
--
-- Laid around the gym place point, like every other room this codebase builds in code. There
-- is not an absolute world coordinate in it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Kit = require(script.Parent.Kit)

local GymRoom = {}

local GYM = Config.Gym
local BUILD = GYM.Build

local W = BUILD.WidthStuds
local D = BUILD.DepthStuds
local H = BUILD.HeightStuds

-- The palette. A warehouse gym is concrete, brick and black rubber with the only colour in
-- the room coming off the plates -- which is why the plates are worth their parts.
local CONCRETE = Color3.fromRGB(188, 188, 190)
local FLOOR = Color3.fromRGB(158, 158, 160)
local BRICK = Color3.fromRGB(150, 92, 74)
local RUBBER = Color3.fromRGB(30, 31, 34)
local STEEL = Color3.fromRGB(198, 202, 208)
local DARK = Color3.fromRGB(52, 55, 62)
local GLASS_TINT = Color3.fromRGB(196, 220, 240)

export type Room = {
	center: Vector3,
}

local room: Room? = nil
local folder: Folder? = nil

local function gymFolder(): Folder
	local existing = folder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "TownGym"
	made.Parent = workspace
	folder = made
	return made
end

-- Tags a part as equipment of a given kind.
--
-- The one function in this file GymService cares about, and the only place the tag and the
-- attribute are written -- so a machine that is built but not registered, or registered
-- under a kind nothing implements, is impossible by construction rather than by review.
local function makeMachine(part: BasePart, kind: string)
	part:SetAttribute(GYM.GymKindAttribute, kind)
	CollectionService:AddTag(part, GYM.EquipmentTag)
end

-- Builds the gym around a centre point, once. Nil means it could not be laid, which the
-- caller treats as "there is no gym here" -- hand-placed equipment elsewhere still works.
function GymRoom.Build(center: Vector3): Room?
	local existing = room
	if existing ~= nil then
		return existing
	end

	local parent = gymFolder()
	local function at(x: number, y: number, z: number): Vector3
		return center + Vector3.new(x, y, z)
	end

	local halfW = W / 2
	local halfD = D / 2

	-- The shell. Concrete floor, brick at the back, glass at the front, mirrors down one side.
	Kit.Slab(parent, "GymFloor", at(0, 0.3, 0), W, D, 0.6, { color = FLOOR, material = Enum.Material.Concrete })
	Kit.Wall(parent, "GymBrick", at(-halfW, 0.3, halfD), at(halfW, 0.3, halfD), H, 1.2, {
		color = BRICK,
		material = Enum.Material.Brick,
	})
	Kit.Wall(parent, "GymEndL", at(-halfW, 0.3, -halfD), at(-halfW, 0.3, halfD), H, 1.2, {
		color = CONCRETE,
		material = Enum.Material.Concrete,
	})
	Kit.GlassWall(parent, "GymFront", at(-halfW, 0.3, -halfD), at(halfW, 0.3, -halfD), H, 1.2, 0.66, CONCRETE, GLASS_TINT)
	Kit.Slab(parent, "GymRoof", at(0, 0.3 + H, 0), W, D, 1.2, { color = CONCRETE, material = Enum.Material.Concrete })

	-- The mirrored wall. Half of what a gym looks like, and the reason the right-hand side of
	-- the room does not read as a blank slab.
	local mirrorLength = D * BUILD.MirrorShare
	Kit.Mirror(parent, "GymMirror", at(halfW - 0.8, 1.5, -mirrorLength / 2), at(halfW - 0.8, 1.5, mirrorLength / 2), H * 0.5)

	-- The name on the brick, which is the one piece of graphic in the room.
	local band = Kit.Block(parent, "GymBand", at(0, H * 0.62, halfD - 1.4), Vector3.new(W * 0.5, 7, 0.3), {
		color = BRICK,
		material = Enum.Material.Brick,
	})
	band.CastShadow = false
	Kit.Sign(band, "POWER LIFTERS", W * 0.4, BUILD.LabelMaxDistanceStuds * 2, Color3.fromRGB(238, 158, 96))

	-- Pendant lamps on a grid. Dozens of small hanging lights rather than a few panels is most
	-- of why the reference reads as a warehouse rather than as an office.
	for ax = 1, BUILD.LightsAcross do
		for az = 1, BUILD.LightsAlong do
			Kit.Pendant(
				parent,
				`GymLamp{ax}_{az}`,
				at(-halfW + W * ((ax - 0.5) / BUILD.LightsAcross), 0.3 + H - 0.6, -halfD + D * ((az - 0.5) / BUILD.LightsAlong)),
				4.5,
				DARK
			)
		end
	end

	-- Squat racks on rubber platforms down the back. These are the room's silhouette: a row of
	-- uprights with loaded bars in them is what a powerlifting floor looks like from the door.
	--
	-- Not tagged. There are four workout kinds and none of them is a squat, so a rack that
	-- registered would either need a fifth kind nobody wrote or would have to lie about being
	-- a bench. Decoration that is honest about being decoration.
	for index = 1, BUILD.Racks do
		local x = -halfW + W * ((index - 0.5) / BUILD.Racks)
		local z = halfD - BUILD.PlatformDepthStuds / 2 - 6
		Kit.Slab(parent, `Platform{index}`, at(x, 0.7, z), BUILD.PlatformWidthStuds, BUILD.PlatformDepthStuds, 0.4, {
			color = RUBBER,
			collide = false,
		})
		for side = -1, 1, 2 do
			Kit.Column(parent, `RackPost{index}_{side}`, at(x + side * 3.4, 0.7, z), 9, 0.9, STEEL)
			Kit.Block(parent, `RackFoot{index}_{side}`, at(x + side * 3.4, 1.1, z - 2.5), Vector3.new(1, 0.6, 6), { color = STEEL })
		end
		Kit.Block(parent, `RackTie{index}`, at(x, 9.4, z), Vector3.new(7.8, 0.7, 0.7), { color = STEEL })
		Kit.Barbell(parent, `RackBar{index}`, at(x, 7.4, z - 0.4), 14, 3)
	end

	-- Flat benches through the middle, each with a bar over it. These are the "bench" machine.
	for index = 1, BUILD.Benches do
		local x = -halfW + W * ((index - 0.5) / BUILD.Benches)
		local z = 2
		Kit.Block(parent, `BenchLeg{index}`, at(x, 1.2, z), Vector3.new(1.6, 1.8, 9), { color = STEEL })
		local pad = Kit.Block(parent, `Bench{index}`, at(x, 2.6, z), Vector3.new(3.4, 1, 10), {
			color = RUBBER,
			collide = true,
		})
		makeMachine(pad, "bench")
		Kit.Sign(pad, "Bench press", 8, BUILD.LabelMaxDistanceStuds, Color3.fromRGB(240, 240, 244))
		for side = -1, 1, 2 do
			Kit.Column(parent, `BenchPost{index}_{side}`, at(x + side * 2.6, 0.7, z - 3.6), 5.5, 0.7, STEEL)
		end
		Kit.Barbell(parent, `BenchBar{index}`, at(x, 6.2, z - 3.6), 12, 2)
	end

	-- Cardio along the glass, facing out. Facing out matters: a treadmill against a blank wall
	-- is a treadmill nobody would choose, and every gym in the world puts them at the window.
	for index = 1, BUILD.Treadmills do
		local x = -halfW + W * ((index - 0.5) / BUILD.Treadmills)
		local z = -halfD + 8
		Kit.Block(parent, `TreadBase{index}`, at(x, 1, z), Vector3.new(6, 1.4, 11), { color = DARK })
		local belt = Kit.Block(parent, `Treadmill{index}`, at(x, 1.9, z + 1), Vector3.new(5, 0.5, 8), {
			color = RUBBER,
			collide = true,
		})
		makeMachine(belt, "treadmill")
		Kit.Sign(belt, "Treadmill", 8, BUILD.LabelMaxDistanceStuds, Color3.fromRGB(240, 240, 244))
		-- The console and the handrails.
		Kit.Block(parent, `TreadConsole{index}`, at(x, 6, z - 4.4), Vector3.new(5, 3, 0.6), { color = Color3.fromRGB(24, 26, 34) })
		Kit.Block(parent, `TreadScreen{index}`, at(x, 6.2, z - 4.8), Vector3.new(3.6, 1.8, 0.2), {
			color = Color3.fromRGB(88, 150, 214),
			material = Enum.Material.Neon,
		}).CastShadow = false
		for side = -1, 1, 2 do
			Kit.Block(parent, `TreadRail{index}_{side}`, at(x + side * 2.6, 4.4, z - 2), Vector3.new(0.4, 0.4, 5), { color = STEEL })
		end
	end

	-- Dumbbell racks along the mirrored side, in descending sizes.
	for index = 1, BUILD.DumbbellRacks do
		local z = -halfD + D * ((index - 0.5) / BUILD.DumbbellRacks)
		local x = halfW - 7
		Kit.Block(parent, `DbFrame{index}`, at(x, 1.6, z), Vector3.new(4, 2.6, 16), { color = DARK })
		local rack = Kit.Block(parent, `Dumbbells{index}`, at(x, 3.4, z), Vector3.new(4.4, 1, 16), {
			color = STEEL,
			collide = true,
		})
		makeMachine(rack, "dumbbells")
		Kit.Sign(rack, "Dumbbells", 8, BUILD.LabelMaxDistanceStuds, Color3.fromRGB(240, 240, 244))
		for bell = 1, 8 do
			local bz = z - 7 + bell * 1.7
			local size = 1.9 - bell * 0.08
			Kit.Block(parent, `Db{index}_{bell}`, at(x, 4.3, bz), Vector3.new(3.2, 0.5, 0.5), { color = STEEL }).CastShadow = false
			for side = -1, 1, 2 do
				Kit.Block(parent, `DbHead{index}_{bell}_{side}`, at(x + side * 1.3, 4.3, bz), Vector3.new(0.9, size, size), {
					color = RUBBER,
				}).CastShadow = false
			end
		end
	end

	-- The pull-up frame, in the corner where there is height for it.
	local px = -halfW + 12
	local pz = -halfD + D * 0.5
	for side = -1, 1, 2 do
		Kit.Column(parent, `PullPost{side}`, at(px + side * 5, 0.7, pz), 13, 1, STEEL)
	end
	local bar = Kit.Block(parent, "PullupBar", at(px, 13.5, pz), Vector3.new(11, 0.7, 0.7), {
		color = STEEL,
		collide = true,
	})
	makeMachine(bar, "pullup")
	Kit.Sign(bar, "Pull-up bar", 9, BUILD.LabelMaxDistanceStuds, Color3.fromRGB(240, 240, 244))

	-- Loose plates and a chalk stand, because a gym floor is never tidy and a perfectly clear
	-- floor is the tell that a room was generated.
	for index = 1, 6 do
		local angle = (index / 6) * math.pi * 2
		Kit.Block(parent, `LoosePlate{index}`, at(math.cos(angle) * (W * 0.28), 0.9, math.sin(angle) * (D * 0.2)), Vector3.new(3.4, 0.5, 3.4), {
			color = if index % 2 == 0 then Color3.fromRGB(206, 66, 62) else Color3.fromRGB(56, 110, 196),
		}).CastShadow = false
	end
	Kit.Block(parent, "ChalkStand", at(halfW - 16, 2, halfD - 14), Vector3.new(3, 3.4, 3), { color = Color3.fromRGB(236, 236, 240) })

	local built: Room = { center = center }
	room = built
	return built
end

function GymRoom.Room(): Room?
	return room
end

-- Takes the gym down. Every machine it laid goes with it, and CollectionService drops the
-- tags on destroy, so GymService unregisters them on its own -- which is why this does not
-- have to walk them.
function GymRoom.Clear()
	local existing = folder
	if existing ~= nil then
		existing:Destroy()
	end
	folder = nil
	room = nil
end

return GymRoom
