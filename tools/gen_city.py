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
  * a sports park with a soccer pitch, basketball, tennis, playground and
    running track;
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
    GRASS, LEAFY_GRASS, MARBLE, METAL, NEON, PAVEMENT, PEBBLE, PLASTIC,
    PLANKS, SLATE, SMOOTH, WOOD,
)
from rbxmx import at, box, group, part, point_light, sign

from world_plan import (
    CEIL_1, CEIL_2, DOORWAY, FLOOR_1, FLOOR_2, GROUND, KERB, PAVING,
    PLACE_ID_ATTRIBUTE, PLACE_LABEL_ATTRIBUTE, PLACE_TAG, SLAB, STOREY, WALL,
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
    # The south edge of the world. Transcribed over there, asserted here.
    MAP_SOUTH_EDGE,
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
# The city's own grass sits two hundredths under the town's ground so that
# roads laid on top (top GROUND) never share a plane with the grass underneath
# them and z-fight. The seam where the city meets the town is a hairline.
CITY_GRASS_TOP = GROUND - 0.02
# The same hairline, the other way up, for the one road this file draws over
# ground the *town* generator laid. The town's lawns top at GROUND exactly, so a
# city road at GROUND is coplanar with them; this puts it a fiftieth clear. Too
# small to be a step a player can feel, big enough that the depth buffer has an
# opinion. Safe range: 0.01 .. 0.05 -- below 0.01 the flicker comes back at
# distance, above 0.05 the lip starts to catch the eye at a kerb.
GRASS_LIFT = 0.02

# ---------------------------------------------------------------------------
# The plan
# ---------------------------------------------------------------------------

# City region: east of the town's grass (x 8), north of the town's east margin
# (z 60), inside the enlarged 2048 baseplate (x/z +/- 1024). The connector's
# south end and the bridge waypoints land in the grass south of z 80.
CITY_X0, CITY_X1 = 8.0, 1024.0
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
# 1117.2, which clears the north strip's back wall at 1116 by 1.2 studs -- the
# strip is not moved and its buildings are not resized.
NORTH_ROAD_Z0 = 1124.0
NORTH_ROAD_Z1 = NORTH_ROAD_Z0 + WCS_W

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

    All six carry into the step-down band -- it is city rather than works, and
    it is laid out in the financial district's five bands because of it, so the
    offices in it line up with the towers above them. Three of the six -- 1, 4
    and 6 -- carry on past it into the works and stop at its south street.

    Everything that draws an avenue (the carriageway, the pavements, the centre
    line, the waypoint chain and surface_floor) and everything that asks which
    avenues cross a street has to agree about this, so it is one function and
    not seven copies of the same conditional."""
    return SOUTH_CS[0] if k in WORKS_AVE else SOUTH_CS[2]


def cs_aves(c):
    """The avenues that cross south street `c`: an avenue crosses it if it runs
    at least that far south."""
    return [k for k in range(len(AVE)) if ave_z0(k) <= c]


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
GREEN_Z0 = SOUTH_CS[2]
GREEN_Z1 = SOUTH_CS[3] + WCS_W
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
# the pixel and the road flickers. Alternate facets therefore finish a hundredth
# of a stud lower. That is a step no player can feel and a difference the depth
# buffer can decide on. Safe range: 0.005 .. 0.03.
CIRCLE_SEAM = 0.01
# ...and the whole ring sits a hundredth under GROUND for the same reason at the
# four mouths, where the spoke roads run over it. The spoke wins, which is right:
# a junction should look like the straight road continuing into the circle.
CIRCLE_SINK = 0.005

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
#
# The waterline in the two straight bands and at the headland. Named rather than
# repeated, because the marina and the works wharf are both built off "the shore
# in the southern bay" and both used to find it by indexing SHORE -- which is a
# reference that silently means a different band the moment a band is inserted,
# and one was.
SHORE_X_BAY = 845.0
SHORE_X_HEADLAND = 995.0

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
    (WORKS_Z1, 400.0, SHORE_X_BAY, "beach"),
    (400.0, 940.0, SHORE_X_HEADLAND, "beach"),
    (940.0, CITY_Z1, SHORE_X_BAY, "beach"),
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

# The tag the game reads to find an interactive sports piece.
SPORT_TAG = "AgesSportFacility"
SPORT_KIND = "FacilityKind"
CAR_TAG = "AgesCarDisplay"
CAR_MODEL_ATTR = "CarModel"

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

# Deco neon. Used as thin bands on parapets and under signs, never as a wall:
# neon is a line in this palette, and a neon surface is a mistake.
NEON_PINK = (255, 108, 176)
NEON_CYAN = (96, 236, 244)
NEON_LIME = (176, 244, 120)
NEON_AMBER = (255, 186, 88)

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

with group("Streets"):
    # The connector, uncarved -- it is the through route and nothing crosses it.
    # Its west verge runs the full length; its east verge is carved at the cross
    # streets, which now run right up to its kerb and T into it.
    road_ns(CONN_X0, CONN_X1, CONN_Z0, CONN_Z1, "Conn")
    # The west verge is carved at the gate road for the same reason the east one
    # is carved at the cross streets: a pavement drawn straight across the mouth
    # of a side road is a kerb the road runs under, not a junction.
    for za, zb in carve((CONN_Z0, CONN_Z1), GATE_FULL):
        walks_ns(CONN_X0, CONN_X1, za, zb, CONN_WALK, "Conn", sides="west")
    for za, zb in carve((CONN_Z0, CONN_Z1), CS_FULL):
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
                            CS_ROAD + WCS_ROAD + (CIRCLE_Z_ROAD if at_circle else [])):
            road_ns(a, a + AVE_W[k], za, zb, f"Ave{k}")
        for za, zb in carve((ave_z0(k), AVE_Z1),
                            CS_FULL + WCS_FULL + (CIRCLE_Z_WALK if at_circle else [])):
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
    walks_ns(PRECINCT_AVE_X0, PRECINCT_AVE_X1, CS[CS_LAST] + CS_W[CS_LAST], NORTH_ROAD_Z0,
             AVE_WALK, "PrecinctAve", sides="west")
    # From the connector's east kerb, not from its centre: the connector is
    # already tarmac at x 19..42, and starting this one inside it would lay two
    # carriageways in the same place. It stops at the avenue's east edge so the
    # corner is one junction rather than a road running past its own end.
    road_ew(NORTH_ROAD_Z0, NORTH_ROAD_Z1, CONN_X1, PRECINCT_AVE_X1, "NorthSvc")
    walks_ew(NORTH_ROAD_Z0, NORTH_ROAD_Z1, CONN_X1, PRECINCT_AVE_X1, CS_WALK,
             "NorthSvc", sides="south")

    # Centre lines.
    dashes_ns(CONN_MID, CONN_Z0, CONN_Z1, [], "Conn")
    dashes_ns(PRECINCT_AVE_X0 + AVE_W[5] / 2, CS[CS_LAST] + CS_W[CS_LAST], NORTH_ROAD_Z0,
              [], "PrecinctAve")
    dashes_ew(NORTH_ROAD_Z0 + WCS_W / 2, CONN_X1, PRECINCT_AVE_X1, [], "NorthSvc")
    for k, a in enumerate(AVE):
        dashes_ns(a + AVE_W[k] / 2, ave_z0(k), AVE_Z1,
                  CS_ROAD + WCS_ROAD + (CIRCLE_Z_WALK if k == CIRCLE_AVE else []),
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
                (_mx + _tan[0] * _off, (PAINT_BOTTOM + PAINT_TOP) / 2,
                 _mz + _tan[1] * _off),
                (CIRCLE_ROAD_W - 2.0, PAINT_TOP - PAINT_BOTTOM, 2.4),
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
# The four deco neons, cycled up the shaft. They were declared with the palette
# and never used by anything, which is the one thing this file is not allowed to
# leave lying around; a lit monument is what they were declared for.
MONUMENT_NEONS = [NEON_CYAN, NEON_PINK, NEON_AMBER, NEON_LIME]

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
            MONUMENT_NEONS[_s % len(MONUMENT_NEONS)], NEON, collide=False)
        _y += MONUMENT_STAGE_H
    box("MonumentFinial",
        (CIRCLE_X - 1.4, CIRCLE_X + 1.4, CIRCLE_Z - 1.4, CIRCLE_Z + 1.4,
         _y, _y + 6.0), CITY_HALL_MARBLE, MARBLE)
    box("MonumentLight",
        (CIRCLE_X - 2.2, CIRCLE_X + 2.2, CIRCLE_Z - 2.2, CIRCLE_Z + 2.2,
         _y + 6.0, _y + 10.4), NEON_AMBER, NEON, collide=False,
        children=point_light(NEON_AMBER, 3.0, 90.0))

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
#   sband3       (z 650..800):   PARK   HOUSE  HOUSE  HOUSE HOUSE
#   sband2       (z 500..650):   MALL   APT    OFFICE HOUSE GREEN
#   sband1       (z 350..500):   FADE   CIRCUS CIRCUS FADE  APT
#   sband0 (south, z 200..350):  DINING CIRCUS CIRCUS FADE  FADE
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
#     city. It took the APT block rather than the GREEN one because there were
#     three APT blocks and only ever one GREEN, and orphaning `greenfield` to
#     un-orphan `office_block` would have been a trade for nothing.
ROLES = [
    ["DINING", "CIRCUS", "CIRCUS", "FADE", "FADE"],
    ["FADE", "CIRCUS", "CIRCUS", "FADE", "APT"],
    ["MALL", "APT", "OFFICES", "HOUSE", "GREEN"],
    ["PARK", "HOUSE", "HOUSE", "HOUSE", "HOUSE"],
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
        box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1), FLOOR_INDOOR, MARBLE)
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

        box("Counter", (cx - 6.0, cx + 6.0, iz0 + 2.0, iz0 + 5.0,
                        FLOOR_1, FLOOR_1 + 3.0), DESK_TOP, WOOD)
        box("Gondola", (ix0 + 3.0, ix0 + 6.0, iz0 + 8.0, iz1 - 4.0,
                        FLOOR_1, FLOOR_1 + 7.5), SHELF, METAL)
        box("Stock", (ix0 + 3.2, ix0 + 5.8, iz0 + 8.4, iz1 - 4.4,
                      FLOOR_1 + 1.8, FLOOR_1 + 3.4), STOCK, PLANKS, collide=False)
        box("Sign", (cx - 8.0, cx + 8.0, iz0 + 0.4, iz0 + 1.4,
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

    north_shops = [
        ("mall_jewelry", "AURUM JEWELERS"),
        ("mall_shoes", "STEPPER SHOES"),
        ("mall_sports", "SPORTZONE"),
        ("mall_gaming", "PIXEL PLAY"),
    ]
    south_shops = [
        ("optometrist", "SIGHT & SOUND"),
        ("pet_shop", "TREATS & TAILS"),
        ("mall_kids", "KIDDIE KORNER"),
        ("mall_foodcourt", "THE FOODCOURT"),
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
                         FLOOR_1 - 0.2, FLOOR_1), PATH_STONE, MARBLE)

        for i, (pid, label) in enumerate(north_shops):
            sx0 = cx0 + i * 24.0
            mall_shop(pid, label, sx0, sx0 + 22.0, corr_z1, z1 - WALL, "south", "shop")
            place_point(pid, sx0 + 11.0, corr_z1 + 6.0, FLOOR_1,
                        f"the {label.lower()}, at the counter")
        for i, (pid, label) in enumerate(south_shops):
            sx0 = cx0 + i * 24.0
            mall_shop(pid, label, sx0, sx0 + 22.0, z0 + WALL, corr_z0, "north", "shop")
            place_point(pid, sx0 + 11.0, corr_z0 - 6.0, FLOOR_1,
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
        box("Park", (x0, x1, z0, z1, GROUND_BOTTOM, CITY_GRASS_TOP), LAWN, GRASS)
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


def high_rise(no, x0, x1, z0, z1, storeys, glass_color):
    """A varied-height skyscraper with a stepped setback roof and ground-floor
    lobby. `storeys` is the number of 15-stud floors; lobby is extra 3 studs."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    cx = (x0 + x1) / 2
    cz = (z0 + z1) / 2
    # Each storey is STOREY tall with a SLAB on top; the lobby is slightly taller.
    lobby_h = 18.0
    tower_top = FLOOR_1 + lobby_h + (storeys - 1) * (STOREY + SLAB)

    with group(f"HighRise_{no}"):
        box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1), FLOOR_INDOOR, MARBLE)
        # Main tower body, setback a few studs at the top.
        box("Tower", (x0 + 3.0, x1 - 3.0, z0 + 3.0, z1 - 3.0,
                      FLOOR_1 + lobby_h, tower_top),
            glass_color, GLASS, transparency=0.45, collide=False)
        # Roof slab and setback.
        box("Roof", (x0 + 3.0, x1 - 3.0, z0 + 3.0, z1 - 3.0,
                     tower_top, tower_top + SLAB),
            (72, 76, 82), CONCRETE)
        box("Setback", (x0 + 6.0, x1 - 6.0, z0 + 6.0, z1 - 6.0,
                        tower_top + SLAB, tower_top + SLAB + STOREY * 0.6),
            glass_color, GLASS, transparency=0.45, collide=False)
        box("SetRoof", (x0 + 6.0, x1 - 6.0, z0 + 6.0, z1 - 6.0,
                        tower_top + SLAB + STOREY * 0.6,
                        tower_top + SLAB + STOREY * 0.6 + SLAB),
            (72, 76, 82), CONCRETE)
        # Antenna mast on the highest.
        if storeys >= 9:
            box("Mast", (cx - 0.6, cx + 0.6, cz - 0.6, cz + 0.6,
                          tower_top + SLAB + STOREY * 0.6, tower_top + 18.0),
                (80, 84, 90), METAL)
            box("MastLight", (cx - 1.0, cx + 1.0, cz - 1.0, cz + 1.0,
                              tower_top + 16.0, tower_top + 17.0),
                (240, 60, 40), NEON, collide=False)

        # Lobby interior (ground floor, fronting south).
        wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, FLOOR_1 + lobby_h),
             RISE_MARBLE, along="x")
        wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, FLOOR_1 + lobby_h),
             RISE_MARBLE, along="z")
        wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, FLOOR_1 + lobby_h),
             RISE_MARBLE, along="z")
        door_z0, door_z1 = cx - DOORWAY / 2, cx + DOORWAY / 2
        wall("WallFront", (x0, x1, z0, iz0, FLOOR_1, FLOOR_1 + lobby_h),
             RISE_MARBLE, along="x", doors=((door_z0, door_z1),))
        glazing("LobbyWin", (x0 + 1.5, x1 - 1.5, iz0 + 0.4, z1 - 0.4,
                             FLOOR_1 + 1.5, FLOOR_1 + lobby_h - 1.0),
                along="x", panes=4)
        box("Reception", (ix0 + 4.0, ix0 + 10.0, iz1 - 6.0, iz1 - 2.0,
                          FLOOR_1, FLOOR_1 + 3.0), DESK_TOP, WOOD)
        box("Sofa", (ix1 - 8.0, ix1 - 3.0, iz1 - 6.0, iz1 - 2.0,
                     FLOOR_1 + 1.2, FLOOR_1 + 2.0), (120, 140, 110), FABRIC)
        ceiling_light(cx, cz, FLOOR_1 + lobby_h - 0.5)
        box("Sign", (cx - 10.0, cx + 10.0, z0 - 1.6, z0 - 0.6,
                     FLOOR_1 + 13.0, FLOOR_1 + 15.0),
            RISE_FRAME, SMOOTH,
            children=sign(f"RISE {no}", "front", color=(250, 246, 234), size=60))

    place_point(f"rise_{no}", cx, z0 + 2.0, FLOOR_1,
                f"rise {no}, the lobby")


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
        box("Slab", (x0, x1, z0, z1, FLOOR_1 - SLAB, FLOOR_1), BANK_MARBLE, MARBLE)
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


