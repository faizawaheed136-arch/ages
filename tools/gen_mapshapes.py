#!/usr/bin/env python3
"""Turn the world's geometry into the picture the map draws.

Run from the repo root:

    python3 tools/gen_mapshapes.py

Writes ``src/shared/world/MapShapes.luau``. Re-run it whenever the world changes;
``tools/check.py`` fails if you forget, so a stale map cannot ship quietly.

**Why the map is drawn and not photographed.** The obvious way to put the town on a
sheet is to render it once and upload the picture. An uploaded image has to clear
moderation before it resolves, and until it does the map is a blank rectangle on
somebody else's machine -- the same silent-failure trade ``MenuIcons`` refuses for the
menu rail, and worse here, because a blank map looks like a map of nowhere rather than
like a missing asset. Frames always render.

**Why it is baked and not measured at runtime.** ``StreamingEnabled`` is on, so the
client only ever holds the geometry near the player and could not draw the far side of
the city if it wanted to. The server could walk the world and send the result, but it
would walk twelve thousand parts on every server start to produce a value that only
changes when an artist changes it. So it is computed here, once, and replicates as an
ordinary module.

**Why parts are classified by shape and not by name.** The city has 681 top-level
children with names like ``StepMewsLamp3``, ``FadePlazaPalms0_1`` and ``IronworksBillets2``.
A table mapping those to map layers would be wrong the first time anybody added a
building, and wrong *silently* -- the new building simply would not appear. But a map
only ever asks two questions about a lump of geometry, and both are answerable from its
dimensions:

  * *Is this a piece of ground?*  Flat, low, and wide enough to walk across. That is a
    road, a plaza, a lawn, a beach, the sea.
  * *Is this a building?*  A model whose parts together stand well above the ground and
    cover a real footprint.

Everything else -- lamps, benches, trees, lane markings, kerbs, bins -- fails both tests
on size alone and is dropped. A new building is picked up because it is building-shaped,
which is the only property that will still be true after somebody renames it.
"""

import hashlib
import json
import math
import os
import sys
import xml.etree.ElementTree as ET

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(REPO, "default.project.json")
OUTPUT = os.path.join(REPO, "src", "shared", "world", "MapShapes.luau")

# Roblox classes that are a solid lump of world. Anything else in the tree is a
# container, a script, a light or an attachment, and has no footprint to draw.
SOLID = {
    "Part",
    "WedgePart",
    "MeshPart",
    "UnionOperation",
    "TrussPart",
    "CornerWedgePart",
    "SpawnLocation",
}

# --- the two size tests, in studs -------------------------------------------------
#
# These are the whole classifier. They live here rather than in Config.luau because
# nothing at runtime reads them: they decide what goes *into* the generated file, and
# changing one means regenerating it. A copy in Config would be a number that looks
# tunable and is not.

# Taller than this and a flat thing is not ground -- it is a wall, a fence or a hoarding.
SURFACE_MAX_HEIGHT = 5.0
# A model reaching this high, with a real footprint under it, is a building.
BUILDING_MIN_HEIGHT = 7.0
BUILDING_MIN_FOOTPRINT = 90.0
# Above this a "building" is really a container model holding a whole district, so the
# walk descends into it instead. 45000 square studs is a 212-stud square: larger than any
# single structure in this world and far smaller than any of its neighbourhoods.
BUILDING_MAX_FOOTPRINT = 45000.0
# Anything smaller than this is scenery. The world is about two thousand studs across and
# the sheet is a few hundred pixels, so a three-stud kerb is well under one pixel -- it
# costs a Frame and draws nothing. This is what discards the two thousand lane dashes.
MIN_SIDE = 3.0
MIN_FOOTPRINT = 200.0
# Glass, water surfaces and marker volumes. Above this they are not really there.
MAX_TRANSPARENCY = 0.6


def properties(item):
    """Every property of an Item, as a dict. Vector-valued ones become dicts."""
    node = item.find("Properties")
    out = {}
    if node is None:
        return out
    for prop in node:
        name = prop.get("name")
        if len(prop):
            out[name] = {child.tag: child.text for child in prop}
        else:
            out[name] = prop.text
    return out


