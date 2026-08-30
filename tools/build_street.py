#!/usr/bin/env python3
"""Generates assets/Street.rbxmx: the road outside the house, the school, the store.

Run from tools/:  python3 build_street.py

Same relationship to world_plan.py that build_furniture.py has to house_plan.py --
the plan holds the numbers and the argument for them, this file turns them into
parts. Nothing here should be inventing a coordinate. If a wall is somewhere
surprising, the surprise belongs in world_plan.py where somebody reading the
design will find it, not buried in the middle of a loop.

Blocky on purpose. The house is a 1,082-part imported model that no generator is
going to match, and pretending otherwise would produce a worse street than
admitting it: what this builds is honest massing at the right scale, with the
doors, floors and sightlines all measured, so an imported school can be dropped
on top of it later without a single route changing. That is the same bet the
placeholder dog is running and it has held up so far.

What it does NOT contain is anything about jobs. A building is a place; a shift
is a rule. The clock-in point in the store is a tagged part with a name on it and
nothing else, and Part 2 is what gives it meaning.
"""

import rbxmx
from rbxmx import (
    ASPHALT, BRICK, CONCRETE, FABRIC, GLASS, GRASS, LEAFY_GRASS, MARBLE,
    METAL, NEON, PEBBLE, PLASTIC, PLANKS, SLATE, SMOOTH, WOOD,
)
from rbxmx import at, box, group, part, point_light, sign

import world_plan as W
from world_plan import (
    BACK_GATE_Z0, BACK_GATE_Z1,
    CEIL_1, CEIL_2, clear_of_paving, CROSSING_Z0, CROSSING_Z1, DOOR_LINE, DOORWAY,
    FAR_WALK_X0, FAR_WALK_X1, FENCE_HALF, FENCE_HEIGHT, FENCE_X, FENCE_Z0,
    FENCE_Z1, FLOOR_1, FLOOR_2, FORECOURT_X0, FRONT_X, GATE_HALF, GROUND,
    INNER_DOORWAY, NEAR_WALK_X0, NEAR_WALK_X1, PARTITION, PATH_HALF, PATH_TOP,
    PATH_X0, PATH_X1, PAVING, PLACE_ID_ATTRIBUTE, PLACE_LABEL_ATTRIBUTE,
    PLACE_POINTS, PLACE_TAG, PLOT_SEAL_Z1, PLOT_X1, ROUTE_RADIUS,
    PROPERTY_X, ROAD_MID, ROAD_X0, ROAD_X1, SCHOOL_DOOR, SCHOOL_X0,
    SCHOOL_X1, SCHOOL_Z0, SCHOOL_Z1, SLAB, STAIR_GOING, STAIR_RISE,
    STAIR_STEPS, STAIR_X0, STAIR_X1, STAIR_Z0, STAIR_Z1, STREET, STREET_Z0,
    STREET_Z1, TRUNK_WIDTH, WALL, WORK_DOOR, WORK_X0, WORK_X1, WORK_Z0, WORK_Z1,
)

rbxmx.begin("RBXSTREET")

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------

# Cosmetic, so it lives here and not in Config, on the rule the rest of the
# codebase already follows: nobody balances this game by changing the color of a
# kerb. Kept dull on purpose. The house is the saturated thing in this world and
# a street that competes with it turns the front door into just another doorway.
LAWN = (106, 142, 84)
VERGE = (96, 130, 78)
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

FLOOR_INDOOR = (198, 192, 180)
FLOOR_SHOP = (208, 206, 200)
PARTITION_PALE = (216, 212, 204)

BARK = (94, 74, 58)
LEAF = (78, 118, 62)

FITTING = (238, 236, 228)
LAMP_LIGHT = (255, 236, 196)
INDOOR_LIGHT = (255, 248, 232)

DESK_TOP = (196, 166, 126)
DESK_LEG = (110, 112, 116)
SEAT = (72, 96, 132)
BOARD = (232, 234, 230)
SHELF = (146, 148, 152)
STOCK = (176, 142, 96)

# How tall a door opening is, measured up from the floor it stands on. Nine
# studs over a five-and-a-half stud character is more than a real building would
# give, and deliberately: these are openings a player runs at without slowing
# down, and a head that clips a lintel reads as the door being closed.
DOOR_HEIGHT = 9.0

# How wide the painted line down the middle of the road is, how long a dash runs
# and how long the gap after it is. Together they are the only thing telling the
# player which way traffic would go, so the dash is long enough to read at a walk.
CENTRE_WIDTH = 0.6
DASH_LENGTH = 6.0
DASH_GAP = 6.0
# Zebra bars: as wide as the road, repeated along it.
STRIPE_WIDTH = 1.2
STRIPE_GAP = 1.2
# Paint sits a hair above the surface it is painted on, because two boxes whose
# top faces share a height flicker against each other from a distance.
PAINT_LIFT = 0.02
PAINT_THICK = 0.12

