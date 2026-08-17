#!/usr/bin/env python3
"""Generates assets/Town.rbxmx: the town that grew past the end of the street.

Run from tools/:  python3 gen_town.py

Same relationship to world_plan.py that build_street.py has, one generation on:
build_street.py built the street that the player's house fronts onto -- the road,
the school, the workplace. This file builds everything that street turns into
when the town is allowed to be a town: the same road corridor continued north
and south, and on either side of it a gym, a library, a clinic, a bakery, a
garage, a park and four more houses.

**Why a second file rather than a longer build_street.py.** Street.rbxmx is
loaded every session and its numbers are checked by read_house.py against
world_plan.py. Town.rbxmx is younger than that and changes faster -- it is the
part of the world the player is told they can grow -- so it is allowed to carry
its own plan. If a new building ends up somewhere surprising, the surprise lives
in this file where the person who added it can be asked, not bolted onto the
plan of the street they did not touch.

**The swap contract.** Everything here is placeholder massing, and every piece a
player interacts with is tagged so that importing a real model later is a
replacement, not a rewrite:

  * Each building is one Model (`group`), so an imported school-style model can
    be dropped in and the routes, jobs and place points keep working because
    they are read off tags, not off geometry.
  * Each place point is an `AgesPlacePoint` part -- the same tag PlaceService
    already reads -- so the graph of places grows by tagging, not by editing
    Luau.
  * Each piece of gym equipment carries the `AgesGymEquipment` tag with a
    `GymKind` attribute. GymService keys off that tag. When real gym art is
    swapped in, whoever imports it keeps the tag on one part and the workout
    keeps working; the tag is the seam between this world's geometry and its
    rules.

The one rule nothing here is allowed to forget: the road, sidewalks and grass
must continue the exact bands build_street.py laid down, because a player who
walks north out of the school onto a sidewalk that has silently become a lawn
has found a bug, not a hedge.
"""

import rbxmx
from rbxmx import (
    ASPHALT, BRICK, CONCRETE, FABRIC, GLASS, GRASS, LEAFY_GRASS, MARBLE,
    METAL, NEON, PEBBLE, PLASTIC, PLANKS, SLATE, SMOOTH, WOOD,
)
from rbxmx import at, box, group, part, point_light, sign

from world_plan import (
    CEIL_1, DOORWAY, DOOR_LINE, FAR_WALK_X0, FAR_WALK_X1, FLOOR_1,
    FORECOURT_X0,
    FRONT_X, GATE_CLEAR, GROUND, NEAR_WALK_X0, NEAR_WALK_X1, PAVING,
    PLACE_ID_ATTRIBUTE, PLACE_LABEL_ATTRIBUTE, PLACE_TAG, PROPERTY_X,
    ROAD_MID, ROAD_X0, ROAD_X1, SLAB, SOUTHGATE_CLEAR, STREET_Z0, STREET_Z1,
    WALL,
)

from house_plan import _ASSETS

TOWN = _ASSETS / "Town.rbxmx"

rbxmx.begin("RBXTOWN")

# ---------------------------------------------------------------------------
# Plan
# ---------------------------------------------------------------------------

# Where the new ground starts. The original street ran Z -132..132; the town
# continues the same bands outward from there. -328 is far enough that the
# southernmost building has a meadow beyond it and room past the loop for the
# town to keep growing.
NORTH_Z0, NORTH_Z1 = STREET_Z1, 232.0          # 132..232
SOUTH_Z0, SOUTH_Z1 = -328.0, STREET_Z0          # -328..-132

# East of the player's own plot the corridor opens out. The near sidewalk ends
# at the property line; from there the ground is the town's until it runs into
# the field on the far side of the new houses.
EAST_X0 = PROPERTY_X                            # -52.6
EAST_X1 = 8.0
EAST_Z0, EAST_Z1 = -328.0, NORTH_Z1             # -328..232

# The west side's buildings all front the same line the school and workplace
# front -- FRONT_X -- so the town agrees about where the front of a building is.
WEST_X0 = -176.0                                # the west edge of the grass band

# South of the street the road loops back on itself: down the east leg, across
# the bottom, and north again up the return leg. That leaves a second road, west
# of the stores, for the town to grow onto. Every band is the width of the road
# it joins -- ROAD_X1 - ROAD_X0 -- so the loop is three rectangles of the same
# size rather than a curve that has to be told what radius it is.
CURL_Z = -290.0              # where the east leg turns west
ROAD_DEPTH = ROAD_X1 - ROAD_X0  # 23; the road is square in section, so the
                                # bottom band is as deep as the road is wide
RETURN_X0, RETURN_X1 = -225.0, -202.0   # the return leg, west of the stores
RETURN_Z0 = CURL_Z - ROAD_DEPTH         # -313, the south edge of the bottom band
RETURN_Z1 = STREET_Z0                   # -132, where the return leg runs out
ROAD_BOTTOM_MID = (CURL_Z + RETURN_Z0) / 2
RETURN_MID = (RETURN_X0 + RETURN_X1) / 2
# The grass west of the street widens to hold the return leg and a row of
# buildings on its far side, and the town's ground runs out just past the
# bottom of the loop.
SOUTH_WEST_X0 = -280.0
# How far south the far sidewalk runs before it hands the kerb back to the road.
FAR_END_Z = -280.0
# The width of a sidewalk band, used to size the return leg's own sidewalk.
SIDEWALK = FAR_WALK_X1 - FAR_WALK_X0

# Five single-storey buildings down the west side, north and south of the
# originals. Footprints leave a clear gap between neighbours so a building can
# be swapped without nudging the one next to it.
GYM_X0, GYM_X1 = -152.0, FRONT_X
GYM_Z0, GYM_Z1 = 96.0, 152.0
GYM_DOOR = 124.0

LIB_X0, LIB_X1 = -152.0, FRONT_X
LIB_Z0, LIB_Z1 = 168.0, 208.0
LIB_DOOR = 188.0

CLINIC_X0, CLINIC_X1 = -152.0, FRONT_X
CLINIC_Z0, CLINIC_Z1 = -116.0, -80.0
CLINIC_DOOR = -98.0

# The two service stores sit clear of each other and of the clinic -- an
# eight-stud gap between neighbours, so a building can be swapped without
# nudging the one next to it, and so the bakery's awning and the garage's
# roll-up door each get a face of their own instead of sharing a wall.
BAKERY_X0, BAKERY_X1 = -152.0, FRONT_X
BAKERY_Z0, BAKERY_Z1 = -160.0, -124.0
BAKERY_DOOR = -142.0

GARAGE_X0, GARAGE_X1 = -152.0, FRONT_X
GARAGE_Z0, GARAGE_Z1 = -204.0, -168.0
GARAGE_DOOR = -186.0

# Four houses on the east side: two north of the player's yard and two south.
#
# The imported house model is much bigger than its rooms. The rooms this town
# was planned around sit in X -12.5..30 by Z -27.5..20, but the model that
# contains them reaches X -55.9..32.5 by Z -44.3..56.8 -- its yard, paths and
# garden beds lap well past the interior. A new house on that same ground reads
# as a mistake even when the boxes do not touch, so every new house stands clear
# of the band rather than tight against it. Each is a simple west-facing shell.
#
# Those bounds are measured from House.rbxmx, and the previous version of this
# comment had the north edge at Z 78.1 -- 21.3 studs further north than the model
# actually reaches, and 46.9 rather than 32.5 in X. The exclusion was sized off
# that wrong number, which is why the clearance is lopsided: 7.7 studs south of
# the model at Z -52, and 31.2 studs north of it at Z 88. The south figure is the
# one that was chosen on purpose. The northern gap is the largest bare frontage
# left on the main road and it is an accident, not a design.
HOUSE_MODEL_Z0, HOUSE_MODEL_Z1 = -44.3, 56.8
# How close a new building may stand to the imported model's own ground.
# Safe range 6-12: under 6 the yards read as one plot, over 12 the street opens
# a hole in itself.
HOUSE_MODEL_CLEAR = 8.0
HOUSE_X0, HOUSE_X1 = -42.0, 2.0
# (z0, z1, door_z, door number)
HOUSES = [
    (88.0, 122.0, 105.0, "14"),
    (128.0, 162.0, 145.0, "16"),
    (-86.0, -52.0, -69.0, "18"),
    (-130.0, -96.0, -113.0, "20"),
]

# How far apart two neighbouring buildings stand on the east side. Houses 14 and
# 16 already leave exactly this, and anything new on this side keeps to it so the
# row reads as one street rather than as houses plus an intruder.
# Safe range 4-10: under 4 two roofs read as a single building, over 10 the row
# stops being a row and becomes separate objects with grass between them.
NEIGHBOUR_GAP = 6.0

