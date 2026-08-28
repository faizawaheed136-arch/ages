#!/usr/bin/env python3
"""The plan of everything outside the house: the street, the school, the store.

house_plan.py is a transcription -- somebody measured an imported building and
wrote the numbers down. This file is the opposite: nothing out there exists yet,
so these numbers are the design, and build_street.py turns them into geometry
rather than being checked against it. That is why the two are separate files.
They are read the same way by read_house.py, which does not care which came
first.


Where the street is, and why
----------------------------
The house faces west. Its front door is a glazed opening in the west wall of the
hall, and the only clear line through it -- once the door leaf standing open at
z -4.4 and the jamb at z 0.4 are both accounted for -- runs down z = -2.0 with
2.26 studs of room on either side. Every measurement below is hung off that
line, because it is the one the player physically walks.

Note that this is *not* z -4.9, where the doormat, the phone and the doorstep
marker all sit. Those were placed against the hall's west wall by the room plan,
which knows where the wall is but not where the hole in it is. They work, because
everything they do happens inside the hall. A path laid on that line would not:
it would run into the door.

The plot's own ground ends at x -52.8, so the property line goes there and the
street beyond it is built on ground of its own. West to east across the corridor:
far sidewalk, road, near sidewalk, fence, garden, front door. A player leaving
home crosses one road, and both buildings are on the far side of it -- the school
to the north and the workplace to the south, so that stepping out of the gate
puts the whole of the rest of the world in view at once.


Heights
-------
Four of them, and they are the reason nothing here has a slope in it. The plot
sits at y 1.04; the street's own ground is laid at 1.02, two hundredths under it,
so the seam where they meet can never z-fight and the player never feels the
step. Paving is half a stud up, which is a kerb. Building floors are the same
height as the paving, so walking indoors is walking, not climbing.
"""

from house_plan import Room, _ASSETS

STREET = _ASSETS / "Street.rbxmx"


class Place(Room):
    """A room, or an outdoor area treated as one.

    Room already carries walls, a floor and a ceiling and knows how to give a
    pivot for something standing against one of its sides, which is the whole of
    what a builder needs. An outdoor area has no ceiling; it gets a nominal one
    high enough that `contains` never rejects anything for being too tall, since
    outdoors the sky is not a constraint.
    """

    def __init__(self, name, x0, x1, z0, z1, floor, ceiling, indoors=True):
        super().__init__(name, x0, x1, z0, z1, floor, ceiling)
        self.indoors = indoors


# ---------------------------------------------------------------------------
# Heights
# ---------------------------------------------------------------------------

# The street's own ground plane. Two hundredths below the plot's 1.04 so the two
# never draw over each other where they overlap. Safe range: anything from 0.5 to
# 1.03 works; above 1.03 the seam flickers.
GROUND = 1.02
# Kerb height, and so the height of every sidewalk, forecourt and ground floor.
# Half a stud is a kerb you can see and step over without the character animating
# a climb. Safe range 0.3-1.0.
KERB = 0.5
PAVING = GROUND + KERB
# The front path across the garden. The plot has a raised apron at 1.20 up
# against the house and lawn at 1.04 beyond it, so a path laid at 1.22 is flush
# where it leaves the door and a hand's breadth proud where it crosses the grass,
# which is what a path looks like.
PATH_TOP = 1.22

# Floor to ceiling inside both buildings, and how thick a floor slab is. Matched
# to the house, whose storeys are 1.04 and 17.36 -- so a building here reads as
# the same size of world rather than as a different game's scenery.
STOREY = 15.0
SLAB = 1.0
# Exterior wall thickness, and internal partition thickness.
WALL = 1.5
PARTITION = 1.0

# ---------------------------------------------------------------------------
# The street corridor, running north-south
# ---------------------------------------------------------------------------

# How far the street runs before it stops. Nothing is authored past this and the
# player is not stopped from walking off the end -- the baseplate goes on to 256.
# Long enough that neither end is visible from the crossing, which is all a street
# has to do to read as a street rather than as a diorama.
STREET_Z0, STREET_Z1 = -132.0, 132.0

# The property line. The plot's own ground ends at x -52.8; the near sidewalk laps
# a fifth of a stud under it so there is no seam to fall down.
PROPERTY_X = -52.6

NEAR_WALK_X0, NEAR_WALK_X1 = -64.5, PROPERTY_X
ROAD_X0, ROAD_X1 = -87.5, -64.5
FAR_WALK_X0, FAR_WALK_X1 = -98.0, -87.5
ROAD_MID = (ROAD_X0 + ROAD_X1) / 2

# The gate road: the one link between the town and the city, leaving the street
# eastwards through this window in the east frontage. The carriageway is
# GATE_Z0..GATE_Z1 and its paving reaches GATE_WALK further out on each side.
#
# These four numbers live here rather than in gen_city.py, where the road is
# actually drawn, because they are the only piece of the city that gen_town.py
# has to obey. The gap in the east frontage between the player's plot and number
# 14 exists *for this road*. Read as a plain gap it looks like the largest bare
# frontage on the street, and the corner shop was built into it on exactly that
# reading -- a 44-stud building standing across the only road out of town, in a
# different asset from the road, so neither generator could see it. Anything new
# on the east side has to be checked against GATE_CLEAR.
GATE_Z0, GATE_Z1 = 64.0, 78.0
GATE_WALK = 4.0
GATE_CLEAR = (GATE_Z0 - GATE_WALK, GATE_Z1 + GATE_WALK)

# ---------------------------------------------------------------------------
# The front garden
# ---------------------------------------------------------------------------

# The line out of the front door, measured rather than chosen. See the note at
# the top of this file: at z -2.0 the doorway gives 2.26 studs of clearance
# either side, which is the widest it gets, and the walk from there to the
# property line is clear the whole way.
DOOR_LINE = -2.0
# Where the path starts, hard up against the house's west wall face at x 3.6.
PATH_X1 = 3.4
PATH_X0 = PROPERTY_X
PATH_HALF = 3.0

# How wide a door opening is. Twice a body's width, because both of these are
# doors a crowd is meant to go through and because a doorway a player has to aim
# at is a doorway they will bounce off.
#
# These sat two hundred lines below, with the school and the workplace, until
# the back gate needed one. They are up here now because every opening in this
# world that a player walks through wants to be one of these two numbers, and
# the gate below is the case that proves it: written independently it came out
# at 3.1 studs of clear gap, narrower than any interior door in the game.
DOORWAY = 8.0
# And how wide an internal one is.
INNER_DOORWAY = 6.0

# The gap in the fence. Wider than the path so the gateposts stand clear of it,
# and a shade over DOORWAY because the posts eat into it from both sides.
GATE_HALF = 4.2

