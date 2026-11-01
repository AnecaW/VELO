import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Represents a cycling activity profile (Road, Gravel, MTB, etc.)
/// Stores profile-specific settings that persist across sessions
class ActivityProfile extends Equatable {
  final String id;
  final String name;
  final String type; // Road, Gravel, MTB, Indoor, Commute, Custom
  final IconData icon;
  final Color accentColor;

  // Profile-specific settings
  final bool autoPauseEnabled;
  final double autoPauseSpeedKmh;
  final bool autoLapEnabled;
  final String autoLapType; // distance, time, position
  final double autoLapValue;
  final bool climbProEnabled;
  final bool navigationEnabled;
  final List<String> dataScreenIds; // IDs of configured data screens

  const ActivityProfile({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.accentColor,
    this.autoPauseEnabled = false,
    this.autoPauseSpeedKmh = 2.0,
    this.autoLapEnabled = false,
    this.autoLapType = 'distance',
    this.autoLapValue = 10.0,
    this.climbProEnabled = true,
    this.navigationEnabled = true,
    this.dataScreenIds = const [],
  });

  /// Create a copy with modified fields
  ActivityProfile copyWith({
    String? id,
    String? name,
    String? type,
    IconData? icon,
    Color? accentColor,
    bool? autoPauseEnabled,
    double? autoPauseSpeedKmh,
    bool? autoLapEnabled,
    String? autoLapType,
    double? autoLapValue,
    bool? climbProEnabled,
    bool? navigationEnabled,
    List<String>? dataScreenIds,
  }) {
    return ActivityProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      icon: icon ?? this.icon,
      accentColor: accentColor ?? this.accentColor,
      autoPauseEnabled: autoPauseEnabled ?? this.autoPauseEnabled,
      autoPauseSpeedKmh: autoPauseSpeedKmh ?? this.autoPauseSpeedKmh,
      autoLapEnabled: autoLapEnabled ?? this.autoLapEnabled,
      autoLapType: autoLapType ?? this.autoLapType,
      autoLapValue: autoLapValue ?? this.autoLapValue,
      climbProEnabled: climbProEnabled ?? this.climbProEnabled,
      navigationEnabled: navigationEnabled ?? this.navigationEnabled,
      dataScreenIds: dataScreenIds ?? this.dataScreenIds,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    type,
    icon,
    accentColor,
    autoPauseEnabled,
    autoPauseSpeedKmh,
    autoLapEnabled,
    autoLapType,
    autoLapValue,
    climbProEnabled,
    navigationEnabled,
    dataScreenIds,
  ];
}

/// Factory constructors for common activity profiles
class ActivityProfileFactory {
  static ActivityProfile createRoadProfile() {
    return const ActivityProfile(
      id: 'road_default',
      name: 'Road',
      type: 'Road',
      icon: Icons.two_wheeler,
      accentColor: Color(0xFF1E88E5),
      autoPauseEnabled: true,
      autoPauseSpeedKmh: 3.0,
      autoLapEnabled: false,
      climbProEnabled: true,
      navigationEnabled: true,
    );
  }

  static ActivityProfile createGravelProfile() {
    return const ActivityProfile(
      id: 'gravel_default',
      name: 'Gravel',
      type: 'Gravel',
      icon: Icons.terrain,
      accentColor: Color(0xFFF57C00),
      autoPauseEnabled: true,
      climbProEnabled: true,
      navigationEnabled: true,
    );
  }

  static ActivityProfile createMTBProfile() {
    return const ActivityProfile(
      id: 'mtb_default',
      name: 'MTB',
      type: 'MTB',
      icon: Icons.downhill_skiing,
      accentColor: Color(0xFF7B1FA2),
      autoPauseEnabled: false,
      climbProEnabled: true,
      navigationEnabled: false,
    );
  }

  static ActivityProfile createIndoorProfile() {
    return const ActivityProfile(
      id: 'indoor_default',
      name: 'Indoor',
      type: 'Indoor',
      icon: Icons.home,
      accentColor: Color(0xFF00ACC1),
      autoPauseEnabled: false,
      climbProEnabled: false,
      navigationEnabled: false,
    );
  }

  static ActivityProfile createCommuteProfile() {
    return const ActivityProfile(
      id: 'commute_default',
      name: 'Commute',
      type: 'Commute',
      icon: Icons.directions_bike,
      accentColor: Color(0xFF4CAF50),
      autoPauseEnabled: true,
      climbProEnabled: false,
      navigationEnabled: true,
    );
  }

  static List<ActivityProfile> createDefaults() {
    return [
      ActivityProfileFactory.createRoadProfile(),
      ActivityProfileFactory.createGravelProfile(),
      ActivityProfileFactory.createMTBProfile(),
      ActivityProfileFactory.createIndoorProfile(),
      ActivityProfileFactory.createCommuteProfile(),
    ];
  }
}
