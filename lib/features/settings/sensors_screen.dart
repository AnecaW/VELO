import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bike_computer/core/runtime.dart';
import 'package:bike_computer/services/bluetooth/ble_sensor_manager.dart';
import 'package:bike_computer/models/sensor_models.dart';

class SensorsScreen extends StatefulWidget {
  final BleSensorManager? manager;
  const SensorsScreen({super.key, this.manager});
  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends State<SensorsScreen> {
  List<SensorInfo> sensors = [];
  String? error;
  bool busy = false;
  Timer? timer;
  BleSensorManager get manager => widget.manager ?? Runtime.sensors;
  @override
  void initState() {
    super.initState();
    sensors = manager.connectedSensors;
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
      error = null;
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sensor Manager')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Bluetooth LE · standaard hartslag, crankcadans en fietsvermogen. Geen verzonnen metingen. ANT+ is in deze versie niet geïmplementeerd.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy
              ? null
              : () => _run(() async {
                  sensors = await manager.scanForSensors();
                }),
          icon: const Icon(Icons.bluetooth_searching),
          label: const Text('Scan sensoren'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.orange)),
        if (sensors.isEmpty && !busy)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Geen sensoren gevonden. Activeer Bluetooth en maak de sensor wakker.',
            ),
          ),
        for (final s in sensors)
          Card(
            child: ListTile(
              title: Text(s.name),
              subtitle: Text(
                '${s.type.name} · ${manager.isConnected(s.id) ? 'Verbonden' : 'Niet verbonden'} · RSSI ${s.rssi}',
              ),
              trailing: TextButton(
                onPressed: busy
                    ? null
                    : () => _run(() async {
                        if (manager.isConnected(s.id)) {
                          await manager.disconnectSensor(s.id);
                        } else {
                          await manager.connectSensor(s.id);
                          await Runtime.database.putDocument(
                            'sensors',
                            s.id,
                            s.name,
                          );
                        }
                      }),
                child: Text(
                  manager.isConnected(s.id) ? 'Disconnect' : 'Connect',
                ),
              ),
            ),
          ),
      ],
    ),
  );
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }
}