FENCE_X = PROPERTY_X + 0.2
FENCE_Z0, FENCE_Z1 = -44.0, 22.0
FENCE_HEIGHT = 3.2
# Half the thickness of a fence rail. Was a literal inside build_street's
# fence_run; it is here now because the south boundary below is placed by
# subtracting it from the plot's edge, so the two have to be the same number.
FENCE_HALF = 0.25

# ---------------------------------------------------------------------------
# The rest of the property line
# ---------------------------------------------------------------------------

# The fence above is the *street* frontage, and it was being read as the whole
# boundary. It is not. The plot's own ground runs x -52.75..32.35, z -44.33..22,
# and three of its four sides are already closed by things that exist:
#
#   north, z 22   House.rbxmx's own 7-stud picket fence from x -55.9 to -15.6,
#                 then the house's north wall from -15.6 to 32.5. Unbroken --
#                 probed at quarter-stud steps across the full width. The land
#                 beyond it belongs to the neighbouring building in that asset,
#                 which is also why FENCE_Z1 is 22 and not the plot's north edge.
#   east          the house *is* the boundary. Its east wall stands full height
#                 from z -31.8 to 22.
#   west          the street fence, with the gate in it.
#
# That leaves the south completely open -- 85 studs of it, with nothing above
# knee height anywhere near the line. So a player who leaves by the front gate
# and turns left walks round the end of the fence, past the back of their own
# house, and onto city grass having crossed nothing whatsoever. That is how the
# town and the city came to have no boundary between them at all while the gate
# road was being described everywhere as the only link between them: the gate
# road is the only *road*, and the two grasses are flush.
#
# Closing it is the decision recorded as option A in MAP_PLAN section B. The
# reasoning written here at the time -- "the gate road becomes the only link" --
# has since been overruled: the corridor east of the plot now carries a street,
# and this fence is what it fronts. A boundary that faces a road is a garden
# fence and wants a gate in it, which is BACK_GATE_Z0/Z1 below.
#
# Both numbers measured off House.rbxmx with read_house.load(), which applies
# rotation, and re-measured by an assertion in build_street.py every run. Do not
# take them off an axis-aligned bounding box: two of that asset's panels are
# 31.3 studs on their local X and turned ninety degrees, so an AABB puts the
# east wall at 46.9 and is wrong by fourteen studs.
PLOT_X1 = 32.35        # east edge of the plot's own ground
PLOT_SEAL_Z1 = -31.8   # where the house's east wall takes over, going north
# The south run sits on FENCE_Z0 rather than on the ground's own edge at -44.33,
# so that it closes the corner with the street fence by construction instead of
# by a second number that has to be kept equal to the first.

# The furthest east *anything* in House.rbxmx reaches, which is not the same as
# PLOT_X1: the plot's ground stops at 32.35, but the house's east wall and the
# north garden's east edge stand at 32.50. The corridor east of the plot is
# measured from this one, because a pavement has to clear the wall, not the lawn.
# Re-measured by build_street.py's check_plot_boundary() every run.
HOUSE_EAST_X = 32.5

# The back gate. The rear fence returns north from the south-east corner to the
# house's east wall over FENCE_Z0..PLOT_SEAL_Z1 -- 12.2 studs -- and the gate
# takes the middle of it.
#
# One INNER_DOORWAY wide, which is the narrowest opening this world already
# asks a player to walk through. The front gate is 8.4 against a DOORWAY of 8;
# the back gate takes the inner width for the same reason a house's inner doors
# are narrower than its front one, and the player has walked through six of
# those before ever reaching this fence.
#
# It was first written as GATE_HALF / 2. That left 3.1 studs of clear gap
# between the posts -- narrower than any door in the game -- which is the sort
# of number that looks fine in a plan and plays like a turnstile. Deriving it
# from a width the player has already been proven able to walk through is the
# version that cannot make that mistake twice. At 6.0 each end of the run keeps
# 3.1 studs of real fence, so it still reads as a fence with a gate in it.
#
# Without any gate the player walks the full length of their own garden and out
# the front to reach a carriageway six studs from their back door. The fence is
# what makes the plot a plot; the gate is what stops it being a pen.
BACK_GATE_HALF = INNER_DOORWAY / 2
BACK_GATE_MID = (FENCE_Z0 + PLOT_SEAL_Z1) / 2
BACK_GATE_Z0 = BACK_GATE_MID - BACK_GATE_HALF
BACK_GATE_Z1 = BACK_GATE_MID + BACK_GATE_HALF

# ---------------------------------------------------------------------------
# The southern link
# ---------------------------------------------------------------------------

# The town had exactly one road into the city -- the gate road above -- and the
# only other window in the east frontage wide enough to take one is the 175
# studs south of the corner shop. This is the road that uses it: east from the
# town road's east kerb at the bottom of the loop, across the seam, to avenue 1.
#
# The band is not chosen. It is works cross street 1, which already runs east
# from avenue 1 into the ironworks, already has a junction tile at that corner,
# and already has a mouth cut in avenue 1's west pavement that until now opened
# onto grass. Landing on it adds no junction to the city and no carve to any
# avenue. gen_city.py asserts these three against SOUTH_CS[1], WCS_W and
# CS_WALK, which are the numbers they were read off -- the assertion is there
# rather than an import here because world_plan.py is imported *by* gen_city and
# cannot see them.
#
# It lives here for the same reason GATE_Z0/Z1 do: gen_town.py has to keep the
# east frontage clear of it and cannot import gen_city.py to find out where it
# is. Anything new on the east side is checked against SOUTHGATE_CLEAR.
SOUTHGATE_Z0, SOUTHGATE_Z1 = -316.0, -294.0
SOUTHGATE_WALK = 4.0
SOUTHGATE_CLEAR = (SOUTHGATE_Z0 - SOUTHGATE_WALK, SOUTHGATE_Z1 + SOUTHGATE_WALK)

# ---------------------------------------------------------------------------
# The northern link
# ---------------------------------------------------------------------------

