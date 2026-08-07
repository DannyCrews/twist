# Twist — build entry points.
#
# Use `make test`, not `swift test`.
#
# The Command Line Tools ship swift-testing under Library/Developer rather than in the
# toolchain, so SwiftPM does not find it on its own. Two things go wrong without the flags
# below, and the second is the dangerous one:
#
#   1. `import Testing` fails to compile in the test target.
#   2. SwiftPM's synthesized runner is wrapped in `#if canImport(Testing)`. If only the test
#      target can see the framework, that guard compiles away to an empty main(), and
#      `swift test` exits 0 having run nothing. Green, with zero tests executed.
#
# Target-level settings in Package.swift cannot reach the synthesized runner, so the search
# path has to be global — hence -Xswiftc here rather than swiftSettings there. Running
# `swift test` directly now fails loudly at compile time, which is the correct behaviour.

DEVELOPER := /Library/Developer/CommandLineTools/Library/Developer
FRAMEWORKS := $(DEVELOPER)/Frameworks
LIBS := $(DEVELOPER)/usr/lib

TESTFLAGS := -Xswiftc -F -Xswiftc $(FRAMEWORKS) \
             -Xlinker -F -Xlinker $(FRAMEWORKS) \
             -Xlinker -rpath -Xlinker $(FRAMEWORKS) \
             -Xlinker -rpath -Xlinker $(LIBS)

.PHONY: build test run dict clean play install app check snapshots sounds preflight

# The whole point of `make play`: clone, one command, the game opens. Anything that could stop
# that is checked first, and reported as an instruction rather than a compiler error.
preflight:
	@command -v swift >/dev/null 2>&1 || { \
		echo ""; \
		echo "Swift is not available yet — Twist needs Apple's Command Line Tools."; \
		echo ""; \
		echo "  Run this, let it finish, then try again:"; \
		echo ""; \
		echo "      xcode-select --install"; \
		echo ""; \
		echo "  About 1 GB, a few minutes. Full Xcode is not required."; \
		echo ""; \
		exit 1; \
	}
	@swift build --help >/dev/null 2>&1 || { \
		echo ""; \
		echo "Swift is installed but cannot build. Usually the developer directory is unset:"; \
		echo ""; \
		echo "      sudo xcode-select --switch /Library/Developer/CommandLineTools"; \
		echo ""; \
		exit 1; \
	}

# Build it and open it. This is the one to point a new player at.
play: preflight
	@echo "Building Twist — about a minute the first time…"
	@Scripts/bundle.sh
	@echo "Opening Twist."
	@open build/Twist.app

# Same, but keep it: copies into /Applications so it is there next time.
install: preflight
	@echo "Building Twist — about a minute the first time…"
	@Scripts/bundle.sh
	@rm -rf /Applications/Twist.app
	@cp -R build/Twist.app /Applications/Twist.app
	@echo "Installed to /Applications/Twist.app"
	@open /Applications/Twist.app

build:
	swift build

test:
	swift test $(TESTFLAGS)

run:
	swift run Twist

dict:
	swift run dicttool

clean:
	rm -rf .build

app:
	Scripts/bundle.sh

# Everything: unit tests, the full pass over the shipped word list, and a guard that every
# screen still renders something. `make test` alone is the fast inner loop.
check: test
	@echo "\n--- shipped word list ---"
	@swift run dicttool verify
	@echo "\n--- rendered screens ---"
	@swift run Twist --snapshot build/snapshots >/dev/null
	@python3 Scripts/check-snapshots.py build/snapshots

snapshots:
	swift run Twist --snapshot build/snapshots

sounds:
	swift run Twist --export-sounds build/sounds
