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
- Keeps the authoritative set-by-set detail in RepFlow's own storage.

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

## 4. Garmin Connect workouts cannot be introspected or reordered

There is no public Connect IQ API to read the athlete's Garmin Connect workout
library, nor to reorder a downloaded structured workout. The
`Toybox.Application` and `Toybox.PersistedContent` modules expose no workout
type.

**Consequence:** RepFlow cannot import your existing Garmin Connect workouts in
V0.1. This is *why* RepFlow owns its own workout engine rather than driving
Garmin's — and it is exactly the flexibility Garmin's structured workouts do
not offer.

**What RepFlow does:** ships a built-in workout catalogue
(`source/WorkoutRepository.mc`). Editable and synced workouts are roadmap items
(V0.2 / V0.4), not fake ones.

---

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

## 9. There IS a supported CLI for the Store bundle

Worth recording because it is commonly believed otherwise: `monkeyc -e`
(`--package-app`) is the official command-line equivalent of VS Code's
**Monkey C: Export Project**, and it produces the `.iq` Store bundle.
`scripts/package.sh` uses it. It requires every product declared in
`manifest.xml` to have its device definition installed locally.
