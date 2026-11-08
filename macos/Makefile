# Bandje build. CONFIG=debug (default, includes DEBUG test modes) or CONFIG=release.
CONFIG ?= debug
APP    := build/Bandje.app

# Network: the app has com.apple.security.network.client only for the Desert Ant Labs SDK's
# license check (at most once per model per calendar month: a random install ID, model and SDK
# version, app ID; never audio or text), which the SDK license requires. Bandje's own code never
# uses the network (scripts/check-no-network.sh).
ENT := Resources/Bandje.entitlements

# Speech models (Voz, Who) to ship inside the app, from scripts/fetch-models.sh (pinned by
# models.lock.json). BUNDLE_MODELS=0 builds without them; the app then loads ~/Music/Bandje/.models.
MODELS ?= $(HOME)/Music/Bandje/.models
BUNDLE_MODELS ?= 1
IDENTITY := $(BANDJE_SIGN_IDENTITY)

.PHONY: build app run clean test selftest selftest-quick install help-refresh

build:
	swift build -c $(CONFIG)

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c $(CONFIG) --show-bin-path)/Bandje" $(APP)/Contents/MacOS/Bandje
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp Resources/Logo.png $(APP)/Contents/Resources/Logo.png
	xcrun actool Resources/Assets.xcassets --compile $(APP)/Contents/Resources --platform macosx \
		--minimum-deployment-target 15.0 --output-partial-info-plist build/assets-partial.plist >/dev/null
	cp Resources/PrivacyInfo.xcprivacy $(APP)/Contents/Resources/PrivacyInfo.xcprivacy
	cp -R Resources/Localization/*.lproj $(APP)/Contents/Resources/
	python3 -I scripts/make-help.py build $(APP)
	@if [ "$(BUNDLE_MODELS)" = "1" ] && [ -f "$(MODELS)/voz/meta.json" ] && [ -d "$(MODELS)/who" ]; then \
		mkdir -p $(APP)/Contents/Resources/Models; \
		cp -Rc "$(MODELS)/voz" "$(MODELS)/who" $(APP)/Contents/Resources/Models/; \
		echo "Models bundled from $(MODELS)"; \
	else \
		echo "Models not bundled (run scripts/fetch-models.sh); the app loads ~/Music/Bandje/.models"; \
	fi
	plutil -lint $(APP)/Contents/Info.plist
	@if [ -n "$(IDENTITY)" ]; then \
		echo "Signing with: $(IDENTITY)"; \
		codesign --force --sign "$(IDENTITY)" --entitlements $(ENT) --timestamp=none $(APP); \
	else \
		echo "WARNING: BANDJE_SIGN_IDENTITY not set, signing ad-hoc."; \
		echo "WARNING: macOS may forget microphone/system-audio permissions after every rebuild."; \
		codesign --force --sign - --entitlements $(ENT) --timestamp=none $(APP); \
	fi
	codesign --verify --strict $(APP)

run: app
	open $(APP)

# Swift Testing only: XCTest's class enumeration crashes on the SDK's macOS 27-only class.
test:
	swift test --disable-xctest
	python3 -I scripts/strings.py check
	python3 -I scripts/make-help.py check

# Live end-to-end tests (DEBUG build, plays fixtures at low volume via afplay).
# Selftests check that recording opens no sockets (the SDK may check its license while transcribing).
# Full run (plays and records real audio, ~10 min): before audits and releases, or after changes
# to the recording pipeline. Quick run (no audio played or recorded, ~1 min): everything else.
selftest:
	$(MAKE) app
	./scripts/selftest.sh

selftest-quick:
	$(MAKE) app
	./scripts/selftest.sh static nomodels dictate memo help menu micswitch leaks

install:
	$(MAKE) app CONFIG=release
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/Bandje.app
	cp -R $(APP) $(HOME)/Applications/Bandje.app

clean:
	rm -rf build .build

# Show a rebuilt help book: macOS keeps a copy per app version and does not refresh it by itself.
help-refresh:
	python3 -I scripts/make-help.py clear
