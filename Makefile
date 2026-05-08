SHELL := /bin/bash
APP_NAME := CCAccountManager
DISPLAY_NAME := CC Account Manager
BUILD_CONFIG := release
BIN_PATH := .build/$(BUILD_CONFIG)/$(APP_NAME)
APP_BUNDLE := build/$(DISPLAY_NAME).app
INSTALL_DIR := $(HOME)/Applications

.PHONY: all build app install run clean test fmt

all: app

build:
	swift build -c $(BUILD_CONFIG)

app: build
	@echo ">> Assembling .app bundle"
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(BIN_PATH)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp Resources/Info.plist.template "$(APP_BUNDLE)/Contents/Info.plist"
	@if [ -d "$(BIN_PATH)_CCAccountManager.bundle" ]; then \
		cp -R "$(BIN_PATH)_CCAccountManager.bundle/." "$(APP_BUNDLE)/Contents/Resources/"; \
	fi
	@echo ">> Ad-hoc codesign"
	@codesign --force --deep --sign - "$(APP_BUNDLE)"
	@echo ">> Built: $(APP_BUNDLE)"

install: app
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(DISPLAY_NAME).app"
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	@echo ">> Installed to $(INSTALL_DIR)/$(DISPLAY_NAME).app"

run: app
	@open "$(APP_BUNDLE)"

test:
	swift test

clean:
	rm -rf .build build

fmt:
	@command -v swift-format >/dev/null 2>&1 && swift-format -i -r Sources Tests || echo "swift-format not installed; skipping"
