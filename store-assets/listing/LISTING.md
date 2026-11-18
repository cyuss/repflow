# Connect IQ Store listing — RepFlow 1.1.0

Field by field, in the order of the upload form. Everything here is ready to
paste; the images are rendered by `python3 store-assets/listing/render.py`.

## App file

`build/release/RepFlow-1.1.0.iq` (made by `just package`, no Hevy key inside).

## Title

    RepFlow

Optional longer form, if the field allows it and you want the keyword:

    RepFlow – Strength Training

## Description (4000 characters max)

- English: `store-assets/full-description.txt` (3,362 characters)
- French: `store-assets/full-description-fr.txt` (3,778 characters)

## What's new

`store-assets/release-notes.txt`

## Category / subcategory

Category: **Health & Fitness** (or the fitness category the form offers).
Subcategory: the one closest to **Strength training / Workouts**.

## Privacy — "Does your app collect user data?"

**No.** The developer receives nothing: no account, no analytics, no server.
Workouts stay on the watch. A saved workout goes to Garmin Connect (Garmin's
own sync) and, only if the user pastes their own Hevy key, to their own Hevy
account — straight from the watch, never to the developer.

Privacy policy URL, once the repository is public on GitHub:

    https://github.com/cyuss/repflow/blob/main/store-assets/privacy-policy.md

## Regional limits

None — available in every region. The app is in English and French.

## Cover (hero) image — 1440 x 720

`store-assets/listing/hero-1440x720.png`

## Icon

`store-assets/listing/icon-512.png` (512 x 512). The watch keeps its own
launcher icon; this one is only for the Store.

## Screen images

Premium, 1080 x 1080, in this order (`store-assets/listing/screens/`):

1. `01-set-screen.png` — Every set, at a glance
2. `02-overview.png` — Your workout. Your order.
3. `03-rest.png` — Rest that knows what's next
4. `04-recap-session.png` — The session, summed up
5. `05-recap-effort.png` — Effort, measured by Garmin
6. `06-recap-zones.png` — Time in every zone
7. `07-recap-week.png` — Volume by muscle, this week
8. `08-analytics-week.png` — Your training, analysed
9. `09-analytics-trend.png` — Consistency you can see

If the form wants the watch's own screen instead, the same nine at native
resolution (454 x 454, Fenix 9 Pro 47 mm) are in `store-assets/screenshots/`.

## Support / contact

    https://github.com/cyuss/repflow/issues

## Regenerating

    just sim-showcase set|rest|overview    the workout screens, staged
    just sim-recap                         the recap
    DEMO=1 just sim-analytics              Analytics with a demo year
    python3 store-assets/listing/render.py the cover, icon and screen images