# The corner shop, on the east frontage opposite the bakery.
#
# It was first built in the gap between the player's own plot and number 14,
# z 64.8..82, on the reading that this was the largest bare frontage on the
# street and that the stale house-model bound above had been fencing it off.
# Both edges were derived rather than typed and both derivations were right. The
# building still had to be torn down and moved, because the gap is not frontage:
# it is the window the gate road leaves town through, GATE_CLEAR is 60..82, and
# the shop stood square across the only link between the town and the city.
#
# Nothing in this file could see it. The road is drawn in gen_city.py, in another
# asset, against another generator's constants; check_city's check 7 reads every
# asset's walls against the city's streets and does catch it, and it was not run.
# Importing GATE_CLEAR is the fix that outlives remembering: the exclusion is now
# a fact this file holds rather than one it has to be told.
#
# The plot it moved to is the same shape in the same frontage line, one street
# further south, chosen so the shop faces the bakery across the road and the two
# read as a small parade rather than as one shop dropped into a gap. Its north
# edge keeps the row's own spacing from number 20; its depth is carried over
# unchanged because the interior below is laid out for it and was measured
# walkable at it.
SHOP_X0, SHOP_X1 = HOUSE_X0, HOUSE_X1
# Safe range 14-24: under 14 the aisles and the service spine stop both fitting,
# over 24 the shop is as deep as a house and stops reading as a shop.
SHOP_DEPTH = 17.2
SHOP_Z1 = HOUSES[3][0] - NEIGHBOUR_GAP
SHOP_Z0 = SHOP_Z1 - SHOP_DEPTH
SHOP_DOOR = (SHOP_Z0 + SHOP_Z1) / 2
assert SHOP_Z1 <= GATE_CLEAR[0] or SHOP_Z0 >= GATE_CLEAR[1], (
    f"the corner shop at z {SHOP_Z0}..{SHOP_Z1} stands in the gate road's "
    f"window at z {GATE_CLEAR[0]}..{GATE_CLEAR[1]}")

# ---------------------------------------------------------------------------
# The south row
# ---------------------------------------------------------------------------
# From the corner shop to the bottom of town was 137 studs of frontage with a
# paved sidewalk down the whole length of it and not one thing on the other
# side. It was the longest walk in the world with nothing at the end of it, and
# it is the half of town the spawn house looks out at.
#
# Nothing about the row is typed. The depth, the spacing and the numbering are
# all read off the four houses that already exist, and the row keeps laying
# plots until the next one will not fit -- so the frontage decides how many
# there are, and a change to the frontage moves the row instead of leaving a
# stale count behind it. That is the same defect this file has already shipped
# once, in HOUSE_MODEL_Z0/Z1 above.
HOUSE_DEPTH = HOUSES[0][1] - HOUSES[0][0]
assert HOUSES[1][0] - HOUSES[0][0] == HOUSE_DEPTH + NEIGHBOUR_GAP, (
    f"numbers 14 and 16 are {HOUSES[1][0] - HOUSES[0][0]} apart, which is not "
    f"a {HOUSE_DEPTH}-stud house plus a {NEIGHBOUR_GAP}-stud gap. The south row "
    f"copies that pitch, so it can no longer tell what the pitch is.")

# The row is laid north to south, so each plot's *north* edge is what carries
# forward. It steps over the southern link's window rather than stopping at it:
# stopping would silently shorten the row if that window ever moved north,
# which is exactly the kind of quiet truncation nobody notices until the street
# is short and no one can say why.
SOUTH_ROW = []
_z1 = SHOP_Z0 - NEIGHBOUR_GAP
_number = int(HOUSES[-1][3])
while True:
    _z0 = _z1 - HOUSE_DEPTH
    if _z0 < SOUTH_Z0:
        break
    if _z0 < SOUTHGATE_CLEAR[1] and _z1 > SOUTHGATE_CLEAR[0]:
        _z1 = SOUTHGATE_CLEAR[0] - NEIGHBOUR_GAP
        continue
    _number += 2
    SOUTH_ROW.append((_z0, _z1, (_z0 + _z1) / 2, str(_number)))
    _z1 = _z0 - NEIGHBOUR_GAP

# Safe range 2-6. Under 2 the row is not a row and the frontage has gone
# missing somewhere; over 6 something has opened up 250 studs of new frontage
# without anyone deciding to, and a wall of identical houses is worse than a
# field. Either way the number is a symptom, so this reports rather than clamps.
assert 2 <= len(SOUTH_ROW) <= 6, (
    f"the south row came out at {len(SOUTH_ROW)} houses between the shop at "
    f"z {SHOP_Z0} and the bottom of town at z {SOUTH_Z0}. Check SHOP_DEPTH, "
    f"SOUTH_Z0 and SOUTHGATE_CLEAR in world_plan.py.")
HOUSES.extend(SOUTH_ROW)

# The park, east of the road, at the top of the houses. Open ground with a pond,
# so the town has one place whose only purpose is being somewhere to be. Sits
# past the last house rather than between them: the east side reads as a row of
# houses that ends at a green, not a house wedged into a hedge.
PARK_X0, PARK_X1 = -44.0, 4.0
PARK_Z0, PARK_Z1 = 168.0, 228.0
PARK_SPOT = (-20.0, 176.0)

# The tag GymService reads to find a machine. Mirrors Config.Gym.EquipmentTag.
GYM_TAG = "AgesGymEquipment"
GYM_KIND_ATTR = "GymKind"

# id, x, z, floor, label. Every new place plus the waypoints that stitch them
# into the route graph -- Routes joins any two place points within 70 studs, and
# these are spaced so every building is within that of a waypoint, and every
# waypoint within that of the next, all the way from the bottom of the street to
# the top.
PLACE_POINTS = [
    ("gym", -120.0, GYM_DOOR, FLOOR_1, "the gym, past the treadmills"),
    ("library", -120.0, LIB_DOOR, FLOOR_1, "the library, by the desk"),
    ("clinic", -120.0, CLINIC_DOOR, FLOOR_1, "the clinic reception"),
    ("bakery", -120.0, BAKERY_DOOR, FLOOR_1, "the bakery, at the counter"),
    ("garage", -120.0, GARAGE_DOOR, FLOOR_1, "the garage workshop"),
    ("park", PARK_SPOT[0], PARK_SPOT[1], GROUND, "the park, by the pond"),
    # Stood in front of the counter rather than behind it: this is where the
    # player is told to be, and the same spot a customer walks to, which is what
    # every other "at the counter" point in town already means.
    ("corner_shop", SHOP_X0 + 6.0, SHOP_DOOR - 2.0, FLOOR_1, "the corner shop, at the counter"),
    # The houses' own points are generated from HOUSES below, not listed here.
    # West sidewalk: the school's north corner up to the top of the street.
    ("corner_n", -92.0, 84.0, PAVING, "the sidewalk north of the school"),
    ("wp_north_1", -92.0, 128.0, PAVING, "outside the gym"),
    ("wp_north_2", -92.0, 172.0, PAVING, "outside the library"),
    ("wp_north_3", -92.0, 216.0, PAVING, "the top of the street"),
    # West sidewalk: the workplace's south corner down to the bottom.
    ("corner_s", -92.0, -80.0, PAVING, "the sidewalk south of the store"),
    ("wp_south_1", -92.0, -124.0, PAVING, "outside the clinic"),
    ("wp_south_2", -92.0, -145.0, PAVING, "outside the bakery"),
    ("wp_south_3", -92.0, -212.0, PAVING, "outside the garage"),
    ("wp_south_4", -92.0, -272.0, PAVING, "the south end of the far walk"),
    # The loop: waypoints on the return road and across the bottom, stitched to
    # the far walk through the inner grass so the south of town is one connected
    # place rather than two dead ends. Spaced so every hop is inside the route
    # link radius, down the long return road and back.
    ("wp_inner", -155.0, -160.0, GROUND, "the grass by the return road"),
    ("wp_inner_n", -170.0, -145.0, GROUND, "the grass between the stores and the return road"),
    ("wp_loop_n", -207.0, -145.0, PAVING, "the return road, north end"),
    ("wp_loop_m_grass", -187.0, -195.0, GROUND, "the grass behind the garage"),
    ("wp_loop_m", -207.0, -195.0, PAVING, "the return road, by the garage"),
    ("wp_loop_m2", -207.0, -255.0, PAVING, "the return road, mid-town"),
    ("wp_inner_m", -172.0, -250.0, GROUND, "the grass between the roads, south"),
    ("wp_inner_s", -150.0, -262.0, GROUND, "the grass between the roads"),
    ("wp_loop_s", -207.0, -300.0, GROUND, "the south turn of the road"),
    # East sidewalk: the new houses and the park, off the crossing.
    ("wp_east_n1", -58.0, 40.0, PAVING, "outside number 14"),
    ("wp_east_n2", -58.0, 88.0, PAVING, "outside number 16"),
    ("wp_east_n3", -58.0, 136.0, PAVING, "the way to the park"),
    # The player's own front door. Without this the near sidewalk has a 76-stud
    # hole in it across the frontage of the one plot that matters, and 76 is
    # over PlaceService's link radius -- so the spawn was joined to the south of
    # town and to nothing else. It could not reach the gate road, and therefore
    # could not reach the city at all. Nothing caught it: check_city asks
    # whether the city reaches *a* town point, and it did, at the far end of a
    # chain the player was not on. See check 12, which now asks from the spawn.
    ("wp_east_home", -58.0, DOOR_LINE, PAVING, "the sidewalk outside your front gate"),
    ("wp_east_s1", -58.0, -36.0, PAVING, "outside number 18"),
    ("wp_east_s2", -58.0, -80.0, PAVING, "outside number 20"),
    ("wp_east_s3", -58.0, -124.0, PAVING, "the south end of the near sidewalk"),
]

