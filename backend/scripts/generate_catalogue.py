"""Regenerate data/garmin_exercises.json from Garmin's own exercise enum.

Garmin's strength catalogue — the (category, exercise) pairs its FIT profile
accepts — is not published as a downloadable file. It is embedded in the Garmin
Connect workout editor, from which cyberjunky/python-garminconnect (MIT) has
already extracted it. This script fetches that extraction and converts it into
the flat JSON this package ships, so the provenance is a URL and a transformation
rather than a blob that appeared one day.

    python backend/scripts/generate_catalogue.py

Re-run it when Garmin adds exercises. The output is sorted, so a regeneration
produces a readable diff instead of a reshuffle. Adding movements never breaks
the mapping — tests check that every pair still exists, not that the file is
unchanged.
"""

from __future__ import annotations

import ast
import json
import pathlib
import urllib.request

SOURCE_URL = (
    "https://raw.githubusercontent.com/cyberjunky/python-garminconnect/"
    "master/garminconnect/exercises.py"
)
OUT = pathlib.Path(__file__).resolve().parent.parent / "repflow_garmin" / "data" / "garmin_exercises.json"


def extract(source: str) -> list[tuple[str, str, str]]:
    """Pull `_RAW` out of the module without importing it.

    Parsed rather than executed: this file is fetched over the network, and
    running fetched code to read a list of strings out of it is not a trade
    worth making.
    """
    tree = ast.parse(source)
    for node in tree.body:
        if not isinstance(node, ast.AnnAssign) or not isinstance(node.target, ast.Name):
            continue
        if node.target.id != "_RAW" or node.value is None:
            continue
        rows = ast.literal_eval(node.value)
        return [(str(a), str(b), str(c)) for a, b, c in rows]
    raise SystemExit(f"no _RAW list found in {SOURCE_URL}")


def main() -> int:
    with urllib.request.urlopen(SOURCE_URL, timeout=30) as response:
        source = response.read().decode("utf-8")

    rows = sorted(set(extract(source)))
    payload = {
        "source": SOURCE_URL,
        "license": "MIT — Garmin Connect workout editor, extracted by cyberjunky/python-garminconnect",
        "count": len(rows),
        "categories": sorted({category for _, category, _ in rows}),
        # [display name, category, exercise] — exercise "" means the category
        # alone names the movement.
        "exercises": [[name, category, exercise] for name, category, exercise in rows],
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=1, ensure_ascii=False) + "\n")
    print(f"{OUT}: {len(rows)} exercises, {len(payload['categories'])} categories")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
