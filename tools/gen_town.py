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

import math

import rbxmx
from rbxmx import (
    ASPHALT, BRICK, CONCRETE, CORRODED_METAL, FABRIC, GLASS, GRASS, LEAFY_GRASS,
    MARBLE, METAL, NEON, PEBBLE, PLASTIC, PLANKS, SLATE, SMOOTH, WOOD,
)
from rbxmx import at, box, group, part, point_light, sign

from world_plan import (
    ALLEYS, ALLEY_MARGIN, ALLEY_MIN, ALLEY_WIDTH, alley_slug, clear_of_alleys,
    BAKERY_DOOR, BAKERY_X0, BAKERY_X1, BAKERY_Z0, BAKERY_Z1,
    CAFE_DOOR, CAFE_X0, CAFE_X1, CAFE_Z0, CAFE_Z1,
    CEIL_1, CLINIC_DOOR, CLINIC_X0, CLINIC_X1, CLINIC_Z0, CLINIC_Z1,
    DOORWAY, DOOR_LINE, FAR_WALK_X0, FAR_WALK_X1, FLOOR_1,
    FORECOURT_X0,
    FRONT_X, GARAGE_DOOR, GARAGE_X0, GARAGE_X1, GARAGE_Z0, GARAGE_Z1,
    GATE_CLEAR, GROUND, GYM_DOOR, GYM_X0, GYM_X1, GYM_Z0, GYM_Z1,
    HALL_DOOR, HALL_X0, HALL_X1, HALL_Z0, HALL_Z1,
    LIB_DEPTH, LIB_DOOR, LIB_X0, LIB_X1, LIB_Z0, LIB_Z1,
    NEAR_WALK_X0, NEAR_WALK_X1, PAVING,
    PLACE_ID_ATTRIBUTE, PLACE_LABEL_ATTRIBUTE, PLACE_TAG, PROPERTY_X,
    MAP_SOUTH_EDGE,
    NORTHGATE_CLEAR, NORTHGATE_MID, NORTHGATE_WALK, NORTHGATE_Z0, NORTHGATE_Z1,
    ROAD_MID, ROAD_X0, ROAD_X1, SLAB, SOUTHGATE_CLEAR, STORE_DEPTH,
    STREET_Z0, STREET_Z1, WEST_FRONTAGE, WEST_GAP,
    WALL,
)

from house_plan import _ASSETS

TOWN = _ASSETS / "Town.rbxmx"

rbxmx.begin("RBXTOWN")

# ---------------------------------------------------------------------------
# Plan
# ---------------------------------------------------------------------------

# Where the new ground starts. The original street ran Z -132..132; the town
# continues the same bands outward from there.
#
# The south edge is not chosen. It used to be a typed -328, which left the town
# ending 172 studs north of the city's own southern boundary -- so the bottom of
# the map was a straight line on one side and stopped early on the other, and
# nothing in either file could see it because neither knew the other's edge.
# MAP_SOUTH_EDGE is the works apron's south face, transcribed into world_plan.py
# and asserted against `WORKS_Z0` in gen_city.py the moment either moves.
#
# The north edge is not chosen either, and used to be. It was a typed 232, which
# is where the grass happened to stop, and the road stopped there with it -- the
# main street ran north past the library and ended in a field. NORTHGATE_CLEAR
# is the northern link's band plus its pavements, so the town's ground now ends
# where the road out of it ends, and moving the link moves the map.
NORTH_Z0 = STREET_Z1                            # 132
NORTH_Z1 = NORTHGATE_CLEAR[1]                   # 339
SOUTH_Z0, SOUTH_Z1 = MAP_SOUTH_EDGE, STREET_Z0  # -500..-132

# East of the player's own plot the corridor opens out. The near sidewalk ends
# at the property line; from there the ground is the town's until it runs into
# the field on the far side of the new houses.
EAST_X0 = PROPERTY_X                            # -52.6
EAST_X1 = 8.0
EAST_Z0, EAST_Z1 = SOUTH_Z0, NORTH_Z1           # -500..232

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
# buildings on its far side. Where it runs out is WEST_EDGE, in "the back
# street" below -- it used to be a typed -280 chosen to look wide enough, and it
# is now the far side of the row that stands on it.
# How far south the far sidewalk runs before it hands the kerb back to the road.
FAR_END_Z = -280.0
# The width of a sidewalk band, used to size the return leg's own sidewalk.
SIDEWALK = FAR_WALK_X1 - FAR_WALK_X0

# The nine buildings of the west frontage -- the seven this file draws and the
# school and workplace that build_street.py does -- are declared together in
# world_plan.py. See WEST_FRONTAGE there for why they cannot live in the file
# that happens to draw them.

# The same check the corner shop gets against the gate road, for the same
# reason: the northern link is drawn in gen_city.py, in another asset, and the
# only thing standing between a building and a road through its roof is this
# file holding the road's band as a fact. The corner shop was built in the gate
# road's window once, and nothing but an import caught it.
assert HALL_Z1 <= NORTHGATE_CLEAR[0], (
    f"the community hall ends at z {HALL_Z1} and the northern link's clearance "
    f"starts at z {NORTHGATE_CLEAR[0]}. The hall is standing in the road out of "
    f"town: move NORTHGATE_Z0 north in world_plan.py, or take a frontage off "
    f"the west side.")

# Where the game stands a player inside any of the five buildings above: eight
# studs in from the front wall, on the door's own line.
#
# It was the literal -120.0, written five times in PLACE_POINTS, and that is how
# the bakery came to have a counter built on top of it. A coordinate typed in
# one table and a solid typed in another, four hundred lines apart, with nothing
# in the tree comparing them -- see check_town.py check 3, which is what finally
# did. Named here so the assertion below has something to assert about.
WEST_SPOT_X = FRONT_X - 8.0
# How deep a counter is. One number because a counter is one thing: the corner
# shop's was arrived at by measuring what a customer needs on their side of it,
# and there is no reason the bakery's should be different.
#
# Safe range 2.5-6.0. Under 2.5 it stops reading as a counter and becomes a
# rail; over 6 the customer side of the bakery starts eating the aisle to the
# display shelf. It is a shape, not a fit -- the assertions are what check that
# it fits.
COUNTER_DEPTH = 3.0
# The bakery's counter, against the door end of the room. Its back stays where
# it was; only its front moves, from ten studs deep to three.
BAKERY_COUNTER_X0 = BAKERY_X1 - 14.0
BAKERY_COUNTER_X1 = BAKERY_COUNTER_X0 + COUNTER_DEPTH
# The width a body needs, which is the number the corner shop's counter was
# rebuilt around when its top was found overhanging into the only standing room
# behind it. A place point closer than this to a solid is a spot the game sends
# a player to and cannot put them in.
BODY_WIDTH = 2.8
assert WEST_SPOT_X - BAKERY_COUNTER_X1 >= BODY_WIDTH, (
    f"the bakery's place point stands {WEST_SPOT_X - BAKERY_COUNTER_X1:.2f} "
    f"studs in front of its counter, and a body needs {BODY_WIDTH}. The point "
    f"is WEST_SPOT_X, shared with four other buildings, so move the counter "
    f"rather than the point: lower COUNTER_DEPTH or take BAKERY_COUNTER_X0 "
    f"further west.")

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

HOUSE_WIDTH = HOUSE_X1 - HOUSE_X0
HOUSE_DEPTH = HOUSES[0][1] - HOUSES[0][0]
assert HOUSES[1][0] - HOUSES[0][0] == HOUSE_DEPTH + NEIGHBOUR_GAP, (
    f"numbers 14 and 16 are {HOUSES[1][0] - HOUSES[0][0]} apart, which is not "
    f"a {HOUSE_DEPTH}-stud house plus a {NEIGHBOUR_GAP}-stud gap. The south row "
    f"and the back row both copy that pitch, so they can no longer tell what the "
    f"pitch is.")

# ---------------------------------------------------------------------------
# The back street
# ---------------------------------------------------------------------------
# The town was one street deep. Six civic buildings shared a single back wall at
# x -152, one row of houses faced them across one carriageway, and behind the
# school and the bakery was 48,000 square studs of unbroken grass -- about two
# fifths of the town's footprint, with a finished 181-stud carriageway lying in
# the middle of it that stopped halfway and connected to nothing. That road is
# RoadReturn. It has had pavement, kerbs, lamps and centre dashes since the loop
# was built, and not one thing to walk to.
#
# This is the row that gives it a reason. It stands on the far side of the
# return road facing east, so the back of the stores and the front of these
# houses look at each other across a road, which is what the back of a block in
# a small town actually looks like.
#
# Every dimension is the east row's, read off it rather than re-chosen -- a
# second row built to second numbers is two towns. The front yard is the depth
# the east row leaves between its sidewalk and its front wall; the garden is the
# depth it leaves behind its back wall before the ground stops being a plot; the
# house is the same 44 by 34. The only thing that had to be decided is which
# side of the road they stand on, and that follows from the stores being on the
# other one.
BACK_FRONT_YARD = HOUSE_X0 - NEAR_WALK_X1      # 10.6
BACK_GARDEN = EAST_X1 - HOUSE_X1               # 6.0
# The return road's west pavement, mirroring the east one it already has.
BACK_WALK_X1 = RETURN_X0
BACK_WALK_X0 = BACK_WALK_X1 - SIDEWALK
BACK_HOUSE_X1 = BACK_WALK_X0 - BACK_FRONT_YARD
BACK_HOUSE_X0 = BACK_HOUSE_X1 - HOUSE_WIDTH
# Where the map stops on this side. The row is what decides it: a garden's depth
# past the back wall and no further, because a strip of grass wider than a garden
# behind the last house is the same bare margin this row was built to remove.
WEST_EDGE = BACK_HOUSE_X0 - BACK_GARDEN

# The row runs exactly as long as the frontage it backs: from the garage, the
# southernmost thing on the west side, to the library, the northernmost. Longer
# and it stands behind open grass at one end; shorter and it stops in the middle
# of the block for no reason a player can see.
#
# The count is not typed. Plots are laid north to south at the street's own
# pitch until the next one will not fit, so moving the garage or the library
# moves the row instead of leaving a stale number behind -- the same rule the
# south row is built by, and for the same reason.
#
# Odd numbers, where the main street is even. That is the one thing about these
# houses that is not copied: a different series is how a player is told this is
# a different road, and it costs nothing.
BACK_ROW_Z1 = LIB_Z1
BACK_ROW_Z0 = GARAGE_Z0
BACK_ROW = []
_bz1 = BACK_ROW_Z1
_bn = 1
while True:
    _bz0 = _bz1 - HOUSE_DEPTH
    if _bz0 < BACK_ROW_Z0:
        break
    BACK_ROW.append((_bz0, _bz1, (_bz0 + _bz1) / 2, str(_bn)))
    _bn += 2
    _bz1 = _bz0 - NEIGHBOUR_GAP

# Safe range 8-12. The frontage is 412 studs at a 40-stud pitch, so ten is what
# it holds; under 8 something has eaten a third of the west side and over 12 the
# pitch has collapsed. Reports rather than clamps -- the number is a symptom.
assert 8 <= len(BACK_ROW) <= 12, (
    f"the back row came out at {len(BACK_ROW)} houses over the "
    f"{BACK_ROW_Z1 - BACK_ROW_Z0:.0f} studs between the garage and the library. "
    f"Check GARAGE_Z0, LIB_Z1, HOUSE_DEPTH and NEIGHBOUR_GAP.")

