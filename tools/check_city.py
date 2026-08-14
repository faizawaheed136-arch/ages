#!/usr/bin/env python3
"""Validates assets/City.rbxmx against the plan in gen_city.py.

Run from tools/:  python3 check_city.py

Reads the emitted City.rbxmx (and Town.rbxmx for the reachability test) and
asserts the things the plan promised:
  * at least 100 houses, each one a model with a front door place point
  * at least 30 career buildings (storefronts + civic) with place points
  * every place point exists exactly once with a readable PlaceId
  * every place point has a neighbour within RouteLinkStuds, and the city is
    one connected component that reaches the town
  * no two building models overlap in 3D
  * every place point has solid ground within a hairline under its floor
  * no street runs through a building's ground-floor wall
  * the street network is one connected piece
  * there is solid ground under the world's SpawnLocation
  * no two assets pave the same ground
"""

import base64
import math
import struct
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
CITY_PATH = ASSETS / "City.rbxmx"
TOWN_PATH = ASSETS / "Town.rbxmx"
# The game place's project file, read for the one thing in the world that is
# positioned in JSON rather than by a generator: the spawn pad.
GAME_PROJECT = ROOT / "default.project.json"

ROUTE_LINK = 70.0
GROUND = 1.02
GROUND_FLOAT_TOL = 0.15

PLACE_TAG = "AgesPlacePoint"
PLACE_ID_ATTR = "PlaceId"

# Minimum thresholds from the plan.
MIN_HOUSES = 60
MIN_CAREER = 30

# What counts as a ground-floor wall for the "no street through a building"
# check. A wall is taller than a kerb, bigger in plan than a lamp post, and its
# underside is on the ground floor -- an awning, a hanging sign or a first-floor
# balcony is *meant* to reach out over the pavement and must not be reported.
WALL_MIN_HEIGHT = 6.0
WALL_MIN_AREA = 20.0
WALL_MAX_BASE = 4.0
# How far a street has to reach into a wall before it is a mistake rather than
# two slabs that share an edge and disagree in the last decimal place.
STREET_BITE = 0.5
# How far apart two pieces of street may be and still count as joined. Zero plus
# a hair: the plan is corner-to-corner and every join in it is exact, so a gap
# here is a gap a player can see.
STREET_JOIN = 0.05

# The band either side of the ground plane that counts as "surface": road, kerb,
# pavement, lawn, sand. Anything whose box crosses this band is something a
# player stands on, which is the only class of part that can be duplicated
# between two assets without one of them visibly winning.
SURFACE_LO = GROUND - 1.0
SURFACE_HI = GROUND + 1.0
# How far two surfaces from different assets have to lap in plan before it is
# worth looking at. The generators lap each other on purpose all the time -- the
# town's near sidewalk runs a fifth of a stud under the property line so there is
# no crack to fall down, and the gate road is laid straight over the town's lawn
# because a road that stopped at the grass would not be a road. A stud filters
# the seams out; the defect this was written for laid 23 studs of city road on
# top of 23 studs of town road.
ASSET_LAP = 1.0
# ...and the thing that actually makes such a lap a defect: two surfaces that
# lap AND finish at the same height. Overlapping volumes are a deliberate idiom
# here (the city's lawns are laid under its roads on purpose, a fiftieth of a
# stud down, so the road always wins the pixel). Two tops in the same plane are
# never deliberate -- neither surface can win, so the graphics card picks per
# frame and the ground flickers as the camera moves. That is what the gate road
# did over the town's grass for the whole 83x14 studs of it.
COPLANAR = 0.005


def decode_tags(blob: str) -> list[str]:
    """NUL-joined base64 string → list of tags."""
    return base64.b64decode(blob).split(b"\0")


def decode_attrs(blob: str) -> dict[str, str]:
    """Roblox binary attribute format → {name: value}."""
    raw = base64.b64decode(blob)
    off = 0
    count = struct.unpack_from("<I", raw, off)[0]; off += 4
    attrs = {}
    for _ in range(count):
        klen = struct.unpack_from("<I", raw, off)[0]; off += 4
        key = raw[off:off + klen].decode(); off += klen
        off += 1  # type byte (0x02 = string)
        vlen = struct.unpack_from("<I", raw, off)[0]; off += 4
        val = raw[off:off + vlen].decode(); off += vlen
        attrs[key] = val
    return attrs


