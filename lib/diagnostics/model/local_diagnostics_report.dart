/// What the diagnostics page reads: the recorded HTTP failures, grouped and
/// raw.
///
/// Kept out of the repository file so a page can name the data it renders
/// without importing the class that runs the SQL — the layer rules would
/// otherwise flag every such widget, and rightly so.
library;

class LocalDiagnosticsNetworkFailureRecord {
  final DateTime createdAt;
  final String host;
  final String method;
  final String urlPath;
  final int? statusCode;
  final String? exceptionType;
  final String? message;
  final int? durationMs;
  final bool retryable;
  final Map<String, Object?> details;

  const LocalDiagnosticsNetworkFailureRecord({
    required this.createdAt,
    required this.host,
    required this.method,
    required this.urlPath,
    required this.statusCode,
    required this.exceptionType,
    required this.message,
    required this.durationMs,
    required this.retryable,
    this.details = const <String, Object?>{},
  });
}

class LocalDiagnosticsHostFailureSummary {
  final String host;
  final int failureCount;
  final int retryableFailureCount;
  final DateTime lastFailureAt;

  const LocalDiagnosticsHostFailureSummary({
    required this.host,
    required this.failureCount,
    required this.retryableFailureCount,
    required this.lastFailureAt,
  });
}

class LocalDiagnosticsReport {
  final int totalNetworkFailureCount;
  final List<LocalDiagnosticsHostFailureSummary> hostFailures;
  final List<LocalDiagnosticsNetworkFailureRecord> recentFailures;

  const LocalDiagnosticsReport({
    required this.totalNetworkFailureCount,
    required this.hostFailures,
    required this.recentFailures,
  });
}
