# Workmanager Notification Chaining Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire `workmanager` into `scheduleNext()` so each notification schedules its own replacement in background, making the koan chain self-perpetuating without the user ever opening the app.

**Architecture:** `scheduleNext()` computes one random delay and uses it for both a `zonedSchedule` notification (display) and a `workmanager` one-off task (chaining). When the task fires in background it re-initializes Flutter bindings and calls `scheduleNext()` again. `cancelByUniqueName` before every registration prevents duplicate tasks.

**Tech Stack:** Flutter, workmanager ^0.5.0, flutter_local_notifications ^18.0.0, shared_preferences ^2.3.0

---

### Task 1: Fix widget test and add service unit tests

**Files:**
- Modify: `test/widget_test.dart`
- Create: `test/notification_service_test.dart`

The existing widget test references `MyApp` which does not exist — it is a copy-paste artifact from the default Flutter template. Fix it to test the actual `App` widget with a pre-seeded koan so no platform channels are invoked.

- [ ] **Step 1: Replace `test/widget_test.dart` with a real smoke test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shit_covered_stick/main.dart';

void main() {
  testWidgets('renders koan text on black screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'current_koan': 'Wu.',
    });
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();
    expect(find.text('Wu.'), findsOneWidget);
  });
}
```

> Pre-seeding `current_koan` means `HomeScreen._load()` returns early from `getCurrentKoan()` without calling `scheduleNext()`, so no platform channels (notifications, workmanager) are invoked.

- [ ] **Step 2: Run to verify it fails** (it will — `MyApp` reference is gone but `App` hasn't been tested yet)

```
flutter test test/widget_test.dart
```

Expected: FAIL — `The following TestFailure was thrown` or similar widget-not-found error.

- [ ] **Step 3: Create `test/notification_service_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shit_covered_stick/notification_service.dart';

void main() {
  group('getCurrentKoan', () {
    test('returns null when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await getCurrentKoan(), isNull);
    });

    test('returns stored koan', () async {
      SharedPreferences.setMockInitialValues({
        'current_koan': 'Ordinary mind is the way.',
      });
      expect(
        await getCurrentKoan(),
        equals('Ordinary mind is the way.'),
      );
    });
  });
}
```

- [ ] **Step 4: Run service tests to confirm they pass already**

```
flutter test test/notification_service_test.dart
```

Expected: PASS — `getCurrentKoan` is already implemented correctly. These tests establish the baseline.

- [ ] **Step 5: Commit**

```
git add test/widget_test.dart test/notification_service_test.dart
git commit -m "test: fix broken widget test, add getCurrentKoan unit tests"
```

---

### Task 2: Add `callbackDispatcher` and workmanager scheduling to `notification_service.dart`

**Files:**
- Modify: `lib/notification_service.dart`

Two changes:
1. Add a top-level `callbackDispatcher` function that workmanager calls in a separate isolate.
2. Capture `_nextDelayHours()` into a local variable and use it for both `zonedSchedule` and a paired `registerOneOffTask`.

- [ ] **Step 1: Replace `lib/notification_service.dart` with the updated file**

```dart
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:workmanager/workmanager.dart';
import 'koans.dart';

final _plugin = FlutterLocalNotificationsPlugin();
final _rng = Random();

const _lastIndexKey = 'last_koan_index';
const _channelId = 'stick';
const _channelName = 'The Stick';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await initNotifications();
    await scheduleNext();
    return true;
  });
}

Future<void> initNotifications() async {
  tz.initializeTimeZones();

  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  await _plugin.initialize(
    const InitializationSettings(android: android, iOS: ios),
  );
}

Future<void> requestPermissions() async {
  await _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  await _plugin
      .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, badge: false, sound: false);
}

Future<String> scheduleNext() async {
  final prefs = await SharedPreferences.getInstance();
  final lastIndex = prefs.getInt(_lastIndexKey) ?? -1;

  int nextIndex;
  do {
    nextIndex = _rng.nextInt(koans.length);
  } while (nextIndex == lastIndex && koans.length > 1);

  await prefs.setInt(_lastIndexKey, nextIndex);
  await prefs.setString('current_koan', koans[nextIndex]);

  final delayHours = _nextDelayHours();
  final scheduledTime = tz.TZDateTime.now(tz.local).add(
    Duration(hours: delayHours),
  );

  await _plugin.zonedSchedule(
    0,
    null,
    koans[nextIndex],
    scheduledTime,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: BigTextStyleInformation(koans[nextIndex]),
        enableLights: false,
        playSound: false,
        enableVibration: false,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
      ),
    ),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
  );

  await Workmanager().cancelByUniqueName('koan-chain');
  await Workmanager().registerOneOffTask(
    'koan-chain',
    'scheduleNext',
    initialDelay: Duration(hours: delayHours),
  );

  return koans[nextIndex];
}

