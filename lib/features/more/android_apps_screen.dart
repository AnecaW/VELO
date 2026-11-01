import 'package:flutter/material.dart';

import '../../services/android_apps.dart';
import '../../widgets/velo_ui.dart';
import '../../core/runtime.dart';
import 'more_screen.dart';
import '../settings/settings_screen.dart';

class AndroidAppsScreen extends StatefulWidget {
  final AndroidApps? service;
  const AndroidAppsScreen({super.key, this.service});
  @override
  State<AndroidAppsScreen> createState() => _AndroidAppsScreenState();
}

class _AndroidAppsScreenState extends State<AndroidAppsScreen>
    with WidgetsBindingObserver {
  late final service = widget.service ?? AndroidApps();
  List<AndroidApp> apps = [];
  String query = '';
  bool favoritesOnly = false;
  Future<void> _favorite(AndroidApp app) async {
    final next = Runtime.settings
        .value<List<dynamic>>('favoriteApps', [])
        .toList();
    if (next.contains(app.package)) {
      next.remove(app.package);
    } else {
      next.add(app.package);
    }
    await Runtime.settings.set('favoriteApps', next);
    if (mounted) setState(() {});
  }

  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    try {
      final rows = await service.load(refresh: refresh);
      if (mounted) {
        setState(() {
          apps = rows;
          error = null;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Je apps konden niet worden geladen. Probeer opnieuw.';
          loading = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(refresh: true);
  }

  Future<void> _open(AndroidApp app) async {
    try {
      await service.launch(app);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Deze app kan niet worden geopend. Mogelijk is ze verwijderd.',
            ),
          ),
        );
      }
      await _load(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = apps
        .where(
          (a) =>
              a.name.toLowerCase().contains(query.toLowerCase()) &&
              (!favoritesOnly ||
                  Runtime.settings
                      .value<List<dynamic>>('favoriteApps', [])
                      .contains(a.package)),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apps'),
        actions: [
          IconButton(
            tooltip: 'Instellingen',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => _load(refresh: true),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: VeloSpace.insets,
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Zoek op je telefoon',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) => setState(() => query = v),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        children: [
                          Text(
                            'Android-apps',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          TextButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const MoreScreen(),
                              ),
                            ),
                            icon: const Icon(
                              Icons.dashboard_outlined,
                              size: 18,
                            ),
                            label: const Text('VELO-functies'),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilterChip(
                          label: const Text('Favorieten'),
                          selected: favoritesOnly,
                          onSelected: (v) => setState(() => favoritesOnly = v),
                          avatar: const Icon(Icons.star_outline, size: 18),
                        ),
                      ),
                      if (error != null) VeloNotice(error!, error: true),
                      if (error != null)
                        TextButton(
                          onPressed: () => _load(refresh: true),
                          child: const Text('Opnieuw proberen'),
                        ),
                    ],
                  ),
                ),
              ),
              if (loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              if (!loading && filtered.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      favoritesOnly
                          ? 'Nog geen favorieten. Houd een app ingedrukt om ze toe te voegen.'
                          : query.isEmpty
                          ? 'Geen te openen Android-apps gevonden.'
                          : 'Geen apps met deze naam.',
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverLayoutBuilder(
                  builder: (context, c) => SliverGrid.builder(
                    itemCount: filtered.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: (c.crossAxisExtent / 100).floor().clamp(
                        3,
                        8,
                      ),
                      mainAxisExtent:
                          112 +
                          (MediaQuery.textScalerOf(context).scale(12) - 12) * 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemBuilder: (context, i) {
                      final app = filtered[i];
                      return Semantics(
                        button: true,
                        excludeSemantics: true,
                        onTap: () => _open(app),
                        onLongPress: () => _favorite(app),
                        label: app.name,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _open(app),
                          onLongPress: () => _favorite(app),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              children: [
                                app.icon == null
                                    ? const SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: Icon(
                                          Icons.apps_rounded,
                                          size: 36,
                                        ),
                                      )
                                    : Image.memory(
                                        app.icon!,
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.contain,
                                        gaplessPlayback: true,
                                        errorBuilder: (_, e, st) =>
                                            const SizedBox(
                                              width: 48,
                                              height: 48,
                                              child: Icon(Icons.apps_rounded),
                                            ),
                                      ),
                                const SizedBox(height: 8),
                                Text(
                                  app.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
