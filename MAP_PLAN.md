# The map pass — what is done, what is owed

Working notes for `tools/gen_city.py`. Everything here is Agent A's; see HANDOVER.md.

Verify every change with **both**:

    python3 tools/gen_city.py && python3 tools/check_city.py

`check_city` has ten checks and they are the only thing standing between a geometry change
and a town that looks fine in Studio but has NPCs standing in traffic. It has already
caught two hardcoded radii that a visual inspection would never have found.

## Done

**1. Road grid widened.** Avenues 14 -> 24, cross streets 14 -> 22, Circle ring 24 -> 34.
Avenue positions were rechosen so `AVE[5] + AVE_W` still lands exactly on 793 — the bay,
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

**8. The corner shop, and the twenty-three studs it stands on.** `gen_town.py` carried a
comment claiming the imported house model reached `z 78.1`. Measured off `House.rbxmx` it
reaches `56.8`. The exclusion band around the player's own plot had been sized off that
wrong number, so the clearance was 7.7 studs on the south side and 31.2 on the north, and
only the southern figure was ever chosen. Twenty-three studs of the main road's frontage —
the stretch directly opposite the player's front gate, which is the one piece of street a
new player certainly sees — were fenced off by a measurement that was wrong.

Both bounds are now derived from what they are measurements *of*: `SHOP_Z0` is the model
clearance every building on that side already keeps, `SHOP_Z1` is the gap houses 14 and 16
already keep from each other. This is the same defect as the depot container pitch — a
number measured once, typed in as a literal, outliving the thing it measured — and the fix
is the same one: stop typing it.

Seventeen studs of frontage is too narrow for a house (the four on this street are 34
deep) and exactly right for a shop, so the mistake left behind the one footprint the
street did not have. Built as a **service spine and a customer floor**: the north strip
runs from the back wall to behind the counter and is the only way to reach either the
stock at the far end or the till at the front, so working the shop is a lap of the
building rather than a stand at one spot. Customer aisles hang south of that spine,
against a glazed flank that looks straight at the player's own front gate.

That plan is an argument, not a decoration — the activity law wants a consumable that
forces traversal every 40–60s, and putting the crates forty-one studs from the till is
what makes the run exist. The verb it is a stage for is spec'd in section A below, and it
is **not** built here: it is a job, and jobs are Agent B's.

Nothing in the shop is tagged. A tag no service reads is orphaned code by this tree's own
rules, and tagging is a one-line change the day the verb lands. One place point,
`corner_shop`, stood in front of the counter where every other "at the counter" point in
town is stood.

Measured off the generated file: `Town.rbxmx` 687 parts in 17 pieces. Every station inside
the shop is reachable by a body of half-width 1.40 — the figure `read_house.py` holds
routes to — and the narrowest point on the whole walkable floor is exactly 1.40. The only
overlapping colliding parts are wall corners and gondola spines, both of which every
existing building in the file already does.

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

### B. Behind the spawn house feels empty

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

### C. Dead ends, and roads to buildings that have none

Owner reports "too many dead ends" and buildings without road access. There is an older
note about 19 of them. The civic precinct was the worst of them and is fixed (item 5 above),
but it was found by *reading the map*, not by a check — which is the whole problem.
`check_city` check 8 only proves the street network is *one connected piece* — it does not
prove there are no stubs, and it does not check that every building has a road. So:

1. Write the missing check first, as a new check in `check_city.py`: for every place point
   with a door, is there a street slab within N studs? Report the offenders. **Do not fix
   dead ends by eye** — the whole reason the two hardcoded radii survived is that geometry
   bugs are invisible until something tests for them.
2. Then fix what it finds, most likely with a perimeter ring road plus spurs.

Hold any new check to CLAUDE.md's bar: it must catch a defect that has actually shipped,
and it must not produce false positives.

### D. Poor neighbourhoods should have narrower roads

Explicitly asked for and **not delivered** — every street in the city is currently the same
width. Needs `AVE_W` to become a per-avenue list, which is a ~22-site refactor (`grep -n
'AVE_W\b'`). Most sites are inside `for k, a in enumerate(AVE)` loops so they can index
directly; `block_bounds` has `band`; `CIRCLE_X` has `CIRCLE_AVE`.

Worth doing at the same time as E, because the new districts need their own street widths
anyway — doing both at once touches those 22 sites once instead of twice.

### E. The empty half

Measured, not assumed: everything built sits in x -256..1024, z -384..1120. **x -1024..-256
is completely empty across the whole map, and so is z -1024..-384** — together more than
half a 2048x2048 baseplate. The bay strip at x 793..1024 is *not* empty; that is the beach
and sports park, and an earlier survey got this wrong.

Owner wants: industrial, docks, and low-rise sprawl, plus downtown densified.

Sequencing note that is easy to get wrong: **downtown infill should come after the grid is
final**, because block interiors changed once already and anything placed into them before
that settles gets built twice.

Docks want water, so they belong against the bay or on a new west shore — decide which
before laying any of it, because it determines whether the empty west half is coastline or
inland.
