# AGES gangs — decided spec

Follows crime parts 1-5 (bounty, police, theft, disguise, bank). Gangs are the next big system.

## The name is "gang", and that is checked

Researched against the **live** Roblox Community Standards, not memory. The words
"gang" and "criminal organization" appear **nowhere** in them. The only organized-crime
line is under *Harmful Off-Platform Speech or Behavior* and is about the real person
behind the account, not game content. *Terrorism and Violent Extremism* is explicitly
scoped to real-world organizations. Theft and robbery are not listed under *Illegal and
Regulated Goods and Activities* at all.

DevForum posts claiming gangs are banned cite a **retired pre-2021 ruleset**; that text
no longer exists. Live evidence: verified-badge group "The Gang Stockholm", 5.79M
members. Experiences "Gang Life" and "Gang Wars" published and unhashtagged.

There is **no "Crime and Violence" maturity descriptor** — crime is not a rated
category and only registers through **Violence**, which AGES has none of. Comparable
crime games with actual guns sit at **Moderate**. AGES lands Mild/Moderate.

I recommended renaming to "Crew" on genre-positioning grounds (the word is owned by the
Da Hood / hood-shooter cluster). **User chose "gang". Settled — do not re-open.**

Watch item: Roblox's IARC/ESRB migration is announced but not live. IARC questionnaires
*do* ask crime-specific questions. Re-run the maturity questionnaire when it lands.

## Four gangs, one per side of the city

**Deferred by the user: do not build districts yet.** The map is going to be expanded
first, and district seams must land on real streets rather than invented coordinates.
Record the intent, build the geography-independent parts now.

- Four gangs, one to a side of the city.
- Territory is markable and the whole city can be taken over.
- A **city map unlocks after joining** and displays in a special way — territory by
  controlling gang. Signposting is part of the mechanic, so the map *is* a feature and
  not a menu.

Territory must be taken **without combat**. The intended verb is marking/tagging: a
held verb, leaves a visible object in the world, rivals can cover it over. Same input,
different opponent. Not shooting people in a zone.

## The bandana — identity and liability

On joining you **automatically wear a very bright coloured head covering**, one colour
per gang, so players and NPCs are distinguishable **from afar**. This is the user's
explicit requirement and it is the backbone of the NPC/human mix in multiplayer.

The design tension to preserve: colours let your own gang recognise you **and** let
witnesses and rival gangs recognise you. It should interact with the existing
description/disguise system (`BountyService.LoseDescription`, `DisguiseService`).
Wearing colours in enemy territory should be dangerous. The bandana is both an
identity and a liability, and that is the point.

## Rank

Four rungs. Low ranks take orders, high ranks give them — at low rank NPCs run the job
and you hold the panel; at high rank you assign roles and NPC crew execute them, badly
if their nerve is low. That inversion is the progression.

| Rung | Meaning |
|---|---|
| hanger-on | You hear about a job. Cut only if you physically show up. |
| hand | Assigned one role, told what to hold. |
| name | Pick your own role, bring one person. |
| who calls it | Choose the job, the crew, and who holds what. |

Top rung capped at **one gang**, mirroring `Ties.luau`'s `limit = 1` on `closest` — the
first gang decision that costs something.

**User amendment: rank rises from a lot of things that help the gang, crime generally
— not only from shared heat.** Widen the currency accordingly.

**Promotion is conferred in a moment, never by crossing a threshold.** This is forced by
`Ties.luau`'s own argument: if it were a threshold, "everybody you were reliably nice to
would become your friend on some birthday you were not paying attention on, and the game
would be telling you about your own life after the fact." Three dots over the boss's
head, face to face, same interaction grammar as everything else.

Bailing — leaving while it is ringing and somebody is still holding — costs rank. NPC
gang members remember it, because each is a persistent cast id with a bond.

## Key implementation facts (verified, not assumed)

- `ties` **is persisted** — `Lives.luau:118`, and `Lives.Reconcile` lists it among the
  saved map-shaped fields. (A research agent claimed otherwise and was wrong.)
- New per-life fields go in `Lives.New()`; `Lives.Reconcile` fills them into old saves.
  Only fields inside `slots` need the explicit pass — ProfileStore's own `Reconcile`
  "cannot descend into a list".
- `BankService.tickRoom` already applies `HeatPerSecondRinging` to **everyone in the
  room**, not just whoever tripped it. Shared heat is therefore already computable.
- `BountyService` already has `HasRecord`, `SuspicionMultiplier`, `HiringBarMultiplier`,
  `LoseDescription`, `Seen`, `Arrest`.
- Progression precedent to copy: `jobStanding: { [string]: number }` and
  `subjectMastery` / `subjectPasses`.

## Parts

1. **The gang exists** — four gangs, joining, the four rungs, the bandana, rank rising
   from crime. Geography-independent, buildable now.
2. **NPC gang members** — spawn, nerve meter, hold assigned roles.
3. **Calling a job** — role-assignment table, commit window.
4. **Territory and the city map** — after the map expansion. Districts on real streets.

## Part 1 is BUILT (2026-08-13, commit "Standing is earned, the rung is given")

Server and client both complete, `python3 tools/check.py` clean at 122 files.
**Never opened in Studio.**

New files: `content/Gangs.luau` (the four, with require-time guards including a pairwise
color-distance check), `world/Colors.luau` (the band as welded geometry, not a
BillboardGui — a nameplate reads through walls at any range and would delete the disguise
system), `services/GangService.luau`, `client/ui/GangUI.luau` (bottom-right, the last free
corner; every activity panel is bottom-left and robbing a bank *while in a gang* is the
intended case).

- **Standing is earned, the rung is given.** `GangService.Credit(player, points, reason)`
  is the single seam; TheftService, BankService (vault opened / per-dollar / per-second of
  somebody else's alarm) and the escape check all call it. Nothing auto-promotes. The
  boss offers the rung off a panel, `takeRank` re-checks against the server's own
  `promotableTo` and compares the id so a stale panel cannot cash a rung.
- **The colors cut both ways.** `Lives.ColorsMultiplier` (1.35) multiplies all heat while
  worn, applied in `BountyService.SuspicionMultiplier` on top of the record multiplier.
  The HUD button prints the multiplier so it is never a free cosmetic.
- **Rank labels carry their own article** ("a hand", "who calls it") because three of four
  take one and the fourth does not.
- `ChoicePanel.PanelContent` gained optional `accent: Color3?` (tints the prompt label,
  applied *after* `applyStyle` so it cannot leak). The gang boss uses it for `replyGood`.
- Bosses wear their own band — applied in `spawnPost`, or they are the one thing in the
  system you must walk up to and read a nameplate to identify.
- Debug: `/gang [go <id>|join <id>|credit <n>|colors [on|off]|reset|on|off]`.
  `GangService.ForceJoin` goes through the real `join` so the rejoin window and the
  already-in-one refusal are still tested.
- **Fixed in passing:** the vault's `Commands.bank` had silently overwritten the older
  `/bank <seconds>` (two keys in one table — the second assignment just wins, no error,
  and both were listed in HELP_TEXT). The old one is now `/idle <seconds>`.

Deferred exactly as instructed: territory, districts, the city map. `side` is written
into `Gangs.luau` and read by nothing — four gangs' colors and names are a one-way door.
