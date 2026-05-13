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