# One point in every house, and one on the sidewalk outside every house in the
# south row -- both generated from HOUSES rather than typed next to it. The
# original four were literals, which works right up until a fifth house exists
# with no point inside it: a home the game cannot send anybody to, in a world
# where nothing checks that a building has a door the route graph knows about.
PLACE_POINTS.extend(
    (f"home_{i + 1}", HOUSE_X0 + 2.0, door_z, FLOOR_1, f"number {number}")
    for i, (_hz0, _hz1, door_z, number) in enumerate(HOUSES))
PLACE_POINTS.extend(
    (f"wp_east_s{4 + i}", -58.0, door_z, PAVING,
     f"outside number {number}")
    for i, (_hz0, _hz1, door_z, number) in enumerate(SOUTH_ROW))

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------

# The same dull civic colours as build_street.py, so the two files read as one
# town. The player's house is the saturated thing in this world.
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
# The bakery's striped awning and its trim.
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

# Per-building wall tones, so five boxes on one side of a road read as five
# buildings and not one long wall.
GYM_WALL = (170, 176, 184)      # pale concrete
LIB_WALL = BRICK_PALE
CLINIC_WALL = (214, 218, 224)   # clean white
BAKERY_WALL = (204, 176, 132)   # warm cream
GARAGE_WALL = (122, 126, 132)   # sheet steel

HOUSE_WALL = (166, 118, 92)

# The shop is the only non-residential thing on the east side, so it is allowed
# one saturated colour the houses do not have -- a painted fascia. That band is
# the whole of its signposting from the road: at the distance a player first sees
# it, the roofline reads before the lettering does.
SHOP_WALL = (198, 190, 176)     # painted render, lighter than the brick either side
SHOP_FASCIA = (44, 96, 78)      # deep green
CHILLER_FRAME = (222, 224, 228)
CRATE = (150, 116, 78)

# As in build_street.py: a door opening is nine studs tall so a player runs
# through without clipping the lintel.
DOOR_HEIGHT = 9.0

# Road markings and kerbs, matching build_street.py's values exactly.
CENTRE_WIDTH = 0.6
DASH_LENGTH = 6.0
DASH_GAP = 6.0
PAINT_LIFT = 0.02
PAINT_THICK = 0.12
KERB_WIDTH = 0.8
SLAB_SINK = 0.6
GROUND_BOTTOM = -1.0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def wall(name, bounds, color, material=BRICK, doors=(), head=DOOR_HEIGHT,
         along="z", collide=True):
    """One wall as a set of boxes, minus its doorways, plus a lintel over each.

    The same helper build_street.py uses, so a door is argued about the same way
    everywhere: a range on the `along` axis, and the hole in the wall is a real
    hole with no invisible part left in the opening.
    """
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


def shell(name, x0, x1, z0, z1, door_z, wall_color, wall_mat=BRICK, front="shop"):
    """A single-storey shell with the door in the east wall.

    The west-side buildings face the road the way the school does, so their door
    is in the east wall, with a windowed front either side of it and the name
    riding the parapet. Three fronts, so three stores on one road read as three
    businesses rather than as one long building: the glazed shopfront, the
    bakery's under a striped awning, and the garage's wide roll-up door with no
    window at all.
    """
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    d0, d1 = door_z - DOORWAY / 2, door_z + DOORWAY / 2

    with group(f"{name}Structure"):
        box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1), FLOOR_INDOOR, MARBLE)
        box("Roof", (x0, x1, z0, z1, CEIL_1, CEIL_1 + SLAB), ROOF_GREY, SLATE)
        wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, CEIL_1), wall_color, wall_mat, along="z")
        wall("WallSouth", (x0, x1, z0, iz0, FLOOR_1, CEIL_1), wall_color, wall_mat, along="x")
        wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, CEIL_1), wall_color, wall_mat, along="x")

        if front == "garage":
            # A workshop front: no shop window, just a wide door the work drives
            # through and, in the opening, the rolled-up shutter itself. The
            # shutter is non-colliding so the player walks through it, which is
            # the same thing they do to a glazed shop door -- the wall's job is
            # to say what the room is, not to stop the player.
            gd0, gd1 = door_z - 7.0, door_z + 7.0
            wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, CEIL_1), wall_color, wall_mat,
                 along="z", doors=((gd0, gd1),), head=CEIL_1 - FLOOR_1)
            box("RollupDoor", (ix1 + 0.4, x1 - 0.4, gd0, gd1,
                               FLOOR_1 + 4.0, FLOOR_1 + 14.0), STEEL, METAL, collide=False)
            for i in range(7):
                zz = gd0 + (gd1 - gd0) * (i + 0.5) / 7
                box(f"RollupSlat{i}", (ix1 + 0.6, x1 - 0.6, zz - 0.12, zz + 0.12,
                                       FLOOR_1 + 4.0, FLOOR_1 + 14.0),
                    (96, 98, 102), METAL, collide=False)
            box("Nameplate", (x1 - 2.5, x1, door_z - 6.0, door_z + 6.0,
                              CEIL_1 + SLAB, 24.0),
                wall_color, BRICK,
                children=sign(name, "right", color=(250, 246, 234), size=72))
        else:
            wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, CEIL_1), wall_color, wall_mat,
                 along="z", doors=((d0, d1),))
            for i, (a, b) in enumerate(((iz0 + 3.0, d0 - 1.0), (d1 + 1.0, iz1 - 3.0))):
                if b - a > 4.0:
                    glazing(f"Shopfront{i + 1}",
                            (ix1 + 0.4, x1 - 0.4, a, b, FLOOR_1 + 1.5, FLOOR_1 + 10.5),
                            along="z", panes=4)
            box("Nameplate", (x1 - 2.5, x1, door_z - 9.0, door_z + 9.0,
                              CEIL_1 + SLAB, 24.0),
                wall_color, BRICK,
                children=sign(name, "right", color=(250, 246, 234), size=72))
            if front == "awning":
                # A striped canopy over the shopfront, standing a little proud
                # of the wall, so the bakery is the one with a face on the
                # street. Non-colliding: a player walks under it, not through a
                # wall of fabric.
                box("Awning", (x1 - 0.4, x1 + 3.2, iz0 + 2.0, iz1 - 2.0,
                               FLOOR_1 + 8.0, FLOOR_1 + 10.5), AWNING_RED, FABRIC, collide=False)
                box("AwningTrim", (x1 + 3.2, x1 + 3.4, iz0 + 2.0, iz1 - 2.0,
                                   FLOOR_1 + 8.0, FLOOR_1 + 10.5), AWNING_CREAM, FABRIC, collide=False)
                box("AwningValance", (x1 + 2.9, x1 + 3.2, iz0 + 2.0, iz1 - 2.0,
                                      FLOOR_1 + 8.0, FLOOR_1 + 9.2), AWNING_RED, FABRIC, collide=False)


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


