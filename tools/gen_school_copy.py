#!/usr/bin/env python3
"""Bakes the editable copy of v1 into assets/SchoolV1Copy.rbxmx.

Same harness as gen_school.py, pointed at world/SchoolCopy.luau -- the fork -- and offset onto
the copy's own ground. Separate from gen_school.py rather than a flag on it because the two
schools are meant to be worked on independently, and one tool that could bake either is a tool
that will eventually bake the wrong one over the other.

Original header follows.

Bakes the school into assets/School.rbxmx so it is visible in Studio without playing.

Run from the repo root:  python tools/gen_school.py

**Why this exists.** `src/server/world/School.luau` lays the school at runtime, which means
the building only exists once the server starts. Open the place in Studio and the plot is
empty; you have to press Play to see anything. That is fine for a system and useless for
looking at a map, and "I want to see the school before I join the game" is a reasonable thing
to want from a building.

**Why it is not a second copy of the school.** The obvious way to get baked geometry is to
rewrite the whole builder in Python next to `gen_city.py`. That would be two schools -- two
definitions of every room, drifting apart from the first edit onward. Instead this *runs the
real builder* under `tools/bootcheck.luau`, with `Instance.new` replaced by a recorder, and
emits whatever it actually laid. There is exactly one definition of the school and it is the
Luau one; this is a camera pointed at it.

So the flow is:

    School.luau  --(bootcheck harness, recording Instance.new)-->  JSON  -->  School.rbxmx

Re-run it after any change to School.luau, Kit.luau or the school's Config, or the baked
asset goes stale against the thing that generates it. `tools/check.py` cannot catch that --
it reads source, and a stale asset is perfectly valid XML.

LIGHTING
--------

**The school has 180 light fittings and none of them were lights.** Kit.LightPanel and the
ceiling strips are Neon: they glow, which looks lit in a screenshot taken at noon, and they
emit nothing at all. The building has a day/night cycle over it, so after dark every room went
black -- which is exactly what the reference photographs are not.

Kit's comment explains why, and it is a fair argument: "a dozen PointLights in one room costs
more than the building." One real light per fitting would be 180 of them and would be
unplayable.

So the fittings stay Neon and a *subset* is given a real light -- every Nth one, with a range
wide enough that the gaps do not read as gaps. Fourteen or so lights covers the corridors and
the atrium, which is where a player actually is, at a fraction of the cost of lighting every
panel. The rooms keep their glow and borrow the corridor's spill through their glass fronts,
which is how the reference rooms are lit too.

Baked rather than added at runtime, and that is forced: Config.School.Building.Baked is true,
so the parts School.luau lays are destroyed after the room anchors are read. A light parented
to one of those would be destroyed with it. The asset is the thing that survives, so the light
has to be in the asset.

**What it deliberately drops.** Signs (BillboardGui/TextLabel) are laid at runtime by
`Kit.Sign` and are not baked: they are readouts rather than geometry, several of them say
things that are only true while a game is running, and a billboard baked into the map cannot
be updated by the code that owns it. The building is baked; the writing on it is not.
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import rbxmx  # noqa: E402

LUAU = Path.home() / ".aftman/tool-storage/luau" / ("luau.exe" if sys.platform == "win32" else "luau")
OUT = ROOT / "assets" / "SchoolV1Copy.rbxmx"

# How far the copy stands from v1's place point.
#
# Chosen so the copy's *bounding box* clears every other asset's, not just so its parts miss
# theirs. The first attempt used an occupancy grid alone and put the copy 206 studs into v1's
# box: the cells were genuinely empty, because v1's grounds are sparse out at that corner, but
# the two buildings still read as one overlapping mess. Sparse does not mean free.
#
# Copy sits at x -640..-180, z -1056..-644. v1 is at x -886..-426, z -585..-181 -- disjoint on
# z with 59 studs to spare.
COPY_OFFSET = (246.0, 0.0, -471.0)

# Which fittings get a real light, and how strong. One in LIGHT_EVERY of the parts whose name
# matches LIT_NAMES, which works out at roughly a dozen for the whole building.
#
# Range is deliberately large and brightness modest: a few wide, soft lights read as a lit room,
# where the same budget spent on many small bright ones reads as a row of spotlights and shows
# every gap between them.
# CeilPanel and LobbyPanel are the current fittings; CeilStrip was the old one and no longer
# exists, so leaving it here meant the corridor grid and the whole lobby ceiling emitted no
# light at all -- Neon glows but does not illuminate, so the building got *darker* the moment
# the strips were replaced by a denser grid. Kept in the list because the copy still builds them.
LIT_NAMES = ("CeilPanel", "LobbyPanel", "CeilStrip", "CorridorLight", "LobbyBanner", "Lantern")
LIGHT_EVERY = 3
LIGHT_RANGE = 62
LIGHT_BRIGHTNESS = 1.4
LIGHT_COLOR = (255, 250, 235)
SCRATCH = ROOT / "build"


def _lua_string(s: str) -> str:
    out = s.replace("\\", "\\\\").replace('"', '\\"')
    return '"' + out.replace("\n", "\\n").replace("\r", "\\r").replace("\0", "\\0") + '"'


RECORDER = r"""

