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

`store-assets/listing/hero-1440x720.jpg`

## Icon

`store-assets/listing/icon-512.png` (512 x 512). The watch keeps its own
launcher icon; this one is only for the Store.

## Screen images (the Store takes five)

1080 x 1080 JPEG, each under 150 KB, in this order (`store-assets/listing/screens/`). Each is one
chapter of a workout, so the five together walk through the whole app:

1. `1-your-order.jpg` — **Your workout. Your order.** The overview and the set
   screen: pick any exercise, put off a busy station, swap or add mid-session.
2. `2-under-the-bar.jpg` — **Built for under the bar.** The set screen and the
   rest screen: live HR zone, smart rest, RPE, last time's numbers, PR alerts.
3. `3-the-recap.jpg` — **A recap worth reading.** Effort, session and zones:
   training effect, Body Battery, HR zones, records.
4. `4-every-muscle.jpg` — **See what you're skipping.** This week's volume per
   muscle; 82 movements, Garmin Connect, Hevy sync.
5. `5-progress.jpg` — **Consistency you can see.** The week, sessions per week
   and the glance.

The first image is the one shown in search results: keep it first.

The native captures (454 x 454, Fenix 9 Pro 47 mm) the images are built from
are in `store-assets/screenshots/`; `10-glance.png` is the glance card.

## Support / contact

    https://github.com/cyuss/repflow/issues

## Regenerating

    just sim-showcase set|rest|overview    the workout screens, staged
    just sim-recap                         the recap
    DEMO=1 just sim-analytics              Analytics with a demo year
    python3 store-assets/listing/render.py the cover, icon and screen images
