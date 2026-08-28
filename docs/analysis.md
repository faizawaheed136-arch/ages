# AGES — In-Depth Game Analysis

**Date:** 2026-08-18  
**Scope:** Full source tree, design docs, handover notes  
**Purpose:** Feed the research commission that follows

---

## 1. What AGES Is

**Premise:** A 13+ Roblox life simulator — "an interactive, playable BitLife world." You live one or more lives from birth to death, age yourself year by year, and accumulate a named *verdict* at the end (a Ribbon: "Steadfast," "Dropout," "Convict," etc.). Death is permanent; there is no paid revive.

**Audience constraint:** All audiences, US English, 13+ hard ceiling. No gore, no gambling, no romance. Failure must be worth playing — there are ~40 named archetypes, ~40% of them failure states, and every one must be written with the same care as a success.

**North-star quote from the owner:** *"There should be a clear way to sign up for a job like arrows leading u to it or something as this is really vague and when working there should be good mechanics to do stuff to keep one busy, thats what will make the game pop."*

This is the single best summary of every design tension in the project. Everything below flows from it.

---

## 2. Core Loop (Current and Intended)

### Current loop (as built)
1. Join lobby → choose gender/country → enter game place
2. Character is a child. Age yourself via manual button (cooldown-gated) or auto timer (safety net)
3. Stat decay runs each year. Stats: health, happiness, smarts, looks (all clamped)
4. Walk to a job station, stand on it → shift begins → wage ticks per completed game hour
5. One text prompt fires mid-shift (a choice). Answer it → record changes
6. Walk off the station → shift ends
7. Repeat until age 18 → office clerk becomes available → work up the ladder to manager
8. Commit crimes → accumulate bounty → get arrested → prison (custody age-up cause)
9. Join a gang → accumulate standing → face the boss for a promotion
10. Die (health hits 0, or mortality roll past 65) → game over → lobby

### Intended loop (per specs, not yet shipped)
1. Same birth → childhood is *playable* (toddler years in 3D, events fire as world encounters, not memories)
2. Events arrive via eight delivery modes (Memory, Direct, Wander, Interact, Letter, PhoneCall, NPCApproach, Shift)
3. Most events are *enacted* — you walk to the thing, click the dots, choose
4. School has six distinct verbs (reading=anagram, science=procedure, art=area-control, music=rhythm, geography=spatial hunt, PE=graded sports drill) with a mastery ladder
5. A "corner shop fetch-and-bag" verb replaces the current idle payout pad
6. Ribbons fire at death with three causal moments, two near-misses
7. Chapter spine: 6 chapters of 5-10 minutes each, birthday seams, "months passed" reel with news
8. Inverse autonomy quota: 1 NPC-initiated interaction per 60s of walking
9. Career branching: uncertain success, tied to school + work choices

**The gap between current and intended is where the analysis lives.**

---

## 3. What Is Built and Working

### Systems with substantial, coherent code

| System | File | Size | Assessment |
|---|---|---|---|
| Data persistence | `DataService.luau` | ~800 | ProfileStore with session locking, schema v2, migration, slot management |
| Stat engine | `StatService.luau` | ~600 | 4 stats, clamped, yearly decay, sick/debt modifiers |
| Aging | `LifeService.luau` | ~800 | Manual + auto age-up, stage transitions, death, skip childhood |
| Event engine | `EventService.luau` | ~930 | Picker, resolver, one-pending-event, escalation chains, writesBack mandatory |
| Event content | `content/LifeEvents/*.luau` | ~5000 total | 12 modules, 144 writesBack annotations, validation at require |
| Job system | `WorkService.luau` | ~3000 | Shift loop, two concurrent tasks, task queues, XP for standing |
| School system | `SchoolService.luau` | ~2100 | Lesson loop, answer discs, report card, mastery |
| Gang system | `GangService.luau` | ~950 | Boss posts, promotion computation, color wearing, heat integration |
| Personality/NPCs | `PeopleService.luau` | ~2700 | Bond scale, decay, cap, offer fan, presence streaming, roaming |
| Crime tree | `CrimeService`, `TheftService`, `BankService`, `BountyService`, `PoliceService`, `WitnessService`, `DisguiseService` | ~3000 | Robbery, vault, heat, pursuit, disguise |
| Delivery layer | `DeliveryService.luau` | medium | Two-phase delivery, staging, timed presenters |
| World events | `WorldEventService.luau` | medium | Tagged anchors, zone parts, proximity checking |
| Enactment | `EnactService.luau` | medium | Dots on subjects, timeout-to-panel fallback |
| Debug harness | `DebugService.luau` | ~2800 | /ageup, /die, /stat, /job, /school, /gang, /fight, etc. |
| Content | `Jobs.luau`, `Ribbons.luau`, `Cast.luau`, `Townsfolk.luau`, `Curriculum.luau`, `Lessons.luau`, `FlagSet`, `Subjects` | ~8000 | 5 jobs, ~40 ribbons, cast of named people, school subjects |
| Client bootstrap | `init.client.luau` | ~1000 | Listens to all Remotes, drives HUD |

