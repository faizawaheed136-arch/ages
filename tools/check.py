#!/usr/bin/env python3
"""Static checks for the AGES tree. Run from the repo root: `python3 tools/check.py`.

Why this file exists
--------------------
Two people work on this tree at once and `rojo build` does not parse Luau, so the
usual "it builds" signal is worth almost nothing here. Everything below is a check
that has already caught a real defect in this repo at least once. Each one prints
findings and nothing else; the exit code is non-zero if any check found something,
so this is safe to wire into a hook later.

The single most important thing in here is `strip_code`. Every ad-hoc scanner
written for this repo so far has stripped `--` to end-of-line with a regex, and
every one of them has produced false positives, because this codebase is full of
backtick-interpolated strings like `Died at {age} -- {country}`. A regex stripper
eats the rest of that line and then reports `country` as an unused local. Three of
the seven findings in the last audit were that exact bug. So the stripper below is
a small character scanner that knows about the four string forms Luau has, and
every check is built on top of it rather than on a regex.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
# There is no aftman.toml, so nothing installs itself and both binaries are looked up
# at a fixed path under the user's home. The `.exe` suffix is the only difference
# between the macOS/Linux and Windows releases; without it a correctly installed
# Windows toolchain looks exactly like a missing one.
EXE = ".exe" if sys.platform == "win32" else ""
LUAU_COMPILE = Path.home() / f".aftman/tool-storage/luau/luau-compile{EXE}"
LUAU_ANALYZE = Path.home() / f".aftman/tool-storage/luau/luau-analyze{EXE}"
LUAU = Path.home() / f".aftman/tool-storage/luau/luau{EXE}"
ROJO = Path.home() / f".aftman/tool-storage/rojo-rbx/rojo/7.7.0/rojo{EXE}"
BUILD_TMP = Path(tempfile.gettempdir())


# --------------------------------------------------------------------------- #
# Lexing
# --------------------------------------------------------------------------- #


def strip_code(text: str) -> str:
    """Blank out comments and string bodies, preserving line and column numbers.

    Returns a string the same length as the input with comment and string-literal
    characters replaced by spaces (newlines kept), so a match offset in the result
    still maps to the right line in the original file.

    Handles: -- line comments, --[[ ]] and --[==[ ]==] block comments, '...' and
    "..." quoted strings with backslash escapes, [[ ]] long strings, and backtick
    interpolated strings -- whose `{...}` holes are *kept*, because the expressions
    inside them are real code and a variable used only inside an interpolation is
    not unused.
    """
    out: list[str] = []
    i, n = 0, len(text)

    def blank(s: str) -> str:
        return "".join(c if c == "\n" else " " for c in s)

    while i < n:
        c = text[i]
        two = text[i : i + 2]

        # Long-bracket opener, possibly preceded by `--` making it a block comment.
        m = re.match(r"--(\[=*\[)", text[i:]) or re.match(r"^(\[=*\[)", text[i:])
        if m:
            is_comment = text[i : i + 2] == "--"
            level = m.group(1).count("=")
            close = "]" + "=" * level + "]"
            end = text.find(close, i + m.end())
            end = n if end == -1 else end + len(close)
            out.append(blank(text[i:end]))
            i = end
            continue

        if two == "--":  # line comment
            end = text.find("\n", i)
            end = n if end == -1 else end
            out.append(blank(text[i:end]))
            i = end
            continue

        if c in "\"'":  # quoted string
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(c + blank(text[i + 1 : j - 1]) + (text[j - 1] if j - 1 < n else ""))
            i = j
            continue

        if c == "`":  # interpolated string: blank the literal parts, keep the holes
            out.append(" ")
            i += 1
            while i < n and text[i] != "`":
                if text[i] == "\\":
                    out.append("  ")
                    i += 2
                elif text[i] == "{":
                    depth, j = 0, i
                    while j < n:
                        if text[j] == "{":
                            depth += 1
                        elif text[j] == "}":
                            depth -= 1
                            if depth == 0:
                                j += 1
                                break
                        j += 1
                    out.append(text[i:j])  # kept verbatim -- this is code
                    i = j
                else:
                    out.append("\n" if text[i] == "\n" else " ")
                    i += 1
            out.append(" ")
            i += 1
            continue

        out.append(c)
        i += 1

    return "".join(out)


def luau_files() -> list[Path]:
    return sorted(p for p in SRC.rglob("*.luau"))


def line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


# --------------------------------------------------------------------------- #
# Checks
# --------------------------------------------------------------------------- #


def check_compile(files, code):
    """A syntax error anywhere on the boot path loads a place with no services in it."""
    # A missing tool is a FAILURE, not a skip. This used to `return 0`, which meant a
    # machine with no toolchain printed "all clean" and exited 0 with the only check
    # that catches a fatal error never having run -- the worst possible outcome on a
    # newly set-up box, where it reads as "the tree is fine" instead of "I checked
    # nothing". Every other check in this file is pure Python and cannot be skipped.
    if not LUAU_COMPILE.exists():
        print(f"  FAILED: {LUAU_COMPILE} missing -- this check did not run.")
        print("    Install luau-compile from the luau-lang/luau releases page")
        print(f"    ({'luau-windows.zip' if EXE else 'luau-macos.zip'}) to that path.")
        return 1
    bad = 0
    for f in files:
        # stdout is the compiled bytecode -- binary, and not utf-8 decodable, so it
        # goes to devnull rather than through `text=True`. Only stderr is read, and
        # only stderr carries the parse errors this check exists for.
        r = subprocess.run(
            [str(LUAU_COMPILE), "--binary", str(f)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        err = r.stderr.decode("utf-8", "replace").strip()
        if err:
            print(f"  {f.relative_to(ROOT)}\n    {err}")
            bad += 1
    return bad


def check_builds(files, code):
    """Both places, always. Plain `rojo build` only builds the game place."""
    if not ROJO.exists():
        print(f"  FAILED: {ROJO} missing -- this check did not run.")
        print("    Install rojo 7.7.0 from the rojo-rbx/rojo releases page to that path.")
        return 1
    bad = 0
    for project in ("default.project.json", "lobby.project.json"):
        if not (ROOT / project).exists():
            continue
        r = subprocess.run(
            [str(ROJO), "build", project,
             "-o", str(BUILD_TMP / f"agescheck-{project}.rbxl")],
            capture_output=True,
            text=True,
            cwd=ROOT,
        )
        if r.returncode != 0:
            print(f"  {project}: {(r.stderr or r.stdout).strip()}")
            bad += 1
    return bad


def _mounted_paths(project: Path) -> set[Path]:
    """Every `$path` in a project tree, resolved against the repo root."""
    found: set[Path] = set()

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "$path" and isinstance(value, str):
                    found.add((ROOT / value).resolve())
                else:
                    walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(json.loads(project.read_text()))
    return found


def check_mounts(files, code):
    """A generated asset that is in no project file is in no place.

    Both world checkers glob `assets/*.rbxmx`, so an unmounted asset is measured,
    reported green, and then not shipped -- the checkers are validating geometry
    that no player can stand in. That is exactly what happened to
    `SchoolFurniture.rbxmx`: it holds the four `AgesEvent` anchors for the four
    school life events, WorldEventService resolves anchors by tag and by nothing
    else, and the file was mounted in neither place. The four events existed in
    content, passed every check in this tree, and could never fire. Nothing else
    could see it -- `rojo build` only reports what a project *does* mention, and
    silence about a file it was never told about is not an error.
    """
    mounted: set[Path] = set()
    for project in ("default.project.json", "lobby.project.json"):
        if (ROOT / project).exists():
            mounted |= _mounted_paths(ROOT / project)
    bad = 0
    for asset in sorted((ROOT / "assets").glob("*.rbxmx")):
        # A directory mount covers everything under it, so ask about ancestors
        # too rather than only the file itself.
        if not any(p == asset or p in asset.parents for p in mounted):
            print(f"  assets/{asset.name} is mounted in no project file, "
                  f"so it is in neither built place")
            bad += 1
    return bad


def check_config(files, code):
    """Dangling `Config.X.Y` -- a nil index at runtime, invisible to the build."""
    cfg = code[SRC / "shared" / "Config.luau"]
    known: set[str] = set()
    # Table and scalar assignments: `Config.Work.Tasks = {`, `Config.Foo = 3`.
    for m in re.finditer(r"^\s*Config((?:\.\w+)+)\s*=", cfg, re.M):
        parts = m.group(1).strip(".").split(".")
        for i in range(len(parts)):
            known.add(".".join(parts[: i + 1]))
    # Function definitions: `function Config.Growth.At(...)`. Missing this was itself
    # a false-positive source -- it reported three live call sites as dangling.
    for m in re.finditer(r"^\s*function\s+Config((?:\.\w+)+)\s*\(", cfg, re.M):
        parts = m.group(1).strip(".").split(".")
        for i in range(len(parts)):
            known.add(".".join(parts[: i + 1]))
    # Keys inside a table literal are reachable too; approximate by collecting every
    # `Key =` at any depth and allowing any known prefix followed by it.
    inner = set(re.findall(r"^\s*(\w+)\s*=", cfg, re.M))

    bad = 0
    for f in files:
        if f.name == "Config.luau":
            continue
        for m in re.finditer(r"\bConfig((?:\.\w+)+)", code[f]):
            parts = m.group(1).strip(".").split(".")
            if parts[0] in {"new", "Get"}:
                continue
            head = parts[0]
            if head in known or head in inner:
                continue
            print(f"  {f.relative_to(ROOT)}:{line_of(code[f], m.start())}  Config.{'.'.join(parts)}")
            bad += 1
    return bad


def check_cycles(files, code):
    """Require cycles. Roblox resolves these into a nil module, not an error."""
    name_to_file = {}
    for f in files:
        key = f.stem if f.stem != "init" else f.parent.name
        name_to_file.setdefault(key, f)
    edges = defaultdict(set)
    for f in files:
        for m in re.finditer(r'require\(([^)]*)\)', code[f]):
            for part in re.findall(r'[\w"]+', m.group(1)):
                part = part.strip('"')
                if part in name_to_file and name_to_file[part] != f:
                    edges[f].add(name_to_file[part])
    colour: dict[Path, int] = {}
    found = 0

    def dfs(node, stack):
        nonlocal found
        colour[node] = 1
        stack.append(node)
        for nxt in edges[node]:
            if colour.get(nxt) == 1:
                cut = stack[stack.index(nxt) :]
                print("  " + " -> ".join(p.stem for p in cut + [nxt]))
                found += 1
            elif colour.get(nxt, 0) == 0:
                dfs(nxt, stack)
        stack.pop()
        colour[node] = 2

    for f in files:
        if colour.get(f, 0) == 0:
            dfs(f, [])
    return found


def check_remotes(files, code):
    """Remote names must appear in BOTH the RemoteName union and REMOTE_NAMES.

    A name in the list and missing from the union is a type error in two places at
    once -- the list literal and every `Remotes.Get` that spells it -- and yet the
    file compiles, both places build, and it works at runtime. Only the analyzer
    ever objects, which means only Studio ever objects. This has happened.
    """
    remotes = SRC / "shared" / "Remotes.luau"
    if remotes not in code:
        return 0
    src = code[remotes]
    union_block = re.search(r"export type RemoteName\s*=(.*?)\blocal\b", src, re.S)
    union = set(re.findall(r'"(\w+)"', union_block.group(1))) if union_block else set()
    list_block = re.search(r"REMOTE_NAMES[^=]*=\s*\{(.*?)\n\}", src, re.S)
    listed = set(re.findall(r'"(\w+)"', list_block.group(1))) if list_block else set()
    used = set()
    for f in files:
        used |= set(re.findall(r'Remotes\.\w+\(\s*"(\w+)"', code[f]))

    bad = 0
    for name in sorted(listed - union):
        print(f"  in REMOTE_NAMES but not in the RemoteName union: {name}")
        bad += 1
    for name in sorted(union - listed):
        print(f"  in the RemoteName union but never created: {name}")
        bad += 1
    for name in sorted(used - union):
        print(f"  Remotes.Get(\"{name}\") but not in the RemoteName union")
        bad += 1
    for name in sorted(union - used):
        print(f"  declared but nothing gets it: {name}")
        bad += 1
    return bad


def check_unused_locals(files, code):
    """Orphaned code. Two dead constants have already shadowed live ones elsewhere."""
    bad = 0
    for f in files:
        t = code[f]
        for m in re.finditer(r"^\s*local\s+([A-Za-z_]\w*)\s*(?::[^=\n]+)?=", t, re.M):
            name = m.group(1)
            if name.startswith("_"):
                continue
            uses = len(re.findall(r"(?<![.:\w])" + re.escape(name) + r"\b", t))
            if uses <= 1:
                print(f"  {f.relative_to(ROOT)}:{line_of(t, m.start())}  {name}")
                bad += 1
    return bad


def check_decl_order(files, code):
    """A name used above the `local` that defines it is a *global* read, not an error.

    Lua resolves names at compile time. A call written above the `local function` that
    defines it does not see the local at all -- it compiles to a global lookup and
    yields nil at runtime. Nothing else catches this: it is legal Luau so the syntax
    check passes, and `rojo build` never parses the file. The symptom is not a load
    failure but a specific feature dying on "attempt to call a nil value" the first
    time it runs. This check has already found exactly that in SchoolService.

    Only **calls** (`name(`) are reported, never bare references, and that limit is
    deliberate rather than lazy. A bare reference to a not-yet-declared local is the
    same bug, but this check has no scope analysis: it cannot tell a module-level
    local from one declared inside some other function further down the file, and
    those collide constantly. `band`, `spot`, `step`, `choice`, `era` are each a
    local in two unrelated functions here. Filtering out table keys, type fields,
    shadowing locals and function parameters still left twenty false positives and
    zero real ones -- so the reference rule was tried, measured, and removed.

    Doing it properly needs a real Luau parser tracking block scope. Until there is
    one, this catches the calls, which is the case that actually bit us.
    """
    bad = 0
    for f in files:
        t = code[f]
        decl: dict[str, int] = {}
        for m in re.finditer(r"^\s*local\s+(?:function\s+)?([A-Za-z_]\w*)", t, re.M):
            decl.setdefault(m.group(1), m.start())
        for name, at in decl.items():
            for m in re.finditer(r"(?<![.:\w])" + re.escape(name) + r"\s*\(", t):
                if m.start() < at:
                    print(
                        f"  {f.relative_to(ROOT)}:{line_of(t, m.start())}  {name} "
                        f"called above its declaration on line {line_of(t, at)}"
                    )
                    bad += 1
                    break
    return bad


# Names a file may call without defining: the Lua and Roblox globals. Anything not on
# this list and not defined in the file is a global lookup that yields nil.
#
# Deliberately short. The library tables -- math, string, table, task, os, bit32, utf8,
# coroutine, debug, buffer, Enum, Instance, Vector3, CFrame -- are absent on purpose: they
# are only ever *called through* a field (`task.wait`, `Instance.new`), and a field access
# is filtered out before the whitelist is consulted. A bare `math(` would be a bug.
LUA_GLOBALS = {
    "assert", "collectgarbage", "error", "getfenv", "getmetatable", "ipairs",
    "loadstring", "newproxy", "next", "pairs", "pcall", "print", "rawequal", "rawget",
    "rawlen", "rawset", "require", "select", "setfenv", "setmetatable", "tonumber",
    "tostring", "type", "typeof", "unpack", "xpcall",
    # Roblox's additions to the global table.
    "delay", "spawn", "tick", "time", "wait", "warn", "elapsedTime", "settings", "version",
    "setclipboard",
}

# Words that can legally sit immediately before a `(` without being a call.
LUA_KEYWORDS = {
    "and", "break", "continue", "do", "else", "elseif", "end", "export", "false", "for",
    "function", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then",
    "true", "until", "while",
}


def _balanced(text: str, start: int) -> int:
    """Index just past the `)` matching the `(` at `start`."""
    depth, i, n = 0, start, len(text)
    while i < n:
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


def _split_top(text: str) -> list[str]:
    """Split on commas that are not inside brackets."""
    parts, depth, current = [], 0, []
    for c in text:
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == "," and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(c)
    parts.append("".join(current))
    return parts


def _defined_names(t: str) -> set[str]:
    """Every name this file binds: locals, parameters, loop variables, globals it writes."""
    names: set[str] = set()

    # `local a, b: T = ...` and `local function f`. The whole list, not just the first
    # name -- a second name on a `local` line is as bound as the first.
    for m in re.finditer(r"(?<![.:\w])local\s+(?:function\s+)?([^=\n]+)", t):
        for part in _split_top(m.group(1)):
            hit = re.match(r"\s*([A-Za-z_]\w*)", part)
            if hit:
                names.add(hit.group(1))

    # Parameters, scanned with balanced brackets rather than `[^)]*` because a parameter
    # can be typed as a function -- `callback: (id: string) -> ()` -- and a naive scan
    # stops at the first `)` and loses every parameter after it.
    for m in re.finditer(r"(?<![.:\w])function\b", t):
        open_at = t.find("(", m.end())
        if open_at == -1:
            continue
        # Only if the `(` really belongs to this `function`: nothing but a name, dots,
        # colons and space may sit between them.
        if not re.fullmatch(r"\s*[\w.:]*\s*", t[m.end() : open_at]):
            continue
        for part in _split_top(t[open_at + 1 : _balanced(t, open_at) - 1]):
            hit = re.match(r"\s*([A-Za-z_]\w*)", part)
            if hit:
                names.add(hit.group(1))

    # Loop variables, both forms.
    for m in re.finditer(r"(?<![.:\w])for\s+([A-Za-z_][\w\s,]*?)\s*(?:=|\bin\b)", t):
        for part in m.group(1).split(","):
            names.add(part.strip())

    # A plain `name = ...` binds a global if there is no local in scope, and either way
    # the file has said what it means by that name. Counted so this check reports only
    # names the file never mentions on the left of anything.
    for m in re.finditer(r"(?<![.:\w=~<>])([A-Za-z_]\w*)\s*(?:,\s*[A-Za-z_]\w*\s*)*=(?!=)", t):
        names.add(m.group(1))

    return names


def check_undefined_calls(files, code):
    """A call to a name the file never defines. The other half of the nil-call bug.

    `check_decl_order` catches a local called *above* its own `local function`. It cannot
    catch a call to a name that is not in the file at all -- which is what a rename leaves
    behind, and this exact defect shipped: part two of the school rebuild renamed `begin`
    to `beginLesson` and missed the call in `ForceStart`. Legal Luau, so the syntax check
    passed; `rojo build` never parses; and the symptom would have been `/school start`
    dying on "attempt to call a nil value" while every other path in the file worked.

    Reports only calls, for the reason `check_decl_order` gives: a bare reference needs
    scope analysis this has none of. Over-collecting bound names is the safe direction --
    it can only hide a bug, never invent one -- so parameters, loop variables and plain
    assignments all count as definitions even where a real parser would scope them out.
    """
    bad = 0
    for f in files:
        t = code[f]
        names = _defined_names(t)
        seen: set[str] = set()
        for m in re.finditer(r"(?<![.:\w])([A-Za-z_]\w*)\s*\(", t):
            name = m.group(1)
            if name in seen or name in names or name in LUA_GLOBALS or name in LUA_KEYWORDS:
                continue
            seen.add(name)
            print(f"  {f.relative_to(ROOT)}:{line_of(t, m.start())}  {name} is called but never defined")
            bad += 1
    return bad


# Globals that are legitimately indexed and called without ever being bound in a file.
# Deliberately short: every name here is a hole in the check below, so a name earns its
# place by being a real Roblox global, not by being awkward.
INDEXED_GLOBALS = {
    "game", "workspace", "script", "shared", "math", "table", "string", "os", "task",
    "coroutine", "debug", "utf8", "bit32", "buffer",
    "Enum", "Instance", "Vector2", "Vector3", "Vector2int16", "Vector3int16",
    "CFrame", "Color3", "UDim", "UDim2", "Ray", "Rect", "Region3", "BrickColor",
    "TweenInfo", "NumberRange", "NumberSequence", "ColorSequence", "Random", "Faces",
    "Axes", "PhysicalProperties", "NumberSequenceKeypoint", "ColorSequenceKeypoint",
    "RaycastParams", "OverlapParams", "Font", "DateTime", "PathWaypoint", "SharedTable",
    "Content", "Path2D", "Secret", "CatalogSearchParams", "FloatCurveKey",
}


def check_undefined_modules(files, code):
    """`Thing.method(...)` where the file never binds `Thing`. A missing `require`.

    This is the third face of the nil-call bug and the most expensive one yet. The other
    two checks look for a bare `name(`; a missing require never looks like that, because
    the call is always written through the module -- `VerdictService.SetMoments(...)`.
    In Lua that reads a global, gets nil, and throws on the index.

    It shipped, twice, in one pass of the boot path:

      * `LifeService` called `VerdictService.SetMoments(...)` inside `Init` without ever
        requiring VerdictService. `init.server.luau` calls the Inits unguarded, so the
        throw took out every service declared after it and nothing was ever Started. The
        symptom is not an error naming LifeService -- it is a place that loads with no
        services in it at all, which is indistinguishable from a broken build.
      * `ReturnService` called `BodyService.Apply(player)` on the Studio arrival path,
        also unrequired, so every join in Studio threw after the life had been rolled.

    Both files listed the module by name in their comments, both read correctly to a
    human, and every other check in this file passed them.

    **The trailing call is not required, and requiring it was this check's own first bug.**
    Written to catch a missing `require`, it looked for `Name.method(` -- so it saw
    `VerdictService.SetMoments(...)` and was blind to `Lives.Active(profile.Data)`, where the
    undefined name is `profile` and it is merely *indexed*. That one cost a whole debugging
    pass: every player spawned adult-sized because `BodyService.onCharacterAdded` threw on
    `profile.Data`, a local the function never bound. Same nil index, same silence, one
    character of syntax different. So the `(` is optional and lowercase names count too --
    a discarded local reads exactly like a missing require to everything downstream of it.

    A bare *reference* still goes unreported (`x = Workspace`, with nothing after the name).
    That needs type-position analysis this has none of: `local p: Player = ...` would report
    `Player` on every file in the tree. Indexing is the line because indexing is what throws.
    """
    bad = 0
    for f in files:
        t = code[f]
        names = _defined_names(t)
        seen: set[str] = set()
        # Two shapes, and the colon may not be treated like the dot. A dot is always an
        # index, so `name.field` is enough on its own. A colon is *also* the type-annotation
        # separator, so a bare `name:field` matches every `id: string,` in every type table
        # in the tree -- the first cut of this widening reported ~400 of them. Only the
        # method-call form `name:method(` is an index, so the colon branch demands the call.
        pattern = r"(?<![.:\w])([A-Za-z_]\w*)\s*(?:\.\s*[A-Za-z_]\w*|:\s*[A-Za-z_]\w*\s*\()"
        for m in re.finditer(pattern, t):
            name = m.group(1)
            if name in seen or name in names or name in INDEXED_GLOBALS:
                continue
            if name in LUA_GLOBALS or name in LUA_KEYWORDS:
                continue
            seen.add(name)
            # A type alias is erased before anything runs, so `type X = Types.X` with Types
            # unrequired never throws -- it is an analyzer error, which means it is a Studio
            # error and nothing else in this pipeline will ever say a word about it. Same
            # missing require, same fix, different symptom, so say which one it is rather
            # than promising a crash that will not come and being disbelieved.
            line_start = t.rfind("\n", 0, m.start()) + 1
            in_type = re.match(r"\s*(?:export\s+)?type\s", t[line_start : m.start()]) is not None
            consequence = (
                "the type resolves to nothing and only Studio's analyzer will say so"
                if in_type
                else "this is a nil index at runtime"
            )
            print(
                f"  {f.relative_to(ROOT)}:{line_of(t, m.start())}  {name} is indexed but "
                f"never defined or required -- {consequence}"
            )
            bad += 1
    return bad


def check_unknown_globals(files, code):
    """A name read where nothing binds it, with real scope analysis behind the claim.

    Every regex check above is file-scoped: `_defined_names` collects `local profile` from
    *anywhere* in a file and calls `profile` defined *everywhere* in it. That is the safe
    direction for a regex, and it is also a hole you can drive a service through. It hid a
    live bug for as long as this file has existed:

        function BodyService.Apply(player)
            local profile = DataService.GetProfile(player)   -- binds it here ...

        local function onCharacterAdded(player, character)
            if DataService.WaitForProfile(player) == nil then end   -- ... and discards it here
            local data = Lives.Active(profile.Data)          -- so this is a nil global

    Every player spawned adult-sized, because that threw one line above the `Apply` call
    that is the whole point of the function. Three regex checks looked straight at it and
    saw a name the file binds.

    `luau-analyze` does the scoping properly, so this check hands the question to it and
    only filters the answer. CLAUDE.md warns that its output drowns in cascade noise
    without a Roblox definitions file, and that is true of the *type* errors -- but the
    `Unknown global` subset is different, and measurable: 3,600 of them across this tree
    resolve to exactly 27 distinct names, 22 of which are `Enum`, `game`, `script`, `task`
    and friends. Whitelisting those leaves pure signal. Every name it found on the first
    run was a real defect:

      * `BountyService.SetArrestedHandler` defined four lines above `local BountyService
        = {}` -- a nil index thrown at *module load*, in a file `init.server.luau`
        requires before it calls a single Init. Not a service that fails: a server that
        never starts. `check_decl_order` missed it because it looks for a name *called*
        too early and this is a name *defined* too early.
      * `bondGain` compared in PeopleService's defining-moment branch, bound nowhere.
      * `moneyPrevious` / `savingsBalance` behind the bank's deposit and withdraw
        buttons, so every one of them was a silent no-op.

    The whitelist is the two sets the regex checks already maintain, which is the point --
    one list of what a Roblox global is, consulted by everything that needs to know.
    """
    if not LUAU_ANALYZE.exists():
        print(f"  FAILED: {LUAU_ANALYZE} missing -- this check did not run.")
        print("    Install luau-analyze from the luau-lang/luau releases page")
        print(f"    ({'luau-windows.zip' if EXE else 'luau-macos.zip'}) to that path.")
        return 1
    known = LUA_GLOBALS | LUA_KEYWORDS | INDEXED_GLOBALS
    bad = 0
    for f in files:
        # `--solver=old` because the new solver reports these differently and this check
        # is calibrated against the old one's wording. Return code is ignored on purpose:
        # it is non-zero for the type-error cascade this check deliberately does not read.
        r = subprocess.run(
            [str(LUAU_ANALYZE), "--solver=old", str(f)],
            capture_output=True,
            text=True,
        )
        seen: set[str] = set()
        for line in (r.stdout + r.stderr).splitlines():
            m = re.search(r"\((\d+),\d+\): TypeError: Unknown global '([^']+)'", line)
            if m is None:
                continue
            name = m.group(2)
            if name in known or name in seen:
                continue
            seen.add(name)
            print(
                f"  {f.relative_to(ROOT)}:{m.group(1)}  {name} is read but nothing binds "
                f"it in scope -- nil at runtime"
            )
            bad += 1
    return bad


def _lua_string(s: str) -> str:
    """A Luau double-quoted literal for arbitrary source text."""
    out = s.replace("\\", "\\\\").replace('"', '\\"')
    out = out.replace("\n", "\\n").replace("\r", "\\r").replace("\0", "\\0")
    return '"' + out + '"'


def check_boot(files, code):
    """Does the server actually start? The only check here that runs the code.

    Everything else in this file reads the source. That is exactly how the game came to be
    unplayable for four days behind `Config.SubjectPerks = { [undefined] = nil }` -- legal
    syntax, a name nothing binds, and a `table index is nil` raised only when the module
    body *executes*. Config is required by every service in both places, so nothing loaded,
    and Roblox spawns a character regardless, so it presented as "I spawn normal size and
    cannot play" rather than as anything naming Config. Three static checks read that line
    and passed it. A fourth would have too.

    `tools/bootcheck.luau` rebuilds enough of a DataModel for `require` to resolve the way
    Rojo maps this repo, stubs the Roblox API, then requires `init.server.luau` -- which
    pulls in every service and drives the whole Init()/Start() lifecycle. Anything that
    throws while a module body runs is reported with the require chain that reached it.

    Scope, honestly: module bodies and the lifecycle calls, nothing else. No player, no
    character, no remote, no heartbeat. A bug that needs one of those is out of reach here
    and always will be. What this covers is "the server never started", which is the
    failure that looks like every other failure.
    """
    if not LUAU.exists():
        print(f"  FAILED: {LUAU} missing -- this check did not run.")
        print("    Install luau from the luau-lang/luau releases page to that path.")
        return 1
    harness = ROOT / "tools" / "bootcheck.luau"
    if not harness.exists():
        print(f"  FAILED: {harness} missing -- this check did not run.")
        return 1

    # Only the two trees the game place mounts. The lobby is a separate DataModel with its
    # own bootstrap and would need its own wiring; it is not silently folded in here,
    # because a harness that half-loads a place reports absences as failures.
    roots = [ROOT / "src" / "server", ROOT / "src" / "shared", ROOT / "vendor"]
    paths = sorted(
        p.relative_to(ROOT).as_posix()
        for r in roots
        if r.exists()
        for p in r.rglob("*.luau")
    )

    lines = ["local AGES_SOURCES = {}", "local AGES_MANIFEST = {}"]
    for rel in paths:
        src = (ROOT / rel).read_text(encoding="utf-8")
        lines.append(f"AGES_SOURCES[{_lua_string(rel)}] = {_lua_string(src)}")
        lines.append(f"table.insert(AGES_MANIFEST, {_lua_string(rel)})")
    prelude = "\n".join(lines) + "\n"

    bundle = BUILD_TMP / "ages-bootcheck.luau"
    bundle.write_text(prelude + harness.read_text(encoding="utf-8"), encoding="utf-8")

    # A wall-clock cap, because a module body that loops forever hangs the whole gate and
    # a gate that hangs gets removed from the hook rather than fixed. The harness has its
    # own `task.wait` budget for the common case; this is the backstop for the rest.
    try:
        r = subprocess.run(
            [str(LUAU), str(bundle)], capture_output=True, text=True, timeout=120
        )
        out = r.stdout + r.stderr
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or "") + (e.stderr or "")
        if isinstance(out, bytes):
            out = out.decode("utf-8", "replace")
        entered = [l for l in out.splitlines() if l.startswith("BOOTCHECK-ENTER")]
        where = entered[-1].split("\t")[1] if entered else "(before the first module)"
        print(f"  FAILED: the boot hung. Last module entered: {where}")
        return 1

    if "BOOTCHECK-END" not in out:
        entered = [l for l in out.splitlines() if l.startswith("BOOTCHECK-ENTER")]
        where = entered[-1].split("\t")[1] if entered else "(before the first module)"
        print(f"  FAILED: the harness died while loading {where} -- this check did not run.")
        for line in out.strip().splitlines()[-12:]:
            if not line.startswith("BOOTCHECK-ENTER"):
                print(f"    {line}")
        return 1

    bad = 0
    for line in out.splitlines():
        if not line.startswith("BOOTCHECK-FAIL\t"):
            continue
        _, rel, err, chain = line.split("\t", 3)
        print(f"  {rel}  {err}")
        print(f"    reached by: {chain}")
        bad += 1
    if bad == 0:
        loaded = next(
            (l.split("\t")[1] for l in out.splitlines() if l.startswith("BOOTCHECK-LOADED")),
            "?",
        )
        print(f"  clean -- {loaded} modules loaded and the lifecycle ran")
    return bad


CHECKS = [
    ("syntax (luau-compile)", check_compile),
    ("both places build (rojo)", check_builds),
    ("every asset is mounted", check_mounts),
    ("dangling Config refs", check_config),
    ("require cycles", check_cycles),
    ("remote name consistency", check_remotes),
    ("unused locals", check_unused_locals),
    ("declaration order", check_decl_order),
    ("calls to undefined names", check_undefined_calls),
    ("modules used but never required", check_undefined_modules),
    ("names read but never bound (scoped)", check_unknown_globals),
    ("the server actually boots", check_boot),
]


def main() -> int:
    files = luau_files()
    code = {f: strip_code(f.read_text()) for f in files}
    print(f"AGES check -- {len(files)} luau files\n")
    total = 0
    for title, fn in CHECKS:
        print(f"{title}:")
        found = fn(files, code)
        total += found
        if found == 0:
            print("  clean")
        print()
    print("FAILED" if total else "all clean")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
