import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';
import 'package:bike_computer/services/gps/gps_service.dart';
import 'package:bike_computer/models/gps_models.dart';
import 'package:bike_computer/services/ride/ride_history_service.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});
  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final history = RideHistoryService(database: Runtime.database);
  bool loaded = false;
  int days = 30;
  @override
  void initState() {
    super.initState();
    history.loadPersistedRides().then((_) {
      if (mounted) setState(() => loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final rides = history
        .getAllRides()
        .where((r) => days == 0 || (r.startTime?.isAfter(cutoff) ?? false))
        .toList();
    final distance = rides.fold(0.0, (sum, r) => sum + r.totalDistance),
        gain = rides.fold(0.0, (sum, r) => sum + r.totalElevationGain);
    final seconds = rides.fold(0, (sum, r) => sum + r.movingTime.inSeconds);
    final longest = rides.fold(
      0.0,
      (best, r) => math.max(best, r.totalDistance),
    );
    final maximum = rides.fold(0.0, (best, r) => math.max(best, r.maxSpeed));
    return Scaffold(
      appBar: AppBar(title: const Text('STATISTIEKEN')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final d in [7, 30, 0])
                ChoiceChip(
                  label: Text(d == 0 ? 'Alles' : '$d dagen'),
                  selected: days == d,
                  onSelected: (_) => setState(() => days = d),
                ),
            ],
          ),
          if (!loaded) const LinearProgressIndicator(),
          for (final row in [
            ('Ritten', '${rides.length}'),
            ('Afstand', '${distance.toStringAsFixed(1)} km'),
            ('Rijtijd', '${seconds ~/ 3600} h ${(seconds ~/ 60) % 60} min'),
            ('Hoogtewinst · GPS', '${gain.round()} m'),
            ('Langste lokale rit', '${longest.toStringAsFixed(1)} km'),
            ('Hoogste gemeten snelheid', '${maximum.toStringAsFixed(1)} km/h'),
          ])
            Card(
              child: ListTile(
                title: Text(row.$1),
                trailing: Text(
                  row.$2,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
          const Text(
            'Berekend uit lokaal opgeslagen ritten. GPS-hoogte is een schatting. Strava Live Segments worden niet ondersteund.',
          ),
        ],
      ),
    );
  }
}

class ClimbScreen extends StatefulWidget {
  const ClimbScreen({super.key});
  @override
  State<ClimbScreen> createState() => _ClimbScreenState();
}

class _ClimbScreenState extends State<ClimbScreen> {
  NavRoute? route;
  RouteProgress? progress;
  String message = 'Open eerst een GPX-route met hoogtegegevens in Navigatie.';
  final gps = RealGPSService();
  StreamSubscription<GPSLocation>? subscription;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await Runtime.database.getDocument('navigation', 'selected');
      if (raw != null && mounted) setState(() => route = NavRoute.decode(raw));
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    }
  }

  Future<void> _locate() async {
    try {
      subscription ??= gps.locationStream.listen(
        (p) {
          if (mounted && route != null) {
            setState(
              () => progress = RouteProgress.locate(
                route!,
                NavPoint(p.latitude, p.longitude),
                accuracy: p.accuracy,
              ),
            );
          }
        },
        onError: (Object e) {
          if (mounted) setState(() => message = e.toString());
        },
      );
      await gps.startListening();
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = route?.points ?? [];
    final valid = points.length > 1 && points.every((p) => p.elevation != null);
    var gain = 0.0;
    if (valid) {
      double anchor = points.first.elevation!;
      for (final p in points) {
        final delta = p.elevation! - anchor;
        if (delta.abs() > 3) {
          if (delta > 0) gain += delta;
          anchor = p.elevation!;
        }
      }
    }
    final position = progress == null
        ? null
        : points[progress!.segment.clamp(0, points.length - 1)].elevation;
    return Scaffold(
      appBar: AppBar(title: const Text('KLIMPROFIEL')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!valid)
            Text(message)
          else ...[
            Text(route!.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: CustomPaint(
                painter: ElevationPainter(
                  points.map((p) => p.elevation!).toList(),
                  progress == null ? null : progress!.traveled / route!.meters,
                ),
              ),
            ),
            ListTile(
              title: const Text('Routeafstand'),
              trailing: Text('${(route!.meters / 1000).toStringAsFixed(1)} km'),
            ),
            ListTile(
              title: const Text('Gefilterde hoogtewinst'),
              trailing: Text('${gain.round()} m'),
            ),
            ListTile(
              title: const Text('Hoogte op de route'),
              trailing: Text(position == null ? '—' : '${position.round()} m'),
            ),
            ListTile(
              title: const Text('Resterende route'),
              trailing: Text(
                progress == null
                    ? '—'
                    : '${(progress!.remaining / 1000).toStringAsFixed(1)} km',
              ),
            ),
            FilledButton(
              onPressed: _locate,
              child: const Text('Positie op profiel volgen'),
            ),
            const Text(
              'Hoogtes komen uit het routebestand. Dit is een volledig routeprofiel; afzonderlijke beklimmingen en voorspellingen tijdens vrije ritten zijn nog niet beschikbaar.',
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    subscription?.cancel();
    gps.dispose();
    super.dispose();
  }
}

class ElevationPainter extends CustomPainter {
  final List<double> elevations;
  final double? fraction;
  ElevationPainter(this.elevations, this.fraction);
  @override
  void paint(Canvas canvas, Size size) {
    if (elevations.length < 2) return;
    final low = elevations.reduce(math.min), high = elevations.reduce(math.max);
    final path = Path();
    for (var i = 0; i < elevations.length; i++) {
      final x = i / (elevations.length - 1) * size.width,
          y =
              size.height -
              16 -
              (elevations[i] - low) /
                  math.max(1, high - low) *
                  (size.height - 32);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xff72d9b0)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
    if (fraction != null) {
      final x = fraction!.clamp(0, 1) * size.width;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Colors.orange
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ElevationPainter old) =>
      old.elevations != elevations || old.fraction != fraction;
}
