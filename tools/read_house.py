#!/usr/bin/env python3
"""Reads the house and checks the furniture standing in it.

This is the debug path for the building. Furniture is generated blind — the
generator does arithmetic against numbers in house_plan.py and never looks at
assets/House.rbxmx — so something has to open the actual model and confirm the
result is a room and not a lawn. An early pass shipped a kitchen outdoors and a
sofa that sealed a doorway; both would have been caught here.

    python3 tools/read_house.py plan     what the house is made of
    python3 tools/read_house.py check    is the furniture where it should be
    python3 tools/read_house.py spawn    where the toddler can start
    python3 tools/read_house.py pocket   where a parent can hand money over

`check` exits non-zero when anything is wrong, so it can gate a commit.
"""

import base64
import json
import math
import struct
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

import house_plan
from house_plan import (
    DELIVERY_MODE_ATTRIBUTE,
    DELIVERY_MODES,
    DELIVERY_TAG,
    ENACT_CHOICES,
    ENACT_FACINGS,
    ENACT_FAN_DEGREES,
    ENACT_HEADINGS,
    ENACT_MARKER_DRIFT_DEGREES,
    ENACT_MARKER_DRIFT_STEP_DEGREES,
    ENACT_MARKER_RADIUS,
    ENACT_MARKER_SPREAD,
    ENACT_MAX_ROTATION_DEGREES,
    ENACT_MIN_FIT_RATE,
    ENACT_MIN_MARKER_RADIUS,
    ENACT_ROTATION_STEP_DEGREES,
    ENACT_SPREAD_STEPS,
    ENACT_THING_REACH_STUDS,
    EVENT_ANCHOR,
    FURNITURE,
    HOUSE,
    INTERACT_RADIUS,
    KEEP_CLEAR,
    MIN_BEARING_GAP_DEGREES,
    NPC_APPROACH_STUDS,
    PARENT_BODY_RADIUS,
    POCKET_ARC_DEGREES,
    POCKET_BEARINGS,
    POCKET_HANDOVER_STUDS,
    POCKET_MIN_FIT_RATE,
    POCKET_RETRY_SPAWN_SCALE,
    POCKET_SPAWN_STUDS,
    ROOMS,
    SCENE_APPROACH_STUDS,
    SCENE_ARC_DEGREES,
    SCENE_BEARINGS,
    SCENE_RETRY_WALK_IN_SCALE,
    SCENE_WALK_IN_STUDS,
    STANCE_BEARINGS,
    SUBJECT_BODY_LENGTH,
    SUBJECT_BODY_WIDTH,
)
from world_plan import (
    CEIL_2,
    FLOOR_1,
    FLOOR_2,
    MIN_HEADROOM,
    PLACES,
    PLACE_ID_ATTRIBUTE,
    PLACE_LABEL_ATTRIBUTE,
    PLACE_POINTS,
    PLACE_TAG,
    ROUTES,
    ROUTE_RADIUS,
    STAIR_GOING,
    STAIR_MIN_GOING,
    STAIR_MAX_RISE,
    STAIR_RISE,
    STAIR_STEPS,
    STAIR_WIDTH,
    STAIR_X0,
    STAIR_X1,
    STAIR_Z0,
    STAIR_Z1,
    STREET,
)

PROJECT = Path(__file__).resolve().parent.parent / "default.project.json"

# Anything thinner than this in every axis is trim, glazing or a fixing rather
# than something a body would walk into.
_SOLID_MIN_THICKNESS = 0.4
# How far two boxes have to interpenetrate before it reads as a mistake instead
# of parts of one piece of furniture sharing a seam.
_CLIP_TOLERANCE = 0.3
# Half the width of a body, in studs. Floor with less than this to spare on
# every side cannot actually be stood on, which is the measure both the space
# sweep and the visitor's waiting spot are held to.
_BODY_RADIUS = 1.4
# Half the width to insist on along a walk, as opposed to at rest. Lower than
# _BODY_RADIUS on purpose: people turn sideways past a chair, and holding a
# corridor to standing-room width fails routes that are perfectly walkable.
_WALK_RADIUS = 1.1


_SOLID_CLASSES = {"Part", "MeshPart", "UnionOperation", "WedgePart", "TrussPart"}
_GROUPING_CLASSES = {"Model", "Folder"}


def _number(node, tag):
    found = node.find(tag) if node is not None else None
    return float(found.text) if found is not None and found.text else 0.0


def _named(props, tag, name):
    """A property element by its XML tag and Roblox property name."""
    if props is None:
        return None
    for child in props.findall(tag):
        if child.get("name") == name:
            return child
    return None


def _tags(props):
    """CollectionService tags: the names joined by NULs, base64'd."""
    node = _named(props, "BinaryString", "Tags")
    if node is None or not node.text:
        return ()
    return tuple(t for t in base64.b64decode(node.text).decode().split("\0") if t)


def _collides(props):
    """Whether a body would be stopped by this part.

    Absent means true, which is Roblox's own default, and the exporter only
    writes the property when it is false.

    This is not a detail. Until it was read, every check here treated the glass
    in the front door as a wall -- a hundredth of a stud thick, filling the
    entire opening -- and reported the only way out of the house as sealed. A
    checker that measures the wrong thing with confidence is worse than no
    checker, and this one line is the difference.
    """
    node = _named(props, "bool", "CanCollide")
    if node is None or not node.text:
        return True
    return node.text.strip().lower() != "false"


def _attributes(props):
    """Roblox's attribute blob: a u32 count, then per entry a length-prefixed
    name, a one-byte type id and the value.

    Only strings (0x02) are decoded. Every attribute the generator writes is
    one, and any other type has a width this does not know, so the parse stops
    there rather than reading a later entry out of a misaligned offset and
    reporting confident nonsense.
    """
    node = _named(props, "BinaryString", "AttributesSerialize")
    if node is None or not node.text:
        return {}

    blob = base64.b64decode(node.text)
    out = {}
    at = 4
    for _ in range(struct.unpack_from("<I", blob, 0)[0]):
        (name_len,) = struct.unpack_from("<I", blob, at)
        at += 4
        name = blob[at:at + name_len].decode()
        at += name_len
        kind, at = blob[at], at + 1
        if kind != 0x02:
            break
        (value_len,) = struct.unpack_from("<I", blob, at)
        at += 4
        out[name] = blob[at:at + value_len].decode()
        at += value_len
    return out


_LOADED = {}


def load(path):
    """Every part in a .rbxmx, as an axis-aligned box in world space.

    Cached by path. Nothing here writes to the boxes it hands back, and the
    street check asks for the same three files once per storey and once per
    route -- parsing five megabytes of House.rbxmx a dozen times over is the
    difference between a check somebody runs and a check somebody skips.

    Roblox stores a rotation matrix, not a bounding box, so the extent along
    each world axis is the size projected through that matrix — which is what
    lets a piece turned to face a different wall still be checked against the
    wall it is now nearest.

    Each box also carries the Model it sits in. That is the difference between
    a sink recessed into a counter and a plant standing inside a sofa: the
    geometry is identical, only the grouping says which one is a mistake.

    Tags, attributes and facing come along too. For most parts they are noise,
    but a delivery point is nothing *but* those three — an invisible box whose
    entire content is which mode it serves and which way it points.
    """
    cached = _LOADED.get(path)
    if cached is not None:
        return cached

    parts = []

    def walk(node, group):
        for item in node.findall("Item"):
            cls = item.get("class")
            props = item.find("Properties")
            name_node = _named(props, "string", "Name")
            name = name_node.text if name_node is not None and name_node.text else "?"

            if cls in _SOLID_CLASSES:
                cframe = _named(props, "CoordinateFrame", "CFrame")
                size = _named(props, "Vector3", "size") or _named(props, "Vector3", "Size")
                if cframe is not None and size is not None:
                    px, py, pz = (_number(cframe, axis) for axis in ("X", "Y", "Z"))
                    rot = [[_number(cframe, "R%d%d" % (i, j)) for j in range(3)] for i in range(3)]
                    half = [_number(size, axis) / 2 for axis in ("X", "Y", "Z")]
                    ext = [sum(abs(rot[i][j]) * half[j] for j in range(3)) for i in range(3)]
                    parts.append(
                        dict(
                            cls=cls, name=name, group=group, p=(px, py, pz), ext=ext,
                            x0=px - ext[0], x1=px + ext[0],
                            y0=py - ext[1], y1=py + ext[1],
                            z0=pz - ext[2], z1=pz + ext[2],
                            tags=_tags(props), attrs=_attributes(props),
                            collide=_collides(props),
                            # A CFrame's front face is -Z, so the direction it
                            # looks is the negated third column of its rotation.
                            look=(-rot[0][2], -rot[1][2], -rot[2][2]),
                        )
                    )

            # The innermost enclosing Model wins, so a piece inside the root
            # Furniture model reports as the piece and not as "Furniture".
            walk(item, name if cls in _GROUPING_CLASSES else group)

    walk(ET.parse(path).getroot(), "")
    _LOADED[path] = parts
    return parts


