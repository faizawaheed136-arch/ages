# Agent C — school and lobby

_No entry yet. Append yours at the top, newest first._

---

## 2026-08-31 — read the first section before you touch build_street.py

Branch `agent-c`, level with `main` at `3460156`. All six gates clean.

### **Street.rbxmx is written by both of us, and the order matters. This one is for A.**

`build_street.py` (yours) writes the street from `world_plan`, including the map's own school
model and the `Place_*` points at their planned coordinates. `gen_school.py` (mine) then does two
post-passes over the same file: `strip_old_school()` removes the map's school so v1's building is
not standing inside it, and `relocate_place_points()` moves `school`, `classroom`, `cafeteria` and
`science_lab` into the rooms of the building that actually got built.

Run them the other way round and the second undoes the first:

    Street.rbxmx   252 KB -> 405 KB      (the old school model comes back)
    Place_school   (-536, -292) -> (-238, 151)

and **every gate still passes**, because each asset is internally consistent — they are just
consistent with different plans. Anything sending a player "to school" then delivers them to a
building that is no longer there. Nothing errors.

Not hypothetical: I did it to myself on 2026-08-31 while auditing whether the assets were still in
sync with the generators, and the only reason I caught it is that I compared the regenerated file
against the committed one instead of trusting a green gate.

**So: run `python tools/rebuild.py` rather than the generators by hand.** It runs all seven in the
one order that works — town, city, street, school, ProperSchool, academy, mapshapes — then all six
gates. A full ordered rebuild reproduces every committed asset byte for byte; that is checked.

If you would rather I stopped writing into your file at all, say so and I will move the two
post-passes elsewhere. It is your asset and I am not comfortable with the arrangement either.

### Your three commits sat unmerged for two days

`7f020d7`, `a68540e`, `6bd80fb` were in neither `main` nor `agent-c` until `5bfde2c`. Everything I
built for several sessions sat on a tree a day out of date and nothing complained — a stale tree
is internally consistent and passes every gate. I now check `merge-base --is-ancestor
origin/agent-a HEAD` at the start of a session.

Twelve conflicts. Most wanted the union; three needed a decision:

- **Music** — we both wrote it. Yours wins whole: service, UI, config block and the `rhythm` verb.
  My `keep` verb and its four-lane implementation are gone. Line-merging two implementations of
  one verb makes rubble.
- **PE** — we both added `id = "pe"`, and Curriculum refuses the duplicate at load. Both lessons
  survive: your 3v3 match keeps `pe`, my drill meter became `gym`, which is what `/gym` and
  StatsUI's `"gym" | "drill"` sweep sources already called it.
- **The lab** — your `buildRoom` places it at `science_lab` rather than the forecourt, which is
  right. But your side of that hunk has no `School.Build(at)` in it, so taking it whole would have
  quietly stopped raising the building at all. Kept both.

Two silent clobbers the gates caught: a second `Config.School.Music` assignment further down the
file was replacing yours wholesale, so MusicService died on a nil `CountInSecondsByLevel`; and
init.client still fired a `RequestMusicHit` remote that no longer exists.

Also fixed ProperSchool's plinth, which overlapped itself at all four corners — found by **your**
new coplanar check in `check_city.py`. It earns its keep.

### v1's school moved, and `SITE` is absolute now

It is at **(-536, -292)**, 534 studs south-west of town, with `Place_school` following it. It had
been baked at (-38, -1138) — 1138 studs into bare baseplate — which is why the owner was seeing a
different world from you: your tree has no `SITE` line, so your bake stood near town and mine
stood alone in a field, and Studio shows the baked asset before anyone presses Play.

`SITE` is **absolute**, never an offset from the marker. As an offset it compounded, because the
bake then writes the marker onto the building: the school walked 618 by -767 studs every run and
nothing complained. Two consecutive bakes now hash identically.

**It does not fit the plot you reserved.** Your plot is 122 x 114; v1's complex is 401 x 266 —
228 of main building, 101 of pool hall west, 72 of gym east — inside a 460 x 268 campus plate. No
offset saves it; the best one tried still leaves 159 overlapping parts. Putting it back on the
marker is what made `check_city` report seventeen buildings with a road through them. The current
site is a holding position: settling it is either you widening the plot or this building losing
its wings, and that is the owner's call.

### A second school: the Gakuran academy

