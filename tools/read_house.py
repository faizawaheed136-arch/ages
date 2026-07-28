#!/usr/bin/env python3
"""Reads the house and checks the furniture standing in it.

This is the debug path for the building. Furniture is generated blind — the
generator does arithmetic against numbers in house_plan.py and never looks at
assets/House.rbxmx — so something has to open the actual model and confirm the
result is a room and not a lawn. An early pass shipped a kitchen outdoors and a
sofa that sealed a doorway; both would have been caught here.

    python3 tools/read_house.py plan     what the house is made of
    python3 tools/read_house.py check    is the furniture where it should be
    python3 tools/read_house.py spawn    where the toddler can start

`check` exits non-zero when anything is wrong, so it can gate a commit.
"""

import json
import math
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

import house_plan
from house_plan import EVENT_ANCHOR, FURNITURE, HOUSE, INTERACT_RADIUS, KEEP_CLEAR, ROOMS

PROJECT = Path(__file__).resolve().parent.parent / "default.project.json"

# Anything thinner than this in every axis is trim, glazing or a fixing rather
# than something a body would walk into.
_SOLID_MIN_THICKNESS = 0.4
# How far two boxes have to interpenetrate before it reads as a mistake instead
# of parts of one piece of furniture sharing a seam.
_CLIP_TOLERANCE = 0.3


_SOLID_CLASSES = {"Part", "MeshPart", "UnionOperation", "WedgePart", "TrussPart"}
_GROUPING_CLASSES = {"Model", "Folder"}


def _number(node, tag):
    found = node.find(tag) if node is not None else None
    return float(found.text) if found is not None and found.text else 0.0


def _named(props, tag, name):
    """A property element by its XML tag and Roblox property name."""
    if props is None:
        return None
    for child in props.findall(tag):
        if child.get("name") == name:
            return child
    return None


def load(path):
    """Every part in a .rbxmx, as an axis-aligned box in world space.

    Roblox stores a rotation matrix, not a bounding box, so the extent along
    each world axis is the size projected through that matrix — which is what
    lets a piece turned to face a different wall still be checked against the
    wall it is now nearest.

    Each box also carries the Model it sits in. That is the difference between
    a sink recessed into a counter and a plant standing inside a sofa: the
    geometry is identical, only the grouping says which one is a mistake.
    """
    parts = []

    def walk(node, group):
        for item in node.findall("Item"):
            cls = item.get("class")
            props = item.find("Properties")
            name_node = _named(props, "string", "Name")
            name = name_node.text if name_node is not None and name_node.text else "?"

            if cls in _SOLID_CLASSES:
                cframe = _named(props, "CoordinateFrame", "CFrame")
                size = _named(props, "Vector3", "size") or _named(props, "Vector3", "Size")
                if cframe is not None and size is not None:
                    px, py, pz = (_number(cframe, axis) for axis in ("X", "Y", "Z"))
                    rot = [[_number(cframe, "R%d%d" % (i, j)) for j in range(3)] for i in range(3)]
                    half = [_number(size, axis) / 2 for axis in ("X", "Y", "Z")]
                    ext = [sum(abs(rot[i][j]) * half[j] for j in range(3)) for i in range(3)]
                    parts.append(
                        dict(
                            cls=cls, name=name, group=group, p=(px, py, pz), ext=ext,
                            x0=px - ext[0], x1=px + ext[0],
                            y0=py - ext[1], y1=py + ext[1],
                            z0=pz - ext[2], z1=pz + ext[2],
                        )
                    )

            # The innermost enclosing Model wins, so a piece inside the root
            # Furniture model reports as the piece and not as "Furniture".
            walk(item, name if cls in _GROUPING_CLASSES else group)

    walk(ET.parse(path).getroot(), "")
    return parts


