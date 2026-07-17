import 'package:http/http.dart' as http;

/// Port for recording HTTP failures from within `shared` code.
///
/// `shared` is the dependency-free foundation and may not depend on the
/// `diagnostics` module (which sits above it, alongside `external`), so
/// [LoggingHttpClient] — which lives in `shared` — depends on this
/// interface instead of the concrete diagnostics implementation. The
/// concrete `LocalDiagnostics` (in `lib/diagnostics/`) implements it and is
/// wired in by the bootstrap, the same inversion pattern used for the
/// enrichment↔learning ports.
abstract class DiagnosticsSink {
  Future<void> recordHttpFailure({
    String? category,
    String? runId,
    String? subjectType,
    String? subjectId,
    required http.BaseRequest request,
    http.StreamedResponse? response,
    Object? error,
    required int durationMs,
    Map<String, Object?> details = const <String, Object?>{},
  });
}
