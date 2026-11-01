import 'package:flutter/material.dart';

/// Stable IDs are stored in ride snapshots; preferences never rewrite history.
enum BikeType {
  road('Racefiets', Icons.speed, 'Ride', 'fastbike'),
  mountain('Mountainbike', Icons.terrain, 'MountainBikeRide', 'mtb'),
  gravel('Gravelbike', Icons.grain, 'GravelRide', 'gravel'),
  electric('Elektrische fiets', Icons.electric_bike, 'EBikeRide', 'trekking'),
  electricMountain(
    'Elektrische mountainbike',
    Icons.bolt,
    'EMountainBikeRide',
    'mtb',
  ),
  city('Stadsfiets', Icons.location_city, 'Ride', 'trekking'),
  trekking('Trekkingfiets', Icons.landscape, 'Ride', 'trekking'),
  other('Andere fiets', Icons.directions_bike, 'Ride', 'trekking');

  const BikeType(this.label, this.icon, this.sportType, this.routingProfile);
  final String label, sportType, routingProfile;
  final IconData icon;
  static BikeType parse(String? value) =>
      values.where((v) => v.name == value).firstOrNull ?? road;
}