def overlap(a, b):
    """Interpenetration of two boxes on each axis. Negative on any axis means
    they are apart."""
    return (
        min(a["x1"], b["x1"]) - max(a["x0"], b["x0"]),
        min(a["y1"], b["y1"]) - max(a["y0"], b["y0"]),
        min(a["z1"], b["z1"]) - max(a["z0"], b["z0"]),
    )


def footprints_overlap(box, rect, tolerance=0.15):
    """Whether a part's footprint intrudes on an (x0, x1, z0, z1) rectangle."""
    x0, x1, z0, z1 = rect
    return (
        box["x1"] > x0 + tolerance
        and box["x0"] < x1 - tolerance
        and box["z1"] > z0 + tolerance
        and box["z0"] < z1 - tolerance
    )


def room_of(box):
    for room in ROOMS:
        if room.contains(box["x0"], box["x1"], box["z0"], box["z1"], box["y0"]):
            return room
    return None


# ---------------------------------------------------------------------------
# plan
# ---------------------------------------------------------------------------

def command_plan():
    house = load(HOUSE)
    print("%s: %d parts" % (HOUSE.name, len(house)))

    by_class = defaultdict(int)
    for part in house:
        by_class[part["cls"]] += 1
    print("  " + ", ".join("%s x%d" % (k, v) for k, v in sorted(by_class.items())))

    # Floor levels show up as horizontal surface area piling up at one height.
    # This is how the second storey was found after a first pass furnished only
    # the ground floor.
    area_at = defaultdict(float)
    for part in house:
        if part["ext"][1] * 2 < 3 and part["ext"][0] * part["ext"][2] > 5:
            area_at[round(part["y1"], 1)] += part["ext"][0] * part["ext"][2] * 4
    print("\nhorizontal surface area by height (candidate floor levels):")
    for y, area in sorted(area_at.items(), key=lambda kv: -kv[1])[:8]:
        print("   y=%6.2f   %8.0f sq studs" % (y, area))

    print("\nrooms transcribed in house_plan.py:")
    for room in ROOMS:
        print(
            "   %-16s x[%6.1f,%6.1f] z[%6.1f,%6.1f]  floor %6.3f  ceiling %5.1f  (%.0f x %.0f)"
            % (room.name, room.x0, room.x1, room.z0, room.z1, room.floor, room.ceiling,
               room.x1 - room.x0, room.z1 - room.z0)
        )

    # Glazing and doors are why half the furniture is not where it would
    # otherwise obviously go, so they get printed with the room they belong to.
    print("\nglazing and doors found in the house:")
    openings = [p for p in house if "curtain" in p["name"].lower() or "door" in p["name"].lower()]
    for part in sorted(openings, key=lambda p: (p["p"][1], p["p"][0])):
        room = room_of(part)
        print(
            "   %-18s x[%6.1f,%6.1f] z[%6.1f,%6.1f] y[%5.1f,%5.1f]  %s"
            % (part["name"], part["x0"], part["x1"], part["z0"], part["z1"],
               part["y0"], part["y1"], room.name if room else "-")
        )

    print("\nkeep-clear footprints:")
    for name, (x0, x1, z0, z1) in KEEP_CLEAR.items():
        print("   %-18s x[%6.1f,%6.1f] z[%6.1f,%6.1f]" % (name, x0, x1, z0, z1))


# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------

