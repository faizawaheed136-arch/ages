# Phase 2 — finish the event schema (SPEC)

**Status:** proposed, awaiting owner sign-off before any code lands.

This is the spec for the missing fields on `LifeEvent`. The plan is in
[`life_layer_plan.md`](life_layer_plan.md). The design is in
[`lifesim_design.md`](lifesim_design.md). **The design wins on disagreement.**

---

## 1. What I am building, in one sentence

Add the four event-schema fields the design locks in and the content already
needs: `tags`, `cooldown`, `escalatesTo`, `writesBack`. Make `writesBack`
mandatory at load (a content error, not a runtime one). Enforce the
"1–3 events per chapter" cap in the picker, not in the content. Leave the
"70/30 world-spawned to modal" rule for phase 3 where ambient routing lands.

---

## 2. The four fields, in the shape they take

The type is in `src/shared/Types.luau` at `LifeEvent` (line 1915). Today it has
`id`, `minAge`, `maxAge`, `delivery`, `prompt`, `choices`, `resolution?`,
`weight?`, `cast?`, `subject?`, `lure?`, `repeatable?`, `requires?`,
`forbids?`, `minStanding?`, `jobs?`. Phase 2 adds:

```lua
-- Loose category tags, for picking pools ("a rival is reading me" — vs.
-- "the room I'm in has gotten too small"). Strings, not enums, because the
-- tag set grows as content grows and a closed enum turns every new tag into
-- a release. Unknown tags are allowed at load: they cannot fail, because
-- nobody reads them except the picker, which is the only place that asks
-- what tags exist.
tags: { string }?,

-- Real seconds between *deliveries*, not between *fires*. A cooldown is on
-- the delivery path: a wandering event with cooldown 60 will not put a lure
-- down twice within a minute of itself, so the room is never littered with
-- copies of the same lure. Nil means 0. Per-life, not global: a second
-- player is on their own clock.
cooldown: number?,

-- The id of the follow-up that comes from this one, if anything. The chain
-- is read by the picker, not by content: a chained event fires *because*
-- the prior one was answered, so the player can trace the thread. Nil means
-- "nothing follows". An escalatesTo that does not exist as an event id is a
-- load error -- a chain to nothing is the worst kind of dead writing.
escalatesTo: string?,

-- What the event writes to, in plain words. The mandatory-stat-or-it-does-
-- not-ship rule from the design. Authored as the list of things the event
-- actually changes (stat names, flag ids, ribbon conditions, tie names) so
-- a missing one is caught at load, not at runtime. The list is also the
-- picker hint for "this event leaves a mark": chained events read it to
-- know what the prior event left behind.
writesBack: { string }?,
```

`tags` and `writesBack` are arrays of strings, both `?`. `cooldown` is a
single number, `?`. `escalatesTo` is a single id, `?`. The shape matches the
design doc's snake-cased names without the underscores, because the rest of
the codebase is camelCase and this is the same project.

---

## 3. Why these four, and why now

The design (`lifesim_design.md` lines 39–55) lists six fields:

```
{ tags, requires, weight, cooldown, escalates_to, writes_back }
```

After phase 1 the file has `requires` and `weight`; `seenEventIds` does the
per-life repeat suppression that the design asks for as a separate rule.
Missing: `tags`, `cooldown`, `escalatesTo`, `writesBack`. The plan
(`life_layer_plan.md` Phase 2) names these four exactly.

`writesBack` is the design's "events that change nothing" trap rule
(`lifesim_design.md` line 114, "Named traps" table). It is also the only
field that requires a *load-time* check rather than a runtime one: a runtime
check on an empty `writesBack` would be a warning the author never sees, and
an event that quietly never moved anything is the design's named trap. The
check is in `init.luau`'s `validate(event)`, next to the existing checks on
`minAge`, `choices`, `cast`, and friends.

The "1–3 events per chapter" rule (design line 52) is a *picker* rule, not a
content rule. Content does not count its own events; the chapter does, when
it picks. Putting the cap in `validate()` would be checking content against
itself, which is the wrong layer. Phase 2 adds the counter to
`EventService.PickStageable` (the ambient pick) and to the birthday-event
pick, and caps each chapter at three firings before the chapter break fires.

The "70/30 world-spawned to modal" rule (design line 54) is *also* a picker
rule, but it depends on the ambient routing layer phase 3 is going to land.
Phase 2 leaves it alone: it cannot be enforced in the picker until the
picker has a "world" route to choose from, and that is phase 3.

---

## 4. What `writesBack` checks

The content author writes the names of the things the event changes. The
names match the registry the rest of the project uses:

