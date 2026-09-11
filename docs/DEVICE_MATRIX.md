# Device matrix

## Targets

| Tier | Device | Product id | Notes |
|---|---|---|---|
| **Primary** | **Fenix 9 Pro 47 mm** | `fenix9pro47mm` | 454x454 AMOLED |
| **Primary** | **Fenix 9 Pro 51 mm** | `fenix9pro51mm` | 466x466 AMOLED — largest screen |
| Primary | Fenix 9 Pro 43 mm | `fenix9pro43mm` | 416x416 AMOLED |
| Primary | Fenix 9 Pro Solar 47/51 mm | `fenix9prosolar47mm`, `fenix9prosolar51mm` | MIP, 260x260 / 280x280 |
| Primary | Fenix 9 43/47 mm | `fenix943mm`, `fenix947mm` | |
| Primary | Fenix 8 family | `fenix8pro47mm`, `fenix847mm`, `fenix843mm`, `fenix8solar47mm`, `fenix8solar51mm` | |
| **Secondary** | **Fenix 6 Pro 47 mm** | `fenix6pro` | Developer's own watch; 240x240, no touch |
| Secondary | Fenix 6X Pro / 6S Pro / 6 / 6S | `fenix6xpro`, `fenix6spro`, `fenix6`, `fenix6s` | |
| Additional | Fenix 7 family | `fenix7`, `fenix7pro`, `fenix7pronowifi`, `fenix7s`, `fenix7spro`, `fenix7x`, `fenix7xpro`, `fenix7xpronowifi` | |
| Additional | epix 2 family | `epix2`, `epix2pro42mm`, `epix2pro47mm`, `epix2pro51mm` | |
| Additional | Venu / vivoactive | `venu3`, `venu3s`, `vivoactive5`, `vivoactive6` | Touch-first; buttons still drive everything |

> Product ids were taken from the **installed device definitions**
> (`scripts/devices.sh --all`), never invented.
>
> Note that the SDK's bundled `resources/device-reference/` artwork folder lags
> the real device list and does **not** contain the Fenix 9 family. Always trust
> the downloaded device definitions, which `scripts/devices.sh --all` reads.

## Generating the capability table

Screen size, memory budget, buttons, touch support and API level are read
directly from Garmin's own `compiler.json` / `simulator.json` for each installed
device:

```sh
scripts/device-matrix.sh
scripts/device-matrix.sh > docs/DEVICE_MATRIX_GENERATED.md
```

This requires device definitions to be installed — see `docs/ENVIRONMENT.md`.

<!-- BEGIN GENERATED MATRIX -->

