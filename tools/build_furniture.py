#!/usr/bin/env python3
"""Generates assets/Furniture.rbxmx.

This file is the source of truth for the furniture, not the .rbxmx it emits —
edit here and re-run. The output is committed so the game builds without a
Python step.

Furniture lives in its own model, separate from assets/House.rbxmx, because the
house is re-exported from Studio by hand: anything sharing that file would be
overwritten every time the building gets redecorated.

Everything here is deliberately blocky and cheap to replace. The one piece that
matters structurally is the rug's event anchor, and even that is a separate
invisible part, so swapping the rug art later cannot break the event.

Coordinates come from measuring the house: floor surface sits at Y=1.037, and
the room holding the spawn is open from x=-12..29, z=-27..-16.
"""

import base64
import struct
from contextlib import contextmanager
from pathlib import Path

FLOOR = 1.037
OUT = Path(__file__).resolve().parent.parent / "assets" / "Furniture.rbxmx"

# Enum.Material tokens.
PLASTIC, SMOOTH, WOOD, PLANKS, FABRIC, METAL, NEON, MARBLE = 256, 272, 512, 528, 1312, 1088, 288, 784

# A single warm, muted palette so the blockiness reads as deliberate rather
# than as a pile of default-colored bricks.
CREAM = (236, 226, 208)
ROSE = (206, 156, 152)
SAGE = (150, 168, 142)
OAK = (168, 124, 82)
WALNUT = (94, 66, 47)
CHARCOAL = (58, 58, 64)
LINEN = (214, 206, 192)
SKY = (162, 190, 206)
WHITE = (245, 243, 238)
BRASS = (198, 160, 96)

_items = []
_ref = 0


def _next_ref():
    global _ref
    _ref += 1
    return f"RBXFURN{_ref:04d}"


def _c3(rgb):
    r, g, b = rgb
    return (0xFF << 24) | (r << 16) | (g << 8) | b


def _tags_blob(tags):
    return base64.b64encode("\0".join(tags).encode()).decode()


def _attributes_blob(attrs):
    """Roblox attribute format: u32 count, then per entry name, type, value.

    0x02 is the string type id. Only strings are needed here; if this encoding
    is ever wrong the attribute simply won't appear, and WorldEventService warns
    by name about the object that carries it.
    """
    out = struct.pack("<I", len(attrs))
    for key, value in attrs.items():
        kb = key.encode()
        vb = value.encode()
        out += struct.pack("<I", len(kb)) + kb
        out += b"\x02"
        out += struct.pack("<I", len(vb)) + vb
    return base64.b64encode(out).decode()


_turn = None


@contextmanager
def turned(px, pz):
    """Emits everything inside a quarter turn about (px, pz).

    The rooms here are long corridors rather than squares, so the same sofa has
    to be able to run along either axis. Rotating at placement time keeps each
    builder written once, in its own natural orientation, instead of every piece
    needing a width-and-depth argument it would then have to interpret."""
    global _turn
    previous = _turn
    _turn = (px, pz)
    try:
        yield
    finally:
        _turn = previous


