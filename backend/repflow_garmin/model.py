"""The one value type that travels between the layers.

Everything upstream of this (a FIT file, one day perhaps a Hevy export) produces
`LoggedSet`s, and everything downstream consumes them. Keeping the shape small
and frozen is what lets the payload builder be a pure function with real tests
rather than something that can only be exercised against a live account.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class LoggedSet:
    """One set as RepFlow recorded it.

    `start_time` is the start of the **lap**, which is not the start of the set:
    a RepFlow lap is closed when a set is logged, so it spans the rest taken
    before the set plus the set itself. `rest_s` is how much of that leading
    span was rest, when the watch recorded it — see `duration_s` below.

    `weight_kg` is None for a bodyweight movement, and that is different from
    0.0. Garmin renders a null weight as blank and a zero as "0 kg", which is a
    claim about the lift rather than an absence of one.
    """

    exercise: str
    set_number: int
    reps: int
    weight_kg: float | None
    start_time: datetime
    duration_s: float
    rest_s: float | None = None

    @property
    def work_s(self) -> float:
        """How long the set itself took, once the leading rest is removed.

        Falls back to the whole lap when the watch did not record a rest — an
        overstatement, but a bounded one, and the alternative is inventing a
        split from nothing.
        """
        if self.rest_s is None:
            return self.duration_s
        return max(0.0, self.duration_s - self.rest_s)
