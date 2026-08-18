# The map pass — what is done, what is owed

Working notes for the world generators — `tools/gen_city.py`, `tools/gen_town.py` and
`tools/build_street.py`. Everything here is Agent A's; see HANDOVER.md.

Verify every change by regenerating **every** asset and running **both** checkers, because
the town and the street share a frontage and the city and the town share two gates:

    python3 tools/gen_town.py && python3 tools/build_street.py && python3 tools/gen_city.py
    python3 tools/check_town.py && python3 tools/check_city.py

`check_city` has twelve sections and `check_town` eight, and they are the only thing standing
between a geometry change and a town that looks fine in Studio but has NPCs standing in
traffic. They have already caught two hardcoded radii, a road drawn through a building, and
a pair of parallel streets that were reachable and still twice as long to walk as they
looked — none of which a visual inspection would have found. What they do *not* measure is
worth knowing too: a street tree stood in the middle of a finished alley with all eighteen
checks green.

## Done

**1. Road grid widened.** Avenues 14 -> 24, cross streets 14 -> 22, Circle ring 24 -> 34.
Avenue positions were rechosen so `AVE[5] + AVE_W[5]` still lands exactly on 793 — the bay,
beach, baywalk, piers and sports park did not move. Paid for out of block interior, which
went 114 -> 102 studs. **That is now the binding constraint: two house rows at 42 studs
each leave an 18-stud lane. There is no more room in the blocks.** Any further widening
must move the east edge and re-lay the bay.

Two bugs fell out, both the same disease — a number measured from other numbers and then
typed in as a literal:

- `CIRCLE_WP_R = 66.0`, which put all eight Circle waypoints in the carriageway once the
  ring grew. Now derived from `CIRCLE_R_ROAD`/`CIRCLE_R_WALK`.
- `wp_fin_gap1` at a literal x=100, which became the middle of avenue 1. Now derived.

Assume there are more. Any literal coordinate in this file that sits near a road is a bug
waiting for the next widening.

**2. Houses varied by district.** `HOUSE_STYLES` (one set of seven, widths 28-32) replaced
by `HOUSE_TIERS` — three sets selected by `house_tier(band, sband)`, which measures
Chebyshev ring distance from the Circle's junction. Inner: wide (36-42), six of seven
two-storey, setback 0-4. Mid: mixed. Outer: narrow (28-30), five of seven single-storey,
setback 8-12. Gives 12/36/12 houses and keeps the total at exactly 60, which the route
checks require and which has no slack.

**3. Shops made distinguishable — the legibility half.** The root cause was not
"they need more variety". `street_fittings(name, x0, x1, z0, z1, front, kind)` took the
shop's *trade* as `kind`, but both call sites passed the **front type** — `"awning"`,
`"shop"`, `"garage"`. So every branch written for a cafe, a restaurant, a pizzeria, an
office, a vet, a bank, a post office and a laundromat was **unreachable**, and all
eighteen main-street shops plus all eight north-strip shops were furnished with the same
supermarket gondola. They were not merely similar — they were the same building inside
and out, and had been since the function was written.

Fixed by saying the two things separately. `SHOP_FRONTS` now holds one row per storefront:

    (trade, width, storeys, awning, glass)

Four cues, in descending order of how far away they read: **awning** colour (five of them,
far apart in hue), **roofline** (7 of 18 main-street shops are now two storey, with an
upper window band at a different rhythm from the shopfront), **frontage width** (28–40,
was a flat 30 everywhere), **glass cut** (`full` / `high` / `narrow` / `none`). Interiors
now have twelve trades: aisles, wall canyons, clothing rails, timber stacks, salon mirrors,
a pizza oven, a dispensary counter, a near-empty studio.

Two bugs fell out of it, both the same disease as last time — a number measured once and
then frozen:

- `MAIN_STREET`'s last band claimed z 818..946, but the cross street's north pavement
  ends at **826**. It was only ever safe because three equal 30-stud shops left a 9.5-stud
  gap that pushed the first one clear by a stud and a half. The moment widths varied, the
  vet's south wall went 1.7 studs into the kerb. **`check_city` check 7 caught it, by
  name, with the offending part and the exact overlap.** Band corrected to start at 826.
- The nameplate ended at a literal `24.0`, which was `CEIL_1 + SLAB + 7` measured once.
  Now `SIGN_Y0`/`SIGN_Y1`, derived.

And one placement bug: the north strip's counters were built against the *east* wall
regardless of their south-facing doors, so their tills sat against a wall the player never
walked to. `counter_at()` now derives the counter from the front, so it always straddles
the place point.

**4. The skyline is centre-tallest.** Owner: *"the downtown center should have the highest
buildings so around the avenue make those a bit taller than everything else."* It was not.
`fade_office_band` set storeys as `6 - sband * 2` — a pure south-to-north ramp off the
financial district — so the tall end of the city was its *southern edge* and the blocks
either side of the Circle were four storeys, shorter than their neighbours. Standing on the
Circle you looked outward at buildings taller than the ones beside you.

Now radial, off the **same Chebyshev ring `house_tier` uses**, so one rule shapes both
districts: `FADE_STOREYS_BY_RING = (7, 5, 4)`, and within a block the tower nearer the
Circle takes the extra floor (`inner = 0 if x0 >= CIRCLE_X else 1`).

`CIRCUS_STOREYS` went `(6, 10, 6)` → `(8, 14, 8)`. The number that had to be measured was
the financial district's **mast**, not its roof: roof 206.5, mast 213.5. At 13 storeys the
Circle won by two studs, which from the ground is a tie. 14 puts it at 231.5.

Measured off the generated file:

| zone | tallest |
|---|---|
| the Circle | **231.5** |
| financial district | 213.5 |
| everything else | 118.5 |

**5. The civic precinct got a road, a shape and two parks.** Owner: *"near the town hall,
all the buildings are identical in a line... theres no road on the buildings behind the town
hall so maybe invert their side... swap some the shops, 30 is too many, switch them out for
police stations, fire fighter stations."* All four halves of that, in order:

- **The road.** The precinct (z 968..1116) had no carriageway in it at all. Fixed as a
  *loop*, not a spur, because dead ends are a standing complaint: avenue 5 carried north up
  the east side (`PrecinctAve`, x 769..793) and a service road along the top
  (`NorthSvc`, z 1124..1146) T-ing into both it and the connector. Four things had to be
  carved back out of the way — the civic front pavement, `CIVIC_X1`, `PrecinctPaving`, and
  the forecourt/promenade waypoint loop, which had been bounded by `PRECINCT_X1` and put two
  waypoints in the new carriageway. Waypoint chains laid on both new pavements, because
  `ROUTE_LINK` is 70 and a north-facing door was 68 studs from `wp_promenade` before any x
  offset.
- **Inverted sides.** The strip's north wall used to face 400 studs of nothing. The three
  services that need a vehicle to reach them — an engine bay, a police yard, a depot — now
  turn round and open onto the service road; the retail keeps its south front where the
  footfall is. That alternation is also what stops the row reading as one wall.
- **Shops swapped for services.** `north_shop_2/4/6` are now NORTH FIRE STATION, NORTH
  POLICE POST and CITY DEPOT. **Place point ids are unchanged** — `north_shop_1` is named in
  `Townsfolk.luau:2693` and `Config.luau:2697` and the rest are addressed by id everywhere.
  Three fewer of the 30 jobless points, and three that a `Jobs.luau` row is obvious for.
- **Not identical any more.** Both rows had every building the same width and the same
  height. Widths are now solved from a *weight* per building (`solve_row`) so the row still
  fills its band exactly however the band moves — civic row 37.4 → 56.7 studs, north strip
  47.9 → 86.9 — and `storeys` is per-building. `storefront` was capped at two storeys
  (`CEIL_1 if storeys < 2 else CEIL_2`); it is now `storey_top(n)` and builds a floor and a
  window band per storey, so City Hall tops out at 78.5, the hotel at 49.5, and the row runs
  24.5 / 33.5 / 49.5 / 78.5 instead of one flat 24.5. `CIVIC_GLASS` gives each kind its own
  window cut, and `GARAGE_BAYS` gives a fire station two shutters with a door between them,
  which is the silhouette.
- **Parks.** Two pocket parks cut clean through the north strip (`north_green_w`,
  `north_green_e`) with a path at pavement height running the full depth — they are through
  routes, not lawns to look at. The three civic passages are planted rather than paved.

Three bugs fell out, and the first two are the same disease as always:

- `CITY_Z1` was 1120, the old top of the grid, so the new service road and the connector's
  last 28 studs were **standing on nothing**. Their own slabs are solid, so all ten checks
  passed; the only symptom would have been open sky under the kerb.
- South-facing awnings projected **inward**. `_shopfront` hung the awning off `f1`, which is
  the outer edge for a north front and the *inner* edge for a south one — so every awning on
  the north strip was an interior canopy, over the customers instead of over the pavement.
- The whole north strip was inside one `NorthStrip` model, and `check_city` walks outermost
  models — so the eight shops were a single 668-stud box and check 5 could not see an overlap
  between two of them. Each building is its own model now. This mattered a lot more the
  moment their widths stopped being eight equal slices of the band.

Measured off the generated file: 9131 parts, all ten checks pass, both places build.

**8. The corner shop — built in the road, and moved.** It was first put in the gap between
the player's plot and number 14, on the reading that a stale comment (`z 78.1` where
`House.rbxmx` actually reaches `56.8`) had been fencing off the largest bare frontage on
the street. Both its bounds were derived rather than typed, and both derivations were
right. It still had to be torn down and moved, because the gap is not frontage: it is the
window the **gate road** leaves town through, and a 44-stud building was standing across
the only link between the town and the city.

