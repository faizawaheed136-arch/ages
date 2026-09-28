"""Check what renders cannot: can a player walk the routes, is anything floating, can the signs be read.

    python sandbox/dealership/walk.py

Reads build/Dealership.ages.model.json (run export.py first), in the builder's own coordinates:
the corner at the origin, +X along the road, +Z away from it, +Y up.

ROUTES. Each is a polyline a visitor walks. A body is a column two studs wide and five tall; at
every half stud along the route the column is sampled at knee, waist and head height, a stud each
side of the line as well as on it, and any part that collides there is a blocker. A route that is
blocked is a door that does not open, a counter across a corridor, a planter in a doorway -- the
bugs a screenshot never shows because nothing looks wrong.

FLOATING. A part with no other part within a twentieth of a stud of it, and not on the ground.
Lights hang from cords and signs from walls, so a floating part is usually a real gap.

SIGNS. Every SurfaceGui's lettering height, estimated the way DealershipBuild.sign() sizes it.
Under 0.35 studs is unreadable from more than a few studs away.
"""

import json
import math
import pathlib

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
MODEL = HERE / "build" / "Dealership.ages.model.json"
CORNER = np.array([-280.0, 1.95, 1940.0])

FLOOR = 0.65
WALK = 0.25
PLAZA = 0.3

# name: (floor height, [(x, z), ...])
ROUTES = {
    "street to the buy circle": (None, [(207, 3), (207, 12), (207, 30), (207, 52)]),
    "buy circle to the lounge": (FLOOR, [(207, 52), (190, 60), (175, 78), (170, 84)]),
    "buy circle to reception": (FLOOR, [(207, 52), (185, 58), (163, 76)]),
    "buy circle to the sales desks": (FLOOR, [(207, 52), (225, 50), (242, 40)]),
    "buy circle to the stair foot": (FLOOR, [(207, 52), (226, 58), (238, 50), (242, 50)]),
    "side door to the handover bay": (None, [(160, 64), (152, 64), (146, 64), (136, 66)]),
    "lot to the side door": (None, [(120, 60), (136, 64), (146, 64)]),
    "garden walk": (None, [(12, 145), (66, 145), (88, 145), (146, 145)]),
    "garden spur to the drop-off": (None, [(136.5, 142), (136.5, 119), (140, 110)]),
    "drop-off to service reception": (None, [(140, 110), (146, 115.4)]),
    "round the engine": (FLOOR, [(176, 58), (188, 58), (188, 68), (176, 68), (176, 58)]),
    "to the build-yours table": (FLOOR, [(222, 60), (226, 66)]),
}


def rotation(cf):
    return np.array(cf["orientation"], float)


def load():
    data = json.load(open(MODEL))
    parts = []

    def walk(node, path):
        name = node.get("name", "Dealership")
        here = f"{path}/{name}" if path else name
        props = node.get("properties", {})
        if node["className"] in ("Part", "WedgePart", "CornerWedgePart", "TrussPart") and "CFrame" in props:
            cf = props["CFrame"]["CFrame"]
            gui = [c for c in node.get("children", []) if c["className"] == "SurfaceGui"]
            parts.append({
                "path": here,
                "pos": np.array(cf["position"], float) - CORNER,
                "rot": rotation(cf),
                "size": np.array(props["Size"], float),
                "collide": props.get("CanCollide", True),
                "transparency": props.get("Transparency", 0),
                "guis": gui,
            })
        for child in node.get("children", []):
            walk(child, here)

    walk(data, "")
    return parts


def half_extents(part):
    # World-axis half extents of the part's oriented box.
    return np.abs(part["rot"]) @ (part["size"] / 2)


def contains(part, point, pad=0.0):
    local = part["rot"].T @ (point - part["pos"])
    return bool(np.all(np.abs(local) <= part["size"] / 2 + pad))


def ground_at(parts, x, z):
    """The highest walkable top under (x, z) below head height: what the visitor stands on."""
    best = 0.0
    for p in parts:
        if not p["collide"]:
            continue
        lo = p["pos"] - p["he"]
        hi = p["pos"] + p["he"]
        if lo[0] <= x <= hi[0] and lo[2] <= z <= hi[2] and hi[1] <= 3.0 and hi[1] > best:
            if contains(p, np.array([x, hi[1] - 0.01, z]), 0.01):
                best = hi[1]
    return best


def check_routes(parts):
    collidable = [p for p in parts if p["collide"]]
    print("ROUTES")
    bad = 0
    for name, (floor, points) in ROUTES.items():
        blockers = {}
        for (x0, z0), (x1, z1) in zip(points, points[1:]):
            length = math.hypot(x1 - x0, z1 - z0)
            steps = max(1, int(length / 0.5))
            dx, dz = (x1 - x0) / length, (z1 - z0) / length
            for i in range(steps + 1):
                t = i / steps
                x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
                base = floor if floor is not None else ground_at(parts, x, z)
                for side in (-1, 0, 1):
                    px, pz = x - dz * side, z + dx * side
                    for h in (1.2, 2.8, 4.6):
                        point = np.array([px, base + h, pz])
                        for p in collidable:
                            lo = p["pos"] - p["he"]
                            hi = p["pos"] + p["he"]
                            if np.all(point >= lo) and np.all(point <= hi) and contains(p, point):
                                key = p["path"]
                                blockers.setdefault(key, (round(px, 1), round(point[1], 1), round(pz, 1)))
        if blockers:
            bad += 1
            print(f"  BLOCKED  {name}")
            for key, at in list(blockers.items())[:8]:
                print(f"           {key}  at {at}")
        else:
            print(f"  clear    {name}")
    return bad


def check_floating(parts):
    print("FLOATING")
    lo = np.array([p["pos"] - p["he"] for p in parts])
    hi = np.array([p["pos"] + p["he"] for p in parts])
    found = 0
    for i, p in enumerate(parts):
        if lo[i][1] <= 0.06:
            continue
        pad = 0.05
        touch = np.all(lo <= hi[i] + pad, axis=1) & np.all(hi >= lo[i] - pad, axis=1)
        touch[i] = False
        if not touch.any():
            found += 1
            if found <= 40:
                print(f"  {p['path']}  at {np.round(p['pos'], 2)}")
    print(f"  {found} floating")
    return found


FACES = {"Front": (0, 1), "Back": (0, 1), "Left": (2, 1), "Right": (2, 1), "Top": (0, 2), "Bottom": (0, 2)}


def check_signs(parts):
    print("SIGNS under 0.35 studs")
    small = 0
    for p in parts:
        for gui in p["guis"]:
            face = gui.get("properties", {}).get("Face", "Front")
            across_i, up_i = FACES.get(face, (0, 1))
            across, up = p["size"][across_i], p["size"][up_i]
            for label in gui.get("children", []):
                text = label.get("properties", {}).get("Text", "")
                lines = text.split("\n") if text else [""]
                longest = max(1, max(len(line) for line in lines))
                studs = min(up / len(lines), across / (0.72 * longest))
                if studs < 0.35:
                    small += 1
                    print(f"  {studs:.2f}  {p['path']}  {text!r}")
    print(f"  {small} small")
    return small


def main():
    parts = load()
    for p in parts:
        p["he"] = half_extents(p)
    print(f"{len(parts)} parts")
    check_routes(parts)
    check_floating(parts)
    check_signs(parts)


if __name__ == "__main__":
    main()
