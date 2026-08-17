#!/usr/bin/env python3
"""Validates the town half of the world -- Town.rbxmx, Street.rbxmx and what
stands in them -- the way check_city.py validates the city.

Run from the repo root:  python3 tools/check_town.py

**Why this exists as a second file rather than as more checks in check_city.py.**
Almost every check over there is scoped to the city by construction, and the
scoping is invisible in the check's own name. "Ground under place points" walks
`city_points`. "Building overlap" walks `city_models`. "Streets against
buildings" is the one that was widened -- it tests the city's roads against
*every* asset's walls, because the gate road once ran through a town house and
passed -- and widening it is what showed that the others had the same shape of
hole. So the town has been carrying twelve green checks that were never asking
about the town at all.

Two defects were sitting in it when this file was first run, and neither was
findable any other way:

  * the bakery's place point stood *inside* the bakery counter, a 10x10 solid.
    The game's instruction is "the bakery, at the counter" and the spot it names
    is four studs inside it.
  * three of the four return-road waypoints were declared at pavement height
    while standing on the carriageway, floating half a stud. The fourth was
    right, which is what a copy-paste that got fixed once looks like.

What it does *not* check, and why, is as much a part of the file as what it
does -- see the note above check 6 on the town's road network, which is a
question that does not transfer from the city and should not be faked.

The readers and the geometry come from check_city rather than being copied.
A second rotation-aware rbxmx reader is two copies of one measurement, which is
the defect this tree has been repaired for more often than any other.
"""

import math
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_city import (  # noqa: E402
    ASSETS, COPLANAR, GROUND_FLOAT_TOL, PLACE_ID_ATTR, PLACE_TAG, STREET_BITE,
    WALL_MAX_BASE, WALL_MIN_AREA, WALL_MIN_HEIGHT,
    decode_attrs, decode_tags, part_box, part_footprint, plan_overlap,
)

# The two files the town is generated into, in the order a reader meets them:
# `gen_town.py` writes the town, `build_street.py` writes the player's street.
TOWN_ASSETS = ("Town", "Street")
# ...and everything else a body in the town can walk into. The city is in here
# because the town's east edge is a seam, not a wall, and a place point near it
# is standing in whatever the *city* put there. The furniture files are here
# because a place point inside a wardrobe is the same defect as one inside a
# counter and there is no reason to be able to see only one of them.
SOLID_ASSETS = TOWN_ASSETS + ("House", "Furniture", "SchoolFurniture", "City")

# Groups that are the world rather than things standing in it. Named rather
# than inferred: the list is short, it changes about once a year, and a rule
# that guessed would quietly start skipping a building the day somebody added
# one with an unusual name.
SURFACE_GROUPS = {"Ground", "Road", "Sidewalks", "Crossing", "Forecourts",
                  "FrontPath", "PlacePoints", "StreetFurniture", "StreetSign",
                  "Fence", "Park"}

# A building is a group with a roof on it -- the same rule check_city's overlap
# check uses. It is not a guess about what a building is: a shell is emitted
# with a Roof and nothing else in this world is, so scrap heaps, hedges and
# depot stacks cannot get in by being wall-shaped.
ROOF_PART = "Roof"

# --- check 3, room to stand ------------------------------------------------
#
# The band a body occupies, measured from the floor the place point declares.
#
# STAND_STEP is where the band starts, and it is the whole reason this check
# reports anything worth reading. A Roblox humanoid walks over what is below its
# hip without noticing, so a band starting at the floor reports every rug,
# doorstep, kerb and book in the game and the real find drowns in them. Two
# studs is the default HipHeight; below it, it is not an obstruction.
STAND_STEP = 2.0
# ...and where it stops. Five studs is a little over head height for R15, which
# is the part of a body that has to fit between two solids.
STAND_HEAD = 5.0
# How much room a standing body needs around the point, as a radius.
#
# Derived, not chosen: HumanoidRootPart is two studs wide, so half of it is one.
# The measurement confirms the margin rather than setting it -- across the 50
# town place points the worst honest clearance is 1.51 (the `home` point beside
# the spawn house's own wall) and the next is 2.00, while the defect this was
# written for measures as *inside* a solid. Safe range 0.8-1.4: under 0.8 a
# point half-buried in a wall stops reporting, over 1.4 the honest 1.51 does.
STAND_CLEAR = 1.0

# A place point counts as belonging to a building if it lands inside the
# building's walls or this far outside them -- a door is drawn in the wall line
# and the point that names it is stood just clear of it.
DOOR_SLACK = 4.0

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