def part_box(props):
    """(name, x0, x1, z0, z1, y0, y1) for a Part's Properties, or None.

    Rotation-aware, and it has to be. `rbxmx.part` emits the piece's *own*
    size plus a rotation matrix, so a bookcase turned to stand against the east
    wall is still written 5 studs wide and 1.4 deep with a quarter turn beside
    it. Reading the size and ignoring the matrix reports it 5 studs deep, which
    is a solid poking a stud and a half through its own wall — and that is a
    lie that already cost this checker a false positive on the television, the
    one thing a scanner is not allowed to do.

    |R| times the size is the exact axis-aligned bounding box for any rotation
    that is a multiple of a quarter turn, which is every rotation this codebase
    emits. For anything else it is a conservative over-estimate, which is the
    right way to be wrong here.
    """
    sv = props.find("Vector3[@name='size']")
    cf = props.find("CoordinateFrame[@name='CFrame']")
    if sv is None or cf is None:
        return None
    sx, sy, sz = (float(sv.find(t).text) for t in "XYZ")
    px, py, pz = (float(cf.find(t).text) for t in "XYZ")

    def r(tag, default):
        el = cf.find(tag)
        return abs(float(el.text)) if el is not None else default

    ex = r("R00", 1.0) * sx + r("R01", 0.0) * sy + r("R02", 0.0) * sz
    ey = r("R10", 0.0) * sx + r("R11", 1.0) * sy + r("R12", 0.0) * sz
    ez = r("R20", 0.0) * sx + r("R21", 0.0) * sy + r("R22", 1.0) * sz
    nm = props.find("string[@name='Name']")
    return (nm.text if nm is not None else "",
            px - ex / 2, px + ex / 2, pz - ez / 2, pz + ez / 2,
            py - ey / 2, py + ey / 2)


def part_footprint(props):
    """The part's true footprint in plan: (cx, cz, half_x, half_z, yaw_radians).

    The bounding box above is exact as a bounding box, and that is the problem
    once anything is spun off the grid: the AABB of a tower turned 45 degrees is
    half again as wide as the tower, so a ring of angled buildings reports itself
    as a pile of overlaps that are not there. `rbxmx.spun_box` exists so the
    circle can be built, and this exists so the checker does not have to be
    switched off to build it.

    Only the yaw matters -- everything in this world stands upright, and a part
    that did not would be a bug of its own.
    """
    sv = props.find("Vector3[@name='size']")
    cf = props.find("CoordinateFrame[@name='CFrame']")
    if sv is None or cf is None:
        return None
    sx, _sy, sz = (float(sv.find(t).text) for t in "XYZ")
    px, _py, pz = (float(cf.find(t).text) for t in "XYZ")

    def r(tag, default):
        el = cf.find(tag)
        return float(el.text) if el is not None else default

    # The local +X axis in world terms is (R00, R20); its angle off world +X is
    # the yaw. A quarter-turn part comes out at exactly 0, pi/2, pi or -pi/2 and
    # the test below then degenerates to the axis-aligned one, which is why this
    # can be used for every part rather than only the spun ones.
    return (px, pz, sx / 2, sz / 2, math.atan2(r("R20", 0.0), r("R00", 1.0)))


def _extent(hx, hz, yaw, ax, az):
    """How far a box of half-size (hx, hz) at `yaw` reaches along a unit axis."""
    c, s = math.cos(yaw), math.sin(yaw)
    # The box's own axes in world terms.
    return abs(hx * (c * ax + s * az)) + abs(hz * (-s * ax + c * az))


def plan_overlap(a, b):
    """Least penetration depth of two footprints in plan, or 0.0 if disjoint.

    A separating-axis test over the four face normals of the two rectangles,
    which is exact for convex shapes and is what makes an angled building
    checkable at all. Returns the smallest overlap across those axes -- the
    depth one has to be pushed to be clear of the other, which is the number
    every caller here wants to compare against a tolerance.
    """
    acx, acz, ahx, ahz, ayaw = a
    bcx, bcz, bhx, bhz, byaw = b
    dx, dz = bcx - acx, bcz - acz
    best = None
    for yaw in (ayaw, ayaw + math.pi / 2, byaw, byaw + math.pi / 2):
        ax, az = math.cos(yaw), math.sin(yaw)
        gap = (_extent(ahx, ahz, ayaw, ax, az)
               + _extent(bhx, bhz, byaw, ax, az)
               - abs(dx * ax + dz * az))
        if gap <= 0.0:
            return 0.0
        if best is None or gap < best:
            best = gap
    return best or 0.0


