"""Draw the exported dealership from a few camera positions, without Studio.

    python sandbox/dealership/preview.py [out_dir]

Reads build/*.model.json (run export.py first) and rasterises every visible part -- blocks,
cylinders, balls and wedges -- with sun shading, translucent glass, glowing neon and outlines, into
one PNG per view. It is not Roblox's renderer and makes no attempt to be: no shadows, no local
lights, no sign text. It is for judging massing, layout, proportion and colour, which is most of
design review, on a machine where Studio is not available.
"""

import json
import math
import pathlib
import sys

import numpy as np
from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
BUILD = HERE / "build"

WIDTH, HEIGHT = 1280, 720
FOV = math.radians(62)
SUN = np.array([0.45, 0.8, 0.38])
SUN = SUN / np.linalg.norm(SUN)
AMBIENT = 0.5

# name: (eye, target)
VIEWS = {
    "frontage": ((40, 34, -95), (160, 6, 45)),
    "showroom": ((207, 13, -34), (207, 11, 40)),
    "lot": ((30, 38, -46), (80, 2, 62)),
    "aerial": ((140, 230, -150), (140, 0, 58)),
    "interior": ((207, 9.5, 25), (207, 5, 80)),
    "counter": ((214, 11, 48), (162, 4, 84)),
    "east": ((330, 40, 30), (205, 8, 60)),
    "service": ((118, 16, 104), (240, 7, 112)),
    "rear": ((207, 40, 230), (207, 8, 120)),
    "parking": ((279, 14, -6), (296, 2, 70)),
    "lotfront": ((40, 5.5, -16), (55, 5, 30)),  # a player on the far pavement
    "wash": ((262, 9, 103), (292, 6, 124)),  # from the service lane
    "vacuum": ((250, 12, 186), (286, 4, 150)),
}


def cframe(value):
    cf = value["CFrame"] if "CFrame" in value else value
    return np.array(cf["position"], float), np.array(cf["orientation"], float)


def box_mesh(size):
    x, y, z = size / 2
    v = np.array([[sx * x, sy * y, sz * z] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)])
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    tris = [t for a, b, c, d in quads for t in ((a, b, c), (a, c, d))]
    return v, tris


def cylinder_mesh(size, segments=18):
    length, radius = size[0], min(size[1], size[2]) / 2
    ring = [(math.cos(2 * math.pi * i / segments) * radius, math.sin(2 * math.pi * i / segments) * radius) for i in range(segments)]
    v = [(-length / 2, a, b) for a, b in ring] + [(length / 2, a, b) for a, b in ring] + [(-length / 2, 0, 0), (length / 2, 0, 0)]
    tris = []
    for i in range(segments):
        j = (i + 1) % segments
        tris += [(i, j, segments + j), (i, segments + j, segments + i)]
        tris += [(2 * segments, j, i), (2 * segments + 1, segments + i, segments + j)]
    return np.array(v, float), tris


def ball_mesh(size, rings=7, segments=12):
    radius = min(size) / 2
    v = []
    for r in range(rings + 1):
        phi = math.pi * r / rings
        for s in range(segments):
            theta = 2 * math.pi * s / segments
            v.append((radius * math.sin(phi) * math.cos(theta), radius * math.cos(phi), radius * math.sin(phi) * math.sin(theta)))
    tris = []
    for r in range(rings):
        for s in range(segments):
            a, b = r * segments + s, r * segments + (s + 1) % segments
            c, d = a + segments, b + segments
            tris += [(a, c, b), (b, c, d)]
    return np.array(v, float), tris


def wedge_mesh(size):
    x, y, z = size / 2
    # Roblox's wedge: full bottom and back faces, the slope running from the top back edge down to
    # the bottom front edge.
    v = np.array([[-x, -y, -z], [x, -y, -z], [-x, -y, z], [x, -y, z], [-x, y, z], [x, y, z]])
    tris = [(0, 2, 3), (0, 3, 1), (2, 4, 5), (2, 5, 3), (0, 1, 5), (0, 5, 4), (0, 4, 2), (1, 3, 5)]
    return v, tris


def parts(node, out):
    cls = node.get("className")
    props = node.get("properties", {})
    if cls in ("Part", "WedgePart") and props.get("Transparency", 0) < 0.97:
        out.append((cls, props))
    for child in node.get("children", []):
        parts(child, out)


def triangles(documents):
    """Every visible triangle in world space, with its colour, opacity and whether it glows."""
    found = []
    for doc in documents:
        parts(doc, found)
    verts, colours, alphas, glows, ids = [], [], [], [], []
    for index, (cls, p) in enumerate(found):
        size = np.array(p.get("Size", [4, 1, 2]), float)
        if "CFrame" not in p:
            continue
        pos, rot = cframe(p["CFrame"])
        shape = p.get("Shape", "Block")
        if cls == "WedgePart":
            v, tris = wedge_mesh(size)
        elif shape == "Cylinder":
            v, tris = cylinder_mesh(size)
        elif shape == "Ball":
            v, tris = ball_mesh(size)
        else:
            v, tris = box_mesh(size)
        world = v @ rot.T + pos
        colour = np.array(p.get("Color", [0.64, 0.64, 0.64]), float)
        alpha = 1 - float(p.get("Transparency", 0))
        glow = p.get("Material") == "Neon"
        for t in tris:
            verts.append(world[list(t)])
            colours.append(colour)
            alphas.append(alpha)
            glows.append(glow)
            ids.append(index + 1)
    return np.array(verts), np.array(colours), np.array(alphas), np.array(glows), np.array(ids)


def camera(eye, target):
    eye, target = np.array(eye, float), np.array(target, float)
    forward = target - eye
    forward /= np.linalg.norm(forward)
    right = np.cross(forward, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, forward)
    return eye, np.stack([right, up, -forward])


