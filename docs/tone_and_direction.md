---
name: AGES creative direction and tone
description: The tone and life-shape AGES is aiming for — all audiences, US English, branching careers with uncertain success (committed to step 3), consequence-free living
type: project
originSessionId: 66bd7d0b-841f-457a-8627-b73736f667fb
---
AGES should read for **all audiences**, not a narrow demographic.

A life should be able to branch into genuinely different shapes — a
sportsperson, an average worker, a doctor, a famous musician — and **success is
never guaranteed** in any of them. The pitch is a game that embodies life while
letting the player live without the consequences a real life would carry:
failure should be interesting to play, not punishing.

**Why:** stated by the user on 2026-07-28 when reviewing the step 2 event
content. They confirmed the existing tone was on track ("i dont think ur
deviating as of yet") — warm, concrete, specific, slightly wry, second person.

**How to apply:**
- **Write in US English.** Directed on 2026-07-28 after the first content pass
  came out unmistakably British (stabilisers, direct debit, biscuit, queued up,
  revise, sandpit, garden). This is a concrete instance of "all audiences" —
  avoid region-specific vocabulary and idiom generally.
- Failure branches must be worth playing, not dead ends or pure stat punishment.
  Death is a restart, not a loss condition.
- Keep it 13+ appropriate: no combat, gambling or gore.

## The "success portion" — an explicit step 3 commitment

The user deferred career branching to Build Order step 3 but asked directly
that it be remembered: *"we'll do that in step 3 like the success portion... but
we can tackle that in step 3 just remember it though."* Treat this as a
standing commitment, not a maybe. Raise it when step 3 planning begins.

**Why it is deferred rather than dropped:** it needs the world (step 3) to
deliver it, and it needs engine work the step 2 schema cannot express.

**How to apply:** career paths need events that *open and close doors*, which
stat deltas alone cannot represent. Expect `LifeEvent` to need
requirements/flags (prerequisite state, unlocked/locked branches) before
doctor / musician / athlete lines are possible. Do not try to fake branching
with stat thresholds alone.
