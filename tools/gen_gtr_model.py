"""Writes assets/vehicles/GTR.rbxmx: the imported GT-R, as a flat model of its 67 mesh parts.

    python tools/gen_gtr_model.py

WHERE THE DATA COMES FROM. The owner imported a GT-R (a Sketchfab model, through Studio's 3D
importer, which uploads each mesh and texture to their account) into the dealership sandbox on
2026-09-30. The import lives only in an open Studio session until something writes it down, so this
file is the record of it: every part's MeshId, TextureID, size and place, read off the import with
the Studio MCP. Nothing here is invented -- the ids are the ones the importer made.

The import's units are metres (a stud per metre: the car is 4.72 long); CarBody's MeshCar scales
it to the world when it builds a car (MeshCar.SCALE). Every part sits at its place in the car with no
rotation, which is what the import gave.

WHY A FILE AND NOT CODE. A MeshPart's MeshId cannot be set by a script at run time -- only
AssetService:CreateMeshPartAsync makes one, asynchronously -- so the parts have to arrive as a model.
Rojo mounts this file in ReplicatedStorage.CarModels (see dealership.project.json).

The nose points to -Z, as every car here does. The wheels are in four groups of five parts (tyre,
rim, brake disc, two callipers), the importer having named them after the callipers.
"""

import pathlib
import sys

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "vehicles" / "GTR.rbxmx"