-- ---------------------------------------------------------------------------------------
-- Recorder: run the real builder, write down every part it lays.
-- ---------------------------------------------------------------------------------------
--
-- Two things the boot harness deliberately does not provide have to be supplied here, and
-- both for the same reason: the harness is built to prove that code *runs*, so its stubs
-- swallow values rather than storing them. To read geometry back, values have to survive.
--
--   1. A part that remembers what was assigned to it. `Instance.new` returns a permissive
--      stub whose properties are write-only, so every recorded part came back empty.
--   2. A CFrame that is actually a position and an angle. `CFrame` is a stub, so
--      `CFrame.new(centre) * CFrame.Angles(0, yaw, 0)` produced another stub and the
--      position was lost.
--
-- The CFrame here is minimal on purpose -- position plus three angles, and multiplication
-- that adds both. That is exactly and only what Kit does with it (see Kit.Block, Kit.Rug):
-- a translation multiplied by a pure rotation. A general CFrame would be a matrix library
-- nobody needs and one more thing that could be subtly wrong.

-- Every material name this building uses, longest first so a short name cannot swallow a long
-- one. Kept beside the recorder rather than derived, because the Python side maps these exact
-- strings to numeric tokens and the two lists have to agree.
local MATERIAL_NAMES = {
	"SmoothPlastic", "CorrodedMetal", "DiamondPlate", "Cobblestone", "WoodPlanks",
	"Concrete", "Granite", "Pebble", "Marble", "Fabric", "Plastic",
	"Brick", "Glass", "Grass", "Metal", "Slate", "Sand", "Rock", "Neon", "Wood", "Foil", "Ice",
}

local function moduleNamed(needle)
	for _, entry in ipairs(order) do
		if string.find(entry.rel, needle, 1, true) ~= nil then
			return entry.value
		end
	end
	return nil
end

-- Required directly. `moduleNamed` only sees modules something in the game already pulled in,
-- and nothing requires the copy's builder -- it exists to be baked, not to run in the game.
local School = rootRequire(ServerScriptService.Server.world.SchoolCopy)
local PlaceService = moduleNamed("services/PlaceService.luau")
local V = baseEnv.Vector3.new

-- A CFrame that keeps what it was given.
local CFMT = {}
local function mkcf(pos, rx, ry, rz)
	return setmetatable({ Position = pos, rx = rx, ry = ry, rz = rz }, CFMT)
end
CFMT.__index = CFMT
CFMT.__mul = function(a, b)
	return mkcf(
		V(a.Position.X + b.Position.X, a.Position.Y + b.Position.Y, a.Position.Z + b.Position.Z),
		a.rx + b.rx, a.ry + b.ry, a.rz + b.rz
	)
end

baseEnv.CFrame = {
	new = function(a, b, c)
		if typeof(a) == "number" then
			return mkcf(V(a, b or 0, c or 0), 0, 0, 0)
		end
		return mkcf(V(a.X, a.Y, a.Z), 0, 0, 0)
	end,
	Angles = function(x, y, z)
		return mkcf(V(0, 0, 0), x or 0, y or 0, z or 0)
	end,
}

