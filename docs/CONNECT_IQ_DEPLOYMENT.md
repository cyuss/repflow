# Publishing RepFlow on the Connect IQ Store

A step-by-step guide, from a clean checkout to a listing people can install.

## What it costs

**Nothing.** Publishing on the Connect IQ Store is free: there is no developer
programme fee, no annual renewal, and no charge per app or per update. What you
need is a Garmin account and acceptance of Garmin's Developer Agreement.

Apps may be listed as free or paid. RepFlow is free, which also means there is
no payment account to set up and no tax interview to complete.

The two things that *do* cost you if you get them wrong are both one-way:

- **The application UUID** in `manifest.xml` (`289C529B638645F0B9A7334DF736972B`).
  Change it after release and every existing install becomes an orphan.
- **The developer signing key** at `~/.garmin/repflow/developer_key.der`.
  Lose it and you cannot publish an update to your own app, ever. Back it up
  before you do anything else — see `docs/SIGNING.md`.

---

## Step 1 — Back up the signing key

Do this first, before the interesting parts, because it is the step that is
impossible to recover from later.

```sh
ls -l ~/.garmin/repflow/developer_key.der   # this file is your app's identity
```

Copy it somewhere durable and private: a password manager's file attachment, an
encrypted archive, a second machine. **Never** into this repository — every path
it could take is in `.gitignore`, and that is deliberate.

## Step 2 — Decide the version

Two places have to agree, and `scripts/package.sh` reads the first:

- `CHANGELOG.md` — the topmost `## [x.y.z]` heading
- `manifest.xml` — the `version` attribute on `<iq:application>`

For a first release, turn `## [Unreleased]` into `## [1.0.0] - YYYY-MM-DD`.

## Step 3 — Check the environment

```sh
make doctor
```

This confirms the SDK is resolvable, the signing key exists, and the device
definitions are installed. Every later step assumes it passed.

## Step 4 — Run everything

```sh
make test                  # unit tests, in the simulator
make build-all             # every product in manifest.xml compiles
make devices-missing       # must print nothing
```

`make devices-missing` matters more than it looks: the Store bundle builds
**every** declared product, so a device definition you have not installed will
silently shrink the bundle — or fail it.

## Step 5 — Test it on a watch

The simulator will not tell you whether the buttons work with chalked hands or
whether the activity really lands in Garmin Connect.

```sh
make sideload DEVICE=fenix6pro
```

Then work through `docs/SMOKE_TEST.md` on the watch. Steps 8, 12 and 14 —
skip an exercise, leave it pending, resume it with its sets intact — are the
product. If they fail, nothing else about the release matters.

Save a real workout at the end and confirm it appears in Garmin Connect on the
phone as a **Strength Training** activity, with a lap per set.

## Step 6 — Build the Store bundle

```sh
make package
```

This runs doctor, the tests and a release build for every device, then produces
the bundle with Garmin's own packaging command:

```sh
monkeyc -e -r -w -f monkey.jungle \
        -o build/release/RepFlow-<version>.iq \
        -y ~/.garmin/repflow/developer_key.der
```

`-e` (`--package-app`) is the supported CLI equivalent of VS Code's
**Monkey C: Export Project**. Both produce the same artifact. Never assemble an
`.iq` by hand.

You should end up with one file of a few megabytes containing one binary per
supported product.

## Step 7 — Take the screenshots

The Store wants the app's screen at the device's **native** resolution, not a
photograph of the simulator window with a bezel around it. Only the simulator
can produce that.

```sh
make sim DEVICE=fenix6pro
make store-shot            # opens the simulator's own export, once per screen
```

`make store-shot` puts `store-assets/screenshots/` on your clipboard and opens
the panel; press Cmd+Shift+G, Cmd+V, name the file, save. Repeat for each screen
worth showing. A good set for RepFlow is five or six:

1. The set screen, mid-workout — the load, the reps, the heart rate zone gauge
2. The workout overview, showing a deferred exercise — this is the product
3. The rest screen, with the recovery figure and what is next
4. The recap's time-in-zone chart
5. The recap's per-exercise list
6. The catalogue, mid-build

## Step 8 — Write the listing

`store-assets/` already holds the text. Check each one still describes what
ships:

| File | What it is |
|---|---|
| `short-description.txt` | ~100 characters, shown in search results |
| `full-description.txt` | Features, supported devices, and the honest limitations |
| `release-notes.txt` | What changed in *this* version |
| `support-url.txt` | Where people report problems — **currently a TODO** |
| `privacy-policy.md` | RepFlow sends nothing anywhere; say so plainly |
| `icon.png` | 512×512, generated from `icon.svg` by `make-icons.sh` |

`support-url.txt` has to be a real URL before you submit. A GitHub issues page
is enough.

**Be honest about the limitations in the description.** RepFlow records a
genuine strength activity with laps, developer fields, heart rate and calories,
but Connect IQ cannot write Garmin's native per-set FIT messages, so Garmin
Connect's built-in strength breakdown will not be populated the way it is for
Garmin's own Gym Activity. Saying that up front costs a few installs and saves
every one-star review that would otherwise say it for you.

## Step 9 — Submit

At <https://apps.garmin.com/developer/>. The portal's wording changes from time
to time; the sequence does not:

1. Sign in with a Garmin account and accept the Developer Agreement.
2. Start a new app submission (for an update, open the existing listing and
   upload a new version instead — never submit an update as a new app).
3. Upload the `.iq` from `build/release/`.
4. Wait for automated validation. It checks the signature, the manifest, the
   declared products and per-device memory, and reports failures immediately
   with a reason.
5. Fill in the listing: name, category (**Health & Fitness**), descriptions.
6. Upload the icon and the screenshots.
7. Check the device list Garmin derived from the bundle against what you expect.
8. Complete the declarations — permissions, privacy, export compliance.

   RepFlow declares five permissions, and each has a one-line answer ready:

   | Permission | Why |
   |---|---|
   | `Fit` | Record and save the workout as an activity |
   | `FitContributor` | Write sets, reps and load into the FIT file |
   | `UserProfile` | Read the athlete's own heart rate zones for the gauge |
   | `SensorHistory` | Body Battery before and after the session |
   | `Sensor` | Accelerometer, to count repetitions — off by default |

9. Submit for review.

## Step 10 — While it is in review

- The app is **not publicly visible** until Garmin approves it.
- You **can** install your own submitted app from your developer account and
  keep testing while review is pending.
- Review normally takes a few business days.
- A rejection comes with a reason. Fix it, re-export, re-upload — same UUID,
  same key.

---

## Updates, later

1. Keep the UUID. Keep the key.
2. Bump the version in `CHANGELOG.md` **and** `manifest.xml`.
3. Write the real changes into `CHANGELOG.md` and `release-notes.txt`.
4. `make test`, `make build-all`, simulator, and a physical smoke test.
5. `make package`.
6. Upload as a **new version of the existing listing**.

A new listing means a new app: your users keep the old one, your reviews do not
carry over, and there is no way to merge them afterwards.

## If something fails

| Symptom | Cause |
|---|---|
| Validation rejects the signature | Built with a different key than the one on file |
| Fewer devices than expected in the bundle | A device definition is not installed — `make devices-missing` |
| "Out of memory" on one product | That device is tighter than the rest; check in the simulator with *File → View Memory* |
| The app installs but will not open | Almost always an uncaught Monkey C runtime error. See `docs/API_LIMITATIONS.md` §9 |
