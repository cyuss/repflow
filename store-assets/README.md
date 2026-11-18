# Store assets

Material for the Connect IQ Store listing. `scripts/package.sh` copies this
directory into `build/release/`.

Everything the Store form asks for, field by field: **`listing/LISTING.md`**.

| File | Purpose |
|---|---|
| `full-description.txt` / `full-description-fr.txt` | Listing body, EN / FR (under 4000 characters) |
| `short-description.txt` | One-line subtitle |
| `release-notes.txt` | "What's new" for this version |
| `privacy-policy.md` | Privacy statement (link it from the form) |
| `listing/hero-1440x720.png` | Cover image |
| `listing/icon-512.png` | Store icon |
| `listing/screens/` | Premium screen images, 1080x1080 |
| `screenshots/` | The same screens at native resolution (Fenix 9 Pro, 454x454) |
| `support-url.txt` | Where users report problems |

## Capturing screenshots

The screens are staged in the simulator on a Fenix 9 Pro 47 mm and captured at
the watch's native resolution, colour-corrected to sRGB, with the round screen
masked from the case:

    just sim-showcase set        # a Push Day under way (also: rest, overview)
    just sim-recap               # the recap, every page filled
    DEMO=1 just sim-analytics    # Analytics with a demo year

Then `python3 listing/render.py` builds the cover, the icon and the premium
screen images from `screenshots/`. See `listing/LISTING.md` for the regeneration
steps.
