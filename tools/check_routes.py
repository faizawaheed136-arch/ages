"""Can a player actually walk there?

**Why this exists.** Every other check in this repo asks whether the geometry is *correct*:
nothing overlapping, nothing floating, dimensions in range. This building keeps producing a
different kind of fault -- geometry that is individually correct and collectively wrong. A locker
bank flush against a wall is a legal bank; it is also, if the wall happens to be the only route
from the atrium to the corridor, the entire school's circulation gone. Nothing in
`check_school.py` can see that, because it looks for parts inside other parts and never for a
part inside a *route*.

Three faults shipped that way and were each found by a person walking into them:

  * the corridor sat three studs over the atrium void, so on the upper floor it had no floor
  * the stairwells were sealed -- shafts with a staircase inside and no door
  * locker banks stood in both passages between the atrium and the corridor

Two of those three would have failed a plain reachability test. The locker one would not, and
that is the more useful lesson: the banks narrowed both passages to about eleven studs without
severing them, so the school stayed fully connected and still read as blocked to anyone walking
it. Connectivity is too weak a question. This asks the stronger one -- *how tight is the
tightest squeeze on the way to each room* -- which catches a route being strangled as well as
cut.

**How it works.** Voxelise the school at two-stud resolution, one layer per storey. A cell is
standable if something supports it at floor level and nothing solid occupies the space a
character's body would need above it. Stair treads link the layers. Then flood-fill from just
inside the front door and report which doors the flood never reached.

Run it after any change to the plan:

    python tools/check_routes.py
"""

from __future__ import annotations

import math
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
ASSET = ROOT / "assets" / "School.rbxmx"

CELL = 2.0
# A Roblox humanoid is about 5 studs tall and steps up 2 without jumping. Support is anything
# whose top surface lands within a step of the floor; an obstruction is anything occupying the
# body above it. Checking the body rather than the feet is what makes a locker bank register as
# a wall and a floor slab not.
STEP_UP = 2.2
BODY_LOW = 2.4
BODY_HIGH = 5.4

# Names that are decoration rather than obstruction. A player walks through a light panel's
# footprint and over a rug; treating them as walls would report false blockages everywhere.
#
# Door leaves are in here for a different reason: they are solid, and they open. Counted as
# walls, every room in the building reported a 4-stud bottleneck at its own doorway and the
# check said nothing useful about anything else. What matters is the width of the *opening*,
# which is what is left once the leaf swings out of it.
PASSABLE = (
    "CeilPanel", "LobbyPanel", "CeilStrip", "Light", "Sign", "Plate", "Band", "Label",
    "Rug", "Bunting", "Banner", "Canopy", "Nosing", "Stripe", "Seam", "Vent", "Handle",
    "Glass", "Mullion", "Fascia", "Soffit", "Crest", "Sheet", "Cork", "Books", "Vision",
    "DoorLeaf", "DoorBar", "DoorPanel",
)
STAIR = ("Stair",)


def aabbs():
    """Every part as an axis-aligned box, rotation accounted for."""
    root = ET.parse(ASSET).getroot()
    out = []
    for item in root.iter("Item"):
        if item.get("class") != "Part":
            continue
        name = item.find("Properties/string[@name='Name']")
        cf = item.find("Properties/CoordinateFrame[@name='CFrame']")
        size = item.find("Properties/Vector3[@name='size']")
        if size is None:
            size = item.find("Properties/Vector3[@name='Size']")
        if name is None or cf is None or size is None or not name.text:
            continue
        c = [float(cf.find(a).text) for a in "XYZ"]
        s = [float(size.find(a).text) for a in "XYZ"]
        r = [float(cf.find(f"R{a}{b}").text) for a in (0, 1, 2) for b in (0, 1, 2)]
        # Half-extent along each world axis for a rotated box.
        h = [
            (abs(r[0]) * s[0] + abs(r[1]) * s[1] + abs(r[2]) * s[2]) / 2,
            (abs(r[3]) * s[0] + abs(r[4]) * s[1] + abs(r[5]) * s[2]) / 2,
            (abs(r[6]) * s[0] + abs(r[7]) * s[1] + abs(r[8]) * s[2]) / 2,
        ]
        out.append((name.text, c, h))
    return out


