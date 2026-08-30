#!/usr/bin/env python3
"""Wraps the baked school in a Studio plugin that inserts it, so it appears with no clicking.

Run from the repo root:  python tools/gen_school_plugin.py

**Why.** `assets/School.rbxmx` is real geometry and shows in edit mode -- but only once it is
*in* the place, and getting it there needs either a Rojo sync or File > Insert from File.
When neither is available (the sync is owned by another machine, and the place is a cloud
Team Create with no local file to edit), there is one remaining way to put an object into a
Studio session without a human clicking: a plugin.

Studio loads every `.rbxmx` in its Plugins folder at startup and runs the Scripts inside. So
this emits a Script with the whole school parented underneath it, and the Script clones it
into Workspace.

**It is idempotent and it is reversible.** It does nothing if a `School` already exists, so
restarting Studio does not stack copies, and it never touches anything else in the place.
Deleting the model removes the school; deleting the plugin file stops it coming back.

**It is a stopgap, not the design.** The right path is the Rojo sync carrying
`Workspace.School`, which `code.project.json` now describes. This exists because that path
depends on a machine this script cannot reach.
"""

import html
import shutil
import time
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSET = ROOT / "assets" / "School.rbxmx"
PLUGINS = Path.home() / "AppData" / "Local" / "Roblox" / "Plugins"
OUT = PLUGINS / "AgesSchoolInsert.rbxmx"

SOURCE = """--!nocheck
-- Puts the AGES school into the place, in edit mode, with nobody clicking anything.
--
-- The building is baked geometry (tools/gen_school.py) and is carried inside this plugin as a
-- child of this script. All this does is clone it into Workspace.
--
-- **It replaces its own previous insert rather than skipping.** The first version of this
-- refused to do anything if a School already existed, which was the right instinct and the
-- wrong rule: the plugin inserts once, the asset is rebuilt a dozen times over an evening, and
-- from then on every restart looked at the stale copy it had inserted itself and decided there
-- was nothing to do. Hours of changes never reached the place, and the symptom is simply that
-- nothing changes -- which reads as a broken sync rather than as a stale insert.
--
-- So the model it lays is stamped, and a stamped model is one it may replace. An unstamped
-- School is somebody else's and is never touched: this refuses rather than guessing, because
-- the one thing worse than not inserting is deleting work that was not ours.

local MODEL_NAME = "School"
local STAMP = "AgesSchoolBake"

local carried = script:FindFirstChild(MODEL_NAME)
if carried == nil then
	warn("[AGES] the school plugin is missing its model; re-run tools/gen_school_plugin.py")
	return
end

-- One part name that only this bake produces. It is how an *unstamped* School left behind by
-- the first version of this plugin is recognised as ours and adopted, rather than being
-- treated as somebody else's work and left to go stale forever.
local FINGERPRINT = "LobbyBanner1"

local existing = workspace:FindFirstChild(MODEL_NAME)
if existing ~= nil then
	local ours = existing:GetAttribute(STAMP) ~= nil or existing:FindFirstChild(FINGERPRINT, true) ~= nil
	if not ours then
		warn("[AGES] a School is already here that this plugin did not insert -- leaving it alone.")
		return
	end
	existing:Destroy()
end

local copy = carried:Clone()
copy:SetAttribute(STAMP, BAKE_STAMP)
copy.Parent = workspace

local parts = 0
for _, d in copy:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end
print(string.format("[AGES] school inserted: %d parts, bake %s.", parts, BAKE_STAMP))
"""



def main() -> None:
    if not ASSET.exists():
        raise SystemExit(f"{ASSET} missing -- run tools/gen_school.py first")

    body = ASSET.read_text(encoding="utf-8")
    # A stamp the plugin prints, so "is this the current school?" is answerable from the
    # output window instead of by counting parts.
    stamp = time.strftime('%Y-%m-%d %H:%M', time.localtime(ASSET.stat().st_mtime))
    source = SOURCE.replace('BAKE_STAMP', repr(stamp).replace("'", '"'))
    # The asset is a full <roblox> document. Lift its single root <Item> out and re-parent it
    # under the plugin script; nesting one <roblox> inside another is not a valid file.
    start = body.index("<Item ")
    end = body.rindex("</Item>") + len("</Item>")
    model = body[start:end]

    PLUGINS.mkdir(parents=True, exist_ok=True)
    if OUT.exists():
        shutil.copy2(OUT, OUT.with_suffix(".rbxmx.bak"))

    OUT.write_text(
        f'''<roblox version="4">
<Item class="Script" referent="AGESSCHOOLPLUGIN">
<Properties>
<string name="Name">AgesSchoolInsert</string>
<ProtectedString name="Source">{html.escape(source)}</ProtectedString>
</Properties>
{model}
</Item>
</roblox>
''',
        encoding="utf-8",
    )
    size = OUT.stat().st_size
    print(f"wrote {OUT} ({size / 1e6:.1f} MB)")
    print("Restart Roblox Studio. The school appears in Workspace, in edit mode, on load.")
    print("To stop it: delete the plugin file above, and delete the School model from the place.")


if __name__ == "__main__":
    main()