# (name, mesh id, texture id, (sx, sy, sz), (x, y, z), double sided)
BODY = [
    ("Badge_Body", 126979087192263, 134050517968366, (1.7948, 0.0312, 0.0399), (0.00001, 0.05891, -0.86195), False),
    ("Paint_Body", 136286704722109, 110465723625333, (1.893, 1.1398, 3.9727), (0.00001, 0.12051, 0.02295), False),
    ("Lamp_BodyFront", 136254687719408, 140541512899530, (1.6804, 0.2268, 0.6049), (0.00001, 0.04011, -1.81135), False),
    ("Trim_Body", 109000814531360, 110659288769699, (1.8854, 1.2175, 2.1044), (0.00001, 0.04256, 0.036), False),
    ("Badge_Boot", 134572187257561, 127199243200925, (0.1029, 0.0833, 0.031), (-0.00054, 0.24856, 2.2364), False),
    ("Paint_Boot", 132384449785587, 110465723625333, (1.177, 0.213, 0.6632), (0.00001, 0.28671, 1.9247), False),
    ("Lamp_BootA", 122506448213698, 140541512899530, (0.3308, 0.0144, 0.0122), (0.00001, 0.35431, 2.2101), False),
    ("Trim_Boot", 122547550794842, 110659288769699, (1.6838, 0.3164, 0.7306), (0.00001, 0.33841, 1.9584), False),
    ("Lamp_Brake3", 117102060917553, 140541512899530, (0.3308, 0.0144, 0.0122), (0.00001, 0.35431, 2.2109), False),
    ("Lamp_BrakeL", 81612355856876, 140541512899530, (0.3766, 0.1819, 0.162), (-0.59299, 0.17376, 2.1307), False),
    ("Lamp_BrakeR", 129623921781354, 140541512899530, (0.3766, 0.1819, 0.162), (0.59301, 0.17376, 2.1307), False),
    ("Chassis", 94400831252575, 129734240272877, (1.8836, 0.8774, 4.5385), (0.00001, -0.12749, -0.01295), False),
    ("Lamp_ChassisFront", 134471006281575, 140541512899530, (1.8508, 0.0395, 0.1885), (0.00001, -0.04684, -1.73775), False),
    ("Trim_Chassis", 103101500454233, 110659288769699, (1.5752, 0.8995, 4.4006), (0.00001, -0.06784, 0.056), False),
    ("Door_LeftCab", 109207031354394, 105592730678586, (0.1134, 0.6975, 1.1321), (-0.73319, 0.04596, 0.00315), False),
    ("Paint_DoorL", 108238848514225, 110465723625333, (0.1573, 0.7606, 1.3228), (-0.84214, -0.06569, -0.0104), False),
    ("Trim_DoorL", 118311906655620, 110659288769699, (0.1676, 0.2484, 1.2267), (-0.8159, 0.26821, 0.03575), False),
    ("Door_RightCab", 117778836312956, 105592730678586, (0.1134, 0.6975, 1.1321), (0.73321, 0.04596, 0.00315), False),
    ("Paint_DoorR", 139451985171563, 110465723625333, (0.1573, 0.7606, 1.3228), (0.84216, -0.06569, -0.0104), False),
    ("Trim_DoorR", 117295180197196, 110659288769699, (0.1676, 0.2484, 1.2267), (0.81591, 0.26821, 0.03575), False),
    ("Exhaust", 122077608855167, 110465723625333, (1.5548, 0.1459, 0.2077), (0.00001, -0.35414, 2.15035), False),
    ("Badge_Front", 81578625181991, 127199243200925, (0.9102, 0.4206, 0.1378), (0.00001, -0.25269, -2.1603), False),
    ("Paint_FrontBumper", 111969607397383, 110465723625333, (1.8418, 0.5266, 0.5851), (0.00001, -0.21789, -1.98025), False),
    ("Lamp_FrontBumper", 135976920905668, 140541512899530, (1.6894, 0.0381, 0.1392), (0.00001, -0.29614, -2.1056), False),
    ("Trim_FrontBumper", 76268922930435, 110659288769699, (1.8718, 0.5091, 0.5736), (0.00001, -0.29114, -2.0715), False),
    ("Glass_Front", 111608409851741, 104144002827361, (1.4706, 0.3811, 0.8767), (0.00001, 0.43806, -0.51185), True),
    ("Glass_LeftQuarter", 97547942143382, 104144002827361, (0.1147, 0.2348, 0.5019), (-0.70914, 0.43201, 0.82015), True),
    ("Glass_Left", 94943021788202, 104144002827361, (0.1501, 0.3258, 1.0484), (-0.70554, 0.43821, 0.1117), True),
    ("Glass_Rear", 108414898438956, 104144002827361, (1.1512, 0.2554, 0.8226), (0.00001, 0.48771, 1.2941), True),
    ("Glass_RightQuarter", 80107844123330, 104144002827361, (0.1147, 0.2348, 0.5019), (0.70916, 0.43201, 0.82015), True),
    ("Glass_Right", 126201643750547, 104144002827361, (0.1501, 0.3258, 1.0484), (0.70556, 0.43821, 0.1117), True),
    ("Lens_HeadL", 75784928344236, 104144002827361, (0.2701, 0.2287, 0.6078), (-0.70514, 0.04106, -1.8128), True),
    ("Lens_HeadR", 94897247872546, 104144002827361, (0.2701, 0.2287, 0.6078), (0.70515, 0.04106, -1.8128), True),
    ("Paint_Hood", 77848188091491, 110465723625333, (1.5412, 0.2873, 1.3613), (0.00001, 0.14686, -1.46365), False),
    ("Trim_Hood", 74605092481914, 110659288769699, (1.5412, 0.2816, 1.3613), (0.00001, 0.14401, -1.46365), False),
    ("Interior", 132995587173747, 105592730678586, (1.752, 1.0481, 2.6182), (0.00001, 0.12206, 0.3589), False),
    ("MirrorGlass_L", 116881942401624, 110659288769699, (0.1375, 0.1234, 0.0791), (-0.92004, 0.32281, -0.28055), False),
    ("MirrorGlass_R", 77295028725596, 110659288769699, (0.1375, 0.1234, 0.0791), (0.92006, 0.32281, -0.28055), False),
    ("Paint_MirrorL", 130213337276662, 110659288769699, (0.1985, 0.2139, 0.1953), (-0.90025, 0.28866, -0.32155), False),
    ("Paint_MirrorR", 95914971728775, 110659288769699, (0.1985, 0.2139, 0.1953), (0.90026, 0.28866, -0.32155), False),
    ("Badge_Rear", 126170840835148, 127199243200925, (0.7586, 0.0526, 0.0386), (-0.00199, 0.13461, 2.2596), False),
    ("Paint_RearBumper", 77904269010803, 110465723625333, (1.891, 0.5923, 0.6907), (0.00001, 0.01926, 2.00675), False),
    ("Lamp_RearBumper", 88220186034031, 140541512899530, (1.7626, 0.2294, 0.281), (0.00001, 0.14901, 2.067), False),
    ("Trim_RearBumper", 134145960952386, 110659288769699, (1.8644, 0.5575, 0.5942), (0.00001, -0.26164, 2.0612), False),
    ("SteeringWheel", 98337615402813, 105592730678586, (0.3474, 0.33254, 0.17814), (-0.37019, 0.20207, -0.24952), False),
    ("Lamp_TailL", 102210478055710, 140541512899530, (0.3773, 0.1832, 0.1625), (-0.59155, 0.17211, 2.12625), False),
    ("Lamp_TailR", 98437123686760, 140541512899530, (0.3773, 0.1832, 0.1625), (0.59156, 0.17211, 2.12625), False),
]

