# AGES: Roblox engineering practice (researched 2026-08-08)

Deep research pass commissioned before building sports, because the job system shipped as
"stand on a circle for four minutes" and that failure was partly a *design* failure and partly
not knowing what the platform can actually do. This file is the platform-capability half.

Everything here is 2025–2026 material. Roblox changed a lot; anything you remember from
before 2024 should be checked against this file first.

## The headline: Server Authority went GA on 2026-07-09

Roblox now ships first-party **client prediction + rollback + resimulation** netcode. One of
the three official templates is *a soccer game with a physics ball* — i.e. exactly the hardest
problem we were about to solve by hand.

- Set `Workspace.AuthorityMode = Server`. This auto-enables `NextGenerationReplication`,
  `PlayerScriptsUseInputActionSystem`, `SignalBehavior = Deferred`, `StreamingEnabled`,
  and `UseFixedSimulation`.
- Gameplay logic moves into `RunService:BindToSimulation(dt)` callbacks, in a ModuleScript
  required by **both** client and server (one definition, run twice — same idea as our
  `shared` mapped modules).
- Input arrives via `InputAction` objects parented under the Player. **Never**
  `UserInputService.InputBegan` inside simulation code.
- Predicted gameplay state lives in **attributes** on predicted instances, so it can be
  rolled back.
- Only properties tagged "Simulation Access" (e.g. `BasePart.CFrame`) are legal inside
  `BindToSimulation`.
- `RunService:SetPredictionMode()` overrides the automatic prediction window.
  `Player:GetCameraState()` is new at GA.

**Decision: sports gets its own third place with `AuthorityMode = Server`.** `AuthorityMode`
is per-place and all-or-nothing — it changes signal semantics to Deferred, replaces the input
pipeline, and costs server CPU. Migrating the open-world life-sim place would be a large risky
migration for no benefit; nothing in a life sim needs sub-100ms fairness. Migrating a *sport*
place buys the exact netcode that would otherwise cost months and still be worse. We already
have two places and a working teleport flow, so a third is marginal.

**Hard limits to design around before writing any sports code:**
- **64 attributes per instance** (50-char names, 50-char string values).
- **8 active animation tracks per Animator** — a real constraint if you layer
  dribble/pass/shoot/tackle.
- RemoteEvents are **not** on the simulation timeline; they land ~**40–50 ms** off it.
  Never mix a RemoteEvent result into predicted state.
- Custom emotes and strafing animations unsupported.
- Tool welds can be deleted during misprediction when swapping tools.
- Mobile/console client rollout trails desktop.

## Architecture — our plain service modules are correct, do not adopt a framework

This is now the mainstream position and it is *Sleitnick's own*, in his Knit postmortem: Knit
is a "plane-car-boat," its "greatest weakness" is losing intellisense (services resolve by
string name into generic tables), services degenerate into "secret global state containers"
functionally equivalent to `_G`, and testing is miserable from pervasive side effects. His
recommendation is: just use ModuleScripts, plus a loader for boot ordering and a networking
utility. **That is exactly what AGES already has.** Knit is effectively unmaintained.

- **Flamework** solves DI properly but *requires roblox-ts*. Luau strips type metadata at
  compile time, so runtime-reflection DI is impossible in pure Luau. Not worth changing
  language for.
- **ECS (Matter / Jecs):** Matter's original repo is unmaintained (fork: `matter-ecs/matter`);
  the live conversation is **Jecs**. ECS pays off with hundreds-to-thousands of homogeneous
  entities stepped every frame, plus a need to snapshot/diff world state. We have ~20 NPCs and
  event-driven progression. **Don't.** Its best argument here was rollback (snapshot/restore is
  trivial in ECS, horrible in OOP) — and Server Authority now gives us rollback for free, which
  removes that argument. Also: ECS on Roblox leaves *replication as an exercise for the user*.
- **UI:** Roact is deprecated → react-lua. Rodux is legacy → Reflex. Our hand-written UI is
  fine; if we ever adopt something, adopt react-lua over Fusion.

## Networking

| Type | Use for | Never |
|---|---|---|
| `RemoteEvent` | Discrete order-sensitive facts: goal scored, possession granted, currency | Per-frame streams |
| `UnreliableRemoteEvent` | Per-frame ephemera: aim direction, cosmetic VFX | Anything that desyncs if dropped |
| `RemoteFunction` | Almost nothing. Server→client invoke is an exploit and a hang vector | Use FireClient + reply event |