# The alleys, and they are not decoration.
#
# With the row built and both ends of the back street joined up, check_city's
# check 12 put the worst detour in the world at 2.02 -- 533 studs walked for 264
# straight, standing in the middle of the back street. That is what a pair of
# parallel roads joined only at their ends measures as: a player outside number 9
# who wants the library walks two hundred studs to a corner first. The road was
# reachable and the walk was still wrong, which is a distinction the route graph
# can make and a player only experiences as the town being annoying.
#
# Which gaps are wide enough to cut through is measured in world_plan.py, over
# all nine buildings on the frontage rather than the seven this file draws. The
# first version of this cut a single alley between the gym and the library and
# said in a comment here that it was the only gap wide enough to take one; it is
# the narrowest of the three, and the two it missed are the two nearest the
# worst-detour point. That is the whole reason WEST_FRONTAGE exists.
#
# Every alley runs from the back street's east pavement to the main street's far
# kerb -- pavement to pavement, abutting both rather than overlapping either,
# because two slabs that share a top height z-fight and both ends of these land
# on a surface that is already at PAVING.
ALLEY_X0 = RETURN_X1 + SIDEWALK
ALLEY_X1 = FAR_WALK_X0

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
#
# HOUSE_DEPTH and the pitch assertion that goes with it live up with HOUSES now,
# because the back row reads them too and a measurement of the east row had no
# business being defined inside the south row's own section.

# How deep the tip has to be before the row is allowed to stop laying houses.
#
# Two house plots, pitch included, because the street is the only ruler this
# file has and the question the number answers is a question about scale: under
# two plots the tip reads as somebody's back yard with rubbish in it, and the
# thing at the bottom of the road has to read as *land* -- a place the town
# takes its refuse to, not a bin. Typed as a multiple rather than as 80 so that
# widening a plot widens the tip with it instead of leaving it looking cramped
# against houses that grew.
TIP_PLOTS = 2
TIP_MIN_DEPTH = TIP_PLOTS * (HOUSE_DEPTH + NEIGHBOUR_GAP)
# The line the row may not cross. The tip then takes everything the row left,
# which is why there is no second constant saying where the tip starts: two
# numbers for one boundary is how a gap opens between them.
TIP_LIMIT = SOUTH_Z0 + TIP_MIN_DEPTH

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
    # Stops at the tip's line, not at the bottom of the map: the row's last
    # plot has to leave a neighbour's gap in front of the fence for the same
    # reason every other plot leaves one, or the last house has a chain-link
    # panel up against its back wall.
    if _z0 - NEIGHBOUR_GAP < TIP_LIMIT:
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
    f"z {SHOP_Z0} and the tip's line at z {TIP_LIMIT}. Check SHOP_DEPTH, "
    f"TIP_PLOTS, MAP_SOUTH_EDGE and SOUTHGATE_CLEAR in world_plan.py.")
HOUSES.extend(SOUTH_ROW)

# The tip's north edge: whatever the row left, one neighbour's gap south of the
# last house. Read off the row rather than declared, so a plot added or removed
# up the street moves the fence instead of opening a strip of nothing between
# the two.
TIP_Z1 = SOUTH_ROW[-1][0] - NEIGHBOUR_GAP
TIP_Z0 = SOUTH_Z0
# Guaranteed by the break above, and asserted anyway because the guarantee lives
# in a loop three screens up and the next person to edit that loop is the one
# this catches.
assert TIP_Z1 - TIP_Z0 >= TIP_MIN_DEPTH, (
    f"the tip came out {TIP_Z1 - TIP_Z0:.0f} studs deep against a minimum of "
    f"{TIP_MIN_DEPTH:.0f}. The south row's break condition is what leaves it "
    f"room; it has stopped doing so.")

# The tip is the full width of the town, seam to seam: the map's west margin to
# the line the city's ground starts on. Not a plot in the corner -- the thing at
# the bottom of the road has to read as land the town uses, and a compound that
# stopped short of either edge would leave two strips of nothing whose only
# purpose was to be the reason the tip is not the width of the map.
TIP_X0, TIP_X1 = WEST_EDGE, EAST_X1

# The road runs out into the gate. The gate is wider than the carriageway on
# both sides, which is not decoration: the fence is drawn as panels between the
# gate's edges and the compound's corners, so a gate narrower than the road
# would put a chain-link panel standing in the middle of the spur. Deriving the
# opening from ROAD_X0/ROAD_X1 rather than typing two numbers means widening the
# road widens the gate instead of walling it off.
#
# Safe range 3-10. Under 3 a player running down the middle of the road clips a
# gatepost; over 10 the fence stops reading as a boundary with a way in and
# becomes two unrelated runs of wire.
TIP_GATE_MARGIN = 5.0
TIP_GATE_X0 = ROAD_X0 - TIP_GATE_MARGIN
TIP_GATE_X1 = ROAD_X1 + TIP_GATE_MARGIN
assert TIP_GATE_X0 < ROAD_X0 and TIP_GATE_X1 > ROAD_X1, (
    f"the tip's gate is x {TIP_GATE_X0}..{TIP_GATE_X1} and the spur is "
    f"{ROAD_X0}..{ROAD_X1}. The fence fills everything the gate does not, so a "
    f"gate no wider than the road puts a panel across the carriageway.")
# The gate that gets built is asserted to be the gate that was declared, down
# where fence_runs() exists to be asked.

# How far the scrub verge reaches in from the south and west edges. The city
# closes its own south edge with a treeline on a verge (works_boundary in
# gen_city.py) and this is the same line continued west, so the bottom of the
# map is one edge rather than two treatments that meet in the middle. Trees
# rather than a wall for the reason given over there: an edge a player can see
# the far side of is an edge they walk to.
TIP_VERGE = 20.0
# The working yard: what the verge leaves. One name for it, because the yard's
# south edge is the verge's north edge and writing it twice is how the two come
# apart.
TIP_YARD_Z0 = TIP_Z0 + TIP_VERGE
TIP_YARD_X0 = TIP_X0 + TIP_VERGE
# Where the trees stand within that verge, and how far apart. 30 is the city's
# own spacing -- `int((x1 - x0) / 30.0)` in works_boundary -- carried over so
# the two halves of the treeline have the same density where they meet.
TIP_TREE_PITCH = 30.0

# The sign on the gate. A player reaches this fence having walked the length of
# a street that gets worse the further down it they go, crossed the link road
# and passed two boarded houses -- three hundred studs of signal that they are
# leaving town, and nothing at the end of it saying what they arrived at. A
# named place is a destination; an unnamed chain-link fence is the edge of the
# map, and a player who reads it that way turns round six strides short of the
# only yard in the town with anything in it to find.
#
# The board is as wide as the hole it names and butts against the west gatepost,
# so the sign and the way in are one object rather than a notice somewhere near
# an opening. Derived rather than typed for the usual reason: widening the gate
# widens the sign, and the two cannot drift apart into a board that overhangs
# the entrance it is pointing at.
TIP_SIGN_W = TIP_GATE_X1 - TIP_GATE_X0
TIP_SIGN_H = 9.0
TIP_SIGN_X1 = TIP_GATE_X0
TIP_SIGN_X0 = TIP_SIGN_X1 - TIP_SIGN_W
assert TIP_SIGN_X0 >= TIP_X0, (
    f"the gate sign runs x {TIP_SIGN_X0}..{TIP_SIGN_X1} and the fence it hangs "
    f"on starts at x {TIP_X0}. The board is the width of the gate laid west of "
    f"it, so a gate this wide has run the sign off the end of the compound.")
# The small board under it, at the height a player reads standing still rather
# than the height they read walking towards it.
TIP_NOTICE_W = 12.0
TIP_NOTICE_H = 3.0
TIP_NOTICE_Y0 = 3.5

# sign()'s canvas is stretched over whatever face it lands on, so a canvas whose
# aspect does not match the board's stretches the lettering -- and a text size
# quoted in canvas pixels means nothing until you know how many studs a pixel
# is. Both boards therefore derive their canvas from their own size at a fixed
# scale, and quote their letter height in studs, which is the only unit anyone
# reading this can check against the world.
SIGN_PX = 24.0
TIP_SIGN_LETTER = 4.0
TIP_NOTICE_LETTER = 1.5

# The tag the rules read to find something worth searching, and the attribute
# that says what kind of thing it is. Same shape as AgesGymEquipment/GymKind:
# geometry stamps the tag, the service finds it by tag and never by name or
# position, and the two can be rebuilt independently.
#
# There is no Config entry behind this yet. Config.luau is not this generator's
# to write, so the tag is laid down here and handed over -- the geometry being
# ready first is the point of a tag contract, not a gap in it.
SCAVENGE_TAG = "AgesScavenge"
SCAVENGE_KIND_ATTR = "ScavengeKind"

# The weighbridge and its office, just inside the gate on the west side: the
# first thing you meet, which is what a weighbridge is. Its east wall faces the
# haul track across a clear apron, so the building is read side-on from the gate
# and front-on from inside the yard. Its place point stands eight studs in from
# that wall, which is what WEST_SPOT_X means for every other building in town.
HUT_X0, HUT_X1 = -130.0, -108.0
HUT_Z0, HUT_Z1 = -436.0, -418.0
HUT_DOOR = (HUT_Z0 + HUT_Z1) / 2
HUT_SPOT_X = HUT_X1 - 8.0

# ---------------------------------------------------------------------------
# Wear
# ---------------------------------------------------------------------------
# How run-down each house is, on 0..1, and it is **one number read off the map
# rather than a list of which houses are broken**.
#
# The reason to derive it is the reason everything else in this section is
# derived: a list would be right on the day it was written and wrong the first
# time a plot moved, and "number 26 is the boarded-up one" is a fact about a
# coordinate, not about a house. Deriving it also means the row cannot develop a
# hole -- there is no house the list forgot.
#
# The scale runs south, away from the player's own front door, because that is
# the direction the town already thins out: the park, the library and the gym
# are north of the spawn plot, the clinic, the bakery and the garage are south
# of it, and the last thing on the road is now the tip. The gradient agrees with
# a layout that was settled before it existed, which is why it reads as a town
# with a bad end rather than as an effect applied to houses.
#
# WEAR_BASE is where the row starts rather than zero: every house on this street
# is meant to be more modest than the imported model the player spawns in, which
# is the one saturated, cared-for building in the world. Safe range 0.2-0.45 --
# under 0.2 the north end is indistinguishable from the player's own house, over
# 0.45 the whole town is a slum and the gradient has nothing left to say.
WEAR_BASE = 0.30
WEAR_Z_NORTH = DOOR_LINE
WEAR_Z_SOUTH = min(door_z for _z0, _z1, door_z, _n in HOUSES)


def wear_at(door_z: float) -> float:
    """0 at the player's own door line, 1 at the last house before the tip."""
    span = WEAR_Z_NORTH - WEAR_Z_SOUTH
    t = min(1.0, max(0.0, (WEAR_Z_NORTH - door_z) / span))
    return WEAR_BASE + (1.0 - WEAR_BASE) * t


