# Release checklist

Copy this list into the release PR or issue and tick it off. `make package`
automates steps marked **(auto)** and refuses to continue if they fail.

## Pre-flight

- [ ] Working tree clean, everything committed **(auto: warns)**
- [ ] Version bumped in `CHANGELOG.md`
- [ ] Version bumped in `manifest.xml` (`<iq:application version="...">`)
- [ ] `CHANGELOG.md` `## [Unreleased]` section moved under the new version, with real entries
- [ ] `README.md` still accurate (features, supported devices, limitations)

## Environment

- [ ] `make doctor` all green **(auto)**
- [ ] Connect IQ SDK version recorded in `docs/ENVIRONMENT.md` matches what is installed
- [ ] `make devices-missing` prints nothing — every declared product can be built

## Quality

- [ ] `make test` — every unit test passes **(auto)**
- [ ] No test was weakened or deleted to get here
- [ ] `make build-all` — every supported device compiles with no warnings **(auto)**
- [ ] Memory headroom checked on the tightest device (simulator → *File → View Memory*)

## Functional

- [ ] `docs/SMOKE_TEST.md` passed **in the simulator**
- [ ] `docs/SMOKE_TEST.md` passed **on a physical Fenix**
- [ ] Result logged in the `docs/SMOKE_TEST.md` results table
- [ ] Steps 8, 12 and 14 specifically verified (skip → pending → resume with state intact)
- [ ] Whole flow completed with **touch disabled** — buttons alone
- [ ] Strength activity confirmed in Garmin Connect, with sane duration and HR

## Manifest & identity

- [ ] Application UUID unchanged: `289C529B638645F0B9A7334DF736972B` **(auto: reported)**
- [ ] Permissions still justified — `Fit`, `FitContributor`, `UserProfile`,
      `SensorHistory`, `Sensor`, and nothing else **(auto: reported)**
- [ ] Supported products list reviewed **(auto: reported)**
- [ ] `minApiLevel` still correct for the declared products

## Security

- [ ] `git ls-files | grep -Ei '\.(der|pem|key|p12|pfx)$'` prints nothing
- [ ] Signing key backed up somewhere durable and private (`docs/SIGNING.md`)
- [ ] No secrets, tokens or personal data in the repo or the store listing

## Package

- [ ] `make package` succeeds **(auto)**
- [ ] `build/release/RepFlow-<version>.iq` exists and is non-trivial in size
- [ ] Per-device PRG sizes look reasonable (no sudden jump)

## Store

- [ ] Icon present and correct in `store-assets/`
- [ ] Screenshots refreshed for this version
- [ ] Short and full descriptions reviewed
- [ ] Release notes written for the Store (not just the CHANGELOG)
- [ ] Support URL reachable
- [ ] Privacy statement accurate

## Submit

- [ ] `.iq` uploaded at <https://apps.garmin.com/developer/>
- [ ] Garmin binary validation passed
- [ ] Listing information completed
- [ ] Device list Garmin derived matches expectations
- [ ] Submitted for review

## After approval

- [ ] Git tag created: `git tag -a v<version> -m "RepFlow v<version>" && git push --tags`
- [ ] `## [Unreleased]` section restarted in `CHANGELOG.md`
- [ ] Store listing spot-checked live
