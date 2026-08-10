#!/usr/bin/env python3
"""Generates assets/City.rbxmx: the city that grew east of the town.

Run from tools/:  python3 gen_city.py

The town (Town.rbxmx) built a road corridor and a handful of buildings on the
west side of the player's street. This file builds what lies east and north of
it: a proper street grid of six avenues and six cross streets, ~150 houses
fronting the avenues, a commercial high street of 25 storefronts, ten civic
buildings in a north civic quarter, and a sports park with a soccer pitch, a
basketball court, a tennis court, a playground and a running track. Everything
sits east of x 8 and north of z 80, clear of the town and of the imported house
model, on ground the baseplate was enlarged to carry.

**Why a separate file.** gen_town.py owns the town's plan and its numbers are
checked against world_plan.py. The city is younger and bigger and is allowed to
carry its own plan, for the same reason the town carries its own: if a building
ends up somewhere surprising, the surprise lives here, where the person who
added it can be asked.

**The swap contract.** The same as the town, because the city is the town's
successor and it must not take a worse deal:

  * Every building is one Model (a `group`), so imported art is a replacement,
    not a rewrite. Routes, jobs and place points are read off tags, never off
    geometry.
  * Every place point is an `AgesPlacePoint` part, so the graph grows by
    tagging.
  * Every interactive sports piece carries `AgesSportFacility` with a
    `FacilityKind` attribute, the seam a future real model must keep.
  * Streets continue the exact bands build_street.py and gen_town.py laid down,
    because a player who walks out of town onto a sidewalk that has silently
    changed colour has found a bug, not a border.
"""

import rbxmx
from rbxmx import (
    ASPHALT, BRICK, CONCRETE, FABRIC, GLASS, GRASS, LEAFY_GRASS, MARBLE,
    METAL, NEON, PEBBLE, PLASTIC, PLANKS, SLATE, SMOOTH, WOOD,
)
from rbxmx import at, box, group, part, point_light, sign

from world_plan import (
    CEIL_1, DOORWAY, FLOOR_1, GROUND, KERB, PAVING,
    PLACE_ID_ATTRIBUTE, PLACE_LABEL_ATTRIBUTE, PLACE_TAG, SLAB, STOREY, WALL,
)

from house_plan import _ASSETS

CITY = _ASSETS / "City.rbxmx"

rbxmx.begin("RBXCITY")

# ---------------------------------------------------------------------------
# Heights, matching build_street.py and gen_town.py exactly
# ---------------------------------------------------------------------------

KERB_WIDTH = 0.8
SLAB_SINK = 0.6
GROUND_BOTTOM = -1.0
DOOR_HEIGHT = 9.0
# The city's own grass sits two hundredths under the town's ground so that
# roads laid on top (top GROUND) never share a plane with the grass underneath
# them and z-fight. The seam where the city meets the town is a hairline.
CITY_GRASS_TOP = GROUND - 0.02

# ---------------------------------------------------------------------------
# The plan
# ---------------------------------------------------------------------------

# City region: east of the town's grass (x 8), north of the imported house
# model (z 80), inside the enlarged 2048 baseplate (x/z +/- 1024).
CITY_X0, CITY_X1 = 8.0, 1024.0
CITY_Z0, CITY_Z1 = 80.0, 1024.0

# The connector: a north-south road as wide as the town's (23 studs) that
# carries the player out of town and up into the city. It has no crossings --
# the high street begins at its east sidewalk -- so it is one continuous strip.
CONN_X0, CONN_X1 = 19.0, 42.0
CONN_Z0, CONN_Z1 = 80.0, 1000.0
CONN_WALK = 6.0
CONN_MID = (CONN_X0 + CONN_X1) / 2

# Six avenues, north-south, 14 studs wide, sidewalks 6 wide. They run from the
# city's south edge up to the last cross street.
AVE = [79.0, 219.0, 359.0, 499.0, 639.0, 779.0]
AVE_W = 14.0
AVE_WALK = 6.0
AVE_Z0, AVE_Z1 = 80.0, 950.0

# Six cross streets, east-west, 14 studs wide, sidewalks 4 wide. They span the
# grid from the first avenue to the last.
CS = [200.0, 350.0, 500.0, 650.0, 800.0, 950.0]
CS_W = 14.0
CS_WALK = 4.0
CS_X0, CS_X1 = 79.0, 793.0

# The high street: a 20-stud east-west road from the connector's east sidewalk
# to the last avenue, lined with storefronts on both sides.
HIGH_Z0, HIGH_Z1 = 120.0, 140.0
HIGH_X0, HIGH_X1 = 48.0, 793.0
HIGH_WALK = 4.0

# Gaps used to carve roads and sidewalks out of each other at crossings. A road
# is carved at the roads it crosses; a north-south sidewalk yields its corner to
# the east-west sidewalk, so one and only one box owns every square.
CS_ROAD = [(c, c + CS_W) for c in CS]
CS_FULL = [(c - CS_WALK, c + CS_W + CS_WALK) for c in CS]
AVE_ROAD = [(a, a + AVE_W) for a in AVE]
AVE_FULL = [(a - AVE_WALK, a + AVE_W + AVE_WALK) for a in AVE]
HIGH_ROAD = [(HIGH_Z0, HIGH_Z1)]

# Houses. Three per row per block, fronting the avenue that row faces. House
# depth 44 (x), frontage 34 (z), 4-stud gaps between neighbours.
HOUSE_DEPTH = 44.0
HOUSE_FRONT = 34.0

# Sports park, east of the last avenue. Open grass with five facilities.
PARK_X0, PARK_X1 = 808.0, 1024.0
PARK_Z0, PARK_Z1 = 100.0, 1024.0

# The tag the game reads to find an interactive sports piece. Mirrors
# Config.World.SportTag / SportKindAttribute.
SPORT_TAG = "AgesSportFacility"
SPORT_KIND = "FacilityKind"

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------

LAWN = (106, 142, 84)
TARMAC = (58, 58, 61)
ROAD_PAINT = (226, 222, 208)
PAVING_GREY = (176, 174, 168)
KERB_GREY = (152, 150, 145)
PATH_STONE = (188, 180, 166)

BRICK_WARM = (156, 108, 88)
BRICK_PALE = (188, 172, 152)
TRIM_WHITE = (232, 230, 224)
ROOF_GREY = (88, 88, 92)
GLAZING = (142, 176, 190)
STEEL = (128, 130, 134)
AWNING_RED = (176, 74, 56)
AWNING_CREAM = (240, 228, 198)

FLOOR_INDOOR = (198, 192, 180)
PARTITION_PALE = (216, 212, 204)

BARK = (94, 74, 58)
LEAF = (78, 118, 62)

FITTING = (238, 236, 228)
LAMP_LIGHT = (255, 236, 196)
INDOOR_LIGHT = (255, 248, 232)

DESK_TOP = (196, 166, 126)
DESK_LEG = (110, 112, 116)
SEAT = (72, 96, 132)
SHELF = (146, 148, 152)
STOCK = (176, 142, 96)

# Houses take a handful of wall tones so a full avenue reads as houses rather
# than as one long wall.
HOUSE_WALL = (166, 118, 92)
HOUSE_WALL_2 = (170, 140, 120)
HOUSE_WALL_3 = (200, 190, 170)
HOUSE_WALL_4 = (150, 150, 160)

# Storefronts cycle a wider palette, one tone per business.
STORE_WALLS = [
    (214, 218, 224),   # clean white
    (204, 176, 132),   # warm cream
    (170, 176, 184),   # pale concrete
    (188, 172, 152),   # pale brick
    (196, 150, 120),   # terracotta
    (176, 196, 200),   # pale teal
    (200, 184, 140),   # sand
    (180, 168, 180),   # mauve grey
    (120, 140, 160),   # slate blue
    (156, 108, 88),    # warm brick
]

# Civic buildings, one tone each so the quarter reads as a row of institutions.
CIVIC_WALLS = [
    (150, 156, 168), (128, 140, 152), (206, 200, 186), (160, 172, 184),
    (214, 210, 198), (96, 104, 122), (196, 88, 72), (140, 148, 156),
    (120, 112, 96), (206, 186, 160),
]

