#!/usr/bin/env python3
"""Translates the school's place points in assets/Street.rbxmx.

Run from the repo root:  python tools/move_school_points.py <dx> <dz>

**Why this touches an asset that gen_street.py owns.** Agent A's downtown rebuild removed their
school building from Street.rbxmx but left its place points behind -- `school`, `classroom`,
`science_lab` and `cafeteria` are still there, marking rooms in a building that no longer
exists. They are orphaned markers, and the school system is what uses them now.

The school is laid *around* the `school` point, so moving the building means moving the point:
a marker left behind is a marker every route, sign and walk-to in the game navigates to while
the school stands somewhere else. The other three are interior markers and move by the same
delta so they stay in the rooms they name.

**This will be overwritten if Agent A regenerates Street.** That is a real risk and the reason
this is a script rather than a hand edit: it is re-runnable, it says what it did, and the delta
is recorded in the commit. If Street comes back with the points in their old spots, run it
again with the same numbers.

It writes a .bak beside the asset before touching anything.
"""

import shutil
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

STREET = ROOT / "assets" / "Street.rbxmx"

# The four the school owns. Deliberately a fixed list rather than "anything matching school":
# moving a point this tool does not understand is how a map quietly stops routing.
SCHOOL_POINTS = {"school", "classroom", "science_lab", "cafeteria"}


def main() -> None:
    if len(sys.argv) not in (3, 4):
        raise SystemExit("usage: python tools/move_school_points.py <dx> <dz> [dy]")
    dx, dz = float(sys.argv[1]), float(sys.argv[2])
    # Off the town's ground the only thing under these markers is the school's own campus slab,
    # whose top sits a fraction above the height the markers were set at -- so they end up
    # inside the slab rather than on it, and check_town reports them as floating with nothing
    # under them. A small lift puts them on the surface they are standing on.
    dy = float(sys.argv[3]) if len(sys.argv) == 4 else 0.0

    import importlib.util

    spec = importlib.util.spec_from_file_location("cc", ROOT / "tools" / "check_city.py")
    cc = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(cc)
    except SystemExit:
        pass

    text = STREET.read_text(encoding="utf-8")
    tree = ET.fromstring(text)

    moved = []
    for props in tree.iter("Properties"):
        el = props.find("BinaryString[@name='AttributesSerialize']")
        if el is None or not el.text:
            continue
        try:
            attrs = cc.decode_attrs(el.text)
        except Exception:
            continue
        pid = attrs.get("PlaceId")
        if pid not in SCHOOL_POINTS:
            continue
        cf = props.find("CoordinateFrame[@name='CFrame']")
        if cf is None:
            continue
        x = float(cf.find("X").text)
        y = float(cf.find("Y").text)
        z = float(cf.find("Z").text)
        cf.find("X").text = repr(x + dx)
        cf.find("Y").text = repr(y + dy)
        cf.find("Z").text = repr(z + dz)
        moved.append((pid, x, z, x + dx, z + dz))

    if not moved:
        raise SystemExit("no school place points found -- nothing written")

    shutil.copy2(STREET, STREET.with_suffix(".rbxmx.bak"))
    STREET.write_text(ET.tostring(tree, encoding="unicode"), encoding="utf-8")

    print(f"moved {len(moved)} place points by ({dx:+.1f}, {dz:+.1f}):")
    for pid, ox, oz, nx, nz in sorted(moved):
        print(f"   {pid:12} ({ox:8.1f},{oz:8.1f})  ->  ({nx:8.1f},{nz:8.1f})")


if __name__ == "__main__":
    main()
