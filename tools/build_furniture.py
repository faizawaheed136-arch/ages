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

import rbxmx
from rbxmx import FABRIC, MARBLE, METAL, NEON, PLASTIC, SMOOTH, WOOD
from rbxmx import against, free, part, piece, point_light
from house_plan import DELIVERY_MODE_ATTRIBUTE, DELIVERY_TAG
from house_plan import FURNITURE as OUT
from house_plan import A, B, C, D, U1, U2, U3

rbxmx.begin("RBXFURN")

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
    with rbxmx.at(x, z, floor=room.ceiling):
        pendant(room.ceiling - room.floor - height - 1.1)


# --------------------------------------------------------------------------
# Delivery points. The world can bring an event to you — post on the mat, the
# phone ringing in the hall, someone at the door — and each of those modes needs
# somewhere in the house to happen. That somewhere is an invisible marker rather
# than a coordinate in code, so the mat can be moved, re-dressed or replaced
# entirely and the post still lands on it.
#
# Same split as the rug's event anchor, and for the same reason: the visible
# object is a stand-in that will be swapped for real art, and the thing that
# makes the delivery work must not go with it. Each marker is emitted inside the
# piece it belongs to so the two move together.
#
# The marker is what the game reads, so its *pose* is content: the letter is
# placed at the point's centre, and a visitor walks straight along the point's
# facing. Both are noted where they matter below.
# --------------------------------------------------------------------------

# Deliberately shorter than 0.4 studs and sitting low: read_house.py treats
# anything taller as something a body would walk into, and a marker nobody can
# see is not an obstacle. Keeping it under the threshold means these cost the
# room no walkable floor rather than needing to be special-cased by name the way
# RugEventAnchor is.
_MARKER_HEIGHT = 0.2


def delivery_point(name, offset, mode, size=None):
    """An invisible spot the world may put a delivery at.

    offset follows the same convention as part(): dy is the underside, so a
    marker's centre — which is where a letter actually lands — sits half its
    height above whatever surface it is standing on.
    """
    part(name, offset, size or (1.6, _MARKER_HEIGHT, 1.2), WHITE, PLASTIC,
         transparency=1, collide=False,
         tags=[DELIVERY_TAG], attrs={DELIVERY_MODE_ATTRIBUTE: mode})


@piece("Doormat")
def doormat(length=3.4, depth=2.2):
    """Where the post lands. Wall piece: back on the wall, depth running in."""
    part("MatCloth", (0, 0, depth / 2), (length, 0.08, depth), WALNUT, FABRIC, collide=False)
    part("MatBorder", (0, 0.08, depth / 2), (length - 0.7, 0.06, depth - 0.7), OAK, FABRIC, collide=False)
    # Standing on the mat's border rather than sunk into it: the envelope is
    # centred on this marker and lifts itself a hair further, so an envelope
    # half-buried in a rug is not a thing that can happen.
    delivery_point("LetterPoint", (0, 0.14, depth / 2), "Letter", size=(1.2, 0.04, 0.9))


@piece("Telephone")
def telephone(dx=0.0, top=2.9, depth=0.9):
    """A hall phone standing on whatever surface it is handed. `top` is that
    surface's height above the floor and dx/depth place it across and along —
    all in the surface's own local frame, so the phone is authored inside the
    same `with` block as the table it stands on and moves when the table does."""
    part("PhoneBase", (dx, top, depth), (0.9, 0.35, 0.9), CHARCOAL, SMOOTH, collide=False)
    part("PhoneHandset", (dx, top + 0.35, depth - 0.18), (1.0, 0.26, 0.34), CHARCOAL, SMOOTH, collide=False)
    part("PhoneDial", (dx, top + 0.35, depth + 0.2), (0.06, 0.5, 0.5), BRASS, METAL,
         collide=False, shape=2, upright_cylinder=True)
    # Inside the phone, not beside it. The presenter outlines the Model the
    # point sits in, so a marker standing on its own would highlight nothing and
    # a call would ring from an empty patch of table.
    delivery_point("PhonePoint", (dx, top, depth), "PhoneCall", size=(1.0, 0.9, 0.9))


@piece("Doorstep")
def doorstep():
    """Where a caller arrives and where they stop. Nothing visible: the doorstep
    is the front door, which the house already has.

    Free-standing, so the origin is the marker itself. Its facing is the whole
    piece — a visitor spawns here and walks NPC_APPROACH_STUDS straight along
    it before waiting, so `side` in the placement below is what decides where
    they end up standing, and read_house.py measures that spot."""
    delivery_point("VisitorPoint", (0, 0.05, 0), "NPCApproach", size=(1.8, _MARKER_HEIGHT, 1.8))


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
with free(A, -11.0, -26.0):
    plant()
ceiling_light(A, -4.0, -21.5)
ceiling_light(A, 22.0, -21.5)

# Hall and dining. The table sits west of the staircase; the west wall can only
# take something short between the door and the window.
#
# Set two studs south of centre so the line straight in from the front door at
# z -4.9 stays open. Centred, the near row of chairs backed onto that line and
# left 1.7 studs to squeeze through — walkable, but the only way in from the
# street was sideways past a chair, and a visitor walking in from the doorstep
# stopped inside one.
with free(B, 13.0, 1.0):
    dining_table()
for dx in (-3.0, 0.0, 3.0):
    with free(B, 13.0 + dx, -2.2):
        chair(back=(0, -1))
    with free(B, 13.0 + dx, 4.2):
        chair(back=(0, 1))
with against(B, "west", -8.2):
    console_table(3.5)
    # On the table rather than beside it, and authored in the table's own frame:
    # -1.15 puts it at the door end of the top, clear of the bowl in the middle.
    telephone(dx=-1.15, top=2.88)

# The front hall is also where the world reaches you: post on the mat, the
# phone on the hall table, callers on the doorstep. All three cluster around the
# door at z -4.9 because that is where all three actually arrive.
with against(B, "west", -4.9):
    doormat()
# On the mat, facing east into the hall, so a visitor walks in rather than into
# the wall. Straight down the middle of the line the dining set was moved to
# keep open, which is the same line the player walks in on.
with free(B, 5.2, -4.9, side="east"):
    doorstep()

ceiling_light(B, 13.0, 1.0)
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
with free(U1, 16.5, 5.0):
    plant()
ceiling_light(U1, 13.0, -1.0)

# Landing: a short gallery, so it gets a runner and little else.
with free(U2, -2.0, -1.0):
    flat_rug(6.0, 12.0, ROSE)
with against(U2, "west", -1.0):
    console_table(5.0)
with against(U2, "east", 3.5):
    bookshelf(4.0)
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

print(rbxmx.write(OUT, "Furniture"))
