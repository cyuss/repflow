# Getting a RepFlow session into Garmin Connect as a real strength activity

Three routes, each investigated against what the current SDKs and APIs actually
expose. Nothing here is assumed; every claim carries its source, and where a
thing is technically possible but not *interpreted* by Garmin Connect, that
distinction is made explicitly.

**The test session, used identically by all three:**

```
Bench Press    3 × 8  × 80 kg
Lat Pulldown   3 × 10 × 60 kg
```

It exists in the suite as `testPocStrengthSession`, so the three routes are
measured against the same data rather than against three different ones.

---

## Summary

| Solution | Garmin activity | Exercises | Sets | Reps | Weight | Native Garmin Connect | Private API | Feasibility |
|---|---|---|---|---|---|---|---|---|
| **A — Connect IQ `ActivityRecording`** | ✅ real FIT, strength | ⚠️ developer field | ⚠️ 1 lap/set | ⚠️ developer field | ⚠️ developer field | ❌ Connect IQ section only | ❌ none | ✅ **shipped** |
| **B — native FIT `set` messages from the watch** | — | ❌ | ❌ | ❌ | ❌ | — | — | ❌ **impossible** |
| **C — native sets written into the recorded activity** | ✅ real FIT, strength | ✅ native | ✅ native | ✅ native | ✅ native | ✅ **muscle map + set table** | ⚠️ yes, unsanctioned | ✅ **implemented, `backend/`** |

⚠️ in the "Private API" column is the whole cost of route C, and it is discussed
under that heading.

---

## RepFlow as it stands

```
Views ──▶ AppController ──▶ WorkoutEngine        (pure, id-based navigation)
               ├──▶ RestTimer
               ├──▶ GarminRecorder ──▶ ActivityRecording   ← route A lives here
               ├──▶ SessionRepository ──▶ Application.Storage
               └──▶ HevySync ──▶ HevyApi ──▶ Hevy REST      ← the existing bridge
```

`WorkoutEngine` navigates by stable exercise id and nothing increments a cursor,
which is what makes "select any exercise at any time" possible. **Every route
below has to preserve that**, and none of them threatens it: all three act at
the moment the session ends, not while it runs.

---

## POC A — Connect IQ `ActivityRecording`

**Status: implemented and shipping.** `source/GarminRecorder.mc`.

```monkeyc
ActivityRecording.createSession({
    :name     => workoutName,
    :sport    => Activity.SPORT_TRAINING,
    :subSport => Activity.SUB_SPORT_STRENGTH_TRAINING
});
```

`SUB_SPORT_STRENGTH_TRAINING` is what makes Garmin Connect label the result
**Strength Training** rather than *Other*.

### What is recorded

| Data | How | Where it shows |
|---|---|---|
| Duration, work time | the session itself | activity summary |
| Heart rate, avg/max, time in zone | the watch, automatically | activity summary and charts |
| Calories | the watch, automatically | activity summary |
| Activity name | `:name` on `createSession` | activity title |
| One lap per completed set | `Session.addLap()` | Laps table |
| Exercise, set number, reps, load | developer fields at `MESG_TYPE_LAP` | **Connect IQ section** of Activity Details |
| Session totals: sets, reps, volume | developer fields at `MESG_TYPE_SESSION` | Connect IQ section of the summary |

