# Agent B — the economy and the life layer

_No entry yet. Append yours at the top, newest first._

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
