import 'package:flutter/material.dart';

import '../core/runtime.dart';
import '../models/bike_type.dart';

class BikeTypeSelector extends StatelessWidget {
  final BikeType? fixed;
  const BikeTypeSelector({super.key, this.fixed});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Runtime.settings,
    builder: (context, _) {
      final type =
          fixed ??
          BikeType.parse(Runtime.settings.value<String?>('bikeType', null));
      return PopupMenuButton<BikeType>(
        enabled: fixed == null,
        tooltip: fixed == null ? 'Fietstype kiezen' : 'Fietstype van deze rit',
        initialValue: type,
        onSelected: (next) async {
          try {
            await Runtime.settings.set('bikeType', next.name);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Fietstype kon niet worden bewaard. Probeer opnieuw.',
                  ),
                ),
              );
            }
          }
        },
        itemBuilder: (_) => [
          for (final item in BikeType.values)
            PopupMenuItem(
              value: item,
              child: Row(
                children: [
                  Icon(item.icon, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Text(item.label)),
                  if (item == type) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(type.icon, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(type.label, overflow: TextOverflow.ellipsis),
              ),
              if (fixed == null) const Icon(Icons.expand_more, size: 18),
            ],
          ),
        ),
      );
    },
  );
}