| Device | Name | Resolution | Shape | Display | App memory | Buttons | Touch | API level |
|---|---|---|---|---|---|---|---|---|
| `fenix9pro47mm` | fēnix® 9 Pro 47mm | 454x454 | round | amoled | 768 KB | enter, up, menu, down, esc | yes | 6.0 |
| `fenix9pro51mm` | fēnix® 9 Pro 51mm | 466x466 | round | amoled | 768 KB | enter, up, menu, down, esc | yes | 6.0 |
| `fenix9pro43mm` | fēnix® 9 Pro 43mm | 416x416 | round | amoled | 768 KB | enter, up, menu, down, esc | yes | 6.0 |
| `fenix9prosolar47mm` | fēnix® 9 Pro Solar 47mm | 260x260 | round | mip | 768 KB | enter, up, menu, down, esc | yes | 6.0 |
| `fenix9prosolar51mm` | fēnix® 9 Pro Solar 51mm | 280x280 | round | mip | 768 KB | enter, up, menu, down, esc | yes | 6.0 |
| `fenix947mm` | fēnix® 9 47mm / 51mm | 454x454 | round | amoled | 768 KB | enter, up, menu, down, esc | yes | 6.0 |
| `fenix943mm` | fēnix® 9 43mm | 416x416 | round | amoled | 768 KB | enter, up, menu, down, esc | yes | 6.0 |
| `fenix8pro47mm` | fēnix® 8 Pro 47mm / 51mm / MicroLED / quatix® 8 Pro 47mm / 51mm | 454x454 | round | amoled | 768 KB | enter, up, menu, down, esc | yes | 6.0 |
| `fenix847mm` | fēnix® 8 47mm / 51mm / tactix® 8 47mm / 51mm / quatix® 8 47mm / 51mm | 454x454 | round | amoled | 768 KB | enter, up, menu, down, esc | yes | 6.0 |
| `fenix843mm` | fēnix® 8 43mm | 416x416 | round | amoled | 768 KB | enter, up, menu, down, esc | yes | 6.0 |
| `fenix8solar47mm` | fēnix® 8 Solar 47mm | 260x260 | round | mip | 768 KB | enter, up, menu, down, esc | yes | 6.0 |
| `fenix8solar51mm` | fēnix® 8 Solar 51mm / tactix® 8 Solar 51mm | 280x280 | round | mip | 768 KB | enter, up, menu, down, esc | yes | 6.0 |
| `fenix7` | fēnix® 7 / quatix® 7 | 260x260 | round | mip | 768 KB | enter, up, menu, down, esc | yes | 5.2 |
| `fenix7pro` | fēnix® 7 Pro | 260x260 | round | mip | 768 KB | enter, up, menu, down, esc | yes | 5.2 |
| `fenix7pronowifi` | fēnix® 7 Pro - Solar Edition (no Wi-Fi) | 260x260 | round | mip | 768 KB | enter, up, menu, down, esc | yes | 5.2 |
| `fenix7s` | fēnix® 7S | 240x240 | round | mip | 768 KB | enter, up, menu, down, esc | yes | 5.2 |
| `fenix7spro` | fēnix® 7S Pro | 240x240 | round | mip | 768 KB | enter, up, menu, down, esc | yes | 5.2 |
| `fenix7x` | fēnix® 7X / tactix® 7 / quatix® 7X Solar / Enduro™ 2 | 280x280 | round | mip | 768 KB | enter, up, menu, down, esc | yes | 5.2 |
| `fenix7xpro` | fēnix® 7X Pro | 280x280 | round | mip | 768 KB | enter, up, menu, down, esc | yes | 5.2 |
| `fenix7xpronowifi` | fēnix® 7X Pro - Solar Edition (no Wi-Fi) | 280x280 | round | mip | 768 KB | enter, up, menu, down, esc | yes | 5.2 |
| `fenix6pro` | fēnix® 6 Pro / 6 Sapphire / 6 Pro Solar / 6 Pro Dual Power / quatix® 6 | 260x260 | round | mip | 1280 KB | enter, up, menu, down, esc | no | 3.4 |
| `fenix6xpro` | fēnix® 6X Pro / 6X Sapphire / 6X Pro Solar / tactix® Delta Sapphire / Delta Solar / Delta Solar - Ballistics Edition / quatix® 6X / 6X Solar / 6X Dual Power | 280x280 | round | mip | 1280 KB | enter, up, menu, down, esc | no | 3.4 |
| `fenix6spro` | fēnix® 6S Pro / 6S Sapphire / 6S Pro Solar / 6S Pro Dual Power | 240x240 | round | mip | 1280 KB | enter, up, menu, down, esc | no | 3.4 |
| `fenix6` | fēnix® 6 / 6 Solar / 6 Dual Power | 260x260 | round | mip | 128 KB | enter, up, menu, down, esc | no | 3.4 |
| `fenix6s` | fēnix® 6S / 6S Solar / 6S Dual Power | 240x240 | round | mip | 128 KB | enter, up, menu, down, esc | no | 3.4 |
| `epix2` | epix™ (Gen 2) / quatix® 7 Sapphire | 416x416 | round | amoled | 768 KB | enter, up, menu, down, esc | yes | 5.2 |
| `epix2pro42mm` | epix™ Pro (Gen 2) 42mm | 390x390 | round | amoled | 768 KB | enter, up, menu, down, esc | yes | 5.2 |
| `epix2pro47mm` | epix™ Pro (Gen 2) 47mm / quatix® 7 Pro | 416x416 | round | amoled | 768 KB | enter, up, menu, down, esc | yes | 5.2 |
| `epix2pro51mm` | epix™ Pro (Gen 2) 51mm / D2™ Mach 1 Pro / tactix® 7 – AMOLED Edition | 454x454 | round | amoled | 768 KB | enter, up, menu, down, esc | yes | 5.2 |
| `venu3` | Venu® 3 | 454x454 | round | amoled | 768 KB | enter, menu, esc | yes | 5.2 |
| `venu3s` | Venu® 3S | 390x390 | round | amoled | 768 KB | enter, menu, esc | yes | 5.2 |
| `vivoactive5` | vívoactive® 5 | 390x390 | round | amoled | 768 KB | enter, menu, esc | yes | 5.2 |
| `vivoactive6` | vívoactive® 6 | 390x390 | round | amoled | 768 KB | enter, esc | yes | 6.0 |

