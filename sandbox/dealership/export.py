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
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
BUILD = HERE / "build"
LUAU = pathlib.Path.home() / ".aftman/tool-storage/luau/luau.exe"
ROJO = pathlib.Path.home() / ".aftman/tool-storage/rojo-rbx/rojo/7.7.0/rojo.exe"

# Where each exported copy stands. AGES's plot corner is the grass at the south-west of the plot
# north of the estate streets; the sandbox builds at the origin.
PLAN = [
    ("Dealership.ages", "DealershipBuild", (-280, 1.95, 1940)),
    ("Dealership.sandbox", "DealershipBuild", (0, 0, 0)),
    ("SandboxSite", "SandboxSite", (0, 0, 0)),
]


def wrap(name: str, path: pathlib.Path) -> str:
    return f"local {name} = (function()\n{path.read_text(encoding='utf-8')}\nend)()\n"


def compose() -> str:
    plan = ",\n".join(
        f'\t{{ file = "{file}", build = {builder}.Build, x = {x}, y = {y}, z = {z} }}'
        for file, builder, (x, y, z) in PLAN
    )
    return "\n".join(
        [
            (HERE / "offline/RobloxStub.luau").read_text(encoding="utf-8"),
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
    missing = [file for file, _, _ in PLAN if file not in documents]
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
