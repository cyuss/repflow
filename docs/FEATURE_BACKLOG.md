# RepFlow — feature backlog

What would make this the strength app a Garmin owner keeps on the watch.

Everything below is checked against **Connect IQ SDK 9.2.0**, installed. Where a
row says *not possible*, that is a verified platform limit and not an opinion —
see `docs/API_LIMITATIONS.md`. Where it says *verify*, the symbol exists but the
behaviour has not been proven by experiment yet.

Legend — **State**: shipped / next / later / not possible.
**Effort**: S (a day), M (a few days), L (a week or more).

---

## The workflow, and where it actually hurts

A set is forty seconds of work and ninety seconds of waiting, repeated twenty
times, by someone whose hands are chalked, whose forearms are pumped, and who is
counting. Every interaction has to survive that. Studying the loop:

| Moment | What the athlete is doing | The friction |
|---|---|---|
| Arriving | Picking the session | Workouts have to exist, and editing them on a phone first is a chore |
| Walking to the rack | Choosing what to do now | **The machine is taken.** This is the one that ruins a plan — and RepFlow's reason to exist |
| Loading | Converting 82.5 kg into plates | Mental arithmetic, mid-warm-up, every single set |
| The set | Lifting, counting | Hands are busy. Nothing can need two presses or precision |
| Racking it | Logging what actually happened | Reps rarely match the plan. Editing must come *before* the rest screen steals focus |
| Resting | Waiting, recovering | Wants: how long left, what is next, is my heart rate coming down |
| Next set | Deciding the load | **What did I do last time?** The single most consulted number in any lifting app |
| Finishing | Judging the session | Was that a good workout? Garmin answers this with charts; a strength app should too |

Three of those eight are already RepFlow's core — the taken machine, one-press
logging, and editing before the rest. The other five are what this list is for.

---

## 1 — Before the first set

| # | Feature | Why it matters in the gym | Feasibility (SDK 9.2.0) | Effort | State |
|---|---|---|---|---|---|
| 1.1 | **Empty workout** — start with nothing, add exercises as you go | The most-used entry point in Hevy and Strong. Plans survive contact with a busy gym about as well as any plan | `Application.Storage`, already in use | M | next |
| 1.2 | **Exercise catalogue** (~80 movements, grouped by muscle) | You cannot add an unplanned exercise without one | Resources + Storage | M | next |
| 1.3 | **Workout editor on the watch** — add, remove, reorder, set targets | Needing a phone to change a plan is the thing that makes watch apps get deleted | `Application.Storage`, `Menu2`, `Picker` | L | next |
| 1.4 | **Repeat last session** | Most training is a repeat with a little more weight | Needs history (§5) | S | later |
| 1.5 | **Settings from the Garmin Connect phone app** — default rest, weight step, units, haptics | Configuring on a 260 px screen is punishment; Garmin already gives a settings pane | `Application.Properties` + `settings.xml` — **verified present** | S | next |
| 1.6 | **kg / lb from the watch's own setting** | A US athlete should never see kilos | `System.getDeviceSettings().weightUnits` — **verified present** | S | next |
| 1.7 | **Warm-up ramp generator** (40 / 60 / 80 % × n) | Everyone does it; nobody wants to log it by hand | Pure arithmetic | S | later |
| 1.8 | **Import from Garmin Connect workouts** | Obvious ask, and the answer is unkind | `PersistedContent.getWorkouts()` returns **names only** — `getId`, `getName`, `toIntent`, `remove`. There is no API for the exercises, sets, reps or weights inside | — | **not possible** |

## 2 — The set (the hot path)

| # | Feature | Why it matters in the gym | Feasibility | Effort | State |
|---|---|---|---|---|---|
| 2.1 | One press of START logs the set | Chalked hands, pumped forearms | — | — | **shipped** |
| 2.2 | Weight and reps inherited from the last performed set | You almost always repeat the load | — | — | **shipped** |
| 2.3 | Edit weight and reps *before* the rest timer takes the screen | Reps rarely match the plan | — | — | **shipped** |
| 2.4 | **Plate calculator** — "82.5 kg = bar + 20 + 10 + 1.25 a side" | Removes arithmetic from every single working set. Cheap to build, used twenty times a session | Pure arithmetic; needs a bar-weight and available-plates setting | S | **next — best value per hour of work in this list** |
| 2.5 | **Coarse steps on a long press** (×5 the normal step) | Going 60 → 100 kg one kilo at a time is forty presses | `BehaviorDelegate.onKeyPressed` / hold | S | next |
| 2.6 | **Add an extra set in place**, beyond the target | Good days happen | Engine already models sets as a list | S | next |
| 2.7 | **Edit a set already logged** | Mis-tap at rep eight of ten | Engine change + a picker | M | later |
| 2.8 | **RPE / RIR after a set**, one optional press | How hard it felt is the input for next week's load | `Picker`, FIT developer field | S | later |
| 2.9 | **Mark to-failure / drop set / rest-pause** | Changes what the number means | Model + FIT field | S | later |
| 2.10 | **Supersets and circuits** — A1 ↔ A2 alternating automatically | Halves the time cost of accessory work | Engine grouping; navigation already id-based, so no cursor to fight | M | later |
| 2.11 | **Per-set targets** (pyramid: 12 / 10 / 8) | A single target rep count is a simplification most programmes do not make | Model change | M | later |
| 2.12 | **Automatic rep counting from the accelerometer** | Garmin's native strength activity does it, so athletes will expect it | `Sensor.registerSensorDataListener` with accelerometer data — **verified present**. But Garmin's own rep counter is **not exposed**; this would be a signal-processing project of our own, accurate for some movements and not others | L | later — build it honestly or not at all |
| 2.13 | Undo the last set | — | — | — | **shipped** |