def overlap(a, b):
    """Interpenetration of two boxes on each axis. Negative on any axis means
    they are apart."""
    return (
        min(a["x1"], b["x1"]) - max(a["x0"], b["x0"]),
        min(a["y1"], b["y1"]) - max(a["y0"], b["y0"]),
        min(a["z1"], b["z1"]) - max(a["z0"], b["z0"]),
    )


def footprints_overlap(box, rect, tolerance=0.15):
    """Whether a part's footprint intrudes on an (x0, x1, z0, z1) rectangle."""
    x0, x1, z0, z1 = rect
    return (
        box["x1"] > x0 + tolerance
        and box["x0"] < x1 - tolerance
        and box["z1"] > z0 + tolerance
        and box["z0"] < z1 - tolerance
    )


def room_of(box):
    for room in ROOMS:
        if room.contains(box["x0"], box["x1"], box["z0"], box["z1"], box["y0"]):
            return room
    return None


# ---------------------------------------------------------------------------
# clearance — how much room a body has, shared by `check` and `spawn`
# ---------------------------------------------------------------------------

def _clearance_field(level_y):
    """Obstacles and standable floor at one storey, as flat rectangles.

    Only geometry in the band a body occupies counts: the floor underfoot and
    the roof overhead are not obstacles, but a sofa is. Tagged furniture parts
    are skipped wholesale — every one the generator emits is an invisible,
    non-colliding marker that exists to be read rather than walked into, and a
    doorstep that reported itself as an obstacle would fail its own check.

    Non-colliding geometry is skipped for the same reason and it matters more:
    a window is something you see through and a wall is something you stop at,
    and the property that tells them apart is CanCollide. See _collides.
    """
    parts = load(HOUSE) + [p for p in load(FURNITURE) if not p["tags"]]
    obstacles = [
        (p["x0"], p["x1"], p["z0"], p["z1"])
        for p in parts
        if p["collide"] and p["y0"] < level_y + 3.0 and p["y1"] > level_y + 0.3
    ]
    floors = [
        (p["x0"], p["x1"], p["z0"], p["z1"])
        for p in load(HOUSE)
        if abs(p["y1"] - level_y) < 0.6 and p["ext"][0] * p["ext"][2] > 20 and p["ext"][1] < 3
    ]
    return obstacles, floors


def clearance(obstacles, x, z):
    """Distance from a spot to the nearest thing standing at body height."""
    best = 99.0
    for x0, x1, z0, z1 in obstacles:
        dx = max(x0 - x, 0.0, x - x1)
        dz = max(z0 - z, 0.0, z - z1)
        best = min(best, math.hypot(dx, dz))
    return best


def standable(floors, x, z):
    return any(x0 <= x <= x1 and z0 <= z <= z1 for x0, x1, z0, z1 in floors)


def walk_clear(obstacles, start, end, width, stop_within=0.0):
    """Whether a body of `width` fits the whole way along a straight line.

    Straight because that is what actually happens: both walks this measures —
    a toddler crossing to the rug, a visitor coming in from the door — are aimed
    at a point with no pathfinding behind them, so a chair halfway along is not
    routed around, it is walked into. `stop_within` is how close to the end the
    walk stops mattering, for the cases that finish on arrival rather than at
    the exact spot.
    """
    (sx, sz), (ex, ez) = start, end
    distance = math.hypot(ex - sx, ez - sz)
    steps = max(int(distance * 2), 1)
    for i in range(steps + 1):
        t = i / steps
        px, pz = sx + (ex - sx) * t, sz + (ez - sz) * t
        if math.hypot(px - ex, pz - ez) <= stop_within:
            break
        if clearance(obstacles, px, pz) < width:
            return False
    return True


def _drift_from(ideal):
    """The bearings around an even fan's slot, best first — EnactService.driftFrom."""
    bearings = [ideal]
    if ENACT_MARKER_DRIFT_STEP_DEGREES <= 0:
        return bearings
    offset = ENACT_MARKER_DRIFT_STEP_DEGREES
    while offset <= ENACT_MARKER_DRIFT_DEGREES:
        bearings.append(ideal + offset)
        bearings.append(ideal - offset)
        offset += ENACT_MARKER_DRIFT_STEP_DEGREES
    return bearings


def _even_options():
    """One bearing list per choice, evenly across the fan — EnactService.evenOptions."""
    step = ENACT_FAN_DEGREES / (ENACT_CHOICES - 1)
    return [_drift_from(-ENACT_FAN_DEGREES / 2 + i * step) for i in range(ENACT_CHOICES)]


def _shadow_limit(origin, a, b):
    """How wide two markers may be drawn without either blocking the walk to the
    other — EnactService.shadowLimit. See that function for why this exists at all.
    """
    ax, az = a[0] - origin[0], a[1] - origin[1]
    bx, bz = b[0] - origin[0], b[1] - origin[1]
    if ax * bx + az * bz <= 0:
        return math.inf
    longer = max(math.hypot(ax, az), math.hypot(bx, bz))
    if longer < 1e-3:
        return math.inf
    return abs(ax * bz - az * bx) / longer


def _conflicts(origin, placed, candidate, thing=None):
    """Whether a spot is unusable given the markers already down — EnactService.conflicts.

    `thing` is where the subject comes to rest, when one of the choices is riding it.
    A floor marker inside that zone would be a second answer under the player's feet
    at the moment they reach the animal, so the pads are kept out of it.
    """
    for taken in placed:
        if math.hypot(taken[0] - candidate[0], taken[1] - candidate[1]) < ENACT_MIN_MARKER_RADIUS * 2:
            return True
        if _shadow_limit(origin, taken, candidate) < ENACT_MIN_MARKER_RADIUS:
            return True
    if thing is not None:
        if math.hypot(thing[0] - candidate[0], thing[1] - candidate[1]) < ENACT_THING_REACH_STUDS + ENACT_MIN_MARKER_RADIUS:
            return True
        # Only the nearer of the two can stand in the other's walk, so which radius
        # has to clear the line depends on which one that is.
        to_thing = math.hypot(thing[0] - origin[0], thing[1] - origin[1])
        to_candidate = math.hypot(candidate[0] - origin[0], candidate[1] - origin[1])
        needed = ENACT_THING_REACH_STUDS if to_thing <= to_candidate else ENACT_MIN_MARKER_RADIUS
        if _shadow_limit(origin, thing, candidate) < needed:
            return True
    return False


def _reach_radius(origin, placed, thing=None):
    """Whether the arrangement can be drawn wide enough to stand on — EnactService.reachRadius."""
    widest = ENACT_MARKER_RADIUS
    for i, a in enumerate(placed):
        for b in placed[i + 1:]:
            widest = min(widest, math.hypot(a[0] - b[0], a[1] - b[1]) / 2, _shadow_limit(origin, a, b))
    if thing is not None:
        to_thing = math.hypot(thing[0] - origin[0], thing[1] - origin[1])
        for a in placed:
            # Subtracted rather than halved: the animal's reach is fixed and the pad's
            # is what gives.
            widest = min(widest, math.hypot(thing[0] - a[0], thing[1] - a[1]) - ENACT_THING_REACH_STUDS)
            if math.hypot(a[0] - origin[0], a[1] - origin[1]) <= to_thing:
                widest = min(widest, _shadow_limit(origin, thing, a))
    return widest >= ENACT_MIN_MARKER_RADIUS


