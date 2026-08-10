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

# Mirrors Config.Enact. An enacted event fans its choices around the player as
# places to stand, and answers the event by walking onto one. A room too tight to
# hold the fan falls back to a panel, which works — but a panel is the thing the
# whole feature exists to get rid of, so a house that can only ever produce panels
# is a broken house rather than a working one.
#
# Nothing is placed at build time, so unlike the delivery points there is no fixed
# spot to check. What can be checked is whether the places events actually happen
# have room for a fan at all: the rug the toddler crawls to, the mat, the phone,
# the doorstep. Those are exactly where the player is standing when a prompt opens.
#
# Whether a body fits where a choice stands is still what decides whether that
# choice can be taken, and it is still measured with the same body clearance
# everything else here measures -- a marker may overhang a table leg, since the
# player stands in its middle.
#
# The drawn size used to be left to the game entirely, and is not any more. Once
# choices could stand at their own distances rather than all at one spread, the
# width of the disc became a placement constraint rather than a cosmetic one: two
# markers on nearly the same bearing must not be drawn wide enough for the near one
# to sit across the walk to the far one. That test needs a width, so MarkerRadius
# and MinMarkerRadius are mirrored below.
ENACT_MARKER_SPREAD = 7.0
ENACT_FAN_DEGREES = 100.0
ENACT_MARKER_RADIUS = 3.0
ENACT_MIN_MARKER_RADIUS = 1.2
# Mirrors Config.Enact.SpreadSteps. A choice that will not fit at full spread is
# tried again nearer the player, one choice at a time, so a check that only tried
# the full spread would report a fallback the game does not take.
ENACT_SPREAD_STEPS = (1.0, 0.75, 0.57, 0.43)
# Mirrors Config.Enact.MarkerDriftDegrees / MarkerDriftStepDegrees. How far a
# choice in an even fan may stray from the slot the fan gave it. Never applied to a
# stanced choice, whose alternatives are its stance's own bearings.
ENACT_MARKER_DRIFT_DEGREES = 45.0
ENACT_MARKER_DRIFT_STEP_DEGREES = 15.0
# Mirrors Config.Enact.MaxRotationDegrees / RotationStepDegrees. The whole even fan
# is turned off the player's facing until the room takes it, smallest turn first.
ENACT_MAX_ROTATION_DEGREES = 180.0
ENACT_ROTATION_STEP_DEGREES = 30.0
# Facings sampled per standing spot. Every 15 degrees rather than every 30, because
# the rotation step is 30: sampling at the same step would hand every facing the
# same set of axes to try and hide any dependence on facing at all. Twenty-four
# samples give two genuinely different sets, which is the honest measurement.
ENACT_FACINGS = 24
# How many headings the *subject* search sweeps. Unlike the fan above, where the
# player's facing is now nearly irrelevant, where the animal ends up depends on it
# entirely -- and the stanced choices are laid out on the line to wherever it went.
ENACT_HEADINGS = 12
# Choices per event. Every authored event has three, so this checks the real case
# rather than Config.Enact.MaxChoices, which nothing currently uses.
ENACT_CHOICES = 3
# Mirrors Config.Enact.ThingReachStuds: how close to the middle of the subject counts
# as choosing the one choice that is placed *on* it rather than on the floor. Matters
# to this file for one reason -- the floor markers have to be kept out of that zone,
# so it is a placement constraint like any other and the check would over-report
# without it.
ENACT_THING_REACH_STUDS = 3.0
# The share of arrivals at an anchor that must get markers rather than a panel.
# Zero was the only bar for as long as the answer was "hardly ever anyway"; now that
# it is 90-100% at every anchor in the house, a bar that only catches *never* would
# let a chair pushed into the wrong corner halve it in silence. Set below the
# measured floor rather than at it, so this catches a regression instead of failing
# on the day it is written. Below about this a panel stops being the exception.
ENACT_MIN_FIT_RATE = 0.85

