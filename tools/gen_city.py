#!/usr/bin/env python3
"""Generates assets/City.rbxmx: the city that grew east of the town.

Run from tools/:  python3 gen_city.py

The town (Town.rbxmx) built a road corridor and a handful of buildings on the
west side of the player's street. This file builds what lies east and north of
it: a full urban grid of six avenues and six cross streets, filled not with a
second copy of the suburb but with a working city --

  * 72 houses, two layouts and eight wall tones so an avenue reads as houses
    rather than as one long wall;
  * fourteen two-storey apartment buildings (56 households), each with its own
    navigable stair;
  * a covered mall with eight shops;
  * a central park with a pond and a fountain;
  * three four-storey office towers around a plaza;
  * a restaurant row with a dining terrace;
  * twenty storefronts lining the main street;
  * thirteen civic buildings (cinema to farm) across the north end;
  * a stadium on the headland, and the school's playing fields -- basketball,
    tennis, playground and running track -- on the open land west of the town;
  * two greenfield blocks left as empty, tree-lined terrain.

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
  * The apartment stair is the town workplace's stair, laid down again: sixteen
    1.0-rise steps, a one-stud guard on the east of the flight, and an open
    upper floor. The walker climbs south to north and steps off onto the slab;
    PathfindingService walks it without help.
"""

import math
import zlib

import rbxmx
from rbxmx import (
    ASPHALT, BRICK, CONCRETE, CORRODED_METAL, DIAMOND_PLATE, FABRIC, GLASS,
    GRANITE, GRASS, LEAFY_GRASS, LIMESTONE, MARBLE, METAL, NEON, PAVEMENT,
    PEBBLE, PLASTIC, PLANKS, SLATE, SMOOTH, WOOD,
)
from rbxmx import at, box, group, part, point_light, sign, spot_light

from world_plan import (
    CEIL_1, CEIL_2, DOORWAY, FLOOR_1, FLOOR_2, GROUND, GROUND_STEP, KERB, PAVING,
    PLACE_ID_ATTRIBUTE, PLACE_LABEL_ATTRIBUTE, PLACE_TAG, SLAB, STOREY,
    TRUNK_WIDTH, WALL,
    # The town's own street, so the gate road can tee off it by name instead of
    # a copied literal that silently stops matching when the town moves.
    PROPERTY_X, ROAD_X0, ROAD_X1,
    GATE_CLEAR, GATE_WALK, GATE_Z0, GATE_Z1,
    # The second link out of town, and the east edge of the plot the Green lies
    # behind. HOUSE_EAST_X is a measurement of House.rbxmx, which this file never
    # opens -- build_street.py re-measures it every run. PATH_HALF is the front
    # path's width, borrowed so the back one matches it.
    BACK_GATE_MID, HOUSE_EAST_X, PATH_HALF,
    SOUTHGATE_CLEAR, SOUTHGATE_WALK, SOUTHGATE_Z0, SOUTHGATE_Z1,
    # The third link, at the top of the town. Unlike the other two its band is
    # not read off anything in this file -- there is no cross street on the
    # connector's west flank at that z -- so the connector's verge is carved for
    # it here rather than the road being fitted to a verge that already yields.
    NORTHGATE_CLEAR, NORTHGATE_MID, NORTHGATE_WALK, NORTHGATE_Z0, NORTHGATE_Z1,
    # The south edge of the world. Transcribed over there, asserted here.
    MAP_SOUTH_EDGE,
    # Half the baseplate. The city's east edge and the west estate's west edge
    # are both this, and neither of them is a typed 1024 any more.
    MAP_EDGE,
    # The school's playing fields, laid on the empty land west of the town. The
    # town owns the school and the way in; this file owns the fields themselves,
    # because the court, track and playground builders live here and a second
    # copy of them in gen_town.py would be two hundred lines of the same asphalt.
    # Four numbers cross the seam: the town's west edge and the south face of
    # the school, which are where the fields stop, and the middle and width of
    # the paved way house "7" gave up, which is where the path meets them.
    SCHOOL_Z0, STREET_Z0, TOWN_WEST_EDGE, FIELDS_WAY_MID, FIELDS_WAY_PAVE,
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
# How far apart to space waypoints along a straight run. PlaceService joins
# points within 70 studs (check_city's ROUTE_LINK), so this is that less a
# two-stud margin: the margin is what stops a chain silently breaking when a
# road's ends get rounded or a run is shortened by a stud at one end.
#
# It was a bare 68 in nine separate `range(...)` calls, which is the shape of a
# number that gets changed in eight places. Safe range 40-68: below 40 the
# point count grows for no routing benefit, above 68 there is no margin left
# and the next small edit anywhere breaks a chain nobody is looking at.
ROUTE_STEP = 68
# How far the city's own grass sits under the town's ground plane.
#
# Not one step but three, and the extra two are a budget rather than padding:
# the lowest paved thing in the city is the Circle's ring, which sinks once to
# let the spoke roads win its four mouths and again to settle its own facet
# seams. Both sinks eat into the gap between road and lawn, and when this was a
# bare GROUND - 0.02 they ate all of it -- sixteen facets of ring finished
# within a rounding error of the grass under them. The assertion next to
# CIRCLE_SEAM is what holds the budget; this is the budget.
CITY_GRASS_SINK = GROUND_STEP * 3
CITY_GRASS_TOP = GROUND - CITY_GRASS_SINK
# The same hairline, the other way up, for a lawn this file draws over ground
# some other generator laid, or over its own CityGround. Both of those top at a
# known plane and a second lawn at the same height is the same flicker.
GRASS_LIFT = GROUND_STEP
# A floor laid on a floor.
#
# The usual building here stands on bare ground and pours a full SLAB, topping
# at FLOOR_1. That is right until the block it stands on is paved -- the mall's
# shop units on the mall's own screed, the bank and the civic blocks on the
# government quarter's setts -- and then the slab finishes in the paving's plane
# and the two fight over every pixel of the floor. Those floors are drawn as a
# thin inlay one step proud of what they sit on instead, which is also what they
# are: a unit's floor finish over the concourse it was fitted into.
#
# Three steps rather than one so the part is thicker than Roblox's 0.05 minimum
# with room to spare; a 0.02 slab is legal to write and gets rounded to
# something else on load.
FLOOR_INLAY = GROUND_STEP * 3

# ---------------------------------------------------------------------------
# The plan
# ---------------------------------------------------------------------------

# City region: east of the town's grass (x 8), north of the town's east margin
# (z 60), inside the enlarged 2048 baseplate (x/z +/- MAP_EDGE). The connector's
# south end and the bridge waypoints land in the grass south of z 80.
CITY_X0, CITY_X1 = 8.0, MAP_EDGE
# The north edge was 1120 -- the old top of the grid -- and the precinct loop
# put a service road at z 1124..1146 and carried the connector to 1148, which
# left both of them standing on nothing: their own slabs are solid, so every
# check passed, and the only symptom would have been open sky under the kerb
# the first time a player walked to the top of the map. Derived from the road
# rather than typed, so the ground follows the next thing laid up here.
CITY_Z0, CITY_Z1 = 60.0, 1152.0

# The connector: a north-south road as wide as the town's (23 studs) that
# carries the player out of town and up into the city. It runs the city's full
# length west of the grid.
CONN_X0, CONN_X1 = 19.0, 42.0
# North end raised from 1120 to 1148 so the precinct's new service road has a
# through route to T into at its west end rather than dead-ending on the map
# edge. See "The precinct loop" below. Nothing is built north of 1120.
CONN_Z0, CONN_Z1 = 60.0, 1148.0
CONN_WALK = 6.0
CONN_MID = (CONN_X0 + CONN_X1) / 2

# The gate road -- the only link between the town and the city -- and the window
# it has to thread. See the note at its call site for how the band was measured.
# GATE_Z0/Z1/WALK come from world_plan because gen_town.py has to keep the east
# frontage clear of them and cannot import this file to find out where they are.
GATE_FULL = [GATE_CLEAR]
# The northern link, the same way: the connector's west verge has to yield to it
# exactly as it yields to the gate road, or the road arrives at a kerb.
NORTHGATE_FULL = [NORTHGATE_CLEAR]

# Six avenues, north-south, 24 studs wide, sidewalks 6 wide.
#
# They were 14, which is one lane and a wing mirror. Cars are coming, and a
# 14-stud carriageway with parked traffic on it is a road no vehicle can pass
# another on -- so the whole grid was rebuilt around 24, which is two real lanes
# plus the weaving room a junction needs. The town's own road is 23 and the
# connector matches it, so 24 also puts the city's streets in the same family as
# the road the player arrives on rather than making the city feel like a scale
# model of itself.
#
# **The positions below are chosen so the grid's east edge does not move.**
# AVE[5] + AVE_W[5] is still exactly 793, which is CS_X1 and the west shore of the
# bay -- so the beach, the baywalk, the piers and the sports park are all
# untouched by this change. What paid for the extra asphalt is the block
# interior, which goes from 114 studs to 102: the avenue pitch dropped from 140
# to 138 and the roads took 10 studs each out of the middle. That is affordable
# because a house row needs at most 40 studs (a 32 style plus an 8 setback) and
# two rows plus a 22-stud lane still fit. It is *only just* affordable, which is
# why the next person to widen anything here has to move the east edge and
# re-lay the bay rather than taking another slice out of the blocks.
#
# The avenues stop at the last cross street and do not continue into the band
# beyond it. They used to run to z 1120, which is the top of the map, and the
# civic row and the north shops were laid out in their own coordinates without
# ever being asked where the roads were -- so avenue 1 ran through the middle of
# the cinema, avenue 2 through the arcade, avenue 3 through the police station,
# avenue 4 through the warehouse, avenue 5 through the post office, avenue 6
# through the dentist, and all six through all eight north shops. Everything
# north of the last cross street is a pedestrian precinct now, which is what the
# north strip's own docstring has claimed all along ("facing south toward the
# civic plaza") and what its benches and lamps were always positioned for.
AVE = [79.0, 217.0, 355.0, 493.0, 631.0, 769.0]
AVE_WALK = 6.0
AVE_Z0 = 60.0

# **Not every avenue is the same road, and the width is how the city says so.**
#
# This used to be one number for all six. The owner asked for poorer
# neighbourhoods to have narrower streets and the answer was that every street in
# the city was 24 studs wide, everywhere, which is a city with no districts in it
# -- the block plan says the north is houses and the south is towers, and a
# player walking between them crossed the same road six times.
#
# Which avenues narrow is *not* a taste call, because the file already knows the
# answer and states it 100 lines down: `WORKS_AVE = (0, 3, 5)`, "those are the
# ones with somewhere to go". Avenues 1, 4 and 6 carry through the city and on
# into the works, so they are the arterials; avenue 3 is the Circle's own spine
# and feeds a roundabout. That leaves 2 and 5, which begin at the step-down band
# and end at the last cross street and serve nothing but the blocks either side
# of them. They are the local roads and they are the ones that come down.
#
# 16 rather than 24 is one lane each way plus kerbside room, against the
# arterials' two lanes each way. The contrast is a third of the width, which is
# what makes it read from across a block -- 20 would have been safer and
# invisible, and an invisible change to a road network is not worth the 23 sites
# it costs. Safe range 14 .. 20: below 14 two cars cannot pass, and above 20 you
# are back to a grid with one road in it.
AVE_W_MAIN = 24.0
AVE_W_LOCAL = 16.0
AVE_W = [AVE_W_MAIN, AVE_W_LOCAL, AVE_W_MAIN,
         AVE_W_MAIN, AVE_W_LOCAL, AVE_W_MAIN]

# Six cross streets, east-west, sidewalks 4 wide.
#
# Two studs narrower than the avenues, and deliberately: the avenues are the
# arterials a driver crosses the city on, and a cross street reading as slightly
# the lesser road is how a grid tells you which way is through-traffic without a
# single sign. Their z positions are unchanged, so this comes out of the block
# depth -- 120 studs to 112, against a house row that needs at most 102.
#
# They begin at the connector's east kerb, not a stud clear of it. The whole
# road out of town used to run the full length of the map with a one-stud strip
# of lawn between its east pavement (ending at 48) and the west end of every
# cross street (beginning at 49), so the only route from the town to the city
# touched the city's street network nowhere at all. Six T-junctions now.
CS = [200.0, 350.0, 500.0, 650.0, 800.0, 950.0]
CS_WALK = 4.0
CS_X0, CS_X1 = CONN_X1, 793.0
# The last cross street, whose north pavement is the civic precinct's frontage
# rather than a row of street corners -- nothing crosses it from the north.
CS_LAST = 5

# **The cross streets are the axis the wealth gradient actually runs on, and
# doing only the avenues would have been a 23-site refactor with nothing to show
# for it.** The plan for this task said "AVE_W becomes a per-avenue list" and
# stopped there. But `house_tier` decides what kind of house a block gets from
# its Chebyshev distance to the Circle, the Circle is at (avenue 3, cross street
# 2) near the *south* of the grid, and the residential blocks are all north --
# so every HOUSE block in sband 4 comes out at 3.5 rings and every one in sband 3
# at 2.5, whatever their avenue band is. The houses get smaller as you walk
# north and they do not care which avenue you are on. Wealth here is a
# north-south gradient, and the avenues run north-south, so an avenue cannot
# express it.
#
# Which streets narrow follows the same "what does this road do" rule as the
# avenues, read against the block plan in ROLES:
#
#   * cross street 6 is the civic precinct's frontage and cross street 2 is the
#     Circle's spine. Both stay.
#   * cross streets 1 and 3 bound the financial fade, the mall, the offices and
#     the apartments -- the dense southern half. Both stay.
#   * cross streets 4 and 5 bound sband 3 and sband 4, which between them are the
#     park and nine of the city's ten house blocks, at the two outermost house
#     tiers. Nothing but homes fronts these two streets. They come down.
#
# So the narrow streets land exactly where the small houses already are, and the
# two gradients say the same thing instead of contradicting each other: walking
# north out of downtown the houses shrink *and* the road pinches.
#
# 14 against 22 for the same reason 16 is set against 24 above -- a third off, so
# it reads. Safe range 12 .. 18: below 12 the centre line has no lane either side
# of it to be the centre of, above 18 it stops reading as a lesser street.
CS_W_MAIN = 22.0
CS_W_LOCAL = 14.0
CS_W = [CS_W_MAIN, CS_W_MAIN, CS_W_MAIN,
        CS_W_LOCAL, CS_W_LOCAL, CS_W_MAIN]

# The works' south streets and the precinct's service road are not part of this:
# a freight street is not a poor neighbourhood's street, it is a road articulated
# lorries turn on. They keep the standard width, and they keep it under their own
# name so that narrowing a *residential* street can never quietly narrow the one
# the timber mill loads from.
WCS_W = CS_W_MAIN

# How far north the avenues run: the far kerb of the last cross street, where
# they all stop. This was the literal 972.0, which is CS[5] + 22 and was correct
# only for as long as every cross street was 22 wide -- exactly the defect class
# this file keeps being repaired for. Derived now, so narrowing a cross street
# cannot leave the avenues hanging 8 studs past their own junction.
AVE_Z1 = CS[CS_LAST] + CS_W[CS_LAST]

# ---------------------------------------------------------------------------
# The precinct loop
# ---------------------------------------------------------------------------
#
# The civic precinct (z 968..1116) had no road in it anywhere. Thirteen civic
# buildings and eight shops, and the only way anything on wheels reached any of
# them was the last cross street at the very bottom of it -- so the whole north
# strip, which is to say every building behind the town hall, had no vehicle
# access at all. A fire station with no road to it is not a hard thing to spot
# once somebody looks; the reason nothing did is that check_city's check 8 asks
# whether the street network is *one piece*, not whether it reaches anything.
#
# Two roads fix it and they make a loop rather than two spurs, which matters:
# the owner's other standing complaint is dead ends, and a service road that
# stops at the east end of the precinct would be the longest one in the city.
#
#   * avenue 5 continued north, x 769..793, from the cross street at z 972 up to
#     the service road. It is the same 24-stud carriageway on the same centre as
#     the avenue below it, so it reads as the avenue carrying on rather than as
#     a new road that happens to line up.
#   * a service road along the top, z 1124..1148, from the connector's east kerb
#     across to avenue 5, T-ing into both.
#
# The connector already ran to z 1120 and now runs to 1148 so the service road
# has something to T into at the west end. Nothing is built north of 1120, so
# the extension crosses nothing.
#
# Everything in the precinct that used to run to x 793 now stops at 763 to leave
# the new avenue its pavement: the precinct paving, the cross street's north
# pavement, the civic row and the north strip. Those are four separate numbers
# that all have to agree, so they are all derived from PRECINCT_AVE_X0.
PRECINCT_AVE_X0 = AVE[5]
PRECINCT_AVE_X1 = AVE[5] + AVE_W[5]
# Where everything else in the precinct has to stop: the new avenue's west
# pavement starts here.
PRECINCT_INNER_X1 = PRECINCT_AVE_X0 - AVE_WALK
# The service road along the top of the precinct. Its south pavement lands at
# 1120, which clears the government quarter's back wall at 1116 by four studs --
# the quarter is not moved and its buildings are not resized.
NORTH_ROAD_Z0 = 1124.0
NORTH_ROAD_Z1 = NORTH_ROAD_Z0 + WCS_W
# Road plus both pavements, in the form `carve` wants. The same thing CS_FULL is
# for the numbered cross streets: anything running north-south past this road
# has to yield the corner squares to it.
NORTH_SVC_FULL = [(NORTH_ROAD_Z0 - CS_WALK, NORTH_ROAD_Z1 + CS_WALK)]

# ---------------------------------------------------------------------------
# The works
# ---------------------------------------------------------------------------
#
# The industrial district, south of the city, and the first half of filling in
# the empty side of the baseplate.
#
# Everything south of z=60 was bare grey baseplate: a thousand studs by four
# hundred of nothing, with the town's back fence on one side of it and the
# financial district's towers on the other. It is also the piece of map the game
# most needs, because every job in this world is currently done in a shop --
# there is nowhere to build a thing, take a thing apart, load a thing onto a
# boat or run a machine, and those are the jobs a life sim needs before it has a
# fifth cashier.
#
# **It is laid on the city's own grid rather than a grid of its own.** Three of
# the six avenues carry south -- 1, 4 and 6 -- and two east-west works streets
# cross them. That is deliberate and it is the lesson of the civic precinct,
# which was laid out in its own coordinates and had six avenues driven through
# it before anybody noticed. A district that borrows the grid cannot be built in
# the wrong place, and a player who drives south off cross street 1 arrives here
# without ever crossing a seam.
#
# Two streets and three avenues also make a loop rather than a comb: every
# junction here has three or four arms and the only dead ends in the district
# are the two avenue stubs at the wharf, which end at water and are supposed to.
#
# The three avenues are 1, 4 and 6 because those are the ones with somewhere to
# go: avenue 1 runs into the connector's own approach, avenue 4 lands in the
# middle of the district, and avenue 6 carries the traffic onto the wharf.
WORKS_AVE = (0, 3, 5)

# Everything south of the city is cut into rows by east-west streets, exactly as
# CS cuts the city -- and here the streets are derived from the rows rather than
# typed. North to south:
#
#   136   the step-down: mid-rise offices, the ramp off the financial district
#   154   the heavy row: ironworks, canteen, power station. The deep one,
#         because a shed with a yard behind it needs the depth and a chimney
#         needs the setback
#   110   the yard row: timber, scrap, the container depot
#
# **The step-down row is the reason this list exists.** The financial district
# stands 195 studs tall and used to stop dead at z=60 with the works' 26-stud
# sheds on the far side of the line -- a cliff, and the only direction out of
# downtown that had no ramp. The north side has had one since the block plan was
# written (195 -> 115 -> 67 -> 34 -> 17, and the whole reason the fade district
# exists); this is that ramp mirrored south, 195 -> 115 -> 67 -> 36. It also
# gives the towers a pavement to open onto, which they never had: their lobby
# doors fronted south onto bare ground.
#
# Change a depth here and every road, junction, centre line, block edge, yard
# and waypoint south of it moves with it. That is the point -- the works was
# built hard against z=60 and inserting a row in front of it had to be one
# number, not forty.
SOUTH_ROW_DEPTH = [136.0, 154.0, 110.0]

# What a cross street costs the map, kerb to kerb with both pavements.
CS_PITCH = WCS_W + 2 * CS_WALK


def _south_streets():
    """The z of each south street's south kerb, south to north.

    The northernmost is placed so its *north* pavement finishes exactly on the
    city's south edge, which is the financial district's front wall."""
    zs = [CITY_Z0 - WCS_W - CS_WALK]
    for depth in SOUTH_ROW_DEPTH:
        zs.append(zs[-1] - CS_PITCH - depth)
    zs.reverse()
    return zs


SOUTH_CS = _south_streets()
# The works' own extent. Its north edge is no longer the city's south edge --
# the step-down band sits between them now -- so it is the street between the
# heavy row and the step-down, which is also where the quay hands over to the
# beach. The south edge is the last street plus an apron wide enough for a
# boundary treeline, which is what says "the map ends here" without a wall.
WORKS_APRON = 44.0
WORKS_Z0 = SOUTH_CS[0] - WORKS_APRON
WORKS_Z1 = SOUTH_CS[2]
# East and west ends of the south streets: they tee into avenue 1 at one end and
# avenue 6 at the other, so they are bounded by those avenues' carriageways.
WORKS_X0 = AVE[0]
WORKS_X1 = AVE[5] + AVE_W[5]

# The blocks the grid leaves, west-to-east and south-to-north, measured off the
# roads rather than typed: this is the fourth time in this file a district has
# been written in literal coordinates and had to be repaired when a road moved,
# and the works is not going to be the fifth.
WORKS_COL_X = [(AVE[0] + AVE_W[0] + AVE_WALK, AVE[3] - AVE_WALK),
               (AVE[3] + AVE_W[3] + AVE_WALK, AVE[5] - AVE_WALK)]
SOUTH_ROW_Z = [(lo + WCS_W + CS_WALK, hi - CS_WALK)
               for lo, hi in zip(SOUTH_CS, SOUTH_CS[1:])]
WORKS_ROW_Z = SOUTH_ROW_Z[:2]   # the two industrial rows
STEP_ROW_Z = SOUTH_ROW_Z[2]     # the step-down band


def ave_z0(k):
    """How far south avenue `k` runs.

    All six carry into the step-down band below the city -- it is city rather
    than works, and is laid out in the financial district's bands because of it,
    so the offices in it line up with the towers above them. Three of them --
    1, 4 and 6 -- carry on past it into the works and stop at its south street.

    Everything that draws an avenue (the carriageway, the pavements, the centre
    line, the waypoint chain and surface_floor) and everything that asks which
    avenues cross a street has to agree about this, so it is one function and
    not seven copies of the same conditional."""
    return SOUTH_CS[0] if k in WORKS_AVE else SOUTH_CS[2]


def cs_aves(c):
    """The avenues that cross south street `c`: an avenue crosses it if it runs
    at least that far south."""
    return [k for k in range(len(AVE)) if ave_z0(k) <= c]


# ---------------------------------------------------------------------------
# The arena superblock
# ---------------------------------------------------------------------------
#
# Two grid blocks taken as one piece of ground, and the local avenue between
# them stopped at each end instead of run through it.
#
# The arena is 184 studs across. A band between two avenues is 114, so it does
# not fit in a block, and there is nowhere else on the map to put it: the city
# is boxed in on all four sides -- the bay east, the connector and the estate
# west, the civic precinct above the grid, the works below it. Extending the map
# south was tried and abandoned; it moved MAP_SOUTH_EDGE, which the town's own
# south house row is laid against, and cost three hundred studs of bare new land
# to gain one building. The land had to come out of the grid instead.
#
# **Which two blocks, and what they cost.** Bands 4 and 5 of the southern row --
# ROLES[0][3] and ROLES[0][4] -- were both FADE, mid-rise offices on the ramp
# down off the financial district's 195-stud towers. Nothing load-bearing is
# lost: no house (the ten HOUSE blocks are the sixty addresses check_city
# counts), no apartment, no CIRCUS quadrant, no block any waypoint is hard-coded
# into. And the site fronts cross street 1 with the financial district directly
# across it, so the arena stands at the top of downtown rather than out in the
# suburbs. It is still a ramp: the drum tops out around eighty studs, between
# the towers behind it and the fade band beside it.
#
# **Why the avenue and not a cross street.** Avenue 5 is the sixteen-stud local
# (see AVE_W) and it is the only road inside the site. The cross street here is
# cross street 2, which is the Circle's spine -- cutting it would leave the ring
# a 46-stud stub for an east arm, teeing into avenue 4 barely clear of the
# promenade. The avenue is *interrupted*, not shortened: it still runs south of
# cross street 1 through the financial district and north of cross street 2
# through the rest of the grid, so both ends of the gap are ordinary
# T-junctions whose intersection tiles are already drawn.
ARENA_BAND = 3            # west band of the pair; the east band is ARENA_BAND + 1
ARENA_SBAND = 0
ARENA_AVE = ARENA_BAND + 1        # the avenue the superblock swallows: avenue 5


def ave_gaps(k):
    """The z bands avenue `k` is not drawn over.

    Kerb to kerb of the two cross streets that bound the superblock, so the
    avenue stops on a junction at each end rather than in the middle of a block.
    Read by the carve lists that draw the carriageway, the pavements and the
    centre line, and by `on_avenue` for everything that instead asks whether a
    point is standing on the road -- surface_floor and the waypoint chain."""
    if k != ARENA_AVE:
        return []
    return [(CS[ARENA_SBAND] + CS_W[ARENA_SBAND], CS[ARENA_SBAND + 1])]


def on_avenue(k, z):
    """Whether avenue `k` is really drawn at this z. `ave_z0(k)..AVE_Z1` less
    whatever `ave_gaps` takes out of the middle."""
    if not (ave_z0(k) < z < AVE_Z1):
        return False
    return not any(g0 <= z <= g1 for g0, g1 in ave_gaps(k))


# Gaps used to carve roads and sidewalks out of each other at crossings. A road
# is carved at the roads it crosses; a north-south sidewalk yields its corner to
# the east-west sidewalk, so one and only one box owns every square.
CS_ROAD = [(c, c + CS_W[j]) for j, c in enumerate(CS)]
CS_FULL = [(c - CS_WALK, c + CS_W[j] + CS_WALK) for j, c in enumerate(CS)]
AVE_ROAD = [(a, a + AVE_W[k]) for k, a in enumerate(AVE)]
AVE_FULL = [(a - AVE_WALK, a + AVE_W[k] + AVE_WALK) for k, a in enumerate(AVE)]
# The same lists for the south streets. The avenue carve is one list *per
# street* and not one list for all of them: the two northern streets are crossed
# by all six avenues and the two southern ones only by the three that carry on
# into the works, and a street carved at an avenue that is not there leaves a
# twenty-four-stud hole in it.
WCS_ROAD = [(c, c + WCS_W) for c in SOUTH_CS]
WCS_FULL = [(c - CS_WALK, c + WCS_W + CS_WALK) for c in SOUTH_CS]
SOUTH_AVE_ROAD = [[(AVE[k], AVE[k] + AVE_W[k]) for k in cs_aves(c)] for c in SOUTH_CS]

# ---------------------------------------------------------------------------
# The west estate
# ---------------------------------------------------------------------------
#
# MAP_PLAN section E, option (c): industrial and low-rise sprawl go west, docks
# stay east on the bay. This is the northern half of that decision -- light
# industrial and trade yards on the land between the town's north edge and the
# top of the map.
#
# **Why here, measured rather than chosen.** The connector's west footway has run
# from z 339 to z 1148 as one unbroken 809-stud slab ever since the northern link
# went in. Its east twin is seven separate runs, broken by the six cross streets
# and the service road, because on that side there is something to cross *to*. A
# footway with a carriageway on one flank and nine hundred studs of untouched
# baseplate on the other is not a pavement, it is the place the map was going to
# be finished. The estate is what it fronts, and the estate's four streets are
# what finally break the slab -- which is the same repair, in the same shape, as
# `RoadReturn` in the town and the cross streets on the connector's east side.
#
# **Why light industry and not more docks.** The heavy end of this world is the
# works, and the works is on the bay because that is where the wharf is; moving
# freight inland to a district with no water is a port that cannot be one. What
# goes here is what a town's residents actually work in and steal from --
# builders' merchants, haulage, self-storage, a scrapyard, a vehicle workshop --
# on the side of the map their houses are on. The town's north road already tees
# into the connector 27 studs south of the estate's south edge, so the walk from
# a front door to a yard gate is a walk, not a bus ride.
#
# The band. East edge is the connector's west footway, so the estate's frontage
# *is* that pavement rather than a second one laid beside it. South edge is the
# northern link's cleared band, the same number gen_town.py ends its lawns on.
# North edge is the city's, so the map has one north edge and not two.
EST_X0 = -MAP_EDGE
EST_X1 = CONN_X0 - CONN_WALK
EST_Z0 = NORTHGATE_CLEAR[1]
EST_Z1 = CITY_Z1

# The estate's streets and rows, on the works' own grid dimensions (WCS_W,
# CS_WALK, CS_PITCH) rather than a set of its own. Two industrial districts
# built to two different road standards is two vocabularies for one idea, and
# the player crossing between them would be told nothing by the difference.
#
# Three depths for four rows: the last row is whatever the band has left. Typing
# it as a fourth entry would be a fourth number that has to be right to the stud
# or the estate either overhangs the map's north edge or stops short of it with
# a strip of grass nothing is built on -- and nothing in this tree would say
# which. `_south_streets` learned the same lesson from the other end.
EST_ROW_DEPTH = [150.0, 185.0, 175.0]


def _est_streets():
    """The z of each estate street's south kerb, south to north.

    The first is one pavement's width north of the band's edge, so the street's
    *south* footway finishes exactly on the line gen_town.py's lawns end at."""
    zs = [EST_Z0 + CS_WALK]
    for depth in EST_ROW_DEPTH:
        zs.append(zs[-1] + CS_PITCH + depth)
    return zs


EST_CS = _est_streets()
EST_ROW_Z = [(c + WCS_W + CS_WALK, nxt - CS_WALK)
             for c, nxt in zip(EST_CS, EST_CS[1:])]
EST_ROW_Z.append((EST_CS[-1] + WCS_W + CS_WALK, EST_Z1 - WORKS_APRON))
# The top of the map gets what the bottom of it gets: an apron wide enough for a
# boundary treeline, and the same one, because two map edges treated two ways is
# the player being told the world ends for two different reasons.
EST_NORTH_APRON = (EST_ROW_Z[-1][1], EST_Z1)

# The top row's depth is not checked here. What it has to be deep enough for is
# a shed, its aprons and a container behind it, and SHED_APRON, BOX_L and
# BOX_MARGIN are declared three thousand lines down with the helpers that use
# them. The bound is asserted there, against those, rather than being a fifth
# opinion here about how deep a yard is. See EST_TOP_ROW.

# The two built columns, east to west, and the common beyond them.
#
# 230 is a frontage row plus its forecourt; 330 is a yard deep enough for a
# transit shed with a lorry able to turn in front of it. Both are within the
# works' own range (its two columns are 378 and 240), which is the only reason
# they are not derived from something: the works measured them the hard way and
# they are the same buildings.
EST_COL_W = [230.0, 330.0]


def _est_avenues():
    """The x of each estate avenue's west kerb, east to west.

    Walking west from the frontage line and subtracting a column and a road each
    time, so a change to EST_COL_W moves the roads instead of stranding them."""
    xs = []
    east = EST_X1
    for w in EST_COL_W:
        xs.append(east - w - AVE_WALK - AVE_W_MAIN)
        east = xs[-1] - AVE_WALK
    return xs


EST_AVE = _est_avenues()
EST_COL_X = [(a + AVE_W_MAIN + AVE_WALK, e) for a, e in
             zip(EST_AVE, [EST_X1] + [x - AVE_WALK for x in EST_AVE])]

# **The rest of the band is not estate and is not empty either.** West of the
# last avenue there are four hundred studs to the map edge, and an industrial
# estate that sprawls the whole way is a bigger estate than this world has jobs
# for. It is common: rough grazing, hedgerows, a farm track and the boundary
# treeline `works_boundary` puts on the south of the works, for the reason that
# function's docstring gives -- an edge a player can see the far side of is an
# edge they walk to. It also gives the crime stack somewhere that is neither
# street nor building, which the map has nowhere else at all.
EST_COMMON_X0, EST_COMMON_X1 = EST_X0, EST_AVE[-1] - AVE_WALK

# Carve lists, the same four the city grid keeps and for the same reasons: a
# road is carved at the roads it crosses, a pavement at the full corridor of the
# road it meets, and the junction square is filled once, explicitly.
EST_CS_ROAD = [(c, c + WCS_W) for c in EST_CS]
EST_CS_FULL = [(c - CS_WALK, c + WCS_W + CS_WALK) for c in EST_CS]
EST_AVE_ROAD = [(a, a + AVE_W_MAIN) for a in EST_AVE]
EST_AVE_FULL = [(a - AVE_WALK, a + AVE_W_MAIN + AVE_WALK) for a in EST_AVE]
# The estate's streets run from the westmost avenue's west kerb to the
# connector's west kerb, so both ends of every one of them is a T.
EST_CS_X0, EST_CS_X1 = EST_AVE[-1], CONN_X0
# ...and the avenues run from the first street to the last, so both of their
# ends are T-junctions too. They do *not* carry on into the north apron: that is
# the boundary treeline, and the works' avenues stop at its south street for the
# same reason. Nor do they carry south past the estate's first street into the
# empty band below -- a carriageway that ends in a field is what the town's back
# street was before `RoadReturn` was carried the whole way, and the fix for it is
# not to build another one.
EST_AVE_Z0, EST_AVE_Z1 = EST_CS[0], EST_CS[-1] + WCS_W

# The common has to read as country and not as a verge, and the estate has to
# read as the thing the country stops at. Both bounds are measured off the
# estate's own columns rather than picked: narrower than the widest yard column
# and it is a margin, wider than the two built columns together and the estate
# is a strip on the edge of a field that should have had a third column in it.
EST_COMMON_W = EST_COMMON_X1 - EST_COMMON_X0
assert max(EST_COL_W) <= EST_COMMON_W <= sum(EST_COL_W) + AVE_WALK * 2 + AVE_W_MAIN, (
    f"the common west of the estate is {EST_COMMON_W:.0f} studs wide, against "
    f"built columns of {', '.join(f'{w:.0f}' for w in EST_COL_W)}. Under "
    f"{max(EST_COL_W):.0f} it is a verge with trees on it rather than open "
    f"country; over "
    f"{sum(EST_COL_W) + AVE_WALK * 2 + AVE_W_MAIN:.0f} there is room for another "
    f"avenue and another column and the estate should have one. Check EST_COL_W "
    f"and EST_X1 -- the band itself is fixed at both ends.")

# No estate street may land in a band the connector's west footway has already
# yielded to somebody else. It cannot happen today -- EST_Z0 *is* the northern
# link's cleared edge -- but it is one edit away the moment a row depth or EST_Z0
# moves, and what it produces is not a visible break: `carve` would hand back
# two overlapping gaps, the footway would lose a stretch it should have kept,
# and the symptom is a missing pavement nobody thinks to look for.
for _band in EST_CS_FULL:
    for _taken, _what in ((GATE_CLEAR, "the gate road"),
                          (NORTHGATE_CLEAR, "the northern link")):
        assert _band[1] <= _taken[0] or _band[0] >= _taken[1], (
            f"an estate street's corridor runs z {_band[0]:.0f}..{_band[1]:.0f}, "
            f"which overlaps {_what} at z {_taken[0]:.0f}..{_taken[1]:.0f}. Both "
            f"carve the connector's west footway, and two overlapping gaps in one "
            f"carve list take out more pavement than either asked for. Move EST_Z0 "
            f"or the first entry of EST_ROW_DEPTH.")

# ---------------------------------------------------------------------------
# Two more ways out of town
# ---------------------------------------------------------------------------
#
# Until now there was one, the gate road, and it is a 14-stud lane. The walk
# from the spawn house's back garden to avenue 1 -- forty studs due east of it --
# was out the front gate, north, east along the gate road, a hundred and forty
# studs north up the connector to cross street 1, east, and two hundred studs
# back south: about six hundred studs to cross forty. Nothing caught it. Check 8
# walks the road surface *inside* the city and check 11 measures models to
# carriageways; neither asks how many ways there are between the two places.
#
# Both of the roads below land on mouths that already exist. Every south street
# has a gap cut in avenue 1's west pavement where it meets it, and three of those
# gaps -- W1, W2, W3 -- open onto nothing, because the works streets they were
# cut for all run *east*. Using them means no new junction on the avenue, no new
# entry in any carve list, and a junction tile that is already drawn.

# The southern link: works cross street 1, carried west from avenue 1, across the
# seam, to the town road's east kerb at the bottom of the loop. The town's own
# road turns west there (CURL_Z), so this makes that corner a crossroads and puts
# the ironworks, the sawmill and the timber yard on a straight road from the
# town's south end -- which is where the works place points, and the jobs, are.
#
# SOUTHGATE_* live in world_plan.py because gen_town.py has to keep the east
# frontage clear of them and cannot import this file. They are asserted rather
# than derived there for the same reason: world_plan is imported *by* this file,
# so it cannot see SOUTH_CS.
assert (SOUTHGATE_Z0, SOUTHGATE_Z1) == (SOUTH_CS[1], SOUTH_CS[1] + WCS_W), (
    f"SOUTHGATE_Z0/Z1 in world_plan.py say {SOUTHGATE_Z0}..{SOUTHGATE_Z1}, but "
    f"works cross street 1 is at {SOUTH_CS[1]}..{SOUTH_CS[1] + WCS_W}. The "
    f"southern link is that street carried west, so it has to be that band or it "
    f"lands beside the junction instead of on it. Update world_plan.py.")
assert SOUTHGATE_WALK == CS_WALK, (
    f"SOUTHGATE_WALK is {SOUTHGATE_WALK} against a cross street's {CS_WALK}. The "
    f"link's pavements have to meet W1's at the avenue or there is a step in the "
    f"kerb. Update world_plan.py.")

# Where the world stops in the south, asserted here for the third time and the
# same reason: the works apron's south face is the southernmost thing in the
# world, gen_town.py has to end its own ground level with it, and gen_town
# cannot import this file to ask.
assert MAP_SOUTH_EDGE == WORKS_Z0, (
    f"MAP_SOUTH_EDGE in world_plan.py says {MAP_SOUTH_EDGE}, but the works apron "
    f"now ends at {WORKS_Z0}. The town's south edge is laid against that number, "
    f"so leaving them apart puts a {abs(WORKS_Z0 - MAP_SOUTH_EDGE):.0f}-stud step "
    f"in the bottom of the map. Update world_plan.py.")

# The Green: the corridor between the player's plot and avenue 1, left as
# parkland.
#
# **This was a street, and building it was a mistake.** It was drawn as the
# Backs -- a full carriageway with two pavements and an elbow onto avenue 1 at
# each end. It generated clean, it passed all twelve checks, and it was still
# wrong, because avenue 1 runs the whole height of the map thirty-five studs
# east of here on the same axis. A second carriageway that close and that
# parallel is not a route, it is the same route again. Its only distinguishing
# feature was being nearer the player's fence.
#
# The lesson is narrower than "don't build redundant roads". Every check in
# check_city measures a road against *itself* -- is it connected, is it carved,
# does it reach the buildings. Nothing measures a road against the road next to
# it, and nothing ever will, because "these two are the same street twice" is a
# judgement about a map and not a property of geometry. The green checks
# exactly as well as the street did. Passing is not the same as being right.
#
# What the corridor is for is the thing the plot's back fence looks at. So:
# grass the full 40.5 studs, a tree belt down the avenue side, and one footpath
# from the back gate straight east to avenue 1's pavement. That path is a
# *shorter* walk into the city than the street it replaces, because a path can
# go straight where the road had to bend twice to find a junction.
GREEN_X0 = HOUSE_EAST_X
GREEN_X1 = AVE[0] - AVE_WALK
# The same two ends the street had: the W2 mouth south, the W3 mouth north.
# Those are gaps cut in avenue 1's west pavement by the south-street plan
# whether or not anything lands in them -- they opened onto bare grass before
# the Backs existed and they open onto the green now, which is the first time
# they have looked deliberate.
# Counted from the end and not the start. These are "the last two south streets"
# -- the pair that brackets the row nearest the city -- and saying so from the
# north end means inserting a row further south leaves them alone. Written as
# [2] and [3] they were a fixed distance from the *bottom* of the map, and the
# green followed the works south the first time a row was added in front of it.
GREEN_Z0 = SOUTH_CS[-2]
GREEN_Z1 = SOUTH_CS[-1] + WCS_W
# The footpath leaves by the back gate, so its line is the gate's line. Same
# half-width as the front path: one house, two paths, one width.
GREEN_PATH_Z = BACK_GATE_MID
GREEN_PATH_HALF = PATH_HALF

# The main street: storefronts on the strip between the connector's east
# sidewalk and the first avenue's west sidewalk, fronting the connector. Carved
# at the cross streets so each crossing stays a clear east-west passage.
MAIN_X0, MAIN_X1 = 48.0, 72.0

# ---------------------------------------------------------------------------
# The Circle
# ---------------------------------------------------------------------------

# Downtown's roundabout, and the one place in the city that is not on the grid.
#
# A grid is legible and a grid is monotonous, and this city had nothing but grid:
# six straight avenues, six straight cross streets, and a player who could see
# the whole plan from the first junction. The Circle is the answer to that. It
# takes one intersection and turns it into a place -- an island with a lit
# monument on it, a ring boulevard round the island, and twelve towers standing
# on an arc facing in, so downtown finally has a centre you can point at.
#
# **It sits on a junction rather than beside one.** The centre is the middle of
# avenue 3 crossed with the middle of cross street 2, so those two roads are not
# diverted round it -- they run into it and become four of its spokes. That is
# also why nothing else had to move: the four blocks that touch this corner were
# all mid-rise fade offices, so no house is lost (check_city wants sixty and
# there are exactly sixty) and the skyline step the block plan is built on is
# kept.
#
# Read from the middle out:
#
#     0 .. 38   the island: plaza, fountain, monument, lawn, kerb
#    38 .. 62   the ring carriageway
#    62 .. 70   the ring pavement, opened at the four spokes
#    72 ..102   the tower arc, three per quadrant, all facing the monument
CIRCLE_AVE = 2   # index into AVE  -- avenue 3
CIRCLE_CS = 1    # index into CS   -- cross street 2
CIRCLE_X = AVE[CIRCLE_AVE] + AVE_W[CIRCLE_AVE] / 2
CIRCLE_Z = CS[CIRCLE_CS] + CS_W[CIRCLE_CS] / 2

CIRCLE_ISLAND = 38.0
CIRCLE_ROAD_W = 34.0    # two lanes each way, matching the arterials at 24 plus a
                        # ring's worth of weaving room. Must stay above the width
                        # of every road that feeds it -- a roundabout narrower
                        # than its own spokes reads as a pinch and drives like
                        # one, and the assertion below holds it to that.
                        # Safe range: 28 .. 40.
CIRCLE_WALK_W = 8.0     # wider than an avenue's 6: this pavement is a promenade
                        # and it is where the tower entrances are read from.
CIRCLE_R_ROAD = CIRCLE_ISLAND + CIRCLE_ROAD_W
CIRCLE_R_WALK = CIRCLE_R_ROAD + CIRCLE_WALK_W

# ---------------------------------------------------------------------------
# What the street widths are not allowed to do
# ---------------------------------------------------------------------------
#
# AVE_W and CS_W are the two lists a person will reach for when they want a
# district to feel different, and four of their twelve entries are load bearing
# for something a long way from where they are typed. None of the four can be
# derived -- they are the *inputs* the rest of the grid is measured from -- so
# they are asserted instead, here, where WORKS_AVE and CIRCLE_AVE both exist.
#
# Every one of these was negative-tested by making the change it forbids. The
# point is not that the defect goes uncaught otherwise -- check_city catches the
# Circle one -- it is *what it is caught as*: narrowing cross street 2 by eight
# studs takes the Circle off its own junction and check 10 reports it as 1004
# coplanar pairs, which names no street, no number and no file. An assertion here
# fails in the generator, on the line that is wrong, before an asset is written.
assert AVE[5] + AVE_W[5] == CS_X1, (
    f"avenue 6 runs x {AVE[5]}..{AVE[5] + AVE_W[5]} and the bay's west shore is "
    f"at {CS_X1}. Its far kerb *is* that shore: the beach, the baywalk, the piers "
    f"and the sports park all start there. To change AVE_W[5] you must move AVE[5] "
    f"to {CS_X1 - AVE_W[5]} in the same edit, and the block west of it loses or "
    f"gains that width -- check the interior assertion below before you do.")
assert all(AVE_W[k] == AVE_W_MAIN for k in WORKS_AVE), (
    f"avenue {[k + 1 for k in WORKS_AVE if AVE_W[k] != AVE_W_MAIN]} is in "
    f"WORKS_AVE but is not at the arterial width. Those three are the only routes "
    f"from the city into the works and they carry its freight. If one of them "
    f"should really be a local street, take it out of WORKS_AVE first and re-read "
    f"ave_z0(), which decides how far south it is drawn.")
# The Circle is not diverted round its junction, it *is* the junction: avenue 3
# and cross street 2 run into it and become its four spokes, and CIRCLE_X/
# CIRCLE_Z are the middles of those two carriageways. Change either width and
# the ring slides off the corner the four CIRCUS blocks are cut to, because the
# blocks are measured from CS/AVE and the ring is measured from the road centres.
assert AVE_W[CIRCLE_AVE] == AVE_W_MAIN and CS_W[CIRCLE_CS] == CS_W_MAIN, (
    f"avenue {CIRCLE_AVE + 1} is {AVE_W[CIRCLE_AVE]} wide and cross street "
    f"{CIRCLE_CS + 1} is {CS_W[CIRCLE_CS]}. They are the Circle's four spokes and "
    f"they have to stay at the arterial widths ({AVE_W_MAIN} and {CS_W_MAIN}) -- "
    f"the ring is centred on where they cross, and moving that centre leaves the "
    f"monument, the twelve towers and the four CIRCUS blocks in three different "
    f"places. Narrow a street that is not a spoke.")
assert max(AVE_W[CIRCLE_AVE], CS_W[CIRCLE_CS]) < CIRCLE_ROAD_W, (
    f"the Circle's ring is {CIRCLE_ROAD_W} wide against spokes of "
    f"{AVE_W[CIRCLE_AVE]} and {CS_W[CIRCLE_CS]}. A roundabout no wider than the "
    f"roads feeding it reads as a pinch and drives like one -- widen "
    f"CIRCLE_ROAD_W to match.")

# The blocks pay for the roads out of their own interiors, so the widths are only
# legal while what is left still holds two facing rows of houses. HOUSE_STYLES
# tops out at a 42-stud width plus setback (see the note on HOUSE_TIERS), twice,
# plus the 18-stud lane between the back gardens.
BLOCK_MIN_INTERIOR = 2 * 42.0 + 18.0
for _b in range(len(AVE) - 1):
    _interior = (AVE[_b + 1] - AVE_WALK) - (AVE[_b] + AVE_W[_b] + AVE_WALK)
    assert _interior >= BLOCK_MIN_INTERIOR, (
        f"avenue band {_b} has {_interior:.0f} studs of interior against the "
        f"{BLOCK_MIN_INTERIOR:.0f} two facing house rows need. Narrow AVE_W[{_b}] "
        f"or move the avenues apart.")

# How many boxes make the circle. Twenty-four is a multiple of four, so a segment
# is centred on each of the four spokes rather than straddling it, and the facets
# are 15 degrees -- small enough that the kerb reads as a curve from the ground
# and large enough that the ring is a hundred parts and not a thousand.
# Safe range: 16 .. 32, and it must stay a multiple of 4.
CIRCLE_SEGS = 24
CIRCLE_STEP = 360.0 / CIRCLE_SEGS
CIRCLE_SPOKE_EVERY = CIRCLE_SEGS // 4

# A ring paved with rectangles cannot tile an annulus exactly: each facet is cut
# to cover its full sector at the *outer* radius, so neighbours lap each other by
# a couple of studs at the inner edge. Overlapping volume is harmless and normal
# here; two overlapping tops in the same plane is not, because neither can win
# the pixel and the road flickers. Alternate facets therefore finish one step
# lower. That is a step no player can feel and a difference the depth buffer can
# decide on.
CIRCLE_SEAM = GROUND_STEP
# ...and the whole ring sits a step under GROUND for the same reason at the four
# mouths, where the spoke roads run over it. The spoke wins, which is right: a
# junction should look like the straight road continuing into the circle.
CIRCLE_SINK = GROUND_STEP

# Both sinks are subtracted from the same gap -- the one between the road plane
# and the grass under it -- so the ring's low facets are the deepest paved thing
# in the city and the only place that gap can run out. It did: at CIRCLE_SINK
# 0.005 and CIRCLE_SEAM 0.01 over a lawn a bare 0.02 down, sixteen facets
# finished five thousandths above the grass and the whole ring flickered. The
# lawn was lowered to make room rather than the sinks shaved, because the sinks
# are each doing a visible job and the depth of the grass under a road is not.
assert GROUND - CIRCLE_SINK - CIRCLE_SEAM >= CITY_GRASS_TOP + GROUND_STEP, (
    f"the Circle's low facets top at {GROUND - CIRCLE_SINK - CIRCLE_SEAM:.3f}, "
    f"which is not a clear {GROUND_STEP} over the lawn at {CITY_GRASS_TOP:.3f}. "
    f"Raise CITY_GRASS_SINK or lower CIRCLE_SINK/CIRCLE_SEAM.")

# What the spokes are carved back to. The roads stop at the carriageway's outer
# radius and the pavements at the ring pavement's, so each spoke tees into the
# ring the same way the cross streets tee into the connector. The carve list form
# is what `carve` wants and the ranges deliberately swallow the CS_ROAD/AVE_ROAD
# gap they contain -- `carve` sorts its gaps and advances past the furthest one,
# so an overlapping pair is one hole, not two.
CIRCLE_Z_ROAD = [(CIRCLE_Z - CIRCLE_R_ROAD, CIRCLE_Z + CIRCLE_R_ROAD)]
CIRCLE_Z_WALK = [(CIRCLE_Z - CIRCLE_R_WALK, CIRCLE_Z + CIRCLE_R_WALK)]
CIRCLE_X_ROAD = [(CIRCLE_X - CIRCLE_R_ROAD, CIRCLE_X + CIRCLE_R_ROAD)]
CIRCLE_X_WALK = [(CIRCLE_X - CIRCLE_R_WALK, CIRCLE_X + CIRCLE_R_WALK)]

# ---------------------------------------------------------------------------
# The shoreline
# ---------------------------------------------------------------------------

# The grid stops at x 793 and the map at x 1024, which left a fifth of the city
# -- 230 studs by a thousand -- as blank lawn with a running track dropped in
# the middle of it. That strip is now the bay, and the bay is doing three jobs
# at once:
#
#   * it ends the map with something rather than with nothing. The east edge was
#     a place where the grass simply stopped;
#   * it is the reason the city looks like this city and not any other. Pastel
#     stucco reads as somebody's colour scheme until there is water behind it;
#   * it puts the tallest thing in the game -- the financial district at z
#     60..200 -- on a waterfront, which is the only place a skyline is worth
#     having. Standing on the baywalk at the south end and looking back west is
#     the shot this whole file exists to produce.
#
# The shore is a step function rather than a straight line, and the step is not
# decoration: the sports park already stood at x 819..980, z 417..920, so the
# water goes around it. What that produces on the map is a headland with a bay
# to its south and another to its north, which is a better coastline than any
# straight edge would have been and cost nothing but honouring what was there.
# (The courts and the track have since gone to the school; what is left out
# there is the stadium, which is the reason the headland still has to be land.)
#
# The waterline in the two straight bands and at the headland. Named rather than
# repeated, because the marina and the works wharf are both built off "the shore
# in the southern bay" and both used to find it by indexing SHORE -- which is a
# reference that silently means a different band the moment a band is inserted,
# and one was.
SHORE_X_BAY = 845.0
SHORE_X_HEADLAND = 995.0

# How far the headland runs. It used to reach z 940, because it had to carry the
# stadium *and* the sports park; with the park gone to the school there was a
# 228-stud stretch of empty coastal grass north of the stadium that existed only
# because something used to be on it. It is water now, and what that buys is the
# thing the stadium was always worth having: the bowl stands on a peninsula with
# the bay on three sides of it, reachable across the neck at x < SHORE_X_BAY.
#
# The stadium is fitted to these two, not the other way round -- see the assert
# beside STAD_NORTH_OUT, which is what stops a later nudge to the bowl from
# quietly putting a stand in the sea.
HEADLAND_Z0, HEADLAND_Z1 = 400.0, 712.0
# What a piece of headland has to keep clear of the waterline at either end: the
# width of the crossing waypoints' band plus room to stand behind them.
HEADLAND_CLEAR = 8.0

# (z0, z1, x of the waterline, what the land does when it meets the water).
# Land runs from CITY_X0 to that x.
#
# The works band is the odd one and it is odd on purpose: an industrial district
# does not get a beach. `quay` is a vertical concrete face with the water right
# up against it and bollards along the top, which is what a working waterfront
# looks like, and it is the foundation the docks are built on when the coastline
# question is answered. The two edges meet at WORKS_Z1 -- the street between the
# heavy row and the step-down band, so the change of coast happens on the same
# line the change of district does -- and there is a step from the quay down
# onto the sand, which is what a real seafront does there too.
SHORE = [
    (WORKS_Z0, WORKS_Z1, SHORE_X_BAY, "quay"),
    (WORKS_Z1, HEADLAND_Z0, SHORE_X_BAY, "beach"),
    (HEADLAND_Z0, HEADLAND_Z1, SHORE_X_HEADLAND, "beach"),
    (HEADLAND_Z1, CITY_Z1, SHORE_X_BAY, "beach"),
]
# How far inland the sand runs, and how wide the paved walk behind it is.
#
# These two are not free numbers. In the southern and northern bands the shore
# is at x 845, so 20 + 26 puts the back of the walk at exactly 799 -- which is
# the east edge of avenue 6's sidewalk. The walk butts the avenue and a player
# steps off one onto the other with no kerb and no seam. Change either number
# and that join opens into a strip of lawn, or worse, overlaps the sidewalk and
# z-fights along a thousand studs.
BEACH_W = 20.0
BAYWALK_W = 26.0
# The seabed is a shelf, not a drop. Nothing in this game swims, so the bay is
# knee-deep everywhere and a player who walks into it wades: no drowning, no
# invisible wall, and no floor missing out from under somebody who stepped off
# the sand. What stops them at the far side is the revetment below.
SEA_FLOOR = GROUND - 2.6
SEA_TOP = GROUND - 0.35
# Rock armour along the map edge. A seawall you can see is a better boundary
# than a wall you cannot: it is what the edge of a causeway actually looks like,
# and it says "this is the end" without the game having to.
REVETMENT_W = 14.0
# The works wharf: paved apron between the quay face and the back of the
# waterfront. BEACH_W + BAYWALK_W by construction, so the back of the wharf
# lands at exactly 799 -- the same line the baywalk's back lands on -- and the
# two run into each other at z=60 without a stud of lawn or a stud of overlap.
# See the note on BEACH_W: this is that number's other half, and moving either
# one without the other opens the join.
WHARF_W = BEACH_W + BAYWALK_W
# The quay's coping: how far its face reaches back behind the shoreline and how
# far it stands out into the water. The apron stops at the inner edge rather than
# running under it, because both finish at PAVING and a slab lapping the coping
# by a stud and a half is the whole length of the wharf flickering. The last
# stud and a half of the quay is the coping's own top, which is what it is on a
# real one.
QUAY_FACE_IN = 1.4
QUAY_FACE_OUT = 1.6

# The tag the game reads to find an interactive sports piece. Decorative --
# nothing in the Luau runtime reads it yet, but the rules that will (referee
# positioning, ball spawns) need one part per fixture named by kind, not a
# search through geometry.
SPORT_TAG = "AgesSportFacility"
SPORT_KIND = "FacilityKind"
CAR_TAG = "AgesCarDisplay"
CAR_MODEL_ATTR = "CarModel"

# The tag SportsDrillService reads to find a drill anchor: a bag, a hoop rim,
# a net, a goal crossbar. Separate from SPORT_TAG on purpose -- that one marks
# every decorative fixture (three ropes and four posts per ring), and a
# machine index built off it would find a dozen "boxing" parts an inch apart
# and call it seven treadmills in one room. This tag goes on exactly the parts
# that are a *drill station*: something a player stands at and works a timing
# sweep against, one tag per station rather than one per fixture.
SPORTS_DRILL_TAG = "AgesSportsDrill"
SPORTS_DRILL_KIND = "SportsDrillKind"

# The tags StadiumCrowdService reads to seat and roam real NPCs in the bowl.
# Every seat in every tier row carries `STADIUM_CROWD_SEAT_TAG` -- there is no
# static crowd any more (see `stadium_seat`): the row is built entirely of
# small, unoccupied seat furniture, and a real avatar dropped on one stands
# or sits directly at the furniture rather than beside a static double. A
# roam anchor is a stop on a stand's concourse walkway; anchors that share a
# `STADIUM_CROWD_STAND_ATTR` value are one stand's loop; a wandering NPC
# walks its stand's loop and only its stand's loop, never crossing into the
# next one, so it never has to pathfind past a wall it can't see over.
STADIUM_CROWD_SEAT_TAG = "AgesStadiumCrowdSeat"
STADIUM_CROWD_ROAM_TAG = "AgesStadiumCrowdRoam"
STADIUM_CROWD_STAND_ATTR = "Stand"

# The tag StadiumEntranceService reads to know where the bowl's own gate
# opening is -- a single invisible, non-colliding part standing in the
# StandWest doorway (see GateArch), matched against Config.StadiumEntrance's
# copy of this same string the way every other tag pair in this file is: no
# shared source, so a rename here means a rename there too.
STADIUM_GATE_TAG = "AgesStadiumGate"

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------

# **The palette is the difference between a city and a grid of boxes.**
#
# What was here before was eight browns, four greys and a brick red, and the
# result read as one long wall no matter how much the layout varied -- the
# geometry was already doing its job and the colour was undoing it. What is here
# now is the south-Florida seaboard: pastel stucco, white deco banding, barrel
# tile, and water. It is a *narrow* palette on purpose, in the way a real
# seafront is narrow -- every wall is a light, desaturated tint, so the few
# saturated things (an awning, a neon band, the sea) are the only things that
# shout, and they are the things worth looking at.
#
# Kept literal rather than generated. These are art direction, and a formula
# that produced them would be a formula somebody had to reverse-engineer before
# they could change one wall.

LAWN = (118, 158, 88)
TARMAC = (58, 58, 61)
ROAD_PAINT = (240, 236, 222)
PAVING_GREY = (206, 202, 192)
KERB_GREY = (186, 182, 172)
PATH_STONE = (222, 212, 192)

BRICK_WARM = (216, 156, 128)
BRICK_PALE = (238, 226, 206)
TRIM_WHITE = (252, 250, 244)
ROOF_GREY = (196, 106, 74)
GLAZING = (168, 210, 220)
STEEL = (128, 130, 134)
AWNING_RED = (232, 96, 92)
AWNING_CREAM = (250, 240, 214)
# The rest of the awning palette. An awning is the single loudest thing a
# storefront owns -- it is the only saturated colour at eye level on a street of
# brick -- so these are the shop's identity at fifty studs, read long before the
# sign is legible. Kept few and far apart in hue on purpose: six awning colours
# a player can name beat twelve they have to compare side by side.
AWNING_GREEN = (86, 150, 106)
AWNING_BLUE = (84, 124, 178)
AWNING_MUSTARD = (222, 176, 84)

# The sea, the sand, and the things that stand in front of them.
SEA_SHALLOW = (104, 206, 208)
SEA_DEEP = (36, 132, 168)
SEABED = (214, 200, 166)
BEACH_SAND = (240, 226, 190)
PALM_TRUNK = (166, 142, 112)
PALM_FROND = (94, 168, 96)
PALM_FROND_2 = (118, 186, 108)

# Shop neon. A thin band under a sign or along an awning, never a wall: neon is
# a line in this palette and a neon surface is a mistake. Pink, cyan and lime
# stood here beside it and went unused once downtown took its own two colours --
# a palette entry nothing draws is the same orphan as a function nothing calls.
NEON_AMBER = (255, 186, 88)

# Downtown's two, and they are deliberately not the four above.
#
# Those four are shop neon: they sit at eye level, on an awning or under a sign,
# where a saturated line is legible and the thing next to it is a doorway.
#
# **Height decides the colour, not the building.** These two were taken right
# down to (96, 44, 74) and (44, 58, 104) to stop the skyline reading as a
# fairground -- which fixed the roofs and ruined the streets, because a deep
# rose at street level is not a highlight, it is a dark stripe. The rule that
# actually holds is the one below: colour lives *down here*, where it is seen
# against a wall and read as a lit edge, and the roofline is white. So these go
# back to the light tints that worked, and nothing at roof height uses them.
DOWNTOWN_NEON = [
    (246, 176, 206),   # light rose
    (158, 200, 246),   # light blue
]

# What a band at roof height is instead.
#
# A crown is seen against open sky, the highest contrast anything in the city
# gets, and it is seen from half the map at once. Colour up there is a claim
# every tower makes simultaneously and the skyline cannot absorb twenty of them.
# White can: it reads as the building's own edge catching the light, which is
# what a lit parapet is, and it leaves the pink and the blue down at the doors
# where they mean "this is the way in".
CROWN_NEON = (234, 238, 246)
# How far a band at roof height is taken down. Applied to CROWN_NEON, never to
# DOWNTOWN_NEON -- a street band takes its colour whole.
NEON_ROOF_DIM = 0.55   # safe range 0.35 .. 0.8; 1.0 puts the fairground back


def dim(color, k):
    """`color` scaled toward black. See NEON_ROOF_DIM for why a roof band and a
    street band cannot share one value."""
    return tuple(int(round(c * k)) for c in color)

# The works, and the one place the seafront palette is deliberately broken.
#
# Every wall in the city is a light desaturated tint, and that is the rule that
# makes an awning read at fifty studs. An industrial district painted in those
# tints would be a pastel factory, which is nothing -- and the whole reason to
# build a second district is that the player can tell from the colour, before
# reading a single sign, that they have left downtown. So the works gets the
# opposite palette: no tints, low saturation, high contrast, and rust. The
# saturated thing here is safety yellow rather than an awning.
WORKS_BRICK = (140, 92, 76)      # soot-darkened engineering brick
WORKS_CLAD = (122, 130, 136)     # profiled steel sheet
WORKS_CLAD_2 = (96, 104, 112)    # the darker sheet, for a second shed
CONCRETE_GREY = (166, 164, 158)
RUST = (146, 88, 56)
SAFETY_YELLOW = (232, 184, 56)
WORKS_TARMAC = (72, 70, 68)      # yard hardstanding: a shade off the roads, so
                                 # a yard is visibly not a carriageway
LOG_BROWN = (128, 96, 64)
CONTAINER_COLORS = [(196, 80, 64), (60, 116, 154), (206, 158, 60),
                    (74, 128, 92), (168, 168, 172)]

FLOOR_INDOOR = (232, 226, 214)
PARTITION_PALE = (240, 236, 228)

BARK = (118, 96, 74)
LEAF = (96, 156, 84)

FITTING = (238, 236, 228)
LAMP_LIGHT = (255, 236, 196)
INDOOR_LIGHT = (255, 248, 232)

DESK_TOP = (196, 166, 126)
DESK_LEG = (110, 112, 116)
SEAT = (72, 96, 132)
SHELF = (146, 148, 152)
STOCK = (176, 142, 96)

# Houses take a handful of wall tones so a full avenue reads as houses rather
# than as one long wall. Roofs cycle three tones on top of that.
#
# Eight walls against three roofs is twenty-four combinations before the two
# floor plans are counted, and the cycles are coprime-ish, so a six-house block
# never repeats a pair. That is the whole trick to a residential street that
# does not read as wallpaper.
HOUSE_WALLS = [
    (246, 226, 198),   # sand stucco
    (238, 198, 196),   # shell pink
    (208, 232, 220),   # seafoam
    (250, 240, 206),   # butter
    (206, 226, 240),   # sky
    (244, 214, 190),   # apricot
    (224, 214, 238),   # lilac
    (250, 246, 236),   # white stucco
]
HOUSE_ROOFS = [
    (196, 106, 74),    # barrel tile
    (172, 88, 66),     # weathered tile
    (232, 226, 212),   # flat white deco
]

# Lot plans.
#
# Colour alone was never going to be enough. Sixty houses were sixty copies of
# one 32x36 box on a dead-straight 39-stud pitch, all topping out at the same
# y=17.52, and from the avenue that reads as a fence with the paint changing
# rather than as a street. Three things break it, and all three are needed --
# any one on its own still leaves a pattern:
#
#   * depth, so the row has a rhythm and the gaps between houses vary;
#   * setback and width, so the building line is jagged rather than ruled;
#   * storeys, so the roofline steps instead of running flat to the horizon.
#
# The west and east rows of a block get *different* depth plans on purpose. When
# both rows shared one plan every house had a twin directly opposite it across
# the lane, which is its own kind of wallpaper and is visible from either
# pavement.
#
# Depths sum short of the 120-stud block and the leftover becomes the margins
# and gaps, so a plan can never overrun the block however it is edited -- see
# lot_run(). Nothing here may drop below 30: the fittings reach iz1 - 9 and the
# stair of a two-storey house needs 17 studs of interior depth.
HOUSE_PLANS = [
    ((36.0, 30.0, 34.0), (32.0, 36.0, 30.0)),
    ((30.0, 36.0, 32.0), (36.0, 30.0, 36.0)),
    ((34.0, 32.0, 36.0), (30.0, 34.0, 34.0)),
    ((32.0, 34.0, 30.0), (34.0, 32.0, 36.0)),
]

# (width, setback, storeys, roof), in three sets by how near downtown the block
# is. Setback pushes the house *away* from its avenue, into the block, so it can
# only ever add front garden -- it can never push a wall out over the pavement,
# which is what check 7 would catch.
#
# There used to be one set of seven for the whole city, widths 28 to 32 and one
# or two storeys, and it was not enough. A four-stud spread on a thirty-stud
# house is invisible from across a street, so every residential block in the
# city read as the same six houses -- which they very nearly were, because the
# sequence was a fixed cycle keyed to the block index and the only thing that
# changed between neighbourhoods was where in the cycle it started.
#
# The fix is not more entries. It is that **where you are should decide what
# kind of house you get**, which is the one thing the old table could not
# express. Near the Circle the houses are wide, two-storey and pushed up against
# the pavement; at the city's edge they are narrow, single-storey and set well
# back behind a garden. A player walking out from downtown now crosses a
# gradient rather than a repeat.
#
# The three constraints that bound every number below:
#
#   * **setback + width must stay <= 42.** Two rows face each other across a
#     block interior that is 102 studs wide since the roads widened, so 42 each
#     leaves an 18-stud lane between the back gardens. Go over and the rows meet
#     in the middle.
#   * **width must stay >= 28 for a two-storey house.** Below that the upstairs
#     stair and its guard stop fitting. A 26-wide two-storey is not a small
#     house, it is a broken one -- so every entry under 30 here is deliberately
#     single-storey.
#   * **seven entries per tier, against six houses a block.** Coprime with the
#     row length on purpose: the sequence walks round rather than repeating, so
#     no block gets the run its neighbour had.
#
# Safe range: width 28 .. 42, setback 0 .. 12, storeys 1 or 2 (house_shell
# supports no third -- it would need a floor slab, a second stair and a window
# course, which is a real change and not a number).

# Nearest the Circle. Wide, tall, and close to the street -- this is the one
# tier that should read as *urban* housing rather than as suburbia that happens
# to be central. Six of the seven are two-storey, which is what makes the
# roofline step up as you walk in toward downtown.
HOUSE_STYLES_INNER = [
    (40.0, 0.0, 2, "flat"),
    (38.0, 2.0, 2, "hip"),
    (42.0, 0.0, 2, "flat"),
    (36.0, 4.0, 2, "hip"),
    (40.0, 2.0, 1, "flat"),
    (38.0, 0.0, 2, "flat"),
    (36.0, 2.0, 2, "hip"),
]

# The middle of the city. Deliberately the most mixed of the three -- half the
# houses two-storey, setbacks all over the range -- because this is where most
# of the residential blocks are and it is the tier most at risk of reading as
# a pattern.
HOUSE_STYLES_MID = [
    (34.0, 4.0, 2, "hip"),
    (30.0, 8.0, 1, "flat"),
    (36.0, 2.0, 2, "flat"),
    (32.0, 6.0, 1, "hip"),
    (34.0, 2.0, 1, "flat"),
    (30.0, 4.0, 2, "hip"),
    (36.0, 0.0, 1, "flat"),
]

# The city's edge. Narrow, low and set back behind a garden. Five of seven are
# single-storey, so the skyline drops away at the rim.
HOUSE_STYLES_OUTER = [
    (28.0, 10.0, 1, "hip"),
    (28.0, 12.0, 1, "flat"),
    (30.0, 8.0, 1, "hip"),
    (28.0, 10.0, 2, "flat"),
    (30.0, 12.0, 1, "hip"),
    (30.0, 10.0, 1, "flat"),
    (28.0, 8.0, 2, "hip"),
]

HOUSE_TIERS = [HOUSE_STYLES_INNER, HOUSE_STYLES_MID, HOUSE_STYLES_OUTER]


def house_tier(band, sband):
    """Which style set a residential block draws from, by how far it is from the
    Circle.

    The Circle sits on the *junction* of avenue 3 and cross street 2, not in a
    block, so the distance is measured to that corner -- hence the halves.
    Chebyshev rather than straight-line because the city is a grid and what the
    player actually walks is blocks-across plus blocks-up, not a diagonal.

    With the current ROLES this puts 12 houses in the inner tier, 36 in the mid
    and 12 in the outer, which is the shape you want: the extremes are rare
    enough to read as special and the middle is where most of the city lives.
    """
    rings = max(abs(band - (CIRCLE_AVE - 0.5)), abs(sband - (CIRCLE_CS - 0.5)))
    if rings <= 1.5:
        return 0
    if rings <= 2.5:
        return 1
    return 2

# The gap between two houses, as a multiple of the margin left at the block's
# ends. Above 1 because a hole in the middle of a terrace reads as a garden
# path and a hole at the end reads as a mistake. Safe range: 1.5 .. 3.0.
HOUSE_GAP_RATIO = 2.3

HOUSE_PARAPET = 2.0     # flat-roof upstand, studs above the roof slab.
HOUSE_HIP_STEPS = 3     # stacked slabs that stand in for a pitched roof.
HOUSE_HIP_INSET = 3.0   # each step is this much smaller all round than the last.
HOUSE_HIP_RISE = 1.6    # and this much taller.

# Car display colours for the dealership forecourt.
CAR_COLORS = [
    (200, 56, 56),   # red
    (56, 80, 160),   # blue
    (220, 216, 200), # white
]

# Storefronts cycle a wider palette, one tone per business. Ten tones against a
# thirteen-building civic row and an eight-building north strip, so neither row
# lands the same colour twice in a row.
STORE_WALLS = [
    (250, 246, 236),   # deco white
    (248, 206, 168),   # sherbet
    (170, 222, 216),   # turquoise
    (250, 236, 190),   # banana
    (244, 186, 196),   # flamingo
    (198, 226, 240),   # pale aqua
    (238, 224, 202),   # cream
    (212, 200, 236),   # lavender
    (150, 200, 214),   # gulf blue
    (246, 172, 146),   # coral
]

# Apartments read as stucco walk-ups with a white deco band under the parapet.
APT_WALLS = [
    (242, 218, 200), (206, 230, 224), (248, 234, 202), (226, 210, 236),
    (200, 222, 238), (246, 202, 198),
]
APT_BAND = (252, 250, 244)
BALCONY = (238, 234, 224)

PITCH_GREEN = (96, 160, 88)
COURT_BLUE = (96, 120, 176)
COURT_GREEN = (120, 170, 120)
TRACK_RED = (176, 96, 84)
SAND = (212, 196, 156)
WATER = (96, 150, 176)

OFFICE_GLASS = (150, 200, 210)
OFFICE_FRAME = (232, 228, 216)
OFFICE_LOBBY = (244, 240, 230)

# Financial district palette. Tropical curtain wall: every tower is a tint of
# sea or sky except the two bronzes, which are there so the row is not a single
# blue-green smear. Frames are white rather than charcoal -- a dark mullion on a
# pale tower is what makes an office block read as an office block in an
# overcast city, and this one is not overcast.
RISE_GLASS = [
    (120, 196, 206),   # aqua
    (156, 214, 200),   # seafoam
    (168, 206, 232),   # sky
    (206, 176, 130),   # bronze
    (96, 168, 200),    # gulf
    (186, 220, 212),   # pale mint
    (196, 190, 226),   # dusk violet
    (222, 190, 148),   # warm bronze
]
RISE_FRAME = (250, 248, 240)
RISE_MARBLE = (250, 246, 238)
BANK_MARBLE = (250, 246, 236)
DOME_GOLD = (226, 196, 116)
CITY_HALL_MARBLE = (250, 246, 238)

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


def glass_doors(name, bounds, along="z", leaves=2, height=DOOR_HEIGHT):
    """A doorway's own opening, filled with real door leaves instead of standing
    open as a bare gap in the wall -- every `wall(doors=...)` cut in this codebase
    up to now has only ever removed material, never put anything back in the hole,
    which reads as a missing door rather than an open one. Two (or more) glass
    leaves meet at a centre mullion, each with a horizontal push bar at hand
    height. Non-colliding on purpose: the wall's own `doors=` cut already defines
    where a player can walk, and a swinging leaf with no open/close state would
    just be a wall that looks like a door and blocks like one too."""
    x0, x1, z0, z1, y0, y1 = bounds
    lo, hi = (z0, z1) if along == "z" else (x0, x1)
    step = (hi - lo) / leaves
    bar_y = y0 + 3.4
    for i in range(leaves):
        a, b = lo + i * step + 0.3, lo + (i + 1) * step - 0.3
        leaf_bounds = (
            (x0, x1, a, b, y0, y0 + height) if along == "z"
            else (a, b, z0, z1, y0, y0 + height)
        )
        box(f"{name}{i + 1}", leaf_bounds, GLAZING, GLASS, transparency=0.3, collide=False)
        bar_a, bar_b = a + 0.6, b - 0.6
        bar_bounds = (
            (x0, x1, bar_a, bar_b, bar_y, bar_y + 0.25) if along == "z"
            else (bar_a, bar_b, z0, z1, bar_y, bar_y + 0.25)
        )
        box(f"{name}{i + 1}Bar", bar_bounds, STEEL, METAL, collide=False)


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
            part("Trunk", (0, 0, 0), (TRUNK_WIDTH, height * 0.62, TRUNK_WIDTH),
                 BARK, WOOD)
            part("Canopy", (0, height * 0.5, 0), (spread, spread * 0.72, spread),
                 LEAF, LEAFY_GRASS, collide=False)
            part("CanopyTop", (0, height * 0.5 + spread * 0.5, 0),
                 (spread * 0.66, spread * 0.5, spread * 0.66),
                 LEAF, LEAFY_GRASS, collide=False)


def palm(x, z, floor, height=22.0, spread=13.0, label="Palm", lean=0):
    """A palm: a bare trunk most of the way up and a crown of eight fronds.

    The one tree that does the whole job of saying where this city is, so it is
    worth the seven extra parts over `tree`. Two things make it read as a palm
    rather than as a lollipop: the trunk is most of the height with nothing on
    it -- palms are legible from the ankles up, which is why they line streets
    without blocking a shopfront -- and the crown droops, so the fronds are
    boxes tilted down and out rather than a ball.

    `lean` (-1, 0, +1) tips the whole tree a few studs along x. Real palms do
    not stand plumb, and a row of them all perfectly vertical is the one way to
    make eighty palms look like eighty copies of one palm.
    """
    trunk_h = height * 0.78
    with group(label):
        with at(x, z, floor=floor):
            # Trunk in three tapering segments, each nudged by `lean`, so the
            # top of the tree is offset from its base without needing rotation.
            seg = trunk_h / 3
            for i, (w, off) in enumerate(((1.5, 0.0), (1.25, 0.35), (1.0, 0.8))):
                part(f"Trunk{i}", (lean * off, seg * i, 0), (w, seg + 0.2, w),
                     PALM_TRUNK, WOOD)
            top = trunk_h
            tip = lean * 0.8
            part("Crown", (tip, top, 0), (2.0, 1.6, 2.0), PALM_TRUNK, WOOD)
            # Eight fronds on the diagonals and the axes, each a flat box
            # reaching out and sagging below the crown.
            reach = spread / 2
            for i, (dx, dz) in enumerate((
                    (1, 0), (-1, 0), (0, 1), (0, -1),
                    (0.7, 0.7), (-0.7, 0.7), (0.7, -0.7), (-0.7, -0.7))):
                leaf = PALM_FROND if i % 2 == 0 else PALM_FROND_2
                part(f"Frond{i}", (tip + dx * reach * 0.5, top + 0.6, dz * reach * 0.5),
                     (abs(dx) * spread + 2.0, 0.5, abs(dz) * spread + 2.0),
                     leaf, LEAFY_GRASS, collide=False)
                # The drooping outer half, one stud lower and further out.
                part(f"FrondTip{i}", (tip + dx * reach, top - 1.2, dz * reach),
                     (abs(dx) * spread * 0.6 + 1.4, 0.5, abs(dz) * spread * 0.6 + 1.4),
                     leaf, LEAFY_GRASS, collide=False)


def palm_row(x0, x1, z0, z1, floor, step=34.0, along="z", label="Palms"):
    """Palms at a fixed spacing down a strip, alternating lean so the row reads
    as planting rather than as a fence. Skips nothing: callers pass a strip that
    is already clear."""
    with group(label):
        if along == "z":
            x = (x0 + x1) / 2
            n = max(int((z1 - z0) / step), 1)
            for i in range(n):
                z = z0 + step / 2 + i * step
                palm(x, z, floor, height=20.0 + (i % 3) * 2.0,
                     spread=12.0 + (i % 2) * 2.0, lean=(i % 3) - 1)
        else:
            z = (z0 + z1) / 2
            n = max(int((x1 - x0) / step), 1)
            for i in range(n):
                x = x0 + step / 2 + i * step
                palm(x, z, floor, height=20.0 + (i % 3) * 2.0,
                     spread=12.0 + (i % 2) * 2.0, lean=(i % 3) - 1)


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


def bench(x, z, toward, label="Bench", floor=GROUND):
    """A park bench, `toward` (+1/-1) tells which way it faces."""
    with group(label):
        with at(x, z, side=("north" if toward > 0 else "south"), floor=floor):
            part("Seat", (0, 1.5, 0), (5.0, 0.35, 1.2), DESK_TOP, WOOD)
            part("Back", (0, 2.1, -1.0), (5.0, 1.4, 0.25), DESK_TOP, WOOD)
            for dx in (-2.0, 2.0):
                part("Leg", (dx, 0, 0), (0.4, 1.5, 0.8), STEEL, METAL)


# ---------------------------------------------------------------------------
# Curves
# ---------------------------------------------------------------------------

# Three helpers and every round thing in the city is built from them. They exist
# because `box` cannot describe a curve at all -- it takes two x's and two z's --
# and because writing the trigonometry out at each call site would put the same
# four lines in a dozen places and let one of them drift.


def polar(radius, phi_deg, cx=None, cz=None):
    """(x, z) at `radius` and `phi_deg` degrees round the Circle's centre.

    Zero degrees is east (+x) and the angle runs toward +z, which is the same
    direction `spun_box` measures a negative yaw in -- see `radial_yaw`.
    """
    phi = math.radians(phi_deg)
    return ((CIRCLE_X if cx is None else cx) + radius * math.cos(phi),
            (CIRCLE_Z if cz is None else cz) + radius * math.sin(phi))


def radial_yaw(phi_deg):
    """The `spun_box` yaw that points a box's local +X axis outward along phi.

    `spun_box` sends local +X to world (cos yaw, -sin yaw), so the yaw that lands
    it on (cos phi, sin phi) is -phi. One line, written once, because getting the
    sign wrong mirrors the whole city and every part of it still looks plausible.
    """
    return -phi_deg


def ring(label, r_in, r_out, y0, y_top, color, material, keep=None,
         cx=None, cz=None, segs=CIRCLE_SEGS, seam=CIRCLE_SEAM, collide=True,
         transparency=0.0, tags=None, attrs=None):
    """An annulus paved with `segs` boxes, each spun to face out of the centre.

    Each facet is sized to cover its whole sector at `r_out`, which means
    neighbours lap by up to (r_out - r_in) * sin(180/segs) at the inner edge.
    That is deliberate: the alternative is sizing at `r_in`, which leaves a
    wedge of bare lawn showing through the outer edge of every seam. `seam`
    drops alternate facets a hairline so the lap cannot z-fight -- see
    CIRCLE_SEAM.

    `keep(i)` decides which facets are drawn, which is how the pavement ring gets
    its four openings without a second function.
    """
    half = math.radians(180.0 / segs)
    depth = r_out - r_in
    width = 2.0 * r_out * math.sin(half)
    mid = (r_in + r_out) / 2
    with group(label):
        for i in range(segs):
            if keep is not None and not keep(i):
                continue
            phi = i * (360.0 / segs)
            px, pz = polar(mid, phi, cx, cz)
            top = y_top - (seam if i % 2 else 0.0)
            rbxmx.spun_box(f"{label}{i}", (px, (y0 + top) / 2, pz),
                           (depth, top - y0, width), radial_yaw(phi),
                           color, material, transparency=transparency,
                           collide=collide, tags=tags, attrs=attrs)


def disc(label, radius, y0, y_top, color, material, cx=None, cz=None,
         segs=CIRCLE_SEGS, collide=True):
    """A filled disc: a square core with one annulus round it.

    The square's half-width is half the radius, so its inscribed circle is the
    annulus's inner boundary and its corners reach past it -- the two overlap
    everywhere they meet and there is no seam to fall down. Trying to fill a
    disc with `ring` alone does not work: the facets at the middle would be
    slivers meeting at a point.
    """
    core = radius * 0.5
    px = CIRCLE_X if cx is None else cx
    pz = CIRCLE_Z if cz is None else cz
    with group(label):
        # A shade under the annulus, and under *both* of the annulus's alternating
        # heights, so the corners where the two overlap have an unambiguous
        # winner. The middle of the disc is the only part of the core anyone sees.
        box(f"{label}Core", (px - core, px + core, pz - core, pz + core,
                             y0, y_top - CIRCLE_SEAM * 2),
            color, material, collide=collide)
    ring(f"{label}Edge", core, radius, y0, y_top, color, material,
         cx=cx, cz=cz, segs=segs, collide=collide)


# `polar`/`radial_yaw`/`ring` above are circle-only: one radius, the same in
# every direction. The stadium's bowl is not -- its pitch is 70 studs wide
# and 110 deep, so a true circle round it is either too tight on the
# touchlines or wastes 40 studs of open ground behind each goal. These three
# generalise the same three functions to an ellipse of two independent radii,
# `rx` and `rz`, which is a circle exactly when the two are equal -- so
# nothing that already calls `polar`/`radial_yaw`/`ring` needs to change,
# and the stadium gets a shape its own dome (an ellipsoid, see `ball` in
# rbxmx.py and `stadium_roof`) can actually match.
def ellipse_point(phi_deg, cx, cz, rx, rz):
    """(x, z) at angle `phi_deg` on the ellipse centred at (cx, cz) with
    semi-axes `rx` (along x) and `rz` (along z). Same convention as `polar`:
    phi=0 is +x, running toward +z."""
    phi = math.radians(phi_deg)
    return cx + rx * math.cos(phi), cz + rz * math.sin(phi)


def ellipse_outward_yaw(phi_deg, rx, rz):
    """The `spun_box` yaw that faces a box outward along the ellipse's own
    normal at `phi_deg` -- not `phi_deg` itself, which is only the outward
    direction on a true circle. The outward normal to (x/rx)^2+(z/rz)^2=1 at
    (rx*cos(phi), rz*sin(phi)) points along (cos(phi)/rx, sin(phi)/rz); on an
    oval as eccentric as the stadium's (rx=70, rz=90) the two directions
    differ by several degrees away from the axes, enough that a seat
    oriented by raw phi visibly does not face the pitch. Reduces to
    `radial_yaw` exactly when rx == rz."""
    phi = math.radians(phi_deg)
    nx, nz = math.cos(phi) / rx, math.sin(phi) / rz
    return math.degrees(math.atan2(-nz, nx))


def elliptical_ring(label, cx, cz, rx_out, rz_out, rx_in, rz_in, y0, y_top,
                     color, material, keep=None, door_facets=(), door_head=12.0,
                     segs=CIRCLE_SEGS, seam=CIRCLE_SEAM, collide=True,
                     transparency=0.0, tags=None, attrs=None):
    """The elliptical equivalent of `ring`: an annulus of `segs` boxes
    between two concentric ellipses, each spun to face outward along the
    true ellipse normal at its own centre angle (`ellipse_outward_yaw`, not
    `radial_yaw`) and sized to its own local outward radius, since that
    radius is not the same at every angle the way it is for `ring`. Facets
    listed in `door_facets` are cut down to a lintel above `door_head`
    studs, an open doorway below it -- the same shape `wall(doors=...)` cuts
    for every axis-aligned wall in the city, built by hand here because
    `wall` only knows a straight span and this facet is spun."""
    half = math.radians(180.0 / segs)
    with group(label):
        for i in range(segs):
            if keep is not None and not keep(i):
                continue
            phi = i * (360.0 / segs)
            ox, oz = ellipse_point(phi, cx, cz, rx_out, rz_out)
            ix, iz = ellipse_point(phi, cx, cz, rx_in, rz_in)
            depth = math.hypot(ox - ix, oz - iz)
            mx, mz = (ox + ix) / 2, (oz + iz) / 2
            r_here = math.hypot(ox - cx, oz - cz)
            width = 2.0 * r_here * math.sin(half)
            yaw = ellipse_outward_yaw(phi, rx_out, rz_out)
            top = y_top - (seam if i % 2 else 0.0)
            lo = y0 + door_head if i in door_facets else y0
            rbxmx.spun_box(f"{label}{i}", (mx, (lo + top) / 2, mz),
                           (depth, top - lo, width), yaw,
                           color, material, transparency=transparency,
                           collide=collide, tags=tags, attrs=attrs)


# ---------------------------------------------------------------------------
# Streets
# ---------------------------------------------------------------------------


# A road and its pavements are drawn by two separate passes, because they are
# carved at different places: a road yields only to the roads it crosses, while
# a pavement has to yield to the crossing street's pavement as well or the two
# fight over the corner. Both used to be drawn by `road_*`, and then the pavement
# pass drew them *again* at its own carve -- so every sidewalk in the city was
# two boxes occupying the same space, hundreds of coincident faces that Roblox
# resolves by flickering. These four functions now each do one job.


def road_ns(x0, x1, z0, z1, prefix):
    """One north-south carriageway."""
    box(f"{prefix}Road", (x0, x1, z0, z1, GROUND_BOTTOM, GROUND), TARMAC, ASPHALT)


def walks_ns(x0, x1, z0, z1, walk, prefix, sides="both"):
    """The pavements flanking a north-south road. `sides` leaves one of them off,
    for the edge of the map and for a verge that has to be carved on one side and
    not the other."""
    # The kerb is the KERB_WIDTH strip against the carriageway and nothing more.
    # It used to be written `(x0 - walk, x0)` -- the *whole* pavement, drawn again
    # underneath the paving and finishing at exactly the same height, so every
    # west kerb and every south kerb in the city was two coincident slabs the
    # depth buffer had to choose between per frame. The east and north sides were
    # always right, which is why it read as "the pavement flickers on one side".
    if sides in ("both", "west"):
        box(f"{prefix}KerbW", (x0 - KERB_WIDTH, x0, z0, z1, GROUND - SLAB_SINK, PAVING),
            KERB_GREY, CONCRETE)
        box(f"{prefix}PavW", (x0 - walk, x0 - KERB_WIDTH, z0, z1, GROUND - SLAB_SINK, PAVING),
            PAVING_GREY, PEBBLE)
    if sides in ("both", "east"):
        box(f"{prefix}KerbE", (x1, x1 + KERB_WIDTH, z0, z1, GROUND - SLAB_SINK, PAVING),
            KERB_GREY, CONCRETE)
        box(f"{prefix}PavE", (x1 + KERB_WIDTH, x1 + walk, z0, z1, GROUND - SLAB_SINK, PAVING),
            PAVING_GREY, PEBBLE)


def road_ew(z0, z1, x0, x1, prefix, lift=0.0):
    """One east-west carriageway.

    ``lift`` raises the surface a hairline. Inside the city nothing needs it --
    the city's own lawns are laid at CITY_GRASS_TOP, a fiftieth under the road,
    precisely so the road always wins. The gate road is the one piece of city
    that crosses ground the *town* generator laid, and the town's grass tops at
    exactly GROUND, so without a lift the two are coplanar and the whole 83x14
    stud surface flickers.
    """
    box(f"{prefix}Road", (x0, x1, z0, z1, GROUND_BOTTOM, GROUND + lift),
        TARMAC, ASPHALT)


def walks_ew(z0, z1, x0, x1, walk, prefix, sides="both"):
    """The pavements flanking an east-west road."""
    if sides in ("both", "south"):
        # Same one-strip rule as walks_ns -- see the note there.
        box(f"{prefix}KerbS", (x0, x1, z0 - KERB_WIDTH, z0, GROUND - SLAB_SINK, PAVING),
            KERB_GREY, CONCRETE)
        box(f"{prefix}PavS", (x0, x1, z0 - walk, z0 - KERB_WIDTH, GROUND - SLAB_SINK, PAVING),
            PAVING_GREY, PEBBLE)
    if sides in ("both", "north"):
        box(f"{prefix}KerbN", (x0, x1, z1, z1 + KERB_WIDTH, GROUND - SLAB_SINK, PAVING),
            KERB_GREY, CONCRETE)
        box(f"{prefix}PavN", (x0, x1, z1 + KERB_WIDTH, z1 + walk, GROUND - SLAB_SINK, PAVING),
            PAVING_GREY, PEBBLE)


# How far a centre line stands proud of the tarmac it is painted on. It is a
# clearance, not a height, and every dash is placed at its own road's surface
# plus this -- which is the whole reason `lift` is threaded through the two
# functions below.
#
# It used to be an absolute `GROUND + 0.02`, correct for the seventy-odd roads
# laid at GROUND and wrong for the one that is not. The gate road is lifted by
# GRASS_LIFT so it beats the town's grass, which puts its surface at exactly
# GROUND + 0.02 as well -- so all eleven of its centre dashes were coincident
# with the road underneath them, six studs by six tenths each, and would have
# flickered. check 10 could not see it: it compares assets against each other,
# and both of these are City.rbxmx.
PAINT_LIFT = 0.02
PAINT_THICK = 0.12
# The same two numbers for the paint that is *not* on a road: the Circle's
# markings and the sports courts' lines, all of which are laid on surfaces at
# GROUND. Derived from the pair above so there is one thickness of paint in the
# city and not two.
PAINT_TOP = GROUND + PAINT_LIFT
PAINT_BOTTOM = PAINT_TOP - PAINT_THICK
# Paint over paint. Two markings that cross -- a zebra crossing over the ring's
# lane line, a centre circle over a halfway line -- are one coat on a real
# surface and two boxes here, and two boxes at one height flicker over every
# stud they share. The upper is the one painted last, which on a road is always
# the crossing and on a pitch is always the circle.
PAINT_OVER_TOP = PAINT_TOP + GROUND_STEP
PAINT_OVER_BOTTOM = PAINT_OVER_TOP - PAINT_THICK
DASH = 6.0
GAP = 6.0


def dashes_ns(x, z_lo, z_hi, gaps, prefix, lift=0.0):
    """Centre dashes along a north-south road, carved at its crossings.

    ``lift`` must match the road's own -- see PAINT_LIFT."""
    top = GROUND + lift + PAINT_LIFT
    for za, zb in carve((z_lo, z_hi), gaps):
        z = za + DASH
        while z + DASH <= zb - DASH:
            box(f"{prefix}Dash{z:.0f}",
                (x - 0.3, x + 0.3, z, z + DASH, top - PAINT_THICK, top),
                ROAD_PAINT, SMOOTH)
            z += DASH + GAP


def dashes_ew(z, x_lo, x_hi, gaps, prefix, lift=0.0):
    """Centre dashes along an east-west road.

    ``lift`` must match the road's own -- see PAINT_LIFT."""
    top = GROUND + lift + PAINT_LIFT
    for xa, xb in carve((x_lo, x_hi), gaps):
        x = xa + DASH
        while x + DASH <= xb - DASH:
            box(f"{prefix}Dash{x:.0f}",
                (x, x + DASH, z - 0.3, z + 0.3, top - PAINT_THICK, top),
                ROAD_PAINT, SMOOTH)
            x += DASH + GAP


with group("Ground"):
    # One box per shore band rather than one box for the city, because the land
    # has to stop at the waterline. A single slab run to the map edge with the
    # bay drawn on top of it would put grass under the sea -- invisible until the
    # first player walked out far enough to see the seabed was green.
    for _i, (_sz0, _sz1, _sx1, _edge) in enumerate(SHORE):
        box(f"CityGround{_i}", (CITY_X0, _sx1, _sz0, _sz1, GROUND_BOTTOM, CITY_GRASS_TOP),
            LAWN, GRASS)

    # The west estate's ground. It stops at CITY_X0 and not at EST_X1, which is
    # five studs further east: CityGround already starts at CITY_X0 and runs
    # under the connector and its two footways, and a second slab reaching to
    # the frontage line would put two boxes with the same top height in the same
    # five studs for the whole 813-stud length of the estate. That is the one
    # defect every surface in this file is tiled to avoid, and here it would have
    # been a hairline of z-fight down the entire west side of the map.
    #
    # Its south face lands on EST_Z0, which is NORTHGATE_CLEAR[1], which is
    # exactly where gen_town.py stops its own lawns (`NORTH_Z1`). The seam
    # between the town's grass and the estate's is a shared edge in two files
    # that both name it after the same road.
    #
    # It stops at the common's east edge rather than running under it. The
    # common lays its own pasture at the same top height, and a slab under a
    # slab is the whole 400-stud width of the common z-fighting -- the same
    # mistake as the five studs at the other end, in the other direction. Grass,
    # pasture, verge: three tiles, each owning its own ground, which is how every
    # other surface in this file is laid.
    box("WestGround", (EST_COMMON_X1, CITY_X0, EST_Z0, EST_Z1,
                       GROUND_BOTTOM, CITY_GRASS_TOP), LAWN, GRASS)

with group("Streets"):
    # The connector, uncarved -- it is the through route and nothing crosses it.
    # Its west verge runs the full length; its east verge is carved at the cross
    # streets, which now run right up to its kerb and T into it.
    road_ns(CONN_X0, CONN_X1, CONN_Z0, CONN_Z1, "Conn")
    # The west verge is carved at the gate road for the same reason the east one
    # is carved at the cross streets: a pavement drawn straight across the mouth
    # of a side road is a kerb the road runs under, not a junction.
    #
    # ...and now at the estate's four streets, which is what turns this from a
    # footway with nothing on its west flank into a frontage. Before the estate
    # it was a single unbroken 809-stud slab from z 339 to the top of the map --
    # measurably the longest run of pavement in the world and the only one with
    # no crossing on it at all.
    for za, zb in carve((CONN_Z0, CONN_Z1), GATE_FULL + NORTHGATE_FULL + EST_CS_FULL):
        walks_ns(CONN_X0, CONN_X1, za, zb, CONN_WALK, "Conn", sides="west")
    # ...and at the north service road, which is a cross street in every way
    # that matters here -- it tees into the connector's east kerb at the top of
    # the map. It is not in CS_FULL because it is not one of the numbered cross
    # streets, and being left out of the carve is what laid the whole corner
    # square twice: once as this pavement running past, once as NorthSvc's own.
    for za, zb in carve((CONN_Z0, CONN_Z1), CS_FULL + NORTH_SVC_FULL):
        walks_ns(CONN_X0, CONN_X1, za, zb, CONN_WALK, "ConnE", sides="east")

    # Gate road: the only link between the town and the city, running east from
    # the town's street to the city connector. It *tees off* the town road at its
    # east kerb (ROAD_X1) -- it used to start at ROAD_X0 instead, which laid the
    # full 23-stud width of the town carriageway a second time, one asset on top
    # of another, and neither this file nor check_city could see it because the
    # town lives in a different .rbxmx.
    #
    # The first twelve studs east of the kerb cross the town's near sidewalk
    # (-64.5..-52.6). The tarmac runs under it rather than stopping short of it:
    # the sidewalk's top is at PAVING and the road's at GROUND, half a stud lower,
    # so the pavement wins the surface and the junction reads as a raised table
    # crossing. The gate road's own kerbs start at PROPERTY_X for the same reason
    # -- two sets of paving at the same height in the same place is the one thing
    # that would z-fight.
    #
    # The z band is the whole reason this needed moving. It used to run z 84..98
    # with paving out to 102, and there is a town house at x -42..2, z 88..122 --
    # walls, roof, partition, a bed in it. The road went through the bedroom.
    # Nothing could see it: check 7 reads City.rbxmx's streets against
    # City.rbxmx's buildings, and the house is in Town.rbxmx.
    #
    # The gap between the two is measured, not chosen. South of it the player's
    # own garden fence finishes at z=56.4; north of it that house begins at
    # z=88.0. Twenty-two studs of road and paving centred in that thirty-stud
    # window leaves 3.6 studs of lawn on the garden side and 6.0 on the town
    # side, and clears both of the street lamps standing on the near walk at
    # z 79.3..80.7 and z 83.3..84.7.
    road_ew(GATE_Z0, GATE_Z1, ROAD_X1, CONN_X0, "Gate", lift=GRASS_LIFT)
    walks_ew(GATE_Z0, GATE_Z1, PROPERTY_X, CONN_X0, GATE_WALK, "Gate")
    dashes_ew((GATE_Z0 + GATE_Z1) / 2, ROAD_X1, CONN_X0, [], "Gate",
              lift=GRASS_LIFT)

    # The southern link. Works cross street 1 carried west to the town road's
    # east kerb, on the same lift and for the same reason as the gate road: its
    # first twelve studs cross ground the town generator laid, and the town's
    # grass tops at exactly GROUND.
    #
    # It tees off at ROAD_X1, not ROAD_X0 -- see the gate road's note. The town's
    # own bottom band already runs east to that kerb over z -313..-290, so this
    # meets it along nineteen of its twenty-two studs and the junction is a
    # crossroads. The three-stud step at each side is real and is left alone: the
    # alternative is retyping W1's band as a number of its own, which is the
    # defect this file keeps being repaired for.
    #
    # The pavements start at PROPERTY_X rather than at the kerb, again like the
    # gate road, so the mouth of the junction stays open instead of being closed
    # by a pavement the road runs under. Unlike the gate road there is no town
    # sidewalk to run beneath here -- the near walk stops at z -290 where the
    # road used to turn -- so those 11.9 studs are bare tarmac by design.
    road_ew(SOUTHGATE_Z0, SOUTHGATE_Z1, ROAD_X1, AVE[0], "Southgate",
            lift=GRASS_LIFT)
    walks_ew(SOUTHGATE_Z0, SOUTHGATE_Z1, PROPERTY_X, AVE[0], SOUTHGATE_WALK,
             "Southgate")
    dashes_ew((SOUTHGATE_Z0 + SOUTHGATE_Z1) / 2, ROAD_X1, AVE[0], [], "Southgate",
              lift=GRASS_LIFT)

    # The northern link. The town's main street used to run north past the
    # library and stop in a field: wp_north_3 was a leaf on the route graph, so
    # the whole north end of town was a spur, and every journey between the two
    # halves of the world went out through the gate road, the southern link or
    # the green. This is the third mouth, and it is the one that turns the town's
    # west side into a loop -- gen_town.py brings its return road all the way up
    # the back and tees it into the same junction.
    #
    # Same construction as the other two and for the same reasons: it tees off
    # the town road at ROAD_X1 rather than ROAD_X0, so the town's own carriageway
    # is not laid a second time in a second asset; it is lifted by GRASS_LIFT
    # because its west half crosses ground the town generator laid at exactly
    # GROUND; and its pavements start at PROPERTY_X so the junction mouth stays
    # open instead of being closed by a kerb the road runs under.
    #
    # Unlike the other two it lands on nothing the city already has -- there is
    # no cross street on this flank at z 312 -- so the connector's west verge has
    # to be carved for it, which is what NORTHGATE_FULL is.
    road_ew(NORTHGATE_Z0, NORTHGATE_Z1, ROAD_X1, CONN_X0, "Northgate",
            lift=GRASS_LIFT)
    walks_ew(NORTHGATE_Z0, NORTHGATE_Z1, PROPERTY_X, CONN_X0, NORTHGATE_WALK,
             "Northgate")
    dashes_ew(NORTHGATE_MID, ROAD_X1, CONN_X0, [], "Northgate", lift=GRASS_LIFT)

    # Avenues: road carved at cross streets, sidewalks carved at the cross
    # streets' own sidewalks so they yield the corners. Avenue 3 is carved a
    # second time at the Circle, and its road and its pavement stop at different
    # radii -- the road at the carriageway's edge, the pavement eight studs
    # further out at the promenade's -- which is why the two are separate loops
    # rather than one.
    #
    # Three of them start 320 studs further south than the other three, in the
    # works -- so the span is `ave_z0(k)`, and the works streets join the carve
    # list. They join it unconditionally rather than only for the three that go
    # south: a gap outside the span carves nothing, and a conditional here is one
    # more place the set of works avenues is written down.
    for k, a in enumerate(AVE):
        at_circle = k == CIRCLE_AVE
        for za, zb in carve((ave_z0(k), AVE_Z1),
                            CS_ROAD + WCS_ROAD + ave_gaps(k)
                            + (CIRCLE_Z_ROAD if at_circle else [])):
            road_ns(a, a + AVE_W[k], za, zb, f"Ave{k}")
        for za, zb in carve((ave_z0(k), AVE_Z1),
                            CS_FULL + WCS_FULL + ave_gaps(k)
                            + (CIRCLE_Z_WALK if at_circle else [])):
            walks_ns(a, a + AVE_W[k], za, zb, AVE_WALK, f"Ave{k}")

    # Cross streets: carved at the avenues, and taking the corner squares --
    # which is why they are carved at AVE_ROAD and the avenues at CS_FULL.
    for j, c in enumerate(CS):
        at_circle = j == CIRCLE_CS
        for xa, xb in carve((CS_X0, CS_X1),
                            AVE_ROAD + (CIRCLE_X_ROAD if at_circle else [])):
            road_ew(c, c + CS_W[j], xa, xb, f"C{j}")
        for xa, xb in carve((CS_X0, CS_X1),
                            AVE_ROAD + (CIRCLE_X_WALK if at_circle else [])):
            walks_ew(c, c + CS_W[j], xa, xb, CS_WALK, f"C{j}",
                     sides="south" if j == CS_LAST else "both")

    # The four south streets. Same carriageway and same pavements as a cross
    # street, each carved at the avenues that actually reach it -- see
    # SOUTH_AVE_ROAD. They run from avenue 1's west kerb to avenue 6's east kerb,
    # so the carve leaves nothing at either end and all four terminate in a T.
    for j, c in enumerate(SOUTH_CS):
        for xa, xb in carve((WORKS_X0, WORKS_X1), SOUTH_AVE_ROAD[j]):
            road_ew(c, c + WCS_W, xa, xb, f"W{j}")
            walks_ew(c, c + WCS_W, xa, xb, CS_WALK, f"W{j}")

    # The west estate. Two avenues and four streets, on the works' dimensions,
    # carved against each other exactly the way the city grid is: the streets
    # take the corner squares (carved at the avenues' carriageway) and the
    # avenues yield the whole corridor (carved at the streets' full width), so
    # one and only one box owns every square and the junction tiles below fill
    # what both of them gave up.
    for _a in EST_AVE:
        for _za, _zb in carve((EST_AVE_Z0, EST_AVE_Z1), EST_CS_ROAD):
            road_ns(_a, _a + AVE_W_MAIN, _za, _zb, f"Est{_a:.0f}")
        for _za, _zb in carve((EST_AVE_Z0, EST_AVE_Z1), EST_CS_FULL):
            walks_ns(_a, _a + AVE_W_MAIN, _za, _zb, AVE_WALK, f"Est{_a:.0f}")
    for _j, _c in enumerate(EST_CS):
        for _xa, _xb in carve((EST_CS_X0, EST_CS_X1), EST_AVE_ROAD):
            road_ew(_c, _c + WCS_W, _xa, _xb, f"E{_j}")
            walks_ew(_c, _c + WCS_W, _xa, _xb, CS_WALK, f"E{_j}")
    for _a in EST_AVE:
        for _c in EST_CS:
            box(f"XE{_a:.0f}_{_c:.0f}",
                (_a, _a + AVE_W_MAIN, _c, _c + WCS_W, GROUND_BOTTOM, GROUND),
                TARMAC, ASPHALT)

    # The last cross street's north pavement, unbroken from end to end. No
    # avenue crosses it -- they all stop at this junction -- so carving it at the
    # avenues would leave six holes in the civic precinct's frontage.
    walks_ew(CS[CS_LAST], CS[CS_LAST] + CS_W[CS_LAST], CS_X0, PRECINCT_INNER_X1, CS_WALK,
             "CivicFront",
             sides="north")

    # Intersection tiles: the square both roads carved away, so every junction
    # is one flat piece of asphalt rather than a grass hole. All but one -- the
    # Circle stands on the avenue-3/cross-street-2 junction, so the tile there
    # would be a fourteen-stud square of tarmac in the middle of the island's
    # lawn, under the monument.
    for k, a in enumerate(AVE):
        for j, c in enumerate(CS):
            if k == CIRCLE_AVE and j == CIRCLE_CS:
                continue
            box(f"X{a:.0f}_{c:.0f}",
                (a, a + AVE_W[k], c, c + CS_W[j], GROUND_BOTTOM, GROUND),
                TARMAC, ASPHALT)
    # ...and the south streets' own, one per street per avenue that reaches it.
    for c in SOUTH_CS:
        for k in cs_aves(c):
            box(f"XW{AVE[k]:.0f}_{c:.0f}",
                (AVE[k], AVE[k] + AVE_W[k], c, c + WCS_W, GROUND_BOTTOM, GROUND),
                TARMAC, ASPHALT)

    # The Circle's own roadway, drawn with the streets because that is what it is
    # -- check 8 walks the street network as one graph and would strand a ring
    # laid anywhere else.
    #
    # The four facets on the spokes run the whole way out to the promenade radius
    # instead of stopping at the carriageway's, and the pavement ring skips those
    # four. That is the junction mouth: a pavement drawn across it would be a kerb
    # the avenue runs under, and a carriageway that stopped short of it would
    # leave eight studs of lawn between the ring and the road feeding it.
    def _spoke(i):
        return i % CIRCLE_SPOKE_EVERY == 0

    ring("CircleRoad", CIRCLE_ISLAND, CIRCLE_R_ROAD,
         GROUND_BOTTOM, GROUND - CIRCLE_SINK, TARMAC, ASPHALT,
         keep=lambda i: not _spoke(i))
    ring("CircleMouth", CIRCLE_ISLAND, CIRCLE_R_WALK,
         GROUND_BOTTOM, GROUND - CIRCLE_SINK, TARMAC, ASPHALT, keep=_spoke)
    ring("CircleKerbOut", CIRCLE_R_ROAD, CIRCLE_R_ROAD + KERB_WIDTH,
         GROUND - SLAB_SINK, PAVING, KERB_GREY, CONCRETE,
         keep=lambda i: not _spoke(i))
    ring("CircleWalk", CIRCLE_R_ROAD + KERB_WIDTH, CIRCLE_R_WALK,
         GROUND - SLAB_SINK, PAVING, PAVING_GREY, PEBBLE,
         keep=lambda i: not _spoke(i))

    # The precinct loop. Avenue 5 carried north through the precinct, and the
    # service road along the top of it. See "The precinct loop" at the head of
    # this file for why they exist and what they had to be measured against.
    #
    # The avenue's east side gets no pavement: x 793 is the precinct's own edge
    # and the bay is beyond it, so a pavement there would be a walk along the
    # back of nothing. Its west side is carved at the service road, for the same
    # reason the connector's verge is carved at the cross streets -- a pavement
    # drawn across the mouth of a side road is a kerb the road runs under.
    road_ns(PRECINCT_AVE_X0, PRECINCT_AVE_X1, CS[CS_LAST] + CS_W[CS_LAST], NORTH_ROAD_Z0,
            "PrecinctAve")
    # The walk stops a pavement's width short of the service road, not at its
    # kerb: the north-south sidewalk yields the corner square to the east-west
    # one (see the note on CS_FULL). Run to NORTH_ROAD_Z0 and the avenue's west
    # kerb and pavement both finish inside NorthSvc's south pavement, in its
    # plane, over the whole corner.
    walks_ns(PRECINCT_AVE_X0, PRECINCT_AVE_X1, CS[CS_LAST] + CS_W[CS_LAST],
             NORTH_ROAD_Z0 - CS_WALK, AVE_WALK, "PrecinctAve", sides="west")
    # From the connector's east kerb, not from its centre: the connector is
    # already tarmac at x 19..42, and starting this one inside it would lay two
    # carriageways in the same place. It stops at the avenue's east edge so the
    # corner is one junction rather than a road running past its own end.
    road_ew(NORTH_ROAD_Z0, NORTH_ROAD_Z1, CONN_X1, PRECINCT_AVE_X1, "NorthSvc")
    walks_ew(NORTH_ROAD_Z0, NORTH_ROAD_Z1, CONN_X1, PRECINCT_AVE_X1, CS_WALK,
             "NorthSvc", sides="south")

    # Centre lines.
    dashes_ns(CONN_MID, CONN_Z0, CONN_Z1, [], "Conn")
    for _a in EST_AVE:
        dashes_ns(_a + AVE_W_MAIN / 2, EST_AVE_Z0, EST_AVE_Z1, EST_CS_ROAD,
                  f"Est{_a:.0f}")
    for _j, _c in enumerate(EST_CS):
        dashes_ew(_c + WCS_W / 2, EST_CS_X0, EST_CS_X1, EST_AVE_ROAD, f"E{_j}")
    dashes_ns(PRECINCT_AVE_X0 + AVE_W[5] / 2, CS[CS_LAST] + CS_W[CS_LAST], NORTH_ROAD_Z0,
              [], "PrecinctAve")
    dashes_ew(NORTH_ROAD_Z0 + WCS_W / 2, CONN_X1, PRECINCT_AVE_X1, [], "NorthSvc")
    for k, a in enumerate(AVE):
        dashes_ns(a + AVE_W[k] / 2, ave_z0(k), AVE_Z1,
                  CS_ROAD + WCS_ROAD + ave_gaps(k)
                  + (CIRCLE_Z_WALK if k == CIRCLE_AVE else []),
                  f"Ave{k}")
    for j, c in enumerate(CS):
        dashes_ew(c + CS_W[j] / 2, CS_X0, CS_X1,
                  AVE_ROAD + (CIRCLE_X_WALK if j == CIRCLE_CS else []), f"C{j}")
    for j, c in enumerate(SOUTH_CS):
        dashes_ew(c + WCS_W / 2, WORKS_X0, WORKS_X1, SOUTH_AVE_ROAD[j], f"W{j}")

    # The Circle's own lane line, one dash per facet round the middle of the
    # carriageway. Named "Dash" like every other painted marking, which is how
    # check 8 knows to leave paint out of the street-connectivity graph.
    ring("CircleLaneDash", CIRCLE_ISLAND + CIRCLE_ROAD_W / 2 - 0.3,
         CIRCLE_ISLAND + CIRCLE_ROAD_W / 2 + 0.3,
         PAINT_BOTTOM, PAINT_TOP, ROAD_PAINT, SMOOTH,
         segs=CIRCLE_SEGS * 2, seam=0.0, keep=lambda i: i % 2 == 0)

    # Four zebra crossings, on the diagonals rather than on the spokes: a
    # crossing laid over a junction mouth is a crossing nobody can read, and the
    # diagonals are also where the island's four paths come out. Stripes run
    # along the direction of travel, which for a crossing of a ring road means
    # radially.
    for _q in range(4):
        _phi = 45.0 + _q * 90.0
        _t = math.radians(_phi)
        _tan = (-math.sin(_t), math.cos(_t))
        for _s in range(-3, 4):
            _off = _s * 4.4
            _mx, _mz = polar(CIRCLE_ISLAND + CIRCLE_ROAD_W / 2, _phi)
            rbxmx.spun_box(
                f"ZebraDash{_q}_{_s}",
                (_mx + _tan[0] * _off, (PAINT_OVER_BOTTOM + PAINT_OVER_TOP) / 2,
                 _mz + _tan[1] * _off),
                (CIRCLE_ROAD_W - 2.0, PAINT_OVER_TOP - PAINT_OVER_BOTTOM, 2.4),
                radial_yaw(_phi), ROAD_PAINT, SMOOTH)


# ---------------------------------------------------------------------------
# The Green, behind the player's plot
# ---------------------------------------------------------------------------

# No grass box. CityGround already lays the whole city in LAWN/GRASS topping at
# CITY_GRASS_TOP, so pulling the carriageway out *is* the grass -- and laying a
# second lawn of the same colour and height on top of the first is the coplanar
# pair the terrace lane already made once and had removed. This is the same
# note, in the second place that would have made the same mistake.
with group("BackGreen"):
    # The spur: the walk from the back gate to avenue 1. It goes straight,
    # which is more than the street it replaced managed.
    box("GreenPath", (GREEN_X0, GREEN_X1,
                      GREEN_PATH_Z - GREEN_PATH_HALF,
                      GREEN_PATH_Z + GREEN_PATH_HALF,
                      GROUND_BOTTOM, GROUND), PATH_STONE, PEBBLE)

    # The spine, running the length of the green. This is not decoration and it
    # is not symmetry: without it the connector at (30,60) -- 85 studs from the
    # spawn, just past the plot's north fence -- is a 203-stud walk out of the
    # front gate and round, and check 12 fails at 2.40. The street that used to
    # be here carried that route and taking it out took the route with it.
    #
    # Drawn in two pieces so the spur owns the crossing square. Two path slabs
    # laid across each other at the same height is the coplanar pair this file
    # has already been bitten by twice.
    _spine_x = GREEN_X0 + 12.0
    box("GreenSpineS", (_spine_x - GREEN_PATH_HALF, _spine_x + GREEN_PATH_HALF,
                        GREEN_Z0, GREEN_PATH_Z - GREEN_PATH_HALF,
                        GROUND_BOTTOM, GROUND), PATH_STONE, PEBBLE)
    box("GreenSpineN", (_spine_x - GREEN_PATH_HALF, _spine_x + GREEN_PATH_HALF,
                        GREEN_PATH_Z + GREEN_PATH_HALF, GREEN_Z1,
                        GROUND_BOTTOM, GROUND), PATH_STONE, PEBBLE)

    # Trees down the avenue side rather than scattered. A belt reads as a screen
    # between a garden and an arterial road, which is what it is for; scattered
    # trees read as an unmown field. The gap at the path is the point of it --
    # the player should be able to see the avenue from their own back gate and
    # know that is where they are walking to.
    _belt_x = GREEN_X1 - 6.0
    for _i, _tz in enumerate(range(int(GREEN_Z0) + 10, int(GREEN_Z1) - 8, 16)):
        if abs(_tz - GREEN_PATH_Z) < 12.0:
            continue
        # Alternating the belt in and out by seven studs: a single file of
        # evenly spaced trunks reads as fenceposts, not as woodland.
        tree(_belt_x - (0.0 if _i % 2 else 7.0), float(_tz), GROUND,
             height=14.0, spread=9.0)
    # A second, looser line against the fence, far enough off it that the rails
    # stay visible -- a fence you cannot see is a boundary the player does not
    # know they have.
    for _tz in range(int(GREEN_Z0) + 22, int(GREEN_Z1) - 8, 34):
        if abs(_tz - GREEN_PATH_Z) < 14.0:
            continue
        tree(GREEN_X0 + 8.0, float(_tz), GROUND, height=12.0, spread=7.5)

    # Facing each other across the path, at the gate end: somewhere to sit that
    # looks back at your own house is the cheapest way to make a green read as
    # somewhere rather than as the space between two things.
    bench(GREEN_X0 + 22.0, GREEN_PATH_Z - GREEN_PATH_HALF - 2.5, 1,
          label="GreenBenchS")
    bench(GREEN_X0 + 22.0, GREEN_PATH_Z + GREEN_PATH_HALF + 2.5, -1,
          label="GreenBenchN")


# ---------------------------------------------------------------------------
# The island in the middle of the Circle
# ---------------------------------------------------------------------------

# The whole point of building a roundabout instead of a junction: something worth
# looking at, in the middle, that can be seen from four streets at once. A ring
# road round an empty lawn would have been more work than the crossroads and no
# more interesting than it.
#
# Heights are all relative to PAVING, and every surface on the island is a
# different hundredth of a stud below the kerb, so the paths beat the lawn and
# the plaza beats both without any two tops ever landing in the same plane.
ISLE_PLAZA_R = 24.0
ISLE_LAWN_R = 36.6
ISLE_KERB_R = CIRCLE_ISLAND
ISLE_PATH_W = 8.0

# The fountain, as a ring of water inside a low basin wall, with the monument
# standing in the middle of it. Radii are solved outward from the monument's
# 14-stud plinth: its corners reach 9.9 studs, so the water starts at 13.
FOUNTAIN_R0, FOUNTAIN_R1 = 13.0, 16.0
FOUNTAIN_WALL = 2.0
FOUNTAIN_LIP = 3.0
FOUNTAIN_WATER = 2.2

# The monument. Five tapering stages of 34 studs on a plinth, topping out at
# roughly 186 -- taller than anything in the fade district and than the towers
# round the Circle itself, and still under the financial district's 195, which
# is the skyline's peak and should stay the skyline's peak.
MONUMENT_STAGES = 5
MONUMENT_STAGE_H = 34.0
MONUMENT_W0, MONUMENT_W1 = 9.0, 3.4
# The monument is a hundred and eighty-six studs of column, so every band on it
# except the first is sky -- it is a roofline, not a street, and it takes the
# roofline's white. See CROWN_NEON. It used to cycle the four shop neons, which
# put an amber-and-lime mast at the exact centre of downtown.
MONUMENT_NEON = dim(CROWN_NEON, NEON_ROOF_DIM)

with group("CircleIsland"):
    # Kerb first, because it is the edge everything else is measured against and
    # the only part of the island a driver sees.
    ring("IsleKerb", ISLE_KERB_R - 1.5, ISLE_KERB_R,
         GROUND - SLAB_SINK, PAVING, KERB_GREY, CONCRETE)
    ring("IsleLawn", ISLE_PLAZA_R, ISLE_LAWN_R,
         GROUND_BOTTOM, PAVING - 0.08, LAWN, GRASS)
    disc("IslePlaza", ISLE_PLAZA_R, GROUND_BOTTOM, PAVING - 0.04,
         PATH_STONE, PEBBLE)

    # Four paths off the diagonals, lining up with the four zebra crossings, so
    # there is a way onto the island that is drawn rather than implied.
    for _q in range(4):
        _phi = 45.0 + _q * 90.0
        _px, _pz = polar((ISLE_PLAZA_R + ISLE_LAWN_R) / 2, _phi)
        rbxmx.spun_box(f"IslePath{_q}",
                       (_px, (GROUND_BOTTOM + PAVING - 0.03) / 2, _pz),
                       (ISLE_LAWN_R - ISLE_PLAZA_R,
                        PAVING - 0.03 - GROUND_BOTTOM, ISLE_PATH_W),
                       radial_yaw(_phi), PATH_STONE, PEBBLE)

    # The fountain.
    ring("FountainWater", FOUNTAIN_R0, FOUNTAIN_R1,
         PAVING, PAVING + FOUNTAIN_WATER, WATER, SMOOTH,
         transparency=0.35, collide=False)
    ring("FountainWallOut", FOUNTAIN_R1, FOUNTAIN_R1 + FOUNTAIN_WALL,
         PAVING - 0.04, PAVING + FOUNTAIN_LIP, BANK_MARBLE, MARBLE)
    ring("FountainWallIn", FOUNTAIN_R0 - FOUNTAIN_WALL, FOUNTAIN_R0,
         PAVING - 0.04, PAVING + FOUNTAIN_LIP, BANK_MARBLE, MARBLE)

    # The monument, and the one thing in the city that is meant to be looked at
    # from a distance rather than walked into.
    _base = PAVING
    box("MonumentPlinth", (CIRCLE_X - 7.0, CIRCLE_X + 7.0,
                           CIRCLE_Z - 7.0, CIRCLE_Z + 7.0, _base - 0.04, _base + 5.0),
        CITY_HALL_MARBLE, MARBLE)
    box("MonumentStep", (CIRCLE_X - 5.5, CIRCLE_X + 5.5,
                         CIRCLE_Z - 5.5, CIRCLE_Z + 5.5, _base + 5.0, _base + 9.0),
        CITY_HALL_MARBLE, MARBLE)
    _y = _base + 9.0
    for _s in range(MONUMENT_STAGES):
        _w = MONUMENT_W0 + (MONUMENT_W1 - MONUMENT_W0) * _s / (MONUMENT_STAGES - 1)
        box(f"MonumentShaft{_s}",
            (CIRCLE_X - _w / 2, CIRCLE_X + _w / 2,
             CIRCLE_Z - _w / 2, CIRCLE_Z + _w / 2, _y, _y + MONUMENT_STAGE_H),
            CITY_HALL_MARBLE, MARBLE)
        # A neon collar at the joint, proud of the shaft so it reads as a band of
        # light rather than as a stripe of paint.
        box(f"MonumentBand{_s}",
            (CIRCLE_X - _w / 2 - 0.6, CIRCLE_X + _w / 2 + 0.6,
             CIRCLE_Z - _w / 2 - 0.6, CIRCLE_Z + _w / 2 + 0.6,
             _y + MONUMENT_STAGE_H - 1.2, _y + MONUMENT_STAGE_H),
            MONUMENT_NEON, NEON, collide=False)
        _y += MONUMENT_STAGE_H
    box("MonumentFinial",
        (CIRCLE_X - 1.4, CIRCLE_X + 1.4, CIRCLE_Z - 1.4, CIRCLE_Z + 1.4,
         _y, _y + 6.0), CITY_HALL_MARBLE, MARBLE)
    _finial = MONUMENT_NEON
    box("MonumentLight",
        (CIRCLE_X - 2.2, CIRCLE_X + 2.2, CIRCLE_Z - 2.2, CIRCLE_Z + 2.2,
         _y + 6.0, _y + 10.4), _finial, NEON, collide=False,
        children=point_light(_finial, 3.0, 90.0))

    # Palms off the diagonals so none of them stands in a path, and benches on
    # the axes looking out at the traffic.
    for _i in range(8):
        _px, _pz = polar(30.0, 22.5 + _i * 45.0)
        palm(_px, _pz, PAVING - 0.08, height=20.0 + (_i % 3) * 2.0,
             spread=12.0 + (_i % 2) * 2.0, lean=(_i % 3) - 1,
             label=f"IslePalm{_i}")
    for _dx, _dz, _toward in ((0, -1, -1), (0, 1, 1), (-1, 0, -1), (1, 0, 1)):
        bench(CIRCLE_X + _dx * 21.0, CIRCLE_Z + _dz * 21.0, _toward,
              label="IsleBench", floor=PAVING)

# Lamps round the promenade, on the facet centres that are not junction mouths,
# so the Circle is a lit place after dark and the twelve towers have something
# to stand above.
with group("CircleLamps"):
    for _i in range(8):
        _px, _pz = polar((CIRCLE_R_ROAD + CIRCLE_R_WALK) / 2, 30.0 + _i * 45.0)
        street_lamp(_px, _pz, 0, floor=PAVING, label=f"CircleLamp{_i}")


# ---------------------------------------------------------------------------
# Block layout
# ---------------------------------------------------------------------------

# What each of the 25 blocks holds. Columns are the five avenue bands (0 =
# between avenue 1 and 2, at the west edge of the grid), rows the five cross-
# street bands (0 = between CS 1 and 2, at the south).
#
# **The rows are a skyline, read from the south.** The financial district sits
# below this grid at z 60..200 with towers up to 195 studs, and the city has to
# come down off that rather than fall off it. So the two southern bands are the
# mid-rise fade district, the middle band is where the density breaks into the
# mall and walk-ups, and the two northern bands are houses. Standing on the
# connector at the south end and looking north, the city steps 195 -> 115 -> 67
# -> 34 -> 17, which is the whole reason the fade district exists.
#
#   sband4 (north, z 800..950):  HOUSE  HOUSE  HOUSE  HOUSE HOUSE
#   sband3       (z 650..800):   PARK   HOUSE  HOUSE  HOUSE ARENA
#   sband2       (z 500..650):   MALL   APT    OFFICE HOUSE SPORTS
#   sband1       (z 350..500):   FADE   CIRCUS CIRCUS FADE  HOUSE
#   sband0 (south, z 200..350):  MIXED  CIRCUS CIRCUS FADE  FADE
#
# Ten HOUSE blocks, and that number is a floor rather than a taste: each block
# holds six houses and check_city.py requires sixty of them with a door each,
# because a life needs somewhere to live and the game hands out addresses from
# this list. Take a HOUSE block away and the checker says so.
#
# **The four CIRCUS blocks are the four corners of the Circle**, and they are
# the corners they are because the Circle is centred on the avenue-3 /
# cross-street-2 junction. They were all FADE, which is why the Circle could be
# put here at all: no house was lost, and the skyline step the rest of this table
# is built on is kept -- a CIRCUS quadrant runs 100/163/100, which sits between
# the financial district's 195 and the fade district's 115 rather than beside it.
#
# This table is load-bearing for three things that are written down elsewhere in
# this file and cannot be checked from here, so change it with all three in view:
#
#   * `fade_office_band` sets storeys as `6 - sband * 2`. It is only meaningful
#     for sband 0 and 1. Putting FADE on any other band builds a tower with zero
#     or negative storeys -- which is legal arithmetic, draws an inside-out box,
#     and is exactly the defect this layout was rescued from: sixteen "offices"
#     standing 19 studs tall, shorter than the houses beside them, across the
#     whole north of the city.
#   * the `wp_cpark_*` waypoints are hard-coded at x 99..203, z 672..792, which
#     is block (band 0, sband 3). PARK has to stay there or the park's own
#     pathfinding lattice is stranded in somebody else's block.
#   * CIRCUS only works on the four blocks that touch the Circle's centre. It
#     lays its towers out by angle from that centre and clips nothing: put it on
#     a block the Circle does not touch and the arc is built somewhere else
#     entirely, most of it outside the block.
#   * OFFICES belongs on sband 2 and the skyline above is why. An office tower
#     tops out at 66.5 studs, which *is* the "67" in that row -- the number was
#     still being quoted after the role had been dropped out of this table
#     altogether, leaving `office_block` and `office_tower` written, correct and
#     unreachable, and the step they were the evidence for missing from the
#     city. It took the APT block rather than the one now marked SPORTS because
#     there were three APT blocks and only ever one of that one.
#   * ARENA takes a whole block and there is exactly one. It sits at [3][4]
#     because that is the block facing the back of the soccer stadium, which is
#     where the city's second big venue belongs and where six houses used to
#     look at a hundred thousand empty seats. Those six went to [1][4] -- two
#     cross streets south, into the low half of the city -- and that swap is
#     why the APT block that was there is gone. **The ten HOUSE blocks are a
#     floor, not a preference:** check_city counts sixty addresses and there is
#     no slack in the number, so ARENA could only ever have been paid for by
#     turning some other role into HOUSE in the same edit.
#   * SPORTS was GREEN -- an empty lot, `greenfield()` -- until the boxing gym
#     and the basketball/volleyball hall needed a home. It is the only block in
#     the ordinary grid this pair could go: everywhere else on this table is
#     already spoken for by the load-bearing reasons above, and the stadium
#     itself lives outside the grid entirely, in the headland (see `stadium()`).
ROLES = [
    ["MIXED", "CIRCUS", "CIRCUS", "FADE", "FADE"],
    ["FADE", "CIRCUS", "CIRCUS", "FADE", "HOUSE"],
    ["MALL", "APT", "OFFICES", "HOUSE", "SPORTS"],
    ["PARK", "HOUSE", "HOUSE", "HOUSE", "ARENA"],
    ["HOUSE", "HOUSE", "HOUSE", "HOUSE", "HOUSE"],
]


def block_bounds(band, sband):
    """(x0, x1, z0, z1) of the buildable interior of a block: between the two
    avenues' sidewalks and the two cross streets' sidewalks."""
    a0, a1 = AVE[band], AVE[band + 1]
    c0, c1 = CS[sband], CS[sband + 1]
    return a0 + AVE_W[band] + AVE_WALK, a1 - AVE_WALK, \
        c0 + CS_W[sband] + CS_WALK + 4.0, c1 - CS_WALK - 4.0


# ---------------------------------------------------------------------------
# Houses
# ---------------------------------------------------------------------------


def span(a, b):
    """Bounds in ascending order. `box` wants x0 < x1, and a fitting laid out
    from the front wall of an east-facing house counts *down*."""
    return (min(a, b), max(a, b))


def inward(ix0, ix1, front):
    """(front wall's inner face, back wall's inner face, sign of "into the room").

    This exists because the obvious spelling of it was wrong for four years and
    nothing could see it. The fittings used to start from
    `nx0, nx1 = (ix0, ix1) if front == "west" else (ix1, ix0)` and then add, so
    on an east-facing house `nx0 + 4` meant `ix1 + 4` -- four studs *past* the
    front wall. Every one of the thirty east-facing houses in the city had its
    bed and sofa standing out on the front path and its kitchen counter out on
    the back lawn. No check caught it: check 5 compares whole-model bounding
    boxes, so furniture outside a house just made the box bigger, and check 7
    only ever looks at walls.

    With a signed direction there is one arithmetic for both, and "four studs
    into the room from the front wall" is `fx + s * 4.0` whichever way the
    house faces.
    """
    if front == "west":
        return ix0, ix1, 1.0
    return ix1, ix0, -1.0


def lot_run(z0, z1, depths):
    """Lay a row of lots of the given depths down a block, returning [(a, b)].

    The leftover after the depths is split into a margin at each end and a
    wider gap between neighbours, so the row always fills the block exactly no
    matter what the plan says. That is the point: a plan is a list of depths and
    nothing else, and it cannot be edited into one that overruns the block or
    leaves a strip of bare ground at the north end.
    """
    n = len(depths)
    slack = (z1 - z0) - sum(depths)
    if slack < 0:
        raise ValueError(
            f"lot plan {depths} needs {sum(depths)} studs but the block is "
            f"only {z1 - z0}. Shorten a depth in HOUSE_PLANS."
        )
    # 2 margins + (n-1) gaps, with gap = margin * HOUSE_GAP_RATIO.
    margin = slack / (2.0 + HOUSE_GAP_RATIO * (n - 1))
    gap = margin * HOUSE_GAP_RATIO
    out = []
    cur = z0 + margin
    for d in depths:
        out.append((cur, cur + d))
        cur += d + gap
    return out


def house_roof(x0, x1, z0, z1, y, roof_color, shape):
    """The roof above a house's top ceiling: a slab, and then either a parapet
    or a stepped hip.

    A hip is stacked inset slabs rather than a wedge because a WedgePart is not
    a Part, and every geometry check in tools/check_city.py walks Parts -- a
    roof built out of wedges would be invisible to all ten of them. Three steps
    at this scale reads as a pitch from the street and stays checkable.
    """
    box("Roof", (x0, x1, z0, z1, y, y + SLAB), roof_color, SLATE)
    if shape == "flat":
        top = y + SLAB + HOUSE_PARAPET
        box("ParapetW", (x0, x0 + 1.0, z0, z1, y + SLAB, top), roof_color, SLATE)
        box("ParapetE", (x1 - 1.0, x1, z0, z1, y + SLAB, top), roof_color, SLATE)
        box("ParapetS", (x0 + 1.0, x1 - 1.0, z0, z0 + 1.0, y + SLAB, top),
            roof_color, SLATE)
        box("ParapetN", (x0 + 1.0, x1 - 1.0, z1 - 1.0, z1, y + SLAB, top),
            roof_color, SLATE)
        return
    base = y + SLAB
    for s in range(HOUSE_HIP_STEPS):
        inset = HOUSE_HIP_INSET * s
        box(f"Hip{s + 1}",
            (x0 + inset, x1 - inset, z0 + inset, z1 - inset,
             base + HOUSE_HIP_RISE * s, base + HOUSE_HIP_RISE * (s + 1)),
            roof_color, SLATE)


def house_upper(ix0, ix1, iz0, iz1, front, wall_color):
    """The second storey of a two-storey house: the stair, the floor it lands
    on, and a bedroom over the living room.

    The stair is the apartment's -- sixteen one-stud risers climbing south to
    north, a one-stud guard down the open side -- because FLOOR_2 is exactly
    sixteen studs above FLOOR_1 and a second flight geometry would be a second
    thing to get wrong. It stands against the back wall so the front door still
    opens into the living room rather than onto a staircase.
    """
    sz0 = iz0
    sz1 = sz0 + 16.0
    if front == "west":
        sx0, sx1 = ix1 - 6.0, ix1          # back wall is the east one
        guard_x0, guard_x1 = sx0 - 1.0, sx0
        side_slab = (ix0, guard_x0)
    else:
        sx0, sx1 = ix0, ix0 + 6.0
        guard_x0, guard_x1 = sx1, sx1 + 1.0
        side_slab = (guard_x1, ix1)

    with group("HouseUpperSlab"):
        # Two pieces around the stair void: everything north of the flight, and
        # the strip beside it. The void itself is what you climb through.
        box("SlabNorth", (ix0, ix1, sz1, iz1, CEIL_1, FLOOR_2),
            FLOOR_INDOOR, MARBLE)
        box("SlabSide", (side_slab[0], side_slab[1], sz0, sz1, CEIL_1, FLOOR_2),
            FLOOR_INDOOR, MARBLE)

    with group("HouseStair"):
        for i in range(16):
            zs = sz0 + i
            box(f"Step{i + 1}", (sx0, sx1, zs, zs + 1.0,
                                 FLOOR_1 - SLAB, FLOOR_1 + (i + 1.0)),
                PARTITION_PALE, CONCRETE)
        box("Guard", (guard_x0, guard_x1, sz0, sz1, FLOOR_2, CEIL_2),
            PARTITION_PALE, PLASTIC)
        box("Rail", (guard_x0 - 0.3, guard_x0, sz0, sz1,
                     FLOOR_1 + 3.0, FLOOR_2 + 3.0), STEEL, METAL, collide=False)

    with group("HouseUpperRoom"):
        nx0 = ix0 if front == "west" else ix1
        sign_x = 1.0 if front == "west" else -1.0
        box("Bed", (min(nx0, nx0 + sign_x * 8.0), max(nx0, nx0 + sign_x * 8.0),
                    iz1 - 9.0, iz1 - 3.0, FLOOR_2 + 0.8, FLOOR_2 + 1.6),
            (214, 218, 224), FABRIC)
        box("Wardrobe",
            (min(nx0 + sign_x * 1.0, nx0 + sign_x * 5.0),
             max(nx0 + sign_x * 1.0, nx0 + sign_x * 5.0),
             sz1 + 2.0, sz1 + 6.0, FLOOR_2, FLOOR_2 + 8.0),
            (150, 110, 80), WOOD)
        box("Rug", (min(nx0, nx0 + sign_x * 10.0), max(nx0, nx0 + sign_x * 10.0),
                    iz1 - 16.0, iz1 - 10.0, FLOOR_2, FLOOR_2 + 0.1),
            wall_color, FABRIC, collide=False)
        ceiling_light((ix0 + ix1) / 2, iz1 - 8.0, CEIL_2)


def house_shell(number, x0, x1, z0, z1, front, door_z, wall_color, roof_color,
                variant, storeys=1, roof="flat"):
    """Slab, roof, four walls (door in the front wall), back and side windows,
    numberplate, then the furniture of the given variant. `front` is "west"
    (door toward the west avenue) or "east".

    `storeys` is 1 or 2 and `roof` is "flat" or "hip". Together they are what
    stops a residential block reading as one building repeated: the walls of a
    two-storey house run to CEIL_2 rather than CEIL_1, so its eaves, its
    windows and its roof all sit sixteen studs higher than its neighbour's."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    d0, d1 = door_z - DOORWAY / 2, door_z + DOORWAY / 2
    eaves = CEIL_2 if storeys == 2 else CEIL_1

    with group(f"House_{number}"):
        with group("HouseStructure"):
            box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1), FLOOR_INDOOR, MARBLE)
            house_roof(x0, x1, z0, z1, eaves, roof_color, roof)
            if front == "west":
                wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, eaves), wall_color,
                     along="z", doors=((d0, d1),))
                wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, eaves), wall_color, along="z")
                glazing("BackWin", (ix1 + 0.4, x1 - 0.4, iz0 + 6.0, iz1 - 6.0,
                                   FLOOR_1 + 3.0, FLOOR_1 + 7.0), along="z", panes=3)
                box("Numberplate", (x0 - 0.6, x0 - 0.1, door_z - 1.5, door_z + 1.5,
                                    FLOOR_1 + 8.0, FLOOR_1 + 9.5),
                    TRIM_WHITE, SMOOTH, children=sign(str(number), "left",
                                                      color=(60, 66, 84), size=44))
                if storeys == 2:
                    glazing("UpperWin", (x0 + 0.4, ix0 - 0.4, iz0 + 6.0, iz1 - 6.0,
                                        FLOOR_2 + 3.0, FLOOR_2 + 7.0), along="z", panes=3)
            else:
                wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, eaves), wall_color,
                     along="z", doors=((d0, d1),))
                wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, eaves), wall_color, along="z")
                glazing("BackWin", (x0 + 0.4, ix0 - 0.4, iz0 + 6.0, iz1 - 6.0,
                                   FLOOR_1 + 3.0, FLOOR_1 + 7.0), along="z", panes=3)
                box("Numberplate", (x1 + 0.1, x1 + 0.6, door_z - 1.5, door_z + 1.5,
                                    FLOOR_1 + 8.0, FLOOR_1 + 9.5),
                    TRIM_WHITE, SMOOTH, children=sign(str(number), "right",
                                                      color=(60, 66, 84), size=44))
                if storeys == 2:
                    glazing("UpperWin", (ix1 + 0.4, x1 - 0.4, iz0 + 6.0, iz1 - 6.0,
                                        FLOOR_2 + 3.0, FLOOR_2 + 7.0), along="z", panes=3)
            wall("WallSouth", (x0, x1, z0, iz0, FLOOR_1, eaves), wall_color, along="x")
            wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, eaves), wall_color, along="x")
            glazing("SideWinS", (x0 + 5.0, x1 - 5.0, z0 + 0.4, iz0 - 0.4,
                                FLOOR_1 + 3.0, FLOOR_1 + 7.0), along="x", panes=2)
            glazing("SideWinN", (x0 + 5.0, x1 - 5.0, iz1 + 0.4, z1 - 0.4,
                                FLOOR_1 + 3.0, FLOOR_1 + 7.0), along="x", panes=2)

        if variant == "suburb":
            suburb_fittings(ix0, ix1, iz0, iz1, door_z, front)
        else:
            cottage_fittings(ix0, ix1, iz0, iz1, door_z, front)

        if storeys == 2:
            house_upper(ix0, ix1, iz0, iz1, front, wall_color)


def suburb_fittings(ix0, ix1, iz0, iz1, door_z, front):
    """Variant A: a partition splits a living half (sofa, table) from a bedroom
    half (bed, wardrobe), the way a real small house is divided."""
    fx, bx, s = inward(ix0, ix1, front)
    with group("HouseFittings"):
        wall("Partition", (*span(fx + s * 5.0, fx + s * 6.0), iz0 + 3.0,
                           iz1 - 3.0, FLOOR_1, CEIL_1),
             PARTITION_PALE, PLASTIC, along="z",
             doors=((door_z - 3.0, door_z + 3.0),))
        box("Sofa", (*span(fx + s * 4.0, fx + s * 8.0), iz1 - 9.0, iz1 - 5.0,
                     FLOOR_1 + 1.2, FLOOR_1 + 2.0), (140, 96, 80), FABRIC)
        desk(fx + s * 14.0, door_z + 2.0,
             FLOOR_1, side=("west" if front == "west" else "east"),
             width=4.0, depth=2.2, label="Table")
        box("Bed", (*span(fx + s * 5.0, fx + s * 13.0), iz0 + 4.0, iz0 + 10.0,
                    FLOOR_1 + 0.8, FLOOR_1 + 1.6), (214, 218, 224), FABRIC)
        box("Wardrobe", (*span(bx - s * 5.0, bx - s * 1.0), iz0 + 4.0, iz0 + 8.0,
                         FLOOR_1, FLOOR_1 + 8.0), (150, 110, 80), WOOD)
        ceiling_light(fx + s * 12.0, door_z, CEIL_1)


def cottage_fittings(ix0, ix1, iz0, iz1, door_z, front):
    """Variant B: open plan. A kitchen counter and stool sit by the back wall,
    the bed and sofa stand at the ends, and the table holds the middle."""
    fx, bx, s = inward(ix0, ix1, front)
    with group("HouseFittings"):
        box("Counter", (*span(bx - s * 8.0, bx - s * 4.0), iz0 + 3.0, iz0 + 8.0,
                        FLOOR_1 + 1.0, FLOOR_1 + 3.6), DESK_TOP, WOOD)
        box("Stool", (*span(bx - s * 7.0, bx - s * 5.0), iz0 + 9.0, iz0 + 10.0,
                      FLOOR_1 + 1.4, FLOOR_1 + 2.2), SEAT, FABRIC)
        box("Bed", (*span(fx + s * 3.0, fx + s * 10.0), iz1 - 9.0, iz1 - 3.0,
                    FLOOR_1 + 0.8, FLOOR_1 + 1.6), (214, 218, 224), FABRIC)
        box("Sofa", (*span(fx + s * 3.0, fx + s * 7.0), iz0 + 4.0, iz0 + 8.0,
                     FLOOR_1 + 1.2, FLOOR_1 + 2.0), (140, 96, 80), FABRIC)
        desk((ix0 + ix1) / 2, door_z, FLOOR_1, side=("west" if front == "west" else "east"),
             width=4.0, depth=2.2, label="Table")
        ceiling_light((ix0 + ix1) / 2, door_z, CEIL_1)


def house_block(band, sband, x0, x1, z0, z1, counter):
    """Two rows of three houses each, one row facing each avenue, with a green
    lane between them. Returns the next free house number.

    Every house on the block takes its depth from the block's plan and its
    width, setback, storeys and roof from the HOUSE_TIERS set its distance from
    the Circle selects, walked from an offset
    that moves with the block -- so the same six houses are never built twice
    and no two adjacent blocks share a rhythm. The count is fixed at six: the
    route checks want sixty homes across the ten residential blocks and there
    is no slack in that number.
    """
    n = counter
    plan_west, plan_east = HOUSE_PLANS[(band + sband) % len(HOUSE_PLANS)]
    runs = {"west": lot_run(z0, z1, plan_west), "east": lot_run(z0, z1, plan_east)}

    # Where the front gardens end, and therefore where the lane begins. Taken
    # from the deepest house actually placed rather than from a fixed 32, so a
    # wider style in a HOUSE_TIERS set cannot quietly grow a house across the
    # path -- which matters far more now that the inner tier reaches 42 studs.
    reach = {"west": 0.0, "east": 0.0}

    for i in range(3):
        for front in ("west", "east"):
            sz0, sz1 = runs[front][i]
            door_z = (sz0 + sz1) / 2
            styles = HOUSE_TIERS[house_tier(band, sband)]
            width, setback, storeys, roof = styles[
                (counter + i * 2 + (0 if front == "west" else 1))
                % len(styles)
            ]
            if front == "west":
                hx0 = x0 + setback
                hx1 = hx0 + width
            else:
                hx1 = x1 - setback
                hx0 = hx1 - width
            reach[front] = max(reach[front], setback + width)
            wall_color = HOUSE_WALLS[(n - 1) % len(HOUSE_WALLS)]
            roof_color = HOUSE_ROOFS[(n - 1) % len(HOUSE_ROOFS)]
            variant = "suburb" if (n % 2) == 1 else "cottage"
            house_shell(n, hx0, hx1, sz0, sz1, front, door_z, wall_color,
                        roof_color, variant, storeys=storeys, roof=roof)
            px = (hx0 + 2.0) if front == "west" else (hx1 - 2.0)
            place_point(f"suburb_{n}", px, door_z, FLOOR_1,
                        f"number {n}, on avenue {band + 1}")
            n += 1

    # The lane between the rows. There is no grass box here: CityGround already
    # lays the whole city in LAWN/GRASS topping at CITY_GRASS_TOP, and this used
    # to draw a second one of exactly the same colour, material and height on
    # top of it -- a coplanar pair the depth buffer had to choose between, which
    # check 10 never saw because it only compares one asset against another.
    lane_x0 = x0 + reach["west"]
    lane_x1 = x1 - reach["east"]
    midx = (lane_x0 + lane_x1) / 2
    box(f"LanePath{band}_{sband}",
        (midx - 1.0, midx + 1.0, z0 + 6.0, z1 - 6.0, GROUND_BOTTOM, GROUND),
        PATH_STONE, PEBBLE)
    for zt in (z0 + 12.0, z0 + 54.0, z1 - 12.0):
        tree(lane_x0 + 8.0, zt, GROUND, height=12.0, spread=8.0)
        tree(lane_x1 - 8.0, zt, GROUND, height=12.0, spread=8.0)
    return n


# ---------------------------------------------------------------------------
# Apartments
# ---------------------------------------------------------------------------

APT_DEPTH = 36.0
APT_FRONT = 48.0


def apartment(apt_no, x0, x1, z0, z1, front, wall_color):
    """A two-storey walk-up. The ground floor is an entrance lobby with the
    stair rising from its south-west corner; the whole upper floor is one open
    flat divided into four furnished zones, each its own household. The stair
    is the town workplace's stair: sixteen 1.0-rise steps, a one-stud guard on
    the east of the flight, and the walker climbs south to north and steps off
    onto the slab."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    mid_z = (z0 + z1) / 2

    # Door sits at the south end of the front wall so the walker lands beside
    # the stair bottom instead of at the top of a sixteen-stud climb.
    door_z = z0 + 6.0
    d0, d1 = door_z - DOORWAY / 2, door_z + DOORWAY / 2

    # The stair column: 6 wide (x), 16 long (z), rising north.
    sx0, sx1 = ix0, ix0 + 6.0
    sz0, sz1 = iz0 + 1.0, iz0 + 17.0
    guard_x0, guard_x1 = sx1, sx1 + 1.0

    with group(f"Apt_{apt_no}"):
        with group("AptStructure"):
            box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1), FLOOR_INDOOR, MARBLE)
            box("Roof", (x0, x1, z0, z1, CEIL_2, CEIL_2 + SLAB), ROOF_GREY, SLATE)
            if front == "west":
                wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, CEIL_2), wall_color,
                     along="z", doors=((d0, d1),))
                wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, CEIL_2), wall_color, along="z")
                glazing("FrontGlaze", (x0 + 0.4, ix0 - 0.4, iz0 + 19.0, iz1 - 3.0,
                                      FLOOR_2 + 3.5, FLOOR_2 + 10.5), along="z", panes=6)
                glazing("BackGlaze", (ix1 + 0.4, x1 - 0.4, iz0 + 3.0, iz1 - 3.0,
                                     FLOOR_2 + 3.5, FLOOR_2 + 10.5), along="z", panes=6)
            else:
                wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, CEIL_2), wall_color,
                     along="z", doors=((d0, d1),))
                wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, CEIL_2), wall_color, along="z")
                glazing("FrontGlaze", (ix1 + 0.4, x1 - 0.4, iz0 + 19.0, iz1 - 3.0,
                                      FLOOR_2 + 3.5, FLOOR_2 + 10.5), along="z", panes=6)
                glazing("BackGlaze", (x0 + 0.4, ix0 - 0.4, iz0 + 3.0, iz1 - 3.0,
                                     FLOOR_2 + 3.5, FLOOR_2 + 10.5), along="z", panes=6)
            wall("WallSouth", (x0, x1, z0, iz0, FLOOR_1, CEIL_2), wall_color, along="x")
            wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, CEIL_2), wall_color, along="x")

            # A painted band under the parapet so the roof reads as a building's
            # cap rather than as a slab left on top.
            box("Band", (x0, x1, z0, z0 + 1.0, CEIL_1 + SLAB - 2.5, CEIL_2),
                APT_BAND, CONCRETE)
            box("BandN", (x0, x1, z1 - 1.0, z1, CEIL_1 + SLAB - 2.5, CEIL_2),
                APT_BAND, CONCRETE)

        with group("AptUpperSlab"):
            # Two pieces around the stair void. The void is exactly the stair
            # column; everything else is walkable upper floor.
            box("SlabNorth", (ix0, ix1, sz1, iz1, CEIL_1, FLOOR_2),
                FLOOR_INDOOR, MARBLE)
            box("SlabEast", (guard_x1, ix1, sz0, sz1, CEIL_1, FLOOR_2),
                FLOOR_INDOOR, MARBLE)

        with group("AptStair"):
            for i in range(16):
                z0s = sz0 + i
                box(f"Step{i + 1}", (sx0, sx1, z0s, z0s + 1.0,
                                     FLOOR_1 - SLAB, FLOOR_1 + (i + 1)),
                    PARTITION_PALE, CONCRETE)
            box("Guard", (guard_x0, guard_x1, sz0, sz1, FLOOR_2, CEIL_2),
                PARTITION_PALE, PLASTIC)
            box("Rail", (guard_x0 - 0.3, guard_x0, sz0, sz1,
                         FLOOR_1 + 3.0, FLOOR_2 + 3.0), STEEL, METAL, collide=False)

        with group("AptLobby"):
            box("Desk", (ix0 + 9.0, ix0 + 14.0, iz0 + 2.0, iz0 + 5.0,
                         FLOOR_1, FLOOR_1 + 3.0), DESK_TOP, WOOD)
            box("Sofa", (ix0 + 18.0, ix0 + 24.0, iz0 + 3.0, iz0 + 6.0,
                         FLOOR_1 + 1.2, FLOOR_1 + 2.0), (140, 96, 80), FABRIC)
            ceiling_light(ix0 + 20.0, iz1 - 6.0, CEIL_1)

        # Four furnished zones on the open upper floor. Each has a bed or a
        # sofa and its own place point, so it reads and works as a separate
        # household.
        with group("AptUpperWest"):
            box("SofaA", (ix0 + 2.0, ix0 + 8.0, iz0 + 20.0, iz0 + 26.0,
                          FLOOR_2 + 1.2, FLOOR_2 + 2.0), (140, 96, 80), FABRIC)
            box("TableA", (ix0 + 5.0, ix0 + 9.0, iz0 + 30.0, iz0 + 33.0,
                           FLOOR_2 + 1.5, FLOOR_2 + 1.8), DESK_TOP, WOOD)
            box("BedA", (ix0 + 3.0, ix0 + 10.0, iz0 + 36.0, iz0 + 42.0,
                         FLOOR_2 + 0.8, FLOOR_2 + 1.6), (214, 218, 224), FABRIC)
        with group("AptUpperEast"):
            box("SofaB", (ix1 - 8.0, ix1 - 2.0, iz0 + 20.0, iz0 + 26.0,
                          FLOOR_2 + 1.2, FLOOR_2 + 2.0), (120, 140, 110), FABRIC)
            box("BedB", (ix1 - 11.0, ix1 - 3.0, iz0 + 30.0, iz0 + 37.0,
                         FLOOR_2 + 0.8, FLOOR_2 + 1.6), (214, 218, 224), FABRIC)
            box("DeskB", (ix1 - 10.0, ix1 - 6.0, iz0 + 40.0, iz0 + 43.0,
                          FLOOR_2 + 1.5, FLOOR_2 + 1.8), DESK_TOP, WOOD)
        with group("AptUpperSouth"):
            box("Dining", (ix0 + 12.0, ix0 + 17.0, iz0 + 4.0, iz0 + 7.0,
                           FLOOR_2 + 1.5, FLOOR_2 + 1.8), DESK_TOP, WOOD)
            box("Seat", (ix0 + 9.0, ix0 + 10.5, iz0 + 8.0, iz0 + 9.5,
                         FLOOR_2 + 1.5, FLOOR_2 + 2.3), SEAT, FABRIC)
            box("Seat2", (ix0 + 18.5, ix0 + 20.0, iz0 + 8.0, iz0 + 9.5,
                          FLOOR_2 + 1.5, FLOOR_2 + 2.3), SEAT, FABRIC)
        with group("AptUpperStudy"):
            box("DeskC", (ix1 - 9.0, ix1 - 5.0, iz0 + 4.0, iz0 + 7.0,
                          FLOOR_2 + 1.5, FLOOR_2 + 1.8), DESK_TOP, WOOD)
            box("ShelfC", (ix1 - 6.0, ix1 - 2.0, iz0 + 9.0, iz0 + 13.0,
                           FLOOR_2, FLOOR_2 + 7.0), SHELF, METAL)

    # Place points: the entrance lobby plus the four households.
    px = (x0 + 2.0) if front == "west" else (x1 - 2.0)
    place_point(f"apt_{apt_no}_entrance", px, door_z + 3.0, FLOOR_1,
                f"apartment block {apt_no} entrance")
    for zone, zz, xx in (
        ("1", iz0 + 30.0, ix0 + 6.0),
        ("2", iz0 + 30.0, ix1 - 6.0),
        ("3", iz0 + 6.0, ix0 + 14.0),
        ("4", iz0 + 6.0, ix1 - 6.0),
    ):
        place_point(f"apt_{apt_no}_{zone}", xx, zz, FLOOR_2,
                    f"apartment {apt_no}, home {zone}")


def apartment_block(band, sband, x0, x1, z0, z1, counter):
    """Two walk-ups, one against the south end of the block facing the west
    avenue, one against the north end facing the east avenue, with the garden
    between them. Returns the next free apartment number."""
    n = counter
    # South-west building, front (west) wall on the west sidewalk.
    apartment(n, x0, x0 + APT_DEPTH, z0, z0 + APT_FRONT, "west",
              APT_WALLS[(n - 1) % len(APT_WALLS)])
    n += 1
    # North-east building, front (east) wall on the east sidewalk.
    apartment(n, x1 - APT_DEPTH, x1, z1 - APT_FRONT, z1, "east",
              APT_WALLS[(n - 1) % len(APT_WALLS)])
    n += 1

    # The garden between them: trees on the grass CityGround already lays.
    # There was a second grass box here, the same colour and material topping at
    # the same CITY_GRASS_TOP as the ground beneath it -- see the note in
    # house_block() for why a coplanar pair like that went unnoticed.
    lane_x0 = x0 + APT_DEPTH
    lane_x1 = x1 - APT_DEPTH
    mid_z = (z0 + z1) / 2
    for zt in (z0 + 6.0, mid_z, z1 - 6.0):
        tree(lane_x0 + 5.0, zt, GROUND, height=12.0, spread=8.0)
        tree(lane_x1 - 5.0, zt, GROUND, height=12.0, spread=8.0)
    return n


# ---------------------------------------------------------------------------
# Mall
# ---------------------------------------------------------------------------

MALL_X = 96.0
MALL_Z = 100.0
MALL_CORRIDOR = 12.0
# The reveal between two shop units. Two studs is what leaves a shadow line
# between neighbouring shopfronts; without it the row glazes over into one
# continuous window and the mall reads as a single shop the length of the
# building.
MALL_UNIT_GAP = 2.0


def mall_shop(pid, label, x0, x1, z0, z1, front, kind):
    """One shop opening onto the mall corridor. `front` is "north" (south of
    the corridor) or "south" (north of the corridor)."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    cx = (x0 + x1) / 2
    # crc32 rather than hash(): Python randomises string hashing per process, so
    # `hash(pid)` gave the mall a different set of shopfront colours on every run
    # and made City.rbxmx the one generated asset that could not be diffed --
    # regenerate it twice and git reports a change with no change in it. Any
    # stable scatter would do; crc32 is in the standard library and will not move.
    wall_color = STORE_WALLS[zlib.crc32(pid.encode()) % len(STORE_WALLS)]

    with group(f"MallShop_{pid}"):
        # No slab. The mall pours one for its whole footprint, in this exact
        # colour and material, and a unit that poured its own laid a second
        # floor in the first one's plane -- eight shops, fifty studs of flicker
        # each. A shop unit is a partition and a shopfront inside a building,
        # not a building.
        box("Roof", (x0, x1, z0, z1, CEIL_1, CEIL_1 + SLAB), ROOF_GREY, SLATE)
        wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, CEIL_1), wall_color, along="z")
        wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, CEIL_1), wall_color, along="z")
        if front == "north":
            # Shop north of the corridor: front wall faces south (z0).
            wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, CEIL_1), wall_color, along="x")
            wall("WallFront", (x0, x1, z0, iz0, FLOOR_1, CEIL_1), wall_color,
                 along="x", doors=((cx - 4.0, cx + 4.0),))
            glazing("Front", (x0 + 1.5, x1 - 1.5, iz0 + 0.4, z1 - 0.4,
                              FLOOR_1 + 1.5, FLOOR_1 + 9.5), along="x", panes=3)
        else:
            wall("WallSouth", (x0, x1, z0, iz0, FLOOR_1, CEIL_1), wall_color, along="x")
            wall("WallFront", (x0, x1, iz1, z1, FLOOR_1, CEIL_1), wall_color,
                 along="x", doors=((cx - 4.0, cx + 4.0),))
            glazing("Front", (x0 + 1.5, x1 - 1.5, iz1 + 0.4, z1 - 0.4,
                              FLOOR_1 + 1.5, FLOOR_1 + 9.5), along="x", panes=3)

        # Counter and sign sized off the unit rather than typed at 12 and 16
        # studs. Those two numbers were measured in a 22-stud unit and were the
        # only thing stopping the mall from holding more shops: the moment the
        # row is solved out of the corridor instead of stepped at a fixed pitch,
        # a narrower unit gets a counter wider than its own interior and a
        # nameplate that overhangs its neighbour's shopfront. Neither is an
        # error anything checks for -- they are legal boxes in the wrong place.
        counter_half = min(6.0, (x1 - x0) / 2 - 3.0)
        sign_half = min(8.0, (x1 - x0) / 2 - 1.0)
        box("Counter", (cx - counter_half, cx + counter_half, iz0 + 2.0, iz0 + 5.0,
                        FLOOR_1, FLOOR_1 + 3.0), DESK_TOP, WOOD)
        box("Gondola", (ix0 + 3.0, ix0 + 6.0, iz0 + 8.0, iz1 - 4.0,
                        FLOOR_1, FLOOR_1 + 7.5), SHELF, METAL)
        box("Stock", (ix0 + 3.2, ix0 + 5.8, iz0 + 8.4, iz1 - 4.4,
                      FLOOR_1 + 1.8, FLOOR_1 + 3.4), STOCK, PLANKS, collide=False)
        box("Sign", (cx - sign_half, cx + sign_half, iz0 + 0.4, iz0 + 1.4,
                     FLOOR_1 + 11.0, FLOOR_1 + 13.0), wall_color, SMOOTH,
            children=sign(label, "front" if front == "north" else "back",
                          color=(250, 246, 234), size=52))
        ceiling_light(cx, (z0 + z1) / 2, CEIL_1)


def mall(band, sband, x0, x1, z0, z1):
    """A covered shopping mall: a 12-stud corridor running east-west between a
    row of four shops on each side, with entrances on the south (facing the
    cross street) and the north."""
    cx0 = x0 + 3.0
    cx1 = x1 - 3.0
    mid_z = (z0 + z1) / 2
    corr_z0, corr_z1 = mid_z - MALL_CORRIDOR / 2, mid_z + MALL_CORRIDOR / 2

    # Six units a side, not four, and the last two on each side came off the
    # main street.
    #
    # That street ran nineteen shopfronts down eight hundred studs of frontage
    # at a constant thirty-stud pitch, three to a band, six bands running, and
    # the effect of that from the pavement is a wall with doors in it -- there
    # was no room left for a tree, a bench or a gap, because the widths and the
    # minimum gap between them added up to exactly the length of the street.
    # Four shops moving indoors is what bought the room, and the four that moved
    # are the four a mall is actually made of: books, records, toys and
    # electronics are mall tenants everywhere, and none of them wants a kerb.
    #
    # The place ids do not change. `toy_store`, `music_store`, `bookstore` and
    # `electronics` are all `placeId`s in Jobs.luau -- the job finds the shop by
    # id and does not care which building it is in.
    north_shops = [
        ("mall_jewelry", "AURUM JEWELERS"),
        ("mall_shoes", "STEPPER SHOES"),
        ("mall_sports", "SPORTZONE"),
        ("mall_gaming", "PIXEL PLAY"),
        ("bookstore", "PAGES & PRESS"),
        ("music_store", "FREQUENCY"),
    ]
    south_shops = [
        ("optometrist", "SIGHT & SOUND"),
        ("pet_shop", "TREATS & TAILS"),
        ("mall_kids", "KIDDIE KORNER"),
        ("mall_foodcourt", "THE FOODCOURT"),
        ("toy_store", "PLAYPEN"),
        ("electronics", "VOLT ELECTRONICS"),
    ]

    with group("Mall"):
        box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1), FLOOR_INDOOR, MARBLE)
        box("Roof", (x0, x1, z0, z1, CEIL_1, CEIL_1 + SLAB), ROOF_GREY, SLATE)
        wall("WallWest", (x0, x0 + WALL, z0, z1, FLOOR_1, CEIL_1), (206, 202, 194),
             along="z")
        wall("WallEast", (x1 - WALL, x1, z0, z1, FLOOR_1, CEIL_1), (206, 202, 194),
             along="z")
        # South main entrance and north entrance, both on the corridor line.
        e0, e1 = (x0 + x1) / 2 - 6.0, (x0 + x1) / 2 + 6.0
        wall("WallSouth", (x0, x1, z0, z0 + WALL, FLOOR_1, CEIL_1), (206, 202, 194),
             along="x", doors=((e0, e1),))
        wall("WallNorth", (x0, x1, z1 - WALL, z1, FLOOR_1, CEIL_1), (206, 202, 194),
             along="x", doors=((e0, e1),))
        # The corridor's own floor, and the inner walls between shops and
        # corridor are the shops' front walls (glazed), so only the corridor
        # slab needs laying.
        box("Corridor", (x0 + WALL, x1 - WALL, corr_z0, corr_z1,
                         FLOOR_1, FLOOR_1 + FLOOR_INLAY), PATH_STONE, MARBLE)

        # The pitch is solved out of the corridor, not stepped at a typed 24.
        # A typed pitch fits the row it was measured in and hangs the last unit
        # out of the end wall of the next one -- the same defect `works_depot`
        # writes about, and here it would be a shopfront standing in the mall's
        # west wall the first time a shop was added.
        for shops, (uz0, uz1), face, ppz in (
            (north_shops, (corr_z1, z1 - WALL), "south", corr_z1 + 6.0),
            (south_shops, (z0 + WALL, corr_z0), "north", corr_z0 - 6.0),
        ):
            pitch = (cx1 - cx0) / len(shops)
            for i, (pid, label) in enumerate(shops):
                sx0 = cx0 + i * pitch
                mall_shop(pid, label, sx0, sx0 + pitch - MALL_UNIT_GAP,
                          uz0, uz1, face, "shop")
                place_point(pid, sx0 + (pitch - MALL_UNIT_GAP) / 2, ppz, FLOOR_1,
                            f"the {label.lower()}, at the counter")

        # Benches down the corridor.
        for x in (cx0 + 20.0, cx0 + 44.0, cx0 + 68.0):
            box(f"Bench{x:.0f}", (x, x + 5.0, mid_z - 3.0, mid_z - 1.6,
                                  FLOOR_1 + 1.5, FLOOR_1 + 1.85), DESK_TOP, WOOD)

    mall_cx = (x0 + x1) / 2
    place_point("mall_entrance", mall_cx, z0 + 1.0, FLOOR_1,
                "the mall entrance, under the awning")
    place_point("wp_mall_corridor", mall_cx, mid_z, FLOOR_1,
                "the mall corridor")


# ---------------------------------------------------------------------------
# City park
# ---------------------------------------------------------------------------


def city_park(band, sband, x0, x1, z0, z1):
    """A square of green with a pond, a fountain, paths and trees."""
    with group("CityPark"):
        # One step over CityGround rather than level with it. The block under
        # this is already LAWN/GRASS at exactly CITY_GRASS_TOP, so a park lawn
        # drawn at that height is two hundred studs of grass with no way to
        # decide which copy is in front. The park wins, and has to: it is the
        # thing the paths and the pond are measured from.
        box("Park", (x0, x1, z0, z1, GROUND_BOTTOM, CITY_GRASS_TOP + GRASS_LIFT),
            LAWN, GRASS)
        # Pond in the west: a blue pool with a sandy rim.
        pond_x0, pond_x1 = x0 + 3.0, x0 + 20.0
        pond_z0, pond_z1 = z0 + 3.0, z0 + 16.0
        box("Pond", (pond_x0, pond_x1, pond_z0, pond_z1,
                     GROUND - 0.3, GROUND), WATER, SMOOTH, collide=False)
        box("PondRim", (pond_x0 - 0.5, pond_x0 + 0.5, pond_z0 - 0.5, pond_z1 + 0.5,
                        GROUND, GROUND + 0.35), SAND, PEBBLE)
        box("PondRim2", (pond_x1 - 0.5, pond_x1 + 0.5, pond_z0 - 0.5, pond_z1 + 0.5,
                         GROUND, GROUND + 0.35), SAND, PEBBLE)
        box("PondRim3", (pond_x0 - 0.5, pond_x1 + 0.5, pond_z0 - 0.5, pond_z0 + 0.5,
                         GROUND, GROUND + 0.35), SAND, PEBBLE)
        box("PondRim4", (pond_x0 - 0.5, pond_x1 + 0.5, pond_z1 - 0.5, pond_z1 + 0.5,
                         GROUND, GROUND + 0.35), SAND, PEBBLE)

        # Fountain in the middle: a round basin with a spout, tagged as the
        # park's place point.
        fx, fz = (x0 + x1) / 2, (z0 + z1) / 2
        box("Basin", (fx - 7.0, fx + 7.0, fz - 7.0, fz + 7.0,
                      GROUND - 0.2, GROUND + 0.5), (196, 190, 180), CONCRETE)
        box("Spout", (fx - 0.7, fx + 0.7, fz - 0.7, fz + 0.7,
                      GROUND + 0.5, GROUND + 5.0), (196, 190, 180), CONCRETE)
        box("Water", (fx - 4.0, fx + 4.0, fz - 4.0, fz + 4.0,
                      GROUND + 0.55, GROUND + 0.8), WATER, SMOOTH, collide=False)
        # Paths from the four entrances to the fountain.
        box("PathN", (fx - 2.0, fx + 2.0, z1 - 6.0, fz + 7.0,
                      GROUND_BOTTOM, GROUND), PATH_STONE, PEBBLE)
        box("PathS", (fx - 2.0, fx + 2.0, fz - 7.0, z0 + 6.0,
                      GROUND_BOTTOM, GROUND), PATH_STONE, PEBBLE)
        box("PathW", (x0 + 6.0, fx - 7.0, fz - 2.0, fz + 2.0,
                      GROUND_BOTTOM, GROUND), PATH_STONE, PEBBLE)

        for tx, tz in ((x0 + 8.0, z1 - 8.0), (x1 - 8.0, z1 - 8.0),
                       (x0 + 8.0, z0 + 8.0), (x1 - 8.0, z0 + 8.0),
                       (x1 - 10.0, fz)):
            tree(tx, tz, GROUND, height=13.0, spread=8.0)
        bench(fx - 11.0, fz, 1)
        bench(fx + 11.0, fz, -1)

    # Place point at the south entrance so it chains to the cross street waypoint.
    place_point("city_park", fx, z0 + 6.0, GROUND, "the park, by the south entrance")


# ---------------------------------------------------------------------------
# Office towers
# ---------------------------------------------------------------------------


def office_tower(office_no, x0, x1, z0, z1):
    """A four-storey glass tower whose ground floor is a working office. The
    storeys above are glazed curtain wall -- scenery for the skyline, the same
    reason a real city has towers you cannot get into."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    cx = (x0 + x1) / 2
    tower_top = CEIL_2 + SLAB + 2 * (STOREY + SLAB)

    with group(f"OfficeTower_{office_no}"):
        box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1), FLOOR_INDOOR, MARBLE)
        box("Roof", (x0, x1, z0, z1, tower_top, tower_top + SLAB), (72, 76, 82), CONCRETE)
        # Corner columns carry the glass curtain wall.
        for xx, zz in ((x0, z0), (x1 - 1.0, z0), (x0, z1 - 1.0), (x1 - 1.0, z1 - 1.0)):
            box(f"Column{xx:.0f}_{zz:.0f}",
                (xx, xx + 1.0, zz, zz + 1.0, FLOOR_1, tower_top),
                OFFICE_FRAME, CONCRETE)
        # Glass bands, one storey each.
        for i, gy in enumerate((FLOOR_1, FLOOR_2, CEIL_2 + SLAB,
                                CEIL_2 + SLAB + STOREY + SLAB)):
            box(f"Glass{i + 1}", (x0 + 1.0, x1 - 1.0, z0 + 1.0, z1 - 1.0,
                                  gy, gy + STOREY - 1.0),
                OFFICE_GLASS, GLASS, transparency=0.5, collide=False)
        # Ground floor office, fronting the plaza (south).
        wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, CEIL_1), OFFICE_LOBBY, along="x")
        wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, CEIL_1), OFFICE_LOBBY, along="z")
        wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, CEIL_1), OFFICE_LOBBY, along="z")
        wall("WallFront", (x0, x1, z0, iz0, FLOOR_1, CEIL_1), OFFICE_LOBBY,
             along="x", doors=((cx - DOORWAY / 2, cx + DOORWAY / 2),))
        glazing("LobbyGlaze", (x0 + 1.5, x1 - 1.5, iz0 + 0.4, z1 - 0.4,
                               FLOOR_1 + 1.5, FLOOR_1 + 9.5), along="x", panes=4)
        box("Reception", (ix0 + 4.0, ix0 + 10.0, iz1 - 7.0, iz1 - 3.0,
                          FLOOR_1, FLOOR_1 + 3.0), DESK_TOP, WOOD)
        box("Sofa", (ix1 - 9.0, ix1 - 4.0, iz1 - 7.0, iz1 - 3.0,
                     FLOOR_1 + 1.2, FLOOR_1 + 2.0), (120, 140, 110), FABRIC)
        ceiling_light(cx, (z0 + z1) / 2, CEIL_1)
        box("TowerSign", (cx - 9.0, cx + 9.0, z0 - 1.6, z0 - 0.6,
                          FLOOR_1 + 13.0, FLOOR_1 + 15.0), OFFICE_FRAME, SMOOTH,
            children=sign(f"TOWER {office_no}", "front", color=(250, 246, 234), size=60))

    place_point(f"office_{office_no}", cx, z0 + 2.0, FLOOR_1,
                f"tower {office_no}, the ground-floor office")


# ---------------------------------------------------------------------------
# Shaped towers
# ---------------------------------------------------------------------------
#
# The tower builder these replaced extruded a rectangle, put a setback and an
# antenna on it and stopped. That is one building, and at the density downtown
# is going to it reads as twenty copies of one building -- the storey count
# varies and the silhouette does not, so the whole skyline is the same tower at
# eight heights.
#
# These do not extrude. A shaft here is `TOWER_SEGS` plates stacked up, and the
# *width and yaw of a plate are functions of its own height* -- so the profile
# curves and the tower turns as it rises. That is the entire idea, and it is
# where the variety comes from: a tower that turns two degrees a plate is a
# different building from one that does not, and it costs the same parts.
#
# Four styles, and they are four presets of the same two functions rather than
# four builders, because four builders is four places for the crown to stop
# matching the shaft it stands on. See TOWER_STYLES.
#
# **Everything stays inside its own footprint.** A square plate spun 45 degrees
# measures w*sqrt(2) across, so a shaft that twists cannot also fill its block:
# it is inset to whatever the widest yaw it actually reaches needs, and
# `tower_fit` asserts that rather than trusting the caller. Without it the
# corner of plate 12 hangs over the sidewalk -- and check_city reads a rotated
# part's true oriented box (see the SAT note on check 5), so it would be caught,
# but as an overlap between two towers a hundred studs apart rather than as the
# inset being wrong here.
TOWER_SEGS = 16          # plates per shaft. 16 reads as a smooth turn from the
                         # street and keeps a tall tower under 60 parts.
                         # Safe range: 10 .. 28.
TOWER_BAND_H = 1.1       # the slab band capping each plate. This is the
                         # horizontal line that makes a glass shaft read as
                         # floors instead of as one very tall pane, and it is
                         # the single cheapest thing on this list.
TOWER_PODIUM_H = 20.0    # the base storeys, below the first shaft plate
TOWER_ROOF = (52, 56, 64)
TOWER_MULLION = (104, 112, 126)   # the band capping each plate: a dark frame,
                                  # not a white one -- see TOWER_GLASS
TOWER_SPIRE = (150, 158, 170)

# **The glass is one family and only the shade moves.**
#
# Every reference skyline for this district is a wall of the same blue-grey at
# several depths. None of them is multicoloured by day. A downtown built out of
# eight different glass tints reads as a toy shelf at noon *and* as nothing
# after dark, because the colour has already been spent on the daylight -- and
# the colour after dark is the whole point.
#
# The family used to sit at (58, 74, 92) and below, which is *navy*, not glass.
# Real curtain wall is bright: it is a mirror pointed at the sky, so at noon it
# is nearly the colour of the sky and the mullions are the only dark lines on
# it. Five stops now instead of four, and the whole range is lifted about forty
# points -- same one hue, same discipline, but the district reads as glass in
# daylight instead of as five hundred studs of dark stone.
TOWER_GLASS = [
    (108, 138, 168),   # the family shade
    (86, 114, 146),    # a stop darker
    (140, 174, 204),   # a stop lighter
    (70, 96, 126),     # the darkest, for the towers that should recede
    (168, 200, 224),   # the clear one: near-sky, for the towers that should read
                       # as pure glass. Deliberately at the end of the list, so a
                       # palette indexed by band puts at most one per block.
]
# How much of the sky comes through a shaft plate. Lifted with the palette: a
# light pane at the old 0.42 reads as painted metal, and the whole point of a
# glass tower is that the building behind it is faintly there.
TOWER_GLASS_TRANSPARENCY = 0.5   # safe range 0.3 .. 0.65
# Where the colour actually lives: the crown ring and the light line over the
# base, both emissive, so they exist at night and nowhere else. A band and a
# lamp, never a lit surface -- the same rule the Circus crowns follow, for the
# same reason: a glowing face reads as a mistake at night and a glowing edge
# reads as a building.
TOWER_CROWN_NEON = DOWNTOWN_NEON


def tower_width(t, taper, bulge):
    """Width multiplier at height fraction `t` -- 0 at the podium top, 1 at the
    crown.

    `taper` is how much narrower the top is than the base. `bulge` lifts the
    middle so the profile is a curve rather than a cone, which is the whole
    difference between the reference towers and a spike: Lakhta and Shanghai
    Tower both swell before they close, and a straight cone reads as an aerial
    on a podium rather than as a building.
    """
    return (1.0 - taper * t) + bulge * math.sin(math.pi * t)


def tower_fit(base_w, base_d, twist, taper, bulge):
    """The widest axis-aligned span the shaft ever reaches, over every plate.

    Measured over the plates that are actually built rather than solved, because
    the widest plate is not always the bottom one once `bulge` is non-zero and
    is never the bottom one once `twist` is: a plate is widest in x at whatever
    yaw puts its diagonal closest to the x axis, and which plate that is depends
    on all three parameters at once. Returning it lets the caller inset by the
    real number instead of by sqrt(2) everywhere, which would throw away a
    third of the footprint on the towers that do not twist at all.
    """
    wx = wz = 0.0
    for i in range(TOWER_SEGS):
        t = (i + 0.5) / TOWER_SEGS
        k = tower_width(t, taper, bulge)
        w, d = base_w * k, base_d * k
        rad = math.radians(twist * t)
        c, s = abs(math.cos(rad)), abs(math.sin(rad))
        wx = max(wx, d * c + w * s)
        wz = max(wz, d * s + w * c)
    return wx, wz


# twist   -- degrees the shaft turns from podium to crown
# taper   -- how much narrower the crown is than the base, 0..1
# bulge   -- how far the waist swells past a straight taper
# spire   -- studs of mast above the crown, 0 for none
# cross   -- second plate at 45 degrees, so the footprint reads octagonal
# steps   -- setback shoulders cut into the shaft, 0 for a continuous one
TOWER_STYLES = {
    # Evolution Tower: a square plan that turns a full half-turn on the way up
    # and barely tapers. The twist is the building.
    "twist":   dict(twist=155.0, taper=0.30, bulge=0.00, spire=0.0,  cross=False, steps=0),
    # Lakhta Center: five-sided, closing to almost nothing under a long spire.
    # The taper is severe on purpose -- the spire has to look like the top of
    # the tower rather than something parked on it.
    "spire":   dict(twist=42.0,  taper=0.68, bulge=0.06, spire=58.0, cross=True,  steps=0),
    # Jin Mao: no twist at all, shoulders instead. The odd one out, and here so
    # the skyline has a building whose profile is steps rather than a curve.
    "setback": dict(twist=0.0,   taper=0.44, bulge=0.00, spire=20.0, cross=False, steps=4),
    # Shanghai Tower: turns, swells, and closes into a lit crown.
    "crown":   dict(twist=105.0, taper=0.52, bulge=0.09, spire=24.0, cross=True,  steps=0),
    # The straight one. No twist, almost no taper, no mast -- a flat-topped
    # glass slab with a lit parapet, which is what most of a real downtown
    # actually is. It is in here because a skyline of nothing but sculpted
    # towers is as monotonous as a skyline of nothing but boxes: the sculpted
    # ones only read as special when there is something ordinary beside them.
    "straight": dict(twist=0.0,  taper=0.08, bulge=0.00, spire=0.0,  cross=False, steps=0),
    # The same idea a size up: a broad slab that recedes behind the others and
    # gives the front row something to stand against.
    "slab":    dict(twist=0.0,   taper=0.16, bulge=0.00, spire=0.0,  cross=False, steps=2),
}


def tower_shaft(cx, cz, base_w, base_d, y0, y1, glass, style):
    """The stack of plates, bottom to top. Returns the top plate's (width,
    depth, yaw) so a crown or a spire can be sized and turned to sit on the
    plate it actually stands on rather than on a second guess at it."""
    twist, taper = style["twist"], style["taper"]
    bulge, cross, steps = style["bulge"], style["cross"], style["steps"]
    span = y1 - y0
    seg_h = span / TOWER_SEGS
    w = d = yaw = 0.0
    for i in range(TOWER_SEGS):
        t = (i + 0.5) / TOWER_SEGS
        k = tower_width(t, taper, bulge)
        # A shoulder every `steps` plates: the plate steps in early rather than
        # following the curve, which is what a setback tower does and what the
        # curve on its own cannot express.
        if steps:
            k *= 1.0 - 0.06 * (i * steps // TOWER_SEGS)
        w, d = base_w * k, base_d * k
        yaw = twist * t
        cy = y0 + (i + 0.5) * seg_h
        rbxmx.spun_box(f"Plate{i}", (cx, cy, cz), (d, seg_h - TOWER_BAND_H, w),
                       yaw, glass, GLASS, transparency=TOWER_GLASS_TRANSPARENCY,
                       collide=False)
        if cross:
            rbxmx.spun_box(f"PlateX{i}", (cx, cy, cz),
                           (d * 0.82, seg_h - TOWER_BAND_H, w * 0.82), yaw + 45.0,
                           glass, GLASS, transparency=TOWER_GLASS_TRANSPARENCY,
                           collide=False)
        # The band sits at the *top* of its own plate, so the tower is capped by
        # one and the podium is not -- the base wants the podium's own parapet
        # under it, not a band floating a plate's height above the lobby roof.
        rbxmx.spun_box(f"Band{i}", (cx, y0 + (i + 1) * seg_h - TOWER_BAND_H / 2, cz),
                       (d + 0.6, TOWER_BAND_H, w + 0.6), yaw,
                       TOWER_MULLION, SMOOTH, collide=False)
    return w, d, yaw


def tower_crown(no, cx, cz, w, d, yaw, y, spire):
    """What closes the shaft: a roof cap, a lit ring, and an optional mast.

    The ring is a band round the cap rather than a glowing top surface, and the
    mast tapers in three lengths rather than being one thin box -- a constant
    section reads as scaffolding from the street, which is what the financial
    district's existing masts already look like.
    """
    rbxmx.spun_box("Roof", (cx, y + SLAB / 2, cz), (d, SLAB, w), yaw,
                   TOWER_ROOF, CONCRETE)
    # White, not the tower's own colour: `neon` is the street band and stays at
    # the doors. See CROWN_NEON.
    _crown = dim(CROWN_NEON, NEON_ROOF_DIM)
    rbxmx.spun_box("Crown", (cx, y + SLAB + 1.3, cz), (d + 1.0, 1.6, w + 1.0), yaw,
                   _crown, NEON, collide=False,
                   children=point_light(_crown, 2.4, 70.0))
    if spire <= 0.0:
        return
    base = y + SLAB + 2.2
    lo, hi = min(w, d), 0.0
    for i, frac in enumerate((0.5, 0.32, 0.16)):
        seg = spire * (0.45, 0.33, 0.22)[i]
        hi = base + seg
        rbxmx.spun_box(f"Spire{i}", (cx, (base + hi) / 2, cz),
                       (lo * frac, seg, lo * frac), yaw, TOWER_SPIRE, METAL)
        base = hi
    # The mast lamp. Dimmed with everything else at roof height: it sits on the
    # highest object in the city and it was the brightest thing in the skyline,
    # which is backwards.
    _lamp = dim((255, 70, 50), NEON_ROOF_DIM)
    box("SpireLight", (cx - 0.9, cx + 0.9, cz - 0.9, cz + 0.9, hi - 1.6, hi - 0.4),
        _lamp, NEON, collide=False,
        children=point_light(_lamp, 2.0, 42.0))


def shaped_tower(no, x0, x1, z0, z1, floors, glass, style="twist", neon=None,
                 tint=0, front="south"):
    """One downtown tower: podium with a real lobby, shaped shaft, lit crown.

    Footprint is given corner-to-corner like every other building in this file,
    and the shaft is inset inside it by however much its own twist needs -- see
    the header. `floors` counts STOREY + SLAB the same way every other building
    in this file does, so a tower and an office block on the same street agree
    about what a storey is.

    `front` is which street the lobby door and the place point face. It exists
    because a block is two rows deep now: the south row opens onto the street
    below it and the north row onto the street above, and a tower that always
    fronted south would put half the district's doors -- and half its place
    points -- against the back of the tower in front of it, out of reach of the
    32-stud road test in check_city.
    """
    spec = TOWER_STYLES[style]
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    podium_top = FLOOR_1 + TOWER_PODIUM_H
    top = podium_top + floors * (STOREY + SLAB)
    # `no` is a label, not a number ("1_w"), so the crown colour cycles on an
    # explicit `tint` rather than on the name -- indexing a palette by `no`
    # reads fine and silently becomes string formatting the first time a
    # caller passes anything but an int.
    neon = neon or TOWER_CROWN_NEON[tint % len(TOWER_CROWN_NEON)]

    # How wide the plates may be. Solved from the style's own worst plate rather
    # than assumed, then asserted -- a style edited to twist further silently
    # grows its own footprint, and this is the line that says so.
    avail_x, avail_z = (x1 - x0) - 2.0, (z1 - z0) - 2.0
    fit_x, fit_z = tower_fit(1.0, 1.0, spec["twist"], spec["taper"], spec["bulge"])
    base_w = min(avail_x / fit_x, avail_z / fit_z)
    base_d = base_w
    gx, gz = tower_fit(base_w, base_d, spec["twist"], spec["taper"], spec["bulge"])
    assert gx <= avail_x + 1e-6 and gz <= avail_z + 1e-6, (
        f"tower {no} ({style}) spans {gx:.1f}x{gz:.1f} inside a footprint of "
        f"{avail_x:.1f}x{avail_z:.1f}. tower_fit and the inset above disagree -- "
        f"if you changed TOWER_STYLES['{style}'], that is what moved.")

    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    # `s` is "outward, toward the street this tower faces". Everything on the
    # front elevation -- the door, the canopy, the nameplate, the place point --
    # is written once against it rather than twice against a conditional.
    s = 1.0 if front == "south" else -1.0
    fz, ifz = (z0, iz0) if front == "south" else (z1, iz1)
    bz, ibz = (z1, iz1) if front == "south" else (z0, iz0)

    with group(f"Tower_{no}"):
        # No plinth and no white box. The base stands straight on the pavement
        # in the tower's own dark stone, glazed on all four sides at street
        # level, and the only bright thing on it is a light line under the
        # shaft. A slab under the footprint reads as a platform the building
        # sits in the middle of, and a marble base reads as a different building
        # bolted to the bottom of this one -- the point of a dense block is that
        # the wall meets the kerb and the tower is one object all the way down.
        # The base is four walls and a roof, not a solid block. It was a solid
        # block, with the lobby walls drawn *inside* it and a door cut in a wall
        # that had twenty studs of stone behind it -- so every tower in the
        # district had a doorway into rock and a place point the player could
        # stand on but never walk into.
        #
        # The base is the shaft's own glass taken down a couple of stops, cast
        # in smooth stone rather than brick. Both halves of that are corrections
        # of the same mistake. It was a flat grey (46, 50, 58) shared by every
        # tower in the city, in the `wall` helper's default BRICK -- so a
        # district of sculpted glass towers stood on twenty identical courses of
        # grey masonry, and from the street the first twenty studs of downtown
        # were a brick wall. Deriving the colour instead means the base belongs
        # to the tower above it and no two neighbours share one.
        base_stone = dim(glass, 0.72)
        _door = (cx - DOORWAY / 2, cx + DOORWAY / 2)
        wall("WallBack", (x0, x1) + span(ibz, bz) + (FLOOR_1, podium_top),
             base_stone, SMOOTH, along="x")
        wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, podium_top),
             base_stone, SMOOTH, along="z")
        wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, podium_top),
             base_stone, SMOOTH, along="z")
        wall("WallFront", (x0, x1) + span(fz, ifz) + (FLOOR_1, podium_top),
             base_stone, SMOOTH, along="x", doors=(_door,))
        glass_doors("Door", _door + span(fz, ifz) + (FLOOR_1, FLOOR_1 + DOOR_HEIGHT),
                    along="x")
        # Glazed in each wall's own thickness. Given the whole interior depth
        # instead -- which is what the first draft did -- `glazing` reads it as
        # "one pane this deep" and fills the room with five translucent slabs.
        glazing("GlazeFront", (x0 + 2.0, x1 - 2.0) + span(fz, ifz)
                + (FLOOR_1 + DOOR_HEIGHT + 1.0, podium_top - 3.0), along="x", panes=5)
        glazing("GlazeWest", (x0, ix0) + (z0 + 2.0, z1 - 2.0)
                + (FLOOR_1 + 2.0, podium_top - 3.0), along="z", panes=4)
        glazing("GlazeEast", (ix1, x1) + (z0 + 2.0, z1 - 2.0)
                + (FLOOR_1 + 2.0, podium_top - 3.0), along="z", panes=4)
        box("BaseRoof", (x0, x1, z0, z1, podium_top - 2.4, podium_top),
            base_stone, SMOOTH)
        # The light line, and it is a *line*: four thin bands round the base's
        # four faces, proud of the wall by the width of a reveal.
        #
        # It used to be one box spanning `x0 - 0.8 .. x1 + 0.8` by
        # `z0 - 0.8 .. z1 + 0.8` -- the whole footprint -- so every tower in the
        # district wore a fifty-by-sixty-stud sheet of saturated colour on its
        # shoulders. From above that is a coloured lid; from the street it is a
        # glowing slab the building appears to be standing in. A reveal is an
        # edge, and an edge is four bands.
        _ny0, _ny1 = podium_top - 1.2, podium_top - 0.2
        for _side, _nb in (
            ("S", (x0 - 0.6, x1 + 0.6, z0 - 0.6, z0 + 0.2)),
            ("N", (x0 - 0.6, x1 + 0.6, z1 - 0.2, z1 + 0.6)),
            ("W", (x0 - 0.6, x0 + 0.2, z0 + 0.2, z1 - 0.2)),
            ("E", (x1 - 0.2, x1 + 0.6, z0 + 0.2, z1 - 0.2)),
        ):
            # One lamp, on the band over the door, rather than four stacked at
            # the same height -- four point lights on one parapet is four times
            # the cost for a glow the eye reads once.
            lit = _side == ("S" if front == "south" else "N")
            box(f"BaseNeon{_side}", _nb + (_ny0, _ny1), neon, NEON, collide=False,
                children=point_light(neon, 1.4, 46.0) if lit else "")
        w, d, yaw = tower_shaft(cx, cz, base_w, base_d,
                                podium_top, top, glass, spec)
        tower_crown(no, cx, cz, w, d, yaw, top, spec["spire"])

        box("Canopy", (cx - DOORWAY, cx + DOORWAY)
            + span(fz - s * 4.0, fz + s * 0.4)
            + (FLOOR_1 + 12.4, FLOOR_1 + 13.4), TOWER_ROOF, SMOOTH,
            collide=False)
        box("Reception", (ix0 + 5.0, ix0 + 13.0)
            + span(ibz - s * 7.0, ibz - s * 3.0) + (FLOOR_1, FLOOR_1 + 3.0),
            DESK_TOP, WOOD)
        ceiling_light(cx, cz, podium_top - 3.0)

    place_point(f"tower_{no}", cx, fz + s * 2.0, FLOOR_1, f"tower {no}, the lobby")
    return top + spec["spire"]


def shaped_tower_skyline(floors, style):
    """The highest point of a `shaped_tower`: its spire tip, or its crown if it
    has no spire.

    Split out because the Circle's height rule is asserted against this number
    and the alternative
    to a function is measuring the generated file by hand and typing the answer
    into a comment -- which is how CIRCUS_STOREYS came to claim 150 for a tower
    that measures 135.5. Anything that changes a tower's height has to change
    it here, in one place, or the assertion is guarding a building nobody
    built.
    """
    spec = TOWER_STYLES[style]
    top = FLOOR_1 + TOWER_PODIUM_H + floors * (STOREY + SLAB)
    return top + SLAB + 2.2 + spec["spire"]


def grand_bank(x0, x1, z0, z1):
    """A grand neoclassical bank with a portico, marble columns, and a vault.
    The place point id is 'bank' so Jobs.luau's bank_teller still resolves."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    cx = (x0 + x1) / 2
    cz = (z0 + z1) / 2
    bank_h = CEIL_1 + SLAB + STOREY  # two storeys + lobby extra
    # Columns along the south portico.
    column_spacing = (x1 - x0 - 4.0) / 4.0
    with group("Bank"):
        # An inlay, not a slab: the bank stands in the government quarter, whose
        # paving is laid for the whole quarter before anything goes up on it.
        box("Slab", (x0, x1, z0, z1, FLOOR_1, FLOOR_1 + FLOOR_INLAY),
            BANK_MARBLE, MARBLE)
        box("Roof", (x0, x1, z0, z1, bank_h, bank_h + SLAB),
            TRIM_WHITE, CONCRETE)
        # Dome on top.
        box("DomeBase", (cx - 12.0, cx + 12.0, cz - 8.0, cz + 8.0,
                         bank_h + SLAB, bank_h + SLAB + 8.0),
            TRIM_WHITE, CONCRETE)
        box("Dome", (cx - 10.0, cx + 10.0, cz - 6.0, cz + 6.0,
                     bank_h + SLAB + 8.0, bank_h + SLAB + 16.0),
            BANK_MARBLE, CONCRETE)
        box("DomeCap", (cx - 4.0, cx + 4.0, cz - 4.0, cz + 4.0,
                        bank_h + SLAB + 16.0, bank_h + SLAB + 22.0),
            DOME_GOLD, METAL)
        # South portico columns.
        for i in range(5):
            col_x = x0 + 2.0 + i * column_spacing
            box(f"Col{i}", (col_x, col_x + 1.2, z0 - 6.0, z0 - 4.8,
                            FLOOR_1, bank_h),
                BANK_MARBLE, MARBLE)
        # Portico roof.
        box("PorticoRoof", (x0 - 2.0, x1 + 2.0, z0 - 6.0, z0 - 4.8,
                            bank_h - 2.0, bank_h + SLAB),
            TRIM_WHITE, CONCRETE)
        # Main walls (north and sides).
        wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, bank_h),
             BANK_MARBLE, along="x")
        wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, bank_h),
             BANK_MARBLE, along="z")
        wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, bank_h),
             BANK_MARBLE, along="z")
        # South wall with grand entrance.
        door_z0, door_z1 = cx - DOORWAY, cx + DOORWAY
        wall("WallSouth", (x0, x1, z0, z0 + WALL, FLOOR_1, bank_h),
             BANK_MARBLE, along="x",
             doors=((door_z0, door_z1),))
        glazing("SouthWinW", (x0 + 1.5, ix0 - 1.5, z0 + 1.0, z0 + WALL - 1.0,
                              FLOOR_1 + 2.0, bank_h - 2.0),
                along="x", panes=3)
        glazing("SouthWinE", (ix1 + 1.5, x1 - 1.5, z0 + 1.0, z0 + WALL - 1.0,
                              FLOOR_1 + 2.0, bank_h - 2.0),
                along="x", panes=3)
        # Interior: teller counter and vault.
        box("Teller", (cx - 10.0, cx + 10.0, z1 - 6.0, z1 - 1.0,
                       FLOOR_1, FLOOR_1 + 3.0),
            DESK_TOP, WOOD)
        box("Vault", (x1 - 8.0, x1 - 1.0, z1 - 10.0, z1 - 1.0,
                      FLOOR_1, FLOOR_1 + 12.0),
            STEEL, METAL)
        for dx in (-8.0, 0.0, 8.0):
            desk(cx + dx, cz, FLOOR_1, side="north", width=4.0, depth=2.6,
                 label="Desk")
        ceiling_light(cx, cz, bank_h - 0.5)
        # Grand sign.
        box("Sign", (cx - 14.0, cx + 14.0, z0 - 1.6, z0 - 0.6,
                     FLOOR_1 + 14.0, FLOOR_1 + 16.0),
            DOME_GOLD, SMOOTH,
            children=sign("UNION BANK", "front", color=(40, 36, 30), size=60))

    place_point("bank", cx, z0 + 4.0, FLOOR_1,
                "the grand bank, by the teller")


def grand_city_hall(x0, x1, z0, z1):
    """A three-storey civic building with a central tower and a cupola.
    Replaces the generic storefront for the 'town_hall' place point."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    cx = (x0 + x1) / 2
    cz = (z0 + z1) / 2
    hall_h = CEIL_2 + SLAB + STOREY  # three storeys
    tower_w = 16.0
    tower_d = 14.0
    with group("CityHall"):
        box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1),
            CITY_HALL_MARBLE, MARBLE)
        # Main hall walls.
        wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, hall_h),
             CITY_HALL_MARBLE, along="x")
        wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, hall_h),
             CITY_HALL_MARBLE, along="z")
        wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, hall_h),
             CITY_HALL_MARBLE, along="z")
        door_z0, door_z1 = cx - DOORWAY, cx + DOORWAY
        wall("WallSouth", (x0, x1, z0, z0 + WALL, FLOOR_1, hall_h),
             CITY_HALL_MARBLE, along="x",
             doors=((door_z0, door_z1),))
        glazing("SouthWinW", (x0 + 1.5, ix0 - 1.5, z0 + 1.0, z0 + WALL - 1.0,
                              FLOOR_1 + 2.0, hall_h - 2.0),
                along="x", panes=3)
        glazing("SouthWinE", (ix1 + 1.5, x1 - 1.5, z0 + 1.0, z0 + WALL - 1.0,
                              FLOOR_1 + 2.0, hall_h - 2.0),
                along="x", panes=3)
        # Central tower rising from the main roof.
        tx0, tx1 = cx - tower_w / 2, cx + tower_w / 2
        tz0, tz1 = cz - tower_d / 2, cz + tower_d / 2
        tower_top = hall_h + SLAB + STOREY
        box("Tower", (tx0, tx1, tz0, tz1, hall_h, tower_top),
            CITY_HALL_MARBLE, CONCRETE)
        box("TowerRoof", (tx0, tx1, tz0, tz1, tower_top, tower_top + SLAB),
            TRIM_WHITE, CONCRETE)
        # Cupola.
        cupola_h = 8.0
        box("Cupola", (cx - 4.0, cx + 4.0, cz - 4.0, cz + 4.0,
                       tower_top + SLAB, tower_top + SLAB + cupola_h),
            TRIM_WHITE, CONCRETE)
        box("CupolaDome", (cx - 3.0, cx + 3.0, cz - 3.0, cz + 3.0,
                           tower_top + SLAB + cupola_h,
                           tower_top + SLAB + cupola_h + 5.0),
            DOME_GOLD, METAL)
        # Interior: council chamber and desk.
        box("CouncilDesk", (cx - 12.0, cx + 12.0, z1 - 6.0, z1 - 1.0,
                            FLOOR_1, FLOOR_1 + 3.0),
            DESK_TOP, WOOD)
        for dx in range(-2, 3):
            desk(cx + dx * 6.0, cz - 2.0, FLOOR_1, side="north", width=5.0,
                 depth=2.6, label="Desk")
        # Benches for the public.
        for dx in (-8.0, 8.0):
            bench(cx + dx, cz, 0)
        ceiling_light(cx, cz, hall_h - 0.5)
        # Grand civic sign.
        box("Sign", (cx - 14.0, cx + 14.0, z0 - 1.6, z0 - 0.6,
                     FLOOR_1 + 16.0, FLOOR_1 + 18.0),
            DOME_GOLD, SMOOTH,
            children=sign("CITY HALL", "front", color=(40, 36, 30), size=60))

    place_point("town_hall", cx, z0 + 4.0, FLOOR_1,
                "city hall, the council chamber")


OFFICE_ROW_DEPTH = 40.0    # the towers' own depth, off the south edge.
OFFICE_PLAZA_GAP = 4.0     # paving starts this far behind them.


def office_block(band, sband, x0, x1, z0, z1, counter):
    """Three towers along the block's south edge, facing the cross street, with
    a paved plaza filling the rest of the block behind them. Returns the next
    free tower number.

    The number has to come in from outside. It used to be `i + 1`, so the three
    towers were office_1..3 on *every* office block -- which was invisible only
    because no block was ever assigned the role. The moment two were, the second
    block's place points would have collided with the first's and check 3 would
    have failed on a generator that had looked correct for as long as it existed.
    """
    tw_w = (x1 - x0 - 2.0) / 3
    for i in range(3):
        tx0 = x0 + 1.0 + i * tw_w
        office_tower(counter + i, tx0, tx0 + tw_w - 1.0, z0,
                     z0 + OFFICE_ROW_DEPTH)
    pz0 = z0 + OFFICE_ROW_DEPTH + OFFICE_PLAZA_GAP
    pz1 = z1
    fx = (x0 + x1) / 2
    fz = (pz0 + pz1) / 2
    with group(f"OfficePlaza_{band}_{sband}"):
        box("Paving", (x0, x1, pz0, pz1, GROUND_BOTTOM, GROUND),
            PATH_STONE, PEBBLE)
        box("Basin", (fx - 5.0, fx + 5.0, fz - 5.0, fz + 5.0,
                      GROUND - 0.2, GROUND + 0.5), (196, 190, 180), CONCRETE)
        box("Spout", (fx - 0.6, fx + 0.6, fz - 0.6, fz + 0.6,
                      GROUND + 0.5, GROUND + 4.0), (196, 190, 180), CONCRETE)
    for tx, tz in ((x0 + 5.0, pz0 + 4.0), (x1 - 5.0, pz0 + 4.0),
                   (x0 + 5.0, pz1 - 4.0), (x1 - 5.0, pz1 - 4.0)):
        tree(tx, tz, GROUND, height=12.0, spread=8.0)
    bench(fx - 9.0, fz, 1, label=f"OfficeBench_{band}_{sband}")
    bench(fx + 9.0, fz, -1, label=f"OfficeBench_{band}_{sband}")
    return counter + 3


# ---------------------------------------------------------------------------
# Dining row
# ---------------------------------------------------------------------------


def dining_restaurant(pid, label, x0, x1, z0, z1):
    """A narrow restaurant with an awning over the door, fronting the south
    cross street. Tables line the window."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    cx = (x0 + x1) / 2
    wall_color = STORE_WALLS[int(pid.split("_")[1]) % len(STORE_WALLS)]

    with group(f"Restaurant_{pid}"):
        box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1), FLOOR_INDOOR, MARBLE)
        box("Roof", (x0, x1, z0, z1, CEIL_1, CEIL_1 + SLAB), ROOF_GREY, SLATE)
        wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, CEIL_1), wall_color, along="z")
        wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, CEIL_1), wall_color, along="z")
        wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, CEIL_1), wall_color, along="x")
        wall("WallFront", (x0, x1, z0, iz0, FLOOR_1, CEIL_1), wall_color,
             along="x", doors=((cx - DOORWAY / 2, cx + DOORWAY / 2),))
        glazing("Front", (x0 + 1.5, x1 - 1.5, iz0 + 0.4, z1 - 0.4,
                          FLOOR_1 + 1.5, FLOOR_1 + 9.5), along="x", panes=3)
        box("Awning", (x0 + 2.0, x1 - 2.0, z0 - 3.4, z0 - 0.4,
                       FLOOR_1 + 8.0, FLOOR_1 + 10.5), AWNING_RED, FABRIC, collide=False)
        box("AwningTrim", (x0 + 2.0, x1 - 2.0, z0 - 3.6, z0 - 3.4,
                           FLOOR_1 + 8.0, FLOOR_1 + 10.5), AWNING_CREAM, FABRIC, collide=False)
        # Tables along the window, a counter across the back.
        for i in range(3):
            tz = iz1 - 6.0 - i * 6.0
            desk(cx, tz, FLOOR_1, side="north", width=4.0, depth=2.2, label="Table")
            chair(cx - 2.6, tz, FLOOR_1, side="south")
            chair(cx + 2.6, tz, FLOOR_1, side="south")
        box("Counter", (ix0 + 2.0, ix0 + 6.0, iz0 + 3.0, iz1 - 3.0,
                        FLOOR_1, FLOOR_1 + 3.0), DESK_TOP, WOOD)
        box("Sign", (cx - 7.0, cx + 7.0, z0 - 2.2, z0 - 1.2,
                     FLOOR_1 + 11.0, FLOOR_1 + 13.0), wall_color, SMOOTH,
            children=sign(label, "front", color=(250, 246, 234), size=52))
        ceiling_light(cx, iz1 - 3.0, CEIL_1)

    place_point(pid, cx, z0 + 2.0, FLOOR_1, f"the {label.lower()}, by the door")


# A table and its two chairs need this much floor, and the terrace is laid out
# by dividing the ground it is given rather than by stepping a fixed pitch off
# one corner. The fixed-pitch version silently drew nothing on a strip narrower
# than its own first step -- every table failed the bounds guard and the caller
# got an empty stone rectangle with no complaint from anywhere.
TERRACE_PITCH_X = 13.0
TERRACE_PITCH_Z = 12.0
TERRACE_MARGIN = 5.0


def dining_terrace(x0, x1, z0, z1, label="DiningTerrace"):
    """Paved outdoor seating: what is left of a restaurant's quadrant once the
    building has taken its frontage.

    Sits on `GROUND`, one step over the lawn CityGround lays, the same plane
    every other in-block plaza in this file uses -- a terrace at PAVING would
    stand six hundredths of a stud above the sidewalk it runs into, which is a
    lip the player trips on and the eye reads as a mistake."""
    cols = max(1, int((x1 - x0 - 2 * TERRACE_MARGIN) // TERRACE_PITCH_X))
    rows = max(1, int((z1 - z0 - 2 * TERRACE_MARGIN) // TERRACE_PITCH_Z))
    with group(label):
        box("Paving", (x0, x1, z0, z1, GROUND_BOTTOM, GROUND),
            PATH_STONE, PEBBLE)
        for i in range(cols):
            for j in range(rows):
                tx = x0 + (x1 - x0) * (i + 0.5) / cols
                tz = z0 + (z1 - z0) * (j + 0.5) / rows
                desk(tx, tz, GROUND, side="north", width=4.0, depth=2.2,
                     label="Table")
                chair(tx - 2.6, tz, GROUND, side="south")
                chair(tx + 2.6, tz, GROUND, side="south")
        for tx in (x0 + 3.0, x1 - 3.0):
            tree(tx, z1 - 4.0, GROUND, height=11.0, spread=7.0)


# ---------------------------------------------------------------------------
# Greenfield
# ---------------------------------------------------------------------------



# ---------------------------------------------------------------------------
# Sports centre (boxing gym + basketball/volleyball hall)
# ---------------------------------------------------------------------------
#
# Replaces the one-off greenfield block: same footprint, no longer an empty
# lot. Two halls side by side with a 6-stud service gap between them, sharing
# the block's frontage onto the cross street that closes its south edge --
# both doors sit within ROAD_ACCESS of that carriageway, which a walled
# building has to answer for (see the note on check_city's road-access sweep
# above the stadium; that bowl is exempt because it carries no `Roof` part,
# but these are real indoor halls and this block is inside the ordinary grid,
# so they get no such exemption and do not need one).

RING_CANVAS = (208, 208, 200)
RING_ROPE = (206, 46, 46)
BAG_LEATHER = (92, 62, 44)
MIRROR_PANEL = (196, 210, 214)
HALL_CEIL = FLOOR_1 + 22.0  # taller than a shopfront's CEIL_1 -- a ring needs headroom a counter doesn't


def boxing_hall(x0, x1, z0, z1):
    """A single walled hall: a ring at the centre, a bag row down one side, a
    mirror wall on the other. The mirror is drawn as a flat tinted panel
    rather than a `glazing()` run -- glazing is non-colliding and see-through
    onto whatever is behind it, which is correct for a shopfront and wrong for
    a wall meant to reflect the room back at whoever is training in it."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    cx, cz = (x0 + x1) / 2, z0 + 34.0

    with group("BoxingGym"):
        box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1), FLOOR_INDOOR, MARBLE)
        box("Roof", (x0, x1, z0, z1, HALL_CEIL, HALL_CEIL + SLAB), ROOF_GREY, SLATE)
        wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, HALL_CEIL), BRICK_WARM, along="z")
        wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, HALL_CEIL), BRICK_WARM, along="z")
        wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, HALL_CEIL), BRICK_WARM, along="x")
        wall("WallFront", (x0, x1, z0, iz0, FLOOR_1, HALL_CEIL), BRICK_WARM,
             along="x", doors=((cx - 5.0, cx + 5.0),))
        glazing("Front", (x0 + 2.0, x1 - 2.0, iz0 + 0.4, z0 + 0.4 + 3.0,
                          FLOOR_1 + 1.5, FLOOR_1 + 9.5), along="x", panes=4)
        box("Sign", (cx - 14.0, cx + 14.0, iz0 + 0.4, iz0 + 1.4,
                     FLOOR_1 + 11.0, FLOOR_1 + 13.0), BRICK_WARM, SMOOTH,
            children=sign("GOLDGLOVE BOXING", "front", color=(250, 246, 234), size=44))

        with group("Ring"):
            rx0, rx1 = cx - 9.0, cx + 9.0
            rz0, rz1 = cz - 9.0, cz + 9.0
            box("Apron", (rx0 - 1.5, rx1 + 1.5, rz0 - 1.5, rz1 + 1.5,
                          FLOOR_1, FLOOR_1 + 1.2), RING_CANVAS, FABRIC)
            box("Canvas", (rx0, rx1, rz0, rz1, FLOOR_1 + 1.2, FLOOR_1 + 1.3),
                (230, 230, 226), FABRIC, tags=[SPORT_TAG], attrs={SPORT_KIND: "boxing"})
            for px, pz in ((rx0, rz0), (rx1, rz0), (rx0, rz1), (rx1, rz1)):
                part_x = px - cx
                part_z = pz - cz
                with at(cx + part_x, cz + part_z, floor=FLOOR_1 + 1.3):
                    part("Post", (0, 0, 0), (0.8, 4.6, 0.8), STEEL, METAL)
            for ry in (1.6, 2.9, 4.2):
                box(f"RopeS{ry:.1f}", (rx0, rx1, rz0 - 0.15, rz0 + 0.15,
                                       FLOOR_1 + 1.3 + ry, FLOOR_1 + 1.5 + ry),
                    RING_ROPE, FABRIC, collide=False,
                    tags=[SPORT_TAG], attrs={SPORT_KIND: "boxing"})
                box(f"RopeN{ry:.1f}", (rx0, rx1, rz1 - 0.15, rz1 + 0.15,
                                       FLOOR_1 + 1.3 + ry, FLOOR_1 + 1.5 + ry),
                    RING_ROPE, FABRIC, collide=False,
                    tags=[SPORT_TAG], attrs={SPORT_KIND: "boxing"})

        with group("Bags"):
            bag_x = ix1 - 5.0
            for i, bz in enumerate((cz - 16.0, cz - 4.0, cz + 8.0)):
                with at(bag_x, bz, floor=FLOOR_1):
                    part(f"Chain{i}", (0, 9.5, 0), (0.3, 2.0, 0.3), STEEL, METAL)
                    # Every heavy bag is both a decorative fixture (SPORT_TAG, for
                    # anything that wants to point a prop at "a boxing bag") and a
                    # drill station (SPORTS_DRILL_TAG) -- three stations rather than
                    # one so the hall never queues players onto a single bag.
                    part(f"Bag{i}", (0, 6.5, 0), (2.2, 5.0, 2.2), BAG_LEATHER, FABRIC,
                         tags=[SPORT_TAG, SPORTS_DRILL_TAG],
                         attrs={SPORT_KIND: "boxing", SPORTS_DRILL_KIND: "boxing"})
            with at(bag_x, cz + 22.0, floor=FLOOR_1):
                part("SpeedBoard", (0, 6.6, 0), (2.4, 1.4, 0.6), DESK_TOP, WOOD)
                part("SpeedBag", (0, 5.6, 0.7), (1.0, 1.4, 1.0), BAG_LEATHER, FABRIC,
                     tags=[SPORT_TAG], attrs={SPORT_KIND: "boxing"})

        box("Mirror", (ix0 + 0.2, ix0 + 0.5, iz0 + 6.0, iz1 - 6.0,
                       FLOOR_1 + 1.0, FLOOR_1 + 9.0), MIRROR_PANEL, GLASS,
            transparency=0.1)
        ceiling_light(cx, cz, HALL_CEIL)
        ceiling_light(cx, iz1 - 10.0, HALL_CEIL)

    place_point("boxing_gym", cx, cz, FLOOR_1, "the boxing gym, at the ring")


def court_hall(x0, x1, z0, z1):
    """A basketball court and a volleyball court sharing one roofed hall, one
    behind the other along the block's depth -- the same reasoning as the
    stadium's tiling, applied at building scale: two courts side by side
    would need double the block's width, which this footprint does not have,
    while stacked along the depth they fit with room for a spectator strip
    between them."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    cx = (x0 + x1) / 2

    bk_z0, bk_z1 = iz0 + 6.0, iz0 + 50.0
    vb_z0, vb_z1 = bk_z1 + 8.0, iz1 - 4.0

    with group("CourtHall"):
        box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1), FLOOR_INDOOR, MARBLE)
        box("Roof", (x0, x1, z0, z1, HALL_CEIL, HALL_CEIL + SLAB), ROOF_GREY, SLATE)
        wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, HALL_CEIL), BRICK_PALE, along="z")
        wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, HALL_CEIL), BRICK_PALE, along="z")
        wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, HALL_CEIL), BRICK_PALE, along="x")
        wall("WallFront", (x0, x1, z0, iz0, FLOOR_1, HALL_CEIL), BRICK_PALE,
             along="x", doors=((cx - 5.0, cx + 5.0),))
        glazing("Front", (x0 + 2.0, x1 - 2.0, iz0 + 0.4, z0 + 0.4 + 3.0,
                          FLOOR_1 + 1.5, FLOOR_1 + 9.5), along="x", panes=4)
        box("Sign", (cx - 16.0, cx + 16.0, iz0 + 0.4, iz0 + 1.4,
                     FLOOR_1 + 11.0, FLOOR_1 + 13.0), BRICK_PALE, SMOOTH,
            children=sign("CIVIC COURTS", "front", color=(250, 246, 234), size=44))

        with group("Basketball"):
            box("Court", (ix0 + 3.0, ix1 - 3.0, bk_z0, bk_z1, FLOOR_1, FLOOR_1 + 0.15),
                COURT_BLUE, SMOOTH)
            box("Mid", (ix0 + 3.0, ix1 - 3.0, (bk_z0 + bk_z1) / 2 - 0.3,
                       (bk_z0 + bk_z1) / 2 + 0.3, FLOOR_1 + 0.15, FLOOR_1 + 0.2),
                (240, 240, 240), SMOOTH)
            for hz, into in ((bk_z0, 1), (bk_z1, -1)):
                with group(f"Hoop{hz:.0f}"):
                    box("Backboard", (cx - 1.75, cx + 1.75, hz - into * 1.5, hz - into * 0.5,
                                      FLOOR_1 + 7.0, FLOOR_1 + 10.0), (240, 240, 240), GLASS,
                        tags=[SPORT_TAG], attrs={SPORT_KIND: "basketball"})
                    # The rim is both the decorative fixture and the drill station --
                    # a hoop is the one part of a basketball goal a shot actually has
                    # to clear, so it is the natural stand-at-this point for a shooting
                    # sweep. Both hoops are tagged, giving the hall two stations.
                    box("Rim", (cx - 1.5, cx + 1.5, hz + into * 0.5, hz + into * 1.5,
                                FLOOR_1 + 7.0, FLOOR_1 + 7.3), (216, 120, 40), METAL,
                        tags=[SPORT_TAG, SPORTS_DRILL_TAG],
                        attrs={SPORT_KIND: "basketball", SPORTS_DRILL_KIND: "basketball"})
                    box("Pole", (cx - 0.5, cx + 0.5, hz - into * 2.0, hz - into * 1.0,
                                 FLOOR_1, FLOOR_1 + 7.0), (120, 120, 126), METAL)
        place_point("basketball_gym", cx, (bk_z0 + bk_z1) / 2, FLOOR_1,
                    "the basketball court")

        with group("Volleyball"):
            box("Court", (ix0 + 5.0, ix1 - 5.0, vb_z0, vb_z1, FLOOR_1, FLOOR_1 + 0.15),
                COURT_GREEN, SMOOTH)
            vmid = (vb_z0 + vb_z1) / 2
            box("Net", (cx - 8.5, cx + 8.5, vmid - 0.1, vmid + 0.1,
                       FLOOR_1 + 1.0, FLOOR_1 + 4.5), (230, 230, 230), FABRIC,
                collide=False, tags=[SPORT_TAG, SPORTS_DRILL_TAG],
                attrs={SPORT_KIND: "volleyball", SPORTS_DRILL_KIND: "volleyball"})
            for side in (-1, 1):
                with at(cx + side * 8.7, vmid, floor=FLOOR_1):
                    part(f"Post{side}", (0, 2.25, 0), (0.5, 4.5, 0.5), STEEL, METAL)
        place_point("volleyball_court", cx, vmid, FLOOR_1, "the volleyball court")

        ceiling_light(cx, (bk_z0 + bk_z1) / 2, HALL_CEIL)
        ceiling_light(cx, vmid, HALL_CEIL)


def sports_center(band, sband, x0, x1, z0, z1):
    """Splits the block into two halls with a service gap between -- the
    boxing gym on the west half, the basketball/volleyball hall on the east,
    both fronting the same cross street so both doors are the block's usual
    ROAD_ACCESS distance from a carriageway."""
    gap = 6.0
    half = (x1 - x0 - gap) / 2
    boxing_hall(x0, x0 + half, z0, z1)
    court_hall(x0 + half + gap, x1, z0, z1)


# ---------------------------------------------------------------------------
# The Garden: the indoor arena
# ---------------------------------------------------------------------------
#
# The block this stands on was six houses, on the last avenue, looking straight
# at the back of the soccer stadium -- a residential street with a hundred
# thousand seats at the end of it. The houses have gone two cross streets south,
# where the rest of the low city is, and the block they were on now holds the
# one building the city was missing: a covered arena, which is what a life sim
# needs for the half of its sport that is not played on grass.
#
# It is a drum, not a box. That is the whole point of the building and the
# reason it is worth the parts: every other large interior in this city is
# rectangular, so the one round room in the world reads as somewhere you have
# arrived at rather than another hall. `elliptical_ring` already builds the
# stadium's bowl out of spun facets and is reused wholesale here -- a second
# implementation of "an annulus of boxes" is the thing this file asserts against
# everywhere else.
#
# Named "The Garden" rather than after the building it is modelled on. The
# nickname is what the place is actually called, and a real venue's registered
# name painted across a Roblox marquee is a trademark problem the game does not
# need to have.
ARENA_MARGIN = 5.0          # plaza between the drum and the block edge
ARENA_WALL_T = 3.2          # thickness of the drum wall
ARENA_ARCADE_H = 15.0       # the glazed street-level band under the drum
ARENA_DRUM_H = 46.0         # top of the drum, where the roof starts
ARENA_ROOF_RINGS = 3        # steps in the dome; each one draws a ring of facets
ARENA_ROOF_RISE = 4.5       # how much each step climbs
ARENA_ROOF_STEP = 7.0       # how far each step draws in
ARENA_TIERS = 3
ARENA_RISE = 5.0            # how much a seating tier climbs over the one inside it
ARENA_TREAD = 8.0           # how deep one seating tier is
ARENA_BOWL_GAP = 6.0        # concourse between the top tier and the drum wall
ARENA_COURT_X = 11.0        # half-width of the show court
ARENA_COURT_Z = 17.0        # half-length
ARENA_DOOR_H = 13.0
# Which facets of the 24 are cut open. 12 is due west -- the city side, where the
# marquee and the main doors are -- and 0 is due east, facing the stadium, so the
# two big venues share a route rather than turning their backs on each other.
ARENA_WEST_FACETS = (11, 12, 13)
ARENA_EAST_FACET = 0
ARENA_STONE = (228, 210, 182)
ARENA_TRIM = (196, 176, 148)
ARENA_SEATS = [(84, 106, 150), (168, 60, 66)]   # two rings, home colours
ARENA_FLOOR = (216, 172, 116)
ARENA_COURT_LINE = (248, 246, 240)


def arena_bowl(cx, cz, floor):
    """The seating: `ARENA_TIERS` concentric rings stepping up and out from the
    court, then the concourse floor behind the top one."""
    for i in range(ARENA_TIERS):
        r_in_x = ARENA_COURT_X + 4.0 + i * ARENA_TREAD
        r_in_z = ARENA_COURT_Z + 4.0 + i * ARENA_TREAD
        elliptical_ring(f"Tier{i}", cx, cz,
                        r_in_x + ARENA_TREAD, r_in_z + ARENA_TREAD,
                        r_in_x, r_in_z,
                        floor, floor + (i + 1) * ARENA_RISE,
                        ARENA_SEATS[i % len(ARENA_SEATS)], CONCRETE)


def arena_block(band, sband, x0, x1, z0, z1):
    """One block, one building: a round arena with a show court in it.

    Takes the whole block rather than sharing it, which nothing else in the grid
    does. A drum with a plaza round it is the shape the building is -- half a
    block of arena beside half a block of something else would be a hall, and
    the city already has one of those on the block below this."""
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    rx = (x1 - x0) / 2 - ARENA_MARGIN
    rz = (z1 - z0) / 2 - ARENA_MARGIN
    ix, iz = rx - ARENA_WALL_T, rz - ARENA_WALL_T
    # The bowl has to fit inside the drum with a concourse behind it. Asserted
    # rather than assumed: every one of these is a tunable above, and a court
    # widened by four studs silently pushes the top tier into the wall, which
    # draws as seating embedded in stone and reads as nothing at all.
    bowl_x = ARENA_COURT_X + 4.0 + ARENA_TIERS * ARENA_TREAD
    bowl_z = ARENA_COURT_Z + 4.0 + ARENA_TIERS * ARENA_TREAD
    assert bowl_x + ARENA_BOWL_GAP <= ix and bowl_z + ARENA_BOWL_GAP <= iz, (
        f"the arena bowl reaches {bowl_x:.1f}x{bowl_z:.1f} inside a drum of "
        f"{ix:.1f}x{iz:.1f} with {ARENA_BOWL_GAP} studs of concourse wanted. "
        f"Shrink ARENA_COURT_*, ARENA_TREAD or ARENA_TIERS -- the block cannot "
        f"grow, it is the grid.")
    drum_top = GROUND + ARENA_DRUM_H
    doors = set(ARENA_WEST_FACETS) | {ARENA_EAST_FACET}

    with group(f"Arena{band}_{sband}"):
        box("Plaza", (x0, x1, z0, z1, GROUND_BOTTOM, GROUND), PATH_STONE, PEBBLE)
        # The drum, in two bands. The glazed arcade at the bottom is what stops
        # a fifty-stud stone cylinder reading as a silo: at street level the
        # building is mostly window, and the solid mass starts above head
        # height -- which is what the wall of an arena actually does, because
        # the concourse behind it is the part with people in it.
        elliptical_ring("Arcade", cx, cz, rx, rz, ix, iz,
                        GROUND, GROUND + ARENA_ARCADE_H, GLAZING, GLASS,
                        transparency=0.45, door_facets=doors,
                        door_head=ARENA_DOOR_H)
        elliptical_ring("Drum", cx, cz, rx, rz, ix, iz,
                        GROUND + ARENA_ARCADE_H, drum_top, ARENA_STONE, LIMESTONE)
        # Vertical fins on the drum, on the facet seams. One ring of thin boxes
        # and the only thing giving a curved wall any scale from across the
        # avenue -- an unbroken cylinder has no way to tell the eye how big it
        # is.
        for f in range(0, CIRCLE_SEGS, 2):
            phi = f * CIRCLE_STEP + CIRCLE_STEP / 2
            fx, fz = ellipse_point(phi, cx, cz, rx + 0.4, rz + 0.4)
            rbxmx.spun_box(f"Fin{f}", (fx, (GROUND + ARENA_ARCADE_H + drum_top) / 2, fz),
                           (1.6, drum_top - GROUND - ARENA_ARCADE_H, 3.0),
                           ellipse_outward_yaw(phi, rx, rz), ARENA_TRIM, LIMESTONE,
                           collide=False)
        # The band the drum wears at the top of the arcade, and the one thing on
        # this building that is lit in colour. Same rule as the towers: the
        # highlight is at the doors, not on the roof.
        _neon = DOWNTOWN_NEON[1]
        elliptical_ring("ArcadeBand", cx, cz, rx + 0.8, rz + 0.8, ix, iz,
                        GROUND + ARENA_ARCADE_H - 1.2, GROUND + ARENA_ARCADE_H,
                        _neon, NEON, collide=False)

        # The dome: rings stepping in and up off the drum, and a cap over the
        # hole the last one leaves. Not a smooth shell -- the steps are what a
        # spun-box ring can honestly build, and they read as the ribbed roof
        # this kind of arena has rather than as a failed sphere.
        ry = drum_top
        rrx, rrz = rx, rz
        for r in range(ARENA_ROOF_RINGS):
            elliptical_ring(f"Roof{r}", cx, cz, rrx, rrz,
                            rrx - ARENA_ROOF_STEP, rrz - ARENA_ROOF_STEP,
                            ry, ry + ARENA_ROOF_RISE, ARENA_TRIM, CONCRETE)
            rrx -= ARENA_ROOF_STEP
            rrz -= ARENA_ROOF_STEP
            ry += ARENA_ROOF_RISE
        box("RoofCap", (cx - rrx, cx + rrx, cz - rrz, cz + rrz, ry, ry + SLAB),
            ARENA_TRIM, CONCRETE)
        _crown = dim(CROWN_NEON, NEON_ROOF_DIM)
        box("RoofBand", (cx - rrx - 0.6, cx + rrx + 0.6,
                         cz - rrz - 0.6, cz + rrz + 0.6,
                         ry + SLAB, ry + SLAB + 1.2), _crown, NEON, collide=False,
            children=point_light(_crown, 2.2, 70.0))

        # The marquee, on the west face, over the main doors. An arena is known
        # by its marquee before it is known by its roof.
        mx = cx - rx
        box("Marquee", (mx - 9.0, mx + 1.0, cz - 22.0, cz + 22.0,
                        GROUND + ARENA_DOOR_H + 1.0, GROUND + ARENA_DOOR_H + 8.0),
            ARENA_TRIM, SMOOTH)
        box("MarqueeFace", (mx - 9.4, mx - 8.9, cz - 21.0, cz + 21.0,
                            GROUND + ARENA_DOOR_H + 2.0, GROUND + ARENA_DOOR_H + 7.0),
            (18, 20, 26), SMOOTH,
            children=sign("THE GARDEN", "left", color=(255, 214, 120), size=64))
        for i in range(6):
            lz = cz - 20.0 + i * 8.0
            box(f"MarqueeLamp{i}", (mx - 9.6, mx - 9.2, lz - 1.6, lz + 1.6,
                                    GROUND + ARENA_DOOR_H + 0.6,
                                    GROUND + ARENA_DOOR_H + 1.4),
                NEON_AMBER, NEON, collide=False,
                children=point_light(NEON_AMBER, 1.4, 26.0) if i % 2 == 0 else "")

        # Inside: the floor, the bowl, the court and the thing hanging over it.
        #
        # The floor is laid *on* the plaza rather than instead of it -- one
        # inlay step up, the same way every other indoor surface in this file
        # meets the ground it stands on. Given the plaza's own height it is two
        # slabs topping in the same plane over the same hundred studs, which is
        # a flicker and is what check 13 reports.
        afloor = GROUND + FLOOR_INLAY
        box("Floor", (cx - ix, cx + ix, cz - iz, cz + iz,
                      GROUND_BOTTOM, afloor), FLOOR_INDOOR, CONCRETE)
        arena_bowl(cx, cz, afloor)
        box("Court", (cx - ARENA_COURT_X, cx + ARENA_COURT_X,
                      cz - ARENA_COURT_Z, cz + ARENA_COURT_Z,
                      afloor, afloor + FLOOR_INLAY), ARENA_FLOOR, WOOD)
        _cl = afloor + FLOOR_INLAY
        box("CentreLine", (cx - ARENA_COURT_X, cx + ARENA_COURT_X,
                           cz - 0.3, cz + 0.3, _cl, _cl + 0.06),
            ARENA_COURT_LINE, SMOOTH, collide=False)
        for _s in (-1, 1):
            box(f"Key{_s}", (cx - 5.0, cx + 5.0,
                             cz + _s * (ARENA_COURT_Z - 12.0) - 0.3,
                             cz + _s * (ARENA_COURT_Z - 12.0) + 0.3,
                             _cl, _cl + 0.06), ARENA_COURT_LINE, SMOOTH,
                collide=False)
            # A hoop at each end, on a stanchion behind the baseline the way a
            # show court's is -- a backboard growing out of the floor is the
            # detail that says "this room is for basketball" from the top tier.
            hz = cz + _s * (ARENA_COURT_Z - 2.0)
            box(f"Stanchion{_s}", (cx - 1.2, cx + 1.2, hz - 1.2, hz + 1.2,
                                   GROUND, GROUND + 11.0), STEEL, METAL)
            box(f"Backboard{_s}", (cx - 4.0, cx + 4.0,
                                   hz - _s * 2.4 - 0.2, hz - _s * 2.4 + 0.2,
                                   GROUND + 9.0, GROUND + 12.0),
                TRIM_WHITE, GLASS, transparency=0.35)
            box(f"Hoop{_s}", (cx - 1.6, cx + 1.6,
                              hz - _s * 4.4, hz - _s * 2.6,
                              GROUND + 10.0, GROUND + 10.3),
                (232, 108, 60), METAL, collide=False)
        # The scoreboard. Hung in the middle over the court, which is the one
        # thing every arena has and no other room in this city does.
        sy = GROUND + 30.0
        box("ScoreboardRig", (cx - 0.6, cx + 0.6, cz - 0.6, cz + 0.6,
                              sy + 12.0, ry), STEEL, METAL, collide=False)
        box("Scoreboard", (cx - 9.0, cx + 9.0, cz - 9.0, cz + 9.0,
                           sy, sy + 12.0), (24, 26, 32), SMOOTH)
        for _fx, _fz, _face in ((cx - 9.2, cz, "left"), (cx + 9.2, cz, "right")):
            box(f"ScoreFace{_face}", (_fx - 0.3, _fx + 0.3, cz - 8.0, cz + 8.0,
                                      sy + 2.0, sy + 10.0), (40, 44, 54), SMOOTH,
                children=sign("THE GARDEN", _face, color=(255, 214, 120), size=48))
        for _i in range(CIRCLE_SEGS // 4):
            _phi = _i * 4 * CIRCLE_STEP + CIRCLE_STEP * 2
            _lx, _lz = ellipse_point(_phi, cx, cz, ix - 4.0, iz - 4.0)
            ceiling_light(_lx, _lz, drum_top - 1.0, label=f"BowlLight{_i}")

    # Three points, and the split is the walk: the doors on the plaza, the
    # concourse just inside them, and the courtside. One point on a building
    # this size would put "the arena" fifty studs from anything a player came
    # here to do.
    place_point("arena", cx - rx - 3.0, cz, GROUND, "the garden, at the doors")
    place_point("arena_concourse", cx - ix + 3.0, cz, GROUND + FLOOR_INLAY,
                "the garden, on the concourse")
    place_point("arena_court", cx, cz - ARENA_COURT_Z + 3.0, GROUND + FLOOR_INLAY,
                "the garden, courtside")


# ---------------------------------------------------------------------------
# Storefronts (main street) and civic buildings
# ---------------------------------------------------------------------------


# How the glass is cut, which is the quietest of the four silhouette cues and the
# one that separates two shops that are otherwise the same box: a florist is all
# window down to the knee, a hardware shop is a high band over a solid base
# because the base is where the timber leans.
#
#   (sill above floor, head above floor, panes, inset from the side wall)
#
# "narrow" insets far enough that a 28-stud frontage keeps a single pane either
# side of the door instead of losing its glazing entirely. That cliff is real:
# the pane run is measured from the doorway outward, so below about 27 studs of
# frontage the two runs cross over and silently produce nothing. Anything added
# here has to be checked against the narrowest width in SHOP_FRONTS.
GLASS_STYLES = {
    "full": (1.5, 10.5, 4, 3.0),
    "high": (5.0, 12.0, 3, 3.0),
    "narrow": (2.0, 8.0, 2, 5.0),
    "none": None,
}

# How tall the fascia sign is, and where it sits. Derived rather than typed: the
# nameplate used to end at a literal 24.0, which was CEIL_1 + SLAB + 7 measured
# once and then frozen -- exactly the disease that put eight Circle waypoints in
# the carriageway when the ring grew. See MAP_PLAN.md.
SIGN_HEIGHT = 7.0
SIGN_Y0 = CEIL_1 + SLAB
SIGN_Y1 = SIGN_Y0 + SIGN_HEIGHT

# Half the width of a roll-up shutter. Wide enough to drive a fire engine
# through and narrow enough that two of them fit on a fifty-stud frontage with a
# door between. Safe range: 5 .. 9 -- above 9 a two-bay station needs a
# seventy-stud front and quietly falls back to one shutter.
ROLLUP_HALF = 7.0

# How many shutters a building of a given kind gets. Keyed on the kind rather
# than carried as another column on two tables, because it is a fact about what
# a fire station *is* and it should say the same thing wherever one is built --
# the civic row has one and the north strip now has another.
GARAGE_BAYS = {
    "fire": 2,
    "warehouse": 2,
}


# One storefront's silhouette and its insides.
#
# This table exists because every shop in the city used to be the same box: same
# 30-stud frontage, same single storey, same four panes of glass at the same
# height, same brick, and -- the part that was invisible from the street and
# worse -- the same interior. `street_fittings` had branches for a cafe, a
# restaurant and a pizzeria that nothing ever reached, because the call site
# passed the *structural* front type ("awning", "shop", "garage") where the
# function wanted a trade. So the cafe was furnished with a supermarket's
# shelving, and had been since the day it was written.
#
# The fix is to say the two things separately. `trade` is what the shop sells and
# drives what is inside it; the rest is what it looks like from across the road.
# Four cues, in descending order of how far away they read:
#
#   awning   a saturated colour at eye level -- readable at fifty studs
#   storeys  the roofline -- readable further, but only against its neighbours
#   width    how much of the block it takes
#   glass    how the frontage is cut, readable once you are on the pavement
#
# The point is that a player can tell a cafe from a hardware shop without
# reading either sign. Same principle as HOUSE_TIERS: variation the player can
# read at distance, not variation that only shows up in a diff.
#
# Constraints, all three of them binding:
#   * Per band, sum(width) + (n + 1) * MIN_SHOP_GAP <= band length. The four-shop
#     band at z 60..196 has only 136 studs, which is why its widths barely vary
#     and it carries its variation in awnings and rooflines instead.
#   * width >= 28, or the glazing runs cross over and vanish (see GLASS_STYLES).
#   * A garage stays single-storey. Its roll-up door's head is measured off
#     CEIL_1, so a second storey would leave the opening under a floor.
#
# Four trades that used to be here are not any more -- bookstore, electronics,
# toy_store and music_store are mall units now. See the note on `north_shops`
# in `mall()` for why: with nineteen of these the street's widths plus its
# minimum gaps came to exactly the length of the street, so there was no
# frontage left over for anything that is not a shop, and a main street with no
# trees, no benches and no gaps in it is a wall with doors in it.
SHOP_FRONTS = {
    # z 60..196 -- the eating end of the street. Three awnings in a row, which is
    # what makes it read as a restaurant strip rather than three more shops.
    "cafe": ("cafe", 28.0, 2, AWNING_RED, "full"),
    "restaurant": ("restaurant", 30.0, 2, AWNING_GREEN, "full"),
    "pizzeria": ("pizzeria", 28.0, 1, AWNING_MUSTARD, "full"),
    # z 218..346
    "supermarket": ("market", 30.0, 1, None, "full"),
    "pharmacy": ("counter", 34.0, 2, AWNING_BLUE, "full"),
    # z 368..496
    "florist": ("market", 28.0, 1, AWNING_GREEN, "full"),
    "hardware": ("workshop", 34.0, 1, None, "high"),
    # z 518..646
    "clothing_store": ("racks", 38.0, 2, None, "full"),
    "laundromat": ("laundromat", 30.0, 1, AWNING_BLUE, "full"),
    # z 668..796 -- the chairs. All three are the same trade at heart, so they
    # are separated by roofline and glass rather than by fittings.
    "barbershop": ("salon", 28.0, 1, AWNING_RED, "narrow"),
    "salon": ("salon", 34.0, 2, None, "full"),
    "tattoo_parlor": ("studio", 28.0, 1, None, "narrow"),
    # z 826..946 -- the motor end.
    "vet": ("desk", 30.0, 1, None, "high"),
    "gas_station": ("garage", 38.0, 1, None, "none"),
    "car_wash": ("garage", 32.0, 1, None, "none"),
}

# The narrowest gap between two storefronts that still reads as two buildings.
# Below about four studs the shadow between them closes up and the row looks
# like one long shed with a lot of doors.
MIN_SHOP_GAP = 4.0


def storey_floor(n):
    """Top surface of floor `n`, 1-based. FLOOR_1 and FLOOR_2 by another name,
    and the same arithmetic carried on past the two world_plan happens to
    name -- a shell that can only be one or two storeys tall is a row of
    buildings that can only be two heights, which is most of why the civic
    precinct read as one long wall."""
    return FLOOR_1 + (n - 1) * (STOREY + SLAB)


def storey_top(storeys):
    """The underside of the roof over an `storeys`-tall shell."""
    return storey_floor(storeys) + STOREY


def storefront(name, x0, x1, z0, z1, door_pos, wall_color, front="north",
               front_type="shop", wall_mat=BRICK, storeys=1, awning=None,
               glass="full", bays=1):
    """A storefront with the door + shopfront on the `front` wall (north,
    south, west or east). `door_pos` is the coordinate along the front wall --
    x for a north/south front, z for a west/east front.

    `storeys` raises the roofline and adds an upper window band; `awning` is a
    colour or None; `glass` names a row of GLASS_STYLES. See SHOP_FRONTS.

    `bays` is how many roll-up doors a `garage` front gets, and it is the whole
    difference between a fire station and a wide shed: two engine bays with a
    pedestrian door between them is the silhouette, and one 14-stud shutter lost
    in eighty-seven studs of brick is not."""
    if bays > 1 and front_type != "garage":
        raise ValueError(f"{name}: bays only means anything on a garage front")
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    d0, d1 = door_pos - DOORWAY / 2, door_pos + DOORWAY / 2
    top = storey_top(storeys)

    with group(f"{name}Structure"):
        box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1), FLOOR_INDOOR, MARBLE)
        box("Roof", (x0, x1, z0, z1, top, top + SLAB), ROOF_GREY, SLATE)
        for _n in range(2, storeys + 1):
            # A floor over the shop rather than an open shell. One part each,
            # and without them the player standing at the counter looks up
            # through fifteen studs of nothing at the underside of the roof.
            _fy = storey_floor(_n)
            box(f"Floor{_n}", (ix0, ix1, iz0, iz1, _fy - SLAB, _fy), FLOOR_INDOOR, MARBLE)

        if front in ("north", "south"):
            wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, top), wall_color, wall_mat, along="z")
            wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, top), wall_color, wall_mat, along="z")
            if front == "north":
                wall("WallSouth", (x0, x1, z0, iz0, FLOOR_1, top), wall_color, wall_mat, along="x")
                f0, f1 = iz1, z1
            else:
                wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, top), wall_color, wall_mat, along="x")
                f0, f1 = z0, iz0
            _shopfront(x0, x1, f0, f1, d0, d1, wall_color, wall_mat, front,
                       front_type, name, door_pos, ix0, ix1, iz0, iz1,
                       top, awning, glass, bays)
        else:
            wall("WallSouth", (x0, x1, z0, iz0, FLOOR_1, top), wall_color, wall_mat, along="x")
            wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, top), wall_color, wall_mat, along="x")
            if front == "west":
                wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, top), wall_color, wall_mat,
                     along="z", doors=((d0, d1),))
            else:
                wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, top), wall_color, wall_mat,
                     along="z", doors=((d0, d1),))
            if bays > 1:
                # Refused rather than ignored. A west/east garage that quietly
                # got one door when it asked for two is exactly the kind of
                # silent shrug that made every shop in this city identical --
                # write the branch when something actually needs it.
                raise ValueError(f"{name}: multi-bay garages are only built on north/south fronts")
            _shopfront_ns(x0, x1, z0, z1, d0, d1, wall_color, wall_mat, front,
                          front_type, name, door_pos, ix0, ix1, iz0, iz1,
                          top, awning, glass)


def _shopfront(x0, x1, f0, f1, d0, d1, wall_color, wall_mat, front, front_type,
               name, door_pos, ix0, ix1, iz0, iz1, top=None, awning=None,
               glass="full", bays=1):
    """The glazed north/south shopfront: wall with door, panes either side,
    nameplate, optional roll-up doors for garage types."""
    top = CEIL_1 if top is None else top
    if front_type == "garage":
        half = ROLLUP_HALF
        # One bay sits on the place point, so a single-shutter garage still has
        # its door where the game puts the player down. Two or more spread to
        # the ends of the frontage and leave the middle for a pedestrian door,
        # which is the arrangement that makes an engine bay read as one.
        room = (ix1 - ix0) - 2 * half - DOORWAY - 8.0
        if bays > 1 and room > 0:
            span = (ix1 - ix0) - 2 * half - 4.0
            centres = [ix0 + half + 2.0 + span * b / (bays - 1) for b in range(bays)]
        else:
            centres = [door_pos]
        openings = [(c - half, c + half) for c in centres]
        if len(centres) > 1:
            openings.append((d0, d1))
        openings.sort()
        wall("WallFront", (x0, x1, f0, f1, FLOOR_1, top), wall_color, wall_mat,
             along="x", doors=tuple(openings), head=CEIL_1 - FLOOR_1)
        for b, (gd0, gd1) in enumerate(zip([c - half for c in centres],
                                           [c + half for c in centres])):
            box(f"RollupDoor{b}", (gd0, gd1, f0 + 0.4, f1 - 0.4,
                                   FLOOR_1 + 4.0, FLOOR_1 + 14.0), STEEL, METAL, collide=False)
            for i in range(7):
                xx = gd0 + (gd1 - gd0) * (i + 0.5) / 7
                box(f"RollupSlat{b}_{i}", (xx - 0.12, xx + 0.12, f0 + 0.6, f1 - 0.6,
                                           FLOOR_1 + 4.0, FLOOR_1 + 14.0),
                    (96, 98, 102), METAL, collide=False)
        sign_face = "back" if front == "south" else "front"
        box("Nameplate", (door_pos - 6.0, door_pos + 6.0, f0, f0 + 2.5,
                          SIGN_Y0, SIGN_Y1), wall_color, BRICK,
            children=sign(name, sign_face, color=(250, 246, 234), size=64))
    else:
        wall("WallFront", (x0, x1, f0, f1, FLOOR_1, top), wall_color, wall_mat,
             along="x", doors=((d0, d1),))
        cut = GLASS_STYLES[glass]
        if cut is not None:
            sill, head, panes, inset = cut
            for i, (a, b) in enumerate(((ix0 + inset, d0 - 1.0), (d1 + 1.0, ix1 - inset))):
                if b - a > 4.0:
                    glazing(f"Shopfront{i + 1}", (a, b, f0 + 0.4, f1 - 0.4,
                                                  FLOOR_1 + sill, FLOOR_1 + head),
                            along="x", panes=panes)
        # One band per upper storey. Deliberately a different rhythm from the
        # shopfront below -- fewer, squarer, set in from the corners -- so the
        # floors read as flats over a shop rather than as one very tall window.
        # Counted off `top` rather than taking a storey count of its own: the
        # roofline is the one thing that cannot disagree with itself.
        _n = 2
        while storey_floor(_n) < top:
            _fy = storey_floor(_n)
            glazing(f"Upper{_n}", (ix0 + 4.0, ix1 - 4.0, f0 + 0.4, f1 - 0.4,
                                   _fy + 3.0, _fy + 10.0), along="x", panes=3)
            _n += 1
        sign_face = "back" if front == "south" else "front"
        box("Nameplate", (door_pos - 9.0, door_pos + 9.0, f0, f0 + 2.5,
                          SIGN_Y0, SIGN_Y1), wall_color, BRICK,
            children=sign(name, sign_face, color=(250, 246, 234), size=64))
        if awning is not None:
            # Outward from the front wall, and which way that is depends on the
            # front. `f0..f1` is the wall's own span, and for a *south* front
            # that span runs z0..iz0 -- so hanging the awning off f1 put every
            # south-facing awning three studs inside its own shop, over the
            # customers rather than over the pavement. Every awning on the north
            # strip was an interior canopy. Same disease as the counters below:
            # one side of the building was written and the other assumed.
            if front == "north":
                a0, a1 = f1, f1 + 3.6
                trim = (a1, a1 + 0.2)
            else:
                a0, a1 = f0 - 3.6, f0
                trim = (a0 - 0.2, a0)
            box("Awning", (ix0 + 2.0, ix1 - 2.0, a0, a1,
                           FLOOR_1 + 8.0, FLOOR_1 + 10.5), awning, FABRIC, collide=False)
            box("AwningTrim", (ix0 + 2.0, ix1 - 2.0, trim[0], trim[1],
                               FLOOR_1 + 8.0, FLOOR_1 + 10.5), AWNING_CREAM, FABRIC, collide=False)


def _shopfront_ns(x0, x1, z0, z1, d0, d1, wall_color, wall_mat, front, front_type,
                  name, door_pos, ix0, ix1, iz0, iz1, top=None, awning=None,
                  glass="full"):
    """The glazed west/east shopfront, for the main street stores."""
    top = CEIL_1 if top is None else top
    if front == "west":
        fw0, fw1 = x0, ix0
        sign_face = "left"
    else:
        fw0, fw1 = ix1, x1
        sign_face = "right"
    if front_type == "garage":
        gd0, gd1 = door_pos - ROLLUP_HALF, door_pos + ROLLUP_HALF
        wall("WallFront", (fw0, fw1, z0, z1, FLOOR_1, top), wall_color, wall_mat,
             along="z", doors=((gd0, gd1),), head=CEIL_1 - FLOOR_1)
        box("RollupDoor", (fw0 + 0.4, fw1 - 0.4, gd0, gd1,
                           FLOOR_1 + 4.0, FLOOR_1 + 14.0), STEEL, METAL, collide=False)
        box("Nameplate", (fw0, fw0 + 2.5, door_pos - 6.0, door_pos + 6.0,
                          SIGN_Y0, SIGN_Y1), wall_color, BRICK,
            children=sign(name, sign_face, color=(250, 246, 234), size=64))
    else:
        wall("WallFront", (fw0, fw1, z0, z1, FLOOR_1, top), wall_color, wall_mat,
             along="z", doors=((d0, d1),))
        cut = GLASS_STYLES[glass]
        if cut is not None:
            sill, head, panes, inset = cut
            for i, (a, b) in enumerate(((iz0 + inset, d0 - 1.0), (d1 + 1.0, iz1 - inset))):
                if b - a > 4.0:
                    glazing(f"Shopfront{i + 1}", (fw0 + 0.4, fw1 - 0.4, a, b,
                                                  FLOOR_1 + sill, FLOOR_1 + head),
                            along="z", panes=panes)
        # See the note in _shopfront: a different rhythm upstairs is what makes
        # two storeys read as two storeys, and one band per storey above that.
        _n = 2
        while storey_floor(_n) < top:
            _fy = storey_floor(_n)
            glazing(f"Upper{_n}", (fw0 + 0.4, fw1 - 0.4, iz0 + 4.0, iz1 - 4.0,
                                   _fy + 3.0, _fy + 10.0), along="z", panes=3)
            _n += 1
        npz0, npz1 = door_pos - 9.0, door_pos + 9.0
        if front == "west":
            box("Nameplate", (x0 - 0.6, x0 - 0.1, npz0, npz1, SIGN_Y0, SIGN_Y1),
                wall_color, BRICK, children=sign(name, sign_face, color=(250, 246, 234), size=64))
        else:
            box("Nameplate", (x1 + 0.1, x1 + 0.6, npz0, npz1, SIGN_Y0, SIGN_Y1),
                wall_color, BRICK, children=sign(name, sign_face, color=(250, 246, 234), size=64))
        if awning is not None:
            a0 = x0 - 3.6 if front == "west" else x1
            a1 = x0 - 0.4 if front == "west" else x1 + 3.6
            box("Awning", (a0, a1, iz0 + 2.0, iz1 - 2.0,
                           FLOOR_1 + 8.0, FLOOR_1 + 10.5), awning, FABRIC, collide=False)
            box("AwningTrim", (a1, a1 + 0.2 if front == "west" else a1 - 0.2,
                               iz0 + 2.0, iz1 - 2.0, FLOOR_1 + 8.0, FLOOR_1 + 10.5),
                AWNING_CREAM, FABRIC, collide=False)


def street_fittings(name, x0, x1, z0, z1, front, trade):
    """What is inside a storefront, chosen by what it sells.

    `trade` is the shop's business. It used to be the same argument as the
    *front type* -- the shape of the front wall -- and because every call site
    passed the front type, every branch here except "garage" and the fallback
    was unreachable. The cafe, the restaurant and the pizzeria had furniture
    written for them that no shop in the city ever received; all eighteen main
    street stores were built with the same supermarket gondola in them. That is
    most of why they were impossible to tell apart: they were not just similar
    outside, they were identical inside. See SHOP_FRONTS.

    A trade with no branch here falls through to a plain counter rather than
    erroring, because an unfurnished shop is a cosmetic problem and refusing to
    generate the city over one is not proportionate -- but every trade named in
    SHOP_FRONTS does have a branch, and adding one to that table without one
    here means a shop that looks empty through its own window."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2

    # The counter straddles the place point, which is always 2.0 studs inside
    # the front wall -- so wherever the door is, "standing at the counter" and
    # the spot the game puts you down on are the same place. The north strip
    # used to get an east-wall counter regardless of its south-facing door,
    # which put its tills against a side wall the player never walked to.
    def counter_at(half):
        if front == "west":
            return (x0 + 1.2, x0 + 3.6, cz - half, cz + half)
        if front == "east":
            return (x1 - 3.6, x1 - 1.2, cz - half, cz + half)
        if front == "south":
            return (cx - half, cx + half, z0 + 1.2, z0 + 3.6)
        return (cx - half, cx + half, z1 - 3.6, z1 - 1.2)

    def counter(half, label="Counter"):
        a, b, c, d = counter_at(half)
        box(label, (a, b, c, d, FLOOR_1, FLOOR_1 + 3.0), DESK_TOP, WOOD)

    with group(f"{name}Fittings"):
        if trade == "cafe":
            counter(5.0)
            for dz in (-6.0, 6.0):
                desk(cx, cz + dz, FLOOR_1, side="north", width=4.0, depth=2.4, label="Table")
        elif trade == "restaurant":
            # No counter at all: a restaurant is a room full of laid tables, and
            # the absence of the serving bar every other shop has is the thing
            # that says so through the window.
            for dx in (-6.0, 0.0, 6.0):
                for dz in (-7.0, 7.0):
                    desk(cx + dx, cz + dz, FLOOR_1, side="north", width=4.0, depth=2.4, label="Table")
                    chair(cx + dx, cz + dz - 2.4, FLOOR_1, side="north")
        elif trade == "pizzeria":
            counter(6.0)
            box("Oven", (ix1 - 6.0, ix1 - 2.0, cz - 3.0, cz + 3.0,
                         FLOOR_1, FLOOR_1 + 7.0), (168, 84, 68), BRICK)
            for dz in (-7.0, 7.0):
                desk(cx + 2.0, cz + dz, FLOOR_1, side="north", width=4.0, depth=2.4, label="Table")
        elif trade == "market":
            # Aisles rather than one gondola against the wall. A market is the
            # one shop whose insides should be visible as *depth* from the
            # street -- rows going away from you, not a single shelf.
            counter(2.6)
            for i in range(3):
                ax = ix0 + 6.0 + i * 5.5
                if ax + 3.0 > ix1 - 2.0:
                    break
                box(f"Aisle{i}", (ax, ax + 3.0, iz0 + 4.0, iz1 - 4.0,
                                  FLOOR_1, FLOOR_1 + 6.0), SHELF, METAL)
                box(f"AisleStock{i}", (ax + 0.2, ax + 2.8, iz0 + 4.4, iz1 - 4.4,
                                       FLOOR_1 + 1.8, FLOOR_1 + 3.4), STOCK, PLANKS, collide=False)
        elif trade == "shelves":
            # Tall wall units on both sides and nothing in the middle: the
            # bookshop/electronics/toyshop silhouette, a canyon rather than aisles.
            counter(2.6)
            for side, (a, b) in (("N", (iz0 + 2.0, iz0 + 5.0)), ("S", (iz1 - 5.0, iz1 - 2.0))):
                box(f"Shelf{side}", (ix0 + 4.0, ix1 - 2.0, a, b,
                                     FLOOR_1, FLOOR_1 + 9.0), SHELF, PLANKS)
                box(f"ShelfStock{side}", (ix0 + 4.4, ix1 - 2.4, a + 0.3, b - 0.3,
                                          FLOOR_1 + 2.0, FLOOR_1 + 7.5), STOCK, PLANKS, collide=False)
        elif trade == "racks":
            # Free-standing rails at head height. Nothing else in this city is
            # waist-high-and-hollow, so a clothing rail reads as clothing.
            counter(2.6)
            for i in range(3):
                rz = cz - 7.0 + i * 7.0
                box(f"Rail{i}", (ix0 + 5.0, ix1 - 3.0, rz - 0.2, rz + 0.2,
                                 FLOOR_1 + 6.0, FLOOR_1 + 6.4), STEEL, METAL, collide=False)
                box(f"Hanging{i}", (ix0 + 5.4, ix1 - 3.4, rz - 1.2, rz + 1.2,
                                    FLOOR_1 + 2.0, FLOOR_1 + 6.0), STOCK, FABRIC, collide=False)
        elif trade == "workshop":
            # Timber on the floor and a bench, not a shelf of packets. The
            # hardware shop is the only trade on the street with stock stacked
            # rather than displayed, which is what the high glass band is for.
            counter(2.6)
            for i in range(4):
                sz = iz0 + 5.0 + i * 4.0
                if sz + 2.5 > iz1 - 3.0:
                    break
                box(f"Timber{i}", (ix0 + 6.0, ix1 - 3.0, sz, sz + 2.5,
                                   FLOOR_1, FLOOR_1 + 4.0 + i * 0.6), STOCK, PLANKS)
            box("Bench", (ix1 - 6.0, ix1 - 2.0, cz - 4.0, cz + 4.0,
                          FLOOR_1 + 2.4, FLOOR_1 + 2.8), DESK_TOP, WOOD)
        elif trade == "salon":
            # Chairs in a row facing a mirrored wall. The mirrors are what make
            # this legible from outside -- a row of seats alone is a waiting room.
            counter(2.6)
            for i in range(3):
                sz = cz - 6.0 + i * 6.0
                chair(ix1 - 6.0, sz, FLOOR_1, side="east")
                box(f"Mirror{i}", (ix1 - 1.8, ix1 - 1.4, sz - 2.0, sz + 2.0,
                                   FLOOR_1 + 4.0, FLOOR_1 + 10.0), GLAZING, GLASS,
                    transparency=0.2, collide=False)
        elif trade == "studio":
            # One chair, one bench, one lamp, and a lot of empty floor. A tattoo
            # studio is the emptiest shop on the street and that is the point:
            # everything else is full of stock and this one is full of room.
            counter(2.6)
            chair(cx + 2.0, cz, FLOOR_1, side="north")
            box("Bed", (cx - 1.0, cx + 5.0, cz + 2.0, cz + 4.4,
                        FLOOR_1 + 2.0, FLOOR_1 + 2.6), SEAT, FABRIC)
            box("LampArm", (cx + 4.0, cx + 4.4, cz + 1.0, cz + 4.0,
                            FLOOR_1 + 8.0, FLOOR_1 + 8.4), STEEL, METAL, collide=False)
        elif trade == "counter":
            # A pharmacy: a long dispensing counter and the stock behind it,
            # out of reach. The one shop where the goods are on the staff's side.
            counter(7.0)
            box("Dispensary", (ix1 - 4.5, ix1 - 2.0, iz0 + 3.0, iz1 - 3.0,
                               FLOOR_1, FLOOR_1 + 8.0), SHELF, METAL)
            box("DispensaryStock", (ix1 - 4.3, ix1 - 2.2, iz0 + 3.4, iz1 - 3.4,
                                    FLOOR_1 + 2.0, FLOOR_1 + 6.5), STOCK, PLANKS, collide=False)
        elif trade == "desk":
            desk(cx, cz - 2.0, FLOOR_1, side="north", width=5.0, depth=2.6, label="Desk")
            chair(cx, cz, FLOOR_1, side="south")
        elif trade == "garage":
            box("CarBody", (cx - 4.0, cx + 4.0, cz - 2.0, cz + 2.0,
                            FLOOR_1 + 2.4, FLOOR_1 + 4.6), (60, 64, 120), SMOOTH)
            box("Workbench", (x1 - 8.0, x1 - 3.0, cz - 3.0, cz + 1.0,
                              FLOOR_1 + 2.4, FLOOR_1 + 2.8), DESK_TOP, WOOD)
        elif trade == "laundromat":
            for i in range(4):
                x = x0 + 4.0 + i * 5.0
                box(f"Washer{i}", (x, x + 2.4, cz - 2.0, cz + 2.0,
                                   FLOOR_1, FLOOR_1 + 3.6), (216, 218, 222), METAL)
        else:
            counter(2.6)
            box("Gondola", (ix1 - 5.0, ix1 - 2.0, iz0 + 4.0, iz1 - 4.0,
                            FLOOR_1, FLOOR_1 + 7.5), SHELF, METAL)
            box("Stock", (ix1 - 4.8, ix1 - 2.2, iz0 + 4.4, iz1 - 4.4,
                          FLOOR_1 + 1.8, FLOOR_1 + 3.4), STOCK, PLANKS, collide=False)
        ceiling_light(cx, cz, CEIL_1)


# ---------------------------------------------------------------------------
# What stands on the main street when a shop does not
# ---------------------------------------------------------------------------
#
# Four of these, and they are the whole reason four shops moved into the mall.
# A shopping street is not a continuous run of frontage -- it is shops with
# things between them, and the things between them are what tell a player where
# they are. Nineteen storefronts at a constant pitch gave the player one cue
# repeated nineteen times; fifteen storefronts with a terrace, a garden, a
# fountain and a row of kiosks between them gives six bands that can be told
# apart from the far pavement.
#
# All four take the same (z0, z1) a shop would and stand in the same 24-stud
# strip, so the table below can hold them in the same list and the solver does
# not have to know which is which.

STREET_FILLERS = {}   # kind -> builder(x0, x1, z0, z1, label)


def street_filler(kind):
    """Register a main-street filler under the name the table uses."""
    def wrap(fn):
        STREET_FILLERS[kind] = fn
        return fn
    return wrap


@street_filler("terrace")
def street_terrace(x0, x1, z0, z1, label):
    """Outdoor tables. Goes at the eating end, between the restaurants, which is
    the one place on the street where the tables have a reason to be."""
    dining_terrace(x0 + 1.0, x1 - 1.0, z0, z1, label=label)


@street_filler("garden")
def street_garden(x0, x1, z0, z1, label):
    """A pocket garden: lawn, a path through it to the pavement, four trees and
    two benches facing the street."""
    cz = (z0 + z1) / 2
    with group(label):
        box("Lawn", (x0, x1, z0, z1, GROUND_BOTTOM,
                     CITY_GRASS_TOP + GRASS_LIFT), LAWN, GRASS)
        box("Path", (x0, x1, cz - 3.0, cz + 3.0, GROUND_BOTTOM, GROUND),
            PATH_STONE, PEBBLE)
        for tz in (z0 + 6.0, z1 - 6.0):
            for tx in (x0 + 7.0, x1 - 7.0):
                tree(tx, tz, GROUND, height=14.0, spread=9.0)
        bench(x0 + 5.0, cz - 5.0, 1)
        bench(x0 + 5.0, cz + 5.0, 1)
        street_lamp(x1 - 3.0, cz, -1, floor=GROUND)


@street_filler("plaza")
def street_plaza(x0, x1, z0, z1, label):
    """A paved square with a fountain in it. The one place on the street a
    player would stop rather than pass through, so it gets the water."""
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    with group(label):
        box("Paving", (x0, x1, z0, z1, GROUND_BOTTOM, GROUND),
            PATH_STONE, PEBBLE)
        box("Basin", (cx - 7.0, cx + 7.0, cz - 7.0, cz + 7.0,
                      GROUND, GROUND + 2.4), BANK_MARBLE, MARBLE)
        box("Water", (cx - 5.6, cx + 5.6, cz - 5.6, cz + 5.6,
                      GROUND + 1.6, GROUND + 2.2), WATER, SMOOTH,
            transparency=0.35, collide=False)
        box("Jet", (cx - 1.0, cx + 1.0, cz - 1.0, cz + 1.0,
                    GROUND + 2.2, GROUND + 7.0), WATER, SMOOTH,
            transparency=0.55, collide=False)
        for bz in (cz - 10.0, cz + 10.0):
            bench(cx, bz, 1 if bz < cz else -1, floor=GROUND)
        for lz in (z0 + 4.0, z1 - 4.0):
            street_lamp(x1 - 3.0, lz, -1, floor=GROUND)


@street_filler("kiosks")
def street_kiosks(x0, x1, z0, z1, label):
    """Two kiosks and a tree between them: a newsstand and a flower cart.

    Small buildings, on purpose. Everything else on this street is thirty studs
    of frontage two storeys high, and a pair of huts a player can see over is
    the only thing on it that gives the row a sense of scale."""
    cz = (z0 + z1) / 2
    with group(label):
        box("Paving", (x0, x1, z0, z1, GROUND_BOTTOM, GROUND),
            PATH_STONE, PEBBLE)
        for i, (kz, colour, awning) in enumerate(
                ((z0 + 5.0, (236, 226, 206), AWNING_MUSTARD),
                 (z1 - 13.0, (222, 232, 224), AWNING_GREEN))):
            kx0, kx1 = x0 + 8.0, x0 + 18.0
            with group(f"Kiosk{i}"):
                box("Body", (kx0, kx1, kz, kz + 8.0, GROUND, GROUND + 9.0),
                    colour, SMOOTH)
                box("Counter", (kx0 - 2.4, kx0, kz + 1.0, kz + 7.0,
                                GROUND + 3.6, GROUND + 4.2), DESK_TOP, WOOD)
                box("Roof", (kx0 - 1.0, kx1 + 1.0, kz - 1.0, kz + 9.0,
                             GROUND + 9.0, GROUND + 10.0), ROOF_GREY, SLATE)
                box("Awning", (kx0 - 5.0, kx0 - 0.4, kz, kz + 8.0,
                               GROUND + 7.4, GROUND + 8.6), awning, FABRIC,
                    collide=False)
        tree((x0 + x1) / 2 + 4.0, cz, GROUND, height=15.0, spread=10.0)
        street_lamp(x1 - 3.0, cz, -1, floor=GROUND)


# The street, band by band. Widths, rooflines, awnings and glass all live in
# SHOP_FRONTS -- this is only what stands where, in order along z.
#
# An entry is either a shop, `("shop", pid, label)`, or a filler,
# `("filler", kind, width)`. Both take frontage out of the band, which is the
# whole point: a filler is not a leftover gap, it is a slot the solver has to
# find room for, and the moment it stops fitting the band says so rather than
# quietly closing up.
#
# **The trades are deliberately not sorted into themed triples any more.** They
# were -- an eating band, a chairs band, a motor band, and three bands of
# whatever was left -- which is a plausible way to write the table and a bad way
# to walk down the street: every band was three shops of one kind, so the whole
# street was six things rather than fifteen. The two ends keep their theme,
# because a restaurant strip and a garage end are real, and the middle is mixed.
# Where the main street's south end is: the city's own south edge, the same
# number the financial district starts from.
MAIN_Z0 = 60.0


def main_band(k):
    """The clear frontage in band `k`: from the far pavement of the cross street
    below it to the near pavement of the one above.

    Derived, because four of the six were typed and three of those were wrong.
    They ran eight studs into the cross street's own north pavement and got away
    with it for exactly as long as the gap solver happened to push the first
    shop clear -- which it stopped doing the moment the shops in a band changed,
    and check_city reported it as `C0PavN cuts 0.5 studs into
    supermarket.WallSouth1`. The sixth carried a comment claiming its pavement
    ended at 826 when the numbers above say 818: a measurement typed once,
    never re-measured, and eight studs of frontage quietly lost with it.
    """
    z0 = MAIN_Z0 if k == 0 else CS[k - 1] + CS_W[k - 1] + CS_WALK
    return z0, CS[k] - CS_WALK


MAIN_STREET = [
    (main_band(0), [
        ("shop", "cafe", "CAFE ASTER"),
        ("shop", "restaurant", "TORRE RESTAURANT"),
        ("filler", "terrace", 30.0),
        ("shop", "pizzeria", "VESUVIO PIZZERIA"),
    ]),
    (main_band(1), [
        ("shop", "supermarket", "MIDWAY MARKET"),
        ("filler", "garden", 34.0),
        ("shop", "pharmacy", "FIRST PHARMACY"),
    ]),
    (main_band(2), [
        ("shop", "florist", "STEM & BLOOM"),
        ("filler", "plaza", 30.0),
        ("shop", "hardware", "IRON & WOOD"),
    ]),
    (main_band(3), [
        ("shop", "clothing_store", "THREAD & CO"),
        ("filler", "kiosks", 26.0),
        ("shop", "laundromat", "CLEAN SPIN"),
    ]),
    (main_band(4), [
        ("shop", "barbershop", "THE CLIPPERS"),
        ("shop", "salon", "LUMIERE SALON"),
        ("shop", "tattoo_parlor", "INKWELL TATTOO"),
    ]),
    (main_band(5), [
        ("shop", "vet", "ANIMAL CLINIC"),
        ("shop", "gas_station", "TANK & GO"),
        ("shop", "car_wash", "WASH & GLIDE"),
    ]),
]


def shop_front(pid):
    """One row of SHOP_FRONTS, loudly. A storefront missing from that table
    would otherwise be built at some default width and quietly become the
    twentieth identical box on the street, which is the exact defect the table
    exists to remove."""
    row = SHOP_FRONTS.get(pid)
    if row is None:
        raise KeyError(
            f"storefront {pid!r} has no row in SHOP_FRONTS. Add one -- trade, "
            f"width, storeys, awning, glass -- or it will not be distinguishable "
            f"from its neighbours."
        )
    return row


def slot_width(slot):
    """How much frontage one entry in a MAIN_STREET band takes."""
    if slot[0] == "shop":
        return shop_front(slot[1])[1]
    return slot[2]


def place_main_street():
    colour = 0
    for (z0, z1), slots in MAIN_STREET:
        n = len(slots)
        widths = [slot_width(s) for s in slots]
        gap = (z1 - z0 - sum(widths)) / (n + 1)
        # Checked rather than trusted. The bands are fixed by the cross streets
        # either side of them, so a width raised by four studs comes straight
        # out of the gaps -- and the first shop to overrun would do it silently,
        # by growing into its neighbour's wall.
        if gap < MIN_SHOP_GAP:
            raise ValueError(
                f"main street band z {z0}..{z1} is over-subscribed: "
                f"{n} slots totalling {sum(widths)} studs leave a {gap:.1f}-stud gap, "
                f"under the {MIN_SHOP_GAP} minimum. Narrow one of "
                f"{[s[1] for s in slots]} in SHOP_FRONTS, or narrow a filler in "
                f"MAIN_STREET."
            )
        cursor = z0 + gap
        for slot, width in zip(slots, widths):
            sz0 = cursor
            sz1 = sz0 + width
            cursor = sz1 + gap
            if slot[0] == "filler":
                kind = slot[1]
                if kind not in STREET_FILLERS:
                    raise KeyError(
                        f"main street band z {z0}..{z1} asks for a {kind!r} filler "
                        f"and nothing is registered under that name. Decorate a "
                        f"builder with @street_filler({kind!r})."
                    )
                STREET_FILLERS[kind](MAIN_X0, MAIN_X1, sz0, sz1,
                                     f"MainStreet{kind.title()}{sz0:.0f}")
                continue
            _, pid, label = slot
            trade, _w, storeys, awning, glass = shop_front(pid)
            door_z = (sz0 + sz1) / 2
            wall_color = STORE_WALLS[colour % len(STORE_WALLS)]
            colour += 1
            ftype = "garage" if trade == "garage" else "shop"
            with group(pid):
                storefront(label, MAIN_X0, MAIN_X1, sz0, sz1, door_z, wall_color,
                           front="west", front_type=ftype, storeys=storeys,
                           awning=awning, glass=glass)
                street_fittings(pid, MAIN_X0, MAIN_X1, sz0, sz1, "west", trade)
            place_point(pid, MAIN_X0 + 2.0, door_z, FLOOR_1,
                        f"the {label.lower()}, by the counter")


place_main_street()


# ---------------------------------------------------------------------------
# Car dealership (replaces the generic garage slot in MAIN_STREET)
# ---------------------------------------------------------------------------

# The dealership anchors the west end of the civic precinct, in line with the
# civic row (z 988..1032) and stopping eight studs short of its first slot at
# x=89 so the forecourt reads as a gap rather than a shared wall. Its west face
# is at 49, one stud clear of the connector's east pavement (which ends at 48).
# It is the one
# building in the band that is not a civic shopfront, which is why it gets the
# corner instead of a slot: a forecourt full of cars wants to be seen off the
# connector, not buried mid-row.
CAR_Z0, CAR_Z1 = 988.0, 1032.0
CAR_X0, CAR_X1 = 49.0, 83.0


def car_dealership(x0, x1, z0, z1, name, brand):
    """A proper car dealership: glass showroom front, three display cars on the
    forecourt, and two service bays in the rear. The place point stays at
    ``auto_dealer`` so the job wiring does not move."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    cx = (x0 + x1) / 2
    cz = (z0 + z1) / 2

    with group("auto_dealer"):
        # --- Showroom (south half, z0..mid) ---
        mid_z = (z0 + z1) / 2
        show_x0, show_x1 = x0, x1
        show_z0, show_z1 = z0, mid_z + WALL
        show_ix0, show_ix1 = show_x0 + WALL, show_x1 - WALL
        show_iz0, show_iz1 = show_z0 + WALL, show_z1 - WALL
        show_cx = (show_x0 + show_x1) / 2
        show_cz = (show_z0 + show_z1) / 2

        with group("Showroom"):
            # To `mid_z`, not to `show_z1`. The two halves share a party wall and
            # so overlap by its thickness everywhere else, which is right for
            # walls and roofs and wrong for floors: both halves poured a slab
            # over the same three studs of it, in the same plane. The floors
            # abut on the centreline and the wall stands across the join.
            box("Slab", (show_x0, show_x1, show_z0, mid_z,
                         FLOOR_1 - SLAB, FLOOR_1), FLOOR_INDOOR, MARBLE)
            box("Roof", (show_x0, show_x1, show_z0, show_z1,
                         CEIL_1, CEIL_1 + SLAB), ROOF_GREY, SLATE)
            # Side walls.
            wall("WallNorth", (show_x0, show_x1, show_iz1, show_z1,
                               FLOOR_1, CEIL_1), STORE_WALLS[0], BRICK, along="x")
            wall("WallWest", (show_x0, show_ix0, show_z0, show_z1,
                              FLOOR_1, CEIL_1), STORE_WALLS[0], BRICK, along="z")
            wall("WallEast", (show_ix1, show_x1, show_z0, show_z1,
                              FLOOR_1, CEIL_1), STORE_WALLS[0], BRICK, along="z")
            # Glass front (south face): full-width glazing, no door cut — the
            # customer walks through the open front into the forecourt.
            glazing("Front", (show_x0 + 1.0, show_x1 - 1.0, show_z0 + 0.4,
                              show_iz0 - 0.4, FLOOR_1 + 1.0, CEIL_1),
                    along="x", panes=6)
            # Nameplate above the glass.
            box("SignPlate", (show_x0 + 2.0, show_x1 - 2.0, show_z0 - 1.6,
                              show_z0 - 0.4, CEIL_1 + SLAB, 24.0),
                RISE_FRAME, SMOOTH,
                children=sign(brand, "front", color=(250, 246, 234), size=64))
            # Showroom desk.
            desk(show_cx, show_iz1 - 3.0, FLOOR_1, side="north",
                 width=6.0, depth=2.4, label="ShowroomDesk")
            chair(show_cx, show_iz1 - 0.5, FLOOR_1, side="south", label="ShowroomChair")
            ceiling_light(show_cx, show_cz, CEIL_1)

        # --- Service bays (north half, mid..z1) ---
        svc_z0, svc_z1 = mid_z - WALL, z1
        svc_ix0, svc_ix1 = x0 + WALL, x1 - WALL
        svc_iz0, svc_iz1 = svc_z0 + WALL, svc_z1 - WALL
        svc_cx = (x0 + x1) / 2

        with group("ServiceBays"):
            box("Slab", (x0, x1, mid_z, svc_z1, FLOOR_1 - SLAB, FLOOR_1),
                FLOOR_INDOOR, MARBLE)
            box("Roof", (x0, x1, svc_z0, svc_z1, CEIL_1, CEIL_1 + SLAB),
                ROOF_GREY, SLATE)
            wall("WallNorth", (x0, x1, svc_iz1, svc_z1, FLOOR_1, CEIL_1),
                 STORE_WALLS[2], BRICK, along="x")
            wall("WallWest", (x0, svc_ix0, svc_z0, svc_z1, FLOOR_1, CEIL_1),
                 STORE_WALLS[2], BRICK, along="z")
            wall("WallEast", (svc_ix1, x1, svc_z0, svc_z1, FLOOR_1, CEIL_1),
                 STORE_WALLS[2], BRICK, along="z")
            # Two roll-up bays on the north wall.
            bay_w = 6.0
            for i, bx in enumerate((svc_cx - 8.0, svc_cx + 8.0)):
                by0, by1 = bx - bay_w / 2, bx + bay_w / 2
                wall(f"BayWall{i}", (by0, by1, svc_iz1, svc_z1,
                                     FLOOR_1, CEIL_1), STORE_WALLS[2], BRICK,
                     along="x", doors=((by0 + 0.5, by1 - 0.5),))
                box(f"Roller{i}", (by0 + 0.5, by1 - 0.5, svc_iz1 + 0.3,
                                   svc_z1 - 0.3, FLOOR_1 + 3.0,
                                   FLOOR_1 + 13.0), STEEL, METAL, collide=False)
            # Service bay interior: workbench and jack.
            box("Workbench", (svc_ix0 + 1.0, svc_ix0 + 5.0,
                              svc_iz0 + 2.0, svc_iz0 + 6.0,
                              FLOOR_1, FLOOR_1 + 2.8), DESK_TOP, WOOD)
            box("Jack", (svc_cx - 1.5, svc_cx + 1.5,
                         svc_iz0 + 8.0, svc_iz0 + 10.0,
                         FLOOR_1, FLOOR_1 + 1.6), STEEL, METAL)
            ceiling_light(svc_cx, (svc_z0 + svc_z1) / 2, CEIL_1)

        # --- Forecourt (south of showroom, z0-8..z0) ---
        with group("Forecourt"):
            box("Asphalt", (x0 - 4.0, x1 + 4.0, z0 - 8.0, z0,
                            GROUND_BOTTOM, GROUND), TARMAC, SMOOTH)
            # Three display cars on low platforms.
            for i, (cx_i, color) in enumerate(zip(
                    (cx - 8.0, cx, cx + 8.0), CAR_COLORS)):
                with group(f"Car{i + 1}"):
                    box("Platform", (cx_i - 3.0, cx_i + 3.0,
                                      z0 - 8.0, z0, GROUND, GROUND + 0.4),
                        PAVING_GREY, SMOOTH)
                    box("Body", (cx_i - 2.4, cx_i + 2.4,
                                  z0 - 6.0, z0 + 2.0, GROUND + 0.4, GROUND + 2.0),
                        color, SMOOTH, tags=[CAR_TAG],
                        attrs={CAR_MODEL_ATTR: brand})
                    box("RoofCar", (cx_i - 1.8, cx_i + 1.8,
                                     z0 - 4.0, z0 + 1.0, GROUND + 2.0, GROUND + 3.0),
                        color, SMOOTH, tags=[CAR_TAG],
                        attrs={CAR_MODEL_ATTR: brand})
            # Nameplate on the forecourt.
            box("ForeSign", (cx - 6.0, cx + 6.0, z0 - 4.0, z0 + 0.0,
                             GROUND + 0.05, GROUND + 0.8),
                TRIM_WHITE, SMOOTH,
                children=sign(brand, "top", color=(40, 40, 44), size=48))

    place_point("auto_dealer", cx, z0 + 2.0, FLOOR_1,
                f"the {brand.lower()}, by the showroom desk")


car_dealership(CAR_X0, CAR_X1, CAR_Z0, CAR_Z1, "AUTOPIA", "Autopia")


# ---------------------------------------------------------------------------
# Fade district: mid-rise offices between the financial district and the
# residential grid. Taller near the south (5-6 storeys), shorter near the
# north (3-4 storeys), so the skyline steps down into the houses.
# ---------------------------------------------------------------------------

FADE_SLAB = 1.0
FADE_STOREY = 15.0


# The mid-rise district's own materials, and the reason it has a list at all.
#
# Every one of these buildings used to be the same three colours in the same two
# materials -- one glass, one marble, one concrete roof -- so sixteen of them
# across the four fade blocks were one building stamped sixteen times. The
# sculpted towers on the waterfront got all the variety in the city and the
# ordinary blocks between them got none, which is backwards: the sculpted ones
# are four hundred studs away and read as a silhouette, and these are the ones a
# player actually walks past.
#
# Three axes, all indexed off the building's own number so the pattern never
# repeats on one street: the curtain wall's tint, and the cladding the lobby is
# faced in -- a colour and a *material*, because at ten studs the material is
# the thing the eye is reading and a wall of flat colour reads as unfinished.
FADE_GLASS = [
    (146, 180, 206),
    (172, 202, 222),
    (124, 158, 188),
    (188, 214, 230),
]
FADE_CLADDING = [
    (RISE_MARBLE, MARBLE),        # polished stone
    ((222, 214, 200), LIMESTONE), # sawn limestone
    ((198, 200, 204), CONCRETE),  # board-marked concrete
    ((214, 196, 178), GRANITE),   # warm granite
]


def fade_office(no, x0, x1, z0, z1, storeys, name="FadeOffice", front="south"):
    """A mid-rise office block: flat roof, glass curtain wall, ground-floor
    lobby. `storeys` is the number of 15-stud floors above the lobby.

    `front` is which street the door, the sign and the place point face, the
    same way `shaped_tower` takes one and for the same reason: a block two rows
    deep has a north row whose street is above it, and an office that always
    opened south put half of them face to face down an alley."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    cx = (x0 + x1) / 2
    cz = (z0 + z1) / 2
    # "Outward, toward the street this office faces". See `shaped_tower`.
    s = 1.0 if front == "south" else -1.0
    fz, ifz = (z0, iz0) if front == "south" else (z1, iz1)
    bz, ibz = (z1, iz1) if front == "south" else (z0, iz0)
    lobby_h = 18.0
    tower_top = FLOOR_1 + lobby_h + (storeys - 1) * (FADE_STOREY + FADE_SLAB)
    glass = FADE_GLASS[no % len(FADE_GLASS)]
    clad, clad_mat = FADE_CLADDING[(no // 2) % len(FADE_CLADDING)]
    neon = DOWNTOWN_NEON[no % len(DOWNTOWN_NEON)]

    with group(f"{name}_{no}"):
        box("Slab", (x0, x1, z0, z1, FLOOR_1 - FADE_SLAB, FLOOR_1),
            FLOOR_INDOOR, MARBLE)
        # Glass tower body.
        box("Tower", (x0 + 2.0, x1 - 2.0, z0 + 2.0, z1 - 2.0,
                      FLOOR_1 + lobby_h, tower_top),
            glass, GLASS, transparency=0.5, collide=False)
        # The floor lines. One thin band per storey, standing a third of a stud
        # proud of the glass -- the cheapest thing on this building and the one
        # that makes it read as an office rather than as a tinted block, because
        # a curtain wall is horizontal and a plain box has no scale at all.
        for _f in range(1, storeys):
            _fy = FLOOR_1 + lobby_h + _f * (FADE_STOREY + FADE_SLAB) - FADE_SLAB
            box(f"Floorline{_f}", (x0 + 1.7, x1 - 1.7, z0 + 1.7, z1 - 1.7,
                                   _fy, _fy + FADE_SLAB),
                clad, SMOOTH, collide=False)
        # Flat roof slab.
        box("Roof", (x0 + 2.0, x1 - 2.0, z0 + 2.0, z1 - 2.0,
                     tower_top, tower_top + FADE_SLAB),
            (72, 76, 82), CONCRETE)
        # Small parapet.
        box("Parapet", (x0 + 1.0, x1 - 1.0, z0 + 1.0, z1 - 1.0,
                        tower_top + FADE_SLAB, tower_top + FADE_SLAB + 2.0),
            (90, 94, 100), CONCRETE)
        # Lobby walls.
        wall("WallBack", (x0, x1) + span(ibz, bz) + (FLOOR_1, FLOOR_1 + lobby_h),
             clad, clad_mat, along="x")
        wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, FLOOR_1 + lobby_h),
             clad, clad_mat, along="z")
        wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, FLOOR_1 + lobby_h),
             clad, clad_mat, along="z")
        door_z0, door_z1 = cx - DOORWAY / 2, cx + DOORWAY / 2
        wall("WallFront", (x0, x1) + span(fz, ifz) + (FLOOR_1, FLOOR_1 + lobby_h),
             clad, clad_mat, along="x", doors=((door_z0, door_z1),))
        # Glazed in the front wall's own thickness. It used to be given
        # `iz0 + 0.4 .. z1 - 0.4` -- the whole interior depth -- which `glazing`
        # reads as four panes each fifty studs deep, so the lobby was filled
        # with translucent slabs rather than fronted by a window.
        glazing("LobbyWin", (x0 + 1.5, x1 - 1.5) + span(fz, ifz)
                + (FLOOR_1 + 1.5, FLOOR_1 + lobby_h - 1.0),
                along="x", panes=4)
        glass_doors("Door", (door_z0, door_z1) + span(fz, ifz)
                    + (FLOOR_1, FLOOR_1 + DOOR_HEIGHT), along="x")
        # The highlight, on the lobby's own head rather than on the roof. Same
        # rule as the towers: colour at the door, white in the sky.
        box("EntranceNeon", (x0 + 1.2, x1 - 1.2)
            + span(fz - s * 0.5, fz + s * 0.3)
            + (FLOOR_1 + lobby_h - 1.4, FLOOR_1 + lobby_h - 0.6),
            neon, NEON, collide=False,
            children=point_light(neon, 1.3, 32.0))
        box("Reception", (ix0 + 4.0, ix0 + 10.0)
            + span(ibz - s * 6.0, ibz - s * 2.0)
            + (FLOOR_1, FLOOR_1 + 3.0), DESK_TOP, WOOD)
        box("Sofa", (ix1 - 8.0, ix1 - 3.0)
            + span(ibz - s * 6.0, ibz - s * 2.0)
            + (FLOOR_1 + 1.2, FLOOR_1 + 2.0), (120, 140, 110), FABRIC)
        ceiling_light(cx, cz, FLOOR_1 + lobby_h - 0.5)
        box("Sign", (cx - 8.0, cx + 8.0)
            + span(fz - s * 1.6, fz - s * 0.6)
            + (FLOOR_1 + 12.0, FLOOR_1 + 14.0),
            RISE_FRAME, SMOOTH,
            children=sign(f"FADE {no}", "front" if front == "south" else "back",
                          color=(250, 246, 234), size=52))

    place_point(f"fade_{no}", cx, fz + s * 2.0, FLOOR_1,
                f"fade {no}, the lobby")


# ---------------------------------------------------------------------------
# The other half of downtown
# ---------------------------------------------------------------------------

# Every building south of the Circle was drawn from one of two vocabularies: a
# sculpted glass tower on the waterfront, a glass mid-rise on the band behind
# it. Twenty of the first and eight of the second, sorted into two solid stripes
# -- which is the whole reason downtown reads as a rendering rather than as a
# place. Cities are not sorted. What makes a real downtown look built over time
# is that the block beside the glass tower is eighty years older than it, in
# stone, two thirds its height, and nobody ever knocked it down.
#
# So this is that building, and it goes into *both* districts rather than into a
# third stripe of its own: a handful of them among the waterfront towers, and
# one of the two slots on every fade block. Swapping in one direction only would
# just move the seam.
#
# Deliberately not brick and deliberately not grey. Warm sawn stone is what the
# era actually built in, it is the one family that sits beside a blue-grey
# curtain wall without fighting it, and grey masonry downtown is the exact thing
# that had to be taken off the tower podiums.
MASONRY_BASE_H = 22.0        # retail base; taller than an office lobby on purpose
MASONRY_STOREY = 13.0        # a pre-war floor is shorter than a modern one
MASONRY_WINDOW_H = 7.0       # the punched opening inside that floor
MASONRY_CORNICE_H = 2.4
MASONRY_CAP_H = 7.0
# Where the shaft steps back, as a fraction of its storeys. Safe range 0.5..0.8:
# below a half the building is a plinth with a tower on it, above four fifths
# the setback is a lip rather than a step.
MASONRY_SETBACK_FRAC = 0.62
MASONRY_INSET = 3.5          # how far it steps back when it does
MASONRY_PIERS = 4            # piers per street face; 0 leaves a ribbon window
MASONRY_PIER_W = 3.0
MASONRY_PIER_D = 0.8         # how far a pier stands proud of the glass
MASONRY_WINDOW = (108, 128, 142)
MASONRY_STONE = [
    ((232, 216, 188), LIMESTONE),   # pale sawn limestone
    ((216, 196, 168), GRANITE),     # warm granite
    ((238, 228, 210), MARBLE),      # cream marble
    ((222, 202, 176), CONCRETE),    # cast stone
]


def masonry_skyline(storeys):
    """The top of a masonry tower's cap.

    Split out for the same reason `shaped_tower_skyline` is: the Circle's
    clearance rule reads the tallest thing on the waterfront, and some of those
    are now this rather than a glass tower. A second copy of this arithmetic in
    the assertion is a rule guarding a building nobody built."""
    return (FLOOR_1 + MASONRY_BASE_H + storeys * MASONRY_STOREY
            + MASONRY_CORNICE_H + MASONRY_CAP_H)


def masonry_tower(tag, x0, x1, z0, z1, storeys, tint=0, front="south",
                  slab=False):
    """A pre-war stone tower: a deep retail base, a shaft of punched window
    courses running between piers, a setback with a cornice under it, and a cap.

    `slab` is whether it pours its own ground plate. False on the waterfront,
    where `FinPaving` already covers the whole band -- a second plate at the same
    height over the same footprint is precisely what check 13 exists to find.
    """
    if storeys < 2:
        raise SystemExit(
            f"[gen_city] masonry_tower {tag!r} was asked for {storeys} storeys. "
            f"It needs at least two: the setback splits the shaft in half, and a "
            f"half with no floors in it draws an inside-out box rather than "
            f"failing."
        )
    stone, stone_mat = MASONRY_STONE[tint % len(MASONRY_STONE)]
    trim = dim(stone, 0.88)
    neon = DOWNTOWN_NEON[tint % len(DOWNTOWN_NEON)]
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    # "Outward, toward the street this building faces". See `shaped_tower`.
    s = 1.0 if front == "south" else -1.0
    fz, ifz = (z0, iz0) if front == "south" else (z1, iz1)
    bz, ibz = (z1, iz1) if front == "south" else (z0, iz0)

    base_top = FLOOR_1 + MASONRY_BASE_H
    low_n = min(storeys - 1, max(1, int(round(storeys * MASONRY_SETBACK_FRAC))))
    high_n = storeys - low_n
    mid = base_top + low_n * MASONRY_STOREY
    shaft_top = base_top + storeys * MASONRY_STOREY
    cornice_top = shaft_top + MASONRY_CORNICE_H
    cap_top = cornice_top + MASONRY_CAP_H
    ux0, ux1 = x0 + 1.0 + MASONRY_INSET, x1 - 1.0 - MASONRY_INSET
    uz0, uz1 = z0 + 1.0 + MASONRY_INSET, z1 - 1.0 - MASONRY_INSET

    with group(f"Masonry_{tag}"):
        if slab:
            box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1),
                FLOOR_INDOOR, MARBLE)
        # The base is four walls, not a solid block, for the reason the tower
        # podiums are: a door cut into twenty studs of stone is a doorway into
        # rock, and the place point outside it is somewhere a player can stand
        # but never walk into.
        _door = (cx - DOORWAY / 2, cx + DOORWAY / 2)
        wall("WallBack", (x0, x1) + span(ibz, bz) + (FLOOR_1, base_top),
             stone, stone_mat, along="x")
        wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, base_top),
             stone, stone_mat, along="z")
        wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, base_top),
             stone, stone_mat, along="z")
        wall("WallFront", (x0, x1) + span(fz, ifz) + (FLOOR_1, base_top),
             stone, stone_mat, along="x", doors=(_door,))
        glass_doors("Door", _door + span(fz, ifz)
                    + (FLOOR_1, FLOOR_1 + DOOR_HEIGHT), along="x")
        glazing("BaseWin", (x0 + 2.0, x1 - 2.0) + span(fz, ifz)
                + (FLOOR_1 + DOOR_HEIGHT + 1.5, base_top - 4.5),
                along="x", panes=5)
        box("BaseCornice", (x0 - 0.8, x1 + 0.8, z0 - 0.8, z1 + 0.8,
                            base_top - 1.8, base_top), trim, stone_mat)
        box("Reception", (ix0 + 4.0, ix0 + 10.0)
            + span(ibz - s * 6.0, ibz - s * 2.0) + (FLOOR_1, FLOOR_1 + 3.0),
            DESK_TOP, WOOD)
        ceiling_light(cx, cz, base_top - 2.6)
        # The highlight, on the head of the base and nowhere else. Same rule the
        # glass towers follow, and the reason the old buildings needed one at
        # all: an unlit stone block beside a lit tower does not read as older,
        # it reads as switched off.
        box("EntranceNeon", (x0 + 1.0, x1 - 1.0)
            + span(fz - s * 1.0, fz - s * 0.2)
            + (base_top - 3.4, base_top - 2.6), neon, NEON, collide=False,
            children=point_light(neon, 1.3, 34.0))
        box("Sign", (cx - 8.0, cx + 8.0)
            + span(fz - s * 1.6, fz - s * 0.6)
            + (FLOOR_1 + 13.0, FLOOR_1 + 15.0), trim, SMOOTH,
            children=sign(tag.upper(), "front" if front == "south" else "back",
                          color=(250, 246, 234), size=52))

        # The shaft, in two portions with the upper one stepped back. Each
        # storey is a stone spandrel with a window course over it, both at full
        # footprint -- that horizontal grain is the whole difference between this
        # and a curtain wall. The piers laid over the top of it are what stop the
        # grain reading as a ribbon window, which is the one thing this era did
        # not build.
        for pname, py0, pn, pins in (("Low", base_top, low_n, 1.0),
                                     ("High", mid, high_n, 1.0 + MASONRY_INSET)):
            px0, px1 = x0 + pins, x1 - pins
            pz0, pz1 = z0 + pins, z1 - pins
            pty = py0 + pn * MASONRY_STOREY
            for i in range(pn):
                sy = py0 + i * MASONRY_STOREY
                wy = sy + MASONRY_STOREY - MASONRY_WINDOW_H
                box(f"{pname}Sill{i}", (px0, px1, pz0, pz1, sy, wy),
                    stone, stone_mat)
                box(f"{pname}Win{i}", (px0, px1, pz0, pz1, wy,
                                       sy + MASONRY_STOREY),
                    MASONRY_WINDOW, GLASS, transparency=0.35, collide=False)
            for qi, (qx, qz, qsx, qsz) in enumerate(
                    ((px0, pz0, 1.0, 1.0), (px1, pz0, -1.0, 1.0),
                     (px0, pz1, 1.0, -1.0), (px1, pz1, -1.0, -1.0))):
                box(f"{pname}Quoin{qi}",
                    span(qx - qsx * MASONRY_PIER_D, qx + qsx * MASONRY_PIER_W)
                    + span(qz - qsz * MASONRY_PIER_D, qz + qsz * MASONRY_PIER_W)
                    + (py0, pty), trim, stone_mat, collide=False)
            step = (px1 - px0) / (MASONRY_PIERS + 1)
            for j in range(1, MASONRY_PIERS + 1):
                pxc = px0 + j * step
                for k, (fa, fb) in enumerate(((pz0 - MASONRY_PIER_D, pz0),
                                              (pz1, pz1 + MASONRY_PIER_D))):
                    box(f"{pname}Pier{j}{'SN'[k]}",
                        (pxc - MASONRY_PIER_W / 2, pxc + MASONRY_PIER_W / 2,
                         fa, fb, py0, pty), trim, stone_mat, collide=False)

        # The cornice under the setback, oversailing the portion below it. This
        # is the shadow line that makes a stone building read as stone from four
        # hundred studs away, and it is one box.
        box("SetbackCornice", (x0 + 0.2, x1 - 0.2, z0 + 0.2, z1 - 0.2,
                               mid - 1.2, mid + 1.2), trim, stone_mat)
        box("Cornice", (ux0 - 1.6, ux1 + 1.6, uz0 - 1.6, uz1 + 1.6,
                        shaft_top, cornice_top), trim, stone_mat)
        cw = max(4.0, (ux1 - ux0) / 2 - 4.0)
        cd = max(4.0, (uz1 - uz0) / 2 - 4.0)
        box("Cap", (cx - cw, cx + cw, cz - cd, cz + cd, cornice_top, cap_top),
            stone, stone_mat)
        # White at roof height, dimmed with every other crown in the city. See
        # CROWN_NEON: the pink and the blue stay down at the door.
        _crown = dim(CROWN_NEON, NEON_ROOF_DIM)
        box("CapBand", (cx - cw - 0.6, cx + cw + 0.6, cz - cd - 0.6, cz + cd + 0.6,
                        cap_top - 1.4, cap_top - 0.4), _crown, NEON, collide=False,
            children=point_light(_crown, 2.0, 60.0))

    place_point(f"masonry_{tag}", cx, fz + s * 2.0, FLOOR_1,
                f"the {tag} building, the lobby")
    return cap_top


# How tall a fade-district office is, by ring distance from the Circle.
#
# This used to be `6 - sband * 2`: a pure south-to-north ramp off the financial
# district, which made the *southern edge* of the city the tall end and left the
# blocks either side of the Circle -- the middle of downtown, the thing the whole
# grid is centred on -- four storeys and shorter than their neighbours. Standing
# on the Circle you looked outward at buildings taller than the ones beside you,
# which is backwards.
#
# Radial now, off the same Chebyshev ring that HOUSE_TIERS uses, so the whole
# city is one shape: tallest at the junction the Circle sits on and stepping down
# in rings, houses included. One rule, two districts, and a player who learns
# "big things are in the middle" from the rooflines learns the same thing from
# the houses.
# Safe range: 4 .. 8. Below 4 a fade office is shorter than the walk-ups it is
# supposed to step down to; above 8 it competes with the Circle's own arc, which
# has to stay the high point.
FADE_STOREYS_BY_RING = (7, 5, 4)


def fade_storeys(band, sband):
    """Storeys for a fade-district office block, by how far it is from the
    Circle. Same measure as house_tier -- see the note there for why the halves
    and why Chebyshev."""
    rings = max(abs(band - (CIRCLE_AVE - 0.5)), abs(sband - (CIRCLE_CS - 0.5)))
    if rings <= 1.5:
        return FADE_STOREYS_BY_RING[0]
    if rings <= 2.5:
        return FADE_STOREYS_BY_RING[1]
    return FADE_STOREYS_BY_RING[2]


def fade_office_band(band, sband, x0, x1, z0, z1, counter):
    """Two mid-rise office blocks per block, as tall as their ring from the
    Circle allows. Returns the next free counter."""
    base_storeys = fade_storeys(band, sband)
    # Loud here rather than inside-out on the map. A tower with zero or negative
    # storeys is legal arithmetic and draws a box whose top is under its bottom,
    # so the symptom is not a crash -- it is a building that is silently missing
    # from the skyline and a block that reads as empty. That shipped once.
    if base_storeys < 3:
        raise SystemExit(
            f"[gen_city] fade_office_band called for band={band} sband={sband}, "
            f"which gives {base_storeys} storeys. Every entry in "
            f"FADE_STOREYS_BY_RING must be at least 3."
        )
    # Two towers with a real plaza between them. The width is solved backwards
    # from the plaza rather than forwards from the towers -- the previous
    # version took half the block each, then tried to put a plaza in what was
    # left, and what was left was three studs. It drew as a two-stud stone
    # sliver a hundred and twenty studs long with two trees standing in it,
    # because `px0` came out greater than `px1` and nothing objects to an
    # inside-out box.
    plaza_w = 24.0
    margin = 1.0
    gap = 2.0
    bw = (x1 - x0 - plaza_w - 2 * margin - 2 * gap) / 2
    left_x0 = x0 + margin
    px0 = left_x0 + bw + gap
    px1 = px0 + plaza_w
    right_x0 = px1 + gap
    for i, bx0 in enumerate((left_x0, right_x0)):
        # The tower nearer the Circle gets the extra floor, so even the two
        # halves of one block lean inward. Which half that is depends on which
        # side of the Circle the block sits on -- on a block west of it the
        # right-hand tower is the inner one.
        inner = 0 if x0 >= CIRCLE_X else 1
        storeys = base_storeys + (1 if i == inner else 0)
        # One of the two is stone, and which one alternates by block so the
        # district is mixed rather than merely striped a second time -- a rule
        # that put every stone building on the west half would be the same
        # sorting problem one axis over.
        #
        # `counter != 1` pins the first office in the district as an office:
        # Townsfolk.luau stands its fade_worker on `fade_1`, and that file
        # belongs to another agent. The parity happens to spare it today; this
        # says so out loud rather than leaving it to luck.
        if i == (band + sband) % 2 and counter != 1:
            masonry_tower(f"{band}{sband}{'we'[i]}", bx0, bx0 + bw, z0, z1,
                          storeys, tint=counter, slab=True)
        else:
            fade_office(counter, bx0, bx0 + bw, z0, z1, storeys,
                        name="FadeOffice")
        counter += 1
    box(f"FadePlaza{sband}_{counter}", (px0, px1, z0, z1, GROUND_BOTTOM, GROUND),
        PATH_STONE, PEBBLE)
    palm_row(px0, px1, z0, z1, GROUND, step=40.0, along="z",
             label=f"FadePlazaPalms{sband}_{counter}")
    for bz in (z0 + 20.0, z1 - 20.0):
        bench(px0 + 5.0, bz, 1)
        bench(px1 - 5.0, bz, -1)
    return counter


# ---------------------------------------------------------------------------
# Mixed block: one sculpted tower, one mid-rise, one restaurant, on the same
# block
# ---------------------------------------------------------------------------
#
# This block was six identical narrow restaurants in a row with a picnic-table
# square behind them -- a food court dropped into the densest corner of the
# city, one street from the waterfront towers and two from the Circle. It read
# as a village that the downtown had grown around and forgotten to demolish.
#
# What replaces it is the thing every real downtown block actually is: more than
# one kind of building. A block of nothing but sculpted towers is as monotonous
# as a block of nothing but shopfronts -- the towers only read as tall because
# something beside them is short, and the short things only read as old because
# something beside them is new. So the four quadrants alternate on the diagonal,
# never two of a kind sharing a street frontage:
#
#     nw  mid-rise office   |  ne  sculpted tower      (front onto the street above)
#     ----------------------+----------------------
#     sw  sculpted tower    |  se  restaurant + terrace (front onto the street below)
#
# The restaurant is not sentiment. `dining_1` is the Chef job's `placeId` in
# Jobs.luau, which is Agent B's file: delete the place point and a job in the
# game points at a building that is not in the world. One restaurant keeps it,
# and one restaurant on a block of towers is a corner unit rather than a food
# court.

# Where the two alleys fall, as a fraction of the block. Never 0.5, for the
# reason FIN_SPLIT_X says at length: four equal quarters is a grid, and the four
# buildings have to be four different sizes or the block reads as a stamp.
#
# The x split is west of centre so the east quadrants are the wide ones -- the
# restaurant needs frontage and a terrace beside it, and the wide quadrant is
# the only one that can carry both.
MIXED_SPLIT_X = 0.44
MIXED_SPLIT_Z = 0.47
MIXED_GAP = 6.0     # the alley between quadrants; same as FIN_GAP, same reason
# How much of the restaurant's quadrant the building takes. The rest is its
# terrace, which is what makes the corner read as a restaurant from across the
# street rather than as a low shed.
MIXED_DINING_FRAC = 0.62
# Storeys for the two sculpted towers. Sized off the mid-rise they stand beside
# (fade_storeys gives 7 here, topping at 115.5) so the block steps rather than
# jumps, and both are far below the Circle -- the assertion that guards that
# only knows about the waterfront, so this one is held by hand and by this note.
MIXED_TOWER_FLOORS = (6, 7)
MIXED_TOWER_STYLES = ("setback", "crown")


def mixed_block(band, sband, x0, x1, z0, z1, fade_no):
    """Four different buildings on one block. Returns the next free fade number.

    The mid-rise takes a number out of the same sequence the fade district uses,
    rather than a sequence of its own: it *is* one of the city's mid-rise
    offices, it is just standing next to a tower, and two numbering schemes for
    one kind of building is two places for a `fade_N` place point id to collide.
    """
    sx = x0 + (x1 - x0) * MIXED_SPLIT_X
    sz = z0 + (z1 - z0) * MIXED_SPLIT_Z
    wx0, wx1 = x0, sx - MIXED_GAP / 2
    ex0, ex1 = sx + MIXED_GAP / 2, x1
    szl0, szl1 = z0, sz - MIXED_GAP / 2
    nz0, nz1 = sz + MIXED_GAP / 2, z1

    # The alleys, paved and planted. The north-south one runs the full depth of
    # the block and the east-west one yields the crossing to it -- the same
    # give-way rule every road and sidewalk in this file follows, and the reason
    # is check 13 rather than taste: two plates that lap and top in the same
    # plane are a z-fight nobody can win, and a full cross laps over 48 studs.
    with group(f"MixedAlley{band}_{sband}"):
        box("AlleyNS", (wx1, ex0, z0, z1, GROUND_BOTTOM, GROUND),
            PATH_STONE, PEBBLE)
        box("AlleyEWWest", (x0, wx1, szl1, nz0, GROUND_BOTTOM, GROUND),
            PATH_STONE, PEBBLE)
        box("AlleyEWEast", (ex0, x1, szl1, nz0, GROUND_BOTTOM, GROUND),
            PATH_STONE, PEBBLE)
        for bz in (z0 + 24.0, z1 - 24.0):
            bench(wx1 + 1.5, bz, 1)
            bench(ex0 - 1.5, bz, -1)
        for bx in (x0 + 24.0, x1 - 24.0):
            tree(bx, (szl1 + nz0) / 2, GROUND, height=13.0, spread=9.0)

    # The two towers' lobby floors.
    #
    # `shaped_tower` pours no slab on purpose -- it stands straight on whatever
    # the block is paved with, which on the waterfront is the block-wide
    # `FinPaving`. On a mixed block there is no block-wide paving to stand on
    # (the restaurant and the mid-rise both pour their own floors, and a third
    # plate under them would top in the same plane as both), so the two towers
    # get a plate each, footprint for footprint. Without it the lobby is a hole
    # in the lawn and the tower's place point floats -- which is exactly what
    # check 4 said the first time this block was built.
    for _tag, _tb in (("SW", (wx0, wx1, szl0, szl1)),
                      ("NE", (ex0, ex1, nz0, nz1))):
        box(f"MixedTowerFloor{band}_{sband}{_tag}",
            _tb + (GROUND_BOTTOM, PAVING), PAVING_GREY, CONCRETE)

    shaped_tower(f"m{band}{sband}sw", wx0, wx1, szl0, szl1,
                 MIXED_TOWER_FLOORS[0],
                 TOWER_GLASS[band % len(TOWER_GLASS)],
                 style=MIXED_TOWER_STYLES[0], tint=0, front="south")
    shaped_tower(f"m{band}{sband}ne", ex0, ex1, nz0, nz1,
                 MIXED_TOWER_FLOORS[1],
                 TOWER_GLASS[(band + 2) % len(TOWER_GLASS)],
                 style=MIXED_TOWER_STYLES[1], tint=1, front="north")
    fade_office(fade_no, wx0, wx1, nz0, nz1, fade_storeys(band, sband),
                name="FadeOffice", front="north")

    # The restaurant fronts the cross street below the block, with its terrace
    # to the east of it -- outdoor tables belong on the street, not behind the
    # kitchen, and the alley side is where the block's own shade is.
    dx = ex0 + (ex1 - ex0) * MIXED_DINING_FRAC
    dining_restaurant("dining_1", "Bistro Verde", ex0, dx, szl0, szl1)
    dining_terrace(dx + 2.0, ex1, szl0, szl1,
                   label=f"MixedTerrace{band}_{sband}")
    return fade_no + 1


# ---------------------------------------------------------------------------
# The Circus: the four blocks that face the Circle
# ---------------------------------------------------------------------------

# Three towers per block, standing on an arc, every one of them turned to face
# the monument. This is the payoff for building the Circle at all: from the
# island, twelve buildings look back at you, and from any of the four spokes you
# are driving into a bowl of towers rather than past another row of frontages.
#
# **The middle tower of each three is the tall one.** A row of equal towers is a
# wall; a tall one with a matching pair either side is a composition, and the
# eye reads the pair as deliberate. Four quadrants, so four tall towers on the
# diagonals and eight shorter ones flanking them.
#
# Everything here is `spun_box`, and the checker has to be able to read it back:
# check_city does a separating-axis test on the rotation matrix rather than an
# axis-aligned box, because a 24x30 tower turned 25 degrees has a bounding box
# 39 studs wide and would report itself as overlapping its neighbour.

# The building line, derived rather than chosen. The pavement ring is a polygon,
# not a circle, so its outer edge bulges past CIRCLE_R_WALK at the facet corners
# -- that bulge is what a building line one stud outside the *nominal* radius
# would end up standing in. One stud of verge past the furthest point the paving
# actually reaches. Safe range: +0.5 .. +4 on the bulge radius.
CIRCUS_FRONT = CIRCLE_R_WALK / math.cos(math.radians(180.0 / CIRCLE_SEGS)) + 1.0
CIRCUS_DEPTH = 30.0
CIRCUS_WIDTH = 24.0
# Degrees between neighbours on the arc. At the building line 20 degrees puts 25
# studs between tower centres, so a 24-wide tower has a stud of daylight at the
# front and eleven at the back -- the wedge between them widens outward, which is
# what makes an arc of buildings read as an arc. Both ends of the range were
# measured, not guessed: at 19 degrees the podiums are a hair apart and at 18
# they interpenetrate, and at 24 the outer tower's back corner crosses the
# block edge at z=342. 22 leaves a 3.8-stud alley between neighbours -- wide
# enough to read as two buildings rather than one seam -- and 1.9 studs of
# block margin. Safe range: 19 .. 23.
CIRCUS_SPREAD = 22.0
# The three towers of a quadrant's arc, outer to inner to outer. The middle one
# stands on the diagonal pointing straight at the monument, so it is the one seen
# down every approach and it is the tallest thing in the city.
#
# It was (6, 10, 6), which topped out at 163 studs -- under the financial
# district's 195 at the *southern edge* of the map. So the highest roofline in
# town was on the way in rather than in the middle of it, and the Circle, which
# the entire grid is centred on and which every avenue runs to, was overlooked by
# something eight blocks away.
#
# The numbers below are measured off the generated file, not estimated, and the
# thing that has to be measured is the *financial district's mast*, not its roof.
# Its roof is at 206.5 but the mast on top reaches 213.5, so a 13-storey Circle
# tower -- 215.5 to the top of its parapet -- won by two studs, which from the
# ground is not a win at all: two silhouettes the same height with one of them
# slightly closer reads as a tie. 14 storeys puts the parapet at 231.5, eighteen
# clear of the mast, which is the smallest gap that still says "that one is the
# middle of the city" from the south end of the connector.
#
# **That fixed the middle four towers and left the other eight losing.** The owner
# asked for the Circle to be higher still, so that *each* of its towers is the
# tallest thing in the city -- not just the four on the diagonals. The shoulders
# were 8 storeys, which is 135.5, seventy-eight studs under the mast they were
# supposed to be beating. From any approach that is not a diagonal the Circle was
# still the second-tallest thing on the horizon.
#
# **The first fix for that was (14, 16, 14), and it ruined the Circle.** Both
# assertions below passed. Both stated requirements were met. The group still came
# out worse than it went in, because the height was bought out of the *shape*: the
# shoulders came up six storeys and the middle only two, which left 231.5 / 263.5 /
# 231.5 -- a two-storey step across a 68-stud arc. From the ground that is not three
# towers, it is one slab with a bump on it. The step between shoulder and middle was
# the thing that made the Circle read as a landmark, and raising the floor without
# raising the roof spent it.
#
# So the height is bought by *translating* the group, not compressing it. CIRCUS_SHAPE
# below is the original silhouette, and every tower is lifted by the same whole number
# of storeys -- the smallest that carries the shortest one over the mast. The step
# survives at exactly what it was, 96 studs, because a translation cannot change it.
#
#   top(n)    = FLOOR_1 + CIRCUS_LOBBY_H + (n - 1) * (CIRCUS_STOREY + CIRCUS_SLAB)
#             = 19.5 + (n - 1) * 16
#   skyline   = top(n) + CIRCUS_SLAB + CIRCUS_PARAPET_H   -- the roof and its parapet,
#             = 23.5 + (n - 1) * 16                          which is what an eye sees
#
#   shoulders  must clear the mast at 213.5 by 18  ->  >= 231.5  ->  8 + 6 = 14
#   middle     carries the same lift, not its own  ->  14 + 6 = 20  ->  327.5
#
# The parapet term is the part that is easy to drop, and dropping it is a four-stud
# lie in the direction that loses the argument -- it was worth writing out.
#
# 13 was rejected for the shoulders for the reason 13 was rejected for the middle
# before it: 215.5 is a two-stud win over the mast, and a two-stud win is a tie.
#
# The middle tower is 24 x 18 at the top and now stands 327.5, which is 18:1 -- more
# slender than anything else in the city and deliberately so. That is real-tower
# territory (432 Park is 15:1, Steinway 24:1) and slenderness is most of what makes a
# building read as a landmark rather than as a block. If it ever looks like a mast
# instead of a tower, the lever is CIRCUS_WIDTH, not the storey count.
#
# The skyline now, from the middle outward:
#   327  the Circle's centre towers (20 storeys)
#   231  the Circle's shoulder towers (14 storeys)
#   213  the financial district's masts
#   134  step and fade offices one ring out (7-8 storeys)
#    83  fade offices two rings out (5-6 storeys)
#    67  the office block
#    34  walk-ups and two-storey houses
#    17  single-storey houses at the edge
# (The 150 that stood on the shoulder line here before was wrong: eight storeys
# measures 135.5, not 150. It is drawn from the formula above now, so it cannot
# drift from the generator again.)
#
# **And that still came out wrong, because one arc repeated four times is not a
# skyline.** `(14, 20, 14)` is three numbers, but the Circle is twelve towers: the
# same quadrant is stamped at all four corners, so what the city actually showed was
# four towers of one height and eight of another. Two rooflines across the whole
# centre. The step was back and the monotony was worse, because the towers were now
# tall enough to be the only thing on the horizon.
#
# Worth naming the mistake, because it is the same one twice: both times I fixed the
# quantity that was written down -- first "each tower is tallest", then "the arc has a
# step" -- and both times the thing that was actually wrong was the *variety*, which
# nobody had written down anywhere. FIN_HEIGHTS one screen up says `varied skyline` in
# its comment and has done since it was written. The Circle never had that line.
#
# So a quadrant is no longer a constant, it is `circus_arc(q)`:
#
#   CIRCUS_ARC        the base arc -- shoulder, peak, shoulder
#   CIRCUS_LIFT       what carries the lowest tower over the mast, applied to all
#   CIRCUS_QUAD_LIFT  a different extra per corner, so no two quadrants match
#   CIRCUS_TILT       the right shoulder above the left, so a quadrant is not even a
#                     mirror of itself and the arc reads as a pinwheel from above
#
# which gives twelve towers on nine distinct rooflines, every one still over the mast:
#
#   NE  14, 20, 15   ->  231.5  327.5  247.5
#   NW  16, 22, 17   ->  263.5  359.5  279.5
#   SE  15, 21, 16   ->  247.5  343.5  263.5
#   SW  17, 23, 18   ->  279.5  375.5  295.5
#
# The peak of every quadrant still clears both its own shoulders by five storeys, so
# each corner reads as an arc rather than a terrace, and the four peaks are all
# different so the centre reads as a cluster rather than as a stamp.
#
# The skyline now, from the middle outward:
#   327-375  the Circle's four peak towers (20-23 storeys)
#   231-295  the Circle's eight shoulder towers (14-18 storeys)
#   213      the financial district's masts
#   134      step and fade offices one ring out (7-8 storeys)
#    83      fade offices two rings out (5-6 storeys)
#    67      the office block
#    34      walk-ups and two-storey houses
#    17      single-storey houses at the edge
#
# Safe range for CIRCUS_LIFT: 6 .. 8. The floor is the assertion below -- at 5 the
# shortest shoulder loses to the mast. The ceiling is slenderness: the tallest tower
# carries CIRCUS_LIFT plus the largest CIRCUS_QUAD_LIFT, and at 9 it passes 21:1 and
# starts to read as an aerial rather than a building. Raise the lift, never the arc.
CIRCUS_ARC = (8, 14, 8)
# Raised 6 -> 10 as the waterfront grew: the spire style tops out 58 studs above
# its own crown, so which band the rotation hands a spire to moves the tallest
# rival by tens of studs and takes the Circle's win with it. This is the
# smallest lift that clears the current rival by CIRCUS_CLEARANCE, and the
# minimality assertion below is what holds it there -- it is also what will
# catch the next person who changes FIN_HEIGHTS, FIN_STYLES or
# FIN_STYLE_STRIDE, in either direction, since a rival that shrinks leaves the
# Circle winning by luck.
CIRCUS_LIFT = 10
# Kept small and all-positive: a negative entry here would drop a quadrant under the
# mast, and a large one buys slenderness at the tallest corner rather than variety.
CIRCUS_QUAD_LIFT = (0, 2, 1, 3)
CIRCUS_TILT = 1


def circus_arc(quadrant):
    """One quadrant's three towers, outer to inner to outer, in storeys."""
    lift = CIRCUS_LIFT + CIRCUS_QUAD_LIFT[quadrant % len(CIRCUS_QUAD_LIFT)]
    return tuple(
        n + lift + (CIRCUS_TILT if i == len(CIRCUS_ARC) - 1 else 0)
        for i, n in enumerate(CIRCUS_ARC)
    )


CIRCUS_STOREYS = tuple(
    n for q in range(len(CIRCUS_QUAD_LIFT)) for n in circus_arc(q)
)
CIRCUS_LOBBY_H = 18.0
CIRCUS_STOREY = 15.0
CIRCUS_SLAB = 1.0
# The parapet standing on the roof slab. Named because it is part of the silhouette
# and therefore part of every height argument above -- four studs of it (slab plus
# parapet) is the difference between the shoulders clearing the financial district
# and tying with it.
CIRCUS_PARAPET_H = 3.0
# How far back from the Circle the block's own corner plaza sits. Measured, not
# chosen: the middle tower's back face is the closest thing to it and clears the
# far corner of a 51-stud square by eleven studs.
CIRCUS_PLAZA = 51.0

CIRCUS_STUCCO = [
    (250, 246, 236),   # deco white
    (206, 230, 224),   # seafoam
    (244, 214, 190),   # apricot
]


def circus_tower(no, phi_deg, storeys, glass, stucco, neon):
    """One tower on the Circle's arc, facing the monument.

    Local axes: +X points outward, away from the island, so the front of the
    building is its -X face and `sign(..., "left")` is the board the island can
    read. +Z runs tangentially. Every part is placed by radius and angle for the
    same reason the ring is: there is no pair of x's and z's that describes a
    box at 25 degrees.
    """
    front = CIRCUS_FRONT
    back = front + CIRCUS_DEPTH
    mid = (front + back) / 2
    yaw = radial_yaw(phi_deg)
    top = FLOOR_1 + CIRCUS_LOBBY_H + (storeys - 1) * (CIRCUS_STOREY + CIRCUS_SLAB)

    def at_radius(name, radius, depth, width, y0, y1, color, material, **kw):
        px, pz = polar(radius, phi_deg)
        rbxmx.spun_box(name, (px, (y0 + y1) / 2, pz),
                       (depth, y1 - y0, width), yaw, color, material, **kw)

    with group(f"CircusTower_{no}"):
        at_radius("Slab", mid, CIRCUS_DEPTH, CIRCUS_WIDTH,
                  FLOOR_1 - CIRCUS_SLAB, FLOOR_1, FLOOR_INDOOR, MARBLE)
        at_radius("Podium", mid, CIRCUS_DEPTH, CIRCUS_WIDTH,
                  FLOOR_1, FLOOR_1 + CIRCUS_LOBBY_H, stucco, CONCRETE)
        # The glazed frontage, proud of the podium by a fifth of a stud so the
        # two faces are never coplanar. The whole reason the podium is solid is
        # that a lobby interior would have to be laid out in a turned frame, and
        # every wall, door and desk builder in this file takes two x's and two
        # z's. The entrance is where the place point is, on the promenade.
        at_radius("Frontage", front + 0.1, 0.6, CIRCUS_WIDTH - 5.0,
                  FLOOR_1 + 2.0, FLOOR_1 + CIRCUS_LOBBY_H - 3.0,
                  GLAZING, GLASS, transparency=0.35, collide=False)
        at_radius("Canopy", front + 1.6, 5.0, DOORWAY + 6.0,
                  FLOOR_1 + CIRCUS_LOBBY_H - 3.0, FLOOR_1 + CIRCUS_LOBBY_H - 1.8,
                  TRIM_WHITE, SMOOTH, collide=False)
        at_radius("Tower", mid, CIRCUS_DEPTH - 6.0, CIRCUS_WIDTH - 6.0,
                  FLOOR_1 + CIRCUS_LOBBY_H, top, glass, GLASS,
                  transparency=0.45, collide=False)
        at_radius("Roof", mid, CIRCUS_DEPTH - 6.0, CIRCUS_WIDTH - 6.0,
                  top, top + CIRCUS_SLAB, (72, 76, 82), CONCRETE)
        at_radius("Parapet", mid, CIRCUS_DEPTH - 4.0, CIRCUS_WIDTH - 4.0,
                  top + CIRCUS_SLAB, top + CIRCUS_SLAB + CIRCUS_PARAPET_H,
                  (90, 94, 100), CONCRETE)
        # The crown. A line of light round the parapet, which is the palette's
        # own rule for neon -- a band, never a surface -- and the thing that
        # makes the Circle read as downtown once the lighting goes warm. White
        # rather than the tower's own colour: see CROWN_NEON.
        crown = dim(CROWN_NEON, NEON_ROOF_DIM)
        at_radius("Crown", mid, CIRCUS_DEPTH - 2.8, CIRCUS_WIDTH - 2.8,
                  top + CIRCUS_SLAB + 1.4, top + CIRCUS_SLAB + 2.6,
                  crown, NEON, collide=False,
                  children=point_light(crown, 2.2, 60.0))
        # ...and the tower's own colour goes here instead, on the lip of the
        # entrance canopy, eighteen studs off the promenade. That is the whole
        # trade: from the island the twelve towers are one white roofline, and
        # from the pavement each one has a different lit door.
        at_radius("EntranceNeon", front + 1.6, 5.2, DOORWAY + 6.4,
                  FLOOR_1 + CIRCUS_LOBBY_H - 3.4, FLOOR_1 + CIRCUS_LOBBY_H - 3.0,
                  neon, NEON, collide=False,
                  children=point_light(neon, 1.6, 34.0))
        px, pz = polar(front - 0.7, phi_deg)
        rbxmx.spun_box("Sign", (px, FLOOR_1 + 13.5, pz), (1.0, 3.0, 16.0), yaw,
                       RISE_FRAME, SMOOTH,
                       children=sign(f"CIRCUS {no}", "left",
                                     color=(250, 246, 234), size=52))

    # The entrance, on the promenade rather than inside the podium: this is where
    # a walker is sent and where a job is worked from.
    ex, ez = polar(CIRCLE_R_WALK - 2.0, phi_deg)
    place_point(f"circus_{no}", ex, ez, PAVING, f"circus {no}, the tower entrance")


def circus_block(band, sband, x0, x1, z0, z1, counter):
    """One quadrant of the Circle: three towers on the arc and a corner plaza.

    Which quadrant is worked out from the block's own bounds rather than passed
    in, because the block plan already knows where the block is and a second
    statement of it is a second thing to get wrong.
    """
    sx = -1 if x1 <= CIRCLE_X else 1
    sz = -1 if z1 <= CIRCLE_Z else 1
    base = math.degrees(math.atan2(sz, sx))
    # Which arc this corner gets. Derived from the running tower count rather than from
    # sx/sz, because the count is what already numbers the towers and the colour cycles
    # below key off it too -- a second way of saying "which quadrant" is a second thing
    # that can disagree with the first.
    for i, storeys in enumerate(circus_arc(counter // len(CIRCUS_ARC))):
        # Same glass family and same two crown colours as the waterfront towers.
        # The Circle stands in the middle of the district it is supposed to
        # crown, and it used to be drawn from a different glass list and a
        # different four-colour neon list than the towers around it -- which is
        # how the centre of downtown ended up the one place where the skyline
        # changed palette.
        circus_tower(counter + i, base + (i - 1) * CIRCUS_SPREAD, storeys,
                     TOWER_GLASS[(counter + i) % len(TOWER_GLASS)],
                     CIRCUS_STUCCO[(counter + i) % len(CIRCUS_STUCCO)],
                     TOWER_CROWN_NEON[(counter + i) % len(TOWER_CROWN_NEON)])

    # The corner of the block the arc does not reach: paved, planted and lit,
    # rather than left as the lawn it would otherwise be. The towers stand on a
    # curve and the block is a rectangle, so there is always a corner left over
    # -- pretending otherwise is how a district ends up with a strip of grass
    # nobody can explain.
    px0 = x0 if sx < 0 else x1 - CIRCUS_PLAZA
    pz0 = z0 if sz < 0 else z1 - CIRCUS_PLAZA
    px1, pz1 = px0 + CIRCUS_PLAZA, pz0 + CIRCUS_PLAZA
    with group(f"CircusPlaza_{band}_{sband}"):
        box("Paving", (px0, px1, pz0, pz1, GROUND_BOTTOM, GROUND),
            PATH_STONE, PEBBLE)
    palm_row(px0 + 6.0, px1 - 6.0, pz0 + 4.0, pz1 - 4.0, GROUND, step=20.0,
             along="z", label=f"CircusPalms_{band}_{sband}")
    bench((px0 + px1) / 2, pz0 + 6.0, 1, label=f"CircusBench_{band}_{sband}")
    bench((px0 + px1) / 2, pz1 - 6.0, -1, label=f"CircusBench_{band}_{sband}")
    return counter + len(CIRCUS_ARC)


# ---------------------------------------------------------------------------
# The civic precinct: everything north of the last cross street.
# ---------------------------------------------------------------------------

# One band, 152 studs deep and the width of the grid, with no road in it. Read
# from the cross street northward:
#
#   968 .. 988    forecourt   -- the walk the civic row is read from
#   988 ..1032    the civic row, thirteen buildings and three passages
#  1032 ..1060    promenade   -- the walk the shops are read from
#  1060 ..1116    the north shops
#
# The two walks are the precinct's east-west spines and the passages are the
# only way between them, which is why there are three of them and why they are
# sixteen studs wide rather than the four the row's ordinary gaps get: a passage
# a player cannot see through from one walk to the other is a passage nobody
# will try. The whole band is paved as one slab a hundredth under the pavement
# height, so the buildings' own slabs sit fractionally proud of it and no two
# faces ever end up coplanar.
PRECINCT_X0, PRECINCT_X1 = CS_X0, CS_X1
PRECINCT_Z0, PRECINCT_Z1 = 968.0, 1060.0

# Starts at 89 rather than the precinct's own edge: the car dealership takes the
# west corner (x 47..81), and the civic row picks up eight studs clear of it.
CIVIC_X0 = 89.0
# Was 787. Stops clear of the new precinct avenue's west pavement rather than
# running into it -- derived, so widening that avenue moves the row instead of
# putting the last civic building in the carriageway.
CIVIC_X1 = PRECINCT_INNER_X1 - 6.0
CIVIC_Z0, CIVIC_Z1 = 988.0, 1032.0
CIVIC_GAP = 4.0
CIVIC_PASSAGE = 16.0
# A passage follows each of these building indices, splitting the row 4/3/3/3.
CIVIC_PASSAGE_AFTER = (3, 6, 9)

NORTH_Z0 = 1060.0
NORTH_Z1 = 1116.0
NORTH_X0 = CIVIC_X0
NORTH_X1 = CIVIC_X1
NORTH_GAP = 4.0

def solve_row(x0, x1, weights, gaps):
    """(start, end) for each slot in a band, given relative widths.

    `gaps` is the width of the space between two neighbouring slots, either a
    single number or one per interstice. The band is always filled exactly --
    that is the whole reason widths are solved rather than typed."""
    n = len(weights)
    if not isinstance(gaps, (list, tuple)):
        gaps = [gaps] * (n - 1)
    content = (x1 - x0) - sum(gaps)
    if content <= 0:
        raise ValueError(f"row from {x0} to {x1} has no room left after {sum(gaps)} of gaps")
    unit = content / sum(weights)
    spans = []
    cursor = x0
    for i, w in enumerate(weights):
        spans.append((cursor, cursor + unit * w))
        cursor += unit * w
        if i < n - 1:
            cursor += gaps[i]
    return spans


# The government quarter, west to east. One row per slot in the band:
#
#   (kind, id, name, storeys, weight)
#
# This band used to be the north shopping strip: five little shopfronts, three
# duplicate emergency services and two fifty-stud pocket parks, standing
# directly behind City Hall. It read as a parade of huts pinned to the back of a
# monument, and the two parks read as gaps somebody had not got round to
# filling -- which is exactly what they were, since the row was solved from
# weights and the parks were what absorbed the remainder.
#
# It is a government quarter now, facing City Hall across the promenade, and the
# reason it works where the strip did not is scale: four monumental stone
# buildings the same height as the hall opposite them make the promenade a
# civic space with two sides, where a row of one-storey shops made it a car park
# with a town hall at one end. The bank came up here from the waterfront for the
# same reason -- a neoclassical bank with a dome was the one building in the
# financial district that was not a tower, and it belongs with the courthouse.
#
# `north_shop_1` survives as the quarter's canteen because Config.Places.Walkable
# and Townsfolk's `north_worker` both name it. The id is load-bearing and the
# building it points at is not, which is why the id is kept verbatim and the
# thing it opens onto changed.
GOV_ROW = [
    ("block", "courthouse", "CITY COURTHOUSE", 3, 1.15),
    ("bank",  "bank", "UNION BANK", 2, 1.30),
    ("plaza", "gov_plaza", "UNION SQUARE", 0, 0.85),
    ("block", "north_shop_1", "CIVIC CANTEEN", 2, 0.90),
    ("block", "treasury", "CITY TREASURY", 3, 1.10),
    ("block", "archive", "STATE ARCHIVE", 2, 1.00),
]

GOV_SLOTS = solve_row(NORTH_X0, NORTH_X1, [row[4] for row in GOV_ROW], NORTH_GAP)

# Limestone, one family, three values -- the same rule the towers follow, for
# the same reason. The old strip took a different STORE_WALLS pastel per unit,
# which is right for a shopping street where each unit is a different business
# and wrong for a quarter where every building belongs to the same institution.
GOV_STONE = [(236, 230, 216), (226, 218, 202), (242, 238, 226)]
GOV_PLINTH = (176, 170, 158)     # the granite base course
GOV_CORNICE = (250, 247, 238)
GOV_PILASTER_W = 2.6             # face width of a pilaster. Safe range 2 .. 4.
GOV_PLINTH_H = 3.2               # base course height, flush with the wall face
GOV_CORNICE_H = 1.6
GOV_PARAPET_H = 3.4
# Pilasters are laid at this pitch and the count is solved from the frontage, so
# a slot that widens gets more of them rather than wider ones. Written as a
# count instead, the courthouse and the canteen would carry the same five and
# the wider building would read as the blurrier photograph of the two.
GOV_PILASTER_PITCH = 15.0        # safe range 11 .. 20
GOV_WINDOW_H = 9.0               # tall sash between pilasters. Safe range 7 .. 12.


def civic_block(pid, label, x0, x1, z0, z1, storeys, stone):
    """A stone civic office: granite base course, pilastered south front, tall
    windows between the pilasters, cornice and parapet.

    Everything fronts south. This band has a road behind it and City Hall in
    front of it, and the strip that stood here turned three of its ten
    buildings round to face the service road -- which is correct for an engine
    bay and wrong for a ministry. A government quarter addresses its square.

    There is no floor slab under the walls: the quarter lays one paved ground
    for the whole band and each building puts a thin floor inlay *on top* of it.
    A per-building slab with its top at PAVING is coplanar with the paving it
    stands on, and two surfaces at the same height is a flicker, not a floor.
    """
    cx = (x0 + x1) / 2
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    eaves = FLOOR_1 + storeys * (STOREY + SLAB)
    cornice_y = eaves + GOV_CORNICE_H
    door = (cx - DOORWAY / 2, cx + DOORWAY / 2)
    with group(pid):
        box("Floor", (x0, x1, z0, z1, FLOOR_1, FLOOR_1 + FLOOR_INLAY),
            FLOOR_INDOOR, MARBLE)
        wall("WallSouth", (x0, x1, z0, iz0, FLOOR_1, eaves), stone, CONCRETE,
             along="x", doors=(door,))
        wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, eaves), stone, CONCRETE, along="x")
        wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, eaves), stone, CONCRETE, along="z")
        wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, eaves), stone, CONCRETE, along="z")
        glass_doors("Door", door + (z0, iz0, FLOOR_1, FLOOR_1 + DOOR_HEIGHT), along="x")
        # The base course is flush with the wall face, not proud of it. A ledge
        # here would be the plinth this district just had removed from under
        # every tower -- a band of darker stone says "base" without putting a
        # step round the building.
        box("Base", (x0, x1, z0, iz0, FLOOR_1, FLOOR_1 + GOV_PLINTH_H), GOV_PLINTH, CONCRETE)
        # Pilasters and the windows between them, both solved from the same
        # division of the frontage so a window is always a bay and never half of
        # one. Storey-height glass, set back into the wall's own thickness.
        bays = max(2, int(round((x1 - x0) / GOV_PILASTER_PITCH)))
        step = (x1 - x0) / bays
        for b in range(bays + 1):
            px = x0 + b * step
            box(f"Pilaster{b}", (px - GOV_PILASTER_W / 2, px + GOV_PILASTER_W / 2,
                                 z0 - 0.7, z0 + 0.2, FLOOR_1, cornice_y),
                GOV_CORNICE, CONCRETE, collide=False)
        for level in range(storeys):
            wy = FLOOR_1 + GOV_PLINTH_H + 1.6 + level * (STOREY + SLAB)
            for b in range(bays):
                px = x0 + b * step
                if px + step / 2 > door[0] and px + step / 2 < door[1] and level == 0:
                    continue
                glazing(f"Win{level}_{b}",
                        (px + GOV_PILASTER_W, px + step - GOV_PILASTER_W, z0, iz0,
                         wy, wy + GOV_WINDOW_H),
                        along="x", panes=2)
        box("Cornice", (x0 - 1.2, x1 + 1.2, z0 - 1.2, z1 + 1.2, eaves, cornice_y),
            GOV_CORNICE, CONCRETE)
        box("Parapet", (x0, x1, z0, z1, cornice_y, cornice_y + GOV_PARAPET_H),
            stone, CONCRETE)
        box("Counter", (cx - 12.0, cx + 12.0, iz1 - 5.0, iz1 - 1.0,
                        FLOOR_1, FLOOR_1 + 3.0), DESK_TOP, WOOD)
        ceiling_light(cx, (z0 + z1) / 2, eaves - 1.0)
        box("Sign", (cx - 16.0, cx + 16.0, z0 - 1.5, z0 - 0.8,
                     cornice_y + 0.6, cornice_y + 2.6), GOV_CORNICE, SMOOTH,
            collide=False,
            children=sign(label, "front", color=(58, 54, 46), size=48))
    place_point(pid, cx, z0 + 3.0, FLOOR_1, f"the {label.lower()}, by the door")


def gov_square(x0, x1, z0, z1):
    """The one open slot in the quarter: a paved square with a flagpole row.

    Paved rather than lawned, and one square rather than the two pocket parks
    that used to sit in this band. A government quarter's open ground is a place
    people stand in front of a building, so it is the same stone as the
    promenade and it lines up with the gap between the bank and the canteen --
    which makes it a view through to City Hall rather than a hole in a row.
    """
    cx = (x0 + x1) / 2
    with group("GovSquare"):
        box("Setts", (x0, x1, z0, z1, PAVING, PAVING + 0.04), PATH_STONE, PEBBLE,
            collide=False)
        for i, px in enumerate((cx - 14.0, cx, cx + 14.0)):
            box(f"FlagPole{i}", (px - 0.5, px + 0.5, z0 + 9.0, z0 + 10.0,
                                 PAVING, PAVING + 34.0), STEEL, METAL)
            box(f"Flag{i}", (px + 0.5, px + 9.0, z0 + 9.2, z0 + 9.4,
                             PAVING + 25.0, PAVING + 33.0),
                (AWNING_RED, TRIM_WHITE, AWNING_BLUE)[i], FABRIC, collide=False)
        for tz in (z0 + 20.0, z1 - 14.0):
            tree(x0 + 10.0, tz, PAVING, height=16.0, spread=11.0, label="SquareTree")
            tree(x1 - 10.0, tz, PAVING, height=16.0, spread=11.0, label="SquareTree")
        bench(cx - 12.0, z1 - 8.0, -1, floor=PAVING)
        bench(cx + 12.0, z1 - 8.0, -1, floor=PAVING)
        street_lamp(cx, (z0 + z1) / 2, 1, floor=PAVING)



def pocket_park(x0, x1, z0, z1, name, label):
    """A lawn with a path straight through it, benches facing in, and trees.

    The path runs the full depth on purpose: these sit in a row of buildings and
    the thing they are worth most for is being *through* routes. A park you can
    only look into is a gap in the row; a park you can walk out of the other
    side of is a short cut, and a short cut is the only reason anyone learns a
    piece of a town."""
    cx = (x0 + x1) / 2
    with group(name):
        # A tone off the city's verge grass and a hair above it, so a mown park
        # reads as different from the ground it is cut out of instead of
        # z-fighting with it. GRASS_LIFT exists for exactly this.
        box("Lawn", (x0, x1, z0, z1, GROUND_BOTTOM, CITY_GRASS_TOP + GRASS_LIFT),
            PITCH_GREEN, GRASS)
        # The path is at pavement height, not ground: it is a continuation of
        # the promenade and the apron either end of it, and a walk that steps
        # down half a stud and back up again is a walk nobody takes.
        box("Path", (cx - 4.0, cx + 4.0, z0, z1, GROUND_BOTTOM, PAVING),
            PATH_STONE, PAVEMENT)
        for _pz in (z0 + 14.0, z1 - 14.0):
            bench(cx - 8.0, _pz, 1, floor=GROUND)
            bench(cx + 8.0, _pz, -1, floor=GROUND)
        for _tx, _tz, _h in ((x0 + 8.0, z0 + 12.0, 17.0), (x1 - 8.0, z0 + 22.0, 14.0),
                             (x0 + 9.0, z1 - 16.0, 15.0), (x1 - 7.0, z1 - 10.0, 18.0)):
            tree(_tx, _tz, GROUND, height=_h, spread=_h * 0.7, label=f"{name}Tree{_tx:.0f}")
        street_lamp(cx - 6.0, (z0 + z1) / 2, 1, floor=GROUND)
        box("Sign", (cx - 5.0, cx + 5.0, z0 + 1.0, z0 + 1.4, GROUND + 4.0, GROUND + 6.0),
            (66, 92, 72), SMOOTH, collide=False,
            children=sign(label, "back", color=(238, 240, 232), size=32))


def government_quarter():
    """The band behind City Hall: four stone civic buildings, the bank, and one
    paved square, all fronting the promenade."""
    prom_z0 = CIVIC_Z1
    with group("GovQuarterGround"):
        # Ground for the whole band, laid once and owned by the band. Every
        # building on it draws its floor as an inlay above this rather than as a
        # slab of its own, so nothing in the quarter is coplanar with anything
        # else -- see civic_block for the failure that rule exists to stop.
        box("GovPaving", (NORTH_X0 - AVE_WALK, PRECINCT_INNER_X1, NORTH_Z0,
                          NORTH_ROAD_Z0 - CS_WALK, GROUND_BOTTOM, PAVING),
            PAVING_GREY, PAVEMENT)
        for _sx0, _sx1 in GOV_SLOTS[::2]:
            street_lamp((_sx0 + _sx1) / 2, prom_z0 + 5.0, 1, floor=PAVING)
    for i, (kind, pid, label, storeys, _w) in enumerate(GOV_ROW):
        sx0, sx1 = GOV_SLOTS[i]
        if kind == "plaza":
            gov_square(sx0, sx1, NORTH_Z0, NORTH_Z1)
        elif kind == "bank":
            grand_bank(sx0, sx1, NORTH_Z0 + 6.0, NORTH_Z1)
        else:
            civic_block(pid, label, sx0, sx1, NORTH_Z0, NORTH_Z1, storeys,
                        GOV_STONE[i % len(GOV_STONE)])
    palm_row(NORTH_X0, NORTH_X1, prom_z0 + 12.0, prom_z0 + 18.0, PAVING,
             step=64.0, along="x", label="PromenadePalms")


# Called below, after civic_fittings is defined -- the strip's three services
# are furnished by the same function the civic row uses, and Python binds that
# name at call time.


# Civic buildings: a row across the north end of the grid, fronting the
# forecourt.
#
#   (place id, business name, kind, front_type, storeys, weight)
#
# The x bounds used to be written out on each row, which is how the row came to
# be standing in the middle of six avenues: the numbers were measured against a
# grid that later grew roads through them and nothing re-read them. They are
# computed from the band now, so the row cannot disagree with the plan.
#
# `storeys` and `weight` are the fix for thirteen buildings the same width and
# the same height standing shoulder to shoulder, which is exactly what a player
# standing at the town hall was looking at. A weight is a *share* of the band --
# widths are still solved backwards from it, so the row still fills the band
# exactly however the band moves, but the town hall is now half again the width
# of the dentist next to the museum instead of matching it to the stud.
#
# Two lower bounds on a weight, both learned the hard way and neither visible
# from this table: civic_fittings lays the arcade's five cabinets from the west
# wall and the construction site's three scaffolds from x0, and both run off the
# end of a building much under forty studs wide. Anything below about 0.9 has to
# be a kind whose fittings are measured from the centre.
CIVIC = [
    ("cinema", "ORION CINEMA", "cinema", "plain", 2, 1.25),
    ("bowling", "SPARE LANES", "bowling", "plain", 1, 1.15),
    ("arcade", "NEON ARCADE", "arcade", "plain", 1, 1.00),
    ("hotel", "GRAND HOTEL", "hotel", "plain", 3, 1.00),
    ("town_hall", "CITY HALL", "hall", "plain", 3, 1.35),
    ("police_station", "CITY POLICE", "police", "plain", 2, 1.00),
    ("fire_station", "CITY FIRE", "fire", "garage", 1, 1.15),
    ("warehouse", "NORTH WAREHOUSE", "warehouse", "garage", 1, 1.10),
    ("construction_site", "SIMMONS BUILD", "construction", "plain", 1, 1.05),
    ("farm", "WINDMILL FARM", "farm", "shop", 1, 1.00),
    ("post_office", "ROYAL POST", "post_office", "plain", 2, 0.90),
    ("museum", "METROPOLITAN MUSEUM", "museum", "plain", 2, 1.20),
    ("dental", "SMILEDENT", "dental", "plain", 1, 0.90),
]

# The window cut for each civic kind. The row used to take storefront's default
# `full` everywhere, which is why thirteen buildings with thirteen different
# jobs all had one continuous band of shop glass across the front: a cinema is a
# blank wall and a sign, a warehouse has no window at all, and a hotel is glazed
# to the floor. This is the cheapest of the four legibility cues in SHOP_FRONTS
# and the one that carries furthest for a building you cannot get an awning on.
CIVIC_GLASS = {
    "cinema": "none",
    "bowling": "narrow",
    "arcade": "narrow",
    "hotel": "full",
    "police": "high",
    "construction": "none",
    "farm": "narrow",
    "post_office": "high",
    "museum": "high",
    "dental": "full",
}


def civic_slots():
    """(x0, x1) for each civic building, west to east, and the passage x spans."""
    gaps = [CIVIC_PASSAGE if i in CIVIC_PASSAGE_AFTER else CIVIC_GAP
            for i in range(len(CIVIC) - 1)]
    slots = solve_row(CIVIC_X0, CIVIC_X1, [row[5] for row in CIVIC], gaps)
    passages = [(slots[i][1], slots[i][1] + CIVIC_PASSAGE) for i in CIVIC_PASSAGE_AFTER]
    return slots, passages


CIVIC_SLOTS, CIVIC_PASSAGES = civic_slots()


def civic_fittings(kind, x0, x1, z0, z1, front="south"):
    """What is inside a civic building, chosen by what it is for.

    `front` is which wall the door is in. It exists because the north strip now
    turns three of these round to face the service road, and a desk is the one
    fitting that has to know: a counter placed against the wall behind the door
    is a counter the player walks past to reach nothing. Same defect
    street_fittings had, found the same way -- see the note on counter_at."""
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    # `near` is a step inside the door and `desk_side` faces back out of it, so
    # a served counter always straddles the spot the game puts the player on.
    inward = 1.0 if front == "south" else -1.0
    near_z = (z0 + 6.0) if front == "south" else (z1 - 6.0)
    desk_side = "north" if front == "south" else "south"
    with group(f"{kind}Fittings"):
        if kind == "cinema":
            box("Screen", (cx - 10.0, cx + 10.0, z1 - 4.0, z1 - 1.0,
                           FLOOR_1 + 5.0, FLOOR_1 + 13.0), (40, 44, 48), SMOOTH)
            for i in range(3):
                box(f"Row{i}", (cx - 12.0, cx + 12.0, z0 + 5.0 + i * 7.0,
                                z0 + 7.5 + i * 7.0, FLOOR_1 + 2.0, FLOOR_1 + 2.8),
                    (150, 70, 80), FABRIC)
        elif kind == "bowling":
            for i in range(3):
                bx = cx - 8.0 + i * 8.0
                box(f"Lane{i}", (bx, bx + 5.0, z0 + 3.0, z1 - 6.0,
                                 FLOOR_1, FLOOR_1 + 0.4), (150, 130, 96), WOOD)
        elif kind == "arcade":
            for i in range(5):
                bx = ix0 + 2.0 + i * 8.0
                box(f"Machine{i}", (bx, bx + 3.4, cz - 2.0, cz + 2.0,
                                    FLOOR_1, FLOOR_1 + 6.0), (30, 34, 40), SMOOTH)
                box(f"Glow{i}", (bx + 0.3, bx + 3.1, cz - 1.6, cz + 1.6,
                                 FLOOR_1 + 3.0, FLOOR_1 + 5.5), (60, 200, 220), NEON, collide=False)
        elif kind == "hotel":
            desk(cx, cz - 4.0, FLOOR_1, side="north", width=10.0, depth=3.0, label="FrontDesk")
            chair(cx, cz - 1.0, FLOOR_1, side="south")
            box("Sofa", (ix0 + 4.0, ix0 + 10.0, iz0 + 4.0, iz0 + 8.0,
                         FLOOR_1 + 1.2, FLOOR_1 + 2.0), (140, 96, 80), FABRIC)
        elif kind in ("hall", "police"):
            for dx, w in ((-5.0, 8.0), (5.0, 6.0)):
                desk(cx + dx, near_z, FLOOR_1, side=desk_side, width=w, depth=3.0, label="Desk")
                chair(cx + dx, near_z + inward * 2.0, FLOOR_1,
                      side="south" if front == "south" else "north")
        elif kind == "fire":
            for dx in (-6.0, 4.0):
                box(f"Engine{dx}", (cx + dx - 3.0, cx + dx + 3.0, cz - 3.0, cz + 3.0,
                                    FLOOR_1 + 2.0, FLOOR_1 + 5.0), (196, 88, 72), SMOOTH)
        elif kind == "warehouse":
            for i in range(3):
                box(f"Shelf{i}", (x0 + 4.0, x0 + 7.0, z0 + 4.0 + i * 8.0,
                                  z0 + 6.4 + i * 8.0, FLOOR_1, FLOOR_1 + 8.0), SHELF, METAL)
        elif kind == "construction":
            for i in range(3):
                bx = x0 + 6.0 + i * 16.0
                box(f"Scaffold{i}", (bx, bx + 1.2, z0 + 2.0, z1 - 2.0,
                                     FLOOR_1, FLOOR_1 + 9.0), (160, 132, 90), WOOD)
                box(f"Deck{i}", (bx - 0.2, bx + 1.4, z0 + 2.0, z1 - 2.0,
                                 FLOOR_1 + 4.5, FLOOR_1 + 4.8), (120, 120, 120), SMOOTH)
            box("Pile", (cx, cx + 8.0, z1 - 5.0, z1 - 1.5, FLOOR_1, FLOOR_1 + 3.0),
                (176, 150, 110), PLANKS)
        elif kind == "farm":
            box("Barn", (cx - 8.0, cx + 8.0, z0 + 3.0, z0 + 14.0,
                         FLOOR_1 + 6.0, FLOOR_1 + 12.0), (196, 160, 120), WOOD)
            box("Hay", (cx - 2.0, cx + 2.0, z1 - 5.0, z1 - 1.0,
                        FLOOR_1, FLOOR_1 + 3.0), (212, 180, 90), PLANKS)
        elif kind == "post_office":
            desk(cx - 4.0, near_z, FLOOR_1, side=desk_side, width=6.0, depth=3.0, label="Counter")
            chair(cx - 4.0, near_z + inward * 2.0, FLOOR_1,
                  side="south" if front == "south" else "north")
            for i in range(3):
                box(f"Bin{i}", (x1 - 6.0, x1 - 3.0, z0 + 4.0 + i * 6.0,
                                z0 + 6.4 + i * 6.0, FLOOR_1, FLOOR_1 + 3.0),
                    (150, 110, 80), PLANKS)
        elif kind == "bank":
            box("Teller", (cx - 8.0, cx + 8.0, z1 - 5.0, z1 - 1.0,
                           FLOOR_1, FLOOR_1 + 3.0), DESK_TOP, WOOD)
            box("Vault", (x1 - 6.0, x1 - 1.0, z1 - 8.0, z1 - 1.0,
                          FLOOR_1, FLOOR_1 + 8.0), STEEL, METAL)
            for dx in (-6.0, 6.0):
                desk(cx + dx, cz - 2.0, FLOOR_1, side="north", width=4.0, depth=2.6, label="Desk")
                chair(cx + dx, cz, FLOOR_1, side="south")
        elif kind == "dental":
            box("Chair", (cx - 3.0, cx + 3.0, cz - 2.0, cz + 4.0,
                          FLOOR_1 + 1.2, FLOOR_1 + 2.4), (214, 218, 224), FABRIC)
            desk(cx - 7.0, cz + 4.0, FLOOR_1, side="east", width=4.0, depth=2.4, label="Desk")
        elif kind == "museum":
            for i in range(4):
                bx = ix0 + 3.0 + i * 10.0
                box(f"Exhibit{i}", (bx, bx + 5.0, cz - 3.0, cz + 3.0,
                                    FLOOR_1, FLOOR_1 + 5.0),
                    (200, 196, 188), PLASTIC)
            box("Statue", (cx - 2.0, cx + 2.0, cz - 2.0, cz + 2.0,
                           FLOOR_1, FLOOR_1 + 6.0), (180, 176, 168), MARBLE)
        ceiling_light(cx, cz, CEIL_1)


# The precinct floor, laid before anything stands on it. One slab a hundredth
# under pavement height: every building's own slab then sits fractionally proud
# and no two horizontal faces are ever coplanar, which is the same trick the
# city's grass plays against the roads laid over it.
with group("CivicPrecinct"):
    box("PrecinctPaving", (PRECINCT_X0, PRECINCT_INNER_X1, PRECINCT_Z0, PRECINCT_Z1,
                           GROUND_BOTTOM, PAVING - 0.02), PAVING_GREY, PAVEMENT)

for _i, (pid, label, kind, ftype, _storeys, _w) in enumerate(CIVIC):
    x0, x1 = CIVIC_SLOTS[_i]
    cx = (x0 + x1) / 2
    if pid == "town_hall":
        grand_city_hall(x0, x1, CIVIC_Z0, CIVIC_Z1)
    else:
        wall_color = STORE_WALLS[_i % len(STORE_WALLS)]
        with group(pid):
            storefront(label, x0, x1, CIVIC_Z0, CIVIC_Z1, cx, wall_color,
                       front="south", front_type=ftype, storeys=_storeys,
                       glass=CIVIC_GLASS.get(kind, "high"),
                       bays=GARAGE_BAYS.get(kind, 1) if ftype == "garage" else 1)
            civic_fittings(kind, x0, x1, CIVIC_Z0, CIVIC_Z1)
        place_point(pid, cx, CIVIC_Z0 + 2.0, FLOOR_1, f"the {label.lower()}, by the desk")

# The three passages, planted rather than paved.
#
# They are the only way between the forecourt and the promenade, so they were
# always going to be walked; sixteen studs of bare grey between two blank side
# walls is a corridor, and a corridor with a tree and a bench in it is a place.
# Cheap, and it is most of the difference between a row of buildings and a
# street.
for _pi, (_px0, _px1) in enumerate(CIVIC_PASSAGES):
    _pcx = (_px0 + _px1) / 2
    with group(f"CivicPassage{_pi}"):
        box("Lawn", (_px0 + 1.0, _px1 - 1.0, CIVIC_Z0 + 6.0, CIVIC_Z1 - 6.0,
                     GROUND_BOTTOM, PAVING - 0.01), LAWN, GRASS)
        box("Path", (_pcx - 3.0, _pcx + 3.0, CIVIC_Z0, CIVIC_Z1,
                     GROUND_BOTTOM, PAVING), PATH_STONE, PAVEMENT)
        tree(_px0 + 4.0, CIVIC_Z0 + 12.0, PAVING, height=14.0, spread=9.0,
             label="PassageTree")
        tree(_px1 - 4.0, CIVIC_Z1 - 12.0, PAVING, height=16.0, spread=10.0,
             label="PassageTree2")

# The forecourt's own furniture, and palms down both spines.
with group("CivicForecourt"):
    for _x in range(int(CIVIC_X0) + 30, int(CIVIC_X1), 120):
        street_lamp(float(_x), PRECINCT_Z0 + 6.0, 1, floor=PAVING)
    for _x0, _x1 in CIVIC_PASSAGES:
        bench(_x0 - 8.0, PRECINCT_Z0 + 14.0, -1)
        bench(_x1 + 8.0, PRECINCT_Z0 + 14.0, -1)
palm_row(CIVIC_X0, CIVIC_X1, PRECINCT_Z0 + 8.0, PRECINCT_Z0 + 14.0, PAVING,
         step=74.0, along="x", label="ForecourtPalms")

# Built here rather than beside its own definition, because three of its slots
# are civic services and civic_fittings is only bound above.
government_quarter()


# ---------------------------------------------------------------------------
# Sports park
# ---------------------------------------------------------------------------


def soccer_field(x0, x1, z0, z1):
    """A 70x110 pitch with goals tagged for the rules to find."""
    with group("SoccerField"):
        box("Pitch", (x0, x1, z0, z1, GROUND_BOTTOM, GROUND), PITCH_GREEN, GRASS)
        box("LineW", (x0 - 0.4, x0 + 0.4, z0, z1, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("LineE", (x1 - 0.4, x1 + 0.4, z0, z1, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("LineS", (x0, x1, z0 - 0.4, z0 + 0.4, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("LineN", (x0, x1, z1 - 0.4, z1 + 0.4, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("Half", (x0, x1, (z0 + z1) / 2 - 0.3, (z0 + z1) / 2 + 0.3, PAINT_BOTTOM, PAINT_TOP),
            (240, 240, 240), SMOOTH)
        # The centre spot sits on the halfway line by definition, so it is
        # painted over it rather than in it -- see PAINT_OVER_TOP.
        box("Center", ((x0 + x1) / 2 - 1.0, (x0 + x1) / 2 + 1.0, (z0 + z1) / 2 - 1.0,
                       (z0 + z1) / 2 + 1.0, PAINT_OVER_BOTTOM, PAINT_OVER_TOP),
            (240, 240, 240), SMOOTH)
        for dz, toward in ((z0, 1), (z1, -1)):
            box(f"Box{dz:.0f}", (x0 + 12.0, x1 - 12.0, dz, dz + toward * 4.0,
                                 PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        # A real goal is about a third as wide as it is tall -- 7.32m against
        # 2.44m. The posts used to sit a fixed 12 studs in from each
        # touchline, which came out 45 studs wide against this 70-wide pitch:
        # nearly two-thirds of the whole width, wider than the 8-stud-tall
        # posts made it read as a goal rather than an open end of the pitch.
        # `GOAL_HALF_WIDTH` centres a 24-stud-wide goal (roughly the same
        # height-to-width ratio as the real thing) on the pitch's own
        # midline instead, well inside the 46-stud penalty box (`Box{dz}`
        # above) the way a real goal sits inside its own box.
        GOAL_HALF_WIDTH = 12.0
        mid_x = (x0 + x1) / 2.0
        for gz in (z0, z1):
            with group(f"Goal{gz:.0f}"):
                box("Post", (mid_x - GOAL_HALF_WIDTH - 0.4, mid_x - GOAL_HALF_WIDTH + 0.4,
                             gz - 2.4, gz, GROUND, GROUND + 8.0),
                    (240, 240, 240), METAL, tags=[SPORT_TAG], attrs={SPORT_KIND: "soccer"})
                box("Post2", (mid_x + GOAL_HALF_WIDTH - 0.4, mid_x + GOAL_HALF_WIDTH + 0.4,
                             gz - 2.4, gz, GROUND, GROUND + 8.0),
                    (240, 240, 240), METAL, tags=[SPORT_TAG], attrs={SPORT_KIND: "soccer"})
                # The crossbar is the drill station for this goal: a penalty sweep aims
                # at the goal as a whole, and the bar is the one part of it that sits at
                # a sensible stand-and-shoot distance in front of the line. Both goals
                # are tagged, so a penalty taker can use either end of the pitch.
                box("Bar", (mid_x - GOAL_HALF_WIDTH, mid_x + GOAL_HALF_WIDTH,
                            gz - 2.4, gz - 1.8, GROUND + 7.6, GROUND + 8.2),
                    (240, 240, 240), METAL, tags=[SPORT_TAG, SPORTS_DRILL_TAG],
                    attrs={SPORT_KIND: "soccer", SPORTS_DRILL_KIND: "soccer"})


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
        for hz, into in ((z0, 1), (z1, -1)):
            with group(f"Hoop{hz:.0f}"):
                box("Backboard", (cx - 1.75, cx + 1.75, hz - into * 1.5, hz - into * 0.5,
                                  GROUND + 7.0, GROUND + 10.0), (240, 240, 240), GLASS,
                    tags=[SPORT_TAG], attrs={SPORT_KIND: "basketball"})
                box("Rim", (cx - 1.5, cx + 1.5, hz + into * 0.5, hz + into * 1.5,
                            GROUND + 7.0, GROUND + 7.3), (216, 120, 40), METAL,
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
        mid_z = (z0 + z1) / 2
        for side in (-1, 1):
            box(f"Service{side}", (x0, x1, mid_z + side * 3.5 - 0.3, mid_z + side * 3.5 + 0.3,
                                   PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        box("Center", ((x0 + x1) / 2 - 0.3, (x0 + x1) / 2 + 0.3, mid_z - 3.5, mid_z + 3.5,
                       PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        with group("Net"):
            box("Net", (x0, x1, mid_z - 0.1, mid_z + 0.1, GROUND + 0.5, GROUND + 3.5),
                (230, 230, 230), FABRIC, tags=[SPORT_TAG], attrs={SPORT_KIND: "tennis"})
            box("PostW", (x0 - 0.5, x0, mid_z - 0.3, mid_z + 0.3, GROUND, GROUND + 3.5),
                (120, 120, 126), METAL)
            box("PostE", (x1, x1 + 0.5, mid_z - 0.3, mid_z + 0.3, GROUND, GROUND + 3.5),
                (120, 120, 126), METAL)


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


# The school's playing fields.
#
# These four -- court, court, playground, track -- stood on the headland east of
# the city until the water was taken round it. They are not city amenities and
# never really were: the school is the only building in the world that has a use
# for a running track, and it is forty minutes' walk away on the far side of the
# map. They now lie where a school's fields lie, on the open land immediately
# south and west of it.
#
# The band is bounded on three sides by numbers that already existed, and by one
# that did not:
#
#   * east on TOWN_WEST_EDGE -- the town's grass stops there, and the fields'
#     grass starts there. Same edge, two files, no overlap and no gap.
#   * north on SCHOOL_Z0, the school's own south face, so the fields run right up
#     under its windows.
#   * south on STREET_Z0, which is where the town's back-row lawn stops as well.
#     The two southern edges are the same line for the same reason.
#   * west on nothing but width. FIELDS_W is the only picked number here, and it
#     is picked to hold a 140-stud track with a margin either side; the land west
#     of it is empty to the map edge, so it is free to change.
FIELDS_X1 = TOWN_WEST_EDGE
FIELDS_W = 268.0
FIELDS_X0 = FIELDS_X1 - FIELDS_W
FIELDS_Z0, FIELDS_Z1 = STREET_Z0, SCHOOL_Z0

with group("SchoolFields"):
    box("Ground", (FIELDS_X0, FIELDS_X1, FIELDS_Z0, FIELDS_Z1,
                   GROUND_BOTTOM, CITY_GRASS_TOP), LAWN, GRASS)

    # Three paths, tiled rather than crossed. Every one of them stops on the
    # face of the next instead of running through it: two slabs of paving at the
    # same top height sharing a square is check 13's whole subject, and a path
    # network is where that mistake is easiest to make -- a crossroads drawn as
    # two long rectangles is a coplanar overlap by construction.
    #
    # The spine enters on the way the town left for it, at FIELDS_WAY_MID and
    # FIELDS_WAY_PAVE wide, so the two halves of the walk are the same walk.
    FIELDS_SPINE_Z0 = FIELDS_WAY_MID - FIELDS_WAY_PAVE / 2
    FIELDS_SPINE_Z1 = FIELDS_WAY_MID + FIELDS_WAY_PAVE / 2
    FIELDS_PATH_W = 22.0
    # The north-south path, and the one number the courts are hung off.
    FIELDS_CROSS_X1 = -360.0
    FIELDS_CROSS_X0 = FIELDS_CROSS_X1 - FIELDS_PATH_W
    FIELDS_CROSS_MID = (FIELDS_CROSS_X0 + FIELDS_CROSS_X1) / 2
    # The south walk, along the bottom of the band, which is what reaches the
    # track. It stops on the cross path's west face; the cross path runs down to
    # meet it and stops on the spine's south face. Its south edge is measured up
    # from FIELDS_Z0 rather than down from a picked number, so it cannot walk off
    # the end of the ground the way a `FIELDS_Z0 + 14` top edge did.
    FIELDS_SOUTH_Z0 = FIELDS_Z0 + 8.0
    FIELDS_SOUTH_Z1 = FIELDS_SOUTH_Z0 + FIELDS_PATH_W
    FIELDS_SOUTH_MID = (FIELDS_SOUTH_Z0 + FIELDS_SOUTH_Z1) / 2

    box("Spine", (FIELDS_X0 + 6.0, FIELDS_X1, FIELDS_SPINE_Z0, FIELDS_SPINE_Z1,
                  GROUND_BOTTOM, PAVING), PAVING_GREY, PAVEMENT)
    box("CrossWalk", (FIELDS_CROSS_X0, FIELDS_CROSS_X1,
                      FIELDS_SOUTH_Z0, FIELDS_SPINE_Z0,
                      GROUND_BOTTOM, PAVING), PAVING_GREY, PAVEMENT)
    box("SouthWalk", (FIELDS_X0 + 6.0, FIELDS_CROSS_X0,
                      FIELDS_SOUTH_Z0, FIELDS_SOUTH_Z1,
                      GROUND_BOTTOM, PAVING), PAVING_GREY, PAVEMENT)

# The track sits in the south-west, on the only quarter of the band wide enough
# for it, with the south walk running along its foot. The other three face the
# cross path, in the order a school uses them: courts nearest the school, the
# playground furthest from it and nearest the way home.
SPORTS_TRACK_X0, SPORTS_TRACK_X1 = -530.0, -390.0
SPORTS_TRACK_Z0, SPORTS_TRACK_Z1 = -94.0, -24.0
running_track(SPORTS_TRACK_X0, SPORTS_TRACK_X1, SPORTS_TRACK_Z0, SPORTS_TRACK_Z1)
basketball_court(-350.0, -318.0, 34.0, 52.0)
tennis_court(-348.0, -320.0, 4.0, 18.0)
playground(-352.0, -312.0, -46.0, -16.0)

# Trees along the north edge, under the school, and down the west boundary --
# planted on the grass and nowhere near the paving, which check 7 is watching.
with group("SchoolFieldsTrees"):
    # The west boundary row skips the two places a walk reaches the west end of
    # the band. check 7 measures *trunks* against paving -- a canopy over a path
    # is a tree beside a path, a trunk in one is a tree in the middle of it.
    for _tz in range(int(FIELDS_Z0) + 30, int(FIELDS_Z1) - 10, 34):
        if (FIELDS_SPINE_Z0 - 4.0 <= _tz <= FIELDS_SPINE_Z1 + 4.0
                or FIELDS_SOUTH_Z0 - 4.0 <= _tz <= FIELDS_SOUTH_Z1 + 4.0):
            continue
        tree(FIELDS_X0 + 14.0, float(_tz), GROUND, label=f"FieldsTreeW{_tz}")
    for _tx in range(int(FIELDS_X0) + 60, int(FIELDS_X1) - 20, 38):
        tree(float(_tx), FIELDS_Z1 - 6.0, GROUND, label=f"FieldsTreeN{_tx}")

with group("SchoolFieldsFittings"):
    # Both rows are on the spine's south verge, twenty studs apart along it, so
    # a bench faces the walk from one side and a lamp reaches over it from the
    # other -- and neither is standing in the north tree row at FIELDS_Z1 - 6.
    # Both are on grass, so both are given GROUND: street_lamp defaults to
    # PAVING because every other lamp in the city is on a sidewalk, and taking
    # that default here would float them half a stud.
    for _i, _bx in enumerate((-330.0, -420.0, -500.0)):
        bench(_bx, FIELDS_SPINE_Z0 - 5.0, 1, label=f"FieldsBench{_i}")
        street_lamp(_bx + 20.0, FIELDS_SPINE_Z0 - 3.0, 0, floor=GROUND,
                    label=f"FieldsLamp{_i}")

# The ids are the ones Jobs.luau and Config.Locations already name. Only the
# coordinates moved; a place point that changed its id would have moved the
# amenity out of the game as well as across the map.
#
# The track's point is on its own start line rather than out in the infield.
# That is where a runner stands, and it is the one spot on a ring that means
# something -- the centre of a running track is a patch of grass.
for pid, cx, cz in (
    ("basketball_court", -334.0, 43.0),
    ("tennis_court", -334.0, 11.0),
    ("playground", -332.0, -31.0),
    ("running_track", SPORTS_TRACK_X0 + 2.0,
     (SPORTS_TRACK_Z0 + SPORTS_TRACK_Z1) / 2),
):
    place_point(pid, cx, cz, GROUND, f"the {pid.replace('_', ' ')}")


# ---------------------------------------------------------------------------
# Stadium
# ---------------------------------------------------------------------------
#
# The pitch keeps the id `soccer_field` it always had -- Jobs.luau and
# Config.Locations both point at that string -- but everything around it is
# new: four raked stands closing it into a bowl, a stepped dome roof closing
# the bowl itself, a centre-hung scoreboard, hanging light rigs over the
# pitch, and a gated forecourt facing avenue 6.
#
# **Enclosed, and still not a building.** The dome is real geometry -- three
# more concentric roof rings above the one the concourse always had, plus a
# glazed skylight over the pitch itself -- but no part in any of it is named
# `Roof`. check_city's road-access sweep and its building-overlap check both
# key off that one literal name (see the note on check 5), and a raked stand
# with a roof over it is still not a room with a door: nobody is routed
# *into* the dome, they walk through an open gate the same as they always
# did. Naming a part `Roof` here would make the checker start asking the
# stadium a question -- "which door serves you, and how far is it from a
# road" -- that a stadium with four open gates has no single answer to. It
# is what lets the bowl sit in the headland, sixty-odd studs from the
# nearest carriageway, the same way the pitch it replaces always has.
#
# **One ellipse, split into four labelled quarters.** The bowl used to be
# four flat-sided rectangles tiled edge to edge -- the west and east stands
# ran the bowl's full length, corner to corner, and the south and north
# stands filled exactly the gap between them, which tiled with no seam and
# no overlap but did not match the smooth ellipsoid dome sitting on top of
# it (`stadium_roof`). It is a true ellipse now, the same shape the dome
# is, built with `elliptical_ring` (see the Curves section) and cut into
# four 90-degree arcs only so each arc can still carry its own `Stand`
# label -- StadiumCrowdService and `Config.Stadium.StandFacing` both read
# that label, and reusing the same four names (`StandEast` etc.) for the
# four arcs meant neither needed to change for the bowl to go round; see
# `stadium_bowl`.
STAD_GAP = 5.0                        # clear ground between the touchline and the first tier
STAD_TIERS = 5
STAD_RISE = 3.0                       # studs climbed per tier -- taller stands, same footprint
STAD_TREAD = 6.0                      # studs deep per tier
STAD_DEPTH = STAD_TIERS * STAD_TREAD  # 30.0
STAD_CONCOURSE = 8.0                  # flat, roofed walkway behind the top tier
STAD_MARGIN = STAD_GAP + STAD_DEPTH + STAD_CONCOURSE  # 43.0, pitch edge to outer wall
STAD_TOP_Y = GROUND + STAD_TIERS * STAD_RISE  # top of the highest seating tier

# The pitch used to sit fixed at x 855..925, z 460..570 and only the bowl's own
# envelope (`STAD_WEST_OUT`..`STAD_NORTH_OUT`, below) moved to chase it. That
# could not do two things a real stadium wants at once: sit the pitch exactly
# in the middle of the bowl on both axes, and grow the bowl noticeably bigger,
# because the one side that cannot move (`STAD_WEST_OUT`, pinned to the
# entrance building's sidewalk clearance -- see below) forces the bowl's own
# centre east of any pitch that stays put, and the crossing 3 studs south of
# the old south wall left no room to grow that axis either. Both limits are
# about where the *bowl* sits, not where the *pitch* has to -- so the pitch
# moves too, east and north into the slack the bowl's fixed neighbours were
# not using, and the bowl grows to fill the room that opens up behind it.
#
# Moved: +7 in x (855..925 to 862..932), +40 in z (460..570 to 500..610).
# Both chosen so the bowl's centre lands exactly on the new pitch centre on
# both axes -- true centring, not the 4-stud x drift or the z-only centring
# either previous pass settled for -- while every wall still clears its own
# real obstacle by a comfortable margin (checked against each below).
STAD_PX0, STAD_PX1 = 862.0, 932.0
STAD_PZ0, STAD_PZ1 = 500.0, 610.0

# Whether a bowl this size actually clears the pitch is not a question one
# radius can answer: the innermost tier's boundary sits at a fixed inset
# (`STAD_CONCOURSE + STAD_TIERS * STAD_TREAD` = 38 studs) in from the outer
# wall, not from the pitch, and a rectangle's corner is `sqrt(2)` further from
# centre than its edge -- so an ellipse can clear both touchlines and both
# goal lines and still cut through all four corners of the pitch rectangle,
# which is exactly what the original symmetric 43-stud-margin bowl did (12 of
# the first tier's 24 facets landing inside the pitch). Checked properly this
# time: every one of the 5 tiers' 24 facets, tested as the oriented box it
# actually is against the pitch rectangle, not just each facet's own radius
# against the pitch's radius at that angle -- the cheaper check is what let
# the previous pass believe 6 facets still clipped the corners when the true,
# full-box count at that geometry was 18. At the geometry below it is 0.
STAD_WEST_OUT = 812.0    # unchanged -- see why, below
STAD_EAST_OUT = 982.0    # 13 studs clear of the headland shore at 995
STAD_SOUTH_OUT = 418.0   # 10 studs clear of the wp_bay_head_s crossing at 408
STAD_NORTH_OUT = 692.0   # 12 studs clear of the wp_bay_head_n crossing at 704
# The bowl is now the only reason the headland is land, so the headland is the
# thing it has to fit inside rather than a backdrop it happens to sit on. Both
# ends of it are within one HEADLAND_CLEAR of the water, and a nudge to either
# number that put a stand in the bay would otherwise show up as a stadium with
# no shoreline in front of it -- which reads as scenery, not as a mistake.
assert (STAD_SOUTH_OUT - HEADLAND_Z0 >= HEADLAND_CLEAR
        and HEADLAND_Z1 - STAD_NORTH_OUT >= HEADLAND_CLEAR), (
    f"the stadium runs z {STAD_SOUTH_OUT}..{STAD_NORTH_OUT} on a headland of "
    f"z {HEADLAND_Z0}..{HEADLAND_Z1}, which leaves less than "
    f"{HEADLAND_CLEAR} studs of shore at one end. Move the bowl or lengthen "
    f"the headland -- HEADLAND_Z0/Z1 are where the water starts.")
# West does not move. `StadiumForecourt`'s `MainEntrance` sits directly
# against this wall (`ex1 = STAD_WEST_OUT`, see below) and needs the 12
# studs between it and avenue 6's sidewalk at 799 that it already has at
# 812 -- shrinking this wall shrinks that gap first and reopens the exact
# sidewalk collision `check_city` caught once already (see the comment on
# `ex0` below). Moving the entrance instead of the wall was ruled out: it is
# glued to this wall by design, on the one side of the bowl that faces a
# road at all. Because west cannot move, `STAD_PX0`/`STAD_PX1` moved to it
# instead: the pitch's own centre in x is now exactly `(STAD_WEST_OUT +
# STAD_EAST_OUT) / 2`, so the bowl's centre sits on the pitch's on this axis
# without needing the wall to give any ground at all.
#
# South had the least room of any side (`STAD_SOUTH_OUT` used to sit only 3
# studs clear of the crossing at 408) and north had the most (81 studs to the
# running track) -- both symptoms of the same thing, a bowl sitting off-centre
# in the 292-stud gap between those two fixed lines (408 and 700). Moving the
# pitch's own centre 40 studs north balances that gap instead of just growing
# into whichever half of it happened to be free, which is what makes 0-overlap
# *and* a visibly bigger bowl possible together: south buys back the margin it
# was missing, north spends some of the margin it never needed, and the bowl
# itself grows from 82x104 to 85x137 -- noticeably longer down the pitch,
# which is the axis a stand actually reads size on. East, the one side with
# no fixed neighbour on this axis, grows independently to the same 0-overlap
# search rather than by a fixed amount.
#
# The pitch itself stays its current 70x110 -- lengthening it was tried in an
# earlier pass and only tightened the tightest buffer above for no clearance
# gained; moving the whole pitch, not resizing it, is what actually had room
# to give.

STAD_SEATS = [(178, 46, 46), (210, 210, 214)]   # home red, alternating with a pale away band
STAD_STRUCTURE = CONCRETE_GREY


def stadium_seat(cx, cz, y0, index, stand_label):
    """One physical stadium seat, tinted in the tier's own alternating
    home/away banding (`STAD_SEATS`) -- and, tagged `STADIUM_CROWD_SEAT_TAG`,
    the StadiumCrowdService anchor a real NPC sits at. There is no static
    crowd separate from the real one any more (see the crowd-tag header
    comment): every seat in every tier is one of these, so an empty seat
    still reads as a seat -- the bowl looks properly tiered and full of
    banding even before a single fan sits down -- and a real avatar dropped
    onto this same tag just occupies the seat it was already standing in
    front of, rather than crowding in beside a static double."""
    box(f"Seat{index}", (cx - 0.9, cx + 0.9, cz - 0.9, cz + 0.9, y0, y0 + 1.0),
        STAD_SEATS[index % 2], PLASTIC,
        tags=[STADIUM_CROWD_SEAT_TAG], attrs={STADIUM_CROWD_STAND_ATTR: stand_label})


def stadium_crowd_arc(cx, cz, rx, rz, phi0, phi1, y0, start_index, stand_label, exclude_phi=None):
    """Real seats scattered along one curved tier at roughly `step` studs of
    arc apart -- the elliptical equivalent of the old `stadium_crowd_row`.
    Every position built is a `stadium_seat`, denser than the old mannequin
    row was (3 studs of arc instead of 5) since a seat is one box, not the
    two-box mannequin plus occasional anchor this replaces -- more of the
    bowl actually seatable, not more parts than before.

    `exclude_phi`, an optional `(lo, hi)` degree window, skips seats inside
    it entirely -- StandWest cuts a vomitory tunnel through every tier at
    phi=180 (see `stadium_bowl`), and a row of seats floating in that open
    doorway would be exactly the "stands blocking the entrance" bug the
    tunnel exists to fix, just moved one layer out."""
    step = 3.0
    mid_r = (rx + rz) / 2.0
    step_deg = step * 180.0 / (math.pi * mid_r)
    n = max(int((phi1 - phi0) / step_deg), 1)
    index = start_index
    for k in range(n):
        phi = phi0 + step_deg / 2 + k * step_deg
        if exclude_phi is not None and exclude_phi[0] <= phi <= exclude_phi[1]:
            continue
        px, pz = ellipse_point(phi, cx, cz, rx, rz)
        stadium_seat(px, pz, y0, index, stand_label)
        index += 1
    return index


def stadium_crowd_roam_arc(cx, cz, rx, rz, phi0, phi1, y0, stand_label):
    """Six stops along a stand's curved concourse, tagged as one roam loop --
    the elliptical equivalent of the old `stadium_crowd_roam_loop`. Six, not
    the original four: `Config.Stadium.MaxRoamingCrowd` is going up
    substantially so the stands read as properly walked, and
    StadiumCrowdService divides that cap evenly across the four stands and
    puts every roamer for a stand on the same loop (`indexAnchors`) -- a
    bigger loop is more of the concourse actually walked per lap, not more
    roamers bunched retracing the same four corners."""
    for i, f in enumerate((0.08, 0.26, 0.44, 0.56, 0.74, 0.92)):
        phi = phi0 + (phi1 - phi0) * f
        px, pz = ellipse_point(phi, cx, cz, rx, rz)
        box(f"RoamAnchor{stand_label}{i}", (px - 0.3, px + 0.3, pz - 0.3, pz + 0.3, y0, y0 + 0.2),
            STAD_STRUCTURE, PLASTIC, transparency=1.0, collide=False,
            tags=[STADIUM_CROWD_ROAM_TAG], attrs={STADIUM_CROWD_STAND_ATTR: stand_label})


def stad_ellipse(inset):
    """(cx, cz, rx, rz) for the ellipse `inset` studs in from the stadium's
    outer envelope on every side -- the elliptical equivalent of the old
    `inset_rect`, and the one shape the bowl's tiers, its concourse and its
    dome are all built from, so they stay concentric and actually match
    each other. `STAD_WEST_OUT`..`STAD_NORTH_OUT` (see the corner-clearance
    comment above them) are chosen so this ellipse's centre lands exactly on
    the pitch's own centre on both axes: the pitch itself moved to sit in the
    middle of the site's real slack rather than the envelope being pulled
    off-centre around a fixed pitch, so there is no drift left on either
    axis to note here any more. Every real caller stays inside
    STAD_GAP..STAD_MARGIN."""
    cx = (STAD_WEST_OUT + STAD_EAST_OUT) / 2
    cz = (STAD_SOUTH_OUT + STAD_NORTH_OUT) / 2
    return (cx, cz, (STAD_EAST_OUT - STAD_WEST_OUT) / 2 - inset,
            (STAD_NORTH_OUT - STAD_SOUTH_OUT) / 2 - inset)


def stad_quadrant(i, segs=CIRCLE_SEGS):
    """Which of the four stands facet `i` of a `segs`-facet ring belongs to.
    Facets are grouped in blocks of `segs / 4`, offset by half a block so
    facet 0 -- due east, phi=0 -- sits in the middle of its own stand
    instead of straddling a seam between two; see `stadium_bowl`. Reusing
    the four original stand names (`StandEast` etc.) rather than inventing
    new ones means `Config.Stadium.StandFacing` and StadiumCrowdService
    need no change at all for the bowl to go from four flat sides to a true
    ellipse -- only where the boundary between stands falls has moved."""
    per = segs // 4
    return ("StandEast", "StandNorth", "StandWest", "StandSouth")[((i + per // 2) // per) % 4]


STAD_STAND_ARC = 90.0  # each of the four stands still covers one quarter of the bowl
STAD_STAND_PHI0 = {"StandEast": -45.0, "StandNorth": 45.0, "StandWest": 135.0, "StandSouth": 225.0}


def stadium_bowl():
    """The bowl itself: four stands, each a 90-degree arc of one ellipse,
    replacing the old `stand_ns`/`stand_ew` pair of flat-sided rectangles
    tiled edge to edge. The rectangles tiled cleanly and cheaply, but they
    tiled into a *rectangle* -- a stepped, square-cornered bowl sitting
    directly under a smooth ellipsoid dome (`stadium_roof`), which is
    exactly the mismatch this function exists to fix. Splitting the new
    ellipse into quarters rather than building it as one continuous ring
    keeps everything about the old per-stand structure that still matters:
    one Roblox group per stand, one `Stand` label per group (unchanged, see
    `stad_quadrant`), a crowd arc per tier and a roam loop on the
    concourse -- the shape underneath all of it is simply the same ellipse
    the dome already is, instead of a different one."""
    for stand, phi0 in STAD_STAND_PHI0.items():
        phi1 = phi0 + STAD_STAND_ARC
        keep = lambda i, s=stand: stad_quadrant(i) == s
        # StandWest's facet 12 gets a full cut through every tier, not just the
        # lintel-door the outer Concourse wall gets below -- "remove the stands
        # only directly in front of the entrance" means a real vomitory tunnel
        # you can walk straight through from the atrium to the pitch-side
        # walkway, not a doorway into a wall of seating that is still solid
        # behind it. `tier_keep` drops facet 12 from every `Tier{i}` ring
        # outright; `tunnel_phi` is that same facet's angular span, so the
        # seats scattered across the tier (`stadium_crowd_arc`) skip it too --
        # a row of seats floating in an open doorway is exactly this same bug.
        tier_keep = keep
        tunnel_phi = None
        if stand == "StandWest":
            half_facet = 180.0 / CIRCLE_SEGS
            tier_keep = lambda i, s=stand: stad_quadrant(i) == s and i != 12
            tunnel_phi = (180.0 - half_facet, 180.0 + half_facet)
        with group(stand):
            crowd_index = 0
            for i in range(STAD_TIERS):
                near_inset = STAD_CONCOURSE + (STAD_TIERS - i) * STAD_TREAD
                far_inset = STAD_CONCOURSE + (STAD_TIERS - i - 1) * STAD_TREAD
                cx, cz, rx_near, rz_near = stad_ellipse(near_inset)
                _, _, rx_far, rz_far = stad_ellipse(far_inset)
                y1 = GROUND + (i + 1) * STAD_RISE
                elliptical_ring(f"Tier{i}", cx, cz, rx_far, rz_far, rx_near, rz_near,
                                 GROUND, y1, STAD_SEATS[i % 2], CONCRETE, keep=tier_keep)
                _, _, rx_mid, rz_mid = stad_ellipse((near_inset + far_inset) / 2)
                crowd_index = stadium_crowd_arc(cx, cz, rx_mid, rz_mid, phi0, phi1,
                                                 y1, crowd_index, stand, exclude_phi=tunnel_phi)
            top_y = STAD_TOP_Y
            cx, cz, rx_out, rz_out = stad_ellipse(0.0)
            _, _, rx_in, rz_in = stad_ellipse(STAD_CONCOURSE)
            # Facet 12 is centred on phi=180 -- due west, the middle of
            # StandWest's own arc -- and is where `stadium_entrance`'s own
            # doorway lines up (see `stadium()`); every other facet, on
            # every stand, is a solid wall the way the old rectangular
            # Concourse always was outside its one gated stand.
            door_facets = {12} if stand == "StandWest" else ()
            elliptical_ring("Concourse", cx, cz, rx_out, rz_out, rx_in, rz_in,
                             GROUND, top_y, STAD_STRUCTURE, CONCRETE, keep=keep,
                             door_facets=door_facets, door_head=12.0)
            if stand == "StandWest":
                # `door_facets` cuts the wall open above a 12-stud lintel, but
                # a bare lintel over a gap reads as damage to the wall, not a
                # gate -- nothing marks the opening as the entrance from the
                # bowl's own side. `stadium_entrance` already builds the real
                # atrium out in the forecourt and leaves its own back wall
                # open on this same centreline (see that function's
                # docstring), so this is deliberately not a second building:
                # just a header and two piers dressing the one doorway the
                # bowl itself cuts, the last few studs of the walk from the
                # atrium to the concourse.
                half = math.radians(180.0 / CIRCLE_SEGS)
                door_half_w = rx_out * math.sin(half)
                gx, gz = STAD_WEST_OUT, cz
                with group("GateArch"):
                    for side in (-1, 1):
                        pz = gz + side * (door_half_w + 1.2)
                        box(f"Pier{side}", (gx - 1.5, gx + 1.5, pz - 1.2, pz + 1.2,
                                            GROUND, GROUND + 13.5),
                            STAD_STRUCTURE, CONCRETE)
                        with at(gx, pz, floor=GROUND):
                            part("Lamp", (0, 12.5, 0), (0.8, 0.8, 0.8), FITTING, NEON,
                                 children=point_light(LAMP_LIGHT, 2.0, 24.0))
                    box("Header", (gx - 1.8, gx + 1.8,
                                    gz - door_half_w - 1.2, gz + door_half_w + 1.2,
                                    GROUND + 13.5, GROUND + 16.0),
                        STAD_STRUCTURE, CONCRETE)
                    box("Sign", (gx - 2.1, gx - 1.8, gz - 9.0, gz + 9.0,
                                  GROUND + 13.8, GROUND + 15.4),
                        STAD_STRUCTURE, SMOOTH,
                        children=sign("MAIN GATE", "left", color=(250, 246, 234), size=40))
                    # A banner in the home kit's own red on each pier, hung from
                    # the header down -- the one visual tie between this gate and
                    # the bowl it stands in, so the last few studs of the walk from
                    # the atrium read as arriving at *this* team's stadium and not
                    # a generic concrete doorway. STAD_SEATS[0] is that same red.
                    for side in (-1, 1):
                        pz = gz + side * (door_half_w + 1.2)
                        box(f"Banner{side}", (gx - 1.65, gx - 1.35, pz - 1.0, pz + 1.0,
                                              GROUND + 6.0, GROUND + 13.4),
                            STAD_SEATS[0], FABRIC)
                    # An invisible, non-colliding trigger spanning the doorway itself --
                    # StadiumEntranceService reads STADIUM_GATE_TAG to know when a player
                    # has actually walked through this gate (not just stood near the
                    # piers), and plays the entrance moment once per session. Centred in
                    # the opening rather than on a pier, so the distance check in the
                    # service is a true "crossed the threshold" rather than "approached
                    # one side of it".
                    box("EntranceTrigger", (gx - 1.0, gx + 1.0,
                                             gz - door_half_w, gz + door_half_w,
                                             GROUND, GROUND + 6.0),
                        STAD_STRUCTURE, SMOOTH, transparency=1, collide=False,
                        tags=[STADIUM_GATE_TAG])
            elliptical_ring("RoofSlab", cx, cz, rx_out, rz_out, rx_in, rz_in,
                             top_y + 7.0, top_y + 7.6, ROOF_GREY, METAL, keep=keep)
            rx_c, rz_c = (rx_out + rx_in) / 2, (rz_out + rz_in) / 2
            for f in (0.15, 0.5, 0.85):
                phi = phi0 + (phi1 - phi0) * f
                sx, sz = ellipse_point(phi, cx, cz, rx_c, rz_c)
                box(f"RoofStrut{phi:.0f}", (sx - 0.5, sx + 0.5, sz - 0.5, sz + 0.5,
                                            top_y, top_y + 7.0), STEEL, METAL)
            stadium_crowd_roam_arc(cx, cz, rx_c, rz_c, phi0, phi1, top_y, stand)


DOME_GLASS = (210, 228, 236)  # a pale sky-blue tint, not clear -- see stadium_roof


def dome_rib(label, inset, y, half_thick=0.9):
    """A white structural rib at one seam of the dome, standing slightly
    proud of the glass on both sides of it -- the visible frame lines a
    glazed dome actually hangs its panels from, the same read as the arches
    in a big-league stadium render: white steelwork over blue glass, not
    glass with no structure at all. Built from `stad_ellipse`, the same
    shape `stadium_bowl`'s tiers and concourse are, so the rib sits flush
    with the bowl underneath it rather than the rectangle it used to. No
    floor at zero here on purpose: `STAD_DOME_INSET` is now slightly
    negative (see below) so this rib, like the shell it sits on, is meant
    to sit outside `stad_ellipse(0.0)`, not be pulled back to it."""
    cx, cz, rx_out, rz_out = stad_ellipse(inset - half_thick)
    _, _, rx_in, rz_in = stad_ellipse(inset + half_thick)
    elliptical_ring(label, cx, cz, rx_out, rz_out, rx_in, rz_in,
                     y - 0.5, y + 0.5, TRIM_WHITE, METAL)


# The dome's rim used to sit 8, then 4, studs in from the outer envelope --
# tucked inside the concourse's own RoofSlab so the glass never quite
# reached the edge the bowl itself is built to. Landing the shell's equator
# on `stad_ellipse(0.0)` exactly closed that -- almost. `Concourse` and
# `RoofSlab` are `elliptical_ring`s: `CIRCLE_SEGS` (24) flat facets, each
# one *tangent* to the true ellipse at its own centre angle
# (`ellipse_outward_yaw` is the true outward normal there), so each facet's
# corners sit slightly outside the smooth curve a tangent always lies
# outside a convex curve except at the touch point, the same reason a
# circumscribed hexagon's corners poke out past the circle it wraps. The
# shell, drawn by `ball` as a true ellipsoid, has no corners: it touches
# `stad_ellipse(0.0)` exactly at 24 points and sits a hair inside the
# concrete everywhere between them, which is the same "frame poking out
# past the glass" symptom as before, just shrunk from 4 studs to a fraction
# of one. STAD_DOME_INSET goes negative to fix it for the same reason it
# went to zero: not a guess, but `stad_ellipse`'s own inset arithmetic run
# backwards by the exact amount a facet's corner overshoots its centre --
# r*(sec(180/24 degrees) - 1), worst case (the shorter, west-east radius,
# 78 studs) about 0.68 studs, the longer one about 0.85. -1.2 clears both
# with room, so the smooth shell now runs past every facet corner on the
# building beneath it rather than stopping a fraction of a stud short of
# them all the way round.
STAD_DOME_INSET = -1.2
STAD_BOWL_RISE = 85.0   # rim to the top of the bowl-shaped lower dome
STAD_CAP_RISE = 40.0    # the cupola's own further climb, rim to apex is the sum


def stad_dome_geometry():
    """(cx, cz, rim_y, rx, rz, ry) for the dome's own ellipsoid -- the one
    piece of geometry `stadium_roof` (which draws the shell) and
    `stadium_light_rig` (which needs to know exactly where the shell's
    interior surface is above a given x/z, not a guessed height) both need,
    computed in one place so the two can never quietly drift apart."""
    cx, cz, rx, rz = stad_ellipse(STAD_DOME_INSET)
    rim_y = STAD_TOP_Y + 7.6      # concourse RoofSlab's own top
    ry = STAD_BOWL_RISE + STAD_CAP_RISE
    return cx, cz, rim_y, rx, rz, ry


def dome_ceiling_y(x, z):
    """The dome's own interior ceiling height directly above (x, z), solved
    from the ellipsoid equation itself: (x/rx)^2 + (z/rz)^2 + (y/ry)^2 = 1
    rearranged for y. Outside the shell's own footprint this goes complex
    and is clamped to the rim -- callers stay inside the bowl, where it
    never comes up."""
    cx, cz, rim_y, rx, rz, ry = stad_dome_geometry()
    dx, dz = (x - cx) / rx, (z - cz) / rz
    under = max(1.0 - dx * dx - dz * dz, 0.0)
    return rim_y + ry * math.sqrt(under)


DOME_BANDS = 10  # latitude rings from rim to apex -- see dome_shell


def dome_shell(cx, cz, rim_y, rx, rz, ry, segs=CIRCLE_SEGS, bands=DOME_BANDS):
    """The dome's actual glazed surface, built as a `bands` x `segs` grid of
    flat panels rather than a single `Part.Shape=Ball`.

    A ball was tried first, and it looked right from outside and was wrong
    underneath: `Part.Shape=Ball` is always a full ellipsoid, symmetric
    about its own centre, so a ball wide and tall enough to read as this
    dome's *top* half also draws an equal, mirror-image bottom half --
    for `ry` this size that is 100+ studs of solid "sphere" hanging in the
    open air under the map, not hidden inside the concourse the way the
    old, much shorter version's buried half was, just a sphere a player
    could swim down and see. A dome is a half of that shape, on purpose,
    and there is no half-ball primitive to ask Roblox for -- so this
    builds only the half that is wanted, panel by panel, and the bottom
    half simply does not exist as geometry any more rather than existing
    and being hidden.

    Each panel is a `tilted_box`, banked to the ellipsoid's own true
    outward normal at its own centre point -- `(x/rx^2, y/ry^2, z/rz^2)`,
    the three-dimensional form of the same gradient `ellipse_outward_yaw`
    already reads off the flat horizontal case -- so panels bank upward
    band by band the way real glazed-panel domes (this is what a big
    stadium roof actually looks like up close: a grid of flat glass
    trapezoids, not one continuous curved pane) do, rather than standing
    vertical like `elliptical_ring`'s walls and stepping over each other
    like the terrace stack this replaced twice now."""
    with group("DomeShell"):
        half = math.radians(180.0 / segs)
        for k in range(bands):
            theta0 = math.radians(90.0 * k / bands)
            theta1 = math.radians(90.0 * (k + 1) / bands)
            theta_m = (theta0 + theta1) / 2
            sm, ym = math.cos(theta_m), rim_y + ry * math.sin(theta_m)
            with group(f"Band{k}"):
                for i in range(segs):
                    phi = math.radians(i * (360.0 / segs))

                    def surf(theta, phi):
                        s = math.cos(theta)
                        return (cx + rx * s * math.cos(phi),
                                rim_y + ry * math.sin(theta),
                                cz + rz * s * math.sin(phi))

                    px, py, pz = surf(theta_m, phi)
                    wx0, wy0, wz0 = surf(theta_m, phi - half)
                    wx1, wy1, wz1 = surf(theta_m, phi + half)
                    width = math.dist((wx0, wy0, wz0), (wx1, wy1, wz1))
                    hx0, hy0, hz0 = surf(theta0, phi)
                    hx1, hy1, hz1 = surf(theta1, phi)
                    rise = math.dist((hx0, hy0, hz0), (hx1, hy1, hz1))

                    nx, nz = math.cos(phi) * sm / rx, math.sin(phi) * sm / rz
                    ny = math.sin(theta_m) / ry
                    nlen = math.sqrt(nx * nx + ny * ny + nz * nz)
                    nx, ny, nz = nx / nlen, ny / nlen, nz / nlen
                    pitch = math.degrees(math.asin(max(-1.0, min(1.0, ny))))
                    yaw = math.degrees(math.atan2(-nz, nx))

                    rbxmx.tilted_box(f"Panel{i}", (px, py, pz),
                                      (0.6, rise, width), yaw, pitch,
                                      DOME_GLASS, GLASS, transparency=0.45,
                                      collide=False)


def stadium_roof():
    """Closes the bowl -- and closes it *tall*. `stadium_bowl` caps the
    outer 8 studs of concourse with a thin RoofSlab; from that slab's top, a
    single glazed dome climbs to a crown roughly a full office tower above
    the ground (compare `FADE_STOREYS_BY_RING`, which tops out downtown at 7
    storeys times STOREY=15 -- this reaches past that on purpose, because a
    stadium is the one building in this city that is supposed to dwarf
    everything else on the skyline).

    The ellipsoid's equator sits at the rim and reaches slightly past the
    stadium's own outer edge, past every corner the facets of the concrete
    ring underneath it turn (see `STAD_DOME_INSET` above), and its pole
    reaches `STAD_BOWL_RISE + STAD_CAP_RISE` studs above that -- both grown
    past what the old terrace stack climbed, because a dome sized to a true
    ellipse instead of a rectangle reads as small unless it is also taller
    than the building it used to just barely clear. It is only ever the
    upper half: see `dome_shell` for why this is no longer a `Part.Shape`
    ellipsoid with an unseen mirror-image bottom half buried in the ground.
    A few white belts mark it with structure, each sized to the ellipsoid's
    own radius at that exact height (read off the ellipsoid equation, not
    guessed) so every one sits flush against the glass, and a small cupola
    caps the apex."""
    cx, cz, rim_y, rx, rz, ry = stad_dome_geometry()
    dome_rib("DomeRib_rim", STAD_DOME_INSET, rim_y)

    dome_shell(cx, cz, rim_y, rx, rz, ry)

    def belt(label, fraction, half_thick=0.9):
        """A thin white ring hugging the shell's true surface `fraction` of
        the way from rim to apex. `scale` is the ellipsoid equation itself
        (x/rx)^2 + (z/rz)^2 + (y/ry)^2 = 1 solved for the horizontal radius
        at that height, not a guessed inset -- which is what keeps every
        belt flush against the glass instead of floating off it or biting
        into it."""
        y = rim_y + ry * fraction
        scale = math.sqrt(max(1 - fraction ** 2, 0.0))
        hx, hz = rx * scale, rz * scale
        elliptical_ring(label, cx, cz, hx + half_thick, hz + half_thick,
                         hx - half_thick, hz - half_thick,
                         y - 0.5, y + 0.5, TRIM_WHITE, METAL)

    belt("DomeBelt1", 0.28)
    belt("DomeBelt2", 0.56)
    belt("DomeBelt3", 0.82)

    apex_y = rim_y + ry
    box("DomeCrownCap", (cx - 4.0, cx + 4.0, cz - 4.0, cz + 4.0, apex_y - 1.0, apex_y + 1.5),
        TRIM_WHITE, METAL)
    return apex_y


STAD_RIG_DROP = 3.0  # how far below the glass a rig hangs -- see stadium_light_rig


def stadium_light_rig(x, z, label):
    """A light fixture hung from the roof rather than standing on a mast --
    the exterior floodlight masts this replaces were 52 studs tall, which
    is nowhere close to the underside of a dome that now climbs past 150,
    so the lamps move to where a domed stadium actually puts them: banks
    mounted straight off the ceiling above them. `dome_ceiling_y(x, z)`
    solves the ellipsoid for its own interior height at this exact point,
    so the rig hangs on a short, fixed `STAD_RIG_DROP` off the true glass
    instead of a long cable reaching for a guessed generic height that used
    to leave forty-plus studs of bare air between the fixture and the roof
    it was supposed to read as mounted to. Six lamps aimed down, the same
    honest downward-cast `floodlight_mast` used rather than an aimed cone
    at the centre spot."""
    ceiling = dome_ceiling_y(x, z)
    rig_y = ceiling - STAD_RIG_DROP
    with group(label):
        box("Cable", (x - 0.3, x + 0.3, z - 0.3, z + 0.3, rig_y, ceiling),
            STEEL, METAL)
        box("Rig", (x - 5.0, x + 5.0, z - 2.0, z + 2.0, rig_y - 0.6, rig_y),
            FITTING, METAL)
        for i, lx in enumerate((-4.0, -2.4, -0.8, 0.8, 2.4, 4.0)):
            box(f"Lamp{i}", (x + lx - 0.6, x + lx + 0.6, z - 0.6, z + 0.6,
                             rig_y - 0.7, rig_y - 0.6), FITTING, NEON,
                children=spot_light(LAMP_LIGHT, 4.0, 140.0, "bottom", angle=65.0))


STAD_GATE_HALF = 9.0  # half-width of this atrium's own front doorway


def stadium_entrance(x0, x1, z0, z1, label):
    """The stadium's proper main entrance: a walled, roofed atrium standing
    in the forecourt, built to the bar the rest of the sports sector already
    holds itself to -- see `boxing_hall`/`court_hall`, which get a real
    front wall, a centred doorway with a lintel, glazing either side of it
    and a fascia sign readable from the street. The stadium's old `MainGate`
    was two posts and a lintel standing in front of a solid wall with no
    opening cut through it at all -- decoration, not a door. This building
    is a door: its own front doorway is `STAD_GATE_HALF` wide, and its back
    (east) side is left open on purpose, because that is exactly where
    `stadium_bowl`'s own StandWest doorway (facet 12, roughly 20 studs
    wide) is cut through the bowl's outer Concourse wall (see `stadium()`)
    -- the two openings sit on the same centreline, `fmid`, so the walk
    from the palms outside to the concourse inside is unbroken, not two
    doors that happen to be near each other."""
    ix0 = x0 + WALL
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    eave = STAD_TOP_Y - 2.0
    with group(label):
        # An inlay: this building stands on the forecourt, which is paved to
        # GROUND under the whole of it before anything goes up.
        box("Slab", (x0, x1, z0, z1, GROUND, GROUND + FLOOR_INLAY),
            FLOOR_INDOOR, MARBLE)
        wall("WallSouth", (x0, x1, z0, z0 + WALL, GROUND, eave), STAD_STRUCTURE, CONCRETE,
             along="x")
        wall("WallNorth", (x0, x1, z1 - WALL, z1, GROUND, eave), STAD_STRUCTURE, CONCRETE,
             along="x")
        wall("WallFront", (x0, ix0, z0, z1, GROUND, eave), STAD_STRUCTURE, CONCRETE,
             along="z", doors=((cz - STAD_GATE_HALF, cz + STAD_GATE_HALF),), head=12.0)
        glass_doors("MainDoors", (x0 + 0.1, ix0 - 0.1, cz - STAD_GATE_HALF, cz + STAD_GATE_HALF,
                                   GROUND, GROUND + DOOR_HEIGHT), along="z", leaves=4)
        glazing("FrontS", (x0 + 0.4, ix0 - 0.4, z0 + WALL + 1.0, cz - STAD_GATE_HALF - 0.4,
                           GROUND + 12.0, eave - 1.0), along="z", panes=2)
        glazing("FrontN", (x0 + 0.4, ix0 - 0.4, cz + STAD_GATE_HALF + 0.4, z1 - WALL - 1.0,
                           GROUND + 12.0, eave - 1.0), along="z", panes=2)
        box("Canopy", (x0 - 4.0, x1, z0, z1, eave, eave + 1.0), DOME_GLASS, GLASS,
            transparency=0.35)
        for rz in (z0 + 3.0, cz, z1 - 3.0):
            box(f"CanopyRib{rz:.0f}", (x0 - 4.0, x0, rz - 0.5, rz + 0.5,
                                       eave - 7.0, eave + 1.0), TRIM_WHITE, METAL)
        box("Sign", (x0 - 0.5, x0 + 0.5, cz - 15.0, cz + 15.0, eave - 7.0, eave - 3.0),
            STAD_STRUCTURE, SMOOTH,
            children=sign("CITY STADIUM", "left", color=(250, 246, 234), size=56))
        for tz in (cz - 5.0, cz - 1.6, cz + 1.6, cz + 5.0):
            with at(cx, tz, floor=GROUND):
                part("Turnstile", (0, 1.8, 0), (1.0, 3.6, 1.0), STEEL, METAL)
        street_lamp(x0 - 5.0, z0 + 2.0, 1, floor=GROUND)
        street_lamp(x0 - 5.0, z1 - 2.0, 1, floor=GROUND)


def stadium():
    fmid = (STAD_PZ0 + STAD_PZ1) / 2
    # One ellipse, four quarters -- see `stadium_bowl`'s own header for why
    # this replaced the four flat-sided rectangles the bowl used to be
    # tiled from. StandWest's one doorway (facet 12, phi=180) is cut inside
    # `stadium_bowl` itself, lined up with `stadium_entrance`'s own front
    # door below.
    stadium_bowl()

    stadium_roof()

    # Four rigs over the pitch's quarter-points rather than four masts at the
    # corners -- the corner masts stood 52 studs tall, a third of the way up
    # a dome that now climbs past 100, and a dome with masts sticking up
    # through it reads as broken, not as a stadium. Hanging them from the
    # roof is also just correct: an enclosed stadium lights its pitch from
    # the roof it built.
    pw, pd = STAD_PX1 - STAD_PX0, STAD_PZ1 - STAD_PZ0
    for qx, qz in ((STAD_PX0 + pw * 0.25, STAD_PZ0 + pd * 0.25),
                   (STAD_PX0 + pw * 0.75, STAD_PZ0 + pd * 0.25),
                   (STAD_PX0 + pw * 0.25, STAD_PZ0 + pd * 0.75),
                   (STAD_PX0 + pw * 0.75, STAD_PZ0 + pd * 0.75)):
        stadium_light_rig(qx, qz, f"LightRig_{qx:.0f}_{qz:.0f}")

    with group("Scoreboard"):
        # Hung from the roof over the pitch rather than standing on its own
        # post outside the touchline -- the old post-mounted board's top sat
        # at G+38, which the dome now clears easily, but a centre-hung board
        # is the bigger, better read: a video-wall on a long cable dropping
        # out of the glass above centre pitch, not a sign on a stick by the
        # corner flag. Two faces, one for each half of the pitch, since a
        # centre-hung board has to read from both ends the way a real
        # stadium's does.
        sb_cx = (STAD_PX0 + STAD_PX1) / 2
        sb_cz = STAD_PZ0 + pd * 0.5
        sb_top = STAD_TOP_Y + 48.0
        sb_bottom = sb_top - 12.0
        box("Cable", (sb_cx - 1.0, sb_cx + 1.0, sb_cz - 1.0, sb_cz + 1.0,
                      sb_top, sb_top + 40.0), STEEL, METAL)
        box("Board", (sb_cx - 22.0, sb_cx + 22.0, sb_cz - 0.9, sb_cz + 0.9,
                      sb_bottom, sb_top), (20, 22, 26), SMOOTH,
            children=sign("HOME 0  -  0  AWAY", "front", color=NEON_AMBER, size=72)
            + sign("HOME 0  -  0  AWAY", "back", color=NEON_AMBER, size=72)
            + point_light(NEON_AMBER, 1.4, 50.0))

    with group("StadiumForecourt"):
        # A long plaza rather than a gate-width strip -- the dome is the
        # thing that makes the stadium read as big from across the
        # headland, but a landmark this size wants a landmark's forecourt
        # in front of it: palms, benches, room for a crowd to gather before
        # kickoff, and a real walled entrance hall at the back of it rather
        # than a turnstile bolted straight onto the sidewalk.
        #
        # It gets that room along the wall rather than out from it, and this is
        # the correction of a real defect: `fx0` was `STAD_WEST_OUT - 30`, which
        # is x 782 -- eleven studs inside avenue 6's carriageway and two inside
        # the junction square at its foot. The plaza was paved over the road.
        # The west edge is now measured from the avenue's own sidewalk instead
        # of guessed at, and the depth that leaves (13 studs, the same 13 the
        # note on STAD_WEST_OUT is written against) is bought back in z: 130
        # studs of frontage along the bowl's west wall, which is what a stadium
        # concourse looks like anyway.
        fx0, fx1 = AVE[5] + AVE_W[5] + AVE_WALK, STAD_WEST_OUT
        fz0, fz1 = fmid - 65.0, fmid + 65.0
        box("Paving", (fx0, fx1, fz0, fz1, GROUND_BOTTOM, GROUND), PATH_STONE, PEBBLE)

        # ex0 used to be STAD_WEST_OUT - 16.0 = 796.0, which put the atrium's own
        # WallNorth/WallSouth 3.0 studs into Ave5PavE, avenue 6's east sidewalk
        # (793.8-799.0 -- see `walks_ns`) -- check_city caught it outright
        # ("Ave5PavE cuts 3.0 studs into StadiumForecourt.WallNorth1"). The
        # building's canopy and lamps overhang another 4-5 studs past x0 on top
        # of that (see `stadium_entrance`'s `Canopy`/`CanopyRib`/`street_lamp`
        # calls at x0-4.0/x0-5.0), so clearing the sidewalk for the whole
        # building, canopy included, needs x0 >= 799.0 + 5.0 + a stud of margin,
        # not just x0 >= 799.0. STAD_WEST_OUT - 7.0 = 805.0 is that -- the
        # closest this building can legally stand to avenue 6 without its own
        # canopy lip ending up back on the sidewalk it was just pulled off of.
        # A second, separate gateway arch was tried in front of this at the
        # plaza's own road-facing edge and reverted: the clear ground between
        # the sidewalk (799.0) and this canopy's own reach (805.0 - 4.0 = 801.0)
        # is one stud wide, nowhere near enough for a second landmark structure
        # with clearance on both sides -- this building, canopy and sign
        # already are the designated, road-facing entrance the forecourt has
        # room for.
        ex0, ex1 = STAD_WEST_OUT - 7.0, STAD_WEST_OUT
        ez0, ez1 = fmid - 15.0, fmid + 15.0
        stadium_entrance(ex0, ex1, ez0, ez1, "MainEntrance")

        # Two rows down the flanks, not one down the whole frontage. The plaza
        # is thirteen studs deep and the entrance's canopy reaches x 801 of it,
        # so a row at 802 running the full length of the plaza plants palms in
        # the doorway -- fronds reach eleven studs (see `palm()`).
        for _fz0, _fz1 in ((fz0 + 6.0, ez0 - 12.0), (ez1 + 12.0, fz1 - 6.0)):
            palm_row(fx0 + 3.0, fx0 + 3.0, _fz0, _fz1, GROUND, step=14.0,
                     along="z", label=f"PlazaPalms{_fz0:.0f}")
        # Offset 10 studs past the doorway edge (cz +/- STAD_GATE_HALF), not just past
        # the entrance building's own footprint: a palm's fronds reach ~11 studs from
        # its trunk (see `palm()`), so flanking it right at the doorway edge let the
        # crown hang into the opening and read as trees blocking the entrance.
        for pz in (ez0 - 10.0, ez1 + 10.0):
            palm(ex0 - 3.0, pz, GROUND, label=f"PlazaPalmFlank{pz:.0f}")
        # Both kept off the entrance's own z band for the same reason as the
        # palms, and the benches sit back against the bowl wall (fx1 - 4) where
        # there is nothing behind them -- fx0 + 10 is now x 809, which is inside
        # the entrance hall.
        for pz in (fz0 + 12.0, ez0 - 20.0, ez1 + 20.0, fz1 - 12.0):
            street_lamp(fx0 + 4.0, pz, 1, floor=GROUND)
            bench(fx1 - 4.0, pz, -1, floor=GROUND)

    soccer_field(STAD_PX0, STAD_PX1, STAD_PZ0, STAD_PZ1)
    place_point("soccer_field", STAD_WEST_OUT - 11.0, (STAD_PZ0 + STAD_PZ1) / 2, GROUND,
                "the stadium's main gate")


stadium()


# ---------------------------------------------------------------------------
# The 25 blocks
# ---------------------------------------------------------------------------

house_no = 1
apt_no = 1
fade_counter = 1
circus_counter = 1
office_counter = 1
for sband in range(5):
    for band in range(5):
        role = ROLES[sband][band]
        x0, x1, z0, z1 = block_bounds(band, sband)
        if role == "HOUSE":
            house_no = house_block(band, sband, x0, x1, z0, z1, house_no)
        elif role == "APT":
            apt_no = apartment_block(band, sband, x0, x1, z0, z1, apt_no)
        elif role == "MALL":
            mall(band, sband, x0, x1, z0, z1)
        elif role == "PARK":
            city_park(band, sband, x0, x1, z0, z1)
        elif role == "OFFICES":
            office_counter = office_block(band, sband, x0, x1, z0, z1,
                                          office_counter)
        elif role == "MIXED":
            fade_counter = mixed_block(band, sband, x0, x1, z0, z1,
                                       fade_counter)
        elif role == "SPORTS":
            sports_center(band, sband, x0, x1, z0, z1)
        elif role == "ARENA":
            arena_block(band, sband, x0, x1, z0, z1)
        elif role == "FADE":
            fade_office_band(band, sband, x0, x1, z0, z1, fade_counter)
            fade_counter += 2  # two offices per block
        elif role == "CIRCUS":
            circus_counter = circus_block(band, sband, x0, x1, z0, z1,
                                          circus_counter)


# ---------------------------------------------------------------------------
# Financial district (south strip, z=60..200)
# ---------------------------------------------------------------------------

# Stops short of cross street 0 at the north rather than on it: the street
# starts at z=200 and its south pavement runs 196..200, so a district that
# reached 200 put its lobby windows inside the kerb. Four studs is the whole of
# the difference and check 7 is what found it -- which is why both ends are
# measured off a road now instead of typed. The south end is the city's own
# south edge, and the northernmost south street was placed so that its north
# pavement finishes exactly there: these towers front onto a pavement now,
# where until the step-down band was built they fronted onto open ground.
FIN_Z0, FIN_Z1 = CITY_Z0, CS[0] - CS_WALK
FIN_HEIGHTS = [10, 8, 12, 7, 9]  # storeys per band, varied skyline
# One family, four shades. Not four colours: a district where every tower is a
# different hue reads as a toybox by day and has nothing left to say at night,
# because the eye has already been given all the colour it is going to get. The
# glass stays one blue-grey and only its value moves, which is what leaves the
# crown neon somewhere to land after dark.
FIN_GLASS = TOWER_GLASS
# Which silhouette each band gets. The waterfront is the one row of towers seen
# end-on from the marina and the south pier, so it is the row where a repeated
# profile shows worst -- six styles across the rotation, never the same one
# twice in a row along the front. `straight` and `slab` are in here on purpose:
# an all-sculpted skyline is as flat as an all-boxy one, and the plain shafts
# are what make the twisted ones read as deliberate rather than as the only
# thing the generator knows how to draw.
FIN_STYLES = ["spire", "straight", "twist", "slab", "crown", "setback"]
FIN_STYLE_STRIDE = 5  # must stay coprime with len(FIN_STYLES); see fin_towers
assert math.gcd(FIN_STYLE_STRIDE, len(FIN_STYLES)) == 1, (
    f"FIN_STYLE_STRIDE {FIN_STYLE_STRIDE} shares a factor with {len(FIN_STYLES)} styles, "
    f"so the four bands will not all get different silhouettes. Pick a stride "
    f"coprime with the number of styles.")

# Four towers to a block, as a 2x2 with a cross alley.
#
# It was two, side by side, and each one got the block's whole 136-stud depth
# against 49 studs of width -- a slab, not a tower, and eight slabs in a row is
# a wall with the sky showing through it. Four at 49 x 66 is a proportion a
# tower can actually be built at, and it doubles the density of the district
# without taking a stud more ground.
FIN_GAP = 6.0
# Where the alley falls, as a fraction of the block. **Never 0.5.** A block cut
# down the middle four times running is a grid, and the thing that makes a real
# downtown read as one is that no two blocks are cut the same way -- so the
# alley wanders and the four towers in a block are four different sizes.
FIN_SPLIT_X = [0.54, 0.44, 0.58, 0.47, 0.51]
FIN_SPLIT_Z = [0.48, 0.56, 0.44, 0.53, 0.58]
# Which corner of a block the alley opens, and which street that corner's tower
# faces. The north pair front the cross street above them, the south pair the
# street below -- see `shaped_tower`'s `front` for why that is not cosmetic.
FIN_QUADS = (("sw", 0, 0, "south"), ("se", 1, 0, "south"),
             ("nw", 0, 1, "north"), ("ne", 1, 1, "north"))
# Storeys off the band's headline height, per corner. Rotated by the band so
# the tall corner walks along the waterfront rather than lining up into a
# second, accidental grid.
#
# **All of them are zero or negative, and that is the rule rather than the
# taste.** FIN_HEIGHTS is the ceiling the Circle's clearance assertion is sized
# against, and a positive entry here raises the district's tallest tower without
# touching the constant that is supposed to state it -- the first draft used
# (0, 3, -2, 5) and pushed the waterfront 46 studs over the middle of the city,
# which the assertion caught and the only available fix for was a 31-storey
# Circle. Vary downward: the district gets four different rooflines a block and
# the number the rest of the file reasons about does not move.
FIN_QUAD_LIFT = [0, -3, -6, -2]

# One quadrant a band is stone rather than glass -- see `masonry_tower` for why
# downtown needs any. Which corner walks along the waterfront rather than lining
# up: at four quadrants a stride of 3 visits every corner before repeating,
# where a stride of 2 would put the stone building on the same diagonal in every
# band and rebuild the stripe this is meant to break.
FIN_MASONRY_STRIDE = 3
FIN_MASONRY_OFFSET = 1
assert math.gcd(FIN_MASONRY_STRIDE, len(FIN_QUADS)) == 1, (
    f"FIN_MASONRY_STRIDE {FIN_MASONRY_STRIDE} shares a factor with "
    f"{len(FIN_QUADS)} quadrants, so the stone building sits on the same corner "
    f"in every band. Pick a stride coprime with the number of quadrants.")


def fin_masonry_quad(band):
    """Which quadrant of `band` is the old building."""
    return (band * FIN_MASONRY_STRIDE + FIN_MASONRY_OFFSET) % len(FIN_QUADS)


def fin_towers():
    """(name, band, ex, ez, front, floors, style, kind) for every building on
    the waterfront, in build order.

    One list, read by `financial_district` below *and* by the Circle's height
    assertion above it. The two used to derive these heights independently --
    the builder from FIN_HEIGHTS and the rule from `max(FIN_HEIGHTS)` -- which
    is the one-measurement-two-places problem this file asserts against
    everywhere else, and it is worse here than usual: the failure is silent and
    the symptom is a Circle that is no longer the tallest thing in its own city.
    """
    # From band 0, not band 1. The westernmost block used to hold the grand
    # bank, which is why the loop started one band in and why FIN_HEIGHTS[0]
    # was a number nothing read. The bank has gone up to the government quarter
    # and the block is towers like every other -- an all-modern downtown was the
    # point of moving it.
    for band in range(0, 5):
        base = FIN_HEIGHTS[band]
        for q, (tag, ex, ez, face) in enumerate(FIN_QUADS):
            floors = max(4, base + FIN_QUAD_LIFT[(q + band) % len(FIN_QUAD_LIFT)])
            # The stride must be coprime with len(FIN_STYLES) or bands repeat
            # each other wholesale: at six styles a stride of 3 gives every odd
            # band the same four silhouettes as every other odd band, which is
            # exactly the sameness the six styles were added to break.
            style = FIN_STYLES[(band * FIN_STYLE_STRIDE + q) % len(FIN_STYLES)]
            kind = "stone" if q == fin_masonry_quad(band) else "glass"
            yield (f"{band}{tag}", band, ex, ez, face, floors, style, kind)


def fin_skyline(floors, style, kind):
    """The highest point of one waterfront building, whichever kind it is.

    The Circle's clearance rule needs the tallest thing in the district and the
    district is no longer one kind of building. Asking `shaped_tower_skyline`
    about a stone one would quietly overstate it by twenty studs -- which is the
    safe direction, and is exactly why it would never have been noticed."""
    if kind == "stone":
        return masonry_skyline(floors)
    return shaped_tower_skyline(floors, style)

# The Circle is the middle of the city and every one of its twelve towers has to be
# the tallest thing in it. Asserted here, rather than in the CIRCUS block, for the
# reason the WORKS_AVE/CIRCLE_AVE pair is asserted where both exist: FIN_HEIGHTS is
# not defined until this line, and a rule that cannot see both sides is not a rule.
#
# CIRCUS_CLEARANCE is the 18 studs the Circle's own comment measured -- the smallest
# gap that still reads as "that one is taller" from the south end of the connector.
#
# There used to be a second assertion here holding the middle 18 studs over its own
# shoulders, and it is worth saying why it is gone rather than tightened. It passed
# on (14, 16, 14) -- a two-storey step that flattened the group into a slab. It was
# measuring the wrong quantity: 18 studs is the threshold for "is that one taller",
# which is a question about *ranking*, and nobody was ever going to misrank the middle
# tower. The question that actually decides whether the Circle looks like anything is
# how far apart the three are, and a floor of 18 answers it with a number six times too
# small. A gate that is green while the thing it guards gets worse is not a weak gate,
# it is the wrong gate, so it is replaced rather than raised.
CIRCUS_CLEARANCE = 18.0
def circus_skyline(storeys):
    """The top of a Circle tower's parapet -- what an eye on the ground sees."""
    top = FLOOR_1 + CIRCUS_LOBBY_H + (storeys - 1) * (CIRCUS_STOREY + CIRCUS_SLAB)
    return top + CIRCUS_SLAB + CIRCUS_PARAPET_H


CIRCUS_SKYLINE = [circus_skyline(n) for n in CIRCUS_STOREYS]
_rival = max(fin_skyline(floors, style, kind)
             for *_head, floors, style, kind in fin_towers())
_floor = _rival + CIRCUS_CLEARANCE

assert min(CIRCUS_SKYLINE) >= _floor, (
    f"the shortest Circle tower tops out at {min(CIRCUS_SKYLINE):.1f} against the "
    f"financial district's {_rival:.1f}. Every tower on the Circle is supposed to be "
    f"the tallest thing in the city, and clearing it by less than "
    f"{CIRCUS_CLEARANCE:.0f} studs reads as a tie from the ground rather than as a "
    f"win. Raise CIRCUS_LIFT.")

# The lift is meant to be the smallest that clears the mast, so that the Circle is the
# tallest thing in the city by design and not by however much headroom somebody felt
# like adding. Asserting minimality is the negative test that would otherwise have to be
# run by hand and re-run every time FIN_HEIGHTS moves.
assert CIRCUS_LIFT == 0 or circus_skyline(min(CIRCUS_ARC) + CIRCUS_LIFT - 1) < _floor, (
    f"CIRCUS_LIFT is {CIRCUS_LIFT} but {CIRCUS_LIFT - 1} already clears "
    f"{_floor:.1f}. The lift is supposed to be the smallest that wins, so drop it by "
    f"one -- the Circle should be the tallest thing in the city on purpose, not by "
    f"accident.")

# The step, per quadrant, not the ranking. This is the requirement the old clearance
# assertion could not see: an arc whose peak barely clears its own shoulders is a
# terrace, and a terrace is what (14, 16, 14) built.
#
# Measured within a quadrant rather than across the Circle, because across the Circle it
# is not a step at all -- the tallest tower and the shortest one stand at opposite
# corners with the monument between them, and comparing those two would have passed
# happily on four identical arcs, which is the *other* defect.
#
# Compared in storeys, not in studs. The stud version of this failed on the very
# configuration it was written to bless: two differences that are both 96 accumulate the
# `(n - 1) * (CIRCUS_STOREY + CIRCUS_SLAB)` term over different n and land one bit apart,
# so `>=` was comparing 95.99999999999997 against 96.0. Storeys are integers and the
# skyline is linear in them with a positive slope, so this is the same requirement with
# none of the float in it -- studs appear in the message only.
CIRCUS_MIN_STEP = 5
for _q in range(len(CIRCUS_QUAD_LIFT)):
    _arc = circus_arc(_q)
    _peak, _shoulders = max(_arc), [n for n in _arc if n != max(_arc)]
    assert _peak - max(_shoulders) >= CIRCUS_MIN_STEP, (
        f"quadrant {_q} of the Circle is {_arc} storeys -- a step of "
        f"{_peak - max(_shoulders)} between its peak and its tallest shoulder, against "
        f"the {CIRCUS_MIN_STEP} an arc needs to read as an arc. Below that the three "
        f"towers line up into a terrace, which is what (14, 16, 14) did. Buy height "
        f"with CIRCUS_LIFT or CIRCUS_QUAD_LIFT, which move a whole arc at once.")

# Variety, which is the thing that was wrong twice and written down neither time.
#
# Twelve towers built from one three-tower constant gave four rooflines of one height
# and eight of another -- correct by every rule above and monotonous on sight, because
# every rule above is about one arc and the city shows all four at once. This is the
# only assertion here that looks at the Circle as a whole.
#
# The floor is 8 rather than 12: shoulders are allowed to repeat between quadrants,
# since two towers on opposite corners of the Circle are never in the same glance. What
# it forbids is the stamp -- one arc copied, which scores 3.
CIRCUS_MIN_ROOFLINES = 8
_rooflines = sorted(set(CIRCUS_STOREYS))
assert len(_rooflines) >= CIRCUS_MIN_ROOFLINES, (
    f"the Circle's twelve towers stand on only {len(_rooflines)} distinct rooflines "
    f"({_rooflines} storeys). Below {CIRCUS_MIN_ROOFLINES} the centre of the city reads "
    f"as one building stamped four times rather than as a cluster. Vary "
    f"CIRCUS_QUAD_LIFT -- it is what makes the four corners differ.")


with group("FinancialDistrict"):
    # Ground for the whole band, laid before anything stands on it. The towers
    # used to each carry a plinth, so the block interior only had a floor where a
    # building happened to be -- and the moment those went, `wp_fin_plaza` and
    # `wp_fin_plaza_n` were left standing over a hole in the cross alley. Ground
    # belongs to the block, not to the building.
    for _band in range(0, 5):
        box(f"FinPaving{_band}",
            (AVE[_band] + AVE_W[_band] + AVE_WALK, AVE[_band + 1] - AVE_WALK,
             FIN_Z0, FIN_Z1, GROUND_BOTTOM, PAVING), PAVING_GREY, CONCRETE)

    # Four shaped towers in each of the five bands, as a 2x2 around a
    # cross alley. Read off `fin_towers()` rather than recomputing the heights
    # here -- see that function for why the two must not derive them separately.
    for _i, (_no, _band, _ex, _ez, _face, _floors, _style, _kind) in \
            enumerate(fin_towers()):
        _bx0 = AVE[_band] + AVE_W[_band] + AVE_WALK
        _bx1 = AVE[_band + 1] - AVE_WALK
        _sx = _bx0 + (_bx1 - _bx0) * FIN_SPLIT_X[_band]
        _sz = FIN_Z0 + (FIN_Z1 - FIN_Z0) * FIN_SPLIT_Z[_band]
        _xs = ((_bx0, _sx - FIN_GAP / 2), (_sx + FIN_GAP / 2, _bx1))
        _zs = ((FIN_Z0, _sz - FIN_GAP / 2), (_sz + FIN_GAP / 2, FIN_Z1))
        if _kind == "stone":
            # No slab: FinPaving already floors the whole band. The stone
            # building takes the same storey count the glass tower it replaced
            # would have had and comes out about twenty studs shorter on its own
            # vocabulary -- which is the step, and it is not typed anywhere.
            masonry_tower(_no, _xs[_ex][0], _xs[_ex][1], _zs[_ez][0], _zs[_ez][1],
                          _floors, tint=_i, front=_face)
        else:
            shaped_tower(_no, _xs[_ex][0], _xs[_ex][1], _zs[_ez][0], _zs[_ez][1],
                         _floors, FIN_GLASS[(_band + _i) % len(FIN_GLASS)],
                         style=_style, tint=_i, front=_face)
    # Street furniture goes on the avenue pavements, not in the middle of the
    # band. There is no plaza here and there never was room for one: the bank
    # fills its band wall to wall and each of the other four is four towers
    # around a six-stud alley, so the "plaza" this used to draw was an inverted
    # box (x0 215 > x1 213) and its trees and benches stood inside the bank and
    # inside the towers. The pavements are the only open ground in the
    # district, and street trees are what actually belongs on them.
    for _k, _a in enumerate(AVE[:5]):
        _px = _a - AVE_WALK / 2  # centre of that avenue's west pavement
        for _z in (88.0, 132.0, 176.0):
            tree(_px, _z, PAVING, height=11.0, spread=7.0)
        bench(_a + AVE_W[_k] + AVE_WALK / 2, 110.0, -1)


# ---------------------------------------------------------------------------
# The step-down: the fade district's south half
# ---------------------------------------------------------------------------

# The ramp off the south face of the financial district, and the answer to the
# one edge of downtown that fell off a cliff.
#
# The north side of the towers has stepped down since the block plan was
# written: 195 to 115 to 67 to 34 to 17, tower to fade office to office tower to
# walk-up to house, and the note on ROLES is most of a page about why. The south
# side had nothing. The towers stopped at z=60 and the next thing standing was a
# twenty-six-stud shed in the works, so from the water the skyline was a wall
# with a yard at the bottom of it -- and the lobby doors, which front south,
# opened onto bare ground with no pavement in front of them at all.
#
# This is the same ramp mirrored: 195 -> 115 -> 67 -> 36. Both rows are
# `fade_office`, the same building the north side steps down with, because they
# are doing the same job and a second primitive that drew the same box would be
# a second primitive to keep true. They share the north side's counter too, so
# the district reads as one thing with the financial district in the middle of
# it rather than two districts with the same name.
#
# **Two rows, not one.** One row of mid-rises would have moved the cliff rather
# than removed it -- 195 to 115 to 36. The second row at 67 is what makes it a
# ramp, and the gap between the two rows is a mews: eighteen studs of paving
# with the north row's front doors on one side of it, which is somewhere to be
# rather than a light well.
#
# The five columns are the financial district's own five bands, between the same
# six avenues, so every office here stands directly under the tower it steps
# down from. That is what all six avenues carrying into this band buys.

# Storeys in each row, north to south. 7 gives 115.5 studs and 4 gives 67.5,
# which are the *same two numbers* the north side steps through -- see the
# skyline in the ROLES note. Safe range: north 6..8, south 4..5, and north must
# stay at least two above south or the two rows read as one terrace.
STEP_STOREYS = (7, 4)
# How deep the north row is and how wide the mews behind it is; the south row
# takes what is left of the band. Safe range: front 54..70, mews 14..24.
STEP_FRONT_DEPTH = 62.0
STEP_MEWS_W = 18.0
# Widths of the two offices in a row, as a share of the band, and the gap
# between them. Uneven on purpose: a row of matched pairs across five bands is a
# fence, and the pair reads as buildings the moment they stop being twins.
STEP_SLOTS = (5, 4)
STEP_GAP = 6.0


def step_storeys(band, row):
    """Storeys for the step-down office in `band`, `row` (0 north, 1 south).

    Keyed to the tower standing above it, so the ramp inherits the financial
    district's own rhythm instead of being a flat terrace under a jagged
    skyline. A tall band steps down through a tall office."""
    return STEP_STOREYS[row] + (1 if FIN_HEIGHTS[band] >= 9 else 0)


def step_band(band, counter):
    """One column of the step-down: two offices at the front, two behind, and
    the mews between them. Returns the next free office number."""
    bx0 = AVE[band] + AVE_W[band] + AVE_WALK
    bx1 = AVE[band + 1] - AVE_WALK
    z0, z1 = STEP_ROW_Z
    front_z0 = z1 - STEP_FRONT_DEPTH
    mews_z0 = front_z0 - STEP_MEWS_W
    for row, (rz0, rz1) in enumerate(((front_z0, z1), (z0, mews_z0))):
        # The wider slot goes on the outside of each column, so the gap between
        # the two offices lines up down the middle of the band and the row does
        # not drift.
        weights = STEP_SLOTS if band % 2 == 0 else STEP_SLOTS[::-1]
        for sx0, sx1 in solve_row(bx0, bx1, weights, STEP_GAP):
            fade_office(counter, sx0, sx1, rz0, rz1, step_storeys(band, row),
                        name="StepOffice")
            counter += 1
    with group(f"StepMews{band}"):
        box("Paving", (bx0, bx1, mews_z0, front_z0, GROUND_BOTTOM, GROUND),
            PATH_STONE, PEBBLE)
    # Trees down the middle of the mews and a bench at each end of it, facing
    # the front row's doors -- the doors are the only reason a player is in here.
    for i in range(4):
        tree(bx0 + 14.0 + i * (bx1 - bx0 - 28.0) / 3.0,
             (mews_z0 + front_z0) / 2, GROUND, height=12.0, spread=8.0,
             label=f"StepMewsTree{band}_{i}")
    bench(bx0 + 8.0, mews_z0 + 4.0, 1, label=f"StepMewsBench{band}")
    bench(bx1 - 8.0, mews_z0 + 4.0, 1, label=f"StepMewsBench{band}")
    street_lamp(bx0 + 4.0, front_z0 - 2.0, 1, floor=GROUND,
                label=f"StepMewsLamp{band}")
    street_lamp(bx1 - 4.0, front_z0 - 2.0, 1, floor=GROUND,
                label=f"StepMewsLamp{band}")
    return counter


for _band in range(5):
    fade_counter = step_band(_band, fade_counter)


# ---------------------------------------------------------------------------
# The works: primitives
# ---------------------------------------------------------------------------

# A shed is not a shop with a bigger roof, which is why `storefront` is not used
# for any of these. The differences are all structural: it is twice as tall, its
# wall is brick to shoulder height and profiled steel above, its openings are
# roll-up doors wide enough to drive through rather than a doorway, and it has a
# clerestory ribbon under the eaves instead of a shopfront at eye level. Reusing
# `storefront` would have meant six more optional arguments on a function that
# already has ten, and every one of them ignored by every shop in the city.

# How high the brickwork goes before the cladding starts. Roughly a truck's
# height, which is not a coincidence -- the brick is there because that is the
# band a forklift hits. Safe range: 6 .. 11; above 11 the cladding band is too
# short to read as cladding and the shed looks like a brick box with a hat.
SHED_PLINTH = 8.0
# One roll-up bay. Wide and tall enough that a lorry through it is believable,
# and both are what the bay-spacing arithmetic below is measured against.
# Safe range: 12 .. 22 wide -- under 12 it reads as a domestic garage.
SHED_BAY_W = 16.0
SHED_BAY_H = 14.0
# The frontage a shed keeps clear at the pedestrian-door end before the first
# bay, and at the far end after the last. Not symmetric on purpose: the door end
# has to hold a door, a pier and a sign, and the far end only has to not look
# cut off. Safe range: inset 24 .. 40, margin 4 .. 12.
SHED_DOOR_INSET = 30.0
SHED_END_MARGIN = 6.0
# The glazed ribbon under the eaves, as a depth below them. This is the only
# daylight a shed gets and it is why the inside is not a black box at midday.
SHED_CLERE_DROP = 8.0
SHED_FASCIA = 2.0
# The concrete strip in front of the bays. Every shed is set back from its block
# edge by exactly this, and the apron fills the gap -- so the concrete stops on
# the same line the pavement starts on. It used to be drawn *outward* from a shed
# standing on the block edge, which laid ten studs of apron over the kerb and the
# near lane of the works street at exactly road height: nothing in check_city
# looks for two coplanar tops inside one asset, so the only symptom would have
# been the road flickering along the whole north row.
SHED_APRON = 10.0


def works_shed(name, x0, x1, z0, z1, front, bays, eaves, clad,
               sign_text=None, brick=WORKS_BRICK, roof=WORKS_CLAD_2):
    """A tall industrial shell with roll-up bays in its front wall.

    `front` is "north" or "south" -- there is no east/west branch, because every
    shed in the works stands in a block with a road along its long side and
    turning one ninety degrees would put its bays where its neighbour's yard is.
    A caller who needs one gets an error rather than a shed facing the wrong way.

    Returns the x of the pedestrian door, which is where the caller puts the
    place point: the game stands the player at the door, and a place point in
    the middle of a two-hundred-stud shed is a player inside a wall.
    """
    if front not in ("north", "south"):
        raise ValueError(f"{name}: a works shed fronts north or south, not {front}")
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    plinth = FLOOR_1 + SHED_PLINTH
    clere0 = eaves - SHED_CLERE_DROP
    clere1 = eaves - SHED_FASCIA
    if clere0 <= plinth + 2.0:
        raise ValueError(f"{name}: eaves at {eaves:.1f} leave no cladding band above "
                         f"the plinth -- raise the eaves or lower SHED_PLINTH")

    # Bay centres. The usable frontage is what is left after the door end and
    # the far margin, divided evenly, with each bay in the middle of its share --
    # so two bays and five bays are both centred runs rather than a row starting
    # at one end and stopping wherever it runs out.
    usable = (ix1 - ix0) - SHED_DOOR_INSET - SHED_END_MARGIN
    if usable < bays * SHED_BAY_W:
        raise ValueError(f"{name}: {bays} bays need {bays * SHED_BAY_W:.0f} studs of "
                         f"frontage and there are {usable:.0f}")
    pitch = usable / bays
    centres = [ix0 + SHED_DOOR_INSET + (b + 0.5) * pitch for b in range(bays)]
    door_x = ix0 + SHED_DOOR_INSET / 2
    openings = sorted([(c - SHED_BAY_W / 2, c + SHED_BAY_W / 2) for c in centres]
                      + [(door_x - DOORWAY / 2, door_x + DOORWAY / 2)])

    if front == "north":
        f0, f1 = iz1, z1
        b0, b1 = z0, iz0
        apron_z0, apron_z1 = z1, z1 + SHED_APRON
    else:
        f0, f1 = z0, iz0
        b0, b1 = iz1, z1
        apron_z0, apron_z1 = z0 - SHED_APRON, z0

    with group(name):
        box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1), CONCRETE_GREY, CONCRETE)
        box("Roof", (x0, x1, z0, z1, eaves, eaves + SLAB), roof, METAL)
        # A raised monitor down the ridge. One box, and it is the difference
        # between a shed and a shipping container the size of a shed.
        box("Monitor", (x0 + 20.0, x1 - 20.0, (z0 + z1) / 2 - 8.0, (z0 + z1) / 2 + 8.0,
                        eaves + SLAB, eaves + SLAB + 5.0), roof, METAL)
        for _mz in ((z0 + z1) / 2 - 8.2, (z0 + z1) / 2 + 7.4):
            box(f"MonitorGlass{_mz:.0f}", (x0 + 22.0, x1 - 22.0, _mz, _mz + 0.8,
                                           eaves + SLAB + 1.0, eaves + SLAB + 4.2),
                GLAZING, GLASS, transparency=0.5, collide=False)

        for band, (yl, yh, colour, mat, cut) in enumerate((
                (FLOOR_1, plinth, brick, BRICK, True),
                (plinth, clere0, clad, METAL, True),
                (clere1, eaves, clad, METAL, False))):
            # Front, with the openings cut out. `head` is measured from the
            # band's own floor, so the lintel over a bay lands at the bay's real
            # height whichever band happens to contain it -- and in the plinth
            # band, where the head is above the band, `wall` draws none at all.
            #
            # `cut` is False for the fascia above the clerestory, and it has to
            # be: `head` there works out negative, so `wall` would put a lintel
            # from the top of the doors right up through the fascia and leave the
            # bays looking like slots. A band entirely above the openings is a
            # solid wall, and saying so is cheaper than making the arithmetic
            # cope.
            wall(f"Front{band}", (x0, x1, f0, f1, yl, yh), colour, mat,
                 doors=tuple(openings) if cut else (),
                 head=FLOOR_1 + SHED_BAY_H - yl, along="x")
            wall(f"Back{band}", (x0, x1, b0, b1, yl, yh), colour, mat, along="x")
            wall(f"West{band}", (x0, ix0, z0, z1, yl, yh), colour, mat, along="z")
            wall(f"East{band}", (ix1, x1, z0, z1, yl, yh), colour, mat, along="z")

        # The clerestory ribbon, all the way round.
        glazing("ClereFront", (x0, x1, f0 + 0.3, f1 - 0.3, clere0, clere1),
                along="x", panes=max(int((x1 - x0) / 20.0), 2))
        glazing("ClereBack", (x0, x1, b0 + 0.3, b1 - 0.3, clere0, clere1),
                along="x", panes=max(int((x1 - x0) / 20.0), 2))
        for _side, (_wx0, _wx1) in (("West", (x0, ix0)), ("East", (ix1, x1))):
            glazing(f"Clere{_side}", (_wx0 + 0.3, _wx1 - 0.3, z0, z1, clere0, clere1),
                    along="z", panes=max(int((z1 - z0) / 20.0), 2))

        # The shutters themselves, in the plane of the front wall.
        for b, c in enumerate(centres):
            box(f"Rollup{b}", (c - SHED_BAY_W / 2, c + SHED_BAY_W / 2,
                               f0 + 0.2, f1 - 0.2, FLOOR_1, FLOOR_1 + SHED_BAY_H),
                clad, CORRODED_METAL)
            for i in range(6):
                sy = FLOOR_1 + 1.4 + i * (SHED_BAY_H - 2.0) / 6.0
                box(f"Slat{b}_{i}", (c - SHED_BAY_W / 2, c + SHED_BAY_W / 2,
                                     f0 - 0.1, f0 + 0.1, sy, sy + 0.35),
                    (58, 58, 60), SMOOTH, collide=False)
            # Bay number, painted on the wall above the shutter. The one piece of
            # signage in this district a player reads while standing at it.
            box(f"BayPlate{b}", (c - 3.0, c + 3.0, f0 - 0.5, f0 - 0.1,
                                 FLOOR_1 + SHED_BAY_H + 1.0, FLOOR_1 + SHED_BAY_H + 5.0),
                clad, SMOOTH, collide=False,
                children=sign(str(b + 1), "front" if front == "south" else "back",
                              color=SAFETY_YELLOW, size=96))
        # The pedestrian door's own head, filling the strip between a nine-stud
        # doorway and the fourteen-stud opening the bay arithmetic cut for it.
        box("DoorHead", (door_x - DOORWAY / 2, door_x + DOORWAY / 2, f0, f1,
                         FLOOR_1 + DOOR_HEIGHT, FLOOR_1 + SHED_BAY_H), clad, METAL)

        if sign_text is not None:
            box("Nameplate", (ix0 + 2.0, ix0 + SHED_DOOR_INSET + 34.0,
                              f0 - 1.2, f0 - 0.4, clere1 - 7.0, clere1 - 0.5),
                brick, SMOOTH, collide=False,
                children=sign(sign_text, "front" if front == "south" else "back",
                              color=(248, 244, 232), size=64))

        # Hardstanding in front of the bays, with a hazard stripe at its edge:
        # concrete under the doors, because grass under a roll-up door is the
        # single thing that stops a shed reading as working.
        box("Apron", (x0 - 2.0, x1 + 2.0, apron_z0, apron_z1,
                      GROUND_BOTTOM, GROUND), CONCRETE_GREY, CONCRETE)
        for b, c in enumerate(centres):
            box(f"Hatch{b}", (c - SHED_BAY_W / 2, c + SHED_BAY_W / 2,
                              apron_z0 + 0.6, apron_z1 - 0.6, GROUND, GROUND + 0.06),
                SAFETY_YELLOW, SMOOTH, collide=False)
    return door_x


def round_tower(name, x, z, y0, height, profile, color, material,
                segs=12, wall_t=2.0, cap=None):
    """A round tower, as a stack of shell annuli.

    `profile` is (height fraction, radius) read from the bottom up, and each
    consecutive pair becomes one band at the mean of its two radii -- so a
    cooling tower's waist is a list of four numbers rather than a formula
    somebody has to reverse-engineer. Twelve facets is enough for a chimney read
    at a hundred studs; the cooling towers use sixteen because they are the two
    largest curved objects in the game.

    Hollow, not solid: these are the only things in the works tall enough to be
    seen against the sky from downtown, and a solid one is a hundred parts of
    geometry nobody can ever be inside of.
    """
    with group(name):
        for i in range(len(profile) - 1):
            (t0, r0), (t1, r1) = profile[i], profile[i + 1]
            rm = (r0 + r1) / 2
            ring(f"Band{i}", rm - wall_t, rm, y0 + height * t0, y0 + height * t1,
                 color, material, cx=x, cz=z, segs=segs, seam=0.0)
        if cap is not None:
            top_r = profile[-1][1]
            ring("Cap", top_r - wall_t - 0.8, top_r + 0.8,
                 y0 + height, y0 + height + 1.4, cap, METAL,
                 cx=x, cz=z, segs=segs, seam=0.0)


def chimney(name, x, z, height=88.0):
    """A brick stack with two hazard bands near the top. The tallest thing south
    of the financial district, and deliberately: it is what tells a player
    standing on the Circle that there is a district down there at all."""
    round_tower(name, x, z, GROUND, height,
                [(0.0, 7.5), (0.4, 6.2), (0.8, 5.2), (1.0, 5.0)],
                WORKS_BRICK, BRICK, segs=12, wall_t=1.8, cap=RUST)
    with group(f"{name}Bands"):
        for i, t in enumerate((0.82, 0.90)):
            ring(f"Hazard{i}", 4.9, 5.6, GROUND + height * t,
                 GROUND + height * t + 3.0, SAFETY_YELLOW, SMOOTH,
                 cx=x, cz=z, segs=12, seam=0.0)


def cooling_tower(name, x, z, height=64.0):
    """The hyperboloid, four numbers wide. Nothing else in this game has a waist
    and that is exactly why it is worth the sixty-four parts: it is the one
    silhouette that says "power station" with no sign on it."""
    round_tower(name, x, z, GROUND, height,
                [(0.0, 27.0), (0.18, 22.0), (0.45, 18.5), (0.72, 19.5), (1.0, 22.5)],
                CONCRETE_GREY, CONCRETE, segs=16, wall_t=2.6)
    # The plume. Non-colliding and barely there -- a cooling tower with nothing
    # coming out of it is a concrete vase.
    with group(f"{name}Plume"):
        for i, (dy, r, tr) in enumerate(((4.0, 20.0, 0.72), (14.0, 26.0, 0.84),
                                         (26.0, 32.0, 0.92))):
            box(f"Plume{i}", (x - r, x + r, z - r, z + r,
                              GROUND + height + dy, GROUND + height + dy + 10.0),
                (236, 238, 240), SMOOTH, transparency=tr, collide=False)


def silo(name, x, z, height=34.0, radius=7.0):
    """A storage silo. Three of them in a row is the cheapest thing in this file
    that reads unmistakably as industry."""
    round_tower(name, x, z, GROUND, height,
                [(0.0, radius), (0.86, radius), (1.0, radius * 0.86)],
                STEEL, CORRODED_METAL, segs=12, wall_t=1.6, cap=CONCRETE_GREY)


def hardstanding(name, x0, x1, z0, z1):
    """A yard surface. GROUND exactly, like a road: the city's grass tops a
    fiftieth lower, so the yard always wins the pixel where the two meet."""
    box(name, (x0, x1, z0, z1, GROUND_BOTTOM, GROUND), WORKS_TARMAC, ASPHALT)


# How far apart the fence posts stand, and how tall the fence is. A palisade at
# ten studs is above head height and below the eaves of everything it stands in
# front of, which is the band where it reads as security rather than as a wall.
# Safe range: post pitch 10 .. 18, height 8 .. 12.
FENCE_PITCH = 14.0
FENCE_H = 10.0


def works_fence(name, x0, x1, z0, z1, gates=()):
    """A palisade round a yard, with the gate openings left out.

    `gates` is a list of (side, centre, width). The gaps are the whole point: a
    yard fenced all the way round is a yard the player watches from the pavement,
    and everything in this district is meant to be walked into.
    """
    sides = {
        "south": ((x0, x1), lambda a, b: (a, b, z0 - 0.5, z0 + 0.5), "x"),
        "north": ((x0, x1), lambda a, b: (a, b, z1 - 0.5, z1 + 0.5), "x"),
        "west": ((z0, z1), lambda a, b: (x0 - 0.5, x0 + 0.5, a, b), "z"),
        "east": ((z0, z1), lambda a, b: (x1 - 0.5, x1 + 0.5, a, b), "z"),
    }
    with group(name):
        for side, (bounds, place, axis) in sides.items():
            gaps = [(c - w / 2, c + w / 2) for s, c, w in gates if s == side]
            for a, b in carve(bounds, gaps):
                if b - a < 1.0:
                    continue
                fx0, fx1, fz0, fz1 = place(a, b)
                box(f"{side}Mesh{a:.0f}", (fx0, fx1, fz0, fz1, GROUND, GROUND + FENCE_H),
                    STEEL, METAL, transparency=0.55, collide=True)
                # Posts and a top rail, opaque, so the fence has a silhouette at
                # distance where a translucent panel has none.
                box(f"{side}Rail{a:.0f}", (fx0 - 0.2, fx1 + 0.2, fz0 - 0.2, fz1 + 0.2,
                                           GROUND + FENCE_H - 0.5, GROUND + FENCE_H),
                    STEEL, METAL)
                n = max(int((b - a) / FENCE_PITCH), 1)
                for i in range(n + 1):
                    t = a + (b - a) * i / n
                    px0, px1, pz0, pz1 = place(t - 0.6, t + 0.6)
                    box(f"{side}Post{t:.0f}", (px0 - 0.3, px1 + 0.3, pz0 - 0.3, pz1 + 0.3,
                                               GROUND, GROUND + FENCE_H + 1.0), STEEL, METAL)


# A shipping container, in studs. Not the real 8x40x8.5 -- a Roblox character is
# five studs tall, so a real container would be shorter than the player and the
# stacks would read as crates. Scaled to the character instead.
BOX_W, BOX_L, BOX_H = 11.0, 34.0, 11.0
# Clearance a container keeps from the edge of the hardstanding it stands on.
# Safe range: 3 .. 8. It is what stops the end box of a row overhanging the
# concrete onto whatever is behind it -- which, in the depot's case, was the
# works street's south pavement, thirteen studs of container in the road.
BOX_MARGIN = 4.0


def container(name, x, z, along, level, color):
    """One container, `along` = "x" or "z", `level` = how many are under it."""
    w, l = (BOX_L, BOX_W) if along == "x" else (BOX_W, BOX_L)
    y0 = GROUND + level * BOX_H
    with group(name):
        box("Body", (x - w / 2, x + w / 2, z - l / 2, z + l / 2, y0, y0 + BOX_H),
            color, CORRODED_METAL)
        # Corrugation: three shallow ribs down the long faces. Without them a
        # stack of these is a stack of solid colour and the eye reads one object.
        for i in range(3):
            t = (i + 1) / 4.0
            if along == "x":
                rx = x - w / 2 + w * t
                box(f"Rib{i}", (rx - 0.4, rx + 0.4, z - l / 2 - 0.2, z + l / 2 + 0.2,
                                y0 + 0.6, y0 + BOX_H - 0.6), color, SMOOTH, collide=False)
            else:
                rz = z - l / 2 + l * t
                box(f"Rib{i}", (x - w / 2 - 0.2, x + w / 2 + 0.2, rz - 0.4, rz + 0.4,
                                y0 + 0.6, y0 + BOX_H - 0.6), color, SMOOTH, collide=False)


def container_stack(name, x, z, along, levels, first):
    """A column of containers, colours stepping through CONTAINER_COLORS from
    `first` so no two neighbouring stacks start on the same colour."""
    for level in range(levels):
        container(f"{name}_{level}", x, z, along, level,
                  CONTAINER_COLORS[(first + level) % len(CONTAINER_COLORS)])


def gantry(name, x0, x1, z, height=42.0, trolley_at=0.45):
    """A travelling gantry crane spanning a yard. Two legs, a box girder across
    them, and a trolley with the hook down -- which is what makes it read as a
    machine that moves rather than as a gate."""
    with group(name):
        for side, gx in (("W", x0), ("E", x1)):
            for dz in (-9.0, 9.0):
                box(f"Leg{side}{dz:.0f}", (gx - 2.0, gx + 2.0, z + dz - 2.0, z + dz + 2.0,
                                           GROUND, GROUND + height), SAFETY_YELLOW, METAL)
            box(f"Brace{side}", (gx - 2.2, gx + 2.2, z - 9.0, z + 9.0,
                                 GROUND + height * 0.55, GROUND + height * 0.55 + 1.6),
                SAFETY_YELLOW, METAL)
            box(f"Bogie{side}", (gx - 3.0, gx + 3.0, z - 11.0, z + 11.0,
                                 GROUND, GROUND + 2.4), (58, 58, 60), METAL)
        box("Girder", (x0 - 3.0, x1 + 3.0, z - 4.0, z + 4.0,
                       GROUND + height, GROUND + height + 5.0), SAFETY_YELLOW, METAL)
        tx = x0 + (x1 - x0) * trolley_at
        box("Trolley", (tx - 5.0, tx + 5.0, z - 5.0, z + 5.0,
                        GROUND + height - 3.0, GROUND + height), (58, 58, 60), METAL)
        box("Rope", (tx - 0.3, tx + 0.3, z - 0.3, z + 0.3,
                     GROUND + BOX_H * 2 + 2.0, GROUND + height - 3.0), STEEL, METAL,
            collide=False)
        box("Hook", (tx - 2.0, tx + 2.0, z - 2.0, z + 2.0,
                     GROUND + BOX_H * 2, GROUND + BOX_H * 2 + 2.0), RUST, CORRODED_METAL)


def pipe_rack(name, x0, x1, z, height=16.0, pipes=3):
    """A run of pipework on trestles. Horizontal lines at height are the one
    thing a yard full of vertical towers is missing."""
    with group(name):
        for i in range(int((x1 - x0) / 26.0) + 1):
            tx = x0 + i * 26.0
            for dz in (-4.0, 4.0):
                box(f"Leg{i}{dz:.0f}", (tx - 0.8, tx + 0.8, z + dz - 0.8, z + dz + 0.8,
                                        GROUND, GROUND + height), STEEL, METAL)
        for p in range(pipes):
            pz = z - 4.0 + p * 8.0 / max(pipes - 1, 1)
            py = GROUND + height - 2.0 - p * 1.8
            box(f"Pipe{p}", (x0 - 2.0, x1 + 2.0, pz - 1.1, pz + 1.1, py, py + 2.2),
                (168, 164, 156) if p % 2 else RUST, CORRODED_METAL)


def scrap_pile(name, x, z, radius, height):
    """A heap. Three offset slabs of rusted plate, each smaller than the last --
    a pile is read by its outline and the outline is all this needs to be."""
    with group(name):
        for i, (f, off) in enumerate(((1.0, 0.0), (0.68, 0.18), (0.36, -0.14))):
            r = radius * f
            y1 = GROUND + height * (i + 1) / 3.0
            box(f"Heap{i}", (x - r + radius * off, x + r + radius * off,
                             z - r - radius * off, z + r - radius * off,
                             GROUND, y1), RUST if i % 2 else (108, 76, 62),
                CORRODED_METAL)


def log_pile(name, x0, x1, z, layers=3, per_layer=5):
    """Stacked timber: rows of logs, each layer shorter and nested on the one
    below. The mill's whole reason for having a yard."""
    with group(name):
        for layer in range(layers):
            n = per_layer - layer
            if n < 1:
                continue
            span = (x1 - x0) - layer * 3.4
            y0 = GROUND + layer * 3.2
            for i in range(n):
                lz = z - span / 2 + span * (i + 0.5) / n
                box(f"Log{layer}_{i}", (x0 + layer * 1.7, x1 - layer * 1.7,
                                        lz - 1.6, lz + 1.6, y0, y0 + 3.2),
                    LOG_BROWN, WOOD)


# ---------------------------------------------------------------------------
# The works: the four blocks
# ---------------------------------------------------------------------------

# Every place point here is a building the game does not yet have a job in. That
# is the order the owner asked for -- the buildings and what is in them first,
# the code that makes each one do something second -- and it is recorded in
# MAP_PLAN.md so it cannot quietly become a district of scenery.


def works_ironworks(x0, x1, z0, z1):
    """The west end of the north row: the district's anchor building, with its
    yard behind it. Fronts *south* onto works street 2, which is the street a
    player arrives on from the city."""
    shed_x0, shed_x1 = x0 + 20.0, x0 + 280.0
    shed_z0 = z0 + SHED_APRON
    shed_z1 = shed_z0 + 76.0
    door = works_shed("Ironworks", shed_x0, shed_x1, shed_z0, shed_z1, "south",
                      4, GROUND + 30.0, WORKS_CLAD, sign_text="VULCAN IRONWORKS")
    place_point("factory", door, shed_z0 - SHED_APRON / 2, GROUND,
                "the door of the Vulcan Ironworks")

    with group("IronworksYard"):
        hardstanding("Yard", shed_x0, shed_x1, shed_z1, z1 - 8.0)
    chimney("IronworksStackW", shed_x0 + 34.0, shed_z1 + 26.0)
    chimney("IronworksStackE", shed_x0 + 62.0, shed_z1 + 26.0, height=72.0)
    for i in range(3):
        silo(f"IronworksSilo{i}", shed_x0 + 118.0 + i * 17.0, shed_z1 + 24.0)
    pipe_rack("IronworksPipes", shed_x0 + 30.0, shed_x1 - 20.0, z1 - 24.0)
    for i in range(4):
        scrap_pile(f"IronworksBillets{i}", shed_x0 + 196.0 + (i % 2) * 34.0,
                   shed_z1 + 18.0 + (i // 2) * 30.0, 11.0, 7.0)
    # Fenced, with the gate on the avenue side so the yard has a way in that is
    # not through the shed.
    works_fence("IronworksFence", shed_x0 - 4.0, shed_x1 + 4.0, shed_z1, z1 - 4.0,
                gates=[("west", (shed_z1 + z1) / 2, 26.0)])


def works_canteen_block(x0, x1, z0, z1):
    """The east end of the north row, and the only soft thing in the district: a
    canteen on the street and a green behind it.

    It is here because a works with nowhere to stand still is a works nobody
    lingers in, and every activity this district will eventually hold needs
    somewhere to wait between shifts."""
    cx0, cx1 = x1 - 68.0, x1
    cz1 = z0 + 36.0
    storefront("Canteen", cx0, cx1, z0, cz1, (cx0 + cx1) / 2, BRICK_PALE,
               front="south", front_type="counter", storeys=1,
               awning=AWNING_MUSTARD, glass="full")
    street_fittings("Canteen", cx0, cx1, z0, cz1, "south", "cafe")
    place_point("works_canteen", (cx0 + cx1) / 2, z0 - 2.0, PAVING,
                "the works canteen")
    pocket_park(cx0, cx1, cz1 + 8.0, z1 - 6.0, "FurnaceGreen", "FURNACE GREEN")


def works_power(x0, x1, z0, z1):
    """The north-east block: turbine hall on the street, cooling towers behind.

    The towers are placed north of the hall rather than beside it so that the
    view from the financial district -- which is directly north of here, and the
    only place in the game with height to look down from -- has the two of them
    in front of the hall rather than hidden by it."""
    hall_x0, hall_x1 = x0 + 16.0, x1 - 16.0
    hall_z0 = z0 + SHED_APRON
    hall_z1 = hall_z0 + 66.0
    door = works_shed("TurbineHall", hall_x0, hall_x1, hall_z0, hall_z1, "south",
                      2, GROUND + 36.0, WORKS_CLAD_2, sign_text="SOUTHBANK POWER",
                      brick=CONCRETE_GREY)
    place_point("power_plant", door, hall_z0 - SHED_APRON / 2, GROUND,
                "the turbine hall at Southbank Power")

    with group("PowerYard"):
        hardstanding("Yard", hall_x0, hall_x1, hall_z1, z1 - 6.0)
    cooling_tower("CoolingW", hall_x0 + 40.0, hall_z1 + 36.0)
    cooling_tower("CoolingE", hall_x0 + 108.0, hall_z1 + 36.0, height=58.0)
    # The switchyard: transformers and gantries, between the hall and the towers.
    with group("Switchyard"):
        for i in range(4):
            tx = hall_x0 + 12.0 + i * 18.0
            box(f"Transformer{i}", (tx, tx + 11.0, hall_z1 + 4.0, hall_z1 + 15.0,
                                    GROUND, GROUND + 9.0), (150, 150, 146), METAL)
            for b in range(3):
                box(f"Bushing{i}_{b}", (tx + 2.0 + b * 3.4, tx + 4.0 + b * 3.4,
                                        hall_z1 + 8.0, hall_z1 + 10.0,
                                        GROUND + 9.0, GROUND + 14.0),
                    (232, 228, 216), PLASTIC)
        for i in range(3):
            px = hall_x0 + 96.0 + i * 26.0
            box(f"Pylon{i}", (px - 1.2, px + 1.2, hall_z1 + 8.0, hall_z1 + 10.4,
                              GROUND, GROUND + 30.0), STEEL, METAL)
            box(f"Crossarm{i}", (px - 9.0, px + 9.0, hall_z1 + 8.6, hall_z1 + 9.8,
                                 GROUND + 26.0, GROUND + 27.4), STEEL, METAL)
    works_fence("PowerFence", hall_x0 - 6.0, hall_x1 + 6.0, hall_z1, z1 - 4.0,
                gates=[("west", (hall_z1 + z1) / 2, 24.0)])


def works_timber(x0, x1, z0, z1):
    """The south-west block, west half: a saw mill with its log yard.

    Fronts *north*, onto works street 2, so that the whole south row faces the
    street the north row's backs are turned to -- which is the answer to the one
    complaint that started this map work at all, a row of identical buildings all
    facing the same way."""
    mill_x0, mill_x1 = x0 + 12.0, x0 + 176.0
    mill_z1 = z1 - SHED_APRON
    mill_z0 = mill_z1 - 52.0
    door = works_shed("SawMill", mill_x0, mill_x1, mill_z0, mill_z1, "north",
                      2, GROUND + 24.0, WORKS_CLAD, sign_text="SIMMONS TIMBER",
                      brick=LOG_BROWN)
    place_point("timber_mill", door, mill_z1 + SHED_APRON / 2, GROUND,
                "the Simmons Timber mill")

    with group("TimberYard"):
        hardstanding("Yard", mill_x0, mill_x1, z0 + 4.0, mill_z0)
    for i in range(3):
        log_pile(f"TimberLogs{i}", mill_x0 + 14.0 + i * 52.0,
                 mill_x0 + 46.0 + i * 52.0, mill_z0 - 22.0)
    for i in range(2):
        box(f"TimberStack{i}", (mill_x0 + 24.0 + i * 60.0, mill_x0 + 60.0 + i * 60.0,
                                z0 + 10.0, z0 + 26.0, GROUND, GROUND + 8.0),
            (176, 150, 110), PLANKS)
    works_fence("TimberFence", mill_x0 - 4.0, mill_x1 + 4.0, z0 + 2.0, mill_z0,
                gates=[("east", (z0 + mill_z0) / 2, 24.0)])


def works_scrapyard(x0, x1, z0, z1):
    """The south-west block, east half: reclamation. Open yard, a crusher, and a
    weighbridge office on the street -- the office is the building, the yard is
    the reason to come here."""
    off_x0, off_x1 = x1 - 76.0, x1 - 8.0
    off_z0 = z1 - 34.0
    storefront("Weighbridge", off_x0, off_x1, off_z0, z1, (off_x0 + off_x1) / 2,
               WORKS_CLAD, front="north", front_type="counter", storeys=1,
               wall_mat=METAL, glass="high")
    place_point("scrapyard", (off_x0 + off_x1) / 2, z1 + 2.0, PAVING,
                "the scrapyard weighbridge")
    with group("ScrapyardWeighplate"):
        box("Plate", (off_x0 - 30.0, off_x0 - 4.0, z1 - 16.0, z1 - 2.0,
                      GROUND, GROUND + 0.4), STEEL, DIAMOND_PLATE)

    with group("ScrapYard"):
        hardstanding("Yard", x1 - 148.0, x1 - 4.0, z0 + 4.0, off_z0 - 6.0)
    for i, (sx, sz, r, h) in enumerate(((x1 - 130.0, z0 + 26.0, 18.0, 15.0),
                                        (x1 - 88.0, z0 + 20.0, 14.0, 11.0),
                                        (x1 - 46.0, z0 + 30.0, 16.0, 13.0),
                                        (x1 - 100.0, z0 + 56.0, 13.0, 9.0))):
        scrap_pile(f"Scrap{i}", sx, sz, r, h)
    # The crusher: a hopper on legs with a chute, and the one machine here that
    # is obviously a machine.
    with group("Crusher"):
        cx = x1 - 34.0
        box("Frame", (cx - 12.0, cx + 12.0, z0 + 54.0, z0 + 70.0,
                      GROUND, GROUND + 18.0), SAFETY_YELLOW, METAL)
        box("Hopper", (cx - 14.0, cx + 14.0, z0 + 52.0, z0 + 72.0,
                       GROUND + 18.0, GROUND + 30.0), RUST, CORRODED_METAL)
        box("Chute", (cx + 12.0, cx + 30.0, z0 + 58.0, z0 + 66.0,
                      GROUND + 8.0, GROUND + 13.0), STEEL, METAL)
    works_fence("ScrapFence", x1 - 152.0, x1 - 2.0, z0 + 2.0, off_z0 - 4.0,
                gates=[("west", (z0 + off_z0) / 2, 26.0)])


def works_depot(x0, x1, z0, z1):
    """The south-east block: the container depot, and the district's link to the
    wharf. A transit shed on the street, stacks behind it, and a gantry over
    them -- which is the thing you can see from the quay four hundred studs away.
    """
    shed_x0, shed_x1 = x0 + 10.0, x0 + 150.0
    shed_z1 = z1 - SHED_APRON
    shed_z0 = shed_z1 - 46.0
    door = works_shed("TransitShed", shed_x0, shed_x1, shed_z0, shed_z1, "north",
                      3, GROUND + 26.0, WORKS_CLAD_2, sign_text="HARBOUR FREIGHT")
    place_point("freight_depot", door, shed_z1 + SHED_APRON / 2, GROUND,
                "the Harbour Freight transit shed")

    # Two yard surfaces rather than one: the shed stands in the middle of the
    # block's north edge, and a single slab covering both sides of it would run
    # under the shed's own footprint -- which is invisible, but it also puts a
    # yard model's bounding box round a building model's, and that is the shape
    # of a check-5 report nobody can act on.
    yard_z1 = shed_z0 - 4.0
    apron_z0, apron_z1 = z0 + 4.0, z1 - 6.0
    with group("DepotYard"):
        hardstanding("Stacks", x0 + 6.0, shed_x1 + 20.0, z0 + 4.0, yard_z1)
        hardstanding("EastApron", shed_x1 + 20.0, x1 - 6.0, apron_z0, apron_z1)
    # Three stacks across, two rows deep, on the west yard.
    for i in range(6):
        container_stack(f"DepotStack{i}", x0 + 40.0 + (i % 3) * 46.0,
                        z0 + 20.0 + (i // 3) * 17.0, "x", 2 + (i % 2), i)
    # ...and a line of them along the east apron, turned ninety degrees so the
    # yard reads as sorted rather than as one pattern repeated. The pitch is
    # solved from the apron rather than typed: a typed 40 fitted the row it was
    # measured on and then ran the last container thirteen studs through the
    # works street's south pavement the first time the block moved.
    rows = 3
    pitch = (apron_z1 - apron_z0 - BOX_L - 2 * BOX_MARGIN) / (rows - 1)
    for i in range(rows):
        container_stack(f"DepotRow{i}", x1 - 38.0,
                        apron_z0 + BOX_MARGIN + BOX_L / 2 + i * pitch,
                        "z", 1, i + 2)
    # The gantry straddles the west yard, its legs clear of the outermost stack
    # (which reaches x0+149) and of the east apron's containers.
    gantry("DepotGantry", x0 + 8.0, x0 + 162.0, z0 + 46.0)
    works_fence("DepotFence", x0 + 4.0, x1 - 4.0, z0 + 2.0, yard_z1,
                gates=[("east", z0 + 40.0, 26.0), ("south", (x0 + x1) / 2, 26.0)])


def works_boundary(x0, x1, z0, z1, name="WorksBoundary", label="BoundaryTree",
                   along="x", edge="low"):
    """An apron at the edge of the map: what the world does instead of stopping.

    A verge and a treeline, because the alternative out here is the baseplate --
    and an edge a player can see the far side of is an edge they walk to. Trees,
    so that the thing beyond reads as somewhere the city has not got to yet
    rather than as the end of the world.

    The works' south apron was the only one when this was written and every
    argument below was a constant in the body. There are three now -- the estate
    has one along the top of the map and one down the west side -- and the
    alternative to parameterising this was a third and fourth copy of a treeline
    loop, in a file where `tree` itself was written out three times before
    somebody went looking. `along` is the axis the trees run down and `edge` says
    which face of the apron is the map edge, so the trees stand on the outside
    of the verge in all four orientations rather than in the middle of it.

    The defaults reproduce the works' apron exactly, to the stud and to the part
    name, so the one caller that predates the arguments is untouched by them."""
    if along not in ("x", "z"):
        raise ValueError(f"{name}: an apron runs along x or z, not {along}")
    with group(name):
        box("Verge", (x0, x1, z0, z1, GROUND_BOTTOM, CITY_GRASS_TOP + GRASS_LIFT),
            PITCH_GREEN, GRASS)
    a0, a1 = (x0, x1) if along == "x" else (z0, z1)
    b0, b1 = (z0, z1) if along == "x" else (x0, x1)
    for i in range(int((a1 - a0) / 30.0)):
        # The three-deep stagger comes off whichever face is the map edge, so an
        # apron on the north of the world has its trees along its north side.
        near = b0 + 12.0 if edge == "low" else b1 - 12.0
        step = 7.0 if edge == "low" else -7.0
        ta, tb = a0 + 15.0 + i * 30.0, near + (i % 3) * step
        tree(*((ta, tb) if along == "x" else (tb, ta)), GROUND,
             height=17.0 + (i % 4) * 3.0, spread=12.0 + (i % 3) * 2.0,
             label=f"{label}{i}")


def works_wharf_fittings():
    """What stands on the quay: a crane, a stack of containers waiting to be
    loaded, and the place point. The quay itself is drawn with the shoreline --
    it is part of the coast, not part of a block."""
    apron_x0 = SHORE_X_BAY - WHARF_W
    z0, z1 = WORKS_Z0, WORKS_Z1
    with group("WharfYard"):
        for i in range(3):
            container_stack(f"WharfStack{i}", apron_x0 + 14.0, z0 + 70.0 + i * 46.0,
                            "z", 2, i + 1)
    gantry("WharfCrane", apron_x0 + 6.0, SHORE_X_BAY - 6.0, z0 + 190.0, height=48.0)
    place_point("works_wharf", apron_x0 + 9.0, z0 + 150.0, PAVING,
                "the works wharf, at the quayside")


# The six buildings, laid into the four blocks. Written out rather than driven
# from a table: each one is a different shape doing a different job, and a table
# with six rows and no two the same is a table pretending to be a pattern.
_wx = WORKS_COL_X
_wz = WORKS_ROW_Z
works_ironworks(_wx[0][0], _wx[0][1], _wz[1][0], _wz[1][1])
works_canteen_block(_wx[0][0], _wx[0][1], _wz[1][0], _wz[1][1])
works_power(_wx[1][0], _wx[1][1], _wz[1][0], _wz[1][1])
works_timber(_wx[0][0], _wx[0][1], _wz[0][0], _wz[0][1])
works_scrapyard(_wx[0][0], _wx[0][1], _wz[0][0], _wz[0][1])
works_depot(_wx[1][0], _wx[1][1], _wz[0][0], _wz[0][1])
works_boundary(WORKS_X0, WORKS_X1, WORKS_Z0, SOUTH_CS[0] - CS_WALK)
works_wharf_fittings()


# ---------------------------------------------------------------------------
# The west estate: what stands in it
# ---------------------------------------------------------------------------
#
# Seven blocks, and no two of them face the same way by accident. Streets 2 and
# 3 each get a front on both sides -- haulage south-facing against the workshop
# north of it, plant hire against the distribution shed -- so half the estate is
# a street with buildings down both flanks rather than a service road with backs
# turned to it. `works_timber`'s docstring names that as the complaint that
# started this map work at all, and an estate laid out in one pass is the one
# place it costs nothing to fix.
#
# The deepest thing any row has to hold, from the parts that make it: a shed
# with an apron in front, a container turned broadside behind it, and the
# clearance a container keeps off the edge of its slab. This is where the top
# row's depth gets checked, because SHED_APRON, SHED_DEPTH_MAX, BOX_L and
# BOX_MARGIN all exist by now and none of them existed where EST_ROW_Z is built.
SHED_DEPTH_MAX = 56.0
EST_ROW_MIN = SHED_APRON + SHED_DEPTH_MAX + BOX_L + 2 * BOX_MARGIN
_est_top = EST_ROW_Z[-1][1] - EST_ROW_Z[-1][0]
assert EST_ROW_MIN <= _est_top < max(EST_ROW_DEPTH) + CS_PITCH + EST_ROW_MIN, (
    f"the estate's top row came out {_est_top:.0f} studs deep. Under "
    f"{EST_ROW_MIN:.0f} it cannot hold a shed with an apron in front and a "
    f"container behind it, which is what every other row in this estate holds, "
    f"and the block would be squashed rather than dropped -- nothing else in "
    f"this tree would say so. Over "
    f"{max(EST_ROW_DEPTH) + CS_PITCH + EST_ROW_MIN:.0f} there is room for a "
    f"fifth street and a fifth row and the estate should have them. The row is "
    f"the remainder of the band, so fix it by changing EST_ROW_DEPTH -- not by "
    f"moving EST_Z1, which is the city's north edge and not the estate's.")

# Trade-counter units on the estate's front row: the width a small trade counter
# needs, and the gap between two of them. Both are read back out of the row by
# `solve_row`, so this is the shape of the parade rather than four typed spans.
EST_UNIT_GAP = 10.0


def est_trade_park(x0, x1, z0, z1):
    """The estate's front row, east half: four trade counters facing the town.

    These are the only buildings in the estate a player walks into rather than
    drives to, and they are on the block nearest the town's north road for that
    reason -- a builders' merchant is a shop with a yard behind it, and the shop
    half belongs where the footfall arrives.
    """
    depth = 38.0
    spans = solve_row(x0 + 10.0, x1 - 10.0, [1, 1, 1, 1], EST_UNIT_GAP)
    # `front_type` is the shape of the opening and `trade` is what is behind it.
    # The tool hire gets a roll-up door because that is what a hire counter is --
    # you drive a mixer out of it -- and it is the one of the four that reads as
    # industry from across the street rather than as a shop with a yard.
    units = (("est_plumbers", "Hartley Plumbing", "shop", "counter",
              BRICK_PALE, AWNING_BLUE),
             ("est_electrical", "Kemp Electrical", "shop", "shelves",
              WORKS_CLAD, None),
             ("est_toolhire", "Ridge Tool Hire", "garage", "racks",
              WORKS_BRICK, None),
             ("est_timber_counter", "Ashby Timber", "shop", "market",
              LOG_BROWN, AWNING_GREEN))
    for (ux0, ux1), (pid, name, ftype, trade, colour, awning) in zip(spans, units):
        mid = (ux0 + ux1) / 2
        tag = name.replace(" ", "")
        storefront(tag, ux0, ux1, z0, z0 + depth, mid, colour,
                   front="south", front_type=ftype, storeys=1,
                   awning=awning, glass="high")
        street_fittings(tag, ux0, ux1, z0, z0 + depth, "south", trade)
        place_point(pid, mid, z0 - 2.0, PAVING, f"{name}, on the estate's front row")

    # The customer yard behind them. A trade counter without somewhere to load a
    # van is a shop with a lorry sign on it, and this is the whole difference
    # between this row and the main street's.
    with group("TradeParkYard"):
        hardstanding("Loading", x0 + 6.0, x1 - 6.0, z0 + depth + 6.0, z1 - 24.0)
        for i, (sx0, sx1) in enumerate(spans):
            box(f"Bay{i}", (sx0 + 4.0, sx1 - 4.0, z0 + depth + 8.0, z0 + depth + 9.0,
                            GROUND, GROUND + 0.06), SAFETY_YELLOW, SMOOTH, collide=False)
    for i in range(4):
        tree(x0 + 26.0 + i * (x1 - x0 - 52.0) / 3.0, z1 - 12.0, GROUND,
             height=16.0, spread=11.0, label=f"TradeParkTree{i}")
    for (ux0, ux1) in spans[::2]:
        street_lamp((ux0 + ux1) / 2, z0 - 6.0, 1, label=f"TradeParkLamp{ux0:.0f}")


def est_builders_merchant(x0, x1, z0, z1):
    """The estate's front row, west half: aggregates and building materials.

    Bays rather than a second shed. A merchant's yard is a row of three-sided
    concrete pens with a different heap in each one, and that is a shape this
    file has nowhere else -- the works stores things in stacks, in piles and in
    containers, and none of them reads as *sold by the tonne*."""
    shed_x0, shed_x1 = x0 + 14.0, x0 + 190.0
    shed_z0 = z0 + SHED_APRON
    shed_z1 = shed_z0 + 46.0
    door = works_shed("MerchantShed", shed_x0, shed_x1, shed_z0, shed_z1, "south",
                      3, GROUND + 26.0, WORKS_CLAD, sign_text="DALEY BUILDING SUPPLIES",
                      brick=WORKS_BRICK)
    place_point("est_merchant", door, shed_z0 - SHED_APRON / 2, GROUND,
                "Daley Building Supplies, on the estate's front row")

    yard_z0 = shed_z1 + 6.0
    with group("MerchantYard"):
        hardstanding("Yard", x0 + 8.0, x1 - 8.0, yard_z0, z1 - 6.0)
    # Four aggregate bays along the back wall, each a three-sided pen with its
    # own heap. The pen walls are what make a heap read as stock rather than as
    # spoil, which is the difference between this yard and the scrapyard's.
    pens = solve_row(x0 + 20.0, x1 - 20.0, [1, 1, 1, 1], 6.0)
    heaps = ((196, 190, 176), (162, 148, 128), (120, 116, 112), (150, 108, 78))
    for i, ((px0, px1), heap) in enumerate(zip(pens, heaps)):
        with group(f"MerchantBay{i}"):
            box("Back", (px0, px1, z1 - 40.0, z1 - 36.0, GROUND, GROUND + 12.0),
                CONCRETE_GREY, CONCRETE)
            for side, sx in (("W", px0), ("E", px1 - 4.0)):
                box(f"Wall{side}", (sx, sx + 4.0, z1 - 40.0, z1 - 12.0,
                                    GROUND, GROUND + 12.0), CONCRETE_GREY, CONCRETE)
            box("Heap", (px0 + 5.0, px1 - 5.0, z1 - 35.0, z1 - 15.0,
                         GROUND, GROUND + 9.0), heap, PEBBLE)
            box("HeapTop", (px0 + 9.0, px1 - 9.0, z1 - 32.0, z1 - 19.0,
                            GROUND + 9.0, GROUND + 12.5), heap, PEBBLE)
    for i in range(2):
        silo(f"MerchantSilo{i}", x1 - 46.0 + i * 18.0, yard_z0 + 24.0, height=30.0)
    for i in range(2):
        log_pile(f"MerchantTimber{i}", x0 + 210.0, x0 + 244.0, yard_z0 + 20.0 + i * 26.0)
    works_fence("MerchantFence", x0 + 6.0, x1 - 6.0, yard_z0 - 2.0, z1 - 4.0,
                gates=[("south", x1 - 60.0, 26.0)])


def est_selfstore(x0, x1, z0, z1):
    """Second row, east: self-storage. Containers on a slab, and an office.

    Cheap to build and it earns its place twice: it is the one destination in
    the estate that a *resident* has a reason to visit rather than a worker, and
    a yard of identical locked boxes is the terrain the crime stack has nowhere
    else on the map."""
    off_x0, off_x1 = x1 - 76.0, x1 - 10.0
    storefront("StoreOffice", off_x0, off_x1, z0, z0 + 30.0, (off_x0 + off_x1) / 2,
               BRICK_PALE, front="south", front_type="counter", storeys=1,
               glass="high")
    street_fittings("StoreOffice", off_x0, off_x1, z0, z0 + 30.0, "south", "desk")
    place_point("est_selfstore", (off_x0 + off_x1) / 2, z0 - 2.0, PAVING,
                "the office at Northgate Self Storage")

    yard_z0, yard_z1 = z0 + 8.0, z1 - 8.0
    with group("SelfStoreYard"):
        hardstanding("Yard", x0 + 8.0, off_x0 - 8.0, yard_z0, yard_z1)
        hardstanding("Drive", off_x0 - 8.0, x1 - 8.0, z0 + 38.0, yard_z1)
    # Four aisles of single-height containers, laid broadside so the gaps between
    # them are aisles a player walks down rather than slots seen end-on. The
    # pitch is solved out of the yard for the reason `works_depot` gives: a typed
    # pitch fits the yard it was measured in and overhangs the next one.
    rows, per_row = 4, 3
    pitch = (yard_z1 - yard_z0 - BOX_W - 2 * BOX_MARGIN) / (rows - 1)
    for r in range(rows):
        rz = yard_z0 + BOX_MARGIN + BOX_W / 2 + r * pitch
        for c in range(per_row):
            container_stack(f"SelfStore{r}_{c}", x0 + 30.0 + c * (BOX_L + 6.0), rz,
                            "x", 1 + (r + c) % 2, r + c)
    works_fence("SelfStoreFence", x0 + 4.0, x1 - 6.0, yard_z0 - 2.0, yard_z1 + 2.0,
                gates=[("south", x1 - 40.0, 24.0)])


def est_haulage(x0, x1, z0, z1):
    """Second row, west: a haulage yard, fronting *north* onto street 3.

    The one block in the estate a lorry is the reason for. Everything in it is
    laid out around the turn: the shed at the back of the yard rather than on
    the street, the apron deep enough to swing a trailer, and the gate on the
    long side rather than the short one."""
    shed_x0, shed_x1 = x0 + 24.0, x0 + 214.0
    shed_z1 = z1 - SHED_APRON
    shed_z0 = shed_z1 - 48.0
    door = works_shed("HaulageShed", shed_x0, shed_x1, shed_z0, shed_z1, "north",
                      3, GROUND + 28.0, WORKS_CLAD_2, sign_text="MARCH & SON HAULAGE")
    place_point("est_haulage", door, shed_z1 + SHED_APRON / 2, GROUND,
                "March & Son Haulage, on the estate's second street")

    yard_z1 = shed_z0 - 6.0
    with group("HaulageYard"):
        hardstanding("Yard", x0 + 8.0, x1 - 8.0, z0 + 6.0, yard_z1)
    # Trailers parked nose-in along the south edge: box bodies on legs, which is
    # the cheapest thing that reads as a vehicle yard without a vehicle in it.
    for i in range(5):
        tx = x0 + 34.0 + i * 56.0
        with group(f"HaulageTrailer{i}"):
            box("Body", (tx - 9.0, tx + 9.0, z0 + 14.0, z0 + 52.0,
                         GROUND + 5.0, GROUND + 18.0),
                CONTAINER_COLORS[i % len(CONTAINER_COLORS)], SMOOTH)
            box("Skirt", (tx - 8.0, tx + 8.0, z0 + 16.0, z0 + 50.0,
                          GROUND + 3.4, GROUND + 5.0), (58, 58, 60), METAL)
            for dz in (z0 + 20.0, z0 + 46.0):
                box(f"Bogie{dz:.0f}", (tx - 8.5, tx + 8.5, dz - 3.0, dz + 3.0,
                                       GROUND, GROUND + 3.4), (40, 40, 42), METAL)
            box("Legs", (tx - 7.0, tx + 7.0, z0 + 15.0, z0 + 16.5,
                         GROUND, GROUND + 5.0), STEEL, METAL)
    for i in range(3):
        container_stack(f"HaulageStack{i}", x1 - 40.0, z0 + 74.0 + i * 40.0, "z",
                        2, i + 1)
    gantry("HaulageGantry", x0 + 16.0, x0 + 150.0, z0 + 78.0, height=34.0)
    works_fence("HaulageFence", x0 + 6.0, x1 - 6.0, z0 + 4.0, yard_z1,
                gates=[("east", z0 + 40.0, 28.0), ("north", x1 - 50.0, 26.0)])


def est_workshop(x0, x1, z0, z1):
    """Third row, east: a commercial vehicle workshop, fronting south onto the
    same street the haulage yard's shed faces.

    Two fronts on one street is what makes street 3 a street. It is also the
    only pairing in the estate that means anything on the ground: the lorries
    are repaired across the road from where they are parked."""
    shed_x0, shed_x1 = x0 + 12.0, x1 - 12.0
    shed_z0 = z0 + SHED_APRON
    shed_z1 = shed_z0 + 44.0
    door = works_shed("WorkshopShed", shed_x0, shed_x1, shed_z0, shed_z1, "south",
                      3, GROUND + 24.0, WORKS_CLAD, sign_text="BRANDT COMMERCIALS",
                      brick=CONCRETE_GREY)
    place_point("est_workshop", door, shed_z0 - SHED_APRON / 2, GROUND,
                "Brandt Commercials, the estate's vehicle workshop")

    yard_z0 = shed_z1 + 6.0
    with group("WorkshopYard"):
        hardstanding("Yard", x0 + 8.0, x1 - 8.0, yard_z0, z1 - 8.0)
    # The fuel island: a canopy on two columns with a pair of pumps under it.
    # Every other roof in the estate is a shed roof, and this is the one that is
    # not -- which is what makes the block legible from the street.
    fx = x0 + 46.0
    with group("WorkshopFuel"):
        box("Canopy", (fx - 24.0, fx + 24.0, yard_z0 + 14.0, yard_z0 + 42.0,
                       GROUND + 17.0, GROUND + 20.0), (236, 232, 224), SMOOTH)
        box("Fascia", (fx - 24.0, fx + 24.0, yard_z0 + 13.0, yard_z0 + 43.0,
                       GROUND + 20.0, GROUND + 22.5), SAFETY_YELLOW, SMOOTH)
        for cx in (fx - 18.0, fx + 18.0):
            box(f"Column{cx:.0f}", (cx - 1.6, cx + 1.6, yard_z0 + 26.0, yard_z0 + 30.0,
                                    GROUND, GROUND + 17.0), STEEL, METAL)
        for px in (fx - 9.0, fx + 9.0):
            box(f"Pump{px:.0f}", (px - 2.2, px + 2.2, yard_z0 + 25.0, yard_z0 + 31.0,
                                  GROUND, GROUND + 7.0), (206, 72, 60), SMOOTH)
    for i in range(3):
        scrap_pile(f"WorkshopParts{i}", x1 - 66.0 + (i % 2) * 30.0,
                   yard_z0 + 18.0 + i * 26.0, 9.0 + (i % 2) * 3.0, 6.0)
    works_fence("WorkshopFence", x0 + 6.0, x1 - 6.0, yard_z0 - 2.0, z1 - 6.0,
                gates=[("west", yard_z0 + 30.0, 24.0)])


def est_planthire(x0, x1, z0, z1):
    """Third row, west: plant and tool hire, fronting north onto street 4.

    Pipe racks and a spoil heap rather than another container yard. What the
    block is for is a hire counter you walk into and a compound you can see over
    the fence -- the compound is the thing being sold."""
    shed_x0, shed_x1 = x1 - 190.0, x1 - 16.0
    shed_z1 = z1 - SHED_APRON
    shed_z0 = shed_z1 - 44.0
    door = works_shed("PlantShed", shed_x0, shed_x1, shed_z0, shed_z1, "north",
                      2, GROUND + 26.0, WORKS_CLAD_2, sign_text="VALE PLANT HIRE",
                      brick=WORKS_BRICK)
    place_point("est_planthire", door, shed_z1 + SHED_APRON / 2, GROUND,
                "Vale Plant Hire, at the top of the estate")

    yard_z1 = shed_z0 - 6.0
    with group("PlantYard"):
        hardstanding("Compound", x0 + 8.0, x1 - 8.0, z0 + 8.0, yard_z1)
    for i in range(3):
        pipe_rack(f"PlantPipes{i}", x0 + 24.0, x0 + 124.0, z0 + 24.0 + i * 22.0,
                  height=12.0 + (i % 2) * 4.0, pipes=3)
    for i, (sx, sz, r, h) in enumerate(((x1 - 70.0, z0 + 30.0, 15.0, 11.0),
                                        (x1 - 118.0, z0 + 24.0, 12.0, 8.0))):
        scrap_pile(f"PlantSpoil{i}", sx, sz, r, h)
    for i in range(2):
        container_stack(f"PlantStore{i}", x0 + 168.0 + i * 44.0, yard_z1 - 22.0,
                        "x", 1, i + 2)
    works_fence("PlantFence", x0 + 6.0, x1 - 6.0, z0 + 6.0, yard_z1,
                gates=[("south", x0 + 90.0, 26.0)])


def est_distribution(x0, x1, z0, z1):
    """The top row, all of it: the distribution shed.

    One block and not two. The avenues stop at street 4, so there is no road
    down the middle of this row to divide it -- and a 632-stud frontage is the
    one place in the estate big enough for a building that reads from the far
    side of the map, which is what the top of the world needs standing on it."""
    shed_x0, shed_x1 = x0 + 60.0, x0 + 420.0
    shed_z0 = z0 + SHED_APRON
    shed_z1 = shed_z0 + SHED_DEPTH_MAX
    door = works_shed("DistributionShed", shed_x0, shed_x1, shed_z0, shed_z1, "south",
                      5, GROUND + 34.0, WORKS_CLAD, sign_text="NORTHGATE DISTRIBUTION",
                      brick=CONCRETE_GREY)
    place_point("est_distribution", door, shed_z0 - SHED_APRON / 2, GROUND,
                "Northgate Distribution, at the top of the map")

    yard_z0 = shed_z1 + 6.0
    with group("DistributionYard"):
        hardstanding("Yard", x0 + 20.0, shed_x1 + 10.0, yard_z0, z1 - 8.0)
        hardstanding("EastApron", shed_x1 + 10.0, x1 - 14.0, z0 + 8.0, z1 - 8.0)
    for i in range(6):
        container_stack(f"DistStack{i}", x0 + 60.0 + (i % 3) * 48.0,
                        yard_z0 + 18.0 + (i // 3) * 18.0, "x", 2 + (i % 2), i)
    rows = 3
    apron_z0, apron_z1 = z0 + 8.0, z1 - 8.0
    pitch = (apron_z1 - apron_z0 - BOX_L - 2 * BOX_MARGIN) / (rows - 1)
    for i in range(rows):
        container_stack(f"DistRow{i}", x1 - 44.0,
                        apron_z0 + BOX_MARGIN + BOX_L / 2 + i * pitch, "z", 1, i + 3)
    gantry("DistributionGantry", x0 + 34.0, x0 + 180.0, yard_z0 + 26.0, height=38.0)
    works_fence("DistributionFence", x0 + 16.0, x1 - 10.0, yard_z0 - 2.0, z1 - 6.0,
                gates=[("east", yard_z0 + 34.0, 28.0)])


# How much of the common one field is, and how wide the farm track running into
# it is. The track is the width of a vehicle and no more -- it is a track, and a
# second carriageway out here would be a road the estate does not need and the
# route lattice would have to be extended down.
EST_FIELD_ROWS = 3
EST_TRACK_W = 12.0
# Where the track runs and where it stops. Module level rather than local to
# `est_common`, because the route lattice has to chain along it and a second
# copy of "the middle of the estate's second street" computed down there would
# be the third place that phrase is written down in this file.
EST_TRACK_Z = EST_CS[1] + WCS_W / 2
EST_TRACK_GATE_X = EST_X0 + WORKS_APRON + 18.0


def est_common(x0, x1, z0, z1):
    """West of the estate: rough grazing, hedgerows and a farm track.

    Four hundred studs of it, and the alternative was a wider estate. This world
    does not have the jobs for one -- the estate is already seven yards against
    the works' six -- and a district built to fill a rectangle is a district with
    nothing in it. Open country is the honest answer to land the city has not
    reached, and it is the answer `works_boundary` already gives on the south of
    the works, just at forty studs instead of four hundred.

    It is also the only ground in the world that is neither street nor building.
    Everything the crime stack does is currently done in front of a window."""
    with group("CommonGround"):
        # The common's own ground, not a colour laid over the estate's: WestGround
        # stops at this box's east face. Same top height as the estate's lawn,
        # because they are the same ground at different colours -- what makes the
        # seam invisible is that they abut rather than overlap.
        box("Pasture", (x0, x1, z0, z1, GROUND_BOTTOM, CITY_GRASS_TOP),
            PITCH_GREEN, GRASS)

    # The track: west out of the junction at the west end of the estate's second
    # street, because that junction already exists and a track that begins at a
    # road is a track somebody drove. It stops at a field gate rather than at the
    # treeline -- a track that runs into a hedge is a texture, a track that ends
    # at a gate is somewhere the map used to go.
    track_z, gate_x = EST_TRACK_Z, EST_TRACK_GATE_X
    with group("CommonTrack"):
        # GROUND exactly, like a road or a park path: the pasture tops a
        # fiftieth lower, so the track always wins the pixel where they meet. At
        # GROUND - 0.04 it was drawn *under* the pasture and was not there at all
        # -- a surface that loses to the ground it is laid on is invisible, and
        # nothing in this tree would have reported it.
        box("Track", (gate_x, x1, track_z - EST_TRACK_W / 2, track_z + EST_TRACK_W / 2,
                      GROUND_BOTTOM, GROUND), (152, 138, 112), PEBBLE)
        for side, sz in (("S", track_z - EST_TRACK_W / 2), ("N", track_z + EST_TRACK_W / 2)):
            box(f"Rut{side}", (gate_x, x1, sz - 1.4, sz + 1.4,
                               GROUND, GROUND + 0.06), (128, 116, 94), PEBBLE,
                collide=False)
        for post_z in (track_z - EST_TRACK_W / 2 - 1.0, track_z + EST_TRACK_W / 2 + 1.0):
            box(f"GatePost{post_z:.0f}", (gate_x - 1.4, gate_x + 1.4,
                                          post_z - 1.4, post_z + 1.4,
                                          GROUND, GROUND + 8.0), LOG_BROWN, WOOD)
        for i in range(3):
            box(f"GateRail{i}", (gate_x - 0.6, gate_x + 0.6,
                                 track_z - EST_TRACK_W / 2, track_z + EST_TRACK_W / 2,
                                 GROUND + 2.0 + i * 2.2, GROUND + 3.0 + i * 2.2),
                LOG_BROWN, WOOD)
    place_point("est_common_gate", gate_x + 8.0, track_z, GROUND,
                "the field gate, west of the estate")

    # Hedgerows dividing the common into fields, one per boundary between them.
    # They stop short of the track so it runs through rather than into them.
    for i in range(1, EST_FIELD_ROWS):
        hz = z0 + (z1 - z0) * i / EST_FIELD_ROWS
        if abs(hz - track_z) < EST_TRACK_W:
            continue
        with group(f"Hedgerow{i}"):
            box("Hedge", (x0 + WORKS_APRON, x1, hz - 3.0, hz + 3.0,
                          GROUND, GROUND + 7.0), (74, 108, 62), LEAFY_GRASS)
        for j in range(int((x1 - x0 - WORKS_APRON) / 46.0)):
            tree(x0 + WORKS_APRON + 24.0 + j * 46.0, hz + (2.0 if j % 2 else -2.0),
                 GROUND, height=19.0 + (j % 3) * 3.0, spread=13.0 + (j % 2) * 3.0,
                 label=f"HedgeTree{i}_{j}")


_ex, _ez = EST_COL_X, EST_ROW_Z
est_trade_park(_ex[0][0], _ex[0][1], _ez[0][0], _ez[0][1])
est_builders_merchant(_ex[1][0], _ex[1][1], _ez[0][0], _ez[0][1])
est_selfstore(_ex[0][0], _ex[0][1], _ez[1][0], _ez[1][1])
est_haulage(_ex[1][0], _ex[1][1], _ez[1][0], _ez[1][1])
est_workshop(_ex[0][0], _ex[0][1], _ez[2][0], _ez[2][1])
est_planthire(_ex[1][0], _ex[1][1], _ez[2][0], _ez[2][1])
est_distribution(EST_COMMON_X1, EST_X1, _ez[3][0], _ez[3][1])
est_common(EST_COMMON_X0, EST_COMMON_X1, EST_Z0, EST_Z1)
# The two map edges. The west one runs the full depth and the north one starts
# where it ends, so the corner belongs to exactly one of them -- two verges
# overlapping there would be two boxes with the same top height, which is the
# defect every surface in this file is tiled to avoid.
works_boundary(EST_X0, EST_X0 + WORKS_APRON, EST_Z0, EST_Z1,
               name="WestBoundary", label="WestEdgeTree", along="z")
works_boundary(EST_X0 + WORKS_APRON, EST_X1, EST_NORTH_APRON[0], EST_NORTH_APRON[1],
               name="NorthBoundary", label="NorthEdgeTree", edge="high")


# ---------------------------------------------------------------------------
# The bayfront
# ---------------------------------------------------------------------------


def sea_band(index, z0, z1, shore_x):
    """One band of water: seabed shelf, two tones of sea over it, sand up the
    beach, and rock armour at the map edge."""
    with group(f"Sea{index}"):
        # Seabed first and full width, so there is a floor under every part of
        # the bay including the strip the revetment stands on.
        box("Seabed", (shore_x, CITY_X1, z0, z1, GROUND_BOTTOM, SEA_FLOOR),
            SEABED, PEBBLE)
        # Two tones, shallow inshore. The break is at a fixed distance from the
        # shore rather than at a fixed x, so the colour follows the coastline
        # around the headland instead of cutting across it.
        shallow_x = min(shore_x + 70.0, CITY_X1)
        box("Shallows", (shore_x, shallow_x, z0, z1, SEA_FLOOR, SEA_TOP),
            SEA_SHALLOW, GLASS, transparency=0.35, collide=False)
        if shallow_x < CITY_X1:
            box("Deep", (shallow_x, CITY_X1, z0, z1, SEA_FLOOR, SEA_TOP),
                SEA_DEEP, GLASS, transparency=0.2, collide=False)
        # Rock armour at the map edge. Collidable, and the only thing out here
        # that is: it is what a player wading east actually stops against.
        rx0 = CITY_X1 - REVETMENT_W
        for i in range(int((z1 - z0) / 18.0)):
            rz = z0 + 9.0 + i * 18.0
            h = GROUND + 2.2 + (i % 3) * 0.9
            box(f"Rock{i}", (rx0 + (i % 2) * 3.0, CITY_X1, rz - 7.0, rz + 7.0,
                             GROUND_BOTTOM, h), (150, 146, 138), SLATE)


def beach_band(index, z0, z1, shore_x):
    """Sand from the waterline back to the walk, and the paved baywalk behind
    it. Both are drawn over the lawn rather than carved out of it: the ground
    is already flat here and a carve would only add seams to keep true."""
    sand_x0 = shore_x - BEACH_W
    walk_x0 = sand_x0 - BAYWALK_W
    with group(f"Beach{index}"):
        box("Sand", (sand_x0, shore_x, z0, z1, GROUND_BOTTOM, GROUND),
            BEACH_SAND, PEBBLE)
        box("Walk", (walk_x0, sand_x0, z0, z1, GROUND_BOTTOM, PAVING),
            PAVING_GREY, PAVEMENT)
        # A low sea wall between the walk and the sand, broken every 120 studs
        # so there is a way down onto the beach. The gaps are the point: a
        # continuous wall would make the sand scenery rather than somewhere to
        # be, and this game is played on foot.
        for gz0, gz1 in carve((z0, z1),
                              [(z0 + 60.0 + i * 120.0, z0 + 84.0 + i * 120.0)
                               for i in range(int((z1 - z0) / 120.0) + 1)]):
            if gz1 - gz0 < 1.0:
                continue
            box(f"SeaWall{gz0:.0f}", (sand_x0 - 1.2, sand_x0, gz0, gz1,
                                      GROUND_BOTTOM, PAVING + 1.4),
                TRIM_WHITE, CONCRETE)
    # Palms down the middle of the walk, benches and lamps facing the water.
    # In the headland band this walk runs right past the stadium's east wall.
    # The palms used to be planted at a fixed x/z offset from the shoreline
    # with no regard for what was built inland of it, so a palm at (~953-959, z)
    # landed inside the bowl for every z the stadium covered. `carve` cuts that
    # span, with a little clearance on each side, out of the row instead.
    # (It used to have to clear the running track as well, which stood north of
    # the stadium until the fields moved to the school.)
    palm_gaps = []
    if shore_x == SHORE_X_HEADLAND:
        palm_gaps.append((STAD_SOUTH_OUT - 8.0, STAD_NORTH_OUT + 10.0))
    for pz0, pz1 in carve((z0, z1), palm_gaps):
        if pz1 - pz0 < 20.0:
            continue
        palm_row(walk_x0 + 4.0, walk_x0 + 10.0, pz0, pz1, PAVING, step=38.0,
                 along="z", label=f"BaywalkPalms{index}{pz0:.0f}")
    with group(f"BaywalkFittings{index}"):
        for i in range(int((z1 - z0) / 76.0)):
            fz = z0 + 38.0 + i * 76.0
            bench(sand_x0 - 5.0, fz, 1)
            street_lamp(walk_x0 + 3.0, fz + 38.0, 1, floor=PAVING)


def pier(x0, name, z_centre, length=110.0, width=16.0):
    """A boardwalk out over the water, with a rail and lamps. Walkable: the deck
    is a solid slab at path height and the rails stop short of the end, which is
    where the place point sits."""
    z0, z1 = z_centre - width / 2, z_centre + width / 2
    x1 = x0 + length
    with group(name):
        box("Deck", (x0, x1, z0, z1, SEA_FLOOR, PAVING), (196, 166, 126), PLANKS)
        for rz in (z0, z1):
            box(f"Rail{rz:.0f}", (x0, x1 - 10.0, rz - 0.4, rz + 0.4,
                                  PAVING, PAVING + 3.2), TRIM_WHITE, WOOD)
        for i in range(int(length / 34.0)):
            street_lamp(x0 + 20.0 + i * 34.0, z0 + 1.6, 1, floor=PAVING)
    return x1


def moored_boat(index, x, z, hull):
    """A small boat at a mooring. Three boxes and a mast -- it is read from the
    baywalk at forty studs, and anything more detailed than this is detail
    nobody is standing close enough to see."""
    with group(f"Boat{index}"):
        box("Hull", (x - 4.0, x + 4.0, z - 11.0, z + 11.0,
                     SEA_TOP - 1.2, SEA_TOP + 1.8), hull, SMOOTH)
        box("Cabin", (x - 2.8, x + 2.8, z - 3.0, z + 5.0,
                      SEA_TOP + 1.8, SEA_TOP + 5.0), TRIM_WHITE, SMOOTH)
        box("Mast", (x - 0.3, x + 0.3, z - 1.0, z - 0.4,
                     SEA_TOP + 5.0, SEA_TOP + 17.0), TRIM_WHITE, METAL)


def quay_band(index, z0, z1, shore_x):
    """The working waterfront: a vertical concrete face with the water against
    it, a paved apron behind, and bollards along the edge.

    The opposite of `beach_band` in every way that matters, and that is the
    point -- a beach says "stop and look at this", a quay says "something is
    loaded here". The apron is the same total width as sand-plus-walk so the two
    edges meet on one line at z=60."""
    apron_x0 = shore_x - WHARF_W
    with group(f"Quay{index}"):
        # The apron, at pavement height rather than ground: a wharf is a built
        # surface, and the half-stud lip against the lawn behind it is the same
        # kerb every pavement in the city has.
        box("Apron", (apron_x0, shore_x - QUAY_FACE_IN, z0, z1,
                      GROUND_BOTTOM, PAVING), CONCRETE_GREY, CONCRETE)
        # The face itself, standing in the water so there is no seam at the
        # waterline where the seabed would otherwise show through.
        box("Face", (shore_x - QUAY_FACE_IN, shore_x + QUAY_FACE_OUT, z0, z1,
                     SEA_FLOOR - 1.0, PAVING), CONCRETE_GREY, CONCRETE)
        # A rubbing strake down the face, which is the one detail that stops it
        # reading as a plain wall from a boat's height.
        box("Fender", (shore_x + QUAY_FACE_OUT, shore_x + 2.4, z0, z1,
                       SEA_TOP - 0.6, SEA_TOP + 1.6), (56, 54, 52), SMOOTH)
        for i in range(int((z1 - z0) / 26.0)):
            bz = z0 + 13.0 + i * 26.0
            box(f"Bollard{i}", (shore_x - 4.4, shore_x - 1.8, bz - 1.3, bz + 1.3,
                                PAVING, PAVING + 2.6), (52, 52, 54), METAL)
            # A ladder every third bollard: the way back up for a player who
            # walks off the edge, which they will, and the shelf is only 2.6
            # studs down but a wall with no way out of the water is a trap.
            if i % 3 == 1:
                box(f"Ladder{i}", (shore_x + QUAY_FACE_OUT, shore_x + 2.2,
                                   bz + 4.0, bz + 5.4,
                                   SEA_FLOOR, PAVING), STEEL, METAL)
    with group(f"QuayFittings{index}"):
        for i in range(int((z1 - z0) / 78.0)):
            street_lamp(apron_x0 + 4.0, z0 + 39.0 + i * 78.0, 1, floor=PAVING)


def bayfront():
    """The whole east edge: sea, sand, walk, and the marina at the south end
    where the walk meets the financial district."""
    for i, (z0, z1, shore_x, edge) in enumerate(SHORE):
        sea_band(i, z0, z1, shore_x)
        (quay_band if edge == "quay" else beach_band)(i, z0, z1, shore_x)

    # The marina, in the southern bay so that it sits under the towers. Two
    # piers with boats moored between them, and the place point on the first
    # pier's head -- which is the furthest out over the water a player can walk
    # and therefore the one spot with the whole skyline in front of them.
    south_shore = SHORE_X_BAY
    with group("Marina"):
        head = pier(south_shore, "PierSouth", 150.0)
        pier(south_shore, "PierNorth", 250.0)
        for i, (bz, hull) in enumerate((
                (176.0, (232, 96, 92)), (200.0, (250, 246, 236)),
                (224.0, (96, 168, 200)), (120.0, (250, 236, 190)))):
            moored_boat(i + 1, south_shore + 44.0 + (i % 2) * 26.0, bz, hull)
    place_point("marina", head - 6.0, 150.0, PAVING,
                "the marina, at the end of the south pier")

    # Somewhere on the walk itself worth naming, halfway up the southern bay.
    walk_x = south_shore - BEACH_W - BAYWALK_W / 2
    place_point("baywalk", walk_x, 320.0, PAVING, "the baywalk, facing the water")


bayfront()


# ---------------------------------------------------------------------------
# Place points and waypoints
# ---------------------------------------------------------------------------


def surface_floor(x, z):
    # `ave_z0(k)` rather than AVE_Z0 in all four avenue tests: three of them run
    # into the works now, and a waypoint dropped on avenue 4 at z=-190 would
    # otherwise be told it was standing on lawn and placed half a stud under the
    # road it is actually on. check 6 measures against real geometry, so the
    # symptom would be "no ground under wp_ave3_2" rather than anything about
    # avenues.
    if CONN_X0 < x < CONN_X1 and CONN_Z0 < z < CONN_Z1:
        return GROUND
    for k, a in enumerate(AVE):
        if a < x < a + AVE_W[k] and on_avenue(k, z):
            return GROUND
    for j, c in enumerate(CS):
        if c < z < c + CS_W[j] and CS_X0 < x < CS_X1:
            return GROUND
    for c in SOUTH_CS:
        if c < z < c + WCS_W and WORKS_X0 < x < WORKS_X1:
            return GROUND
    for a in EST_AVE:
        if a < x < a + AVE_W_MAIN and EST_AVE_Z0 < z < EST_AVE_Z1:
            return GROUND
    for c in EST_CS:
        if c < z < c + WCS_W and EST_CS_X0 < x < EST_CS_X1:
            return GROUND
    if CONN_X0 - CONN_WALK < x < CONN_X0 and CONN_Z0 < z < CONN_Z1:
        return PAVING
    if CONN_X1 < x < CONN_X1 + CONN_WALK and CONN_Z0 < z < CONN_Z1:
        return PAVING
    for k, a in enumerate(AVE):
        if a - AVE_WALK < x < a and on_avenue(k, z):
            return PAVING
        if a + AVE_W[k] < x < a + AVE_W[k] + AVE_WALK and on_avenue(k, z):
            return PAVING
    for j, c in enumerate(CS):
        if CS_X0 < x < CS_X1 and c - CS_WALK < z < c:
            return PAVING
        if CS_X0 < x < CS_X1 and c + CS_W[j] < z < c + CS_W[j] + CS_WALK:
            return PAVING
    for c in SOUTH_CS:
        if WORKS_X0 < x < WORKS_X1 and c - CS_WALK < z < c:
            return PAVING
        if WORKS_X0 < x < WORKS_X1 and c + WCS_W < z < c + WCS_W + CS_WALK:
            return PAVING
    for a in EST_AVE:
        if EST_AVE_Z0 < z < EST_AVE_Z1 and a - AVE_WALK < x < a:
            return PAVING
        if EST_AVE_Z0 < z < EST_AVE_Z1 and a + AVE_W_MAIN < x < a + AVE_W_MAIN + AVE_WALK:
            return PAVING
    for c in EST_CS:
        if EST_CS_X0 < x < EST_CS_X1 and c - CS_WALK < z < c:
            return PAVING
        if EST_CS_X0 < x < EST_CS_X1 and c + WCS_W < z < c + WCS_W + CS_WALK:
            return PAVING
    return GROUND


WAYPOINTS = []


def waypoint(pid, x, z, label, floor=None):
    WAYPOINTS.append((pid, x, z, floor if floor is not None else surface_floor(x, z), label))


# Bridge from the town's east sidewalk into the city. The gate road at z=91
# connects the town's east road (x=-87.5..8) to the connector (x=19..42).
# Both on the gate road's centre line, so they move with it rather than being two
# more numbers to forget. wp_bridge_1 was left behind at z=91 when the road moved
# out of the town house, and stood on open grass until check 6 said so.
_gate_mid = (GATE_Z0 + GATE_Z1) / 2
waypoint("wp_bridge_1", -55.0, _gate_mid, "the gate road, by the town's east edge", GROUND)
waypoint("wp_bridge_2", 8.0, _gate_mid, "the gate road, at the city's south edge", GROUND)

# The connector, chained every 68 studs.
for i, z in enumerate(range(60, 1120, ROUTE_STEP)):
    waypoint(f"wp_conn_{i}", CONN_MID, float(z), "the connector road")

# Avenue road centres, one point every 68 studs so a walk up any avenue chains
# north to south. The road centre is always asphalt: road slab or tile. The
# chain stops where the avenues do -- the precinct beyond is walked, not driven,
# and it has its own chain below.
#
# Four of the grid points land inside the Circle -- two on avenue 3 (z=332 and
# z=400, both on the island) and two on cross street 2 (x=314 in the
# carriageway, x=382 in the island). They are skipped here rather than inside
# waypoint() so that the reason is visible where the lattice is written: the
# ring's own chain below replaces them, and a silent filter would hide the day
# somebody moves the Circle and the grid quietly loses two points.
#
# Avenue 5's points are skipped over the arena superblock for the same reason
# and by the same rule that stops the road being drawn there -- see `ave_gaps`.
# The arena's own forecourt chain replaces them.
def in_circle(x, z):
    return math.hypot(x - CIRCLE_X, z - CIRCLE_Z) < CIRCLE_R_WALK


for k, a in enumerate(AVE):
    for i, z in enumerate(range(int(ave_z0(k)), int(AVE_Z1), ROUTE_STEP)):
        if in_circle(a + AVE_W[k] / 2, float(z)) or not on_avenue(k, float(z)):
            continue
        waypoint(f"wp_ave{k}_{i}", a + AVE_W[k] / 2, float(z), f"avenue {k + 1}")

# Cross street road centres.
for j, c in enumerate(CS):
    for i, x in enumerate(range(int(CS_X0), int(CS_X1), ROUTE_STEP)):
        if in_circle(float(x), c + CS_W[j] / 2):
            continue
        waypoint(f"wp_cs{j}_{i}", float(x), c + CS_W[j] / 2, f"cross street {j + 1}")

# The south streets, the same way. Nothing south of the city is more than a
# block from one of these four, which is the whole reason the works was laid on
# the city's grid rather than given a plan of its own: the lattice is four lines
# of code instead of a bespoke chain per yard.
for j, c in enumerate(SOUTH_CS):
    for i, x in enumerate(range(int(WORKS_X0), int(WORKS_X1), ROUTE_STEP)):
        waypoint(f"wp_ws{j}_{i}", float(x), c + WCS_W / 2, f"south street {j + 1}")

# The two new links out of town. Without these the roads are geometry nothing
# routes down: Routes joins place points within 70 studs and knows nothing about
# tarmac, so a carriageway with no chain on it shortens no journey for anyone but
# a player who already knows it is there. Shortening the journey is the whole
# reason both roads exist, so these chains are not optional decoration.
#
# Southgate takes GROUND explicitly for the same reason wp_bridge_1/2 do: its
# west half stands on ground the *town* generator laid, which surface_floor
# cannot see from in here. Its west end lands 43 studs from the town's
# southernmost road point and its east end 7.5 from wp_ws1_0, so the two networks
# join at both ends of it.
_southgate_mid = (SOUTHGATE_Z0 + SOUTHGATE_Z1) / 2
for _i, _x in enumerate(range(int(ROAD_X1), int(AVE[0]), ROUTE_STEP)):
    waypoint(f"wp_southgate_{_i}", float(_x), _southgate_mid,
             "the southern link, between the town and the works", GROUND)

# The northern link, chained the same way and for the same reason: without this
# the road is tarmac nothing routes down. Its west end lands 12 studs from
# gen_town's wp_top_junction, which stands in the middle of the junction it tees
# into, and its east end 28 from wp_conn_4 -- so the two networks join at both
# ends of it, which is the only property that makes a link a link.
#
# GROUND explicitly, like the southern link: the west half of this road stands on
# ground the *town* generator laid, which surface_floor cannot see from in here.
for _i, _x in enumerate(range(int(ROAD_X1), int(CONN_X0), ROUTE_STEP)):
    waypoint(f"wp_northgate_{_i}", float(_x), NORTHGATE_MID,
             "the northern link, between the town and the connector", GROUND)

# The west estate, on the same four-lines-of-code lattice the works gets, and
# for the same reason: the grid is regular, so a bespoke chain per yard would be
# more code that says less.
#
# Both chains are offset half a junction from the corner rather than started on
# it -- streets from EST_CS_X0 + AVE_W_MAIN/2, avenues from EST_AVE_Z0 + WCS_W/2.
# A point started exactly on a kerb line sits on the *face* of the junction tile
# rather than inside it, and check 6 looks for ground under a point by asking
# which part contains it. Half a carriageway in is unambiguous, and it also lands
# the two chains on each other at every crossing instead of 12 studs apart.
#
# The four street chains are what tie the estate to the rest of the world: each
# one ends between 11 and 20 studs west of the connector's carriageway, and the
# connector's own chain runs up the middle of it. The worst of the four joins is
# 33 studs, against ROUTE_LINK's 70 -- so the estate has four independent ways in
# and not one. That is deliberate and it is measured: check 12 caught a
# one-connection district at 2.02x its straight line when the town's back street
# went in, against a 1.9 limit.
for _j, _c in enumerate(EST_CS):
    for _i, _x in enumerate(range(int(EST_CS_X0 + AVE_W_MAIN / 2), int(EST_CS_X1),
                                  ROUTE_STEP)):
        waypoint(f"wp_est_cs{_j}_{_i}", float(_x), _c + WCS_W / 2,
                 f"the estate's {['first', 'second', 'third', 'fourth'][_j]} street")

for _k, _a in enumerate(EST_AVE):
    for _i, _z in enumerate(range(int(EST_AVE_Z0 + WCS_W / 2), int(EST_AVE_Z1),
                                  ROUTE_STEP)):
        waypoint(f"wp_est_ave{_k}_{_i}", _a + AVE_W_MAIN / 2, float(_z),
                 f"the estate's {'east' if _k == 0 else 'west'} avenue")

# The farm track. Chained east to west, starting at the common's edge, so the
# first point lands 18 studs from the street chain it hands off to and the last
# lands 5 studs short of the gate -- if it were walked the other way the
# remainder would fall at the *east* end, which is the one end that has to be
# close to something. The green's spine has the same note on it for the same
# reason.
#
# A track with no chain on it is the defect this file has repaired three times
# now: Routes joins place points within 70 studs and knows nothing about what is
# under them, so the gate at the far end was a destination the game could see
# and no player could ever be routed to. check 4 said so the moment it existed
# -- one stranded point out of 778 -- which is the whole argument for the
# lattice being a gate rather than a habit.
for _i, _x in enumerate(range(int(EST_COMMON_X1), int(EST_TRACK_GATE_X), -ROUTE_STEP)):
    waypoint(f"wp_est_track_{_i}", float(_x), EST_TRACK_Z,
             "the farm track, west of the estate", GROUND)

# The green's paths. The spur's east end lands 21 studs from wp_ave0_6 and its
# west end 33 from the spawn, so the back gate is still the short way into the
# city -- and it is shorter than it was, because the street this replaced had to
# bend east twice to find a junction and the path does not.
waypoint("wp_green_gate", GREEN_X0 + 6.0, GREEN_PATH_Z,
         "the green, outside your back gate")
waypoint("wp_green_ave", GREEN_X1 - 2.0, GREEN_PATH_Z,
         "the green, at avenue 1")

# The spine, ending six studs inside each end so both points sit on path rather
# than on the mouth. The north one is what puts the connector back within reach
# of the spawn; the south one hands off to the works cross street. Spaced by
# division rather than by a fixed step so the two ends are always the ends --
# a fixed step leaves a remainder, and the remainder lands at the north end,
# which is the one end that has to be close to something.
_green_spine_x = GREEN_X0 + 12.0
_green_s, _green_n = GREEN_Z0 + 6.0, GREEN_Z1 - 6.0
_green_steps = math.ceil((_green_n - _green_s) / ROUTE_STEP)
for _i in range(_green_steps + 1):
    waypoint(f"wp_green_{_i}", _green_spine_x,
             _green_s + (_green_n - _green_s) * _i / _green_steps,
             "the green")

# The step-down band's mews. Two per column rather than one in the middle: a
# single point at the centre of a 102-stud band is 72 studs from the avenue
# lattice either side of it, which is past ROUTE_LINK, and a mews nothing can
# route into is a paved corridor with four trees in it that no player is ever
# sent down.
_mews_z = STEP_ROW_Z[1] - STEP_FRONT_DEPTH - STEP_MEWS_W / 2
for _b in range(5):
    for _i, _mx in enumerate((AVE[_b] + AVE_W[_b] + AVE_WALK + 20.0,
                              AVE[_b + 1] - AVE_WALK - 20.0)):
        waypoint(f"wp_step{_b}_{_i}", _mx, _mews_z,
                 "the step-down mews", GROUND)

# Two points in the middle of the district's open ground, because the works has
# something the rest of the city does not: blocks 240 studs deep with a yard in
# the back half and the only road at the front. The door of the ironworks is
# reachable and the far end of its yard is not, and a route that can only reach
# the doorway of a place the player is meant to walk around inside is the same
# defect the sports park had.
waypoint("wp_works_ironyard", WORKS_COL_X[0][0] + 150.0, WORKS_ROW_Z[1][0] + 108.0,
         "the ironworks yard", GROUND)
waypoint("wp_works_depotyard", WORKS_COL_X[1][0] + 90.0, WORKS_ROW_Z[0][0] + 30.0,
         "the container yard", GROUND)

# The Circle's own chain. Eight points on the pavement ring at the facet
# centres between the four junction mouths, so a walk round the Circle never
# steps into a carriageway, and four on the island's diagonal paths so the
# monument is somewhere you can be sent. Ring spacing is 2*66*sin(22.5) = 50.5
# studs and every link out to the grid was measured against ROUTE_LINK.
# Mid-pavement, *derived*. This was a hardcoded 66 with a comment quoting the
# kerb and walk radii it had been measured against, and the first time the ring
# was widened it silently became a radius out in the carriageway -- eight
# waypoints hanging over tarmac, which check 6 caught only because it tests for
# ground rather than for pavement. A number measured from two other numbers
# should be computed from them.
CIRCLE_WP_R = (CIRCLE_R_ROAD + KERB_WIDTH + CIRCLE_R_WALK) / 2
CIRCLE_ISLE_WP_R = 30.0   # on the diagonal paths, clear of the fountain wall.
for i in range(8):
    _phi = 22.5 + i * 45.0
    _wx, _wz = polar(CIRCLE_WP_R, _phi)
    waypoint(f"wp_circle_{i}", _wx, _wz, "the Circle, on the pavement", PAVING)
for i in range(4):
    _phi = 45.0 + i * 90.0
    _wx, _wz = polar(CIRCLE_ISLE_WP_R, _phi)
    waypoint(f"wp_circle_isle_{i}", _wx, _wz,
             "the Circle's island, by the monument", PAVING)

# Mall corridor waypoint (emitted above as a place point) plus the strip of
# green between avenue 6 and the water, which runs the whole east side.
#
# The column is at x 810, west of SHORE_X_BAY, so every one of these is on land
# in all four shore bands and none of them cares where the waterline is. The
# spurs east of it do care: there used to be three more, at (850,835), (850,909)
# and (870,735), laid to reach a sports park that stood out on the headland.
# Both the park and that stretch of headland are gone -- the fields went to the
# school and the land went under the bay -- and the three of them were left
# standing in open water, which is exactly what check 6 called them.
for z in (460, 528, 596, 664, 732, 800, 868, 936):
    waypoint(f"wp_park_{z:.0f}", 810.0, float(z), "the east green, by the avenue")
waypoint("wp_park_850_475", 850.0, 475.0, "the stadium's south lawn")

# City park edges, so the fountain chains to the avenue lattice.
waypoint("wp_cpark_w", 99.0, 740.0, "the park's west edge", GROUND)
waypoint("wp_cpark_e", 203.0, 740.0, "the park's east edge", GROUND)
waypoint("wp_cpark_s", 151.0, 672.0, "the park's south edge", GROUND)
waypoint("wp_cpark_n", 151.0, 792.0, "the park's north edge", GROUND)

# Financial district waypoint lattice: chained from the connector's east
# sidewalk (x = CONN_X1 + CONN_WALK = 48) down to the plaza, so the bank and
# towers are reachable from the connector without a 125-stud jump.
_fin_x = CONN_X1 + CONN_WALK + 1.0
for z in range(60, 200, ROUTE_STEP):
    waypoint(f"wp_fin_{z:.0f}", _fin_x, float(z), "the financial district plaza")
# On avenue 1's *east* pavement, which is the side the bank fronts. It used to
# sit at x 100, which was pavement when the avenue was 14 wide and is the middle
# of the carriageway now that it is 24. Derived from the avenue rather than
# typed, so the next widening moves it instead of stranding it.
waypoint("wp_fin_gap1", AVE[0] + AVE_W[0] + AVE_WALK / 2, 62.0,
         "the financial district, bank approach", PAVING)
waypoint("wp_fin_gap2", 200.0, 80.0, "the financial district, mid-plaza", PAVING)
waypoint("wp_fin_gap3", 250.0, 100.0, "the financial district, east plaza", PAVING)
waypoint("wp_fin_bank", 156.0, 62.0, "the grand bank entrance", PAVING)
waypoint("wp_fin_plaza", 300.0, 100.0, "the financial plaza, by the benches", PAVING)
waypoint("wp_fin_plaza_n", 300.0, 180.0, "the financial plaza, north", PAVING)

# Fade district waypoints: connect the financial district plaza to the
# residential grid via the mid-rise corridor.
# Only 234 and 470 survive of the old x=300 column. The Circus took the two
# blocks the other three stood in: z=302 is inside the middle south-west tower,
# z=370 is under the Circle's own pavement ring, and z=438 is inside the middle
# north-west tower. 470 is the replacement, north of the Circus and south of the
# north-west plaza, and it chains to cross street 3 at x=246 and x=314.
for z in (234, 470):
    waypoint(f"wp_fade_{z}", 300.0, float(z), "the fade offices, by the entrance")
_waypoint_fade_x = CONN_X1 + CONN_WALK + 1.0
for z in range(200, 500, ROUTE_STEP):
    waypoint(f"wp_fade_conn_{z:.0f}", _waypoint_fade_x, float(z), "the fade district, by the road")

# Office plaza waypoints. The three towers are place points and chain to each
# other and to the avenues on their own, but the plaza behind them -- fountain,
# benches, trees -- is the half of the block a walker would actually be sent to
# and has nothing in it the router can see. Read off ROLES rather than typed as
# coordinates so they follow the role if the block ever moves, which is the
# mistake the wp_fade_* column made and had to be repaired for.
for _sband in range(5):
    for _band in range(5):
        if ROLES[_sband][_band] != "OFFICES":
            continue
        _ox0, _ox1, _oz0, _oz1 = block_bounds(_band, _sband)
        _ocx = (_ox0 + _ox1) / 2
        _plaza_z0 = _oz0 + OFFICE_ROW_DEPTH + OFFICE_PLAZA_GAP
        for _k, _oz in enumerate((_plaza_z0 + 14.0, _oz1 - 10.0)):
            waypoint(f"wp_office_{_band}_{_sband}_{_k}", _ocx, _oz,
                     "the office plaza", GROUND)

# Bayfront waypoints.
#
# The grid's own lattice stops at the last avenue, so without these the whole
# east side is a place you can see and not walk to -- which is what check_city
# said the first time this was built, in as many words: "marina has neighbour
# within 70.0 -- nearest too far". Three chains and two crossings:
#
#   * one chain down the middle of the walk in each shore band, at that band's
#     own x, because the shore steps out around the sports park and a single
#     straight chain would run through the headland;
#   * a link at each cross street's east end, from the avenue-6 junction across
#     to the walk, so every east-west street reaches the water;
#   * two crossings of the headland, south and north of the sports park, to
#     join the three chains into one.
#
# The works band gets the same chain on its wharf apron -- same width of paving,
# same job -- but measured from the *back* of the apron rather than the middle of
# a walk, because the front half of a wharf is where the cranes and the stacks
# go and a waypoint there is a waypoint inside a container.
for _i, (_z0, _z1, _sx, _edge) in enumerate(SHORE):
    if _edge == "quay":
        _wx = _sx - WHARF_W + 8.0
        _label = "the works wharf"
    else:
        _wx = _sx - BEACH_W - BAYWALK_W / 2
        _label = "the baywalk"
    for _z in range(int(_z0) + 34, int(_z1), ROUTE_STEP):
        waypoint(f"wp_bay{_i}_{_z}", _wx, float(_z), _label, PAVING)

# East end of every cross street: the avenue-6 junction, which the cross-street
# chain already reaches from the west.
for _j, _c in enumerate(CS):
    waypoint(f"wp_bay_cs{_j}", AVE[5] + AVE_W[5] / 2, _c + CS_W[_j] / 2,
             f"cross street {_j + 1}, at the bay end", GROUND)

# Across the headland, clear of the stadium to the south and to the north,
# joining the southern and northern walks to the one behind it.
# Both crossings are measured off the headland's own ends rather than typed, so
# that shortening the peninsula moves them with it instead of leaving one of
# them standing in the water it just made.
for _x in (824.0, 892.0, 960.0):
    waypoint(f"wp_bay_head_s_{_x:.0f}", _x, HEADLAND_Z0 + HEADLAND_CLEAR,
             "the headland, south of the stadium", GROUND)
    waypoint(f"wp_bay_head_n_{_x:.0f}", _x, HEADLAND_Z1 - HEADLAND_CLEAR,
             "the headland, north of the stadium", GROUND)

# The school's playing fields, out on the west side of the town. Three chains,
# all on the paving laid for them: the spine in from the town's way, the cross
# path south past the courts, and the south walk west to the track.
#
# The east end of the spine is the only cross-asset link in the set. It sits a
# short step from `wp_fields_way_1`, which gen_town.py lays at TOWN_WEST_EDGE +
# 6 on the same FIELDS_WAY_MID: the town checks its own half of that walk and
# this file checks its own, and check_city's reachability sweep -- which reads
# both files -- is the only thing that sees the join. That is the same
# arrangement the gate roads use.
for _i, _x in enumerate((-320.0, -380.0, -440.0, -500.0, -548.0)):
    waypoint(f"wp_fields_spine_{_i}", _x, FIELDS_WAY_MID,
             "the walk through the school's playing fields", PAVING)
for _i, _z in enumerate((40.0, 0.0, -40.0, -80.0)):
    waypoint(f"wp_fields_cross_{_i}", FIELDS_CROSS_MID, _z,
             "the path past the school's courts", PAVING)
for _i, _x in enumerate((-400.0, -460.0, -520.0)):
    waypoint(f"wp_fields_south_{_i}", _x, FIELDS_SOUTH_MID,
             "the walk along the foot of the playing fields", PAVING)
waypoint("wp_fields_corner", FIELDS_CROSS_MID, FIELDS_SOUTH_MID,
         "the corner of the playing fields", PAVING)

# The south pier, out to the marina. The deck ends at the shore plus the pier's
# own length, so the last of these has to sit inside it -- a waypoint past the
# end is a point over open water, which check_city calls a floating point.
for _i, _x in enumerate((872.0, 914.0, 946.0)):
    waypoint(f"wp_pier_{_i}", _x, 150.0, "the south pier", PAVING)

# The civic precinct: two east-west chains, one on each walk, joined by the
# three passages through the civic row.
#
# The precinct has no roads in it, so it has no road lattice to borrow -- and
# until the avenues were pulled back it was borrowing exactly that, chaining the
# north shops to the rest of the city along six roads that were driving through
# the buildings. These are the walks the precinct was designed around.
_forecourt_z = PRECINCT_Z0 + 10.0
_promenade_z = (CIVIC_Z1 + NORTH_Z0) / 2
# Bounded by the precinct's *inner* edge, not PRECINCT_X1. The precinct now
# ends in a carriageway, and this loop laid two waypoints per 64 studs right up
# to 793 -- so the moment the avenue went in, wp_forecourt_11 and
# wp_promenade_11 were standing at x=776 in the middle of it. check_city's
# "ground under place points" named both. Third time this exact class of bug has
# shown up in this file; see MAP_PLAN.md.
for _i, _x in enumerate(range(int(PRECINCT_X0) + 30, int(PRECINCT_INNER_X1), 64)):
    waypoint(f"wp_forecourt_{_i}", float(_x), _forecourt_z,
             "the civic forecourt", PAVING)
    waypoint(f"wp_promenade_{_i}", float(_x), _promenade_z,
             "the promenade behind the civic row", PAVING)
for _i, (_px0, _px1) in enumerate(CIVIC_PASSAGES):
    waypoint(f"wp_civic_passage_{_i}", (_px0 + _px1) / 2, (CIVIC_Z0 + CIVIC_Z1) / 2,
             "a passage through the civic row", PAVING)

# The precinct loop's own chains, one on each of the two new pavements.
#
# The roads went in before these did, and that order is wrong round if anything
# is ever going to front them: a building on the north service road is 68 studs
# from wp_promenade before you count a single stud of x offset, and ROUTE_LINK is
# 70. The road exists, so the walk exists, so the lattice has to exist -- or the
# north strip can be turned to face the road and immediately fail check 4.
#
# Both x and z are derived from the road constants rather than typed, for the
# reason the comment above wp_forecourt gives at length.
_precinct_ave_walk_x = PRECINCT_INNER_X1 + AVE_WALK / 2
for _i, _z in enumerate(range(int(CS[CS_LAST] + CS_W[CS_LAST]) + 4,
                             int(NORTH_ROAD_Z0), 64)):
    waypoint(f"wp_precinct_ave_{_i}", _precinct_ave_walk_x, float(_z),
             "the precinct avenue's west pavement", PAVING)

_north_svc_walk_z = NORTH_ROAD_Z0 - CS_WALK / 2
for _i, _x in enumerate(range(int(CONN_X1) + 6, int(PRECINCT_INNER_X1), 64)):
    waypoint(f"wp_north_svc_{_i}", float(_x), _north_svc_walk_z,
             "the north service road's south pavement", PAVING)

for pid, x, z, floor, label in WAYPOINTS:
    place_point(pid, x, z, floor, label)

with group("PlacePoints"):
    for pid, x, z, floor, label in PLACE_POINTS:
        box(f"Place_{pid}", (x - 0.5, x + 0.5, z - 0.5, z + 0.5, floor, floor + 1.0),
            (255, 255, 255), SMOOTH, transparency=1.0, collide=False,
            tags=[PLACE_TAG],
            attrs={PLACE_ID_ATTRIBUTE: pid, PLACE_LABEL_ATTRIBUTE: label})

print(rbxmx.write(CITY, "City"))
