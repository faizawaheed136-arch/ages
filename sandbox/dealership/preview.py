"""Draw the exported dealership from a few camera positions, without Studio.

    python sandbox/dealership/preview.py [out_dir] [view,view@night,...]

Reads build/*.model.json (run export.py first) and rasterises every visible part -- blocks,
cylinders, balls and wedges -- with sun shading, translucent glass, glowing neon, sign text and
outlines, into one PNG per view. Add @night to a view's name for the same camera after dark: a
dim moon, every PointLight and SpotLight in the build lighting what is in its range, neon and lit
signs glowing through a bloom.

It is not Roblox's renderer and makes no attempt to be: no shadows (the builder's lights cast
none either), no materials, Arial standing in for Gotham. It is for judging massing, layout,
proportion, colour, signage and where the light falls, which is most of design review, on a
machine where Studio is not available.
"""

import json
import math
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = pathlib.Path(__file__).resolve().parent
BUILD = HERE / "build"

WIDTH, HEIGHT = 1280, 720
FOV = math.radians(62)
SUN = np.array([0.45, 0.8, 0.38])
SUN = SUN / np.linalg.norm(SUN)
AMBIENT = 0.5

# After dark: a low blue ambient and a faint moon, so unlit ground is readable but dark.
MOON = np.array([-0.35, 0.8, -0.3])
MOON = MOON / np.linalg.norm(MOON)
NIGHT_AMBIENT = np.array([0.075, 0.085, 0.12])
NIGHT_MOON = np.array([0.07, 0.08, 0.11])
LIGHT_GAIN = 0.85  # what a lamp of Brightness 1 adds at its own position, before falloff

FONTS = {
    "Heavy": "C:/Windows/Fonts/ariblk.ttf",
    "Bold": "C:/Windows/Fonts/arialbd.ttf",
    "Medium": "C:/Windows/Fonts/arial.ttf",
    "Regular": "C:/Windows/Fonts/arial.ttf",
}

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
    "handover": ((98, 7.5, 40), (140, 6, 66)),
    "cabin": ((30, 6.5, 68), (22, 4, 92)),
    "street": ((110, 5.5, -30), (200, 9, 30)),  # across the road, at a player's eye
    "bays": ((186, 8, 99), (214, 6, 120)),  # the workshop from the service lane
    "mezz": ((242, 19, 86), (205, 6, 42)),  # from the gallery, over the rail
    "hall": ((182, 5.5, 30), (214, 15, 90)),  # a player inside the doors, looking up the hall
    "deckside": ((196, 6, 36), (256, 13, 58)),  # across the hall to the east deck, stair and lift
    "deck": ((249, 18.5, 75), (238, 11, 30)),  # on the east deck by the lounge, looking to the front
    "westdeck": ((196, 7, 70), (156, 4, 38)),  # the raised display deck and the counter
    "buy": ((207, 7.5, 50), (207, 5, 72)),  # walking up the runway to the buy desk
    "salesman": ((205, 6.3, 60), (207, 5.7, 72)),  # close on the man at the desk
    # The cars, close: each style's front three-quarters, and one from behind.
    "car_sedan": ((51, 6.5, 11), (59.5, 2.6, 24)),
    "car_coupe": ((40, 6, 11), (48.5, 2.3, 24)),
    "car_suv": ((29, 8, 10), (37.5, 3.1, 24)),
    "car_pickup": ((18, 8, 10), (26.5, 3.1, 24)),
    "car_wagon": ((7, 7, 11), (15.5, 2.8, 24)),
    "car_rear": ((66, 6.5, 39), (59.5, 2.6, 24)),
    "car_super": ((169, 6.5, 29), (178, 3, 44)),
    "car_roadster": ((237, 7, 29), (228, 3, 44)),
    "car_gt": ((167, 8, 29), (157.5, 4, 42.5)),
    # Floor plans of the showroom: straight down, everything above the cut left out.
    "plan": ((207, 150, 59.9), (207, 0, 60), 29),  # under the ceiling: the upper floor
    "plan0": ((207, 150, 59.9), (207, 0, 60), 12),  # under the upper floor: the showroom floor
    # The grand pass: the garden, the back of house, the new floor pieces.
    "garden": ((77, 16, 112), (77, 3, 150)),  # from the drop-off end, down the garden walk
    "gardenhigh": ((30, 55, 100), (90, 0, 150)),
    "backhouse": ((190, 14, 205), (205, 8, 150)),  # the service block's back wall from the far lawn
    "engine": ((190, 7.5, 70), (182, 3, 63)),
    "buildyours": ((226, 7, 60), (236.6, 5.5, 67)),
    "doors": ((207, 6, 40), (207, 5, 16)),
    "store": ((180, 6.5, 30), (170, 3.5, 21)),
    "kids": ((224, 6, 30), (233, 1.5, 22)),
    "solar": ((150, 40, 100), (205, 19, 132)),
    "lotnight": ((54, 22, -20), (54, 2, 46)),  # from inside, looking back at the doors and their screens
    # The whole site from straight above, roofs on: where the grounds have room.
    "site": ((155, 330, 89.9), (155, 0, 90), 80),
}

