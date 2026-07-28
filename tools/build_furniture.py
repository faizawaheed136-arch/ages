#!/usr/bin/env python3
"""Generates assets/Furniture.rbxmx.

This file is the source of truth for the furniture, not the .rbxmx it emits —
edit here and re-run. The output is committed so the game builds without a
Python step.

Furniture lives in its own model, separate from assets/House.rbxmx, because the
house is re-exported from Studio by hand: anything sharing that file would be
overwritten every time the building gets redecorated.

Everything here is deliberately blocky and cheap to replace. Each piece is its
own Model, so real art can be swapped in one object at a time. The one piece
that matters structurally is the rug's event anchor, and even that is a
separate invisible part, so swapping the rug art later cannot break the event.


How placement works
-------------------
Rooms come from house_plan.py, transcribed from the house itself, rather than
guessed from open floor — open floor does not know where the building ends, and
an earlier pass put a whole kitchen on the lawn. `tools/read_house.py plan`
prints the geometry those numbers were read off.

Every wall-standing builder is authored once, facing +Z, with its local origin
on its BACK face and centred across X. Placing it against a wall is then just a
matter of which quarter turn to apply, so a sofa never has to be re-measured to
move from one wall to another. Free-standing builders are authored around their
centre and say so.
"""

import base64
import struct
from contextlib import contextmanager

from house_plan import FURNITURE as OUT
from house_plan import A, B, C, D, U1, U2, U3

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
_parts = 0

# (pivot_x, pivot_z, quarter_turns, floor_y) for whatever is being emitted.
_ctx = (0.0, 0.0, 0, 0.0)

# Quarter turns about Y, applied to a local offset. One turn sends x to z.
_TURN_OFFSET = {
    0: lambda dx, dz: (dx, dz),
    1: lambda dx, dz: (dz, -dx),
    2: lambda dx, dz: (-dx, -dz),
    3: lambda dx, dz: (-dz, dx),
}
_TURN_MATRIX = {
    0: "<R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22>",
    1: "<R00>0</R00><R01>0</R01><R02>1</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>-1</R20><R21>0</R21><R22>0</R22>",
    2: "<R00>-1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>-1</R22>",
    3: "<R00>0</R00><R01>0</R01><R02>-1</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>1</R20><R21>0</R21><R22>0</R22>",
}

# Which quarter turn puts a piece's back against which wall. Named for the wall
# rather than the direction it faces, because that is how a room gets laid out.
_BACK = {"north": 0, "west": 1, "south": 2, "east": 3}


@contextmanager
def against(room, side, along):
    """Emit a wall-standing builder with its back on `side` of `room`."""
    global _ctx
    previous = _ctx
    px, pz = room.wall(side, along)
    _ctx = (px, pz, _BACK[side], room.floor)
    try:
        yield
    finally:
        _ctx = previous


@contextmanager
def free(room, x, z, side="north"):
    """Emit a builder at an explicit spot in the room, for the pieces that stand
    away from every wall."""
    global _ctx
    previous = _ctx
    _ctx = (x, z, _BACK[side], room.floor)
    try:
        yield
    finally:
        _ctx = previous


def piece(label):
    """Wraps a builder so everything it emits lands in one Model.

    The grouping is not cosmetic. It is what lets the checker tell a sink set
    into a counter — parts of one object, allowed to share space — from a plant
    standing inside a sofa, which is a mistake. It also means each blocky
    stand-in is one selectable object, so it can be swapped for real art
    without disturbing anything around it.
    """

    def decorate(build):
        def wrapped(*args, **kwargs):
            start = len(_items)
            build(*args, **kwargs)
            children = _items[start:]
            del _items[start:]
            _items.append(f'''<Item class="Model" referent="{_next_ref()}">
<Properties>
<string name="Name">{label}</string>
</Properties>
{"".join(children)}
</Item>''')

        wrapped.__name__ = build.__name__
        wrapped.__doc__ = build.__doc__
        return wrapped

    return decorate


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