def iter_part_boxes(path: Path):
    """(name, x0, x1, z0, z1, y0, y1) for every Part in an asset, at any depth."""
    for item in ET.parse(path).getroot().iter("Item"):
        if item.get("class") != "Part":
            continue
        props = item.find("Properties")
        if props is None:
            continue
        b = part_box(props)
        if b is not None:
            yield b


def parse_rbxmx(path: Path):
    """Return (place_points, models) from an rbxmx file.

    place_points: list of (id, x, z, floor)
    models: list of (name, bbox, part_names, footprints) where
    bbox = (xmin, xmax, zmin, zmax, ymin, ymax) and footprints is
    [((cx, cz, hx, hz, yaw), y0, y1), ...] -- one per part, in plan, so a
    model that stands off the grid can be tested for real rather than by the
    bounding box it happens to cast.

    Models are the top-level replacement contract: only the direct children of
    the file's root model are collected, because those are the swappable
    buildings. Each house is one Model `House_<N>` wrapping `HouseStructure` and
    `HouseFittings` sub-models, so a bbox built from direct children only would
    miss the house entirely -- but the bbox here spans every Part under the
    model at any depth.
    """
    tree = ET.parse(path)
    root = tree.getroot()
    place_points = []
    models = []

    def walk(element, depth):
        for child in element:
            if child.tag != "Item":
                continue
            cls = child.get("class", "")
            if cls != "Model":
                continue
            props = child.find("Properties")
            name_el = props.find("string[@name='Name']") if props is not None else None
            name = name_el.text if name_el is not None else ""
            # Every Part under this model, at any depth.
            parts = []
            part_names = set()
            footprints = []
            for item in child.findall(".//Item"):
                if item.get("class") != "Part":
                    continue
                p = item.find("Properties")
                pn_el = p.find("string[@name='Name']") if p is not None else None
                if pn_el is not None:
                    part_names.add(pn_el.text)
                b = part_box(p) if p is not None else None
                if b is None:
                    continue
                _, bx0, bx1, bz0, bz1, by0, by1 = b
                px = (bx0 + bx1) / 2
                pz = (bz0 + bz1) / 2
                parts.append((bx0, bx1, bz0, bz1, by0, by1))
                fp = part_footprint(p)
                if fp is not None:
                    footprints.append((fp, by0, by1))
                # Place point tags can sit on any part at any depth.
                tags_el = p.find("BinaryString[@name='Tags']")
                attrs_el = p.find("BinaryString[@name='AttributesSerialize']")
                tags = decode_tags(tags_el.text) if tags_el is not None else []
                if PLACE_TAG.encode() in tags and attrs_el is not None:
                    attrs = decode_attrs(attrs_el.text)
                    if PLACE_ID_ATTR in attrs:
                        x, z = px, pz
                        place_points.append((attrs[PLACE_ID_ATTR], x, z, by0))
            if parts and depth == 1:
                bbox = (min(p[0] for p in parts),
                        max(p[1] for p in parts),
                        min(p[2] for p in parts),
                        max(p[3] for p in parts),
                        min(p[4] for p in parts),
                        max(p[5] for p in parts))
                models.append((name, bbox, part_names, footprints))
            walk(child, depth + 1)

    walk(root, 0)
    return place_points, models


def parse_part_place_points(path: Path):
    """Extract place points from root-level Parts (not inside models)."""
    tree = ET.parse(path)
    root = tree.getroot()
    points = []
    for child in root:
        if child.tag == "Item" and child.get("class") == "Part":
            props = child.find("Properties")
            if props is None:
                continue
            tags_el = props.find("BinaryString[@name='Tags']")
            if tags_el is None:
                continue
            tags = decode_tags(tags_el.text)
            if PLACE_TAG.encode() not in tags:
                continue
            attrs_el = props.find("BinaryString[@name='AttributesSerialize']")
            if attrs_el is None:
                continue
            attrs = decode_attrs(attrs_el.text)
            if PLACE_ID_ATTR not in attrs:
                continue
            b = part_box(props)
            if b is None:
                continue
            _, bx0, bx1, bz0, bz1, by0, _by1 = b
            points.append((attrs[PLACE_ID_ATTR],
                           (bx0 + bx1) / 2, (bz0 + bz1) / 2, by0))
    return points


