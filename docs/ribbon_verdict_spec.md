# Ribbon / Verdict system spec

**For Agent B.** This is the end-of-life verdict layer: the system that converts "I played some minigames" into "I was a washed-up athlete who became a teacher." The docs call it the highest-ROI feature in the game. It does not exist today.

## What exists today

- `LifeService.Die(player)` sets `alive = false`, `stage = "Death"`, increments `livesLived`, resets all services, then fires `PlayerDied` with `ageYears`.
- The client receives `PlayerDied`, tears down every panel, and shows `deathFrame` — a translucent black overlay with a single button: "Back to the menu."
- The lobby reads `livesLived` to number the life slot. It does not read any verdict data.
- `LifeData` carries everything needed to compute a verdict: job history (via `jobStanding`), money, debt, convictions, gang membership, bonds, ties, milestones, school grades, subject mastery, gym workouts, age at death.

## What the system needs to do

1. **Compute a ribbon** from the life's data — a named archetype with a one-line description.
2. **Surface three causal moments** — the specific decisions/events that produced the ribbon. Not the stats, the *moments*. A player who died at 82 with $0 should not see "had no money." They should see "was fired from the office at 31, never held a steady job again."
3. **Show near-misses** — things the life almost was. "2 seasons from All-State." "One more year at the clinic and you would have been a doctor."
4. **Integrate into the death flow** — the verdict screen replaces or sits above the current blank death screen. The player reads it before pressing "Back to the menu."
5. **Ship with a debug command** — `/ribbon [name]` or similar, so it can be tested without living a full life.

## The agreed shape

### 1. Ribbon type

```lua
export type Ribbon = {
    id: string,            -- machine key, e.g. "dropped_out", "benchwarmer"
    title: string,         -- shown on screen, e.g. "Dropout"
    description: string,   -- one line of prose, e.g. "You never finished what you started."
    -- The three causal moments. Each is a string that names a specific event or
    -- decision, with the age it happened at. The player should be able to trace
    -- each one back to a moment they actually lived.
    moments: { RibbonMoment },
    -- Near-misses. Things the life almost achieved. Shown below the moments.
    -- Nil if the life had none worth noting.
    nearMisses: { string }?,
}

export type RibbonMoment = {
    age: number,
    line: string,  -- e.g. "Failed out of high school at 17"
}
```

### 2. Ribbon computation lives in a new service

**`VerdictService.luau`** in `src/server/services/`. One public function:

```lua
function VerdictService.Compute(player: Player): Ribbon?
```

Returns `nil` for a life that ended too young to have a ribbon (under 16, or childhood death).
Returns a `Ribbon` for every other life.

The computation reads `LifeData` and applies a scoring matrix. The matrix is **content,
not code** — it lives in a content file `content/Ribbons.luau` alongside `Jobs.luau` and
`Townsfolk.luau`, and the service reads it at require time. This means adding a ribbon
or adjusting weights is a table edit, not a code change.

### 3. The scoring matrix (in `content/Ribbons.luau`)

Each ribbon is an entry:

```lua
local Ribbons = {
    {
        id = "steadfast",
        title = "Steadfast",
        description = "You held a job for thirty years and never once looked for an easier one.",
        -- Scored by: years worked, total standing across all jobs, no convictions,
        -- bonds > 30 with at least 2 people, school grades mostly B or above.
        -- The matrix below is the *shape*, not the exact numbers — those are tuned
        -- in Config or as local constants in the content file.
        score = function(data)
            local s = 0
            -- Work record.
            s += table.sum(data.jobStanding, function(_, v) return v end) / 10
            -- No convictions is a strong signal.
            if data.convictions == 0 then s += 15 end
            -- Bonds.
            local strongTies = 0
            for _, bond in data.bonds do
                if bond >= 40 then strongTies += 1 end
            end
            s += strongTies * 3
            -- School.
            for _, grade in data.schoolGrades do
                if grade.grade == "A" then s += 2 end
                if grade.grade == "B" then s += 1 end
            end
            return s, buildMoments(data, "steadfast")
        end,
        momentsTemplate = "steadfast",
        nearMissesTemplate = "steadfast",
    },
    -- ... ~40 entries total. ~40% are failure ribbons.
}
```

