"""Fill Garmin Connect's native strength table from a RepFlow activity.

RepFlow records a genuine strength activity on the watch, but Connect IQ cannot
write the FIT `set` messages that Garmin Connect's exercise table, work/rest
split and muscle map are built from — see docs/garmin-strength-integration-poc.md.
What it *can* write is one lap per set carrying the exercise, set number, reps
and load as developer fields, and it already does.

This package closes the gap from the other side: it reads those laps back out of
the activity Garmin already has, and writes them into that activity as native
exercise sets. The activity is not replaced and nothing is uploaded twice — the
heart rate, calories and timing the watch measured stay exactly as they are.
"""

__all__ = ["__version__"]

__version__ = "0.1.0"
