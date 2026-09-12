# Hevy ↔ RepFlow ↔ Garmin Connect — feasibility

**Verdict up front: four of the five steps work exactly as described. The fifth
works, but not in the form you pictured.**

Everything below was verified against the **installed Connect IQ SDK 9.2.0** and
against **Hevy's own OpenAPI specification**, fetched from
`api.hevyapp.com/docs/`. Where something is unproven it says so, and where I got
it wrong earlier in this project it says that too.

---

## The workflow, step by step

| # | What you want | Verdict |
|---|---|---|
| 1 | Import Hevy routines onto the watch, see them as a workout list | **Works** |
| 2 | Start one, navigate freely with RepFlow | **Already built** |
| 3 | Finish and save → sync happens on its own | **Works**, inside one hard limit |
| 4 | On Hevy: the session as if logged on the phone | **Works, exactly** |
| 5 | On Garmin Connect: name, sets, reps, weights, exercise names | **Partly** — see below |

---

## 1. Importing the routines — works

**Hevy side, verified from the OpenAPI spec:**

```
GET /v1/routines
  header  api-key       string (uuid), required
  query   page          integer, must be 1 or greater
  query   pageSize      integer, default 5, MAX 10
```

The response carries everything RepFlow needs, per routine:

```
id, title, folder_id, updated_at, created_at
exercises[]
  index, title, rest_seconds, notes, exercise_template_id, superset_id
  sets[]
    index, type, weight_kg, reps, rep_range{start,end}
```

`exercise_template_id` is the thing that makes the rest of this work. It is
Hevy's own identifier for a movement, and carrying it through is what makes step
4 exact rather than a guess.

**Watch side, verified in the SDK:**

`Communications.makeWebRequest(url, params, options, callback)` takes
`:headers` (so the `api-key` header goes in directly) and `:responseType`, and
JSON responses are deserialised into a Monkey C `Dictionary` before the callback
sees them. It needs the `Communications` permission. It is asynchronous.

**Constraints, all real:**

- **`pageSize` caps at 10.** More than ten routines means more than one request.
- **The phone must be in Bluetooth range.** A Garmin watch has no network of its
  own; every request is proxied through Garmin Connect Mobile. This is stated
  plainly in the SDK's own HTTPS topic.
- **Memory is not the problem people assume.** A watch app gets **1,310,720
  bytes** on a Fenix 6 Pro. The 128 KB figure usually quoted for that watch is
  the *data field* limit. The import comfortably fits in the foreground.

---

## 2. Training — already built

Nothing new. The one change is that each exercise carries its Hevy
`exercise_template_id` alongside its RepFlow id, so the session can be posted
back without matching on names.

---

## 3. Automatic sync after saving — works, inside one hard limit

**Verified in the SDK:**

- `Background.registerForActivityCompletedEvent()` — *"Wakes your background
  service when the user completes an activity."* API level 3.1.0, and the
  **Fenix 6 is in its supported-device list**. This is exactly the hook.
- `System.ServiceDelegate.onActivityCompleted({:sport, :subSport})` is the
  callback.
- Garmin's own FAQ discusses `Communications.makeWebRequest()` **from a
  background process**, so web requests there are supported and expected.
- The background and the foreground are the same app and share
  `Application.Storage` — the SDK's own BackgroundTimer sample writes to Storage
  from the background to notify the foreground.

**The hard limit: a background service gets 32,768 bytes** on a Fenix 6 Pro
(65,536 on newer watches), and is killed if it has not exited within 30 seconds.
Garmin's FAQ warns specifically that a web response *and* the dictionary built
from it must both fit in that pool.

A workout POST body — seven exercises, four sets each — is on the order of two
kilobytes. That fits. But it means:

- The **import** must happen in the **foreground**, where there is room.
- The **export** can run in the background, and must keep its payload small and
  ignore most of the response.

**What must be designed for, not hoped about:** the phone is not always there.
The session has to be queued in Storage and retried — `registerForTemporalEvent`
allows a retry as often as every five minutes — and only cleared when Hevy has
actually answered. Without a queue, a workout finished away from the phone is a
workout lost.

Requires the `Background` and `Communications` permissions.

---

## 4. The session on Hevy — works, exactly

**Verified from the OpenAPI spec:**