### Content that exists but has no verb

| Content | Status |
|---|---|
| Crime events | Events exist but theft/fight mechanics are rudimentary |
| Gym system | `GymService.luau` exists (~835 lines) |
| Fight system | `FightService.luau` exists (~1170 lines) |
| House/car/bills | `HouseService`, `CarDealerService`, `BillService`, `SavingsService` all exist |
| Milestones | `MilestoneService.luau` exists |
| Gossip | `GossipService.luau` exists |
| Return to lobby | `ReturnService.luau` exists |
| Pocket money | `PocketMoneyService.luau` exists |

### World geometry

- City generator: `tools/gen_city.py` — roads, avenues, circle ring
- Town generator: `tools/gen_town.py` — buildings on blocks
- Street generator: `tools/build_street.py` — individual street facade
- House, Furniture, SchoolFurniture: generated .rbxmx files
- **Map Plan** documents active rebalancing: avenues widened 14→24, blocks interior narrowed 114→102 studs, current binding constraint is 18-stud lane between house rows

### What is NOT built

| System | Status |
|---|---|
| **VerdictService** | File exists (~200 lines) but **never integrated** into LifeService.Death() |
| **Ribbons content** | ~40 ribbons defined in `content/Ribbons.luau` with score functions |
| **Sports** | Docs spec exists but no code |
| **Corner shop fetch-and-bag verb** | Geometry generated, verb not built |
| **Chapter spine** | No chapter tracking, no birthday seam UI, no "months passed" reel |
| **Ambient events in world** | Childhood events use "Wander" delivery but no world-space props yet |
| **Autonomy quota** | Not measured, not built |
| **Rivals/mentors/family NPC memory** | PeopleService has bonds but no 5+1 memory queue |
| **State-not-bars UI** | No visual distinction between "tired" vs "energetic" beyond stat numbers |
| **Career branching** | CareerBranch.luau event module exists but the branching logic is minimal |
| **Lobby place** | Separate `lobby.project.json` exists but spins, slots, avatar preview not built |
| **Perks system** | Config has `Config.Spins` and `Config.Perks` but no service implements them |

---

## 4. Design Tensions and Known Issues

### 4.1 The Idle Payout Pad (most critical)

**The law:** `docs/activity_design_law.md` explicitly names the current job system as the anti-pattern.

**What's actually happening:** A shift is a 4-real-minute timer. Wages are credited per game hour regardless of task outcome. Two concurrent task slots exist in code but the *soft-failure multiplier* (requirement 4) is not implemented — a perfect shift and a sloppy shift pay the same. The shift length is defined by a clock, not by tasks completed.

**The fix direction:** Implement the corner shop fetch-and-bag verb first (per the law). This is the single highest-impact mechanical change.

### 4.2 Bond Decay vs. No-Decay Need Bars

**The law:** `docs/lifesim_design.md` says "No decaying need bars" and "Positives ratchet."

**The tension:** `PeopleService.luau` documents that bonds *do* decay: "A year you did not visit costs you." This is a need bar in bond clothing — the player must visit or lose. The spec authors have not resolved this contradiction.