# The top of the town used to be a stop. The main road ran north past the gym
# and the library and ended in a field, and the route graph agreed: wp_north_3
# was a leaf with one neighbour, so every journey between the town and the city
# went out through the gate road, the southern link or the green, and the whole
# north end was a cul-de-sac a player walks up once and never again.
#
# This is the band that opens it. The town road turns east at the top and runs
# to the connector, the way the gate road does at z 64..78, so the north end
# becomes a junction and the town's west side becomes a loop with two mouths
# instead of one.
#
# Unlike the other two links this band is not read off the city. The gate road
# takes its 14 studs from the window between the player's garden and number 14,
# and the southern link takes its 22 from works cross street 1; there is nothing
# on the city's west flank at this z to inherit from, so the road inherits from
# the town road it leaves -- ROAD_X1 - ROAD_X0, the width of the carriageway it
# tees off. A link that is the width of the road feeding it is the one width
# that cannot be wrong.
#
# Z0 is a choice and the only one here. It is far enough north of the library
# to leave two more frontages on the west side -- gen_town.py puts a cafe and a
# community hall in them and asserts both clear NORTHGATE_CLEAR -- and it is not
# aligned with city cross street 1 at z 200..222, which would have made a
# crossroads out of it. That alignment was tried on paper and dropped: the
# library already stands at z 168..208 and cannot clear a road at 200, and
# moving the library to suit a junction is the tail wagging the dog. The gate
# road is the precedent -- it is an unaligned west-side tee into the connector
# and has been since the town had a road at all.
#
# It lives here rather than in gen_town.py for the reason GATE_Z0 and
# SOUTHGATE_Z0 do: gen_town.py has to keep its north frontage clear of a road
# that gen_city.py draws, and cannot import gen_city.py to find out where it is.
NORTHGATE_Z0 = 312.0
NORTHGATE_Z1 = NORTHGATE_Z0 + (ROAD_X1 - ROAD_X0)
NORTHGATE_WALK = 4.0
NORTHGATE_CLEAR = (NORTHGATE_Z0 - NORTHGATE_WALK, NORTHGATE_Z1 + NORTHGATE_WALK)
# The centre line, which both generators need: gen_town paints it and hangs its
# junction waypoint on it, gen_city paints its half and chains four more along
# it. The gate road's and the southern link's midpoints are each recomputed
# locally in two or three places, which is fine until one of them is edited.
NORTHGATE_MID = (NORTHGATE_Z0 + NORTHGATE_Z1) / 2

# ---------------------------------------------------------------------------
# The edge of the baseplate
# ---------------------------------------------------------------------------

# Half the baseplate: solid default ground is x/z -MAP_EDGE .. +MAP_EDGE.
#
# The number is a transcription. The baseplate is declared once, in
# default.project.json, as `"Size": [2048, 20, 2048]`, and until now every
# generator that needed to know where it ended typed 1024 for itself --
# gen_city.py's CITY_X1 was one of them. Two files holding two literals for one
# measurement is the defect this tree keeps producing, so the number lives here
# and check_city.py reads the project file and asserts the two still agree. That
# check is the whole reason a transcription is acceptable: it is not a second
# source of truth, it is a cached one with a gate on the cache.
#
# Not everything stops here. The city's ground runs to z 1152 and draws its own
# floor past the baseplate's north edge, which is fine -- a slab from
# GROUND_BOTTOM up is solid whether or not there is a baseplate under it. What
# is not fine is *assuming* the baseplate is there, which is what putting a
# waypoint at z 1140 over nothing would be.
MAP_EDGE = 1024.0

# ---------------------------------------------------------------------------
# The south edge of the world
# ---------------------------------------------------------------------------

# Where the map stops, and it is the city that decides. The works district ends
# at its own apron -- a boundary treeline wide enough to say "the map ends here"
# without a wall -- and that apron's south face is the southernmost thing in the
# world. gen_city.py derives it as `WORKS_Z0` from the works' street plan, so
# this is a transcription of a number computed over there, and gen_city asserts
# the two agree the moment either moves.
#
# It lives here rather than in gen_town.py for exactly the reason SOUTHGATE_Z0
# does: the town has to end level with the city and cannot import gen_city.py to
# find out where that is. Before this existed the town stopped at a typed -328,
# 172 studs short of the city's edge, and the gap read as the map running out
# early on one side.
MAP_SOUTH_EDGE = -500.0

# ---------------------------------------------------------------------------
# The crossing
# ---------------------------------------------------------------------------

# Centred on the door line, so the way out of the house and the way across the
# road are the same straight walk. A player who leaves home and keeps going
# arrives at the far sidewalk without ever having made a decision, which is the
# point: the decision is which way to turn once they are there.
CROSSING_Z0, CROSSING_Z1 = DOOR_LINE - 6.0, DOOR_LINE + 6.0

# ---------------------------------------------------------------------------
# The west frontage
# ---------------------------------------------------------------------------

# Every building on the west side of the main street, in one file, because the
# frontage is built by two of them: the school and the workplace come out of
# build_street.py and the other seven out of gen_town.py. They used to be
# declared in whichever file drew them, and the cost of that showed up twice.
# Once when both files planted a street tree in the same square at (-104, 88),
# one trunk inside another, in two assets neither of which could see the other.
# Once when this frontage's gaps were counted from gen_town.py alone, which
# knows about seven of the nine buildings, and the comment that came out of the
# count said the gym-library gap was the only one wide enough to walk down. It
# is the narrowest of three. A frontage described in two places is a frontage
# nobody has measured.
#
# All nine front the same line, with a forecourt between them and the far
# sidewalk. Same line on purpose: a street is a street because its buildings
# agree about where the front of a building is.
FRONT_X = -112.0
FORECOURT_X0 = -112.0

# ---------------------------------------------------------------------------
# The return road
# ---------------------------------------------------------------------------

# The return leg of the loop south of the street, and the back street that
# stands on its west side, are both drawn in gen_town.py, which is also where
# these numbers used to live entirely. They move here because the school now
# stands on that street too (see below) and build_street.py, which draws the
# school, cannot import gen_town.py to find out where its own building's front
# door faces -- the same reason NORTHGATE_Z0/GATE_Z0 already live here rather
# than in the file that draws the roads they describe.
#
# RETURN_X0/X1 is the carriageway; BACK_WALK_X0/X1 is its west pavement,
# mirroring the sidewalk the main street already has (SIDEWALK, the width of
# FAR_WALK_X0..X1) rather than choosing a second number for the same kerb.
RETURN_X0, RETURN_X1 = -225.0, -202.0
RETURN_MID = (RETURN_X0 + RETURN_X1) / 2
SIDEWALK = FAR_WALK_X1 - FAR_WALK_X0
BACK_WALK_X1 = RETURN_X0
BACK_WALK_X0 = BACK_WALK_X1 - SIDEWALK

# ---------------------------------------------------------------------------
# The school
# ---------------------------------------------------------------------------

