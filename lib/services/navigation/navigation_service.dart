import 'package:url_launcher/url_launcher.dart';

import 'gpx_route.dart';

/// Requires sustained, accurate deviation, and bounds requests after failures.
class OffRouteDetector {
  DateTime? _since, _lastAttempt;
  bool shouldRecalculate(
    RouteProgress progress,
    double accuracy,
    DateTime now,
  ) {
    if (!accuracy.isFinite || accuracy > 35 || !progress.offRoute) {
      _since = null;
      return false;
    }
    _since ??= now;
    if (now.difference(_since!).inSeconds < 12 ||
        (_lastAttempt != null &&
            now.difference(_lastAttempt!).inSeconds < 60)) {
      return false;
    }
    _lastAttempt = now;
    _since = null;
    return true;
  }

  void reset() => _since = null;
}

class ExternalNavigation {
  static Uri googleMaps(NavPoint destination) =>
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': '${destination.lat},${destination.lon}',
        'travelmode': 'bicycling',
      });
  static Future<void> open(NavPoint destination) async {
    final app = Uri.parse(
      'google.navigation:q=${destination.lat},${destination.lon}&mode=b',
    );
    if (await canLaunchUrl(app) &&
        await launchUrl(app, mode: LaunchMode.externalApplication)) {
      return;
    }
    if (!await launchUrl(
      googleMaps(destination),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('Geen kaartapp of browser beschikbaar.');
    }
  }
}