def part(name, center, size, color, material=SMOOTH, transparency=0.0,
         collide=True, shape=1, upright_cylinder=False, tags=None, attrs=None,
         children=""):
    """center is (x, y, z) with y being the BOTTOM of the part, so furniture is
    placed by what it stands on rather than by its middle."""
    x, ybase, z = center
    sx, sy, sz = size
    y = ybase + sy / 2

    turn = _turn
    if turn is not None:
        px, pz = turn
        # Quarter turn about Y: x' = z, z' = -x. Size is left alone because the
        # CFrame carries the rotation, which is also why discs need no special
        # case here — they are circular about the axis being turned.
        x, z = px + (z - pz), pz - (x - px)

    if upright_cylinder:
        # Cylinder parts run along their X axis, so a disc lying flat needs X
        # rotated onto Y. sx becomes thickness; sy/sz become the diameter.
        rot = "<R00>0</R00><R01>-1</R01><R02>0</R02><R10>1</R10><R11>0</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22>"
        y = ybase + sx / 2
    elif turn is not None:
        rot = "<R00>0</R00><R01>0</R01><R02>1</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>-1</R20><R21>0</R21><R22>0</R22>"
    else:
        rot = "<R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22>"

    extra = ""
    if tags:
        extra += f'<BinaryString name="Tags">{_tags_blob(tags)}</BinaryString>'
    if attrs:
        extra += f'<BinaryString name="AttributesSerialize">{_attributes_blob(attrs)}</BinaryString>'

    _items.append(f'''<Item class="Part" referent="{_next_ref()}">
<Properties>
<string name="Name">{name}</string>
<CoordinateFrame name="CFrame"><X>{x}</X><Y>{y}</Y><Z>{z}</Z>{rot}</CoordinateFrame>
<Vector3 name="size"><X>{sx}</X><Y>{sy}</Y><Z>{sz}</Z></Vector3>
<bool name="Anchored">true</bool>
<bool name="CanCollide">{"true" if collide else "false"}</bool>
<token name="Material">{material}</token>
<token name="shape">{shape}</token>
<Color3uint8 name="Color3uint8">{_c3(color)}</Color3uint8>
<float name="Transparency">{transparency}</float>
<float name="Reflectance">0</float>
{extra}
</Properties>
{children}
</Item>''')


def point_light(color, brightness, rng):
    r, g, b = [c / 255 for c in color]
    return f'''<Item class="PointLight" referent="{_next_ref()}">
<Properties>
<string name="Name">Glow</string>
<Color3 name="Color"><R>{r}</R><G>{g}</G><B>{b}</B></Color3>
<float name="Brightness">{brightness}</float>
<float name="Range">{rng}</float>
<bool name="Shadows">true</bool>
<bool name="Enabled">true</bool>
</Properties>
</Item>'''


# --------------------------------------------------------------------------
# The nursery, west end of the room.
# --------------------------------------------------------------------------

def rug(cx, cz):
    """The rug from childhood_across_the_rug. Ten studs across, which at a
    crawler's walkSpeed of 4 is a genuine journey and at sixteen is one step —
    the same object measuring the body that crosses it."""
    part("Rug", (cx, FLOOR, cz), (0.08, 10, 10), ROSE, FABRIC, collide=False,
         shape=2, upright_cylinder=True)
    part("RugInner", (cx, FLOOR + 0.08, cz), (0.06, 7, 7), CREAM, FABRIC,
         collide=False, shape=2, upright_cylinder=True)
    part("RugCenter", (cx, FLOOR + 0.14, cz), (0.05, 3, 3), SAGE, FABRIC,
         collide=False, shape=2, upright_cylinder=True)

    # Kept separate from the art on purpose: the rug can be replaced with a
    # nicer model without touching the thing that makes the event fire.
    part("RugEventAnchor", (cx, FLOOR, cz), (2, 2, 2), WHITE, PLASTIC,
         transparency=1, collide=False,
         tags=["AgesEvent"], attrs={"EventId": "childhood_across_the_rug"})


def crib(cx, cz):
    w, l, h = 3.0, 5.5, 3.2
    part("CribBase", (cx, FLOOR + 1.0, cz), (w, 0.3, l), OAK, WOOD)
    part("CribMattress", (cx, FLOOR + 1.3, cz), (w - 0.5, 0.5, l - 0.5), WHITE, FABRIC)
    part("CribBlanket", (cx, FLOOR + 1.8, cz + 1.0), (w - 0.6, 0.12, l / 2), SKY, FABRIC, collide=False)
    for dx, dz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        part("CribPost", (cx + dx * (w / 2 - 0.15), FLOOR, cz + dz * (l / 2 - 0.15)),
             (0.3, h, 0.3), OAK, WOOD)
    # Bars: the view out of the first place a life is kept.
    n = 9
    for i in range(n):
        z = cz - l / 2 + 0.5 + i * (l - 1.0) / (n - 1)
        for dx in (-1, 1):
            part("CribBar", (cx + dx * (w / 2 - 0.15), FLOOR + 1.3, z),
                 (0.16, h - 1.5, 0.16), OAK, WOOD, collide=False)
    for dx in (-1, 1):
        part("CribRail", (cx + dx * (w / 2 - 0.15), FLOOR + h - 0.25, cz), (0.34, 0.25, l), OAK, WOOD)


