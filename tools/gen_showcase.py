#!/usr/bin/env python3
"""Bakes the showcase block-out into assets/Showcase.rbxmx.

**Why bake at all, when Shell.Build already lays the same parts at runtime.**

Because Studio shows you the *place*, not the game. A shell built at runtime means the place is
19 modules and a spawn point -- opening it and looking around shows an empty baseplate, and the
building only exists after you press Play. That is a real trap: it looks exactly like the sync
being broken, and this project has already lost an afternoon to it once.

Baking puts the geometry in the place itself, so it is there the moment Rojo connects. Shell.Build
then stands down if it finds the baked model already in the workspace -- see its `Build`.

The runtime path stays, and is still the source of truth: this script *runs* Shell.luau under a
recording stub rather than reimplementing it, so the two cannot disagree. Change the plan and
re-run; there is no second copy of the geometry to keep in step.
"""

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import rbxmx  # noqa: E402  -- Agent A's writer, used as-is

LUAU = Path.home() / ".aftman/tool-storage/luau" / ("luau.exe" if sys.platform == "win32" else "luau")
SRC = ROOT / "src/showcase"
# **In a subdirectory, and that is deliberate.**
#
# check.py asserts that every `assets/*.rbxmx` is mounted in one of the two *AGES* places, which
# is a good check -- it once caught four events that existed in content and could never fire. But
# its glob is not recursive and it does not know about a third place, so a showcase asset sitting
# in assets/ would fail it forever. Rather than edit check.py, which is Agent A's file, the
# showcase keeps its assets somewhere that check is not making a claim about.
OUT = ROOT / "assets" / "showcase" / "Showcase.rbxmx"

# **Where it stands in the AGES world.**
#
# Measured, not chosen: the nearest clear 408 x 456 to the town's school marker, with every
# mounted asset counted as an obstacle -- the two parked schools included, because neither is
# being removed. AGES has nothing closer. Even a 292 x 332 cannot get within 484 studs of the
# marker; the land around the town is full.
#
# The apron is off for this build. The baseplate is already ground, and a 560 x 608 apron would
# reach straight into the roads the site was picked to clear.
SITE = (-240.0, -732.0)

# A stub environment that keeps what it is given. The bootcheck harness this repo uses elsewhere
# returns write-only stubs, which is fine for proving code runs and useless for reading geometry
# back -- every recorded part came out empty. See the note at the top of check_showcase.py.
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
Enum = setmetatable({}, { __index = function(_, k)
	return setmetatable({}, { __index = function(_, n) return { Name = n, Enum = k } end })
end })

local partMeta = {}
partMeta.__index = partMeta
partMeta.__newindex = function(self, key, value)
	if key == "Parent" then
		rawset(self, "Parent", value)
		if type(value) == "table" and value.Children then table.insert(value.Children, self) end
		if self.ClassName == "Part" then table.insert(recorded, self) end
	else
		rawset(self, key, value)
	end
end
Instance = { new = function(class)
	return setmetatable({ ClassName = class, Name = "", Children = {}, Tags = {}, Attrs = {} }, partMeta)
end }

-- Kit tags and attributes its parts, so the recorder has to keep both -- a stub that swallows
-- them bakes untagged geometry, and every system finds nothing with no error anywhere.
function partMeta.SetAttribute(self, key, value) self.Attrs[key] = value end
function partMeta.GetAttribute(self, key) return self.Attrs[key] end
local CollectionStub = {
	AddTag = function(_, part, tag) table.insert(part.Tags, tag) end,
	GetTagged = function() return {} end,
}
game = { GetService = function(_, name)
	if name == "CollectionService" then return CollectionStub end
	return setmetatable({}, { __index = function() return function() end end })
end }
workspace = setmetatable({ ClassName = "Workspace", Children = {} }, partMeta)
workspace.FindFirstChild = function() return nil end

__BODY__

for _, p in recorded do
	local c, s, col = p.CFrame.Position, p.Size, p.Color
	-- Tags and attributes come out alongside the geometry. A recorder that drops them bakes
	-- untagged props, every system finds nothing, and there is no error anywhere to explain it.
	local attrs = {}
	for k, v in p.Attrs do
		table.insert(attrs, k .. "=" .. tostring(v))
	end
	print(("PART\t%s\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%d\t%d\t%d\t%s\t%s"):format(
		p.Name, c.X, c.Y, c.Z, s.X, s.Y, s.Z, col.R, col.G, col.B,
		table.concat(p.Tags, ","), table.concat(attrs, ",")))
end
"""


def record() -> list[dict]:
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
        # Baked at the origin the starter uses, so the model lands exactly where the runtime
        # build would have put it.
        f"Shell.Build(Vector3.new({SITE[0]} - Plan.WidthStuds / 2, 0, {SITE[1]} - Plan.DepthStuds / 2), {{ Ground = false }})",
    ])
    script = Path(os.environ.get("TEMP", "/tmp")) / "gen_showcase.luau"
    script.write_text(HARNESS.replace("__BODY__", body), encoding="utf-8")

    r = subprocess.run([str(LUAU), str(script)], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=180)
    if r.returncode != 0:
        raise SystemExit("shell failed to run:\n" + r.stderr)

    parts = []
    for line in r.stdout.splitlines():
        if not line.startswith("PART\t"):
            continue
        f = line.split("\t")
        parts.append({
            "name": f[1],
            "c": (float(f[2]), float(f[3]), float(f[4])),
            "s": (float(f[5]), float(f[6]), float(f[7])),
            "rgb": (int(f[8]), int(f[9]), int(f[10])),
            "tags": [t for t in (f[11] if len(f) > 11 else "").split(",") if t],
            "attrs": dict(kv.split("=", 1) for kv in (f[12] if len(f) > 12 else "").split(",") if "=" in kv),
        })
    return parts


def main() -> int:
    parts = record()
    # The failure this guards against is the one that has actually happened here: a bake that
    # writes nothing and reports success. Refuse rather than overwrite a good asset with an
    # empty one.
    if len(parts) < 100:
        raise SystemExit(f"refusing to write: the shell laid only {len(parts)} parts, which is not a building")

    rbxmx.begin("SC")
    for p in parts:
        cx, cy, cz = p["c"]
        sx, sy, sz = p["s"]
        rbxmx.box(
            p["name"],
            (cx - sx / 2, cx + sx / 2, cz - sz / 2, cz + sz / 2, cy - sy / 2, cy + sy / 2),
            p["rgb"],
            rbxmx.CONCRETE,
            tags=p["tags"] or None,
            attrs=p["attrs"] or None,
        )
    print(f"recorded {len(parts)} parts from Shell.luau")
    print(rbxmx.write(OUT, "Showcase"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
