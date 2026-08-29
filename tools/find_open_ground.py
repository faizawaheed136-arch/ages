#!/usr/bin/env python3
"""Finds a clear rectangle big enough to put the school on.

Run from the repo root:  python tools/find_open_ground.py [width] [depth]

Moving the school "somewhere it does not overlap anything" is not a thing to judge by eye.
The map is 2048 studs across with roads, pavements, houses, shops and a stadium in it, and the
school with its campus apron is roughly 300 x 260 -- there are not many places it fits, and
the ones that look empty in Studio are often a pavement or a waypoint chain.

So this measures. It reads every asset the project mounts, projects every part onto the
ground plane, and scans for the emptiest rectangle of the requested size. Roads and pavements
count as occupied: a school laid over a carriageway passes a visual check and fails
check_city's "no street runs through a building", which is the exact failure this is meant to
avoid.
"""

import sys
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"

# The school is laid around a place point, so what matters is where its *footprint* lands.
# Defaults are the current building plus its campus apron, with a margin.
DEFAULT_W, DEFAULT_D = 300, 260

# Assets that are the world a building would collide with. School.rbxmx is excluded on
# purpose -- we are looking for somewhere to put it, so it must not count as an obstacle.
OBSTACLES = ("Street", "Town", "City", "House", "Furniture", "SchoolFurniture", "Versailles")

MAP_MIN, MAP_MAX = -1024, 1024
CELL = 16  # grid resolution in studs; fine enough to matter, coarse enough to be quick


def parts_of(path: Path):
    """Every part's world-space footprint as (x0, z0, x1, z1)."""
    if not path.exists():
        return
    for props in ET.parse(path).getroot().iter("Properties"):
        cf = props.find("CoordinateFrame[@name='CFrame']")
        size = props.find("Vector3[@name='size']")
        if cf is None or size is None:
            continue
        try:
            x = float(cf.find("X").text)
            z = float(cf.find("Z").text)
            sx = float(size.find("X").text)
            sz = float(size.find("Z").text)
        except (AttributeError, TypeError, ValueError):
            continue
        # Rotation is ignored deliberately: an axis-aligned bound of a rotated part is larger
        # than the part, which errs toward calling ground occupied. For "is this clear?" the
        # safe error is the pessimistic one.
        yield (x - sx / 2, z - sz / 2, x + sx / 2, z + sz / 2)


def main() -> None:
    want_w = float(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_W
    want_d = float(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_D

    n = (MAP_MAX - MAP_MIN) // CELL
    occupied = bytearray(n * n)

    counted = 0
    for name in OBSTACLES:
        for x0, z0, x1, z1 in parts_of(ASSETS / f"{name}.rbxmx"):
            counted += 1
            cx0 = max(0, int((x0 - MAP_MIN) // CELL))
            cx1 = min(n - 1, int((x1 - MAP_MIN) // CELL))
            cz0 = max(0, int((z0 - MAP_MIN) // CELL))
            cz1 = min(n - 1, int((z1 - MAP_MIN) // CELL))
            for cz in range(cz0, cz1 + 1):
                base = cz * n
                for cx in range(cx0, cx1 + 1):
                    occupied[base + cx] = 1

    print(f"scanned {counted} parts across {len(OBSTACLES)} assets, {CELL}-stud grid")

    # Summed-area table over the occupancy grid, so any rectangle costs four lookups.
    sat = [[0] * (n + 1) for _ in range(n + 1)]
    for z in range(n):
        row = sat[z + 1]
        prev = sat[z]
        run = 0
        base = z * n
        for x in range(n):
            run += occupied[base + x]
            row[x + 1] = prev[x + 1] + run

    cw = int(want_w // CELL)
    cd = int(want_d // CELL)
    best = []
    for z in range(0, n - cd):
        for x in range(0, n - cw):
            total = sat[z + cd][x + cw] - sat[z][x + cw] - sat[z + cd][x] + sat[z][x]
            if total == 0:
                wx = MAP_MIN + (x + cw / 2) * CELL
                wz = MAP_MIN + (z + cd / 2) * CELL
                best.append((wx, wz))

    print(f"\nlooking for {want_w:.0f} x {want_d:.0f} studs of completely clear ground")
    if not best:
        print("  none found -- nowhere on the map is that empty.")
        print("  Try a smaller footprint, or accept a site that clips a pavement.")
        return

    # Report a few well-separated options rather than a thousand adjacent cells.
    chosen = []
    for wx, wz in best:
        if all(abs(wx - px) > want_w or abs(wz - pz) > want_d for px, pz in chosen):
            chosen.append((wx, wz))
        if len(chosen) >= 8:
            break

    print(f"  {len(best)} clear positions; {len(chosen)} distinct sites:\n")
    for wx, wz in chosen:
        print(f"    centre ({wx:8.0f}, {wz:8.0f})")


if __name__ == "__main__":
    main()