def dresser(cx, cz):
    w, l, h = 2.4, 4.5, 3.0
    part("DresserBody", (cx, FLOOR, cz), (w, h, l), WALNUT, WOOD)
    for i, dz in enumerate((-1.1, 0.0, 1.1)):
        part("DresserDrawer", (cx + w / 2 - 0.05, FLOOR + 0.35 + i * 0.85, cz + dz),
             (0.12, 0.7, l - 0.6), LINEN, SMOOTH, collide=False)
    part("DresserTop", (cx, FLOOR + h, cz), (w + 0.3, 0.2, l + 0.3), WALNUT, WOOD)


def toy_chest(cx, cz):
    part("ToyChest", (cx, FLOOR, cz), (2.6, 1.8, 3.2), SAGE, WOOD)
    part("ToyChestLid", (cx, FLOOR + 1.8, cz), (2.8, 0.3, 3.4), CREAM, WOOD)
    for i, (dx, dz, col) in enumerate(((-0.6, 1.9, ROSE), (0.5, 2.2, SKY), (0.0, 2.7, BRASS))):
        part("Block", (cx + dx, FLOOR, cz + dz), (0.9, 0.9, 0.9), col, PLASTIC)


def rocker(cx, cz):
    part("ChairSeat", (cx, FLOOR + 1.2, cz), (2.6, 0.5, 2.6), LINEN, FABRIC)
    part("ChairBack", (cx - 1.05, FLOOR + 1.7, cz), (0.5, 2.4, 2.6), LINEN, FABRIC)
    for dx, dz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        part("ChairLeg", (cx + dx * 1.0, FLOOR, cz + dz * 1.0), (0.28, 1.2, 0.28), WALNUT, WOOD)


# --------------------------------------------------------------------------
# The living room, east end.
# --------------------------------------------------------------------------

def sofa(cx, cz):
    part("SofaBase", (cx, FLOOR + 0.6, cz), (3.4, 1.0, 8.5), SAGE, FABRIC)
    part("SofaBack", (cx + 1.3, FLOOR + 1.6, cz), (0.8, 2.0, 8.5), SAGE, FABRIC)
    for dz in (-1, 1):
        part("SofaArm", (cx, FLOOR + 1.6, cz + dz * 4.0), (3.4, 1.2, 0.8), SAGE, FABRIC)
    for dz in (-2.2, 0.0, 2.2):
        part("Cushion", (cx - 0.2, FLOOR + 1.6, cz + dz), (2.8, 0.4, 2.0), LINEN, FABRIC, collide=False)
    for dx, dz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        part("SofaLeg", (cx + dx * 1.4, FLOOR, cz + dz * 3.8), (0.3, 0.6, 0.3), WALNUT, WOOD)


def coffee_table(cx, cz):
    part("TableTop", (cx, FLOOR + 1.2, cz), (3.6, 0.25, 5.0), OAK, WOOD)
    for dx, dz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        part("TableLeg", (cx + dx * 1.5, FLOOR, cz + dz * 2.1), (0.3, 1.2, 0.3), WALNUT, WOOD)
    part("Bowl", (cx, FLOOR + 1.45, cz), (0.5, 1.6, 1.6), SKY, MARBLE, collide=False,
         shape=2, upright_cylinder=True)