def render(tris, colours, alphas, glows, ids, eye, target):
    origin, view = camera(eye, target)
    cam = (tris - origin) @ view.T  # camera space: x right, y up, looking down -z
    normals = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    lengths = np.linalg.norm(normals, axis=1, keepdims=True)
    normals = normals / np.where(lengths == 0, 1, lengths)
    # Two-sided: face each triangle toward the camera before lighting it.
    toward = origin - tris.mean(axis=1)
    normals *= np.sign(np.sum(normals * toward, axis=1, keepdims=True) + 1e-9)
    shade = AMBIENT + (1 - AMBIENT) * np.clip(normals @ SUN, 0, 1)
    lit = np.where(glows[:, None], np.clip(colours * 1.25 + 0.08, 0, 1), colours * shade[:, None])

    focal = (HEIGHT / 2) / math.tan(FOV / 2)
    image = np.zeros((HEIGHT, WIDTH, 3))
    sky_top, sky_bottom = np.array([0.46, 0.64, 0.86]), np.array([0.82, 0.88, 0.94])
    t = np.linspace(0, 1, HEIGHT)[:, None]
    image[:] = (sky_top * (1 - t) + sky_bottom * t)[:, None, :]
    depth = np.full((HEIGHT, WIDTH), np.inf)
    owner = np.zeros((HEIGHT, WIDTH), int)

    near = 0.3
    order = np.arange(len(tris))
    opaque = alphas >= 0.99
    # Opaque first, then translucent from far to near over them.
    translucent = order[~opaque]
    translucent = translucent[np.argsort(cam[translucent, :, 2].mean(axis=1))]
    for pass_order in (order[opaque], translucent):
        for i in pass_order:
            polygon = cam[i]
            if np.all(polygon[:, 2] > -near):
                continue
            polygon = clip_near(polygon, near)
            if len(polygon) < 3:
                continue
            for k in range(1, len(polygon) - 1):
                raster(np.array([polygon[0], polygon[k], polygon[k + 1]]), focal, lit[i], alphas[i], ids[i], image, depth, owner)

    # Outlines where one part meets another or the depth jumps: what makes flat colour read as form.
    edge = np.zeros((HEIGHT, WIDTH), bool)
    edge[:, 1:] |= owner[:, 1:] != owner[:, :-1]
    edge[1:, :] |= owner[1:, :] != owner[:-1, :]
    finite = np.where(np.isfinite(depth), depth, 1e6)
    jump = np.zeros((HEIGHT, WIDTH), bool)
    jump[:, 1:] |= np.abs(finite[:, 1:] - finite[:, :-1]) > 0.06 * finite[:, 1:]
    jump[1:, :] |= np.abs(finite[1:, :] - finite[:-1, :]) > 0.06 * finite[1:, :]
    image[edge] *= 0.78
    image[jump] *= 0.6
    return Image.fromarray((np.clip(image, 0, 1) * 255).astype(np.uint8))


def clip_near(polygon, near):
    out = []
    for a, b in zip(polygon, np.roll(polygon, -1, axis=0)):
        a_in, b_in = a[2] <= -near, b[2] <= -near
        if a_in:
            out.append(a)
        if a_in != b_in:
            t = (-near - a[2]) / (b[2] - a[2])
            out.append(a + (b - a) * t)
    return np.array(out)


def raster(tri, focal, colour, alpha, part_id, image, depth, owner):
    z = -tri[:, 2]
    sx = WIDTH / 2 + tri[:, 0] / z * focal
    sy = HEIGHT / 2 - tri[:, 1] / z * focal
    x0, x1 = max(int(math.floor(sx.min())), 0), min(int(math.ceil(sx.max())), WIDTH - 1)
    y0, y1 = max(int(math.floor(sy.min())), 0), min(int(math.ceil(sy.max())), HEIGHT - 1)
    if x0 > x1 or y0 > y1:
        return
    area = (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0])
    if abs(area) < 1e-9:
        return
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    w0 = ((sx[1] - xs) * (sy[2] - ys) - (sx[2] - xs) * (sy[1] - ys)) / area
    w1 = ((sx[2] - xs) * (sy[0] - ys) - (sx[0] - xs) * (sy[2] - ys)) / area
    w2 = 1 - w0 - w1
    inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
    if not inside.any():
        return
    # Perspective-correct depth: interpolate 1/z across the screen.
    inv = w0 / z[0] + w1 / z[1] + w2 / z[2]
    pixel_depth = 1 / np.where(inv == 0, 1e-9, inv)
    region = depth[y0 : y1 + 1, x0 : x1 + 1]
    closer = inside & (pixel_depth < region)
    if not closer.any():
        return
    target = image[y0 : y1 + 1, x0 : x1 + 1]
    if alpha >= 0.99:
        target[closer] = colour
        region[closer] = pixel_depth[closer]
        owner[y0 : y1 + 1, x0 : x1 + 1][closer] = part_id
    else:
        target[closer] = target[closer] * (1 - alpha) + colour * alpha


def main() -> int:
    out_dir = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else BUILD / "preview"
    out_dir.mkdir(parents=True, exist_ok=True)
    documents = [json.loads((BUILD / name).read_text(encoding="utf-8")) for name in ("Dealership.sandbox.model.json", "SandboxSite.model.json")]
    tris, colours, alphas, glows, ids = triangles(documents)
    print(f"{len(tris)} triangles")
    wanted = sys.argv[2].split(",") if len(sys.argv) > 2 else list(VIEWS)
    for name in wanted:
        eye, target = VIEWS[name]
        render(tris, colours, alphas, glows, ids, eye, target).save(out_dir / f"{name}.png")
        print(f"  {name}.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