New, unrelated to v1 — the owner asked for a dark, moody interactive showcase school. It is now
**in AGES** at (-240, -732), 400 x 448 x 60, mounted as `Workspace.Academy`.

- `src/showcase/world/Plan.luau` is the plan **as data**, and that is load-bearing rather than
  tidy: every dimension derives from the band widths, and because it is data it can be executed.
  The edge indices were off by one on the first run, which put the south rooms at z -72 and
  overlapped twelve of them. Caught before a single part was laid.
- `src/showcase/{server,client,shared}/` — lockers and uniform changing, a period/duty-chime loop,
  hinged doors, a sparring arena with camera work, gym equipment. All found by CollectionService
  tag, so nothing is wired by path.
- **Lighting.** Its look is the inverse of AGES's — 3 / -0.45 / 0.18 against 2.1 / 0.1 / 0.75 —
  and there is one Lighting service per place. `LightingZone.luau` grades **per client** on a box
  test, so the town stays bright for everyone outside it. It captures AGES's own values at
  startup rather than hardcoding them, so it cannot override a change you make to the town.
- Its assets live in `assets/showcase/`, not `assets/`, so your "every `assets/*.rbxmx` is mounted
  in one of the two AGES places" check keeps meaning what it says. Its glob is not recursive.

Site chosen by measurement: with every mounted asset counted as an obstacle (both parked schools
included), AGES has nothing closer. Even a 292 x 332 cannot get within 484 studs of the marker.

### New tools

- **`tools/check_routes.py`** — voxelises a baked school, floods it from the front door, reports
  the narrowest point on every route and anything fouling a stair tread. Written after the fourth
  time geometry was individually correct and collectively unwalkable. It found live bugs
  immediately: vending machines two studs off two doorways, and lobby furniture standing on the
  bottom six treads.
- **`tools/check_showcase.py`** — gates the academy, and checks **geometry rather than the absence
  of an error**: 280 parts across the expected extent. This repo has already shipped a bake that
  wrote zero parts and reported success, so "it ran" is not evidence.
- **`tools/rebuild.py`** — see the first section.

### The repo moved

`C:\Users\saabi\GitHub\ages`, out of iCloudDrive — the owner switched Apple accounts and iCloud
would not adopt the old folder while it still held files, and a git repo inside a sync engine is a
corruption hazard anyway. Nothing hardcodes the old path. Irrelevant to you on the Mac, except
that paths in older entries of this file are now stale.

### One thing I want from you

**Push more often, or say where you are working.** Your last commit is 2026-08-29 16:38. If you
have done anything since, it is not on `origin` and not in the owner's iCloud — I checked both
today. I cannot see a Mac working tree, and the owner has now twice believed we were out of sync
when the truth was that there was nothing to sync.

---

## 2026-08-29 (later) — the timetable is finished, and the school is a building

Branch `agent-c`. Gate: **all clean** — 133 server modules, 49 client modules, both places
build, all three bootstraps run.

### Every subject now has a verb, and Math is the only quiz left

`Curriculum.luau` had Reading and Music sitting on `verb = "quiz"` with the debt written into
the comments. Both are paid.

| Subject | Verb | What you do |
|---|---|---|
| Science | `procedure` | walk the tool order, commit the bench *(was already built)* |
| Art | `copy` | replicate the study while it shifts *(was already built)* |
| Geography | `hunt` | find a named place with no marker *(was already built)* |
| **Reading** | **`build`** | **two words, one shared tray of letters** |
| **Music** | **`keep`** | **four lanes, judged on when you act** |
| Math | `quiz` | arithmetic under a clock — a decision, not a debt |

**Reading.** Two words stand on the board with letters missing and there is one tray between
them. It is almost always obvious which letter goes in a gap — that was never the question.
The question, forty times a lesson, is *which word to spend it on*. Two queues at half load
each, bought with a shared tray rather than a second minigame. The technique nothing teaches:
fill the word needing the rarer letters first. Mastery buys **takebacks** and nothing else.

The old comment in `Curriculum.luau` called Reading an unsolved problem because "a passage
with the answer inside it is a quiz with more words". That was right about *that shape*. The
way out was not a better question, it was to stop asking one — and the comment is kept,
because the trap is worth leaving written down.

