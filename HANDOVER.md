# Parallel work brief — read this before you touch anything

Three agents work on AGES at once, across two machines. This document is the contract
between them. A violation is not a merge conflict — it is silent data loss in a tree
where somebody else may have uncommitted work.

Read this, then read [`docs/README.md`](docs/README.md), which holds the settled design
decisions. Those used to live in one machine's local assistant memory and were invisible
to everyone else; most of them exist because something was built, rejected and rebuilt,
and the rejections are the valuable part.

## Which agent am I?

Nobody is "Agent B" by default — that is decided by which lane you were given when your
session started. If you were not told, **ask before editing anything.** Guessing wrong
means editing a file somebody else has open.

| | Lane | Machine |
|---|---|---|
| **A** | the world, and the crime/combat stack | Mac |
| **B** | the economy and the life layer | Mac |
| **C** | school and lobby | Windows |

A and B share one working tree on the Mac. C has its own clone on Windows and works on
the `agent-c` branch.

## The split

**Agent A owns the world.** The city generator and everything downstream:

    tools/gen_city.py      tools/world_plan.py     tools/build_street.py
    tools/gen_town.py      tools/house_plan.py     tools/check_city.py
    tools/rbxmx.py         tools/check.py          assets/*.rbxmx

Road width, block pitch and building footprint are one coordinate system — they cannot
be worked on by two people. A also owns the crime and combat stack: `FightService`,
`Fighters`, `FightUI`, `world/Spotting`, `PoliceService`, `WitnessService`,
`BountyService`, `GangService`, `DisguiseService`, `TheftService`, `BankService`.

**Agent B owns the economy and the life layer.**

    CarDealerService / CarDealerUI      HouseService / HouseUI
    BillService / StatsUI               MilestoneService / MilestoneFlash
    GossipService / BondCelebration     PeopleService / BonusPop
    WorkService / MoneyPop              MoneyService, BodyService, ReturnService
    content/Jobs.luau, JobTasks.luau, Public.luau, Townsfolk.luau

**Agent C owns school and lobby.**

    src/server/services/SchoolService.luau      school content modules
    the lobby place: lobby.project.json tree, join codes

Sports is unbuilt and school is five 20-second multiple-choice questions with a teacher
NPC that nothing branches on. So C is not maintaining a system — it is building two from
a settled spec, and they are **one lane rather than two** because PE class is a graded
sports drill.

**C's queue is [`docs/school_sports_plan.md`](docs/school_sports_plan.md)**, eight phases
in order, with the seams against A and B named at the bottom. The design it implements is
`docs/school_and_sports.md`; the law it answers to is `docs/activity_design_law.md`.
**Spec each phase back before building it** — one-line feature requests get agreed first
in this project, never implemented directly.

## Ownership — the one rule with no exceptions

**Do not edit a file on another agent's list. Not to fix a typo, not to fix a lint
error, not to add one line.** There is uncommitted work in this tree on more than one
side. If you need something changed in a file you do not own, say so in your hand-back
and stop.

If you find a real bug in someone else's code, that is worth reporting — name the file
and the line, and hand it back. Do not fix it.

## Shared files — append-only, never reorganise

Four files are edited by everyone:

    src/shared/Config.luau      src/shared/Types.luau
    src/shared/Remotes.luau     src/server/services/DebugService.luau

1. **Add, never move.** Do not reorder blocks, re-sort keys, reformat, or "tidy while
   you are in there". A whole-file reformat destroys another agent's uncommitted edits
   in a way that is nearly impossible to spot in review. This has already happened once
   in this repo, to two project files, by an agent that meant to add a single line.
2. Put new material in **one contiguous block** next to what it belongs with.
3. In `Remotes.luau`, a new remote name goes in **both** the `RemoteName` union **and**
   the `REMOTE_NAMES` list. The gate checks this — trust it here.
4. In `DebugService.luau`, add your command as `Commands.x = function(...)` **and** add
   it to `HELP_TEXT`. A command not in `HELP_TEXT` does not exist as far as anyone
   testing is concerned; two shipped that way and were found months later.

## Never touch these

- **`tools/` and `assets/` unless you are A.** `City.rbxmx` is 8.4 MB of generated XML.
  A conflict in it cannot be hand-merged — the correct fix is always to regenerate.
- **Absolute world coordinates.** The map still moves. The contract that makes parallel
  work safe is: **place-point ids are stable, place-point coordinates are not.** Look
  positions up by id through the tagged-part path in `src/server/world/Routes.luau`. If
  you are about to write `Vector3.new(366, 8, 357)` into a Luau file, stop.
- `CLAUDE.md` and `docs/` — propose changes, do not make them.

## The bar

Every one of these is a hard requirement. Each exists because that defect has already
shipped into this tree at least once.

1. `--!strict` at the top of every file.
2. **No magic numbers in logic files.** Every tunable goes in `src/shared/Config.luau`
   with a comment saying what it does *and* a `-- Safe range: a-b` line.
3. **Comment the *why*, not the *what*.** The comment explains the decision and what it
   would break if changed. `-- adds 1 to the count` is noise.
4. **No orphaned code.** A field written and never read, a function with no caller, a
   parameter nobody passes — delete it. Grep every consumer of a field you change.
5. **No silent failures.** Content errors `error()` naming the offending id and saying
   what to do about it.
6. State changes are atomic and server-authoritative. Decide the outcome, *then* write.
7. Idempotency wherever a retry is possible.
8. **Every system ships with a debug path** in `DebugService.luau`.

Content rules: 13+ hard ceiling. No gore, no gambling, no romantic partners — ever, not
deferred. Combat *is* allowed. US English. Failure should be worth playing. The
reasoning behind all of these is in `docs/`.

## Verification — before you hand anything over

```
python3 tools/check.py          # python tools\check.py on Windows
```

Syntax, both place builds, dangling Config refs, require cycles, remote-name
consistency, unused locals, declaration order, calls to undefined names.

**The gate is currently green. Any failure you see is yours.**

Two things about it that matter:

- **`rojo build` does not parse Luau.** "Builds clean" means nothing. A syntax error in
  one module propagates through `require` and takes down *both places* with no error
  naming the file — the symptom is a place that loads with no services in it.
- A missing toolchain is now a **failure**, not a skip. If you see
  `FAILED: ...missing -- this check did not run`, the gate did not run and you have no
  signal. Install the tool at the exact path in the message.

### Do not start a rojo server. Ever, in this arrangement.

There is **one** `rojo serve`, it runs on the Mac, and Agent A owns it. Only one process
can hold port 34872, and this has already cost a full session once: a server from a
*different repo* held the port, Studio was connected to it, and every change both agents
made for hours was written correctly to disk and delivered to nothing. It presents as
"my changes don't show up", which reads like a broken build.

- **Never run `rojo serve`.** If you think you need one, say so and stop.
- To check what is being served, ask the server — but note the response is **MessagePack,
  not JSON**, so piping it to a JSON parser fails and looks like a dead server:

      curl -s http://localhost:34872/api/rojo | grep -a projectName

  It must say `ages`. Anything else means Studio is connected to the wrong thing.
- To verify your own changes package correctly, build to a scratch file instead — which
  is what `tools/check.py` already does, so just run the gate.

## Two machines

The Mac runs A, B, Studio and the one rojo server. **Windows cannot sync to Studio** —
C edits and pushes, and the Mac pulls to see it in game.

Sync is git and only git. Do not put this repo in iCloud, Dropbox, OneDrive or Syncthing:
a sync daemon racing the rojo watcher corrupts `.git`, and a half-synced `.git` loses
work nothing can recover.

`.gitattributes` pins everything to LF and marks `*.rbxmx` binary. On Windows, set
`git config --global core.autocrlf false` before cloning, or git rewrites every line of
every file on checkout and the two machines start disagreeing about files neither edited.

## Handover protocol

Each agent writes **only its own file** and reads all three:

    handover/A.md      handover/B.md      handover/C.md

One writer per path means a conflict is structurally impossible. Append your latest
entry at the top with a date. Say: what you changed, what the gate says, what you did
**not** do and why, and any bug you found in someone else's files but did not touch. If
you were blocked by ownership, name the file and what you needed.

## Commit discipline

Commit your own files **by name**. Never `git add -A`, never `git add .` — the tree has
more than one agent's uncommitted work in it and a blanket add sweeps up half-finished
work from someone who cannot see you doing it.

C commits on the `agent-c` branch and pushes; it does not commit to `main`.

Follow the existing message style: short, present tense, about the *why* — `Standing is
earned, the rung is given`, `Different clothes`, `One vault, one alarm, one guard,
everybody in the room`.