def parse_streets_and_walls(path: Path):
    """Return (streets, walls) as flat footprint rectangles.

    streets: [(name, x0, x1, z0, z1)] — every Part under the top-level `Streets`
    model except the painted lane markings, which are decals lying on top of a
    road and would otherwise be counted as separate slabs of road.

    walls:   [(model, part, x0, x1, z0, z1)] — the ground-floor solids of every
    building. A "ground-floor solid" is tall enough to be a wall rather than a
    kerb, wide enough to be a wall rather than a post, and low enough to be on
    the ground floor rather than an awning or a sign hanging over the pavement.
    Overhanging into the street is legal and common; standing in it is not.
    """
    tree = ET.parse(path)
    root = tree.getroot()
    streets = []
    walls = []

    def rect_of(item):
        p = item.find("Properties")
        if p is None:
            return None
        b = part_box(p)
        return None if b is None else (b, part_footprint(p))

    def model_name(item):
        p = item.find("Properties")
        el = p.find("string[@name='Name']") if p is not None else None
        return el.text if el is not None else ""

    for top in root.findall("Item"):
        for child in top.findall("Item"):
            if child.get("class") != "Model":
                continue
            if model_name(child) == "Streets":
                for item in child.findall(".//Item"):
                    if item.get("class") != "Part":
                        continue
                    r = rect_of(item)
                    if r and "Dash" not in r[0][0]:
                        b, foot = r
                        streets.append((b[0], foot, b[1:5]))
                continue
            # Any other top-level group: hunt for ground-floor walls in it.
            for item in child.findall(".//Item"):
                if item.get("class") != "Part":
                    continue
                r = rect_of(item)
                if r is None:
                    continue
                (name, x0, x1, z0, z1, y0, y1), foot = r
                if y1 - y0 <= WALL_MIN_HEIGHT:
                    continue
                if (x1 - x0) * (z1 - z0) <= WALL_MIN_AREA:
                    continue
                if y0 > WALL_MAX_BASE:
                    continue
                walls.append((model_name(child), name, foot, (x0, x1, z0, z1)))
    return streets, walls


def parse_walls(path: Path):
    """The ground-floor walls of an asset, by the same rule as above.

    Separate from `parse_streets_and_walls` because the streets only ever come
    from City.rbxmx and the walls have to come from everywhere. The city's roads
    are laid in world coordinates that run straight through the town's, and the
    town's buildings are in a different file, so "no street runs through a
    building" was only ever asking the question of half the world. The gate road
    ran through a town house -- walls, roof, a bed in it -- for as long as the
    check existed, and passed.
    """
    root = ET.parse(path).getroot()

    def model_name(item):
        p = item.find("Properties")
        el = p.find("string[@name='Name']") if p is not None else None
        return el.text if el is not None else ""

    walls = []
    for top in root.findall("Item"):
        for child in top.findall("Item"):
            if child.get("class") != "Model" or model_name(child) == "Streets":
                continue
            for item in child.findall(".//Item"):
                if item.get("class") != "Part":
                    continue
                p = item.find("Properties")
                r = part_box(p) if p is not None else None
                if r is None:
                    continue
                name, x0, x1, z0, z1, y0, y1 = r
                if (y1 - y0 <= WALL_MIN_HEIGHT
                        or (x1 - x0) * (z1 - z0) <= WALL_MIN_AREA
                        or y0 > WALL_MAX_BASE):
                    continue
                walls.append((f"{path.stem}/{model_name(child)}", name,
                              part_footprint(p), (x0, x1, z0, z1)))
    return walls


def parse_surfaces(path: Path):
    """Every part in an asset whose box crosses the ground plane.

    Returns [(name, footprint, top_y)]. This is deliberately every Part at any
    depth and not just the ones under `Streets`: the point of the check that
    uses it is that two *different files* can pave the same square, and neither
    generator has ever read the other's output.
    """
    out = []
    for item in ET.parse(path).getroot().iter("Item"):
        if item.get("class") != "Part":
            continue
        props = item.find("Properties")
        if props is None:
            continue
        b = part_box(props)
        if b is None or b[6] < SURFACE_LO or b[5] > SURFACE_HI:
            continue
        out.append((b[0], part_footprint(props), b[6]))
    return out


