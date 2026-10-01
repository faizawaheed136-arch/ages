"""Writes assets/vehicles/<id>.rbxmx for every car of the imported pack, and the catalog block of
src/server/content/Vehicles.luau.

    python tools/gen_car_pack.py

WHERE THE DATA COMES FROM. The owner imported a pack of cars (a Sketchfab parking-lot scene, through
Studio's 3D importer, which uploads each mesh and texture to their account) into the dealership
sandbox on 2026-09-30. Every car in it is two to four meshes -- body shell, doors and trim, interior
and wheels -- merged by material, with the four wheels baked into one of them. tools/car_pack_data.json
is the record of that import: each part's MeshId, ColorMap and TexturePack, size and place, read off the
saved place, and what was found by reading the meshes themselves (their connected pieces: the four
wheels of every car, the roof). Nothing here is invented -- the ids are the ones the importer made.

WHAT IT MAKES. Each car as a template for shared/MeshCar, in the same shape as the GT-R's
(tools/gen_gtr_model.py): metres, nose to -Z, parts named for what they are. The body parts are the
import's own, turned to face -Z (every car lay in the lot at its own angle). Painting is by tint: a
SurfaceAppearance named Tint on every body part carries the part's own texture, and the paint colour
multiplies it, so the white cars of the pack take any colour whole and the dark shut-lines, glass and
trim stay dark.

THE WHEELS. They are baked into the interior mesh and cannot turn or steer there. So each car's four
wheels are laid over them: the GT-R's tyre and rim meshes, sized to the baked wheel's diameter and width
and made a little larger, which hides it. The suspension moves the new wheels and the baked ones stay
with the body; a wheel well hides the difference at the extremes of the travel.

THE LAMPS are not in the meshes as parts either (they are painted in the texture), so each car gets
small stand-in parts where its lamps are: invisible until a headlight, brake light or indicator wants them.

The pack's cars carry their makers' own badges in their textures; the catalog gives them this game's
names, and they are drawn as they were imported.
"""

import json
import math
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "tools" / "car_pack_data.json"
OUT_DIR = ROOT / "assets" / "vehicles"
VEHICLES = ROOT / "src" / "server" / "content" / "Vehicles.luau"

# The pack is drawn in studs, a stud being 0.28 m (shared/CarSpec.StudsPerMetre): its car 16.2 studs long
# is 4.5 m. The template is in metres.
M = 0.28
# How much larger than life a modelled car is drawn: the GT-R's, and every car here, so they stand
# together in a showroom.
SCALE = 1.25
S = SCALE / M            # studs to the metre, drawn

# The GT-R's wheel meshes, one set per corner (the importer made a mesh for each side): tyre, rim. A
# wheel here is these, resized. (mesh, texture, native size)
TYRE_TEXTURE = 118898513318919
RIM_TEXTURE = 100297853731521
TYRE_NATIVE = (0.2326, 0.72827, 0.72827)
RIM_NATIVE = (0.2351, 0.55706, 0.55706)
WHEEL_MESH = {
    "FL": (123758535222665, 127721857418428),
    "FR": (88276289357347, 121644899848728),
    "RL": (140006374850353, 87700987764014),
    "RR": (130420570516088, 80706659341289),
}
# What the overlay is over the baked wheel: a little bigger all round, so it hides it.
TYRE_GROW_D, TYRE_GROW_W = 1.03, 1.10
RIM_OF_TYRE = 0.80

_ref = 0


def ref() -> str:
    global _ref
    _ref += 1
    return f"RBX{_ref}"


def content(name: str, asset: int) -> str:
    return f'<Content name="{name}"><url>rbxassetid://{asset}</url></Content>' if asset else f'<Content name="{name}"><null></null></Content>'


def vec(name: str, v) -> str:
    return f'<Vector3 name="{name}"><X>{v[0]:.6f}</X><Y>{v[1]:.6f}</Y><Z>{v[2]:.6f}</Z></Vector3>'