Nothing in `gen_town.py` could see it. The road is drawn by `gen_city.py`, into another
asset, off another file's constants. `check_city` check 7 reads every asset's walls against
the city's streets and catches it in one line — and it was not run before the commit. Two
fixes, because the procedural one alone is worthless:

- `GATE_Z0/Z1/WALK` and the derived `GATE_CLEAR` moved into `world_plan.py`, which both
  generators already import. `gen_town.py` now asserts the shop clears it. The exclusion is
  a fact the file holds rather than one somebody has to remember.
- The interior was written in world coordinates, so moving the building would have meant
  retyping every fitting one at a time. It is now written as depths from the shop's own
  south wall. Verified faithful by regenerating at the old bounds and diffing the
  `CornerShop` group against the committed file: identical but for float noise.

It now stands on the east frontage opposite the bakery, one street south, in the same
17.2-stud shape — too narrow for a house (the four on this street are 34 deep) and exactly
right for a shop. Facing the bakery is a gain rather than a consolation: two shops across a
road read as a small parade, where one dropped into a gap reads as an intruder. Its north
edge keeps the row's own spacing from number 20.

Built as a **service spine and a customer floor**: the north strip runs from the back wall
to behind the counter and is the only way to reach either the stock at the far end or the
till at the front, so working the shop is a lap of the building rather than a stand at one
spot. Customer aisles hang south of that spine, against a glazed flank — glazed on that
side because the customer floor is what is behind it, the north flank backing onto a staff
corridor and staying solid. The signed fascia wraps west and north, north being the face a
player walking down from home sees from a hundred studs off.

That plan is an argument, not a decoration — the activity law wants a consumable that
forces traversal every 40–60s, and putting the crates forty-one studs from the till is
what makes the run exist. The verb it is a stage for is spec'd in section A below, and it
is **not** built here: it is a job, and jobs are Agent B's.

Nothing in the shop is tagged. A tag no service reads is orphaned code by this tree's own
rules, and tagging is a one-line change the day the verb lands. One place point,
`corner_shop`, stood in front of the counter where every other "at the counter" point in
town is stood.

Measured off the generated file: `Town.rbxmx` 687 parts in 17 pieces. Flood-filled from the
doorway at a body half-width of 1.40 — the figure `read_house.py` holds routes to — 100% of
the free floor is reachable and every station is on it.

That probe caught one thing the first one missed, because the first one only looked at the
floor plan. The counter top overhung 0.4 studs on **both** sides, leaving 2.6 studs of
standing room behind the counter at chest height over a base that is 3.0 clear — under the
2.8 a walking body needs, and invisible from above. A capsule does not duck. The overhang
is now on the customer side only, which is where a person leans anyway.

**9. `City.rbxmx` is reproducible again.** Regenerating it twice in a row produced two
different files. `mall_shop` picked its wall tone with `STORE_WALLS[hash(pid) % 10]`, and
Python randomises string hashing per process — so the mall's eight shopfronts were
repainted on every run and the one generated asset in the tree could not be diffed. Now
`zlib.crc32`. Same class as the stale bounds above: a value that looks derived and is
actually arbitrary. Verified by three consecutive runs to the same md5.

**10. Streets are no longer all one width** — see section D, which is now done. `AVE_W` and
`CS_W` are per-street lists, four of the twelve streets narrow, and the six ways a future
edit could break something a thousand studs away are assertions in the generator rather
than things you find out from the beach.

**11. The west estate — section E's north district, built.** Section E was resolved as
option (c): industrial and low-rise sprawl go west, docks stay east on the bay. This is the
first half of that — light industrial and trade yards at x −1024..13, z 339..1148, fronting
`ConnPavW`.

*Why there.* Measured, not chosen: `ConnPavW` was a single unbroken 809-stud slab of footway
against `ConnEPavE`'s seven runs. It was a pavement with nothing on either side of it to
cross to. The district gives it four real junctions and something to serve. It abuts the
city, where the jobs are, and stands ~1000 studs clear of the town's houses — which is why
it is light industry and trade counters rather than more port: the heavy works is on the bay
and stays there.

*Built inside `gen_city.py` rather than as a new `West.rbxmx`*, which is a deviation from
the spec and was taken on two measured grounds. The `ConnPavW` carve list is a line in
`gen_city.py` and is unreachable from another file — a second generator could not have put
those four junctions in. And five-plus helpers (`road_ns`, `walks_ew`, `works_shed`,
`storefront`, `tree`) would have had to be duplicated, in a tree where `tree()` had already
been written three times.

*The plan is derived, not typed.* Row depths give street positions; column widths give
avenue positions; the last row and the common's width fall out as remainders, each guarded
by an assertion that fires. Two of those assertions earn their place: one bounds the
common's width, and one asserts no estate street band overlaps `GATE_CLEAR` or
`NORTHGATE_CLEAR`, because two overlapping gaps in one `carve` list silently remove more
pavement than either asked for.

`MAP_EDGE` came out of this. `default.project.json` declares the baseplate once as
`[2048, 20, 2048]`, and every generator that needed to know where the world ended typed
1024 for itself. It now lives in `world_plan.py` with check 9 reading the project file and
asserting the two still agree — a transcription is only acceptable with a gate on the cache.

*Two coplanar-surface bugs were found by reasoning rather than by a checker*, and neither
would have been reported by anything in this tree: the common's pasture overlapped
`WestGround` at the same top height for its whole 400-stud width, and the farm track was
drawn *below* the pasture it was laid on, which made it invisible. A surface that loses to
the ground it is laid on is a defect with no symptom in any gate here. Both are fixed by
tiling rather than by lifting.

*And building it exposed a hole in the gate that certified it* — see 12.

**12. Check 11 was not looking at the largest buildings in the city.** The estate added 12
place points and the destination count rose by 5. `DOOR_SLACK` was 3.0, and every
`works_shed` place point stands `SHED_APRON / 2` = 5.0 studs out on its loading apron, so
**no shed anywhere was a destination**: not the six new ones, and not the ironworks, sawmill,
turbine hall or transit shed either, which had been exempt since the day the works was built.
Check 11 was green partly because it was not asking about them.

The standoffs are two clean populations — 197 points inside their own walls, 7 at 2.0 out (a
storefront door), 9 at exactly 5.0 (a shed apron), then nothing until 36. `DOOR_SLACK` is now
5.0 and the count is 173. All nine sheds pass at 14.0 studs from a carriageway against a
limit of 32, and lowering the limit to 13 now reports all nine, where before it reported them
at no limit at all.

`DOOR_SLACK` is a **matcher, not a threshold**, and that decides the value. `ROAD_ACCESS` is
set in the middle of a measured gap and is deliberately loose; a matcher has to attribute
each point to exactly one building, so it is set at the largest standoff any generator
actually uses. If that is ever exceeded the answer is to move the point, not to widen the
slack — so check 11 now also asserts the attribution is unique, and it fires at 9.0 where
`dining_1` reaches the next restaurant along.

That assertion was nearly shipped wrong. Written as "one point, one model" it failed at 5.5
on `est_electrical`, which turned out to be Kemp Electrical's *Structure* and *Fittings* —
one building emitted as two groups, not two buildings. The invariant is geometric, not
nominal: the models a point matches must overlap one another. The rejected alternative was a
regex stripping `Structure|Fittings` from group names, which is a guess about naming rather
than a statement about geometry, and would have been wrong again for the self-store office
that stands inside its own yard's shed footprint.

*What is deliberately still not checked:* nine destinations have no walls at all — the park,
the baywalk, the marina, the playground, the four sports pitches and the estate's field gate.
They stand 14 to 341 studs from a carriageway and every one of them is right: you walk to a
tennis court across a park, and the field gate opens onto a farm track reached by its own
waypoint chain. Holding them to `ROAD_ACCESS` would report nine correct things on the first
run, which is how the earlier "a model with walls" attempt died. Measuring point-to-road
instead of bounds-to-road does not rescue it either — that reads 62 studs for the four north
shops, which are served by a road running along the back of them.

### 13. The south-west band cannot be connected without moving one town house

Section E's second half — the low-rise sprawl south of the west estate — is **measured and
not built**, because the measurement says it cannot be built honestly yet. Recording the
numbers so nobody has to take them on faith or measure them again.

The band is x -1024..-296.1, z -500..339: 728 by 839 studs. Its east neighbour is the town,
and the town's west boundary is the back row's back gardens. That row is **unbroken**: 15
houses, x -290.1..-246.1, on a 40-stud pitch — 34 deep with 6-stud gaps — running z -386..208.
594 studs of wall, and the widest gap in it is 6. One house sits at z -26..8, squarely across
the latitude of `AlleyWorkplaceSchool` (z -10..-2), which is otherwise the natural crossing.

So the band's only road connections are its ends: the estate at z 339, and a loop around the
town's south tip. Modelling a district spine at x -601 (the southward continuation of
`EST_AVE[-1]`, derived rather than picked) with waypoints at `ROUTE_STEP`, against the real
1455-point route graph and the real spawn:

| connection | worst detour | where it lands |
| --- | --- | --- |
| north only, into the estate | **2.26 FAIL** | (-601, -318) — walks 1532 for 678 |
| north + a leg round the town's south tip | **2.08 FAIL** | (-601, -56) — walks 1269 for 610 |
| north + one crossing of the back row at z -6 | **1.42 PASS** | (-601, -450) — walks 1056 for 745 |