int _nextDelayHours() {
  // Not daily. Not weekly. Not learnable.
  // Weighted toward medium gaps, with occasional long silences.
  final roll = _rng.nextDouble();
  if (roll < 0.30) return 12 + _rng.nextInt(12);      // half a day to a day
  if (roll < 0.60) return 24 + _rng.nextInt(48);      // one to three days
  if (roll < 0.85) return 72 + _rng.nextInt(120);     // three to eight days
  return 240 + _rng.nextInt(240);                      // ten to twenty days
}

Future<String?> getCurrentKoan() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('current_koan');
}
```

- [ ] **Step 2: Run analyze**

```
flutter analyze lib/notification_service.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Run service tests**

```
flutter test test/notification_service_test.dart
```

Expected: PASS

- [ ] **Step 4: Commit**

```
git add lib/notification_service.dart
git commit -m "feat: add callbackDispatcher and workmanager chaining to scheduleNext"
```

---

### Task 3: Initialize workmanager in `main.dart`

**Files:**
- Modify: `lib/main.dart`

Add the workmanager import and one `initialize` call after `initNotifications`. `callbackDispatcher` is now a top-level export from `notification_service.dart`.

- [ ] **Step 1: Replace `lib/main.dart` with the updated file**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'notification_service.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(surface: Colors.black),
      ),
      home: const HomeScreen(),
    );
  }
}
```

- [ ] **Step 2: Run analyze**

```
flutter analyze lib/main.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Run widget test**

```
flutter test test/widget_test.dart
```

Expected: PASS

- [ ] **Step 4: Commit**

```
git add lib/main.dart
git commit -m "feat: initialize workmanager with callbackDispatcher on app start"
```

---

### Task 4: iOS background task configuration

**Files:**
- Modify: `ios/Runner/Info.plist`

Two additions to `Info.plist`:
- `BGTaskSchedulerPermittedIdentifiers` — tells iOS which background task identifiers this app is allowed to register. workmanager uses `be.tramm.flutter.workmanager`.
- `UIBackgroundModes` — declares `fetch` and `processing` capabilities so the OS grants background execution time.

- [ ] **Step 1: Add the two keys to `ios/Runner/Info.plist`**

Insert before the closing `</dict>` tag (i.e., before line 48):

```xml
	<key>BGTaskSchedulerPermittedIdentifiers</key>
	<array>
		<string>be.tramm.flutter.workmanager</string>
	</array>
	<key>UIBackgroundModes</key>
	<array>
		<string>fetch</string>
		<string>processing</string>
	</array>
```

The final `</dict></plist>` block should look like:

```xml
	<key>BGTaskSchedulerPermittedIdentifiers</key>
	<array>
		<string>be.tramm.flutter.workmanager</string>
	</array>
	<key>UIBackgroundModes</key>
	<array>
		<string>fetch</string>
		<string>processing</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: Commit**

```
git add ios/Runner/Info.plist
git commit -m "feat: add iOS background task identifiers for workmanager"
```

---

### Task 5: On-device verification (Android)

workmanager background execution cannot be tested in the Flutter test harness — it requires a real device or emulator.

- [ ] **Step 1: Run on Android device/emulator**

```
flutter run
```

- [ ] **Step 2: Confirm first-launch flow**

On first launch (fresh install, no SharedPreferences), the app should show a koan. Open logcat and filter for `WorkManager`:

```
adb logcat | grep -i workmanager
```

Expected: a task named `koan-chain` should be enqueued.

- [ ] **Step 3: Force workmanager to fire immediately for testing**

In a debug build, trigger the task without waiting hours:

```
adb shell am broadcast -a androidx.work.diagnostics.REQUEST_DIAGNOSTICS --es "output" "logcat"
```

Or use the WorkManager test helper via `flutter_test` on Android. Alternatively, temporarily change `_nextDelayHours()` to return `0` (or `1`), reinstall, and observe that a second notification is scheduled after the first fires.

- [ ] **Step 4: Restore `_nextDelayHours()` if modified in step 3**

If you changed `_nextDelayHours()` to return a short delay for testing, revert it before shipping.

- [ ] **Step 5: Final full test run**

```
flutter test
flutter analyze
```

Expected: all tests PASS, no analysis issues.

- [ ] **Step 6: Commit if any changes remain**

```
git add -p
git commit -m "chore: post-device-test cleanup"
```
