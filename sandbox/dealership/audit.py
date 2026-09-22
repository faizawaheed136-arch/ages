"""Find the faces in the exported dealership that will flicker in Roblox.

    python sandbox/dealership/audit.py [--all]

Two visible parts whose faces lie in the same plane, facing the same way, and overlap, z-fight:
the engine cannot decide which is in front and draws both, alternating, as the camera moves. The
builder lays about 1,400 parts by hand-typed coordinates and it is easy to do -- a pier whose face
is flush with the wall it stands on, two parapet runs that both reach the corner. Neither the
preview nor check.py can see it; this can.

What it leaves out, because no camera finds it:
  * overlaps thinner than MIN_SPAN either way;
  * undersides less than a stud off the ground, which nobody can get under to see;
  * overlaps that a third, opaque block hides -- one pressed flat against them, or one they are
    both buried in, like a slat and its backing both flush with the wall behind them.
Pairs that look the same (colour and material) are reported apart and only with --all: two
identical smooth faces fighting draw the same pixels either way.

Only blocks are checked; discs and balls have no flat faces to share bar a disc's caps, which are
stepped over the floor on purpose. Parts turned other than by quarter turns are skipped. The exit
status is the number of findings that look different, so it can gate an export.
"""

import json
import pathlib
import sys

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
BUILD = HERE / "build"
EPS = 0.002  # studs: closer than this and two faces are one plane
MIN_SPAN = 0.1  # studs: an overlap thinner than this either way is a sliver


def walk(node, path, out):
    name = node.get("name", "Dealership")
    here = f"{path}/{name}" if path else name
    props = node.get("properties", {})
    transparency = props.get("Transparency", 0)
    if node.get("className") == "Part" and props.get("Shape", "Block") == "Block" and transparency < 0.97:
        cf = props["CFrame"]["CFrame"]
        rot = np.array(cf["orientation"], float)
        if np.allclose(np.abs(rot), np.round(np.abs(rot)), atol=1e-4):
            half = np.abs(rot) @ (np.array(props.get("Size", [4, 1, 2]), float) / 2)
            centre = np.array(cf["position"], float)
            look = (tuple(props.get("Color", [])), props.get("Material", "Plastic"))
            out.append((here, centre - half, centre + half, look, transparency == 0))
    for child in node.get("children", []):
        walk(child, here, out)


def hidden(lo, hi, opaque, axis, side, plane, rect_lo, rect_hi, skip):
    """Whether one opaque block covers the whole overlap: pressed against it, or around it."""
    others = [a for a in range(3) if a != axis]
    near = lo[:, axis] if side == "+" else hi[:, axis]
    pressed = np.abs(near - plane) <= EPS
    around = (lo[:, axis] < plane - EPS) & (hi[:, axis] > plane + EPS)
    covers = opaque & (pressed | around)
    for a, r0, r1 in zip(others, rect_lo, rect_hi):
        covers &= (lo[:, a] <= r0 + EPS) & (hi[:, a] >= r1 - EPS)
    covers[list(skip)] = False
    return bool(covers.any())


def findings(boxes):
    lo = np.array([b[1] for b in boxes])
    hi = np.array([b[2] for b in boxes])
    opaque = np.array([b[4] for b in boxes])
    found = []
    for axis in range(3):
        others = [a for a in range(3) if a != axis]
        for side, faces in (("-", lo[:, axis]), ("+", hi[:, axis])):
            order = np.argsort(faces)
            for k, i in enumerate(order):
                for j in order[k + 1 :]:
                    if faces[j] - faces[i] > EPS:
                        break
                    if axis == 1 and side == "-" and faces[i] < 1:
                        continue  # the underside of anything within a stud of the ground
                    r0 = [max(lo[i, a], lo[j, a]) for a in others]
                    r1 = [min(hi[i, a], hi[j, a]) for a in others]
                    if min(b - a for a, b in zip(r0, r1)) < MIN_SPAN:
                        continue
                    if hidden(lo, hi, opaque, axis, side, faces[i], r0, r1, (i, j)):
                        continue
                    area = (r1[0] - r0[0]) * (r1[1] - r0[1])
                    found.append((area, "xyz"[axis] + side, faces[i], i, j))
    return found


def main() -> int:
    show_all = "--all" in sys.argv
    doc = json.loads((BUILD / "Dealership.sandbox.model.json").read_text(encoding="utf-8"))
    boxes = []
    walk(doc, "", boxes)
    # One line per pair of part names and face: a row of forty ribs is one mistake, not forty.
    groups = {}
    for area, face, at, i, j in findings(boxes):
        same = boxes[i][3] == boxes[j][3]
        a, b = sorted((boxes[i][0], boxes[j][0]))
        key = (same, a, b, face)
        total, count, where = groups.get(key, (0.0, 0, at))
        groups[key] = (total + area, count + 1, where)
    different = 0
    for (same, a, b, face), (total, count, at) in sorted(groups.items(), key=lambda kv: (kv[0][0], -kv[1][0])):
        if same and not show_all:
            continue
        different += 0 if same else count
        tag = "same   " if same else "DIFFERS"
        print(f"{tag} {total:8.2f} sq studs  x{count:<3} {face} at {at:8.2f}   {a}  |  {b}")
    same_count = sum(c for (s, *_), (_, c, _) in groups.items() if s)
    print(f"{len(boxes)} blocks checked: {different} overlaps that look different, {same_count} that look the same")
    return min(different, 255)


if __name__ == "__main__":
    sys.exit(main())
