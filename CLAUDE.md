# AGES

Roblox / Luau 3D open-world life simulator, Rojo-synced to Studio. Source in `src/`.

North star: an interactive, playable BitLife world — life as a game.

## Read these first

- **[`HANDOVER.md`](HANDOVER.md)** — three agents work on this tree across two machines.
  Which files you may touch, and which you may not, is decided there. If you were not
  told which agent you are, ask before editing anything.
- **[`docs/README.md`](docs/README.md)** — the settled design decisions. Most exist
  because something was built, rejected and rebuilt, and the rejection is the valuable
  part. Read before proposing a feature, not after it is turned down.

## Toolchain

Rojo 7.7.0 lives at `~/.aftman/tool-storage/rojo-rbx/rojo/7.7.0/rojo`. Plain `rojo`
fails — there is no `aftman.toml` in the repo. Run from `/Users/ayeshwaheed/ages`.

There is no `luau-lsp`, `selene` or `stylua` installed.

## Two places, two project files

The experience is two Roblox places and both have to be built and checked:

- `default.project.json` — the **game** place. `rojo build --output /tmp/ages.rbxlx`.
- `lobby.project.json` — the **lobby**, and the *start place*: this is where a player joins.
  `rojo build lobby.project.json --output /tmp/ages-lobby.rbxlx`.

`rojo build` with no argument only builds the game place, so a change that breaks the lobby
tree will pass unnoticed unless the second command is run too.

**`rojo serve` with no argument serves the game place, and this is a live hazard.** The
Studio plugin syncs whatever the server is serving into whatever place happens to be open —
it does not check that the two match and it gives no warning. Connecting a lobby place to a
plain `rojo serve` pours the whole town, all twenty services and every prop into the menu,
and the only cheap fix is to close without saving and reopen the built file. Always name the
project: `rojo serve lobby.project.json` for the lobby, plain `rojo serve` for the game, and
only ever one at a time on the default port 34872.

Three modules are mapped into *both* places by path rather than copied, and appear in the
lobby under `Server.shared`:

- `src/server/services/DataService.luau` — one definition of how a profile loads and locks.
- `src/server/content/Countries.luau` — one list of countries.
- `src/server/content/LifeSetup.luau` — one definition of what a valid life is, checked in
  the lobby where one is made and in the game place where `/setup skip` rolls one.

A mapped module may only `require` a sibling that is *also* mapped, next to it, under the
same name in both places. `LifeSetup` requires `script.Parent.Countries`, which resolves
because Countries is its sibling in `src/server/content/` and again in `Server.shared` —
so the two must stay mapped side by side. Any other `require` in a mapped file breaks the
lobby build.

The character menu lives in the lobby only. `src/server/services/SetupService.luau` is what
is left of it in the game place: the begin handler, `/setup skip`, and `NameOf`/`CountryOf`.
Dying does not restart a life in place — the life stays dead in its slot and the player is
teleported back to the lobby by `ReturnService`, which is also the arrival check for a player
who lands here with nothing to play.

`Config.Lobby.GamePlaceId` and `Config.Lobby.LobbyPlaceId` are `0` until the places are
published. Every path that needs one refuses by name rather than failing at a web call.

**`rojo build` does not parse Luau.** It only checks the file tree against
`default.project.json`, so it will happily build a file with a syntax error or a
`--!strict` violation in it. The first Studio sync is the real compiler. Anything
reported as "builds clean" has not been type-checked.

## Verifying a change without Studio

**Run `python3 tools/check.py` from the repo root.** It does everything in this section
in one pass — syntax, both builds, every asset mounted, dangling Config refs, require
cycles, remote-name consistency, unused locals, declaration order, calls to undefined
names — and exits non-zero if anything is wrong. Run it before you hand any change over. The rest of this
section is what it does and why, which matters when it reports something.

Four things it has already caught that nothing else could:

- `schoolFolder()` called forty lines above its `local function`, which is a *global* read
  in Lua and therefore nil. Legal Luau, so the syntax check passed; `rojo build` never
  parses; the symptom would have been every lesson in the game dying on "attempt to call a
  nil value" the first time a teacher spawned.
- Two remote names in `REMOTE_NAMES` and missing from the `RemoteName` union. Compiles,
  builds, and works at runtime — only the analyzer objects, which means only Studio does.
- `begin(player, ...)` left behind in `SchoolService.ForceStart` after the function was
  renamed to `beginLesson`. Same nil-call class as the first, but the name is nowhere in
  the file at all, so the declaration-order check could never see it. It shipped, and
  `/school start` would have died the first time it ran.
- `assets/SchoolFurniture.rbxmx` mounted in neither project file, so the four `AgesEvent`
  anchors for the four school life events were in no built place and those events could
  never fire. `rojo build` reports on what a project *does* mention; silence about a file
  it was never told about is not an error. Worse, both world checkers glob `assets/*.rbxmx`
  and had been reading it, measuring it and calling it green the whole time — a checker
  that discovers its own inputs will certify a file that ships nowhere.

It is deliberately not a linter. Every check in it is there because that exact defect
already shipped into this tree at least once, and anything that produced false positives
was removed rather than tuned — see the comment on `check_decl_order` for one that was
tried, measured and dropped. If you add a check, hold it to the same bar: a scanner nobody
trusts is a scanner nobody runs.