# Moved off the main street entirely, onto the back street's west side, by
# direct owner instruction: "the school is overlapping onto roads and it
# still isnt big enough so move its location."
#
# Every FRONT_X-facing footprint on the main street is capped at
# BUILDING_DEPTH -- 40 studs -- because the return road's own sidewalk
# (RETURN_X1 + SIDEWALK) runs the entire north-south length of the map right
# behind it; growing a building on that frontage past about 90 studs deep
# drives its back wall through a road no matter how far the front wall is
# pushed, which is what happened at both -232 and -190, the school's last two
# homes on this site (kept in git blame, not here). That ceiling cannot be
# raised by resizing in place. It can only be left.
#
# The back street's west side has no such ceiling. WEST_EDGE (gen_town.py) is
# a declared stopping point for what that generator chooses to build, not a
# wall or a road -- nothing stands past it in any generator, and the baseplate
# itself runs to MAP_EDGE. A building sited here can be as deep as the design
# needs rather than as deep as the nearest road allows.
#
# The site is the back street's own frontage, chosen rather than found clear:
# it falls exactly on back-street houses "1", "3" and "5" (gen_town.py's
# BACK_ROW, z 174-208, 134-168 and 94-128), which is what "or remove houses to
# compensate" already authorised. SCHOOL_Z0/Z1 line up on their outer edges --
# 208 is BACK_ROW's own north end (LIB_Z1, no gap needed there) and 94 is
# house "5"'s own south wall, leaving house "7" its ordinary NEIGHBOUR_GAP to
# the school's south wall rather than a second, wider gap invented for the
# occasion. gen_town.py filters BACK_ROW against this same band, so moving the
# school moves the houses it displaces without a second number to keep in step.
#
# The school faces the same way the houses it replaced did: east, onto
# BACK_WALK's sidewalk and the return road beyond it. That keeps
# build_street.py's existing convention -- door on the east wall -- true
# without a structural change, only new coordinates.
#
# Depth is chosen room by room rather than as one figure, because the two
# rows either side of the corridor need different amounts of it. SCHOOL_YARD
# mirrors BACK_FRONT_YARD (gen_town.py): the gap between the sidewalk and the
# building's own front wall. EAST_ROOM_DEPTH holds the lobby/office/gym row,
# which needs no more than the old building's whole depth did. WEST_ROOM_DEPTH
# holds Math/Science/the cafeteria, and is sized for Science: Lab.Build
# scatters stations on a ring in every direction from a centre point (see
# SCIENCE_Z0/Z1 below), not along one axis, so the room has to be wide as well
# as deep -- unlike the old site, nothing here is forcing a choice between
# the two.
SCHOOL_YARD = 6.0
EAST_ROOM_DEPTH = 39.0
CORRIDOR_WIDTH = 8.0
WEST_ROOM_DEPTH = 70.0

SCHOOL_X1 = BACK_WALK_X0 - SCHOOL_YARD
SCH_IN_X1 = SCHOOL_X1 - WALL
HALL_E_X1 = SCH_IN_X1 - EAST_ROOM_DEPTH
HALL_E_X0 = HALL_E_X1 - PARTITION
HALL_W_X1 = HALL_E_X0 - CORRIDOR_WIDTH
HALL_W_X0 = HALL_W_X1 - PARTITION
SCH_IN_X0 = HALL_W_X0 - WEST_ROOM_DEPTH
SCHOOL_X0 = SCH_IN_X0 - WALL          # -363.5 -- 122 studs deep, was 78

SCHOOL_Z0, SCHOOL_Z1 = 94.0, 208.0    # houses "1"/"3"/"5"'s combined frontage
SCHOOL_DOOR = (SCHOOL_Z0 + SCHOOL_Z1) / 2   # 151.0 -- house "3"'s own door line

WORK_X0, WORK_X1 = -142.0, FRONT_X
WORK_Z0, WORK_Z1 = -74.0, -22.0
WORK_DOOR = -48.0

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

# The two north of the library, and the reason they exist: past the library the
# west frontage stopped and the sidewalk ran another twenty-four studs into a
# field. A player who walked the length of the town found the last thing in it
# was a building they had already been in, and then nothing -- the north end
# read as the map running out rather than as the top of a street.
#
# Nothing about their footprints is chosen. The gap between two buildings on
# this side, the depth of a store and the depth of the library are all already
# facts about the row; the cafe is a store's depth and the hall is the library's,
# each one gap north of what it follows. Doors are on the centre line, which is
# where all five of the existing doors are.
WEST_GAP = CLINIC_Z0 - BAKERY_Z1
assert WEST_GAP == BAKERY_Z0 - GARAGE_Z1, (
    f"the west side leaves {WEST_GAP} studs between the bakery and the clinic "
    f"and {BAKERY_Z0 - GARAGE_Z1} between the garage and the bakery. The cafe "
    f"and the hall are spaced by that number, and it has stopped being one "
    f"number.")
# These two were called STORE_DEPTH and LIB_DEPTH and they are not depths. Every
# building on this frontage faces the road across its *x* axis, so the distance
# back from its front wall is the x extent -- 40 studs, the same for all nine --
# and the z extent these measure is how much frontage it takes up along the
# street. The old names said the opposite of what the numbers were, and the
# first thing built against them from outside this file (the parade at the tip
# end, which is 40 back and 36 wide) was written 36 back and 40 wide before the
# footprint was printed out and read. Renamed rather than commented, because a
# comment does not travel to the call site and a name does.
STORE_FRONT = BAKERY_Z1 - BAKERY_Z0
LIB_FRONT = LIB_Z1 - LIB_Z0

# The one that really is a depth: how far back from the front wall a building on
# this frontage goes. Derived from the garage and then asserted against all of
# them, because a row where one building is deeper than its neighbours has a
# back wall standing in somebody's yard, and the parades built elsewhere in the
# town read this number rather than choosing their own.
BUILDING_DEPTH = GARAGE_X1 - GARAGE_X0
for _bn, _bx0, _bx1 in (("the garage", GARAGE_X0, GARAGE_X1),
                        ("the bakery", BAKERY_X0, BAKERY_X1),
                        ("the clinic", CLINIC_X0, CLINIC_X1),
                        ("the library", LIB_X0, LIB_X1)):
    assert _bx1 - _bx0 == BUILDING_DEPTH, (
        f"{_bn} is {_bx1 - _bx0} studs deep and the frontage is built {BUILDING_DEPTH}. "
        f"Every building on the west side shares one depth, and the two parades "
        f"read that number rather than choosing one, so this is now two depths.")

CAFE_X0, CAFE_X1 = -152.0, FRONT_X
CAFE_Z0 = LIB_Z1 + WEST_GAP
CAFE_Z1 = CAFE_Z0 + STORE_FRONT
CAFE_DOOR = (CAFE_Z0 + CAFE_Z1) / 2

HALL_X0, HALL_X1 = -152.0, FRONT_X
HALL_Z0 = CAFE_Z1 + WEST_GAP
HALL_Z1 = HALL_Z0 + LIB_FRONT
HALL_DOOR = (HALL_Z0 + HALL_Z1) / 2