**Failure ribbons** are not punishments — they are named endings. "Dropout," "Benchwarmer,"
"Estranged," "Broke," "Convict," "Lonely." Each has a description that is specific and
observational, not judgmental. The game does not say "you failed." It says "you were
a benchwarmer who never got called up."

### 4. Causal moments

Moments are **not** derived from stats. They are selected from the life's `flags`,
`seenEventIds`, and `schoolGrades` / `jobStanding` / `bonds` — things that actually
happened at a specific age. The `momentsTemplate` on each ribbon selects from
pre-authored moment sets keyed by ribbon id.

A moments template for "steadfast":

```lua
local SteadfastMoments = {
    { age = 16, flag = "firstJob", line = "Got your first job at the shop" },
    { age = 22, flag = "promotion", line = "Promoted to office clerk" },
    { age = 31, bond = "neighbor", line = "Mrs. Chen brought you soup when you were sick" },
}
```

The selector reads the life's actual data and picks the best matching moments from the
template. If a flag is absent, it falls back to the nearest available signal (a school
grade, a bond milestone, a standing band). The output always has exactly three moments
unless the life is too young, in which case it has one or two and that is honest.

### 5. Near-misses

Near-misses are computed, not authored. They answer: what was one step away from a
different ribbon? The algorithm:

1. For every other ribbon, compute how close this life's data would have scored.
2. Pick the top 1–2 that are within 15% of the threshold.
3. Format them as prose: "One more year at the clinic and you would have been a doctor."
   "You were two seasons from All-State."

If no near-miss is within range, `nearMisses` is nil.

### 6. Death flow integration

```
LifeService.Die(player)
  → compute ribbon via VerdictService.Compute(player)
  → store ribbon on LifeData (new field: `verdict: Ribbon?`)
  → fire PlayerDied remote with ageYears AND ribbon
  → client shows verdict screen instead of blank death overlay
```

**New remote shape:**
```lua
-- In Remotes.luau:
| "PlayerDied"  -- now carries { ageYears: number, ribbon: Ribbon? }
```

Wait — remote shapes can't change without a migration. Better: add a new remote.

```lua
| "VerdictReady"  -- fires after PlayerDied, carries the ribbon
```

Flow:
1. `LifeService.Die` sets `alive = false`, computes ribbon, stores it on LifeData.
2. Fires `PlayerDied` (existing remote, existing shape — no breaking change).
3. Client shows death screen.
4. Client requests verdict via `RequestVerdict` remote (new).
5. Server fires `VerdictReady` with the ribbon.
6. Client replaces death overlay with verdict screen.

Or simpler: fire both in `Die()`:

```lua
PlayerDiedRemote:FireClient(player, { ageYears = ageYears, ribbon = ribbon })
```

This changes the remote shape. That is a breaking change for any existing client
handlers. The existing handler at `init.client.luau:908` does:
```lua
Remotes.Get("PlayerDied").OnClientEvent:Connect(function(ageYears: number)
```

If we change the shape, we need to update that handler too. This is acceptable — it's
one handler, one remote, both in B's lane. But we should be explicit about it in the spec.

**Agreed approach:** Change `PlayerDied` to carry `{ ageYears: number, ribbon: Ribbon? }`.
Update the client handler to match. The ribbon is nil for childhood deaths and lives
that died before the verdict system was added (migration handles the latter).

### 7. The verdict screen (client)

The verdict screen replaces `deathFrame` in StatsUI. It shows:

1. **The ribbon title** — large, centred. "DROPOUT" or "STEADFAST" or "BENCHWARMER."
2. **The description** — smaller, below the title. "You never finished what you started."
3. **Three causal moments** — each on its own line, with the age in a muted colour.
4. **Near-misses** — if any, below the moments in a smaller font.
5. **"Back to the menu"** button — same as today, idempotent.

