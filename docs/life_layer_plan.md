# Life layer — the build plan

This is the ordered queue for Agent B. The *design* is settled in
[`lifesim_design.md`](lifesim_design.md) and the law every activity answers to is in
[`activity_design_law.md`](activity_design_law.md). **Read both before phase 1.**
This file is only the order of work and the seams with the other agents.

The life layer is **one lane, not several**, because the chapter spine, the event
system, the autonomy quota and the rival slots are one feature at four scales. Phase 1
without phase 5 is a clock. Phase 5 without phase 1 is a relationship without a place
to be one. Building any of them alone leaves the rest half-built, the way school
without sports leaves school half-playable.

Where the plan and the design disagree, the design wins — say so and I will fix the
plan.

## Ground rules for every phase

- **Spec the phase back before building it.** One-line feature requests get agreed
  first in this project, never implemented directly. This applies to every phase below.
- Hold every activity to the seven requirements in `activity_design_law.md`. The
  existing job system fails them — it is an idle payout pad — and is the worked example
  of what not to ship.
- **Zero need bars.** A state exists because something happened, and the state
  triggers content. A bar that drains on a timer is the Sims trap and we have
  committed not to walk into it.
- Every system ships with a debug command in `DebugService.luau` **and** an entry in
  `HELP_TEXT`, or it cannot be tested without playing the whole game up to it.
- **Do not narrate. Emit facts and get out of the way.** A named rival, a named injury,
  a named grade. Specific enough to connect, no more.

---

## Phase 0 — orientation, and two contradictions to report

Gate green, read [`lifesim_design.md`](lifesim_design.md),
[`step3_scope.md`](step3_scope.md), [`activity_design_law.md`](activity_design_law.md).
Report what you think phase 1 is before starting it.

Two settlements in conflict with the code. Both must be adjudicated before the
chapter spine lands:

**(C1) Bond decay.** `Config.People.DecayPerYearAway = -3` and `Ties.luau`'s header
both say "the only way a friendship ends in this game is that you stop turning up
and the bond decays." `lifesim_design.md` names decay-on-neglect as a trap in the
same family as decaying need bars, and locks the rule that gains stick. One of these
is wrong. The design wins — decay is the trap. Resolution lives in phase 5.

**(C2) Ambient events.** `lifesim_design.md` and `step3_scope.md` both say events
must fire at random in the world, with the same user commitment from 2026-07-28.
`EventService.OfferForAge` is the only call site in the code today. Diagnosis stands;
resolution lives in phase 3.

## Phase 1 — the chapter spine

Nothing in `src/` matches `chapter` or `reel`. This is the frame the rest hangs on.

1. **6 chapters of 5–10 minutes, 35–60 minutes per life.** Chapters are a band of
   ages, not a timer. Decide the bands and where they break.
2. **The break is the birthday, with a diegetic Continue button.** The player presses
   it. The game does not cut. Agency at the seam.
3. **The "months passed" reel, and it carries news or it is cut.** What changed in the
   world, what an NPC did without you, what a tie moved to. A reel of decorative slides
   teaches the player to skip it, permanently — so build the news source first and the
   screen second. If there is no news, show no reel.
4. You already built the ribbon system. Ribbons are the answer to the Day-3 wall and
   chapters are the answer to the 40-minute session. They are the same feature seen at
   two scales; make the reel and the verdict share one "what happened" query.

## Phase 2 — finish the event schema

The schema in `lifesim_design.md` is `{ tags, requires, weight, cooldown, escalates_to,
writes_back }`. `requires` and `weight` exist. `seenEventIds` already gives per-life
repeat suppression. Missing: `tags`, `cooldown`, `escalatesTo`, `writesBack`.

5. **`writesBack` is mandatory and enforced at load.** An event that cannot write to a
   stat, a tie, a flag or a ribbon condition is a cutscene — `error()` naming the id at
   require time, the way `Tills.luau` and `Jobs.luau` already do.
6. **`escalatesTo` — chains, never cold rolls.** A follow-up comes from the prior event,
   so the player can trace the thread. A cold random event feels like weather.
7. **1–3 events per chapter.** More than that and no single one registers. Enforce it in
   the picker, not in the content.
8. **70/30 world-spawned to modal.** The majority happen in the world — an NPC walks up,
   a marker appears. Modal panels are the minority, for things that need a decision
   surface. This is the same rule as the 3-dot interaction grammar.

## Phase 3 — ambient events (an owner commitment, unshipped)

9. An ambient trigger source — timers plus proximity to NPCs and locations — feeding the
   existing `EventService` selection. The `delivery` seam built in step 2 is the intended
   extension point; do not build a parallel one.
10. World deliveries as `EventUI` handlers: NPCApproach, Location, Letter, PhoneCall.
    `DeliveryService` already does two-phase staging with `deliveringEventId` /
    `pendingEventId` — extend it rather than duplicating it.
