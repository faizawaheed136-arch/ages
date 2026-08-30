#!/usr/bin/env python3
"""Finds things inside the school that block or intersect each other.

Run from the repo root:  python tools/check_school.py

check_town and check_city test the school against the *world* -- roads through it, buildings
under it, place points with nothing beneath them. Nothing tested the school against itself, so
furniture standing inside a wall, a bench through a stair and a machine buried in a column all
passed every gate while being the first thing anybody notices from the inside.

**What counts as a fault, and what does not.** Almost every object here is deliberately several
overlapping parts -- a table is a top and a leg that meet, a vending machine is a cabinet with a
window sunk into its face, a sign sits on the plate it is written on. Reporting those would bury
the real faults in thousands of intended ones. So a pair is only a fault when *both* parts are
solid, they belong to different objects, and the smaller one is substantially buried rather than
touching: two things that were placed independently and landed in the same space.

Slabs and floors are excluded as the thing being intersected: everything in the building
legitimately stands on a floor and most props sit slightly into one.
"""

import collections
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
ASSET = ROOT / "assets" / "School.rbxmx"

# How much of the smaller part has to be inside the larger before it is a fault rather than a
# join. Two thirds is well past "touching" and well short of "coincident".
BURIED_SHARE = 0.66

# The smallest part worth reporting. Below this it is trim, and trim is meant to sit in things.
MIN_VOLUME = 12.0

# Names that are structure or ground. A prop inside one of these is worth knowing about; two of
# these meeting each other is just the building being built.
# Pairs that are one object wearing two names. Books belong in a Stack; a machine's window is
# sunk into its own cabinet. Reporting these buries the real faults under intended ones.
TOGETHER = {("Books", "Stack"), ("Shelf", "Stack")}

STRUCTURE = ("Floor", "Roof", "Slab", "Campus", "Plaza", "Wall", "Ceil", "Terrace", "Apron",
             "Parapet", "Cornice", "Plinth", "Coping", "Band", "Landing", "Stair", "Bleacher",
             "Platform", "Rug", "Disc", "Court", "Lane", "Infield", "Track", "Pool", "Glass")


def family(name: str) -> str:
    """The object a part belongs to: its name with trailing indices stripped."""
    head = name.rstrip("0123456789_-")
    while head and head[-1] in "0123456789_-":
        head = head[:-1]
    return head or name


def is_structure(name: str) -> bool:
    return any(k in name for k in STRUCTURE)


def main() -> None:
    if not ASSET.exists():
        raise SystemExit(f"{ASSET} missing -- run tools/gen_school.py first")

    parts = []
    for item in ET.parse(ASSET).getroot().iter("Item"):
        if item.get("class") != "Part":
            continue
        props = item.find("Properties")
        n = props.find("string[@name='Name']")
        cf = props.find("CoordinateFrame[@name='CFrame']")
        sz = props.find("Vector3[@name='size']")
        col = props.find("bool[@name='CanCollide']")
        if n is None or cf is None or sz is None:
            continue
        if col is not None and col.text == "false":
            continue  # you can walk through it; it cannot block anything
        try:
            x, y, z = (float(cf.find(a).text) for a in ("X", "Y", "Z"))
            sx, sy, sz_ = (float(sz.find(a).text) for a in ("X", "Y", "Z"))
            r = [float(cf.find(f"R{a}{b}").text) for a in range(3) for b in range(3)]
        except (AttributeError, TypeError, ValueError):
            continue
        # Rotation-aware axis-aligned bounds. Generous, which for "is this buried" errs toward
        # not reporting -- the opposite of the mistake that matters here.
        hx = abs(r[0]) * sx / 2 + abs(r[1]) * sy / 2 + abs(r[2]) * sz_ / 2
        hy = abs(r[3]) * sx / 2 + abs(r[4]) * sy / 2 + abs(r[5]) * sz_ / 2
        hz = abs(r[6]) * sx / 2 + abs(r[7]) * sy / 2 + abs(r[8]) * sz_ / 2
        parts.append({
            "name": n.text or "?", "fam": family(n.text or "?"),
            "min": (x - hx, y - hy, z - hz), "max": (x + hx, y + hy, z + hz),
            "vol": max(sx * sy * sz_, 1e-6), "at": (x, y, z),
        })

    print(f"{len(parts)} solid parts in the school")

    # Bucket by cell so this is not 1753^2.
    CELL = 24
    grid = collections.defaultdict(list)
    for i, p in enumerate(parts):
        for cx in range(int(p["min"][0] // CELL), int(p["max"][0] // CELL) + 1):
            for cz in range(int(p["min"][2] // CELL), int(p["max"][2] // CELL) + 1):
                grid[(cx, cz)].append(i)

    faults = collections.Counter()
    examples = {}
    seen = set()
    for bucket in grid.values():
        for a_i in range(len(bucket)):
            for b_i in range(a_i + 1, len(bucket)):
                ia, ib = bucket[a_i], bucket[b_i]
                key = (min(ia, ib), max(ia, ib))
                if key in seen:
                    continue
                seen.add(key)
                a, b = parts[ia], parts[ib]
                if a["fam"] == b["fam"]:
                    continue                      # parts of one object
                if is_structure(a["name"]) and is_structure(b["name"]):
                    continue                      # the building meeting itself
                small, large = (a, b) if a["vol"] <= b["vol"] else (b, a)
                if small["vol"] < MIN_VOLUME:
                    continue
                if is_structure(large["name"]) and "Wall" not in large["name"]:
                    continue                      # standing on a floor is not a fault
                overlap = 1.0
                for axis in range(3):
                    lo = max(a["min"][axis], b["min"][axis])
                    hi = min(a["max"][axis], b["max"][axis])
                    if hi <= lo:
                        overlap = 0.0
                        break
                    overlap *= (hi - lo)
                if overlap / small["vol"] < BURIED_SHARE:
                    continue
                pair = tuple(sorted((small["fam"], large["fam"])))
                if pair in TOGETHER:
                    continue
                # A part sunk into the cabinet it belongs to -- CoffeeRecess in CoffeeBody --
                # shares a stem with it, which is the same "one object" case by another route.
                if small["fam"].startswith(large["fam"]) or large["fam"].startswith(small["fam"]):
                    continue
                faults[pair] += 1
                examples.setdefault(pair, (small["name"], large["name"], small["at"]))

    if not faults:
        print("\nno object is buried inside another. Clean.")
        return 0

    print(f"\n{sum(faults.values())} buried parts, across {len(faults)} pairs of objects:\n")
    for (fa, fb), count in faults.most_common(25):
        sn, ln, at = examples[(fa, fb)]
        print(f"  {count:4}x  {fa:22} inside {fb:22}  e.g. {sn} at ({at[0]:.0f},{at[1]:.0f},{at[2]:.0f})")
    return 1


if __name__ == "__main__":
    sys.exit(main())
