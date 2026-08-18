# Phase 3 — ambient events

## Summary

The event system already has a two-phase delivery pipeline (`deliveringEventId` → `pendingEventId`) and a route-based picker (`PickStageable`). What is missing is the *routing layer* that connects world context to event selection: proximity triggers, escalation chains, tag-based context filtering, cooldown enforcement, and 70/30 world-to-modal ratio.

This phase closes the gap between "events can be staged" and "events arrive when they belong."

## What already exists (do not rebuild)

- `DeliveryService.tick` — timer-driven ambient scheduler, picks via `EventService.PickStageable`
- `WorldEventService.tick` — proximity checker for tagged anchors, calls `EventService.OfferIfEligible`
- `DeliveryPresenters.For` — three presenters: Letter, PhoneCall, NPCApproach
- `EventService.pickForRoute` — weighted picker, fresh-then-repeat, route-gated
- `EventService.ResolveChoice` — applies effects, fires `answeredHandlers`, calls `ageUpHandler` for childhood
- Schema fields validated at load: `tags`, `cooldown`, `escalatesTo`, `writesBack`
- The 0–5 age rule is correct and already implemented: `ResolveChoice` line 617 calls `ageUpHandler` only when `ageYears <= Config.Childhood.EndAge`

## What is missing

1. **Proximity-based trigger source** — ambient events fire on a timer regardless of where the player is. A friend event should be more likely when a friend is nearby, not just when the clock says so.
2. **Escalation chains** — `escalatesTo` is validated but never read. A resolved event should be able to pull its follow-up into the world.
3. **Tag-based context routing** — `tags` are validated but never read. Events should carry context labels that the picker uses to weight or filter candidates.
4. **Cooldown enforcement** — `cooldown` is validated but never checked. An event should not re-fire within its cooldown window.
5. **70/30 ratio enforcement** — no tracking of how many world-spawned vs modal events have fired in a chapter.

---

## 1. Tag-based context routing

### Context tags

A context tag describes the player's current situation. The picker reads them and uses them to filter events: an event whose tags match the current context is a better candidate than one whose tags do not.

An event with no tags is always eligible (it is universal). An event with tags is eligible only when at least one of its tags matches the current context — unless it is the only candidate, in which case it still fires.

### What the context returns

A function `getContextTags(player)` lives in `EventService` and returns a `Set<string>`. The set is built from:

- **NPC proximity**: for each NPC within `Config.Ambient.NPCContextRadius` (default 15 studs) of the player, emit `npc:{cast}` — e.g. `npc:friend`, `npc:neighbor`. Cast comes from `event.cast` on NPCApproach events; the cast registry (`Cast.ById`) maps each cast member to a string.
- **Current location**: for the current room / zone the player stands in, emit `zone:{zoneId}`. Zone ids come from a new table `Zones.luau` keyed by the collection tag on floor parts (`Config.World.ZoneTag`). This is the first time a zone system is introduced; it lives in `src/server/content/` alongside Cast, Flags, Jobs, etc.
- **Flags that describe state**: for each flag on the life that appears in `Config.Ambient.FlagContext`, emit `flag:{flagId}`. This lets events like `gym_pushed_too_hard` (forbids `sick`) preferentially fire when `flag:sick` is absent, and the flu event (`ambient_flu`, forbids `sick`) preferentially fire when it is present.

### Integration in the picker

`pickForRoute` is modified to accept an optional `contextTags: Set<string>?`. When non-nil:

- An event with no tags is always considered (same as now).
- An event with tags is only considered if at least one of its tags is in the context set, or if no tagged candidate exists in the pool.
- The set passed is the result of `getContextTags(player)`.

`PickStageable` passes `nil` (no context filtering) to preserve existing behaviour for birthday picks and shift picks, which are driven by different rules. The context filtering only applies to Ambient route picks in `DeliveryService.tick`.

### Implementation

- `EventService.luau`: add `getContextTags(player): Set<string>` and thread `contextTags` through to `pickForRoute`.
- `DeliveryService.luau`: call `EventService.getContextTags(player)` before each `PickStageable` call in `tick`, pass the result as the filter.
- `src/server/content/Zones.luau`: new file, keyed by string id, each with a `tag` field. Require in `init.luau`. No content yet — the table exists for future zones.

---

## 2. Cooldown enforcement

### What it is

`cooldown` is a real-seconds delay between successive *deliveries* of the same event id for the same life. Nil means no cooldown (the default). The field is validated at load but never checked at runtime.

### Storage

`LifeData` gains one field:

```lua
cooldownTimers: { [string]: number },
```

Keyed by event id, value is `os.clock()` of the last delivery. Written on stage (not on resolution), because the cooldown is on the *delivery* path per the field comment. A missed phone call should come back; the cooldown tracks "don't send another one of these too soon."