- `UnreliableRemoteEvent` payload cap: **900 bytes** documented (~908 measured).
- Both remote types: roughly **500 requests/sec per client**, shared across all remotes of
  that type. Exceeding produces throttling and warnings, *not* an engine kick.
- **Outdated folklore to ignore:** the old "20 calls/sec" and "50 KB/s" wiki numbers.

**Serialization.** Default remote encoding is self-describing — every value carries a type tag.
A single `number` costs **9 bytes** (8 float + 1 tag). Sending `{x=,y=,z=}` pays three tags plus
key strings plus table framing; three float32s in a `buffer` is **12 bytes total**. Use buffers
for anything high-frequency. **Zap** (codegen from an IDL, validates all inbound data — the
generated validators are free anti-exploit) or **ByteNet**. Also **batch**: one remote at 20 Hz
with an accumulated payload beats twenty remotes at 20 Hz.

**Network ownership — the classic trap, and why we're not fighting it.**
- Server always owns anchored parts; cannot be overridden.
- **Unanchoring an assembly wipes its ownership setting** and reverts to automatic. Order
  matters; this silently breaks `SetNetworkOwner` calls made before unanchoring.
- Ownership is per-*assembly*, not per-part.
- Studio has a "Network owners" viewport visualization — use it.

The failure mode every Roblox soccer game hits: giving ownership to the last toucher is
responsive solo, but each handoff **freezes the ball ~0.5 s**. Keeping it server-side
(`SetNetworkOwner(nil)`) removes the hitch but adds a full RTT to every kick — at 175+ ms the
ball visibly trails the striker. **There is no good answer inside this API.** That is the
single strongest argument for the Server Authority place.

If ever built by hand: server owns the authoritative ball, clients run a **local visual clone**
simulated optimistically and blended back toward the server transform. Reference reading (do
not vendor — author admits it's messy, Knit-based, lightly tested): "Server Authoritative
Soccer System" on the DevForum, a Chickynoid fork with ball-claiming prediction and goalkeeper
lag compensation demoed at 200 ping.

Also: **`Workspace.ImprovedPhysicsReplication` shipped globally 2026-06-15** with eventual
consistency. Physics network stats now report **zero** — monitor **Instance State Replication
(ISR)** stats instead. There's a `Disabled` escape hatch for regressions.

**Lag compensation.** Canonical theory is Gabriel Gambetta's: sequence-number every input,
server echoes last processed sequence, client resimulates unacknowledged inputs on correction.
For rewind hit validation there's `RollbackHitbox` (per-player hitbox history, rewinds every
character to the shot timestamp, OBB intersection) — directly applicable to a goalkeeper save
or a tackle.

**Anti-exploit.** Clients send **intent, never results** — "I kicked," not "the ball is now at
X with velocity V." Token-bucket rate limit per player per remote. Type- and bounds-check
everything; return `nil` and drop **silently** so exploiters can't fingerprint which check
failed. Log-and-ignore beats auto-kick — false positives cost real players. You cannot hide a
remote; obfuscated names buy minutes.

## Performance

**Event renames (use the new names):** `Stepped → PreSimulation`, `Heartbeat → PostSimulation`,
`RenderStepped → PreRender`, plus new `PreAnimation`. Frame order: PreRender → PreAnimation →
animation evaluation → PreSimulation → physics → PostSimulation. Apply forces in
`PreSimulation` (before the solver), read results in `PostSimulation`. Subtlety:
`PostSimulation` fires slightly before `Heartbeat` — not byte-identical signals.

- `task.wait()` yields with a one-frame minimum; fine for coarse work. **Never poll a
  condition on a frame event when it changes every few seconds** — that's ~59 wasted
  frames/sec. Use signals. *(Our School/Work services tick at 4 Hz, which is defensible, but
  worth revisiting as signals where possible.)*
- What actually costs frames: synchronous Luau blocking the main thread; deep-clone /
  serialize / recursive table work on large structures; per-frame closures and table
  allocations feeding the incremental GC; draw calls.
- **Procedural animation: write `Motor6D.Transform`, not `C0`/`C1`.** Commonly-missed real
  perf bug.
- `--!native`: best on numeric/`buffer`-heavy inner loops, ~2–3× on intersection math. Engine
  API calls (raycasts, instance access) are **not** accelerated. Costs server startup time —
  use the `@native` attribute on individual hot functions, don't blanket modules.
  `--!optimize 2` is already default for published places.
- **Parallel Luau: probably not for us.** Servers expose only **~2 usable worker threads**
  (clients up to 8). Splitting a 1 ms task four ways can be *slower* than serial. Worth it for
  bulk raycast batches or large NPC populations; not for 20 townsfolk.