# The frontage in z order, which is the only order any question about it wants
# an answer in. Sorted rather than typed in order, so adding a tenth building
# anywhere in the list puts it in the right place in every gap measurement.
#
# Eight buildings now, not nine: the school stood here once, but it has moved
# to the back street (see SCHOOL_X0 above) and left this frontage for good --
# it is not confined to a FRONT_X-facing footprint any more, so it has no
# business in the tuple that measures FRONT_X-facing gaps.
WEST_FRONTAGE = tuple(sorted((
    ("the garage", GARAGE_Z0, GARAGE_Z1),
    ("the bakery", BAKERY_Z0, BAKERY_Z1),
    ("the clinic", CLINIC_Z0, CLINIC_Z1),
    ("the workplace", WORK_Z0, WORK_Z1),
    ("the gym", GYM_Z0, GYM_Z1),
    ("the library", LIB_Z0, LIB_Z1),
    ("the cafe", CAFE_Z0, CAFE_Z1),
    ("the community hall", HALL_Z0, HALL_Z1),
), key=lambda b: b[1]))

for _a, _b in zip(WEST_FRONTAGE, WEST_FRONTAGE[1:]):
    assert _b[1] >= _a[2], (
        f"{_a[0]} runs to z {_a[2]} and {_b[0]} starts at z {_b[1]}, so they "
        f"overlap by {_a[2] - _b[1]} studs. Two buildings on the west frontage "
        f"are standing in each other.")

# The alleys through the frontage.
#
# The west side is a solid wall of building from the garage to the community
# hall, and the back street runs the whole length of it on the other side. Two
# parallel roads joined only at their ends is what check_city's detour ratio
# punishes: a player outside a back-street house who wants the library walks to
# a corner first. The gaps between buildings are the only way through, and an
# alley goes in every gap wide enough to hold one.
#
# Wide enough means a doorway's width to walk down -- the same opening the
# player has already walked through everywhere else -- plus a margin of grass
# against each building, so the paving stops short of the walls instead of
# running into them. Which gaps those are is measured here rather than decided:
# the first version of this picked one by hand and got it wrong, because the
# file it was picked in could only see seven of the nine buildings.
ALLEY_WIDTH = DOORWAY
ALLEY_MARGIN = 4.0
ALLEY_MIN = ALLEY_WIDTH + 2 * ALLEY_MARGIN

ALLEYS = tuple(
    (f"{_a[0]} and {_b[0]}",
     (_a[2] + _b[1]) / 2 - ALLEY_WIDTH / 2,
     (_a[2] + _b[1]) / 2 + ALLEY_WIDTH / 2)
    for _a, _b in zip(WEST_FRONTAGE, WEST_FRONTAGE[1:])
    if _b[1] - _a[2] >= ALLEY_MIN)

# Safe range 2-5. One alley down a 500-stud frontage is a frontage the player
# walks around rather than through, which is the state this started in and the
# detour check failed on. More than five and the west side has stopped being a
# row of buildings and become a row of gaps. Reports rather than clamps: the
# number is a symptom of the footprints, not a thing to correct here.
assert 2 <= len(ALLEYS) <= 5, (
    f"the west frontage came out with {len(ALLEYS)} gaps of at least "
    f"{ALLEY_MIN} studs, out of "
    f"{[(f'{a[0]}/{b[0]}', b[1] - a[2]) for a, b in zip(WEST_FRONTAGE, WEST_FRONTAGE[1:])]}. "
    f"Check the west frontage footprints and ALLEY_MIN.")


# A tree's trunk, and therefore the only part of a tree that stands on the
# ground. The canopy is CanCollide false in all three generators on purpose --
# it hangs at head height and a player is meant to brush through it -- so the
# square a tree occupies is this wide and not `spread` wide.
#
# It lives here because `tree()` is written out three times, in gen_town.py,
# build_street.py and gen_city.py, and all three had their own 1.6. That is the
# same shape as every other defect this week: one measurement, several files,
# no way for any of them to notice the others disagreeing. They agreed, this
# time. Nothing made them.
TRUNK_WIDTH = 1.6


def alley_slug(blurb: str) -> str:
    """`the gym and the library` -> `GymLibrary`, for part names."""
    return "".join(w.title() for w in blurb.split() if w not in ("the", "and"))


def clear_of_alleys(z: float, spread: float) -> bool:
    """Is there room for something `spread` wide, centred on z, beside an alley?

    Street trees want the frontage gaps for the same reason the alleys do --
    they are the only grass left on that side -- and where both want the same
    gap the path wins. A tree standing in a footpath is an obstacle, not a
    hedge, which is the same conclusion already reached about the one that used
    to stand on the cafe's forecourt. Asked as a question rather than answered
    with a list of trees to delete, because a list goes stale the moment a
    building moves and the tree it silently readmits stands in the road.
    """
    return all(z + spread / 2 <= z0 or z - spread / 2 >= z1
               for _blurb, z0, z1 in ALLEYS)


def clear_of_forecourts(x: float, z: float, spread: float) -> bool:
    """The same question about the paved aprons in front of the nine buildings.

    This exists because check_town's check 7 found a nine-stud tree standing in
    the middle of the clinic's forecourt on the check's first run. The tree is
    planted in `build_street.py`; the forecourt is drawn in `gen_town.py`; the
    two are in different assets and neither file can see the other's, so nothing
    anywhere in the tree was wrong and nothing anywhere could have said so.
    That is the third time this exact shape has cost something -- the duplicate
    trunk at (-104, 88), the tree in the finished alley, and now this -- and all
    three were two files placing objects into one strip.

    A forecourt runs from the building line to the far sidewalk, over the z the
    building occupies, so the answer is read off WEST_FRONTAGE rather than from
    a list of aprons: a building added to that tuple gets a forecourt that trees
    already avoid, without anybody remembering to say so.

    The x band is FORECOURT_X0..FAR_WALK_X0 because that is the span both
    generators pass to `box`. It is emphatically *not* FRONT_X..FORECOURT_X0:
    those are two names for the same number, -112, and this function was first
    written that way -- a zero-width band that answered "clear" for every point
    in the world including the tree it was written to catch. The two names exist
    because a building's front and its apron's near edge are the same line today
    and might not be tomorrow; that is a reason to keep both names, not a reason
    to measure a width between them.
    """
    if not (min(FORECOURT_X0, FAR_WALK_X0) - spread / 2 <= x
            <= max(FORECOURT_X0, FAR_WALK_X0) + spread / 2):
        return True
    return all(z + spread / 2 <= z0 or z - spread / 2 >= z1
               for _blurb, z0, z1 in WEST_FRONTAGE)