### Integration

- `EventService.isEligible`: after the existing checks, if `event.cooldown ~= nil`, check `data.cooldownTimers[event.id] == nil or os.clock() - data.cooldownTimers[event.id] >= event.cooldown`.
- `DeliveryService.stage`: after a successful `present()` call, set `data.cooldownTimers[event.id] = os.clock()`.

---

## 3. Escalation chains

### What it is

`escalatesTo` on an event means "after this is answered, stage the named event in the world." The chain is read at resolution, not at selection. The follow-up is a world delivery (Ambient route), not a modal panel — it arrives when the player reaches it, not as a surprise prompt.

This is what makes a life feel threaded rather than random: a pushed-too-hard gym injury can escalate to a doctor visit or a physical therapy session, and the player can trace the cause back.

### Implementation in `EventService.ResolveChoice`

After applying effects, flags, money, and firing `answeredHandlers` (lines 583–606 in the current file), but *before* the `ageUpHandler` call (line 617), check:

```lua
if event.escalatesTo ~= nil then
    local followUp = LifeEvents.ById[event.escalatesTo]
    if followUp ~= nil then
        -- Stage the follow-up via DeliveryService, bypassing the timer.
        -- ForceStage is the right primitive: it claims the event in the profile
        -- and builds the world object immediately.
        DeliveryService.ForceStage(player, event.escalatesTo)
    end
end
```

`DeliveryService.ForceStage` already exists and does exactly this: it stages a named event without using the timer, for debug use. Reusing it for escalations keeps the code path shared.

### Important constraint

The escalation only fires if the follow-up event is eligible (age, flags, cooldown, etc.). If `ForceStage` returns false (the event is not stageable), the chain simply does not continue — no warning, no error. This is the same as a birthday rolling a nil event.

---

## 4. Proximity-based ambient triggers

### What it is

Currently, ambient events are timer-driven and placed at a fixed delivery point. The player must walk to that point to collect them. What is missing is the ability for ambient events to be triggered by *proximity to a living NPC or a tagged location*, not just by the clock.

An NPCApproach event like `gym_running_group` (cast: neighbor, tags: `{"neighbor", "gym"}`) should fire when the player is near a neighbor *and* the event is eligible, rather than waiting for the timer to place a stranger at a random delivery point.

### How it works

`DeliveryService.tick` already runs every `Config.Ambient.TickSeconds` (1s). It already calls `EventService.PickStageable` with route "Ambient". What we add is a second pick path: **proximity pick**.

In each tick, after the timer pick, also attempt a proximity pick:

```
for each player:
    context = getContextTags(player)
    if context has any npc tag:
        proxEvent = PickStageable(player, "Ambient", filter=canPresent, contextTags=context, preferProximity=true)
        if proxEvent ~= nil and proxEvent.cast ~= nil:
            -- Stage it, but at the NPC's location, not at a delivery point.
            DeliveryService.ProximityStage(player, proxEvent)
```

### `DeliveryService.ProximityStage`

This is a new function. It:

1. Finds the nearest NPC matching `event.cast` to the player (via `NPCService.GetPositions()` — see below).
2. Calls the presenter with the NPC's current position as the point, not a delivery-point marker.
3. Tags the NPC's root part as the anchor (instead of a separate envelope/part), so `WorldEventService` picks it up.
4. The NPC walks *toward* the player (instead of walking to a fixed point from the door).

The key difference from `ForceStage`: `ProximityStage` places the delivery at the NPC's current position and uses the NPC's root as the anchor. The NPC is already there; the player walks to them.

### NPCService additions

`NPCService` needs to expose current positions for proximity selection:

```lua
function NPCService.GetPositions(player: Player): { { id: string, position: Vector3, cast: string } }
```

Returns a list of all active visitors for the player, with their cast type and root position. Called from `DeliveryService` during proximity picking.

### World location proximity

Separately, `WorldEventService` already checks player proximity to tagged anchors. What we add is a new tag: `Config.World.AmbientTriggerTag`. Events with tags like `{"gym"}` can be associated with a physical location (the gym floor) via a tag on the floor parts. When the player enters that zone, `WorldEventService` calls `EventService.PickStageable` with route "Ambient" and the context tags including `zone:gym`. This is an extension of the existing anchor system, not a new service.

### Implementation

- `NPCService.luau`: add `GetPositions(player)`.
- `DeliveryService.luau`: add `ProximityStage(player, event)`, modify `tick()` to attempt a proximity pick after the timer pick.
- `WorldEventService.luau`: read `Config.World.AmbientTriggerTag` and call a new `EventService.PickNearby(player)` when the player enters a tagged zone.
- `EventService.luau`: add `PickNearby(player)` — same as `PickStageable` but with context tags and a zone-based filter.

---

## 5. 70/30 ratio enforcement