def command_check():
    house = load(HOUSE)
    furniture = load(FURNITURE)
    failures = []

    def report(title, rows):
        print("%-42s %s" % (title + ":", len(rows) if rows else "clean"))
        for row in rows[:12]:
            print("      " + row)
        if len(rows) > 12:
            print("      ... and %d more" % (len(rows) - 12))
        if rows:
            failures.append(title)

    # Which room each piece is in, and the pieces that are in none of them.
    homeless, sunken = [], []
    home = {}
    for part in furniture:
        room = room_of(part)
        home[id(part)] = room
        if room is None:
            homeless.append(
                "%-20s x[%6.1f,%6.1f] z[%6.1f,%6.1f]"
                % (part["name"], part["x0"], part["x1"], part["z0"], part["z1"])
            )
        elif part["y0"] < room.floor - _CLIP_TOLERANCE:
            sunken.append(
                "%-20s in %-16s underside %.2f, floor %.2f"
                % (part["name"], room.name, part["y0"], room.floor)
            )
    report("furniture outside every room", homeless)
    report("furniture sunk below its floor", sunken)

    blocking = set()
    for part in furniture:
        room = home[id(part)]
        # Only things standing on the floor block a route; a pendant hanging in
        # a stairwell at ceiling height does not.
        if room and part["y0"] > room.floor + 6.0:
            continue
        for name, rect in KEEP_CLEAR.items():
            if footprints_overlap(part, rect):
                blocking.add("%-18s blocked by %s" % (name, part["name"]))
    report("routes blocked", sorted(blocking))

    solids = [p for p in house if p["ext"][1] * 2 > _SOLID_MIN_THICKNESS]
    clipping = defaultdict(float)
    for part in furniture:
        for solid in solids:
            dx, dy, dz = overlap(part, solid)
            if min(dx, dy, dz) > _CLIP_TOLERANCE:
                clipping[(part["name"], solid["name"])] = max(
                    clipping[(part["name"], solid["name"])], min(dx, dy, dz)
                )
    report(
        "furniture clipping the house",
        ["%-20s into %-20s by %.2f" % (a, b, v)
         for (a, b), v in sorted(clipping.items(), key=lambda kv: -kv[1])],
    )

    # Furniture against furniture. Parts within one piece are meant to share
    # space — a drawer sits in a dresser, a sink sits in a counter — so only
    # overlaps between two different pieces are mistakes.
    collisions = {}
    for i, a in enumerate(furniture):
        for b in furniture[i + 1:]:
            if a["group"] == b["group"]:
                continue
            dx, dy, dz = overlap(a, b)
            depth = min(dx, dy, dz)
            if depth <= _CLIP_TOLERANCE:
                continue
            key = ("%s/%s" % (a["group"], a["name"]), "%s/%s" % (b["group"], b["name"]))
            collisions[key] = max(collisions.get(key, 0.0), depth)
    report(
        "furniture inside other furniture",
        ["%-26s and %-26s by %.2f" % (a, b, v)
         for (a, b), v in sorted(collisions.items(), key=lambda kv: -kv[1])],
    )

    counts = defaultdict(int)
    for part in furniture:
        room = home[id(part)]
        counts[room.name if room else "nowhere"] += 1
    print("\n%d parts placed:" % len(furniture))
    for room in ROOMS:
        print("   %-16s %3d" % (room.name, counts[room.name]))

    anchors = [p for p in furniture if p["name"] == "RugEventAnchor"]
    print("\nevent anchors: %d" % len(anchors))
    for part in anchors:
        print("   at (%.1f, %.1f)" % (part["p"][0], part["p"][2]))
    if not anchors:
        failures.append("no event anchor")

    if failures:
        print("\nFAILED: " + ", ".join(failures))
        return 1
    print("\nOK")
    return 0


# ---------------------------------------------------------------------------
# spawn
# ---------------------------------------------------------------------------

def _clearance_field(level_y):
    """Obstacles and standable floor at one storey, as flat rectangles.

    Only geometry in the band a body occupies counts: the floor underfoot and
    the roof overhead are not obstacles, but a sofa is.
    """
    parts = load(HOUSE) + [p for p in load(FURNITURE) if p["name"] != "RugEventAnchor"]
    obstacles = [
        (p["x0"], p["x1"], p["z0"], p["z1"])
        for p in parts
        if p["y0"] < level_y + 3.0 and p["y1"] > level_y + 0.3
    ]
    floors = [
        (p["x0"], p["x1"], p["z0"], p["z1"])
        for p in load(HOUSE)
        if abs(p["y1"] - level_y) < 0.6 and p["ext"][0] * p["ext"][2] > 20 and p["ext"][1] < 3
    ]
    return obstacles, floors