- **`stat:<name>`** for a stat. Names are the four from `StatName`
  (`health`, `happiness`, `smarts`, `looks`). Authoring as
  `{ "stat:health", "stat:happiness" }` so a stat move is greppable.
- **`flag:<id>`** for a flag set or cleared. Names are the ids from
  `content/Flags.luau`. Both `sets` and `clears` count as writes; an event
  that clears a flag is moving state just as much as one that sets one.
- **`tie:<name>`** for a tie change. Names are the tie ids from
  `content/Ties.luau`. Used by phase 5's rivals/mentors/family slots; the
  field exists now so the chain check below does not break later.
- **`ribbon:<id>`** for a ribbon condition the event satisfies. Used by
  the verdict layer: a single answer can be the moment a ribbon becomes
  reachable, and the chain code needs to know that.
- **`standing:<jobId>`** for a work-record write. The performance field on a
  shift event already writes standing; this is the named hook the picker
  reads.
- **`money`** for a money change. Cost and payout on a choice both count.

The validator in `init.luau` checks each id against its registry and refuses
unknown ones at load, exactly the same way `Flags.AssertKnown` refuses
unknown flag ids today. **Empty `writesBack` is refused.** An event with
no writes is a cutscene, and the design's "Named traps" table row for
"Events that change nothing" is the rule that catches it.

The check does **not** try to be clever. It does not parse the event's
choices to derive the writes; it checks what the author *said*. Deriving
the list from effects would re-implement the same rule in two places and
let a choice with `effects = { happiness = 0 }` and no other writes pass a
check that was supposed to catch it. The author names the writes; the
validator confirms the names are real; runtime applies them.

The check does **not** require every *choice* to write something. A choice
with `effects = { smarts = 3 }` and `cost = 0` writes to `stat:smarts` and
to nothing else, and that is fine: the *event* writes, the choices differ.
What the field is for is the *event* moving the world; the choices are how
it moves it. Today the "moves something" check at the end of the loop
already covers choices (line 504 in `init.luau`). Phase 2 keeps that check
and adds the *event-level* `writesBack` on top of it.

---

## 5. What `escalatesTo` checks

The id must exist as another event in `LifeEvents.ById`. The chain is read
by the picker in phase 3: when the ambient route picks an event whose
`escalatesTo` is set, the follow-up is staged *because* the prior event was
answered, not because it was rolled. Today the picker does not know about
chains, so the field is loaded and validated but not yet *used*. The shape
is locked in now so phase 3 can build the chain logic on a stable base.

A chain id that points at the same event is refused: it would loop forever
the first time the picker ran, and the bug would look like an event that
never stopped firing. A chain id that points at an event whose `minAge` is
below the prior event's `minAge` is refused: a follow-up that could have
fired before its cause is an event whose shape disagrees with itself, and
the picker cannot tell which way the chain runs.

---

## 6. What `cooldown` checks

Whole real seconds, above zero, with a sane upper bound. The bound is
`Config.Ambient.MaxSecondsBetween` * 4 = 960s, which is twice the longest
ambient gap and therefore long enough that no authored cooldown ever
overlaps with the ambient schedule. A cooldown above that is a copy-paste
of a different unit (game minutes, game months), not an intent.

Cooldown is applied on the delivery path, not the resolution path. A
wandered event with cooldown 60 will not put a lure down twice within a
minute; the picker remembers the last time the event was *delivered* and
refuses to redeliver inside the window. The clock is real seconds because
the schedule is in real seconds (`Config.Ambient.TickSeconds`). An event
that resolves instantly (a panel) has no second delivery, so its cooldown
is moot -- the cooldown is for the *next* delivery, and there is no next
one. The check is in the picker; the validator only catches bad numbers.

A cooldown on an event that is not wander/ambient/shift is a no-op, and
the validator warns-but-allows: it is not the validator's job to second-
guess the route, only the route layer's. Today only Wander, Ambient, and
Shift can fire twice in a life, so only those three routes ever look at
`cooldown`. The validator catches negative numbers and non-integers.

---

## 7. What `tags` checks

Tags are picked up by phase 3's ambient routing and by phase 5's slot code.
The validator does not enforce them. Tags are a content-side vocabulary
that grows as the game grows, and locking the type to an enum would mean
every new tag is a Types release. The picker reads tags as opaque strings
and asks the content registry for events whose tag set intersects the
context: "rival events", "room events", "money events". Tags with no
readers are ignored, exactly like a flag nobody requires.

The validator *does* enforce that tags are non-empty strings when present.
`tags = {}` is the same as `tags = nil` and is normalised to nil at
validate time, so the picker never has to think about an empty list.