def top_groups(path: Path):
    """{group: [(part_name, footprint, box)]} for a file's top-level groups.

    The town's files are one root Model holding a flat row of named groups --
    Ground, Road, Bakery, House14 -- so the group *is* the unit of meaning here,
    where in the city it is the model. Reading it that way is what lets the
    checks below say "the bakery" instead of "a part at these coordinates".
    """
    out = {}
    root = ET.parse(path).getroot()
    for top in root.findall("Item"):
        for grp in top.findall("Item"):
            props = grp.find("Properties")
            name_el = props.find("string[@name='Name']") if props is not None else None
            if name_el is None:
                continue
            acc = out.setdefault(f"{path.stem}/{name_el.text}", [])
            for item in grp.iter("Item"):
                if item.get("class") != "Part":
                    continue
                p = item.find("Properties")
                b = part_box(p) if p is not None else None
                if b is not None:
                    acc.append((b[0], part_footprint(p), b[1:]))
    return out


def place_points(path: Path):
    """[(id, x, z, floor)] for every tagged part in a file, each one once.

    Deliberately not check_city's `parse_rbxmx`: that walk visits a point once
    per enclosing model and hands back duplicates for the caller to squash by
    id, which means two *different* points sharing one id look exactly like one
    point seen twice. In the town every point lives in a single `PlacePoints`
    group, so the id collision is the only thing a duplicate can be.
    """
    out = []
    for item in ET.parse(path).getroot().iter("Item"):
        if item.get("class") != "Part":
            continue
        props = item.find("Properties")
        if props is None:
            continue
        tags_el = props.find("BinaryString[@name='Tags']")
        attrs_el = props.find("BinaryString[@name='AttributesSerialize']")
        if tags_el is None or attrs_el is None:
            continue
        if PLACE_TAG.encode() not in decode_tags(tags_el.text):
            continue
        attrs = decode_attrs(attrs_el.text)
        if PLACE_ID_ATTR not in attrs:
            continue
        b = part_box(props)
        if b is not None:
            out.append((attrs[PLACE_ID_ATTR], (b[1] + b[2]) / 2,
                        (b[3] + b[4]) / 2, b[5]))
    return out


def solids(path: Path):
    """[(name, footprint, y0, y1)] for every colliding part that is not a marker.

    Place points themselves are excluded: they are one-stud cubes standing at
    the exact spot the checks below ask about, so leaving them in would have
    every point report itself as the thing in its own way.
    """
    out = []
    for item in ET.parse(path).getroot().iter("Item"):
        if item.get("class") != "Part":
            continue
        props = item.find("Properties")
        if props is None:
            continue
        cc = props.find("bool[@name='CanCollide']")
        if cc is not None and cc.text == "false":
            continue
        tags_el = props.find("BinaryString[@name='Tags']")
        if tags_el is not None and PLACE_TAG.encode() in decode_tags(tags_el.text):
            continue
        b = part_box(props)
        if b is not None:
            out.append((f"{path.stem}/{b[0]}", part_footprint(props), b[5], b[6]))
    return out


def gap_to(x, z, foot):
    """Distance from a point to a footprint in plan; negative if inside it.

    -1.0 rather than the true penetration depth when the point is inside: the
    depth is not a number anyone acts on, and a single sentinel keeps the
    reported column honest about the difference between "close to" and "in".
    """
    if plan_overlap((x, z, 0.001, 0.001, 0.0), foot) > 0.0:
        return -1.0
    cx, cz, hx, hz, yaw = foot
    c, s = math.cos(-yaw), math.sin(-yaw)
    dx, dz = x - cx, z - cz
    lx, lz = dx * c - dz * s, dx * s + dz * c
    return math.hypot(max(abs(lx) - hx, 0.0), max(abs(lz) - hz, 0.0))


def ground_floor_walls(parts):
    """The parts of a group that are walls standing on the ground floor.

    Same three tests check_city uses, and for the same reason: taller than a
    kerb, bigger in plan than a post, based low enough to be a wall rather than
    an awning or a hanging sign. An overhang into the street is deliberate and
    common; standing in the street is not.
    """
    out = []
    for name, foot, (x0, x1, z0, z1, y0, y1) in parts:
        if (y1 - y0 <= WALL_MIN_HEIGHT
                or (x1 - x0) * (z1 - z0) <= WALL_MIN_AREA
                or y0 > WALL_MAX_BASE):
            continue
        out.append((name, foot, (x0, x1, z0, z1, y0, y1)))
    return out


