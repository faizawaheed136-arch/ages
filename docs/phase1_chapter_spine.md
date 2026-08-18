# Phase 1 — the chapter spine (SPEC)

**Status:** proposed, awaiting owner sign-off before any code lands.

This is the spec for the *frame* the rest of the life layer hangs on: six chapter
bands, a birthday seam, a shared "what happened" query, and a news-driven reel.
The plan is in [`life_layer_plan.md`](life_layer_plan.md). The design is in
[`lifesim_design.md`](lifesim_design.md). **The design wins on disagreement.**

---

## 1. What I am building, in one sentence

A life is six age bands of 5–10 minutes. The seam between bands is a birthday
moment the player presses Continue on. The screen between bands is a "months
passed" reel that lists what changed in the world, in a single shared query that
the end-of-life verdict also speaks. The reel is suppressed when the query is
empty — a slide deck teaches the player to skip the reel permanently.

## 2. The six chapter bands

The bands are a *player experience* decision, not a calendar one. I am choosing
them on three criteria together: (a) roughly 5–10 minutes per band at playtest
walking pace, (b) age-of-decision matches what the design locks in
(lifesim_design.md lines 33–35: events ambient 0–5; events only fire ambiently
from age 6; from 6 up, no event advances the year), and (c) the band ends on a
narrative turn the player can feel without being told.

| # | Band   | Ages  | Approx minutes | What changes at the seam                                              |
|---|--------|-------|----------------|-----------------------------------------------------------------------|
| 1 | Infant | 0–4   | 4–6            | First chapter. World is home + garden. Bond formation with one NPC.    |
| 2 | Child  | 5–9   | 5–7            | School begins. A rival/mentor slot opens. Year advances per event.    |
| 3 | Tween  | 10–14 | 6–8            | Sports verbs land. First job verb candidates. Bond ceiling matters.   |
| 4 | Teen   | 15–19 | 7–9            | Standing / mastery systems engage. Career gates start to bite.        |
| 5 | Adult  | 20–39 | 8–10           | Longest band. Houses, jobs, crime, family slots. Most of life lives.   |
| 6 | Elder  | 40–80 | 5–7            | Reflection band. Verdict pre-loads as ribbons get visible in HUD.      |

**Total:** 35–57 minutes per life, inside the design's 35–60 window.

**Why not birthday-every-year:** the design's own rule says no event advances
the year after age 5. If chapter breaks were yearly the bands would each be
exactly one band — the reel would be the only variation. Bands are the
variation. Year markers inside a band are *fact cards* in the reel, not seams.

**Why six and not four or eight:** four bands would force >12-minute stretches,
which is past the DevForum retention threshold for "a single sitting" inside
a young-audience game. Eight bands would put seams under five minutes apart,
which the design explicitly rejects ("the chapter break is the birthday" — the
*seam is the feature*, density matters).

**Why a 20-year adult band:** this is where the verbs accumulate. A player who
buys a house at 22 and commits a crime at 25 needs both visible at age 40. A
five-year band would erase the second from the reel at 30.

## 3. The shared "what happened" query

**One query, two consumers.** A life has moments. The verdict picks three
chronologically-anchored moments that *caused* the verdict (a flag set, a
bond crossing, a grade earned, a job held). The reel picks every moment since
the last chapter break. Both are answered by the same function:

```lua
function LifeService.Moments(data: LifeData, opts: {
    sinceMonths: number?,    -- nil = whole life
    untilMonths: number?,    -- nil = now
    maxCount: number?,       -- nil = unlimited; verdict uses 3
    kinds: {string}?,        -- nil = all; verdict uses ribbon template
}): { Moment }
```

A `Moment` is `{ ageMonths, kind, id, line }` where `kind ∈ { "flag", "bond",
"grade", "standing", "mastery", "job", "house", "gangRank", "visit",
"confrontation", "age" }`. Same kinds the verdict already reads. The function
walks `data.flags`, `data.bonds`, `data.schoolGrades`, `data.jobStanding`,
`data.subjectMastery`, `data.jobId`, `data.houses.owned`, `data.gangRankId`,
`data.visits` (proximity-driven NPC news), `data.confrontations` (future:
rival/mentor/family events), and emits a `Moment` for every entry inside the
window.