**Where it matters:** This is the core social loop. If bonds decay, the game becomes a maintenance chore. If they don't, relationships lose urgency. The spec's own "inverse autonomy quota" (1 NPC interaction per 60s walking) suggests the world should approach the player — which reduces the visitation burden but doesn't resolve the underlying tension.

### 4.3 VerdictService Is an Island

**The code:** `VerdictService.luau` exists and is well-written. It computes a Ribbon from LifeData, picks three moments, computes two near-misses.

**The gap:** It is never called from `LifeService.Death()`. The `PlayerDied` remote fires with `{ageYears}` only, not `{ageYears, ribbon}`. The `verdict: Ribbon?` field on `LifeData` is never written. Debug command `/verdict` does not exist.

**Impact:** This is the single highest-ROI unshipped feature per the design docs. A life that ends without a named verdict is just a list of numbers that stopped changing.

### 4.4 Gangs Built But Never Studio-Tested

**The state:** `GangService.luau` is complete (950 lines). Promotion is face-to-face, colors are worn, standing is earned separately from rank. The design is sound per `gangs_spec.md`.

**The gap:** No one has ever tested it in Studio. The gang boss NPC may not spawn. The dots may not appear. The panel may not open. The color bandana may not render.

**Risk:** This is a social system that lives or dies on first contact. If it doesn't work in practice, the entire "who you run with" layer is dead code.

### 4.5 School Is a Proximity Check → Timer → Quiz

**The current loop:** Walk to school pad → question appears with 20s timer → pick answer → repeat ×5 → lesson ends → credit smarts.

**The spec says:** Six distinct verbs, mastery ladder, free stat via 3-dot prompt over teacher.

**The gap:** The current school is a question-clicker. It moves smarts but has no verb. The six-subject model (reading=anagram, science=procedure, etc.) is fully spec'd but not implemented.

### 4.6 Event Schema Enforcement vs. Content Reality

**The enforcement:** `LifeEvents/init.luau` validates every event at require time: `writesBack` is mandatory, age ranges are valid, escalation chains don't loop, casts resolve, lures are present only on wandered events.

**The reality:** 144 `writesBack` annotations exist across 12 event modules. The enforcement is working. But `EventService` does not yet distinguish between "event that changed stats" and "event that changed nothing" — the writesBack field is checked at load time but not at resolution time.

### 4.7 The Map Plan Bug

**The issue:** `MAP_PLAN.md` documents that route graph check 12 has a defect: join points within ROUTE_LINK have no idea what's between them. A probe 14 studs behind the back fence scored 1.01, indicating a "legit" connection through a house.

**Status:** Deferred to B's regenerating town geometry. This means the navigation system may route players through solid geometry.

---

## 5. Architecture Assessment

### Strengths

1. **One-source-of-truth remotes:** `Remotes.luau` is the single definition. Union type + list kept in sync. This prevents the common Roblox anti-pattern of remote names drifting between server and client.

2. **Config-driven tunables:** No magic numbers in logic. `Config.luau` is 228KB of documented constants with safe ranges. Every tunable has a comment saying what it does.

3. **Injection over direct require:** EventService doesn't require EnactService, WorldEventService, or DeliveryService — they inject handlers at Init. This prevents circular dependencies and keeps services loosely coupled.

4. **Content validation at require time:** `LifeEvents/init.luau` throws immediately on bad content. A duplicate event ID, a broken escalation chain, a missing writesBack — all caught before the server starts.

5. **Per-hour wage crediting:** WorkService pays per completed game hour, not accrued-and-paid-at-end. This means leaving mid-shift costs nothing unearned, and rejoining preserves what was worked. A clean design decision with real consequences.

6. **ProfileStore with session locking:** Data is safe across restarts. Schema v2 with migration path.

7. **Comment density:** Every non-trivial function documents the *why*, not just the what. The WorkService.shift type comment alone is worth reading as a model for the rest of the codebase.

### Weaknesses

1. **No type-checking CI:** `rojo build` does not parse Luau. A syntax error compiles clean and only surfaces at first Studio sync. The recommended `luau-analyze --solver=old` runs without Roblox definitions, drowning real errors in cascade noise.

