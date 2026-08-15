# Agent B — the economy and the life layer

_No entry yet. Append yours at the top, newest first._

## 2026-08-15 (seventh entry)

**Queue written, phase 0 done.** [`docs/life_layer_plan.md`](docs/life_layer_plan.md) is
the ordered build plan for the life layer, mirroring `docs/school_sports_plan.md`. Phase
0 orientation complete: read `lifesim_design.md`, `step3_scope.md`,
`activity_design_law.md`.

### What I think phase 1 is

The chapter spine. Six age bands summing to ~35–60 minutes per life, broken at birthdays
the player presses through. The "months passed" reel is part of phase 1, not phase 5,
because its content source has to exist before its screen does — a news-less reel is
worse than no reel, and the news source is the same "what happened" query the verdict
already speaks. Building the screen before the source would teach the player to skip it
the way a decorative slide teaches them to skip it: permanently. Same feature, two
scales: ribbon at the end of a life, reel at the end of a chapter. **One shared "what
happened" query.**

### Two contradictions, adjudicated

**(C1) Bond decay is wrong.** `Config.People.DecayPerYearAway = -3` and `Ties.luau`'s
header both claim decay is how a friendship ends in this game. `lifesim_design.md`
explicitly names decay-on-neglect as a trap in the same family as decaying need bars
and locks the rule that **positives ratchet**. The design wins. The config and the
header comment are both wrong, but I am not patching the code yet — the rewrite is
phase 5, and any change now would create a desync between the comment and the code
that a future reader has to reconcile. **Resolution: delete `DecayPerYearAway`, remove
the decay call from the yearly tick, keep the header comment saying gains stick.**
Phasing it with the riv/mentor/family slots means the visible shape changes at one
moment (rival appears, decay disappears) rather than two unconnected ones.

**(C2) Events-only-on-age-up is wrong, but the diagnosis is right.** `step3_scope.md`
records the owner commitment 2026-07-28 verbatim: *"events are only happening only when i
grow up they should happen at random in my world as i decide them."* `LifeService`
calls `EventService.OfferForAge` at five sites (lines 412, 415, 438, 533, 565), all
inside or directly triggered by `AgeUp`. Nothing else calls it. **Diagnosis stands.**
Resolution lives in phase 3: ambient trigger source (timers + proximity) feeding the
existing `EventService.OfferForAge` selection, plus the four world-delivery handlers
(NPCApproach, Location, Letter, PhoneCall) as `EventUI` kinds. **Extend, do not
duplicate**, because `DeliveryService` already does two-phase staging with
`deliveringEventId`/`pendingEventId` — parallel machinery would orphan it.

The owner rule **"events advance the year in ages 0–5 only"** is honoured by the
existing code: `NextEventDelaySeconds` is gated on childhood in `LifeService`
(line 404), and the `OfferForAge` chain is only entered from a birthday or childhood
event response. **Adult events do not call AgeUp today and must continue not to. No
code changes required to honour it — this is already correct.** Confirming the
existing guard rather than building one.

### Gate

`all clean` — 139 files, 8 checks, before any code touched.

### Not done yet

- Phase 1 spec is unwritten. The "what happened" query shape is the first thing to
  design — without it, the reel and the verdict stay two queries and the duplication
  is the first thing a future refactor has to undo.
- A's overnight changes (MAP_PLAN.md, Town.rbxmx, gen_town.py) are still uncommitted.
  Hand-over acknowledgement only — `life_layer_plan.md` phase 6 references the corner
  shop geometry but does not depend on this session's diff landing.

## 2026-08-14 (sixth entry)

**Lane clean.** Gate `all clean` — 139 files, 8 checks. One small fix landed in this session: removed a duplicate `local subjectGates = job.subjectGates` declaration inside `hireRefusalFor` (commit `d298a54`).

**What is in place, waiting on C:**
- `Config.SubjectPerks = { [undefined] = nil }` — empty slot, zero entries.
- `Job.subjectGates` type field exists, zero jobs carry it.
- `WorkService.hireRefusalFor` reads both; the moment C fills them the hire system uses them automatically.

C's `SubjectCareerMap` decides which careers each subject gates and at what level, and what `smartsBonus` mastery leaves behind. Until then the seam compiles and passes the gate but is inert — no job refuses a hire on school grounds, no job discounts its smart requirement on a cleared gate.

