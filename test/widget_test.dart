import 'package:flutter_test/flutter_test.dart';
import 'package:runtracker/main.dart';

void main() {
  testWidgets('home screen shows running metrics and activity modes', (tester) async {
    await tester.pumpWidget(const RunTrackerApp());
    await tester.pumpAndSettle();
    expect(find.text('RUNTRACKER'), findsOneWidget);
    expect(find.text('AFSTAND'), findsOneWidget);
    expect(find.text('DUUR'), findsOneWidget);
    expect(find.text('TEMPO'), findsOneWidget);
    expect(find.text('Hardlopen'), findsOneWidget);
    expect(find.text('Wandelen'), findsOneWidget);
    expect(find.text('Fietsen'), findsOneWidget);
    expect(find.text('START HARDLOPEN'), findsOneWidget);

    await tester.tap(find.text('Wandelen'));
    await tester.pumpAndSettle();
    expect(find.text('START WANDELING'), findsOneWidget);

    await tester.tap(find.text('Fietsen'));
    await tester.pumpAndSettle();
    expect(find.text('START FIETSTOCHT'), findsOneWidget);
  });
}