`tools/check_city.py` and `tools/check_town.py` are a separate thing — they validate the
generated world geometry, not the Luau. Run both when the world changes; they cover
different halves of it and almost nothing in one is asking about the other's. Most of
`check_city`'s checks are scoped to the city by construction and their names do not say
so, which is why the town needed its own gate rather than more entries in that file.

**Syntax-check every file first. This is the only check that catches a fatal error.**
`luau-compile` lives at `~/.aftman/tool-storage/luau/luau-compile` (from the official
`luau-lang/luau` release; re-download `luau-macos.zip` if it goes missing):

```
for f in $(find src -name '*.luau'); do
  out=$(~/.aftman/tool-storage/luau/luau-compile --binary "$f" 2>&1 >/dev/null)
  [ -n "$out" ] && { echo "=== $f"; echo "$out"; }
done
```

A syntax error in one module is not a local problem. `require` propagates the error to the
caller, so a bad file anywhere on the boot path kills the whole server — and the symptom is
not an error about that file, it is a place that loads with no services in it at all. This
has already happened once: a chained `data :: any :: { [string]: any }` in `DataService`
(Luau allows at most **one** `::` per expression — parenthesise it) took down both places at
once, and looked exactly like a broken lobby and a broken game.

`luau-analyze --solver=old` also runs, but without a Roblox definitions file every `Player`,
`game` and `task` is an unknown symbol and the real errors drown in the cascade. Filter out
`Unknown global|Unknown require|Unknown type|Unknown symbol` and read what is left with
suspicion — most of it is still error-type noise.

Then `rojo build` plus a Python pass over `src/`:

1. **Dangling `Config.X.Y` refs** — resolve every `Config.` access against
   `src/shared/Config.luau`. The resolver must handle both table assignments
   (`Config.Work.Tasks = {`) and top-level scalar assignments.
2. **Require cycles** — DFS over `require(...)` edges. 55 modules currently.
3. **Declaration order** — a local function used above its definition. Regex
   `(?<![.:\w])name\s*\(`, and it **must strip `--` comments first** or it reports
   prose as calls.
4. **Calls to undefined names** — the same nil call, but to a name the file never binds
   at all, which is what a half-finished rename leaves behind. Collect every name the
   file binds (locals, parameters, loop variables, plain assignments), then report any
   `name(` that is not one of them, not a Lua/Roblox global and not a keyword. Parameter
   lists must be scanned with balanced brackets — a parameter typed as a function,
   `callback: (id: string) -> ()`, defeats a `[^)]*` scan and loses every parameter
   after it, which reads as a false positive on a perfectly good call.

Also worth doing by hand: grep every consumer of a field you changed. A field that
is written and never read is orphaned code, and the build will not tell you.

## Conventions

- `--!strict` at the top of every file. `--!strict` rejects extra fields in a table
  literal returned against an annotated return type — a common latent break.
- Shared types live in `src/shared/Types.luau`. Structural typing means two types with
  the same shape are interchangeable, so adding a field to both ends of a
  server→client hop often needs no plumbing.
- **No magic numbers in logic files.** Every tunable goes in `src/shared/Config.luau`
  with a comment saying what it does and a safe range.
- State changes are atomic and server-authoritative. Persistence is ProfileStore.
  `StreamingEnabled` is on.
- Idempotency wherever a retry is possible: decide the outcome before any write, then
  record it, rather than writing and unpicking.
- Every new system ships with a debug path. Debug commands live in
  `src/server/services/DebugService.luau`.
- Comment the *why*, not the *what*. No orphaned code — delete it rather than leaving
  it unreferenced.
- No silent failures. Content errors should `error()` with a message that names the
  offending id and says what to do about it.

## Content rules

13+: no gambling, no gore. All audiences, US English. Failure should be worth playing.

**Combat is allowed.** This line used to read "no combat" and stated it as a platform
constraint. That was wrong: Roblox permits combat at 13+, and the biggest games on the
platform are built on it — Blox Fruits is 13+ and fights for a living. It was a design
preference dressed up as a rule, and the owner has overruled it. What the rating actually
forbids is *gore*: no blood, no dismemberment, no realistic injury, no death animations
that dwell. A fight is a contest with a winner, and it ends with somebody on the floor and
back up again. Weigh new combat against that, not against a ban that does not exist.

**The 13+ rating is still a hard ceiling — any feature that would push the game to 17+ is
off the table, permanently, not deferred.** The romantic-partner / dating system was scrapped
for exactly this reason: a partner is the one relationship the game cannot write and stay
13+. The tie ladder therefore stops at friendship (`known` → `friend` → `closest friend`)
and climbs no further; if the top rung ever wants to grow, the rung above `closest` has to
be something a 13+ life can hold — a mentor, a rival, a sibling you chose — not a partner.
Weigh every new relationship, event, or mechanic against this before building it.

## Interaction grammar

Choices are a three-dot marker above a character's head that opens a panel — not
pads on the floor to walk onto. Floor markers still exist for *destinations* (shift
marks, job pads, event anchors); they are not an answering surface.

Walk-onto discs cannot carry a price. The price column lives in
`src/client/ui/ChoicePanel.luau`, which also renders a `note` in that same column when
there is no cost. One column, one thing in it.
