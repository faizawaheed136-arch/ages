# AGES: life-sim design and retention (the verdict layer)

Researched 2026-08-08 across BitLife, InstLife, The Sims, Crusader Kings, Animal Crossing,
Stardew, Rimworld's designer writing, and the Roblox retention literature. This file covers
the layer *above* activities: what a life means, how NPCs relate, and why a player comes back.

**The single strongest finding:** build the ribbon system before building another activity.
AGES has activities and no verdict. The activities do not mean anything yet. **The verdict
*is* the loop** — it is what converts "I played some minigames" into "I was a washed-up
athlete who became a teacher." Highest ROI feature in the entire game, by a wide margin.

## Ribbons (the end-of-life verdict)

- ~**40 named archetypes**, and about **40% of them should be failure archetypes**. A life that
  ends badly must still end *named*. "Dropout," "Benchwarmer," "Estranged" are content, not
  punishment. This is the whole thesis of "failure worth playing."
- Before showing the title, **show three causal moments** — the specific decisions that produced
  it, with the age they happened at. Attribution is the entire payoff. Crusader Kings' most
  common complaint is that outcomes arrive without a traceable cause; do not repeat it.
- Ribbons are the collection meta. They are *knowledge* the player accumulates about the
  system, which satisfies the "still teaching" test across lives, not just within one.
- Show a small number of near-misses ("you were 2 seasons from All-State") — near-misses drive
  the replay far harder than the achieved title does.

## Needs and drives

- **No decaying need bars. None.** This is The Sims' named trap: bars that drain on a timer
  convert the game into maintenance chores and punish the player for engaging with content.
  Sims 4 walked this back repeatedly and it is still the most-cited complaint.
- Use **state-triggering instead of timer-draining**: a state exists (tired, broke, in trouble)
  because something *happened*, and it triggers content rather than demanding upkeep. States
  should open doors, not close them.
- **Inverse autonomy quota:** at least **one NPC-initiated interaction per 60 seconds of
  walking**. The world approaches the player, not only the reverse. InstLife's fatal flaw was
  that nothing ever happened unless you tapped it — a list of buttons is not a life.

## Event system

Schema for every event:

```
{ tags, requires, weight, cooldown, escalates_to, writes_back }
```

- **`writes_back` is mandatory.** An event that does not alter durable state is a cutscene. If
  it cannot write to a stat, a tie, a flag, or a ribbon condition, cut it.
- **Escalation chains, never cold rolls.** Follow-ups come from `escalates_to` on a prior event,
  so the player can trace the thread. A cold random event feels like weather; a chained one
  feels like consequence.
- **Repeat suppression per life** — an event fires at most once per life unless it is explicitly
  a recurring ritual.
- **1–3 events per age chapter.** More than that and no single one registers.
- **70/30 world-spawned to modal.** The majority should happen *in the world* — an NPC walks up,
  a marker appears, something changes on the street. Modal panels are the minority case, for
  things that genuinely need a decision surface. (This matches the 3-dot interaction grammar.)

## Relationships (romance-free by permanent design)

- **Bi-directional tie scale, −3 to +5.** Negative ties are content: a rival is a relationship.
- **Positives ratchet** — Animal Crossing's model. Gains stick; a friendship does not evaporate
  from neglect. Decay-on-neglect is the same maintenance-chore trap as need bars.
- Three structural slots replace romance entirely: **rivals, mentors, family.** These carry all
  the dramatic weight romance carries in other life sims, and they are age-appropriate at 13+
  forever. Rivalry in particular is the engine for sports and school.
- **NPC memory: 5 rolling + 1 defining.** Five recent interactions remembered in a queue, plus
  one permanent "defining moment" that never falls out and is quoted back at the player. Cheap
  to store, enormous perceived depth.
- **No gift-preference tables.** Stardew's likes/dislikes matrix immediately becomes a wiki
  lookup — the player stops playing the game and starts reading a spreadsheet. If gifts exist,
  they should respond to *context* (what happened recently), not to a hidden static table.

## Meta-progression

- **Horizontal only. Never starting stats.** Unlocks may add options, archetypes, starting
  situations, or knowledge — never raw power at birth. Vertical meta-progression makes the
  first life feel like a demo and invalidates every ribbon earned before it.
- **Zero gating at the door.** Everything in a life is reachable on life #1. The reason to play
  again is that you now know the system, not that the game withheld the content.

## Session shape

- Target **35–60 minutes per life**, in roughly **6 chapters of 5–10 minutes** each.
- The chapter break is the **birthday**, with a **diegetic Continue button** — the player presses
  it, the game does not simply cut. Agency at the seam.
- Between chapters, a **"months passed" reel** — and it must contain **news, not filler**: what
  changed in the world, what an NPC did without you, what your ties moved to. A reel of
  decorative slides teaches the player to skip it, permanently.

## Retention data (Roblox)

- **D1: 30–40% is good, 40%+ is excellent. D7: 8% weak / 15% good / 20% excellent.**
- **Daily rewards alone do not work.** They move a metric and not the behaviour.
- **One in-game friend by Day 5 correlates with ~3× D30.** Social hooks outperform reward hooks
  by a large margin. Even in a single-player-shaped life sim, this argues for visible
  co-presence and shared spaces.
- **The Day-3 wall** is where the curve breaks — that is when the novelty of the verb is gone
  and only the meta-loop holds. The ribbon system is the answer to Day 3.
- The most common piece of first-impression feedback on Roblox playtests, near-verbatim:
  *"raise the saturation, the game is dark as hell."* First impression is lighting, before
  anyone evaluates a mechanic. See `ages_look_and_feel.md`.

## Named traps

| Trap | Named source | Rule |
|---|---|---|
| Decaying need bars | The Sims | State-triggering, never timer-draining |
| Untraceable outcomes | Crusader Kings | Always show the three causal moments |
| Nothing happens unless tapped | InstLife | Inverse autonomy quota, 1 per 60s |
| Gift-preference spreadsheet | Stardew | No static preference tables |
| Decay-on-neglect friendship | — | Positives ratchet |
| Vertical meta-progression | roguelike drift | Horizontal only, never starting stats |
| Content gated behind lives played | — | Zero gating at the door |
| Filler transition screens | — | The reel carries news or it is cut |
| Events that change nothing | — | `writes_back` is mandatory |

## The line to keep

Apophenia is the mechanic. Tynan Sylvester's "Simulation Dream": the player assembles a story
from fragments that the simulation never explicitly authored. Our job is to supply fragments
that are *specific enough to connect* — a named rival, a named injury, a named grade — and then
get out of the way. Do not narrate the story. Emit facts and let the player write it.