def command_spawn():
    room = house_plan.A
    obstacles, floors = _clearance_field(room.floor)
    ax, az = EVENT_ANCHOR

    def clearance(x, z):
        best = 99.0
        for x0, x1, z0, z1 in obstacles:
            dx = max(x0 - x, 0.0, x - x1)
            dz = max(z0 - z, 0.0, z - z1)
            best = min(best, math.hypot(dx, dz))
        return best

    def standable(x, z):
        return any(x0 <= x <= x1 and z0 <= z <= z1 for x0, x1, z0, z1 in floors)

    def path_clear(x, z, width=1.1):
        """Walk the straight line to the anchor and make sure a body fits the
        whole way. Clearance at the spawn alone is not enough — the point of
        the spawn is the crawl, and the crawl has to be possible."""
        distance = math.hypot(ax - x, az - z)
        steps = max(int(distance * 2), 1)
        for i in range(steps + 1):
            t = i / steps
            px, pz = x + (ax - x) * t, z + (az - z) * t
            if math.hypot(px - ax, pz - az) <= INTERACT_RADIUS:
                break
            if clearance(px, pz) < width:
                return False
        return True

    project = json.loads(PROJECT.read_text())
    current = project["tree"]["Workspace"]["SpawnLocation"]["$properties"]["Position"]
    cx, cz = current[0], current[2]
    crawl = math.hypot(cx - ax, cz - az) - INTERACT_RADIUS
    print("spawn in default.project.json: (%.1f, %.1f)" % (cx, cz))
    print("   clearance %.2f studs" % clearance(cx, cz))
    print("   standable: %s" % ("yes" if standable(cx, cz) else "NO — not over a floor"))
    print("   crawl to the anchor: %.1f studs before it fires" % crawl)
    print("   path to the anchor: %s" % ("clear" if path_clear(cx, cz) else "BLOCKED"))

    print("\nalternatives in %s (clearance, crawl, position):" % room.name)
    candidates = []
    x = room.x0 + 1.0
    while x < room.x1 - 1.0:
        z = room.z0 + 1.0
        while z < room.z1 - 1.0:
            if standable(x, z):
                c = clearance(x, z)
                d = math.hypot(x - ax, z - az) - INTERACT_RADIUS
                if c >= 2.6 and 9.0 <= d <= 15.0 and path_clear(x, z):
                    candidates.append((c, d, x, z))
            z += 0.25
        x += 0.25
    candidates.sort(key=lambda t: (-t[0], -t[1]))
    if not candidates:
        print("   none — no spot has 2.6 studs of clearance and a 9-15 stud crawl")
    for c, d, x, z in candidates[:10]:
        print("   clearance %.2f  crawl %5.1f studs  at (%.1f, %.1f)" % (c, d, x, z))
    return 0


# ---------------------------------------------------------------------------
# space
# ---------------------------------------------------------------------------

# Resolution of the floor sampling grid, in studs. Half a stud is finer than any
# gap that matters and still cheap to sweep.
_GRID = 0.5
# Half the width of a body, in studs. Open floor narrower than this on both
# sides cannot actually be walked through, so it does not count as space.
_BODY_RADIUS = 1.4
# How much of a room's walkable floor has to be in one connected piece. Short of
# this the room has a pocket you can see but not reach, which is what a sofa
# spanning a room does — and what raw floor area completely fails to notice.
_MIN_REACHABLE = 0.97


