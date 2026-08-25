#!/usr/bin/env python3
"""Writes .rbxmx models: the shared half of build_furniture.py and build_street.py.

Everything here was in build_furniture.py first, and moved out the day a second
generator needed it. Nothing about emitting a Part is furniture-specific, and two
copies of a rotation matrix table is exactly the kind of thing that ends up
disagreeing about which way east is.

The state is module-level rather than an object, which looks careless and is not:
the builders read as layout files -- `with against(A, "south", -8.0): crib()` --
and threading a writer through every one of those call sites would bury the plan
under the plumbing. One generator runs per process, so there is nothing for the
global to collide with. `begin()` at the top, `write()` at the bottom.

Two ways to place geometry, because two things are being built:

    part()   in a builder's own frame, for anything authored once and stood
             against a wall. dx across, dz forward from its back face, dy up
             from the floor to the part's underside. Which wall it ends up on is
             a quarter turn applied by `against`, so a sofa is never re-measured.

    box()    in world space, corner to corner. A road is not a piece of
             furniture placed in a room; it is a rectangle at a known place on
             the map, and expressing it as an offset from a pivot would be a
             translation nobody can check by eye.
"""

import base64
import html
import math
import struct
from contextlib import contextmanager

# Enum.Material tokens.
PLASTIC, SMOOTH, WOOD, PLANKS, FABRIC, METAL, NEON, MARBLE = 256, 272, 512, 528, 1312, 1088, 288, 784
CONCRETE, BRICK, SLATE, GLASS, ASPHALT, PAVEMENT = 816, 848, 800, 1568, 1376, 1232
GRASS, LEAFY_GRASS, PEBBLE, COBBLESTONE, LIMESTONE, GRANITE = 1280, 1284, 864, 880, 1216, 832
# The two the works district needs and nothing else in the world does: rusted
# sheet for a scrapyard and a silo, and tread plate for a loading dock. Kept
# here rather than approximated with METAL and a brown, because the whole point
# of the industrial palette is that it is the one district where a surface is
# allowed to look worn -- and METAL renders polished at any colour.
CORRODED_METAL, DIAMOND_PLATE = 1040, 1056

_items = []
_ref = 0
_prefix = "RBXITEM"
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

# Which face of a part a SurfaceGui is drawn on, by the world direction it ends
# up pointing once the quarter turn above has been applied. Enum.NormalId, and
# the mapping is the reason this is a dict rather than a number written at the
# call site: a sign is authored facing the way the building faces, and getting it
# wrong puts the school's name on the inside of its own wall.
FACE = {"front": 5, "back": 2, "top": 1, "bottom": 4, "right": 0, "left": 3}


def begin(prefix):
    """Starts a model. `prefix` seeds the referent ids, which have to be unique
    within a file and are easier to read when they say which file they are in."""
    global _items, _ref, _prefix, _parts, _ctx
    _items, _ref, _prefix, _parts, _ctx = [], 0, prefix, 0, (0.0, 0.0, 0, 0.0)


def write(path, root_name):
    """Wraps everything emitted so far in one Model and writes it out."""
    body = "\n".join(_items)
    path.write_text(f'''<roblox version="4">
<Item class="Model" referent="{_prefix}ROOT">
<Properties>
<string name="Name">{html.escape(root_name)}</string>
</Properties>
{body}
</Item>
</roblox>
''')
    return f"wrote {path} ({_parts} parts in {len(_items)} pieces)"


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


@contextmanager
def at(x, z, side="north", floor=0.0):
    """Like `free`, but for a spot on the map rather than in a room -- a bench on
    a sidewalk has a place and a facing but no walls to be measured from."""
    global _ctx
    previous = _ctx
    _ctx = (x, z, _BACK[side], floor)
    try:
        yield
    finally:
        _ctx = previous