# SurfaceGui faces, in the part's own axes: the outward normal, the gui's x axis and its down
# axis, the corner the gui starts from (as signs of half the size), and which sizes it spans.
# Top reads from local -Z, the side the builder puts the road.
FACES = {
    "Front": ((0, 0, -1), (-1, 0, 0), (0, -1, 0), (1, 1, -1), (0, 1)),
    "Back": ((0, 0, 1), (1, 0, 0), (0, -1, 0), (-1, 1, 1), (0, 1)),
    "Left": ((-1, 0, 0), (0, 0, 1), (0, -1, 0), (-1, 1, -1), (2, 1)),
    "Right": ((1, 0, 0), (0, 0, -1), (0, -1, 0), (1, 1, 1), (2, 1)),
    "Top": ((0, 1, 0), (-1, 0, 0), (0, 0, -1), (1, 1, 1), (0, 2)),
}
SPOT_FACES = {"Bottom": (0, -1, 0), "Top": (0, 1, 0), "Front": (0, 0, -1), "Back": (0, 0, 1), "Left": (-1, 0, 0), "Right": (1, 0, 0)}


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


class Scene:
    """Every visible part, every light and every sign in the exported model files."""

    def __init__(self, documents):
        self.parts, self.lights, self.signs = [], [], []
        for doc in documents:
            self.walk(doc)

    def walk(self, node):
        props = node.get("properties", {})
        if node.get("className") in ("Part", "Seat", "WedgePart") and "CFrame" in props:
            pos, rot = cframe(props["CFrame"])
            size = np.array(props.get("Size", [4, 1, 2]), float)
            # A character's head: the Head mesh draws as a ball the height of the scaled part.
            for child in node.get("children", []):
                mesh = child.get("properties", {})
                if child.get("className") == "SpecialMesh" and mesh.get("MeshType") == "Head":
                    diameter = size[1] * mesh.get("Scale", [1, 1, 1])[1]
                    props = dict(props, Shape="Ball")
                    size = np.array([diameter, diameter, diameter])
            if props.get("Transparency", 0) < 0.97:
                self.parts.append((node["className"], props, pos, rot, size))
            for child in node.get("children", []):
                self.attached(child, pos, rot, size)
        for child in node.get("children", []):
            self.walk(child)

    def attached(self, child, pos, rot, size):
        cls, props = child.get("className"), child.get("properties", {})
        if cls in ("PointLight", "SpotLight"):
            direction = None
            if cls == "SpotLight":
                direction = rot @ np.array(SPOT_FACES[props.get("Face", "Front")], float)
            self.lights.append(
                {
                    "pos": pos,
                    "colour": np.array(props.get("Color", [1, 1, 1]), float),
                    "brightness": float(props.get("Brightness", 1)),
                    "range": float(props.get("Range", 8)),
                    "direction": direction,
                    "angle": math.radians(float(props.get("Angle", 90))),
                }
            )
        elif cls == "SurfaceGui" and props.get("Face", "Front") in FACES:
            for label in child.get("children", []):
                if label.get("className") != "TextLabel":
                    continue
                lp = label.get("properties", {})
                if not lp.get("Text", "").strip():
                    continue
                self.signs.append(
                    {
                        "pos": pos,
                        "rot": rot,
                        "size": size,
                        "face": props.get("Face", "Front"),
                        "pps": float(props.get("PixelsPerStud", 50)),
                        "glow": float(props.get("LightInfluence", 1)) < 0.5,
                        "text": lp["Text"],
                        "colour": np.array(lp.get("TextColor3", [0, 0, 0]), float),
                        "weight": lp.get("FontFace", {}).get("weight", "Regular"),
                    }
                )

    def triangles(self):
        verts, colours, alphas, glows, ids = [], [], [], [], []
        for index, (cls, p, pos, rot, size) in enumerate(self.parts):
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


