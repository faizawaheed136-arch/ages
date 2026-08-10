--!strict
-- What the lobby *looks* like: a list of pieces, and nothing that knows how to build them.
--
-- Every piece is positioned relative to the mark the player's avatar stands on, never in
-- world coordinates. That is the whole reason this is a module and not twenty parts in
-- `lobby.project.json`, which is where static geometry would normally live. The stage has
-- three things that must agree with each other -- where the character stands, where the
-- platform under them is, and where the camera looks -- and in JSON those are three
-- hand-copied numbers with nothing stopping them drifting apart. Here the mark is the
-- origin, `Config.Lobby.Stage.Origin` is the only absolute position in the file, and moving
-- the whole set is one edit.
--
-- Deliberately built from primitives with no assets at all. Not because the composition is
-- a placeholder -- it is meant to be the finished screen -- but because a lobby that
-- depends on an uploaded model cannot be reviewed by reading the repository, and this is
-- the first thing every player will ever see.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

-- A piece of scenery. `offset` and `size` are studs; `offset` is from the mark.
--
-- `spin` is degrees per second about Y, and it is the only animation in the file. Anything
-- that needed a second kind of movement would be a system rather than a piece, and would
-- belong beside the camera controller instead.
export type Piece = {
	name: string,
	offset: Vector3,
	size: Vector3,
	rotation: Vector3?,
	-- Block unless said otherwise. Only the halo is anything else, and it has to be a cylinder
	-- rather than a thin box for the one reason that matters at this camera distance: a box's
	-- corners are visible against the backdrop and a disc's are not.
	shape: Enum.PartType?,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	reflectance: number?,
	-- Whether the avatar can stand on it. True for exactly one piece -- the disc -- and it
	-- matters more than it looks. A Humanoid with nothing solid under it never leaves the
	-- Freefall state, so an avatar held on a mark above thin air stands there in a falling
	-- pose forever, with the idle animation never playing. The character is anchored anyway
	-- and does not need the floor to hold it up; it needs the floor to *be there* so the
	-- Humanoid's ground check finds it.
	solid: boolean?,
	-- Lit from inside rather than by the sun. A `light` piece carries its own PointLight,
	-- which is what makes the floating shards read as shards rather than as grey blocks --
	-- there is no skybox sun in here worth speaking of.
	light: { color: Color3, range: number, brightness: number }?,
	spin: number?,
}

local Stage = {}

local ACCENT = Color3.fromRGB(122, 196, 255)
local WARM = Color3.fromRGB(255, 186, 122)
local DEEP = Color3.fromRGB(28, 32, 46)
local PALE = Color3.fromRGB(206, 214, 232)
-- The halo, and the only colour in here that is also in the menu palette
-- (`Config.Lobby.Menu.Palette.Accent`). Deliberately the same: the disc behind the character
-- is the largest warm shape on the screen and the title is the second largest, and two golds
-- that nearly match is worse than one gold or two colours.
local GOLD = Color3.fromRGB(225, 200, 150)

-- Which way the camera lies from the mark, on the horizontal, in radians.
--
-- Derived from `CameraOffset` rather than written down, because the halo has to face the
-- camera and a hand-copied angle is exactly the drift this file exists to prevent -- move the
-- camera and a literal would leave the disc edge-on, showing the player a gold line.
local function cameraYaw(): number
	local offset = Config.Lobby.Stage.CameraOffset
	return math.atan2(offset.X, offset.Z)
end

-- The unit vector from the mark toward the camera, flattened.
local function towardCamera(): Vector3
	local yaw = cameraYaw()
	return Vector3.new(math.sin(yaw), 0, math.cos(yaw))
end

-- The unit vector to the camera's right, flattened.
--
-- Anything placed "to one side" has to be placed along *this*, not along world X. They happen
-- to be about thirty degrees apart at the current camera, which is far enough that a pair of
-- pieces offset symmetrically in X arrives visibly lopsided on screen -- one closer, one
-- further, neither where it was meant to be.
local function cameraRight(): Vector3
	local toward = towardCamera()
	return Vector3.new(toward.Z, 0, -toward.X)
end

-- The disc the avatar stands on, and the ring around it.
--
-- Split into three pieces rather than one cylinder because the lip is what gives the
-- platform an edge to catch the light on. A single flat disc at this camera angle reads as
-- a painted circle on nothing.
local function platform(): { Piece }
	return {
		{
			name = "Disc",
			offset = Vector3.new(0, -0.5, 0),
			size = Vector3.new(18, 1, 18),
			color = DEEP,
			material = Enum.Material.Slate,
			solid = true,
		},
		{
			name = "Lip",
			offset = Vector3.new(0, -0.15, 0),
			size = Vector3.new(19.2, 0.3, 19.2),
			color = ACCENT,
			material = Enum.Material.Neon,
			transparency = 0.35,
		},
		-- Hangs below the disc and is never lit from above, so it fades into the void
		-- instead of ending. The platform should not look like it was cut out and put there.
		{
			name = "Underside",
			offset = Vector3.new(0, -3.5, 0),
			size = Vector3.new(14, 6, 14),
			color = Color3.fromRGB(18, 20, 30),
			material = Enum.Material.Rock,
		},
	}