def cframe(pos, phi: float) -> str:
    c, s = math.cos(phi), math.sin(phi)
    return (
        f'<CoordinateFrame name="CFrame"><X>{pos[0]:.6f}</X><Y>{pos[1]:.6f}</Y><Z>{pos[2]:.6f}</Z>'
        f"<R00>{c:.7f}</R00><R01>0</R01><R02>{s:.7f}</R02><R10>0</R10><R11>1</R11><R12>0</R12>"
        f"<R20>{-s:.7f}</R20><R21>0</R21><R22>{c:.7f}</R22></CoordinateFrame>"
    )


def number_value(name: str, value: float) -> str:
    return f"""    <Item class="NumberValue" referent="{ref()}"><Properties><string name="Name">{name}</string><double name="Value">{value:.5f}</double></Properties></Item>
"""


def vector_value(name: str, v) -> str:
    return f"""    <Item class="Vector3Value" referent="{ref()}"><Properties><string name="Name">{name}</string>{vec("Value", v)}</Properties></Item>
"""


def skin(name: str, colormap: int, texturepack: int, alpha: str) -> str:
    return f"""      <Item class="SurfaceAppearance" referent="{ref()}">
        <Properties>
          <string name="Name">{name}</string>
          {content("ColorMap", colormap)}
          {content("TexturePack", texturepack)}
          <token name="AlphaMode">{alpha}</token>
        </Properties>
      </Item>
"""


def mesh_part(name, mesh, texture, size, native, pos, phi, double, skin_xml="", collide=False) -> str:
    return f"""    <Item class="MeshPart" referent="{ref()}">
      <Properties>
        <string name="Name">{name}</string>
        {content("MeshId", mesh)}
        {content("TextureID", texture)}
        {vec("size", size)}
        {vec("InitialSize", native)}
        {cframe(pos, phi)}
        <bool name="Anchored">false</bool>
        <bool name="CanCollide">{"true" if collide else "false"}</bool>
        <bool name="CanQuery">false</bool>
        <bool name="CanTouch">false</bool>
        <bool name="Massless">true</bool>
        <bool name="CastShadow">true</bool>
        <bool name="DoubleSided">{"true" if double else "false"}</bool>
        <token name="Material">256</token>
        <token name="RenderFidelity">0</token>
        <token name="CollisionFidelity">0</token>
      </Properties>
{skin_xml}    </Item>
"""


def plain_part(name, size, pos, color=(255, 255, 255)) -> str:
    return f"""    <Item class="Part" referent="{ref()}">
      <Properties>
        <string name="Name">{name}</string>
        {vec("size", size)}
        {cframe(pos, 0.0)}
        <bool name="Anchored">false</bool>
        <bool name="CanCollide">false</bool>
        <bool name="CanQuery">false</bool>
        <bool name="CanTouch">false</bool>
        <bool name="Massless">true</bool>
        <bool name="CastShadow">false</bool>
        <float name="Transparency">1</float>
        <Color3uint8 name="Color3uint8">{(color[0] << 16) | (color[1] << 8) | color[2] | 0xFF000000}</Color3uint8>
        <token name="Material">272</token>
      </Properties>
    </Item>
"""


def rot(phi: float, x: float, z: float):
    """Roblox's CFrame.Angles(0, phi, 0) applied to (x, z)."""
    return x * math.cos(phi) + z * math.sin(phi), -x * math.sin(phi) + z * math.cos(phi)


