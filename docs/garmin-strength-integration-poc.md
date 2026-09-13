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
| **C — backend generating FIT + upload** | ✅ real FIT, strength | ✅ native | ✅ native | ✅ native | ✅ native | ✅ **muscle map + set table** | ⚠️ yes, unsanctioned | ⚠️ needs a server |

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

### Unverified

Whether the session contributes to **Training Load / Training Effect / Training
Readiness**. Those are computed by firmware from a recorded activity, and a
Connect IQ recording is one — but this is firmware behaviour and has not been
observed on hardware. RepFlow's materials no longer claim it either way.

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

### The route that actually works

[hevy2garmin](https://github.com/intergalacticwiseguy/hevy2garmin) does exactly
what this POC needs, in production, today:

- maps 433+ Hevy exercises to **Garmin FIT exercise categories**
- builds a FIT file with `ExerciseTitleMessage` + `SetMessage` per set, plus
  `RecordMessage` heart-rate samples
- uploads it with `garminconnect` → `client.upload_activity(fit_path)`

`upload_activity` is the **reverse-engineered Garmin Connect web endpoint**, not
a program API. That is the ⚠️ in the table:

- no Garmin approval, no agreement, works for an individual today
- **unsanctioned**: it can break without notice, and it is outside Garmin's terms
- it needs the user's Garmin Connect credentials, which is a real security
  burden for anyone but the user themselves

For RepFlow specifically, the pieces already built carry most of this: `HevyMap`
produces exactly the exercise/set/rep/weight structure a FIT builder needs, and
`HevySync` already posts it. A backend would consume the same payload.

### What is missing, concretely

1. A server. RepFlow is currently a watch app with no infrastructure.
2. An exercise → FIT category map. RepFlow's catalogue has 82 movements with
   muscle groups; Garmin's `exercise_category` enum is a different vocabulary.
3. Garmin Connect authentication per user.
4. A decision about operating an unsanctioned integration.

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
- Route **C**'s *working* half — generate FIT server-side and upload — preserves
  navigation completely, because it acts after the session is over. It is the
  only way to get the muscle map. It costs a server and sits outside Garmin's
  terms.
- Route **A** preserves navigation, ships today, needs nothing, and gives the
  athlete every physiological metric plus a labelled set list in the Connect IQ
  section.

### What RepFlow should do

**Now (done):** route A, with the `fitContributions` block so the per-lap detail
is actually drawn, and Hevy carrying the set table, volume, records and
per-muscle analytics. That is the same split Rack uses — set detail in a
companion app, physiology in Garmin Connect — with the difference that Hevy is
an app the athlete already keeps their training in.

**Next, if the muscle map proves to matter more than the absence of a server:**
route C as an opt-in. The session already leaves the watch as a Hevy payload;
a backend subscribes to it, builds the FIT, and uploads. Nothing on the watch
changes, and an athlete who does not want it is unaffected.

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
