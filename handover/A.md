# Agent A — the world, and the crime/combat stack

## 2026-08-18 (last) — three missing requires, and why the gate said clean

**The game place would not load.** Not slowly, not partly: it came up with no services in
it at all. Owner reported it as "it's not letting me load into the game."

**Root cause.** `LifeService:Init()` calls `VerdictService.SetMoments(...)` at line 785 and
`VerdictService` was never required. In Lua that is a *global* read — nil — so the call is
a nil index that throws. `init.server.luau` calls every service's `Init()` **unguarded by
pcall**, and `LifeService:Init()` is line 92 of it, so the throw took out every service
declared after line 92 and nothing in the game ever reached `Start()`. This is the exact
symptom CLAUDE.md already warns about for a syntax error on the boot path — "a place that
loads with no services in it at all" — arriving by a different route.

**The comment is what caused it.** Above the `SetMoments` call, a comment claimed requiring
`VerdictService` here would close a require cycle. It would not: `VerdictService` reaches
only `DataService` and `Ribbons`, and neither reaches back. Somebody believed the comment,
skipped the require, and the code kept compiling because a nil global is legal Luau.
`SetMoments` still has a real job (it threads the moments *query* in) — that is a separate
problem from the require, and conflating the two is how the require got lost.

**Two more of the same defect were queued behind it**, found by scanning for the class
rather than by looking for the bug:

- `ReturnService` calls `BodyService.Apply(player)` on the Studio arrival path, unrequired.
  It threw on **every Studio join**, out of a `PlayerAdded` handler, *after* the life had
  already been rolled — so the player landed in a begun life wearing an adult body and the
  rest of the handler (including the frame yield that stops `BodyService` re-sizing them)
  never ran. This is why joining as a kid was not working even in the runs that got that far.
- `WorkService` calls `Customers.Queue(...)`, unrequired, and its type alias on line 56
  pointed at nothing. Only fires once a customer-facing job actually starts, which is why it
  outlived the two on the boot path.

**Why `check.py` was green through all three.** Its "calls to undefined names" check matches
a bare `name(`. Every one of these is `Module.method(` — a *field* call on an undefined
name — and the regex never looked at that shape. **This is the fourth time in this tree that
a gate was green because it was not looking at the thing**, and it belongs on the same list
as `check_city` measuring an asset that shipped in neither project file.

**Fixed:** tenth check, `check_undefined_modules`. Built on the existing `strip_code` rather
than a fresh comment stripper — my first throwaway scan flagged `Ambient` and `Work` inside
backtick strings, and `strip_code` already blanks strings while keeping `{...}` interpolation
holes, so it reports zero false positives tree-wide. Negative-tested by deleting each of the
three requires in turn: all three FIRED, the unmodified control tree clean.

**Ownership.** `LifeService`, `ReturnService` and `WorkService` are **B's files** and I edited
all three. That was under direct owner instruction to make the place load, and none of the
edits change behaviour — each is one `require` line plus the comment explaining why the
cycle argument is false. B: read them and keep or restate the comments in your own voice, but
do not remove the requires without running `check.py`. Commit `3c1b092`. `Cast.luau` was left
unstaged and untouched.

**To load in as a kid there is nothing to type.** `ReturnService.onPlayerAdded` already calls
`SetupService.Skip(player, true)` on every Studio join, so joining the game place rolls a
fresh child life at age zero. `/setup skip` still works mid-session to restart at will. That
path was correct all along — it was just throwing on the line after it.

**Not Studio-tested.** The gate is green and the boot path no longer has a nil index in it.
Whether the child body actually lands is the first thing to look at in Studio.

## 2026-08-18 (later still) — a boundary that lied, and an audit of the ones that stay hidden

**The disguise disc was painted wider than the disguise reached.** `DisguiseService` accepts
a player at `ReachStuds` — 6 studs, a *radius*. `Wardrobe` drew the disc at
`ReachStuds * 2.2`, which as a *diameter* is a radius of 6.6. The outer 0.6 studs of paint
was ground you could stand on, see yourself on the mark, and be off it as far as the server
was concerned — losing five seconds of change with the disc under your feet the whole time.

The comment above that constant argued for exactly the right rule and then got the direction
backwards. **The asymmetry is the thing to remember: a mark drawn too small is invisible,
because a player just outside it who keeps working never learns anything was wrong. A mark
drawn too big is a boundary that lies at the one moment the player is under pressure.** It
is drawn inside the reach now, as a share so it cannot drift from `ReachStuds`, and the
share errors at load if it ever reaches 1.

**Audit of the rest of the crime stack for the FightService defect** — server state the
player must react to, surfaced only as text or not at all. Findings, none of them acted on:

- **`PoliceService` officer `notice` has no tell, and that is deliberate** — the comment at
  the fall-through says so: *"the read is the distance and your own behaviour, not the
  officer's animation."* I agree and did not touch it. Do not "fix" this without re-reading
  it first.
- **But the two things that comment tells the player to read are themselves unreadable.**
  `Spotting.luau` says of conspicuousness: *"Every other system in this game gives the player
  a dial; this one gave them a wall."* The dial got built — heat, movement speed, gang
  colors — and `WitnessService.Describe` admits in its own comment that it is *"the one the
  player cannot see."* Running makes you easier to spot and nothing tells you so.
- The natural world-space answer is the crowd glancing at you more as you get louder, at a
  rate set by conspicuousness — a pre-warning below the existing binary stop-and-turn. **It
  needs a neck aimed on a townsperson, which is `PeopleService`/`NPCService` and not mine.**
  The technique is settled: `FightService.poseOf` and `NPCService.aimNeck` both drive a
  `Motor6D` `C0` against a rest pose captured once. Handing this over rather than building it.
- Smaller: `Config.Interact.RangeStuds` (closes the gang boss panel) and `BankService`'s
  distance to the silencing panel are both spatial quantities the player is asked to judge
  and never shown. `BountyService` is the one that gets this right — `client/world/SearchRing`
  draws the search radius, and it is the model to copy.

## 2026-08-18 (later) — the Circle, and a fight tell that is not a progress bar

Two pieces, both committed, one of them **untested in Studio**.

**The Circle's towers are now the tallest things in the city, and the skyline is derived.**
The shoulders were 8 storeys — 135.5 studs — against a 213.5 mast in the financial district
they were supposed to dominate. The comment above `CIRCUS_STOREYS` said they stood at 150.
Nobody typed that to deceive; it was measured once, typed as a literal, and left while the
generator moved underneath it. That is the defect this tree produces over and over, so the
fix is not the new number, it is that **there is no number left to rot**: `high_rise_skyline(n)`
and `circus_skyline(n)` compute what an eye on the ground sees.

**My first fix for that was `(14, 16, 14)`, and the owner rejected it on sight — correctly.**
It satisfied every requirement written down and made the Circle worse. Raising the shoulders
six storeys and the middle only two left a 32-stud step across a 68-stud arc, which from the
ground is one slab with a bump on it rather than three towers. **The lesson is worth more
than the fix: I treated "each tower is the tallest thing in the city" as the whole spec, when
the thing that made the Circle a landmark was the step between the towers — a property nobody
had written down and therefore nothing was protecting.** When a requirement arrives late,
check what the existing shape was buying before spending it.

**That fix restored the step and was still rejected, for a different reason: the Circle is
not three towers, it is twelve.** One three-tower constant stamped at all four corners
showed four towers of one height and eight of another. Two rooflines across the whole
centre — and worse than the version before it, because they were now tall enough to be the
only thing on the horizon.

**Twice in a row I fixed the quantity that was written down and missed the one that was
not.** First "each tower is the tallest", then "the arc has a step"; the thing actually
wrong both times was variety. `FIN_HEIGHTS`, one screen up in the same file, has said
`varied skyline` in its comment since it was written. The Circle never had that line, so
nothing was protecting it and every gate stayed green through both rounds. **If you are
about to satisfy a stated requirement by changing a shape, write down what the shape was
already buying before you spend it.**

A quadrant is now `circus_arc(q)`, built from four small constants:

