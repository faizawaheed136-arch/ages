"""Where a player can actually get to: a flood fill of the floor from the front doors.

    python sandbox/dealership/walkmap.py [out.png] [area]

A cell is solid if anything that collides stands at knee, waist or head height above the floor
there; a body is two studs wide, so the solid cells are grown by a stud before the fill. The fill
starts on the plaza at the doors and steps between neighbouring cells. The picture shows reachable
floor light, floor nobody can reach orange, solid dark -- a lounge behind a counter, a stair foot
behind a rope, a desk with no way round it are all orange where they should be light.

Areas: `showroom` (default) and `site`.
"""

import pathlib
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from walk import FLOOR, contains, half_extents, load  # noqa: E402

AREAS = {
    # x0, x1, z0, z1, cell, floor, start (x, z), labelled points
    "showroom": (146, 268, 8, 100, 0.5, FLOOR, (207, 18), {
        "lounge sofa": (169, 90), "reception": (163, 76.5), "desk 40": (246, 40), "desk 68": (246, 68),
        "stair foot": (242, 50), "build yours": (230, 64.5), "engine": (182, 57.5), "buy seat": (207, 64),
        "offices": (233, 86), "coffee bar": (156, 88), "side door": (151, 64),
        "store shelf": (173, 20.5), "store table": (172, 24), "kids table": (232, 20.8), "spec board": (166, 25),
    }),
    # The upper floor, from the head of the stair.
    "upper": (146, 268, 20, 100, 0.5, 13.45, (242, 82), {
        "owners lounge": (170, 90), "gallery": (240, 92), "bridge": (205, 93), "sky lounge": (254, 60),
        "deck office": (256, 40), "lift": (248, 31.5),
    }),
    "site": (-4, 314, -6, 176, 1.0, None, (207, -3), {
        "showroom": (207, 40), "lot": (60, 46), "cabin door": (22, 86), "garden fountain": (77, 134),
        "garden west": (14, 145), "service reception": (148, 115.4), "parts door": (244, 154),
        "wash entry": (290, 110), "vacuum bays": (286, 160), "ev bays": (290, 40), "handover": (135, 66),
        "yard bench": (202.5, 156), "bins": (221, 161.5),
    }),
}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "walkmap.png"
    area = sys.argv[2] if len(sys.argv) > 2 else "showroom"
    x0, x1, z0, z1, cell, floor, start, points = AREAS[area]
    parts = [p for p in load() if p["collide"]]
    for p in parts:
        p["he"] = half_extents(p)
    nx, nz = int((x1 - x0) / cell), int((z1 - z0) / cell)
    solid = np.zeros((nz, nx), bool)
    lo = np.array([p["pos"] - p["he"] for p in parts])
    hi = np.array([p["pos"] + p["he"] for p in parts])
    for j in range(nz):
        z = z0 + (j + 0.5) * cell
        row = (lo[:, 2] <= z) & (hi[:, 2] >= z)
        idx = np.nonzero(row)[0]
        for i in range(nx):
            x = x0 + (i + 0.5) * cell
            base = floor
            if base is None:
                # Outdoors: stand on whatever low surface is here (lot, walk, plaza, floor).
                base = 0.0
                for k in idx:
                    if lo[k][0] <= x <= hi[k][0] and hi[k][1] <= 1.0 and hi[k][1] > base:
                        base = hi[k][1]
            if floor is not None:
                # Something has to be underfoot: the hall's void is not a floor for the deck.
                under = np.array([x, base - 0.15, z])
                if not any(lo[k][0] <= x <= hi[k][0] and lo[k][1] <= under[1] <= hi[k][1] and contains(parts[k], under) for k in idx):
                    solid[j, i] = True
                    continue
            for h in (1.2, 2.8, 4.6):
                point = np.array([x, base + h, z])
                hit = False
                for k in idx:
                    if lo[k][0] <= x <= hi[k][0] and lo[k][1] <= point[1] <= hi[k][1] and contains(parts[k], point):
                        hit = True
                        break
                if hit:
                    solid[j, i] = True
                    break
    # Grow by the body's radius.
    r = int(round(1.0 / cell))
    grown = solid.copy()
    for dj in range(-r, r + 1):
        for di in range(-r, r + 1):
            if dj * dj + di * di <= r * r:
                grown |= np.roll(np.roll(solid, dj, 0), di, 1)
    reach = np.zeros_like(solid)
    si, sj = int((start[0] - x0) / cell), int((start[1] - z0) / cell)
    queue = deque([(sj, si)])
    reach[sj, si] = True
    while queue:
        j, i = queue.popleft()
        for dj, di in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            a, b = j + dj, i + di
            if 0 <= a < nz and 0 <= b < nx and not reach[a, b] and not grown[a, b]:
                reach[a, b] = True
                queue.append((a, b))
    scale = max(1, int(900 / max(nx, nz)))
    img = Image.new("RGB", (nx * scale, nz * scale))
    px = img.load()
    for j in range(nz):
        for i in range(nx):
            if solid[j, i]:
                c = (40, 40, 48)
            elif reach[j, i]:
                c = (225, 228, 220)
            elif grown[j, i]:
                c = (150, 150, 158)
            else:
                c = (240, 140, 40)
            for a in range(scale):
                for b in range(scale):
                    # Drawn as a map: +X to the right, +Z (away from the road) up.
                    px[i * scale + b, (nz - 1 - j) * scale + a] = c
    draw = ImageDraw.Draw(img)
    report = []
    for label, (x, z) in points.items():
        i, j = int((x - x0) / cell), int((z - z0) / cell)
        ok = 0 <= j < nz and 0 <= i < nx and reach[j, i]
        near = ok
        if not ok:
            # Reachable within two studs counts: a seat is reached by standing next to it.
            span = int(2.0 / cell)
            near = bool(reach[max(0, j - span):j + span + 1, max(0, i - span):i + span + 1].any())
        report.append((label, near))
        cx, cy = i * scale, (nz - 1 - j) * scale
        draw.ellipse((cx - 4, cy - 4, cx + 4, cy + 4), fill=(40, 170, 90) if near else (220, 40, 40))
        draw.text((cx + 6, cy - 6), label, fill=(20, 20, 20))
    img.save(out)
    print(f"wrote {out}: {reach.sum()} reachable cells, {(~solid & ~grown & ~reach).sum()} free but unreachable")
    for label, ok in report:
        print(f"  {'reach' if ok else 'CANNOT REACH'}  {label}")


if __name__ == "__main__":
    main()