<!-- END GENERATED MATRIX -->

## Per-device verification

For each device, verify:

| Check | How |
|---|---|
| Compilation | `make build DEVICE=<id>` — no errors, no warnings |
| Screen resolution | Layout readable; `Theme.drawFitted` picked a sensible font |
| Memory constraints | Simulator → *File → View Memory*; headroom at peak (overview with a long workout) |
| Buttons | START completes a set; BACK opens the overview; UP/DOWN adjust weight; MENU opens actions |
| Touch support | Optional tap on reps works where present; **everything works with touch disabled** |
| ActivityRecording | Activity starts, laps are marked per set, saves successfully |
| Storage | Session persists across an app restart |
| Vibration | Single buzz at rest expiry; silent where unsupported or disabled |
| Layouts | No clipped text on the smallest (`fenix6pro`, 240x240) or largest (`fenix9pro51mm`, 466x466) screen |
| API level | `minApiLevel` 3.1.0 satisfied by the device |

## Fallbacks for older devices

RepFlow's `minApiLevel` is **3.1.0**; the Fenix 6 family reports API level 3.4, so it qualifies. Where a
capability is missing, RepFlow degrades rather than dropping the feature for
modern devices:

| Capability | Fallback |
|---|---|
| Vibration | `Attention has :vibrate` and `DeviceSettings.vibrateOn` are checked; silently skipped |
| Touch | Every action is reachable by button; touch only ever adds a shortcut |
| `ActivityRecording` | `Toybox has :ActivityRecording` checked; the workout runs without a FIT recording |
| Garmin metrics | Calories / average HR rows are omitted when `Activity.getActivityInfo()` does not provide them |
| Large fonts | `Theme.drawFitted` falls back down a font ladder until the text fits |

No modern-device behaviour is compromised for legacy compatibility.

## Results log

| Date | Version | Device | Build | Unit tests | Simulator | Physical | Notes |
|---|---|---|---|---|---|---|---|
| 2026-09-11 | 0.1.0-dev | all 33 products | ✅ 33/33 | — | — | — | `make build-all`, SDK 9.2.0 |
| 2026-09-11 | 0.1.0-dev | `fenix6pro` | ✅ | ✅ 18/18 | ✅ launches | ⬜ pending | Tightest layout; no touch |
| 2026-09-11 | 0.1.0-dev | `fenix9pro47mm` | ✅ | ✅ 18/18 | ✅ launches | ⬜ pending | Primary target |
| | | | | | | | |

### Release binary sizes

Release builds (`monkeyc -r`) are around **35 KB**; debug builds are ~150 KB
because of the embedded symbol information. Only the release size matters for
the device memory budget — this is what makes `fenix6` / `fenix6s`, with a
128 KB watch-app limit, comfortably viable.
