# Environment

The environment RepFlow was developed and verified against, and how to
reproduce it.

## Verified environment

| Item | Value |
|---|---|
| OS | macOS 26.5.2 (Darwin 25.5.0), arm64 |
| Shell | zsh |
| Java | Temurin OpenJDK 26.0.2.1 (Garmin requires **11+**) |
| Connect IQ SDK | **9.2.0** (`connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2`) |
| Compiler | `monkeyc` 9.2.0 |
| SDK Manager | 1.0.16 (Homebrew cask `connectiq-sdk-manager`) |
| Other tooling | git, make, just, openssl, VS Code |

The SDK version is **not** hard-coded anywhere in the build. `scripts/lib.sh`
resolves whichever SDK is active, in this order:

1. `$CIQ_SDK_HOME`, if it contains `bin/monkeyc`
2. `~/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg`
3. the newest directory under `.../ConnectIQ/Sdks/`

Run `make doctor` to see what is actually in use.

## Locations

| What | Where (macOS) |
|---|---|
| SDKs | `~/Library/Application Support/Garmin/ConnectIQ/Sdks/` |
| Active SDK pointer | `~/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg` |
| Device definitions | `~/Library/Application Support/Garmin/ConnectIQ/Devices/` |
| Developer signing key | `~/.garmin/repflow/developer_key.der` (outside the repo) |

On Windows these live under `%APPDATA%\Garmin\ConnectIQ`; on Linux under
`~/.Garmin/ConnectIQ`.

The bootstrap scripts deliberately **do not edit your shell configuration**.
The SDK's `bin` directory is added to `PATH` only for the duration of each
script, by `scripts/lib.sh`. If you want `monkeyc` on your interactive `PATH`,
add this to your own shell rc file:

```sh
export PATH="$(tr -d '\n' < "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")bin:$PATH"
```

## Setting up from scratch

```sh
make bootstrap     # macOS / Linux
# Windows:  powershell -File scripts/bootstrap-windows.ps1
make doctor
```

`make bootstrap` installs a JDK if needed, downloads and installs the latest
Connect IQ SDK from Garmin's public SDK feed, installs the SDK Manager and
VS Code with the Monkey C extension, and creates a developer signing key.

## The one step that cannot be automated

**Device definitions require a signed-in Garmin account.**

Garmin distributes device definitions (`compiler.json`, `simulator.json`,
screen and font metrics for each watch) only through the Connect IQ SDK
Manager, which requires signing in with a Garmin developer account and
accepting the SDK licence. The SDK Manager binary talks to
`monkeynet.garmin.com` with an OAuth token; there is no public anonymous
endpoint and no CLI.

Without them, `monkeyc` cannot compile for any target at all.

To install them:

1. Open the Connect IQ SDK Manager
   (`/Applications/SdkManager.app` on macOS — `make bootstrap` installs it).
2. Sign in with your Garmin account and accept the SDK licence.
3. Open the **Devices** tab.
4. Download the devices RepFlow targets — at minimum:
   - `fenix9pro47mm`, `fenix9pro51mm` (primary targets)
   - `fenix6pro` (the developer's own watch)
   Download all of them if you intend to publish, since the Store bundle
   needs every product declared in `manifest.xml`.
5. `make doctor` — it should now report `[OK] required device definitions`.

`make devices` lists what can be built right now, `make devices-missing` lists
what `manifest.xml` declares but is not installed locally, and
`scripts/devices.sh --all` lists every device definition installed locally.

## Finding real device ids

Device ids in `manifest.xml` were taken from the installed device definitions,
never invented.

**Use `scripts/devices.sh --all`, not `--known`.** The SDK ships a bundled
`resources/device-reference/` folder of reference artwork, which `--known`
reads — but that folder **lags the real device list**. In SDK 9.2.0 it contains
no Fenix 9 entries at all, even though the Fenix 9 Pro device definitions
download and compile perfectly:

```sh
scripts/devices.sh --all | grep fenix9
# fenix943mm fenix947mm fenix9pro43mm fenix9pro47mm fenix9pro51mm
# fenix9prosolar47mm fenix9prosolar51mm
```

The authoritative source is always what the SDK Manager has downloaded into
`Devices/`. See `docs/DEVICE_MATRIX.md` for the generated capability table.

## Simulator on Linux

The Connect IQ simulator is a GTK application. On some distributions it needs
extra libraries (`libwebkit2gtk`, `libpng`, 32-bit compatibility packages on
older SDKs). If `connectiq` exits silently, run the binary directly to see the
loader error:

```sh
"$(tr -d '\n' < ~/.Garmin/ConnectIQ/current-sdk.cfg)bin/simulator"
```
