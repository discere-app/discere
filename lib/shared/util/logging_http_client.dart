import 'dart:async';

import 'package:discere/shared/util/logger.dart';
import 'package:http/http.dart' as http;

class LoggingHttpClient extends http.BaseClient {
  static final _log = Logger.forType(LoggingHttpClient);
  final http.Client _inner;
  final String _scope;

  LoggingHttpClient(this._inner, {String scope = 'HTTP'}) : _scope = scope;

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
      return response;
    } catch (error) {
      stopwatch.stop();
      _log.debug(
        '[$_scope] <xx ${request.method} ${request.url} failed after ${stopwatch.elapsedMilliseconds} ms: $error',
      );
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
  }
}
