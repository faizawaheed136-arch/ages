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

-- Kit tags and attributes, so the stub has to accept both or the shell errors on the first prop.
function partMeta.SetAttribute() end
function partMeta.GetAttribute() return nil end
game = { GetService = function(_, name)
	return setmetatable({}, { __index = function() return function() end end })
end }
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
-- What the plan says it should be, so the assertion below derives instead of hardcoding and
-- cannot go stale the next time the footprint changes. It already did, once.
print(("EXPECT %g %g %g"):format(Plan.WidthStuds, Plan.DepthStuds, Plan.RoofStuds + Plan.LanternStuds))
"""


def run_shell() -> tuple[int, list[float], list[float]]:
    plan = (SRC / "world/Plan.luau").read_text(encoding="utf-8").replace("\nreturn Plan\n", "\n")
    kit = (SRC / "world/Kit.luau").read_text(encoding="utf-8").replace("\nreturn Kit\n", "\n")
    props = (SRC / "world/Props.luau").read_text(encoding="utf-8").replace("\nreturn Props\n", "\n")
    props = props.replace("local Plan = require(script.Parent.Plan)", "")
    props = props.replace("local Kit = require(script.Parent.Kit)", "")
    shell = (SRC / "world/Shell.luau").read_text(encoding="utf-8")
    shell = shell.replace("local Plan = require(script.Parent.Plan)", "")
    shell = shell.replace("local Kit = require(script.Parent.Kit)", "")
    shell = shell.replace("local Props = require(script.Parent.Props)", "")
    shell = shell.replace("\nreturn Shell\n", "\n")

    body = "\n".join([
        plan, kit, props, shell,
        "Shell.Build(Vector3.new(-Plan.WidthStuds / 2, 0, -Plan.DepthStuds / 2))",
    ])
    script = Path(os.environ.get("TEMP", "/tmp")) / "showcase_shell.luau"
    script.write_text(HARNESS.replace("__PLACEHOLDER__", body), encoding="utf-8")

    r = subprocess.run([str(LUAU), str(script)], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
    if r.returncode != 0:
        print("        " + (r.stderr.strip().splitlines() or ["failed"])[0])
        return 0, [], []
    parts, extent, expect = 0, [], []
    for line in r.stdout.splitlines():
        if line.startswith("PARTS "):
            parts = int(line.split()[1])
        elif line.startswith("EXTENT "):
            extent = [float(v) for v in line.split()[1:]]
        elif line.startswith("EXPECT "):
            expect = [float(v) for v in line.split()[1:]]
    return parts, extent, expect


def check_plan_and_shell() -> None:
    print("\n2. The plan's arithmetic")
    plan_src = (SRC / "world/Plan.luau").read_text(encoding="utf-8").replace("\nreturn Plan\n", "\n")
    asserts = r"""
local out = {}
local function t(name, cond) table.insert(out, (cond and "ok " or "no ") .. name) end
local E, ZE = Plan.Edge, Plan.ZEdge

