import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/features/lock_screen/inactivity_lock.dart';

void main() {
  testWidgets('locks after five minutes without activity', (tester) async {
    var locked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: InactivityLock(
          enabled: true,
          onTimeout: () => locked = true,
          child: const Scaffold(body: Text('App content')),
        ),
      ),
    );

    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(locked, isFalse);

    await tester.pump(const Duration(seconds: 1));
    expect(locked, isTrue);
  });

  testWidgets('pointer activity restarts the five-minute timeout', (tester) async {
    var locked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: InactivityLock(
          enabled: true,
          onTimeout: () => locked = true,
          child: const Scaffold(body: Text('App content')),
        ),
      ),
    );

    await tester.pump(const Duration(minutes: 4));
    tester.binding.handlePointerEvent(
      const PointerMoveEvent(
        pointer: 1,
        position: Offset(20, 20),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(locked, isFalse);

    await tester.pump(const Duration(seconds: 1));
    expect(locked, isTrue);
  });

  testWidgets('does not start the timeout while disabled', (tester) async {
    var locked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: InactivityLock(
          enabled: false,
          onTimeout: () => locked = true,
          child: const Scaffold(body: Text('App content')),
        ),
      ),
    );

    await tester.pump(const Duration(minutes: 6));
    expect(locked, isFalse);
  });
}
