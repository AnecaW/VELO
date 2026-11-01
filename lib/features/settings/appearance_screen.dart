import '../../widgets/velo_ui.dart';

import 'package:flutter/material.dart';
import 'package:bike_computer/core/runtime.dart';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});
  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  Future<void> set(String k, dynamic v) async {
    await Runtime.settings.set(k, v);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('OLED & uiterlijk')),
    body: VeloPageList(
      children: [
        const Text(
          'Rust op je scherm.',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        for (final theme in [
          ('oled', 'OLED Black', 'Echt zwart, optimaal contrast'),
          ('graphite', 'Dark Graphite', 'Zachte grafietvlakken'),
          ('light', 'Light Mode', 'Heldere weergave voor overdag'),
          ('system', 'Automatisch', 'Volgt de systeeminstellingen'),
        ])
          Card(
            child: ListTile(
              title: Text(theme.$2),
              subtitle: Text(theme.$3),
              trailing: Runtime.settings.value('theme', 'oled') == theme.$1
                  ? Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => set('theme', theme.$1),
            ),
          ),
        const ListTile(title: Text('Accentkleur')),
        Wrap(
          spacing: 12,
          children: [
            for (final color in [
              0xff7cdec2,
              0xff70c5ff,
              0xffb6a1ff,
              0xffffbc78,
              0xffff8fab,
            ])
              IconButton(
                tooltip: 'Accent ${color.toRadixString(16)}',
                onPressed: () => set('accent', color),
                icon: Icon(Icons.circle, color: Color(color), size: 36),
              ),
          ],
        ),
        SwitchListTile(
          title: const Text('Extra contrast'),
          value: Runtime.settings.value('contrast', false),
          onChanged: (v) => set('contrast', v),
        ),
        SwitchListTile(
          title: const Text('Minimalistisch fietsscherm'),
          subtitle: const Text('Snelheid, afstand en tijd op de eerste pagina'),
          value: Runtime.settings.value('minimalRide', false),
          onChanged: (v) => set('minimalRide', v),
        ),
        SwitchListTile(
          title: const Text('Nachtmodus tijdens ritten'),
          subtitle: const Text(
            'Donker thema en gedimde helderheid bij actieve registratie',
          ),
          value: Runtime.settings.value('nightRide', false),
          onChanged: (v) => set('nightRide', v),
        ),
      ],
    ),
  );
}