end

-- Two pillars flanking the mark, set back and turned slightly inward.
--
-- They exist for depth, not decoration: with nothing between the avatar and the backdrop
-- the shot has no middle distance and the character looks pasted on. Turned inward by a few
-- degrees so the pair frames the mark rather than fencing it.
local function pillars(): { Piece }
	local out: { Piece } = {}
	for _, side in { -1, 1 } do
		table.insert(out, {
			name = if side < 0 then "PillarLeft" else "PillarRight",
			offset = Vector3.new(side * 7.5, 5, -3),
			size = Vector3.new(1.8, 12, 1.8),
			rotation = Vector3.new(0, side * -8, 0),
			color = Color3.fromRGB(46, 52, 70),
			material = Enum.Material.Concrete,
		})
		table.insert(out, {
			name = if side < 0 then "PillarLightLeft" else "PillarLightRight",
			offset = Vector3.new(side * 7.5, 10.4, -3),
			size = Vector3.new(2.2, 0.5, 2.2),
			color = WARM,
			material = Enum.Material.Neon,
			light = { color = WARM, range = 26, brightness = 2.2 },
		})
	end
	return out
end

-- Shards turning slowly in the air behind and above the mark.
--
-- Placed by hand rather than generated, because six positions chosen to sit in the gaps of
-- one particular camera framing is exactly the kind of thing a loop gets wrong. A random
-- scatter puts one in front of the avatar's face roughly one time in six, and it would be a
-- different one every server.
local SHARDS: { { pos: Vector3, size: Vector3, spin: number } } = {
	{ pos = Vector3.new(-11, 9, -8), size = Vector3.new(1.6, 2.4, 1.6), spin = 11 },
	{ pos = Vector3.new(12.5, 12, -11), size = Vector3.new(2.2, 3, 2.2), spin = -8 },
	{ pos = Vector3.new(-8, 15.5, -14), size = Vector3.new(1.2, 1.8, 1.2), spin = 15 },
	{ pos = Vector3.new(9, 6.5, -16), size = Vector3.new(1.8, 2.6, 1.8), spin = -12 },
	{ pos = Vector3.new(-15, 4, -13), size = Vector3.new(1.4, 2, 1.4), spin = 9 },
	{ pos = Vector3.new(16, 17, -19), size = Vector3.new(2.6, 3.6, 2.6), spin = -6 },
}

local function shards(): { Piece }
	local out: { Piece } = {}
	for index, shard in SHARDS do
		table.insert(out, {
			name = `Shard{index}`,
			offset = shard.pos,
			size = shard.size,
			rotation = Vector3.new(18, index * 37, 24),
			color = PALE,
			material = Enum.Material.Glass,
			transparency = 0.45,
			reflectance = 0.3,
			light = { color = ACCENT, range = 18, brightness = 1.1 },
			spin = shard.spin,
		})
	end
	return out
end

-- The glowing disc the character is silhouetted against, and the beams either side of it.
--
-- **This is the piece that makes the shot a composition rather than a character in a room.**
-- A lit avatar on a dark backdrop has nothing behind it, so the eye has no reason to land on
-- it; a large, simple, bright shape directly behind the head gives the silhouette an edge and
-- puts the player at the centre of the frame by geometry rather than by hope.
--
-- Two discs rather than one. The outer is wide and nearly transparent and reads as glow; the
-- inner is small and solid and reads as a source. One disc at a middle transparency reads as
-- neither -- it looks like a flat sticker, which is precisely what it is.
--
-- Both are rotated to face the camera, and `cameraYaw` is why: a cylinder's axis is its local
-- X, so the disc faces the camera exactly when local X points at it. Turning by (yaw - 90°)
-- does that for any camera position.
local function halo(): { Piece }
	local back = -towardCamera()
	-- Degrees, and a quarter turn off the camera bearing -- see above.
	local facing = math.deg(cameraYaw()) - 90

	return {
		{
			name = "HaloOuter",
			-- Behind the mark and up at head height, so the character's head and shoulders sit
			-- inside the disc rather than under it. Sixteen studs back rather than the four the
			-- word "behind" suggests: at this camera the disc has to clear the pillars, and a
			-- glow that near the character would light the back of their head instead of
			-- silhouetting it.
			offset = back * 16 + Vector3.new(0, 5.5, 0),
			-- X is the cylinder's thickness; Y and Z are its diameter. Twenty-two studs across at
			-- roughly thirty from the camera puts it at a little over half the frame height --
			-- big enough to be the thing behind the character, small enough not to become the
			-- subject.
			size = Vector3.new(0.4, 22, 22),
			rotation = Vector3.new(0, facing, 0),
			shape = Enum.PartType.Cylinder,
			color = GOLD,
			material = Enum.Material.Neon,
			transparency = 0.82,
		},
		{
			-- A fraction further back so the two never z-fight. Coplanar neon is the one pairing
			-- that flickers differently on every machine.
			name = "HaloInner",
			offset = back * 16.4 + Vector3.new(0, 5.5, 0),
			size = Vector3.new(0.4, 12, 12),
			rotation = Vector3.new(0, facing, 0),
			shape = Enum.PartType.Cylinder,
			color = GOLD,
			material = Enum.Material.Neon,
			transparency = 0.55,
			-- The only light on the far side of the character, and the reason the silhouette has
			-- an edge rather than a seam. Short range so it stays a rim light and does not reach
			-- around to fill in the front, which the key light is for.
			light = { color = GOLD, range = 24, brightness = 1.6 },
		},
	}
