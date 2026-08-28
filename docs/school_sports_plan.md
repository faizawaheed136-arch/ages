# School + Sports — the build plan

This is the ordered queue for Agent C. The *design* is settled in
[`school_and_sports.md`](school_and_sports.md) and the law it answers to is in
[`activity_design_law.md`](activity_design_law.md). **Read both before phase 1.** This
file is only the order of work and the seams with the other two agents.

School and sports are **one lane, not two**, because PE class is the live 3v3 soccer
match. That join is what makes school carry the childhood years, and it is why building
either one alone leaves the other half-useless.

**Reconciled 2026-08-28, overriding the original phase order below:** PE is not a graded
solo drill. PE class opens a grading window on the same always-on soccer pitch anyone can
walk onto at any time — `SoccerService.Begin` puts the player on the roster and starts
scoring their performance in that live match; walking onto the pitch outside class does
the roster half with no grading. The four solo drills (item 29, `SportsDrillService`) are
untouched by this and stay a separate, always-available system that raises Sport skill
and speed on their own — they are not what PE grades. See the Soccer Skills section of
the menu (fed by `SoccerCareer` on the life record) for the career tally either path
builds toward.

Where the plan and the spec disagree, the spec wins — say so and I will fix the plan.

## Ground rules for every phase

- **Spec the phase back before building it.** One-line feature requests get agreed
  first in this project, never implemented directly. This applies to every phase below.
- Hold every minigame to the seven requirements in `activity_design_law.md`. The
  existing job system fails them — it is an idle payout pad — and is the worked example
  of what not to ship.
- **Zero quizzes.** Bully's only quiz subject is its least-loved. Persona 5's classroom
  trivia is unrelated to the game, so everyone uses a guide. Never use real-world trivia.
- Every system ships with a debug command in `DebugService.luau` **and** an entry in
  `HELP_TEXT`, or it cannot be tested without playing the whole game up to it.

---

## Phase 0 — orientation

Gate green, then read `HANDOVER.md`, `docs/README.md`, `activity_design_law.md`,
`school_and_sports.md`. Report what you think phase 1 is before starting it.

## Phase 1 — tear out the quiz

School today is five 20-second multiple-choice questions with a teacher NPC that is pure
spectacle: no failure path branches on it.

1. Replace it with the 4-period day, ~90–150s per period.
2. **Period 3 is always Lunch/Recess with no minigame** — a deliberate breather, proven
   in RHS2. Do not fill it.
3. Subject pool of 6, **only 3 scheduled on any given day**, so missing a subject costs a
   full cycle rather than a single lesson.
4. Timetable UI and the bell.

## Phase 2 — six subjects, six distinct verbs

The single most important lesson from Bully: every subject is a different *verb*, not a
different question set. Difficulty is a **rising threshold on the same minigame**, not
new content — five levels means five sessions of reuse per asset.

5. **Reading** — anagram / word-build, tap letter tiles.
6. **Science** — follow a shown 4–8 step tool order at the bench. Three strikes.
7. **Art** — colour-grid replication (the mobile-safe variant of area control).
8. **Music** — 4-lane rhythm. Windows ±80ms Good / ±45ms Great / ±25ms Perfect.
9. **Geography** — a spatial landmark hunt through school and town. Reward is
   **permanent map markers**; in Bully this is the best reward in the game.
10. **PE** — built alongside phase 6/7. It is the live 3v3 soccer match graded, not a
    separate minigame; see the reconciliation note above.

Each subject should buff a verb used *outside* class. That is the mechanism that stops
school feeling like a detour.

## Phase 3 — grading and the mastery ladder

11. Letter grade A–F → three payouts: currency, **Subject XP into a specialisation
    track**, and a stat.
12. **Five levels per subject**, thresholds ~40/55/70/85/95% of max score.
13. **Clearing level 5 makes that subject optional forever** and leaves a passive perk.
    This is non-negotiable and no Roblox school game has it. **Mastery is an exit, not a
    treadmill** — it is the single most important anti-boredom mechanic in the design.
14. Report card shows **the career you are building toward**, so a child-years player can
    see the point of any of this.

## Phase 4 — consequence

**Consequence must be loss of upside, never punishment-by-waiting.**

15. **Cram** (spend an evening, +1 class level next attempt) vs **Skip** (free the slot
    for a job or a sport, take the absence). No cheating-as-crime — 13+.
16. Absences: 3 → detention, 5 → grade cap, 8 → guardian event and a locked career branch.
17. Detention is a **2-minute escapable obby**, not a timeout.
18. Lateness: ~30 seconds of real grace from the bell, bell SFX and an orange pip; after
    grace a hall-monitor NPC walks you in and you forfeit the first scoring segment.

**Also in this phase: spec the sports pitch geometry** and hand it to Agent A. Phase 6
stalls without it and A needs lead time. See "Seams" below.

## Phase 5 — the free stat, and peers

19. A **3-dot prompt over the teacher's head, 2–3 times per class** — this fits the
    existing interaction grammar exactly. Correct = a free stat, no time cost, **no
    penalty for wrong**. In Persona 5 this is the only stat gain costing no time slot,
    which is precisely why players engage with it. Questions about the **AGES world**.
