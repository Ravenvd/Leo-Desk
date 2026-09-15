import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('Leo Desk app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const LeoDeskApp());

    expect(find.text('Leo Desk'), findsWidgets);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Customers'), findsOneWidget);
  });
}