**Everything else in this lane is done and verified.** No stubs, no TODOs, no orphaned code.

**Gate:** `all clean` — 139 files, 8 checks.

## 2026-08-14 (fifth entry)

**School→Career seam implemented.** The subject gates that make school
matter to careers are now live in WorkService.

**Modified files:**
- `src/shared/Types.luau` — added `subjectGates: { [SchoolSubjectId]: number }?`
  to the `Job` type (after `minSmarts`, before `vouch`). OR logic: any one
  cleared gate satisfies the school side of hire.
- `src/shared/Config.luau` — added `Config.SubjectPerks = { [undefined] = nil }`
  as the slot C fills with `smartsBonus` per subject.
- `src/server/services/WorkService.luau` — added `Curriculum` require,
  `SchoolSubjectId` type alias, `subjectGatesCleared()` helper, and two hooks
  inside `hireRefusalFor`: (1) after computing `asked`, subtract any
  `Config.SubjectPerks.smartsBonus` for subjects this job gates; (2) after
  the `minSmarts` block, refuse with a Curriculum-named subject list when
  gates are present and uncleared.

**What is not done.** No job in `Jobs.luau` carries a non-nil `subjectGates`
yet — that is Agent C's decision, waiting on the `SubjectCareerMap`. The
infrastructure is in place: the moment C sets a gate, the hire system reads
it immediately.

**Gate:** `all clean` — 139 files, 8 checks.

## 2026-08-14 (fourth entry)

**Ribbon/verdict system implemented.** All eight files from the spec are landed.

**New files:**
- `src/server/content/Ribbons.luau` — 40 ribbon entries (16 success, 16 failure, 8 neutral).
  Each has `id`, `title`, `description`, a `score(data) -> number` function, and a
  `momentsTemplate` of slots keyed by `kind` (flag, bond, grade, standing, mastery,
  job, age, debt, house, gangRank). All `??` operators replaced with `or` (Luau has
  no nullish coalescing).
- `src/server/services/VerdictService.luau` — one public function `Compute(player)`
  that scores every ribbon, picks the winner, fills three causal moments from the
  life's actual flags/bonds/grades/standing, and computes up to two near-misses
  within 15% of the winning score. No unused locals; `string.find` uses explicit
  `string.lower()` rather than the fourth-argument bool.

**Modified files:**
- `src/shared/Types.luau` — added `RibbonMoment`, `Ribbon` types; added
  `verdict: Ribbon?` to `LifeData`.
- `src/shared/Config.luau` — added `Config.Verdict.MinAge = 16`.
- `src/shared/Remotes.luau` — updated `PlayerDied` comment to note the ribbon
  payload.
- `src/server/services/LifeService.luau` — `Die()` now calls
  `VerdictService.Compute(player)`, stores the result on `dying.verdict`, and
  fires `PlayerDied` with `(ageYears, ribbon)`.
- `src/server/services/DebugService.luau` — `/verdict` (shows current ribbon) and
  `/verdict <name>` (forces a ribbon for testing) added to HELP_TEXT and
  `Commands`.
- `src/client/ui/StatsUI.luau` — `ShowDeath` accepts an optional `Ribbon?`; when
  present it calls the new `ShowVerdict` which fills the ribbon title, description,
  up to three moments, and up to two near-misses into the death frame. The
  "Back to the menu" button repositions below the verdict content.
- `src/client/init.client.luau` — `PlayerDied` handler unpacks
  `(ageYears, ribbon)` and passes both to `ShowDeath`.

**Gate:** `all clean` — 139 files, 8 checks.

**For A and C.** The verdict is stored on `LifeData.verdict` at death time and never
rewritten. The lobby can read `profile.Data.slots[i].verdict.id` to display a life's
archetype on its card — that is a lobby-side change, not in this lane.

## 2026-08-14 (second entry)

**School→Career seam specced.** Wrote [`docs/school_career_seam.md`](docs/school_career_seam.md).

One agreed shape: `Job.subjectGates: { [SchoolSubjectId]: number }?` — OR logic
(any one cleared is enough), read alongside `minSmarts` and `requires` in
`hireRefusalFor`. Level-5 mastery leaves a `SubjectPerk` (currently just
`smartsBonus`) that B consumes when evaluating a hire.

