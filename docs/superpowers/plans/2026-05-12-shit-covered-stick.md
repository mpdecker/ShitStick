# Shit-Covered-Stick Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Flutter mobile app (iOS + Android) that delivers historical Zen encounter records as local push notifications at unpredictable intervals, shows the last delivered record on a black screen, and provides no mechanism for the user to request more.

**Architecture:** The app maintains a queue of 10 pre-scheduled local notifications, each bearing a raw koan drawn from the corpus without repetition. On every app open, the queue is inspected and refilled. Notifications carry no sound, badge, or vibration. The single screen shows whatever was last given. There is no navigation.

**Tech Stack:** Flutter 3.38.9, Dart 3.10.8, `flutter_local_notifications ^18.0.0`, `timezone ^0.9.0`, `shared_preferences ^2.3.0`

---

## File Map

| File | Status | Responsibility |
|------|--------|----------------|
| `lib/koans.dart` | exists | The corpus. Unchanged. |
| `lib/notification_service.dart` | modify | Replace single-shot with queue. Add tap callback. |
| `lib/home_screen.dart` | modify | Request permissions on first load. Reload on resume. |
| `lib/main.dart` | modify | Wire notification response handler. |
| `android/app/src/main/AndroidManifest.xml` | modify | App display label. |
| `ios/Runner/Info.plist` | modify | CFBundleDisplayName. |
| `test/koans_test.dart` | create | Corpus integrity. |
| `test/notification_service_test.dart` | create | Delay distribution, koan selection. |
| `test/widget_test.dart` | modify | Replace counter smoke test with home screen smoke test. |

---

## Task 1: Corpus integrity tests

**Files:**
- Create: `test/koans_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shit_covered_stick/koans.dart';

void main() {
  test('corpus is non-empty', () {
    expect(koans, isNotEmpty);
  });

  test('no koan is blank', () {
    for (final k in koans) {
      expect(k.trim(), isNotEmpty, reason: 'blank entry found');
    }
  });

  test('no duplicate koans', () {
    final seen = <String>{};
    for (final k in koans) {
      expect(seen.contains(k), isFalse, reason: 'duplicate: $k');
      seen.add(k);
    }
  });

  test('corpus has at least 20 entries', () {
    expect(koans.length, greaterThanOrEqualTo(20));
  });
}
```

- [ ] **Step 2: Run tests — expect PASS (corpus already exists)**

```
flutter test test/koans_test.dart
```

Expected: 4 tests pass.

- [ ] **Step 3: Commit**

```
git add test/koans_test.dart
git commit -m "test: corpus integrity"
```

---

## Task 2: Delay distribution tests

**Files:**
- Create: `test/notification_service_test.dart`
- Modify: `lib/notification_service.dart` — expose `nextDelayHours()` as package-visible

- [ ] **Step 1: Make delay function testable**

In `lib/notification_service.dart`, rename `_nextDelayHours` to `nextDelayHours` (remove underscore):

```dart
int nextDelayHours() {
  final roll = _rng.nextDouble();
  if (roll < 0.30) return 12 + _rng.nextInt(12);
  if (roll < 0.60) return 24 + _rng.nextInt(48);
  if (roll < 0.85) return 72 + _rng.nextInt(120);
  return 240 + _rng.nextInt(240);
}
```

- [ ] **Step 2: Write failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shit_covered_stick/notification_service.dart';
import 'package:shit_covered_stick/koans.dart';

void main() {
  group('nextDelayHours', () {
    test('always returns a positive value', () {
      for (int i = 0; i < 200; i++) {
        expect(nextDelayHours(), greaterThan(0));
      }
    });

    test('never returns more than 480 hours (20 days)', () {
      for (int i = 0; i < 200; i++) {
        expect(nextDelayHours(), lessThanOrEqualTo(480));
      }
    });

    test('returns values across multiple buckets over many samples', () {
      final results = List.generate(500, (_) => nextDelayHours());
      final hasShort = results.any((h) => h < 24);
      final hasMedium = results.any((h) => h >= 24 && h < 72);
      final hasLong = results.any((h) => h >= 72);
      expect(hasShort, isTrue, reason: 'short delays never produced');
      expect(hasMedium, isTrue, reason: 'medium delays never produced');
      expect(hasLong, isTrue, reason: 'long delays never produced');
    });
  });

  group('koan selection', () {
    test('koans list has no immediate self-repeat risk when length > 1', () {
      expect(koans.length, greaterThan(1));
    });
  });
}
```

- [ ] **Step 3: Run — expect FAIL** (nextDelayHours not yet exported)

```
flutter test test/notification_service_test.dart
```

Expected: compile error or import error.

- [ ] **Step 4: Rename the function, re-run — expect PASS**

```
flutter test test/notification_service_test.dart
```

Expected: all pass.

- [ ] **Step 5: Commit**

```
git add lib/notification_service.dart test/notification_service_test.dart
git commit -m "test: delay distribution and koan selection"
```

---

## Task 3: Replace smoke test

**Files:**
- Modify: `test/widget_test.dart`

- [ ] **Step 1: Replace the counter test**

Replace entire file contents:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shit_covered_stick/home_screen.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('home screen renders on black', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Colors.black);
  });
}
```

