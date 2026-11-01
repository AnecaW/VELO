import 'package:bike_computer/services/integrations/gpx_exchange_service.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bike_computer/core/runtime.dart';

class GpxExchangeScreen extends StatefulWidget {
  const GpxExchangeScreen({super.key});
  @override
  State<GpxExchangeScreen> createState() => _GpxExchangeScreenState();
}

class _GpxExchangeScreenState extends State<GpxExchangeScreen> {
  String? message;
  bool busy = false;
  Future<void> run(Future<String?> Function() action) async {
    setState(() => busy = true);
    try {
      final result = await action();
      if (mounted) setState(() => message = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Bestand niet verwerkt. Controleer het GPX-bestand, opslagtoegang en probeer opnieuw.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> importRoute() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return null;
    final file = files.first, length = await files.first.length();
    if (length == null || length > 10 * 1024 * 1024) {
      throw const FormatException('GPX maximaal 10 MB');
    }
    final raw = utf8.decode(await file.readAsBytes());
    await GpxExchangeService(Runtime.database)
        .importRoute(raw, filename: file.name);
    return 'GPX-route lokaal bewaard. Open Kaart → Lokale routes. Er is geen account gekoppeld en niets online verstuurd.';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('GPX-bestanden')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Zelfstandig uitwisselen',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'Exporteer je eigen ritten en importeer routes als GPX. Je kiest zelf welke bestanden je deelt.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : () => run(importRoute),
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('GPX-route importeren'),
        ),
        OutlinedButton(
          onPressed: () => launchUrl(
            Uri.parse('https://www.strava.com/upload/select'),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text('Strava · officiële bestandsupload openen'),
        ),
        OutlinedButton(
          onPressed: () => launchUrl(
            Uri.parse('https://www.komoot.com/'),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text('Komoot openen'),
        ),
        if (message != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(message!)),
        if (busy) const LinearProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          'Eigen rit als GPX exporteren',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        FutureBuilder(
          future: Runtime.database.getAllRides(),
          builder: (context, snapshot) => Column(
            children: [
              if ((snapshot.data ?? []).isEmpty)
                const ListTile(
                  title: Text('Nog geen eigen ritten. Neem eerst een rit op.'),
                ),
              for (final ride in snapshot.data ?? [])
                ListTile(
                  title: Text('${ride.startTime ?? ride.rideId}'),
                  subtitle: Text(
                    '${ride.totalDistance.toStringAsFixed(1)} km · lokale opname',
                  ),
                  trailing: IconButton(
                    tooltip: 'GPX exporteren',
                    icon: const Icon(Icons.save_alt),
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            final gpx = await GpxExchangeService(
                              Runtime.database,
                            ).exportRide(ride.rideId);
                            final result = await FilePicker.saveFile(
                              fileName: '${ride.rideId}.gpx',
                              bytes: Uint8List.fromList(utf8.encode(gpx)),
                            );
                            return result == null
                                ? 'Export geannuleerd.'
                                : 'GPX-bestand opgeslagen op de gekozen locatie. Het bestand is nog niet naar een dienst geüpload.';
                          }),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