def pixel_rays(view, focal):
    """The world direction through every pixel centre, scaled so its depth from the camera is 1."""
    xs = (np.arange(WIDTH) + 0.5 - WIDTH / 2) / focal
    ys = -(np.arange(HEIGHT) + 0.5 - HEIGHT / 2) / focal
    cam = np.stack(np.broadcast_arrays(xs[None, :], ys[:, None], -np.ones((HEIGHT, WIDTH))), axis=-1)
    return cam @ view


def draw_triangles(indices, cam, focal, colours, alphas, ids, image, depth, owner, which):
    near = 0.3
    for i in indices:
        polygon = cam[i]
        if np.all(polygon[:, 2] > -near):
            continue
        polygon = clip_near(polygon, near)
        if len(polygon) < 3:
            continue
        for k in range(1, len(polygon) - 1):
            raster(np.array([polygon[0], polygon[k], polygon[k + 1]]), focal, colours[i], alphas[i], ids[i], i, image, depth, owner, which)


def render(scene, geometry, eye, target, night=False, cut=None):
    tris, colours, alphas, glows, ids = geometry
    if cut is not None:
        keep = tris[:, :, 1].min(axis=1) < cut
        tris, colours, alphas, glows, ids = tris[keep], colours[keep], alphas[keep], glows[keep], ids[keep]
    origin, view = camera(eye, target)
    focal = (HEIGHT / 2) / math.tan(FOV / 2)
    cam = (tris - origin) @ view.T  # camera space: x right, y up, looking down -z
    normals = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    lengths = np.linalg.norm(normals, axis=1, keepdims=True)
    normals = normals / np.where(lengths == 0, 1, lengths)
    # Two-sided: face each triangle toward the camera before lighting it.
    toward = origin - tris.mean(axis=1)
    normals *= np.sign(np.sum(normals * toward, axis=1, keepdims=True) + 1e-9)
    # By day each triangle is lit flat by the sun; by night the light is worked out per pixel
    # below, so here each carries its own colour.
    shade = np.ones(len(tris)) if night else AMBIENT + (1 - AMBIENT) * np.clip(normals @ SUN, 0, 1)
    lit = np.where(glows[:, None], np.clip(colours * 1.25 + 0.08, 0, 1), colours * shade[:, None])

    image = np.zeros((HEIGHT, WIDTH, 3))
    if night:
        sky_top, sky_bottom = np.array([0.02, 0.03, 0.07]), np.array([0.07, 0.08, 0.14])
    else:
        sky_top, sky_bottom = np.array([0.46, 0.64, 0.86]), np.array([0.82, 0.88, 0.94])
    t = np.linspace(0, 1, HEIGHT)[:, None]
    image[:] = (sky_top * (1 - t) + sky_bottom * t)[:, None, :]
    depth = np.full((HEIGHT, WIDTH), np.inf)
    owner = np.zeros((HEIGHT, WIDTH), int)
    which = np.full((HEIGHT, WIDTH), -1)

    order = np.arange(len(tris))
    opaque = alphas >= 0.99
    draw_triangles(order[opaque], cam, focal, lit, alphas, ids, image, depth, owner, which)

    rays = pixel_rays(view, focal)
    solid = which >= 0
    tri_at = np.maximum(which, 0)
    # How lit each pixel is against its own colour: what an unlit sign on that face gets.
    factor = np.ones((HEIGHT, WIDTH, 1))
    factor[solid, 0] = shade[tri_at[solid]]
    bloom = np.zeros((HEIGHT, WIDTH, 3))
    if night:
        glowing = solid & glows[tri_at]
        unlit = solid & ~glowing
        lighting = night_light(scene, rays, depth, unlit, normals[tri_at], origin)
        image[unlit] *= lighting[unlit]
        factor[unlit, 0] = lighting[unlit].mean(axis=1)
        bloom[glowing] = image[glowing]

    for sign in scene.signs:
        if cut is None or sign["pos"][1] < cut:
            draw_sign(sign, image, depth, factor, bloom, origin, rays, night)

    # Translucent parts over everything opaque, far to near. After dark glass is only as bright
    # as the little light it catches.
    translucent = order[~opaque]
    translucent = translucent[np.argsort(cam[translucent, :, 2].mean(axis=1))]
    glass = lit.copy()
    if night:
        glass[~glows] *= 0.22
    draw_triangles(translucent, cam, focal, glass, alphas, ids, image, depth, owner, which)

    # Outlines where one part meets another or the depth jumps: what makes flat colour read as form.
    edge = np.zeros((HEIGHT, WIDTH), bool)
    edge[:, 1:] |= owner[:, 1:] != owner[:, :-1]
    edge[1:, :] |= owner[1:, :] != owner[:-1, :]
    finite = np.where(np.isfinite(depth), depth, 1e6)
    jump = np.zeros((HEIGHT, WIDTH), bool)
    jump[:, 1:] |= np.abs(finite[:, 1:] - finite[:, :-1]) > 0.06 * finite[:, 1:]
    jump[1:, :] |= np.abs(finite[1:, :] - finite[:-1, :]) > 0.06 * finite[1:, :]
    image[edge] *= 0.85 if night else 0.78
    image[jump] *= 0.75 if night else 0.6

    if night:
        # Bloom: what makes neon and lit lettering read as light rather than as bright paint.
        src = Image.fromarray((np.clip(bloom, 0, 1) * 255).astype(np.uint8))
        for radius, gain in ((3, 0.5), (12, 0.55), (30, 0.3)):
            image += np.asarray(src.filter(ImageFilter.GaussianBlur(radius)), float) / 255 * gain
    return Image.fromarray((np.clip(image, 0, 1) * 255).astype(np.uint8))


