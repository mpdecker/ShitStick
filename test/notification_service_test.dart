import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shit_covered_stick/notification_service.dart';
import 'package:timezone/data/latest.dart' as tzdata;

// scheduleNext() is shared between web and native and branches on kIsWeb
// internally — which is always false under the VM test target, even when
// we're only exercising the web-facing ensureKoanChainWeb() entry point.
// So its native branch (notification scheduling + Workmanager) still runs
// here and needs the same channel mocks widget_test.dart uses for it.
const _notificationsChannel =
    MethodChannel('dexterous.com/flutter/local_notifications');
const _workmanagerChannel =
    MethodChannel('be.tramckrijte.workmanager/foreground_channel_work_manager');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // scheduleNext() reads tz.local; production sets this as a side effect
    // of initNotifications(), which test code never calls.
    tzdata.initializeTimeZones();

    IOSFlutterLocalNotificationsPlugin.registerWith();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notificationsChannel, (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'zonedSchedule':
          return null;
        default:
          return null;
      }
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_workmanagerChannel, (call) async => null);
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notificationsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_workmanagerChannel, null);
  });

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

  group('ensureKoanChainWeb', () {
    test('picks a koan on first launch when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await getCurrentKoan(), isNull);

      await ensureKoanChainWeb();

      expect(await getCurrentKoan(), isNotNull);
    });

    test('keeps the current koan while its delivery time is still in the future', () async {
      final future = DateTime.now().add(const Duration(days: 2));
      SharedPreferences.setMockInitialValues({
        'current_koan': 'Ordinary mind is the way.',
        'next_delivery_epoch_ms': future.millisecondsSinceEpoch,
      });

      await ensureKoanChainWeb();

      expect(await getCurrentKoan(), equals('Ordinary mind is the way.'));
    });

    test('advances to a new koan once the delivery time has passed', () async {
      final past = DateTime.now().subtract(const Duration(days: 2));
      SharedPreferences.setMockInitialValues({
        'current_koan': 'Ordinary mind is the way.',
        'next_delivery_epoch_ms': past.millisecondsSinceEpoch,
      });

      await ensureKoanChainWeb();

      expect(await getCurrentKoan(), isNot(equals('Ordinary mind is the way.')));

      final prefs = await SharedPreferences.getInstance();
      final nextMs = prefs.getInt('next_delivery_epoch_ms');
      expect(nextMs, greaterThan(past.millisecondsSinceEpoch));
    });

    test('re-rolls on a fresh visit even while the delivery time is still in the future', () async {
      final future = DateTime.now().add(const Duration(days: 2));
      SharedPreferences.setMockInitialValues({
        'current_koan': 'Ordinary mind is the way.',
        'next_delivery_epoch_ms': future.millisecondsSinceEpoch,
      });

      await ensureKoanChainWeb(freshVisit: true);

      expect(await getCurrentKoan(), isNot(equals('Ordinary mind is the way.')));

      final prefs = await SharedPreferences.getInstance();
      final nextMs = prefs.getInt('next_delivery_epoch_ms');
      expect(nextMs, greaterThan(DateTime.now().millisecondsSinceEpoch));
    });

    test('never shows the same koan on two consecutive fresh visits', () async {
      SharedPreferences.setMockInitialValues({});
      await ensureKoanChainWeb(freshVisit: true);

      var previous = await getCurrentKoan();
      for (var i = 0; i < 10; i++) {
        await ensureKoanChainWeb(freshVisit: true);
        final current = await getCurrentKoan();
        expect(current, isNot(equals(previous)));
        previous = current;
      }
    });
  });
}