---

## 8. The picker cap: 1–3 events per chapter

`PickStageable` (line 388) is the ambient pick today. The chapter is read
off `data.lastChapterBreakMonths` (the field phase 1 added). On every
chapter break the picker resets its per-chapter count to zero, so a chapter
that began without events stays eligible for events until the cap.

The cap is **three, not one**. The design says "1–3 events per age chapter",
which is read as "between one and three" — the lower bound is enforced by
content density, not by the picker, because a chapter that produced no
events at all is a content gap rather than a picker failure. The picker
stages up to three and lets the chapter roll without forcing more.

The picker counts *deliveries*, not resolutions. A wander event that the
player walks past and never answers still counts, because the delivery
already happened -- the lure was put down, the room already moved. Counting
only resolutions would let a player skip a chapter by ignoring every lure,
and a chapter that the player walked past is still a chapter that had
things in it.

The cap is per player, per chapter, not per life. A new chapter resets the
count. The picker stores the count on `data.pendingEventCountInChapter`
(set to 0 at every break in `LifeService:EnterChapter`, the function phase
1 added) and refuses to redeliver once it reaches 3.

The cap does *not* apply to shift events. A shift is the player's chosen
context for events, not the world's, and the design rule is about chapters
-- the chapter pacing -- not about per-shift density. Shift events continue
to fire at the cadence `Config.Ambient.MaxPerYear` allows; the chapter cap
is an outer one. A shift event that would push the chapter over three is
allowed to fire anyway, because refusing it would leave the player mid-shift
with nothing happening, which is the worse failure.

---

## 9. How the validator changes

`src/server/content/LifeEvents/init.luau` adds four checks inside
`validate(event)`, each one placed next to the rule it extends:

- `escalatesTo` next to the `cast`/`subject`/`lure` block at the top of
  the function. The chain check is small (two `if`s, one for same-id, one
  for age ordering) and reads better against the other cross-reference
  checks that already live there.
- `cooldown` next to the `minAge`/`maxAge` check at the top, because both
  are numeric bounds. The upper-bound constant goes into
  `Config.Events.MaxCooldownSeconds`, mirroring the existing `Config.Enact`
  / `Config.Ambient` pattern.
- `tags` next to the `lure` check -- both are "authored as words,
  validated as shape, used by content-side readers". The normalisation
  from empty list to nil happens here.
- `writesBack` as the last check before the choice loop. It belongs at the
  end because it cross-references against the registries the choice loop
  has already validated (`Flags`, `StatName`, and the future `Ties`), and
  adding it after the choice loop means the cross-reference table is fully
  loaded by the time it runs.

All four checks throw with the existing message shape, e.g.
`[AGES content] event "<id>" has ...`. The gate already grep-matches on
that prefix, and a new shape would mean a new gate pattern. Same prefix,
same line layout, same `error()`.

The registry cross-references (`stat:<x>`, `flag:<x>`, `tie:<x>`,
`ribbon:<x>`) each get their own helper, mirroring `Flags.AssertKnown`. The
helpers live alongside `Flags` in `content/`, one per registry, and each
one throws at load when the registry is not yet populated. The registries
that exist today (`Flags`) get a helper now; the ones phase 5 introduces
(`Ties`) get theirs when phase 5 lands. Phase 2 only checks what is
checkable today: `stat:*`, `flag:*`, and `money`. `tie:*` and `ribbon:*`
are accepted as opaque strings until their registries exist, with a
comment in the validator that says so. Adding the helpers later is a
content-side addition, not a type change.

---

## 10. Data changes

`LifeData` gains one field, set in `LifeService:EnterChapter` next to
`lastChapterBreakMonths`:

```lua
pendingEventCountInChapter: number  -- 0..3, set to 0 at every break
```

That is the only data change. Cooldown is *not* a data field: it lives on
the event itself and the picker reads the per-life last-delivery time out
of an in-memory table inside `EventService`. Persisting the cooldown clock
would survive the player's session and make a reconnect at age 30 skip
cooldowns that were set at age 12, which is a bug that moves between
sessions and never gets noticed until someone reconnects after a long
break. Session-scoped is the honest scope.

---

## 11. What this phase does NOT build

- **No ambient routing layer.** Phase 3. The fields are loaded and the
  cap is enforced, but the picker still uses today's routes.
- **No escalations actually firing.** Phase 3 again. The id is loaded and
  the chain check is in place, but the picker does not stage follow-ups
  from `escalatesTo` until phase 3 lands the chain logic.
- **No `tie:*` or `ribbon:*` writeBack registry check.** Those registries
  do not exist yet. Phase 2 accepts them as opaque strings; phase 5 wires
  the check.