def night_light(scene, rays, depth, mask, pixel_normals, origin):
    """The light reaching each pixel in `mask` after dark: ambient, moon, and every lamp in range."""
    total = np.zeros((HEIGHT, WIDTH, 3))
    normals = pixel_normals[mask]
    points = origin + rays[mask] * depth[mask][:, None]
    add = NIGHT_AMBIENT + NIGHT_MOON * np.clip(normals @ MOON, 0, 1)[:, None]
    for light in scene.lights:
        offset = light["pos"] - points
        dist = np.linalg.norm(offset, axis=1)
        reach = dist < light["range"]
        if not reach.any():
            continue
        d = dist[reach]
        unit = offset[reach] / np.maximum(d, 1e-6)[:, None]
        strength = (1 - d / light["range"]) ** 1.6 * light["brightness"] * LIGHT_GAIN
        strength *= np.clip(np.sum(normals[reach] * unit, axis=1), 0, 1)
        if light["direction"] is not None:
            cos = unit @ -light["direction"]
            edge = math.cos(min(light["angle"], math.pi * 0.999) / 2)
            strength *= np.clip((cos - edge) / max(1 - edge, 1e-3) * 3, 0, 1)
        add[reach] += strength[:, None] * light["colour"]
    total[mask] = np.clip(add, 0, 1.6)
    return total


_textures = {}


