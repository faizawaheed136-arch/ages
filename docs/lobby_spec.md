---
name: AGES lobby and menu — decided spec
description: The user's answers on the Shindo-Life-style lobby (separate place, Robux spins, numeric odds, 3 deletable slots, avatar on screen). Read before touching the lobby, slots, spins, codes or perks.
type: project
originSessionId: 410bd256-49f4-462a-aeb1-eed6143b340e
---
Decided 2026-08-05, in one message, after the user rejected the setup card being the whole
front end: *"no i want the menu to be a seperate screen which allows u to load into the
game, change ur character into a different life one, use codes, spin power ups stuff like
that, look at the one in shindo life its amazing... something that captivates ppl from the
get go."* Then they answered every open question at once and said **"jus rmr all of this,
and make no mistakes."** These are settled. Do not re-open them; build to them.

## Settled — these overrode my recommendations

- **Separate lobby place with TeleportService.** I recommended one place with a parked
  camera; the user chose two places explicitly — *"it would make life much easier for later
  updates."* They are right about decoupling. Two Rojo project files, shared code shared.
- **Spins are buyable with Robux.** I recommended never-purchasable on gambling grounds and
  the user overrode it. It is their game and Roblox supports it natively via developer
  products. **Do not re-argue this.** Two things it obliges, technically: Roblox requires the
  odds of a paid random item to be **disclosed before purchase**, and paid random items are
  restricted from under-13 accounts — AGES is 13+ so the audience matches, but the purchase
  path still has to handle a rejected purchase gracefully rather than assuming it succeeded.
- **Odds are shown as numbers**, not words. This deliberately breaks grammar with the
  refusal system (which shows social odds as words — "a long shot"). That split is
  defensible and intended: a purchase needs disclosed numbers, a social risk reads better as
  a phrase. Do not "unify" them.
- **3 life slots for now, with a delete option.** Delete is destructive and irreversible, so
  it needs a real confirmation, and it must be idempotent.
- **The player's actual Roblox avatar stands on the lobby screen**, Shindo Life style. Note
  it must be their *real* avatar at full size — not run through `Config.Growth` / BodyService,
  which resizes bodies by in-game age.
- **The scene must be a composed, "amazing" set piece**, not the player's spawn point.
- **Build order is mine to choose.** User: *"u can start in wtvr order works best for u."*

## Perks — the shape to build for

"Born into" was approved as the *lead*, not the whole thing: *"born into is a good lead but
for other powerups money boost and stuff like that is good too we could add that later."*

So the perk type must be **general from day one** — an effect-kind union where a birth
circumstance is one kind and a multiplier (money boost, etc.) is another. Author only birth
circumstances now, but do not hardcode "birth circumstance" into the type or the spin will
need reworking the day the first boost is added.

Approved sketch, rarer deliberately **not** stronger (it is a better story, not a buff —
this is what keeps it from being a stat lottery and it is the "failure worth playing" line):
common ordinary start · uncommon born abroad / a knack / a big family · rare born into money
/ a family already coming apart / raised by one grandparent · legendary a twin / born famous
/ born with nothing.

## The bug to fix on day one, by name

The user singled this out: *"also fix the issue u said that shouldn't show up weeks later."*

**ProfileStore's `Reconcile` cannot reach inside an array.** With lives stored as
`slots: {Life}`, the day a new per-life field is added, every already-saved slot loads back
missing it — no error, just nil where a number should be. **Write an explicit per-slot
reconcile that runs against a life template on load, before any slot work ships.** Not later.

## Standing constraint that still applies

13+, no combat/gore. The no-gambling line was overridden *for spins specifically* and for
nothing else.
