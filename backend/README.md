# `repflow-garmin` — fill in Garmin Connect's strength table

RepFlow records a real Garmin strength activity. What it cannot do is fill in
the exercise table Garmin Connect shows underneath it:

```
EXERCISES                                                    EDIT
Set   Name                      Time    Reps    Weight
                                                  kg
Add Exercise                                                    +
```

That table, the work/rest split, `Total Reps`, `Total Sets` and the muscle map
are all drawn from FIT `set` messages, and Connect IQ cannot write those — three
independent verifications against SDK 9.2.0 are in
[`../docs/garmin-strength-integration-poc.md`](../docs/garmin-strength-integration-poc.md).

This tool fills the table from the other side, after the fact.

**It is not a server.** "Backend" names where it sits in the picture below, not
a thing that runs. See [Use](#use).

## How it works

```
watch                    Garmin Connect                 this tool
──────────────────────────────────────────────────────────────────────────
RepFlow records
 one lap per set,   ──▶  activity stored
 exercise/set/reps/       with the laps    ──▶  download the original FIT
 load/rest as                                   read the developer fields
 developer fields                               map names to Garmin's enum
                         native exercise  ◀──   PUT /exerciseSets
                         table filled in
```

Nothing is uploaded twice and no second activity is created. The heart rate,
calories, duration and timing the watch measured are untouched — only the set
list is written.

**Every RepFlow activity you have ever recorded can be filled in retroactively**,
because the data was always in the FIT file. Nothing had to be captured at the
time.

## Setup

```sh
make backend-setup            # from the repository root
```

## Use

```sh
make sync-garmin-show         # what would be written, writes nothing
make sync-garmin              # write it, after confirming

make sync-hevy-show           # what would be posted to Hevy, posts nothing
make sync-hevy                # post it, after confirming
```

Nothing runs between those commands. This is a program you start, which talks to
Garmin and exits — not a service, not a daemon, nothing listening. Run it after a
session, or once a month to catch up on the last ten: it reads the activities
Garmin already stores, so it works just as well a year later.

The full command, for the options the `make` targets do not cover:

```sh
backend/.venv/bin/repflow-garmin list           # which activities can be filled in
backend/.venv/bin/repflow-garmin fill --activity 123
backend/.venv/bin/repflow-garmin fill --dry-run
backend/.venv/bin/repflow-garmin hevy --private
```

Both `make` targets take `ACTIVITY=` to name one; `just` takes it positionally.

## Hevy

`make sync-hevy` sends the same session to Hevy, read from the same place — the
FIT file on Garmin's servers. The watch posts to Hevy itself when it can; this
is how to catch up when it could not, and it works weeks later without the watch
being involved.

It asks for your Hevy API key (Hevy app → Settings → Developer) and **does not
store it**. Garmin's session token is cached because Garmin issued it and can
revoke it; a Hevy key is read and write over your entire training history and
cannot be scoped, so it is asked for each time. `HEVY_API_KEY` works if you
prefer, bearing in mind that an environment variable is visible to everything in
the session.

Two of Hevy's rules lose the **whole** workout rather than one set when broken,
so both are enforced before anything is sent:

- `exercise_template_id` must be a real template. Your own custom exercises are
  fetched along with Hevy's, and a movement that matches nothing is reported
  rather than filed under the nearest one.
- `rpe` must be 6, 7, 7.5, 8, 8.5, 9, 9.5 or 10. There is no 6.5.

The endpoint creates rather than updates, so running it twice would put the
session in twice. It checks your recent workouts for one starting at the same
moment and stops if it finds one; `--force` overrides that.

Each command asks **which session** first — arrow keys through your recent
strength activities, Enter to choose, `q` to cancel. It guesses only when there
is nobody to ask: a pipe, a cron job, or `--yes`, and then it says out loud
which one it took. This tool once acted on the session from the day before, and
a guess printed after the fact is not the same as being asked.

`fill` prints the payload, says how many sets it is replacing, and asks before
writing. `--dry-run` never writes; `--yes` skips the question; `--activity <id>`
picks a specific activity instead of the most recent strength one.

## What this costs, stated plainly

**It is not part of Garmin's developer program.** Garmin's official APIs read
activities and write training *plans*; none of them uploads or edits a completed
activity. The two endpoints used here —

```
GET  /activity-service/activity/{id}/exerciseSets
PUT  /activity-service/activity/{id}/exerciseSets
```

— are the ones Garmin Connect's own web client calls when a person edits a
strength activity by hand. Using them programmatically is outside Garmin's terms
of service. They can change without notice, and this tool would then stop
working.

**It signs in as you.** There is no other way to write to your own activities.
The password is read from the environment or typed into your own terminal and is
never stored; only the session token Garmin itself issues is cached, in
`~/.garminconnect`. Deleting that directory signs out. Nothing is sent anywhere
except to Garmin.

**The PUT replaces the whole set list.** If you have edited an activity's
exercises by hand in Garmin Connect, filling it will overwrite that. The tool
reads the existing sets first and tells you how many it is about to replace.

## What it can and cannot identify

Garmin validates every exercise against its own enum — 1527 movements in 47
categories — and rejects the whole request if one is unknown. The category is
also what draws the muscle map, so a set filed under the wrong category is worse
than one filed under no specific variant.

So the mapping is deliberately conservative:

1. RepFlow's own eighty movements are **mapped by hand** in `mapping.py`. A test
   fails if the watch app gains an exercise that has no entry.
2. Anything else — a Hevy import, a custom exercise — goes through token
   matching against Garmin's catalogue.
3. When the variant is not convincing, the **category is kept and the variant
   dropped**. Garmin then shows the category's own name, which is true.
4. What cannot be identified at all is **reported, not guessed**. `show` and
   `fill` name every exercise that will be missing from the table.

Garmin's enum has real gaps — no pec deck, no skullcrusher, no triceps pushdown,
no leg extension as a quad machine. Those are mapped to their category with the
variant left off, and each one says so in `mapping.py`.

## Layout

| File | What it does |
|---|---|
| `model.py` | `LoggedSet` — the one value type between the layers |
| `fitread.py` | Read RepFlow's laps out of a FIT file |
| `catalogue.py` | Garmin's exercise enum, and name matching |
| `mapping.py` | RepFlow's vocabulary, mapped by hand |
| `payload.py` | Build the request body — pure, fully tested |
| `garmin.py` | Sign in, download, read and write the sets |
| `hevy.py` | Match movements to Hevy templates and build the workout |
| `cli.py` | The command line |
| `tui.py` | Choosing from a list with the arrow keys |

`payload.py`, `mapping.py` and `catalogue.py` are pure and need no account, which
is why most of the test suite runs without one. `tests/fitfixture.py` builds FIT
files with **Garmin's own** Python SDK encoder, so the reader is tested against
Garmin's definition of the format rather than against its own assumptions.

```sh
make test-backend
```

`tests/test_watch_contract.py` is the one to read first: it parses
`source/GarminRecorder.mc` and `resources/fit_contributions.xml` and fails if the
Monkey C side and this side ever stop agreeing about the developer fields.
