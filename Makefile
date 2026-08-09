PROJECT           := Macstify.xcodeproj
SCHEME            := Macstify
PREVIEW_SCHEME    := MacstifyPreview
CONFIGURATION     := Release
DERIVED_DATA      := build
PRODUCTS          := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)
SAVER             := $(PRODUCTS)/Macstify.saver
PREVIEW           := $(PRODUCTS)/MacstifyPreview.app/Contents/MacOS/MacstifyPreview
INSTALL_DIR       := $(HOME)/Library/Screen Savers
DIST_DIR          := dist
DIST              := $(DIST_DIR)/Macstify.zip
CHECKSUM          := $(DIST_DIR)/checksum.txt
SUBMISSION        := $(DERIVED_DATA)/submission.zip

# codesign resolves this by prefix, and there is only one such identity.
CODESIGN_IDENTITY ?= Developer ID Application
NOTARY_PROFILE    ?= macstify

XCODEBUILD := xcodebuild -project $(PROJECT) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA)

.DEFAULT_GOAL := build

.PHONY: build
build:
	$(XCODEBUILD) -scheme $(SCHEME) build

.PHONY: install
install: build
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/Macstify.saver"
	cp -R $(SAVER) "$(INSTALL_DIR)/"
	@echo
	@echo 'Installed. macOS caches the loaded bundle, so if an older build is'
	@echo 'still running: killall legacyScreenSaver, then reopen System Settings.'

.PHONY: uninstall
uninstall:
	rm -rf "$(INSTALL_DIR)/Macstify.saver"

.PHONY: preview
preview:
	$(XCODEBUILD) -scheme $(PREVIEW_SCHEME) build
	$(PREVIEW)

.PHONY: lint
lint:
	swiftlint --strict

.PHONY: format
format:
	swiftformat Sources Preview

# Signs with Developer ID rather than the ad-hoc signature a plain build
# produces, then notarizes. Gatekeeper rejects anything less once the bundle
# reaches another Mac and picks up a quarantine flag. Stapling attaches the
# ticket to the bundle so it validates without a network round trip.
.PHONY: release
release:
	$(XCODEBUILD) -scheme $(SCHEME) \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY="$(CODESIGN_IDENTITY)" \
		OTHER_CODE_SIGN_FLAGS="--timestamp" \
		build
	codesign --verify --strict --verbose=2 $(SAVER)
	rm -f $(SUBMISSION)
	ditto -c -k --keepParent $(SAVER) $(SUBMISSION)
	xcrun notarytool submit $(SUBMISSION) --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(SAVER)
	xcrun stapler validate $(SAVER)
	mkdir -p $(DIST_DIR)
	rm -f $(DIST) $(CHECKSUM)
	ditto -c -k --keepParent $(SAVER) $(DIST)
	cd $(DIST_DIR) && shasum -a 256 $(notdir $(DIST)) > $(notdir $(CHECKSUM))
	@echo
	@echo "Ready to distribute:"
	@cat $(CHECKSUM)

.PHONY: clean
clean:
	rm -rf $(DERIVED_DATA) dist