def _fan_fits(obstacles, floors, x, z, axis, options, anchored, thing=None):
    """Whether every choice has somewhere to stand with the arrangement on `axis`.

    Mirrors EnactService.fan exactly, and is used for both arrangements because the
    game uses one function for both: each choice walks its own bearings in order,
    tries every spread step at each before questioning the bearing, and takes the
    first spot that holds. Greedy in the authored order, not a search for the best
    whole arrangement — same as the game, so that a spot this reports as workable is
    one the game will actually lay markers on.

    All or nothing: two markers out of three is not a reduced choice, it is a broken
    one, so an arrangement that loses any of its spots is not an arrangement.
    """
    origin = (x, z)
    placed, claimed = [], []

    for bearings in options:
        taken = False
        for bearing in bearings:
            # Only a stanced arrangement can crowd itself in a way that matters;
            # an even fan's near misses are caught below on geometry alone.
            if anchored and any(
                abs((bearing - already + 180.0) % 360.0 - 180.0) < MIN_BEARING_GAP_DEGREES
                for already in claimed
            ):
                continue
            angle = math.radians(axis + bearing)
            dx, dz = math.sin(angle), math.cos(angle)

            for scale in ENACT_SPREAD_STEPS:
                spread = ENACT_MARKER_SPREAD * scale
                spot = (x + dx * spread, z + dz * spread)
                if not standable(floors, *spot):
                    continue
                if clearance(obstacles, *spot) < _BODY_RADIUS:
                    continue
                # The game only rays for line of sight here; this insists a body
                # fits the whole way. Stricter on purpose: a choice you can see but
                # have to squeeze past a chair to reach is a choice the player will
                # read as broken, and the cost of being wrong is one spot reported
                # tighter than it plays.
                if not walk_clear(obstacles, origin, spot, _WALK_RADIUS):
                    continue
                if _conflicts(origin, placed, spot, thing):
                    continue
                placed.append(spot)
                claimed.append(bearing)
                taken = True
                break
            if taken:
                break
        if not taken:
            return False

    return _reach_radius(origin, placed, thing)


def _fan_axes(facing):
    """Every axis the game would try from this facing, best first — EnactService.rotations.

    This is the whole of what changed. The check used to sweep headings and take any
    that worked, which flattered the game: the game only ever tried the one way the
    player happened to be facing, and measuring it honestly put the real fit rate at
    19%. Now the game turns the arrangement itself, so the sweep and the game are
    finally the same thing, and this function is where they meet.
    """
    axes = [facing]
    if ENACT_ROTATION_STEP_DEGREES <= 0:
        return axes
    limit = min(ENACT_MAX_ROTATION_DEGREES, 180.0)
    turn = ENACT_ROTATION_STEP_DEGREES
    while turn <= limit:
        axes.append(facing + turn)
        if turn < 180.0:
            axes.append(facing - turn)
        turn += ENACT_ROTATION_STEP_DEGREES
    return axes


def _any_rotation(obstacles, floors, x, z, facing, cache):
    """Whether a player at (x, z) facing this way gets markers rather than a panel.

    The cache is keyed on the axis rather than the facing, because facings 15
    degrees apart share every axis but one. Without it this repeats the same fan
    two dozen times per spot for no new information.
    """
    for axis in _fan_axes(facing):
        key = round(axis % 360.0, 3)
        fits = cache.get(key)
        if fits is None:
            fits = _fan_fits(obstacles, floors, x, z, axis, _even_options(), False)
            cache[key] = fits
        if fits:
            return True
    return False


def _standing_spots(obstacles, floors, x, z, radius, rings=3, bearings=8):
    """Where a player might be when an event fires at (x, z).

    Not (x, z) itself. An event fires when the player comes within
    InteractRadius of its anchor, and the anchor is a doormat or a phone on a
    hall table — places you stand *beside*, not on. Measuring the fan from the
    anchor asks whether a fan fits inside the furniture, which is the wrong
    question and always answers no.
    """
    spots = []
    for ring in range(rings + 1):
        r = radius * ring / rings
        # The center is one spot, not `bearings` copies of itself.
        for b in range(bearings if ring > 0 else 1):
            angle = math.radians(b * 360.0 / bearings)
            px, pz = x + math.sin(angle) * r, z + math.cos(angle) * r
            if standable(floors, px, pz) and clearance(obstacles, px, pz) >= _BODY_RADIUS:
                spots.append((px, pz))
    return spots


def _near(obstacles, x, z, reach):
    """Obstacles close enough to matter to a fan raised anywhere near (x, z).

    Purely a speed cut — every check below is a full sweep over every obstacle
    in the storey, and doing that thousands of times per spot is the difference
    between this check running and this check being skipped.
    """
    return [
        (x0, x1, z0, z1)
        for x0, x1, z0, z1 in obstacles
        if x0 - reach <= x <= x1 + reach and z0 - reach <= z <= z1 + reach
    ]


def enact_reach(obstacles, floors, x, z):
    """(workable, total) ways of arriving at (x, z) that get markers rather than a panel.

    A case is a place to stand crossed with a way to be facing, not a place to stand
    on its own. That is the measurement that matters, because it is the one the
    player takes: they walk up to the phone from wherever they were, facing however
    they were, and what they get is decided then.

    Zero workable is a fault -- every event here falls back to a panel, which is the
    one outcome the whole feature exists to avoid. But the number itself is the
    reason this returns a rate rather than a boolean: the difference between a house
    where enactment works and one where it technically can is a percentage, and it
    is not visible from inside the game at all.
    """
    near = _near(obstacles, x, z, INTERACT_RADIUS + ENACT_MARKER_SPREAD + _BODY_RADIUS)
    spots = _standing_spots(near, floors, x, z, INTERACT_RADIUS)

    workable = total = 0
    for px, pz in spots:
        cache = {}
        for i in range(ENACT_FACINGS):
            total += 1
            if _any_rotation(near, floors, px, pz, i * 360.0 / ENACT_FACINGS, cache):
                workable += 1
    return workable, total


def _facings(facings, part):
    """The enactable note for a spot in the informational listing.

    Printed even when every case works, because the number falling is the warning: a
    spot that drops from all of them to a handful still passes the check but is one
    more chair away from only ever producing panels.
    """
    counts = facings.get(id(part))
    if counts is None:
        return ""
    workable, total = counts
    rate = 100.0 * workable / total if total else 0.0
    return "   %d/%d spot-facings enact (%.0f%%)" % (workable, total, rate)


# ---------------------------------------------------------------------------
# subjects
# ---------------------------------------------------------------------------

def _subject_bearings():
    """The bearings SceneService tries, in the order it tries them.

    Straight ahead first, then alternating outward, so the animal arrives where
    the player is already looking whenever the room allows it.
    """
    if SCENE_BEARINGS <= 1:
        return [0.0]
    step = SCENE_ARC_DEGREES / (SCENE_BEARINGS - 1)
    angles = [-SCENE_ARC_DEGREES / 2 + i * step for i in range(SCENE_BEARINGS)]
    return sorted(angles, key=lambda a: (abs(a), a))


def _subject_axis(obstacles, floors, x, z, heading):
    """(bearing, resting spot) for the dog, or None.

    Mirrors SceneService.place: a resting spot with floor under it and room for
    the animal, a spawn spot the same walk-in further out, and a clear line both
    from the player to the resting spot and along the walk in.

    The resting spot comes back as well as the bearing because a choice now rides the
    animal, so where it stops is not only the axis the other choices are laid out on
    -- it is also a place the floor markers have to stay out of.
    """
    # Clearance is measured to the animal's near edge, so its middle stands half
    # its own length further out than the Config number.
    rest_at = SCENE_APPROACH_STUDS + SUBJECT_BODY_LENGTH / 2
    radius = max(SUBJECT_BODY_LENGTH, SUBJECT_BODY_WIDTH) / 2

    for walk_in in (SCENE_WALK_IN_STUDS, SCENE_WALK_IN_STUDS * SCENE_RETRY_WALK_IN_SCALE):
        for bearing in _subject_bearings():
            angle = math.radians(heading + bearing)
            dx, dz = math.sin(angle), math.cos(angle)
            stop = (x + dx * rest_at, z + dz * rest_at)
            spawn = (x + dx * (rest_at + walk_in), z + dz * (rest_at + walk_in))
            if not standable(floors, *stop) or not standable(floors, *spawn):
                continue
            if clearance(obstacles, *stop) < radius or clearance(obstacles, *spawn) < radius:
                continue
            # The player has to be able to see it, and it has to be able to get
            # there. Both are single rays in the game; both are held to a body's
            # width here, for the reason _fan_fits gives.
            if not walk_clear(obstacles, (x, z), stop, _WALK_RADIUS):
                continue
            if not walk_clear(obstacles, spawn, stop, _WALK_RADIUS):
                continue
            return heading + bearing, stop
    return None