## 3 — Rest

| # | Feature | Why it matters in the gym | Feasibility | Effort | State |
|---|---|---|---|---|---|
| 3.1 | Rest starts by itself when a set is logged | — | — | — | **shipped** |
| 3.2 | Per-exercise rest duration, adjustable ±15 s | Squats are not curls | — | — | **shipped** |
| 3.3 | **Vibration at 10 s to go, not only at zero** | Ten seconds is enough to get back under the bar | `Attention.vibrate` — **verified present** | S | next |
| 3.4 | **Backlight flash when rest ends** | A gym is loud and a wrist is not always in view | `Attention.backlight` — **verified present** | S | next |
| 3.5 | **Rest screen shows the next set's target** | Removes the "wait, what weight?" moment | View change | S | next |
| 3.6 | **Heart rate recovery** — bpm dropped in the first 60 s of rest | A genuine fitness signal, from samples RepFlow already takes for the zone chart. Nothing else in this category shows it | `ZoneTracker` already samples at 1 Hz | M | next — the premium differentiator |
| 3.7 | Skip rest when heart rate falls below a threshold | Auto-pacing for conditioning work | Sampling already in place | M | later |

## 4 — The gym floor

| # | Feature | Why it matters | Feasibility | Effort | State |
|---|---|---|---|---|---|
| 4.1 | **Select any exercise at any time** | The product | — | — | **shipped** |
| 4.2 | Defer an occupied machine and resume it with state intact | The product | — | — | **shipped** |
| 4.3 | Suggest the next sensible exercise | Saves a trip through the overview after every exercise | — | — | **shipped** |
| 4.4 | **Reorder exercises mid-workout** | Deferring is reactive; reordering is deciding | Engine is id-based, so this is a list move | M | next |
| 4.5 | **Substitute an exercise** — machine taken, pick the alternative | Deferring twice means it is time to do something else | Needs the catalogue (1.2) | M | next |
| 4.6 | **Add an unplanned exercise mid-workout** | Half of all sessions | Needs the catalogue (1.2) | M | next |

## 5 — Memory and progression

| # | Feature | Why it matters | Feasibility | Effort | State |
|---|---|---|---|---|---|
| 5.1 | **Last time's numbers on the set screen** — "last: 55 × 10, 10, 8" | The most consulted number in any lifting app, and RepFlow currently cannot answer it. Everything in this section depends on it | `SessionRepository.appendHistory` already writes sessions; needs a read path and an index by exercise id | M | **next — highest value in this list** |
| 5.2 | **Personal record detection** — heaviest set, best estimated 1RM, best volume | The reason people keep logging | Derived from 5.1 | M | next |
| 5.3 | **A distinct haptic and a badge when a record falls** | The one moment worth interrupting a workout for | `Attention.vibrate` | S | next |
| 5.4 | **Estimated 1RM** (Epley) per exercise, and its trend | Compares sessions that used different rep ranges | Arithmetic on 5.1 | S | later |
| 5.5 | **Per-exercise history on the watch** — the last five sessions | Answers "am I actually progressing" without a phone | `Menu2` over stored history | M | later |
| 5.6 | **Weekly volume per muscle group** | Catches the classic imbalance: six pushing exercises, one pulling | Needs muscle tags in the catalogue | M | later |
| 5.7 | **History pruning with a size cap** | `Application.Storage` is finite and a silent write failure is the worst kind | Storage bookkeeping | S | next, alongside 5.1 |

## 6 — Feeling like a Garmin

