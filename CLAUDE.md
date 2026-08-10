# AGES

Roblox / Luau 3D open-world life simulator, Rojo-synced to Studio. Source in `src/`.

North star: an interactive, playable BitLife world — life as a game.

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
in one pass — syntax, both builds, dangling Config refs, require cycles, remote-name
consistency, unused locals, declaration order — and exits non-zero if anything is wrong.
Run it before you hand any change over. The rest of this section is what it does and why,
which matters when it reports something.

Two things it has already caught that nothing else could:

- `schoolFolder()` called forty lines above its `local function`, which is a *global* read
  in Lua and therefore nil. Legal Luau, so the syntax check passed; `rojo build` never
  parses; the symptom would have been every lesson in the game dying on "attempt to call a
  nil value" the first time a teacher spawned.
- Two remote names in `REMOTE_NAMES` and missing from the `RemoteName` union. Compiles,
  builds, and works at runtime — only the analyzer objects, which means only Studio does.

It is deliberately not a linter. Every check in it is there because that exact defect
already shipped into this tree at least once, and anything that produced false positives
was removed rather than tuned — see the comment on `check_decl_order` for one that was
tried, measured and dropped. If you add a check, hold it to the same bar: a scanner nobody
trusts is a scanner nobody runs.

`tools/check_city.py` is a separate thing — it validates the generated `City.rbxmx`
geometry, not the Luau. Both are worth running when the world changes.

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

13+: no combat, no gambling, no gore. All audiences, US English. Failure should be
worth playing.

**The 13+ rating is a hard ceiling — any feature that would push the game to 17+ is off
the table, permanently, not deferred.** The romantic-partner / dating system was scrapped
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
