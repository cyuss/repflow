"""The authenticated half: find the activity, read it, write the sets back.

Two endpoints do the work, and neither is part of Garmin's developer program:

    GET  /activity-service/activity/{id}/exerciseSets
    PUT  /activity-service/activity/{id}/exerciseSets

They are the ones Garmin Connect's own web client uses when a person edits a
strength activity by hand. Using them means signing in as the athlete, which is
why this runs on the athlete's own machine and stores nothing but the session
token Garmin itself issues. See the README for what that costs and what it does
not.

The PUT **replaces** the activity's whole set list. Nothing here ever writes
without having read first, so an activity that already has sets — edited by hand
in Garmin Connect, or filled in by a previous run — is reported rather than
quietly overwritten.
"""

from __future__ import annotations

import os
import pathlib
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from garminconnect import Garmin

from .fitread import read_sets, unzip
from .model import LoggedSet

#: Where the Garmin-issued session tokens are cached. Not a password: these
#: expire, and deleting the directory signs out.
TOKEN_STORE = os.getenv("GARMINTOKENS", "~/.garminconnect")

#: The activity type Garmin assigns to what RepFlow records
#: (`SPORT_TRAINING` + `SUB_SPORT_STRENGTH_TRAINING`). Kept strict on purpose:
#: filling the wrong activity's set table is a destructive mistake, and an
#: activity that does not match can always be named by its id.
STRENGTH_TYPES = frozenset({"strength_training"})


class GarminError(Exception):
    pass


@dataclass(frozen=True)
class ActivitySummary:
    """Just enough of Garmin's activity record to choose one and report on it."""

    activity_id: int
    name: str
    start_local: str
    activity_type: str

    @classmethod
    def parse(cls, raw: dict[str, Any]) -> "ActivitySummary":
        type_key = (raw.get("activityType") or {}).get("typeKey") or "?"
        return cls(
            activity_id=int(raw["activityId"]),
            name=str(raw.get("activityName") or "Untitled"),
            start_local=str(raw.get("startTimeLocal") or "?"),
            activity_type=type_key,
        )

    def __str__(self) -> str:
        return f"{self.activity_id}  {self.start_local}  {self.name} ({self.activity_type})"


def connect(email: str | None = None, password: str | None = None) -> Garmin:
    """Sign in, reusing a cached token when there is one.

    The password is read from the environment or prompted for in the operator's
    own terminal, and is never written anywhere. Only Garmin's tokens are
    cached, in `TOKEN_STORE`.
    """
    import getpass
    import sys

    store = str(pathlib.Path(TOKEN_STORE).expanduser())

    client = Garmin(prompt_mfa=lambda: input("Garmin MFA code: ").strip())
    try:
        client.login(store)
        return client
    except Exception:
        pass  # no usable cached token; fall through to a full sign-in

    email = email or os.getenv("GARMIN_EMAIL")
    password = password or os.getenv("GARMIN_PASSWORD")
    if (not email or not password) and not sys.stdin.isatty():
        # Prompting into a pipe produces an EOFError three frames deep, which
        # reads as a bug rather than as "this needs a terminal".
        raise GarminError(
            "Garmin Connect sign-in needs a terminal. Run this in your own "
            "shell, or set GARMIN_EMAIL and GARMIN_PASSWORD — bearing in mind "
            "that an environment variable is visible to everything in the "
            "session and usually lands in shell history."
        )
    email = email or input("Garmin Connect email: ").strip()
    password = password or getpass.getpass("Garmin Connect password: ")
    client = Garmin(
        email=email,
        password=password,
        prompt_mfa=lambda: input("Garmin MFA code: ").strip(),
    )
    client.login()
    try:
        client.client.dump(store)
    except Exception as exc:  # a failed cache costs a re-login, not the run
        print(f"  (could not cache the session token: {exc})")
    return client


def recent_strength(client: Garmin, limit: int = 20) -> list[ActivitySummary]:
    """The athlete's recent strength activities, newest first."""
    raw = client.get_activities(0, limit)
    return [
        ActivitySummary.parse(a)
        for a in raw
        if (a.get("activityType") or {}).get("typeKey") in STRENGTH_TYPES
    ]


def latest_strength(client: Garmin) -> ActivitySummary:
    found = recent_strength(client, limit=20)
    if not found:
        recent = [ActivitySummary.parse(a) for a in client.get_activities(0, 10)]
        listing = "\n  ".join(str(a) for a in recent) or "(none)"
        raise GarminError(
            "no strength activity among the last 20. Name one by id with "
            f"--activity. Recent activities:\n  {listing}"
        )
    return found[0]


def logged_sets(client: Garmin, activity_id: int) -> list[LoggedSet]:
    """Download the original FIT and read RepFlow's laps out of it."""
    raw = client.download_activity(
        str(activity_id), dl_fmt=Garmin.ActivityDownloadFormat.ORIGINAL
    )
    return read_sets(unzip(raw))


def existing_sets(client: Garmin, activity_id: int) -> list[dict[str, Any]]:
    """Whatever exercise sets the activity already has."""
    url = f"/activity-service/activity/{activity_id}/exerciseSets"
    body = client.connectapi(url) or {}
    sets = body.get("exerciseSets")
    return list(sets) if isinstance(sets, list) else []


def write_sets(client: Garmin, activity_id: int, payload: dict[str, Any]) -> Any:
    """Replace the activity's exercise sets.

    Garmin validates each `(category, name)` against its own enum and answers
    400 "Invalid Sub-Category Passed" for anything it does not know — which
    rejects the entire request, not the offending row. `mapping.resolve` is what
    keeps that from happening; this is the last mile.
    """
    url = f"/activity-service/activity/{activity_id}/exerciseSets"
    return client.client.put("connectapi", url, json=payload, api=True)


def now_utc() -> datetime:
    return datetime.now(timezone.utc)
