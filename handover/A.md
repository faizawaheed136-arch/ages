# Agent A — the world, and the crime/combat stack

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