def piece(label):
    """Wraps a builder so everything it emits lands in one Model.

    The grouping is not cosmetic. It is what lets the checker tell a sink set
    into a counter -- parts of one object, allowed to share space -- from a plant
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
<string name="Name">{html.escape(label)}</string>
</Properties>
{"".join(children)}
</Item>''')

        wrapped.__name__ = build.__name__
        wrapped.__doc__ = build.__doc__
        return wrapped

    return decorate


@contextmanager
def group(label):
    """The same grouping as `piece`, as a block rather than a decorator.

    A street is laid out as a sequence of regions rather than a catalogue of
    objects, so most of what it emits has no builder function to hang a decorator
    on. Same rule underneath: one Model per thing that could be replaced whole.
    """
    start = len(_items)
    try:
        yield
    finally:
        children = _items[start:]
        del _items[start:]
        _items.append(f'''<Item class="Model" referent="{_next_ref()}">
<Properties>
<string name="Name">{html.escape(label)}</string>
</Properties>
{"".join(children)}
</Item>''')


def _next_ref():
    global _ref
    _ref += 1
    return f"{_prefix}{_ref:04d}"


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


def _emit(name, x, y, z, sx, sy, sz, rot, color, material, transparency,
          collide, shape, tags, attrs, children):
    global _parts
    _parts += 1
    extra = ""
    if tags:
        extra += f'<BinaryString name="Tags">{_tags_blob(tags)}</BinaryString>'
    if attrs:
        extra += f'<BinaryString name="AttributesSerialize">{_attributes_blob(attrs)}</BinaryString>'

    _items.append(f'''<Item class="Part" referent="{_next_ref()}">
<Properties>
<string name="Name">{html.escape(name)}</string>
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


def part(name, offset, size, color, material=SMOOTH, transparency=0.0,
         collide=True, shape=1, upright_cylinder=False, tags=None, attrs=None,
         children=""):
    """offset is (dx, dy, dz) in the builder's own space: dx across, dz forward
    from its back face, and dy up from the floor to the part's underside."""
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

    _emit(name, x, y, z, sx, sy, sz, rot, color, material, transparency,
          collide, shape, tags, attrs, children)


def box(name, bounds, color, material=SMOOTH, transparency=0.0, collide=True,
        tags=None, attrs=None, children=""):
    """A world-space axis-aligned box, given as (x0, x1, z0, z1, y0, y1).

    Corners rather than centre-and-size because that is how the plan is written
    and how the checker reads it back: a road runs from one x to another, and a
    slab's top is a height somebody has to be able to compare against the height
    of the sidewalk beside it. Turning that into a centre and a size by hand is
    two subtractions and a division per part, done hundreds of times, and every
    one of them is a chance to put a wall half a stud into the ground.
    """
    x0, x1, z0, z1, y0, y1 = bounds
    _emit(name, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2,
          abs(x1 - x0), abs(y1 - y0), abs(z1 - z0), _TURN_MATRIX[0],
          color, material, transparency, collide, 1, tags, attrs, children)


def ball(name, center, size, color, material=SMOOTH, transparency=0.0, collide=True,
         tags=None, attrs=None, children=""):
    """A world-space ellipsoid (`Part.Shape` = Ball), centre and full size --
    the same size convention as `spun_box`, diameters rather than radii, so a
    caller measuring one against a `box()` next to it is comparing like units.

    Non-uniform size renders as a smooth ellipsoid, not a sphere stretched to
    fit -- which is what lets one part be shaped to a rectangular footprint
    instead of a circle dropped over it. Identity rotation, the same
    `_TURN_MATRIX[0]` `box()` already uses: a ball looks the same rotated or
    not, so there is no rotation-matrix arithmetic to get wrong here the way
    there would be for a tilted panel, which is why this is the shape the
    stadium's dome is built from (see `stadium_roof` in gen_city.py) rather
    than a stack of raked box terraces trying to approximate the same curve.
    """
    cx, cy, cz = center
    sx, sy, sz = size
    _emit(name, cx, cy, cz, abs(sx), abs(sy), abs(sz), _TURN_MATRIX[0],
          color, material, transparency, collide, 0, tags, attrs, children)