def command_space():
    """How much of each room you can actually walk, and what is taking it up.

    `check` only proves nothing overlaps. A room can pass that and still be
    miserable, so this measures the two things you feel: how much floor is left,
    and whether that floor is one connected space or several pockets separated
    by furniture you cannot squeeze past.

    Floor area alone is the wrong target — a bedroom is mostly bed and a galley
    kitchen is mostly counter, and neither is a problem. Reachability is the
    part that actually breaks a room.
    """
    furniture = load(FURNITURE)
    problems = 0

    for room in ROOMS:
        # Only things at body height take space away. A rug is floor you can
        # walk on and a pendant is over your head; neither crowds the room.
        standing = [
            p for p in furniture
            if room.contains(p["x0"], p["x1"], p["z0"], p["z1"], p["y0"])
            and p["y1"] > room.floor + 0.4
            and p["y0"] < room.floor + 4.0
        ]

        nx = max(int((room.x1 - room.x0) / _GRID), 1)
        nz = max(int((room.z1 - room.z0) / _GRID), 1)
        solid = [[False] * nz for _ in range(nx)]
        for ix in range(nx):
            x = room.x0 + (ix + 0.5) * _GRID
            for iz in range(nz):
                z = room.z0 + (iz + 0.5) * _GRID
                solid[ix][iz] = any(
                    p["x0"] <= x <= p["x1"] and p["z0"] <= z <= p["z1"] for p in standing
                )

        open_cells = sum(1 for ix in range(nx) for iz in range(nz) if not solid[ix][iz])
        clear = open_cells / (nx * nz)

        # Erode by a body's width. What survives is floor you can stand on
        # without clipping a wall or a wardrobe.
        reach = int(math.ceil(_BODY_RADIUS / _GRID))
        walkable = set()
        for ix in range(nx):
            for iz in range(nz):
                if solid[ix][iz]:
                    continue
                # Outside the grid counts as solid: that is the room's wall.
                if ix < reach or iz < reach or ix >= nx - reach or iz >= nz - reach:
                    continue
                if all(
                    not solid[ix + dx][iz + dz]
                    for dx in range(-reach, reach + 1)
                    for dz in range(-reach, reach + 1)
                ):
                    walkable.add((ix, iz))

        # Flood fill the walkable floor. More than one region means somewhere in
        # this room is cut off from somewhere else in it.
        seen, regions = set(), []
        for start in walkable:
            if start in seen:
                continue
            stack, region = [start], 0
            seen.add(start)
            while stack:
                cx, cz = stack.pop()
                region += 1
                for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nxt = (cx + dx, cz + dz)
                    if nxt in walkable and nxt not in seen:
                        seen.add(nxt)
                        stack.append(nxt)
            regions.append(region)
        regions.sort(reverse=True)
        reachable = regions[0] / len(walkable) if walkable else 0.0

        footprint = defaultdict(float)
        for p in standing:
            footprint[p["group"]] = max(
                footprint[p["group"]],
                (p["x1"] - p["x0"]) * (p["z1"] - p["z0"]),
            )

        broken = not walkable or reachable < _MIN_REACHABLE
        problems += broken
        print(
            "%-16s %5.0f sq studs   %3.0f%% clear   walkable in %d piece%s%s"
            % (
                room.name,
                (room.x1 - room.x0) * (room.z1 - room.z0),
                clear * 100,
                len(regions),
                "" if len(regions) == 1 else "s",
                "   <- SPLIT" if broken else "",
            )
        )
        pieces = sorted(footprint.items(), key=lambda kv: -kv[1])
        print("      %d pieces: %s" % (
            len(pieces),
            ", ".join("%s %.0f" % (n, a) for n, a in pieces[:10]) or "none",
        ))

    print(
        "\n%d room(s) with floor you cannot walk between (body width %.1f studs)"
        % (problems, _BODY_RADIUS * 2)
    )
    return 1 if problems else 0


COMMANDS = {
    "plan": command_plan,
    "check": command_check,
    "spawn": command_spawn,
    "space": command_space,
}

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "check"
    if which not in COMMANDS:
        print(__doc__)
        sys.exit(2)
    sys.exit(COMMANDS[which]() or 0)
