import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiongrade/loginscreen.dart';

void main() {
  testWidgets('instructor login matches the compact reference layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(298, 662);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen(isInstructor: true)),
    );

    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Remember me'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Forgot your password?'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);

    final emailRect = tester.getRect(find.byType(TextFormField).first);
    final passwordRect = tester.getRect(find.byType(TextFormField).last);
    final loginButtonRect = tester.getRect(find.byType(ElevatedButton));

    expect(emailRect.width, closeTo(268, 2));
    expect(emailRect.height, closeTo(48, 0.1));
    expect(emailRect.top, closeTo(219, 1));
    expect(passwordRect.top - emailRect.bottom, closeTo(12, 0.1));
    expect(loginButtonRect.height, closeTo(37, 0.1));
    expect(loginButtonRect.top, closeTo(379, 1));
    expect(loginButtonRect.top, greaterThan(passwordRect.bottom));
    expect(loginButtonRect.top, lessThan(400));
  });

  testWidgets('validation errors do not resize the login form', (tester) async {
    tester.view.physicalSize = const Size(298, 662);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen(isInstructor: true)),
    );

    final emailField = find.byType(TextFormField).first;
    final passwordField = find.byType(TextFormField).last;
    final button = find.byType(ElevatedButton);
    final initialEmailRect = tester.getRect(emailField);
    final initialPasswordRect = tester.getRect(passwordField);
    final initialButtonRect = tester.getRect(button);

    await tester.tap(find.text('Log in'));
    await tester.pump();

    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    final passwordError = tester.widget<Text>(
      find.text('Password is required'),
    );
    expect(passwordError.style?.fontSize, 11);
    expect(passwordError.style?.color, const Color(0xFFB84C4C));
    expect(tester.getRect(emailField), initialEmailRect);
    expect(tester.getRect(passwordField), initialPasswordRect);
    expect(tester.getRect(button), initialButtonRect);
  });

  testWidgets('failed login marks both fields as errors', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen(isInstructor: true)),
    );

    await tester.enterText(
      find.byType(TextFormField).first,
      'teacher@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'password123');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    final decorators = tester.widgetList<InputDecorator>(
      find.byType(InputDecorator),
    );
    for (final decorator in decorators) {
      final border = decorator.decoration.enabledBorder! as OutlineInputBorder;
      expect(border.borderSide.color, Colors.redAccent);
    }
  });

  testWidgets('instructor and student can show or hide their password', (
    tester,
  ) async {
    for (final isInstructor in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            key: ValueKey(isInstructor),
            isInstructor: isInstructor,
          ),
        ),
      );

      final passwordField = find.byType(EditableText).last;
      expect(tester.widget<EditableText>(passwordField).obscureText, isTrue);
      expect(find.byTooltip('Show password'), findsNothing);

      await tester.enterText(passwordField, 'secret');
      await tester.pump();
      expect(find.byTooltip('Show password'), findsOneWidget);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();

      expect(tester.widget<EditableText>(passwordField).obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);

      await tester.enterText(passwordField, '');
      await tester.pump();
      expect(find.byTooltip('Show password'), findsNothing);
      expect(tester.widget<EditableText>(passwordField).obscureText, isTrue);

      await tester.enterText(passwordField, 'secret');
      await tester.pump();
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(tester.widget<EditableText>(passwordField).obscureText, isTrue);
    }
  });
}
