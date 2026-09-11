# Connect IQ Store deployment

## Phase 1 — Pre-release

Work through `docs/RELEASE_CHECKLIST.md`. In summary:

```sh
git status                 # clean working tree
# bump the version in CHANGELOG.md and manifest.xml (see "Versioning" below)
make doctor                # environment OK
make test                  # all unit tests pass
make build-all             # every supported device compiles
make sim                   # simulator smoke test
make sideload              # physical Fenix smoke test
```

Then verify by hand:

- `manifest.xml` permissions — RepFlow declares only `Fit`. Extra permissions
  cost you users and invite review questions.
- `manifest.xml` products — `make devices-missing` must print nothing.
- **Application UUID unchanged** — `289C529B638645F0B9A7334DF736972B`.
- **Signing key backed up** — `docs/SIGNING.md`.
- Memory headroom on the tightest device (simulator: *File → View Memory*).
- Launcher icon and app name render correctly.
- `docs/SMOKE_TEST.md` passed on hardware, with the result logged.

## Phase 2 — Export the `.iq` bundle

The Connect IQ Store takes a single `.iq` file containing one binary per
supported device.

**From the CLI (what `make package` does):**

```sh
make package
```

`scripts/package.sh` runs doctor, the tests and a release build for every
device, then produces the bundle with Garmin's official packaging command:

```sh
monkeyc -e -r -w -f monkey.jungle -o build/release/RepFlow-<version>.iq \
        -y ~/.garmin/repflow/developer_key.der
```

`-e` / `--package-app` is the supported CLI equivalent of VS Code's export
wizard. It builds **every** product declared in `manifest.xml`, so all their
device definitions must be installed locally — `make devices-missing` must print
nothing or `package.sh` will skip this step and tell you.

**From VS Code (equivalent):**

Command Palette → **Monkey C: Export Project**

Both routes produce the same artifact. Never assemble an `.iq` by hand.

## Phase 3 — Store materials

`store-assets/` holds the listing material. Garmin requires:

| Asset | Requirement |
|---|---|
| Icon | Square PNG, at least 256×256 |
| Screenshots | Real device or simulator captures, at least one, per device family |
| Short description | ~100 characters |
| Full description | Features, supported devices, limitations |
| Release notes | This version's changes |
| Support URL | Where users report problems |
| Privacy policy | Required if you collect data — RepFlow does not, but a short "no data leaves your watch" statement is still worth publishing |

RepFlow's suggested description:

> RepFlow is a flexible strength-training app for Garmin watches.
>
> Change exercise order at any time, skip occupied machines, resume exercises
> later and track your sets, reps and weights without interrupting your workout.
>
> Your workout. Your order.

Capture screenshots from the simulator with **File → Save Screenshot**.

## Phase 4 — Submission

1. Sign in at <https://apps.garmin.com/developer/>
   (a Garmin account, plus acceptance of the Developer Agreement).
2. Choose **Submit an App** — or **Upload New Version** for an update.
3. Upload the `.iq` from `build/release/`.
4. Wait for Garmin's automated binary validation. It checks the signature, the
   manifest, the declared products and per-device memory. Failures are reported
   immediately with a reason.
5. Complete the listing: name, category (**Health & Fitness**), descriptions.
6. Upload the icon and screenshots.
7. Verify the supported device list Garmin derived from the bundle matches what
   you expect.
8. Complete the required declarations (permissions usage, privacy, export
   compliance).
9. **Submit for review.**

## Phase 5 — Review

After submission:

- The app is **not publicly visible** until Garmin approves it.
- You **can** install and test your own submitted app from your developer
  account while review is pending.
- Review typically takes a few business days.
- Rejections come with a reason. Fix it, re-export and re-upload — the same
  UUID and the same signing key.

## Phase 6 — Future updates

Every update must:

1. **Preserve the application UUID** in `manifest.xml`. Never regenerate it.
2. **Use the same signing key.** A different key means a different app.
3. Bump the version in `CHANGELOG.md` and `manifest.xml`.
4. Update `CHANGELOG.md` with real changes.
5. Pass the full test matrix: `make test`, `make build-all`, simulator and
   physical smoke tests.
6. Produce a fresh `.iq` with `make package`.
7. Upload as **Update New Version** on the existing listing — never as a new app.

## Versioning

RepFlow uses semantic versioning, recorded in two places that must agree:

- `CHANGELOG.md` — the topmost `## [x.y.z]` heading
- `manifest.xml` — the `version` attribute on `<iq:application>` (add it when
  you make the first store release; a missing attribute defaults to `1.0.0`)

`scripts/package.sh` reads the version from `CHANGELOG.md` and names the `.iq`
after it.
