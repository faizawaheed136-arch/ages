#!/usr/bin/env python3
"""Wraps the whole script tree in a Studio plugin that installs it.

Run from the repo root:
    rojo build codemodel.project.json --output build-code.rbxmx
    python tools/gen_code_plugin.py

**Why this exists, and why it should not have to.** The right way to get code into a Studio
session is the Rojo sync, and `code.project.json` describes it correctly. But connecting is a
click inside Studio, and there is no way to make that click from outside: `autoReconnect` only
reconnects a connection that was live when Studio last closed, so once the server has been
restarted the chain is broken until a human presses the button.

The geometry already worked around this -- `gen_school_plugin.py` carries the baked school and
parents it into Workspace. This is the same trick for the script tree: Server into
ServerScriptService, the shared modules into ReplicatedStorage, Client into
StarterPlayerScripts, ProfileStore into ServerStorage. Exactly the four mounts
`code.project.json` describes, because a second definition of where code goes is a second
thing to keep in step.

**Stamped, and it replaces only its own work.** The school plugin's first version skipped when
something was already there, and the result was hours of changes never arriving while
everything looked fine. Every container this installs carries an attribute; a container with
that attribute may be replaced, and one without it is somebody else's and is left alone with a
warning. That is the difference between a tool that refreshes and a tool that quietly stops.

**This is a workaround, not the design.** When Rojo is connected it should own these trees --
having both is two sources of truth. Delete the plugin once the sync is reliable.
"""

import html
import shutil
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODEL = ROOT / "build-code.rbxmx"
PLUGINS = Path.home() / "AppData" / "Local" / "Roblox" / "Plugins"
OUT = PLUGINS / "AgesCodeInstall.rbxmx"

SOURCE = """--!nocheck
-- Installs the AGES script tree into this place, in edit mode, with nobody clicking anything.
--
-- The four mounts below are exactly the ones code.project.json describes. If that file changes,
-- change these together -- two definitions of where code lives is two things to keep in step.

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local STAMP = "AgesCodeInstall"

local carried = script:FindFirstChild("Code")
if carried == nil then
\twarn("[AGES] the code plugin is missing its payload; re-run tools/gen_code_plugin.py")
\treturn
end

-- Replaces `name` under `parent` with `source`, but only if what is there was put there by
-- this plugin. Anything unstamped belongs to somebody else and is left alone: the one thing
-- worse than not installing is deleting work that was not ours.
local function install(parent, name, source)
\tif source == nil then
\t\twarn(string.format("[AGES] payload has no %s -- skipped", name))
\t\treturn false
\tend
\tlocal existing = parent:FindFirstChild(name)
\tif existing ~= nil then
\t\t-- Unstamped, but at a path code.project.json defines as ours. That is a tree an
\t\t-- earlier Rojo sync put here: the same code from the same repo, only stale. Adopted
\t\t-- once and stamped on the way out, so the question does not come up again.
\t\t--
\t\t-- The test is the *path*, not the contents. ServerScriptService.Server is not
\t\t-- somewhere anything else in this game puts a tree, and neither are the others --
\t\t-- they are exactly the four mounts the project file names.
\t\tif existing:GetAttribute(STAMP) == nil then
\t\t\tprint(string.format("[AGES] adopting %s.%s from an earlier sync", parent.Name, name))
\t\tend
\t\texisting:Destroy()
\tend
\tlocal copy = source:Clone()
\tcopy.Name = name
\tcopy:SetAttribute(STAMP, BAKE_STAMP)
\tcopy.Parent = parent
\treturn true
end

local done = 0

if install(ServerScriptService, "Server", carried:FindFirstChild("Server")) then
\tdone += 1
end
if install(ServerStorage, "ProfileStore", carried:FindFirstChild("Vendor")) then
\tdone += 1
end
if install(StarterPlayer:FindFirstChild("StarterPlayerScripts"), "Client", carried:FindFirstChild("Client")) then
\tdone += 1
end

-- ReplicatedStorage is the odd one: code.project.json maps src/shared onto ReplicatedStorage
-- *itself*, so the shared modules are its direct children rather than sitting in a folder.
-- Each one is installed and stamped individually for the same reason.
local shared = carried:FindFirstChild("Shared")
if shared ~= nil then
\tfor _, child in shared:GetChildren() do
\t\tif install(ReplicatedStorage, child.Name, child) then
\t\t\tdone += 1
\t\tend
\tend
end

print(string.format("[AGES] code installed: %d trees, bake %s.", done, BAKE_STAMP))
"""


def main() -> None:
    if not MODEL.exists():
        raise SystemExit(
            f"{MODEL} missing -- run:\n"
            "  rojo build codemodel.project.json --output build-code.rbxmx"
        )

    body = MODEL.read_text(encoding="utf-8")
    stamp = time.strftime("%Y-%m-%d %H:%M", time.localtime(MODEL.stat().st_mtime))
    source = SOURCE.replace("BAKE_STAMP", '"' + stamp + '"')

    # Lift the model's root Item out of its <roblox> wrapper and rename it, so the plugin
    # script has exactly one child called Code.
    start = body.index("<Item ")
    end = body.rindex("</Item>") + len("</Item>")
    model = body[start:end]
    # The built root is a Folder named after the project; the plugin looks for "Code".
    model = model.replace(
        "<string name=\"Name\">ages-code-model</string>",
        "<string name=\"Name\">Code</string>",
        1,
    )

    PLUGINS.mkdir(parents=True, exist_ok=True)
    if OUT.exists():
        shutil.copy2(OUT, OUT.with_suffix(".rbxmx.bak"))

    OUT.write_text(
        f'''<roblox version="4">
<Item class="Script" referent="AGESCODEPLUGIN">
<Properties>
<string name="Name">AgesCodeInstall</string>
<ProtectedString name="Source">{html.escape(source)}</ProtectedString>
</Properties>
{model}
</Item>
</roblox>
''',
        encoding="utf-8",
    )
    print(f"wrote {OUT} ({OUT.stat().st_size / 1e6:.1f} MB), bake {stamp}")
    print("Restart Roblox Studio. The script tree installs itself on load.")


if __name__ == "__main__":
    main()
