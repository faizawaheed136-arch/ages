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