**Music.** Four lanes, a chart falling down them. The chart goes out **complete at the
downbeat and never again**: a player who can see the next bar is reading music, one sent a
note at a time is being startled. Mastery buys the judgement windows — 25/45/80ms at level
one, 48/76/124 at the top, same chart and same tempo — which is the cleanest instance in the
game of a progression the player can feel inside the verb.

**Timing is judged client-side and there is no honest alternative**: the window is shorter
than a Roblox round trip, so a server-timed rhythm game is not stricter, it is unplayable.
The client sends a claim; the server checks the note exists, is unjudged, is inside the
window it granted, and was due about now, and it sweeps misses itself because a client that
never reports one has a perfect run. That does not make cheating impossible — it makes it
cost more than playing, which is the honest bar when the prize is smarts. **Raise it if you
disagree; it is the one place in my lane where the server is not the authority.**

Debug: `/read [start|solve|end|on|off]` and `/music [start|auto [grade]|end|on|off]`, both in
`HELP_TEXT`. `/music auto` is the only way to reach a band other than F without playing a
hundred-beat piece by hand.

### The school is a three-storey building now

`world/School.luau` (880 lines) lays the whole thing at runtime around the place point:

- Three storeys at 18 studs each, on a **300 x 210** footprint
- An atrium cut through all three with a glazed lantern over it and two stair flights inside
- A glazed front elevation, entrance canopy, plaza, crossing, trees, name and welcome signs
- A corridor spine per floor with lockers, seating, planting and lighting
- **Cafeteria** and **library** on the ground floor; **science, art, reading, music** on the
  second; **cooking lab, computer lab, English, staff room** on the third
- An **aquatic centre** with a barrel-vaulted glass roof, six-lane tank, diving board,
  lifeguard chair and spectator benches
- A **gymnasium** with court markings, hoops and bleachers
- A **six-lane running track** with an infield, goalposts and floodlights

About fifteen hundred parts. `world/Kit.luau` is the shared vocabulary it is built from —
slabs, walls, glass walls, columns, light panels, stairs, railings, signs, rugs, planters,
trees, bunting. Four modules had already grown their own byte-identical `buildBlock`; the
fifth copy is the one somebody forgets to fix.

**Why runtime Luau and not `assets/`.** `docs/school_sports_plan.md` says the school interior
is Agent A's because it is generated by `tools/` into `assets/`, and that is true of the
*shell on the street*. But `Lab.luau` and `Studio.luau` were already laying school rooms in
code around the place point, and nothing about that touches `assets/`, needs a regeneration,
or can conflict in an 11 MB XML file. School follows them. **There is not one absolute world
coordinate in it** — every position derives from the centre it is handed, so it moves when
the map moves.

**A, this is the seam to rule on.** If you would rather the building were generated into
`Street.rbxmx` I will spec it over instead. But four rooms are already laid this way, the
fifth costs nothing, and doing it in code is what let the school get big without touching
anything of yours.

### The building is architecture; the verbs are furniture

`School.RoomAt(id)` is the entire join. `ScienceService` does not know where the lab is — it
asks for `"science"` and lays benches in whatever comes back. A wall can move without a
subject breaking and a subject can be added without a wall moving. Lab, Studio, ReadingRoom
and MusicRoom all resolve their centre this way and fall back to the bare place point when
there is no building, so **nothing here is load-bearing on the architecture having worked**.

The bully corridor no longer lays its own hallway when the building is up (`Corridor.Build`
takes `layProps`), and taken homework is now redone in the **actual library** rather than at
a desk invented at the end of the run.

### Two defects an audit caught that nothing in the tree could

I wrote a throwaway layout audit in Python because the boot harness stubs `CFrame`, so
`School.Build`'s geometry never executes anywhere — the gate proves the module *loads*, not
that the building stands up. It found two real ones:

1. **The ground-floor rooms started in front of the corridor.** Cafeteria tables and corridor
   lockers occupied the same studs.
2. **The room band was 32 studs deep.** `Studio` lays the study wall at 0.7 of a 60-stud
   radius on one bearing and the paint cupboard at 0.65 on the opposite one — 81 studs apart.
   The art room's cupboard would have stood outside the back of the building.

Both are the same class of bug and it is one **no check in this repo can see**: a room is
sized in `School.luau` and the furniture that goes in it is sized in a completely different
module's Config. Nothing measures one against the other. That is why the footprint is
300 x 210 and why `BackBandDepthStuds` is 99 with a comment saying the art room chose it.

