# AGES (working title)

Roblox life-sim. Rojo project. See project spec for full design.

## Prerequisites

- Roblox Studio
- [Rojo](https://rojo.space) CLI + the Rojo Studio plugin (not installed on this
  machine — install it wherever you run Studio, e.g. `cargo install rojo`,
  `aftman add rojo-rbx/rojo`, or download a release from GitHub)

## Sync with Studio

1. From this directory: `rojo serve`
2. In Studio, open/create a place, open the Rojo plugin panel, and connect
   (default port 34872).
3. Press Play. You'll see a grey baseplate and a HUD in the top-left corner
   showing Age, Life Stage, progress toward the next year, an Age Up button,
   and the four stats.

To test anything that has to survive a restart (steps 5 and 6 below), turn on
**Game Settings → Security → Enable Studio Access to API Services** first.
Without it ProfileStore falls back to an in-memory mock store that is wiped
every time you stop the playtest, so saves will look broken when they aren't.

## Aging

Age does not advance on a wall clock. A year ends one of two ways:

- The player presses **Age Up**. Gated by `Config.ManualAgeUpCooldownSeconds`
  so it can't be spammed from birth to death.
- The safety net fires after `Config.AutoAgeUpGameHours` of *active session*
  playtime, showing a calm notice. Only in-server time counts, and the
  accumulator is saved in the profile, so leaving mid-year banks progress
  instead of losing it.

Auto thresholds are authored in **game hours**. `Config.Time.RealMinutesPerGameDay`
(12) over a 24 hour game day gives 30 real seconds per game hour, so the default
100 game hours is 50 real minutes. Re-tune the day length and every game-time
duration rescales with it; `ManualAgeUpCooldownSeconds` stays in real seconds on
purpose, because it's an input rate limit rather than a world duration.

Below `Config.ManualAgeUpMinAge` (5) there is no Age Up button — an infant
choosing to grow up doesn't fit the fiction — so those years run on the safety
net alone, at the faster `Config.ChildAutoAgeUpGameHours` (4 game hours = 2 real
minutes, so ages 0-4 take about 10 real minutes total). From age 5 the player
takes the wheel, since that's the point they could plausibly be choosing things
for themselves.

Both routes call `LifeService.AgeUp`, so stat decay, stage transitions and the
mortality roll can't drift apart between them.

## Debug commands (Studio only)

Type these in chat. `!` works too, in case the chat system swallows `/`.

| Command | Effect |
| --- | --- |
| `/ageup [n]` | Age up n times through the real code path (default 1) |
| `/age <years>` | Age up repeatedly until reaching that age |
| `/die` | Force death and restart |
| `/stat <name> <value>` | Set health / happiness / smarts / looks |
| `/bank <seconds>` | Fast-forward the automatic age-up timer |
| `/life` | Print age, stage, alive, banked seconds, lives lived |

`/bank` is the quick way to verify the safety net: at the default threshold of
3000 seconds, `/bank 2990` puts you a few seconds away from an automatic age-up
without editing Config and restarting.

## What's here (Build Order step 1: Skeleton)

- `vendor/ProfileStore` — vendored from
  [MadStudioRoblox/ProfileStore](https://github.com/MadStudioRoblox/ProfileStore)
  for profile load/save with session locking.
- `src/server/services/DataService.luau` — profile load/save, session locking.
- `src/server/services/StatService.luau` — the four stats (health, happiness,
  smarts, looks), clamped 0-100, with yearly decay that accelerates after
  age 60.
- `src/server/services/LifeService.luau` — aging, life stage transitions
  (Childhood / Adolescence / Adulthood / Elder), death (health hits 0, or an
  age-based natural mortality roll past 65), and restart.
- `src/server/services/DebugService.luau` — Studio-only chat commands for
  triggering edge cases without waiting on real time. No-ops outside Studio.
- `src/shared/Config.luau` — every tunable number. No magic numbers elsewhere.
- `src/shared/Types.luau` — shared type definitions, including the profile schema.
- `src/shared/Remotes.luau` — single source of truth for remote events.
- `src/client/` — minimal HUD only. No world content yet.

No world content, careers, events, or crime yet — those are later Build Order
steps. This step is just "grey baseplate + working numbers."

## Type-checking

All modules are `--!strict`. Verifying needs `luau-lsp` plus the Roblox API
definitions (`globalTypes.d.luau`, downloadable from the luau-lsp releases);
neither is checked in, so point `--defs` at wherever you keep it.

```sh
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --defs=globalTypes.d.luau --sourcemap=sourcemap.json \
  --ignore="vendor/**" src/
```

`vendor/**` is ignored because the vendored ProfileStore reports type errors of
its own; everything under `src/` must stay clean.

## Next up (Build Order step 2)

Event engine: data-driven life events that spawn as world interactions
(NPCApproach / Letter / PhoneCall / Location) rather than popups. Target ~20
test events before moving to step 3 (Modern world v1).
