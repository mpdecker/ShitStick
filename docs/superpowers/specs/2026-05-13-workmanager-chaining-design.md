# Workmanager Notification Chaining

**Date:** 2026-05-13
**Status:** Approved

## Problem

`scheduleNext()` is called on first launch (when `current_koan` is null in SharedPreferences) and never again — the stored koan is never cleared, so the home screen never re-triggers scheduling. One notification fires, then silence forever unless the user reinstalls.

## Goal

Make the notification chain self-perpetuating in background without requiring the user to open the app.

## Approach: Paired scheduling

Each call to `scheduleNext()` registers two things at the same delay N:
1. A `flutter_local_notifications` `zonedSchedule` notification (existing, unchanged)
2. A `workmanager` one-off background task

When the workmanager task fires, it calls `scheduleNext()` again from a background isolate — scheduling the next notification + next task. This is self-perpetuating.

Platform behavior:
- **Android:** WorkManager is reliable; fires at approximately the scheduled time.
- **iOS:** Uses BGTaskScheduler; the OS may delay or skip firings. Accepted as best-effort. The chain self-repairs when the user next opens the app.

## Data Flow

```
First launch
  → HomeScreen: getCurrentKoan() == null → scheduleNext()
      → pick koan, store to SharedPreferences
      → zonedSchedule notification at now + N hours
      → cancel 'koan-chain' workmanager task (no-op on first run)
      → register 'koan-chain' one-off task, initialDelay: N hours

~N hours later (background)
  → callbackDispatcher fires in separate isolate
      → WidgetsFlutterBinding.ensureInitialized()
      → initNotifications()  ← re-init required in isolate
      → scheduleNext()       ← picks next koan, schedules next pair
      → return true
```

## Files Changed

### `lib/notification_service.dart`
- Add `@pragma('vm:entry-point') void callbackDispatcher()` top-level function. Initializes bindings, timezone, notifications, then calls `scheduleNext()` inside `Workmanager().executeTask(...)`.
- In `scheduleNext()`:
  - Capture `_nextDelayHours()` into `final delayHours` (used for both the notification and the task).
  - After `_plugin.zonedSchedule(...)`, add:
    ```dart
    await Workmanager().cancelByUniqueName('koan-chain');
    await Workmanager().registerOneOffTask(
      'koan-chain',
      'scheduleNext',
      initialDelay: Duration(hours: delayHours),
    );
    ```

### `lib/main.dart`
- After `await initNotifications()`, add:
  ```dart
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  ```

### `ios/Runner/Info.plist`
- Add `BGTaskSchedulerPermittedIdentifiers` array containing `be.tramm.flutter.workmanager`.
- Add `UIBackgroundModes` array containing `fetch` and `processing`.

### Android
No manifest changes required. The workmanager package auto-initializes via its own `ContentProvider`.

## Constraints

- The `callbackDispatcher` function must be top-level (not inside a class) and annotated `@pragma('vm:entry-point')`.
- `_nextDelayHours()` is called once per `scheduleNext()` invocation and its result is reused for both the notification and workmanager task — they are always in sync.
- `cancelByUniqueName` before each registration ensures no duplicate tasks accumulate (safe to call from home screen, notification tap, or background callback).