def dining_block(band, sband, x0, x1, z0, z1):
    """Six restaurants along the south edge of the block, with a terrace of
    tables and trees behind them."""
    names = [
        ("dining_1", "EL SOL"), ("dining_2", "LA PLAYA"), ("dining_3", "BISTRO VERDE"),
        ("dining_4", "SAPORI"), ("dining_5", "THE GRILL"), ("dining_6", "CASA LINDA"),
    ]
    rw = (x1 - x0 - 8.0) / 6
    for i, (pid, label) in enumerate(names):
        rx0 = x0 + 4.0 + i * rw
        dining_restaurant(pid, label, rx0, rx0 + rw - 2.0, z0, z0 + 30.0)
    # Terrace: tables on the grass north of the restaurants.
    tz0 = z0 + 34.0
    for i in range(4):
        for j in range(3):
            tx = x0 + 10.0 + i * 26.0
            tz = tz0 + 8.0 + j * 14.0
            desk(tx, tz, GROUND, side="north", width=4.0, depth=2.2, label="Table")
            chair(tx - 2.6, tz, GROUND, side="south")
            chair(tx + 2.6, tz, GROUND, side="south")
    for tx in (x0 + 6.0, x1 - 6.0, (x0 + x1) / 2):
        tree(tx, z1 - 4.0, GROUND, height=12.0, spread=8.0)


