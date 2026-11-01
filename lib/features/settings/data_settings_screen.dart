import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/runtime.dart';
import '../../widgets/velo_ui.dart';
import '../accounts/account_screen.dart';

class DataSettingsScreen extends StatelessWidget {
  const DataSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Synchronisatie en privacy')),
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: Runtime.accountSync,
        builder: (context, _) => ListView(
          padding: VeloSpace.insets,
          children: [
            VeloSection(
              title: 'Je gegevens',
              children: [
                ListTile(
                  leading: Icon(
                    Runtime.accountSync.busy
                        ? Icons.sync
                        : Icons.cloud_outlined,
                  ),
                  title: const Text('Accountsynchronisatie'),
                  subtitle: Text(
                    Runtime.accounts.user == null
                        ? 'Meld je aan om je gegevens te synchroniseren.'
                        : Runtime.accountSync.message ??
                              (Runtime.accountSync.lastSuccess == null
                                  ? 'Je wijzigingen worden automatisch bewaard.'
                                  : 'Laatste synchronisatie: ${TimeOfDay.fromDateTime(Runtime.accountSync.lastSuccess!.toLocal()).format(context)}'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('Nu synchroniseren'),
                  enabled:
                      Runtime.accounts.user != null &&
                      !Runtime.accountSync.busy,
                  onTap: () => Runtime.accountSync.run(),
                ),
                ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('Account en bewaarde versies'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const VeloSection(
              title: 'Privacy',
              children: [
                ListTile(
                  leading: Icon(Icons.location_on_outlined),
                  title: Text('Locatie tijdens je rit'),
                  subtitle: Text(
                    'Je GPS-spoor wordt eerst op dit toestel opgeslagen. Je eigen ritten synchroniseren alleen wanneer je bent aangemeld.',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.apps_outlined),
                  title: Text('Apps op je telefoon'),
                  subtitle: Text(
                    'De lijst met geïnstalleerde apps en iconen blijft op je toestel. Je zelf gekozen favorieten horen bij je overdraagbare instellingen.',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.map_outlined),
                  title: Text('Kaartdiensten'),
                  subtitle: Text(
                    'Bij online kaarten ontvangt de kaartprovider het bekeken gebied. Vooraf gedownloade gebieden werken offline.',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.link),
                  title: Text('Verbonden diensten'),
                  subtitle: Text(
                    'Je bepaalt zelf welke gegevens je deelt. Je kunt een verbinding op elk moment verbreken.',
                  ),
                ),
              ],
            ),
            VeloSection(
              title: 'Android-toegang',
              children: [
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Appmachtigingen beheren'),
                  subtitle: const Text('Locatie, Bluetooth en meldingen'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => Geolocator.openAppSettings(),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
