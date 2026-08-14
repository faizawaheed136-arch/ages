# Agent B — the economy and the life layer

_No entry yet. Append yours at the top, newest first._

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
