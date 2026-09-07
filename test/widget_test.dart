import 'package:flutter_test/flutter_test.dart';

import 'package:leo_desk/main.dart';

void main() {
  testWidgets('Leo Desk app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const LeoDeskApp());

    expect(find.text('Leo Desk'), findsWidgets);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Customers'), findsOneWidget);
  });
}