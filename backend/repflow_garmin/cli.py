"""`repflow-garmin` — fill in the exercise table of a RepFlow activity.

    repflow-garmin list                 # which activities can be filled in
    repflow-garmin show                 # what would be written, writing nothing
    repflow-garmin fill                 # write it, after showing and confirming
    repflow-garmin fill --activity 123  # a specific one
    repflow-garmin fill --yes           # unattended
    repflow-garmin hevy                 # send the same session to Hevy

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
from .hevy import (
    HevyError,
    already_posted,
    build_workout,
    post_workout,
    summarise as summarise_hevy,
    templates,
)
from .tui import choose, confirm, interactive
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


def _pick(client: Any, activity_id: int | None, unattended: bool) -> Any:
    """Which activity to act on: the one named, or one the athlete chooses.

    Named on the command line wins. Otherwise the recent strength activities are
    offered, because "it picked the wrong one" has already happened here — the
    listing endpoint is documented as newest-first and is not — and a guess that
    gets printed after the fact is not the same as being asked.

    With no terminal, or with --yes, the newest is taken and said out loud.
    """
    if activity_id is not None:
        print(f"Activity: {activity_id}")
        return None, activity_id

    if unattended or not interactive():
        activity = latest_strength(client)
        print(f"Activity: {activity}")
        return activity, activity.activity_id

    found = recent_strength(client, limit=20)
    if not found:
        # Same refusal as latest_strength, with the same listing of what there
        # is instead of a bare "none found".
        activity = latest_strength(client)
        return activity, activity.activity_id

    chosen = choose(found, lambda a: str(a), title="Which session?")
    if chosen is None:
        raise GarminError("nothing chosen")
    print(f"Activity: {chosen}")
    return chosen, chosen.activity_id


def _load(client: Any, activity_id: int | None, unattended: bool = False) -> tuple[Any, list[Any]]:
    activity, activity_id = _pick(client, activity_id, unattended)
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
    activity_id, sets = _load(client, args.activity, args.yes)
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

    if not args.yes and not confirm("\nWrite these sets to the activity?"):
        print("Nothing written.")
        return 1

    write_sets(client, int(activity_id), payload)
    print("Written. Reload the activity in Garmin Connect.")
    return 0


def _hevy_key(explicit: str | None) -> str:
    """The Hevy API key, from the flag, the environment, or the terminal.

    Never written to disk by this tool. A key is read+write access to the
    athlete's entire training history, so it is not cached the way Garmin's
    session token is — that one Garmin issues and can revoke, this one cannot
    be scoped.
    """
    import getpass
    import os
    import sys

    key = (explicit or os.getenv("HEVY_API_KEY") or "").strip()
    if key:
        return key
    if not sys.stdin.isatty():
        raise HevyError(
            "no Hevy API key. Pass --key, or set HEVY_API_KEY, or run this in a "
            "terminal so it can be typed without landing in shell history."
        )
    return getpass.getpass("Hevy API key: ").strip()


def _cmd_hevy(args: argparse.Namespace) -> int:
    key = _hevy_key(args.key)
    client = connect()
    activity, activity_id = _pick(client, args.activity, args.yes)

    sets = logged_sets(client, int(activity_id))
    print(f"  read {len(sets)} sets from the activity's FIT file")

    print("  fetching your Hevy exercise catalogue...")
    catalogue = templates(key)
    print(f"  {len(catalogue)} templates, custom exercises included")

    title = activity.name if activity is not None else f"RepFlow {activity_id}"
    body, unmatched = build_workout(title, sets, catalogue, is_private=args.private)
    print(f"  would post \"{title}\": {summarise_hevy(body)}\n")
    _print_hevy_mapping(sets, catalogue)
    if unmatched:
        print(
            "\n  NOT sent — no Hevy template matches:\n    "
            + "\n    ".join(sorted(unmatched))
        )

    if args.json:
        print(json.dumps(body, indent=1))

    existing = already_posted(key, sets[0].start_time)
    if existing is not None:
        print(
            f"\n  Hevy already has a workout starting at that moment "
            f"(\"{existing.get('title')}\"). Posting again would duplicate it."
        )
        if not args.force:
            print("  Nothing sent. Pass --force to post it anyway.")
            return 1

    if args.dry_run:
        print("\nDry run — nothing sent.")
        return 0
    if not args.yes and not confirm("\nPost this workout to Hevy?"):
        print("Nothing sent.")
        return 1

    post_workout(key, body)
    print("Posted. Open Hevy and pull to refresh.")
    return 0


def _print_hevy_mapping(sets: list[Any], catalogue: list[Any]) -> None:
    """Which Hevy movement each RepFlow name became.

    Same reason as the Garmin one: a rejected template id is loud, and a
    plausible but wrong match is silent and lands in the athlete's own training
    history where they will believe it.
    """
    from .hevy import resolve as resolve_hevy

    seen: dict[str, Any] = {}
    counts: dict[str, int] = {}
    for logged in sets:
        template = resolve_hevy(logged.exercise, catalogue)
        if template is None:
            continue
        seen.setdefault(logged.exercise, template)
        counts[logged.exercise] = counts.get(logged.exercise, 0) + 1
    if not seen:
        return

    width = max(len(name) for name in seen)
    print("  Exercise mapping:\n")
    for name, template in seen.items():
        exact = "exact" if name.strip().lower() == template.title.strip().lower() else "matched"
        print(f"    {name:<{width}}  x{counts[name]}  ->  {template.title}  ({exact})")


def _suggest_activities() -> None:
    """List what else is there, rather than leaving the athlete to guess.

    Being told "this one is not a RepFlow activity" is only half an answer; the
    other half is which one is.
    """
    try:
        found = recent_strength(connect(), limit=20)
    except Exception:
        return
    if not found:
        return
    print("\nRecent strength activities:", file=sys.stderr)
    for activity in found:
        print(f"  {activity}", file=sys.stderr)


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

    p_hevy = sub.add_parser("hevy", help="send the session to Hevy")
    p_hevy.add_argument("--activity", type=int, default=None)
    p_hevy.add_argument("--key", default=None, help="Hevy API key; else HEVY_API_KEY, else prompted")
    p_hevy.add_argument("--private", action="store_true", help="post it as a private workout")
    p_hevy.add_argument("--dry-run", action="store_true")
    p_hevy.add_argument("--force", action="store_true", help="post even if Hevy already has it")
    p_hevy.add_argument("--yes", action="store_true", help="do not ask")
    p_hevy.add_argument("--json", action="store_true")
    p_hevy.set_defaults(func=_cmd_hevy)

    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except NotARepFlowActivity as exc:
        print(f"error: {exc}", file=sys.stderr)
        _suggest_activities()
        return 2
    except (GarminError, HevyError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