2. **No test framework:** TestEZ is archived. No Jest Lua, no Lune headless runner. There is zero automated test coverage. The only "testing" is the `tools/check.py` static analysis and manual Studio play.

3. **Client-server split is implicit:** `init.client.luau` has one long list of remote handlers with no schema. A server that fires a remote the client doesn't know about is silently dropped. There is no contract test between server and client.

4. **Three-agent parallel with no merge automation:** `HANDOVER.md` is the only coordination. Agent A owns world/crime, B owns economy/life, C owns school/lobby. Shared files are append-only. There is no automated conflict detection — a shared file edited on two machines simultaneously is a manual merge.

5. **Service count is high (44):** `src/server/services/` has 44 files. The init order is a 30-line dependency graph that must be maintained by hand. The comments explain the order but don't enforce it.

6. **No luau-lsp, selene, or stylua:** The project conventions explicitly call these out as absent. Formatting, linting, and inline type-checking are all manual.

7. **VerdictService is a prototype:** It works in isolation but is not wired into the death flow. This is a "works on my machine" system, not a shipped feature.

---

## 6. Gap Analysis: Spec vs. Implementation

| Spec Item | Status | Gap |
|---|---|---|
| Playable toddler years (0-5) in 3D | **Not started** | No childhood verb, no toddler movement model |
| World-spawned events (70%) | **Partially** | DeliveryService exists. WorldEventService exists. No world-space event props for childhood. |
| Modal events (30%) | **Done** | Panel resolution works. EventUI handles it. |
| 3-dot interaction grammar | **Done** | Interact module, dots on NPCs, ChoicePanel on client |
| Six school verbs | **Not started** | SchoolService exists but is question-clicker. Mastery ladder not built. |
| Sports (third place, server authority) | **Not started** | Docs spec complete. No code. |
| Corner shop fetch-and-bag | **Geometry done, verb not** | Shop geometry generated. Task system has fetch-bag state in ActiveTask type but no consumer. |
| Ribbon/verdict at death | **Service built, not wired** | VerdictService.Compute() exists. Not called from Death(). PlayerDied remote shape wrong. |
| Chapter spine (6 chapters, birthday seams) | **Not started** | No chapter tracking. `lastChapterBreakMonths` field exists on LifeData but is never read or written. |
| "Months passed" reel | **Not started** | No transition UI between chapters. |
| Inverse autonomy quota (1 per 60s) | **Not measured** | No meter, no counter, no enforcement. |
| NPC memory (5+1) | **Not started** | PeopleService tracks bonds but not interaction history. |
| Career branching | **Partial** | CareerBranch event module exists. Scoring is minimal. |
| Gang promotion face-to-face | **Built, untested** | Code is complete. Never Studio-tested. |
| Lobby spins with numeric odds | **Not started** | Config.Spins exists. No service. |
| Perks ("Born into" lead type) | **Not started** | Config.Perks exists. No service. |
| Robux spin shop | **Not started** | No monetization code. |

---

## 7. Research Priorities (Recommended)

Based on the gap analysis and design tensions, these are the research areas ordered by impact:

### Tier 1: Must-Research (blocks the next build phase)

1. **Activity verb design for corner shop fetch-and-bag**  
   The activity design law is the single most important design document. The corner shop is the first chance to apply it. Research should cover: basket size progression, patient customer impatience, multi-item orders, the 40-60s consumable traversal rhythm, and the soft-failure multiplier. This is the thing that makes the game "pop" per the owner's quote.

2. **VerdictService integration**  
   Highest-ROI feature. Research the integration points: where in Death() to call Compute(), what the PlayerDied remote shape should be, how moments are selected from the three fallback chains (flags → bond milestones → school grades → standing bands → age milestones), and the near-miss scoring. Also research whether the current ~40 ribbon definitions are sufficient or need expansion.

3. **Chapter spine and birthday seam UI**  
   The 35-60 minute life target requires a chapter structure. Research what the "months passed" reel should show (news, not filler), how birthday seams should feel (diegetic continue button, not a cut), and what data feeds the reel (tie changes, stat moves, world events that happened without the player).

