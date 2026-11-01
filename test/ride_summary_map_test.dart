import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_computer/features/ride/ride_summary_screen.dart';
import 'package:bike_computer/models/gps_models.dart';
import 'package:bike_computer/models/ride_session.dart';

void main() {
  testWidgets('View Map opens a route preview dialog', (tester) async {
    final session = RideSession(
      state: RideState.finished,
      startTime: DateTime(2024, 1, 1, 9, 0, 0),
      endTime: DateTime(2024, 1, 1, 9, 30, 0),
      trackPoints: [
        TrackPoint(
          latitude: 51.2194,
          longitude: 4.4025,
          altitude: 10,
          timestamp: DateTime(2024, 1, 1, 9, 0, 0),
        ),
        TrackPoint(
          latitude: 51.2202,
          longitude: 4.4042,
          altitude: 12,
          timestamp: DateTime(2024, 1, 1, 9, 15, 0),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: RideSummaryScreen(session: session)),
    );

    final mapButton = find.text('View Map');
    await tester.ensureVisible(mapButton);
    await tester.tap(mapButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Route Map'), findsOneWidget);
    expect(find.text('Route overview'), findsOneWidget);
  });
}
