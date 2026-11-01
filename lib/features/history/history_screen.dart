import 'dart:async';

import 'package:bike_computer/features/ride/ride_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:bike_computer/services/ride/ride_history_service.dart';

/// Ride history list screen
class HistoryScreen extends StatefulWidget {
  final RideHistoryService? service;
  const HistoryScreen({super.key, this.service});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final RideHistoryService _historyService;
  bool _isLoading = true;
  String? _error;
  StreamSubscription<String>? _changes;

  @override
  void initState() {
    super.initState();
    _historyService = widget.service ?? RideHistoryService();
    _loadHistory();
    _changes = _historyService.database.documentChanges
        .where((kind) => kind == 'ride')
        .listen((_) => _loadHistory());
  }

  Future<void> _loadHistory() async {
    try {
      await _historyService.loadPersistedRides();
      _error = null;
    } catch (_) {
      _error = 'Ritten laden is niet gelukt. Probeer opnieuw.';
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Activiteiten')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              TextButton(
                onPressed: _loadHistory,
                child: const Text('Opnieuw proberen'),
              ),
            ],
          ),
        ),
      );
    }
    final rides = _historyService.getRidesSortedByDate();
    final stats = _historyService.getStatistics();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activiteiten'),
        actions: [
          if (rides.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Ritgeschiedenis wissen',
              onPressed: _confirmClearHistory,
            ),
        ],
      ),
      body: rides.isEmpty
          ? _buildEmptyState(context)
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Statistics summary
                    _buildStatsCard(context, stats),
                    const SizedBox(height: 24),

                    // Rides list
                    Text(
                      'Recente ritten',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 12),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: rides.length,
                      itemBuilder: (context, index) {
                        final ride = rides[index];
                        return InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => RideSummaryScreen(session: ride),
                            ),
                          ),
                          child: _buildRideCard(context, ride, index + 1),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _confirmClearHistory() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alle ritten verwijderen?'),
        content: const Text(
          'Alle opgeslagen ritten worden verwijderd. Dit wordt ook naar je account gesynchroniseerd.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );

    if (shouldClear != true) return;

    await _historyService.clearHistory();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Nog geen ritten',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Je opgeslagen ritten verschijnen hier.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(
    BuildContext context,
    ({int totalRides, double totalDistance, Duration totalTime}) stats,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                Text(
                  '${stats.totalRides}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text('Rides', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            Column(
              children: [
                Text(
                  '${stats.totalDistance.toStringAsFixed(1)} km',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text('Afstand', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            Column(
              children: [
                Text(
                  _formatDuration(stats.totalTime),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text('Tijd', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRideCard(BuildContext context, dynamic ride, int position) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ride #$position',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Row(
                  children: [
                    if (ride.endTime != null)
                      Text(
                        _formatDate(ride.endTime),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete ride',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Rit verwijderen?'),
                            content: const Text(
                              'Dit verwijdert de lokale rit en het GPS-spoor.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Annuleren'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Verwijderen'),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                        final deleted = await _historyService.deleteRide(
                          ride.id,
                        );
                        if (deleted && mounted) {
                          setState(() {});
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${ride.totalDistance.toStringAsFixed(2)} km',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Afstand',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _formatDuration(ride.elapsedTime),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Tijd',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${ride.averageSpeed.toStringAsFixed(1)} km/h',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Gemiddelde',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.month}/${date.day}/${date.year}';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}
