import '../integrations/strava_upload_card.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:bike_computer/widgets/route_map.dart';
import 'package:bike_computer/services/navigation/gpx_route.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:flutter/material.dart';
import 'package:bike_computer/models/ride_session.dart';
import 'package:bike_computer/models/ride_models.dart';
import 'package:bike_computer/services/ride/gpx_export_service.dart';

/// Ride summary screen shown after ride ends
class RideSummaryScreen extends StatefulWidget {
  final RideSession session;

  const RideSummaryScreen({super.key, required this.session});

  @override
  State<RideSummaryScreen> createState() => _RideSummaryScreenState();
}

class _RideSummaryScreenState extends State<RideSummaryScreen> {
  late RideStats _stats;

  @override
  void initState() {
    super.initState();
    _stats = widget.session.getStats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.session.state == RideState.saved
              ? 'RIDE SAVED'
              : 'RITOVERZICHT',
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (widget.session.id != null)
                TextFormField(
                  initialValue: 'Fietsrit',
                  decoration: const InputDecoration(
                    labelText: 'Naam van de rit',
                  ),
                  onFieldSubmitted: (value) async {
                    await Runtime.database.putDocument(
                      'ride-name',
                      widget.session.id!,
                      value,
                    );
                  },
                ),
              _buildSummaryCard(context),
              const SizedBox(height: 24),

              // Detailed stats
              _buildStatsGrid(context),
              const SizedBox(height: 24),

              // Actions
              _buildActions(context),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              '${_stats.totalDistance.toStringAsFixed(2)} km',
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 16),
            Text(
              _formatDuration(_stats.elapsedTime),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    Text(
                      '${_stats.averageSpeed.toStringAsFixed(1)} km/h',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Avg Speed',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      '${_stats.maxSpeed.toStringAsFixed(1)} km/h',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Max Speed',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DETAILS', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.2,
          children: [
            _buildStatCard(
              context,
              '${_stats.totalElevationGain.toStringAsFixed(0)} m',
              'Elevation Gain',
            ),
            _buildStatCard(
              context,
              '${_stats.totalElevationLoss.toStringAsFixed(0)} m',
              'Elevation Loss',
            ),
            _buildStatCard(
              context,
              _formatDuration(_stats.movingTime),
              'Moving Time',
            ),
            _buildStatCard(context, '${_stats.numberOfLaps}', 'Laps'),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, String value, String label) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Column(
      children: [
        if (widget.session.id != null)
          StravaUploadCard(rideId: widget.session.id!),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _showRouteMap(context),
            icon: const Icon(Icons.map),
            label: const Text('View Map'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              try {
                final gpx = GpxExportService.exportToGpx(widget.session);
                final uri = await FilePicker.saveFile(
                  fileName: '${widget.session.id ?? 'bike-ride'}.gpx',
                  mimeType: 'application/gpx+xml',
                  bytes: Uint8List.fromList(utf8.encode(gpx)),
                );
                if (context.mounted && uri != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('GPX opgeslagen: $uri')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Export mislukt: $e')));
                }
              }
            },
            icon: const Icon(Icons.download),
            label: const Text('Export GPX'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              // Return to home
              context.go('/ride');
            },
            icon: const Icon(Icons.home),
            label: const Text('Naar fietscomputer'),
          ),
        ),
      ],
    );
  }

  void _showRouteMap(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final points = widget.session.trackPoints;

        return AlertDialog(
          title: const Text('Route Map'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Route overview'),
                const SizedBox(height: 12),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade900,
                  ),
                  child: CustomPaint(
                    child: RouteMap(
                      route: points.length < 2
                          ? null
                          : NavRoute(
                              'GPS-spoor',
                              points
                                  .map(
                                    (p) => NavPoint(
                                      p.latitude,
                                      p.longitude,
                                      p.altitude,
                                    ),
                                  )
                                  .toList(),
                            ),
                      online: Runtime.settings.value('onlineMap', false),
                      offlinePath: Runtime.settings.value<String?>(
                        'offlineMap',
                        null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Track points: ${points.length}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