def tv_unit(cx, cz):
    part("TVStand", (cx, FLOOR, cz), (1.8, 1.6, 6.5), WALNUT, WOOD)
    part("TVScreen", (cx, FLOOR + 1.6, cz), (0.25, 3.4, 5.8), CHARCOAL, SMOOTH)
    part("TVGlass", (cx + 0.15, FLOOR + 1.75, cz), (0.05, 3.0, 5.4), (24, 26, 32), SMOOTH, collide=False)


def bookshelf(cx, cz):
    w, l, h = 1.4, 5.0, 7.0
    part("ShelfBack", (cx, FLOOR, cz), (0.3, h, l), WALNUT, WOOD)
    for i in range(4):
        part("Shelf", (cx - 0.5, FLOOR + 0.6 + i * 1.9, cz), (w, 0.2, l), WALNUT, WOOD)
        for j, col in enumerate((ROSE, SKY, SAGE, CREAM, BRASS)):
            part("Book", (cx - 0.5, FLOOR + 0.8 + i * 1.9, cz - 1.8 + j * 0.9),
                 (0.9, 1.2, 0.25), col, SMOOTH, collide=False)
    for dz in (-1, 1):
        part("ShelfSide", (cx - 0.5, FLOOR, cz + dz * (l / 2)), (w, h, 0.2), WALNUT, WOOD)


def floor_lamp(cx, cz):
    part("LampBase", (cx, FLOOR, cz), (1.4, 0.3, 1.4), BRASS, METAL, shape=2, upright_cylinder=True)
    part("LampPole", (cx, FLOOR + 0.3, cz), (0.2, 5.4, 0.2), BRASS, METAL)
    part("LampShade", (cx, FLOOR + 5.4, cz), (2.0, 1.6, 2.0), CREAM, FABRIC,
         collide=False, children=point_light((255, 226, 180), 1.4, 22))


def pendant(cx, cz, ceiling):
    part("PendantCord", (cx, ceiling - 1.6, cz), (0.12, 1.6, 0.12), CHARCOAL, METAL, collide=False)
    part("PendantShade", (cx, ceiling - 2.4, cz), (2.4, 0.9, 2.4), WHITE, SMOOTH,
         collide=False, children=point_light((255, 236, 205), 1.8, 30))
    part("PendantBulb", (cx, ceiling - 2.6, cz), (0.6, 0.4, 0.6), (255, 240, 210), NEON, collide=False)


def plant(cx, cz):
    part("PotBody", (cx, FLOOR, cz), (1.6, 1.6, 1.6), ROSE, MARBLE, shape=2, upright_cylinder=True)
    part("Stem", (cx, FLOOR + 1.6, cz), (0.25, 2.4, 0.25), (96, 118, 82), PLASTIC, collide=False)
    for i, (dx, dz, s) in enumerate(((0.9, 0.3, 1.8), (-0.8, 0.6, 1.6), (0.2, -0.9, 1.7))):
        part("Leaf", (cx + dx, FLOOR + 2.6 + i * 0.5, cz + dz), (s, 0.16, s * 0.7),
             (110, 140, 92), PLASTIC, collide=False)


# --------------------------------------------------------------------------
# Kitchen and dining, the big room to the south.
# --------------------------------------------------------------------------

