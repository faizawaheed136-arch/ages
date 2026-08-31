#!/usr/bin/env python3
"""Rebuilds every generated asset, in the one order that works.

**Why this file exists.**

`assets/Street.rbxmx` is written by two generators owned by two different agents, and the order
matters:

  * Agent A's `build_street.py` writes the street from `world_plan.py`. That includes the map's
    own school model and the place points at their planned coordinates.
  * Agent C's `gen_school.py` then does two post-passes over it: `strip_old_school()` removes the
    map's school so v1's building is not standing inside it, and `relocate_place_points()` moves
    "school", "classroom", "cafeteria" and "science_lab" into the rooms of the building that
    actually got built.

Run them the other way round and the second undoes the first. Nothing errors. The file simply
grows back to 405 KB, the old school reappears inside the new one, and `Place_school` goes back
to (-238, 151) -- so anything sending a player "to school" delivers them to a building that is no
longer there. Every gate in this repo still passes, because each asset is internally consistent;
they are just consistent with different plans.

That is not hypothetical: it happened on 2026-08-31 while auditing whether the assets were in
sync with the generators, and the only reason it was caught is that the check compared the
regenerated file against the committed one.

So: run this rather than the generators by hand.
"""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PY = sys.executable

# Order is the whole point.
#
#   the world first -- town, city, street
#   then the schools, which post-process the street
#   then the map, which reads the finished assets
STEPS = [
    ("gen_town.py", "the town"),
    ("gen_city.py", "the city"),
    ("build_street.py", "the street  (writes Place_* at their planned coordinates)"),
    ("gen_school.py", "v1's school  (strips the map's school, moves Place_* into the built rooms)"),
    ("gen_proper_school.py", "the parked ProperSchool"),
    ("gen_showcase.py", "the academy"),
    ("gen_mapshapes.py", "the map      (must be last: it reads every asset above)"),
]

GATES = ["check.py", "check_school.py", "check_town.py", "check_city.py",
         "check_routes.py", "check_showcase.py"]


def run(script: str, label: str) -> bool:
    path = ROOT / "tools" / script
    if not path.exists():
        print(f"  --    {script:24s} not present, skipped")
        return True
    r = subprocess.run([PY, str(path)], cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=900)
    tail = [ln for ln in r.stdout.strip().splitlines() if ln.strip()]
    note = tail[-1][:64] if tail else ""
    print(f"  {'ok' if r.returncode == 0 else 'FAIL':4s}  {script:24s} {label}")
    if note:
        print(f"        {note}")
    if r.returncode != 0:
        print("        " + (r.stderr.strip().splitlines() or [""])[-1][:100])
    return r.returncode == 0


def main() -> int:
    print("rebuilding every generated asset, in order\n")
    for script, label in STEPS:
        if not run(script, label):
            print(f"\nstopped at {script}. The assets are now half-rebuilt -- fix it and re-run "
                  f"from the top rather than continuing, or the ordering above is broken.")
            return 1

    print("\nrunning the gates\n")
    bad = []
    for gate in GATES:
        path = ROOT / "tools" / gate
        if not path.exists():
            continue
        r = subprocess.run([PY, str(path)], cwd=ROOT, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=900)
        tail = [ln for ln in r.stdout.strip().splitlines() if ln.strip()]
        print(f"  {'ok' if r.returncode == 0 else 'FAIL':4s}  {gate:20s} {tail[-1][:60] if tail else ''}")
        if r.returncode != 0:
            bad.append(gate)

    if bad:
        print(f"\n{len(bad)} gate(s) failed: {', '.join(bad)}")
        return 1
    print("\nall assets rebuilt and every gate clean")
    print("Rojo caches .rbxmx at startup -- restart it, or Studio keeps serving the old ones.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