# What each kind of damage costs. Thresholds rather than a continuous ramp for
# the three that are binary in the world -- a window is boarded or it is not --
# and read straight off `wear` for the two that are not.
#
# Safe ranges are set by the row they have to land in. There are nine houses
# spread over 0.30..1.00, so a threshold moved by more than about 0.08 changes
# how many houses show the damage, and any threshold below WEAR_BASE applies it
# to every house in town including the two at the good end.
PATH_CRACK_WEAR = 0.45   # the front path breaks into slabs with weeds between
ROOF_PATCH_WEAR = 0.55   # mismatched felt patches appear on the roof
JUNK_WEAR = 0.62         # something dumped in the front yard
BOARD_WEAR = 0.72        # one window boarded
BOARD_BOTH_WEAR = 0.90   # both of them, and the house is empty

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
    ("gym", WEST_SPOT_X, GYM_DOOR, FLOOR_1, "the gym, past the treadmills"),
    ("library", WEST_SPOT_X, LIB_DOOR, FLOOR_1, "the library, by the desk"),
    ("cafe", WEST_SPOT_X, CAFE_DOOR, FLOOR_1, "the cafe, at a window table"),
    ("community_hall", WEST_SPOT_X, HALL_DOOR, FLOOR_1, "the community hall"),
    ("clinic", WEST_SPOT_X, CLINIC_DOOR, FLOOR_1, "the clinic reception"),
    ("bakery", WEST_SPOT_X, BAKERY_DOOR, FLOOR_1, "the bakery, at the counter"),
    ("garage", WEST_SPOT_X, GARAGE_DOOR, FLOOR_1, "the garage workshop"),
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
    # wp_north_3 was the top of the street, and a leaf: its only neighbour was
    # wp_north_2, so the whole north end of town was a spur off the route graph
    # and every journey between the town and the city went out through the gate
    # road, the southern link or the green. The street carries on to a junction
    # now, and so does the chain -- these two and wp_top_junction below are what
    # make the northern link a road anything actually routes down.
    ("wp_north_3", -92.0, 216.0, PAVING, "outside the cafe"),
    ("wp_north_4", -92.0, 260.0, PAVING, "outside the community hall"),
    ("wp_north_5", -92.0, NORTHGATE_CLEAR[0] - 4.0, PAVING, "the top of the street"),
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
    # All four of these stand at RETURN_MID, in the middle of the return road's
    # carriageway, which tops at GROUND. Three of them said PAVING, half a stud
    # up, and floated -- and wp_loop_s said GROUND and was right, which is what
    # one line getting fixed and its three neighbours not looks like. Half a
    # stud is nothing to look at; the reason it is a defect is that the height a
    # point declares is a claim about which surface it is standing on, and these
    # three claimed a pavement fifteen studs east of them. Found by check_town
    # check 2, the town's half of a question check_city had only ever asked of
    # the city.
    ("wp_loop_n", RETURN_MID, -145.0, GROUND, "the return road, north end"),
    ("wp_loop_m_grass", -187.0, -195.0, GROUND, "the grass behind the garage"),
    ("wp_loop_m", RETURN_MID, -195.0, GROUND, "the return road, by the garage"),
    ("wp_loop_m2", RETURN_MID, -255.0, GROUND, "the return road, mid-town"),
    ("wp_inner_m", -172.0, -250.0, GROUND, "the grass between the roads, south"),
    ("wp_inner_s", -150.0, -262.0, GROUND, "the grass between the roads"),
    ("wp_loop_s", RETURN_MID, -300.0, GROUND, "the south turn of the road"),
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
    # Either side of the southern link road. The near walk is two slabs with a
    # thirty-stud carriageway between them, so the route graph needs a point on
    # each -- one hop across the crossing rather than an 87-stud jump from the
    # last maintained house to the first neglected one, which is over the link
    # radius and would have left the bottom of the street unreachable.
    ("wp_cross_n", -58.0, CURL_Z + 2.0, PAVING, "the crossing, town side"),
    ("wp_cross_s", -58.0, SOUTHGATE_CLEAR[0] - 2.0, PAVING, "the crossing, tip side"),
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

# The tip. The gate point stands in the gap in the fence, on the haul track, so
# a route into the yard goes through the opening rather than at the wire; the
# yard point is where a player is put down when the game says "the tip".
PLACE_POINTS.extend([
    ("wp_tip_gate", ROAD_MID, TIP_Z1 - 6.0, GROUND, "the gate of the tip"),
    ("tip", ROAD_MID, TIP_Z1 - 44.0, GROUND, "the tip, in the yard"),
    ("tip_office", HUT_SPOT_X, HUT_DOOR, FLOOR_1, "the tip office, at the desk"),
])

# Every hop the route graph has to make, checked against the radius that makes it
# a hop at all. Routes joins two points within ROUTE_LINK of each other and
# nothing else joins them, so a chain with one gap in it is not a long walk -- it
# is a piece of the map the game cannot reach. Most of this table's spacing was
# eyeballed and got away with it; the tip was 87 studs from the last house that
# had a waypoint, which is where eyeballing stopped getting away with it.
ROUTE_LINK = 70.0

# The back street's own chain, and the reason it is generated rather than typed:
# it is 648 studs from the bottom corner of the loop to the top junction, which
# is ten hops, and ten typed coordinates is ten chances to leave a gap in a road
# whose entire purpose is to be a second way round. The count is whatever it
# takes to keep every hop under the radius, so lengthening the road adds a point
# instead of opening a hole.
#
# It starts at wp_loop_n, which already stands on this carriageway at z -145, so
# the new chain joins the existing loop by construction rather than by being
# close enough to it.
BACK_WP_Z0 = -145.0
_back_span = NORTHGATE_MID - BACK_WP_Z0
_back_hops = math.ceil(_back_span / ROUTE_LINK)
PLACE_POINTS.extend(
    (f"wp_back_{i}", RETURN_MID, BACK_WP_Z0 + _back_span * i / _back_hops, GROUND,
     "the back street")
    for i in range(1, _back_hops))

# The top road, west to east: the return leg's corner, then across to the main
# street's junction, where gen_city.py's own chain picks it up and carries it to
# the connector. Same reason for generating it, same reason for the count.
_top_span = ROAD_MID - RETURN_MID
_top_hops = math.ceil(_top_span / ROUTE_LINK)
PLACE_POINTS.extend(
    (f"wp_top_{i}", RETURN_MID + _top_span * i / _top_hops, NORTHGATE_MID, GROUND,
     "the top road")
    for i in range(_top_hops))
PLACE_POINTS.append(
    ("wp_top_junction", ROAD_MID, NORTHGATE_MID, GROUND,
     "the junction at the top of the street"))

# Each alley, west to east. Both ends land on a pavement that is already on the
# graph, which is the whole point of them -- a cut-through nothing routes down
# is a cut-through only a player who already knows the map will ever use.
_alley_span = ALLEY_X1 - ALLEY_X0
_alley_hops = math.ceil(_alley_span / ROUTE_LINK)
for _blurb, _az0, _az1 in ALLEYS:
    _slug = alley_slug(_blurb).lower()
    PLACE_POINTS.extend(
        (f"wp_alley_{_slug}_{i}",
         ALLEY_X0 + _alley_span * i / _alley_hops, (_az0 + _az1) / 2, PAVING,
         f"the alley between {_blurb}")
        for i in range(_alley_hops + 1))

# One point in every house on the back street, and one on its sidewalk outside
# every one -- generated from BACK_ROW for the same reason the east row's are
# generated from HOUSES.
BACK_WALK_MID = (BACK_WALK_X0 + BACK_WALK_X1) / 2
PLACE_POINTS.extend(
    (f"home_b{i + 1}", BACK_HOUSE_X1 - 2.0, door_z, FLOOR_1, f"number {number}")
    for i, (_bz0, _bz1, door_z, number) in enumerate(BACK_ROW))
PLACE_POINTS.extend(
    (f"wp_back_walk{i + 1}", BACK_WALK_MID, door_z, PAVING,
     f"the back street, outside number {number}")
    for i, (_bz0, _bz1, door_z, number) in enumerate(BACK_ROW))


def _check_chain(chain, axis, blurb):
    """Assert every consecutive hop along a chain is inside the link radius.

    `axis` is 0 for a chain that runs east-west and 1 for one that runs
    north-south: the points are sorted along it before being paired, so the
    chain does not have to be written in order and cannot be silently reordered
    into a passing one either.
    """
    by_id = {pid: (x, z) for pid, x, z, _f, _l in PLACE_POINTS}
    missing = [pid for pid in chain if pid not in by_id]
    assert not missing, f"{blurb}: no place point called {missing}"
    ordered = sorted(chain, key=lambda pid: by_id[pid][axis])
    for a, b in zip(ordered, ordered[1:]):
        ax, az = by_id[a]
        bx, bz = by_id[b]
        d = math.hypot(bx - ax, bz - az)
        assert d <= ROUTE_LINK, (
            f"{a} at ({ax:.0f},{az:.0f}) and {b} at ({bx:.0f},{bz:.0f}) are "
            f"{d:.0f} studs apart, over the {ROUTE_LINK:.0f}-stud link radius. "
            f"{blurb} is broken at that gap.")


_south = ["wp_east_s3", "wp_cross_n", "wp_cross_s"]
_south += [f"wp_east_s{4 + i}" for i in range(len(SOUTH_ROW))]
_south += ["wp_tip_gate", "tip"]
_check_chain(_south, 1, "the walk from the street down to the tip")

# The back street, bottom corner to top junction. Every house on it hangs off
# this chain through its own sidewalk point, so a gap here strands ten homes.
_back = ["wp_loop_n"] + [f"wp_back_{i}" for i in range(1, _back_hops)]
_back += [f"wp_top_{i}" for i in range(_top_hops)] + ["wp_top_junction"]
_check_chain(_back, 1, "the back street, from the loop to the top junction")

# The top road itself, which runs the other way and therefore sorts the other
# way. Written as its own chain rather than folded into the one above because a
# chain sorted by z cannot see a gap in a road that runs along x.
_top = [f"wp_top_{i}" for i in range(_top_hops)] + ["wp_top_junction"]
_check_chain(_top, 0, "the top road, from the back street to the main street")

# The main street's west walk, all the way up to the junction. This is the half
# the north end was missing: wp_north_3 used to be the last point on it and had
# exactly one neighbour, which is what a dead end looks like to a route graph.
_north = ["corner_n", "wp_north_1", "wp_north_2", "wp_north_3", "wp_north_4",
          "wp_north_5", "wp_top_junction"]
_check_chain(_north, 1, "the main street's west walk up to the top junction")

# The two new buildings, each to the walk outside it. A building whose place
# point is out of reach of the chain is a door the game can name and cannot
# route to, which is the defect wp_east_home was added for.
for _pid, _wp in (("cafe", "wp_north_3"), ("community_hall", "wp_north_4")):
    _check_chain([_pid, _wp], 1, f"the walk from {_wp} into {_pid}")

# And the back street's houses to the back street's own chain. Checked as pairs
# rather than as one chain because they are a comb, not a line: each house hangs
# off the walk point outside it and nothing else.
for _i, (_bz0, _bz1, _door_z, _number) in enumerate(BACK_ROW):
    _check_chain([f"home_b{_i + 1}", f"wp_back_walk{_i + 1}"], 0,
                 f"the walk from the back street into number {_number}")
_back_walk = [f"wp_back_walk{i + 1}" for i in range(len(BACK_ROW))]
_check_chain(_back_walk + ["wp_loop_n"], 1, "the back street's sidewalk")

def _check_joins(pid, targets, blurb):
    """Assert a point is within the link radius of one of a named set of points.

    The set is named rather than inferred. The first version of this asked the
    weaker question -- "is there anything within the link radius that is not
    more of this same alley" -- and a negative test walked the alley's west end
    ninety studs east of the back street without the assertion firing, because
    what it found instead was `school`, an interior place point on the far side
    of the frontage. Destinations and roads are the same kind of thing to the
    route graph, so a check that will accept either is a check that passes when
    an alley opens onto a wall.
    """
    by_id = {p: (x, z) for p, x, z, _f, _l in PLACE_POINTS}
    assert pid in by_id, f"{blurb}: no place point called {pid}"
    missing = [t for t in targets if t not in by_id]
    assert not missing, f"{blurb}: no place point called {missing}"
    px, pz = by_id[pid]
    near = [(t, math.hypot(by_id[t][0] - px, by_id[t][1] - pz)) for t in targets]
    assert any(d <= ROUTE_LINK for _t, d in near), (
        f"{blurb}: {pid} at ({px:.0f},{pz:.0f}) is "
        f"{min(d for _t, d in near):.0f} studs from the nearest point on that "
        f"road, over the {ROUTE_LINK}-stud link radius, so the alley is a paved "
        f"strip the route graph never joins to it. Move the alley's end onto "
        f"the pavement or add a waypoint on the road it misses.")


# Each alley, and its west end.
#
# The run itself and the join onto the back street are checked here because this
# file draws both. The east end is not, and deliberately: the main street's
# waypoints at these z values are generated by build_street.py into a different
# asset, so at this point in this program they do not exist to be measured
# against. The only thing that can see both ends at once is check_city, which
# reads every asset -- and it does check it, by reachability and by the detour
# ratio that put these alleys here in the first place. A local check that could
# only pretend to measure the east end would be worth less than the honest gap.
for _blurb, _az0, _az1 in ALLEYS:
    _slug = alley_slug(_blurb).lower()
    _ids = [f"wp_alley_{_slug}_{i}" for i in range(_alley_hops + 1)]
    _check_chain(_ids, 0, f"the alley between {_blurb}")
    _check_joins(_ids[0], _back_walk + _back,
                 f"the west end of the alley between {_blurb}, off the back street")

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
CAFE_WALL = (186, 196, 178)     # sage render
HALL_WALL = BRICK_WARM          # the one warm-brick civic building
# The cafe's furniture and the hall's stage: one timber in the town, because the
# two buildings that went up together should look like they went up together.
CAFE_TIMBER = (162, 118, 74)
CURTAIN_RED = (120, 42, 46)
CHAIR_BLUE = (72, 88, 118)