Two things fall straight out of that table. **The south leg is worthless** — it moves the
worst point from the district's south end to its *middle* and buys 0.18, because the failure
was never at the ends. And **one mid-latitude crossing is both necessary and sufficient**,
with 0.48 of headroom at the alley's own centreline.

The crossing has room to move: swept against `MAX_DETOUR`, any latitude from **z -365.6 to
between 200 and 240** passes. That is ~575 studs of freedom, so this is a cheap ask and not a
knife-edge one. The best of them is the alley's, both because it is near the spawn's own
latitude and because the town already has a road there — continuing `AlleyWorkplaceSchool`
west from the return road's west kerb (x -225) to the town's west edge (x -296.1) adds no new
junction. It costs exactly one house: the one at z -26..8.

**That house is in `gen_town.py`, which is not this lane's file.** The plan of record was to
route around the problem with a clear-band constant in `world_plan.py`, the way `GATE_*`,
`SOUTHGATE_*` and `NORTHGATE_*` already do. The measurement kills that plan: a clear band
reserves space, it does not remove a house, and the row has no gap to reserve. So the district
is specced and stopped rather than built, and the ask is one line — *move or drop the back-row
house at z -26..8 and carry the alley west* — for whoever owns that file.

### 14. Check 12 links straight through buildings — found, not yet fixed

Falling out of the above, and worth more than the district was. Check 12 builds its route
graph by joining any two place points within `ROUTE_LINK`. It has no notion of anything
standing between them. A probe point 14 studs west of the town's back fence, at the spawn's
own latitude, scores **1.01** — because it links to `home_b6` at (-248.1, -9), and that line
runs through the living room of the house at z -26..8.

So the check would have passed a west district whose "connection" to the town was a hop across
six back gardens, a fence and a house. That is this tree's signature defect — *a gate that is
green because it is not looking at the thing* — sitting inside the gate that was written to
catch the last one.

Measuring how bad it is: **505 of the current route graph's edges cross a ground-floor wall**
belonging to neither endpoint. Almost all are benign — `cafe -- pizzeria` clips the terrace
neighbour's wall where the real walk along the pavement is five studs longer. A raw
"no edge crosses a wall" assertion would report hundreds of correct things on its first run,
which is exactly how check 11's "a model with walls" attempt died. Deleting those edges and
re-running changes the shipped world **not at all**: 0 unreachable, worst detour still 1.51 at
`wp_bridge_2`, same top five. The pavement waypoints already carry every route; the
wall-crossing edges are pure redundant shortcut.

But deleting them does *not* catch the probe, and the reason is the interesting part. A door
point stands 2 studs *inside* its own front wall (the -2.0 convention behind `DOOR_SLACK`), so
the endpoint's own building has to be exempt or every door edge is blocked — and that exemption
is what lets a line cross the whole house to reach a door on the far side. Pushing each door
out to its building's nearest face removes the need for any exemption: 468 of 1455 points stand
inside a building, and with them pushed out the probe is correctly **unreachable at every
latitude along the wall**.

That version is not free, and that is why it is not committed. It reports the shipped city at
**1.96 against a limit of 1.9**, with 5 points stranded: `apt_4_1`, `wp_works_ironyard`,
`wp_works_depotyard`, `wp_civic_passage_0` and `wp_civic_passage_2`. Three of those five are
named for passages and yards — gaps between buildings — and the wall boxes are AABBs, which
check 11's own comment already records as *bigger* than the slab they came from. So the
strong suspicion is AABB inflation closing gaps that are really open, not five real defects.
Five nameable candidates is a tractable problem, unlike 505; it just needs to be worked
through one at a time before the check can be turned on.

## Owed, in the order I would do it

### A. Shops — the *function* half, which is a spec question, not a build one

The legibility half is done (above). This is the rest of *"just code for them to be
functional"*, and I stopped before building it on purpose, because the answer decides
whose code it is.

**What a shop can already do**, measured against `Jobs.luau` and `Tills.luau` rather than
assumed:

- **Work there.** 45 of the city's non-residential place points have a `Jobs.luau` entry.
  That is the main existing seam and it is not broken — all 7 job place ids that are
  missing from `City.rbxmx` (`bakery`, `clinic`, `garage`, `gym`, `library`, `office`,
  `store`) resolve against `Town`/`Street`. Nothing is dangling.
- **Rob it.** Exactly 4: `pharmacy`, `electronics`, `clothing_store`, `gas_station`.
  `Tills.luau`'s own header argues *at length* that this list must stay short — a spree
  should be a route, and a town where some doors are worth something is a town with
  knowledge in it. **Do not lengthen it to make shops "functional".** That fights a
  decision already made in writing.

**What has no function at all** — 30 place points, and this is the honest list:

    hardware  optometrist  pet_shop  museum  marina
    north_shop_1..8        mall_foodcourt/gaming/jewelry/kids/shoes/sports
    dining_2..6            office_1..3

**The gap, stated plainly: there is no customer verb.** A player cannot buy anything in
any shop in this game. `Interact.InteractKind` is `Person | Event | Station | Till | Vault
| Boss | Fight` — every one of those is either working, robbing, or fighting. Nothing is
*shopping*. So "make the shops functional" is not a gap in the map at all; it is a missing
mechanic, and building it means a new interact kind and a spend path.

Three reasons not to just build it:

1. The economy agent owns `CarDealerService` and `HouseService` — both are purchase flows.
   A third, parallel "buy a thing from a shop" path built here is the exact duplication
   `HANDOVER.md` forbids.
2. Per the activity design law, a shop you walk into and click "buy" is an idle payout pad
   with the sign changed. If shops get a verb it needs to be something the player *does*.
3. `check_city` wants ≥30 career buildings, so the count cannot be trimmed to suit.

**So this is spec'd back rather than built.** The question for the owner is one line:
*when a player walks into a shop, what do they physically do?* Everything else follows from
that. Filling the 30 jobless points with more `Jobs.luau` rows would raise the number of
"functional" shops without adding a single thing to do, and is not worth doing.

#### The answer, spec'd: fetch and bag

Asked for a verb, this is the one. It is written against the seven requirements in
`docs/activity_design_law.md` one at a time, because a shop minigame that fails any of
them is the job system with a different sign on it.

A customer comes to the counter and names two to four things. You read the order, run the
aisles, pick them up, bag them at the counter and hand the bag over.

1. **One verb, one commit, one undo window.** The verb is *fetch*. The commit is handing
   the bag across the counter; nothing is scored until then. The undo is pulling an item
   back out of the bag and swapping it — available right up to the commit, and paid for in
   the only currency the activity has, which is the customer's patience. An undo that costs
   the thing you are protecting is an undo worth having.
2. **Two queues, each at about half load.** Customers at the counter, up to three deep,
   each with a patience bar. *And* the shelves: every shelf face holds a stock level and a
   face at zero cannot be picked from, so restocking is its own queue with its own clock.
   Tuned so neither one alone fills the shift — serving only customers strands you on an
   empty face, stocking only shelves strands the queue. The decision between them is the
   game.
3. **A consumable that forces traversal.** Stock, and the traversal is the length of the
   building. Crates live in the bay at the back, forty-one studs from the till, and one
   crate is worth a fixed number of restocks. Tune the crate so it empties every 45s or
   so. This is why the floor plan puts the stock at the far end — see the comment in
   `gen_town.py`; a shop with its stock behind the counter passes every other requirement
   and is still a game about standing still.
4. **Soft failure, never binary.** Patience is a multiplier on the payout, not a pass. A
   customer who runs out does not vanish: they take whatever is in the bag, pay for that
   much and tip nothing. A wrong item is handed back, which costs time, not the order.
   Nothing in the shop can be failed, only done slower and for less.
5. **Escalation changes the space, not the numbers.** Five levels, and not one of them is
   a faster arrival rate. L1 two aisles, orders of two. L2 the chiller opens — a third
   destination, and the only one that costs a beat to open. **L3 the shelf plan is
   reshuffled overnight**, which kills the route the player memorised and is the best
   escalation on the list because it attacks their knowledge rather than their reflexes.
   L4 a pallet lands in the north spine mid-shift and the one service corridor narrows. L5
   a second register opens and the queue splits.
6. **Progression widens the player's own tolerance.** The basket. You start able to carry
   one item, and buy your way to two, three, four. That is the size of what a player can
   hold in their head, made physical: at one it is a trip per item, at four it is a route
   problem. The player watches their own capacity grow, and route-planning is the skill
   that grows with it.
7. **Same input, different opponent.** Five customers, one verb. *The list* — four items,
   long patience, a pure route problem. *The dawdler* — orders one thing, adds a second
   while you are gone, and punishes over-optimising. *The rush* — two items, very short
   fuse. *The kid* — pays in coins, so the commit itself takes an extra beat and bagging
   early starts to matter. *The regular* — always the same order, which is the one you can
   have bagged before they reach the counter. That last one is the discovered technique
   the law asks to leave room for, and it is not taught anywhere.

Supporting rules, also from the law: reward $7–$25 an order with the tip carrying the
patience multiplier; a shift is *N orders served*, not a clock; the 3-dot prompt over the
shopkeeper starts it, per the interaction grammar.

