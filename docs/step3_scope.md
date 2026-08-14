---
name: AGES step 3 scope decisions
description: User-committed step 3 direction — playable toddler years, ambient world-triggered events, career branching; decided 2026-07-28
type: project
originSessionId: 66bd7d0b-841f-457a-8627-b73736f667fb
---
Decisions the user made on 2026-07-28 after play-testing step 2 in Studio.
These are commitments for Build Order step 3 (the world), not open questions.

## Playable toddler years (0–5)

Ages 0–5 must be **actually playable in 3D**, not a memory montage. The user
was offered the fork explicitly (montage vs. playable toddler) and chose
playable without hesitation: *"i want it to be a playable toddler for sure."*

**Why:** the opening five minutes should be a 3D game, not a text prologue.
It is also a genuinely distinctive opening.

**How to apply:** the childhood events in `src/server/content/LifeEvents/Childhood.luau`
are currently all `delivery = "Memory"` — framed as recollections precisely
because there was no world. In step 3 these need re-delivery as world
interactions (crawl to the object, go through the gap in the hedge). Budget a
toddler movement/interaction system; do not assume the `Memory` delivery
survives. The event *content* should stay; only delivery changes.

## Events must fire ambiently in the world

Events currently only fire on age-up (`EventService.OfferForAge` is called from
`LifeService.AgeUp`). The user wants them to **occur at random while playing,
encountered and chosen in the world** rather than arriving as a birthday
questionnaire.

**Why:** stated 2026-07-28 — *"events are only happening only when i grow up
they should happen at random in my world as i decide them."* Age-up-only
delivery makes the world a lobby between text prompts.

**How to apply:** needs an ambient trigger source (timers, proximity to NPCs
and locations) feeding the existing `EventService` selection, plus the
world-based deliveries (NPCApproach / Location / Letter / PhoneCall) as new
`EventUI` handlers. The `delivery` seam built in step 2 is the intended
extension point.

## Events advance the year — in childhood ONLY

Resolving an event advances the age by a year **during ages 0–5 only**. The
user was explicit that this rule does not generalize: *"after age 5 there will
be a lot more events so they wont be advancing years, just chaing life
choices."*

**Why:** childhood has ~10 events across 5 years, so one-event-per-year makes
exploring the cause of growing up rather than waiting on a timer. From age 6
the event count per year rises sharply, so the same rule would rocket the
player through a life.

**How to apply:** gate the advance on the childhood band. From age 6 up, events
only apply stat deltas and (later) set career/life flags. Never let an adult
event call AgeUp.

## World authored in Studio, place file committed

The house/world is hand-authored in Roblox Studio, and the `.rbxlx` place file
is committed to git as a binary blob. Decided 2026-07-28 over the alternative
of scripting geometry in the Rojo project.

**How to apply:** code must not depend on hand-placed geometry directly — bind
events to the world through CollectionService tags so the art can be rebuilt or
redressed without code changes. Claude cannot author Studio geometry; the user
does that.

## Skip Childhood is kept

Still offered on life 2+, and still bypasses the whole toddler slice.

## Career branching with uncertain success

Still committed (see ages_tone_and_direction.md). Needs requirements/flags on
`LifeEvent` — stat deltas alone cannot open and close doors.

## Relationship continuity (idea, not yet scheduled)

People chosen in an event should persist as real presences later in the life.
Raised 2026-07-28: *"if i make a decision for a friend then there should be a
friend for me when i go to school that type or in my neighbourhood, we'll do
that whenever u want."*

**Why:** without it, a choice about a person is a one-off stat delta and the
world stays anonymous. Continuity is what makes an early decision feel like it
mattered years later.

**How to apply:** needs persistent relationship records in `ProfileData` (who,
how you met, standing), events able to both create and require them, and NPC
spawning in the world driven by that record. It shares the flags/requirements
machinery already identified for career branching — build them together, not
twice. The user explicitly deferred timing ("whenever u want"), so raise it as
an option rather than assuming it is next.

## Events are scenes, not memories with floor markers (decided 2026-07-29)

The user was given an explicit fork after play-testing enacted events and chose
**scenes**: an event brings its subject into the room and you act on it. Their
words: *"i acctually want to be able to do the events like it said shout at the
dog a dog should come and i want to shout at it."*

The fork offered was (A) scenes — toddler events become things that happen to
you, costing a rewrite of the childhood content's voice — versus (B) keep the
memories and add actors only where an event is already present-tense. They chose
A, reasoning *"because we'll be able to with events later"* — i.e. the actor
machinery pays off across all later life stages, not just childhood.

**Why this matters:** enacted events (shipped 113b3e5) moved the choices off a
panel and onto discs on the floor, but a disc labeled "Put your hand out" is
still a label you read. `childhood_big_dog` is the case that exposed it — its
prompt says *"There is a dog... it has noticed you"* and no dog exists.

**How to apply:** three layers, and they stack — (1) actors: an event can bring a
subject into the room, reusing NPCService's existing spawn/approach/cleanup;
(2) choices anchored to the subject rather than fanned around the player, with
the fan kept as the fallback for events with nothing to anchor to;
(3) performance: taking a choice plays an animation and the subject reacts, so
arriving somewhere is not mistaken for doing something.

21 of the 22 childhood events are `delivery = "Memory"` with past-tense outcomes
("You have liked dogs unconditionally ever since"). Converting to scenes means
those outcomes change voice — that is content work, not a code feature, and it
should follow the machinery being proven on one event rather than lead it.
