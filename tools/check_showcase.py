#!/usr/bin/env python3
"""Gate for the Gakuran showcase place.

Four things, in the order they can go wrong:

  1. every showcase module compiles
  2. the plan's arithmetic holds -- bands sum to the footprint, no room overlaps another,
     the stair climbs exactly one storey with a riser a humanoid can walk
  3. the shell actually lays parts, with the extent the plan says it should
  4. the place builds under rojo

(3) is the one worth having. This repo has already shipped a bake that wrote **zero parts and
reported success**, because the harness returned a permissive stub for a failed require and the
builder became a callable table that did nothing. A gate that only checks "it ran" cannot see
that. So the stub environment here *keeps* what it is given, and the check is on the geometry
that comes out rather than on the absence of an error.

Nothing in here touches v1, ProperSchool or SchoolV1Copy.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LUAU = Path.home() / ".aftman/tool-storage/luau" / ("luau.exe" if sys.platform == "win32" else "luau")
LUAU_COMPILE = LUAU.with_name("luau-compile.exe" if sys.platform == "win32" else "luau-compile")
ROJO = Path.home() / ".aftman/tool-storage/rojo-rbx/rojo/7.7.0" / ("rojo.exe" if sys.platform == "win32" else "rojo")
SRC = ROOT / "src/showcase"

failures: list[str] = []


def report(name: str, ok: bool, detail: str = "") -> None:
    print(f"  {'OK  ' if ok else 'FAIL'}  {name}{'  --  ' + detail if detail else ''}")
    if not ok:
        failures.append(name)


# ---------------------------------------------------------------- 1. syntax
def check_compiles() -> None:
    print("\n1. Every showcase module compiles")
    files = sorted(SRC.rglob("*.luau"))
    bad = []
    for path in files:
        # --binary writes the bytecode to stdout, so decode leniently: we only want the
        # return code and the first line of stderr.
        r = subprocess.run([str(LUAU_COMPILE), "--binary", str(path)],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        if r.returncode != 0:
            bad.append(f"{path.relative_to(ROOT)}: {r.stderr.strip().splitlines()[0] if r.stderr.strip() else 'failed'}")
    for line in bad:
        print(f"        {line}")
    report(f"{len(files)} modules", not bad, f"{len(bad)} failed" if bad else "")


# ---------------------------------------------------------------- 2 + 3. the plan and the shell
# A stub environment that *remembers*. Every value the builder assigns has to survive, or the
# geometry check below reads an empty part and calls a broken shell fine.
HARNESS = r"""
local recorded = {}

local function vec(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, {
		__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
		__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
	})
end
Vector3 = { new = vec, zero = vec(0, 0, 0) }
Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end }
CFrame = { new = function(p) return { Position = p } end, identity = {} }

local EnumStub = setmetatable({}, { __index = function(t, k)
	return setmetatable({}, { __index = function() return { Name = k } end })
end })
Enum = EnumStub

local partMeta = {}
partMeta.__index = partMeta
local function newPart(class)
	return setmetatable({ ClassName = class, Name = "", Children = {} }, partMeta)
end
partMeta.__newindex = function(self, key, value)
	if key == "Parent" then
		rawset(self, "Parent", value)
		if type(value) == "table" and value.Children then table.insert(value.Children, self) end
		if self.ClassName == "Part" then table.insert(recorded, self) end
	else
		rawset(self, key, value)
	end
end

Instance = { new = function(class) return newPart(class) end }
local workspaceFolder = newPart("Workspace")
workspace = workspaceFolder
workspace.FindFirstChild = function() return nil end

-- module resolution: script.Parent.X returns the module we loaded by that name
local MODULES = {}
local function fakeScript(name)
	local parent = setmetatable({}, { __index = function(_, k) return MODULES[k] end })
	return { Parent = parent, Name = name }
end
local realRequire = require
function require(m) return m end

__PLACEHOLDER__