### Tier 2: Should-Research (significant impact, not blocking)

4. **School verb design for six subjects**  
   The spec says six distinct verbs with zero quizzes. Research what each verb actually *is* mechanically — anagram for reading, procedure for science, area-control for art, rhythm for music, spatial hunt for geography, graded drill for PE. Each needs its own interaction model. The mastery ladder (5 levels per subject, level 5 = optional forever) also needs design.

5. **Sports mechanic (charge-and-release)**  
   Third place, server authority, charge-and-release + aim, contextual two-button UI. Research the input model, the server-authoritative placement requirements, and how sports fits into the school system and the broader life sim.

6. **Bond decay resolution**  
   The tension between "no decaying need bars" and "bonds decay" is unresolved. Research what the right model is: does bond decay make relationships feel urgent or like maintenance? What do successful life sims do? Is there a third option — state-triggering instead of timer-draining, as the spec suggests?

### Tier 3: Nice-to-Research (quality of life)

7. **NPC memory model (5 rolling + 1 defining)**  
   How to store, retrieve, and surface interaction history. What the "defining moment" looks like when quoted back. Whether this needs new fields on LifeData or can piggyback on existing structures.

8. **World geometry and navigation**  
   The MAP_PLAN bug (route through a house) and the town geometry rebalancing. Whether the current road grid (avenues 24, cross streets 22, circle ring 34) supports the intended gameplay flow.

9. **Client-server remote contract testing**  
   How to prevent the "server fires remote, client doesn't know about it" class of bugs. Whether a shared schema file or a codegen step would help.

---

## 8. Readiness Assessment

### What is ready to ship

- The data layer (ProfileStore, slots, lives)
- The stat engine (4 stats, decay, clamping)
- The aging engine (manual + auto, stage transitions, death)
- The event engine (picker, resolver, escalation, writesBack enforcement)
- The interaction grammar (3-dot prompts, ChoicePanel, EnactService)
- The person system (bond scale, decay, cap, offer fan, presence streaming)
- The debug harness (/ageup, /die, /stat, /job, /school, /gang, etc.)
- Job content (5 jobs, shift events, standing ladder)
- Gang content (4 gangs, promotion ladder, color wearing)
- World geometry generators (city, town, street, house, furniture)

### What is not ready

- Any activity verb that passes the activity design law
- The verdict/ribbon system (service exists but is not integrated)
- The chapter spine
- Childhood as a playable 3D layer
- Sports
- The lobby place (spins, slots, perks)
- Any monetization

### The single most important statement

**AGES has a simulation but no mechanics.** The simulation layer (stats, aging, bonds, jobs, crime, gangs, events) is in decent shape. The thing that is missing — and the thing the owner explicitly asked for — is *what the player is physically doing minute to minute*. The job system is an idle payout pad. School is a question-clicker. There are no verbs that pass the activity design law.

Building more simulation on top of this (more events, more ribbons, more jobs) will not fix it. The next build phase must start with the corner shop fetch-and-bag verb, then school verbs, then sports. Everything else is secondary.

---

## 9. Quick Reference: Key Numbers

| Metric | Value |
|---|---|
| Total source lines | ~60,765 |
| Server services | 44 |
| Life event modules | 12 |
| `writesBack` annotations | 144 |
| Jobs | 5 (shop_assistant, office_clerk, manager, bakery, librarian, mechanic — actually 6) |
| Gangs | 4 |
| Ribbon archetypes | ~40 |
| School subjects | 6 (spec), 1 (built) |
| Real seconds per game hour | 30 |
| Real minutes per game day | 12 |
| Auto age-up threshold (adolescent+) | 100 game hours = 50 real minutes |
| Child auto age-up | 4 game hours = 2 real minutes |
| Manual age-up cooldown | 60 seconds |
| Target life duration | 35-60 minutes |
| Target chapters per life | 6 |
| Schema version | 2 |
| ProfileStore | Vendored in `vendor/ProfileStore/` |

---

*Analysis complete. Ready for research commission.*
