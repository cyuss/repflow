"""`repflow-garmin` — fill in the exercise table of a RepFlow activity.

    repflow-garmin list                 # which activities can be filled in
    repflow-garmin show                 # what would be written, writing nothing
    repflow-garmin fill                 # write it, after showing and confirming
    repflow-garmin fill --activity 123  # a specific one
    repflow-garmin fill --yes           # unattended

`show` and `fill --dry-run` never write. `fill` prints the payload, says what it
is replacing, and asks — because the endpoint replaces the activity's entire set
list and there is no undo beyond editing it back by hand.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from . import __version__
from .fitread import NotARepFlowActivity
from .garmin import (
    GarminError,
    connect,
    existing_sets,
    latest_strength,
    logged_sets,
    recent_strength,
    write_sets,
)
from .payload import build, summarise


def _report(sets: list[Any], payload: dict[str, Any], unmapped: list[str]) -> None:
    print(f"  read {len(sets)} sets from the activity's FIT file")
    print(f"  would write {summarise(payload['exerciseSets'])}\n")
    _print_mapping(sets)
    if unmapped:
        print(
            "\n  NOT written — Garmin's exercise enum has no match for:\n    "
            + "\n    ".join(sorted(unmapped))
            + "\n  Add them to repflow_garmin/mapping.py to include them."
        )


def _print_mapping(sets: list[Any]) -> None:
    """Show which Garmin exercise each RepFlow name became.

    This is the one thing worth reading before writing. A rejected pair is loud;
    a *plausible but wrong* one is silent, and the category is what draws the
    muscle map — so "Barbell Curl became a wrist curl" has to be visible here or
    it is not visible anywhere.
    """
    from .catalogue import display_name
    from .mapping import lookup, resolve

    seen: dict[str, tuple[str, str | None]] = {}
    counts: dict[str, int] = {}
    for logged in sets:
        target = resolve(logged.exercise)
        if target is None:
            continue
        seen.setdefault(logged.exercise, target)
        counts[logged.exercise] = counts.get(logged.exercise, 0) + 1

    if not seen:
        return

    width = max(len(name) for name in seen)
    tally = max(len(f"x{count}") for count in counts.values())
    indent = 4 + width + 2 + tally + len("  ->  ")   # align under the arrow

    print("  Exercise mapping — check the muscle group, not just the name:\n")
    for name, (category, exercise) in seen.items():
        # "curated" means a person wrote this pair down; "matched" means it was
        # inferred from the name, which is where a wrong answer would come from.
        origin = "curated" if lookup(name) is not None else "matched"
        detail = category if exercise is None else f"{category} / {exercise}"
        print(f"    {name:<{width}}  {f'x{counts[name]}':<{tally}}  ->  "
              f"{display_name(category, exercise)}")
        print(f"{'':<{indent}}{detail}  ({origin})")


def _cmd_list(args: argparse.Namespace) -> int:
    client = connect()
    found = recent_strength(client, limit=args.limit)
    if not found:
        print("No strength activities found.")
        return 1
    for activity in found:
        print(f"  {activity}")
    return 0


def _load(client: Any, activity_id: int | None) -> tuple[Any, list[Any]]:
    activity = None
    if activity_id is None:
        activity = latest_strength(client)
        activity_id = activity.activity_id
        print(f"Activity: {activity}")
    else:
        print(f"Activity: {activity_id}")
    return activity_id, logged_sets(client, int(activity_id))


def _cmd_show(args: argparse.Namespace) -> int:
    client = connect()
    activity_id, sets = _load(client, args.activity)
    payload, unmapped = build(activity_id, sets)
    _report(sets, payload, unmapped)
    if args.json:
        print(json.dumps(payload, indent=1))
    return 0


def _cmd_fill(args: argparse.Namespace) -> int:
    client = connect()
    activity_id, sets = _load(client, args.activity)
    payload, unmapped = build(activity_id, sets)
    _report(sets, payload, unmapped)

    if not payload["exerciseSets"]:
        print("\nNothing to write.")
        return 1

    already = existing_sets(client, int(activity_id))
    if already:
        print(
            f"\n  This activity already has {len(already)} exercise sets. "
            "Writing replaces all of them."
        )

    if args.dry_run:
        print("\nDry run — nothing written.")
        return 0

    if not args.yes:
        answer = input("\nWrite these sets to the activity? [y/N] ").strip().lower()
        if answer not in {"y", "yes"}:
            print("Nothing written.")
            return 1

    write_sets(client, int(activity_id), payload)
    print("Written. Reload the activity in Garmin Connect.")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="repflow-garmin", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--version", action="version", version=__version__)
    sub = parser.add_subparsers(dest="command", required=True)

    p_list = sub.add_parser("list", help="recent strength activities")
    p_list.add_argument("--limit", type=int, default=20)
    p_list.set_defaults(func=_cmd_list)

    for name, func, help_text in (
        ("show", _cmd_show, "what would be written (writes nothing)"),
        ("fill", _cmd_fill, "write the exercise sets into the activity"),
    ):
        p = sub.add_parser(name, help=help_text)
        p.add_argument("--activity", type=int, default=None, help="activity id; default is the most recent strength activity")
        p.add_argument("--json", action="store_true", help="print the full request body")
        if name == "fill":
            p.add_argument("--dry-run", action="store_true")
            p.add_argument("--yes", action="store_true", help="do not ask")
        p.set_defaults(func=func)

    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except (GarminError, NotARepFlowActivity) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
