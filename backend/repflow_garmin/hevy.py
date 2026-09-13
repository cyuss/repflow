"""Push a RepFlow session to Hevy, from the activity Garmin already stores.

The watch posts to Hevy itself when it can. It cannot always: the phone may be
out of range at the end of a session, Bluetooth may have dropped, the key may
not have been entered yet. This is the way to catch up afterwards, and it reads
the same source as the Garmin path — the FIT file on Garmin's servers — so a
session can be recovered weeks later without the watch being involved at all.

Two things Hevy's API is strict about, and both lose the **whole** workout
rather than one set when they are wrong:

  * `exercise_template_id` must be a real template id. There is no free-text
    exercise name.
  * `rpe` must be one of 6, 7, 7.5, 8, 8.5, 9, 9.5, 10.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from .catalogue import _tokens
from .model import LoggedSet

BASE = "https://api.hevyapp.com/v1"

#: Hevy pages its listings, and caps the page size per endpoint.
TEMPLATE_PAGE_SIZE = 100
WORKOUT_PAGE_SIZE = 10

#: Exactly the values Hevy accepts. Mirrors source/Rpe.mc — a test asserts the
#: two agree, because they are the same rule written in two languages.
RPE_SCALE = (6.0, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0)


class HevyError(Exception):
    pass


@dataclass(frozen=True)
class Template:
    """One movement in Hevy's exercise catalogue."""

    id: str
    title: str

    @property
    def tokens(self) -> frozenset[str]:
        return frozenset(_tokens(self.title))


