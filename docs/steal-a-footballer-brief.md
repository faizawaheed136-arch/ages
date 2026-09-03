# STEAL A FOOTBALLER — build brief

You are building a Roblox game called **Steal a Footballer**. This document is the complete
specification. Build it in the order given. Every number here is a starting value chosen to make
the loop work; they are tuned, not arbitrary, and the reasoning is attached so you can retune
rather than guess.

---

## 0. THE ONE-LINE PITCH

You collect footballers onto pedestals in your base. They generate cash every second. Better
footballers generate more. **Everyone else can walk into your base and carry one out.**

The theft is the game. Collection alone is idle; theft is what makes a player check their base,
defend it, and come back tomorrow.

---

## 1. NON-NEGOTIABLE CONSTRAINTS

### 1.1 The roster is original characters, not real footballers

**Do not use real players' names, faces, numbers, or club kits.** Real footballers are real
people with aggressively licensed image rights, and Roblox moderates real-person likenesses.
A game that ships with "Messi" in it is a takedown waiting to happen.

Use football **archetypes** instead. They read as footballers without being anyone:

| Tier | Names |
|---|---|
| Common | The Trialist, Sunday Leaguer, Bench Warmer, The Kit Man |
| Uncommon | Set-Piece Specialist, Left-Back Lightning, The Utility Man, Long-Throw Merchant |
| Rare | The Playmaker, Target Man, Sweeper Keeper, The Enganche |
| Epic | The Maestro, Golden Boot, The Wall, Box-to-Box Engine |
| Legendary | The Free-Kick King, Cannon, The Libero, Ballon Bandit |
| Mythic | Total Football, The Invincible, Golden Generation |
| Icon | Number 10 Eternal, The GOAT |

Keep the roster in **one data module**. If real-player licences are ever obtained, swapping the
roster must be a change to that file and nothing else.

### 1.2 The server is the only authority

Every value that matters lives on the server and is never accepted from a client:

- Cash balance, and every change to it
- Which units a player owns, and their tiers
- Whether a steal succeeded
- Income accrual

