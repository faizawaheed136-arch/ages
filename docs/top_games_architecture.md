# AGES: architecture patterns from Roblox's top games (researched 2026-08-19)

Companion to [`roblox_engineering.md`](roblox_engineering.md) rather than a replacement for it —
that file covers the platform-capability half (Server Authority GA, animation/pathfinding caps,
DataStore budgets). This one covers the *architecture* half: how the highest-scale, longest-lived
Roblox games are actually structured, sourced from Roblox's own engineering docs, the games'
public dev-blog and DevForum material, and third-party engineering write-ups that quote them
directly. Nothing here contradicts `roblox_engineering.md`; where the two overlap (Server
Authority, ProfileStore) this file only adds what the other one doesn't already have.

## Service architecture: the field has converged on what AGES already does

Knit (Sleitnick's service/controller framework) was the default recommendation for years. It has
now stopped receiving updates, and the criticism that finally stuck is structural rather than
cosmetic: Knit resolves services by string name into generic tables, which loses intellisense and
turns services into "secret global-state containers" — and it is reportedly miserable to unit-test,
because Hoarcekat testing against a Knit service means fighting side effects wired in everywhere.
`roblox_engineering.md` already reached this conclusion independently in the sports research pass.
The pattern large codebases converge on instead, confirmed across multiple independent guides:

- **Three top-level folders and nothing else**: server Services in `ServerScriptService`, client
  Controllers in `StarterPlayerScripts`, shared modules in `ReplicatedStorage`. AGES's
  `src/server/services`, `src/client`, `src/shared` split is exactly this — not a simplification,
  the actual shape production codebases use.
- **A central bootstrap that requires and initializes every service in a fixed order**, rather than
  services requiring each other freely. AGES does this in `src/server/init.server.luau`.
- **Dependency injection through explicit setter functions to break require cycles**, not a DI
  container. AGES's `EventService.SetAgeUpHandler` / `SetEnactHandler` / `SetSceneHandler` /
  `SetActHandler` and `SetupService.SetBeginHandler` are this pattern by name. The alternative —
  services requiring each other directly — is what produces the require cycles `tools/check.py`'s
  cycle detector exists to catch.
- **One module owns one domain and exposes a narrow API**; nothing reaches into another service's
  internal tables. AGES's rule that `BountyService` never requires `PoliceService` (or vice versa)
  and both only ever call through a handful of named public functions is this same discipline.

The one gap worth naming: AGES has zero automated tests. The reason large-scale guides keep landing
on "server Services, client Controllers, shared modules" is partly that it is the layout Jest-Lua /
Lune headless testing wants — pure-logic modules with no DataModel dependency are trivially testable
in that shape and much harder to test in a framework that resolves everything through a runtime
registry. `roblox_engineering.md`'s CI section already flags this; nothing has changed it.

## Networking: the pattern AGES's own Remotes.luau header already argues for, confirmed at scale

A guide aggregating real production incident patterns puts numbers on what `Remotes.luau`'s header
comments assert by argument alone:

- **RemoteEvent is the default for roughly 90% of traffic; RemoteFunction should be under 10%
  combined**, and server-side `RemoteFunction` in particular should be rare and audited — a
  yielding server-side invoke can be stalled indefinitely by a client that simply never answers.
  AGES has zero RemoteFunctions. Every remote in `Remotes.luau` is fire-and-forget in one direction,
  which is ahead of the curve rather than a simplification.
- **The five-step server-authoritative pipeline**: client sends *intent* (never an outcome) → server
  validates against its own state → server mutates state atomically → server fans results out →
  client reconciles by interpolating, never teleporting. This is precisely what `Remotes.luau`'s own
  comments describe for `RequestSpin` ("nothing on this wire a client could have forged the result
  of") and `RequestFightAction` ("the strongest thing a forged packet can claim is that a button went
  down") — AGES independently arrived at the industry pattern, not a simplification of it.
- **73% of exploit reports in 2025 traced back to a client-trusted RemoteEvent** the developer had
  assumed was an internal API rather than public attack surface. The rule this argues for — treat
  every remote handler as though it receives hostile input from the open internet, because it
  does — is already AGES's stated convention (every `OnServerEvent` handler in the services read for
  this doc type-checks its arguments before touching state), but it is worth stating as a standing
  rule rather than an emergent one, because it is the single highest-leverage line item in this file.
- **Bandwidth budget is roughly 50 KB/s outbound per client.** The two levers to stay under it are
  interest management (only replicate to clients who could plausibly care — AGES's per-player
  `JobPostsUpdated`/`GuideUpdated` pattern is this) and delta compression / digest-before-push (AGES's
  own `pushed[player]` digest pattern in `BountyService`, `TheftService`, `BankService`, `GangService`
  and `FightService` — comparing a cheap string before firing — is exactly this, independently
  reached, and worth keeping as a house convention rather than something to "clean up" later.

## Data persistence: ProfileService → ProfileStore, and what changed between them

`roblox_engineering.md` already covers ProfileStore's autosave interval (300s vs ProfileService's
30s, ~10x fewer DataStore calls) and the per-experience budget change. Worth adding: ProfileStore is
the direct successor to ProfileService from the same author, with one structural improvement that
matters for a multi-agent tree like this one — its session-lock handling is "more responsive at
resolving conflicts between servers," which is the failure mode a shared save is most exposed to
when two servers (or, here, two development machines) can plausibly both hold a lock at once.

The pattern worth calling out because AGES doesn't have this problem yet but will the moment trading
or PvP economy exists between *players* rather than between a player and the world: **item/currency
duplication is a trade-lock problem, not a DataStore problem.** The concrete shape every write-up
converges on:

1. A trade (or any multi-party mutation) is validated in full *before* anything is written — decide,
   then write, never the reverse. This is already AGES's own stated house rule
   ("`Idempotency wherever a retry is possible: decide the outcome before any write`" in
   `CLAUDE.md`) — the research confirms it is the correct rule, not merely a stylistic preference.
2. Both sides of a multi-party mutation are locked for the duration of the transaction, and the whole
   thing either completes or fails atomically — never "give player A's item, then try to give player
   B's" as two separate steps a crash could land between.
3. One unpatched dupe in an economy-driven game can, per one write-up bluntly, "mint enough phantom
   [items] in 48 hours to crater the secondary market and force a full economy rollback" — the
   asymmetry between how cheap a dupe bug is to write and how expensive it is to have shipped is why
   this gets a whole layer of validation rather than a single check.

AGES has no player-to-player trading today (the closest is gang standing and shared bank-heat, both
of which are already one-way, server-computed, and never client-asserted), so this is forward-looking
rather than a gap — but it is the first thing to design correctly, not retrofit, the day a trade
verb is proposed for anything.

## Anti-exploit at economy scale: the four-layer shape

Aggregated from several production-pattern write-ups, the validation pipeline every remote handler
in an economy-bearing game should run, in order:

1. **Type/shape validation at the door** — reject anything that isn't the expected type before it
   touches any other logic. AGES already does this (every handler checks `typeof(x) ~= "string"` etc.
   before proceeding) — this is table stakes, not a gap.
2. **Sanity checks against the server's own authoritative state** — balance, ownership, cooldown,
   position — never against anything the client asserted. Also already AGES's pattern throughout.
3. **Per-player, per-remote rate limiting**, calibrated to "the maximum legal use-rate plus a small
   buffer for network jitter" — e.g. a button that can legally fire twice a second gets a cap of
   three. **This is the one layer AGES does not have anywhere in the tree.** Every remote handler
   read for this doc trusts `RemoteEvent`'s own implicit throttling (Roblox's ~500 req/s per client,
   shared across all remotes of that type) and nothing per-remote. That ceiling is far too loose to
   stop a scripted client from, for instance, spamming `RequestTillHold` or `RequestBankHold` faster
   than a human ever could — worth a token-bucket utility in `shared/` the day any remote's abuse
   ceiling matters more than "the server already clamps the outcome," which is most of them, but not
   all: a bot holding `RequestFightAction` at inhuman frequency, or hammering `RequestGangChoice`,
   costs nothing today because the state machines already reject an illegal transition — but a
   *legal* action taken at an inhuman rate (e.g. a scripted `RequestRep` press pattern that always
   lands in the gym's sweet zone) is exactly the class of exploit rate limiting catches and pure state
   validation does not.
4. **Background behavioral heuristics** — a sweeper that watches for statistical anomalies rather
   than single-request violations (a player whose gym reps are all frame-perfect, a player whose
   theft sessions never once get spotted). AGES has no telemetry layer of any kind yet; this is the
   most expensive layer to build and the one every source treats as optional until the game has real
   money moving through it.

The concrete anti-pattern list is worth keeping as a checklist for any new remote: currency ever
held in a client-readable variable, hit/outcome confirmation fired from the client rather than
computed by the server, trusting a reported position without validating it server-side, and — named
explicitly as the mistake teams make on purpose — skipping rate limits on a game "too small to be
worth exploiting." AGES is pre-launch, which is exactly the moment that argument is most often made
and most often wrong.

## Multi-server state: not a problem AGES has yet, but worth designing around correctly

Every Roblox game above a few hundred concurrent players is not one server — it is a fleet of
independent server processes, each with its own local Lua state, sharing nothing by default. At
50 or so players per server, roughly one-fourteenth of a title's concurrent audience is looking at
any single instance's world. AGES's per-place single-server model (one game place, one lobby place,
no cross-server anything) is correct for its current scale and is not a simplification to apologize
for — but the three primitives every game reaches for once it needs servers to agree on something are
worth having named before the first feature that needs one is designed under time pressure:

- **MessagingService** — a publish/subscribe channel across servers. ~150ms typical latency, roughly
  150 messages/minute per server and 60/minute per topic, 1KB payload cap, and **no delivery
  guarantee** — a subscriber can simply miss a message, so anything built on it must be idempotent on
  the receiving end (safe to process the same message twice, and correct after missing one entirely).
- **MemoryStore** — Redis-style key/value state shared across every server in an experience, with
  sub-50ms reads, atomic operations, and native structures including a SortedMap. The concrete pattern
  for a cross-server leaderboard: write `(id, score)` with `UpdateAsync` using a *max-of-current-and-new*
  transform rather than a plain overwrite, which is what stops two servers' simultaneous writes from
  losing whichever one lands second. Data evicts after 30 days at the outside, sooner under memory
  pressure — it is a cache for hot state, never the record of truth.
- **`TeleportService:ReserveServer()`** — a private server instance keyed to an access code, for
  matchmaking or an instanced activity. The gotcha every guide flags: a reserved instance survives
  roughly 30 seconds after the last player leaves, so a matchmaker has to mint a fresh code per
  session rather than assume an old one is still good.

The classification rule worth carrying forward if AGES's gangs ever grow the deferred territory/city-map
layer `gangs_spec.md` already flags as future work: decide, per piece of state, whether it is
**strongly consistent** (must never disagree between servers — this wants DataStore with a lock, the
ProfileStore pattern AGES already has), **eventually consistent** (a shared leaderboard, a gang's
total territory count — MemoryStore is the right tool), or **genuinely server-local** (an individual
chase's search radius, a till's clerk-glance cycle — no cross-server primitive needed at all, and
reaching for one would be the wrong tool). Most of what AGES tracks today — a life's own bounty,
standing, bonds — is correctly server-local by construction, because it belongs to one player's one
active session; the one place this taxonomy will bite is the day "one gang can hold territory the
whole server agrees on" needs to become "one gang holds territory every server agrees on."

## Streaming, at the scale of an actual built city

`roblox_engineering.md` already covers the streaming property names and budgets. Worth adding the
one structural fact every open-world write-up leads with: **Roblox has no built-in world chunking or
level-of-detail system** — `StreamingEnabled` streams *instances* in and out by distance, but nothing
scales an asset's fidelity down at range the way Unreal or Unity would, and nothing partitions the
world into engine-managed cells. Both are the developer's job, which is exactly why `MAP_PLAN.md`'s
own recurring bug class (a literal coordinate measured once and typed in, silently wrong the next
time the grid changes) is a streaming-adjacent risk as much as a geometry one — every hand-placed
`PlacePointTag` and delivery point is itself a piece of manual world-partitioning that a chunking
system would otherwise be managing.

The other fact worth carrying into any future work on `gen_city.py`'s crowd or traffic systems: server
load from streaming does not scale linearly with players in one place — when a cluster of players
converges on one region (a bank robbery drawing a crowd, a gang boss's corner, a shift's rush task),
load spikes non-linearly rather than by headcount, because everyone in range is now replicating the
same dense region to each other simultaneously. AGES's per-player NPC/visitor spawning (till clerks,
bank guards, gang bosses shared per-post rather than per-player) already avoids the worst version of
this by not multiplying rig counts with player counts in the first place — worth keeping as the
default instinct for anything spawned in response to a player converging on a place, rather than
retrofitting a population cap after a bank robbery with six players in it turns out to be expensive.