def spun_box(name, center, size, yaw, color, material=SMOOTH, transparency=0.0,
             collide=True, tags=None, attrs=None, children=""):
    """A world-space box spun `yaw` degrees about Y, given centre-and-size.

    The fourth way to place geometry, and the only one that is not a rectangle
    on the grid. `box` is corner-to-corner because a road running north is two
    x's and two z's and anything else would be unreadable -- but a road running
    round a circle is not describable that way at all, and neither is a tower
    set at an angle to the grid. Those want a centre, a size and an angle.

    Positive yaw turns the +X axis toward +Z, which is the same handedness the
    quarter turns in `_TURN_OFFSET` use, so `spun_box(..., yaw=90)` and a piece
    emitted under `at(..., side="west")` agree about which way they have turned.

    The corner-to-corner form stays the default for everything on the grid. This
    is for the things that are not: use it and the axis-aligned bounding box a
    checker reads back is larger than the part, which is true, but it means two
    angled parts can be reported as overlapping when they do not. check_city.py
    reads the rotation back and does a proper separating-axis test for exactly
    that reason -- if you add another checker, do the same or stay on the grid.
    """
    cx, cy, cz = center
    sx, sy, sz = size
    rad = math.radians(yaw)
    c, s = math.cos(rad), math.sin(rad)
    rot = (f"<R00>{c}</R00><R01>0</R01><R02>{s}</R02>"
           f"<R10>0</R10><R11>1</R11><R12>0</R12>"
           f"<R20>{-s}</R20><R21>0</R21><R22>{c}</R22>")
    _emit(name, cx, cy, cz, abs(sx), abs(sy), abs(sz), rot,
          color, material, transparency, collide, 1, tags, attrs, children)


def tilted_box(name, center, size, yaw, pitch, color, material=SMOOTH,
                transparency=0.0, collide=True, tags=None, attrs=None,
                children=""):
    """A world-space box spun `yaw` degrees about Y like `spun_box`, and then
    banked `pitch` degrees so its own local X axis (depth/outward) climbs
    toward local Y (up) -- the panel this file reaches for when a surface is
    curved in *two* directions at once, not one, which `spun_box`'s single
    rotation cannot reach (its local X always stays level). Built for the
    stadium's dome (see `dome_shell` in gen_city.py): a lat/long grid of
    these, each banked to its own point's true surface normal, is what a
    dome actually is with box primitives -- the panels of a faceted glass
    roof, not a stepped terrace stack and not a full sphere half-buried
    for the sake of a smooth top half no primitive here can cut in two.

    At pitch=0 this is exactly `spun_box`; the two are meant to agree there,
    since `pitch` composes as a second rotation about the *already-yawed*
    local Z axis (width, tangential) -- the axis a dome panel's own row and
    column both hold fixed as it banks from the rim toward the pole.
    """
    cx, cy, cz = center
    sx, sy, sz = size
    yr, pr = math.radians(yaw), math.radians(pitch)
    cy_, sy_ = math.cos(yr), math.sin(yr)
    cp, sp = math.cos(pr), math.sin(pr)
    r00, r10, r20 = cp * cy_, sp, -cp * sy_
    r01, r11, r21 = -sp * cy_, cp, sp * sy_
    r02, r12, r22 = sy_, 0.0, cy_
    rot = (f"<R00>{r00}</R00><R01>{r01}</R01><R02>{r02}</R02>"
           f"<R10>{r10}</R10><R11>{r11}</R11><R12>{r12}</R12>"
           f"<R20>{r20}</R20><R21>{r21}</R21><R22>{r22}</R22>")
    _emit(name, cx, cy, cz, abs(sx), abs(sy), abs(sz), rot,
          color, material, transparency, collide, 1, tags, attrs, children)


