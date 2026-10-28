# TapTheTab developer tasks. `make help` lists them.
# The app targets (app, universal, package, run) need macOS + Xcode 16 / Swift 6.

SWIFT ?= swift
APP   := dist/TapTheTab.app

.DEFAULT_GOAL := help
.PHONY: help build test app universal package run clean lint

help: ## Show this help
	@grep -E '^[a-z][a-zA-Z_-]*:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

build: ## Debug build (core only on Linux)
	$(SWIFT) build

test: ## Run the unit tests
	$(SWIFT) test

app: ## Build dist/TapTheTab.app for this Mac (ad-hoc signed)
	scripts/build-app.sh

universal: ## Build a universal (arm64 + x86_64) dist/TapTheTab.app
	scripts/build-app.sh --universal

package: ## Zip + dmg + SHA256SUMS.txt from dist/TapTheTab.app (builds it if missing)
	@test -d $(APP) || $(MAKE) app
	scripts/package.sh

run: ## Open dist/TapTheTab.app (builds it if missing)
	@test -d $(APP) || $(MAKE) app
	open $(APP)

clean: ## Remove build products
	rm -rf .build dist

lint: ## Run swiftformat/swiftlint if installed (optional, not required)
	@if command -v swiftformat >/dev/null 2>&1; then \
		swiftformat --lint Sources Tests; \
	else \
		echo "note: swiftformat not installed; skipping (brew install swiftformat)"; \
	fi
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --quiet; \
	else \
		echo "note: swiftlint not installed; skipping (brew install swiftlint)"; \
	fi