Developer fields only render if declared in resources — see
`resources/fit_contributions.xml`. The SDK is explicit: *"Field id **must** match
the fitField id in resources or your data will not display!"*
([Activity Recording, Connect IQ Core Topics](https://developer.garmin.com/connect-iq/core-topics/activity-recording/)).
RepFlow shipped once without that block, and every field was invisible.

### What is lost

- **The muscle map.** It is derived from the exercise `category` on FIT `set`
  messages. No set messages, no diagram.
- **Garmin's native per-set table.** Same cause.
- Rest periods as first-class objects. A lap boundary is the only marker.

#### Observed on hardware — 13 Sep 2026, Fenix 6 Pro 47 mm

![Garmin Connect showing a RepFlow activity: native Strength Training, empty
exercise table](evidence/connect-strength-empty-table.png)

This settles the first half of POC B by observation rather than by reading the
SDK, and it is worth being precise about what it shows.

The activity **is** native. Garmin Connect titles it *Strength Training*, carries
the workout's own name through from RepFlow, and computes heart rate and
calories from it. Nothing about it is quarantined into a Connect IQ ghetto.

And the `EXERCISES` table is **there, with its native columns — `Set | Name |
Time | Reps | Weight kg` — and empty**, offering *Add Exercise +* instead. Those
columns are fed by FIT `set` messages. RepFlow cannot write them, so Garmin has
the table and no rows to put in it.

That is the distinction this document draws, made visible: **the activity is
native, its contents are not.** Anyone who assumes "it records a strength
activity" implies "the sets appear" can look at this screenshot instead.

It also shows the table is **user-editable**, which is the shape route C
targets: those rows are real Garmin objects, not a rendering of developer
fields.

### Limitations found in practice

- A running recording **blocks Garmin's sleep tracking**, so it must be closed
  on every exit — `AppController.onAppStop` does.
- A recording **cannot be reattached** after an app restart; a resumed workout
  starts a fresh one.
- `Session` has **no pause/resume**: only `stop()` then `start()`.

### Answered on hardware — 14 Sep 2026

**A Connect IQ recording does produce a Training Effect.** The session message
of a real RepFlow activity, read back from Garmin's own servers:

```
total_calories            328
avg_heart_rate            100
max_heart_rate            140
total_training_effect     0.7
total_anaerobic_training_effect   0.0
enhanced_avg_respiration_rate     21.84
```

So the firmware treats it as it treats any recorded activity: heart rate,
calories, respiration and an aerobic training effect are all computed and
written. That settles the second of this document's two open questions, and it
settles it the way the first one was — by looking at a real file rather than by
reasoning about what ought to happen.

The remaining open question is the first: whether a **string** developer field
renders in Garmin Connect's laps table.

---

## POC B — native FIT strength structures from the watch

**Status: impossible. Not "hard", not "undocumented" — the API does not exist.**

### What a native strength FIT file contains

Established by reading a working implementation that produces exactly the
Garmin Connect view in question
([hevy2garmin](https://github.com/intergalacticwiseguy/hevy2garmin), `src/hevy2garmin/fit.py`),
cross-checked against the [FIT SDK](https://developer.garmin.com/fit/) and its
[Profile.xlsx](https://developer.garmin.com/fit/protocol/), which is the
authoritative list of FIT messages and fields:

```
FileIdMessage
SportMessage
ExerciseTitleMessage   message_index, exercise_category, exercise_name,
                       workout_step_name        ← custom exercise names
EventMessage           TIMER / START
RecordMessage          timestamp, heart_rate    ← the HR trace
SetMessage             timestamp, start_time, duration,
                       set_type = ACTIVE | REST,
                       category[], category_subtype[],
                       message_index, workout_step_index,
                       repetitions, weight      ← the set table AND the muscle map
LapMessage
SessionMessage
ActivityMessage
```

**`SetMessage.category` is the muscle map.** Garmin maps its own exercise
category enum to muscle groups; there is no other input to that diagram.

### What Connect IQ exposes

`ActivityRecording.Session` has exactly eight methods:

```
addLap()   createField()   discard()   isRecording()
save()     setTimerEventListener()     start()   stop()
```

And a developer field can target exactly three message types — this is the
complete list from `Toybox.FitContributor`:

```
MESG_TYPE_RECORD     MESG_TYPE_LAP     MESG_TYPE_SESSION
```

**There is no `MESG_TYPE_SET`, and no `addSet()`.**

Verified three independent ways against the installed SDK 9.2.0:

1. The HTML API documentation for `ActivityRecording`, `Session` and `FitContributor`.
2. The full method list (`doc/method_list.html`) searched for every symbol
   containing *set*, *repetition* or *exercise*. The only `repetitionNumber` in
   the API belongs to workout **interval** steps and is unrelated to strength.
3. The compiled symbol table `bin/api.debug.xml`.

The suite asserts it, so it cannot rot quietly:

```monkeyc
Test.assert(!(FitContributor has :MESG_TYPE_SET));
```

### Confirmed outside this project

> *"ConnectIQ — the SDK available to third-party developers — has no mechanism
> to write Set messages into a FIT file at all."*
> *"The critical function, `addSet()`, does not exist."*
> *"A third-party app cannot produce a FIT file that Garmin Connect would
> recognise as a proper strength session."*
> — [the5krunner, March 2026](https://the5krunner.com/2026/03/24/garmin-connect-plus-strength-apps/)

### `:nativeNum` — the one remaining thread, and why it is not pulled

`Session.createField()` accepts `:nativeNum`, which maps a developer field onto
a native FIT field number. It cannot help here: it changes how a field inside a
**record, lap or session** message is interpreted. It cannot conjure a message
type that the API will not emit. And the FIT profile defining those numbers does
not ship with the Connect IQ SDK, so using it at all would mean guessing.

### Technically possible ≠ natively interpreted

This is the distinction the mission asked for, and it is the whole of POC B:

- **Technically possible from Connect IQ:** arbitrary numeric and string data on
  record, lap and session messages. Garmin Connect *displays* it, in its
  Connect IQ section, if declared in `fitContributions`.
- **Natively interpreted by Garmin Connect:** only what arrives in the message
  types Garmin defines for strength — `set`, `exercise_title`. Connect IQ cannot
  write either.

---

## POC C — backend generating FIT and uploading

**Status: feasible, demonstrated by a working project, and the only route that
produces the muscle map.**

```
RepFlow (watch) ──▶ Hevy REST ──▶ RepFlow backend ──▶ Garmin Connect
                    (already built)   generate FIT      upload activity
```

### What the official Garmin Connect Developer Program allows

From [the program overview](https://developer.garmin.com/gc-developer-program/overview/):

| API | Direction | What it does |
|---|---|---|
| Health API | **read** | all-day metrics: heart rate, sleep, steps |
| Activity API | **read** | full activity data for 30+ activity types |
| Women's Health API | **read** | cycle and pregnancy data |
| **Training API** | **write** | *"Publish structured workouts and training plans for users to sync to compatible Garmin devices"* |
| Courses API | **write** | publish courses for automatic syncing |

**There is no official API to upload a completed activity.** The Activity API
reads; it does not accept. This is the decisive finding for route C.

All of these require Garmin approval and a signed agreement — the program is
aimed at companies, and access is described as *"throttled access"* against
production.

### What the Training API would give, and why it is not enough alone

It can push a **structured workout** to the watch. That is the LiftTrack model:
build the plan in an app, sync it to Garmin Connect, then **run it in Garmin's
native strength mode**, which writes the set messages itself.

That produces a perfect Garmin Connect result — and **destroys RepFlow's reason
to exist**, because the native player owns the order. No deferring an occupied
machine, no choosing any exercise at any time. It is the opposite trade.

### The route that actually works — and it is better than uploading a file

The obvious move is the one [hevy2garmin](https://github.com/intergalacticwiseguy/hevy2garmin)
makes: build a complete FIT file server-side, with `ExerciseTitleMessage` +
`SetMessage` per set, and upload it through `garminconnect`'s
`client.upload_activity`. It works, in production, today.

But it creates a **second activity**. RepFlow has already recorded one, with the
athlete's real heart rate, their real calories, their real timing — and an
uploaded duplicate has none of that unless the file reproduces it, after which
there are two activities and one of them has to be deleted.

There is a better endpoint, and it is the one Garmin Connect's own web client
uses when a person edits a strength activity by hand:

```
GET  /activity-service/activity/{id}/exerciseSets
PUT  /activity-service/activity/{id}/exerciseSets
```

The PUT writes native exercise sets **into an activity that already exists**.
So the activity RepFlow recorded keeps everything it measured, and only the set
table is filled in. Nothing is uploaded twice and nothing has to be deleted.

The body, confirmed against a payload posted by a Garmin Connect user and
against what `cyberjunky/python-garminconnect` sends:

```json
{"activityId": 4172875329,
 "exerciseSets": [
   {"exercises": [{"category": "BENCH_PRESS",
                   "name": "BARBELL_BENCH_PRESS",
                   "probability": 100.0}],
    "duration": 26.9,
    "repetitionCount": 8,
    "weight": 80000.0,
    "setType": "ACTIVE",
    "startTime": "2026-09-13T12:07:33.0",
    "wktStepIndex": null}]}
```

Weight in **grams**. `setType` is `ACTIVE` or `REST`, which is what feeds Work
Time and Rest Time. Semantics are replace-all.

Two properties make this materially better than the upload route:

- **The source data is already on Garmin's servers.** RepFlow writes the
  exercise, set number, reps and load as developer fields on every lap, and
  developer fields are self-describing — the FIT file carries its own field
  definitions. Downloading the original activity and reading them back needs no
  Hevy, no watch change, and no capture at the time. **Every RepFlow activity
  ever recorded can be filled in retroactively.**
- **It is additive.** The heart rate, calories and duration the watch measured
  are untouched.

### What is missing, concretely

1. Garmin Connect authentication per athlete. There is no way around signing in
   as the person whose activity it is.
2. An exercise → Garmin enum map. Garmin validates `(category, name)` against
   its own catalogue — 1527 movements in 47 categories — and rejects the whole
   request for one unknown value. The category is also what draws the muscle
   map, so a confident wrong answer is worse than an unspecific right one.
3. A decision about operating outside Garmin's terms of service.

### Implemented

`backend/` does all three. `repflow-garmin fill` downloads the activity's
original FIT, reads RepFlow's laps out of it, resolves each exercise against
Garmin's enum, and PUTs the set list. RepFlow's own eighty movements are mapped
by hand — fuzzy matching filed "Barbell Curl" as a barbell *wrist* curl and
"Back Extension" under resistance bands, both plausible and both the wrong
muscle group — and anything unrecognisable is reported rather than guessed. See
[`../backend/README.md`](../backend/README.md).

The watch gained one field for this: `rest`, the seconds the athlete actually
rested before each set. A RepFlow lap is closed when a set is logged, so it
spans the rest *and* the set; without that number the two cannot be separated
afterwards, and Garmin's Work Time / Rest Time have nothing to read.

---

## Recommendation

**Keep route A as the product, add route C as an option, never pursue route B.**

### Why

The mission's stated priority is to keep RepFlow's flexible navigation *and*
land as close to a native strength activity as possible. Those two pull in
opposite directions, and the ordering matters:

- Route **B** is closed. Not a matter of effort.
- Route **C**'s *official* half — the Training API — buys a native activity by
  handing the order back to Garmin's player. That fails the first requirement
  outright, so it is not a candidate.
- Route **C**'s *working* half — write native exercise sets into the activity
  RepFlow already recorded — preserves navigation completely, because it acts
  after the session is over. It is the only way to get the muscle map. It costs
  a Garmin Connect sign-in and sits outside Garmin's terms.
- Route **A** preserves navigation, ships today, needs nothing, and gives the
  athlete every physiological metric plus a labelled set list in the Connect IQ
  section.

### What RepFlow should do

**Now (done):** route A, with the `fitContributions` block so the per-lap detail
is actually drawn, and Hevy carrying the set table, volume, records and
per-muscle analytics. That is the same split Rack uses — set detail in a
companion app, physiology in Garmin Connect — with the difference that Hevy is
an app the athlete already keeps their training in.

**Next (done):** route C as an opt-in, in `backend/`. It reads the activity
Garmin already stores rather than anything the watch sends, so an athlete who
never runs it is unaffected and one who runs it a year late gets the same
result.

**Before either:** settle the two things documentation cannot.

1. Does a **string** developer field render in Garmin Connect's laps table? The
   exercise name is one. Numbers are documented; text is not.
2. Does a Connect IQ recording contribute to **Training Load / Training Effect /
   Training Readiness**?

Both are answered by one real session on a real watch.

---

## Test steps

### In the simulator

```sh
make test DEVICE=fenix6pro     # includes testPocStrengthSession
make sim DEVICE=fenix6pro
```

Perform Bench Press 3 × 8 × 80 and Lat Pulldown 3 × 10 × 60, end the workout and
choose **Save**. The simulator writes a FIT file it will not upload, so what this
proves is that the session, the laps and the fields are produced without error —
not what Garmin Connect renders.

### On a real watch — the part that actually settles it

```sh
make sideload DEVICE=fenix6pro
```

1. Perform the same two exercises.
2. End the workout, **Save**, and let the watch sync.
3. In Garmin Connect, open the activity and record:
   - is it titled and typed as **Strength Training**?
   - laps: is there one per set?
   - does the Connect IQ section show **Exercise / Set / Reps / Weight** per lap,
     and does the exercise **name** appear as text?
   - is there a muscle map? (expected: no)
   - next morning: did **Training Readiness** or **Training Load** move?
4. Write the answers into this file. Two of them are currently open questions
   and they are the only things standing between this document and complete.