-- A part that keeps what it was given. Unknown reads fall through to the harness's own stub,
-- so anything this does not model still behaves the way the rest of the boot check expects.
local recorded = {}
local realNew = baseEnv.Instance.new

baseEnv.Instance.new = function(class)
	local props = {}
	local fallback = realNew(class)
	local obj = setmetatable({}, {
		__index = function(_, k)
			local v = props[k]
			if v ~= nil then
				return v
			end
			return fallback[k]
		end,
		__newindex = function(_, k, v)
			props[k] = v
		end,
	})
	if class == "Part" then
		table.insert(recorded, props)
	end
	return obj
end

-- The harness mounts no assets, so there is no place point to find. The real one's world
-- position is read out of Street.rbxmx by the Python side and substituted in below.
--
-- **This must be the true position, not the origin.** An asset baked around (0,0,0) mounts at
-- the origin -- a school hundreds of studs from the point every route in the game walks to --
-- and leaves the three place points that stood on the old school's floor (classroom,
-- science_lab, cafeteria) hanging with nothing under them. check_town catches exactly that.
PlaceService.Find = function(id)
	if id == "school" then
		return { part = { Position = V(SCHOOL_X, SCHOOL_Y, SCHOOL_Z) } }
	end
	return nil
end

-- The fork is loaded here rather than looked up in `order`, and the result is checked: the
-- harness hands back a permissive stub for a module that failed to load, and a stub answers
-- `.Build` with another stub rather than an error. Baking against one produces an empty asset
-- and no complaint, which is exactly what happened the first time.
if typeof(School) ~= "table" or typeof(School.Build) ~= "function" then
	-- The failure list is printed by bootcheck before this point, and the copy is required
	-- lazily *after* it -- so its own failure never made that list. Dump it here.
	for _, f in ipairs(failures) do
		if string.find(tostring(f.rel), "SchoolCopy", 1, true) then
			print("COPYFAIL	" .. tostring(f.rel) .. "	" .. tostring(f.err))
		end
	end
	error("[gen_school_copy] world/SchoolCopy.luau did not load -- got a stub, not the module.")
end
School.Clear()
School.Build(V(SCHOOL_X, SCHOOL_Y, SCHOOL_Z))

local function num(v, fallback)
	return if typeof(v) == "number" and v == v then v else fallback
end

-- A real Vector3 from the harness answers .X; a stub does not answer with a number. That is
-- the test for "did this value survive", and anything that fails it is dropped rather than
-- guessed: a part emitted at a stubbed coordinate is a part in the wrong place, which is
-- worse than one that is visibly absent.
local function vec3(v)
	if typeof(v) == "table" or typeof(v) == "vector" or typeof(v) == "userdata" then
		local x, y, z = num(v.X, nil), num(v.Y, nil), num(v.Z, nil)
		if x ~= nil and y ~= nil and z ~= nil then
			return x, y, z
		end
	end
	return nil
end