def clear_of_paving(x: float, z: float, width: float) -> bool:
    """Is this square still grass? One question, both generators, every surface.

    `width` is the footprint of the thing that stands on the ground, which for
    a tree is `TRUNK_WIDTH` and not its canopy: check_town's check 7 measures
    trunks and deliberately ignores canopies, because a branch over a pavement
    is what a street tree is for. A filter that refuses what the checker would
    pass is not caution, it is a second opinion nobody asked for, and it costs
    real trees -- asked with the canopy instead, this drops the tree outside the
    school over a one-stud overhang of its forecourt.

    The two rules above are separate because they are separate measurements, and
    composed here because a call site should be asking "may I plant this" rather
    than enumerating the ways the answer could be no -- the alley tree survived
    a call site that asked only about alleys, and the forecourt tree survived
    one that asked about nothing at all.

    This prevents. It is not the guarantee: it can only know about the surfaces
    it has been taught, and both trees it was written for were standing on a
    surface nobody had thought to teach it. check_town's check 7 measures the
    built asset and is what actually holds the line.

    The alley half is asked without checking x, which makes it conservative:
    it will refuse a spot that merely shares a z with an alley even if it is two
    hundred studs away from one. That is deliberate for now -- the alleys' z
    bands are measured here but their x span is `RETURN_X1 + SIDEWALK` to
    `FAR_WALK_X0`, and RETURN_X1 belongs to the return road, which only
    gen_town.py draws. Narrowing it means moving that road into the plan, which
    is a real change and not one to make in passing. Refusing too much plants
    one tree fewer; refusing too little is the defect this whole function is
    about, so the error is taken in the safe direction and written down rather
    than left to be rediscovered.
    """
    return clear_of_alleys(z, width) and clear_of_forecourts(x, z, width)

# Floor heights. Ground floors sit level with the paving outside them.
FLOOR_1 = PAVING
CEIL_1 = FLOOR_1 + STOREY
FLOOR_2 = CEIL_1 + SLAB
CEIL_2 = FLOOR_2 + STOREY

# The stair in the workplace: one straight run, no landing, climbing north.
#
# Rise and going are stated rather than derived so read_house.py can confirm they
# multiply back out to the storey height -- a stair whose top is a stud short of
# the floor it serves is a stair that drops the player back down it. A stud of
# rise per stud of going is steeper than a real building and the reason is the
# building: sixteen studs of storey at a realistic pitch is a thirty-stud run,
# which is two thirds of the depth of the whole store. Roblox walks a 1.0 step
# without animating a climb. Safe range 0.6-1.5.
STAIR_STEPS = 16
STAIR_RISE = 1.0
STAIR_GOING = 1.0
STAIR_WIDTH = 6.0
STAIR_X0, STAIR_X1 = -140.5, -134.5
STAIR_Z0, STAIR_Z1 = -56.0, -40.0

# What read_house.py holds the stair to. A Roblox humanoid walks up a step of
# 2.0 without any help, so the rise limit is about how it looks and feels rather
# than whether it is climbable; the going limit is about whether a foot lands on
# it. Both stated as bars rather than derived, so changing the stair above has
# to survive a number somebody chose on purpose.
STAIR_MAX_RISE = 1.6
STAIR_MIN_GOING = 0.9
# Clear height over a tread and through a doorway. A body is 5.8 studs tall
# (Config.NPC.BodyHeight); the difference is the margin that stops a camera from
# clipping the slab every step of the way up.
MIN_HEADROOM = 6.5

# ---------------------------------------------------------------------------
# Rooms
# ---------------------------------------------------------------------------

# School: one storey, laid out along a spine corridor with the west row (away
# from the door) holding the subject rooms and the east row (facing it)
# holding the lobby, the office and the gym. Single storey because a stair is
# the one thing in a building that cannot be got wrong quietly -- it either
# works or the player is stuck on a landing -- and the workplace already has
# the one that has to work. The school gets a second floor when there is a
# reason to go up there.
#
# HALL_E_X0/X1 and HALL_W_X0/X1 (the corridor's two walls) and SCH_IN_X0/X1
# (the building's own inner face) are declared with the site above rather
# than here, because SCH_IN_X0's only job is bounding how deep the west row
# can go -- it is part of choosing where the building's own walls stand, not
# part of laying rooms out inside them. build_street.py imports all four
# rather than re-deriving them, which it used to do independently: two files
# computing the same wall from the same SCHOOL_X0 is the one-measurement,
# two-files problem WEST_FRONTAGE already exists to avoid, and there was no
# reason the corridor should be exempt from it.
SCH_IN_Z0, SCH_IN_Z1 = SCHOOL_Z0 + WALL, SCHOOL_Z1 - WALL   # 95.5 .. 206.5

# The west row's three z-bands are not equal to each other. Science needs by
# far the most: `Lab.Build` (Lab.luau) scatters real stations on a ring out to
# Config.School.Science.RoomRadiusStuds in every direction from a centre
# point, not along a single axis, so its band has to be wide as well as deep.
# Math and the cafeteria have no such requirement -- Math answers questions
# with floor discs fanned around wherever the player is standing
# (SchoolService.placeDiscs), and the cafeteria is hand-placed furniture with
# nothing procedural in it -- so Math takes only what a teacher's desk and two
# rows of pupils' need and the cafeteria takes what both leave over.
MATH_Z0, MATH_Z1 = SCH_IN_Z0, SCH_IN_Z0 + 25.0
WEST_SPLIT_1 = MATH_Z1
SCIENCE_Z0 = WEST_SPLIT_1 + PARTITION
SCIENCE_Z1 = SCIENCE_Z0 + 60.0
WEST_SPLIT_2 = SCIENCE_Z1
CAFETERIA_Z0, CAFETERIA_Z1 = WEST_SPLIT_2 + PARTITION, SCH_IN_Z1

# The east row's three z-bands. The lobby is sized around the door rather
# than the other way round -- SCHOOL_DOOR sits inside it with room either
# side for the inner doorway cut through HallEast -- and the office and the
# school's own gym (a PE court, not the freestanding public gym on the main
# street: see GYM_X0/X1 above, a different building for a different age of
# player) take what is left north and south of it.
OFFICE_Z0, OFFICE_Z1 = SCH_IN_Z0, SCH_IN_Z0 + 43.0
EAST_SPLIT_1 = OFFICE_Z1
LOBBY_Z0 = EAST_SPLIT_1 + PARTITION
LOBBY_Z1 = LOBBY_Z0 + 24.0
EAST_SPLIT_2 = LOBBY_Z1
SCH_GYM_Z0, SCH_GYM_Z1 = EAST_SPLIT_2 + PARTITION, SCH_IN_Z1
assert LOBBY_Z0 < SCHOOL_DOOR < LOBBY_Z1, (
    f"the lobby now spans z {LOBBY_Z0}..{LOBBY_Z1} and the door is at "
    f"{SCHOOL_DOOR}. The door has to open into the room it is named for.")