**The degenerate strategy, audited before it ships.** The exploit is to ignore the shelves
and serve only orders you can already fill. It fails because orders are drawn from the
whole floor, so one face at zero blocks roughly every second order within a minute. The
second exploit is parking at the counter with a basket of the most common item; the L3
reshuffle and the dawdler both break it.

**Whose code this is.** The stage is built — see "Done" — but the service is not, and it
must not be built here. Fetch-and-bag is a job: it lands in `WorkService`,
`content/Jobs.luau` and `JobTasks.luau`, and all three are **Agent B's** by `HANDOVER.md`.
This section is the hand-over, not the start of one. Agent A's remaining obligations to it
are geometry and tags, both of which are one-line changes on request.

### B. The spawn house is alone at the edge of the world — *B1 and B2 built; B3 deferred by the owner*

**Built 2026-08-17.** Two roads, three houses, a back gate, one waypoint that turned out to
matter more than any of them, and a new check. What follows is the spec as it was written,
then the build notes; the spec is left standing because the reasoning in it is what the
build was measured against.

**The thing this actually found.** The complaint was "the spawn house is at the end of the
map". The defect underneath it was that **the spawn could reach 23 of 620 place points, and
not one of them was in the city.** The near sidewalk had no point on it outside the player's
own front gate, leaving a 76-stud hole — six studs over `ROUTE_LINK` — which cut the spawn
off from the north half of its own street, and the only road into the city left from that
half. Every existing check passed: the city was one component and it did touch the town, at
the far end of a chain the player was not standing on. "At least one" was the bug. One line
in `PLACE_POINTS` (`wp_east_home`) fixed it; `check_city` check 12 is what stops it coming
back. See "the check that was missing" below.


