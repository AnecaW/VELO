/// Base exception for the application
abstract class AppException implements Exception {
  final String message;
  final dynamic originalException;
  final StackTrace? stackTrace;

  AppException({
    required this.message,
    this.originalException,
    this.stackTrace,
  });

  @override
  String toString() => message;
}

/// Exceptions for GPS operations
class GPSException extends AppException {
  GPSException({
    required super.message,
    super.originalException,
    super.stackTrace,
  });
}

/// Exceptions for Bluetooth operations
class BluetoothException extends AppException {
  BluetoothException({
    required super.message,
    super.originalException,
    super.stackTrace,
  });
}

/// Exceptions for storage operations
class StorageException extends AppException {
  StorageException({
    required super.message,
    super.originalException,
    super.stackTrace,
  });
}

/// Exceptions for permission operations
class PermissionException extends AppException {
  final String permission;

  PermissionException({
    required super.message,
    required this.permission,
    super.originalException,
    super.stackTrace,
  });
}

/// Exceptions for navigation operations
class NavigationException extends AppException {
  NavigationException({
    required super.message,
    super.originalException,
    super.stackTrace,
  });
}

/// Exceptions for ride operations
class RideException extends AppException {
  RideException({
    required super.message,
    super.originalException,
    super.stackTrace,
  });
}

/// Generic validation exception
class ValidationException extends AppException {
  ValidationException({
    required super.message,
    super.originalException,
    super.stackTrace,
  });
}
