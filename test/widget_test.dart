import 'package:flutter_test/flutter_test.dart';

import 'package:leo_desk/main.dart';

void main() {
  testWidgets('Leo Desk app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const LeoDeskApp());

    expect(find.text('Leo Desk'), findsOneWidget);
    expect(find.text('Database initialized successfully'), findsOneWidget);
  });
}