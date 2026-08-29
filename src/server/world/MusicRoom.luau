--!strict
-- The music room, as a room that exists.
--
-- One thing in it: the stand you play at. Unlike the lab, the studio and the reading room,
-- nothing here is a destination you walk between mid-lesson -- the whole piece happens where
-- you are standing, because a rhythm you have to walk across a room to keep is not a rhythm.
--
-- So the room is deliberately the thinnest of the four. The four lane posts are there to
-- say which lane is which *in the world* rather than only on the panel, which is the same
-- reason the lab has a board on a wall: a player should be able to look up from the screen
-- and still know where they are.
--
-- Split from MusicService for the reason Lab is split from ScienceService: where a thing
-- stands and what happens when you reach it are different questions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Kit = require(script.Parent.Kit)

local MusicRoom = {}

local MUSIC = Config.School.Music
local BUILD = MUSIC.Build

export type Room = {
	center: Vector3,
	stand: Vector3,
}

local room: Room? = nil
local folder: Folder? = nil

local function roomFolder(): Folder
	local existing = folder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "MusicRoom"
	made.Parent = workspace
	folder = made
	return made
end

local function onCircle(center: Vector3, bearing: number, share: number): Vector3
	local direction = CFrame.Angles(0, math.rad(bearing), 0) * Vector3.new(0, 0, -1)
	return center + direction * (BUILD.RoomRadiusStuds * share)
end

-- Builds the room around a centre point, once. Nil means it could not be laid, which the
-- caller turns into Music refusing at the door with a reason.
function MusicRoom.Build(center: Vector3): Room?
	local existing = room
	if existing ~= nil then
		return existing
	end

	local parent = roomFolder()
	local standAt = onCircle(center, BUILD.StandBearing, BUILD.StandDistanceShare)

	local stand = Kit.Block(parent, "MusicStand", standAt + Vector3.new(0, 2.2, 0), Vector3.new(7, 4.4, 2.4), {
		color = Color3.fromRGB(52, 56, 68),
	})
	Kit.Sign(stand, "Stand here", 8, BUILD.LabelMaxDistanceStuds, Color3.fromRGB(244, 246, 250))

	-- One post per lane, in front of the stand and spread across it, so the lanes exist in the
	-- room and not only in the panel. Coloured left to right in the same order the panel draws
	-- them, which is the whole of what makes them worth building.
	local colors = {
		Color3.fromRGB(232, 106, 118),
		Color3.fromRGB(238, 190, 96),
		Color3.fromRGB(108, 196, 142),
		Color3.fromRGB(104, 158, 232),
	}
	for lane = 1, MUSIC.Lanes do
		local offset = (lane - (MUSIC.Lanes + 1) / 2) * 5
		local post = Kit.Block(parent, `Lane{lane}`, standAt + Vector3.new(offset, 5, -7), Vector3.new(3.4, 10, 1.2), {
			color = colors[((lane - 1) % #colors) + 1],
			material = Enum.Material.Neon,
		})
		post.CastShadow = false
	end

	local built: Room = { center = center, stand = standAt }
	room = built
	return built
end

function MusicRoom.Room(): Room?
	return room
end

function MusicRoom.Clear()
	local existing = folder
	if existing ~= nil then
		existing:Destroy()
	end
	folder = nil
	room = nil
end

return MusicRoom