| | | |
|---|---|---|
| `CIRCUS_ARC` | `(8, 14, 8)` | the base arc — shoulder, peak, shoulder |
| `CIRCUS_LIFT` | `6` | carries the lowest tower over the mast, applied to all |
| `CIRCUS_QUAD_LIFT` | `(0, 2, 1, 3)` | a different extra per corner, so no two match |
| `CIRCUS_TILT` | `1` | right shoulder over left, so an arc is not a mirror |

Twelve towers on **nine** rooflines, 231.5 to 375.5, every one clear of the mast and every
quadrant's peak five storeys over its own shoulders. **Raise `CIRCUS_LIFT` or
`CIRCUS_QUAD_LIFT`, never `CIRCUS_ARC`.** Safe range for the lift is 6..8 — the tallest
tower carries the lift *plus* the largest quad lift, and at 9 it passes 21:1 slenderness.

Three assertions, all negative-tested against an unmodified control:

- **Every tower clears the mast by `CIRCUS_CLEARANCE`**, and the lift is *minimal* — the
  latter is the by-hand negative test made permanent, so it re-runs when `FIN_HEIGHTS` moves.
- **Peak over shoulders, `CIRCUS_MIN_STEP`, measured *within* a quadrant.** Across the
  Circle it is not a step at all: the tallest and shortest towers stand at opposite corners
  with the monument between them, and comparing those two passes happily on four identical
  arcs — which is the other defect.
- **`CIRCUS_MIN_ROOFLINES`** — the first assertion here that looks at the Circle whole.
  Stamping one arc four times scores 3 and fires it.

The old "middle clears its shoulders by 18" assertion is **deleted, not raised**: it was
green on the flat version, because 18 studs answers "is that one taller", a ranking question
nobody was going to get wrong. Note the step assertion compares **storeys, not studs** — in
studs it failed on the very config it was written to bless, because two differences that are
both 96 accumulate over different `n` and land one bit apart.

**`FightService` now draws the wind-up on the body. This has never run in Studio.**
The opponent's `intent`, `timer` and `windTotal` were already replicated and were spent
entirely on a bar and a caption in the bottom-centre panel — nothing in the world at all. The
fight's whole skill is reading *when*, and the three archetypes are meant to be told apart by
their tells, so a generic bar made all three identical to look at with only a number
differing. `Fighters.luau` asks for the opposite in its own comment.

Three things in it are worth knowing before you touch it:

- **`poseOf` captures the rest `C0`s once, when the body is built.** Reading "rest" per tick
  reads back the previous frame's own write, and the arm walks off the shoulder over a few
  seconds. Animations drive `Transform` and posing composes onto `C0`, so the two coexist —
  `NPCService`'s `aimNeck` is the precedent.
- **Amplitude is derived from `strikeFooting / HARDEST_STRIKE`,** so no literal anywhere says
  how big a tell is. A brawler sweeps 107°, a scrapper 46°, and they are ~3x apart at the
  midpoint of their wind-ups — which is the moment the player has to decide.
- **`aimLimb` special-cases straight up.** The cross product is degenerate there; normalising
  it returns NaN, and a NaN `CFrame` does not error, it silently deletes the limb.

Verified numerically only — every pose maps to its target within 1.6e-16. **The visual result
on a real R15 rig is unconfirmed, and the direction signs are the likely first casualty: if an
arm winds forward instead of back, or the torso leans the wrong way, flip the sign on the
offending component of `ARM_WOUND` / `ARM_THROWN` / `WAIST_WOUND_DEGREES` rather than
rewriting `aimLimb`, which is the part that is proven.** The tell runs on its own loop at
`Config.NPC.LookTickSeconds` — borrowed, not added, because `Config.luau` is B's file.

## 2026-08-18 — the south-west band, stopped on purpose

**I did not build the south district, and the reason is a measurement, not a preference.**
The plan of record was to route around `gen_town.py` with a clear-band constant in
`world_plan.py`, the way `GATE_*`/`SOUTHGATE_*`/`NORTHGATE_*` already do. That plan is dead:
a clear band reserves space, and the town's back row has no space to reserve. It is 15 houses
on a 40-stud pitch, z −386..208, and **every gap in it is 6 studs**. One of them sits across
the `AlleyWorkplaceSchool` latitude, which is the one place a crossing would have been free.

Simulated against the real 1455-point graph: north-only **2.26**, north plus a leg round the
town's south tip **2.08**, both against a 1.9 limit. One crossing at z −6 gives **1.42**. The
south leg buys 0.18 and is not worth building — the worst point was never at the ends, it is
in the middle, which is exactly where the wall is. Any crossing latitude from −366 to ~210
works, so the ask is cheap: **move or drop the back-row house at z −26..8 and carry the alley
west from x −225 to −296.1.** That house is in `gen_town.py`. Not my file, and it was still in
flight under another agent, so it is specced and handed over rather than edited. `MAP_PLAN.md`
section 13 has the table.

**The bigger find is that check 12 would have let me cheat.** Its route graph joins any two
points within `ROUTE_LINK` with no idea what is between them. A probe 14 studs behind the
town's back fence scores **1.01**, because it links to `home_b6` through the living room of
the house at z −26..8. I could have shipped a district whose connection to the town was a hop
across six gardens, a fence and a house, and every gate would have been green. That is the
same defect the check was written to catch, living inside the check.

Do not fix it with "no edge may cross a wall" — **505 current edges cross one**, and nearly
all are terraces where the real walk is five studs longer along the pavement. Deleting them
all changes the shipped world by nothing (0 stranded, worst still 1.51 at `wp_bridge_2`), but
it also does not catch the probe: a door stands 2 studs *inside* its own wall, so its own
building must be exempt, and that exemption is what lets a line cross a house to reach the far
door. Pushing all 468 interior points out to their nearest face fixes it properly and the
probe goes unreachable everywhere along the wall. **That version reports the shipped city at
1.96 against 1.9 with 5 stranded** — `apt_4_1`, `wp_works_ironyard`, `wp_works_depotyard`,
`wp_civic_passage_0/2`. Three are named for passages and yards, and the wall boxes are AABBs
which check 11 already documents as bigger than the slab. Probably inflation closing real
gaps, not five real bugs — but it needs working through one at a time, so it is written up in
`MAP_PLAN.md` section 14 and **not committed**.

## 2026-08-18 (earlier) — the west estate

**The west estate is built, and it found a hole in the checker that certified it.**
Section E of `MAP_PLAN.md` was resolved as option **(c)** — industrial and low-rise sprawl
west, docks stay east on the bay — and the north district was approved with **"go"**. It is
built: light industrial and trade yards at x −1024..13, z 339..1148, `City.rbxmx` 11874 →
13956 parts in 681 pieces. All three gates green, and the asset regenerates to the same md5
twice running. Full write-up in `MAP_PLAN.md` sections 11 and 12; the two things worth
knowing here are below.