def shelf_run(x, z0, z1, floor, label="Shelving"):
    """A gondola of shelves with something on them, running along z."""
    with group(label):
        box(f"{label}Base", (x - 1.6, x + 1.6, z0, z1, floor, floor + 0.6), SHELF, METAL)
        for i, dy in enumerate((3.0, 5.6, 8.2)):
            box(f"{label}Deck{i + 1}", (x - 1.6, x + 1.6, z0, z1, floor + dy,
                                        floor + dy + 0.3), SHELF, METAL)
        box(f"{label}Spine", (x - 0.2, x + 0.2, z0, z1, floor, floor + 9.5), SHELF, METAL)
        n = max(1, int((z1 - z0) // 3.0))
        for i in range(n):
            a = z0 + (z1 - z0) * i / n + 0.4
            b = z0 + (z1 - z0) * (i + 1) / n - 0.4
            for dy in (3.3, 5.9):
                box(f"{label}Stock", (x - 1.4, x + 1.4, a, b, floor + dy,
                                      floor + dy + 1.8), STOCK, PLANKS, collide=False)


def aisle_run(z, x0, x1, floor, label="Aisle"):
    """The same gondola as shelf_run, turned to run along x instead of z.

    Two functions rather than one with an axis argument because every bound in
    both is written out flat, and an axis flag would mean six ternaries in the
    body of something whose whole job is to be obvious. The shop's aisles run
    east-west, at right angles to the library's shelving, so it needs the other
    one.
    """
    with group(label):
        box(f"{label}Base", (x0, x1, z - 1.6, z + 1.6, floor, floor + 0.6), SHELF, METAL)
        for i, dy in enumerate((3.0, 5.6, 8.2)):
            box(f"{label}Deck{i + 1}", (x0, x1, z - 1.6, z + 1.6, floor + dy,
                                        floor + dy + 0.3), SHELF, METAL)
        box(f"{label}Spine", (x0, x1, z - 0.2, z + 0.2, floor, floor + 9.5), SHELF, METAL)
        n = max(1, int((x1 - x0) // 3.0))
        for i in range(n):
            a = x0 + (x1 - x0) * i / n + 0.4
            b = x0 + (x1 - x0) * (i + 1) / n - 0.4
            for dy in (3.3, 5.9):
                box(f"{label}Stock", (a, b, z - 1.4, z + 1.4, floor + dy,
                                      floor + dy + 1.8), STOCK, PLANKS, collide=False)


def tree(x, z, floor, height=15.0, spread=10.0, label="Tree"):
    """Trunk you can walk into, canopy you cannot."""
    with group(label):
        with at(x, z, floor=floor):
            part("Trunk", (0, 0, 0), (1.6, height * 0.62, 1.6), BARK, WOOD)
            part("Canopy", (0, height * 0.5, 0), (spread, spread * 0.72, spread),
                 LEAF, LEAFY_GRASS, collide=False)
            part("CanopyTop", (0, height * 0.5 + spread * 0.5, 0),
                 (spread * 0.66, spread * 0.5, spread * 0.66),
                 LEAF, LEAFY_GRASS, collide=False)


def bench(x, z, floor, side="north", label="Bench"):
    with group(label):
        with at(x, z, side=side, floor=floor):
            part("Seat", (0, 1.5, 0.9), (6.0, 0.35, 2.0), DESK_TOP, WOOD)
            part("Back", (0, 1.85, 0.1), (6.0, 1.8, 0.3), DESK_TOP, WOOD)
            for dx in (-2.5, 2.5):
                part("Leg", (dx, 0, 0.9), (0.35, 1.5, 1.8), STEEL, METAL)


def street_lamp(x, z, toward, label="StreetLamp"):
    """A pole on the sidewalk with its arm reaching `toward` (+1 east, -1 west)."""
    with group(label):
        with at(x, z, floor=PAVING):
            part("Base", (0, 0, 0), (1.4, 0.5, 1.4), STEEL, METAL)
            part("Pole", (0, 0.5, 0), (0.5, 12.0, 0.5), STEEL, METAL)
            part("Arm", (toward * 1.4, 12.0, 0), (3.2, 0.4, 0.4), STEEL, METAL)
            part("Head", (toward * 2.9, 11.4, 0), (1.6, 0.7, 1.0),
                 FITTING, NEON, children=point_light(LAMP_LIGHT, 1.6, 26.0))


def place_point(pid, x, z, floor, label):
    """The same invisible tagged coordinate PlaceService already reads."""
    box(f"Place_{pid}", (x - 0.5, x + 0.5, z - 0.5, z + 0.5, floor, floor + 1.0),
        (255, 255, 255), SMOOTH, transparency=1.0, collide=False,
        tags=[PLACE_TAG],
        attrs={PLACE_ID_ATTRIBUTE: pid, PLACE_LABEL_ATTRIBUTE: label})


# ---------------------------------------------------------------------------
# Ground, road, sidewalks
# ---------------------------------------------------------------------------

with group("Ground"):
    # The road corridor continued north, south, and east of the player's plot.
    # Three bands rather than one slab, mirroring build_street.py: grass, road,
    # grass, so no two boxes that share a top height overlap and z-fight.
    box("GrassWestN", (WEST_X0, ROAD_X0, NORTH_Z0, NORTH_Z1, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)
    box("GrassEastN", (ROAD_X1, EAST_X0, NORTH_Z0, NORTH_Z1, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)
    box("RoadN", (ROAD_X0, ROAD_X1, NORTH_Z0, NORTH_Z1, GROUND_BOTTOM, GROUND),
        TARMAC, ASPHALT)

    # South of the street the road loops: down the east leg, across the bottom,
    # back up the return leg. The grass tiles around it exactly, the way the
    # bands north of the street do, so the loop reads as road-in-grass rather
    # than as a line of separate boxes.
    box("GrassBottom", (SOUTH_WEST_X0, ROAD_X1, SOUTH_Z0, RETURN_Z0, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)
    box("GrassWestLoop", (SOUTH_WEST_X0, RETURN_X0, RETURN_Z0, STREET_Z0, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)
    box("GrassInner", (RETURN_X1, ROAD_X0, CURL_Z, STREET_Z0, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)
    box("GrassEastS", (ROAD_X1, EAST_X0, SOUTH_Z0, STREET_Z0, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)
    box("RoadEast", (ROAD_X0, ROAD_X1, CURL_Z, STREET_Z0, GROUND_BOTTOM, GROUND),
        TARMAC, ASPHALT)
    box("RoadBottom", (RETURN_X1, ROAD_X1, RETURN_Z0, CURL_Z, GROUND_BOTTOM, GROUND),
        TARMAC, ASPHALT)
    box("RoadReturn", (RETURN_X0, RETURN_X1, RETURN_Z0, STREET_Z0, GROUND_BOTTOM, GROUND),
        TARMAC, ASPHALT)

    # East of the property line: one continuous bed of grass the length of the
    # new quarter, under the houses and the park.
    box("GrassEast", (EAST_X0, EAST_X1, EAST_Z0, EAST_Z1, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)

    # The grass west of the original street edge widens north of the loop too,
    # so the return leg ends against its own meadow rather than a cliff.
    box("GrassWestMargin", (SOUTH_WEST_X0, WEST_X0, STREET_Z0, NORTH_Z1,
                            GROUND_BOTTOM, GROUND), LAWN, GRASS)

with group("Road"):
    # Centre dashes, continuing the pattern build_street.py started (dashes on
    # 126, 114, ... going south; 138, 150, ... going north) so the line reads
    # as one road rather than three short ones.
    for z in range(138, int(NORTH_Z1), 12):
        box(f"DashN{z}", (ROAD_MID - CENTRE_WIDTH / 2, ROAD_MID + CENTRE_WIDTH / 2,
                          float(z), float(z) + DASH_LENGTH,
                          GROUND + PAINT_LIFT - PAINT_THICK, GROUND + PAINT_LIFT),
            ROAD_PAINT, SMOOTH)
    for z in range(-138, int(CURL_Z) - 1, -12):
        box(f"DashEast{abs(z)}", (ROAD_MID - CENTRE_WIDTH / 2, ROAD_MID + CENTRE_WIDTH / 2,
                                  float(z), float(z) + DASH_LENGTH,
                                  GROUND + PAINT_LIFT - PAINT_THICK, GROUND + PAINT_LIFT),
            ROAD_PAINT, SMOOTH)
    # The bottom and return legs, dashed the same way: a centre line along each,
    # so the loop is one road that happens to fold rather than three roads that
    # meet. Stopped short of the road's ends so no dash runs off onto the grass.
    for x in range(int(RETURN_X1), int(ROAD_X1) - 12, 12):
        box(f"DashBottom{abs(x)}", (float(x), float(x) + DASH_LENGTH,
                                    ROAD_BOTTOM_MID - CENTRE_WIDTH / 2,
                                    ROAD_BOTTOM_MID + CENTRE_WIDTH / 2,
                                    GROUND + PAINT_LIFT - PAINT_THICK, GROUND + PAINT_LIFT),
            ROAD_PAINT, SMOOTH)
    for z in range(int(RETURN_Z0), int(STREET_Z0) - 12, 12):
        box(f"DashReturn{abs(z)}", (RETURN_MID - CENTRE_WIDTH / 2, RETURN_MID + CENTRE_WIDTH / 2,
                                    float(z), float(z) + DASH_LENGTH,
                                    GROUND + PAINT_LIFT - PAINT_THICK, GROUND + PAINT_LIFT),
            ROAD_PAINT, SMOOTH)

with group("Sidewalks"):
    # The four bands north of the street, unchanged: kerb at the road edge,
    # paving against the buildings, both sunk into the ground.
    for prefix, z0, z1 in (("N", NORTH_Z0, NORTH_Z1),):
        box(f"NearKerb{prefix}", (NEAR_WALK_X0, NEAR_WALK_X0 + KERB_WIDTH, z0, z1,
                                  GROUND - SLAB_SINK, PAVING), KERB_GREY, CONCRETE)
        box(f"NearPaving{prefix}", (NEAR_WALK_X0 + KERB_WIDTH, NEAR_WALK_X1, z0, z1,
                                    GROUND - SLAB_SINK, PAVING), PAVING_GREY, PEBBLE)
        box(f"FarKerb{prefix}", (FAR_WALK_X1 - KERB_WIDTH, FAR_WALK_X1, z0, z1,
                                 GROUND - SLAB_SINK, PAVING), KERB_GREY, CONCRETE)
        box(f"FarPaving{prefix}", (FAR_WALK_X0, FAR_WALK_X1 - KERB_WIDTH, z0, z1,
                                   GROUND - SLAB_SINK, PAVING), PAVING_GREY, PEBBLE)

    # South of the street, the same two bands plus the return leg's own. The
    # near band runs out flush with the east leg's turn, the far band runs past
    # the garage toward the loop's turn, and the return band follows the return
    # road -- so each store and each future frontage on the loop has a walk to
    # stand on.
    box("NearKerbS", (NEAR_WALK_X0, NEAR_WALK_X0 + KERB_WIDTH, CURL_Z, STREET_Z0,
                      GROUND - SLAB_SINK, PAVING), KERB_GREY, CONCRETE)
    box("NearPavingS", (NEAR_WALK_X0 + KERB_WIDTH, NEAR_WALK_X1, CURL_Z, STREET_Z0,
                        GROUND - SLAB_SINK, PAVING), PAVING_GREY, PEBBLE)
    box("FarKerbS", (FAR_WALK_X1 - KERB_WIDTH, FAR_WALK_X1, FAR_END_Z, STREET_Z0,
                     GROUND - SLAB_SINK, PAVING), KERB_GREY, CONCRETE)
    box("FarPavingS", (FAR_WALK_X0, FAR_WALK_X1 - KERB_WIDTH, FAR_END_Z, STREET_Z0,
                       GROUND - SLAB_SINK, PAVING), PAVING_GREY, PEBBLE)
    box("ReturnKerb", (RETURN_X1, RETURN_X1 + KERB_WIDTH, CURL_Z, STREET_Z0,
                       GROUND - SLAB_SINK, PAVING), KERB_GREY, CONCRETE)
    box("ReturnPaving", (RETURN_X1 + KERB_WIDTH, RETURN_X1 + SIDEWALK, CURL_Z, STREET_Z0,
                         GROUND - SLAB_SINK, PAVING), PAVING_GREY, PEBBLE)

with group("Forecourts"):
    # A flat apron in front of each new west-side building, running from its
    # front wall out to the far sidewalk -- the walk from the road to a desk is
    # flat the whole way, the same as the school's.
    for name, z0, z1 in (
        ("Gym", GYM_Z0, GYM_Z1),
        ("Library", LIB_Z0, LIB_Z1),
        ("Clinic", CLINIC_Z0, CLINIC_Z1),
        ("Bakery", BAKERY_Z0, BAKERY_Z1),
        ("Garage", GARAGE_Z0, GARAGE_Z1),
    ):
        box(f"{name}Forecourt",
            (FORECOURT_X0, FAR_WALK_X0, z0, z1, GROUND - SLAB_SINK, PAVING),
            PAVING_GREY, PEBBLE)

# ---------------------------------------------------------------------------
# Gym equipment
# ---------------------------------------------------------------------------

# Each machine is its own Model so it can be swapped for real art, and each
# carries the AgesGymEquipment tag on one part with its GymKind -- the seam the
# rules read. GymService finds machines by tag, never by name or position.


def treadmill(x, z, label="Treadmill"):
    with group(label):
        box(f"{label}Belt", (x - 1.1, x + 1.1, z - 1.6, z + 1.6, FLOOR_1, FLOOR_1 + 0.5),
            (34, 38, 42), SMOOTH, tags=[GYM_TAG], attrs={GYM_KIND_ATTR: "treadmill"})
        box(f"{label}Deck", (x - 1.3, x + 1.3, z - 0.8, z + 1.6, FLOOR_1 + 0.5, FLOOR_1 + 0.8),
            STEEL, METAL)
        box(f"{label}Console", (x - 0.7, x + 0.7, z + 1.3, z + 2.0, FLOOR_1 + 0.8, FLOOR_1 + 3.0),
            (20, 24, 30), SMOOTH)


def bench_press(x, z, label="BenchPress"):
    with group(label):
        box(f"{label}Base", (x - 1.0, x + 1.0, z - 1.4, z + 1.4, FLOOR_1, FLOOR_1 + 0.3),
            STEEL, METAL, tags=[GYM_TAG], attrs={GYM_KIND_ATTR: "bench"})
        box(f"{label}Post", (x - 0.2, x + 0.2, z - 1.8, z + 1.8, FLOOR_1, FLOOR_1 + 3.6),
            STEEL, METAL)
        box(f"{label}Bar", (x - 1.6, x + 1.6, z - 0.2, z + 0.2, FLOOR_1 + 3.4, FLOOR_1 + 3.8),
            STEEL, METAL)
        box(f"{label}Seat", (x - 0.5, x + 0.5, z - 0.8, z + 0.8, FLOOR_1 + 1.6, FLOOR_1 + 2.0),
            (40, 44, 80), FABRIC)


def dumbbell_rack(x, z0, z1, label="Dumbbells"):
    with group(label):
        box(f"{label}Base", (x - 0.9, x + 0.9, z0, z1, FLOOR_1, FLOOR_1 + 0.6),
            STEEL, METAL, tags=[GYM_TAG], attrs={GYM_KIND_ATTR: "dumbbells"})
        box(f"{label}Rack", (x - 0.7, x + 0.7, z0 + 0.5, z1 - 0.5, FLOOR_1 + 0.6, FLOOR_1 + 2.2),
            STEEL, METAL)
        for i in range(int((z1 - z0) // 3)):
            z = z0 + 1.5 + i * 3
            box(f"{label}Db{i}", (x - 0.5, x + 0.5, z - 1.0, z + 1.0, FLOOR_1 + 2.2, FLOOR_1 + 2.6),
                (120, 120, 128), METAL, collide=False)


def pullup(x, z, label="PullUp"):
    with group(label):
        box(f"{label}Base", (x - 0.8, x + 0.8, z - 1.2, z + 1.2, FLOOR_1, FLOOR_1 + 0.4),
            STEEL, METAL, tags=[GYM_TAG], attrs={GYM_KIND_ATTR: "pullup"})
        for dz in (-1.0, 1.0):
            box(f"{label}Post", (x - 0.25, x + 0.25, z + dz - 0.2, z + dz + 0.2,
                                 FLOOR_1, FLOOR_1 + 8.5), STEEL, METAL)
        box(f"{label}Bar", (x - 1.2, x + 1.2, z - 0.15, z + 0.15, FLOOR_1 + 8.4, FLOOR_1 + 8.7),
            STEEL, METAL)


# ---------------------------------------------------------------------------
# The gym
# ---------------------------------------------------------------------------

with group("Gym"):
    shell("GOLDFIELD GYM", GYM_X0, GYM_X1, GYM_Z0, GYM_Z1, GYM_DOOR, GYM_WALL)

    with group("GymFittings"):
        # Machines against the north wall, facing the room; the rack and the
        # pull-up bar on the west side; mirrors down the east wall. The middle
        # of the floor stays open, because that is where the workout happens.
        treadmill(-139.0, 147.0, label="Treadmill1")
        treadmill(-125.0, 147.0, label="Treadmill2")
        bench_press(-132.0, 124.0)
        dumbbell_rack(-149.5, 104.0, 120.0)
        pullup(-139.0, 104.0)
        glazing("MirrorEast",
                (GYM_X1 - 1.6, GYM_X1 - 0.4, GYM_Z0 + 4.0, GYM_Z1 - 4.0,
                 FLOOR_1 + 2.0, FLOOR_1 + 8.0), along="z", panes=6)
        ceiling_light(-140.0, 106.0, CEIL_1)
        ceiling_light(-122.0, 124.0, CEIL_1)
        ceiling_light(-132.0, 142.0, CEIL_1)

# ---------------------------------------------------------------------------
# The library
# ---------------------------------------------------------------------------

with group("Library"):
    shell("TOWN LIBRARY", LIB_X0, LIB_X1, LIB_Z0, LIB_Z1, LIB_DOOR, LIB_WALL)

    with group("LibraryFittings"):
        # Shelves down the west and east walls, reading tables in the middle,
        # and the librarian's desk set back from the door.
        shelf_run(LIB_X0 + WALL + 1.6, LIB_Z0 + 6.0, LIB_Z1 - 6.0, FLOOR_1, label="WestShelf")
        shelf_run(LIB_X1 - WALL - 1.6, LIB_Z0 + 6.0, LIB_Z1 - 6.0, FLOOR_1, label="EastShelf")
        desk(LIB_X0 + 20.0, LIB_DOOR, FLOOR_1, side="east", width=8.0, depth=3.0,
             label="Desk")
        chair(LIB_X0 + 20.0, LIB_DOOR - 4.0, FLOOR_1, side="south")
        for x, z in ((-134.0, 190.0), (-134.0, 180.0)):
            desk(x, z, FLOOR_1, side="east", width=4.0, depth=2.4, label="ReadingTable")
            for dz in (-3.0, 3.0):
                chair(x + 0.5, z + dz, FLOOR_1, side="west")
        ceiling_light(-130.0, 188.0, CEIL_1)
        ceiling_light(-138.0, 178.0, CEIL_1)

# ---------------------------------------------------------------------------
# The clinic
# ---------------------------------------------------------------------------

with group("Clinic"):
    shell("CLINIC", CLINIC_X0, CLINIC_X1, CLINIC_Z0, CLINIC_Z1, CLINIC_DOOR, CLINIC_WALL)

    with group("ClinicFittings"):
        # Reception by the door, an exam bed against the north wall with a light
        # over it, and a medicine shelf along the south wall.
        desk(CLINIC_X0 + 26.0, CLINIC_DOOR, FLOOR_1, side="north", width=8.0, depth=3.0,
             label="Reception")
        chair(CLINIC_X0 + 26.0, CLINIC_DOOR - 4.0, FLOOR_1, side="south")
        box("ExamBed", (CLINIC_X1 - 14.0, CLINIC_X1 - 6.0, CLINIC_Z1 - 9.0, CLINIC_Z1 - 3.0,
                        FLOOR_1 + 1.5, FLOOR_1 + 3.2), (214, 218, 224), FABRIC)
        box("ExamLight", (CLINIC_X1 - 10.0, CLINIC_X1 - 9.0, CLINIC_Z1 - 6.0, CLINIC_Z1 - 5.0,
                          CEIL_1 - 2.0, CEIL_1 - 1.0), FITTING, NEON)
        shelf_run(CLINIC_X0 + WALL + 1.6, CLINIC_Z0 + 4.0, CLINIC_Z1 - 4.0, FLOOR_1,
                  label="Medicine")
        ceiling_light(CLINIC_X0 + 22.0, CLINIC_DOOR, CEIL_1)

# ---------------------------------------------------------------------------
# The bakery
# ---------------------------------------------------------------------------

with group("Bakery"):
    shell("BAKERY", BAKERY_X0, BAKERY_X1, BAKERY_Z0, BAKERY_Z1, BAKERY_DOOR, BAKERY_WALL,
          front="awning")

    with group("BakeryFittings"):
        # A counter along the east wall by the door, the oven bank against the
        # west wall, and a display shelf of stock between them.
        box("Counter", (BAKERY_X1 - 14.0, BAKERY_X1 - 4.0, BAKERY_DOOR - 8.0, BAKERY_DOOR + 2.0,
                        FLOOR_1, FLOOR_1 + 3.2), DESK_TOP, WOOD)
        box("Ovens", (BAKERY_X0, BAKERY_X0 + 3.0, BAKERY_Z0 + 3.0, BAKERY_Z1 - 3.0,
                      FLOOR_1, FLOOR_1 + 6.5), STEEL, METAL)
        shelf_run(BAKERY_X0 + 20.0, BAKERY_Z0 + 4.0, BAKERY_Z1 - 4.0, FLOOR_1, label="Display")
        ceiling_light(BAKERY_X0 + 22.0, BAKERY_DOOR, CEIL_1)

# ---------------------------------------------------------------------------
# The garage
# ---------------------------------------------------------------------------

with group("Garage"):
    shell("GARAGE", GARAGE_X0, GARAGE_X1, GARAGE_Z0, GARAGE_Z1, GARAGE_DOOR, GARAGE_WALL,
          front="garage")

    with group("GarageFittings"):
        # A car on a lift in the middle of the floor -- the one thing a garage
        # has to have -- with the workbench against the west wall.
        box("CarBody", (GARAGE_X1 - 20.0, GARAGE_X1 - 10.0, GARAGE_DOOR - 3.0, GARAGE_DOOR + 3.0,
                        FLOOR_1 + 2.4, FLOOR_1 + 4.6), (60, 64, 120), SMOOTH)
        for dx in (-4.0, 4.0):
            for dz in (-2.0, 2.0):
                box(f"Wheel{dx}_{dz}",
                    (GARAGE_X1 - 15.0 + dx - 0.7, GARAGE_X1 - 15.0 + dx + 0.7,
                     GARAGE_DOOR + dz - 0.7, GARAGE_DOOR + dz + 0.7,
                     FLOOR_1 + 1.0, FLOOR_1 + 2.2), (30, 30, 34), SMOOTH)
        box("Lift", (GARAGE_X1 - 15.0 - 2.4, GARAGE_X1 - 15.0 + 2.4,
                     GARAGE_DOOR - 4.4, GARAGE_DOOR + 4.4, FLOOR_1, FLOOR_1 + 0.8),
            STEEL, METAL)
        box("Workbench", (GARAGE_X0 + 2.0, GARAGE_X0 + 7.0, GARAGE_DOOR - 6.0, GARAGE_DOOR + 2.0,
                          FLOOR_1 + 2.4, FLOOR_1 + 2.8), DESK_TOP, WOOD)
        box("ToolChest", (GARAGE_X0 + 8.0, GARAGE_X0 + 10.0, GARAGE_DOOR - 5.0, GARAGE_DOOR - 1.0,
                          FLOOR_1, FLOOR_1 + 3.4), STEEL, METAL)
        ceiling_light(GARAGE_X0 + 24.0, GARAGE_DOOR, CEIL_1)

# ---------------------------------------------------------------------------
# The houses
# ---------------------------------------------------------------------------

def house(z0, z1, door_z, number):
    """A small west-facing house: path off the sidewalk, door in the west wall,
    two rooms either side of a cross partition."""
    ix0, ix1 = HOUSE_X0 + WALL, HOUSE_X1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    d0, d1 = door_z - DOORWAY / 2, door_z + DOORWAY / 2

    with group(f"House{number}"):
        # Starts at the back of the sidewalk, not at the kerb. The sidewalk is
        # already paved from the kerb to the property line -- by build_street.py
        # along the original street and by this file's own extensions past it --
        # so a path drawn from the kerb laid eleven studs of stone in the same
        # plane as eleven studs of paving, in two different files, and the two
        # flickered against each other outside every front door in town.
        box("Path", (NEAR_WALK_X1, HOUSE_X0, door_z - 2.2, door_z + 2.2,
                     PAVING - 0.5, PAVING), PATH_STONE, PEBBLE)

        with group("HouseStructure"):
            box("Slab", (HOUSE_X0, HOUSE_X1, z0, z1, FLOOR_1 - SLAB, FLOOR_1),
                FLOOR_INDOOR, MARBLE)
            box("Roof", (HOUSE_X0, HOUSE_X1, z0, z1, CEIL_1, CEIL_1 + SLAB), ROOF_GREY, SLATE)
            wall("WallWest", (HOUSE_X0, ix0, z0, z1, FLOOR_1, CEIL_1), HOUSE_WALL,
                 along="z", doors=((d0, d1),))
            wall("WallEast", (ix1, HOUSE_X1, z0, z1, FLOOR_1, CEIL_1), HOUSE_WALL, along="z")
            wall("WallSouth", (HOUSE_X0, HOUSE_X1, z0, iz0, FLOOR_1, CEIL_1), HOUSE_WALL, along="x")
            wall("WallNorth", (HOUSE_X0, HOUSE_X1, iz1, z1, FLOOR_1, CEIL_1), HOUSE_WALL, along="x")
            for i, (a, b) in enumerate(((iz0 + 3.0, iz0 + 7.0), (iz1 - 7.0, iz1 - 3.0))):
                glazing(f"Window{i + 1}",
                        (ix1 + 0.4, HOUSE_X1 - 0.4, a, b, FLOOR_1 + 3.0, FLOOR_1 + 7.0),
                        along="z", panes=2)
            box("Numberplate", (HOUSE_X0 - 0.6, HOUSE_X0 - 0.1, door_z - 1.5, door_z + 1.5,
                                FLOOR_1 + 8.0, FLOOR_1 + 9.5),
                TRIM_WHITE, SMOOTH,
                children=sign(number, "left", color=(60, 66, 84), size=48))

        with group("HouseFittings"):
            # The partition runs the depth of the house, so it is an along-z wall
            # and its door is a range in z -- the same axis as the front door it
            # lets the player walk straight through. Declared along-x here, the
            # door never overlaps the wall's thin extent and wall() fills the gap
            # with one box that reaches across the yard into the next building.
            wall("Partition", (ix0 + 6.0, ix0 + 7.0, iz0 + 4.0, iz1 - 4.0, FLOOR_1, CEIL_1),
                 PARTITION_PALE, PLASTIC, along="z", doors=((door_z - 3.0, door_z + 3.0),))
            box("Sofa", (ix0 + 11.0, ix0 + 15.0, iz1 - 9.0, iz1 - 5.0, FLOOR_1 + 1.2, FLOOR_1 + 2.0),
                (140, 96, 80), FABRIC)
            desk(ix0 + 18.0, door_z + 2.0, FLOOR_1, side="west", width=4.0, depth=2.2,
                 label="Table")
            box("Bed", (ix0 + 8.0, ix0 + 15.0, iz0 + 4.0, iz0 + 10.0, FLOOR_1 + 0.8, FLOOR_1 + 1.6),
                (214, 218, 224), FABRIC)
            ceiling_light(ix0 + 18.0, door_z, CEIL_1)


for z0, z1, door_z, number in HOUSES:
    house(z0, z1, door_z, number)


# ---------------------------------------------------------------------------
# The corner shop
# ---------------------------------------------------------------------------

# Seventeen studs of frontage and forty-one of depth, and the interior is laid
# out around that shape rather than in spite of it.
#
# The plan is a service spine and a customer floor. The north strip -- from the
# back wall to behind the counter -- is the only way to reach either the stock at
# the back or the till at the front, so working the shop is a lap of the building
# rather than a stand at one spot. The customer aisles hang south of that spine,
# between it and the glazed flank.
#
# That is a floor plan with an argument in it. `docs/activity_design_law.md`
# requires a consumable that forces traversal every 40-60 seconds; here the
# consumable is the stock on the shelves and the traversal is the length of the
# room. Putting the crates at the back and the till at the front is what makes
# the run exist at all -- a shop with its stock behind the counter would satisfy
# every other requirement and still be a game about standing still.
#
# Nothing here is tagged. The counter, the aisles and the crates are the stage
# for a verb that has not been agreed yet, and a tag no service reads is orphaned
# code by this tree's own rules. Tagging is a one-line change when the verb lands.
SHOP_IX0, SHOP_IX1 = SHOP_X0 + WALL, SHOP_X1 - WALL       # -40.5 .. 0.5
SHOP_IZ0, SHOP_IZ1 = SHOP_Z0 + WALL, SHOP_Z1 - WALL       #  66.3 .. 80.5
_SD0, _SD1 = SHOP_DOOR - DOORWAY / 2, SHOP_DOOR + DOORWAY / 2

# The spine, and the two things it connects. Written as bounds rather than as
# widths because every one of them has to be checked against the 2.8 studs a
# walking body needs -- read_house.py measures routes at a half-width of 1.40 --
# and a width that has to be added to a start to be checked is a width that gets
# checked wrong.
# Everything below is written as a depth from the shop's own south wall rather
# than as a world z. The first version was written in world coordinates, and when
# the building had to move off the gate road every fitting in it would have had
# to be retyped one at a time -- which is the way a shelf ends up standing in a
# wall. Depths move with the shop; world coordinates do not.
SHOP_SPINE_Z0 = SHOP_Z0 + 11.6  # north of this is the service strip, kept clear
SHOP_COUNTER_X0, SHOP_COUNTER_X1 = -30.0, -27.0
SHOP_CLERK_X1 = -24.0           # the standing room behind the counter
SHOP_BAY_X = -8.0               # the stock bay's rail, east of the aisles

with group("CornerShop"):
    # A paved forecourt rather than a house's narrow path: a shop's front is
    # somewhere people stand, and the width of it is the difference between a
    # door in a wall and a place. Starts at the back of the sidewalk for the same
    # reason the houses' paths do -- the ground from the kerb is already paved by
    # another file, and two slabs in one plane flicker.
    box("Forecourt", (NEAR_WALK_X1, SHOP_X0, SHOP_Z0 + 1.0, SHOP_Z1 - 1.0,
                      PAVING - 0.5, PAVING), PATH_STONE, PEBBLE)

    with group("ShopStructure"):
        box("Slab", (SHOP_X0, SHOP_X1, SHOP_Z0, SHOP_Z1, FLOOR_1 - SLAB, FLOOR_1),
            FLOOR_INDOOR, MARBLE)
        box("Roof", (SHOP_X0, SHOP_X1, SHOP_Z0, SHOP_Z1, CEIL_1, CEIL_1 + SLAB),
            ROOF_GREY, SLATE)

        # The whole street face is door and glass. Three openings that meet edge
        # to edge leave wall() with no solid span to draw, which is the point:
        # the piers between them are the two door posts below, at a shopfront's
        # thickness rather than a wall's. A player on the sidewalk can see the
        # counter, and seeing the counter is how they learn there is one.
        wall("WallWest", (SHOP_X0, SHOP_IX0, SHOP_Z0, SHOP_Z1, FLOOR_1, CEIL_1),
             SHOP_WALL, doors=((SHOP_IZ0, _SD0), (_SD0, _SD1), (_SD1, SHOP_IZ1)),
             along="z")
        for i, (a, b) in enumerate(((SHOP_IZ0, _SD0), (_SD1, SHOP_IZ1))):
            glazing(f"Shopfront{i + 1}",
                    (SHOP_X0 + 0.4, SHOP_IX0 - 0.4, a, b, FLOOR_1, FLOOR_1 + DOOR_HEIGHT),
                    along="z", panes=1)
        for i, zz in enumerate((_SD0, _SD1)):
            box(f"DoorPost{i + 1}", (SHOP_X0, SHOP_IX0, zz - 0.35, zz + 0.35,
                                     FLOOR_1, FLOOR_1 + DOOR_HEIGHT), SHOP_FASCIA, METAL)

        wall("WallEast", (SHOP_IX1, SHOP_X1, SHOP_Z0, SHOP_Z1, FLOOR_1, CEIL_1),
             SHOP_WALL, along="z")

        # The long window goes on the south flank because that is the side the
        # customer floor is on -- the aisles, the chiller and the till are all
        # south of the service spine, so this is the only flank with anything
        # behind it worth seeing. The north flank backs onto the spine and stays
        # solid; a window onto a staff corridor is a window into nothing.
        #
        # It used to be here for a different and now false reason: the shop stood
        # north of the player's plot and this face looked at their front gate.
        # The building moved and the face did not, which is how a comment outlives
        # the thing it describes. Sill at three studs so the shelving inside reads
        # over it rather than behind it.
        wall("WallSouth", (SHOP_X0, SHOP_X1, SHOP_Z0, SHOP_IZ0, FLOOR_1, CEIL_1),
             SHOP_WALL, along="x", doors=((-34.0, -14.0),))
        box("FlankSill", (-34.0, -14.0, SHOP_Z0, SHOP_IZ0, FLOOR_1, FLOOR_1 + 3.0),
            SHOP_WALL, BRICK)
        glazing("FlankWindow",
                (-34.0, -14.0, SHOP_Z0 + 0.4, SHOP_IZ0 - 0.4,
                 FLOOR_1 + 3.0, FLOOR_1 + DOOR_HEIGHT), along="x", panes=5)

        wall("WallNorth", (SHOP_X0, SHOP_X1, SHOP_IZ1, SHOP_Z1, FLOOR_1, CEIL_1),
             SHOP_WALL, along="x")

        # The fascia wraps the west face and the north one. West because that is
        # the shopfront; north because the player lives at the top of this street
        # and every walk here is a walk south, so the north flank is the face they
        # see from a hundred studs off and the one that has to say what this is.
        # The south return is not signed -- it faces the empty end of the street.
        box("FasciaWest", (SHOP_X0 - 0.5, SHOP_X0, SHOP_Z0, SHOP_Z1,
                           FLOOR_1 + DOOR_HEIGHT, CEIL_1), SHOP_FASCIA, SMOOTH,
            children=sign("CORNER SHOP", "left", color=(244, 240, 228), size=64))
        box("FasciaNorth", (SHOP_X0, -10.0, SHOP_Z1, SHOP_Z1 + 0.5,
                            FLOOR_1 + DOOR_HEIGHT, CEIL_1), SHOP_FASCIA, SMOOTH,
            children=sign("CORNER SHOP", "back", color=(244, 240, 228), size=64))

    with group("ShopFittings"):
        # Mat inside the door: the only thing in the entry bay, because the entry
        # bay is where a queue stands and anything in it is something a customer
        # would have to path around.
        box("Mat", (SHOP_IX0, SHOP_IX0 + 4.0, _SD0, _SD1, FLOOR_1, FLOOR_1 + 0.08),
            (72, 78, 74), FABRIC, collide=False)

        # The counter stops short of the spine rather than reaching the north
        # wall. That gap is the only way behind it, and it is deliberate: the way
        # round is a distance, and a distance is what makes leaving the till a
        # decision instead of a keystroke.
        box("CounterBase", (SHOP_COUNTER_X0, SHOP_COUNTER_X1, SHOP_IZ0 + 1.2,
                            SHOP_SPINE_Z0, FLOOR_1, FLOOR_1 + 3.2), DESK_TOP, WOOD)
        # The top overhangs on the customer side only. A 0.4 lip on the staff side
        # as well left 2.6 studs of standing room behind the counter at chest
        # height -- under the 2.8 a walking body needs, and invisible from the
        # floor plan because the base underneath it is 3.0 clear. A capsule does
        # not duck.
        box("CounterTop", (SHOP_COUNTER_X0 - 0.4, SHOP_COUNTER_X1, SHOP_IZ0 + 0.8,
                           SHOP_SPINE_Z0 + 0.4, FLOOR_1 + 3.2, FLOOR_1 + 3.5),
            (208, 180, 140), WOOD)
        box("Till", (SHOP_COUNTER_X0 + 0.3, SHOP_COUNTER_X1 - 0.3, SHOP_SPINE_Z0 - 3.4,
                     SHOP_SPINE_Z0 - 1.0, FLOOR_1 + 3.5, FLOOR_1 + 4.6), STEEL, METAL)
        box("BagStack", (SHOP_COUNTER_X0 + 0.6, SHOP_COUNTER_X1 - 0.6, SHOP_IZ0 + 2.0,
                         SHOP_IZ0 + 4.0, FLOOR_1 + 3.5, FLOOR_1 + 4.0), STOCK, PLANKS,
            collide=False)
        # Nothing stands in the three studs behind the counter. That strip is the
        # clerk's own room and it is barely over the 2.8 a walking body needs, so
        # a shelf against the back of the counter would be a wall with a job
        # title -- the first thing to trap a player who is meant to be running.

        # Two runs and a chiller, all south of the spine. The south aisle lines up
        # with the front door so a player walking straight in is in an aisle, not
        # facing the end of a gondola.
        aisle_run(SHOP_Z0 + 3.2, SHOP_CLERK_X1 + 1.0, -16.0, FLOOR_1,
                  label="AisleSouth")
        aisle_run(SHOP_Z0 + 10.0, SHOP_CLERK_X1 + 1.0, SHOP_BAY_X - 1.0, FLOOR_1,
                  label="AisleCentre")
        # End-stops the south run rather than standing beside it: the chiller is
        # the tall thing you see through the flank window, and it is the far end
        # of the shortest errand a customer can send you on.
        box("Chiller", (-15.0, SHOP_BAY_X - 1.0, SHOP_IZ0, SHOP_IZ0 + 2.6,
                        FLOOR_1, FLOOR_1 + 9.0), CHILLER_FRAME, METAL)
        box("ChillerGlass", (-14.6, SHOP_BAY_X - 1.4, SHOP_IZ0 - 0.1, SHOP_IZ0 + 0.3,
                             FLOOR_1 + 1.2, FLOOR_1 + 8.0), GLAZING, GLASS,
            transparency=0.45, collide=False)

        # The stock bay, walled off from the customer floor by a waist-high rail
        # so it reads as staff-only without becoming a room the player has to
        # find a door into. Reached along the spine, like the counter.
        box("BayRail", (SHOP_BAY_X, SHOP_BAY_X + 0.4, SHOP_IZ0, SHOP_SPINE_Z0,
                        FLOOR_1, FLOOR_1 + 3.5), STEEL, METAL)
        # Two columns of four-stud crates, edge to edge, all of them south of the
        # spine. Nothing is stacked in the spine itself -- the run along the north
        # wall is the one corridor that has to stay walkable, and a crate in it is
        # the difference between a shop and a maze.
        for i, (cx, cd) in enumerate(((-5.5, 3.7), (-5.5, 7.7),
                                      (-1.5, 5.2), (-1.5, 9.2))):
            cz = SHOP_Z0 + cd
            box(f"Crate{i + 1}", (cx - 2.0, cx + 2.0, cz - 2.0, cz + 2.0,
                                  FLOOR_1, FLOOR_1 + 4.0), CRATE, WOOD)
        box("CrateTop", (-7.5, -3.5, SHOP_Z0 + 3.7, SHOP_Z0 + 7.7,
                         FLOOR_1 + 4.0, FLOOR_1 + 8.0), CRATE, WOOD)

        for lx, ld in ((-35.0, None), (-28.0, 13.2), (-17.0, 5.2),
                       (-17.0, 13.2), (-4.0, 8.2)):
            ceiling_light(lx, SHOP_DOOR if ld is None else SHOP_Z0 + ld, CEIL_1)

# ---------------------------------------------------------------------------
# The park
# ---------------------------------------------------------------------------

with group("Park"):
    # A pond with a stone rim, two crossing paths, benches and a picnic table,
    # and trees ringing the edges. Open on purpose: nothing here is fenced, so
    # the player can cut across the grass to the road whenever they want.
    box("Pond", (PARK_X0 + 6.0, PARK_X0 + 22.0, PARK_Z0 + 6.0, PARK_Z0 + 18.0,
                 GROUND - 0.6, GROUND), (92, 128, 152), SMOOTH)
    box("PondRim", (PARK_X0 + 5.2, PARK_X0 + 22.8, PARK_Z0 + 5.2, PARK_Z0 + 18.8,
                    GROUND, GROUND + 0.3), (150, 150, 150), CONCRETE, collide=False)
    box("PathA", (PARK_X0 + 18.0, PARK_X1 - 8.0, PARK_Z0 + 12.0, PARK_Z0 + 17.0,
                  GROUND, GROUND + 0.5), PAVING_GREY, PEBBLE)
    box("PathB", (PARK_X0 + 10.0, PARK_X0 + 15.0, PARK_Z0 + 4.0, PARK_Z1 - 6.0,
                  GROUND, GROUND + 0.5), PAVING_GREY, PEBBLE)

    for x, z in (
        (PARK_X0 + 3.0, PARK_Z1 - 3.0),
        (PARK_X1 - 3.0, PARK_Z1 - 3.0),
        (PARK_X1 - 3.0, PARK_Z0 + 3.0),
        (PARK_X0 + 32.0, PARK_Z0 + 3.0),
        (PARK_X0 + 3.0, PARK_Z0 + 26.0),
        (PARK_X1 - 3.0, PARK_Z0 + 40.0),
    ):
        tree(x, z, GROUND, height=14.0, spread=9.0)

    bench(PARK_X0 + 26.0, PARK_Z0 + 24.0, GROUND, side="north")
    bench(PARK_X1 - 26.0, PARK_Z1 - 24.0, GROUND, side="south")
    box("PicnicTable", (PARK_X0 + 30.0, PARK_X1 - 28.0, PARK_Z1 - 14.0, PARK_Z1 - 8.0,
                        GROUND + 2.0, GROUND + 2.4), DESK_TOP, WOOD)
    for dx in (-6.0, 6.0):
        box(f"PicnicSeat{dx}",
            (PARK_X0 + 30.0 + dx - 2.0, PARK_X0 + 30.0 + dx + 2.0,
             PARK_Z1 - 15.0, PARK_Z1 - 7.0, GROUND + 1.2, GROUND + 1.6), DESK_TOP, WOOD)

# ---------------------------------------------------------------------------
# Street furniture
# ---------------------------------------------------------------------------

with group("StreetFurniture"):
    # Lamps where the new sidewalks start, and a couple along them so the north
    # and south ends of town are lit the way the original street is.
    for z in (84.0, 128.0, 172.0, 216.0):
        street_lamp(FAR_WALK_X1 - 2.0, z, 1)
        street_lamp(NEAR_WALK_X0 + 2.0, z, -1)
    for z in (-100.0, -145.0, -190.0, -208.0, -250.0, -275.0):
        street_lamp(FAR_WALK_X1 - 2.0, z, 1)
        street_lamp(NEAR_WALK_X0 + 2.0, z, -1)
    for z in (-150.0, -195.0, -240.0, -280.0):
        street_lamp(RETURN_X1 + 3.5, z, -1)

    # Trees filling the grass between buildings, so the town has a street to
    # itself rather than a row of boxes.
    # The south meadow gets a few trees so the loop's far side reads as grass
    # rather than as a void; the frontages along the loop stay clear for the
    # buildings that will one day front them.
    # The row up the west verge starts at z=160, not z=88: build_street.py
    # already plants one at (-104, 88) as the last of its own row, and the two
    # were landing in exactly the same square from two different files -- one
    # trunk inside another, in two assets neither of which could see the other.
    for x, z in ((-104.0, 160.0), (-104.0, 220.0),
                 (-130.0, -120.0), (-130.0, -164.0), (-140.0, -214.0),
                 (-220.0, -50.0), (-220.0, 50.0), (-220.0, 150.0),
                 (-220.0, 200.0), (-215.0, -320.0), (-150.0, -320.0),
                 (-100.0, -320.0)):
        tree(x, z, GROUND)

# ---------------------------------------------------------------------------
# Place points
# ---------------------------------------------------------------------------

with group("PlacePoints"):
    for pid, x, z, floor, label in PLACE_POINTS:
        place_point(pid, x, z, floor, label)

print(rbxmx.write(TOWN, "Town"))
