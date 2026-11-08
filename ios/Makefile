# Bandje for iOS. Fixed test simulator: iPhone 17 Pro, iOS 26.5.
# The first "iPhone 17 Pro" simulator (ids change when simulators are recreated).
SIM ?= $(shell xcrun simctl list devices available | grep -m1 "iPhone 17 Pro .[0-9A-F]" | grep -oE "[0-9A-F-]{36}")
PROJECT = Bandje.xcodeproj
SCHEME = Bandje
DERIVED = build/DerivedData
PACKAGES = build/SourcePackages
XCB = xcodebuild -quiet -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -clonedSourcePackagesDirPath $(PACKAGES)
SIM_APP = $(DERIVED)/Build/Products/Debug-iphonesimulator/Bandje.app

.PHONY: gen resolve build fixtures test run screenshots device clean models-check

gen:
	xcodegen generate --quiet

resolve: gen
	$(XCB) -resolvePackageDependencies

build: gen
	$(XCB) -destination id=$(SIM) -configuration Debug build

fixtures:
	bash scripts/dev/make-fixtures.sh >/dev/null

test: gen fixtures
	@xcrun simctl boot $(SIM) 2>/dev/null || true
	rm -rf build/test.xcresult
	$(XCB) -destination id=$(SIM) -resultBundlePath build/test.xcresult test
	xcrun xcresulttool get test-results summary --path build/test.xcresult --compact

run: build
	@xcrun simctl boot $(SIM) 2>/dev/null || true
	xcrun simctl install $(SIM) $(SIM_APP)
	xcrun simctl launch $(SIM) com.neurendal.bandje $(ARGS)

# Verify the models inside the built simulator app against models.lock.json.
models-check:
	python3 scripts/verify-and-copy-models.py verify $(SIM_APP)/Models

STATES ?= empty library recording idle playing-10 playing-90 transcript transcribing summary import-error error about

screenshots: build
	bash scripts/dev/screenshots.sh $(SIM) $(SIM_APP) $(STATES)

device: gen
	$(XCB) -destination generic/platform=iOS -configuration Release -allowProvisioningUpdates build

clean:
	rm -rf build $(PROJECT)
