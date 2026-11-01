/// Application-wide constants
class AppConstants {
  AppConstants._();

  // App info
  static const String appName = 'Bike Computer';
  static const String appVersion = '1.0.0';

  // Activity profile defaults
  static const List<String> defaultActivityTypes = [
    'Road',
    'Gravel',
    'MTB',
    'Indoor',
    'Commute',
  ];

  // GPS settings
  static const int defaultGpsUpdateRateHz = 1;
  static const double gpsAccuracyThreshold = 30.0; // meters

  // Auto pause settings
  static const double autoPauseSpeedThreshold = 2.0; // km/h

  // Data screen configurations
  static const int maxDataScreens = 8;
  static const int maxFieldsPerScreen = 8;

  // Storage keys
  static const String storageKeyActivityProfiles = 'activity_profiles';
  static const String storageKeyCurrentProfile = 'current_profile';
  static const String storageKeyDataScreens = 'data_screens';
  static const String storageKeySettings = 'settings';

  // Unit systems
  static const String unitSystemMetric = 'metric';
  static const String unitSystemImperial = 'imperial';
}
