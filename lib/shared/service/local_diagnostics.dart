import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:discere/shared/repository/local_diagnostics_repository.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

class LocalDiagnosticsContext {
  final String category;
  final String? runId;
  final String? subjectType;
  final String? subjectId;
  final Map<String, Object?> details;

  const LocalDiagnosticsContext({
    required this.category,
    required this.runId,
    required this.subjectType,
    required this.subjectId,
    this.details = const <String, Object?>{},
  });
}

class LocalDiagnostics {
  static final _log = Logger.forType(LocalDiagnostics);
  static final LocalDiagnostics instance = LocalDiagnostics();
  static const _contextZoneKey = #local_diagnostics_context;

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
    final bindingType = binding?.runtimeType.toString();
    if (bindingType != null &&
        bindingType.contains('TestWidgetsFlutterBinding')) {
      return false;
    }
    return true;
  }

  Future<T> runScope<T>({
    required String category,
    String? timelineName,
    String? runId,
    String? subjectType,
    String? subjectId,
    Map<String, Object?> details = const <String, Object?>{},
    required Future<T> Function() action,
  }) async {
    if (!isEnabled) return action();

    final timeline = developer.TimelineTask(filterKey: category);
    final args = {
      'category': category,
      if (runId != null) 'runId': runId,
      if (subjectType != null) 'subjectType': subjectType,
      if (subjectId != null) 'subjectId': subjectId,
      ...details,
    };
    timeline.start(timelineName ?? category, arguments: args);

    return runZoned(
      () async {
        try {
          return await action();
        } finally {
          timeline.finish(arguments: args);
        }
      },
      zoneValues: {
        _contextZoneKey: LocalDiagnosticsContext(
          category: category,
          runId: runId,
          subjectType: subjectType,
          subjectId: subjectId,
          details: details,
        ),
      },
    );
  }

  Future<void> recordEvent({
    required String category,
    required String eventType,
    String? runId,
    String? owner,
    String? subjectType,
    String? subjectId,
    int? durationMs,
    String? level,
    String? message,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    if (!isEnabled) return Future<void>.value();
    final context = Zone.current[_contextZoneKey] as LocalDiagnosticsContext?;
    final effectiveCategory = category;
    final mergedDetails = {...?context?.details, ...details};
    developer.log(
      'event=$eventType category=$effectiveCategory subject=${subjectType ?? context?.subjectType ?? "-"}:${subjectId ?? context?.subjectId ?? "-"}',
      name: 'LocalDiagnostics',
    );
    return _enqueue(() async {
      await _repository.insertEvent(
        LocalDiagnosticsEventRecord(
          createdAt: DateTime.now(),
          category: effectiveCategory,
          eventType: eventType,
          runId: runId ?? context?.runId,
          owner: owner,
          subjectType: subjectType ?? context?.subjectType,
          subjectId: subjectId ?? context?.subjectId,
          durationMs: durationMs,
          level: level,
          message: message,
          details: mergedDetails,
        ),
      );
    });
  }

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
  }) {
    if (!isEnabled) return Future<void>.value();
    final context = Zone.current[_contextZoneKey] as LocalDiagnosticsContext?;
    final effectiveCategory = category ?? context?.category ?? 'http';
    final retryable = response != null
        ? _isRetryableStatus(response.statusCode)
        : _isRetryableError(error);
    final normalizedError = _normalizeHttpFailure(
      request: request,
      response: response,
      error: error,
    );
    final mergedDetails = {
      ...?context?.details,
      ...details,
      'retryable': retryable,
      ...normalizedError.details,
    };
    developer.log(
      'http failure category=$effectiveCategory host=${request.url.host} status=${response?.statusCode ?? "-"} error=${error.runtimeType}',
      name: 'LocalDiagnostics',
    );
    return _enqueue(() async {
      await _repository.insertNetworkFailure(
        LocalDiagnosticsNetworkFailureRecord(
          createdAt: DateTime.now(),
          category: effectiveCategory,
          runId: runId ?? context?.runId,
          subjectType: subjectType ?? context?.subjectType,
          subjectId: subjectId ?? context?.subjectId,
          host: request.url.host,
          method: request.method,
          urlPath: _sanitizedPath(request.url),
          statusCode: response?.statusCode,
          exceptionType: normalizedError.exceptionType,
          message: normalizedError.message,
          durationMs: durationMs,
          retryable: retryable,
          details: mergedDetails,
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
        typeName == 'SocketException';
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