HOUSE_WALL = (166, 118, 92)
# Where that brick ends up at the bottom of the road: the same hue with the life
# gone out of it -- damp-stained, greyed, never repainted. Deliberately not a
# different colour. A house at the bad end has to read as *the same house* that
# nobody has looked after, because a differently-coloured row would look like a
# different builder put it there, which is the opposite of the point.
HOUSE_WALL_WORN = (112, 96, 88)
ROOF_PATCH = (58, 56, 58)       # felt, laid over a hole and not matched
BOARD_PLY = (150, 122, 84)      # plywood over a window
WEED = (96, 112, 58)
RUBBLE = (128, 122, 112)

# The tip. Nothing here is allowed a clean colour: this is the one place in the
# town where a surface is meant to look spoiled, the same licence the works
# district has in the city.
TIP_DIRT = (104, 92, 76)        # compacted earth and ash, the haul surface
TIP_SPOIL = (86, 78, 66)        # older, capped, grassed-over in patches
TIP_SCRUB = (112, 120, 78)      # the grass that comes back on a capped bank
SKIP_YELLOW = (168, 132, 44)    # a skip that was yellow a long time ago
SKIP_RUST = (128, 82, 52)
CHAINLINK = (118, 122, 126)
WRECK_BODY = (96, 100, 104)
TIP_SIGN_BOARD = (46, 72, 58)   # municipal green -- the one clean thing here,
TIP_SIGN_INK = (238, 240, 232)  # because a sign nobody can read is not a sign


def worn(color, amount, toward=None):
    """`color` faded `amount` of the way toward its worn form, 0..1.

    Everything the wear gradient touches goes through here, so there is exactly
    one place that decides what "run-down" does to a colour. Written as a lerp
    rather than as a per-house palette because nine hand-picked browns is nine
    chances to pick one that reads as a different material.
    """
    target = HOUSE_WALL_WORN if toward is None else toward
    t = min(1.0, max(0.0, amount))
    return tuple(round(a + (b - a) * t) for a, b in zip(color, target))

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
# The tip's own helpers
# ---------------------------------------------------------------------------

# How tall the chain-link stands, and how far apart its posts are. A tip fence
# is taller than a garden one because the thing it is keeping out is people, and
# the height is the whole reason the gate reads as the way in.
# Safe range 7-11: under 7 a player reads it as something to vault, over 11 the
# yard is a pit you look down into rather than a place you walk about in.
FENCE_HEIGHT = 8.0
FENCE_POST_PITCH = 12.0
# Thin on purpose. A panel is 12 x 0.4 = 4.8 studs in plan, well under
# check_town's WALL_MIN_AREA of 20, so a fence never registers as a building
# wall and never gets reported as standing in a road. That is correct rather
# than convenient: a fence is a boundary, and a boundary in a carriageway is a
# gate, which is what the gap in this one is for.
FENCE_THICK = 0.4


def fence_runs(a0, a1, gaps):
    """`a0..a1` with every range in `gaps` cut out of it."""
    runs = [(a0, a1)]
    for g0, g1 in sorted(gaps):
        cut = []
        for r0, r1 in runs:
            if g0 > r0:
                cut.append((r0, min(g0, r1)))
            if g1 < r1:
                cut.append((max(g1, r0), r1))
        runs = [(r0, r1) for r0, r1 in cut if r1 - r0 > 0.01]
    return runs


def chainlink(label, a0, a1, at_coord, along="x", gaps=()):
    """A run of chain-link along one axis, minus its gates.

    `gaps` are ranges on the `along` axis that get no fence -- the same argument
    shape `wall()` takes for doorways, so a hole in a boundary is reasoned about
    the same way everywhere in this file.

    Each surviving run is then divided into a whole number of panels *of its
    own*. The obvious implementation is one pitch across the whole length with
    the panels whose middle lands in a gap skipped, and that is what this
    replaced: it silently rounded the gate to the panel grid. A gate declared
    five studs wider than the carriageway on each side came out half a stud
    wider, and both posts that should have framed the opening were dropped,
    because the rule that kept a post asked whether either of its neighbouring
    panels had survived and at the opening neither had. The declared gate and
    the built gate were different numbers and nothing compared them. A gate is
    a measurement, not a rounding.
    """
    i = j = 0
    for r0, r1 in fence_runs(a0, a1, gaps):
        n = max(1, int(round((r1 - r0) / FENCE_POST_PITCH)))
        step = (r1 - r0) / n
        for k in range(n):
            i += 1
            a, b = r0 + k * step, r0 + (k + 1) * step
            bounds = ((a, b, at_coord - FENCE_THICK / 2, at_coord + FENCE_THICK / 2,
                       GROUND, GROUND + FENCE_HEIGHT) if along == "x"
                      else (at_coord - FENCE_THICK / 2, at_coord + FENCE_THICK / 2,
                            a, b, GROUND, GROUND + FENCE_HEIGHT))
            box(f"{label}Mesh{i}", bounds, CHAINLINK, METAL, transparency=0.4)
        # Both ends of every run get a post, which is what puts one on each side
        # of the opening: the two places the fence has to look finished are the
        # corners and the gate.
        for k in range(n + 1):
            j += 1
            a = r0 + k * step
            bounds = ((a - 0.3, a + 0.3, at_coord - 0.3, at_coord + 0.3,
                       GROUND, GROUND + FENCE_HEIGHT + 0.6) if along == "x"
                      else (at_coord - 0.3, at_coord + 0.3, a - 0.3, a + 0.3,
                            GROUND, GROUND + FENCE_HEIGHT + 0.6))
            box(f"{label}Post{j}", bounds, STEEL, METAL)


def spoil_mound(x, z, radius, height, label="Spoil"):
    """A heap of covered spoil: three shrinking tiers rather than a cone.

    Tiers because the world is boxes and a box heap reads as a heap at this
    scale, and because a mound the player can get up is a mound they will get
    up -- each tier is a step, not a wall.
    """
    with group(label):
        for i in range(3):
            r = radius * (1.0 - i * 0.28)
            y0 = GROUND + height * i / 3.0
            y1 = GROUND + height * (i + 1) / 3.0
            box(f"{label}Tier{i + 1}", (x - r, x + r, z - r, z + r, y0, y1),
                worn(TIP_SPOIL, i * 0.3, TIP_DIRT), PEBBLE)


# How much room each searchable thing takes in plan, as a half-extent from its
# own centre. Named because two readers need them: the helper that draws the
# thing, and the assertion below that checks nothing is standing in the haul
# track. A footprint written once in a helper and again in a check is a
# footprint that will disagree with itself the first time a skip gets longer.
SKIP_HALF_X, SKIP_HALF_Z = 5.0, 3.0
# The wreck is not symmetric -- its open door reaches further east than its body
# does west -- and one number that covers the widest side is the right kind of
# wrong for a clearance check.
WRECK_HALF_X, WRECK_HALF_Z = 5.4, 7.0


def scavenge_skip(x, z, label="Skip", rusty=False):
    """An open-top skip. The tagged part is the load, which is what a player
    reaches into -- so the marker sits at the height of the thing you do."""
    body = SKIP_RUST if rusty else SKIP_YELLOW
    hx, hz = SKIP_HALF_X, SKIP_HALF_Z
    with group(label):
        box(f"{label}Floor", (x - hx, x + hx, z - hz, z + hz,
                              GROUND, GROUND + 0.4), body, CORRODED_METAL)
        for name, bounds in (
            ("SideW", (x - hx, x - hx + 0.4, z - hz, z + hz, GROUND, GROUND + 4.2)),
            ("SideE", (x + hx - 0.4, x + hx, z - hz, z + hz, GROUND, GROUND + 4.2)),
            ("SideS", (x - hx, x + hx, z - hz, z - hz + 0.4, GROUND, GROUND + 4.2)),
            ("SideN", (x - hx, x + hx, z + hz - 0.4, z + hz, GROUND, GROUND + 4.2)),
        ):
            box(f"{label}{name}", bounds, body, CORRODED_METAL)
        box(f"{label}Load", (x - hx + 0.6, x + hx - 0.6, z - hz + 0.6, z + hz - 0.6,
                             GROUND + 0.4, GROUND + 3.4), RUBBLE, PEBBLE,
            collide=False, tags=[SCAVENGE_TAG],
            attrs={SCAVENGE_KIND_ATTR: "skip"})


def scavenge_pile(x, z, label="Pile", size=5.0):
    """A heap of loose rubbish tipped straight onto the dirt."""
    with group(label):
        box(f"{label}Base", (x - size, x + size, z - size * 0.8, z + size * 0.8,
                             GROUND, GROUND + 1.6), RUBBLE, PEBBLE,
            tags=[SCAVENGE_TAG], attrs={SCAVENGE_KIND_ATTR: "pile"})
        box(f"{label}Crown", (x - size * 0.6, x + size * 0.6,
                              z - size * 0.5, z + size * 0.5,
                              GROUND + 1.6, GROUND + 2.6),
            worn(RUBBLE, 0.5, TIP_SPOIL), PEBBLE)
        box(f"{label}Board", (x + size * 0.2, x + size * 0.9, z - 0.2, z + 0.2,
                              GROUND + 1.6, GROUND + 4.4), BOARD_PLY, PLANKS,
            collide=False)


def scavenge_wreck(x, z, label="Wreck"):
    """A car that got as far as the tip. No wheels, no glass, one door hanging
    open -- a shape the player reads as finished, not as a vehicle to try."""
    with group(label):
        box(f"{label}Body", (x - 3.0, x + 3.0, z - WRECK_HALF_Z, z + WRECK_HALF_Z,
                             GROUND + 0.4, GROUND + 3.2), WRECK_BODY, CORRODED_METAL,
            tags=[SCAVENGE_TAG], attrs={SCAVENGE_KIND_ATTR: "wreck"})
        box(f"{label}Cabin", (x - 2.6, x + 2.6, z - 3.0, z + 3.2,
                              GROUND + 3.2, GROUND + 5.4),
            worn(WRECK_BODY, 0.6, RUBBLE), CORRODED_METAL)
        box(f"{label}Axle", (x - 3.2, x + 3.2, z - 5.0, z - 4.2,
                             GROUND, GROUND + 0.6), (52, 50, 50), METAL)
        box(f"{label}Door", (x + 2.6, x + WRECK_HALF_X, z - 1.0, z + 2.6,
                             GROUND + 0.8, GROUND + 3.6),
            worn(WRECK_BODY, 0.4, RUBBLE), CORRODED_METAL)


# ---------------------------------------------------------------------------
# Ground, road, sidewalks
# ---------------------------------------------------------------------------