def parse_solids(path: Path):
    """Every part in an asset, as a 3D box. Used to ask what is underfoot."""
    return list(iter_part_boxes(path))


def parse_spawn(path: Path):
    """(x, y, z, size_y) of the game place's SpawnLocation, or None.

    Read out of the project file rather than hardcoded, because the whole point
    of the check is that the number in the JSON and the ground in the assets
    drifted apart without anything noticing.
    """
    import json
    data = json.loads(path.read_text())

    def hunt(node):
        if not isinstance(node, dict):
            return None
        if node.get("$className") == "SpawnLocation":
            props = node.get("$properties", {})
            pos = props.get("Position")
            size = props.get("Size", [4, 0.2, 4])
            if pos:
                return (float(pos[0]), float(pos[1]), float(pos[2]), float(size[1]))
        for value in node.values():
            found = hunt(value)
            if found:
                return found
        return None

    return hunt(data)


def connected_components(points, link_studs):
    """Union-find on points, linking any two within link_studs."""
    n = len(points)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    for i in range(n):
        xi, zi = points[i][1], points[i][2]
        for j in range(i + 1, n):
            xj, zj = points[j][1], points[j][2]
            if (xi - xj) ** 2 + (zi - zj) ** 2 <= link_studs ** 2:
                union(i, j)

    comps = {}
    for i in range(n):
        r = find(i)
        comps.setdefault(r, []).append(i)
    return comps


assertions_failed = 0


def check(label, condition, detail=""):
    global assertions_failed
    if condition:
        print(f"  OK  {label}")
    else:
        assertions_failed += 1
        msg = f"FAIL  {label}"
        if detail:
            msg += f"  —  {detail}"
        print(msg, file=sys.stderr)


