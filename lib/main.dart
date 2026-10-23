import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const PulsoraApp());

const ink = Color(0xFF080D18);
const panel = Color(0xFF141C2D);
const lime = Color(0xFFB7F56A);
const muted = Color(0xFF9BA8BC);
const violet = Color(0xFF9D8CFF);

class PulsoraApp extends StatelessWidget {
  const PulsoraApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PULSORA',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: ink,
          colorScheme: const ColorScheme.dark(primary: lime, surface: panel),
        ),
        home: const PulsoraHomePage(),
      );
}

class RunRecord {
  const RunRecord(
    this.date,
    this.seconds,
    this.meters,
    this.coordinates, {
    this.activityType = 'hardlopen',
  });

  final String date;
  final int seconds;
  final double meters;
  final List<List<double>> coordinates;
  final String activityType;

  bool get isWalking => activityType == 'wandelen';
  bool get isCycling => activityType == 'fietsen';
  String get activityLabel =>
      isWalking ? 'Wandelen' : (isCycling ? 'Fietsen' : 'Hardlopen');

  Map<String, dynamic> toJson() => {
        'date': date,
        'seconds': seconds,
        'meters': meters,
        'coordinates': coordinates,
        'activityType': activityType,
      };

  factory RunRecord.fromJson(Map<String, dynamic> json) => RunRecord(
        json['date'] as String,
        json['seconds'] as int,
        (json['meters'] as num).toDouble(),
        (json['coordinates'] as List<dynamic>)
            .map((e) => [(e[0] as num).toDouble(), (e[1] as num).toDouble()])
            .toList(),
        activityType: ['hardlopen', 'wandelen', 'fietsen']
                .contains(json['activityType'] as String?)
            ? json['activityType'] as String
            : 'hardlopen',
      );
}

class FitnessRecord {
  const FitnessRecord({
    required this.date,
    required this.exercise,
    required this.sets,
    required this.reps,
    required this.weightKg,
    this.notes = '',
    this.sessionId = '',
    this.sessionName = '',
  });
  final String date;
  final String exercise;
  final int sets;
  final int reps;
  final double weightKg;
  final String notes;
  final String sessionId;
  final String sessionName;

  Map<String, dynamic> toJson() => {
        'date': date,
        'exercise': exercise,
        'sets': sets,
        'reps': reps,
        'weightKg': weightKg,
        'notes': notes,
        'sessionId': sessionId,
        'sessionName': sessionName,
      };

  factory FitnessRecord.fromJson(Map<String, dynamic> json) => FitnessRecord(
        date: json['date'] as String,
        exercise: json['exercise'] as String,
        sets: json['sets'] as int,
        reps: json['reps'] as int,
        weightKg: (json['weightKg'] as num).toDouble(),
        notes: json['notes'] as String? ?? '',
        sessionId: json['sessionId'] as String? ?? '',
        sessionName: json['sessionName'] as String? ?? '',
      );
}

class PulsoraHomePage extends StatefulWidget {
  const PulsoraHomePage({super.key});
  @override
  State<PulsoraHomePage> createState() => _PulsoraHomePageState();
}

