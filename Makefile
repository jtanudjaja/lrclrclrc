# Convenience wrapper around the build scripts.
#
#   make          → build and launch the app (same as `make run`)
#   make build    → just compile + assemble lrclrclrc.app
#   make run      → build, then (re)launch the app
#   make install  → build, copy lrclrclrc.app into /Applications, and launch it
#   make dmg      → build and package lrclrclrc.dmg
#   make debug    → build a debug configuration
#   make clean    → remove build outputs

APP := lrclrclrc.app
INSTALL_DIR := /Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP)

.DEFAULT_GOAL := run
.PHONY: build install run dmg debug clean

build:
	bash scripts/build-app.sh release

debug:
	bash scripts/build-app.sh debug

run: build
	@killall lrclrclrc 2>/dev/null || true
	open $(APP)

# Wait for the old instance to exit (`open` right after killall can re-activate
# the dying process instead of launching the new copy), and stage the copy
# before removing the old one so a failed ditto — or a bad APP/INSTALL_DIR
# override — dies harmlessly instead of leaving /Applications without the app.
install: build
	@killall lrclrclrc 2>/dev/null || true
	@for i in $$(seq 1 50); do pgrep -xq lrclrclrc || break; sleep 0.1; done
	rm -rf "$(INSTALLED_APP).tmp"
	ditto "$(APP)" "$(INSTALLED_APP).tmp"
	rm -rf "$(INSTALLED_APP)"
	mv "$(INSTALLED_APP).tmp" "$(INSTALLED_APP)"
	@echo "✓ installed $(INSTALLED_APP)"
	open "$(INSTALLED_APP)"

dmg: build
	bash scripts/make-dmg.sh

clean:
	rm -rf .build $(APP) lrclrclrc.dmg