# The four wheels: (corner, [(role, mesh, texture, size, position)]). Tyre, rim, disc, two callipers.
WHEELS = [
    ("FL", [
        ("Tyre", 123758535222665, 118898513318919, (0.2326, 0.72827, 0.72827), (-0.80439, -0.32627, -1.40783)),
        ("Rim", 127721857418428, 100297853731521, (0.2351, 0.55706, 0.55706), (-0.80564, -0.32627, -1.40783)),
        ("Disc", 84540892455488, 105428772488891, (0.0491, 0.40306, 0.40306), (-0.84114, -0.32627, -1.40783)),
        ("CalliperA", 105777465647918, 110659288769699, (0.0694, 0.3468, 0.10501), (-0.82739, -0.331, -1.57626)),
        ("CalliperB", 82136105306654, 110659288769699, (0.069, 0.30242, 0.10028), (-0.82719, -0.30275, -1.57305)),
    ]),
    ("FR", [
        ("Tyre", 88276289357347, 118898513318919, (0.2326, 0.72827, 0.72827), (0.80441, -0.32627, -1.40783)),
        ("Rim", 121644899848728, 100297853731521, (0.2351, 0.55706, 0.55706), (0.80566, -0.32627, -1.40783)),
        ("Disc", 94925874567584, 105428772488891, (0.0491, 0.40306, 0.40306), (0.84116, -0.32627, -1.40783)),
        ("CalliperA", 79131389053309, 110659288769699, (0.0694, 0.3468, 0.10501), (0.82741, -0.331, -1.57626)),
        ("CalliperB", 112702625889537, 110659288769699, (0.069, 0.30242, 0.10028), (0.8272, -0.30275, -1.57305)),
    ]),
    ("RL", [
        ("Tyre", 140006374850353, 118898513318919, (0.2326, 0.72827, 0.72827), (-0.82821, -0.32627, 1.37523)),
        ("Rim", 87700987764014, 100297853731521, (0.2351, 0.55706, 0.55706), (-0.82945, -0.32627, 1.37523)),
        ("Disc", 106788071769315, 105428772488891, (0.0491, 0.40306, 0.40306), (-0.86495, -0.32627, 1.37523)),
        ("CalliperA", 113657721251117, 110659288769699, (0.0694, 0.3468, 0.10501), (-0.8512, -0.331, 1.20681)),
        ("CalliperB", 122556556823243, 110659288769699, (0.069, 0.30242, 0.10028), (-0.85101, -0.30275, 1.21002)),
    ]),
    ("RR", [
        ("Tyre", 130420570516088, 118898513318919, (0.2326, 0.72827, 0.72827), (0.82822, -0.32627, 1.37523)),
        ("Rim", 80706659341289, 100297853731521, (0.2351, 0.55706, 0.55706), (0.82947, -0.32627, 1.37523)),
        ("Disc", 94744654214933, 105428772488891, (0.0491, 0.40306, 0.40306), (0.86497, -0.32627, 1.37523)),
        ("CalliperA", 82518713431395, 110659288769699, (0.0694, 0.3468, 0.10501), (0.85122, -0.331, 1.20681)),
        ("CalliperB", 130168495554227, 110659288769699, (0.069, 0.30242, 0.10028), (0.85102, -0.30275, 1.21002)),
    ]),
]