def _subject_reach(obstacles, floors, x, z):
    """(placed, stanced, total) over the standing spots near (x, z).

    Three numbers rather than one because the two halves fail independently and
    for different reasons. `placed` is how many spots can hold the animal at all;
    `stanced` is how many of those can *also* hold the choices arranged around
    it. A spot that places the dog but cannot stance the choices still plays --
    the animal walks in and the event falls back to a panel -- so it is a warning
    rather than a fault. Zero placed anywhere is the fault: it means the event
    that the whole subject system was built for never shows an animal.
    """
    near = _near(obstacles, x, z, INTERACT_RADIUS + SCENE_APPROACH_STUDS
                 + SUBJECT_BODY_LENGTH + SCENE_WALK_IN_STUDS + _BODY_RADIUS)
    spots = _standing_spots(near, floors, x, z, INTERACT_RADIUS)

    placed = stanced = 0
    for px, pz in spots:
        # A spot counts if any facing works, the same way the player counts it:
        # they turn around. Swept for both answers together rather than settling
        # on the first facing that places the animal -- the axis the choices are
        # arranged on is the facing plus whichever bearing the animal took, so a
        # facing that places it is not necessarily one that can also hold the
        # choices, and the player would have found the one that does.
        any_placed = False
        for i in range(ENACT_HEADINGS):
            found = _subject_axis(near, floors, px, pz, i * 360.0 / ENACT_HEADINGS)
            if found is None:
                continue
            axis, stop = found
            any_placed = True
            # The same fan as the even one, told to use the stances' own bearings
            # and never turned: the axis here is the line to the animal, and turning
            # it would point "toward the dog" away from the dog. Handed the animal's
            # resting spot too, because one of the choices is standing on it.
            if _fan_fits(near, floors, px, pz, axis, STANCE_BEARINGS, True, stop):
                stanced += 1
                break
        if any_placed:
            placed += 1
    return placed, stanced, len(spots)


# ---------------------------------------------------------------------------
# pocket money — can a parent get to you, wherever you happen to be
# ---------------------------------------------------------------------------

# How finely the floor is sampled when sweeping for handover room. Coarser than
# `space` by four times, because this asks eight questions per sample instead of one
# and the answer is a rate over a room rather than a shape — half a stud of extra
# resolution would cost minutes and move the percentage by nothing.
_POCKET_GRID = 2.0


def _parent_bearings():
    """The bearings PocketMoneyService tries, in the order it tries them.

    Ground.Bearings, which SceneService uses too — the same fan, a much wider arc.
    A parent lives here and may perfectly well come from behind you.
    """
    if POCKET_BEARINGS <= 1:
        return [0.0]
    step = POCKET_ARC_DEGREES / (POCKET_BEARINGS - 1)
    angles = [-POCKET_ARC_DEGREES / 2 + i * step for i in range(POCKET_BEARINGS)]
    return sorted(angles, key=lambda a: (abs(a), a))


def _parent_axis(obstacles, floors, x, z, heading):
    """The bearing a parent can arrive on for a player at (x, z) facing `heading`.

    Mirrors PocketMoneyService.spawnSpot: floor under the spot, room for an adult
    standing on it, and a clear way in. Held to a body's width rather than the game's
    single ray, for the reason _fan_fits gives — a ray threads gaps a person does not.

    The walk stops short by HandoverStuds, because it does: they come to arm's length
    and hand it over. Without that, every handover in the house would be blocked by
    the player's own body sitting at the end of the line.

    Both distances, in the order the game tries them: the whole arc at full range and
    then the whole arc drawn in. That order is the scene degrading rather than
    searching — a long walk everywhere it fits, a short one everywhere else.
    """
    for out in (POCKET_SPAWN_STUDS, POCKET_SPAWN_STUDS * POCKET_RETRY_SPAWN_SCALE):
        for bearing in _parent_bearings():
            angle = math.radians(heading + bearing)
            dx, dz = math.sin(angle), math.cos(angle)
            spawn = (x + dx * out, z + dz * out)
            if not standable(floors, *spawn):
                continue
            if clearance(obstacles, *spawn) < PARENT_BODY_RADIUS:
                continue
            if not walk_clear(obstacles, spawn, (x, z), PARENT_BODY_RADIUS,
                              stop_within=POCKET_HANDOVER_STUDS):
                continue
            return heading + bearing
    return None


def _pocket_sweep():
    """[(room, workable, total)] over every place a birthday could turn over.

    A case is a spot crossed with a facing, the same unit enact_reach counts, and for
    the same reason: the arc is centered on where the player is looking, and a
    birthday gives them no chance to turn around first. What is being measured is a
    moment they do not choose.
    """
    fields, rows = {}, []
    reach = POCKET_SPAWN_STUDS + PARENT_BODY_RADIUS

    for room in ROOMS:
        if room.floor not in fields:
            fields[room.floor] = _clearance_field(room.floor)
        obstacles, floors = fields[room.floor]

        workable = total = 0
        nx = max(int((room.x1 - room.x0) / _POCKET_GRID), 1)
        nz = max(int((room.z1 - room.z0) / _POCKET_GRID), 1)
        for ix in range(nx):
            x = room.x0 + (ix + 0.5) * _POCKET_GRID
            for iz in range(nz):
                z = room.z0 + (iz + 0.5) * _POCKET_GRID
                # Only somewhere the player could actually be standing when the
                # year turns over. Inside a wardrobe is not a birthday.
                if not standable(floors, x, z) or clearance(obstacles, x, z) < _BODY_RADIUS:
                    continue
                near = _near(obstacles, x, z, reach)
                for i in range(ENACT_HEADINGS):
                    total += 1
                    if _parent_axis(near, floors, x, z, i * 360.0 / ENACT_HEADINGS) is not None:
                        workable += 1
        rows.append((room, workable, total))

    return rows


def command_pocket():
    """Where in the house a parent can be staged to hand pocket money over.

    The failure this exists to catch is quiet by design and rare enough to miss by
    playing: a birthday in a room too tight for an adult to appear in pays out of the
    fallback instead, which credits the money over the player's own head after a
    retry cycle. Nothing is lost and nothing errors — the scene simply did not happen,
    and the only way to find out how often that is true is to measure it.
    """
    rows = _pocket_sweep()
    workable = sum(w for _, w, _ in rows)
    total = sum(t for _, _, t in rows)

    print("a parent can be staged %d/%d spot-facings (%.0f%%), bar %.0f%%\n"
          % (workable, total, 100.0 * workable / total if total else 0.0,
             100.0 * POCKET_MIN_FIT_RATE))
    print("   %d bearings across %d degrees, appearing %.0f studs out then %.0f, "
          "handing over at %.0f" % (POCKET_BEARINGS, POCKET_ARC_DEGREES,
                                    POCKET_SPAWN_STUDS,
                                    POCKET_SPAWN_STUDS * POCKET_RETRY_SPAWN_SCALE,
                                    POCKET_HANDOVER_STUDS))

    print("")
    for room, w, t in rows:
        if t == 0:
            print("   %-16s no floor to stand on" % room.name)
            continue
        rate = 100.0 * w / t
        print("   %-16s %4d/%-4d %3.0f%%%s"
              % (room.name, w, t, rate, "   <- fallback territory" if w == 0 else ""))

    if total == 0:
        print("\nFAILED: nowhere in the house to have a birthday")
        return 1
    if workable < total * POCKET_MIN_FIT_RATE:
        print("\nFAILED: under the %.0f%% bar" % (100.0 * POCKET_MIN_FIT_RATE))
        return 1
    print("\nOK")
    return 0


# ---------------------------------------------------------------------------
# plan
# ---------------------------------------------------------------------------

