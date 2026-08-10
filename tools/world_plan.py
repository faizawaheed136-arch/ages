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
# The gap in the fence. Wider than the path so the gateposts stand clear of it.
GATE_HALF = 4.2

FENCE_X = PROPERTY_X + 0.2
FENCE_Z0, FENCE_Z1 = -44.0, 22.0
FENCE_HEIGHT = 3.2

# ---------------------------------------------------------------------------
# The crossing
# ---------------------------------------------------------------------------

# Centred on the door line, so the way out of the house and the way across the
# road are the same straight walk. A player who leaves home and keeps going
# arrives at the far sidewalk without ever having made a decision, which is the
# point: the decision is which way to turn once they are there.
CROSSING_Z0, CROSSING_Z1 = DOOR_LINE - 6.0, DOOR_LINE + 6.0

# ---------------------------------------------------------------------------
# The two buildings
# ---------------------------------------------------------------------------

# Both front the same line, with a forecourt between them and the far sidewalk.
# Same line on purpose: a street is a street because its buildings agree about
# where the front of a building is.
FRONT_X = -112.0
FORECOURT_X0 = -112.0

SCHOOL_X0, SCHOOL_X1 = -152.0, FRONT_X
SCHOOL_Z0, SCHOOL_Z1 = 10.0, 76.0
SCHOOL_DOOR = 43.0

WORK_X0, WORK_X1 = -142.0, FRONT_X
WORK_Z0, WORK_Z1 = -74.0, -22.0
WORK_DOOR = -48.0

# How wide a door opening is. Twice a body's width, because both of these are
# doors a crowd is meant to go through and because a doorway a player has to aim
# at is a doorway they will bounce off.
DOORWAY = 8.0
# And how wide an internal one is.
INNER_DOORWAY = 6.0

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

# School: one storey, laid out along a spine corridor with the classrooms on the
# far side of it from the street. Single storey because a stair is the one thing
# in a building that cannot be got wrong quietly -- it either works or the player
# is stuck on a landing -- and the workplace below already has the one that has
# to work. The school gets a second floor when there is a reason to go up there.
SCHOOL_LOBBY = Place("school lobby", -130.0, -113.5, 33.0, 53.0, FLOOR_1, CEIL_1)
SCHOOL_HALL = Place("school corridor", -138.0, -131.0, 11.5, 74.5, FLOOR_1, CEIL_1)
SCHOOL_ROOM_1 = Place("classroom 1", -150.5, -139.0, 11.5, 32.0, FLOOR_1, CEIL_1)
SCHOOL_ROOM_2 = Place("classroom 2", -150.5, -139.0, 33.0, 53.0, FLOOR_1, CEIL_1)
SCHOOL_ROOM_3 = Place("classroom 3", -150.5, -139.0, 54.0, 74.5, FLOOR_1, CEIL_1)
SCHOOL_GYM = Place("school gym", -130.0, -113.5, 54.0, 74.5, FLOOR_1, CEIL_1)
SCHOOL_OFFICE = Place("school office", -130.0, -113.5, 11.5, 32.0, FLOOR_1, CEIL_1)

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
    SCHOOL_LOBBY, SCHOOL_HALL, SCHOOL_ROOM_1, SCHOOL_ROOM_2, SCHOOL_ROOM_3,
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
    ("gate", PROPERTY_X + 3.0, DOOR_LINE, PATH_TOP, "your front gate, on the street"),
    ("crossing", -58.0, DOOR_LINE, PAVING, "the crossing outside your house"),
    ("school", -105.0, SCHOOL_DOOR, PAVING, "the school forecourt"),
    # Just inside the classroom door rather than in among the desks. Somewhere
    # the game can put a player down is somewhere a player can be put down
    # standing up, and the middle of a row of desks is not that.
    ("classroom", -141.0, 43.0, FLOOR_1, "a classroom"),
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
    # The two walks along the street are on the sidewalk, not the road, and the
    # floor stated here is which of the two -- half a stud apart and it decides
    # whether the kerb is a step or a wall.
    ("up the street to school", PAVING, [
        (-92.0, DOOR_LINE), (-92.0, SCHOOL_DOOR), (-105.0, SCHOOL_DOOR),
    ]),
    ("into the school", FLOOR_1, [
        (-105.0, SCHOOL_DOOR), (-120.0, SCHOOL_DOOR), (-134.5, SCHOOL_DOOR),
        (-141.0, SCHOOL_DOOR),
    ]),
    ("along the school corridor", FLOOR_1, [
        (-134.5, 20.0), (-134.5, SCHOOL_DOOR), (-134.5, 66.0),
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