SCHOOL_LOBBY = Place("school lobby", HALL_E_X1, SCH_IN_X1, LOBBY_Z0, LOBBY_Z1, FLOOR_1, CEIL_1)
SCHOOL_HALL = Place("school corridor", HALL_W_X1, HALL_E_X0, SCH_IN_Z0, SCH_IN_Z1, FLOOR_1, CEIL_1)
SCHOOL_MATH = Place("math classroom", SCH_IN_X0, HALL_W_X0, MATH_Z0, MATH_Z1, FLOOR_1, CEIL_1)
SCHOOL_SCIENCE = Place("science lab", SCH_IN_X0, HALL_W_X0, SCIENCE_Z0, SCIENCE_Z1, FLOOR_1, CEIL_1)
SCHOOL_CAFETERIA = Place("cafeteria", SCH_IN_X0, HALL_W_X0, CAFETERIA_Z0, CAFETERIA_Z1, FLOOR_1, CEIL_1)
# The centre of the science lab's floor, well clear of every wall -- see the
# comment above SCIENCE_Z0/Z1. Passed to Lab.Build (via a "science_lab" place
# point below) instead of the school's own outdoor forecourt point, which is
# what SchoolService used until now: `ceilingAbove` in Lab.luau raycasts up
# from the centre it is given and refuses to build at all if there is no roof
# within a storey of it, and the forecourt has none. That is not a hypothetical
# -- it is the point PLACE_ID "school" names, and it is outdoors, so Science
# could never actually have built a single bench before this room existed for
# it to build one inside.
SCIENCE_CENTER_X = (SCHOOL_SCIENCE.x0 + SCHOOL_SCIENCE.x1) / 2
SCIENCE_CENTER_Z = (SCIENCE_Z0 + SCIENCE_Z1) / 2
SCHOOL_GYM = Place("school gym", HALL_E_X1, SCH_IN_X1, SCH_GYM_Z0, SCH_GYM_Z1, FLOOR_1, CEIL_1)
SCHOOL_OFFICE = Place("school office", HALL_E_X1, SCH_IN_X1, OFFICE_Z0, OFFICE_Z1, FLOOR_1, CEIL_1)

# Workplace: a store on the ground floor and offices over it, which is one
# building holding both of the jobs the economy needs -- the one a sixteen year
# old can take and the one an adult can. They are separated by a staircase rather
# than by a loading screen.
#
# The ground floor is deliberately one room. A shop floor with the front door at
# one end and the stair at the other is a room a player can read from the doorway,
# and a player who has just walked into a building for the first time in this game
# should not have to solve it. Everything that is not selling happens behind the
# stockroom wall at the far end.
WORK_SHOP = Place("shop floor", -140.5, -113.5, -57.0, -23.5, FLOOR_1, CEIL_1)
WORK_BACK = Place("stockroom", -140.5, -113.5, -72.5, -58.0, FLOOR_1, CEIL_1)

# The stairwell, as a place, so the check can ask whether a body fits in it. It
# is a hole in the upper slab as much as it is a room: the three slab boxes in
# build_street.py are drawn around exactly these bounds, and if the two ever
# disagree the player climbs the stair into a ceiling.
WORK_STAIR = Place("stairwell", STAIR_X0, STAIR_X1, STAIR_Z0, STAIR_Z1, FLOOR_1, CEIL_2)

# Upstairs. The stair arrives on a landing at the street end, and a corridor runs
# back from it down the length of the building with the offices off its east side
# -- the same spine the school uses, for the same reason: one line to walk and
# every door visible from it.
WORK_LANDING = Place("office landing", -140.5, -127.0, -40.0, -23.5, FLOOR_2, CEIL_2)
WORK_CORRIDOR = Place("office corridor", -133.5, -127.0, -72.5, -40.0, FLOOR_2, CEIL_2)
# Over the stockroom, west of the corridor. The room a shift gets to leave to.
# It stops a stud short of the stair void and a wall stands in the gap: a room
# whose far end is a hole in the floor is a room that kills people.
WORK_BREAK = Place("break room", -140.5, -134.5, -72.5, -57.0, FLOOR_2, CEIL_2)
WORK_OPEN = Place("open plan office", -126.0, -113.5, -72.5, -48.0, FLOOR_2, CEIL_2)
WORK_MEETING = Place("meeting room", -126.0, -113.5, -47.0, -23.5, FLOOR_2, CEIL_2)

# Outdoors. Ceilings are nominal; see Place.
GARDEN = Place("front garden", PROPERTY_X, 3.4, -30.0, 18.0, 1.04, 90.0, indoors=False)
STREET_PLACE = Place("street", FAR_WALK_X0, PROPERTY_X, -60.0, 90.0, GROUND, 90.0, indoors=False)

PLACES = [
    GARDEN, STREET_PLACE,
    SCHOOL_LOBBY, SCHOOL_HALL, SCHOOL_MATH, SCHOOL_SCIENCE, SCHOOL_CAFETERIA,
    SCHOOL_GYM, SCHOOL_OFFICE,
    WORK_SHOP, WORK_BACK, WORK_STAIR,
    WORK_LANDING, WORK_CORRIDOR, WORK_BREAK, WORK_OPEN, WORK_MEETING,
]

# ---------------------------------------------------------------------------
# Place points
# ---------------------------------------------------------------------------

# Somewhere the game can be told to put a player, or to look for one. Same idea
# as the delivery points in house_plan.py and the same reason for existing: the
# spot is a property of the world, so it lives in the world and not in a table of
# coordinates in Luau that nobody remembers to update when a wall moves.
#
# Mirrors Config.World.PlacePointTag / PlacePointAttribute.
PLACE_TAG = "AgesPlacePoint"
PLACE_ID_ATTRIBUTE = "PlaceId"
# What /places prints beside the id. It rides on the part rather than living in a
# Luau table for the same reason the position does: one of the two would rot.
PLACE_LABEL_ATTRIBUTE = "PlaceLabel"

