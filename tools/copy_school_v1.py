"""Makes an editable copy of school v1, standing on its own clear ground.

**Why this exists.** v1 is finished and working, and editing the thing that is already in the
map is the risky move: there is no undo in Studio that survives a resync, and a bad edit to
`assets/School.rbxmx` is a bad edit to the school players walk around in.

So this writes a second, independent model -- same parts, same names, shifted to empty ground --
mounted at `Workspace.SchoolV1Copy`. Edit that one freely. The original is untouched, and it is
also recoverable three other ways: the `school-v1` git tag, `assets/archive/School-v1.rbxmx`,
and `assets/archive/School-v1.luau` (the builder that produced it).

Re-run to reset the copy back to whatever `assets/School.rbxmx` currently is. That throws away
edits made to the copy in Studio, which is the point of it being a copy.

    python tools/copy_school_v1.py
"""

from __future__ import annotations

import sys
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "School.rbxmx"
OUT = ROOT / "assets" / "SchoolV1Copy.rbxmx"

# Surveyed against the copy's *measured* footprint -- 460 x 404 -- plus a 20-stud margin all
# round, on a 20-stud occupancy grid across every other asset in the map.
#
# Measured rather than assumed, because the first attempt guessed the footprint at 440x450 and
# put the copy 17 studs into the original it was supposed to be safely away from. A model's
# bounding box is a thing you can read; there is no reason to estimate it.
SITE = (-910.0, -30.0)


def measure(root: ET.Element) -> tuple[float, float]:
    """The source model's centre in x and z, so the shift can be expressed as a destination."""
    xs: list[float] = []
    zs: list[float] = []
    for item in root.iter("Item"):
        if item.get("class") != "Part":
            continue
        cf = item.find("Properties/CoordinateFrame[@name='CFrame']")
        size = item.find("Properties/Vector3[@name='size']")
        if size is None:
            size = item.find("Properties/Vector3[@name='Size']")
        if cf is None or size is None:
            continue
        x = float(cf.find("X").text)
        z = float(cf.find("Z").text)
        sx = float(size.find("X").text)
        sz = float(size.find("Z").text)
        xs += [x - sx / 2, x + sx / 2]
        zs += [z - sz / 2, z + sz / 2]
    return (min(xs) + max(xs)) / 2, (min(zs) + max(zs)) / 2


def main() -> int:
    if not SOURCE.exists():
        print(f"no {SOURCE.relative_to(ROOT)} to copy -- run tools/gen_school.py first")
        return 1

    tree = ET.parse(SOURCE)
    root = tree.getroot()

    cx, cz = measure(root)
    dx, dz = SITE[0] - cx, SITE[1] - cz

    # Only the CFrame's translation moves. Rotation is left exactly as it is -- every rotated
    # part in this model (the cylinders, the curved stair treads) keeps its orientation, and a
    # copy that quietly straightened them would be a different building.
    moved = 0
    for item in root.iter("Item"):
        cf = item.find("Properties/CoordinateFrame[@name='CFrame']")
        if cf is None:
            continue
        node_x, node_z = cf.find("X"), cf.find("Z")
        if node_x is None or node_z is None:
            continue
        node_x.text = repr(float(node_x.text) + dx)
        node_z.text = repr(float(node_z.text) + dz)
        moved += 1

    # The top-level model gets its own name, or Rojo mounts two things called "School" and one
    # of them wins at random.
    for item in root.iter("Item"):
        if item.get("class") == "Model":
            name = item.find("Properties/string[@name='Name']")
            if name is not None and name.text == "School":
                name.text = "SchoolV1Copy"
                break

    tree.write(OUT, encoding="utf-8", xml_declaration=True)
    print(f"wrote {OUT} -- {moved} parts, moved {dx:+.0f} x {dz:+.0f} to ({SITE[0]:.0f}, {SITE[1]:.0f})")
    print("the original assets/School.rbxmx is untouched")
    return 0


if __name__ == "__main__":
    sys.exit(main())