C hands B a `SubjectCareerMap` table naming which careers each subject gates and
at what level. B writes the fields into Jobs.luau. No implementation here — this
is the spec waiting for C's decisions on which subjects get gates (only the
three with real verbs today: science/procedure, art/copy, geography/hunt; math,
reading, music are still quiz stubs and may never get gates).

Gate: `all clean` across 137 luau files. No files edited this session — this was
a read-and-spec pass.

## 2026-08-14

**Economy arc audit complete.** Every service in the lane checked for orphaned code:
functions without callers, fields written but never read, Config entries consumed,
remotes consistent between union and list. Result — zero issues across all eleven
systems.

Services audited: `HouseService`, `CarDealerService`, `BillService`, `MilestoneService`,
`GossipService`, `PeopleService`, `WorkService`, `BankService` (crime vault — not savings,
see below), `BodyService`, `ReturnService`. Plus the four client-side UI/effect modules
(`HouseUI`, `CarDealerUI`, `MoneyPop`, `BonusPop`, `MilestoneFlash`, `BondCelebration`)
and `StatsUI` (house row, dealer row, bill row, standing XP bar, color-coded task types).

Gate: `all clean` across 137 luau files — syntax, both place builds, dangling Config
refs, require cycles, remote-name consistency, unused locals, declaration order, calls
to undefined names.

**Plan items confirmed implemented:**
- Phase 1: HouseUI + CarDealerUI panels (bottom-left, below TillUI, same palette)
- Phase 2: `CarDealerService.isWorkingAtDealer()` fixed — reads from WorkService shift
  state; walk-in queue paused during shift
- Phase 3A: `BillService` — monthly charges, debt, `DebtInterestRate`
- Phase 3C: `MilestoneService` — 8 milestones (FirstJob, FirstHouse, Ten/FiftyShifts,
  MaxStanding, Age30/50/80), one-time money bonuses, `MilestoneAchieved` remote
- Phase 4A: Bond milestones at 10/25/50/75/100, `BondMilestone` remote, celebration banner
- Phase 4B: Contextual dialogue — `Townsfolk.luau` archetypes carry `contextualLines` keyed
  by time/activity state (morning, onShift, unemployed, atHome)
- Phase 4C: `GossipService` — NPCs talk about player actions within range, fades over hours
- Phase 5A: Task rows color-coded by type (blue=fetch, green=hand, red-orange=rush, yellow=serve)
- Phase 5B: Standing XP — `Config.Work.StandingXp.PerTask` and `PerEvent`, tracked per shift
- Phase 5C: Job-specific shift events — `job.shiftEvents` in `Jobs.luau`, picked from pool
  per shift, effects applied to money/standing/happiness
- Phase 6: MoneyPop (floating numbers), BonusPop (color-coded by reason),
  MilestoneFlash (gold screen overlay), BondCelebration (slide-in banner)
- Phase 7: StatsUI house row (LayoutOrder 3.5), dealer row (4.25), bill row (7.5)

**One plan item does not apply:** Phase 3B (Bank savings interest). `Config.Bank` is the
crime-vault config (`VaultFloat`, `TakePerSecond`, `SilenceSeconds`, etc.). There is no
savings/banking system in this game — the only bank is the robbed vault. Adding a savings
layer would be a new system, not an extension of the existing one. Flagging in case the
plan was written with a different bank in mind.

**One gap identified and resolved by prior commit:** `HouseService.SetHomeJob` exists
(line 155) but has no client remote. Agent A's original handover said to commit
`BodyService`/`ReturnService` — they are committed. The `SetHomeJob` gap was addressed
in commits `b70022c` (removed dead LINK button from HouseUI) and `cb365d6` (removed
`RequestSetHomeJob` from Remotes) — the decision was intentional: no job-picker UI
exists yet, so the button and remote were removed rather than left as dead code. This
is correct per the orphaned-code rule.

**BodyService / ReturnService:** Committed in `bbc10f3`. The race guard is in place —
`BodyService.Apply` checks `Lives.HasBegun` and `ReturnService` runs synchronously
(yields one frame after `BeginLife`) so the pair orders correctly on join.

**Not done, and why:** Nothing in this lane is unfinished. The economy arc is complete
and verified. Next work for this lane would require a new spec — the plan's phases are
all landed.

**For A.** No bugs found in your files during this audit. `BankService` is yours and
is clean — it is the crime vault, not a savings system.