def sign_texture(sign, across, up):
    """The sign's lettering as an alpha mask, laid out as TextScaled lays it: the largest size,
    to 100 gui pixels, at which the block fits the label."""
    key = (sign["text"], sign["weight"], round(across, 3), round(up, 3), sign["pps"])
    if key in _textures:
        return _textures[key]
    gui_w, gui_h = across * sign["pps"], up * sign["pps"]
    path = FONTS.get(sign["weight"], FONTS["Regular"])
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    lo, hi = 1, 100
    while lo < hi:
        mid = (lo + hi + 1) // 2
        box = probe.multiline_textbbox((0, 0), sign["text"], font=ImageFont.truetype(path, mid), align="center", spacing=mid * 0.1)
        if box[2] - box[0] <= gui_w * 0.98 and box[3] - box[1] <= gui_h * 0.98:
            lo = mid
        else:
            hi = mid - 1
    scale = 640 / max(gui_w, gui_h)  # sampled at a steady resolution, whatever the gui's size
    w, h = max(int(gui_w * scale), 1), max(int(gui_h * scale), 1)
    size = max(int(lo * scale), 1)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).multiline_text(
        (w / 2, h / 2), sign["text"], fill=255, font=ImageFont.truetype(path, size), anchor="mm", align="center", spacing=size * 0.1
    )
    _textures[key] = np.asarray(mask, float) / 255
    return _textures[key]


def draw_sign(sign, image, depth, factor, bloom, origin, rays, night):
    normal, gx, gy, corner, spans = FACES[sign["face"]]
    rot, size, pos = sign["rot"], sign["size"], sign["pos"]
    n = rot @ np.array(normal, float)
    ax, ay = rot @ np.array(gx, float), rot @ np.array(gy, float)
    top_left = pos + rot @ (np.array(corner, float) * size / 2)
    if np.dot(n, origin - top_left) <= 0:
        return  # the face looks away from the camera
    across, up = size[spans[0]], size[spans[1]]
    # Every pixel's ray meets the face's plane at depth t, rays being scaled to depth 1; the
    # lettering shows where that is no deeper than whatever was drawn there.
    denom = rays @ n
    with np.errstate(divide="ignore", invalid="ignore"):
        t = np.dot(n, top_left - origin) / denom
    ok = np.isfinite(t) & (t > 0.3) & (t <= depth + np.maximum(0.06, 0.004 * t))
    if not ok.any():
        return
    ys, xs = np.nonzero(ok)
    hit = origin + rays[ys, xs] * t[ys, xs][:, None]
    u = (hit - top_left) @ ax / across
    v = (hit - top_left) @ ay / up
    inside = (u >= 0) & (u < 1) & (v >= 0) & (v < 1)
    if not inside.any():
        return
    ys, xs, u, v = ys[inside], xs[inside], u[inside], v[inside]
    mask = sign_texture(sign, across, up)
    th, tw = mask.shape
    alpha = mask[np.minimum((v * th).astype(int), th - 1), np.minimum((u * tw).astype(int), tw - 1)]
    keep = alpha > 0.02
    ys, xs, alpha = ys[keep], xs[keep], alpha[keep][:, None]
    colour = np.clip(sign["colour"] * 1.15, 0, 1) if sign["glow"] else sign["colour"] * factor[ys, xs]
    image[ys, xs] = image[ys, xs] * (1 - alpha) + colour * alpha
    if night and sign["glow"]:
        bloom[ys, xs] = np.maximum(bloom[ys, xs], colour * alpha)


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


def raster(tri, focal, colour, alpha, part_id, tri_id, image, depth, owner, which):
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
        which[y0 : y1 + 1, x0 : x1 + 1][closer] = tri_id
    else:
        target[closer] = target[closer] * (1 - alpha) + colour * alpha


def main() -> int:
    out_dir = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else BUILD / "preview"
    out_dir.mkdir(parents=True, exist_ok=True)
    documents = [json.loads((BUILD / name).read_text(encoding="utf-8")) for name in ("Dealership.sandbox.model.json", "SandboxSite.model.json")]
    scene = Scene(documents)
    geometry = scene.triangles()
    print(f"{len(geometry[0])} triangles, {len(scene.lights)} lights, {len(scene.signs)} signs")
    wanted = sys.argv[2].split(",") if len(sys.argv) > 2 else list(VIEWS)
    for name in wanted:
        view, _, mode = name.partition("@")
        eye, target, *cut = VIEWS[view]
        out = f"{view}-{mode}.png" if mode else f"{view}.png"
        render(scene, geometry, eye, target, night=mode == "night", cut=cut[0] if cut else None).save(out_dir / out)
        print(f"  {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