class _PulsoraHomePageState extends State<PulsoraHomePage> {
  final MapController mapController = MapController();
  final List<LatLng> route = [];
  final List<RunRecord> history = [];
  StreamSubscription<Position>? gps;
  Timer? timer;
  int elapsed = 0;
  double meters = 0;
  bool running = false;
  bool starting = false;
  bool finishing = false;
  bool resuming = false;
  bool paused = false;
  bool showHistory = false;
  bool showFitness = false;
  final List<FitnessRecord> fitnessHistory = [];
  String status = 'Klaar om te gaan';
  DateTime? startedAt;
  double weeklyGoalKm = 10;
  String historyFilter = 'Alles';
  String activityType = 'hardlopen';
  String fitnessSearch = '';
  String selectedFitnessExercise = '';

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  @override
  void dispose() {
    final subscription = gps;
    gps = null;
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((Object _) {
        // Disposal must complete even if the GPS stream cannot cancel cleanly.
      }));
    }
    timer?.cancel();
    timer = null;
    super.dispose();
  }

  bool isValidRecord(RunRecord record) {
    if (DateTime.tryParse(record.date) == null ||
        record.seconds < 0 ||
        !record.meters.isFinite ||
        record.meters < 0) {
      return false;
    }
    return record.coordinates.every((point) =>
        point.length >= 2 &&
        point[0].isFinite &&
        point[1].isFinite &&
        point[0] >= -90 &&
        point[0] <= 90 &&
        point[1] >= -180 &&
        point[1] <= 180);
  }

  Future<void> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedGoal = prefs.getDouble('runtracker_weekly_goal_km');
      final savedGoal = storedGoal != null &&
              storedGoal.isFinite &&
              storedGoal > 0 &&
              storedGoal <= 500
          ? storedGoal
          : 10.0;
      if (mounted) setState(() => weeklyGoalKm = savedGoal);
      final fitnessValue = prefs.getString('pulsora_fitness_history');
      if (fitnessValue != null) {
        try {
          final decodedFitness = jsonDecode(fitnessValue);
          if (decodedFitness is List<dynamic>) {
            fitnessHistory
              ..clear()
              ..addAll(decodedFitness.whereType<Map<String, dynamic>>().map(FitnessRecord.fromJson)
                .where((r) => r.exercise.trim().isNotEmpty && r.sets > 0 && r.reps > 0 && r.weightKg.isFinite && r.weightKg >= 0).take(300));
          }
        } catch (_) {
          // Fitness history should never block loading existing GPS activities.
        }
      }
      if (mounted) setState(() {});
      final value = prefs.getString('runtracker_history');
      if (value == null) return;
      final decoded = jsonDecode(value);
      if (decoded is! List<dynamic>) {
        throw const FormatException('Ongeldig formaat trainingsgeschiedenis');
      }
      final records = <RunRecord>[];
      var skippedRecords = 0;
      for (final item in decoded) {
        try {
          if (item is! Map<String, dynamic>) {
            skippedRecords++;
            continue;
          }
          final record = RunRecord.fromJson(item);
          if (!isValidRecord(record)) {
            skippedRecords++;
            continue;
          }
          records.add(record);
        } catch (_) {
          skippedRecords++;
        }
      }
      if (mounted) {
        setState(() {
          history
            ..clear()
            ..addAll(records.take(100));
        });
        if (skippedRecords > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$skippedRecords ongeldige training(s) overgeslagen. Andere geldige trainingen zijn geladen.'),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => status = 'Geschiedenis kon niet worden geladen');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opgeslagen trainingen konden niet worden gelezen. Je bestaande gegevens zijn niet overschreven. Controleer de opslagruimte en start de app opnieuw.')),
        );
      }
    }
  }

  Future<void> saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final validRecords = <RunRecord>[];
    final seenRecords = <String>{};
    for (final record in history) {
      if (!isValidRecord(record)) continue;
      final encoded = jsonEncode(record.toJson());
      if (seenRecords.add(encoded)) validRecords.add(record);
    }
    final saved = await prefs.setString(
      'runtracker_history',
      jsonEncode(validRecords.take(100).map((e) => e.toJson()).toList()),
    );
    if (!saved) {
      throw StateError('Trainingsgeschiedenis kon niet worden opgeslagen');
    }
  }

  Future<bool> checkLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return false;
    if (!serviceEnabled) {
      setState(() => status = 'Schakel locatie/GPS in op je telefoon');
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (!mounted) return false;
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (!mounted) return false;
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => status = 'Locatietoestemming is nodig voor GPS-tracking');
      return false;
    }
    return true;
  }

  AndroidSettings settings() => AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: Duration(seconds: 2),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'PULSORA is actief',
          notificationText: 'Je training wordt vastgelegd.',
          enableWakeLock: true,
        ),
      );

  Future<void> startRun() async {
    if (running || starting) return;
    setState(() {
      starting = true;
      status = 'Locatietoestemming controleren…';
    });
    try {
      if (!await checkLocation()) return;
      setState(() {
        route.clear();
        elapsed = 0;
        meters = 0;
        startedAt = DateTime.now();
        starting = false;
        running = true;
        paused = false;
        status = 'GPS-signaal zoeken…';
      });
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && running && !paused) setState(() => elapsed++);
    });
      gps = Geolocator.getPositionStream(locationSettings: settings()).listen(
        acceptPosition,
        onError: (_) => handleGpsError(),
      );
    } catch (_) {
      timer?.cancel();
      timer = null;
      final subscription = gps;
      gps = null;
      try {
        await subscription?.cancel();
      } catch (_) {
        // Keep resetting the run state even if GPS cleanup fails.
      }
      if (mounted) {
        setState(() {
          running = false;
          paused = false;
          starting = false;
          status = 'Training starten is niet gelukt. Controleer GPS en probeer opnieuw.';
        });
      }
    } finally {
      if (mounted && starting) setState(() => starting = false);
    }
  }

  void handleGpsError() {
    if (!mounted || !running) return;
    timer?.cancel();
    timer = null;
    final subscription = gps;
    gps = null;
    setState(() {
      paused = true;
      status = 'GPS niet beschikbaar. Training gepauzeerd; controleer locatie en tik op Hervatten.';
    });
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((Object _) {
        // GPS stream errors must not leave tracking state inconsistent.
      }));
    }
  }

  void acceptPosition(Position p) {
    if (!mounted || !running || paused) return;
    if (!p.latitude.isFinite ||
        !p.longitude.isFinite ||
        p.latitude < -90 ||
        p.latitude > 90 ||
        p.longitude < -180 ||
        p.longitude > 180 ||
        !p.accuracy.isFinite ||
        p.accuracy < 0) {
      setState(() => status = 'Ongeldige GPS-meting genegeerd');
      return;
    }
    if (p.accuracy > 35) {
      setState(() => status = 'GPS-signaal zwak · nauwkeuriger locatie zoeken');
      return;
    }
    final point = LatLng(p.latitude, p.longitude);
    if (route.isNotEmpty) {
      final last = route.last;
      final delta = Geolocator.distanceBetween(
          last.latitude, last.longitude, point.latitude, point.longitude);
      if (delta >= 80) {
        setState(() => status = 'GPS-sprong genegeerd');
        return;
      }
      if (delta > 0) meters += delta;
    }
    setState(() {
      route.add(point);
      status = 'GPS actief · nauwkeurigheid ' + p.accuracy.round().toString() + ' m';
    });
    try {
      mapController.move(point, 16);
    } catch (_) {
      // The map may still be initializing on the first GPS fix.
    }
  }

  Future<void> pauseRun() async {
    if (!running || paused) return;
    setState(() {
      paused = true;
      status = 'Training pauzeren…';
    });
    timer?.cancel();
    timer = null;
    final subscription = gps;
    gps = null;
    try {
      await subscription?.cancel();
    } catch (_) {
      // Cancellation errors must not undo the paused state.
    }
    if (!mounted) return;
    setState(() => status = 'Training gepauzeerd');
  }

  Future<void> resumeRun() async {
    if (!running || !paused || resuming) return;
    resuming = true;
    try {
      if (!await checkLocation()) return;
      final subscription = Geolocator.getPositionStream(
        locationSettings: settings(),
      ).listen(
        acceptPosition,
        onError: (_) => handleGpsError(),
      );
      if (!mounted || !running || !paused) {
        await subscription.cancel();
        return;
      }
      gps = subscription;
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && running && !paused) setState(() => elapsed++);
      });
      setState(() {
        paused = false;
        status = 'GPS hervatten…';
      });
    } catch (_) {
      timer?.cancel();
      timer = null;
      final subscription = gps;
      gps = null;
      try {
        await subscription?.cancel();
      } catch (_) {
        // Keep the run paused even if stream cleanup fails.
      }
      if (mounted) {
        setState(() {
          paused = true;
          status = 'Hervatten is niet gelukt. Probeer het opnieuw.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => resuming = false);
      } else {
        resuming = false;
      }
    }
  }

  Future<void> finishRun() async {
    if (!running || finishing) return;
    setState(() {
      finishing = true;
      running = false;
      paused = false;
      status = 'Training afronden en opslaan…';
    });
    timer?.cancel();
    timer = null;
    try {
      final subscription = gps;
      gps = null;
      try {
        await subscription?.cancel();
      } catch (_) {
        // A GPS cleanup error must not prevent saving the completed run.
      }
      final record = startedAt != null && (elapsed > 0 || meters > 0)
          ? RunRecord(
              startedAt!.toIso8601String(),
              elapsed,
              meters,
              route.map((p) => [p.latitude, p.longitude]).toList(),
              activityType: activityType,
            )
          : null;
      if (record != null) {
        history.insert(0, record);
        if (history.length > 100) history.removeRange(100, history.length);
        try {
          await saveHistory();
          if (mounted) {
            setState(() => status = 'Training opgeslagen op dit apparaat');
          }
        } catch (_) {
          if (mounted) {
            setState(() => status = 'Training afgerond, maar opslaan is mislukt');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Training afgerond, maar opslaan is mislukt. De training blijft voorlopig in de lijst staan.'),
                duration: const Duration(seconds: 8),
                action: SnackBarAction(
                  label: 'Opnieuw proberen',
                  onPressed: () async {
                    try {
                      await saveHistory();
                      if (!mounted) return;
                      setState(() => status = 'Training alsnog opgeslagen');
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Training alsnog opgeslagen')),
                      );
                    } catch (_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Opslaan is opnieuw mislukt. Controleer de opslagruimte en probeer het nogmaals.')),
                      );
                    }
                  },
                ),
              ),
            );
          }
        }
      } else if (mounted) {
        setState(() => status = 'Training afgerond');
      }
    } finally {
      if (mounted) {
        setState(() => finishing = false);
      } else {
        finishing = false;
      }
    }
  }


  Future<void> saveFitnessHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString('pulsora_fitness_history', jsonEncode(fitnessHistory.take(300).map((r) => r.toJson()).toList()));
    if (!saved) throw StateError('Fitnessgeschiedenis kon niet worden opgeslagen');
  }

  Future<void> addFitnessRecord() async {
    final sessionName = TextEditingController(text: 'Krachttraining');
    final exercises = <Map<String, TextEditingController>>[
      _newExerciseControllers(),
    ];
    String? validationMessage;
    final sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    final date = DateTime.now().toIso8601String();

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, refreshDialog) => AlertDialog(
          backgroundColor: panel,
          title: const Text('Nieuwe trainingssessie'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: sessionName,
                    decoration: const InputDecoration(labelText: 'Naam van de training', hintText: 'Bijv. Benen en core'),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(exercises.length, (index) {
                    final item = exercises[index];
                    return Container(
                      key: ValueKey('exercise-$index'),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ink,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF29344A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(child: Text('Oefening ${index + 1}', style: const TextStyle(color: lime, fontWeight: FontWeight.w800))),
                            if (exercises.length > 1)
                              IconButton(
                                tooltip: 'Oefening verwijderen',
                                onPressed: () {
                                  final removed = exercises.removeAt(index);
                                  for (final controller in removed.values) { controller.dispose(); }
                                  refreshDialog(() => validationMessage = null);
                                },
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                          ]),
                          TextField(controller: item['exercise'], decoration: const InputDecoration(labelText: 'Oefening', hintText: 'Bijv. leg press')),
                          Row(children: [
                            Expanded(child: TextField(controller: item['sets'], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sets'))),
                            const SizedBox(width: 10),
                            Expanded(child: TextField(controller: item['reps'], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Herhalingen'))),
                          ]),
                          TextField(controller: item['weight'], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Gewicht (kg)', helperText: '0 = lichaamsgewicht of geen extra gewicht')),
                          TextField(controller: item['notes'], maxLines: 2, decoration: const InputDecoration(labelText: 'Notitie (optioneel)')),
                        ],
                      ),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        if (exercises.length >= 20) {
                          refreshDialog(() => validationMessage = 'Je kunt maximaal 20 oefeningen per sessie toevoegen.');
                          return;
                        }
                        refreshDialog(() {
                          exercises.add(_newExerciseControllers());
                          validationMessage = null;
                        });
                      },
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Oefening toevoegen'),
                    ),
                  ),
                  if (validationMessage != null)
                    Align(alignment: Alignment.centerLeft, child: Text(validationMessage!, style: const TextStyle(color: Colors.orangeAccent))),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuleren')),
            FilledButton(
              onPressed: () {
                if (sessionName.text.trim().isEmpty) {
                  refreshDialog(() => validationMessage = 'Vul een naam voor de training in.');
                  return;
                }
                for (var i = 0; i < exercises.length; i++) {
                  final item = exercises[i];
                  final name = item['exercise']!.text.trim();
                  final setCount = int.tryParse(item['sets']!.text.trim());
                  final repCount = int.tryParse(item['reps']!.text.trim());
                  final kg = double.tryParse(item['weight']!.text.trim().replaceAll(',', '.'));
                  if (name.isEmpty || setCount == null || setCount < 1 || setCount > 100 ||
                      repCount == null || repCount < 1 || repCount > 1000 ||
                      kg == null || !kg.isFinite || kg < 0 || kg > 2000) {
                    refreshDialog(() => validationMessage = 'Controleer oefening ${i + 1}: naam, sets, herhalingen en gewicht.');
                    return;
                  }
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Sessie opslaan'),
            ),
          ],
        ),
      ),
    );

    if (accepted == true && mounted) {
      final name = sessionName.text.trim();
      final records = exercises.map((item) => FitnessRecord(
        date: date,
        exercise: item['exercise']!.text.trim(),
        sets: int.parse(item['sets']!.text.trim()),
        reps: int.parse(item['reps']!.text.trim()),
        weightKg: double.parse(item['weight']!.text.trim().replaceAll(',', '.')),
        notes: item['notes']!.text.trim(),
        sessionId: sessionId,
        sessionName: name,
      )).toList();
      setState(() {
        fitnessHistory.insertAll(0, records);
        if (fitnessHistory.length > 300) fitnessHistory.removeRange(300, fitnessHistory.length);
      });
      try {
        await saveFitnessHistory();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${records.length} oefening(en) opgeslagen in "$name"')),
          );
        }
      } catch (_) {
        if (!mounted) return;
        setState(() => fitnessHistory.removeWhere((record) => record.sessionId == sessionId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opslaan is niet gelukt. Controleer de opslagruimte en probeer opnieuw.')),
        );
      }
    }

    sessionName.dispose();
    for (final item in exercises) {
      for (final controller in item.values) { controller.dispose(); }
    }
  }

  Map<String, TextEditingController> _newExerciseControllers() => {
        'exercise': TextEditingController(),
        'sets': TextEditingController(text: '3'),
        'reps': TextEditingController(text: '10'),
        'weight': TextEditingController(text: '0'),
        'notes': TextEditingController(),
      };

  Future<void> deleteFitnessRecord(FitnessRecord record) async {
    final index = fitnessHistory.indexOf(record);
    if (index < 0) return;
    setState(() => fitnessHistory.removeAt(index));
    try { await saveFitnessHistory(); } catch (_) {
      if (!mounted) return;
      setState(() => fitnessHistory.insert(index.clamp(0, fitnessHistory.length), record));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verwijderen is niet opgeslagen; de training is teruggezet.')));
    }
  }

  Widget fitnessView() {
    final totalVolume = fitnessHistory.fold<double>(0, (sum, r) => sum + r.sets * r.reps * r.weightKg);
    final exercises = fitnessHistory.map((r) => r.exercise.toLowerCase()).toSet().length;
    final now = DateTime.now();
    final dailyVolume = List<double>.generate(7, (index) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: 6 - index));
      return fitnessHistory.where((r) {
        final date = DateTime.tryParse(r.date)?.toLocal();
        return date != null && date.year == day.year && date.month == day.month && date.day == day.day;
      }).fold<double>(0, (sum, r) => sum + r.sets * r.reps * r.weightKg);
    });
    final maxDailyVolume = dailyVolume.fold<double>(0, (max, value) => value > max ? value : max);
    final personalRecords = <String, double>{};
    for (final record in fitnessHistory) {
      final key = record.exercise.trim();
      final previous = personalRecords[key];
      if (previous == null || record.weightKg > previous) personalRecords[key] = record.weightKg;
    }
    final sortedRecords = personalRecords.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final exerciseNames = fitnessHistory
        .map((record) => record.exercise.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final comparisonExercise = exerciseNames.contains(selectedFitnessExercise)
        ? selectedFitnessExercise
        : (exerciseNames.isEmpty ? '' : exerciseNames.first);
    final comparisonRecords = fitnessHistory
        .where((record) => record.exercise.trim() == comparisonExercise)
        .toList()
      ..sort((a, b) => (DateTime.tryParse(a.date) ?? DateTime(1970))
          .compareTo(DateTime.tryParse(b.date) ?? DateTime(1970)));
    final latestComparison = comparisonRecords.isEmpty ? null : comparisonRecords.last;
    final firstComparison = comparisonRecords.isEmpty ? null : comparisonRecords.first;
    final weightChange = latestComparison == null || firstComparison == null
        ? 0.0
        : latestComparison.weightKg - firstComparison.weightKg;
    final filteredFitnessHistory = <FitnessRecord>[];
    final groupedFitnessHistory = <String, List<FitnessRecord>>{};
    for (var index = 0; index < fitnessHistory.length; index++) {
      final record = fitnessHistory[index];
      final matchesSearch = record.exercise.toLowerCase().contains(fitnessSearch) ||
          record.sessionName.toLowerCase().contains(fitnessSearch) ||
          record.notes.toLowerCase().contains(fitnessSearch);
      if (!matchesSearch) continue;
      filteredFitnessHistory.add(record);
      // Old records without a session ID remain separate instead of being merged accidentally.
      final groupKey = record.sessionId.isNotEmpty ? 'session:${record.sessionId}' : 'legacy:$index';
      groupedFitnessHistory.putIfAbsent(groupKey, () => <FitnessRecord>[]).add(record);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 28), children: [
      Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF263654), Color(0xFF1A2238), Color(0xFF352B58)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white.withValues(alpha: .08))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('STRENGTH STUDIO', style: TextStyle(color: lime, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          const Text('Elke herhaling telt.', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, height: 1.1)),
          const SizedBox(height: 8),
          const Text('Leg sets, herhalingen en gewicht vast. Bekijk later wat je eerder hebt gedaan.', style: TextStyle(color: Color(0xFFD0D8E8), height: 1.4)),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: lime, foregroundColor: ink, padding: const EdgeInsets.symmetric(vertical: 15)),
            onPressed: addFitnessRecord, icon: const Icon(Icons.add_rounded),
            label: const Text('Nieuwe trainingssessie', style: TextStyle(fontWeight: FontWeight.w900)))),
        ])),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _statCard('LOGBOEK', '${fitnessHistory.length}', 'registraties', Icons.fitness_center_rounded)),
        const SizedBox(width: 10),
        Expanded(child: _statCard('OEFENINGEN', '$exercises', 'verschillend', Icons.bolt_rounded)),
      ]),
      const SizedBox(height: 10),
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF29344A))),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: violet.withValues(alpha: .16), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.insights_rounded, color: violet)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('TOTAAL VOLUME', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${totalVolume.toStringAsFixed(0)} kg · sets × herhalingen × gewicht', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ])),
        ])),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF29344A))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('VOLUME PER DAG', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Laatste 7 dagen', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 14),
          SizedBox(height: 94, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: List.generate(7, (index) {
            final value = dailyVolume[index];
            final fraction = maxDailyVolume <= 0 ? 0.0 : value / maxDailyVolume;
            final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: 6 - index));
            const labels = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
            return Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Expanded(child: Align(alignment: Alignment.bottomCenter, child: Container(
                width: double.infinity,
                height: value <= 0 ? 4 : (12 + fraction * 48),
                decoration: BoxDecoration(
                  color: value <= 0 ? const Color(0xFF303B50) : lime,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                ),
              ))),
              const SizedBox(height: 7),
              Text(labels[day.weekday - 1], style: const TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w700)),
            ])));
          }))),
          const SizedBox(height: 8),
          Text(maxDailyVolume <= 0 ? 'Voeg een training toe om je voortgang te zien.' : 'Hoogste dagvolume: ${maxDailyVolume.toStringAsFixed(0)} kg', style: const TextStyle(color: muted, fontSize: 11)),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF29344A))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('PERSOONLIJKE RECORDS', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (sortedRecords.isEmpty)
            const Text('Je records verschijnen hier zodra je oefeningen vastlegt.', style: TextStyle(color: muted, fontSize: 12))
          else
            ...sortedRecords.take(5).map((entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                const Icon(Icons.emoji_events_outlined, color: lime, size: 19),
                const SizedBox(width: 8),
                Expanded(child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('${entry.value.toStringAsFixed(1)} kg', style: const TextStyle(color: lime, fontWeight: FontWeight.w900)),
              ]),
            )),
        ]),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF29344A))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('PRESTATIES VERGELIJKEN', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Volg je gewicht per oefening', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (exerciseNames.isEmpty)
            const Text('Registreer eerst een oefening om je voortgang te vergelijken.', style: TextStyle(color: muted, fontSize: 12))
          else ...[
            DropdownButtonFormField<String>(
              key: const ValueKey('fitness-comparison-exercise'),
              value: comparisonExercise,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Kies een oefening',
                filled: true,
                fillColor: ink,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              items: exerciseNames.map((name) => DropdownMenuItem<String>(value: name, child: Text(name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (value) {
                if (value != null) setState(() => selectedFitnessExercise = value);
              },
            ),
            const SizedBox(height: 12),
            if (latestComparison != null && firstComparison != null)
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('LAATSTE GEWICHT', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text('${latestComparison.weightKg.toStringAsFixed(1)} kg', style: const TextStyle(color: lime, fontSize: 22, fontWeight: FontWeight.w900)),
                ])),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('VERSCHIL', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text('${weightChange > 0 ? '+' : ''}${weightChange.toStringAsFixed(1)} kg', style: TextStyle(color: weightChange >= 0 ? lime : const Color(0xFFFF9A8A), fontSize: 22, fontWeight: FontWeight.w900)),
                  Text('eerste → laatste registratie', style: const TextStyle(color: muted, fontSize: 10)),
                ])),
              ]),
            const SizedBox(height: 12),
            ...comparisonRecords.reversed.take(5).toList().reversed.map((record) {
              final date = DateTime.tryParse(record.date)?.toLocal();
              final label = date == null ? 'Datum onbekend' : '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}';
              final maxWeight = comparisonRecords.fold<double>(0, (max, item) => item.weightKg > max ? item.weightKg : max);
              final fraction = maxWeight <= 0 ? 0.0 : (record.weightKg / maxWeight).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 42, child: Text(label, style: const TextStyle(color: muted, fontSize: 11))),
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: fraction, minHeight: 8, backgroundColor: const Color(0xFF303B50), color: violet),
                  )),
                  const SizedBox(width: 10),
                  SizedBox(width: 58, child: Text('${record.weightKg.toStringAsFixed(1)} kg', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
                ]),
              );
            }),
          ],
        ]),
      ),
      const SizedBox(height: 24),
      const Text('JOUW FITNESSLOGBOEK', style: TextStyle(color: muted, fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      TextField(
        key: const ValueKey('fitness-history-search'),
        onChanged: (value) => setState(() => fitnessSearch = value.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Zoek op oefening, sessie of notitie…',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: fitnessSearch.isEmpty ? null : IconButton(
            tooltip: 'Zoekopdracht wissen',
            onPressed: () => setState(() => fitnessSearch = ''),
            icon: const Icon(Icons.close_rounded),
          ),
          filled: true,
          fillColor: panel,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 10),
      if (fitnessHistory.isEmpty)
        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF29344A))),
          child: const Column(children: [
            Icon(Icons.sports_gymnastics_rounded, color: violet, size: 42), SizedBox(height: 12),
            Text('Je eerste training begint hier', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), SizedBox(height: 6),
            Text('Voeg een oefening toe en bekijk later gewicht, sets en herhalingen.', textAlign: TextAlign.center, style: TextStyle(color: muted, height: 1.4)),
          ]))
      else if (filteredFitnessHistory.isEmpty)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF29344A))),
          child: const Column(children: [
            Icon(Icons.search_off_rounded, color: muted, size: 36),
            SizedBox(height: 10),
            Text('Geen trainingen gevonden', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            SizedBox(height: 6),
            Text('Probeer een andere zoekterm voor je oefening, sessie of notitie.', textAlign: TextAlign.center, style: TextStyle(color: muted, height: 1.4)),
          ]),
        )
      else
        ...groupedFitnessHistory.entries.map((entry) {
          final records = entry.value;
          final first = records.first;
          final date = DateTime.tryParse(first.date)?.toLocal();
          final dateText = date == null ? 'Datum onbekend' : '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
          final sessionVolume = records.fold<double>(0, (sum, r) => sum + r.sets * r.reps * r.weightKg);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF29344A))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: violet.withValues(alpha: .15), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.fitness_center_rounded, color: violet)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(first.sessionName.isNotEmpty ? first.sessionName : first.exercise, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(dateText, style: const TextStyle(color: muted, height: 1.45, fontSize: 12)),
                    const SizedBox(height: 3),
                    Text('${records.length} oefening(en) · volume ${sessionVolume.toStringAsFixed(0)} kg', style: const TextStyle(color: lime, fontSize: 12, fontWeight: FontWeight.w800)),
                  ])),
                ]),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFF29344A)),
                const SizedBox(height: 6),
                ...records.map((record) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.bolt_rounded, color: lime, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(record.exercise, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('${record.sets} sets × ${record.reps} herhalingen · ${record.weightKg.toStringAsFixed(1)} kg', style: const TextStyle(color: muted, fontSize: 12)),
                      if (record.notes.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(record.notes, style: const TextStyle(color: Color(0xFFD0D8E8), fontSize: 12)),
                      ],
                    ])),
                    IconButton(
                      tooltip: 'Oefening verwijderen',
                      onPressed: () => deleteFitnessRecord(record),
                      icon: const Icon(Icons.delete_outline_rounded, color: muted),
                    ),
                  ]),
                )),
              ]),
            ),
          );
        }),
    ]);
  }

  Future<void> editWeeklyGoal() async {
    final controller = TextEditingController(text: weeklyGoalKm.toStringAsFixed(1));
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Weekdoel instellen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Afstand per week (km)',
            helperText: 'Kies een haalbaar doel, bijvoorbeeld 10 km.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim().replaceAll(',', '.'));
              if (parsed != null && parsed > 0 && parsed <= 500) {
                Navigator.pop(dialogContext, parsed);
              }
            },
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setDouble('runtracker_weekly_goal_km', value);
      if (!saved) throw StateError('Weekdoel kon niet worden opgeslagen');
      if (!mounted) return;
      setState(() => weeklyGoalKm = value);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weekdoel opgeslagen')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weekdoel opslaan is niet gelukt. Probeer het opnieuw.')),
      );
    }
  }

  Future<void> exportHistoryCsv() async {
    if (history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Er zijn nog geen trainingen om te exporteren')),
      );
      return;
    }
    final rows = <String>[
      'Activiteit;Datum;Duur_seconden;Afstand_meter;Tempo_per_km;Gemiddelde_snelheid_km_per_uur;GPS_route;GPS_punten',
      ...history.map((run) {
        final date = DateTime.tryParse(run.date)?.toLocal().toIso8601String() ?? run.date;
        final averageSpeed = run.seconds > 0 ? (run.meters / run.seconds * 3.6).toStringAsFixed(1) : '';
        final hasRoute = run.coordinates.isEmpty ? 'nee' : 'ja';
        return '${run.activityLabel};${date};${run.seconds};${run.meters.toStringAsFixed(1)};${paceFor(run.meters, run.seconds)};${averageSpeed};${hasRoute};${run.coordinates.length}';
      }),
    ];
    try {
      final directory = await getTemporaryDirectory();
      final file = File(directory.path + '/pulsora-trainingen-' + DateTime.now().millisecondsSinceEpoch.toString() + '.csv');
      await file.writeAsString('\uFEFF' + rows.join('\n'), flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        text: 'Trainingsgeschiedenis geëxporteerd vanuit PULSORA',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV exporteren is niet gelukt. Probeer het opnieuw.')),
        );
      }
    }
  }

  String runSummaryText(RunRecord run) {
    final date = DateTime.tryParse(run.date);
    final dateText = date == null
        ? 'Datum onbekend'
        : date.day.toString().padLeft(2, '0') + '-' +
            date.month.toString().padLeft(2, '0') + '-' + date.year.toString();
    return [
      'PULSORA - trainingssamenvatting',
      'Activiteit: ${run.activityLabel}',
      'Datum: $dateText',
      'Afstand: ${(run.meters / 1000).toStringAsFixed(2)} km',
      'Duur: ${clock(run.seconds)}',
      'Tempo: ${paceFor(run.meters, run.seconds)} min/km',
      'Gemiddelde snelheid: ${run.seconds > 0 ? (run.meters / run.seconds * 3.6).toStringAsFixed(1) + ' km/u' : 'niet beschikbaar'}',
      'GPS-route: ${run.coordinates.isEmpty ? 'niet beschikbaar' : 'beschikbaar'}',
      'GPS-punten: ${run.coordinates.length}',
    ].join('\\n');
  }

  Future<void> shareRunSummary(RunRecord run) async {
    try {
      await Share.share(runSummaryText(run), subject: 'PULSORA trainingssamenvatting');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trainingssamenvatting delen is niet gelukt. Probeer het opnieuw.')),
        );
      }
    }
  }

  Future<void> copyRunSummary(RunRecord run) async {
    try {
      await Clipboard.setData(ClipboardData(text: runSummaryText(run)));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trainingssamenvatting gekopieerd')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Samenvatting kopiëren is niet gelukt. Probeer het opnieuw.')),
        );
      }
    }
  }

  Future<void> exportRunGpx(RunRecord run) async {
    if (run.coordinates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deze training bevat geen GPS-route om te exporteren')),
      );
      return;
    }
    try {
      final validCoordinates = run.coordinates.where((point) =>
          point.length >= 2 &&
          point[0].isFinite &&
          point[1].isFinite &&
          point[0] >= -90 &&
          point[0] <= 90 &&
          point[1] >= -180 &&
          point[1] <= 180).toList();
      if (validCoordinates.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Deze training bevat geen geldige GPS-punten om te exporteren')),
          );
        }
        return;
      }
      final points = validCoordinates.map((point) =>
          '      <trkpt lat="${point[0]}" lon="${point[1]}"></trkpt>').join('\n');
      final date = DateTime.tryParse(run.date)?.toUtc().toIso8601String();
      final gpx = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<gpx version="1.1" creator="PULSORA" xmlns="http://www.topografix.com/GPX/1/1">',
        '  <trk>',
        '    <name>PULSORA ${run.activityLabel.toLowerCase()}</name>',
        if (date != null) '    <time>$date</time>',
        '    <trkseg>',
        points,
        '    </trkseg>',
        '  </trk>',
        '</gpx>',
      ].join('\n');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/pulsora-${DateTime.now().millisecondsSinceEpoch}.gpx');
      await file.writeAsString(gpx, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/gpx+xml')],
        text: 'GPS-route geëxporteerd vanuit PULSORA',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPX exporteren is niet gelukt. Probeer het opnieuw.')),
        );
      }
    }
  }

  Future<void> deleteRun(RunRecord run) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Training verwijderen?'),
        content: const Text('Deze training en de bijbehorende opgeslagen GPS-route worden van dit apparaat verwijderd.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuleren')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final originalIndex = history.indexOf(run);
    if (originalIndex < 0) return;
    setState(() => history.removeAt(originalIndex));
    try {
      await saveHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Training verwijderd')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          final restoreIndex = originalIndex.clamp(0, history.length);
          history.insert(restoreIndex, run);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verwijderen is niet opgeslagen. De training is teruggezet in de lijst. Controleer de opslagruimte en probeer opnieuw.')),
        );
      }
    }
  }

  String clock(int value) {
    final h = value ~/ 3600;
    final m = (value % 3600) ~/ 60;
    final s = value % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return h.toString().padLeft(2, '0') + ':' + mm + ':' + ss;
    return mm + ':' + ss;
  }

  String paceFor(double distance, int seconds) {
    if (distance < 20 || seconds == 0) return '--:--';
    final value = (seconds / (distance / 1000)).round();
    if (value >= 3600) return '--:--';
    return (value ~/ 60).toString().padLeft(2, '0') +
        ':' + (value % 60).toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    final center = route.isEmpty ? const LatLng(52.0907, 5.1214) : route.last;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 12), child: Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [lime, Color(0xFF8BE5C2)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(17),
              boxShadow: [BoxShadow(color: lime.withValues(alpha: .16), blurRadius: 18, offset: const Offset(0, 5))]),
              child: const Icon(Icons.bolt_rounded, color: ink, size: 29)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PULSORA', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2.3)),
              Text('MOVE WITH PURPOSE', style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1.7, fontWeight: FontWeight.w800)),
            ])),
            if (showHistory) IconButton(tooltip: 'Trainingsgegevens exporteren', onPressed: exportHistoryCsv, icon: const Icon(Icons.ios_share_rounded, color: lime)),
            IconButton(tooltip: showFitness ? 'Terug naar sporten' : 'Fitnesslogboek',
              onPressed: () => setState(() { showFitness = !showFitness; showHistory = false; }),
              style: IconButton.styleFrom(backgroundColor: showFitness ? violet.withValues(alpha: .18) : panel),
              icon: Icon(Icons.fitness_center_rounded, color: showFitness ? violet : muted)),
            const SizedBox(width: 4),
            IconButton(tooltip: showHistory ? 'Terug naar sporten' : 'Trainingsgeschiedenis',
              onPressed: () => setState(() { showHistory = !showHistory; showFitness = false; }),
              style: IconButton.styleFrom(backgroundColor: showHistory ? lime.withValues(alpha: .16) : panel),
              icon: Icon(showHistory ? Icons.close_rounded : Icons.history_rounded, color: showHistory ? lime : muted)),
          ])),
          Expanded(child: showFitness ? fitnessView() : (showHistory ? historyView() : runView(center))),
        ]),
      ),
    );
  }

  Widget runView(LatLng center) => Column(children: [
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(children: [
                FlutterMap(
                  mapController: mapController,
                  options: MapOptions(initialCenter: center, initialZoom: 13),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.draveinx.runtracker',
                    ),
                    if (route.length > 1)
                      PolylineLayer(polylines: [
                        Polyline(points: route, color: lime, strokeWidth: 5),
                      ]),
                    if (route.isNotEmpty)
                      MarkerLayer(markers: [
                        Marker(
                          point: route.last, width: 22, height: 22,
                          child: Container(
                            decoration: BoxDecoration(color: lime, shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3)),
                          ),
                        ),
                      ]),
                    const RichAttributionWidget(
                      attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
                    ),
                  ],
                ),
                Positioned(
                  top: 14, left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                    decoration: BoxDecoration(color: ink.withValues(alpha: .92), borderRadius: BorderRadius.circular(30)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(
                          color: running && !paused ? lime : muted, shape: BoxShape.circle)),
                      const SizedBox(width: 7),
                      Text(running ? (paused ? 'GEPAUZEERD' : 'LIVE GPS') : 'ROUTEKAART',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                    ]),
                  ),
                ),
                Positioned(
                  right: 12, bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'centerMap',
                    backgroundColor: panel, foregroundColor: lime,
                    onPressed: route.isEmpty ? null : () => mapController.move(route.last, 16),
                    child: const Icon(Icons.my_location_rounded),
                  ),
                ),
              ]),
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(children: [
              if (!running && !starting && !finishing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        avatar: const Icon(Icons.directions_run_rounded, size: 18),
                        label: const Text('Hardlopen'),
                        selected: activityType == 'hardlopen',
                        onSelected: (_) => setState(() => activityType = 'hardlopen'),
                        selectedColor: lime,
                        labelStyle: TextStyle(
                          color: activityType == 'hardlopen' ? ink : Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.directions_walk_rounded, size: 18),
                        label: const Text('Wandelen'),
                        selected: activityType == 'wandelen',
                        onSelected: (_) => setState(() => activityType = 'wandelen'),
                        selectedColor: lime,
                        labelStyle: TextStyle(
                          color: activityType == 'wandelen' ? ink : Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.directions_bike_rounded, size: 18),
                        label: const Text('Fietsen'),
                        selected: activityType == 'fietsen',
                        onSelected: (_) => setState(() => activityType = 'fietsen'),
                        selectedColor: lime,
                        labelStyle: TextStyle(
                          color: activityType == 'fietsen' ? ink : Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),

              Row(children: [
                Expanded(child: metric('AFSTAND', (meters / 1000).toStringAsFixed(2), 'KM')),
                Container(width: 1, height: 60, color: const Color(0xFF25343B)),
                Expanded(child: metric('DUUR', clock(elapsed), '')),
                Container(width: 1, height: 60, color: const Color(0xFF25343B)),
                Expanded(child: metric('TEMPO', paceFor(meters, elapsed), '/KM')),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(child: smallMetric(Icons.speed_rounded, 'Snelheid',
                    meters < 10 || elapsed == 0 ? '--' : (meters / elapsed * 3.6).toStringAsFixed(1) + ' km/u')),
                const SizedBox(width: 10),
                Expanded(child: smallMetric(Icons.my_location_rounded, 'GPS-punten', route.length.toString())),
              ]),
              const SizedBox(height: 10),
              Text(status, textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 11)),
              const SizedBox(height: 14),
              Row(children: [
                if (!running)
                  Expanded(child: action(finishing ? 'OPSLAAN…' : (starting ? 'GPS CONTROLEREN…' : (activityType == 'wandelen' ? 'START WANDELING' : (activityType == 'fietsen' ? 'START FIETSTOCHT' : 'START HARDLOPEN'))), Icons.play_arrow_rounded, startRun, disabled: starting || finishing))
                else if (!paused) ...[
                  Expanded(child: action('PAUZE', Icons.pause_rounded, pauseRun, secondary: true)),
                  const SizedBox(width: 10),
                  Expanded(child: action('AFRONDEN', Icons.stop_rounded, finishRun)),
                ] else ...[
                  Expanded(child: action(resuming ? 'GPS HERVATTEN…' : 'VERDER', Icons.play_arrow_rounded, resumeRun, disabled: resuming)),
                  const SizedBox(width: 10),
                  Expanded(child: action('AFRONDEN', Icons.stop_rounded, finishRun, secondary: true, disabled: resuming)),
                ],
              ]),
            ]),
          ),
        ),
      ]);

  Widget metric(String label, String value, String unit) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(children: [
          Text(label, style: const TextStyle(color: muted, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800))),
          if (unit.isNotEmpty) Text(unit, style: const TextStyle(color: lime, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ]),
      );

  Widget smallMetric(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF25343B))),
        child: Row(children: [
          Icon(icon, color: lime, size: 18),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: muted, fontSize: 10)),
            const SizedBox(height: 3),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ])),
        ]),
      );

  Widget action(String label, IconData icon, Future<void> Function() callback, {bool secondary = false, bool disabled = false}) =>
      SizedBox(height: 54, child: FilledButton.icon(
        onPressed: disabled ? null : () => callback(),
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: .8)),
        style: FilledButton.styleFrom(
          backgroundColor: secondary ? panel : lime,
          foregroundColor: secondary ? Colors.white : ink,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ));

  Widget _statCard(String label, String value, String unit, IconData icon) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF25343B))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: lime, size: 19),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
          Text(unit, style: const TextStyle(color: lime, fontSize: 10, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(color: muted, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
        ]),
      );

  void showRunDetails(RunRecord run) {
    final points = run.coordinates.map((p) => LatLng(p[0], p[1])).toList();
    final center = points.isEmpty ? const LatLng(52.0907, 5.1214) : points[points.length ~/ 2];
    final detailMapController = MapController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ink,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.82,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(run.activityLabel.toUpperCase() + ' · DETAILS', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.5))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ]),
              const SizedBox(height: 12),
              Expanded(
                flex: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: points.isEmpty
                      ? const Center(child: Text('Voor deze training is geen GPS-route opgeslagen.', textAlign: TextAlign.center, style: TextStyle(color: muted)))
                      : FlutterMap(
                          mapController: detailMapController,
                          options: MapOptions(
                            initialCenter: center,
                            initialZoom: 13,
                            onMapReady: () {
                              if (points.length > 1) {
                                detailMapController.fitCamera(
                                  CameraFit.bounds(
                                    bounds: LatLngBounds.fromPoints(points),
                                    padding: const EdgeInsets.all(36),
                                  ),
                                );
                              }
                            },
                          ),
                          children: [
                            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.draveinx.runtracker'),
                            if (points.length > 1) PolylineLayer(polylines: [Polyline(points: points, color: lime, strokeWidth: 5)]),
                            MarkerLayer(markers: [
                              Marker(
                                point: points.first,
                                width: 30,
                                height: 30,
                                child: const Tooltip(
                                  message: 'Start',
                                  child: Icon(Icons.flag_circle_rounded, color: lime, size: 28),
                                ),
                              ),
                              if (points.length > 1)
                                Marker(
                                  point: points.last,
                                  width: 30,
                                  height: 30,
                                  child: const Tooltip(
                                    message: 'Finish',
                                    child: Icon(Icons.location_on_rounded, color: Colors.redAccent, size: 28),
                                  ),
                                ),
                            ]),
                            const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _statCard('AFSTAND', (run.meters / 1000).toStringAsFixed(2), 'km', Icons.route_rounded)),
                const SizedBox(width: 8),
                Expanded(child: _statCard('DUUR', clock(run.seconds), 'min:sec', Icons.timer_rounded)),
                const SizedBox(width: 8),
                Expanded(child: _statCard('TEMPO', paceFor(run.meters, run.seconds), '/km', Icons.speed_rounded)),
              ]),
              const SizedBox(height: 12),
              Text('GPS-punten: ${run.coordinates.length}', style: const TextStyle(color: muted, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget historyView() {
    if (history.isEmpty) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.route_rounded, color: lime, size: 44),
        SizedBox(height: 12),
        Text('Nog geen activiteiten', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text('Je opgeslagen hardloopsessies en wandelroutes verschijnen hier.', style: TextStyle(color: muted)),
      ]));
    }
    final now = DateTime.now();
    final displayedHistory = history.where((run) {
      final date = DateTime.tryParse(run.date)?.toLocal();
      if (date == null) return false;
      if (historyFilter == 'Deze week') {
        final weekStart = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return !date.isBefore(weekStart);
      }
      if (historyFilter == 'Deze maand') {
        return !date.isBefore(DateTime(now.year, now.month, 1));
      }
      return true;
    }).toList();
    final totalMeters = history.fold<double>(0, (sum, run) => sum + run.meters);
    final totalSeconds = history.fold<int>(0, (sum, run) => sum + run.seconds);
    final weekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
    final weeklyRuns = history.where((run) {
      final date = DateTime.tryParse(run.date)?.toLocal();
      return date != null && !date.isBefore(DateTime(weekStart.year, weekStart.month, weekStart.day));
    }).toList();
    final weeklyMeters = weeklyRuns.fold<double>(0, (sum, run) => sum + run.meters);
    final weeklySeconds = weeklyRuns.fold<int>(0, (sum, run) => sum + run.seconds);
    final monthStart = DateTime(now.year, now.month, 1);
    final monthlyRuns = history.where((run) {
      final date = DateTime.tryParse(run.date)?.toLocal();
      return date != null && !date.isBefore(monthStart);
    }).toList();
    final monthlyMeters = monthlyRuns.fold<double>(0, (sum, run) => sum + run.meters);
    final monthlySeconds = monthlyRuns.fold<int>(0, (sum, run) => sum + run.seconds);
    final longestRun = history.isEmpty
        ? null
        : history.reduce((a, b) => a.meters >= b.meters ? a : b);
    final timedRuns = history.where((run) => run.meters >= 100 && run.seconds > 0).toList();
    final fastestRun = timedRuns.isEmpty
        ? null
        : timedRuns.reduce((a, b) =>
            a.seconds / a.meters <= b.seconds / b.meters ? a : b);
    final trainingDays = history
        .map((run) => DateTime.tryParse(run.date)?.toLocal())
        .whereType<DateTime>()
        .map((date) => DateTime(date.year, date.month, date.day))
        .toSet();
    final today = DateTime(now.year, now.month, now.day);
    var streakDays = 0;
    var streakDate = trainingDays.contains(today)
        ? today
        : today.subtract(const Duration(days: 1));
    while (trainingDays.contains(streakDate)) {
      streakDays++;
      streakDate = streakDate.subtract(const Duration(days: 1));
    }
    final validSpeedRuns = history
        .where((run) => run.meters >= 100 && run.seconds > 0)
        .toList();
    final averageSpeed = validSpeedRuns.isEmpty
        ? null
        : validSpeedRuns.fold<double>(0, (sum, run) => sum + run.meters) /
            validSpeedRuns.fold<int>(0, (sum, run) => sum + run.seconds) * 3.6;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: displayedHistory.isEmpty ? 2 : displayedHistory.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('JOUW VOORTGANG', style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
              ),
              Row(children: [
                Expanded(child: _statCard('TOTAAL', (totalMeters / 1000).toStringAsFixed(1), 'km', Icons.route_rounded)),
                const SizedBox(width: 10),
                Expanded(child: _statCard('TRAININGEN', history.length.toString(), 'runs', Icons.fitness_center_rounded)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _statCard(
                  'LANGSTE RUN',
                  longestRun == null ? '—' : (longestRun.meters / 1000).toStringAsFixed(2),
                  'km',
                  Icons.emoji_events_rounded,
                )),
                const SizedBox(width: 10),
                Expanded(child: _statCard(
                  'BESTE TEMPO',
                  fastestRun == null ? '—' : paceFor(fastestRun.meters, fastestRun.seconds),
                  '/km',
                  Icons.bolt_rounded,
                )),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _statCard(
                  'TRAININGSREEKS',
                  streakDays.toString(),
                  streakDays == 1 ? 'dag op rij' : 'dagen op rij',
                  Icons.local_fire_department_rounded,
                )),
                const SizedBox(width: 10),
                Expanded(child: _statCard(
                  'GEM. SNELHEID',
                  averageSpeed == null ? '—' : averageSpeed.toStringAsFixed(1),
                  'km/u',
                  Icons.speed_rounded,
                )),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _statCard(
                  'ACTIEVE DAGEN',
                  trainingDays.length.toString(),
                  trainingDays.length == 1 ? 'dag met training' : 'dagen met training',
                  Icons.event_available_rounded,
                )),
                const SizedBox(width: 10),
                Expanded(child: _statCard(
                  'TOTALE BEWEEGTIJD',
                  clock(totalSeconds),
                  'uur:min:sec',
                  Icons.timer_rounded,
                )),
              ]),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF25343B))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Expanded(child: Text('DEZE WEEK', style: TextStyle(color: lime, fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 11))),
                    TextButton.icon(
                      onPressed: editWeeklyGoal,
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: const Text('Weekdoel'),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: Text((weeklyMeters / 1000).toStringAsFixed(2) + ' / ' + weeklyGoalKm.toStringAsFixed(1) + ' km',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                    Text(weeklyRuns.length.toString() + (weeklyRuns.length == 1 ? ' training' : ' trainingen'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: ((weeklyMeters / 1000) / weeklyGoalKm).clamp(0.0, 1.0),
                      minHeight: 9,
                      backgroundColor: const Color(0xFF25343B),
                      valueColor: const AlwaysStoppedAnimation<Color>(lime),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    (weeklyMeters / 1000) >= weeklyGoalKm
                        ? 'Weekdoel behaald! Goed bezig.'
                        : ((weeklyGoalKm - weeklyMeters / 1000).toStringAsFixed(1) + ' km te gaan tot je weekdoel.'),
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  const SizedBox(height: 5),
                  Text('Beweegtijd: ' + clock(weeklySeconds) + ' · Totale beweegtijd: ' + clock(totalSeconds),
                      style: const TextStyle(color: muted, fontSize: 11)),
                  const SizedBox(height: 5),
                  Text(
                    weeklyMeters >= 100 && weeklySeconds > 0
                        ? 'Gemiddeld tempo deze week: ' + paceFor(weeklyMeters, weeklySeconds) + ' /km'
                        : 'Weektempo verschijnt zodra je een training van minstens 100 meter hebt opgeslagen.',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    weeklyMeters >= 100 && weeklySeconds > 0
                        ? 'Gemiddelde snelheid deze week: ' + (weeklyMeters / weeklySeconds * 3.6).toStringAsFixed(1) + ' km/u'
                        : 'Gemiddelde weeksnelheid verschijnt na een geldige training.',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF25343B))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('DEZE MAAND', style: TextStyle(color: lime, fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 11)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _statCard('AFSTAND', (monthlyMeters / 1000).toStringAsFixed(2), 'km', Icons.calendar_month_rounded)),
                    const SizedBox(width: 10),
                    Expanded(child: _statCard('TRAININGEN', monthlyRuns.length.toString(), 'runs', Icons.fitness_center_rounded)),
                    const SizedBox(width: 10),
                    Expanded(child: _statCard('BEWEEGTIJD', clock(monthlySeconds), 'uur:min:sec', Icons.timer_rounded)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    monthlyMeters >= 100 && monthlySeconds > 0
                        ? 'Gemiddeld tempo deze maand: ' + paceFor(monthlyMeters, monthlySeconds) + ' /km'
                        : 'Gemiddeld tempo verschijnt zodra je deze maand een training van minstens 100 meter hebt opgeslagen.',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    monthlyMeters >= 100 && monthlySeconds > 0
                        ? 'Gemiddelde snelheid deze maand: ' + (monthlyMeters / monthlySeconds * 3.6).toStringAsFixed(1) + ' km/u'
                        : 'Maandgemiddelde snelheid verschijnt na een geldige training.',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              if (history.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF25343B)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.insights_rounded, color: lime, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('GEMIDDELD PER TRAINING', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                            const SizedBox(height: 4),
                            Text(
                              (totalMeters / history.length / 1000).toStringAsFixed(2) + ' km · ' +
                                  clock((totalSeconds / history.length).round()) + ' gemiddelde duur',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              history.where((run) => run.meters >= 100 && run.seconds > 0).isEmpty
                                  ? 'Gemiddelde snelheid beschikbaar na een geldige training.'
                                  : (history.where((run) => run.meters >= 100 && run.seconds > 0)
                                      .fold<double>(0, (sum, run) => sum + (run.meters / 1000))
                                      .isFinite
                                      ? (history.where((run) => run.meters >= 100 && run.seconds > 0)
                                              .fold<double>(0, (sum, run) => sum + run.meters) /
                                          history.where((run) => run.meters >= 100 && run.seconds > 0)
                                              .fold<int>(0, (sum, run) => sum + run.seconds) * 3.6)
                                          .toStringAsFixed(1) + ' km/u gemiddelde snelheid'
                                      : 'Gemiddelde snelheid niet beschikbaar.'),
                              style: const TextStyle(color: muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              if (history.isNotEmpty)
                Text(
                  'Gemiddeld tempo over alle trainingen: ' +
                      paceFor(totalMeters, totalSeconds) + ' /km',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              const SizedBox(height: 10),
              const Text('RECENTE TRAININGEN', style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: ['Alles', 'Deze week', 'Deze maand'].map((filter) =>
                  ChoiceChip(
                    label: Text(filter),
                    selected: historyFilter == filter,
                    onSelected: (_) => setState(() => historyFilter = filter),
                    selectedColor: lime,
                    labelStyle: TextStyle(
                      color: historyFilter == filter ? ink : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ).toList(),
              ),
              const SizedBox(height: 10),
            ]),
          );
        }
        if (displayedHistory.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24, horizontal: 8),
            child: Text('Geen trainingen in deze periode.', style: TextStyle(color: muted)),
          );
        }
        final run = displayedHistory[index - 1];
        final date = DateTime.parse(run.date).toLocal();
        final dateText = date.day.toString().padLeft(2, '0') + '-' +
            date.month.toString().padLeft(2, '0') + '-' + date.year.toString();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => showRunDetails(run),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF25343B))),
              child: Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: lime.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)),
                  child: Icon(run.isWalking ? Icons.directions_walk_rounded : (run.isCycling ? Icons.directions_bike_rounded : Icons.directions_run_rounded), color: lime)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(run.activityLabel + ' · ' + dateText, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(clock(run.seconds) + ' · ' + run.coordinates.length.toString() + ' GPS-punten',
                    style: const TextStyle(color: muted, fontSize: 11)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text((run.meters / 1000).toStringAsFixed(2) + ' km',
                    style: const TextStyle(color: lime, fontSize: 17, fontWeight: FontWeight.w900)),
                Text(paceFor(run.meters, run.seconds) + ' /km',
                    style: const TextStyle(color: muted, fontSize: 11)),
              ]),
              PopupMenuButton<String>(
                tooltip: 'Trainingopties',
                icon: const Icon(Icons.more_vert_rounded, color: muted),
                onSelected: (value) {
                  if (value == 'delete') deleteRun(run);
                  if (value == 'details') showRunDetails(run);
                  if (value == 'summary') shareRunSummary(run);
                  if (value == 'copy_summary') copyRunSummary(run);
                  if (value == 'gpx') exportRunGpx(run);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'details', child: Text('Details bekijken')),
                  PopupMenuItem(value: 'summary', child: Text('Samenvatting delen')),
                  PopupMenuItem(value: 'copy_summary', child: Text('Samenvatting kopiëren')),
                  PopupMenuItem(value: 'gpx', child: Text('GPS-route exporteren (GPX)')),
                  PopupMenuItem(value: 'delete', child: Text('Training verwijderen')),
                ],
              ),
            ]),
            ),
          ),
        );
      },
    );
  }
}