20. Exam payoff is a **persistent multiplier**, not a checkpoint: Top of Class = 1.5×
    social gain until the next exam, Top 10 = 1.2×.
21. Paired scoring with a classmate or NPC (RHS2 Cooking style), plus a **Help / Share
    Notes** 3-dot on a struggling classmate: gives them score, gives you a friendship
    tie. This is the ties ladder feeding school.

## Phase 6 — sports as its own place

**Roblox Server Authority went GA on 2026-07-09 and one of the three official templates
is a soccer game with a physics ball. Study that template before writing anything.** The
engineering detail is in [`roblox_engineering.md`](roblox_engineering.md).

One sport, built to depth: **soccer**. One physics object, and both *Soccer: Touch
Football* and *Blue Lock Rivals* prove the audience exists.

22. `sports.project.json` with `AuthorityMode = Server`. This changes the gate — see Seams.
23. Server owns the authoritative ball; render a **client-side visual clone** that lerps
    toward the authoritative CFrame. **Never transfer ball network ownership per touch**
    — it freezes the ball ~0.5s on every possession change, and this is the mistake every
    Roblox sports game makes first.
24. **Charge-and-release**: hold, power bar fills over ~0.9s, **overcharge zone in the
    last 15%** adds power but randomises direction ±8°. Release timing is the only timing
    check, evaluated client-side and sent as a value, which makes it latency-immune. Aim
    is camera facing — no second thumb, so it works on a phone.
25. **Perfect ±60ms / Good ±120ms**, and a bad release **degrades to the player's Sport
    stat rather than failing outright**. This is Madden's rule and the kindest failure
    design in sports games. Do not widen or narrow these without measuring on mobile:
    NBA 2K's ~40ms window is unplayable over Roblox replication plus touch latency.
26. **Contextual two-button UI**: off-ball Sprint + Press; on-ball those swap to Shoot +
    Pass, via `ContextActionService` bind/unbind. Never more than 3 action buttons
    visible. Minimum tap target 44–50px, in the thumb zone. Adopt as global UI law.
27. Possession contests by **per-frame magnitude checks, never `Touched`** — `Touched`
    keeps firing through debounces and is why every slide-tackle thread breaks. Contest
    compares distance, facing dot-product and a per-player claim cooldown; **ties go to
    the defender** to avoid steal-spam.
28. **13+ contact:** no ragdoll, no tackles-to-ground. Brief stagger, possession loss,
    ~0.4s control lockout. Contact resolves as a possession contest, never as damage.

## Phase 7 — the solo layer, and the join

**Ship the solo layer first — a life sim's default case is one player alone.**

29. Four drills, each with a personal-best board: wall-pass streak, cone time-trial,
    weighted-corner target shooting, keepy-up rhythm lane. Proven scoring shapes:
    N-in-a-row inside a time window, sets of 10 counting makes, time trial against your
    own recorded best, weighted points so weak-foot and corner attempts are worth more.
    **Score month-to-month as well as all-time**, so recent form is visible rather than a
    lifetime record nobody will beat again. Layer objectives into one run rather than
    adding more courses.
30. **Stamina as one shared pool** across sprint, press and shot power — that is what
    makes every sprint a decision. Empty = "winded" for ~2s at 60% move speed, not a hard
    stop. Three documented failure modes: max too high (never affects choice), recovery
    too low (waiting is anti-fun), too many actions tied to it (choice overload).
31. **Form** bar filling from completed passes, tackles and shots on target, spendable at
    ≥30% for a timed buff. Purely positive-play driven.
32. AI opponents scaled by the Sport stat.
33. **PE class = the live 3v3 match, graded.** The join between the two systems is
    `SoccerService.Begin`, not the solo drills above — those stay a separate,
    always-available skill-training system, untouched by the PE join.
34. **A tutorial is mandatory.** Blue Lock Rivals' single biggest criticism is having
    none, and Football Fusion 2's skill culture exists because of its practice field —
    ship a teleportable practice pitch.

---

## Seams with the other agents

Three places where this lane touches someone else's. Raise them early; do not work
around them.

**1. Geometry is Agent A's, always.** The pitch, cones, targets, wall-pass boards, the
school interior — all of it is generated by `tools/` into `assets/`, which C must never
touch. `City.rbxmx` is 8.4 MB of generated XML and a conflict in it cannot be
hand-merged. **Spec what you need in phase 4** and hand it over; A needs lead time and
phase 6 stalls without it.

**2. A third place changes the gate.** `tools/check.py` builds two projects and would
not know about `sports.project.json` — meaning a broken sports tree would pass silently,
which is exactly the failure mode the gate exists to prevent. `check.py` is A's file.
Propose the project file, let A wire it in.

**3. Subject XP gates careers**, and careers are Agent B's at branching step 3. C defines
the XP tracks and what each subject feeds (Science → doctor/engineer, PE → athlete, Art
→ creative); B consumes them. This needs **one agreement on the shape**, not ongoing
contact.
