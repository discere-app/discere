import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:discere/diagnostics/repository/local_diagnostics_repository.dart';
import 'package:discere/shared/service/diagnostics_sink.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

class LocalDiagnostics implements DiagnosticsSink {
  static final _log = Logger.forType(LocalDiagnostics);

  final LocalDiagnosticsRepository _repository;
  final bool _enabled;
  Future<void> _writeQueue = Future<void>.value();

  LocalDiagnostics({LocalDiagnosticsRepository? repository, bool? enabled})
    : _repository = repository ?? const LocalDiagnosticsRepository(),
      _enabled = enabled ?? _defaultEnabled();

  bool get isEnabled => _enabled;

  static bool _defaultEnabled() {
    if (kReleaseMode) return false;
    final binding = WidgetsBinding.instance;
    final bindingType = binding.runtimeType.toString();
    if (bindingType.contains('TestWidgetsFlutterBinding')) {
      return false;
    }
    return true;
  }

  @override
  Future<void> recordHttpFailure({
    required http.BaseRequest request,
    http.StreamedResponse? response,
    Object? error,
    required int durationMs,
  }) {
    if (!isEnabled) return Future<void>.value();
    final retryable = response != null
        ? _isRetryableStatus(response.statusCode)
        : _isRetryableError(error);
    final normalizedError = _normalizeHttpFailure(
      request: request,
      response: response,
      error: error,
    );
    developer.log(
      'http failure host=${request.url.host} status=${response?.statusCode ?? "-"} error=${error.runtimeType}',
      name: 'LocalDiagnostics',
    );
    return _enqueue(() async {
      await _repository.insertNetworkFailure(
        LocalDiagnosticsNetworkFailureRecord(
          createdAt: DateTime.now(),
          host: request.url.host,
          method: request.method,
          urlPath: _sanitizedPath(request.url),
          statusCode: response?.statusCode,
          exceptionType: normalizedError.exceptionType,
          message: normalizedError.message,
          durationMs: durationMs,
          retryable: retryable,
          details: {...normalizedError.details, 'retryable': retryable},
        ),
      );
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    _writeQueue = _writeQueue
        .catchError((Object error, StackTrace stackTrace) {
          _log.warn('Diagnostics write chain recovered from: $error');
        })
        .then((_) => operation())
        .catchError((Object error, StackTrace stackTrace) {
          _log.warn('Diagnostics write failed: $error');
        });
    return _writeQueue;
  }

  static bool _isRetryableStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 425 ||
        statusCode == 429 ||
        statusCode >= 500;
  }

  static bool _isRetryableError(Object? error) {
    final typeName = error?.runtimeType.toString();
    return error is TimeoutException ||
        error is http.ClientException ||
        typeName == 'SocketException' ||
        typeName == '_ClientSocketException';
  }

  static String _sanitizedPath(Uri uri) {
    return uri.path.isEmpty ? '/' : uri.path;
  }

  static _NormalizedHttpFailure _normalizeHttpFailure({
    required http.BaseRequest request,
    http.StreamedResponse? response,
    Object? error,
  }) {
    if (response != null) {
      final reasonPhrase = _cleanText(response.reasonPhrase);
      return _NormalizedHttpFailure(
        exceptionType: null,
        message: reasonPhrase != null
            ? 'HTTP ${response.statusCode} $reasonPhrase'
            : 'HTTP ${response.statusCode}',
        details: {
          'requestUrl': request.url.toString(),
          'reasonPhrase': reasonPhrase,
        },
      );
    }

    final exceptionType = error?.runtimeType.toString();
    final details = <String, Object?>{'requestUrl': request.url.toString()};

    if (error is SocketException) {
      details['osError'] = _cleanText(error.osError?.message);
      details['socketAddress'] = error.address?.address;
      details['socketPort'] = error.port;
      return _NormalizedHttpFailure(
        exceptionType: exceptionType,
        message: _joinMessageParts([
          'SocketException',
          _cleanText(error.message),
          _cleanText(error.osError?.message),
        ]),
        details: details,
      );
    }

    if (error is TimeoutException) {
      details['timeoutDurationMs'] = error.duration?.inMilliseconds;
      return _NormalizedHttpFailure(
        exceptionType: exceptionType,
        message: _joinMessageParts([
          'TimeoutException',
          _cleanText(error.message),
        ]),
        details: details,
      );
    }

    if (error is http.ClientException) {
      return _NormalizedHttpFailure(
        exceptionType: exceptionType,
        message: _joinMessageParts([
          'ClientException',
          _cleanText(error.message),
          if (error.uri != null) error.uri.toString(),
        ]),
        details: details,
      );
    }

    return _NormalizedHttpFailure(
      exceptionType: exceptionType,
      message: _cleanText(error?.toString()) ?? exceptionType,
      details: details,
    );
  }

  static String? _cleanText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _joinMessageParts(List<String?> values) {
    return values
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join(': ');
  }
}

class _NormalizedHttpFailure {
  final String? exceptionType;
  final String? message;
  final Map<String, Object?> details;

  const _NormalizedHttpFailure({
    required this.exceptionType,
    required this.message,
    required this.details,
  });
}
