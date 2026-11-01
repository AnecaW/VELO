import 'package:flutter/material.dart';

import 'dart:ui';

import 'package:go_router/go_router.dart';
import 'package:bike_computer/features/home/home_screen.dart';
import 'package:bike_computer/features/navigation/navigation_screen.dart';
import 'package:bike_computer/features/ride/ride_screen.dart';
import 'package:bike_computer/features/training/training_screen.dart';
import 'package:bike_computer/features/more/more_screen.dart';
import 'package:bike_computer/features/settings/settings_screen.dart';
import 'package:bike_computer/features/history/history_screen.dart';
import 'package:bike_computer/features/ride/ride_summary_screen.dart';
import 'package:bike_computer/models/ride_session.dart';

class ScaffoldWithNavBar extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const ScaffoldWithNavBar({super.key, required this.navigationShell});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: navigationShell,
    bottomNavigationBar: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .92),
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outline
                    .withValues(alpha: .25),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 72,
              child: Row(
                children: [
                  for (var i = 0; i < 5; i++)
                    Expanded(
                      child: Semantics(
                        selected: navigationShell.currentIndex == i,
                        button: true,
                        child: InkWell(
                          key: ValueKey('tab-$i'),
                          onTap: () => navigationShell.goBranch(i),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: i == 0
                                      ? Theme.of(context).colorScheme.primary
                                      : navigationShell.currentIndex == i
                                      ? Theme.of(context).colorScheme.primary
                                            .withValues(alpha: .14)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  [
                                    Icons.speed,
                                    Icons.map_outlined,
                                    Icons.history_rounded,
                                    Icons.fitness_center,
                                    Icons.grid_view_rounded,
                                  ][i],
                                  size: i == 0 ? 26 : 23,
                                  color: i == 0
                                      ? Colors.black
                                      : navigationShell.currentIndex == i
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurface
                                            .withValues(alpha: .55),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                [
                                  'Fiets',
                                  'Kaart',
                                  'Activiteiten',
                                  'Training',
                                  'Apps',
                                ][i],
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: navigationShell.currentIndex == i
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

final router = GoRouter(
  initialLocation: '/ride',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) =>
          ScaffoldWithNavBar(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/ride', builder: (_, s) => const RideScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/navigation',
              builder: (_, s) => const NavigationScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/history', builder: (_, s) => const HistoryScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/training',
              builder: (_, s) => const TrainingScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/more', builder: (_, s) => const MoreScreen()),
          ],
        ),
      ],
    ),
    GoRoute(path: '/settings', builder: (_, s) => const SettingsScreen()),
    GoRoute(path: '/home', builder: (_, s) => const HomeScreen()),
    GoRoute(
      path: '/ride/summary',
      builder: (_, s) => s.extra is RideSession
          ? RideSummaryScreen(session: s.extra! as RideSession)
          : const Scaffold(
              body: Center(child: Text('Geen opgeslagen rit geselecteerd')),
            ),
    ),
  ],
);