**Streaming** (matters for us — `StreamingEnabled` is on):
- `ModelStreamingBehavior = Improved`; `StreamingIntegrityMode = PauseOutsideLoadedArea`.
- Leave `StreamingMinRadius` at **64** so the engine can scale down for weak devices; set
  `StreamingTargetRadius` meaningfully above min — the gap is the buffer that prevents pauses.
- `ModelStreamingMode = Atomic` avoids `WaitForChild` storms, but **atomicity only holds for
  initial replication**.
- **Minimise `Persistent`** models — they never stream out and permanently hold memory.
- **Critical for sport: client-side physics only simulates inside streamed regions**, even for
  locally created parts. A pitch must not stream out. `Player:AddReplicationFocus()` can keep a
  distant region simulating, at server cost.
- New: Predictive Streaming (opt-in preloading) and SLIM (auto-generated LODs).

**Leaks.** The engine will not GC an instance while a connection referencing it is alive, and
it does **not** auto-destroy Player objects or their characters on leave — enable
`Workspace.PlayerCharacterDestroyBehavior`. One Trove/Janitor per lifecycle boundary. The
CollectionService pattern: `GetInstanceAddedSignal` → create Trove, `GetInstanceRemovedSignal`
→ `:Destroy()`, backfill with `GetTagged()` at startup. **`Debris` only removes instances — it
does not disconnect connections.** Watch `LuaHeap`, `InstanceCount`, `PlaceScriptMemory`; the
classic leak profile is a server fine for 90 minutes that then drifts.

**MicroProfiler:** Ctrl+F6 (Ctrl+Shift+F6 pause), press again for function-level Luau timing.
Orange = scripts, blue = render, red = GPU wait. Server health: Dev Console → Server Stats →
Heartbeat steps/sec; below 60 means over budget. Script activity % is a share of *script* time,
not frame time — don't chase 80% when all Luau costs 1.2 ms.

## Animation and character feel

- **`AnimationConstraint` now replaces `Motor6D` in R15 rigs** when `AvatarJointUpgrade` is
  Default/Enabled — the default for new experiences. Migrate rig code from
  `FindFirstChildOfClass("Motor6D")` to `FindFirstChildWhichIsA("AnimationConstraint")` with a
  Motor6D fallback. It supports force-based simulation (`IsKinematic = false`,
  `LinearStrength`/`AngularStrength`/`MaxForce`/`MaxTorque`), so ragdolls and arm-strength
  effects no longer need rig surgery. `Workspace.ImprovedAnimationConstraint` (June 2026) fixed
  long-standing chain instability.
- **Blending semantics, internalise this:** the Animator evaluates tracks **per joint**, high
  priority to low, accumulating weight, and **stops once the sum reaches 1.0** — lower-priority
  tracks then contribute *nothing* to that joint. Same-priority tracks blend proportionally to
  weight. Priorities low→high: `Core, Idle, Movement, Action, Action2, Action3, Action4`.
  Practical rule: **one track at Action+ per body group at a time**, or you get jitter.
- `AnimationController` is legacy — use `Animator`.
- `IKControl` is the right tool for foot planting on slopes, hand-to-ball contact, look-at.
  Set `ChainRoot` and `EndEffector` (never make ChainRoot the rig root). Add
  `BallSocketConstraint`/`HingeConstraint` with `LimitsEnabled` to stop wrists/elbows
  inverting. Known bug: IK can still influence the rig at `Weight = 0` — toggle `Enabled`.
- **Don't rewrite the character.** The modern answer is **Character Physics Controllers**
  (`ControllerManager` + ground/airborne/swim controllers) — the Humanoid's locomotion
  internals as standalone instances, giving precise acceleration/deceleration/slope control
  while keeping clothing, accessories, camera, health, animation loading. Going fully
  Humanoid-less costs all of that plus replication headaches, and pure-Lua controllers are
  stuck at 60 Hz while physics steps at 240 Hz. Responsiveness comes from tightening
  acceleration curves, killing animation fade-in on action starts, and predicting locally.

**Pathfinding** (relevant to our walking NPCs): hard caps of **3,000 studs** line-of-sight and
a **20,000-node budget** — exceeding either **fails silently**. Always branch on `Path.Status`
(`Success`/`NoPath`/`ClosestNoPath`); most bugs are unhandled `NoPath`. `AgentRadius` = half
HRP width + 0.5–1 stud. Practical ceiling ~a dozen concurrently-repathing agents; there are
2025 reports of engine-level degradation pushing script activity 3–5% → 15–40%. Recompute every
1–2 s or when the target moves 5–10 studs; only re-path on `Blocked` when
`blockedWaypointIndex >= nextWaypointIndex`. Beyond that scale use a precomputed node graph or
flow field. Under StreamingEnabled, client-side `ComputeAsync` fails against non-streamed
targets.

