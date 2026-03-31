/// Base class for all application-specific exceptions.
/// Allows for consistent error handling and UI feedback.
class AppException implements Exception {
  final String message;
  final dynamic originalError;

  AppException(this.message, {this.originalError});

  @override
  String toString() => message;
}

/// Thrown when a network request fails (e.g., no internet, timeout).
class NetworkException extends AppException {
  NetworkException(super.message, {super.originalError});
}

/// Thrown when the server returns an error response (e.g., 404, 500).
class ServerException extends AppException {
  final int? statusCode;
  ServerException(super.message, {this.statusCode, super.originalError});
}

/// Thrown when data received from a remote source is invalid or cannot be parsed.
class DataFormatException extends AppException {
  DataFormatException(super.message, {super.originalError});
}
