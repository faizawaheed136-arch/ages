"""Build Meridian Motors outside Studio, as real Roblox files.

    python sandbox/dealership/export.py

Runs world/DealershipBuild.luau under the Luau command line against a stand-in for Roblox's API
(offline/RobloxStub.luau), writes the result as Rojo model files, and has Rojo turn those into:

  sandbox/dealership/Dealership.rbxmx
      The dealership, positioned for its AGES plot -- corner (-280, 1.95, 1940). To add it to
      AGES: Studio's Model tab -> Insert from File -> this file, or mount it in
      default.project.json under Workspace like the other assets/*.rbxmx. It lands in place.

  dealership-sandbox.rbxlx  (repo root, gitignored)
      An open-space place with the dealership at the origin, already built -- visible the moment
      it opens, no Play needed. `dealership.project.json` describes it.

WHY THIS EXISTS. The dealership is laid by code, and until now that code only ran inside a Studio
session, through a bridge that is not always there. This makes the dealership a file: it can be
reviewed, versioned and dropped into a place without either.
"""

import json
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
BUILD = HERE / "build"
LUAU = pathlib.Path.home() / ".aftman/tool-storage/luau/luau.exe"
ROJO = pathlib.Path.home() / ".aftman/tool-storage/rojo-rbx/rojo/7.7.0/rojo.exe"

# Where each exported copy stands. AGES's plot corner is the grass at the south-west of the plot
# north of the estate streets; the sandbox builds at the origin.
#
# The sandbox copy is stocked with the game's own display cars afterwards; the AGES copy is not,
# because DealershipService stocks it when the server starts.
PLAN = [
    ("Dealership.ages", "DealershipBuild", (-280, 1.95, 1940), None),
    # Cars were out from 2026-09-22 to 2026-09-25, on the owner's word; back since shared/CarBody
    # draws them properly.
    ("Dealership.sandbox", "DealershipBuild", (0, 0, 0), "stockDisplayCars"),
    ("SandboxSite", "SandboxSite", (0, 0, 0), None),
]

# Game modules the display cars need, in load order, each registered under the name the code
# requires it by: `require(ReplicatedStorage:WaitForChild("Config"))` resolves through the registry.
REGISTERED = [
    ("Config", ROOT / "src/shared/Config.luau"),
    ("Types", ROOT / "src/shared/Types.luau"),
    ("CarSpec", ROOT / "src/shared/CarSpec.luau"),
    ("MeshCar", ROOT / "src/shared/MeshCar.luau"),
    ("CarBody", ROOT / "src/shared/CarBody.luau"),
    ("CarPhysics", ROOT / "src/shared/CarPhysics.luau"),
]
# Loaded as locals, after the registry.
CAR_MODULES = [
    ("Vehicles", ROOT / "src/server/content/Vehicles.luau"),
    ("VehicleChassis", ROOT / "src/server/world/VehicleChassis.luau"),
]

REGISTRY = """
local MODULES = {}
local function require(target)
	local module = MODULES[target.Name]
	if module == nil then
		error(`export: {target.Name} is required but not registered in export.py's REGISTERED`)
	end
	return module
end
local function register(name, module)
	MODULES[name] = module
	local stand = Instance.new("ModuleScript")
	stand.Name = name
	stand.Parent = ReplicatedStorage
	return module
end
"""


def source(path: pathlib.Path) -> str:
    # Spliced into a function body, where `export type` is not allowed; the types still parse.
    return re.sub(r"^export type ", "type ", path.read_text(encoding="utf-8"), flags=re.M)


def wrap(name: str, path: pathlib.Path) -> str:
    return f"local {name} = (function()\n{source(path)}\nend)()\n"


def registered(name: str, path: pathlib.Path) -> str:
    return f'local {name} = register("{name}", (function()\n{source(path)}\nend)())\n'


def compose() -> str:
    plan = ",\n".join(
        f'\t{{ file = "{file}", build = {builder}.Build, x = {x}, y = {y}, z = {z}, after = {after or "nil"} }}'
        for file, builder, (x, y, z), after in PLAN
    )
    return "\n".join(
        [
            (HERE / "offline/RobloxStub.luau").read_text(encoding="utf-8"),
            REGISTRY,
            *(registered(name, path) for name, path in REGISTERED),
            *(wrap(name, path) for name, path in CAR_MODULES),
            (HERE / "offline/DisplayCars.luau").read_text(encoding="utf-8"),
            wrap("DealershipBuild", ROOT / "src/server/world/DealershipBuild.luau"),
            wrap("SandboxSite", HERE / "SandboxSite.luau"),
            f"local EXPORT_PLAN = {{\n{plan}\n}}\n",
            (HERE / "offline/export.luau").read_text(encoding="utf-8"),
        ]
    )


def run_builders() -> dict[str, tuple[str, int]]:
    BUILD.mkdir(exist_ok=True)
    script = BUILD / "combined.luau"
    script.write_text(compose(), encoding="utf-8")
    result = subprocess.run([str(LUAU), str(script)], capture_output=True, text=True, encoding="utf-8")
    if result.returncode != 0:
        sys.exit(f"the builder failed under the Luau CLI:\n{result.stdout[-2000:]}\n{result.stderr[-4000:]}")

    documents: dict[str, tuple[str, int]] = {}
    lines = iter(result.stdout.splitlines())
    for line in lines:
        if not line.startswith("=====BEGIN "):
            continue
        _, name, count = line.split(" ")
        body = next(lines)
        end = next(lines)
        if end != f"=====END {name}":
            sys.exit(f"export of {name} was cut short")
        json.loads(body)  # Fails here, not inside Rojo, if the exporter wrote bad JSON.
        documents[name] = (body, int(count))
    missing = [file for file, _, _, _ in PLAN if file not in documents]
    if missing:
        sys.exit(f"the exporter produced nothing for {missing}")
    return documents


def rojo_build(project: pathlib.Path, output: pathlib.Path) -> None:
    result = subprocess.run([str(ROJO), "build", str(project), "--output", str(output)], capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"rojo build {project.name} failed:\n{result.stdout}\n{result.stderr}")


def main() -> int:
    documents = run_builders()
    for name, (body, count) in documents.items():
        (BUILD / f"{name}.model.json").write_text(body, encoding="utf-8")
        print(f"  {name}: {count} instances")

    # The drop-in model for AGES: the project's name is the instance's name.
    model_project = BUILD / "dealership-model.project.json"
    model_project.write_text(
        json.dumps({"name": "Dealership", "tree": {"$path": "Dealership.ages.model.json"}}, indent=2),
        encoding="utf-8",
    )
    rojo_build(model_project, HERE / "Dealership.rbxmx")
    print(f"  wrote {(HERE / 'Dealership.rbxmx').relative_to(ROOT)}")

    rojo_build(ROOT / "dealership.project.json", ROOT / "dealership-sandbox.rbxlx")
    print("  wrote dealership-sandbox.rbxlx")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