The client sends **intent** ("I want to buy the unit on conveyor slot 3", "I want to start
stealing pedestal 5"). The server decides what that means. A remote that accepts a *price*, a
*value*, or an *amount of cash* from the client is a remote that will be used to mint money on
day one.

---

## 2. THE ECONOMY

This is the part most builds get wrong. The numbers below form a working curve; change them
together, not individually.

### 2.1 Tiers

Seven tiers, each **3.5×** the last. Income per second is **value ÷ 100**, so any unit pays back
its own purchase price in 100 seconds of ownership — long enough that buying is a decision, short
enough that it always feels worth it.

| Tier | Value | Income / sec | Conveyor odds | Steal hold |
|---|---:|---:|---:|---:|
| Common | 250 | 2.5 | 55% | 2.0 s |
| Uncommon | 875 | 8.75 | 25% | 2.5 s |
| Rare | 3,060 | 30.6 | 12% | 3.0 s |
| Epic | 10,700 | 107 | 5% | 4.0 s |
| Legendary | 37,500 | 375 | 2% | 5.5 s |
| Mythic | 131,000 | 1,310 | 0.8% | 7.0 s |
| Icon | 460,000 | 4,600 | 0.2% | 10.0 s |

**Steal hold** is how long the thief must stand at the pedestal holding the key. It scales with
value so that stealing an Icon is a genuine commitment — ten seconds standing still in someone
else's base is long enough for them to run back and stop you.

### 2.2 Why 3.5× and not 2×

At 2× per tier, seven tiers span 64×, and a Legendary is a mild upgrade over an Epic. At 3.5×
they span 1,838×, so each tier up is an event. That is what makes a rare drop feel like a rare
drop, and it is what makes theft worth the risk.

### 2.3 Opening state

- Player starts with **$500** and **one free Common** already on a pedestal.
- First purchase is therefore affordable immediately, and income is non-zero from second one.
- A fresh player with 8 Commons earns **$20/s**; a Rare is 2.5 minutes away. That is the intended
  early pace.

### 2.4 Conveyor

- One unit spawns every **12 seconds** and travels a loop past every base.
- Rolled against the odds table above. An Icon therefore appears roughly **once every 100
  minutes** server-wide — rare enough to be talked about, common enough to exist.
- A unit not bought within one full loop **despawns**. Otherwise the conveyor silts up with
  Commons nobody wants.
- The price a player pays is the unit's **Value**.

### 2.5 Base upgrades

| Upgrade | Effect | Cost |
|---|---|---|
| Pedestal 9–16 | +1 slot | `5,000 × 2.2^(n-8)` |
| Vault Lock | 60 s of immunity, 5 min cooldown | 10,000 |
| Scout | Alerts you to a thief 3 s earlier | 25,000 |
| Sponsorship I–V | +10% income each | `40,000 × 3^(level-1)` |
| Boots I–III | +8% walk speed each | `15,000 × 2.5^(level-1)` |

---

## 3. THE STEAL

### 3.1 Rules

1. Walk into another player's base and hold **E** on an occupied pedestal for that tier's hold
   time. Moving out of range cancels it — no progress is kept.
2. On success the unit becomes a **carried object**. It is visibly attached to the thief.
3. While carrying: walk speed **× 0.55**, sprint disabled, and a **server-wide marker** shows the
   thief's position. Carrying an Icon should feel like carrying a bomb.
4. The owner receives an alert with a **compass arrow** to the thief.
5. If the owner touches the thief, the unit **drops and returns home** after 3 seconds on the
   ground. Anyone else may pick it up in that window.
6. Reaching your own base with it places it on a free pedestal. If you have none free, you cannot
   steal — check this **before** the hold starts and say so in the prompt text.

### 3.2 Protection

- **New-player grace:** 10 minutes of immunity from first join. Non-negotiable — a player robbed
  in their first two minutes does not come back.
- **Vault Lock:** purchased, 60 s, 5 min cooldown.
- **Per-base cooldown:** a base cannot be stolen from more than once per **90 seconds**, by
  anyone. This stops a group farming one player into the ground.
- **Per-thief cooldown:** 25 s between successful steals.
- **Offline bases are stealable.** This is the genre and removing it removes the tension — but it
  is why the grace period and the per-base cooldown exist.

### 3.3 Server-side state machine

The steal must be a server-owned state machine. The client sends `RequestSteal(pedestalId)` and
nothing else. The server:

1. Validates the pedestal is occupied, not the thief's own, not grace-protected, not locked, and
   both cooldowns have elapsed.
2. Validates the thief has a free pedestal.
3. Starts a timer, and **re-checks the thief's distance to the pedestal every 0.25 s**. Out of
   range at any check cancels it.
4. On completion, transfers ownership atomically and starts the carry.

Never run the hold timer on the client and trust its completion message.

---

## 4. THE WORLD

A floodlit stadium at night. A pitch in the middle, bases ringed around it, the conveyor running
the loop between them.

| Element | Studs | Note |
|---|---:|---|
| Central pitch | 120 × 80 | Cosmetic and the social space. Players meet here. |
| Conveyor loop | 8 wide | Runs between the pitch and the bases, passing every one. |
| Plot | 90 × 90 | Eight of them, ringed. |
| Plot wall | 12 high | Open front. Ownership must read at a glance. |
| Pedestal | 6 × 4 × 6 | Two rows of four, positions **derived by dividing the plot span**, never at a fixed pitch — a fixed pitch breaks silently when the plot or slot count changes. |
| Walkway | 20 wide | Between plots and the conveyor. |

**Scale rules that come from the engine, not from taste:**

- An R15 avatar is **5 studs** tall. A jumping avatar's head reaches **12.2** — so no ceiling
  under 14.
- The third-person camera sits about **12.5 studs behind the head**, so any corridor under
  ~16 wide makes the camera collide with walls and force-zoom. That, not the body, is why the
  walkway is 20.
- A humanoid climbs a **2-stud** rise without jumping. Every step and kerb is 2 or less.

`Workspace.StreamingEnabled = true` — this is a big world with many players.

---

## 5. SYSTEMS TO BUILD

Use Rojo with a `default.project.json`, source as `.luau` files in `src/`, and never edit models
by hand in Studio where a script could lay them instead.

```
src/
  shared/
    Roster.luau         the seven tiers and every unit. One table. The only place a value appears.
    Economy.luau        income maths, upgrade costs, the odds table
    Remotes.luau        one place that creates and names every RemoteEvent
  server/
    PlotService.luau    assigns a plot on join, releases it on leave
    IncomeService.luau  the income tick
    ConveyorService.luau spawning, travel, despawn, purchase
    StealService.luau    the state machine in 3.3
    SaveService.luau     persistence
    UpgradeService.luau
  client/
    HudUI.luau          cash, income/sec, pedestal count
    AlertUI.luau        the thief compass
    ShopUI.luau         upgrades
    CarryUI.luau        what you are holding and how far home is
```

### 5.1 The income tick

**One loop for the whole server, not one per player and never one per unit.**

```lua
-- Once a second, walk the plots and add. Sixty units on eight plots is 480 additions a second,
-- which is nothing. A `while true do task.wait(1) end` inside each unit is 480 coroutines, which
-- is a frame-rate problem you will blame on rendering.
while true do
    task.wait(1)
    for player, plot in activePlots do
        local perSecond = 0
        for _, unit in plot.units do
            perSecond += unit.income
        end
        addCash(player, perSecond * plot.sponsorshipMultiplier)
    end
end
```

Accrue on the server. Push the balance to the client for display only.

### 5.2 Persistence

Use **ProfileService** (or DataStore with explicit session locking). Save:

- cash
- owned units: `{ tier, unitId, slot }`
- upgrade levels
- lifetime stats: earned, stolen, been-stolen-from

Save on leave, and every **120 s** as insurance. Session-lock so two servers cannot write the same
profile — without it a player joining two servers duplicates their entire base.

### 5.3 Data shape

Put the unit's tier and value in **Attributes** on its model, not in a name-parsing scheme:

```lua
model:SetAttribute("UnitId", "playmaker")
model:SetAttribute("Tier", "Rare")
```

Find pedestals, plots and conveyor slots with **CollectionService tags**, never by path. Tagged
geometry can be moved, rebuilt or re-laid without touching a line of code.

---

## 6. BUILD ORDER

Build in this order. Each step must be **playable** before the next begins.

1. **A plot, a pedestal, a unit, income, and a cash counter.** No conveyor, no stealing. One free
   unit placed on join. If watching a number rise is not satisfying here, no amount of theft
   will save it.
2. **The conveyor and buying.** Now there is a decision: save or spend.
3. **Stealing.** The game becomes a game. Grace period and both cooldowns from day one, not
   later — they are load-bearing, not polish.
4. **Persistence.** Everything before this is disposable; after it, players have something to
   lose.
5. **Upgrades.** Pedestals first, then Sponsorship, then the rest.
6. **Polish.** Sounds, the carry marker, rarity beams, a leaderboard.

---

## 7. FEEL, WHICH IS MOSTLY SOUND AND TIMING

- **A rarity reveal needs a beat.** When a Legendary or better spawns on the conveyor, hold a
  half-second before the name appears. Instant reveals read as a list; a beat reads as an event.
- **Announce Mythic and Icon server-wide.** Rare things must be seen to be rare, or nobody
  believes the odds.
- **Cash is a sound, not a number.** A soft tick when income lands makes an idle game feel alive.
- **The steal alert must be loud and directional.** If the owner cannot tell where the thief is
  within a second, defending is impossible and the mechanic is just tax.
- **Every ProximityPrompt gets `RequiresLineOfSight = false`.** A prompt that flickers as someone
  walks between you and it reads as broken.

---

## 8. THINGS THAT WILL GO WRONG

Listed because each has a cheap fix known in advance.

| Failure | Fix |
|---|---|
| Client sends its own cash total | Server holds the balance; the client is told, never asked |
| Income runs per-unit in coroutines | One server loop over plots |
| Two servers write one profile | Session-locked ProfileService |
| Steal timer completes on the client | Server timer with a distance re-check every 0.25 s |
| A thief steals with no free pedestal | Check before the hold starts, and say so in the prompt |
| Pedestals at a fixed pitch break on resize | Derive positions by dividing the plot span |
| A new player is farmed in their first minute | 10-minute grace, 90 s per-base cooldown |
| Conveyor fills with unsold Commons | Despawn after one full loop |
| Real footballer names | Original archetypes, roster in one table |

---

## 9. WHAT TO HAND BACK

- A Rojo project that builds
- Every system as a module with a `Start()` function, called from one bootstrap
- A short note on any number you changed and why
- A list of anything you stubbed, with the exact failure mode it causes while stubbed —
  placeholder asset ids that make a system run **silently** are the most expensive kind of
  incomplete work, because they look identical to a bug