def command_plan():
    house = load(HOUSE)
    print("%s: %d parts" % (HOUSE.name, len(house)))

    by_class = defaultdict(int)
    for part in house:
        by_class[part["cls"]] += 1
    print("  " + ", ".join("%s x%d" % (k, v) for k, v in sorted(by_class.items())))

    # Floor levels show up as horizontal surface area piling up at one height.
    # This is how the second storey was found after a first pass furnished only
    # the ground floor.
    area_at = defaultdict(float)
    for part in house:
        if part["ext"][1] * 2 < 3 and part["ext"][0] * part["ext"][2] > 5:
            area_at[round(part["y1"], 1)] += part["ext"][0] * part["ext"][2] * 4
    print("\nhorizontal surface area by height (candidate floor levels):")
    for y, area in sorted(area_at.items(), key=lambda kv: -kv[1])[:8]:
        print("   y=%6.2f   %8.0f sq studs" % (y, area))

    print("\nrooms transcribed in house_plan.py:")
    for room in ROOMS:
        print(
            "   %-16s x[%6.1f,%6.1f] z[%6.1f,%6.1f]  floor %6.3f  ceiling %5.1f  (%.0f x %.0f)"
            % (room.name, room.x0, room.x1, room.z0, room.z1, room.floor, room.ceiling,
               room.x1 - room.x0, room.z1 - room.z0)
        )

    # Glazing and doors are why half the furniture is not where it would
    # otherwise obviously go, so they get printed with the room they belong to.
    print("\nglazing and doors found in the house:")
    openings = [p for p in house if "curtain" in p["name"].lower() or "door" in p["name"].lower()]
    for part in sorted(openings, key=lambda p: (p["p"][1], p["p"][0])):
        room = room_of(part)
        print(
            "   %-18s x[%6.1f,%6.1f] z[%6.1f,%6.1f] y[%5.1f,%5.1f]  %s"
            % (part["name"], part["x0"], part["x1"], part["z0"], part["z1"],
               part["y0"], part["y1"], room.name if room else "-")
        )

    print("\nkeep-clear footprints:")
    for name, (x0, x1, z0, z1) in KEEP_CLEAR.items():
        print("   %-18s x[%6.1f,%6.1f] z[%6.1f,%6.1f]" % (name, x0, x1, z0, z1))


# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------