- **No NPC-news reel entries from chain events.** A followed chain is a
  reel moment in principle, but the reel query walks durable state, not
  the picker. Phase 5 again.
- **No 70/30 enforcement.** Phase 3, where the picker gets a "world" route
  to choose from. Phase 2 cannot enforce a ratio whose denominator does
  not exist.

---

## 12. Files to touch

| File | Change |
|---|---|
| `src/shared/Types.luau` | Add `tags`, `cooldown`, `escalatesTo`, `writesBack` to `LifeEvent`; add `pendingEventCountInChapter` to `LifeData` |
| `src/server/content/LifeEvents/init.luau` | Add four validator checks; add `Tags`, `Cooldown`, `WritesBack` helpers in `content/` if they are not already there |
| `src/server/content/Flags.luau` | Already has `AssertKnown`; reused as the model for the new helpers |
| `src/server/content/Ties.luau` | **NEW** -- forward-compatible placeholder registry that phase 5 will populate. Phase 2 ships an empty `Ties.ById = {}` so the helper compiles |
| `src/shared/Config.luau` | Add `Config.Events.MaxCooldownSeconds = 960` next to the existing `Config.Enact` / `Config.Ambient` blocks |
| `src/server/services/EventService.luau` | Add the chapter-count check to `PickStageable`; reset the count in `LifeService:EnterChapter` (which lives in `LifeService.luau`, not here) |
| `src/server/services/LifeService.luau` | In `EnterChapter`, reset `pendingEventCountInChapter = 0` |
| `src/server/content/LifeEvents/*.luau` | Every authored event gets a `writesBack` list. Cooldown/tags/escalatesTo are optional and most events will not set them |

The last row is the load-bearing one. There are roughly 70 events across the
seven content files today (Childhood, School, Teen, Adult, Gym, Ambient,
Work). Phase 2 *adds* `writesBack` to each of them; a representative diff
for `childhood_first_word`:

```lua
writesBack = { "stat:smarts", "stat:happiness" },
```

The values come from the existing `effects` tables on the choices -- the
author reads what the event already does and writes that down. The
validator's `movesSomething` check on each choice (line 504 today) means
*some* effect already exists; `writesBack` is the names of those effects
at the event level. For an event whose only effects are `flags`
(`{ sets = { "wandered_off" } }`), the `writesBack` is `{ "flag:wandered_off" }`.

This is mechanical work: read the event's existing effects, write them as
ids. The validator catches every miss.

---

## 13. Gate

After implementation:

- `python3 tools/check.py` returns `all clean`.
- Every authored event has `writesBack`; the validator refuses any that do
  not, so a missing one is a load-time error, not a runtime warning.
- The chain check refuses self-chains and age-back chains; the smoke test
  in the harness (`/offer <id>`) cannot break either rule.
- `PickStageable` refuses to deliver past three in a chapter; the smoke
  test for that is `/ambient x4` in the same chapter, expecting the fourth
  to return nothing.
- No new fields on the wire (`OfferedEvent`, `OfferedChoice`) -- phase 2 is
  a server-side schema change, not a client-facing one. The client
  continues to render the existing payload.

---

## 14. Open questions for the owner

1. **`writesBack` granularity.** I have proposed author-named ids
   (`stat:health`, `flag:wandered_off`, `money`). If you want the field
   to be a single boolean (`did_write: boolean`) instead of a list, say so
   before I write the validator -- the validator gets shorter, the
   registry cross-references go away, and the picker loses the ability to
   ask "what did the prior event leave behind". The list is the more
   useful shape, but it is the more invasive one.
2. **`pendingEventCountInChapter` persistence.** I have proposed
   session-scoped (the field lives on `LifeData`, but `LifeService` only
   resets it on a chapter break, never reads it across sessions). If you
   want it to survive reconnect, say so -- it is one extra line in
   `DataService` to persist, but the bug it prevents (a reconnect that
   silently skips events whose cooldowns are stale) is real.
3. **`Config.Events.MaxCooldownSeconds = 960`.** Twice the longest
   ambient gap, as the upper bound on a sane cooldown. If you want a
   different bound -- 300s, say, so a cooldown can never be longer than
   the longest ambient gap -- say so before I write the constant.
4. **Empty `Ties.luau` placeholder.** Phase 2 ships an empty
   `Ties.ById = {}` so the helper compiles. If you would rather phase 2
   accept `tie:*` as opaque strings forever (no helper at all), say so --
   it is a smaller diff and avoids the empty file.

If you sign off on (1), (2), (3), (4) above, I will implement in the order
of section 12 and report the gate result.
