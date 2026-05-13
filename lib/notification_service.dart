import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'koans.dart';

final _plugin = FlutterLocalNotificationsPlugin();
final _rng = Random();

const _lastIndexKey = 'last_koan_index';
const _channelId = 'stick';
const _channelName = 'The Stick';

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
