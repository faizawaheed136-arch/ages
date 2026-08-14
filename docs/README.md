# Design decisions

These are the settled decisions behind AGES. They were made in conversation over
several weeks and used to live only in one machine's local assistant memory, which
is gitignored — so a second machine, or a second person, had no way to read them.
They are in the repo now because a decision nobody else can see is a decision that
gets re-litigated, or quietly broken, by the next person to touch the code.

**Read these before proposing a feature.** Most of them exist because something was
built, rejected, and rebuilt. The rejections are the valuable part, and they are
written down here rather than in anybody's head.

## Start here

| File | What it settles |
|---|---|
| [`mechanics_first.md`](mechanics_first.md) | Bias every part toward what the player physically *does*. Signposting is part of the mechanic; idle time inside an activity is a bug. |
| [`activity_design_law.md`](activity_design_law.md) | The seven requirements every activity must pass, the anti-pattern table, and why the job system is still an idle payout pad. |
| [`interaction_grammar.md`](interaction_grammar.md) | Choices are a three-dot prompt above a character's head, not floor pads. Floor markers are for destinations only. |
| [`tone_and_direction.md`](tone_and_direction.md) | All audiences, US English, failure worth playing. |

## Systems

| File | What it settles |
|---|---|
| [`lifesim_design.md`](lifesim_design.md) | The ribbon/verdict layer as the highest-ROI feature. No decaying need bars, inverse autonomy, ties without romance, horizontal-only meta. |
| [`school_and_sports.md`](school_and_sports.md) | One distinct verb per subject, a mastery ladder that buys the right to skip, and the charge-and-release input spec. |
| [`school_sports_plan.md`](school_sports_plan.md) | The ordered build queue for the above — eight phases, and the seams where it touches the other two agents. |
| [`gangs_spec.md`](gangs_spec.md) | Four gangs, one per city side; bright per-gang bandana; a four-rung ladder conferred face to face. Territory and the city map are deferred. |
| [`lobby_spec.md`](lobby_spec.md) | Separate lobby place, Robux spins with numeric odds, three deletable slots, real avatar on screen. Settled — do not re-open. |
| [`economy_direction.md`](economy_direction.md) | Currency arrives with the world in step 3. Paid revives were rejected, and why. |
| [`step3_scope.md`](step3_scope.md) | Playable toddler years, ambient world-triggered events, career branching. |

## Craft

| File | What it settles |
|---|---|
| [`look_and_feel.md`](look_and_feel.md) | The 2025 lighting reset, PBR/atmosphere/post baselines, the game-feel timing table, easing curves. |
| [`roblox_engineering.md`](roblox_engineering.md) | Server Authority, sports as a third place, remote/buffer costs, network-ownership traps, engine caps, CI tooling. |

## Two rules that override everything here

**13+ is a hard ceiling.** Any feature that would push the game to 17+ is off the
table permanently, not deferred. This is why there is no dating system: a romantic
partner is the one relationship the game cannot write and stay 13+. The tie ladder
stops at `known` → `friend` → `closest friend`. If the top rung ever grows, it grows
into something a 13+ life can hold — a mentor, a rival, a sibling you chose.

**Combat is allowed.** What the rating forbids is gore, not fighting: no blood, no
dismemberment, no realistic injury, no death animation that dwells. A fight is a
contest with a winner, and it ends with somebody on the floor and back up again.

## A note on staleness

These files were written at different times and some describe intentions rather
than shipped code. Where a document and the code disagree, the code is what exists
— but the document is what was *agreed*, so the gap is a bug or an unfinished job,
not permission to do something else. If you find one, say so.

`MAP_PLAN.md` in the repo root is the live status of the world build and supersedes
any world description in here.
