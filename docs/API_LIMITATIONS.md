# Garmin Connect IQ API limitations

Every limitation here was verified against the **installed Connect IQ SDK
9.2.0** API documentation and symbol table, not assumed. Where a limitation
exists, the workaround RepFlow actually implements is named.

---

## 1. RepFlow cannot write Garmin's native strength `set` FIT messages

**Verified:** `Toybox.ActivityRecording.Session` exposes exactly these methods:

```
addLap()          createField()   discard()   isRecording()
save()            setTimerEventListener()     start()   stop()
```

There is no API to emit a FIT `set` message (the message type Garmin's own
Gym Activity uses to record "set 3: 10 reps @ 55 kg"). `createField()` writes
**developer** fields, which are attached to `MESG_TYPE_RECORD`,
`MESG_TYPE_LAP` or `MESG_TYPE_SESSION` — not to native set messages.

**Consequence:** a RepFlow activity in Garmin Connect is a genuine strength
activity with correct duration, heart rate and calories, but Garmin Connect's
built-in per-set breakdown will not be populated the way it is for Garmin's
native Gym Activity app.

**What RepFlow does instead** (`source/GarminRecorder.mc`):

- Records with `Activity.SPORT_TRAINING` + `Activity.SUB_SPORT_STRENGTH_TRAINING`,
  both confirmed present in the SDK symbol table, so Garmin Connect classifies
  the activity as strength training.
- Calls `addLap()` after every completed set — the closest supported analogue
  of a set boundary, giving a per-set lap breakdown.
- Writes three developer FIT fields on the session message: `repflow_sets`,
  `repflow_reps`, `repflow_volume`.
- Writes four developer FIT fields on **every lap**: `exercise` (string),
  `set`, `reps` and `weight`. This is what turns Garmin Connect's lap table
  from "lap 7, 0:42" into "Bench Press, set 3, 8 reps at 70 kg". Developer
  fields are displayed by Garmin Connect and by the Connect phone app alongside
  Garmin's own metrics.
- Keeps the authoritative set-by-set detail in RepFlow's own storage.

### `:nativeNum` — available, deliberately unused

`Session.createField()` accepts a `:nativeNum` option, which maps a developer
field onto a **native** FIT field number so Garmin Connect treats it as its own
rather than as an add-on. That would be the closest thing to native per-set
data that Connect IQ offers.

It is not used, because the FIT profile that defines those field numbers **does
not ship with the Connect IQ SDK** — using it today would mean inventing a
number and hoping. Per the project's no-fake-API rule, it stays unused until
the number for a lap's repetition/weight field can be read out of Garmin's
published FIT profile and confirmed on a physical watch.

### What *is* fully compatible

A saved RepFlow activity is an ordinary FIT activity file. It syncs to Garmin
Connect over Bluetooth like any other, appears in the activity feed and in the
phone app, and contributes its duration, heart rate, calories and intensity
minutes to Garmin's weekly totals exactly as a native strength session does.
Training Effect, recovery time and training status contribution are computed by
the device firmware and are **not** exposed to Connect IQ (see §11), so those
specific figures are the ones a RepFlow activity will not carry.

---

## 2. `ActivityRecording.Session` has no pause/resume

**Verified:** there is no `pause()` or `resume()` method on `Session`.

**What RepFlow does:** `GarminRecorder.pause()` calls `stop()` and
`GarminRecorder.resume()` calls `start()` again on the same session object.
This stops and restarts the FIT timer without ending the recording, which is
the supported way to achieve a pause.

---

## 3. A recording cannot be reattached after the app is restarted

If RepFlow is killed mid-workout, the `Session` object is gone. Connect IQ
offers no API to reopen an in-progress recording.

**What RepFlow does:** RepFlow's own workout state *is* fully restored —
`SessionRepository` persists the session after every set, so no sets, reps or
weights are lost (`AppController.resumeWorkout`). A **new** Garmin recording is
started for the remainder of the workout, so an interrupted workout produces
two activities in Garmin Connect rather than one. This is documented rather
than hidden.

---

## 4. Garmin Connect workouts: names only, never contents

**Verified against SDK 9.2.0**, twice, because it is the most commonly asked-for
feature and the answer is unwelcome.

`Toybox.PersistedContent` lists what is installed on the watch:

```
getWorkouts()      getCourses()     getRoutes()    getTracks()    getWaypoints()
getAppWorkouts()   ... and the same, restricted to this app's own content
```

Each entry is a `PersistedContent.Workout`, and it exposes **exactly four
methods**:

```
getId()      a unique serializable id
getName()    a readable name
toIntent()   a system intent that launches it in Garmin's own player
remove()     delete it
```

There is **no API of any kind** for the contents: no exercises, no steps, no
sets, no repetitions, no loads, no rest. The workout an athlete built in Garmin
Connect is, to a Connect IQ app, a name and a handle.

