.PHONY: build test app install clean

build:
	swift build

# Plain Command Line Tools do not ship XCTest, so `swift test` needs the
# full Xcode toolchain (XCTest.framework lives inside Xcode.app). Point
# DEVELOPER_DIR at Xcode for this target only; `build`/`app` stay CLT-only.
# Override for Xcode-beta or non-standard installs:
#   make test XCODE_DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
XCODE_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

# Separate --build-path: `build` uses CLT's Swift and `test` uses Xcode's, and
# a shared .build makes each clobber the other's modules ("module compiled with
# Swift X cannot be imported by the Swift Y compiler").
test:
	DEVELOPER_DIR=$(XCODE_DEVELOPER_DIR) swift test --build-path .build-test

app:
	./scripts/make-app.sh

install: app
	rm -rf /Applications/xfake.app
	cp -R build/xfake.app /Applications/
	@echo "Installed. Launch from /Applications (menu bar icon: eyeglasses)."

clean:
	rm -rf .build .build-test build
