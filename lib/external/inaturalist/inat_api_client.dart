import 'dart:convert';

import 'package:discere/shared/util/constants.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:http/http.dart' as http;

/// Addresses the iNaturalist API: builds its URLs and makes the requests.
///
/// Split from what the app *asks* it for so that the callers above — photos,
/// common names, taxon lookup — are about their subject rather than about
/// URL encoding and HTTP verbs.
class INatApiClient {
  static final _log = Logger.forType(INatApiClient);

  /// Verbose request logging. Debug-only by default; flip locally when an
  /// iNaturalist response needs inspecting.
  static const bool enableDebugLogging = true;

  static const apiHost = 'api.inaturalist.org';

  /// Some endpoints only exist on the old website host, not on the v2 API.
  static const legacyWebHost = 'www.inaturalist.org';

  static const _apiBasePath = '/v2';

  final http.Client _client;

  const INatApiClient({required http.Client client}) : _client = client;

  /// A v2 API URL for [path].
  ///
  /// Uses [Uri.https] only for the parameterless case; anything else is
  /// encoded by hand because the API takes repeated keys (`fields=a&fields=b`)
  /// and `Uri.https` cannot express those.
  Uri uri(
    String path, {
    Map<String, String>? queryParameters,
    Map<String, List<String>>? queryParametersAll,
  }) {
    final encodedPath = '$_apiBasePath$path';
    final hasParameters =
        (queryParameters?.isNotEmpty ?? false) ||
        (queryParametersAll?.isNotEmpty ?? false);
    if (!hasParameters) return Uri.https(apiHost, encodedPath);

    return Uri(
      scheme: 'https',
      host: apiHost,
      path: encodedPath,
      query: _encodeRepeatable({
        for (final entry in (queryParameters ?? const <String, String>{}).entries)
          entry.key: [entry.value],
        ...?queryParametersAll,
      }),
    );
  }

  /// Performs the request.
  ///
  /// With [fields] it goes out as a POST carrying `X-HTTP-Method-Override`:
  /// the v2 API's field selection can exceed what fits in a URL, and this is
  /// the escape hatch it documents for that.
  Future<http.Response> get(Uri uri, {Object? fields}) {
    if (fields == null) {
      return _client.get(uri, headers: {'User-Agent': AppConstants.userAgent});
    }
    return _client.post(
      uri,
      headers: {
        'User-Agent': AppConstants.userAgent,
        'X-HTTP-Method-Override': 'GET',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'fields': fields}),
    );
  }

  /// Whether a failed request is worth attempting again: rate limiting and
  /// server-side errors are, a rejected or malformed request is not.
  static bool isRetryableStatus(int statusCode) =>
      statusCode == 429 || statusCode >= 500;

  static void logDebug(String message) {
    if (enableDebugLogging) _log.debug(message);
  }

  static String _encodeRepeatable(Map<String, List<String>> parameters) => [
    for (final entry in parameters.entries)
      for (final value in entry.value)
        '${Uri.encodeQueryComponent(entry.key)}='
            '${Uri.encodeQueryComponent(value)}',
  ].join('&');
}

/// Splits [items] into runs of at most [size], for endpoints that take a
/// bounded number of ids per request.
List<List<T>> chunked<T>(List<T> items, int size) => [
  for (var index = 0; index < items.length; index += size)
    items.sublist(index, index + size > items.length ? items.length : index + size),
];