_ref = 0


def ref() -> str:
    global _ref
    _ref += 1
    return f"RBX{_ref}"


def content(name: str, asset: int) -> str:
    return f'<Content name="{name}"><url>rbxassetid://{asset}</url></Content>'


def vec(name: str, v) -> str:
    return f'<Vector3 name="{name}"><X>{v[0]}</X><Y>{v[1]}</Y><Z>{v[2]}</Z></Vector3>'


def skin(name: str, texture: int) -> str:
    """A SurfaceAppearance carrying the part's own texture as its colour map, for paint and rims.

    A MeshPart ignores its Color, but a SurfaceAppearance's Color tints its ColorMap -- and a script
    in the game cannot write a ColorMap (it needs plugin capability), only the Color. So the map is
    authored into the model here and world/MeshCar only ever sets Color.
    """
    if not (name.startswith("Paint_") or name.endswith("_Rim")):
        return ""
    return f"""      <Item class="SurfaceAppearance" referent="{ref()}">
        <Properties>
          <string name="Name">Tint</string>
          {content("ColorMap", texture)}
        </Properties>
      </Item>
"""


def mesh_part(name: str, mesh: int, texture: int, size, pos, double: bool) -> str:
    return f"""    <Item class="MeshPart" referent="{ref()}">
      <Properties>
        <string name="Name">{name}</string>
        {content("MeshId", mesh)}
        {content("TextureID", texture)}
        {vec("size", size)}
        {vec("InitialSize", size)}
        <CoordinateFrame name="CFrame"><X>{pos[0]}</X><Y>{pos[1]}</Y><Z>{pos[2]}</Z><R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>
        <bool name="Anchored">false</bool>
        <bool name="CanCollide">false</bool>
        <bool name="CanQuery">false</bool>
        <bool name="CanTouch">false</bool>
        <bool name="Massless">true</bool>
        <bool name="CastShadow">true</bool>
        <bool name="DoubleSided">{"true" if double else "false"}</bool>
        <token name="Material">256</token>
        <token name="RenderFidelity">0</token>
        <token name="CollisionFidelity">0</token>
      </Properties>
{skin(name, texture)}    </Item>
"""


def main() -> None:
    parts = []
    for name, mesh, texture, size, pos, double in BODY:
        parts.append(mesh_part(name, mesh, texture, size, pos, double))
    for corner, pieces in WHEELS:
        for role, mesh, texture, size, pos in pieces:
            parts.append(mesh_part(f"Wheel{corner}_{role}", mesh, texture, size, pos, False))
    total = len(BODY) + sum(len(p) for _, p in WHEELS)
    if total != 67:
        sys.exit(f"expected 67 parts, have {total}")
    root = f"""<roblox version="4">
  <Item class="Model" referent="{ref()}">
    <Properties>
      <string name="Name">GTR</string>
    </Properties>
{"".join(parts)}  </Item>
</roblox>
"""
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(root, encoding="utf-8")
    print(f"wrote {OUT} ({total} parts)")


if __name__ == "__main__":
    main()