def part(name, offset, size, color, material=SMOOTH, transparency=0.0,
         collide=True, shape=1, upright_cylinder=False, tags=None, attrs=None,
         children=""):
    """offset is (dx, dy, dz) in the builder's own space: dx across, dz forward
    from its back face, and dy up from the floor to the part's underside."""
    global _parts
    _parts += 1
    dx, dy, dz = offset
    sx, sy, sz = size
    px, pz, turns, floor = _ctx

    ox, oz = _TURN_OFFSET[turns](dx, dz)
    x, z = px + ox, pz + oz
    y = floor + dy + sy / 2

    if upright_cylinder:
        # Cylinder parts run along their X axis, so a disc lying flat needs X
        # rotated onto Y. sx becomes thickness; sy/sz become the diameter.
        # Discs are circular about that axis, so the room turn does not apply.
        rot = "<R00>0</R00><R01>-1</R01><R02>0</R02><R10>1</R10><R11>0</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22>"
        y = floor + dy + sx / 2
    else:
        rot = _TURN_MATRIX[turns]

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
# Wall pieces. Local origin sits on the back face, centred across X, so depth
# runs 0..d forward and the piece can be stood against any wall unchanged.
# --------------------------------------------------------------------------

@piece("Crib")
def crib(length=5.5, depth=3.0, height=3.2):
    part("CribBase", (0, 1.0, depth / 2), (length, 0.3, depth), OAK, WOOD)
    part("CribMattress", (0, 1.3, depth / 2), (length - 0.5, 0.5, depth - 0.5), WHITE, FABRIC)
    part("CribBlanket", (1.0, 1.8, depth / 2), (length / 2, 0.12, depth - 0.6), SKY, FABRIC, collide=False)
    for sx in (-1, 1):
        for sz in (0.15, depth - 0.15):
            part("CribPost", (sx * (length / 2 - 0.15), 0, sz), (0.3, height, 0.3), OAK, WOOD)
    # Bars: the view out of the first place a life is kept.
    n = 9
    for i in range(n):
        x = -length / 2 + 0.5 + i * (length - 1.0) / (n - 1)
        for dz in (0.15, depth - 0.15):
            part("CribBar", (x, 1.3, dz), (0.16, height - 1.5, 0.16), OAK, WOOD, collide=False)
    for dz in (0.15, depth - 0.15):
        part("CribRail", (0, height - 0.25, dz), (length, 0.25, 0.34), OAK, WOOD)


@piece("Dresser")
def dresser(length=4.5, depth=2.4, height=3.0):
    part("DresserBody", (0, 0, depth / 2), (length, height, depth), WALNUT, WOOD)
    for i in range(3):
        dy = 0.35 + i * 0.85
        part("DresserDrawer", (0, dy, depth - 0.05), (length - 0.4, 0.7, 0.12), LINEN, SMOOTH, collide=False)
        part("DresserPull", (0, dy + 0.28, depth + 0.03), (0.8, 0.12, 0.12), BRASS, METAL, collide=False)
    part("DresserTop", (0, height, depth / 2 + 0.15), (length + 0.3, 0.2, depth + 0.3), WALNUT, WOOD)


@piece("ToyChest")
def toy_chest(length=3.2, depth=2.6):
    part("ToyChest", (0, 0, depth / 2), (length, 1.8, depth), SAGE, WOOD)
    part("ToyChestLid", (0, 1.8, depth / 2 + 0.1), (length + 0.2, 0.3, depth + 0.2), CREAM, WOOD)
    for dx, dz, col in ((-1.9, depth + 0.6, ROSE), (-2.2, depth + 1.5, SKY), (-2.7, depth + 0.9, BRASS)):
        part("Block", (dx, 0, dz), (0.9, 0.9, 0.9), col, PLASTIC)


@piece("RockingChair")
def rocker(depth=2.8):
    part("ChairSeat", (0, 1.2, depth / 2 + 0.2), (2.6, 0.5, 2.6), LINEN, FABRIC)
    part("ChairBack", (0, 1.7, 0.25), (2.6, 2.4, 0.5), LINEN, FABRIC)
    for sx in (-1, 1):
        for dz in (0.6, depth - 0.4):
            part("ChairLeg", (sx * 1.0, 0, dz), (0.28, 1.2, 0.28), WALNUT, WOOD)