# The kerb is a strip of its own along the road edge of each sidewalk rather than
# the side face of the paving, so the line where the pavement stops is visible
# from the far side of the road.
KERB_WIDTH = 0.8
# How far the paving is sunk into the ground beneath it. Enough that no seam
# shows on a slope; the tops are what matter.
SLAB_SINK = 0.6

# ---------------------------------------------------------------------------
# Wall helper
# ---------------------------------------------------------------------------


def wall(name, bounds, color, material=BRICK, doors=(), head=DOOR_HEIGHT,
         along="z", collide=True):
    """A wall as one box, minus its doorways, plus a lintel over each.

    Doorways are given as ranges on the `along` axis rather than as parts to
    subtract, because that is how they are argued about: a door is somewhere
    along a wall and so wide. Emitting the wall in pieces means the hole is a
    real hole -- there is no invisible part left standing in the opening for the
    player to walk into, which is exactly the failure that made the house's own
    front door measure as sealed.
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
    """A run of window, as one non-colliding pane per bay.

    CanCollide false and it matters: the pane in the house's own front door is
    exactly this, and a checker that does not read the property calls the
    doorway sealed. Everything here that a player can see through is also
    something they can walk through, so the geometry that stops them is always
    the wall beside it and never the glass.
    """
    x0, x1, z0, z1, y0, y1 = bounds
    lo, hi = (z0, z1) if along == "z" else (x0, x1)
    step = (hi - lo) / panes
    for i in range(panes):
        a, b = lo + i * step + 0.3, lo + (i + 1) * step - 0.3
        piece_bounds = (x0, x1, a, b, y0, y1) if along == "z" else (a, b, z0, z1, y0, y1)
        box(f"{name}{i + 1}", piece_bounds, GLAZING, GLASS,
            transparency=0.55, collide=False)


# ---------------------------------------------------------------------------
# The ground
# ---------------------------------------------------------------------------

# Everything from behind the buildings to the property line. Two bands rather
# than one slab, with the road filling the gap between them: a grass box and a
# road box that shared a top height would z-fight down the whole length of the
# street, and the cheapest fix is to not overlap them.
GROUND_X0 = SCHOOL_X0 - 24.0
GROUND_BOTTOM = -1.0

with group("Ground"):
    box("GrassWest", (GROUND_X0, ROAD_X0, STREET_Z0, STREET_Z1, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)
    box("GrassEast", (ROAD_X1, PROPERTY_X, STREET_Z0, STREET_Z1, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)

with group("Road"):
    box("Carriageway", (ROAD_X0, ROAD_X1, STREET_Z0, STREET_Z1, GROUND_BOTTOM, GROUND),
        TARMAC, ASPHALT)

    # Centre line, skipped where the crossing is. A dash painted through a zebra
    # is the one road marking a player would actually notice being wrong.
    z = STREET_Z0 + DASH_GAP
    i = 0
    while z + DASH_LENGTH < STREET_Z1:
        if not (z < CROSSING_Z1 + 2.0 and z + DASH_LENGTH > CROSSING_Z0 - 2.0):
            i += 1
            box(f"Dash{i}",
                (ROAD_MID - CENTRE_WIDTH / 2, ROAD_MID + CENTRE_WIDTH / 2,
                 z, z + DASH_LENGTH,
                 GROUND + PAINT_LIFT - PAINT_THICK, GROUND + PAINT_LIFT),
                ROAD_PAINT, SMOOTH)
        z += DASH_LENGTH + DASH_GAP

with group("Crossing"):
    # Bars across the road, on the door line. Standing in the doorway of the
    # house and looking west, this is the thing that says the road is crossable
    # here -- which is the whole reason the crossing is on the door line and not
    # wherever was convenient.
    pitch = STRIPE_WIDTH + STRIPE_GAP
    count = int((CROSSING_Z1 - CROSSING_Z0) // pitch)
    for i in range(count):
        z0 = CROSSING_Z0 + i * pitch + STRIPE_GAP / 2
        box(f"Stripe{i + 1}",
            (ROAD_X0 + 1.0, ROAD_X1 - 1.0, z0, z0 + STRIPE_WIDTH,
             GROUND + PAINT_LIFT - PAINT_THICK, GROUND + PAINT_LIFT),
            ROAD_PAINT, SMOOTH)

with group("Sidewalks"):
    box("NearKerb", (NEAR_WALK_X0, NEAR_WALK_X0 + KERB_WIDTH, STREET_Z0, STREET_Z1,
                     GROUND - SLAB_SINK, PAVING), KERB_GREY, CONCRETE)
    box("NearPaving", (NEAR_WALK_X0 + KERB_WIDTH, NEAR_WALK_X1, STREET_Z0, STREET_Z1,
                       GROUND - SLAB_SINK, PAVING), PAVING_GREY, PEBBLE)
    box("FarKerb", (FAR_WALK_X1 - KERB_WIDTH, FAR_WALK_X1, STREET_Z0, STREET_Z1,
                    GROUND - SLAB_SINK, PAVING), KERB_GREY, CONCRETE)
    box("FarPaving", (FAR_WALK_X0, FAR_WALK_X1 - KERB_WIDTH, STREET_Z0, STREET_Z1,
                      GROUND - SLAB_SINK, PAVING), PAVING_GREY, PEBBLE)

    # A ramp down to the road at each end of the crossing, so the kerb is not a
    # step the player has to climb on the one line they are meant to walk.
    for name, kx0, kx1 in (
        ("NearRamp", NEAR_WALK_X0, NEAR_WALK_X0 + KERB_WIDTH),
        ("FarRamp", FAR_WALK_X1 - KERB_WIDTH, FAR_WALK_X1),
    ):
        box(name, (kx0, kx1, CROSSING_Z0, CROSSING_Z1, GROUND - SLAB_SINK, GROUND),
            KERB_GREY, CONCRETE)

with group("Forecourts"):
    # The apron each building stands on, running from its front wall out to the
    # far sidewalk. Same height as the paving and the ground floors, so the walk
    # from the crossing to a desk inside is flat the whole way.
    box("SchoolForecourt",
        (FORECOURT_X0, FAR_WALK_X0, SCHOOL_Z0, SCHOOL_Z1, GROUND - SLAB_SINK, PAVING),
        PAVING_GREY, PEBBLE)
    box("WorkForecourt",
        (FORECOURT_X0, FAR_WALK_X0, WORK_Z0, WORK_Z1, GROUND - SLAB_SINK, PAVING),
        PAVING_GREY, PEBBLE)

# ---------------------------------------------------------------------------
# The front garden
# ---------------------------------------------------------------------------

with group("FrontPath"):
    # Laid on the door line, which is measured and not chosen -- see world_plan.
    # A path that arrives at the wall beside the door is worse than no path,
    # because it tells the player the wrong thing with total confidence.
    #
    # Its surface is a hundredth under PATH_TOP rather than on it. The house is
    # imported art and carries its own doorstep -- a 0.15-stud slab over
    # x -2.1..1.3, z -5.5..0.7 -- whose top is at PATH_TOP exactly, so a path
    # laid to the same height fought it across six studs directly outside the
    # front door: the most-looked-at square of ground in the game. A hundredth
    # is under the place-point float tolerance, so "home" still reads as
    # standing on it, and it puts the doorstep proud of the path, which is what
    # a doorstep is.
    box("Path", (PATH_X0, PATH_X1, DOOR_LINE - PATH_HALF, DOOR_LINE + PATH_HALF,
                 PATH_TOP - 0.6, PATH_TOP - 0.01), PATH_STONE, PEBBLE)


def check_plot_boundary():
    """Re-measure the three sides of the plot this file does not build.

    PLOT_X1 and PLOT_SEAL_Z1 describe House.rbxmx, and nothing else in this
    generator opens House.rbxmx -- it is a 1,082-part imported model that gets
    dropped in whole. So they are two numbers copied out of an asset, which is
    this tree's oldest way of shipping a bug: the asset moves, the copy does
    not, and the only symptom is a gap in a fence that nobody walks into for a
    month. Re-reading the model costs a tenth of a second.

    The north side is checked too even though this file does not touch it,
    because the *reason* it is not built here is that House.rbxmx already
    closes it. That is an assumption, not an observation, until it is probed.
    """
    import read_house

    parts = read_house.load(str(W.STREET.parent / "House.rbxmx"))
    walls = [q for q in parts if q["y0"] < 3.0 < q["y1"]]
    floors = [q for q in parts if q["y1"] <= 2.0]

    def blocked(x, z):
        return any(q["x0"] <= x <= q["x1"] and q["z0"] <= z <= q["z1"]
                   for q in walls)

    east = max(q["x1"] for q in floors if q["z0"] < FENCE_Z0 + 1.0)
    assert abs(east - PLOT_X1) < 0.1, (
        f"the plot's ground now ends at x {east:.2f}, not PLOT_X1 {PLOT_X1}. "
        f"The south fence is drawn to PLOT_X1 - FENCE_HALF and the return "
        f"stands on it, so both are now {'short of' if east > PLOT_X1 else 'past'} "
        f"the edge. Update PLOT_X1 in world_plan.py.")

    seal = next(z / 10 for z in range(int(FENCE_Z0 * 10), 0)
                if blocked(PLOT_X1 - FENCE_HALF, z / 10))
    assert abs(seal - PLOT_SEAL_Z1) < 0.3, (
        f"the house's east wall now starts at z {seal:.2f}, not PLOT_SEAL_Z1 "
        f"{PLOT_SEAL_Z1}. The return run stops at PLOT_SEAL_Z1, so the "
        f"boundary now has a {abs(seal - PLOT_SEAL_Z1):.1f}-stud "
        f"{'gap' if seal > PLOT_SEAL_Z1 else 'overlap'} in it. Update "
        f"PLOT_SEAL_Z1 in world_plan.py.")

    # A hole is only a hole if a body fits through it. The north side is a
    # picket fence, so it is mostly gaps -- six-tenths of a stud between every
    # pair of pickets -- and a probe that reports any unblocked sample reports
    # the whole run as open, which is what the first version of this did.
    gaps, start = [], None
    for step in range(int(PROPERTY_X * 4), int(PLOT_X1 * 4) + 1):
        if blocked(step / 4, FENCE_Z1):
            if start is not None:
                gaps.append((start, step / 4))
                start = None
        elif start is None:
            start = step / 4
    if start is not None:
        gaps.append((start, PLOT_X1))
    gaps = [g for g in gaps if g[1] - g[0] >= 2 * ROUTE_RADIUS]
    assert not gaps, (
        f"House.rbxmx no longer closes the plot's north side at z {FENCE_Z1}: a "
        f"body fits through x " + ", ".join(f"{a:.1f}..{b:.1f}" for a, b in gaps)
        + ". That side is unbuilt *because* the asset's own picket fence and "
        f"north wall cover it. They no longer do, so a fourth run has to be "
        f"added below.")


check_plot_boundary()


def fence_run(a0, a1, index, axis="z", line=FENCE_X):
    """Rails and posts between two points on a boundary line.

    `axis` is the direction the run travels; `line` is the fixed coordinate on
    the other one. The street frontage runs north-south, which is why that is
    the default, but the south boundary runs east-west and is the same fence.
    """
    lo, hi = line - FENCE_HALF, line + FENCE_HALF

    def across(b0, b1, out=0.0):
        """(x0, x1, z0, z1) for a piece spanning b0..b1 along `axis`."""
        if axis == "z":
            return (lo - out, hi + out, b0, b1)
        return (b0, b1, lo - out, hi + out)

    top = 1.04 + FENCE_HEIGHT
    box(f"RailTop{index}", across(a0, a1) + (top - 0.4, top), TRIM_WHITE, WOOD)
    box(f"RailLow{index}", across(a0, a1) + (top - 2.0, top - 1.6),
        TRIM_WHITE, WOOD)
    span = a1 - a0
    posts = max(2, int(span // 5.5) + 1)
    for i in range(posts):
        a = a0 + span * i / (posts - 1)
        a = min(max(a, a0 + 0.3), a1 - 0.3)
        box(f"Post{index}_{i + 1}", across(a - 0.3, a + 0.3, 0.2)
            + (1.04, top + 0.3), TRIM_WHITE, WOOD)


def gate_posts(line, z0, z1, tag):
    """The pair of capped posts either side of a gap in a north-south fence.

    Both gates in this plot are gaps in a run travelling along z, so both get
    the same posts on the same construction -- which is the point: a player who
    has learned what the front gate looks like should recognise the back one as
    a gate without being told.
    """
    for i, z in enumerate((z0, z1)):
        box(f"{tag}Post{i + 1}",
            (line - 0.55, line + 0.55, z - 0.55, z + 0.55, 1.04, 1.04 + 4.6),
            TRIM_WHITE, WOOD)
        box(f"{tag}Cap{i + 1}",
            (line - 0.85, line + 0.85, z - 0.85, z + 0.85,
             1.04 + 4.6, 1.04 + 5.1), TRIM_WHITE, WOOD)


with group("Fence"):
    fence_run(FENCE_Z0, DOOR_LINE - GATE_HALF, 1)
    fence_run(DOOR_LINE + GATE_HALF, FENCE_Z1, 2)
    # The south boundary, and the return north up to the house's own east wall.
    # The return is the plot's frontage onto the green, so it takes a gate in
    # the middle of it -- see BACK_GATE_Z0/Z1 in world_plan. The south
    # boundary keeps none: it faces the gate road's verge, which is grass, and
    # a gate onto grass is a hole with nothing on the other side.
    fence_run(FENCE_X, PLOT_X1 - FENCE_HALF, 3, axis="x", line=FENCE_Z0)
    back_line = PLOT_X1 - FENCE_HALF
    fence_run(FENCE_Z0, BACK_GATE_Z0, 4, line=back_line)
    fence_run(BACK_GATE_Z1, PLOT_SEAL_Z1, 5, line=back_line)
    gate_posts(FENCE_X, DOOR_LINE - GATE_HALF, DOOR_LINE + GATE_HALF, "Gate")
    gate_posts(back_line, BACK_GATE_Z0, BACK_GATE_Z1, "BackGate")


def tree(x, z, floor, height=15.0, spread=10.0, label="Tree"):
    """Trunk you can walk into, canopy you cannot.

    The foliage is CanCollide false because it hangs at head height and a player
    is going to brush it. A tree that stops you dead two studs from its trunk is
    the single most obvious tell that a world was built out of boxes.
    """
    with group(label):
        with at(x, z, floor=floor):
            part("Trunk", (0, 0, 0), (TRUNK_WIDTH, height * 0.62, TRUNK_WIDTH),
                 BARK, WOOD)
            part("Canopy", (0, height * 0.5, 0), (spread, spread * 0.72, spread),
                 LEAF, LEAFY_GRASS, collide=False)
            part("CanopyTop", (0, height * 0.5 + spread * 0.5, 0),
                 (spread * 0.66, spread * 0.5, spread * 0.66),
                 LEAF, LEAFY_GRASS, collide=False)


def street_lamp(x, z, toward, label="StreetLamp"):
    """A pole on the sidewalk with its arm reaching `toward` (+1 east, -1 west)."""
    with group(label):
        with at(x, z, floor=PAVING):
            part("Base", (0, 0, 0), (1.4, 0.5, 1.4), STEEL, METAL)
            part("Pole", (0, 0.5, 0), (0.5, 12.0, 0.5), STEEL, METAL)
            part("Arm", (toward * 1.4, 12.0, 0), (3.2, 0.4, 0.4), STEEL, METAL)
            part("Head", (toward * 2.9, 11.4, 0), (1.6, 0.7, 1.0),
                 FITTING, NEON, children=point_light(LAMP_LIGHT, 1.6, 26.0))


def bench(x, z, floor, side="north", label="Bench"):
    with group(label):
        with at(x, z, side=side, floor=floor):
            part("Seat", (0, 1.5, 0.9), (6.0, 0.35, 2.0), DESK_TOP, WOOD)
            part("Back", (0, 1.85, 0.1), (6.0, 1.8, 0.3), DESK_TOP, WOOD)
            for dx in (-2.5, 2.5):
                part("Leg", (dx, 0, 0.9), (0.35, 1.5, 1.8), STEEL, METAL)


with group("StreetFurniture"):
    for z in range(-80, 81, 32):
        street_lamp(NEAR_WALK_X0 + 2.0, float(z), -1)
        street_lamp(FAR_WALK_X1 - 2.0, float(z), 1)

    # Trees only where there is grass to stand them in: the two gaps between the
    # buildings' forecourts, and the lawn of the player's own garden.
    #
    # Those gaps are also the only way through the west frontage, and gen_town.py
    # now cuts an alley down every one of them wide enough to take one -- so the
    # grass a tree wants and the paving a path wants are the same strip, claimed
    # from two files that cannot see each other's assets. Where both want it the
    # path wins, and the tree that loses is dropped by measurement rather than by
    # deleting a line here: this file has already had one tree land inside a tree
    # gen_town.py planted, and the fix for that was the same fix -- ask the shared
    # plan instead of keeping a second copy of the answer.
    # `clear_of_paving` and not `clear_of_alleys`: the alley question was the
    # only one asked here, and the tree at (-104, -86) passed it while standing
    # six studs inside the clinic's forecourt. Asking one question about paving
    # rather than one question per kind of paving is the difference -- a call
    # site that enumerates hazards only ever knows about the hazards that have
    # already been paid for.
    TREE_SPREAD = 10.0
    for x, z in ((-104.0, -16.0), (-104.0, 6.0), (-104.0, 88.0), (-104.0, -86.0)):
        if not clear_of_paving(x, z, TRUNK_WIDTH):
            continue
        tree(x, z, GROUND, spread=TREE_SPREAD)
    for x, z in ((-20.0, -22.0), (-34.0, 14.0), (-13.0, 20.0), (-40.0, -34.0)):
        tree(x, z, 1.04, height=13.0, spread=9.0)

    bench(FAR_WALK_X0 + 3.0, SCHOOL_DOOR - 10.0, PAVING, side="east")
    bench(FAR_WALK_X0 + 3.0, WORK_DOOR + 10.0, PAVING, side="east")
    bench(NEAR_WALK_X1 - 3.0, DOOR_LINE + 20.0, PAVING, side="west")

with group("StreetSign"):
    # A name on the road, so the place the player leaves from is a place and not
    # a location. It stands on the near sidewalk by the gate, facing the house.
    with at(NEAR_WALK_X0 + 2.0, DOOR_LINE - 11.0, floor=PAVING):
        part("Post", (0, 0, 0), (0.4, 9.0, 0.4), STEEL, METAL)
        part("Plate", (0, 8.0, 0), (0.3, 1.8, 9.0), TRIM_WHITE, SMOOTH,
             children=sign("PARKSIDE ROAD", "left", color=(46, 62, 96), size=64))

# ---------------------------------------------------------------------------
# The school
# ---------------------------------------------------------------------------

# Everything below is read straight off world_plan's rooms. Inner faces first, so
# a wall that moves in the plan moves here and nowhere else.
SCH_IN_X0, SCH_IN_X1 = SCHOOL_X0 + WALL, SCHOOL_X1 - WALL   # -150.5 .. -113.5
SCH_IN_Z0, SCH_IN_Z1 = SCHOOL_Z0 + WALL, SCHOOL_Z1 - WALL   # 11.5 .. 74.5
SCH_DOOR_Z0, SCH_DOOR_Z1 = SCHOOL_DOOR - DOORWAY / 2, SCHOOL_DOOR + DOORWAY / 2

# The corridor's two walls, and the classroom cross-walls behind the west one.
HALL_E_X0, HALL_E_X1 = -131.0, -130.0
HALL_W_X0, HALL_W_X1 = -139.0, -138.0
CLASS_SPLIT_1 = 32.0
CLASS_SPLIT_2 = 53.0

# ---------------------------------------------------------------------------
# The school -- removed
# ---------------------------------------------------------------------------
#
# Greenfield School used to be built here: SchoolStructure, SchoolPartitions,
# SchoolPortico, SchoolParapet and SchoolFittings, plus the nameplate reading
# GREENFIELD SCHOOL over the entrance.
#
# It is gone from assets/Street.rbxmx already -- the downtown rebuild dropped
# the building but left its place points behind, which is what
# tools/move_school_points.py exists to shepherd. The generator code outlived
# the building by about a week.
#
# The school is now built at runtime by src/server/world/School.luau and baked
# to assets/School.rbxmx, laid around the `school` place point. Two schools in
# one world is one too many, so this is deleted rather than commented out or
# left behind a flag: a flag would be a promise that the old one still works,
# and it does not -- world_plan's SCHOOL_* interior Places describe rooms that
# no longer exist anywhere.
#
# **Do not regenerate Street.rbxmx from this file without checking with Agent A
# first.** The asset on disk carries downtown work that is not in this script,
# so a regen would silently roll that back -- which is a much worse problem
# than the one this note is about.


# ---------------------------------------------------------------------------
# The workplace
# ---------------------------------------------------------------------------

WRK_IN_X0, WRK_IN_X1 = WORK_X0 + WALL, WORK_X1 - WALL     # -140.5 .. -113.5
WRK_IN_Z0, WRK_IN_Z1 = WORK_Z0 + WALL, WORK_Z1 - WALL     # -72.5 .. -23.5
WRK_DOOR_Z0, WRK_DOOR_Z1 = WORK_DOOR - DOORWAY / 2, WORK_DOOR + DOORWAY / 2

# The stockroom wall, and the corridor/office partition upstairs.
STOCK_Z0, STOCK_Z1 = -58.0, -57.0
OFFICE_X0, OFFICE_X1 = -127.0, -126.0
GUARD_X0, GUARD_X1 = -134.5, -133.5

with group("Workplace"):
    with group("WorkStructure"):
        box("Slab", (WORK_X0, WORK_X1, WORK_Z0, WORK_Z1, FLOOR_1 - SLAB, FLOOR_1),
            FLOOR_SHOP, MARBLE)
        box("Roof", (WORK_X0, WORK_X1, WORK_Z0, WORK_Z1, CEIL_2, CEIL_2 + SLAB),
            ROOF_GREY, SLATE)

        wall("WallWest", (WORK_X0, WRK_IN_X0, WORK_Z0, WORK_Z1, FLOOR_1, CEIL_2),
             BRICK_WARM, along="z")
        wall("WallEast", (WRK_IN_X1, WORK_X1, WORK_Z0, WORK_Z1, FLOOR_1, CEIL_2),
             BRICK_WARM, along="z", doors=((WRK_DOOR_Z0, WRK_DOOR_Z1),))
        wall("WallSouth", (WORK_X0, WORK_X1, WORK_Z0, WRK_IN_Z0, FLOOR_1, CEIL_2),
             BRICK_WARM, along="x")
        wall("WallNorth", (WORK_X0, WORK_X1, WRK_IN_Z1, WORK_Z1, FLOOR_1, CEIL_2),
             BRICK_WARM, along="x")

        # The shopfront: one long window either side of the door, floor to
        # lintel, because a store the player cannot see into from the street is
        # a store they have no reason to walk toward.
        glazing("Shopfront1",
                (WRK_IN_X1 + 0.4, WORK_X1 - 0.4, WRK_IN_Z0 + 3.0, WRK_DOOR_Z0 - 1.0,
                 FLOOR_1 + 1.5, FLOOR_1 + 10.5), along="z", panes=4)
        glazing("Shopfront2",
                (WRK_IN_X1 + 0.4, WORK_X1 - 0.4, WRK_DOOR_Z1 + 1.0, WRK_IN_Z1 - 3.0,
                 FLOOR_1 + 1.5, FLOOR_1 + 10.5), along="z", panes=4)
        glazing("OfficeGlazing",
                (WRK_IN_X1 + 0.4, WORK_X1 - 0.4, WRK_IN_Z0 + 3.0, WRK_IN_Z1 - 3.0,
                 FLOOR_2 + 3.5, FLOOR_2 + 10.5), along="z", panes=8)

    with group("WorkGroundFloor"):
        wall("StockWall", (WRK_IN_X0, WRK_IN_X1, STOCK_Z0, STOCK_Z1, FLOOR_1, CEIL_1),
             PARTITION_PALE, PLASTIC, along="x", doors=((-134.0, -126.0),))

    with group("WorkUpperSlab"):
        # Three pieces around the stair void. If these ever disagree with
        # world_plan's STAIR_* the player climbs sixteen steps into a ceiling,
        # which is why the void is written as the room WORK_STAIR and checked.
        box("SlabWest", (WRK_IN_X0, STAIR_X1, WRK_IN_Z0, STAIR_Z0, CEIL_1, FLOOR_2),
            FLOOR_INDOOR, MARBLE)
        box("SlabNorth", (WRK_IN_X0, STAIR_X1, STAIR_Z1, WRK_IN_Z1, CEIL_1, FLOOR_2),
            FLOOR_INDOOR, MARBLE)
        box("SlabEast", (STAIR_X1, WRK_IN_X1, WRK_IN_Z0, WRK_IN_Z1, CEIL_1, FLOOR_2),
            FLOOR_INDOOR, MARBLE)

    with group("WorkStair"):
        # Solid steps rather than treads on stringers. A player runs up this
        # every shift and a gap between treads is somewhere to get caught.
        for i in range(STAIR_STEPS):
            z0 = STAIR_Z0 + i * STAIR_GOING
            box(f"Step{i + 1}",
                (STAIR_X0, STAIR_X1, z0, z0 + STAIR_GOING,
                 FLOOR_1 - SLAB, FLOOR_1 + (i + 1) * STAIR_RISE),
                PARTITION_PALE, CONCRETE)
        box("Guard", (GUARD_X0, GUARD_X1, STAIR_Z0, STAIR_Z1, FLOOR_2, CEIL_2),
            PARTITION_PALE, PLASTIC)
        box("VoidWall", (STAIR_X0, STAIR_X1, STOCK_Z1, STAIR_Z0, FLOOR_2, CEIL_2),
            PARTITION_PALE, PLASTIC)
        # A rail down the open side of the flight, at the height it would be.
        box("Rail", (GUARD_X0 - 0.3, GUARD_X0, STAIR_Z0, STAIR_Z1,
                     FLOOR_1 + 3.0, FLOOR_2 + 3.0), STEEL, METAL, collide=False)

    with group("WorkUpperFloor"):
        wall("OfficePartition",
             (OFFICE_X0, OFFICE_X1, WRK_IN_Z0, WRK_IN_Z1, FLOOR_2, CEIL_2),
             PARTITION_PALE, PLASTIC, along="z",
             doors=((-62.0, -56.0), (-40.0, -34.0)))
        box("MeetingWall", (OFFICE_X1, WRK_IN_X1, -48.0, -47.0, FLOOR_2, CEIL_2),
            PARTITION_PALE, PLASTIC)
        # The landing's own back wall, closing the corridor off from the space
        # over the shop's west aisle.
        box("LandingWall", (WRK_IN_X0, GUARD_X0, -41.0, -40.0, FLOOR_2, CEIL_2),
            PARTITION_PALE, PLASTIC, collide=False)

    with group("WorkParapet"):
        for name, bounds in (
            ("West", (WORK_X0, WORK_X0 + 1.0, WORK_Z0, WORK_Z1)),
            ("East", (WORK_X1 - 1.0, WORK_X1, WORK_Z0, WORK_Z1)),
            ("South", (WORK_X0, WORK_X1, WORK_Z0, WORK_Z0 + 1.0)),
            ("North", (WORK_X0, WORK_X1, WORK_Z1 - 1.0, WORK_Z1)),
        ):
            box(f"Parapet{name}", (*bounds, CEIL_2 + SLAB, CEIL_2 + SLAB + 2.5),
                BRICK_WARM, BRICK)
        box("Fascia", (WORK_X1 - 2.5, WORK_X1, WRK_DOOR_Z0 - 6.0, WRK_DOOR_Z1 + 6.0,
                       FLOOR_1 + 11.5, FLOOR_1 + 15.5),
            (40, 62, 74), SMOOTH,
            children=sign("PARKSIDE MARKET", "right", color=(246, 226, 168), size=72))

# ---------------------------------------------------------------------------
# Fittings
# ---------------------------------------------------------------------------


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
    """A gondola: two decks and an end frame, running along z."""
    with group(label):
        box(f"{label}Base", (x - 1.6, x + 1.6, z0, z1, floor, floor + 0.6), SHELF, METAL)
        for i, dy in enumerate((3.0, 5.6, 8.2)):
            box(f"{label}Deck{i + 1}", (x - 1.6, x + 1.6, z0, z1, floor + dy,
                                        floor + dy + 0.3), SHELF, METAL)
        box(f"{label}Spine", (x - 0.2, x + 0.2, z0, z1, floor, floor + 9.5), SHELF, METAL)
        # Something on the shelves, so the store is stocked rather than empty.
        n = max(1, int((z1 - z0) // 3.0))
        for i in range(n):
            a = z0 + (z1 - z0) * i / n + 0.4
            b = z0 + (z1 - z0) * (i + 1) / n - 0.4
            for dy in (3.3, 5.9):
                box(f"{label}Stock", (x - 1.4, x + 1.4, a, b, floor + dy,
                                      floor + dy + 1.8), STOCK, PLANKS, collide=False)


def classroom(room, index):
    """A board on the west wall, the teacher's desk in front of it, one row of
    desks facing them, and a clear lane down the middle to the door.

    Every dimension is measured off the room and the whole arrangement stops
    seven studs short of the east wall, because the door is in that wall and the
    first pass at this put four desks and four chairs out in the corridor. The
    gap left at the room's midline is not decoration either: it is the line the
    player walks in on, and it is the reason there is an even number of desks.
    """
    mid_z = (room.z0 + room.z1) / 2
    box(f"Board{index}", (room.x0, room.x0 + 0.3, mid_z - 6.0, mid_z + 6.0,
                          FLOOR_1 + 4.0, FLOOR_1 + 9.0), BOARD, SMOOTH, collide=False)
    desk(room.x0 + 4.5, mid_z, FLOOR_1, side="east", width=6.0, depth=2.6,
         label="TeacherDesk")
    for offset in (-8.0, -3.0, 3.0, 8.0):
        desk(room.x0 + 8.0, mid_z + offset, FLOOR_1, side="east",
             width=3.0, depth=2.2, label="PupilDesk")
    for z in (mid_z - 6.0, mid_z + 6.0):
        ceiling_light((room.x0 + room.x1) / 2, z, CEIL_1)


    # Shop floor. The whole southern third of the room is left empty and that is
    # the design, not an oversight: the door, the stockroom and the stair all
    # open onto it, so it is the one lane every walk in this building uses. The
    # aisles live north of it, well clear of the stairwell -- a gondola standing
    # in the stairwell is a shelf hanging in mid-air over the fourth step, which
    # is exactly what the first pass built.
    for i, x in enumerate((-132.0, -126.0)):
        shelf_run(x, -44.0, -27.0, FLOOR_1, label=f"Aisle{i + 1}")
    box("WallShelf", (-138.0, -116.0, -25.5, -23.5, FLOOR_1, FLOOR_1 + 9.0),
        SHELF, METAL)
    # Checkout, beside the door and out of the line through it.
    box("Counter", (-119.0, -115.5, -40.0, -30.0, FLOOR_1, FLOOR_1 + 3.4),
        DESK_TOP, WOOD)
    box("Till", (-118.0, -116.5, -36.0, -34.0, FLOOR_1 + 3.4, FLOOR_1 + 4.4),
        STEEL, METAL)
    for z in (-52.0, -42.0, -32.0):
        for x in (-137.0, -129.0, -121.0):
            ceiling_light(x, z, CEIL_1)

    # Stockroom: pallets against the south wall, clear of the lane in from the
    # door at x -130.
    for i, x in enumerate((-137.5, -122.0, -117.0)):
        box(f"Pallet{i + 1}", (x - 2.2, x + 2.2, -71.0, -64.0, FLOOR_1, FLOOR_1 + 5.0),
            STOCK, PLANKS)
    ceiling_light(-128.0, -68.0, CEIL_1)

    # Open plan office: one row of desks along the east side with a lane down
    # the west, which is where Part 2's adult job clocks in. The lane is what the
    # place point stands in -- a clock-in spot you can only reach by climbing
    # over a desk is a clock-in spot nobody clocks in at.
    for z in (-70.0, -65.0, -57.0, -52.5):
        desk(-118.0, z, FLOOR_2, side="east", width=3.6, depth=2.6, label="OfficeDesk")
        chair(-116.5, z, FLOOR_2, side="east")
    for z in (-68.0, -53.0):
        ceiling_light(-120.0, z, CEIL_2)

    # Meeting room.
    box("Table", (-124.0, -116.0, -44.0, -32.0, FLOOR_2 + 2.4, FLOOR_2 + 2.8),
        DESK_TOP, WOOD)
    for x in (-123.0, -117.0):
        for z in (-42.0, -38.0, -34.0):
            chair(x, z, FLOOR_2, side="north")
    ceiling_light(-120.0, -38.0, CEIL_2)

    # Break room, and the lights along the corridor and landing.
    box("BreakTable", (-139.5, -135.5, -70.0, -64.0, FLOOR_2 + 2.4, FLOOR_2 + 2.8),
        DESK_TOP, WOOD)
    ceiling_light(-137.5, -67.0, CEIL_2)
    for z in (-68.0, -58.0, -48.0, -37.0, -28.0):
        ceiling_light(-130.0, z, CEIL_2)

# ---------------------------------------------------------------------------
# Place points
# ---------------------------------------------------------------------------

with group("PlacePoints"):
    # Invisible, deaf and un-collidable: this is a coordinate the game can look
    # up by name, and the one thing it must never do is be an object in the room.
    # Same pattern as the delivery points in the house, and PlaceService reads it
    # by tag rather than by path so moving one in Studio is a supported edit.
    for place_id, x, z, floor, label in PLACE_POINTS:
        box(f"Place_{place_id}", (x - 0.5, x + 0.5, z - 0.5, z + 0.5, floor, floor + 1.0),
            (255, 255, 255), SMOOTH, transparency=1.0, collide=False,
            tags=[PLACE_TAG],
            attrs={PLACE_ID_ATTRIBUTE: place_id, PLACE_LABEL_ATTRIBUTE: label})

print(rbxmx.write(STREET, "Street"))
