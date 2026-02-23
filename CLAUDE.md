# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**flowtrace** is a native macOS app (minimum macOS 15.7) built with Swift and SwiftUI. It is in early development — currently at the scaffolding stage with no business logic yet.

- Bundle ID: `vladgla.flowtrace`
- App Sandbox and Hardened Runtime are enabled
- No external dependencies (no CocoaPods, no Swift Package Manager packages)

## Build & Test Commands

Build (Debug):
```bash
xcodebuild build -project flowtrace.xcodeproj -scheme flowtrace -configuration Debug
```

Build (Release):
```bash
xcodebuild build -project flowtrace.xcodeproj -scheme flowtrace -configuration Release
```

Run all tests (unit + UI):
```bash
xcodebuild test -project flowtrace.xcodeproj -scheme flowtrace -destination 'platform=macOS'
```

Run unit tests only:
```bash
xcodebuild test -project flowtrace.xcodeproj -scheme flowtraceTests -destination 'platform=macOS'
```

## Architecture

The app uses the standard SwiftUI app lifecycle:

- **`flowtrace/flowtraceApp.swift`** — `@main` entry point; defines a `WindowGroup` scene containing `ContentView`
- **`flowtrace/ContentView.swift`** — root view; all UI starts here
- **`flowtrace/Assets.xcassets/`** — asset catalog for app icons and colors

Tests are split into two targets:
- **`flowtraceTests/`** — unit tests using Swift Testing (`@Test` macro, `@testable import flowtrace`)
- **`flowtraceUITests/`** — UI/launch tests using XCTest; includes launch performance measurement

As the app grows, add new Swift files under `flowtrace/` and register them in the Xcode project (`flowtrace.xcodeproj/project.pbxproj`).
