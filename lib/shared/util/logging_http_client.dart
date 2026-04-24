import 'dart:async';

import 'package:discere/shared/service/local_diagnostics.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:http/http.dart' as http;

class LoggingHttpClient extends http.BaseClient {
  static final _log = Logger.forType(LoggingHttpClient);
  final http.Client _inner;
  final String _scope;
  final LocalDiagnostics _diagnostics;

  LoggingHttpClient(
    this._inner, {
    String scope = 'HTTP',
    LocalDiagnostics? diagnostics,
  }) : _scope = scope,
       _diagnostics = diagnostics ?? LocalDiagnostics.instance;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stopwatch = Stopwatch()..start();
    _log.debug('[$_scope] --> ${request.method} ${request.url}');

    try {
      final response = await _inner.send(request);
      stopwatch.stop();
      _log.debug(
        '[$_scope] <-- ${response.statusCode} ${request.method} ${request.url} (${stopwatch.elapsedMilliseconds} ms)',
      );
      if (response.statusCode >= 400) {
        unawaited(
          _diagnostics.recordHttpFailure(
            request: request,
            response: response,
            durationMs: stopwatch.elapsedMilliseconds,
          ),
        );
      }
      return response;
    } catch (error) {
      stopwatch.stop();
      _log.debug(
        '[$_scope] <xx ${request.method} ${request.url} failed after ${stopwatch.elapsedMilliseconds} ms: $error',
      );
      unawaited(
        _diagnostics.recordHttpFailure(
          request: request,
          error: error,
          durationMs: stopwatch.elapsedMilliseconds,
        ),
      );
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
  }
}
