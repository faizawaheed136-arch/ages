---
name: AGES interaction grammar — overhead prompt, not floor pads
description: For ~/ages, choices are made via a three-dot indicator above a character's head that opens an options menu, NOT by walking onto pads on the floor
type: feedback
originSessionId: bf0a63c9-3916-48e6-81ef-c515f6d16a35
---
Player choices in AGES are presented as **a three-dot indicator floating above the
character's head; you interact with it and the options come up** — the interaction
style of well-made Roblox games. This replaces the earlier floor-pad grammar, where
choices were discs on the ground the player walked onto.

**Why:** stated by the user on 2026-08-01, in their words — "instead of places on the
floor to walk on, make the mechanic more appealing like 3 dots over each characters
head and then the options come up like good roblox games, thats what we want."

They drew an explicit line in the same message: *"i can change the graphics and
animations later but not that type of hard coding stuff."* Cosmetics (models, textures,
animations) are theirs to swap later and should not be over-invested in. **Interaction
architecture is not something they can change later**, so it has to be built correctly
now rather than approximated.

**How to apply:**
- One interaction grammar across the whole game — person offers, event choices, lesson
  answers. Two grammars living side by side is worse than either.
- Beware: a lot of code comments in the repo argue *for* the floor pads ("the decision
  is being made with your feet", "the player watches the floor get more generous").
  That prose is now wrong. Rewrite it when touching those files rather than leaving
  the codebase arguing against its own design.
- Do not read this as "menus are fine everywhere". The physicality the user wants is
  still real — the dog still walks up to you, the person still stands in a place you
  travelled to. What changed is how the *choice* is taken once you are there.

**Related preference — realism over determinism.** In the same message the user chose
a chance of refusal for the relationship system over a guaranteed yes, because "its
more realistic". When a design fork is realism vs. tidy determinism, expect them to
pick realism.

**A choice that names a physical act must produce that act, not just prose.** Stated
2026-08-26: "even in normal chat windows, if ur option is to put ur hands up or to push
someone, that action should automatically take place" — and, in the same message, about
the lab: "if ur options are to mix 2 things and it says could cause an explosion, a
small explosion should happen." Choosing an option is already physical under this
grammar (you walked up, the dot opened, you picked a row) — this extends the same idea
to the *outcome*: an option whose label is a literal physical verb should cause that
verb to visibly happen in the world, not only resolve to `outcome` text and `effects`
numbers.

The lab is the concrete, built example: `ProcedureStep.volatile` (Types.luau) plus
ScienceService's `commitBench` is a physical-act choice with a physical-act result —
reach for the wrong station at the wrong point and a real, cosmetic-only explosion goes
off at the bench, not just a worse score and a sentence about it.

Checked at the time this note was written: no `LifeEvents/*.luau` choice anywhere in
the content actually reads as a literal physical act today. The closest hits
(`Crime.luau`'s `push` — "push back and insist you are qualified", `Gym.luau`'s
`push_through`) are verbal or metaphorical, not "shove another person" or "raise your
hands", so there is nothing existing to retrofit yet. Treat this as authoring guidance
going forward rather than a backlog of choices to fix: the day a life event's option
label is a real physical verb, it needs a real effect (an animation, a prop moving, a
Townsfolk NPC reacting) the same way the lab's does — not a generic "physical choice"
framework built ahead of any content that needs it, which is exactly the
undifferentiated-outcome trap `ProcedureStep`'s own doc comment warns against.
