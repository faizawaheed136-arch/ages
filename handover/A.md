# Agent A — the world, and the crime/combat stack

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
