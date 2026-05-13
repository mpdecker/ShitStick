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