def point_light(color, brightness, rng, name="Glow"):
    r, g, b = [c / 255 for c in color]
    return f'''<Item class="PointLight" referent="{_next_ref()}">
<Properties>
<string name="Name">{html.escape(name)}</string>
<Color3 name="Color"><R>{r}</R><G>{g}</G><B>{b}</B></Color3>
<float name="Brightness">{brightness}</float>
<float name="Range">{rng}</float>
<bool name="Shadows">true</bool>
<bool name="Enabled">true</bool>
</Properties>
</Item>'''


def spot_light(color, brightness, rng, face, angle=90.0, name="Spot"):
    """A directional cone, cast from one face of whatever part it is nested in
    (`children=spot_light(...)`) via `box`/`part`'s own `children` parameter --
    the same way a `PointLight` is hung off a fitting in `point_light` above.

    `face` is one of the strings in the module-level `FACE` map (`"front"`,
    `"bottom"`, ...), not a raw NormalId, so a floodlight is written the same
    way a sign's face is: by which way the part is turned, not by a number
    that means nothing without this file open beside it. Everything in this
    codebase that needs a cone rather than a glow -- a stadium floodlight
    aimed down at a pitch, a headlamp aimed along a road -- casts from a
    fitting's own face rather than carrying a separate aim vector, because a
    part already has a face pointed the right way once it is placed.
    """
    r, g, b = [c / 255 for c in color]
    return f'''<Item class="SpotLight" referent="{_next_ref()}">
<Properties>
<string name="Name">{html.escape(name)}</string>
<Color3 name="Color"><R>{r}</R><G>{g}</G><B>{b}</B></Color3>
<float name="Brightness">{brightness}</float>
<float name="Range">{rng}</float>
<float name="Angle">{angle}</float>
<token name="Face">{FACE[face]}</token>
<bool name="Shadows">true</bool>
<bool name="Enabled">true</bool>
</Properties>
</Item>'''


# Enum.Font. Deliberately not the GothamBold every label in the game is set in:
# the Gotham tokens have been renumbered more than once, this file is written
# blind and a token Roblox does not recognise drops the whole property rather
# than falling back to a different typeface. A building's name is worth less than
# the certainty that it appears at all.
SOURCE_SANS_BOLD = 4


def sign(text, face, color=(255, 255, 255), size=48, width=800, height=200,
         font=SOURCE_SANS_BOLD):
    """Lettering painted on one face of a part, as a child of that part.

    A blocky world can carry a name without art, and a street where the buildings
    are not labelled is a street where the player has to walk into a building to
    find out what it is.

    `face` is a key of FACE and is stated in world terms by the caller, because
    the quarter turn that puts a sign board on a wall also turns its faces, and
    the only reader who can keep that straight is the one writing the layout.
    """
    r, g, b = [c / 255 for c in color]
    escaped = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return f'''<Item class="SurfaceGui" referent="{_next_ref()}">
<Properties>
<string name="Name">Sign</string>
<token name="Face">{FACE[face]}</token>
<bool name="AlwaysOnTop">false</bool>
<token name="SizingMode">0</token>
<Vector2 name="CanvasSize"><X>{width}</X><Y>{height}</Y></Vector2>
<float name="LightInfluence">0</float>
<bool name="Enabled">true</bool>
</Properties>
<Item class="TextLabel" referent="{_next_ref()}">
<Properties>
<string name="Name">Text</string>
<UDim2 name="Size"><XS>1</XS><XO>0</XO><YS>1</YS><YO>0</YO></UDim2>
<UDim2 name="Position"><XS>0</XS><XO>0</XO><YS>0</YS><YO>0</YO></UDim2>
<float name="BackgroundTransparency">1</float>
<string name="Text">{escaped}</string>
<token name="Font">{font}</token>
<bool name="TextScaled">false</bool>
<float name="TextSize">{size}</float>
<Color3 name="TextColor3"><R>{r}</R><G>{g}</G><B>{b}</B></Color3>
<token name="TextXAlignment">2</token>
<token name="TextYAlignment">1</token>
</Properties>
</Item>
</Item>'''