@piece("Sofa")
def sofa(length=8.5, seat=3.4):
    depth = seat + 0.8
    part("SofaBack", (0, 0.6, 0.4), (length, 3.0, 0.8), SAGE, FABRIC)
    part("SofaBase", (0, 0.6, 0.8 + seat / 2), (length, 1.0, seat), SAGE, FABRIC)
    for sx in (-1, 1):
        part("SofaArm", (sx * (length / 2 - 0.4), 1.6, 0.8 + seat / 2), (0.8, 1.2, seat), SAGE, FABRIC)
    for dx in (-2.2, 0.0, 2.2):
        part("Cushion", (dx, 1.6, 0.8 + seat / 2 - 0.2), (2.0, 0.4, seat - 0.6), LINEN, FABRIC, collide=False)
    for sx in (-1, 1):
        for dz in (1.0, depth - 0.4):
            part("SofaLeg", (sx * (length / 2 - 0.6), 0, dz), (0.3, 0.6, 0.3), WALNUT, WOOD)


@piece("Television")
def tv_unit(length=6.5, depth=1.8):
    part("TVStand", (0, 0, depth / 2), (length, 1.6, depth), WALNUT, WOOD)
    part("TVScreen", (0, 1.6, depth / 2), (length - 0.7, 3.4, 0.25), CHARCOAL, SMOOTH)
    part("TVGlass", (0, 1.75, depth / 2 + 0.15), (length - 1.1, 3.0, 0.05), (24, 26, 32), SMOOTH, collide=False)


@piece("Bookshelf")
def bookshelf(length=5.0, depth=1.4, height=7.0):
    part("ShelfBack", (0, 0, 0.15), (length, height, 0.3), WALNUT, WOOD)
    for i in range(4):
        part("Shelf", (0, 0.6 + i * 1.9, 0.3 + depth / 2), (length, 0.2, depth), WALNUT, WOOD)
        for j, col in enumerate((ROSE, SKY, SAGE, CREAM, BRASS)):
            part("Book", (-1.8 + j * 0.9, 0.8 + i * 1.9, 0.3 + depth / 2),
                 (0.25, 1.2, 0.9), col, SMOOTH, collide=False)
    for sx in (-1, 1):
        part("ShelfSide", (sx * (length / 2), 0, 0.3 + depth / 2), (0.2, height, depth), WALNUT, WOOD)


