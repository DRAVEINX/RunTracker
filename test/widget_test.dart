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
    expect(find.text('Zoek op oefening, sessie of notitie…'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('PERSOONLIJKE RECORDS'),
      find.byType(ListView).last,
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();
    expect(find.text('PERSOONLIJKE RECORDS'), findsOneWidget);
  });

  testWidgets('exercise comparison shows latest weight and progress', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pulsora_fitness_history': '[{"date":"2026-01-01T10:00:00.000","exercise":"Leg press","sets":3,"reps":10,"weightKg":20.0,"notes":"","sessionId":"one","sessionName":"Benen"},{"date":"2026-01-08T10:00:00.000","exercise":"Leg press","sets":3,"reps":10,"weightKg":25.5,"notes":"","sessionId":"two","sessionName":"Benen"}]',
    });

    await tester.pumpWidget(const PulsoraApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fitnesslogboek'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('PRESTATIES VERGELIJKEN'),
      find.byType(ListView).last,
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();

    expect(find.text('PRESTATIES VERGELIJKEN'), findsOneWidget);
    expect(find.text('Leg press'), findsAtLeastNWidgets(1));
    // The latest weight is shown in both the comparison card and workout history.
    expect(find.text('25.5 kg'), findsAtLeastNWidgets(1));
    expect(find.text('+5.5 kg'), findsOneWidget);
  });

  testWidgets('exercise comparison updates when another exercise is selected', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pulsora_fitness_history': '[{"date":"2026-01-01T10:00:00.000","exercise":"Bench press","sets":3,"reps":10,"weightKg":30.0,"notes":"","sessionId":"one","sessionName":"Bovenlichaam"},{"date":"2026-01-08T10:00:00.000","exercise":"Bench press","sets":3,"reps":10,"weightKg":35.0,"notes":"","sessionId":"two","sessionName":"Bovenlichaam"},{"date":"2026-01-01T10:00:00.000","exercise":"Leg press","sets":3,"reps":10,"weightKg":20.0,"notes":"","sessionId":"three","sessionName":"Benen"},{"date":"2026-01-08T10:00:00.000","exercise":"Leg press","sets":3,"reps":10,"weightKg":25.5,"notes":"","sessionId":"four","sessionName":"Benen"}]',
    });

    await tester.pumpWidget(const PulsoraApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fitnesslogboek'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('PRESTATIES VERGELIJKEN'),
      find.byType(ListView).last,
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();

    expect(find.text('35.0 kg'), findsAtLeastNWidgets(1));
    expect(find.text('+5.0 kg'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fitness-comparison-exercise')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leg press').last);
    await tester.pumpAndSettle();

    expect(find.text('25.5 kg'), findsAtLeastNWidgets(1));
    expect(find.text('+5.5 kg'), findsOneWidget);
  });
  testWidgets('fitness history search filters sessions and shows empty state', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pulsora_fitness_history': '[{"date":"2026-01-08T10:00:00.000","exercise":"Leg press","sets":3,"reps":10,"weightKg":25.5,"notes":"Rustig tempo","sessionId":"one","sessionName":"Benen"}]',
    });

    await tester.pumpWidget(const PulsoraApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fitnesslogboek'));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('fitness-history-search')),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('fitness-history-search')), 'Benen');
    await tester.pumpAndSettle();
    expect(find.text('Benen'), findsAtLeastNWidgets(1));
    expect(find.text('Geen trainingen gevonden'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('fitness-history-search')), 'Onvindbaar');
    await tester.pumpAndSettle();
    expect(find.text('Geen trainingen gevonden'), findsOneWidget);

    await tester.tap(find.byTooltip('Zoekopdracht wissen'));
    await tester.pumpAndSettle();
    expect(find.text('Geen trainingen gevonden'), findsNothing);
    expect(find.text('Rustig tempo'), findsAtLeastNWidgets(1));

    // Notes are searchable too, not only exercise and session names.
    // Search is case-insensitive and ignores accidental surrounding spaces.
    await tester.enterText(find.byKey(const ValueKey('fitness-history-search')), '  RUSTIG TEMPO  ');
    await tester.pumpAndSettle();
    expect(find.text('Rustig tempo'), findsAtLeastNWidgets(1));
    expect(find.text('Geen trainingen gevonden'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('fitness-history-search')), 'Leg press');
    await tester.pumpAndSettle();
    expect(find.text('Rustig tempo'), findsAtLeastNWidgets(1));
    expect(find.text('Geen trainingen gevonden'), findsNothing);

    // Numeric training details are searchable too (weight, sets and reps).
    await tester.enterText(find.byKey(const ValueKey('fitness-history-search')), '25.5');
    await tester.pumpAndSettle();
    expect(find.text('Rustig tempo'), findsAtLeastNWidgets(1));
    expect(find.text('Geen trainingen gevonden'), findsNothing);

    // Dutch decimal-comma input should find the same weight as decimal-point input.
    await tester.enterText(find.byKey(const ValueKey('fitness-history-search')), '25,5');
    await tester.pumpAndSettle();
    expect(find.text('Rustig tempo'), findsAtLeastNWidgets(1));
    expect(find.text('Geen trainingen gevonden'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('fitness-history-search')), '10');
    await tester.pumpAndSettle();
    expect(find.text('Rustig tempo'), findsAtLeastNWidgets(1));
    expect(find.text('Geen trainingen gevonden'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('fitness-history-search')), '3');
    await tester.pumpAndSettle();
    expect(find.text('Rustig tempo'), findsAtLeastNWidgets(1));
    expect(find.text('Geen trainingen gevonden'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('fitness-history-search')), '2026-01-08');
    await tester.pumpAndSettle();
    expect(find.text('Rustig tempo'), findsAtLeastNWidgets(1));
    expect(find.text('Geen trainingen gevonden'), findsNothing);
  });
}