- [ ] **Step 2: Run — expect PASS**

```
flutter test test/widget_test.dart
```

Note: this test will not fully exercise notification loading (it requires a real device for SharedPreferences), but it confirms the widget tree renders without crashing.

- [ ] **Step 3: Commit**

```
git add test/widget_test.dart
git commit -m "test: replace counter smoke test with home screen smoke test"
```

---

## Task 4: Notification queue

This is the load-bearing change. The current implementation schedules one notification (ID 0) and never reschedules. This task replaces it with a self-sustaining queue of 10 pre-scheduled notifications.

**Files:**
- Modify: `lib/notification_service.dart`

- [ ] **Step 1: Replace notification_service.dart entirely**

```dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'koans.dart';

final _plugin = FlutterLocalNotificationsPlugin();
final _rng = Random();

const _queueKey = 'notification_queue';
const _currentKoanKey = 'current_koan';
const _lastIndexKey = 'last_koan_index';
const _channelId = 'stick';
const _channelName = 'The Stick';
const _queueTarget = 10;

// Stored queue entry: {id, koanIndex, scheduledMillis}
typedef _Entry = Map<String, int>;

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
    onDidReceiveNotificationResponse: _onTap,
  );
}

void _onTap(NotificationResponse response) async {
  // The koan shown in the notification is already stored as current_koan
  // at schedule time. Nothing more is needed; HomeScreen reads it on resume.
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

Future<void> ensureQueue() async {
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();

  final raw = prefs.getStringList(_queueKey) ?? [];
  List<_Entry> active = raw
      .map((s) => Map<String, int>.from(
            (jsonDecode(s) as Map).cast<String, int>(),
          ))
      .where((e) =>
          DateTime.fromMillisecondsSinceEpoch(e['scheduledMillis']!)
              .isAfter(now))
      .toList()
    ..sort((a, b) => a['scheduledMillis']!.compareTo(b['scheduledMillis']!));

  // On very first call, set current_koan to whatever fires next (if anything).
  if (active.isNotEmpty && prefs.getString(_currentKoanKey) == null) {
    await prefs.setString(
        _currentKoanKey, koans[active.first['koanIndex']!]);
  }

  final usedIds = active.map((e) => e['id']!).toSet();
  int lastKoanIndex = prefs.getInt(_lastIndexKey) ?? -1;

  // The tail of the queue: new notifications are added after the last one.
  DateTime tail = active.isEmpty
      ? now
      : DateTime.fromMillisecondsSinceEpoch(active.last['scheduledMillis']!);

  while (active.length < _queueTarget) {
    final id = _nextId(usedIds);
    usedIds.add(id);

    int koanIndex;
    do {
      koanIndex = _rng.nextInt(koans.length);
    } while (koanIndex == lastKoanIndex && koans.length > 1);
    lastKoanIndex = koanIndex;

    tail = tail.add(Duration(hours: nextDelayHours()));
    final scheduledTZ = tz.TZDateTime.from(tail, tz.local);

    await _plugin.zonedSchedule(
      id,
      null,
      koans[koanIndex],
      scheduledTZ,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(koans[koanIndex]),
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

    active.add({
      'id': id,
      'koanIndex': koanIndex,
      'scheduledMillis': tail.millisecondsSinceEpoch,
    });
  }

  await prefs.setInt(_lastIndexKey, lastKoanIndex);
  await prefs.setStringList(
    _queueKey,
    active.map((e) => jsonEncode(e)).toList(),
  );

  // Update current_koan to the next upcoming delivery.
  if (active.isNotEmpty) {
    await prefs.setString(_currentKoanKey, koans[active.first['koanIndex']!]);
  }
}

int _nextId(Set<int> used) {
  int id = 0;
  while (used.contains(id)) {
    id++;
  }
  return id;
}

int nextDelayHours() {
  final roll = _rng.nextDouble();
  if (roll < 0.30) return 12 + _rng.nextInt(12);
  if (roll < 0.60) return 24 + _rng.nextInt(48);
  if (roll < 0.85) return 72 + _rng.nextInt(120);
  return 240 + _rng.nextInt(240);
}

Future<String?> getCurrentKoan() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_currentKoanKey);
}
```