PITCH_GREEN = (96, 160, 88)
COURT_BLUE = (96, 120, 176)
COURT_GREEN = (120, 170, 120)
TRACK_RED = (176, 96, 84)
SAND = (212, 196, 156)

# ---------------------------------------------------------------------------
# Small builders, shared with gen_town.py's language
# ---------------------------------------------------------------------------


def wall(name, bounds, color, material=BRICK, doors=(), head=DOOR_HEIGHT,
         along="z", collide=True):
    """One wall as a set of boxes, minus its doorways, plus a lintel over each."""
    x0, x1, z0, z1, y0, y1 = bounds
    lo, hi = (z0, z1) if along == "z" else (x0, x1)

    spans = []
    cursor = lo
    for d0, d1 in sorted(doors):
        if d0 > cursor:
            spans.append((cursor, d0))
        cursor = max(cursor, d1)
    if cursor < hi:
        spans.append((cursor, hi))

    for i, (a, b) in enumerate(spans):
        piece_bounds = (x0, x1, a, b, y0, y1) if along == "z" else (a, b, z0, z1, y0, y1)
        box(f"{name}{i + 1}", piece_bounds, color, material, collide=collide)

    lintel_y0 = y0 + head
    if lintel_y0 < y1:
        for i, (d0, d1) in enumerate(sorted(doors)):
            piece_bounds = (
                (x0, x1, d0, d1, lintel_y0, y1) if along == "z"
                else (d0, d1, z0, z1, lintel_y0, y1)
            )
            box(f"{name}Head{i + 1}", piece_bounds, color, material, collide=collide)


def glazing(name, bounds, along="z", panes=1):
    """A run of window as non-colliding panes -- a wall's own opening filled."""
    x0, x1, z0, z1, y0, y1 = bounds
    lo, hi = (z0, z1) if along == "z" else (x0, x1)
    step = (hi - lo) / panes
    for i in range(panes):
        a, b = lo + i * step + 0.3, lo + (i + 1) * step - 0.3
        piece_bounds = (x0, x1, a, b, y0, y1) if along == "z" else (a, b, z0, z1, y0, y1)
        box(f"{name}{i + 1}", piece_bounds, GLAZING, GLASS,
            transparency=0.55, collide=False)


def ceiling_light(x, z, ceiling, label="CeilingLight"):
    with group(label):
        with at(x, z, floor=ceiling):
            part("Panel", (0, -0.5, 0), (5.0, 0.4, 1.6), FITTING, NEON,
                 collide=False, children=point_light(INDOOR_LIGHT, 1.1, 22.0))


def desk(x, z, floor, side="north", width=5.0, depth=2.6, label="Desk"):
    with group(label):
        with at(x, z, side=side, floor=floor):
            part("Top", (0, 2.4, depth / 2), (width, 0.3, depth), DESK_TOP, WOOD)
            for dx in (-width / 2 + 0.4, width / 2 - 0.4):
                part("Leg", (dx, 0, depth / 2), (0.3, 2.4, depth - 0.6), DESK_LEG, METAL)


def chair(x, z, floor, side="north", label="Chair"):
    with group(label):
        with at(x, z, side=side, floor=floor):
            part("Seat", (0, 1.6, 0), (1.8, 0.3, 1.8), SEAT, FABRIC)
            part("Back", (0, 1.9, -0.75), (1.8, 2.0, 0.3), SEAT, FABRIC)
            part("Stem", (0, 0, 0), (0.4, 1.6, 0.4), DESK_LEG, METAL)


def tree(x, z, floor, height=15.0, spread=10.0, label="Tree"):
    with group(label):
        with at(x, z, floor=floor):
            part("Trunk", (0, 0, 0), (1.6, height * 0.62, 1.6), BARK, WOOD)
            part("Canopy", (0, height * 0.5, 0), (spread, spread * 0.72, spread),
                 LEAF, LEAFY_GRASS, collide=False)
            part("CanopyTop", (0, height * 0.5 + spread * 0.5, 0),
                 (spread * 0.66, spread * 0.5, spread * 0.66),
                 LEAF, LEAFY_GRASS, collide=False)


def street_lamp(x, z, toward, floor=PAVING, label="StreetLamp"):
    """A pole on the sidewalk with its arm reaching `toward` (+1, -1, 0)."""
    with group(label):
        with at(x, z, floor=floor):
            part("Base", (0, 0, 0), (1.4, 0.5, 1.4), STEEL, METAL)
            part("Pole", (0, 0.5, 0), (0.5, 12.0, 0.5), STEEL, METAL)
            if toward == 0:
                part("Arm", (0, 12.0, 1.4), (0.4, 0.4, 3.2), STEEL, METAL)
                part("Head", (0, 11.4, 2.9), (1.0, 0.7, 1.6),
                     FITTING, NEON, children=point_light(LAMP_LIGHT, 1.6, 26.0))
            else:
                part("Arm", (toward * 1.4, 12.0, 0), (3.2, 0.4, 0.4), STEEL, METAL)
                part("Head", (toward * 2.9, 11.4, 0), (1.6, 0.7, 1.0),
                     FITTING, NEON, children=point_light(LAMP_LIGHT, 1.6, 26.0))


PLACE_POINTS = []


def place_point(pid, x, z, floor, label):
    """Stash a tagged coordinate; the single PlacePoints group emits them all
    at the end, the same way gen_town.py does."""
    PLACE_POINTS.append((pid, x, z, floor, label))


def carve(bounds, gaps):
    """The pieces of bounds left after every gap has been cut out."""
    lo, hi = bounds
    segs = []
    cursor = lo
    for g0, g1 in sorted(gaps):
        if g0 > cursor:
            segs.append((cursor, g0))
        cursor = max(cursor, g1)
    if cursor < hi:
        segs.append((cursor, hi))
    return segs


# ---------------------------------------------------------------------------
# Streets
# ---------------------------------------------------------------------------


def road_ns(x0, x1, z0, z1, walk, prefix):
    """One north-south road strip: road slab, kerb and paving on both sides."""
    box(f"{prefix}Road", (x0, x1, z0, z1, GROUND_BOTTOM, GROUND), TARMAC, ASPHALT)
    box(f"{prefix}KerbW", (x0 - walk, x0, z0, z1, GROUND - SLAB_SINK, PAVING),
        KERB_GREY, CONCRETE)
    box(f"{prefix}PavW", (x0 - walk, x0 - KERB_WIDTH, z0, z1, GROUND - SLAB_SINK, PAVING),
        PAVING_GREY, PEBBLE)
    box(f"{prefix}KerbE", (x1, x1 + KERB_WIDTH, z0, z1, GROUND - SLAB_SINK, PAVING),
        KERB_GREY, CONCRETE)
    box(f"{prefix}PavE", (x1 + KERB_WIDTH, x1 + walk, z0, z1, GROUND - SLAB_SINK, PAVING),
        PAVING_GREY, PEBBLE)


def walks_ns(x0, x1, z0, z1, walk, prefix):
    """Sidewalk-only variant, for carving at a crossing the road is not."""
    box(f"{prefix}KerbW", (x0 - walk, x0, z0, z1, GROUND - SLAB_SINK, PAVING),
        KERB_GREY, CONCRETE)
    box(f"{prefix}PavW", (x0 - walk, x0 - KERB_WIDTH, z0, z1, GROUND - SLAB_SINK, PAVING),
        PAVING_GREY, PEBBLE)
    box(f"{prefix}KerbE", (x1, x1 + KERB_WIDTH, z0, z1, GROUND - SLAB_SINK, PAVING),
        KERB_GREY, CONCRETE)
    box(f"{prefix}PavE", (x1 + KERB_WIDTH, x1 + walk, z0, z1, GROUND - SLAB_SINK, PAVING),
        PAVING_GREY, PEBBLE)


def road_ew(z0, z1, x0, x1, walk, prefix):
    """One east-west road strip."""
    box(f"{prefix}Road", (x0, x1, z0, z1, GROUND_BOTTOM, GROUND), TARMAC, ASPHALT)
    box(f"{prefix}KerbS", (x0, x1, z0 - walk, z0, GROUND - SLAB_SINK, PAVING),
        KERB_GREY, CONCRETE)
    box(f"{prefix}PavS", (x0, x1, z0 - walk, z0 - KERB_WIDTH, GROUND - SLAB_SINK, PAVING),
        PAVING_GREY, PEBBLE)
    box(f"{prefix}KerbN", (x0, x1, z1, z1 + KERB_WIDTH, GROUND - SLAB_SINK, PAVING),
        KERB_GREY, CONCRETE)
    box(f"{prefix}PavN", (x0, x1, z1 + KERB_WIDTH, z1 + walk, GROUND - SLAB_SINK, PAVING),
        PAVING_GREY, PEBBLE)