local rows = {}
local dropped = 0
for _, props in ipairs(recorded) do
	local sx, sy, sz = vec3(props.Size)
	local cf = props.CFrame
	-- Not an if-expression: `a, b, c = if x then f() else nil` keeps only the first return
	-- value in Luau, which silently reduced every position to its X.
	local px, py, pz
	if cf ~= nil then
		px, py, pz = vec3(cf.Position)
	end
	if sx ~= nil and px ~= nil then
		local color = props.Color
		local r, g, b = 200, 200, 200
		if color ~= nil and typeof(color.R) == "number" then
			r = math.floor(color.R * 255 + 0.5)
			g = math.floor(color.G * 255 + 0.5)
			b = math.floor(color.B * 255 + 0.5)
		end
		local shape = "Block"
		if props.Shape ~= nil and string.find(tostring(props.Shape), "Ball", 1, true) then
			shape = "Ball"
		elseif props.Shape ~= nil and string.find(tostring(props.Shape), "Cylinder", 1, true) then
			shape = "Cylinder"
		end
		-- **Substring search, not an anchored match.**
		--
		-- This read `string.match(m, "([%w]+)$")` -- the last run of word characters at the *end*
		-- of the string. The harness stringifies its enum stubs with punctuation after the name,
		-- so nothing ever matched and every part in the building baked as SmoothPlastic. Every
		-- concrete wall, wood bench, metal rail, glass pane and fabric banner has been plastic
		-- this whole time, which is most of why it looked unfinished no matter what was added.
		--
		-- Shape never had the bug because it searches for a substring, which is what this does
		-- now. Longest names first, so WoodPlanks is not swallowed by Wood and SmoothPlastic is
		-- not swallowed by Plastic.
		local material = "SmoothPlastic"
		if props.Material ~= nil then
			local m = tostring(props.Material)
			for _, name in ipairs(MATERIAL_NAMES) do
				if string.find(m, name, 1, true) ~= nil then
					material = name
					break
				end
			end
		end
		table.insert(rows, {
			name = tostring(props.Name or "Part"),
			x = px, y = py, z = pz,
			sx = sx, sy = sy, sz = sz,
			r = r, g = g, b = b,
			yaw = math.deg(num(cf.ry, 0)),
			roll = math.deg(num(cf.rz, 0)),
			-- Pitch, for anything tilted along its length -- a stair stringer, a ramp soffit.
			-- Zero for everything that does not ask, so no existing part moves.
			pitch = math.deg(num(cf.rx, 0)),
			shape = shape,
			material = material,
			transparency = num(props.Transparency, 0),
			reflectance = num(props.Reflectance, 0),
			collide = props.CanCollide == true,
		})
	else
		dropped += 1
	end
end

local out = {}
for _, row in ipairs(rows) do
	table.insert(out, string.format(
		'{"name":%q,"x":%.3f,"y":%.3f,"z":%.3f,"sx":%.3f,"sy":%.3f,"sz":%.3f,'
			.. '"r":%d,"g":%d,"b":%d,"yaw":%.2f,"roll":%.2f,"pitch":%.2f,"shape":%q,"material":%q,'
			.. '"transparency":%.3f,"reflectance":%.3f,"collide":%s}',
		row.name, row.x, row.y, row.z, row.sx, row.sy, row.sz,
		row.r, row.g, row.b, row.yaw, row.roll, row.pitch, row.shape, row.material,
		row.transparency, row.reflectance, tostring(row.collide)
	))
end
-- The room anchors, so the Python side can move the map's legacy school place points into
-- the rooms of the building that actually exists now. They are computed by laying the
-- building and live nowhere else, which is why they have to come out through here.
local plan = School.Plan()
local anchors = {}
if plan ~= nil then
	for id, pos in plan.rooms do
		table.insert(anchors, string.format('{"id":%q,"x":%.3f,"y":%.3f,"z":%.3f}', id, pos.X, pos.Y, pos.Z))
	end