```
POST /v1/workouts
{
  "workout": {
    "title":       string      required
    "description": string|null
    "start_time":  string      required   ISO 8601, e.g. 2024-08-14T12:00:00Z
    "end_time":    string      required
    "is_private":  boolean                defaults to false
    "exercises": [{
      "exercise_template_id": string      e.g. "D04AC939"
      "superset_id":          integer|null
      "notes":                string|null
      "sets": [{
        "type":             "warmup" | "normal" | "failure" | "dropset"
        "weight_kg":        number|null
        "reps":             integer|null
        "distance_meters":  integer|null
        "duration_seconds": integer|null
        "custom_metric":    number|null
        "rpe":              6 | 7 | 7.5 | 8 | 8.5 | 9 | 9.5 | 10
      }]
    }]
  }
}
```

Every field RepFlow records has somewhere to go. The mapping is **exact, not
approximate**: the `exercise_template_id` came from the routine, so Hevy files
the session against the same movement it would have if you had logged it on the
phone. Your history does not fork, and your per-exercise records stay whole.

RepFlow's own model already covers `type` (a set marked to-failure is in the
backlog at 2.9) and `rpe` (2.8). Neither is needed for this to work.

---

## 5. The session on Garmin Connect — partly, and here is the honest line

### What works

| Thing | How | Verified |
|---|---|---|
| **Activity named after the Hevy routine** | `ActivityRecording.createSession({:name => title})` | yes |
| Classified as strength training | `SPORT_TRAINING` + `SUB_SPORT_STRENGTH_TRAINING` | yes |
| One lap per set | `Session.addLap()` after each set | yes, shipped |
| **Exercise name, set number, reps and weight, per lap** | developer FIT fields at `MESG_TYPE_LAP`, declared with `displayInActivityLaps="true"` | yes — see the defect below |
| Session totals in the Activity Summary | developer fields at `MESG_TYPE_SESSION`, `displayInActivitySummary="true"` | yes |

### The defect this study found

**RepFlow was writing developer fields that Garmin Connect would never have
shown.** Displaying them requires a `<fitContributions>` block in resources,
declaring each `fitField` with a matching id and the `displayInActivityLaps` /
`displayInActivitySummary` flags. The SDK is blunt about it:

> *"Field id **must** match the fitField id in resources or your data will not
> display!"*

RepFlow shipped with no such block. The FIT files were correct; nothing was ever
asked to draw them. Fixed in `resources/fit_contributions.xml`.

### What does not work, and cannot

**Garmin Connect's native strength view — the one that lists sets with Garmin's
own exercise names — cannot be populated by any Connect IQ app.** That view is
built from FIT `set` messages, and `ActivityRecording.Session` exposes exactly:

```
addLap()   createField()   discard()   isRecording()
save()     setTimerEventListener()     start()   stop()
```

There is no way to emit a `set` message. So a RepFlow activity shows its set
detail in the **Connect IQ section** of Activity Details — a laps table with
your labels on it — not in Garmin's native strength breakdown.

`createField()` does accept a `:nativeNum` option, which maps a developer field
onto a native FIT field number. That is the closest thing to native data on
offer. **It is not used, and I will not use it until it can be verified**: the
FIT profile that defines those numbers does not ship with the Connect IQ SDK,
so using it today means inventing a number and hoping.

### One thing still unproven

The SDK states that record-level fields must be numeric and that other levels
may be strings. It does **not** state whether Garmin Connect *renders* a string
developer field in the laps table. The exercise name is a string.

If it turns out strings are not rendered there, the fallback is a numeric
exercise index per lap plus the names in the activity description — worse, but
it works. **This needs one real activity on a real watch to settle, and it
cannot be settled from documentation.**

---

## What I got wrong earlier in this project

Stated plainly, because this study exists because you stopped trusting the
earlier answers.

1. **"Connect IQ cannot read Garmin Connect workouts."** Correct, and verified
   three times. `PersistedContent.Workout` exposes `getId`, `getName`,
   `toIntent`, `remove` and nothing else.
2. **"`getCurrentWorkoutStep()` is useless here."** Wrong as stated. It exists,
   it is supported on the Fenix 6 Pro, and it returns step name, target and
   duration. It only ever describes the step *Garmin's own player is running*,
   which rules out a watch app but not a data field.