# Mirrors Config.Scene and the "dog" entry in content/Subjects.luau. An event that
# is about something puts that thing in the room and then arranges the choices
# around it -- so the question "does this house have room for the dog event" is
# two questions, not one, and both of them are geometry this file can answer
# without opening Studio.
#
# This is the harness for a feature whose failure mode is silent by design: a room
# with nowhere to put the animal simply doesn't get one, and the event plays as
# plain text. That is the correct behavior and it is also indistinguishable, from
# inside the game, from the feature being broken. Checking it here is the only
# place the difference shows up.
SUBJECT_BODY_LENGTH = 3.2
SUBJECT_BODY_WIDTH = 1.3
# Config.Scene.ApproachStuds, which is itself derived: MarkerSpread + MarkerRadius
# + 1 stud of clearance. Measured to the animal's near edge, so the distance from
# the player to its middle is this plus half its length.
SCENE_APPROACH_STUDS = ENACT_MARKER_SPREAD + 3.0 + 1.0
# How far beyond its resting place it appears, and the drawn-in retry -- the same
# two attempts, in the same order, that SceneService.begin makes.
SCENE_WALK_IN_STUDS = 8.0
SCENE_RETRY_WALK_IN_SCALE = 0.5
# The arc it may be placed across, centered on the player's facing, and how many
# bearings are tried within it. Straight ahead is tried first and the rest fan
# outward, so the animal arrives where the player is already looking whenever the
# room allows it.
SCENE_ARC_DEGREES = 120.0
SCENE_BEARINGS = 7

# Where the dog event's floor choices stand, in degrees off the line from the player
# to the subject. Mirrors EnactService.STANCE_BEARINGS, one row per choice in the
# order the event authors them.
#
# Two rows, not three, and the missing one is the whole of what changed: "Put your
# hand out" is now stanced "at", which puts it on the animal rather than on a patch
# of floor near it. It needs no floor, so it is not here -- and its absence is not
# only bookkeeping, it is a real easing of the arrangement. The hardest bearing to
# fit was always 0, dead on the line to the animal, because that is the one direction
# the animal is already standing in.
#
# Still a much harder shape to fit than the even fan above, and that is the point of
# checking it. The even fan is 100 degrees wide and entirely in front of the player;
# this needs floor to the side of them and behind them.
#
# Several bearings per choice rather than one, because one did not survive contact
# with this house: measured here, a rigid 0/90/180 fitted at three of the eight
# places the toddler's dog event actually fires. The animal lands wherever the room
# allows, often at a slant, and 90 degrees off a slanted axis points into the near
# wall of a twelve-stud-deep room. Each choice takes the first bearing its floor
# will hold, which is eight of eight -- and this file is where that was found out,
# which is the reason it mirrors the lists rather than just the first of each.
STANCE_BEARINGS = (
    (90.0, -90.0, 65.0, -65.0),
    (180.0, 150.0, -150.0),
)
# Mirrors EnactService.MIN_BEARING_GAP_DEGREES. The regions overlap, so without a
# floor on the gap two choices could be handed near-identical bearings and drawn
# on top of each other.
MIN_BEARING_GAP_DEGREES = 30.0

# Mirrors Config.PocketMoney's handover block and Config.NPC.BodyRadius. Every
# birthday from five to seventeen puts a parent in the room and walks them over to
# hand the allowance across, and where a parent can appear is geometry — so whether
# this house can actually do that is a question for this file rather than for a play
# session that happens to land on the wrong birthday.
#
# The reason it needs checking harder than anything above it: an enacted prompt fires
# at an anchor, so there are eight places in the house to check and they are known.
# A birthday fires wherever the player is standing at the moment it turns over, which
# is anywhere at all. This is measured as a sweep of the whole floor, not of a list
# of spots, because there is no list.
PARENT_BODY_RADIUS = 1.4
# How far out they appear, and the drawn-in retry — the same two attempts, in the
# same order, that PocketMoneyService.spawnSpot makes. The retry exists because of
# this file: the far distance alone stages a parent in 54% of the house, and adding
# the second sweep took it to 83%, nearly all of it upstairs.
POCKET_SPAWN_STUDS = 14.0
POCKET_RETRY_SPAWN_SCALE = 0.5
POCKET_ARC_DEGREES = 300.0
POCKET_BEARINGS = 9
# They stop this far short and hand it over, so the last stretch of the walk is the
# player's own body rather than something blocking it.
POCKET_HANDOVER_STUDS = 4.0
# The share of the house, facing included, where a parent can be staged.
#
# Much lower than ENACT_MIN_FIT_RATE and deliberately so, because the two failures
# are not comparable. A fan that will not fit turns a walkable choice into a panel,
# which is the feature not happening; a handover that cannot be staged still pays the
# money, from the fallback, a retry cycle later. The bar exists to catch the house
# being rebuilt into somewhere a parent can never appear at all -- and, like the enact
# bar, is set below the measured floor so it catches a regression rather than failing
# on the day it was written.
POCKET_MIN_FIT_RATE = 0.75