# ---------------------------------------------------------------------------
# Greenfield
# ---------------------------------------------------------------------------


def greenfield(band, sband, x0, x1, z0, z1, index):
    """An empty block: grass, a path, a few trees. Land the city has not got
    to yet, and a future building's site."""
    with group(f"Greenfield_{index}"):
        box("Field", (x0, x1, z0, z1, GROUND_BOTTOM, CITY_GRASS_TOP), LAWN, GRASS)
        box("FieldPath", (x0 + 14.0, x1 - 14.0, (z0 + z1) / 2 - 1.5,
                          (z0 + z1) / 2 + 1.5, GROUND_BOTTOM, GROUND),
            PATH_STONE, PEBBLE)
        for tx, tz in ((x0 + 8.0, z0 + 8.0), (x1 - 8.0, z0 + 8.0),
                       (x0 + 8.0, z1 - 8.0), (x1 - 8.0, z1 - 8.0),
                       ((x0 + x1) / 2, (z0 + z1) / 2)):
            tree(tx, tz, GROUND, height=13.0, spread=9.0)


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
SHOP_FRONTS = {
    # z 60..196 -- the eating end of the street. Three awnings in a row, which is
    # what makes it read as a restaurant strip rather than three more shops.
    "cafe": ("cafe", 28.0, 2, AWNING_RED, "full"),
    "restaurant": ("restaurant", 30.0, 2, AWNING_GREEN, "full"),
    "pizzeria": ("pizzeria", 28.0, 1, AWNING_MUSTARD, "full"),
    "supermarket": ("market", 30.0, 1, None, "full"),
    # z 218..346
    "pharmacy": ("counter", 34.0, 2, AWNING_BLUE, "full"),
    "florist": ("market", 28.0, 1, AWNING_GREEN, "full"),
    "bookstore": ("shelves", 32.0, 2, None, "high"),
    # z 368..496
    "electronics": ("shelves", 36.0, 2, None, "full"),
    "hardware": ("workshop", 34.0, 1, None, "high"),
    "toy_store": ("shelves", 28.0, 1, AWNING_MUSTARD, "full"),
    # z 518..646
    "clothing_store": ("racks", 38.0, 2, None, "full"),
    "music_store": ("racks", 28.0, 1, None, "narrow"),
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


# The street, band by band. Widths, rooflines, awnings and glass all live in
# SHOP_FRONTS -- this is only which shops stand where, in order along z.
MAIN_STREET = [
    (60.0, 196.0, [
        ("cafe", "CAFE ASTER"),
        ("restaurant", "TORRE RESTAURANT"),
        ("pizzeria", "VESUVIO PIZZERIA"),
        ("supermarket", "MIDWAY MARKET"),
    ]),
    (218.0, 346.0, [
        ("pharmacy", "FIRST PHARMACY"),
        ("florist", "STEM & BLOOM"),
        ("bookstore", "PAGES & PRESS"),
    ]),
    (368.0, 496.0, [
        ("electronics", "VOLT ELECTRONICS"),
        ("hardware", "IRON & WOOD"),
        ("toy_store", "PLAYPEN"),
    ]),
    (518.0, 646.0, [
        ("clothing_store", "THREAD & CO"),
        ("music_store", "FREQUENCY"),
        ("laundromat", "CLEAN SPIN"),
    ]),
    (668.0, 796.0, [
        ("barbershop", "THE CLIPPERS"),
        ("salon", "LUMIERE SALON"),
        ("tattoo_parlor", "INKWELL TATTOO"),
    ]),
    # 826, not 818. The band used to claim eight studs of the cross street's own
    # north pavement, which ends at 826.0 -- it was only ever safe because three
    # equal 30-stud shops left a 9.5-stud gap that pushed the first one clear by
    # a stud and a half. Widen any shop here and the vet walks into the kerb,
    # which is what happened the moment this table gained widths, and which
    # check_city's "no street runs through a building" reported by name.
    (826.0, 946.0, [
        ("vet", "ANIMAL CLINIC"),
        ("gas_station", "TANK & GO"),
        ("car_wash", "WASH & GLIDE"),
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


def place_main_street():
    colour = 0
    for (z0, z1, stores) in MAIN_STREET:
        n = len(stores)
        widths = [shop_front(pid)[1] for pid, _ in stores]
        gap = (z1 - z0 - sum(widths)) / (n + 1)
        # Checked rather than trusted. The bands are fixed by the cross streets
        # either side of them, so a width raised by four studs comes straight
        # out of the gaps -- and the first shop to overrun would do it silently,
        # by growing into its neighbour's wall.
        if gap < MIN_SHOP_GAP:
            raise ValueError(
                f"main street band z {z0}..{z1} is over-subscribed: "
                f"{n} shops totalling {sum(widths)} studs leave a {gap:.1f}-stud gap, "
                f"under the {MIN_SHOP_GAP} minimum. Narrow one of "
                f"{[pid for pid, _ in stores]} in SHOP_FRONTS."
            )
        cursor = z0 + gap
        for i, (pid, label) in enumerate(stores):
            trade, width, storeys, awning, glass = shop_front(pid)
            sz0 = cursor
            sz1 = sz0 + width
            cursor = sz1 + gap
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
            box("Slab", (show_x0, show_x1, show_z0, show_z1,
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
            box("Slab", (x0, x1, svc_z0, svc_z1, FLOOR_1 - SLAB, FLOOR_1),
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


def fade_office(no, x0, x1, z0, z1, storeys, name="FadeOffice"):
    """A mid-rise office block: flat roof, glass curtain wall, ground-floor
    lobby. `storeys` is the number of 15-stud floors above the lobby."""
    ix0, ix1 = x0 + WALL, x1 - WALL
    iz0, iz1 = z0 + WALL, z1 - WALL
    cx = (x0 + x1) / 2
    cz = (z0 + z1) / 2
    lobby_h = 18.0
    tower_top = FLOOR_1 + lobby_h + (storeys - 1) * (FADE_STOREY + FADE_SLAB)

    with group(f"{name}_{no}"):
        box("Slab", (x0, x1, z0, z1, FLOOR_1 - FADE_SLAB, FLOOR_1),
            FLOOR_INDOOR, MARBLE)
        # Glass tower body.
        box("Tower", (x0 + 2.0, x1 - 2.0, z0 + 2.0, z1 - 2.0,
                      FLOOR_1 + lobby_h, tower_top),
            (140, 170, 195), GLASS, transparency=0.5, collide=False)
        # Flat roof slab.
        box("Roof", (x0 + 2.0, x1 - 2.0, z0 + 2.0, z1 - 2.0,
                     tower_top, tower_top + FADE_SLAB),
            (72, 76, 82), CONCRETE)
        # Small parapet.
        box("Parapet", (x0 + 1.0, x1 - 1.0, z0 + 1.0, z1 - 1.0,
                        tower_top + FADE_SLAB, tower_top + FADE_SLAB + 2.0),
            (90, 94, 100), CONCRETE)
        # Lobby walls.
        wall("WallNorth", (x0, x1, iz1, z1, FLOOR_1, FLOOR_1 + lobby_h),
             RISE_MARBLE, along="x")
        wall("WallWest", (x0, ix0, z0, z1, FLOOR_1, FLOOR_1 + lobby_h),
             RISE_MARBLE, along="z")
        wall("WallEast", (ix1, x1, z0, z1, FLOOR_1, FLOOR_1 + lobby_h),
             RISE_MARBLE, along="z")
        door_z0, door_z1 = cx - DOORWAY / 2, cx + DOORWAY / 2
        wall("WallSouth", (x0, x1, z0, iz0, FLOOR_1, FLOOR_1 + lobby_h),
             RISE_MARBLE, along="x", doors=((door_z0, door_z1),))
        glazing("LobbyWin", (x0 + 1.5, x1 - 1.5, iz0 + 0.4, z1 - 0.4,
                             FLOOR_1 + 1.5, FLOOR_1 + lobby_h - 1.0),
                along="x", panes=4)
        box("Reception", (ix0 + 4.0, ix0 + 10.0, iz1 - 6.0, iz1 - 2.0,
                          FLOOR_1, FLOOR_1 + 3.0), DESK_TOP, WOOD)
        box("Sofa", (ix1 - 8.0, ix1 - 3.0, iz1 - 6.0, iz1 - 2.0,
                     FLOOR_1 + 1.2, FLOOR_1 + 2.0), (120, 140, 110), FABRIC)
        ceiling_light(cx, cz, FLOOR_1 + lobby_h - 0.5)
        box("Sign", (cx - 8.0, cx + 8.0, z0 - 1.6, z0 - 0.6,
                     FLOOR_1 + 12.0, FLOOR_1 + 14.0),
            RISE_FRAME, SMOOTH,
            children=sign(f"FADE {no}", "front", color=(250, 246, 234), size=52))

    place_point(f"fade_{no}", cx, z0 + 2.0, FLOOR_1,
                f"fade {no}, the lobby")


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
        fade_office(counter, bx0, bx0 + bw, z0, z1, storeys, name="FadeOffice")
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
# The skyline now, from the middle outward:
#   231  the Circle's centre towers
#   213  the financial district's masts
#   150  the Circle's shoulder towers (8 storeys)
#   115  fade offices one ring out (7-8 storeys)
#    83  fade offices two rings out (5-6 storeys)
#    67  the office block
#    34  walk-ups and two-storey houses
#    17  single-storey houses at the edge
# Safe range for the middle: 12 .. 18. Below 12 the financial district takes the
# crown back; above 18 the tower reads as out of scale beside its own shoulders,
# which is why the shoulders went up to 8 at the same time.
CIRCUS_STOREYS = (8, 14, 8)
CIRCUS_LOBBY_H = 18.0
CIRCUS_STOREY = 15.0
CIRCUS_SLAB = 1.0
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
                  top + CIRCUS_SLAB, top + CIRCUS_SLAB + 3.0,
                  (90, 94, 100), CONCRETE)
        # The crown. A line of light round the parapet, which is the palette's
        # own rule for neon -- a band, never a surface -- and the thing that
        # makes the Circle read as downtown once the lighting goes warm.
        at_radius("Crown", mid, CIRCUS_DEPTH - 2.8, CIRCUS_WIDTH - 2.8,
                  top + CIRCUS_SLAB + 1.4, top + CIRCUS_SLAB + 2.6,
                  neon, NEON, collide=False,
                  children=point_light(neon, 2.2, 60.0))
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
    for i, storeys in enumerate(CIRCUS_STOREYS):
        circus_tower(counter + i, base + (i - 1) * CIRCUS_SPREAD, storeys,
                     RISE_GLASS[(counter + i) % len(RISE_GLASS)],
                     CIRCUS_STUCCO[(counter + i) % len(CIRCUS_STUCCO)],
                     MONUMENT_NEONS[(counter + i) % len(MONUMENT_NEONS)])

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
    return counter + len(CIRCUS_STOREYS)


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

# The north strip, west to east. One row per slot in the band:
#
#   (slot, id, sign, kind, front, storeys, awning, glass, weight)
#
# `slot` is what gets built -- a shop, a civic service, or a pocket park.
# `front` is which wall the door is in, and it is the whole point of this table
# now that the strip has a road on *both* sides of it. Until the precinct loop
# went in, the strip's north wall faced 400 studs of nothing and every door had
# to be on the promenade; now the service road runs along the top of it, so the
# three services that need a vehicle to reach them -- an engine bay, a police
# yard, a depot -- turn round and open onto the road, and the retail keeps its
# south front where the footfall is. That alternation is also what stops the row
# reading as one wall: a north-facing building shows the promenade its back and
# its roofline instead of another identical shopfront.
#
# `weight` is a *share* of the band, not a width in studs. Widths are solved
# from it below so the row always fills the band exactly however the band moves.
# Written as literal widths this table would have had to be re-added-up by hand
# the day the precinct avenue pulled CIVIC_X1 west, which is the same class of
# mistake as every other frozen number in this file.
NORTH_ROW = [
    ("shop",  "north_shop_1", "NORTH CAFÉ", "cafe", "south", 2, AWNING_RED, "full", 1.00),
    ("civic", "north_shop_2", "NORTH FIRE STATION", "fire", "north", 1, None, "none", 1.45),
    ("shop",  "north_shop_3", "NORTH PHARMACY", "counter", "south", 1, AWNING_BLUE, "full", 0.95),
    ("park",  "north_green_w", "Bell Green", None, None, 0, None, None, 0.95),
    ("civic", "north_shop_4", "NORTH POLICE POST", "police", "north", 2, None, "high", 1.25),
    ("shop",  "north_shop_5", "IRON & WOOD NORTH", "workshop", "south", 1, None, "high", 1.00),
    ("civic", "north_shop_6", "CITY DEPOT", "warehouse", "north", 1, None, "none", 1.25),
    ("park",  "north_green_e", "Foundry Green", None, None, 0, None, None, 0.80),
    ("shop",  "north_shop_7", "NORTH BAKERY", "cafe", "south", 2, AWNING_MUSTARD, "full", 0.95),
    ("shop",  "north_shop_8", "THE NORTH GRILL", "restaurant", "south", 1, None, "full", 0.95),
]


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


NORTH_SLOTS = solve_row(NORTH_X0, NORTH_X1, [row[8] for row in NORTH_ROW], NORTH_GAP)


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


def north_business_strip():
    """The north strip: shops facing the promenade, services facing the service
    road behind them, and two pocket parks cut through the row."""
    prom_z0, prom_z1 = CIVIC_Z1, NORTH_Z0
    # Each building is its own top-level model, deliberately not wrapped in one
    # "NorthStrip" group the way it used to be. check_city walks outermost
    # models: with the whole row inside one, the eight shops were a single
    # 668-stud box and check 5 could not see an overlap between two of them --
    # which matters a great deal more now that their widths are solved from
    # weights rather than being eight equal slices of the band.
    with group("NorthStripGround"):
        # The apron between the buildings' north walls and the service road's
        # pavement. Without it a north-facing door opens onto four studs of
        # grass and then a kerb, which reads as a building somebody forgot to
        # finish rather than as a yard.
        box("NorthApron", (NORTH_X0, PRECINCT_INNER_X1, NORTH_Z1,
                           NORTH_ROAD_Z0 - CS_WALK, GROUND_BOTTOM, PAVING - 0.02),
            PAVING_GREY, PAVEMENT)
        # Lamps and benches down the promenade, in front of the shops rather
        # than in them, and benches facing the shopfronts.
        for _sx0, _sx1 in NORTH_SLOTS[::3]:
            street_lamp((_sx0 + _sx1) / 2, prom_z0 + 5.0, 1, floor=PAVING)
        bench(NORTH_X0 + 8.0, prom_z1 - 6.0, -1)
        bench(NORTH_X1 - 8.0, prom_z1 - 6.0, -1)
    for i, row in enumerate(NORTH_ROW):
        slot, pid, label, kind, front, storeys, awning, glass, _w = row
        sx0, sx1 = NORTH_SLOTS[i]
        sz_cx = (sx0 + sx1) / 2
        if slot == "park":
            pocket_park(sx0, sx1, NORTH_Z0, NORTH_Z1, pid, label)
            continue
        wall_color = STORE_WALLS[i % len(STORE_WALLS)]
        # The door is in whichever wall faces a road, and the place point is
        # always two studs inside it -- so the spot the game puts a player
        # down on is the spot the door is, whichever way the building turned.
        door_z = NORTH_Z0 + 2.0 if front == "south" else NORTH_Z1 - 2.0
        ftype = "garage" if glass == "none" else "shop"
        with group(pid):
            storefront(label, sx0, sx1, NORTH_Z0, NORTH_Z1, sz_cx, wall_color,
                       front=front, front_type=ftype, storeys=storeys,
                       awning=awning, glass=glass,
                       bays=GARAGE_BAYS.get(kind, 1) if ftype == "garage" else 1)
            if slot == "civic":
                civic_fittings(kind, sx0, sx1, NORTH_Z0, NORTH_Z1, front=front)
            else:
                street_fittings(pid, sx0, sx1, NORTH_Z0, NORTH_Z1, front, kind)
        place_point(pid, sz_cx, door_z, FLOOR_1,
                    f"the {label.lower()}, by the door")
    palm_row(NORTH_X0, NORTH_X1, prom_z0 + 12.0, prom_z0 + 18.0, PAVING,
             step=64.0, along="x", label="NorthStripPalms")


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
north_business_strip()


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
        box("Center", ((x0 + x1) / 2 - 1.0, (x0 + x1) / 2 + 1.0, (z0 + z1) / 2 - 1.0,
                       (z0 + z1) / 2 + 1.0, PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        for dz, toward in ((z0, 1), (z1, -1)):
            box(f"Box{dz:.0f}", (x0 + 12.0, x1 - 12.0, dz, dz + toward * 4.0,
                                 PAINT_BOTTOM, PAINT_TOP), (240, 240, 240), SMOOTH)
        for gz in (z0, z1):
            with group(f"Goal{gz:.0f}"):
                box("Post", (x0 + 12.0, x0 + 12.8, gz - 2.4, gz, GROUND, GROUND + 8.0),
                    (240, 240, 240), METAL, tags=[SPORT_TAG], attrs={SPORT_KIND: "soccer"})
                box("Post2", (x1 - 12.8, x1 - 12.0, gz - 2.4, gz, GROUND, GROUND + 8.0),
                    (240, 240, 240), METAL, tags=[SPORT_TAG], attrs={SPORT_KIND: "soccer"})
                box("Bar", (x0 + 12.0, x1 - 12.0, gz - 2.4, gz - 1.8, GROUND + 7.6, GROUND + 8.2),
                    (240, 240, 240), METAL, tags=[SPORT_TAG], attrs={SPORT_KIND: "soccer"})


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


soccer_field(820.0, 890.0, 420.0, 530.0)
basketball_court(850.0, 882.0, 900.0, 918.0)
tennis_court(900.0, 928.0, 900.0, 914.0)
playground(830.0, 870.0, 820.0, 850.0)
running_track(840.0, 980.0, 700.0, 770.0)

for pid, cx, cz in (
    ("soccer_field", 855.0, 475.0),
    ("basketball_court", 866.0, 909.0),
    ("tennis_court", 914.0, 907.0),
    ("playground", 850.0, 835.0),
    ("running_track", 910.0, 735.0),
):
    place_point(pid, cx, cz, GROUND, f"the {pid.replace('_', ' ')}")


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
        elif role == "DINING":
            dining_block(band, sband, x0, x1, z0, z1)
        elif role == "GREEN":
            greenfield(band, sband, x0, x1, z0, z1, band * 5 + sband)
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
FIN_GLASS = RISE_GLASS


with group("FinancialDistrict"):
    # The grand bank in the first band.
    bank_x0 = AVE[0] + AVE_W[0] + AVE_WALK
    bank_x1 = AVE[1] - AVE_WALK
    grand_bank(bank_x0, bank_x1, FIN_Z0, FIN_Z1)

    # High-rises in the remaining four bands.
    for band in range(1, 5):
        bx0 = AVE[band] + AVE_W[band] + AVE_WALK
        bx1 = AVE[band + 1] - AVE_WALK
        # Two towers per band, split the width roughly in half with a plaza.
        mid_x = (bx0 + bx1) / 2
        tw = (bx1 - bx0) / 2 - 2.0
        h1 = FIN_HEIGHTS[band]
        h2 = FIN_HEIGHTS[band - 1] if band > 1 else FIN_HEIGHTS[0]
        high_rise(f"{band}_w", bx0, bx0 + tw, FIN_Z0, FIN_Z1,
                  h1, FIN_GLASS[band % len(FIN_GLASS)])
        high_rise(f"{band}_e", mid_x + 2.0, bx1, FIN_Z0, FIN_Z1,
                  h2, FIN_GLASS[(band + 2) % len(FIN_GLASS)])
    # Street furniture goes on the avenue pavements, not in the middle of the
    # band. There is no plaza here and there never was room for one: the bank
    # fills its band wall to wall and each of the other four is two towers with
    # two studs between them, so the "plaza" this used to draw was an inverted
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


def works_boundary(x0, x1, z0, z1):
    """The south apron: what the map does instead of stopping.

    A treeline and a boundary fence, because the alternative down here is the
    baseplate -- and an edge a player can see the far side of is an edge they
    walk to. Trees, so that the thing beyond the works reads as somewhere the
    city has not got to yet rather than as the end of the world."""
    with group("WorksBoundary"):
        box("Verge", (x0, x1, z0, z1, GROUND_BOTTOM, CITY_GRASS_TOP + GRASS_LIFT),
            PITCH_GREEN, GRASS)
    for i in range(int((x1 - x0) / 30.0)):
        tx = x0 + 15.0 + i * 30.0
        tree(tx, z0 + 12.0 + (i % 3) * 7.0, GROUND,
             height=17.0 + (i % 4) * 3.0, spread=12.0 + (i % 3) * 2.0,
             label=f"BoundaryTree{i}")


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
    palm_row(walk_x0 + 4.0, walk_x0 + 10.0, z0, z1, PAVING, step=38.0,
             along="z", label=f"BaywalkPalms{index}")
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
        box("Apron", (apron_x0, shore_x, z0, z1, GROUND_BOTTOM, PAVING),
            CONCRETE_GREY, CONCRETE)
        # The face itself, standing in the water so there is no seam at the
        # waterline where the seabed would otherwise show through.
        box("Face", (shore_x - 1.4, shore_x + 1.6, z0, z1, SEA_FLOOR - 1.0, PAVING),
            CONCRETE_GREY, CONCRETE)
        # A rubbing strake down the face, which is the one detail that stops it
        # reading as a plain wall from a boat's height.
        box("Fender", (shore_x + 1.6, shore_x + 2.4, z0, z1,
                       SEA_TOP - 0.6, SEA_TOP + 1.6), (56, 54, 52), SMOOTH)
        for i in range(int((z1 - z0) / 26.0)):
            bz = z0 + 13.0 + i * 26.0
            box(f"Bollard{i}", (shore_x - 4.4, shore_x - 1.8, bz - 1.3, bz + 1.3,
                                PAVING, PAVING + 2.6), (52, 52, 54), METAL)
            # A ladder every third bollard: the way back up for a player who
            # walks off the edge, which they will, and the shelf is only 2.6
            # studs down but a wall with no way out of the water is a trap.
            if i % 3 == 1:
                box(f"Ladder{i}", (shore_x + 1.6, shore_x + 2.2, bz + 4.0, bz + 5.4,
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
        if a < x < a + AVE_W[k] and ave_z0(k) < z < AVE_Z1:
            return GROUND
    for j, c in enumerate(CS):
        if c < z < c + CS_W[j] and CS_X0 < x < CS_X1:
            return GROUND
    for c in SOUTH_CS:
        if c < z < c + WCS_W and WORKS_X0 < x < WORKS_X1:
            return GROUND
    if CONN_X0 - CONN_WALK < x < CONN_X0 and CONN_Z0 < z < CONN_Z1:
        return PAVING
    if CONN_X1 < x < CONN_X1 + CONN_WALK and CONN_Z0 < z < CONN_Z1:
        return PAVING
    for k, a in enumerate(AVE):
        if a - AVE_WALK < x < a and ave_z0(k) < z < AVE_Z1:
            return PAVING
        if a + AVE_W[k] < x < a + AVE_W[k] + AVE_WALK and ave_z0(k) < z < AVE_Z1:
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
def in_circle(x, z):
    return math.hypot(x - CIRCLE_X, z - CIRCLE_Z) < CIRCLE_R_WALK


for k, a in enumerate(AVE):
    for i, z in enumerate(range(int(ave_z0(k)), int(AVE_Z1), ROUTE_STEP)):
        if in_circle(a + AVE_W[k] / 2, float(z)):
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

# Mall corridor waypoint (emitted above as a place point) plus the sports
# park's own lattice.
for z in (460, 528, 596, 664, 732, 800, 868, 936):
    waypoint(f"wp_park_{z:.0f}", 810.0, float(z), "the east park, by the avenue")
for x, z in ((850.0, 475.0), (850.0, 835.0), (850.0, 909.0), (870.0, 735.0)):
    waypoint(f"wp_park_{x:.0f}_{z:.0f}", x, z, "across the east park")

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

# Across the headland, clear of the pitch to the south and the courts to the
# north, joining the southern and northern walks to the one behind the park.
for _x in (824.0, 892.0, 960.0):
    waypoint(f"wp_bay_head_s_{_x:.0f}", _x, 408.0, "the headland, south of the park", GROUND)
    waypoint(f"wp_bay_head_n_{_x:.0f}", _x, 932.0, "the headland, north of the park", GROUND)

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