t("bands sum to 400 x 340", Plan.WidthStuds == 400 and Plan.DepthStuds == 340)
t("edge lists close on the footprint", Plan.X[#Plan.X] == Plan.WidthStuds and Plan.Z[#Plan.Z] == Plan.DepthStuds)
t("gallery is 28 wide", Plan.X[E.GalleryInner] - Plan.X[E.RoomInner] == Plan.GalleryStuds)
t("atrium is square in plan", Plan.X[E.VoidFar] - Plan.X[E.VoidNear] == Plan.Z[ZE.AtriumBack] - Plan.Z[ZE.GardenBack])
t("garden is 160 x 140, open to the south", Plan.X[E.VoidFar] - Plan.X[E.VoidNear] == 160 and Plan.Z[ZE.GardenBack] == 140)
t("both clear heights beat the 12.2 jump crown", Plan.GroundClearStuds > 12.2 and Plan.UpperClearStuds > 12.2)
t("ground floor is taller than the upper", Plan.GroundClearStuds > Plan.UpperClearStuds)
t("roof 48, lantern above the parapet", Plan.RoofStuds == 48 and Plan.LanternStuds > 0)
t("gym is one volume through both storeys", Plan.GymClearStuds == Plan.RoofStuds - Plan.SlabStuds)

-- The stair climbs FLOOR TO FLOOR, not clear height. Getting that wrong lands it a slab short
-- of its own landing, which is a bug you find by walking into it.
t("stair rise == the ground storey", math.abs(Plan.StairTreads * Plan.StairRiserStuds - Plan.GroundStoreyStuds) < 1e-9)
t("stair riser is walkable (< 2)", Plan.StairRiserStuds < 2)
t("stair run fits inside the atrium", Plan.StairRunStuds() < Plan.AtriumStuds)
t("stair is wide enough to sit on and climb", Plan.StairWidthStuds >= 24)
t("seating tiers are deeper than the walking going", Plan.StairTierGoingStuds > Plan.StairGoingStuds)

local bridges = Plan.Bridges()
t("two bridges, wing to wing", #bridges == 2
	and bridges[1].X1 == Plan.X[E.GalleryInner] and bridges[1].X2 == Plan.X[E.EdgeFar])
t("bridges do not overlap each other", bridges[2].Z1 > bridges[1].Z2)

local rooms, bad, outside = Plan.Rooms(), 0, 0
for i, a in rooms do
	if a.X1 < 0 or a.Z1 < 0 or a.X2 > Plan.WidthStuds or a.Z2 > Plan.DepthStuds then outside += 1 end
	for j = i + 1, #rooms do local b = rooms[j]
		if a.Floor == b.Floor and a.X2 > b.X1 and b.X2 > a.X1 and a.Z2 > b.Z1 and b.Z2 > a.Z1 then bad += 1 end end
end
t("no room overlaps another on its floor", bad == 0)
t("every room is inside the footprint", outside == 0)

local gym, cafe = Plan.Gym(), Plan.Cafeteria()
t("gym and cafeteria are in opposite wings",
	cafe.X2 <= Plan.X[E.VoidNear] and gym.X1 >= Plan.X[E.VoidFar])
local want = { ["Art Studio"] = false, ["Science Lab"] = false, Math = false, Kitchen = false }
for _, r in rooms do if want[r.Label] ~= nil then want[r.Label] = true end end
for label, found in want do t("programme has " .. label, found) end

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
    parts, extent, expect = run_shell()
    report("shell laid parts", parts > 0, f"{parts} parts")
    if extent and expect:
        w, d, h = extent[1] - extent[0], extent[5] - extent[4], extent[3] - extent[2]
        # The ground apron overhangs the footprint by 100 studs on each axis. Both numbers come
        # from the plan rather than from this file, so a footprint change moves them together.
        want_w, want_d, want_h = expect[0] + 200, expect[1] + 200, expect[2]
        report("extent matches the plan plus its apron", abs(w - want_w) < 1 and abs(d - want_d) < 1,
               f"{w:g} x {d:g}, wanted {want_w:g} x {want_d:g}")
        # Ground plate sits 2 below zero and the tallest thing is the lantern, so the total is a
        # little over the plan's height. Loose on purpose: this catches a building that failed to
        # rise, not one that is a stud out.
        report("stands to roughly the plan's full height", want_h - 4 < h < want_h + 12,
               f"{h:g} tall, plan says {want_h:g}")


# ---------------------------------------------------------------- 3b. the props are tagged
def check_props() -> None:
    """Every interactive system finds its geometry by CollectionService tag, so an untagged bake
    is a building full of props that do nothing -- with no error anywhere to explain it.

    This reads the **baked asset**, not the source, because that is where the tags have to survive:
    the recorder has to collect them, the writer has to encode them, and either can drop them
    silently. It has already happened once -- the stub collected the tags and the print statement
    that fed the writer did not carry them.
    """
    import base64
    import collections
    import xml.etree.ElementTree as ET

    print("\n3b. The props carry their tags")
    asset = ROOT / "assets/showcase/Showcase.rbxmx"
    if not asset.exists():
        report("baked asset exists", False, "run tools/gen_showcase.py")
        return

    tags: collections.Counter = collections.Counter()
    leaves: list[tuple[str, float, float]] = []
    for item in ET.parse(asset).getroot().iter("Item"):
        props = item.find("Properties")
        if props is None:
            continue
        blob = props.find("BinaryString[@name='Tags']")
        if blob is None or not blob.text:
            continue
        found = [t for t in base64.b64decode(blob.text).decode().split("\0") if t]
        for tag in found:
            tags[tag] += 1
        if "Door" in found or "LockerDoor" in found:
            name_el = props.find("string[@name='Name']")
            size = props.find("Vector3[@name='size']")
            if size is not None:
                leaves.append((
                    name_el.text if name_el is not None else "?",
                    float(size.find("X").text),
                    float(size.find("Z").text),
                ))

    # One row per system that binds a tag at Start(). A system whose tag count drops to zero has
    # nothing to attach to, which is exactly the failure this file exists to catch.
    expected = {
        "VendingMachine": 1,
        "SparringRing": 1,
        "TargetNode": 1,
        "ArenaCamera": 1,
        "LockerDoor": 1,
        "Wardrobe": 1,
        "Door": 1,
    }
    for tag, least in sorted(expected.items()):
        report(f"{tag}", tags[tag] >= least, f"{tags[tag]} tagged")

    # **Every hinged leaf needs an unambiguous width axis.**
    #
    # Hinge picks the longer of the leaf's two horizontal dimensions as its width and hinges on
    # that edge. A leaf that is *square* gives it nothing to choose between: floating-point noise
    # decides, and the door pivots about the wrong edge with no error anywhere.
    #
    # The bar is deliberately low. It first went in at a 2:1 aspect ratio, which failed all ten
    # locker doors at 4.5 x 2.4 -- and those are fine, because 4.5 is plainly the longer side.
    # That was a style rule pretending to be a correctness check. What actually breaks the pivot
    # is near-equality, so that is what this measures.
    ambiguous = []
    for name, sx, sz in leaves:
        if min(sx, sz) > max(sx, sz) * 0.9:
            ambiguous.append(f"{name} {sx:g} x {sz:g}  (ratio {min(sx, sz) / max(sx, sz):.2f})")
    for line in ambiguous[:4]:
        print(f"        {line}")
    report("every hinged leaf is clearly wider than it is thick", not ambiguous,
           f"{len(leaves)} leaves, {len(ambiguous)} ambiguous")


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
    check_props()
    check_builds()
    if failures:
        print(f"\n{len(failures)} CHECK(S) FAILED")
        return 1
    print("\nALL SHOWCASE CHECKS PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
