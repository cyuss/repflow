# Documentation

Start with [`PRODUCT.md`](PRODUCT.md) if you want to know what RepFlow is for,
and [`ARCHITECTURE.md`](ARCHITECTURE.md) if you want to know how it is built.

## The product

| | |
|---|---|
| [PRODUCT.md](PRODUCT.md) | What it is for, and what it refuses to do |
| [FEATURE_BACKLOG.md](FEATURE_BACKLOG.md) | What is worth building next, and what the platform refuses outright |

## The code

| | |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | How the pieces fit, and which file is allowed to touch what |
| [API_LIMITATIONS.md](API_LIMITATIONS.md) | What Connect IQ genuinely cannot do, each entry with how it was verified |
| [TESTING.md](TESTING.md) | How the suites run, and the traps in the simulator |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Day-to-day commands |
| [ENVIRONMENT.md](ENVIRONMENT.md) | SDK, device definitions, signing key |

## Garmin and Hevy

| | |
|---|---|
| [garmin-strength-integration-poc.md](garmin-strength-integration-poc.md) | The three routes into Garmin Connect's native strength table, why only one is open, and the evidence for each claim |
| [HEVY_SYNC_FEASIBILITY.md](HEVY_SYNC_FEASIBILITY.md) | What Hevy's API does and does not carry |

## The pictures

`assets/` holds the diagrams the README uses. They are hand-written animated
SVGs rather than screenshots, so that they explain the app without pretending to
be it, and they stay readable in a still frame for anything that will not
animate them.

| | |
|---|---|
| [assets/banner.svg](assets/banner.svg) | The wordmark, and the focus moving out of order |
| [assets/any-order.svg](assets/any-order.svg) | One session, taken in the order the gym allowed |
| [assets/a-session.svg](assets/a-session.svg) | Choose, lift, rest, recap |
| [assets/where-it-goes.svg](assets/where-it-goes.svg) | What leaves the watch by itself, and what needs a command |

## Devices and release

| | |
|---|---|
| [DEVICE_MATRIX.md](DEVICE_MATRIX.md) | Every supported product and its screen |
| [DEVICE_TESTING.md](DEVICE_TESTING.md) | What to check on real hardware |
| [SMOKE_TEST.md](SMOKE_TEST.md) | The manual gate before a release |
| [SIGNING.md](SIGNING.md) | The developer key, and why it must never change |
| [CONNECT_IQ_DEPLOYMENT.md](CONNECT_IQ_DEPLOYMENT.md) | Publishing to the Connect IQ Store |
| [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) | The list, in order |
| [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) | Where the work stands |

## evidence/

Screenshots that back a specific claim made in one of the documents above. Each
one is referenced from the text it supports; none is decoration.