## Data

**The 2026 change that matters: DataStore request budgets moved from per-server to
per-experience**, plus a total storage cap. The legacy `60 + 10 × players` per-server-per-minute
model is **dead** — budget is now shared across every running server, so a popular Saturday is
when you discover you were saving too often. ProfileStore's **300 s default autosave** (up from
ProfileService's 30 s) is well-aligned; **do not lower it**.

ProfileStore practice: kick if `:StartSessionAsync()` returns `nil`; `:EndSession()` on
`PlayerRemoving`, `BindToClose`, **and before every teleport** — this directly affects our
lobby↔game↔sport hops, and skipping it means the destination server waits on lock expiry. Pass
a `Cancel` condition tied to the player still being present. Never use `Steal`. **Mutate
`profile.Data` in place, never reassign the table.** Use `ProfileStore.Mock` in Studio.
`:ProfileVersionQuery()` is the rollback tool for support tickets.

**Migrations:** store an integer `dataVersion` *inside* the profile and apply ordered migration
functions on load. Versioning the store *name* strands existing players — reserve that for
unrecoverable breaks. **Namespace by subsystem** (`Data.school`, `Data.career`, `Data.ties`) so
each owns its own migrations and we never write one 400-line monolithic migrator. *(We already
have a `schema` field — keep using it this way.)*

**MemoryStore** (cross-server only): quota **64 KB + 1.2 KB × concurrent users**, game-level,
with an **8-day traceback** before scaling back down. Exponential backoff on
`DataUpdateConflict`. Studio shares quotas but isolated data — with one user the quota is tiny,
which is the usual "why does this fail only in Studio" answer.

## Testing and tooling — the highest-leverage change available to us

**TestEZ is archived. Use Jest Lua.** Migration gotchas: Jest needs explicit
`require(JestGlobals)` (no injected globals), and `.toEqual` is *deep* equality where TestEZ's
`.to.equal` was reference equality.

**Split CI in two.** Job 1 (Ubuntu, every PR): `rokit install` → `wally install` →
`rojo sourcemap` → `wally-package-types` → `stylua --check` → `selene .` → **`luau-lsp
analyze`**. That last step is the highest-value item in the whole pipeline — full type checking
with Rojo instance-tree resolution and Roblox API types, catching most of what currently costs
us a Studio round-trip. Job 2 (Windows, nightly/on-merge): Studio + `run-in-roblox` with the
Jest runner; this is the flaky link (needs a `ROBLOSECURITY` burner secret, and Roblox pins
cookies to IP so runners need a stable-IP tunnel). Reference: `Sleitnick/rbx-ci-test`.

**Better still: write pure-logic modules DataModel-free and run them headlessly under Lune** in
Job 1. Content tables, tie ladders, career branching rules, economy math, save migrations — all
testable with no Studio at all. **Given our "batch the testing" working style this is the single
biggest process win available**: it converts a class of bugs from "found in a Studio session"
to "found in 40 seconds on push."

Toolchain notes: **Rokit** replaced Foreman. Set `--!strict` globally via `.luaurc` rather than
per-file headers. Gitignore `sourcemap.json`.

> Note against our CLAUDE.md: it says there is no `luau-lsp`, `selene` or `stylua` installed.
> Installing `luau-lsp` in particular is now clearly worth it — it is the one tool that would
> have caught type errors we currently only find on the first Studio sync.

## The short list for a physics-ball sport

1. **Own place, `AuthorityMode = Server`.** Study the official soccer template first.
2. **Never hand ball ownership between players** — ~0.5 s freeze per handoff, no workaround.
   Server owns the ball; clients render a locally-simulated visual blended toward truth.
3. **Design for the 8-track Animator cap and 64-attribute cap now**, not after building
   animation layering.
4. **Never mix RemoteEvent results into predicted state** (~40–50 ms off the timeline).
   Predicted state goes in attributes.
5. **Buffer-serialize every per-frame packet** (Zap). 12 bytes packed vs ~30+ tagged.
6. **Rewind for hit validation** — validate saves/tackles against the shooter's timestamp, or
   you punish high-ping players for having ping.
7. **Watch ISR stats, not physics stats.**
8. **The pitch must not stream out** — client physics only simulates in streamed regions.