def command_check():
    house = load(HOUSE)
    furniture = load(FURNITURE)
    failures = []

    def report(title, rows):
        print("%-42s %s" % (title + ":", len(rows) if rows else "clean"))
        for row in rows[:12]:
            print("      " + row)
        if len(rows) > 12:
            print("      ... and %d more" % (len(rows) - 12))
        if rows:
            failures.append(title)

    # Which room each piece is in, and the pieces that are in none of them.
    homeless, sunken = [], []
    home = {}
    for part in furniture:
        room = room_of(part)
        home[id(part)] = room
        if room is None:
            homeless.append(
                "%-20s x[%6.1f,%6.1f] z[%6.1f,%6.1f]"
                % (part["name"], part["x0"], part["x1"], part["z0"], part["z1"])
            )
        elif part["y0"] < room.floor - _CLIP_TOLERANCE:
            sunken.append(
                "%-20s in %-16s underside %.2f, floor %.2f"
                % (part["name"], room.name, part["y0"], room.floor)
            )
    report("furniture outside every room", homeless)
    report("furniture sunk below its floor", sunken)

    blocking = set()
    for part in furniture:
        room = home[id(part)]
        # Only things standing on the floor block a route; a pendant hanging in
        # a stairwell at ceiling height does not.
        if room and part["y0"] > room.floor + 6.0:
            continue
        for name, rect in KEEP_CLEAR.items():
            if footprints_overlap(part, rect):
                blocking.add("%-18s blocked by %s" % (name, part["name"]))
    report("routes blocked", sorted(blocking))

    solids = [p for p in house if p["ext"][1] * 2 > _SOLID_MIN_THICKNESS]
    clipping = defaultdict(float)
    for part in furniture:
        for solid in solids:
            dx, dy, dz = overlap(part, solid)
            if min(dx, dy, dz) > _CLIP_TOLERANCE:
                clipping[(part["name"], solid["name"])] = max(
                    clipping[(part["name"], solid["name"])], min(dx, dy, dz)
                )
    report(
        "furniture clipping the house",
        ["%-20s into %-20s by %.2f" % (a, b, v)
         for (a, b), v in sorted(clipping.items(), key=lambda kv: -kv[1])],
    )

    # Furniture against furniture. Parts within one piece are meant to share
    # space — a drawer sits in a dresser, a sink sits in a counter — so only
    # overlaps between two different pieces are mistakes.
    collisions = {}
    for i, a in enumerate(furniture):
        for b in furniture[i + 1:]:
            if a["group"] == b["group"]:
                continue
            dx, dy, dz = overlap(a, b)
            depth = min(dx, dy, dz)
            if depth <= _CLIP_TOLERANCE:
                continue
            key = ("%s/%s" % (a["group"], a["name"]), "%s/%s" % (b["group"], b["name"]))
            collisions[key] = max(collisions.get(key, 0.0), depth)
    report(
        "furniture inside other furniture",
        ["%-26s and %-26s by %.2f" % (a, b, v)
         for (a, b), v in sorted(collisions.items(), key=lambda kv: -kv[1])],
    )

    # Delivery points. The game warns about a missing one, but only at the
    # moment it first tries to stage something there — which is minutes into a
    # session, in the output window, long after whoever moved the furniture has
    # stopped looking. It is a fact about the house, so it is checked here.
    points = [p for p in furniture if DELIVERY_TAG in p["tags"]]
    faults, served = [], defaultdict(int)
    fields = {}

    for point in points:
        mode = point["attrs"].get(DELIVERY_MODE_ATTRIBUTE)
        room = home[id(point)]

        if mode is None:
            faults.append("%-16s carries no %s attribute" % (point["name"], DELIVERY_MODE_ATTRIBUTE))
        elif mode not in DELIVERY_MODES:
            faults.append('%-16s serves "%s", which is not a delivery mode' % (point["name"], mode))
        else:
            served[mode] += 1

        if room is None:
            # Already reported as homeless above, but repeated here because a
            # delivery point outside the house is a different kind of wrong: it
            # is somewhere the world will put a letter you cannot reach.
            faults.append("%-16s is not in any room" % point["name"])
            continue

        if mode != "NPCApproach":
            continue

        # A doorstep is only as good as the spot it sends a visitor to. The walk
        # is a straight MoveTo with no pathfinding, so a wait spot behind a
        # dining chair is a visitor who never arrives and times out in the hall.
        if room.floor not in fields:
            fields[room.floor] = _clearance_field(room.floor)
        obstacles, floors = fields[room.floor]

        px, pz = point["p"][0], point["p"][2]
        wx = px + point["look"][0] * NPC_APPROACH_STUDS
        wz = pz + point["look"][2] * NPC_APPROACH_STUDS
        room_at_wait = any(r.contains(wx, wx, wz, wz, room.floor) for r in ROOMS)
        space = clearance(obstacles, wx, wz)

        if not room_at_wait:
            faults.append(
                "%-16s sends a visitor to (%.1f, %.1f), which is outside every room"
                % (point["name"], wx, wz)
            )
        elif not standable(floors, wx, wz):
            faults.append(
                "%-16s sends a visitor to (%.1f, %.1f), which has no floor under it"
                % (point["name"], wx, wz)
            )
        elif space < _BODY_RADIUS:
            faults.append(
                "%-16s waiting spot (%.1f, %.1f) has %.2f studs of room, needs %.2f"
                % (point["name"], wx, wz, space, _BODY_RADIUS)
            )
        elif not walk_clear(obstacles, (px, pz), (wx, wz), _WALK_RADIUS):
            faults.append(
                "%-16s cannot walk straight from (%.1f, %.1f) to (%.1f, %.1f)"
                % (point["name"], px, pz, wx, wz)
            )

    for mode in DELIVERY_MODES:
        if served[mode] == 0:
            faults.append('nothing in the house serves "%s" deliveries' % mode)
    report("delivery points (%d)" % len(points), faults)

    # Enactment. An enacted event fans its choices around the player as places to
    # stand; where they cannot be fanned it falls back to a panel, which works —
    # but a house where they can never be fanned is a house in which the feature
    # does not exist. The spots checked are the ones the player is actually
    # standing on when a prompt opens: the rug the toddler crawls to, and every
    # delivery point, since collecting a letter is what opens its event.
    anchors = [p for p in furniture if p["name"] == "RugEventAnchor"]
    faults, facings = [], {}
    for spot in anchors + points:
        room = home[id(spot)]
        if room is None:
            continue  # already reported above as somewhere the player cannot go
        if room.floor not in fields:
            fields[room.floor] = _clearance_field(room.floor)
        obstacles, floors = fields[room.floor]

        sx, sz = spot["p"][0], spot["p"][2]
        workable, total = enact_reach(obstacles, floors, sx, sz)
        facings[id(spot)] = (workable, total)
        if total == 0:
            # Nowhere to stand within reach at all, which is a worse fault than an
            # unenactable one: the event cannot be triggered either.
            faults.append(
                "%-16s at (%.1f, %.1f) has nowhere to stand within %.0f studs"
                % (spot["name"], sx, sz, INTERACT_RADIUS)
            )
        elif workable == 0:
            faults.append(
                "%-16s at (%.1f, %.1f) cannot arrange %d choices from any of %d arrivals"
                % (spot["name"], sx, sz, ENACT_CHOICES, total)
            )
        elif workable < total * ENACT_MIN_FIT_RATE:
            faults.append(
                "%-16s at (%.1f, %.1f) enacts %d of %d arrivals (%.0f%%), under the %.0f%% bar"
                % (spot["name"], sx, sz, workable, total,
                   100.0 * workable / total, 100.0 * ENACT_MIN_FIT_RATE)
            )
    report("enactable spots (%d)" % len(facings), faults)

    # Subjects. The toddler's dog event is the only one so far that is *about*
    # something, and it fires at the rug — so this is that one spot, checked
    # twice: can the animal be put in the room at all, and can the choices then be
    # arranged around it rather than around the player's facing.
    #
    # Only the first is a fault. Failing to stance the choices means the event
    # falls back to a panel with the dog still standing there, which is a real and
    # working outcome; failing to place the dog means the event is a wall of text
    # about an animal that is not present, which is the exact hole the whole
    # subject system was built to fill.
    faults, subjects = [], {}
    for spot in anchors:
        room = home[id(spot)]
        if room is None:
            continue
        if room.floor not in fields:
            fields[room.floor] = _clearance_field(room.floor)
        obstacles, floors = fields[room.floor]

        sx, sz = spot["p"][0], spot["p"][2]
        placed, stanced, total = _subject_reach(obstacles, floors, sx, sz)
        subjects[id(spot)] = (placed, stanced, total)
        if total > 0 and placed == 0:
            faults.append(
                "%-16s at (%.1f, %.1f) has nowhere to put a dog from any of %d standing spots"
                % (spot["name"], sx, sz, total)
            )
    report("subject spots (%d)" % len(subjects), faults)

    # Pocket money. Every birthday from five to seventeen sends a parent across the
    # room with the allowance, and a birthday fires wherever the player happens to be
    # -- so unlike everything above it, this is not a list of spots but the whole
    # floor. One number, held to a bar, because per-room detail is what `pocket` is
    # for and this is the gate.
    #
    # A room that fails is not broken: the money is credited from the fallback a retry
    # cycle later, which is why the bar sits far below the enact one. What it catches
    # is the house being furnished into somewhere a parent can no longer appear.
    rows = _pocket_sweep()
    staged = sum(w for _, w, _ in rows)
    cases = sum(t for _, _, t in rows)
    faults = []
    if cases == 0:
        faults.append("nowhere in the house to stand when a birthday turns over")
    elif staged < cases * POCKET_MIN_FIT_RATE:
        faults.append(
            "a parent can be staged at %d of %d spot-facings (%.0f%%), under the %.0f%% bar"
            % (staged, cases, 100.0 * staged / cases, 100.0 * POCKET_MIN_FIT_RATE)
        )
    report("pocket money handovers (%d%%)"
           % (100.0 * staged / cases if cases else 0.0), faults)

    # The world outside. Folded into the same gate as the house because it is
    # the same question asked one house further out -- and because the first of
    # these routes starts in the hall, so a sofa moved into the doorway breaks
    # the street, and nothing would say so if the two were checked apart.
    for title, street_faults in _street_sections()[0]:
        report(title, street_faults)

    counts = defaultdict(int)
    for part in furniture:
        room = home[id(part)]
        counts[room.name if room else "nowhere"] += 1
    print("\n%d parts placed:" % len(furniture))
    for room in ROOMS:
        print("   %-16s %3d" % (room.name, counts[room.name]))

    print("\nevent anchors: %d" % len(anchors))
    for part in anchors:
        print("   at (%.1f, %.1f)%s" % (part["p"][0], part["p"][2], _facings(facings, part)))
        counts = subjects.get(id(part))
        if counts is not None:
            # Printed even when nothing is wrong, because the interesting number is
            # the second one falling away from the first: that is the event playing
            # with the dog present but the choices no longer arranged around it,
            # which is a quiet downgrade rather than a failure.
            placed, stanced, total = counts
            print("      %d/%d hold a dog, %d of those stance its choices"
                  % (placed, total, stanced))
    if not anchors:
        failures.append("no event anchor")

    print("\ndelivery points:")
    for point in sorted(points, key=lambda p: p["attrs"].get(DELIVERY_MODE_ATTRIBUTE, "")):
        mode = point["attrs"].get(DELIVERY_MODE_ATTRIBUTE, "?")
        extra = ""
        if mode == "NPCApproach":
            extra = "   visitor waits at (%.1f, %.1f)" % (
                point["p"][0] + point["look"][0] * NPC_APPROACH_STUDS,
                point["p"][2] + point["look"][2] * NPC_APPROACH_STUDS,
            )
        print("   %-12s %-14s at (%.1f, %.1f)%s%s"
              % (mode, point["name"], point["p"][0], point["p"][2],
                 extra, _facings(facings, point)))

    if failures:
        print("\nFAILED: " + ", ".join(failures))
        return 1
    print("\nOK")
    return 0


# ---------------------------------------------------------------------------
# spawn
# ---------------------------------------------------------------------------

def command_spawn():
    room = house_plan.A
    obstacles, floors = _clearance_field(room.floor)
    ax, az = EVENT_ANCHOR

    def path_clear(x, z):
        # Clearance at the spawn alone is not enough — the point of the spawn
        # is the crawl, and the crawl has to be possible.
        return walk_clear(obstacles, (x, z), (ax, az), _WALK_RADIUS, INTERACT_RADIUS)

    project = json.loads(PROJECT.read_text())
    current = project["tree"]["Workspace"]["SpawnLocation"]["$properties"]["Position"]
    cx, cz = current[0], current[2]
    crawl = math.hypot(cx - ax, cz - az) - INTERACT_RADIUS
    print("spawn in default.project.json: (%.1f, %.1f)" % (cx, cz))
    print("   clearance %.2f studs" % clearance(obstacles, cx, cz))
    print("   standable: %s" % ("yes" if standable(floors, cx, cz) else "NO — not over a floor"))
    print("   crawl to the anchor: %.1f studs before it fires" % crawl)
    print("   path to the anchor: %s" % ("clear" if path_clear(cx, cz) else "BLOCKED"))

    print("\nalternatives in %s (clearance, crawl, position):" % room.name)
    candidates = []
    x = room.x0 + 1.0
    while x < room.x1 - 1.0:
        z = room.z0 + 1.0
        while z < room.z1 - 1.0:
            if standable(floors, x, z):
                c = clearance(obstacles, x, z)
                d = math.hypot(x - ax, z - az) - INTERACT_RADIUS
                if c >= 2.6 and 9.0 <= d <= 15.0 and path_clear(x, z):
                    candidates.append((c, d, x, z))
            z += 0.25
        x += 0.25
    candidates.sort(key=lambda t: (-t[0], -t[1]))
    if not candidates:
        print("   none — no spot has 2.6 studs of clearance and a 9-15 stud crawl")
    for c, d, x, z in candidates[:10]:
        print("   clearance %.2f  crawl %5.1f studs  at (%.1f, %.1f)" % (c, d, x, z))
    return 0


