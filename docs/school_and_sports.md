# AGES: school redesign and sports spec (researched 2026-08-08)

Read `ages_activity_design_law.md` first — this file is that law applied to the two systems
that most need it. School is currently five 20-second multiple-choice questions with a teacher
NPC that is pure spectacle (no failure path branches on it). Sports is unbuilt.

---

# SCHOOL

## The diagnosis

**Players skip class because every competing activity is mechanised and class isn't.** Only two
Roblox games solved "class" mechanically — RoHigh and Roblox High School 2 — and both did it the
same way: *a class is a 2–4 minute minigame with a letter grade attached to a payout.*
Brookhaven's school has no class system (a player volunteers as teacher and the lesson is
homework for them). Berry Avenue puts school next to bank robbery, and bank robbery has a loop.
Adopt Me's school is a need-meter stop. Bloxburg has no school at all.

## Bully is the single best reference, and the reason is one sentence

**Every subject is a different *verb*, not a different question set.** Anagram, area-control,
directional sequence, rhythm, aim, photo hunt. Only Math is a quiz — and Math is the least-loved
class in the game. Persona 5 has the same tell: its classroom questions are real-world trivia
unrelated to the game, so everyone just uses a guide. **Never use real trivia in AGES.**

Bully's structure: two classes/day, 5 in-game days, **an in-game hour = 1 real minute**, five
levels per subject. The four lessons to steal:

1. **Different verb per subject** (above).
2. **Each class buffs a verb used outside class.** Gym → throw accuracy and wrestling moves.
   Chemistry → unlocks firecrackers/stink bombs (a crafting tree). Geography → **marks
   collectibles on your world map** (the best reward in the game). Art → social ability. This is
   the mechanism that stops school feeling like a detour.
3. **Difficulty is a rising threshold on the same minigame**, not new content. Art level 1 needs
   less canvas uncovered than level 5. Five levels = five sessions of reuse per asset.
4. **Passing buys the right to skip.** Clear level 5 and attendance becomes optional — the
   minimap bell goes grey. **Mastery is an exit, not a treadmill.** This is the single most
   important anti-boredom mechanic and no Roblox school game has it.

Truancy in Bully: 30 in-game minutes (~30 real seconds) grace, then prefects actively hunt you
and drag you to class. You cannot apologise for truancy specifically.

Also worth knowing: RHS2's Science class splits the room red vs blue and sends everyone
**running through the hallways** collecting scrap — a scavenger hunt that uses the school
building as the level. Its Cooking class auto-pairs players into duos with a shared cauldron
(3 ingredients = 1 recipe). Period 4 is **always lunch with no minigame** — a deliberate
breather. Detention is a **2-minute obby you can escape**, not a timeout.

## The spec