3. **"128 KB of app memory."** Wrong. That is the data field limit. A watch app
   gets 1,310,720 bytes on a Fenix 6 Pro — more than the Fenix 9 Pro's 786,432.
   Several code comments justified design decisions with this false figure; they
   have been corrected.
4. **Developer fields would show in Garmin Connect.** Wrong as shipped, because
   the `fitContributions` block was missing. Fixed.
5. **The MTP prompt proves the data lines work.** Wrong on its own — a watch can
   show it on power alone. The wall-charger test is what settles it.

---

## Confirmed against a working implementation

After this study was written, a shipping Garmin/Hevy app was found and read in
full: **[zweihochzehn/garmin-hevy-app](https://github.com/zweihochzehn/garmin-hevy-app)**
— a Connect IQ app for the Venu 2 that pulls Hevy routines, guides the sets, and
posts the workout back. It is not affiliated with this project. Reading it
independently confirmed every conclusion above, and taught four things this
study had missed.

**Confirmed:**

- `Communications` + `Fit` are the only permissions it needs. Live heart rate
  and calories come from `Toybox.Activity`, which the SDK's permission table
  does not list — `Sensor` covers `Toybox.Sensor` and is not required for HR.
- `pageSize` really does cap at 10; they page and cap at 50 routines.
- **Connect IQ cannot write structured strength sets into a FIT.** Their ADR
  calls it "confirmed as an unresolved Garmin forum request". They write **no
  developer fields at all** and accept that sets do not appear in the Garmin
  activity.
- A response that is too large is a real failure mode: they keep the history
  fetch to five workouts because "a big page would be a slow BLE transfer and
  can exceed the response size limit".

**Learned, and now fixed in RepFlow:**

1. **A running `ActivityRecording` blocks Garmin's sleep tracking.** Verified by
   them on a physical Venu 2: leaving the app mid-workout left the recording
   running and cost a night of sleep data. RepFlow only ever closed the
   recording in `finishWorkout`, so swiping out mid-session left it dangling.
   `AppController.onAppStop` now closes it on every exit — saved if any set was
   logged, discarded otherwise.
2. **Never round a load the athlete has not touched.** RepFlow snapped the
   inherited weight to the displayed unit's step grid, which on a statute watch
   is a kg→lb→kg round trip: a routine's 20.0 kg became 19.96 kg before a rep
   was performed. Rounding now happens only where the athlete chooses a value.
3. **"No target weight" is not zero.** Their app shows "–" and logs `null`;
   RepFlow stores 0.0 and would log a fabricated zero. Hevy's `weight_kg` is
   nullable, so this matters the moment anything is posted. **Not yet fixed** —
   it needs a nullable weight through the model and a schema bump, and is listed
   below.
4. **Practical details worth copying**: an API key typed on a watch has no
   hyphens, so strip non-alphanumerics and re-insert the 8-4-4-4-12 form;
   negative response codes are Connect IQ transport errors and positive ones are
   HTTP, so 401/403 means the key and anything ≤ 0 means the phone; persist the
   payload *before* the first send and clear it only on 200/201, matched by
   `start_time`; keep the pending store a queue, not a slot.

**Where they went further:** they fetch the athlete's recent workouts from Hevy
to pre-fill "what did I lift last time", rather than relying on the watch's own
history. That works from the first session on a new watch, where RepFlow's local
history is empty.

**Where RepFlow goes further:** they follow the routine's order. RepFlow's whole
reason to exist — selecting any exercise at any time, deferring an occupied
machine — is not something their flow does.

## How the others do it — Rack and LiftSync

Two shipping products were put forward as the target. Both are real, both work,
and neither is built the way RepFlow is. The difference is worth understanding
before copying anything.

### Rack — a watch companion to a phone app

Rack's Connect IQ app is a **companion**. Its store listing is explicit: create
the routine in the Rack iOS app, open Rack on the watch, "your watch syncs
automatically over Bluetooth", and "log sets from your phone **or** confirm them
on your watch".

The transport is not the Hevy-style cloud API. It is the Connect IQ phone
messaging channel — `Communications.transmit`,
`Communications.registerForPhoneAppMessages`, `PhoneAppMessage`, all present in
SDK 9.2.0 — paired with a phone app built on Garmin's Mobile SDK for iOS. That
is what LiftSync's own write-up calls "FIT-over-BLE", and what it correctly
identifies as the dividing line between apps that log on the watch and apps
that only sync a summary afterwards.

**What that buys them:** live two-way sync. Hot-swap an exercise on the phone
and the watch updates without restarting the activity.

**What it costs:** an iOS app. A second thing to install, a second thing to
keep, an App Store account, and a Swift codebase beside the Monkey C one.

**RepFlow reaches the same place without one, because Hevy already is the phone
app.** Routines come from Hevy's cloud API instead of from a companion over BLE,
and the finished session goes back the same way. Nothing extra to install, and
it works with the app the athlete already keeps their training in.

What RepFlow does not get, and does not want: logging a set on the phone and
watching the wrist update. The whole point here is not touching the phone.

### LiftSync — and the claim about `addSet()`

LiftSync's write-up says Garmin closed its `addSet()` cloud API to third
parties, so a cloud app like Hevy can no longer push a native strength activity
into Garmin Connect.

That is about a **different API from the one this document covers**: Garmin's
cloud-to-cloud partner API, not Connect IQ. It is consistent with everything
verified here, and it explains why Hevy's own Garmin integration can only ever
produce a summary. It does not change what a Connect IQ app on the watch can do.

### The claim worth being careful about

Rack's listing says its recording "counts toward Training Load, Training Effect,
and Training Readiness".

That is very likely true, and **it contradicts something this project asserted
earlier**. Those figures are computed by the firmware from a recorded activity's
heart rate and duration; a Connect IQ recording is a recorded activity, through
the same FIT pipeline with the same sport and sub-sport. The claim RepFlow made
— that its sessions do not contribute — was a negative asserted without
evidence. It has been withdrawn from the store description and from
`API_LIMITATIONS.md` §11.

What stays verified: a Connect IQ app cannot **read** or **set** those numbers.
Whether the watch derives them from what the app recorded is firmware behaviour,
and it needs one real session on a physical watch to settle.

### Settled: where Rack's muscle map actually lives

Rack's developer, quoted in an analysis of Garmin's strength-app ecosystem
([the5krunner, March 2026](https://the5krunner.com/2026/03/24/garmin-connect-plus-strength-apps/)):

> *"We bypassed the API entirely. The data never touches Garmin's cloud, so we
> never needed their permission."*

The same piece states that ConnectIQ *"has no mechanism to write Set messages
into a FIT file at all"* and that *"the critical function, `addSet()`, does not
exist"* — reached independently here by listing the three message types
`FitContributor` can target.

So the muscle diagram and the set table a Rack user sees are **in the Rack iOS
app**. Garmin Connect gets the recorded activity. That is the same split RepFlow
has, with Hevy in the place of Rack's own app — and Hevy is one the athlete
already uses.

Rack's "native Garmin activity with per-exercise breakdown" is the other half of
that listing, and it should be read carefully. The activity really is native —
any Connect IQ recording is. The per-exercise breakdown is what developer FIT
fields on laps produce, in Garmin Connect's Connect IQ section. Nothing in SDK
9.2.0 writes a FIT `set` message, and this was searched exhaustively: the entire
method list, every symbol containing "repetition", "set" or "exercise", and the
eight methods `ActivityRecording.Session` exposes. The only `repetitionNumber`
in the API belongs to workout *interval* steps and has nothing to do with
strength.

## What it would take to build

| Piece | Where | Size |
|---|---|---|
| API key setting (string property, edited on the phone) | `properties.xml`, `Settings` | small |
| `HevyClient` — GET routines, paginate, parse | new, foreground | medium |
| Routine → `Workout` mapping, keeping `exercise_template_id` | `Workout`, `Exercise`, schema v3 | medium |
| Session → POST body, queued in Storage | new | medium |
| `ServiceDelegate.onActivityCompleted` + temporal retry | new, `(:background)` | medium |
| `fitContributions` so Garmin Connect draws the laps | done | — |
| Nullable "no target weight" through the model | `Exercise`, schema v3 | medium |
| One permission: `Communications` (`Background` only if syncing without opening the app) | `manifest.xml` | small |

The one piece that cannot be designed from documentation is whether a string
lap field renders in Garmin Connect. Everything else is specified.