def analyse(car):
    """The car's own numbers, in metres, in a frame with its nose to -Z and the road at y = 0."""
    phi = car["phi"]
    cx, cz = car["centre"]
    ground = min(w["lo"][1] for w in car["wheels"])
    wheels = {}
    for w in car["wheels"]:
        wc = [(w["lo"][i] + w["hi"][i]) / 2 for i in range(3)]
        x, z = rot(phi, wc[0] - cx, wc[2] - cz)
        corner = ("F" if z < 0 else "R")
        corner = ("F" if z < 0 else "R")
        side = "L" if x < 0 else "R"
        ext = [w["hi"][i] - w["lo"][i] for i in range(3)]
        along_x = abs(car["axis"][0]) > 0.7          # the car lies along world X: its axles run along Z
        width = ext[2] if along_x else ext[0]
        diameter = ext[1]
        wheels[corner + side] = {"x": x * M, "y": (wc[1] - ground) * M, "z": z * M, "d": diameter * M, "w": width * M}
    assert sorted(wheels) == ["FL", "FR", "RL", "RR"], f"car {car['k']}: wheels {sorted(wheels)}"
    # One wheel found much bigger or smaller than the other three is a stray piece of the car taken for
    # it: it gets its neighbours' size, on the road.
    for corner, w in wheels.items():
        others = sorted(o["d"] for c, o in wheels.items() if c != corner)
        median = others[1]
        if abs(w["d"] - median) > 0.18 * median and max(others) < 1.1 * min(others):
            print(f"  FIXED car {car['k']}: wheel {corner} {w['d']:.2f} -> {median:.2f}")
            w["d"] = median
            w["y"] = median / 2
    # Front and rear wheels of a car are the same size to within a staggered fitment.
    ds = [w["d"] for w in wheels.values()]
    if max(ds) > 1.25 * min(ds):
        print(f"  WARNING car {car['k']}: wheel diameters {[round(d, 2) for d in ds]}")
    return phi, cx, cz, ground, wheels


def build(car, car_id: str):
    phi, cx, cz, ground, wheels = analyse(car)
    items = []
    top = 0.0
    zmin, zmax, xmin, xmax = 1e9, -1e9, 1e9, -1e9
    paint_white = 0.0
    for i, p in enumerate(car["parts"], 1):
        x, z = rot(phi, p["pos"][0] - cx, p["pos"][2] - cz)
        y = p["pos"][1] - ground
        pos = (x * M, y * M, z * M)
        size = [v * M for v in p["size"]]
        paint_white = max(paint_white, p["white"])
        # bounds, in the car's frame
        for gx in (p["bbox"][0][0], p["bbox"][1][0]):
            for gz in (p["bbox"][0][2], p["bbox"][1][2]):
                bx, bz = rot(phi, gx - cx, gz - cz)
                zmin, zmax = min(zmin, bz * M), max(zmax, bz * M)
                xmin, xmax = min(xmin, bx * M), max(xmax, bx * M)
        top = max(top, (p["bbox"][1][1] - ground) * M)
        sk = skin("Tint", p["colormap"], p["texturepack"], p["alpha"])
        items.append(mesh_part(f"Paint_{i}", p["mesh"], 0, size, p["size"], pos, phi, p["doubleSided"], sk))
    length = zmax - zmin
    track = (abs(wheels["FL"]["x"]) + abs(wheels["FR"]["x"])) / 2
    width = 2 * track + (wheels["FL"]["w"] + wheels["FR"]["w"]) / 2
    zc = (zmax + zmin) / 2
    # the wheels
    for corner, w in wheels.items():
        tyre_size = (w["w"] * TYRE_GROW_W, w["d"] * TYRE_GROW_D, w["d"] * TYRE_GROW_D)
        rim_size = (tyre_size[0] * RIM_NATIVE[0] / TYRE_NATIVE[0], tyre_size[1] * RIM_OF_TYRE, tyre_size[1] * RIM_OF_TYRE)
        centre = (w["x"], w["y"], w["z"])
        tyre_mesh, rim_mesh = WHEEL_MESH[corner]
        items.append(mesh_part(f"Wheel{corner}_Tyre", tyre_mesh, TYRE_TEXTURE, tyre_size, TYRE_NATIVE, centre, 0.0, False))
        items.append(mesh_part(f"Wheel{corner}_Rim", rim_mesh, 0, rim_size, RIM_NATIVE, centre, 0.0, False, skin("Tint", RIM_TEXTURE, 0, "0")))
    ride_h = top
    front_z, rear_z = wheels["FL"]["z"], wheels["RL"]["z"]
    wheelbase = rear_z - front_z
    # Lamps: stand-in parts where a real car's are.
    lamp_x = 0.36 * width
    items.append(plain_part("Lens_HeadL", (0.2, 0.09, 0.06), (-lamp_x, 0.50 * top, zmin + 0.06)))
    items.append(plain_part("Lens_HeadR", (0.2, 0.09, 0.06), (lamp_x, 0.50 * top, zmin + 0.06)))
    items.append(plain_part("Lamp_TailL", (0.26, 0.08, 0.04), (-lamp_x, 0.58 * top, zmax - 0.04), (255, 30, 30)))
    items.append(plain_part("Lamp_TailR", (0.26, 0.08, 0.04), (lamp_x, 0.58 * top, zmax - 0.04), (255, 30, 30)))
    # Numbers the builder reads.
    items.append(number_value("RoofY", top))
    items.append(number_value("WheelX", -0.46 * track))
    items.append(number_value("WheelZ", front_z + 0.42 * wheelbase))
    items.append(number_value("HoodY", 0.80 * top))
    items.append(number_value("HoodZ", zmin + 0.28 * length))
    items.append(vector_value("SigFront", (0.35 * width, 0.46 * top, zmin + 0.03)))
    items.append(vector_value("SigRear", (0.33 * width, 0.55 * top, zmax - 0.03)))
    xml = f"""<roblox version="4">
  <Item class="Model" referent="{ref()}">
    <Properties>
      <string name="Name">{car_id}</string>
    </Properties>
{"".join(items)}  </Item>
</roblox>
"""
    radius = sum(w["d"] for w in wheels.values()) / 4 / 2 * TYRE_GROW_D
    return xml, {
        "length": length,
        "width": width,
        "height": top,
        "radius": radius,
        "paintable": paint_white >= 0.30,
        "wheelbase": wheelbase,
    }