def walks_ew(z0, z1, x0, x1, walk, prefix):
    """Sidewalk-only east-west variant."""
    box(f"{prefix}KerbS", (x0, x1, z0 - walk, z0, GROUND - SLAB_SINK, PAVING),
        KERB_GREY, CONCRETE)
    box(f"{prefix}PavS", (x0, x1, z0 - walk, z0 - KERB_WIDTH, GROUND - SLAB_SINK, PAVING),
        PAVING_GREY, PEBBLE)
    box(f"{prefix}KerbN", (x0, x1, z1, z1 + KERB_WIDTH, GROUND - SLAB_SINK, PAVING),
        KERB_GREY, CONCRETE)
    box(f"{prefix}PavN", (x0, x1, z1 + KERB_WIDTH, z1 + walk, GROUND - SLAB_SINK, PAVING),
        PAVING_GREY, PEBBLE)


PAINT_TOP = GROUND + 0.02
PAINT_BOTTOM = PAINT_TOP - 0.12
DASH = 6.0
GAP = 6.0


def dashes_ns(x, z_lo, z_hi, gaps, prefix):
    """Centre dashes along a north-south road, carved at its crossings."""
    for za, zb in carve((z_lo, z_hi), gaps):
        z = za + DASH
        while z + DASH <= zb - DASH:
            box(f"{prefix}Dash{z:.0f}",
                (x - 0.3, x + 0.3, z, z + DASH, PAINT_BOTTOM, PAINT_TOP),
                ROAD_PAINT, SMOOTH)
            z += DASH + GAP


def dashes_ew(z, x_lo, x_hi, gaps, prefix):
    """Centre dashes along an east-west road."""
    for xa, xb in carve((x_lo, x_hi), gaps):
        x = xa + DASH
        while x + DASH <= xb - DASH:
            box(f"{prefix}Dash{x:.0f}",
                (x, x + DASH, z - 0.3, z + 0.3, PAINT_BOTTOM, PAINT_TOP),
                ROAD_PAINT, SMOOTH)
            x += DASH + GAP


with group("Ground"):
    box("CityGround", (CITY_X0, CITY_X1, CITY_Z0, CITY_Z1, GROUND_BOTTOM, CITY_GRASS_TOP),
        LAWN, GRASS)

with group("Streets"):
    # The connector, uncarved.
    road_ns(CONN_X0, CONN_X1, CONN_Z0, CONN_Z1, CONN_WALK, "Conn")

    # Avenues: road carved at cross streets and the high street, sidewalks also
    # carved at the cross streets' own sidewalks so they yield the corners.
    for k, a in enumerate(AVE):
        for za, zb in carve((AVE_Z0, AVE_Z1), CS_ROAD + HIGH_ROAD):
            road_ns(a, a + AVE_W, za, zb, AVE_WALK, f"Ave{k}")
        for za, zb in carve((AVE_Z0, AVE_Z1), CS_FULL + HIGH_ROAD):
            walks_ns(a, a + AVE_W, za, zb, AVE_WALK, f"Ave{k}W")

    # Cross streets: carved at the avenues.
    for j, c in enumerate(CS):
        for xa, xb in carve((CS_X0, CS_X1), AVE_ROAD):
            road_ew(c, c + CS_W, xa, xb, CS_WALK, f"C{j}")
        for xa, xb in carve((CS_X0, CS_X1), AVE_ROAD):
            walks_ew(c, c + CS_W, xa, xb, CS_WALK, f"C{j}W")

    # The high street: road carved at the avenues, walks carved at the avenues'
    # full width so the avenues' own sidewalks own the crossings.
    for xa, xb in carve((HIGH_X0, HIGH_X1), AVE_ROAD):
        road_ew(HIGH_Z0, HIGH_Z1, xa, xb, HIGH_WALK, "High")
    for xa, xb in carve((HIGH_X0, HIGH_X1), AVE_FULL):
        walks_ew(HIGH_Z0, HIGH_Z1, xa, xb, HIGH_WALK, "HighW")

    # Intersection tiles: the square both roads carved away, so every junction
    # is one flat piece of asphalt rather than a grass hole.
    for a in AVE:
        for c in CS:
            box(f"X{a:.0f}_{c:.0f}", (a, a + AVE_W, c, c + CS_W, GROUND_BOTTOM, GROUND),
                TARMAC, ASPHALT)
        box(f"XHigh{a:.0f}", (a, a + AVE_W, HIGH_Z0, HIGH_Z1, GROUND_BOTTOM, GROUND),
            TARMAC, ASPHALT)

    # Centre lines.
    dashes_ns(CONN_MID, CONN_Z0, CONN_Z1, [], "Conn")
    for k, a in enumerate(AVE):
        dashes_ns(a + AVE_W / 2, AVE_Z0, AVE_Z1, CS_ROAD + HIGH_ROAD, f"Ave{k}")
    for j, c in enumerate(CS):
        dashes_ew(c + CS_W / 2, CS_X0, CS_X1, AVE_ROAD, f"C{j}")
    dashes_ew(HIGH_Z0 + (HIGH_Z1 - HIGH_Z0) / 2, HIGH_X0, HIGH_X1, AVE_ROAD, "High")


# ---------------------------------------------------------------------------
# Houses
# ---------------------------------------------------------------------------


