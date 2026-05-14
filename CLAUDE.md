# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app is

A Flutter app called **shit_covered_stick** — a silent Zen koan delivery app. It shows a single koan on a pure black screen and pushes the next one as a local notification after an intentionally irregular delay (hours to weeks). There is no UI interaction, no navigation, no settings screen. The experience is the silence.

## Commands

```bash
# Run on device/emulator
flutter run

# Build APK
flutter build apk

# Build iOS
flutter build ios

# Analyze (lint)
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart
```

## Architecture

All app logic lives in four files under `lib/`:

- **`koans.dart`** — static list of Zen koans (plain `List<String>`). No logic, just corpus.
- **`notification_service.dart`** — all scheduling logic. `initNotifications()` is called at startup; `scheduleNext()` picks a random koan (avoiding repeat of last), persists it to `SharedPreferences`, and schedules a `flutter_local_notifications` zonedSchedule with a random delay from `_nextDelayHours()`. `getCurrentKoan()` reads the persisted current koan.
- **`home_screen.dart`** — `HomeScreen` calls `getCurrentKoan()` on init; if none exists (first launch), calls `scheduleNext()` to both schedule and set the first koan. Renders the koan as plain white text on black, or empty if not ready.
- **`main.dart`** — calls `initNotifications()`, sets full-black system UI chrome, mounts `App` → `HomeScreen`.

### Notification timing intent

`_nextDelayHours()` is deliberately irregular — weighted toward medium gaps (12h–3d), with a long tail up to 20 days. **Do not make this predictable or configurable** — unpredictability is a design constraint, not an oversight.

### Key dependencies

| Package | Purpose |
|---|---|
| `flutter_local_notifications` | Scheduling silent push notifications |
| `timezone` | Required for `zonedSchedule` |
| `shared_preferences` | Persisting current koan index and text across launches |
| `workmanager` | Available in pubspec but not yet wired in |