print("PARTS " .. tostring(#recorded))
local minx, miny, minz = math.huge, math.huge, math.huge
local maxx, maxy, maxz = -math.huge, -math.huge, -math.huge
for _, p in recorded do
	local c, s = p.CFrame and p.CFrame.Position, p.Size
	if c and s then
		minx = math.min(minx, c.X - s.X / 2); maxx = math.max(maxx, c.X + s.X / 2)
		miny = math.min(miny, c.Y - s.Y / 2); maxy = math.max(maxy, c.Y + s.Y / 2)
		minz = math.min(minz, c.Z - s.Z / 2); maxz = math.max(maxz, c.Z + s.Z / 2)
	end
end
print(("EXTENT %g %g %g %g %g %g"):format(minx, maxx, miny, maxy, minz, maxz))
"""


def run_shell() -> tuple[int, list[float]]:
    plan = (SRC / "world/Plan.luau").read_text(encoding="utf-8").replace("\nreturn Plan\n", "\n")
    kit = (SRC / "world/Kit.luau").read_text(encoding="utf-8").replace("\nreturn Kit\n", "\n")
    shell = (SRC / "world/Shell.luau").read_text(encoding="utf-8")
    shell = shell.replace("local Plan = require(script.Parent.Plan)", "")
    shell = shell.replace("local Kit = require(script.Parent.Kit)", "")
    shell = shell.replace("\nreturn Shell\n", "\n")

    body = "\n".join([
        plan, kit, shell,
        "Shell.Build(Vector3.new(-Plan.WidthStuds / 2, 0, -Plan.DepthStuds / 2))",
    ])
    script = Path(os.environ.get("TEMP", "/tmp")) / "showcase_shell.luau"
    script.write_text(HARNESS.replace("__PLACEHOLDER__", body), encoding="utf-8")

    r = subprocess.run([str(LUAU), str(script)], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
    if r.returncode != 0:
        print("        " + (r.stderr.strip().splitlines() or ["failed"])[0])
        return 0, []
    parts, extent = 0, []
    for line in r.stdout.splitlines():
        if line.startswith("PARTS "):
            parts = int(line.split()[1])
        elif line.startswith("EXTENT "):
            extent = [float(v) for v in line.split()[1:]]
    return parts, extent


def check_plan_and_shell() -> None:
    print("\n2. The plan's arithmetic")
    plan_src = (SRC / "world/Plan.luau").read_text(encoding="utf-8").replace("\nreturn Plan\n", "\n")
    asserts = r"""
local out = {}
local function t(name, cond) table.insert(out, (cond and "ok " or "no ") .. name) end
local E = Plan.Edge
t("bands sum to the footprint", Plan.WidthStuds == 400 and Plan.DepthStuds == 448)
t("edge lists close on the footprint", Plan.X[#Plan.X] == Plan.WidthStuds and Plan.Z[#Plan.Z] == Plan.DepthStuds)
t("corridor is 24 wide", Plan.Z[E.CorridorInner] - Plan.Z[E.BandInner] == Plan.CorridorStuds)
t("corridor runs 240 unbroken", Plan.X[E.CorridorFar] - Plan.X[E.BandInner] == 240)
t("courtyard is square", Plan.X[E.CourtFar] - Plan.X[E.CourtNear] == Plan.Z[E.CourtFar] - Plan.Z[E.CourtNear])
t("ceiling clears a jump (16 > 12.2)", Plan.ClearStuds > 12.2)
t("stair climbs exactly one storey", math.abs(Plan.StairTreads * Plan.StairRiserStuds - Plan.StoreyStuds) < 1e-9)
t("stair riser is walkable (< 2)", Plan.StairRiserStuds < 2)
t("stair run fits its band", Plan.StairTreads * Plan.StairGoingStuds < Plan.BandStuds)
local rooms, bad, outside = Plan.Rooms(), 0, 0
for i, a in rooms do
	if a.X1 < 0 or a.Z1 < 0 or a.X2 > Plan.WidthStuds or a.Z2 > Plan.DepthStuds then outside += 1 end
	for j = i + 1, #rooms do local b = rooms[j]
		if a.Floor == b.Floor and a.X2 > b.X1 and b.X2 > a.X1 and a.Z2 > b.Z1 and b.Z2 > a.Z1 then bad += 1 end end
end
t("no room overlaps another on its floor", bad == 0)
t("every room is inside the footprint", outside == 0)
local gym = Plan.Gym()
t("gym clears both side bands", gym.X1 > Plan.X[E.BandInner] and gym.X2 < Plan.X[E.CorridorFar])
for _, line in out do print("ASSERT " .. line) end
"""
    script = Path(os.environ.get("TEMP", "/tmp")) / "showcase_plan.luau"
    script.write_text(plan_src + asserts, encoding="utf-8")
    r = subprocess.run([str(LUAU), str(script)], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
    if r.returncode != 0:
        report("plan module runs", False, (r.stderr.strip().splitlines() or [""])[0])
        return
    for line in r.stdout.splitlines():
        if line.startswith("ASSERT "):
            state, name = line[7:10], line[10:]
            report(name, state == "ok ")

    print("\n3. The shell lays real geometry")
    parts, extent = run_shell()
    report("shell laid parts", parts > 0, f"{parts} parts")
    if extent:
        w, d, h = extent[1] - extent[0], extent[5] - extent[4], extent[3] - extent[2]
        # The ground apron is 160 wider than the building on each axis; the building itself is
        # 400 x 448 x 60. Checking the extent rather than the part count is what catches a shell
        # that lays plenty of parts in the wrong place.
        report("extent matches the plan + apron", abs(w - 560) < 1 and abs(d - 608) < 1, f"{w:g} x {d:g}")
        report("stands 60 studs to the roof deck", abs(h - 62) < 3, f"{h:g} tall")


# ---------------------------------------------------------------- 4. the place builds
def check_builds() -> None:
    print("\n4. The place builds")
    out = Path(os.environ.get("TEMP", "/tmp")) / "showcase_gate.rbxl"
    for project in ("showcase.project.json", "default.project.json", "lobby.project.json"):
        r = subprocess.run([str(ROJO), "build", project, "-o", str(out)], cwd=ROOT,
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
        report(project, r.returncode == 0, (r.stderr.strip().splitlines() or [""])[-1] if r.returncode else "")


def main() -> int:
    print("showcase gate")
    check_compiles()
    check_plan_and_shell()
    check_builds()
    if failures:
        print(f"\n{len(failures)} CHECK(S) FAILED")
        return 1
    print("\nALL SHOWCASE CHECKS PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
