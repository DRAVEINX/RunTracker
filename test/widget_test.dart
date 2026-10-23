import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pulsora/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
    expect(find.byTooltip('Fitnesslogboek'), findsOneWidget);

    await tester.tap(find.text('Wandelen'));
    await tester.pumpAndSettle();
    expect(find.text('START WANDELING'), findsOneWidget);

    await tester.tap(find.text('Fietsen'));
    await tester.pumpAndSettle();
    expect(find.text('START FIETSTOCHT'), findsOneWidget);

    await tester.tap(find.byTooltip('Fitnesslogboek'));
    await tester.pumpAndSettle();
    expect(find.text('STRENGTH STUDIO'), findsOneWidget);
    expect(find.text('Nieuwe trainingssessie'), findsOneWidget);
    expect(find.text('VOLUME PER DAG'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('PRESTATIES VERGELIJKEN'),
      find.byType(ListView).last,
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();
    expect(find.text('PRESTATIES VERGELIJKEN'), findsOneWidget);
    expect(find.text('Volg je gewicht per oefening'), findsOneWidget);
    expect(find.text('Registreer eerst een oefening om je voortgang te vergelijken.'), findsOneWidget);
    expect(find.text('Je eerste training begint hier'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('fitness-history-search')),
      find.byType(ListView).last,
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fitness-history-search')), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('PERSOONLIJKE RECORDS'),
      find.byType(ListView).last,
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();
    expect(find.text('PERSOONLIJKE RECORDS'), findsOneWidget);
  });
}
