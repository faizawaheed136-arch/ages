#!/usr/bin/env python3
"""The floor plan of assets/House.rbxmx, transcribed by hand.

This exists so build_furniture.py and read_house.py cannot disagree about where
the rooms are. Placing furniture and checking furniture used to keep their own
copies of these numbers, which meant a room could be fixed in one and stay wrong
in the other.

The numbers are transcribed rather than computed because the house is an
imported model with no room markup in it. `read_house.py plan` prints the
geometry these were read off, so they can be re-checked whenever the building
is re-exported from Studio.
"""

from pathlib import Path

_ASSETS = Path(__file__).resolve().parent.parent / "assets"
HOUSE = _ASSETS / "House.rbxmx"
FURNITURE = _ASSETS / "Furniture.rbxmx"


class Room:
    """A real room, measured off the house. x0/x1 and z0/z1 are the inside
    faces of its walls, floor is the surface furniture stands on, and ceiling is
    what lights hang from — all four vary per room in this building."""

    def __init__(self, name, x0, x1, z0, z1, floor, ceiling):
        self.name = name
        self.x0, self.x1, self.z0, self.z1 = x0, x1, z0, z1
        self.floor, self.ceiling = floor, ceiling

    def wall(self, side, along):
        """Pivot for a piece standing with its back on `side`, positioned
        `along` the wall (an x for north/south walls, a z for east/west)."""
        if side == "north":
            return (along, self.z0)
        if side == "south":
            return (along, self.z1)
        if side == "west":
            return (self.x0, along)
        if side == "east":
            return (self.x1, along)
        raise ValueError(side)

    def contains(self, x0, x1, z0, z1, y0, tolerance=0.15):
        """Whether a part sits inside these walls, on this storey.

        Height is part of the test because rooms stack: the main bedroom's
        footprint sits entirely inside the hall's, so a plan-only match hands
        every upstairs piece to the room underneath it. The tolerance absorbs
        pieces authored flush against a wall, which land a hair outside it.
        """
        return (
            x0 >= self.x0 - tolerance
            and x1 <= self.x1 + tolerance
            and z0 >= self.z0 - tolerance
            and z1 <= self.z1 + tolerance
            and self.floor - 1.0 <= y0 <= self.ceiling + tolerance
        )


# Ground floor.
# Room A's west wall is glazed end to end, and its north wall carries a door at
# x -6.3 plus windows over x -12.6..-6.7 and x 12.8..25.5, which leaves the
# south wall and the east end as the only places anything tall can go.
A = Room("nursery/living", -12.5, 29.5, -27.5, -15.5, 1.037, 13.8)
# West wall: window over z 1.2..7.1 and a door at z -4.9. Stairs land in
# x 21.5..31 by z -5.5..3.5 and are left completely alone.
B = Room("hall/dining", 4.0, 30.0, -10.0, 7.0, 1.048, 14.7)
C = Room("kitchen", 4.0, 17.0, 9.0, 19.0, 1.103, 13.7)
D = Room("bathroom", 20.0, 30.0, 8.0, 20.0, 1.265, 13.8)
# Upper floor, vaulted to the roof. U2 stops at z 6.5 because the house is
# solid from there south; the floor drawn beyond it is the top of a mass, not a
# room, which is what an earlier pass mistook for a corridor.
U1 = Room("main bedroom", 4.0, 19.0, -9.0, 7.0, 17.356, 30.9)
U2 = Room("landing", -6.0, 2.0, -9.0, 6.5, 17.204, 30.5)
U3 = Room("child's room", 4.0, 30.0, 9.0, 19.0, 17.356, 31.1)

ROOMS = [A, B, C, D, U1, U2, U3]

# Footprints nothing may stand in. Doorways are the only routes between rooms
# and the staircase is the only route between floors, so a piece that overlaps
# one of these can strand the player rather than merely look wrong.
KEEP_CLEAR = {
    "A <-> B doorway": (4.0, 16.0, -16.5, -14.0),
    "B <-> C doorway": (7.5, 13.5, 8.0, 10.0),
    "staircase": (21.5, 31.0, -5.5, 3.5),
}

# Where the toddler's first event fires, and how close the player has to get.
# Mirrors Config.InteractRadius; read_house.py uses it to measure the crawl.
EVENT_ANCHOR = (-4.0, -21.5)
INTERACT_RADIUS = 6.0

# Where the world is allowed to put something it brings you: the mat the post
# lands on, the phone that rings, the doorstep a caller stands on. These mirror
# Config.World.DeliveryPointTag / DeliveryPointAttribute and the Ambient modes in
# Types.EventDelivery.
#
# Mirrored rather than shared because one side is Luau and the other is Python.
# The cost of that is what read_house.py buys back: it fails when a mode has
# nowhere in the house to happen, so a missing doormat is a failed check rather
# than a warning nobody reads in the output window an hour into a play session.
DELIVERY_TAG = "AgesDeliveryPoint"
DELIVERY_MODE_ATTRIBUTE = "DeliveryMode"
DELIVERY_MODES = ("Letter", "PhoneCall", "NPCApproach")

# Mirrors Config.NPC.ApproachStuds. A visitor spawns on the doorstep marker and
# walks this far straight along its facing before stopping, so where they end up
# is decided by turning the marker rather than by anything in code — which means
# the spot they stop on is a property of the house and can be checked here.
NPC_APPROACH_STUDS = 6.0
