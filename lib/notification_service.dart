import 'dart:math';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import 'koans.dart';

final _plugin = FlutterLocalNotificationsPlugin();
final _rng = Random();

const _lastIndexKey = 'last_koan_index';
const _nextDeliveryEpochKey = 'next_delivery_epoch_ms';
const _koanNotificationId = 0;
const _channelId = 'stick';
const _channelName = 'The Stick';

/// Grace after [next_delivery_epoch_ms] before assuming Workmanager missed the chain.
const Duration _repairGrace = Duration(minutes: 45);

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await initNotifications();
    await scheduleNext(promptForExactAlarms: false);
    return true;
  });
}

Future<void> initNotifications() async {
  tzdata.initializeTimeZones();

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

NotificationDetails _koanNotificationDetails(String body) {
  return NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      styleInformation: BigTextStyleInformation(body),
      enableLights: false,
      playSound: false,
      enableVibration: false,
    ),
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
    ),
  );
}

Future<bool> _notificationsPermittedForChain() async {
  if (_isAndroid) {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final enabled = await android?.areNotificationsEnabled();
    if (enabled == false) return false;
  } else if (_isIos) {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final opts = await ios?.checkPermissions();
    if (opts != null && !opts.isEnabled && !opts.isProvisionalEnabled) {
      return false;
    }
  }
  return true;
}

/// Re-attach alarm + Workmanager for the persisted koan and [nextDeliveryEpochMs]
/// without advancing the corpus (pending list was cleared but fire time not reached).
Future<void> _rescheduleExistingKoan(int nextDeliveryEpochMs) async {
  final prefs = await SharedPreferences.getInstance();
  final body = prefs.getString('current_koan');
  if (body == null || body.isEmpty) {
    await scheduleNext();
    return;
  }

  final scheduledTime =
      tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, nextDeliveryEpochMs);
  final now = tz.TZDateTime.now(tz.local);
  if (!scheduledTime.isAfter(now)) {
    await scheduleNext();
    return;
  }

  final androidMode = await _resolveAndroidScheduleMode();

  await _plugin.zonedSchedule(
    _koanNotificationId,
    null,
    body,
    scheduledTime,
    _koanNotificationDetails(body),
    androidScheduleMode: androidMode,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
  );

  var delay = scheduledTime.difference(now);
  if (delay < const Duration(seconds: 1)) {
    delay = const Duration(seconds: 1);
  }

  await Workmanager().cancelByUniqueName('koan-chain');
  await Workmanager().registerOneOffTask(
    'koan-chain',
    'scheduleNext',
    initialDelay: delay,
  );
}

/// If the next delivery time has passed and no pending koan notification exists,
/// advance the chain (Workmanager likely did not run).
Future<void> ensureKoanChain() async {
  if (!await _notificationsPermittedForChain()) return;

  final pending = await _plugin.pendingNotificationRequests();
  final hasKoanPending =
      pending.any((PendingNotificationRequest p) => p.id == _koanNotificationId);
  if (hasKoanPending) return;

  final prefs = await SharedPreferences.getInstance();
  final nextMs = prefs.getInt(_nextDeliveryEpochKey);
  final now = DateTime.now().millisecondsSinceEpoch;

  if (nextMs == null) {
    await scheduleNext();
    return;
  }

  if (now < nextMs + _repairGrace.inMilliseconds) {
    await _rescheduleExistingKoan(nextMs);
    return;
  }

  await scheduleNext();
}

Future<AndroidScheduleMode> _resolveAndroidScheduleMode({
  bool promptForExactAlarms = true,
}) async {
  if (!_isAndroid) {
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }
  final android = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (android == null) return AndroidScheduleMode.inexactAllowWhileIdle;

  var can = await android.canScheduleExactNotifications();
  if (can == true) return AndroidScheduleMode.exactAllowWhileIdle;

  if (promptForExactAlarms) {
    await android.requestExactAlarmsPermission();
    can = await android.canScheduleExactNotifications();
    if (can == true) return AndroidScheduleMode.exactAllowWhileIdle;
  }
  return AndroidScheduleMode.inexactAllowWhileIdle;
}

Future<String> scheduleNext({bool promptForExactAlarms = true}) async {
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

  await prefs.setInt(
    _nextDeliveryEpochKey,
    scheduledTime.millisecondsSinceEpoch,
  );

  final androidMode =
      await _resolveAndroidScheduleMode(promptForExactAlarms: promptForExactAlarms);

  await _plugin.zonedSchedule(
    _koanNotificationId,
    null,
    koans[nextIndex],
    scheduledTime,
    _koanNotificationDetails(koans[nextIndex]),
    androidScheduleMode: androidMode,
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
  if (roll < 0.30) return 12 + _rng.nextInt(12); // half a day to a day
  if (roll < 0.60) return 24 + _rng.nextInt(48); // one to three days
  if (roll < 0.85) return 72 + _rng.nextInt(120); // three to eight days
  return 240 + _rng.nextInt(240); // ten to twenty days
}

Future<String?> getCurrentKoan() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('current_koan');
}