### What it is

Of all events that fire in a chapter, 70% should be world-spawned (Ambient, Wandered, Anchored routes) and 30% modal (Immediate, Shift routes). This keeps the life feeling lived-in rather than interrupted by panels.

### Tracking

`LifeData` gains two fields:

```lua
worldEventsThisChapter: number,
modalEventsThisChapter: number,
```

Reset to 0 at each chapter break (same place as `pendingEventCountInChapter`, line ~506 in LifeService).

Incremented in `EventService.offer()` at line 311, after the existing `pendingEventCountInChapter += 1`:

```lua
local route = Delivery.RouteOf(event.delivery)
if route == "Immediate" or route == "Shift" then
    data.modalEventsThisChapter += 1
else
    data.worldEventsThisChapter += 1
end
```

### Enforcement

Two choke points need the check:

**`OfferForAge` (birthday / Immediate)**: before picking an Immediate event, check that the resulting ratio would still satisfy 70%. The check is: `worldCount >= 0.7 * (worldCount + modalCount + 1)`. Simplified: `worldCount * 10 >= modalCount * 3`. If the check fails, return nil — the birthday slot goes unfulfilled this chapter.

**`PickStageable` for Ambient route**: no check needed here — Ambient is already world-spawned.

**Shift events**: shift events are modal by nature (they happen at work). The ratio check applies to them too, but since WorkService controls shift event firing independently, the check lives in `WorkService` when it picks a shift event. For now, shift events bypass the ratio — they are not counted in `modalEventsThisChapter` and are not subject to the 70/30 rule. This is a deliberate carve-out: work events are structurally different from birthday and ambient events.

### The math

With `MaxPerChapter = 3`:
- Minimum world events = 2 (66.7% — just under 70%)
- To guarantee 70% with 3 events: 3 world, 0 modal → 100%. 2 world + 1 modal → 66.7%.
- So with a cap of 3, the only way to strictly hit 70% is 3/0 or 2/0 (0/1 and 1/2 violate it).

This means the ratio effectively becomes: **at most 1 modal event per chapter**. The birthday event counts as modal, so a chapter can have at most one birthday *and* no other modal events, or a birthday with zero ambient events (which is a low-event chapter).

If the cap is raised to 4 in the future, the ratio becomes: 3 world + 1 modal = 75%, which satisfies it.

---

## 6. 0–5 age rule (already correct — no changes)

`EventService.ResolveChoice` line 617:

```lua
if ageYears <= Config.Childhood.EndAge and ageUpHandler ~= nil then
    ageUpHandler(player, "Event")
end
```

Adult ambient events never call `ageUpHandler`. Confirmed. No code changes needed.

---

## File changes

| File | Change |
|---|---|
| `src/shared/Types.luau` | Add `cooldownTimers`, `worldEventsThisChapter`, `modalEventsThisChapter` to `LifeData` |
| `src/shared/Config.luau` | Add `Ambient.NPCContextRadius`, `Ambient.FlagContext`, `World.AmbientTriggerTag` |
| `src/server/services/EventService.luau` | Add `getContextTags`, thread context in `pickForRoute`, add escalation chain in `ResolveChoice`, add ratio tracking in `offer` |
| `src/server/services/DeliveryService.luau` | Add `ProximityStage`, call `getContextTags` in `tick`, enforce cooldown on stage |
| `src/server/services/NPCService.luau` | Add `GetPositions` |
| `src/server/services/WorldEventService.luau` | Read new `AmbientTriggerTag`, call `EventService.PickNearby` on zone entry |
| `src/server/content/Zones.luau` | New file, empty keyed table for future zones |
| `src/server/content/LifeEvents/init.luau` | No changes (validation is already in place) |

---

## Verification

1. `python3 tools/check.py` — zero errors.
2. `luau-compile` all modified server files — no type errors.
3. In-Studio tests:
   - Start a new life at age 13. Wait for the first ambient event. Observe it arrives as a letter (timer-triggered, fixed delivery point).
   - Walk near a neighbor NPC. Wait. Observe a neighbor-tagged event (`visit_the_ladder` or `gym_running_group`) appears at the neighbor's location instead of the mat.
   - Resolve an event with `escalatesTo`. Observe the follow-up event is staged in the world immediately after resolution.
   - Resolve an event with `cooldown`. Attempt to fire it again within the cooldown window. Observe it is refused.
   - Check `/deliveries` debug output: shows `worldEventsThisChapter` and `modalEventsThisChapter` counters.
   - Force a birthday event when world count is 0 and modal count would reach 1. With `MaxPerChapter=3`, the birthday should still fire (it is the chapter spine). But a second modal event (e.g. via debug `/event`) should be refused.
   - Walk into a zone-tagged area. Observe zone context tags appear in `/deliveries` debug output.