def footprint(props):
    """The top-down box of one solid part, or None if it has no geometry.

    Returns centre, width and depth in world studs, the yaw in degrees, the height of
    its top face, and its colour.
    """
    frame = props.get("CFrame")
    size = props.get("size")
    if not frame or not size:
        return None

    x, y, z = float(frame["X"]), float(frame["Y"]), float(frame["Z"])
    sx, sy, sz = float(size["X"]), float(size["Y"]), float(size["Z"])
    rot = [[float(frame[f"R{r}{c}"]) for c in range(3)] for r in range(3)]

    # R11 is how much of the part's own up axis still points up. Near 1 the part is
    # lying flat the way almost everything in this world does, and its footprint is
    # simply its X by its Z turned by the yaw. Below that it has been tipped over -- a
    # ramp, a leaning sign -- and there is no yaw that describes it, so the honest
    # answer is the world-aligned box that contains it.
    if abs(rot[1][1]) >= 0.95:
        yaw = math.degrees(math.atan2(rot[2][0], rot[0][0]))
        width, depth = sx, sz
        top = y + sy / 2
        height = sy
    else:
        half = (sx / 2, sy / 2, sz / 2)
        width = 2 * sum(abs(rot[0][i]) * half[i] for i in range(3))
        depth = 2 * sum(abs(rot[2][i]) * half[i] for i in range(3))
        rise = sum(abs(rot[1][i]) * half[i] for i in range(3))
        yaw = 0.0
        top = y + rise
        height = 2 * rise

    packed = props.get("Color3uint8")
    if packed:
        value = int(packed)
        color = ((value >> 16) & 255, (value >> 8) & 255, value & 255)
    else:
        color = (150, 150, 150)

    return {
        "x": x,
        "z": z,
        "w": width,
        "d": depth,
        "yaw": yaw,
        "top": top,
        "height": height,
        "color": color,
        "transparency": float(props.get("Transparency") or 0),
    }


def solids_under(item):
    """Every solid part at or below this item, flattened."""
    found = []
    stack = [item]
    while stack:
        node = stack.pop()
        if node.get("class") in SOLID:
            box = footprint(properties(node))
            if box is not None and box["transparency"] < MAX_TRANSPARENCY:
                found.append(box)
        else:
            stack.extend(node.findall("Item"))
    return found


def big_enough(width, depth):
    return min(width, depth) >= MIN_SIDE and width * depth >= MIN_FOOTPRINT


def collect(item, out):
    """Walk the tree, emitting one shape per piece of ground and one per building."""
    kind = item.get("class")

    if kind in SOLID:
        box = footprint(properties(item))
        if (
            box is not None
            and box["transparency"] < MAX_TRANSPARENCY
            and box["height"] <= SURFACE_MAX_HEIGHT
            and big_enough(box["w"], box["d"])
        ):
            box["kind"] = "surface"
            out.append(box)
        return

    parts = solids_under(item)
    if parts:
        left = min(p["x"] - p["w"] / 2 for p in parts)
        right = max(p["x"] + p["w"] / 2 for p in parts)
        near = min(p["z"] - p["d"] / 2 for p in parts)
        far = max(p["z"] + p["d"] / 2 for p in parts)
        width, depth = right - left, far - near
        top = max(p["top"] for p in parts)
        area = width * depth

        if (
            top >= BUILDING_MIN_HEIGHT
            and area >= BUILDING_MIN_FOOTPRINT
            and area <= BUILDING_MAX_FOOTPRINT
            and big_enough(width, depth)
        ):
            # The roof, which is what you would see from above: the highest part, and
            # among equally high ones the widest, so a chimney does not get to decide
            # what colour the house is.
            roof = max(parts, key=lambda p: (round(p["top"], 2), p["w"] * p["d"]))
            out.append(
                {
                    "x": (left + right) / 2,
                    "z": (near + far) / 2,
                    "w": width,
                    "d": depth,
                    # A building's footprint is the box around all of its parts, which
                    # is world-aligned by construction, so it has no yaw of its own.
                    "yaw": 0.0,
                    "top": top,
                    "color": roof["color"],
                    "kind": "building",
                }
            )
            return

    for child in item.findall("Item"):
        collect(child, out)


def mounted_assets():
    """Every .rbxmx the game place actually mounts into Workspace.

    Read out of the project file rather than globbed off disk, because an asset nothing
    mounts ships nowhere -- and a map that drew it would be a map of a place the player
    can never stand in.
    """
    with open(PROJECT) as handle:
        project = json.load(handle)

    found = []

    def walk(node):
        if not isinstance(node, dict):
            return
        path = node.get("$path")
        if isinstance(path, str) and path.endswith(".rbxmx"):
            found.append(path)
        for key, value in node.items():
            if not key.startswith("$"):
                walk(value)

    walk(project["tree"].get("Workspace", {}))
    return sorted(set(found))


def source_hash(assets):
    """A fingerprint of the exact bytes the generated map was built from.

    Written into `MapShapes.luau` and recomputed by `tools/check.py`, so that editing
    the town and forgetting to regenerate is a failed check rather than a map that
    quietly shows last week's streets. The asset *path* goes into the digest as well
    as its contents, because mounting the same geometry somewhere else moves it in the
    world and has to count as a change.
    """
    digest = hashlib.sha256()
    for relative in assets:
        with open(os.path.join(REPO, relative), "rb") as handle:
            digest.update(relative.encode())
            digest.update(hashlib.sha256(handle.read()).digest())
    return digest.hexdigest()[:16]


