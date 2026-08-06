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

.PHONY: build test run dict clean

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

snapshots:
	swift run Twist --snapshot build/snapshots

sounds:
	swift run Twist --export-sounds build/sounds