**Worth considering for `check.py`** (A's file, so I have not touched it): a check that
resolves each `School.RoomAt` consumer's furniture extent against the room it is handed. I
can hand over the audit script if it is wanted.

Also caught by the gate and worth recording: I named a file-level local `at` in `School.Build`
while every builder above it takes `at` as a *parameter*, and the declaration-order check
read that as a use-before-declaration. CLAUDE.md names that exact false-positive class and
says such checks were dropped rather than tuned — so the fix went here, not in the checker.
The local is `toWorld` now.

### Still not done

- **The map is unchanged.** The owner has asked for the whole map scaled up to roughly
  Brookhaven size with taller, livable buildings and bigger houses and streets. That is
  `tools/gen_city.py`, `world_plan.py`, `build_street.py` and `house_plan.py` regenerating
  `City.rbxmx` — **all of it Agent A's**, and the one job in this queue that genuinely cannot
  be done the way the school was. Not started, and it should be A's call how.
- **PE is still not on the timetable**, because it is a graded sports drill and sports is
  unbuilt. The gym and the track now exist to hold it, which they did not before.
- **Nobody can be stood up for yet.** `Config.School.Bully.Intervene` is written and unused.
- **The corridor still does not talk to `SchoolService`** — lateness costs a lesson nothing.

---

## 2026-08-29 — the corridor, and a boot fix that was not mine to make

Branch `agent-c`. Gate: **all clean** (126 server modules, 47 client modules, both places
build, both boot).

### The thing to read first: `main` was dead when I cloned it

`python tools/check.py` on a pristine clone of `main` at `1082f90`, with zero local edits,
failed on the boot check:

```
src/server/content/LifeEvents/init.luau:77:
  [AGES content] event "tie_mentor_guidance" casts "mentor", who is not in the cast
  ^ this throws on require, so init.server.luau dies and NO service starts
```

`LifeEvents/Ties.luau` set `cast = "mentor"`, `"rival"`, `"sibling"` and `"enemy"` on its
four events. Those are **tie ids from `content/Ties.luau`, not cast ids** — `Cast.ById` has
none of them, the content validator threw at require time, and it took `EventService`, then
`init.server.luau`, then every service in the game place with it. The game place loaded with
nothing running in it. The lobby was unaffected, which is why this could sit on `main`
looking fine.

`friend` is both a tie id and a cast id, which is almost certainly how the belief spread.
The file's own header said the cast field "is still required on each one so a rig appears" —
that was the false premise, and `Types.LifeEvent` documents the opposite: nil is allowed and
falls back to the first cast member. The tied person is already carried by the `tie:*:*` tag
the context builder fills in, so these events never needed to name anybody.

**This is Agent B's file and I edited it anyway** — commit `610d8a9`, four lines deleted and
the misleading header paragraph rewritten to record why. The owner explicitly overruled the
ownership rule when I raised it, because nothing in my own lane could be tested against a
server that would not start. Flagging it here as loudly as I can: **B, this is yours, please
check I read it the way you meant it.** If the intent was that `cast` should accept a *kind*
of person, the fix belongs in the validator and the type instead, and mine should be reverted.

Nothing else of B's or A's was touched.

### What I built: the school corridor (commit `f7f3c74`)

Four new files, all in the C lane, plus append-only additions to the four shared files.

| File | What it is |
|---|---|
| `src/server/world/Corridor.luau` | Lays the corridor around the school place point |
| `src/server/content/Bullies.luau` | Who stands in it — four archetypes |
| `src/server/services/BullyService.luau` | The only thing that knows how a stare-down is scored |
| `src/client/ui/NerveUI.luau` | The bar and the hold button |

**The verb.** Somebody steps across you between lessons. One key: your nerve rises while
you hold, their patience falls on its own, and letting go in the band just above them is
facing them down. Below it you backed off and they take the toll. Past it you overcommitted,
which is worse than backing off. The release *value* is what scores it, so it is
latency-immune and works on a phone with one thumb.

Held against the seven requirements in `activity_design_law.md`:

1. **One verb, commit and undo** — the release is the commit; walking away before letting go
   costs nothing at all, which is the undo window.
2. **Two concurrent queues** — at paired tiers a second bully walks toward you from the far
   end. The first bar says when the window *opens*; their arrival says when it *shrinks*.
3. **A consumable forcing traversal** — taken homework is redone at the library desk at the
   far end of the corridor. Burst, forced walk, burst.
4. **Soft failure** — backing down costs the toll and a point of happiness. Never the lesson,
   never a rung already earned. `bullyStandUps` is never decremented.
5. **Escalation by changing the space** — higher tiers occupy stations further down the
   corridor and then send a second person. No bully anywhere has a difficulty number.
6. **Progression widens tolerance** — `bullyNerve` physically widens the green band on screen,
   Stardew-style. It never moves the bar for you: a maxed life that releases badly still backs
   down.
7. **Same input, different opponent** — three drains. `steady` never lies. `bluffer` falls
   fast and jumps back **once**, so releasing on first sight loses and waiting one beat wins.
   `mirror` falls against your own rise, so holding is the wrong answer against it and the
   window has to be taken early. `content/Bullies.luau` errors at require time if any drain
   has nobody using it, because a corridor that stops teaching is invisible to every other
   check in the tree.

**13+ by construction, not by moderation.** Nothing in any line is about the player — every
one is about the toll or about who moves first. No gore, no injury, nobody degraded, and the
player is never the aggressor unprompted. The single door into contact is overholding against
somebody you have *already* faced down, gated on `Config.School.Bully.TipsIntoFight`, and what
is behind that door is `FightService.Challenge` — already a contest with a winner. If it
refuses for any reason the overhold just resolves as an overhold, so the flag can be turned
off without leaving a hole.

**Debug path:** `/nerve [go [id]|stood|backed|over|end|set <n>|homework [on|off]|list|on|off]`,
in `HELP_TEXT`. `set` is the only way to watch the window widen without playing thirty
corridors; `over` is the only way to test the fight door.

### The other thing worth knowing: the school can now grow without touching `assets/`

`docs/school_sports_plan.md` says geometry is Agent A's, always, including the school
interior — and it is, for anything generated by `tools/` into `assets/`. But `world/Lab.luau`
and `world/Studio.luau` were already building school rooms **in Luau at runtime**, around the
place point, and nothing about that touches `assets/` or needs a regeneration.

`Corridor.luau` follows them exactly. There is not one absolute world coordinate in it —
every position is derived from the centre it is handed, so it moves when the map moves.

**This is the seam to agree on.** If C keeps building school interior this way there is no
contention with A at all and no 11 MB conflict is possible. If A would rather the corridor
were generated into `Street.rbxmx` instead, say so and I will spec it over rather than build
it — but three rooms are already laid this way and the fourth costing nothing is worth having
on purpose rather than by accident.

### Not done, and why

- **Reading and Music are still `verb = "quiz"`.** They are the two real debts on the
  timetable and both are named as such in `Curriculum.luau`. Next in this lane.
- **PE is not on the timetable at all**, because it is a graded sports drill and sports is
  unbuilt. Unchanged.
- **The corridor does not talk to `SchoolService`.** Lateness does not yet cost a lesson
  anything — the second clock is the paired bully, not the bell. Wiring a late penalty into
  lesson scoring is a `SchoolService` change (my file, no cycle) and is the obvious next
  seam, but it wants agreeing first rather than assuming.
- **Nobody can be stood up for yet.** `Config.School.Bully.Intervene` is written and unused:
  stepping in when a bully is working a classmate needs classmate NPCs in the corridor, which
  is a bigger piece than it looks and is the thing that would make this system *kind* rather
  than only defensive. It is the highest-value next addition here.

### Environment note for whoever gets this Windows box next

It had no toolchain at all. Installed at the exact paths `check.py` expects:
Python 3.12.10 (winget), luau 0.736 (`luau-windows.zip`), Rojo 7.7.0
(`rojo-7.7.0-windows-x86_64.zip`) under `~/.aftman/tool-storage/`.

Two traps worth writing down, both of which I hit: `core.autocrlf` is `true` by default here
and has to be `false` **before** cloning, and the obvious place to clone on this machine is
inside OneDrive, which `HANDOVER.md` forbids. The clone lives at `C:\Users\saabi\ages`.
Running the gate leaves a `tools/__pycache__/` that is not in `.gitignore` — delete it before
committing.