def main():
    assets = mounted_assets()
    if not assets:
        print("gen_mapshapes: default.project.json mounts no .rbxmx into Workspace.")
        return 1

    shapes = []
    for relative in assets:
        path = os.path.join(REPO, relative)
        if not os.path.exists(path):
            print(f"gen_mapshapes: {relative} is mounted but missing from disk.")
            return 1
        with open(path, "rb") as handle:
            raw = handle.read()

        root = ET.fromstring(raw)
        before = len(shapes)
        for item in root.findall("Item"):
            collect(item, shapes)
        print(f"  {relative}: {len(shapes) - before} shapes")

    if not shapes:
        print("gen_mapshapes: found no geometry. Refusing to write an empty map.")
        return 1

    # Painter's order, decided here so the client never sorts a thousand entries: ground
    # first from lowest to highest, then buildings, so a roof covers the floor slab under
    # it and a road covers the dirt it was laid on.
    shapes.sort(key=lambda s: (s["kind"] == "building", s["top"]))

    left = min(s["x"] - s["w"] / 2 for s in shapes)
    right = max(s["x"] + s["w"] / 2 for s in shapes)
    near = min(s["z"] - s["d"] / 2 for s in shapes)
    far = max(s["z"] + s["d"] / 2 for s in shapes)

    fingerprint = source_hash(assets)

    lines = []
    add = lines.append
    add("--!strict")
    add("-- The world, flattened into rectangles for the map to draw.")
    add("--")
    add("-- GENERATED by tools/gen_mapshapes.py. Do not edit by hand -- regenerate.")
    add("-- `tools/check.py` compares SourceHash against the mounted .rbxmx files and")
    add("-- fails if this file has fallen behind the world it describes.")
    add("--")
    add("-- Everything is in world studs, not in normalized map space, so this file does")
    add("-- not have to agree with whatever bounds the map happens to be drawn at. The")
    add("-- caller normalizes with `WorldMap.Normalize`, the same call the icons use.")
    add("--")
    add("-- Already in painter's order: ground from the bottom up, then buildings. Draw it")
    add("-- front to back and a roof lands on top of the floor it covers.")
    add("--")
    add("-- `rotationDegrees` is a yaw about the world's up axis, which is the only turn a")
    add("-- Frame can make. Parts tipped onto their side have no such angle, so they carry")
    add("-- the world-aligned box that contains them instead.")
    add("")
    add("export type Shape = {")
    add("\tx: number,")
    add("\tz: number,")
    add("\twidthStuds: number,")
    add("\tdepthStuds: number,")
    add("\trotationDegrees: number,")
    add("\t-- \"surface\" for ground you could walk on, \"building\" for something you could")
    add("\t-- walk into. The map tones the two differently; nothing else reads it.")
    add("\tkind: string,")
    add("\tcolor: Color3,")
    add("}")
    add("")
    add("local MapShapes = {}")
    add("")
    add(f'MapShapes.SourceHash = "{fingerprint}"')
    add("")
    add("-- The box the geometry actually occupies. Wider than the box the place points")
    add("-- measure, because a coastline has no doorway on it.")
    add("MapShapes.Extent = {")
    add(f"\tminX = {left:.1f},")
    add(f"\tmaxX = {right:.1f},")
    add(f"\tminZ = {near:.1f},")
    add(f"\tmaxZ = {far:.1f},")
    add("}")
    add("")
    # A `local` and then a field, rather than `MapShapes.All: { Shape } = {`. Luau only
    # allows a type annotation on a local declaration, and the field form is a parse error
    # -- one that costs the whole game, because a module that will not compile throws on
    # `require`, and TerritoryService requires this on the boot path. The first version of
    # this generator emitted the field form and took down both the server and the client.
    add(f"-- {len(shapes)} shapes.")
    add("local All: { Shape } = {")
    for s in shapes:
        r, g, b = s["color"]
        add(
            "\t{{ x = {x:.1f}, z = {z:.1f}, widthStuds = {w:.1f}, depthStuds = {d:.1f}, "
            "rotationDegrees = {yaw:.1f}, kind = \"{kind}\", "
            "color = Color3.fromRGB({r}, {g}, {b}) }},".format(
                x=s["x"], z=s["z"], w=s["w"], d=s["d"], yaw=s["yaw"], kind=s["kind"], r=r, g=g, b=b
            )
        )
    add("}")
    add("")
    add("MapShapes.All = All")
    add("")
    add("return MapShapes")
    add("")

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w") as handle:
        handle.write("\n".join(lines))

    surfaces = sum(1 for s in shapes if s["kind"] == "surface")
    print(
        f"wrote {os.path.relpath(OUTPUT, REPO)}: {len(shapes)} shapes "
        f"({surfaces} ground, {len(shapes) - surfaces} buildings), hash {fingerprint}"
    )
    print(f"  extent X {left:.0f}..{right:.0f}  Z {near:.0f}..{far:.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
