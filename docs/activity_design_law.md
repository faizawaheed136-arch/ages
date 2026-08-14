# AGES: how to build an activity (the law)

Researched 2026-08-08 across Bloxburg, Work at a Pizza Place, Overcooked, Stardew, Adopt Me,
ER:LC, My Restaurant, and the game-design literature on engaging repetition. This is the
general law. School, jobs, sports and anything future must pass it.

**Why this exists:** our job system shipped as "stand on a glowing circle for four real
minutes while a wage ticks." The audit found the wage is credited per game-hour *regardless of
task outcome* — so rushing and dawdling pay the same. That is the definition of an idle payout
pad, and Southwest Florida's AFK bridge-operator job is the named anti-pattern. School is the
same shape: proximity check → timer → multiple-choice click → credit.

## The one-sentence test

**A task stays fun exactly as long as it is still teaching.** When the mind stops learning, the
simulation stops being fun and becomes work. Ask of any activity: *what does the player know on
repetition 30 that they didn't on repetition 1?* If the answer is "nothing," it is work.

## The seven requirements

Every activity in AGES must have all seven. This is a checklist, not a menu.

1. **One verb with a commit action and an undo window.**
   Bloxburg's burger assembler is the model: stack the ingredients, and you may freely remove
   them *until the top bun is placed*. The commit is explicit and player-chosen; failure only
   exists after commit. This makes mistakes feel like decisions instead of gotchas.

2. **Two concurrent queues, so prioritisation exists.**
   Overcooked's difficulty comes from *simultaneous* orders with free ordering, on a tiny
   control set — difficulty lives in the system, not the interface. **Two queues at 50% load
   each is far more engaging than one queue at 100%.** One queue is a conveyor belt; two is a
   decision.

3. **A consumable that forces traversal every 40–60 seconds.**
   Bloxburg's BFF cashier needs bags pre-placed, ~50 per refill, then you walk to the back for
   a crate. **The busywork becomes a resource you spend, so it generates its own pacing
   interrupt** — burst of service → forced traversal → burst of service. Verse/chorus structure
   for almost no implementation cost. This is the single best structural idea found in the
   whole sweep.

4. **A soft-failure multiplier, never binary pass/fail.**
   Work at a Pizza Place's star rating: 3 stars = 100% pay, 2 = 80%, 1 = 30%, 0 = 0%. Overcooked
   uses a 3-star coin gradient. Bloxburg uses an "efficiency" stat. Losing a customer should
   cost money, not the shift. **And a perfect shift must pay visibly more than a sloppy one** —
   if outcomes don't differentiate, the skill has been deleted. (Ours currently don't.)

5. **Escalation by changing the space, not the numbers.**
   Overcooked's disruption levels (sliding counters, earthquakes separating players) exist
   explicitly to prevent role-lock — players self-assign permanent lanes and optimise the fun
   away. Bloxburg's pizza stations stop being reachable from one spot, converting a UI task
   into a movement task. Bloxburg's map update added speed limits. **Spatial escalation forces
   re-planning; numeric escalation does not.**

6. **Progression that visibly widens the player's own tolerance.**
   Stardew grants +1 rod proficiency per fishing level, which *physically enlarges the green
   bar* and cuts max bite delay. The player sees their margin grow. Compare Bloxburg, where
   levelling mostly changes a wage number — invisible inside the verb. **Never make progression
   only a number outside the mechanic.**

7. **Same input, different opponent.**
   Stardew's fish have distinct movement personalities; the controls never change but knowledge
   compounds. This is how you get 100 repetitions out of one mechanic without adding a button.

## Supporting rules

- **Any second where the player has no input available is a bug.** Bloxburg fishing has a 5–20s
  dead wait ending in one binary keypress — it is the most-criticised job in the game. Bloxburg
  mining has a 1s-per-swing wait, but TNT blocks hiss when struck and give a flee window, which
  converts the same clock into a risk/reward decision. Identical dead time, opposite feel.
