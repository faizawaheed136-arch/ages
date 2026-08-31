#!/usr/bin/env python3
"""Generates assets/Versailles.rbxmx: Empty placeholder."""

import rbxmx
from rbxmx import SMOOTH
from rbxmx import box, group

from world_plan import GROUND, PLACE_TAG, PLACE_ID_ATTRIBUTE, PLACE_LABEL_ATTRIBUTE
from house_plan import _ASSETS

VERSAILLES = _ASSETS / "Versailles.rbxmx"
rbxmx.begin("RBXVERS")


def place_point(pid, x, z, floor, label):
    """Navigation waypoint."""
    box(f"Place_{pid}", (x - 1.0, x + 1.0, z - 1.0, z + 1.0,
                          floor, floor + 2.0),
        (255, 255, 255), SMOOTH, transparency=1.0, collide=False,
        tags=[PLACE_TAG],
        attrs={PLACE_ID_ATTRIBUTE: pid, PLACE_LABEL_ATTRIBUTE: label})


# ===========================================================================
# EMPTY - Just a single waypoint marking the palace site
# ===========================================================================

with group("VersaillesSite"):
    place_point("versailles_site", 400.0, 1600.0, GROUND, "Versailles palace site")


# ===========================================================================
# WRITE THE ASSET
# ===========================================================================

print(rbxmx.write(VERSAILLES, "Versailles"))