11. **Events advance the year in ages 0–5 only.** Explicit owner decision. Never let an
    adult event call `AgeUp`.

## Phase 4 — the autonomy quota

12. **At least one NPC-initiated interaction per 60 seconds of walking.** InstLife's
    fatal flaw was that nothing happened unless you tapped it — a list of buttons is not
    a life.
13. **Measure before you build.** Instrument the current rate first and report the real
    number. A debug command that prints seconds-since-last-approach and the rolling
    average, so the quota is a thing you can see failing rather than a thing you assume.

## Phase 5 — rivals, mentors, and NPC memory

Bonds already run −20..100, so negative ties are representable and unused. Nothing in
`src/` matches `rival`.

14. **Three structural slots replace romance entirely: rivals, mentors, family.** These
    carry the weight romance carries elsewhere and stay 13+ forever. Rivalry is the
    engine for sports and school — coordinate the shape with C once, not continuously.
15. **Negative ties are content.** A rival is a relationship, not an absence of one.
16. **NPC memory: 5 rolling + 1 defining.** Five recent interactions in a queue plus one
    permanent defining moment that never falls out and gets quoted back at the player.
    Cheap to store, enormous perceived depth.
17. **No gift-preference tables.** Stardew's likes/dislikes matrix becomes a wiki lookup
    and the player stops playing. If gifts exist they respond to *context* — what
    happened recently — never to a hidden static table.
18. Resolve the decay contradiction from phase 0 here. Positives ratchet, decay dies.

## Phase 6 — the corner shop verb: fetch and bag

**The stage is already built and standing** — generated into `Town.rbxmx` this
session. Place point `corner_shop`, in the town, opposite the player's own front gate.
Service spine along the north wall, customer aisles south of it, crates forty-one studs
from the till so the run exists.

**The full spec is in `MAP_PLAN.md` section A, written against all seven requirements of
the activity design law.** Read it there; the short version is: a customer names 2–4
things, you run the aisles, bag them, hand the bag over. Two queues (customers and shelf
stock), stock as the traversal consumable, patience as a payout multiplier rather than a
pass/fail, escalation by reshuffling the shelf plan rather than raising the arrival rate,
and the basket capacity as the progression that widens what the player can hold in their
head.

19. This is a job — `WorkService`, `content/Jobs.luau`, `JobTasks.luau`, all yours.
20. **Nothing in the shop geometry is tagged.** A tag no service reads is orphaned code,
    so I left them off. When you need the counter, the shelf faces or the crates tagged,
    name the tag and the attribute in your handover and I will add them — that is a
    one-line change in `gen_town.py`, which is mine and which you must not touch.
21. The existing job system is the worked example of what *not* to ship: the law calls it
    an idle payout pad. This shop is the argument that we can do better in the same
    service. If fetch-and-bag lands well, the honest next question is which existing jobs
    get rebuilt on it.

## Phase 7 — states, not bars

22. **No decaying need bars. None.** The Sims' named trap: bars that drain on a timer turn
    the game into maintenance chores and punish the player for engaging with content.
23. **State-triggering instead.** A state exists — tired, broke, in trouble — because
    something *happened*, and it triggers content. **States open doors, they do not close
    them.** `BillService` debt is the closest thing already built; check whether it opens
    a door or only closes one, and report.

## Phase 8 — career branching, and the seam with C

24. Career branching with uncertain success is committed. It needs requirements and flags
    on `LifeEvent` — stat deltas alone cannot open and close doors, and the machinery is
    shared with relationship continuity, so build them together, not twice.
25. `Job.subjectGates` and `Config.SubjectPerks` are already in place and inert, waiting
    on C's `SubjectCareerMap`. That seam needs **one agreement on the shape**, not ongoing
    contact. If C has not delivered it by the time you reach this phase, say so and move
    on rather than blocking.
26. **Horizontal meta-progression only. Never starting stats.** Vertical unlocks make the
    first life feel like a demo and invalidate every ribbon earned before them. Zero
    gating at the door — everything is reachable on life #1. The reason to play again is
    that you now know the system.

---

## Seams with the other agents

Three places where this lane touches someone else's. Raise them early; do not work
around them.

**1. Geometry is Agent A's, always.** The corner shop interior, the chapter-break
birthday room, the rival/mentor/family NPC spawn points — all of it is generated by
`tools/` into `assets/`, which B must never touch. `City.rbxmx` is 8.4 MB of
generated XML and a conflict in it cannot be hand-merged. Spec what you need in
phase 0 and hand it over; A needs lead time and phase 6 stalls without it.

**2. Rival/mentor/family shape is shared with C once.** Rivalry is the engine for
school and sports as well as the life layer. Propose the slot shape, let C wire it
into their verbs; do not change it after.

**3. Subject gates and the career seam.** `Job.subjectGates` and `Config.SubjectPerks`
are already in place and inert — C's `SubjectCareerMap` is what lights them up. One
agreement on the shape, not ongoing contact.