- **Reward per task should be small and frequent.** Bloxburg pays $7–$25 per task at level 1.
  Over-rewarding devalues the reward and makes the task feel like a toll ("I had to do all that
  for *that*").
- **Shift length should be defined by tasks completed, not by a clock.** Ours is a 4-minute
  timer; that is why it reads as waiting.
- **Cross-system upgrades make the world cohere.** Bloxburg: gym → walk speed → janitor
  throughput. An out-of-job investment upgrades an in-job verb. Wire our stats into activity
  *throughput*, not just into gates.
- **A trivial verb with a discovered optimal technique beats a complex verb with an obvious
  one.** WaaPP's pizza boxer is "cut and box," but masters pre-open boxes while waiting and
  stage them on the conveyor so they close rather than drag. Leave room for technique.
- **Audit every activity for the degenerate strategy before it ships.** Bloxburg had to cut pay
  on the first three deliveries of a shift because players were resetting shifts to farm short
  routes.

## Signposting (a system the player cannot find does not exist)

- **A directory with teleport.** Bloxburg's phone Jobs app lists every job, starts a shift, and
  teleports you in. Discovery must not depend on physically stumbling into a building.
- **A per-player pathfinding beam.** Client-side `Beam` from HumanoidRootPart to the current
  objective, driven by `PathfindingService` waypoints so it *curves around geometry*. Gated on
  state, visible only to its owner. This is the literal ask from the original mechanics-first
  direction ("arrows leading u to it").
- **A diegetic world-space arrow for the active task**, not a minimap ping. Bloxburg spawns a
  translucent yellow arrow the instant you pick up a delivery.
- **Ambient need markers.** BloxBurger pops a box icon above anything needing restock — the
  queue is readable across the room with no UI open.
- **A physical tutorial pad at each station** (WaaPP). Per-station, on demand, free to experts,
  always there for a returning player who forgot. **Blue Lock Rivals' single most-cited flaw is
  having no tutorial at all.**
- **Published schedules beat RNG.** Adopt Me publishes its task clock; players build routes and
  arrive early. Predictability is a skill surface.
- Standing markers are fine as an **entry** affordance and catastrophic as the activity itself.

## Named anti-patterns (all of which we currently commit)

| Anti-pattern | Named example | Our status |
|---|---|---|
| Idle payout pad | Southwest Florida bridge operator | **This is our job system** |
| Unskilled dead time as most of the loop | Bloxburg fishing | Our 3.5s verdict hold + 4min shift |
| Zero-failure tasks | Bloxburg stocker | Our task marks cannot be failed |
| Undifferentiated outcomes | — | Our wage ignores task performance |
| Numbers-only progression | — | Our standing bands are invisible in the verb |
| Job-as-nametag | Brookhaven's 80+ roles | Not yet, but the risk if we add jobs fast |
| Variety-as-fix | — | Adding more jobs will not fix a hollow verb |

**"Variety-as-fix" is the one to internalise:** a dev on the DevForum added whole new gamemodes
and the game still felt repetitive. More content around a hollow verb does not fix the verb.
Fix the verb first, then add jobs.

## Juice is confirmation, not decoration

Bloxburg's pizza baker plays an error tone on a bad build and a jingle on a good one. That is
the entire feedback layer and it is enough. Research constraint (Kao, CHI 2024): **both none
and *extreme* juiciness significantly decrease player experience** — over-juice makes it
impossible to tell which feedback is mechanically meaningful. And amplified feedback builds a
sense of competence **only when attached to an action that displays player skill**. So: juice
the player's choices hard, leave ambient and automatic events quiet.

## Loop nesting

Nest at four time scales: short (seconds–minutes), medium (hours), long (days), and make sure
the **shortest loop completes inside the first session**. The quotable line from the
best-regarded DevForum retention post: *"a grind can be continuous, but it can not be
repetitive."*