def main() -> int:
    if not ASSET.exists():
        print(f"no {ASSET.relative_to(ROOT)} -- run tools/gen_school.py first")
        return 1

    parts = aabbs()
    if not parts:
        print("no parts in the asset")
        return 1

    # Storey levels, taken from the floor plates themselves rather than from Config -- the
    # question is what was built, not what was meant.
    levels = sorted({round(c[1] + h[1], 1) for n, c, h in parts if n.startswith("Floor") and "Rail" not in n})
    levels = [y for i, y in enumerate(levels) if i == 0 or y - levels[i - 1] > 5]
    if not levels:
        print("no floor plates found")
        return 1

    xs = [c[0] for _, c, _ in parts]
    zs = [c[2] for _, c, _ in parts]
    x0, x1 = min(xs) - 4, max(xs) + 4
    z0, z1 = min(zs) - 4, max(zs) + 4
    nx = int((x1 - x0) / CELL) + 1
    nz = int((z1 - z0) / CELL) + 1

    support = [[[False] * nz for _ in range(nx)] for _ in levels]
    blocked = [[[False] * nz for _ in range(nx)] for _ in levels]
    stairish = [[[False] * nz for _ in range(nx)] for _ in levels]

    for name, c, h in parts:
        passable = any(k in name for k in PASSABLE)
        is_stair = any(k in name for k in STAIR)
        gx0 = max(0, int((c[0] - h[0] - x0) / CELL))
        gx1 = min(nx - 1, int((c[0] + h[0] - x0) / CELL))
        gz0 = max(0, int((c[2] - h[2] - z0) / CELL))
        gz1 = min(nz - 1, int((c[2] + h[2] - z0) / CELL))
        top, bottom = c[1] + h[1], c[1] - h[1]
        for li, y in enumerate(levels):
            supports = (y - STEP_UP) <= top <= (y + STEP_UP)
            obstructs = (not passable) and bottom < y + BODY_HIGH and top > y + BODY_LOW
            if not (supports or obstructs or is_stair):
                continue
            for gx in range(gx0, gx1 + 1):
                for gz in range(gz0, gz1 + 1):
                    if supports:
                        support[li][gx][gz] = True
                    if obstructs and not is_stair:
                        blocked[li][gx][gz] = True
                    if is_stair:
                        stairish[li][gx][gz] = True

    def standable(li, gx, gz):
        if not (0 <= gx < nx and 0 <= gz < nz):
            return False
        if stairish[li][gx][gz]:
            return True
        return support[li][gx][gz] and not blocked[li][gx][gz]

    # Start just inside the front door.
    doors = [(n, c) for n, c, _ in parts if n.startswith("EntranceDoorLeaf")]
    if not doors:
        print("no entrance door found")
        return 1
    dx = sum(c[0] for _, c in doors) / len(doors)
    dz = sum(c[2] for _, c in doors) / len(doors)
    inward = 1 if dz < (z0 + z1) / 2 else -1

    start = None
    for step in range(3, 40):
        gx = int((dx - x0) / CELL)
        gz = int((dz + inward * step - z0) / CELL)
        if standable(0, gx, gz):
            start = (0, gx, gz)
            break
    if start is None:
        print("FAIL  nothing standable inside the front door -- the lobby has no floor")
        return 1

    seen = set([start])
    stack = [start]
    while stack:
        li, gx, gz = stack.pop()
        for ax, az in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nxt = (li, gx + ax, gz + az)
            if nxt not in seen and standable(li, gx + ax, gz + az):
                seen.add(nxt)
                stack.append(nxt)
        # A stair cell joins the storey above and below.
        if stairish[li][gx][gz]:
            for other in (li - 1, li + 1):
                if 0 <= other < len(levels) and standable(other, gx, gz):
                    nxt = (other, gx, gz)
                    if nxt not in seen:
                        seen.add(nxt)
                        stack.append(nxt)

    reached_floor = [sum(1 for li, _, _ in seen if li == i) for i in range(len(levels))]

    # ---- clearance, and the bottleneck on the best route to each cell
    #
    # Clearance is the distance from a cell to the nearest thing you would walk into, by a BFS
    # outward from every blocked cell. The bottleneck is then a widest-path search: among all
    # routes from the front door to a cell, the one whose narrowest point is widest. That number
    # is what a player experiences as "this bit is tight".
    INF = 10 ** 9
    clear = [[[INF] * nz for _ in range(nx)] for _ in levels]
    ring = []
    for li in range(len(levels)):
        for gx in range(nx):
            for gz in range(nz):
                if blocked[li][gx][gz] or not support[li][gx][gz]:
                    clear[li][gx][gz] = 0
                    ring.append((li, gx, gz))
    head = 0
    while head < len(ring):
        li, gx, gz = ring[head]
        head += 1
        for ax, az in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            mx, mz = gx + ax, gz + az
            if 0 <= mx < nx and 0 <= mz < nz and clear[li][mx][mz] > clear[li][gx][gz] + 1:
                clear[li][mx][mz] = clear[li][gx][gz] + 1
                ring.append((li, mx, mz))

    import heapq
    wide = {}
    pq = [(-clear[start[0]][start[1]][start[2]], start)]
    while pq:
        negw, cell = heapq.heappop(pq)
        w = -negw
        if cell in wide and wide[cell] >= w:
            continue
        wide[cell] = w
        li, gx, gz = cell
        nbrs = [(li, gx + ax, gz + az) for ax, az in ((1, 0), (-1, 0), (0, 1), (0, -1))]
        if stairish[li][gx][gz]:
            nbrs += [(o, gx, gz) for o in (li - 1, li + 1) if 0 <= o < len(levels)]
        for nb in nbrs:
            if nb not in seen:
                continue
            nw = min(w, clear[nb[0]][nb[1]][nb[2]])
            if nw > wide.get(nb, -1):
                heapq.heappush(pq, (-nw, nb))

    # Every room door: is the corridor side of it reachable?
    targets = [(n, c) for n, c, _ in parts if n.endswith("DoorLeaf") and not n.startswith("Entrance")]
    unreachable = []
    tight = []
    for name, c in targets:
        ok = False
        best = 0
        for r in range(1, 9):
            for ax, az in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                gx = int((c[0] + ax * r * CELL - x0) / CELL)
                gz = int((c[2] + az * r * CELL - z0) / CELL)
                for li in range(len(levels)):
                    if (li, gx, gz) in seen:
                        ok = True
                        best = max(best, wide.get((li, gx, gz), 0))
            if ok:
                break
        if not ok:
            unreachable.append(name)
        else:
            # Clearance is a radius in cells, so the walkable width it implies is twice it.
            tight.append((best * 2 * CELL, name))

    print(f"walkable map: {nx} x {nz} cells at {CELL:g} studs, {len(levels)} storeys "
          f"at y {', '.join(f'{y:g}' for y in levels)}")
    for i, n in enumerate(reached_floor):
        state = "reached" if n else "NEVER REACHED"
        print(f"  storey {i + 1}: {n:5} cells {state} from the front door")
    print(f"  {len(targets) - len(unreachable)}/{len(targets)} room doors reachable on foot")
    if tight:
        tight.sort()
        print(f"  tightest squeeze on any route: {tight[0][0]:.0f} studs (to {tight[0][1]})")
        print("  narrowest five routes:")
        for w, n in tight[:5]:
            print(f"     {w:5.0f} studs   {n}")

    failed = False
    if len(levels) > 1 and reached_floor[1] == 0:
        print("\nFAIL  the upper storey cannot be reached from the front door -- "
              "the stairs are sealed, or they land somewhere with no floor")
        failed = True
    # A route narrower than this is one a player reads as blocked even though it is not.
    SQUEEZE = 8.0
    squeezed = [(w, n) for w, n in tight if w < SQUEEZE]
    if squeezed:
        print()
        print(f"FAIL  {len(squeezed)} route(s) squeezed below {SQUEEZE:g} studs:")
        for w, n in squeezed:
            print(f"        {w:5.1f} studs   {n}")
        failed = True

    if unreachable:
        print(f"\nFAIL  {len(unreachable)} door(s) with no walkable route from the entrance:")
        for n in sorted(unreachable):
            print(f"        {n}")
        failed = True

    if failed:
        return 1
    print("\nall clean -- every room is reachable on foot from the front door")
    return 0


if __name__ == "__main__":
    sys.exit(main())