## What it looks like at the very top of the platform

One concrete data point, since AGES has nothing to compare its own numbers against yet: Pet Simulator
99's publicly described backend serves roughly **1.5 million concurrent players across thousands of
server instances**, with real-time economy tracking (hatching, trading, purchasing) feeding forensic
tooling built specifically to trace duplication exploits across millions of trades, plus
error-aggregation and anomaly detection spanning the whole distributed fleet. Notably, that team's
lead developer has publicly documented a correctness issue in Roblox's own DataStore write semantics
— the lesson being less "here is a number to aim for" and more that even the platform's own
persistence primitives have had bugs sophisticated teams found by operating at genuine scale, which
is one more argument for treating ProfileStore's documented behavior as the contract rather than
assuming a wire-level guarantee it doesn't make.

## The short list, if AGES only takes five things from this

1. **Add per-remote rate limiting.** It is the one layer from the four-layer anti-exploit shape
   AGES is missing entirely, and it is cheap: a shared token-bucket module in `src/shared/`, called
   from the handful of remotes where a legal action taken at an illegal rate is the actual exploit
   surface (rep timing in the gym, theft/bank hold spam, fight action spam).
2. **Keep the digest-before-push pattern as a named house convention**, not an incidental
   optimization — it is already load-bearing for bandwidth and it is already correct.
3. **Never build a trade verb without the lock-both-sides-atomically pattern from day one.** Retrofitting
   it onto a shipped trade system is where the cited 48-hour-economy-collapse failure mode lives.
4. **When territory/cross-server gang state gets built**, classify each field as
   strongly-consistent / eventually-consistent / server-local *before* writing it, and reach for
   DataStore-with-lock, MemoryStore, or nothing accordingly — not "however the till and bank rooms
   already do sharing," which is a single-server pattern that does not generalize across instances.
5. **Treat every remote handler as public internet input, permanently** — not as an increasingly
   trusted internal API as the codebase grows, which is how 73% of the exploits in the cited industry
   figure got in.
