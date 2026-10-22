import 'package:flutter_test/flutter_test.dart';
import 'package:pulsora/main.dart';

void main() {
  testWidgets('home screen shows running metrics and activity modes', (tester) async {
    await tester.pumpWidget(const PulsoraApp());
    await tester.pumpAndSettle();
    expect(find.text('PULSORA'), findsOneWidget);
    expect(find.text('AFSTAND'), findsOneWidget);
    expect(find.text('DUUR'), findsOneWidget);
    expect(find.text('TEMPO'), findsOneWidget);
    expect(find.text('Hardlopen'), findsOneWidget);
    expect(find.text('Wandelen'), findsOneWidget);
    expect(find.text('Fietsen'), findsOneWidget);
    expect(find.text('START HARDLOPEN'), findsOneWidget);
    expect(find.text('MOVE WITH PURPOSE'), findsOneWidget);

    await tester.tap(find.text('Wandelen'));
    await tester.pumpAndSettle();
    expect(find.text('START WANDELING'), findsOneWidget);

    await tester.tap(find.text('Fietsen'));
    await tester.pumpAndSettle();
    expect(find.text('START FIETSTOCHT'), findsOneWidget);
  });
}