end

-- Two tall slabs of light standing well behind the halo, leaning outward.
--
-- They are not lights -- they cast nothing and light nothing. They are shapes, and their only
-- job is to give the empty upper half of the frame something with a vertical in it, so the
-- backdrop is not a flat field above the character's head. Leaning outward rather than
-- standing straight because two verticals flanking a third vertical is a fence.
local function beams(): { Piece }
	local out: { Piece } = {}
	local back = -towardCamera()
	-- Along the camera's right, not along world X. Offsetting a symmetric pair in X puts one of
	-- them nearer the camera than the other, and the pair reads as crooked rather than as
	-- flanking -- see `cameraRight`.
	local right = cameraRight()
	for _, side in { -1, 1 } do
		table.insert(out, {
			name = if side < 0 then "BeamLeft" else "BeamRight",
			offset = back * 26 + right * (side * 17) + Vector3.new(0, 20, 0),
			size = Vector3.new(2.6, 44, 0.4),
			-- Yawed to face the camera, then rolled outward *within* that facing --
			-- `CFrame.Angles` applies X, then Y, then Z, so the roll happens in the already
			-- turned frame and leans the slab across the screen rather than away from it.
			rotation = Vector3.new(0, math.deg(cameraYaw()), side * 13),
			color = PALE,
			material = Enum.Material.Neon,
			transparency = 0.9,
		})
	end
	return out
end

-- A far wall of haze behind everything, and the two lights that actually shape the avatar.
--
-- The backdrop is a single enormous slab rather than a skybox because it has to be *behind
-- the shards and in front of nothing* -- a skybox is at infinity and the shards would have
-- no depth to sit in front of. It is dark, matte and out of focus by virtue of the
-- atmosphere set in the place file.
--
-- The two lights are a key and a fill, and they are the reason the avatar reads as a person
-- standing somewhere rather than a mannequin. The key is warm, high and on the camera's
-- side; the fill is cold, low and on the far side, bright enough to keep the shadowed half
-- from going black but not bright enough to flatten it.
local function backdropAndLights(): { Piece }
	return {
		{
			name = "Backdrop",
			offset = Vector3.new(0, 18, -46),
			size = Vector3.new(220, 90, 3),
			color = Color3.fromRGB(22, 25, 37),
			material = Enum.Material.SmoothPlastic,
		},
		{
			name = "KeyLight",
			offset = Vector3.new(5, 11, 7),
			size = Vector3.new(0.6, 0.6, 0.6),
			color = WARM,
			material = Enum.Material.Neon,
			transparency = 1,
			light = { color = WARM, range = 34, brightness = 3.4 },
		},
		{
			name = "FillLight",
			offset = Vector3.new(-8, 5, -6),
			size = Vector3.new(0.6, 0.6, 0.6),
			color = ACCENT,
			material = Enum.Material.Neon,
			transparency = 1,
			light = { color = ACCENT, range = 30, brightness = 1.6 },
		},
	}
end

-- Everything, in the order it is built. Order does not matter to the result -- nothing here
-- collides or welds -- but it is the order the pieces appear in Explorer, which is worth
-- keeping legible for whoever next moves the camera.
function Stage.Pieces(): { Piece }
	local out: { Piece } = {}
	for _, group in { platform(), halo(), beams(), pillars(), shards(), backdropAndLights() } do
		for _, piece in group do
			table.insert(out, piece)
		end
	end
	return out
end

-- Where the mark is, in world space. The one absolute in the file, and everything above is
-- measured from it.
function Stage.Origin(): Vector3
	return Config.Lobby.Stage.Origin
end

return Stage
