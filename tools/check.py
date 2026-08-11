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

import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
LUAU_COMPILE = Path.home() / ".aftman/tool-storage/luau/luau-compile"
ROJO = Path.home() / ".aftman/tool-storage/rojo-rbx/rojo/7.7.0/rojo"


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
    if not LUAU_COMPILE.exists():
        print(f"  SKIPPED: {LUAU_COMPILE} missing (re-download luau-macos.zip)")
        return 0
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
        print(f"  SKIPPED: {ROJO} missing")
        return 0
    bad = 0
    for project in ("default.project.json", "lobby.project.json"):
        if not (ROOT / project).exists():
            continue
        r = subprocess.run(
            [str(ROJO), "build", project, "-o", f"/tmp/agescheck-{project}.rbxl"],
            capture_output=True,
            text=True,
            cwd=ROOT,
        )
        if r.returncode != 0:
            print(f"  {project}: {(r.stderr or r.stdout).strip()}")
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


CHECKS = [
    ("syntax (luau-compile)", check_compile),
    ("both places build (rojo)", check_builds),
    ("dangling Config refs", check_config),
    ("require cycles", check_cycles),
    ("remote name consistency", check_remotes),
    ("unused locals", check_unused_locals),
    ("declaration order", check_decl_order),
    ("calls to undefined names", check_undefined_calls),
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
