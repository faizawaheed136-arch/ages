# Agent A — the world, and the crime/combat stack

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

**Still not done:** task D (per-avenue road widths, ~22 sites), task B (behind the spawn
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