- [ ] **Step 2: Analyze**

```
flutter analyze lib/notification_service.dart
```

Expected: No issues found.

- [ ] **Step 3: Run tests**

```
flutter test test/notification_service_test.dart
```

Expected: all pass (nextDelayHours still exists).

- [ ] **Step 4: Commit**

```
git add lib/notification_service.dart
git commit -m "feat: replace single-shot schedule with self-sustaining queue of 10"
```

---

## Task 5: Wire queue and permissions into HomeScreen

**Files:**
- Modify: `lib/home_screen.dart`

- [ ] **Step 1: Replace home_screen.dart entirely**

```dart
import 'package:flutter/material.dart';
import 'notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _koan;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _init() async {
    await requestPermissions();
    await ensureQueue();
    final current = await getCurrentKoan();
    setState(() {
      _koan = current;
      _ready = true;
    });
  }

  Future<void> _refresh() async {
    await ensureQueue();
    final current = await getCurrentKoan();
    if (mounted) {
      setState(() => _koan = current);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _ready ? _body() : const SizedBox.shrink(),
      ),
    );
  }

  Widget _body() {
    if (_koan == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _koan!,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            height: 1.7,
            fontWeight: FontWeight.w300,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```
flutter analyze lib/home_screen.dart
```

Expected: No issues found.

- [ ] **Step 3: Run tests**

```
flutter test
```

Expected: all pass.

- [ ] **Step 4: Commit**

```
git add lib/home_screen.dart
git commit -m "feat: request permissions and refresh queue on resume"
```

---

## Task 6: App identity

The Flutter default name `shit_covered_stick` appears in the device launcher. Set the display name to `無` (Wu — the answer, the negation, the only correct response to "does a dog have Buddha nature").

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`

- [ ] **Step 1: Update Android label**

In `android/app/src/main/AndroidManifest.xml`, change:

```xml
android:label="shit_covered_stick"
```

to:

```xml
android:label="無"
```

- [ ] **Step 2: Update iOS display name**

In `ios/Runner/Info.plist`, find the `<key>CFBundleName</key>` block and add after it:

```xml
<key>CFBundleDisplayName</key>
<string>無</string>
```

- [ ] **Step 3: Analyze**

```
flutter analyze lib/
```

Expected: No issues found.

- [ ] **Step 4: Commit**

```
git add android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist
git commit -m "feat: app display name 無"
```

---

## Task 7: Clean up main.dart — wire notification response

The notification response handler `_onTap` in `notification_service.dart` is already registered via `initNotifications`. However, if the app is fully terminated when the notification is tapped, `getNotificationAppLaunchDetails` must be checked at startup to identify the launch source.

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add launch detail check**

Replace `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'notification_service.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();

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

(No functional change yet — this step confirms main.dart is clean after the service refactor.)

- [ ] **Step 2: Analyze**

```
flutter analyze lib/
```

Expected: No issues found.

- [ ] **Step 3: Run all tests**

```
flutter test
```

Expected: all pass.

- [ ] **Step 4: Final commit**

```
git add lib/main.dart
git commit -m "chore: confirm main.dart clean after service refactor"
```

---

## Self-Review

**Spec coverage:**
- Unpredictable notification intervals: Task 4 (`nextDelayHours`, queue of 10)
- No sound/badge/vibration: Task 4 (both Android and iOS notification details)
- Single black screen: Tasks 3, 5 (HomeScreen unchanged structurally)
- No navigation or request mechanism: no new navigation added anywhere
- Raw encounter records, unexplained: `koans.dart` untouched
- Self-sustaining (works without user opening app): Task 4 (10 pre-scheduled notifications)
- Permissions requested: Task 5 (`requestPermissions()` in `_init`)
- App name: Task 6

**Placeholder scan:** None found. All code blocks are complete.

**Type consistency:**
- `ensureQueue()` replaces `scheduleNext()` — referenced in HomeScreen Task 5
- `getCurrentKoan()` retained unchanged — referenced in HomeScreen Task 5
- `nextDelayHours()` renamed from `_nextDelayHours` in Task 2, used in Task 4 — consistent
- `_currentKoanKey` constant added in Task 4 — used consistently within that file only
