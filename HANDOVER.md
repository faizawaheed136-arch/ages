# Parallel work brief — read this before you touch anything

There are two agents working on AGES in the same working tree at the same time. This
document is the contract between them. Read it, then write the "Ownership" and "Shared
files" sections into your memory, because a violation of either is not a merge conflict —
it is silent data loss in a tree where the other agent may have uncommitted work.

You are **Agent B**. The other is **Agent A**.

## The split

**Agent A owns the world.** The city generator and everything downstream of it:

    tools/gen_city.py      tools/world_plan.py     tools/build_street.py
    tools/gen_town.py      tools/house_plan.py     tools/check_city.py
    tools/rbxmx.py         assets/*.rbxmx

A is doing a single coherent pass over the map: widening the road grid for cars, giving
houses real size variation keyed to distance from downtown, densifying downtown, and
filling the empty south-west half of the baseplate with an industrial district, docks and
low-rise sprawl. Road width, block pitch and building footprint are one coordinate system —
they cannot be worked on by two people.

A also owns the crime and combat stack: `FightService`, `Fighters`, `FightUI`,
`world/Spotting`, `PoliceService`, `WitnessService`, `BountyService`, `GangService`,
`DisguiseService`, `TheftService`, `BankService`.

**You own the economy and the life layer.** Everything you have in flight:

    src/server/services/CarDealerService.luau   src/client/ui/CarDealerUI.luau
    src/server/services/HouseService.luau       src/client/ui/HouseUI.luau
    src/server/services/BillService.luau        src/client/ui/StatsUI.luau
    src/server/services/MilestoneService.luau   src/client/world/MilestoneFlash.luau
    src/server/services/GossipService.luau      src/client/world/BondCelebration.luau
    src/server/services/PeopleService.luau      src/client/world/BonusPop.luau
    src/server/services/WorkService.luau        src/client/world/MoneyPop.luau
    src/server/services/MoneyService.luau       src/server/services/BodyService.luau
    src/server/services/ReturnService.luau
    src/server/content/Jobs.luau, JobTasks.luau, Public.luau, Townsfolk.luau

## Ownership — the one rule with no exceptions

**Do not edit a file on A's list. Not to fix a typo, not to fix a lint error, not to add
one line.** There is uncommitted work in this tree on both sides. If you need something
changed in a file A owns, say so in your final message to the owner and stop.

If you find a real bug in A's code, that is worth reporting — write it down, name the file
and line, and hand it back. Do not fix it.

## Shared files — append-only, never reorganise

Four files are edited by both of us:

    src/shared/Config.luau      src/shared/Types.luau
    src/shared/Remotes.luau     src/server/services/DebugService.luau

Rules for all four:

1. **Add, never move.** Do not reorder blocks, do not re-sort keys, do not reformat, do
   not "tidy while you are in there". A whole-file reformat of Config.luau destroys the
   other agent's uncommitted edits in a way that is nearly impossible to spot in review.
2. Put new material in **one contiguous block** next to the material it belongs with, and
   nowhere else.
3. In `Remotes.luau`, a new remote name goes in **both** the `RemoteName` union **and** the
   `REMOTE_NAMES` list. Only Studio's analyzer catches a mismatch — the gate now checks it,
   so trust the gate here.
4. In `DebugService.luau`, add your command as a new `Commands.x = function(...)` and add
   it to `HELP_TEXT`. A command that is not in `HELP_TEXT` does not exist as far as anyone
   testing is concerned; two have already been shipped that way and found months later.

## Never touch these

- **`tools/` and `assets/` — nothing, at all.** A is regenerating the city. Any edit you
  make there is going to be overwritten, and any `.rbxmx` you regenerate will overwrite A's.
- **Absolute world coordinates.** The map is about to move. The contract that makes this
  safe is: **place-point ids are stable, place-point coordinates are not.** Look positions
  up by id through the tagged-part path in `src/server/world/Routes.luau`. If you ever find
  yourself writing `Vector3.new(366, 8, 357)` into a Luau file, stop — there are currently
  zero hardcoded city coordinates in `src/` and that is the only reason these two
  workstreams can run at once.
- `CLAUDE.md` — propose changes, do not make them.

## The bar

Every one of these is a hard requirement, not a preference. They exist because each defect
has already shipped into this tree at least once.

1. `--!strict` at the top of every file.
2. **No magic numbers in logic files.** Every tunable goes in `src/shared/Config.luau` with
   a comment saying what it does *and* a `-- Safe range: a-b` line. A number in a service
   is a number nobody can tune and nobody can find.
3. **Comment the *why*, not the *what*.** The comment explains the decision — what was
   considered, what it would break if changed. `-- adds 1 to the count` is noise.
4. **No orphaned code.** A field written and never read, a function with no caller, a
   parameter nobody passes — delete it. The build will not tell you. Grep every consumer of
   a field you change.
5. **No silent failures.** Content errors `error()` with a message naming the offending id
   and saying what to do about it.
6. State changes are atomic and server-authoritative. Decide the outcome, *then* write —
   never write and unpick.
7. Idempotency wherever a retry is possible.
8. **Every system ships with a debug path** in `DebugService.luau`.

Content rules: 13+ hard ceiling. No gore, no gambling, no romantic partners — ever, not
deferred. Combat *is* allowed. US English. Failure should be worth playing.

## Verification — do this before you hand anything over

```
cd /Users/ayeshwaheed/ages
python3 tools/check.py
```

That runs syntax, both place builds, dangling Config refs, require cycles, remote-name
consistency, unused locals, declaration order, and calls to undefined names.

Two things about it that matter:

- **`rojo build` does not parse Luau.** "Builds clean" means nothing. A syntax error in one
  module propagates through `require` and takes down *both places* with no error naming the
  file — the symptom is a place that loads with no services in it.
- **The gate is currently FAILED, and every failure in it is yours.** See your queue below.
  Until it is green, neither agent has a signal. This is why it is task one.

Do not run `rojo serve` without naming the project file. Plain `rojo serve` serves the
game place, and the Studio plugin will happily pour the entire town into an open lobby
place with no warning.

### Do not start a rojo server. Ever, in this arrangement.

There is **one** `rojo serve` for both agents, it is already running, and Agent A owns it:

    cd /Users/ayeshwaheed/ages && rojo serve      # port 34872, projectName "ages"

This is not a style preference. Only one process can hold port 34872, and this has already
cost a full session once: a `rojo serve` was running from a *completely different repo*
(`/Users/ayeshwaheed/Omniroute-test`) on that port, Studio was connected to it, and every
change either agent made for hours was written correctly to disk and delivered to nothing.
It presents as "my changes don't show up", which reads like a broken build rather than a
server pointed at the wrong project.

So:

- **Never run `rojo serve`.** If you think you need one, say so and stop.
- If you want to check what is actually being served, do not guess — ask the running server:
  `curl -s http://localhost:34872/api/rojo` prints `projectName`. It must say **`ages`**.
  Anything else means Studio is connected to the wrong thing and nobody's work is landing.
- To verify your own changes compile and package without touching the server, build to a
  scratch file instead: `rojo build --output /tmp/check.rbxlx` and
  `rojo build lobby.project.json --output /tmp/check-lobby.rbxlx`. That is what
  `tools/check.py` already does, which is another reason to just run the gate.

## Your queue, in order

Agent A has already diagnosed these. The findings below are things A verified by reading
the code, not guesses — but verify each one yourself before acting, because A did not edit
your files and could not test the fixes.

### Task 0 — the game is currently broken on boot. Fix this first.

`src/server/services/WorkService.luau:43` reads:

    local BonusPop = require(script.Parent.Parent.world.BonusPop)

From `src/server/services/`, that path resolves to `src/server/world/BonusPop`. **That
module does not exist.** There is a `BonusPop.luau` in `src/client/world/`, but the server
tree has only `MoneyPop.luau`. Indexing a Folder for a child that is not there raises
"BonusPop is not a valid member of Folder", and because `require` propagates errors to the
caller and WorkService is on the boot path, the symptom is **a place that loads with no
services in it at all** — not an error naming WorkService.

The gate reported this as a harmless "unused local". It is not.

The fix is almost certainly to **delete line 43**: `BonusPop` is unused in WorkService, and
the bonus popup is already driven client-side from `src/client/init.client.luau:610`. Do
not "fix" it by creating a server-side `world/BonusPop.luau` — that would be inventing a
module to satisfy a require that should never have been written. Check first whether the
server was ever meant to drive bonus pops; if it was, that is a design question to raise,
not to answer by stub.

While you are there, confirm no other service requires a `world/` module that only exists
on the other side of the client/server split. It is the same one-line mistake and it has
the same fatal, misleading symptom.

### Task 1 — make the gate green

Do not silence anything with a `_` prefix. An unused local is usually a half-finished
wiring job; the fix is to finish the wiring or delete the dead code. Per file:

**`src/server/services/GossipService.luau:21-22`** — `PeopleService` and `PlaceService` are
both imported and never used. Deleting line 21 also **removes the require cycle**
(`PeopleService:84` requires GossipService, GossipService:21 requires PeopleService back).
Do this before considering any restructuring: the cycle probably deletes itself here.

**`src/client/ui/CarDealerUI.luau:18`** and **`src/client/ui/HouseUI.luau:18`** — both
import `Remotes` and never use it. This is correct-by-design, not a bug: both files use the
callback-registrar pattern (`OnServe`, `OnBuyHouse`, `OnSellHouse`, `OnSetHomeJob`) and the
remote traffic is owned by `init.client.luau`. So the import is simply a leftover. Delete
it. Do not wire remotes into the UI modules — that would break the pattern every other UI
in this codebase follows.

**`src/client/ui/HouseUI.luau` — the real bug here.** `makeHouseRow` at line 207 is a
~120-line function with **no callers anywhere in the file**. `HouseUI.Set` (line 329)
builds its rows inline instead, twice over — once for owned houses and once for available
ones, with near-identical construction code in both branches. The six unused colour
constants the gate flags (`TRACK_COLOR`, `BUTTON_IDLE`, `BUTTON_hover`, `BUTTON_TEXT`,
`BUTTON_DEAD`, `BUTTON_DEAD_TEXT`) are unused *because* they belong to that dead function.

This is quality-bar rule 4 in its purest form. Pick one: either finish `makeHouseRow` and
route both branches of `Set` through it — which is what it was obviously written for, and
which deletes a large duplication — or delete the function and its six constants. Do not
leave it. Also note `BUTTON_hover` is miscased against its five siblings; whichever way you
go, that name should not survive.

`Set` does correctly destroy old rows before rebuilding, so there is **no** repeated-
connection leak. A checked that specifically; do not go looking for it.

**`src/client/world/BondCelebration.luau:6`** (`ReplicatedStorage`),
**`BonusPop.luau:10,33`** (`RunService`, `BONUS_KEYWORDS`), **`MoneyPop.luau:10,22`**
(`RunService`, `const`) — all four modules are genuinely used from `init.client.luau`
(lines 608, 610, 836, 841), so these are dead imports and dead constants inside otherwise
live files. `BONUS_KEYWORDS` is the one to think about rather than delete reflexively: a
keyword table nobody reads usually means a categorisation feature that was designed and
then not wired.

**`src/client/init.client.luau:24`** (`MoneyPop`) — **this is Agent A's file, and the gate
appears to be wrong about it.** `MoneyPop` is imported at line 24 and used at line 608.
Do not edit the file. Instead, work out *why* the gate flags a local that is plainly used,
and report the answer. This matters more than it looks: `tools/check.py` is the shared
signal for both agents, and CLAUDE.md is explicit that checks producing false positives get
removed rather than tuned, because a scanner nobody trusts is a scanner nobody runs. If the
check has a real hole, that is a more valuable find than the eighteen lint fixes above it.

### Task 2 — finish the economy arc you are mid-way through

Cars, houses, bills, milestones, gossip. **None of it has been Studio-tested.** Hold it to
the bar, especially rule 4 — HouseUI above suggests these services were written ahead of
their UI, so expect more fields that are written and never read, and more helpers with no
callers. Grep every consumer of every field before you call any of it done.

Each of these also needs a debug command in `DebugService.luau` and an entry in
`HELP_TEXT`, per rule 8. Check whether they have one; a system you cannot drive from the
console cannot be tested without playing the whole game up to it.

### Task 3 — if you have room

School parts 4c/4d, and lobby part 5 (join codes). Both are self-contained and touch
nothing A owns. Spec either one back before building it — one-line feature requests get
specced and agreed first in this project, not implemented directly.

## Commit discipline

Commit your own files only, by name — never `git add -A`, never `git add .`. The tree has
two agents' uncommitted work in it and a blanket add will sweep up A's half-finished map
generator. Follow the existing message style: short, present tense, about the *why*
(`Standing is earned, the rung is given`, `Different clothes`, `One vault, one alarm, one
guard, everybody in the room`).

## How to hand back

End with: what you changed, what the gate says, what you did **not** do and why, and any
bug you found in A's files but did not touch. If you were blocked by ownership, say which
file and what you needed.