# id, x, z, floor, description. The descriptions are what /places prints, so they
# are written for somebody standing in the game wondering where they can go.
PLACE_POINTS = [
    ("home", 0.0, DOOR_LINE, PATH_TOP, "the front path, outside your own door"),
    # **The world's SpawnLocation is not here.** It stands at (8, 1.14, -21.5) in
    # default.project.json, which is inside the nursery, and this note used to say
    # it was at the gate -- the pad was moved twice and the note was not, so it had
    # become an instruction to undo both moves. It is written out here rather than
    # left to the project file because a .project.json cannot hold a comment.
    #
    # Three positions, each overruling the last, and the reasons are worth keeping
    # because two of them are not about geometry at all:
    #
    #   (13, 1.387, -18.6)  over nothing. The front garden ends at x=3.4 and the
    #                       city's ground does not start until x=8, z=60, so a
    #                       player who arrived before a service teleported them
    #                       fell to the baseplate. This is what check_city's check
    #                       9 was written for, and check 9 still reads the real
    #                       value out of the project file every run.
    #   the front gate      solid, and wrong for the game: a life begins as a
    #                       crawler and it should begin where the events are, not
    #                       out on the lawn.
    #   (8, 1.14, -21.5)    in the nursery, at the *far* side of it. It sat seven
    #                       studs from the rug against an interact radius of six,
    #                       so the first event of a life fired after about a
    #                       quarter second of crawling. Nine studs now -- a little
    #                       over two seconds at a crawler's speed, on a path that
    #                       clears the furniture.
    #
    # So if the nursery furniture moves, this moves, and the number that matters is
    # the distance to the rug rather than the coordinate. The pad is also thin and
    # non-collidable on purpose: a default 12x1x12 collidable slab is a one-stud
    # lip that an adult steps over without noticing and a crawler at jumpPower 0
    # cannot climb at all.
    ("gate", PROPERTY_X + 3.0, DOOR_LINE, PATH_TOP, "your front gate, on the street"),
    ("crossing", -58.0, DOOR_LINE, PAVING, "the crossing outside your house"),
    # On the back street now, not the main one -- see SCHOOL_X0 above. Set back
    # from BACK_WALK_X0 by half of SCHOOL_YARD rather than by a chosen offset,
    # the same rule the old point followed against FRONT_X and FAR_WALK_X0: the
    # middle of the forecourt, not its edge. gen_town.py's own "wp_school_walk",
    # on the sidewalk this point faces, is what actually joins it to the rest
    # of the map -- see the comment there.
    ("school", SCHOOL_X1 + SCHOOL_YARD / 2, SCHOOL_DOOR, PAVING, "the school forecourt"),
    # Just inside the math classroom door rather than in among the desks.
    # Somewhere the game can put a player down is somewhere a player can be
    # put down standing up, and the middle of a row of desks is not that. The x
    # is the west row's own centre line (SCIENCE_CENTER_X, shared by all three
    # rooms in that row since they share an x-band) rather than a chosen depth,
    # so all three of these points move together if the row's depth ever does.
    ("classroom", SCIENCE_CENTER_X, (MATH_Z0 + MATH_Z1) / 2, FLOOR_1, "a classroom"),
    # The centre of the science lab's floor -- see the comment on
    # SCIENCE_CENTER_X/Z above. This is what SchoolService.buildRoom passes to
    # Lab.Build instead of the outdoor "school" point, which has no roof over
    # it and so could never pass Lab.Build's own ceiling check.
    ("science_lab", SCIENCE_CENTER_X, SCIENCE_CENTER_Z, FLOOR_1, "the science lab, among the benches"),
    ("cafeteria", SCIENCE_CENTER_X, (CAFETERIA_Z0 + CAFETERIA_Z1) / 2, FLOOR_1, "the cafeteria"),
    ("work", -105.0, WORK_DOOR, PAVING, "outside the store"),
    ("store", -120.0, WORK_DOOR, FLOOR_1, "the shop floor"),
    # In the open plan office rather than in the corridor outside it, because this
    # is where Part 2's desk job clocks in and a clock-in point you have to walk
    # away from to start working is a clock-in point in the wrong room.
    ("office", -123.0, -52.5, FLOOR_2, "the office upstairs"),
]

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

# The whole point of this part, written down as something that can fail.
#
# Everything else read_house.py measures is a rate -- what share of the house can
# hold a fan of choice markers, what share can stage a parent. A route is not a
# rate. Either you can walk from your front door to the school or you cannot, and
# if you cannot then the street does not exist as far as the player is concerned
# no matter how much of it got built.
#
# Straight segments between waypoints, because that is the honest test: Roblox
# pathfinding would route around a bollard placed in a doorway and report a walk
# that no player would ever find. A route that is clear as a series of straight
# lines is clear.
ROUTES = [
    ("out of the front door", FLOOR_1, [
        (5.0, DOOR_LINE), (0.0, DOOR_LINE), (PROPERTY_X + 3.0, DOOR_LINE),
        (-58.0, DOOR_LINE),
    ]),
    ("across the road", GROUND, [
        (-58.0, DOOR_LINE), (-92.0, DOOR_LINE),
    ]),
    # The walk from the crossing to the school's own forecourt is deliberately
    # not here. It used to be a straight sidewalk hop, "up the street to
    # school", because the school stood on this same street; now it crosses an
    # alley, a second road and a second sidewalk that gen_town.py draws into a
    # different asset (Town.rbxmx), which this file's straight-line checker
    # never loads (see _street_field in read_house.py) and so could never
    # honestly verify. That walk is check_city's job, which reads every asset
    # and already checks reachability and detour ratio over the town's own
    # waypoint graph -- gen_town.py's "wp_school_walk" is what joins the school
    # to it. What stays here is what this file can actually see: the forecourt
    # inward, all of it inside Street.rbxmx.
    ("into the school", FLOOR_1, [
        (SCHOOL_X1 + SCHOOL_YARD / 2, SCHOOL_DOOR),
        (SCH_IN_X1 - 6.5, SCHOOL_DOOR),
        ((HALL_W_X1 + HALL_E_X0) / 2, SCHOOL_DOOR),
        (HALL_W_X0 - 3.0, SCHOOL_DOOR),
    ]),
    ("along the school corridor", FLOOR_1, [
        ((HALL_W_X1 + HALL_E_X0) / 2, MATH_Z0 + 1.0),
        ((HALL_W_X1 + HALL_E_X0) / 2, SCHOOL_DOOR),
        ((HALL_W_X1 + HALL_E_X0) / 2, CAFETERIA_Z1 - 1.0),
    ]),
    ("down the street to work", PAVING, [
        (-92.0, DOOR_LINE), (-92.0, WORK_DOOR), (-105.0, WORK_DOOR),
    ]),
    ("into the store", FLOOR_1, [
        (-105.0, WORK_DOOR), (-118.0, WORK_DOOR), (-130.0, WORK_DOOR),
        (-130.0, -62.0),
    ]),
    # Starts at the head of the stair and ends at the desk. The stair itself is
    # not routed through: a flight of steps reads as a wall to a flat clearance
    # sweep, which is the right answer for a flat sweep and not worth fighting.
    # It is checked as geometry instead -- steps times rise against the storey
    # height, and the width and headroom of the well it runs in.
    ("across the office floor", FLOOR_2, [
        (-137.5, -37.0), (-130.0, -30.0), (-130.0, -59.0), (-123.0, -59.0),
        (-123.0, -52.5),
    ]),
]

# How much room a route has to have. The same half-body the rest of the checking
# is done with, and deliberately not the narrower walking figure read_house.py
# allows inside the house: squeezing sideways past a dining chair is a thing a
# player will do in their own kitchen, and having to do it to get out of the front
# door is not.
ROUTE_RADIUS = 1.4
