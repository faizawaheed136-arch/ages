#!/usr/bin/env python3
"""Generates assets/SchoolFurniture.rbxmx: hand-placed interact anchors and
their decoy props for the four school life events.

Run from tools/:  python3 build_school_furniture.py

The anchors are invisible, tagged parts that WorldEventService reads every tick.
The decoys are visible stand-ins — lockers, a fountain, a notice board, a
bookshelf — that a builder can later swap for real art without touching the
event wiring. Each anchor lives inside its decoy's model so a replacement
preserves the tag and attribute automatically.
"""

from pathlib import Path

import rbxmx
from rbxmx import box, group, part, piece
from house_plan import _ASSETS

rbxmx.begin("RBXSCHOOL")

# Palette: school-appropriate, blocky, swappable.
LOCKER_BLUE = (82, 114, 168)
FOUNTAIN_GREY = (168, 172, 176)
BOARD_BROWN = (168, 124, 82)
SHELF_OAK = (168, 124, 82)
WHITE = (245, 243, 238)

# --------------------------------------------------------------------------
# Decoy props, each carrying one invisible AgesEvent anchor inside it.
# --------------------------------------------------------------------------

@piece("NoticeBoard")
def notice_board(x, z):
    """A pinned board on the lobby wall. The anchor sits at face height in the
    middle of the board — the place a player looks at when they walk up to it."""
    part("BoardFace", (x - 0.05, 5.5, z - 2.0),
         (0.1, 5.0, 4.0), BOARD_BROWN, rbxmx.WOOD)
    part("BoardTop", (x - 0.1, 8.0, z),
         (0.2, 0.2, 4.2), (120, 80, 50), rbxmx.WOOD)
    part("BoardBottom", (x - 0.1, 3.0, z),
         (0.2, 0.2, 4.2), (120, 80, 50), rbxmx.WOOD)
    part("NoticeBoardEventAnchor", (x + 0.05, 5.5, z),
         (0.5, 2.0, 1.5), WHITE, rbxmx.PLASTIC,
         transparency=1.0, collide=False,
         tags=["AgesEvent"], attrs={"EventId": "school_notice_board"})


@piece("WaterFountain")
def water_fountain(x, z):
    """A wall-mounted fountain in the corridor. The anchor sits at the spout
    height where a player would reach to drink."""
    part("FountainBody", (x - 0.1, 3.5, z),
         (0.2, 2.5, 1.2), FOUNTAIN_GREY, rbxmx.METAL)
    part("FountainBasin", (x - 0.15, 2.5, z),
         (0.3, 0.3, 1.4), FOUNTAIN_GREY, rbxmx.METAL)
    part("FountainSpout", (x - 0.25, 4.5, z),
         (0.4, 0.3, 0.3), FOUNTAIN_GREY, rbxmx.METAL)
    part("WaterFountainEventAnchor", (x + 0.15, 4.0, z),
         (0.8, 1.5, 0.8), WHITE, rbxmx.PLASTIC,
         transparency=1.0, collide=False,
         tags=["AgesEvent"], attrs={"EventId": "school_water_fountain"})


@piece("Locker")
def locker(x, z):
    """A row locker against the classroom wall. The anchor sits at the grille
    height where a note would be slipped through."""
    part("LockerBody", (x - 0.3, 4.5, z),
         (0.6, 7.0, 1.5), LOCKER_BLUE, rbxmx.METAL)
    part("LockerDoor", (x - 0.05, 4.5, z),
         (0.1, 7.0, 1.3), (70, 100, 148), rbxmx.METAL)
    part("LockerGrille", (x - 0.05, 5.5, z),
         (0.1, 1.0, 1.0), (50, 70, 100), rbxmx.METAL, collide=False)
    part("LockerEventAnchor", (x + 0.25, 5.5, z),
         (0.5, 1.2, 0.8), WHITE, rbxmx.PLASTIC,
         transparency=1.0, collide=False,
         tags=["AgesEvent"], attrs={"EventId": "school_locker_note"})


@piece("Bookshelf")
def bookshelf(x, z):
    """A library bookshelf against the classroom wall. The anchor sits on the
    shelf at the level a child would reach for a book."""
    part("ShelfSideLeft", (x - 0.25, 2.0, z - 1.0),
         (0.15, 5.0, 0.15), SHELF_OAK, rbxmx.WOOD)
    part("ShelfSideRight", (x - 0.25, 2.0, z + 1.0),
         (0.15, 5.0, 0.15), SHELF_OAK, rbxmx.WOOD)
    part("ShelfTop", (x - 0.25, 4.5, z),
         (0.15, 0.15, 2.15), SHELF_OAK, rbxmx.WOOD)
    part("ShelfBottom", (x - 0.25, 0.5, z),
         (0.15, 0.15, 2.15), SHELF_OAK, rbxmx.WOOD)
    for y_offset in (1.5, 2.8, 3.8):
        part(f"ShelfBoard{y_offset}", (x - 0.25, y_offset, z),
             (0.15, 0.1, 2.0), SHELF_OAK, rbxmx.WOOD)
    for i, (bx, by, bz, bc) in enumerate([
        (-0.15, 1.6, -0.6, (180, 60, 60)),
        (-0.15, 1.6, -0.3, (60, 100, 180)),
        (-0.15, 1.6, 0.0, (60, 160, 80)),
        (-0.15, 1.6, 0.3, (180, 160, 60)),
        (-0.15, 1.6, 0.6, (140, 60, 160)),
    ]):
        part(f"Book{i + 1}", (bx, by, bz),
             (0.1, 0.8, 0.4), bc, rbxmx.WOOD)
    part("BookshelfEventAnchor", (x + 0.15, 2.5, z),
         (0.5, 1.0, 1.0), WHITE, rbxmx.PLASTIC,
         transparency=1.0, collide=False,
         tags=["AgesEvent"], attrs={"EventId": "school_library_book"})


# --------------------------------------------------------------------------
# Placement. Each decoy+anchor pair lives in its room at the coordinates from
# Config.School.Anchors so the debug command can verify without re-reading.
# --------------------------------------------------------------------------

with group("SchoolFurniture"):
    with group("NoticeBoard"):
        notice_board(-114.0, 42.0)
    with group("WaterFountain"):
        water_fountain(-138.0, 48.0)
    with group("Locker"):
        locker(-150.0, 22.0)
    with group("Bookshelf"):
        bookshelf(-150.0, 43.0)

SCHOOL_FURNITURE = _ASSETS / "SchoolFurniture.rbxmx"
print(rbxmx.write(SCHOOL_FURNITURE, "SchoolFurniture"))