# ---------------------------------------------------------------------------
# space
# ---------------------------------------------------------------------------

# Resolution of the floor sampling grid, in studs. Half a stud is finer than any
# gap that matters and still cheap to sweep.
_GRID = 0.5
# How much of a room's walkable floor has to be in one connected piece. Short of
# this the room has a pocket you can see but not reach, which is what a sofa
# spanning a room does — and what raw floor area completely fails to notice.
_MIN_REACHABLE = 0.97


def command_space():
    """How much of each room you can actually walk, and what is taking it up.

    `check` only proves nothing overlaps. A room can pass that and still be
    miserable, so this measures the two things you feel: how much floor is left,
    and whether that floor is one connected space or several pockets separated
    by furniture you cannot squeeze past.

    Floor area alone is the wrong target — a bedroom is mostly bed and a galley
    kitchen is mostly counter, and neither is a problem. Reachability is the
    part that actually breaks a room.
    """
    furniture = load(FURNITURE)
    problems = 0

    for room in ROOMS:
        # Only things at body height take space away. A rug is floor you can
        # walk on and a pendant is over your head; neither crowds the room.
        standing = [
            p for p in furniture
            if room.contains(p["x0"], p["x1"], p["z0"], p["z1"], p["y0"])
            and p["y1"] > room.floor + 0.4
            and p["y0"] < room.floor + 4.0
        ]

        nx = max(int((room.x1 - room.x0) / _GRID), 1)
        nz = max(int((room.z1 - room.z0) / _GRID), 1)
        solid = [[False] * nz for _ in range(nx)]
        for ix in range(nx):
            x = room.x0 + (ix + 0.5) * _GRID
            for iz in range(nz):
                z = room.z0 + (iz + 0.5) * _GRID
                solid[ix][iz] = any(
                    p["x0"] <= x <= p["x1"] and p["z0"] <= z <= p["z1"] for p in standing
                )

        open_cells = sum(1 for ix in range(nx) for iz in range(nz) if not solid[ix][iz])
        clear = open_cells / (nx * nz)

        # Erode by a body's width. What survives is floor you can stand on
        # without clipping a wall or a wardrobe.
        reach = int(math.ceil(_BODY_RADIUS / _GRID))
        walkable = set()
        for ix in range(nx):
            for iz in range(nz):
                if solid[ix][iz]:
                    continue
                # Outside the grid counts as solid: that is the room's wall.
                if ix < reach or iz < reach or ix >= nx - reach or iz >= nz - reach:
                    continue
                if all(
                    not solid[ix + dx][iz + dz]
                    for dx in range(-reach, reach + 1)
                    for dz in range(-reach, reach + 1)
                ):
                    walkable.add((ix, iz))

        # Flood fill the walkable floor. More than one region means somewhere in
        # this room is cut off from somewhere else in it.
        seen, regions = set(), []
        for start in walkable:
            if start in seen:
                continue
            stack, region = [start], 0
            seen.add(start)
            while stack:
                cx, cz = stack.pop()
                region += 1
                for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nxt = (cx + dx, cz + dz)
                    if nxt in walkable and nxt not in seen:
                        seen.add(nxt)
                        stack.append(nxt)
            regions.append(region)
        regions.sort(reverse=True)
        reachable = regions[0] / len(walkable) if walkable else 0.0

        footprint = defaultdict(float)
        for p in standing:
            footprint[p["group"]] = max(
                footprint[p["group"]],
                (p["x1"] - p["x0"]) * (p["z1"] - p["z0"]),
            )

        broken = not walkable or reachable < _MIN_REACHABLE
        problems += broken
        print(
            "%-16s %5.0f sq studs   %3.0f%% clear   walkable in %d piece%s%s"
            % (
                room.name,
                (room.x1 - room.x0) * (room.z1 - room.z0),
                clear * 100,
                len(regions),
                "" if len(regions) == 1 else "s",
                "   <- SPLIT" if broken else "",
            )
        )
        pieces = sorted(footprint.items(), key=lambda kv: -kv[1])
        print("      %d pieces: %s" % (
            len(pieces),
            ", ".join("%s %.0f" % (n, a) for n, a in pieces[:10]) or "none",
        ))

    print(
        "\n%d room(s) with floor you cannot walk between (body width %.1f studs)"
        % (problems, _BODY_RADIUS * 2)
    )
    return 1 if problems else 0


# ---------------------------------------------------------------------------
# street — can you get out of the house, and into the buildings
# ---------------------------------------------------------------------------

# Everything above this file measures is a rate: what share of the house can fan
# a set of choices, what share can stage a parent. None of that applies outside.
# A street either lets you walk from your own front door to the school or it does
# not, and a street that fails that has not been built no matter how much of it
# exists. So the measure out here is a route, and a route is a boolean.

# Anything whose top is less than this above the surface being walked is
# something you step onto rather than into. A kerb is half a stud and a humanoid
# takes it without breaking stride; counted as an obstacle it would report the
# road as walled off from the sidewalk along its entire length.
_STEP_OVER = 0.8
# How far below a route's stated floor a surface may sit and still be the thing
# holding the player up. The walk out of the front door crosses the hall at
# 1.05, the garden path at 1.22 and the sidewalk at 1.52 without the player ever
# feeling a step, and one route spanning three heights is the honest unit.
_FLOOR_TOLERANCE = 1.0
# How finely a route is sampled, in samples per stud. Four is a sample every
# quarter stud, which is finer than any gap a body could slip through.
_ROUTE_SAMPLES = 4.0

_STREET_FIELDS = {}


def _street_field(level_y):
    """Obstacles and standable ground at one height, for the world outside.

    Reads the house and its furniture too, because the first route this has to
    prove starts in the hall. A street that is clear from the gate onward and
    blocked at the door has failed at the only place it mattered.
    """
    cached = _STREET_FIELDS.get(level_y)
    if cached is not None:
        return cached

    parts = [p for p in load(STREET) if not p["tags"]]
    parts += load(HOUSE)
    parts += [p for p in load(FURNITURE) if not p["tags"]]
    solid = [p for p in parts if p["collide"]]

    obstacles = [
        (p["x0"], p["x1"], p["z0"], p["z1"])
        for p in solid
        if p["y0"] < level_y + 3.0 and p["y1"] > level_y + _STEP_OVER
    ]
    floors = [
        (p["x0"], p["x1"], p["z0"], p["z1"])
        for p in solid
        if abs(p["y1"] - level_y) < _FLOOR_TOLERANCE
        and p["ext"][0] * p["ext"][2] > 20 and p["ext"][1] < 3
    ]
    _STREET_FIELDS[level_y] = (obstacles, floors)
    return obstacles, floors


def _route_pinch(obstacles, waypoints):
    """The narrowest half-width along a chain of straight segments, and where.

    Straight lines rather than pathfinding, for the reason walk_clear gives and
    one more: a route this reports as clear is one that stays clear when a bench
    is added, because there is nothing clever in it to be fooled.
    """
    worst, at = 99.0, waypoints[0]
    for (sx, sz), (ex, ez) in zip(waypoints, waypoints[1:]):
        distance = math.hypot(ex - sx, ez - sz)
        steps = max(int(distance * _ROUTE_SAMPLES), 1)
        for i in range(steps + 1):
            t = i / steps
            px, pz = sx + (ex - sx) * t, sz + (ez - sz) * t
            room = clearance(obstacles, px, pz)
            if room < worst:
                worst, at = room, (px, pz)
    return worst, at


def _route_rows():
    """[(name, floor, pinch, where, unsupported waypoints)] for every route."""
    rows = []
    for name, floor, waypoints in ROUTES:
        obstacles, floors = _street_field(floor)
        pinch, where = _route_pinch(obstacles, waypoints)
        unsupported = [w for w in waypoints if not standable(floors, *w)]
        rows.append((name, floor, pinch, where, unsupported))
    return rows


def _route_faults(rows):
    faults = []
    for name, _, pinch, where, unsupported in rows:
        if pinch < ROUTE_RADIUS:
            faults.append(
                "%-26s pinches to %.2f studs at (%.1f, %.1f), needs %.2f"
                % (name, pinch, where[0], where[1], ROUTE_RADIUS)
            )
        for wx, wz in unsupported:
            faults.append(
                "%-26s turns at (%.1f, %.1f) with no ground under it" % (name, wx, wz)
            )
    return faults