with group("Ground"):
    # The road corridor continued north, south, and east of the player's plot.
    # Three bands rather than one slab, mirroring build_street.py: grass, road,
    # grass, so no two boxes that share a top height overlap and z-fight.
    box("GrassWestN", (WEST_X0, ROAD_X0, NORTH_Z0, NORTHGATE_Z0, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)
    box("GrassEastN", (ROAD_X1, EAST_X0, NORTH_Z0, NORTH_Z1, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)
    box("RoadN", (ROAD_X0, ROAD_X1, NORTH_Z0, NORTHGATE_Z0, GROUND_BOTTOM, GROUND),
        TARMAC, ASPHALT)

    # The top of the town, which used to be where the road stopped. The main
    # street now tees into an east-west road at NORTHGATE_Z0, the return road
    # comes up the back and tees into the same one, and gen_city.py carries it
    # east from ROAD_X1 to the connector -- so the west side of town is a loop
    # with a mouth at each end instead of a cul-de-sac with a mouth at one.
    #
    # RoadTop starts at RETURN_X1 and not at RETURN_X0 because the return leg's
    # own tile already covers the corner square, exactly the way RoadBottom
    # yields the south-west corner to it. Two tiles claiming one corner is two
    # coplanar slabs, which is the one thing every surface in this file is tiled
    # to avoid.
    box("RoadTop", (RETURN_X1, ROAD_X1, NORTHGATE_Z0, NORTHGATE_Z1,
                    GROUND_BOTTOM, GROUND), TARMAC, ASPHALT)
    box("GrassTopN", (RETURN_X0, ROAD_X1, NORTHGATE_Z1, NORTH_Z1,
                      GROUND_BOTTOM, GROUND), LAWN, GRASS)

    # South of the street the road loops: down the east leg, across the bottom,
    # back up the return leg. The grass tiles around it exactly, the way the
    # bands north of the street do, so the loop reads as road-in-grass rather
    # than as a line of separate boxes.
    box("GrassBottom", (WEST_EDGE, ROAD_X0, TIP_Z1, RETURN_Z0, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)
    box("GrassWestLoop", (WEST_EDGE, RETURN_X0, RETURN_Z0, STREET_Z0, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)
    box("GrassInner", (RETURN_X1, ROAD_X0, CURL_Z, STREET_Z0, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)
    box("GrassEastS", (ROAD_X1, EAST_X0, TIP_Z1, STREET_Z0, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)
    box("RoadEast", (ROAD_X0, ROAD_X1, CURL_Z, STREET_Z0, GROUND_BOTTOM, GROUND),
        TARMAC, ASPHALT)
    box("RoadBottom", (RETURN_X1, ROAD_X1, RETURN_Z0, CURL_Z, GROUND_BOTTOM, GROUND),
        TARMAC, ASPHALT)
    # The return leg, carried the whole way north to the top road. It used to
    # stop at STREET_Z0 -- 181 studs of finished carriageway that ended in a
    # meadow -- and stopping there is what made the back of the town a field
    # with a road lying in it.
    box("RoadReturn", (RETURN_X0, RETURN_X1, RETURN_Z0, NORTHGATE_Z1, GROUND_BOTTOM, GROUND),
        TARMAC, ASPHALT)

    # The spur: the loop's bottom band carried on south, in the same band and
    # the same width, to dead-end at the tip's gate. It is what makes the last
    # two houses a street rather than two buildings in a field -- and it is
    # named Road* inside Ground because in this town a road is a tile of the
    # ground jigsaw, not a slab on top of one, which is the rule check_town's
    # check 6 reads carriageways by.
    box("RoadSpur", (ROAD_X0, ROAD_X1, TIP_Z1, RETURN_Z0, GROUND_BOTTOM, GROUND),
        TARMAC, ASPHALT)

    # East of the property line: one continuous bed of grass the length of the
    # new quarter, under the houses and the park. It stops at the tip's fence
    # line, where the ground stops being anybody's lawn.
    box("GrassEast", (EAST_X0, EAST_X1, TIP_Z1, EAST_Z1, GROUND_BOTTOM, GROUND),
        LAWN, GRASS)

    # The tip's own ground, the full width of the town, tiled rather than laid
    # over the grass: two boxes sharing a top height z-fight, and every other
    # surface in this file is a tile for that reason. Five tiles, not one with
    # decoration on it -- the scrub verge the boundary trees stand on, and the
    # haul track running in from the gate, are both different ground rather than
    # strips painted over the same slab.
    box("TipScrub", (TIP_X0, TIP_X1, TIP_Z0, TIP_Z0 + TIP_VERGE, GROUND_BOTTOM, GROUND),
        TIP_SCRUB, GRASS)
    box("TipScrubWest", (TIP_X0, TIP_X0 + TIP_VERGE, TIP_YARD_Z0, TIP_Z1,
                         GROUND_BOTTOM, GROUND), TIP_SCRUB, GRASS)
    box("TipGroundWest", (TIP_X0 + TIP_VERGE, TIP_GATE_X0, TIP_YARD_Z0, TIP_Z1,
                          GROUND_BOTTOM, GROUND), TIP_DIRT, PEBBLE)
    # The track is the gate's own width carried all the way to the back fence:
    # what the player can see of where they are allowed to walk is the width of
    # the hole they came in through, so the yard cannot close behind them.
    box("TipTrack", (TIP_GATE_X0, TIP_GATE_X1, TIP_YARD_Z0, TIP_Z1,
                     GROUND_BOTTOM, GROUND), TIP_SPOIL, PEBBLE)
    box("TipGroundEast", (TIP_GATE_X1, TIP_X1, TIP_YARD_Z0, TIP_Z1,
                          GROUND_BOTTOM, GROUND), TIP_DIRT, PEBBLE)

    # The two bands either side of the back street, north of the loop. This was
    # one box -- GrassWestMargin, 104 by 364 studs of undifferentiated lawn --
    # and it was the largest single thing in the town by area. The return road
    # now runs up the middle of it, so it is grass, road, grass: the same three
    # bands as every other street here, for the same reason.
    box("GrassBackWest", (WEST_EDGE, RETURN_X0, STREET_Z0, NORTH_Z1,
                          GROUND_BOTTOM, GROUND), LAWN, GRASS)
    box("GrassBackEast", (RETURN_X1, WEST_X0, STREET_Z0, NORTHGATE_Z0,
                          GROUND_BOTTOM, GROUND), LAWN, GRASS)

with group("Road"):
    # Centre dashes, continuing the pattern build_street.py started (dashes on
    # 126, 114, ... going south; 138, 150, ... going north) so the line reads
    # as one road rather than three short ones.
    # Stopped a dash short of the top junction rather than run into it: paint
    # laid across a junction mouth tells a player the road goes straight on,
    # which at the top of this street it no longer does.
    for z in range(138, int(NORTHGATE_Z0) - int(DASH_LENGTH), 12):
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
    # The return leg's line runs the whole length of it now, bottom corner to
    # top junction, and stops a dash short of each the way the main road's does.
    for z in range(int(RETURN_Z0) + 12, int(NORTHGATE_Z0) - int(DASH_LENGTH), 12):
        box(f"DashReturn{z:+d}", (RETURN_MID - CENTRE_WIDTH / 2, RETURN_MID + CENTRE_WIDTH / 2,
                                  float(z), float(z) + DASH_LENGTH,
                                  GROUND + PAINT_LIFT - PAINT_THICK, GROUND + PAINT_LIFT),
            ROAD_PAINT, SMOOTH)
    # The top road, west of the main street's junction: the return leg's traffic
    # crosses the main road here, so the line runs up to the junction mouth and
    # stops rather than being painted through it.
    for x in range(int(RETURN_X1) + 12, int(ROAD_X0) - 12, 12):
        box(f"DashTop{abs(x)}", (float(x), float(x) + DASH_LENGTH,
                                 NORTHGATE_MID - CENTRE_WIDTH / 2,
                                 NORTHGATE_MID + CENTRE_WIDTH / 2,
                                 GROUND + PAINT_LIFT - PAINT_THICK, GROUND + PAINT_LIFT),
            ROAD_PAINT, SMOOTH)
    # The spur, dashed the same way and then stopping. Where the paint stops is
    # the only warning a driver's road gives that it has become a yard, and it
    # stops one dash short of the gate rather than running into the fence.
    for z in range(int(RETURN_Z0) - 12, int(TIP_Z1 + DASH_LENGTH + DASH_GAP), -12):
        box(f"DashSpur{abs(z)}", (ROAD_MID - CENTRE_WIDTH / 2, ROAD_MID + CENTRE_WIDTH / 2,
                                  float(z), float(z) + DASH_LENGTH,
                                  GROUND + PAINT_LIFT - PAINT_THICK, GROUND + PAINT_LIFT),
            ROAD_PAINT, SMOOTH)

with group("Sidewalks"):
    # The four bands north of the street, unchanged: kerb at the road edge,
    # paving against the buildings, both sunk into the ground.
    # Both stop at the top road's south pavement rather than at the town's edge.
    # They are north-south walks and the top road crosses them: a slab carried
    # through would lay a raised kerb across the middle of that carriageway,
    # which is the defect the southern link's note below is written about.
    for prefix, z0, z1 in (("N", NORTH_Z0, NORTHGATE_CLEAR[0]),):
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
    # ...and the same two bands again south of the southern link, so the last
    # two houses and the tip gate have a walk instead of a verge.
    #
    # It is two runs and not one because the link road from the city crosses
    # this band. `road_ew(SOUTHGATE_Z0, SOUTHGATE_Z1, ROAD_X1, ...)` in
    # gen_city.py starts at ROAD_X1, which is exactly where the near walk starts
    # -- so a single slab from the tip to the street would lay a raised kerb
    # across the middle of that carriageway, in another asset, where nothing in
    # this file would ever look. The existing run already ends at CURL_Z, which
    # is SOUTHGATE_CLEAR[1] to the stud; the new one starts at the other side of
    # the same window, read from it rather than typed, and the thirty studs
    # between them are a road crossing, which is what they look like.
    assert SOUTHGATE_CLEAR[1] == CURL_Z, (
        f"the near sidewalk's existing south run ends at {CURL_Z} and the "
        f"southern link's clearance ends at {SOUTHGATE_CLEAR[1]}. They were the "
        f"same number, which is why there is no third slab between them; they "
        f"are not any more, so there is now a {abs(SOUTHGATE_CLEAR[1] - CURL_Z):.0f} "
        f"stud hole in the walk or a slab lying in the link road.")
    box("NearKerbTip", (NEAR_WALK_X0, NEAR_WALK_X0 + KERB_WIDTH, TIP_Z1, SOUTHGATE_CLEAR[0],
                        GROUND - SLAB_SINK, PAVING), KERB_GREY, CONCRETE)
    box("NearPavingTip", (NEAR_WALK_X0 + KERB_WIDTH, NEAR_WALK_X1, TIP_Z1, SOUTHGATE_CLEAR[0],
                          GROUND - SLAB_SINK, PAVING), PAVING_GREY, PEBBLE)
    box("FarKerbS", (FAR_WALK_X1 - KERB_WIDTH, FAR_WALK_X1, FAR_END_Z, STREET_Z0,
                     GROUND - SLAB_SINK, PAVING), KERB_GREY, CONCRETE)
    box("FarPavingS", (FAR_WALK_X0, FAR_WALK_X1 - KERB_WIDTH, FAR_END_Z, STREET_Z0,
                       GROUND - SLAB_SINK, PAVING), PAVING_GREY, PEBBLE)
    # The back street's two walks, running the full length of the return road
    # from the loop's bottom corner to the top road's south pavement. The east
    # one already existed over CURL_Z..STREET_Z0 and stopped there with the road;
    # both now go the whole way, because a pavement that ends where a road
    # carries on is how a player learns to stop walking.
    box("ReturnKerb", (RETURN_X1, RETURN_X1 + KERB_WIDTH, CURL_Z, NORTHGATE_CLEAR[0],
                       GROUND - SLAB_SINK, PAVING), KERB_GREY, CONCRETE)
    box("ReturnPaving", (RETURN_X1 + KERB_WIDTH, RETURN_X1 + SIDEWALK, CURL_Z,
                         NORTHGATE_CLEAR[0], GROUND - SLAB_SINK, PAVING), PAVING_GREY, PEBBLE)
    box("BackKerb", (BACK_WALK_X1 - KERB_WIDTH, BACK_WALK_X1, CURL_Z, NORTHGATE_CLEAR[0],
                     GROUND - SLAB_SINK, PAVING), KERB_GREY, CONCRETE)
    box("BackPaving", (BACK_WALK_X0, BACK_WALK_X1 - KERB_WIDTH, CURL_Z, NORTHGATE_CLEAR[0],
                       GROUND - SLAB_SINK, PAVING), PAVING_GREY, PEBBLE)

    # The top road's own pavements. The north one is continuous -- nothing
    # crosses it, because neither north-south road carries on past the junction
    # -- and the south one is three pieces, carved around the return leg and the
    # main street. Written as a carve rather than as three typed slabs so that
    # moving either road moves the gaps with it.
    _top_walk_x = ((BACK_WALK_X0, RETURN_X0), (RETURN_X1, ROAD_X0),
                   (ROAD_X1, NEAR_WALK_X1))
    # The cut-throughs joining the back street to the main one, one per gap in
    # the west frontage wide enough to hold one. See ALLEYS in the plan for
    # which gaps those are, and for the measurement that says they have to
    # exist at all.
    for _blurb, _az0, _az1 in ALLEYS:
        box(f"Alley{alley_slug(_blurb)}",
            (ALLEY_X0, ALLEY_X1, _az0, _az1,
             GROUND - SLAB_SINK, PAVING), PAVING_GREY, PEBBLE)

    box("TopKerbN", (BACK_WALK_X0, NEAR_WALK_X1, NORTHGATE_Z1, NORTHGATE_Z1 + KERB_WIDTH,
                     GROUND - SLAB_SINK, PAVING), KERB_GREY, CONCRETE)
    box("TopPavingN", (BACK_WALK_X0, NEAR_WALK_X1, NORTHGATE_Z1 + KERB_WIDTH,
                       NORTHGATE_Z1 + NORTHGATE_WALK, GROUND - SLAB_SINK, PAVING),
        PAVING_GREY, PEBBLE)
    for _i, (_tx0, _tx1) in enumerate(_top_walk_x):
        box(f"TopKerbS{_i + 1}", (_tx0, _tx1, NORTHGATE_Z0 - KERB_WIDTH, NORTHGATE_Z0,
                                  GROUND - SLAB_SINK, PAVING), KERB_GREY, CONCRETE)
        box(f"TopPavingS{_i + 1}", (_tx0, _tx1, NORTHGATE_Z0 - NORTHGATE_WALK,
                                    NORTHGATE_Z0 - KERB_WIDTH,
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
        ("Cafe", CAFE_Z0, CAFE_Z1),
        ("Hall", HALL_Z0, HALL_Z1),
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
        box("Counter", (BAKERY_COUNTER_X0, BAKERY_COUNTER_X1,
                        BAKERY_DOOR - 8.0, BAKERY_DOOR + 2.0,
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
# The cafe
# ---------------------------------------------------------------------------

# Tables, and that is the point of it. The library has a desk and the gym has
# machines; this is the one room on the west side whose furniture is arranged
# for two people to sit at rather than for one player to use, which is what a
# town needs somewhere to put a conversation. Nothing here is tagged -- the verb
# has not been agreed, and a tag no service reads is orphaned code by this tree's
# own rules -- but the geometry is laid out for the verb that is coming rather
# than around a decoration.
with group("Cafe"):
    shell("CAFE", CAFE_X0, CAFE_X1, CAFE_Z0, CAFE_Z1, CAFE_DOOR, CAFE_WALL,
          front="awning")

    with group("CafeFittings"):
        # The service counter is against the back wall, not the door, so the walk
        # from the street to the till is the length of the room and the tables
        # are what a player passes on the way. A counter by the door would make
        # the room a queue.
        box("Counter", (CAFE_X0 + 6.0, CAFE_X0 + 6.0 + COUNTER_DEPTH,
                        CAFE_Z0 + 5.0, CAFE_Z1 - 5.0, FLOOR_1, FLOOR_1 + 3.2),
            DESK_TOP, WOOD)
        box("Backbar", (CAFE_X0 + WALL, CAFE_X0 + WALL + 2.0, CAFE_Z0 + 5.0, CAFE_Z1 - 5.0,
                        FLOOR_1, FLOOR_1 + 5.0), CAFE_TIMBER, WOOD)
        box("UrnLeft", (CAFE_X0 + WALL + 0.4, CAFE_X0 + WALL + 1.6,
                        CAFE_DOOR - 4.0, CAFE_DOOR - 2.4, FLOOR_1 + 5.0, FLOOR_1 + 7.4),
            STEEL, METAL)
        box("UrnRight", (CAFE_X0 + WALL + 0.4, CAFE_X0 + WALL + 1.6,
                         CAFE_DOOR + 2.4, CAFE_DOOR + 4.0, FLOOR_1 + 5.0, FLOOR_1 + 7.4),
            STEEL, METAL)
        # Four tables down the window side, each with a chair either side of it.
        # Spaced by division so the row is always centred in whatever depth the
        # cafe has, rather than by a step that would drift off the end of it.
        for _i in range(4):
            _tz = CAFE_Z0 + WALL + (CAFE_Z1 - CAFE_Z0 - 2 * WALL) * (_i + 0.5) / 4
            _tx = CAFE_X1 - 12.0
            box(f"Table{_i + 1}", (_tx - 2.2, _tx + 2.2, _tz - 2.2, _tz + 2.2,
                                   FLOOR_1 + 2.4, FLOOR_1 + 2.8), CAFE_TIMBER, WOOD)
            box(f"TableLeg{_i + 1}", (_tx - 0.4, _tx + 0.4, _tz - 0.4, _tz + 0.4,
                                      FLOOR_1, FLOOR_1 + 2.4), STEEL, METAL)
            chair(_tx - 4.0, _tz, FLOOR_1, side="east", label=f"Chair{_i + 1}A")
            chair(_tx + 4.0, _tz, FLOOR_1, side="west", label=f"Chair{_i + 1}B")
        ceiling_light(CAFE_X0 + 12.0, CAFE_DOOR, CEIL_1)
        ceiling_light(CAFE_X1 - 12.0, CAFE_DOOR, CEIL_1)

# ---------------------------------------------------------------------------
# The community hall
# ---------------------------------------------------------------------------

# One clear floor with a stage at the end of it, which is the opposite of every
# other interior in this town: the gym, the library, the clinic and the shop are
# all rooms full of furniture a player walks between. A hall is a room whose
# whole content is the space in it, and the town did not have one -- there was
# nowhere a crowd could be put that was not a street.
#
# The stacking chairs are against the walls rather than set out in rows. A hall
# with the chairs already out is a hall in the middle of something; a hall with
# them stacked is a hall waiting for whatever is put in it, which is what this
# building is for until an event claims it.
with group("Hall"):
    shell("COMMUNITY HALL", HALL_X0, HALL_X1, HALL_Z0, HALL_Z1, HALL_DOOR, HALL_WALL)

    with group("HallFittings"):
        box("Stage", (HALL_X0 + WALL, HALL_X0 + WALL + 10.0, HALL_Z0 + 4.0, HALL_Z1 - 4.0,
                      FLOOR_1, FLOOR_1 + 2.4), CAFE_TIMBER, WOOD)
        box("StageEdge", (HALL_X0 + WALL + 10.0, HALL_X0 + WALL + 10.4,
                          HALL_Z0 + 4.0, HALL_Z1 - 4.0, FLOOR_1, FLOOR_1 + 2.4),
            TRIM_WHITE, SMOOTH)
        # A curtain behind the stage, non-colliding: it is a backdrop, and a
        # player who walks into it should brush past rather than be stopped by a
        # wall of fabric a foot in front of a real one.
        box("Curtain", (HALL_X0 + WALL + 0.2, HALL_X0 + WALL + 0.6,
                        HALL_Z0 + 3.0, HALL_Z1 - 3.0, FLOOR_1 + 2.4, CEIL_1 - 1.0),
            CURTAIN_RED, FABRIC, collide=False)
        # Stacks of chairs against the two side walls -- north and south, the
        # walls with nothing else on them -- starting east of the stage so none
        # of them stands on it.
        for _i in range(5):
            _sx = HALL_X0 + WALL + 12.0 + (HALL_X1 - HALL_X0 - 2 * WALL - 12.0) * (_i + 0.5) / 5
            for _tag, _sz in (("S", HALL_Z0 + WALL + 2.0), ("N", HALL_Z1 - WALL - 2.0)):
                box(f"ChairStack{_tag}{_i + 1}",
                    (_sx - 1.6, _sx + 1.6, _sz - 1.8, _sz + 1.8, FLOOR_1, FLOOR_1 + 5.6),
                    CHAIR_BLUE, PLASTIC)
        # A notice board by the door: the one surface in town that says what a
        # hall is for, and the only thing in the room a player can read.
        box("NoticeBoard", (HALL_X1 - WALL - 0.6, HALL_X1 - WALL - 0.2,
                            HALL_DOOR + 6.0, HALL_DOOR + 16.0, FLOOR_1 + 4.0, FLOOR_1 + 10.0),
            CAFE_TIMBER, WOOD,
            children=sign("WHAT'S ON", "left", color=(238, 240, 232), size=48))
        for _i in range(3):
            ceiling_light(HALL_X0 + (HALL_X1 - HALL_X0) * (_i + 0.5) / 3, HALL_DOOR, CEIL_1)

# ---------------------------------------------------------------------------
# The houses
# ---------------------------------------------------------------------------

def house(z0, z1, door_z, number,
          x0=HOUSE_X0, x1=HOUSE_X1, walk_x=NEAR_WALK_X1, facing="west"):
    """A small house: path off the sidewalk, door in the wall it faces, two
    rooms either side of a cross partition.

    Written for the east row, which faces west, and generalised rather than
    copied when the back street wanted the same house facing the other way. A
    mirrored duplicate would have been forty lines shorter to write and would
    have put two houses in this town whose wear ramp, boarded windows, cracked
    path and yard junk were two implementations of one idea -- the exact defect
    this tree keeps being repaired for, in a function whose whole job is that
    every house in a row is the same house.

    Everything below is written as a distance from the *front* wall or from the
    sidewalk, and `s` turns that into a direction. There is no branch on
    `facing` except where the two sides genuinely differ: which wall has the
    door in it, which wall has the windows, and which way the sign reads.
    """
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    d0, d1 = door_z - DOORWAY / 2, door_z + DOORWAY / 2

    # The front wall, and the sign of "into the house" from it. The sidewalk is
    # on the other side of the front wall from the rooms, so the same sign also
    # points from the sidewalk toward the house -- which is what makes the path
    # and the yard fall out of one number instead of two.
    front = x0 if facing == "west" else x1
    s = 1.0 if facing == "west" else -1.0

    def inward(d):
        """d studs from the front wall, into the house."""
        return front + s * d

    def outward(d):
        """d studs from the front wall, out into the yard."""
        return front - s * d

    decay = wear_at(door_z)
    wall_colour = worn(HOUSE_WALL, decay)

    with group(f"House{number}"):
        # Starts at the back of the sidewalk, not at the kerb. The sidewalk is
        # already paved from the kerb to the property line -- by build_street.py
        # along the original street and by this file's own extensions past it --
        # so a path drawn from the kerb laid eleven studs of stone in the same
        # plane as eleven studs of paving, in two different files, and the two
        # flickered against each other outside every front door in town.
        #
        # Past PATH_CRACK_WEAR it stops being one slab and becomes three with
        # weeds through the joints. The pieces are cut out of the same span the
        # whole path occupies, so a broken path is exactly as long as a sound
        # one and the door is never left with a step of bare grass in front of
        # it -- a decorative crack that a player has to walk round is a trip
        # hazard, not a detail.
        #
        # Both ends are sorted rather than assumed in order: on the back street
        # the sidewalk is east of the front wall instead of west of it, and a
        # box whose x0 is greater than its x1 is not a mirrored box, it is a
        # part with a negative size.
        path_lo, path_hi = sorted((walk_x, front))
        if decay < PATH_CRACK_WEAR:
            box("Path", (path_lo, path_hi, door_z - 2.2, door_z + 2.2,
                         PAVING - 0.5, PAVING), PATH_STONE, PEBBLE)
        else:
            span = path_hi - path_lo
            for i in range(3):
                a = path_lo + span * i / 3
                b = path_lo + span * (i + 1) / 3
                # The gap grows with the decay, and only between slabs -- the
                # two ends stay put against the paving and the doorstep. Which
                # of those two ends is the doorstep depends on which way the
                # house faces, and neither end moves either way, so this needs
                # no sign of its own.
                nick = 0.5 * (decay - PATH_CRACK_WEAR) / (1.0 - PATH_CRACK_WEAR)
                box(f"PathSlab{i + 1}",
                    (a if i == 0 else a + nick, b if i == 2 else b - nick,
                     door_z - 2.2, door_z + 2.2, PAVING - 0.5, PAVING),
                    worn(PATH_STONE, decay, RUBBLE), PEBBLE)

        with group("HouseStructure"):
            box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1),
                FLOOR_INDOOR, MARBLE)
            box("Roof", (x0, x1, z0, z1, CEIL_1, CEIL_1 + SLAB), ROOF_GREY, SLATE)
            # Felt patches, laid on the roof rather than cut into it: a hole in
            # the roof of a house the player can walk into is a hole in the
            # ceiling of a room, and every one of these houses has a bed in it.
            # The count is read off the wear so it climbs with everything else
            # instead of being a second decision.
            if decay >= ROOF_PATCH_WEAR:
                patches = 1 + int((decay - ROOF_PATCH_WEAR) * 6)
                for i in range(patches):
                    pz = z0 + (z1 - z0) * (i + 1) / (patches + 1)
                    pa, pb = sorted((inward(4.0 + 3.0 * i), inward(14.0 + 3.0 * i)))
                    box(f"RoofPatch{i + 1}",
                        (pa, pb, pz - 4.0, pz + 4.0,
                         CEIL_1 + SLAB, CEIL_1 + SLAB + 0.12),
                        ROOF_PATCH, FABRIC, collide=False)
            # Only the door moves between the two rows. Both walls are drawn
            # either way, so a house that faces east is not a house with a wall
            # missing.
            wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, CEIL_1), wall_colour,
                 along="z", doors=((d0, d1),) if facing == "west" else ())
            wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, CEIL_1), wall_colour,
                 along="z", doors=((d0, d1),) if facing == "east" else ())
            wall("WallSouth", (x0, x1, z0, iz0, FLOOR_1, CEIL_1), wall_colour, along="x")
            wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, CEIL_1), wall_colour, along="x")
            # A boarded window is the same opening with plywood in it instead of
            # glass, so the wall behind is unchanged and the house stays a house
            # a player can be sent into. The south window goes first because it
            # is the one furthest from the door.
            boards = (2 if decay >= BOARD_BOTH_WEAR
                      else 1 if decay >= BOARD_WEAR else 0)
            # The windows are in the back wall, whichever wall that is.
            win_x0, win_x1 = sorted((inward(HOUSE_WIDTH - WALL) + s * 0.4,
                                     inward(HOUSE_WIDTH) - s * 0.4))
            for i, (a, b) in enumerate(((iz0 + 3.0, iz0 + 7.0), (iz1 - 7.0, iz1 - 3.0))):
                opening = (win_x0, win_x1, a, b, FLOOR_1 + 3.0, FLOOR_1 + 7.0)
                if i < boards:
                    box(f"WindowBoard{i + 1}", opening, BOARD_PLY, PLANKS, collide=False)
                else:
                    glazing(f"Window{i + 1}", opening, along="z", panes=2)
            plate_x0, plate_x1 = sorted((outward(0.6), outward(0.1)))
            box("Numberplate", (plate_x0, plate_x1, door_z - 1.5, door_z + 1.5,
                                FLOOR_1 + 8.0, FLOOR_1 + 9.5),
                worn(TRIM_WHITE, decay, RUBBLE), SMOOTH,
                children=sign(number, "left" if facing == "west" else "right",
                              color=(60, 66, 84), size=48))

        # The front yard, which is the half of a house a player actually reads:
        # they walk past it at eye level and they only ever see the roof from a
        # distance. Weeds first, then dumped rubbish, both kept east of the
        # property line so nothing here can reach the sidewalk the route graph
        # walks down -- a tyre standing on the pavement is an obstruction on the
        # only path through town.
        with group("HouseYard"):
            for i in range(round(decay * 6)):
                wa, wb = sorted((walk_x + s * (1.5 + (i % 3) * 3.0),
                                 walk_x + s * (2.6 + (i % 3) * 3.0)))
                wz = z0 + 3.0 + (z1 - z0 - 6.0) * ((i * 7) % 11) / 10.0
                if abs(wz - door_z) < 3.4:      # not in the path itself
                    wz += 5.0
                box(f"Weed{i + 1}", (wa, wb, wz, wz + 1.1,
                                     GROUND, GROUND + 0.9 + 0.4 * (i % 3)),
                    WEED, LEAFY_GRASS, collide=False)
            if decay >= JUNK_WEAR:
                ta, tb = sorted((walk_x + s * 2.0, walk_x + s * 5.4))
                box("YardTyre", (ta, tb, door_z + 5.0, door_z + 8.4,
                                 GROUND, GROUND + 1.1), (44, 44, 46), PEBBLE)
                aa, ab = sorted((outward(4.2), outward(1.4)))
                box("YardAppliance", (aa, ab, door_z - 9.0, door_z - 6.0,
                                      GROUND, GROUND + 4.2),
                    worn(TRIM_WHITE, decay, RUBBLE), CORRODED_METAL)

        with group("HouseFittings"):
            # The partition runs the depth of the house, so it is an along-z wall
            # and its door is a range in z -- the same axis as the front door it
            # lets the player walk straight through. Declared along-x here, the
            # door never overlaps the wall's thin extent and wall() fills the gap
            # with one box that reaches across the yard into the next building.
            pa, pb = sorted((inward(WALL + 6.0), inward(WALL + 7.0)))
            wall("Partition", (pa, pb, iz0 + 4.0, iz1 - 4.0, FLOOR_1, CEIL_1),
                 PARTITION_PALE, PLASTIC, along="z", doors=((door_z - 3.0, door_z + 3.0),))
            sa, sb = sorted((inward(WALL + 11.0), inward(WALL + 15.0)))
            box("Sofa", (sa, sb, iz1 - 9.0, iz1 - 5.0, FLOOR_1 + 1.2, FLOOR_1 + 2.0),
                (140, 96, 80), FABRIC)
            desk(inward(WALL + 18.0), door_z + 2.0, FLOOR_1,
                 side="west" if facing == "west" else "east",
                 width=4.0, depth=2.2, label="Table")
            ba, bb = sorted((inward(WALL + 8.0), inward(WALL + 15.0)))
            box("Bed", (ba, bb, iz0 + 4.0, iz0 + 10.0, FLOOR_1 + 0.8, FLOOR_1 + 1.6),
                (214, 218, 224), FABRIC)
            ceiling_light(inward(WALL + 18.0), door_z, CEIL_1)


for z0, z1, door_z, number in HOUSES:
    house(z0, z1, door_z, number)

# The back street's row, the same house turned round to face the return road.
for z0, z1, door_z, number in BACK_ROW:
    house(z0, z1, door_z, number,
          x0=BACK_HOUSE_X0, x1=BACK_HOUSE_X1, walk_x=BACK_WALK_X0, facing="east")


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
SHOP_COUNTER_X0 = -30.0
SHOP_COUNTER_X1 = SHOP_COUNTER_X0 + COUNTER_DEPTH
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
# The tip
# ---------------------------------------------------------------------------
# What the road runs out into. The street's decay gradient has to arrive
# somewhere, and a gradient that ends at a fence with a field behind it says the
# houses got worse for no reason; a gradient that ends at the place the town
# takes its refuse says why.
#
# Everything searchable in here carries SCAVENGE_TAG. That is the whole of this
# generator's share of scavenging: geometry stamps a tag, and the rules find it
# by tag and by nothing else -- the same seam AgesGymEquipment already runs on,
# and the reason a real art pass can replace every box below without touching a
# line of Luau.

# Where each object stands, as (x, z) with its own plan half-extents, so the
# clearance rule below is reading the same numbers the geometry is drawn from.
# Laid out by hand rather than scattered by a rule: a tip is a place where
# somebody dumped things where there was room, and a grid reads as a car park.
TIP_MOUNDS = [
    # x, z, radius, height
    (-230.0, -455.0, 18.0, 16.0),
    (-145.0, -458.0, 14.0, 12.0),
    (-178.0, -428.0, 11.0, 9.0),
    (-25.0, -458.0, 12.0, 10.0),
]
TIP_SKIPS = [
    # x, z, rusty
    (-180.0, -466.0, False),
    (-110.0, -468.0, True),
    (-15.0, -424.0, False),
    (-198.0, -466.0, True),
]
TIP_PILES = [
    # x, z, size
    (-245.0, -420.0, 5.0),
    (-118.0, -448.0, 5.0),
    (-48.0, -455.0, 4.0),
    (-195.0, -450.0, 4.0),
]
TIP_WRECKS = [
    (-215.0, -422.0),
    (-148.0, -422.0),
    (-42.0, -422.0),
]
TIP_MASTS = [
    (-105.0, -450.0),
    (-28.0, -416.0),
]
MAST_HALF = 1.8

# How much room the yard leaves between one thing and the next, and between
# anything and the edge of the working ground.
#
# Derived, not chosen: BODY_WIDTH is already this file's answer to "how much
# room does a person need", arrived at when the corner shop's counter was found
# overhanging the only standing room behind it. Twice that is a gap two people
# could pass in, which is the difference between a yard with routes through it
# and a yard that is a maze of dead ends. A tip is meant to be picked through,
# and a player who has to reverse out of every gap has been given scenery rather
# than a place.
TIP_CLEAR = 2 * BODY_WIDTH

# This is the check that mattered. The first version of this layout was typed
# out by eye and read as fine in the table: every number was inside the yard and
# none was in the track. Measured, it had a floodlight mast standing inside a
# spoil mound, a wreck buried in another one, and a heap a stud off the office
# wall -- because a table of centres says nothing about extents, and four kinds
# of object with four different footprints is exactly where reading coordinates
# stops working. Nothing else in the tree would have caught it: check_town's
# overlap check compares *buildings*, and a spoil heap is not a building.
_placed = (
    [(x, z, r, r, f"mound at ({x:.0f},{z:.0f})") for x, z, r, _h in TIP_MOUNDS]
    + [(x, z, SKIP_HALF_X, SKIP_HALF_Z, f"skip at ({x:.0f},{z:.0f})")
       for x, z, _r in TIP_SKIPS]
    + [(x, z, s, s * 0.8, f"pile at ({x:.0f},{z:.0f})") for x, z, s in TIP_PILES]
    + [(x, z, WRECK_HALF_X, WRECK_HALF_Z, f"wreck at ({x:.0f},{z:.0f})")
       for x, z in TIP_WRECKS]
    + [(x, z, MAST_HALF, MAST_HALF, f"mast at ({x:.0f},{z:.0f})")
       for x, z in TIP_MASTS]
    + [((HUT_X0 + HUT_X1) / 2, (HUT_Z0 + HUT_Z1) / 2,
        (HUT_X1 - HUT_X0) / 2, (HUT_Z1 - HUT_Z0) / 2, "the weighbridge office")]
)


def _plan_gap(a, b):
    """Distance between two axis-aligned footprints, 0 if they touch or overlap."""
    ax, az, ahx, ahz, _ = a
    bx, bz, bhx, bhz, _ = b
    return math.hypot(max(abs(bx - ax) - ahx - bhx, 0.0),
                      max(abs(bz - az) - ahz - bhz, 0.0))


for _i, _a in enumerate(_placed):
    _x, _z, _hx, _hz, _what = _a
    assert _x + _hx <= TIP_GATE_X0 - TIP_CLEAR or _x - _hx >= TIP_GATE_X1 + TIP_CLEAR, (
        f"{_what} reaches x {_x - _hx:.1f}..{_x + _hx:.1f} and the haul track is "
        f"{TIP_GATE_X0}..{TIP_GATE_X1}. The track is the width of the gate on "
        f"purpose -- it is the only thing telling the player where they may walk "
        f"-- so nothing may stand in it or within {TIP_CLEAR:.1f} of it.")
    assert (TIP_YARD_X0 + TIP_CLEAR <= _x - _hx and _x + _hx <= TIP_X1 - TIP_CLEAR
            and TIP_YARD_Z0 + TIP_CLEAR <= _z - _hz
            and _z + _hz <= TIP_Z1 - TIP_CLEAR), (
        f"{_what} reaches x {_x - _hx:.1f}..{_x + _hx:.1f} "
        f"z {_z - _hz:.1f}..{_z + _hz:.1f}, which leaves under {TIP_CLEAR:.1f} "
        f"studs against the edge of the working yard at x {TIP_YARD_X0}..{TIP_X1} "
        f"z {TIP_YARD_Z0}..{TIP_Z1}. Either it is outside the yard or a player "
        f"cannot get round the back of it.")
    for _b in _placed[_i + 1:]:
        _d = _plan_gap(_a, _b)
        assert _d >= TIP_CLEAR, (
            f"{_what} and {_b[4]} are {_d:.1f} studs apart, under the "
            f"{TIP_CLEAR:.1f} the yard leaves between two things. At 0.0 they "
            f"are standing in each other.")

# The gate that gets built is the gate that was declared. The first version of
# chainlink() laid panels on one pitch across the whole boundary and dropped the
# ones whose middle landed in the gap, which rounded this opening from 33 studs
# to 24 and left a five-stud shoulder reading as half a stud -- while
# TIP_GATE_MARGIN still said 5.0 in the source. Asked of fence_runs() rather
# than of the constants, because the constants were never what was wrong.
_gate = fence_runs(TIP_X0, TIP_X1, ((TIP_GATE_X0, TIP_GATE_X1),))
assert len(_gate) == 2 and _gate[0][1] == TIP_GATE_X0 and _gate[1][0] == TIP_GATE_X1, (
    f"the tip's fence comes out as {_gate}, which does not leave an opening at "
    f"exactly x {TIP_GATE_X0}..{TIP_GATE_X1}. The haul track is drawn to the "
    f"declared width, so a narrower hole in the fence is two panels standing in "
    f"the track.")

with group("Tip"):
    # The boundary. Chain-link across the north with the gate in it and up the
    # east seam against the city; trees on the south and west, which is what the
    # map does instead of stopping -- the same treatment works_boundary() gives
    # the city's south edge, continued west so the bottom of the world is one
    # line rather than two ideas meeting in the middle.
    chainlink("TipFenceN", TIP_X0, TIP_X1, TIP_Z1, along="x",
              gaps=((TIP_GATE_X0, TIP_GATE_X1),))
    chainlink("TipFenceE", TIP_Z0, TIP_Z1, TIP_X1, along="z")

    # The gates themselves, swung back into the yard against nothing, which is
    # what a working tip's gates look like at every hour a player will ever see
    # them. They are the reason the opening reads as a gate rather than as a
    # length of missing fence, and they are the length of one panel so the eye
    # gets the width of the hole from the width of the leaf.
    for i, gx in enumerate((TIP_GATE_X0, TIP_GATE_X1)):
        box(f"TipGateLeaf{i + 1}",
            (gx - FENCE_THICK / 2, gx + FENCE_THICK / 2,
             TIP_Z1 - FENCE_POST_PITCH, TIP_Z1, GROUND, GROUND + FENCE_HEIGHT),
            CHAINLINK, METAL, transparency=0.4)
        box(f"TipGateEdge{i + 1}",
            (gx - 0.25, gx + 0.25, TIP_Z1 - FENCE_POST_PITCH - 0.25,
             TIP_Z1 - FENCE_POST_PITCH + 0.25, GROUND, GROUND + FENCE_HEIGHT),
            STEEL, METAL)

    # The sign, on the north face of the fence so it is read on the way in. It
    # sits a hair proud of the posts rather than in the same plane as the mesh:
    # two slabs sharing a face z-fight, and the fence is the one surface in this
    # compound a player looks straight through.
    #
    # "back" is +z. The player walks south down the spur, so +z is the face
    # turned towards them; a sign on the other face would be legible only from
    # inside the yard they have not gone into yet.
    box("TipSignBoard",
        (TIP_SIGN_X0, TIP_SIGN_X1, TIP_Z1 + 0.3, TIP_Z1 + 0.9,
         GROUND + FENCE_HEIGHT, GROUND + FENCE_HEIGHT + TIP_SIGN_H),
        TIP_SIGN_BOARD, SMOOTH,
        children=sign("TOWN TIP", "back", color=TIP_SIGN_INK,
                      size=round(TIP_SIGN_LETTER * SIGN_PX),
                      width=round(TIP_SIGN_W * SIGN_PX),
                      height=round(TIP_SIGN_H * SIGN_PX)))
    # What the sign above it does not say, and the reason a player walks in
    # rather than looking at the gate and turning round. It is not a prompt --
    # the prompt is the three dots on the skips -- it is the permission that
    # makes walking into somebody else's yard a thing this town does.
    box("TipNotice",
        (TIP_SIGN_X1 - TIP_NOTICE_W, TIP_SIGN_X1, TIP_Z1 + 0.3, TIP_Z1 + 0.9,
         GROUND + TIP_NOTICE_Y0, GROUND + TIP_NOTICE_Y0 + TIP_NOTICE_H),
        worn(TRIM_WHITE, 0.5, RUBBLE), SMOOTH,
        children=sign("SALVAGE PERMITTED", "back", color=(52, 56, 64),
                      size=round(TIP_NOTICE_LETTER * SIGN_PX),
                      width=round(TIP_NOTICE_W * SIGN_PX),
                      height=round(TIP_NOTICE_H * SIGN_PX)))

    # The weighbridge plate: a steel deck set into the track at the gate, so the
    # first ten strides inside the fence are on something that says what this
    # place does. Low enough to run straight over.
    box("Weighplate", (TIP_GATE_X0 + 1.0, TIP_GATE_X1 - 1.0, -432.0, -414.0,
                       GROUND, GROUND + 0.3), STEEL, METAL)

    for i, (x, z, radius, height) in enumerate(TIP_MOUNDS):
        spoil_mound(x, z, radius, height, label=f"Spoil{i + 1}")
    for i, (x, z, rusty) in enumerate(TIP_SKIPS):
        scavenge_skip(x, z, label=f"Skip{i + 1}", rusty=rusty)
    for i, (x, z, size) in enumerate(TIP_PILES):
        scavenge_pile(x, z, label=f"Pile{i + 1}", size=size)
    for i, (x, z) in enumerate(TIP_WRECKS):
        scavenge_wreck(x, z, label=f"Wreck{i + 1}")

    # Two masts over the yard rather than street lamps: a lamp on a pavement arm
    # leaning over a dirt yard is the wrong object, and its base would stand at
    # PAVING half a stud above ground that tops at GROUND.
    for i, (x, z) in enumerate(TIP_MASTS):
        with group(f"TipMast{i + 1}"):
            with at(x, z, floor=GROUND):
                part("Base", (0, 0, 0), (2 * MAST_HALF, 0.6, 2 * MAST_HALF),
                     STEEL, CONCRETE)
                part("Mast", (0, 0.6, 0), (0.8, 22.0, 0.8), STEEL, METAL)
                part("Head", (0, 22.0, 0), (3.6, 1.0, 1.6), FITTING, NEON,
                     children=point_light(LAMP_LIGHT, 2.0, 40.0))

    # The boundary treeline, spaced the way gen_city.py spaces its own so the
    # two halves have the same density where they meet at x = 8.
    for i in range(int((TIP_X1 - TIP_X0) / TIP_TREE_PITCH)):
        tx = TIP_X0 + TIP_TREE_PITCH / 2 + i * TIP_TREE_PITCH
        tree(tx, TIP_Z0 + 6.0 + (i % 3) * 4.0, GROUND,
             height=17.0 + (i % 4) * 3.0, spread=12.0 + (i % 3) * 2.0,
             label=f"TipTreeS{i + 1}")
    for i in range(int((TIP_Z1 - TIP_YARD_Z0) / TIP_TREE_PITCH)):
        tz = TIP_YARD_Z0 + TIP_TREE_PITCH / 2 + i * TIP_TREE_PITCH
        tree(TIP_X0 + 6.0 + (i % 3) * 4.0, tz, GROUND,
             height=16.0 + (i % 3) * 3.0, spread=11.0 + (i % 2) * 3.0,
             label=f"TipTreeW{i + 1}")

shell("Weighbridge", HUT_X0, HUT_X1, HUT_Z0, HUT_Z1, HUT_DOOR, worn(BRICK_PALE, 0.7),
      wall_mat=CONCRETE)
with group("WeighbridgeFittings"):
    desk(HUT_X0 + 6.0, HUT_DOOR, FLOOR_1, side="east")
    chair(HUT_X0 + 9.0, HUT_DOOR, FLOOR_1, side="east")
    ceiling_light((HUT_X0 + HUT_X1) / 2, HUT_DOOR, CEIL_1)

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
    # The back street, lit both sides now that it has houses on one of them.
    # Laid at the row's own pitch rather than at a step of their own, so a lamp
    # stands between every second pair of front doors all the way up.
    for _i in range(len(BACK_ROW) + 1):
        _lz = BACK_ROW_Z1 - _i * 2 * (HOUSE_DEPTH + NEIGHBOUR_GAP)
        if _lz < CURL_Z:
            break
        street_lamp(BACK_WALK_X1 - 3.5, _lz, 1)
    for z in (-150.0, -195.0, -240.0, -280.0):
        street_lamp(RETURN_X1 + 3.5, z, -1)
    # ...and up the east walk, which used to end with the road at STREET_Z0.
    for _i in range(1, 6):
        _lz = STREET_Z0 + _i * 88.0
        if _lz > NORTHGATE_CLEAR[0]:
            break
        street_lamp(RETURN_X1 + 3.5, _lz, -1)

    # Trees filling the grass between buildings, so the town has a street to
    # itself rather than a row of boxes.
    # The south meadow gets a few trees so the loop's far side reads as grass
    # rather than as a void; the frontages along the loop stay clear for the
    # buildings that will one day front them.
    # The row up the west verge starts at z=160, not z=88: build_street.py
    # already plants one at (-104, 88) as the last of its own row, and the two
    # were landing in exactly the same square from two different files -- one
    # trunk inside another, in two assets neither of which could see the other.
    #
    # Four of these used to stand at x -220, which was open meadow when they
    # were planted and is the middle of the back street's carriageway now that
    # the return leg runs the length of it. They have moved to the verge between
    # that road's east pavement and the west grass band -- the only strip on this
    # side that is still grass -- and the x is derived from the two edges of that
    # strip rather than typed, so a wider pavement moves the trees instead of
    # standing them on it.
    # The one at (-104, 220) has gone with them. It stood on the largest bare
    # patch of the west verge, and that patch is the cafe's forecourt now -- a
    # tree in the middle of a paved apron between a door and a pavement is an
    # obstacle, not a hedge.
    #
    # The one at (-104, 160) has gone for the same reason, but it was not spotted
    # by eye: the alley between the gym and the library was cut straight through
    # it, trunk dead centre of an eight-stud path, and the asset built and both
    # checkers passed for it. Nothing either of them measures is "is there a tree
    # in this footpath". So the list is filtered rather than edited -- a deleted
    # line is a fact about today's alleys, and clear_of_alleys is a fact about
    # whatever the alleys turn out to be.
    VERGE_MID = (RETURN_X1 + SIDEWALK + WEST_X0) / 2
    TREE_SPREAD = 10.0
    for x, z in ((-104.0, 160.0),
                 (-130.0, -120.0), (-130.0, -164.0), (-140.0, -214.0),
                 (VERGE_MID, -50.0), (VERGE_MID, 50.0), (VERGE_MID, 150.0),
                 (VERGE_MID, 200.0), (VERGE_MID, 260.0),
                 (-215.0, -320.0), (-150.0, -320.0), (-100.0, -320.0)):
        if ALLEY_X0 <= x <= ALLEY_X1 and not clear_of_alleys(z, TREE_SPREAD):
            continue
        tree(x, z, GROUND, spread=TREE_SPREAD)

# ---------------------------------------------------------------------------
# Place points
# ---------------------------------------------------------------------------

with group("PlacePoints"):
    for pid, x, z, floor, label in PLACE_POINTS:
        place_point(pid, x, z, floor, label)

print(rbxmx.write(TOWN, "Town"))