The frame uses the same visual language as the rest of the HUD: Gotham Bold for the
title, Gotham for body, warm off-white on dark. No new palette needed.

### 8. Config additions

No new Config entries needed. The ribbon content lives in `content/Ribbons.luau`, the
scoring weights are local constants in that file. The only Config change is adding
`Verdict` to `DebugService`'s command list.

Actually — one Config entry is useful: the minimum age for a ribbon.

```lua
Verdict = {
    MinAge = 16,  -- under this, verdict is nil and the death screen stays blank
},
```

### 9. Debug command

```
/verdict              shows your current ribbon (or "none yet" if under MinAge)
/verdict <ribbonId>   forces the named ribbon onto your life for testing
```

The force command writes `data.verdict` directly so the client can see it without
dying.

### 10. Content: the ~40 ribbons

The ribbons are content. They should be split into:

**Success ribbons (~16):** Steadfast, Master, Creator, Leader, Healer, Athlete,
Scholar, Philanthropist, Family, Explorer, Artisan, Architect, Musician, Writer,
Diplomat, Guardian.

**Failure ribbons (~16):** Dropout, Benchwarmer, Estranged, Broke, Convict, Lonely,
Washed-up, Addict, Drifter, Nobody, Burnt-out, Failed, Forgotten, Unemployed,
Inmate, vagrant.

**Neutral / specific ribbons (~8):** Parent (had a child), Immigrant (moved towns),
Inventor (patented something), Survivor (lived through a major event), Widow/Widower,
Retiree, Volunteer, Migrant.

Each has a title, a description, a moments template, and a near-miss template. The
moments templates reference flags, bonds, grades, and standing bands that exist in
`LifeData`.

**The 40% failure rule:** At least 16 of the ~40 ribbons are failure states. "A life
that ends badly must still end *named*."

## What does not change

- `LifeService.Die` still does everything it does today except compute and store the
  ribbon.
- The death teleport to lobby is unchanged.
- `livesLived` on the profile is unchanged — the lobby already numbers slots.
- School, work, people, crime — none of these services change their output. The
  ribbon reads their output, it does not modify it.

## What needs to be specced back (not done in this pass)

- The exact ribbon list and their descriptions — this is content writing, not engineering.
  The shape is agreed; the prose is a separate task.
- The moments template selection algorithm — the sketch above is the intent, not the
  implementation. The exact fallback chain (flag → bond → grade → standing) needs a
  pass when the service is built.
- The near-miss prose formatting — the algorithm is agreed (score all other ribbons,
  pick top 2 within 15%), the output strings need authoring.

## Verification

1. A life that dies at 17 with no job and no bonds gets a failure ribbon (e.g. "Dropout")
   with moments like "Never held a job" and "No one close enough to visit."
2. A life that dies at 82 after 40 years at the office with strong bonds gets "Steadfast"
   with three specific moments named by age and event.
3. A child who dies at 8 gets no ribbon (under MinAge) and the death screen stays blank.
4. `/verdict` shows the current ribbon or "none yet."
5. `/verdict steadfast` forces the ribbon, the client shows it on the death screen.
6. Gate: `python3 tools/check.py` — `all clean`.

## Files to touch

| File | Change |
|---|---|
| `src/shared/Types.luau` | Add `Ribbon`, `RibbonMoment` types; add `verdict: Ribbon?` to `LifeData` |
| `src/shared/Remotes.luau` | Change `PlayerDied` payload shape; add `RequestVerdict` |
| `src/server/services/VerdictService.luau` | **NEW** — compute, moments, near-misses |
| `src/server/content/Ribbons.luau` | **NEW** — the ~40 ribbons and their templates |
| `src/server/services/LifeService.luau` | Compute ribbon in `Die()`, store on LifeData |
| `src/server/services/DebugService.luau` | Add `/verdict` command |
| `src/client/ui/StatsUI.luau` | Replace blank deathFrame with verdict screen |
| `src/client/init.client.luau` | Handle new `PlayerDied` payload shape |
| `src/shared/Config.luau` | Add `Config.Verdict.MinAge` |