def suburb_house(x0, x1, z0, z1, door_z, number, front):
    """A small house fronting an avenue. `front` is "west" (door in the west
    wall) or "east" (door in the east wall); x0..x1 is its depth, z0..z1 its
    frontage along the avenue."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    d0, d1 = door_z - DOORWAY / 2, door_z + DOORWAY / 2
    tones = (HOUSE_WALL, HOUSE_WALL_2, HOUSE_WALL_3, HOUSE_WALL_4)
    wall_color = tones[(number - 1) % len(tones)]

    with group(f"Suburb{number}"):
        with group("HouseStructure"):
            box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1), FLOOR_INDOOR, MARBLE)
            box("Roof", (x0, x1, z0, z1, CEIL_1, CEIL_1 + SLAB), ROOF_GREY, SLATE)
            if front == "west":
                wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, CEIL_1), wall_color,
                     along="z", doors=((d0, d1),))
                wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, CEIL_1), wall_color, along="z")
                for i, (a, b) in enumerate(((iz0 + 3.0, iz0 + 7.0), (iz1 - 7.0, iz1 - 3.0))):
                    glazing(f"Window{i + 1}",
                            (ix1 + 0.4, x1 - 0.4, a, b, FLOOR_1 + 3.0, FLOOR_1 + 7.0),
                            along="z", panes=2)
                box("Numberplate", (x0 - 0.6, x0 - 0.1, door_z - 1.5, door_z + 1.5,
                                    FLOOR_1 + 8.0, FLOOR_1 + 9.5),
                    TRIM_WHITE, SMOOTH, children=sign(str(number), "left",
                                                      color=(60, 66, 84), size=48))
            else:
                wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, CEIL_1), wall_color,
                     along="z", doors=((d0, d1),))
                wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, CEIL_1), wall_color, along="z")
                for i, (a, b) in enumerate(((iz0 + 3.0, iz0 + 7.0), (iz1 - 7.0, iz1 - 3.0))):
                    glazing(f"Window{i + 1}",
                            (x0 + 0.4, ix0 - 0.4, a, b, FLOOR_1 + 3.0, FLOOR_1 + 7.0),
                            along="z", panes=2)
                box("Numberplate", (x1 + 0.1, x1 + 0.6, door_z - 1.5, door_z + 1.5,
                                    FLOOR_1 + 8.0, FLOOR_1 + 9.5),
                    TRIM_WHITE, SMOOTH, children=sign(str(number), "right",
                                                      color=(60, 66, 84), size=48))
            wall("WallSouth", (x0, x1, z0, iz0, FLOOR_1, CEIL_1), wall_color, along="x")
            wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, CEIL_1), wall_color, along="x")

        with group("HouseFittings"):
            if front == "west":
                wall("Partition", (ix0 + 6.0, ix0 + 7.0, iz0 + 4.0, iz1 - 4.0,
                                   FLOOR_1, CEIL_1), PARTITION_PALE, PLASTIC,
                     along="z", doors=((door_z - 3.0, door_z + 3.0),))
                box("Sofa", (ix0 + 11.0, ix0 + 15.0, iz1 - 9.0, iz1 - 5.0,
                             FLOOR_1 + 1.2, FLOOR_1 + 2.0), (140, 96, 80), FABRIC)
                desk(ix0 + 18.0, door_z + 2.0, FLOOR_1, side="west", width=4.0,
                     depth=2.2, label="Table")
                box("Bed", (ix0 + 8.0, ix0 + 15.0, iz0 + 4.0, iz0 + 10.0,
                            FLOOR_1 + 0.8, FLOOR_1 + 1.6), (214, 218, 224), FABRIC)
                ceiling_light(ix0 + 18.0, door_z, CEIL_1)
            else:
                wall("Partition", (ix1 - 7.0, ix1 - 6.0, iz0 + 4.0, iz1 - 4.0,
                                   FLOOR_1, CEIL_1), PARTITION_PALE, PLASTIC,
                     along="z", doors=((door_z - 3.0, door_z + 3.0),))
                box("Sofa", (ix1 - 15.0, ix1 - 11.0, iz1 - 9.0, iz1 - 5.0,
                             FLOOR_1 + 1.2, FLOOR_1 + 2.0), (140, 96, 80), FABRIC)
                desk(ix1 - 18.0, door_z + 2.0, FLOOR_1, side="east", width=4.0,
                     depth=2.2, label="Table")
                box("Bed", (ix1 - 15.0, ix1 - 8.0, iz0 + 4.0, iz0 + 10.0,
                            FLOOR_1 + 0.8, FLOOR_1 + 1.6), (214, 218, 224), FABRIC)
                ceiling_light(ix1 - 18.0, door_z, CEIL_1)


HOUSE_SLOTS = []  # (x0, x1, z0, z1, door_z, front, number)


def build_house_slots():
    n = 1
    for band in range(5):
        a0, a1 = AVE[band], AVE[band + 1]
        wx0, wx1 = a0 + AVE_WALK + WALL + 0.5, a0 + AVE_WALK + WALL + 0.5 + HOUSE_DEPTH
        ex1, ex0 = a1 - AVE_WALK - WALL - 0.5, a1 - AVE_WALK - WALL - 0.5 - HOUSE_DEPTH
        for sband in range(5):
            c0, c1 = CS[sband], CS[sband + 1]
            zlo, zhi = c0 + CS_W + CS_WALK + 4.0, c1 - CS_WALK - 4.0
            zc = (zlo + zhi) / 2
            for dz in (-38.0, 0.0, 38.0):
                z0, z1 = zc + dz - HOUSE_FRONT / 2, zc + dz + HOUSE_FRONT / 2
                HOUSE_SLOTS.append((wx0, wx1, z0, z1, zc + dz, "west", n))
                n += 1
                HOUSE_SLOTS.append((ex0, ex1, z0, z1, zc + dz, "east", n))
                n += 1


build_house_slots()

for x0, x1, z0, z1, door_z, front, number in HOUSE_SLOTS:
    suburb_house(x0, x1, z0, z1, door_z, number, front)

# ---------------------------------------------------------------------------
# Storefronts and civic buildings
# ---------------------------------------------------------------------------


def storefront(name, x0, x1, z0, z1, door_pos, wall_color, front="north",
               front_type="shop", wall_mat=BRICK):
    """A single-storey storefront with the door + shopfront on the `front` wall
    (north or south). `door_pos` is the x coordinate of the door."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    d0, d1 = door_pos - DOORWAY / 2, door_pos + DOORWAY / 2

    with group(f"{name}Structure"):
        box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1), FLOOR_INDOOR, MARBLE)
        box("Roof", (x0, x1, z0, z1, CEIL_1, CEIL_1 + SLAB), ROOF_GREY, SLATE)
        wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, CEIL_1), wall_color, wall_mat, along="z")
        wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, CEIL_1), wall_color, wall_mat, along="z")

        if front == "north":
            wall("WallSouth", (x0, x1, z0, iz0, FLOOR_1, CEIL_1), wall_color, wall_mat, along="x")
            if front_type == "garage":
                gd0, gd1 = door_pos - 7.0, door_pos + 7.0
                wall("WallFront", (x0, x1, iz1, z1, FLOOR_1, CEIL_1), wall_color, wall_mat,
                     along="x", doors=((gd0, gd1),), head=CEIL_1 - FLOOR_1)
                box("RollupDoor", (gd0, gd1, iz1 + 0.4, z1 - 0.4, FLOOR_1 + 4.0, FLOOR_1 + 14.0),
                    STEEL, METAL, collide=False)
                for i in range(7):
                    xx = gd0 + (gd1 - gd0) * (i + 0.5) / 7
                    box(f"RollupSlat{i}", (xx - 0.12, xx + 0.12, iz1 + 0.6, z1 - 0.6,
                                           FLOOR_1 + 4.0, FLOOR_1 + 14.0),
                        (96, 98, 102), METAL, collide=False)
                box("Nameplate", (door_pos - 6.0, door_pos + 6.0, z1 - 2.5, z1,
                                  CEIL_1 + SLAB, 24.0), wall_color, BRICK,
                    children=sign(name, "front", color=(250, 246, 234), size=72))
            else:
                wall("WallFront", (x0, x1, iz1, z1, FLOOR_1, CEIL_1), wall_color, wall_mat,
                     along="x", doors=((d0, d1),))
                for i, (a, b) in enumerate(((ix0 + 3.0, d0 - 1.0), (d1 + 1.0, ix1 - 3.0))):
                    if b - a > 4.0:
                        glazing(f"Shopfront{i + 1}",
                                (a, b, iz1 + 0.4, z1 - 0.4, FLOOR_1 + 1.5, FLOOR_1 + 10.5),
                                along="x", panes=4)
                box("Nameplate", (door_pos - 9.0, door_pos + 9.0, z1 - 2.5, z1,
                                  CEIL_1 + SLAB, 24.0), wall_color, BRICK,
                    children=sign(name, "front", color=(250, 246, 234), size=72))
                if front_type == "awning":
                    box("Awning", (ix0 + 2.0, ix1 - 2.0, z1 - 0.4, z1 + 3.2,
                                   FLOOR_1 + 8.0, FLOOR_1 + 10.5), AWNING_RED, FABRIC, collide=False)
                    box("AwningTrim", (ix0 + 2.0, ix1 - 2.0, z1 + 3.2, z1 + 3.4,
                                      FLOOR_1 + 8.0, FLOOR_1 + 10.5), AWNING_CREAM, FABRIC, collide=False)
                    box("AwningValance", (ix0 + 2.0, ix1 - 2.0, z1 + 2.9, z1 + 3.2,
                                          FLOOR_1 + 8.0, FLOOR_1 + 9.2), AWNING_RED, FABRIC, collide=False)
        else:  # south
            wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, CEIL_1), wall_color, wall_mat, along="x")
            if front_type == "garage":
                gd0, gd1 = door_pos - 7.0, door_pos + 7.0
                wall("WallFront", (x0, x1, z0, iz0, FLOOR_1, CEIL_1), wall_color, wall_mat,
                     along="x", doors=((gd0, gd1),), head=CEIL_1 - FLOOR_1)
                box("RollupDoor", (gd0, gd1, z0 + 0.4, iz0 - 0.4, FLOOR_1 + 4.0, FLOOR_1 + 14.0),
                    STEEL, METAL, collide=False)
                for i in range(7):
                    xx = gd0 + (gd1 - gd0) * (i + 0.5) / 7
                    box(f"RollupSlat{i}", (xx - 0.12, xx + 0.12, z0 + 0.6, iz0 - 0.6,
                                           FLOOR_1 + 4.0, FLOOR_1 + 14.0),
                        (96, 98, 102), METAL, collide=False)
                box("Nameplate", (door_pos - 6.0, door_pos + 6.0, z0, z0 + 2.5,
                                  CEIL_1 + SLAB, 24.0), wall_color, BRICK,
                    children=sign(name, "back", color=(250, 246, 234), size=72))
            else:
                wall("WallFront", (x0, x1, z0, iz0, FLOOR_1, CEIL_1), wall_color, wall_mat,
                     along="x", doors=((d0, d1),))
                for i, (a, b) in enumerate(((ix0 + 3.0, d0 - 1.0), (d1 + 1.0, ix1 - 3.0))):
                    if b - a > 4.0:
                        glazing(f"Shopfront{i + 1}",
                                (a, b, z0 + 0.4, iz0 - 0.4, FLOOR_1 + 1.5, FLOOR_1 + 10.5),
                                along="x", panes=4)
                box("Nameplate", (door_pos - 9.0, door_pos + 9.0, z0, z0 + 2.5,
                                  CEIL_1 + SLAB, 24.0), wall_color, BRICK,
                    children=sign(name, "back", color=(250, 246, 234), size=72))
                if front_type == "awning":
                    box("Awning", (ix0 + 2.0, ix1 - 2.0, z0 - 3.2, z0 - 0.4,
                                   FLOOR_1 + 8.0, FLOOR_1 + 10.5), AWNING_RED, FABRIC, collide=False)
                    box("AwningTrim", (ix0 + 2.0, ix1 - 2.0, z0 - 3.4, z0 - 3.2,
                                      FLOOR_1 + 8.0, FLOOR_1 + 10.5), AWNING_CREAM, FABRIC, collide=False)
                    box("AwningValance", (ix0 + 2.0, ix1 - 2.0, z0 - 3.2, z0 - 2.9,
                                          FLOOR_1 + 8.0, FLOOR_1 + 9.2), AWNING_RED, FABRIC, collide=False)