# ---------------------------------------------------------------------------------------------
# The catalog. Every car is drawn the same size-for-size as the GT-R (SCALE), and priced and tuned on one
# ladder, so that a dearer car is always the quicker one -- the rule content/Vehicles checks.
# ---------------------------------------------------------------------------------------------

CLASSES = ["compact", "sedan", "suv", "sports", "super"]
NAMES = {
    "compact": (["Kestrel", "Brightwater"], ["Wren", "Finch", "Lark", "Swift", "Pipit", "Teal", "Linnet", "Sparrow", "Plover"]),
    "sedan": (["Marlow", "Halden"], ["Verve", "Sterling", "Regent", "Aria", "Corso", "Meridian", "Hallmark", "Cadence", "Dominion", "Ambassador", "Lyric", "Sovereign", "Tribune", "Monarch"]),
    "suv": (["Elmhurst", "Ostrava"], ["Ridge", "Trailhead", "Overland", "Vantage", "Cairn", "Ranger", "Tundra", "Highland", "Escarp"]),
    "sports": (["Castellan", "Rhodes"], ["Gale", "Ember", "Blaze", "Falcon", "Rival", "Apex", "Strike", "Vector", "Fury", "Surge", "Rapid", "Talon", "Havoc", "Comet", "Riot", "Sprint"]),
    "super": (["Solari", "Vanta"], ["Corsa", "Tempesta", "Lampo", "Furia", "Veloce", "Saetta", "Fulmine", "Scatto", "Raggio", "Zenith", "Inferno", "Aurora"]),
}
PAINTS = [
    (30, 62, 150), (176, 40, 36), (24, 24, 28), (150, 154, 160), (36, 96, 70), (214, 120, 30),
    (96, 40, 120), (200, 200, 204), (20, 90, 140), (120, 20, 40),
]
DRIVE = {"compact": "FWD", "sedan": "FWD", "suv": "AWD", "sports": "RWD", "super": "AWD"}
SEATS = {"compact": 4, "sedan": 5, "suv": 5, "sports": 2, "super": 2}
STEER = {"compact": 34, "sedan": 32, "suv": 28, "sports": 34, "super": 33}