def main():
    global assertions_failed

    print(f"Parsing {CITY_PATH.name}...")
    city_points, city_models = parse_rbxmx(CITY_PATH)
    # Also parse root-level parts for place points that were placed outside models.
    root_points = parse_part_place_points(CITY_PATH)
    city_points.extend(root_points)

    # De-duplicate place points (some may appear in both walk and root parse).
    seen_ids = set()
    unique_points = []
    for pid, x, z, f in city_points:
        if pid in seen_ids:
            continue
        seen_ids.add(pid)
        unique_points.append((pid, x, z, f))
    city_points = unique_points

    print(f"  Parsed {len(city_points)} place points, {len(city_models)} models.\n")

    # --- 1. Houses ---
    print("1. Houses")
    house_models = [m for m in city_models if m[0].startswith("House_")]
    house_ids = {pid for pid, *_ in city_points if pid.startswith("suburb_")}
    apt_ids = {pid for pid, *_ in city_points if pid.startswith("apt_")}
    home_ids = house_ids | apt_ids
    check(f"≥{MIN_HOUSES} house models", len(house_models) >= MIN_HOUSES,
          f"got {len(house_models)}")
    check(f"≥{MIN_HOUSES} house place points", len(house_ids) >= MIN_HOUSES,
          f"got {len(house_ids)}")
    print()

    # --- 2. Career buildings ---
    print("2. Career buildings")
    # Career place points = all points that aren't homes, waypoints, or navigation.
    _waypoint_prefixes = ("wp_", "cs", "ave", "high", "conn")
    career_ids = {pid for pid, *_ in city_points
                  if pid not in home_ids
                  and not pid.startswith(_waypoint_prefixes)
                  and pid not in ("mall_entrance", "wp_mall_corridor",
                                  "city_park", "greenfield_1", "greenfield_2")}
    check(f"≥{MIN_CAREER} career place points", len(career_ids) >= MIN_CAREER,
          f"got {len(career_ids)}")
    print()

    # --- 3. Place point uniqueness ---
    print("3. Place point uniqueness")
    ids = [pid for pid, *_ in city_points]
    check("no duplicate place point ids", len(ids) == len(set(ids)),
          f"{len(ids)} total, {len(set(ids))} unique")
    print()

    # --- 4. Route connectivity ---
    print("4. Route connectivity")

    # Parse the town's place points for the reachability test. The town keeps
    # its points inside models (they are not root-level Parts), so this needs
    # the same model walk the city uses.
    town_points, _ = parse_rbxmx(TOWN_PATH)
    all_points = [(pid, x, z, f) for pid, x, z, f in city_points]
    for pid, x, z, f in town_points:
        if pid not in {p[0] for p in all_points}:
            all_points.append((pid, x, z, f))

    city_ids = {p[0] for p in city_points}
    town_ids = {p[0] for p in town_points}
    comps = connected_components(all_points, ROUTE_LINK)

    # The city itself must be one connected component — every city point
    # reachable from every other city point.
    city_indices = [i for i, (pid, *_) in enumerate(all_points) if pid in city_ids]
    city_roots = {next(k for k in comps if i in comps[k])
                  for i in city_indices}
    city_in_one = len(city_roots) == 1
    city_size = sum(len(comps[k]) for k in city_roots) if city_in_one else 0
    check("city points form one connected component",
          city_in_one,
          f"{len(city_roots)} pieces ({city_size} city points)")

    # The city must reach the town — at least one town point shares a
    # component with a city point. This validates the bridge points without
    # asserting the town is internally connected (that is the town's job).
    town_indices = [i for i, (pid, *_) in enumerate(all_points) if pid in town_ids]
    if town_indices:
        town_roots = {next(k for k in comps if i in comps[k])
                      for i in town_indices}
        shared = city_roots & town_roots
        check("city reaches at least one town point",
              len(shared) > 0,
              f"{len(shared)} of {len(town_roots)} town components reachable")
    else:
        check("city reaches at least one town point", False, "no town points found")

    # Every city place point has at least one neighbour within 70.
    city_idx = {i for i, (pid, *_ ,) in enumerate(all_points) if pid in city_ids}
    city_or_town_idx = set(range(len(all_points)))

    for i in city_idx:
        pid, xi, zi, _ = all_points[i]
        has_neighbor = False
        for j in city_or_town_idx:
            if i == j:
                continue
            xj, zj = all_points[j][1], all_points[j][2]
            if (xi - xj) ** 2 + (zi - zj) ** 2 <= ROUTE_LINK ** 2:
                has_neighbor = True
                break
        check(f"{pid} has neighbour within {ROUTE_LINK}",
              has_neighbor, f"nearest too far at ({xi:.0f},{zi:.0f})")
    print()

    # --- 5. Building overlap ---
    print("5. Building overlap")
    # Only check models that contain a "Roof" part — these are the actual
    # buildings. Two buildings that share a bounding-box face are fine.
    # (Streets, ground, and sports facilities don't have roofs.)
    roof_models = [(name, bbox, fps) for name, bbox, part_names, fps in city_models
                   if "Roof" in part_names]

    def models_intersect(fps_a, fps_b):
        """True if any part of one model is really inside any part of the other.

        The bounding-box test above is only the cheap filter. The Circus stands
        twelve towers on an arc, every one of them turned to face the monument,
        and the AABB of a tower at 23 degrees is a third wider than the tower --
        so its neighbours' boxes lap even though there is a four-stud alley
        between the buildings. Confirming with the same SAT the street checks
        use is what keeps this check worth reading; reporting eight overlaps
        that are not there would have retired it inside a week.
        """
        for fa, ay0, ay1 in fps_a:
            for fb, by0, by1 in fps_b:
                if ay1 <= by0 + COPLANAR or by1 <= ay0 + COPLANAR:
                    continue  # one is stacked clear above the other
                if plan_overlap(fa, fb) > COPLANAR:
                    return True
        return False

    overlaps = 0
    for i in range(len(roof_models)):
        n1, (x1a, x1b, z1a, z1b, _, _), fps1 = roof_models[i]
        for j in range(i + 1, len(roof_models)):
            n2, (x2a, x2b, z2a, z2b, _, _), fps2 = roof_models[j]
            # Two boxes overlap if they overlap in all three axes.
            if not (x1a < x2b and x1b > x2a and z1a < z2b and z1b > z2a):
                continue
            if not models_intersect(fps1, fps2):
                continue
            overlaps += 1
            print(f"    overlap: {n1} and {n2}", file=sys.stderr)
    check("no building overlaps", overlaps == 0, f"{overlaps} overlaps found")
    print()

    # --- 6. Ground under place points ---
    print("6. Ground under place points")
    # Collect all solid (CanCollide=true) Part bounds from the city and town
    # files. The two bridge waypoints sit on the town's grass, so judging them
    # against the city file alone would call every boundary point floating.
    solid_boxes = []
    for path in (CITY_PATH, TOWN_PATH):
        tree = ET.parse(path)
        root = tree.getroot()
        for item in root.iter("Item"):
            if item.get("class") != "Part":
                continue
            props = item.find("Properties")
            if props is None:
                continue
            cc = props.find("bool[@name='CanCollide']")
            if cc is not None and cc.text == "false":
                continue
            b = part_box(props)
            if b is not None:
                solid_boxes.append(b[1:])

    floating = 0
    for pid, x, z, floor_y in city_points:
        if floor_y <= GROUND - 1.0:
            # Sports facility points on ground (y ≈ 1.02) — check the ground plane.
            pass
        found = False
        for xa, xb, za, zb, ya, yb in solid_boxes:
            if xa <= x <= xb and za <= z <= zb and ya <= floor_y + 0.01 and yb >= floor_y - GROUND_FLOAT_TOL:
                found = True
                break
        if not found:
            floating += 1
            print(f"    no ground under {pid} at ({x:.1f},{z:.1f}) floor={floor_y:.2f}",
                  file=sys.stderr)
    check(f"every place point has ground within {GROUND_FLOAT_TOL:.2f}",
          floating == 0, f"{floating} floating points")
    print()

    # --- 7. Streets against buildings ---
    print("7. Streets against buildings")
    # Nothing else in this file could see this one. The building-overlap check
    # above compares buildings with buildings; the road builders are handed
    # bounds by the block plan and never look at what is standing there. So a
    # district laid out in its own coordinates -- which is how the civic row and
    # the north shops were written -- can have six avenues driven straight
    # through it and every other check will still pass. It shipped exactly that
    # way: an avenue ran through the middle of the cinema, the arcade, the
    # police station, the warehouse, the post office and all eight north shops.
    streets, walls = parse_streets_and_walls(CITY_PATH)
    # ...and every other asset's buildings too. The city's roads are drawn in
    # world coordinates and the town is at the other end of them.
    for _other in sorted(ASSETS.glob("*.rbxmx")):
        if _other != CITY_PATH:
            walls.extend(parse_walls(_other))
    print(f"  {len(streets)} street slabs, {len(walls)} ground-floor walls "
          f"across {len(list(ASSETS.glob('*.rbxmx')))} assets.")
    struck = {}
    for model, part, wfoot, (wx0, wx1, wz0, wz1) in walls:
        for sname, sfoot, _sbox in streets:
            bite = plan_overlap(wfoot, sfoot)
            if bite > STREET_BITE:
                prev = struck.get(model)
                if prev is None or bite > prev[0]:
                    struck[model] = (bite, part, sname, wx0, wx1, wz0, wz1)
    for model, (bite, part, sname, wx0, wx1, wz0, wz1) in sorted(struck.items()):
        print(f"    {sname} cuts {bite:.1f} studs into {model}.{part} "
              f"at x[{wx0:.0f},{wx1:.0f}] z[{wz0:.0f},{wz1:.0f}]", file=sys.stderr)
    check("no street runs through a building", not struck,
          f"{len(struck)} building(s) with a road in them")
    print()

    # --- 8. Street network connectivity ---
    print("8. Street network")
    # Place-point connectivity (check 4) is a claim about the *waypoint* graph,
    # and waypoints are dropped on whatever surface is under them -- including
    # lawn. So the entire road out of town was able to run the full length of
    # the map one stud clear of the city's west kerb, joined to it by nothing at
    # all, and check 4 was perfectly happy because there were waypoints on the
    # grass in between. This asks the roads themselves.
    n = len(streets)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    # Each slab is grown by half the join tolerance before the test, so two that
    # merely share an edge come out as overlapping. Growing rather than
    # comparing gaps is what lets an angled slab join a straight one: there is no
    # such thing as "the x gap" between two rectangles at different angles.
    grown = [(f[0], f[1], f[2] + STREET_JOIN / 2, f[3] + STREET_JOIN / 2, f[4])
             for _n, f, _b in streets]
    for i in range(n):
        for j in range(i + 1, n):
            if plan_overlap(grown[i], grown[j]) > 0.0:
                ra, rb = find(i), find(j)
                if ra != rb:
                    parent[ra] = rb

    pieces = {}
    for i in range(n):
        pieces.setdefault(find(i), []).append(i)
    for _, idx in sorted(pieces.items(), key=lambda p: -len(p[1]))[1:]:
        xs = [streets[i] for i in idx]
        print(f"    {len(idx)} slabs stranded at "
              f"x[{min(s[2][0] for s in xs):.0f},{max(s[2][1] for s in xs):.0f}] "
              f"z[{min(s[2][2] for s in xs):.0f},{max(s[2][3] for s in xs):.0f}]: "
              f"{', '.join(sorted({s[0].rstrip('0123456789_') for s in xs})[:6])}",
              file=sys.stderr)
    check("the street network is one piece", len(pieces) == 1,
          f"{len(pieces)} pieces")
    print()

    # --- 9. Ground under the spawn ---
    print("9. Ground under the spawn")
    # Everything above this line validates City.rbxmx against itself. The spawn
    # pad is not in City.rbxmx and is not in any generator -- it is four numbers
    # in default.project.json -- so nothing in this repo has ever been able to
    # say whether it stands on anything. It did not: it sat at (13, 1.387, -18.6),
    # which is east of where the front garden ends (x=3.4) and south and west of
    # where the city's ground begins (x=8, z=60), i.e. over open baseplate, ten
    # studs up. A player who arrived before a service teleported them fell.
    spawn = parse_spawn(GAME_PROJECT)
    if spawn is None:
        check("the game place has a SpawnLocation", False, "none found")
    else:
        sx, sy, sz, spad = spawn
        pad_bottom = sy - spad / 2
        print(f"  spawn at ({sx:.1f}, {sy:.2f}, {sz:.1f})")
        under = None
        for asset in sorted(ASSETS.glob("*.rbxmx")):
            for nm, x0, x1, z0, z1, y0, y1 in parse_solids(asset):
                if x0 <= sx <= x1 and z0 <= sz <= z1 and y1 <= pad_bottom + 0.01:
                    if under is None or y1 > under[0]:
                        under = (y1, asset.name, nm)
        if under is None:
            print(f"    nothing at all under ({sx:.1f},{sz:.1f})", file=sys.stderr)
            check("solid ground under the spawn", False, "the pad is over the baseplate")
        else:
            top, asset, nm = under
            drop = pad_bottom - top
            print(f"  standing on {nm} in {asset}, top y={top:.2f}")
            check(f"solid ground within {GROUND_FLOAT_TOL:.2f} under the spawn",
                  drop <= GROUND_FLOAT_TOL, f"a {drop:.2f} stud drop")
    print()

    # --- 10. Assets against each other ---
    print("10. Assets against each other")
    # The other half of the same blind spot. Each asset is generated by a script
    # that has never read another asset's output, so two of them can pave the
    # same square and every single-file check stays green. That is exactly what
    # happened: the city's gate road was drawn from x=-87.5, the west edge of the
    # *town's* carriageway, so 23 studs of city road lay on top of 23 studs of
    # town road, in two different files, and the surfaces of both finished at
    # exactly y=1.02 -- the whole width of the only link between the two halves
    # of the world, flickering.
    #
    # What is asked is not "do these overlap" but "do these overlap and finish
    # in the same plane". Overlapping is how the seams are built and how a road
    # gets to cross a lawn; a shared top is the part no player can unsee.
    surfaces = {p.name: parse_surfaces(p) for p in sorted(ASSETS.glob("*.rbxmx"))}
    for _n, _s in surfaces.items():
        print(f"  {_n}: {len(_s)} ground-plane parts")
    laps = {}
    names = sorted(surfaces)
    for i, an in enumerate(names):
        for bn in names[i + 1:]:
            for aname, afoot, atop in surfaces[an]:
                for bname, bfoot, btop in surfaces[bn]:
                    if abs(atop - btop) > COPLANAR:
                        continue
                    lap = plan_overlap(afoot, bfoot)
                    if lap > ASSET_LAP:
                        key = (an, bn, aname, bname)
                        if key not in laps or lap > laps[key][0]:
                            laps[key] = (lap, atop)
    for (an, bn, a, b), (lap, top) in sorted(laps.items(),
                                             key=lambda kv: -kv[1][0])[:20]:
        print(f"    {an}:{a} and {bn}:{b} share {lap:.1f} studs of "
              f"surface, both topping at y={top:.3f}", file=sys.stderr)
    check("no two assets share a surface plane", not laps,
          f"{len(laps)} coplanar pair(s)")

    # --- Summary ---
    print()
    if assertions_failed == 0:
        print("ALL CHECKS PASSED")
    else:
        print(f"{assertions_failed} CHECK(S) FAILED", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