def store_fittings(name, x0, x1, z0, z1, front, kind):
    """A few boxes that make a storefront read as its business."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    with group(f"{name}Fittings"):
        if kind in ("cafe", "restaurant", "pizzeria"):
            if front == "north":
                box("Counter", (cx - 5.0, cx + 5.0, z1 - 3.2, z1 - 0.8, FLOOR_1, FLOOR_1 + 3.0),
                    DESK_TOP, WOOD)
            else:
                box("Counter", (cx - 5.0, cx + 5.0, z0 + 0.8, z0 + 3.2, FLOOR_1, FLOOR_1 + 3.0),
                    DESK_TOP, WOOD)
            for dx in (-6.0, 6.0):
                desk(cx + dx, cz, FLOOR_1, side="east", width=4.0, depth=2.4, label="Table")
                for dz in (-2.4, 2.4):
                    chair(cx + dx, cz + dz, FLOOR_1, side="west")
        elif kind in ("office", "bank", "post_office", "dental", "optometrist"):
            for dx in (-5.0, 5.0):
                desk(cx + dx, cz - 2.0, FLOOR_1, side="north", width=4.0, depth=2.6,
                     label="Desk")
                chair(cx + dx, cz, FLOOR_1, side="south")
        elif kind == "garage":
            box("CarBody", (cx - 4.0, cx + 4.0, cz - 2.0, cz + 2.0, FLOOR_1 + 2.4, FLOOR_1 + 4.6),
                (60, 64, 120), SMOOTH)
            box("Workbench", (x0 + 2.0, x0 + 7.0, cz - 3.0, cz + 1.0,
                              FLOOR_1 + 2.4, FLOOR_1 + 2.8), DESK_TOP, WOOD)
        elif kind == "laundromat":
            for i in range(4):
                x = ix0 + 2.0 + i * 5.0
                box(f"Washer{i}", (x, x + 2.4, cz - 2.0, cz + 2.0, FLOOR_1, FLOOR_1 + 3.6),
                    (216, 218, 222), METAL)
        else:  # shop
            box("Counter", (cx - 5.0, cx + 5.0, cz - 2.0, cz + 0.6, FLOOR_1, FLOOR_1 + 3.0),
                DESK_TOP, WOOD)
            box("Gondola", (ix0 + 2.0, ix0 + 5.0, iz0 + 4.0, iz1 - 4.0, FLOOR_1, FLOOR_1 + 7.5),
                SHELF, METAL)
            box("Stock", (ix0 + 2.2, ix0 + 4.8, iz0 + 4.4, iz1 - 4.4,
                          FLOOR_1 + 1.8, FLOOR_1 + 3.4), STOCK, PLANKS, collide=False)
        ceiling_light(cx, cz, CEIL_1)


# (place id, business name, x0, x1, front, front_type)
# North side of the high street: z 80..116, door in the south wall facing the road.
HIGH_NORTH = [
    ("cafe", "CAFE ASTER", 0, 0, "north", "awning"),
    ("restaurant", "TORRE RESTAURANT", 0, 0, "north", "awning"),
    ("pizzeria", "VESUVIO PIZZERIA", 0, 0, "north", "awning"),
    ("supermarket", "MIDWAY MARKET", 0, 0, "north", "shop"),
    ("pharmacy", "FIRST PHARMACY", 0, 0, "north", "shop"),
    ("florist", "STEM & BLOOM", 0, 0, "north", "shop"),
    ("bookstore", "PAGES & PRESS", 0, 0, "north", "shop"),
    ("electronics", "VOLT ELECTRONICS", 0, 0, "north", "shop"),
    ("hardware", "IRON & WOOD", 0, 0, "north", "shop"),
    ("toy_store", "PLAYPEN", 0, 0, "north", "shop"),
    ("clothing_store", "THREAD & CO", 0, 0, "north", "shop"),
    ("music_store", "FREQUENCY", 0, 0, "north", "shop"),
    ("laundromat", "CLEAN SPIN", 0, 0, "north", "shop"),
    ("barbershop", "THE CLIPPERS", 0, 0, "north", "shop"),
    ("salon", "LUMIERE SALON", 0, 0, "north", "shop"),
]

# South side of the high street: z 144..180, door in the north wall facing the road.
HIGH_SOUTH = [
    ("tattoo_parlor", "INKWELL TATTOO", 0, 0, "south", "shop"),
    ("pet_shop", "TREATS & TAILS", 0, 0, "south", "shop"),
    ("vet", "ANIMAL CLINIC", 0, 0, "south", "plain"),
    ("dental", "SMILEDENT", 0, 0, "south", "plain"),
    ("optometrist", "SIGHT & SOUND", 0, 0, "south", "plain"),
    ("auto_dealer", "AUTOPIA", 0, 0, "south", "garage"),
    ("gas_station", "TANK & GO", 0, 0, "south", "garage"),
    ("car_wash", "WASH & GLIDE", 0, 0, "south", "garage"),
    ("post_office", "ROYAL POST", 0, 0, "south", "plain"),
    ("bank", "UNION BANK", 0, 0, "south", "plain"),
]


def place_stores():
    store_w = 34.0
    for i, (pid, label, _, _, front, ftype) in enumerate(HIGH_NORTH):
        n = len(HIGH_NORTH)
        step = (HIGH_X1 - HIGH_X0 - store_w) / (n - 1)
        cx = HIGH_X0 + store_w / 2 + i * step
        x0, x1 = cx - store_w / 2, cx + store_w / 2
        z0, z1 = 80.0, 116.0
        wall_color = STORE_WALLS[i % len(STORE_WALLS)]
        with group(pid):
            storefront(label, x0, x1, z0, z1, cx, wall_color, front=front, front_type=ftype)
            store_fittings(pid, x0, x1, z0, z1, front, "cafe" if ftype == "awning" else ftype)
        place_point(pid, cx, 114.0, FLOOR_1, f"the {pid}, at the counter")

    for i, (pid, label, _, _, front, ftype) in enumerate(HIGH_SOUTH):
        n = len(HIGH_SOUTH)
        step = (HIGH_X1 - HIGH_X0 - store_w) / (n - 1)
        cx = HIGH_X0 + store_w / 2 + i * step
        x0, x1 = cx - store_w / 2, cx + store_w / 2
        z0, z1 = 144.0, 180.0
        wall_color = STORE_WALLS[(i + 7) % len(STORE_WALLS)]
        with group(pid):
            storefront(label, x0, x1, z0, z1, cx, wall_color, front=front, front_type=ftype)
            store_fittings(pid, x0, x1, z0, z1, front, ftype)
        place_point(pid, cx, 146.0, FLOOR_1, f"the {pid}, at the counter")


place_stores()

# The ten civic buildings, a row across the north end of the grid. z 968..1012,
# door in the south wall facing the last cross street.
# (place id, business name, x0, x1, kind, front_type)
CIVIC = [
    ("cinema", "ORION CINEMA", 99.0, 155.0, "cinema", "plain"),
    ("bowling", "SPARE LANES", 159.0, 215.0, "bowling", "plain"),
    ("arcade", "NEON ARCADE", 219.0, 275.0, "arcade", "plain"),
    ("hotel", "GRAND HOTEL", 279.0, 335.0, "hotel", "plain"),
    ("town_hall", "CITY HALL", 339.0, 395.0, "hall", "plain"),
    ("police_station", "CITY POLICE", 399.0, 455.0, "police", "plain"),
    ("fire_station", "CITY FIRE", 459.0, 515.0, "fire", "garage"),
    ("warehouse", "NORTH WAREHOUSE", 519.0, 575.0, "warehouse", "garage"),
    ("construction_site", "SIMMONS BUILD", 579.0, 635.0, "construction", "plain"),
    ("farm", "WINDMILL FARM", 639.0, 695.0, "farm", "shop"),
]


def civic_fittings(kind, x0, x1, z0, z1):
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    with group(f"{kind}Fittings"):
        if kind == "cinema":
            box("Screen", (cx - 10.0, cx + 10.0, z1 - 4.0, z1 - 1.0, FLOOR_1 + 5.0, FLOOR_1 + 13.0),
                (40, 44, 48), SMOOTH)
            for i in range(3):
                box(f"Row{i}", (cx - 12.0, cx + 12.0, z0 + 5.0 + i * 7.0,
                                z0 + 7.5 + i * 7.0, FLOOR_1 + 2.0, FLOOR_1 + 2.8),
                    (150, 70, 80), FABRIC)
        elif kind == "bowling":
            for i in range(3):
                bx = cx - 8.0 + i * 8.0
                box(f"Lane{i}", (bx, bx + 5.0, z0 + 3.0, z1 - 6.0, FLOOR_1, FLOOR_1 + 0.4),
                    (150, 130, 96), WOOD)
        elif kind == "arcade":
            for i in range(5):
                bx = ix0 + 2.0 + i * 8.0
                box(f"Machine{i}", (bx, bx + 3.4, cz - 2.0, cz + 2.0, FLOOR_1, FLOOR_1 + 6.0),
                    (30, 34, 40), SMOOTH)
                box(f"Glow{i}", (bx + 0.3, bx + 3.1, cz - 1.6, cz + 1.6, FLOOR_1 + 3.0, FLOOR_1 + 5.5),
                    (60, 200, 220), NEON, collide=False)
        elif kind == "hotel":
            desk(cx, cz - 4.0, FLOOR_1, side="north", width=10.0, depth=3.0, label="FrontDesk")
            chair(cx, cz - 1.0, FLOOR_1, side="south")
            box("Sofa", (ix0 + 4.0, ix0 + 10.0, iz0 + 4.0, iz0 + 8.0,
                         FLOOR_1 + 1.2, FLOOR_1 + 2.0), (140, 96, 80), FABRIC)
        elif kind in ("hall", "police"):
            desk(cx - 5.0, cz - 2.0, FLOOR_1, side="north", width=8.0, depth=3.0, label="Desk")
            chair(cx - 5.0, cz, FLOOR_1, side="south")
            desk(cx + 5.0, cz - 2.0, FLOOR_1, side="north", width=6.0, depth=3.0, label="Desk")
            chair(cx + 5.0, cz, FLOOR_1, side="south")
        elif kind == "fire":
            for dx in (-6.0, 4.0):
                box(f"Engine{dx}", (cx + dx - 3.0, cx + dx + 3.0, cz - 3.0, cz + 3.0,
                                    FLOOR_1 + 2.0, FLOOR_1 + 5.0), (196, 88, 72), SMOOTH)
        elif kind == "warehouse":
            for i in range(3):
                box(f"Shelf{i}", (x0 + 4.0, x0 + 7.0, z0 + 4.0 + i * 8.0, z0 + 6.4 + i * 8.0,
                                  FLOOR_1, FLOOR_1 + 8.0), SHELF, METAL)
        elif kind == "construction":
            for i in range(3):
                bx = x0 + 6.0 + i * 16.0
                box(f"Scaffold{i}", (bx, bx + 1.2, z0 + 2.0, z1 - 2.0, FLOOR_1, FLOOR_1 + 9.0),
                    (160, 132, 90), WOOD)
                box(f"Deck{i}", (bx - 0.2, bx + 1.4, z0 + 2.0, z1 - 2.0,
                                 FLOOR_1 + 4.5, FLOOR_1 + 4.8), (120, 120, 120), SMOOTH)
            box("Pile", (cx, cx + 8.0, z1 - 5.0, z1 - 1.5, FLOOR_1, FLOOR_1 + 3.0),
                (176, 150, 110), PLANKS)
        elif kind == "farm":
            box("Barn", (cx - 8.0, cx + 8.0, z0 + 3.0, z0 + 14.0, FLOOR_1 + 6.0, FLOOR_1 + 12.0),
                (196, 160, 120), WOOD)
            box("Hay", (cx - 2.0, cx + 2.0, z1 - 5.0, z1 - 1.0, FLOOR_1, FLOOR_1 + 3.0),
                (212, 180, 90), PLANKS)
        ceiling_light(cx, cz, CEIL_1)


for pid, label, x0, x1, kind, ftype in CIVIC:
    z0, z1 = 968.0, 1012.0
    cx = (x0 + x1) / 2
    wall_color = CIVIC_WALLS[CIVIC.index((pid, label, x0, x1, kind, ftype))]
    with group(pid):
        storefront(label, x0, x1, z0, z1, cx, wall_color, front="south", front_type=ftype)
        civic_fittings(kind, x0, x1, z0, z1)
    place_point(pid, cx, 970.0, FLOOR_1, f"the {label.lower()}, by the desk")

# ---------------------------------------------------------------------------
# Sports park
# ---------------------------------------------------------------------------


def soccer_field(x0, x1, z0, z1):
    """A 70x110 pitch with goals tagged for the rules to find."""
    with group("SoccerField"):
        box("Pitch", (x0, x1, z0, z1, GROUND_BOTTOM, GROUND), PITCH_GREEN, GRASS)
        # Touchlines, goal lines, halfway line.
        box("LineW", (x0 - 0.4, x0 + 0.4, z0, z1, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("LineE", (x1 - 0.4, x1 + 0.4, z0, z1, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("LineS", (x0, x1, z0 - 0.4, z0 + 0.4, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("LineN", (x0, x1, z1 - 0.4, z1 + 0.4, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("Half", (x0, x1, (z0 + z1) / 2 - 0.3, (z0 + z1) / 2 + 0.3, PAINT_BOTTOM, PAINT_TOP),
            (240, 240, 240), SMOOTH)
        box("Center", ((x0 + x1) / 2 - 1.0, (x0 + x1) / 2 + 1.0, (z0 + z1) / 2 - 1.0,
                       (z0 + z1) / 2 + 1.0, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        # Penalty boxes.
        for dz, toward in ((z0, 1), (z1, -1)):
            box(f"Box{dz:.0f}", (x0 + 12.0, x1 - 12.0, dz, dz + toward * 4.0,
                                 PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        # Goals, tagged so a future model swap keeps the sport working.
        for gz in (z0, z1):
            with group(f"Goal{gz:.0f}"):
                box("Post", (x0 + 12.0, x0 + 12.8, gz - 2.4, gz + 0.0, GROUND, GROUND + 8.0),
                    (240, 240, 240), METAL,
                    tags=[SPORT_TAG], attrs={SPORT_KIND: "soccer"})
                box("Post2", (x1 - 12.8, x1 - 12.0, gz - 2.4, gz + 0.0, GROUND, GROUND + 8.0),
                    (240, 240, 240), METAL,
                    tags=[SPORT_TAG], attrs={SPORT_KIND: "soccer"})
                box("Bar", (x0 + 12.0, x1 - 12.0, gz - 2.4, gz - 1.8, GROUND + 7.6, GROUND + 8.2),
                    (240, 240, 240), METAL,
                    tags=[SPORT_TAG], attrs={SPORT_KIND: "soccer"})


def basketball_court(x0, x1, z0, z1):
    with group("BasketballCourt"):
        box("Court", (x0, x1, z0, z1, GROUND_BOTTOM, GROUND), COURT_BLUE, SMOOTH)
        box("LineOut", (x0 - 0.3, x0 + 0.3, z0, z1, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("LineOut2", (x1 - 0.3, x1 + 0.3, z0, z1, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("LineEndS", (x0, x1, z0 - 0.3, z0 + 0.3, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("LineEndN", (x0, x1, z1 - 0.3, z1 + 0.3, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("Mid", (x0, x1, (z0 + z1) / 2 - 0.3, (z0 + z1) / 2 + 0.3, PAINT_BOTTOM, PAINT_TOP),
            (240, 240, 240), SMOOTH)
        cx = (x0 + x1) / 2
        # Each end: backboard and pole just outside the baseline, rim reaching
        # into the court. `into` is +1 for the south end, -1 for the north, so
        # both hoops point the same way relative to the baseline.
        for hz, into in ((z0, 1), (z1, -1)):
            with group(f"Hoop{hz:.0f}"):
                box("Backboard", (cx - 1.75, cx + 1.75, hz - into * 1.5, hz - into * 0.5,
                                  GROUND + 7.0, GROUND + 10.0),
                    (240, 240, 240), GLASS,
                    tags=[SPORT_TAG], attrs={SPORT_KIND: "basketball"})
                box("Rim", (cx - 1.5, cx + 1.5, hz + into * 0.5, hz + into * 1.5,
                            GROUND + 7.0, GROUND + 7.3),
                    (216, 120, 40), METAL,
                    tags=[SPORT_TAG], attrs={SPORT_KIND: "basketball"})
                box("Pole", (cx - 0.5, cx + 0.5, hz - into * 2.0, hz - into * 1.0,
                             GROUND, GROUND + 7.0), (120, 120, 126), METAL)


def tennis_court(x0, x1, z0, z1):
    with group("TennisCourt"):
        box("Court", (x0, x1, z0, z1, GROUND_BOTTOM, GROUND), COURT_GREEN, GRASS)
        box("BaselineS", (x0, x1, z0 - 0.3, z0 + 0.3, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("BaselineN", (x0, x1, z1 - 0.3, z1 + 0.3, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("SideW", (x0 - 0.3, x0 + 0.3, z0, z1, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("SideE", (x1 - 0.3, x1 + 0.3, z0, z1, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        # The net halves the court along its length; a service line sits in each
        # half, with a centre service line joining them down the middle.
        mid_z = (z0 + z1) / 2
        for side in (-1, 1):
            box(f"Service{side}", (x0, x1, mid_z + side * 3.5 - 0.3, mid_z + side * 3.5 + 0.3,
                                   PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("Center", ((x0 + x1) / 2 - 0.3, (x0 + x1) / 2 + 0.3, mid_z - 3.5, mid_z + 3.5,
                       PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        with group("Net"):
            box("Net", (x0, x1, mid_z - 0.1, mid_z + 0.1,
                        GROUND + 0.5, GROUND + 3.5), (230, 230, 230), FABRIC,
                tags=[SPORT_TAG], attrs={SPORT_KIND: "tennis"})
            box("PostW", (x0 - 0.5, x0, mid_z - 0.3, mid_z + 0.3,
                          GROUND, GROUND + 3.5), (120, 120, 126), METAL)
            box("PostE", (x1, x1 + 0.5, mid_z - 0.3, mid_z + 0.3,
                          GROUND, GROUND + 3.5), (120, 120, 126), METAL)


def playground(x0, x1, z0, z1):
    with group("Playground"):
        box("Sandpit", (x0, x1, z0, z1, GROUND_BOTTOM, GROUND - 0.1), SAND, PEBBLE)
        box("PitRim", (x0 - 0.4, x0 + 0.4, z0, z1, GROUND, GROUND + 0.3), (140, 120, 90), WOOD)
        box("PitRim2", (x1 - 0.4, x1 + 0.4, z0, z1, GROUND, GROUND + 0.3), (140, 120, 90), WOOD)
        box("PitRim3", (x0, x1, z0 - 0.4, z0 + 0.4, GROUND, GROUND + 0.3), (140, 120, 90), WOOD)
        box("PitRim4", (x0, x1, z1 - 0.4, z1 + 0.4, GROUND, GROUND + 0.3), (140, 120, 90), WOOD)
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        with group("Swings"):
            box("Beam", (cx - 8.0, cx + 8.0, z0 + 2.0, z0 + 2.6, GROUND + 7.0, GROUND + 7.6),
                STEEL, METAL, tags=[SPORT_TAG], attrs={SPORT_KIND: "playground"})
            for dx in (-7.0, 7.0):
                box(f"Post{dx}", (cx + dx - 0.4, cx + dx + 0.4, z0 + 1.2, z0 + 3.4,
                                  GROUND, GROUND + 7.0), STEEL, METAL)
            for dx in (-4.0, 4.0):
                box(f"Seat{dx}", (cx + dx - 0.8, cx + dx + 0.8, z0 + 4.6, z0 + 5.4,
                                  GROUND + 0.5, GROUND + 0.8), (180, 120, 80), WOOD)
        with group("Slide"):
            box("Ladder", (cx + 6.0, cx + 8.0, z1 - 4.0, z1 - 2.0, GROUND, GROUND + 5.0),
                STEEL, METAL, tags=[SPORT_TAG], attrs={SPORT_KIND: "playground"})
            box("SlideBed", (cx - 8.0, cx + 8.0, z1 - 7.0, z1 - 4.0, GROUND + 0.5, GROUND + 1.0),
                (96, 140, 180), METAL, tags=[SPORT_TAG], attrs={SPORT_KIND: "playground"})
        with group("Seesaw"):
            box("Pivot", (cx + 12.0, cx + 13.0, z0 + 8.0, z0 + 10.0, GROUND, GROUND + 2.0),
                STEEL, METAL, tags=[SPORT_TAG], attrs={SPORT_KIND: "playground"})
            box("Plank", (cx + 5.0, cx + 20.0, z0 + 8.6, z0 + 9.4, GROUND + 2.0, GROUND + 2.4),
                (180, 120, 80), WOOD)


def running_track(x0, x1, z0, z1):
    """A stadium-shaped ring of asphalt with a start/finish line."""
    lane = 10.0
    with group("RunningTrack"):
        box("StraightS", (x0, x1, z0, z0 + lane, GROUND_BOTTOM, GROUND), TRACK_RED, SMOOTH)
        box("StraightN", (x0, x1, z1 - lane, z1, GROUND_BOTTOM, GROUND), TRACK_RED, SMOOTH)
        box("EndW", (x0, x0 + lane, z0 + lane, z1 - lane, GROUND_BOTTOM, GROUND), TRACK_RED, SMOOTH)
        box("EndE", (x1 - lane, x1, z0 + lane, z1 - lane, GROUND_BOTTOM, GROUND), TRACK_RED, SMOOTH)
        box("Lane1", (x0 + lane * 0.25, x0 + lane * 0.75, z0 + 0.4, z0 + lane - 0.4,
                      PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("Lane2", (x1 - lane * 0.75, x1 - lane * 0.25, z0 + 0.4, z0 + lane - 0.4,
                      PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        with group("StartLine"):
            box("Start", (x0 + 2.0, x0 + 2.6, z0 + 0.4, z1 - 0.4, PAINT_BOTTOM, PAINT_TOP),
                (240, 240, 240), SMOOTH, tags=[SPORT_TAG], attrs={SPORT_KIND: "track"})


soccer_field(850.0, 920.0, 500.0, 610.0)
basketball_court(830.0, 862.0, 1000.0, 1018.0)
tennis_court(880.0, 908.0, 1000.0, 1014.0)
playground(830.0, 870.0, 900.0, 930.0)
running_track(860.0, 1000.0, 700.0, 770.0)

for pid, cx, cz in (
    ("soccer_field", 885.0, 555.0),
    ("basketball_court", 846.0, 1009.0),
    ("tennis_court", 894.0, 1007.0),
    ("playground", 850.0, 915.0),
    ("running_track", 930.0, 735.0),
):
    place_point(pid, cx, cz, GROUND, f"the {pid.replace('_', ' ')}")

# ---------------------------------------------------------------------------
# Street furniture
# ---------------------------------------------------------------------------

with group("StreetFurniture"):
    # Lamps along the connector and down each avenue, and at the high street.
    for z in range(120, 1000, 90):
        street_lamp(13.5, z, 1)
        street_lamp(47.5, z, -1)
    for a in AVE:
        for z in range(160, 960, 150):
            street_lamp(a + AVE_W + 1.5, z, 0)
    for x in range(100, 780, 130):
        street_lamp(x, 118.5, 0)
        street_lamp(x, 141.5, 0)

    # Trees in the block gardens between house rows, along the connector's west
    # margin, and ringing the sports park.
    for band in range(5):
        a0, a1 = AVE[band], AVE[band + 1]
        gx = (a0 + a1) / 2
        for sband in range(5):
            c0, c1 = CS[sband], CS[sband + 1]
            gz = (c0 + c1) / 2
            tree(gx, gz, GROUND, height=13.0, spread=8.0)
    for z in (150, 300, 450, 600, 750, 900):
        tree(10.0, z, GROUND, height=13.0, spread=8.0)
    for x, z in ((830, 120), (900, 120), (960, 400), (900, 650), (960, 820),
                 (830, 760), (830, 990), (990, 990), (990, 500), (990, 950)):
        tree(x, z, GROUND, height=14.0, spread=9.0)
    # Benches in the park.
    bench_x = 808.0
    box("BenchSeat", (bench_x + 4.0, bench_x + 10.0, 560.0, 562.0, GROUND + 1.5, GROUND + 1.85),
        DESK_TOP, WOOD)
    box("BenchSeat2", (bench_x + 4.0, bench_x + 10.0, 736.0, 738.0, GROUND + 1.5, GROUND + 1.85),
        DESK_TOP, WOOD)

# ---------------------------------------------------------------------------
# Place points and waypoints
# ---------------------------------------------------------------------------

# What surface sits under a coordinate, so every waypoint is grounded.
def surface_floor(x, z):
    if CONN_X0 < x < CONN_X1 and CONN_Z0 < z < CONN_Z1:
        return GROUND
    for a in AVE:
        if a < x < a + AVE_W and AVE_Z0 < z < AVE_Z1:
            return GROUND
    for c in CS:
        if c < z < c + CS_W and CS_X0 < x < CS_X1:
            return GROUND
    if HIGH_X0 < x < HIGH_X1 and HIGH_Z0 < z < HIGH_Z1:
        return GROUND
    if CONN_X0 - CONN_WALK < x < CONN_X0 and CONN_Z0 < z < CONN_Z1:
        return PAVING
    if CONN_X1 < x < CONN_X1 + CONN_WALK and CONN_Z0 < z < CONN_Z1:
        return PAVING
    for a in AVE:
        if a - AVE_WALK < x < a and AVE_Z0 < z < AVE_Z1:
            return PAVING
        if a + AVE_W < x < a + AVE_W + AVE_WALK and AVE_Z0 < z < AVE_Z1:
            return PAVING
    for c in CS:
        if CS_X0 < x < CS_X1 and c - CS_WALK < z < c:
            return PAVING
        if CS_X0 < x < CS_X1 and c + CS_W < z < c + CS_W + CS_WALK:
            return PAVING
    if HIGH_X0 < x < HIGH_X1 and HIGH_Z0 - HIGH_WALK < z < HIGH_Z0:
        return PAVING
    if HIGH_X0 < x < HIGH_X1 and HIGH_Z1 < z < HIGH_Z1 + HIGH_WALK:
        return PAVING
    return GROUND


WAYPOINTS = []


def waypoint(pid, x, z, label, floor=None):
    WAYPOINTS.append((pid, x, z, floor if floor is not None else surface_floor(x, z), label))


# Bridge from the town's east sidewalk into the city, over the grass seam. The
# first is within 70 studs of the town's "home" place point, so the whole graph
# reaches back to the town.
waypoint("city_bridge_1", -20.0, 64.0, "the grass where the city begins", GROUND)
waypoint("city_bridge_2", 6.0, 64.0, "the city's south edge", GROUND)

# The connector, chained every 70 studs, with points at the high street and the
# north end.
for i, z in enumerate(range(90, 1000, 70)):
    waypoint(f"conn_{i}", CONN_X1 + 2.0, float(z), "the connector road")
waypoint("conn_high", 45.0, 130.0, "the connector by the high street", GROUND)
waypoint("conn_north", 45.0, 960.0, "the connector north end", GROUND)

# Avenue centres, one point every 70 studs so a walk up any avenue chains
# north to south. The lattice is denser than one point per block on purpose: a
# block is 150 studs long, which is more than twice the 70-stud route link, so
# one point per block would break the walk into chunks that never reach each
# other.
#
# Points sit at the road centre rather than on the sidewalk because the sidewalk
# is carved away at every cross street, and for the last avenue those carve-outs
# run past the cross streets' own range -- a sidewalk point there would land on
# bare grass. The road centre is always asphalt: road slab or intersection tile.
for k, a in enumerate(AVE):
    for i, z in enumerate(range(90, 950, 70)):
        waypoint(f"ave{k}_{i}", a + AVE_W / 2, float(z), f"avenue {k + 1}")

# High-street crossings: a point on the high street road at every avenue, so the
# storefronts' walk and the avenue lattice reach each other.
for k, a in enumerate(AVE):
    waypoint(f"high_x{k}", a + AVE_W / 2, (HIGH_Z0 + HIGH_Z1) / 2,
             f"the high street at avenue {k + 1}")

# Cross street north sidewalks: one point at every avenue corner, so the east-
# west walks chain through the same corners the avenues use.
for j, c in enumerate(CS):
    for k, a in enumerate(AVE):
        waypoint(f"cs{j}_c{k}", a + AVE_W + 2.0, c + CS_W + 2.0,
                 f"cross street {j + 1}, avenue {k + 1}")

# The high street walks. z 118.5 is the south sidewalk, in front of the north
# row of stores; z 141.5 is the north sidewalk, in front of the south row.
for i, x in enumerate(range(60, 780, 70)):
    waypoint(f"high_{i}", float(x), HIGH_Z0 - HIGH_WALK / 2, "the high street, south side")
    waypoint(f"highs_{i}", float(x), HIGH_Z1 + HIGH_WALK / 2, "the high street, north side")

# The park: from the last avenue's east sidewalk across to each facility. The
# highest park point sits on grass north of the avenue's end, so it reaches the
# avenue lattice rather than relying on the avenue running past it.
for z in (560, 735, 915, 970):
    waypoint(f"park_av_{z:.0f}", AVE[-1] + AVE_W + 2.0, float(z), "the avenue side of the park")
for x, z in ((830, 560), (860, 735), (910, 735), (820, 1010)):
    waypoint(f"park_w_{x:.0f}_{z:.0f}", float(x), float(z), "across the park")

for pid, x, z, floor, label in WAYPOINTS:
    place_point(pid, x, z, floor, label)

# House place points, emitted with the house slots.
for x0, x1, z0, z1, door_z, front, number in HOUSE_SLOTS:
    px = (x0 + 2.0) if front == "west" else (x1 - 2.0)
    place_point(f"suburb_{number}", px, door_z, FLOOR_1,
                f"number {number}, on avenue {((number - 1) // 30) + 1}")

with group("PlacePoints"):
    for pid, x, z, floor, label in PLACE_POINTS:
        box(f"Place_{pid}", (x - 0.5, x + 0.5, z - 0.5, z + 0.5, floor, floor + 1.0),
            (255, 255, 255), SMOOTH, transparency=1.0, collide=False,
            tags=[PLACE_TAG],
            attrs={PLACE_ID_ATTRIBUTE: pid, PLACE_LABEL_ATTRIBUTE: label})

print(rbxmx.write(CITY, "City"))
