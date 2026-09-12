.DEFAULT_GOAL := help
SHELL := /bin/bash

# Override the build target on the command line:
#   make build DEVICE=fenix847mm
DEVICE ?= fenix6pro
# monkeyc type-check level: 0=off 1=gradual 2=informative 3=strict
TYPECHECK ?= 3

# The simulator targets ask which device to run when you do not name one.
# Passing DEVICE=<id> on the command line skips the question.
ifeq ($(origin DEVICE), command line)
SIM_DEVICE := $(DEVICE)
else
SIM_DEVICE :=
endif

export DEVICE
export TYPECHECK

.PHONY: help doctor bootstrap key devices devices-all devices-missing \
        build build-all test sim sim-fresh sim-attach shot sideload \
        clean package release-check

help: ## Show this help
	@echo "RepFlow — your workout, your order."
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "  DEVICE=$(DEVICE)   (override: make build DEVICE=<id>; list ids with 'make devices')"

doctor: ## Check the development environment
	@scripts/doctor.sh

bootstrap: ## Install SDK, tooling and signing key for this OS
	@case "$$(uname -s)" in \
		Darwin) scripts/bootstrap-macos.sh ;; \
		Linux)  scripts/bootstrap-linux.sh ;; \
		*) echo "On Windows run: powershell -File scripts/bootstrap-windows.ps1"; exit 1 ;; \
	esac

key: ## Create the developer signing key if it does not exist
	@scripts/make-developer-key.sh

devices: ## List device ids RepFlow can be built for right now
	@scripts/devices.sh

devices-all: ## List every device definition installed locally
	@scripts/devices.sh --all

devices-missing: ## List manifest products whose definitions are not installed
	@scripts/devices.sh --missing

build: ## Build a signed PRG for $(DEVICE)
	@scripts/build.sh $(DEVICE)

build-all: ## Build every device declared in manifest.xml and installed locally
	@scripts/build.sh --all

test: ## Run the unit tests in the simulator
	@scripts/test.sh $(DEVICE)

sim: ## Pick a device and launch RepFlow in the simulator
	@REPFLOW_DETACH=1 scripts/run-simulator.sh $(SIM_DEVICE)

sim-fresh: ## Same, but clear the app's stored session first
	@REPFLOW_DETACH=1 REPFLOW_RESET=1 scripts/run-simulator.sh $(SIM_DEVICE)

sim-attach: ## Launch and stay attached, streaming the app's println output
	@scripts/run-simulator.sh $(SIM_DEVICE)

shot: ## Screenshot the simulator's watch face to build/sim-shot.png
	@scripts/shot.sh

.PHONY: store-shot
store-shot: ## Open the simulator's native-resolution export, for store screenshots
	@scripts/store-shots.sh

sideload: ## Build and copy a release PRG to a USB-connected watch
	@scripts/sideload.sh $(DEVICE)

package: ## Full release build: doctor, tests, all devices, .iq bundle
	@scripts/package.sh

release-check: ## Everything package does, plus the release checklist reminder
	@scripts/package.sh
	@echo
	@echo "Now work through docs/RELEASE_CHECKLIST.md before submitting."

clean: ## Remove build output
	@rm -rf build
	@mkdir -p build
	@echo "build/ cleaned"
