import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/core/theme/app_theme.dart';
import 'package:leo_desk/features/lock_screen/startup_lock_screen.dart';

void main() {
  testWidgets('does not unlock with an incorrect password', (tester) async {
    var unlocked = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StartupLockScreen(onUnlock: () => unlocked = true),
      ),
    );

    await tester.enterText(find.byType(TextField), '1234');
    await tester.ensureVisible(find.text('Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock'));
    await tester.pump();

    expect(unlocked, isFalse);
    expect(find.text('Incorrect password. Please try again.'), findsOneWidget);
  });

  testWidgets('unlocks with the configured password', (tester) async {
    var unlocked = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StartupLockScreen(onUnlock: () => unlocked = true),
      ),
    );

    await tester.enterText(find.byType(TextField), '2818');
    await tester.ensureVisible(find.text('Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock'));
    await tester.pump();

    expect(unlocked, isTrue);
  });
}