def classify(m) -> str:
    L, H = m["length"] / M, m["height"] / M
    if H <= 3.85 and L >= 14.8:
        return "super"
    if H <= 4.05:
        return "sports"
    if H >= 4.6:
        return "suv"
    if L >= 15.2:
        return "sedan"
    return "compact"


def main() -> None:
    cars = json.load(open(DATA))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    built = []
    for car in cars:
        car_id = f"pack{car['k']:02d}"
        xml, m = build(car, car_id)
        with open(OUT_DIR / f"{car_id}.rbxmx", "w", encoding="utf-8", newline="\n") as handle:
            handle.write(xml)
        m["id"] = car_id
        m["class"] = classify(m)
        built.append(m)
        print(f"{car_id}: {m['class']:8s} L={m['length']:.2f} W={m['width']:.2f} H={m['height']:.2f} R={m['radius']:.3f} paint={m['paintable']}")
    # the ladder
    built.sort(key=lambda m: (CLASSES.index(m["class"]), m["length"]))
    n = len(built)
    used = {c: 0 for c in CLASSES}
    entries = []
    for rank, m in enumerate(built):
        t = rank / (n - 1)
        brands, models = NAMES[m["class"]]
        brand = brands[used[m["class"]] % len(brands)]
        name = models[used[m["class"]] % len(models)]
        used[m["class"]] += 1
        price = int(round(11000 * (86000 / 11000) ** t / 100.0)) * 100
        kph = 172 + (338 - 172) * t ** 0.92
        # 0-100 km/h from 9.5 s down to 3.2 s along the ladder; the harness measures a car's mean pull to 100 km/h
        # at about 1.55 times the initial pull its entry asks for.
        t100 = 9.5 - 6.3 * t
        a0 = (100 / 3.6 / t100) / 1.55
        top_studs = round(kph / 3.6 * S + rank * 0.25, 1)
        accel = round(a0 * S + rank * 0.05, 2)
        color = PAINTS[rank % len(PAINTS)] if m["paintable"] else (255, 255, 255)
        w, h, l = m["width"] * S, m["height"] * S, m["length"] * S
        entries.append(f"""	{{
		id = "{m['id']}",
		name = "{brand} {name}",
		brand = "{brand}",
		year = {2019 + rank % 8},
		style = "{'gt' if m['class'] in ('sports', 'super') else 'sedan' if m['class'] in ('sedan', 'compact') else 'suv'}",
		model = "{m['id']}",
		drivetrain = "{DRIVE[m['class']]}",
		seats = {SEATS[m['class']]},
		price = {price},
		scale = {SCALE},
		tyreRadius = {m['radius']:.3f},
		size = Vector3.new({w:.2f}, {h:.2f}, {l:.2f}),
		color = Color3.fromRGB({color[0]}, {color[1]}, {color[2]}),
		accentColor = Color3.fromRGB(18, 18, 20),
		topSpeedStuds = {top_studs},
		acceleration = {accel},
		steerDegrees = {STEER[m['class']]},
	}},""")
    block = "\n".join(entries)
    text = VEHICLES.read_text(encoding="utf-8")
    begin, end = "\t-- BEGIN PACK (generated by tools/gen_car_pack.py)\n", "\t-- END PACK\n"
    new = begin + block + "\n" + end
    if begin in text:
        text = re.sub(re.escape(begin) + r".*?" + re.escape(end), lambda _: new, text, flags=re.S)
    else:
        marker = "}\n\n-- Loud at require time"
        assert marker in text, "Vehicles.luau has no end of SOURCE to put the pack before"
        text = text.replace(marker, new + marker, 1)
    with open(VEHICLES, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print(f"wrote {n} cars to {OUT_DIR} and the catalog block of {VEHICLES.name}")


if __name__ == "__main__":
    main()