The spawn is at `(8.0, 1.14, -21.5)`, standing on `House.rbxmx` — so this is the *town*,
not the city, and it is `tools/gen_town.py` / `world_plan.py`, not `gen_city.py`.
Confirm with an occupancy map before designing anything:

    python3 - <<'EOF'
    import re, collections
    pat = re.compile(r'<CoordinateFrame name="CFrame">\s*<X>([-\d.eE+]+)</X>\s*<Y>[-\d.eE+]+</Y>\s*<Z>([-\d.eE+]+)</Z>')
    pts=[]
    for f in ('City','Town','Street','House'):
        pts += [(float(a),float(b)) for a,b in pat.findall(open('assets/%s.rbxmx'%f,encoding='utf-8').read())]
    CELL=64; g=collections.Counter()
    for x,z in pts: g[(int(x//CELL),int(z//CELL))]+=1
    xs=[p[0] for p in pts]; zs=[p[1] for p in pts]
    for cz in range(int(max(zs)//CELL), int(min(zs)//CELL)-1, -1):
        print("%6d %s" % (cz*CELL, "".join(("." if g[(cx,cz)]==0 else "#")+" "
              for cx in range(int(min(xs)//CELL), int(max(xs)//CELL)+1))))
    EOF

This is the same tool that found the real void (below) and corrected a wrong assumption
about where it was. Measure first.

**Measured 2026-08-17. There is 74.5 studs of bare grass back there, and then a
134-stud office tower.**

Read the retraction below before the finding: the first version of this entry said there
was no ground behind the house at all, and it was wrong.

The strip. The house's back wall is at **x 32.5** — rotation-aware `max(x1)` over every
part in `House.rbxmx`. The nearest built thing east of it is at **x 107**: the portico of a
financial-district tower whose parapet tops out at **y 134.5**, with a second one of 86.5
behind it at z -105..-51. Between the two there is nothing at all, over roughly
`x 32.5..107, z -112..56` — about 75 studs deep and 170 long, all of it flat grass.

So the complaint is right and the phrase is exact: it is empty. What the measurement adds
is *what it is empty between*. A player who walks around their own house is looking at the
back of downtown across three-quarters of a block of mown nothing, with no fence, no
change of surface and no boundary of any kind to say where their garden stops being theirs.

**And the plan above had the file wrong.** This is not `gen_town.py`. The ground behind
the house is `CityGround1` — `gen_city.py`, `(CITY_X0, ...) = (8.0, ...)`, grass, top y 1.00
— which meets the town's `GrassEast` (grass, top y 1.02) at x 8.0 on the same two-hundredth
step the whole world uses for a seam. The town's grass stopping at x 8 is correct and
deliberate, not a shortfall. The land behind the player's house belongs to the city.

That matters for who does the work, because `EAST_X1 = 8.0` in `gen_town.py` and
`CITY_X0 = 8.0` in `gen_city.py` are two literals in two files describing one seam, each
carrying a comment that points at the other. They agree today. Nothing makes them agree,
and this is the shape of defect this tree keeps being repaired for — so whatever lands here
should put that seam in `world_plan.py` once, where both generators already import from.

**Correction, 2026-08-17 (evening): the strip is 40 studs, not 75, and Avenue 0 is in it.**

The 74.5-stud figure above is the distance to the first thing that stands *above* y 3. A
road does not. `Ave0Road` is a 24-stud arterial at **x 79..103**, and it runs the full
height of the map, `z -434..200`, forty studs from the player's back fence. With its
pavements (`Ave0PavW` x 73..78.2, `Ave0PavE` x 103.8..109) it occupies half of what this
entry called a void. The actual bare ground behind the house is **x 32.35..73 — 40.65
studs**, which is one street wide and not one stud more.

Same defect as the retraction below, one layer down: a probe that filters for obstructions
cannot see a road, and I read "nothing is in the way" as "nothing is there".

**What is actually wrong back there is not emptiness. It is that the town has no way onto
that road.** The gate road (`z 64..78`) runs east from the town's main road and stops at
`CONN_X0 = 19`; the connector runs *north* from `CITY_Z0 = 60`. Avenue 0's west pavement is
continuous from z -430 to z 196 except at its own cross-street junctions, and nothing joins
it from the west below z 200. So the walk from the spawn house's back garden to the road
forty studs behind it is: out the front gate, north up the main road, east along the gate
road, **140 studs north up the connector to cross street 1 at z 200**, east to Avenue 0,
then two hundred studs back south to stand level with where you started. Call it six hundred
studs to cross forty.

`check_city` does not catch this and is not wrong not to. Check 8 measures the connected
road surface *inside* the city; check 11 measures every city model's distance to a
carriageway. Both pass. Neither of them asks how many ways there are from the town into
the city, and the answer is one.

#### The spec — "populate around the spawn house"

Asked for: a theme park (good, farther away, **explicitly deferred**), a few more
medium houses, roads back into the main city, generally more populated. Three parts, in
the order the measurements say they should be done.

**B1. The Backs — a street down the town's east edge.** Fills the whole 40.65-stud
corridor, because that is exactly what fits in it.

    west pavement   x 32.35 .. 38.1     against the plot's rear fence
    carriageway     x 38.1  .. 61.1     23 wide == ROAD_DEPTH, the town's own road width
    east pavement   x 61.1  .. 73.0     11.9 wide == NEAR_WALK_X1 - NEAR_WALK_X0,
                                        meeting Ave0PavW's west face at 73.0

Every one of those is derived: the west edge is `PLOT_X1`, the east edge is Avenue 0's
pavement, the carriageway is the town's road width, and the two pavements are what is left.
`73.0` is a `gen_city.py` number that `gen_town.py` would need, so it goes in `world_plan.py`
with `CITY_X0` — which is the same duplicate-literal problem this section already flags.

- **North end**: into the gate road / connector junction at `z 60..78`. The Backs'
  carriageway (38.1..61.1) and the connector's (19..42) overlap by 3.9 studs, which is a
  bad junction, so the junction is paved as one square, `x 19..61.1, z 60..78`. Gate road in
  from the west, connector north into the city, Backs south along the town's edge. Cafe
  Aster's west wall is at x 44.4 from z 64 — it currently fronts a pavement shared with the
  connector and would front this junction instead, which is better, but **it does mean the
  Backs cannot simply run north past it**; z 60 is the hard north end.
- **South end**: turns east at `z -136..-106` and joins Avenue 0. That is not a chosen
  number — it is the existing gap in `Ave0PavW` where cross street W2 already crosses, so
  the Backs lands on a junction that is built rather than making a new one. No dead end,
  and check 11 stays green by construction.
- **What it buys**: the six-hundred-stud detour becomes forty studs, and the town gets a
  *second* road into the city. Today it has one, and that one is a 14-stud lane.

**B2. Houses — and they cannot go behind the house.** 40.65 studs holds a street and
nothing else, and the block between the Backs and Avenue 0 is 11.9 studs of pavement. So
"a few more medium houses" is not a thing that can be built where the complaint points.
Where it *can* be built is the town's own street, which is where the player actually walks:

- **East frontage, `z -328..-153.2`** — 174.8 studs of bare grass south of the corner shop,
  on the same `HOUSE_X0..X1 = -42..2` line as houses 14/16/18/20. At the row's existing
  pitch (34 frontage + `NEIGHBOUR_GAP` 6) that is **four houses**, numbers 22–28.
- **West frontage, `z -280..-204`** — 76 studs south of the garage, above where the far
  sidewalk hands the kerb back at `FAR_END_Z`. One or two buildings on the `FRONT_X` line.
  Better used for something that is not a house; see B3's front door.

Four to six new buildings on the street the player walks down every day will read as
"more populated". Four houses in a field behind a fence will not.

**B3. The theme park — deferred, and here is what "functioning" has to mean.** Site: south,
past the road loop. The main road's east leg already runs down to `CURL_Z = -290` and the
loop bottom sits at `z -313..-290`, so the park's front door is an extension of a road that
already points at it, on new ground below `z -328`. Far enough to be a trip, walkable, and
it does not collide with stage 2 (west, `x -1024..-280`) or the works district (east of
`x 119`, `z -426..-142`).

Before any of it is built: **a ride the player watches is a prop, and a ride that pays out
for standing on it is the idle-payout pad the activity design law exists to forbid.** Each
ride needs the same shape as any other activity — a queue you join, a boarding verb, an
input while it runs, and an outcome that could have gone the other way. A park with four
rides and one verb between them is worse than a park with one ride that is actually a game.
That is the spec to write before the geometry, and it is why this is "save it for later"
rather than "build it last".

**Open, and needs an answer before B1 is built:** the rear fence built for option A seals
the plot so the front gate is the only way off it. With the Backs behind it the fence is
right — it becomes a garden fence onto a street instead of a wall against a field — but the
"front gate is the only link" reasoning that justified it is now overruled, and the plot
wants a **back gate** onto the Backs' west pavement. Otherwise the player walks the length
of their own garden to reach a road six studs from their back door.
*Answered: built, `BACK_GATE_Z0/Z1`.*

#### What was built

**B1, the roads.** Both land on mouths that already exist in avenue 1's west pavement, so
neither adds a junction tile or a carve-list entry and checks 8/10/11 stay green by
construction.

- **Southgate** — works cross street 1 (`SOUTH_CS[1]`, z -316..-294) carried west to the
  town road's east kerb. The town's **second** link, straight into the works district where
  the job place points are.
- **The Backs** — north-south, `x 44..67`, `z -132..56`, filling the corridor behind the
  spawn plot, with an elbow east onto avenue 1 at each end. Its 11.5-stud west pavement
  fronts the plot's rear fence. **Reverted the same day — see "The Backs was the same
  street twice" below.**

**The back gate.** `INNER_DOORWAY` wide, not `GATE_HALF`. Written independently it came out
at 3.1 studs of clear gap — narrower than any interior door in the game, a number that looks
fine in a plan and plays like a turnstile. `DOORWAY`/`INNER_DOORWAY` moved up
`world_plan.py` to sit with the gate constants, because every opening a player walks through
wants to be one of those two numbers. A point sits outside it — `wp_backs_gate` then,
`wp_green_gate` now: a gate with no point on the far side is a hole in a fence that no
route uses.

**B2, three houses**, numbers 22/24/26, on the east frontage below the corner shop. Not
four, and not typed: `SOUTH_ROW` reads the depth, pitch and numbering off houses 14/16 and
lays plots until the next will not fit, so the frontage decides the count. It steps *over*
`SOUTHGATE_CLEAR` rather than stopping at it — stopping would silently shorten the row if
that window ever moved. Negative-tested by disabling the exclusion: the row runs house 28
across the new carriageway and check 7 names it, which is the corner-shop/`GATE_CLEAR` story
repeating exactly. The houses' place points are now generated from `HOUSES` too; the four
originals were literals, which works until a fifth house exists with no point inside it.

The west frontage (`z -280..-204`) is still bare. One house fits at the civic side's own
depth and spacing; a second overruns the loop's bottom road by two studs. Left alone
deliberately — the west side being clinic/bakery/garage is what makes this read as a town
rather than a subdivision.

#### The Backs was the same street twice, and is now a green

**It generated clean, it passed all twelve checks, and it was wrong.** Avenue 1 runs the
full height of the map thirty-five studs east of the Backs on the same axis. Two parallel
carriageways that close are not two routes; they are one route drawn twice, and the only
thing distinguishing the second one was being nearer the player's fence. The 40.65 studs
was read as "a slot exactly one street wide", and *fits* was allowed to stand in for
*belongs*.

The lesson is narrower than "do not build redundant roads", and it is a lesson about the
checker. **Every check in `check_city` measures a road against itself** — is it connected
(8), is it carved (10), does it reach the buildings (11), can the spawn get to everything
(12). Nothing measures a road against the road beside it, and nothing ever will, because
"these two are the same street twice" is a judgement about a map, not a property of
geometry. The green passes exactly as well as the street did. **Passing is not being
right**, and this file should stop treating a green run as the end of the argument.

**What is there now.** The corridor is what the plot's back fence looks at: grass (no new
slab — `CityGround` already lays lawn there, and a second lawn at the same height and tone
is the coplanar pair check 10 exists for), a two-line tree belt down the avenue side with a
deliberate gap on the path's line so the player can see the avenue from their own gate, a
footpath straight east from the back gate, and two benches facing each other across it.

**The load-bearing find, and it was check 12 that made it.** Taking the street out took a
*route* with it, which the geometry gave no sign of: the connector's mouth at (30, 60) is
85 studs from the spawn, and with only the gate spur there it became a 203-stud walk out of
the front door and around — check 12 at **2.40**, a fail. The fix is a footpath spine down
the length of the green, and it is not decoration or symmetry; it is the route. With it,
worst detour **1.51**, all 636 points reachable. A path is a road for this purpose, which
is the useful thing to know: what the corridor needed was a *way through*, not a
carriageway, and those are not the same requirement.

`ROUTE_STEP` (68) replaced a bare `68` repeated in nine `range()` calls — the shape of a
number that gets changed in eight places.

#### The check that was missing

**`check_city` check 12, "Every place reachable from the spawn".** Dijkstra over the route
graph from the spawn pad, asking two things a component count cannot: can you get there at
all, and is the way there anything like the way it looks (`MAX_DETOUR`, 1.9).

Both halves are needed and neither subsumes the other, which the measurements show:

| world state | unreachable | worst ratio |
|---|---|---|
| before this session | 597 of 620 | 1.20 |
| two new roads later | 0 | **2.56** |
| the 76-stud hole closed | 0 | 1.47 |

The reachability half catches row one and says nothing about row two. The ratio half catches
row two and passes row one at 1.20 — because a ratio can only be computed for somewhere you
can already get to. Negative-tested against the pre-change assets: exit 1, "597 stranded".

This is also the check that turns "the town has one road into the city" from an observation
into a failure. One link still connects; it just costs six hundred studs.

**Retraction, and what caused it.** The first pass of this measurement loaded `Town`,
`House`, `Street` and `Furniture` and concluded there was no ground east of x 8 — that the
house overhung its own slab by 24 studs and the world ended at its back wall. Every number
in that finding was correct. The conclusion was wrong, because `City.rbxmx` was not in the
list, and `City.rbxmx` is where the ground behind the house lives. Two edits were made on
that premise and have been reverted.

Worth keeping for two reasons. First, the tell was there and was ignored: the same probe
reported the town's grass ending at exactly x 8.0 and, when the city was finally included,
the city's ground *starting* at exactly x 8.0. A boundary that lands on a round number
shared with the file you left out is a seam, not a cliff. Second, `default.project.json`
mounts five assets into one place and the world is only the union of them — so any probe
that answers "what is at this coordinate" has to load all five or it is answering a
different question. The occupancy script printed at the top of this section loads four.

**This is also the argument for `check_town.py`, which now exists.** Not because it would
have caught a hole — there is no hole — but because the checker is where a probe like this
gets written down once, with the right asset list, instead of being rebuilt from memory by
whoever next wonders what is behind the house.

#### `check_town.py` — six checks, and two defects that were already in the town

**Why a second file and not more checks in `check_city.py`.** Almost every check over
there is scoped to the city by construction, and *the scoping is invisible in the check's
own name*. "Ground under place points" walks `city_points`. "Building overlap" walks
`city_models`. The one exception is check 7, which was widened to test the city's roads
against every asset's walls after the gate road was found running through a town house —
and widening it is what showed the others had the same shape of hole. The town had been
carrying twelve green checks that were never asking about the town at all.

The readers and the geometry are imported from `check_city` rather than copied. A second
rotation-aware rbxmx reader is two copies of one measurement, which is the defect this
tree has been repaired for more often than any other.

**Two defects were in the town when it was first run, and nothing else could see either.**

- **The bakery's place point stood inside the bakery counter.** The counter was
  `BAKERY_X1 - 14 .. BAKERY_X1 - 4` — ten studs deep, a round number that made a neat
  rectangle — and the point is at `BAKERY_X1 - 8`, four studs inside it. The game's own
  instruction for that building is *"the bakery, at the counter"*, and the spot it names is
  in the furniture. Two lines above it in the same table, the corner shop's point carries a
  comment saying it is stood in front of its counter "which is what every other 'at the
  counter' point in town already means". It did not.
  Fixed by making the counter a counter: `COUNTER_DEPTH = 3.0`, one constant now shared
  with the corner shop's, whose depth was arrived at by measuring what a customer needs on
  their side of it. The point did not move — `WEST_SPOT_X` is shared with four other
  buildings, so the counter was the thing that was wrong.
- **Three of the four return-road waypoints floated half a stud**, declared at `PAVING`
  height while standing on a carriageway that tops at `GROUND`. The fourth said `GROUND`
  and was right, which is what one line getting fixed and its three neighbours not looks
  like. Half a stud is nothing to look at; it is a failure because *the height a point
  declares is a claim about which surface it is standing on*, and these three claimed a
  pavement fifteen studs east of them. All four now derive their x from `RETURN_MID`.

**The new check is 3, "room to stand".** A place point is not a label on a map — it is the
coordinate the game walks a player to and leaves them standing on, and nothing in this repo
had ever asked whether a body fits there. The fittings are laid out by a generator that
never reads the place point table, and the place point table is a list of coordinates that
never reads the fittings; the two are only ever compared here.

Two decisions make it report something worth reading rather than noise:

- **The band starts at `STAND_STEP` (2.0), not at the floor.** A Roblox humanoid walks over
  what is below its hip without noticing, so a band starting at the floor reports every rug,
  doorstep, kerb and book in the game and the real find drowns in them. Two studs is the
  default `HipHeight` — below it, it is not an obstruction.
- **`STAND_CLEAR` (1.0) is derived, not chosen.** `HumanoidRootPart` is two studs wide, so
  half of it is one. The measurement confirms the margin rather than setting it: across the
  50 town place points the worst honest clearance is 1.51 and the next is 2.00, while the
  defect measures as *inside*.

Checks 1, 4, 5 and 6 are the town's half of questions the city already asks: unique ids, a
place point in every building (which `gen_town.py`'s own comment says nothing checks), no
two buildings in each other, no road through a building. All six negative-tested by making
the change each forbids; checks 2 and 3 additionally against `git show HEAD:assets/Town.rbxmx`.

**What it deliberately does not check.** *Is the road network one connected piece* — check
8's town analogue — **does not transfer and is not faked.** In the city a road is a slab
laid on top of the ground; in the town it is a tile *of* the ground, so unioning the ground
jigsaw would return "one piece" for a town with no roads in it at all. That check needs a
real formulation before it needs a threshold. The same reading turned up that the two
generators disagree about where a road lives — `build_street.py` uses a `Road` group,
`gen_town.py` puts its four carriageways in `Ground` as `RoadN`/`RoadEast`/`RoadBottom`/
`RoadReturn` — which check 6 has to special-case and which wants unifying.

**And the hole underneath both checkers, found the next day.** Both of them discover their
inputs by globbing `assets/*.rbxmx`. `assets/SchoolFurniture.rbxmx` was mounted in *neither*
project file, so for as long as it has existed both checkers have been reading it, measuring
it and reporting it green while it shipped into no place at all. It carries the four
invisible `AgesEvent` anchors for the four school life events, `WorldEventService` finds an
anchor by tag and by nothing else, and those four events have therefore never been able to
fire in any build.

`rojo build` could not catch this: it reports on what a project file *does* mention, and
silence about a file it was never told about is not an error. The general statement is the
one to keep — **a checker that discovers its own inputs will certify a file that ships
nowhere**, and the fix belongs upstream of geometry. It is `check.py` check 3, "every asset
is mounted": glob the assets, recursively collect every `$path` in both project files, fail
on any asset no `$path` covers (a directory mount counting as covering what is under it, so
it does not assume assets are mounted one file at a time). Negative-tested in both
directions, and the fix verified by decoding the built place rather than trusting the build
— the anchor's `Tags` deserialises to `AgesEvent` and its `AttributesSerialize` to
`EventId = school_notice_board` inside the built `.rbxlx`.

### C. Dead ends, and roads to buildings that have none — *the check is written; it finds nothing*

**Done: `check_city` check 11, "A road to every door".** For every model in the city that
contains a place point, the gap to the nearest carriageway. 159 destinations, worst 18.0
studs, median 8.0, threshold 32. It passes. **There is no building in the city without road
access**, and the older note about 19 of them is stale — the civic precinct (item 5) was
the last of them.

Two definitions do the work, and both were arrived at by measuring formulations that
failed:

- *A destination is a model that contains a place point.* The obvious formulation — every
  model with walls — reports `Sea0-3`, the scrap piles, the depot stacks, the switchyard
  and the cooling towers, because a heap of scrap is wall-shaped. Containing a place point
  is not a guess about what a building is; it is the game saying out loud that it sends
  players there. `wp_` waypoints are excluded: a waypoint is a step on a route, and routes
  legitimately cross parks and piers.
- *Distance is to the carriageway, not to any street slab.* The precinct had pavements. It
  had no road.

Negative-tested rather than asserted: with `PrecinctAve` and `NorthSvc` deleted from
`gen_city.py` the check fails and exits non-zero, reporting the eight north-strip shops at
47 and 88 studs. That is a 29-stud gap between the worst honest case and the smallest real
defect, which is what makes the threshold a measurement rather than a taste.

**A dead-end check was attempted and abandoned, and the reason is worth keeping.** The
formulation was: project a probe box past each end of each road slab along its long axis;
if nothing is there, the road ends in nothing. It reported twelve dead ends around the
Circle. They were all false. The ring is not a chain of segments laid end to end — it is a
paved annulus tiled by twenty overlapping *radial* planks, each 34 long by 18.8 wide with
its long axis pointing outward from the centre. The "ends" of a plank are the inner and
outer kerbs of the ring, and probing past them is probing off the road on purpose. The
assumption that a road slab's long axis is the direction of travel is false in the one
place it matters. **A per-part end probe cannot answer this question**; anything that
replaces it has to work on the connected road *surface*, the way check 8 does, and ask
about reachable area rather than about part ends. Until then, check 11 covers the half of
the complaint that has real defects behind it.

Remaining, if it turns out to matter: `ConnRoad` at (30.5, 60.0) and the three `XW79_*`
crossing stubs were the only non-Circle candidates the probe found, and none of them
strands a destination — check 11 passes with all four in place.

### D. Poor neighbourhoods should have narrower roads — *done*

`AVE_W` and `CS_W` are lists now. Avenues 2 and 5 are 16 studs against the arterials' 24;
cross streets 4 and 5 are 14 against 22. Measured off the generated file, not intended:
`Ave1 16, Ave4 16`, the other four avenues 24, `C3 14, C4 14`, the other four cross streets
22, and all four works streets 22.

**This section said "make `AVE_W` a per-avenue list" and that instruction was wrong on its
own.** Avenues run north-south. The city's wealth gradient does not: `house_tier` picks a
block's house styles from its Chebyshev distance to the Circle, the Circle sits near the
*south* of the grid at (avenue 3, cross street 2), and every residential block is north of
it — so all five HOUSE blocks in sband 4 come out at 3.5 rings and all four in sband 3 at
2.5, **whatever avenue band they are in**. The houses get smaller as you walk north and they
do not care which avenue you are on. Doing only the avenues would have been a 23-site
refactor that changed nothing a player could see, which is the worst possible outcome for a
change this wide. The cross streets are the axis that carries the ask, so `CS_W` was split
too.

Which streets narrow is not a taste call — both lists were read off things the file already
states:

- `WORKS_AVE = (0, 3, 5)`, whose own comment is *"those are the ones with somewhere to go"*.
  Avenues 1, 4 and 6 carry freight south into the works. They stay.
- `CIRCLE_AVE = 2`. Avenue 3 runs into the roundabout and becomes two of its four spokes.
  It stays, and so does cross street 2 for the same reason.
- That leaves avenues 2 and 5, which begin at the step-down band and end at the last cross
  street and serve nothing but the blocks either side.
- On the other axis, `ROLES` puts the park and nine of the ten house blocks in sbands 3 and
  4, which are bounded by cross streets 4 and 5. Nothing but homes fronts those two. Cross
  street 6 is the civic precinct's frontage and 1 and 3 bound the mall, the offices, the
  apartments and the financial fade — all stay.

So the narrow streets land exactly where the small houses already are, and the two gradients
now say the same thing instead of being unaware of each other: walking north out of downtown
the houses shrink *and* the road pinches. A third off in both cases (24→16, 22→14) because
that is what reads from across a block; 20 and 18 were rejected as safe and invisible, and an
invisible change is not worth a 40-site refactor.

**Narrowing is the only safe direction and this is what made the change cheap.** A
carriageway is subtracted from the block interior either side of it, so every stud off a
road is a stud back to the blocks — and the note above `AVE` records that the interior was
*only just* affordable at 24. Nothing had to move to pay for this.

Six things a future edit could break are now assertions in `gen_city.py`, each negative-
tested by making the change it forbids:

- `AVE[5] + AVE_W[5]` is the bay's west shore. Touch avenue 6's width in either direction
  and you must move `AVE[5]` in the same edit or re-lay the beach, baywalk, piers and sports
  park.
- No avenue in `WORKS_AVE` may leave the arterial width.
- Avenue 3 and cross street 2 must stay arterial: they are the Circle's spokes and
  `CIRCLE_X`/`CIRCLE_Z` are their carriageway centres.
- `CIRCLE_ROAD_W` must exceed both.
- Every avenue band must keep the 102 studs two facing house rows need.

The Circle one is worth keeping for the reason it exists rather than for the check: narrowing
cross street 2 by eight studs *is* already caught, by `check_city` check 10 — as **1004
coplanar pairs**, naming no street, no number and no file. The assertion fails in the
generator on the line that is wrong, before an asset is written.

Also fixed in passing: `AVE_Z1` was the literal `972.0`, which is `CS[5] + 22` and was only
correct while every cross street was 22 wide. It is derived from `CS[CS_LAST] + CS_W[CS_LAST]`
now. That is the fifth time this file's recurring defect — a number measured from other
numbers and then typed in — has been repaired, and the first time one was caught *before* it
shipped rather than after.

`WCS_W` is separate and deliberately so: the works' south streets and the precinct's service
road keep the standard 22. A freight street is not a poor neighbourhood's street, and holding
it under its own name means narrowing a residential road can never quietly narrow the one the
timber mill loads from.

Verified: all eleven `check_city` checks pass, `check.py` all clean, both places build,
`City.rbxmx` reproducible to one md5 across runs, `Town.rbxmx` byte-identical. The one extra
part (11783 → 11784) is one extra centre-line dash, because the dash runs are carved at the
crossing roads and four of those moved.

### E. The empty half

Measured, not assumed: everything built sits in x -256..1024, z -384..1120. **x -1024..-256
is completely empty across the whole map, and so is z -1024..-384** — together more than
half a 2048x2048 baseplate. The bay strip at x 793..1024 is *not* empty; that is the beach
and sports park, and an earlier survey got this wrong.

Owner wants: industrial, docks, and low-rise sprawl, plus downtown densified.

Resolved as option (c): industrial and low-rise sprawl west, docks east on the bay. The north
half of the west band is **built** — see 11. The south half is **measured and stopped**: it
cannot reach the detour gate without a crossing through the town's back row, which is another
lane's file. See 13 for the numbers and the one-line ask.

Sequencing note that is easy to get wrong: **downtown infill should come after the grid is
final**, because block interiors changed once already and anything placed into them before
that settles gets built twice.

Docks want water, so they belong against the bay or on a new west shore — decide which
before laying any of it, because it determines whether the empty west half is coastline or
inland.

### F. The poor end, and the tip — *built 2026-08-18*

Not on the original owed list; it came from the owner: *"make the area around it poorer,
add a land fill, almost broken houses after that part of the neighbourhood, expand that
map"*, approved as residential-only, scavenging as a real verb, gangs deferred.

**The spec, which is what the build was measured against.**

1. **Decay is a function of distance from your front door, not a list.** A hand-written
   list of which houses are run-down is a second table describing something the layout
   already knows, and two tables that describe one thing are never compared. `house()`
   takes a `decay` 0..1 solved from the door's z; `worn(color, amount, toward)` is the one
   place that decides what run-down does to a colour; features (cracked path, roof patch,
   yard junk, boarded windows) switch on thresholds of the same number. Verified by
   measuring the built asset, not the source: parts per house climb 25 → 34 and boarded
   windows 0 → 1 → 2 monotonically with z, so moving a house moves its condition.
2. **The street runs out.** The loop closed at z -290..-313. A dead-end spur continues
   south in the same x band to the tip gate, with plots 28 and 30 on it at z -360..-326
   and -400..-366, south of the road to the factories.
3. **The tip fills z -500..-400, the full town width.** Chain-link, a gate the spur
   dead-ends into, spoil mounds, skips, wrecks, two floodlight masts over the yard rather
   than street lamps, a weighbridge plate in the track and a weighbridge hut, and the
   city's boundary treeline continued west at the same 30-stud pitch `works_boundary()`
   uses, so the bottom of the world is one edge rather than two ideas meeting in the
   middle.

**The sidewalk could not be one slab, and this is the trap to remember.**
`gen_city.py`'s `road_ew(SOUTHGATE_Z0, SOUTHGATE_Z1, ROAD_X1, AVE[0], ...)` starts at
x = `ROAD_X1` = -64.5, which is exactly where the town's near sidewalk band begins. A
single kerb-and-paving run from the tip up to the street would have laid a raised kerb
across the middle of that carriageway — **in another asset, from a generator that never
looks at it.** Two runs with a 30-stud crossing between them, plus an assertion that
`SOUTHGATE_CLEAR[1]` and `CURL_Z` are still the same number, which is the only reason
there is no third slab between them.

**Three defects nothing in the tree could have caught, each now an assertion in
`gen_town.py`, each negative-tested by making the change it forbids:**

- **`ROUTE_LINK`** — house 26 at z -256.2 and house 28 at -343 are 87 studs apart against
  a 70-stud link radius. Everything south of house 26 would have been off the route graph,
  and `check_city` check 4 passes anyway because the town points it *can* reach are still
  one component. Fixed with `wp_cross_n`/`wp_cross_s` either side of the link road; the
  assertion walks the whole south chain in z order and names the offending pair.
- **`TIP_CLEAR = 2 * BODY_WIDTH`** — the hand-typed yard had five real collisions,
  including a floodlight mast inside a spoil heap. A table of centres says nothing about
  extents, and `check_town` check 5 compares *buildings*: a spoil heap has no `Roof` part,
  so it was never in scope. Pairwise over everything placed in the yard, plus the haul
  track and the yard edge. Derived, not chosen — `BODY_WIDTH` is already the file's answer
  to how much room a person needs, and twice it is a gap two people can pass in.
- **The gate assertion** — `TIP_GATE_MARGIN = 5.0` declares a 33-stud opening; the built
  opening was 24 studs, with **no posts at the opening at all**, because `chainlink()` laid
  panels on one pitch across the whole boundary and dropped the ones whose midpoint fell in
  the gap. `fence_runs()` now splits at the gate's exact edges and subdivides each run
  independently, and the assertion asks `fence_runs()` what it built rather than trusting
  the constant. **A declared measurement quietly rounded to a construction grid** joins the
  recurring defect classes at the top of this file.

**Signposting is part of the mechanic.** A player who walks 300 studs of worsening street
to an unnamed chain-link fence reads it as the edge of the map and turns round. The board
is as wide as the hole it names and butts against the west gatepost, so sign and entrance
are one object; the notice under it grants permission to salvage, which is not the same
thing as the prompt — the prompt is the three dots on the skips, per the interaction
grammar. Both boards derive their canvas from their own size at a fixed pixels-per-stud,
because `sign()` stretches its canvas over whatever face it lands on.

**The seam that is deliberately half-built.** Eleven parts carry `AgesScavenge` with a
`ScavengeKind` attribute — 4 `skip`, 4 `pile`, 3 `wreck` — in the shape of
`AgesGymEquipment`/`GymKind`. There is no `Config` entry behind it because `Config.luau`
belongs to another agent. Geometry first is how a tag contract is supposed to work.

**Gangs deferred by the owner** — *"we can do the gangs later will probably be included in
their territory"*. Nothing gang-specific was built. The tip and the poor end are laid out
so they can become territory later: one dead-end approach, one gate, a fenced compound with
a single way in, and a run of houses whose condition already grades toward it.

Verified: `Town.rbxmx` 1079 parts in 25 pieces, md5 `50563a826cdf4bd298f883db4eb6ae96`,
reproducible across consecutive runs. `check_town` all six green, `check_city` all twelve
green, `check.py` clean in every check in this lane.

### G. The back of the town, the north gate, and the alleys — *built 2026-08-19*

From the owner: *"there should be more houses and depth and stuff behind the school and
bakery and stuff so the town doesnt end at the spawn point along with more stuff along the
town library instead of a dead end, focus on that too"*. Spec'd back and approved with
*"open it and yes cafe and community hall"* — the north end **opens onto the city**, and
the library end gets two buildings rather than a turning circle.

**Three measurements turned the request into defects rather than taste.**

- The town was **one street deep**: six civic buildings on one back wall, one house row
  opposite, and nothing behind either.
- `GrassWestMargin` was **104 × 364 studs of a single bare slab** — roughly two fifths of
  the town's footprint — and `RoadReturn` was lying in it: **181 studs of finished
  carriageway**, pavement and kerbs and lamps and centre dashes, stopping halfway and
  connecting to nothing.
- `wp_north_3` was a **leaf on the route graph**. The whole north end was a spur, so every
  town↔city journey went via the gate road, the southern link or the green.

**What was built.** Ten east-facing houses on odd numbers 1–19 down the back street (odd
numbering is the one thing not copied from the east row — a different series is how the
player is told it is a different road, and it costs nothing). The north gate, at
`NORTHGATE_Z0 = 312`, drawn on both sides of the asset seam. A café and a community hall
north of the library, both with footprints derived from the row rather than chosen: the
café is a store's depth, the hall is the library's, each one `WEST_GAP` north of what it
follows. Three alleys through the west frontage.

**Rejected, and why.** Aligning the north gate with city cross street 1 at z 200..222 to
make a proper crossroads — the library stands at 168..208 and moving a building to suit a
junction is the tail wagging the dog. The gate road is the existing precedent for an
unaligned tee on the west flank. Also rejected: a separate wear rule for the back row, for
being a second table describing what `wear_at(door_z)` already knows.

**The frontage was described in two files, and so nobody had measured it.** This is the
section worth reading. The first cut at the detour problem put one alley between the gym
and the library and justified it in a comment: the only gap on the frontage wide enough to
walk down. False. The west frontage is built by `gen_town.py` (garage, bakery, clinic, gym,
library, café, hall) **and** `build_street.py` (school, workplace), and the gap count came
from the file that can see seven of the nine. Measured across all nine:

| gap | studs | alley |
|---|---|---|
| garage → bakery | 8 | — |
| bakery → clinic | 8 | — |
| clinic → workplace | 6 | — |
| **workplace → school** | **32** | yes |
| **school → gym** | **20** | yes |
| **gym → library** | **16** | yes |
| library → café | 8 | — |
| café → hall | 8 | — |

The gap that was picked by hand is the narrowest of the three, and the two that were missed
are the two nearest the worst-detour point. `WEST_FRONTAGE` now lives in `world_plan.py` as
one sorted table of all nine, and `ALLEYS` is derived from it — every gap of at least
`ALLEY_WIDTH + 2 * ALLEY_MARGIN` gets a cut-through, none of them chosen.

**The detour ratio is what made all of this necessary and what proved it worked.**
`check_city` check 12 measures walked distance against straight-line from the spawn:

| state | worst detour | where |
|---|---|---|
| back street built, ends joined only at the corners | **2.02 — fails** | middle of the back street |
| one alley, gym → library | 1.82 | `wp_back_walk5` |
| three alleys, derived | **1.51** | `wp_bridge_2`, in the city |

Two parallel roads joined only at their ends are *reachable* and still wrong; that is a
distinction the route graph can make and a player only experiences as the town being
annoying. At 1.51 the worst walk in the world is no longer in the town at all.

**A tree stood in the middle of the first alley and every gate passed.** The trunk at
(-104, 160) was dead centre of an eight-stud path. The asset built, `check_town` went six
green, `check_city` went twelve green — nothing either of them measures is *"is there a
tree in this footpath"*. Street trees want the frontage gaps for the same reason the alleys
do: they are the only grass left on that side, and two files were planting into that strip
with neither able to see the other's asset. (The same collision had already put one trunk
inside another at (-104, 88).) `clear_of_alleys(z, spread)` now lives in the shared plan
and both generators ask it, so the tree that loses is dropped by measurement — a deleted
line is a fact about today's alleys, and a list goes stale the moment a building moves and
silently readmits a tree that then stands in the road.

**An assertion that failed its own negative test.** `_check_joins` first asked whether an
alley end had *anything* within the link radius that was not more of the same alley.
Pulling the west end ninety studs off the back street did not fire it: what it found was
`school`, an interior place point on the far side of the frontage. Destinations and roads
are the same kind of thing to the route graph, so that check would have passed an alley
opening onto a wall. It now takes a named set of back-street points. The **east** end is
deliberately not checked locally — the main street's waypoints at those z values are
generated by `build_street.py` into another asset and do not exist at that point in the
program — and the comment says so. `check_city` sees both ends and does check it.

Verified: `Town.rbxmx` 1592 parts in 37 pieces, md5 `a225bfd1225cee2098329cb7987b4a05`;
`Street.rbxmx` 486 in 14; `City.rbxmx` 11874 in 499 — all byte-identical across consecutive
runs. `check_town` all six green (101 place points and 30 buildings, from 59 and 18),
`check_city` all twelve green (688 place points reachable, worst detour 1.51), `check.py`
all clean. Every new assertion negative-tested.

### H. Filling the tip end and the library line — *built 2026-08-20*

From the owner: *"add more houses and shops near the landfill area to fill it in then move
onto the community hall and everything along the line of the library to fill it up"*.
Spec'd back with measurements and approved with **"go"**. Two builds in that order.

**Build A — the tip end.** The return road carried the rest of the way south to the tip
line; `BACK_ROW` extended to meet it; `TipParade`, a two-unit terrace facing west at the
poor end; service yards behind. `BACK_ROW_Z0` moved from `GARAGE_Z0` to
`TIP_Z1 + NEIGHBOUR_GAP` and is asserted equal to `SOUTH_ROW[-1][0]`, so the back row and
the east row now stop level against the same fence **because the same fact stops both** —
not because two numbers agree today. The row went 10 → 15 houses with no count typed.

A terrace and not detached units, for a measured reason: the band is 76.5 studs, and two
units plus a gap need 80. The style follows the constraint rather than the other way round.

**Build B — the library line.** `NorthParade`: POST OFFICE and TOWN BARBERS at
x −52.6..−12.6, z 228..308, facing **west** across the main street at the café and the
community hall. That side was houses as far as the park and then eighty studs of nothing —
a street with buildings down one side only is a street with a back to it. Here the band is
80 to the stud, so the units *are* detached with `WEST_GAP` between them, and the gap earns
its keep as the only way off that pavement into the ground behind. It is deliberately
narrower than `ALLEY_MIN`: claiming a passage the file has not paved would put a footpath
in the route graph that nothing on the ground says is there.

No forecourt, against nine set-back civic buildings opposite. That contrast is the point,
not an economy — a shopfront standing on the footway is what tells a player which side of
the street is which from the far pavement, before they have read a sign.

**Geometry and tag seams only, no `Config` entries.** `Config.luau` belongs to another
agent. Both units are untagged for now: a tag no service reads is orphaned code by this
tree's rules.

**No betting shop.** It was the obvious fourth name for a poor-end parade and it is banned
outright at 13+.

#### The park was being drawn inside a house, and all three gates passed it

`PARK_Z0, PARK_Z1` had moved from `168..228` to `-88..-28`, comment rewritten to match. The
park is x −44..4; number 18 stands at x −42..2, z −86..−52. A **44 × 34 overlap with a
standing house** — pond, both paths, both benches and the picnic table inside its front
room.

Three checks live next door to that question and none of them asks it: check 5 compares
*buildings to buildings* and a park is surface geometry, check 6 asks about carriageways,
check 7 asks about trees. The guard is now an assertion in `gen_town.py` under `HOUSES`
rather than a ninth check, because a generator that can draw a park on a house should not
be allowed to finish.

The same edit silently broke Build B. `NORTH_PARADE_Z0 = PARK_Z1` was written when
`PARK_Z1` was 228 and the band was the documented 80. With the park moved it became 336,
the shops did not move, and **256 studs of empty frontage** were left on a finished
pavement — the defect the parade exists to remove, four times worse, reported by nothing.

#### The assertion over it could never have fired

It read `assert 2 <= len(NORTH_PARADE) <= 3`. The row is built from a fixed tuple of two
names, so `n` is 0, 1 or 2 and **never 3**. A bound no generator can reach is not a loose
check; it is the appearance of one.

| replaced by | catches |
|---|---|
| `len(NORTH_PARADE) == 2` | the band shrinking and dropping units off the south end |
| `NORTH_PARADE_SLACK < STORE_FRONT + WEST_GAP` | the band growing and leaving a plot nobody built |

The second is the half that was missing and the half that mattered.

#### One pavement, two halves, one of them checked

`wp_south_3` had moved from z −212 to −106 — "outside the garage", up beside the bakery,
out of order with its neighbours, leaving a **127-stud hop** to `wp_south_4` against a
70-stud `ROUTE_LINK`. The bottom of the far walk came off the route graph.

`_check_chain` was already running on `corner_n, wp_north_1..5, wp_top_junction`, the north
half of that same walk, and on nothing south of the school. Five points each side, all at
x −92, neighbouring lines in the same literal, and only one half checked — and the defect
landed in the unchecked half. `_southwalk` now covers the other five.

#### `roof_groups`: a building is a thing with a roof on it

check_town's unit of "a building" was the **top-level group**, which is the same thing for
a house and quietly wrong for a parade — `TipParade` is one top-level group with two shops
in it. Check 4 asked whether *the parade* had a place point anywhere in it and said yes on
the strength of one unit's; check 5 could not see two units of one terrace standing in each
other at all. Four buildings were being checked as two, and the header printed the symptom
for two days: 36 before a parade of two went in, 37 after. Nobody read it, because nobody
had said what the number counted.

Keyed on the innermost group holding a `Roof`, chained through the whole group path —
every house's inner group is called `HouseStructure`, and fifteen under one key is the
exact merge it exists to undo. **37 → 39 buildings**; ground-floor walls 145 → 141, the
four dropped (`BoxBank`, `HallEast1`, `HallEast2`, `Ovens`) all interior fittings.

#### Smaller repairs in the same pass

- **`clear_of_forecourts` had a zero-width x band.** `min/max(FRONT_X, FORECOURT_X0)` are
  two names for the same number, −112, so it answered "clear" for every point in the world
  including the tree it was written to catch. Both names are worth keeping; the width
  between them was never a width.
- **`TRUNK_WIDTH = 1.6` into `world_plan.py`.** `tree()` is written three times and all
  three had their own 1.6. They agreed; nothing made them. Canopies are `CanCollide false`
  by design and check 7 measures trunks, so asking the filter with the canopy refuses real
  trees over a one-stud overhang — a filter stricter than its checker is a second opinion
  nobody asked for.
- **`build_street.py` asked `clear_of_alleys` where it needed `clear_of_paving`**, and a
  tree stood six studs inside the clinic's forecourt. A call site that enumerates hazards
  only knows the hazards already paid for. 486 → 483 parts.
- **check_town filed failures under the wrong heading.** stdout block-buffers when piped,
  so FAIL lines surfaced above their own section header and check 7's first negative test
  read as a check 6 failure. `line_buffering=True` on both streams. A report filed under
  the wrong heading is worse than none, because it is believed.

**`tools/check_asserts.py` is new.** It breaks one input per case and checks the *right*
assertion fires, matched on a phrase only that assertion prints, with a control run that
catches a guard firing unconditionally. 6/6. It covers the north parade block and nothing
else — six of the forty-odd assertions in `gen_town.py` — and says so at the top, because a
harness read as coverage it does not have is how `2 <= n <= 3` survived.

Verified: `Town.rbxmx` 2064 parts in 44 pieces, `Street.rbxmx` 483 in 14, `City.rbxmx`
11874 in 499 — all md5-stable across consecutive runs. `check_town` **8/8** (121 place
points, 39 buildings, 10671 colliding parts), `check_city` **12/12** (708 place points
reachable, 159 destinations, worst detour 1.51 at `wp_bridge_2`), `check.py` all clean.
Nothing Studio-tested.

**Open.** The `wp_south_*` and `wp_north_*` chains are typed literals on a ~44-stud pitch
whose labels are approximate — `wp_south_1` is "outside the clinic" at −124 against
`CLINIC_DOOR = -98`. The positions are defensible as route-graph nodes; the *labels* are
what lie. Worth deriving both halves from the door constants in one pass, which moves
points and needs `check_city` re-run.
