# Physical device testing

The simulator will not tell you whether the buttons feel right with sweaty
hands, whether the text is readable at arm's length, or whether the activity
actually lands in Garmin Connect. Test on the watch before every release.

## Prerequisites

- The device definition installed (`make devices` lists what is available).
- A developer signing key (`make key`).
- Developer sideloading is allowed on Garmin watches with no special unlock —
  the PRG simply has to be signed.

## 1. Connect the watch by USB

Plug the watch in with its data cable (a charge-only cable will not work).

- **macOS / Windows:** most Fenix models mount as a USB mass-storage volume.
  You should see a `GARMIN` folder at its root.
- **Fenix 8 / newer models in MTP mode:** these do not mount as a plain disk on
  macOS. Install [Android File Transfer](https://www.android.com/filetransfer/)
  or use a Windows machine, where MTP is supported natively by Explorer.
  `scripts/sideload.sh` will not find an MTP device and will print the manual
  copy instructions instead.

## 2. Build a signed PRG

```sh
make sideload DEVICE=fenix6pro
```

This runs a **release** build (`monkeyc -r`, debug symbols stripped), which is
what you want when testing what users will get.

To build without copying anything:

```sh
RELEASE=1 scripts/build.sh fenix6pro
# -> build/RepFlow-fenix6pro.prg
```

## 3. Sideload

`scripts/sideload.sh` looks for a mounted volume containing `GARMIN/APPS`,
asks for confirmation, and copies the PRG to:

```
<WATCH>/GARMIN/APPS/RepFlow.prg
```

The script **only ever writes that one file**. It never deletes anything on the
watch.

If no watch is found, copy it by hand — same destination. The file name does
not matter to the watch, but keeping it `RepFlow.prg` means the next sideload
replaces the old build rather than installing a second copy.

## 4. Disconnect safely

Eject the volume properly (Finder eject / Windows "Safely Remove Hardware")
before unplugging. Pulling the cable during a write can corrupt the watch's
filesystem.

The watch re-scans its app list on disconnect. This takes a few seconds.

## 5. Launch RepFlow

On a Fenix: **START → Activities & Apps →** scroll to **RepFlow**.

If RepFlow does not appear:
- confirm the PRG is in `GARMIN/APPS/`;
- confirm you built for the *right device id* — a PRG built for another product
  is silently ignored;
- restart the watch.

## 6. Run the smoke test

Work through **`docs/SMOKE_TEST.md`** in full. On the watch, pay particular
attention to:

- **Readability** — can you read the weight mid-set, at arm's length, without
  squinting?
- **One-press set completion** — does START complete a set every time, first
  try, without a mis-hit?
- **Haptics** — does the rest timer vibrate once at zero, and is it noticeable
  in a noisy gym?
- **Gloves** — buttons must do everything. Touch is a bonus.
- **Battery and thermals** — a 60–90 minute session should not warm the watch or
  drain it noticeably.

## 7. Verify in Garmin Connect

1. Sync the watch (Garmin Connect Mobile, or Garmin Express by USB).
2. The activity must appear as **Strength Training**.
3. Check duration, average heart rate and calories look right.
4. Check the lap breakdown — RepFlow marks one lap per completed set.

What you will **not** see is Garmin's native per-set reps/weight breakdown.
That is a Connect IQ API limitation, not a RepFlow bug —
see `docs/API_LIMITATIONS.md` §1.

## Troubleshooting

| Symptom | Cause |
|---|---|
| App missing from the list | Wrong device id, or PRG not in `GARMIN/APPS/` |
| "Requires update" on launch | Built against a newer `minApiLevel` than the watch firmware |
| Immediate crash on launch | Out of memory — check `File → View Memory` in the simulator for that device |
| No activity in Garmin Connect | Activity discarded on the summary screen, or the `Fit` permission is missing from `manifest.xml` |
| Watch not found by sideload.sh | MTP mode (Fenix 8+) — copy by hand |

## Device test matrix

Record results in `docs/DEVICE_MATRIX.md`.
