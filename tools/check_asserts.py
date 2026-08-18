"""Do gen_town's assertions actually fire? Break one input, watch exactly one.

An assertion nobody has watched fire is a comment with a colon in it. Each case
here breaks one input and expects one assertion to catch it -- and expects the
*right* one, matched on a phrase only that assertion prints, because the failure
mode this harness exists to avoid is a mutation that trips a neighbouring guard
first and reads as a pass. A control case runs the source unmutated, so a guard
that fires unconditionally cannot make the whole file look green either.

**This covers the north parade block and nothing else.** Six assertions out of the
forty-odd in gen_town.py; the rest have never been watched. Green here means those
six work, not that the town is checked, and that is why this is not part of the
gate suite -- check.py, check_city.py and check_town.py are. Extend it when you add
an assertion. Do not read it as coverage nobody wrote.

Every case is a defect that actually reached the tree. The park one drew a pond,
two paths, two benches and a picnic table inside a standing house and passed all
three gates. The band-too-long one is the 256 studs of empty frontage the same edit
left on the street the parade exists to finish. The walk one took the bottom of the
far walk off the route graph while the label on the line still read "outside the
garage".

Cases 1-5 are reachable from the plan block alone, so they are exec'd from the
source up to the first `with group(...)` and never touch disk. Case 6 lives in the
build section and needs the whole file, so it runs as a subprocess against a temp
copy -- which would write assets/Town.rbxmx if its assertion ever stopped firing.
Regenerate and `cmp` after running this.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = (HERE / "gen_town.py").read_text()
PREFIX = SRC.split('with group("Ground")')[0]

# (name, old text, new text, phrase the right assertion prints)
PREFIX_CASES = [
    ("park drawn on a standing house",
     "PARK_Z0, PARK_Z1 = 168.0, 228.0",
     "PARK_Z0, PARK_Z1 = -88.0, -28.0",
     "the pond is being drawn through its front room"),
    ("parade band too short to hold its names",
     "NORTH_PARADE_Z0 = PARK_Z1",
     "NORTH_PARADE_Z0 = NORTH_PARADE_Z1 - 40.0",
     "units over the"),
    ("parade band left with a plot nobody built",
     "NORTH_PARADE_Z0 = PARK_Z1",
     "NORTH_PARADE_Z0 = PARK_Z1 - 200.0",
     "frontage on a made pavement with nothing on it"),
    ("parade back wall over the city seam",
     "NORTH_PARADE_X1 = NORTH_PARADE_X0 + BUILDING_DEPTH",
     "NORTH_PARADE_X1 = NORTH_PARADE_X0 + BUILDING_DEPTH + 60.0",
     "studs into the city"),
    ("south walk point moved out of sequence",
     '("wp_south_3", -92.0, -212.0, PAVING, "outside the garage"),',
     '("wp_south_3", -92.0, -106.0, PAVING, "outside the garage"),',
     "west walk down to the far end"),
]

FULL_CASE = ("a parade unit with no wall colour",
             '"TOWN BARBERS": BARBER_WALL,',
             "",
             "NORTH_PARADE_WALLS")


def run_prefix(old, new):
    assert SRC.count(old) == 1, f"mutation target is not unique: {old!r}"
    g = {"__name__": "_neg"}
    try:
        exec(PREFIX.replace(old, new), g)
    except AssertionError as e:
        return str(e)
    return None


def run_full(old, new):
    assert SRC.count(old) == 1, f"mutation target is not unique: {old!r}"
    with tempfile.NamedTemporaryFile("w", suffix=".py", dir=HERE,
                                     delete=False) as fh:
        fh.write(SRC.replace(old, new))
        tmp = Path(fh.name)
    try:
        p = subprocess.run([sys.executable, tmp.name], cwd=HERE,
                           capture_output=True, text=True)
        if "AssertionError" in p.stderr:
            return p.stderr.strip().splitlines()[-1]
        return None
    finally:
        tmp.unlink()


def main():
    fired = 0
    cases = [(n, run_prefix, o, w, p) for n, o, w, p in PREFIX_CASES]
    cases.append((FULL_CASE[0], run_full, FULL_CASE[1], FULL_CASE[2],
                  FULL_CASE[3]))

    # The control: unmutated source must raise nothing at all. Without it every
    # case below could be passing on an assertion that fires unconditionally.
    control = "PARK_Z0, PARK_Z1 = 168.0, 228.0"
    if run_prefix(control, control) is not None:
        print("FAIL  the unmutated plan already asserts", file=sys.stderr)
        return 1
    print("OK    control: the unmutated plan raises nothing")

    for name, runner, old, new, phrase in cases:
        msg = runner(old, new)
        if msg is None:
            print(f"FAIL  {name}: nothing fired", file=sys.stderr)
        elif phrase not in msg:
            print(f"FAIL  {name}: a different assertion fired\n      {msg}",
                  file=sys.stderr)
        else:
            fired += 1
            print(f"OK    {name}")
            flat = re.sub(r"\s+", " ", msg)[:150]
            print(f"      {flat}")

    print(f"\n{fired}/{len(cases)} assertions fired")
    return 0 if fired == len(cases) else 1


if __name__ == "__main__":
    sys.exit(main())
