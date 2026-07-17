import 'dart:async';

import 'package:discere/shared/service/diagnostics_sink.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:http/http.dart' as http;

class LoggingHttpClient extends http.BaseClient {
  static final _log = Logger.forType(LoggingHttpClient);
  final http.Client _inner;
  final String _scope;
  final DiagnosticsSink _diagnostics;
  final HostCooldownTracker _hostCooldownTracker;

  LoggingHttpClient(
    this._inner, {
    String scope = 'HTTP',
    required DiagnosticsSink diagnostics,
    required HostCooldownTracker hostCooldownTracker,
  }) : _scope = scope,
       _diagnostics = diagnostics,
       _hostCooldownTracker = hostCooldownTracker;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await _hostCooldownTracker.waitIfCoolingDown(request.url.host);
    final stopwatch = Stopwatch()..start();
    _log.debug('[$_scope] --> ${request.method} ${request.url}');

    try {
      final response = await _inner.send(request);
      stopwatch.stop();
      _log.debug(
        '[$_scope] <-- ${response.statusCode} ${request.method} ${request.url} (${stopwatch.elapsedMilliseconds} ms)',
      );
      if (response.statusCode >= 400) {
        _hostCooldownTracker.recordHttpResponse(
          request.url.host,
          response.statusCode,
        );
        unawaited(
          _diagnostics.recordHttpFailure(
            request: request,
            response: response,
            durationMs: stopwatch.elapsedMilliseconds,
          ),
        );
      } else {
        _hostCooldownTracker.clearHost(request.url.host);
      }
      return response;
    } catch (error) {
      stopwatch.stop();
      _hostCooldownTracker.recordHttpError(request.url.host, error);
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