**`line` is filled by a parallel `FormatMoment(moment, data)` function.** The
verdict already does this for its three slots; the same function is the source
of reel lines, the lobby card archetype, and the future NPC "remember when"
quote-back. The function must be deterministic and not narrate — it returns
prose built from facts in the data ("You fell into debt", "You and somebody
became close", "School was hard that year"), not authored flavour.

**No duplication.** VerdictService fills its three moments by walking the
ribbon's `momentsTemplate`, which lists slot kinds. Phase 1 changes that
walk to call `LifeService.Moments({ sinceMonths = nil, maxCount = 3, kinds =
templateKinds })` and map the result back. The "what happened" query is the
single source. The reel UI calls it again with `sinceMonths = lastBreakAt`
and gets a variable-length list.

## 4. The reel and its news source

**Build the news source before the screen.** The reel reads from
`LifeService.Moments`. If a chapter break yields zero moments, the reel
*is not shown*. The player presses Continue and the next chapter begins with
no inter-band screen. This is the explicit antidote to the "filler transition
screens" trap from the design (line 113).

**Empty reel is a feature, not a failure.** A life with no flags set, no
bonds, no jobs, no houses is a valid opening. The reel says nothing because
nothing happened. Showing three decorative slides anyway would teach the
player to skip the reel, and that lesson survives into the chapters where
the reel *does* carry news. The skip is permanent; the empty reel is
honest.

**Visual treatment when non-empty.** Plain text list, age-anchored. No
animation, no music, no click-to-flip. The design's line: "Do not narrate.
Emit facts and get out of the way." The reel is a list, not a cinematic.

**The reel is a screen, not a player surface.** There are no choices in the
reel. There is one button: Continue. Pressing it ages the life to the start
of the next band (a single AgeUp to the band boundary, not a year-by-year
climb) and unpauses the game.

## 5. The diegetic Continue button

The design (line 84) requires the player to press the seam. Phase 1 builds
exactly one button:

- **A "Continue" prompt that appears at the chapter boundary**, not before.
- The world freezes while the prompt is up: NPCs idle, timers pause, ambient
  triggers are not fired. The seam is the only time the world is allowed to
  be still.
- The button is centred, large, and unambiguous. It says **"Continue"** in
  the look-and-feel font. No options, no menu, no skip.
- Pressing it fires the chapter transition:
  1. Compute moments since the last break (`LifeService.Moments`).
  2. If the list is non-empty, show the reel. Continue is a single
     persistent button below the list; pressing it again advances.
  3. Age the life to the band boundary in one AgeUp call.
  4. Fire the new chapter's opening event sources (phase 3 hooks here).
  5. Resume.

**The button is diegetic because the player chooses when the chapter ends.**
A passive cut would interrupt an active shift or conversation. A button the
player presses when *they* are ready respects the verbs the life layer exists
to host.

## 6. Data changes

`LifeData` gains one field, set on the first break to the chapter that
started it and updated at every break:

```lua
lastChapterBreakMonths: number  -- ageMonths at the start of the current band
```

Nothing else. `seenEventIds`, `flags`, `bonds`, `schoolGrades`, `jobStanding`,
`subjectMastery`, `jobId`, `houses.owned`, `gangRankId` are already
verdict-readable. The query walks them; no schema rewrite is needed for the
reel.

## 7. What this phase does NOT build

- **No ambient triggers.** Phase 3.
- **No rival/mentor/family slots in `confrontations`.** Phase 5. The kinds
  list above is forward-compatible; the data is empty until then.
- **No "NPC news without you" entries in the reel.** A moment from an NPC
  that did not involve the player is rich content but a separate query —
  it asks `what changed in the world`, not `what happened in your life`. It
  belongs in a sibling query `WorldService.Moments(data, sinceMonths)` that
  does not exist yet. Spec it in phase 4 (autonomy quota, where NPCs move
  and act) or phase 5 (rivals), whichever lands first.
- **No "what did you do this life" lobby card.** Lobby-side change, not in
  this lane (handover B.md, "For A and C" in the 2026-08-14 ribbon entry).
- **No `Config.Verdict.MinAge` change.** The current value of 16 is fine for
  both reel and verdict.

## 8. Files to touch

| File                                            | Change                                                                                  |
|-------------------------------------------------|-----------------------------------------------------------------------------------------|
| `src/shared/Types.luau`                         | Add `Moment` type, add `lastChapterBreakMonths` to `LifeData`                           |
| `src/server/services/LifeService.luau`          | Add `Moments(data, opts)` and `FormatMoment(moment, data)`; set/advance break on band entry; freeze/unfreeze world around the seam |
| `src/server/services/VerdictService.luau`       | Replace the inline `fillMoments` walk with `LifeService.Moments(...)` + `FormatMoment` |
| `src/server/content/Ribbons.luau`               | No change — `momentsTemplate` slot kinds are already in the same vocabulary            |
| `src/client/ui/ChapterReel.luau`                | **NEW** — shows the list, one persistent Continue button, suppressed when list is empty |
| `src/client/ui/StatsUI.luau`                    | Hook the reel remote; the seam freezes the HUD's shift/task rows by listening to a `ChapterBreak` remote |
| `src/shared/Remotes.luau`                       | Add `ChapterBreak` (server→client, carries `{ ageMonths, moments: { Moment } }`)         |
| `src/shared/Config.luau`                        | Add `Config.Life.ChapterBands = { {0,4}, {5,9}, {10,14}, {15,19}, {20,39}, {40,80} }`   |
| `src/server/services/DebugService.luau`         | Add `/reel` (force a chapter break to current age) and `/moments` (print the query) to HELP_TEXT and Commands |

## 9. Gate

After implementation:
- `python3 tools/check.py` returns `all clean`.
- In-Studio: skip childhood, work one shift, walk for ~3 minutes, /reel —
  expect a non-empty reel with a Continue button that ages to the next band.
- In-Studio: /reel on a life that has done nothing since spawn — expect
  the world to advance to the next band boundary with no reel screen.

## 10. Open questions for the owner

1. **Band boundaries.** I have proposed 0–4 / 5–9 / 10–14 / 15–19 / 20–39 /
   40–80. If you want the adult band shorter (e.g. 20–34 / 35–54 / 55–80)
   say so before I write the Config table — `LifeService.Moments` is
   parameterised over the band list and is cheap to change, but the lobby
   card and the HUD copy read the band number and rewriting copy twice is
   twice the work.
2. **"NPC news without you" reel entries.** Out of scope for phase 1, but
   I want the query shape to admit them. Confirm I can add
   `WorldService.Moments(...)` in phase 4 or 5 and have it feed the same
   `ChapterReel` UI as a second list under the personal moments.
3. **Verdict pre-load in the elder band.** Line 5 in the table says the
   verdict becomes visible in the HUD as the life approaches 40. Confirm —
   I would rather the verdict stay a death-only surprise and the elder band
   end cold.

If you sign off on (1), (2), (3) above, I will implement in the order of
section 8 and report the gate result.