def _request(path: str, key: str, method: str = "GET", body: dict | None = None) -> Any:
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(
        f"{BASE}{path}",
        data=data,
        method=method,
        headers={
            "api-key": key,
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")[:400]
        if exc.code in (401, 403):
            raise HevyError(
                "Hevy rejected the API key. Check it in the Hevy app under "
                "Settings -> Developer."
            ) from exc
        raise HevyError(f"Hevy answered {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise HevyError(f"could not reach Hevy: {exc.reason}") from exc


def templates(key: str, max_pages: int = 30) -> list[Template]:
    """Hevy's whole exercise catalogue, custom movements included.

    Fetched rather than shipped: the athlete's own custom exercises are in here,
    and they are exactly the ones a hard-coded list would miss.
    """
    found: list[Template] = []
    for page in range(1, max_pages + 1):
        body = _request(
            f"/exercise_templates?page={page}&pageSize={TEMPLATE_PAGE_SIZE}", key
        ) or {}
        rows = body.get("exercise_templates") or []
        for row in rows:
            template_id, title = row.get("id"), row.get("title")
            if isinstance(template_id, str) and isinstance(title, str):
                found.append(Template(id=template_id, title=title))
        if len(rows) < TEMPLATE_PAGE_SIZE:
            break
    if not found:
        raise HevyError("Hevy returned no exercise templates")
    return found


def resolve(name: str, catalogue: Iterable[Template]) -> Template | None:
    """Match a RepFlow exercise name to a Hevy template.

    Exact title first, because a name that came *from* Hevy — every routine
    RepFlow imports — is already a Hevy title and must not be re-guessed. Then
    the same word-set comparison the Garmin mapping uses, which absorbs the
    truncation the watch applies to a FIT string.

    Returns None rather than a best guess: a set filed under the wrong movement
    is worse in someone's training history than a set that is missing from it.
    """
    rows = list(catalogue)
    wanted = name.strip().lower()
    for template in rows:
        if template.title.strip().lower() == wanted:
            return template

    query = frozenset(_tokens(name))
    if not query:
        return None
    best: Template | None = None
    best_score = 0.0
    for template in rows:
        candidate = template.tokens
        if not candidate:
            continue
        overlap = len(query & candidate)
        if not overlap:
            continue
        score = 1.0 if query == candidate else overlap / len(query | candidate)
        if score > best_score or (
            score == best_score and best is not None and len(template.title) < len(best.title)
        ):
            best, best_score = template, score
    # The same threshold the Garmin mapping uses, for the same reason.
    return best if best_score >= 0.60 else None


def _rpe(value: float | None) -> float | None:
    """Drop a rating Hevy's enumeration does not contain."""
    if value is None:
        return None
    for allowed in RPE_SCALE:
        if abs(allowed - value) < 0.01:
            return allowed
    return None


def _iso(moment: datetime) -> str:
    """`2026-09-13T12:07:00Z` — Hevy wants a zoned timestamp."""
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def build_workout(
    title: str,
    sets: Iterable[LoggedSet],
    catalogue: Iterable[Template],
    is_private: bool = False,
) -> tuple[dict[str, Any], list[str]]:
    """Build the POST /v1/workouts body, and report what could not be matched.

    Consecutive sets of the same movement are grouped into one exercise, in the
    order they were performed. That order is the point of this app — an athlete
    who goes A, B, A gets three entries, because that is what happened, and
    collapsing them would rewrite the session into one they did not do.
    """
    rows = list(catalogue)
    ordered = sorted(sets, key=lambda s: s.start_time)
    if not ordered:
        raise HevyError("no sets to send")

    exercises: list[dict[str, Any]] = []
    unmatched: list[str] = []
    seen_unmatched: set[str] = set()
    current: dict[str, Any] | None = None
    current_name: str | None = None

    for logged in ordered:
        template = resolve(logged.exercise, rows)
        if template is None:
            if logged.exercise not in seen_unmatched:
                seen_unmatched.add(logged.exercise)
                unmatched.append(logged.exercise)
            current, current_name = None, None
            continue

        if current is None or current_name != logged.exercise:
            current = {
                "exercise_template_id": template.id,
                "superset_id": None,
                "notes": None,
                "sets": [],
            }
            current_name = logged.exercise
            exercises.append(current)

        current["sets"].append(
            {
                "type": "normal",
                # A bodyweight set has no load, and null is what Hevy's own
                # schema asks for. A zero would claim the athlete lifted nothing.
                "weight_kg": logged.weight_kg,
                "reps": logged.reps,
                "rpe": _rpe(logged.rpe),
            }
        )

    if not exercises:
        raise HevyError(
            "none of the exercises in this session matched a Hevy template: "
            + ", ".join(sorted(seen_unmatched))
        )

    body = {
        "workout": {
            "title": title,
            "description": None,
            "start_time": _iso(ordered[0].start_time),
            "end_time": _iso(ordered[-1].start_time),
            "is_private": is_private,
            "exercises": exercises,
        }
    }
    return body, unmatched


def already_posted(key: str, start: datetime) -> dict[str, Any] | None:
    """A workout already in Hevy that starts at the same moment.

    The endpoint is a create, not an upsert: running the command twice would
    put the session in twice. Start time is the identity — two RepFlow sessions
    cannot begin in the same second.
    """
    body = _request(f"/workouts?page=1&pageSize={WORKOUT_PAGE_SIZE}", key) or {}
    wanted = _iso(start)[:19]
    for workout in body.get("workouts") or []:
        existing = str(workout.get("start_time") or "")
        if existing[:19] == wanted:
            return workout
    return None


def post_workout(key: str, body: dict[str, Any]) -> Any:
    return _request("/workouts", key, method="POST", body=body)


def summarise(body: dict[str, Any]) -> str:
    """One line describing what is about to be created in someone's history."""
    exercises = body["workout"]["exercises"]
    sets = sum(len(e["sets"]) for e in exercises)
    reps = sum(s["reps"] or 0 for e in exercises for s in e["sets"])
    volume = sum(
        (s["weight_kg"] or 0.0) * (s["reps"] or 0) for e in exercises for s in e["sets"]
    )
    return (
        f"{_count(len(exercises), 'exercise')}, {_count(sets, 'set')}, "
        f"{_count(reps, 'rep')}, {volume:,.0f} kg"
    )


def _count(n: int, noun: str) -> str:
    return f"{n} {noun}" if n == 1 else f"{n} {noun}s"
