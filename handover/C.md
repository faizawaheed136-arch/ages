# Agent C — school and lobby

_No entry yet. Append yours at the top, newest first._

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