end
print("SCHOOLANCHORS[" .. table.concat(anchors, ",") .. "]")
print("SCHOOLDROPPED[" .. tostring(dropped) .. "]")
print("SCHOOLJSON[" .. table.concat(out, ",") .. "]")
"""


def school_place_point() -> tuple[float, float, float]:
    """Where the map says the school goes.

    Read from Street.rbxmx rather than written down here, because the map moves: MAP_PLAN is
    explicit that place-point ids are stable and coordinates are not, so a literal in this
    file would be right until the next time Agent A regenerates the street.
    """
    import importlib.util
    from xml.etree import ElementTree as ET

    spec = importlib.util.spec_from_file_location("cc", ROOT / "tools" / "check_city.py")
    cc = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(cc)
    except SystemExit:
        pass

    for props in ET.parse(ROOT / "assets" / "Street.rbxmx").getroot().iter("Properties"):
        el = props.find("BinaryString[@name='AttributesSerialize']")
        if el is None or not el.text:
            continue
        try:
            attrs = cc.decode_attrs(el.text)
        except Exception:
            continue
        if attrs.get("PlaceId") == "school":
            cf = props.find("CoordinateFrame[@name='CFrame']")
            if cf is not None:
                return (float(cf.find("X").text), float(cf.find("Y").text), float(cf.find("Z").text))
    raise SystemExit('no "school" place point in assets/Street.rbxmx -- cannot place the bake')


def record() -> tuple[list[dict], list[dict]]:
    """Runs School.Build under the boot harness and returns the parts it laid."""
    roots = [ROOT / "src" / "server", ROOT / "src" / "shared", ROOT / "vendor"]
    paths = sorted(
        {p.relative_to(ROOT).as_posix() for r in roots if r.exists() for p in r.rglob("*.luau")}
    )
    lines = ["local AGES_SOURCES = {}", "local AGES_MANIFEST = {}", 'local AGES_PLACE = "game"']
    for rel in paths:
        lines.append(f"AGES_SOURCES[{_lua_string(rel)}] = {_lua_string((ROOT / rel).read_text(encoding='utf-8'))}")
        lines.append(f"table.insert(AGES_MANIFEST, {_lua_string(rel)})")
    px, py, pz = school_place_point()
    px, py, pz = px + COPY_OFFSET[0], py + COPY_OFFSET[1], pz + COPY_OFFSET[2]
    print(f"school place point: ({px:.1f}, {py:.1f}, {pz:.1f})")
    recorder = (RECORDER.replace("SCHOOL_X", repr(px))
                        .replace("SCHOOL_Y", repr(py))
                        .replace("SCHOOL_Z", repr(pz)))
    bundle = "\n".join(lines) + "\n" + (ROOT / "tools" / "bootcheck.luau").read_text(encoding="utf-8") + recorder

    SCRATCH.mkdir(exist_ok=True)
    script = SCRATCH / "gen_school.luau"
    script.write_text(bundle, encoding="utf-8")

    r = subprocess.run([str(LUAU), str(script)], capture_output=True, text=True, timeout=300)
    out = r.stdout + r.stderr
    marker = "SCHOOLJSON["
    if marker not in out:
        print("the recorder produced nothing. Tail of its output:")
        print(out[-2000:])
        raise SystemExit(1)
    def block(tag: str) -> list[dict]:
        if tag not in out:
            return []
        chunk = out[out.index(tag) + len(tag):]
        chunk = chunk[: chunk.index("]")]
        return json.loads("[" + chunk + "]") if chunk.strip() else []

    body = out[out.index(marker) + len(marker):]
    body = body[: body.rindex("]")]
    return json.loads("[" + body + "]"), block("SCHOOLANCHORS[")


# Roblox material names, as the recorder reads them off the part, to the numeric tokens an
# rbxmx file actually stores. `<token name="Material">SmoothPlastic</token>` is not a valid
# file -- the whole asset failed to parse on it, which is what "invalid digit found in string"
# meant. Anything not listed falls back to smooth plastic rather than crashing the bake: a
# wrong-looking surface is a note to add a mapping, a failed bake is a lost afternoon.
MATERIALS = {
    "Plastic": rbxmx.PLASTIC,
    "SmoothPlastic": rbxmx.SMOOTH,
    "Wood": rbxmx.WOOD,
    "WoodPlanks": rbxmx.PLANKS,
    "Fabric": rbxmx.FABRIC,
    "Metal": rbxmx.METAL,
    "DiamondPlate": rbxmx.DIAMOND_PLATE,
    "CorrodedMetal": rbxmx.CORRODED_METAL,
    "Neon": rbxmx.NEON,
    "Marble": rbxmx.MARBLE,
    "Concrete": rbxmx.CONCRETE,
    "Brick": rbxmx.BRICK,
    "Slate": rbxmx.SLATE,
    "Glass": rbxmx.GLASS,
    "Asphalt": rbxmx.ASPHALT,
    "Pavement": rbxmx.PAVEMENT,
    "Grass": rbxmx.GRASS,
    "LeafyGrass": rbxmx.LEAFY_GRASS,
    "Pebble": rbxmx.PEBBLE,
    "Cobblestone": rbxmx.COBBLESTONE,
    "Limestone": rbxmx.LIMESTONE,
    "Granite": rbxmx.GRANITE,
}

_unmapped: set[str] = set()


def material_token(name: str) -> int:
    if name not in MATERIALS:
        _unmapped.add(name)
    return MATERIALS.get(name, rbxmx.SMOOTH)


def emit(rows: list[dict]) -> None:
    rbxmx.begin("RBXSCHOOL")

    # Grouped by the prefix of each part's name, which is how School.luau already names things
    # (Wing1, Pediment3, LoungeSofa2...). One Model per family means the checker can tell parts
    # of one object from two objects sharing space, and means a room can be selected whole in
    # Studio rather than part by part.
    def family(name: str) -> str:
        head = "".join(c for c in name if not c.isdigit() and c != "_")
        return head or "Part"

    families: dict[str, list[dict]] = {}
    for row in rows:
        families.setdefault(family(row["name"]), []).append(row)

    lit = 0
    for label in sorted(families):
        with rbxmx.group(label):
            for row in families[label]:
                material = material_token(row["material"])
                center = (row["x"], row["y"], row["z"])
                size = (row["sx"], row["sy"], row["sz"])
                color = (row["r"], row["g"], row["b"])
                # Cylinders (rugs, plates) come out as flat boxes: rbxmx writes blocks and
                # balls, and a disc drawn as a square is a much smaller lie than a missing one.
                if row["shape"] == "Cylinder":
                    # Baked as a real cylinder rather than falling through to spun_box, which
                    # turned every disc in the building into a square. The roll is what lays it
                    # flat; see Kit.Rug and rbxmx.disc.
                    rbxmx.disc(
                        row["name"], center, size, row["yaw"], row.get("roll", 0),
                        color, material=material,
                        transparency=row["transparency"], reflectance=row.get("reflectance", 0.0), collide=row["collide"],
                    )
                elif row["shape"] == "Ball":
                    rbxmx.ball(
                        row["name"], center, size,
                        color, material=material,
                        transparency=row["transparency"], reflectance=row.get("reflectance", 0.0), collide=row["collide"],
                    )
                else:
                    # A real light on every Nth fitting. See LIGHTING in the module docstring
                    # for why it is a subset and not one per panel.
                    children = ""
                    if any(k in row["name"] for k in LIT_NAMES):
                        if lit % LIGHT_EVERY == 0:
                            children = rbxmx.point_light(
                                LIGHT_COLOR, LIGHT_BRIGHTNESS, LIGHT_RANGE, name="Light"
                            )
                        lit += 1
                    rbxmx.spun_box(
                        row["name"], center, size, row["yaw"],
                        color, material=material,
                        transparency=row["transparency"], reflectance=row.get("reflectance", 0.0), collide=row["collide"],
                        children=children,
                    )

    print(rbxmx.write(OUT, "SchoolV1Copy"))


# The map's own school, which this one replaces. Stripped from the assets rather than only
# hidden at runtime, because hiding happens when a server starts and the whole point of baking
# is to see the right building in Studio *before* anything runs.
#
# Named models only, and every one of them was checked to carry no attributes -- no place
# points, no event anchors, no interact tags. `Street.PlacePoints` is a sibling and is never
# touched, which is why `school` still resolves afterwards.
#
# Deliberately absent: City.RunningTrack, City.SoccerField, City.BoxingGym. Those carry
# FacilityKind and SportsDrillKind attributes that other systems read, so removing them would
# break a capability rather than replace one.
OLD_SCHOOL = {
    "Street.rbxmx": ("School", "SchoolFittings"),
    # City.SchoolFields / SchoolFieldsTrees / SchoolFieldsFittings are deliberately NOT here.
    # They are the sports ground rather than the school building, and thirteen wp_fields_*
    # waypoints stand on them -- removing them left every one of those hanging in mid-air,
    # which check_city caught. The building is replaced; the playing fields are not.
}


# The map's school carries three interior markers -- a classroom, a science lab and a
# cafeteria -- that point at rooms inside the building this one replaces. Deleting them is not
# an option: `classroom` is in Config.Places.Walkable, so content can offer to walk you there,
# and a destination that silently does nothing is worse than a wrong one.
#
# So they move into the equivalent rooms of the new school. Nothing else in the map is
# touched, and `school` and `wp_school_walk` are deliberately left where they are: the first
# is the anchor this whole building is laid around, and the second is a routing waypoint the
# path graph depends on.
RELOCATE = {
    "classroom": "english",
    "science_lab": "science",
    "cafeteria": "cafeteria",
}


def relocate_place_points(anchors: list[dict]) -> None:
    from xml.etree import ElementTree as ET
    import importlib.util

    spec = importlib.util.spec_from_file_location("cc2", ROOT / "tools" / "check_city.py")
    cc = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(cc)
    except SystemExit:
        pass

    by_id = {a["id"]: a for a in anchors}
    path = ROOT / "assets" / "Street.rbxmx"
    tree = ET.parse(path)
    moved = []
    for props in tree.getroot().iter("Properties"):
        el = props.find("BinaryString[@name='AttributesSerialize']")
        if el is None or not el.text:
            continue
        try:
            attrs = cc.decode_attrs(el.text)
        except Exception:
            continue
        pid = attrs.get("PlaceId")
        room = RELOCATE.get(pid)
        if room is None or room not in by_id:
            continue
        cf = props.find("CoordinateFrame[@name='CFrame']")
        if cf is None:
            continue
        a = by_id[room]
        cf.find("X").text = f"{a['x']:.4f}"
        # A hair above the room's floor, so the "ground within 0.15 under it" check sees the
        # slab rather than the point sitting exactly in its surface.
        cf.find("Y").text = f"{a['y'] + 0.1:.4f}"
        cf.find("Z").text = f"{a['z']:.4f}"
        moved.append(f"{pid} -> {room}")
    if moved:
        tree.write(path, encoding="unicode", xml_declaration=False)
        print("  " + ", ".join(moved))
    else:
        print("  nothing to move")


def strip_old_school() -> None:
    """Removes the map's own school from the generated assets.

    Re-run this after Agent A regenerates Street or City -- their generators write those
    models back, and this is a post-pass over their output rather than a change to it.
    """
    from xml.etree import ElementTree as ET

    for filename, names in OLD_SCHOOL.items():
        path = ROOT / "assets" / filename
        if not path.exists():
            print(f"  {filename}: not present, skipped")
            continue
        tree = ET.parse(path)
        root = tree.getroot()
        top = root.find("Item")
        if top is None:
            continue
        removed = []
        for child in list(top.findall("Item")):
            nm = child.find("Properties/string[@name='Name']")
            if nm is not None and nm.text in names:
                # Refuse to strip anything carrying attributes. If A ever puts a place point
                # inside the school model, this stops rather than silently deleting it.
                for props in child.iter("Properties"):
                    if props.find("BinaryString[@name='AttributesSerialize']") is not None:
                        raise SystemExit(
                            f"refusing to strip {filename}:{nm.text} -- it now carries "
                            f"attributes, which means something reads it. Re-check before removing."
                        )
                top.remove(child)
                removed.append(nm.text)
        if removed:
            tree.write(path, encoding="unicode", xml_declaration=False)
            print(f"  {filename}: removed {', '.join(removed)}")
        else:
            print(f"  {filename}: nothing to remove")


if __name__ == "__main__":
    if not LUAU.exists():
        raise SystemExit(f"luau missing at {LUAU} -- see CLAUDE.md for the toolchain")
    parts, anchors = record()
    print(f"recorded {len(parts)} parts from School.luau")
    emit(parts)
    if _unmapped:
        print("  materials with no token mapping (fell back to smooth plastic): "
              + ", ".join(sorted(_unmapped)))
    print("moving the map's school place points into the new rooms:")
    # The map's place points belong to v1. The copy is a sandbox and gets none.
    # relocate_place_points(anchors)
    print("stripping the map's own school:")
    strip_old_school()
