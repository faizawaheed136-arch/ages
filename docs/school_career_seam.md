# School → Career seam spec

**Agreed between Agent B and Agent C. One decision, not ongoing contact.**

## What exists today

- `LifeData.subjectMastery: { [string]: number }` — per-life, per-subject, level number.
  Populated by SchoolService, reset on death.
- `SchoolSubjectId = "science" | "math" | "reading" | "art" | "music" | "geography"` —
  locked to the six subjects on the timetable.
- `Job` has `minSmarts` (the only stat gate) and `requires` (prerequisite job + standing).
  No job reads `subjectMastery` today.
- Current career branches are all standing-based: shop → office → manager, bakery →
  librarian → clinic / mechanic → gym. Smarts gates separate the "diligent school"
  track from the "practical hands" track within each branch.

## What the seam needs

C builds the subjects. B builds the careers. The subjects need to *matter* to the
careers — not as a replacement for `minSmarts` (which measures the childhood as a
whole) but as a way for each subject to open a specific door that standing alone
cannot. This is the "subject XP gates careers" line from the school plan, and it is
what makes school feel like a detour rather than the main road.

## The agreed shape

### 1. A `subjectGates` field on Job

```lua
export type Job = {
    -- existing fields ...
    --
    -- Which subjects must be cleared to open this job, and to what level.
    -- Nil means the job does not care about school beyond `minSmarts`.
    --
    -- A subject is not a stat — it is a ladder. Clearing level 5 means
    -- you have pushed that subject past its max, which makes it optional
    -- forever and leaves a passive perk (see SubjectPerks below). A gate
    -- at level 3 says: this job wants somebody who has spent time at it,
    -- not somebody who just happened to have a high smarts bar from
    -- sitting every lesson.
    --
    -- Multiple entries are OR, not AND. A player who cleared either
    -- science or geography has done something relevant here; both is
    -- better but neither is a hard requirement.
    subjectGates: { [SchoolSubjectId]: number }?,
}
```

### 2. WorkService reads it alongside `minSmarts` and `requires`

In `hireRefusalFor`, after the `minSmarts` check (or alongside it, order does not
matter — they are independent gates), add:

```lua
local subjectGates = job.subjectGates
if subjectGates ~= nil and not SubjectGatesCleared(data, subjectGates) then
    return `This desk wants experience in {subjectGatesList(subjectGates)}.`
end
```

`SubjectGatesCleared` is a small helper:

```lua
local function SubjectGatesCleared(data: LifeData, gates: { [SchoolSubjectId]: number }): boolean
    for subjectId, level in gates do
        if (data.subjectMastery[subjectId] ?? 0) >= level then
            return true
        end
    end
    return false
end
```

The refusal text names the subjects, not the numbers — the player has seen them on
their report card and will recognise the names even if they do not know their own
levels.

### 3. SubjectPerks table in Config

When a subject reaches level 5 (cleared), the life gets a small passive that is
consulted when a job reads `subjectMastery`. This is where C declares what each
subject *feeds*:

```lua
SubjectPerks = {
    science = {
        description = "You understand procedures. Jobs that ask for method feel easier.",
        -- Applied as a reduction to minSmarts on jobs that have both minSmarts and science gates.
        -- Not a flat number — it scales with how far past level 5 the life is.
        smartsBonus = 5,
    },
    geography = {
        description = "You know where things are. The world feels smaller.",
        -- Future: could affect walking speed or place-point discovery. No job gate today.
        smartsBonus = 0,
    },
    art = {
        description = "You see colour and shape. Jobs that ask for an eye take less time.",
        smartsBonus = 3,
    },
    -- math, reading, music: no perks yet. Their verbs are still quiz stubs.
},
```

B consumes `SubjectPerks` — C defines them.

## What C must decide and hand over

For each subject that has a real verb (procedure, copy, hunt), C specifies:

1. **Which careers it gates** — the job ids and the level required (usually 3 or 5).
2. **What perk it leaves at level 5** — the `smartsBonus` number and a one-line
   description.
3. **What verb the quiz stubs get** — math, reading, and music still read
   `verb = "quiz"` in Curriculum.luau. Until they get a real verb, their mastery
   cannot gate anything meaningful (a quiz-level number is noise, not a signal).
   C should either build those verbs or declare that those three subjects remain
   general-purpose smarts-feeders and do not get subject gates at all.

The output C hands to B is a table — one per subject with a real verb — that looks
like:

```lua
-- From C to B. One agreement, not ongoing.
SubjectCareerMap = {
    science = {
        gates = { "doctor", "engineer" },
        level = 3,
        perk = { smartsBonus = 5, description = "Procedures come naturally." },
    },
    geography = {
        gates = { "journalist", "architect" },
        level = 3,
        perk = { smartsBonus = 0, description = "You know the town." },
    },
    art = {
        gates = { "illustrator", "designer" },
        level = 3,
        perk = { smartsBonus = 3, description = "An eye for detail." },
    },
}
```

B takes that table and writes the `subjectGates` fields into the relevant jobs in
Jobs.luau.

## What B must write

1. Add `subjectGates: { [SchoolSubjectId]: number }?` to the `Job` type in Types.luau.
2. Add `SubjectGatesCleared` helper and the gate check inside `hireRefusalFor` in
   WorkService.luau.
3. Add `Config.SubjectPerks` (or consume C's table directly — either shape is fine
   as long as it lives in Config or is importable).
4. Update the subject names in refusal text so they render as the human-readable
   name from Curriculum (e.g., "Science" not "science").

## What does not change

- `minSmarts` stays. It measures the childhood. A job can have both `minSmarts` and
  `subjectGates` — that is the common case, not the exception.
- `requires` stays. Standing at a previous job is still the primary ladder mechanism.
- Subject mastery is still per-life, reset on death. It is not a global trait.
- The six `SchoolSubjectId` values stay locked to the timetable. Adding a subject
  is a Curriculum entry; gating a new career off an existing subject is a one-line
  change to a Job table.

## Verification

After B lands the change:

1. A life with smarts 70 but zero subject mastery can apply for a job with only
   `minSmarts` — hired.
2. A life with smarts 55 but science level 3 can apply for a job with
   `minSmarts = 50` and `subjectGates = { science = 3 }` — hired.
3. A life with smarts 70 but zero subject mastery cannot apply for a job with
   `subjectGates = { science = 3 }` — refused with a text naming the subject.
4. A life with smarts 50 and science level 5 gets the `smartsBonus` from
   `SubjectPerks.science` applied when the job also has `minSmarts`.
5. Gate: `python3 tools/check.py` — `all clean`.

## Open questions (answer before building, do not implement now)

- Do quiz-stub subjects (math, reading, music) get subject gates once their verbs
  are built, or do they remain general smarts-feeders only? **C decides.**
- Is the OR logic (any one gate clears) or AND (all listed gates must clear)?
  **Agreed: OR.** A player who specialised in one subject should not need to
  specialise in all of them.
- What happens if a job has both `minSmarts` and `subjectGates` and the player
  clears the subject gate but not the smarts bar? **Refused on smarts, as today.**
  The gates are independent.