`Activity.getCurrentWorkoutStep()` does report step detail — but only while
**Garmin's own workout player** is the thing running the activity. An app
cannot start that player and stay in control: `toIntent()` hands the watch over
to Garmin's activity, and RepFlow is no longer on screen.

**Consequence:** RepFlow cannot import, read, mirror or execute a workout
created in Garmin Connect. Listing the names would cost a `PersistedContent`
permission — which costs installs and invites review questions — to display a
list that could not be opened. So it is not done.

**What RepFlow does instead:** builds workouts on the watch. The catalogue is
82 movements across ten muscle groups, a workout is assembled in under a
minute, and it is stored on the watch permanently — see `source/WorkoutEditor.mc`
and `source/ExerciseCatalogue.mc`. Built once, it is there every session.

## 5. Storage is limited and per-value bounded

`Application.Storage` accepts a bounded `ValueType` and each device has a total
app-storage budget. Large or deeply nested structures fail at runtime.

**What RepFlow does:**

- Serialises with short keys (`"i"`, `"n"`, `"ts"`, …) and sets as flat arrays
  rather than dictionaries (`WorkoutSet.toStorage`).
- Stores only **one** active session.
- Keeps history as summary aggregates only, capped at
  `SessionRepository.MAX_HISTORY` (20) entries.
- Wraps every read and write; a storage failure never interrupts a workout,
  and a corrupt active session is dropped rather than crashing the app.

---

## 6. Vibration is not universal

`Toybox.Attention` is absent on some products, `vibrate` is absent on others,
and the user can disable vibration system-wide.

**What RepFlow does:** `AppController.vibrate()` checks `Attention has :vibrate`
and honours `DeviceSettings.vibrateOn` before calling. Haptics are always
optional; nothing in the workout flow depends on them.

---

## 7. Garmin metrics are only available while an activity is live

`Activity.getActivityInfo()` returns `null` outside an activity, and individual
fields (`calories`, `averageHeartRate`) are `null` when the device does not
provide them.

**What RepFlow does:** `WorkoutSummaryView` reads calories and average heart
rate defensively and simply omits those rows when unavailable, rather than
displaying zeros. RepFlow's own metrics (sets, reps, volume, duration) always
come from RepFlow's engine.

---

## 8. Device definitions require an authenticated Garmin account

Not an API limitation, but a hard build dependency: `monkeyc` cannot target any
device without locally installed device definitions, and Garmin ships them only
through the signed-in SDK Manager. See `docs/ENVIRONMENT.md`.

---

## 9. `catch` does not catch Monkey C runtime errors

**Verified by direct experiment** in the simulator (a throwaway unit test that
invoked a method on a null read out of a Dictionary, inside a `try/catch`):

```
DEBUG: about to invoke on null
Error: Unexpected Type Error          <- the catch block was never reached
```

Monkey C separates `Toybox.Lang.Exception`, which `try/catch` handles, from
runtime **errors** — *Unexpected Type*, *Symbol Not Found* — which it does not.
Those abort the application.

Wrapping a parser in `try/catch` therefore does **not** make it safe against
malformed input: calling a method on a value that turned out to be the wrong
type takes the whole app down. On a watch that matters more than on a desktop,
because the bad value can be in persistent storage — so the app would fail on
every launch, and the athlete has no way to clear it.

**What RepFlow does:** `source/SessionSnapshot.mc` validates the persisted
snapshot field by field, and checks a `SCHEMA_VERSION` marker, *before* anything
is parsed. `SessionRepository.loadActive()` discards anything unrecognised
instead of guessing at it. The try/catch is still there, but as the second line
of defence rather than the first. `tests/SessionSnapshotTest.mc` covers version
mismatches, missing fields, wrong types and nested damage.

The same applies anywhere else external data is parsed — treat storage, and any
future network payload, as untrusted.

## 10. There IS a supported CLI for the Store bundle

Worth recording because it is commonly believed otherwise: `monkeyc -e`
(`--package-app`) is the official command-line equivalent of VS Code's
**Monkey C: Export Project**, and it produces the `.iq` Store bundle.
`scripts/package.sh` uses it. It requires every product declared in
`manifest.xml` to have its device definition installed locally.

---

## 11. Firmware-computed training metrics are not exposed

**Verified:** the SDK exposes no API for Training Effect (aerobic or
anaerobic), recovery time, training status, training load, or VO2 max
contribution. `Toybox.UserProfile` reports the *stored profile* — heart rate
zones, age, weight — and `Toybox.ActivityMonitor` reports steps and intensity
minutes, but none of the coaching figures.

**Consequence:** a Connect IQ app cannot display them, and cannot make an
activity contribute to them beyond what the firmware infers from the FIT file
it records.

**What RepFlow does:** shows what it can actually measure — heart rate and its
zones, time in zone, calories, Body Battery before and after — and does not
show an invented Training Effect. A fabricated coaching number would be worse
than none, because the athlete cannot tell it apart from the watch's own until
they compare the two screens.