def counter_run(x0, x1, cz, depth=2.4, sink_at=None, stove_at=None):
    """A straight run of cabinets between two x positions, drawn as one solid
    body with fronts laid on it. Appliances are cut into the run by position
    rather than placed as separate furniture, so a counter can never end up
    with a stove floating beside it."""
    length = x1 - x0
    cx = (x0 + x1) / 2
    part("CounterBody", (cx, FLOOR, cz), (length, 2.9, depth), LINEN, WOOD)
    part("CounterTop", (cx, FLOOR + 2.9, cz), (length + 0.2, 0.3, depth + 0.2), CHARCOAL, MARBLE)
    n = max(1, int(length // 2.4))
    for i in range(n):
        x = x0 + (i + 0.5) * length / n
        part("CabinetDoor", (x, FLOOR + 0.3, cz - depth / 2 - 0.05),
             (length / n - 0.2, 2.3, 0.1), CREAM, WOOD, collide=False)
        part("CabinetPull", (x, FLOOR + 2.3, cz - depth / 2 - 0.15),
             (0.6, 0.12, 0.12), BRASS, METAL, collide=False)
    if sink_at is not None:
        part("SinkBasin", (sink_at, FLOOR + 2.5, cz), (3.0, 0.7, 1.6), (208, 212, 214), METAL)
        part("SinkTap", (sink_at, FLOOR + 3.2, cz + 0.7), (0.18, 1.4, 0.18), BRASS, METAL, collide=False)
    if stove_at is not None:
        part("StoveTop", (stove_at, FLOOR + 3.2, cz), (3.4, 0.1, depth - 0.4), CHARCOAL, METAL, collide=False)
        for dx in (-0.8, 0.8):
            for dz in (-0.5, 0.5):
                part("Burner", (stove_at + dx, FLOOR + 3.3, cz + dz), (1.0, 0.08, 1.0),
                     (40, 40, 44), SMOOTH, collide=False, shape=2, upright_cylinder=True)
        part("OvenDoor", (stove_at, FLOOR + 0.4, cz - depth / 2 - 0.08),
             (3.2, 2.0, 0.16), CHARCOAL, METAL, collide=False)


def fridge(cx, cz):
    part("FridgeBody", (cx, FLOOR, cz), (3.0, 7.0, 2.6), (222, 224, 226), METAL)
    part("FridgeDoorUpper", (cx, FLOOR + 2.6, cz - 1.4), (2.9, 4.3, 0.2), (232, 234, 236), METAL, collide=False)
    part("FridgeDoorLower", (cx, FLOOR + 0.1, cz - 1.4), (2.9, 2.4, 0.2), (232, 234, 236), METAL, collide=False)
    part("FridgeHandle", (cx + 1.1, FLOOR + 3.0, cz - 1.6), (0.14, 3.4, 0.14), BRASS, METAL, collide=False)


def island(cx, cz):
    part("IslandBody", (cx, FLOOR, cz), (4.0, 2.9, 8.0), SAGE, WOOD)
    part("IslandTop", (cx, FLOOR + 2.9, cz), (5.2, 0.35, 9.0), CREAM, MARBLE)
    for dz in (-2.6, 0.0, 2.6):
        stool(cx + 3.2, cz + dz)
    part("FruitBowl", (cx, FLOOR + 3.25, cz + 2.8), (0.5, 1.8, 1.8), OAK, WOOD,
         collide=False, shape=2, upright_cylinder=True)


def stool(cx, cz):
    part("StoolSeat", (cx, FLOOR + 2.4, cz), (1.6, 0.3, 1.6), OAK, WOOD, shape=2, upright_cylinder=True)
    part("StoolPole", (cx, FLOOR, cz), (0.25, 2.4, 0.25), CHARCOAL, METAL)
    part("StoolFoot", (cx, FLOOR, cz), (1.2, 0.15, 1.2), CHARCOAL, METAL, shape=2, upright_cylinder=True)


def chair(cx, cz, back):
    """back is a unit (dx, dz) pointing at the side the backrest sits on, so a
    ring of chairs around a table can all be told to face inward."""
    bx, bz = back
    part("ChairSeat", (cx, FLOOR + 1.5, cz), (2.0, 0.35, 2.0), OAK, WOOD)
    part("ChairRest", (cx + bx * 0.85, FLOOR + 1.85, cz + bz * 0.85),
         (0.35 if bx else 2.0, 2.4, 0.35 if bz else 2.0), OAK, WOOD)
    for dx, dz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        part("ChairLeg", (cx + dx * 0.8, FLOOR, cz + dz * 0.8), (0.25, 1.5, 0.25), WALNUT, WOOD)


def dining_table(cx, cz):
    w, l = 5.0, 10.0
    part("DiningTop", (cx, FLOOR + 2.5, cz), (w, 0.35, l), WALNUT, WOOD)
    for dx, dz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        part("DiningLeg", (cx + dx * (w / 2 - 0.5), FLOOR, cz + dz * (l / 2 - 0.6)),
             (0.45, 2.5, 0.45), WALNUT, WOOD)
    for dz in (-3.0, 0.0, 3.0):
        chair(cx - 3.6, cz + dz, (-1, 0))
        chair(cx + 3.6, cz + dz, (1, 0))
    for i, dz in enumerate((-2.0, 2.0)):
        part("Plate", (cx, FLOOR + 2.85, cz + dz), (0.12, 1.6, 1.6), WHITE, MARBLE,
             collide=False, shape=2, upright_cylinder=True)


# --------------------------------------------------------------------------
# Bedroom, bathroom, study, hall.
# --------------------------------------------------------------------------

def bed(cx, cz, head_dz=-1):
    """head_dz says which way the headboard points, because a bed is the one
    piece whose orientation a room is read from."""
    w, l = 6.5, 8.0
    part("BedFrame", (cx, FLOOR + 0.5, cz), (w, 1.2, l), WALNUT, WOOD)
    part("Mattress", (cx, FLOOR + 1.7, cz), (w - 0.4, 1.4, l - 0.4), WHITE, FABRIC)
    part("Duvet", (cx, FLOOR + 3.1, cz - head_dz * 1.2), (w - 0.2, 0.35, l - 3.0), SAGE, FABRIC, collide=False)
    part("Headboard", (cx, FLOOR, cz + head_dz * (l / 2)), (w, 5.0, 0.4), WALNUT, WOOD)
    for dx in (-1, 1):
        part("Pillow", (cx + dx * 1.5, FLOOR + 3.1, cz + head_dz * (l / 2 - 1.4)),
             (2.4, 0.6, 1.6), LINEN, FABRIC, collide=False)
    for dx, dz in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        part("BedLeg", (cx + dx * (w / 2 - 0.4), FLOOR, cz + dz * (l / 2 - 0.4)),
             (0.4, 0.5, 0.4), WALNUT, WOOD)


def nightstand(cx, cz):
    part("NightstandBody", (cx, FLOOR, cz), (2.0, 2.2, 2.0), WALNUT, WOOD)
    part("NightstandTop", (cx, FLOOR + 2.2, cz), (2.2, 0.2, 2.2), WALNUT, WOOD)
    part("TableLampBase", (cx, FLOOR + 2.4, cz), (0.6, 0.9, 0.6), BRASS, METAL)
    part("TableLampShade", (cx, FLOOR + 3.3, cz), (1.4, 1.1, 1.4), CREAM, FABRIC,
         collide=False, children=point_light((255, 224, 176), 1.1, 14))


def wardrobe(cx, cz):
    w, l, h = 2.6, 7.0, 8.0
    part("WardrobeBody", (cx, FLOOR, cz), (w, h, l), WALNUT, WOOD)
    for dz in (-1, 1):
        part("WardrobeDoor", (cx - w / 2 - 0.06, FLOOR + 0.2, cz + dz * (l / 4)),
             (0.12, h - 0.4, l / 2 - 0.2), OAK, WOOD, collide=False)
    for dz in (-0.35, 0.35):
        part("WardrobePull", (cx - w / 2 - 0.18, FLOOR + h / 2, cz + dz),
             (0.14, 1.6, 0.14), BRASS, METAL, collide=False)


def desk(cx, cz):
    part("DeskTop", (cx, FLOOR + 2.4, cz), (3.0, 0.3, 6.0), OAK, WOOD)
    for dz in (-1, 1):
        part("DeskLeg", (cx, FLOOR, cz + dz * 2.6), (2.8, 2.4, 0.3), WALNUT, WOOD)
    part("Monitor", (cx - 0.4, FLOOR + 2.7, cz), (0.2, 2.2, 3.6), CHARCOAL, SMOOTH, collide=False)
    part("MonitorStand", (cx - 0.4, FLOOR + 2.7, cz), (1.2, 0.4, 1.2), CHARCOAL, SMOOTH, collide=False)
    part("Keyboard", (cx + 0.7, FLOOR + 2.7, cz), (1.0, 0.15, 2.6), LINEN, SMOOTH, collide=False)


def bathtub(cx, cz):
    w, l = 4.0, 7.0
    part("TubOuter", (cx, FLOOR, cz), (w, 2.6, l), WHITE, MARBLE)
    part("TubInner", (cx, FLOOR + 0.6, cz), (w - 0.9, 2.2, l - 0.9), (218, 232, 236), SMOOTH, collide=False)
    part("TubTap", (cx, FLOOR + 2.6, cz - l / 2 + 0.5), (0.2, 1.2, 0.2), BRASS, METAL, collide=False)


def toilet(cx, cz):
    part("ToiletBase", (cx, FLOOR, cz), (2.0, 1.4, 2.6), WHITE, MARBLE)
    part("ToiletSeat", (cx, FLOOR + 1.4, cz + 0.2), (2.0, 0.25, 2.2), WHITE, SMOOTH)
    part("ToiletCistern", (cx, FLOOR + 1.4, cz - 1.4), (2.0, 2.6, 0.9), WHITE, MARBLE)


def basin(cx, cz):
    part("BasinPedestal", (cx, FLOOR, cz), (1.2, 2.6, 1.2), WHITE, MARBLE)
    part("BasinBowl", (cx, FLOOR + 2.6, cz), (2.6, 0.9, 2.2), WHITE, MARBLE)
    part("BasinTap", (cx - 0.9, FLOOR + 3.5, cz), (0.18, 1.1, 0.18), BRASS, METAL, collide=False)
    part("Mirror", (cx - 1.4, FLOOR + 4.6, cz), (0.12, 3.4, 2.6), (206, 220, 226), SMOOTH, collide=False)


def console_table(cx, cz):
    part("ConsoleTop", (cx, FLOOR + 2.6, cz), (1.8, 0.28, 7.0), WALNUT, WOOD)
    for dz in (-1, 1):
        part("ConsoleLeg", (cx, FLOOR, cz + dz * 3.0), (1.6, 2.6, 0.3), WALNUT, WOOD)
    part("HallBowl", (cx, FLOOR + 2.88, cz), (0.4, 1.4, 1.4), BRASS, METAL,
         collide=False, shape=2, upright_cylinder=True)


def flat_rug(cx, cz, w, l, color=ROSE):
    part("Rug", (cx, FLOOR, cz), (w, 0.08, l), color, FABRIC, collide=False)
    part("RugBorder", (cx, FLOOR + 0.08, cz), (w - 1.6, 0.06, l - 1.6), CREAM, FABRIC, collide=False)


def chandelier(cx, cz, ceiling):
    """The hall is double height, so the fitting has to be long enough to read
    from the floor rather than a pendant lost in the ceiling."""
    part("ChandelierCord", (cx, ceiling - 9.0, cz), (0.16, 9.0, 0.16), BRASS, METAL, collide=False)
    part("ChandelierHub", (cx, ceiling - 10.2, cz), (2.0, 1.2, 2.0), BRASS, METAL, collide=False)
    for dx, dz in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        part("ChandelierArm", (cx + dx * 1.6, ceiling - 10.6, cz + dz * 1.6),
             (1.2, 0.9, 1.2), CREAM, FABRIC, collide=False,
             children=point_light((255, 232, 196), 1.5, 26))


# --------------------------------------------------------------------------

CEILING = 14.0

# This room is forty studs wide but only ten deep, so every long piece is
# turned to run along it. Left unturned, the sofa alone reaches wall to wall
# and the room stops being somewhere a crawler can cross.
#
# Nursery west, living room east, and a clear middle between them: the toddler
# can see where it is going long before it can get there, which is the point.
rug(-2.0, -21.5)
with turned(-8.0, -23.8):
    crib(-8.0, -23.8)
with turned(-7.5, -18.6):
    dresser(-7.5, -18.6)
toy_chest(3.0, -24.8)
rocker(-9.5, -20.0)
plant(-10.0, -17.5)

# Sofa on one wall, television on the other, and nothing between them. A
# coffee table would fit the room and close the only way through it, so the
# one that would have gone here stands in the hall instead.
with turned(24.0, -23.8):
    sofa(24.0, -23.8)
with turned(24.0, -17.9):
    tv_unit(24.0, -17.9)
with turned(15.5, -24.8):
    bookshelf(15.5, -24.8)
floor_lamp(28.2, -18.5)
plant(28.2, -24.5)

pendant(-3.0, -21.5, CEILING)
pendant(24.0, -21.5, CEILING)

# Kitchen and dining, x -6..28 by z 25..52. Counters hug the north wall so the
# middle of the room stays walkable; the island splits cooking from eating
# without a wall, which is what makes the two ends readable as one place.
KITCHEN_CEILING = 13.5
counter_run(-4.0, 14.0, 26.4, sink_at=2.0, stove_at=10.0)
fridge(17.5, 26.4)
island(6.0, 34.0)
dining_table(12.0, 45.0)
bookshelf(27.0, 40.0)
plant(-4.0, 50.0)
plant(25.0, 28.0)
floor_lamp(-4.0, 38.0)
pendant(6.0, 34.0, KITCHEN_CEILING)
pendant(12.0, 45.0, KITCHEN_CEILING)

# Bedroom, x 6..23 by z -9..4. Bed against the north wall, everything else
# arranged around the walk from the door to it.
bed(14.0, -3.0, head_dz=-1)
nightstand(9.5, -6.0)
nightstand(18.5, -6.0)
wardrobe(21.6, 0.0)
flat_rug(14.0, 2.0, 9.0, 6.0, SKY)
plant(7.5, 2.5)
pendant(14.0, -2.0, CEILING)

# Bathroom, x 21..29 by z 5..17. Narrow, so the three fixtures go one per wall
# and the middle is left clear.
bathtub(25.0, 8.0)
toilet(27.0, 13.5)
basin(23.0, 14.5)
pendant(25.0, 12.0, CEILING)

# Study, x 5..17 by z 10..18.
desk(7.5, 14.0)
chair(10.0, 14.0, (1, 0))
bookshelf(16.0, 13.0)
plant(6.5, 17.0)
floor_lamp(15.5, 17.0)
pendant(11.0, 14.0, CEILING)

# Entry hall, x -24..0 by z -10..5. Double height at 31 studs, so it is
# deliberately underfurnished: the volume is the thing you notice, and a
# toddler at bodyScale 0.30 should feel small standing in it.
HALL_CEILING = 31.0
flat_rug(-12.0, -2.5, 14.0, 10.0, ROSE)
coffee_table(-12.0, -2.5)
console_table(-22.5, -2.5)
plant(-22.0, 3.0)
plant(-22.0, -8.0)
chandelier(-12.0, -2.5, HALL_CEILING)

body = "\n".join(_items)
OUT.write_text(f'''<roblox version="4">
<Item class="Model" referent="RBXFURNROOT">
<Properties>
<string name="Name">Furniture</string>
</Properties>
{body}
</Item>
</roblox>
''')
print(f"wrote {OUT} ({len(_items)} parts)")
