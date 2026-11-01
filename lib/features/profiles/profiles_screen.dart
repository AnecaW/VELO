import '../../widgets/velo_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bike_computer/features/profiles/cubits/activity_profile_cubit.dart';
import 'package:bike_computer/models/activity_profile.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ActivityProfileCubit()..loadProfiles(),
    child: const _ProfileList(),
  );
}

class _ProfileList extends StatelessWidget {
  const _ProfileList();
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<ActivityProfileCubit, ActivityProfileState>(
    builder: (context, state) => Scaffold(
      appBar: AppBar(
        title: const Text('Activiteitprofielen'),
        actions: [
          IconButton(
            tooltip: 'Profiel toevoegen',
            onPressed: () => _edit(context, null),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: VeloPageList(
        children: [
          for (final p in state.profiles)
            Card(
              child: ListTile(
                leading: Icon(p.icon, color: p.accentColor),
                title: Text(p.name),
                subtitle: Text(
                  '${p.type} · autopauze ${p.autoPauseEnabled ? 'aan' : 'uit'}',
                ),
                onTap: () => _edit(context, p),
                trailing: IconButton(
                  tooltip: 'Als standaard kiezen',
                  icon: Icon(
                    state.selectedProfile?.id == p.id
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                  ),
                  onPressed: () =>
                      context.read<ActivityProfileCubit>().selectProfile(p.id),
                ),
              ),
            ),
          if (state.error != null) Text(state.error!),
        ],
      ),
    ),
  );
  Future<void> _edit(BuildContext context, ActivityProfile? profile) async {
    final cubit = context.read<ActivityProfileCubit>(),
        name = TextEditingController(text: profile?.name ?? '');
    var type = profile?.type ?? 'Road',
        pause = profile?.autoPauseEnabled ?? false,
        speed = profile?.autoPauseSpeedKmh ?? 3.0,
        color = profile?.accentColor ?? const Color(0xff7cdec2);
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(profile == null ? 'Nieuw profiel' : 'Profiel wijzigen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Naam'),
                ),
                DropdownButton<String>(
                  value: type,
                  items: [
                    for (final t in [
                      'Road',
                      'Gravel',
                      'MTB',
                      'Indoor',
                      'Commute',
                      'Custom',
                    ])
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => update(() => type = v!),
                ),
                SwitchListTile(
                  title: const Text('Automatische pauze'),
                  value: pause,
                  onChanged: (v) => update(() => pause = v),
                ),
                Text('Pauzedrempel ${speed.toStringAsFixed(1)} km/h'),
                Slider(
                  value: speed,
                  min: 1,
                  max: 10,
                  divisions: 18,
                  onChanged: (v) => update(() => speed = v),
                ),
                Wrap(
                  children: [
                    for (final c in [
                      0xff7cdec2,
                      0xff70c5ff,
                      0xffb6a1ff,
                      0xffffbc78,
                    ])
                      IconButton(
                        icon: Icon(Icons.circle, color: Color(c)),
                        onPressed: () => update(() => color = Color(c)),
                      ),
                  ],
                ),
                if (error != null) Text(error!),
              ],
            ),
          ),
          actions: [
            if (profile != null)
              TextButton(
                onPressed: () async {
                  try {
                    await cubit.deleteProfile(profile.id);
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    update(() => error = e.toString());
                  }
                },
                child: const Text('Verwijderen'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) {
                  update(() => error = 'Vul een naam in');
                  return;
                }
                final p = ActivityProfile(
                  id:
                      profile?.id ??
                      'profile-${DateTime.now().microsecondsSinceEpoch}',
                  name: name.text.trim(),
                  type: type,
                  icon: Icons.directions_bike,
                  accentColor: color,
                  autoPauseEnabled: pause,
                  autoPauseSpeedKmh: speed,
                );
                if (profile == null) {
                  await cubit.addProfile(p);
                } else {
                  await cubit.updateProfile(p);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Opslaan'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
  }
}
