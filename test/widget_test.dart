// removed unused import
import 'package:flutter_test/flutter_test.dart';

import 'package:visiongrade/main.dart';

void main() {
  testWidgets('Splash screen shows the VisionGRADE branding and login button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Vision'), findsOneWidget);
    expect(find.text('Grade'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('Selecting instructor opens the reusable login screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Instructor'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome !'), findsOneWidget);
    expect(find.text('Log in to continue'), findsOneWidget);
  });
}
