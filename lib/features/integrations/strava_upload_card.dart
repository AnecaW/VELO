import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/runtime.dart';
import '../../services/integrations/backend_strava.dart';
import '../../services/accounts/account_service.dart';
import '../../widgets/velo_ui.dart';
import 'connected_apps_screen.dart';

class StravaUploadCard extends StatefulWidget {
  final String rideId;
  final BackendStravaService? service;
  final bool loadRemote;
  const StravaUploadCard({
    super.key,
    required this.rideId,
    this.service,
    this.loadRemote = true,
  });
  @override
  State<StravaUploadCard> createState() => _StravaUploadCardState();
}

class _StravaUploadCardState extends State<StravaUploadCard> {
  late final service =
      widget.service ??
      Runtime.integrations.strava.service as BackendStravaService;
  Map<String, dynamic> job = {};
  bool connected = false, canUpload = false, busy = false, reading = false;
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (['pending', 'running', 'local_pending'].contains(job['status'])) {
        _load();
      }
    });
  }

  Future<void> _load() async {
    if (reading || service.accounts.user == null) return;
    reading = true;
    try {
      if (widget.loadRemote) await service.refreshRideStatus(widget.rideId);
      final info = await service.information();
      final raw = await service.database.getDocument('sync', widget.rideId);
      final pending = await service.database.getDocument(
        'strava-upload-outbox',
        jsonEncode([service.accounts.user!['id'], widget.rideId]),
      );
      if (mounted) {
        setState(() {
          connected = info['connected'] == true;
          canUpload = info['features']?['uploads'] == true;
          job = raw == null
              ? pending == null
                    ? {}
                    : {'status': 'local_pending'}
              : jsonDecode(raw);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is AccountFailure
              ? e.message
              : 'De uploadstatus kon niet worden opgehaald.',
        );
      }
    } finally {
      reading = false;
    }
  }

  Future<void> _upload() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (['failed', 'needs_review'].contains(job['status']) &&
          job['job_id'] != null) {
        var confirmed = true;
        if (job['status'] == 'needs_review') {
          confirmed =
              await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Controleer eerst Strava'),
                  content: const Text(
                    'Deze upload heeft een onzekere uitkomst. Controleer of de rit al in Strava staat. Alleen opnieuw proberen wanneer er geen dubbele rit ontstaat.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Annuleren'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Gecontroleerd, opnieuw proberen'),
                    ),
                  ],
                ),
              ) ??
              false;
        }
        if (!confirmed) return;
        await service.accounts.request(
          'POST',
          '/api/v1/jobs/${job['job_id']}/retry',
          body: {'confirmed_no_duplicate': true},
        );
      } else {
        await service.enqueue(widget.rideId);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is AccountFailure
              ? e.message
              : 'Upload niet voltooid. Je eigen rit blijft bewaard.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = job['status'];
    final label = job['removed'] == true
        ? 'Verwijderd in Strava'
        : switch (status) {
            'complete' => 'Geüpload naar Strava',
            'pending' => 'In de Strava-wachtrij',
            'running' => 'Strava verwerkt je rit',
            'local_pending' => 'Wacht op verbinding',
            'failed' => 'Upload mislukt',
            'needs_review' => 'Controle in Strava vereist',
            _ => 'Eigen VELO-rit',
          };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            if (error ?? job['error'] case final String text)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: VeloNotice(text, error: true),
              ),
            if (busy) const LinearProgressIndicator(),
            if (job['upload_id'] != null) Text('Upload ${job['upload_id']}'),
            if (job['removed'] == true)
              const Text(
                'Deze activiteit is in Strava verwijderd. Je lokale rit blijft bewaard; er wordt geen nieuwe upload gemaakt.',
              )
            else if (job['activity_id'] != null)
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(
                    'https://www.strava.com/activities/${job['activity_id']}',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xfffc5200),
                ),
                child: const Text(
                  'View on Strava',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              )
            else if (status == 'complete')
              const Text(
                'Deze rit is eerder verstuurd; er wordt geen dubbele upload gemaakt.',
              )
            else if (!connected)
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const StravaAccountScreen(),
                  ),
                ),
                child: const Text('Strava verbinden'),
              )
            else if (!canUpload)
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const StravaAccountScreen(),
                  ),
                ),
                child: const Text('Uploadtoestemming geven'),
              )
            else
              OutlinedButton.icon(
                onPressed:
                    busy ||
                        ['pending', 'running', 'local_pending'].contains(status)
                    ? null
                    : _upload,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(
                  ['failed', 'needs_review'].contains(status)
                      ? 'Upload opnieuw proberen'
                      : 'Uploaden naar Strava',
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }
}