def _place_rows():
    """[(id, label, point or None, room or None, clearance, standable)]."""
    points = {}
    duplicates = []
    for p in load(STREET):
        if PLACE_TAG not in p["tags"]:
            continue
        place_id = p["attrs"].get(PLACE_ID_ATTRIBUTE)
        if place_id is None:
            duplicates.append((None, p))
        elif place_id in points:
            duplicates.append((place_id, p))
        else:
            points[place_id] = p

    rows = []
    for place_id, x, z, floor, label in PLACE_POINTS:
        point = points.pop(place_id, None)
        obstacles, floors = _street_field(floor)
        room = None
        for place in PLACES:
            if place.contains(x, x, z, z, floor):
                room = place
                break
        rows.append((place_id, label, point, room,
                     clearance(obstacles, x, z), standable(floors, x, z), (x, z)))
    return rows, points, duplicates


def _place_faults(rows, orphans, duplicates):
    faults = []
    # Being in no Place is not a fault: the forecourt points stand on paving
    # that no room covers, which is correct. Standing room is, and so is the
    # plan and the model disagreeing about which points exist at all.
    for place_id, _, point, _room, space, ground, (x, z) in rows:
        if point is None:
            faults.append('the plan names "%s" and nothing in the model carries it' % place_id)
            continue
        if not ground:
            faults.append('"%s" at (%.1f, %.1f) has no ground under it' % (place_id, x, z))
        if space < _BODY_RADIUS:
            faults.append('"%s" at (%.1f, %.1f) has %.2f studs of room, needs %.2f'
                          % (place_id, x, z, space, _BODY_RADIUS))
    for place_id in sorted(orphans):
        faults.append('the model carries "%s", which the plan does not name' % place_id)
    for place_id, p in duplicates:
        if place_id is None:
            faults.append("%-16s is tagged as a place and names no place" % p["name"])
        else:
            faults.append('two place points answer to "%s"' % place_id)
    return faults


def _stair_headroom():
    """The least clear height over any tread, and where it was measured.

    The one part of this world a flat clearance sweep cannot speak about. A
    flight of steps reads as a wall to something measuring at knee height, which
    is the right answer for a flat sweep and the wrong answer about a stair, so
    the stair is checked as what it is: sixteen surfaces you stand on, each of
    which has to have a head's worth of nothing above it.
    """
    parts = [p for p in load(STREET) if p["collide"] and not p["tags"]]
    worst, at = 99.0, None
    xs = (STAIR_X0 + 1.0, (STAIR_X0 + STAIR_X1) / 2, STAIR_X1 - 1.0)
    for i in range(STAIR_STEPS):
        top = FLOOR_1 + (i + 1) * STAIR_RISE
        z = STAIR_Z0 + (i + 0.5) * STAIR_GOING
        for x in xs:
            above = 99.0
            for p in parts:
                if p["x0"] < x < p["x1"] and p["z0"] < z < p["z1"] and p["y0"] >= top - 0.05:
                    above = min(above, p["y0"] - top)
            if above < worst:
                worst, at = above, (x, z)
    return worst, at


def _stair_faults(headroom, at):
    faults = []
    climb = STAIR_STEPS * STAIR_RISE
    storey = FLOOR_2 - FLOOR_1
    if abs(climb - storey) > 0.01:
        faults.append("the stair climbs %.2f studs to a floor %.2f studs up" % (climb, storey))
    run = STAIR_STEPS * STAIR_GOING
    if abs(run - (STAIR_Z1 - STAIR_Z0)) > 0.01:
        faults.append("the stair runs %.2f studs through a %.2f stud well"
                      % (run, STAIR_Z1 - STAIR_Z0))
    if STAIR_RISE > STAIR_MAX_RISE:
        faults.append("a rise of %.2f is over the %.2f bar" % (STAIR_RISE, STAIR_MAX_RISE))
    if STAIR_GOING < STAIR_MIN_GOING:
        faults.append("a going of %.2f is under the %.2f bar" % (STAIR_GOING, STAIR_MIN_GOING))
    if STAIR_WIDTH < ROUTE_RADIUS * 2:
        faults.append("the stair is %.2f studs wide, needs %.2f"
                      % (STAIR_WIDTH, ROUTE_RADIUS * 2))
    if abs((STAIR_X1 - STAIR_X0) - STAIR_WIDTH) > 0.01:
        faults.append("the stair well is %.2f studs wide and the stair says %.2f"
                      % (STAIR_X1 - STAIR_X0, STAIR_WIDTH))
    if headroom < MIN_HEADROOM:
        faults.append("only %.2f studs of headroom over the tread at (%.1f, %.1f), needs %.2f"
                      % (headroom, at[0], at[1], MIN_HEADROOM))
    return faults


def _street_sections():
    """Every street check, as (title, faults) pairs, for `street` and `check`."""
    route_rows = _route_rows()
    place_rows, orphans, duplicates = _place_rows()
    headroom, at = _stair_headroom()
    return (
        [
            ("routes (%d)" % len(route_rows), _route_faults(route_rows)),
            ("place points (%d)" % len(place_rows),
             _place_faults(place_rows, orphans, duplicates)),
            ("the stair (%d steps)" % STAIR_STEPS, _stair_faults(headroom, at)),
        ],
        route_rows,
        place_rows,
        headroom,
    )


def command_street():
    """Whether the world outside the front door can be walked.

    The failure this exists to catch is the one that cannot be seen from inside
    Studio without playing: a doorway a stud too narrow, or a slab that stops
    short of the wall it was meant to meet. Both look right from above and both
    end the game at the same place -- standing in a doorway, not going through.
    """
    sections, route_rows, place_rows, headroom = _street_sections()

    print("places in world_plan.py:")
    for place in PLACES:
        print("   %-18s x[%7.1f,%7.1f] z[%7.1f,%7.1f]  floor %6.2f  %s"
              % (place.name, place.x0, place.x1, place.z0, place.z1, place.floor,
                 "indoors" if place.indoors else "outdoors"))

    print("\nroutes (body half-width %.2f studs):" % ROUTE_RADIUS)
    for name, floor, pinch, where, unsupported in route_rows:
        note = ""
        if pinch < ROUTE_RADIUS:
            note = "   <- BLOCKED"
        elif unsupported:
            note = "   <- %d waypoint(s) over nothing" % len(unsupported)
        print("   %-26s floor %6.2f   tightest %5.2f at (%7.1f,%7.1f)%s"
              % (name, floor, pinch, where[0], where[1], note))

    print("\nplace points:")
    for place_id, label, point, room, space, ground, (x, z) in place_rows:
        print("   %-10s (%7.1f,%7.1f)  %-6s  room %-18s %5.2f studs of room   %s"
              % (place_id, x, z,
                 "found" if point is not None else "MISSING",
                 room.name if room is not None else "-",
                 space, label))
        if not ground:
            print("              no ground under it")

    print("\nthe stair: %d steps of %.2f rise and %.2f going, %.1f studs wide"
          % (STAIR_STEPS, STAIR_RISE, STAIR_GOING, STAIR_WIDTH))
    print("   climbs %.2f studs, from %.2f to %.2f"
          % (STAIR_STEPS * STAIR_RISE, FLOOR_1, FLOOR_2))
    print("   least headroom over a tread: %.2f studs (bar %.2f)" % (headroom, MIN_HEADROOM))

    print("")
    failed = []
    for title, faults in sections:
        print("%-42s %s" % (title + ":", len(faults) if faults else "clean"))
        for row in faults[:12]:
            print("      " + row)
        if len(faults) > 12:
            print("      ... and %d more" % (len(faults) - 12))
        if faults:
            failed.append(title)

    if failed:
        print("\nFAILED: " + ", ".join(failed))
        return 1
    print("\nOK")
    return 0


COMMANDS = {
    "plan": command_plan,
    "check": command_check,
    "spawn": command_spawn,
    "space": command_space,
    "pocket": command_pocket,
    "street": command_street,
}

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "check"
    if which not in COMMANDS:
        print(__doc__)
        sys.exit(2)
    sys.exit(COMMANDS[which]() or 0)
