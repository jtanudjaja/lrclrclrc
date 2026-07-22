# Convenience wrapper around the build scripts.
#
#   make        → build and launch the app (same as `make run`)
#   make build  → just compile + assemble lrclrclrc.app
#   make run    → build, then (re)launch the app
#   make dmg    → build and package lrclrclrc.dmg
#   make debug  → build a debug configuration
#   make clean  → remove build outputs

APP := lrclrclrc.app

.DEFAULT_GOAL := run
.PHONY: build run dmg debug clean

build:
	bash scripts/build-app.sh release

debug:
	bash scripts/build-app.sh debug

run: build
	@killall lrclrclrc 2>/dev/null || true
	open $(APP)

dmg: build
	bash scripts/make-dmg.sh

clean:
	rm -rf .build $(APP) lrclrclrc.dmg
