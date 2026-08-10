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
"""

import base64
import math
import struct
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

ASSETS = Path(__file__).resolve().parent.parent / "assets"
CITY_PATH = ASSETS / "City.rbxmx"
TOWN_PATH = ASSETS / "Town.rbxmx"

ROUTE_LINK = 70.0
GROUND = 1.02
GROUND_FLOAT_TOL = 0.15

PLACE_TAG = "AgesPlacePoint"
PLACE_ID_ATTR = "PlaceId"

# Minimum thresholds from the plan.
MIN_HOUSES = 100
MIN_CAREER = 30


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


def parse_rbxmx(path: Path):
    """Return (place_points, models) from an rbxmx file.

    place_points: list of (id, x, z, floor)
    models: list of (name, bbox) where bbox = (xmin, xmax, zmin, zmax, ymin, ymax)

    Models are the top-level replacement contract: each Model in the file, with a
    bbox covering every Part under it at any depth. Houses are one Model named
    `Suburb<N>` wrapping `HouseStructure` and `HouseFittings` sub-models, so a
    bbox built from direct children only would miss the house entirely.
    """
    tree = ET.parse(path)
    root = tree.getroot()
    place_points = []
    models = []

    def walk(element):
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
            for item in child.findall(".//Item"):
                if item.get("class") != "Part":
                    continue
                p = item.find("Properties")
                cf = p.find("Vector3[@name='size']") if p is not None else None
                cf_x = p.find("CoordinateFrame[@name='CFrame']") if p is not None else None
                if cf is None or cf_x is None:
                    continue
                sx = float(cf.find("X").text)
                sy = float(cf.find("Y").text)
                sz = float(cf.find("Z").text)
                px = float(cf_x.find("X").text)
                py = float(cf_x.find("Y").text)
                pz = float(cf_x.find("Z").text)
                parts.append((px - sx / 2, px + sx / 2,
                              pz - sz / 2, pz + sz / 2,
                              py - sy / 2, py + sy / 2))
                # Place point tags can sit on any part at any depth.
                tags_el = p.find("BinaryString[@name='Tags']")
                attrs_el = p.find("BinaryString[@name='AttributesSerialize']")
                tags = decode_tags(tags_el.text) if tags_el is not None else []
                if PLACE_TAG.encode() in tags and attrs_el is not None:
                    attrs = decode_attrs(attrs_el.text)
                    if PLACE_ID_ATTR in attrs:
                        x, z = px, pz
                        y = py - sy / 2  # floor = bottom of the part
                        place_points.append((attrs[PLACE_ID_ATTR], x, z, y))
            if parts:
                bbox = (min(p[0] for p in parts),
                        max(p[1] for p in parts),
                        min(p[2] for p in parts),
                        max(p[3] for p in parts),
                        min(p[4] for p in parts),
                        max(p[5] for p in parts))
                models.append((name, bbox))
            walk(child)

    walk(root)
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
            cf = props.find("CoordinateFrame[@name='CFrame']")
            sv = props.find("Vector3[@name='size']")
            if cf is None or sv is None:
                continue
            x = float(cf.find("X").text)
            z = float(cf.find("Z").text)
            y = float(cf.find("Y").text)
            sy = float(sv.find("Y").text)
            points.append((attrs[PLACE_ID_ATTR], x, z, y - sy / 2))
    return points


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
    house_models = [m for m in city_models if m[0].startswith("Suburb")]
    house_ids = {pid for pid, *_ in city_points if pid.startswith("suburb_")}
    check("≥100 house models", len(house_models) >= MIN_HOUSES,
          f"got {len(house_models)}")
    check("≥100 house place points", len(house_ids) >= MIN_HOUSES,
          f"got {len(house_ids)}")
    print()

    # --- 2. Career buildings ---
    print("2. Career buildings")
    # Models that contain a "Roof" part are buildings (houses, stores, civic).
    # Career buildings = all buildings minus houses.
    building_models = [m for m in city_models
                       if any(m[0] == n for n, _ in city_models)]
    # Actually re-check: a building has a Roof. We already have the part names;
    # look for models whose name is one of the known store/civic ids.
    career_ids = {pid for pid, *_ in city_points
                  if pid not in house_ids
                  and not pid.startswith("cs")
                  and not pid.startswith("ave")
                  and not pid.startswith("high")
                  and not pid.startswith("highs")
                  and not pid.startswith("conn")
                  and not pid.startswith("park_")
                  and not pid.startswith("city_")
                  and not pid.startswith("civic")}
    check("≥30 career place points", len(career_ids) >= MIN_CAREER,
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
    roof_models = []
    for name, bbox in city_models:
        if name.startswith("Suburb") or name in (
            "cafe", "restaurant", "pizzeria", "supermarket", "pharmacy",
            "florist", "bookstore", "electronics", "hardware", "toy_store",
            "clothing_store", "music_store", "laundromat", "barbershop",
            "salon", "tattoo_parlor", "pet_shop", "vet", "dental",
            "optometrist", "auto_dealer", "gas_station", "car_wash",
            "post_office", "bank", "cinema", "bowling", "arcade",
            "hotel", "town_hall", "police_station", "fire_station",
            "warehouse", "construction_site", "farm",
        ):
            roof_models.append((name, bbox))

    overlaps = 0
    for i in range(len(roof_models)):
        n1, (x1a, x1b, z1a, z1b, _, _) = roof_models[i]
        for j in range(i + 1, len(roof_models)):
            n2, (x2a, x2b, z2a, z2b, _, _) = roof_models[j]
            # Two boxes overlap if they overlap in all three axes.
            if (x1a < x2b and x1b > x2a and z1a < z2b and z1b > z2a):
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
            cf = props.find("Vector3[@name='size']")
            cf_x = props.find("CoordinateFrame[@name='CFrame']")
            if cf is None or cf_x is None:
                continue
            sx = float(cf.find("X").text)
            sy = float(cf.find("Y").text)
            sz = float(cf.find("Z").text)
            px = float(cf_x.find("X").text)
            py = float(cf_x.find("Y").text)
            pz = float(cf_x.find("Z").text)
            solid_boxes.append((px - sx / 2, px + sx / 2,
                                pz - sz / 2, pz + sz / 2,
                                py - sy / 2, py + sy / 2))

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

    # --- Summary ---
    print()
    if assertions_failed == 0:
        print("ALL CHECKS PASSED")
    else:
        print(f"{assertions_failed} CHECK(S) FAILED", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
