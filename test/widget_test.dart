import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shit_covered_stick/main.dart';
import 'package:shit_covered_stick/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');

  testWidgets('renders koan text on black screen', (WidgetTester tester) async {
    IOSFlutterLocalNotificationsPlugin.registerWith();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (MethodCall call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'requestPermissions':
          return true;
        case 'checkPermissions':
          return <String, Object>{
            'isEnabled': true,
            'isAlertEnabled': true,
            'isBadgeEnabled': false,
            'isSoundEnabled': false,
            'isProvisionalEnabled': false,
            'isCriticalEnabled': false,
          };
        case 'pendingNotificationRequests':
          // Id 0 pending avoids ensureKoanChain restore path (Workmanager not inited in test).
          return <Map<String, Object>?>[
            <String, Object>{'id': 0, 'body': 'Wu.', 'payload': ''},
          ];
        case 'zonedSchedule':
          return null;
        default:
          return null;
      }
    });

    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, null);
    });

    SharedPreferences.setMockInitialValues({
      'current_koan': 'Wu.',
      // Future delivery so ensureKoanChain does not call scheduleNext (no WM in test).
      'next_delivery_epoch_ms':
          DateTime.now().add(const Duration(days: 365)).millisecondsSinceEpoch,
    });
    await initNotifications();
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();
    expect(find.text('Wu.'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
