import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const RunTrackerApp());

const ink = Color(0xFF0A1014);
const panel = Color(0xFF131D23);
const lime = Color(0xFFC7F36B);
const muted = Color(0xFF8FA1A8);

class RunTrackerApp extends StatelessWidget {
  const RunTrackerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RunTracker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: ink,
          colorScheme: const ColorScheme.dark(primary: lime, surface: panel),
        ),
        home: const RunHomePage(),
      );
}

class RunRecord {
  const RunRecord(this.date, this.seconds, this.meters, this.coordinates);
  final String date;
  final int seconds;
  final double meters;
  final List<List<double>> coordinates;

  Map<String, dynamic> toJson() => {
        'date': date,
        'seconds': seconds,
        'meters': meters,
        'coordinates': coordinates,
      };

  factory RunRecord.fromJson(Map<String, dynamic> json) => RunRecord(
        json['date'] as String,
        json['seconds'] as int,
        (json['meters'] as num).toDouble(),
        (json['coordinates'] as List<dynamic>)
            .map((e) => [(e[0] as num).toDouble(), (e[1] as num).toDouble()])
            .toList(),
      );
}

class RunHomePage extends StatefulWidget {
  const RunHomePage({super.key});
  @override
  State<RunHomePage> createState() => _RunHomePageState();
}

class _RunHomePageState extends State<RunHomePage> {
  final MapController mapController = MapController();
  final List<LatLng> route = [];
  final List<RunRecord> history = [];
  StreamSubscription<Position>? gps;
  Timer? timer;
  int elapsed = 0;
  double meters = 0;
  bool running = false;
  bool paused = false;
  bool showHistory = false;
  String status = 'Klaar om te gaan';
  DateTime? startedAt;

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  @override
  void dispose() {
    gps?.cancel();
    timer?.cancel();
    super.dispose();
  }

  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('runtracker_history');
    if (value == null) return;
    try {
      final records = (jsonDecode(value) as List<dynamic>)
          .map((e) => RunRecord.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() => history.addAll(records));
    } catch (_) {
      if (mounted) setState(() => status = 'Geschiedenis kon niet worden geladen');
    }
  }

  Future<void> saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('runtracker_history',
        jsonEncode(history.map((e) => e.toJson()).toList()));
  }

  Future<bool> checkLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => status = 'Schakel locatie/GPS in op je telefoon');
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
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
          notificationTitle: 'RunTracker is actief',
          notificationText: 'Je training wordt vastgelegd.',
          enableWakeLock: true,
        ),
      );

  Future<void> startRun() async {
    if (!await checkLocation()) return;
    setState(() {
      route.clear();
      elapsed = 0;
      meters = 0;
      startedAt = DateTime.now();
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
      onError: (_) {
        if (mounted) setState(() => status = 'GPS tijdelijk niet beschikbaar');
      },
    );
  }

  void acceptPosition(Position p) {
    if (!mounted || !running || paused) return;
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
    await gps?.cancel();
    gps = null;
    timer?.cancel();
    setState(() {
      paused = true;
      status = 'Training gepauzeerd';
    });
  }

  Future<void> resumeRun() async {
    if (!await checkLocation()) return;
    setState(() {
      paused = false;
      status = 'GPS hervatten…';
    });
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && running && !paused) setState(() => elapsed++);
    });
    gps = Geolocator.getPositionStream(locationSettings: settings()).listen(
      acceptPosition,
      onError: (_) {
        if (mounted) setState(() => status = 'GPS tijdelijk niet beschikbaar');
      },
    );
  }

  Future<void> finishRun() async {
    await gps?.cancel();
    gps = null;
    timer?.cancel();
    if (startedAt != null && (elapsed > 0 || meters > 0)) {
      history.insert(0, RunRecord(
        startedAt!.toIso8601String(),
        elapsed,
        meters,
        route.map((p) => [p.latitude, p.longitude]).toList(),
      ));
      if (history.length > 100) history.removeRange(100, history.length);
      await saveHistory();
    }
    setState(() {
      running = false;
      paused = false;
      status = 'Training opgeslagen op dit apparaat';
    });
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: lime, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.route_rounded, color: ink, size: 25),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('RUNTRACKER', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2.1)),
                Text('YOUR PACE. YOUR PATH.', style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.5)),
              ])),
              IconButton(
                tooltip: showHistory ? 'Terug naar training' : 'Trainingsgeschiedenis',
                onPressed: () => setState(() => showHistory = !showHistory),
                icon: Icon(showHistory ? Icons.close_rounded : Icons.history_rounded, color: lime),
              ),
            ]),
          ),
          Expanded(child: showHistory ? historyView() : runView(center)),
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
                  Expanded(child: action('START TRAINING', Icons.play_arrow_rounded, startRun))
                else if (!paused) ...[
                  Expanded(child: action('PAUZE', Icons.pause_rounded, pauseRun, secondary: true)),
                  const SizedBox(width: 10),
                  Expanded(child: action('AFRONDEN', Icons.stop_rounded, finishRun)),
                ] else ...[
                  Expanded(child: action('VERDER', Icons.play_arrow_rounded, resumeRun)),
                  const SizedBox(width: 10),
                  Expanded(child: action('AFRONDEN', Icons.stop_rounded, finishRun, secondary: true)),
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

  Widget action(String label, IconData icon, Future<void> Function() callback, {bool secondary = false}) =>
      SizedBox(height: 54, child: FilledButton.icon(
        onPressed: () => callback(),
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: .8)),
        style: FilledButton.styleFrom(
          backgroundColor: secondary ? panel : lime,
          foregroundColor: secondary ? Colors.white : ink,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ));

  Widget historyView() {
    if (history.isEmpty) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.directions_run_rounded, color: lime, size: 44),
        SizedBox(height: 12),
        Text('Nog geen trainingen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text('Je opgeslagen runs verschijnen hier.', style: TextStyle(color: muted)),
      ]));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final run = history[index];
        final date = DateTime.parse(run.date).toLocal();
        final dateText = date.day.toString().padLeft(2, '0') + '-' +
            date.month.toString().padLeft(2, '0') + '-' + date.year.toString();
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF25343B))),
          child: Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: lime.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.directions_run_rounded, color: lime)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dateText, style: const TextStyle(fontWeight: FontWeight.w800)),
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
          ]),
        );
      },
    );
  }
}
