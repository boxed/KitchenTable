# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

This is a macOS Cocoa app built with Xcode. Open `KitchenTable.xcodeproj` in Xcode to build and run, or use the command line:

```bash
xcodebuild -scheme KitchenTable -configuration Debug build
```

There are no tests.

## Architecture

KitchenTable is a single-window macOS app that acts as a dashboard display, designed to be rendered to a 960x540 PNG image and served over HTTP (port 8123) to an external display (e.g., an e-ink screen).

All app logic lives in `AppDelegate.swift`. The UI is defined in `Base.lproj/MainMenu.xib`.

### What it displays

- **Date**: Current day number (large, right side) and weekday name in Swedish (top right)
- **Calendar events**: Today's events from the "Delad" calendar, split into AM (above separator) and PM (below separator)
- **Weather icons**: Rain icon (cloud.heavyrain) if rain >= 10mm, sun icon (sun.max) if UV index >= 3

### Data flow

1. A 5-second timer calls `dateUpdater()` and `readCalendar()` repeatedly
2. Changes to any displayed data set `dataChanged` to a new `Date()`
3. `updateDisplay()` compares `dataChanged` vs `lastChanged` — only re-renders the PNG when something actually changed
4. PNG rendering captures the NSView to a bitmap, compresses on a background thread

### HTTP server (Swifter)

- `GET /last_changed` — returns the timestamp of last PNG update and seconds until next midnight+10min; accepts optional `?battery=` query param displayed in window title
- `GET /image` — returns the current PNG

### Dependencies

- **Swifter** (Swift Package Manager, v1.5.0) — lightweight HTTP server
- **EventKit** — calendar access
- **Open-Meteo API** — weather data (fetched at most once per hour)

### Key details

- Location is hardcoded to coordinates 59.41789, 17.95551 (Stockholm area)
- Weather data comes from `api.open-meteo.com` (no API key needed)
- App is sandboxed with network client/server and calendar entitlements