| # | Feature | Why it matters | Feasibility | Effort | State |
|---|---|---|---|---|---|
| 6.1 | Strength activity recorded, one lap per set, developer FIT fields | Lands in Garmin Connect like any other activity | — | — | **shipped** |
| 6.2 | Live heart rate with a five-segment zone gauge | The number worth a glance mid-set | `UserProfile.getHeartRateZones` | — | **shipped** |
| 6.3 | Time-in-zone bar chart at the end | The screen a Fenix shows after every activity | Counted at 1 Hz by `ZoneTracker` | — | **shipped** |
| 6.4 | Garmin-style stop menu: keep training / save / discard | Muscle memory from every native activity | — | — | **shipped** |
| 6.5 | **Glance view** — the workout in progress, or the last session, in the glance carousel | Garmin owners swipe the carousel constantly. An app that is absent from it feels bolted on | `AppBase.getGlanceView` — **verified present** | M | next |
| 6.6 | **Body Battery before and after the session** | Deeply Garmin, and a genuinely interesting number for a lifter | `SensorHistory.getBodyBatteryHistory` — **verified present** | S | next |
| 6.7 | Stress before and after | Same idea, weaker signal for strength work | `SensorHistory.getStressHistory` — **verified present** | S | later |
| 6.8 | **Publish a complication** so a watch face can show the last or next workout | Puts RepFlow on the watch face without a widget | `Toybox.Complications` exists; publishing from a watch app needs proving | M | verify |
| 6.9 | Native per-set FIT `set` messages | Would make Garmin Connect show sets natively | Connect IQ **cannot write FIT `set` messages**. RepFlow marks one lap per set and writes developer fields instead | — | **not possible** |
| 6.10 | Training Effect, recovery time, training status contribution | Would make the session count towards Garmin's own coaching | Computed by the device firmware; **not exposed** to Connect IQ | — | **not possible** |
| 6.11 | Reattach the recording after an app restart | Would make a crash mid-workout harmless | `ActivityRecording` **cannot be reattached**; a new recording is started for the remainder | — | **not possible** |
| 6.12 | Pause and resume the recording | — | `ActivityRecording.Session` has **no pause/resume** — only `stop()` / `start()` | — | **not possible** |

## 7 — Ergonomics and polish

| # | Feature | Why it matters | Feasibility | Effort | State |
|---|---|---|---|---|---|
| 7.1 | Button-first everywhere; touch optional | Sweat and gloves defeat touchscreens | — | — | **shipped** |
| 7.2 | Layout that respects a round screen and picks fonts that fit | 240 × 240 through 466 × 466 from one code path | — | — | **shipped** |
| 7.3 | Meaning in shape, not only colour — tick, play, pause, cross | Readable at arm's length, and to the colour-blind | — | — | **shipped** |
| 7.4 | **A haptic vocabulary**: set logged, rest over, record broken — three different patterns | You should know what happened without looking | `Attention.vibrate` takes a pattern | S | next |
| 7.5 | **Respect the device's font scale setting** | Accessibility, and Garmin owners do change it | `System.getDeviceSettings()` | S | later |
| 7.6 | **More languages** — currently English and French | The Store is global | Resource folders | S | later |
| 7.7 | Keep the screen lit through a set | Glancing down should not need a wrist flick | Behaviour under `ActivityRecording` needs proving | S | verify |

## 8 — Data safety

| # | Feature | Why it matters | Feasibility | Effort | State |
|---|---|---|---|---|---|
| 8.1 | Persisted session validated field by field before parsing | Monkey C runtime errors **cannot be caught**; a bad byte in storage would otherwise abort the app | `SessionSnapshot`, `SCHEMA_VERSION` | — | **shipped** |
| 8.2 | Resume an interrupted workout with state intact | A phone call should not cost you a session | — | — | **shipped** |
| 8.3 | **Schema migration, not just rejection** | Today an unknown version is discarded. Once people have history, that is data loss | Versioned readers | M | next, before the first update ships |
| 8.4 | **Export history off the watch** | Nobody wants their training locked in one app | `Communications.makeWebRequest` — needs somewhere to send it | L | later |

---

## If I could build only ten things next

In order. Each one earns its place by how often it is touched per session.

| Rank | Feature | Why this one |
|---|---|---|
| 1 | Last time's numbers (5.1) | Consulted before literally every working set. Unlocks 5.2–5.6 |
| 2 | Plate calculator (2.4) | A day's work; used twenty times a session, forever |
| 3 | Empty workout + add exercise mid-session (1.1, 1.2, 4.6) | Turns a fixed plan into a tool that survives a busy gym |
| 4 | Settings from the phone, and kg/lb (1.5, 1.6) | Cheap, and the difference between "usable" and "not for me" for half the world |
| 5 | Rest warning at 10 s + backlight (3.3, 3.4) | Two small things that remove the need to watch the watch |
| 6 | Personal records with their own haptic (5.2, 5.3) | The reason logging becomes a habit |
| 7 | Watch-side workout editor (1.3) | Removes the phone from the loop entirely |
| 8 | Glance view (6.5) | The difference between an app on the watch and an app *of* the watch |
| 9 | Heart rate recovery (3.6) | Nothing else in this category shows it, and the samples are already being taken |
| 10 | Reorder and substitute (4.4, 4.5) | Makes deferring a strategy rather than a workaround |

## What I would deliberately not build

- **Anything that fakes a Garmin metric.** Training Effect, recovery time and
  training status are computed by the firmware and not exposed. Showing an
  invented one would be worse than showing nothing.
- **A cloud account.** The watch, the FIT file and Garmin Connect are the whole
  chain. Adding a server adds a login, a privacy policy and an outage.
- **Automatic rep counting, until it is honestly good.** A counter that is right
  eight times out of ten is worse than no counter, because you have to check it
  every set — and checking it costs more than counting did.