def main():
    groups = {}
    for f in TOWN_ASSETS:
        groups.update(top_groups(ASSETS / f"{f}.rbxmx"))

    points = []
    for f in TOWN_ASSETS:
        points.extend(place_points(ASSETS / f"{f}.rbxmx"))

    obstacles = []
    for f in SOLID_ASSETS:
        obstacles.extend(solids(ASSETS / f"{f}.rbxmx"))

    buildings = {g: ground_floor_walls(parts) for g, parts in groups.items()
                 if g.split("/", 1)[1] not in SURFACE_GROUPS
                 and any(n == ROOF_PART for n, _f, _b in parts)}

    print(f"Parsing {', '.join(TOWN_ASSETS)}...")
    print(f"  {len(points)} place points, {len(buildings)} buildings, "
          f"{len(obstacles)} colliding parts in {len(SOLID_ASSETS)} assets.\n")

    # --- 1. Place point ids ---
    print("1. Place point ids")
    ids = [pid for pid, *_ in points]
    dupes = sorted({pid for pid in ids if ids.count(pid) > 1})
    for pid in dupes:
        where = [f"({x:.0f},{z:.0f})" for p, x, z, _f in points if p == pid]
        print(f"    {pid} is declared at {', '.join(where)}", file=sys.stderr)
    check("every place point id is used once", not dupes,
          f"{len(dupes)} id(s) declared twice")
    print()

    # --- 2. Ground under every place point ---
    print("2. Ground under place points")
    # check_city asks this of the city's points and only the city's. The town's
    # were never asked, and three of them were floating: wp_loop_n, wp_loop_m
    # and wp_loop_m2 were written at PAVING height while standing in the middle
    # of the return road's carriageway, half a stud up. wp_loop_s, the fourth
    # point on the same road, was written at GROUND and was right -- so the
    # defect was one line being fixed and its three neighbours not.
    #
    # Half a stud is nothing to look at. The reason it is a failure rather than
    # a note is that the *height a point declares is a claim about what surface
    # it is on*, and three points claimed to be on a pavement that is fifteen
    # studs away.
    floating = []
    for pid, x, z, floor_y in points:
        top = None
        for _nm, foot, y0, y1 in obstacles:
            if y0 > floor_y + 0.01:
                continue
            if gap_to(x, z, foot) > 0.0:
                continue
            if top is None or y1 > top:
                top = y1
        drop = floor_y - top if top is not None else math.inf
        if drop > GROUND_FLOAT_TOL:
            floating.append((drop, pid, x, z))
    for drop, pid, x, z in sorted(floating, reverse=True):
        where = "nothing at all under it" if drop == math.inf else f"a {drop:.2f} stud drop"
        print(f"    {pid} at ({x:.0f},{z:.0f}): {where}", file=sys.stderr)
    check(f"every place point has ground within {GROUND_FLOAT_TOL:.2f}",
          not floating, f"{len(floating)} floating")
    print()

    # --- 3. Room to stand at every place point ---
    print("3. Room to stand")
    # A place point is not a label on a map. It is the coordinate the game walks
    # a player to and leaves them standing on, and nothing in this repo has ever
    # asked whether a body fits there. The bakery's did not: "the bakery, at the
    # counter" named a spot four studs inside a 10x10 solid counter, so the one
    # instruction the game gives in that building put the player in the
    # furniture.
    #
    # It is worth being precise about why nothing else could see it. Check 2
    # above passes -- there is a floor under the point, the counter is standing
    # on it. check_city's building-overlap check compares buildings with
    # buildings and a place point is neither. The fittings are laid out by a
    # generator that never reads the place point table, and the place point
    # table is a list of coordinates that never reads the fittings. The two are
    # only ever compared here.
    tight = []
    for pid, x, z, floor_y in points:
        lo, hi = floor_y + STAND_STEP, floor_y + STAND_HEAD
        worst = None
        for nm, foot, y0, y1 in obstacles:
            if y1 <= lo or y0 >= hi:
                continue
            d = gap_to(x, z, foot)
            if worst is None or d < worst[0]:
                worst = (d, nm)
        if worst is not None and worst[0] < STAND_CLEAR:
            tight.append((worst[0], pid, x, z, worst[1]))
    for d, pid, x, z, nm in sorted(tight):
        how = f"is inside {nm}" if d < 0 else f"is {d:.2f} studs from {nm}"
        print(f"    {pid} at ({x:.0f},{z:.0f}) {how}", file=sys.stderr)
    check(f"every place point has {STAND_CLEAR} studs of clearance to stand in",
          not tight, f"{len(tight)} unstandable")
    print()

    # --- 4. A place point in every building ---
    print("4. A place point in every building")
    # gen_town.py says of the houses: "a home the game cannot send anybody to,
    # in a world where nothing checks that a building has a door the route graph
    # knows about". This is that check. A building with no point in it is a
    # thirty-thousand-part prop -- the player can see it, walk round it, read
    # the sign over the door, and there is no way for the game to ever mention
    # it.
    #
    # Note what this cannot see: the spawn house is House.rbxmx, an imported
    # asset with no named groups and no roof part this rule can find, so it is
    # not in the list. Its point (`home`) is written in Street.rbxmx and is
    # covered by checks 2 and 3 like any other.
    empty = []
    for g, walls in sorted(buildings.items()):
        x0 = min(b[0] for _n, _f, b in walls) - DOOR_SLACK
        x1 = max(b[1] for _n, _f, b in walls) + DOOR_SLACK
        z0 = min(b[2] for _n, _f, b in walls) - DOOR_SLACK
        z1 = max(b[3] for _n, _f, b in walls) + DOOR_SLACK
        inside = [pid for pid, px, pz, _f in points
                  if x0 <= px <= x1 and z0 <= pz <= z1 and not pid.startswith("wp_")]
        if not inside:
            empty.append((g, x0, x1, z0, z1))
    for g, x0, x1, z0, z1 in empty:
        print(f"    {g} has no place point in x[{x0:.0f},{x1:.0f}] "
              f"z[{z0:.0f},{z1:.0f}] -- nothing can be sent there", file=sys.stderr)
    check("every building can be walked to", not empty,
          f"{len(empty)} building(s) with no place point")
    print()

    # --- 5. Building overlap ---
    print("5. Building overlap")
    # check_city's version of this reads `city_models` and stops. Two town
    # buildings standing in each other has never been asked.
    overlaps = []
    names = sorted(buildings)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            for _n1, f1, b1 in buildings[a]:
                for _n2, f2, b2 in buildings[b]:
                    if b1[5] <= b2[4] + COPLANAR or b2[5] <= b1[4] + COPLANAR:
                        continue  # one is stacked clear above the other
                    if plan_overlap(f1, f2) > COPLANAR:
                        overlaps.append((a, _n1, b, _n2))
                        break
                else:
                    continue
                break
    for a, n1, b, n2 in overlaps:
        print(f"    {a}.{n1} stands in {b}.{n2}", file=sys.stderr)
    check("no two buildings overlap", not overlaps, f"{len(overlaps)} overlap(s)")
    print()

    # --- 6. Roads against buildings ---
    print("6. Roads against buildings")
    # The town's half of the check that found the corner shop standing in the
    # gate road. That one tests the *city's* roads against every asset's walls;
    # this tests the town's own, which nothing has.
    #
    # And it has to know that the two generators disagree about where a road
    # lives. `build_street.py` puts its carriageway in a group called `Road`.
    # `gen_town.py` puts its four in the `Ground` group, named `RoadN`,
    # `RoadEast`, `RoadBottom`, `RoadReturn` -- because in the town the road is
    # a tile of the ground jigsaw rather than a slab laid on top of it, which is
    # also why the "is the road network one connected piece" question does not
    # transfer from the city and is not asked here. Faking it by unioning the
    # ground tiles would return "one piece" for a town with no roads in it at
    # all. That check needs a real formulation before it needs a threshold.
    roads = []
    for g, parts in groups.items():
        gname = g.split("/", 1)[1]
        for name, foot, box in parts:
            if gname == "Road" or (gname == "Ground" and name.startswith("Road")):
                if "Dash" not in name:
                    roads.append((f"{g}/{name}", foot))
    struck = {}
    for g, walls in buildings.items():
        for wname, wfoot, wbox in walls:
            for rname, rfoot in roads:
                bite = plan_overlap(wfoot, rfoot)
                if bite > STREET_BITE:
                    prev = struck.get(g)
                    if prev is None or bite > prev[0]:
                        struck[g] = (bite, wname, rname, wbox)
    print(f"  {len(roads)} carriageway slabs against "
          f"{sum(len(w) for w in buildings.values())} ground-floor walls.")
    for g, (bite, wname, rname, wbox) in sorted(struck.items()):
        print(f"    {rname} cuts {bite:.1f} studs into {g}.{wname} "
              f"at x[{wbox[0]:.0f},{wbox[1]:.0f}] z[{wbox[2]:.0f},{wbox[3]:.0f}]",
              file=sys.stderr)
    check("no road runs through a building", not struck,
          f"{len(struck)} building(s) with a road in them")

    print()
    if assertions_failed == 0:
        print("ALL CHECKS PASSED")
    else:
        print(f"{assertions_failed} CHECK(S) FAILED", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
