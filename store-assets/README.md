# Store assets

Material for the Connect IQ Store listing. `scripts/package.sh` copies this
directory into `build/release/`.

| File | Purpose | Status |
|---|---|---|
| `short-description.txt` | ~100 char store subtitle | ready |
| `full-description.txt` | Full listing body | ready |
| `release-notes.txt` | Per-version notes | update each release |
| `icon.png` | Square PNG, 256x256 minimum | **TODO** |
| `screenshots/` | Device or simulator captures | **TODO** |
| `support-url.txt` | Where users report problems | **TODO** |
| `privacy-policy.md` | Data handling statement | draft present |

## Capturing screenshots

Run RepFlow in the simulator (`make sim`) and use **File -> Save Screenshot**
for each screen:

1. `01-workouts.png`   workout picker
2. `02-exercise.png`   exercise screen mid-set
3. `03-rest.png`       rest timer with "next up"
4. `04-overview.png`   overview showing mixed states (done / pending / active)
5. `05-summary.png`    end-of-workout summary

Screenshot 4 is the one that sells the app: capture it with at least one
completed, one pending and one untouched exercise visible.

## Icon

Derive it from `resources/drawables/launcher_icon.svg` (a dumbbell on black
with the RepFlow blue #00A8E8 bar) and export at 256x256 or larger.
