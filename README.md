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
3. Press Play. You'll see a grey baseplate and a HUD in the top-right corner
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

Those early years are content, not a wait — see Events below — so a first life
plays them through. From the second life on (`Config.SkipChildhoodMinLives`) the
button appears as **Skip Childhood** instead, crossing them in one press. It
still runs the ordinary per-year path, so skipped years decay stats and cross
stages exactly as if they'd been lived; they just don't offer events.

All routes call `LifeService.AgeUp`, so stat decay, stage transitions and the
mortality roll can't drift apart between them.

## Events

One life event is offered per birthday, drawn at random (by `weight`) from the
entries eligible for that age and not yet answered this life. The seen list is
per-life: a new life may live the same moments again.

The engine decides *which* event fires; it does not decide how it looks. Each
event names a `delivery`, and the client keys its presentation off that:

- **Memory** — ages 0-5. Dim, wide, quiet; a recollection surfacing. This one is
  permanent, not a placeholder: a toddler has no world to walk around.
- **Direct** — everything else, pending a world. In step 3 these become
  `NPCApproach` / `Letter` / `PhoneCall` / `Location`, which are new entries in
  `EventUI.DELIVERY_STYLES` — the server, the engine and the content don't move.

`DELIVERY_STYLES` is a closed record rather than a loose map, so adding a variant
to `Types.EventDelivery` fails type-checking until it has been given a
presentation.

Server-authoritative throughout: the client is sent prompt and choice labels
only (never the effects or outcome lines), and the only answer accepted is one
belonging to the exact event that player was offered. The pending event lives in
the profile, so an unanswered prompt survives a rejoin — and rejoining can't be
used to reroll one you don't like.

### Adding events

Drop an entry into any module under `src/server/content/LifeEvents/`. No code
changes. The aggregator validates on server start and throws loudly on a
duplicate id, a backwards age range, fewer than two choices, or a choice that
moves no stat — per the spec, a choice that doesn't move a stat should be cut.

## Debug commands (Studio only)

Type these in chat. `!` works too, in case the chat system swallows `/`.

| Command | Effect |
| --- | --- |
| `/ageup [n]` | Age up n times through the real code path (default 1) |
| `/age <years>` | Age up repeatedly until reaching that age |
| `/die` | Force death and restart |
| `/stat <name> <value>` | Set health / happiness / smarts / looks |
| `/bank <seconds>` | Fast-forward the automatic age-up timer |
| `/life` | Print age, stage, alive, banked seconds, lives lived, pending event |
| `/event <id>` | Force a specific event on screen, ignoring age and seen list |
| `/events` | List what's eligible at the current age, and how many are seen |
| `/reevents` | Clear the seen list for this life so content can be replayed |

`/bank` is the quick way to verify the safety net: at the default threshold of
3000 seconds, `/bank 2990` puts you a few seconds away from an automatic age-up
without editing Config and restarting.

## What's here (Build Order steps 1-2)

- `vendor/ProfileStore` — vendored from
  [MadStudioRoblox/ProfileStore](https://github.com/MadStudioRoblox/ProfileStore)
  for profile load/save with session locking.
- `src/server/services/DataService.luau` — profile load/save, session locking.
- `src/server/services/StatService.luau` — the four stats (health, happiness,
  smarts, looks), clamped 0-100, with yearly decay that accelerates after
  age 60.
- `src/server/services/LifeService.luau` — aging, life stage transitions
  (Childhood / Adolescence / Adulthood / Elder), death (health hits 0, or an
  age-based natural mortality roll past 65), restart, and Skip Childhood.
- `src/server/services/EventService.luau` — event selection and answer
  validation. Decides *which* event fires, never how it's presented.
- `src/server/content/LifeEvents/` — the event content, as plain data tables.
- `src/server/services/DebugService.luau` — Studio-only chat commands for
  triggering edge cases without waiting on real time. No-ops outside Studio.
- `src/shared/Config.luau` — every tunable number. No magic numbers elsewhere.
- `src/shared/Types.luau` — shared type definitions, including the profile schema.
- `src/shared/Remotes.luau` — single source of truth for remote events.
- `src/client/ui/StatsUI.luau` — the HUD.
- `src/client/ui/EventUI.luau` — the delivery layer: how an event looks.

No world, careers, money or crime yet — those are later Build Order steps.
Events currently arrive as panels because there is nowhere yet for them to
happen; `delivery` is the seam that fixes that without rewriting them.

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

## Next up (Build Order step 3)

Modern world v1. That's when events stop being panels: the world-based
deliveries get written as new `EventUI` handlers and existing content switches
over by changing one field. Game currency arrives with it, since that's the
first build where there's both something to earn it from and something to spend
it on.