**Structure.** Per school year: **4 periods/day, ~90–150s each, period 3 always Lunch/Recess**
(free-play social block, no minigame — RHS2's proven breather). Subjects drawn from a pool of 6;
**only 3 scheduled on any given day**, so a missed subject costs a full cycle.

**Six subjects, six distinct verbs, zero quizzes:**
1. **Reading** — anagram / word-build. Touch-friendly: tap letter tiles.
2. **Science** — follow a shown 4–8 step tool order at the bench. Three strikes.
3. **Art** — area-control or colour-grid replication (the mobile-safe version).
4. **Music** — 4-lane rhythm. Windows: **±80ms Good / ±45ms Great / ±25ms Perfect**
   (StepMania judge-4 reference is 22.5/45/90ms).
5. **Geography/History** — a *spatial* hunt through school and town for landmarks. Reward =
   permanent map markers, Bully-style.
6. **PE** — **the live 3v3 soccer match, graded.** *(Reconciled 2026-08-28: soccer was
   built to full engineering depth rather than as a solo drill — see the Sports section
   below — and PE grades that same always-on match rather than a separate minigame.
   `SoccerService.Begin` is the join between the two systems and it is what makes school
   carry the childhood years. Walking onto the pitch outside class time joins the same
   roster with no grading window open; the four solo drills further down stay a
   separate, always-available skill-training system and are not what PE grades.)*

**Grading** → letter A–F → three payouts: currency, **Subject XP into a specialisation track**,
and a stat. Subject XP gates careers at branching step 3 (Science → doctor/engineer, PE →
athlete, Art → creative). **Show the career you're building toward on the report card** so a
child-years player can see the point.

**Five-level mastery ladder per subject**, thresholds ~40/55/70/85/95% of max score. **On
clearing level 5 that subject becomes optional forever** and leaves a passive perk. Non-negotiable.

**The free stat, Persona-style.** During any class a **3-dot prompt appears over the teacher's
head 2–3 times** (fits our existing interaction grammar exactly). Correct = free stat, no time
cost, no penalty for wrong. In P5 this is the only stat gain that costs no time slot, which is
precisely why players engage with it. Questions must be about the **AGES world**, never real
trivia. P5's exam payoff is a *persistent multiplier*, not a checkpoint: Top of Class = 1.5×
social gain until the next exam, Top 10 = 1.2×. Steal that shape.

**Peer mechanics (13+ safe).** Pair two players (or player + NPC) into a shared score, RHS2
Cooking style. Add a **Help / Share Notes** 3-dot on a struggling classmate: gives them score,
gives you a friendship tie. Our ties ladder feeding school.

**Risk/consequence (13+ safe).** No cheating-as-crime. Instead **Cram** (spend an evening for +1
class level next attempt) vs **Skip** (free the slot for a job or sport, incur an absence).
Absences: 3 → detention (a 2-minute escapable obby), 5 → grade cap, 8 → guardian event and a
locked career branch. Lateness: **~30-second real grace from the bell**, bell SFX + an orange
pip; after grace a hall-monitor NPC walks you in and you forfeit the first scoring segment.
**Consequence must be loss of upside, never punishment-by-waiting.**

---

# SPORTS

## Pick one sport and build it to depth: soccer

One physics object, and both *Soccer: Touch Football* (~399M visits, ~85% rating) and *Blue Lock
Rivals* prove Roblox players will play it.

## Input primitives, ranked for Roblox + mobile

Ranked on single-touch feasibility, tolerance to 80–200ms latency, and phone-size readability.

1. **Three-click meter** (golf). Click 1 starts a sweeping marker; click 2 sets power, with an
   **overswing zone that gives more power but speeds the marker up**, degrading click 3; click 3
   sets accuracy against a window. **Zero RNG, every input owns one variable.** The most reusable
   meter in all of gaming, and the overswing zone is free risk/reward.
2. **Charge-and-release power bar** (Blue Lock Rivals holds M1; FF2 has 19 power levels 1–95).
   Latency-immune — the release *value* is what's sent.
3. **Single timing window on a moving marker** (NBA 2K green window is **~40–60ms**, shifting
   ±30–47ms by animation/distance; FIFA timed finishing ~50–80ms). **Widen drastically for
   Roblox: ±120ms Good / ±60ms Perfect.** 40ms is unplayable over Roblox replication plus mobile
   touch latency.
4. **Aim reticle + timing, two-axis** (MLB The Show PCI — widely considered the best batting
   input in games). Deepest primitive here but needs a second thumb. **Ship a sensitivity slider
   on day one** — The Show 26 added one because fixed PCI speed broke muscle memory.
5. **Body-contact physics, no shoot button** (*Touch Football*): movement only — WASD, jump,
   double-jump — and **you shoot and pass by touching the ball with your body**. Skill is
   approach angle, speed, timing. Lowest ceiling per action, highest accessibility, and its
   numbers justify it.
6. **Directional flick vocabulary** (2K dribble stick). On mobile, swipe-on-a-pad. Cap at 4
   directions + 1 modifier.
7. **Contextual two-button loadout.** Roblox's own docs cite *Super Striker League*: off-ball =
   Sprint + Tackle; on-ball those **swap** to Deke + Pass. The button set changes with state
   rather than growing. **Adopt as global UI law.** Minimum tap target 44–50px, thumb zone.
8. **Rhythm lane timing** — perfect for training drills and PE class, fully client-side.
9. **Combo chain with a decaying balance resource** (Tony Hawk). A *transition* partially resets
   balance, which rewards variety — the best anti-camping mechanic found.
10. **Meter that governs power *and* accuracy** (Madden), where the window **shrinks under
    pressure**, and **missing it falls back to your ratings rather than failing outright**. The
    kindest failure design in sports games. Steal this rule specifically.
11. **Gesture-as-verb with auto-positioning** (Wii Sports Tennis removed running entirely —
    auto-move the player, let them own only the strike). Ports perfectly.
12. **Alternating-tap speed build** (Track & Field). Use sparingly — Sakurai's critique is that
    it rewards innate tapping speed with little improvement headroom, and it's a wrist-injury
    vector on touchscreens. Short bursts only, always capped by stamina.

Rocket League's pure-physics model is aspirational but not achievable under Roblox replication
(Psyonix ran Bullet Physics, not Unreal's, to own the sim). Cherry-pick the philosophy.

## What Roblox sports games actually do

- **Football Fusion 2** — LMB throw, RMB context catch, 19 power levels, an in-game controls
  list, and a **teleportable practice field**. The practice field is why it has a skill culture.
- **Blue Lock Rivals** — hold M1 to charge (tap-shooting deliberately weak), M2 lock-on quick
  pass, jump-before-passing extends range, **Flow** charges to ≥30% then activates as a timed
  buff. Widely criticised for **no tutorial at all**.
- **Hoopz** — power is a *separate* variable from timing. Already went through a "Shooting V2"
  rework, i.e. the first timing model didn't survive players.
- **TSB** (input feel only) — feels good because inputs are *cancellable*, not because there are
  many.

## The technical pitfalls

These are covered in depth in `ages_roblox_engineering.md`; the sports-specific summary:

1. **Never transfer ball network ownership per touch** — it freezes the ball ~0.5s on every
   possession change. Server owns the authoritative ball; render a **client-side visual clone**
   that lerps toward the authoritative CFrame.
2. **Server ownership costs a full RTT per kick** — at 175+ ping the ball visibly trails the
   striker. Hide it with the visual clone plus a short **client-authoritative contact window**
   (client decides the moment of foot-to-ball; server validates distance and cooldown).
3. **Client ownership is a total exploit surface** — attach a BodyVelocity and the ball flies.
4. **Possession contests: use per-frame magnitude checks, not `Touched`.** Every slide-tackle
   thread breaks because `Touched` keeps firing through debounces. Contest = server compares
   distance, facing dot-product, and a per-player claim cooldown; **ties go to the defender** to
   avoid steal-spam.
5. **Lag compensation:** rolling position buffer sampled ~0.1s holding a few seconds; client
   sends an `os.clock()` timestamp; server rewinds and validates with OBB intersection.
6. **Animation blending:** `Play(fadeTime)` fade is **linear and unchangeable**, which makes
   sports moves look weightless. Tween `AdjustWeight` with an easing curve, normalise weights
   across active tracks each frame, and ramp `IKControl` weight only during the ball-contact
   window.
7. **13+ contact:** no ragdoll, no tackles-to-ground. Brief stagger animation + possession loss
   + ~0.4s control lockout. **Contact resolves as a possession contest, never as damage.**
8. **The pitch must not stream out** — client physics only simulates in streamed regions.

**The big one: Roblox Server Authority went GA 2026-07-09 and one of the three official
templates is a soccer game with a physics ball.** Build sports as its own place with
`AuthorityMode = Server` and study that template before writing anything. See
`ages_roblox_engineering.md`.

## The spec

- **Core input, mobile-first: charge-and-release + aim.** Hold → power bar fills over ~0.9s with
  an **overcharge zone in the last 15%** that adds power but randomises direction ±8°. Release
  timing is the only timing check, evaluated client-side, sent as a value. Aim = camera facing,
  so no second thumb is required.
- **Contextual two-button UI always.** Off-ball: Sprint + Press. On-ball: Shoot + Pass. Swap via
  `ContextActionService` bind/unbind. **Never more than 3 action buttons visible.**
- **Timing windows: Perfect ±60ms, Good ±120ms, else fall back to the player's Sport stat.** A
  bad release should *degrade*, never *fail* (Madden's rule).
- **Stamina as one shared pool** for sprint, press and shot power — that makes every sprint a
  decision. Empty = "winded" for ~2s at 60% move speed, not a hard stop. The three documented
  failure modes: max too high (never affects choice), recovery too low (waiting is anti-fun),
  too many actions tied to it (choice overload).
- **Momentum:** a Form bar filling from completed passes/tackles/shots-on-target, spendable at
  ≥30% for a timed buff. Purely positive-play driven (Blue Lock's proven shape).
- **Ship the solo layer first — this is the default case in a life sim.** Four drills, each with
  a personal-best board: wall-pass streak, cone time-trial, target shooting with weighted corner
  values, keepy-up rhythm lane. Proven scoring templates: *N-in-a-row inside a time window*,
  *sets of 10 count the makes*, *time trial vs your own recorded best*, *weighted points* so
  weak-foot and corner attempts are worth more. **Score month-to-month as well as all-time**, so
  recent form is visible and not just a lifetime record you'll never beat. Layer objectives into
  one run rather than adding more courses.
- **AI opponents scaled by the Sport stat.**
- **PE class = the live 3v3 match, graded** (reconciled 2026-08-28 — see the subject-list
  entry above). These solo drills are a separate, always-available system that raises
  Sport skill and speed on their own; they are not what PE grades.
- **A tutorial is mandatory.**