@piece("KitchenCounter")
def counter_run(length, depth=2.4, sink_at=None, stove_at=None):
    """A straight run of cabinets. Appliances are cut into the run by position
    rather than placed as separate furniture, so a counter can never end up
    with a stove floating beside it."""
    part("CounterBody", (0, 0, depth / 2), (length, 2.9, depth), LINEN, WOOD)
    part("CounterTop", (0, 2.9, depth / 2 + 0.1), (length + 0.2, 0.3, depth + 0.2), CHARCOAL, MARBLE)
    n = max(1, int(length // 2.4))
    for i in range(n):
        dx = -length / 2 + (i + 0.5) * length / n
        part("CabinetDoor", (dx, 0.3, depth - 0.05), (length / n - 0.2, 2.3, 0.1), CREAM, WOOD, collide=False)
        part("CabinetPull", (dx, 2.3, depth + 0.05), (0.6, 0.12, 0.12), BRASS, METAL, collide=False)
    if sink_at is not None:
        part("SinkBasin", (sink_at, 2.5, depth / 2), (3.0, 0.7, depth - 0.8), (208, 212, 214), METAL)
        part("SinkTap", (sink_at, 3.2, 0.5), (0.18, 1.4, 0.18), BRASS, METAL, collide=False)
    if stove_at is not None:
        part("StoveTop", (stove_at, 3.2, depth / 2), (3.4, 0.1, depth - 0.4), CHARCOAL, METAL, collide=False)
        for dx in (-0.8, 0.8):
            for dz in (-0.5, 0.5):
                part("Burner", (stove_at + dx, 3.3, depth / 2 + dz), (1.0, 0.08, 1.0),
                     (40, 40, 44), SMOOTH, collide=False, shape=2, upright_cylinder=True)
        part("OvenDoor", (stove_at, 0.4, depth - 0.08), (3.2, 2.0, 0.16), CHARCOAL, METAL, collide=False)


@piece("Fridge")
def fridge(length=3.0, depth=2.6, height=7.0):
    part("FridgeBody", (0, 0, depth / 2), (length, height, depth), (222, 224, 226), METAL)
    part("FridgeDoorUpper", (0, 2.6, depth - 0.1), (length - 0.1, 4.3, 0.2), (232, 234, 236), METAL, collide=False)
    part("FridgeDoorLower", (0, 0.1, depth - 0.1), (length - 0.1, 2.4, 0.2), (232, 234, 236), METAL, collide=False)
    part("FridgeHandle", (length / 2 - 0.4, 3.0, depth + 0.05), (0.14, 3.4, 0.14), BRASS, METAL, collide=False)


@piece("Wardrobe")
def wardrobe(length=7.0, depth=2.6, height=8.0):
    part("WardrobeBody", (0, 0, depth / 2), (length, height, depth), WALNUT, WOOD)
    for sx in (-1, 1):
        part("WardrobeDoor", (sx * (length / 4), 0.2, depth + 0.06),
             (length / 2 - 0.2, height - 0.4, 0.12), OAK, WOOD, collide=False)
    for sx in (-1, 1):
        part("WardrobePull", (sx * 0.35, height / 2, depth + 0.18), (0.14, 1.6, 0.14), BRASS, METAL, collide=False)


@piece("Bed")
def bed(length=6.5, depth=8.0):
    part("Headboard", (0, 0, 0.2), (length, 5.0, 0.4), WALNUT, WOOD)
    part("BedFrame", (0, 0.5, 0.4 + depth / 2), (length, 1.2, depth), WALNUT, WOOD)
    part("Mattress", (0, 1.7, 0.4 + depth / 2), (length - 0.4, 1.4, depth - 0.4), WHITE, FABRIC)
    part("Duvet", (0, 3.1, 0.4 + depth / 2 + 1.2), (length - 0.2, 0.35, depth - 3.0), SAGE, FABRIC, collide=False)
    for sx in (-1, 1):
        part("Pillow", (sx * 1.5, 3.1, 1.8), (2.4, 0.6, 1.6), LINEN, FABRIC, collide=False)
    for sx in (-1, 1):
        for dz in (0.8, depth):
            part("BedLeg", (sx * (length / 2 - 0.4), 0, dz), (0.4, 0.5, 0.4), WALNUT, WOOD)


@piece("Nightstand")
def nightstand(depth=2.0):
    part("NightstandBody", (0, 0, depth / 2), (2.0, 2.2, depth), WALNUT, WOOD)
    part("NightstandTop", (0, 2.2, depth / 2 + 0.1), (2.2, 0.2, depth + 0.2), WALNUT, WOOD)
    part("TableLampBase", (0, 2.4, depth / 2), (0.6, 0.9, 0.6), BRASS, METAL)
    part("TableLampShade", (0, 3.3, depth / 2), (1.4, 1.1, 1.4), CREAM, FABRIC,
         collide=False, children=point_light((255, 224, 176), 1.1, 14))


@piece("Desk")
def desk(length=6.0, depth=3.0):
    part("DeskTop", (0, 2.4, depth / 2), (length, 0.3, depth), OAK, WOOD)
    for sx in (-1, 1):
        part("DeskLeg", (sx * (length / 2 - 0.4), 0, depth / 2), (0.3, 2.4, depth - 0.4), WALNUT, WOOD)
    part("Monitor", (0, 2.7, 0.9), (3.6, 2.2, 0.2), CHARCOAL, SMOOTH, collide=False)
    part("MonitorStand", (0, 2.7, 0.9), (1.2, 0.4, 1.2), CHARCOAL, SMOOTH, collide=False)
    part("Keyboard", (0, 2.7, depth - 0.7), (2.6, 0.15, 1.0), LINEN, SMOOTH, collide=False)


@piece("ConsoleTable")
def console_table(length=7.0, depth=1.8):
    part("ConsoleTop", (0, 2.6, depth / 2), (length, 0.28, depth), WALNUT, WOOD)
    for sx in (-1, 1):
        part("ConsoleLeg", (sx * (length / 2 - 0.4), 0, depth / 2), (0.3, 2.6, depth - 0.2), WALNUT, WOOD)
    part("HallBowl", (0, 2.88, depth / 2), (0.4, 1.4, 1.4), BRASS, METAL,
         collide=False, shape=2, upright_cylinder=True)


@piece("Bathtub")
def bathtub(length=7.0, depth=4.0):
    part("TubOuter", (0, 0, depth / 2), (length, 2.6, depth), WHITE, MARBLE)
    part("TubInner", (0, 0.6, depth / 2), (length - 0.9, 2.2, depth - 0.9), (218, 232, 236), SMOOTH, collide=False)
    part("TubTap", (-length / 2 + 0.5, 2.6, depth / 2), (0.2, 1.2, 0.2), BRASS, METAL, collide=False)


@piece("Toilet")
def toilet(depth=2.6):
    part("ToiletCistern", (0, 1.4, 0.45), (2.0, 2.6, 0.9), WHITE, MARBLE)
    part("ToiletBase", (0, 0, 1.7), (2.0, 1.4, 1.8), WHITE, MARBLE)
    part("ToiletSeat", (0, 1.4, 1.7), (2.0, 0.25, 1.8), WHITE, SMOOTH)


@piece("Basin")
def basin(depth=2.2):
    part("BasinPedestal", (0, 0, depth / 2), (1.2, 2.6, 1.2), WHITE, MARBLE)
    part("BasinBowl", (0, 2.6, depth / 2), (2.6, 0.9, depth), WHITE, MARBLE)
    part("BasinTap", (0, 3.5, 0.3), (0.18, 1.1, 0.18), BRASS, METAL, collide=False)
    part("Mirror", (0, 4.6, 0.06), (2.6, 3.4, 0.12), (206, 220, 226), SMOOTH, collide=False)


# --------------------------------------------------------------------------
# Free-standing pieces. Local origin is the centre of the footprint.
# --------------------------------------------------------------------------

@piece("Rug")
def rug(diameter=10.0, event_id=None):
    """The rug from childhood_across_the_rug. Ten studs across, which at a
    crawler's walkSpeed of 4 is a genuine journey and at sixteen is one step —
    the same object measuring the body that crosses it."""
    part("Rug", (0, 0, 0), (0.08, diameter, diameter), ROSE, FABRIC, collide=False,
         shape=2, upright_cylinder=True)
    part("RugInner", (0, 0.08, 0), (0.06, diameter * 0.7, diameter * 0.7), CREAM, FABRIC,
         collide=False, shape=2, upright_cylinder=True)
    part("RugCenter", (0, 0.14, 0), (0.05, diameter * 0.3, diameter * 0.3), SAGE, FABRIC,
         collide=False, shape=2, upright_cylinder=True)
    if event_id:
        # Kept separate from the art on purpose: the rug can be replaced with a
        # nicer model without touching the thing that makes the event fire.
        part("RugEventAnchor", (0, 0, 0), (2, 2, 2), WHITE, PLASTIC,
             transparency=1, collide=False,
             tags=["AgesEvent"], attrs={"EventId": event_id})


@piece("Rug")
def flat_rug(w, l, color=ROSE):
    part("Rug", (0, 0, 0), (w, 0.08, l), color, FABRIC, collide=False)
    part("RugBorder", (0, 0.08, 0), (w - 1.6, 0.06, l - 1.6), CREAM, FABRIC, collide=False)


@piece("CoffeeTable")
def coffee_table(length=5.0, depth=3.6):
    part("TableTop", (0, 1.2, 0), (length, 0.25, depth), OAK, WOOD)
    for sx in (-1, 1):
        for sz in (-1, 1):
            part("TableLeg", (sx * (length / 2 - 0.4), 0, sz * (depth / 2 - 0.4)),
                 (0.3, 1.2, 0.3), WALNUT, WOOD)
    part("Bowl", (0, 1.45, 0), (0.5, 1.6, 1.6), SKY, MARBLE, collide=False,
         shape=2, upright_cylinder=True)


@piece("Chair")
def chair(back=(0, -1)):
    """back is a unit (dx, dz) pointing at the side the backrest sits on, so a
    ring of chairs around a table can all be told to face inward."""
    bx, bz = back
    part("ChairSeat", (0, 1.5, 0), (2.0, 0.35, 2.0), OAK, WOOD)
    part("ChairRest", (bx * 0.85, 1.85, bz * 0.85),
         (0.35 if bx else 2.0, 2.4, 0.35 if bz else 2.0), OAK, WOOD)
    for sx in (-1, 1):
        for sz in (-1, 1):
            part("ChairLeg", (sx * 0.8, 0, sz * 0.8), (0.25, 1.5, 0.25), WALNUT, WOOD)


@piece("DiningTable")
def dining_table(length=10.0, depth=5.0):
    part("DiningTop", (0, 2.5, 0), (length, 0.35, depth), WALNUT, WOOD)
    for sx in (-1, 1):
        for sz in (-1, 1):
            part("DiningLeg", (sx * (length / 2 - 0.6), 0, sz * (depth / 2 - 0.5)),
                 (0.45, 2.5, 0.45), WALNUT, WOOD)
    for dx in (-2.2, 2.2):
        part("Plate", (dx, 2.85, 0), (0.12, 1.6, 1.6), WHITE, MARBLE,
             collide=False, shape=2, upright_cylinder=True)


@piece("KitchenIsland")
def island(length=6.0, depth=3.4):
    part("IslandBody", (0, 0, 0), (length, 2.9, depth), SAGE, WOOD)
    part("IslandTop", (0, 2.9, 0), (length + 1.0, 0.35, depth + 1.0), CREAM, MARBLE)
    part("FruitBowl", (-length / 4, 3.25, 0), (0.5, 1.8, 1.8), OAK, WOOD,
         collide=False, shape=2, upright_cylinder=True)


@piece("Stool")
def stool():
    part("StoolSeat", (0, 2.4, 0), (1.6, 0.3, 1.6), OAK, WOOD, shape=2, upright_cylinder=True)
    part("StoolPole", (0, 0, 0), (0.25, 2.4, 0.25), CHARCOAL, METAL)
    part("StoolFoot", (0, 0, 0), (1.2, 0.15, 1.2), CHARCOAL, METAL, shape=2, upright_cylinder=True)


@piece("FloorLamp")
def floor_lamp():
    part("LampBase", (0, 0, 0), (1.4, 0.3, 1.4), BRASS, METAL, shape=2, upright_cylinder=True)
    part("LampPole", (0, 0.3, 0), (0.2, 5.4, 0.2), BRASS, METAL)
    part("LampShade", (0, 5.4, 0), (2.0, 1.6, 2.0), CREAM, FABRIC,
         collide=False, children=point_light((255, 226, 180), 1.4, 22))


@piece("Plant")
def plant():
    part("PotBody", (0, 0, 0), (1.6, 1.6, 1.6), ROSE, MARBLE, shape=2, upright_cylinder=True)
    part("Stem", (0, 1.6, 0), (0.25, 2.4, 0.25), (96, 118, 82), PLASTIC, collide=False)
    for i, (dx, dz, s) in enumerate(((0.9, 0.3, 1.8), (-0.8, 0.6, 1.6), (0.2, -0.9, 1.7))):
        part("Leaf", (dx, 2.6 + i * 0.5, dz), (s, 0.16, s * 0.7), (110, 140, 92), PLASTIC, collide=False)


@piece("CeilingLight")
def pendant(drop):
    """drop is how far below the ceiling the shade hangs. The upper floor is
    vaulted to the roof, so the same fitting needs a much longer cord up there
    than it does downstairs."""
    part("PendantCord", (0, -drop, 0), (0.12, drop, 0.12), CHARCOAL, METAL, collide=False)
    part("PendantShade", (0, -drop - 0.9, 0), (2.4, 0.9, 2.4), WHITE, SMOOTH,
         collide=False, children=point_light((255, 236, 205), 1.8, 30))
    part("PendantBulb", (0, -drop - 1.1, 0), (0.6, 0.4, 0.6), (255, 240, 210), NEON, collide=False)


# How far above the floor the lowest part of a light fitting hangs. Set from the
# floor rather than from the ceiling because the upper storey is vaulted to the
# roof: a drop that looks right downstairs left the upstairs lights hanging at
# 3.4 studs, head height, right where you walk. Safe range 7.0-9.5 — below 7 a
# character walks into it, above 9.5 it stops lighting the room.
LIGHT_HEIGHT = 7.8


def ceiling_light(room, x, z, height=LIGHT_HEIGHT):
    # dy is measured up from whatever the context calls the floor, so hanging a
    # fitting is a matter of calling the ceiling the floor and going down. The
    # 1.1 is how far the bulb sits below the cord's top in pendant().
    global _ctx
    previous = _ctx
    _ctx = (x, z, 0, room.ceiling)
    try:
        pendant(room.ceiling - room.floor - height - 1.1)
    finally:
        _ctx = previous


# --------------------------------------------------------------------------
# The layout. Rooms A..U3 come from house_plan.py, which carries their walls,
# floor heights and the windows and doorways each one has to work around —
# those spans are the reason a piece sits where it does rather than somewhere
# more obvious. Run `python3 tools/read_house.py check` after editing.
# --------------------------------------------------------------------------

# Room A holds both ends of the toddler years: the nursery it starts in and the
# living room it is growing toward, with the middle left open so one can be
# seen from the other. The doorway at x 4..16 in the south wall is the only way
# out and stays clear.
with against(A, "south", -8.0):
    crib()
with against(A, "north", 6.0):
    dresser()
with against(A, "south", -1.0):
    rocker()
with free(A, -4.0, -21.5):
    rug(10.0, event_id="childhood_across_the_rug")

# Living end: the television takes the unglazed east wall, and the sofa sits
# around the corner from it against the north wall rather than facing it head
# on. Facing it meant an 8.5-stud sofa lying across a room only twelve deep,
# which left 1.7 studs at either end — you could see the floor in front of the
# television and never reach it.
with against(A, "east", -21.5):
    tv_unit()
# Stood half a stud off the wall rather than flush to it: the curtain over
# x 21..25.5 hangs 0.3 studs proud of the wall face, and a sofa pushed right
# back into it clipped the cloth.
with free(A, 23.0, -27.0, side="north"):
    sofa()
with free(A, 17.0, -26.0):
    floor_lamp()
ceiling_light(A, -4.0, -21.5)
ceiling_light(A, 22.0, -21.5)

# Hall and dining. The table sits west of the staircase; the west wall can only
# take something short between the door and the window.
with free(B, 13.0, -1.0):
    dining_table()
for dx in (-3.0, 0.0, 3.0):
    with free(B, 13.0 + dx, -4.2):
        chair(back=(0, -1))
    with free(B, 13.0 + dx, 2.2):
        chair(back=(0, 1))
with against(B, "west", -8.2):
    console_table(3.5)
ceiling_light(B, 13.0, -1.0)
ceiling_light(B, 26.0, -8.0)

# Kitchen. Counters take the two walls the doorway is not in, so the way in
# from the hall stays clear.
with against(C, "south", 10.5):
    counter_run(12.0, sink_at=-3.0, stove_at=3.0)
with against(C, "east", 12.0):
    counter_run(4.0)
with against(C, "west", 11.0):
    fridge()
ceiling_light(C, 10.0, 13.0)

# Bathroom.
with against(D, "south", 25.0):
    bathtub(6.0, 3.4)
with against(D, "east", 11.0):
    toilet()
with against(D, "west", 13.0):
    basin()
ceiling_light(D, 25.0, 13.0)

# Main bedroom. The house already stands something of its own in the north-west
# corner, x 4.2..7.7 by z -10.7..-7.4, so the bed is pushed east of it.
with against(U1, "north", 13.5):
    bed()
with against(U1, "north", 8.9):
    nightstand()
with against(U1, "south", 8.0):
    wardrobe()
with free(U1, 13.0, 3.0):
    flat_rug(9.0, 5.0, SKY)
ceiling_light(U1, 13.0, -1.0)

# Landing: a short gallery, so it gets a runner and little else.
with free(U2, -2.0, -1.0):
    flat_rug(6.0, 12.0, ROSE)
with against(U2, "west", -1.0):
    console_table(5.0)
ceiling_light(U2, -2.0, -1.0)

# Child's room, with the desk it grows into at the far end. The room is 26 by
# 10, so the bed stands against the west wall with its length running into the
# room: laid against a long wall its 8 studs of depth left a two-stud passage,
# which is the same mistake that once sealed the living room.
with against(U3, "west", 14.0):
    bed()
with against(U3, "north", 20.0):
    desk()
with against(U3, "south", 20.0):
    wardrobe()
with against(U3, "south", 27.0):
    toy_chest()
with free(U3, 17.0, 14.0):
    flat_rug(8.0, 5.0, SAGE)
ceiling_light(U3, 10.0, 14.0)
ceiling_light(U3, 24.0, 14.0)

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
print(f"wrote {OUT} ({_parts} parts in {len(_items)} pieces)")
