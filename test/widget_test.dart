import 'package:flutter_test/flutter_test.dart';
import 'package:runtracker/main.dart';

void main() {
  testWidgets('home screen shows running metrics', (tester) async {
    await tester.pumpWidget(const RunTrackerApp());
    await tester.pumpAndSettle();
    expect(find.text('RUNTRACKER'), findsOneWidget);
    expect(find.text('AFSTAND'), findsOneWidget);
    expect(find.text('DUUR'), findsOneWidget);
    expect(find.text('TEMPO'), findsOneWidget);
    expect(find.text('START TRAINING'), findsOneWidget);
  });
}