(Dated today. The entry below is dated two days later — the two machines disagree about the
date and I have not touched someone else's header to hide it.)

**It is inside `gen_city.py`, not a new `West.rbxmx`.** That is a deviation from the
approved spec and it was taken for two reasons that can be checked: the `ConnPavW` carve
list is a line in `gen_city.py` and no second generator could have reached it to put those
four junctions in, and five-plus helpers would have been duplicated in a tree where `tree()`
had already been written three times.

**Check 11 was not looking at the largest buildings in the city.** The estate added 12 place
points and the destination count went up by 5. `DOOR_SLACK` was 3.0; every `works_shed`
place point stands `SHED_APRON / 2` = 5.0 studs out on its loading apron. So no shed
anywhere was a "destination" — not the six new ones, and not the ironworks, sawmill, turbine
hall or transit shed either, which had been exempt since the works was built. It is 5.0 now,
173 destinations, and lowering `ROAD_ACCESS` to 13 reports all nine sheds where before it
reported them at no limit at all.

The guard on that number nearly shipped wrong, which is the part worth reading. Written as
"one point matches one model" it failed at 5.5 on `est_electrical` — which is Kemp
Electrical's *Structure* and *Fittings*, one building emitted as two groups. The invariant
is geometric, not nominal: the models a point matches must overlap one another. The rejected
fix was a regex stripping `Structure|Fittings` from group names, which is a guess about
naming rather than a statement about geometry, and would have been wrong a second time on
the self-store office that stands inside its own yard's shed footprint.

**`MAP_EDGE` now exists in `world_plan.py`** because `default.project.json` declares the
baseplate once and every generator that needed the world's edge typed 1024 for itself.
Check 9 reads the project file and asserts the two agree, including that the plate is
centred — a plate of the right size shifted 100 studs east still puts 100 studs of the
estate over nothing. A transcription is only acceptable with a gate on the cache.

**Two coplanar-surface bugs were found by reasoning, not by a gate**, and nothing in this
tree could have reported either: the common's pasture overlapped `WestGround` at the same
top height across its whole 400-stud width, and the farm track was drawn *below* the pasture
it was laid on, so it was invisible. A surface that loses to the ground it is laid on has no
symptom in any checker here. Worth a check of its own; I have not written one.

**Not done, carried forward.**

- **The south district** (low-rise sprawl, x −1024..−296, z −512..339) is the other half of
  section E and is next. It has to join the town's return road at both corners, so it
  depends on `gen_town.py` — which carries 49 uncommitted lines that are **not mine** (a
  `SouthPark` block) and currently fails my park-on-house assertion. The plan is to route
  around it with a clear-band constant in `world_plan.py`, the `NORTHGATE_CLEAR` pattern,
  rather than edit an in-flight file on someone else's list.
- The estate has no tags yet. `AgesPlacePoint` is there via `place_point`; `AgesScavenge`
  in the yards is a one-line change and is owed. No `Config.luau` entries — B's file.
- `wp_south_*` / `wp_north_*` are still typed literals whose labels lie about where they
  are. The road-group naming split between `build_street.py` and `gen_town.py` is still
  unreconciled, and `clear_of_paving`'s alley half is still unwritten.

**For whoever owns `gen_town.py` right now:** its `SouthPark` block fails `check_town`'s
park-on-house assertion. The cheapest correct fix is rewording line 2 of
`src/server/content/LifeEvents/Park.luau` to "The park at the top of the houses" — your
file, not mine, so I have left both alone.

**Nothing here has been Studio-tested.** Three green gates mean it compiles, packages and
measures correctly; they do not mean it plays.

## 2026-08-20

**Both builds the owner asked for are in, and the session's real finding was two edits
nobody could account for.** The request was *"add more houses and shops near the landfill
area to fill it in then move onto the community hall and everything along the line of the
library to fill it up"*, approved with **"go"** against a spec'd-back set of measurements.

**Build A, the tip end.** Return road carried south to the tip line, `BACK_ROW` extended
to meet it, a two-unit terrace (`TipParade`) facing west at the poor end, service yards
behind. `BACK_ROW_Z0` moved from `GARAGE_Z0` to `TIP_Z1 + NEIGHBOUR_GAP` and is asserted
equal to `SOUTH_ROW[-1][0]` — the two rows now stop level against the same fence *because
they are stopped by the same fact*, not because two numbers agree today. The row grew
10 → 15 houses without a count being typed anywhere.

**Build B, the library line.** `NorthParade` — POST OFFICE and TOWN BARBERS, x −52.6..−12.6,
z 228..308, facing **west** across the street at the café and the community hall. The east
side of that street was houses to the park and then eighty studs of nothing, which is what
gives a street a back to it. Detached with `WEST_GAP` between, where the tip parade is a
terrace: down there the band is 76.5 studs and two units plus a gap need 80, so the terrace
was the only thing that fitted; up here the band is 80 to the stud and the gap earns its
keep as the only way off that pavement. Deliberately narrower than `ALLEY_MIN`, so no
passage is claimed in the route graph that the ground does not show. Geometry and tag seams
only — **no `Config` entries**, because `Config.luau` is B's file.

### The park was being drawn inside a house, and all three gates passed it

`PARK_Z0, PARK_Z1` had been moved from `168..228` to `-88..-28` with the comment rewritten
to match ("beside the garage"). The park is x −44..4; number 18 stands at x −42..2, z
−86..−52. **A 44 × 34 overlap with a standing house** — pond, both paths, both benches and
the picnic table inside its front room.

Nothing caught it, and the three checks that live nearest the question are the reason:
check 5 compares *buildings to buildings* and a park is surface geometry; check 6 asks
about carriageways; check 7 asks about trees. Three checks in the neighbourhood and not one
of them asking it.

The same edit silently broke Build B. `NORTH_PARADE_Z0 = PARK_Z1` was written when
`PARK_Z1` was 228 and the band was the documented 80 studs. With the park moved it became
**336**, the two shops did not move, and what was left was **256 studs of empty frontage on
a finished pavement** — the exact defect the parade was built to remove, four times worse,
reported by nothing.

**And the assertion over it was decoration.** It read `assert 2 <= len(NORTH_PARADE) <= 3`,
and the upper bound *could never fire*: the row is built from a fixed tuple of two names,
so `n` is 0, 1 or 2 and never 3. A bound no generator can reach is not a loose check, it is
the appearance of one. It has been replaced by two that can fire — `len == 2` for the band
shrinking, and `NORTH_PARADE_SLACK < STORE_FRONT + WEST_GAP` for the band growing, which is
the half that was missing and the half that mattered. Plus an assert under `HOUSES` that no
house shares z with the park, in the generator rather than the checker because a generator
that can draw a park on a house should not be allowed to finish.

### The second stray edit: a waypoint whose label still told the truth

`wp_south_3` had moved from z −212 to −106. It is labelled "outside the garage"; −106 is up
beside the bakery. That puts it *out of order* with its neighbours and leaves a **127-stud
hop** down to `wp_south_4` against a 70-stud `ROUTE_LINK` — the bottom of the far walk off
the route graph entirely.

Every gate passed it. `check_town` does not ask about routing, `check_city`'s reachability
is scoped to the city, and **the label still read "outside the garage"**, so nothing about
the line looked wrong to a person reading it either.

The reason it survived is the interesting part: `_check_chain` was already being run on
`corner_n, wp_north_1..5, wp_top_junction` — the north half of that pavement — and on
nothing south of the school. One continuous walk, five points each side, identical
neighbouring lines in the same literal, and only one half checked. The defect landed in the
unchecked half. `_southwalk` now covers the other five. `_check_chain` sorts before pairing,
so a point that drifts out of sequence surfaces as the oversized hop it leaves behind.

### `roof_groups`, and a count that said what was wrong for two days

check_town's unit of "a building" was the **top-level group**. That is the same thing as a
building for a house or the bakery and quietly wrong for a parade: `TipParade` is one
top-level group with two shops in it. So check 4 asked whether *the parade* had a place
point anywhere in it and answered yes on the strength of one unit's, and check 5 could not
see two units of one terrace standing in each other at all. Four buildings were checked as
two. The header printed the symptom the whole time — 36 before a parade of two went in, 37
after — and nobody read it, because nobody had said what the number counted.

`roof_groups()` keys on the innermost group holding a `Roof`, chained through the whole
group path (every house's inner group is called `HouseStructure`; fifteen under one key is
the exact merge it exists to undo). **37 → 39 buildings.** Ground-floor walls 145 → 141;
the four dropped are `BoxBank`, `HallEast1`, `HallEast2` and `Ovens`, all interior fittings,
so the new set is strictly more correct. Negative-tested by giving only the first parade
unit a place point — check 4 named `NorthParade/TownBarbers` and failed, which it could not
have done before.

### Smaller things

- **`clear_of_forecourts` had a zero-width x band.** `min/max(FRONT_X, FORECOURT_X0)` —
  two names for the same number, −112 — so it answered "clear" for every point in the
  world, including the tree it was written to catch. The two names are worth keeping; the
  width between them was never a width. Now `FORECOURT_X0..FAR_WALK_X0`, which is the span
  both generators actually pass to `box`.
- **`TRUNK_WIDTH = 1.6` moved into `world_plan.py`.** `tree()` is written out three times
  and all three had their own 1.6. They agreed. Nothing made them. The canopy is
  `CanCollide false` on purpose, so the square a tree occupies is its trunk — and check 7
  measures trunks. Asking the filter with the canopy instead refuses the tree outside the
  school over a one-stud overhang: a filter that refuses what the checker would pass is a
  second opinion nobody asked for, and it costs real trees.
- **`build_street.py` was asking `clear_of_alleys` where it needed `clear_of_paving`.** A
  call site that enumerates hazards only knows about the hazards already paid for. Street
  486 → 483 parts.
- **check_town's report was filing failures under the wrong heading.** stdout is block
  buffered the moment it is piped, so every FAIL line surfaced *above* its own section
  header and check 7's first negative test read as a check 6 failure. `line_buffering=True`
  on both streams.

### State

`Town.rbxmx` 2064 parts / 44 pieces · `City.rbxmx` 11874 / 499 · `Street.rbxmx` 483 / 14,
all md5-stable across consecutive runs. **check_town 8/8** (121 place points, 39 buildings,
10671 colliding parts), **check_city 12/12** (708 place points reachable, 159 destinations,
worst detour 1.51 at `wp_bridge_2`), **check.py all clean**. Nothing Studio-tested.

`tools/check_asserts.py` is new: it breaks one input per case and checks that the *right*
assertion fires, with a control run that catches a guard firing unconditionally. **6/6.**
It covers the north parade block and nothing else — six of the forty-odd assertions in
`gen_town.py` — and it says so at the top, because a harness read as coverage it does not
have is how the `2 <= n <= 3` bound survived in the first place.

**Open.** The `wp_south_*` chain is five typed literals whose labels are approximate:
`wp_south_1` "outside the clinic" is at −124 against `CLINIC_DOOR = -98`, and the north
half has the same drift. They are route-graph nodes on a ~44-stud pitch, not door markers,
so the positions are defensible and the *labels* are what lie — worth deriving both halves
from the door constants in one pass, which will move points and needs check_city re-run.
Also still open: the road-group naming split between `build_street.py` (`Road` group) and
`gen_town.py` (carriageways inside `Ground`); `clear_of_paving`'s alley half is conservative
until `RETURN_X1` moves into the plan.

## 2026-08-19

**The town stopped being one street deep.** Asked for "more houses and depth and stuff
behind the school and bakery and stuff so the town doesnt end at the spawn point, along
with more stuff along the town library instead of a dead end". Spec'd back and approved:
*"open it and yes cafe and community hall"* — so the north end **opens onto the city**
through a gate matching the southgate rather than being closed off, and the library end
gets two more buildings.

**What the measurements said before anything was built.** The town was six civic
buildings on one back wall with a single house row opposite. Behind them sat
`GrassWestMargin`, 104 × 364 studs of one bare slab — about two fifths of the footprint.
Lying in it was `RoadReturn`: 181 studs of *finished* carriageway, with pavement, kerbs,
lamps and dashes, that stopped halfway and connected to nothing. And `wp_north_3` was a
leaf on the route graph, so the entire north end was a spur — every town↔city journey
went via the gate road, the southern link or the green. The request was not for
decoration; it was for the half of the town that was already drawn to be finished.

**Built:** a back street of ten east-facing houses on odd numbers 1–19; the north gate,
drawn on both sides of the asset seam (`gen_town` and `gen_city`); a café and a community
hall north of the library; and three alleys through the west frontage. `NORTHGATE_*` lives
in `world_plan.py` because gen_town must keep its frontage clear of a road gen_city draws
and cannot import gen_city — the same reason `GATE_CLEAR` and `SOUTHGATE_CLEAR` are there.

**`house()` was generalised rather than mirrored.** The back row faces east; the original
faces west. A mirrored duplicate would have been quicker to write and would have put two
implementations of one wear ramp, one boarded-window rule and one cracked path in the
tree — the defect class at the top of this file, four times over. Instead `house()` takes
`x0/x1/walk_x/facing` and does its own arithmetic through `inward()`/`outward()`, and
every x-span is `sorted()`, because a box whose x0 exceeds its x1 is a negative-size part
and not a mirror. The wear law is untouched: `wear_at(door_z)` is still one southward
z-ramp, and the back row reads it. A second rule for "the back of the block" was
considered and rejected for being a second table describing something the layout knows.

**The alleys, and the check that made them necessary.** With the row built and both ends
joined, `check_city` check 12 put the worst detour in the world at **2.02** — 533 studs
walked for 264 straight, standing in the middle of the new back street. That is what two
parallel roads joined only at their ends measure as: reachable, and still wrong. The route
graph can tell those apart; a player only experiences it as the town being annoying.

**Then the same defect class that this file keeps getting caught by, caught it again.**
The first fix cut one alley between the gym and the library, and the comment justifying it
said that was the only gap on the frontage wide enough to walk down. That was false. The
west frontage is built by **two files** — seven buildings from `gen_town.py`, the school
and the workplace from `build_street.py` — and the gap count had been taken from
`gen_town.py`, which can only see seven of the nine. The real gaps are workplace→school
**32**, school→gym **20**, gym→library **16**. The one that was picked is the narrowest of
the three, and the two that were missed are the two nearest the worst-detour point.

So `WEST_FRONTAGE` now lives in `world_plan.py`, all nine buildings in one sorted table,
and `ALLEYS` is *measured* off it — every gap of at least `ALLEY_WIDTH + 2 * ALLEY_MARGIN`
gets a cut-through. Three alleys, none of them chosen. Worst detour **1.82 → 1.51**, and
the worst point in the world moved off the town entirely (it is `wp_bridge_2` in the city
now). Margin against the 1.9 limit went from 0.08 to 0.39.

**A tree was standing in the middle of the first alley, and everything passed.** The alley
between the gym and the library was cut straight through the trunk at (-104, 160) — dead
centre of an eight-stud path — and the asset built, `check_town` went six green and
`check_city` went twelve green. Nothing either of them measures is *"is there a tree in
this footpath"*. Street trees want the frontage gaps for exactly the reason the alleys do:
they are the only grass left on that side. Both files planted into that strip and neither
could see the other's asset — the same collision that once put one trunk inside another at
(-104, 88). Fixed with `clear_of_alleys(z, spread)` in the shared plan, called from both
generators, so the tree that loses is dropped **by measurement**: a deleted line is a fact
about today's alleys, and a list goes stale the moment a building moves, silently
readmitting a tree that then stands in the road. Two trees dropped, every other one kept.

**One assertion failed its negative test and was rewritten.** `_check_joins` first asked
the weak question — "is there anything within the link radius that is not more of this
same alley". Walking the alley's west end ninety studs off the back street did **not** fire
it, because what it found instead was `school`, an interior place point on the far side of
the frontage. Destinations and roads are the same kind of thing to the route graph, so a
check that accepts either passes when an alley opens onto a wall. It now takes the named
set of back-street points. The east end is deliberately **not** checked locally: the main
street's waypoints at those z values are generated by `build_street.py` into another
asset and do not exist at that point in the program. `check_city` is the only thing that
can see both ends, and it does. An honest gap beats a check that pretends.

Every new assertion was negative-tested by patching the source and confirming it fires
with a message naming the offending value: frontage overlap, `WEST_GAP` stops being one
number, too few alleys, too many alleys, alley waypoints past the link radius, alley west
end off the back street, and the back-row count.

Verified: `Town.rbxmx` 1592 parts in 37 pieces (md5 `a225bfd1225cee2098329cb7987b4a05`),
`Street.rbxmx` 486 in 14, `City.rbxmx` 11874 in 499 — all three byte-identical across
consecutive runs. `check_town` all six green (101 place points, 30 buildings, up from 59
and 18), `check_city` all twelve green (688 place points reachable, worst detour 1.51),
`check.py` all clean.

**Still open in this lane:** the road-group naming split — `build_street.py` puts
carriageways in a `Road` group and `gen_town.py` puts them inside `Ground` — which is why
`check_city`'s carriageway count has to know about both. Gangs still deferred; the tip is
still laid out to become territory. Map stages 2–4 unstarted.

## 2026-08-18

**The street the player spawns on now goes somewhere, and gets worse on the way.** Asked
for the area around the spawn house to feel poorer, for almost-broken houses past that
part of the neighbourhood, for a landfill, and for the map to expand south. Approved
scope: residential frontage only, scavenging as a real verb, gangs deferred.

**Decay is a function of distance from your own front door, not a list.** The one design
decision worth keeping. A hand-written list of which houses are run-down is a second
table describing something the layout already knows, and this file has been bitten by
that class four times. `house()` takes a `decay` 0..1 solved from the door's z against
the street, everything visual goes through `worn(color, amount, toward)`, and features
switch on thresholds of the same number. Measured out of the built asset, house / door z
/ decay / parts / boarded windows:

| 14 | 105 | 0.30 | 25 | 0 |
| 16 | 145 | 0.30 | 25 | 0 |
| 18 | -69 | 0.42 | 26 | 0 |
| 20 | -113 | 0.50 | 28 | 0 |
| 22 | -176 | 0.62 | 32 | 0 |
| 24 | -216 | 0.69 | 32 | 0 |
| 26 | -256 | 0.77 | 33 | 1 |
| 28 | -343 | 0.93 | 34 | 2 |
| 30 | -383 | 1.00 | 34 | 2 |

Monotone in the geometry, not just in the source. Move a house and its condition moves
with it; add house 32 further south and it is the worst one without anybody deciding so.

**The street runs out.** The loop closed at z -290..-313 and simply stopped. A dead-end
spur continues south in the same x band to the tip gate, with plots 28 and 30 on it, and
the tip fills z -500..-400 across the full town width — chain-link, a gate the spur dead
-ends into, spoil mounds, skips, wrecks, two floodlight masts, a weighbridge plate and a
weighbridge hut, and the city's boundary treeline continued west so the south edge of the
world closes in one line rather than two treatments meeting in the middle.

**Three things nothing in this tree could have caught, now assertions.**

- *The route graph would have broken silently.* House 26's waypoint is z -256.2 and house
  28's is -343 — 87 studs against a 70-stud link radius. Everything south of house 26,
  the entire tip included, would have been unreachable, and `check_city`'s connectivity
  check passes because the town points it can reach are still one component. Fixed with a
  crossing either side of the link road (`wp_cross_n`/`wp_cross_s`) and a `ROUTE_LINK`
  assertion that walks the whole south chain in z order and names the two points that are
  too far apart. Negative-tested by deleting the crossing: it reports the 87-stud gap.
- *A hand-typed yard layout had five real collisions* — a floodlight mast standing inside
  a spoil heap, two heaps through the hut, a wreck in a mound. A table of centres says
  nothing about extents, and `check_town`'s overlap check compares *buildings*: a spoil
  heap has no `Roof` part, so it is not a building and was never in scope. The separation
  rule is now in the generator as a pairwise assertion over everything placed in the yard,
  at `TIP_CLEAR = 2 * BODY_WIDTH`. Derived, not chosen: `BODY_WIDTH` is already this
  file's answer to how much room a person needs, and twice it is a gap two people pass in
  — the difference between a yard with routes through it and a maze of dead ends.
- *The gate that got built was not the gate that was declared.* `TIP_GATE_MARGIN = 5.0`
  says a 33-stud opening at x -92.5..-59.5. The built opening was 24 studs at -88..-64,
  because `chainlink()` laid panels on one pitch across the whole boundary and dropped the
  ones whose midpoint fell in the gap — and **no posts survived at the opening at all**,
  because the post rule needed an adjacent surviving panel and at the gate neither
  neighbour had one. The constant said 5.0 the entire time and nothing compared the
  constant to the geometry. `fence_runs()` now splits at the gate's exact edges and
  subdivides each run independently, and an assertion asks `fence_runs()` what it produced
  rather than trusting the constant. **A declared measurement quietly rounded to a
  construction grid** goes on the list next to the other four recurring defect classes.

**Signposting.** The player walks 300 studs of worsening street, crosses the link road and
arrives at a chain-link fence. Unnamed, that reads as the edge of the map and they turn
round six strides short of the only yard in town with anything in it. `TipSignBoard` is as
wide as the hole it names and butts against the west gatepost, so sign and entrance are one
object; `TipNotice` under it says salvage is permitted, which is the *permission*, not the
prompt — the prompt is the three dots on the skips. Both boards derive their canvas from
their own size at a fixed `SIGN_PX`, because `sign()` stretches its canvas over whatever
face it lands on and a text size quoted in canvas pixels means nothing until you know how
many studs a pixel is.

**For B — a tag contract, half-built on purpose.** Eleven parts in the tip carry
`AgesScavenge` with a `ScavengeKind` attribute: 4 `skip`, 4 `pile`, 3 `wreck`. Same shape
as `AgesGymEquipment`/`GymKind` — geometry stamps the tag, the service finds it by tag and
never by name or position, and the two rebuild independently. **There is no `Config` entry
behind it and I did not write one**: `Config.luau` is yours. The geometry being ready first
is the point of a tag contract, not a gap in it. Place points to hang it off: `tip`,
`wp_tip_gate`, `tip_office`.

Town.rbxmx 1079 parts in 25 pieces, md5 `50563a826cdf4bd298f883db4eb6ae96`, reproducible
across consecutive runs. `check_town` all six green (59 place points, 18 buildings),
`check_city` all twelve green (159 destinations, farthest 18.0 from a carriageway; all 645
place points reachable, worst detour 1.51). `check.py` clean in every check in my lane —
the require cycles among `EventService`/`DeliveryService`/`WorldEventService` and the unused
`yearJustEnded` at `PeopleService.luau:2044` are yours and are untouched.

**Nothing here has been Studio-tested.**

## 2026-08-18 (later)

**Four school events have never been able to fire, in any build, and every check in
this tree was green about it.** `assets/SchoolFurniture.rbxmx` was mounted in neither
project file. It holds the four invisible `AgesEvent` anchors carrying `EventId`
`school_notice_board`, `school_water_fountain`, `school_locker_note`,
`school_library_book` — and `WorldEventService` resolves an anchor by
`CollectionService:GetTagged` and by nothing else. There is no coordinate fallback. The
four events are written in `LifeEvents/School.luau`, inventoried in `Config.School.Anchors`
with positions that match the generator exactly, and were unreachable.

**Why nothing saw it, which is the part worth keeping.** `rojo build` reports on what a
project file *does* mention; a file it was never told about produces silence, and silence
is not an error. And both world checkers glob `assets/*.rbxmx`, so the asset was being
read, measured and reported green by `check_city` and `check_town` on every run — the
checkers were validating geometry that no player could stand in. **A checker that
discovers its own inputs will happily certify a file that ships nowhere.** That is a
general hole, not a school one: any future asset gets the same treatment.

`DebugService`'s `/school interact` prints "not tagged" per anchor and its comment says a
missing tag means "the furniture model has not been placed yet". All four have been saying
it. A debug path that reports the defect correctly is not a gate — nobody runs it unless
they already suspect something.

**The gate: `check.py` check 3, "every asset is mounted".** Globs `assets/*.rbxmx`,
recursively collects every `$path` in both project files, and fails on any asset no
`$path` covers. It counts a directory mount as covering what is under it, so it does not
depend on assets being mounted one file at a time. It lives in `check.py` rather than in
either world checker because the question is not geometry — it is whether a built place
contains the thing. Negative-tested in both directions: it fired on the real defect before
the fix, fires on a synthetic unmounted asset, and confirms the `src/shared` directory
mount covers a file beneath it.

Fix is one mount in `default.project.json`, next to `Street` because the school building
itself is generated by `build_street.py`. Verified by decoding the built place rather than
by trusting the build: the anchor's `Tags` deserialises to `AgesEvent` and its
`AttributesSerialize` to `EventId = school_notice_board` inside `/tmp/ages.rbxlx`.
`SchoolFurniture.rbxmx` regenerates to an identical md5, `check_city` and `check_town`
both still all-green with the new geometry in scope.

**Open, and for whoever owns the seam**: the four school events have now *never* run, so
they are unplayed content rather than working content — treat them as untested, not as a
regression fixed. `Config.School.Anchors` still holds a second copy of the four positions
that only the debug printout reads; it agrees with the generator today and nothing
compares them.

## 2026-08-18

**`check_town.py` exists, and the town was not clean.** Four entries in this file say the
town has no geometry gate and that I would write the checker first. It found two defects on
its first run, and the more interesting one is that **the bakery's place point was standing
inside the bakery counter** — a 10x10 solid, the point four studs in. The game's own
instruction for that building is "the bakery, at the counter", and the spot it named was in
the furniture. Two lines above it in the same table, the corner shop's point carries a
comment claiming it is stood in front of its counter "which is what every other 'at the
counter' point in town already means". It did not. A comment that documents a rule the file
breaks two lines earlier is worth more attention than a comment that is merely stale.

Nothing could see it, and the reason is worth stating exactly: **the fittings are laid out
by a generator that never reads the place point table, and the place point table is a list
of coordinates that never reads the fittings.** Ground-under-the-point passes — there is a
floor, the counter is standing on it. Building-overlap compares buildings with buildings and
a place point is neither. The two were never compared anywhere until now.

**The second: three of the four return-road waypoints floated half a stud**, written at
`PAVING` while standing on a carriageway that tops at `GROUND`. The fourth said `GROUND` and
was right — one line getting fixed and its three neighbours not. Half a stud is nothing to
look at. It is a failure because the height a point declares is a *claim about which surface
it is on*, and three of them claimed a pavement fifteen studs east.

**Why a second file rather than more checks in `check_city.py`, which is the thing I
expected to conclude the opposite.** Almost every check over there is scoped to the city by
construction and **the scoping is invisible in the check's own name** — "ground under place
points" walks `city_points`, "building overlap" walks `city_models`. The one exception is
check 7, widened to all assets after the gate road was found running through a town house,
and widening it is what showed the rest had the same hole. The town has been carrying twelve
green checks that were never asking about the town. Readers and geometry are *imported* from
`check_city`, not copied — a second rotation-aware rbxmx reader is two copies of one
measurement, which is this tree's most-repaired defect.

**The one genuinely new check is 3, "room to stand".** A place point is not a label on a
map, it is where the game leaves a player standing, and nothing here had asked whether a
body fits. Two things make it report signal: the band starts at `STAND_STEP` 2.0 rather than
at the floor, because a humanoid walks over anything below its hip and a band starting at
the floor reports every rug, kerb and book in the game; and `STAND_CLEAR` 1.0 is *derived* —
`HumanoidRootPart` is two studs wide — with the measurement confirming the margin rather
than setting it (worst honest 1.51, next 2.00, defect *inside*).

**What it deliberately does not check, which took as long to decide as the checks did.**
"Is the road network one piece" **does not transfer from the city.** In the city a road is a
slab on top of the ground; in the town it is a tile *of* the ground, so unioning the jigsaw
returns "one piece" for a town with no roads in it. I wrote it, measured it, saw it answer a
different question, and removed it. That reading also turned up that the two generators
disagree about where a road lives — `build_street.py` uses a `Road` group, `gen_town.py`
puts its four carriageways in `Ground` — which check 6 special-cases and which wants
unifying. **Left open on purpose.**

Fixes: `COUNTER_DEPTH` is one constant shared by the bakery's counter and the corner shop's,
with an assertion in the generator that fails on its own line and names the fix; the five
west-side literals `-120.0` are `WEST_SPOT_X = FRONT_X - 8.0`; all four loop waypoints derive
x from `RETURN_MID`. All six checks negative-tested by making the change each forbids, plus
2 and 3 against `git show HEAD:assets/Town.rbxmx`. The assertion negative-tested too.
`Town.rbxmx` reproducible to one md5, `City.rbxmx` and `Street.rbxmx` untouched, all twelve
city checks still green.

**Still open in my lane**: the town's west frontage `z -280..-204`, B3 (deferred), map
stages 2–4, the road-group naming split above. `check.py` still FAILS, still entirely Agent
B's — two require cycles, `recordInteraction` undefined at `PeopleService.luau:507`, unused
`yearJustEnded` at 2044.

**Nothing here has been Studio-tested.**

## 2026-08-17 (late night)

**I built the Backs, it passed all twelve checks, and it was the wrong thing to build.**
Avenue 1 runs the full height of the map thirty-five studs east of it on the same axis. A
second carriageway that close and that parallel is not a route, it is the same route drawn
twice, and the only thing distinguishing mine was being nearer the player's fence. I had
measured a 40.65-stud corridor, found it was exactly one street wide, and let *fits* stand
in for *belongs*. It is now **the Green**.

The lesson is narrower than "no redundant roads", and it is about the checker rather than
the road. **Every check in `check_city` measures a road against itself** — connected (8),
carved (10), reaches the buildings (11), reachable from the spawn (12). Nothing measures a
road against the road beside it, and nothing ever should, because "these two are the same
street twice" is a judgement about a map and not a property of geometry. The green passes
exactly as well as the street did. *Passing is not being right.* Four consecutive entries
in this file end with "all checks green" as though that settled something.

**And taking the street out took a route with it, invisibly.** The connector's mouth at
(30, 60) is 85 studs from the spawn; with only the gate spur left it became a 203-stud walk
out of the front door and round — **check 12 at 2.40**, a fail, on a change that was pure
subtraction. The fix is a footpath spine down the length of the green. It is not decoration
and it is not symmetry, it is the route, and the general form is worth carrying: **what
that corridor needed was a way through, not a carriageway**, and those are not the same
requirement. A path routes as well as a road and costs a strip of stone. Worst detour
**1.51** with it, 636 points, all reachable.

Written so the spur owns the crossing square and the spine is two boxes, because two path
slabs laid across each other at one height is the coplanar pair this file has been bitten
by twice. **No grass box**: `CityGround` already lays lawn there at that tone and height,
and a second one is the same defect a third time — pulling the carriageway out *is* the
grass. Trees in a two-line belt down the avenue side with a gap on the path's line, so the
player can see the avenue from their own back gate and knows where they are walking to.

`ROUTE_STEP` (68) replaced a bare `68` in nine separate `range()` calls — the shape of a
number that gets changed in eight places. Value unchanged, so `City.rbxmx` is affected only
by the green.

Negative-tested by emptying the spine loop: 2.40 at `wp_conn_0`, named. `City.rbxmx`
reproducible to one md5 (11859 parts in 499 pieces) across the restore. `build_street.py`
comment corrected and `Street.rbxmx` verified byte-identical. `MAP_PLAN.md` B1 says
"reverted" at the point it claims the Backs was built, rather than being quietly rewritten.

**Unchanged from the entry below**: no `check_town.py`, the town's west frontage
`z -280..-204` still deliberately bare, B3 deferred. `check.py` still **FAILS**, still
entirely in Agent B's lane — the same two require cycles plus `recordInteraction` called
and never defined in `PeopleService.luau:507` and an unused `yearJustEnded` at 2044.

**Nothing here has been Studio-tested.**

## 2026-08-17 (night)

**B1 and B2 are built, and the thing they found is worse than the thing they were asked
to fix.** The brief was "the spawn house is at the end of the map, make it more populated".
Measuring the result properly turned up this: **the spawn could reach 23 of 620 place
points, and not one of them was in the city.**

The near sidewalk had no place point outside the player's own front gate. That left a
76-stud hole in the chain — six studs over `ROUTE_LINK` — which severed the spawn from the
north half of its own street, and the only road into the city left from that half. So every
route out of the spawn went south, round the loop, and stopped. Not a slow path: no path.

Nothing in this tree could see it, and it is worth being precise about why. `check_city`
check 4 asks two questions — is the city one connected component, and does the city reach
**at least one** town point. Both were true. The city reached the town at the far end of a
chain the player was not standing on. *"At least one" was the bug*, and I wrote in
yesterday's entry that the missing check was "how many links are there between the two
places". That was the right instinct pointed at the wrong quantity: link *count* is a proxy.
The quantity is "can the player get there, and how far out of their way".

**`check_city` check 12, "Every place reachable from the spawn"** — Dijkstra from the spawn
pad over the route graph, asking both. Reachability, and a detour ratio (`MAX_DETOUR` 1.9)
of walked distance against straight-line. Both halves are load-bearing and the numbers prove
it: before this session, 597 unreachable and a worst ratio of 1.20; after the two new roads,
0 unreachable and a worst ratio of **2.56**; after the missing waypoint, 1.47. The
reachability half is blind to the middle row, the ratio half is blind to the first — a ratio
can only be computed for somewhere you can already get to. Negative-tested against
`git show HEAD:assets/*.rbxmx`: exit 1, "597 stranded".

The threshold is 1.9, not the 1.47 the world measures. A ratio gate is a smoke alarm, not a
tape measure; tightened to the current worst it fails the next time somebody adds an honest
cul-de-sac, and a check that cries wolf gets deleted.

**Built.** *Southgate* — works cross street 1 carried west to the town's kerb, the second
link, straight into the works district where the job points are. *The Backs* — north-south
behind the spawn plot, `x 44..67`, elbowing onto avenue 1 at both ends. Both land on mouths
that already exist in `Ave0PavW`, so no new junction tiles and no carve-list entries. *The
back gate*, with `wp_backs_gate` outside it. *Three houses*, 22/24/26, on the town's east
frontage below the corner shop.

**Two things I got wrong inside this build and want the next person to see.**

The back gate was first `GATE_HALF / 2`, which reads fine in a plan and gives **3.1 studs of
clear gap** — narrower than any interior door in the game. Fixed by deriving it from
`INNER_DOORWAY`, a width the player has already been proven able to walk through, and
`DOORWAY`/`INNER_DOORWAY` moved up `world_plan.py` to sit beside the gate constants. Every
opening a player walks through should be one of those two numbers or say why not.

The south row was specced as "four houses, numbers 22–28". It is three, and it is not typed:
`SOUTH_ROW` reads depth, pitch and numbering off houses 14/16 and lays plots until one will
not fit, so the frontage decides the count. It steps *over* `SOUTHGATE_CLEAR` rather than
stopping at it. Negative-tested by disabling that exclusion — the row puts house 28 across
the new carriageway and check 7 says so, which is the corner-shop/`GATE_CLEAR` story
repeating word for word. House place points are generated from `HOUSES` now; the four
originals were literals, which works right up until a fifth house exists with no point in it.

**Still open.** The town's west frontage `z -280..-204` is bare and takes exactly one house
at the civic side's spacing — left alone on purpose, since clinic/bakery/garage is what makes
that side read as a town. B3, the theme park, is deferred by the owner; the spec in
`MAP_PLAN.md` is the part that matters (a ride you watch is a prop, a ride that pays out for
standing on it is the idle pad). `check_town.py` still does not exist. `tools/check.py` still
FAILS on three require cycles in `src/` — `DeliveryService`/`WorldEventService`/
`EventService` — which are Agent B's and untouched.

## 2026-08-17 (evening)

**I got task B wrong a second way, and the second way is more interesting than the
first.** This morning's entry says there are 74.5 studs of bare grass behind the spawn
house. That number is the distance to the first thing standing above y 3, and **a road
does not stand above y 3**. `Ave0Road` is a 24-stud arterial at x 79..103 running the full
height of the map, z -434..200, forty studs from the player's back fence. The genuinely
bare ground is **x 32.35..73 — 40.65 studs**, which is one street wide and not one stud
more. My probe filtered for obstructions and I read "nothing is in the way" as "nothing is
there". That is the same mistake as the missing fifth asset, one layer down, and both were
in output I had already printed.

**The real fault is not emptiness, it is that the town has exactly one way into the city.**
The gate road stops at `CONN_X0 = 19`; the connector runs *north* from `CITY_Z0 = 60`;
`Ave0PavW` is unbroken from z -430 to 196 except at its own junctions and nothing meets it
from the west below cross street 1 at z 200. So the walk from the back garden to the road
forty studs behind it is about **six hundred studs**. `check_city` 8 and 11 both pass and
are right to — 8 measures the road surface inside the city, 11 measures models to
carriageways. Neither asks how many links there are between the two places. That is a
missing check and I have not written it.

**The owner's brief redirected the section**: populate around the spawn house — a theme
park (good, farther away, *explicitly deferred*), a few medium houses, roads back into the
city. `MAP_PLAN.md` B1/B2/B3 is the spec, awaiting a go. The load-bearing finding is B2:
40.65 studs holds a street and nothing else, so the houses **cannot** go where the
complaint points; they go on the town's own frontage, 174.8 bare studs south of the corner
shop, which is where the player actually walks. B1's south end elbows onto Avenue 0 at
`z -136..-106` because that gap in `Ave0PavW` is a junction that already exists — landing
on it rather than cutting a new one keeps check 11 green by construction.

**Committed: the option-A fence** (`1a003c1`) — the plot's south and east boundaries, 96
studs not 170 because three sides were already closed. `fence_run` takes an axis now;
byte-identical for the two pre-existing runs. `check_plot_boundary()` re-measures what it
does not build, all three assertions negative-tested. Its reasoning ("the front gate
becomes the only link") is now overruled by the brief, but the fence itself survives it —
it becomes a garden fence onto the Backs. **It wants a back gate**, which is the one open
question blocking B1.

**Half a day lost to a stale `.pyc` in a directory that is not in the tree.** macOS system
Python 3.9 writes bytecode to `~/Library/Caches/com.apple.python/<abs path>/`, not to
`tools/__pycache__`, so `ls tools/` shows nothing and `git checkout` cannot clear it. A
negative test had set `FENCE_Z1 = 30.0`; `30.0` and `22.0` are the same byte length, the
restore landed in the same second, mtime and size both matched, and the cache was reused.
`build_street.py` then failed for an hour against a source line that plainly read `22.0`.
If a generator disagrees with its own constants, `rm -rf ~/Library/Caches/com.apple.python`
before believing anything else.

`check_city` green on all eleven. `check.py` **FAILS**, entirely in Agent B's lane —
require cycles `EventService -> DeliveryService -> WorldEventService -> EventService` and
two unused locals in `Zones.luau`/`EventService.luau`. Syntax clean and both places build,
so this morning's `EventService` syntax error is fixed. Nothing of mine is implicated.

**Nothing here has been Studio-tested.**

## 2026-08-17 (later)

**Task B is measured, not built, and I got it wrong once on the way.** The plan says
"confirm with an occupancy map before designing anything", so I did, and my first answer
was that there is no ground behind the spawn house at all — that the building overhangs
its slab by 24 studs and the world ends at its back wall. I had loaded `Town`, `House`,
`Street` and `Furniture`. The ground behind the house is in `City.rbxmx`. Every number I
measured was right and the conclusion was wrong, and I had already written it into
`MAP_PLAN.md` and started editing `world_plan.py` and `gen_town.py` against it. Both edits
are reverted; the entry now leads with the retraction.

The tell was in my own output and I read past it: the town's grass ends at exactly x 8.0
and the city's ground begins at exactly x 8.0. A boundary that lands on a round number
shared with the file you left out is a seam, not a cliff. `default.project.json` mounts
**five** assets into one place and the world is only their union — the occupancy script
printed in `MAP_PLAN.md` section B loads four, which is how the wrong answer was available
to be reached at all.

The real finding: **74.5 studs of bare grass between the house's back wall (x 32.5) and
the portico of a 134-stud office tower (x 107)**, over about `x 32.5..107, z -112..56`.
The complaint is right. What the measurement adds is that the plot has *no rear boundary* —
the fence is a single line on the street side over `FENCE_Z0..Z1`, so the player walks out
of the front door, round either end of it, and is on city ground having crossed nothing.
So the question is not "what fills the gap", it is "where does the plot end", and that is
a spec to agree before it is built.

Two things for whoever takes it. It is `gen_city.py`, not `gen_town.py` — the plan asserts
the opposite and is wrong. And `EAST_X1 = 8.0` in `gen_town.py` and `CITY_X0 = 8.0` in
`gen_city.py` are two literals in two files for one seam, each commented to point at the
other; they agree today and nothing makes them. That belongs in `world_plan.py`.

Also do not size anything off an axis-aligned bounding box in `House.rbxmx`. Two of its
panels are 31.3 studs on their local X and turned ninety degrees, so an AABB puts the east
wall at 46.9 and is wrong by fourteen studs. `read_house.load()` applies the rotation.

`check_city.py` green on all eleven. Nothing in `tools/` or `assets/` changed, so both
assets are untouched. **`check.py` currently FAILS**, on `EventService.luau` — a stray
`end` at line 381 and a call to an undefined `characterPosition` at 245. That is Agent B's
file, uncommitted and mid-edit, and I have not touched it.

Committed separately today: the spawn note in `world_plan.py`, which claimed the
SpawnLocation was at the front gate. It is in the nursery, moved there by `ec34680` and
`326137b`, and the note had become an instruction to undo both. Comment-only; both assets
regenerate to identical md5s.

## 2026-08-17

**Task D is done, and the plan's own instruction for it was wrong.** `MAP_PLAN.md` said
"make `AVE_W` a per-avenue list", so that is what I started. Avenues run north-south.
The city's wealth gradient does not: `house_tier` picks a block's houses from its
Chebyshev distance to the Circle, the Circle is near the *south* of the grid, and every
residential block is north of it — so all five HOUSE blocks in sband 4 come out at 3.5
rings and all four in sband 3 at 2.5, **whatever their avenue band**. The houses get
smaller as you walk north and they do not care which avenue you are on. Following the
instruction as written would have been a 23-site refactor that changed nothing anyone
could see. `CS_W` is a list too, and that is the half that carries the ask.

Which streets narrow was read off things `gen_city.py` already states, not chosen:
`WORKS_AVE = (0, 3, 5)` ("those are the ones with somewhere to go") and `CIRCLE_AVE`
between them account for four of the six avenues, leaving 2 and 5; `ROLES` puts the park
and nine of the ten house blocks in the two sbands bounded by cross streets 4 and 5.
Measured off the generated file: avenues 2 and 5 at 16 against 24, cross streets 4 and 5
at 14 against 22, works streets untouched at 22. The narrow streets land exactly where
the small houses already are, so the two gradients now agree.

Narrowing is the only safe direction — a carriageway is subtracted from the block
interior either side of it, so every stud off a road is a stud back to the blocks, and
the interior was *only just* affordable at 24. Nothing had to move to pay for this.

**Six assertions, each negative-tested by making the change it forbids.** The one worth
knowing about: narrowing cross street 2 takes the Circle off its own junction, and that
*is* already caught — by check 10, as **1004 coplanar pairs**, naming no street, no
number and no file. Diagnosis is not detection. The assertion fails in the generator on
the line that is wrong.

Also caught before it shipped rather than after: `AVE_Z1` was the literal `972.0`, which
is `CS[5] + 22` and was true only while every cross street was 22 wide. Derived now.
That is this file's recurring defect for the fifth time and the first one found early.

`WCS_W` is held separately on purpose — the works' streets and the precinct service road
keep 22, so narrowing a residential street can never quietly narrow the one the timber
mill loads from.

Eleven `check_city` checks green, `check.py` all clean, both places build, `City.rbxmx`
reproducible to one md5, `Town.rbxmx` byte-identical. 11784 parts, one more than before:
one extra centre-line dash, because dash runs are carved at the crossing roads and four
of those moved. I accounted for that part rather than assuming it.

**Still not done:** task B (behind the spawn house), task E / map stages 2–4, the job
code for the works place points and `north_shop_2/4/6`, and there is still **no
`check_town.py`**. Task E is now the only thing left in my lane that is a build rather
than a decision, and it needs the coastline call first (docks want water: bay or a new
west shore).

**Nothing here has been Studio-tested.**

## 2026-08-16

**The corner shop was built standing in the road, and has been moved.** It went into the
gap between the player's plot and number 14 on the reading that the gap was the street's
largest bare frontage. It is not: it is the window the gate road leaves town through, so a
44-stud building stood across the only link between the town and the city. `check_city`
check 7 catches this in one line and I did not run it before committing `fda3290`. The
lesson is not "run the checker" — it is that the exclusion lived in the other generator, so
`GATE_Z0/Z1/WALK` and a derived `GATE_CLEAR` now live in `world_plan.py`, which both
generators import, and `gen_town.py` asserts against it. City output verified byte-identical
across that refactor.

The shop now stands opposite the bakery, same 17.2-stud shape, one street south. Its
interior was written in world coordinates and is now written as depths from its own south
wall — verified faithful by regenerating at the old bounds and diffing the group.

**New: `check_city` check 11, "A road to every door."** Task C's missing check. For every
city model containing a non-`wp_` place point, the gap to the nearest carriageway. 159
destinations, worst 18.0, median 8.0, threshold 32 — **it passes**, so there is no building
in the city without road access and the old note about 19 of them is stale. Negative-tested:
delete `PrecinctAve` and `NorthSvc` from `gen_city.py` and it fails, naming the eight
north-strip shops at 47 and 88.

Two formulations were measured and rejected before this one, and both rejections are
written up in `MAP_PLAN.md` section C. So is the **dead-end probe, which was abandoned**:
the Circle is not a chain of segments but an annulus tiled by twenty overlapping *radial*
planks, so a road slab's long axis is not the direction of travel and a per-part end probe
cannot answer the question. Anything replacing it has to work on the connected road surface
the way check 8 does.

**`City.rbxmx` is reproducible again.** `mall_shop` picked its wall tone with `hash(pid)`,
which Python randomises per process, so regenerating repainted the mall and the asset could
not be diffed. Now `zlib.crc32`.

**Also caught by the new walkability probe:** the shop's counter top overhung on both
sides, leaving 2.6 studs behind the counter at chest height over a base 3.0 clear — under
the 2.8 a body needs, and invisible from a floor plan. Overhang is now customer-side only.

`check_city` exits 0 on all eleven. `check.py` all clean. Both places build.

**Still not done:** task D (per-avenue road widths, ~22 sites — *done 08-17*), task B (behind the spawn
house), map stages 2–4, the job code for the works place points and `north_shop_2/4/6`.
Task A's *verb* is spec'd in `MAP_PLAN.md` and belongs to B — the shop is a stage with
nothing tagged in it, and tagging is a one-line change the day the verb lands.

**Nothing here has been Studio-tested.**

## 2026-08-14

**Landed.** The financial district steps down instead of falling off a cliff. Two rows
of offices ramp 195 -> 131/115 -> 83/67 -> 37 across five columns, mirroring the north
side's fade with the same two numbers, with an 18-stud paved mews between the rows. The
towers front south, so the northernmost new street is placed such that its far pavement
lands exactly on their front wall — they had been opening onto bare ground.

The works district moved 194 studs south to make room and **nothing in `works_*`
changed**: row depths are the constant and street positions are derived from them. This
is the pattern to keep. The recurring bug class in `gen_city.py` is a number measured
from other numbers and then typed in as a literal; the depot container pitch was one
(a literal `40`, correct for the row it was measured on, cutting 13 studs into a
pavement once the row moved) and it is now solved from the apron.

11783 parts in 498 pieces. All ten geometry checks green.

**Also landed, cross-machine infrastructure.** `tools/check.py` returned 0 when its
binaries were missing, so a machine with no toolchain printed `all clean` with the only
two checks that catch a fatal error never having run. That is now a hard failure that
names the path it wanted. Added `.exe` handling and a real temp dir for Windows.
`.gitattributes` pins LF and marks `*.rbxmx` binary. `globIgnorePaths` in both project
files stops rojo's watcher panicking on the `.tmp` files an agent's atomic save leaves
behind — that crash killed the server twice in one morning.

**Not done, and why.**

- The town's main road is bare on both sides. Specced three options, waiting on a
  decision. Note there is **no `check_town.py`** — the town has no geometry gate at all,
  so anything built there is unverified in a way the city is not. I would write the
  checker first.
- Map stage 2 (low-rise sprawl, x -1024..-280), stage 3 (docks — the quay is built and
  waiting on a coastline decision), stage 4 (downtown densification, must come after the
  grid is final).
- Task D: poor neighbourhoods get narrower roads (`AVE_W` -> a per-avenue list, ~22 sites).
  *Done 2026-08-17 — and the per-avenue framing was wrong; see that entry.*
- Task C: dead ends and buildings with no road. Write the missing `check_city` check first.
- Task A: shops. Blocked on a design question — when a player walks into a shop, what do
  they physically do?
- Job code for the seven works place points (`factory`, `works_canteen`, `power_plant`,
  `timber_mill`, `scrapyard`, `freight_depot`, `works_wharf`) and `north_shop_2/4/6`.

**For B.** `BodyService.luau` and `ReturnService.luau` are yours and I deliberately left
them uncommitted — the matched pair that waits for `Lives.HasBegun` before applying a
body. Commit them by name.

**Nothing here has been Studio-tested.** The gate is green, which means it compiles and
packages; it does not mean it plays.
