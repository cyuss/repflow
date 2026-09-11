# RepFlow — Product

> **Your workout. Your order.**

## The problem

Structured workouts — Garmin's included — assume you will perform exercises in
the order they were written. A real gym does not work that way:

- the machine you need is occupied;
- you want to alternate two exercises as a superset;
- you want to skip something and come back to it;
- you want to change the weight or reps mid-workout.

Every existing option forces a compromise: follow the prescribed order, or
abandon structure entirely and track nothing.

## The principle

**Select any exercise at any time.**

RepFlow never forces a linear index. The workout engine navigates by stable
exercise id, and moving between exercises never destroys set state. That single
rule is what the whole app is built around, and it is enforced by the test suite
(`tests/WorkoutEngineTest.mc`).

## Who it is for

Someone who lifts in a normal, busy gym, wears a Garmin watch, and wants their
sets, reps and weights tracked *and* a real strength activity in Garmin
Connect — without pretending the gym is empty.

## What RepFlow owns vs what Garmin owns

| RepFlow owns | Garmin owns |
|---|---|
| Exercises, workout structure | Activity recording (FIT) |
| Sets, reps, weights | Heart rate and sensors |
| Rest timers | Activity duration |
| Exercise state & navigation | Calories |
| Completion / pending logic | Garmin Connect sync |
| RepFlow workout history | |

This split is deliberate. RepFlow never reimplements what the watch already
does well, and never pretends to do something the Connect IQ API does not
support — see `docs/API_LIMITATIONS.md`.

## Exercise states

| State | Meaning | How you get there |
|---|---|---|
| `NOT_STARTED` | untouched | initial state |
| `ACTIVE` | currently selected | select it |
| `PENDING` | started or deferred — **resumable** | "skip for now", or navigate away mid-exercise |
| `COMPLETED` | all target sets done | perform the sets, or explicitly "mark done" |
| `SKIPPED` | abandoned for this session | explicit skip |

`PENDING` is the state that makes RepFlow what it is. A pending exercise keeps
every set already performed, stays visible in the overview, and resumes exactly
where it was left.

## Core flows

**Complete a set** — one press of START. The next set inherits the weight and
reps you actually just performed, not the template's.

**Machine busy** — MENU → *Skip for now*. The exercise becomes `PENDING`, the
overview opens, pick something else.

**Come back** — open the overview (BACK, one press), select the pending
exercise. It resumes on the correct set with the correct weight.

**Superset** — complete a set of A, press BACK during rest, pick B, complete a
set, go back to A. Both stay `PENDING` between turns and neither loses state.

**Finish** — RepFlow refuses to quietly call the workout done while anything is
unfinished or pending; ending then requires an explicit confirmation.

## Non-goals for V0.1

No backend, no companion app, no accounts, no cloud sync, no Hevy import, no
Garmin Training API, no AI coaching, no payments. The watch app has to be good
first. See the roadmap in `README.md`.
